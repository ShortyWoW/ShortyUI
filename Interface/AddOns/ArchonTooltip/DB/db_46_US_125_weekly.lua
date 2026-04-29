local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Paladin-Holy','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','DemonHunter-Devourer','Paladin-Protection','Evoker-Augmentation','Unknown-Unknown','Priest-Holy','Hunter-Survival','Mage-Frost','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Rogue-Subtlety','Warrior-Fury','Evoker-Preservation','Warrior-Arms','Priest-Shadow','Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','DeathKnight-Frost','Warrior-Protection','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','Paladin-Retribution','Mage-Arcane','Druid-Guardian','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelas:BAACLgAFFH8HAAIBAAQJ9CGkBwBYAQABAAQJ9CGkBwBYAQAuAAQKfxUAAgEACAk+IzcMALkCAAEACAk+IzcMALkCAAEuAAUUBQkJAAIA6RcA.Abemonkey:BAABLgAFFH8JAAICAAUJ6Rf0AwCtAQACAAUJ6Rf0AwCtAQAAAA==.',
Ac='Actaeus:BAABLgAECn8XAAMDAAcJ+ht1LAABAgADAAYJQxx1LAABAgAEAAQJMRQyWADlAAAAAA==.',
Ad='Addelana:BAABLgAECn8VAAIFAAgJjxL2DQBfAQAFAAgJjxL2DQBfAQAAAA==.Adelyda:BAAALgAECgQJCAAAAA==.Adrasta:BAAALgAECgYJCAAAAA==.',
Ae='Aedrius:BAAALgAECgEJAQAAAA==.Aelador:BAAALgADCgMJBAAAAA==.Aelathe:BAAALgAECgEJAQAAAA==.Aerys:BAAALgAECgEJAQAAAA==.',
Af='Afewbeerz:BAAALgADCgMJAwAAAA==.Africandrake:BAAALgADCgYJBgAAAA==.',
Ah='Ahnkori:BAAALgAECgIJAgAAAA==.',
Ai='Aifik:BAAALgAECgEJAQAAAA==.',
Ak='Akey:BAABLgAECn8bAAIDAAcJqgxrFwBAAQADAAcJqgxrFwBAAQAAAA==.Akiller:BAAALgAECgMJBQAAAA==.',
Al='Alamal:BAAALgAECgEJAQAAAA==.Alamwah:BAACLgAFFH8GAAIGAAMJ5xUzEwCnAAAGAAMJ5xUzEwCnAAAuAAQKfx0AAgYABwmMHAguAEQCAAYABwmMHAguAEQCAAAA.Alanaz:BAAALgAECgcJCwAAAA==.Alaroo:BAAALgAECgYJBwAAAA==.Aleine:BAABLgAECn8kAAIHAAgJEg/eFACAAQAHAAgJEg/eFACAAQAAAA==.Aleio:BAAALgAECgIJAgAAAA==.Alessi:BAAALgAECgEJAQAAAA==.Alexrose:BAAALgADCgcJBwAAAA==.Alliete:BAAALgAECgEJAQABLgAECggJFQAIACEJAA==.Alliyah:BAAALgAECgEJAgABLgAECgMJBgAJAAAAAA==.Aloine:BAABLgAECn8YAAIKAAcJmgdCEADrAAAKAAcJmgdCEADrAAAAAA==.Alphonze:BAAALgAECgIJAgAAAA==.Alynne:BAAALgADCgcJBwAAAA==.',
Am='Amelior:BAAALgADCgIJAgAAAA==.Amogus:BAAALgAECgYJDAAAAA==.Amorallan:BAAALgAECgQJBAAAAA==.Ampuzzible:BAABLgAECn8mAAIKAAgJ5RkIAwAqAgAKAAgJ5RkIAwAqAgAAAA==.',
An='Andju:BAAALgADCgMJAwAAAA==.Anhedonias:BAAALgAECgcJAQAAAA==.Animism:BAAALgADCgUJBQAAAA==.Anivar:BAAALgADCgcJBwAAAA==.Anyá:BAABLgAECn8XAAILAAYJowcNCgD8AAALAAYJowcNCgD8AAAAAA==.',
Ar='Arbitera:BAABLgAECn8WAAICAAgJ3h7CFwADAgACAAgJ3h7CFwADAgAAAA==.Arcaneth:BAAALgADCggJCAAAAA==.Arcette:BAAALgADCgkJHQAAAA==.Archmystique:BAABLgAECn8eAAIMAAcJpxXnfgDTAQAMAAcJpxXnfgDTAQAAAA==.Arcthane:BAAALgADCgQJBAABLgADCgkJHQAJAAAAAA==.Arkona:BAAALgAECgYJDwAAAA==.Arkzart:BAAALgAECgQJBAAAAA==.Arrogant:BAAALgAECgEJAgAAAA==.',
As='Asanath:BAAALgADCgkJDwAAAA==.Ashley:BAABLgAECn8dAAIDAAgJAx7SGgBmAgADAAgJAx7SGgBmAgAAAA==.Ashryveris:BAAALgAECgYJEQAAAA==.Asmonjoel:BAAALgAECgMJBgAAAA==.Assumi:BAAALgAECgUJCQAAAA==.',
At='Ataturk:BAAALgAECgQJCQAAAA==.Athenis:BAAALgAECgcJDgAAAA==.Atka:BAAALgADCgcJBwAAAA==.',
Au='Audree:BAAALgADCgEJAQAAAA==.Augiediaz:BAAALgAECgcJBwAAAA==.Auraine:BAAALgAECgYJBwAAAA==.Aurelionn:BAAALgAECgEJAgAAAA==.',
Av='Avadacadavra:BAAALgADCgUJBwAAAA==.',
Ax='Axonpredator:BAAALgADCgEJAQAAAA==.',
Az='Azamat:BAAALgAECgYJBwAAAA==.Azazêll:BAAALgAECgYJEgAAAA==.Azidian:BAAALgADCgEJAQAAAA==.Azmodais:BAAALgAECgIJAgAAAA==.Azuredemonx:BAABLgAECn8YAAIGAAYJtxWvZwBrAQAGAAYJtxWvZwBrAQAAAA==.Azurgosa:BAAALgADCgUJBQAAAA==.',
Ba='Baagul:BAAALgADCggJDQAAAA==.Badheals:BAABLgAECn8eAAQNAAgJexbWKAAQAgANAAgJexbWKAAQAgAOAAIJXweBCgByAAAPAAMJLAboGgBmAAAAAA==.Balfin:BAAALgADCggJCAAAAA==.Balid:BAAALgADCgIJAwAAAA==.Banan:BAAALgAECgMJAwAAAA==.Bazaseal:BAAALgAECgQJBAAAAA==.',
Bb='Bbqporkbuns:BAABLgAECn8cAAIQAAkJABmzAwDwAgAQAAkJABmzAwDwAgAAAA==.',
Be='Beauranged:BAAALgAECgIJAgAAAA==.Bece:BAAALgADCgcJDgAAAA==.Beefcakes:BAAALgADCgEJAQAAAA==.Beenafflictn:BAAALgADCgEJAQAAAA==.Beerpong:BAABLgAECn8YAAMRAAYJtBBvPAAqAQARAAYJfw1vPAAqAQASAAYJ3Ar0TwAEAQABLgAECggJCAAJAAAAAA==.Bellanoth:BAAALgAECgcJCwAAAA==.Belledormi:BAABLgAECn8kAAMIAAcJmQr8DQALAQAIAAcJmQr8DQALAQATAAEJ5QFJRQAhAAAAAA==.Bellfurion:BAAALgAECgQJCgAAAA==.Belltree:BAAALgADCgIJAgAAAA==.Bendyendy:BAAALgADCgYJBwAAAA==.',
Bf='Bfev:BAABLgAECn8fAAIUAAgJJR1sAQBVAgAUAAgJJR1sAQBVAgAAAA==.',
Bh='Bhad:BAAALgADCgMJAwAAAA==.',
Bi='Bid:BAABLgAECn8YAAIDAAYJwxrzPwCvAQADAAYJwxrzPwCvAQAAAA==.Bierfiendx:BAAALgAECgEJAQAAAA==.Bify:BAAALgADCgYJCAAAAA==.Bigalo:BAABLgAECn8YAAILAAYJbRQfBwBKAQALAAYJbRQfBwBKAQAAAA==.Bigcogg:BAAALgAECgQJBAAAAA==.Bigdikbusta:BAAALgAECgYJDwAAAA==.Biggesthighz:BAAALgAECggJDwAAAA==.Bigjer:BAACLgAFFH8GAAIVAAMJDRRxBgD7AAAVAAMJDRRxBgD7AAAuAAQKfxcAAhUACAmNHn0SALwCABUACAmNHn0SALwCAAAA.Bird:BAABLgAECn8YAAMIAAgJNCHnDQCXAgAIAAgJNCHnDQCXAgAWAAUJawy0LQAFAQAAAA==.Bisifix:BAAALgADCgEJAQAAAA==.',
Bl='Blaisy:BAABLgAECn8ZAAIKAAcJDhRZKwCbAQAKAAcJDhRZKwCbAQAAAA==.Blakdynamite:BAAALgADCgIJAgAAAA==.Blayx:BAAALgADCgQJBAABLgAECgYJGAAMAMQjAA==.Blerdsterm:BAABLgAECn8kAAMXAAgJxR9ACQAaAgAVAAcJ8R9UIQBJAgAXAAYJ3B1ACQAaAgAAAA==.Blitzz:BAAALgADCgcJDQAAAA==.',
Bo='Bofà:BAAALgAECgkJBwAAAA==.Boogeyman:BAAALgAECgYJCQAAAA==.Boohbooh:BAAALgADCgUJBQAAAA==.Borgnine:BAAALgAECggJEgAAAA==.',
Br='Brannie:BAABLgAECn8XAAIYAAcJWwWLDgANAQAYAAcJWwWLDgANAQAAAA==.Brenine:BAAALgAECgQJDAAAAA==.Brila:BAAALgAECgkJBwAAAA==.Britneyfears:BAAALgAECgUJBQABLgAECgkJBgAJAAAAAA==.Brodess:BAACLgAFFH8FAAIZAAIJbCGlEgDGAAAZAAIJbCGlEgDGAAAuAAQKfxsAAhkACAmhJCAGADEDABkACAmhJCAGADEDAAAA.Brody:BAABLgAECn8kAAIGAAgJShmICADqAQAGAAgJShmICADqAQAAAA==.Bromorc:BAAALgADCgUJEwAAAA==.Brox:BAAALgAECgMJBgAAAA==.',
Bs='Bse:BAAALgADCgYJBgAAAA==.',
Bu='Bubbleo:BAAALgAECgEJAgAAAA==.Budholy:BAAALgAECgEJAQAAAA==.Buggyhealz:BAACLgAFFH8MAAINAAQJDhtiAwBmAQANAAQJDhtiAwBmAQAuAAQKfyQAAg0ACAnKJWkFADcDAA0ACAnKJWkFADcDAAAA.Bulimio:BAAALgADCgkJHAAAAA==.Bungeye:BAAALgAECgEJAQAAAA==.Bunzbunnie:BAAALgAECgIJAwAAAA==.Bunzbunny:BAAALgADCggJCgAAAA==.Buratt:BAAALgADCgUJEwAAAA==.Burtmonklin:BAABLgAECn8UAAISAAgJTCKtBwAKAwASAAgJTCKtBwAKAwAAAA==.Busdriver:BAACLgAFFH8GAAIaAAMJ3RTzEADtAAAaAAMJ3RTzEADtAAAuAAQKfxgAAhoACAk9HLkzAGgCABoACAk9HLkzAGgCAAAA.Busterr:BAAALgAECgQJCwAAAA==.',
Ca='Caleroice:BAAALgAECgcJCAAAAA==.Capacitør:BAABLgAECn8XAAIZAAYJ7R+yHwASAgAZAAYJ7R+yHwASAgAAAA==.Cardib:BAABLgAECn8eAAQbAAcJyh1hGgB6AQAbAAUJPBphGgB6AQAcAAYJ4RzSFgBZAQAdAAEJAAAoIABxAAAAAA==.Cartier:BAAALgADCgYJBgAAAA==.Cattabloom:BAAALgAECgEJAQAAAA==.Cattazap:BAABLgAECn8gAAMFAAgJZyNABAAwAwAFAAgJZyNABAAwAwAZAAMJvAvweABfAAAAAA==.',
Ce='Ceefu:BAAALgAFFAQJBAABLgAFFAUJCwAFAC0dAA==.Celtic:BAAALgAECgcJAQAAAA==.Cerran:BAAALgAECgEJAQAAAA==.',
Ch='Chakrakhan:BAAALgAECgcJBwAAAA==.Char:BAAALgAECgQJBwAAAA==.Chase:BAABLgAECn8bAAIXAAcJRx3cBgBXAgAXAAcJRx3cBgBXAgAAAA==.Chopzuey:BAAALgADCgYJCAAAAA==.Chugtiki:BAABLgAECn8dAAMFAAkJXhc4FQBrAgAFAAkJXhc4FQBrAgAZAAUJSRD4VgDpAAAAAA==.',
Ci='Cinderaz:BAAALgADCgUJEwAAAA==.Ciyus:BAAALgAECgQJBQAAAA==.',
Cl='Clann:BAAALgAECgUJCQAAAA==.Clarissahh:BAAALgAECgEJAgAAAA==.',
Co='Coolrunnins:BAAALgAECgcJEAAAAA==.Coolwhip:BAAALgAECgMJBwAAAA==.Coquin:BAAALgADCgEJAwAAAA==.Coquina:BAAALgAECgMJBgAAAA==.Cordeilia:BAACLgAFFH8JAAIKAAIJUgrhDgCHAAAKAAIJUgrhDgCHAAAuAAQKfygAAgoACAmxIBoGAO4CAAoACAmxIBoGAO4CAAAA.Cosmi:BAAALgAECgYJDwAAAQ==.Costiigan:BAAALgAECgMJBgAAAA==.',
Cr='Criznara:BAAALgAECgcJAgAAAA==.Crowlie:BAAALgAECgkJAgAAAA==.Cruxxi:BAABLgAECn8cAAMcAAgJBx4uJACDAgAcAAgJgB0uJACDAgAbAAQJWBxCJAA4AQAAAA==.',
Cu='Curthill:BAAALgAECgMJBAAAAA==.',
Cx='Cxaxukluth:BAAALgAECgYJDAABLgAECgYJDwAJAAAAAQ==.',
Cy='Cyberdots:BAAALgAECgYJBQAAAA==.Cyenthea:BAAALgAECgcJDwABLgAFFAYJFgAGAO8hAA==.Cygeance:BAAALgADCgYJCQAAAA==.Cyklar:BAAALgADCgUJEAAAAA==.Cyphren:BAAALgAECgYJDwAAAA==.Cyrias:BAAALgADCgUJBQAAAA==.',
Da='Dacaille:BAAALgAECgUJBwAAAA==.Daddysouls:BAAALgAECgcJBwAAAA==.Dadingding:BAAALgAECgcJEgAAAA==.Daqueta:BAAALgAECgYJCQAAAA==.Daquetapl:BAAALgAECgIJAgAAAA==.Darkniggura:BAAALgAECgcJEgAAAA==.Darknstormy:BAAALgAECgUJCgAAAA==.Darkpal:BAAALgAFFAIJBAAAAA==.Darthbane:BAAALgAECgQJBAAAAA==.Dazer:BAAALgADCgYJBQAAAA==.Dazgrim:BAAALgAECgQJAwABLgAECgYJDQAJAAAAAA==.Dazrawr:BAAALgADCgEJAQABLgAECgYJDQAJAAAAAA==.',
De='Deadlobster:BAAALgADCgcJBwAAAA==.Deadnick:BAAALgAECgMJAgAAAA==.Deathax:BAAALgADCggJDwAAAA==.Deathicus:BAAALgAECgcJEgAAAA==.Decapitation:BAACLgAFFH8FAAIDAAMJKRJyCwAGAQADAAMJKRJyCwAGAQAuAAQKfx4AAgMABwmIJFwCAIICAAMABwmIJFwCAIICAAAA.Deify:BAAALgAECgYJEwAAAA==.Deliaz:BAAALgADCgUJEwAAAA==.Deltaz:BAAALgADCgEJAQAAAA==.Demønknight:BAAALgADCgkJCQAAAA==.Derek:BAAALgADCgIJAgAAAA==.Devoidh:BAABLgAECn8nAAIeAAgJ1x+SAgDMAgAeAAgJ1x+SAgDMAgAAAA==.',
Di='Dinadan:BAAALgAECgMJAwABLgAECgYJGAAeAMcQAA==.Dindu:BAAALgAECgEJAQAAAA==.Dirge:BAAALgADCgcJFQAAAA==.Dirtybob:BAAALgADCgkJDgAAAA==.Disastros:BAAALgAECgQJBgAAAA==.Divinebeef:BAAALgAECgEJAgAAAA==.',
Dj='Djapana:BAAALgAECgYJEwAAAA==.Djavolo:BAAALgAECgIJAgAAAA==.',
Dn='Dnomm:BAAALgADCgUJEwAAAA==.',
Do='Dodjy:BAAALgAECgQJCgAAAA==.Donussy:BAAALgADCgMJAwAAAA==.Dopeyplane:BAAALgAECgIJAgAAAA==.Dowob:BAAALgAECgMJBQABLgAECgYJCwAJAAAAAA==.',
Dr='Dracheal:BAAALgAECgEJAQAAAA==.Dracknstoob:BAABLgAECn8YAAIWAAYJ9RKxBQBHAQAWAAYJ9RKxBQBHAQAAAA==.Dragondaddy:BAAALgADCgUJBQAAAA==.Dragonfyre:BAAALgADCgEJAQAAAA==.Dragongirlqt:BAAALgADCggJDwABLgAECggJFgAHANgeAA==.Dreaddlord:BAAALgAECgEJAQAAAA==.Dreadiedude:BAABLgAECn8bAAIPAAcJ9hJZCQBaAQAPAAcJ9hJZCQBaAQAAAA==.Drowlie:BAAALgADCgMJBAABLgAECgUJCgAJAAAAAA==.',
Dt='Dtree:BAAALgAECgIJBgAAAA==.',
Du='Duardin:BAAALgAECgIJAgAAAA==.Dureth:BAAALgAECgIJAgAAAA==.Durrin:BAAALgADCgcJCQAAAA==.Dutchman:BAAALgAECgQJDQAAAA==.',
Dw='Dwaka:BAECLgAFFH8ZAAMTAAYJqB+GAADiAQAIAAYJYB2bAwDmAQATAAUJ9xyGAADiAQAuAAQKfxUAAxMACAkEIYIHAHMCABMABgnEJYIHAHMCAAgABgnzGxEYABICAAEuAAUUBgkZABMAFCQA.',
['Dë']='Dëathvader:BAAALgADCgYJCwAAAA==.',
['Dî']='Dîddler:BAABLgAECn8jAAMSAAgJkBGEKADDAQASAAgJGRGEKADDAQARAAUJUQy0EQC6AAAAAA==.',
['Dø']='Døden:BAABLgAECn8WAAIfAAcJoBcmAQDIAQAfAAcJoBcmAQDIAQAAAA==.',
Eb='Ebonflow:BAAALgADCgQJBAAAAA==.',
Ed='Edgestreak:BAAALgAECgEJAQAAAA==.',
Ei='Eio:BAAALgAECgEJAQAAAA==.',
El='Eleice:BAAALgADCgcJCQAAAA==.Elele:BAAALgAECgQJCgAAAA==.Eleshock:BAACLgAFFH8HAAIFAAMJqxebDgD0AAAFAAMJqxebDgD0AAAuAAQKfxYAAgUACAnTHbgPAJoCAAUACAnTHbgPAJoCAAAA.Elizan:BAAALgAECgQJBAAAAA==.Ellell:BAAALgAECgEJAQAAAA==.Ellieb:BAABLgAECn8WAAIPAAgJ/BQOLACiAQAPAAgJ/BQOLACiAQAAAA==.Ellinah:BAAALgAECgEJAgAAAA==.Elshaddai:BAAALgAECgQJBgAAAA==.',
Em='Emsulquiorra:BAAALgAECgYJDgAAAA==.',
En='Endersfault:BAABLgAECn8bAAIgAAgJqCJpAQBAAgAgAAgJqCJpAQBAAgAAAA==.Englaived:BAAALgAECgUJEgAAAA==.Enmebaragesi:BAAALgAECggJDgAAAA==.Enve:BAABLgAECn8WAAMGAAgJZgqYJQDoAAAGAAcJrweYJQDoAAAhAAUJqwv+SADOAAABLgAECggJDAAJAAAAAA==.',
Ep='Epicdemoness:BAAALgAECgEJAQAAAA==.',
Er='Eremano:BAAALgAECgQJBgAAAA==.',
Eu='Euphea:BAAALgAECgMJBAAAAA==.Euustace:BAAALgADCgkJCwAAAA==.',
Ev='Evokunt:BAAALgADCgEJAQAAAA==.',
Ex='Extintion:BAABLgAECn8eAAIaAAgJ0RGsDAC7AQAaAAgJ0RGsDAC7AQAAAA==.Extratusks:BAAALgAECgEJAQAAAA==.',
Fa='Fabe:BAEBLgAECn8YAAILAAYJ/B7LDAD+AQALAAYJ/B7LDAD+AQAAAA==.Falion:BAACLgAFFH8JAAIKAAQJpxnYAwBQAQAKAAQJpxnYAwBQAQAuAAQKfyoAAwoACAkSJKQAAO0CAAoACAkSJKQAAO0CACIAAQnnBj5YADEAAAAA.Fanks:BAAALgADCgYJDAABLgAECggJDAAJAAAAAA==.Fanny:BAAALgADCgEJAQAAAA==.Farkq:BAAALgADCgUJBQAAAA==.Farseer:BAABLgAECn8UAAIZAAcJER2cLAC0AQAZAAcJER2cLAC0AQAAAA==.Fatpandah:BAAALgAECgQJBgAAAA==.Fatrider:BAAALgAECgYJCwABLgAECgkJGAAjAMgIAA==.',
Fe='Fefetux:BAAALgADCgcJBwAAAA==.Felburn:BAAALgAECgEJAwAAAA==.Felicia:BAABLgAECn8WAAIhAAcJySG8CgC1AgAhAAcJySG8CgC1AgAAAA==.Fellordkiki:BAAALgAECggJBwAAAA==.Fenrig:BAEBLgAECn8YAAIgAAYJKhAvIQA1AQAgAAYJKhAvIQA1AQAAAA==.Ferrante:BAABLgAECn8nAAIaAAgJJg/eFgBbAQAaAAgJJg/eFgBbAQAAAA==.',
Fi='Figwigs:BAAALgAECgUJCgAAAA==.Filthymaje:BAAALgAECgIJAQAAAA==.Filthypally:BAABLgAECn8kAAIkAAkJOCRDBACJAwAkAAkJOCRDBACJAwAAAA==.Fishetbek:BAAALgAECgQJBAAAAA==.Fishingbot:BAAALgADCgEJAQAAAA==.Fister:BAAALgADCgIJAgABLgAECgQJBAAJAAAAAA==.Fivëam:BAABLgAECn8YAAIlAAcJ0CBkAAAhAgAlAAcJ0CBkAAAhAgAAAA==.',
Fl='Flashheart:BAAALgAECgYJCwAAAA==.Fletchers:BAAALgAECgYJDQAAAA==.',
Fo='Foodoom:BAAALgAECgYJBgAAAA==.',
Fr='Fraerel:BAAALgAECgEJAQAAAA==.Freezefauker:BAAALgAECgYJEgAAAA==.Fridge:BAABLgAECn8XAAIMAAYJGSEeEgCxAQAMAAYJGSEeEgCxAQAAAA==.Frobrew:BAAALgADCgIJAQAAAA==.Frostsmash:BAABLgAECn8VAAMfAAgJyB7xAQC9AgAfAAgJyB7xAQC9AgAjAAEJ5ALvTwAVAAAAAA==.Frostxfury:BAABLgAECn8UAAIaAAYJtB2BUgD6AQAaAAYJtB2BUgD6AQAAAA==.Frostybunz:BAAALgADCgcJDgAAAA==.Frostyshiver:BAAALgAECgYJEwAAAA==.Frósty:BAAALgADCgEJAQAAAA==.Frøstynips:BAACLgAFFH8hAAIaAAUJdBnOBQCmAQAaAAUJdBnOBQCmAQAuAAQKf0QAAxoACAkbJkoHAGcDABoACAkbJkoHAGcDAB8ABgm6IgAAAAAAAAAA.',
Fu='Funkymunky:BAAALgAECgMJAgAAAA==.Furrbulous:BAAALgADCgIJAgAAAA==.Furysgrip:BAABLgAECn8dAAIjAAgJdhEhBgBHAQAjAAgJdhEhBgBHAQAAAA==.',
Fy='Fyre:BAAALgADCgcJCwAAAA==.',
['Fí']='Fírnen:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúnk:BAABLgAECn8YAAMDAAcJHxdBDwCIAQADAAcJHxdBDwCIAQAEAAEJqQL9lQAjAAAAAA==.',
Ga='Gaara:BAAALgADCgYJCAAAAA==.Garaktou:BAAALgADCgEJAQAAAA==.Garius:BAABLgAECn8bAAIkAAkJUh5ABABeAgAkAAkJUh5ABABeAgAAAA==.Gartah:BAAALgADCgIJAgABLgAECgQJBAAJAAAAAA==.Garthception:BAAALgAECgUJBQAAAA==.',
Ge='Gentlegiantt:BAABLgAECn8iAAMPAAgJzhjIBADNAQAPAAgJzhjIBADNAQAmAAEJAABcMAA0AAAAAA==.Gentlemonstr:BAAALgAECgYJBgAAAA==.',
Gh='Ghood:BAAALgADCgMJAwAAAA==.',
Gi='Gigit:BAAALgAECgYJEwAAAA==.Giji:BAABLgAECn8WAAIZAAcJWhOWCwBDAQAZAAcJWhOWCwBDAQAAAA==.Gingersnapss:BAAALgAECgYJEgAAAA==.Girlsdayoni:BAAALgADCgcJBwAAAA==.',
Gl='Glizzyblasta:BAAALgADCgcJBwAAAA==.',
Gn='Gnimble:BAABLgAECn8UAAICAAcJIBrFBwCDAQACAAcJIBrFBwCDAQAAAA==.Gnuh:BAAALgADCgMJAwAAAA==.',
Go='Gohan:BAABLgAECn8SAAIDAAYJ1x9sUgBxAQADAAYJ1x9sUgBxAQAAAA==.Goku:BAAALgAECgMJBgABLgAECgYJEgADANcfAA==.Gommo:BAAALgAFFAIJAgAAAA==.Gooblento:BAABLgAECn8UAAIkAAcJbw9RkABbAQAkAAcJbw9RkABbAQAAAA==.Gorbad:BAAALgAECggJDAAAAA==.',
Gr='Grahamington:BAAALgAECgQJBwAAAA==.Grandmaster:BAAALgAECgcJDgAAAA==.Grapes:BAAALgAECgYJDAAAAA==.Grayfang:BAAALgADCgYJAQAAAA==.Greatranger:BAAALgAECgMJAwAAAA==.Grimmic:BAAALgADCgIJAgAAAA==.Groovywar:BAAALgADCggJCwAAAA==.Groundizzle:BAABLgAECn8WAAIKAAgJIRL5HAD2AQAKAAgJIRL5HAD2AQAAAA==.',
Gu='Guineamon:BAAALgAECgcJEQAAAA==.',
Gw='Gwwalker:BAAALgAECgcJCgAAAA==.',
Gz='Gzul:BAAALgAECgEJAgAAAA==.',
['Gô']='Gôof:BAAALgADCggJCQAAAA==.',
Ha='Haerinm:BAAALgAECgcJDQAAAA==.Hammel:BAAALgAECgkJCgAAAA==.Hanzxo:BAAALgAECgYJBwAAAA==.Harry:BAABLgAECn8eAAIMAAgJ2R4iMACyAgAMAAgJ2R4iMACyAgAAAA==.Harryrox:BAAALgADCgYJBgAAAA==.Haruk:BAABLgAECn8jAAIBAAgJdh57AwBLAgABAAgJdh57AwBLAgAAAA==.Hatememore:BAAALgAECgEJAgAAAA==.Hazchum:BAAALgADCgQJAgAAAA==.',
He='Healsdead:BAAALgADCgEJAQAAAA==.Heatfist:BAABLgAECn8fAAIlAAgJcg64BQDMAQAlAAgJcg64BQDMAQAAAA==.Hellhost:BAABLgAECn8XAAMfAAcJpBT9BgCbAQAfAAYJOxj9BgCbAQAaAAIJOgPRRwBQAAAAAA==.Hertfor:BAAALgAECgEJAQAAAA==.Heåls:BAABLgAECn8VAAIBAAcJ9hpXHgAkAgABAAcJ9hpXHgAkAgAAAA==.',
Hi='Hisoka:BAAALgAECgQJCgABLgAECgUJCwAJAAAAAA==.',
Ho='Hoboface:BAAALgAECgEJAQAAAA==.Hoelishock:BAAALgAECgcJEAAAAA==.Hollynova:BAABLgAECn8VAAIiAAYJpxWECABZAQAiAAYJpxWECABZAQABLgAECggJIAAIAL4LAA==.Holyreimer:BAAALgADCgcJAwAAAA==.Honeydew:BAACLgAFFH8MAAICAAQJwRmaAwBMAQACAAQJwRmaAwBMAQAuAAQKfx8AAgIACQnmHAUGAAADAAIACQnmHAUGAAADAAAA.Hotteemie:BAAALgADCgcJDAAAAA==.',
Hr='Hrkz:BAAALgAECgIJAwABLgAECgYJCAAJAAAAAA==.',
Hy='Hydrastrider:BAAALgADCgEJAQAAAA==.Hydraxius:BAAALgADCgcJDwAAAA==.Hylingaar:BAAALgADCgQJBgABLgADCgYJBgAJAAAAAA==.Hyoinmaru:BAAALgADCgEJAQAAAA==.',
Ia='Iamokuz:BAAALgADCgEJAQAAAA==.',
Ic='Icevoker:BAECLgAFFH8IAAITAAMJkReyAAAdAQATAAMJkReyAAAdAQAuAAQKfzsABBMACQljH8ECAP8CABMACAkWIMECAP8CAAgAAQmAGgYdAFIAABYAAQlNA+VKACwAAAAA.Iceyq:BAAALgAECgQJBwAAAA==.',
If='Ifloat:BAAALgAECgYJBgABLgAECgcJDQAJAAAAAA==.',
Ig='Igni:BAAALgAECgcJEQAAAA==.',
Ii='Iilliidann:BAAALgADCgEJAQAAAA==.',
Il='Ilioa:BAAALgADCggJGwAAAA==.',
Im='Immortus:BAAALgADCgUJBQABLgAECgcJAgAJAAAAAA==.Imsteve:BAAALgAECgQJCwAAAA==.Imugi:BAABLgAECn8VAAIIAAgJIQmIKQByAQAIAAgJIQmIKQByAQAAAA==.',
In='Innarial:BAAALgADCggJEQABLgAECggJJwAaACYPAA==.Interia:BAAALgAECgUJDAABLgAECgcJGAAWABIYAA==.Intress:BAAALgADCgIJAgAAAA==.',
Io='Ionsw:BAAALgAECgMJAwAAAA==.',
Is='Ishgard:BAAALgADCgcJCAAAAA==.Isopentene:BAAALgAECgMJAwAAAA==.',
Iu='Iudex:BAAALgADCgEJAQAAAA==.',
Iv='Ivalace:BAAALgAECgcJAQAAAA==.Ivyoxide:BAAALgAECgYJDAAAAA==.',
Ja='Jacabon:BAAALgADCgQJBwAAAA==.Jackillz:BAABLgAECn8aAAMCAAYJzR1zIQCpAQACAAUJ6B1zIQCpAQARAAUJpg8yOgA0AQAAAA==.Jackpriest:BAAALgAFFAEJAQAAAA==.Jadè:BAAALgADCgYJBwABLgAECgUJCQAJAAAAAA==.Jagalr:BAAALgADCgYJBgAAAA==.Jarok:BAAALgAECggJDQAAAA==.Jaydee:BAAALgAECgIJBAAAAA==.',
Jb='Jbhunna:BAAALgAECgUJCwAAAA==.',
Je='Jee:BAABLgAECn8bAAIVAAcJTQ1rDwAzAQAVAAcJTQ1rDwAzAQAAAA==.Jellypriest:BAAALgADCgIJAwAAAA==.Jenish:BAAALgAECgEJAQAAAA==.Jescon:BAAALgAECgEJAQAAAA==.Jexs:BAAALgAECgUJCQAAAA==.',
Ji='Jiamil:BAAALgAECgMJAwAAAA==.Jiayu:BAAALgADCgEJAQAAAA==.Jibberwish:BAAALgADCgcJDAABLgAECgYJFgAjAJ4eAA==.Jics:BAAALgAECgEJAQAAAA==.',
Jo='Jolteon:BAAALgADCgcJDQAAAA==.',
Ju='Juanster:BAAALgADCgcJBwAAAA==.Jubber:BAABLgAECn8WAAMjAAYJnh5FFADMAQAjAAYJZxlFFADMAQAaAAQJ3h5dowA6AQAAAA==.Jumpnglide:BAAALgAECgMJBgAAAA==.',
Jx='Jxidyn:BAAALgAECgYJBwAAAA==.',
Jy='Jynx:BAABLgAECn8WAAIGAAgJHyAdMAA7AgAGAAgJHyAdMAA7AgAAAA==.',
['Jø']='Jøzzy:BAAALgADCgUJBQAAAA==.',
Ka='Kaherd:BAABLgAECn8ZAAIVAAYJCg8bUABnAQAVAAYJCg8bUABnAQAAAA==.Kahora:BAAALgADCgcJCgAAAA==.Kallavan:BAAALgADCgEJAQAAAA==.Kalmonk:BAABLgAECn8gAAMCAAYJixwOBQDYAQACAAYJixwOBQDYAQASAAIJyQxvewBXAAAAAA==.Kalmyth:BAAALgADCgYJBgABLgAECgEJAgAJAAAAAA==.Kaltizdat:BAAALgADCgcJBwABLgAECgQJBAAJAAAAAA==.Kasadori:BAAALgADCgcJCQAAAA==.Kasualz:BAAALgAECgcJEAAAAA==.Kayrali:BAAALgADCgMJBAAAAA==.Kazsham:BAAALgAECgQJCQAAAA==.',
Kb='Kboomz:BAAALgADCgYJBgAAAA==.',
Kd='Kdvt:BAAALgAFFAIJAwABLgAFFAQJCgAMAF4JAA==.',
Ke='Keedrimath:BAAALgAECgYJBgAAAA==.Keenagon:BAAALgADCgcJBwAAAA==.Kelf:BAAALgADCgcJCgAAAA==.Kellbow:BAAALgAECgYJDQAAAA==.Kelynada:BAAALgADCgMJAwAAAA==.Keyevokey:BAAALgADCggJFgAAAA==.',
Kh='Khaemset:BAAALgADCgkJCQAAAA==.',
Ki='Kieldaz:BAABLgAECn8YAAIeAAYJxxBaEABLAQAeAAYJxxBaEABLAQAAAA==.Kinore:BAAALgAECgQJBAAAAA==.Kirisute:BAABLgAECn8zAAIMAAkJRiHsIADwAgAMAAkJRiHsIADwAgAAAA==.Kitchenboss:BAAALgAECggJEwAAAA==.Kithari:BAAALgAECgUJCwABLgAECgcJGgACAJ0fAA==.',
Kn='Knickerbits:BAAALgADCgMJAwAAAA==.Knotting:BAAALgAECgYJCgAAAA==.',
Ko='Koll:BAAALgADCgIJAgAAAA==.Kollateral:BAABLgAECn8cAAIHAAYJsBQ7FwBhAQAHAAYJsBQ7FwBhAQAAAA==.Kopara:BAAALgAECgcJEQAAAA==.Koriella:BAAALgAECgIJAgAAAA==.Kotetsu:BAAALgADCgUJBQAAAA==.',
Kr='Kraejekta:BAAALgADCgYJBwAAAA==.Krankiekunt:BAAALgAECgUJDAAAAA==.Krazmar:BAAALgADCgYJCwAAAA==.Kreigor:BAAALgADCgUJBQAAAA==.Krellhim:BAAALgAECgcJCwAAAA==.Krislocked:BAAALgAECgYJEQAAAA==.Krusper:BAAALgADCgIJAgAAAA==.',
Ku='Kungfused:BAAALgAECgIJAgAAAA==.',
Ky='Kyza:BAAALgADCgIJAgAAAA==.',
La='Laaurge:BAAALgAECgEJAQAAAA==.Landwalker:BAABLgAECn8aAAINAAcJth9wHgBMAgANAAcJth9wHgBMAgAAAA==.Langas:BAAALgAECgkJBgAAAA==.Latorius:BAAALgAECggJCQAAAA==.Lazarian:BAAALgADCgUJDQABLgAFFAEJAQAJAAAAAA==.Lazziel:BAABLgAECn8VAAIMAAcJGQRy6QAkAQAMAAcJGQRy6QAkAQAAAA==.',
Le='Leebear:BAAALgADCgEJAQAAAA==.Leilashte:BAAALgAECgYJBgAAAA==.Lenn:BAABLgAECn88AAIPAAcJ+RJHCABwAQAPAAcJ+RJHCABwAQAAAA==.Letmesolodps:BAAALgAECgQJBgAAAA==.Lettucelordh:BAAALgAECgcJEwAAAA==.Lexavis:BAAALgAECggJCgAAAA==.Leyi:BAABLgAECn8gAAMcAAcJOBh0OwAeAgAcAAcJOBh0OwAeAgAbAAMJeguNRQCfAAAAAA==.Leyissa:BAAALgAECgcJBwABLgAECgcJIAAcADgYAA==.',
Li='Liggma:BAAALgAECgQJBwAAAA==.Linkss:BAAALgADCgYJCwAAAA==.Linshadow:BAAALgADCgcJDgAAAA==.Litchblade:BAACLgAFFH8GAAIaAAQJ5gLGCwAVAQAaAAQJ5gLGCwAVAQAuAAQKfxYAAhoACAkbFaBHAB0CABoACAkbFaBHAB0CAAAA.Litgoblin:BAAALgADCgEJAgAAAA==.Littlecoops:BAAALgADCgYJCAAAAA==.',
Lo='Loalo:BAAALgADCgUJBQAAAA==.Locky:BAAALgAECgQJBgAAAA==.Lomzz:BAAALgAECgEJAgAAAA==.Loopy:BAAALgADCgEJAQAAAA==.Lootminator:BAAALgADCgQJBQAAAA==.Loptr:BAAALgADCgEJAQAAAA==.Lorelai:BAAALgADCgcJEQAAAA==.Lowkey:BAAALgAECgYJAQABLgAECgcJBwAJAAAAAA==.Lozza:BAAALgADCgQJBQAAAA==.',
Lu='Lucullus:BAAALgAECgIJAgAAAA==.Lukotii:BAAALgADCgkJAQAAAA==.Luminarus:BAAALgAECgQJBgAAAA==.Luts:BAAALgADCgIJAgAAAA==.',
Ly='Lyd:BAAALgAECgYJDAAAAA==.Lynarium:BAAALgAECgcJDgAAAA==.Lynnmage:BAAALgADCgQJBAAAAA==.',
['Lû']='Lûmiere:BAABLgAECn8YAAIkAAgJrx5gOQA+AgAkAAgJrx5gOQA+AgAAAA==.',
Ma='Magharitta:BAABLgAECn8YAAIaAAgJXBkjNABmAgAaAAgJXBkjNABmAgAAAA==.Majicx:BAAALgAECgUJBQAAAA==.Malign:BAABLgAECn8VAAIcAAgJFgpeWQC8AQAcAAgJFgpeWQC8AQAAAA==.Manaseeker:BAAALgADCgkJDAAAAA==.Maraku:BAAALgAFFAEJAgAAAA==.Masonic:BAAALgAECgQJDAAAAA==.Mathdori:BAAALgADCgkJAwAAAA==.Matter:BAAALgAECgUJCgAAAA==.Maxxfury:BAAALgAECgYJAwAAAA==.',
Mc='Mcshok:BAAALgADCgcJCAAAAA==.',
Me='Medesin:BAAALgADCgUJEwAAAA==.Medhic:BAAALgADCgIJAQAAAA==.Meirge:BAAALgADCgcJBwAAAA==.Mekhanite:BAABLgAECn8bAAIjAAcJdyDaAQAYAgAjAAcJdyDaAQAYAgAAAA==.Memebeam:BAAALgAECgYJBwAAAA==.Memedemon:BAAALgAECgEJAQABLgAECgUJCQAJAAAAAA==.Mercykill:BAAALgADCgYJBgAAAA==.Mesmagius:BAAALgAECgUJBQAAAA==.Metasoul:BAABLgAECn8lAAIGAAgJ8hR2FABaAQAGAAgJ8hR2FABaAQAAAA==.',
Mi='Midknight:BAAALgAECgYJBwAAAA==.Milfdella:BAAALgAECgcJDQAAAA==.Milspec:BAABLgAECn8WAAIVAAYJBhiRNADXAQAVAAYJBhiRNADXAQAAAA==.Minami:BAABLgAECn8bAAIkAAcJkR2uCgDkAQAkAAcJkR2uCgDkAQAAAA==.Minhiriath:BAAALgAECgYJDAAAAA==.Mistea:BAAALgAECgYJBgAAAA==.',
Mo='Modren:BAAALgAECgIJAgAAAA==.Momotaku:BAAALgAECgYJDwAAAA==.Monalisa:BAAALgAECgYJEQAAAA==.Monkecco:BAAALgAECgcJBQAAAA==.Monkgyatso:BAAALgAECgUJCwAAAA==.Monkhax:BAAALgADCgYJBQAAAA==.Monkow:BAAALgAECgQJCQAAAA==.Monne:BAAALgADCgYJBgABLgAECggJFgAPAPwUAA==.Monthax:BAAALgAECgIJAgAAAA==.Moomoos:BAABLgAECn8jAAIHAAgJthfwAgCzAQAHAAgJthfwAgCzAQAAAA==.Moonoo:BAAALgADCgIJAgAAAA==.Moonsblades:BAAALgAECgEJAQAAAA==.Moonthorn:BAAALgAECgUJCAAAAA==.Morada:BAAALgADCgcJDQAAAA==.Morena:BAAALgADCgMJBgAAAA==.Morgaina:BAABLgAECn8VAAIbAAcJNhKPEgC3AQAbAAcJNhKPEgC3AQAAAA==.Movski:BAABLgAECn8dAAMUAAYJyyCsCABOAQAUAAYJYiCsCABOAQAnAAQJxhf7DwAPAQAAAA==.',
Ms='Msbearhaven:BAAALgADCgYJBgAAAA==.',
Mu='Murst:BAABLgAECn8dAAMcAAcJCx97PwAPAgAcAAYJDSJ7PwAPAgAbAAEJ/g+xYgBJAAAAAA==.',
My='Myeyeshurt:BAAALgAECgQJCwAAAA==.',
['Mä']='Mäya:BAAALgAECgUJCwAAAA==.',
['Më']='Mëmëmë:BAAALgAECgEJAQAAAA==.',
['Mü']='Müz:BAAALgAECgUJCAABLgAFFAgJAQAJAAAAAA==.',
Na='Nahyeah:BAAALgAECgQJBAAAAA==.Natria:BAABLgAECn8iAAMTAAgJ+BD5DwDbAQATAAgJ+BD5DwDbAQAIAAMJGgoXTwCRAAAAAA==.Naw:BAAALgAECgYJBwAAAA==.Nayashka:BAAALgAECgUJDQAAAA==.',
Ne='Neeb:BAAALgAECgYJCwAAAA==.Neebd:BAAALgAECgQJBgABLgAECgYJCwAJAAAAAA==.Nepth:BAABLgAECn8jAAIBAAgJqx97FABuAgABAAgJqx97FABuAgAAAA==.Nerfde:BAAALgAECgQJBAAAAA==.Nerfdelag:BAAALgAECgcJEQAAAA==.',
Ni='Nihonshu:BAAALgADCgIJAQAAAA==.Niskus:BAAALgAECgYJEQAAAA==.Nixipixie:BAAALgADCgcJCAAAAA==.Nizan:BAAALgAECgMJAwAAAA==.Nizie:BAAALgADCgMJAgAAAA==.',
No='Nobbiepally:BAAALgAECgUJCwAAAA==.Notagoblin:BAAALgAECgYJDQAAAA==.Notahealer:BAAALgAECgcJDwAAAA==.Notdahuntard:BAAALgAECgkJDgAAAA==.',
Np='Nps:BAAALgAECgQJBgAAAA==.',
Nr='Nragz:BAAALgAECgMJBQAAAA==.',
Ns='Nsi:BAABLgAFFH8HAAIGAAMJQBRDEADRAAAGAAMJQBRDEADRAAAAAA==.',
Nu='Nulldeath:BAABLgAECn8UAAIaAAcJpCExNQBiAgAaAAcJpCExNQBiAgAAAA==.Nutsdormu:BAABLgAECn8tAAIWAAcJ2RSwBQBHAQAWAAcJ2RSwBQBHAQAAAA==.',
Ny='Nyssaela:BAAALgAECgUJBQAAAA==.Nyxmoona:BAAALgADCgUJEwAAAA==.',
['Nà']='Nàishà:BAABLgAECn8XAAMKAAcJtxSEBQDLAQAKAAcJtxSEBQDLAQAYAAYJKgVcQgDnAAAAAA==.',
Od='Odinwolf:BAABLgAFFH8LAAIFAAUJLR1sBQB1AQAFAAUJLR1sBQB1AQAAAA==.',
Og='Oggie:BAAALgAECgQJCgAAAA==.Oginn:BAAALgAECgQJBgAAAA==.',
Oh='Ohspeghettii:BAAALgADCgYJBgABLgAECgUJCQAJAAAAAA==.',
Oi='Oioi:BAAALgADCgEJAQAAAA==.',
Oj='Ojisancage:BAAALgAFFAEJAQAAAA==.',
On='Onepuff:BAAALgAECgcJDAAAAA==.Onism:BAAALgADCgkJDAAAAA==.',
Or='Orinys:BAABLgAECn8YAAIWAAYJCQzDJwA2AQAWAAYJCQzDJwA2AQAAAA==.Orkky:BAABLgAECn8dAAIjAAcJ4RwnEQD4AQAjAAcJ4RwnEQD4AQAAAA==.',
Pa='Packnwang:BAAALgADCgEJAQAAAA==.Page:BAABLgAECn8WAAIUAAgJNRi9AgADAgAUAAgJNRi9AgADAgAAAA==.Pakurruun:BAAALgADCgcJFAAAAA==.Pallatress:BAAALgADCgUJEAAAAA==.Panginoon:BAABLgAECn8cAAMaAAgJqRzMJwCbAgAaAAgJ5xvMJwCbAgAjAAYJvxW/HQBcAQAAAA==.Paphio:BAAALgAECgMJBgAAAA==.Papipalala:BAAALgAECgIJAgAAAA==.Pawadin:BAAALgAECgYJBwAAAA==.',
Pe='Pepapo:BAAALgAECgMJBwAAAA==.Pepio:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Peppsi:BAAALgADCgcJDAAAAA==.Perden:BAAALgADCgMJAwAAAA==.',
Pg='Pgundry:BAAALgAECgMJAwAAAA==.',
Ph='Phakin:BAAALgADCgkJCQAAAA==.Phatboss:BAAALgAECgYJBgABLgAECggJEwAJAAAAAA==.Phayzedout:BAAALgAECgcJEAAAAA==.',
Pi='Pierat:BAAALgAECgYJCgAAAA==.Piergeiron:BAAALgAECgcJBgABLgABCgQJBQAJAAAAAA==.Pinkrawr:BAAALgADCgMJAwAAAA==.Pinkwarrior:BAAALgAECgIJAgAAAA==.Pinkyblue:BAABLgAECn8bAAMcAAgJmxRePwAQAgAcAAgJmxRePwAQAgAbAAEJAACabQA5AAAAAA==.Pinkymonky:BAAALgADCgQJBgAAAA==.Pipeppy:BAAALgADCgYJBgAAAA==.Pipssqeek:BAAALgAECgkJAQAAAA==.Pipung:BAAALgAECgQJBQAAAA==.',
Pl='Plutô:BAAALgADCgYJDAAAAA==.',
Po='Poairua:BAAALgADCgEJAQAAAA==.Poda:BAAALgAECgEJAQAAAA==.Polloloco:BAAALgADCgcJCAAAAA==.Poobumhead:BAAALgAECgYJEgAAAA==.',
Pr='Praetorian:BAAALgADCgcJEQAAAA==.Priestmn:BAAALgADCgYJBgAAAA==.Probabely:BAAALgADCgEJAQABLgAFFAQJDAAaAM8aAA==.Probably:BAACLgAFFH8MAAIaAAQJzxqUAwB4AQAaAAQJzxqUAwB4AQAuAAQKfyQAAhoACAlwJg4SAA8DABoACAlwJg4SAA8DAAAA.',
Pt='Ptree:BAAALgADCgcJBwABLgAECgIJBgAJAAAAAA==.Ptreei:BAAALgAECgIJBQABLgAECgIJBgAJAAAAAA==.',
Pu='Puck:BAABLgAECn8XAAMTAAgJHBkBAgCJAQATAAcJQxgBAgCJAQAIAAUJ1BKZMgA1AQAAAA==.Pudgeys:BAABLgAFFH8FAAIQAAMJ4g1FAgCvAAAQAAMJ4g1FAgCvAAAAAA==.Punj:BAAALgAECgYJBwABLgADCgYJBgAJAAAAAA==.Purdxpriest:BAAALgADCgQJAwABLgADCgcJCQAJAAAAAA==.Purdxwarlock:BAAALgADCgEJAQABLgADCgcJCQAJAAAAAA==.',
Py='Pyropuff:BAAALgADCgEJAQABLgAECggJJQAeAKcgAA==.Pytranze:BAAALgAECgYJCwAAAA==.Pywarrior:BAAALgADCgEJAQAAAA==.',
Qo='Qoldia:BAAALgADCgYJBgAAAA==.',
Qu='Quarizma:BAACLgAFFH8PAAIEAAQJ9yKuAAChAQAEAAQJ9yKuAAChAQAuAAQKfysAAgQACAknJaYAAFUCAAQACAknJaYAAFUCAAAA.',
Ra='Radiantbunz:BAAALgADCgkJDgAAAA==.Rajbl:BAAALgAECgYJDgAAAA==.Rampagefist:BAAALgADCgMJAwAAAA==.Randalor:BAAALgADCgYJCgAAAA==.Rano:BAAALgAECgYJCAAAAA==.Ravenknight:BAAALgAECgEJAQAAAA==.Rayningdeath:BAAALgAECgkJAgAAAA==.Rayá:BAAALgADCgcJCAAAAA==.',
Re='Reaperzx:BAAALgAECgYJCgAAAA==.Recks:BAAALgADCgEJAQAAAA==.Rejzo:BAAALgAECgMJBQAAAA==.Rejzosun:BAAALgAECgMJAwAAAA==.Renavant:BAAALgAECgUJDgAAAA==.Repliod:BAABLgAECn8fAAMmAAcJtyWgAgD8AgAmAAcJtyWgAgD8AgAOAAIJSQLyKgBvAAAAAA==.Restho:BAAALgAECgYJEwAAAA==.Revarix:BAABLgAECn8YAAMfAAgJsRenAwBIAgAfAAgJsRenAwBIAgAaAAEJKAdGOAEgAAAAAA==.',
Rh='Rhaella:BAABLgAECn8VAAIBAAcJWQ93DQBoAQABAAcJWQ93DQBoAQAAAA==.Rhuiser:BAAALgAECgcJEAAAAA==.Rhéá:BAAALgAECgYJCwAAAA==.',
Ri='Riggerized:BAAALgAECgcJDgABLgAECggJIwAHALYXAA==.Rilirian:BAAALgAECgkJBgAAAA==.Riseth:BAABLgAECn8XAAIZAAcJaSCABADhAQAZAAcJaSCABADhAQAAAA==.Rivella:BAAALgAECgcJCQAAAA==.',
Ro='Rockmelons:BAAALgADCgEJAQAAAA==.Rockosocko:BAAALgADCggJEAAAAA==.Roflpwnnt:BAABLgAECn8nAAQLAAgJbRz2AgDeAQALAAcJjxj2AgDeAQAEAAYJ7BT+QABUAQADAAIJhh/krgBmAAAAAA==.Rolln:BAAALgADCggJCwAAAA==.Romanée:BAAALgAECgQJCAAAAA==.Rootdaddy:BAAALgADCgEJAQAAAA==.Rootweaver:BAAALgADCgYJBgAAAA==.Rousay:BAABLgAECn8XAAIRAAYJ8wbsDQDxAAARAAYJ8wbsDQDxAAAAAA==.',
Ru='Rusdar:BAAALgAECgMJAwABLgAECgcJHAAVANoDAA==.Rustylightz:BAAALgAECgQJBAAAAA==.Rutee:BAABLgAECn8fAAIkAAgJChdzTwDzAQAkAAgJChdzTwDzAQAAAA==.',
Ry='Ryn:BAAALgAECgcJEwAAAA==.Ryuk:BAAALgAECgYJEQAAAA==.',
['Rà']='Ràvon:BAAALgAECgMJAwAAAA==.',
Sa='Sabelin:BAAALgADCgEJAQABLgAECgcJGgACAJ0fAA==.Safy:BAABLgAECn8YAAISAAcJ6gutCwA1AQASAAcJ6gutCwA1AQAAAA==.Saltyslug:BAAALgAECgQJCQAAAA==.Saltz:BAAALgAECgQJBAABLgAECggJDAAJAAAAAA==.Sanctilaz:BAAALgAFFAEJAQAAAA==.Sanosan:BAAALgAECgMJBQAAAA==.Saraedor:BAAALgADCgMJAwABLgAECgEJAgAJAAAAAA==.Sartoc:BAAALgADCggJDgABLgAECgEJAgAJAAAAAA==.',
Sc='Scabbo:BAABLgAECn8UAAIbAAYJvhNwBAAQAQAbAAYJvhNwBAAQAQAAAA==.Scaleseeker:BAAALgADCgcJDQAAAA==.Scarfeast:BAAALgADCgQJBAAAAA==.Scummbag:BAAALgAECgEJAwAAAA==.',
Sd='Sdw:BAAALgADCgcJCgABLgAECgEJAgAJAAAAAA==.',
Se='Sebille:BAABLgAECn8fAAIMAAgJCR6XLwC0AgAMAAgJCR6XLwC0AgAAAA==.Seiferoth:BAAALgAECgEJAQABLgAFFAUJCwAFAC0dAA==.Selais:BAAALgAECgYJEgAAAA==.Selussa:BAAALgAECgYJBgABLgAFFAYJFgAGAO8hAA==.Senddori:BAAALgAECgUJBQAAAA==.Sepl:BAAALgAECgYJCgAAAA==.Serana:BAAALgAECgUJBQAAAA==.Serasashrain:BAAALgADCgEJAQAAAA==.',
Sh='Shaddai:BAABLgAECn8YAAIHAAgJBxdVCgAqAgAHAAgJBxdVCgAqAgAAAA==.Shadylock:BAAALgAECgMJBgAAAA==.Shakyrabbit:BAAALgADCgMJBAAAAA==.Shamankiller:BAAALgAECgYJEQAAAA==.Shamannoodle:BAAALgADCgIJAgAAAA==.Shamitsdk:BAAALgADCgMJBgABLgAECgYJEAAJAAAAAA==.Shamix:BAAALgADCgYJDAAAAA==.Shaniquasimo:BAAALgAECgYJEQAAAA==.Shaquiqui:BAAALgAECgIJAgAAAA==.Sharddaddy:BAAALgADCgIJAgAAAA==.Sharftay:BAAALgAECgYJEgABLgAFFAYJFQADABsMAA==.Sharissa:BAAALgAECgYJCAAAAA==.Shatgun:BAAALgADCgcJBwAAAA==.Shinieedruid:BAAALgAECgMJAgABLgAECggJGgAcAMYcAA==.Shockedurmum:BAABLgAECn8WAAMQAAcJIhYmFgBcAQAQAAYJNA8mFgBcAQAZAAYJ+RmIRQAyAQAAAA==.Shocknôrris:BAAALgAECgYJDAAAAA==.Shouffle:BAAALgADCgcJBwAAAA==.',
Si='Sickomode:BAAALgADCgMJAwABLgAECgcJGAAWABIYAA==.Siferbooze:BAAALgADCgQJBAAAAA==.Silcy:BAAALgADCgMJAwAAAA==.Sillàrus:BAAALgAECgcJAgAAAA==.Silverspulse:BAABLgAECn8YAAMKAAYJWBvgLwCCAQAKAAUJZRvgLwCCAQAiAAQJrRohLAA6AQAAAA==.Sinfulpally:BAABLgAECn8hAAIkAAgJzh0SCgDrAQAkAAgJzh0SCgDrAQAAAA==.Sippycup:BAABLgAECn8YAAIaAAgJ8h6UGADoAgAaAAgJ8h6UGADoAgAAAA==.Sisisi:BAAALgADCgQJBAAAAA==.',
Sk='Skartos:BAAALgADCgcJFQAAAA==.Skilledplaya:BAAALgAECgQJBAAAAA==.Skulv:BAACLgAFFH8GAAIGAAMJISDMEQC3AAAGAAMJISDMEQC3AAAuAAQKfyMAAgYACAnvJFoJAD0DAAYACAnvJFoJAD0DAAAA.Skum:BAAALgAECgEJAgAAAA==.Skunkdmeow:BAAALgAECgcJCgAAAA==.',
Sl='Slimygerald:BAAALgAECgIJAgAAAA==.Slopain:BAAALgAECgQJCgAAAA==.Slopflop:BAAALgADCgYJBgAAAA==.Slåppery:BAAALgAECgcJDQAAAA==.',
Sm='Smallarms:BAAALgAECgcJBQAAAA==.',
Sn='Snorlax:BAAALgADCgcJBwAAAA==.Snort:BAABLgAECn8WAAMBAAYJ9SGCAwBKAgABAAYJ9SGCAwBKAgAkAAUJpx/ZZwCwAQAAAA==.',
So='Sonotafurry:BAAALgAECgMJBgAAAA==.Soojung:BAAALgADCgYJBgAAAA==.Soova:BAAALgAECgYJDQAAAA==.Sorcus:BAAALgAECgUJCwAAAA==.Soreknees:BAAALgADCgEJAQAAAA==.Souliuge:BAAALgADCgMJAwAAAA==.Soundface:BAABLgAECn8UAAIZAAYJXRdbJQDmAQAZAAYJXRdbJQDmAQAAAA==.',
Sp='Sparkysteve:BAABLgAECn8YAAMZAAcJ3yFjEAClAgAZAAcJ3yFjEAClAgAFAAEJqg4fmgA5AAAAAA==.Spelcastndog:BAABLgAECn8cAAIMAAgJehd7SwBUAgAMAAgJehd7SwBUAgAAAA==.Spindrift:BAAALgAECgYJEAAAAA==.Spinypubes:BAAALgAECgMJBQAAAA==.Spiritfuzz:BAAALgAECgQJBAABLgAFFAQJBgAaAOYCAA==.Spiritrez:BAAALgADCgYJAwABLgADCggJFgAJAAAAAA==.Spodermin:BAAALgADCgEJAQAAAA==.Spoonyy:BAAALgAECgIJBwAAAA==.Spukz:BAACLgAFFH8IAAIVAAIJmxCtGACmAAAVAAIJmxCtGACmAAAuAAQKfxQAAxUABgmUHuMFAMkBABUABgmUHuMFAMkBABcAAQk4D5g/ADkAAAAA.Spunkmonk:BAAALgAECgEJAwAAAA==.',
St='Stabbyhunt:BAAALgAECgYJBgAAAA==.Starstorm:BAAALgADCggJFgAAAA==.Sterlybo:BAAALgADCgUJBQAAAA==.Stoneyboi:BAAALgADCgcJCQAAAA==.Stormwrath:BAAALgAECgYJEAAAAA==.Stoutbrew:BAAALgAECgYJDgAAAA==.Stuy:BAABLgAECn8vAAIEAAgJ6xlQAgC1AQAEAAgJ6xlQAgC1AQAAAA==.Stãria:BAAALgAECgYJEAAAAA==.Stårlå:BAAALgADCgEJAgAAAA==.Stèpsis:BAAALgADCgEJAQAAAA==.Störme:BAAALgADCgUJDAAAAA==.',
Su='Sugarburst:BAAALgAECgYJDgAAAA==.Sugmanutz:BAAALgAECgMJAwAAAA==.Sukmahdisc:BAABLgAECn8VAAIiAAgJTgrjIQCEAQAiAAgJTgrjIQCEAQAAAA==.Sulph:BAAALgADCgEJAQAAAA==.Supershy:BAAALgAECgEJAQAAAA==.Suppirin:BAAALgADCgYJCAAAAA==.Supprakus:BAABLgAECn8eAAIIAAYJTBouCQBVAQAIAAYJTBouCQBVAQAAAA==.Susuryss:BAAALgADCgUJBQAAAA==.',
Sv='Svendlemoon:BAABLgAECn8eAAIOAAYJ2BbZEACfAQAOAAYJ2BbZEACfAQAAAA==.',
Sw='Swak:BAAALgAECgYJEAAAAA==.Sweaty:BAAALgADCgkJCQAAAA==.Swinginwilly:BAAALgAECgYJBgAAAA==.Swippy:BAAALgADCgQJBAAAAA==.Swirlo:BAABLgAECn8iAAIGAAgJDhgJDgCdAQAGAAgJDhgJDgCdAQAAAA==.Swirlyball:BAAALgADCgkJEQABLgAECggJIgAGAA4YAA==.',
Sy='Syaphire:BAAALgADCgIJAgAAAA==.Syndeath:BAAALgADCgIJAgAAAA==.Synths:BAABLgAECn8UAAMKAAgJ7hZNGgAJAgAKAAgJ7hZNGgAJAgAYAAEJtAoZYQA2AAAAAA==.',
['Sñ']='Sñort:BAAALgAECgYJDQAAAA==.',
['Sý']='Sýìvàñás:BAAALgAECgUJAQAAAA==.',
Ta='Taffyclown:BAABLgAECn8aAAICAAcJnR9zAgBPAgACAAcJnR9zAgBPAgAAAA==.Taharuot:BAAALgADCgcJDQAAAA==.Takahe:BAAALgADCgcJCAAAAA==.Tallinor:BAAALgAECgYJEgAAAA==.Taumast:BAAALgAECgMJBQABLgAECggJFgAKACESAA==.Tauter:BAAALgADCgUJEQAAAA==.Tazzee:BAAALgAECgEJAQAAAA==.',
Te='Teeki:BAAALgADCgcJBwAAAA==.Teiresius:BAAALgADCgYJBgAAAA==.Telsda:BAAALgAECgEJAgAAAA==.Tempyst:BAABLgAECn8YAAMWAAcJEhhEEwAOAgAWAAcJEhhEEwAOAgAIAAEJpgEiZgApAAAAAA==.Tessdee:BAAALgAECgYJCAAAAA==.Tetactic:BAAALgADCgIJAgAAAA==.',
Th='Thalia:BAABLgAECn8UAAIHAAgJzxwGBQCsAgAHAAgJzxwGBQCsAgAAAA==.Thaytred:BAAALgAECgMJCAAAAA==.Thecheezels:BAAALgAECgIJAwAAAA==.Thegòòch:BAAALgADCgEJAQAAAA==.Thesean:BAAALgADCgcJBwAAAA==.Thevoice:BAAALgADCgQJBAAAAA==.Thomzhar:BAAALgAECgUJCwAAAA==.Thornir:BAAALgADCgEJAQABLgADCgMJBAAJAAAAAA==.Thraznith:BAAALgAECgUJDAAAAA==.Threeföld:BAAALgADCgYJBgABLgAFFAIJAgAJAAAAAA==.Throber:BAAALgADCgkJDAAAAA==.',
Ti='Tienchi:BAAALgAECggJEwAAAA==.Tierk:BAAALgAECgcJDAAAAA==.Tillyhunter:BAAALgADCgcJEQAAAA==.Timmyy:BAAALgAECgcJDAAAAA==.Tinainverse:BAAALgADCgEJAQAAAA==.',
To='Tomatofarmer:BAAALgADCgUJBQAAAA==.Tormént:BAACLgAFFH8FAAIfAAIJVBDIAQCrAAAfAAIJVBDIAQCrAAAuAAQKfzAAAh8ACAnMIx8AANICAB8ACAnMIx8AANICAAAA.Torvold:BAAALgADCgYJBgAAAA==.',
Tr='Traumatizer:BAABLgAECn8cAAIVAAcJVxUgNADZAQAVAAcJVxUgNADZAQAAAA==.Treehumpin:BAAALgAECgMJAwAAAA==.Tremorlover:BAAALgAECgIJBQAAAA==.Trogas:BAAALgAECgMJAwAAAA==.Tronix:BAAALgAECggJCAAAAA==.Tronixs:BAAALgAECgEJAQABLgAECggJCAAJAAAAAA==.Trucidario:BAAALgAECgMJBgAAAA==.Trulsdk:BAAALgAECgEJAQABLgAECgYJBwAJAAAAAA==.Truwar:BAAALgAECgYJBwAAAA==.',
Tu='Turtlewave:BAAALgAECgUJAgAAAA==.',
Tw='Twiganomicon:BAAALgAECgEJAQAAAA==.Twiggz:BAAALgAECgQJDAAAAA==.Twinkleface:BAAALgAECgQJBAAAAA==.',
Ty='Tylund:BAABLgAECn8aAAIDAAgJzgjKQgClAQADAAgJzgjKQgClAQAAAA==.Tyrilara:BAAALgADCgUJCAAAAA==.Tyruu:BAAALgADCgYJBgAAAA==.',
['Tâ']='Tânk:BAAALgAECgEJAgAAAA==.',
['Tï']='Tïm:BAAALgAECgMJAwABLgAECgcJDAAJAAAAAA==.',
Un='Unholykníght:BAAALgADCgEJAQAAAA==.',
Ur='Uratowel:BAAALgADCgEJAQAAAA==.',
Va='Valaya:BAAALgAECgYJDAAAAA==.Valcaris:BAAALgAECgMJAwAAAA==.Valdr:BAAALgAECgQJBAABLgAFFAQJCAAmADgVAA==.Valentine:BAAALgAECgEJAQAAAA==.Valex:BAAALgAECgEJAQAAAA==.Valithor:BAAALgAECgYJBwAAAA==.Vampaph:BAAALgADCgEJAQAAAA==.',
Ve='Velarose:BAAALgAECgYJEwAAAA==.Veledor:BAAALgADCgEJAQAAAA==.Velenair:BAAALgAECgQJDQABLgAECgcJBQAJAAAAAA==.Velenlerolan:BAAALgAECgYJDgAAAA==.Velicelia:BAAALgAECgEJAgAAAA==.Velthara:BAABLgAECn8bAAIkAAkJshgqIACrAgAkAAkJshgqIACrAgAAAA==.Velzan:BAAALgAECgUJCgAAAA==.Verailde:BAAALgADCgIJAgAAAA==.Verathos:BAAALgADCgIJAgAAAA==.Vergil:BAAALgAECgYJCQAAAA==.Verilence:BAABLgAECn8dAAMdAAgJxyNrAABYAwAdAAgJxyNrAABYAwAcAAEJ+wdRJAEtAAAAAA==.Verks:BAAALgADCgYJBgABLgAECgUJCQAJAAAAAA==.Vext:BAAALgAECgcJCAAAAA==.',
Vi='Victar:BAAALgADCgMJAwAAAA==.Villios:BAAALgAECgcJDgAAAA==.',
Vo='Voidberg:BAAALgAECgUJBQABLgAFFAMJBQANADEJAA==.Voidfondler:BAACLgAFFH8GAAIGAAMJRxXbGgD6AAAGAAMJRxXbGgD6AAAuAAQKfxQAAgYACAl5IoETAOMCAAYACAl5IoETAOMCAAAA.Voidgasm:BAAALgAECgMJBQAAAA==.Voidlocked:BAAALgAECgYJCwAAAA==.Vorndryad:BAAALgADCgYJBgAAAA==.',
Vy='Vynburn:BAABLgAECn8dAAIMAAgJMRNDDgDWAQAMAAgJMRNDDgDWAQAAAA==.Vynnaris:BAAALgAECgYJDQAAAA==.',
['Vì']='Vìn:BAAALgAECgEJAgAAAA==.',
Wa='Wadadadadeng:BAAALgADCgMJAwAAAA==.Wakuja:BAAALgADCgYJBgABLgAFFAUJCwAFAC0dAA==.Wallahi:BAAALgAECgUJCwAAAA==.Warriorlol:BAAALgADCgEJAQAAAA==.Warspear:BAAALgADCgEJAQAAAA==.Watson:BAABLgAECn8UAAIMAAYJrhAxJABAAQAMAAYJrhAxJABAAQAAAA==.Waveryy:BAAALgADCgYJCwAAAA==.',
We='Wehex:BAAALgADCgIJAgAAAA==.Wemblitz:BAAALgADCgUJEAAAAA==.Weraise:BAAALgADCgcJBwAAAA==.Wesh:BAAALgAECgMJAwAAAA==.',
Wh='Whio:BAAALgAECgYJDQAAAA==.',
Wi='Wildglaive:BAAALgADCgkJGAAAAA==.Wintersfence:BAAALgAECgYJEQAAAA==.',
Wo='Woshiwacky:BAAALgADCgcJCQAAAA==.',
Xa='Xaldrin:BAAALgADCgEJAQAAAA==.Xallatath:BAAALgAECgUJBQAAAA==.Xanxes:BAAALgADCgIJAgAAAA==.',
Xe='Xenarn:BAEALgADCgUJAQABLgAECgYJGAAgACoQAA==.Xenoruin:BAABLgAECn8bAAIhAAcJjg9bBgBTAQAhAAcJjg9bBgBTAQAAAA==.Xerez:BAAALgADCgYJDAAAAA==.Xertzart:BAABLgAECn8iAAINAAcJSB3vBwDkAQANAAcJSB3vBwDkAQAAAA==.Xev:BAAALgADCgkJEgAAAA==.',
Xi='Ximigo:BAAALgAECgYJEAAAAA==.Xinrat:BAAALgAECgIJAgAAAA==.',
['Xê']='Xêv:BAAALgAECgcJEQAAAA==.',
Yo='Yojambuh:BAAALgAECgMJBQAAAA==.Yoyo:BAAALgAECgYJCgAAAA==.',
Yr='Yrugae:BAAALgADCgYJDgAAAA==.',
['Yõ']='Yõzõrã:BAAALgADCgcJCAAAAA==.',
Za='Zae:BAABLgAECn8YAAIoAAYJqB7EAgANAgAoAAYJqB7EAgANAgAAAA==.Zaeley:BAAALgAECgkJCQABLgAECgcJGAAoAKgeAA==.Zanisha:BAAALgAECgYJEAAAAA==.Zatasia:BAAALgAFFAIJAgAAAA==.',
Ze='Zeddar:BAAALgAECgQJBAAAAA==.Zegion:BAABLgAECn8bAAMBAAYJCAqVVgAhAQABAAYJCAqVVgAhAQAkAAEJ3QNcWQElAAAAAA==.Zelendorm:BAABLgAECn8WAAIHAAgJ2B6dCwAQAgAHAAgJ2B6dCwAQAgAAAA==.Zephyreus:BAAALgADCgkJFgAAAA==.Zerat:BAAALgADCggJDwABLgAECggJFgAPAPwUAA==.Zeroth:BAAALgADCgcJCgAAAA==.',
Zi='Zingerböx:BAAALgADCgYJBgAAAA==.Zionara:BAAALgADCgUJBQABLgAFFAQJAQAJAAAAAA==.',
Zu='Zunara:BAAALgADCgcJBwAAAA==.',
['Ãk']='Ãkillies:BAABLgAECn8cAAMVAAcJ2gPuaAARAQAVAAcJnAPuaAARAQAXAAIJ9QIsRgArAAAAAA==.',
['År']='Årrow:BAAALgADCgMJAwAAAA==.',
['Ær']='Æries:BAAALgADCgUJBQAAAA==.',
['Îl']='Îllshot:BAAALgADCgcJBwAAAA==.',
['Ðo']='Ðomino:BAAALgAECgEJAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

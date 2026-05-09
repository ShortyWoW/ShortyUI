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

local lookup = {'Paladin-Holy','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Paladin-Protection','Evoker-Augmentation','Unknown-Unknown','Priest-Holy','Hunter-Survival','Mage-Frost','Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warrior-Fury','Warrior-Arms','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Protection','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaoaqu:BAAALgAECgEJAwAAAA==.Abelas:BAACLgAFFH8HAAIBAAQJ9CGyBwBYAQABAAQJ9CGyBwBYAQAuAAQKfxUAAgEACAk+IzIMALkCAAEACAk+IzIMALkCAAEuAAUUBgkWAAIAIyAA.Abemonkey:BAABLgAFFH8WAAICAAYJIyC6AgAwAgACAAYJIyC6AgAwAgAAAA==.Abuden:BAAALgAECgEJAQAAAA==.',
Ac='Actaeus:BAABLgAECn8XAAMDAAcJ+ht0LAABAgADAAYJQxx0LAABAgAEAAQJMRQ+WADlAAAAAA==.',
Ad='Addelana:BAABLgAECn8WAAMFAAgJlBLbNQCsAQAFAAgJlBLbNQCsAQAGAAEJdAOfcQAhAAAAAA==.Adelyda:BAAALgAECgQJCAAAAA==.Adrasta:BAAALgAECgcJDgAAAA==.',
Ae='Aedrius:BAAALgAECgEJAQAAAA==.Aelador:BAAALgADCgMJBAAAAA==.Aelathe:BAAALgAECgEJAQAAAA==.Aerys:BAAALgAECgEJAQAAAA==.',
Af='Afewbeerz:BAAALgADCgMJAwAAAA==.Africandrake:BAAALgADCgYJBgAAAA==.',
Ah='Ahnkori:BAAALgAECgIJAgAAAA==.',
Ai='Aifik:BAAALgAECgIJAgAAAA==.',
Ak='Akey:BAABLgAECn8rAAIDAAgJvgyZNAB7AQADAAgJvgyZNAB7AQAAAA==.Akiller:BAAALgAECgMJBQAAAA==.',
Al='Alamal:BAAALgAECgEJAQAAAA==.Alamwah:BAACLgAFFH8KAAIHAAQJzxqsJwATAQAHAAQJzxqsJwATAQAuAAQKfx8AAgcABwnxHAcuAEQCAAcABwnxHAcuAEQCAAAA.Alanaz:BAAALgAECgcJCwAAAA==.Alaroo:BAAALgAECgYJCQAAAA==.Albinoslug:BAAALgADCgUJBQAAAA==.Aleine:BAABLgAECn9GAAIIAAkJTxM0CgCfAQAIAAkJTxM0CgCfAQAAAA==.Aleio:BAAALgAECgIJAgAAAA==.Alektra:BAAALgAECggJCQAAAA==.Alessi:BAAALgAECgYJCAAAAA==.Alexrose:BAAALgADCgcJBwAAAA==.Aliq:BAAALgAECgEJAQAAAA==.Alliete:BAAALgAECgEJAQABLgAECggJGAAJAI0MAA==.Alliyah:BAAALgAECgEJAgABLgAECgMJBgAKAAAAAA==.Aloine:BAABLgAECn8kAAILAAkJhQZzIQA9AQALAAkJhQZzIQA9AQAAAA==.Alphonze:BAAALgAECgIJAgAAAA==.Alynne:BAAALgAECgcJBgAAAA==.',
Am='Amelior:BAAALgADCgIJAgAAAA==.Amogus:BAAALgAECggJDAAAAA==.Amorallan:BAAALgAECgQJBAAAAA==.Ampuzzible:BAABLgAECn8qAAILAAgJ4Bo/CwAyAgALAAgJ4Bo/CwAyAgAAAA==.',
An='Andju:BAAALgADCgMJAwAAAA==.Anhedonias:BAAALgAECgcJAQAAAA==.Animism:BAAALgADCgUJBQAAAA==.Anivar:BAAALgADCgcJBwAAAA==.Anneke:BAAALgADCgMJAwABLgAECggJGAAJAI0MAA==.Anyá:BAABLgAECn8nAAIMAAgJuwniEACfAQAMAAgJuwniEACfAQAAAA==.',
Ar='Arbitera:BAABLgAECn8lAAICAAkJ4x4ZAwALAwACAAkJ4x4ZAwALAwAAAA==.Arcaneth:BAAALgADCggJCAAAAA==.Arcette:BAAALgADCgkJHQAAAA==.Archmystique:BAABLgAECn8oAAINAAcJFBnMRwCQAQANAAcJFBnMRwCQAQAAAA==.Arcthane:BAAALgADCgQJBAABLgADCgkJHQAKAAAAAA==.Arkona:BAABLgAECn8UAAILAAYJyBlSIgDRAQALAAYJyBlSIgDRAQAAAA==.Arkzart:BAAALgAECgQJBAAAAA==.Arrogant:BAAALgAFFAEJAQAAAA==.',
As='Asanath:BAAALgADCgkJDwAAAA==.Asdf:BAAALgAECgEJAQAAAA==.Ashley:BAABLgAECn8uAAIDAAkJLCFKAgAnAwADAAkJLCFKAgAnAwAAAA==.Ashryveris:BAAALgAECgYJEwAAAA==.Asmonjoel:BAAALgAECgMJBgAAAA==.Assumi:BAABLgAECn8WAAIOAAYJZwtyXgAUAQAOAAYJZwtyXgAUAQAAAA==.',
At='Ataturk:BAAALgAECgUJDAAAAA==.Athenis:BAAALgAECgcJDgAAAA==.Atka:BAAALgADCgcJBwAAAA==.Atumor:BAAALgAFFAEJAQABLgAFFAMJBwAPAKkSAA==.',
Au='Audree:BAAALgADCgMJAwAAAA==.Augiediaz:BAAALgAECgcJDAAAAA==.Auraine:BAAALgAECgcJCQAAAA==.Aurelionn:BAAALgAECgEJAgAAAA==.',
Av='Avadacadavra:BAAALgADCgUJBwAAAA==.',
Ax='Axonpredator:BAAALgADCgEJAQAAAA==.',
Az='Azamat:BAAALgAECgcJCAAAAA==.Azazêll:BAABLgAECn8YAAIQAAYJ8Q0qDgDwAAAQAAYJ8Q0qDgDwAAAAAA==.Azidian:BAAALgADCgEJAQAAAA==.Azmodais:BAAALgAECgIJAgAAAA==.Azuredemonx:BAABLgAECn80AAIHAAcJrBvwHADbAQAHAAcJrBvwHADbAQAAAA==.Azurgosa:BAAALgADCgUJBQAAAA==.',
Ba='Baagul:BAAALgAECgIJAgAAAA==.Badheals:BAABLgAECn8jAAQRAAkJpBXXKAAQAgARAAkJpBXXKAAQAgASAAIJZQfhHQBrAAATAAMJQwagSQBaAAABLgAFFAIJAgAKAAAAAA==.Balfin:BAAALgADCggJCAAAAA==.Balid:BAAALgADCggJCQAAAA==.Banan:BAAALgAECgUJCAAAAA==.Bazaseal:BAAALgAECgUJBwAAAA==.',
Bb='Bbqporkbuns:BAACLgAFFH8KAAIUAAMJGhN6BQDpAAAUAAMJGhN6BQDpAAAuAAQKfyMAAhQACQnvGbMDAPACABQACQnvGbMDAPACAAAA.',
Be='Beauranged:BAAALgAECgIJAgAAAA==.Bece:BAAALgADCgcJDgAAAA==.Beefcakes:BAAALgADCgEJAQAAAA==.Beenafflictn:BAAALgADCgEJAQAAAA==.Beerpong:BAABLgAECn8YAAMVAAYJtBBwPAAqAQAVAAYJfw1wPAAqAQAWAAYJ3AruTwAEAQABLgAECgkJGwADAF0eAA==.Belevie:BAAALgADCgYJBgABLgAECgkJPwAJAHsNAA==.Bellanoth:BAABLgAECn8UAAQJAAkJ+QqKIAA9AQAJAAgJIwmKIAA9AQAXAAcJWgQgFwDSAAAYAAIJYwVCGgAkAAAAAA==.Belledormi:BAABLgAECn8/AAMJAAkJew0fFwCJAQAJAAkJew0fFwCJAQAYAAEJ5QFRRQAhAAAAAA==.Bellfurion:BAAALgAECgQJCgAAAA==.Belltree:BAAALgADCgIJAgAAAA==.Bendyendy:BAAALgADCgYJBwAAAA==.',
Bf='Bfev:BAABLgAECn8hAAIZAAkJ+By/AwCaAgAZAAkJ+By/AwCaAgAAAA==.',
Bh='Bhad:BAAALgADCgMJAwAAAA==.',
Bi='Bid:BAABLgAECn8lAAIDAAgJFBx/GQAGAgADAAgJFBx/GQAGAgAAAA==.Bierfiendx:BAAALgAECgEJAQAAAA==.Bify:BAAALgADCgYJCAAAAA==.Bigalo:BAABLgAECn8lAAIMAAgJRBP1DADWAQAMAAgJRBP1DADWAQAAAA==.Bigcogg:BAAALgAFFAIJAgAAAA==.Bigdikbusta:BAAALgAECgYJDwAAAA==.Biggesthighz:BAABLgAECn8gAAIMAAgJAxlRBgBMAgAMAAgJAxlRBgBMAgAAAA==.Bigjer:BAACLgAFFH8OAAIaAAQJwRyQCABdAQAaAAQJwRyQCABdAQAuAAQKfxwAAhoACQmqHnQSALwCABoACQmqHnQSALwCAAAA.Biglee:BAAALgAECgEJAgAAAA==.Bird:BAABLgAECn8YAAMJAAgJNCHkDQCXAgAJAAgJNCHkDQCXAgAXAAUJawyxLQAFAQAAAA==.',
Bl='Blaisy:BAABLgAECn8jAAILAAgJRRVfKwCbAQALAAgJRRVfKwCbAQAAAA==.Blakdynamite:BAAALgAECgQJBgAAAA==.Blayx:BAAALgADCgQJBAABLgAECgcJHwANAEAkAA==.Blerdsterm:BAABLgAECn8tAAMbAAkJCh/XAQDEAgAbAAkJ7RzXAQDEAgAaAAcJ+h9UIQBJAgAAAA==.Blitzz:BAAALgAECgQJBAAAAA==.Blueragebar:BAAALgAECgEJAQAAAA==.',
Bo='Bofà:BAAALgAFFAIJBAAAAA==.Boogeyman:BAAALgAECgkJDgAAAA==.Boohbooh:BAAALgADCgUJBQAAAA==.Borgnine:BAABLgAECn8cAAIVAAkJxxImCwAHAgAVAAkJxxImCwAHAgAAAA==.',
Br='Brannie:BAABLgAECn8nAAIcAAgJrQfeHQBNAQAcAAgJrQfeHQBNAQAAAA==.Brenine:BAABLgAECn8oAAQTAAcJLRXhFgCFAQATAAcJIBXhFgCFAQASAAMJxQ/RJwCPAAAdAAQJawQJKgBSAAAAAA==.Brila:BAAALgAECgkJDgAAAA==.Britneyfears:BAAALgAECgYJBQABLgAECgkJBgAKAAAAAA==.Brodess:BAACLgAFFH8NAAIGAAQJ+iKxBQCYAQAGAAQJ+iKxBQCYAQAuAAQKfykAAgYACQl7JNADAMYCAAYACQl7JNADAMYCAAAA.Brody:BAABLgAECn8nAAIHAAkJnR7yBQDLAgAHAAkJnR7yBQDLAgAAAA==.Bromorc:BAAALgADCggJIAAAAA==.Brothernarms:BAABLgAECn8XAAIbAAkJ1gulDwBNAQAbAAkJ1gulDwBNAQAAAA==.Brox:BAAALgAECgMJBgAAAA==.',
Bs='Bse:BAAALgADCgYJBgAAAA==.',
Bu='Bubbleo:BAAALgAECgEJAgAAAA==.Budholy:BAAALgAECgEJAwAAAA==.Buggyboi:BAAALgADCgMJAwABLgAFFAUJFQARALQcAA==.Buggyhealz:BAACLgAFFH8VAAIRAAUJtBzMBgDMAQARAAUJtBzMBgDMAQAuAAQKfykAAhEACQmfJGQFADcDABEACQmfJGQFADcDAAAA.Bulimio:BAAALgAECgIJAwAAAA==.Bungeye:BAAALgAECgEJAQAAAA==.Bunzbunnie:BAAALgAECgQJDAAAAA==.Bunzbunny:BAAALgAECgMJAwAAAA==.Buratt:BAAALgADCggJIAAAAA==.Burtmonklin:BAABLgAECn8iAAIWAAkJDCXbAQAEAwAWAAkJDCXbAQAEAwAAAA==.Busdriver:BAACLgAFFH8OAAIeAAQJmBplIQBdAQAeAAQJmBplIQBdAQAuAAQKfx0AAh4ACQkTH7kzAGgCAB4ACQkTH7kzAGgCAAAA.Buster:BAAALgAECgEJAQAAAA==.Busterr:BAAALgAECgQJCwAAAA==.',
Ca='Caleroice:BAAALgAECgcJDgAAAA==.Capacitør:BAABLgAECn8kAAIGAAgJjyCHBwBpAgAGAAgJjyCHBwBpAgAAAA==.Cardib:BAABLgAECn83AAQOAAgJfiHdIADsAQAOAAYJgCHdIADsAQAQAAYJoxtbGgB6AQAfAAEJAAAqIABxAAAAAA==.Cartier:BAAALgADCgYJBgAAAA==.Cattabloom:BAAALgAECgEJAwAAAA==.Cattazap:BAACLgAFFH8GAAMFAAMJmxbXHADyAAAFAAMJmxbXHADyAAAGAAEJgwQ6LwBAAAAuAAQKfyQAAwUACAmdJD4EADADAAUACAmdJD4EADADAAYAAwm8C/x4AF8AAAAA.',
Ce='Ceefu:BAABLgAFFH8JAAICAAUJbRoKBwC4AQACAAUJbRoKBwC4AQABLgAFFAUJCwAFADAdAA==.Celtic:BAAALgAECgcJAQAAAA==.Cerran:BAAALgAECgEJAQAAAA==.',
Ch='Chakrakhan:BAABLgAECn8XAAIVAAgJQBGCEwCXAQAVAAgJQBGCEwCXAQAAAA==.Char:BAAALgAECgYJEQAAAA==.Chase:BAABLgAECn8nAAIbAAgJNR9RAwBxAgAbAAgJNR9RAwBxAgAAAA==.Chayang:BAAALgAECgYJBgAAAA==.Chopzuey:BAAALgADCgYJCAAAAA==.Chugtiki:BAABLgAECn8zAAMFAAkJvRyrBQDeAgAFAAkJvRyrBQDeAgAGAAgJnxP1GQCAAQAAAA==.',
Ci='Cinderaz:BAAALgADCggJIAAAAA==.Ciyus:BAAALgAECgYJCAAAAA==.',
Cl='Clann:BAAALgAECgYJEQAAAA==.Clarissahh:BAAALgAECgQJCwAAAA==.',
Co='Coolrunnins:BAABLgAECn8aAAISAAgJnhiQBAAgAgASAAgJnhiQBAAgAgAAAA==.Coolwhip:BAAALgAECgMJDQAAAA==.Coquin:BAAALgADCgEJAwAAAA==.Coquina:BAAALgAECgUJDQAAAA==.Cordeilia:BAACLgAFFH8RAAILAAQJ0RD6CgAaAQALAAQJ0RD6CgAaAQAuAAQKfzgAAgsACAmcIRoGAO0CAAsACAmcIRoGAO0CAAAA.Cosmi:BAAALgAECgYJDwABLgAFFAIJAgAKAAAAAQ==.Costiigan:BAAALgAECgUJDQAAAA==.',
Cr='Criznara:BAAALgAECgcJBwAAAA==.Crowlie:BAAALgAECgkJCgAAAA==.Cruxxi:BAABLgAECn8jAAMOAAkJFh8fEQBbAgAOAAkJFh8fEQBbAgAQAAQJWBw/JAA4AQAAAA==.',
Cu='Curthill:BAAALgAECgMJBAAAAA==.',
Cx='Cxaxukluth:BAAALgAECgYJDAABLgAFFAIJAgAKAAAAAQ==.',
Cy='Cyberdots:BAAALgAECgYJBQAAAA==.Cyenthea:BAABLgAECn8UAAMBAAcJiyMeFwBZAgABAAYJQiQeFwBZAgAPAAcJdR+vLwC+AQABLgAFFAgJGAAHADEcAA==.Cygeance:BAAALgADCgYJCQAAAA==.Cyklar:BAAALgADCggJHQAAAA==.Cyphren:BAAALgAECgYJDwAAAA==.Cyrias:BAAALgADCgUJBQAAAA==.',
Da='Dacaille:BAAALgAECgYJCAAAAA==.Daddysouls:BAAALgAECgcJBwAAAA==.Dadingding:BAAALgAECgcJEgAAAA==.Damnflanders:BAABLgAECn8VAAIgAAkJbwmLBQB1AQAgAAkJbwmLBQB1AQAAAA==.Dankozdravic:BAAALgAECgQJBgAAAA==.Daqueta:BAAALgAECgYJCgAAAA==.Daquetamk:BAAALgAECgUJBgAAAA==.Daquetapl:BAAALgAECgIJAwAAAA==.Darkniggura:BAABLgAECn8WAAINAAgJJg9mZgBEAQANAAgJJg9mZgBEAQAAAA==.Darknstormy:BAAALgAECgUJDwAAAA==.Darkpal:BAABLgAFFH8HAAIPAAMJqRKMKQAHAQAPAAMJqRKMKQAHAQAAAA==.Darkskye:BAAALgAECggJDgAAAA==.Darthbane:BAAALgAECgQJBAAAAA==.Dazer:BAAALgAECgcJCQAAAA==.Dazgrim:BAAALgAECgQJAwABLgAECgYJDQAKAAAAAA==.Dazrawr:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.',
De='Deadlobster:BAAALgADCgcJBwAAAA==.Deadlyfreak:BAAALgAECgcJCgAAAA==.Deadnick:BAAALgAECggJCgAAAA==.Deathax:BAAALgADCggJDwAAAA==.Deathcerby:BAAALgADCgIJAgAAAA==.Deathicus:BAABLgAECn8cAAIPAAgJkQXNrwAkAQAPAAgJkQXNrwAkAQAAAA==.Decapitation:BAACLgAFFH8LAAIDAAMJwht4CwAGAQADAAMJwht4CwAGAQAuAAQKfy0AAgMACQmWI/EBADQDAAMACQmWI/EBADQDAAAA.Deify:BAABLgAECn8VAAMGAAYJIhs0MgCTAQAGAAYJIhs0MgCTAQAFAAEJlQ13ngAyAAAAAA==.Deifyh:BAAALgAECgIJAgAAAA==.Deliaz:BAAALgADCggJIAAAAA==.Deltaz:BAAALgADCgEJAQAAAA==.Demønknight:BAAALgADCgkJCQAAAA==.Derek:BAAALgADCgIJAgAAAA==.Devoidh:BAABLgAECn8pAAIhAAgJFSGRAgDMAgAhAAgJFSGRAgDMAgAAAA==.',
Di='Dinadan:BAAALgAECgMJAwABLgAECggJJQAhAMwPAA==.Dindu:BAAALgAECgEJAQAAAA==.Dirge:BAAALgADCgcJFQAAAA==.Dirtybob:BAAALgADCgkJDgAAAA==.Disastros:BAAALgAECgQJBgAAAA==.Discosisqo:BAAALgAECgUJCwAAAA==.Divinebeef:BAAALgAECgEJAgAAAA==.',
Dj='Djapana:BAABLgAECn8WAAIZAAYJ1xKGHgAIAQAZAAYJ1xKGHgAIAQAAAA==.Djavolo:BAAALgAECgIJAwAAAA==.',
Dn='Dnomm:BAAALgADCggJIAAAAA==.',
Do='Dodjy:BAAALgAECgQJDAAAAA==.Donussy:BAAALgADCgMJAwAAAA==.Dopeyplane:BAAALgAECgIJAgAAAA==.Dowob:BAAALgAECgMJBwABLgAFFAIJBAAKAAAAAA==.',
Dr='Dracheal:BAAALgAECgEJAQAAAA==.Dracknstoob:BAABLgAECn8lAAQXAAgJKhB/CwCVAQAXAAgJKhB/CwCVAQAYAAIJFQfgEgBeAAAJAAIJDgRuVQBFAAAAAA==.Dragidy:BAAALgADCgQJBAAAAA==.Dragondaddy:BAAALgADCgUJBQAAAA==.Dragonfyre:BAAALgADCgEJAQAAAA==.Dragongirlqt:BAAALgAECgEJAQABLgAECgkJJQAIAGodAA==.Dreaddlord:BAAALgAECgUJCQAAAA==.Dreadiedude:BAABLgAECn8mAAITAAgJxRNlFACeAQATAAgJxRNlFACeAQAAAA==.Drowlie:BAAALgADCgMJBAABLgAECgYJEQAKAAAAAA==.Drpwnface:BAAALgADCgUJBQAAAA==.',
Dt='Dtree:BAAALgAFFAEJAwAAAA==.',
Du='Duardin:BAAALgAECgIJAgAAAA==.Dureth:BAAALgAECgIJAgAAAA==.Dusktoday:BAAALgAECgEJAQAAAA==.Dutchman:BAABLgAECn8bAAIUAAYJ8BKMDABAAQAUAAYJ8BKMDABAAQAAAA==.',
Dw='Dwaka:BAECLgAFFH8fAAMJAAgJmBtIAgBFAgAJAAgJKBpIAgBFAgAYAAUJ9xyFAADiAQAuAAQKfxUAAxgACAkEIYQHAHMCABgABgnEJYQHAHMCAAkABgnzGxAYABICAAEuAAUUCAkpAAkAliMA.',
['Dë']='Dëathvader:BAAALgADCgYJEgAAAA==.',
['Dø']='Døden:BAABLgAECn8bAAIgAAgJuRU7AwDmAQAgAAgJuRU7AwDmAQAAAA==.',
Eb='Ebonflow:BAAALgADCgQJBAAAAA==.',
Ed='Edgestreak:BAAALgAECgEJAQAAAA==.Edricas:BAAALgAECgEJAQAAAA==.',
Ei='Eio:BAAALgAECgEJAQAAAA==.',
El='Eleice:BAAALgAECgIJAgAAAA==.Elele:BAAALgAECgYJDAAAAA==.Eleshock:BAACLgAFFH8OAAIFAAUJGR6qBgCqAQAFAAUJGR6qBgCqAQAuAAQKfxYAAgUACAnTHa8PAJoCAAUACAnTHa8PAJoCAAAA.Elizan:BAAALgAECgQJBAAAAA==.Ellell:BAAALgAECgQJBgAAAA==.Ellieb:BAABLgAECn8lAAITAAkJfhWTCwAQAgATAAkJfhWTCwAQAgAAAA==.Ellinah:BAAALgAECgcJDQABLgAFFAMJAwAKAAAAAA==.Elshaddai:BAAALgAECgcJEQAAAA==.',
Em='Emsulquiorra:BAABLgAECn8WAAINAAgJKxzqJAARAgANAAgJKxzqJAARAgAAAA==.',
En='Endersfault:BAABLgAECn8fAAIiAAkJKCITAwChAgAiAAkJKCITAwChAgAAAA==.Englaived:BAAALgAECgUJEgAAAA==.Enmebaragesi:BAAALgAECggJDwAAAA==.Enve:BAABLgAECn8VAAMHAAcJNQxgaQDJAAAjAAUJrQsCSQDOAAAHAAYJoAlgaQDJAAABLgAECgkJFQAeAIcQAA==.',
Ep='Epicdemoness:BAAALgAECgEJAQAAAA==.',
Er='Eremano:BAAALgAECgQJCgAAAA==.',
Eu='Euphea:BAAALgAECgMJBAAAAA==.Euustace:BAAALgAECgYJCAAAAA==.',
Ev='Evokunt:BAAALgADCgEJAQAAAA==.',
Ex='Extintion:BAACLgAFFH8FAAIeAAIJqgUTgwCMAAAeAAIJqgUTgwCMAAAuAAQKfykAAh4ACQl2FIQhAAECAB4ACQl2FIQhAAECAAAA.Extratusks:BAAALgAECgEJAQAAAA==.',
Fa='Faartwizard:BAAALgAECgQJBwAAAA==.Fabe:BAEBLgAECn80AAIMAAcJqR8uCQATAgAMAAcJqR8uCQATAgAAAA==.Falion:BAACLgAFFH8NAAILAAQJ2R3ZAwBQAQALAAQJ2R3ZAwBQAQAuAAQKfyoAAwsACAkPJD8EANQCAAsACAkPJD8EANQCACQAAQnnBj1YADEAAAAA.Fanks:BAAALgAECgMJAwABLgAECgkJFQAeAIcQAA==.Fanny:BAAALgADCgEJAQAAAA==.Farkq:BAAALgADCgUJBQAAAA==.Farseer:BAABLgAECn8UAAIGAAcJER2eLAC0AQAGAAcJER2eLAC0AQAAAA==.Fatchina:BAAALgAECgYJBgAAAA==.Fatpandah:BAAALgAECgQJBgAAAA==.Fatrider:BAABLgAECn8eAAIPAAkJhhb4GAA0AgAPAAkJhhb4GAA0AgAAAA==.',
Fe='Fefetux:BAAALgADCgcJBwAAAA==.Felburn:BAAALgAECgEJBAAAAA==.Felicia:BAABLgAECn8eAAIjAAgJfyO7CgC1AgAjAAgJfyO7CgC1AgAAAA==.Fellordkiki:BAAALgAECggJEAAAAA==.Fenrig:BAEBLgAECn8YAAIiAAYJKhAxIQA1AQAiAAYJKhAxIQA1AQABLgAECgcJHAAWAIgPAA==.Ferrante:BAABLgAECn8zAAIeAAkJnQ+dKwDNAQAeAAkJnQ+dKwDNAQAAAA==.',
Fi='Figwigs:BAABLgAECn8hAAINAAgJDBFcPACzAQANAAgJDBFcPACzAQAAAA==.Filthymaje:BAAALgAECgIJAQAAAA==.Filthypally:BAACLgAFFH8KAAIPAAQJJRdnFwBMAQAPAAQJJRdnFwBMAQAuAAQKfzcAAg8ACQnUJQ8BAGwDAA8ACQnUJQ8BAGwDAAAA.Fishetbek:BAAALgAECgQJBAAAAA==.Fishingbot:BAAALgADCgEJAQAAAA==.Fister:BAAALgADCgIJAgABLgAECgQJBAAKAAAAAA==.Fistymonky:BAAALgADCgQJBgAAAA==.Fivëam:BAABLgAECn8ZAAIlAAgJUR8QAQBTAgAlAAgJUR8QAQBTAgAAAA==.',
Fl='Flashheart:BAAALgAECgYJCwAAAA==.Flashnlights:BAAALgAECgEJAQAAAA==.Fletchers:BAAALgAECgYJDQAAAA==.',
Fo='Foodoom:BAAALgAECgYJBgAAAA==.',
Fr='Fraerel:BAAALgAECgEJAQAAAA==.Françoise:BAAALgADCggJDAABLgAECgMJAwAKAAAAAA==.Freezefauker:BAABLgAECn8hAAINAAgJmA85QwCeAQANAAgJmA85QwCeAQAAAA==.Fridge:BAABLgAECn8jAAINAAgJfSCWFAB1AgANAAgJfSCWFAB1AgAAAA==.Frobrew:BAAALgADCgIJAQAAAA==.Frostsmash:BAABLgAECn8VAAMgAAgJyB7yAQC9AgAgAAgJyB7yAQC9AgAmAAEJ5ALyTwAVAAAAAA==.Frostxfury:BAABLgAECn8wAAIeAAcJmyG/GAA3AgAeAAcJmyG/GAA3AgAAAA==.Frostybunz:BAAALgADCggJDwAAAA==.Frostyshiver:BAABLgAECn8kAAINAAcJ+BsPKgD6AQANAAcJ+BsPKgD6AQABLgAFFAIJBAAKAAAAAA==.Frósty:BAAALgADCgMJBAAAAA==.Frøstynips:BAACLgAFFH8wAAIeAAYJbxyFCQC8AQAeAAYJbxyFCQC8AQAuAAQKf0UAAx4ACAkzJkoHAGcDAB4ACAkzJkoHAGcDACAABgnDIhkDAPEBAAAA.',
Fu='Funkymunky:BAAALgAECgMJAgAAAA==.Furrbulous:BAAALgADCgIJAgAAAA==.Furysgrip:BAACLgAFFH8IAAImAAMJEwj8FQCgAAAmAAMJEwj8FQCgAAAuAAQKfyMAAiYACAmdE3IRAFoBACYACAmdE3IRAFoBAAAA.',
Fy='Fyre:BAAALgADCgcJCwAAAA==.',
['Fí']='Fírnen:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúnk:BAABLgAECn8jAAQMAAkJ+xJYEACmAQAMAAkJGglYEACmAQADAAcJHhc2OQBoAQAEAAEJqQITlgAjAAAAAA==.',
Ga='Gaara:BAAALgADCgYJCAAAAA==.Galedrial:BAAALgADCgEJAQAAAA==.Garaktou:BAAALgAECgEJAQAAAA==.Garius:BAACLgAFFH8FAAIPAAIJDxOfQACrAAAPAAIJDxOfQACrAAAuAAQKfxsAAg8ACQlHHqUVAE0CAA8ACQlHHqUVAE0CAAAA.Gartah:BAAALgADCgIJAgABLgAECgQJBAAKAAAAAA==.Garthception:BAAALgAECgUJBQAAAA==.Gashweaver:BAAALgAECgMJAQAAAA==.',
Ge='Gentlegiantt:BAACLgAFFH8KAAITAAMJ/Q03GQDcAAATAAMJ/Q03GQDcAAAuAAQKfyQAAxMACAnbGCIRAMMBABMACAnbGCIRAMMBAB0AAQkAAGAwADQAAAAA.Gentlemonstr:BAAALgAFFAEJAQAAAA==.',
Gh='Ghood:BAAALgADCgMJAwAAAA==.',
Gi='Gigit:BAAALgAECgYJEwAAAA==.Giji:BAABLgAECn8dAAIGAAcJPBVqGQCDAQAGAAcJPBVqGQCDAQAAAA==.Gingersnapss:BAAALgAECgYJEgAAAA==.Girlsdayoni:BAAALgADCgcJBwAAAA==.',
Gl='Glizzyblasta:BAAALgADCgcJBwAAAA==.',
Gn='Gnimble:BAABLgAECn8WAAICAAgJdxrJEwDAAQACAAgJdxrJEwDAAQAAAA==.Gnuh:BAAALgAECgEJAQABLgAECgQJBwAKAAAAAA==.',
Go='Gohan:BAABLgAECn8SAAIDAAYJ1x9oUgBxAQADAAYJ1x9oUgBxAQAAAA==.Goku:BAAALgAECgMJBgABLgAECgYJEgADANcfAA==.Gommo:BAABLgAFFH8FAAIPAAMJNQIAOgDCAAAPAAMJNQIAOgDCAAAAAA==.Gooblento:BAABLgAECn8kAAIPAAgJphnAJADwAQAPAAgJphnAJADwAQAAAA==.Gorbad:BAAALgAECggJEwAAAA==.Gotwood:BAAALgAECgEJAQAAAA==.',
Gr='Grahamington:BAAALgAECgUJCwAAAA==.Grandmaster:BAAALgAECgcJDgAAAA==.Grapes:BAAALgAECgcJEwAAAA==.Grayfang:BAAALgADCgYJAQAAAA==.Greatranger:BAAALgAECgMJAwAAAA==.Grimmic:BAAALgADCgIJAgAAAA==.Groovywar:BAAALgAECgIJAgAAAA==.Groundizzle:BAABLgAECn8hAAILAAgJ+BlMDwD0AQALAAgJ+BlMDwD0AQAAAA==.',
Gu='Guineamon:BAABLgAECn8eAAMkAAgJnxJoEQDBAQAkAAgJnxJoEQDBAQALAAEJcwTjhAAsAAAAAA==.',
Gw='Gwwalker:BAAALgAECgcJCwAAAA==.',
Gz='Gzul:BAAALgAECgEJAgAAAA==.',
['Gô']='Gôof:BAAALgADCggJCQAAAA==.',
Ha='Haerinm:BAAALgAECgcJDQAAAA==.Haj:BAAALgAECgEJAgAAAA==.Hammel:BAAALgAECgkJCgAAAA==.Hanzxo:BAAALgAECgYJBwAAAA==.Harry:BAABLgAECn8oAAINAAgJxSKsDQCwAgANAAgJxSKsDQCwAgAAAA==.Harryrox:BAAALgADCgYJBgAAAA==.Haruk:BAABLgAECn8tAAIBAAkJMCB/AgArAwABAAkJMCB/AgArAwAAAA==.Hatememore:BAAALgAECgEJAgAAAA==.Hazchum:BAAALgADCgQJAgAAAA==.',
He='Heatfist:BAABLgAECn8oAAIlAAkJ7w5VAgDOAQAlAAkJ7w5VAgDOAQAAAA==.Hellhost:BAABLgAECn8hAAMgAAgJphZPBACsAQAgAAgJphZPBACsAQAeAAIJPwMN0wBKAAAAAA==.Hertfor:BAAALgAECgEJAQAAAA==.Heåls:BAABLgAECn8jAAIBAAcJahtSHgAkAgABAAcJahtSHgAkAgAAAA==.',
Hi='Hisoka:BAAALgAECgQJCwABLgAECgUJDQAKAAAAAA==.',
Ho='Hoboface:BAAALgAECgcJCQAAAA==.Hoelishock:BAABLgAECn8ZAAIBAAgJPh6YOQCUAQABAAgJPh6YOQCUAQAAAA==.Hollynova:BAABLgAECn8gAAMkAAgJGxYbDgDvAQAkAAcJWRgbDgDvAQALAAEJZwY+TwAvAAABLgAECgkJLAAJAGsNAA==.Holyreimer:BAAALgADCgcJAwAAAA==.Honeydew:BAACLgAFFH8XAAICAAYJhxkRBQDlAQACAAYJhxkRBQDlAQAuAAQKfx8AAgIACQkLHeIFAAEDAAIACQkLHeIFAAEDAAAA.Hotteemie:BAAALgADCggJDgAAAA==.',
Hr='Hrkz:BAAALgAECgIJAwABLgAECgYJDQAKAAAAAA==.',
Hy='Hydrastrider:BAAALgADCgEJAgAAAA==.Hydraxius:BAAALgAECgEJAgAAAA==.Hylingaar:BAAALgADCgQJBgABLgAECgYJBwAKAAAAAA==.Hyoinmaru:BAAALgADCgEJAQAAAA==.',
['Hâ']='Hârry:BAAALgAECggJCAAAAA==.',
Ia='Iamokuz:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.',
Ic='Icevoker:BAECLgAFFH8WAAMYAAQJuRYaAwAKAQAYAAMJ5RcaAwAKAQAJAAIJ1hT1KgCeAAAuAAQKfz0ABBgACQljH8ICAP8CABgACAkWIMICAP8CAAkAAgkAESpGAH0AABcAAQlNA+xKACwAAAAA.Iceyq:BAAALgAECgQJBwAAAA==.',
If='Ifloat:BAAALgAECgYJBgABLgAECggJGgAhAHMbAA==.',
Ig='Igni:BAAALgAECgcJEQAAAA==.',
Ii='Iilliidann:BAAALgADCgEJAQAAAA==.',
Il='Ilioa:BAAALgADCggJGwAAAA==.',
Im='Immortus:BAAALgADCgUJBQABLgAECgcJAgAKAAAAAA==.Imsteve:BAAALgAECgQJCwAAAA==.Imugi:BAABLgAECn8YAAIJAAgJjQyIKQByAQAJAAgJjQyIKQByAQAAAA==.',
In='Interia:BAAALgAECgYJEQABLgAECgcJHgAXABIYAA==.Intress:BAAALgADCgIJAgAAAA==.',
Io='Ionsw:BAAALgAECgQJCwAAAA==.',
Ir='Ironski:BAAALgADCgEJAQABLgAECggJGgAeAOYgAA==.',
Is='Ishgard:BAAALgADCgcJCAAAAA==.Isopentene:BAAALgAECgMJAwAAAA==.',
It='Itchystrasz:BAAALgAECgEJAQAAAA==.',
Iu='Iudex:BAAALgAECgIJAgAAAA==.',
Iv='Ivalace:BAAALgAECgkJAQAAAA==.Ivyoxide:BAAALgAECgYJEgAAAA==.',
Ja='Jacabon:BAAALgADCgQJBwAAAA==.Jackillz:BAABLgAECn8aAAMCAAYJzh1aIQCoAQACAAUJ6R1aIQCoAQAVAAUJpg8zOgA0AQAAAA==.Jackpriest:BAAALgAFFAEJAQAAAA==.Jadè:BAAALgADCgYJBwABLgAECgUJCQAKAAAAAA==.Jagalr:BAAALgADCgYJBgAAAA==.Jarok:BAAALgAECggJDQAAAA==.',
Jb='Jbhunna:BAAALgAECgUJCwAAAA==.',
Je='Jee:BAABLgAECn8gAAIaAAgJ4QzHHwBtAQAaAAgJ4QzHHwBtAQAAAA==.Jellypriest:BAAALgAECgEJAQAAAA==.Jenish:BAAALgAECgEJAQAAAA==.Jescon:BAAALgAECggJCgAAAA==.Jeteil:BAAALgADCgEJAQABLgAECgkJJQATAH4VAA==.Jexs:BAAALgAECgUJCQAAAA==.',
Ji='Jiamil:BAAALgAECgMJBAAAAA==.Jiayu:BAAALgADCgEJAQAAAA==.Jibberwish:BAAALgADCgcJDAABLgAECggJIwAeAHMhAA==.Jics:BAAALgAECgEJAgAAAA==.',
Jo='Jojoburn:BAAALgAECgEJAgAAAA==.Jojokiller:BAAALgAECgEJAgAAAA==.Jojoshock:BAAALgAECgEJAQAAAA==.Jolteon:BAAALgADCgcJDQAAAA==.Jorkin:BAAALgAECgEJAQAAAA==.',
Ju='Juanster:BAAALgADCgcJBwAAAA==.Jubber:BAABLgAECn8jAAMeAAgJcyEiEQB0AgAeAAgJZSEiEQB0AgAmAAYJZxlFFADMAQAAAA==.Jumpnglide:BAAALgAECgMJBgAAAA==.Justaliltren:BAAALgAECgkJBwAAAA==.',
Jx='Jxidyn:BAAALgAECgYJCAAAAA==.',
Jy='Jynx:BAABLgAECn8lAAIHAAkJ4yEvBADzAgAHAAkJ4yEvBADzAgAAAA==.',
['Jø']='Jøzzy:BAAALgADCgUJBQAAAA==.',
Ka='Kaherd:BAABLgAECn81AAIaAAcJ8A6OIwBTAQAaAAcJ8A6OIwBTAQAAAA==.Kahora:BAAALgADCgcJCgAAAA==.Kallavan:BAAALgADCgEJAQAAAA==.Kalmonk:BAABLgAECn8yAAMCAAkJYBaaDAAgAgACAAkJYBaaDAAgAgAWAAIJyQxwewBXAAAAAA==.Kalmyth:BAAALgADCgYJBgABLgAFFAMJAwAKAAAAAA==.Kaltizdat:BAAALgADCgcJBwABLgAECgQJCAAKAAAAAA==.Karytheca:BAAALgADCgIJAgAAAA==.Kasadori:BAAALgADCgcJCQAAAA==.Kasualz:BAAALgAECgcJEQAAAA==.Kayrali:BAAALgADCgMJBAAAAA==.Kazsham:BAAALgAECgQJCQAAAA==.',
Kb='Kboomz:BAAALgAECgUJBgAAAA==.',
Kd='Kdvt:BAACLgAFFH8KAAINAAQJ5wcBOwAjAQANAAQJ5wcBOwAjAQAuAAQKfxcAAg0ACAleHHNkAA8CAA0ACAleHHNkAA8CAAEuAAUUBQkSAA0A1AwA.',
Ke='Keedrimath:BAAALgAECgYJBgAAAA==.Keenagon:BAAALgADCgcJBwAAAA==.Kelf:BAAALgADCgcJCgAAAA==.Kellbow:BAAALgAECggJDQAAAA==.Kelynada:BAAALgADCgMJAwAAAA==.Keyevokey:BAAALgAECgEJAQAAAA==.',
Kh='Khaemset:BAAALgADCgkJCQAAAA==.',
Ki='Kieldaz:BAABLgAECn8lAAIhAAgJzA81CgAwAQAhAAgJzA81CgAwAQAAAA==.Kinore:BAAALgAECgQJBAAAAA==.Kirisute:BAABLgAECn8zAAINAAkJbyHsIADwAgANAAkJbyHsIADwAgAAAA==.Kitchenboss:BAABLgAECn8TAAINAAgJ1h0zdADqAQANAAgJ1h0zdADqAQAAAA==.Kithari:BAAALgAECgUJCwABLgAECggJJAACADQgAA==.',
Kn='Knickerbits:BAAALgADCgMJAwAAAA==.Knotting:BAABLgAECn8WAAISAAYJFRTrDABJAQASAAYJFRTrDABJAQAAAA==.',
Ko='Koll:BAAALgADCgIJAgAAAA==.Kollateral:BAABLgAECn83AAIIAAcJhxhXCQCxAQAIAAcJhxhXCQCxAQAAAA==.Kopara:BAAALgAECgcJEQAAAA==.Korell:BAAALgAECgEJAQABLgAECgcJDAAKAAAAAA==.Koriella:BAAALgAECgIJAgAAAA==.Kotetsu:BAAALgADCgUJBQAAAA==.',
Kr='Kraejekta:BAAALgAECgUJBQAAAA==.Krankiekunt:BAAALgAECgUJDAAAAA==.Krazmar:BAAALgADCgYJCwAAAA==.Kreigor:BAAALgADCgUJBQAAAA==.Krellhim:BAAALgAECgcJCwAAAA==.Krislocked:BAAALgAECgYJEQAAAA==.Krusper:BAAALgAECgQJBAAAAA==.',
Ku='Kungfused:BAAALgAECgQJBAAAAA==.',
Ky='Kyza:BAAALgAECggJDAAAAA==.',
La='Laaurge:BAAALgAECgUJBwAAAA==.Laceia:BAAALgADCgMJAwABLgAECgYJBwAKAAAAAA==.Landwalker:BAACLgAFFH8IAAIRAAMJsA3TJADCAAARAAMJsA3TJADCAAAuAAQKfyUAAhEABwkXIPQVABUCABEABwkXIPQVABUCAAAA.Langas:BAAALgAECgkJBgAAAA==.Latorius:BAAALgAECgkJEQAAAA==.Lazarian:BAAALgADCgUJDQABLgAECgkJDwAKAAAAAA==.Lazziel:BAABLgAECn8cAAINAAcJ0wROjgD2AAANAAcJ0wROjgD2AAAAAA==.',
Le='Leebear:BAAALgADCgEJAQAAAA==.Leilashte:BAAALgAECgcJEwAAAA==.Lenn:BAABLgAECn9HAAITAAgJLRG7FgCGAQATAAgJLRG7FgCGAQAAAA==.Letmesolodps:BAAALgAECgQJBgAAAA==.Lettucelordh:BAABLgAECn8fAAMYAAkJFB15AQB4AgAYAAgJmR15AQB4AgAJAAMJ0RZsLwDoAAAAAA==.Leyi:BAABLgAECn8gAAMOAAcJOBhrOwAeAgAOAAcJOBhrOwAeAgAQAAMJeguORQCfAAABLgAECggJIAAdAHUeAA==.Leyissa:BAABLgAECn8gAAIdAAgJdR7yBAAbAgAdAAgJdR7yBAAbAgAAAA==.',
Li='Liggma:BAABLgAECn8gAAMkAAcJGxncEgCvAQAkAAcJMBHcEgCvAQALAAYJBxr0FACvAQAAAA==.Lilfatty:BAAALgAECgEJAQABLgAECgkJCAAKAAAAAA==.Linkss:BAAALgADCgYJCwAAAA==.Linshadow:BAAALgAECgEJAQAAAA==.Litchblade:BAACLgAFFH8JAAIeAAQJrwVQRAAFAQAeAAQJrwVQRAAFAQAuAAQKfxYAAh4ACAkbFaFHAB0CAB4ACAkbFaFHAB0CAAAA.Litgoblin:BAAALgADCgEJAgAAAA==.Littlecoops:BAAALgADCgYJCAAAAA==.Livelord:BAAALgAECgEJAQAAAA==.',
Lo='Loalo:BAAALgADCgUJBQAAAA==.Locky:BAAALgAECgQJBgAAAA==.Lomzz:BAAALgAECgEJBQAAAA==.Loopy:BAAALgADCgEJAQAAAA==.Lootminator:BAAALgADCgQJBQAAAA==.Loptr:BAAALgADCgEJAQAAAA==.Lorelai:BAAALgADCgcJEQAAAA==.Lowkey:BAAALgAECgYJAgABLgAECgcJCAAKAAAAAA==.Lozza:BAAALgADCgQJBQAAAA==.',
Lu='Lucullus:BAAALgAECgYJCQAAAA==.Lukotii:BAAALgADCgkJAQAAAA==.Luminarus:BAAALgAECgQJBgAAAA==.Lurethuid:BAAALgAECgQJBAAAAA==.Luts:BAAALgADCgIJAgAAAA==.',
Ly='Lyd:BAABLgAECn8YAAMbAAcJ+wuuEQA1AQAbAAcJ+wuuEQA1AQAaAAMJhgGhmABeAAAAAA==.Lynarium:BAAALgAECgcJDgAAAA==.Lynnmage:BAAALgADCgQJBAAAAA==.Lynnoni:BAAALgADCggJDwAAAA==.',
['Lû']='Lûmiere:BAABLgAECn8ZAAIPAAgJYh9XOQA+AgAPAAgJYh9XOQA+AgAAAA==.',
Ma='Magharitta:BAABLgAECn8xAAIeAAkJOyE2DwCHAgAeAAkJOyE2DwCHAgAAAA==.Majicx:BAAALgAECgUJDAAAAA==.Malign:BAABLgAECn8WAAIOAAgJeQpdWQC8AQAOAAgJeQpdWQC8AQAAAA==.Malthayel:BAAALgAECgEJAQAAAA==.Manaseeker:BAAALgADCgkJDAAAAA==.Maraku:BAABLgAFFH8FAAMMAAMJvgggEQDoAAAMAAMJSwggEQDoAAADAAEJlwhvKgBNAAAAAA==.Masonic:BAABLgAECn8VAAMHAAYJrxDbRwAhAQAHAAYJrxDbRwAhAQAhAAIJpADhLAAtAAAAAA==.Mathdori:BAAALgAECgkJBgAAAA==.Matter:BAAALgAECgUJDAAAAA==.Maxxfury:BAAALgAECgYJAwAAAA==.',
Mc='Mcshok:BAAALgADCgcJCAAAAA==.',
Me='Medesin:BAAALgADCggJIAAAAA==.Medhic:BAAALgADCgIJAQAAAA==.Meirge:BAAALgAECgUJBQAAAA==.Mekhanite:BAABLgAECn8rAAImAAgJGyQ7AgDWAgAmAAgJGyQ7AgDWAgAAAA==.Memebeam:BAAALgAECgYJBwAAAA==.Memedemon:BAAALgAECgEJAQABLgAECgUJCQAKAAAAAA==.Mercykill:BAAALgADCgcJDAAAAA==.Mesmagius:BAAALgAECgUJBQAAAA==.Metasoul:BAABLgAECn8oAAIHAAkJlxX6FgAEAgAHAAkJlxX6FgAEAgAAAA==.',
Mi='Midknight:BAAALgAFFAIJAgAAAA==.Milfdella:BAABLgAECn8aAAIhAAgJcxskAwApAgAhAAgJcxskAwApAgAAAA==.Milspec:BAABLgAECn8dAAIaAAcJKh50FADIAQAaAAcJKh50FADIAQAAAA==.Minami:BAABLgAECn8nAAIPAAgJHSB0DgCLAgAPAAgJHSB0DgCLAgAAAA==.Minhiriath:BAABLgAECn8ZAAIeAAcJhhTWQgB0AQAeAAcJhhTWQgB0AQAAAA==.Mintbadger:BAAALgAECgcJCgAAAA==.Mistea:BAAALgAECgYJBgAAAA==.',
Mo='Modren:BAAALgAECgMJBgAAAA==.Mojo:BAAALgAECgkJCQAAAA==.Mold:BAAALgAECgMJAwAAAA==.Momotaku:BAABLgAECn8aAAMFAAgJ9xpZRABwAQAFAAgJ9xpZRABwAQAGAAIJWQdoewBXAAAAAA==.Monalisa:BAABLgAECn8bAAINAAcJVRj5OAC/AQANAAcJVRj5OAC/AQAAAA==.Monkecco:BAAALgAECgcJBQAAAA==.Monkgyatso:BAAALgAECgUJCwAAAA==.Monkhax:BAAALgADCgYJBQAAAA==.Monkow:BAAALgAECgQJCQAAAA==.Monne:BAAALgADCgYJBgABLgAECgkJJQATAH4VAA==.Monthax:BAAALgAECgIJAgAAAA==.Moomoos:BAABLgAECn82AAIIAAkJqRt6AwBoAgAIAAkJqRt6AwBoAgAAAA==.Moonoo:BAAALgADCgIJAgAAAA==.Moonsblades:BAAALgAECgEJAQAAAA==.Moonthorn:BAAALgAECgUJDwAAAA==.Morada:BAAALgAECgEJAQAAAA==.Mordok:BAAALgAECgEJAwAAAA==.Morena:BAAALgADCgMJBgAAAA==.Morgaina:BAABLgAECn8iAAIQAAcJkB0SAwAAAgAQAAcJkB0SAwAAAgAAAA==.Movski:BAABLgAECn8gAAQZAAYJyyCcHwD9AQAZAAYJYiCcHwD9AQAnAAQJxhf+DwAPAQAoAAMJbR2BCAD/AAAAAA==.Moñk:BAABLgAECn85AAMVAAgJ9hc9EgCkAQAVAAgJVBE9EgCkAQAWAAgJoRc0HQBKAQAAAA==.',
Ms='Msbearhaven:BAAALgADCgYJBgAAAA==.',
Mu='Multîpass:BAAALgADCgUJBQAAAA==.Murst:BAABLgAECn8dAAMOAAcJCx9zPwAPAgAOAAYJDSJzPwAPAgAQAAEJ/g+1YgBJAAAAAA==.',
My='Myeyeshurt:BAAALgAECgQJCwAAAA==.Mysterymeat:BAAALgADCgEJAQAAAA==.',
['Mä']='Mäya:BAAALgAECgUJDgAAAA==.',
['Më']='Mëmëmë:BAAALgAECgUJCgAAAA==.',
Na='Nahyeah:BAAALgAECgQJBAAAAA==.Natria:BAABLgAECn8rAAMYAAgJSRRxBACtAQAYAAgJSRRxBACtAQAJAAMJGgocTwCRAAAAAA==.Naw:BAAALgAECgYJCwAAAA==.Nayashka:BAAALgAECgUJDgAAAA==.',
Ne='Neeb:BAAALgAFFAIJBAAAAA==.Neebd:BAAALgAFFAEJAQABLgAFFAIJBAAKAAAAAA==.Nepth:BAABLgAECn8mAAIBAAgJqh96FABuAgABAAgJqh96FABuAgAAAA==.Nerfde:BAAALgAECgQJBAAAAA==.Nerfdelag:BAABLgAECn8ZAAIeAAgJXBnTcACmAQAeAAgJXBnTcACmAQAAAA==.Nerfgün:BAAALgAECgQJBAABLgAFFAMJAwAKAAAAAA==.',
Ni='Nihonshu:BAAALgADCgIJAQAAAA==.Niskus:BAAALgAECgYJEQAAAA==.Nixipixie:BAAALgADCgcJCAAAAA==.Nizan:BAAALgAECgQJBgAAAA==.Nizie:BAAALgADCgMJAgAAAA==.',
No='Nobbiepally:BAAALgAECgYJEwAAAA==.Nonono:BAAALgAECgMJBQAAAA==.Notagoblin:BAAALgAECgYJDQAAAA==.Notahealer:BAAALgAECgcJDwAAAA==.Notdahuntard:BAAALgAECgkJDgAAAA==.Notso:BAAALgAECgcJCwAAAA==.',
Np='Nps:BAAALgAECgUJDgAAAA==.',
Nr='Nragz:BAAALgAFFAEJAQAAAA==.',
Ns='Nsi:BAABLgAFFH8LAAIHAAMJCCN8JgAXAQAHAAMJCCN8JgAXAQAAAA==.',
Nu='Nulldeath:BAABLgAECn8UAAIeAAcJpCEyNQBiAgAeAAcJpCEyNQBiAgAAAA==.Nutsdormu:BAABLgAECn9EAAIXAAgJ5ROECADeAQAXAAgJ5ROECADeAQAAAA==.',
Ny='Nyssaela:BAAALgAECgUJBQAAAA==.Nyxmoona:BAAALgADCggJHgAAAA==.',
['Nà']='Nàishà:BAABLgAECn8mAAMLAAgJnBmkCQBPAgALAAgJnBmkCQBPAgAcAAYJKgVlQgDnAAAAAA==.',
Ob='Obskur:BAAALgAECgQJBAABLgAECgcJHgAXABIYAA==.',
Od='Odinwolf:BAABLgAFFH8LAAIFAAUJMB1wBQB1AQAFAAUJMB1wBQB1AQAAAA==.',
Og='Oggie:BAAALgAECgQJCwAAAA==.Oginn:BAAALgAECgQJBgAAAA==.',
Oh='Ohspeghettii:BAAALgADCgcJEAABLgAECgYJEQAKAAAAAA==.',
Oj='Ojisancage:BAABLgAECn8UAAIOAAgJ1REegABaAQAOAAgJ1REegABaAQAAAA==.',
On='Onepuff:BAABLgAECn8cAAINAAgJlRP+MgDUAQANAAgJlRP+MgDUAQAAAA==.Onism:BAAALgADCgkJDAAAAA==.',
Oo='Ooggabooga:BAAALgAECgEJAQAAAA==.',
Or='Orinys:BAABLgAECn80AAIXAAcJ0RMwCwCcAQAXAAcJ0RMwCwCcAQAAAA==.Orkky:BAABLgAECn8nAAImAAgJWiGVBgAvAgAmAAgJWiGVBgAvAgAAAA==.',
Pa='Packnwang:BAAALgADCgEJAQAAAA==.Page:BAACLgAFFH8FAAIZAAMJRg+rFAD1AAAZAAMJRg+rFAD1AAAuAAQKfx4AAhkACAm7GCoLAO4BABkACAm7GCoLAO4BAAAA.Pakurruun:BAAALgADCgcJFAAAAA==.Pallatress:BAAALgADCggJHQAAAA==.Panginoon:BAABLgAECn8lAAMeAAkJox/MJwCbAgAeAAgJjx/MJwCbAgAmAAcJqBfAHQBcAQAAAA==.Paphio:BAAALgAECgMJBgAAAA==.Papipalala:BAAALgAECgIJAgAAAA==.Pawadin:BAAALgAECgcJCQAAAA==.',
Pe='Pepapo:BAAALgAECgMJBwAAAA==.Pepio:BAAALgAECgMJBgABLgAECgQJBAAKAAAAAA==.Peppsi:BAAALgADCgcJDAAAAA==.Perden:BAAALgADCgMJAwAAAA==.',
Pg='Pgundry:BAAALgAECgMJAwAAAA==.',
Ph='Phakin:BAAALgADCgkJCQAAAA==.Phatboss:BAAALgAECgYJCwABLgAECggJEwANANYdAA==.Phayzedout:BAABLgAECn8cAAMeAAkJcBjLFgBFAgAeAAkJcBjLFgBFAgAgAAEJAAAlFgA4AAAAAA==.',
Pi='Pierat:BAAALgAECggJEQAAAA==.Piergeiron:BAAALgAECgcJDAAAAA==.Pinkrawr:BAAALgADCgMJAwAAAA==.Pinkwarrior:BAAALgAECgMJBQAAAA==.Pinkyblue:BAABLgAECn8dAAMOAAgJChtVPwAQAgAOAAgJChtVPwAQAgAQAAEJAAChbQA5AAAAAA==.Pipeppy:BAAALgADCgYJBgAAAA==.Pipssqeek:BAAALgAECgkJDQAAAA==.Pipung:BAAALgAECgQJBQAAAA==.',
Pl='Plarrior:BAAALgAFFAMJBAAAAA==.Plutô:BAAALgADCgYJDAAAAA==.',
Po='Poairua:BAAALgADCgEJAQAAAA==.Poda:BAAALgAECgEJAQAAAA==.Polloloco:BAAALgAECgQJBQAAAA==.Poobumhead:BAABLgAECn8uAAIOAAcJFRXrNgCJAQAOAAcJFRXrNgCJAQAAAA==.Potoro:BAAALgADCgIJAgAAAA==.Powzar:BAAALgAECgEJAwAAAA==.',
Pr='Praetorian:BAAALgAECgEJAgAAAA==.Priestmn:BAAALgAECgEJAQAAAA==.Probabely:BAAALgADCgEJAQABLgAFFAUJFAAeANoeAA==.Probably:BAACLgAFFH8UAAIeAAUJ2h77GgBtAQAeAAUJ2h77GgBtAQAuAAQKfykAAh4ACQn4JQ4SAA8DAB4ACQn4JQ4SAA8DAAAA.Prís:BAAALgAECgMJAwAAAA==.',
Pt='Ptree:BAAALgADCgcJBwABLgAFFAEJAwAKAAAAAA==.Ptreei:BAAALgAFFAEJAgABLgAFFAEJAwAKAAAAAA==.',
Pu='Puck:BAABLgAECn8XAAMYAAgJJxkXBgBxAQAYAAcJVRgXBgBxAQAJAAUJ1BKgMgA1AQAAAA==.Pudgeydk:BAAALgAECgEJAQAAAA==.Pudgeys:BAABLgAFFH8MAAIUAAQJKxsHAgBqAQAUAAQJKxsHAgBqAQAAAA==.Punj:BAAALgAECgcJCAABLgADCgYJBgAKAAAAAA==.Purdxpriest:BAAALgADCgQJAwABLgADCgcJCQAKAAAAAA==.Purdxwarlock:BAAALgADCgEJAQABLgADCgcJCQAKAAAAAA==.',
Py='Pyropuff:BAAALgADCgEJAQABLgAECgkJMwAhAAQgAA==.Pytranze:BAAALgAECgcJEgAAAA==.Pywarrior:BAAALgADCgEJAQAAAA==.',
Qo='Qoldia:BAAALgADCgYJBgAAAA==.',
Qu='Quarizma:BAACLgAFFH8aAAIEAAYJ2iRpAQASAgAEAAYJ2iRpAQASAgAuAAQKfzAAAgQACQkPJqUAABgDAAQACQkPJqUAABgDAAAA.',
Ra='Radiantbunz:BAAALgAECgQJBAAAAA==.Rajbl:BAAALgAECgYJDgAAAA==.Rampagefist:BAAALgADCgMJAwAAAA==.Randalor:BAAALgADCgYJCgAAAA==.Rano:BAAALgAECgYJCAAAAA==.Ravenknight:BAAALgAECgUJBQAAAA==.Rayningdeath:BAAALgAECgkJCAAAAA==.Rayá:BAAALgADCgcJCAAAAA==.',
Re='Reaperzx:BAAALgAECggJEQAAAA==.Reblle:BAAALgADCgIJAgAAAA==.Recks:BAAALgADCgEJAQAAAA==.Rejzo:BAAALgAECgMJBQABLgAECgcJAQAKAAAAAA==.Rejzogue:BAAALgAECgcJAQAAAA==.Rejzosun:BAAALgAECgMJAwAAAA==.Renavant:BAABLgAECn8ZAAIHAAcJVAxGSgAaAQAHAAcJVAxGSgAaAQAAAA==.Repliod:BAABLgAECn81AAMdAAgJ8iX2AAD5AgAdAAgJ8iX2AAD5AgASAAIJSQL4KgBvAAAAAA==.Restho:BAABLgAECn8WAAMFAAgJ9BimHQDEAQAFAAgJ9BimHQDEAQAGAAIJUAtkeABhAAAAAA==.Revarix:BAABLgAECn8dAAMgAAkJHxapAwBIAgAgAAkJHxapAwBIAgAeAAEJKAdgOAEgAAAAAA==.',
Rh='Rhaella:BAABLgAECn8iAAMBAAgJmBAlGwCwAQABAAgJmBAlGwCwAQAPAAQJAgdqsQCSAAAAAA==.Rhuiser:BAAALgAECgcJEAAAAA==.Rhéá:BAAALgAECgYJCwAAAA==.',
Ri='Riggerized:BAAALgAECgcJEQABLgAECgkJNgAIAKkbAA==.Rightmeow:BAAALgADCgYJBgAAAA==.Rilirian:BAAALgAECgkJDwAAAA==.Riseth:BAABLgAECn8pAAIGAAgJIyUFAwDmAgAGAAgJIyUFAwDmAgAAAA==.Riteboys:BAAALgAECgcJCAABLgAECggJDwAKAAAAAA==.Ritéboys:BAAALgAECgEJAgABLgAECggJDwAKAAAAAA==.Ritëboys:BAAALgAECgEJAQABLgAECggJDwAKAAAAAA==.Rivella:BAAALgAECgcJCQAAAA==.',
Ro='Rockmelons:BAAALgADCgEJAQAAAA==.Rockosocko:BAAALgADCggJEAAAAA==.Roflpwnnt:BAABLgAECn8pAAQMAAgJzxwXCgACAgAMAAgJbxcXCgACAgAEAAYJ6xSqQABXAQADAAIJhh/1rgBmAAAAAA==.Rolln:BAAALgADCggJCwAAAA==.Romanée:BAAALgAECgQJCgAAAA==.Rootdaddy:BAAALgADCgEJAQAAAA==.Rootweaver:BAAALgADCgYJBgAAAA==.Rousay:BAABLgAECn8ZAAIVAAgJmAayHQA2AQAVAAgJmAayHQA2AQAAAA==.',
Ru='Rusdar:BAAALgAECgMJAwABLgAECggJHQAaAKEDAA==.Rustylightz:BAAALgAECgQJBAAAAA==.Rutactic:BAAALgAECgMJAwAAAA==.Rutee:BAABLgAECn8wAAIPAAkJBRvbDwB9AgAPAAkJBRvbDwB9AgAAAA==.',
Ry='Ryn:BAABLgAECn8RAAIHAAcJVQQcnwDYAAAHAAcJVQQcnwDYAAAAAA==.Ryuk:BAAALgAECgYJEQAAAA==.',
['Rà']='Ràvon:BAAALgAECgMJAwAAAA==.',
Sa='Sabelin:BAAALgADCgEJAQABLgAECggJJAACADQgAA==.Safy:BAABLgAECn8kAAIWAAkJ7go0FQCSAQAWAAkJ7go0FQCSAQAAAA==.Saltyslug:BAAALgAECgUJDAAAAA==.Saltz:BAAALgAECgQJBAABLgAECgkJFQAeAIcQAA==.Sanctilaz:BAAALgAECgkJDwAAAA==.Sanosan:BAAALgAECgMJBgAAAA==.Saraedor:BAAALgADCgMJAwABLgAFFAMJAwAKAAAAAA==.Sartoc:BAAALgAFFAMJAwAAAA==.',
Sc='Scabbo:BAABLgAECn8fAAIQAAgJjxUNBADSAQAQAAgJjxUNBADSAQAAAA==.Scaleseeker:BAAALgADCgcJDQAAAA==.Scalesoul:BAAALgAFFAIJAgAAAQ==.Scarfeast:BAAALgADCgQJBAAAAA==.Scummbag:BAAALgAECgEJAwAAAA==.',
Sd='Sdfgoose:BAAALgAECgIJAgAAAA==.Sdw:BAAALgAECgEJAQABLgAECgEJAgAKAAAAAA==.',
Se='Sebille:BAABLgAECn8nAAINAAgJCR6ZLwC0AgANAAgJCR6ZLwC0AgAAAA==.Sebrogue:BAAALgAECgQJBwAAAA==.Seiferoth:BAAALgAECgEJAQABLgAFFAUJCwAFADAdAA==.Selais:BAABLgAECn8UAAIaAAYJLh0PIABrAQAaAAYJLh0PIABrAQAAAA==.Selunara:BAAALgADCgYJBgAAAA==.Selussa:BAAALgAECgYJBgABLgAFFAgJGAAHADEcAA==.Senddori:BAAALgAECgUJBQAAAA==.Sepl:BAAALgAECgYJCgAAAA==.Serana:BAAALgAECgUJBgAAAA==.Serasashrain:BAAALgADCgEJAQAAAA==.',
Sh='Shaddai:BAABLgAECn8pAAIIAAkJRxhWCgAqAgAIAAkJRxhWCgAqAgAAAA==.Shadowmaggot:BAAALgAECgcJCAAAAA==.Shadylock:BAAALgAECgMJBgAAAA==.Shadypally:BAAALgAECgYJBgAAAA==.Shakyrabbit:BAAALgADCgMJBAAAAA==.Shalash:BAAALgAECgQJBAAAAA==.Shamankiller:BAAALgAECgYJEQAAAA==.Shamannoodle:BAAALgADCgIJAgAAAA==.Shamitsdk:BAAALgADCgMJBgABLgAECgcJGAAFALUWAA==.Shamix:BAAALgADCgYJDAAAAA==.Shamlen:BAAALgAECgEJAQAAAA==.Shaniquasimo:BAABLgAECn8aAAIOAAgJ/x8oDACPAgAOAAgJ/x8oDACPAgAAAA==.Shaquiqui:BAAALgAECgIJAgAAAA==.Sharddaddy:BAAALgADCgIJAgAAAA==.Sharftay:BAAALgAECgYJEgABLgAFFAYJFwADAB4MAA==.Sharissa:BAAALgAECgYJDgAAAA==.Shatgun:BAAALgADCgcJBwAAAA==.Shinieedruid:BAAALgAECgMJAgABLgAECgkJIgAOANAbAA==.Shockedurmum:BAABLgAECn8WAAMUAAcJIhYlFgBcAQAUAAYJNA8lFgBcAQAGAAYJ+RmQRQAyAQAAAA==.Shocknôrris:BAAALgAECgYJEgAAAA==.Shouffle:BAAALgADCgcJBwAAAA==.',
Si='Sickomode:BAAALgADCgMJAwABLgAECgcJHgAXABIYAA==.Siferbooze:BAAALgADCgQJBAAAAA==.Silcy:BAAALgADCgMJAwAAAA==.Sillàrus:BAAALgAECgcJAgAAAA==.Silverspulse:BAABLgAECn80AAMLAAcJKx8SCgBHAgALAAcJKx8SCgBHAgAkAAQJrRoeLAA6AQAAAA==.Sinfulbeast:BAAALgAECgYJBgABLgAECggJLgAPAA4eAA==.Sinfulpally:BAABLgAECn8uAAIPAAgJDh4JGgAtAgAPAAgJDh4JGgAtAgAAAA==.Sippy:BAAALgAFFAIJAgABLgAFFAIJBwAeAG8SAA==.Sippycup:BAACLgAFFH8HAAIeAAIJbxIgdwCcAAAeAAIJbxIgdwCcAAAuAAQKfyMAAh4ACQnGH6gLAKwCAB4ACQnGH6gLAKwCAAAA.Sisisi:BAAALgAECgQJBwAAAA==.',
Sk='Skartos:BAAALgADCggJFwAAAA==.Skilledplaya:BAAALgAECgYJCQAAAA==.Skruffles:BAAALgAECgUJBQABLgAECgYJBgAKAAAAAA==.Skulv:BAACLgAFFH8LAAIHAAUJeyDdDwB4AQAHAAUJeyDdDwB4AQAuAAQKfzIAAgcACQlpJOABAEADAAcACQlpJOABAEADAAAA.Skum:BAAALgAECgEJAgAAAA==.Skunkdmeow:BAAALgAECgcJCgAAAA==.',
Sl='Slimygerald:BAAALgAECgIJAgAAAA==.Slopain:BAABLgAECn8XAAIhAAgJCRboBQCnAQAhAAgJCRboBQCnAQAAAA==.Slopflop:BAAALgADCgYJBgAAAA==.Slåppery:BAAALgAECgcJEgAAAA==.',
Sm='Smallarms:BAAALgAECgcJBQABLgAECgcJBgAKAAAAAA==.',
Sn='Sniickorzz:BAAALgAECgEJAgAAAA==.Snipereye:BAAALgAECgEJAQAAAA==.Snorlax:BAAALgAECgUJBQAAAA==.Snort:BAABLgAECn8jAAMBAAgJfiGsBADmAgABAAgJfiGsBADmAgAPAAcJrCFdGgArAgAAAA==.Snërt:BAAALgAECgYJCgAAAA==.',
So='Sonotafurry:BAAALgAECgUJDQAAAA==.Soojung:BAAALgAECgEJAQAAAA==.Soova:BAAALgAECgYJDQAAAA==.Sorcus:BAAALgAECgUJDwAAAA==.Soreknees:BAAALgADCgEJAQAAAA==.Souliuge:BAAALgADCgMJAwAAAA==.Soundface:BAABLgAECn8jAAIGAAYJVyBQGQCEAQAGAAYJVyBQGQCEAQAAAA==.',
Sp='Sparkysteve:BAABLgAECn8bAAMGAAgJ6CBjEAClAgAGAAgJ6CBjEAClAgAFAAIJnA0WmgA5AAAAAA==.Spelcastndog:BAACLgAFFH8HAAINAAMJ/AupTgDoAAANAAMJ/AupTgDoAAAuAAQKfyoAAg0ACAlIG9AgACcCAA0ACAlIG9AgACcCAAAA.Spindrift:BAABLgAECn8cAAIBAAgJjSGeBADoAgABAAgJjSGeBADoAgAAAA==.Spinypubes:BAAALgAECgMJBQAAAA==.Spiritfuzz:BAAALgAECgQJBAABLgAFFAQJCQAeAK8FAA==.Spiritrez:BAAALgADCgYJAwABLgAECgEJAQAKAAAAAA==.Spodermin:BAAALgADCgEJAQAAAA==.Spoonyy:BAAALgAECggJEQAAAA==.Spukz:BAACLgAFFH8KAAIaAAMJ4hauGACmAAAaAAMJ4hauGACmAAAuAAQKfxYAAxoABgmCHx0UAMsBABoABgmCHx0UAMsBABsAAQk4D54/ADkAAAAA.Spunkmonk:BAAALgAECgEJAwAAAA==.',
St='Stabbyhunt:BAAALgAECggJAwAAAA==.Starstorm:BAAALgAECgEJAQAAAA==.Sterlybo:BAAALgAECgIJAwABLgAECgcJFgAPAM4YAA==.Stoneyboi:BAAALgADCgcJCQAAAA==.Stormwrath:BAAALgAECgYJEAAAAA==.Stoutbrew:BAAALgAECgYJDwAAAA==.Stuy:BAACLgAFFH8JAAIEAAMJgwr8DQDaAAAEAAMJgwr8DQDaAAAuAAQKfzEAAgQACAnGGioHAJoBAAQACAnGGioHAJoBAAAA.Stãria:BAABLgAECn8mAAIDAAgJIRHcJgC4AQADAAgJIRHcJgC4AQAAAA==.Stårlå:BAAALgADCgEJAgAAAA==.Stèpsis:BAAALgAECgEJAQAAAA==.Störme:BAAALgADCggJGQAAAA==.',
Su='Sugarburst:BAABLgAECn8YAAMUAAYJ2xk4CwBcAQAUAAYJ2xk4CwBcAQAFAAEJ7AGujAAgAAAAAA==.Sugmanutz:BAAALgAECgMJAwAAAA==.Sukmahdisc:BAABLgAECn8aAAIkAAkJLwzfIQCEAQAkAAkJLwzfIQCEAQAAAA==.Sulph:BAAALgADCgEJAQAAAA==.Supershy:BAAALgAECgEJAQAAAA==.Suppirin:BAAALgADCgYJCAAAAA==.Supprakus:BAABLgAECn8tAAIJAAgJKRtdCgAkAgAJAAgJKRtdCgAkAgAAAA==.Suspectsusan:BAAALgAECgEJAgAAAA==.Susuryss:BAAALgADCgUJBQAAAA==.',
Sv='Svendlemoon:BAABLgAECn8tAAISAAgJwhkaBAAyAgASAAgJwhkaBAAyAgAAAA==.',
Sw='Swak:BAABLgAECn8VAAIeAAgJQBOQLQDEAQAeAAgJQBOQLQDEAQAAAA==.Swaky:BAAALgADCgMJAwAAAA==.Sweaty:BAAALgADCgkJCQAAAA==.Swinginwilly:BAAALgAECgYJBgAAAA==.Swippy:BAAALgADCgQJBAAAAA==.Swirlo:BAABLgAECn8wAAIHAAkJdR39BQDLAgAHAAkJdR39BQDLAgAAAA==.Swirlyball:BAAALgADCgkJEQABLgAECgkJMAAHAHUdAA==.',
Sy='Syaphire:BAAALgAECgMJAwAAAA==.Syndeath:BAAALgADCgIJAgAAAA==.Synths:BAABLgAECn8dAAQkAAgJdhnTDgDkAQALAAgJ7xZSGgAJAgAkAAYJjRvTDgDkAQAcAAEJtAogYQA2AAAAAA==.',
['Sñ']='Sñort:BAAALgAECgcJDgAAAA==.',
['Sý']='Sýìvàñás:BAAALgAECgUJAQAAAA==.',
Ta='Taffyclown:BAABLgAECn8kAAICAAgJNCBsBQC5AgACAAgJNCBsBQC5AgAAAA==.Taharuot:BAAALgAECgQJBgAAAA==.Takahe:BAAALgADCgcJCAAAAA==.Talelm:BAAALgADCgEJAQAAAA==.Tallinor:BAABLgAECn8uAAMNAAcJKhB6UAB5AQANAAcJKhB6UAB5AQApAAQJhgc8CQDAAAAAAA==.Taumast:BAAALgAECgQJDAABLgAECggJIQALAPgZAA==.Tauter:BAAALgADCggJHgAAAA==.Tazzee:BAAALgAECgEJAQAAAA==.',
Te='Teeki:BAAALgADCgcJBwAAAA==.Teiresius:BAAALgADCgYJBgAAAA==.Telsda:BAAALgAECgEJAgAAAA==.Telsrok:BAAALgADCgUJBQAAAA==.Tempyst:BAABLgAECn8eAAMXAAcJEhhDEwAOAgAXAAcJEhhDEwAOAgAJAAYJzAzpMADhAAAAAA==.Tessdee:BAAALgAECgYJCQAAAA==.Tetactic:BAAALgADCgIJAgAAAA==.',
Th='Thalia:BAABLgAECn8mAAIIAAkJcx++AQC1AgAIAAkJcx++AQC1AgAAAA==.Thaytred:BAAALgAECgMJCAAAAA==.Thecheezels:BAAALgAECgIJAwAAAA==.Thegòòch:BAAALgADCgEJAQAAAA==.Thesean:BAAALgADCgcJBwAAAA==.Thevoice:BAAALgADCgQJBAAAAA==.Thomzhar:BAAALgAECgUJCwAAAA==.Thornir:BAAALgADCgEJAQABLgADCgMJBAAKAAAAAA==.Thors:BAAALgAECgYJCAAAAA==.Thraznith:BAAALgAECgUJDAAAAA==.Threeföld:BAAALgADCgYJBgABLgAFFAMJCAAPAGsRAA==.Throber:BAAALgADCgkJDAAAAA==.',
Ti='Tienchi:BAABLgAECn8iAAMVAAkJMRzqBgBdAgAVAAgJmx/qBgBdAgAWAAEJTASkYwA3AAAAAA==.Tierk:BAAALgAECgcJDAAAAA==.Tillyhunter:BAAALgADCgcJEQAAAA==.Timmyy:BAAALgAECggJDQAAAA==.Tinainverse:BAAALgADCgEJAQAAAA==.',
To='Tomatofarmer:BAAALgADCgUJBQAAAA==.Tormént:BAACLgAFFH8HAAIgAAIJCBbJAQCrAAAgAAIJCBbJAQCrAAAuAAQKf0IAAiAACQnbJC0AAFsDACAACQnbJC0AAFsDAAAA.Torvold:BAAALgAECgMJAwAAAA==.',
Tr='Transport:BAAALgAECgYJBQAAAA==.Traumatizer:BAABLgAECn8nAAIaAAgJ9BqoFwCqAQAaAAgJ9BqoFwCqAQAAAA==.Treehumpin:BAAALgAECgMJAwAAAA==.Tremorlover:BAAALgAECgIJBQAAAA==.Trogas:BAAALgAECgMJAwAAAA==.Tronix:BAABLgAECn8bAAIDAAkJXR6uBQDYAgADAAkJXR6uBQDYAgAAAA==.Tronixs:BAAALgAECgEJAQABLgAECgkJGwADAF0eAA==.Trucidario:BAAALgAECgUJDQAAAA==.Trulsdk:BAAALgAECgQJCQABLgAECgYJBwAKAAAAAA==.Truwar:BAAALgAECgYJBwAAAA==.',
Tu='Turtlewave:BAAALgAECgUJAgAAAA==.',
Tw='Twiganomicon:BAAALgAECgEJAQAAAA==.Twiggz:BAABLgAECn8cAAIDAAcJUgZmYQDsAAADAAcJUgZmYQDsAAAAAA==.Twinkleface:BAAALgAECgQJBAAAAA==.',
Ty='Tylund:BAABLgAECn88AAIDAAkJ/RFeJgC6AQADAAkJ/RFeJgC6AQAAAA==.Tyrilara:BAAALgADCgUJCAAAAA==.Tyruu:BAAALgAECgYJBwAAAA==.',
['Tâ']='Tânk:BAAALgAECgEJBQAAAA==.',
['Tï']='Tïm:BAAALgAECgMJAwABLgAECggJDQAKAAAAAA==.',
Ul='Ultimatdeath:BAAALgAECgkJAQAAAA==.',
Un='Unholykníght:BAAALgADCgEJAQAAAA==.',
Ur='Uratowel:BAAALgADCgEJAQAAAA==.',
Va='Valaya:BAAALgAECgYJDAAAAA==.Valcaris:BAABLgAECn8UAAIlAAgJhgwiBABXAQAlAAgJhgwiBABXAQAAAA==.Valdr:BAAALgAECgQJBAABLgAFFAQJCAAdADkVAA==.Valentine:BAABLgAECn8WAAINAAkJXhN8HQA5AgANAAkJXhN8HQA5AgAAAA==.Valex:BAAALgAECgEJAQAAAA==.Valithor:BAAALgAECgcJCAAAAA==.Vampaph:BAAALgADCgEJAQAAAA==.',
Ve='Velarose:BAAALgAECgYJEwAAAA==.Velarrine:BAAALgADCgYJBgAAAA==.Veledor:BAAALgADCgEJAQAAAA==.Velenair:BAABLgAECn8ZAAMkAAYJWxSeGQBlAQAkAAYJWxSeGQBlAQAcAAQJ5BB/KwDvAAABLgAECgcJBgAKAAAAAA==.Velenlerolan:BAABLgAECn8dAAIeAAcJehuULQDEAQAeAAcJehuULQDEAQAAAA==.Velicelia:BAAALgAECgQJBQAAAA==.Velthara:BAABLgAECn8kAAIPAAkJ6hloGQAxAgAPAAkJ6hloGQAxAgAAAA==.Velzan:BAAALgAFFAEJAgAAAA==.Verailde:BAAALgADCgcJCAAAAA==.Verathos:BAAALgADCgIJAgAAAA==.Vergil:BAAALgAFFAIJAwAAAA==.Verilence:BAABLgAECn8lAAMfAAgJPSVrAABYAwAfAAgJPSVrAABYAwAOAAEJ+wd4JAEtAAAAAA==.Verks:BAAALgADCgYJBgABLgAECgUJCQAKAAAAAA==.Vext:BAAALgAECggJCAAAAA==.',
Vi='Victar:BAAALgADCgMJAwAAAA==.Villios:BAAALgAECgcJEQAAAA==.',
Vo='Voidberg:BAAALgAECgUJBgABLgAFFAQJDAARAC8JAA==.Voidfondler:BAACLgAFFH8KAAIHAAQJNBn9GwA6AQAHAAQJNBn9GwA6AQAuAAQKfxUAAgcACAl5IocTAOMCAAcACAl5IocTAOMCAAAA.Voidgasm:BAAALgAECgMJBQAAAA==.Voidlocked:BAAALgAECgYJCwAAAA==.Vorndryad:BAAALgADCgYJBgAAAA==.',
Vy='Vynburn:BAABLgAECn8mAAINAAkJEhXMHQA3AgANAAkJEhXMHQA3AgAAAA==.Vynnaris:BAABLgAECn8bAAImAAgJmwejHgDNAAAmAAgJmwejHgDNAAAAAA==.',
['Vì']='Vìn:BAAALgAECgEJAgAAAA==.',
Wa='Wadadadadeng:BAAALgADCgYJCgAAAA==.Waise:BAAALgAECgEJAQAAAA==.Wakuja:BAAALgADCgYJBgABLgAFFAUJCwAFADAdAA==.Wallahi:BAAALgAECgUJDQAAAA==.Warriorlol:BAAALgADCgEJAQAAAA==.Warspear:BAAALgADCgEJAQAAAA==.Watson:BAABLgAECn8dAAINAAgJ5xHcOQC7AQANAAgJ5xHcOQC7AQAAAA==.Waveryy:BAAALgADCgYJCwAAAA==.',
We='Wehex:BAAALgADCgIJAgAAAA==.Wemblitz:BAAALgADCggJGgAAAA==.Weraise:BAAALgADCgcJBwAAAA==.Wesh:BAAALgAECgQJCwAAAA==.',
Wh='Whio:BAABLgAECn8ZAAMVAAgJ4BD2EwCRAQAVAAgJ4BD2EwCRAQACAAQJIQsVUACTAAAAAA==.',
Wi='Wildglaive:BAAALgADCgkJHQAAAA==.Windwankur:BAAALgAECgIJAgAAAA==.Wintersfence:BAAALgAECgYJEgAAAA==.',
Wo='Woshiwacky:BAAALgADCgcJCQAAAA==.',
Xa='Xaldrin:BAAALgADCgEJAQAAAA==.Xallatath:BAAALgAFFAEJAwAAAA==.Xanxes:BAAALgADCgIJAgAAAA==.',
Xe='Xenarn:BAEBLgAECn8cAAIWAAcJiA9iHQBJAQAWAAcJiA9iHQBJAQAAAA==.Xenoruin:BAABLgAECn8dAAIjAAgJug6zEQBtAQAjAAgJug6zEQBtAQAAAA==.Xerez:BAAALgADCgYJDAAAAA==.Xertzart:BAABLgAECn87AAIRAAgJdx8oCQC2AgARAAgJdx8oCQC2AgAAAA==.Xev:BAAALgADCgkJEgAAAA==.',
Xi='Ximigo:BAAALgAECgYJEgAAAA==.Xinrat:BAAALgAECgIJAgAAAA==.Xiongzzrwar:BAAALgAFFAEJAQABLgAFFAYJEgAZAO8YAA==.',
['Xê']='Xêv:BAAALgAFFAIJBAAAAA==.',
Ya='Yangdu:BAAALgADCgcJBwAAAA==.',
Yo='Yojambuh:BAAALgAECgMJBQAAAA==.Yondari:BAAALgAECgcJBgAAAA==.Yoyo:BAAALgAECgYJCgAAAA==.',
Yr='Yrugae:BAAALgADCgYJDgAAAA==.',
['Yõ']='Yõzõrã:BAAALgADCgcJCAAAAA==.',
Za='Zae:BAABLgAECn8ZAAIpAAYJqh7FAgANAgApAAYJqh7FAgANAgABLgAECgkJEQAKAAAAAA==.Zaeley:BAAALgAECgkJEQAAAA==.Zanisha:BAABLgAECn8sAAITAAcJsgQoLgDcAAATAAcJsgQoLgDcAAAAAA==.Zargrim:BAAALgAECgYJBgAAAA==.Zatasia:BAACLgAFFH8LAAICAAQJdg2pEgAEAQACAAQJdg2pEgAEAQAuAAQKfxQAAgIACQnJCkEeAFYBAAIACQnJCkEeAFYBAAAA.',
Ze='Zeddar:BAAALgAECgQJBAAAAA==.Zegion:BAABLgAECn8bAAMBAAYJCAqWVgAhAQABAAYJCAqWVgAhAQAPAAEJ3QN3WQElAAAAAA==.Zelendorm:BAABLgAECn8lAAIIAAkJah1xAwBpAgAIAAkJah1xAwBpAgAAAA==.Zelis:BAAALgADCgIJAgAAAA==.Zephyreus:BAAALgADCgkJFgAAAA==.Zerat:BAAALgAECgUJBQABLgAECgkJJQATAH4VAA==.Zeroth:BAAALgADCgcJCgAAAA==.Zezîma:BAAALgADCgYJBgAAAA==.',
Zi='Zingerböx:BAAALgADCgYJBgAAAA==.Zionara:BAAALgADCgUJBQABLgAFFAQJAQAKAAAAAA==.',
Zu='Zugzak:BAAALgAECgYJBgABLgAFFAIJAgAKAAAAAA==.Zunara:BAAALgADCgcJBwAAAA==.',
['Ãk']='Ãkillies:BAABLgAECn8dAAMaAAgJoQP3aAARAQAaAAgJbAP3aAARAQAbAAIJ9QIyRgArAAAAAA==.',
['År']='Årrow:BAAALgADCgMJAwAAAA==.',
['Ær']='Æries:BAAALgAECgIJAgAAAA==.',
['Îl']='Îllshot:BAAALgADCgcJBwAAAA==.',
['Ðo']='Ðomino:BAAALgAECgEJAQAAAA==.',
['ßa']='ßaccycønes:BAAALgAECgMJAwAAAA==.',
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

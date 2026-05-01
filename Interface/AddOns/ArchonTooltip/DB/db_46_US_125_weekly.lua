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

local lookup = {'Paladin-Holy','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Paladin-Protection','Evoker-Augmentation','Unknown-Unknown','Priest-Holy','Hunter-Survival','Mage-Frost','Warlock-Destruction','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warrior-Fury','Warrior-Arms','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','DemonHunter-Vengeance','DeathKnight-Frost','Warrior-Protection','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelas:BAACLgAFFH8HAAIBAAQJ9CGvBwBYAQABAAQJ9CGvBwBYAQAuAAQKfxUAAgEACAk+IzEMALkCAAEACAk+IzEMALkCAAEuAAUUBgkUAAIArh4A.Abemonkey:BAABLgAFFH8UAAICAAYJrh4+AQA5AgACAAYJrh4+AQA5AgAAAA==.',
Ac='Actaeus:BAABLgAECn8XAAMDAAcJ+htzLAABAgADAAYJQxxzLAABAgAEAAQJMRQqWADlAAAAAA==.',
Ad='Addelana:BAABLgAECn8WAAMFAAgJjxLcNQCsAQAFAAgJjxLcNQCsAQAGAAEJcwPfWQAkAAAAAA==.Adelyda:BAAALgAECgQJCAAAAA==.Adrasta:BAAALgAECgYJCAAAAA==.',
Ae='Aedrius:BAAALgAECgEJAQAAAA==.Aelador:BAAALgADCgMJBAAAAA==.Aelathe:BAAALgAECgEJAQAAAA==.Aerys:BAAALgAECgEJAQAAAA==.',
Af='Afewbeerz:BAAALgADCgMJAwAAAA==.Africandrake:BAAALgADCgYJBgAAAA==.',
Ah='Ahnkori:BAAALgAECgIJAgAAAA==.',
Ai='Aifik:BAAALgAECgEJAQAAAA==.',
Ak='Akey:BAABLgAECn8dAAIDAAgJ7Av4KQBtAQADAAgJ7Av4KQBtAQAAAA==.Akiller:BAAALgAECgMJBQAAAA==.',
Al='Alamal:BAAALgAECgEJAQAAAA==.Alamwah:BAACLgAFFH8JAAIHAAMJxBtqFwAYAQAHAAMJxBtqFwAYAQAuAAQKfx4AAgcABwmMHAwuAEQCAAcABwmMHAwuAEQCAAAA.Alanaz:BAAALgAECgcJCwAAAA==.Alaroo:BAAALgAECgYJCAAAAA==.Albinoslug:BAAALgADCgUJBQAAAA==.Aleine:BAABLgAECn80AAIIAAgJEg/dFACBAQAIAAgJEg/dFACBAQAAAA==.Aleio:BAAALgAECgIJAgAAAA==.Alessi:BAAALgAECgYJBgAAAA==.Alexrose:BAAALgADCgcJBwAAAA==.Alliete:BAAALgAECgEJAQABLgAECggJFwAJAIwMAA==.Alliyah:BAAALgAECgEJAgABLgAECgMJBgAKAAAAAA==.Aloine:BAABLgAECn8hAAILAAgJ8AY4HQAaAQALAAgJ8AY4HQAaAQAAAA==.Alphonze:BAAALgAECgIJAgAAAA==.Alynne:BAAALgADCgcJDQAAAA==.',
Am='Amelior:BAAALgADCgIJAgAAAA==.Amogus:BAAALgAECgcJDAAAAA==.Amorallan:BAAALgAECgQJBAAAAA==.Ampuzzible:BAABLgAECn8pAAILAAgJwhrDBwAyAgALAAgJwhrDBwAyAgAAAA==.',
An='Andju:BAAALgADCgMJAwAAAA==.Anhedonias:BAAALgAECgcJAQAAAA==.Animism:BAAALgADCgUJBQAAAA==.Anivar:BAAALgADCgcJBwAAAA==.Anneke:BAAALgADCgMJAwABLgAECggJFwAJAIwMAA==.Anyá:BAABLgAECn8fAAIMAAgJ9wgiDACcAQAMAAgJ9wgiDACcAQAAAA==.',
Ar='Arbitera:BAABLgAECn8dAAICAAgJZh/QAwCtAgACAAgJZh/QAwCtAgAAAA==.Arcaneth:BAAALgADCggJCAAAAA==.Arcette:BAAALgADCgkJHQAAAA==.Archmystique:BAABLgAECn8jAAINAAcJGBe3NwCIAQANAAcJGBe3NwCIAQAAAA==.Arcthane:BAAALgADCgQJBAABLgADCgkJHQAKAAAAAA==.Arkona:BAABLgAECn8UAAILAAYJyBlQIgDRAQALAAYJyBlQIgDRAQAAAA==.Arkzart:BAAALgAECgQJBAAAAA==.Arrogant:BAAALgAECgUJBwAAAA==.',
As='Asanath:BAAALgADCgkJDwAAAA==.Ashley:BAABLgAECn8lAAIDAAgJNyBlBgCRAgADAAgJNyBlBgCRAgAAAA==.Ashryveris:BAAALgAECgYJEgAAAA==.Asmonjoel:BAAALgAECgMJBgAAAA==.Assumi:BAAALgAECgYJDwAAAA==.',
At='Ataturk:BAAALgAECgUJDAAAAA==.Athenis:BAAALgAECgcJDgAAAA==.Atka:BAAALgADCgcJBwAAAA==.',
Au='Audree:BAAALgADCgEJAQAAAA==.Augiediaz:BAAALgAECgcJBwAAAA==.Auraine:BAAALgAECgcJCAAAAA==.Aurelionn:BAAALgAECgEJAgAAAA==.',
Av='Avadacadavra:BAAALgADCgUJBwAAAA==.',
Ax='Axonpredator:BAAALgADCgEJAQAAAA==.',
Az='Azamat:BAAALgAECgYJBwAAAA==.Azazêll:BAABLgAECn8YAAIOAAYJ9g3aCgD2AAAOAAYJ9g3aCgD2AAAAAA==.Azidian:BAAALgADCgEJAQAAAA==.Azmodais:BAAALgAECgIJAgAAAA==.Azuredemonx:BAABLgAECn8mAAIHAAcJ5xUUKQBCAQAHAAcJ5xUUKQBCAQAAAA==.Azurgosa:BAAALgADCgUJBQAAAA==.',
Ba='Baagul:BAAALgADCggJDQAAAA==.Badheals:BAABLgAECn8gAAQPAAgJaBfbKAAQAgAPAAgJaBfbKAAQAgAQAAIJXwetFgBwAAARAAMJLAanOQBfAAAAAA==.Balfin:BAAALgADCggJCAAAAA==.Balid:BAAALgADCggJCQAAAA==.Banan:BAAALgAECgUJCAAAAA==.Bazaseal:BAAALgAECgUJBgAAAA==.',
Bb='Bbqporkbuns:BAACLgAFFH8HAAISAAIJURZdBAC1AAASAAIJURZdBAC1AAAuAAQKfx4AAhIACQm6GbMDAPACABIACQm6GbMDAPACAAAA.',
Be='Beauranged:BAAALgAECgIJAgAAAA==.Bece:BAAALgADCgcJDgAAAA==.Beefcakes:BAAALgADCgEJAQAAAA==.Beenafflictn:BAAALgADCgEJAQAAAA==.Beerpong:BAABLgAECn8YAAMTAAYJtBBzPAAqAQATAAYJfw1zPAAqAQAUAAYJ3ArxTwAEAQABLgAECgkJEQAKAAAAAA==.Belevie:BAAALgADCgYJBgAAAA==.Bellanoth:BAABLgAECn8UAAQJAAkJ+AruFwA+AQAJAAgJJAnuFwA+AQAVAAcJUgT+EQDaAAAWAAIJNAUOFQAmAAAAAA==.Belledormi:BAABLgAECn8vAAMJAAgJfwsRGQA1AQAJAAgJfwsRGQA1AQAWAAEJ5QFSRQAhAAAAAA==.Bellfurion:BAAALgAECgQJCgAAAA==.Belltree:BAAALgADCgIJAgAAAA==.Bendyendy:BAAALgADCgYJBwAAAA==.',
Bf='Bfev:BAABLgAECn8gAAIXAAgJdx6JAwBnAgAXAAgJdx6JAwBnAgAAAA==.',
Bh='Bhad:BAAALgADCgMJAwAAAA==.',
Bi='Bid:BAABLgAECn8gAAIDAAcJWBpNIQCaAQADAAcJWBpNIQCaAQAAAA==.Bierfiendx:BAAALgAECgEJAQAAAA==.Bify:BAAALgADCgYJCAAAAA==.Bigalo:BAABLgAECn8gAAIMAAcJ9hJ2DQCIAQAMAAcJ9hJ2DQCIAQAAAA==.Bigcogg:BAAALgAECgQJBAAAAA==.Bigdikbusta:BAAALgAECgYJDwAAAA==.Biggesthighz:BAABLgAECn8ZAAIMAAgJNRDmCADUAQAMAAgJNRDmCADUAQAAAA==.Bigjer:BAACLgAFFH8KAAIYAAQJyxdRBwBaAQAYAAQJyxdRBwBaAQAuAAQKfxgAAhgACAmiIHsSALwCABgACAmiIHsSALwCAAAA.Bird:BAABLgAECn8YAAMJAAgJNCHpDQCXAgAJAAgJNCHpDQCXAgAVAAUJawyyLQAFAQAAAA==.Bisifix:BAAALgADCgEJAQAAAA==.',
Bl='Blaisy:BAABLgAECn8hAAILAAgJkxJbKwCbAQALAAgJkxJbKwCbAQAAAA==.Blakdynamite:BAAALgAECgQJBgAAAA==.Blayx:BAAALgADCgQJBAABLgAECgcJHAANAD8kAA==.Blerdsterm:BAABLgAECn8tAAMZAAkJ+x4/CQAaAgAYAAcJ8R9WIQBJAgAZAAkJ4Rw/CQAaAgAAAA==.Blitzz:BAAALgAECgQJBAAAAA==.',
Bo='Bofà:BAAALgAFFAEJAQAAAA==.Boogeyman:BAAALgAECgYJDgAAAA==.Boohbooh:BAAALgADCgUJBQAAAA==.Borgnine:BAAALgAECgkJEwAAAA==.',
Br='Brannie:BAABLgAECn8ZAAIaAAgJHgUYGAA9AQAaAAgJHgUYGAA9AQAAAA==.Brenine:BAABLgAECn8aAAQRAAcJwA+WFQBVAQARAAcJ8g6WFQBVAQAQAAMJxQ/RJwCPAAAbAAQJawQKKgBSAAAAAA==.Brila:BAAALgAECgkJDgAAAA==.Britneyfears:BAAALgAECgYJBQABLgAECgkJBgAKAAAAAA==.Brodess:BAACLgAFFH8JAAIGAAQJKiD7BQBnAQAGAAQJKiD7BQBnAQAuAAQKfyEAAgYACAnEJCMGADEDAAYACAnEJCMGADEDAAAA.Brody:BAABLgAECn8lAAIHAAkJoh1GAwDEAgAHAAkJoh1GAwDEAgAAAA==.Bromorc:BAAALgADCgcJHAAAAA==.Brox:BAAALgAECgMJBgAAAA==.',
Bs='Bse:BAAALgADCgYJBgAAAA==.',
Bu='Bubbleo:BAAALgAECgEJAgAAAA==.Budholy:BAAALgAECgEJAQAAAA==.Buggyhealz:BAACLgAFFH8QAAIPAAQJUB2zCQBmAQAPAAQJUB2zCQBmAQAuAAQKfykAAg8ACQmeJGgFADcDAA8ACQmeJGgFADcDAAAA.Bulimio:BAAALgAECgEJAQAAAA==.Bungeye:BAAALgAECgEJAQAAAA==.Bunzbunnie:BAAALgAECgQJCgAAAA==.Bunzbunny:BAAALgAECgMJAwAAAA==.Buratt:BAAALgADCgcJHAAAAA==.Burtmonklin:BAABLgAECn8bAAIUAAgJrSSzAwCIAgAUAAgJrSSzAwCIAgAAAA==.Busdriver:BAACLgAFFH8KAAIcAAQJqxjAFwBUAQAcAAQJqxjAFwBUAQAuAAQKfxkAAhwACAkMILwzAGgCABwACAkMILwzAGgCAAAA.Buster:BAAALgAECgEJAQAAAA==.Busterr:BAAALgAECgQJCwAAAA==.',
Ca='Caleroice:BAAALgAECgcJDgAAAA==.Capacitør:BAABLgAECn8fAAIGAAcJjR58CgDzAQAGAAcJjR58CgDzAQAAAA==.Cardib:BAABLgAECn8wAAQdAAgJzh7SHADHAQAdAAYJkR7SHADHAQAOAAYJ8xpeGgB6AQAeAAEJAAAnIABxAAAAAA==.Cartier:BAAALgADCgYJBgAAAA==.Cattabloom:BAAALgAECgEJAwAAAA==.Cattazap:BAABLgAECn8kAAMFAAgJnCQ+BAAwAwAFAAgJnCQ+BAAwAwAGAAMJvAsDeQBfAAAAAA==.',
Ce='Ceefu:BAAALgAFFAQJBAABLgAFFAUJCwAFAC0dAA==.Celtic:BAAALgAECgcJAQAAAA==.Cerran:BAAALgAECgEJAQAAAA==.',
Ch='Chakrakhan:BAAALgAECggJCQAAAA==.Char:BAAALgAECgYJDAAAAA==.Chase:BAABLgAECn8hAAIZAAgJWR6VBADyAQAZAAgJWR6VBADyAQAAAA==.Chopzuey:BAAALgADCgYJCAAAAA==.Chugtiki:BAABLgAECn8rAAMFAAkJuhwJAwDnAgAFAAkJuhwJAwDnAgAGAAUJSRD+VgDpAAAAAA==.',
Ci='Cinderaz:BAAALgADCgcJHAAAAA==.Ciyus:BAAALgAECgQJBQAAAA==.',
Cl='Clann:BAAALgAECgYJCwAAAA==.Clarissahh:BAAALgAECgQJCQAAAA==.',
Co='Coolrunnins:BAAALgAECggJEgAAAA==.Coolwhip:BAAALgAECgMJDQAAAA==.Coquin:BAAALgADCgEJAwAAAA==.Coquina:BAAALgAECgUJCwAAAA==.Cordeilia:BAACLgAFFH8NAAILAAQJEAj8CQDxAAALAAQJEAj8CQDxAAAuAAQKfzAAAgsACAmcIRsGAO0CAAsACAmcIRsGAO0CAAAA.Cosmi:BAAALgAECgYJDwABLgAFFAEJAQAKAAAAAQ==.Costiigan:BAAALgAECgUJCwAAAA==.',
Cr='Criznara:BAAALgAECgcJBgAAAA==.Crowlie:BAAALgAECgkJAwAAAA==.Cruxxi:BAABLgAECn8cAAMdAAgJBx4tJACDAgAdAAgJgB0tJACDAgAOAAQJWBxDJAA4AQAAAA==.',
Cu='Curthill:BAAALgAECgMJBAAAAA==.',
Cx='Cxaxukluth:BAAALgAECgYJDAABLgAFFAEJAQAKAAAAAQ==.',
Cy='Cyberdots:BAAALgAECgYJBQAAAA==.Cyenthea:BAAALgAECgcJDwABLgAFFAcJEwAHAH8fAA==.Cygeance:BAAALgADCgYJCQAAAA==.Cyklar:BAAALgADCgcJGQAAAA==.Cyphren:BAAALgAECgYJDwAAAA==.Cyrias:BAAALgADCgUJBQAAAA==.',
Da='Dacaille:BAAALgAECgYJCAAAAA==.Daddysouls:BAAALgAECgcJBwAAAA==.Dadingding:BAAALgAECgcJEgAAAA==.Damnflanders:BAAALgAECgYJDAAAAA==.Dankozdravic:BAAALgAECgMJBAAAAA==.Daqueta:BAAALgAECgYJCgAAAA==.Daquetamk:BAAALgAECgUJBgAAAA==.Daquetapl:BAAALgAECgIJAwAAAA==.Darkniggura:BAAALgAECggJEwAAAA==.Darknstormy:BAAALgAECgUJDQAAAA==.Darkpal:BAABLgAFFH8HAAIfAAMJqxLGGgAMAQAfAAMJqxLGGgAMAQAAAA==.Darkskye:BAAALgAECggJCgAAAA==.Darthbane:BAAALgAECgQJBAAAAA==.Dazer:BAAALgAECgEJAQAAAA==.Dazgrim:BAAALgAECgQJAwABLgAECgYJDQAKAAAAAA==.Dazrawr:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.',
De='Deadlobster:BAAALgADCgcJBwAAAA==.Deadnick:BAAALgAECggJCgAAAA==.Deathax:BAAALgADCggJDwAAAA==.Deathicus:BAAALgAECggJEwAAAA==.Decapitation:BAACLgAFFH8JAAIDAAMJZhJ5CwAGAQADAAMJZhJ5CwAGAQAuAAQKfycAAgMACAkwJJ0CAOwCAAMACAkwJJ0CAOwCAAAA.Deify:BAABLgAECn8VAAMGAAYJIhs1MgCTAQAGAAYJIhs1MgCTAQAFAAEJlQ1/ngAyAAAAAA==.Deifyh:BAAALgAECgIJAgAAAA==.Deliaz:BAAALgADCgcJHAAAAA==.Deltaz:BAAALgADCgEJAQAAAA==.Demønknight:BAAALgADCgkJCQAAAA==.Derek:BAAALgADCgIJAgAAAA==.Devoidh:BAABLgAECn8pAAIgAAgJFCGSAgDMAgAgAAgJFCGSAgDMAgAAAA==.',
Di='Dinadan:BAAALgAECgMJAwABLgAECgcJIAAgALEQAA==.Dindu:BAAALgAECgEJAQAAAA==.Dirge:BAAALgADCgcJFQAAAA==.Dirtybob:BAAALgADCgkJDgAAAA==.Disastros:BAAALgAECgQJBgAAAA==.Divinebeef:BAAALgAECgEJAgAAAA==.',
Dj='Djapana:BAABLgAECn8VAAIXAAYJABEZGgD/AAAXAAYJABEZGgD/AAAAAA==.Djavolo:BAAALgAECgIJAwAAAA==.',
Dn='Dnomm:BAAALgADCgcJHAAAAA==.',
Do='Dodjy:BAAALgAECgQJCgAAAA==.Donussy:BAAALgADCgMJAwAAAA==.Dopeyplane:BAAALgAECgIJAgAAAA==.Dowob:BAAALgAECgMJBwABLgAFFAEJAQAKAAAAAA==.',
Dr='Dracheal:BAAALgAECgEJAQAAAA==.Dracknstoob:BAABLgAECn8gAAMVAAcJMRI/CQCLAQAVAAcJMRI/CQCLAQAWAAEJYwPuFAAoAAAAAA==.Dragidy:BAAALgADCgQJBAAAAA==.Dragondaddy:BAAALgADCgUJBQAAAA==.Dragonfyre:BAAALgADCgEJAQAAAA==.Dragongirlqt:BAAALgADCggJDwABLgAECggJHQAIAN0eAA==.Dreaddlord:BAAALgAECgUJBgAAAA==.Dreadiedude:BAABLgAECn8dAAIRAAgJNBIdEQCGAQARAAgJNBIdEQCGAQAAAA==.Drowlie:BAAALgADCgMJBAABLgAECgYJEAAKAAAAAA==.',
Dt='Dtree:BAAALgAFFAEJAgAAAA==.',
Du='Duardin:BAAALgAECgIJAgAAAA==.Dureth:BAAALgAECgIJAgAAAA==.Durrin:BAAALgADCggJCgAAAA==.Dusktoday:BAAALgAECgEJAQAAAA==.Dutchman:BAABLgAECn8VAAISAAYJLQ2/CwAhAQASAAYJLQ2/CwAhAQAAAA==.',
Dw='Dwaka:BAECLgAFFH8aAAMJAAcJfxxAAQAuAgAJAAcJmBpAAQAuAgAWAAUJ9xyGAADiAQAuAAQKfxUAAxYACAkEIYIHAHMCABYABgnEJYIHAHMCAAkABgnzGxYYABICAAEuAAUUBwkhABYAASUA.',
['Dë']='Dëathvader:BAAALgADCgYJDQAAAA==.',
['Dø']='Døden:BAABLgAECn8XAAIhAAgJchXvAQAEAgAhAAgJchXvAQAEAgAAAA==.',
Eb='Ebonflow:BAAALgADCgQJBAAAAA==.',
Ed='Edgestreak:BAAALgAECgEJAQAAAA==.Edricas:BAAALgAECgEJAQAAAA==.',
Ei='Eio:BAAALgAECgEJAQAAAA==.',
El='Eleice:BAAALgAECgIJAgAAAA==.Elele:BAAALgAECgYJDAAAAA==.Eleshock:BAACLgAFFH8JAAIFAAQJVBuiDgD0AAAFAAQJVBuiDgD0AAAuAAQKfxYAAgUACAnTHbMPAJoCAAUACAnTHbMPAJoCAAAA.Elizan:BAAALgAECgQJBAAAAA==.Ellell:BAAALgAECgEJAQAAAA==.Ellieb:BAABLgAECn8dAAIRAAgJ1RUXDQC7AQARAAgJ1RUXDQC7AQAAAA==.Ellinah:BAAALgAECgcJDQABLgAECgkJCwAKAAAAAA==.Elshaddai:BAAALgAECgYJDAAAAA==.',
Em='Emsulquiorra:BAAALgAECgYJDgAAAA==.',
En='Endersfault:BAABLgAECn8dAAIiAAgJqiLLAQCpAgAiAAgJqiLLAQCpAgAAAA==.Englaived:BAAALgAECgUJEgAAAA==.Enmebaragesi:BAAALgAECggJDwAAAA==.Enve:BAABLgAECn8PAAMjAAYJhg0ASQDOAAAjAAUJqwsASQDOAAAHAAMJ8wt3wAB/AAABLgAECggJFAAcAA8SAA==.',
Ep='Epicdemoness:BAAALgAECgEJAQAAAA==.',
Er='Eremano:BAAALgAECgQJCgAAAA==.',
Eu='Euphea:BAAALgAECgMJBAAAAA==.Euustace:BAAALgAECgQJBAAAAA==.',
Ev='Evokunt:BAAALgADCgEJAQAAAA==.',
Ex='Extintion:BAABLgAECn8mAAIcAAgJ0xUtIADGAQAcAAgJ0xUtIADGAQAAAA==.Extratusks:BAAALgAECgEJAQAAAA==.',
Fa='Faartwizard:BAAALgADCgIJAgAAAA==.Fabe:BAEBLgAECn8mAAIMAAcJjxvZCQDEAQAMAAcJjxvZCQDEAQAAAA==.Falion:BAACLgAFFH8LAAILAAQJ2xzYAwBQAQALAAQJ2xzYAwBQAQAuAAQKfyoAAwsACAkSJFwCAOUCAAsACAkSJFwCAOUCACQAAQnnBjxYADEAAAAA.Fanks:BAAALgAECgIJAgABLgAECggJFAAcAA8SAA==.Fanny:BAAALgADCgEJAQAAAA==.Farkq:BAAALgADCgUJBQAAAA==.Farseer:BAABLgAECn8UAAIGAAcJER2gLAC0AQAGAAcJER2gLAC0AQAAAA==.Fatchina:BAAALgADCgUJBQAAAA==.Fatpandah:BAAALgAECgQJBgAAAA==.Fatrider:BAABLgAECn8eAAIfAAkJfha3DwBAAgAfAAkJfha3DwBAAgAAAA==.',
Fe='Fefetux:BAAALgADCgcJBwAAAA==.Felburn:BAAALgAECgEJBAAAAA==.Felicia:BAABLgAECn8XAAIjAAgJBSK9CgC1AgAjAAgJBSK9CgC1AgAAAA==.Fellordkiki:BAAALgAECggJCwAAAA==.Fenrig:BAEBLgAECn8YAAIiAAYJKhAwIQA1AQAiAAYJKhAwIQA1AQABLgAECgcJDgAKAAAAAA==.Ferrante:BAABLgAECn8wAAIcAAkJWg/RHQDVAQAcAAkJWg/RHQDVAQAAAA==.',
Fi='Figwigs:BAAALgAECggJEgAAAA==.Filthymaje:BAAALgAECgIJAQAAAA==.Filthypally:BAABLgAECn8tAAIfAAkJfSQXAQBOAwAfAAkJfSQXAQBOAwAAAA==.Fishetbek:BAAALgAECgQJBAAAAA==.Fishingbot:BAAALgADCgEJAQAAAA==.Fister:BAAALgADCgIJAgABLgAECgQJBAAKAAAAAA==.Fistymonky:BAAALgADCgQJBgAAAA==.Fivëam:BAABLgAECn8ZAAIlAAgJTx+tAABiAgAlAAgJTx+tAABiAgAAAA==.',
Fl='Flashheart:BAAALgAECgYJCwAAAA==.Flashnlights:BAAALgAECgEJAQAAAA==.Fletchers:BAAALgAECgYJDQAAAA==.',
Fo='Foodoom:BAAALgAECgYJBgAAAA==.',
Fr='Fraerel:BAAALgAECgEJAQAAAA==.Françoise:BAAALgADCggJDAABLgAECgMJAwAKAAAAAA==.Freezefauker:BAAALgAECgcJEwAAAA==.Fridge:BAABLgAECn8eAAINAAcJkyHTFQAtAgANAAcJkyHTFQAtAgAAAA==.Frobrew:BAAALgADCgIJAQAAAA==.Frostsmash:BAABLgAECn8VAAMhAAgJyB7yAQC9AgAhAAgJyB7yAQC9AgAmAAEJ5ALxTwAVAAAAAA==.Frostxfury:BAABLgAECn8iAAIcAAcJFSG1EgAkAgAcAAcJFSG1EgAkAgAAAA==.Frostybunz:BAAALgADCggJDwAAAA==.Frostyshiver:BAABLgAECn8bAAINAAcJoBi1KwC1AQANAAcJoBi1KwC1AQABLgAFFAEJAQAKAAAAAA==.Frósty:BAAALgADCgEJAgAAAA==.Frøstynips:BAACLgAFFH8nAAIcAAYJehw5BADFAQAcAAYJehw5BADFAQAuAAQKf0QAAxwACAkbJkkHAGcDABwACAkbJkkHAGcDACEABgm9IugBAAYCAAAA.',
Fu='Funkymunky:BAAALgAECgMJAgAAAA==.Furrbulous:BAAALgADCgIJAgAAAA==.Furysgrip:BAABLgAECn8hAAImAAgJ6xJUDQA6AQAmAAgJ6xJUDQA6AQAAAA==.',
Fy='Fyre:BAAALgADCgcJCwAAAA==.',
['Fí']='Fírnen:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúnk:BAABLgAECn8gAAQDAAgJ3xQjKAB3AQADAAcJHxcjKAB3AQAMAAgJkwkZDwBtAQAEAAEJqQIDlgAjAAAAAA==.',
Ga='Gaara:BAAALgADCgYJCAAAAA==.Galedrial:BAAALgADCgEJAQAAAA==.Garaktou:BAAALgADCgQJBAAAAA==.Garius:BAABLgAECn8bAAIfAAkJPx4fDQBbAgAfAAkJPx4fDQBbAgAAAA==.Gartah:BAAALgADCgIJAgABLgAECgQJBAAKAAAAAA==.Garthception:BAAALgAECgUJBQAAAA==.Gashweaver:BAAALgAECgMJAQAAAA==.',
Ge='Gentlegiantt:BAACLgAFFH8HAAIRAAMJ/AwGEwDbAAARAAMJ/AwGEwDbAAAuAAQKfyMAAxEACAnOGBEMAM0BABEACAnOGBEMAM0BABsAAQkAAF4wADQAAAAA.Gentlemonstr:BAAALgAFFAEJAQAAAA==.',
Gh='Ghood:BAAALgADCgMJAwAAAA==.',
Gi='Gigit:BAAALgAECgYJEwAAAA==.Giji:BAABLgAECn8WAAIGAAcJWhN3GgBAAQAGAAcJWhN3GgBAAQAAAA==.Gingersnapss:BAAALgAECgYJEgAAAA==.Girlsdayoni:BAAALgADCgcJBwAAAA==.',
Gl='Glizzyblasta:BAAALgADCgcJBwAAAA==.',
Gn='Gnimble:BAABLgAECn8UAAICAAcJIBrWGQDsAQACAAcJIBrWGQDsAQAAAA==.Gnuh:BAAALgADCgMJAwABLgAECgQJBwAKAAAAAA==.',
Go='Gohan:BAABLgAECn8SAAIDAAYJ1x9pUgBxAQADAAYJ1x9pUgBxAQAAAA==.Goku:BAAALgAECgMJBgABLgAECgYJEgADANcfAA==.Gommo:BAAALgAFFAIJAgAAAA==.Gooblento:BAABLgAECn8VAAIfAAgJ1g1RkABbAQAfAAgJ1g1RkABbAQAAAA==.Gorbad:BAAALgAECggJDwAAAA==.Gotwood:BAAALgAECgEJAQAAAA==.',
Gr='Grahamington:BAAALgAECgQJBwAAAA==.Grandmaster:BAAALgAECgcJDgAAAA==.Grapes:BAAALgAECgcJEwAAAA==.Grayfang:BAAALgADCgYJAQAAAA==.Greatranger:BAAALgAECgMJAwAAAA==.Grimmic:BAAALgADCgIJAgAAAA==.Groovywar:BAAALgADCggJCwAAAA==.Groundizzle:BAABLgAECn8aAAILAAgJcxb6HAD2AQALAAgJcxb6HAD2AQAAAA==.',
Gu='Guineamon:BAABLgAECn8YAAMkAAcJhBStDQCvAQAkAAcJhBStDQCvAQALAAEJcwTghAAsAAAAAA==.',
Gw='Gwwalker:BAAALgAECgcJCgAAAA==.',
Gz='Gzul:BAAALgAECgEJAgAAAA==.',
['Gô']='Gôof:BAAALgADCggJCQAAAA==.',
Ha='Haerinm:BAAALgAECgcJDQAAAA==.Haj:BAAALgAECgEJAQAAAA==.Hammel:BAAALgAECgkJCgAAAA==.Hanzxo:BAAALgAECgYJBwAAAA==.Harry:BAABLgAECn8oAAINAAgJxCK8BwC9AgANAAgJxCK8BwC9AgAAAA==.Harryrox:BAAALgADCgYJBgAAAA==.Haruk:BAABLgAECn8kAAIBAAkJ9Rt/BgB6AgABAAkJ9Bt/BgB6AgAAAA==.Hatememore:BAAALgAECgEJAgAAAA==.Hazchum:BAAALgADCgQJAgAAAA==.',
He='Healsdead:BAAALgADCgQJBAAAAA==.Heatfist:BAABLgAECn8oAAIlAAkJ6g6lAQDgAQAlAAkJ6g6lAQDgAQAAAA==.Hellhost:BAABLgAECn8fAAMhAAgJohaQAgDLAQAhAAgJohaQAgDLAQAcAAIJOgOPqABKAAAAAA==.Hertfor:BAAALgAECgEJAQAAAA==.Heåls:BAABLgAECn8cAAIBAAcJ9hpVHgAkAgABAAcJ9hpVHgAkAgAAAA==.',
Hi='Hisoka:BAAALgAECgQJCwABLgAECgUJDQAKAAAAAA==.',
Ho='Hoboface:BAAALgAECgIJAwAAAA==.Hoelishock:BAAALgAECgcJEQAAAA==.Hollynova:BAABLgAECn8dAAMkAAcJkxXFDQCtAQAkAAYJHBjFDQCtAQALAAEJXQZRQAAvAAABLgAECgkJIwAJACkLAA==.Holyreimer:BAAALgADCgcJAwAAAA==.Honeydew:BAACLgAFFH8TAAICAAYJRxS3AwDQAQACAAYJRxS3AwDQAQAuAAQKfx8AAgIACQkPHeIFAAEDAAIACQkPHeIFAAEDAAAA.Hotteemie:BAAALgADCggJDgAAAA==.',
Hr='Hrkz:BAAALgAECgIJAwABLgAECgYJDQAKAAAAAA==.',
Hy='Hydrastrider:BAAALgADCgEJAgAAAA==.Hydraxius:BAAALgADCgcJEAAAAA==.Hylingaar:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Hyoinmaru:BAAALgADCgEJAQAAAA==.',
Ia='Iamokuz:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.',
Ic='Icevoker:BAECLgAFFH8IAAIWAAMJkRf3AQARAQAWAAMJkRf3AQARAQAuAAQKfzsABBYACQljH8ICAP8CABYACAkWIMICAP8CAAkAAQmAGs5AAE8AABUAAQlNA+lKACwAAAAA.Iceyq:BAAALgAECgQJBwAAAA==.',
If='Ifloat:BAAALgAECgYJBgABLgAECgcJDQAKAAAAAA==.',
Ig='Igni:BAAALgAECgcJEQAAAA==.',
Ii='Iilliidann:BAAALgADCgEJAQAAAA==.',
Il='Ilioa:BAAALgADCggJGwAAAA==.',
Im='Immortus:BAAALgADCgUJBQABLgAECgcJAgAKAAAAAA==.Imsteve:BAAALgAECgQJCwAAAA==.Imugi:BAABLgAECn8XAAIJAAgJjAyKKQByAQAJAAgJjAyKKQByAQAAAA==.',
In='Innarial:BAAALgADCggJEQABLgAECgkJMAAcAFoPAA==.Interia:BAAALgAECgYJEQABLgAECgcJHgAVABIYAA==.Intress:BAAALgADCgIJAgAAAA==.',
Io='Ionsw:BAAALgAECgQJBwAAAA==.',
Ir='Ironski:BAAALgADCgEJAQABLgAECggJGgAcAN0gAA==.',
Is='Ishgard:BAAALgADCgcJCAAAAA==.Isopentene:BAAALgAECgMJAwAAAA==.',
It='Itchystrasz:BAAALgADCgMJAwAAAA==.',
Iu='Iudex:BAAALgADCgEJAQAAAA==.',
Iv='Ivalace:BAAALgAECgkJAQAAAA==.Ivyoxide:BAAALgAECgYJEgAAAA==.',
Ja='Jacabon:BAAALgADCgQJBwAAAA==.Jackillz:BAABLgAECn8aAAMCAAYJzR1WIQCoAQACAAUJ6B1WIQCoAQATAAUJpg83OgA0AQAAAA==.Jackpriest:BAAALgAFFAEJAQAAAA==.Jadè:BAAALgADCgYJBwABLgAECgUJCQAKAAAAAA==.Jagalr:BAAALgADCgYJBgAAAA==.Jarok:BAAALgAECggJDQAAAA==.Jaydee:BAAALgAECgIJBAAAAA==.',
Jb='Jbhunna:BAAALgAECgUJCwAAAA==.',
Je='Jee:BAABLgAECn8cAAIYAAgJ3QzUGABqAQAYAAgJ3QzUGABqAQAAAA==.Jellypriest:BAAALgADCgIJAwAAAA==.Jenish:BAAALgAECgEJAQAAAA==.Jescon:BAAALgAECgEJAgAAAA==.Jexs:BAAALgAECgUJCQAAAA==.',
Ji='Jiamil:BAAALgAECgMJBAAAAA==.Jiayu:BAAALgADCgEJAQAAAA==.Jibberwish:BAAALgADCgcJDAABLgAECgcJHgAcAF4fAA==.Jics:BAAALgAECgEJAgAAAA==.',
Jo='Jojoburn:BAAALgAECgEJAQAAAA==.Jojokiller:BAAALgAECgEJAgAAAA==.Jolteon:BAAALgADCgcJDQAAAA==.Jorkin:BAAALgAECgEJAQAAAA==.',
Ju='Juanster:BAAALgADCgcJBwAAAA==.Jubber:BAABLgAECn8eAAMcAAcJXh87FwABAgAcAAcJNR87FwABAgAmAAYJZxlEFADMAQAAAA==.Jumpnglide:BAAALgAECgMJBgAAAA==.Justaliltren:BAAALgAECgkJBwAAAA==.',
Jx='Jxidyn:BAAALgAECgYJBwAAAA==.',
Jy='Jynx:BAABLgAECn8dAAIHAAgJiSEdBgB7AgAHAAgJiSEdBgB7AgAAAA==.',
['Jø']='Jøzzy:BAAALgADCgUJBQAAAA==.',
Ka='Kaherd:BAABLgAECn8nAAIYAAcJ4g7HGgBZAQAYAAcJ4g7HGgBZAQAAAA==.Kahora:BAAALgADCgcJCgAAAA==.Kallavan:BAAALgADCgEJAQAAAA==.Kalmonk:BAABLgAECn8oAAMCAAgJ0xfMCAAkAgACAAgJ0xfMCAAkAgAUAAIJyQxqewBXAAAAAA==.Kalmyth:BAAALgADCgYJBgABLgAECgkJCwAKAAAAAA==.Kaltizdat:BAAALgADCgcJBwABLgAECgQJBgAKAAAAAA==.Kasadori:BAAALgADCgcJCQAAAA==.Kasualz:BAAALgAECgcJEQAAAA==.Kayrali:BAAALgADCgMJBAAAAA==.Kazsham:BAAALgAECgQJCQAAAA==.',
Kb='Kboomz:BAAALgAECgMJAwAAAA==.',
Kd='Kdvt:BAACLgAFFH8GAAINAAMJKQb5PADZAAANAAMJKQb5PADZAAAuAAQKfxUAAg0ABwn2GHtkAA8CAA0ABwn2GHtkAA8CAAAA.',
Ke='Keedrimath:BAAALgAECgYJBgAAAA==.Keenagon:BAAALgADCgcJBwAAAA==.Kelf:BAAALgADCgcJCgAAAA==.Kellbow:BAAALgAECgcJDQAAAA==.Kelynada:BAAALgADCgMJAwAAAA==.Keyevokey:BAAALgAECgEJAQAAAA==.',
Kh='Khaemset:BAAALgADCgkJCQAAAA==.',
Ki='Kieldaz:BAABLgAECn8gAAIgAAcJsRAVCQAXAQAgAAcJsRAVCQAXAQAAAA==.Kinore:BAAALgAECgQJBAAAAA==.Kirisute:BAABLgAECn8zAAINAAkJRiHsIADwAgANAAkJRiHsIADwAgAAAA==.Kitchenboss:BAABLgAECn8TAAINAAgJ0B02dADqAQANAAgJ0B02dADqAQAAAA==.Kithari:BAAALgAECgUJCwABLgAECggJHAACAJIfAA==.',
Kn='Knickerbits:BAAALgADCgMJAwAAAA==.Knotting:BAAALgAECgYJCwAAAA==.',
Ko='Koll:BAAALgADCgIJAgAAAA==.Kollateral:BAABLgAECn8pAAIIAAcJTxTtCQBmAQAIAAcJTxTtCQBmAQAAAA==.Kopara:BAAALgAECgcJEQAAAA==.Korell:BAAALgADCgEJAQABLgAECgcJDAAKAAAAAA==.Koriella:BAAALgAECgIJAgAAAA==.Kotetsu:BAAALgADCgUJBQAAAA==.',
Kr='Kraejekta:BAAALgAECgUJBQAAAA==.Krankiekunt:BAAALgAECgUJDAAAAA==.Krazmar:BAAALgADCgYJCwAAAA==.Kreigor:BAAALgADCgUJBQAAAA==.Krellhim:BAAALgAECgcJCwAAAA==.Krislocked:BAAALgAECgYJEQAAAA==.Krusper:BAAALgAECgQJBAAAAA==.',
Ku='Kungfused:BAAALgAECgMJAwAAAA==.',
Ky='Kyza:BAAALgAECgcJCgAAAA==.',
La='Laaurge:BAAALgAECgUJBgAAAA==.Landwalker:BAACLgAFFH8IAAIPAAMJqA3tGQDLAAAPAAMJqA3tGQDLAAAuAAQKfx4AAg8ABwnqH3MeAEsCAA8ABwnqH3MeAEsCAAAA.Langas:BAAALgAECgkJBgAAAA==.Latorius:BAAALgAECggJDwAAAA==.Lazarian:BAAALgADCgUJDQABLgAFFAEJAQAKAAAAAA==.Lazziel:BAABLgAECn8cAAINAAcJ0gQucAD5AAANAAcJ0gQucAD5AAAAAA==.',
Le='Leebear:BAAALgADCgEJAQAAAA==.Leilashte:BAAALgAECgYJDAAAAA==.Lenn:BAABLgAECn9BAAIRAAgJCRFnEACPAQARAAgJCRFnEACPAQAAAA==.Letmesolodps:BAAALgAECgQJBgAAAA==.Lettucelordh:BAABLgAECn8cAAMWAAgJzh3mAACDAgAWAAgJdh3mAACDAgAJAAIJrhY8MQCbAAAAAA==.Lexavis:BAAALgAECggJDAAAAA==.Leyi:BAABLgAECn8gAAMdAAcJOBhvOwAeAgAdAAcJOBhvOwAeAgAOAAMJeguPRQCfAAABLgAECggJEgAKAAAAAA==.Leyissa:BAAALgAECggJEgAAAA==.',
Li='Libidinous:BAAALgAECgEJAQAAAA==.Liggma:BAABLgAECn8aAAMLAAcJCRctDgDAAQALAAYJBhotDgDAAQAkAAcJbwlpFwAyAQAAAA==.Linkss:BAAALgADCgYJCwAAAA==.Linshadow:BAAALgAECgEJAQAAAA==.Litchblade:BAACLgAFFH8JAAIcAAQJrwVKLAANAQAcAAQJrwVKLAANAQAuAAQKfxYAAhwACAkbFaFHAB0CABwACAkbFaFHAB0CAAAA.Litgoblin:BAAALgADCgEJAgAAAA==.Littlecoops:BAAALgADCgYJCAAAAA==.',
Lo='Loalo:BAAALgADCgUJBQAAAA==.Locky:BAAALgAECgQJBgAAAA==.Lomzz:BAAALgAECgEJBAAAAA==.Loopy:BAAALgADCgEJAQAAAA==.Lootminator:BAAALgADCgQJBQAAAA==.Loptr:BAAALgADCgEJAQAAAA==.Lorelai:BAAALgADCgcJEQAAAA==.Lowkey:BAAALgAECgYJAgABLgAECgcJCAAKAAAAAA==.Lozza:BAAALgADCgQJBQAAAA==.',
Lu='Lucullus:BAAALgAECgIJAgAAAA==.Lukotii:BAAALgADCgkJAQAAAA==.Luminarus:BAAALgAECgQJBgAAAA==.Lurethuid:BAAALgAECgQJBAAAAA==.Luts:BAAALgADCgIJAgAAAA==.',
Ly='Lyd:BAABLgAECn8YAAMZAAcJ+guPCwBIAQAZAAcJ+guPCwBIAQAYAAMJhgGemABeAAAAAA==.Lynarium:BAAALgAECgcJDgAAAA==.Lynnmage:BAAALgADCgQJBAAAAA==.Lynnoni:BAAALgADCggJDQAAAA==.',
['Lû']='Lûmiere:BAABLgAECn8YAAIfAAgJrx5ZOQA+AgAfAAgJrx5ZOQA+AgAAAA==.',
Ma='Magharitta:BAABLgAECn8oAAIcAAgJICL3DABfAgAcAAgJICL3DABfAgAAAA==.Majicx:BAAALgAECgUJCQAAAA==.Malign:BAABLgAECn8WAAIdAAgJcgpdWQC8AQAdAAgJcgpdWQC8AQAAAA==.Malthayel:BAAALgAECgEJAQAAAA==.Manaseeker:BAAALgADCgkJDAAAAA==.Maraku:BAAALgAFFAIJBAAAAA==.Masonic:BAAALgAECgUJDwAAAA==.Matter:BAAALgAECgUJCwAAAA==.Maxxfury:BAAALgAECgYJAwAAAA==.',
Mc='Mcshok:BAAALgADCgcJCAAAAA==.',
Me='Medesin:BAAALgADCgcJHAAAAA==.Medhic:BAAALgADCgIJAQAAAA==.Meirge:BAAALgAECgUJBQAAAA==.Mekhanite:BAABLgAECn8dAAImAAgJESCWAwAXAgAmAAgJESCWAwAXAgAAAA==.Memebeam:BAAALgAECgYJBwAAAA==.Memedemon:BAAALgAECgEJAQABLgAECgUJCQAKAAAAAA==.Mesmagius:BAAALgAECgUJBQAAAA==.Metasoul:BAABLgAECn8mAAIHAAgJ8hSSGwCPAQAHAAgJ8hSSGwCPAQAAAA==.',
Mi='Midknight:BAAALgAECggJDgAAAA==.Milfdella:BAAALgAECgcJDQAAAA==.Milspec:BAABLgAECn8WAAIYAAYJBhiQNADYAQAYAAYJBhiQNADYAQAAAA==.Minami:BAABLgAECn8dAAIfAAgJwh2XEAA4AgAfAAgJwh2XEAA4AgAAAA==.Minhiriath:BAABLgAECn8YAAIcAAcJYRS9LwB7AQAcAAcJYRS9LwB7AQAAAA==.Mistea:BAAALgAECgYJBgAAAA==.',
Mo='Modren:BAAALgAECgMJBAAAAA==.Mojo:BAAALgAECgkJCQAAAA==.Momotaku:BAAALgAECgYJEQAAAA==.Monalisa:BAABLgAECn8YAAINAAcJJxTBNACSAQANAAcJJxTBNACSAQAAAA==.Monkecco:BAAALgAECgcJBQAAAA==.Monkgyatso:BAAALgAECgUJCwAAAA==.Monkhax:BAAALgADCgYJBQAAAA==.Monkow:BAAALgAECgQJCQAAAA==.Monne:BAAALgADCgYJBgABLgAECggJHQARANUVAA==.Monthax:BAAALgAECgIJAgAAAA==.Moomoos:BAABLgAECn8sAAIIAAkJShkFAwBAAgAIAAkJShkFAwBAAgAAAA==.Moonoo:BAAALgADCgIJAgAAAA==.Moonsblades:BAAALgAECgEJAQAAAA==.Moonthorn:BAAALgAECgUJCwAAAA==.Mooseoose:BAAALgAECgcJCgAAAA==.Morada:BAAALgADCgkJFwAAAA==.Mordok:BAAALgAECgEJAQAAAA==.Morena:BAAALgADCgMJBgAAAA==.Morgaina:BAABLgAECn8cAAIOAAcJjx3vAQALAgAOAAcJjx3vAQALAgAAAA==.Movski:BAABLgAECn8fAAQXAAYJyyCdHwD9AQAXAAYJYiCdHwD9AQAnAAQJxhf+DwAPAQAoAAIJshvZCACgAAAAAA==.Moñk:BAABLgAECn8xAAMTAAgJ1hPwDACpAQAUAAgJGRF8KADDAQATAAgJVRHwDACpAQAAAA==.',
Ms='Msbearhaven:BAAALgADCgYJBgAAAA==.',
Mu='Multîpass:BAAALgADCgUJBQAAAA==.Murst:BAABLgAECn8dAAMdAAcJCx95PwAPAgAdAAYJDSJ5PwAPAgAOAAEJ/g+3YgBJAAAAAA==.',
My='Myeyeshurt:BAAALgAECgQJCwAAAA==.Mysterymeat:BAAALgADCgEJAQAAAA==.',
['Mä']='Mäya:BAAALgAECgUJDQAAAA==.',
['Më']='Mëmëmë:BAAALgAECgQJCQAAAA==.',
['Mü']='Müz:BAAALgAECgUJCAABLgAFFAgJAQAKAAAAAA==.',
Na='Nahyeah:BAAALgAECgQJBAAAAA==.Natria:BAABLgAECn8rAAMWAAgJRhQbAwDCAQAWAAgJRhQbAwDCAQAJAAMJGgodTwCRAAAAAA==.Naw:BAAALgAECgYJCQAAAA==.Nayashka:BAAALgAECgUJDQAAAA==.',
Ne='Neeb:BAAALgAECgYJEAABLgAFFAEJAQAKAAAAAA==.Neebd:BAAALgAFFAEJAQAAAA==.Nepth:BAABLgAECn8mAAIBAAgJqx97FABuAgABAAgJqx97FABuAgAAAA==.Nerfde:BAAALgAECgQJBAAAAA==.Nerfdelag:BAAALgAECgcJEQAAAA==.Nerfgün:BAAALgADCgEJAQABLgAECgkJCwAKAAAAAA==.',
Ni='Nihonshu:BAAALgADCgIJAQAAAA==.Niskus:BAAALgAECgYJEQAAAA==.Nixipixie:BAAALgADCgcJCAAAAA==.Nizan:BAAALgAECgQJBgAAAA==.Nizie:BAAALgADCgMJAgAAAA==.',
No='Nobbiepally:BAAALgAECgYJEgAAAA==.Nonono:BAAALgAECgMJBQAAAA==.Notagoblin:BAAALgAECgYJDQAAAA==.Notahealer:BAAALgAECgcJDwAAAA==.Notdahuntard:BAAALgAECgkJDgAAAA==.Notso:BAAALgAECgQJBAAAAA==.',
Np='Nps:BAAALgAECgUJCwAAAA==.',
Nr='Nragz:BAAALgAECgcJCgAAAA==.',
Ns='Nsi:BAABLgAFFH8IAAIHAAMJ8iI1FgAeAQAHAAMJ8iI1FgAeAQAAAA==.',
Nu='Nulldeath:BAABLgAECn8UAAIcAAcJpCE1NQBiAgAcAAcJpCE1NQBiAgAAAA==.Nutsdormu:BAABLgAECn88AAIVAAgJzBI9CQCMAQAVAAgJzBI9CQCMAQAAAA==.',
Ny='Nyssaela:BAAALgAECgUJBQAAAA==.Nyxmoona:BAAALgADCgcJGgAAAA==.',
['Nà']='Nàishà:BAABLgAECn8YAAMLAAgJyRSaCgD9AQALAAgJyRSaCgD9AQAaAAYJKgVnQgDnAAAAAA==.',
Ob='Obskur:BAAALgADCgQJBAABLgAECgcJHgAVABIYAA==.',
Od='Odinwolf:BAABLgAFFH8LAAIFAAUJLR1vBQB1AQAFAAUJLR1vBQB1AQAAAA==.',
Og='Oggie:BAAALgAECgQJCgAAAA==.Oginn:BAAALgAECgQJBgAAAA==.',
Oh='Ohspeghettii:BAAALgADCgcJDQABLgAECgYJCwAKAAAAAA==.',
Oi='Oioi:BAAALgADCgEJAQAAAA==.',
Oj='Ojisancage:BAABLgAECn8VAAIdAAcJPhMtPAA+AQAdAAcJPhMtPAA+AQAAAA==.',
On='Onepuff:BAABLgAECn8UAAINAAcJZA/ZQQBpAQANAAcJZA/ZQQBpAQAAAA==.Onism:BAAALgADCgkJDAAAAA==.',
Or='Orinys:BAABLgAECn8mAAIVAAcJYBOZCACdAQAVAAcJYBOZCACdAQAAAA==.Orkky:BAABLgAECn8eAAImAAgJxhz3BQDNAQAmAAgJxhz3BQDNAQAAAA==.',
Pa='Packnwang:BAAALgADCgEJAQAAAA==.Page:BAABLgAECn8eAAIXAAgJvBg0BwD/AQAXAAgJvBg0BwD/AQAAAA==.Pakurruun:BAAALgADCgcJFAAAAA==.Pallatress:BAAALgADCgcJGQAAAA==.Panginoon:BAABLgAECn8iAAMcAAkJUR7SJwCbAgAcAAgJDR7SJwCbAgAmAAcJfBfAHQBcAQAAAA==.Paphio:BAAALgAECgMJBgAAAA==.Papipalala:BAAALgAECgIJAgAAAA==.Pawadin:BAAALgAECgcJCQAAAA==.',
Pe='Pepapo:BAAALgAECgMJBwAAAA==.Pepio:BAAALgAECgMJBQABLgAECgQJBAAKAAAAAA==.Peppsi:BAAALgADCgcJDAAAAA==.Perden:BAAALgADCgMJAwAAAA==.',
Pg='Pgundry:BAAALgAECgMJAwAAAA==.',
Ph='Phakin:BAAALgADCgkJCQAAAA==.Phatboss:BAAALgAECgYJCwABLgAECggJEwANANAdAA==.Phayzedout:BAABLgAECn8ZAAMcAAgJgxglFwABAgAcAAgJgxglFwABAgAhAAEJAAAlFgA4AAAAAA==.',
Pi='Pierat:BAAALgAECgcJCwAAAA==.Piergeiron:BAAALgAECgcJDAAAAA==.Pinkrawr:BAAALgADCgMJAwAAAA==.Pinkwarrior:BAAALgAECgMJBQAAAA==.Pinkyblue:BAABLgAECn8bAAMdAAgJmxRcPwAQAgAdAAgJmxRcPwAQAgAOAAEJAAChbQA5AAAAAA==.Pipeppy:BAAALgADCgYJBgAAAA==.Pipssqeek:BAAALgAECgkJAgAAAA==.Pipung:BAAALgAECgQJBQAAAA==.',
Pl='Plarrior:BAAALgAECgcJBwAAAA==.Plutô:BAAALgADCgYJDAAAAA==.',
Po='Poairua:BAAALgADCgEJAQAAAA==.Poda:BAAALgAECgEJAQAAAA==.Polloloco:BAAALgAECgQJBAAAAA==.Poobumhead:BAABLgAECn8gAAIdAAcJ/hNCLgBzAQAdAAcJ/hNCLgBzAQAAAA==.Potoro:BAAALgADCgIJAgAAAA==.Powzar:BAAALgAECgEJAQAAAA==.',
Pr='Praetorian:BAAALgAECgEJAgAAAA==.Priestmn:BAAALgADCgYJCQAAAA==.Probabely:BAAALgADCgEJAQABLgAFFAQJEAAcABseAA==.Probably:BAACLgAFFH8QAAIcAAQJGx68FABdAQAcAAQJGx68FABdAQAuAAQKfykAAhwACQn4JRISAA8DABwACQn4JRISAA8DAAAA.',
Pt='Ptree:BAAALgADCgcJBwABLgAFFAEJAgAKAAAAAA==.Ptreei:BAAALgAFFAEJAQABLgAFFAEJAgAKAAAAAA==.',
Pu='Puck:BAABLgAECn8XAAMWAAgJHBl5BACAAQAWAAcJQxh5BACAAQAJAAUJ1BKiMgA1AQAAAA==.Pudgeydk:BAAALgAECgEJAQAAAA==.Pudgeys:BAABLgAFFH8IAAISAAMJzhafAwC2AAASAAMJzhafAwC2AAAAAA==.Punj:BAAALgAECgYJBwABLgADCgYJBgAKAAAAAA==.Purdxpriest:BAAALgADCgQJAwABLgADCgcJCQAKAAAAAA==.Purdxwarlock:BAAALgADCgEJAQABLgADCgcJCQAKAAAAAA==.',
Py='Pyropuff:BAAALgADCgEJAQABLgAECggJLgAgAD0hAA==.Pytranze:BAAALgAECgYJCwAAAA==.Pywarrior:BAAALgADCgEJAQAAAA==.',
Qo='Qoldia:BAAALgADCgYJBgAAAA==.',
Qu='Quarizma:BAACLgAFFH8UAAIEAAUJ9SMnAgCmAQAEAAUJ9SMnAgCmAQAuAAQKfy4AAgQACAknJQoBAKACAAQACAknJQoBAKACAAAA.',
Ra='Radiantbunz:BAAALgADCgkJDgAAAA==.Rajbl:BAAALgAECgYJDgAAAA==.Rampagefist:BAAALgADCgMJAwAAAA==.Randalor:BAAALgADCgYJCgAAAA==.Rano:BAAALgAECgYJCAAAAA==.Ravenknight:BAAALgAECgIJAgAAAA==.Rayningdeath:BAAALgAECgkJAwAAAA==.Rayá:BAAALgADCgcJCAAAAA==.',
Re='Reaperzx:BAAALgAECgcJCwAAAA==.Reblle:BAAALgADCgIJAgAAAA==.Recks:BAAALgADCgEJAQAAAA==.Rejzo:BAAALgAECgMJBQAAAA==.Rejzosun:BAAALgAECgMJAwAAAA==.Renavant:BAAALgAECgcJEwAAAA==.Repliod:BAABLgAECn8vAAMbAAgJ8SVjAADkAgAbAAgJ8SVjAADkAgAQAAIJSQL3KgBvAAAAAA==.Restho:BAABLgAECn8VAAMFAAgJ7hghIABkAQAFAAgJ7hghIABkAQAGAAIJUAtreABhAAAAAA==.Revarix:BAABLgAECn8dAAMhAAkJJRapAwBIAgAhAAkJJRapAwBIAgAcAAEJKAdXOAEgAAAAAA==.',
Rh='Rhaella:BAABLgAECn8WAAIBAAgJAg57GQCBAQABAAgJAg57GQCBAQAAAA==.Rhuiser:BAAALgAECgcJEAAAAA==.Rhéá:BAAALgAECgYJCwAAAA==.',
Ri='Riggerized:BAAALgAECgcJEQABLgAECgkJLAAIAEoZAA==.Rightmeow:BAAALgADCgYJBgAAAA==.Rilirian:BAAALgAECgkJDwAAAA==.Riseth:BAABLgAECn8hAAIGAAgJmSQYAgDWAgAGAAgJmSQYAgDWAgAAAA==.Riteboys:BAAALgAECgcJBwABLgAECggJDwAKAAAAAA==.Ritéboys:BAAALgAECgEJAgABLgAECggJDwAKAAAAAA==.Rivella:BAAALgAECgcJCQAAAA==.',
Ro='Rockmelons:BAAALgADCgEJAQAAAA==.Rockosocko:BAAALgADCggJEAAAAA==.Roflpwnnt:BAABLgAECn8pAAQMAAgJxxzpBQAUAgAMAAgJYxfpBQAUAgAEAAYJ7BT/QABUAQADAAIJhh/2rgBmAAAAAA==.Rolln:BAAALgADCggJCwAAAA==.Romanée:BAAALgAECgQJCAAAAA==.Rootdaddy:BAAALgADCgEJAQAAAA==.Rootweaver:BAAALgADCgYJBgAAAA==.Rousay:BAABLgAECn8ZAAITAAgJlwa6FQA9AQATAAgJlwa6FQA9AQAAAA==.',
Ru='Rusdar:BAAALgAECgMJAwABLgAECggJHQAYAKIDAA==.Rustylightz:BAAALgAECgQJBAAAAA==.Rutactic:BAAALgAECgMJAwAAAA==.Rutee:BAABLgAECn8nAAIfAAgJHBgnHQDbAQAfAAgJHBgnHQDbAQAAAA==.',
Ry='Ryn:BAABLgAECn8RAAIHAAcJMAQUnwDYAAAHAAcJMAQUnwDYAAAAAA==.Ryuk:BAAALgAECgYJEQAAAA==.',
['Rà']='Ràvon:BAAALgAECgMJAwAAAA==.',
Sa='Sabelin:BAAALgADCgEJAQABLgAECggJHAACAJIfAA==.Safy:BAABLgAECn8hAAIUAAgJFQzQEwBnAQAUAAgJFQzQEwBnAQAAAA==.Saltyslug:BAAALgAECgQJCwAAAA==.Saltz:BAAALgAECgQJBAABLgAECggJFAAcAA8SAA==.Sanctilaz:BAAALgAFFAEJAQAAAA==.Sanosan:BAAALgAECgMJBgAAAA==.Saraedor:BAAALgADCgMJAwABLgAECgkJCwAKAAAAAA==.Sartoc:BAAALgAECgkJCwAAAA==.',
Sc='Scabbo:BAABLgAECn8aAAIOAAcJRBTFBACHAQAOAAcJRBTFBACHAQAAAA==.Scaleseeker:BAAALgADCgcJDQAAAA==.Scalesoul:BAAALgAFFAEJAQAAAQ==.Scarfeast:BAAALgADCgQJBAAAAA==.Scummbag:BAAALgAECgEJAwAAAA==.',
Sd='Sdw:BAAALgADCgcJCgABLgAECgEJAgAKAAAAAA==.',
Se='Sebille:BAABLgAECn8iAAINAAgJCR6ZLwC0AgANAAgJCR6ZLwC0AgAAAA==.Sebrogue:BAAALgAECgQJBwAAAA==.Seiferoth:BAAALgAECgEJAQABLgAFFAUJCwAFAC0dAA==.Selais:BAAALgAECgYJEgAAAA==.Selussa:BAAALgAECgYJBgABLgAFFAcJEwAHAH8fAA==.Senddori:BAAALgAECgUJBQAAAA==.Sepl:BAAALgAECgYJCgAAAA==.Serana:BAAALgAECgUJBgAAAA==.Serasashrain:BAAALgADCgEJAQAAAA==.',
Sh='Shaddai:BAABLgAECn8gAAIIAAgJ4RdXCgAqAgAIAAgJ4RdXCgAqAgAAAA==.Shadowmaggot:BAAALgAECgcJCAAAAA==.Shadylock:BAAALgAECgMJBgAAAA==.Shadypally:BAAALgAECgQJBAAAAA==.Shakyrabbit:BAAALgADCgMJBAAAAA==.Shamankiller:BAAALgAECgYJEQAAAA==.Shamannoodle:BAAALgADCgIJAgAAAA==.Shamitsdk:BAAALgADCgMJBgABLgAECgcJFwAFAIoWAA==.Shamix:BAAALgADCgYJDAAAAA==.Shaniquasimo:BAABLgAECn8ZAAIdAAgJcR3uCAB+AgAdAAgJcR3uCAB+AgAAAA==.Shaquiqui:BAAALgAECgIJAgAAAA==.Sharddaddy:BAAALgADCgIJAgAAAA==.Sharftay:BAAALgAECgYJEgABLgAFFAYJFQADABsMAA==.Sharissa:BAAALgAECgYJCAAAAA==.Shatgun:BAAALgADCgcJBwAAAA==.Shinieedruid:BAAALgAECgMJAgABLgAECggJIAAdAMYcAA==.Shockedurmum:BAABLgAECn8WAAMSAAcJIhYmFgBcAQASAAYJNA8mFgBcAQAGAAYJ+RmMRQAyAQAAAA==.Shocknôrris:BAAALgAECgYJEgAAAA==.Shouffle:BAAALgADCgcJBwAAAA==.',
Si='Sickomode:BAAALgADCgMJAwABLgAECgcJHgAVABIYAA==.Siferbooze:BAAALgADCgQJBAAAAA==.Silcy:BAAALgADCgMJAwAAAA==.Sillàrus:BAAALgAECgcJAgAAAA==.Silverspulse:BAABLgAECn8mAAMLAAcJih5gBwA7AgALAAcJih5gBwA7AgAkAAQJrRogLAA6AQAAAA==.Sinfulbeast:BAAALgAECgYJBgABLgAECggJKQAfAAkeAA==.Sinfulpally:BAABLgAECn8pAAIfAAgJCR5mEgAnAgAfAAgJCR5mEgAnAgAAAA==.Sippycup:BAACLgAFFH8FAAIcAAIJcRLTVQCgAAAcAAIJcRLTVQCgAAAuAAQKfyEAAhwACQn0HgMGAMACABwACQn0HgMGAMACAAAA.Sisisi:BAAALgAECgQJBQAAAA==.',
Sk='Skartos:BAAALgADCggJFwAAAA==.Skilledplaya:BAAALgAECgYJCQAAAA==.Skruffles:BAAALgADCgUJBQABLgAECgYJBgAKAAAAAA==.Skulv:BAACLgAFFH8IAAIHAAQJCyCECAB0AQAHAAQJCyCECAB0AQAuAAQKfzEAAgcACAnLJSwCAPMCAAcACAnLJSwCAPMCAAAA.Skum:BAAALgAECgEJAgAAAA==.Skunkdmeow:BAAALgAECgcJCgAAAA==.',
Sl='Slimygerald:BAAALgAECgIJAgAAAA==.Slopain:BAAALgAECgcJEgAAAA==.Slopflop:BAAALgADCgYJBgAAAA==.Slåppery:BAAALgAECgcJDQAAAA==.',
Sm='Smallarms:BAAALgAECgcJBQAAAA==.',
Sn='Sniickorzz:BAAALgAECgEJAQAAAA==.Snipereye:BAAALgAECgEJAQAAAA==.Snorlax:BAAALgAECgUJBQAAAA==.Snort:BAABLgAECn8eAAMBAAcJryEABQCgAgABAAcJryEABQCgAgAfAAcJeCDZIADFAQAAAA==.Snërt:BAAALgAECgYJCgAAAA==.',
So='Sonotafurry:BAAALgAECgUJCwAAAA==.Soojung:BAAALgADCgYJBgAAAA==.Soova:BAAALgAECgYJDQAAAA==.Sorcus:BAAALgAECgUJCwAAAA==.Soreknees:BAAALgADCgEJAQAAAA==.Souliuge:BAAALgADCgMJAwAAAA==.Soundface:BAABLgAECn8ZAAIGAAYJDhxiJQDmAQAGAAYJDhxiJQDmAQAAAA==.',
Sp='Sparkysteve:BAABLgAECn8aAAMGAAgJHSBkEAClAgAGAAgJHSBkEAClAgAFAAIJoA0dmgA5AAAAAA==.Spelcastndog:BAABLgAECn8iAAINAAgJmBmyKwC1AQANAAgJmBmyKwC1AQAAAA==.Spindrift:BAABLgAECn8YAAIBAAcJFSKKBQCQAgABAAcJFSKKBQCQAgAAAA==.Spinypubes:BAAALgAECgMJBQAAAA==.Spiritfuzz:BAAALgAECgQJBAABLgAFFAQJCQAcAK8FAA==.Spiritrez:BAAALgADCgYJAwABLgAECgEJAQAKAAAAAA==.Spodermin:BAAALgADCgEJAQABLgABCgIJAgAKAAAAAA==.Spoonyy:BAAALgAECgYJDQAAAA==.Spukz:BAACLgAFFH8JAAIYAAMJxQ2qGACmAAAYAAMJxQ2qGACmAAAuAAQKfxUAAxgABgmUHjAPAMUBABgABgmUHjAPAMUBABkAAQk4D54/ADkAAAAA.Spunkmonk:BAAALgAECgEJAwAAAA==.',
St='Stabbyhunt:BAAALgAECggJBgAAAA==.Starstorm:BAAALgAECgEJAQAAAA==.Sterlybo:BAAALgAECgIJAgABLgAECgcJFgAfAM0YAA==.Stoneyboi:BAAALgADCgcJCQAAAA==.Stormwrath:BAAALgAECgYJEAAAAA==.Stoutbrew:BAAALgAECgYJDgAAAA==.Stuy:BAACLgAFFH8HAAIEAAMJzgkOCgDZAAAEAAMJzgkOCgDZAAAuAAQKfzAAAgQACAnrGWIFAKYBAAQACAnrGWIFAKYBAAAA.Stãria:BAABLgAECn8fAAIDAAgJxAuBKQBwAQADAAgJxAuBKQBwAQAAAA==.Stårlå:BAAALgADCgEJAgAAAA==.Stèpsis:BAAALgADCgEJAQAAAA==.Störme:BAAALgADCgcJFQAAAA==.',
Su='Sugarburst:BAABLgAECn8UAAMSAAYJ/hgPCQBaAQASAAYJ/hgPCQBaAQAFAAEJ6gGzbAAgAAAAAA==.Sugmanutz:BAAALgAECgMJAwAAAA==.Sukmahdisc:BAABLgAECn8aAAIkAAkJLQzgIQCEAQAkAAkJLQzgIQCEAQAAAA==.Sulph:BAAALgADCgEJAQAAAA==.Supershy:BAAALgAECgEJAQAAAA==.Suppirin:BAAALgADCgYJCAAAAA==.Supprakus:BAABLgAECn8tAAIJAAgJKhsdBwAlAgAJAAgJKhsdBwAlAgAAAA==.Suspectsusan:BAAALgAECgEJAQAAAA==.Susuryss:BAAALgADCgUJBQAAAA==.',
Sv='Svendlemoon:BAABLgAECn8kAAIQAAYJ0xdjCABqAQAQAAYJ0xdjCABqAQAAAA==.',
Sw='Swak:BAAALgAECgcJEQAAAA==.Swaky:BAAALgADCgMJAwAAAA==.Sweaty:BAAALgADCgkJCQAAAA==.Swinginwilly:BAAALgAECgYJBgAAAA==.Swippy:BAAALgADCgQJBAAAAA==.Swirlo:BAABLgAECn8qAAIHAAgJ/R8uBQCRAgAHAAgJ/R8uBQCRAgAAAA==.Swirlyball:BAAALgADCgkJEQABLgAECggJKgAHAP0fAA==.',
Sy='Syaphire:BAAALgAECgMJAwAAAA==.Syndeath:BAAALgADCgIJAgAAAA==.Synths:BAABLgAECn8WAAQLAAgJ7hZSGgAJAgALAAgJ7hZSGgAJAgAkAAEJRhy6MABRAAAaAAEJtAohYQA2AAAAAA==.',
['Sñ']='Sñort:BAAALgAECgcJDgAAAA==.',
['Sý']='Sýìvàñás:BAAALgAECgUJAQAAAA==.',
Ta='Taffyclown:BAABLgAECn8cAAICAAgJkh9IBACbAgACAAgJkh9IBACbAgAAAA==.Takahe:BAAALgADCgcJCAAAAA==.Tallinor:BAABLgAECn8gAAMNAAcJbAzyTgBEAQANAAcJcwvyTgBEAQApAAQJhgc9CQDAAAAAAA==.Taumast:BAAALgAECgMJCAABLgAECggJGgALAHMWAA==.Tauter:BAAALgADCgcJGgAAAA==.Tazzee:BAAALgAECgEJAQAAAA==.',
Te='Teeki:BAAALgADCgcJBwAAAA==.Teiresius:BAAALgADCgYJBgAAAA==.Telsda:BAAALgAECgEJAgAAAA==.Tempyst:BAABLgAECn8eAAMVAAcJEhhAEwAOAgAVAAcJEhhAEwAOAgAJAAYJxgygJADiAAAAAA==.Tessdee:BAAALgAECgYJCAAAAA==.Tetactic:BAAALgADCgIJAgAAAA==.',
Th='Thalia:BAABLgAECn8dAAIIAAkJXBwKAgB6AgAIAAkJXBwKAgB6AgAAAA==.Thaytred:BAAALgAECgMJCAAAAA==.Thecheezels:BAAALgAECgIJAwAAAA==.Thegòòch:BAAALgADCgEJAQAAAA==.Thesean:BAAALgADCgcJBwAAAA==.Thevoice:BAAALgADCgQJBAAAAA==.Thomzhar:BAAALgAECgUJCwAAAA==.Thornir:BAAALgADCgEJAQABLgADCgMJBAAKAAAAAA==.Thors:BAAALgAECgYJAwAAAA==.Thraznith:BAAALgAECgUJDAAAAA==.Threeföld:BAAALgADCgYJBgABLgAFFAMJBQAfAOUPAA==.Throber:BAAALgADCgkJDAAAAA==.',
Ti='Tienchi:BAABLgAECn8aAAITAAgJBR1aBQBGAgATAAgJBR1aBQBGAgAAAA==.Tierk:BAAALgAECgcJDAAAAA==.Tillyhunter:BAAALgADCgcJEQAAAA==.Timmyy:BAAALgAECggJDQAAAA==.Tinainverse:BAAALgADCgEJAQAAAA==.',
To='Tomatofarmer:BAAALgADCgUJBQAAAA==.Tormént:BAACLgAFFH8HAAIhAAIJ/BVNBACtAAAhAAIJ/BVNBACtAAAuAAQKfzkAAiEACQmyJBMAAF8DACEACQmyJBMAAF8DAAAA.Torvold:BAAALgAECgMJAwAAAA==.',
Tr='Traumatizer:BAABLgAECn8dAAIYAAgJThT2EACyAQAYAAgJThT2EACyAQAAAA==.Treehumpin:BAAALgAECgMJAwAAAA==.Tremorlover:BAAALgAECgIJBQAAAA==.Trogas:BAAALgAECgMJAwAAAA==.Tronix:BAAALgAECgkJEQAAAA==.Tronixs:BAAALgAECgEJAQABLgAECgkJEQAKAAAAAA==.Trucidario:BAAALgAECgUJCwAAAA==.Trulsdk:BAAALgAECgQJCAABLgAECgYJBwAKAAAAAA==.Truwar:BAAALgAECgYJBwAAAA==.',
Tu='Turtlewave:BAAALgAECgUJAgAAAA==.',
Tw='Twiganomicon:BAAALgAECgEJAQAAAA==.Twiggz:BAABLgAECn8aAAIDAAcJFgb1TQDkAAADAAcJFgb1TQDkAAAAAA==.Twinkleface:BAAALgAECgQJBAAAAA==.',
Ty='Tylund:BAABLgAECn8qAAIDAAgJrQ4hHQCxAQADAAgJrQ4hHQCxAQAAAA==.Tyrilara:BAAALgADCgUJCAAAAA==.Tyruu:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tânk:BAAALgAECgEJBAAAAA==.',
['Tï']='Tïm:BAAALgAECgMJAwABLgAECggJDQAKAAAAAA==.',
Ul='Ulfiant:BAAALgAECgEJAQAAAA==.Ultimatdeath:BAAALgAECgkJAQAAAA==.',
Un='Unholykníght:BAAALgADCgEJAQAAAA==.',
Ur='Uratowel:BAAALgADCgEJAQAAAA==.',
Va='Valaya:BAAALgAECgYJDAAAAA==.Valcaris:BAAALgAECgcJEQAAAA==.Valdr:BAAALgAECgQJBAABLgAFFAQJCAAbADgVAA==.Valentine:BAAALgAECgkJEgAAAA==.Valex:BAAALgAECgEJAQAAAA==.Valithor:BAAALgAECgYJBwAAAA==.Vampaph:BAAALgADCgEJAQAAAA==.',
Ve='Velarose:BAAALgAECgYJEwAAAA==.Veledor:BAAALgADCgEJAQAAAA==.Velenair:BAAALgAECgYJEwABLgAECgcJBQAKAAAAAA==.Velenlerolan:BAABLgAECn8dAAIcAAcJcxtnHgDRAQAcAAcJcxtnHgDRAQAAAA==.Velicelia:BAAALgAECgQJBQAAAA==.Velthara:BAABLgAECn8kAAIfAAkJ6xndDwA/AgAfAAkJ6xndDwA/AgAAAA==.Velzan:BAAALgAECgUJCgAAAA==.Verailde:BAAALgADCgYJBgAAAA==.Verathos:BAAALgADCgIJAgAAAA==.Vergil:BAAALgAFFAEJAQAAAA==.Verilence:BAABLgAECn8kAAMeAAgJGSRrAABYAwAeAAgJGSRrAABYAwAdAAEJ+wdoJAEtAAAAAA==.Verks:BAAALgADCgYJBgABLgAECgUJCQAKAAAAAA==.Vext:BAAALgAECggJCAAAAA==.',
Vi='Victar:BAAALgADCgMJAwAAAA==.Villios:BAAALgAECgcJDwAAAA==.',
Vo='Voidberg:BAAALgAECgUJBgABLgAFFAMJCAAPAEEKAA==.Voidfondler:BAACLgAFFH8KAAIHAAQJQRicDwA9AQAHAAQJQRicDwA9AQAuAAQKfxUAAgcACAl5IooTAOMCAAcACAl5IooTAOMCAAAA.Voidgasm:BAAALgAECgMJBQAAAA==.Voidlocked:BAAALgAECgYJCwAAAA==.Vorndryad:BAAALgADCgYJBgAAAA==.',
Vy='Vynburn:BAABLgAECn8lAAINAAgJKxfnHQD4AQANAAgJKxfnHQD4AQAAAA==.Vynnaris:BAABLgAECn8ZAAImAAcJzQcHFgDPAAAmAAcJzQcHFgDPAAAAAA==.',
['Vì']='Vìn:BAAALgAECgEJAgAAAA==.',
Wa='Wadadadadeng:BAAALgADCgUJBgAAAA==.Wakuja:BAAALgADCgYJBgABLgAFFAUJCwAFAC0dAA==.Wallahi:BAAALgAECgUJDQAAAA==.Warriorlol:BAAALgADCgEJAQAAAA==.Warspear:BAAALgADCgEJAQAAAA==.Watson:BAABLgAECn8dAAINAAgJ5xFxKQC/AQANAAgJ5xFxKQC/AQAAAA==.Waveryy:BAAALgADCgYJCwAAAA==.',
We='Wehex:BAAALgADCgIJAgAAAA==.Wemblitz:BAAALgADCgcJFgAAAA==.Weraise:BAAALgADCgcJBwAAAA==.Wesh:BAAALgAECgQJBwAAAA==.',
Wh='Whio:BAABLgAECn8UAAMTAAcJJhG9EgBcAQATAAcJJhG9EgBcAQACAAQJIQsUUACTAAAAAA==.',
Wi='Wildglaive:BAAALgADCgkJHQAAAA==.Windwankur:BAAALgAECgIJAgAAAA==.Wintersfence:BAAALgAECgYJEgAAAA==.',
Wo='Woshiwacky:BAAALgADCgcJCQAAAA==.',
Xa='Xaldrin:BAAALgADCgEJAQAAAA==.Xallatath:BAAALgAECgYJDwAAAA==.Xanxes:BAAALgADCgIJAgAAAA==.',
Xe='Xenarn:BAEALgAECgcJDgAAAA==.Xenoruin:BAABLgAECn8dAAIjAAgJuA7sCwB+AQAjAAgJuA7sCwB+AQAAAA==.Xerez:BAAALgADCgYJDAAAAA==.Xertzart:BAABLgAECn8tAAIPAAgJqx0ICACMAgAPAAgJqx0ICACMAgAAAA==.Xev:BAAALgADCgkJEgAAAA==.',
Xi='Ximigo:BAAALgAECgYJEAAAAA==.Xinrat:BAAALgAECgIJAgAAAA==.Xiongzzrwar:BAAALgAFFAEJAQABLgAFFAUJDwAXACQWAA==.',
['Xê']='Xêv:BAABLgAECn8XAAMcAAgJEx37JgCiAQAcAAgJEx37JgCiAQAmAAEJAABhRgAvAAAAAA==.',
Ya='Yangdu:BAAALgADCgcJBwAAAA==.',
Yo='Yojambuh:BAAALgAECgMJBQAAAA==.Yoyo:BAAALgAECgYJCgAAAA==.',
Yr='Yrugae:BAAALgADCgYJDgAAAA==.',
['Yõ']='Yõzõrã:BAAALgADCgcJCAAAAA==.',
Za='Zae:BAABLgAECn8ZAAIpAAYJqB7GAgANAgApAAYJqB7GAgANAgAAAA==.Zaeley:BAAALgAECgkJDAABLgAECgcJGQApAKgeAA==.Zanisha:BAABLgAECn8eAAIRAAcJuQPdJgDOAAARAAcJuQPdJgDOAAAAAA==.Zargrim:BAAALgADCgEJAQAAAA==.Zatasia:BAABLgAFFH8GAAICAAMJFgpdEgC8AAACAAMJFgpdEgC8AAAAAA==.',
Ze='Zeddar:BAAALgAECgQJBAAAAA==.Zegion:BAABLgAECn8bAAMBAAYJCAqTVgAhAQABAAYJCAqTVgAhAQAfAAEJ3QN+WQElAAAAAA==.Zelendorm:BAABLgAECn8dAAIIAAgJ3R58AwArAgAIAAgJ3R58AwArAgAAAA==.Zephyreus:BAAALgADCgkJFgAAAA==.Zerat:BAAALgAECgUJBQABLgAECggJHQARANUVAA==.Zeroth:BAAALgADCgcJCgAAAA==.Zezîma:BAAALgADCgYJBgAAAA==.',
Zi='Zingerböx:BAAALgADCgYJBgAAAA==.Zionara:BAAALgADCgUJBQABLgAFFAQJAQAKAAAAAA==.',
Zu='Zugzak:BAAALgAECgYJBgABLgAECggJIAAPAGgXAA==.Zunara:BAAALgADCgcJBwAAAA==.',
['Ãk']='Ãkillies:BAABLgAECn8dAAMYAAgJogPWNQCyAAAYAAgJbQPWNQCyAAAZAAIJ9QIxRgArAAAAAA==.',
['År']='Årrow:BAAALgADCgMJAwAAAA==.',
['Ær']='Æries:BAAALgAECgIJAgAAAA==.',
['Îl']='Îllshot:BAAALgADCgcJBwAAAA==.',
['Ðo']='Ðomino:BAAALgAECgEJAQAAAA==.',
['ßa']='ßaccycønes:BAAALgADCgYJBgAAAA==.',
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

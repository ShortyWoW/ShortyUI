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

local lookup = {'Hunter-Survival','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Priest-Holy','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Warrior-Protection','DemonHunter-Havoc','DeathKnight-Unholy','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Elemental',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Ademar:BAABLgAECn8fAAIBAAYJwhbeGwAlAQABAAYJwhbeGwAlAQAAAA==.',
Ag='Agrius:BAAALgAECgYJDAAAAA==.',
Ak='Akurumira:BAAALgADCgIJAgAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgIJAwAAAA==.Allectra:BAAALgAECgQJBwAAAA==.Allupinya:BAAALgADCgEJAgAAAA==.',
Am='Amnon:BAABLgAECn8jAAICAAgJGx80AQBoAgACAAgJGx80AQBoAgAAAA==.',
As='Asaelis:BAAALgAECgUJDAAAAA==.Astauren:BAAALgADCgMJBAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECggJGQADAAMgAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAABLgAFFAEJAQAEAAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAABLgAECn8eAAMFAAgJnQiVHQBHAQAFAAgJnQiVHQBHAQAGAAEJ7QD5dwAPAAAAAA==.Azgardia:BAAALgAECgIJAgAAAA==.Azryiel:BAAALgAECgUJBQABLgAECggJHgAFAJ0IAA==.Azulå:BAAALgAECgEJAQAAAA==.',
Ba='Bach:BAABLgAFFH8KAAIHAAMJXiB+EgAjAQAHAAMJXiB+EgAjAQAAAA==.Balloffur:BAAALgAECggJEgAAAA==.Bamboostixx:BAABLgAECn8WAAIIAAgJDwoQVABvAQAIAAgJDwoQVABvAQAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAABLgAECn8hAAIJAAkJohQ8DQAYAgAJAAkJohQ8DQAYAgAAAA==.Berastú:BAAALgAECgYJCwAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQAEAAAAAA==.Bloodlusst:BAAALgADCgQJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8YAAIKAAYJYxkYRQApAQAKAAYJYxkYRQApAQAAAA==.Bors:BAABLgAECn8fAAMLAAkJQxmiCQD8AgALAAkJQxmiCQD8AgAMAAUJARHLUgABAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJDwAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8YAAILAAYJvAnzYwA7AQALAAYJvAnzYwA7AQAAAA==.Calyse:BAABLgAECn8bAAINAAcJ1B+BBQAaAgANAAcJ1B+BBQAaAgAAAA==.Casblind:BAACLgAFFH8WAAIKAAYJtRcECgCkAQAKAAYJtRcECgCkAQAuAAQKfx8AAgoACQkZIHoQAPoCAAoACQkZIHoQAPoCAAAA.Casima:BAAALgAECgYJEQAAAA==.',
Ch='Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn8mAAIOAAgJARDHFACxAQAOAAgJARDHFACxAQAAAA==.Chicknwaffle:BAAALgAECgMJBgAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8gAAIFAAcJdBe9EwCgAQAFAAcJdBe9EwCgAQAAAA==.',
Ci='Ciri:BAAALgAECgEJAQAAAA==.',
Co='Cornmoon:BAAALgADCgQJAgAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAgJHAAPAAgiAA==.',
Da='Dalanorea:BAAALgAECgYJBgAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgAECgQJBgAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECggJHwAQAEAgAA==.',
Di='Diménsional:BAABLgAECn8aAAIFAAcJaREHHQBLAQAFAAcJaREHHQBLAQAAAA==.Dinbek:BAAALgAECgMJAwAAAA==.Dindroc:BAAALgADCgcJDgAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAABLgAECn8XAAIRAAYJRQdCDQC8AAARAAYJRQdCDQC8AAAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.Drunkmcmonk:BAAALgADCgMJAwAAAA==.',
Du='Duronimo:BAAALgADCgcJCgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8LAAMSAAQJYwizEwDlAAASAAMJaAmzEwDlAAATAAIJgAJIKABHAAAuAAQKfxwABBIACAkLGj4WADYCABIACAkLGj4WADYCABMAAQkoB9ZbACsAAA4AAQnmAReKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAQJCwASAGMIAA==.Eclipzé:BAABLgAECn8YAAMUAAcJyhjNUAA4AQAUAAYJMhHNUAA4AQACAAQJGxfyCwDJAAABLgAFFAQJCwASAGMIAA==.',
Ei='Eifel:BAAALgAECgYJEQABLgAECgkJGwAVABceAA==.',
El='Elessardan:BAABLgAECn8eAAMWAAgJZx8kDACIAgAWAAgJZx8kDACIAgAHAAIJXhGqawBxAAAAAA==.Elvaca:BAAALgADCgEJAQAAAA==.',
En='Endilli:BAAALgAECgQJBgAAAA==.',
Eq='Equinoxis:BAEALgAECgYJBgABLgAFFAYJGAASAD8VAA==.',
Et='Eternal:BAAALgAFFAMJBAAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn8mAAIQAAYJLxhPFABvAQAQAAYJLxhPFABvAQAAAA==.',
Fe='Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn8iAAIFAAcJEhB/HABPAQAFAAcJEhB/HABPAQABLgAFFAIJBgAXAL4aAA==.',
Fi='Filho:BAABLgAECn8bAAMLAAYJ8hOQSgAtAQALAAYJ8hOQSgAtAQAMAAIJqAK/gABEAAAAAA==.',
Fr='Friedtips:BAAALgADCgQJBgABLgAECggJIgAYAKQfAA==.Frostwaffle:BAAALgADCgYJBgABLgAECgMJBgAEAAAAAA==.Frumpy:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.',
Ga='Gabe:BAAALgAECgEJAgAAAA==.Galvek:BAACLgAFFH8KAAQBAAMJZBcDDQAPAQABAAMJZBcDDQAPAQALAAIJawsZPgCeAAAMAAEJnwNgLABBAAAuAAQKfyIABAEACQlrHK4OAL4BAAEACAkSE64OAL4BAAsABgkIHa5BAKkBAAwABgmhEFs9AGgBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJCQAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAAALgAECgQJDAAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gw='Gwarr:BAAALgAECgIJAgAAAA==.',
Ha='Harvie:BAAALgADCgYJBgABLgAECgQJDAAEAAAAAA==.Hatani:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
He='Hemofluffin:BAAALgAECgIJAgABLgAFFAMJCgAZAL4SAA==.',
Hu='Husky:BAAALgAECgYJDQAAAA==.',
Ic='Icyfurball:BAAALgADCgkJIwABLgAECgYJEAAEAAAAAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgIJAwAAAA==.',
In='Indigobleue:BAABLgAECn8iAAMOAAcJURwqEADpAQAOAAcJURwqEADpAQATAAUJQBg6GgBfAQAAAA==.Infidel:BAAALgAECgIJAgABLgADCgEJAQAEAAAAAA==.',
Ja='Japplen:BAAALgAECgQJCAAAAA==.',
Je='Jeffery:BAAALgADCgMJAwAAAA==.Jeraziah:BAAALgADCgYJBwAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgADAEQWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jiñ:BAAALgAECgQJCAAAAA==.',
Jo='Jorenson:BAABLgAECn8jAAIZAAgJYxKmNwCbAQAZAAgJYxKmNwCbAQAAAA==.',
Ka='Kaether:BAABLgAECn8UAAMOAAYJoAitKQD+AAAOAAYJoAitKQD+AAASAAIJmADgaQAkAAAAAA==.Kalzdemar:BAAALgAECgUJDQABLgAECgYJHwABAMIWAA==.Kasitus:BAABLgAECn8eAAIZAAgJIyTkCgC0AgAZAAgJIyTkCgC0AgAAAA==.',
Ke='Keldanor:BAAALgAECgEJAQAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kilometraje:BAAALgAECgYJEAAAAA==.Kissey:BAAALgAECgMJBAAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAAALgAFFAIJBAAAAA==.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgYJCQAEAAAAAA==.',
Ky='Kyrak:BAAALgAECgQJBQAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Ladiebee:BAAALgADCgcJBwAAAA==.Lainey:BAABLgAECn8lAAILAAgJFxqgHADxAQALAAgJFxqgHADxAQAAAA==.Landocamando:BAAALgAECgYJEwAAAA==.Larrusbain:BAAALgAECgUJEAAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECgYJJgAQAC8YAA==.Lerya:BAABLgAECn8hAAIRAAkJ7BLnAwDJAQARAAkJ7BLnAwDJAQAAAA==.Lexnn:BAABLgAECn8hAAIKAAgJgxB5LQCBAQAKAAgJgxB5LQCBAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgADCggJCQAAAA==.Ligetnoone:BAAALgAECgYJEAAAAA==.Lighte:BAABLgAECn8oAAIIAAgJhhqwIQAiAgAIAAgJhhqwIQAiAgAAAA==.Lilyith:BAAALgAECgIJAwAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn8eAAIHAAYJoBYZHgBEAQAHAAYJoBYZHgBEAQAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn8dAAIIAAYJ7hC0cwApAQAIAAYJ7hC0cwApAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.Manimal:BAAALgAECgEJAQAAAA==.Mavren:BAAALgAECgQJBAAAAA==.',
Me='Mefisto:BAAALgAECgQJBAABLgAECgQJCAAEAAAAAA==.Mellesaun:BAAALgAECgYJEQAAAA==.Merie:BAAALgADCgYJBwAAAA==.Mewtwo:BAAALgAFFAIJAwABLgAFFAYJFQAaANMZAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgADCgcJDAAAAA==.',
Mo='Moonsaw:BAAALgAECgYJEQAAAA==.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.',
My='Myrling:BAAALgAECgYJEAAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAABLgAECn8eAAQKAAgJsBm0LgB8AQAYAAcJlRagIAC4AQAKAAcJwA+0LgB8AQAbAAEJrwInIgAiAAAAAA==.',
Ni='Nimbus:BAABLgAFFH8IAAIIAAMJ5ApdTwDlAAAIAAMJ5ApdTwDlAAABLgAFFAcJEwAaACUUAA==.Nishikki:BAECLgAFFH8YAAISAAYJPxVUAwC3AQASAAYJPxVUAwC3AQAuAAQKfzMAAhIACQmPIDECAPsCABIACQmPIDECAPsCAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.',
Ny='Nydie:BAABLgAECn8qAAIVAAkJjRlVFQBPAgAVAAkJjRlVFQBPAgAAAA==.Nymuellyn:BAABLgAECn8fAAIQAAgJQCCrDwCqAgAQAAgJQCCrDwCqAgAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Pa='Palmanance:BAAALgAECgkJCgAAAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAgAAAA==.Phibalan:BAAALgAECgEJAQAAAA==.',
Pi='Pixel:BAAALgAECgEJAQAAAA==.Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAABLgAECn8UAAILAAYJPAxHcAAXAQALAAYJPAxHcAAXAQAAAA==.',
Pr='Pradigy:BAAALgAECgYJEgAAAA==.',
Pu='Pubba:BAAALgAECgYJCQAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgYJCQAEAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.',
Pw='Pwincess:BAAALgAECgEJAQAAAA==.',
Ra='Raelyndria:BAAALgAECgcJEwAAAA==.Raengurth:BAAALgAECgEJAQAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Rakkali:BAAALgAFFAEJAQAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgADAEQWAA==.Razaller:BAABLgAECn8UAAMaAAkJiA73JQAcAQAaAAkJiA73JQAcAQARAAEJFgE4RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgADAEQWAA==.',
Re='Redrogue:BAABLgAECn8fAAIPAAYJ6wmyDgDoAAAPAAYJ6wmyDgDoAAAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8KAAIZAAMJvhIpUADvAAAZAAMJvhIpUADvAAAuAAQKfzIAAhkACAnWIe0aANwCABkACAnWIe0aANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAAALgAECgQJCQAAAA==.',
Ro='Rogun:BAAALgAECgUJEAAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgADAEQWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Satele:BAAALgAECgQJBgAAAA==.',
Sc='Scarypoppins:BAABLgAECn8ZAAIcAAcJYiL2BQBCAgAcAAcJYiL2BQBCAgAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECgYJBgAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAECggJHgAFAJ0IAA==.Seònaid:BAAALgAFFAIJAwAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgADCgUJBQABLgAECgYJDQAEAAAAAA==.Shammywaddle:BAABLgAECn8ZAAMDAAgJAyDLGwDTAQADAAYJ4CHLGwDTAQAdAAgJnRDCFQCkAQAAAA==.Shamtraxx:BAABLgAECn8aAAMDAAgJRBb2LwDIAQADAAcJPBb2LwDIAQAdAAcJTw1uRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgcJCwAAAA==.',
Sk='Skorpius:BAAALgAECgQJDAAAAA==.Skumi:BAAALgAECgUJCgAAAA==.',
Sl='Slaytanic:BAABLgAECn8gAAIVAAcJMRvxKQDXAQAVAAcJMRvxKQDXAQAAAA==.Slymick:BAAALgAECgcJEAAAAA==.',
So='Solora:BAABLgAECn8fAAIdAAYJ+gZxNgDUAAAdAAYJ+gZxNgDUAAAAAA==.Soluna:BAABLgAECn8hAAIVAAgJwhUPKwDSAQAVAAgJwhUPKwDSAQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgQJBQAAAA==.Stuffedbear:BAABLgAECn8UAAIHAAYJBQWONgCyAAAHAAYJBQWONgCyAAAAAA==.',
Su='Subiegrl:BAAALgAECgQJBAAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAABLgAECn8iAAIYAAgJpB/+EgA/AgAYAAgJpB/+EgA/AgAAAA==.',
['Sã']='Sãrik:BAAALgAECgQJCAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIdAAgJphAKGwB2AQAdAAgJphAKGwB2AQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAMJCQADALgcAA==.',
Th='Thirstrap:BAABLgAECn8XAAIYAAgJ+wonEwBYAQAYAAgJ+wonEwBYAQAAAA==.Thorge:BAAALgAECgYJEQAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgAECgMJAwAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJEwAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8aAAIMAAgJJRG3CgBFAQAMAAgJJRG3CgBFAQAAAA==.Ventt:BAACLgAFFH8UAAIdAAYJFhHpBgCBAQAdAAYJFhHpBgCBAQAuAAQKfygAAh0ACQmNIgkDAOUCAB0ACQmNIgkDAOUCAAAA.',
Vo='Volstaag:BAAALgAECgEJAgAAAA==.Voluus:BAAALgAECgYJDQAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAAALgAECgQJCAAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgQJBQABLgAECgYJEgAEAAAAAA==.Wayme:BAAALgAECgUJDAAAAA==.',
We='Wendorf:BAAALgADCgkJCQAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Xa='Xahle:BAABLgAECn8VAAIZAAcJ0AuxUABKAQAZAAcJ0AuxUABKAQAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgAECgQJBAAAAA==.',
Za='Zadkiel:BAAALgAECgQJBQAAAA==.',
Ze='Zeparu:BAAALgAECggJDwAAAA==.Zero:BAAALgAECgUJBwAAAA==.',
Zi='Zitillidan:BAAALgADCgUJBgABLgAECgYJHwABAMIWAA==.',
Zo='Zogz:BAAALgAECgYJDwAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8bAAIVAAkJFx4XIQCmAgAVAAkJFx4XIQCmAgAAAA==.',
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

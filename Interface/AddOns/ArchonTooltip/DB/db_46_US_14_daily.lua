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

local lookup = {'Priest-Discipline','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='daily',zone=46,date='2026-05-11',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAUJFgABAD0bAA==.',
Ae='Aerglo:BAAALgAECgYJDQAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEwAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBQAAAA==.Astraldoge:BAABLgAECn8UAAMCAAYJhgpWEQC9AAZoDAAABAAxAGkMAAAEABUAawwAAAQAGgBqDAAABAAYAGwMAAADACAA6gwAAAEABAADAAYJqwOdpQDHAAZoDAAAAQADAGkMAAACAAwAawwAAAIADgBqDAAAAQAGAGwMAAACAAoA6gwAAAEABAACAAUJrQxWEQC9AAVoDAAAAwAxAGkMAAACABUAawwAAAIAGgBqDAAAAwAYAGwMAAABACAAAAA=.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAAALgAECgQJBAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8hAAIDAAgJgyBDDgBoAghoDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAEAGEAbQwAAAMAPwDqDAAABQBbAG4MAAADADkAAwAICYMgQw4AaAIIaAwAAAUAXgBpDAAABQBZAGsMAAAFAFgAagwAAAMAYQBsDAAABABhAG0MAAADAD8A6gwAAAUAWwBuDAAAAwA5AAAA.',
Ba='Banana:BAAALgADCgUJCQABLgAECgcJGgAEAGgWAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIFAAcJiCQ4IQCmAgdoDAAABQBPAGkMAAAGAGAAawwAAAUAYQBqDAAAAwBJAGwMAAADAGAA6gwAAAQAXQBuDAAAAwBhAAUABwmIJDghAKYCB2gMAAAFAE8AaQwAAAYAYABrDAAABQBhAGoMAAADAEkAbAwAAAMAYADqDAAABABdAG4MAAADAGEAAAA=.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAFAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJEAAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8hAAIGAAgJNiL0DQCkAghoDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAEAGEAbQwAAAMAUQDqDAAABQBhAG4MAAADAD4ABgAICTYi9A0ApAIIaAwAAAUAYgBpDAAABQBZAGsMAAAFAFYAagwAAAMAUgBsDAAABABhAG0MAAADAFEA6gwAAAUAYQBuDAAAAwA+AAAA.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgQJBAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIHAAYJMhuGjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAHAAYJMhuGjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8oAAIIAAkJPx46BQD1AgloDAAABwBaAGkMAAAFAEsAawwAAAQATQBqDAAABQBfAGwMAAAFAE8AbQwAAAIAHQDqDAAABwBSAG4MAAAEAFsAbwwAAAEASgAIAAkJPx46BQD1AgloDAAABwBaAGkMAAAFAEsAawwAAAQATQBqDAAABQBfAGwMAAAFAE8AbQwAAAIAHQDqDAAABwBSAG4MAAAEAFsAbwwAAAEASgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8eAAIJAAgJyxcZCQCsAQhoDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAEAFIAbQwAAAMALgDqDAAABQA0AG4MAAADACUACQAICcsXGQkArAEIaAwAAAQARQBpDAAABABGAGsMAAAEAEMAagwAAAMAOwBsDAAABABSAG0MAAADAC4A6gwAAAUANABuDAAAAwAlAAAA.',
Ck='Ckonquer:BAABLgAFFH8JAAIKAAMJ7xRcGQDwAANoDAAAAwAxAGkMAAACABkA6gwAAAQAVQAKAAMJ7xRcGQDwAANoDAAAAwAxAGkMAAACABkA6gwAAAQAVQAAAA==.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8GAAMLAAUJzAZ2TgDKAAVoDAAAAQAYAGkMAAABABYAawwAAAEAAABqDAAAAQAHAOoMAAACABYACwAECQIJdk4AygAEaAwAAAEAGABpDAAAAQAWAGoMAAABAAcA6gwAAAIAFgAMAAEJKgBOGgANAAFrDAAAAQAAAAAA.',
Cz='Czaedyn:BAABLgAECn8pAAIMAAkJRBLdAwDpAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAMAAkJRBLdAwDpAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECggJFgAIAJoEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMLAAcJ4hh0RAD+AQdoDAAABAA/AGkMAAADAEoAawwAAAUAUABqDAAAAwBFAGwMAAADAEMAbQwAAAEAFgDqDAAABABKAAsABwniGHREAP4BB2gMAAAEAD8AaQwAAAMASgBrDAAABQBQAGoMAAABAEUAbAwAAAMAQwBtDAAAAQAWAOoMAAAEAEoADQABCQAACi0ARAABagwAAAIAOAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8hAAMOAAgJAAyvDgBoAQhoDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAEACMAbQwAAAMAKQDqDAAABQAZAG4MAAADACcADgAICQAMrw4AaAEIaAwAAAUAEwBpDAAABQAQAGsMAAAFACMAagwAAAMAHwBsDAAABAAjAG0MAAADACkA6gwAAAUAGQBuDAAAAgAnAA8AAQm6AQJtABoAAW4MAAABAAQAAAA=.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIQAAgJPCGgDADYAghoDAAAAwBgAGkMAAAEAFsAawwAAAUAYgBqDAAABQBeAGwMAAAEAGEAbQwAAAIAOwDqDAAABABaAG4MAAABADQAEAAICTwhoAwA2AIIaAwAAAMAYABpDAAABABbAGsMAAAFAGIAagwAAAUAXgBsDAAABABhAG0MAAACADsA6gwAAAQAWgBuDAAAAQA0AAAA.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8YAAILAAYJWAtqZwAKAQZoDAAABwAiAGkMAAAGACQAawwAAAQAJABqDAAAAwAbAGwMAAABABIA6gwAAAMAFAALAAYJWAtqZwAKAQZoDAAABwAiAGkMAAAGACQAawwAAAQAJABqDAAAAwAbAGwMAAABABIA6gwAAAMAFAAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAHAFgQAA==.',
Ev='Evi:BAAALgADCgkJCQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgADCgkJEwAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgcJFAAFAAccAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8IAAIHAAMJJxAlTgD4AANoDAAAAwAhAGkMAAADADwA6gwAAAIAHgAHAAMJJxAlTgD4AANoDAAAAwAhAGkMAAADADwA6gwAAAIAHgAuAAQKfygAAgcACAkWHtQkACMCAAcACAkWHtQkACMCAAAA.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.',
Gr='Greasemonkèy:BAABLgAECn8WAAIIAAgJmgSBZgD1AAhoDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgACAAICZoEgWYA9QAIaAwAAAUAGABpDAAAAwAEAGsMAAADAAQAagwAAAMACABsDAAAAwAQAG0MAAABAA0A6gwAAAMADABuDAAAAQAIAAAA.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgARAAAAAA==.Heavyroller:BAAALgAECgEJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgARAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAISAAcJZiQfAQDgAgdoDAAABQBfAGkMAAAEAGIAawwAAAQAYABqDAAAAwBdAGwMAAACAFQAbQwAAAIAWgDqDAAABABdABIABwlmJB8BAOACB2gMAAAFAF8AaQwAAAQAYgBrDAAABABgAGoMAAADAF0AbAwAAAIAVABtDAAAAgBaAOoMAAAEAF0AAAA=.Hotten:BAACLgAFFH8FAAIEAAQJtAa/DwAFAQRoDAAAAgAVAGkMAAABACgAawwAAAEAAADqDAAAAQAGAAQABAm0Br8PAAUBBGgMAAACABUAaQwAAAEAKABrDAAAAQAAAOoMAAABAAYALgAECn8UAAMEAAgJYQohEwCVAQAEAAgJYQohEwCVAQATAAYJjwLGhwCcAAAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8WAAMUAAgJnAyZJAAlAQhoDAAAAwAhAGkMAAADACYAawwAAAMAPQBqDAAAAwA8AGwMAAACAAcAbQwAAAIAEgDqDAAABAAgAG4MAAACACIAFAAHCUMNmSQAJQEHaAwAAAEAIQBpDAAAAQAmAGsMAAABAD0AagwAAAEAPABtDAAAAQADAOoMAAACACAAbgwAAAIAIgAVAAcJRQdhJwACAQdoDAAAAgAdAGkMAAACAA8AawwAAAIAGQBqDAAAAgA4AGwMAAACAAcAbQwAAAEAEgDqDAAAAgAPAAAA.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgcJEwAAAA==.',
Ka='Kalmea:BAAALgAECgUJCAAAAA==.Kaoru:BAABLgAECn8gAAIWAAgJghMABwCuAQhoDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAEADEAbQwAAAMAGwDqDAAABQBKAG4MAAADADgAFgAICYITAAcArgEIaAwAAAQAPQBpDAAABQAqAGsMAAAFACUAagwAAAMAPQBsDAAABAAxAG0MAAADABsA6gwAAAUASgBuDAAAAwA4AAAA.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgEJAQAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8pAAMLAAgJaBjtHAAOAghoDAAACABTAGkMAAAIAEQAawwAAAgAPgBqDAAABQAtAGwMAAAGADIAbQwAAAIAMwDqDAAAAgAnAG4MAAACAFAACwAICWgY7RwADgIIaAwAAAUAUwBpDAAABQBEAGsMAAAFAD4AagwAAAEAKQBsDAAABAAyAG0MAAACADMA6gwAAAEAJwBuDAAAAgBQAAwABgl+DBItAAkBBmgMAAADABMAaQwAAAMAOwBrDAAAAwAtAGoMAAAEAC0AbAwAAAIAFADqDAAAAQAOAAAA.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMXAAgJnx8gBgCJAghoDAAABgBfAGkMAAAGAFYAawwAAAYAUQBqDAAABQBTAGwMAAAFAFIAbQwAAAIAQwDqDAAABgBaAG4MAAADAD4AFwAICZ8fIAYAiQIIaAwAAAQAXwBpDAAABQBWAGsMAAAFAFEAagwAAAMAUwBsDAAAAgBSAG0MAAACAEMA6gwAAAUAWgBuDAAAAwA+ABgABglNFiI0AG4BBmgMAAACADsAaQwAAAEANwBrDAAAAQAyAGoMAAACADYAbAwAAAMANgDqDAAAAQBEAAAA.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAABLgAFFH8GAAIGAAMJYxZTTgAAAQNoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAGAAMJYxZTTgAAAQNoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAAAA==.Lifegiver:BAACLgAFFH8IAAMZAAMJVBdMGAD8AANoDAAAAwBTAGkMAAACABgA6gwAAAMARwAZAAMJVBdMGAD8AANoDAAAAgBTAGkMAAACABgA6gwAAAIARwAQAAIJOxXJMwCIAAJoDAAAAQAzAOoMAAABADkALgAECn8WAAMQAAgJXhhDHAD0AQAQAAgJXhhDHAD0AQAZAAMJaCFTRQAZAQAAAA==.Listyn:BAACLgAFFH8JAAIQAAMJMQOyGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAQAAMJMQOyGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAuAAQKfxkAAhAABwm8D/k2AE0BABAABwm8D/k2AE0BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgQJBAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8aAAIaAAgJBBjJDAD2AQhoDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAADADsAbQwAAAIAMgDqDAAABABBAG4MAAADACIAGgAICQQYyQwA9gEIaAwAAAQASABpDAAABABGAGsMAAAEAEsAagwAAAIALgBsDAAAAwA7AG0MAAACADIA6gwAAAQAQQBuDAAAAwAiAAAA.Mart:BAACLgAFFH8MAAIOAAQJMh8FDQBVAQRoDAAABABUAGkMAAADAEsAawwAAAIASQDqDAAAAwBWAA4ABAkyHwUNAFUBBGgMAAAEAFQAaQwAAAMASwBrDAAAAgBJAOoMAAADAFYALgAECn8pAAIOAAkJ4B3QBgAiAgAOAAkJ4B3QBgAiAgAAAA==.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAOADIfAA==.',
Mi='Miyafuji:BAABLgAECn8hAAMYAAgJ3CPRBADQAghoDAAABQBWAGkMAAAFAGAAawwAAAUAXwBqDAAAAwBSAGwMAAAEAGIAbQwAAAMAYADqDAAABQBSAG4MAAADAF8AGAAICdwj0QQA0AIIaAwAAAMAVgBpDAAABABgAGsMAAAEAF8AagwAAAIAUgBsDAAAAwBiAG0MAAADAGAA6gwAAAQAUgBuDAAAAwBfAAEABgnVHt0TAA4CBmgMAAACAFEAaQwAAAEAUQBrDAAAAQBMAGoMAAABAFAAbAwAAAEARwDqDAAAAQBRAAAA.',
Mo='Moonwell:BAACLgAFFH8IAAIQAAMJmSKMFgAsAQNoDAAABABOAGkMAAACAFoA6gwAAAIAYAAQAAMJmSKMFgAsAQNoDAAABABOAGkMAAACAFoA6gwAAAIAYAAuAAQKfyIAAhAACAnYJAUEADUDABAACAnYJAUEADUDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8QAAIEAAUJPCG6AwCEAQVoDAAABQBjAGkMAAAEAEkAawwAAAMASgBqDAAAAQAwAOoMAAADAFwABAAFCTwhugMAhAEFaAwAAAUAYwBpDAAABABJAGsMAAADAEoAagwAAAEAMADqDAAAAwBcAC4ABAp/KAAEBAAJCagiMwYAXgIABAAJCagiMwYAXgIAFgAECZ0PVGIAtwAAEwABCT8VvdEANAAAAAA=.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQARAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBQAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJDgABLgAECgcJGAASAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8XAAMbAAYJNBL9HQDeAAZoDAAABwA+AGkMAAAGAEYAawwAAAQAPQBqDAAAAgBEAGwMAAABABAA6gwAAAMAFgAbAAYJNBL9HQDeAAZoDAAABgA+AGkMAAAEAEYAawwAAAIAPQBqDAAAAgBEAGwMAAABABAA6gwAAAEAFgAcAAQJNAS3gwCwAARoDAAAAQADAGkMAAACAA0AawwAAAIAEQDqDAAAAgAIAAAA.Palanthir:BAABLgAECn8kAAIFAAkJXB7hGgA5AgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAFAAkJXB7hGgA5AgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAAAA==.Pandapve:BAACLgAFFH8LAAMVAAMJoxW8EADsAANoDAAABgBGAGkMAAACACoA6gwAAAMANQAVAAMJoxW8EADsAANoDAAABQBGAGkMAAACACoA6gwAAAMANQAUAAEJEAcYQgA8AAFoDAAAAQASAC4ABAp/JwADFQAICQwhuQYAdAIAFQAICQwhuQYAdAIAFAAGCfcQXlAAAgEAAAA=.',
Pe='Peja:BAAALgAECgUJDgAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgARAAAAAA==.',
Ph='Phu:BAACLgAFFH8PAAIZAAUJehd7DQAJAQVoDAAAAgA2AGkMAAAFAE0AawwAAAMAMABqDAAAAQA3AOoMAAAEADsAGQAFCXoXew0ACQEFaAwAAAIANgBpDAAABQBNAGsMAAADADAAagwAAAEANwDqDAAABAA7AC4ABAp/KQACGQAICVokXQUASAMAGQAICVokXQUASAMAAAA=.',
Po='Pockthelock:BAABLgAECn8VAAMLAAcJURK6RABmAQdoDAAABQAuAGkMAAAEAD0AawwAAAQANABqDAAAAwBFAGwMAAABACYAbQwAAAEAEwDqDAAAAwA+AAsABwm4D7pEAGYBB2gMAAAFAC4AaQwAAAQAPQBrDAAABAA0AGoMAAACAEUAbAwAAAEAJgBtDAAAAQATAOoMAAACABYADQACCY0Y/xcASgACagwAAAEADgDqDAAAAQA+AAAA.',
Pu='Puds:BAAALgADCggJEwABLgAECgUJDgARAAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8oAAILAAkJKhccHgAHAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgALAAkJKhccHgAHAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECggJEAAAAA==.Ravioli:BAABLgAECn8jAAIUAAgJcCWLAgDwAghoDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAFAGEAbQwAAAMAXgDqDAAABQBfAG4MAAADAFwAFAAICXAliwIA8AIIaAwAAAUAYQBpDAAABQBhAGsMAAAFAGAAagwAAAQAYwBsDAAABQBhAG0MAAADAF4A6gwAAAUAXwBuDAAAAwBcAAEuAAQKBwkYABIAZiQA.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8eAAMHAAkJzQzNNwDSAQloDAAABQA3AGkMAAAFACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQAHAAkJzQzNNwDSAQloDAAABAA3AGkMAAAEACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQASAAIJOQT/GABQAAJoDAAAAQAJAGkMAAABAAwAAAA=.Rayliee:BAAALgADCgMJAwABLgAECgkJHgAHAM0MAA==.',
Rh='Rhyssa:BAABLgAECn8WAAIVAAYJmiBJGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAVAAYJmiBJGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgQJBgAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIFAAgJtBZERQAUAghoDAAABABTAGkMAAADAEUAawwAAAQASgBqDAAAAgBDAGwMAAACAEoAbQwAAAEADwDqDAAAAwBFAG4MAAABABQABQAICbQWREUAFAIIaAwAAAQAUwBpDAAAAwBFAGsMAAAEAEoAagwAAAIAQwBsDAAAAgBKAG0MAAABAA8A6gwAAAMARQBuDAAAAQAUAAAA.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQYAAcJxAusPgA/AQdoDAAABAA3AGkMAAAEABkAawwAAAUAJQBqDAAABAALAGwMAAAEAEUAbQwAAAEABADqDAAABQAFABgABwnEC6w+AD8BB2gMAAADADcAaQwAAAMAGQBrDAAABQAlAGoMAAACAAsAbAwAAAMARQBtDAAAAQAEAOoMAAAEAAUAFwAECSwBNFoAUAAEaAwAAAEABABpDAAAAQACAGoMAAABAAYA6gwAAAEAAgABAAIJ6wFlUQBGAAJqDAAAAQAFAGwMAAABAAMAAAA=.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8pAAMPAAkJvgu4FgCdAQloDAAABwBHAGkMAAAGABEAawwAAAYAHgBqDAAABAAdAGwMAAAEABwAbQwAAAMAGgDqDAAABgAiAG4MAAAEAAwAbwwAAAEAEwAPAAkJvgu4FgCdAQloDAAABQBHAGkMAAAEABEAawwAAAQAHgBqDAAAAwAdAGwMAAAEABwAbQwAAAMAGgDqDAAABQAiAG4MAAAEAAwAbwwAAAEAEwAdAAUJwwEZMACWAAVoDAAAAgAGAGkMAAACAAAAawwAAAIABgBqDAAAAQARAOoMAAABAAMAAAA=.',
Se='Sempii:BAAALgAECgUJCAAAAA==.Serarlan:BAAALgAECgEJBAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgADCgIJAgABLgAECgUJDgARAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAAALgAECggJEQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJCQAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIeAAcJ2CB/CQCDAgdoDAAABABiAGkMAAAEAF0AawwAAAYAWgBqDAAABABbAGwMAAAEAFEAbQwAAAEAPQDqDAAABABOAB4ABwnYIH8JAIMCB2gMAAAEAGIAaQwAAAQAXQBrDAAABgBaAGoMAAAEAFsAbAwAAAQAUQBtDAAAAQA9AOoMAAAEAE4AAAA=.Slightcoyote:BAAALgAECgYJDwAAAA==.',
Sm='Smokeyh:BAACLgAFFH8MAAIUAAMJ5iGkEgAxAQNoDAAABgBTAGkMAAABAFsA6gwAAAUAVQAUAAMJ5iGkEgAxAQNoDAAABgBTAGkMAAABAFsA6gwAAAUAVQAuAAQKf0AAAhQACAn8I1EDANQCABQACAn8I1EDANQCAAAA.',
Sn='Snow:BAABLgAECn8YAAIfAAcJRRtYFwBQAgdoDAAABABCAGkMAAAEAFkAawwAAAQAWwBqDAAAAwBEAGwMAAACAEIA6gwAAAYAXwBuDAAAAQAJAB8ABwlFG1gXAFACB2gMAAAEAEIAaQwAAAQAWQBrDAAABABbAGoMAAADAEQAbAwAAAIAQgDqDAAABgBfAG4MAAABAAkAAAA=.',
St='Strongtoast:BAAALgAECggJDQAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAARAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgIJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8lAAILAAgJ+BTzJgDYAQhoDAAABwBQAGkMAAAFAEAAawwAAAcAOQBqDAAABgBRAGwMAAAFADkAbQwAAAEAHwDqDAAABQArAG4MAAABACkACwAICfgU8yYA2AEIaAwAAAcAUABpDAAABQBAAGsMAAAHADkAagwAAAYAUQBsDAAABQA5AG0MAAABAB8A6gwAAAUAKwBuDAAAAQApAAAA.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8YAAMCAAgJawuvDQD2AAhoDAAABAASAGkMAAAEACIAawwAAAQAIABqDAAABAAVAGwMAAAEACwAbQwAAAEAEADqDAAAAgAhAG4MAAABABkAAgAHCeQKrw0A9gAHaAwAAAQAEgBpDAAABAAiAGsMAAAEACAAagwAAAQAFQBsDAAAAgAsAG0MAAABABAA6gwAAAEAFQAgAAMJrwjTLQCNAANsDAAAAgAHAOoMAAABACEAbgwAAAEAGQAAAA==.',
To='Torí:BAABLgAECn8XAAIFAAgJvgmyowA5AQhoDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIABQAICb4JsqMAOQEIaAwAAAUAIABpDAAAAwAkAGsMAAADABgAagwAAAMAFQBsDAAAAwAeAG0MAAABAAoA6gwAAAQAFQBuDAAAAQASAAAA.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCAAAAA==.Vallkyr:BAABLgAECn8iAAIHAAkJ0x6nEACmAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAHAAkJ0x6nEACmAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAITAAgJ7A74OQDHAQhoDAAABAAuAGkMAAADADYAawwAAAQALABqDAAAAgA8AGwMAAACAB8AbQwAAAEAKwDqDAAAAwAkAG4MAAABAAoAEwAICewO+DkAxwEIaAwAAAQALgBpDAAAAwA2AGsMAAAEACwAagwAAAIAPABsDAAAAgAfAG0MAAABACsA6gwAAAMAJABuDAAAAQAKAAAA.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAQAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgQJCQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEAAAAA==.Zitta:BAABLgAECn8eAAIhAAgJYhV8FwAEAghoDAAABQA8AGkMAAAFAD8AawwAAAUARwBqDAAABABDAGwMAAAEAEAAbQwAAAIAIADqDAAABABCAG4MAAABAAoAIQAICWIVfBcABAIIaAwAAAUAPABpDAAABQA/AGsMAAAFAEcAagwAAAQAQwBsDAAABABAAG0MAAACACAA6gwAAAQAQgBuDAAAAQAKAAAA.Zittav:BAABLgAECn8bAAMiAAkJaxlkGwA5AgloDAAABAAiAGkMAAAEAEMAawwAAAQAPQBqDAAABAA3AGwMAAAEAGIAbQwAAAEAUADqDAAABABEAG4MAAABAC4AbwwAAAEARwAiAAkJaxlkGwA5AgloDAAAAgAiAGkMAAACAEMAawwAAAMAPQBqDAAAAwA3AGwMAAADAGIAbQwAAAEAUADqDAAAAwBEAG4MAAABAC4AbwwAAAEARwAFAAYJix5NNQC5AQZoDAAAAgBDAGkMAAACAFIAawwAAAEARwBqDAAAAQBiAGwMAAABAFEA6gwAAAEAVwAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAASAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
['Zà']='Zàpster:BAAALgAECgkJAQAAAA==.',
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

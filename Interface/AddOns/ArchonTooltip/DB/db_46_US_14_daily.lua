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

local lookup = {'Priest-Discipline','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='daily',zone=46,date='2026-05-10',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAUJFgABAD0bAA==.',
Ae='Aerglo:BAAALgAECgYJDQAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEwAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBQAAAA==.Astraldoge:BAABLgAECn8UAAMCAAYJhgrwEAC9AAZoDAAABAAxAGkMAAAEABUAawwAAAQAGgBqDAAABAAYAGwMAAADACAA6gwAAAEABAADAAYJqwObpQDHAAZoDAAAAQADAGkMAAACAAwAawwAAAIADgBqDAAAAQAGAGwMAAACAAoA6gwAAAEABAACAAUJrQzwEAC9AAVoDAAAAwAxAGkMAAACABUAawwAAAIAGgBqDAAAAwAYAGwMAAABACAAAAA=.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAAALgADCgMJAwAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8fAAIDAAgJgyC8DQBmAghoDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAEAGEAbQwAAAMAPwDqDAAABABbAG4MAAACADkAAwAICYMgvA0AZgIIaAwAAAUAXgBpDAAABQBZAGsMAAAFAFgAagwAAAMAYQBsDAAABABhAG0MAAADAD8A6gwAAAQAWwBuDAAAAgA5AAAA.',
Ba='Banana:BAAALgADCgUJCQABLgAECgYJGQAEALgZAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIFAAcJiCQ4IQCmAgdoDAAABQBPAGkMAAAGAGAAawwAAAUAYQBqDAAAAwBJAGwMAAADAGAA6gwAAAQAXQBuDAAAAwBhAAUABwmIJDghAKYCB2gMAAAFAE8AaQwAAAYAYABrDAAABQBhAGoMAAADAEkAbAwAAAMAYADqDAAABABdAG4MAAADAGEAAAA=.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAFAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJEAAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8fAAIGAAgJMCK9DQCgAghoDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAEAGEAbQwAAAMAUQDqDAAABABhAG4MAAACAD4ABgAICTAivQ0AoAIIaAwAAAUAYgBpDAAABQBZAGsMAAAFAFYAagwAAAMAUgBsDAAABABhAG0MAAADAFEA6gwAAAQAYQBuDAAAAgA+AAAA.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIHAAYJMhuHjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAHAAYJMhuHjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8oAAIIAAkJPx77BAD2AgloDAAABwBaAGkMAAAFAEsAawwAAAQATQBqDAAABQBfAGwMAAAFAE8AbQwAAAIAHQDqDAAABwBSAG4MAAAEAFsAbwwAAAEASgAIAAkJPx77BAD2AgloDAAABwBaAGkMAAAFAEsAawwAAAQATQBqDAAABQBfAGwMAAAFAE8AbQwAAAIAHQDqDAAABwBSAG4MAAAEAFsAbwwAAAEASgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8cAAIJAAgJPxf7CACoAQhoDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAEAFIAbQwAAAMALgDqDAAABAA0AG4MAAACABsACQAICT8X+wgAqAEIaAwAAAQARQBpDAAABABGAGsMAAAEAEMAagwAAAMAOwBsDAAABABSAG0MAAADAC4A6gwAAAQANABuDAAAAgAbAAAA.',
Ck='Ckonquer:BAABLgAFFH8JAAIKAAMJ7xRzGADyAANoDAAAAwAxAGkMAAACABkA6gwAAAQAVQAKAAMJ7xRzGADyAANoDAAAAwAxAGkMAAACABkA6gwAAAQAVQAAAA==.',
Cr='Crazytaco:BAAALgADCgYJCAAAAA==.',
Cu='Cursewords:BAABLgAFFH8GAAMLAAUJzAYeTADKAAVoDAAAAQAYAGkMAAABABYAawwAAAEAAABqDAAAAQAHAOoMAAACABYACwAECQIJHkwAygAEaAwAAAEAGABpDAAAAQAWAGoMAAABAAcA6gwAAAIAFgAMAAEJKgBzGQANAAFrDAAAAQAAAAAA.',
Cz='Czaedyn:BAABLgAECn8pAAIMAAkJRBK7AwDqAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAMAAkJRBK7AwDqAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECggJFgAIAJoEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMLAAcJ4hhyRAD+AQdoDAAABAA/AGkMAAADAEoAawwAAAUAUABqDAAAAwBFAGwMAAADAEMAbQwAAAEAFgDqDAAABABKAAsABwniGHJEAP4BB2gMAAAEAD8AaQwAAAMASgBrDAAABQBQAGoMAAABAEUAbAwAAAMAQwBtDAAAAQAWAOoMAAAEAEoADQABCQAACi0ARAABagwAAAIAOAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8fAAIOAAgJAAxaDgBoAQhoDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAEACMAbQwAAAMAKQDqDAAABAAZAG4MAAACACcADgAICQAMWg4AaAEIaAwAAAUAEwBpDAAABQAQAGsMAAAFACMAagwAAAMAHwBsDAAABAAjAG0MAAADACkA6gwAAAQAGQBuDAAAAgAnAAAA.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIPAAgJPCGgDADYAghoDAAAAwBgAGkMAAAEAFsAawwAAAUAYgBqDAAABQBeAGwMAAAEAGEAbQwAAAIAOwDqDAAABABaAG4MAAABADQADwAICTwhoAwA2AIIaAwAAAMAYABpDAAABABbAGsMAAAFAGIAagwAAAUAXgBsDAAABABhAG0MAAACADsA6gwAAAQAWgBuDAAAAQA0AAAA.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8YAAILAAYJWAu2ZQAIAQZoDAAABwAiAGkMAAAGACQAawwAAAQAJABqDAAAAwAbAGwMAAABABIA6gwAAAMAFAALAAYJWAu2ZQAIAQZoDAAABwAiAGkMAAAGACQAawwAAAQAJABqDAAAAwAbAGwMAAABABIA6gwAAAMAFAAAAA==.',
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
Fr='Frostpimp:BAACLgAFFH8IAAIHAAMJJxDDSwD7AANoDAAAAwAhAGkMAAADADwA6gwAAAIAHgAHAAMJJxDDSwD7AANoDAAAAwAhAGkMAAADADwA6gwAAAIAHgAuAAQKfygAAgcACAkUHnAjACICAAcACAkUHnAjACICAAAA.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.',
Gr='Greasemonkèy:BAABLgAECn8WAAIIAAgJmgSCZgD1AAhoDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgACAAICZoEgmYA9QAIaAwAAAUAGABpDAAAAwAEAGsMAAADAAQAagwAAAMACABsDAAAAwAQAG0MAAABAA0A6gwAAAMADABuDAAAAQAIAAAA.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgAAAA==.Heavyroller:BAAALgAECgEJAQAAAA==.Help:BAAALgAECgYJBgABLgAECggJEgAQAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIRAAcJZiQfAQDgAgdoDAAABQBfAGkMAAAEAGIAawwAAAQAYABqDAAAAwBdAGwMAAACAFQAbQwAAAIAWgDqDAAABABdABEABwlmJB8BAOACB2gMAAAFAF8AaQwAAAQAYgBrDAAABABgAGoMAAADAF0AbAwAAAIAVABtDAAAAgBaAOoMAAAEAF0AAAA=.Hotten:BAAALgAFFAIJAgAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8WAAMSAAgJnAzHIwAlAQhoDAAAAwAhAGkMAAADACYAawwAAAMAPQBqDAAAAwA8AGwMAAACAAcAbQwAAAIAEgDqDAAABAAgAG4MAAACACIAEgAHCUMNxyMAJQEHaAwAAAEAIQBpDAAAAQAmAGsMAAABAD0AagwAAAEAPABtDAAAAQADAOoMAAACACAAbgwAAAIAIgATAAcJRQdTJgAFAQdoDAAAAgAdAGkMAAACAA8AawwAAAIAGQBqDAAAAgA4AGwMAAACAAcAbQwAAAEAEgDqDAAAAgAPAAAA.',
In='Indomitable:BAAALgAECgYJBgAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgcJEwAAAA==.',
Ka='Kalmea:BAAALgAECgUJCAAAAA==.Kaoru:BAABLgAECn8eAAIUAAgJchF8BwCaAQhoDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAEADEAbQwAAAMAGwDqDAAABABKAG4MAAACABMAFAAICXIRfAcAmgEIaAwAAAQAPQBpDAAABQAqAGsMAAAFACUAagwAAAMAPQBsDAAABAAxAG0MAAADABsA6gwAAAQASgBuDAAAAgATAAAA.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgEJAQAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8pAAMLAAgJaBhVHAAMAghoDAAACABTAGkMAAAIAEQAawwAAAgAPgBqDAAABQAtAGwMAAAGADIAbQwAAAIAMwDqDAAAAgAnAG4MAAACAFAACwAICWgYVRwADAIIaAwAAAUAUwBpDAAABQBEAGsMAAAFAD4AagwAAAEAKQBsDAAABAAyAG0MAAACADMA6gwAAAEAJwBuDAAAAgBQAAwABgl+DBItAAkBBmgMAAADABMAaQwAAAMAOwBrDAAAAwAtAGoMAAAEAC0AbAwAAAIAFADqDAAAAQAOAAAA.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMVAAgJnx/cBQCKAghoDAAABgBfAGkMAAAGAFYAawwAAAYAUQBqDAAABQBTAGwMAAAFAFIAbQwAAAIAQwDqDAAABgBaAG4MAAADAD4AFQAICZ8f3AUAigIIaAwAAAQAXwBpDAAABQBWAGsMAAAFAFEAagwAAAMAUwBsDAAAAgBSAG0MAAACAEMA6gwAAAUAWgBuDAAAAwA+ABYABglNFiI0AG4BBmgMAAACADsAaQwAAAEANwBrDAAAAQAyAGoMAAACADYAbAwAAAMANgDqDAAAAQBEAAAA.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAABLgAFFH8GAAIGAAMJYxaxSwAAAQNoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAGAAMJYxaxSwAAAQNoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAAAA==.Lifegiver:BAACLgAFFH8IAAMXAAMJXBdlFwD8AANoDAAAAwBTAGkMAAACABgA6gwAAAMARwAXAAMJXBdlFwD8AANoDAAAAgBTAGkMAAACABgA6gwAAAIARwAPAAIJOxWBMgCIAAJoDAAAAQAzAOoMAAABADkALgAECn8WAAMPAAgJXhiaGwDzAQAPAAgJXhiaGwDzAQAXAAMJaCFTRQAZAQAAAA==.Listyn:BAACLgAFFH8JAAIPAAMJMQOyGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAPAAMJMQOyGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAuAAQKfxkAAg8ABwm8D+o1AE0BAA8ABwm8D+o1AE0BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8YAAIYAAgJmxfJDAD2AQhoDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAADADsAbQwAAAIAMgDqDAAAAwBBAG4MAAACABsAGAAICZsXyQwA9gEIaAwAAAQASABpDAAABABGAGsMAAAEAEsAagwAAAIALgBsDAAAAwA7AG0MAAACADIA6gwAAAMAQQBuDAAAAgAbAAAA.Mart:BAACLgAFFH8MAAIOAAQJMh9/DABWAQRoDAAABABUAGkMAAADAEsAawwAAAIASQDqDAAAAwBWAA4ABAkyH38MAFYBBGgMAAAEAFQAaQwAAAMASwBrDAAAAgBJAOoMAAADAFYALgAECn8pAAIOAAkJ4B2dBgAiAgAOAAkJ4B2dBgAiAgAAAA==.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAOADIfAA==.',
Mi='Miyafuji:BAABLgAECn8fAAMWAAgJmyPhBADGAghoDAAABQBWAGkMAAAFAGAAawwAAAUAXwBqDAAAAwBSAGwMAAAEAGIAbQwAAAMAYADqDAAABABSAG4MAAACAFoAFgAICZsj4QQAxgIIaAwAAAMAVgBpDAAABABgAGsMAAAEAF8AagwAAAIAUgBsDAAAAwBiAG0MAAADAGAA6gwAAAMAUgBuDAAAAgBaAAEABgnVHt0TAA4CBmgMAAACAFEAaQwAAAEAUQBrDAAAAQBMAGoMAAABAFAAbAwAAAEARwDqDAAAAQBRAAAA.',
Mo='Moonwell:BAACLgAFFH8IAAIPAAMJmSK6FQAsAQNoDAAABABOAGkMAAACAFoA6gwAAAIAYAAPAAMJmSK6FQAsAQNoDAAABABOAGkMAAACAFoA6gwAAAIAYAAuAAQKfyIAAg8ACAnYJNoDADUDAA8ACAnYJNoDADUDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8QAAIEAAUJPCGEAwCFAQVoDAAABQBjAGkMAAAEAEkAawwAAAMASgBqDAAAAQAwAOoMAAADAFwABAAFCTwhhAMAhQEFaAwAAAUAYwBpDAAABABJAGsMAAADAEoAagwAAAEAMADqDAAAAwBcAC4ABAp/JwAEBAAICWYloQQAywIABAAICWYloQQAywIAFAAECZ0PU2IAtwAAGQABCT8VvdEANAAAAAA=.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAQAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBQAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJDgABLgAECgcJGAARAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8XAAMaAAYJNBLdHADfAAZoDAAABwA+AGkMAAAGAEYAawwAAAQAPQBqDAAAAgBEAGwMAAABABAA6gwAAAMAFgAaAAYJNBLdHADfAAZoDAAABgA+AGkMAAAEAEYAawwAAAIAPQBqDAAAAgBEAGwMAAABABAA6gwAAAEAFgAbAAQJNAS4gwCwAARoDAAAAQADAGkMAAACAA0AawwAAAIAEQDqDAAAAgAIAAAA.Palanthir:BAABLgAECn8kAAIFAAkJXB73GQA4AgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAFAAkJXB73GQA4AgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAAAA==.Pandapve:BAACLgAFFH8LAAMTAAMJoxUcEADsAANoDAAABgBGAGkMAAACACoA6gwAAAMANQATAAMJoxUcEADsAANoDAAABQBGAGkMAAACACoA6gwAAAMANQASAAEJEAfZQAA8AAFoDAAAAQASAC4ABAp/JwADEwAICQwhbAYAdQIAEwAICQwhbAYAdQIAEgAGCfcQXlAAAgEAAAA=.',
Pe='Peja:BAAALgAECgUJDgAAAA==.Pelan:BAAALgADCgIJAgABLgAECggJEgAQAAAAAA==.',
Ph='Phu:BAACLgAFFH8PAAIXAAUJehd7DQAJAQVoDAAAAgA2AGkMAAAFAE0AawwAAAMAMABqDAAAAQA3AOoMAAAEADsAFwAFCXoXew0ACQEFaAwAAAIANgBpDAAABQBNAGsMAAADADAAagwAAAEANwDqDAAABAA7AC4ABAp/JQACFwAICVokXQUASAMAFwAICVokXQUASAMAAAA=.',
Po='Pockthelock:BAABLgAECn8VAAMLAAcJURJrQwBkAQdoDAAABQAuAGkMAAAEAD0AawwAAAQANABqDAAAAwBFAGwMAAABACYAbQwAAAEAEwDqDAAAAwA+AAsABwm4D2tDAGQBB2gMAAAFAC4AaQwAAAQAPQBrDAAABAA0AGoMAAACAEUAbAwAAAEAJgBtDAAAAQATAOoMAAACABYADQACCY0Y1RYASwACagwAAAEADgDqDAAAAQA+AAAA.',
Pu='Puds:BAAALgADCggJEwAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8oAAILAAkJKhc8HQAGAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgALAAkJKhc8HQAGAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECggJDwAAAA==.Ravioli:BAABLgAECn8hAAISAAgJlSTkAgDeAghoDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAFAGEAbQwAAAMAXgDqDAAABABfAG4MAAACAE0AEgAICZUk5AIA3gIIaAwAAAUAYQBpDAAABQBhAGsMAAAFAGAAagwAAAQAYwBsDAAABQBhAG0MAAADAF4A6gwAAAQAXwBuDAAAAgBNAAEuAAQKBwkYABEAZiQA.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8eAAMHAAkJzQxUNwDMAQloDAAABQA3AGkMAAAFACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQAHAAkJzQxUNwDMAQloDAAABAA3AGkMAAAEACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQARAAIJOQT/GABQAAJoDAAAAQAJAGkMAAABAAwAAAA=.Rayliee:BAAALgADCgMJAwABLgAECgkJHgAHAM0MAA==.',
Rh='Rhyssa:BAABLgAECn8WAAITAAYJmiBKGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAATAAYJmiBKGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgQJBgAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIFAAgJtBZGRQAUAghoDAAABABTAGkMAAADAEUAawwAAAQASgBqDAAAAgBDAGwMAAACAEoAbQwAAAEADwDqDAAAAwBFAG4MAAABABQABQAICbQWRkUAFAIIaAwAAAQAUwBpDAAAAwBFAGsMAAAEAEoAagwAAAIAQwBsDAAAAgBKAG0MAAABAA8A6gwAAAMARQBuDAAAAQAUAAAA.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQWAAcJxAutPgA/AQdoDAAABAA3AGkMAAAEABkAawwAAAUAJQBqDAAABAALAGwMAAAEAEUAbQwAAAEABADqDAAABQAFABYABwnEC60+AD8BB2gMAAADADcAaQwAAAMAGQBrDAAABQAlAGoMAAACAAsAbAwAAAMARQBtDAAAAQAEAOoMAAAEAAUAFQAECSwBM1oAUAAEaAwAAAEABABpDAAAAQACAGoMAAABAAYA6gwAAAEAAgABAAIJ6wFlUQBGAAJqDAAAAQAFAGwMAAABAAMAAAA=.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8pAAMcAAkJvgsvFgCdAQloDAAABwBHAGkMAAAGABEAawwAAAYAHgBqDAAABAAdAGwMAAAEABwAbQwAAAMAGgDqDAAABgAiAG4MAAAEAAwAbwwAAAEAEwAcAAkJvgsvFgCdAQloDAAABQBHAGkMAAAEABEAawwAAAQAHgBqDAAAAwAdAGwMAAAEABwAbQwAAAMAGgDqDAAABQAiAG4MAAAEAAwAbwwAAAEAEwAdAAUJwwEZMACWAAVoDAAAAgAGAGkMAAACAAAAawwAAAIABgBqDAAAAQARAOoMAAABAAMAAAA=.',
Se='Sempii:BAAALgAECgUJCAAAAA==.Serarlan:BAAALgAECgEJBAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgADCgIJAgABLgADCggJEwAQAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAAALgAECggJEQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJCQAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIeAAcJ2CB/CQCDAgdoDAAABABiAGkMAAAEAF0AawwAAAYAWgBqDAAABABbAGwMAAAEAFEAbQwAAAEAPQDqDAAABABOAB4ABwnYIH8JAIMCB2gMAAAEAGIAaQwAAAQAXQBrDAAABgBaAGoMAAAEAFsAbAwAAAQAUQBtDAAAAQA9AOoMAAAEAE4AAAA=.Slightcoyote:BAAALgAECgYJDwAAAA==.',
Sm='Smokeyh:BAACLgAFFH8MAAISAAMJ5iHdEQAyAQNoDAAABgBTAGkMAAABAFsA6gwAAAUAVQASAAMJ5iHdEQAyAQNoDAAABgBTAGkMAAABAFsA6gwAAAUAVQAuAAQKf0AAAhIACAn8IysDANQCABIACAn8IysDANQCAAAA.',
Sn='Snow:BAABLgAECn8YAAIfAAcJRRtYFwBQAgdoDAAABABCAGkMAAAEAFkAawwAAAQAWwBqDAAAAwBEAGwMAAACAEIA6gwAAAYAXwBuDAAAAQAJAB8ABwlFG1gXAFACB2gMAAAEAEIAaQwAAAQAWQBrDAAABABbAGoMAAADAEQAbAwAAAIAQgDqDAAABgBfAG4MAAABAAkAAAA=.',
St='Strongtoast:BAAALgAECggJDQAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAAQAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgIJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8lAAILAAgJ+BRFJgDWAQhoDAAABwBQAGkMAAAFAEAAawwAAAcAOQBqDAAABgBRAGwMAAAFADkAbQwAAAEAHwDqDAAABQArAG4MAAABACkACwAICfgURSYA1gEIaAwAAAcAUABpDAAABQBAAGsMAAAHADkAagwAAAYAUQBsDAAABQA5AG0MAAABAB8A6gwAAAUAKwBuDAAAAQApAAAA.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8XAAMCAAgJvQpnDQD2AAhoDAAABAASAGkMAAAEACIAawwAAAQAIABqDAAABAAVAGwMAAAEACwAbQwAAAEAEADqDAAAAQAVAG4MAAABABkAAgAHCeQKZw0A9gAHaAwAAAQAEgBpDAAABAAiAGsMAAAEACAAagwAAAQAFQBsDAAAAgAsAG0MAAABABAA6gwAAAEAFQAgAAIJdQbdNgBWAAJsDAAAAgAHAG4MAAABABkAAAA=.',
To='Torí:BAABLgAECn8XAAIFAAgJvgmzowA5AQhoDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIABQAICb4Js6MAOQEIaAwAAAUAIABpDAAAAwAkAGsMAAADABgAagwAAAMAFQBsDAAAAwAeAG0MAAABAAoA6gwAAAQAFQBuDAAAAQASAAAA.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCAAAAA==.Vallkyr:BAABLgAECn8iAAIHAAkJ0x4DEACkAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAHAAkJ0x4DEACkAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIZAAgJ7A74OQDHAQhoDAAABAAuAGkMAAADADYAawwAAAQALABqDAAAAgA8AGwMAAACAB8AbQwAAAEAKwDqDAAAAwAkAG4MAAABAAoAGQAICewO+DkAxwEIaAwAAAQALgBpDAAAAwA2AGsMAAAEACwAagwAAAIAPABsDAAAAgAfAG0MAAABACsA6gwAAAMAJABuDAAAAQAKAAAA.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAQAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgQJBgAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEAAAAA==.Zitta:BAABLgAECn8eAAIhAAgJYhV8FwAEAghoDAAABQA8AGkMAAAFAD8AawwAAAUARwBqDAAABABDAGwMAAAEAEAAbQwAAAIAIADqDAAABABCAG4MAAABAAoAIQAICWIVfBcABAIIaAwAAAUAPABpDAAABQA/AGsMAAAFAEcAagwAAAQAQwBsDAAABABAAG0MAAACACAA6gwAAAQAQgBuDAAAAQAKAAAA.Zittav:BAABLgAECn8bAAMiAAkJaxlmGwA5AgloDAAABAAiAGkMAAAEAEMAawwAAAQAPQBqDAAABAA3AGwMAAAEAGIAbQwAAAEAUADqDAAABABEAG4MAAABAC4AbwwAAAEARwAiAAkJaxlmGwA5AgloDAAAAgAiAGkMAAACAEMAawwAAAMAPQBqDAAAAwA3AGwMAAADAGIAbQwAAAEAUADqDAAAAwBEAG4MAAABAC4AbwwAAAEARwAFAAYJix54MwC5AQZoDAAAAgBDAGkMAAACAFIAawwAAAEARwBqDAAAAQBiAGwMAAABAFEA6gwAAAEAVwAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAARAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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

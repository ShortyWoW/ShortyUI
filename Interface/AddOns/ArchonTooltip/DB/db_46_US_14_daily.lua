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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Priest-Discipline','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='daily',zone=46,date='2026-05-16',data={Ad='Adrestia:BAEALgAFFAIJAgAAAA==.',
Ae='Aerglo:BAAALgAECgYJDwAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEwAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8UAAMBAAYJhgp2FAC5AAZoDAAABAAxAGkMAAAEABUAawwAAAQAGgBqDAAABAAYAGwMAAADACAA6gwAAAEABAACAAYJqwOfpQDHAAZoDAAAAQADAGkMAAACAAwAawwAAAIADgBqDAAAAQAGAGwMAAACAAoA6gwAAAEABAABAAUJrQx2FAC5AAVoDAAAAwAxAGkMAAACABUAawwAAAIAGgBqDAAAAwAYAGwMAAABACAAAAA=.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAAALgAFFAIJAwAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8hAAICAAgJgyDdFwBFAghoDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAEAGEAbQwAAAMAPwDqDAAABQBbAG4MAAADADkAAgAICYMg3RcARQIIaAwAAAUAXgBpDAAABQBZAGsMAAAFAFgAagwAAAMAYQBsDAAABABhAG0MAAADAD8A6gwAAAUAWwBuDAAAAwA5AAAA.',
Ba='Banana:BAAALgADCgUJCQABLgADCgcJBwADAAAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIEAAcJiCQ6IQCmAgdoDAAABQBPAGkMAAAGAGAAawwAAAUAYQBqDAAAAwBJAGwMAAADAGAA6gwAAAQAXQBuDAAAAwBhAAQABwmIJDohAKYCB2gMAAAFAE8AaQwAAAYAYABrDAAABQBhAGoMAAADAEkAbAwAAAMAYADqDAAABABdAG4MAAADAGEAAAA=.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAEAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJEAAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8hAAIFAAgJNiKFGABwAghoDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAEAGEAbQwAAAMAUQDqDAAABQBhAG4MAAADAD4ABQAICTYihRgAcAIIaAwAAAUAYgBpDAAABQBZAGsMAAAFAFYAagwAAAMAUgBsDAAABABhAG0MAAADAFEA6gwAAAUAYQBuDAAAAwA+AAAA.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgQJBAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIGAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAGAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8xAAIHAAkJOiK7AgBZAwloDAAACABaAGkMAAAGAEsAawwAAAUAYABqDAAABgBfAGwMAAAGAFgAbQwAAAMAXQDqDAAACABSAG4MAAAFAFsAbwwAAAIASgAHAAkJOiK7AgBZAwloDAAACABaAGkMAAAGAEsAawwAAAUAYABqDAAABgBfAGwMAAAGAFgAbQwAAAMAXQDqDAAACABSAG4MAAAFAFsAbwwAAAIASgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8eAAIIAAgJyxdYDACTAQhoDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAEAFIAbQwAAAMALgDqDAAABQA0AG4MAAADACUACAAICcsXWAwAkwEIaAwAAAQARQBpDAAABABGAGsMAAAEAEMAagwAAAMAOwBsDAAABABSAG0MAAADAC4A6gwAAAUANABuDAAAAwAlAAAA.',
Ck='Ckonquer:BAACLgAFFH8LAAIJAAMJwxbSHADqAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQAJAAMJwxbSHADqAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQAuAAQKfxoAAgkACQnNHkMGAL0CAAkACQnNHkMGAL0CAAAA.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMKAAYJUAhXCgCmAAZoDAAAAQAYAGkMAAABABYAawwAAAEAAABqDAAAAQAHAGwMAAABAAQA6gwAAAMANgALAAQJAgkIVwDPAARoDAAAAQAYAGkMAAABABYAagwAAAEABwDqDAAAAgAWAAoAAwm+B1cKAKYAA2sMAAABAAAAbAwAAAEABADqDAAAAQA2AAAA.',
Cz='Czaedyn:BAABLgAECn8pAAIKAAkJRBJ1BQDDAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAKAAkJRBJ1BQDDAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECggJFgAHAJoEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMLAAcJ4hh1RAD+AQdoDAAABAA/AGkMAAADAEoAawwAAAUAUABqDAAAAwBFAGwMAAADAEMAbQwAAAEAFgDqDAAABABKAAsABwniGHVEAP4BB2gMAAAEAD8AaQwAAAMASgBrDAAABQBQAGoMAAABAEUAbAwAAAMAQwBtDAAAAQAWAOoMAAAEAEoADAABCQAACi0ARAABagwAAAIAOAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8hAAMNAAgJAAzOEQBiAQhoDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAEACMAbQwAAAMAKQDqDAAABQAZAG4MAAADACcADQAICQAMzhEAYgEIaAwAAAUAEwBpDAAABQAQAGsMAAAFACMAagwAAAMAHwBsDAAABAAjAG0MAAADACkA6gwAAAUAGQBuDAAAAgAnAA4AAQnAAbF6ABoAAW4MAAABAAQAAAA=.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIPAAgJPCGfDADYAghoDAAAAwBgAGkMAAAEAFsAawwAAAUAYgBqDAAABQBeAGwMAAAEAGEAbQwAAAIAOwDqDAAABABaAG4MAAABADQADwAICTwhnwwA2AIIaAwAAAMAYABpDAAABABbAGsMAAAFAGIAagwAAAUAXgBsDAAABABhAG0MAAACADsA6gwAAAQAWgBuDAAAAQA0AAAA.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8eAAILAAcJ1AslaQAsAQdoDAAACAArAGkMAAAHACQAawwAAAUAJABqDAAABAAdAGwMAAACAB0AbQwAAAEAEADqDAAAAwAUAAsABwnUCyVpACwBB2gMAAAIACsAaQwAAAcAJABrDAAABQAkAGoMAAAEAB0AbAwAAAIAHQBtDAAAAQAQAOoMAAADABQAAAA=.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAGAFgQAA==.',
Ev='Evi:BAAALgADCgkJCQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgADCgkJEwAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgcJHgAEAPYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8MAAIGAAQJ4Q5jPQA/AQRoDAAABAAhAGkMAAAEADwAawwAAAEAHADqDAAAAwAeAAYABAnhDmM9AD8BBGgMAAAEACEAaQwAAAQAPABrDAAAAQAcAOoMAAADAB4ALgAECn8uAAIGAAgJQh50JgBAAgAGAAgJQh50JgBAAgAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgMJAwABLgAECgkJJAAEAFweAA==.',
Gr='Greasemonkèy:BAABLgAECn8WAAIHAAgJmgSDZgD1AAhoDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgABwAICZoEg2YA9QAIaAwAAAUAGABpDAAAAwAEAGsMAAADAAQAagwAAAMACABsDAAAAwAQAG0MAAABAA0A6gwAAAMADABuDAAAAQAIAAAA.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgADAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgADAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIQAAcJZiQfAQDgAgdoDAAABQBfAGkMAAAEAGIAawwAAAQAYABqDAAAAwBdAGwMAAACAFQAbQwAAAIAWgDqDAAABABdABAABwlmJB8BAOACB2gMAAAFAF8AaQwAAAQAYgBrDAAABABgAGoMAAADAF0AbAwAAAIAVABtDAAAAgBaAOoMAAAEAF0AAAA=.Hotten:BAACLgAFFH8HAAIRAAQJTRCEDwAZAQRoDAAAAwAqAGkMAAABACcAawwAAAEAAADqDAAAAgBTABEABAlNEIQPABkBBGgMAAADACoAaQwAAAEAJwBrDAAAAQAAAOoMAAACAFMALgAECn8YAAMRAAgJswzNFgCiAQARAAgJswzNFgCiAQASAAYJjwIBoACRAAAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8eAAMTAAgJUBA9HwBuAQhoDAAABAAzAGkMAAAEACYAawwAAAQAPQBqDAAABAA8AGwMAAADACEAbQwAAAMAEgDqDAAABQArAG4MAAADAC0AEwAICSYQPR8AbgEIaAwAAAIAMwBpDAAAAgAmAGsMAAACAD0AagwAAAIAPABsDAAAAQAhAG0MAAACAA8A6gwAAAMAKwBuDAAAAwAtABQABwlFB1czAOcAB2gMAAACAB0AaQwAAAIADwBrDAAAAgAZAGoMAAACADgAbAwAAAIABwBtDAAAAQASAOoMAAACAA8AAAA=.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgcJEwAAAA==.',
Ka='Kalmea:BAAALgAECgUJCAAAAA==.Kaoru:BAABLgAECn8gAAIVAAgJghMJCgCCAQhoDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAEADEAbQwAAAMAGwDqDAAABQBKAG4MAAADADgAFQAICYITCQoAggEIaAwAAAQAPQBpDAAABQAqAGsMAAAFACUAagwAAAMAPQBsDAAABAAxAG0MAAADABsA6gwAAAUASgBuDAAAAwA4AAAA.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgIJAgAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8xAAMLAAgJohl2KgDyAQhoDAAACQBTAGkMAAAKAEQAawwAAAoAPgBqDAAABgBVAGwMAAAHADIAbQwAAAIAMwDqDAAAAwA9AG4MAAACAFAACwAICaIZdioA8gEIaAwAAAYAUwBpDAAABwBEAGsMAAAHAD4AagwAAAIAVQBsDAAABQAyAG0MAAACADMA6gwAAAIAPQBuDAAAAgBQAAoABgl+DBEtAAkBBmgMAAADABMAaQwAAAMAOwBrDAAAAwAtAGoMAAAEAC0AbAwAAAIAFADqDAAAAQAOAAAA.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMWAAgJnx9zCgBeAghoDAAABgBfAGkMAAAGAFYAawwAAAYAUQBqDAAABQBTAGwMAAAFAFIAbQwAAAIAQwDqDAAABgBaAG4MAAADAD4AFgAICZ8fcwoAXgIIaAwAAAQAXwBpDAAABQBWAGsMAAAFAFEAagwAAAMAUwBsDAAAAgBSAG0MAAACAEMA6gwAAAUAWgBuDAAAAwA+ABcABglNFiI0AG4BBmgMAAACADsAaQwAAAEANwBrDAAAAQAyAGoMAAACADYAbAwAAAMANgDqDAAAAQBEAAAA.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAABLgAFFH8GAAIFAAMJYxZTWwD6AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAFAAMJYxZTWwD6AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAAAA==.Lifegiver:BAACLgAFFH8IAAMYAAMJVBdZGwDzAANoDAAAAwBTAGkMAAACABgA6gwAAAMARwAYAAMJVBdZGwDzAANoDAAAAgBTAGkMAAACABgA6gwAAAIARwAPAAIJOxXHOQCIAAJoDAAAAQAzAOoMAAABADkALgAECn8cAAMPAAgJKBqqFwBBAgAPAAgJKBqqFwBBAgAYAAUJPCJYRQAZAQAAAA==.Lindon:BAAALgADCgIJAgAAAA==.Listyn:BAACLgAFFH8JAAIPAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAPAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAuAAQKfx4AAg8ABwnTEC84AG4BAA8ABwnTEC84AG4BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgQJBAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8aAAIZAAgJBBjKDAD2AQhoDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAADADsAbQwAAAIAMgDqDAAABABBAG4MAAADACIAGQAICQQYygwA9gEIaAwAAAQASABpDAAABABGAGsMAAAEAEsAagwAAAIALgBsDAAAAwA7AG0MAAACADIA6gwAAAQAQQBuDAAAAwAiAAAA.Mart:BAACLgAFFH8MAAINAAQJMh/LDgBGAQRoDAAABABUAGkMAAADAEsAawwAAAIASQDqDAAAAwBWAA0ABAkyH8sOAEYBBGgMAAAEAFQAaQwAAAMASwBrDAAAAgBJAOoMAAADAFYALgAECn8pAAINAAkJ4B26CAAZAgANAAkJ4B26CAAZAgAAAA==.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAANADIfAA==.',
Mi='Miyafuji:BAABLgAECn8hAAMXAAgJ2iNrCQC1AghoDAAABQBWAGkMAAAFAGAAawwAAAUAXwBqDAAAAwBSAGwMAAAEAGIAbQwAAAMAYADqDAAABQBSAG4MAAADAF8AFwAICdojawkAtQIIaAwAAAMAVgBpDAAABABgAGsMAAAEAF8AagwAAAIAUgBsDAAAAwBiAG0MAAADAGAA6gwAAAQAUgBuDAAAAwBfABoABgnVHt4TAA4CBmgMAAACAFEAaQwAAAEAUQBrDAAAAQBMAGoMAAABAFAAbAwAAAEARwDqDAAAAQBRAAAA.',
Mo='Moonwell:BAACLgAFFH8MAAIPAAQJRCDJEAB6AQRoDAAABQBOAGkMAAADAFoAawwAAAEAQADqDAAAAwBgAA8ABAlEIMkQAHoBBGgMAAAFAE4AaQwAAAMAWgBrDAAAAQBAAOoMAAADAGAALgAECn8jAAIPAAgJ2CS1BQAqAwAPAAgJ2CS1BQAqAwAAAA==.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8SAAIRAAUJPCGJBQB3AQVoDAAABQBjAGkMAAAEAEkAawwAAAQASgBqDAAAAgBaAOoMAAADAFwAEQAFCTwhiQUAdwEFaAwAAAUAYwBpDAAABABJAGsMAAAEAEoAagwAAAIAWgDqDAAAAwBcAC4ABAp/KAAEEQAJCagilgQA0AIAEQAJCagilgQA0AIAFQAECZ0PVmIAtwAAEgABCT8VvNEANAAAAAA=.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQADAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBQAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJDgABLgAECgcJGAAQAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMbAAcJyxH7GgAnAQdoDAAACAA+AGkMAAAHAFIAawwAAAUAQABqDAAAAwBEAGwMAAACABUAbQwAAAEAFADqDAAAAwAWABsABwnLEfsaACcBB2gMAAAHAD4AaQwAAAUAUgBrDAAAAwBAAGoMAAADAEQAbAwAAAIAFQBtDAAAAQAUAOoMAAABABYAHAAECTQEuIMAsAAEaAwAAAEAAwBpDAAAAgANAGsMAAACABEA6gwAAAIACAAAAA==.Palanthir:BAABLgAECn8kAAIEAAkJXB65KQASAgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAEAAkJXB65KQASAgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAAAA==.Pandapve:BAACLgAFFH8PAAMUAAQJpBztBgBcAQRoDAAABwBGAGkMAAADAFMAawwAAAEAOQDqDAAABABSABQABAmkHO0GAFwBBGgMAAAGAEYAaQwAAAMAUwBrDAAAAQA5AOoMAAAEAFIAEwABCRAHm0cAOwABaAwAAAEAEgAuAAQKfykAAxQACAkMIWMKAFMCABQACAkMIWMKAFMCABMABgkpEV9QAAIBAAAA.',
Pe='Peja:BAAALgAECgYJEAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgADAAAAAA==.',
Ph='Phu:BAACLgAFFH8RAAIYAAUJexh9DQAJAQVoDAAAAgA2AGkMAAAFAE0AawwAAAQAOwBqDAAAAgA3AOoMAAAEADsAGAAFCXsYfQ0ACQEFaAwAAAIANgBpDAAABQBNAGsMAAAEADsAagwAAAIANwDqDAAABAA7AC4ABAp/MQACGAAICeAkXQUASAMAGAAICeAkXQUASAMAAAA=.',
Po='Pockthelock:BAABLgAECn8XAAMMAAcJUxbFDAAhAQdoDAAABgBQAGkMAAAFAEYAawwAAAUARwBqDAAAAgBFAGwMAAABACYAbQwAAAEAEwDqDAAAAwA+AAsABwm4D71dAEcBB2gMAAAFAC4AaQwAAAQAPQBrDAAABAA0AGoMAAACAEUAbAwAAAEAJgBtDAAAAQATAOoMAAACABYADAAECdIbxQwAIQEEaAwAAAEAUABpDAAAAQBGAGsMAAABAEcA6gwAAAEAPgAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgUJDgADAAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8oAAILAAkJKhcSLQDmAQloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgALAAkJKhcSLQDmAQloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECggJEAAAAA==.Ravioli:BAABLgAECn8jAAITAAgJbiXTAwDdAghoDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAFAGEAbQwAAAMAXgDqDAAABQBfAG4MAAADAFwAEwAICW4l0wMA3QIIaAwAAAUAYQBpDAAABQBhAGsMAAAFAGAAagwAAAQAYwBsDAAABQBhAG0MAAADAF4A6gwAAAUAXwBuDAAAAwBcAAEuAAQKBwkYABAAZiQA.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8eAAMGAAkJzQwKTgCuAQloDAAABQA3AGkMAAAFACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQAGAAkJzQwKTgCuAQloDAAABAA3AGkMAAAEACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQAQAAIJOQT/GABQAAJoDAAAAQAJAGkMAAABAAwAAAA=.Rayliee:BAAALgADCgMJAwABLgAECgkJHgAGAM0MAA==.',
Rd='Rd:BAAALgADCggJDQAAAA==.',
Re='Ret:BAAALgAECgUJBQAAAA==.',
Rh='Rhyssa:BAABLgAECn8WAAIUAAYJmiBOGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAUAAYJmiBOGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIEAAgJtBZIRQAUAghoDAAABABTAGkMAAADAEUAawwAAAQASgBqDAAAAgBDAGwMAAACAEoAbQwAAAEADwDqDAAAAwBFAG4MAAABABQABAAICbQWSEUAFAIIaAwAAAQAUwBpDAAAAwBFAGsMAAAEAEoAagwAAAIAQwBsDAAAAgBKAG0MAAABAA8A6gwAAAMARQBuDAAAAQAUAAAA.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQXAAcJxAusPgA/AQdoDAAABAA3AGkMAAAEABkAawwAAAUAJQBqDAAABAALAGwMAAAEAEUAbQwAAAEABADqDAAABQAFABcABwnEC6w+AD8BB2gMAAADADcAaQwAAAMAGQBrDAAABQAlAGoMAAACAAsAbAwAAAMARQBtDAAAAQAEAOoMAAAEAAUAFgAECSwBNloAUAAEaAwAAAEABABpDAAAAQACAGoMAAABAAYA6gwAAAEAAgAaAAIJ6wFnUQBGAAJqDAAAAQAFAGwMAAABAAMAAAA=.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8pAAMOAAkJvgvRIQB6AQloDAAABwBHAGkMAAAGABEAawwAAAYAHgBqDAAABAAdAGwMAAAEABwAbQwAAAMAGgDqDAAABgAiAG4MAAAEAAwAbwwAAAEAEwAOAAkJvgvRIQB6AQloDAAABQBHAGkMAAAEABEAawwAAAQAHgBqDAAAAwAdAGwMAAAEABwAbQwAAAMAGgDqDAAABQAiAG4MAAAEAAwAbwwAAAEAEwAdAAUJwwEZMACWAAVoDAAAAgAGAGkMAAACAAAAawwAAAIABgBqDAAAAQARAOoMAAABAAMAAAA=.',
Se='Sempii:BAAALgAECgUJCQAAAA==.Serarlan:BAAALgAECgEJBQAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgAECgEJAQABLgAECgUJDgADAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAAALgAECggJEQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIeAAcJ2CCBCQCDAgdoDAAABABiAGkMAAAEAF0AawwAAAYAWgBqDAAABABbAGwMAAAEAFEAbQwAAAEAPQDqDAAABABOAB4ABwnYIIEJAIMCB2gMAAAEAGIAaQwAAAQAXQBrDAAABgBaAGoMAAAEAFsAbAwAAAQAUQBtDAAAAQA9AOoMAAAEAE4AAAA=.Slightcoyote:BAAALgAECgcJEQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8NAAITAAMJ5iGhFQAqAQNoDAAABgBTAGkMAAABAFsA6gwAAAYAVQATAAMJ5iGhFQAqAQNoDAAABgBTAGkMAAABAFsA6gwAAAYAVQAuAAQKf0cAAxMACAneJMUDAN8CABMACAneJMUDAN8CABQAAQnMHWRcAFUAAAAA.',
Sn='Snow:BAABLgAECn8YAAIfAAcJRRtYFwBQAgdoDAAABABCAGkMAAAEAFkAawwAAAQAWwBqDAAAAwBEAGwMAAACAEIA6gwAAAYAXwBuDAAAAQAJAB8ABwlFG1gXAFACB2gMAAAEAEIAaQwAAAQAWQBrDAAABABbAGoMAAADAEQAbAwAAAIAQgDqDAAABgBfAG4MAAABAAkAAAA=.',
St='Strongtoast:BAAALgAECggJEgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAADAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgYJDAAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgIJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8lAAILAAgJ+BT5OgCvAQhoDAAABwBQAGkMAAAFAEAAawwAAAcAOQBqDAAABgBRAGwMAAAFADkAbQwAAAEAHwDqDAAABQArAG4MAAABACkACwAICfgU+ToArwEIaAwAAAcAUABpDAAABQBAAGsMAAAHADkAagwAAAYAUQBsDAAABQA5AG0MAAABAB8A6gwAAAUAKwBuDAAAAQApAAAA.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8ZAAMBAAgJiw1OEAD0AAhoDAAABAASAGkMAAAEACIAawwAAAQAIABqDAAABAAVAGwMAAAEACwAbQwAAAEAEADqDAAAAgAhAG4MAAACAD8AAQAHCeQKThAA9AAHaAwAAAQAEgBpDAAABAAiAGsMAAAEACAAagwAAAQAFQBsDAAAAgAsAG0MAAABABAA6gwAAAEAFQAgAAMJpw3cMQCYAANsDAAAAgAHAOoMAAABACEAbgwAAAIAPwAAAA==.',
To='Torí:BAABLgAECn8XAAIEAAgJvgmyowA5AQhoDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIABAAICb4JsqMAOQEIaAwAAAUAIABpDAAAAwAkAGsMAAADABgAagwAAAMAFQBsDAAAAwAeAG0MAAABAAoA6gwAAAQAFQBuDAAAAQASAAAA.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCAAAAA==.Vallkyr:BAABLgAECn8iAAIGAAkJ0x6FGwB7AgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAGAAkJ0x6FGwB7AgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAISAAgJ7A77OQDHAQhoDAAABAAuAGkMAAADADYAawwAAAQALABqDAAAAgA8AGwMAAACAB8AbQwAAAEAKwDqDAAAAwAkAG4MAAABAAoAEgAICewO+zkAxwEIaAwAAAQALgBpDAAAAwA2AGsMAAAEACwAagwAAAIAPABsDAAAAgAfAG0MAAABACsA6gwAAAMAJABuDAAAAQAKAAAA.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAgAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgYJDwAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEQAAAA==.Zitta:BAABLgAECn8eAAIhAAgJYhV8FwAEAghoDAAABQA8AGkMAAAFAD8AawwAAAUARwBqDAAABABDAGwMAAAEAEAAbQwAAAIAIADqDAAABABCAG4MAAABAAoAIQAICWIVfBcABAIIaAwAAAUAPABpDAAABQA/AGsMAAAFAEcAagwAAAQAQwBsDAAABABAAG0MAAACACAA6gwAAAQAQgBuDAAAAQAKAAAA.Zittav:BAABLgAECn8bAAMiAAkJaxlnGwA5AgloDAAABAAiAGkMAAAEAEMAawwAAAQAPQBqDAAABAA3AGwMAAAEAGIAbQwAAAEAUADqDAAABABEAG4MAAABAC4AbwwAAAEARwAiAAkJaxlnGwA5AgloDAAAAgAiAGkMAAACAEMAawwAAAMAPQBqDAAAAwA3AGwMAAADAGIAbQwAAAEAUADqDAAAAwBEAG4MAAABAC4AbwwAAAEARwAEAAYJix6ESwCbAQZoDAAAAgBDAGkMAAACAFIAawwAAAEARwBqDAAAAQBiAGwMAAABAFEA6gwAAAEAVwAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAAQAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
['Zà']='Zàpster:BAAALgAECgkJAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

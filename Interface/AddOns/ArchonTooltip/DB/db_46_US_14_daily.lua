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

local lookup = {'Priest-Discipline','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='daily',zone=46,date='2026-05-14',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAYJGAABAEEZAA==.',
Ae='Aerglo:BAAALgAECgYJDgAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEwAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8UAAMCAAYJhgoNEwC7AAZoDAAABAAxAGkMAAAEABUAawwAAAQAGgBqDAAABAAYAGwMAAADACAA6gwAAAEABAADAAYJqwOfpQDHAAZoDAAAAQADAGkMAAACAAwAawwAAAIADgBqDAAAAQAGAGwMAAACAAoA6gwAAAEABAACAAUJrQwNEwC7AAVoDAAAAwAxAGkMAAACABUAawwAAAIAGgBqDAAAAwAYAGwMAAABACAAAAA=.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAAALgAFFAIJAwAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8hAAIDAAgJgyBMEwBXAghoDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAEAGEAbQwAAAMAPwDqDAAABQBbAG4MAAADADkAAwAICYMgTBMAVwIIaAwAAAUAXgBpDAAABQBZAGsMAAAFAFgAagwAAAMAYQBsDAAABABhAG0MAAADAD8A6gwAAAUAWwBuDAAAAwA5AAAA.',
Ba='Banana:BAAALgADCgUJCQABLgAECgcJIAAEALcWAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIFAAcJiCQ6IQCmAgdoDAAABQBPAGkMAAAGAGAAawwAAAUAYQBqDAAAAwBJAGwMAAADAGAA6gwAAAQAXQBuDAAAAwBhAAUABwmIJDohAKYCB2gMAAAFAE8AaQwAAAYAYABrDAAABQBhAGoMAAADAEkAbAwAAAMAYADqDAAABABdAG4MAAADAGEAAAA=.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAFAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJEAAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8hAAIGAAgJNiIcEwCJAghoDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAEAGEAbQwAAAMAUQDqDAAABQBhAG4MAAADAD4ABgAICTYiHBMAiQIIaAwAAAUAYgBpDAAABQBZAGsMAAAFAFYAagwAAAMAUgBsDAAABABhAG0MAAADAFEA6gwAAAUAYQBuDAAAAwA+AAAA.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgQJBAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIHAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAHAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8wAAIIAAkJOiJBAgBfAwloDAAACABaAGkMAAAGAEsAawwAAAUAYABqDAAABgBfAGwMAAAGAFgAbQwAAAMAXQDqDAAACABSAG4MAAAFAFsAbwwAAAEASgAIAAkJOiJBAgBfAwloDAAACABaAGkMAAAGAEsAawwAAAUAYABqDAAABgBfAGwMAAAGAFgAbQwAAAMAXQDqDAAACABSAG4MAAAFAFsAbwwAAAEASgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8eAAIJAAgJyxeyCgCgAQhoDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAEAFIAbQwAAAMALgDqDAAABQA0AG4MAAADACUACQAICcsXsgoAoAEIaAwAAAQARQBpDAAABABGAGsMAAAEAEMAagwAAAMAOwBsDAAABABSAG0MAAADAC4A6gwAAAUANABuDAAAAwAlAAAA.',
Ck='Ckonquer:BAACLgAFFH8LAAIKAAMJwxZBGwDrAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQAKAAMJwxZBGwDrAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQAuAAQKfxoAAgoACQnNHqcEANgCAAoACQnNHqcEANgCAAAA.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMLAAYJUAjtCQCnAAZoDAAAAQAYAGkMAAABABYAawwAAAEAAABqDAAAAQAHAGwMAAABAAQA6gwAAAMANgAMAAQJAgntUwDKAARoDAAAAQAYAGkMAAABABYAagwAAAEABwDqDAAAAgAWAAsAAwm+B+0JAKcAA2sMAAABAAAAbAwAAAEABADqDAAAAQA2AAAA.',
Cz='Czaedyn:BAABLgAECn8pAAILAAkJRBLABADVAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwALAAkJRBLABADVAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAEABsAbQwAAAMABgDqDAAABgA+AG4MAAAEADsAbwwAAAEAFwAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECggJFgAIAJoEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMMAAcJ4hh1RAD+AQdoDAAABAA/AGkMAAADAEoAawwAAAUAUABqDAAAAwBFAGwMAAADAEMAbQwAAAEAFgDqDAAABABKAAwABwniGHVEAP4BB2gMAAAEAD8AaQwAAAMASgBrDAAABQBQAGoMAAABAEUAbAwAAAMAQwBtDAAAAQAWAOoMAAAEAEoADQABCQAACi0ARAABagwAAAIAOAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8hAAMOAAgJAAxgEABjAQhoDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAEACMAbQwAAAMAKQDqDAAABQAZAG4MAAADACcADgAICQAMYBAAYwEIaAwAAAUAEwBpDAAABQAQAGsMAAAFACMAagwAAAMAHwBsDAAABAAjAG0MAAADACkA6gwAAAUAGQBuDAAAAgAnAA8AAQnAAeJ0ABoAAW4MAAABAAQAAAA=.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIQAAgJPCGfDADYAghoDAAAAwBgAGkMAAAEAFsAawwAAAUAYgBqDAAABQBeAGwMAAAEAGEAbQwAAAIAOwDqDAAABABaAG4MAAABADQAEAAICTwhnwwA2AIIaAwAAAMAYABpDAAABABbAGsMAAAFAGIAagwAAAUAXgBsDAAABABhAG0MAAACADsA6gwAAAQAWgBuDAAAAQA0AAAA.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8eAAIMAAcJ1AvrXQAwAQdoDAAACAArAGkMAAAHACQAawwAAAUAJABqDAAABAAdAGwMAAACAB0AbQwAAAEAEADqDAAAAwAUAAwABwnUC+tdADABB2gMAAAIACsAaQwAAAcAJABrDAAABQAkAGoMAAAEAB0AbAwAAAIAHQBtDAAAAQAQAOoMAAADABQAAAA=.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAHAFgQAA==.',
Ev='Evi:BAAALgADCgkJCQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgADCgkJEwAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgcJHQAFAPYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8MAAIHAAQJ4Q41OQBFAQRoDAAABAAhAGkMAAAEADwAawwAAAEAHADqDAAAAwAeAAcABAnhDjU5AEUBBGgMAAAEACEAaQwAAAQAPABrDAAAAQAcAOoMAAADAB4ALgAECn8pAAIHAAgJFh7+KwAWAgAHAAgJFh7+KwAWAgAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.',
Gr='Greasemonkèy:BAABLgAECn8WAAIIAAgJmgSDZgD1AAhoDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgACAAICZoEg2YA9QAIaAwAAAUAGABpDAAAAwAEAGsMAAADAAQAagwAAAMACABsDAAAAwAQAG0MAAABAA0A6gwAAAMADABuDAAAAQAIAAAA.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgARAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgARAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAISAAcJZiQfAQDgAgdoDAAABQBfAGkMAAAEAGIAawwAAAQAYABqDAAAAwBdAGwMAAACAFQAbQwAAAIAWgDqDAAABABdABIABwlmJB8BAOACB2gMAAAFAF8AaQwAAAQAYgBrDAAABABgAGoMAAADAF0AbAwAAAIAVABtDAAAAgBaAOoMAAAEAF0AAAA=.Hotten:BAACLgAFFH8GAAIEAAQJMA6NDgAbAQRoDAAAAgAVAGkMAAABACcAawwAAAEAAADqDAAAAgBTAAQABAkwDo0OABsBBGgMAAACABUAaQwAAAEAJwBrDAAAAQAAAOoMAAACAFMALgAECn8YAAMEAAgJswxbEwCtAQAEAAgJswxbEwCtAQATAAYJjwLYlACTAAAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8cAAMUAAgJsQ93HQBqAQhoDAAABAAzAGkMAAAEACYAawwAAAQAPQBqDAAABAA8AGwMAAADACEAbQwAAAIAEgDqDAAABQArAG4MAAACACIAFAAICd0Odx0AagEIaAwAAAIAMwBpDAAAAgAmAGsMAAACAD0AagwAAAIAPABsDAAAAQAhAG0MAAABAAMA6gwAAAMAKwBuDAAAAgAiABUABwlFB2EsAPoAB2gMAAACAB0AaQwAAAIADwBrDAAAAgAZAGoMAAACADgAbAwAAAIABwBtDAAAAQASAOoMAAACAA8AAAA=.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgcJEwAAAA==.',
Ka='Kalmea:BAAALgAECgUJCAAAAA==.Kaoru:BAABLgAECn8gAAIWAAgJghPLCACKAQhoDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAEADEAbQwAAAMAGwDqDAAABQBKAG4MAAADADgAFgAICYITywgAigEIaAwAAAQAPQBpDAAABQAqAGsMAAAFACUAagwAAAMAPQBsDAAABAAxAG0MAAADABsA6gwAAAUASgBuDAAAAwA4AAAA.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgIJAgAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8xAAMMAAgJohkgIgAHAghoDAAACQBTAGkMAAAKAEQAawwAAAoAPgBqDAAABgBVAGwMAAAHADIAbQwAAAIAMwDqDAAAAwA9AG4MAAACAFAADAAICaIZICIABwIIaAwAAAYAUwBpDAAABwBEAGsMAAAHAD4AagwAAAIAVQBsDAAABQAyAG0MAAACADMA6gwAAAIAPQBuDAAAAgBQAAsABgl+DBEtAAkBBmgMAAADABMAaQwAAAMAOwBrDAAAAwAtAGoMAAAEAC0AbAwAAAIAFADqDAAAAQAOAAAA.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMXAAgJnx9ICAB0AghoDAAABgBfAGkMAAAGAFYAawwAAAYAUQBqDAAABQBTAGwMAAAFAFIAbQwAAAIAQwDqDAAABgBaAG4MAAADAD4AFwAICZ8fSAgAdAIIaAwAAAQAXwBpDAAABQBWAGsMAAAFAFEAagwAAAMAUwBsDAAAAgBSAG0MAAACAEMA6gwAAAUAWgBuDAAAAwA+ABgABglNFiI0AG4BBmgMAAACADsAaQwAAAEANwBrDAAAAQAyAGoMAAACADYAbAwAAAMANgDqDAAAAQBEAAAA.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAABLgAFFH8GAAIGAAMJYxZUVQD7AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAGAAMJYxZUVQD7AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAAAA==.Lifegiver:BAACLgAFFH8IAAMZAAMJVBcKGgD3AANoDAAAAwBTAGkMAAACABgA6gwAAAMARwAZAAMJVBcKGgD3AANoDAAAAgBTAGkMAAACABgA6gwAAAIARwAQAAIJOxV0NwCIAAJoDAAAAQAzAOoMAAABADkALgAECn8aAAMQAAgJKBpLFQBEAgAQAAgJKBpLFQBEAgAZAAMJaCFYRQAZAQAAAA==.Lindon:BAAALgADCgIJAgAAAA==.Listyn:BAACLgAFFH8JAAIQAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAQAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAuAAQKfx4AAhAABwnTEA00AG8BABAABwnTEA00AG8BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgQJBAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8aAAIaAAgJBBjKDAD2AQhoDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAADADsAbQwAAAIAMgDqDAAABABBAG4MAAADACIAGgAICQQYygwA9gEIaAwAAAQASABpDAAABABGAGsMAAAEAEsAagwAAAIALgBsDAAAAwA7AG0MAAACADIA6gwAAAQAQQBuDAAAAwAiAAAA.Mart:BAACLgAFFH8MAAIOAAQJMh8LDgBJAQRoDAAABABUAGkMAAADAEsAawwAAAIASQDqDAAAAwBWAA4ABAkyHwsOAEkBBGgMAAAEAFQAaQwAAAMASwBrDAAAAgBJAOoMAAADAFYALgAECn8pAAIOAAkJ4B3OBwAeAgAOAAkJ4B3OBwAeAgAAAA==.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAOADIfAA==.',
Mi='Miyafuji:BAABLgAECn8hAAMYAAgJ2iMZBgDDAghoDAAABQBWAGkMAAAFAGAAawwAAAUAXwBqDAAAAwBSAGwMAAAEAGIAbQwAAAMAYADqDAAABQBSAG4MAAADAF8AGAAICdojGQYAwwIIaAwAAAMAVgBpDAAABABgAGsMAAAEAF8AagwAAAIAUgBsDAAAAwBiAG0MAAADAGAA6gwAAAQAUgBuDAAAAwBfAAEABgnVHt4TAA4CBmgMAAACAFEAaQwAAAEAUQBrDAAAAQBMAGoMAAABAFAAbAwAAAEARwDqDAAAAQBRAAAA.',
Mo='Moonwell:BAACLgAFFH8MAAIQAAQJRCCFDwB6AQRoDAAABQBOAGkMAAADAFoAawwAAAEAQADqDAAAAwBgABAABAlEIIUPAHoBBGgMAAAFAE4AaQwAAAMAWgBrDAAAAQBAAOoMAAADAGAALgAECn8iAAIQAAgJ2CTpBAAtAwAQAAgJ2CTpBAAtAwAAAA==.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8SAAIEAAUJPCHYBAB7AQVoDAAABQBjAGkMAAAEAEkAawwAAAQASgBqDAAAAgBaAOoMAAADAFwABAAFCTwh2AQAewEFaAwAAAUAYwBpDAAABABJAGsMAAAEAEoAagwAAAIAWgDqDAAAAwBcAC4ABAp/KAAEBAAJCagilgQA0AIABAAJCagilgQA0AIAFgAECZ0PVmIAtwAAEwABCT8VvNEANAAAAAA=.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQARAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBQAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJDgABLgAECgcJGAASAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMbAAcJyxE9FQA/AQdoDAAACAA+AGkMAAAHAFIAawwAAAUAQABqDAAAAwBEAGwMAAACABUAbQwAAAEAFADqDAAAAwAWABsABwnLET0VAD8BB2gMAAAHAD4AaQwAAAUAUgBrDAAAAwBAAGoMAAADAEQAbAwAAAIAFQBtDAAAAQAUAOoMAAABABYAHAAECTQEuIMAsAAEaAwAAAEAAwBpDAAAAgANAGsMAAACABEA6gwAAAIACAAAAA==.Palanthir:BAABLgAECn8kAAIFAAkJXB7nIQAlAgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAFAAkJXB7nIQAlAgloDAAABgBPAGkMAAAFAFQAawwAAAQAUABqDAAABABLAGwMAAAEAFEAbQwAAAMANADqDAAABQBNAG4MAAAEAF8AbwwAAAEARQAAAA==.Pandapve:BAACLgAFFH8PAAMVAAQJpBxbBgBkAQRoDAAABwBGAGkMAAADAFMAawwAAAEAOQDqDAAABABSABUABAmkHFsGAGQBBGgMAAAGAEYAaQwAAAMAUwBrDAAAAQA5AOoMAAAEAFIAFAABCRAHtUUAOwABaAwAAAEAEgAuAAQKfycAAxUACAkMIa0IAGQCABUACAkMIa0IAGQCABQABgn3EF9QAAIBAAAA.',
Pe='Peja:BAAALgAECgYJDwAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgARAAAAAA==.',
Ph='Phu:BAACLgAFFH8QAAIZAAUJexh9DQAJAQVoDAAAAgA2AGkMAAAFAE0AawwAAAQAOwBqDAAAAQA3AOoMAAAEADsAGQAFCXsYfQ0ACQEFaAwAAAIANgBpDAAABQBNAGsMAAAEADsAagwAAAEANwDqDAAABAA7AC4ABAp/MQACGQAICeAkXQUASAMAGQAICeAkXQUASAMAAAA=.',
Po='Pockthelock:BAABLgAECn8XAAMNAAcJUxY2CgA2AQdoDAAABgBQAGkMAAAFAEYAawwAAAUARwBqDAAAAgBFAGwMAAABACYAbQwAAAEAEwDqDAAAAwA+AAwABwm4D+lRAE8BB2gMAAAFAC4AaQwAAAQAPQBrDAAABAA0AGoMAAACAEUAbAwAAAEAJgBtDAAAAQATAOoMAAACABYADQAECdIbNgoANgEEaAwAAAEAUABpDAAAAQBGAGsMAAABAEcA6gwAAAEAPgAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgUJDgARAAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8oAAIMAAkJKhfXJQDzAQloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgAMAAkJKhfXJQDzAQloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAEADcAbQwAAAMAJgDqDAAABgBIAG4MAAAFAEEAbwwAAAIALgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECggJEAAAAA==.Ravioli:BAABLgAECn8jAAIUAAgJbiVAAwDnAghoDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAFAGEAbQwAAAMAXgDqDAAABQBfAG4MAAADAFwAFAAICW4lQAMA5wIIaAwAAAUAYQBpDAAABQBhAGsMAAAFAGAAagwAAAQAYwBsDAAABQBhAG0MAAADAF4A6gwAAAUAXwBuDAAAAwBcAAEuAAQKBwkYABIAZiQA.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8eAAMHAAkJzQzSRAC5AQloDAAABQA3AGkMAAAFACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQAHAAkJzQzSRAC5AQloDAAABAA3AGkMAAAEACcAawwAAAUAKABqDAAAAwAYAGwMAAACACQAbQwAAAIABwDqDAAABQAnAG4MAAACABkAbwwAAAEAEQASAAIJOQT/GABQAAJoDAAAAQAJAGkMAAABAAwAAAA=.Rayliee:BAAALgADCgMJAwABLgAECgkJHgAHAM0MAA==.',
Rd='Rd:BAAALgADCgcJCAAAAA==.',
Rh='Rhyssa:BAABLgAECn8WAAIVAAYJmiBOGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAVAAYJmiBOGgAOAgZoDAAABABUAGkMAAAEAE8AawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAcAYAAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIFAAgJtBZIRQAUAghoDAAABABTAGkMAAADAEUAawwAAAQASgBqDAAAAgBDAGwMAAACAEoAbQwAAAEADwDqDAAAAwBFAG4MAAABABQABQAICbQWSEUAFAIIaAwAAAQAUwBpDAAAAwBFAGsMAAAEAEoAagwAAAIAQwBsDAAAAgBKAG0MAAABAA8A6gwAAAMARQBuDAAAAQAUAAAA.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQYAAcJxAusPgA/AQdoDAAABAA3AGkMAAAEABkAawwAAAUAJQBqDAAABAALAGwMAAAEAEUAbQwAAAEABADqDAAABQAFABgABwnEC6w+AD8BB2gMAAADADcAaQwAAAMAGQBrDAAABQAlAGoMAAACAAsAbAwAAAMARQBtDAAAAQAEAOoMAAAEAAUAFwAECSwBNloAUAAEaAwAAAEABABpDAAAAQACAGoMAAABAAYA6gwAAAEAAgABAAIJ6wFnUQBGAAJqDAAAAQAFAGwMAAABAAMAAAA=.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8pAAMPAAkJvguPHACGAQloDAAABwBHAGkMAAAGABEAawwAAAYAHgBqDAAABAAdAGwMAAAEABwAbQwAAAMAGgDqDAAABgAiAG4MAAAEAAwAbwwAAAEAEwAPAAkJvguPHACGAQloDAAABQBHAGkMAAAEABEAawwAAAQAHgBqDAAAAwAdAGwMAAAEABwAbQwAAAMAGgDqDAAABQAiAG4MAAAEAAwAbwwAAAEAEwAdAAUJwwEZMACWAAVoDAAAAgAGAGkMAAACAAAAawwAAAIABgBqDAAAAQARAOoMAAABAAMAAAA=.',
Se='Sempii:BAAALgAECgUJCQAAAA==.Serarlan:BAAALgAECgEJBQAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgAECgEJAQABLgAECgUJDgARAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAAALgAECggJEQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIeAAcJ2CCBCQCDAgdoDAAABABiAGkMAAAEAF0AawwAAAYAWgBqDAAABABbAGwMAAAEAFEAbQwAAAEAPQDqDAAABABOAB4ABwnYIIEJAIMCB2gMAAAEAGIAaQwAAAQAXQBrDAAABgBaAGoMAAAEAFsAbAwAAAQAUQBtDAAAAQA9AOoMAAAEAE4AAAA=.Slightcoyote:BAAALgAECgcJEAAAAA==.',
Sm='Smokeyh:BAACLgAFFH8NAAIUAAMJ5iENFAAsAQNoDAAABgBTAGkMAAABAFsA6gwAAAYAVQAUAAMJ5iENFAAsAQNoDAAABgBTAGkMAAABAFsA6gwAAAYAVQAuAAQKf0cAAxQACAneJDoDAOcCABQACAneJDoDAOcCABUAAQnMHWtXAFYAAAAA.',
Sn='Snow:BAABLgAECn8YAAIfAAcJRRtYFwBQAgdoDAAABABCAGkMAAAEAFkAawwAAAQAWwBqDAAAAwBEAGwMAAACAEIA6gwAAAYAXwBuDAAAAQAJAB8ABwlFG1gXAFACB2gMAAAEAEIAaQwAAAQAWQBrDAAABABbAGoMAAADAEQAbAwAAAIAQgDqDAAABgBfAG4MAAABAAkAAAA=.',
St='Strongtoast:BAAALgAECggJEgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAARAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgYJDAAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgIJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8lAAIMAAgJ+BR+MQC9AQhoDAAABwBQAGkMAAAFAEAAawwAAAcAOQBqDAAABgBRAGwMAAAFADkAbQwAAAEAHwDqDAAABQArAG4MAAABACkADAAICfgUfjEAvQEIaAwAAAcAUABpDAAABQBAAGsMAAAHADkAagwAAAYAUQBsDAAABQA5AG0MAAABAB8A6gwAAAUAKwBuDAAAAQApAAAA.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8ZAAMCAAgJiw0JDwD1AAhoDAAABAASAGkMAAAEACIAawwAAAQAIABqDAAABAAVAGwMAAAEACwAbQwAAAEAEADqDAAAAgAhAG4MAAACAD8AAgAHCeQKCQ8A9QAHaAwAAAQAEgBpDAAABAAiAGsMAAAEACAAagwAAAQAFQBsDAAAAgAsAG0MAAABABAA6gwAAAEAFQAgAAMJpw0sLgCbAANsDAAAAgAHAOoMAAABACEAbgwAAAIAPwAAAA==.',
To='Torí:BAABLgAECn8XAAIFAAgJvgmyowA5AQhoDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIABQAICb4JsqMAOQEIaAwAAAUAIABpDAAAAwAkAGsMAAADABgAagwAAAMAFQBsDAAAAwAeAG0MAAABAAoA6gwAAAQAFQBuDAAAAQASAAAA.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCAAAAA==.Vallkyr:BAABLgAECn8iAAIHAAkJ0x6YFQCSAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAHAAkJ0x6YFQCSAgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAITAAgJ7A77OQDHAQhoDAAABAAuAGkMAAADADYAawwAAAQALABqDAAAAgA8AGwMAAACAB8AbQwAAAEAKwDqDAAAAwAkAG4MAAABAAoAEwAICewO+zkAxwEIaAwAAAQALgBpDAAAAwA2AGsMAAAEACwAagwAAAIAPABsDAAAAgAfAG0MAAABACsA6gwAAAMAJABuDAAAAQAKAAAA.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAgAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgQJCQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEAAAAA==.Zitta:BAABLgAECn8eAAIhAAgJYhV8FwAEAghoDAAABQA8AGkMAAAFAD8AawwAAAUARwBqDAAABABDAGwMAAAEAEAAbQwAAAIAIADqDAAABABCAG4MAAABAAoAIQAICWIVfBcABAIIaAwAAAUAPABpDAAABQA/AGsMAAAFAEcAagwAAAQAQwBsDAAABABAAG0MAAACACAA6gwAAAQAQgBuDAAAAQAKAAAA.Zittav:BAABLgAECn8bAAMiAAkJaxlnGwA5AgloDAAABAAiAGkMAAAEAEMAawwAAAQAPQBqDAAABAA3AGwMAAAEAGIAbQwAAAEAUADqDAAABABEAG4MAAABAC4AbwwAAAEARwAiAAkJaxlnGwA5AgloDAAAAgAiAGkMAAACAEMAawwAAAMAPQBqDAAAAwA3AGwMAAADAGIAbQwAAAEAUADqDAAAAwBEAG4MAAABAC4AbwwAAAEARwAFAAYJix6qPwCqAQZoDAAAAgBDAGkMAAACAFIAawwAAAEARwBqDAAAAQBiAGwMAAABAFEA6gwAAAEAVwAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAASAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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

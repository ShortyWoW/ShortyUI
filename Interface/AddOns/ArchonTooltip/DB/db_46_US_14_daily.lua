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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Priest-Discipline','Warrior-Arms','Warrior-Fury','Paladin-Protection','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='daily',zone=46,date='2026-05-20',data={Ad='Adrestia:BAEALgAFFAIJAgAAAA==.',
Ae='Aerglo:BAABLgAECn8WAAQBAAYJahYdLAArAQZoDAAABABFAGkMAAAEADoAawwAAAQAQQBqDAAABAA/AGwMAAADACoA6gwAAAMAMgABAAYJ1hMdLAArAQZoDAAAAgA3AGkMAAABADgAawwAAAMAMQBqDAAABAA/AGwMAAADACoA6gwAAAIAMgACAAMJNBn4QgDKAANoDAAAAQBFAGkMAAACADoAawwAAAEAQQADAAMJ+gaEbABWAANoDAAAAQAQAGkMAAABABMA6gwAAAEAEQAAAA==.',
Al='Alidruid:BAAALgAECgQJBgAAAA==.',
An='Analog:BAABLgAECn8cAAMEAAgJEhwcJACzAQhoDAAABABNAGkMAAAEAFAAawwAAAQARgBqDAAABQA4AGwMAAAFACgAbQwAAAEAWwDqDAAABAA8AG4MAAABAGEABAAGCSQZHCQAswEGaAwAAAQATQBpDAAABABQAGsMAAAEAEYAagwAAAUAOABsDAAABAAoAOoMAAAEADwABQADCToJXPMAjQADbAwAAAEADQBtDAAAAQAhAG4MAAABABcAAAA=.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8aAAMGAAYJEQzqFgC2AAZoDAAABQAxAGkMAAAFABkAawwAAAUAGgBqDAAABQAYAGwMAAAEACAA6gwAAAIAFAAGAAUJrQzqFgC2AAVoDAAAAwAxAGkMAAACABUAawwAAAIAGgBqDAAAAwAYAGwMAAACACAABwAGCRoGm6sAlgAGaAwAAAIABgBpDAAAAwAZAGsMAAADAA4AagwAAAIAEABsDAAAAgAKAOoMAAACABQAAAA=.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8FAAIIAAIJixYsEgCQAAJoDAAAAgBKAOoMAAADACgACAACCYsWLBIAkAACaAwAAAIASgDqDAAAAwAoAAAA.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8mAAIHAAkJZSBADwCkAgloDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAFAGEAbQwAAAQAPwDqDAAABgBbAG4MAAAEADkAbwwAAAEAUAAHAAkJZSBADwCkAgloDAAABQBeAGkMAAAFAFkAawwAAAUAWABqDAAAAwBhAGwMAAAFAGEAbQwAAAQAPwDqDAAABgBbAG4MAAAEADkAbwwAAAEAUAAAAA==.',
Ba='Banana:BAAALgADCgUJCQAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIFAAcJiCQ6IQCmAgdoDAAABQBPAGkMAAAGAGAAawwAAAUAYQBqDAAAAwBJAGwMAAADAGAA6gwAAAQAXQBuDAAAAwBhAAUABwmIJDohAKYCB2gMAAAFAE8AaQwAAAYAYABrDAAABQBhAGoMAAADAEkAbAwAAAMAYADqDAAABABdAG4MAAADAGEAAAA=.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAFAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8mAAIJAAkJWCQ+BwAaAwloDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAFAGEAbQwAAAQAVADqDAAABgBhAG4MAAAEAGEAbwwAAAEAXQAJAAkJWCQ+BwAaAwloDAAABQBiAGkMAAAFAFkAawwAAAUAVgBqDAAAAwBSAGwMAAAFAGEAbQwAAAQAVADqDAAABgBhAG4MAAAEAGEAbwwAAAEAXQAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgYJCgAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIKAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAKAAYJMhuIjAC5AQZoDAAAAwBOAGkMAAAEAEwAawwAAAUASQBqDAAAAwA3AGwMAAADAC8A6gwAAAMARwAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn83AAILAAkJcyMTAgCDAwloDAAACQBgAGkMAAAHAEsAawwAAAYAYwBqDAAABwBgAGwMAAAHAFwAbQwAAAMAXQDqDAAACQBgAG4MAAAFAFsAbwwAAAIASgALAAkJcyMTAgCDAwloDAAACQBgAGkMAAAHAEsAawwAAAYAYwBqDAAABwBgAGwMAAAHAFwAbQwAAAMAXQDqDAAACQBgAG4MAAAFAFsAbwwAAAIASgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8jAAIMAAkJExozCAAJAgloDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAFAFgAbQwAAAQALgDqDAAABgBQAG4MAAAEADIAbwwAAAEAOwAMAAkJExozCAAJAgloDAAABABFAGkMAAAEAEYAawwAAAQAQwBqDAAAAwA7AGwMAAAFAFgAbQwAAAQALgDqDAAABgBQAG4MAAAEADIAbwwAAAEAOwAAAA==.',
Ck='Ckonquer:BAACLgAFFH8LAAINAAMJwxaFIADnAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQANAAMJwxaFIADnAANoDAAABAA/AGkMAAACABkA6gwAAAUAVQAuAAQKfxoAAg0ACQnNHqQHALcCAA0ACQnNHqQHALcCAAAA.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMOAAYJUAg5DACfAAZoDAAAAQAYAGkMAAABABYAawwAAAEAAABqDAAAAQAHAGwMAAABAAQA6gwAAAMANgAPAAQJAgkDYADKAARoDAAAAQAYAGkMAAABABYAagwAAAEABwDqDAAAAgAWAA4AAwm+BzkMAJ8AA2sMAAABAAAAbAwAAAEABADqDAAAAQA2AAAA.',
Cz='Czaedyn:BAABLgAECn8tAAIOAAkJlRQfBQDqAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAFACgAbQwAAAQAHADqDAAABgA+AG4MAAAFADsAbwwAAAIAJAAOAAkJlRQfBQDqAQloDAAABwBIAGkMAAAGADQAawwAAAYARABqDAAABAAcAGwMAAAFACgAbQwAAAQAHADqDAAABgA+AG4MAAAFADsAbwwAAAIAJAAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwALAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAAALgAECgcJDAAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMPAAcJ4hh1RAD+AQdoDAAABAA/AGkMAAADAEoAawwAAAUAUABqDAAAAwBFAGwMAAADAEMAbQwAAAEAFgDqDAAABABKAA8ABwniGHVEAP4BB2gMAAAEAD8AaQwAAAMASgBrDAAABQBQAGoMAAABAEUAbAwAAAMAQwBtDAAAAQAWAOoMAAAEAEoAEAABCQAACi0ARAABagwAAAIAOAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8mAAMRAAkJCg2rDgCyAQloDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAFAEUAbQwAAAQAKQDqDAAABgAZAG4MAAAEACcAbwwAAAEAFQARAAkJCg2rDgCyAQloDAAABQATAGkMAAAFABAAawwAAAUAIwBqDAAAAwAfAGwMAAAFAEUAbQwAAAQAKQDqDAAABgAZAG4MAAACACcAbwwAAAEAFQASAAEJwAGIhQAaAAFuDAAAAgAEAAAA.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAITAAgJPCGfDADYAghoDAAAAwBgAGkMAAAEAFsAawwAAAUAYgBqDAAABQBeAGwMAAAEAGEAbQwAAAIAOwDqDAAABABaAG4MAAABADQAEwAICTwhnwwA2AIIaAwAAAMAYABpDAAABABbAGsMAAAFAGIAagwAAAUAXgBsDAAABABhAG0MAAACADsA6gwAAAQAWgBuDAAAAQA0AAAA.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8fAAIPAAcJAQwZcQA4AQdoDAAACAArAGkMAAAHACQAawwAAAUAJABqDAAABAAdAGwMAAACAB0AbQwAAAEAEADqDAAABAAWAA8ABwkBDBlxADgBB2gMAAAIACsAaQwAAAcAJABrDAAABQAkAGoMAAAEAB0AbAwAAAIAHQBtDAAAAQAQAOoMAAAEABYAAAA=.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAKAFgQAA==.',
Ev='Evi:BAAALgADCgkJCQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgcJHgAFAPYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8MAAIKAAQJ4Q5ERQA7AQRoDAAABAAhAGkMAAAEADwAawwAAAEAHADqDAAAAwAeAAoABAnhDkRFADsBBGgMAAAEACEAaQwAAAQAPABrDAAAAQAcAOoMAAADAB4ALgAECn8uAAIKAAgJJh5MKwBDAgAKAAgJJh5MKwBDAgAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgcJBQABLgAECgkJLQAFAEsfAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAILAAkJnASDZgD1AAloDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgAbwwAAAEACwALAAkJnASDZgD1AAloDAAABQAYAGkMAAADAAQAawwAAAMABABqDAAAAwAIAGwMAAADABAAbQwAAAEADQDqDAAAAwAMAG4MAAABAAgAbwwAAAEACwAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAUAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAUAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIVAAcJZiQfAQDgAgdoDAAABQBfAGkMAAAEAGIAawwAAAQAYABqDAAAAwBdAGwMAAACAFQAbQwAAAIAWgDqDAAABABdABUABwlmJB8BAOACB2gMAAAFAF8AaQwAAAQAYgBrDAAABABgAGoMAAADAF0AbAwAAAIAVABtDAAAAgBaAOoMAAAEAF0AAAA=.Hotten:BAACLgAFFH8IAAIWAAQJFhAJEQAbAQRoDAAAAwAoAGkMAAABACcAawwAAAEAAADqDAAAAwBTABYABAkWEAkRABsBBGgMAAADACgAaQwAAAEAJwBrDAAAAQAAAOoMAAADAFMALgAECn8YAAMWAAgJswxBGgCkAQAWAAgJswxBGgCkAQAXAAYJjwLKsQCRAAAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8mAAMCAAgJcxKnHQCSAQhoDAAABQAzAGkMAAAFACYAawwAAAUAPQBqDAAABQA8AGwMAAAEADUAbQwAAAQAHwDqDAAABgAwAG4MAAAEAC0AAgAICXMSpx0AkgEIaAwAAAMAMwBpDAAAAwAmAGsMAAADAD0AagwAAAMAPABsDAAAAgA1AG0MAAADAB8A6gwAAAQAMABuDAAABAAtAAEABwlFBxw3APMAB2gMAAACAB0AaQwAAAIADwBrDAAAAgAZAGoMAAACADgAbAwAAAIABwBtDAAAAQASAOoMAAACAA8AAAA=.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAABLgAECn8UAAIJAAcJbAtJhQAuAQdoDAAABgA+AGkMAAAEABwAawwAAAMAGwBqDAAAAgAQAGwMAAABABIA6gwAAAMAHQBuDAAAAQAIAAkABwlsC0mFAC4BB2gMAAAGAD4AaQwAAAQAHABrDAAAAwAbAGoMAAACABAAbAwAAAEAEgDqDAAAAwAdAG4MAAABAAgAAAA=.',
Ka='Kalmea:BAAALgAECgYJCgAAAA==.Kaoru:BAABLgAECn8lAAIYAAkJWRS0BwDYAQloDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAFADEAbQwAAAQAOQDqDAAABgBKAG4MAAAEADgAbwwAAAEAJAAYAAkJWRS0BwDYAQloDAAABAA9AGkMAAAFACoAawwAAAUAJQBqDAAAAwA9AGwMAAAFADEAbQwAAAQAOQDqDAAABgBKAG4MAAAEADgAbwwAAAEAJAAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgIJAgAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn85AAMPAAgJxxnqKwAHAghoDAAACwBTAGkMAAAMAEQAawwAAA0AQABqDAAABgBVAGwMAAAHADIAbQwAAAIAMwDqDAAAAwA9AG4MAAADAFAADwAICccZ6isABwIIaAwAAAgAUwBpDAAACQBEAGsMAAAKAEAAagwAAAIAVQBsDAAABQAyAG0MAAACADMA6gwAAAIAPQBuDAAAAwBQAA4ABgl+DBEtAAkBBmgMAAADABMAaQwAAAMAOwBrDAAAAwAtAGoMAAAEAC0AbAwAAAIAFADqDAAAAQAOAAAA.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMZAAgJnx+hDABXAghoDAAABgBfAGkMAAAGAFYAawwAAAYAUQBqDAAABQBTAGwMAAAFAFIAbQwAAAIAQwDqDAAABgBaAG4MAAADAD4AGQAICZ8foQwAVwIIaAwAAAQAXwBpDAAABQBWAGsMAAAFAFEAagwAAAMAUwBsDAAAAgBSAG0MAAACAEMA6gwAAAUAWgBuDAAAAwA+ABoABglNFiI0AG4BBmgMAAACADsAaQwAAAEANwBrDAAAAQAyAGoMAAACADYAbAwAAAMANgDqDAAAAQBEAAAA.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAECgYJBgABLgAFFAMJCQATADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAECgQJBgAAAA==.Lifedeclined:BAABLgAFFH8GAAIJAAMJYxbfZgD2AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAJAAMJYxbfZgD2AANoDAAAAgAvAGkMAAACADsA6gwAAAIAQAAAAA==.Lifegiver:BAACLgAFFH8IAAMbAAMJVBfxHgDrAANoDAAAAwBTAGkMAAACABgA6gwAAAMARwAbAAMJVBfxHgDrAANoDAAAAgBTAGkMAAACABgA6gwAAAIARwATAAIJOxUvPwCIAAJoDAAAAQAzAOoMAAABADkALgAECn8cAAMTAAgJKBqAGgBCAgATAAgJKBqAGgBCAgAbAAUJPCJYRQAZAQAAAA==.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAITAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwATAAMJMQOzGgCSAANoDAAABAAIAGkMAAABAAAA6gwAAAQADwAuAAQKfx4AAhMABwnTEIc9AG8BABMABwnTEIc9AG8BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgYJCgAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8eAAIcAAkJLRnKDAD2AQloDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAAEAEoAbQwAAAMANgDqDAAABABBAG4MAAAEACwAbwwAAAEAOAAcAAkJLRnKDAD2AQloDAAABABIAGkMAAAEAEYAawwAAAQASwBqDAAAAgAuAGwMAAAEAEoAbQwAAAMANgDqDAAABABBAG4MAAAEACwAbwwAAAEAOAAAAA==.Mart:BAACLgAFFH8MAAIRAAQJMh9wEABDAQRoDAAABABUAGkMAAADAEsAawwAAAIASQDqDAAAAwBWABEABAkyH3AQAEMBBGgMAAAEAFQAaQwAAAMASwBrDAAAAgBJAOoMAAADAFYALgAECn8pAAIRAAkJ4B3sDABnAgARAAkJ4B3sDABnAgAAAA==.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAARADIfAA==.',
Mi='Miyafuji:BAABLgAECn8qAAMaAAkJ6CMLBAAhAwloDAAABgBWAGkMAAAGAGAAawwAAAYAXwBqDAAABABSAGwMAAAFAGIAbQwAAAQAYADqDAAABgBSAG4MAAAEAF8AbwwAAAEAXQAaAAkJ6CMLBAAhAwloDAAAAwBWAGkMAAAEAGAAawwAAAQAXwBqDAAAAgBSAGwMAAAEAGIAbQwAAAQAYADqDAAABABSAG4MAAAEAF8AbwwAAAEAXQAdAAYJ1R7eEwAOAgZoDAAAAwBRAGkMAAACAFEAawwAAAIATABqDAAAAgBQAGwMAAABAEcA6gwAAAIAUQAAAA==.',
Mo='Moonwell:BAACLgAFFH8QAAITAAQJRCA4EwB5AQRoDAAABgBOAGkMAAAEAFoAawwAAAIAQADqDAAABABgABMABAlEIDgTAHkBBGgMAAAGAE4AaQwAAAQAWgBrDAAAAgBAAOoMAAAEAGAALgAECn8jAAITAAgJ2CSxBgApAwATAAgJ2CSxBgApAwAAAA==.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8VAAIWAAUJOyO6BACMAQVoDAAABQBjAGkMAAAFAEkAawwAAAUAXgBqDAAAAwBaAOoMAAADAFwAFgAFCTsjugQAjAEFaAwAAAUAYwBpDAAABQBJAGsMAAAFAF4AagwAAAMAWgDqDAAAAwBcAC4ABAp/KgAEFgAJCb8jlgQA0AIAFgAJCb8jlgQA0AIAGAAECZ0PVmIAtwAAFwABCT8VvNEANAAAAAA=.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAUAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgUJEwABLgAECgcJGAAVAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMeAAcJyxFwHwAqAQdoDAAACAA+AGkMAAAHAFIAawwAAAUAQABqDAAAAwBEAGwMAAACABUAbQwAAAEAFADqDAAAAwAWAB4ABwnLEXAfACoBB2gMAAAHAD4AaQwAAAUAUgBrDAAAAwBAAGoMAAADAEQAbAwAAAIAFQBtDAAAAQAUAOoMAAABABYAHwAECTQEuIMAsAAEaAwAAAEAAwBpDAAAAgANAGsMAAACABEA6gwAAAIACAAAAA==.Palanthir:BAABLgAECn8tAAIFAAkJSx8MDgDVAgloDAAABwBPAGkMAAAGAFYAawwAAAUAUwBqDAAABQBLAGwMAAAFAFUAbQwAAAMANADqDAAABwBYAG4MAAAGAF8AbwwAAAEARQAFAAkJSx8MDgDVAgloDAAABwBPAGkMAAAGAFYAawwAAAUAUwBqDAAABQBLAGwMAAAFAFUAbQwAAAMANADqDAAABwBYAG4MAAAGAF8AbwwAAAEARQAAAA==.Pandapve:BAACLgAFFH8TAAMBAAQJ4iCUBACRAQRoDAAACABhAGkMAAAEAFQAawwAAAIAOQDqDAAABQBhAAEABAniIJQEAJEBBGgMAAAHAGEAaQwAAAQAVABrDAAAAgA5AOoMAAAFAGEAAgABCRAHLUwAOwABaAwAAAEAEgAuAAQKfykAAwEACAkMIWAMAEwCAAEACAkMIWAMAEwCAAIABgkpEV9QAAIBAAAA.',
Pe='Peja:BAAALgAECgcJEQAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAUAAAAAA==.',
Ph='Phu:BAACLgAFFH8RAAIbAAUJexh9DQAJAQVoDAAAAgA2AGkMAAAFAE0AawwAAAQAOwBqDAAAAgA3AOoMAAAEADsAGwAFCXsYfQ0ACQEFaAwAAAIANgBpDAAABQBNAGsMAAAEADsAagwAAAIANwDqDAAABAA7AC4ABAp/MQACGwAICeAkXQUASAMAGwAICeAkXQUASAMAAAA=.',
Po='Pockthelock:BAABLgAECn8eAAMQAAcJdhgLCgB5AQdoDAAABwBQAGkMAAAGAEYAawwAAAYARwBqDAAAAwBSAGwMAAADAEYAbQwAAAEAEwDqDAAABABAABAABgnYGwsKAHkBBmgMAAACAFAAaQwAAAIARgBrDAAAAgBHAGoMAAABAFIAbAwAAAIARgDqDAAAAgBAAA8ABwm4DxhnAE8BB2gMAAAFAC4AaQwAAAQAPQBrDAAABAA0AGoMAAACAEUAbAwAAAEAJgBtDAAAAQATAOoMAAACABYAAAA=.',
Pu='Puds:BAAALgADCggJEwABLgAECgEJAQAUAAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8sAAIPAAkJMxjWLAADAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAFADcAbQwAAAQAJgDqDAAABgBIAG4MAAAGAEEAbwwAAAMAQwAPAAkJMxjWLAADAgloDAAABgBDAGkMAAAFAEQAawwAAAUAPABqDAAABABOAGwMAAAFADcAbQwAAAQAJgDqDAAABgBIAG4MAAAGAEEAbwwAAAMAQwAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAABLgAECn8XAAQFAAgJyQz5nwAMAQhoDAAAAwAQAGkMAAADACMAawwAAAMAMQBqDAAABAATAGwMAAADAAgAbQwAAAEAYQDqDAAABAAEAG4MAAACABAABQAHCYsI+Z8ADAEHaAwAAAIAEABpDAAAAwAjAGsMAAADADEAagwAAAMAEwBsDAAAAQAIAOoMAAACAAQAbgwAAAEAEAAEAAUJjALZVwCaAAVoDAAAAQAEAGoMAAABAAQAbAwAAAIADQBtDAAAAQAFAG4MAAABAAQAIAABCZYBMEwAEAAB6gwAAAIABAAAAA==.Ravioli:BAABLgAECn8oAAICAAkJnCUIAQBWAwloDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAGAGIAbQwAAAQAYQDqDAAABgBgAG4MAAAEAF8AbwwAAAEAWwACAAkJnCUIAQBWAwloDAAABQBhAGkMAAAFAGEAawwAAAUAYABqDAAABABjAGwMAAAGAGIAbQwAAAQAYQDqDAAABgBgAG4MAAAEAF8AbwwAAAEAWwABLgAECgcJGAAVAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMKAAkJuA08TwDGAQloDAAABgA3AGkMAAAGACcAawwAAAYAKABqDAAABAAeAGwMAAACACQAbQwAAAIABwDqDAAABgA5AG4MAAACABkAbwwAAAEAEQAKAAkJuA08TwDGAQloDAAABQA3AGkMAAAFACcAawwAAAYAKABqDAAABAAeAGwMAAACACQAbQwAAAIABwDqDAAABgA5AG4MAAACABkAbwwAAAEAEQAVAAIJOQT/GABQAAJoDAAAAQAJAGkMAAABAAwAAAA=.Rayliee:BAAALgADCgMJAwABLgAECgkJIwAKALgNAA==.',
Rd='Rd:BAAALgAECgcJCAAAAA==.',
Re='Ret:BAAALgAECgYJBgAAAA==.',
Rh='Rhyssa:BAABLgAECn8ZAAIBAAcJwCCCFwDFAQdoDAAABABUAGkMAAAFAFIAawwAAAUATABqDAAAAQBdAGwMAAABAE8A6gwAAAgAYABuDAAAAQBTAAEABwnAIIIXAMUBB2gMAAAEAFQAaQwAAAUAUgBrDAAABQBMAGoMAAABAF0AbAwAAAEATwDqDAAACABgAG4MAAABAFMAAAA=.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIFAAgJtBZIRQAUAghoDAAABABTAGkMAAADAEUAawwAAAQASgBqDAAAAgBDAGwMAAACAEoAbQwAAAEADwDqDAAAAwBFAG4MAAABABQABQAICbQWSEUAFAIIaAwAAAQAUwBpDAAAAwBFAGsMAAAEAEoAagwAAAIAQwBsDAAAAgBKAG0MAAABAA8A6gwAAAMARQBuDAAAAQAUAAAA.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQaAAcJxAusPgA/AQdoDAAABAA3AGkMAAAEABkAawwAAAUAJQBqDAAABAALAGwMAAAEAEUAbQwAAAEABADqDAAABQAFABoABwnEC6w+AD8BB2gMAAADADcAaQwAAAMAGQBrDAAABQAlAGoMAAACAAsAbAwAAAMARQBtDAAAAQAEAOoMAAAEAAUAGQAECSwBNloAUAAEaAwAAAEABABpDAAAAQACAGoMAAABAAYA6gwAAAEAAgAdAAIJ6wFnUQBGAAJqDAAAAQAFAGwMAAABAAMAAAA=.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8tAAMSAAkJYw1NIgCZAQloDAAABwBHAGkMAAAGABEAawwAAAYAHgBqDAAABAAdAGwMAAAFACsAbQwAAAQAKwDqDAAABgAiAG4MAAAFAAwAbwwAAAIAFQASAAkJYw1NIgCZAQloDAAABQBHAGkMAAAEABEAawwAAAQAHgBqDAAAAwAdAGwMAAAFACsAbQwAAAQAKwDqDAAABQAiAG4MAAAFAAwAbwwAAAIAFQAhAAUJwwEZMACWAAVoDAAAAgAGAGkMAAACAAAAawwAAAIABgBqDAAAAQARAOoMAAABAAMAAAA=.',
Se='Sempii:BAAALgAECgUJCQAAAA==.Serarlan:BAAALgAECgEJBgAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgAECgEJAQAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8ZAAIKAAgJVg7KYgCSAQhoDAAABAAwAGkMAAAEACcAawwAAAQAKABqDAAAAgA1AGwMAAACABcAbQwAAAEAEgDqDAAABgAzAG4MAAACACMACgAICVYOymIAkgEIaAwAAAQAMABpDAAABAAnAGsMAAAEACgAagwAAAIANQBsDAAAAgAXAG0MAAABABIA6gwAAAYAMwBuDAAAAgAjAAAA.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIiAAcJ2CCBCQCDAgdoDAAABABiAGkMAAAEAF0AawwAAAYAWgBqDAAABABbAGwMAAAEAFEAbQwAAAEAPQDqDAAABABOACIABwnYIIEJAIMCB2gMAAAEAGIAaQwAAAQAXQBrDAAABgBaAGoMAAAEAFsAbAwAAAQAUQBtDAAAAQA9AOoMAAAEAE4AAAA=.Slightcoyote:BAAALgAECggJEwAAAA==.',
Sm='Smokeyh:BAACLgAFFH8RAAICAAQJRyBeDAB7AQRoDAAABwBTAGkMAAACAF0AawwAAAEARADqDAAABwBVAAIABAlHIF4MAHsBBGgMAAAHAFMAaQwAAAIAXQBrDAAAAQBEAOoMAAAHAFUALgAECn9HAAMCAAgJ3iRtBADeAgACAAgJ3iRtBADeAgABAAEJzB2cZgBUAAAAAA==.',
Sn='Snow:BAABLgAECn8YAAIjAAcJRRtYFwBQAgdoDAAABABCAGkMAAAEAFkAawwAAAQAWwBqDAAAAwBEAGwMAAACAEIA6gwAAAYAXwBuDAAAAQAJACMABwlFG1gXAFACB2gMAAAEAEIAaQwAAAQAWQBrDAAABABbAGoMAAADAEQAbAwAAAIAQgDqDAAABgBfAG4MAAABAAkAAAA=.',
St='Strongtoast:BAAALgAECggJEgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAAUAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgYJBwAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8qAAIPAAgJuxZsOgDOAQhoDAAACABQAGkMAAAGAEAAawwAAAgAOQBqDAAABgBRAGwMAAAFADkAbQwAAAEAHwDqDAAABgA7AG4MAAACADkADwAICbsWbDoAzgEIaAwAAAgAUABpDAAABgBAAGsMAAAIADkAagwAAAYAUQBsDAAABQA5AG0MAAABAB8A6gwAAAYAOwBuDAAAAgA5AAAA.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8ZAAMGAAgJiw0dEgDxAAhoDAAABAASAGkMAAAEACIAawwAAAQAIABqDAAABAAVAGwMAAAEACwAbQwAAAEAEADqDAAAAgAhAG4MAAACAD8ABgAHCeQKHRIA8QAHaAwAAAQAEgBpDAAABAAiAGsMAAAEACAAagwAAAQAFQBsDAAAAgAsAG0MAAABABAA6gwAAAEAFQAkAAMJpw3XNwCXAANsDAAAAgAHAOoMAAABACEAbgwAAAIAPwAAAA==.',
To='Torí:BAABLgAECn8YAAIFAAkJZwmyowA5AQloDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIAbwwAAAEAEQAFAAkJZwmyowA5AQloDAAABQAgAGkMAAADACQAawwAAAMAGABqDAAAAwAVAGwMAAADAB4AbQwAAAEACgDqDAAABAAVAG4MAAABABIAbwwAAAEAEQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCwAAAA==.Vallkyr:BAABLgAECn8iAAIKAAkJ0x77HgB+AgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAKAAkJ0x77HgB+AgloDAAABABfAGkMAAAEAFEAawwAAAQANgBqDAAAAwBWAGwMAAAEAE0AbQwAAAMAVgDqDAAABQBcAG4MAAAFADgAbwwAAAIAVwAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIXAAgJ7A77OQDHAQhoDAAABAAuAGkMAAADADYAawwAAAQALABqDAAAAgA8AGwMAAACAB8AbQwAAAEAKwDqDAAAAwAkAG4MAAABAAoAFwAICewO+zkAxwEIaAwAAAQALgBpDAAAAwA2AGsMAAAEACwAagwAAAIAPABsDAAAAgAfAG0MAAABACsA6gwAAAMAJABuDAAAAQAKAAAA.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAwAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgYJDwAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgcJEgAAAA==.Zitta:BAABLgAECn8eAAIDAAgJYhV8FwAEAghoDAAABQA8AGkMAAAFAD8AawwAAAUARwBqDAAABABDAGwMAAAEAEAAbQwAAAIAIADqDAAABABCAG4MAAABAAoAAwAICWIVfBcABAIIaAwAAAUAPABpDAAABQA/AGsMAAAFAEcAagwAAAQAQwBsDAAABABAAG0MAAACACAA6gwAAAQAQgBuDAAAAQAKAAAA.Zittav:BAABLgAECn8bAAMEAAkJaxlnGwA5AgloDAAABAAiAGkMAAAEAEMAawwAAAQAPQBqDAAABAA3AGwMAAAEAGIAbQwAAAEAUADqDAAABABEAG4MAAABAC4AbwwAAAEARwAEAAkJaxlnGwA5AgloDAAAAgAiAGkMAAACAEMAawwAAAMAPQBqDAAAAwA3AGwMAAADAGIAbQwAAAEAUADqDAAAAwBEAG4MAAABAC4AbwwAAAEARwAFAAYJix6dWwCSAQZoDAAAAgBDAGkMAAACAFIAawwAAAEARwBqDAAAAQBiAGwMAAABAFEA6gwAAAEAVwAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAAVAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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

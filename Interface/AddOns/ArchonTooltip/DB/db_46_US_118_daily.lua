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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Unknown-Unknown','Druid-Feral','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Warrior-Arms','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Druid-Guardian','DemonHunter-Havoc','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-05-31',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8KAAIBAAQJeAZ2JgD8AARoDAAAAwANAGkMAAADABgAawwAAAEACQDqDAAAAwASAAEABAl4BnYmAPwABGgMAAADAA0AaQwAAAMAGABrDAAAAQAJAOoMAAADABIALgAECn9CAAIBAAkJBBvuFAA3AgABAAkJBBvuFAA3AgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwACAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCAADAKYbAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCAADAKYbAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCAADAKYbAA==.Arathrok:BAACLgAFFH8IAAIDAAMJphugcgD8AANoDAAABABMAGkMAAADAFgA6gwAAAEALwADAAMJphugcgD8AANoDAAABABMAGkMAAADAFgA6gwAAAEALwAuAAQKfx4AAgMACQmLIPRKANEBAAMACQmLIPRKANEBAAAA.',
As='Asha:BAACLgAFFH8TAAMEAAUJ/xbcDwArAQVoDAAABABHAGkMAAAEADEAawwAAAQATgBqDAAAAwA7AOoMAAAEACQABAAFCf8W3A8AKwEFaAwAAAMARwBpDAAAAwAxAGsMAAADAE4AagwAAAIAOwDqDAAAAwAkAAUABQntBeMsAN8ABWgMAAABABYAaQwAAAEADQBrDAAAAQAPAGoMAAABABQA6gwAAAEACAAuAAQKfxwABAQACAnLIK0aAMUBAAQACAnLIK0aAMUBAAYABAnQHMM+AEQBAAUABQnGGYA0AB0BAAAA.Asmoday:BAABLgAECn8pAAIDAAkJziLtDQDtAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgADAAkJziLtDQDtAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgAAAA==.Astra:BAAALgAECgEJAQABLgAECgYJCwAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7wqZGAApAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe8KmRgAKQEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAECgQJBAABLgAFFAQJFAAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCXPAABXAwloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAIAAkJZCXPAABXAwloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxvWDAAJAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAKAAkJAxvWDAAJAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCAALAGAgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAcJEgAMAI4RAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAAALgAFFAgJBAAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8IAAILAAMJYCBpQgASAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwALAAMJYCBpQgASAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwAuAAQKfyIAAgsACQnBI2YTALsCAAsACQnBI2YTALsCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgADCgYJCwAAAA==.',
Cy='Cylla:BAACLgAFFH8TAAIOAAQJlAw+WwAcAQRoDAAABgAuAGkMAAAGABIAawwAAAIADQDqDAAABQAxAA4ABAmUDD5bABwBBGgMAAAGAC4AaQwAAAYAEgBrDAAAAgANAOoMAAAFADEALgAECn86AAIOAAkJfBy0LABRAgAOAAkJfBy0LABRAgAAAA==.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8WAAMPAAYJQAtiHwDpAAZoDAAAAwA4AGkMAAAEABMAawwAAAQAHQBqDAAABQASAGwMAAACAB0A6gwAAAQAEgAPAAYJQAtiHwDpAAZoDAAAAwA4AGkMAAADABMAawwAAAMAHQBqDAAABQASAGwMAAACAB0A6gwAAAQAEgAQAAIJ1QJegwA2AAJpDAAAAQAGAGsMAAABAAcAAAA=.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8NAAIRAAQJWRIlJwARAQRoDAAABgA7AGkMAAAEACEAawwAAAEAGADqDAAAAgBFABEABAlZEiUnABEBBGgMAAAGADsAaQwAAAQAIQBrDAAAAQAYAOoMAAACAEUALgAECn84AAIRAAkJPh9uCAAkAwARAAkJPh9uCAAkAwAAAA==.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH84AAIKAAgJUyOcAADMAghoDAAACgBjAGkMAAAJAGEAawwAAAkAXgBqDAAABwBfAGwMAAAFAGEAbQwAAAQASADqDAAACgBhAG4MAAACAEoACgAICVMjnAAAzAIIaAwAAAoAYwBpDAAACQBhAGsMAAAJAF4AagwAAAcAXwBsDAAABQBhAG0MAAAEAEgA6gwAAAoAYQBuDAAAAgBKAC4ABAp/aAACCgAJCYImNgAAhwMACgAJCYImNgAAhwMAAAA=.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBAABLgAFFAgJOAAKAFMjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8gAAMKAAcJjxXDHgAlAQdoDAAABgAjAGkMAAAGADMAawwAAAUALQBqDAAAAwBHAGwMAAAEAFEA6gwAAAcAOgBuDAAAAQA5AAEABglLFDc8AEEBBmgMAAAEACMAaQwAAAQALgBrDAAAAwAlAGoMAAACAEcAbAwAAAEAUQDqDAAABgA6AAoABwleEMMeACUBB2gMAAACABUAaQwAAAIAMwBrDAAAAgAtAGoMAAABAEMAbAwAAAMAIwDqDAAAAQAnAG4MAAABADkAAAA=.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFAAKAIUlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8rAAISAAgJYiLSAAByAghoDAAACABfAGkMAAAHAF4AawwAAAUAYQBqDAAABgBcAGwMAAAFAGAAbQwAAAIAMgDqDAAACQBZAG4MAAABAFcAEgAICWIi0gAAcgIIaAwAAAgAXwBpDAAABwBeAGsMAAAFAGEAagwAAAYAXABsDAAABQBgAG0MAAACADIA6gwAAAkAWQBuDAAAAQBXAC4ABAp/QQAEEgAJCaUl2gAAygMAEgAJCaUl2gAAygMAEwAHCRIRQC8AhgEAFAACCdwhukYAyQAAAAA=.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCAALAGAgAA==.Geronimô:BAAALgAECgQJBQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAYJFgAVACIWAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8cAAILAAYJcQteyADgAAZoDAAABgAhAGkMAAAGABYAawwAAAYAFwBqDAAABQAzAGwMAAAEACkA6gwAAAEAGAALAAYJcQteyADgAAZoDAAABgAhAGkMAAAGABYAawwAAAYAFwBqDAAABQAzAGwMAAAEACkA6gwAAAEAGAAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Hu='Huugg:BAAALgADCgMJAwAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMTAAMJXhZxHAC1AANoDAAABAAyAGkMAAADADYA6gwAAAIAQwATAAMJBxJxHAC1AANoDAAABAAyAGkMAAACADYA6gwAAAEAIQASAAIJ7hGKMQCSAAJpDAAAAQAYAOoMAAABAEMALgAECn8vAAQSAAkJYhywEgAdAgASAAgJxR6wEgAdAgAUAAcJ/wyaMgAwAQATAAQJjgl5TQCSAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJIAAKAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxO/JwABAgloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgARAAkJpxO/JwABAgloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIWAAkJ/yElEAC9AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAWAAkJ/yElEAC9AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECgMJAwAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxzpCwCEAgloDAAABgBAAGkMAAAFADgAawwAAAUAUABqDAAABABJAGwMAAAGAE4AbQwAAAQARQDqDAAABgBZAG4MAAAEAE4AbwwAAAIAOgAQAAkJDxzpCwCEAgloDAAABABAAGkMAAADADgAawwAAAMAUABqDAAAAgBJAGwMAAAEAE4AbQwAAAQARQDqDAAAAwBZAG4MAAAEAE4AbwwAAAIAOgAXAAYJmQ4+EAD1AAZoDAAAAgAjAGkMAAACACUAawwAAAIANQBqDAAAAgAeAGwMAAACABMA6gwAAAMAKQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR2rBgCLAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAKAAkJWR2rBgCLAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIOAAkJvBy6GgClAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAOAAkJvBy6GgClAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCgABLgAFFAQJFAAKAIUlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAFFAQJAQABLgAFFAgJBAAHAAAAAA==.Misfortune:BAAALgAECggJDgABLgAFFAMJCAALAGAgAA==.Mitsy:BAABLgAECn8mAAIUAAgJ+RRxHQC+AQhoDAAABgA9AGkMAAAFADMAawwAAAUANgBqDAAABQA+AGwMAAAFAD0AbQwAAAIAHQDqDAAABgBEAG4MAAAEAC8AFAAICfkUcR0AvgEIaAwAAAYAPQBpDAAABQAzAGsMAAAFADYAagwAAAUAPgBsDAAABQA9AG0MAAACAB0A6gwAAAYARABuDAAABAAvAAAA.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACwAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAYAAIJcAczcQBbAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAABLgAECn8WAAMZAAkJ7RTTGAA9AQloDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAwBGAGwMAAACAC8AbQwAAAEAGADqDAAAAgBBAG4MAAABACQAbwwAAAEAFwAZAAUJBh3TGAA9AQVoDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAQBGAOoMAAABAEEACwAGCWcNwLUA+wAGagwAAAIAQgBsDAAAAgAvAG0MAAABABgA6gwAAAEAKABuDAAAAQAkAG8MAAABABcAAAA=.Moons:BAACLgAFFH8SAAIMAAcJjhHaAgDZAQdoDAAABABVAGkMAAAFADAAawwAAAMALgBqDAAAAQAgAGwMAAABACAAbQwAAAEAEQDqDAAAAwAoAAwABwmOEdoCANkBB2gMAAAEAFUAaQwAAAUAMABrDAAAAwAuAGoMAAABACAAbAwAAAEAIABtDAAAAQARAOoMAAADACgALgAECn9TAAIMAAkJjyNXAgAaAwAMAAkJjyNXAgAaAwAAAA==.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8HAAISAAUJagdXDwDaAAVoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAOoMAAACABYAEgAFCWoHVw8A2gAFaAwAAAEAKABpDAAAAQAJAGsMAAABAAUAbAwAAAIAEQDqDAAAAgAWAC4ABAp/GAACEgAHCasfVQ4AVQIAEgAHCasfVQ4AVQIAAAA=.',
Mu='Mudpie:BAABLgAECn8aAAIaAAkJAx9oCgAhAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgAaAAkJAx9oCgAhAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIbAAQJVhveCgAzAQRoDAAAAQBBAGkMAAABAEQAawwAAAEAUwDqDAAAAgA+ABsABAlWG94KADMBBGgMAAABAEEAaQwAAAEARABrDAAAAQBTAOoMAAACAD4ALgAECn89AAMbAAkJ4yOKAgAnAwAbAAkJ4yOKAgAnAwACAAEJTBjK6wBHAAAAAA==.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAbAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAbAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAbAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJOAAKAFMjAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFAAKAIUlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMcAAkJJg4rIwCXAQloDAAABQAfAGkMAAAFABcAawwAAAUAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABQA0AG4MAAACAA8AbwwAAAEAKAAcAAkJJg4rIwCXAQloDAAAAwAfAGkMAAADABcAawwAAAMAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABAA0AG4MAAACAA8AbwwAAAEAKAARAAQJlQHMsABkAARoDAAAAgADAGkMAAACAAQAawwAAAIABADqDAAAAQADAAAA.Newtree:BAAALgAFFAcJBAABLgAFFAgJBAAHAAAAAA==.',
No='Notker:BAABLgAECn8uAAITAAkJ7CNnAgByAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwATAAkJ7CNnAgByAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1Rw5BwB9AgloDAAACABXAGkMAAAHAFoAawwAAAcAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABgBFAG4MAAADADMAbwwAAAEARwAKAAkJ1Rw5BwB9AgloDAAABgBXAGkMAAAGAFoAawwAAAYAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABQBFAG4MAAADADMAbwwAAAEARwABAAMJlAl4jwCAAANoDAAAAgAbAGkMAAABAAEAawwAAAEAKwANAAEJPQsKQwAzAAHqDAAAAQAcAAAA.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AXgTQD3AARoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAsABAn4BeBNAPcABGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBMpJwCZAANoDAAAAgAsAGkMAAACADYA6gwAAAEAMgANAAIJQBMpJwCZAAJoDAAAAQAsAGkMAAABADYAAQACCSANaDoAkgACaAwAAAEAKgBpDAAAAQAYAAoAAQmhE6wmADwAAeoMAAABADIAAAA=.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAgJBAAHAAAAAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAbAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8VAAIFAAgJfA9FJwBlAQhoDAAABQA9AGkMAAAEAB4AawwAAAMAIwBqDAAAAgAcAGwMAAACACYAbQwAAAEAEwDqDAAAAwArAG4MAAABADAABQAICXwPRScAZQEIaAwAAAUAPQBpDAAABAAeAGsMAAADACMAagwAAAIAHABsDAAAAgAmAG0MAAABABMA6gwAAAMAKwBuDAAAAQAwAAAA.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8UAAQJAAQJaCN5BwD+AARoDAAABwBdAGkMAAAGAFwAawwAAAIAWADqDAAABQBYAAkAAwlrHHkHAP4AA2gMAAACAEkAaQwAAAIAOABrDAAAAgBYAB0AAgmQIzRrANAAAmgMAAAFAF0A6gwAAAUAWAAeAAEJ8COQFABYAAFpDAAABABcAC4ABAp/OgAEHQAJCQUk1yMARQIAHQAHCaMe1yMARQIACQAFCUojWQ4A4wEAHgADCV0kXR0AswAAAAA=.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAYJGAAgAMMfAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgUJBQAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIhAAkJTQgWCgCGAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAhAAkJTQgWCgCGAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIWAAkJ2hefKQAjAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAWAAkJ2hefKQAjAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAAAA==.Skúnkstomper:BAAALgAECgEJAQAAAA==.Skûnkstomper:BAAALgADCgMJAQABLgAECgEJAQAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIYAAkJixMqMQB/AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAYAAkJixMqMQB/AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ8NEwAEAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAAMAAkJYQ8NEwAEAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8UAAIKAAQJhSVkBgCvAQRoDAAABwBiAGkMAAAGAFwAawwAAAIAXwDqDAAABQBhAAoABAmFJWQGAK8BBGgMAAAHAGIAaQwAAAYAXABrDAAAAgBfAOoMAAAFAGEALgAECn8yAAIKAAkJwyWvAgA8AwAKAAkJwyWvAgA8AwAAAA==.',
Te='Teafayd:BAABLgAECn8XAAMeAAYJhQtCGwDEAAZoDAAABAAcAGkMAAAGACQAawwAAAUAJABqDAAAAwAcAGwMAAACABMA6gwAAAMAGwAeAAYJCAtCGwDEAAZoDAAAAgAVAGkMAAAGACQAawwAAAQAJABqDAAAAwAcAGwMAAACABMA6gwAAAMAGwAJAAIJMAqlLwBPAAJoDAAAAgAcAGsMAAABABgAAAA=.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIUAAkJbh5ACwCBAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAUAAkJbh5ACwCBAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8RAAIDAAUJZBcFSgBAAQVoDAAABQBPAGkMAAAEAEEAawwAAAMAMgBqDAAAAgAYAOoMAAADACwAAwAFCWQXBUoAQAEFaAwAAAUATwBpDAAABABBAGsMAAADADIAagwAAAIAGADqDAAAAwAsAC4ABAp/TQACAwAJCc4i9gwA9QIAAwAJCc4i9gwA9QIAAAA=.',
To='Tomayter:BAABLgAECn8tAAITAAkJzh8IBwDwAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgATAAkJzh8IBwDwAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwALAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIOAAkJjSJbDAAEAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAOAAkJjSJbDAAEAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAAALgAECgcJCAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfho0AwBVAgloDAAABwBAAGkMAAAGAEgAawwAAAYAUABqDAAABAA6AGwMAAAGAEUAbQwAAAQAOADqDAAABwA7AG4MAAAEAEQAbwwAAAIARwAJAAkJfho0AwBVAgloDAAABABAAGkMAAAFAEgAawwAAAUAUABqDAAABAA6AGwMAAAFAEUAbQwAAAMAOADqDAAABQA7AG4MAAADAEQAbwwAAAIARwAdAAcJAAaTkQAQAQdoDAAAAwAUAGkMAAABAAYAawwAAAEAGgBsDAAAAQAKAG0MAAABABUA6gwAAAIADgBuDAAAAQAGAAAA.',
['Æs']='Æsc:BAABLgAECn8uAAIVAAkJUBeYEwC/AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAVAAkJUBeYEwC/AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAAAA==.',
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

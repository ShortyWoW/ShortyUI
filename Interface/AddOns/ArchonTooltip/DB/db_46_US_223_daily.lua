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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Druid-Feral','Druid-Guardian','Druid-Balance','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Druid-Restoration','Mage-Fire','Mage-Arcane','Monk-Mistweaver','Paladin-Protection','Warrior-Protection','Priest-Shadow',}
local provider = {region='US',realm='TolBarad',name='US',type='daily',zone=46,date='2026-05-22',data={Ae='Aelarion:BAAALgADCgIJAgAAAA==.',
Ai='Airfryer:BAABLgAECn8qAAMBAAgJbB0vAwA/AghoDAAABwBUAGkMAAAHAEoAawwAAAcAWgBqDAAABwBNAGwMAAAEAEsAbQwAAAIALwDqDAAABgA9AG4MAAACAFwAAQAICWwdLwMAPwIIaAwAAAYAVABpDAAABgBKAGsMAAAGAFoAagwAAAcATQBsDAAABABLAG0MAAACAC8A6gwAAAYAPQBuDAAAAgBcAAIAAwkKDdjGAJ4AA2gMAAABACMAaQwAAAEAIgBrDAAAAQAeAAAA.',
Aj='Ajorc:BAABLgAECn8aAAIDAAcJKhuaCgAdAgdoDAAAAwA9AGkMAAAEAEsAawwAAAQATgBqDAAABAA6AGwMAAADADkA6gwAAAQASgBuDAAABABFAAMABwkqG5oKAB0CB2gMAAADAD0AaQwAAAQASwBrDAAABABOAGoMAAAEADoAbAwAAAMAOQDqDAAABABKAG4MAAAEAEUAAAA=.Ajudando:BAACLgAFFH8aAAMEAAQJQRTbCAANAQRoDAAABwAlAGkMAAAHAFMAawwAAAQAEwDqDAAACABDAAQABAm2E9sIAA0BBGgMAAAGACUAaQwAAAYATQBrDAAABAATAOoMAAAHAEMAAwADCZMQ8AgA7gADaAwAAAEADgBpDAAAAQBTAOoMAAABABwALgAECn8+AAQDAAgJwyJ5BQBoAgADAAgJwyJ5BQBoAgAEAAgJoRfsFgBVAQAFAAIJtArObwBgAAAAAA==.',
Ar='Arc:BAAALgAECgIJBAAAAA==.Arkanjjo:BAAALgAECgEJAQAAAA==.Arkhin:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.Artesuda:BAAALgAECgIJAwAAAA==.',
Au='Aurelya:BAAALgAECgEJAwAAAA==.',
Aw='Awrelius:BAAALgADCgUJDAAAAA==.',
Az='Aznat:BAAALgAECgYJDgABLgAECggJJQAHAG4aAA==.',
Ba='Bachir:BAAALgAECgQJBAAAAA==.Balduco:BAAALgAECgQJDQABLgAECgYJDgAGAAAAAA==.Banguelä:BAAALgAECgYJDAAAAA==.Barkernth:BAABLgAECn8hAAIIAAgJwRXaFQC2AQhoDAAABQBFAGkMAAAFAEUAawwAAAUARgBqDAAABQA3AGwMAAAFADUAbQwAAAEADwDqDAAABgBVAG8MAAABABoACAAICcEV2hUAtgEIaAwAAAUARQBpDAAABQBFAGsMAAAFAEYAagwAAAUANwBsDAAABQA1AG0MAAABAA8A6gwAAAYAVQBvDAAAAQAaAAAA.Batatadoci:BAABLgAECn8VAAIJAAgJqghglAAmAQhoDAAAAwASAGkMAAADACsAawwAAAMAGwBqDAAAAwATAGwMAAADABIAbQwAAAEACADqDAAAAwAPAG4MAAACABcACQAICaoIYJQAJgEIaAwAAAMAEgBpDAAAAwArAGsMAAADABsAagwAAAMAEwBsDAAAAwASAG0MAAABAAgA6gwAAAMADwBuDAAAAgAXAAAA.',
Be='Bellatryx:BAAALgAECgEJAQAAAA==.Benx:BAAALgAECgEJAQAAAA==.',
Bi='Bianca:BAAALgAECgcJCAAAAA==.Bispopelado:BAAALgADCgcJBwAAAA==.',
Br='Brutaal:BAAALgADCgUJBQAAAA==.Brutállus:BAAALgADCgcJBwAAAA==.',
Ca='Calangosauro:BAAALgAFFAIJAgAAAA==.',
Ch='Chinchanchen:BAAALgAECgEJAQAAAA==.',
Co='Coqueiro:BAAALgADCgYJBgAAAA==.',
Cr='Cremador:BAAALgAECgYJDgAAAA==.',
Cy='Cyrannus:BAAALgAECgMJAwABLgAECggJKgABAGwdAA==.',
Da='Dabura:BAAALgADCgEJAwAAAA==.Dam:BAAALgADCgYJBgAAAA==.',
De='Deabu:BAAALgADCgQJBQAAAA==.Demethryus:BAAALgADCgYJBgAAAA==.Dennath:BAAALgAECgQJBQAAAA==.Ders:BAAALgADCgEJAQAAAA==.Devilton:BAABLgAECn8kAAIKAAcJQA5pcQAXAQdoDAAABwAgAGkMAAAGACsAawwAAAYAMABqDAAABQAqAGwMAAAEACYAbQwAAAEACQDqDAAABwAuAAoABwlADmlxABcBB2gMAAAHACAAaQwAAAYAKwBrDAAABgAwAGoMAAAFACoAbAwAAAQAJgBtDAAAAQAJAOoMAAAHAC4AAAA=.',
Di='Diericshaman:BAAALgADCgUJBQAAAA==.',
Dk='Dkagulino:BAAALgAECgIJAgABLgAFFAMJCAALAJQgAA==.',
Do='Domri:BAABLgAECn8bAAILAAgJaCAHHwBLAghoDAAABQBeAGkMAAAEAF8AawwAAAQAWwBqDAAABABaAGwMAAAEAFYAbQwAAAEAIADqDAAABABVAG4MAAABAF4ACwAICWggBx8ASwIIaAwAAAUAXgBpDAAABABfAGsMAAAEAFsAagwAAAQAWgBsDAAABABWAG0MAAABACAA6gwAAAQAVQBuDAAAAQBeAAAA.Donnus:BAABLgAECn81AAIMAAkJfyDcGACoAgloDAAACABeAGkMAAAHAFkAawwAAAgAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABwBYAG4MAAAFAEsAbwwAAAMATgAMAAkJfyDcGACoAgloDAAACABeAGkMAAAHAFkAawwAAAgAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABwBYAG4MAAAFAEsAbwwAAAMATgAAAA==.Doomhand:BAAALgAECgQJBAAAAA==.Dormin:BAAALgADCgUJBQAAAA==.Dorotty:BAAALgAECgQJBQAAAA==.',
Dr='Dragolancer:BAAALgAECgMJAwAAAA==.Drakonvolk:BAABLgAECn81AAMNAAkJKiHGDgDWAgloDAAACQBUAGkMAAAIAF8AawwAAAcAVgBqDAAABgBXAGwMAAAFAEoAbQwAAAIARADqDAAACQBVAG4MAAAGAF8AbwwAAAEAWQANAAkJQCDGDgDWAgloDAAACABOAGkMAAAHAF8AawwAAAYATgBqDAAABABEAGwMAAAEAEoAbQwAAAIARADqDAAABgBVAG4MAAADAFoAbwwAAAEAWQAOAAcJLyDRAwA9AgdoDAAAAQBUAGkMAAABAE4AawwAAAEAVgBqDAAAAgBXAGwMAAABAEQA6gwAAAMAUQBuDAAAAwBfAAAA.Drevanir:BAAALgADCggJCAAAAA==.Druidzuda:BAAALgADCgEJAQAAAA==.',
['Dé']='Dégell:BAAALgAECgUJCQAAAA==.',
Ed='Edy:BAAALgAECgkJDQAAAA==.',
Ei='Einheriar:BAAALgADCgUJBQAAAA==.',
El='Elanya:BAAALgAECgMJAwAAAA==.Elidaryel:BAABLgAECn80AAIKAAkJFSCiCwDOAgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUATADqDAAACABeAG4MAAAFAFMAbwwAAAIALQAKAAkJFSCiCwDOAgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUATADqDAAACABeAG4MAAAFAFMAbwwAAAIALQAAAA==.Elrondperedh:BAAALgAECgMJAwAAAA==.',
Er='Eryeth:BAAALgAECgYJBgABLgAECggJJQAHAG4aAA==.',
Fa='Faephine:BAAALgADCgkJEgAAAA==.',
Fe='Felithia:BAAALgADCgQJBAABLgAFFAUJEAAOAKoRAA==.',
Fr='Fred:BAAALgAECgUJCQAAAA==.Frozenrune:BAABLgAECn8lAAMOAAgJ1B/zBAD8AQhoDAAABgBhAGkMAAAFAFwAawwAAAUAXwBqDAAABQBbAGwMAAAFAF4AbQwAAAMAMgDqDAAABQBcAG4MAAADAC8ADgAGCeEk8wQA/AEGaAwAAAMAYQBpDAAAAgBcAGsMAAACAF8AagwAAAIAWwBsDAAAAgBeAOoMAAACAFwACAAICWAWyRIA4AEIaAwAAAMAKQBpDAAAAwBEAGsMAAADAEsAagwAAAMAQQBsDAAAAwAxAG0MAAADADIA6gwAAAMARABuDAAAAwAvAAAA.',
Fu='Fuleco:BAABLgAECn8vAAMPAAgJ4CPaCAA1AghoDAAACABjAGkMAAAIAGIAawwAAAcAWQBqDAAABgBjAGwMAAAFAFgAbQwAAAEAXwDqDAAACQBhAG4MAAADAEoADwAGCaUi2ggANQIGaAwAAAEAYABpDAAAAQBXAGsMAAAGAFkAbAwAAAQAWADqDAAAAgBfAG4MAAABAEoAEAAICXQhfBUAHQIIaAwAAAcAYwBpDAAABwBiAGsMAAABAFAAagwAAAYAYwBsDAAAAQA5AG0MAAABAF8A6gwAAAcAYQBuDAAAAgBHAAAA.',
Ga='Gablle:BAACLgAFFH8FAAIRAAMJBhuhEgACAQNoDAAAAgBNAGkMAAABAFIA6gwAAAIALgARAAMJBhuhEgACAQNoDAAAAgBNAGkMAAABAFIA6gwAAAIALgAuAAQKfzYAAxEACQneDQ0gAIIBABEACQneDQ0gAIIBABIACQkbBWAtADABAAAA.Gabrielstone:BAAALgAECgQJBgAAAA==.Gabriwel:BAAALgAECgQJCQAAAA==.',
Gl='Glimmuln:BAABLgAECn8kAAMTAAYJjQnpagDcAAZoDAAABwAYAGkMAAAGACMAawwAAAYAFwBqDAAABAAMAGwMAAAFAAkA6gwAAAgAKgATAAYJjQnpagDcAAZoDAAABgAYAGkMAAAGACMAawwAAAYAFwBqDAAABAAMAGwMAAAEAAkA6gwAAAgAKgAUAAIJywTajwAoAAJoDAAAAQATAGwMAAABAAQAAAA=.Glimwr:BAAALgAECgQJDQAAAA==.',
Go='Gordorc:BAAALgAECgEJAQAAAA==.Gorvok:BAAALgADCgMJAwAAAA==.',
Gr='Grongos:BAAALgAECgEJAgABLgAECgYJDgAGAAAAAA==.Grumps:BAAALgADCgcJBwAAAA==.',
Gu='Gudeath:BAAALgAECgcJBwAAAA==.Gueber:BAAALgAECgYJDAAAAA==.Gueberlin:BAAALgADCgQJBAAAAA==.Guebernir:BAAALgADCgYJDAAAAA==.',
Ha='Hakoda:BAAALgAECgEJAQAAAA==.Harggoth:BAAALgAECggJEAAAAA==.',
He='Hergor:BAABLgAECn8qAAQUAAkJAxZpJwCBAQloDAAABQBAAGkMAAAEADwAawwAAAUAKQBqDAAABgBAAGwMAAAGACsAbQwAAAUAIwDqDAAABwBIAG4MAAADACQAbwwAAAEAXwAUAAgJ2hNpJwCBAQhoDAAABABAAGkMAAAEADwAawwAAAUAKQBqDAAABABAAGwMAAAFACsAbQwAAAQAIwDqDAAAAwBIAG4MAAADACQAEwAFCaQJf3IAxQAFaAwAAAEACABqDAAAAQAIAG0MAAABADMA6gwAAAQALABvDAAAAQALABUAAgm9CB8sADUAAmoMAAABAAAAbAwAAAEAFgAAAA==.Hexdrinker:BAAALgAECgEJAQAAAA==.',
Ir='Irmasuelen:BAAALgAECgYJCwAAAA==.',
Je='Jeh:BAAALgAECgMJAwAAAA==.Jeje:BAAALgAECgQJBwAAAA==.',
Jo='Jorgebenjorg:BAAALgAECgEJAQAAAA==.',
Ka='Kalanguin:BAAALgADCgEJAQAAAA==.Kate:BAABLgAECn8jAAIWAAkJZxSQKwDXAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAWAAkJZxSQKwDXAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAAAA==.',
Kh='Khylin:BAAALgAECgUJCAAAAA==.',
Kl='Klimorin:BAAALgADCgMJBAAAAA==.',
Kr='Krzero:BAAALgADCgIJAgABLgAECgkJNQANACohAA==.',
Lc='Lcabronehboy:BAABLgAECn8YAAIMAAcJNw97fgBcAQdoDAAAAwArAGkMAAACACsAawwAAAIAFwBqDAAABQAnAGwMAAACABUA6gwAAAgAMABuDAAAAgA1AAwABwk3D3t+AFwBB2gMAAADACsAaQwAAAIAKwBrDAAAAgAXAGoMAAAFACcAbAwAAAIAFQDqDAAACAAwAG4MAAACADUAAAA=.',
Le='Lexan:BAABLgAECn8fAAMUAAcJHRBzOQAdAQdoDAAABgAkAGkMAAAFAC4AawwAAAUAKQBqDAAABAAsAGwMAAAEACsAbQwAAAEAGADqDAAABgA3ABQABwkdEHM5AB0BB2gMAAAFACQAaQwAAAQALgBrDAAABAApAGoMAAADACwAbAwAAAMAKwBtDAAAAQAYAOoMAAAGADcAFQAFCTwI5B4ArwAFaAwAAAEAFABpDAAAAQAYAGsMAAABABkAagwAAAEACABsDAAAAQANAAAA.',
Li='Linlygan:BAAALgADCgQJBAAAAA==.Lissão:BAABLgAECn8jAAMIAAgJjh0hCwAsAghoDAAABgBHAGkMAAAGAFAAawwAAAYAUABqDAAABABTAGwMAAAEADoAbQwAAAIASQDqDAAABgBUAG4MAAABAFAACAAICY4dIQsALAIIaAwAAAYARwBpDAAABgBQAGsMAAAGAFAAagwAAAQAUwBsDAAABAA6AG0MAAACAEkA6gwAAAUAVABuDAAAAQBQAA0AAQnxAJM8ARkAAeoMAAABAAIAAAA=.',
Lu='Lucoa:BAAALgADCgUJBQABLgAECggJJQACAJYcAA==.Luhanar:BAAALgAECgYJCwABLgAECgkJNQANACohAA==.',
Ly='Lylithe:BAAALgAECgEJAQAAAA==.',
Ma='Madow:BAABLgAECn8lAAICAAgJlhyOIwA2AghoDAAABgA9AGkMAAAGAFAAawwAAAYATQBqDAAABABZAGwMAAAEAFAAbQwAAAIALgDqDAAACABcAG4MAAABAEgAAgAICZYcjiMANgIIaAwAAAYAPQBpDAAABgBQAGsMAAAGAE0AagwAAAQAWQBsDAAABABQAG0MAAACAC4A6gwAAAgAXABuDAAAAQBIAAAA.Magmafire:BAABLgAECn84AAMXAAkJUyKVAADlAgloDAAABQBjAGkMAAAEAGAAawwAAAMAWwBqDAAACQBfAGwMAAAIAEwAbQwAAAgAWADqDAAABwBbAG4MAAAHAFEAbwwAAAUATgAXAAkJ+yCVAADlAgloDAAAAQBKAGkMAAACAGAAawwAAAIAWwBqDAAABwBfAGwMAAAFAEkAbQwAAAYAWADqDAAABQBbAG4MAAAHAFEAbwwAAAUATgAYAAcJ8x/XAgBYAgdoDAAABABjAGkMAAACAFcAawwAAAEAVQBqDAAAAgAbAGwMAAADAEwAbQwAAAIANADqDAAAAgBYAAAA.Magronego:BAAALgAECgQJBgAAAA==.Malakain:BAAALgAECgQJBQAAAA==.Mazakita:BAAALgADCgMJAwAAAA==.',
Mi='Mitsy:BAABLgAECn8ZAAMZAAYJMB4nJQCqAQZoDAAABABSAGkMAAAFAFYAawwAAAUAOgBqDAAAAwBNAGwMAAADAEMA6gwAAAUAWgAZAAYJMB4nJQCqAQZoDAAAAwBSAGkMAAADAFYAawwAAAMAOgBqDAAAAQBNAGwMAAABAEMA6gwAAAMAWgARAAYJDAt6PwAcAQZoDAAAAQANAGkMAAACACkAawwAAAIAJABqDAAAAgAlAGwMAAACABgA6gwAAAIAGgAAAA==.',
Mo='Morevil:BAAALgADCgQJBAAAAA==.Morterubra:BAABLgAECn8oAAMNAAgJiRydQgDYAQhoDAAACwBbAGkMAAAFAEYAawwAAAcAVQBqDAAAAwANAGwMAAACACMAbQwAAAIANwDqDAAABwBQAG4MAAADAFsADQAICYkcnUIA2AEIaAwAAAkAWwBpDAAAAwBGAGsMAAAFAFUAagwAAAEADQBsDAAAAQAjAG0MAAACADcA6gwAAAcAUABuDAAAAwBbAAgABQmgC080AJUABWgMAAACADIAaQwAAAIAHgBrDAAAAgAUAGoMAAACAAwAbAwAAAEAEAABLgAECggJKgABAGwdAA==.Mosa:BAAALgAECgUJEQAAAA==.',
Mu='Mulkzagoon:BAAALgADCgQJBgAAAA==.Murodan:BAAALgAECgQJBAAAAA==.Musphelheim:BAAALgADCgcJBwAAAA==.',
['Mö']='Mörrigan:BAAALgAECgQJBAAAAA==.',
Na='Nadruk:BAABLgAECn8jAAITAAcJuh7wHQAsAgdoDAAABQBaAGkMAAAFAEEAawwAAAUAVABqDAAABgBQAGwMAAAFAE4AbQwAAAIAOgDqDAAABwBbABMABwm6HvAdACwCB2gMAAAFAFoAaQwAAAUAQQBrDAAABQBUAGoMAAAGAFAAbAwAAAUATgBtDAAAAgA6AOoMAAAHAFsAAAA=.Natalia:BAAALgAECgkJDQAAAA==.',
Ne='Neskau:BAAALgAECgEJAQAAAA==.Nevinha:BAAALgADCgEJAQAAAA==.Neymardacaça:BAAALgADCgIJAgAAAA==.',
Ni='Nidaime:BAABLgAECn8aAAIMAAgJRhNQ0gBJAQhoDAAABAApAGkMAAAEAEQAawwAAAUAQABqDAAABABFAGwMAAABACkAbQwAAAEAFQDqDAAABQA4AG4MAAACADMADAAICUYTUNIASQEIaAwAAAQAKQBpDAAABABEAGsMAAAFAEAAagwAAAQARQBsDAAAAQApAG0MAAABABUA6gwAAAUAOABuDAAAAgAzAAAA.',
No='Noach:BAAALgADCgMJAwABLgAECgYJDgAGAAAAAA==.Nocro:BAAALgADCgEJAQAAAA==.',
Oa='Oathkeeper:BAAALgADCgYJCwAAAA==.',
Od='Odahviing:BAAALgAECgYJBgABLgAECggJKgABAGwdAA==.',
Oi='Oicasada:BAAALgADCgMJBAAAAA==.',
Op='Optix:BAAALgAECgMJAwAAAA==.',
Ox='Oxylus:BAABLgAECn8cAAIWAAgJqxHyMwCnAQhoDAAABQBDAGkMAAAFAEIAawwAAAUAOwBqDAAABAAkAGwMAAAEACYAbQwAAAEAHADqDAAAAwAtAG4MAAABABMAFgAICasR8jMApwEIaAwAAAUAQwBpDAAABQBCAGsMAAAFADsAagwAAAQAJABsDAAABAAmAG0MAAABABwA6gwAAAMALQBuDAAAAQATAAAA.',
Pa='Padremario:BAAALgADCgEJAgAAAA==.Palahorda:BAAALgADCgUJBQAAAA==.Panchorf:BAABLgAECn8kAAIaAAcJOAZrJgCwAAdoDAAABwAWAGkMAAAGABoAawwAAAYADQBqDAAABQAGAGwMAAAEAAoAbQwAAAEABADqDAAABwASABoABwk4BmsmALAAB2gMAAAHABYAaQwAAAYAGgBrDAAABgANAGoMAAAFAAYAbAwAAAQACgBtDAAAAQAEAOoMAAAHABIAAAA=.',
Pe='Pescador:BAAALgAECgcJEAAAAA==.Pevê:BAAALgAECgQJAwAAAA==.',
Pr='Prihunter:BAABLgAECn8kAAILAAcJyAuEcQArAQdoDAAABwAcAGkMAAAGACIAawwAAAYAJwBqDAAABQAYAGwMAAAEABcAbQwAAAEAEQDqDAAABwAkAAsABwnIC4RxACsBB2gMAAAHABwAaQwAAAYAIgBrDAAABgAnAGoMAAAFABgAbAwAAAQAFwBtDAAAAQARAOoMAAAHACQAAAA=.Primanocte:BAAALgADCgYJBgAAAA==.',
Ra='Rafikii:BAACLgAFFH8GAAIEAAMJRwJIIwA3AANoDAAAAwAGAGkMAAABAAAA6gwAAAIACQAEAAMJRwJIIwA3AANoDAAAAwAGAGkMAAABAAAA6gwAAAIACQAuAAQKfx0AAgQACAndApAgAJoAAAQACAndApAgAJoAAAAA.Randel:BAAALgADCgQJBAAAAA==.Raswell:BAAALgADCgEJAQAAAA==.',
Rh='Rhadamants:BAAALgAECgEJAQAAAA==.',
Ri='Richard:BAAALgADCggJBQAAAA==.Ritaa:BAABLgAECn8cAAIJAAcJSxuaRwAMAgdoDAAABABFAGkMAAAEAEAAawwAAAYAQgBqDAAABAAzAGwMAAAEAD4A6gwAAAMASQBuDAAAAwBSAAkABwlLG5pHAAwCB2gMAAAEAEUAaQwAAAQAQABrDAAABgBCAGoMAAAEADMAbAwAAAQAPgDqDAAAAwBJAG4MAAADAFIAAAA=.Rizúl:BAAALgAECgQJBAAAAA==.',
Rl='Rldsbvb:BAABLgAECn8lAAIHAAgJbhqnEgD2AQhoDAAABgBEAGkMAAAHAFcAawwAAAYAQwBqDAAABAA2AGwMAAAEAFIAbQwAAAIATQDqDAAABwA7AG4MAAABAB8ABwAICW4apxIA9gEIaAwAAAYARABpDAAABwBXAGsMAAAGAEMAagwAAAQANgBsDAAABABSAG0MAAACAE0A6gwAAAcAOwBuDAAAAQAfAAAA.',
Ro='Rotgaz:BAAALgAECgEJAQAAAA==.',
Sa='Sabedetudo:BAAALgAECgEJAQAAAA==.Sadomie:BAABLgAECn8pAAILAAkJGRZmKwADAgloDAAABwBHAGkMAAAGADcAawwAAAQAOQBqDAAABQA/AGwMAAAFAFIAbQwAAAQAJwDqDAAABgBIAG4MAAADADYAbwwAAAEAEgALAAkJGRZmKwADAgloDAAABwBHAGkMAAAGADcAawwAAAQAOQBqDAAABQA/AGwMAAAFAFIAbQwAAAQAJwDqDAAABgBIAG4MAAADADYAbwwAAAEAEgAAAA==.',
Sh='Shagratth:BAAALgADCgcJBwAAAA==.Shindi:BAAALgADCgQJBQAAAA==.Shreka:BAAALgAECgMJAwAAAA==.',
Si='Silaleas:BAAALgAECgcJDQAAAA==.',
Sk='Skiff:BAAALgAECgEJAgAAAA==.',
Sn='Snoxxie:BAAALgAECgEJAQAAAA==.',
So='Solana:BAAALgADCgYJBgAAAA==.',
Sw='Sweej:BAAALgAFFAIJAgAAAA==.',
Ta='Tacalypau:BAAALgADCgYJBgAAAA==.Tahir:BAAALgAECgYJCAAAAA==.Taima:BAAALgADCgkJCwAAAA==.',
Th='Thebrunovest:BAABLgAECn8ZAAINAAYJEhBTpgD6AAZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwANAAYJEhBTpgD6AAZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwAAAA==.Thortrevan:BAABLgAECn8sAAILAAgJ0h2ZEAC1AghoDAAACQBgAGkMAAAIAFYAawwAAAoAWABqDAAABAAxAGwMAAAEAEkAbQwAAAEAQgDqDAAABgBPAG4MAAACACsACwAICdIdmRAAtQIIaAwAAAkAYABpDAAACABWAGsMAAAKAFgAagwAAAQAMQBsDAAABABJAG0MAAABAEIA6gwAAAYATwBuDAAAAgArAAAA.Thrain:BAABLgAECn8fAAIbAAcJexkAFwBgAQdoDAAABgBOAGkMAAAFAFIAawwAAAUAPgBqDAAABAAmAGwMAAAEACoAbQwAAAEAOwDqDAAABgBCABsABwl7GQAXAGABB2gMAAAGAE4AaQwAAAUAUgBrDAAABQA+AGoMAAAEACYAbAwAAAQAKgBtDAAAAQA7AOoMAAAGAEIAAAA=.',
Ti='Tiffah:BAABLgAECn8lAAIMAAkJpiBFEQDZAgloDAAABQBcAGkMAAAFAFUAawwAAAUAVQBqDAAABABfAGwMAAAFAEcAbQwAAAIASQDqDAAABgBaAG4MAAAEAFUAbwwAAAEAVgAMAAkJpiBFEQDZAgloDAAABQBcAGkMAAAFAFUAawwAAAUAVQBqDAAABABfAGwMAAAFAEcAbQwAAAIASQDqDAAABgBaAG4MAAAEAFUAbwwAAAEAVgAAAA==.Tinth:BAAALgADCgEJAQAAAA==.Tixi:BAAALgAECgUJBQAAAA==.',
To='Toranaar:BAAALgAECgUJCAABLgAECgkJDQAGAAAAAA==.Totahealer:BAAALgAECgMJBQABLgAECgYJDgAGAAAAAA==.',
Tr='Traix:BAAALgAECgYJEgAAAA==.Trememoita:BAAALgAECgMJAwAAAA==.',
Va='Vanthyn:BAAALgAECgEJAQAAAA==.',
Ve='Veccia:BAAALgADCgIJAgAAAA==.Veltharys:BAAALgADCgIJAgAAAA==.',
Vh='Vherk:BAAALgADCgQJBAAAAA==.',
Vi='Visemir:BAAALgADCgQJBAAAAA==.',
We='Wenasnoches:BAAALgADCggJDAAAAA==.',
Wh='Whitetusk:BAAALgADCgcJBwAAAA==.',
Wo='Wonderkast:BAAALgAECgEJAQABLgAFFAgJIAAcABQfAA==.',
Wu='Wurdulak:BAAALgADCgEJAgAAAA==.',
Xa='Xamelo:BAABLgAECn8kAAITAAcJsSPjDADGAgdoDAAABwBhAGkMAAAGAGAAawwAAAYAYQBqDAAABQBcAGwMAAAEAGAAbQwAAAEAQgDqDAAABwBcABMABwmxI+MMAMYCB2gMAAAHAGEAaQwAAAYAYABrDAAABgBhAGoMAAAFAFwAbAwAAAQAYABtDAAAAQBCAOoMAAAHAFwAAAA=.',
Xi='Xicobruxo:BAAALgAECgIJAgAAAA==.',
Yo='Yona:BAAALgAECgUJEAABLgAECgcJGgAJANIWAA==.',
Za='Zadockn:BAAALgAECgQJBQAAAA==.',
Zu='Zughy:BAAALgAECgYJCQABLgAFFAgJIAAcABQfAA==.',
['Zé']='Zédaplanta:BAABLgAECn8fAAIWAAYJ+hP0QABoAQZoDAAACABVAGkMAAAHAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAUAOgAWAAYJ+hP0QABoAQZoDAAACABVAGkMAAAHAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAUAOgAAAA==.',
['Är']='Ärkin:BAAALgAECgQJBAABLgAECggJKgABAGwdAA==.',
['Ðe']='Ðeath:BAAALgAECgYJEAABLgAECggJLwAPAOAjAA==.',
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

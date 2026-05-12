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

local lookup = {'Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Druid-Guardian','Paladin-Retribution','Mage-Frost','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-05-12',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgADCgMJAwABLgAECgEJAwABAAAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAABLgAECn8wAAICAAkJoRmSCQBhAgloDAAABwBKAGkMAAAGAEcAawwAAAYAUABqDAAABgAsAGwMAAAGADYAbQwAAAQAWQDqDAAABQAwAG4MAAAEADcAbwwAAAQAMQACAAkJoRmSCQBhAgloDAAABwBKAGkMAAAGAEcAawwAAAYAUABqDAAABgAsAGwMAAAGADYAbQwAAAQAWQDqDAAABQAwAG4MAAAEADcAbwwAAAQAMQAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8SAAIDAAgJrxmgVgCeAQhoDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAAwAICa8ZoFYAngEIaAwAAAMATABpDAAAAwBUAGsMAAADAEwAagwAAAEAKwBsDAAAAwA3AG0MAAACADcA6gwAAAEALwBuDAAAAgBBAAAA.',
Ar='Aramis:BAAALgAECgUJCQABLgAECgkJGwAEAN4fAA==.Arathrok:BAABLgAECn8bAAIEAAkJ3h/SPwA5AgloDAAABQBfAGkMAAAEAFoAawwAAAQATQBqDAAAAwBdAGwMAAADAFoAbQwAAAEAUQDqDAAABQBNAG4MAAABAEMAbwwAAAEARwAEAAkJ3h/SPwA5AgloDAAABQBfAGkMAAAEAFoAawwAAAQATQBqDAAAAwBdAGwMAAADAFoAbQwAAAEAUQDqDAAABQBNAG4MAAABAEMAbwwAAAEARwAAAA==.',
As='Asha:BAACLgAFFH8IAAIFAAQJAhUbCQA6AQRoDAAAAgA4AGkMAAACADEAawwAAAIASADqDAAAAgAkAAUABAkCFRsJADoBBGgMAAACADgAaQwAAAIAMQBrDAAAAgBIAOoMAAACACQALgAECn8UAAQGAAcJghd6IQBXAQAGAAQJ0Bx6IQBXAQAFAAcJ4B5nHgBEAQAHAAQJDA55NQDRAAAAAA==.Asmoday:BAABLgAECn8eAAIEAAgJTB88GABSAghoDAAABQBUAGkMAAAFAF8AawwAAAUAUgBqDAAAAgA5AGwMAAAEAFUAbQwAAAIARgDqDAAABQBYAG4MAAACADUABAAICUwfPBgAUgIIaAwAAAUAVABpDAAABQBfAGsMAAAFAFIAagwAAAIAOQBsDAAABABVAG0MAAACAEYA6gwAAAUAWABuDAAAAgA1AAAA.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECggJHgAEAEwfAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7QoRDQBhAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe0KEQ0AYQEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.',
Ba='Bat:BAABLgAECn8ZAAIIAAgJAyUWAQADAwhoDAAABABhAGkMAAAEAF4AawwAAAMAYgBqDAAAAwBfAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAABAFYACAAICQMlFgEAAwMIaAwAAAQAYQBpDAAABABeAGsMAAADAGIAagwAAAMAXwBsDAAABABeAG0MAAADAGEA6gwAAAMAXgBuDAAAAQBWAAAA.',
Be='Benedictine:BAAALgAECgEJBAAAAA==.',
Bi='Bigcleavage:BAABLgAECn8aAAIJAAgJShrHDwAMAghoDAAABQA+AGkMAAAEAEsAawwAAAQAUgBqDAAAAwBDAGwMAAADAFAAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkACQAICUoaxw8ADAIIaAwAAAUAPgBpDAAABABLAGsMAAAEAFIAagwAAAMAQwBsDAAAAwBQAG0MAAACACgA6gwAAAMAOABuDAAAAgBJAAAA.',
Bl='Blueberrypie:BAAALgAECgQJBwABLgAECggJFQAKAKoeAA==.',
Bo='Boomster:BAAALgAFFAgJAwAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8aAAILAAkJnyEDKACFAgloDAAABQBjAGkMAAAEAFUAawwAAAQAWwBqDAAAAwBiAGwMAAADAFkAbQwAAAEAWgDqDAAABABiAG4MAAABAD4AbwwAAAEARwALAAkJnyEDKACFAgloDAAABQBjAGkMAAAEAFUAawwAAAQAWwBqDAAAAwBiAGwMAAADAFkAbQwAAAEAWgDqDAAABABiAG4MAAABAD4AbwwAAAEARwAAAA==.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAECgMJBQABLgAECggJFQAKAKoeAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cy='Cylla:BAACLgAFFH8IAAIMAAMJgQnqVwDlAANoDAAAAwAeAGkMAAADABIA6gwAAAIAFwAMAAMJgQnqVwDlAANoDAAAAwAeAGkMAAADABIA6gwAAAIAFwAuAAQKfzAAAgwACAmJHWohADgCAAwACAmJHWohADgCAAAA.',
Di='Dilfdormu:BAAALgAECgcJDwAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAABLgAECn8sAAINAAkJ/BxLEAC1AgloDAAABwBSAGkMAAAGAFYAawwAAAYARgBqDAAABQBbAGwMAAAFAF8AbQwAAAQARgDqDAAABgBSAG4MAAAEADwAbwwAAAEAHAANAAkJ/BxLEAC1AgloDAAABwBSAGkMAAAGAFYAawwAAAYARgBqDAAABQBbAGwMAAAFAF8AbQwAAAQARgDqDAAABgBSAG4MAAAEADwAbwwAAAEAHAAAAA==.',
Dr='Dratak:BAACLgAFFH8hAAIJAAcJtiKAAABuAgdoDAAABwBjAGkMAAAGAF4AawwAAAYAWQBqDAAABABfAGwMAAACAGEAbQwAAAEANwDqDAAABwBhAAkABwm2IoAAAG4CB2gMAAAHAGMAaQwAAAYAXgBrDAAABgBZAGoMAAAEAF8AbAwAAAIAYQBtDAAAAQA3AOoMAAAHAGEALgAECn9TAAIJAAkJmSVdAADTAwAJAAkJmSVdAADTAwAAAA==.Dread:BAABLgAECn8bAAIFAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABQAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJCgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJAQABLgAFFAcJIQAJALYiAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAgAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAAALgAECgUJEQAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJCQAJAB8kAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8jAAIOAAcJZCJWAQC6AgdoDAAABwBfAGkMAAAGAF4AawwAAAQAYQBqDAAABQBcAGwMAAAEAGAAbQwAAAIAMgDqDAAABwBZAA4ABwlkIlYBALoCB2gMAAAHAF8AaQwAAAYAXgBrDAAABABhAGoMAAAFAFwAbAwAAAQAYABtDAAAAgAyAOoMAAAHAFkALgAECn8zAAQOAAkJbCWmAwAuAwAOAAgJQyWmAwAuAwAPAAcJEhFALwCGAQAQAAIJ3CG6RgDJAAAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAUJFQARAKEaAA==.',
Gu='Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJCwAAAA==.Haradali:BAAALgAECgIJAgAAAA==.',
Ho='Holydiah:BAAALgAECgYJDQAAAA==.Holypriest:BAAALgAECgcJCQAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAABLgAECn8fAAMOAAkJfBuwEgAdAgloDAAABQBcAGkMAAAFAFAAawwAAAUASgBqDAAABABVAGwMAAADAEgAbQwAAAEAXwDqDAAABgBRAG4MAAABABcAbwwAAAEAGwAOAAgJwh2wEgAdAghoDAAABQBcAGkMAAAEAFAAawwAAAQASgBqDAAAAwBVAGwMAAADAEgAbQwAAAEAXwDqDAAABgBRAG8MAAABABsADwAECY4J5zoAoAAEaQwAAAEAEQBrDAAAAQAZAGoMAAABAB4AbgwAAAEAFwAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECggJHgAEAEwfAA==.Kayla:BAAALgAECgEJAgAAAA==.',
Ki='Kiran:BAAALgAECgEJAwAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgUJEQABAAAAAA==.Kroth:BAABLgAECn84AAINAAkJ7xA4IADaAQloDAAACAA5AGkMAAAHACgAawwAAAcAPgBqDAAABwAvAGwMAAAHADgAbQwAAAUAHADqDAAABwA8AG4MAAAFABIAbwwAAAMAEQANAAkJ7xA4IADaAQloDAAACAA5AGkMAAAHACgAawwAAAcAPgBqDAAABwAvAGwMAAAHADgAbQwAAAUAHADqDAAABwA8AG4MAAAFABIAbwwAAAMAEQAAAA==.',
Ku='Kubfury:BAAALgAECgUJBgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8cAAISAAgJ9R8nEgBVAghoDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAQArAGwMAAADAEcAbQwAAAIAXwDqDAAABQBSAG4MAAACAD0AEgAICfUfJxIAVQIIaAwAAAUAVQBpDAAABQBTAGsMAAAFAFwAagwAAAEAKwBsDAAAAwBHAG0MAAACAF8A6gwAAAUAUgBuDAAAAgA9AAAA.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAgJAwABAAAAAA==.',
Lu='Lunaci:BAABLgAECn8bAAMTAAgJQxR1FQCuAQhoDAAABABAAGkMAAAEADgAawwAAAQASABqDAAAAwA8AGwMAAAEACwAbQwAAAIAKQDqDAAABAApAG4MAAACACoAEwAICU4TdRUArgEIaAwAAAIAQABpDAAAAgA4AGsMAAACAEgAagwAAAEAPABsDAAAAgAsAG0MAAACACkA6gwAAAEAGABuDAAAAgAqABQABgmZDqgKAAUBBmgMAAACACMAaQwAAAIAJQBrDAAAAgA1AGoMAAACAB4AbAwAAAIAEwDqDAAAAwApAAAA.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8fAAIJAAgJnhkeCAAHAghoDAAABQBYAGkMAAAFAEMAawwAAAUAUwBqDAAAAwBLAGwMAAAEAFAAbQwAAAIALwDqDAAABQBCAG4MAAACABkACQAICZ4ZHggABwIIaAwAAAUAWABpDAAABQBDAGsMAAAFAFMAagwAAAMASwBsDAAABABQAG0MAAACAC8A6gwAAAUAQgBuDAAAAgAZAAAA.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8fAAIMAAgJphj+LAAAAghoDAAABQBJAGkMAAAFAEgAawwAAAUASABqDAAAAwBGAGwMAAAEAEQAbQwAAAIAKgDqDAAABQBEAG4MAAACACwADAAICaYY/iwAAAIIaAwAAAUASQBpDAAABQBIAGsMAAAFAEgAagwAAAMARgBsDAAABABEAG0MAAACACoA6gwAAAUARABuDAAAAgAsAAAA.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgQJBAAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJCQAJAB8kAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQABLgAFFAgJAwABAAAAAA==.Misfortune:BAAALgAECgMJBAABLgAECgkJGgALAJ8hAA==.Mitsy:BAABLgAECn8UAAIQAAcJFg8ZHgBhAQdoDAAABAAqAGkMAAADACcAawwAAAIAIgBqDAAAAgAfAGwMAAADABoA6gwAAAQAKABuDAAAAgAvABAABwkWDxkeAGEBB2gMAAAEACoAaQwAAAMAJwBrDAAAAgAiAGoMAAACAB8AbAwAAAMAGgDqDAAABAAoAG4MAAACAC8AAAA=.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACwAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAVAAIJcAdZVQBlAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAAALgAECgcJBwAAAA==.Moons:BAACLgAFFH8QAAIWAAUJbhVEAQBmAQVoDAAABABVAGkMAAAFADAAawwAAAMALgBqDAAAAQAgAOoMAAADACgAFgAFCW4VRAEAZgEFaAwAAAQAVQBpDAAABQAwAGsMAAADAC4AagwAAAEAIADqDAAAAwAoAC4ABAp/PwACFgAJCcIhkwEACQMAFgAJCcIhkwEACQMAAAA=.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAABLgAECn8VAAIOAAcJXB9VDgBVAgdoDAAABABfAGkMAAADAE8AawwAAAMASwBqDAAAAwBWAGwMAAACAFsA6gwAAAQAWgBuDAAAAgArAA4ABwlcH1UOAFUCB2gMAAAEAF8AaQwAAAMATwBrDAAAAwBLAGoMAAADAFYAbAwAAAIAWwDqDAAABABaAG4MAAACACsAAAA=.',
Mu='Mudpie:BAABLgAECn8VAAIKAAgJqh59CQAJAghoDAAAAwBRAGkMAAAEAFQAawwAAAQAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEACgAICaoefQkACQIIaAwAAAMAUQBpDAAABABUAGsMAAAEAF0AagwAAAIARgBsDAAAAwBLAG0MAAABAEwA6gwAAAMARwBuDAAAAQBBAAAA.Munco:BAABLgAECn8tAAIXAAgJFyKyBgD7AghoDAAABgBgAGkMAAAHAGEAawwAAAcAXQBqDAAABQBhAGwMAAAGAFsAbQwAAAMAQQDqDAAABwBaAG4MAAAEAE0AFwAICRcisgYA+wIIaAwAAAYAYABpDAAABwBhAGsMAAAHAF0AagwAAAUAYQBsDAAABgBbAG0MAAADAEEA6gwAAAcAWgBuDAAABABNAAAA.Muncola:BAAALgAECgEJAQABLgAECggJLQAXABciAA==.Muncoli:BAAALgAECgMJBAABLgAECggJLQAXABciAA==.Muncolito:BAAALgADCgEJAQABLgAECggJLQAXABciAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJCQAJAB8kAA==.',
Ne='Nellie:BAABLgAECn8XAAMYAAgJdQokIgA8AQhoDAAABAAfAGkMAAAEABcAawwAAAQAKABqDAAAAgAdAGwMAAADAB0AbQwAAAEAJADqDAAABAAUAG4MAAABAAUAGAAICXUKJCIAPAEIaAwAAAIAHwBpDAAAAgAXAGsMAAACACgAagwAAAIAHQBsDAAAAwAdAG0MAAABACQA6gwAAAMAFABuDAAAAQAFAA0ABAmVAcywAGQABGgMAAACAAMAaQwAAAIABABrDAAAAgAEAOoMAAABAAMAAAA=.Newtree:BAAALgAFFAQJAgABLgAFFAgJAwABAAAAAA==.',
No='Notker:BAABLgAECn8fAAIPAAgJRCR6AgAsAwhoDAAABQBiAGkMAAAFAF0AawwAAAUAYQBqDAAAAwBeAGwMAAAEAGAAbQwAAAIAWADqDAAABQBhAG4MAAACAEsADwAICUQkegIALAMIaAwAAAUAYgBpDAAABQBdAGsMAAAFAGEAagwAAAMAXgBsDAAABABgAG0MAAACAFgA6gwAAAUAYQBuDAAAAgBLAAAA.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECggJHgAEAEwfAA==.',
Or='Orcwarr:BAABLgAECn8gAAQJAAgJ3hemCQDnAQhoDAAABgBLAGkMAAAFAEcAawwAAAUAQwBqDAAABABPAGwMAAAEACUAbQwAAAEAQgDqDAAABQBFAG4MAAACACcACQAICd4XpgkA5wEIaAwAAAQASwBpDAAABABHAGsMAAAEAEMAagwAAAQATwBsDAAABAAlAG0MAAABAEIA6gwAAAQARQBuDAAAAgAnAAIAAwmUCXiPAIAAA2gMAAACABsAaQwAAAEAAQBrDAAAAQArABkAAQk9CwpDADMAAeoMAAABABwAAAA=.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AXPKgAbAQRoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAsABAn4Bc8qABsBBGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAECgEJAQABLgAECggJFQAKAKoeAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pipsi:BAAALgAECgEJAQABLgAECggJLQAXABciAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJBQAEACkWAA==.',
Pr='Pryor:BAAALgAECgEJAQABLgAECggJHgAEAEwfAA==.',
Qu='Quiverinpalm:BAAALgAECgcJDgAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8JAAQaAAMJ4RtcCACwAANoDAAABABJAGkMAAADAFwA6gwAAAIAMAAaAAIJWhlcCACwAAJoDAAAAgBJAGkMAAACADgAGwACCSIT9WMAlwACaAwAAAIAMQDqDAAAAgAwABwAAQnwI5oHAGAAAWkMAAABAFwALgAECn8wAAQaAAgJfyNZDgDjAQAaAAUJiyJZDgDjAQAbAAYJPh2vLgC5AQAcAAMJVCT7DQDLAAAAAA==.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIdAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAdAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAEJAgABAAAAAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJEwAeAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAgAAAA==.Siñ:BAABLgAECn8YAAIfAAgJQgZYCQBNAQhoDAAABAAWAGkMAAAEABgAawwAAAQAFgBqDAAAAwARAGwMAAAEABAAbQwAAAIADwDqDAAAAQAEAG4MAAACAAUAHwAICUIGWAkATQEIaAwAAAQAFgBpDAAABAAYAGsMAAAEABYAagwAAAMAEQBsDAAABAAQAG0MAAACAA8A6gwAAAEABABuDAAAAgAFAAAA.',
Sk='Skeetshootah:BAABLgAECn8eAAISAAgJjRbkIwDbAQhoDAAABQBKAGkMAAAFAE0AawwAAAUATQBqDAAAAwAvAGwMAAADACsAbQwAAAIAOADqDAAABQAyAG4MAAACABYAEgAICY0W5CMA2wEIaAwAAAUASgBpDAAABQBNAGsMAAAFAE0AagwAAAMALwBsDAAAAwArAG0MAAACADgA6gwAAAUAMgBuDAAAAgAWAAAA.',
Sl='Slowbadon:BAABLgAECn8XAAIVAAgJLxVvJgBpAQhoDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AFQAICS8VbyYAaQEIaAwAAAQAPwBpDAAABABHAGsMAAAEAEwAagwAAAIAHQBsDAAAAgApAG0MAAACADYA6gwAAAMAMgBuDAAAAgAuAAAA.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAgJAwABAAAAAA==.Streetlight:BAAALgAECgUJBwABLgABCgEJAQABAAAAAA==.Streetlights:BAAALgAECgUJDQABLgABCgEJAQABAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQABAAAAAA==.',
Ta='Tank:BAACLgAFFH8JAAIJAAMJHyTtCAAxAQNoDAAABABZAGkMAAADAFoA6gwAAAIAYQAJAAMJHyTtCAAxAQNoDAAABABZAGkMAAADAFoA6gwAAAIAYQAuAAQKfywAAgkACAm8Ja8CADwDAAkACAm8Ja8CADwDAAAA.',
Te='Teafayd:BAAALgAECgYJDAAAAA==.',
Th='Thunderdot:BAABLgAECn8lAAIQAAkJ/RxTDgCeAgloDAAABQBTAGkMAAAFAFQAawwAAAUAVgBqDAAABABDAGwMAAADAFUAbQwAAAIAKADqDAAACABQAG4MAAAEADkAbwwAAAEASQAQAAkJ/RxTDgCeAgloDAAABQBTAGkMAAAFAFQAawwAAAUAVgBqDAAABABDAGwMAAADAFUAbQwAAAIAKADqDAAACABQAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAABLgAECn9EAAIEAAkJ2x/8CADjAgloDAAACgBfAGkMAAAJAFoAawwAAAoAXQBqDAAACQBWAGwMAAAIAF8AbQwAAAUANwDqDAAACgBWAG4MAAAFAEwAbwwAAAIAOwAEAAkJ2x/8CADjAgloDAAACgBfAGkMAAAJAFoAawwAAAoAXQBqDAAACQBWAGwMAAAIAF8AbQwAAAUANwDqDAAACgBWAG4MAAAFAEwAbwwAAAIAOwAAAA==.',
To='Tomayter:BAABLgAECn8fAAIPAAgJQyAgBgCwAghoDAAABQBdAGkMAAAFAF4AawwAAAUAWABqDAAAAwA2AGwMAAAEAE4AbQwAAAIAUgDqDAAABQBcAG4MAAACAE0ADwAICUMgIAYAsAIIaAwAAAUAXQBpDAAABQBeAGsMAAAFAFgAagwAAAMANgBsDAAABABOAG0MAAACAFIA6gwAAAUAXABuDAAAAgBNAAAA.',
Tr='Trap:BAAALgAFFAEJAgAAAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwALAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIEAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoABAAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAWAFMYAA==.',
Tw='Twaave:BAABLgAECn8jAAIMAAkJlCH1GwAHAwloDAAABQBgAGkMAAAEAGAAawwAAAUAWwBqDAAABABcAGwMAAADAFsAbQwAAAIANgDqDAAABwBeAG4MAAAEAEcAbwwAAAEAWgAMAAkJlCH1GwAHAwloDAAABQBgAGkMAAAEAGAAawwAAAUAWwBqDAAABABcAGwMAAADAFsAbQwAAAIANgDqDAAABwBeAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwABAAAAAA==.',
Ve='Verdessa:BAAALgAECgQJBAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8fAAMaAAgJaRTSCABbAQhoDAAABQA/AGkMAAAFAEgAawwAAAUAQABqDAAAAwAvAGwMAAAEADsAbQwAAAIAGADqDAAABQAzAG4MAAACAB0AGgAICWkU0ggAWwEIaAwAAAIAPwBpDAAABABIAGsMAAAEAEAAagwAAAMALwBsDAAAAwA7AG0MAAABABgA6gwAAAMAMwBuDAAAAQAdABsABwn/BTpfACIBB2gMAAADABQAaQwAAAEABgBrDAAAAQAaAGwMAAABAAoAbQwAAAEAFQDqDAAAAgAOAG4MAAABAAYAAAA=.',
['Æs']='Æsc:BAABLgAECn8fAAIRAAgJmBc+DgCoAQhoDAAABQAxAGkMAAAFAFQAawwAAAUASwBqDAAAAwBBAGwMAAAEAEsAbQwAAAIAIwDqDAAABQA+AG4MAAACACgAEQAICZgXPg4AqAEIaAwAAAUAMQBpDAAABQBUAGsMAAAFAEsAagwAAAMAQQBsDAAABABLAG0MAAACACMA6gwAAAUAPgBuDAAAAgAoAAAA.',
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

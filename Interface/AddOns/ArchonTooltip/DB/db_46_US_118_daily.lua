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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Druid-Guardian','Paladin-Retribution','Mage-Frost','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-05-10',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAABLgAECn8wAAIBAAkJoRmNCABpAgloDAAABwBKAGkMAAAGAEcAawwAAAYAUABqDAAABgAsAGwMAAAGADYAbQwAAAQAWQDqDAAABQAwAG4MAAAEADcAbwwAAAQAMQABAAkJoRmNCABpAgloDAAABwBKAGkMAAAGAEcAawwAAAYAUABqDAAABgAsAGwMAAAGADYAbQwAAAQAWQDqDAAABQAwAG4MAAAEADcAbwwAAAQAMQAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8SAAICAAgJrxmgVgCeAQhoDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAAgAICa8ZoFYAngEIaAwAAAMATABpDAAAAwBUAGsMAAADAEwAagwAAAEAKwBsDAAAAwA3AG0MAAACADcA6gwAAAEALwBuDAAAAgBBAAAA.',
Ar='Aramis:BAAALgAECgUJCQABLgAECggJGgADAG8gAA==.Arathrok:BAABLgAECn8aAAIDAAgJbyDQPwA5AghoDAAABQBfAGkMAAAEAFoAawwAAAQATQBqDAAAAwBdAGwMAAADAFoAbQwAAAEAUQDqDAAABQBNAG4MAAABAEMAAwAICW8g0D8AOQIIaAwAAAUAXwBpDAAABABaAGsMAAAEAE0AagwAAAMAXQBsDAAAAwBaAG0MAAABAFEA6gwAAAUATQBuDAAAAQBDAAAA.',
As='Asha:BAACLgAFFH8IAAIEAAQJAhVqCAA9AQRoDAAAAgA4AGkMAAACADEAawwAAAIASADqDAAAAgAkAAQABAkCFWoIAD0BBGgMAAACADgAaQwAAAIAMQBrDAAAAgBIAOoMAAACACQALgAECn8UAAQFAAcJgheoHwBYAQAFAAQJ0ByoHwBYAQAEAAcJ4B7IHABIAQAGAAQJDA7WMwDRAAAAAA==.Asmoday:BAABLgAECn8eAAIDAAgJTB+SFgBTAghoDAAABQBUAGkMAAAFAF8AawwAAAUAUgBqDAAAAgA5AGwMAAAEAFUAbQwAAAIARgDqDAAABQBYAG4MAAACADUAAwAICUwfkhYAUwIIaAwAAAUAVABpDAAABQBfAGsMAAAFAFIAagwAAAIAOQBsDAAABABVAG0MAAACAEYA6gwAAAUAWABuDAAAAgA1AAAA.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECggJHgADAEwfAA==.Autoshift:BAABLgAECn8WAAIHAAgJ7QpQDABhAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwABwAICe0KUAwAYQEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.',
Ba='Bat:BAABLgAECn8ZAAIHAAgJAyX2AAADAwhoDAAABABhAGkMAAAEAF4AawwAAAMAYgBqDAAAAwBfAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAABAFYABwAICQMl9gAAAwMIaAwAAAQAYQBpDAAABABeAGsMAAADAGIAagwAAAMAXwBsDAAABABeAG0MAAADAGEA6gwAAAMAXgBuDAAAAQBWAAAA.',
Be='Benedictine:BAAALgAECgEJBAAAAA==.',
Bi='Bigcleavage:BAABLgAECn8aAAIIAAgJShqmDACgAQhoDAAABQA+AGkMAAAEAEsAawwAAAQAUgBqDAAAAwBDAGwMAAADAFAAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkACAAICUoapgwAoAEIaAwAAAUAPgBpDAAABABLAGsMAAAEAFIAagwAAAMAQwBsDAAAAwBQAG0MAAACACgA6gwAAAMAOABuDAAAAgBJAAAA.',
Bl='Blueberrypie:BAAALgAECgQJBwABLgAECggJFQAJAKoeAA==.',
Bo='Boomster:BAAALgAFFAgJAwAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8ZAAIKAAgJbCIAKACFAghoDAAABQBjAGkMAAAEAFUAawwAAAQAWwBqDAAAAwBiAGwMAAADAFkAbQwAAAEAWgDqDAAABABiAG4MAAABAD4ACgAICWwiACgAhQIIaAwAAAUAYwBpDAAABABVAGsMAAAEAFsAagwAAAMAYgBsDAAAAwBZAG0MAAABAFoA6gwAAAQAYgBuDAAAAQA+AAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCgAAAA==.',
Ch='Cherrypie:BAAALgAECgIJBAABLgAECggJFQAJAKoeAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cy='Cylla:BAACLgAFFH8IAAILAAMJgQmHUwDoAANoDAAAAwAeAGkMAAADABIA6gwAAAIAFwALAAMJgQmHUwDoAANoDAAAAwAeAGkMAAADABIA6gwAAAIAFwAuAAQKfy0AAgsACAlCHV4hACwCAAsACAlCHV4hACwCAAAA.',
Di='Dilfdormu:BAAALgAECgcJDwAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAABLgAECn8sAAIMAAkJ/BxLEAC1AgloDAAABwBSAGkMAAAGAFYAawwAAAYARgBqDAAABQBbAGwMAAAFAF8AbQwAAAQARgDqDAAABgBSAG4MAAAEADwAbwwAAAEAHAAMAAkJ/BxLEAC1AgloDAAABwBSAGkMAAAGAFYAawwAAAYARgBqDAAABQBbAGwMAAAFAF8AbQwAAAQARgDqDAAABgBSAG4MAAAEADwAbwwAAAEAHAAAAA==.',
Dr='Dratak:BAACLgAFFH8gAAIIAAYJSCX+AAAfAgZoDAAABwBjAGkMAAAGAF4AawwAAAYAWQBqDAAABABfAGwMAAACAGEA6gwAAAcAYQAIAAYJSCX+AAAfAgZoDAAABwBjAGkMAAAGAF4AawwAAAYAWQBqDAAABABfAGwMAAACAGEA6gwAAAcAYQAuAAQKf00AAggACQmVJV0AANMDAAgACQmVJV0AANMDAAAA.Dread:BAABLgAECn8bAAIEAAgJjBq8EAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwavBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJCgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgADCgEJAgABLgAFFAYJIAAIAEglAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAgAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAAALgAECgUJEQAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJCQAIAB8kAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8jAAINAAcJZCIUAQC6AgdoDAAABwBfAGkMAAAGAF4AawwAAAQAYQBqDAAABQBcAGwMAAAEAGAAbQwAAAIAMgDqDAAABwBZAA0ABwlkIhQBALoCB2gMAAAHAF8AaQwAAAYAXgBrDAAABABhAGoMAAAFAFwAbAwAAAQAYABtDAAAAgAyAOoMAAAHAFkALgAECn8zAAQNAAkJbCWlAwAuAwANAAgJQyWlAwAuAwAOAAcJEhE/LwCGAQAPAAIJ3CG4RgDJAAAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAUJEQAQAMIYAA==.',
Gu='Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJCgAAAA==.Haradali:BAAALgAECgIJAgAAAA==.',
Ho='Holydiah:BAAALgAECgYJDQAAAA==.Holypriest:BAAALgAECgcJCQAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAABLgAECn8eAAMNAAgJkB2uEgAdAghoDAAABQBcAGkMAAAFAFAAawwAAAUASgBqDAAABABVAGwMAAADAEgAbQwAAAEAXwDqDAAABgBRAG4MAAABABcADQAHCXYgrhIAHQIHaAwAAAUAXABpDAAABABQAGsMAAAEAEoAagwAAAMAVQBsDAAAAwBIAG0MAAABAF8A6gwAAAYAUQAOAAQJjgmqOACgAARpDAAAAQARAGsMAAABABkAagwAAAEAHgBuDAAAAQAXAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECggJHgADAEwfAA==.Kayla:BAAALgAECgEJAgAAAA==.',
Ki='Kiran:BAAALgAECgEJAwAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgUJEQARAAAAAA==.Kroth:BAABLgAECn84AAIMAAkJ7xDbHgDZAQloDAAACAA5AGkMAAAHACgAawwAAAcAPgBqDAAABwAvAGwMAAAHADgAbQwAAAUAHADqDAAABwA8AG4MAAAFABIAbwwAAAMAEQAMAAkJ7xDbHgDZAQloDAAACAA5AGkMAAAHACgAawwAAAcAPgBqDAAABwAvAGwMAAAHADgAbQwAAAUAHADqDAAABwA8AG4MAAAFABIAbwwAAAMAEQAAAA==.',
Ku='Kubfury:BAAALgAECgUJBgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8cAAISAAgJ9R9mEABXAghoDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAQArAGwMAAADAEcAbQwAAAIAXwDqDAAABQBSAG4MAAACAD0AEgAICfUfZhAAVwIIaAwAAAUAVQBpDAAABQBTAGsMAAAFAFwAagwAAAEAKwBsDAAAAwBHAG0MAAACAF8A6gwAAAUAUgBuDAAAAgA9AAAA.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgAAAA==.',
Lu='Lunaci:BAABLgAECn8bAAMTAAgJQxSKFACtAQhoDAAABABAAGkMAAAEADgAawwAAAQASABqDAAAAwA8AGwMAAAEACwAbQwAAAIAKQDqDAAABAApAG4MAAACACoAEwAICU4TihQArQEIaAwAAAIAQABpDAAAAgA4AGsMAAACAEgAagwAAAEAPABsDAAAAgAsAG0MAAACACkA6gwAAAEAGABuDAAAAgAqABQABgmZDk0KAAUBBmgMAAACACMAaQwAAAIAJQBrDAAAAgA1AGoMAAACAB4AbAwAAAIAEwDqDAAAAwApAAAA.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8fAAIIAAgJnhmDBwAPAghoDAAABQBYAGkMAAAFAEMAawwAAAUAUwBqDAAAAwBLAGwMAAAEAFAAbQwAAAIALwDqDAAABQBCAG4MAAACABkACAAICZ4ZgwcADwIIaAwAAAUAWABpDAAABQBDAGsMAAAFAFMAagwAAAMASwBsDAAABABQAG0MAAACAC8A6gwAAAUAQgBuDAAAAgAZAAAA.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8fAAILAAgJphhWKgAAAghoDAAABQBJAGkMAAAFAEgAawwAAAUASABqDAAAAwBGAGwMAAAEAEQAbQwAAAIAKgDqDAAABQBEAG4MAAACACwACwAICaYYVioAAAIIaAwAAAUASQBpDAAABQBIAGsMAAAFAEgAagwAAAMARgBsDAAABABEAG0MAAACACoA6gwAAAUARABuDAAAAgAsAAAA.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgQJBAAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJCQAIAB8kAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQAAAA==.Misfortune:BAAALgAECgMJBAABLgAECggJGQAKAGwiAA==.Mitsy:BAABLgAECn8UAAIPAAcJFg/iHABhAQdoDAAABAAqAGkMAAADACcAawwAAAIAIgBqDAAAAgAfAGwMAAADABoA6gwAAAQAKABuDAAAAgAvAA8ABwkWD+IcAGEBB2gMAAAEACoAaQwAAAMAJwBrDAAAAgAiAGoMAAACAB8AbAwAAAMAGgDqDAAABAAoAG4MAAACAC8AAAA=.',
Mo='Money:BAABLgAECn8jAAMKAAgJGCGdIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACgAHCRYhnSAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAVAAIJcAe6UgBlAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAAALgAECgYJBgAAAA==.Moons:BAACLgAFFH8QAAIWAAUJbhVEAQBmAQVoDAAABABVAGkMAAAFADAAawwAAAMALgBqDAAAAQAgAOoMAAADACgAFgAFCW4VRAEAZgEFaAwAAAQAVQBpDAAABQAwAGsMAAADAC4AagwAAAEAIADqDAAAAwAoAC4ABAp/PwACFgAJCcIhYAEACwMAFgAJCcIhYAEACwMAAAA=.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAABLgAECn8VAAINAAcJXB9UDgBVAgdoDAAABABfAGkMAAADAE8AawwAAAMASwBqDAAAAwBWAGwMAAACAFsA6gwAAAQAWgBuDAAAAgArAA0ABwlcH1QOAFUCB2gMAAAEAF8AaQwAAAMATwBrDAAAAwBLAGoMAAADAFYAbAwAAAIAWwDqDAAABABaAG4MAAACACsAAAA=.',
Mu='Mudpie:BAABLgAECn8VAAIJAAgJqh59CQAJAghoDAAAAwBRAGkMAAAEAFQAawwAAAQAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEACQAICaoefQkACQIIaAwAAAMAUQBpDAAABABUAGsMAAAEAF0AagwAAAIARgBsDAAAAwBLAG0MAAABAEwA6gwAAAMARwBuDAAAAQBBAAAA.Munco:BAABLgAECn8tAAIXAAgJFyIIBACdAghoDAAABgBgAGkMAAAHAGEAawwAAAcAXQBqDAAABQBhAGwMAAAGAFsAbQwAAAMAQQDqDAAABwBaAG4MAAAEAE0AFwAICRciCAQAnQIIaAwAAAYAYABpDAAABwBhAGsMAAAHAF0AagwAAAUAYQBsDAAABgBbAG0MAAADAEEA6gwAAAcAWgBuDAAABABNAAAA.Muncola:BAAALgAECgEJAQABLgAECggJLQAXABciAA==.Muncoli:BAAALgAECgMJBAABLgAECggJLQAXABciAA==.Muncolito:BAAALgADCgEJAQABLgAECggJLQAXABciAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJCQAIAB8kAA==.',
Ne='Nellie:BAABLgAECn8XAAMYAAgJdQp2IABAAQhoDAAABAAfAGkMAAAEABcAawwAAAQAKABqDAAAAgAdAGwMAAADAB0AbQwAAAEAJADqDAAABAAUAG4MAAABAAUAGAAICXUKdiAAQAEIaAwAAAIAHwBpDAAAAgAXAGsMAAACACgAagwAAAIAHQBsDAAAAwAdAG0MAAABACQA6gwAAAMAFABuDAAAAQAFAAwABAmVAcqwAGQABGgMAAACAAMAaQwAAAIABABrDAAAAgAEAOoMAAABAAMAAAA=.Newtree:BAAALgAFFAQJAgAAAA==.',
No='Notker:BAABLgAECn8fAAIOAAgJRCQ9AgAsAwhoDAAABQBiAGkMAAAFAF0AawwAAAUAYQBqDAAAAwBeAGwMAAAEAGAAbQwAAAIAWADqDAAABQBhAG4MAAACAEsADgAICUQkPQIALAMIaAwAAAUAYgBpDAAABQBdAGsMAAAFAGEAagwAAAMAXgBsDAAABABgAG0MAAACAFgA6gwAAAUAYQBuDAAAAgBLAAAA.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECggJHgADAEwfAA==.',
Or='Orcwarr:BAABLgAECn8gAAQIAAgJ3hfQCADxAQhoDAAABgBLAGkMAAAFAEcAawwAAAUAQwBqDAAABABPAGwMAAAEACUAbQwAAAEAQgDqDAAABQBFAG4MAAACACcACAAICd4X0AgA8QEIaAwAAAQASwBpDAAABABHAGsMAAAEAEMAagwAAAQATwBsDAAABAAlAG0MAAABAEIA6gwAAAQARQBuDAAAAgAnAAEAAwmUCXePAIAAA2gMAAACABsAaQwAAAEAAQBrDAAAAQArABkAAQk9CwlDADMAAeoMAAABABwAAAA=.',
Pa='Panders:BAABLgAFFH8KAAIKAAQJ+AW9JwAbAQRoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAoABAn4Bb0nABsBBGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAECgEJAQABLgAECggJFQAJAKoeAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pipsi:BAAALgAECgEJAQABLgAECggJLQAXABciAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJBQADACkWAA==.',
Pr='Pryor:BAAALgAECgEJAQABLgAECggJHgADAEwfAA==.',
Qu='Quiverinpalm:BAAALgAECgcJDgAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8JAAQaAAMJ4RuqBwCwAANoDAAABABJAGkMAAADAFwA6gwAAAIAMAAaAAIJWhmqBwCwAAJoDAAAAgBJAGkMAAACADgAGwACCSITIl8AlwACaAwAAAIAMQDqDAAAAgAwABwAAQnwI3oGAGEAAWkMAAABAFwALgAECn8tAAQaAAgJfyNaDgDjAQAaAAUJ/yFaDgDjAQAbAAYJPh09LAC5AQAcAAMJVCSSDQDCAAAAAA==.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIdAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAdAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAEJAgARAAAAAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJEwAeAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAQAAAA==.Siñ:BAABLgAECn8VAAIfAAgJQAVZCQBBAQhoDAAAAwAPAGkMAAADAA4AawwAAAMAFgBqDAAAAwARAGwMAAAEABAAbQwAAAIADwDqDAAAAQAEAG4MAAACAAUAHwAICUAFWQkAQQEIaAwAAAMADwBpDAAAAwAOAGsMAAADABYAagwAAAMAEQBsDAAABAAQAG0MAAACAA8A6gwAAAEABABuDAAAAgAFAAAA.',
Sk='Skeetshootah:BAABLgAECn8eAAISAAgJjRY+IgDTAQhoDAAABQBKAGkMAAAFAE0AawwAAAUATQBqDAAAAwAvAGwMAAADACsAbQwAAAIAOADqDAAABQAyAG4MAAACABYAEgAICY0WPiIA0wEIaAwAAAUASgBpDAAABQBNAGsMAAAFAE0AagwAAAMALwBsDAAAAwArAG0MAAACADgA6gwAAAUAMgBuDAAAAgAWAAAA.',
Sl='Slowbadon:BAABLgAECn8XAAIVAAgJLxXxJABtAQhoDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AFQAICS8V8SQAbQEIaAwAAAQAPwBpDAAABABHAGsMAAAEAEwAagwAAAIAHQBsDAAAAgApAG0MAAACADYA6gwAAAMAMgBuDAAAAgAuAAAA.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgAAAA==.Streetlight:BAAALgAECgUJBwABLgABCgEJAQARAAAAAA==.Streetlights:BAAALgAECgUJDQABLgABCgEJAQARAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQARAAAAAA==.',
Ta='Tank:BAACLgAFFH8JAAIIAAMJHyQWCAA0AQNoDAAABABZAGkMAAADAFoA6gwAAAIAYQAIAAMJHyQWCAA0AQNoDAAABABZAGkMAAADAFoA6gwAAAIAYQAuAAQKfykAAggACAl/Ja4CADwDAAgACAl/Ja4CADwDAAAA.',
Te='Teafayd:BAAALgAECgMJBgAAAA==.',
Th='Thunderdot:BAABLgAECn8kAAIPAAkJ/RxSDgCeAgloDAAABQBTAGkMAAAFAFQAawwAAAQAVgBqDAAABABDAGwMAAADAFUAbQwAAAIAKADqDAAACABQAG4MAAAEADkAbwwAAAEASQAPAAkJ/RxSDgCeAgloDAAABQBTAGkMAAAFAFQAawwAAAQAVgBqDAAABABDAGwMAAADAFUAbQwAAAIAKADqDAAACABQAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAABLgAECn9EAAIDAAkJ2x8wCADkAgloDAAACgBfAGkMAAAJAFoAawwAAAoAXQBqDAAACQBWAGwMAAAIAF8AbQwAAAUANwDqDAAACgBWAG4MAAAFAEwAbwwAAAIAOwADAAkJ2x8wCADkAgloDAAACgBfAGkMAAAJAFoAawwAAAoAXQBqDAAACQBWAGwMAAAIAF8AbQwAAAUANwDqDAAACgBWAG4MAAAFAEwAbwwAAAIAOwAAAA==.',
To='Tomayter:BAABLgAECn8fAAIOAAgJQyCfBQCwAghoDAAABQBdAGkMAAAFAF4AawwAAAUAWABqDAAAAwA2AGwMAAAEAE4AbQwAAAIAUgDqDAAABQBcAG4MAAACAE0ADgAICUMgnwUAsAIIaAwAAAUAXQBpDAAABQBeAGsMAAAFAFgAagwAAAMANgBsDAAABABOAG0MAAACAFIA6gwAAAUAXABuDAAAAgBNAAAA.',
Tr='Trap:BAAALgAFFAEJAgAAAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQAKAG4aAA==.Trist:BAABLgAECn8dAAIKAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAKAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8kAAIDAAgJuh4DLQCFAghoDAAABgBeAGkMAAAGAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeAy0AhQIIaAwAAAYAXgBpDAAABgBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAWAFMYAA==.',
Tw='Twaave:BAABLgAECn8iAAILAAkJlCH1GwAHAwloDAAABQBgAGkMAAAEAGAAawwAAAQAWwBqDAAABABcAGwMAAADAFsAbQwAAAIANgDqDAAABwBeAG4MAAAEAEcAbwwAAAEAWgALAAkJlCH1GwAHAwloDAAABQBgAGkMAAAEAGAAawwAAAQAWwBqDAAABABcAGwMAAADAFsAbQwAAAIANgDqDAAABwBeAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwARAAAAAA==.',
Ve='Verdessa:BAAALgAECgQJBAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8fAAMaAAgJaRQNCABnAQhoDAAABQA/AGkMAAAFAEgAawwAAAUAQABqDAAAAwAvAGwMAAAEADsAbQwAAAIAGADqDAAABQAzAG4MAAACAB0AGgAICWkUDQgAZwEIaAwAAAIAPwBpDAAABABIAGsMAAAEAEAAagwAAAMALwBsDAAAAwA7AG0MAAABABgA6gwAAAMAMwBuDAAAAQAdABsABwn/BchbACABB2gMAAADABQAaQwAAAEABgBrDAAAAQAaAGwMAAABAAoAbQwAAAEAFQDqDAAAAgAOAG4MAAABAAYAAAA=.',
['Æs']='Æsc:BAABLgAECn8fAAIQAAgJmBdxDQCoAQhoDAAABQAxAGkMAAAFAFQAawwAAAUASwBqDAAAAwBBAGwMAAAEAEsAbQwAAAIAIwDqDAAABQA+AG4MAAACACgAEAAICZgXcQ0AqAEIaAwAAAUAMQBpDAAABQBUAGsMAAAFAEsAagwAAAMAQQBsDAAABABLAG0MAAACACMA6gwAAAUAPgBuDAAAAgAoAAAA.',
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

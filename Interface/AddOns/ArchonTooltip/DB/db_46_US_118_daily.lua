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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Unknown-Unknown','Druid-Feral','Warrior-Protection','Paladin-Retribution','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Hunter-Survival','Druid-Guardian','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-05-20',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgIJAgAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8KAAIBAAQJeAYzHgAGAQRoDAAAAwANAGkMAAADABgAawwAAAEACQDqDAAAAwASAAEABAl4BjMeAAYBBGgMAAADAA0AaQwAAAMAGABrDAAAAQAJAOoMAAADABIALgAECn9CAAIBAAkJAxvhDwBNAgABAAkJAxvhDwBNAgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwACAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwAAAA==.',
Ar='Aramis:BAAALgAECggJEgABLgAECgkJHAADAIkgAA==.Aranumi:BAAALgAECgMJAwABLgAECgkJHAADAIkgAA==.Arathrok:BAABLgAECn8cAAIDAAkJiSDSPwA5AgloDAAABQBfAGkMAAAEAFoAawwAAAQATQBqDAAAAwBdAGwMAAADAFoAbQwAAAEAUQDqDAAABQBNAG4MAAABAEMAbwwAAAIAVQADAAkJiSDSPwA5AgloDAAABQBfAGkMAAAEAFoAawwAAAQATQBqDAAAAwBdAGwMAAADAFoAbQwAAAEAUQDqDAAABQBNAG4MAAABAEMAbwwAAAIAVQAAAA==.',
As='Asha:BAACLgAFFH8SAAMEAAUJ/xYeCwA6AQVoDAAABABHAGkMAAAEADEAawwAAAQATgBqDAAAAgA7AOoMAAAEACQABAAFCf8WHgsAOgEFaAwAAAMARwBpDAAAAwAxAGsMAAADAE4AagwAAAEAOwDqDAAAAwAkAAUABQntBeAlAO4ABWgMAAABABYAaQwAAAEADQBrDAAAAQAPAGoMAAABABQA6gwAAAEACAAuAAQKfxwABAQACAnLIEwWANEBAAQACAnLIEwWANEBAAYABAnQHPIxAEcBAAUABQnGGTIvACIBAAAA.Asmoday:BAABLgAECn8pAAIDAAkJzCKkCQD9AgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgADAAkJzCKkCQD9AgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgAAAA==.Astra:BAAALgAECgEJAQABLgAECgQJBAAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECgkJKQADAMwiAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7QrKEwA6AQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe0KyhMAOgEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.Auun:BAAALgAECgEJAQABLgAECgkJKQADAMwiAA==.',
Ba='Bat:BAABLgAECn8cAAIIAAgJHCUBAgDqAghoDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAABAFYACAAICRwlAQIA6gIIaAwAAAUAYwBpDAAABQBeAGsMAAADAGIAagwAAAQAYgBsDAAABABeAG0MAAADAGEA6gwAAAMAXgBuDAAAAQBWAAAA.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIJAAkJARteCgAdAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAJAAkJARteCgAdAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAAAA==.Bilbert:BAAALgAECgMJAwABLgAECgkJIQAKAMAjAA==.',
Bl='Blueberrypie:BAAALgAFFAEJAQABLgAFFAEJAQAHAAAAAA==.',
Bo='Boomster:BAAALgAFFAgJBAAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8hAAIKAAkJwCNHDgDTAgloDAAABgBjAGkMAAAFAFUAawwAAAUAWwBqDAAAAwBiAGwMAAAEAFkAbQwAAAIAWgDqDAAABABiAG4MAAACAF8AbwwAAAIAUgAKAAkJwCNHDgDTAgloDAAABgBjAGkMAAAFAFUAawwAAAUAWwBqDAAAAwBiAGwMAAAEAFkAbQwAAAIAWgDqDAAABABiAG4MAAACAF8AbwwAAAIAUgAAAA==.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQAAAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBAABLgAFFAEJAQAHAAAAAA==.Criscomaster:BAAALgADCgUJBQAAAA==.',
Cy='Cylla:BAACLgAFFH8OAAILAAMJ2gxtZADpAANoDAAABQAeAGkMAAAFABIA6gwAAAQAMQALAAMJ2gxtZADpAANoDAAABQAeAGkMAAAFABIA6gwAAAQAMQAuAAQKfzcAAgsACQl5HN0kAGECAAsACQl5HN0kAGECAAAA.',
Di='Dilfdormu:BAABLgAECn8WAAMMAAYJQAt1HADrAAZoDAAAAwA4AGkMAAAEABMAawwAAAQAHQBqDAAABQASAGwMAAACAB0A6gwAAAQAEgAMAAYJQAt1HADrAAZoDAAAAwA4AGkMAAADABMAawwAAAMAHQBqDAAABQASAGwMAAACAB0A6gwAAAQAEgANAAIJ1QL/dQA2AAJpDAAAAQAGAGsMAAABAAcAAAA=.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8JAAIOAAMJgBGPLgDMAANoDAAABQA7AGkMAAADACAA6gwAAAEAKgAOAAMJgBGPLgDMAANoDAAABQA7AGkMAAADACAA6gwAAAEAKgAuAAQKfzUAAg4ACQkjH+gGACYDAA4ACQkjH+gGACYDAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH8vAAIJAAcJTCS7AACFAgdoDAAACQBjAGkMAAAIAGAAawwAAAgAXgBqDAAABgBfAGwMAAAEAGEAbQwAAAMASADqDAAACQBhAAkABwlMJLsAAIUCB2gMAAAJAGMAaQwAAAgAYABrDAAACABeAGoMAAAGAF8AbAwAAAQAYQBtDAAAAwBIAOoMAAAJAGEALgAECn9fAAIJAAkJQCZBAACCAwAJAAkJQCZBAACCAwAAAA==.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJAgABLgAFFAcJLwAJAEwkAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8XAAMBAAYJBBGXSQDsAAZoDAAABQAjAGkMAAAFADMAawwAAAQALQBqDAAAAwBHAGwMAAABABkA6gwAAAUAOgABAAUJbxGXSQDsAAVoDAAABAAjAGkMAAAEAC4AawwAAAMAJQBqDAAAAgBHAOoMAAAFADoACQAFCeoNKSkAuwAFaAwAAAEAEwBpDAAAAQAzAGsMAAABAC0AagwAAAEAQwBsDAAAAQAZAAAA.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJDwAJABglAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8rAAIPAAgJYyL1AAAXAwhoDAAACABfAGkMAAAHAF4AawwAAAUAYQBqDAAABgBcAGwMAAAFAGAAbQwAAAIAMgDqDAAACQBZAG4MAAABAFcADwAICWMi9QAAFwMIaAwAAAgAXwBpDAAABwBeAGsMAAAFAGEAagwAAAYAXABsDAAABQBgAG0MAAACADIA6gwAAAkAWQBuDAAAAQBXAC4ABAp/PgAEDwAJCXElnQAA0wMADwAJCXElnQAA0wMAEAAHCRIRQC8AhgEAEQACCdwhukYAyQAAAAA=.',
Ge='Geronimô:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAYJFgASACIWAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDAAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAAALgAECgYJEgAAAA==.Holypriest:BAAALgAECgcJCQAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAABLgAECn8iAAQPAAkJYRywEgAdAgloDAAABQBcAGkMAAAFAFAAawwAAAUASgBqDAAABABVAGwMAAADAEgAbQwAAAIAXwDqDAAABgBRAG4MAAACABcAbwwAAAIAMAAPAAgJxB6wEgAdAghoDAAABQBcAGkMAAAEAFAAawwAAAQASgBqDAAAAwBVAGwMAAADAEgAbQwAAAEAXwDqDAAABgBRAG8MAAACADAAEAAECY4JRUUAnQAEaQwAAAEAEQBrDAAAAQAZAGoMAAABAB4AbgwAAAIAFwARAAEJkAg2cAAsAAFtDAAAAQAVAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAMwiAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ki='Kiran:BAAALgAECgEJAwABLgAECgIJAgAHAAAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgYJFwABAAQRAA==.Kroth:BAABLgAECn9KAAIOAAkJpxMYIwADAgloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAOAAkJpxMYIwADAgloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDQAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAITAAkJACK6CgDSAgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAATAAkJACK6CgDSAgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.',
Lu='Lunaci:BAABLgAECn8qAAMNAAkJEBzoCQCQAgloDAAABgBAAGkMAAAFADgAawwAAAUAUABqDAAABABJAGwMAAAGAE4AbQwAAAQARQDqDAAABgBZAG4MAAAEAE4AbwwAAAIAOgANAAkJEBzoCQCQAgloDAAABABAAGkMAAADADgAawwAAAMAUABqDAAAAgBJAGwMAAAEAE4AbQwAAAQARQDqDAAAAwBZAG4MAAAEAE4AbwwAAAIAOgAUAAYJmQ40DgABAQZoDAAAAgAjAGkMAAACACUAawwAAAIANQBqDAAAAgAeAGwMAAACABMA6gwAAAMAKQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIJAAkJVx0OBQChAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAJAAkJVx0OBQChAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAILAAkJvBzgFAC5AgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwALAAkJvBzgFAC5AgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJDwAJABglAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQABLgAFFAgJBAAHAAAAAA==.Misfortune:BAAALgAECgcJCwABLgAECgkJIQAKAMAjAA==.Mitsy:BAABLgAECn8dAAIRAAgJQRI8HgCfAQhoDAAABQA+AGkMAAAEADMAawwAAAQANQBqDAAABAA+AGwMAAAEACsAbQwAAAEAGQDqDAAABQArAG4MAAACAC8AEQAICUESPB4AnwEIaAwAAAUAPgBpDAAABAAzAGsMAAAEADUAagwAAAQAPgBsDAAABAArAG0MAAABABkA6gwAAAUAKwBuDAAAAgAvAAAA.',
Mo='Money:BAABLgAECn8jAAMKAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACgAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAVAAIJcAedZwBbAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAABLgAECn8WAAMWAAkJ7RQOFQBBAQloDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAwBGAGwMAAACAC8AbQwAAAEAGADqDAAAAgBBAG4MAAABACQAbwwAAAEAFwAWAAUJBh0OFQBBAQVoDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAQBGAOoMAAABAEEACgAGCWYN05kAFgEGagwAAAIAQgBsDAAAAgAvAG0MAAABABgA6gwAAAEAKABuDAAAAQAkAG8MAAABABcAAAA=.Moons:BAACLgAFFH8RAAIXAAYJtRPaAwCZAQZoDAAABABVAGkMAAAFADAAawwAAAMALgBqDAAAAQAgAGwMAAABACAA6gwAAAMAKAAXAAYJtRPaAwCZAQZoDAAABABVAGkMAAAFADAAawwAAAMALgBqDAAAAQAgAGwMAAABACAA6gwAAAMAKAAuAAQKf0gAAhcACQlII0YCAAoDABcACQlII0YCAAoDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8FAAIPAAUJSAdXDwDaAAVoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAQAPAOoMAAABABYADwAFCUgHVw8A2gAFaAwAAAEAKABpDAAAAQAJAGsMAAABAAUAbAwAAAEADwDqDAAAAQAWAC4ABAp/GAACDwAHCasfVQ4AVQIADwAHCasfVQ4AVQIAAAA=.',
Mu='Mudpie:BAABLgAECn8ZAAIYAAkJuR5wCAAgAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAEAQAAYAAkJuR5wCAAgAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAEAQAABLgAFFAEJAQAHAAAAAA==.Munco:BAACLgAFFH8FAAIZAAQJVhuABgBRAQRoDAAAAQBBAGkMAAABAEQAawwAAAEAUwDqDAAAAgA+ABkABAlWG4AGAFEBBGgMAAABAEEAaQwAAAEARABrDAAAAQBTAOoMAAACAD4ALgAECn88AAIZAAkJ5CODAQA8AwAZAAkJ5CODAQA8AwAAAA==.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAZAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAZAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAZAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJDwAJABglAA==.',
Ne='Nellie:BAABLgAECn8gAAMaAAkJJg5HHQCkAQloDAAABQAfAGkMAAAFABcAawwAAAUAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABQA0AG4MAAACAA8AbwwAAAEAKAAaAAkJJg5HHQCkAQloDAAAAwAfAGkMAAADABcAawwAAAMAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABAA0AG4MAAACAA8AbwwAAAEAKAAOAAQJlQHMsABkAARoDAAAAgADAGkMAAACAAQAawwAAAIABADqDAAAAQADAAAA.Newtree:BAAALgAFFAQJBAABLgAFFAgJBAAHAAAAAA==.',
No='Notker:BAABLgAECn8uAAIQAAkJ7COcAQCAAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAQAAkJ7COcAQCAAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAAAA==.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECgkJKQADAMwiAA==.',
Or='Orcwarr:BAABLgAECn8oAAQJAAgJQRsoCwAMAghoDAAABwBLAGkMAAAGAEcAawwAAAYAVgBqDAAABQBPAGwMAAAFAEIAbQwAAAIAQgDqDAAABgBFAG4MAAADADMACQAICUEbKAsADAIIaAwAAAUASwBpDAAABQBHAGsMAAAFAFYAagwAAAUATwBsDAAABQBCAG0MAAACAEIA6gwAAAUARQBuDAAAAwAzAAEAAwmUCXiPAIAAA2gMAAACABsAaQwAAAEAAQBrDAAAAQArABsAAQk9CwpDADMAAeoMAAABABwAAAA=.',
Pa='Panders:BAABLgAFFH8KAAIKAAQJ+AXLOgAGAQRoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAoABAn4Bcs6AAYBBGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAECgYJBwABLgAFFAEJAQAHAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAgJBAAHAAAAAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAZAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAMwiAA==.',
Qu='Quiverinpalm:BAABLgAECn8UAAIFAAcJ5Q6PLAAwAQdoDAAABQA9AGkMAAAEAB4AawwAAAMAIwBqDAAAAgAcAGwMAAACACYAbQwAAAEAEwDqDAAAAwArAAUABwnlDo8sADABB2gMAAAFAD0AaQwAAAQAHgBrDAAAAwAjAGoMAAACABwAbAwAAAIAJgBtDAAAAQATAOoMAAADACsAAAA=.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8PAAQcAAMJZB5UDACeAANoDAAABgBQAGkMAAAFAFwA6gwAAAQAPQAdAAIJnRuAaQCyAAJoDAAABABQAOoMAAAEAD0AHAACCVoZVAwAngACaAwAAAIASQBpDAAAAgA4AB4AAQnwI6UOAFYAAWkMAAADAFwALgAECn83AAQcAAkJ7yNZDgDjAQAdAAcJox7iJgAdAgAcAAUJiyJZDgDjAQAeAAMJVCSZFwC5AAAAAA==.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAQJBAAHAAAAAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJFQAgAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIhAAkJTQiKCACQAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAhAAkJTQiKCACQAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAAAA==.',
Sk='Skeetshootah:BAABLgAECn8tAAITAAkJ2hfjHwAxAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgATAAkJ2hfjHwAxAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAAAA==.Skúnkstomper:BAAALgAECgEJAQAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIVAAkJixOqKwCBAQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAVAAkJixOqKwCBAQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.Streetlight:BAABLgAECn8VAAIXAAkJYg9UDwATAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAAXAAkJYg9UDwATAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8PAAIJAAMJGCWCCQBJAQNoDAAABgBeAGkMAAAFAFwA6gwAAAQAYQAJAAMJGCWCCQBJAQNoDAAABgBeAGkMAAAFAFwA6gwAAAQAYQAuAAQKfy8AAgkACQmCJa8CADwDAAkACQmCJa8CADwDAAAA.',
Te='Teafayd:BAABLgAECn8XAAMeAAYJhQuiFQDNAAZoDAAABAAcAGkMAAAGACQAawwAAAUAJABqDAAAAwAcAGwMAAACABMA6gwAAAMAGwAeAAYJCAuiFQDNAAZoDAAAAgAVAGkMAAAGACQAawwAAAQAJABqDAAAAwAcAGwMAAACABMA6gwAAAMAGwAcAAIJMAroKQBTAAJoDAAAAgAcAGsMAAABABgAAAA=.',
Th='Thunderdot:BAABLgAECn8yAAIRAAkJcR6pCACXAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQARAAkJcR6pCACXAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8LAAIDAAQJgRWDOgBLAQRoDAAABABIAGkMAAADAEEAawwAAAIALQDqDAAAAgAlAAMABAmBFYM6AEsBBGgMAAAEAEgAaQwAAAMAQQBrDAAAAgAtAOoMAAACACUALgAECn9NAAIDAAkJziL2CAAEAwADAAkJziL2CAAEAwAAAA==.',
To='Tomayter:BAABLgAECn8tAAIQAAkJzh9XBQD+AgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAQAAkJzh9XBQD+AgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAQJBAAHAAAAAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQAKAG4aAA==.Trist:BAABLgAECn8dAAIKAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAKAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAXAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAILAAkJjSIJCQAXAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgALAAkJjSIJCQAXAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Verdessa:BAAALgAECgQJCAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMcAAkJfhptAgBjAgloDAAABwBAAGkMAAAGAEgAawwAAAYAUABqDAAABAA6AGwMAAAGAEUAbQwAAAQAOADqDAAABwA7AG4MAAAEAEQAbwwAAAIARwAcAAkJfhptAgBjAgloDAAABABAAGkMAAAFAEgAawwAAAUAUABqDAAABAA6AGwMAAAFAEUAbQwAAAMAOADqDAAABQA7AG4MAAADAEQAbwwAAAIARwAdAAcJ/wUpggAWAQdoDAAAAwAUAGkMAAABAAYAawwAAAEAGgBsDAAAAQAKAG0MAAABABUA6gwAAAIADgBuDAAAAQAGAAAA.',
['Æs']='Æsc:BAABLgAECn8uAAISAAkJUBfIDwDPAQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAASAAkJUBfIDwDPAQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAAAA==.',
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

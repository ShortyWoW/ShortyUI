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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Fire','Mage-Frost','Paladin-Retribution','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','DemonHunter-Vengeance','Rogue-Outlaw','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Holy','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Warrior-Arms','Rogue-Assassination','Mage-Arcane','Paladin-Protection','Druid-Balance','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-06-05',data={Ad='Advvy:BAEALgAECgUJEgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8+AAICAAkJiCIIBQAKAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAGAFYAbQwAAAUATQDqDAAACgBVAG4MAAAGAFoAbwwAAAQAXQACAAkJiCIIBQAKAwloDAAACQBdAGkMAAAIAFgAawwAAAgAWwBqDAAABgBPAGwMAAAGAFYAbQwAAAUATQDqDAAACgBVAG4MAAAGAFoAbwwAAAQAXQAAAA==.Algebra:BAECLgAFFH8bAAMDAAYJwiSGAACnAQZoDAAABwBfAGkMAAAGAGEAawwAAAUAYwBqDAAAAwBaAGwMAAABAFkA6gwAAAUAWQAEAAYJfiSpGgD/AQZoDAAABgBbAGkMAAAFAGEAawwAAAQAYwBqDAAAAgBaAGwMAAABAFkA6gwAAAQAWQADAAUJxSSGAACnAQVoDAAAAQBfAGkMAAABAF8AawwAAAEAYQBqDAAAAQBUAOoMAAABAFgALgAECn8dAAIEAAkJoSS1CQAnAwAEAAkJoSS1CQAnAwAAAA==.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgcJDwAAAA==.Aradell:BAEALgAFFAMJAwABLgAFFAMJCAAFANsPAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJFAAGAGweAA==.',
Ay='Ayoade:BAECLgAFFH8dAAIHAAUJ+RQTEwBLAQVoDAAABwAzAGkMAAAHAD0AawwAAAcATgBqDAAAAQAfAOoMAAAHAC0ABwAFCfkUExMASwEFaAwAAAcAMwBpDAAABwA9AGsMAAAHAE4AagwAAAEAHwDqDAAABwAtAC4ABAp/GAADBwAICWkcnQoAjAIABwAICWkcnQoAjAIACAACCREV4zEAhwAAAS4ABRQICTQACQB9IAA=.',
Az='Azzurel:BAEBLgAECn8XAAMKAAgJMBFadgBIAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACgAICTARWnYASAEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAsAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEBLgAFFH8FAAIMAAUJawotFwC3AAVoDAAAAQAyAGkMAAABAAkAawwAAAEAGwBqDAAAAQAiAOoMAAABABMADAAFCWsKLRcAtwAFaAwAAAEAMgBpDAAAAQAJAGsMAAABABsAagwAAAEAIgDqDAAAAQATAAEuAAUUBQkSAA0AIBUA.',
Bl='Bloodroyal:BAEALgADCgcJBwABLgAFFAMJDgAOAEsdAA==.',
Bo='Bobbysan:BAECLgAFFH8fAAIPAAgJnhiqBQAaAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAACABWAG4MAAABADgADwAICZ4YqgUAGgIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAgAVgBuDAAAAQA4AC4ABAp/LwACDwAJCRghYAsAdgIADwAJCRghYAsAdgIAAAA=.Bonemommyxo:BAECLgAFFH8UAAIQAAYJEiNOFwD7AQZoDAAABQBhAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAQAAYJEiNOFwD7AQZoDAAABQBhAGkMAAAFAGMAawwAAAMAXQBqDAAAAQApAG0MAAABADsA6gwAAAUAYwAuAAQKfysAAhAACQmQJRwCALsDABAACQmQJRwCALsDAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Bu='Buttlustplz:BAEALgAFFAEJAgABLgAFFAMJCQARANgfAA==.',
Ch='Chunghús:BAEALgAECgYJBgABLgAFFAgJGwAHAEUNAA==.',
Co='Coggettle:BAEALgADCgcJBwABLgAECggJKAASANMgAA==.',
Cr='Crustome:BAEBLgAECn8aAAITAAgJ0QfSJgBPAQhoDAAABgATAGkMAAAGABMAawwAAAUAEABqDAAAAwAaAGwMAAACACQAbQwAAAEABgDqDAAAAgAJAG4MAAABAB8AEwAICdEH0iYATwEIaAwAAAYAEwBpDAAABgATAGsMAAAFABAAagwAAAMAGgBsDAAAAgAkAG0MAAABAAYA6gwAAAIACQBuDAAAAQAfAAAA.Crustorc:BAEBLgAECn8XAAIUAAkJigcvNQBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQAUAAkJigcvNQBqAQloDAAAAwAXAGkMAAADABYAawwAAAMADwBqDAAAAwAXAGwMAAADABwAbQwAAAEACQDqDAAABAAPAG4MAAACABEAbwwAAAEAFQABLgAECggJGgATANEHAA==.',
Cu='Cubed:BAEALgAFFAEJAQABLgAFFAYJGwADAMIkAA==.',
Da='Darkstrand:BAEALgAECgYJBgABLgAFFAMJDgAOAEsdAA==.',
De='Deathhealher:BAEALgADCgEJAQABLgAECgcJFgAVAKYFAA==.Deathhunterz:BAEBLgAECn8WAAIVAAcJpgW1ogDOAAdoDAAABAAPAGkMAAAEABIAawwAAAUACQBqDAAAAgAaAGwMAAADABgAbQwAAAEACwDqDAAAAwAGABUABwmmBbWiAM4AB2gMAAAEAA8AaQwAAAQAEgBrDAAABQAJAGoMAAACABoAbAwAAAMAGABtDAAAAQALAOoMAAADAAYAAAA=.Demagogué:BAECLgAFFH8OAAMWAAcJFRUrEwBrAQdoDAAAAgA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAYAQQBuDAAAAQA0ABYABgnCESsTAGsBBmgMAAABAD0AawwAAAEACQBqDAAAAQAlAG0MAAABACcA6gwAAAUAQQBuDAAAAQA0AAkAAwkaFQQ9AOEAA2gMAAABABwAbAwAAAIAMgDqDAAAAQBTAC4ABAp/JwADFgAICfsjwQgAxgIAFgAICfsjwQgAxgIACQAHCZEcoDMA1AEAAS4ABRQICRsABwBFDQA=.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Dreamspun:BAECLgAFFH8OAAIOAAMJSx08BwD/AANoDAAABQBGAGkMAAACAEoA6gwAAAcAUAAOAAMJSx08BwD/AANoDAAABQBGAGkMAAACAEoA6gwAAAcAUAAuAAQKfzYAAg4ACQmeIpIAADIDAA4ACQmeIpIAADIDAAAA.Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8UAAIXAAYJUiAdCwAkAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAXAAYJUiAdCwAkAgZoDAAABABTAGkMAAAEAGAAawwAAAUAXABqDAAAAgBUAGwMAAACAC4A6gwAAAMAXQAuAAQKfxcAAxcACAmLIZwGAPMCABcACAmLIZwGAPMCABgAAQl/JqFrAGsAAAEuAAUUCAk0AAkAfSAA.Dubsy:BAECLgAFFH80AAIJAAgJfSB/AAA2AghoDAAACwBQAGkMAAALAF8AawwAAAgAWwBqDAAACQBjAGwMAAABAEMAbQwAAAEALADqDAAACgBWAG4MAAABAGQACQAICX0gfwAANgIIaAwAAAsAUABpDAAACwBfAGsMAAAIAFsAagwAAAkAYwBsDAAAAQBDAG0MAAABACwA6gwAAAoAVgBuDAAAAQBkAC4ABAp/MwADCQAJCdAllgAAtAMACQAJCdAllgAAtAMAFgAECbUj8isAhgEAAAA=.',
Eh='Ehanee:BAEALgAFFAIJAwAAAA==.',
Ei='Eibm:BAEALgAECgEJAQAAAA==.',
Er='Ereshin:BAEBLgAECn8YAAIJAAgJXB8/DADsAghoDAAABQBjAGkMAAADAGAAawwAAAQAWQBqDAAAAwBKAGwMAAACAE8AbQwAAAEAEgDqDAAAAwBYAG4MAAADAGAACQAICVwfPwwA7AIIaAwAAAUAYwBpDAAAAwBgAGsMAAAEAFkAagwAAAMASgBsDAAAAgBPAG0MAAABABIA6gwAAAMAWABuDAAAAwBgAAAA.',
Ev='Evieari:BAECLgAFFH8WAAMZAAYJ8xdxCgCFAQZoDAAABABAAGkMAAAEACYAawwAAAQALwBqDAAABAAlAGwMAAABAGAA6gwAAAUAUgAZAAUJZBlxCgCFAQVoDAAAAgBAAGkMAAABACYAawwAAAEAKgBsDAAAAQBgAOoMAAADAFIAGgAFCVAMuh0AQwEFaAwAAAIAJQBpDAAAAwAYAGsMAAADAC8AagwAAAQAJQDqDAAAAgAKAC4ABAp/GQADGgAJCdYauBsA4gEAGgAGCaYcuBsA4gEAGQAHCbkZmCkApQEAAS4ABRQGCQUAGQBKHwA=.Evielyssa:BAEBLgAFFH8JAAIZAAUJGRIjEAA5AQVoDAAAAgAZAGkMAAACACUAawwAAAIAMQBqDAAAAQBMAOoMAAACACoAGQAFCRkSIxAAOQEFaAwAAAIAGQBpDAAAAgAlAGsMAAACADEAagwAAAEATADqDAAAAgAqAAEuAAUUBgkFABkASh8A.Evierari:BAEBLgAFFH8FAAMZAAIJSh9bIQCYAAJoDAAAAwBQAGkMAAACAE8AGQACCUofWyEAmAACaAwAAAIAUABpDAAAAgBPABsAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8mAAMQAAYJkyR2FgABAgZoDAAACQBiAGkMAAAJAGEAawwAAAcAWgBqDAAABABVAGwMAAABAFEA6gwAAAgAYwAQAAYJkyR2FgABAgZoDAAABwBiAGkMAAAHAGEAawwAAAUAWgBqDAAAAgBVAGwMAAABAFEA6gwAAAUAYwAcAAUJtBYECgA3AQVoDAAAAgAtAGkMAAACADwAawwAAAIAPQBqDAAAAgAkAOoMAAADAEAALgAECn8/AAMQAAkJMCZ3AgC0AwAQAAkJMCZ3AgC0AwAcAAYJpxy5CwCqAQAAAA==.',
Fe='Felshins:BAEALgADCgMJBgABLgAECggJGAAJAFwfAA==.',
Fo='Fofer:BAEBLgAECn8nAAIPAAcJASYZCQCYAgdoDAAACABjAGkMAAAIAGIAawwAAAgAYwBqDAAABQBjAGwMAAAFAGMAbQwAAAEAWQDqDAAABABgAA8ABwkBJhkJAJgCB2gMAAAIAGMAaQwAAAgAYgBrDAAACABjAGoMAAAFAGMAbAwAAAUAYwBtDAAAAQBZAOoMAAAEAGAAAS4ABRQICR8AHQBCHwA=.Foil:BAEALgADCgkJGwABLgAECgkJVgAeAMglAA==.',
Fr='Froshin:BAEALgADCgUJCwABLgAECggJGAAJAFwfAA==.',
Fs='Fshi:BAEALgAECgcJBAAAAA==.',
Fu='Funkey:BAECLgAFFH8SAAMNAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAgAWAOoMAAAEACYAFQAFCZkO1EsA+QAFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAIAFgDqDAAABAAmAA0AAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAw0ACQmfIMQBAPwCAA0ACAmzIsQBAPwCABUABgl+FiNRAIUBAAAA.',
Gr='Greatares:BAEBLgAFFH8FAAIfAAMJPgdlJwCyAANoDAAAAgAKAGkMAAABABAA6gwAAAIAGwAfAAMJPgdlJwCyAANoDAAAAgAKAGkMAAABABAA6gwAAAIAGwAAAA==.Greathades:BAEALgAECgkJAgABLgAFFAMJBQAfAD4HAA==.Greatmonkey:BAEALgAECgcJBgABLgAFFAMJBQAfAD4HAA==.Greatodin:BAEALgAECgkJBAABLgAFFAMJBQAfAD4HAA==.Greatosiris:BAEALgAECgkJAgABLgAFFAMJBQAfAD4HAA==.Greatra:BAEALgADCgEJAQABLgAFFAMJBQAfAD4HAA==.Grummel:BAECLgAFFH8NAAITAAMJACLQHwANAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgATAAMJACLQHwANAQNoDAAABwBbAGkMAAACAE8A6gwAAAQAWgAuAAQKfycAAxMACQk8IH8JAPkCABMACQk8IH8JAPkCACAAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAIeAAMJSxTwNADVAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgAeAAMJSxTwNADVAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJNAAJAH0gAA==.',
Hr='Hrtenjoyer:BAEBLgAECn8aAAIYAAkJFx69BgDWAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAADAFkAbwwAAAIAHQAYAAkJFx69BgDWAgloDAAABABfAGkMAAADAEgAawwAAAMATQBqDAAABABaAGwMAAAEAE8AbQwAAAEAUgDqDAAAAgBaAG4MAAADAFkAbwwAAAIAHQABLgAFFAUJDQAQAMIcAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAYJJgAQAJMkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.Ilnarya:BAEALgAECgEJAQABLgAECgkJHgAVALIRAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIfAAkJWhaDDQAEAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAfAAkJWhaDDQAEAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAIVAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAFQAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACFQAHCaElBx4AVAIAFQAHCaElBx4AVAIAAS4ABRQICRsABwBFDQA=.',
Ja='Jail:BAEBLgAECn8oAAMhAAkJJCJOAAAuAwloDAAABwBhAGkMAAAFAF4AawwAAAYARwBqDAAABABcAGwMAAAEAF8AbQwAAAMAUgDqDAAABQBgAG4MAAAEAGIAbwwAAAIAPgAhAAkJJCJOAAAuAwloDAAABQBhAGkMAAAEAF4AawwAAAQARwBqDAAAAwBcAGwMAAADAF8AbQwAAAIAUgDqDAAAAwBgAG4MAAACAGIAbwwAAAEAPgAEAAkJbRUwOgApAgloDAAAAgA4AGkMAAABADwAawwAAAIAMQBqDAAAAQBEAGwMAAABACMAbQwAAAEAMwDqDAAAAgBMAG4MAAACAEAAbwwAAAEALQAAAA==.',
Ka='Katestinks:BAECLgAFFH8NAAMQAAUJwhx1MgCCAQVoDAAAAwBZAGkMAAADAFkAawwAAAIAEgBqDAAAAQAJAOoMAAAEAGEAEAAECcIcdTIAggEEaAwAAAMAWQBpDAAAAwBZAGsMAAACABIA6gwAAAQAYQAdAAEJAACZWwAAAAFqDAAAAQAJAC4ABAp/KwADEAAJCdAjmAUASAMAEAAJCdAjmAUASAMAHQABCbYKVloAKgAAAAA=.',
Ke='Kelandrea:BAECLgAFFH8IAAIFAAMJ2w/mYwDUAANoDAAAAwAWAGkMAAABAD0A6gwAAAQAJgAFAAMJ2w/mYwDUAANoDAAAAwAWAGkMAAABAD0A6gwAAAQAJgAuAAQKfx8ABAUACQmrG9giAJ4CAAUACQmrG9giAJ4CABEAAgnSEPeBAHAAACIAAgkzF3tGAD8AAAAA.',
Ki='Kirkh:BAEALgAECgcJDAABLgAECgkJJgAbAEobAA==.Kirkpriest:BAEBLgAECn8mAAIbAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAbAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECggJJQAjAGQfAA==.',
Kr='Kregazi:BAECLgAFFH8MAAIdAAQJYhhjFgAeAQRoDAAABAA7AGkMAAAEAEMAawwAAAEAXADqDAAAAwAdAB0ABAliGGMWAB4BBGgMAAAEADsAaQwAAAQAQwBrDAAAAQBcAOoMAAADAB0ALgAECn84AAIdAAkJyCLDBADdAgAdAAkJyCLDBADdAgAAAA==.',
Ky='Kyriste:BAEBLgAECn8aAAIZAAcJZiH0DQB4AgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAwBVAGwMAAADAEAA6gwAAAQAWwBuDAAAAgBXABkABwlmIfQNAHgCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAADAFUAbAwAAAMAQADqDAAABABbAG4MAAACAFcAAS4ABRQFCR8AEwD5IQA=.',
La='Larissaqt:BAECLgAFFH8jAAIbAAcJthV1BgDuAQdoDAAABwBTAGkMAAAGAEoAawwAAAcAHQBqDAAABgAgAGwMAAACADEA6gwAAAUAUABuDAAAAgAPABsABwm2FXUGAO4BB2gMAAAHAFMAaQwAAAYASgBrDAAABwAdAGoMAAAGACAAbAwAAAIAMQDqDAAABQBQAG4MAAACAA8ALgAECn8yAAIbAAkJDiOYAgA9AwAbAAkJDiOYAgA9AwAAAA==.',
Li='Lilylock:BAEALgAECgEJAQABLgAECgkJHQAUABcdAA==.Lilyweave:BAEBLgAECn8dAAQUAAkJFx1oEwBPAgloDAAAAwBLAGkMAAAEAFcAawwAAAQAVwBqDAAABQBiAGwMAAAEAFEAbQwAAAMAPQDqDAAAAgBaAG4MAAADAD4AbwwAAAEAMQAUAAkJFx1oEwBPAgloDAAAAgBLAGkMAAADAFcAawwAAAQAVwBqDAAABQBiAGwMAAADAFEAbQwAAAMAPQDqDAAAAgBaAG4MAAADAD4AbwwAAAEAMQAkAAIJDQ88PQBjAAJoDAAAAQAYAGkMAAABADQAHwABCTcMwkIAMwABbAwAAAEAHwAAAA==.Lioshi:BAEALgAECgYJDAABLgAFFAQJEwAEAOEbAA==.',
Ma='Maildaddy:BAECLgAFFH8bAAIHAAgJRQ3MCQDwAQhoDAAABQAwAGkMAAAFAEMAawwAAAUALQBqDAAAAwAmAGwMAAABAAoAbQwAAAEACADqDAAABgAxAG4MAAABAAQABwAICUUNzAkA8AEIaAwAAAUAMABpDAAABQBDAGsMAAAFAC0AagwAAAMAJgBsDAAAAQAKAG0MAAABAAgA6gwAAAYAMQBuDAAAAQAEAC4ABAp/JAAEBwAICYkcjgkARAIABwAHCSUgjgkARAIAAgAFCSgRKjcAGwEACAADCRwc3ycA4gAAAAA=.Maxxy:BAEBLgAECn8cAAIeAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAeAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8PAAMZAAQJyhotEAA4AQRoDAAABABFAGkMAAAEADgAawwAAAMAPADqDAAABABXABkABAnKGi0QADgBBGgMAAAEAEUAaQwAAAMAOABrDAAAAwA8AOoMAAADAFcAGgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADGgAICc4ZmQwAbgIAGgAICc4ZmQwAbgIAGQAECSYMg1wAwQAAAS4ABRQICTQACQB9IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgcJFgAVAKYFAA==.Merarite:BAEALgAFFAIJAgAAAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEwAEAOEbAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8YAAIFAAUJuxh6LwBAAQVoDAAABgAzAGkMAAAFAD4AawwAAAQAOgBqDAAAAwAxAOoMAAAGAFEABQAFCbsYei8AQAEFaAwAAAYAMwBpDAAABQA+AGsMAAAEADoAagwAAAMAMQDqDAAABgBRAC4ABAp/SwACBQAJCc0hiwkAEwMABQAJCc0hiwkAEwMAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Nh='Nhylia:BAEBLgAFFH8FAAIFAAMJihQyVwDsAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQAFAAMJihQyVwDsAANoDAAAAgAtAGkMAAABAB4A6gwAAAIAUQABLgAFFAMJCAAFANsPAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAWAH8aAA==.Nixei:BAEBLgAECn8UAAIWAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYAFgAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAECLgAFFH8KAAIZAAQJeRvkDwA7AQRoDAAAAwBOAGkMAAADAFEAawwAAAIAOgDqDAAAAgA+ABkABAl5G+QPADsBBGgMAAADAE4AaQwAAAMAUQBrDAAAAgA6AOoMAAACAD4ALgAECn8eAAIZAAkJvSN0BAAzAwAZAAkJvSN0BAAzAwAAAA==.',
['Ní']='Nítedragon:BAEALgAECgEJAQABLgAECgcJFAAHAFAgAA==.',
Ow='Owlenjoyer:BAECLgAFFH8GAAIjAAMJRxU3KwDFAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAjAAMJRxU3KwDFAANoDAAAAwAiAGkMAAACADQA6gwAAAEATAAuAAQKfx8AAiMACQmGGkUMAIYCACMACQmGGkUMAIYCAAEuAAUUBQkNABAAwhwA.',
Pa='Palashin:BAEBLgAECn8UAAIRAAYJCR6DHQALAgZoDAAABABgAGkMAAAEAEwAawwAAAQAVABqDAAAAwBHAGwMAAABADAA6gwAAAQAUwARAAYJCR6DHQALAgZoDAAABABgAGkMAAAEAEwAawwAAAQAVABqDAAAAwBHAGwMAAABADAA6gwAAAQAUwABLgAECggJGAAJAFwfAA==.',
Pe='Personnelkid:BAEALgAECgcJDQABLgAECgkJPwAZAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIEAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUABAAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJDgABLgAFFAgJGwAHAEUNAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMPAAkJNhB3IACaAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAPAAkJ8Q53IACaAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAYAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAABLgAFFAIJAgABAAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEgANACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8fAAITAAUJ+SFqEQBrAQVoDAAACQBcAGkMAAAJAFUAawwAAAYASgBqDAAAAwBdAOoMAAAEAF4AEwAFCfkhahEAawEFaAwAAAkAXABpDAAACQBVAGsMAAAGAEoAagwAAAMAXQDqDAAABABeAC4ABAp/QQADEwAJCYglzgQA4QIAEwAJCVklzgQA4QIAIAACCZ0YIRUAqAAAAAA=.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJDQATAAAiAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
Se='Serenytey:BAEALgAECgcJDQAAAA==.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJGAAJAFwfAA==.Shinthyr:BAEBLgAECn8YAAIZAAcJ5R4eFQA0AgdoDAAABQBTAGkMAAAEAFUAawwAAAQAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABkABwnlHh4VADQCB2gMAAAFAFMAaQwAAAQAVQBrDAAABABdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICRgACQBcHwA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgcJDwABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAgABLgAECgcJDwABAAAAAA==.',
Ta='Tahune:BAEBLgAECn9WAAMeAAkJyCXNAADZAwloDAAADABdAGkMAAALAGIAawwAAAsAYgBqDAAACwBhAGwMAAAKAGIAbQwAAAgAYQDqDAAACwBhAG4MAAAHAFoAbwwAAAUAYQAeAAkJyCXNAADZAwloDAAACgBdAGkMAAALAGIAawwAAAkAYgBqDAAACwBhAGwMAAAKAGIAbQwAAAgAYQDqDAAACwBhAG4MAAAHAFoAbwwAAAUAYQAjAAIJhiEzWwCWAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAIPAAgJVhGtLABMAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYADwAICVYRrSwATAEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBQkWAB0A6CAA.',
Th='Therapygap:BAEBLgAECn8wAAQZAAgJHBNdJQCKAQhoDAAACABMAGkMAAAJADwAawwAAAUANwBqDAAABgAdAGwMAAAJADQAbQwAAAMALwDqDAAABwA8AG4MAAABAAgAGQAHCVcVXSUAigEHaAwAAAUATABpDAAABQA8AGsMAAAEADcAagwAAAUAHQBsDAAABwA0AG0MAAADAC8A6gwAAAYAPAAbAAYJKwpkVwCnAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAaAAEJfAOVfgAhAAFuDAAAAQAIAAEuAAQKCQk/ABkAgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAgJFwAXAKQaAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAgJGwAHAEUNAA==.',
Tw='Twomonk:BAEALgAFFAEJAQABLgAFFAIJBgAYAL4hAA==.',
Un='Unsown:BAEALgAECgUJBQABLgAFFAMJDgAOAEsdAA==.',
Us='Usurah:BAECLgAFFH8aAAIFAAgJvBRmCwDzAQhoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsAbQwAAAEACADqDAAABAA+AG4MAAABACoABQAICbwUZgsA8wEIaAwAAAYATgBpDAAABgBWAGsMAAADAEEAagwAAAMAPABsDAAAAgAbAG0MAAABAAgA6gwAAAQAPgBuDAAAAQAqAC4ABAp/KwADBQAJCYAixAkAQwMABQAJCYAixAkAQwMAIgAFCVgcSRoANwEAAAA=.',
Vi='Vindh:BAECLgAFFH8SAAMVAAUJugcWUgDlAAVoDAAABgAXAGkMAAAEABUAawwAAAMACABqDAAAAQAJAOoMAAAEABgAFQAFCboHFlIA5QAFaAwAAAYAFwBpDAAABAAVAGsMAAADAAgAagwAAAEACQDqDAAAAwAYAA0AAQkOBvIRACkAAeoMAAABAA8ALgAECn8oAAQVAAkJtxVdPQD/AQAVAAkJtxVdPQD/AQANAAIJOgMqLgA9AAAlAAEJAABafQAAAAAAAA==.',
Vy='Vyndraennis:BAEBLgAECn8eAAIVAAkJshEsQQC4AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAVAAkJshEsQQC4AQloDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAACADEAbwwAAAEAGQAAAA==.',
['Vî']='Vîtâl:BAEALgADCgMJAwABLgAFFAQJEAAXAFsdAA==.',
Ya='Yaav:BAEBLgAECn8XAAIQAAkJxhDJUwDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAQAAkJxhDJUwDAAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIKAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAKAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8lAAMjAAgJZB/ODQBwAghoDAAABgBTAGkMAAAGAFYAawwAAAUAUABqDAAABABLAGwMAAAGAFMAbQwAAAIASgDqDAAABgBUAG4MAAACAEYAIwAICWQfzg0AcAIIaAwAAAYAUwBpDAAABgBWAGsMAAAFAFAAagwAAAQASwBsDAAABQBTAG0MAAABAEoA6gwAAAUAVABuDAAAAgBGAB4AAwmYCQeXAHgAA2wMAAABACIAbQwAAAEAHQDqDAAAAQAJAAAA.',
Zh='Zhuröng:BAECLgAFFH8TAAIEAAQJ4RvwRQBNAQRoDAAABgBVAGkMAAAGAE4AawwAAAQAKgDqDAAAAwBPAAQABAnhG/BFAE0BBGgMAAAGAFUAaQwAAAYATgBrDAAABAAqAOoMAAADAE8ALgAECn8nAAIEAAkJrh/KTQBNAgAEAAkJrh/KTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8WAAIdAAUJ6CBxDwBnAQVoDAAABwBbAGkMAAAGAEQAawwAAAMAXQBqDAAAAQBMAOoMAAAFAFQAHQAFCeggcQ8AZwEFaAwAAAcAWwBpDAAABgBEAGsMAAADAF0AagwAAAEATADqDAAABQBUAC4ABAp/JQACHQAICY4haQQABQMAHQAICY4haQQABQMAAAA=.',
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

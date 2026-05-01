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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Druid-Restoration','Priest-Holy','Priest-Discipline','Druid-Balance','Paladin-Retribution','DeathKnight-Unholy',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-01',data={Ad='Advvy:BAEALgAECgQJCAAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8gAAICAAgJtx2SBQBQAghoDAAABgBSAGkMAAAFAFcAawwAAAUAUABqDAAAAwAnAGwMAAADAEIAbQwAAAIAOADqDAAABgBVAG4MAAACAEkAAgAICbcdkgUAUAIIaAwAAAYAUgBpDAAABQBXAGsMAAAFAFAAagwAAAMAJwBsDAAAAwBCAG0MAAACADgA6gwAAAYAVQBuDAAAAgBJAAAA.Algebra:BAECLgAFFH8FAAIDAAQJuRpIFwBnAQRoDAAAAgBRAGkMAAABAD0AawwAAAEAQgDqDAAAAQBAAAMABAm5GkgXAGcBBGgMAAACAFEAaQwAAAEAPQBrDAAAAQBCAOoMAAABAEAALgAECn8WAAIDAAgJmCNyBgDRAgADAAgJmCNyBgDRAgAAAA==.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgUJCgAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAYJFgAEAHYeAA==.',
Ay='Ayoade:BAECLgAFFH8IAAIFAAQJzRLnCgA8AQRoDAAAAgArAGkMAAACAD0AawwAAAIANADqDAAAAgAjAAUABAnNEucKADwBBGgMAAACACsAaQwAAAIAPQBrDAAAAgA0AOoMAAACACMALgAECn8YAAMFAAgJaRyaCgCMAgAFAAgJaRyaCgCMAgAGAAIJERXdMQCHAAAAAA==.',
Az='Azzurel:BAEBLgAECn8XAAMHAAgJKBEXLgB0AQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACIABwAICSgRFy4AdAEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAiAAgAAQkAADRyADMAAWoMAAABABQAAAA=.',
Bo='Bobbysan:BAECLgAFFH8aAAIJAAYJtRoFAwCqAQZoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACcA6gwAAAUASAAJAAYJtRoFAwCqAQZoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACcA6gwAAAUASAAuAAQKfyMAAgkACQlUHpoKAOACAAkACQlUHpoKAOACAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgQJCQAAAA==.',
De='Deathhunterz:BAEALgADCgkJFgAAAA==.Demagogué:BAEALgAFFAEJAQABLgAFFAYJDgAFAJ4QAA==.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJCQABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8GAAIKAAQJ0Bj6DQC/AARoDAAAAQBNAGkMAAABAFkAawwAAAIAKABsDAAAAgAuAAoABAnQGPoNAL8ABGgMAAABAE0AaQwAAAEAWQBrDAAAAgAoAGwMAAACAC4ALgAECn8XAAMKAAgJiyGaBgD0AgAKAAgJiyGaBgD0AgALAAEJgCYCMwBwAAABLgAFFAQJCAAFAM0SAA==.',
Eh='Ehanee:BAEALgAECgQJBgAAAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJAwABAAAAAA==.Evierari:BAEALgAFFAMJAwAAAA==.',
Fo='Fofer:BAEBLgAECn8ZAAIJAAYJuSVNCAANAgZoDAAABQBhAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAAJAAYJuSVNCAANAgZoDAAABQBhAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAABLgAECggJHQAMAD8lAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECgcJEwABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8LAAMNAAQJkRM6GQAOAQRoDAAABABDAGkMAAAEAFoAawwAAAEAFADqDAAAAgAWAA0ABAkKDToZAA4BBGgMAAACACEAaQwAAAMAOABrDAAAAQAUAOoMAAACABYADgACCbYenQIAowACaAwAAAIAQwBpDAAAAQBaAC4ABAp/IgADDgAICbMixAEA/AIADgAICbMixAEA/AIADQACCfoPbn4ASAAAAAA=.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJGgALAAMUAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJGgALAAMUAA==.Greatra:BAEALgADCgEJAQABLgAECgkJGgALAAMUAA==.Greatyulon:BAEBLgAECn8aAAQLAAYJAxSbMQBeAQZoDAAABgBEAGkMAAAFACoAawwAAAUALwBqDAAAAwAsAGwMAAADAC4A6gwAAAQAMgALAAYJShObMQBeAQZoDAAABABEAGkMAAAEACoAawwAAAQAJQBqDAAAAQAsAGwMAAABAC4A6gwAAAMAMgAJAAUJiw6hIQD2AAVoDAAAAQBCAGkMAAABAA4AawwAAAEALwBqDAAAAQAeAGwMAAABABQACgAECY8FnlcAcAAEaAwAAAEAFgBqDAAAAQATAGwMAAABAAEA6gwAAAEADQAAAA==.Grummel:BAECLgAFFH8FAAIPAAIJPB88EADOAAJoDAAABABbAGkMAAABAEQADwACCTwfPBAAzgACaAwAAAQAWwBpDAAAAQBEAC4ABAp/HwADDwAICf0hfgkA+QIADwAICf0hfgkA+QIAEAABCXAUah0AQAAAAAA=.',
Hb='Hbcarter:BAEALgADCgIJAgABLgAFFAQJCAAFAM0SAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEALgAECggJDgAAAA==.',
Iz='Izapotato:BAECLgAFFH8PAAINAAUJTRUdCQCXAQVoDAAAAwBUAGkMAAADABwAawwAAAMAJABqDAAAAgBDAOoMAAAEAEQADQAFCU0VHQkAlwEFaAwAAAMAVABpDAAAAwAcAGsMAAADACQAagwAAAIAQwDqDAAABABEAC4ABAp/GwACDQAHCX4loxgAwQIADQAHCX4loxgAwQIAAS4ABRQGCQ4ABQCeEAA=.',
Ke='Kelandrea:BAEALgAFFAEJAQAAAA==.',
Ki='Kirkh:BAEALgAECgcJCgABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht+BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht+BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgAAAA==.',
Kr='Kregazi:BAEBLgAECn8hAAIRAAgJZCAOAwArAghoDAAABgBXAGkMAAAFAFcAawwAAAUAXgBqDAAABQBZAGwMAAAEAGEAbQwAAAIATADqDAAABABSAG4MAAACADYAEQAICWQgDgMAKwIIaAwAAAYAVwBpDAAABQBXAGsMAAAFAF4AagwAAAUAWQBsDAAABABhAG0MAAACAEwA6gwAAAQAUgBuDAAAAgA2AAAA.',
La='Larissaqt:BAECLgAFFH8MAAIEAAUJ/gvLCAA1AQVoDAAAAwAoAGkMAAACACsAawwAAAMAEQBqDAAAAgAfAOoMAAACABUABAAFCf4LywgANQEFaAwAAAMAKABpDAAAAgArAGsMAAADABEAagwAAAIAHwDqDAAAAgAVAC4ABAp/GgACBAAICRMd5REAbAIABAAICRMd5REAbAIAAAA=.',
Li='Lioshi:BAEALgAECgMJAwABLgAFFAQJCAADANoWAA==.',
Ma='Maildaddy:BAECLgAFFH8OAAIFAAYJnhAjBAC0AQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAFAAYJnhAjBAC0AQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAuAAQKfxsABAUACAnnF3UOAFACAAUABwnZGnUOAFACAAIABQkoESU3ABsBAAYAAwkcHNknAOIAAAAA.Maxxy:BAEBLgAECn8VAAISAAgJph+iFgCBAghoDAAABABdAGkMAAADAFwAawwAAAMAXwBqDAAAAgA6AGwMAAACAEoAbQwAAAEARQDqDAAABABUAG4MAAACAE8AEgAICaYfohYAgQIIaAwAAAQAXQBpDAAAAwBcAGsMAAADAF8AagwAAAIAOgBsDAAAAgBKAG0MAAABAEUA6gwAAAQAVABuDAAAAgBPAAAA.',
Mc='Mckellen:BAECLgAFFH8HAAMTAAQJ9g3QBwAcAQRoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABMABAlaDdAHABwBBGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AFAACCREJ+RMAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADFAAICc4ZmgwAbgIAFAAICc4ZmgwAbgIAEwAECSYMdFwAwQAAAS4ABRQECQgABQDNEgA=.',
Mi='Minidruid:BAEALgAECgYJCgABLgAFFAMJBwADALgTAA==.',
Mo='Mordraius:BAEALgAECggJDAABLgAFFAQJCAADANoWAA==.',
My='Myceliums:BAEALgAECgQJBgAAAA==.',
Na='Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJDAABAAAAAA==.Nixei:BAEALgAECggJDAAAAA==.',
Ny='Nyriaa:BAEBLgAECn8eAAITAAkJvSNsAACAAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwATAAkJvSNsAACAAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgYJBgABAAAAAA==.',
Pe='Peepofloor:BAEALgADCgcJCwAAAA==.Personnelkid:BAEALgAECgEJAQABLgAECggJGwADAC0NAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJbw1yiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAlAG4MAAABAAUAAwAICW8NcogAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJQBuDAAAAQAFAAAA.',
Pu='Punchweagle:BAEBLgAECn8kAAMJAAkJaA7jEACIAQloDAAABgAyAGkMAAAFAEAAawwAAAYAOgBqDAAABAAoAGwMAAAEACUAbQwAAAMADADqDAAABAAwAG4MAAADAAsAbwwAAAEACgAJAAkJUgrjEACIAQloDAAAAgAbAGkMAAACACsAawwAAAIAJwBqDAAAAgAOAGwMAAACACUAbQwAAAMADADqDAAAAgAdAG4MAAADAAsAbwwAAAEACgALAAYJUxRBMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowfather:BAEALgAECggJCQAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJCQABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgQJAQAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAQJCwANAJETAA==.Rexpanda:BAEALgAECgQJBQABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJuBNfLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANQADAAMJuBNfLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANQAuAAQKfxkAAgMACAkUHLFDAG0CAAMACAkUHLFDAG0CAAAA.',
Sh='Shiins:BAEALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shinthyr:BAEALgAECgcJEwAAAA==.',
Si='Sizzlefox:BAEALgADCgQJBAABLgAECgUJCgABAAAAAA==.',
Ta='Tahune:BAEBLgAECn8pAAMSAAgJdyQ7AwAKAwhoDAAABwBYAGkMAAAGAGIAawwAAAYAXwBqDAAABgBcAGwMAAAFAF4AbQwAAAMAXADqDAAABgBhAG4MAAACAFcAEgAICXckOwMACgMIaAwAAAUAWABpDAAABgBiAGsMAAAEAF8AagwAAAYAXABsDAAABQBeAG0MAAADAFwA6gwAAAYAYQBuDAAAAgBXABUAAgmGIYIsAKwAAmgMAAACAFYAawwAAAIAVQAAAA==.Taso:BAEALgAECgcJDQABLgAFFAIJBQARAKAeAA==.',
Th='Therapygap:BAEBLgAECn8aAAMTAAYJ+BE8OQBWAQZoDAAABgBMAGkMAAAGACUAawwAAAIANQBqDAAAAwAdAGwMAAAFACIA6gwAAAQALAATAAYJ+BE8OQBWAQZoDAAAAwBMAGkMAAACACUAawwAAAEANQBqDAAAAgAdAGwMAAAEACIA6gwAAAMALAAEAAYJgAnBJwDBAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEwBqDAAAAQAIAGwMAAABACAA6gwAAAEACAABLgAECggJGwADAC0NAA==.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAUJEAAKAGAdAA==.Trèantdaddy:BAEALgAECgIJAwABLgAFFAYJDgAFAJ4QAA==.',
Us='Usurah:BAECLgAFFH8PAAIWAAUJwBkRCgBcAQVoDAAABABOAGkMAAAEAEEAawwAAAIAQgBqDAAAAgA8AOoMAAADADUAFgAFCcAZEQoAXAEFaAwAAAQATgBpDAAABABBAGsMAAACAEIAagwAAAIAPADqDAAAAwA1AC4ABAp/JgACFgAJCX4iwgkAQwMAFgAJCX4iwgkAQwMAAAA=.',
Vi='Vindh:BAECLgAFFH8IAAMNAAQJhgeNHQD0AARoDAAAAwAXAGkMAAACABUAawwAAAEABgDqDAAAAgAZAA0ABAmGB40dAPQABGgMAAADABcAaQwAAAIAFQBrDAAAAQAGAOoMAAABABkADgABCQ4GgwYAOQAB6gwAAAEADwAuAAQKfyIAAw0ACAkfF1s9AP8BAA0ACAkfF1s9AP8BAA4AAQlTAx8aACkAAAAA.',
Vy='Vyndraennis:BAEBLgAECn8XAAINAAcJpRDoKQA+AQdoDAAABAAiAGkMAAAEAC0AawwAAAQAMQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABAA1AA0ABwmlEOgpAD4BB2gMAAAEACIAaQwAAAQALQBrDAAABAAxAGoMAAADADIAbAwAAAMAHABtDAAAAQAtAOoMAAAEADUAAAA=.',
Ya='Yaav:BAEBLgAECn8UAAIXAAcJQhKcMQBzAQdoDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0ABcABwlCEpwxAHMBB2gMAAAEADYAaQwAAAQAOgBrDAAAAwAmAGoMAAADAEsAbAwAAAMAIwBtDAAAAQAoAOoMAAACADQAAAA=.',
Yu='Yufia:BAEBLgAECn8ZAAIHAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAHAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEALgAECgQJBwABLgAECgYJCgABAAAAAA==.',
Zh='Zhuröng:BAECLgAFFH8IAAIDAAQJ2hYWIwBIAQRoDAAAAwBJAGkMAAADAE4AawwAAAEAAwDqDAAAAQBPAAMABAnaFhYjAEgBBGgMAAADAEkAaQwAAAMATgBrDAAAAQADAOoMAAABAE8ALgAECn8dAAIDAAgJRiDQTQBNAgADAAgJRiDQTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8FAAIRAAIJoB5nDgC7AAJoDAAAAwBYAGkMAAACAEQAEQACCaAeZw4AuwACaAwAAAMAWABpDAAAAgBEAC4ABAp/IwACEQAICY4haAQABQMAEQAICY4haAQABQMAAAA=.',
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

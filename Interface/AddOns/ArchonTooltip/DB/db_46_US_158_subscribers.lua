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

local lookup = {'Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Unknown-Unknown','Monk-Mistweaver','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-04-28',data={Ad='Advvy:BAEALgAECgQJCAAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Al='Alcean:BAEBLgAECn8YAAIBAAgJpxeUHADiAQhoDAAABQBKAGkMAAAEAEkAawwAAAQAPABqDAAAAgAnAGwMAAACACMAbQwAAAEAFQDqDAAABQBVAG4MAAABAEkAAQAICacXlBwA4gEIaAwAAAUASgBpDAAABABJAGsMAAAEADwAagwAAAIAJwBsDAAAAgAjAG0MAAABABUA6gwAAAUAVQBuDAAAAQBJAAAA.Algebra:BAECLgAFFH8FAAICAAQJuRq4DQBtAQRoDAAAAgBRAGkMAAABAD0AawwAAAEAQgDqDAAAAQBAAAIABAm5GrgNAG0BBGgMAAACAFEAaQwAAAEAPQBrDAAAAQBCAOoMAAABAEAALgAECn8VAAICAAgJgiMEBADcAgACAAgJgiMEBADcAgAAAA==.Aléyna:BAEALgAECgEJAQAAAA==.',
Ar='Arteron:BAEALgAFFAIJAwABLgAFFAYJFgADAHYeAA==.',
Ay='Ayoade:BAECLgAFFH8IAAIEAAQJzRJsCAAoAQRoDAAAAgArAGkMAAACAD0AawwAAAIANADqDAAAAgAjAAQABAnNEmwIACgBBGgMAAACACsAaQwAAAIAPQBrDAAAAgA0AOoMAAACACMALgAECn8YAAMEAAgJaRyTCgCMAgAEAAgJaRyTCgCMAgAFAAIJERXVMQCHAAAAAA==.',
Az='Azzurel:BAEBLgAECn8XAAMGAAgJKBFVIwBxAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACIABgAICSgRVSMAcQEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAiAAcAAQkAAC9yADMAAWoMAAABABQAAAA=.',
Bo='Bobbysan:BAECLgAFFH8UAAIIAAYJ6hjVAgCWAQZoDAAABQBQAGkMAAAEAEwAawwAAAMASQBqDAAAAwArAGwMAAABACcA6gwAAAQAMQAIAAYJ6hjVAgCWAQZoDAAABQBQAGkMAAAEAEwAawwAAAMASQBqDAAAAwArAGwMAAABACcA6gwAAAQAMQAuAAQKfyMAAggACQlUHpgKAOACAAgACQlUHpgKAOACAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgQJCQAAAA==.',
De='Deathhunterz:BAEALgADCgkJFgAAAA==.Demagogué:BAEALgAECgQJBQABLgAFFAYJDgAEAJ4QAA==.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJCAABLgAECgcJBwAJAAAAAA==.',
Du='Dubsii:BAEBLgAECn8VAAIKAAgJiyGWBgD1AghoDAAAAwBWAGkMAAADAFEAawwAAAIAWwBqDAAAAwBTAGwMAAACAFEAbQwAAAIASgDqDAAABABhAG4MAAACAFkACgAICYshlgYA9QIIaAwAAAMAVgBpDAAAAwBRAGsMAAACAFsAagwAAAMAUwBsDAAAAgBRAG0MAAACAEoA6gwAAAQAYQBuDAAAAgBZAAEuAAUUBAkIAAQAzRIA.',
Eh='Ehanee:BAEALgAECgQJBgAAAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJAwAJAAAAAA==.Evierari:BAEALgAFFAMJAwAAAA==.',
Fo='Fofer:BAEBLgAECn8ZAAIIAAYJuSXtBQASAgZoDAAABQBhAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAAIAAYJuSXtBQASAgZoDAAABQBhAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAABLgAECggJHQALAD8lAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECgcJEwAJAAAAAA==.',
Fu='Funkey:BAECLgAFFH8JAAMMAAMJKxcrGQD6AANoDAAABABDAGkMAAAEAFoA6gwAAAEAFAAMAAMJARErGQD6AANoDAAAAgA1AGkMAAADADgA6gwAAAEAFAANAAIJth6dAgCjAAJoDAAAAgBDAGkMAAABAFoALgAECn8hAAMNAAgJsyLDAQD8AgANAAgJsyLDAQD8AgAMAAIJCw3cxwBpAAAAAA==.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJGgAIAAMUAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJGgAIAAMUAA==.Greatra:BAEALgADCgEJAQABLgAECgkJGgAIAAMUAA==.Greatyulon:BAEBLgAECn8aAAQIAAYJAxTSGgD6AAZoDAAABgBEAGkMAAAFACoAawwAAAUALwBqDAAAAwAsAGwMAAADAC4A6gwAAAQAMgAOAAYJShOWMQBeAQZoDAAABABEAGkMAAAEACoAawwAAAQAJQBqDAAAAQAsAGwMAAABAC4A6gwAAAMAMgAIAAUJiw7SGgD6AAVoDAAAAQBCAGkMAAABAA4AawwAAAEALwBqDAAAAQAeAGwMAAABABQACgAECY8FgFcAcgAEaAwAAAEAFgBqDAAAAQATAGwMAAABAAEA6gwAAAEADQAAAA==.Grummel:BAECLgAFFH8FAAIPAAIJPB83EADOAAJoDAAABABbAGkMAAABAEQADwACCTwfNxAAzgACaAwAAAQAWwBpDAAAAQBEAC4ABAp/HwADDwAICf0hegkA+QIADwAICf0hegkA+QIAEAABCXAUaB0AQAAAAAA=.',
Hb='Hbcarter:BAEALgADCgIJAgABLgAFFAQJCAAEAM0SAA==.',
Il='Illiyania:BAEALgADCgcJDQAAAA==.',
Im='Imquitelarge:BAEALgAECggJCAAAAA==.',
Iz='Izapotato:BAECLgAFFH8NAAIMAAUJhhV6CABlAQVoDAAAAwBWAGkMAAADABwAawwAAAIAJABqDAAAAQBDAOoMAAAEAEQADAAFCYYVeggAZQEFaAwAAAMAVgBpDAAAAwAcAGsMAAACACQAagwAAAEAQwDqDAAABABEAC4ABAp/HgACDAAHCX4loBgAwQIADAAHCX4loBgAwQIAAS4ABRQGCQ4ABACeEAA=.',
Ke='Kelandrea:BAEALgAECgkJEgAAAA==.',
Ki='Kirkh:BAEALgAECgcJCgABLgAECgkJJgADAEobAA==.Kirkpriest:BAEBLgAECn8mAAIDAAkJSht7BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQADAAkJSht7BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.',
Kr='Kregazi:BAEBLgAECn8hAAIRAAgJZCDtAQB4AghoDAAABgBXAGkMAAAFAFcAawwAAAUAXgBqDAAABQBZAGwMAAAEAGEAbQwAAAIATADqDAAABABSAG4MAAACADYAEQAICWQg7QEAeAIIaAwAAAYAVwBpDAAABQBXAGsMAAAFAF4AagwAAAUAWQBsDAAABABhAG0MAAACAEwA6gwAAAQAUgBuDAAAAgA2AAAA.',
La='Larissaqt:BAECLgAFFH8IAAIDAAUJeAVMCQApAQVoDAAAAgAFAGkMAAABAA4AawwAAAIADwBqDAAAAQAfAOoMAAACABUAAwAFCXgFTAkAKQEFaAwAAAIABQBpDAAAAQAOAGsMAAACAA8AagwAAAEAHwDqDAAAAgAVAC4ABAp/GgACAwAICRMd5BEAbAIAAwAICRMd5BEAbAIAAAA=.',
Li='Lioshi:BAEALgAECgMJAwABLgAECggJHAACAGQhAA==.',
Ma='Maildaddy:BAECLgAFFH8OAAIEAAYJnhCmAgC6AQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAEAAYJnhCmAgC6AQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAuAAQKfxsABAQACAnnF3EOAFACAAQABwnZGnEOAFACAAEABQkoER83ABsBAAUAAwkcHNInAOIAAAAA.Maxxy:BAEALgAECggJEwAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMSAAQJ9g2LBQAeAQRoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABIABAlaDYsFAB4BBGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AEwACCREJ+xMAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADEwAICc4ZlwwAbwIAEwAICc4ZlwwAbwIAEgAECSYMcFwAwQAAAS4ABRQECQgABADNEgA=.',
Mi='Minidruid:BAEALgAECgQJBAABLgAFFAMJBwACALgTAA==.',
Mo='Mordraius:BAEALgAECggJCwABLgAECggJHAACAGQhAA==.',
My='Myceliums:BAEALgAECgQJBgAAAA==.',
Na='Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJDAAJAAAAAA==.Nixei:BAEALgAECggJDAAAAA==.',
Ny='Nyriaa:BAEBLgAECn8cAAISAAgJTiTPAAAtAwhoDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAABAFMAEgAICU4kzwAALQMIaAwAAAUAYwBpDAAABQBiAGsMAAAFAFsAagwAAAMAXwBsDAAAAwBeAG0MAAABAFEA6gwAAAUAYwBuDAAAAQBTAAAA.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgYJBgAJAAAAAA==.',
Pe='Peepofloor:BAEALgADCgcJCwAAAA==.Personnelkid:BAEALgAECgEJAQABLgAECgcJHAADAJkPAA==.',
Ph='Pheiro:BAEBLgAECn8ZAAICAAgJaw1siADBAQhoDAAABABSAGkMAAAEAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABAAlAG4MAAABAAUAAgAICWsNbIgAwQEIaAwAAAQAUgBpDAAABAAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAQAJQBuDAAAAQAFAAAA.',
Pu='Punchweagle:BAEBLgAECn8iAAMIAAgJ3Q/yEABYAQhoDAAABgAyAGkMAAAFAEAAawwAAAYAOgBqDAAABAAoAGwMAAAEACUAbQwAAAMADADqDAAABAAwAG4MAAACAAsADgAGCVMUPDIAWwEGaAwAAAQAMgBpDAAAAwBAAGsMAAAEADoAagwAAAIAKABsDAAAAgAlAOoMAAACADAACAAICTEL8hAAWAEIaAwAAAIAGwBpDAAAAgArAGsMAAACACcAagwAAAIADgBsDAAAAgAlAG0MAAADAAwA6gwAAAIAHQBuDAAAAgALAAAA.',
Qr='Qrowfather:BAEALgAECgcJBwAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECgcJBwAJAAAAAA==.',
Ra='Raveglaive:BAEALgAECgQJAQAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAMJCQAMACsXAA==.Rexpanda:BAEALgAECgQJBQABLgAECgUJBQAJAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQAJAAAAAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAICAAMJuBOOJwD+AANoDAAAAwA/AGkMAAACACMA6gwAAAIANQACAAMJuBOOJwD+AANoDAAAAwA/AGkMAAACACMA6gwAAAIANQAuAAQKfxkAAgIACAkUHKhDAG0CAAIACAkUHKhDAG0CAAAA.',
Sa='Saven:BAEBLgAECn8aAAMUAAkJtiURBwD6AgloDAAABABiAGkMAAAEAGMAawwAAAQAYwBqDAAAAwBhAGwMAAADAGEAbQwAAAEAUwDqDAAABABiAG4MAAACAGMAbwwAAAEAXwAUAAgJwyURBwD6AghoDAAABABiAGkMAAAEAGMAawwAAAQAYwBqDAAAAwBhAGwMAAADAGEAbQwAAAEAUwDqDAAABABiAG4MAAACAGMAFQABCdoXt44AVwABbwwAAAEAPQAAAA==.Savont:BAECLgAFFH8JAAIEAAQJqCCaBQBnAQRoDAAAAwBJAGkMAAADAFAAawwAAAIAWADqDAAAAQBbAAQABAmoIJoFAGcBBGgMAAADAEkAaQwAAAMAUABrDAAAAgBYAOoMAAABAFsALgAECn8cAAMEAAkJ0yNsAgBMAwAEAAkJ0yNsAgBMAwABAAMJkxirHADoAAABLgAECgkJGgAUALYlAA==.',
Se='Serenytey:BAEALgAECgYJCwAAAA==.',
Sh='Shiins:BAEALgADCgMJAwABLgAECgcJEwAJAAAAAA==.Shinthyr:BAEALgAECgcJEwAAAA==.',
Ta='Tahune:BAEBLgAECn8hAAMWAAgJECNtFQCLAghoDAAABgBYAGkMAAAFAFYAawwAAAUAVABqDAAABQBcAGwMAAAEAF4AbQwAAAIAXADqDAAABQBcAG4MAAABAFcAFgAICRAjbRUAiwIIaAwAAAQAWABpDAAABQBWAGsMAAADAFQAagwAAAUAXABsDAAABABeAG0MAAACAFwA6gwAAAUAXABuDAAAAQBXABcAAgmGIRQkALAAAmgMAAACAFYAawwAAAIAVQAAAA==.Taso:BAEALgAECgcJDQABLgAFFAIJBQARAKAeAA==.',
Th='Therapygap:BAEBLgAECn8aAAMSAAYJ+BE6OQBWAQZoDAAABgBMAGkMAAAGACUAawwAAAIANQBqDAAAAwAdAGwMAAAFACIA6gwAAAQALAASAAYJ+BE6OQBWAQZoDAAAAwBMAGkMAAACACUAawwAAAEANQBqDAAAAgAdAGwMAAAEACIA6gwAAAMALAADAAYJgAm5IgC6AAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEwBqDAAAAQAIAGwMAAABACAA6gwAAAEACAABLgAECgcJHAADAJkPAA==.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAUJDwAKAGAdAA==.Trèantdaddy:BAEALgAECgIJAgABLgAFFAYJDgAEAJ4QAA==.',
Us='Usurah:BAECLgAFFH8NAAIVAAUJwBkMCgBcAQVoDAAAAwBOAGkMAAAEAEEAawwAAAIAQgBqDAAAAQA8AOoMAAADADUAFQAFCcAZDAoAXAEFaAwAAAMATgBpDAAABABBAGsMAAACAEIAagwAAAEAPADqDAAAAwA1AC4ABAp/JgACFQAJCX4ivgkAQwMAFQAJCX4ivgkAQwMAAAA=.',
Vi='Vindh:BAECLgAFFH8GAAMMAAMJ6QdxLACSAANoDAAAAwAXAGkMAAACABUA6gwAAAEADwAMAAIJ1whxLACSAAJoDAAAAwAXAGkMAAACABUADQABCQ4GGgUAOQAB6gwAAAEADwAuAAQKfyMAAwwACAkfF1Q9AP8BAAwACAkfF1Q9AP8BAA0AAQlTA0cVACkAAAAA.',
Vy='Vyndraennis:BAEALgAECgYJEAAAAA==.',
Ya='Yaav:BAEALgAECgYJDQAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIGAAkJXR5BCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAGAAkJXR5BCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEALgAECgQJBwAAAA==.',
Zh='Zhuröng:BAEBLgAECn8cAAICAAcJZCHHTQBNAgdoDAAABQBeAGkMAAAEAFcAawwAAAQAWgBqDAAABABQAGwMAAAEAF4AbQwAAAIANQDqDAAABQBcAAIABwlkIcdNAE0CB2gMAAAFAF4AaQwAAAQAVwBrDAAABABaAGoMAAAEAFAAbAwAAAQAXgBtDAAAAgA1AOoMAAAFAFwAAAA=.',
Zo='Zomb:BAECLgAFFH8FAAIRAAIJoB4jCwC8AAJoDAAAAwBYAGkMAAACAEQAEQACCaAeIwsAvAACaAwAAAMAWABpDAAAAgBEAC4ABAp/IwACEQAICY4hZgQABQMAEQAICY4hZgQABQMAAAA=.',
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

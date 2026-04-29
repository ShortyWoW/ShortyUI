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

local lookup = {'Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','DemonHunter-Havoc','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','Paladin-Protection','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement','Monk-Windwalker','DemonHunter-Devourer','Priest-Discipline','DeathKnight-Unholy','Druid-Guardian','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abeblinkin:BAABLgAECn8oAAIBAAkJ9x8QAgDGAgABAAkJ9x8QAgDGAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8gAAICAAkJNhw8JwCJAgACAAkJNhw8JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn8pAAICAAkJohDTCQDvAQACAAkJohDTCQDvAQAAAA==.',
Aj='Ajm:BAAALgAECgMJAwAAAA==.',
Ak='Akeno:BAABLgAECn8VAAIDAAgJQCNZAQAYAwADAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEQAAAA==.Akime:BAAALgAECgQJCgAAAA==.Akudama:BAAALgAECgUJCQABLgAFFAQJCgAEAPAaAA==.',
Al='Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJBAAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgUJCQAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgEJAQAAAA==.Annisseda:BAACLgAFFH8FAAIFAAMJoRGPBgD5AAAFAAMJoRGPBgD5AAAuAAQKfyAAAgUACAkGIzwJABkDAAUACAkGIzwJABkDAAAA.',
Ar='Arrhythmia:BAAALgAECgUJCQABLgAFFAQJCAAGAAAAAQ==.Articuno:BAAALgAECgMJAwAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgMJAwAAAA==.',
Az='Azzy:BAACLgAFFH8NAAIFAAQJ7hq4AQBtAQAFAAQJ7hq4AQBtAQAuAAQKfysAAgUACQkVI34CAJMDAAUACQkVI34CAJMDAAAA.',
Ba='Babyboomie:BAAALgAECgEJAQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8XAAIHAAgJJBN7BACSAQAHAAgJJBN7BACSAQAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAAALgAECgUJDQAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8YAAIIAAgJaRCTOADMAQAIAAgJaRCTOADMAQAAAA==.',
Be='Beeflocks:BAAALgAECgYJEgAAAA==.Bekarn:BAABLgAECn8YAAMJAAcJeAooUwA5AQAJAAcJeAooUwA5AQAKAAMJ6ghfegBaAAAAAA==.Bennafflock:BAAALgAECgIJAwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJFwALALcbAA==.Bigxthaplug:BAAALgAECgQJBwAAAA==.Bilboswagins:BAAALgAECgcJEwAAAA==.Billski:BAAALgAECgcJBQAAAA==.Billyspike:BAABLgAECn8XAAIMAAYJyxrdDQDVAQAMAAYJyxrdDQDVAQAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgYJFwAMAMsaAA==.Billyspikepd:BAAALgADCgMJAwABLgAECgYJFwAMAMsaAA==.Billyspikepr:BAAALgAECgIJAgABLgAECgYJFwAMAMsaAA==.',
Bl='Blammo:BAAALgADCgYJCAAAAA==.Blobcat:BAAALgADCggJCAAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8GAAICAAQJGxIrCQADAQACAAQJGxIrCQADAQAuAAQKfx4AAgIABwmTIXIdALoCAAIABwmTIXIdALoCAAAA.Bloodhase:BAAALgAECgcJDQAAAA==.Bluecard:BAABLgAECn8kAAQEAAgJKh/2HgCeAgAEAAgJtB72HgCeAgANAAMJ1RjHOQDNAAAOAAEJFyGMJwBTAAAAAA==.',
Bo='Bokunh:BAAALgAECgYJDAAAAA==.Boomywhoomy:BAAALgADCgEJAQAAAA==.Bothenheim:BAACLgAFFH8FAAICAAMJrh4hBwAbAQACAAMJrh4hBwAbAQAuAAQKfx4AAgIACAkhIcQaAMkCAAIACAkhIcQaAMkCAAAA.',
Br='Brewsimmons:BAABLgAFFH8HAAIPAAYJ9gi+AgBzAQAPAAYJ9gi+AgBzAQAAAA==.Brüisér:BAABLgAECn8bAAIQAAgJzg0OBgA0AQAQAAgJzg0OBgA0AQAAAA==.',
Ca='Callamsvoid:BAAALgADCgEJAQAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Carathea:BAABLgAECn8WAAIRAAcJFCCGDACLAgARAAcJFCCGDACLAgAAAA==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgADCgcJCwAAAA==.Caylen:BAACLgAFFH8FAAISAAMJ3A3BCADVAAASAAMJ3A3BCADVAAAuAAQKfyAAAhIACAm3HkYRAK0CABIACAm3HkYRAK0CAAAA.Caytheles:BAABLgAECn8gAAMEAAkJTB+oBQBiAwAEAAkJTB+oBQBiAwANAAIJCwMSVQBvAAAAAA==.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8MAAIBAAUJlxraCgDHAQABAAUJlxraCgDHAQAuAAQKfxoAAgEACAniJBEaAA8DAAEACAniJBEaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAAALgAECgQJBQAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgADCgUJCAAAAA==.',
Cl='Cleverlev:BAAALgAECgYJBwABLgAECgYJBgAGAAAAAA==.',
Co='Colivism:BAABLgAECn8YAAIBAAcJSRSyeQDeAQABAAcJSRSyeQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECgcJFgARABQgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgADCgcJDQABLgAECgYJBgAGAAAAAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgADCggJFwAAAA==.',
Da='Daedrenda:BAAALgADCgQJBAAAAA==.Daeland:BAAALgAECgYJDQAAAA==.',
De='Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAAALgAECgYJEQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8GAAIIAAQJCx4mAgBuAQAIAAQJCx4mAgBuAQAuAAQKfyAAAwgACQlWIuYSAKACAAgACAk4HuYSAKACABMABglxIEooAOQBAAAA.Demonpunter:BAAALgAECgYJDwAAAA==.Dewussi:BAABLgAECn8eAAMCAAcJ3B2UCwDZAQAQAAcJOBmADQDvAQACAAcJYRuUCwDZAQAAAA==.',
Di='Dinoscarr:BAAALgAECgIJAwAAAA==.',
Dj='Djholy:BAAALgAECgQJBAAAAA==.',
Do='Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAAALgAECgUJCQABLgAECggJFAATABIbAA==.',
Dr='Drscholar:BAAALgADCgUJBwAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Dungorogue:BAAALgAFFAIJAgAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8hAAMRAAgJbQv6OABXAQARAAgJbQv6OABXAQAUAAUJxwQrSQC5AAAAAA==.Elivoker:BAAALgADCgkJCQAAAA==.Elmdor:BAAALgADCgkJEAAAAA==.Elyndra:BAAALgADCgYJBgAAAA==.',
En='Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.',
Ex='Excentric:BAAALgAECggJEwABLgAFFAUJDAABAJcaAA==.Excerpt:BAAALgAECgMJAwABLgAFFAUJDAABAJcaAA==.',
Fa='Farëeya:BAAALgADCgcJCwAAAA==.Fayne:BAAALgADCgUJCgAAAA==.',
Fe='Fernsama:BAAALgADCgQJBAABLgADCgYJCgAGAAAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAAALgAECgQJBAAAAA==.',
Fr='Froackie:BAAALgAECgYJDgAAAA==.Fruto:BAABLgAECn8aAAIVAAgJWBJlBwCFAQAVAAgJWBJlBwCFAQAAAA==.',
Ga='Garzislao:BAAALgAECgQJBgAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAABLgAECn8gAAIFAAkJ/SCkBABfAwAFAAkJ/SCkBABfAwAAAA==.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIJAAUJlQiLBQBzAQAJAAUJlQiLBQBzAQAuAAQKfxcAAgkACAlLFqskAAMCAAkACAlLFqskAAMCAAEuAAUUBgkHAA8A9ggA.Goku:BAAALgAECgQJBAAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAYJBwAPAPYIAA==.Grence:BAAALgAECgUJDAABLgAECgcJEgAGAAAAAA==.Grimreaper:BAAALgAECgMJCAAAAA==.Groldin:BAAALgAECgQJBAAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.',
['Gõ']='Gõtchoo:BAAALgADCgMJAwAAAA==.',
Ha='Hairball:BAAALgAECgYJDgAAAA==.Hallona:BAAALgADCgMJAwAAAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8oAAIIAAkJ6xvmDwC8AgAIAAkJ6xvmDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jacopo:BAAALgAECgYJDwAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8UAAIIAAgJ7BcwGgBrAgAIAAgJ7BcwGgBrAgAAAA==.',
Ka='Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEgAAAA==.Kanree:BAACLgAFFH8MAAIPAAQJUwYmCgAMAQAPAAQJUwYmCgAMAQAuAAQKfysAAg8ACQnGGUsLAJ0CAA8ACQnGGUsLAJ0CAAAA.Kartiri:BAACLgAFFH8FAAMWAAMJFgwpDgCUAAAWAAIJyAopDgCUAAAXAAIJMBWBCABjAAAuAAQKfx8ABBcACAldHlgGAN4CABcACAldHlgGAN4CABgABAkjFMUlAPUAABYAAwnuB/YTALsAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAAALgAECgYJDwAAAA==.Keicelinis:BAAALgAECgEJAgAAAA==.Keratos:BAAALgADCgIJAgAAAA==.',
Kh='Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Korxin:BAACLgAFFH8FAAIIAAQJ6BW6BwAJAQAIAAQJ6BW6BwAJAQAuAAQKfyIAAggACQkpI+wEAD8DAAgACQkpI+wEAD8DAAAA.',
Kr='Kreizikat:BAABLgAECn8fAAISAAgJUh44DgDIAgASAAgJUh44DgDIAgAAAA==.Krinn:BAAALgAECgUJBQAAAA==.',
Ku='Kurquaan:BAAALgAECgQJBAAAAA==.',
Le='Leilar:BAAALgAECgEJAQAAAA==.Levitticus:BAABLgAECn8fAAIZAAgJFBcWHgAmAgAZAAgJFBcWHgAmAgABLgAECgYJBgAGAAAAAA==.',
Li='Liale:BAAALgAECgEJAQAAAA==.',
Lo='Loinari:BAAALgAECgEJAgAAAA==.Lokano:BAAALgADCgIJAgAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAECgIJAgAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgIJBQAAAA==.Lull:BAAALgAECgUJCQAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEQAGAAAAAA==.Magidragon:BAAALgAECgMJBAAAAA==.Magoraga:BAAALgADCgYJBgAAAA==.',
Me='Melt:BAACLgAFFH8KAAIEAAQJ8BqtDQBuAQAEAAQJ8BqtDQBuAQAuAAQKfysAAwQACQmyIv4NAAkDAAQACQmyIv4NAAkDAA0ABAmoEngsAAwBAAAA.Metons:BAAALgAECgMJBAAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgADCgYJDAAAAA==.Mommon:BAAALgAECgIJAgAAAA==.Moonraisin:BAAALgADCgkJCwAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECgYJBgAAAA==.Naminé:BAAALgADCgMJAwAAAA==.Nattyrav:BAABLgAECn8nAAMaAAkJCR7AAwDuAgAaAAkJZR3AAwDuAgAKAAYJoBtYBwCRAQAAAA==.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn8eAAIbAAgJCxTGGwD+AQAbAAgJCxTGGwD+AQAAAA==.Neryssa:BAACLgAFFH8JAAIEAAQJix22DQBuAQAEAAQJix22DQBuAQAuAAQKfyoAAwQACQk5I+wIAOMBAAQACAknI+wIAOMBAA0ABAkMIfkYAIMBAAAA.',
Ni='Nipz:BAAALgADCgYJBgABLgAECgIJAgAGAAAAAA==.',
No='Nocter:BAABLgAECn8dAAQEAAkJuR1cNwAuAgAEAAcJgB1cNwAuAgAOAAUJUiCTCwCBAQANAAMJ9g3/PQC8AAAAAA==.Not:BAAALgADCgcJAgAAAA==.',
Ny='Nymura:BAAALgAECgIJAwAAAA==.',
['Nä']='Näesthra:BAABLgAECn8cAAIRAAgJXxOGIgDQAQARAAgJXxOGIgDQAQAAAA==.',
Oa='Oakhugger:BAAALgAECgcJEwAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8VAAIcAAYJhh1mQQDuAQAcAAYJhh1mQQDuAQAAAA==.',
Ol='Oldeone:BAAALgAECgIJAgAAAA==.',
Om='Omgega:BAABLgAECn8fAAICAAcJExkxTgD4AQACAAcJExkxTgD4AQAAAA==.',
On='Onimeek:BAABLgAECn8lAAMHAAkJZx73CADTAgAHAAkJZx73CADTAgAcAAMJkgbDPgBjAAAAAA==.',
Or='Oryn:BAAALgAECgUJCQABLgAECgkJDwAGAAAAAA==.Oryx:BAAALgADCgMJCQAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgUJCgAAAA==.Paper:BAAALgAFFAQJCAAAAQ==.',
Pe='Peacefullev:BAAALgAECgYJBgAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJCgAAAA==.',
Ph='Phantomthief:BAAALgAECgUJAQAAAA==.',
Pi='Pipeleto:BAAALgAECgYJDgAAAA==.',
Po='Poochimus:BAAALgAECgYJDAAAAA==.Pookong:BAAALgADCgMJAwAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECgUJBQAAAA==.Priestpwnz:BAAALgAECgUJCAAAAA==.Protomán:BAAALgAECgMJAwAAAA==.Proximity:BAAALgADCgMJBAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAQAAAA==.',
Re='Redeemedlev:BAACLgAFFH8LAAIdAAQJ2xMUBABJAQAdAAQJ2xMUBABJAQAuAAQKfyYAAh0ACAlvIcECACwCAB0ACAlvIcECACwCAAEuAAQKBgkGAAYAAAAA.Relax:BAABLgAECn8VAAIcAAYJ1x2vGAA7AQAcAAYJ1x2vGAA7AQAAAA==.',
Rh='Rhesand:BAAALgAECgYJCgAAAA==.Rhëa:BAAALgADCgUJBgAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8ZAAIbAAYJOxs6CABUAQAbAAYJOxs6CABUAQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8MAAIeAAQJeBaOBQBgAQAeAAQJeBaOBQBgAQAuAAQKfyoAAh4ACQkPIOgPAB4DAB4ACQkPIOgPAB4DAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAQJDAAeAHgWAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAABLgAECn8kAAIFAAgJ1x94EwCyAgAFAAgJ1x94EwCyAgAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAGAAAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgUJDAAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDQAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAAALgAECgcJEwAAAA==.Saero:BAAALgAECgMJBwAAAA==.Saluuknir:BAABLgAECn8aAAMWAAcJ6QZiDwD3AAAYAAYJaAeCIwAMAQAWAAcJ4gJiDwD3AAAAAA==.Sandfox:BAAALgAECgMJAwAAAA==.Saphh:BAAALgAECgcJDgABLgAECggJGwAPAMAZAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgUJBQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8FAAIfAAMJmhdeAQAAAQAfAAMJmhdeAQAAAQABLgAECggJFQADAEAjAA==.',
Si='Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.',
Sl='Slingshotz:BAABLgAECn8ZAAIgAAkJxBnDBgCQAgAgAAkJxBnDBgCQAgAAAA==.Slootbag:BAAALgAECgUJBQAAAA==.',
Sn='Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAABLgAECn8cAAICAAgJoCFyJQCRAgACAAgJoCFyJQCRAgAAAA==.',
So='Solari:BAAALgAECgcJDgAAAA==.Solvi:BAAALgAECgQJBQAAAA==.Sophispapa:BAABLgAECn8kAAICAAcJtxxxDgC1AQACAAcJtxxxDgC1AQAAAA==.Souprage:BAAALgAECgQJBQAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgAAAA==.Spywar:BAAALgADCgkJGAABLgAECggJFwAKADkUAA==.',
St='Starlighter:BAABLgAECn8bAAMUAAgJawxuNQA/AQAUAAcJAQluNQA/AQARAAYJGAVOEQDaAAAAAA==.',
Su='Supressor:BAAALgADCgQJCAAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8YAAIVAAYJKSQmAAASAgAVAAYJKSQmAAASAgAuAAQKfx0AAhUACQm/IiAGACUDABUACQm/IiAGACUDAAAA.Tarmo:BAAALgADCgYJEQAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAMJBQACAK4eAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAAALgAECgUJCQAAAA==.',
Th='Thaleon:BAAALgADCgEJAQAAAA==.Tharella:BAAALgAECgMJAwAAAA==.Thauriel:BAAALgADCgMJAwAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tinyterror:BAAALgADCgYJCAAAAA==.Titania:BAABLgAECn8WAAIZAAkJ6AO9QAB1AQAZAAkJ6AO9QAB1AQAAAA==.',
To='Toe:BAACLgAFFH8HAAIeAAQJfB38EQBZAQAeAAQJfB38EQBZAQAuAAQKfxoAAh4ACAm0HogYAOgCAB4ACAm0HogYAOgCAAAA.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgMJAwABLgADCgMJBAAGAAAAAA==.',
Ug='Uggoorc:BAAALgAFFAEJAQAAAA==.',
Va='Van:BAAALgADCgcJBwAAAA==.Vaultkey:BAAALgADCgIJAgAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Venin:BAAALgAECgYJBgAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgIJAgAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgADCgYJBgAAAA==.',
We='Weebsora:BAAALgAECgEJAQAAAA==.',
Wo='Worldtree:BAAALgAECgMJAgAAAA==.',
Xa='Xaelthira:BAAALgADCgkJEgAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgIJAgAGAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAAAAA==.',
Xz='Xzarrion:BAAALgADCgEJAQAAAA==.',
Ya='Yadhi:BAAALgAECgEJAQAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECgcJFwAIAEQfAA==.Yimomo:BAAALgAFFAEJAQAAAA==.',
Yo='Yoshira:BAAALgADCgQJBgABLgAECgMJBAAGAAAAAA==.',
Za='Zalconn:BAABLgAECn8eAAIhAAgJzCQ9AwBsAwAhAAgJzCQ9AwBsAwAAAA==.Zarrona:BAAALgAECgQJBAAAAA==.Zayah:BAAALgAECgMJAwAAAA==.',
Zn='Znasty:BAAALgAECgYJCgAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
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

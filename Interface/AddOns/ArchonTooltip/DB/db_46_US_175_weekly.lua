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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Monk-Brewmaster','Druid-Balance','Evoker-Preservation','Warlock-Destruction','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Unknown-Unknown','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Druid-Restoration','Druid-Feral','Paladin-Protection','Druid-Guardian','Warrior-Protection','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abiotic:BAAALgADCgYJBgAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.',
Ai='Aings:BAABLgAECn8eAAIBAAgJbSJvEwAeAgABAAgJbSJvEwAeAgAAAA==.',
Al='Aletaa:BAAALgAECgcJAQABLgAFFAMJCgACAHsWAA==.Alex:BAABLgAECn8lAAIDAAkJ9hvhBQCBAgADAAkJ9hvhBQCBAgAAAA==.Alivathor:BAAALgAECgEJAQAAAA==.Allypally:BAABLgAECn8YAAIEAAgJgw1jQABIAQAEAAgJgw1jQABIAQAAAA==.Althir:BAABLgAECn8lAAICAAgJZR/pJQDbAgACAAgJZR/pJQDbAgAAAA==.Althorian:BAAALgADCgMJAwAAAA==.',
Am='Amgrod:BAEALgAECgYJEQAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCgcJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8XAAIEAAcJvRfnJgCoAQAEAAcJvRfnJgCoAQAAAA==.',
Ar='Arfas:BAAALgAECgYJCgAAAA==.Arkhitype:BAABLgAECn8eAAQFAAcJIRCOBwArAQAGAAYJuQ+vMACBAQAFAAYJmw6OBwArAQAHAAEJHwZNDwApAAAAAA==.',
As='Ashya:BAAALgADCgYJBgAAAA==.Asur:BAAALgAECgYJDgAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAAALgAECgYJEQAAAA==.Auris:BAAALgADCgMJAwAAAA==.',
Ay='Aynilith:BAAALgAECgEJAQAAAA==.',
Ba='Bajr:BAABLgAECn8iAAIIAAgJeg75HwChAQAIAAgJeg75HwChAQAAAA==.Bakura:BAABLgAECn8fAAIJAAgJ/xllBAA5AgAJAAgJ/xllBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8dAAIDAAgJZBShIQBpAQADAAgJZBShIQBpAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAABLgAECn8tAAIKAAgJdSHHAABGAgAKAAgJdSHHAABGAgAAAA==.Berserk:BAAALgADCgIJAgAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJBwABLgAECgkJJwALAE4gAA==.Bigbear:BAAALgAECgYJCAABLgAFFAQJCgAMAD4kAA==.Bigtamer:BAAALgADCgMJAwAAAA==.',
Bj='Bjebo:BAABLgAECn8dAAINAAgJDAr2EwBlAQANAAgJDAr2EwBlAQAAAA==.',
Bl='Blaank:BAAALgAECgYJCgAAAA==.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.',
Bo='Boba:BAAALgAFFAIJBAABLgAFFAYJFwAOABkaAA==.',
Br='Brewchew:BAAALgAECgEJAQAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAABLgAECn8nAAQLAAkJTiByBQC8AgALAAkJTiByBQC8AgAJAAEJAAB3HwB1AAAPAAEJ+RmibQA5AAAAAA==.',
Ca='Calib:BAACLgAFFH8HAAIQAAMJzhBoEwDiAAAQAAMJzhBoEwDiAAAuAAQKfyUAAhAACAlDHaoKAPABABAACAlDHaoKAPABAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgADCgUJBgAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQARAKwRAA==.Cheechin:BAAALgAECgMJAwABLgAFFAQJCgACAP0OAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAABLgAECn8YAAINAAcJIBIyFABiAQANAAcJIBIyFABiAQAAAA==.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn8YAAIQAAcJViIrFwBeAgAQAAcJViIrFwBeAgAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8NAAISAAQJVx3SAABmAQASAAQJVx3SAABmAQAuAAQKfy0AAhIACQnQIh8AADoDABIACQnQIh8AADoDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8lAAITAAgJmiAwAgD+AgATAAgJmiAwAgD+AgAAAA==.',
Cv='Cvv:BAAALgADCgIJBAABLgADCgUJCgAUAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8HAAIVAAMJ3hf5EAD6AAAVAAMJ3hf5EAD6AAAuAAQKfykAAhUACAlqJGMBAC4DABUACAlqJGMBAC4DAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAAALgAECgYJDgAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJDQAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Dejavu:BAAALgAECgYJBgAAAA==.Demonblades:BAABLgAECn8aAAIDAAgJMRPZGQCbAQADAAgJMRPZGQCbAQAAAA==.Demonicpixie:BAAALgADCgUJBwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAKAOYeAA==.Devotegoat:BAAALgAECgMJAwAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAABLgAECn8ZAAMWAAgJSxB5MAB/AQAWAAYJ5xN5MAB/AQAXAAcJvQulGgAoAQAAAA==.',
Do='Docignis:BAABLgAECn8UAAIQAAcJjw8ZHQAtAQAQAAcJjw8ZHQAtAQAAAA==.Dockevorkian:BAACLgAFFH8FAAIWAAMJ+hsTCgDvAAAWAAMJ+hsTCgDvAAAuAAQKfycAAhYACAm5Ij0GAOsCABYACAm5Ij0GAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECgcJFAAQAI8PAA==.Docrhada:BAAALgAECgQJBAABLgAECgcJFAAQAI8PAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAAALgAECggJEAABLgAFFAUJEQABAG4eAA==.',
Dr='Dracoramonk:BAAALgAECgcJCwAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Dricex:BAAALgAECgEJAQAAAA==.Drinnagon:BAAALgAECgIJAwABLgAECgcJGQAKAOYeAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAKAOYeAA==.Drinntellect:BAABLgAECn8ZAAMKAAcJ5h6rBQDPAQAKAAYJCh+rBQDPAQACAAcJzBpXOACGAQAAAA==.Drraxx:BAAALgAECgQJBAAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8jAAIYAAgJBwf+CABHAQAYAAgJBwf+CABHAQAAAA==.',
Ea='Eamass:BAABLgAECn8kAAIMAAgJuCGtAgCuAgAMAAgJuCGtAgCuAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8UAAIZAAcJlgcJFgDPAAAZAAcJlgcJFgDPAAAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJCwAUAAAAAA==.',
En='Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8RAAQBAAUJbh7WDwBvAQABAAQJbh7WDwBvAQASAAQJbRBMAQBPAQAZAAEJAAASHQAAAAAuAAQKfyoAAgEACQmII3YDAPwCAAEACQmII3YDAPwCAAAA.Enthing:BAACLgAFFH8HAAIDAAMJpQxrIwDXAAADAAMJpQxrIwDXAAAuAAQKfykAAgMACAlcH28KADQCAAMACAlcH28KADQCAAAA.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAAALgAECggJEgAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAAALgAECgcJEgAAAA==.',
Fe='Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8YAAQaAAgJkxqgFwALAgAaAAgJkxqgFwALAgAbAAYJCBiIDQB+AQADAAEJPRSchgA6AAAAAA==.Fentagram:BAABLgAECn8dAAMJAAgJaiYoAAD0AgAJAAgJaiYoAAD0AgALAAEJgSOk+wBjAAAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgEJAQAAAA==.',
Fl='Floofwall:BAAALgAECgcJCgAAAA==.',
Fo='Fonyfish:BAABLgAECn8yAAMLAAkJCSPOAQAiAwALAAkJCSPOAQAiAwAPAAIJsBJqUQB6AAAAAA==.Fonytime:BAAALgAECgYJBgABLgAECgkJMgALAAkjAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8bAAMPAAgJbwwpBwBCAQAPAAgJbwwpBwBCAQALAAYJ0gUBVwDsAAAAAA==.Foxydots:BAAALgADCgcJCQAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgADCgcJDQABLgAECgQJCgAUAAAAAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8eAAMcAAcJux53FABKAgAcAAYJHiN3FABKAgAMAAcJWQvGGQAxAQAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Gg='Ggakkaltigad:BAAALgAECgQJBgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8TAAIdAAUJRB2oAgCJAQAdAAUJRB2oAgCJAQAuAAQKfyUAAx0ACAmmJHcHADEDAB0ACAmCJHcHADEDAB4AAgnRGUopAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8WAAIQAAYJhBmkIQAPAQAQAAYJhBmkIQAPAQABLgAFFAQJDQASAFcdAA==.Glorm:BAABLgAECn8ZAAIfAAgJ+gUgWQAkAQAfAAgJ+gUgWQAkAQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAAALgAECgQJCgAAAA==.Grantul:BAABLgAECn8lAAIdAAgJGx16CAAjAgAdAAgJGx16CAAjAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAAALgAECgYJEQABLgAFFAQJCgAMAD4kAA==.Grolgan:BAAALgAECgQJBQAAAA==.Growlings:BAAALgAECgMJBAAAAA==.',
Gu='Guncow:BAAALgADCgUJBQAAAA==.',
Ha='Hawktwo:BAAALgADCgEJAQABLgAECgQJCgAUAAAAAA==.',
He='Healiostrasz:BAAALgAECgMJBQAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgQJBQABLgAECgYJDwAUAAAAAA==.Holyczar:BAAALgADCgMJAwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hu='Hubirt:BAABLgAECn8kAAIEAAgJIhcPHADiAQAEAAgJIhcPHADiAQAAAA==.Huntsybuntsy:BAABLgAECn8hAAIQAAgJLhaAGwA2AgAQAAgJLhaAGwA2AgAAAA==.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJCwAUAAAAAA==.',
Hy='Hydrafoil:BAAALgAECgIJAgAAAA==.',
Ia='Ianthel:BAAALgAECgMJBgAAAA==.',
Ic='Icesloth:BAAALgAECgYJEQAAAA==.',
Id='Idamae:BAAALgAECgYJDQAAAA==.Iduun:BAAALgAECgUJBQAAAA==.',
Il='Iladelle:BAABLgAECn8kAAIDAAgJZxF9HACJAQADAAgJZxF9HACJAQAAAA==.Illidabina:BAAALgADCgEJAQABLgAECgcJHgAcALseAA==.',
In='Inariokami:BAAALgAECgcJDQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgEJAQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAAALgAECgQJBAABLgAECgYJFgALAKghAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAABLgAECn8mAAMPAAgJXxsABQCLAgAPAAgJWhkABQCLAgALAAMJnhS2nABJAAAAAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8UAAIWAAYJJg67RAAmAQAWAAYJJg67RAAmAQAAAA==.',
Je='Jessalba:BAAALgAECgMJAgAAAA==.Jestorian:BAAALgAECgUJCQAAAA==.',
Ji='Jirakaidae:BAAALgAECgQJBAAAAA==.',
Jo='Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCgAAAA==.Juicyfists:BAAALgADCgcJCgAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAAALgAECgYJDwAAAA==.',
Jx='Jxson:BAABLgAECn8XAAQgAAYJ3BJfVwBMAQAgAAYJ3BJfVwBMAQANAAYJqREkHAAaAQAhAAMJfhI6IwC8AAABLgAECgYJFgALAKghAA==.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ke='Kehila:BAAALgADCgEJAQAAAA==.',
Kh='Khelad:BAABLgAFFH8KAAIEAAQJsg24EABDAQAEAAQJsg24EABDAQAAAA==.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAAALgAECgMJAwAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killt:BAABLgAECn8dAAIfAAgJZBYxIgASAgAfAAgJZBYxIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAAALgAECgcJEQAAAA==.',
Ky='Kynthe:BAAALgAECgYJCgAAAA==.Kyongye:BAAALgAECggJCQAAAA==.',
La='Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8KAAMIAAQJcxXtCQBdAQAIAAQJcxXtCQBdAQAYAAIJ7AhZIACTAAAuAAQKfy8AAwgACAm9INYGAIoCAAgACAlPH9YGAIoCABgACAkEG8EaAFACAAAA.',
Le='Leadgut:BAAALgADCgQJBQAAAA==.Lemanjá:BAABLgAECn8WAAIYAAgJuwcbCgAwAQAYAAgJuwcbCgAwAQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAAALgAECggJEgAAAA==.Limbless:BAAALgAECgMJBAABLgAECgUJCAAUAAAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockstar:BAAALgADCgQJBAABLgAECgEJAQAUAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAAALgAECgQJBwAAAA==.Loozer:BAAALgAECgcJDAAAAA==.',
Lu='Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAAALgAECgYJEQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8UAAMBAAcJXBMnQQA7AQABAAcJXBMnQQA7AQASAAEJywjjGAAsAAAAAA==.',
Ma='Magelyman:BAAALgAECgcJDAAAAA==.Magetiger:BAAALgAECgYJDwAAAA==.Malitheion:BAAALgAECgIJAwAAAA==.Malzen:BAAALgAECgYJDAAAAA==.Manaleia:BAAALgADCgcJBwAAAA==.Manasolid:BAABLgAECn8eAAICAAgJSxKoKADCAQACAAgJSxKoKADCAQAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgADCgYJBgAAAA==.',
Me='Meches:BAAALgAECgQJCAABLgAECgYJFwAgAEMWAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAAALgAECgYJEQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Methslinger:BAAALgAECgcJAgAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8XAAIWAAcJdA9jFgBbAQAWAAcJdA9jFgBbAQAAAA==.',
Mk='Mkoons:BAAALgAECgEJAQAAAA==.',
Mo='Mook:BAAALgADCgkJCQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAAALgAECgMJBAAAAA==.Mortmuzi:BAAALgADCgYJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAAALgAECgQJDgAAAA==.Muldah:BAACLgAFFH8KAAICAAQJ/Q5AIQBOAQACAAQJ/Q5AIQBOAQAuAAQKfywAAgIACAmnIAQMAIUCAAIACAmnIAQMAIUCAAAA.',
My='Mynte:BAABLgAECn8cAAIWAAYJnRL/GgAvAQAWAAYJnRL/GgAvAQAAAA==.',
Na='Natty:BAAALgADCgkJFwAAAA==.Navie:BAAALgAECggJCAAAAA==.Nawperwoman:BAABLgAECn8kAAMcAAgJnhuhCADzAQAcAAgJnhuhCADzAQARAAEJrgGfdgAYAAAAAA==.',
Ne='Necronomicob:BAAALgAECgcJEwAAAA==.Neil:BAAALgADCgUJBQABLgAECggJEwAUAAAAAA==.Nekros:BAABLgAECn8eAAMLAAcJlCAdDwAwAgALAAYJqh8dDwAwAgAPAAQJaBxWJQAyAQAAAA==.Neø:BAABLgAECn8WAAMBAAgJJhSIigBrAQABAAgJJhSIigBrAQASAAMJkQpZDABwAAAAAA==.',
Ni='Nicebud:BAAALgAECgMJAwAAAA==.Nightsfury:BAAALgAECgYJBgAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAAALgADCgkJCwABLgAECgEJAQAUAAAAAA==.Nornyr:BAABLgAECn8YAAIRAAgJKhHfGAA/AQARAAgJKhHfGAA/AQAAAA==.Noxiss:BAAALgADCgQJBAABLgAECggJIwABAOweAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn8eAAINAAgJDwrNFABdAQANAAgJDwrNFABdAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oreosniffer:BAABLgAECn8mAAIGAAkJ+SEJAQD5AgAGAAkJ+SEJAQD5AgAAAA==.Oriax:BAAALgAECgYJDgAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgMJAwAAAA==.',
Pa='Paean:BAAALgADCgkJJQAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8gAAMgAAgJfwZhSwCjAAAgAAcJVARhSwCjAAANAAEJbAHvUAAXAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBAAUAAAAAA==.Persephones:BAABLgAECn8fAAIXAAcJ5w+6GQAwAQAXAAcJ5w+6GQAwAQAAAA==.',
Ph='Phenelope:BAAALgAECgQJBAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgcJDQAUAAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgADCgQJBAAAAA==.',
Pk='Pkalygos:BAABLgAECn8cAAIOAAgJwBR7BwC8AQAOAAgJwBR7BwC8AQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDQAAAA==.Powerstrokee:BAAALgAECgQJCgAAAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAITAAgJrRznEQCDAgATAAgJrRznEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIiAAYJwBQQFwBjAQAiAAYJwBQQFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAAALgAECgUJCgAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôps:BAAALgAECgYJEgAAAA==.',
Qu='Quickprick:BAAALgAECgcJCwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAAAAA==.Rasina:BAAALgAECgIJAgAAAA==.Ratkìng:BAAALgAECgIJAgAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Reknojir:BAAALgAECgIJAgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8KAAIDAAQJ/QpsFwAXAQADAAQJ/QpsFwAXAQAuAAQKfyQAAwMACAnAG8YLACICAAMACAnAG8YLACICABoABgkAEcQ6ABYBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgQJBAAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgUJCAAUAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn8VAAIjAAcJnwGhFwBfAAAjAAcJnwGhFwBfAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Runeclad:BAABLgAECn8ZAAIBAAgJCRXgHADaAQABAAgJCRXgHADaAQAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
Sa='Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgUJCgAAAA==.Salitheion:BAAALgAECgYJBgAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanatura:BAAALgAECgYJBwAAAA==.Sapper:BAABLgAECn8kAAIRAAgJGSGbAwC1AgARAAgJGSGbAwC1AgAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgMJBAAAAA==.Sarn:BAABLgAECn8ZAAIjAAgJEBM3DwCIAQAjAAgJEBM3DwCIAQAAAA==.Sathi:BAAALgAECgIJAgAAAA==.Saudhum:BAABLgAECn8WAAMJAAYJvRsfCADLAQAJAAYJvRsfCADLAQALAAQJ2g0MbQCyAAAAAA==.Sayuri:BAAALgAECgYJDAAAAA==.',
Sb='Sboop:BAAALgAECgEJAQAAAA==.',
Se='Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn8aAAIfAAgJNgLlMgDwAAAfAAgJNgLlMgDwAAAAAA==.Shikí:BAAALgADCggJEgAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8WAAIeAAcJDBNfCACCAQAeAAcJDBNfCACCAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAABLgAECn8aAAIkAAgJ7wwTEwD5AAAkAAgJ7wwTEwD5AAAAAA==.Shotsshots:BAABLgAECn8lAAQIAAgJWR2sCwBGAgAIAAgJWR2sCwBGAgAlAAIJGAwvIwCDAAAYAAEJAACfkQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgADCgcJCwAAAA==.Sicaria:BAAALgAECgQJCgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDQAAAA==.Skully:BAACLgAFFH8KAAIMAAQJPiShAgCyAQAMAAQJPiShAgCyAQAuAAQKfy8AAgwACAnjJI4BAOQCAAwACAnjJI4BAOQCAAAA.',
Sl='Slicedup:BAAALgAECgEJAQAAAA==.Sluffshot:BAABLgAECn8nAAMZAAgJqiC+AgA3AgAZAAgJFyC+AgA3AgABAAQJYx02twAUAQAAAA==.',
Sn='Snorina:BAABLgAECn8pAAIXAAgJ3yEICQD0AQAXAAgJ3yEICQD0AQAAAA==.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgADCgUJBQAAAA==.Solsteece:BAAALgADCgYJDgAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAAALgAECgYJDwAAAA==.Sosozen:BAAALgAECgYJEQAAAA==.Soul:BAAALgAECgUJCQAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgUJCQAUAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Spirittoast:BAAALgADCgkJKwAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAAALgAECgcJEwAAAA==.',
Sq='Squelch:BAAALgAECgEJAQAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Strumpet:BAAALgAECgQJBAAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAAALgAECgQJBAABLgAECgcJDAAUAAAAAA==.Swytch:BAABLgAECn8lAAIFAAgJzhdYAgAFAgAFAAgJzhdYAgAFAgAAAA==.',
Sy='Sylrytherin:BAAALgAECgcJEAABLgAECggJKQAXAN8hAA==.Sylvii:BAABLgAECn8XAAMgAAYJQxbBIAB7AQAgAAYJQxbBIAB7AQANAAQJrwzkLQCjAAAAAA==.',
Ta='Tabor:BAAALgAECgUJBgAAAA==.Tammyfaye:BAAALgADCgEJAQABLgAECgQJCgAUAAAAAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAAALgAECgcJDwAAAA==.Tauryel:BAAALgAECgUJCAAAAA==.',
Te='Tebook:BAABLgAECn8jAAIBAAgJ7B6EHADcAQABAAgJ7B6EHADcAQAAAA==.Telath:BAABLgAECn8fAAIDAAgJ0xr7PAAAAgADAAgJ0xr7PAAAAgAAAA==.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8NAAIDAAUJcR+lCgBgAQADAAUJcR+lCgBgAQAuAAQKfx0AAgMACAmGH14aALYCAAMACAmGH14aALYCAAAA.Thistlechi:BAABLgAECn8jAAIcAAgJIxktEAB9AgAcAAgJIxktEAB9AgAAAA==.Thyck:BAABLgAECn8ZAAIIAAgJuRLMGwC5AQAIAAgJuRLMGwC5AQAAAA==.Thydis:BAAALgAECgYJCQAAAA==.',
Ti='Tibbs:BAABLgAECn8XAAImAAgJ6Q3tEgBuAQAmAAgJ6Q3tEgBuAQAAAA==.Timber:BAAALgAECgIJBQAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJBgAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAAALgAECgYJCgAAAA==.',
Tu='Tullamore:BAAALgAECgIJAgAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgEJAgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQRAAcJrBHlLQBJAQARAAYJHxHlLQBJAQAcAAUJhQ2dKwCfAAAMAAEJWgDumAAbAAAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAECgcJEAAUAAAAAA==.',
Un='Uncorrupted:BAAALgAECgcJCwAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgQJBwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAAALgAECgYJDgAAAA==.Vasdepherens:BAABLgAECn8fAAIZAAgJGRMIGACbAQAZAAgJGRMIGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJDQAAAA==.Vermouth:BAABLgAECn8bAAMcAAYJHRSLMQBfAQAcAAYJHRSLMQBfAQARAAYJ3gLIKwCqAAAAAA==.',
Vi='Vindrelis:BAAALgADCgUJCgAAAA==.Violêt:BAAALgAECgQJBQAAAA==.',
Vo='Voidchris:BAAALgAECgYJCAAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgEJAQAAAA==.Volkanegos:BAAALgAECgYJEAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAECgkJMgAdAPIeAA==.Wizerwar:BAABLgAECn8yAAIdAAkJ8h5fAQD3AgAdAAkJ8h5fAQD3AgAAAA==.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAAALgAECgQJBgAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgYJBgAAAA==.',
Ya='Yadiyada:BAAALgADCgcJBwAAAA==.',
Yl='Ylzera:BAAALgAECgEJAQAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIaAAYJyQjTFgDqAAAaAAYJyQjTFgDqAAAAAA==.Yoshì:BAAALgAECgQJBAAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAAAAA==.Zakuren:BAABLgAECn8fAAIIAAgJkgs0OADNAQAIAAgJkgs0OADNAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBAAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAAALgAECgYJEAAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8YAAQmAAcJ1Q1hGwAkAQAmAAYJgA9hGwAkAQAOAAUJSwTjMwDOAAAnAAQJNAsxKwDDAAAAAA==.',
['Òm']='Òmêñ:BAAALgADCgkJDwAAAA==.',
['Ôj']='Ôjarg:BAAALgAECgcJEAAAAA==.',
['Ül']='Ülf:BAAALgADCgQJBAAAAA==.',
['ßæ']='ßær:BAAALgAECgQJBwAAAA==.',
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

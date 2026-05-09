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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Monk-Brewmaster','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Unknown-Unknown','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Warrior-Protection','Paladin-Protection','Druid-Guardian','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abiotic:BAAALgADCgkJDAAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.',
Ai='Aings:BAABLgAECn8mAAIBAAkJSCKACQDIAgABAAkJSCKACQDIAgAAAA==.',
Al='Aletaa:BAAALgAECgcJAQABLgAFFAMJCgACAIAWAA==.Alex:BAABLgAECn8uAAIDAAkJ5B2JBgDAAgADAAkJ5B2JBgDAAgAAAA==.Alivathor:BAAALgAECgEJAgAAAA==.Allypally:BAABLgAECn8bAAIEAAkJig2OPgCKAQAEAAkJig2OPgCKAQAAAA==.Althir:BAABLgAECn8oAAICAAkJxB/+EACSAgACAAkJxB/+EACSAgAAAA==.Althorian:BAAALgADCgMJAwAAAA==.',
Am='Amgrod:BAEALgAECgYJEgAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIEAAcJ5hjlNACqAQAEAAcJ5hjlNACqAQAAAA==.',
Ar='Arfas:BAAALgAECgcJCwAAAA==.Arkhitype:BAABLgAECn8lAAQFAAgJhxXdAwDmAQAFAAgJ1hPdAwDmAQAGAAYJuQ+rMACBAQAHAAEJGQbAFAApAAAAAA==.Armak:BAAALgADCgEJAQAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgADCgMJAwAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn8UAAIEAAYJdQy4cwAFAQAEAAYJdQy4cwAFAQAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAAALgAECgYJEgAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgUJBgAAAA==.',
Ba='Bajr:BAABLgAECn8lAAIIAAkJHQ6wJADCAQAIAAkJHQ6wJADCAQAAAA==.Bakura:BAABLgAECn8gAAIJAAgJABplBAA5AgAJAAgJABplBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8eAAIDAAgJkBSHMwBnAQADAAgJkBSHMwBnAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAABLgAECn83AAIKAAgJjCJ/AAC0AgAKAAgJjCJ/AAC0AgAAAA==.Berserk:BAAALgADCgIJAgAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJCgABLgAECgkJKAALAFcgAA==.Bigbear:BAAALgAECgcJCwABLgAFFAQJDgAMAGMkAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAABLgAECn8lAAINAAkJUA5+EADLAQANAAkJUA5+EADLAQAAAA==.',
Bl='Blaank:BAAALgAECgYJCwAAAA==.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.',
Bo='Boba:BAABLgAFFH8IAAMOAAMJMyGcGAAKAQAOAAMJMyGcGAAKAQAPAAEJ1wHaLwA9AAABLgAFFAYJFwAQACIaAA==.Borg:BAAALgAECgEJAQAAAA==.',
Br='Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAAALgAECgQJBQAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAABLgAECn8oAAQLAAkJVyBGCQCzAgALAAkJVyBGCQCzAgAJAAEJAAB6HwB1AAARAAEJ+RmibQA5AAAAAA==.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8LAAIPAAQJvBEaEAAuAQAPAAQJvBEaEAAuAQAuAAQKfywAAg8ACAl4ILUJAD4CAA8ACAl4ILUJAD4CAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgEJAQAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQASAKwRAA==.Cheechin:BAAALgAECgcJCwABLgAFFAQJDgACAH4PAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAABLgAECn8dAAINAAcJXhJkGgBkAQANAAcJXhJkGgBkAQAAAA==.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn8gAAIPAAgJsB9JCgA1AgAPAAgJsB9JCgA1AgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgADCggJCAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8RAAITAAQJMCL/AAB5AQATAAQJMCL/AAB5AQAuAAQKfy0AAhMACQnYIkEAAJMDABMACQnYIkEAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8mAAIUAAgJmiDGBADjAgAUAAgJmiDGBADjAgAAAA==.',
Cv='Cvv:BAAALgADCgIJBAABLgAECgYJEAAVAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8LAAIWAAQJARSFEQA7AQAWAAQJARSFEQA7AQAuAAQKfzAAAhYACAltJBgCADsDABYACAltJBgCADsDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8VAAICAAcJ7hmiMwDSAQACAAcJ7hmiMwDSAQAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Dejavu:BAAALgAECgYJDgAAAA==.Demonblades:BAABLgAECn8bAAIDAAkJmRFeIQDAAQADAAkJmRFeIQDAAQAAAA==.Demonicpixie:BAAALgADCgkJDQAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAKAO4eAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAABLgAECn8fAAMXAAgJ0xB+MAB/AQAXAAYJ0xR+MAB/AQAYAAcJqgviJAAcAQAAAA==.',
Do='Docignis:BAABLgAECn8XAAIPAAgJXA+yHgBYAQAPAAgJXA+yHgBYAQAAAA==.Dockevorkian:BAACLgAFFH8JAAIXAAQJPx3fBgBWAQAXAAQJPx3fBgBWAQAuAAQKfygAAhcACAnKIjwGAOsCABcACAnKIjwGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAPAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAPAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8YAAIDAAgJURy3DwBHAgADAAgJURy3DwBHAgABLgAFFAUJEgATAG8eAA==.',
Dr='Dracoramonk:BAAALgAECggJDQAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Dricex:BAAALgAECgEJAQAAAA==.Drinnagon:BAAALgAECgIJBQABLgAECgcJGQAKAO4eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAKAO4eAA==.Drinntellect:BAABLgAECn8ZAAMKAAcJ7h6qBQDPAQAKAAYJCh+qBQDPAQACAAcJ0xowTQCCAQAAAA==.Drraxx:BAAALgAECgQJBAAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8kAAIZAAgJXwecCwA0AQAZAAgJXwecCwA0AQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8nAAIMAAkJQCHzAQD/AgAMAAkJQCHzAQD/AgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8aAAIaAAgJMgi3GAAFAQAaAAgJMgi3GAAFAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJEgAVAAAAAA==.',
En='Enanthate:BAAALgADCgMJAwABLgAECgYJEAAVAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8SAAQTAAUJbx5fAgA8AQABAAQJbx77IABeAQATAAQJhBJfAgA8AQAaAAEJAADqJgAAAAAuAAQKfyoAAgEACQmJI44HAOQCAAEACQmJI44HAOQCAAAA.Enthing:BAACLgAFFH8LAAIDAAQJEw0uJgAYAQADAAQJEw0uJgAYAQAuAAQKfzAAAgMACAmDH2gQAD8CAAMACAmDH2gQAD8CAAAA.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8YAAIXAAgJPybXAAB8AwAXAAgJPybXAAB8AwAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAABLgAECn8UAAIYAAgJ+xE9MQBbAQAYAAgJ+xE9MQBbAQAAAA==.',
Fe='Felaxare:BAAALgAECgEJAQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8aAAQbAAgJORyhFwALAgAbAAgJlBqhFwALAgAcAAYJCBiIDQB+AQADAAIJgRdWhACLAAAAAA==.Fentagram:BAABLgAECn8fAAMJAAgJcSaQAAC8AgAJAAgJcSaQAAC8AgALAAMJNCAoiQCzAAAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgEJAQAAAA==.',
Fl='Floofwall:BAAALgAECggJEgAAAA==.',
Fo='Fonyfish:BAABLgAECn8yAAMLAAkJCSNdAwAbAwALAAkJCSNdAwAbAwARAAIJsBJpUQB6AAAAAA==.Fonytime:BAAALgAECgYJBgABLgAECgkJMgALAAkjAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8jAAMRAAgJVRDABgCAAQARAAgJVRDABgCAAQALAAYJ4wUmcQDoAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECgYJEgAVAAAAAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8kAAMdAAcJvx50FABKAgAdAAYJHiN0FABKAgAMAAcJYAu+IgAlAQAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Gg='Ggakkaltigad:BAAALgAECgcJCQAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8VAAIeAAUJPx04BwBoAQAeAAUJPx04BwBoAQAuAAQKfyUAAx4ACAmmJHQHADEDAB4ACAmCJHQHADEDAB8AAgnRGUopAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8WAAIPAAYJhBn9KwAIAQAPAAYJhBn9KwAIAQABLgAFFAQJEQATADAiAA==.Glorm:BAABLgAECn8eAAIOAAgJUwYaWQAkAQAOAAgJUwYaWQAkAQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAAALgAECgYJEgAAAA==.Grantul:BAABLgAECn8mAAIeAAgJHR35DQANAgAeAAgJHR35DQANAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAAALgAECgYJEQABLgAFFAQJDgAMAGMkAA==.Grolgan:BAAALgAECgYJCAAAAA==.Growlings:BAAALgAECgYJBwAAAA==.',
Gu='Guilarth:BAAALgADCgYJBgAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hawktwo:BAAALgADCgEJAQABLgAECgYJEgAVAAAAAA==.',
He='Healiostrasz:BAAALgAECgMJBQAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgQJBQABLgAECgYJFQAEAAcXAA==.Holyczar:BAAALgADCgMJAwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIEAAgJ/RjNJQDrAQAEAAgJ/RjNJQDrAQAAAA==.Huntsybuntsy:BAABLgAECn8pAAMPAAgJ3Bh/GwA2AgAPAAgJMxZ/GwA2AgAgAAgJ3xJHBwC+AQAAAA==.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJEgAVAAAAAA==.',
Hy='Hydrafoil:BAAALgAECgIJAgAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAAALgAECgYJEgAAAA==.',
Id='Idamae:BAAALgAECgYJDgAAAA==.Iduun:BAAALgAECgUJCQAAAA==.',
Il='Iladelle:BAABLgAECn8kAAIDAAgJ5xE8LACHAQADAAgJ5xE8LACHAQAAAA==.Illidabina:BAAALgAECgIJBQABLgAECgcJJAAdAL8eAA==.',
In='Inariokami:BAAALgAECgcJEAAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgEJAQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAAALgAECgUJBQABLgAECgYJHAALAOMiAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAABLgAECn8uAAMRAAgJoBz/BACLAgARAAgJWxn/BACLAgALAAgJLxqSFQA1AgAAAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8UAAIXAAYJJg7DRAAmAQAXAAYJJg7DRAAmAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jestorian:BAAALgAECgUJCQAAAA==.',
Ji='Jirakaidae:BAAALgAECgQJCAAAAA==.',
Jo='Jockinonmytw:BAABLgAECn8vAAIGAAkJLSPWAAA6AwAGAAkJLSPWAAA6AwAAAA==.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgADCgcJCgAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAAALgAECgYJDwAAAA==.',
Jx='Jxson:BAABLgAECn8bAAQhAAYJxRReVwBMAQAhAAYJxRReVwBMAQANAAYJCBKfJAAWAQAiAAMJfhI7IwC8AAABLgAECgYJHAALAOMiAA==.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kantuo:BAAALgAECgYJBgAAAA==.',
Ke='Kehila:BAAALgADCgEJAQAAAA==.',
Kh='Khelad:BAABLgAFFH8OAAIEAAQJ+A9NGQBGAQAEAAQJ+A9NGQBGAQAAAA==.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAAALgAECgQJBQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killt:BAABLgAECn8dAAIOAAgJZBYwIgASAgAOAAgJZBYwIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8UAAIjAAcJXQ9wFAAmAQAjAAcJXQ9wFAAmAQAAAA==.',
Ky='Kynthe:BAAALgAECgYJCgAAAA==.Kyongye:BAAALgAECggJCgAAAA==.',
La='Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8OAAMIAAQJLBsVCgByAQAIAAQJLBsVCgByAQAZAAIJ7AhkIACTAAAuAAQKfzgAAwgACQmBI5QBAEEDAAgACQmBI5QBAEEDABkACAkEG5UaAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBQAAAA==.Lemanjá:BAABLgAECn8bAAIZAAgJ7QlLCwA6AQAZAAgJ7QlLCwA6AQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8VAAMkAAgJcgk9FwDgAAAkAAcJZgo9FwDgAAAEAAIJKAUJ5wBHAAAAAA==.Limbless:BAAALgAECgMJBAABLgAECgUJCAAVAAAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockstar:BAAALgADCgQJBgABLgAECgMJAwAVAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAAALgAECgYJDgAAAA==.Loozer:BAAALgAECgcJEAAAAA==.',
Lu='Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAAALgAECgYJEQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8WAAMBAAgJ9BSFOACXAQABAAgJ9BSFOACXAQATAAEJywjjGAAsAAAAAA==.',
Ma='Magelyman:BAAALgAECgcJDwAAAA==.Magetiger:BAAALgAECgYJEAAAAA==.Malitheion:BAAALgAECgQJBwAAAA==.Malzen:BAAALgAECgYJDAAAAA==.Manaleia:BAAALgADCgcJBwAAAA==.Manasolid:BAABLgAECn8kAAICAAgJbRIsNwDFAQACAAgJbRIsNwDFAQAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgADCgYJBgAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgYJEAAVAAAAAA==.',
Me='Meches:BAAALgAECgQJCAABLgAECgYJHQAhAEkWAA==.Mediocre:BAAALgAECgEJAQAAAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8YAAICAAcJNwfbcwApAQACAAcJNwfbcwApAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Methslinger:BAAALgAECgcJAwAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8dAAIXAAgJ/RWDDgD/AQAXAAgJ/RWDDgD/AQAAAA==.',
Mk='Mkoons:BAAALgAECgEJAgAAAA==.',
Mo='Mook:BAAALgADCgkJCQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAAALgAECgYJCQAAAA==.Mortmuzi:BAAALgADCgYJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8XAAILAAYJVxMaSABQAQALAAYJVxMaSABQAQAAAA==.Muldah:BAACLgAFFH8OAAICAAQJfg/kLwBJAQACAAQJfg/kLwBJAQAuAAQKfy8AAgIACQlXIDYIAO4CAAIACQlXIDYIAO4CAAAA.',
My='Mynte:BAABLgAECn8eAAIXAAYJnBIRHwBQAQAXAAYJnBIRHwBQAQAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAAALgAECgkJEQAAAA==.Nawperwoman:BAABLgAECn8oAAMdAAgJvhtgCgAUAgAdAAgJvhtgCgAUAgASAAEJrgGfdgAYAAAAAA==.Nazevroth:BAAALgAECgQJBAAAAA==.',
Ne='Necronomicob:BAABLgAECn8VAAILAAgJXxS3JwDIAQALAAgJXxS3JwDIAQAAAA==.Neil:BAAALgADCgUJBQABLgAFFAEJAQAVAAAAAA==.Nekros:BAABLgAECn8lAAMLAAgJpiAyDQCEAgALAAcJ3h8yDQCEAgARAAQJaBxSJQAyAQAAAA==.Neø:BAABLgAECn8eAAMBAAgJaRX6KwDLAQABAAgJaRX6KwDLAQATAAMJoApMEQBmAAAAAA==.',
Ni='Nicebud:BAAALgAECgMJAwAAAA==.Nightsfury:BAAALgAECgYJBgAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAAALgAECgEJAgABLgAECgEJAgAVAAAAAA==.Nornyr:BAABLgAECn8eAAISAAgJoBb6DQAMAgASAAgJoBb6DQAMAgAAAA==.Noxiss:BAAALgADCgQJBAABLgAECggJKAABAO0eAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn8kAAINAAgJJgowHABTAQANAAgJJgowHABTAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAAALgAECgcJDwAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgMJAwAAAA==.',
Pa='Paean:BAAALgAECgQJBAAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8gAAMhAAgJgAbUfwDbAAAhAAcJVATUfwDbAAANAAEJawHsZQAXAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBQAVAAAAAA==.Peata:BAAALgADCgkJCgAAAA==.Persephones:BAABLgAECn8fAAIYAAcJ4g/aJwCaAQAYAAcJ4g/aJwCaAQAAAA==.',
Ph='Phenelope:BAAALgAECgcJCgAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgcJEAAVAAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgADCgQJBAAAAA==.',
Pk='Pkalygos:BAABLgAECn8cAAIQAAgJxhR+CgCrAQAQAAgJxhR+CgCrAQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDQAAAA==.Powerstrokee:BAAALgAECgcJEgAAAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAIUAAgJrRzoEQCDAgAUAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIkAAYJwBQRFwBjAQAkAAYJwBQRFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAAALgAECgYJDwAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJDgAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Reknojir:BAAALgAECgIJAgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8OAAIDAAQJbg1yJQAbAQADAAQJbg1yJQAbAQAuAAQKfy0AAwMACQnsHPwIAJUCAAMACQnsHPwIAJUCABsABgkAEcc6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgQJBAAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgUJCAAVAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn8cAAIlAAgJcwHZHABxAAAlAAgJcwHZHABxAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Runeclad:BAABLgAECn8aAAIBAAgJyBadJADwAQABAAgJyBadJADwAQAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAQAAAA==.',
Sa='Saauurrora:BAAALgADCggJCAAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgUJCgABLgAECgYJEAAVAAAAAA==.Salitheion:BAAALgAECggJDAAAAA==.Saloraith:BAAALgAECgYJBgAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8pAAISAAkJOCDtAgAUAwASAAkJOCDtAgAUAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgMJBAAAAA==.Sarn:BAABLgAECn8bAAIlAAkJpxI2DwCIAQAlAAkJpxI2DwCIAQAAAA==.Sathi:BAAALgAECgIJAgAAAA==.Saudhum:BAABLgAECn8WAAMJAAYJwRsfCADLAQAJAAYJwRsfCADLAQALAAQJ4Q3XigCvAAAAAA==.Sayuri:BAAALgAECgcJEgAAAA==.',
Sb='Sboop:BAAALgAECgMJBQAAAA==.',
Se='Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn8iAAIOAAgJewI3QwD1AAAOAAgJewI3QwD1AAAAAA==.Shikí:BAAALgADCggJFAAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8aAAIfAAcJvRRJDAB8AQAfAAcJvRRJDAB8AQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAABLgAECn8eAAIjAAgJYxFSDgB+AQAjAAgJYxFSDgB+AQAAAA==.Shotsshots:BAABLgAECn8lAAQIAAgJWR1LFQAlAgAIAAgJWR1LFQAlAgAmAAIJGgw1LwB/AAAZAAEJAACwkQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgADCgcJCwAAAA==.Sicaria:BAAALgAECgUJDwAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8OAAIMAAQJYySKBACuAQAMAAQJYySKBACuAQAuAAQKfzIAAgwACQleJX0AAGMDAAwACQleJX0AAGMDAAAA.',
Sl='Slicedup:BAAALgAECgMJAwAAAA==.Sluffshot:BAABLgAECn8qAAMaAAkJeyAtAgDZAgAaAAkJ+h8tAgDZAgABAAQJYx0ytwAUAQAAAA==.',
Sn='Snorina:BAABLgAECn8uAAIYAAgJdiNtCwANAgAYAAgJdiNtCwANAgAAAA==.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgADCgUJBQAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn8VAAMMAAYJJBD4KgD1AAAMAAYJJBD4KgD1AAAdAAEJWglaZQAtAAAAAA==.Sosozen:BAAALgAECgYJEgAAAA==.Soul:BAAALgAECgYJDQAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgYJDQAVAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgQJBAAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8YAAICAAgJUw2ZSACOAQACAAgJUw2ZSACOAQAAAA==.',
Sq='Squelch:BAAALgAECgIJAwAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Strumpet:BAAALgAECgQJBAAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAAALgAECgQJBAABLgAECgcJEAAVAAAAAA==.Swytch:BAABLgAECn8mAAIFAAgJ7BdUAwACAgAFAAgJ7BdUAwACAgAAAA==.',
Sy='Sylrytherin:BAAALgAECgcJEAABLgAECggJLgAYAHYjAA==.Sylvii:BAABLgAECn8dAAMhAAYJSRYVLQBxAQAhAAYJSRYVLQBxAQANAAYJdAsFKgD0AAAAAA==.',
Ta='Tabor:BAAALgAECgUJCgAAAA==.Tammyfaye:BAAALgADCgEJAQABLgAECgYJEgAVAAAAAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8VAAIUAAcJIhRgGQDAAQAUAAcJIhRgGQDAAQAAAA==.Tauryel:BAAALgAECgUJCAAAAA==.',
Te='Tebook:BAABLgAECn8oAAIBAAgJ7R5ZKwDOAQABAAgJ7R5ZKwDOAQAAAA==.Telath:BAABLgAECn8fAAIDAAgJ0xr3PAAAAgADAAgJ0xr3PAAAAgAAAA==.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8SAAIDAAUJSCAXEwBjAQADAAUJSCAXEwBjAQAuAAQKfx0AAgMACAmGH1saALYCAAMACAmGH1saALYCAAAA.Thistlechi:BAABLgAECn8jAAIdAAgJIxktEAB9AgAdAAgJIxktEAB9AgAAAA==.Thyck:BAABLgAECn8ZAAIIAAgJuxKCKwChAQAIAAgJuxKCKwChAQAAAA==.Thydis:BAAALgAECgYJCQAAAA==.',
Ti='Tibbs:BAABLgAECn8ZAAInAAgJgg6nGQByAQAnAAgJgg6nGQByAQAAAA==.Timber:BAAALgAECgIJBQAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAAALgAECgYJEAAAAA==.',
Tu='Tullamore:BAAALgAECgIJAgAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgYJBwAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQSAAcJrBHnLQBJAQASAAYJHxHnLQBJAQAdAAUJjw1KTwDVAAAMAAEJWgDzmAAbAAAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAUJDwAhAJsYAA==.',
Un='Uncorrupted:BAAALgAECggJEQAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJDQAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAAALgAECgYJEwAAAA==.Vasdepherens:BAABLgAECn8iAAIaAAkJShMoEQBfAQAaAAkJShMoEQBfAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8cAAMdAAcJcRM7IQAcAQAdAAcJcRM7IQAcAQASAAYJ6ALqOACmAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEAAAAA==.Violêt:BAAALgAECgYJCAAAAA==.',
Vo='Voidchris:BAAALgAECgcJDgAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgEJAQAAAA==.Volkanegos:BAABLgAECn8UAAMeAAYJ0wKTRQCnAAAeAAYJ0wKTRQCnAAAfAAEJuwCKSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAECgkJOwAeANgiAA==.Wizerwar:BAABLgAECn87AAIeAAkJ2CKxAABMAwAeAAkJ2CKxAABMAwAAAA==.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAAALgAECgYJDAAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgYJBgAAAA==.',
Ya='Yadiyada:BAAALgADCgcJBwAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIbAAYJywhGHgDmAAAbAAYJywhGHgDmAAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn8oAAIIAAkJiQuNJADDAQAIAAkJiQuNJADDAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAAALgAECgYJEgAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8dAAQnAAgJbwxZHgBMAQAnAAcJlw1ZHgBMAQAQAAUJSwTjMwDOAAAoAAQJNAsuKwDDAAAAAA==.',
['Òm']='Òmêñ:BAAALgADCgkJDwAAAA==.',
['Ôj']='Ôjarg:BAAALgAECgcJEAAAAA==.',
['Ül']='Ülf:BAAALgADCgQJBAAAAA==.',
['ßæ']='ßær:BAAALgAECgQJCQAAAA==.',
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

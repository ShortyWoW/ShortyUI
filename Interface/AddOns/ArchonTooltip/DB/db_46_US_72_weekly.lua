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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Paladin-Protection','Mage-Frost','Warrior-Arms','Warrior-Fury','Priest-Shadow','Warrior-Protection','Rogue-Subtlety','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Unholy','Shaman-Elemental','Druid-Balance','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Druid-Feral','Paladin-Retribution','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAAALgAECgcJEwAAAA==.Akusenshi:BAAALgAECgYJDwAAAA==.',
Al='Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgQJBwAAAA==.Alexi:BAAALgADCgYJBAAAAA==.Alivis:BAEALgADCgYJEQABLgAECgcJHAABAFciAA==.Alzith:BAAALgAECgQJBQAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgACAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAgJKQADAC4lAA==.',
Ap='Apexalpha:BAAALgAECgIJAwAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgADCgcJDAAAAA==.Arold:BAABLgAECn8aAAIEAAgJFhEELAC0AQAEAAgJFhEELAC0AQAAAA==.',
As='Asylia:BAACLgAFFH8KAAIFAAQJNRGCCQA5AQAFAAQJNRGCCQA5AQAuAAQKfxcAAgUACAlLGy4hABcCAAUACAlLGy4hABcCAAAA.',
At='Atlantus:BAAALgAECgYJDgAAAA==.',
Au='Aurelliae:BAAALgAECggJEQAAAA==.',
Av='Avesiren:BAABLgAECn8VAAIGAAYJcRTrEQAhAQAGAAYJcRTrEQAhAQAAAA==.',
Ay='Ayidá:BAAALgAECgQJBwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgYJDAAAAA==.Babymamaa:BAAALgAECgIJAgAAAA==.Babymuffins:BAAALgAECgYJDgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgEJAQAAAA==.Belanda:BAAALgAECgIJAgAAAA==.Belgord:BAAALgAECgQJBgAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJBwAAAA==.',
Bl='Blackmill:BAAALgAECgYJDAAAAA==.Blayrog:BAABLgAECn8cAAIHAAcJ0w5XaABAAQAHAAcJ0w5XaABAAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8hAAMIAAcJOBifDQBoAQAIAAcJ1BefDQBoAQAJAAYJ/RDNUQBiAQABLgAFFAUJEQAKANoUAA==.Bolf:BAAALgAECgQJCAAAAA==.Boombaaby:BAAALgAECgUJDwAAAA==.Bootzee:BAAALgAECgYJEgAAAA==.',
Br='Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAAALgAECgYJDwAAAA==.Brunhilian:BAAALgAECgQJBAAAAA==.',
Bu='Buckmaster:BAAALgADCggJDAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAAALgAECgYJDgAAAA==.Calada:BAAALgAECgQJBgAAAA==.',
Ce='Cedarnia:BAAALgADCgMJAgAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAECgcJCwACAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8WAAIFAAcJ3RNtIgChAQAFAAcJ3RNtIgChAQAAAA==.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgYJDgAAAA==.',
Cr='Cribbage:BAABLgAECn8mAAILAAgJYCIGAwCkAgALAAgJYCIGAwCkAgAAAA==.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCgUJBwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgQJCgAAAA==.',
Cy='Cynosure:BAABLgAECn8iAAIMAAkJxRi3BAB7AgAMAAkJxRi3BAB7AgAAAA==.Cytronsneak:BAAALgAECgEJAQAAAA==.',
Da='Dabb:BAAALgADCgcJCAAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgQJCAAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8WAAIEAAYJcQiOagD3AAAEAAYJcQiOagD3AAAAAA==.Darkheaven:BAAALgAECgYJDAAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgUJCQAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECgYJEAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8JAAINAAMJOBfsLgD1AAANAAMJOBfsLgD1AAAuAAQKfyIAAg0ACAlOIrMZALoCAA0ACAlOIrMZALoCAAEuAAQKBQkKAAIAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCggJCgAAAA==.Devinetoro:BAAALgAECgYJEQAAAA==.Devnull:BAAALgADCgIJAgAAAA==.Devour:BAABLgAECn8hAAIOAAkJGBckLAD/AQAOAAkJGBckLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8WAAQPAAYJBxQECAAyAQAPAAYJBxQECAAyAQAQAAQJTRKgHQCEAAARAAMJLQboRACEAAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgYJDgABLgAFFAQJDAASALkKAA==.Dreadsofdeth:BAABLgAECn8VAAIHAAYJixhvngCZAQAHAAYJixhvngCZAQAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8ZAAIEAAgJ5AlxQABoAQAEAAgJ5AlxQABoAQAAAA==.',
Ei='Einheri:BAABLgAECn8bAAIJAAYJxBpwHACFAQAJAAYJxBpwHACFAQAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgADCgYJDgAAAA==.Elracc:BAAALgAECgYJBgAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8HAAIMAAIJGhIaGgCmAAAMAAIJGhIaGgCmAAAuAAQKfx8AAgwACQkWDygLAO4BAAwACQkWDygLAO4BAAAA.Enoira:BAAALgAECgEJAQAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgADCgkJGwAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Ev='Evillizard:BAAALgAECgYJDwAAAA==.',
Ex='Exhumer:BAAALgAECgYJEwAAAA==.',
Fa='Faffard:BAAALgAECgQJCgABLgAECggJJQATALIHAA==.Fame:BAAALgAFFAEJAQABLgAFFAQJDwARAFEZAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBAAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgADCgYJCQAAAA==.',
Fi='Fizzlenips:BAAALgADCgcJFAAAAA==.',
Fl='Flap:BAACLgAFFH8PAAIRAAQJURnvEgBAAQARAAQJURnvEgBAAQAuAAQKfxkAAxEACAlOGGocAOQBABEACAlOGGocAOQBAA8AAQkAAJhAAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fy='Fystie:BAAALgAECgQJCgABLgAECggJJQATALIHAA==.',
Ga='Galpally:BAAALgAECgYJEgAAAA==.Ganzar:BAAALgADCgMJBAABLgAECgkJGwAUAPMcAA==.Garin:BAAALgAECgUJBQAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.',
Gi='Gishongar:BAAALgADCgkJCQAAAA==.',
Gl='Glorak:BAAALgAECgYJDwAAAA==.',
Gr='Grashen:BAAALgAECgYJEgAAAA==.Gravorik:BAAALgAECgUJBwAAAA==.Greefkarga:BAAALgADCgkJCQAAAA==.Grogu:BAAALgAECgYJDgAAAA==.',
Gs='Gsm:BAABLgAECn8ZAAIVAAYJQQ2wLQD/AAAVAAYJQQ2wLQD/AAAAAA==.',
Gu='Gulritz:BAAALgAECgEJAQAAAA==.',
Ha='Hante:BAAALgADCgQJBAAAAA==.Hartmonster:BAAALgAECgQJBAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMBAAcJIwUrYwDnAAABAAYJ1AUrYwDnAAASAAEJrwFcLQAfAAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgEJAQAAAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgADCgMJCQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECgYJEQAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAAALgAECgYJEAAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8YAAIWAAYJVg9yJQAQAQAWAAYJVg9yJQAQAQAAAA==.Jellexy:BAAALgAECgQJCgAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8HAAIXAAMJcw77FwDAAAAXAAMJcw77FwDAAAAuAAQKfysAAhcACAk0HQAKAE0CABcACAk0HQAKAE0CAAAA.Jonnyfive:BAAALgAECgMJAwAAAA==.',
Ka='Kailis:BAABLgAECn8dAAIBAAgJThaKHADyAQABAAgJThaKHADyAQAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgAECgYJCgAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8iAAMBAAcJkCE1AAB9AgABAAcJkCE1AAB9AgASAAUJWQe4CgBuAQAuAAQKfzgAAwEACQkZJuAAAGEDABIACQkYIo0CAIkDAAEACQkWJuAAAGEDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgADCgEJAQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJBgAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn8uAAIYAAkJURg8AgCnAgAYAAkJURg8AgCnAgAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIZAAkJaxdAFgDcAQAZAAkJaxdAFgDcAQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgIJAgAAAA==.Kruger:BAABLgAECn8ZAAIEAAYJqgZZbgDuAAAEAAYJqgZZbgDuAAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.',
Kt='Ktanna:BAAALgAECgYJDwAAAA==.',
Ku='Kublakhan:BAAALgAECgYJCwAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAUJEQAGAE4dAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8eAAIFAAgJQx7lFgD7AQAFAAgJQx7lFgD7AQAAAA==.Lateralus:BAAALgAECgYJEwAAAA==.Laureli:BAAALgAECgQJCAAAAA==.',
Le='Leeta:BAAALgAECgYJDgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAAALgAECgYJDAAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgAAAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgIJAgAAAA==.Losoz:BAAALgAECgEJAQAAAA==.',
Lu='Lusilsandrus:BAAALgAECgUJDAAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAECgYJBgAAAA==.Mahoutsukai:BAAALgAECgUJBgAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAAALgAECgYJDgAAAA==.',
Me='Mechaknight:BAAALgAECgUJCAAAAA==.Meddler:BAAALgADCgQJBQAAAA==.',
Mi='Mildrik:BAAALgAECgYJDAAAAA==.Miracledh:BAABLgAECn8WAAIaAAYJKiboBgAyAgAaAAYJKiboBgAyAgAAAA==.Mirkdrak:BAAALgAECgQJCwAAAA==.Misheard:BAABLgAECn8lAAINAAkJeR+VJQCoAQANAAkJeR+VJQCoAQAAAA==.Misjudged:BAAALgAECgYJDgAAAA==.Missus:BAAALgAECgYJCgAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgEJAQAAAA==.Mizzen:BAABLgAECn8dAAIbAAcJpBhlFACMAQAbAAcJpBhlFACMAQABLgAFFAUJEQAKANoUAA==.',
Mo='Mohtavius:BAABLgAECn8WAAILAAYJTBHrFgALAQALAAYJTBHrFgALAQAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn8lAAITAAgJsgcIDAASAQATAAgJsgcIDAASAQAAAA==.Moonbaboon:BAAALgAECgcJCgAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Munkìe:BAAALgAECgIJAwABLgAECgYJGQAVAEENAA==.Muura:BAABLgAECn8eAAIUAAgJ2QsfggDcAAAUAAgJ2QsfggDcAAAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJCgAAAA==.',
Na='Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8bAAIFAAYJYBsOHwC6AQAFAAYJYBsOHwC6AQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJBgAAAA==.Negate:BAAALgAECgYJEQABLgAFFAYJGwAQAEEeAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAACAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgEJAgAAAA==.',
Ot='Otwin:BAAALgAECgQJBwAAAA==.',
Pa='Pahuum:BAAALgAECgIJAgAAAA==.Paimon:BAAALgAECgUJCAABLgAFFAQJDwARAFEZAA==.Paintrainn:BAAALgAECgYJDgAAAA==.Palewhiteman:BAABLgAECn8aAAIZAAgJ5BkQCwBgAgAZAAgJ5BkQCwBgAgAAAA==.Palleigh:BAAALgAECgYJEQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAAALgAECgYJDgAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAAALgAECgYJEAAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAAALgAECgYJDwAAAA==.Poplocndrop:BAAALgADCgcJFAAAAA==.',
Pr='Predaturd:BAAALgAECgMJAgAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAAALgAECgYJEQAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn8wAAIBAAkJnROiGQAFAgABAAkJnROiGQAFAgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgEJAgABLgAECgkJGwAUAPMcAA==.',
Re='Reihino:BAAALgADCgcJBwAAAA==.Resbak:BAAALgAECgcJCwAAAA==.Resiaus:BAABLgAECn8zAAIQAAkJ7RtBAgDgAgAQAAkJ7RtBAgDgAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgADCggJCwAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgAECgMJAwAAAA==.Roctheist:BAAALgAECgYJDwAAAA==.Rocthoeb:BAABLgAECn8xAAILAAkJxhH9EQDoAQALAAkJxhH9EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8dAAIcAAgJlx/OAgBvAgAcAAgJlx/OAgBvAgAAAA==.',
Sa='Saeris:BAAALgAECgMJAwAAAA==.Saintkhal:BAEALgAECgQJCAABLgAECggJEAACAAAAAA==.Saintmedicus:BAEALgAECggJEAAAAA==.Saintshammy:BAAALgAFFAEJAgAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIZAAcJeyJzEgB/AgAZAAcJeyJzEgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAAALgAECgYJEAAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAAALgAECgYJEAAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shinstabber:BAAALgAECgYJEAAAAA==.Shivantis:BAAALgADCgUJBQAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwACAAAAAA==.Shruggie:BAAALgAECgYJEwAAAA==.',
Si='Silven:BAAALgADCgUJBQAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAAALgAECgYJEAAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8bAAIBAAcJ3xVwLwD0AQABAAcJ3xVwLwD0AQAAAA==.',
Sm='Smidgen:BAAALgADCgcJCAAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8YAAISAAgJYAYCDQAcAQASAAgJYAYCDQAcAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAFADURAA==.Starlie:BAAALgAECgUJBQAAAA==.Stratacaster:BAAALgAECgMJBgAAAA==.Strawberry:BAAALgAECgUJCwAAAA==.Stuckinwell:BAACLgAFFH8FAAMEAAIJjxjmNQCnAAAEAAIJGBDmNQCnAAATAAEJkxaSEABXAAAuAAQKfxsAAwQACQn6GrkzAD0CAAQACAnpFrkzAD0CABMABQkNHD8YAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8KAAIOAAIJhh6LFQC3AAAOAAIJhh6LFQC3AAABLgAFFAYJGwAQAEEeAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDAAAAA==.Synsyn:BAAALgAECgQJCQAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8aAAIHAAgJKQ5EiQC/AQAHAAgJKQ5EiQC/AQAAAA==.',
Te='Teanfists:BAAALgAECgEJBAAAAA==.Temna:BAABLgAECn8ZAAIdAAYJLh6pMQC2AQAdAAYJLh6pMQC2AQAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAAALgAECgQJCgAAAA==.Thespaniard:BAABLgAECn8cAAIKAAcJOxmpEQC9AQAKAAcJOxmpEQC9AQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAAALgAECgUJBQAAAA==.Tinbasher:BAAALgAECgQJBgAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAAALgAECgYJBwAAAA==.Tricky:BAAALgAECgEJAQAAAA==.Triviousox:BAAALgAECgYJDwAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAECgYJBwACAAAAAA==.Twotvmage:BAABLgAECn8jAAMHAAgJyRh4KQD8AQAHAAgJyRh4KQD8AQAeAAEJIA3EDQA4AAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgADCgcJFQAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJCQABLgAECggJJwAEAOQZAA==.',
Up='Uplift:BAAALgAECgcJBwABLgAFFAYJEAAHAPgeAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAABLgAECn8XAAMfAAYJvw3PDgDTAAAfAAYJ0wvPDgDTAAANAAQJOA0KowDOAAAAAA==.Valky:BAAALgADCgQJBAABLgAECgYJFwAfAL8NAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAAALgAECgcJEgAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECgEJAQABLgAECgcJEgACAAAAAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn8ZAAIBAAYJjRjFNAB6AQABAAYJjRjFNAB6AQAAAA==.Vessna:BAAALgAECgQJCAABLgAECgQJCwACAAAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAAALgAECgQJBgAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgUJEAAAAA==.Vorttex:BAAALgAECgEJAQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAARAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAAALgAECgYJDgAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAQAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIKAAgJ4RsCEQB4AgAKAAgJ4RsCEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAAALgAFFAIJAgAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yu='Yuzuriha:BAAALgAECgQJCQAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgADCgYJBgAAAA==.',
Zo='Zophier:BAAALgADCgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAAALgAECgYJCgAAAA==.',
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

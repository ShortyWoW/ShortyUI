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

local lookup = {'DemonHunter-Devourer','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Mage-Arcane','DemonHunter-Havoc','Evoker-Preservation','Warrior-Fury','Monk-Windwalker','Paladin-Retribution','Priest-Discipline','Priest-Holy','Druid-Restoration','Druid-Balance','Warlock-Affliction','Druid-Feral','Hunter-Survival','Druid-Guardian','Rogue-Subtlety','Mage-Fire','Hunter-Marksmanship','Evoker-Augmentation','Warrior-Protection',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelothh:BAAALgAECgYJEAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIBAAcJyBqfMgAvAgABAAcJyBqfMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAAALgAECgYJDAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgEJAQAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAABLgAECn8VAAICAAcJIRtSDwAmAgACAAcJIRtSDwAmAgAAAA==.Akoni:BAAALgADCggJDgABLgAECgYJFAADAHgiAA==.',
Al='Allaris:BAABLgAECn8YAAIEAAYJwQTuegDRAAAEAAYJwQTuegDRAAAAAA==.Allíesin:BAAALgAECgQJBQAAAA==.Altryn:BAAALgAECgMJAwAAAA==.Alundrablaze:BAABLgAECn8UAAIFAAYJ7REiNgAyAQAFAAYJ7REiNgAyAQABLgAECgYJGAAEAMUNAA==.',
Am='Amarixa:BAAALgADCgcJCgABLgAECgQJBQAGAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAIHAAQJyxnbDABPAQAHAAQJyxnbDABPAQAuAAQKfzIAAgcACQlmIdgDALgCAAcACQlmIdgDALgCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.',
Ap='Apollis:BAAALgADCgcJBwAAAA==.',
Ar='Aranthino:BAAALgAECgYJCgAAAA==.Aryabhatta:BAABLgAECn8UAAIIAAYJ5yCSHwDeAQAIAAYJ5yCSHwDeAQAAAA==.',
As='Ashrom:BAAALgADCgkJDwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECgQJBAAAAA==.',
At='Athenarelia:BAAALgAFFAIJBAAAAA==.',
Ba='Backbush:BAAALgAECgMJAwAAAA==.Baelskrim:BAABLgAECn8UAAIJAAYJrR8hEwC/AQAJAAYJrR8hEwC/AQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn8zAAMKAAkJdiB8CQDJAgAKAAkJuR98CQDJAgALAAMJig7lMABVAAAAAA==.',
Be='Beansination:BAABLgAECn8WAAMJAAkJpxdeDAAVAgAJAAkJpxdeDAAVAgAFAAUJyBT0UQA9AQAAAA==.Beefsupriem:BAAALgAECgYJCwAAAA==.Bellatrïx:BAAALgAECgEJAQABLgAECgQJBQAGAAAAAA==.Belliaz:BAAALgAECgQJBQAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgADCgcJFAAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAECggJFwACAI0hAA==.',
Bl='Bloodlyfrost:BAABLgAECn8gAAIMAAgJ9wUsYgBNAQAMAAgJ9wUsYgBNAQAAAA==.Bloodyguthix:BAAALgADCgYJBgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJCQABLgAFFAMJBwANAKQFAA==.Breaknasweat:BAAALgAECgEJAQAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgADCgYJBgAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAQJCQAKANkbAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Candyquartz:BAAALgADCgcJFAAAAA==.',
Ce='Celladorne:BAAALgAECgcJCgAAAA==.',
Ch='Chibi:BAACLgAFFH8IAAIOAAMJeAEgBgC7AAAOAAMJeAEgBgC7AAAuAAQKfyQAAg4ACAlIE8gPALwBAA4ACAlIE8gPALwBAAAA.Chronokite:BAAALgAECggJDwAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Crushed:BAABLgAECn8UAAMPAAYJbRpfEwCwAQAPAAYJbRpfEwCwAQAEAAIJQQsSpQBxAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMFAAcJvBK0NAA5AQAFAAcJvBK0NAA5AQAJAAUJxwemZwCkAAABLgAECggJDwAGAAAAAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8kAAICAAkJrhV/DQA+AgACAAkJrhV/DQA+AgAAAA==.Darkfuse:BAAALgAECgIJAgAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgADCgQJBAAAAA==.Dayman:BAAALgAECgUJEgAAAA==.',
Db='Dbk:BAAALgAECgQJBgAAAA==.',
De='Deader:BAAALgAECggJCQAAAA==.Deadlyydot:BAAALgAECgMJCgAAAA==.Deadlyykiss:BAABLgAECn8WAAIQAAYJtQULBwDXAAAQAAYJtQULBwDXAAAAAA==.Deathhowl:BAAALgAECgEJAQAAAA==.Demonsaber:BAAALgAECgIJAgAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8UAAMRAAYJ7AlzHQDtAAARAAYJ7AlzHQDtAAABAAQJ2wSfiACAAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgIJAgAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAABLgAECn8ZAAIIAAcJ5wxtPgBUAQAIAAcJ5wxtPgBUAQAAAA==.Displace:BAAALgAECgMJBAAAAA==.Divish:BAABLgAECn8dAAISAAkJohlxBQBCAgASAAkJohlxBQBCAgAAAA==.',
Do='Dogan:BAAALgADCgYJEgAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgADCgMJAgAAAA==.',
Dr='Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJCAAAAA==.Droggnoir:BAAALgADCgEJAQABLgAECggJEwAGAAAAAA==.Druecc:BAABLgAECn8WAAIMAAYJoROWYQBOAQAMAAYJoROWYQBOAQAAAA==.Druidlord:BAAALgAECgUJCQAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECgcJCAAAAA==.Dumplíng:BAAALgADCgUJBQABLgAECgYJDAAGAAAAAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgIJAgAGAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAQAAAA==.',
Ed='Edgerallen:BAAALgAECggJEwAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJDwAGAAAAAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgcJCQAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.',
Er='Era:BAABLgAECn8UAAITAAYJwxjsHACBAQATAAYJwxjsHACBAQAAAA==.',
Ex='Executions:BAAALgADCgEJAgAAAA==.',
Fa='Fanara:BAAALgAECgEJAQAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAAALgAECgYJEQAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgMJAwAAAA==.Felbládes:BAAALgAECgMJAwAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8aAAIUAAYJpBsEFQCEAQAUAAYJpBsEFQCEAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Fitua:BAABLgAECn8fAAIKAAkJiQstZQAZAQAKAAkJiQstZQAZAQAAAA==.Fizzbann:BAAALgADCgkJDwABLgAECgYJFAADAHgiAA==.',
Fk='Fkingbeast:BAAALgAFFAcJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgAECggJDgAAAA==.Foutre:BAAALgAECgYJEQAAAA==.',
Fr='Fruntstabba:BAAALgADCgcJDQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzytotems:BAAALgAECgQJBwAAAA==.',
['Få']='Fång:BAAALgAECgYJDAAAAA==.',
Ga='Garo:BAABLgAECn8uAAIOAAgJrh9OBAAoAgAOAAgJrh9OBAAoAgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8hAAIVAAgJVCHJDQCRAgAVAAgJVCHJDQCRAgAAAA==.',
Gh='Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.',
Gl='Glert:BAABLgAECn8WAAIMAAcJSxAXngCaAQAMAAcJSxAXngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQNAAkJcQYHHABbAQANAAkJcQYHHABbAQAWAAYJAwS5NQD3AAAXAAYJUAIrVQDiAAAAAA==.Goinsolo:BAAALgAFFAEJAQAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMYAAgJzBnwHwBCAgAYAAgJzBnwHwBCAgAZAAUJeQ6VTQDzAAAAAA==.Gorvax:BAABLgAECn8YAAILAAYJdRhJEwBAAQALAAYJdRhJEwBAAQAAAA==.',
Gr='Grimnyx:BAAALgADCgUJBQAAAA==.Grimstout:BAAALgADCgMJAwAAAA==.Gripe:BAAALgADCgMJAwAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJFwAIAK4gAA==.',
Gw='Gwenledyr:BAABLgAECn8sAAQEAAkJ5xYGGAAiAgAEAAkJqxQGGAAiAgAPAAUJBhHqFACpAAAaAAIJFRsoHQCIAAAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEAAGAAAAAA==.Heimthrall:BAABLgAECn8iAAIVAAgJzwoETABhAQAVAAgJzwoETABhAQAAAA==.Hekatee:BAAALgADCgYJCgAAAA==.Hekkruk:BAAALgADCgcJCQABLgAECggJIgAbAAIdAA==.Henshin:BAABLgAECn8aAAMYAAYJDSM6FwALAgAYAAYJDSM6FwALAgAZAAYJnhOjHwA5AQAAAA==.Herak:BAABLgAECn8eAAIcAAcJMgvKFABuAQAcAAcJMgvKFABuAQAAAA==.Hermiecrabbs:BAAALgADCgUJBQAAAA==.',
Hi='Highchairjr:BAABLgAECn8ZAAMPAAYJtxmAMQDzAAAEAAUJHRdsaAD8AAAPAAUJihaAMQDzAAAAAA==.Hildaelf:BAAALgADCgkJEQABLgAECgYJFAADAHgiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8hAAICAAcJPR8BDQBEAgACAAcJPR8BDQBEAgAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJAwAAAA==.Horazi:BAAALgAECgEJAQABLgAECgcJFQACACEbAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ii='Iil:BAABLgAECn8YAAMMAAYJJBNCZQBHAQAMAAYJJBNCZQBHAQAQAAEJFRSVGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgYJGAAMACQTAA==.',
Is='Istor:BAAALgAECgUJCAAAAA==.',
Ja='Jaxxia:BAABLgAECn8WAAICAAYJxQ1dLAAtAQACAAYJxQ1dLAAtAQAAAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAAALgAECgYJEwAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgADCggJDgAAAA==.',
Jo='Joesphkony:BAAALgADCgUJBQAAAA==.Jorick:BAAALgAECgQJBwAAAA==.',
Ju='Ju:BAAALgAECgYJDwAAAA==.Juzodots:BAAALgADCgUJBQAAAA==.Juzomido:BAACLgAFFH8MAAIcAAQJmBD9CwAbAQAcAAQJmBD9CwAbAQAuAAQKfyQAAhwACQlsHJMEAM0CABwACQlsHJMEAM0CAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn8gAAIUAAgJaxZ9DQDgAQAUAAgJaxZ9DQDgAQAAAA==.Kaline:BAABLgAECn8XAAIdAAgJ4xqoBgBcAgAdAAgJ4xqoBgBcAgAAAA==.Karupted:BAAALgAECgYJEgAAAA==.Katianna:BAABLgAECn8jAAIFAAkJtxmpCQCSAgAFAAkJtxmpCQCSAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAAALgAECgYJEAAAAA==.Keola:BAAALgADCgUJBQABLgAECgYJBgAGAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8YAAIXAAYJFxffHABjAQAXAAYJFxffHABjAQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAAALgAECgcJEQAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.',
Ko='Koraena:BAAALgAECgUJCQAAAA==.Koronuss:BAAALgADCgEJAQAAAA==.',
Kr='Krivgar:BAAALgAECgYJDQAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgEJAgAAAA==.',
Ku='Kulrig:BAACLgAFFH8HAAMNAAMJpAWsEQCTAAANAAMJpAWsEQCTAAAXAAIJFQePGQB0AAAuAAQKfzoABBcACAnqGFsfAOYBABcABwlxF1sfAOYBAA0ABwm+GikQAM4BABYAAQkNBuZMACgAAAAA.Kurwa:BAAALgADCgMJAwAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgYJEwAGAAAAAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEAAGAAAAAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgADCgYJCQABLgAECgYJFAADAHgiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgADCgUJCgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8aAAIeAAkJmB3FFwBKAgAeAAkJmB3FFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8fAAIVAAgJwBjeIgD6AQAVAAgJwBjeIgD6AQAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgUJBgAAAA==.Mathelmana:BAABLgAECn8YAAMEAAYJxQ0xWgAfAQAEAAYJCQ0xWgAfAQAaAAQJeQ0RFQDgAAAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgADCgIJAgAAAA==.',
Mi='Miliandra:BAAALgADCgMJBQAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8cAAINAAgJnwkvGwBiAQANAAgJnwkvGwBiAQAAAA==.Miseral:BAABLgAECn8oAAIRAAgJ8B0BBwAwAgARAAgJ8B0BBwAwAgAAAA==.Missfrost:BAAALgAECgIJBwAAAA==.Mitzy:BAAALgADCgEJAQAAAA==.',
Mo='Moganchee:BAABLgAECn8cAAMMAAgJ1gSBbAA4AQAMAAgJ1gSBbAA4AQAfAAcJCgJmCADiAAAAAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAMJBwANAKQFAA==.Morghella:BAABLgAECn8nAAIIAAkJFxvyCQCYAgAIAAkJFxvyCQCYAgAAAA==.Morticiaa:BAAALgADCgEJAgAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgADCgUJCgAAAA==.Mythros:BAAALgADCgMJBAAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJBQAAAA==.Nesmae:BAAALgAECgcJDAABLgAFFAIJBQAIAHYYAA==.',
Ni='Nightwitch:BAAALgAECgEJAQAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8FAAIIAAIJdhjlMgC4AAAIAAIJdhjlMgC4AAAuAAQKfzAAAggACQkcI30MANwCAAgACQkcI30MANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECggJDQAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgUJBQAAAA==.',
Ol='Oleyinka:BAAALgAECgQJBgAAAA==.',
Om='Omnissiah:BAABLgAECn8WAAIXAAYJVRWsLQCPAQAXAAYJVRWsLQCPAQAAAA==.',
On='Once:BAAALgAECgUJCQAAAA==.Oneyedemon:BAAALgADCggJCAAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgYJEgAGAAAAAA==.',
Op='Opaths:BAABLgAECn8cAAIKAAgJvxz/IQD+AQAKAAgJvxz/IQD+AQAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn8YAAIDAAYJdh54CQCuAQADAAYJdh54CQCuAQAAAA==.',
Pa='Palaremix:BAAALgADCgEJAQAAAA==.',
Pe='Peng:BAAALgAECggJEwAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAECggJFwACAI0hAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Priedorei:BAAALgADCgIJAgAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgYJBgAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAAALgAECggJDgAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJBgAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAAALgAECgIJAQAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8ZAAICAAcJCxyBEgACAgACAAcJCxyBEgACAgAAAA==.Raydoink:BAAALgADCgUJBwAAAA==.',
Re='Reighan:BAAALgADCgUJBQAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgEJAgAAAA==.Revolting:BAABLgAFFH8MAAIBAAUJzwwhJgAYAQABAAUJzwwhJgAYAQAAAA==.Reze:BAAALgADCgcJBwABLgAECggJHwAgADshAA==.Rezme:BAAALgADCggJDAAAAA==.',
Ri='Rianne:BAAALgAECgMJAwAAAA==.Rizeen:BAAALgAECgYJCwAAAA==.',
Ro='Rowanbow:BAAALgAECgQJBAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8kAAMYAAgJYBzSCwCNAgAYAAgJYBzSCwCNAgAZAAIJtQSwXgApAAAAAA==.',
Sa='Saberhawk:BAAALgAECgYJBwAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakurazuka:BAABLgAECn8WAAIEAAYJ5AwKgwBUAQAEAAYJ5AwKgwBUAQAAAA==.Salaminizer:BAAALgAECgEJAwAAAA==.Samidudu:BAABLgAECn8UAAIdAAcJWBNlDQA1AQAdAAcJWBNlDQA1AQAAAA==.Sanath:BAABLgAECn8kAAIhAAkJwA72EgCyAQAhAAkJwA72EgCyAQAAAA==.Sanctusdeus:BAAALgAECgUJCwAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECggJJQAcALwVAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIZAAcJdiRKHwAFAgAZAAcJdiRKHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8YAAIOAAYJOyB6BwC5AQAOAAYJOyB6BwC5AQAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAMJBwANAKQFAA==.Sevotharte:BAAALgAECgIJAgAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgMJBQAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8LAAIFAAMJayQjEQA5AQAFAAMJayQjEQA5AQAuAAQKfx4AAgUACQkII/gAAIkDAAUACQkII/gAAIkDAAAA.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIbAAkJGhlHAwBZAgAbAAkJGhlHAwBZAgAAAA==.',
Si='Sib:BAAALgAECgEJAQAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgYJDgAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8UAAIVAAYJLhbuTwBWAQAVAAYJLhbuTwBWAQAAAA==.Snke:BAAALgADCgcJBwABLgAECgYJFAAVAC4WAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8rAAIKAAkJnB5PEwBhAgAKAAkJnB5PEwBhAgAAAA==.Sonofgods:BAABLgAECn8WAAIIAAYJ5RFKRQA9AQAIAAYJ5RFKRQA9AQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgEJAQABLgAECgYJDwAGAAAAAA==.',
Sp='Spectrahl:BAABLgAECn8bAAIJAAgJSxDAGgB5AQAJAAgJSxDAGgB5AQABLgAFFAIJBQAIAHYYAA==.Spedspidspud:BAAALgAECgYJDgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECggJIQANAN0PAA==.',
St='Starrbuck:BAABLgAECn8YAAIYAAYJGgVKWwCvAAAYAAYJGgVKWwCvAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8WAAIcAAgJaxFzDQDOAQAcAAgJaxFzDQDOAQAAAA==.Stryke:BAABLgAECn8UAAIXAAYJThpxEwDAAQAXAAYJThpxEwDAAQAAAA==.',
Su='Sunfury:BAAALgAECgEJAgAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgIJAgAAAA==.Suterareta:BAAALgAECgYJDQAAAA==.',
Sy='Sylareith:BAAALgAECgYJCgAAAA==.Syntara:BAABLgAECn8kAAIOAAkJIRpOAgCLAgAOAAkJIRpOAgCLAgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taksun:BAABLgAECn8gAAIdAAgJVhaBCQCLAQAdAAgJVhaBCQCLAQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn8lAAILAAgJ2AwEFwAYAQALAAgJ2AwEFwAYAQAAAA==.Tav:BAAALgAFFAIJAgAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8UAAMDAAYJeCKFBwDeAQADAAYJeCKFBwDeAQAVAAUJug+6fwDsAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.',
Ti='Tianara:BAABLgAECn8XAAMCAAgJjSHxBAAdAwACAAgJjSHxBAAdAwADAAQJPhVmKgC4AAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJCgAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJBAAAAA==.Tolerabull:BAABLgAECn8aAAICAAYJYhtXFgDbAQACAAYJYhtXFgDbAQAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8pAAIBAAgJ0RlYFgAJAgABAAgJ0RlYFgAJAgAAAA==.Trojaan:BAAALgAECgkJDgAAAA==.Trulisha:BAAALgAECgYJEAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgIJAgAAAA==.',
Ue='Uelfaen:BAAALgADCgUJBQAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8aAAILAAkJZAa/FgAaAQALAAkJZAa/FgAaAQAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAAALgAECgYJCgAAAA==.',
Va='Vaderon:BAAALgAECgUJCAAAAA==.Vaelanar:BAAALgADCgUJBQAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8IAAIDAAMJjwgnBwCVAAADAAMJjwgnBwCVAAAuAAQKfyUAAgMACAlIFp4VAHYBAAMACAlIFp4VAHYBAAAA.Vaynitee:BAAALgADCgQJBAAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgYJGAALAHUYAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECgUJBQAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAECggJJgAFAKolAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8ZAAILAAgJrxJ9EABqAQALAAgJrxJ9EABqAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8aAAIIAAcJnhIIRABBAQAIAAcJnhIIRABBAQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgYJDgAGAAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8hAAMNAAgJ3Q8cGgBrAQANAAgJ3Q8cGgBrAQAWAAcJwQ8gKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgMJAwAAAA==.',
Ws='Wselfwulf:BAAALgADCgYJCwABLgAECgYJFAADAHgiAA==.',
Xa='Xanadaria:BAAALgAECgQJBQAAAA==.Xanalluna:BAAALgADCgkJCQABLgAECgQJBQAGAAAAAA==.Xandrelyra:BAAALgADCgMJAwABLgAECgQJBQAGAAAAAA==.',
Xe='Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgADCgYJCgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgIJAgABLgAECgQJCAAGAAAAAA==.Yakushimaru:BAABLgAECn8lAAIZAAgJbR6kBwBaAgAZAAgJbR6kBwBaAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgEJAQAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8FAAIVAAMJ6xGCLwD3AAAVAAMJ6xGCLwD3AAAAAA==.Zeith:BAABLgAECn8bAAIiAAkJeBQvCQDjAQAiAAkJeBQvCQDjAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAABLgAECn8iAAIbAAgJAh2xAwBEAgAbAAgJAh2xAwBEAgAAAA==.',
Zy='Zyphoros:BAAALgADCgkJCgAAAA==.',
['Äz']='Äzúlà:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAAALgAECgYJEgAAAA==.',
['Ìt']='Ìta:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðeadlymyth:BAAALgADCgEJAQAAAA==.',
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

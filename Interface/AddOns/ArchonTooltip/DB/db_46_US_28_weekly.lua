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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Druid-Balance','Priest-Discipline','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','Druid-Guardian','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','DeathKnight-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Mage-Fire','Warrior-Arms','DemonHunter-Vengeance','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8dAAMCAAgJLRO/KwC1AQACAAgJLRO/KwC1AQADAAEJAAAGgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPkYAA==.Acidrain:BAABLgAECn8oAAIFAAgJuiBhBQCZAgAFAAgJuiBhBQCZAgAAAA==.Acmiax:BAABLgAECn8YAAMGAAcJShomeACKAQAGAAYJZBgmeACKAQABAAUJuQsoNQD2AAAAAA==.',
Ad='Adar:BAAALgAECgQJBAAAAA==.',
Ae='Aep:BAAALgAECgUJCQABLgADCgcJDwAHAAAAAA==.',
Ah='Ahrmanhamma:BAACLgAFFH8GAAIGAAQJpBgcDwBrAQAGAAQJpBgcDwBrAQAuAAQKfxoAAgYACQksIvEDABUDAAYACQksIvEDABUDAAAA.Ahu:BAABLgAECn8nAAMEAAgJrxcsMADwAQAEAAgJrxcsMADwAQAIAAMJZAQccwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJCAAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn8yAAMEAAkJbQ94HADyAQAEAAkJxg54HADyAQAIAAgJnwwUNQCVAQAAAA==.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIJAAkJhhruJgDXAgAJAAkJhhruJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAIKAAkJIw8yCgABAgAKAAkJIw8yCgABAgAAAA==.Allaria:BAAALgAECgMJAwAAAA==.',
Am='Ambassador:BAABLgAECn8eAAILAAkJkhemBAA2AgALAAkJkhemBAA2AgAAAA==.Amoondai:BAACLgAFFH8NAAIMAAMJDyE0CgAjAQAMAAMJDyE0CgAjAQAuAAQKfzMAAgwACQmaItsDABoDAAwACQmaItsDABoDAAAA.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8uAAMNAAgJICHdAwCKAgANAAgJICHdAwCKAgAOAAYJ7wNj0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIPAAkJLSGxAwAyAwAPAAkJLSGxAwAyAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Ba='Bacstabath:BAABLgAECn8jAAIQAAkJoBwVBgAvAwAQAAkJoBwVBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJBgAGAKQYAA==.Banshee:BAABLgAECn8eAAIRAAkJ0x/iBQDNAgARAAkJ0x/iBQDNAgAAAA==.',
Be='Becca:BAABLgAECn8mAAILAAgJ5BUICQC4AQALAAgJ5BUICQC4AQAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigdamaj:BAABLgAECn8kAAIOAAkJBhSxIQAAAgAOAAkJBhSxIQAAAgAAAA==.Birbdormu:BAAALgAECgQJBAABLgAECgkJJgASAHQcAA==.',
Bl='Bloodiblind:BAAALgAECgMJAwAAAA==.Bloodios:BAABLgAECn8nAAINAAkJHBovBQBaAgANAAkJHBovBQBaAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobin:BAAALgADCgcJCAABLgAECgkJHQATAOkQAA==.Bobinforapl:BAABLgAECn8dAAITAAkJ6RDYDgDkAQATAAkJ6RDYDgDkAQAAAA==.Bombadil:BAABLgAECn8oAAITAAgJJwTHHQA+AQATAAgJJwTHHQA+AQAAAA==.',
Br='Bribage:BAABLgAECn8mAAMSAAkJdBxUBQCUAgASAAkJdBxUBQCUAgAPAAEJtyEidwBgAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAHAAAAAA==.Budderwar:BAABLgAECn8rAAMUAAkJBiZtAABjAwAUAAkJBiZtAABjAwAVAAMJvw4ChwCjAAAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.',
Cb='Cbreezy:BAAALgAECgEJAQAAAA==.',
Ce='Celjska:BAAALgAECgQJBAAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8XAAMFAAcJUg7fQABGAQAFAAYJjw/fQABGAQAWAAcJkwpfNgAwAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgADCgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgEJAQAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8lAAIXAAgJySX3AQADAwAXAAgJySX3AQADAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIYAAkJdw4MDQA8AQAYAAkJdw4MDQA8AQAAAA==.Corrail:BAAALgAECgUJBQAAAA==.Correin:BAABLgAECn8bAAIZAAkJcg22EQBsAQAZAAkJcg22EQBsAQAAAA==.',
Cr='Craszhin:BAAALgAECggJEwAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn8qAAIJAAkJIwyjNwDEAQAJAAkJIwyjNwDEAQAAAA==.',
Da='Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.',
De='Deets:BAABLgAECn8lAAIEAAgJVSBpCwCFAgAEAAgJVSBpCwCFAgAAAA==.Defoy:BAABLgAECn8WAAMIAAYJIRnFDQAPAQAIAAYJ4hbFDQAPAQAEAAQJYhC9gQCUAAAAAA==.Demona:BAABLgAECn8oAAMDAAgJMAqQCQA+AQADAAgJMAqQCQA+AQACAAYJWgM0hgC5AAAAAA==.Demonicfates:BAABLgAECn8ZAAIZAAcJtw6vFABGAQAZAAcJtw6vFABGAQAAAA==.Derffy:BAABLgAECn8YAAIaAAYJLhyICAClAQAaAAYJLhyICAClAQAAAA==.Descalabrada:BAAALgAECgQJCAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgMJAwAAAA==.',
Dm='Dmt:BAABLgAECn8eAAIbAAgJyBf1EADiAQAbAAgJyBf1EADiAQAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8fAAMPAAgJUwn7OAAyAQAPAAgJUwn7OAAyAQAYAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgEJBQAAAA==.',
Ec='Eclair:BAABLgAECn8oAAMWAAgJFxVtGgDeAQAWAAgJFxVtGgDeAQAFAAMJYhjbNgDSAAAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJIwAQAKAcAA==.',
El='Eleysia:BAAALgADCgUJBgAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8kAAIXAAkJDB0JCAD5AgAXAAkJDB0JCAD5AgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgYJFgAJAKsLAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACQeAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJB5aHAAvAgAFAAkJJB5aHAAvAgAWAAcJQQvZTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACQeAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAHAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8gAAIZAAgJnRSyDAC2AQAZAAgJnRSyDAC2AQAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgEJAQABLgAECgUJBQAHAAAAAA==.Ferg:BAAALgAECgQJBAABLgAECggJKAAJANAiAA==.Fergis:BAABLgAECn8oAAIJAAgJ0CItDwCjAgAJAAgJ0CItDwCjAgAAAA==.Fetchme:BAAALgAECgMJAwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8bAAMNAAkJCBc5EgDoAQANAAkJ+hY5EgDoAQAcAAYJ4xRCCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEAAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgADCgcJFwAAAA==.Frostymonk:BAABLgAECn8WAAIbAAYJIwlFLwDcAAAbAAYJIwlFLwDcAAAAAA==.Frozenwaffle:BAAALgAECgQJBQABLgAECgkJIwAdAGIhAA==.',
Fu='Furryben:BAAALgADCgkJGgAAAA==.',
Ga='Galeste:BAAALgAECgQJBAAAAA==.',
Gi='Gigem:BAAALgAECgUJCwAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQeAAkJkASPIwBcAQAeAAkJkASPIwBcAQAfAAUJ9gP3SgCoAAAgAAEJlQH4GgAaAAAAAA==.Glarious:BAAALgAECgYJDQABLgAECgkJGwAeAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8jAAMdAAkJYiEPDQCyAgAdAAkJYiEPDQCyAgAMAAYJwBTANQBmAQAAAA==.Grôg:BAAALgAECgUJAwABLgAECgcJBwAHAAAAAA==.',
Gu='Guldaniel:BAAALgADCgkJHwAAAA==.Guthx:BAABLgAECn8eAAIPAAkJyxggEgA9AgAPAAkJyxggEgA9AgAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAHAAAAAA==.',
Ho='Holymolii:BAABLgAECn8fAAILAAgJyhUXCgChAQALAAgJyhUXCgChAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8XAAQKAAcJQBb/EwB4AQAKAAYJ4hb/EwB4AQAIAAUJRxh5RABDAQAEAAEJEBLqtQA8AAABLgAECgkJKwAUAAYmAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAAALgAECgUJDgAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJGwAJAJkWAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8hAAIhAAkJlhNAAgAOAgAhAAkJlhNAAgAOAgAAAA==.Istayblunted:BAABLgAECn8bAAILAAcJrR8READEAQALAAcJrR8READEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAHweAA==.',
Ji='Jiayerah:BAAALgAECgIJAgABLgAECgYJFwAMAPkhAA==.Jinkuzo:BAABLgAECn8mAAIiAAgJeiBBBgB1AgAiAAgJeiBBBgB1AgAAAA==.Jinmu:BAABLgAECn8lAAMQAAgJ7BMjDQDPAQAQAAgJ7BMjDQDPAQAjAAEJJgvUGQA6AAAAAA==.',
Ju='Juggie:BAABLgAECn8fAAIMAAgJUhJTEwDBAQAMAAgJUhJTEwDBAQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8kAAIjAAkJVgumBQCdAQAjAAkJVgumBQCdAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJfxoiDQCEAgACAAkJVBoiDQCEAgADAAEJFBvMawA8AAAAAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECgYJCgABLgAECgkJIAAiANYZAA==.',
Kl='Klodar:BAAALgAECgEJAQAAAA==.Klum:BAAALgADCgcJEwAAAA==.',
Kr='Krazee:BAAALgADCgEJAQAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJCwAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgIJAgAAAA==.Lendela:BAAALgAECgQJBwAAAA==.',
Li='Liljugg:BAAALgAECgYJDAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgADCgcJDwAAAA==.Lor:BAAALgAECgQJBQAAAA==.Lostmana:BAAALgAECgIJAgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Ly='Lygor:BAABLgAECn8fAAIEAAgJFw9hLACdAQAEAAgJFw9hLACdAQAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Majellan:BAAALgAECgMJBgAAAA==.Makrub:BAAALgAECggJDQAAAA==.Mandigosa:BAAALgAECgIJAgAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marsawn:BAABLgAECn8gAAMdAAkJ5BfPBgBnAgAdAAkJ5BfPBgBnAgAMAAMJYBjcLgDWAAAAAA==.',
Mc='Mcpeepants:BAAALgAECgIJAgABLgAFFAQJBgAGAKQYAA==.',
Me='Meqi:BAABLgAECn8XAAMJAAYJ0hxSSgCJAQAJAAYJ0hxSSgCJAQAkAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8dAAMKAAgJcg9pDQDPAQAKAAgJcg9pDQDPAQAIAAYJXwmSTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8oAAIVAAkJ1CHXAgDqAgAVAAkJ1CHXAgDqAgAAAA==.Mineralelf:BAABLgAECn8oAAIEAAkJpAogLgCWAQAEAAkJpAogLgCWAQAAAA==.Minichaos:BAABLgAECn8VAAMDAAYJthJGDgDuAAADAAYJthJGDgDuAAACAAQJfQZmhQC7AAAAAA==.Miriam:BAAALgAECgYJEAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIqBwD5AgABAAgJvCIqBwD5AgAAAA==.',
Mo='Mojosavage:BAAALgAECgcJEgAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgADCgEJAQAAAA==.Mortshan:BAABLgAECn8bAAIkAAkJQBbzAABFAgAkAAkJQBbzAABFAgAAAA==.Mournfull:BAAALgAECgEJAQAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgQJCgAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgADCgMJAwAAAA==.Nikru:BAAALgAECgMJAwABLgAFFAUJDgAPAAIPAA==.Ninok:BAAALgAFFAEJAQAAAA==.',
No='Nornee:BAABLgAECn8XAAIWAAcJjA7aSgBXAQAWAAcJjA7aSgBXAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIaAAgJRR3vAwA5AgAaAAgJRR3vAwA5AgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8ZAAMVAAcJkBGFHwBvAQAVAAcJghGFHwBvAQAlAAEJ4wwDPwAxAAAAAA==.',
Ol='Ollïee:BAAALgAECgUJBQAAAA==.',
Op='Oprawyndfury:BAAALgAECgMJAwAAAA==.',
Or='Orceo:BAABLgAECn8gAAIEAAkJ+iPHBQAxAwAEAAkJ+iPHBQAxAwAAAA==.Orkreghar:BAAALgAECgEJAQAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwAAAA==.',
Ox='Oxcanor:BAAALgADCgkJDwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJkh+0TgDcAQACAAYJkh+0TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJKwAUAAYmAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8hAAIFAAkJxAaDJwAgAQAFAAkJxAaDJwAgAQAAAA==.Popple:BAABLgAECn8gAAIVAAgJDgzpGwCJAQAVAAgJDgzpGwCJAQAAAA==.Potential:BAABLgAECn8aAAIiAAgJIxuBDAD7AQAiAAgJIxuBDAD7AQAAAA==.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJCgAAAA==.Puggsly:BAAALgADCgkJDAAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIdAAcJxAztIAA3AQAdAAcJxAztIAA3AQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8ZAAIVAAcJPxlPFgC1AQAVAAcJPxlPFgC1AQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Reishirome:BAAALgADCgkJJgAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIYAAgJOSIZAwDlAgAYAAgJOSIZAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8YAAISAAgJ3ATyKAD7AAASAAgJ3ATyKAD7AAAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgAECgUJBQAAAA==.',
Ru='Rumincoke:BAAALgADCgkJCwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8XAAIMAAYJ+SF0CgBAAgAMAAYJ+SF0CgBAAgAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAHAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8lAAITAAkJ6xWfCABSAgATAAkJ6xWfCABSAgAAAA==.',
Sh='Shadowhntr:BAAALgAECgEJAQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shavedussy:BAAALgADCgUJBQAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgUJCAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smogcheck:BAACLgAFFH8FAAIeAAMJSw6BEwDUAAAeAAMJSw6BEwDUAAAuAAQKfyAAAx4ACAkgFGMbAK0BAB4ACAkgFGMbAK0BACAAAQl9CMw+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8fAAIPAAgJSRysDACBAgAPAAgJSRysDACBAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh46BAC7AgAFAAkJyh46BAC7AgAWAAEJFgL4igAiAAAAAA==.Snowws:BAABLgAECn8WAAIRAAgJqhqwOAASAgARAAgJqhqwOAASAgAAAA==.',
So='Sortis:BAABLgAECn8bAAIJAAkJmRbbMwCjAgAJAAkJmRbbMwCjAgAAAA==.',
Sp='Spongerunner:BAAALgAECgUJDQAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn8aAAIEAAcJvhO0MgCDAQAEAAcJvhO0MgCDAQAAAA==.Strigo:BAABLgAFFH8KAAQKAAQJAxYCBwBbAQAKAAQJAxYCBwBbAQAEAAEJIxm5IABfAAAIAAEJnwyuKABKAAAAAA==.',
Su='Subway:BAAALgAECgcJDQAAAA==.Sunbaby:BAABLgAECn8fAAImAAgJmx6FAgBTAgAmAAgJmx6FAgBTAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDAAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAITAAkJcSBFBQD9AgATAAkJcSBFBQD9AgAAAA==.Talas:BAABLgAECn8hAAMEAAkJgRpHDwDBAgAEAAkJgRpHDwDBAgAIAAUJswruVwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temerald:BAAALgADCgkJCQAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAECggJGQAOAAIjAA==.Thrann:BAABLgAECn8ZAAMOAAgJAiOaOgBNAgAOAAcJqCKaOgBNAgAcAAEJHiVwEABwAAAAAA==.Thunderdex:BAACLgAFFH8KAAMRAAYJmBhlCQCqAQARAAYJmBhlCQCqAQAZAAEJ6APFFABCAAAuAAQKfxgAAhEACQmOGWgcAKgCABEACQmOGWgcAKgCAAAA.',
Ti='Tirium:BAAALgAECgEJAQAAAA==.',
To='Togglesmith:BAAALgADCgMJAwAAAA==.Togglestein:BAAALgADCgYJDQAAAA==.Togglethorp:BAAALgADCgYJDAAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgQJBwAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJBwAAAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vallius:BAABLgAECn8dAAIQAAkJ4xLsBwApAgAQAAkJ4xLsBwApAgAAAA==.Vanargandr:BAAALgAECgUJBQAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJHhqSDACLAgACAAkJHhqSDACLAgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn8lAAMWAAkJKBeIGADtAQAWAAgJ2BWIGADtAQAFAAIJDQTyYgA0AAAAAA==.',
Wa='Waffletoast:BAAALgADCgcJCAABLgAECgkJIwAdAGIhAA==.Wanders:BAABLgAECn8bAAMJAAgJLRITOQC+AQAJAAgJ0hETOQC+AQAnAAYJLAmbCwAcAQAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwAAAA==.',
Xa='Xannies:BAABLgAECn8mAAInAAYJSgWPDQDvAAAnAAYJSgWPDQDvAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAABLgAECn8bAAIGAAkJ7yPnAQBNAwAGAAkJ7yPnAQBNAwAAAA==.Yesenìa:BAAALgADCgEJAQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn8nAAQgAAgJfh98AQB3AgAgAAgJfh98AQB3AgAfAAMJ4Q9gSwCmAAAeAAEJ9wHMLgAbAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn8oAAIoAAgJaQYwDABHAQAoAAgJaQYwDABHAQAAAA==.Zillyanna:BAAALgAECgcJEQAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgMJAwAAAA==.Zywol:BAABLgAECn8cAAMSAAkJ7RVrEADMAQASAAkJ7RVrEADMAQAPAAMJlgbCpgB6AAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8WAAIJAAYJqwuhfQAWAQAJAAYJqwuhfQAWAQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCAAAAA==.Ðespair:BAABLgAECn8tAAQTAAgJxSEhCgCWAgATAAcJPSEhCgCWAgAdAAgJNx+WGgBnAQAMAAUJlhikKQD+AAAAAA==.',
['Ðr']='Ðream:BAAALgAECgYJCQAAAA==.',
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

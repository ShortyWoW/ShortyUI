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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Hunter-Marksmanship','Unknown-Unknown','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Druid-Balance','Priest-Discipline','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','Druid-Guardian','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Mage-Fire','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Shaman-Enhancement',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8bAAMCAAgJXBF/JgCVAQACAAgJXBF/JgCVAQADAAEJAAAFgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPkYAA==.Acidrain:BAABLgAECn8gAAIFAAgJGRvUCQD+AQAFAAgJGRvUCQD+AQAAAA==.Acmiax:BAAALgAECgUJEQAAAA==.',
Ad='Adar:BAAALgADCgcJBwAAAA==.',
Ah='Ahrmanhamma:BAABLgAECn8YAAIGAAkJ3x8xBADcAgAGAAkJ3x8xBADcAgAAAA==.Ahu:BAABLgAECn8nAAMEAAgJrxcpMADwAQAEAAgJrxcpMADwAQAHAAMJZAQLcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgIJAgAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAIAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJBQAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn8pAAMEAAgJMg4EIwCRAQAHAAgJnwxINQCSAQAEAAgJhwoEIwCRAQAAAA==.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIJAAkJhhruJgDXAgAJAAkJhhruJgDXAgAAAA==.Alexijones:BAABLgAECn8ZAAIKAAcJQRCXDQCGAQAKAAcJQRCXDQCGAQAAAA==.Allaria:BAAALgADCgUJCQAAAA==.',
Am='Ambassador:BAABLgAECn8aAAILAAcJwhruBQDPAQALAAcJwhruBQDPAQAAAA==.Amoondai:BAACLgAFFH8KAAIMAAMJExyfCAAOAQAMAAMJExyfCAAOAQAuAAQKfzIAAgwACQmaItsDABoDAAwACQmaItsDABoDAAAA.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8mAAMNAAgJHSGHAgBBAgANAAgJHSGHAgBBAgAOAAYJ7wNg0gDcAAAAAA==.Apolyon:BAABLgAECn8kAAIPAAkJLCEkAgA7AwAPAAkJLCEkAgA7AwAAAA==.',
Ar='Araon:BAAALgADCgEJAgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Ba='Bacstabath:BAABLgAECn8jAAIQAAkJoBwVBgAvAwAQAAkJoBwVBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAECgkJGAAGAN8fAA==.Banshee:BAABLgAECn8aAAIRAAcJ6h4TDgAGAgARAAcJ6h4TDgAGAgAAAA==.',
Be='Becca:BAABLgAECn8eAAILAAcJ6xbHEAC6AQALAAcJ6xbHEAC6AQAAAA==.',
Bi='Bigdamaj:BAABLgAECn8hAAIOAAgJiBVoIgC5AQAOAAgJiBVoIgC5AQAAAA==.Birbdormu:BAAALgAECgQJBAABLgAECggJIAASAPscAA==.',
Bl='Bloodios:BAABLgAECn8kAAINAAgJ5hbmBgC1AQANAAgJ5hbmBgC1AQAAAA==.',
Bo='Bobin:BAAALgADCgcJBwABLgAECgcJGQATAPgRAA==.Bobinforapl:BAABLgAECn8ZAAITAAcJ+BGkEgBpAQATAAcJ+BGkEgBpAQAAAA==.Bombadil:BAABLgAECn8gAAITAAgJ4AMjFgBAAQATAAgJ4AMjFgBAAQAAAA==.',
Br='Bribage:BAABLgAECn8gAAMSAAgJ+xymBgAyAgASAAgJ+xymBgAyAgAPAAEJ1yHEXgBiAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgQJBAAAAA==.Budderwar:BAABLgAECn8nAAMUAAkJWSVFAABZAwAUAAkJWSVFAABZAwAVAAMJvw77hgCjAAAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJAwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.',
Cb='Cbreezy:BAAALgAECgEJAQAAAA==.',
Ce='Celjska:BAAALgAECgQJBAAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8UAAMFAAcJ7A3dQABGAQAFAAYJjw/dQABGAQAWAAcJ1Ak2KAAtAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.',
Ci='Cinderspella:BAAALgAECgEJAQAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8dAAIXAAgJwyX/AAALAwAXAAgJwyX/AAALAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8ZAAIYAAcJcQzLDwC9AAAYAAcJcQzLDwC9AAAAAA==.Corrail:BAAALgAECgUJBQAAAA==.Correin:BAABLgAECn8YAAIZAAgJAQ7UDwA/AQAZAAgJAQ7UDwA/AQAAAA==.',
Cr='Craszhin:BAAALgAECggJCwAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn8kAAIJAAgJnQyyPAB4AQAJAAgJnQyyPAB4AQAAAA==.',
Da='Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.',
De='Deets:BAABLgAECn8dAAIEAAgJaB9aCQBmAgAEAAgJaB9aCQBmAgAAAA==.Defoy:BAABLgAECn8VAAMHAAYJwRj/SQAqAQAHAAYJghb/SQAqAQAEAAQJYRAkhwBGAAAAAA==.Demona:BAABLgAECn8gAAMDAAgJ3gn3CAAcAQADAAcJ4wr3CAAcAQACAAEJwAPKvwAoAAAAAA==.Demonicfates:BAABLgAECn8WAAIZAAYJsw8LEgAiAQAZAAYJsw8LEgAiAQAAAA==.Derffy:BAAALgAECgYJEgAAAA==.Descalabrada:BAAALgAECgQJCAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Dm='Dmt:BAABLgAECn8eAAIaAAgJyBfUCwDqAQAaAAgJyBfUCwDqAQAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadx:BAAALgAECgYJCwAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8fAAMPAAgJUwmnKQA+AQAPAAgJUwmnKQA+AQAYAAEJAAARPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgEJBAAAAA==.',
Ec='Eclair:BAABLgAECn8gAAMWAAgJ+hFIHgBxAQAWAAgJ+hFIHgBxAQAFAAMJXxjcKgDYAAAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgADCgcJBwABLgAECgkJIwAQAKAcAA==.',
El='Eleysia:BAAALgADCgUJBgAAAA==.Elmore:BAAALgADCgkJCQAAAA==.Elmos:BAABLgAECn8kAAIXAAkJDB0KCAD5AgAXAAkJDB0KCAD5AgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgYJFQAJAMUKAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACQeAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJB5aHAAvAgAFAAkJJB5aHAAvAgAWAAcJQQveTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACQeAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAIAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8YAAIZAAgJSRHmCwB+AQAZAAgJSRHmCwB+AQAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgEJAQAAAA==.Ferg:BAAALgAECgEJAQABLgAECggJIAAJAHYiAA==.Fergis:BAABLgAECn8gAAIJAAgJdiK1CQCjAgAJAAgJdiK1CQCjAgAAAA==.Fetchme:BAAALgAECgMJAwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8XAAMNAAgJtBU6EgDoAQANAAgJoxU6EgDoAQAbAAYJsxRBCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECgcJDwAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgADCgcJFwAAAA==.Frostymonk:BAABLgAECn8WAAIaAAYJIwnwIwDgAAAaAAYJIwnwIwDgAAAAAA==.Frozenwaffle:BAAALgADCgEJAgABLgAECggJHwAcAFAdAA==.',
Fu='Furryben:BAAALgADCgkJFwAAAA==.',
Ga='Galeste:BAAALgAECgQJBAAAAA==.',
Gi='Gigem:BAAALgAECgMJBgAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQdAAkJkASNIwBcAQAdAAkJkASNIwBcAQAeAAUJ9gP1SgCoAAAfAAEJlQFcFQAcAAAAAA==.Glarious:BAAALgAECgYJBgABLgAECgkJGwAdAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8fAAMcAAgJUB0ODQCyAgAcAAgJUB0ODQCyAgAMAAYJwBS4NQBmAQAAAA==.Grôg:BAAALgAECgUJAwABLgAECgcJBwAIAAAAAA==.',
Gu='Guldaniel:BAAALgADCgkJHgAAAA==.Guthx:BAABLgAECn8aAAIPAAcJ5hy0FADgAQAPAAcJ5hy0FADgAQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAIAAAAAA==.',
Ho='Holymolii:BAABLgAECn8XAAILAAcJ5hW4CQBsAQALAAcJ5hW4CQBsAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAAALgAECgcJEgABLgAECgkJJwAUAFklAA==.',
In='Incredabull:BAAALgAECgUJDQAAAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8bAAIgAAgJMA+kAgCrAQAgAAgJMA+kAgCrAQAAAA==.Istayblunted:BAABLgAECn8bAAILAAcJrR8SEADEAQALAAcJrR8SEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAHweAA==.',
Ji='Jiayerah:BAAALgADCgkJFQABLgAECgYJEQAIAAAAAA==.Jinkuzo:BAABLgAECn8eAAIhAAgJbCDlAwB/AgAhAAgJbCDlAwB/AgAAAA==.Jinmu:BAABLgAECn8dAAMQAAgJVxLNDgCAAQAQAAcJjBPNDgCAAQAiAAEJGwt8FAA6AAAAAA==.',
Ju='Juggie:BAABLgAECn8XAAIMAAcJiRGzFABsAQAMAAcJiRGzFABsAQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8hAAIiAAgJwQvQBQBfAQAiAAgJwQvQBQBfAQAAAA==.',
Ka='Kagami:BAAALgADCgMJAwAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8UAAMCAAcJSBr0GQDaAQACAAcJDxr0GQDaAQADAAEJFBvLawA8AAAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECgYJBgAAAA==.',
Kl='Klum:BAAALgADCgcJEwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJCwAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgADCgkJDgAAAA==.Lendela:BAAALgAECgMJAwAAAA==.',
Li='Liljugg:BAAALgAECgYJDAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgADCgUJCQAAAA==.Lor:BAAALgAECgQJBQAAAA==.Lostmana:BAAALgADCgkJDgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Ly='Lygor:BAABLgAECn8XAAIEAAcJ7A1FKQBxAQAEAAcJ7A1FKQBxAQAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Majellan:BAAALgAECgMJAwAAAA==.Makrub:BAAALgAECggJDQAAAA==.Mandigosa:BAAALgADCgcJDAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marsawn:BAABLgAECn8cAAIcAAgJtRjdBgAeAgAcAAgJtRjdBgAeAgAAAA==.',
Mc='Mcpeepants:BAAALgADCgcJCQABLgAECgkJGAAGAN8fAA==.',
Me='Meqi:BAAALgAECgYJEQAAAA==.',
Mi='Mikàsa:BAABLgAECn8VAAMKAAcJAA9+DACXAQAKAAcJAA9+DACXAQAHAAYJXwmCTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8iAAIVAAgJ/R82BgBRAgAVAAgJ/R82BgBRAgAAAA==.Mineralelf:BAABLgAECn8iAAIEAAgJfgrXLABfAQAEAAgJfgrXLABfAQAAAA==.Minichaos:BAAALgAECgYJDwAAAA==.Miriam:BAAALgAECgYJEAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIqBwD5AgABAAgJvCIqBwD5AgAAAA==.',
Mo='Mojosavage:BAAALgAECgYJCwAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgADCgEJAQAAAA==.Mortshan:BAABLgAECn8XAAIjAAcJshagAQCzAQAjAAcJshagAQCzAQAAAA==.Mournfull:BAAALgADCgEJAQAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgQJBgAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgADCgMJAwAAAA==.Ninok:BAAALgAECggJCAAAAA==.',
No='Nornee:BAAALgAECgYJEAAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8YAAIkAAgJcRw5AwAdAgAkAAgJcRw5AwAdAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgEJAQAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8WAAIVAAYJfhHqHABJAQAVAAYJfhHqHABJAQAAAA==.',
Ol='Ollïee:BAAALgAECgUJBQAAAA==.',
Or='Orceo:BAABLgAECn8aAAIEAAgJ8SHJBQAxAwAEAAgJ8SHJBQAxAwAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwAAAA==.',
Ox='Oxcanor:BAAALgADCgkJDwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJkh+6TgDcAQACAAYJkh+6TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJJwAUAFklAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8hAAIFAAkJxAY2HQAsAQAFAAkJxAY2HQAsAQAAAA==.Popple:BAABLgAECn8fAAIVAAgJogvZEwCWAQAVAAgJogvZEwCWAQAAAA==.Potential:BAAALgAECggJEwAAAA==.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgQJBgAAAA==.Puggsly:BAAALgADCgkJCQAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIcAAcJxAzKHAAWAQAcAAcJxAzKHAAWAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8WAAIVAAYJAxogFQCLAQAVAAYJAxogFQCLAQAAAA==.',
Ra='Radaghast:BAAALgADCgUJCQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Reishirome:BAAALgADCgkJJgAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIYAAgJOSIaAwDlAgAYAAgJOSIaAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8VAAISAAYJHgWeKgC3AAASAAYJHgWeKgC3AAAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgADCgMJBAAAAA==.',
Ru='Rumincoke:BAAALgADCgQJBAAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAAALgAECgYJEQAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAIAAAAAA==.',
Sc='Scalygrob:BAAALgAECgcJDwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8iAAITAAgJuRfIBwAgAgATAAgJuRfIBwAgAgAAAA==.',
Sh='Shadowhntr:BAAALgAECgEJAQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgIJAwAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smogcheck:BAABLgAECn8dAAMdAAgJxRNiGwCtAQAdAAcJpxRiGwCtAQAfAAEJfQjNPgA0AAAAAA==.',
Sn='Snackcake:BAABLgAECn8XAAIPAAcJBB3BDAA8AgAPAAcJBB3BDAA8AgAAAA==.Snakeoil:BAABLgAECn8ZAAMFAAcJCiEiBwA0AgAFAAcJCiEiBwA0AgAWAAEJFgJiawAiAAAAAA==.Snowws:BAABLgAECn8WAAIRAAgJqhq4OAASAgARAAgJqhq4OAASAgAAAA==.',
So='Sortis:BAABLgAECn8bAAIJAAkJmRbdMwCjAgAJAAkJmRbdMwCjAgAAAA==.',
Sp='Spongerunner:BAAALgAECgQJCQAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAAALgAECgYJEwAAAA==.Strigo:BAABLgAFFH8KAAQKAAQJAxaeAwBoAQAKAAQJAxaeAwBoAQAEAAEJIxm0IABfAAAHAAEJnwyjKABKAAAAAA==.',
Su='Subway:BAAALgAECgcJCgAAAA==.Sunbaby:BAABLgAECn8XAAIlAAcJVR7RAgD/AQAlAAcJVR7RAgD/AQAAAA==.',
['Sà']='Sàlís:BAAALgADCgcJCgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8dAAITAAgJByJIBQD9AgATAAgJByJIBQD9AgAAAA==.Talas:BAABLgAECn8dAAMEAAkJshlJDwDBAgAEAAkJshlJDwDBAgAHAAUJswrXVwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temerald:BAAALgADCgkJCQAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJCQAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrann:BAABLgAECn8YAAIOAAcJqCKnIgC4AQAOAAcJqCKnIgC4AQAAAA==.Thunderdex:BAACLgAFFH8HAAIRAAUJzxcDDQBOAQARAAUJzxcDDQBOAQAuAAQKfxgAAhEACQmOGWocAKgCABEACQmOGWocAKgCAAAA.',
Ti='Tirium:BAAALgADCgYJCgAAAA==.',
To='Togglesmith:BAAALgADCgMJAwAAAA==.Togglestein:BAAALgADCgUJCAAAAA==.Togglethorp:BAAALgADCgYJBgAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgMJBgAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJBwAAAA==.',
Va='Vaadboolin:BAAALgAECggJEQAAAA==.Vallius:BAABLgAECn8ZAAIQAAcJKxJHDACkAQAQAAcJKxJHDACkAQAAAA==.Vanargandr:BAAALgADCgcJCAABLgAECgEJAQAIAAAAAA==.',
Ve='Verðandi:BAAALgADCgcJCwAAAA==.',
Vo='Volcano:BAABLgAECn8XAAICAAcJkRitGgDVAQACAAcJkRitGgDVAQAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn8hAAMWAAgJ8xXmDwD4AQAWAAgJ8xXmDwD4AQAFAAEJTQOrkAAnAAAAAA==.',
Wa='Waffletoast:BAAALgADCgcJBwABLgAECggJHwAcAFAdAA==.Wanders:BAAALgAECgcJEwAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwAAAA==.',
Xa='Xannies:BAABLgAECn8iAAImAAYJTwWQDQDvAAAmAAYJTwWQDQDvAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAABLgAECn8bAAIGAAkJ7yP1AABUAwAGAAkJ7yP1AABUAwAAAA==.Yesenìa:BAAALgADCgEJAQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn8fAAQfAAgJtRtkAQBCAgAfAAgJtRtkAQBCAgAeAAMJ4Q9eSwCmAAAdAAEJ8wFlJgAbAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn8gAAInAAgJgAWWCQBOAQAnAAgJgAWWCQBOAQAAAA==.Zillyanna:BAAALgAECgcJCwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zywol:BAABLgAECn8ZAAMSAAcJkhfdIwDeAQASAAcJkhfdIwDeAQAPAAMJlgbHpgB6AAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8VAAIJAAYJxQoWZAATAQAJAAYJxQoWZAATAQAAAA==.',
['Ðe']='Ðespair:BAABLgAECn8tAAQTAAgJxSEjCgCWAgATAAcJPSEjCgCWAgAcAAgJNx/nEgBuAQAMAAUJlhhoHwAHAQAAAA==.',
['Ðr']='Ðream:BAAALgAECgUJCAAAAA==.',
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

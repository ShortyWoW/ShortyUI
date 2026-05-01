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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Unknown-Unknown','Priest-Shadow','DemonHunter-Havoc','Priest-Holy','Druid-Guardian','Priest-Discipline','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance','Monk-Mistweaver','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aellaleander:BAAALgAECgYJCgAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCgABAGwYAA==.',
Ap='Aphrodotty:BAAALgADCgQJBAAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAABLgAECn8iAAMCAAcJexsECwA6AgACAAcJexsECwA6AgADAAQJYAUEbACTAAAAAA==.',
Au='Aurorabelli:BAAALgAECgYJDAAAAA==.Auróra:BAACLgAFFH8KAAIBAAQJbBgPEABgAQABAAQJbBgPEABgAQAuAAQKfysAAwEACAnLI0AOAAgDAAEACAnLI0AOAAgDAAQAAQkAAARpAD8AAAAA.Aurõrä:BAAALgAECgQJBAAAAA==.',
Az='Azlia:BAAALgAECgYJCgAAAA==.Azrabaine:BAAALgADCgIJAwAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAAALgAECgMJBAAAAA==.',
Ba='Bahumn:BAAALgAECgcJDwAAAA==.Bangpôwbôôm:BAABLgAECn8mAAMFAAgJHRpOCwBbAQAGAAgJJhl6WADoAQAFAAYJERhOCwBbAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8hAAMHAAgJJxOZDgDzAQAHAAgJJxOZDgDzAQAIAAMJBBSL5gDBAAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8eAAIJAAgJ9xsjNQCfAgAJAAgJ9xsjNQCfAgAAAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAKAAAAAA==.',
Br='Brivia:BAAALgAECgMJAwABLgAFFAQJCgABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJDQALAE0RAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECgYJBgAAAA==.',
Ca='Camel:BAABLgAECn8ZAAMIAAYJrA1VUwAUAQAIAAYJrA1VUwAUAQAHAAUJ1wXENgCfAAAAAA==.Cattlestance:BAAALgAECggJCAAAAA==.',
Ch='Chastitylock:BAAALgAECgYJDAAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCgABAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgADCgQJBQAAAA==.Dashdashdash:BAABLgAECn8gAAIMAAYJ+CQ5DgCAAgAMAAYJ+CQ5DgCAAgAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAAALgAECgYJEgAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJBgAAAA==.Destyne:BAABLgAECn8WAAINAAYJrRcZEgCLAQANAAYJrRcZEgCLAQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJBgAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAAALgAECgYJEAAAAA==.Drezlek:BAAALgADCgkJFgAAAA==.',
Du='Durkanis:BAABLgAECn8cAAIOAAgJThzrAgAkAgAOAAgJThzrAgAkAgAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgAAAA==.',
Ec='Ectasee:BAABLgAECn8pAAICAAgJJSQWAQBFAwACAAgJJSQWAQBFAwAAAA==.',
Ei='Eirenus:BAAALgAECgYJBwABLgAECgcJFQAPAJ8FAA==.',
Em='Emi:BAABLgAECn8WAAMDAAgJ8hNgFgBiAQADAAcJuBJgFgBiAQACAAQJWhg1cQDLAAAAAA==.',
En='Enøch:BAAALgAECgIJAgAAAA==.',
Ey='Eyekilledyou:BAAALgAECgYJCgABLgAECgcJFAAQAL8fAA==.',
Fa='Fanuc:BAABLgAECn8cAAMCAAgJ1CIIAgAQAwACAAgJ1CIIAgAQAwARAAEJkxSTKgA7AAAAAA==.',
Fe='Felbawlz:BAABLgAECn8QAAISAAYJyRWKZgBuAQASAAYJyRWKZgBuAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAAALgAECgIJAgAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAECgQJBQABLgAECgYJCgAKAAAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAKAAAAAA==.',
Fo='Forthrich:BAABLgAECn8iAAIIAAgJFQpDQwBAAQAIAAgJFQpDQwBAAQAAAA==.Fozuul:BAAALgAECgEJAQAAAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgADCgUJBAAAAA==.Gawkin:BAABLgAECn8lAAMHAAgJAh0SEgCCAgAHAAgJAh0SEgCCAgAIAAQJZQ8XZgDlAAAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Gobbs:BAAALgADCgcJEwABLgAECggJHgATAIgbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIUAAUJ8CPFEwCXAQAUAAUJ8CPFEwCXAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8ZAAIVAAcJshMeAwCSAQAVAAcJshMeAwCSAQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgADCggJBwAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDAAAAA==.',
He='Heelorestus:BAABLgAECn8ZAAMLAAgJaAwKNABIAQALAAgJaAwKNABIAQANAAYJwxBBPQBFAQAAAA==.',
Hi='Hippocalypse:BAAALgAECgMJBQABLgAECggJHgAJAPcbAA==.Hirculos:BAAALgAECggJDQAAAA==.',
Ho='Holyfrog:BAABLgAECn8jAAIHAAgJmxgSFwBZAgAHAAgJmxgSFwBZAgAAAA==.Holythis:BAABLgAECn8mAAIWAAkJihakBgB8AgAWAAkJihakBgB8AgAAAA==.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn8oAAIXAAgJHRRjBQDCAQAXAAgJHRRjBQDCAQAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8TAAMSAAgJ2RirGQCcAQASAAgJqBerGQCcAQAMAAQJEw0sSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn8rAAIYAAgJghafCQDRAQAYAAgJghafCQDRAQAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAAALgAECgIJBwAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAAALgAECgYJEAAAAA==.',
Jo='Jofixit:BAABLgAECn8rAAITAAgJ8R8BDwDDAgATAAgJ8R8BDwDDAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAQAAAA==.Kaepop:BAABLgAECn8OAAISAAgJ4Q4BcQBRAQASAAgJ4Q4BcQBRAQAAAA==.Kanda:BAABLgAECn8bAAITAAcJphn1IgA0AgATAAcJphn1IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8eAAMTAAgJfx+ACQBkAgATAAgJPRuACQBkAgAZAAgJBx1BGgBUAgAAAA==.',
Ke='Kedri:BAABLgAECn8nAAITAAcJmxMjJACLAQATAAcJmxMjJACLAQAAAA==.Keihas:BAABLgAECn8sAAMaAAgJFyH9AgD4AgAaAAgJmR/9AgD4AgAbAAgJJRjUBwAUAgAAAA==.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8kAAMFAAgJmRhvBwCpAQAFAAgJmRhvBwCpAQAGAAEJAAAI1gAAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAABLgAECn8eAAIDAAgJpBpbFwBcAgADAAgJpBpbFwBcAgAAAA==.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgQJDAAAAA==.Kodali:BAAALgAECgUJCQAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgEJAwAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgADCgQJBAAAAA==.',
Lo='Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgIJAwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAAALgAECgQJBwAAAA==.Magicpantiez:BAABLgAECn8ZAAIJAAgJkh1bPwB7AgAJAAgJkh1bPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAgABLgAECgEJAwAKAAAAAA==.Malexling:BAABLgAECn8cAAIIAAYJSRumMQB8AQAIAAYJSRumMQB8AQAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAABLgAECn8mAAIJAAgJWRzYFAA0AgAJAAgJWRzYFAA0AgAAAA==.',
Mi='Milcah:BAABLgAECn8bAAQOAAgJ6AxTFAArAQAOAAgJ6AxTFAArAQAcAAQJYQTaZwCCAAAXAAEJOgMbOQAkAAAAAA==.Mitteny:BAABLgAECn8VAAMLAAgJEBIbJAC3AQALAAcJ4BAbJAC3AQANAAgJzgK/JwC/AAAAAA==.Mitternacht:BAAALgAECggJDwAAAA==.',
Mo='Mooncraig:BAABLgAECn8qAAMcAAgJEhurCQD1AQAcAAgJEhurCQD1AQAdAAcJZgzRKABDAQAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn8ZAAIOAAYJZhaFCgAeAQAOAAYJZhaFCgAeAQAAAA==.',
Na='Naois:BAAALgADCgEJAQABLgAECgEJAwAKAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nazureser:BAAALgADCgkJCQABLgAECggJHgADAKQaAA==.',
Ne='Nemeeia:BAAALgAECgYJCAAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIYAAgJYBcfFQBoAgAYAAgJYBcfFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn8XAAIUAAcJbAkwXQA7AQAUAAcJbAkwXQA7AQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgADCgkJGwAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgADCgEJAQAAAA==.Panda:BAACLgAFFH8ZAAIeAAYJ4CQMAAA8AgAeAAYJ4CQMAAA8AgAuAAQKfzYAAh4ACQn0JUAAAMQDAB4ACQn0JUAAAMQDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn8tAAILAAgJWhi0DgCcAQALAAgJWhi0DgCcAQAAAA==.',
Pi='Picolás:BAABLgAECn8aAAIJAAcJ6h3KGgALAgAJAAcJ6h3KGgALAgAAAA==.',
Po='Pog:BAAALgAECgQJBAAAAA==.',
Pr='Prepare:BAAALgAECgYJCQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8cAAIPAAgJxRDWCwDNAQAPAAgJxRDWCwDNAQAAAA==.Probono:BAAALgAECgYJEQAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJCwAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.',
Re='Reprises:BAABLgAECn8WAAMMAAgJZB/OCwCkAgAMAAcJZCHOCwCkAgASAAgJwRdYEADtAQAAAA==.Reptar:BAAALgADCgYJBgABLgAECgUJBQAKAAAAAA==.Revini:BAABLgAECn8dAAIFAAgJcCSJAgBEAwAFAAgJcCSJAgBEAwAAAA==.Rezø:BAABLgAECn8VAAMPAAcJnwXoMgALAQAPAAYJLwboMgALAQANAAEJPwLEhQArAAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8ZAAMeAAgJcg5pGABHAQAeAAgJcg5pGABHAQAZAAEJAADxmgAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAABLgAECn8jAAISAAcJ0holFQDAAQASAAcJ0holFQDAAQAAAA==.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scruffy:BAABLgAECn8mAAIQAAgJpSCVAwCEAgAQAAgJpSCVAwCEAgAAAA==.',
Se='Seferres:BAACLgAFFH8JAAIfAAMJiySSCQBHAQAfAAMJiySSCQBHAQAuAAQKfyAAAh8ACAkqJOIKAN0CAB8ACAkqJOIKAN0CAAAA.Senortickle:BAABLgAECn8UAAIXAAgJsSPfAADKAgAXAAgJsSPfAADKAgAAAA==.',
Sh='Shaunara:BAABLgAECn8cAAMSAAgJmA89VQCjAQASAAgJmA89VQCjAQAgAAIJTRCFJgBRAAABLgAFFAMJCQAfAIskAA==.Shawts:BAABLgAECn8bAAIJAAcJKhHNQwBjAQAJAAcJKhHNQwBjAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.',
Sk='Skragrott:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAgAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBAAAAA==.',
St='Starburnz:BAAALgADCgQJBAABLgAECgkJJgAhADUbAA==.Steve:BAABLgAECn8WAAMZAAcJIg/QDAAAAQAZAAcJIg/QDAAAAQAeAAEJAgVFMQA1AAAAAA==.Stimutax:BAABLgAECn8WAAIiAAYJxAV1BwAKAQAiAAYJxAV1BwAKAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8gAAIHAAcJ1yBLGgBCAgAHAAcJ1yBLGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJDwAAAA==.Taurenvar:BAABLgAECn8jAAIRAAgJBR1WBgCTAgARAAgJBR1WBgCTAgAAAA==.Taziel:BAAALgAECggJDgAAAA==.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tingariban:BAAALgAECgcJDQAAAA==.',
To='Tohruu:BAABLgAECn8gAAIaAAgJ/g3KAwCkAQAaAAgJ/g3KAwCkAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8dAAIcAAgJdSJvAgDGAgAcAAgJdSJvAgDGAgAAAA==.',
Tw='Tweedledumm:BAABLgAECn8VAAIWAAYJ8BJ0FQB4AQAWAAYJ8BJ0FQB4AQAAAA==.',
Um='Umgross:BAAALgADCgYJBgAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgMJBAAAAA==.Vilehatred:BAABLgAECn8WAAIWAAYJAhSQGQBFAQAWAAYJAhSQGQBFAQAAAA==.',
Vo='Voltz:BAAALgADCgkJFwAAAA==.',
Wa='Wallis:BAAALgADCgcJDgAAAA==.Wattzazugzug:BAAALgAECgQJCQAAAA==.Waverunner:BAABLgAECn8YAAIjAAgJBhqlAwAYAgAjAAgJBhqlAwAYAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn8nAAITAAgJTQpFLABiAQATAAgJTQpFLABiAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAECggJKwACAI0XAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECgcJEQAAAA==.Zaligator:BAABLgAECn8cAAQaAAgJZxZ1AwCxAQAaAAcJvRh1AwCxAQAkAAMJtwX4PQB7AAAbAAEJZwhuSAAzAAAAAA==.Zayuna:BAAALgAECgQJBAAAAA==.',
Zi='Zil:BAAALgADCgEJAQAAAA==.Ziptoria:BAAALgAECgYJEgAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8NAAILAAUJTRERCABGAQALAAUJTRERCABGAQAuAAQKfyMAAgsACAmSICUNALECAAsACAmSICUNALECAAAA.Zombear:BAAALgAECgYJBwABLgAFFAYJGQAeAOAkAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8mAAMhAAkJNRugAwC0AgAhAAkJNRugAwC0AgAQAAYJeRZrLQB3AQAAAA==.',
Zy='Zylph:BAAALgAECgYJEQAAAA==.',
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

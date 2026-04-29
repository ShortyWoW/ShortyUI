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

local lookup = {'Priest-Discipline','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Warlock-Demonology','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Frost','Paladin-Holy','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','Paladin-Retribution','Mage-Frost','Druid-Balance','Druid-Feral','Warrior-Fury','Warrior-Arms','Priest-Holy','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','Shaman-Restoration','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Priest-Shadow','Mage-Arcane','DeathKnight-Blood','Druid-Restoration','Warlock-Affliction','Monk-Mistweaver','Monk-Windwalker',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abysm:BAAALgADCgkJDQAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAMJBgABACgHAA==.',
Ad='Adorabull:BAAALgADCgcJBgABLgAECggJJAACAO0eAA==.',
Ae='Aemun:BAABLgAECn8XAAMDAAgJeQ2mIAD0AQADAAgJeQ2mIAD0AQAEAAYJlAmwCAD2AAAAAA==.',
Ak='Akelita:BAAALgAECgYJEwAAAA==.',
Al='Alailea:BAABLgAECn8WAAIFAAcJmw05HQAWAQAFAAcJmw05HQAWAQAAAA==.Alwysafkable:BAAALgADCgQJBAAAAA==.',
Am='Amazadin:BAAALgAFFAIJAgABLgAFFAMJBgABACgHAA==.',
An='Andiwin:BAAALgAECgkJAQAAAA==.Andurthil:BAAALgAECgYJDAAAAA==.Anzul:BAAALgAECgQJBAAAAA==.',
Ar='Artistic:BAAALgAECgYJBgAAAA==.Arylanna:BAAALgAECgYJCwAAAA==.',
As='Asure:BAAALgAECgYJEwAAAA==.',
Az='Azerith:BAAALgAECgUJBgAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8YAAIGAAgJpBe6LQBWAgAGAAgJpBe6LQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAAALgAECgUJCQAAAA==.Bloodtemplar:BAAALgAECgUJCQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgMJAwAHAAAAAA==.Canan:BAAALgAECgMJAwAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAAALgAECggJEwAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgADCgEJAQAAAA==.',
Ce='Celum:BAAALgAECgMJBgAAAA==.',
Ch='Chaquén:BAAALgAECgYJDAAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAAALgAECgYJDQAAAA==.Chaw:BAACLgAFFH8LAAMIAAQJyRybAgAaAQAIAAMJkRmbAgAaAQAFAAEJbibgEAB1AAAuAAQKfyUABAgACAlWJAoDANoBAAkABwnWH1EiABECAAgACAlxIgoDANoBAAUABAk3I1NIAJEBAAAA.Chenkenichi:BAAALgAECgUJCQAAAA==.Chergar:BAABLgAECn8bAAIKAAgJ5iFHBQDpAgAKAAgJ5iFHBQDpAgAAAA==.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAQAAAA==.',
Ci='Cinny:BAABLgAECn8mAAIFAAgJsRtvBgAGAgAFAAgJsRtvBgAGAgAAAA==.Cinnyrolls:BAAALgAECgYJDgAAAA==.Cityairlines:BAABLgAECn8bAAILAAgJlxOAAQCnAQALAAgJlxOAAQCnAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Co='Cooldukenuke:BAACLgAFFH8FAAIMAAMJqg/mDwDaAAAMAAMJqg/mDwDaAAAuAAQKfx4AAgwACAnKHTwTAHgCAAwACAnKHTwTAHgCAAAA.',
Cr='Creepychalk:BAAALgAECgIJAwAAAA==.Criticize:BAAALgAECgYJEgAAAA==.',
Cs='Csorb:BAABLgAECn8aAAINAAgJfyEpAwDiAgANAAgJfyEpAwDiAgAAAA==.Csoren:BAAALgADCgQJBAAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgMJAwAAAA==.Cursedcanfly:BAACLgAFFH8MAAIOAAQJ8h2FAwBcAQAOAAQJ8h2FAwBcAQAuAAQKfyYAAw4ACAmFJeUDAFoDAA4ACAmFJeUDAFoDAA8ABQnaFGYiABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8GAAIQAAMJ/BDaEADuAAAQAAMJ/BDaEADuAAAuAAQKfyEAAhAACAnyHmcEAE4CABAACAnyHmcEAE4CAAAA.Dejavu:BAACLgAFFH8JAAIRAAMJ+RJ1CADhAAARAAMJ+RJ1CADhAAAuAAQKfyQAAhEACAmWGZYaAC8CABEACAmWGZYaAC8CAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Deppthcharge:BAAALgADCgcJBwAAAA==.Desdemona:BAAALgADCgUJBwAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Dooghammer:BAAALgAECggJDwAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECggJFgAKAA8lAA==.',
Du='Duplexity:BAABLgAECn8WAAIKAAgJDyUDAgBYAwAKAAgJDyUDAgBYAwAAAA==.',
Dw='Dwalin:BAAALgADCgcJCAAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8IAAISAAQJ3xUHFAAHAQASAAQJ3xUHFAAHAQAuAAQKfyUAAhIACAlgIwgNACUDABIACAlgIwgNACUDAAAA.',
Em='Emieretta:BAABLgAECn8iAAIQAAgJnRXUCgDSAQAQAAgJnRXUCgDSAQAAAA==.',
Eq='Eqdk:BAAALgAECgYJEAAAAA==.',
Er='Erret:BAACLgAFFH8GAAITAAMJFBBgLQABAQATAAMJFBBgLQABAQAuAAQKfyIAAhMACAk5HyYyAKoCABMACAk5HyYyAKoCAAAA.',
Ez='Ezinder:BAAALgADCgkJEAAAAA==.',
Fa='Faience:BAAALgAECgYJDAAAAA==.Falorina:BAAALgAECgYJDgAAAA==.Fathernature:BAABLgAECn8UAAMUAAcJ6BjZKAC4AQAUAAcJ6BjZKAC4AQAVAAEJeQXyOAAlAAAAAA==.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAAALgAECggJEgAAAA==.Felfaith:BAAALgADCgQJBAAAAA==.Fester:BAAALgADCgUJBQAAAA==.',
Fi='Finnin:BAABLgAECn8XAAMWAAgJ1iAVAgBNAgAWAAgJ1iAVAgBNAgAXAAEJ0gZ0SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8bAAIFAAgJpBrXCADbAQAFAAgJpBrXCADbAQAAAA==.Formidabull:BAAALgAECgEJAQABLgAECggJJAACAO0eAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Freidafondle:BAAALgAECgMJBAAAAA==.Frozenfaith:BAABLgAECn8bAAMBAAgJ7gs2CABiAQABAAcJqww2CABiAQAYAAIJ9ARIdwBMAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8bAAISAAgJqxGlDwCoAQASAAgJqxGlDwCoAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBgAAAA==.',
Gh='Ghettomike:BAABLgAECn8ZAAIQAAgJixtGCgDaAQAQAAgJixtGCgDaAQAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Giranimo:BAAALgAECgQJBAAAAA==.',
Gl='Glabados:BAAALgAECgEJAQABLgAECggJGwARAE4gAA==.Glossy:BAACLgAFFH8MAAIDAAQJNB5HAQCGAQADAAQJNB5HAQCGAQAuAAQKfyUAAwMACAmyJZMDAGMDAAMACAmyJZMDAGMDABkAAgkNHyoUALsAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAQJDAADADQeAA==.Glossydh:BAAALgADCgcJBgABLgAFFAQJDAADADQeAA==.Glossydk:BAAALgAECgQJBQABLgAFFAQJDAADADQeAA==.Glossylock:BAAALgADCgcJDQABLgAFFAQJDAADADQeAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8aAAIWAAgJ+QvKBwClAQAWAAgJ+QvKBwClAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAABLgAECn8kAAMSAAgJAiVfCQBGAwASAAgJAiVfCQBGAwAaAAQJ5iJ0EwCUAQABLgAFFAMJAwAHAAAAAA==.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAAALgAECgMJBgAAAA==.',
Ha='Halîk:BAAALgAECgYJDwAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn8rAAIbAAkJrBtpAACjAgAbAAkJrBtpAACjAgAAAA==.Hathina:BAACLgAFFH8JAAIWAAQJtSDmAwAsAQAWAAQJtSDmAwAsAQAuAAQKfyYAAxYACAmBJSUEAGkDABYACAmBJSUEAGkDABcAAwmCHyQeAP4AAAAA.',
He='Heket:BAABLgAECn8aAAISAAgJQgVTkwBWAQASAAgJQgVTkwBWAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.',
Hi='Highdra:BAAALgADCgkJCQAAAA==.Hill:BAABLgAECn8bAAIFAAgJex9dBAA8AgAFAAgJex9dBAA8AgAAAA==.Hive:BAABLgAECn8hAAIWAAgJnRV4BQDXAQAWAAgJnRV4BQDXAQAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAAALgAECgUJDgAAAA==.',
Hu='Husentar:BAABLgAECn8XAAITAAYJ1BwsHQBlAQATAAYJ1BwsHQBlAQAAAA==.Huuhablo:BAABLgAECn8mAAICAAgJcBu6CADnAQACAAgJcBu6CADnAQAAAA==.',
Ic='Icaron:BAAALgAECgcJBgAAAA==.',
Ig='Igothots:BAAALgADCgMJAgAAAA==.',
Il='Illuminottey:BAAALgAECggJCwAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAIJBAAHAAAAAA==.Insatiabull:BAABLgAECn8kAAICAAgJ7R68EgDqAgACAAgJ7R68EgDqAgAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Ja='Jacksof:BAAALgAECgQJCgAAAA==.Jackstands:BAABLgAECn8nAAIcAAgJuCBeAQC0AgAcAAgJuCBeAQC0AgAAAA==.Jagerin:BAAALgAECgYJCwABLgAECggJGwARAE4gAA==.',
Je='Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIdAAgJyBryBQA8AgAdAAgJyBryBQA8AgAAAA==.Jinksy:BAAALgAECgEJAQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJAgAAAA==.Junn:BAABLgAECn8bAAIeAAgJQBDeCABxAQAeAAgJQBDeCABxAQAAAA==.',
Ka='Kahayman:BAABLgAECn8UAAITAAgJmRWDTgBLAgATAAgJmRWDTgBLAgAAAA==.',
Kh='Khathani:BAAALgADCggJIAAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAAALgAECgYJDAAAAA==.Koriggan:BAAALgAECgYJDgAAAA==.',
Kr='Krea:BAAALgAECgYJDgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn8VAAQfAAYJ7QoAKAAzAQAfAAYJ7QoAKAAzAQAOAAUJwAezEgDJAAAPAAEJhwQYRAAmAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8bAAIGAAgJ5BS2DQCmAQAGAAgJ5BS2DQCmAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn8XAAIdAAYJwhrIAgBvAQAdAAYJwhrIAgBvAQAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.',
Lo='Loopey:BAAALgAECgcJEAABLgAFFAMJCQARAPkSAA==.',
Lu='Luceriss:BAAALgAECgcJDAAAAA==.',
Ma='Magicboi:BAAALgAECgQJBAAAAA==.Magwar:BAACLgAFFH8GAAIWAAQJBAnhBgDwAAAWAAQJBAnhBgDwAAAuAAQKfyUAAhYACAmjHKEZAH8CABYACAmjHKEZAH8CAAAA.Maike:BAAALgAECgUJCQAAAA==.Marcelyne:BAAALgADCggJDgABLgAECgYJEwAHAAAAAA==.Marothius:BAACLgAFFH8IAAMGAAQJpAtdEADxAAAGAAMJ8gldEADxAAAgAAEJuhAJFABWAAAuAAQKfyYAAyAACAnRGxEXAJEBACAABgl3HBEXAJEBAAYABgkpGjRsAIkBAAAA.Martaug:BAABLgAECn8ZAAIcAAcJlR3NGQBJAgAcAAcJlR3NGQBJAgAAAA==.Marune:BAAALgAECgIJAwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn8XAAMXAAYJDB0NBABkAQAWAAYJmht7MgDiAQAXAAYJ2BMNBABkAQAAAA==.Mawg:BAAALgAECgEJAQAAAA==.Mayfair:BAAALgAECgIJAwAAAA==.',
Mb='Mbarnes:BAAALgAECgMJAwAAAA==.',
Me='Melee:BAACLgAFFH8cAAISAAcJaSQiAAD2AgASAAcJaSQiAAD2AgAuAAQKfxQAAhIACQmZJjoCALoDABIACQmZJjoCALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgADCgkJIQAAAA==.Minibeer:BAAALgAECgYJDgAAAA==.Miquella:BAAALgAECgUJBgAAAA==.Misohotramen:BAACLgAFFH8FAAICAAMJtxLXDAD3AAACAAMJtxLXDAD3AAAuAAQKfyQAAgIACAmrHpsEAEQCAAIACAmrHpsEAEQCAAAA.',
Mo='Moist:BAABLgAECn8XAAINAAYJFCL6AQDNAQANAAYJFCL6AQDNAQAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Mordakka:BAAALgAECgUJBQAAAA==.Morior:BAABLgAECn8lAAMGAAgJwhvUBwD0AQAGAAcJwhvUBwD0AQAgAAIJMBipUQB5AAAAAA==.Motgustus:BAAALgAECgQJBAAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn8aAAIGAAYJDiBGDgCgAQAGAAYJDiBGDgCgAQAAAA==.Muskrattsam:BAAALgAECgYJDwAAAA==.',
My='Myravia:BAAALgAECgcJEAAAAA==.Myrokos:BAABLgAECn8nAAISAAgJSx9JBQBEAgASAAgJSx9JBQBEAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn8nAAINAAgJyw2zEwA0AQANAAgJyw2zEwA0AQAAAA==.Nails:BAAALgADCgcJCgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAQABLgAFFAEJAgAHAAAAAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgYJDwAHAAAAAA==.Niddy:BAAALgAECgYJDwAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8NAAMhAAQJtB0oBQB9AQAhAAQJtB0oBQB9AQABAAQJ0QLFBQAFAQAuAAQKfyUABCEACAn7IdYGAB0DACEACAn7IdYGAB0DABgABgnIFb8uAIgBAAEAAgnLBNpZAC4AAAAA.Noel:BAAALgAECgIJAwAAAA==.Nomsayin:BAABLgAECn8eAAIGAAcJdh0RMwBAAgAGAAcJdh0RMwBAAgAAAA==.Nonospot:BAAALgAECgYJEAAAAA==.Noobuddy:BAAALgAECgUJBQABLgAFFAQJDQAhALQdAA==.Noraboo:BAABLgAECn8WAAMiAAgJphihBAD7AQAiAAYJbxyhBAD7AQATAAYJ4g4OzgBPAQAAAA==.Norannestra:BAAALgAECgQJBwAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAAALgAECgcJEQAAAA==.',
Ny='Nyctt:BAABLgAECn8VAAMDAAgJsBlOGQA6AgADAAgJ1xdOGQA6AgAZAAIJ5xdkFgCSAAAAAA==.Nyzstra:BAABLgAECn8lAAITAAgJiyIMAwCfAgATAAgJiyIMAwCfAgAAAA==.',
['Nì']='Nìrvana:BAAALgAECgQJCAAAAA==.',
On='Onlybeams:BAABLgAECn8bAAICAAgJABbHCgDHAQACAAgJABbHCgDHAQAAAA==.',
Or='Orphu:BAAALgADCgYJEAAAAA==.',
Pa='Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Pastrydragon:BAACLgAFFH8IAAIOAAMJxBcICAABAQAOAAMJxBcICAABAQAuAAQKfyMAAw4ACAmZINMKAMgCAA4ACAlgHtMKAMgCAA8ABglCI5ILACICAAAA.',
Pi='Pistachio:BAAALgAECgYJEAAAAA==.Pitviper:BAABLgAECn8bAAIZAAgJfx97AABUAgAZAAgJfx97AABUAgAAAA==.',
Po='Pogaca:BAAALgADCgMJAwABLgAECgYJDgAHAAAAAA==.Portabull:BAAALgADCgcJBwABLgAECggJJAACAO0eAA==.Possess:BAABLgAECn8XAAIGAAYJAR25DQCmAQAGAAYJAR25DQCmAQAAAA==.Pownora:BAAALgAECgYJDgABLgAECggJFgAiAKYYAA==.',
Ps='Psarchasm:BAAALgAECgYJDQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn8XAAIFAAYJxh+aCgDAAQAFAAYJxh+aCgDAAQAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8bAAIRAAgJTiAEAQCaAgARAAgJTiAEAQCaAgAAAA==.Rayyzer:BAAALgAECggJEAAAAA==.',
Re='Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAAALgAECgYJCAAAAA==.Rincewind:BAAALgADCgQJBAAAAA==.',
Ro='Rossabella:BAABLgAECn8kAAIBAAgJ1A5sBQC1AQABAAgJ1A5sBQC1AQAAAA==.Rot:BAABLgAECn8bAAIjAAgJJiVwAADMAgAjAAgJJiVwAADMAgAAAA==.',
Ru='Rude:BAAALgADCggJGwABLgAFFAQJCQAWALUgAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAAALgADCgcJDAABLgAECggJFAATAJkVAA==.Saphlocket:BAAALgAECgIJBAAAAA==.Sathin:BAABLgAECn8XAAICAAYJbQdELADEAAACAAYJbQdELADEAAAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAQJCAAGAKQLAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.September:BAAALgAECgIJAgABLgAECggJHAAFAJIVAA==.Sevatar:BAAALgAECgYJBgAAAA==.',
Sf='Sfcwarner:BAAALgADCgMJAwAAAA==.',
Sh='Shampooyou:BAAALgAECgYJDgAAAA==.Shockakhan:BAAALgAECgIJAwAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECggJFgAKAA8lAA==.',
Si='Silentmamba:BAAALgADCgMJAwAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sn='Snowflake:BAAALgADCgUJBQAAAA==.',
Sp='Spellsteal:BAABLgAECn8ZAAITAAcJ2BmPawD+AQATAAcJ2BmPawD+AQAAAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Splashmountn:BAAALgAECgEJAQAAAA==.Spring:BAABLgAECn8cAAMFAAgJkhWtCgC/AQAFAAgJThWtCgC/AQAJAAYJ0wvuTQAYAQAAAA==.',
Ss='Ssgwarner:BAAALgADCgQJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAQJDAADALAgAA==.Sting:BAAALgADCgEJAQAAAA==.Stormclaw:BAABLgAECn8dAAIkAAcJ4Rs1BgAPAgAkAAcJ4Rs1BgAPAgAAAA==.Stregoica:BAAALgADCgcJDgABLgAFFAQJCAAGAKQLAA==.',
Su='Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Ta='Tallron:BAACLgAFFH8KAAIkAAQJMRzKAwBXAQAkAAQJMRzKAwBXAQAuAAQKfyEAAiQACAkKJLsJAPcCACQACAkKJLsJAPcCAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAQJCgAkADEcAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tandraella:BAAALgAECgQJBAABLgAFFAMJBgABACgHAA==.Taqas:BAABLgAECn8cAAITAAgJTRGpYwASAgATAAgJTRGpYwASAgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8fAAIbAAgJIhfqAgCyAQAbAAgJIhfqAgCyAQAAAA==.Tombs:BAAALgAECgIJAwAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Tristex:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.',
Tu='Tuha:BAAALgAECgQJBAAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Va='Valliya:BAAALgADCgQJBgAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIlAAgJtA9hAQCMAQAlAAgJtA9hAQCMAQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8dAAMhAAcJChu9BQCwAQAhAAcJChu9BQCwAQAYAAEJJRbAegA9AAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8bAAImAAgJDxeSAwASAgAmAAgJDxeSAwASAgAAAA==.Volq:BAAALgADCgIJAgAAAA==.Voodoopriest:BAABLgAECn8YAAIGAAcJLgQgpAAQAQAGAAcJLgQgpAAQAQAAAA==.Voyria:BAABLgAECn8XAAIkAAYJTAVXHADTAAAkAAYJTAVXHADTAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.',
Wa='Warm:BAACLgAFFH8HAAInAAQJtRPBBABEAQAnAAQJtRPBBABEAQAuAAQKfyEAAicACAltIGgIAPMCACcACAltIGgIAPMCAAAA.Warmlight:BAAALgAECgYJBgAAAA==.',
We='Weewu:BAAALgADCgYJCAAAAA==.Weledish:BAABLgAECn8jAAITAAgJYBkySABfAgATAAgJYBkySABfAgAAAA==.',
Wi='Wienercat:BAAALgAECgQJCQABLgAECgUJDgAHAAAAAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgADCgEJAQAAAA==.',
Ya='Yael:BAABLgAECn8WAAICAAYJDx5MEwBkAQACAAYJDx5MEwBkAQAAAA==.',
Za='Zarewien:BAABLgAECn8XAAIYAAYJhgjhDgABAQAYAAYJhgjhDgABAQAAAA==.',
Zi='Ziddles:BAAALgAECgYJDAAAAA==.',
Zo='Zomgmonk:BAABLgAECn8nAAIRAAgJthfKBADMAQARAAgJthfKBADMAQAAAA==.',
Zu='Zurisdad:BAABLgAECn8YAAIRAAcJRQ6iCgBEAQARAAcJRQ6iCgBEAQABLgAFFAMJBgATABQQAA==.Zurishmi:BAACLgAFFH8NAAIcAAQJLB9jBQB2AQAcAAQJLB9jBQB2AQAuAAQKfyYAAhwACAmRJBMEADQDABwACAmRJBMEADQDAAAA.',
['Äm']='Ämäteräsu:BAAALgAECgQJBAAAAA==.',
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

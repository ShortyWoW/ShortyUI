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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','DemonHunter-Havoc','Warrior-Protection','Priest-Holy','Druid-Guardian','Priest-Discipline','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aellaleander:BAAALgAECgYJCgAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwABAGwYAA==.',
Ap='Aphrodotty:BAAALgADCgQJBAAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAABLgAECn8pAAMCAAgJiRm4DQBaAgACAAgJiRm4DQBaAgADAAQJYAUDbACTAAAAAA==.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAEAC0bAA==.',
Au='Aurorabelli:BAAALgAECggJEwAAAA==.Auróra:BAACLgAFFH8LAAIBAAQJbBgSEABgAQABAAQJbBgSEABgAQAuAAQKfzEAAwEACQlCJGcDABoDAAEACQlCJGcDABoDAAUAAQkAAAVpAD8AAAAA.Aurõrä:BAAALgAECgQJBAAAAA==.',
Az='Azlia:BAAALgAECgYJDwABLgAFFAMJAwAGAAAAAA==.Azrabaine:BAAALgADCgIJAwAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAAALgAECgMJBAAAAA==.',
Ba='Bahumn:BAAALgAECggJEQAAAA==.Bangpôwbôôm:BAABLgAECn8sAAMHAAgJ6huRCAD8AQAHAAgJJhmRCAD8AQAIAAgJLBlwWADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8qAAMJAAkJ7hOsFgDYAQAJAAgJJBOsFgDYAQAKAAUJpBAYjgDRAAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAILAAgJaxwfNQCfAgALAAgJaxwfNQCfAgABLgAFFAMJBQAMADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bogeyman:BAAALgADCgcJDQABLgAECgcJFwANAFETAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAGAAAAAA==.',
Br='Brivia:BAAALgAECgMJAwABLgAFFAQJCwABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJEQAOAI0SAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECgYJCgAAAA==.',
Ca='Camel:BAABLgAECn8eAAMJAAYJXxrEIgBxAQAJAAUJBRjEIgBxAQAKAAYJrA0scQAKAQAAAA==.Cattlestance:BAAALgAECggJEAAAAA==.',
Ch='Chastitylock:BAAALgAECgYJDAAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgQJBAAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwABAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgADCgUJBwAAAA==.Dashdashdash:BAABLgAECn8rAAIPAAYJDiVTCAAOAgAPAAYJDiVTCAAOAgAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8YAAIQAAcJvxSKDgB7AQAQAAcJvxSKDgB7AQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJBgAAAA==.Destyne:BAABLgAECn8cAAIRAAcJhhUcFQCtAQARAAcJhhUcFQCtAQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJBgAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAAALgAECggJEwAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8kAAISAAgJuhwqBAA9AgASAAgJuhwqBAA9AgAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgAAAA==.',
Ec='Ectasee:BAABLgAECn8yAAMCAAkJRySQAACtAwACAAkJRySQAACtAwADAAMJ8RANPwCuAAAAAA==.',
Ei='Eirenus:BAAALgAECgYJBwABLgAECgcJGgATAFcMAA==.',
El='Element:BAAALgAECgQJBAAAAA==.',
Em='Emi:BAABLgAECn8WAAMDAAgJ+BNlHgBaAQADAAcJvxJlHgBaAQACAAQJWxgvcQDLAAAAAA==.',
En='Enøch:BAAALgAECgMJAgAAAA==.',
Ey='Eyekilledyou:BAAALgAECgYJDwABLgAECggJHQAMAOshAA==.',
Fa='Fanuc:BAABLgAECn8hAAMCAAgJQyOQAwASAwACAAgJQyOQAwASAwAUAAEJkxSWKgA7AAAAAA==.',
Fe='Felbawlz:BAABLgAECn8XAAINAAcJURNyUAAIAQANAAcJURNyUAAIAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAAALgAECgIJAgAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJAwAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAGAAAAAA==.',
Fo='Forthrich:BAABLgAECn8oAAIKAAgJOgqpWQA9AQAKAAgJOgqpWQA9AQAAAA==.Fozuul:BAAALgAECggJCgABLgAECgkJJwAEAC0bAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgQJBAAAAA==.Gawkin:BAABLgAECn8tAAMJAAgJAh0TEgCCAgAJAAgJAh0TEgCCAgAKAAUJABbhTABfAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Gobbs:BAAALgADCgcJEwABLgAECggJHgAVAJAbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgEJAQAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIWAAUJ8CPIGwCKAQAWAAUJ8CPIGwCKAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8aAAIXAAcJshPHBQBkAQAXAAcJshPHBQBkAQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgAECgQJBAAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDAAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMRAAkJhQ9IPQBFAQARAAYJwxBIPQBFAQAOAAkJBwzVJgAOAQAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQAMADEYAA==.Hirculos:BAAALgAECggJDQAAAA==.',
Ho='Holyfrog:BAABLgAECn8rAAIJAAgJexwzDwAnAgAJAAgJexwzDwAnAgAAAA==.Holythis:BAACLgAFFH8FAAIYAAMJAAufBgCiAAAYAAMJAAufBgCiAAAuAAQKfysAAhgACQmLFqIGAHwCABgACQmLFqIGAHwCAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn8xAAIZAAkJahOZBAAeAgAZAAkJahOZBAAeAgAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMNAAkJphk8EwAjAgANAAkJphk8EwAjAgAPAAQJEw0sSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn8xAAIaAAgJfRsmCgD9AQAaAAgJfRsmCgD9AQAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAAALgAECgQJCwAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAABLgAECn8UAAIVAAYJQAoLaQDWAAAVAAYJQAoLaQDWAAAAAA==.',
Jo='Jofixit:BAABLgAECn8xAAIVAAgJcyH+DgDDAgAVAAgJcyH+DgDDAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaepop:BAABLgAECn8OAAINAAgJEw8DcQBRAQANAAgJEw8DcQBRAQAAAA==.Kanda:BAABLgAECn8cAAIVAAgJhBn1IgA0AgAVAAgJhBn1IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8nAAMVAAkJAB+xAwD/AgAVAAkJAB+xAwD/AgAbAAgJBx3eGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn8vAAIVAAgJqhbRHQDqAQAVAAgJqhbRHQDqAQAAAA==.Keihas:BAABLgAECn8xAAMcAAkJdx/+AgD4AgAcAAgJmR/+AgD4AgAdAAkJ2BdYBwBhAgAAAA==.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8kAAMHAAgJnhhvCQDoAQAHAAgJnhhvCQDoAQAIAAEJAAB0CQEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8FAAIDAAMJLhM3GADrAAADAAMJLhM3GADrAAAuAAQKfx4AAgMACAmkGlgXAFwCAAMACAmkGlgXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgQJDAAAAA==.Kodali:BAAALgAECgUJCQAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgEJBAAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgIJAwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAAALgAECgUJDAAAAA==.Magicpantiez:BAABLgAECn8ZAAILAAgJkh1QPwB7AgALAAgJkh1QPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAgABLgAECgEJBAAGAAAAAA==.Malexling:BAABLgAECn8hAAIKAAYJeBvMPwCGAQAKAAYJeBvMPwCGAQAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8HAAILAAMJOQ4eSgD1AAALAAMJOQ4eSgD1AAAuAAQKfyYAAgsACAlYHDUgACoCAAsACAlYHDUgACoCAAAA.',
Mi='Milcah:BAABLgAECn8fAAQSAAgJuQ1QEAADAQASAAgJuQ1QEAADAQAeAAQJYQTjZwCCAAAZAAEJOgMcOQAkAAAAAA==.Mitteny:BAABLgAECn8dAAMOAAgJQRICFACkAQAOAAgJQRICFACkAQARAAgJzwJkMgC+AAAAAA==.Mitternacht:BAABLgAECn8VAAIDAAgJYBQ1EgDKAQADAAgJYBQ1EgDKAQABLgAECggJKgAVABodAA==.',
Mo='Monen:BAAALgADCgcJCQAAAA==.Mooncraig:BAABLgAECn8wAAMeAAgJch1RCQA5AgAeAAgJch1RCQA5AgAfAAcJ2g2oNQBCAQAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn8eAAISAAYJbhYRDQA8AQASAAYJbhYRDQA8AQAAAA==.',
Na='Naois:BAAALgAECgEJAQABLgAECgEJBAAGAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAECgIJAgABLgAECggJEQAGAAAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAMJBQADAC4TAA==.',
Ne='Nemeeia:BAAALgAECgYJCAAAAA==.Nestshalis:BAAALgADCgEJAQABLgAECgYJDgAGAAAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIaAAgJYBccFQBpAgAaAAgJYBccFQBpAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn8kAAIWAAgJFguQHACEAQAWAAgJFguQHACEAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8ZAAIgAAYJ2SQMAAA8AgAgAAYJ2SQMAAA8AgAuAAQKfzsAAiAACQn0JT8AAMQDACAACQn0JT8AAMQDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAIOAAgJFhqUDAD9AQAOAAgJFhqUDAD9AQAAAA==.',
Pi='Picolás:BAABLgAECn8cAAILAAcJ1R4fJAAWAgALAAcJ1R4fJAAWAgAAAA==.',
Po='Pog:BAAALgAECgQJCQAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8kAAITAAgJ0xAFEQDFAQATAAgJ0xAFEQDFAQAAAA==.Probono:BAABLgAECn8VAAIOAAYJ2woxLgDfAAAOAAYJ2woxLgDfAAAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJDQAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAAALgAECgQJBAAAAA==.',
Re='Reprises:BAABLgAECn8eAAMPAAgJcx/NCwCkAgAPAAcJZCHNCwCkAgANAAgJxBeuGgDpAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAYJGwAhAEoWAA==.Restdrag:BAAALgADCgkJCQAAAA==.Revini:BAABLgAECn8dAAIHAAgJcSSKAgBEAwAHAAgJcSSKAgBEAwAAAA==.Rezø:BAABLgAECn8aAAMTAAcJVwxEIwAQAQATAAYJBg5EIwAQAQARAAEJPwLHhQArAAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8fAAMgAAkJVA0eDADiAQAgAAkJVA0eDADiAQAbAAEJAAD8mgAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAABLgAECn8qAAINAAgJVxpjFgAJAgANAAgJVxpjFgAJAgAAAA==.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scruffy:BAABLgAECn8uAAIMAAgJxCFxBACiAgAMAAgJxCFxBACiAgAAAA==.',
Se='Seferres:BAACLgAFFH8NAAIhAAQJdiKPBQCfAQAhAAQJdiKPBQCfAQAuAAQKfyMAAiEACAm3JOEKAN0CACEACAm3JOEKAN0CAAAA.Senortickle:BAABLgAECn8XAAIZAAkJICSEAAA5AwAZAAkJICSEAAA5AwAAAA==.',
Sh='Shaunara:BAABLgAECn8eAAMNAAgJGxA9VQCkAQANAAgJGxA9VQCkAQAiAAIJUhCCJgBRAAABLgAFFAQJDQAhAHYiAA==.Shawts:BAABLgAECn8bAAILAAcJLREzWgBgAQALAAcJLREzWgBgAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.',
Sk='Skragrott:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAgAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBAAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAEAC0bAA==.Steve:BAABLgAECn8WAAMbAAcJJQ9GEADpAAAbAAcJJQ9GEADpAAAgAAEJCQWCQAA0AAAAAA==.Stimutax:BAABLgAECn8cAAIjAAcJTwa2BAAKAQAjAAcJTwa2BAAKAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8mAAIJAAcJ1yBIGgBCAgAJAAcJ1yBIGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJDwAAAA==.Taurenvar:BAABLgAECn8qAAIUAAkJnh0iAgCUAgAUAAkJnh0iAgCUAgAAAA==.Taziel:BAAALgAECggJDgAAAA==.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDQAAAA==.',
To='Tohruu:BAABLgAECn8gAAIcAAgJBw51BQCHAQAcAAgJBw51BQCHAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8lAAIeAAgJLyN6AwDRAgAeAAgJLyN6AwDRAgAAAA==.',
Tw='Tweedledumm:BAABLgAECn8bAAIYAAcJvxaUDAByAQAYAAcJvxaUDAByAQAAAA==.',
Um='Umgross:BAAALgADCgYJBgAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgMJBAAAAA==.Vilehatred:BAABLgAECn8cAAIYAAcJPBb5DgBIAQAYAAcJPBb5DgBIAQAAAA==.',
Vo='Voltz:BAAALgADCgkJGQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgQJCQAAAA==.Waverunner:BAABLgAECn8bAAIkAAkJCxuNAwBnAgAkAAkJCxuNAwBnAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn8tAAIVAAgJygq7OwBeAQAVAAgJygq7OwBeAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAIJBQACANgNAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEgAAAA==.Zaligator:BAABLgAECn8eAAQcAAgJiRYABADDAQAcAAgJ0RUABADDAQAlAAMJtwX8PQB7AAAdAAEJawjWWwAzAAAAAA==.Zayuna:BAAALgAECgQJBAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8ZAAIVAAgJoQqQNgBzAQAVAAgJoQqQNgBzAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8RAAIOAAUJjRIUCABGAQAOAAUJjRIUCABGAQAuAAQKfyMAAg4ACAmyICcNALECAA4ACAmyICcNALECAAAA.Zombear:BAAALgAECgYJBwABLgAFFAYJGQAgANkkAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMEAAkJLRvvBQCqAgAEAAkJLRvvBQCqAgAMAAYJeRZnLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8XAAIBAAYJ9QbKcgDkAAABAAYJ9QbKcgDkAAAAAA==.',
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

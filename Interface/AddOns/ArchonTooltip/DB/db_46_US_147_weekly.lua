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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Mage-Frost','Priest-Shadow','DemonHunter-Havoc','Druid-Guardian','Priest-Discipline','Shaman-Enhancement','DemonHunter-Devourer','Hunter-BeastMastery','Warrior-Fury','Priest-Holy','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aellaleander:BAAALgAECgYJCgAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCgABAGwYAA==.',
Ap='Aphrodotty:BAAALgADCgQJBAAAAA==.Apocolapse:BAAALgADCgcJDgAAAA==.',
As='Asahhealer:BAABLgAECn8cAAMCAAcJbhRNDAB4AQACAAcJbhRNDAB4AQADAAQJYAX3awCTAAAAAA==.',
Au='Aurorabelli:BAAALgAECgUJBgAAAA==.Auróra:BAACLgAFFH8KAAIBAAQJbBiZBQBeAQABAAQJbBiZBQBeAQAuAAQKfyoAAwEACAnLIz0OAAgDAAEACAnLIz0OAAgDAAQAAQkAAP1oAD8AAAAA.Aurõrä:BAAALgAECgQJBAAAAA==.',
Az='Azlia:BAAALgAECgMJAwABLgAECgQJBQAFAAAAAA==.Azrabaine:BAAALgADCgIJAwAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAAALgAECgIJAgAAAA==.',
Ba='Bahumn:BAAALgAECgYJDgAAAA==.Bangpôwbôôm:BAABLgAECn8fAAMGAAgJJhmCWADoAQAGAAgJJhmCWADoAQAHAAUJ0xQQCQD4AAAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8ZAAMIAAgJRQ5tCQCsAQAIAAgJRQ5tCQCsAQAJAAMJphOL5gDBAAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8ZAAIKAAgJsRseNQCfAgAKAAgJsRseNQCfAgAAAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAFAAAAAA==.',
Br='Brivia:BAAALgAECgMJAwABLgAFFAQJCgABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgYJEAABLgAFFAQJCQALADcNAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgADCgYJCQAAAA==.',
Ca='Camel:BAAALgAECgYJEgAAAA==.',
Ch='Chastitylock:BAAALgAECgUJBgAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Dashdashdash:BAABLgAECn8UAAIMAAYJtiRhAgDzAQAMAAYJtiRhAgDzAQAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAAALgAECgYJDAAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgADCgEJAQAAAA==.Destyne:BAAALgAECgYJEAAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAAALgAECgQJCgAAAA==.Drezlek:BAAALgADCgkJFgAAAA==.',
Du='Durkanis:BAABLgAECn8UAAINAAcJSR26AQDqAQANAAcJSR26AQDqAQAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgAAAA==.',
Ec='Ectasee:BAABLgAECn8hAAICAAgJjyNwAAAjAwACAAgJjyNwAAAjAwAAAA==.',
Ei='Eirenus:BAAALgAECgYJBwABLgAECgcJFQAOAJ8FAA==.',
Em='Emi:BAAALgAFFAIJAgAAAA==.',
En='Enøch:BAAALgAECgIJAgAAAA==.',
Ey='Eyekilledyou:BAAALgAECgUJBQABLgAECgYJEAAFAAAAAA==.',
Fa='Fanuc:BAABLgAECn8bAAMCAAgJ1CJ5AAAdAwACAAgJ1CJ5AAAdAwAPAAEJkxSVKgA7AAAAAA==.',
Fe='Felbawlz:BAABLgAECn8VAAIQAAYJtRYmHgAWAQAQAAYJtRYmHgAWAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAECgQJBQAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAFAAAAAA==.',
Fo='Forthrich:BAABLgAECn8cAAIJAAcJmwqGiQBoAQAJAAcJmwqGiQBoAQAAAA==.Fozuul:BAAALgAECgEJAQAAAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Gawkin:BAABLgAECn8cAAIIAAgJcxwWEgCCAgAIAAgJcxwWEgCCAgAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Gobbs:BAAALgADCgcJEwABLgAECgcJGQARAFUeAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.',
Gu='Gulev:BAAALgADCgkJCQAAAA==.Gumbercules:BAABLgAECn8WAAISAAUJWyOjLwDxAQASAAUJWyOjLwDxAQAAAA==.Gurnsey:BAAALgADCgcJDgAAAA==.Gutholoydne:BAAALgAECgcJEQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJCAAAAA==.',
He='Heelorestus:BAABLgAECn8ZAAMLAAgJaAz/MwBIAQALAAgJaAz/MwBIAQATAAYJwxA9PQBFAQAAAA==.',
Hi='Hippocalypse:BAAALgAECgIJAwAAAA==.Hirculos:BAAALgAECgcJDAAAAA==.',
Ho='Holyfrog:BAABLgAECn8bAAIIAAgJmxgSFwBZAgAIAAgJmxgSFwBZAgAAAA==.Holythis:BAABLgAECn8hAAIUAAkJIhakBgB8AgAUAAkJIhakBgB8AgAAAA==.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn8gAAIVAAgJeBPPCwABAgAVAAgJeBPPCwABAgAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBgAAAA==.',
Il='Illaadden:BAAALgAECggJEgAAAA==.',
In='Infiltrata:BAABLgAECn8kAAIWAAgJfhaiAwDeAQAWAAgJfhaiAwDeAQAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAAALgAECgIJBwAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAAALgAECgYJCgAAAA==.',
Jo='Jofixit:BAABLgAECn8kAAIRAAgJ8R8CDwDDAgARAAgJ8R8CDwDDAgAAAA==.',
Ka='Kaepop:BAAALgAECggJEQAAAA==.Kanda:BAABLgAECn8UAAIRAAcJKxn4IgA0AgARAAcJKxn4IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8WAAMXAAgJCB0/GgBUAgAXAAgJBx0/GgBUAgARAAMJzhXeIwDjAAAAAA==.',
Ke='Kedri:BAABLgAECn8cAAIRAAcJ6xLbDwCCAQARAAcJ6xLbDwCCAQAAAA==.Keihas:BAABLgAECn8qAAMYAAgJmR/6AgD4AgAYAAgJmR/6AgD4AgAZAAgJcxYwAwD+AQAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8gAAIHAAgJeBiJAgDqAQAHAAgJeBiJAgDqAQAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAABLgAECn8bAAIDAAgJZxlbFwBcAgADAAgJZxlbFwBcAgAAAA==.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgQJCAAAAA==.Kodali:BAAALgAECgUJCAAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgADCgEJAQAAAA==.',
Li='Linarine:BAAALgADCgQJBAAAAA==.',
Lo='Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgEJAQAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAAALgAECgMJAwAAAA==.Magicpantiez:BAABLgAECn8ZAAIKAAgJkh1WPwB7AgAKAAgJkh1WPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAQAAAA==.Malexling:BAABLgAECn8VAAIJAAYJ8xlVZAC5AQAJAAYJ8xlVZAC5AQAAAA==.',
Me='Mezrè:BAABLgAECn8gAAIKAAgJmhfkDADlAQAKAAgJmhfkDADlAQAAAA==.',
Mi='Milcah:BAAALgAECggJEwAAAA==.Mitteny:BAAALgAECgcJDQAAAA==.Mitternacht:BAAALgAECgYJDQABLgAECgcJGgARAJ0bAA==.',
Mo='Mooncraig:BAABLgAECn8jAAIaAAgJEhu1AwD0AQAaAAgJEhu1AwD0AQAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAAALgAECgYJEgAAAA==.',
Na='Nargrark:BAAALgADCgIJAgAAAA==.Nazureser:BAAALgADCgkJCQABLgAECggJGwADAGcZAA==.',
Ne='Nemeeia:BAAALgAECgIJAgAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIWAAgJYBchFQBpAgAWAAgJYBchFQBpAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn8WAAISAAcJbAmPFAD5AAASAAcJbAmPFAD5AAAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgADCgkJGwAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgADCgEJAQAAAA==.Panda:BAACLgAFFH8SAAIbAAYJGR8MAAA8AgAbAAYJGR8MAAA8AgAuAAQKfzMAAhsACQnbJEAAAMQDABsACQnbJEAAAMQDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn8dAAILAAgJ/xWIHgDkAQALAAgJ/xWIHgDkAQAAAA==.',
Pi='Picolás:BAABLgAECn8UAAIKAAYJqxeuJAA9AQAKAAYJqxeuJAA9AQAAAA==.',
Po='Pog:BAAALgAECgMJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJCQAAAA==.Primrose:BAABLgAECn8UAAIOAAcJvQ+lBgCOAQAOAAcJvQ+lBgCOAQAAAA==.Probono:BAAALgAECgYJCwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJCQAAAA==.Rainee:BAAALgADCgQJBAAAAA==.',
Re='Reprises:BAAALgAECgcJDgAAAA==.Reptar:BAAALgADCgYJBgABLgAECgUJBQAFAAAAAA==.Revini:BAABLgAECn8dAAIHAAgJcCSHAgBEAwAHAAgJcCSHAgBEAwAAAA==.Rezø:BAABLgAECn8VAAMOAAcJnwXkMgALAQAOAAYJLwbkMgALAQATAAEJPwK5hQArAAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8YAAMbAAgJcg5mGABHAQAbAAgJcg5mGABHAQAXAAEJAADtmgAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAABLgAECn8eAAIQAAYJah1MEgBvAQAQAAYJah1MEgBvAQAAAA==.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scruffy:BAABLgAECn8eAAIcAAcJLCDWAgD/AQAcAAcJLCDWAgD/AQAAAA==.',
Se='Seferres:BAABLgAECn8dAAIdAAgJbSHiCgDdAgAdAAgJbSHiCgDdAgAAAA==.Senortickle:BAAALgAECgcJEgAAAA==.',
Sh='Shaunara:BAABLgAECn8XAAMQAAgJmA84VQCjAQAQAAgJmA84VQCjAQAeAAIJTRCDJgBRAAABLgAECggJHQAdAG0hAA==.Shawts:BAABLgAECn8bAAIKAAcJKhF/GgB2AQAKAAcJKhF/GgB2AQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.',
Sk='Skragrott:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgADCgkJEQAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBAAAAA==.',
St='Starburnz:BAAALgADCgQJBAABLgAECggJIAAfAP8aAA==.Steve:BAABLgAECn8VAAIXAAcJIg/CBgAIAQAXAAcJIg/CBgAIAQAAAA==.Stimutax:BAAALgAECgYJEAAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8dAAIIAAcJdR9MGgBCAgAIAAcJdR9MGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgQJCgAAAA==.Taurenvar:BAABLgAECn8iAAIPAAgJZBxVBgCTAgAPAAgJZBxVBgCTAgAAAA==.Taziel:BAAALgAECggJDgAAAA==.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgEJAQAAAA==.',
Ti='Tingariban:BAAALgAECgUJBwAAAA==.',
To='Tohruu:BAABLgAECn8YAAIYAAgJ9wwREwCwAQAYAAgJ9wwREwCwAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8VAAIaAAcJICOPAQBmAgAaAAcJICOPAQBmAgAAAA==.',
Tw='Tweedledumm:BAABLgAECn8UAAIUAAYJ8BJyFQB4AQAUAAYJ8BJyFQB4AQAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgMJBAAAAA==.Vilehatred:BAAALgAECgYJEAAAAA==.',
Vo='Voltz:BAAALgADCgkJFwAAAA==.',
Wa='Wallis:BAAALgADCgcJBwAAAA==.Wattzazugzug:BAAALgAECgMJBgAAAA==.Waverunner:BAABLgAECn8WAAIgAAcJzBpOAgDAAQAgAAcJzBpOAgDAAQAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn8gAAIRAAgJFQqpGQAvAQARAAgJFQqpGQAvAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAECggJIwACAE8VAA==.',
Yo='Yoyoma:BAAALgAECgQJDQAAAA==.',
Za='Zakarie:BAAALgAECgYJEAAAAA==.Zaligator:BAABLgAECn8WAAMYAAYJsxeAAgBkAQAYAAYJsxeAAgBkAQAhAAMJtwX/PQB7AAAAAA==.Zayuna:BAAALgAECgQJBAAAAA==.',
Zi='Ziptoria:BAAALgAECgUJBwAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8JAAILAAQJNw0LCABGAQALAAQJNw0LCABGAQAuAAQKfx4AAgsACAljHyQNALECAAsACAljHyQNALECAAAA.Zombear:BAAALgAECgYJBwABLgAFFAYJEgAbABkfAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8gAAMfAAgJ/xoaAgBpAgAfAAgJ/xoaAgBpAgAcAAYJeRZoLQB3AQAAAA==.',
Zy='Zylph:BAAALgAECgYJCwAAAA==.',
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

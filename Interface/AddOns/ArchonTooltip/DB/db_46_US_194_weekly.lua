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

local lookup = {'DemonHunter-Devourer','Paladin-Holy','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Shaman-Restoration','Mage-Frost','Priest-Holy','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Monk-Windwalker','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Druid-Restoration','Druid-Balance','Warlock-Affliction','Hunter-Survival','Druid-Guardian','Rogue-Subtlety','DemonHunter-Havoc','Mage-Fire','Hunter-BeastMastery','Evoker-Augmentation','Hunter-Marksmanship','Druid-Feral','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelothh:BAAALgAECgQJCgAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIBAAcJxxqlMgAvAgABAAcJxxqlMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAAALgAECgQJDAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgEJAQAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAABLgAECn8VAAICAAcJIxtrCQBAAgACAAcJIxtrCQBAAgAAAA==.Akoni:BAAALgADCggJDgABLgAECgUJDgADAAAAAA==.',
Al='Allaris:BAAALgAECgYJEgAAAA==.Allíesin:BAAALgAECgQJBQAAAA==.Altryn:BAAALgADCgkJCwAAAA==.Alundrablaze:BAAALgAECgUJDwABLgAECgYJEgADAAAAAA==.',
Am='Amarixa:BAAALgADCgcJCgABLgAECgIJAwADAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8KAAIEAAMJnxo+EwAAAQAEAAMJnxo+EwAAAQAuAAQKfzAAAgQACQleIT4JAPUCAAQACQleIT4JAPUCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.',
Ar='Aranthino:BAAALgAECgYJCgAAAA==.Aryabhatta:BAAALgAECgYJEAAAAA==.',
As='Ashrom:BAAALgADCgkJDwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECgQJBAAAAA==.',
At='Athenarelia:BAAALgAFFAIJBAAAAA==.',
Ba='Baelskrim:BAAALgAECgYJEwAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn8pAAMFAAgJuR5qDwBEAgAFAAgJ4R1qDwBEAgAGAAMJig6FJABWAAAAAA==.',
Be='Beansination:BAABLgAECn8WAAMHAAkJlRfqBwAiAgAHAAkJlRfqBwAiAgAIAAUJyBT6UQA9AQAAAA==.Beefsupriem:BAAALgAECgYJCwAAAA==.Bellatrïx:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Belliaz:BAAALgAECgIJAwAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgADCgcJFAAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAECggJFwACAI0hAA==.',
Bl='Bloodlyfrost:BAABLgAECn8YAAIJAAgJPAN6cgDzAAAJAAgJPAN6cgDzAAAAAA==.Bloodyguthix:BAAALgADCgQJBAAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgEJAQABLgAECggJMwAKAAEYAA==.Breaknasweat:BAAALgAECgEJAQAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bréwtality:BAAALgADCgUJBQABLgAFFAQJCAAFAE8aAA==.',
Ca='Candyquartz:BAAALgADCgcJDQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCgAAAA==.',
Ch='Chibi:BAACLgAFFH8FAAILAAIJAgEaBQCDAAALAAIJAgEaBQCDAAAuAAQKfyAAAgsACAlEDssPALwBAAsACAlEDssPALwBAAAA.Chronokite:BAAALgAECgcJCgABLgAECgcJFwAIAL0SAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.',
Cp='Cpr:BAAALgAECgQJCAAAAA==.',
Cr='Crushed:BAABLgAECn8UAAMMAAYJcBpfEwCwAQAMAAYJcBpfEwCwAQANAAIJOwuwgwBzAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMIAAcJvRItJgA7AQAIAAcJvRItJgA7AQAHAAUJxwelZwCkAAAAAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8bAAICAAgJbBN9FQCnAQACAAgJbBN9FQCnAQAAAA==.Darkfuse:BAAALgAECgIJAgAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgADCgQJBAAAAA==.Dayman:BAAALgAECgUJCQAAAA==.',
De='Deader:BAAALgAECgMJAwAAAA==.Deadlyydot:BAAALgAECgIJBAAAAA==.Deadlyykiss:BAAALgAECgUJDQAAAA==.Demonsaber:BAAALgAECgIJAgAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAAALgAECgUJDgAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgIJAgAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAAALgAECgcJEwAAAA==.Displace:BAAALgAECgMJBAAAAA==.Divish:BAABLgAECn8ZAAIOAAgJGhpqBQAEAgAOAAgJGhpqBQAEAgAAAA==.',
Do='Dogan:BAAALgADCgYJEgAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgADCgIJAQAAAA==.',
Dr='Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgQJBQAAAA==.Droggnoir:BAAALgADCgEJAQABLgAECggJEgADAAAAAA==.Druecc:BAAALgAECgYJEgAAAA==.Druidlord:BAAALgAECgUJCQAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECgYJBwAAAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgIJAgADAAAAAA==.',
Ed='Edgerallen:BAAALgAECgYJCwAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECgcJFwAIAL0SAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgcJCQAAAA==.Elianaa:BAAALgADCgIJAgAAAA==.',
Er='Era:BAAALgAECgUJDgAAAA==.',
Ex='Executions:BAAALgADCgEJAQAAAA==.',
Fa='Fanara:BAAALgADCggJDwAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAAALgAECgYJEQAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgMJAwAAAA==.Felbládes:BAAALgADCgQJBAAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8UAAIPAAYJTRpAEgBhAQAPAAYJTRpAEgBhAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Fitua:BAABLgAECn8aAAIFAAkJhwsmUwAIAQAFAAkJhwsmUwAIAQAAAA==.Fizzbann:BAAALgADCgkJDwABLgAECgUJDgADAAAAAA==.',
Fk='Fkingbeast:BAAALgAFFAYJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgAECgcJBwAAAA==.Foutre:BAAALgAECgYJEQAAAA==.',
Fr='Fruntstabba:BAAALgADCgcJDQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzytotems:BAAALgAECgQJBQAAAA==.',
['Få']='Fång:BAAALgAECgYJBwAAAA==.',
Ga='Garo:BAABLgAECn8sAAILAAgJmB7oAgArAgALAAgJmB7oAgArAgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8ZAAIQAAcJsSJyEAA5AgAQAAcJsSJyEAA5AgAAAA==.',
Gh='Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgADCgcJBwAAAA==.',
Gl='Glert:BAABLgAECn8WAAIJAAcJShAYngCaAQAJAAcJShAYngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQRAAkJbAaYEwBnAQARAAkJbAaYEwBnAQASAAYJAwS7NQD3AAAKAAYJUAIkVQDiAAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMTAAgJzBnxHwBCAgATAAgJzBnxHwBCAgAUAAUJeQ6QTQDzAAAAAA==.Gorvax:BAAALgAECgYJEgAAAA==.',
Gr='Grimnyx:BAAALgADCgUJBQAAAA==.Grimstout:BAAALgADCgMJAwAAAA==.Gripe:BAAALgADCgEJAQAAAA==.Groguk:BAAALgAECgEJAQAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgAAAA==.',
Gw='Gwenledyr:BAABLgAECn8jAAQNAAgJ4hMFJAChAQANAAgJYBIFJAChAQAMAAUJ+xBfEACuAAAVAAIJGBImHQCIAAAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEAADAAAAAA==.Heimthrall:BAABLgAECn8iAAIQAAgJyAp1NQBtAQAQAAgJyAp1NQBtAQAAAA==.Hekatee:BAAALgADCgUJCQAAAA==.Hekkruk:BAAALgADCgcJCQAAAA==.Henshin:BAABLgAECn8UAAITAAYJCiMAEAATAgATAAYJCiMAEAATAgAAAA==.Herak:BAABLgAECn8XAAIWAAYJkggVFgATAQAWAAYJkggVFgATAQAAAA==.',
Hi='Highchairjr:BAAALgAECgYJEwAAAA==.Hildaelf:BAAALgADCgkJEQABLgAECgUJDgADAAAAAA==.',
Ho='Hojdeeznuts:BAABLgAECn8aAAICAAYJXx6tDgDzAQACAAYJXx6tDgDzAQAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgADCgkJDAAAAA==.Horazi:BAAALgAECgEJAQABLgAECgcJFQACACMbAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ii='Iil:BAAALgAECgUJEgAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgUJEgADAAAAAA==.',
Is='Istor:BAAALgAECgUJBQAAAA==.',
Ja='Jaxxia:BAAALgAECgUJEAAAAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAAALgAECgYJDgAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgADCgcJCAAAAA==.',
Jo='Joesphkony:BAAALgADCgUJBQAAAA==.',
Ju='Ju:BAAALgAECgQJCQAAAA==.Juzodots:BAAALgADCgUJBQAAAA==.Juzomido:BAACLgAFFH8IAAIWAAMJBxZ5CAATAQAWAAMJBxZ5CAATAQAuAAQKfyIAAhYACAnAHZMEAM0CABYACAnAHZMEAM0CAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn8ZAAIPAAcJdRJ7EAB3AQAPAAcJdRJ7EAB3AQAAAA==.Kaline:BAABLgAECn8XAAIXAAgJ4hqnBgBbAgAXAAgJ4hqnBgBbAgAAAA==.Karupted:BAAALgAECgYJDQAAAA==.Katianna:BAABLgAECn8eAAIIAAgJjBvCBwBvAgAIAAgJjBvCBwBvAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAAALgAECgUJDQAAAA==.Keola:BAAALgADCgUJBQABLgAECgYJBgADAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAAALgAECgYJEgAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAAALgAECgUJDgAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.',
Ko='Koraena:BAAALgAECgUJCAAAAA==.Koronuss:BAAALgADCgEJAQAAAA==.',
Kr='Krivgar:BAAALgAECgYJDQAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgEJAQAAAA==.',
Ku='Kulrig:BAABLgAECn8zAAQKAAgJARhaHwDmAQAKAAcJcRdaHwDmAQARAAcJdxdODgChAQASAAEJDgaHPAAoAAAAAA==.Kurwa:BAAALgADCgEJAQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgADCgkJGwAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgYJDwADAAAAAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEAADAAAAAA==.Lastmark:BAAALgADCgUJCAAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgADCgYJCQABLgAECgUJDgADAAAAAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgADCgUJCgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8YAAIYAAgJzx/JFwBKAgAYAAgJzx/JFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8aAAIQAAYJcRmYNQBtAQAQAAYJcRmYNQBtAQAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgUJBgAAAA==.Mathelmana:BAAALgAECgYJEgAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Mi='Miliandra:BAAALgADCgMJBQAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8YAAIRAAcJzwmKFwBCAQARAAcJzwmKFwBCAQAAAA==.Miseral:BAABLgAECn8gAAIZAAgJeBuQDACZAgAZAAgJeBuQDACZAgAAAA==.Missfrost:BAAALgAECgIJBgAAAA==.',
Mo='Moganchee:BAABLgAECn8aAAMJAAcJSAX1XwAcAQAJAAcJSAX1XwAcAQAaAAcJCgJnCADiAAAAAA==.Mordakka:BAAALgAFFAEJAQABLgAECggJMwAKAAEYAA==.Morghella:BAABLgAECn8fAAIbAAgJ7xklDwAfAgAbAAgJ7xklDwAfAgAAAA==.Morticiaa:BAAALgADCgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgADCgUJCgAAAA==.Mythros:BAAALgADCgMJBAAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Ne='Needswowaa:BAAALgAECgcJBQAAAA==.Nesmae:BAAALgAECgcJBwABLgAECgkJKwAbAGEeAA==.',
Ni='Nightwitch:BAAALgAECgEJAQAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAABLgAECn8rAAIbAAkJYR5/DADcAgAbAAkJYR5/DADcAgAAAA==.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECggJDAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgUJBQAAAA==.',
Ol='Oleyinka:BAAALgAECgMJBAAAAA==.',
Om='Omnissiah:BAABLgAECn8WAAIKAAYJVRWnLQCPAQAKAAYJVRWnLQCPAQAAAA==.',
On='Once:BAAALgAECgUJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.',
Op='Opaths:BAABLgAECn8YAAIFAAcJUBq+KgCRAQAFAAcJUBq+KgCRAQAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAAALgAECgYJEgAAAA==.',
Pa='Palaremix:BAAALgADCgEJAQAAAA==.',
Pe='Peng:BAAALgAECgYJCQAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAECggJFwACAI0hAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgIJAgAAAA==.',
Ps='Psyberollin:BAAALgAECgYJBgAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAAALgAECgYJBgAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJBgAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAAALgADCgYJBwAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAAALgAECgYJEwAAAA==.',
Re='Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgEJAgAAAA==.Revolting:BAABLgAFFH8HAAIBAAQJ9goKGwAEAQABAAQJ9goKGwAEAQAAAA==.Reze:BAAALgADCgcJBwAAAA==.Rezme:BAAALgADCgcJBwAAAA==.',
Ri='Rianne:BAAALgAECgMJAwAAAA==.Rizeen:BAAALgAECgUJBgAAAA==.',
Ro='Rowanbow:BAAALgAECgQJBAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8cAAMTAAgJ0BkZCgBoAgATAAgJ0BkZCgBoAgAUAAIJsgQfSwAqAAAAAA==.',
Sa='Saberhawk:BAAALgADCgkJHAAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakurazuka:BAABLgAECn8WAAINAAYJ4AwKgwBUAQANAAYJ4AwKgwBUAQAAAA==.Salaminizer:BAAALgAECgEJAQAAAA==.Samidudu:BAAALgAECgcJEwAAAA==.Sanath:BAABLgAECn8dAAIcAAgJIA7QEgBvAQAcAAgJIA7QEgBvAQAAAA==.Sanctusdeus:BAAALgAECgQJBAAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECggJHQAdAOAUAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8cAAIUAAcJdiRFHwAFAgAUAAcJdiRFHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAAALgAECgYJEgAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAECggJMwAKAAEYAA==.Sevotharte:BAAALgAECgIJAgAAAA==.',
Sh='Shadobread:BAAALgAECgYJEgAAAA==.Shadowglider:BAAALgAECgMJBQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8GAAIIAAMJbCSZCgBBAQAIAAMJbCSZCgBBAQAuAAQKfxwAAggACQkKI/8AAEsDAAgACQkKI/8AAEsDAAAA.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8WAAIeAAgJOhajBQC5AQAeAAgJOhajBQC5AQAAAA==.',
Si='Sib:BAAALgADCgcJEgAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDAAAAA==.',
Sk='Skeets:BAAALgADCgYJDgAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAAALgAECgYJDwAAAA==.Snke:BAAALgADCgcJBwABLgAECgYJDwADAAAAAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8oAAIFAAgJ3iEKEQAzAgAFAAgJ3iEKEQAzAgAAAA==.Sonofgods:BAAALgAECgYJEwAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.',
Sp='Spectrahl:BAABLgAECn8UAAIHAAgJYg4nFAB3AQAHAAgJYg4nFAB3AQABLgAECgkJKwAbAGEeAA==.Spedboi:BAAALgAECgYJBgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECggJGQARAI4QAA==.',
St='Starrbuck:BAAALgAECgYJEgAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8VAAIWAAcJ1xIcDACdAQAWAAcJ1xIcDACdAQAAAA==.Stryke:BAAALgAECgUJDgAAAA==.',
Su='Sunfury:BAAALgAECgEJAQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgADCgMJAwAAAA==.Suterareta:BAAALgAECgUJDQAAAA==.',
Sy='Sylareith:BAAALgAECgQJBQAAAA==.Syntara:BAABLgAECn8bAAILAAgJiheTBADjAQALAAgJiheTBADjAQAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taksun:BAABLgAECn8bAAIXAAYJShaQCwAHAQAXAAYJShaQCwAHAQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn8dAAIGAAgJUQytEwDpAAAGAAgJUQytEwDpAAAAAA==.Tav:BAAALgAECgQJBQAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAAALgAECgUJDgAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.',
Ti='Tianara:BAABLgAECn8XAAMCAAgJjSHwBAAdAwACAAgJjSHwBAAdAwAfAAQJPhVpKgC4AAAAAA==.',
Tj='Tjismyname:BAAALgAECgQJBAAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJBAAAAA==.Tolerabull:BAABLgAECn8UAAICAAYJRxSOGgB4AQACAAYJRxSOGgB4AQAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8hAAIBAAgJHBUGFwCwAQABAAgJHBUGFwCwAQAAAA==.Trojaan:BAAALgAECgkJBwAAAA==.Trulisha:BAAALgAECgYJEAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgIJAgAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8XAAIGAAgJgwa8FgDIAAAGAAgJgwa8FgDIAAAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAAALgADCgcJCgAAAA==.',
Va='Vaderon:BAAALgAECgUJCAAAAA==.Vaelanar:BAAALgADCgUJBQAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8FAAIfAAIJLQVkBwBaAAAfAAIJLQVkBwBaAAAuAAQKfyEAAh8ACAlsEJ0VAHYBAB8ACAlsEJ0VAHYBAAAA.',
Ve='Venmo:BAAALgADCgEJAQAAAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECgUJBQAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAECggJHgAIAJIjAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8XAAIGAAgJqhIrDgAwAQAGAAgJqhIrDgAwAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8VAAIbAAcJ7BA6NQA8AQAbAAcJ7BA6NQA8AQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgYJBgADAAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wigglyears:BAABLgAECn8ZAAMRAAgJjhB1LgBtAQARAAcJHRJ1LgBtAQASAAcJwQ8fKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgMJAwAAAA==.',
Ws='Wselfwulf:BAAALgADCgYJCwABLgAECgUJDgADAAAAAA==.',
Xa='Xanadaria:BAAALgAECgIJAwAAAA==.Xanalluna:BAAALgADCgkJCQABLgAECgIJAwADAAAAAA==.Xandrelyra:BAAALgADCgMJAwABLgAECgIJAwADAAAAAA==.',
Xe='Xeriirado:BAAALgADCgcJBwABLgAECgEJAQADAAAAAA==.Xeril:BAAALgADCgQJBAAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgIJAgABLgAECgQJCAADAAAAAA==.Yakushimaru:BAABLgAECn8dAAIUAAgJdRtYBwAjAgAUAAgJdRtYBwAjAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgEJAgAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgEJAQAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAAALgAFFAIJAgAAAA==.Zeith:BAABLgAECn8YAAIgAAgJ6BIkCwB0AQAgAAgJ6BIkCwB0AQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgEJAQAAAA==.',
Zi='Zildon:BAAALgAECgQJBAAAAA==.',
Zu='Zurik:BAABLgAECn8aAAIeAAgJehwuBgCbAgAeAAgJehwuBgCbAgAAAA==.',
['Äz']='Äzúlà:BAAALgAECgEJAQAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAAALgAECgYJEgAAAA==.',
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

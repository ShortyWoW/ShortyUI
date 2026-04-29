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

local lookup = {'Unknown-Unknown','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Priest-Holy','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Druid-Restoration','Druid-Balance','Warlock-Affliction','Paladin-Retribution','Hunter-Survival','Druid-Guardian','DemonHunter-Havoc','Hunter-BeastMastery','Evoker-Augmentation','Hunter-Marksmanship','Druid-Feral','Paladin-Protection','DemonHunter-Devourer',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelothh:BAAALgAECgQJCgAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ae='Aelirra:BAAALgAECgcJEgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAAALgAECgQJCAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgEJAQAAAA==.',
Ak='Akhta:BAAALgAECgcJDwAAAA==.Akoni:BAAALgADCggJDgABLgAECgQJCQABAAAAAA==.',
Al='Allaris:BAAALgAECgYJDAAAAA==.Allíesin:BAAALgAECgEJAQAAAA==.Altryn:BAAALgADCgkJCwAAAA==.Alundrablaze:BAAALgAECgUJCgABLgAECgYJDAABAAAAAA==.',
Am='Amarixa:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8HAAICAAMJnxrnBgADAQACAAMJnxrnBgADAQAuAAQKfykAAgIACAltI8sBAFgCAAIACAltI8sBAFgCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.',
Ar='Aranthino:BAAALgAECgMJBAAAAA==.Aryabhatta:BAAALgAECgUJCwAAAA==.',
As='Ashrom:BAAALgADCgcJBwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECgQJBAAAAA==.',
At='Athenarelia:BAAALgAECgYJDwAAAA==.',
Ba='Baelskrim:BAAALgAECgYJDQAAAA==.Bamdk:BAABLgAECn8hAAMDAAgJyRmODQCwAQADAAgJbBiODQCwAQAEAAMJig7OEQBXAAAAAA==.',
Be='Beansination:BAABLgAECn8UAAMFAAgJDhmIBADfAQAFAAgJDhmIBADfAQAGAAUJyBT9UQA9AQAAAA==.Beefsupriem:BAAALgAECgYJCwAAAA==.Bellatrïx:BAAALgADCgYJBgABLgAECgEJAQABAAAAAA==.Belliaz:BAAALgAECgEJAQAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgADCgYJDQAAAA==.Bigfinger:BAAALgADCgQJBQAAAA==.Biohazard:BAAALgAECgYJDgABLgAECggJFwAHAI0hAA==.',
Bl='Bloodlyfrost:BAAALgAECgcJEAAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgEJAQABLgAECggJJgAIAD4WAA==.Breakstuff:BAAALgADCgcJCQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bréwtality:BAAALgADCgUJBQABLgAECggJIQADAP8eAA==.',
Ca='Candyquartz:BAAALgADCgcJBwAAAA==.',
Ce='Celladorne:BAAALgADCgcJDAAAAA==.',
Ch='Chibi:BAABLgAECn8cAAIJAAgJBA3KDwC8AQAJAAgJBA3KDwC8AQAAAA==.Chronokite:BAAALgAECgcJBAAAAA==.',
Co='Colair:BAAALgAECgEJAQAAAA==.',
Cp='Cpr:BAAALgAECgIJAgABLgAECgQJBQABAAAAAA==.',
Cr='Crushed:BAABLgAECn8UAAMKAAYJcBpiEwCwAQAKAAYJcBpiEwCwAQALAAIJOwuFPAB7AAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMGAAcJvRJjDwBLAQAGAAcJvRJjDwBLAQAFAAUJxweaZwCkAAAAAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8bAAIHAAgJbBPNCAC4AQAHAAgJbBPNCAC4AQAAAA==.Darkfuse:BAAALgAECgIJAgAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgADCgQJBAAAAA==.Dayman:BAAALgAECgQJBwAAAA==.',
De='Deader:BAAALgAECgIJAgAAAA==.Deadlyydot:BAAALgAECgIJBAAAAA==.Deadlyykiss:BAAALgAECgUJDQAAAA==.Demonsaber:BAAALgADCgYJBgAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAAALgAECgQJCQAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dirtydotz:BAAALgADCgIJAgAAAA==.Disengage:BAAALgAECgcJDwAAAA==.Displace:BAAALgAECgMJBAAAAA==.Divish:BAAALgAECggJEgAAAA==.',
Do='Dogan:BAAALgADCgYJDQAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgADCgIJAQAAAA==.',
Dr='Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgIJAgAAAA==.Droggnoir:BAAALgADCgEJAQABLgAECgYJCgABAAAAAA==.Druecc:BAAALgAECgYJDAAAAA==.Druidlord:BAAALgAECgQJCAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECgYJBwAAAA==.',
Dy='Dyrre:BAAALgADCgEJAQAAAA==.',
Ed='Edgerallen:BAAALgAECgYJBgAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgAAAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgUJBwAAAA==.Elianaa:BAAALgADCgIJAgAAAA==.',
Er='Era:BAAALgAECgQJCQAAAA==.',
Fa='Fanara:BAAALgADCgQJBgAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgYJBgAAAA==.Farty:BAAALgAECgQJCQAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAAALgAECgQJCwAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Fitua:BAABLgAECn8VAAIDAAgJUwy+fgCGAQADAAgJUwy+fgCGAQAAAA==.Fizzbann:BAAALgADCgkJCQABLgAECgQJCQABAAAAAA==.',
Fk='Fkingbeast:BAAALgAFFAYJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgADCgYJCwAAAA==.Foutre:BAAALgAECgUJCwAAAA==.',
Fr='Fruntstabba:BAAALgADCgcJBwAAAA==.',
Fu='Fuzzytotems:BAAALgAECgMJAwAAAA==.',
['Få']='Fång:BAAALgADCggJCgAAAA==.',
Ga='Garo:BAABLgAECn8lAAIJAAcJIh8tAgDeAQAJAAcJIh8tAgDeAQAAAA==.',
Ge='Getlnmyvan:BAAALgAECgYJEgAAAA==.',
Gh='Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgADCgcJBwAAAA==.',
Gl='Glert:BAAALgAECgcJEgAAAA==.',
Go='Goinpriest:BAABLgAECn8dAAQMAAgJ5gQJDgAVAQAMAAgJ5gQJDgAVAQANAAYJAwS4NQD3AAAIAAYJUAIfVQDiAAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8gAAMOAAgJzBntHwBCAgAOAAgJzBntHwBCAgAPAAUJeQ6LTQDzAAAAAA==.Gorvax:BAAALgAECgYJDAAAAA==.',
Gr='Grimnyx:BAAALgADCgUJBQAAAA==.Grimstout:BAAALgADCgMJAwAAAA==.Groguk:BAAALgADCgUJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgAAAA==.',
Gw='Gwenledyr:BAABLgAECn8bAAQLAAgJsRPiWgC3AQALAAcJEBPiWgC3AQAKAAUJ+xATCACwAAAQAAIJGBIoHQCIAAAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.Heimthrall:BAABLgAECn8aAAIRAAgJswpTGwBKAQARAAgJswpTGwBKAQAAAA==.Hekatee:BAAALgADCgEJAQAAAA==.Hekkruk:BAAALgADCgcJCQAAAA==.Henshin:BAAALgAECgYJDgAAAA==.Herak:BAAALgAECgYJEgAAAA==.Hermiecrabbs:BAAALgADCgUJBQAAAA==.',
Hi='Highchairjr:BAAALgAECgYJEQAAAA==.Hildaelf:BAAALgADCgkJEQABLgAECgQJCQABAAAAAA==.',
Ho='Hojdeeznuts:BAABLgAECn8VAAIHAAYJgB3JBgDmAQAHAAYJgB3JBgDmAQAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgADCgkJDAAAAA==.',
Hu='Huehue:BAAALgADCgYJBgAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgQJBgAAAA==.',
Ii='Iil:BAAALgAECgUJDQAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.',
Is='Istor:BAAALgADCgcJFQAAAA==.',
Ja='Jaxxia:BAAALgAECgQJCgAAAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAAALgAECgQJBwAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jo='Joesphkony:BAAALgADCgQJBAAAAA==.',
Ju='Ju:BAAALgAECgQJCQAAAA==.Juzodots:BAAALgADCgUJBQAAAA==.Juzomido:BAACLgAFFH8FAAISAAMJHA+0BAC5AAASAAMJHA+0BAC5AAAuAAQKfyIAAhIACAnAHZEEAM0CABIACAnAHZEEAM0CAAAA.',
Ka='Kaijhin:BAAALgAECgYJEgAAAA==.Kaline:BAABLgAECn8XAAITAAgJ4hqoBgBbAgATAAgJ4hqoBgBbAgAAAA==.Karupted:BAAALgAECgQJBwAAAA==.Katianna:BAABLgAECn8bAAIGAAgJHxmqAwBCAgAGAAgJHxmqAwBCAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAAALgAECgQJCAAAAA==.Keola:BAAALgADCgUJBQABLgAECgYJBgABAAAAAA==.',
Kh='Khalli:BAAALgAECgYJDAAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAAALgAECgQJCAAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.',
Ko='Koraena:BAAALgAECgUJCAAAAA==.Koronuss:BAAALgADCgEJAQAAAA==.',
Kr='Krivgar:BAAALgAECgQJCAAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgEJAQAAAA==.',
Ku='Kulrig:BAABLgAECn8mAAMIAAgJPhZYHwDmAQAIAAcJcRdYHwDmAQAMAAcJMxNoIADVAQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgADCgYJDQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEAABAAAAAA==.Lastmark:BAAALgADCgUJCAAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgADCgYJCQABLgAECgQJCQABAAAAAA==.Lunaari:BAAALgADCgQJBAAAAA==.Lunalei:BAAALgADCgQJBQAAAA==.',
Ly='Lysius:BAAALgADCgEJAQAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAAALgAECgcJEwAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8UAAIRAAYJexeFGgBRAQARAAYJexeFGgBRAQAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgMJAwAAAA==.Mathelmana:BAAALgAECgYJDAAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Mi='Miliandra:BAAALgADCgMJBQAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAAALgAECgcJEQAAAA==.Miseral:BAABLgAECn8YAAIUAAgJeBuODACZAgAUAAgJeBuODACZAgAAAA==.Missfrost:BAAALgAECgIJAwAAAA==.',
Mo='Moganchee:BAAALgAECgcJEQAAAA==.Mordakka:BAAALgADCggJCAABLgAECggJJgAIAD4WAA==.Morghella:BAABLgAECn8XAAIVAAcJShWBCwCzAQAVAAcJShWBCwCzAQAAAA==.Morticiaa:BAAALgADCgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.',
My='Mynadshealu:BAAALgADCgQJCAAAAA==.Mythros:BAAALgADCgMJBAAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Ne='Needswowaa:BAAALgADCgcJBAAAAA==.Nesmae:BAAALgADCggJCAABLgAECggJJQAVAPIgAA==.',
Ni='Nightwitch:BAAALgAECgEJAQAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAABLgAECn8lAAIVAAgJ8iB/DADcAgAVAAgJ8iB/DADcAgAAAA==.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgYJCQAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgUJBQAAAA==.',
Ol='Oleyinka:BAAALgAECgEJAgAAAA==.',
Om='Omnissiah:BAAALgAECgYJEgAAAA==.',
On='Once:BAAALgAECgUJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgQJBwABAAAAAA==.',
Op='Opaths:BAAALgAECgcJEQAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAAALgAECgYJDAAAAA==.',
Pa='Palaremix:BAAALgADCgEJAQAAAA==.',
Pe='Peng:BAAALgAECgYJCAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAECggJFwAHAI0hAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgIJAgAAAA==.',
Ps='Psyberollin:BAAALgAECgYJBgAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJBgAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAAALgADCgQJBQAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAAALgAECgQJDAAAAA==.',
Re='Remiel:BAAALgADCgYJCQAAAA==.Renka:BAAALgAECgEJAgAAAA==.Revolting:BAAALgAFFAMJAwAAAA==.Reze:BAAALgADCgcJBwAAAA==.',
Ri='Rianne:BAAALgADCgkJEgAAAA==.Rizeen:BAAALgAECgEJAQAAAA==.',
Ro='Rowanbow:BAAALgADCgcJEwAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8UAAMOAAYJZBRTVwBNAQAOAAYJZBRTVwBNAQAPAAIJsgTVIwAuAAAAAA==.',
Sa='Saberhawk:BAAALgADCgkJHAAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakurazuka:BAAALgAECgYJEQAAAA==.Salaminizer:BAAALgADCgcJCAAAAA==.Samidudu:BAAALgAECgcJDQAAAA==.Sanath:BAABLgAECn8VAAIWAAgJrwhKCQBTAQAWAAgJrwhKCQBTAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgcJGQAXAJMWAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8ZAAIPAAYJ5iRKHwAFAgAPAAYJ5iRKHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAAALgAECgYJDAAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAECggJJgAIAD4WAA==.Sevotharte:BAAALgAECgIJAgAAAA==.',
Sh='Shadobread:BAAALgAECgYJEgAAAA==.Shadowglider:BAAALgAECgIJAgAAAA==.Shangmaul:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Sharindlar:BAABLgAECn8UAAIGAAgJjSK2AADvAgAGAAgJjSK2AADvAgAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8WAAIYAAgJOhZBAgDBAQAYAAgJOhZBAgDBAQAAAA==.',
Si='Sib:BAAALgADCgcJEAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDAAAAA==.',
Sk='Skeets:BAAALgADCgYJDgAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAAALgAECgQJCAAAAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8jAAIDAAgJ3iGZAwBlAgADAAgJ3iGZAwBlAgAAAA==.Sonofgods:BAAALgAECgQJCwAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.',
Sp='Spectrahl:BAAALgAECgYJDAABLgAECggJJQAVAPIgAA==.Spedboi:BAAALgAECgYJBgAAAA==.Spooky:BAAALgADCgUJBQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgADCgMJAwAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgcJGwAMAEcQAA==.',
St='Starrbuck:BAAALgAECgYJDAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAAALgAECgYJDQAAAA==.Stryke:BAAALgAECgQJCQAAAA==.',
Su='Sunfury:BAAALgAECgEJAQAAAA==.Sushii:BAAALgADCgMJAwAAAA==.Suterareta:BAAALgAECgQJCAAAAA==.',
Sy='Syntara:BAABLgAECn8bAAIJAAgJihfmAQDvAQAJAAgJihfmAQDvAQAAAA==.',
['Sí']='Síelys:BAAALgAECgQJBQAAAA==.',
Ta='Taksun:BAABLgAECn8VAAITAAYJJhSmEgBHAQATAAYJJhSmEgBHAQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn8ZAAIEAAcJ/QwVIABDAQAEAAcJ/QwVIABDAQAAAA==.Tav:BAAALgAECgQJBQAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAAALgAECgQJCQAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCgIJAgAAAA==.',
Ti='Tianara:BAABLgAECn8XAAMHAAgJjSH0BAAdAwAHAAgJjSH0BAAdAwAZAAQJPhVlKgC4AAAAAA==.',
Tj='Tjismyname:BAAALgADCgcJDgAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJAwAAAA==.Tolerabull:BAAALgAECgYJDgAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8ZAAIaAAcJGROETwC4AQAaAAcJGROETwC4AQAAAA==.Trulisha:BAAALgAECgYJEAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAAALgAECggJDwAAAA==.Urmaria:BAAALgAECgEJAQAAAA==.Ursalaisis:BAAALgADCgcJCgAAAA==.',
Va='Vaderon:BAAALgAECgMJAwAAAA==.Vaelanar:BAAALgADCgUJBQAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAABLgAECn8dAAIZAAgJFg+bFQB2AQAZAAgJFg+bFQB2AQAAAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voladus:BAAALgAECgYJBgABLgAECggJFgAGAMMiAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAAALgAECgYJEwAAAA==.',
['Vì']='Vìcious:BAAALgAECgYJDwAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgYJBgABAAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wigglyears:BAABLgAECn8bAAMMAAcJRxD9CQBQAQAMAAcJRxD9CQBQAQANAAYJzxEdKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgMJAwAAAA==.',
Ws='Wselfwulf:BAAALgADCgYJCwABLgAECgQJCQABAAAAAA==.',
Xa='Xanadaria:BAAALgAECgEJAQAAAA==.Xanalluna:BAAALgADCgkJCQABLgAECgEJAQABAAAAAA==.Xandrelyra:BAAALgADCgMJAwAAAA==.',
Xe='Xeriirado:BAAALgADCgcJBwABLgAECgEJAQABAAAAAA==.Xeril:BAAALgADCgQJBAAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgIJAgABLgAECgQJCAABAAAAAA==.Yakushimaru:BAABLgAECn8ZAAIPAAcJlBoaGwAqAgAPAAcJlBoaGwAqAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgEJAgAAAA==.',
Yo='Yos:BAAALgADCgMJAwAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAAALgAECgQJCQAAAA==.Zeith:BAAALgAECggJEAAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zi='Zildon:BAAALgAECgQJBAAAAA==.',
Zu='Zurik:BAABLgAECn8ZAAIYAAgJehwsBgCcAgAYAAgJehwsBgCcAgAAAA==.',
['Äz']='Äzúlà:BAAALgAECgEJAQAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAAALgAECgYJDAAAAA==.',
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

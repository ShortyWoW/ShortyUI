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

local lookup = {'Druid-Restoration','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Evoker-Augmentation','Priest-Discipline','Hunter-Marksmanship','Mage-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Priest-Shadow','Hunter-Survival','Paladin-Retribution','Paladin-Protection','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','DemonHunter-Vengeance','Evoker-Devastation','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAAALgAECgYJCwAAAA==.',
Ac='Acbabcaa:BAAALgADCgQJBQAAAA==.Aceon:BAAALgAECgYJDQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAAALgAECgcJDwAAAA==.',
Ae='Aelinjr:BAAALgAECgEJAQAAAA==.Aelyt:BAAALgADCgkJJQAAAA==.Aesirkin:BAAALgAECgIJAwAAAA==.Aeth:BAAALgAECggJEQAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAQJDAABACwaAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgYJBgAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alpharetta:BAAALgAECgcJBgAAAA==.Alsou:BAAALgADCgEJAQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8XAAIBAAgJHwxgSgB5AQABAAgJHwxgSgB5AQAAAA==.Alysona:BAAALgAECgUJDgAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amewow:BAAALgAECgQJBAAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAAALgAECgMJCAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwACAAAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgADCgYJBgAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAAALgAECgUJDQAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Aruneza:BAAALgAECgYJEQAAAA==.',
As='Asajj:BAAALgAECgQJCQAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgYJDQACAAAAAA==.Asheriz:BAAALgADCgYJBgABLgAECgcJEgACAAAAAA==.Asherous:BAAALgAECgcJEgAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgYJEAACAAAAAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashèr:BAAALgAECgUJBQABLgAECgcJEgACAAAAAA==.Aszura:BAAALgADCgIJAgAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgADCgQJAwAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJDgAAAA==.Avryn:BAAALgAECgUJDAAAAA==.',
Ay='Ayilime:BAAALgADCgcJCwAAAA==.',
Ba='Balør:BAAALgAECgMJAwABLgAECgYJEAACAAAAAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beenah:BAAALgAECgUJDQAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJCAABLgAECgYJDgACAAAAAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECggJDgACAAAAAA==.Benefitheals:BAAALgADCgMJAwAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8UAAIDAAgJ3hHnCgBJAQADAAgJ3hHnCgBJAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgABLgAECgYJCQACAAAAAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAAALgAECgkJCAAAAA==.',
Bo='Booptyboop:BAAALgAECgQJBgAAAA==.Booptydo:BAAALgADCgYJBgAAAA==.Boris:BAAALgADCgYJBQAAAA==.Bowhawk:BAAALgAECgQJCAAAAA==.',
Br='Braiin:BAAALgAECgUJBgABLgAFFAQJDAABACwaAA==.Brakken:BAAALgADCgQJBAAAAA==.Bravebolt:BAAALgADCgcJBwAAAA==.Brawll:BAAALgADCgEJAQAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAABLgAECn8XAAIEAAYJHiH0HQAsAgAEAAYJHiH0HQAsAgAAAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubblzmgee:BAAALgAECgYJEwAAAA==.',
Ca='Cadence:BAAALgAECgEJAQAAAA==.Cadin:BAABLgAECn8VAAMEAAkJSxmVDQCvAgAEAAkJSxmVDQCvAgAFAAcJYhddLwCkAQAAAA==.Cakeman:BAAALgADCgEJAQAAAA==.Capone:BAAALgADCgMJAQAAAA==.Carahz:BAAALgAECgUJDgAAAA==.Carindria:BAAALgADCgkJEQAAAA==.Caylavana:BAAALgAECgYJCgAAAA==.',
Ce='Celaylria:BAAALgAECgIJAwAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8VAAMGAAcJZxiuHwABAgAGAAcJZxiuHwABAgABAAYJmhh0OQDAAQABLgAFFAMJBwAHACcXAA==.Charmed:BAAALgAECgQJCAAAAA==.Charmíng:BAAALgAECgUJCAAAAA==.Cheryll:BAAALgAECgUJBQAAAA==.',
Ci='Cint:BAAALgAECgMJAwAAAA==.',
Cl='Cloudedjade:BAAALgAECgYJDwAAAA==.Clydè:BAAALgAECgcJEwAAAA==.',
Co='Coleybear:BAAALgAECgUJBwAAAA==.Copedk:BAAALgAECgYJEwAAAA==.Copedogg:BAAALgADCgcJDgAAAA==.Corrode:BAAALgADCgcJDQAAAA==.Covertm:BAAALgAECgQJCAAAAA==.Covertw:BAAALgADCgEJAQAAAA==.Covertx:BAABLgAECn8UAAIIAAYJdRKUCQA/AQAIAAYJdRKUCQA/AQAAAA==.',
Cr='Crashedout:BAAALgADCgEJAgAAAA==.Crew:BAAALgAECgMJAwAAAA==.Crims:BAAALgAECgYJCwAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8WAAIJAAYJ2AdEBwD5AAAJAAYJ2AdEBwD5AAAAAA==.Cyberdemonxd:BAAALgADCgMJBwABLgAECgQJDAACAAAAAA==.',
Da='Daadeedaa:BAABLgAECn8hAAIKAAgJ2yEiLgC5AgAKAAgJ2yEiLgC5AgAAAA==.Daddysparey:BAAALgAECgQJCgAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn8XAAIKAAgJdgu4hADIAQAKAAgJdgu4hADIAQAAAA==.Dardeathicus:BAACLgAFFH8HAAILAAIJ8RqjMgC+AAALAAIJ8RqjMgC+AAAuAAQKfx8AAgsACAnIIIQoAJgCAAsACAnIIIQoAJgCAAAA.Darderyag:BAAALgAECgYJCwAAAA==.Darek:BAAALgAECgEJAQAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwACAAAAAA==.Deshaman:BAAALgAECgYJDQABLgAFFAMJBgAMAHERAA==.Devilbeast:BAAALgAECgQJBwAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8YAAIFAAgJ5BOCJQDlAQAFAAgJ5BOCJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBAAAAA==.',
Do='Dolfi:BAAALgADCggJCwAAAA==.Dorlesette:BAABLgAECn8cAAINAAgJfAWpDwDmAAANAAgJfAWpDwDmAAAAAA==.',
Dr='Dreamlesnite:BAAALgAECgYJEwAAAA==.Dreidelman:BAAALgAECgEJAQAAAA==.Drkstar:BAAALgAECgUJBQAAAA==.',
Du='Dunthur:BAAALgADCgYJBgAAAA==.Durto:BAAALgADCgkJCQABLgAECgQJBQACAAAAAA==.',
Dy='Dylora:BAAALgAECgYJEwAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
Eg='Egregore:BAAALgAECgQJBgAAAA==.',
El='Eliwena:BAAALgAECggJDQAAAA==.Ellaria:BAAALgAECgYJEwAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAAALgAECgcJEAAAAA==.',
Em='Emokins:BAAALgAECgYJEwAAAA==.',
En='Endesh:BAAALgAECgYJEwAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erubus:BAABLgAFFH8FAAMOAAIJLBbbGQCbAAAOAAIJLBbbGQCbAAAPAAEJQwGOFAA9AAAAAA==.Eryss:BAAALgAECgUJDgAAAA==.',
Es='Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evoked:BAAALgAECgUJDgAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAUJDAAKAJcaAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJDQAQAH0YAA==.Faelýn:BAAALgAECgMJBwAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgcJFwABAAsTAA==.',
Fd='Fdk:BAAALgADCgMJAwAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fl='Fluoria:BAAALgAECgIJAgAAAA==.Fláreon:BAABLgAECn8UAAIRAAcJDRg/HQAsAgARAAcJDRg/HQAsAgAAAA==.',
Fr='Frutypebblz:BAAALgAECgYJDgAAAA==.',
Fu='Fuzznn:BAAALgAECgMJAwABLgABCgIJAgACAAAAAA==.',
['Fà']='Fàmous:BAAALgAECgYJEgAAAA==.',
Ga='Galabris:BAAALgAECgYJEwAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgADCgIJAgAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimligrimes:BAAALgADCgEJAQAAAA==.Gitchusum:BAAALgADCgcJBwAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAAALgAECgYJDQAAAA==.Gormladin:BAAALgAECgUJDgAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.',
['Gï']='Gïzmö:BAAALgAECgQJBwAAAA==.',
Ha='Halfang:BAAALgADCgYJBgAAAA==.Handham:BAAALgAECgMJAwAAAA==.Hasheth:BAAALgAECgIJBAAAAA==.Havocfang:BAAALgADCgIJAQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgMJAwAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgADCgcJBwABLgAECgQJBgACAAAAAA==.Hitpoints:BAAALgAECgQJCQAAAA==.',
Ho='Hobbikeen:BAAALgAECgcJEwAAAA==.Holyhope:BAAALgAECgYJCwAAAA==.Holymana:BAAALgAECgYJCgAAAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgADCgEJAQABLgAECgQJBgACAAAAAA==.Hutzil:BAAALgAECgcJEQAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Ic='Ichoh:BAAALgAECgcJDQAAAA==.',
Il='Illidianna:BAABLgAECn8WAAMSAAcJKhTAFABXAQASAAcJdBPAFABXAQATAAIJixJdXABvAAAAAA==.',
Im='Imitlol:BAAALgAECgEJAQAAAA==.',
In='Inception:BAAALgADCgcJBwAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
Ja='Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jaefury:BAAALgAECgYJDwAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgADCgkJIgACAAAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAUACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAQAAAA==.Johnnypopoff:BAAALgAECgYJEwAAAA==.Jojohunts:BAAALgAECgYJCQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Junyubych:BAAALgAECgMJAwAAAA==.Justylln:BAAALgADCgMJAgAAAA==.Justzach:BAABLgAECn8dAAIOAAgJHh3PAQBXAgAOAAgJHh3PAQBXAgAAAA==.',
['Jà']='Jàccuse:BAAALgAECgQJBwAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgADCgcJDgAAAA==.Kailm:BAAALgADCgIJAgABLgAECggJJAAQADEkAA==.Kait:BAAALgAECgEJAQAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgADCgEJAQAAAA==.Kazurend:BAACLgAFFH8IAAIVAAMJDiEECQAwAQAVAAMJDiEECQAwAQAuAAQKfxoAAhUACAnQI7wFADMDABUACAnQI7wFADMDAAAA.',
Ke='Keleira:BAAALgAECgUJCwAAAA==.Kelemvore:BAAALgADCgMJBgAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAQAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Ki='Kiel:BAAALgAECgYJBgABLgAECgYJDAACAAAAAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQAAAA==.Kiramman:BAAALgAECgMJAwAAAA==.Kithiri:BAAALgAECgIJAgAAAA==.',
Kn='Knarn:BAABLgAECn8WAAIWAAcJmh0oBACsAQAWAAcJmh0oBACsAQAAAA==.',
Ko='Koralie:BAACLgAFFH8SAAIMAAUJcRXWAACrAQAMAAUJcRXWAACrAQAuAAQKfxkAAwwACAk6HXUbAGICAAwACAk6HXUbAGICAAkABAmsDZJcANAAAAAA.',
Kr='Krillaxx:BAAALgAECgYJCwAAAA==.Krimzin:BAAALgAECgYJBgABLgAFFAIJBQAXAFAWAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAAAAA==.',
Ky='Kyliekat:BAAALgAECgEJAQAAAA==.Kyndlynn:BAAALgAECgQJBwAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgMJBQAAAA==.Lathelous:BAABLgAECn8WAAIYAAcJSyGDAQAUAgAYAAcJSyGDAQAUAgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJIgAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAAALgAECgYJDQAAAA==.',
Li='Lideina:BAAALgAECgUJEAAAAA==.Lightt:BAABLgAECn8ZAAMDAAcJNRQGKwCdAQADAAYJDxcGKwCdAQAVAAUJNQEDVQBvAAAAAA==.Liightt:BAAALgAECgUJCgAAAA==.Lilnug:BAAALgAECgQJCgAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8WAAIEAAcJTRjqDABvAQAEAAcJTRjqDABvAQAAAA==.',
Lo='Lockkjaw:BAAALgADCgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgACAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCAAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECgUJCQAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAAALgAECgYJBwAAAA==.Luckyevoker:BAAALgADCgUJBQABLgAECgYJBwACAAAAAA==.Lurien:BAAALgAECgcJCgAAAA==.',
Ly='Lyfebane:BAABLgAECn8VAAMXAAcJOQ/zFgBoAQAXAAcJOQ/zFgBoAQARAAUJ1xR0UQAzAQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAAALgAECgUJEwAAAA==.',
Ma='Magetree:BAAALgAECgQJBAABLgAECggJHwAXAEMiAA==.Mageyoucream:BAAALgADCgEJAQAAAA==.Main:BAABLgAECn8XAAIXAAcJ9wi3mQBKAQAXAAcJ9wi3mQBKAQAAAA==.Malec:BAAALgADCggJCAAAAA==.Maliceone:BAAALgADCggJEwAAAA==.Malicepaly:BAAALgADCgkJEwAAAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Max:BAABLgAECn8XAAIZAAgJ2x5sCwDAAQAZAAgJ2x5sCwDAAQAAAA==.',
Mb='Mbaku:BAAALgAECgEJAQABLgAECggJHgAVAI8ZAA==.',
Me='Melinoe:BAAALgAECgQJBwAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8PAAIaAAUJLRRiBQChAQAaAAUJLRRiBQChAQAuAAQKfxgAAxoACAnkGgEOAFYCABoACAnkGgEOAFYCAAcABQm/GosyADUBAAAA.Mishosuki:BAAALgAECgIJAwAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAAALgAECgYJEAAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECgQJBAAAAA==.',
Mn='Mnesarte:BAAALgAECgYJCwAAAA==.',
Mo='Moonkist:BAAALgAECgUJDAAAAA==.Moose:BAABLgAECn8iAAILAAcJByKyCQDjAQALAAcJByKyCQDjAQAAAA==.Morpheos:BAABLgAECn8XAAMBAAcJCxPsSAB/AQABAAcJCxPsSAB/AQAGAAQJfAd1FAC6AAAAAA==.Moxci:BAAALgAECgIJBAAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJDQAQAH0YAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8fAAMGAAkJjRjGBQCuAQAGAAgJ3RfGBQCuAQABAAMJbQrPuQBSAAAAAA==.Navariis:BAAALgADCgYJDgAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAUJEAAaABIOAA==.',
Ne='Nelrehim:BAAALgADCgQJBgAAAA==.Nephz:BAAALgADCgUJBQAAAA==.Nephzz:BAAALgAECgQJAgAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgQJCAAAAA==.',
Ni='Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAAALgAECgYJEwAAAA==.',
No='Noirheffer:BAABLgAECn8fAAMXAAgJQyL1FwDZAgAXAAgJQyL1FwDZAgAYAAQJVhDfKADDAAAAAA==.Noobishdad:BAAALgADCgEJAQAAAA==.',
Nu='Nulannatoo:BAAALgAECgMJAwAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyrrhi:BAAALgAECgQJBAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Od='Odysseus:BAAALgADCgkJEQAAAA==.',
Ol='Olgann:BAAALgAECgMJAwAAAA==.Olguita:BAAALgAECgMJBAAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgEJAQABLgAECgYJCgACAAAAAA==.',
On='Onehothealer:BAABLgAECn8WAAIVAAgJAhTmGQAQAgAVAAgJAhTmGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgMJBQAAAA==.',
Op='Opheliastar:BAABLgAECn8kAAIVAAgJbxQDBgCnAQAVAAgJbxQDBgCnAQAAAA==.',
Pa='Pad:BAAALgAECgUJDQAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn8fAAMRAAgJcAtACwCLAQARAAgJcAtACwCLAQAXAAEJuArcRAEyAAAAAA==.Pallyown:BAAALgAFFAIJBAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAAALgAECgcJDQAAAA==.Pat:BAAALgAECgEJAQAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgYJBwAAAA==.',
Ph='Pharla:BAAALgADCggJDQAAAA==.',
Pi='Pin:BAAALgAECgcJBgAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgEJAQAAAA==.',
Po='Popcorntea:BAAALgAECgEJAQAAAA==.Porgoon:BAAALgAECgQJBAAAAA==.',
Ps='Psaul:BAAALgAECgUJCgAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAMJCQAbAIgcAA==.',
Qe='Qedeshah:BAAALgADCgQJBAAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgQJBwAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECgEJAQAAAA==.Rambotank:BAAALgADCgUJBwAAAA==.Ramcharger:BAAALgAECgYJBgAAAA==.Ranen:BAABLgAECn8XAAIPAAcJCyDfAwDOAQAPAAcJCyDfAwDOAQAAAA==.Rashun:BAAALgAECgUJBwAAAA==.',
Re='Redcinnabar:BAAALgADCgcJFwAAAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgIJAgAAAA==.',
Ri='Riju:BAAALgAECgcJDAAAAA==.Rikashae:BAAALgADCgkJFQAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgIJAwAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Rollforpi:BAAALgAECgIJAgABLgAFFAQJDAABACwaAA==.Ropebunnyana:BAABLgAECn8kAAINAAkJ1R9HAABhAwANAAkJ1R9HAABhAwAAAA==.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAAALgAECgQJBgAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAECggJJwAbAKIlAA==.',
Sa='Sacra:BAAALgADCgcJBwAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Samiracy:BAAALgAECgYJEwAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Sapprot:BAAALgADCgIJAgAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAAALgAECgQJBwAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAAALgAECgYJCgAAAA==.Severa:BAAALgADCgIJAgAAAA==.',
Sh='Shalia:BAAALgADCgMJAwABLgADCgMJBgACAAAAAA==.Sharas:BAAALgADCgcJBwAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8VAAIDAAcJrw+0MAB+AQADAAcJrw+0MAB+AQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJCwAAAA==.Shyly:BAAALgAECgYJBgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn8mAAILAAgJhxIHSQAYAgALAAgJhxIHSQAYAgAAAA==.Sin:BAAALgAECgcJCAAAAA==.',
Sk='Skarletfaith:BAAALgAECgUJDQAAAA==.',
Sl='Sloanya:BAABLgAECn8fAAMNAAgJEBzKAwAIAgANAAgJEBzKAwAIAgAPAAYJKxqbJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8XAAIGAAcJzyIlAgA7AgAGAAcJzyIlAgA7AgAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgMJAwAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAMJBgAMAHERAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAMJBgAMAHERAA==.Spëcter:BAAALgAECgUJBQABLgAECgcJDgACAAAAAA==.Spëcthyr:BAAALgAECgcJDgAAAA==.',
Sq='Squishypoo:BAAALgADCgEJAQAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8FAAISAAMJBQ5xDQDxAAASAAMJBQ5xDQDxAAAuAAQKfxYAAxIACAloHUEIAO4BABIACAloHUEIAO4BABwAAgmNCjknAEwAAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAMJBQASAAUOAA==.Superlockz:BAAALgADCgkJCQABLgAFFAMJBQASAAUOAA==.Superpallyz:BAABLgAECn8eAAMRAAcJgBl0JwDvAQARAAcJgBl0JwDvAQAYAAQJEQmKMACQAAABLgAFFAMJBQASAAUOAA==.Supershamanz:BAAALgAECgUJCQABLgAFFAMJBQASAAUOAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAAALgAECgYJDwAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taldazlian:BAAALgADCgMJAwAAAA==.Taliesin:BAAALgADCgQJBAAAAA==.Tallon:BAAALgAECgEJAQABLgAECggJHQAHAAsiAA==.Tantalus:BAAALgAECgcJBQAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.',
Te='Tealet:BAAALgADCgcJBwAAAA==.Tellinor:BAAALgAECgYJBgAAAA==.Temporal:BAAALgADCgcJDgAAAA==.',
Th='Thanamoros:BAAALgAECgMJBAABLgAECggJFgAHAE0UAA==.Theroach:BAAALgAECgIJAwAAAA==.Throfin:BAAALgAECgUJCgAAAA==.',
Ti='Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8GAAIMAAMJcRGXBwAKAQAMAAMJcRGXBwAKAQAuAAQKfxwAAgwACAk7H6EVAIsCAAwACAk7H6EVAIsCAAAA.Tomate:BAAALgADCgQJBAAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgUJCQAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgIJAgABLgAECgUJDQACAAAAAA==.Treemonk:BAAALgADCgYJBgABLgAECgkJHwAGAI0YAA==.Trolvere:BAAALgAECgQJBwAAAA==.',
Tu='Tummy:BAAALgADCgcJEQAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Ty='Tygragon:BAAALgAECgQJBAAAAA==.',
Tz='Tzipporah:BAAALgAECgQJBAAAAA==.',
Ub='Ubee:BAABLgAECn8UAAISAAYJTwz+JADsAAASAAYJTwz+JADsAAAAAA==.',
Ul='Ultimakitty:BAAALgAECgMJAwAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAECggJFgAHAE0UAA==.Varabo:BAAALgAECgQJBQAAAA==.Varolina:BAAALgADCgYJCgAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECgcJDgACAAAAAA==.Velemon:BAAALgAFFAIJAwAAAA==.Velisen:BAAALgAECgQJCAAAAA==.Velthala:BAAALgAECgcJDgAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Virasdruid:BAAALgAECgIJBAAAAA==.Virusmonk:BAAALgAECgEJAgAAAA==.Vitner:BAAALgAECgUJBwAAAA==.',
Vo='Vosaleana:BAAALgADCgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8MAAIBAAQJLBrNCABGAQABAAQJLBrNCABGAQAuAAQKfycAAwEACAncG7IrAAECAAEABwmBHbIrAAECAAYABwmZIw4gAP4BAAAA.',
Vu='Vulcus:BAAALgADCgEJAwABLgAFFAQJDAABACwaAA==.Vulpii:BAAALgADCgYJBQABLgAECggJGwAcAIwfAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQACAAAAAA==.',
Wc='Wcreator:BAAALgAECgMJBQAAAA==.',
We='Weapònized:BAAALgAECgQJBwAAAA==.',
Wh='Whitestain:BAAALgAECgYJDwAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8GAAIdAAMJrCZ3AABMAQAdAAMJrCZ3AABMAQAuAAQKfyYAAh0ACAmTJpgAAIsDAB0ACAmTJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAQJDAABACwaAA==.',
Xe='Xemnastrasza:BAABLgAECn8WAAQHAAgJTRS7IQCxAQAHAAgJAhK7IQCxAQAdAAQJpgjlLQCrAAAaAAEJawV5SwArAAAAAA==.Xenonne:BAACLgAFFH8FAAISAAMJfBAnDAD+AAASAAMJfBAnDAD+AAAuAAQKfxcAAxIABgkCHddKAMkBABIABgkCHddKAMkBABMABQl3D2lGANsAAAAA.',
Xo='Xolither:BAAALgAECgYJDgAAAA==.',
Xp='Xpireedk:BAACLgAFFH8FAAIeAAIJdiNAAQDVAAAeAAIJdiNAAQDVAAAuAAQKfxkAAx4ACAn3JEEDAF8CAB4ACAn3JEEDAF8CAAsABQm/HLF1AJoBAAAA.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgIJAgAAAA==.',
Za='Zariala:BAAALgAECgEJAQAAAA==.Zatana:BAAALgAECgUJBQAAAA==.',
Ze='Zephymoo:BAABLgAECn8kAAMfAAgJ1BtSBgCXAgAfAAgJ1BtSBgCXAgAGAAEJfAPAggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAABLgAECn8WAAQcAAcJYRjcCADnAQAcAAcJYRjcCADnAQATAAQJlQVJUQClAAASAAIJPQCr9wAPAAABLgAECggJHwAMAG8dAA==.',
Zh='Zhengshi:BAAALgAECgYJEAAAAA==.',
Zo='Zoder:BAAALgAECgQJCQAAAA==.Zoose:BAAALgAECgYJEwAAAA==.Zoser:BAABLgAECn8UAAIPAAYJziUaAgArAgAPAAYJziUaAgArAgAAAA==.',
Zu='Zuckuss:BAAALgADCgQJAQAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgEJAQAAAA==.',
['ßu']='ßugs:BAAALgAECgYJDwAAAA==.',
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

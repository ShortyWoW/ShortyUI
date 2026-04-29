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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Evoker-Augmentation','Priest-Shadow','Mage-Frost','Druid-Feral','Paladin-Retribution','Priest-Holy','Priest-Discipline','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Warlock-Affliction','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Evoker-Devastation','DeathKnight-Frost','Hunter-Survival','Evoker-Preservation','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgEJAQABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8cAAICAAgJ9wxCIgDnAQACAAgJ9wxCIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAAALgAECgQJBQAAAA==.',
Al='Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAAALgADCgkJGwAAAA==.Alliautopsy:BAAALgAECgEJAgAAAA==.Althraniir:BAAALgAECgYJDAAAAA==.Altrois:BAABLgAECn8dAAIDAAYJ2hnZEQCFAQADAAYJ2hnZEQCFAQAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAABLgAECn8gAAMEAAgJWSEtCQD+AgAEAAgJWSEtCQD+AgAFAAEJwRdieABDAAAAAA==.Alystrasza:BAAALgAECgcJEwABLgAECggJIAAEAFkhAA==.',
Am='Amatsano:BAAALgAECgQJBQAAAA==.Amorsith:BAAALgAECgUJBQAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAABLgAECn8UAAMGAAYJlSLhNwDIAQAGAAUJQR/hNwDIAQAHAAMJSSKXGQAoAQAAAA==.',
An='Aneyna:BAAALgAECgQJBwAAAA==.Angrycrack:BAAALgAECgYJDQAAAA==.Animuggus:BAEALgAECgQJBQAAAA==.Anjunabeets:BAABLgAFFH8SAAMIAAYJDg2HCQCAAQAIAAUJKQ2HCQCAAQAJAAMJlgbECQDlAAAAAA==.Anthran:BAABLgAECn8dAAMKAAgJvA4lHwBYAQAKAAYJzQ4lHwBYAQALAAYJfAlaJgD7AAAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.',
Ar='Arcscythe:BAABLgAECn8UAAIMAAYJQBcKBAC3AQAMAAYJQBcKBAC3AQAAAA==.Areyouscared:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAA==.Artoo:BAAALgAECgQJBgAAAA==.',
As='Astralpanda:BAAALgAECgcJEQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8UAAINAAYJQgwvMwAxAQANAAYJQgwvMwAxAQAAAA==.',
Ba='Baconn:BAAALgAECgkJAgAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgYJFAAOAEcaAA==.Baer:BAAALgAECgYJDgAAAA==.Balgith:BAAALgAECgcJEwAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAAALgAECgUJCwAAAA==.Barron:BAAALgAECgYJDgABLgAECggJJgAPAFokAA==.Bastid:BAAALgADCgkJDwAAAA==.Battleburger:BAAALgAECgYJDwAAAA==.Bauchelaine:BAAALgAECgYJDgAAAA==.Bavunga:BAAALgAECgcJCwAAAA==.Bayle:BAAALgADCgcJBwAAAA==.',
Bc='Bchan:BAAALgAECgQJBwAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAECgQJBAAAAA==.Beoron:BAABLgAECn8hAAIQAAkJ1SHLBADKAgAQAAkJ1SHLBADKAgABLgAFFAMJBQAJAFQIAA==.Bettyßastion:BAABLgAECn8UAAIRAAcJUh07QQAiAgARAAcJUh07QQAiAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgQJBwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Booteecheeks:BAAALgADCgMJAwAAAA==.Borabora:BAAALgAFFAEJAQAAAA==.Boss:BAAALgAECgEJAQABLgAECggJHAACAPcMAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAAALgADCgkJFgAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECgUJCgAAAA==.Bruus:BAAALgADCgcJCwAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8bAAIFAAcJCRUXKQC2AQAFAAcJCRUXKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAAALgAECgYJDQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAAALgAECgYJDAAAAA==.Camabell:BAAALgADCgcJBwAAAA==.Canekii:BAAALgAECgUJBQAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathrîne:BAAALgADCgkJIAAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJKQACAOgjAA==.Ceruledge:BAAALgAECgQJBwAAAA==.',
Ch='Chaboomy:BAECLgAFFH8LAAIFAAQJuxCdAwA7AQAFAAQJuxCdAwA7AQAuAAQKfx0AAgUACAkFIOQPAKQCAAUACAkFIOQPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJBwABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgADCgYJDgAAAA==.Chips:BAABLgAECn8YAAIGAAcJYxOeCQCFAQAGAAcJYxOeCQCFAQAAAA==.Chopper:BAABLgAECn8gAAIQAAgJASBmAwABAwAQAAgJASBmAwABAwABLgAECggJIAAKANAZAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMSAAcJfBWjJgC4AQASAAcJ5hSjJgC4AQATAAQJBAYIQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgQJBQAAAA==.Collie:BAEBLgAECn8pAAIQAAkJ/yQSAAA+AwAQAAkJ/yQSAAA+AwAAAA==.Conkerin:BAAALgADCgMJAwAAAA==.',
Cr='Croissant:BAAALgAECgMJBgAAAA==.Crusadus:BAAALgAECgkJAgAAAA==.Crusible:BAAALgAECgUJCAAAAA==.',
Cu='Curzz:BAAALgADCgcJBgAAAA==.',
Cy='Cynis:BAAALgAECgEJAQAAAA==.',
Da='Dad:BAAALgADCgMJAwAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAAALgAECggJEQAAAA==.Darkseph:BAAALgAECgQJBgAAAA==.',
De='Deadcoffee:BAAALgAECgcJEwAAAA==.Deathsteak:BAAALgAECgQJBAAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8UAAIDAAcJrRKEEQCIAQADAAcJrRKEEQCIAQAAAA==.Deepman:BAAALgAECgMJAwAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8pAAMUAAkJ8iEPAAAfAwAUAAkJ8iEPAAAfAwAVAAgJkhy8FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgADCgcJBwAAAA==.Disastrous:BAACLgAFFH8FAAIJAAMJVAgZCQD2AAAJAAMJVAgZCQD2AAAuAAQKfysAAgkACQkbIK4AAO4CAAkACQkbIK4AAO4CAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECggJJQAWAB8dAA==.',
Do='Doomangel:BAAALgAECgQJBQAAAA==.Doson:BAAALgADCgMJAwAAAA==.Doubleedge:BAAALgADCgIJAgABLgAECgcJFwAPAOMUAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgMJBQABLgAECggJHQARAAsUAA==.Dragonslock:BAAALgAECgYJCgAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAINAAcJCBGGJQCQAQANAAcJCBGGJQCQAQAAAA==.Draygos:BAAALgAECgYJBgAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgADCgEJAQAAAA==.Drumboppie:BAAALgAECgcJEwAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8JAAICAAQJLQ8IBgAHAQACAAQJLQ8IBgAHAQAuAAQKfyMAAgIACQm+H+UEAEcDAAIACQm+H+UEAEcDAAAA.Duskshifter:BAAALgAECgMJAwABLgAFFAQJCQACAC0PAA==.',
['Dø']='Døc:BAABLgAECn8oAAQXAAkJTgtzCAB4AQAXAAkJRApzCAB4AQAYAAcJzQ7qRQBqAQAZAAYJzw0gFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAABLgAECn8gAAMUAAgJcxv7EAC3AQAUAAcJchj7EAC3AQARAAUJ3R4FcACcAQAAAA==.',
Ei='Eielmolate:BAACLgAFFH8LAAMLAAQJzAqJCAA8AQALAAQJzAqJCAA8AQAKAAEJagEHGwBAAAAuAAQKfyQAAwsACAmbG2o1ADYCAAsABwmbG2o1ADYCAAoAAQkAALZfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8eAAIWAAgJgxneKgBVAgAWAAgJgxneKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJDAAAAA==.',
En='Enimed:BAABLgAECn8pAAIaAAkJvBl8AQA4AgAaAAkJvBl8AQA4AgAAAA==.Ennio:BAAALgADCgkJCQAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgQJBwAAAA==.',
Ev='Evil:BAABLgAECn8gAAQKAAgJ0Bm/HwBUAQALAAcJvhdXVADKAQAKAAUJ1Ra/HwBUAQAbAAIJURrRGAC0AAAAAA==.',
Ex='Exile:BAAALgADCgcJCQABLgADCgcJDwABAAAAAA==.',
Ey='Eyebite:BAAALgAECgYJCwABLgAECggJFwAcAF0kAA==.',
Fa='Faelinius:BAAALgAECgQJCAAAAA==.Fatherseph:BAAALgADCgkJEQABLgAECgQJBgABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgQJBAABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAECgcJGgAaACEVAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Fisterdobble:BAABLgAECn8kAAIPAAkJ0RRICwD6AQAPAAkJ0RRICwD6AQAAAA==.',
Fl='Fleurdelys:BAAALgADCgkJJAAAAA==.',
Fo='Forgeddemon:BAABLgAECn8WAAMdAAcJ6wmoRQArAQAdAAcJ6wmoRQArAQAeAAMJRgYPYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgADCgcJBwAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgADCgcJBwABLgAECggJHAAfACkWAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8aAAIUAAgJxx/SAQD9AQAUAAgJxx/SAQD9AQAAAA==.Frostina:BAAALgAECgYJDQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMgAAcJDRQvGACUAQAgAAcJDRQvGACUAQAGAAEJuAvypQA5AAAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAAALgAECgQJBQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBQAAAA==.',
Gl='Glo:BAAALgAECgUJCAAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAAALgAECgYJCQAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgUJBAAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAAALgAECgQJCgAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAABLgAECn8XAAIcAAgJXSQVAgDoAgAcAAgJXSQVAgDoAgAAAA==.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAAALgADCgYJEgAAAA==.',
Gu='Gulaj:BAAALgAECgUJCgAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
Ha='Havixsucks:BAABLgAECn8iAAQbAAgJXhPdAQBnAQALAAgJ0RFcRQD7AQAbAAYJChPdAQBnAQAKAAMJ6QTCYwBHAAAAAA==.',
He='Healgimp:BAABLgAECn8bAAISAAcJKhaSCAB3AQASAAcJKhaSCAB3AQAAAA==.Healslux:BAABLgAECn8WAAIVAAgJiR3GAgBlAgAVAAgJiR3GAgBlAgAAAA==.',
Hi='Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hortzel:BAAALgAECgQJBQAAAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Huntus:BAABLgAECn8qAAMJAAkJgR61AQCiAgAJAAkJgR61AQCiAgAIAAEJlQfSkQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8VAAIRAAgJ2Q73FAB5AQARAAgJ2Q73FAB5AQAAAA==.',
Ic='Icy:BAAALgAECgEJAgAAAA==.',
Im='Immersa:BAABLgAECn8WAAMhAAgJTBabDQAAAgAhAAgJdhWbDQAAAgANAAcJjxJ+IgCqAQAAAA==.Impostor:BAAALgAECgcJDgAAAA==.',
In='Indabow:BAAALgAECggJEAAAAA==.Indamurim:BAABLgAECn8WAAMeAAgJJxKlKQCPAQAeAAcJTxClKQCPAQAdAAcJcwznPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAAALgAECggJEAAAAA==.',
Ja='Jabrick:BAAALgAECgcJDgAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECgUJBQAAAA==.Jay:BAAALgAECgEJAQAAAA==.',
Ji='Jibjabjibjab:BAABLgAECn8VAAMCAAgJPBz3IQDpAQACAAYJXx/3IQDpAQAcAAQJ5hi+DQA/AQAAAA==.Jimm:BAACLgAFFH8MAAIdAAQJMwnmBQAZAQAdAAQJMwnmBQAZAQAuAAQKfyQAAh0ACAnxElohAPcBAB0ACAnxElohAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAECgYJCgABAAAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8ZAAIWAAkJ4hruFQDTAgAWAAkJ4hruFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgEJAgAAAA==.',
Kh='Khandak:BAABLgAECn8UAAIaAAgJhBkADwAcAgAaAAgJhBkADwAcAgAAAA==.',
Ki='Kidslaps:BAAALgAECgYJDgAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAECgcJCQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgADCgQJBAABLgAECgYJCgABAAAAAA==.',
Ku='Kurisutina:BAABLgAECn8cAAIfAAgJKRasIACvAQAfAAgJKRasIACvAQAAAA==.',
La='Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgEJAQAAAA==.Lariat:BAAALgAECgYJBwAAAA==.',
Le='Leadblaster:BAAALgAECgEJAwABLgAECgMJAwABAAAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAAALgAECgcJDQAAAA==.Lemegegen:BAAALgAECgYJCQAAAA==.',
Lh='Lhux:BAABLgAECn8dAAIJAAgJ0SHBDADZAgAJAAgJ0SHBDADZAgAAAA==.Lhuxi:BAAALgAECgQJBwABLgAECggJHQAJANEhAA==.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAABLgAECn8gAAIFAAgJsB2oEQCNAgAFAAgJsB2oEQCNAgAAAA==.Lorgar:BAAALgAECgQJBAAAAA==.',
Lu='Luca:BAAALgAECgEJAgAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAQAAAA==.Lurth:BAAALgADCgYJBgAAAA==.Lurthshots:BAAALgAECgEJAwAAAA==.Luxmunkii:BAAALgAECgEJAwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJKAAXAE4LAA==.Lyxxie:BAABLgAECn8kAAMDAAkJRxXLNwBXAgADAAkJRxXLNwBXAgAiAAEJQAZaGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8XAAIPAAcJ4xQRfADZAQAPAAcJ4xQRfADZAQAAAA==.Mageus:BAAALgADCgYJBQAAAA==.Maguar:BAAALgAECggJDwAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menyin:BAAALgAECgEJAQABLgAECggJKQAYAIcaAA==.Metsutan:BAABLgAECn8pAAICAAkJ6CM5AAAdAwACAAkJ6CM5AAAdAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgADCgMJAwAAAA==.',
Mo='Moggle:BAABLgAECn8XAAMOAAcJFg2qDAApAQAOAAYJ3A2qDAApAQASAAUJAggCYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAIPAAYJHxYAvABqAQAPAAYJHxYAvABqAQAAAA==.Mokey:BAABLgAECn8YAAIbAAgJSSF9AgCWAgAbAAgJSSF9AgCWAgAAAA==.Molathom:BAAALgAECgEJAQAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgcJFwAPAOMUAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgUJBgAAAA==.Moppit:BAAALgADCgcJEQAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Moskeebee:BAABLgAECn8UAAIJAAcJyiUUEgCnAgAJAAcJyiUUEgCnAgAAAA==.',
['Mâ']='Mâtthêw:BAAALgAECgQJCAAAAA==.',
['Mø']='Møløtøv:BAAALgAECgQJDwAAAA==.',
Na='Nazuresh:BAAALgAECgEJAQABLgAECgYJEAABAAAAAA==.',
Ne='Nekcrotic:BAAALgAECgYJEQAAAA==.Nekromant:BAABLgAECn8YAAIKAAgJfhJnCwAKAgAKAAgJfhJnCwAKAgAAAA==.Nemriel:BAAALgAECgEJAQAAAA==.',
Ni='Nictus:BAAALgAECgYJEAAAAA==.Nirith:BAAALgAECgYJCAAAAA==.',
No='Nohric:BAAALgAECgUJBgAAAA==.Norsem:BAAALgAECgUJCgAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgQJBAAAAA==.',
['Nî']='Nîghtraid:BAABLgAECn8bAAITAAgJKR4iDgBYAgATAAgJKR4iDgBYAgAAAA==.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgYJBgABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJBwAAAA==.',
On='Oneth:BAAALgAECgQJBQAAAA==.Onfleek:BAAALgAECgYJDwAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opshammi:BAABLgAECn8pAAIYAAgJhxqdKADuAQAYAAgJhxqdKADuAQAAAA==.',
Or='Orakrak:BAABLgAECn8XAAIGAAcJRQwmDQBQAQAGAAcJRQwmDQBQAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgEJAQAAAA==.',
Pa='Pakapunch:BAAALgAECgEJAQAAAA==.Pallom:BAAALgAECgEJAQAAAA==.Parsera:BAAALgADCgEJAQABLgAECgkJKQATABwlAA==.Parseus:BAAALgADCgYJBwABLgAECgkJKQATABwlAA==.Parseval:BAABLgAECn8pAAMTAAkJHCUIAADRAwATAAkJHCUIAADRAwASAAQJPxscQwAsAQAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJKQAGADQlAA==.Paws:BAABLgAECn8pAAIGAAkJNCUbAABAAwAGAAkJNCUbAABAAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAAALgAECgUJCQAAAA==.',
Ph='Physix:BAAALgAECgQJBQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAECgQJCgAAAA==.Porkins:BAABLgAECn8kAAMiAAkJuxs9AACNAgAiAAkJuxs9AACNAgAaAAYJvg0JJwAGAQAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Promised:BAAALgADCgIJAgABLgAFFAEJAQABAAAAAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAABLgAECn8dAAIPAAgJBB6dCQAPAgAPAAgJBB6dCQAPAgAAAA==.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAECgYJCgABAAAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJCQAAAA==.',
Ra='Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAAALgAECgYJDgAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgADCgQJBAAAAA==.Raìdèn:BAAALgAECgYJEAAAAA==.',
Re='Replicate:BAAALgAECgEJBAAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAMJBwANAI4SAA==.Restocrayze:BAAALgADCgEJAQAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgADCgQJBAABLgAECgcJFAAJAE4VAA==.',
Ry='Ryanx:BAABLgAECn8kAAIVAAkJLCPeAACSAwAVAAkJLCPeAACSAwAAAA==.Ryri:BAAALgAECgcJEAAAAA==.',
Sa='Saatana:BAAALgAECggJEwAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Samavati:BAABLgAECn8UAAIfAAcJ0gykLgBGAQAfAAcJ0gykLgBGAQAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgQJBgAAAA==.Santoku:BAAALgAECgQJBQAAAA==.Sarah:BAABLgAECn8lAAITAAgJGxuYAgA1AgATAAgJGxuYAgA1AgAAAA==.Sassyface:BAABLgAECn8hAAIKAAkJ+weEAgBlAQAKAAkJ+weEAgBlAQAAAA==.Saveena:BAAALgAECgEJAQAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgUJBQABLgAECggJIAAEAFkhAA==.Sebbyr:BAAALgADCgMJAwAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shaduw:BAACLgAFFH8MAAIgAAQJBx9bAQBhAQAgAAQJBx9bAQBhAQAuAAQKfyQAAyAACAnOIa0DABkDACAACAnOIa0DABkDAAYACAkBDjwyAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAAALgAECgYJDgAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.',
Si='Sibbrena:BAABLgAECn8kAAIOAAkJiR37BQAuAwAOAAkJiR37BQAuAwAAAA==.Sixpacksorc:BAABLgAECn8mAAIPAAgJWiQhFQApAwAPAAgJWiQhFQApAwAAAA==.',
Sk='Skn:BAABLgAECn8dAAMVAAcJPCPQEACMAgAVAAcJPCPQEACMAgARAAIJxhioAgGQAAAAAA==.',
Sl='Slizzard:BAAALgAECgUJCgAAAA==.',
Sm='Smutty:BAAALgAECgUJCQAAAA==.',
Sn='Snackychan:BAAALgAECgcJEQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spleen:BAAALgAECgYJDgAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJBgAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAECgYJCgABAAAAAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stelthme:BAAALgAECgIJAgABLgAECgcJGQACAOYgAA==.Stormburst:BAAALgADCgIJAgABLgAECggJFwAcAF0kAA==.Strawberries:BAABLgAECn8aAAIPAAcJ6yBpDgDUAQAPAAcJ6yBpDgDUAQABLgAFFAEJAQABAAAAAA==.',
Sw='Swan:BAAALgAECgEJAQABLgAECggJHgAjAFgeAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8VAAIgAAgJ8h04AQBPAgAgAAgJ8h04AQBPAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAABLgAECn8UAAMNAAgJHBfNBgCIAQANAAgJHBfNBgCIAQAhAAEJ0wFxRAAkAAABLgAFFAMJBQAJAFQIAA==.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.',
Th='Theory:BAABLgAECn8UAAIDAAYJ9ROgJwDzAAADAAYJ9ROgJwDzAAAAAA==.Thessali:BAAALgAECgQJBQAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgYJBgAAAA==.',
To='Tomjim:BAACLgAFFH8HAAMNAAMJjhL+BwACAQANAAMJjhL+BwACAQAkAAIJbgfgEwCLAAAuAAQKfyQABA0ACAkCIAgLAMUCAA0ACAkCIAgLAMUCACQABwnkEA8dAJwBACEABglrCyciABkBAAAA.',
Tr='Trashii:BAABLgAECn8ZAAIjAAgJPRtQAgABAgAjAAgJPRtQAgABAgAAAA==.Treevive:BAABLgAECn8XAAIEAAgJmyBAHABaAgAEAAgJmyBAHABaAgAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn8WAAIRAAYJkwk7KQD+AAARAAYJkwk7KQD+AAAAAA==.',
Ts='Tsinga:BAAALgAECgMJBAAAAA==.',
Tu='Turlo:BAABLgAECn8XAAIVAAYJWR03LADVAQAVAAYJWR03LADVAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECgMJAwABLgAECggJIAAlAKUYAA==.Twostep:BAABLgAECn8gAAIlAAgJpRgUAwAsAgAlAAgJpRgUAwAsAgAAAA==.',
['Tø']='Tøm:BAACLgAFFH8KAAIRAAQJJR17AQCIAQARAAQJJR17AQCIAQAuAAQKfyIAAhEABwmkJTgYANgCABEABwmkJTgYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAQAAAA==.Unshookable:BAABLgAECn8hAAIfAAgJMB5UDACPAgAfAAgJMB5UDACPAgAAAA==.',
Ur='Ursos:BAAALgAECgUJCAAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAAALgAECggJDQAAAA==.Vallatris:BAAALgAECgQJBQAAAA==.Valsande:BAAALgADCgkJEwAAAA==.Vargr:BAAALgADCgEJAQAAAA==.',
Ve='Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAAALgAECgYJEQAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Viviera:BAAALgADCgcJBwABLgAECgQJBgABAAAAAA==.',
Vo='Voidh:BAAALgAECgUJBQAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgADCgcJDgAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAAALgAECgQJBQAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAAALgAECgcJEwAAAA==.',
Wr='Wrathofdolph:BAAALgAECgEJAQAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xy='Xyfin:BAABLgAECn8dAAIjAAgJBxmUBgCVAgAjAAgJBxmUBgCVAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.',
Za='Zaboo:BAAALgAECgYJEAAAAA==.Zandramadas:BAABLgAECn8kAAMFAAkJMiDiHAAaAgAFAAcJMR7iHAAaAgAEAAgJNRhrLAD9AQAAAA==.Zaraline:BAABLgAECn8UAAIJAAcJThVeOgDFAQAJAAcJThVeOgDFAQAAAA==.Zarasha:BAAALgAECgQJBQAAAA==.',
Ze='Zeakz:BAAALgADCgYJDgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zephon:BAABLgAECn8WAAIDAAcJ7w16ngBEAQADAAcJ7w16ngBEAQAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.',
Zi='Zinyak:BAAALgAECgQJBQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zoomiez:BAAALgAECgYJCgAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8WAAIPAAgJMBdlWgAqAgAPAAgJMBdlWgAqAgAAAA==.',
['Øv']='Øval:BAAALgAECgEJAQAAAA==.',
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

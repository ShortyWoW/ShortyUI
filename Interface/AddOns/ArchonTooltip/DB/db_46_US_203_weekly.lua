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

local lookup = {'Warlock-Destruction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Priest-Shadow','Druid-Balance','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Evoker-Augmentation','DemonHunter-Devourer','Mage-Frost','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Shaman-Elemental','Hunter-BeastMastery','Paladin-Holy','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Warrior-Fury','Hunter-Survival','DeathKnight-Frost',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Absens:BAABLgAECn8gAAIBAAgJtw4FAgCIAQABAAgJtw4FAgCIAQAAAA==.',
Ad='Adorian:BAAALgADCgMJAwABLgAECggJGgACACsjAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgADAAAAAA==.',
Ae='Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgMJBwAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgEJAgABLgAFFAQJCgAEAAIbAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJBgAAAA==.Amerlinn:BAAALgAECgMJBgAAAA==.',
An='Annaday:BAAALgAECgYJEAAAAA==.Antiock:BAABLgAECn8aAAICAAgJKyM+BAAKAwACAAgJKyM+BAAKAwAAAA==.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAAALgAECgYJCgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJCgAAAA==.',
Ar='Aralaith:BAABLgAECn8ZAAIFAAcJpyOACQDsAgAFAAcJpyOACQDsAgABLgAFFAYJDQAGAEIiAA==.Argul:BAAALgADCgEJAQAAAA==.Artto:BAAALgAECgYJDAAAAA==.',
As='Asevenhex:BAAALgADCgMJAwAAAA==.Ashbrínger:BAABLgAECn8hAAIHAAcJxh+YMwBUAgAHAAcJxh+YMwBUAgAAAA==.Association:BAAALgADCgQJBAAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJAwAAAA==.',
Av='Averax:BAAALgAECgYJCgAAAA==.Avyrax:BAAALgADCgcJDQABLgAECgYJCgADAAAAAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Ayraena:BAAALgAECgQJBQAAAA==.',
Az='Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAAALgAECgYJDwAAAA==.Bashine:BAAALgAECgYJCgAAAA==.Baylohn:BAAALgAECgYJCwAAAA==.',
Be='Bearwrestler:BAAALgAECgUJEAABLgAFFAMJBwACAJ0dAA==.',
Bi='Bier:BAAALgAECgIJAgAAAA==.Bigrig:BAAALgAECgEJAQAAAA==.Bitterman:BAAALgAECgUJDAABLgAECgYJBwADAAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAAALgAECgYJCgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.',
Bo='Boogies:BAAALgADCgQJBAAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIHAAgJExomWADaAQAHAAgJExomWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgAAAA==.',
Ca='Calduu:BAAALgAECgMJAwAAAA==.Caledia:BAAALgAECgUJBQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn8YAAIEAAYJjCOvBQAeAgAEAAYJjCOvBQAeAgAAAA==.Carinancey:BAAALgADCgYJBgAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAAALgAECgYJEAAAAA==.',
Cc='Cchaos:BAAALgADCgMJAwAAAA==.',
Ce='Celaborn:BAAALgAECgYJDwAAAA==.',
Ch='Chazaraz:BAAALgAECgYJEQAAAA==.Chevy:BAAALgAECgEJAgAAAA==.Chifreak:BAAALgAECgIJAgABLgAECgYJEgADAAAAAA==.Chillmourne:BAAALgAECgYJDAAAAA==.Chucknoris:BAAALgADCgYJCAAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAAALgAECgYJDAAAAA==.',
Cl='Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgAAAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgQJBQADAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgQJBQADAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAMJBwAIAJ4XAA==.Crucifiiks:BAAALgADCgcJBwAAAA==.Cruciö:BAAALgADCgIJAgAAAA==.Crànk:BAAALgAECgIJAwABLgAECgQJBQADAAAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgYJCwADAAAAAA==.Darkstär:BAABLgAECn8YAAICAAYJnxbbBgAyAQACAAYJnxbbBgAyAQAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAAALgAECgYJCgAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgYJCgADAAAAAA==.Deardren:BAAALgAECgUJBQAAAA==.Deepfriar:BAABLgAECn8YAAIJAAYJMSQ8EQBYAgAJAAYJMSQ8EQBYAgAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonmore:BAAALgAECgYJCgAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgADCgQJBQAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.Dewshine:BAAALgAECgQJBQAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Dhgeek:BAAALgADCgcJCQAAAA==.',
Di='Diablognomis:BAAALgAECgEJAQAAAA==.Dingô:BAAALgADCggJDgAAAA==.Dirtman:BAAALgAECgUJEQAAAA==.',
Dk='Dkrise:BAAALgADCgcJBwABLgAECgYJFAAKADQIAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCQAGAJkiAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAAALgAECgcJDAAAAA==.Doodyshamala:BAAALgADCggJCwAAAA==.Doozey:BAABLgAECn8kAAILAAgJAx9LBQAxAgALAAgJAx9LBQAxAgAAAA==.Dorigis:BAAALgADCgkJEgABLgAECgUJCgADAAAAAA==.Dotdotdotded:BAAALgAECgYJEwAAAA==.',
Dr='Drewdog:BAAALgAECgcJDQAAAA==.Drunkgerardo:BAAALgAECgEJAQAAAA==.Druyesil:BAAALgAECgEJAQAAAA==.',
Du='Dubes:BAABLgAECn8VAAIMAAYJtBDPJAA9AQAMAAYJtBDPJAA9AQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgEJAQAAAA==.',
['Dö']='Dökkálfar:BAAALgADCgkJCQAAAA==.',
Ei='Eirote:BAABLgAECn8YAAINAAYJMBgfAQBlAQANAAYJMBgfAQBlAQAAAA==.',
El='Eldari:BAABLgAECn8RAAIGAAcJuhlsCQBZAQAGAAcJuhlsCQBZAQAAAA==.Elem:BAACLgAFFH8GAAIOAAQJywjYCwAcAQAOAAQJywjYCwAcAQAuAAQKfyMAAg4ACAmcIFoYAFMCAA4ACAmcIFoYAFMCAAAA.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgADCgcJBgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCgAAAA==.',
En='Enzojr:BAABLgAECn8dAAIPAAgJhCA9AgAdAgAPAAgJhCA9AgAdAgAAAA==.',
Ep='Ephixa:BAAALgAECgQJBQAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMKAAgJgyFzCgDPAgAKAAgJdB9zCgDPAgAQAAYJZyBWDQADAgAAAA==.',
Ey='Eye:BAABLgAECn8eAAMRAAgJLSJ9AACRAgARAAgJLSJ9AACRAgASAAEJmQzJjwAoAAAAAA==.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgADCgcJCQAAAA==.Faranth:BAABLgAECn8XAAIKAAYJbBOzCgA6AQAKAAYJbBOzCgA6AQAAAA==.Faronyr:BAAALgADCgYJBgAAAA==.',
Fe='Felboi:BAAALgAECgUJCQAAAA==.Felorc:BAAALgADCggJCwAAAA==.Felynne:BAAALgAECgQJBAAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAAALgAECgYJEAAAAA==.Ferolynch:BAABLgAECn8VAAIQAAYJRCDyDgDrAQAQAAYJRCDyDgDrAQAAAA==.Ferum:BAABLgAECn8dAAIEAAgJ0hw+FACUAgAEAAgJ0hw+FACUAgAAAA==.',
Fi='Fionnan:BAAALgAECgYJDwABLgAECgYJGAAOANIKAA==.',
Fo='Forest:BAABLgAECn8kAAIGAAgJLx5+AwD7AQAGAAgJLx5+AwD7AQAAAA==.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAQAAAA==.Fryeguy:BAAALgAECgEJAQAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJAwAAAA==.',
['Fè']='Fèresha:BAAALgAECgYJCgAAAA==.',
Ga='Gallium:BAAALgAECgYJCQAAAA==.Gazerbeam:BAAALgAECgQJCQAAAA==.',
Ge='Geelock:BAAALgADCgcJFAAAAA==.Gehena:BAAALgAECgYJEgAAAQ==.Gemsareyum:BAAALgAECgUJDQABLgAFFAQJEgATAIIRAA==.Gesht:BAAALgAECgYJCgAAAA==.',
Go='Goldenbell:BAAALgADCggJCAAAAA==.Goof:BAABLgAECn8fAAIUAAgJFg2DMwCvAQAUAAgJFg2DMwCvAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgEJAQAAAA==.Grish:BAAALgAECgMJBAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgIJBgAAAA==.',
Ha='Haddor:BAAALgAECgYJDAAAAA==.Haelexi:BAAALgADCgYJCQAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgYJEgADAAAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgYJCAAAAA==.Haunter:BAAALgAECgUJDQAAAA==.Hayleigh:BAACLgAFFH8KAAIEAAQJAhulAwBcAQAEAAQJAhulAwBcAQAuAAQKfyIAAgQACAlNJHkGACQDAAQACAlNJHkGACQDAAAA.',
He='Heimdallr:BAAALgADCggJEwAAAA==.Hellbreezy:BAAALgAECggJCAAAAA==.Helldin:BAAALgAECgYJEQAAAA==.Hellenfeller:BAAALgAECgEJAQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8UAAMVAAcJGBk6BQC7AQAVAAcJ8Rc6BQC7AQAJAAIJ1BZdaACLAAAAAA==.Hittomi:BAAALgADCgIJAgAAAA==.',
Ho='Holific:BAABLgAECn8YAAIHAAYJjRVVHQA+AQAHAAYJjRVVHQA+AQAAAA==.Honeychild:BAAALgAECgQJBAAAAA==.Hotrodranger:BAAALgAECgYJCwAAAA==.',
Hu='Huckleberry:BAAALgADCgcJCwAAAA==.',
Hv='Hvac:BAABLgAECn8YAAIMAAYJjw6cJgA0AQAMAAYJjw6cJgA0AQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAAALgAECgYJCwAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJBwAAAA==.',
Im='Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJBwAAAA==.Incarnated:BAABLgAECn8WAAIIAAgJoxtEBgAhAgAIAAgJoxtEBgAhAgAAAA==.Inflammation:BAAALgADCgcJDwABLgAECgUJCAADAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAQJCgAMAJgZAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgUJBQAAAA==.Jadecross:BAAALgAECgcJEAAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgADCgMJBAAAAA==.Jerambae:BAAALgAECgYJDgAAAA==.Jerryatric:BAAALgADCgkJFQAAAA==.',
Jo='Joelah:BAAALgAECgQJCAAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgEJAQAAAA==.',
Ka='Kalfeen:BAAALgAECgMJBQAAAA==.Kallikan:BAAALgAECgYJBwAAAA==.Kanmojo:BAAALgADCgIJAgAAAA==.Kashume:BAAALgAECgMJBAAAAA==.Kasteen:BAAALgAECgEJAQAAAA==.Kazon:BAAALgADCgcJCgABLgAECggJGgACACsjAA==.Kaøs:BAAALgADCgcJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgEJAQAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAABLgAECn8jAAIHAAgJWxZsTwDzAQAHAAgJWxZsTwDzAQAAAA==.',
Kh='Khaosreborn:BAAALgAECgQJBwAAAA==.',
Ki='Kiiren:BAAALgADCgYJBgABLgAECgMJBQADAAAAAA==.Kilaaz:BAAALgAECgUJCwAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAAALgAECgcJDAABLgAFFAMJAwADAAAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kullman:BAAALgADCgYJCgAAAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAAALgAECgYJCwAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAAALgAECgUJDAAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Lealoo:BAAALgAECgQJCwABLgAECgYJDgADAAAAAA==.Legolard:BAAALgAECgUJCgAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgEJAQAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8VAAIMAAcJjQvfIQBLAQAMAAcJjQvfIQBLAQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAAALgAECgUJDAAAAA==.Liori:BAAALgADCgcJCQAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgUJDAADAAAAAA==.',
Lo='Loena:BAABLgAECn8WAAIHAAcJAhwcPQAwAgAHAAcJAhwcPQAwAgAAAA==.Lokk:BAAALgAECgEJAQABLgAECgUJDQADAAAAAA==.',
Lu='Lunabug:BAABLgAECn8eAAIWAAYJox8aBwBsAQAWAAYJox8aBwBsAQAAAA==.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAAALgAECgYJDwAAAA==.Lyandre:BAABLgAECn8dAAIJAAgJRhN9FgAoAgAJAAgJRhN9FgAoAgAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
Ma='Madan:BAAALgAECgEJAQAAAA==.Malehorelock:BAAALgAECgEJAQABLgAECgYJGAATABoiAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAAALgAECgYJCgAAAA==.Mammadruid:BAAALgAECgUJDwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Matadør:BAAALgAECgcJCAAAAA==.Mathwhiz:BAAALgAECgYJBwAAAA==.Mauldis:BAAALgAECgYJCgAAAA==.Mavgard:BAAALgADCgcJCgAAAA==.Mavgards:BAAALgADCgMJAwABLgADCgcJCgADAAAAAA==.Maxrebo:BAABLgAECn8UAAIXAAcJTBlHCwA6AQAXAAcJTBlHCwA6AQAAAA==.',
Me='Meatwàd:BAAALgAECgIJAgAAAA==.Mekanzi:BAAALgAECgQJBAAAAA==.Meliõdas:BAAALgAECgQJBQAAAA==.Merebels:BAAALgAECgQJBgAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8YAAIYAAYJwhdjCQCuAQAYAAYJwhdjCQCuAQAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAMJBwAIAJ4XAA==.Misfire:BAAALgAECgYJDAAAAA==.Mithygos:BAAALgAECgQJCQAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAAALgAECgYJEgAAAA==.Molykote:BAAALgADCgUJBQAAAA==.',
My='Myhiknee:BAAALgADCgMJAwAAAA==.Myriana:BAAALgAECgQJBAAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
Na='Nahryn:BAAALgAECgYJCgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgEJAQAAAA==.',
Ne='Nella:BAAALgADCgYJBwABLgAECgYJEgADAAAAAA==.Nerbert:BAAALgADCgYJBgABLgAECgcJFgAKADwVAA==.Neretsym:BAAALgAECgYJDwAAAA==.Nevercumdin:BAAALgADCgEJAQAAAA==.',
Ni='Nibbzz:BAAALgAECgcJEgAAAA==.Nineva:BAAALgAECgYJEAAAAA==.',
No='Nobas:BAABLgAECn8YAAMGAAYJcgiHEQDdAAAGAAYJcgiHEQDdAAAEAAEJ6wJo5AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBQAAAA==.',
Op='Oppgjør:BAAALgADCgkJCgAAAA==.',
Or='Orenge:BAAALgAECgIJBAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8WAAIKAAcJPBUCCABsAQAKAAcJPBUCCABsAQAAAA==.',
Os='Osteo:BAABLgAECn8XAAMBAAcJcwK9PwC1AAAZAAcJ6AECLwDLAAABAAcJCAK9PwC1AAAAAA==.',
Ou='Ouron:BAAALgAECgYJEgAAAA==.',
Pa='Papashrimps:BAACLgAFFH8FAAIMAAIJlBBYHACmAAAMAAIJlBBYHACmAAAuAAQKfyAAAgwACAkWICorAMYCAAwACAkWICorAMYCAAAA.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAAALgAECgYJEgAAAA==.Plaguestingr:BAABLgAECn8ZAAITAAcJxSKSAwBTAgATAAcJxSKSAwBTAgAAAA==.',
Po='Pontifex:BAAALgAECgUJDQAAAA==.Portandmorph:BAAALgAECgYJCgAAAA==.Potlock:BAAALgAECgMJBwAAAA==.',
Pr='Proey:BAABLgAECn8XAAIFAAYJQxUZCgBOAQAFAAYJQxUZCgBOAQAAAA==.Prone:BAABLgAECn8YAAIOAAYJ0gp+FgD2AAAOAAYJ0gp+FgD2AAAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Pumpidan:BAAALgAECgIJAwAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Ra='Raakotah:BAABLgAECn8pAAIGAAkJSiFjAAARAwAGAAkJSiFjAAARAwAAAA==.Raelo:BAAALgAECgUJBgAAAA==.Raiseurmug:BAAALgAECgYJBgABLgAECgYJEgADAAAAAA==.Rakash:BAABLgAECn8kAAIIAAgJHSF5BABMAgAIAAgJHSF5BABMAgAAAA==.Rascaldragon:BAAALgAECgQJBAAAAA==.Ravenlark:BAAALgAECgYJCgAAAA==.Ravia:BAAALgAECgYJEgAAAA==.Raxton:BAAALgADCgMJAwABLgAECgcJFgAKADwVAA==.Razuki:BAAALgAECgIJAwABLgAECgcJHwAUAC8jAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Resco:BAACLgAFFH8SAAIaAAUJixTDBACpAQAaAAUJixTDBACpAQAuAAQKfyoAAhoACAncJHYGAD8DABoACAncJHYGAD8DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAAALgAECgYJEAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Rook:BAACLgAFFH8HAAIIAAMJnhffDAANAQAIAAMJnhffDAANAQAuAAQKfyQAAggACAmEIh4XAPECAAgACAmEIh4XAPECAAAA.Rosenrott:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.Rosepiercer:BAAALgAECgYJEAAAAA==.Rouz:BAAALgAECgYJCgAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAABLgAECn8VAAMKAAYJJyVBEgBYAgAKAAYJJyVBEgBYAgAQAAMJFyQbJgDyAAAAAA==.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saetha:BAAALgAECgYJBgAAAA==.Samandean:BAAALgAECgYJDgAAAA==.Santhallibar:BAAALgAECgYJEAAAAA==.Sarasvati:BAAALgAECgYJCwAAAA==.Saster:BAAALgAECgUJCwAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgIJBgADAAAAAA==.',
Sc='Scrabs:BAAALgAECgcJCwAAAA==.',
Se='Sellena:BAAALgAECgYJDAABLgAECgYJDgADAAAAAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQADAAAAAA==.Senpai:BAAALgAECgYJDQABLgAFFAQJCgAEAAIbAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAABLgAECn8hAAIMAAkJZxwiHQABAwAMAAkJZxwiHQABAwAAAA==.Shango:BAAALgADCgcJCQAAAA==.Shansoracle:BAAALgAECgQJBAABLgAECgkJIQAMAGccAA==.Shed:BAABLgAECn8dAAISAAgJ6h6LDQDIAgASAAgJ6h6LDQDIAgAAAA==.Sheislegend:BAAALgADCggJHAAAAA==.Shelby:BAAALgAECgYJEgAAAA==.Shmuckman:BAAALgADCgkJEAAAAA==.Shoty:BAAALgAECgIJAgABLgAFFAMJBwAIAJ4XAA==.',
Si='Siccinok:BAAALgAECgUJCQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgADAAAAAA==.Sindorian:BAABLgAECn8YAAMTAAYJGiITJwAdAgATAAYJGiITJwAdAgAbAAQJrRTHHwDiAAAAAA==.',
Sl='Slimped:BAAALgAECgEJAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgMJAwAAAA==.',
So='Solandor:BAABLgAECn8ZAAIaAAcJJCGZAwANAgAaAAcJJCGZAwANAgAAAA==.Solarial:BAAALgAECgQJBAAAAA==.Solastra:BAAALgAECgYJCgAAAA==.Soramai:BAAALgADCgcJDQAAAA==.Soth:BAABLgAECn8YAAIIAAYJrRepFABtAQAIAAYJrRepFABtAQAAAA==.',
Sp='Sparticusdru:BAAALgAECgYJDAAAAA==.Spore:BAAALgADCgcJDAABLgAECgEJAQADAAAAAA==.',
St='Starkadia:BAAALgADCgcJBwAAAA==.Staryxia:BAACLgAFFH8FAAIcAAIJsg+9AQCtAAAcAAIJsg+9AQCtAAAuAAQKfyIAAhwACAnuIksBAPYCABwACAnuIksBAPYCAAAA.Steamdruid:BAAALgAECgMJBAAAAA==.Stonecookies:BAAALgAECgYJDAAAAA==.Stonecross:BAAALgAECgYJCQAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stormbolt:BAABLgAECn8YAAIGAAYJTBE1DgAPAQAGAAYJTBE1DgAPAQAAAA==.Striggen:BAAALgAECgQJBAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgMJAwAAAA==.Sulwen:BAACLgAFFH8NAAIGAAYJQiLsAAA9AgAGAAYJQiLsAAA9AgAuAAQKfxgAAgYACAlJJv0EAFEDAAYACAlJJv0EAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAAALgAECgQJCQAAAA==.',
Ta='Tacopie:BAAALgAECgEJAgAAAA==.Taera:BAAALgAECgYJEgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Talanazar:BAABLgAECn8XAAMKAAYJtB1LBwB8AQAQAAYJgR11FAChAQAKAAYJQxpLBwB8AQAAAA==.Tallish:BAABLgAECn8VAAILAAYJxg3xegA3AQALAAYJxg3xegA3AQAAAA==.Taterchip:BAAALgAECgUJCgAAAA==.Taylia:BAAALgAECgEJAgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgQJBwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8aAAIIAAcJzxc+DQC0AQAIAAcJzxc+DQC0AQAAAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgADCgcJEgAAAA==.',
Tw='Twiddleado:BAAALgAECgYJDgAAAA==.Twinkie:BAAALgADCgcJBwABLgAECgYJEgADAAAAAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valenora:BAAALgAECgYJDwAAAA==.Valise:BAAALgAECgEJAQAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgIJAgABLgAECgUJDQADAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Velanie:BAAALgADCgkJCgAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgADCgkJEQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Vellidedâ:BAAALgAECgYJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAAALgAECgUJCgAAAA==.',
Vi='Viperc:BAAALgADCgMJAwABLgAECgQJBwADAAAAAA==.Viridria:BAAALgAECgEJAQAAAA==.Virridian:BAAALgAECgYJDwAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgEJAgAAAA==.Voolock:BAAALgADCggJCAAAAA==.',
Wa='Wallofshame:BAAALgAECgYJEAAAAA==.Warchef:BAAALgADCgYJCgABLgAECgYJCgADAAAAAA==.Warriorclaps:BAAALgADCgMJBgAAAA==.Wartooth:BAAALgAECgYJCgAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAAALgAECgYJEAAAAA==.Wendee:BAAALgAECgUJBwAAAA==.',
Wh='Whitefóx:BAAALgAECgcJCAABLgAECgkJIQAMAGccAA==.Whitley:BAAALgAECgYJBwAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Xa='Xanthium:BAAALgAECgEJAQAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgEJAgAAAA==.Xardots:BAAALgAECgYJEwABLgAECgYJEgADAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAAALgAECgYJCgAAAA==.',
Xt='Xtronger:BAAALgAECgUJCAAAAA==.',
['Xá']='Xároth:BAAALgAECgYJEgAAAQ==.',
Ya='Yaddi:BAAALgAECgMJAwAAAA==.Yarrow:BAAALgADCgIJAgAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgADCgUJBQAAAA==.Zest:BAAALgAECgcJDwAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgADCgYJBgAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zy='Zyde:BAAALgAECgUJDQAAAA==.',
['År']='Årthas:BAAALgADCgEJAQAAAA==.',
['Øa']='Øake:BAAALgADCgIJAgAAAA==.',
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

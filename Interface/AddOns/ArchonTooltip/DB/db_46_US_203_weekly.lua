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

local lookup = {'Warlock-Destruction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Evoker-Augmentation','Priest-Shadow','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Hunter-BeastMastery','Warrior-Fury','Hunter-Survival','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Shaman-Elemental','Mage-Frost','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Priest-Discipline','Warrior-Protection','Mage-Arcane','Monk-Brewmaster','Warlock-Affliction','Paladin-Protection','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Arms','DeathKnight-Frost','Evoker-Preservation',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Absens:BAABLgAECn8jAAIBAAkJiQ8JAwDKAQABAAkJiQ8JAwDKAQAAAA==.',
Ad='Adorian:BAAALgADCgMJAwABLgAECgkJHwACANYjAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgADAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgMJBwAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgIJAwABLgAFFAUJDwAEAP8fAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgUJCwAAAA==.',
An='Anamuht:BAAALgAECgEJAQABLgAECgcJHQAFAGAeAA==.Annaday:BAABLgAECn8YAAICAAcJNQ1iFgDLAAACAAcJNQ1iFgDLAAAAAA==.Antiock:BAABLgAECn8fAAICAAkJ1iNABAAKAwACAAkJ1iNABAAKAwAAAA==.Anyamonka:BAAALgAECgYJCgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8hAAIGAAgJHiUdAQACAwAGAAgJHiUdAQACAwABLgAFFAYJDQAHAEIiAA==.Argul:BAAALgADCgEJAQAAAA==.Artto:BAAALgAECgYJEgAAAA==.',
As='Asevenhex:BAAALgADCgMJAwAAAA==.Ashbrínger:BAABLgAECn8rAAIIAAgJFiQQBADfAgAIAAgJFiQQBADfAgAAAA==.Association:BAAALgADCgQJBAAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJAwAAAA==.',
Av='Averax:BAABLgAECn8UAAMJAAYJdhcfJQBXAQAJAAYJdhcfJQBXAQAKAAEJvQ2FbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECgYJFAAJAHYXAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAAALgAFFAEJAQAAAA==.',
Az='Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMLAAYJ7QemYADSAAALAAYJ7QemYADSAAABAAQJGQQ3RwCZAAAAAA==.Bashine:BAAALgAECgYJEAAAAA==.Baylohn:BAAALgAECgYJDwAAAA==.',
Be='Bearwrestler:BAAALgAFFAEJAQABLgAFFAQJCwACAF4cAA==.',
Bi='Bier:BAAALgAECgMJBQAAAA==.Bigrig:BAAALgAECgkJCQAAAA==.Bitterman:BAAALgAECgUJDAABLgAECgYJDQADAAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAAALgAECgYJDgAAAA==.Blinx:BAAALgADCgQJBAAAAA==.',
Bo='Boogies:BAAALgADCgQJBwAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIIAAgJExogWADaAQAIAAgJExogWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgAAAA==.',
Ca='Calduu:BAAALgAECgMJAwAAAA==.Caledia:BAAALgAECgUJBQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn8fAAIEAAgJmx9ICACIAgAEAAgJmx9ICACIAgAAAA==.Carinancey:BAAALgADCgYJBgAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAABLgAECn8YAAIMAAcJugwyKgBsAQAMAAcJugwyKgBsAQAAAA==.Caylaetal:BAAALgADCgUJBQAAAA==.',
Cc='Cchaos:BAAALgAECgIJAgAAAA==.',
Ce='Celaborn:BAABLgAECn8VAAINAAYJThxVNQDUAQANAAYJThxVNQDUAQAAAA==.',
Ch='Chazaraz:BAABLgAECn8YAAMMAAgJzwhnLQBcAQAMAAgJDQhnLQBcAQAOAAQJ8walHQC7AAAAAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAECgIJAgABLgAECgYJGAAJAHoiAA==.Chillmourne:BAAALgAECgcJDQAAAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgADCgcJCQAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAAALgAECgYJEAAAAA==.',
Cl='Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECggJDQADAAAAAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgQJBQADAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgQJBQADAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAQJCwAPAK0cAA==.Crucifiiks:BAAALgADCgcJBwAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJAwABLgAECgQJBQADAAAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgYJEQADAAAAAA==.Darkstär:BAABLgAECn8fAAICAAgJRBUDCgB0AQACAAgJRBUDCgB0AQAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn8UAAMQAAYJ6wisJADJAAAQAAUJmwqsJADJAAARAAQJegMdVQB7AAAAAA==.Deardren:BAAALgAECgUJBQAAAA==.Deeanne:BAAALgADCgIJAgAAAA==.Deepfriar:BAABLgAECn8fAAISAAgJrR9eBACMAgASAAgJrR9eBACMAgAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonmore:BAAALgAECgYJDgAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgADCgQJBQAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.Dewshine:BAAALgAECgUJBwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Dhgeek:BAAALgADCggJDwAAAA==.',
Di='Diablognomis:BAAALgAECgEJAQAAAA==.Dingô:BAAALgADCggJDgAAAA==.Dirtman:BAABLgAECn8YAAITAAYJtRh9FgBgAQATAAYJtRh9FgBgAQAAAA==.',
Dk='Dkrise:BAAALgADCgcJBwABLgAECgcJGgAFAF4JAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCQAHAJkiAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAAALgAECgcJEQAAAA==.Doodyshamala:BAAALgADCggJEgAAAA==.Doozey:BAABLgAECn8kAAIJAAgJAx9zHACnAgAJAAgJAx9zHACnAgAAAA==.Dorigis:BAAALgADCgkJHQABLgAECgYJEAADAAAAAA==.Dotdotdotded:BAABLgAECn8WAAILAAgJrwVtPAA9AQALAAgJrwVtPAA9AQAAAA==.',
Dr='Drewdog:BAAALgAECgkJEgAAAA==.Drunkgerardo:BAAALgAECgIJAQAAAA==.Drunkzen:BAAALgADCgUJBQAAAA==.Druyesil:BAAALgAECgEJAQAAAA==.',
Du='Dubes:BAABLgAECn8cAAIUAAgJHBIaKgC8AQAUAAgJHBIaKgC8AQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJAgAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ei='Eirote:BAABLgAECn8fAAIVAAgJeBUUAQD7AQAVAAgJeBUUAQD7AQAAAA==.',
El='Eldari:BAABLgAECn8SAAIHAAcJuhmmDgClAQAHAAcJuhmmDgClAQAAAA==.Elem:BAACLgAFFH8MAAIWAAUJMQhcCgBEAQAWAAUJMQhcCgBEAQAuAAQKfyMAAhYACAmcIFUYAFMCABYACAmcIFUYAFMCAAAA.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgQJBAAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAABLgAECn8lAAIXAAgJSyG5AgCMAgAXAAgJSyG5AgCMAgAAAA==.',
Ep='Ephixa:BAAALgAECgYJCwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.',
Ev='Evoke:BAABLgAECn8fAAMFAAgJgyF5CgDOAgAFAAgJdB95CgDOAgAYAAYJZyBVDQADAgAAAA==.',
Ey='Eye:BAABLgAECn8eAAMZAAgJLSKKBQCtAgAZAAgJLSKKBQCtAgATAAEJmQzZjwAoAAAAAA==.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgADCgcJCQAAAA==.Faranth:BAABLgAECn8eAAIFAAgJuxZuCgDjAQAFAAgJuxZuCgDjAQAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felorc:BAAALgADCggJEgAAAA==.Felynne:BAAALgAECgQJBQAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8SAAIJAAcJ2xRSIgBlAQAJAAcJ2xRSIgBlAQAAAA==.Ferum:BAABLgAECn8lAAIEAAgJdx88FACUAgAEAAgJdx88FACUAgAAAA==.',
Fi='Fionnan:BAABLgAECn8VAAIaAAYJCwYGFQB1AAAaAAYJCwYGFQB1AAABLgAECggJHwAWAEUJAA==.',
Fo='Forest:BAABLgAECn8kAAIHAAgJLx4lDQDGAgAHAAgJLx4lDQDGAgAAAA==.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAQAAAA==.Fryeguy:BAAALgAECgEJAQAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBAAAAA==.',
['Fè']='Fèresha:BAAALgAECgcJDAAAAA==.',
Ga='Gallium:BAAALgAECgYJDgAAAA==.Gazerbeam:BAAALgAECgUJCwAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAQJGgAMAGQjAA==.Gesht:BAAALgAECgcJEQAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Go='Goldenbell:BAAALgADCggJCAAAAA==.Goof:BAABLgAECn8iAAIbAAkJCAxSGQCCAQAbAAkJCAxSGQCCAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAAALgAECgYJCgAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECggJDQADAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBgAAAA==.',
Ha='Haddor:BAAALgAECgYJEQAAAA==.Haelexi:BAAALgADCgcJCgAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgYJGAADAAAAAA==.Hamonkulous:BAAALgADCgIJAgAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Haunter:BAABLgAECn8UAAMPAAYJPR9BLgCCAQAPAAUJmyJBLgCCAQACAAIJxRE7KwAzAAAAAA==.Hayleigh:BAACLgAFFH8PAAIEAAUJ/x+lAwDcAQAEAAUJ/x+lAwDcAQAuAAQKfycAAgQACAmgJHgGACQDAAQACAmgJHgGACQDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Hellbreezy:BAAALgAECgkJCgAAAA==.Helldin:BAABLgAECn8UAAIIAAYJ8A70kgBXAQAIAAYJ8A70kgBXAQAAAA==.Hellenfeller:BAAALgAECgYJCwAAAA==.',
Hi='Hilitepriest:BAABLgAECn8VAAMcAAcJGRrmCAAFAgAcAAcJ8xjmCAAFAgASAAIJ1BZdaACLAAAAAA==.Hittomi:BAAALgADCgIJAgAAAA==.',
Ho='Holific:BAABLgAECn8fAAIIAAgJpxHDKQCbAQAIAAgJpxHDKQCbAQAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgYJEQAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.',
Hv='Hvac:BAABLgAECn8dAAIUAAYJjw55WwAmAQAUAAYJjw55WwAmAQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAAALgAECgYJEAAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCAAAAA==.',
Im='Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJCAAAAA==.Incarnated:BAACLgAFFH8FAAIPAAIJURMWUgCkAAAPAAIJURMWUgCkAAAuAAQKfxwAAg8ACAnAH88LAGwCAA8ACAnAH88LAGwCAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAADAAAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAUJDwAUACwdAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgUJBQAAAA==.Jadecross:BAABLgAECn8VAAIRAAcJzBWIDwCvAQARAAcJzBWIDwCvAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgEJAQAAAA==.Jerambae:BAAALgAECgYJEgAAAA==.Jerryatric:BAAALgAECgYJBgAAAA==.',
Jo='Joelah:BAAALgAECgQJCAAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgcJBwAAAA==.',
Ka='Kalfeen:BAAALgAECgUJCgAAAA==.Kallikan:BAAALgAECgYJEQAAAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAAALgAECgUJCQAAAA==.Kasteen:BAAALgAECgEJAQAAAA==.Kazon:BAAALgADCgcJCgABLgAECgkJHwACANYjAA==.Kaøs:BAAALgADCgcJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgEJAQAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAACLgAFFH8GAAIIAAMJKAbEJADdAAAIAAMJKAbEJADdAAAuAAQKfysAAggACAmHGFYdANoBAAgACAmHGFYdANoBAAAA.',
Kh='Khaosreborn:BAAALgAECgUJDAAAAA==.Khaotic:BAAALgADCgMJAwAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgUJCgADAAAAAA==.Kilaaz:BAAALgAECgUJDwAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAAALgAECgcJDAABLgAFFAMJBgAdAEYPAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kullman:BAAALgADCgYJCgAAAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAAALgAECgYJEQAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAAALgAECgUJDAAAAA==.Law:BAAALgAECgEJAQABLgAFFAUJDwAEAP8fAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Lealoo:BAAALgAECgQJDwABLgAECgYJFAAKAMkQAA==.Legolard:BAAALgAECgYJEAAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgEJAQAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8XAAIUAAcJLQxcTwBDAQAUAAcJLQxcTwBDAQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAAALgAECgUJEgAAAA==.Liori:BAAALgAECgEJAgAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgUJEgADAAAAAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8bAAIIAAkJVCHuIADFAQAIAAkJVCHuIADFAQAAAA==.Lokk:BAAALgAECgQJBAABLgAECgUJDQADAAAAAA==.',
Lu='Lunabug:BAABLgAECn8iAAIQAAcJJx7OCwC5AQAQAAcJJx7OCwC5AQAAAA==.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAAALgAECgYJDwAAAA==.Lyandre:BAABLgAECn8dAAISAAgJRhODFgAoAgASAAgJRhODFgAoAgAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
Ma='Madan:BAAALgAECgYJBwAAAA==.Malehorelock:BAAALgAECgEJAQABLgAECgYJGgAMABoiAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn8UAAMUAAYJmxx8MACiAQAUAAYJmxx8MACiAQAeAAEJ5AjeHAA5AAAAAA==.Mammadruid:BAAALgAECgYJEwAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Matadør:BAAALgAECgcJCgAAAA==.Mathwhiz:BAAALgAECgYJDQAAAA==.Mauldis:BAABLgAECn8UAAITAAYJJAY1KgDbAAATAAYJJAY1KgDbAAAAAA==.Mavgard:BAAALgADCgcJCgAAAA==.Mavgards:BAAALgADCgMJAwABLgADCgcJCgADAAAAAA==.Maxrebo:BAABLgAECn8VAAIfAAcJEBpSDwCbAQAfAAcJEBpSDwCbAQAAAA==.',
Me='Meatwàd:BAAALgAECgIJAgAAAA==.Mekanzi:BAAALgAECgQJBAAAAA==.Meliõdas:BAAALgAECgQJBwAAAA==.Merebels:BAAALgAECgQJBgAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8fAAIgAAgJ7hMJAgDNAQAgAAgJ7hMJAgDNAQAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAQJCwAPAK0cAA==.Misfire:BAAALgAECgYJEgAAAA==.Mithygos:BAAALgAECgUJDQAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn8YAAMHAAYJIwdZLQCnAAAHAAUJGQZZLQCnAAAaAAEJRwskIQAlAAAAAA==.Molykote:BAAALgADCgYJCwAAAA==.',
My='Myhiknee:BAAALgADCgMJAwAAAA==.Myriana:BAAALgAECgQJBAAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
Na='Nahryn:BAABLgAECn8UAAIEAAYJvyEzDABGAgAEAAYJvyEzDABGAgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgQJBAABLgAECgYJGAARAIgiAA==.Nerbert:BAAALgADCgYJBgABLgAECggJHgAFAIcUAA==.Neretsym:BAABLgAECn8VAAIMAAYJ9hzGJACHAQAMAAYJ9hzGJACHAQAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAAALgAECgcJEgAAAA==.Nineva:BAABLgAECn8YAAIEAAcJZANNQgDIAAAEAAcJZANNQgDIAAAAAA==.',
No='Nobas:BAABLgAECn8fAAMHAAgJUQiNGAA5AQAHAAgJUQiNGAA5AQAEAAEJ6wJs5AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBQAAAA==.',
Op='Oppgjør:BAAALgAECgQJBQAAAA==.',
Or='Oreeree:BAAALgADCgUJBQAAAA==.Orenge:BAAALgAECgQJBwAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8eAAIFAAgJhxTUDQCtAQAFAAgJhxTUDQCtAQAAAA==.',
Os='Osteo:BAABLgAECn8bAAMLAAcJHwM5XADdAAALAAcJEwM5XADdAAABAAcJCAK8PwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8aAAMWAAcJjhQnHACCAQAWAAYJBxUnHACCAQATAAQJrQw7ZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8IAAIUAAMJ1RLTMgACAQAUAAMJ1RLTMgACAQAuAAQKfy0AAhQACQlrIC8HAMYCABQACQlrIC8HAMYCAAAA.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8YAAIhAAYJEhnYCQBpAQAhAAYJEhnYCQBpAQAAAA==.Plaguestingr:BAABLgAECn8hAAIMAAgJyiEMBQCqAgAMAAgJyiEMBQCqAgAAAA==.',
Po='Pontifex:BAABLgAECn8UAAISAAYJ8Bi2EACdAQASAAYJ8Bi2EACdAQAAAA==.Portandmorph:BAAALgAECgYJDwAAAA==.Potlock:BAAALgAECgMJBwAAAA==.',
Pr='Proey:BAABLgAECn8eAAMGAAgJVBIYDAC+AQAGAAgJVBIYDAC+AQAcAAUJIxPMFwAuAQAAAA==.Prone:BAABLgAECn8fAAIWAAgJRQm3JwAwAQAWAAgJRQm3JwAwAQAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Ra='Raakotah:BAABLgAECn8yAAIHAAkJ6yL3AAAsAwAHAAkJ6yL3AAAsAwAAAA==.Raelo:BAAALgAECgYJDAAAAA==.Raiseurmug:BAAALgAECggJDQAAAA==.Rakash:BAABLgAECn8kAAIPAAgJHSGoIAC/AgAPAAgJHSGoIAC/AgAAAA==.Rascaldragon:BAAALgAECgQJBAAAAA==.Ravenlark:BAAALgAECgcJEQAAAA==.Ravia:BAABLgAECn8YAAMJAAYJeiJcEADtAQAJAAYJFCFcEADtAQAiAAUJUiE5CQDdAQAAAA==.Razuki:BAAALgAECgIJAwABLgAECggJIgAbAJ0hAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAQAAAA==.Resco:BAACLgAFFH8YAAINAAYJbheeAADMAQANAAYJbheeAADMAQAuAAQKfywAAg0ACAncJHYGAD8DAA0ACAncJHYGAD8DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAAALgAECggJEwAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Rook:BAACLgAFFH8LAAIPAAQJrRzzEABqAQAPAAQJrRzzEABqAQAuAAQKfyQAAg8ACAmEIiAXAPECAA8ACAmEIiAXAPECAAAA.Rosenrott:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Rosepiercer:BAABLgAECn8WAAIMAAYJqCMlGgBrAgAMAAYJqCMlGgBrAgAAAA==.Rouz:BAAALgAECgYJEAAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8GAAMFAAMJ2iBwEQAkAQAFAAMJ2iBwEQAkAQAYAAEJZiLeBwBmAAAuAAQKfxgAAwUACAl8JWsNALMBAAUACAl8JWsNALMBABgAAwkXJCAmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saetha:BAAALgAECgYJCwAAAA==.Samandean:BAABLgAECn8UAAIKAAYJyRBEMABOAQAKAAYJyRBEMABOAQAAAA==.Santhallibar:BAABLgAECn8YAAIjAAcJ+wEFDAC6AAAjAAcJ+wEFDAC6AAAAAA==.Sarasvati:BAAALgAECgYJDwAAAA==.Saster:BAAALgAECgYJDQAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBgADAAAAAA==.',
Sc='Scrabs:BAAALgAECggJDQAAAA==.',
Se='Sellena:BAAALgAECgYJEAABLgAECgYJFAAKAMkQAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQADAAAAAA==.Senpai:BAAALgAECgYJEgABLgAFFAUJDwAEAP8fAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8IAAIUAAMJXBLbMQAFAQAUAAMJXBLbMQAFAQAuAAQKfyYAAhQACQmQHjwIALcCABQACQmQHjwIALcCAAAA.Shango:BAAALgADCgcJCQAAAA==.Shansoracle:BAAALgAECgQJBAABLgAFFAMJCAAUAFwSAA==.Shed:BAABLgAECn8iAAITAAgJEyFJBgBGAgATAAgJEyFJBgBGAgAAAA==.Sheislegend:BAAALgAECgEJAQAAAA==.Shelby:BAABLgAECn8YAAISAAYJAB39CwDkAQASAAYJAB39CwDkAQAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shoty:BAAALgAECgIJAgABLgAFFAQJCwAPAK0cAA==.',
Si='Siccinok:BAAALgAECgUJDAAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgADAAAAAA==.Sindorian:BAABLgAECn8aAAMMAAYJGiIQJwAdAgAMAAYJGiIQJwAdAgAOAAUJxBnIHwDiAAAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgEJAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJBAAAAA==.',
So='Solandor:BAABLgAECn8fAAMNAAgJ5B32BgBCAgANAAgJ5B32BgBCAgAkAAIJARdNKABIAAAAAA==.Solarial:BAAALgAECgQJCAAAAA==.Solastra:BAAALgAECgYJEAAAAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn8fAAIPAAcJkhcUKQCYAQAPAAcJkhcUKQCYAQAAAA==.',
Sp='Sparticusdru:BAAALgAECgcJDgAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
St='Starkadia:BAAALgADCgcJBwAAAA==.Staryxia:BAACLgAFFH8IAAIlAAMJkhLNAgD+AAAlAAMJkhLNAgD+AAAuAAQKfykAAiUACQmvIEsBAPYCACUACQmvIEsBAPYCAAAA.Steamdruid:BAAALgAECgYJCwAAAA==.Stonecookies:BAAALgAECgcJEwAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stormbolt:BAABLgAECn8fAAIHAAgJUA54EgB3AQAHAAgJUA54EgB3AQAAAA==.Striggen:BAAALgAECgQJCAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgQJBAAAAA==.Sulwen:BAACLgAFFH8NAAIHAAYJQiLsAAA9AgAHAAYJQiLsAAA9AgAuAAQKfxgAAgcACAlJJvwEAFEDAAcACAlJJvwEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAAALgAECgUJCwAAAA==.',
Ta='Tacopie:BAAALgAECgQJBQAAAA==.Taera:BAABLgAECn8YAAIRAAYJiCIbBwBMAgARAAYJiCIbBwBMAgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8dAAMFAAcJYB6eBwAZAgAFAAcJPx6eBwAZAgAYAAYJgR14FAChAQAAAA==.Talavenn:BAAALgAECgEJAgAAAA==.Tallish:BAABLgAECn8VAAIJAAYJxg3wegA3AQAJAAYJxg3wegA3AQAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAAALgAECgYJEAAAAA==.Taylia:BAAALgAECgQJBQAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgYJCwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8iAAIPAAgJ7h3XCgB3AgAPAAgJ7h3XCgB3AgAAAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgADCggJFgAAAA==.',
Tr='Triand:BAAALgAECgcJBgAAAA==.',
Tw='Twiddleado:BAABLgAECn8WAAIUAAgJCREYMACjAQAUAAgJCREYMACjAQAAAA==.Twinkie:BAAALgADCgcJBwABLgAECgYJGAAJAHoiAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgUJBQAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgEJAwAAAA==.Valenora:BAAALgAECgYJEwAAAA==.Valise:BAAALgAECgYJBwAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgIJAgABLgAECgUJDQADAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECgQJBAAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Vellidedâ:BAAALgAECgYJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAAALgAECgYJDAAAAA==.',
Vi='Viperc:BAAALgADCgMJAwABLgAECgQJCQADAAAAAA==.Viridria:BAAALgAECgEJAQAAAA==.Virridian:BAABLgAECn8VAAIMAAYJCh7FLQD8AQAMAAYJCh7FLQD8AQAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgADCgMJAwAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBQAAAA==.Voolock:BAAALgADCggJCAAAAA==.',
Wa='Wallofshame:BAAALgAECgYJEAAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgYJFAAUAJscAA==.Warriorclaps:BAAALgADCgcJDQAAAA==.Wartooth:BAABLgAECn8UAAMLAAYJ8BIaVwDsAAALAAUJlg8aVwDsAAABAAMJnhNvSwCLAAAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8YAAIdAAcJ5RXkCgB6AQAdAAcJ5RXkCgB6AQAAAA==.Wendee:BAAALgAECgYJDQAAAA==.',
Wh='Whitefóx:BAAALgAFFAIJAgABLgAFFAMJCAAUAFwSAA==.Whitley:BAAALgAECggJCQAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Xa='Xanthium:BAAALgAECgYJBwAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgQJBgAAAA==.Xardots:BAABLgAECn8bAAIBAAcJ8hPdBgBIAQABAAcJ8hPdBgBIAQABLgAECgYJGAADAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn8UAAImAAYJmw2SDQAoAQAmAAYJmw2SDQAoAQAAAA==.',
Xt='Xtronger:BAAALgAECgcJDwAAAA==.',
['Xá']='Xároth:BAAALgAECgYJGAAAAQ==.',
Ya='Yaddi:BAAALgAECgMJAwAAAA==.Yarrow:BAAALgADCgkJCQAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgEJAQAAAA==.Zest:BAABLgAECn8XAAImAAkJ9Q9ABQAKAgAmAAkJ9Q9ABQAKAgAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgAECgEJAgAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
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

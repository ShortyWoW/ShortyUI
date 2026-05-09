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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Evoker-Augmentation','Priest-Shadow','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Shaman-Elemental','Warrior-Protection','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Paladin-Protection','Priest-Discipline','DeathKnight-Frost','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Absens:BAABLgAECn8uAAMBAAkJ/RGSBADBAQABAAkJgA+SBADBAQACAAgJUg9wBACZAQAAAA==.',
Ad='Adorian:BAAALgAECgcJBwABLgAECgkJIAADANojAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgMJBwAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgUJCQABLgAFFAUJFAAFAIkgAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgUJCwAAAA==.',
An='Anamuht:BAAALgAECgEJAQABLgAECggJJwAGAPIeAA==.Annaday:BAABLgAECn8bAAIDAAcJOA1tGgD0AAADAAcJOA1tGgD0AAAAAA==.Antiock:BAABLgAECn8gAAIDAAkJ2iNBBAAKAwADAAkJ2iNBBAAKAwAAAA==.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAAALgAECgYJCgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8hAAIHAAgJXiU6AgD5AgAHAAgJXiU6AgD5AgABLgAFFAcJEAAIAMcjAA==.Argul:BAAALgADCgEJAQAAAA==.Artto:BAABLgAECn8YAAIJAAYJ/xBNZAAlAQAJAAYJ/xBNZAAlAQAAAA==.',
As='Asevenhex:BAAALgADCgMJAwAAAA==.Ashbrínger:BAABLgAECn8zAAIJAAgJsiWjBAAHAwAJAAgJsiWjBAAHAwAAAA==.Association:BAAALgADCgQJBAAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn8aAAMKAAYJlRgeMwBpAQAKAAYJlRgeMwBpAQALAAEJvQ2FbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECgYJGgAKAJUYAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAAALgAFFAEJAQAAAA==.',
Az='Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMMAAYJ7we7fADNAAAMAAYJ7we7fADNAAABAAQJGQQ5RwCZAAAAAA==.Bashine:BAAALgAECgYJEQABLgAFFAUJEgANAMQfAA==.Baylohn:BAABLgAECn8WAAIOAAcJ8hZZKwCiAQAOAAcJ8hZZKwCiAQAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIPAAgJ1BcDLADxAQAPAAgJ1BcDLADxAQABLgAFFAQJDwADAJAgAA==.',
Bi='Bier:BAAALgAECgMJBQAAAA==.Bigrig:BAAALgAECgkJCwAAAA==.Bitterman:BAAALgAECgcJEwAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8UAAMQAAYJbBQKDAAHAQAQAAUJuRcKDAAHAQAKAAYJmgwcWQDxAAAAAA==.Blinx:BAAALgADCgQJBAAAAA==.',
Bo='Boogies:BAAALgADCgQJBwAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIJAAgJGBogWADaAQAJAAgJGBogWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.',
['Bá']='Bád:BAAALgADCggJDgAAAA==.',
Ca='Calduu:BAAALgAECgMJAwAAAA==.Caledia:BAAALgAECgYJCwAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn8pAAIFAAgJVyIfCADKAgAFAAgJVyIfCADKAgAAAA==.Carinancey:BAAALgAECgEJAQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAABLgAECn8YAAIOAAcJvgxKPQBYAQAOAAcJvgxKPQBYAQAAAA==.Caylaetal:BAAALgADCgUJBQAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8WAAIRAAYJsBxUNQDUAQARAAYJsBxUNQDUAQAAAA==.',
Ch='Chazaraz:BAABLgAECn8iAAMSAAgJtgrzEACeAQASAAcJQAnzEACeAQAOAAgJEQgeQQBKAQAAAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAECgIJAgABLgAECgcJGQAKAMMiAA==.Chillmourne:BAAALgAECgcJDQAAAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgADCgcJCQAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAABLgAECn8WAAIPAAYJVQxYggANAQAPAAYJVQxYggANAQAAAA==.',
Cl='Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECggJFwATAHQQAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgQJBQAEAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgQJBQAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAQJDwANAKwcAA==.Crucifiiks:BAAALgAECgEJAQAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJAwABLgAECgQJBQAEAAAAAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Darkstär:BAABLgAECn8pAAIDAAgJ7RpJCAADAgADAAgJ7RpJCAADAgAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn8aAAQUAAYJ6gi7LwDHAAAUAAUJmgq7LwDHAAATAAQJ8QJeRACFAAAVAAQJFgQpRgBkAAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgYJGgAMAFoUAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deeanne:BAAALgAECgMJAwAAAA==.Deepfriar:BAABLgAECn8pAAIWAAgJkiIZBQC3AgAWAAgJkiIZBQC3AgAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonmore:BAABLgAECn8UAAMLAAYJBQtzOwASAQALAAYJXwlzOwASAQAQAAUJIwiSEwCRAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgADCggJDAAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCQAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgADCggJFgAAAA==.',
Di='Diablognomis:BAAALgAECgIJAwAAAA==.Dingô:BAAALgADCggJEgAAAA==.Dirtman:BAABLgAECn8aAAIXAAYJcBn7HQBeAQAXAAYJcBn7HQBeAQAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECgcJHAAGAO0LAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAIAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAAALgAECgcJEwAAAA==.Doodyshamala:BAAALgADCggJGQAAAA==.Doozey:BAABLgAECn8kAAIKAAgJlx/dDwBFAgAKAAgJlx/dDwBFAgAAAA==.Dorigis:BAAALgADCgkJJgABLgAECgcJFgAYAP8gAA==.Dotdotdotded:BAABLgAECn8WAAIMAAgJtwVzUQA2AQAMAAgJtwVzUQA2AQAAAA==.',
Dr='Drewdog:BAABLgAECn8cAAMOAAYJLxZ6SAA0AQASAAYJKQweGQA/AQAOAAYJGRZ6SAA0AQAAAA==.Droid:BAAALgAECgEJAQAAAA==.Drunkgerardo:BAAALgAECgIJAQAAAA==.Drunkzen:BAAALgADCgUJBQAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn8mAAIPAAgJgRT7MgDVAQAPAAgJgRT7MgDVAQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJBQAAAA==.',
Ei='Eirote:BAABLgAECn8pAAIZAAgJABaYAQDuAQAZAAgJABaYAQDuAQAAAA==.',
El='Eldari:BAABLgAECn8YAAIIAAgJ2RusCgAgAgAIAAgJ2RusCgAgAgAAAA==.Elem:BAACLgAFFH8NAAIaAAUJsAhzEQA3AQAaAAUJsAhzEQA3AQAuAAQKfyMAAhoACAmcIFQYAFMCABoACAmcIFQYAFMCAAAA.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgQJBAAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAABLgAECn8rAAIbAAkJoiM/AQAaAwAbAAkJoiM/AQAaAwAAAA==.',
Ep='Ephixa:BAAALgAECgYJDwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAAALgAECggJCAABLgAFFAcJEAAIAMcjAA==.',
Ev='Evoke:BAABLgAECn8fAAMGAAgJgyF0CgDOAgAGAAgJdB90CgDOAgAcAAYJZyBWDQADAgAAAA==.',
Ey='Eye:BAACLgAFFH8FAAIdAAMJdxdPBAASAQAdAAMJdxdPBAASAQAuAAQKfx4AAx0ACAk0IuYCAGsCAB0ACAk0IuYCAGsCABcAAQmZDNePACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgADCggJEAAAAA==.Faranth:BAABLgAECn8oAAIGAAgJvhl6CwAUAgAGAAgJvhl6CwAUAgAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felorc:BAAALgADCggJGQAAAA==.Felynne:BAAALgAECgQJCQAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8VAAIKAAcJ+BSDNQBgAQAKAAcJ+BSDNQBgAQAAAA==.Ferum:BAABLgAECn8uAAIFAAkJTiDlBwDNAgAFAAkJTiDlBwDNAgAAAA==.',
Fi='Fionnan:BAABLgAECn8cAAIeAAcJWQZ8GQCSAAAeAAcJWQZ8GQCSAAABLgAECggJKQAaANgJAA==.',
Fo='Forest:BAACLgAFFH8FAAQFAAMJ3BCHOABsAAAFAAIJZwaHOABsAAAeAAIJtgj5CgBhAAAIAAEJ6wonKABHAAAuAAQKfygAAwgACAktHiUNAMYCAAgACAktHiUNAMYCAAUAAwn3G9JHAPMAAAAA.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECgYJCAAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECggJDgAAAA==.',
Ga='Gallium:BAAALgAECgYJDgAAAA==.Gazerbeam:BAAALgAECgYJDQAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAQJIgAOAP0kAA==.Gesht:BAAALgAECgcJEQAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgYJBgAAAA==.',
Go='Goldenbell:BAAALgADCggJCAAAAA==.Goof:BAABLgAECn8tAAIfAAkJSQyEIACDAQAfAAkJSQyEIACDAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAAALgAECgYJEAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECggJDQAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8UAAIgAAYJ5BeUEQCuAQAgAAYJ5BeUEQCuAQAAAA==.Haelexi:BAAALgADCgcJDQAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECgcJIAAEAAAAAA==.Hamonkulous:BAAALgADCgIJAgAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8aAAMNAAYJ4iEUQAB9AQANAAUJpiIUQAB9AQADAAIJ0h4nMABYAAAAAA==.Hayleigh:BAACLgAFFH8UAAIFAAUJiSBBBgDXAQAFAAUJiSBBBgDXAQAuAAQKfykAAgUACAmgJHUGACQDAAUACAmgJHUGACQDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8aAAIJAAYJhxFZYAAuAQAJAAYJhxFZYAAuAQAAAA==.Hellenfeller:BAAALgAECgYJEQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMhAAgJ0Rl8CABWAgAhAAgJQBl8CABWAgAWAAIJ1BZnaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn8pAAIJAAgJlROXNQCnAQAJAAgJlROXNQCnAQAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.',
Hv='Hvac:BAABLgAECn8nAAIPAAgJKQxOTgB/AQAPAAgJKQxOTgB/AQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAAALgAECgYJEQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Im='Imjustadruid:BAAALgADCgUJBAAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJCQAAAA==.Incarnated:BAACLgAFFH8HAAINAAIJ7xTPcAChAAANAAIJ7xTPcAChAAAuAAQKfyEAAg0ACAk/IUsRAHMCAA0ACAk/IUsRAHMCAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgEJAQAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQABLgAFFAUJDwAPACkdAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgUJBQAAAA==.Jadecross:BAABLgAECn8VAAIVAAcJyhX5FQCoAQAVAAcJyhX5FQCoAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgEJAQAAAA==.Jerambae:BAAALgAECgYJEgAAAA==.Jerryatric:BAAALgAECgcJDAAAAA==.',
Jo='Joelah:BAAALgAECgYJDgAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgcJCwAAAA==.',
Ka='Kalfeen:BAAALgAECgUJDgAAAA==.Kallikan:BAABLgAECn8XAAIeAAYJABfgDgCQAQAeAAYJABfgDgCQAQAAAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAAALgAECgcJEAAAAA==.Kasteen:BAAALgAECgIJAwAAAA==.Kazon:BAAALgADCgcJCgABLgAECgkJIAADANojAA==.Kaøs:BAAALgADCgcJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgEJAQAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAACLgAFFH8JAAIJAAMJ8QvvMQDvAAAJAAMJ8QvvMQDvAAAuAAQKfywAAgkACAmGGBQqANYBAAkACAmGGBQqANYBAAAA.',
Kh='Khaosreborn:BAAALgAECgUJDQAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgUJDgAEAAAAAA==.Kilaaz:BAAALgAECgUJDwAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAAALgAFFAIJAgABLgAFFAQJCgAYAGEaAA==.',
Ko='Korius:BAAALgAECgUJBQAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kullman:BAAALgADCgYJCgAAAA==.Kungfurry:BAAALgAECgIJAwAAAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8ZAAIiAAcJjRWQBQBzAQAiAAcJjRWQBQBzAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAAALgAECgYJEgAAAA==.Law:BAAALgAECgEJAQABLgAFFAUJFAAFAIkgAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Lealoo:BAABLgAECn8VAAIJAAYJkRPmWwA4AQAJAAYJkRPmWwA4AQABLgAECgcJGwALAK8QAA==.Leghorn:BAAALgADCgIJAgABLgAECgUJDgAEAAAAAA==.Legolard:BAABLgAECn8WAAIYAAcJ/yB2BgArAgAYAAcJ/yB2BgArAgAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgEJAQAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8dAAIPAAcJqAwxYABSAQAPAAcJqAwxYABSAQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8ZAAIJAAcJpBsmNACtAQAJAAcJpBsmNACtAQAAAA==.Liori:BAAALgAECgEJAgAAAA==.Lirillïa:BAAALgADCggJDQABLgAECgcJGQAJAKQbAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8bAAIJAAkJWSH1LgDBAQAJAAkJWSH1LgDBAQAAAA==.Lokk:BAAALgAECgQJBAABLgAECgYJDgAEAAAAAA==.',
Lu='Lunabug:BAABLgAECn8kAAIUAAgJ/RodDQDnAQAUAAgJ/RodDQDnAQAAAA==.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAABLgAECn8WAAIWAAcJmRotIwDMAQAWAAcJmRotIwDMAQAAAA==.Lyandre:BAABLgAECn8dAAIWAAgJRhOBFgAoAgAWAAgJRhOBFgAoAgAAAA==.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgcJGQAKAMMiAA==.',
Ma='Madan:BAAALgAECgYJDQAAAA==.Malehorelock:BAAALgAECgEJAQABLgAECgYJGwAOAB0iAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn8aAAMPAAYJRx/0MwDRAQAPAAYJRx/0MwDRAQAjAAEJ5AjfHAA5AAAAAA==.Mammadruid:BAABLgAECn8aAAMFAAcJYBIeVQDDAAAFAAUJcQweVQDDAAAeAAcJewbdGACYAAAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Matadør:BAAALgAECgcJCgAAAA==.Mathwhiz:BAAALgAECgYJDQABLgAECgcJEwAEAAAAAA==.Mauldis:BAABLgAECn8aAAIXAAYJ1QvxLQD+AAAXAAYJ1QvxLQD+AAAAAA==.Mavgard:BAAALgADCgcJCgAAAA==.Mavgards:BAAALgADCgMJAwABLgADCgcJCgAEAAAAAA==.Maxrebo:BAABLgAECn8bAAITAAgJoBt7CABDAgATAAgJoBt7CABDAgAAAA==.',
Me='Meatwàd:BAAALgAECgIJAgAAAA==.Mekanzi:BAAALgAECgQJBAAAAA==.Meliõdas:BAAALgAECgUJEAAAAA==.Merebels:BAAALgAECgQJBgAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8pAAICAAgJtxamAgD3AQACAAgJtxamAgD3AQAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAQJDwANAKwcAA==.Misfire:BAABLgAECn8UAAIOAAcJLw6YQwBCAQAOAAcJLw6YQwBCAQAAAA==.Mithygos:BAAALgAECgYJDwAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn8gAAMIAAcJaghyLQDgAAAIAAYJ2AdyLQDgAAAeAAEJQwvZLAAkAAAAAA==.Molykote:BAAALgADCgYJDgAAAA==.Monks:BAAALgAFFAIJAgAAAA==.',
My='Myhiknee:BAAALgADCgMJAwAAAA==.Myriana:BAAALgAECgQJBAAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgUJCgAAAA==.',
Na='Nahryn:BAABLgAECn8aAAIFAAYJwSEYEgA9AgAFAAYJwSEYEgA9AgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgQJBAABLgAECgcJIAAVAM4iAA==.Nerbert:BAAALgADCgYJBgABLgAECggJHwAGAFcVAA==.Neretsym:BAABLgAECn8cAAIOAAcJEhvYJQC9AQAOAAcJEhvYJQC9AQAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAAALgAECgcJEgAAAA==.Nineva:BAABLgAECn8bAAIFAAcJgwOAVADFAAAFAAcJgwOAVADFAAAAAA==.',
No='Nobas:BAABLgAECn8pAAMIAAgJsgiLHwA6AQAIAAgJsgiLHwA6AQAFAAEJ6wJz5AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAAALgAECgcJDAAAAA==.',
Or='Oreeree:BAAALgAECgYJBgAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8fAAIGAAgJVxWMEgC3AQAGAAgJVxWMEgC3AQAAAA==.',
Os='Osteo:BAABLgAECn8hAAMMAAcJ+QPMcADpAAAMAAcJ+QPMcADpAAABAAcJCAK9PwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8aAAMaAAcJkBTeKAB6AQAaAAYJCRXeKAB6AQAXAAQJrQw9ZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8MAAIPAAQJrBiCJABfAQAPAAQJrBiCJABfAQAuAAQKfzEAAg8ACQkzIX0JAN0CAA8ACQkzIX0JAN0CAAAA.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8gAAIgAAcJuhueBwDbAQAgAAcJuhueBwDbAQAAAA==.Plaguestingr:BAABLgAECn8pAAIOAAgJciQkBQDgAgAOAAgJciQkBQDgAgAAAA==.',
Po='Pontifex:BAABLgAECn8aAAIWAAYJ+hqXFACzAQAWAAYJ+hqXFACzAQAAAA==.Portandmorph:BAABLgAECn8WAAIPAAcJbBJxTACDAQAPAAcJbBJxTACDAQAAAA==.Potlock:BAAALgAECgMJBwAAAA==.',
Pr='Proey:BAABLgAECn8oAAMHAAgJ/hQ7DgDnAQAHAAgJ/hQ7DgDnAQAhAAUJJhOOIAAnAQAAAA==.Prone:BAABLgAECn8pAAIaAAgJ2AlvMwA/AQAaAAgJ2AlvMwA/AQAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Ra='Raakotah:BAABLgAECn8zAAIIAAkJ/CKgAQAjAwAIAAkJ/CKgAQAjAwAAAA==.Raelo:BAABLgAECn8UAAIdAAcJLQj/DQAmAQAdAAcJLQj/DQAmAQAAAA==.Raiseurmug:BAABLgAECn8XAAITAAgJdBDDFQCMAQATAAgJdBDDFQCMAQAAAA==.Rakash:BAACLgAFFH8FAAINAAMJvBnxRAAEAQANAAMJvBnxRAAEAQAuAAQKfyQAAg0ACAknIaYgAL8CAA0ACAknIaYgAL8CAAAA.Rascaldragon:BAAALgAECgQJBAAAAA==.Ravenlark:BAABLgAECn8UAAIMAAcJQgUOZgACAQAMAAcJQgUOZgACAQAAAA==.Ravia:BAABLgAECn8ZAAMKAAcJwyLjDgBQAgAKAAcJ/CHjDgBQAgAQAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJCQABLgAECgkJKwAfAJcgAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAQAAAA==.Resco:BAACLgAFFH8eAAIRAAYJIRzQAQC4AQARAAYJIRzQAQC4AQAuAAQKfzAAAhEACQnHJHMGAD8DABEACQnHJHMGAD8DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8WAAIaAAkJ2Ab4QwDyAAAaAAkJ2Ab4QwDyAAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Rook:BAACLgAFFH8PAAINAAQJrByMIQBdAQANAAQJrByMIQBdAQAuAAQKfyUAAg0ACAmFIiIXAPECAA0ACAmFIiIXAPECAAAA.Rosenrott:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.Rosepiercer:BAABLgAECn8dAAIOAAcJBiMiFgAeAgAOAAcJBiMiFgAeAgAAAA==.Rouz:BAABLgAECn8WAAIcAAYJMw/OCAAeAQAcAAYJMw/OCAAeAQAAAA==.',
Ru='Rubert:BAAALgAECgcJBwAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8JAAMGAAMJlCTqEQBGAQAGAAMJlCTqEQBGAQAcAAEJZiLhBwBmAAAuAAQKfxsAAwYACQmEJY8KACICAAYACQmEJY8KACICABwAAwkXJBsmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saetha:BAAALgAECgYJCwAAAA==.Samandean:BAABLgAECn8bAAILAAcJrxALFABNAQALAAcJrxALFABNAQAAAA==.Santhallibar:BAABLgAECn8bAAIkAAcJDgJuDwC7AAAkAAcJDgJuDwC7AAAAAA==.Sarasvati:BAABLgAECn8VAAIFAAYJ2B/zFAAgAgAFAAYJ2B/zFAAgAgAAAA==.Saster:BAABLgAECn8VAAINAAgJaR5zEAB7AgANAAgJaR5zEAB7AgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scrabs:BAAALgAECggJDQAAAA==.',
Se='Sellena:BAABLgAECn8WAAIdAAYJTxLDDAA8AQAdAAYJTxLDDAA8AQABLgAECgcJGwALAK8QAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIVAAYJyRxKIQCpAQAVAAYJyRxKIQCpAQABLgAFFAUJFAAFAIkgAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8LAAIPAAMJHBUIQwAEAQAPAAMJHBUIQwAEAQAuAAQKfysAAg8ACQkgH+IKAMwCAA8ACQkgH+IKAMwCAAAA.Shango:BAAALgADCgcJCQAAAA==.Shansoracle:BAAALgAFFAMJAwABLgAFFAMJCwAPABwVAA==.Shed:BAABLgAECn8jAAIXAAgJEiGoCQA+AgAXAAgJEiGoCQA+AgAAAA==.Sheislegend:BAAALgAECgEJAQAAAA==.Shelby:BAABLgAECn8fAAIWAAcJdBrFDAAaAgAWAAcJdBrFDAAaAgAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shoty:BAAALgAECgIJAgABLgAFFAQJDwANAKwcAA==.',
Si='Siccinok:BAABLgAECn8UAAIPAAYJfxStbwAyAQAPAAYJfxStbwAyAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Sindorian:BAABLgAECn8bAAMOAAYJHSIRJwAdAgAOAAYJHSIRJwAdAgASAAUJxBnHHwDiAAAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgEJAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJBAAAAA==.',
So='Solandor:BAABLgAECn8fAAMRAAgJ6B00DAAoAgARAAgJ6B00DAAoAgAlAAIJBRe0NgBGAAAAAA==.Solar:BAAALgAECgQJBAAAAA==.Solarial:BAAALgAECgUJDAAAAA==.Solastra:BAABLgAECn8WAAIfAAYJwhsfFgDeAQAfAAYJwhsfFgDeAQAAAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn8pAAINAAgJ/hZ1KADbAQANAAgJ/hZ1KADbAQAAAA==.',
Sp='Sparticusdru:BAAALgAECgcJEQAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
St='Starkadia:BAAALgADCgcJBwAAAA==.Staryxia:BAACLgAFFH8MAAIiAAQJrBUWAgBGAQAiAAQJrBUWAgBGAQAuAAQKfy0AAiIACQmhIUsBAPYCACIACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJDQAAAA==.Stonecookies:BAABLgAECn8WAAMMAAcJhwj/XQAWAQAMAAcJWwb/XQAWAQABAAUJ7AYuSQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stormbolt:BAABLgAECn8pAAIIAAgJeRKxEgCwAQAIAAgJeRKxEgCwAQAAAA==.Striggen:BAAALgAECgQJDAAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgQJBAAAAA==.Sulwen:BAACLgAFFH8QAAIIAAcJxyPuAAA9AgAIAAcJxyPuAAA9AgAuAAQKfxkAAggACQkyJvoEAFEDAAgACQkyJvoEAFEDAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAAALgAECgYJDQAAAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAABLgAECn8gAAIVAAcJziJvBQC4AgAVAAcJziJvBQC4AgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8nAAQGAAgJ8h5OBgB6AgAGAAgJ8h5OBgB6AgAcAAYJgR15FAChAQAmAAEJqRLqJwA3AAAAAA==.Talavenn:BAAALgAECgQJBQAAAA==.Tallish:BAABLgAECn8ZAAIKAAgJlgvzegA3AQAKAAgJlgvzegA3AQAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8WAAIRAAYJ7hMYJABQAQARAAYJ7hMYJABQAQAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgYJCwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8qAAINAAgJQR8TDwCIAgANAAgJQR8TDwCIAgAAAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgADCggJFgAAAA==.',
Tr='Triand:BAAALgAECgcJBgAAAA==.',
Tw='Twiddleado:BAABLgAECn8dAAIPAAgJfRFmOwC2AQAPAAgJfRFmOwC2AQAAAA==.Twinkie:BAAALgADCgcJBwABLgAECgcJGQAKAMMiAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgQJBwAAAA==.Valenora:BAABLgAECn8UAAIBAAYJwBunBwBoAQABAAYJwBunBwBoAQAAAA==.Valise:BAAALgAECgYJDQAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgMJBQABLgAECgYJDgAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECgcJCwAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8XAAIaAAcJsRh1FgD/AQAaAAcJsRh1FgD/AQAAAA==.',
Vi='Viperc:BAAALgADCgMJAwABLgAECgQJCQAEAAAAAA==.Viridria:BAAALgAECgEJAQAAAA==.Virridian:BAABLgAECn8bAAIOAAcJSyD1FwAQAgAOAAcJSyD1FwAQAgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgADCgMJAwAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCggJCAAAAA==.',
Wa='Wallofshame:BAABLgAECn8XAAIfAAcJfBxSFQDmAQAfAAcJfBxSFQDmAQAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgYJGgAPAEcfAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn8aAAMMAAYJWhRKUwAxAQAMAAUJoBJKUwAxAQABAAMJnxNvSwCLAAAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8bAAIYAAcJSBYWDgCBAQAYAAcJSBYWDgCBAQAAAA==.Wendee:BAABLgAECn8UAAMWAAcJXgFsNACvAAAWAAcJXgFsNACvAAAHAAUJdQTgSwCoAAAAAA==.',
Wh='Whitefóx:BAABLgAFFH8FAAIgAAQJ8wW/BQC4AAAgAAQJ8wW/BQC4AAABLgAFFAMJCwAPABwVAA==.Whitley:BAAALgAECggJEgAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Xa='Xanthium:BAAALgAECgYJDQAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgQJBgAAAA==.Xardots:BAABLgAECn8jAAIBAAgJDRU/BQCrAQABAAgJDRU/BQCrAQABLgAECgcJIAAEAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn8aAAImAAYJKg54EQAlAQAmAAYJKg54EQAlAQAAAA==.',
Xt='Xtronger:BAABLgAECn8XAAIFAAgJjhQmIADEAQAFAAgJjhQmIADEAQAAAA==.',
['Xá']='Xároth:BAAALgAECgcJIAAAAQ==.',
Ya='Yaddi:BAAALgAECgMJAwAAAA==.Yarrow:BAAALgADCgkJCQAAAA==.',
Ye='Yeeyee:BAAALgAECgkJAgAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgIJAgAAAA==.Zest:BAABLgAECn8XAAImAAkJ9A+hBwD2AQAmAAkJ9A+hBwD2AQAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAAALgAECgYJDgAAAA==.',
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

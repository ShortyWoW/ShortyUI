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

local lookup = {'Paladin-Retribution','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Mage-Frost','Unknown-Unknown','Hunter-BeastMastery','Druid-Restoration','Priest-Discipline','Rogue-Outlaw','Shaman-Elemental','DemonHunter-Devourer','Druid-Feral','Mage-Arcane','DeathKnight-Unholy','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Monk-Brewmaster','Hunter-Marksmanship','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Warrior-Protection','Paladin-Holy','Evoker-Preservation','Druid-Balance','DeathKnight-Frost',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aahhotep:BAAALgADCgMJAwAAAA==.',
Ab='Abelresurekt:BAAALgAECgYJCwAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgEJAQAAAA==.',
Ad='Aderanoe:BAAALgAECgYJBgAAAA==.',
Ag='Agawaateyaa:BAAALgAECgYJDQAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgADCgQJBAAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn8UAAIBAAYJaQ06UgAXAQABAAYJaQ06UgAXAQAAAA==.',
Am='Amadezon:BAAALgAECgcJDwAAAA==.Ambitions:BAAALgAECgQJBwAAAA==.Ament:BAAALgAECgQJBwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn8rAAICAAkJ6COeAAA1AwACAAkJ6COeAAA1AwAAAA==.Aranrùth:BAAALgADCgEJAQAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAAALgAECgYJBwAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arteria:BAAALgAECgQJBgAAAA==.Arthurdagon:BAAALgADCgYJCgAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashnotky:BAABLgAECn8gAAQDAAgJshFvHABqAQADAAYJXxNvHABqAQAEAAgJpQtJTAALAQAFAAMJ7wwACwB7AAAAAA==.',
Au='Auraborealis:BAAALgAECgYJEQAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balzamon:BAABLgAECn8fAAIGAAcJXgegIgAjAQAGAAcJXgegIgAjAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAABLgAECn8qAAIHAAkJhh+ABQDjAgAHAAkJhh+ABQDjAgAAAA==.Banjankri:BAAALgAECgQJCwAAAA==.Bartreant:BAAALgAECgcJDQAAAA==.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgIJAgABLgAECgUJEAAIAAAAAA==.',
Bk='Bkmh:BAAALgADCggJCAAAAA==.',
Bl='Blacksmoke:BAAALgAECgUJDgAAAA==.Blindaf:BAAALgAECgIJAgAAAA==.Blooddemon:BAAALgAECgUJDQABLgAECgkJIgABAKwUAA==.Bloodegg:BAABLgAECn8kAAIJAAgJvBEaJQCGAQAJAAgJvBEaJQCGAQAAAA==.',
Bo='Boinky:BAABLgAECn8WAAIKAAYJtCWhCgBeAgAKAAYJtCWhCgBeAgAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgYJCAAAAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAAALgAECgQJDgAAAA==.',
Bs='Bshoottu:BAAALgAECgUJCgAAAA==.',
Bu='Bubzee:BAAALgADCgQJBAAAAA==.Butters:BAAALgAECgIJAgAAAA==.',
Ca='Calculus:BAABLgAECn8ZAAIHAAcJCiP2WwAmAgAHAAcJCiP2WwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.',
Ch='Chawn:BAAALgAECgYJEQAAAA==.Chiari:BAAALgAECgUJCwAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAAALgAECgYJDwAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAQJBwALAMYNAA==.Daeheals:BAABLgAFFH8HAAILAAQJxg1UDQA4AQALAAQJxg1UDQA4AQAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAQJBwALAMYNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAQJBwALAMYNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgADCgcJCQAAAA==.Dauman:BAAALgADCgEJAwABLgADCgQJBQAIAAAAAA==.Dawnholck:BAAALgAECgYJEQAAAA==.',
De='Deadash:BAAALgAECgEJAQAAAA==.Deathbynade:BAABLgAECn8iAAIBAAgJrhCxKQCbAQABAAgJrhCxKQCbAQAAAA==.Deathclaw:BAABLgAECn8gAAIEAAcJvBhHZACeAQAEAAcJvBhHZACeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deldúwath:BAABLgAECn8aAAIMAAYJQRPZBAA0AQAMAAYJQRPZBAA0AQAAAA==.',
Di='Dionus:BAABLgAECn8XAAIBAAYJOAsPWQAFAQABAAYJOAsPWQAFAQAAAA==.',
Dk='Dkragg:BAAALgAECgIJBgABLgAFFAMJBQANAAYNAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8iAAIGAAgJHgJCMQDLAAAGAAgJHgJCMQDLAAAAAA==.',
Dr='Draucan:BAABLgAECn8eAAILAAYJkhuLDwCUAQALAAYJkhuLDwCUAQAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAIAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8eAAIEAAYJ/g9fRgAdAQAEAAYJ/g9fRgAdAQAAAA==.',
El='Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgADCgMJAwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Falafel:BAABLgAECn8iAAIBAAcJ5xi6JACxAQABAAcJ5xi6JACxAQAAAA==.Fattaco:BAAALgAECgMJBgABLgAECgkJIgABAKwUAA==.',
Fe='Feederr:BAABLgAECn8cAAIOAAcJ8xOJOAABAQAOAAcJ8xOJOAABAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgQJBAAIAAAAAA==.Fenrys:BAAALgAECgUJCgAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAABLgAECn8UAAIPAAgJTR2nAQB+AgAPAAgJTR2nAQB+AgAAAA==.Flubber:BAAALgADCgUJBQAAAA==.',
Fo='Foresttnymph:BAAALgADCgEJAQAAAA==.',
Fr='Frostykush:BAAALgADCgEJAQAAAA==.Frozenmeat:BAABLgAECn8XAAMHAAcJdRA8qACJAQAHAAcJdRA8qACJAQAQAAEJ8AGjIQAmAAAAAA==.Frèydís:BAAALgAECgYJCwABLgAFFAMJBQANAAYNAA==.',
Fu='Furgus:BAAALgAECgIJAgABLgAECgQJBAAIAAAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwAAAA==.',
Go='Gosudizzle:BAAALgAECgYJBwAAAA==.',
Gr='Graebeard:BAABLgAECn8WAAIRAAcJtgrUVQABAQARAAcJtgrUVQABAQAAAA==.',
Gw='Gwendolyn:BAABLgAECn8lAAIPAAkJTCNUAAAyAwAPAAkJTCNUAAAyAwABLgAECgkJKwACAOgjAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hammershock:BAABLgAECn8ZAAISAAYJOCGCDAAiAgASAAYJOCGCDAAiAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAAALgAECgYJDgAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECgYJCgAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyreaper:BAAALgAECgcJEQAAAA==.Hontar:BAAALgADCgYJBgAAAA==.Howdydrüüidy:BAABLgAECn8UAAMPAAYJgBQ7CgBBAQAPAAYJgBQ7CgBBAQAKAAEJhAPvhgAkAAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIHAAYJLwlwfADcAAAHAAYJLwlwfADcAAAAAA==.',
Il='Illimommy:BAACLgAFFH8SAAIOAAYJiByQAgDVAQAOAAYJiByQAgDVAQAuAAQKfxcAAg4ACQnAIpoKAC8DAA4ACQnAIpoKAC8DAAAA.',
In='Inkarok:BAABLgAECn8aAAITAAYJ3RFJEgAfAQATAAYJ3RFJEgAfAQAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgcJEgAIAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8OAAINAAUJxhtoBwBkAQANAAUJxhtoBwBkAQAuAAQKfyEAAw0ACAlHHwkNAM4CAA0ACAlHHwkNAM4CABIABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAAALgAECgcJEwAAAA==.',
Ka='Kadriel:BAAALgAECgQJBwAAAA==.Kalanrahl:BAABLgAECn8iAAIHAAgJ6RLWOACEAQAHAAgJ6RLWOACEAQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgQJBAAAAA==.Kapootz:BAAALgADCgQJBQAAAA==.Kathlick:BAAALgAECgYJDQAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Kh='Khaiduus:BAABLgAECn8XAAINAAYJZBleLQCwAQANAAYJZBleLQCwAQAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kirinkurai:BAABLgAECn8dAAIUAAcJ9BszAwDsAQAUAAcJ9BszAwDsAQAAAA==.Kittsune:BAAALgAECgEJAQAAAA==.',
Km='Kmoniwnaleya:BAAALgADCgcJGAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Kottenmouth:BAACLgAFFH8FAAIVAAIJvh4fBACzAAAVAAIJvh4fBACzAAAuAAQKfzIAAhUACQnDI1YAAD8DABUACQnDI1YAAD8DAAAA.',
Kr='Kraven:BAAALgAECgkJAQAAAA==.Kritea:BAABLgAECn8iAAMWAAkJ7BYHBABXAgAWAAkJ7BYHBABXAgAXAAEJ2BEFHgA9AAAAAA==.',
Ku='Kunimitsu:BAAALgADCgUJBQABLgAECgUJCwAIAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAABLgAECn8UAAIGAAYJhxhbFQCJAQAGAAYJhxhbFQCJAQAAAA==.',
Li='Life:BAAALgAECgEJAQAAAA==.Lizardmann:BAAALgAECgcJCwAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJKwACAOgjAA==.',
Lu='Lumiere:BAAALgAECgYJDgAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAECgMJAwAIAAAAAA==.Marshmallow:BAAALgAECgYJDQAAAA==.Maryla:BAABLgAECn8iAAIBAAkJrBR8GAD4AQABAAkJrBR8GAD4AQAAAA==.Maskara:BAAALgADCgUJBgAAAA==.',
Mc='Mchammer:BAAALgADCgYJBgAAAA==.',
Me='Metarage:BAAALgAECgYJCwAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgEJAQAAAA==.',
Ml='Mlj:BAAALgADCgYJCAAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgEJAQAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgQJBwAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8XAAQYAAYJdBMILgBIAQAYAAYJdBMILgBIAQAZAAQJHghHZwCkAAACAAEJ4wqxRwA1AAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Nativelock:BAABLgAECn8VAAIFAAYJCAabEgADAQAFAAYJCAabEgADAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAAALgAECgYJEAAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
Nu='Nuka:BAAALgAECgUJEAAAAA==.',
Ny='Nynnaeve:BAAALgAECgYJEwAAAA==.',
On='Onions:BAABLgAECn8YAAMSAAkJ7xbWLwDIAQASAAcJdBTWLwDIAQANAAkJlA2qEACfAQAAAA==.Onthecoda:BAAALgAECggJEgAAAA==.',
Op='Opani:BAAALgAECgIJAgAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAAALgAECgYJDwAAAA==.',
Pa='Paigeturner:BAABLgAECn8ZAAMQAAYJQQkzDAAPAQAQAAYJgAczDAAPAQAHAAYJVwglcAD5AAAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgQJBAAIAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAABLgAECn8eAAIEAAYJfhyBMwBdAQAEAAYJfhyBMwBdAQAAAA==.',
Ph='Phabio:BAAALgADCgkJHAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAAALgAECgMJBQAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qr='Qrixe:BAAALgADCgUJCQAAAA==.',
Qu='Quelthemar:BAAALgAECgIJAgAAAA==.Quesy:BAACLgAFFH8FAAIRAAMJqRbYOwClAAARAAMJqRbYOwClAAAuAAQKfyIAAhEACQmCHwMOACsDABEACQmCHwMOACsDAAAA.',
Ra='Ragnabrew:BAAALgAECgUJBgABLgAFFAMJBQANAAYNAA==.Ragnatotemzz:BAABLgAFFH8FAAINAAMJBg22EgDoAAANAAMJBg22EgDoAAAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgMJAwAAAA==.',
Re='Rebelmonk:BAAALgADCgMJBQAAAA==.Redneckgirls:BAAALgADCgMJAgABLgADCgMJBQAIAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rennl:BAAALgAECgUJCgAAAA==.Requiemechoe:BAAALgAECgYJCgAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgADCgYJCQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgADCggJFwABLgAECgQJBAAIAAAAAA==.Ripsets:BAACLgAFFH8GAAMJAAMJgyAxEgAqAQAJAAMJAiAxEgAqAQAaAAEJxyI8IwBjAAAuAAQKfywAAwkACAmTJWcGAJECABoACAlKIFEQALcCAAkABwmEJWcGAJECAAAA.',
Ro='Roflkopterz:BAABLgAECn8VAAIJAAYJ0xc2JwB7AQAJAAYJ0xc2JwB7AQAAAA==.Roflkopterzz:BAAALgAECgYJCwAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAMJBQANAAYNAA==.',
Sa='Saeallina:BAAALgAECgkJDwAAAA==.Sarigos:BAAALgAECgcJDwAAAA==.Saviorselvz:BAAALgAECgQJBAAAAA==.',
Sc='Schieldemon:BAABLgAECn8iAAMOAAgJnBo9EADuAQAOAAgJnBo9EADuAQATAAQJ6gc1UQClAAAAAA==.Science:BAAALgAECgYJBgAAAA==.Scrythe:BAABLgAECn8eAAIbAAYJqhwoDABOAQAbAAYJqhwoDABOAQAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJKwACAOgjAA==.Seseren:BAAALgAECgEJAQAAAA==.',
Sh='Shabooty:BAAALgAECgUJEAAAAA==.Shariandel:BAAALgAECggJEAAAAA==.Sharrin:BAAALgAECgYJBgAAAA==.Shiebert:BAAALgAECgQJBAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAMJBQANAAYNAA==.Shrodwrah:BAABLgAECn8XAAIcAAYJrguTQgAuAQAcAAYJrguTQgAuAQAAAA==.',
Si='Sippycup:BAAALgAECgYJBgAAAA==.',
Sk='Skkarrgh:BAAALgADCgQJBQAAAA==.',
So='Solomoon:BAACLgAFFH8MAAILAAQJ4BWqCQBEAQALAAQJ4BWqCQBEAQAuAAQKfyMABAsACQkgH5cFAPUCAAsACQkNH5cFAPUCAB0AAwmiHvM+AP4AABwAAQnhITByAF4AAAAA.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.',
St='Stabsrael:BAABLgAFFH8JAAIWAAMJtCJ4CgA4AQAWAAMJtCJ4CgA4AQAAAA==.Stalkurnjr:BAAALgADCgYJBgABLgAECgcJDwAIAAAAAA==.Steamlene:BAAALgAECgMJAwAAAA==.Steelehorn:BAABLgAECn8iAAIeAAgJSR8/AwBcAgAeAAgJSR8/AwBcAgAAAA==.Stigmã:BAAALgADCgcJDgAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgUJBQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syryn:BAAALgAECgUJDQAAAA==.',
Ta='Talasacerdos:BAABLgAECn8ZAAIdAAcJug96EwBoAQAdAAcJug96EwBoAQAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAAALgAECgcJEgAAAA==.',
Th='Theirz:BAAALgAECgQJBQAAAA==.Thorgrum:BAACLgAFFH8FAAIRAAMJIiS0IQA1AQARAAMJIiS0IQA1AQAuAAQKfyAAAhEABgnSJbUZAO4BABEABgnSJbUZAO4BAAAA.',
Ti='Tillandra:BAAALgAECgYJCwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJBwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgAIAAAAAA==.',
Tw='Twistedteas:BAAALgAECgQJBgAAAA==.',
Tz='Tzzird:BAABLgAECn8kAAMBAAgJlCB3LQBtAgABAAgJlCB3LQBtAgAfAAEJegEtWgAhAAAAAA==.',
Um='Umbralstar:BAAALgAECgcJDAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAAALgAECgcJDgAAAA==.',
Ve='Velddor:BAABLgAECn8lAAIVAAcJySOQBAA7AgAVAAcJySOQBAA7AgAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAAALgAECgYJDQAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAAALgAECgUJEAAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8cAAMJAAcJbg96KAB1AQAJAAcJbg96KAB1AQAaAAIJYwBahwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8YAAIDAAcJHg6BBwA7AQADAAcJHg6BBwA7AQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAAALgAECgQJBAABLgAECggJJgAgAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn8dAAIQAAYJdBCsAwBGAQAQAAYJdBCsAwBGAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgAIAAAAAA==.',
Ya='Yarndog:BAAALgADCgcJBwAAAA==.Yaviel:BAABLgAECn8cAAIJAAcJ8BsbFADxAQAJAAcJ8BsbFADxAQAAAA==.',
Yu='Yushis:BAAALgAECgYJEQAAAA==.',
Za='Zackaran:BAABLgAECn8UAAMhAAcJAQqKIgDrAAAhAAcJAQqKIgDrAAAKAAEJzwre3gAlAAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEALgAECgcJEgAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAFFAMJBQARAKkWAA==.Zeromus:BAABLgAECn8UAAIiAAYJqQcxCADjAAAiAAYJqQcxCADjAAAAAA==.',
Zo='Zoidbergg:BAAALgAECgUJBgABLgAECggJJAABAJQgAA==.',
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

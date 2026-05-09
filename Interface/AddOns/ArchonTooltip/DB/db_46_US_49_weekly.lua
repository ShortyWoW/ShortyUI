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

local lookup = {'Priest-Shadow','Paladin-Retribution','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Warrior-Fury','Mage-Frost','Unknown-Unknown','Hunter-BeastMastery','Druid-Restoration','Hunter-Survival','Priest-Holy','Rogue-Outlaw','Shaman-Elemental','DemonHunter-Devourer','Druid-Feral','Mage-Arcane','DeathKnight-Unholy','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Blood','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Druid-Balance','Evoker-Preservation','Warrior-Protection','Paladin-Holy','DeathKnight-Frost',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aahhotep:BAAALgADCgMJAwAAAA==.',
Ab='Abelresurekt:BAAALgAECgcJEQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgEJAQAAAA==.',
Ad='Aderanoe:BAAALgAECgcJDQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8UAAIBAAYJygI7OAClAAABAAYJygI7OAClAAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgADCgQJBAAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn8bAAICAAcJPw9+TABgAQACAAcJPw9+TABgAQAAAA==.',
Am='Amadezon:BAAALgAECgcJDwAAAA==.Ambitions:BAAALgAECgcJDwAAAA==.Ament:BAAALgAECgQJBwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn81AAIDAAkJOyV2AABsAwADAAkJOyV2AABsAwAAAA==.Aranrùth:BAAALgAECgQJBQAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAAALgAECgYJCAAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arteria:BAAALgAECggJDgAAAA==.Arthurdagon:BAAALgAECgYJBgAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashnotky:BAABLgAECn8gAAQEAAgJshFrHABqAQAEAAYJXxNrHABqAQAFAAgJpQuzZAAFAQAGAAMJ7wzpEABsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8YAAIHAAcJHRJdFACeAQAHAAcJHRJdFACeAQAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balzamon:BAABLgAECn8gAAIIAAgJggZRKgArAQAIAAgJggZRKgArAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAABLgAECn8qAAIJAAkJhh8lCgDVAgAJAAkJhh8lCgDVAgAAAA==.Bartreant:BAAALgAECgcJEgAAAA==.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJAwABLgAECgYJEQAKAAAAAA==.',
Bk='Bkmh:BAAALgADCggJCAAAAA==.',
Bl='Blacksmoke:BAAALgAECgYJEwAAAA==.Blindaf:BAAALgAECgUJBwAAAA==.Blooddemon:BAAALgAECgUJDQABLgAECgkJKwACANYZAA==.Bloodegg:BAABLgAECn8kAAILAAgJvBHwOQDHAQALAAgJvBHwOQDHAQAAAA==.',
Bo='Boinky:BAABLgAECn8XAAIMAAYJtCXqDwBXAgAMAAYJtCXqDwBXAgAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgYJDwAAAA==.Brewzlee:BAAALgADCgEJAgABLgAECgYJEQAKAAAAAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAAALgAECgUJEwAAAA==.',
Bs='Bshoottu:BAAALgAECgYJEAAAAA==.',
Bu='Bubzee:BAAALgADCgYJCAAAAA==.Butters:BAAALgAECgIJAwAAAA==.',
Ca='Cadel:BAAALgAECgMJAgAAAA==.Calculus:BAABLgAECn8aAAIJAAgJ3SHtWwAmAgAJAAgJ3SHtWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.',
Ch='Chawn:BAABLgAECn8YAAINAAcJmhZuDgDBAQANAAcJmhZuDgDBAQAAAA==.Chiari:BAAALgAECgUJCwABLgAECgYJBgAKAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAAALgAECgYJEQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAUJDAAHAMIPAA==.Daeheals:BAABLgAFFH8MAAIHAAUJwg88DACGAQAHAAUJwg88DACGAQAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAUJDAAHAMIPAA==.Daethknight:BAAALgADCgIJAgABLgAFFAUJDAAHAMIPAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgADCgcJCQAAAA==.Dauman:BAAALgADCgEJAwABLgADCgQJBQAKAAAAAA==.Dawnholck:BAABLgAECn8UAAQHAAYJQg2SMAAbAQAHAAUJdQ6SMAAbAQAOAAQJcwnKYQCqAAABAAMJtgg3OgCaAAAAAA==.',
De='Deadash:BAAALgAECgEJAgAAAA==.Deathbynade:BAABLgAECn8lAAICAAkJCBLNIgD6AQACAAkJCBLNIgD6AQAAAA==.Deathclaw:BAABLgAECn8gAAIFAAcJvBiMQwBeAQAFAAcJvBiMQwBeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deldúwath:BAABLgAECn8dAAIPAAcJARGcBQBiAQAPAAcJARGcBQBiAQAAAA==.',
Di='Dionus:BAABLgAECn8fAAICAAgJTApsTQBdAQACAAgJTApsTQBdAQAAAA==.',
Dk='Dkragg:BAAALgAECgIJBwABLgAFFAQJCAAQAK8LAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8qAAIIAAgJTgK2PgDGAAAIAAgJTgK2PgDGAAAAAA==.Dorkfish:BAAALgAECgEJAQAAAA==.',
Dr='Drakuluh:BAAALgADCgMJAwAAAA==.Draucan:BAABLgAECn8jAAIHAAYJtRskFQCVAQAHAAYJtRskFQCVAQAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAKAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8jAAIFAAcJPRFCOgB+AQAFAAcJPRFCOgB+AQAAAA==.',
El='Elemetzy:BAAALgAECgEJAQAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgADCgMJAwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJBwAKAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Falafel:BAABLgAECn8jAAICAAcJ5xjZNgCiAQACAAcJ5xjZNgCiAQAAAA==.Fattaco:BAAALgAECgMJBgABLgAECgkJKwACANYZAA==.',
Fe='Feederr:BAABLgAECn8iAAIRAAcJOxQjOwBKAQARAAcJOxQjOwBKAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgUJBgAKAAAAAA==.Fenrys:BAAALgAECgUJCgAAAA==.Feryn:BAAALgAECgQJCwAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAABLgAECn8WAAISAAgJch2iAgB7AgASAAgJch2iAgB7AgAAAA==.Flubber:BAAALgADCgUJBQAAAA==.',
Fo='Followmenot:BAAALgADCgEJAQAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8dAAMJAAcJ5RUeQwCeAQAJAAcJ5RUeQwCeAQATAAEJ8AGkIQAmAAAAAA==.Frèydís:BAAALgAECgYJCwABLgAFFAQJCAAQAK8LAA==.',
Fu='Furgus:BAAALgAECgIJAgABLgAECgUJBgAKAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAUJFAAMAM4gAA==.',
Go='Gosudizzle:BAAALgAECgcJCAABLgAFFAIJAwAKAAAAAA==.',
Gr='Graebeard:BAABLgAECn8WAAIUAAcJtgo2dAD5AAAUAAcJtgo2dAD5AAAAAA==.',
Gw='Gwendolyn:BAABLgAECn8wAAISAAkJRiRVAABcAwASAAkJRiRVAABcAwABLgAECgkJNQADADslAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8fAAIVAAYJ0CFNEgAmAgAVAAYJ0CFNEgAmAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAAALgAECgcJEwAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECgcJDQAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8WAAICAAcJFBhsUgDqAQACAAcJFBhsUgDqAQAAAA==.Hontar:BAAALgADCggJCwAAAA==.Howdydrüüidy:BAABLgAECn8bAAMSAAcJ+hOACQCPAQASAAcJ+hOACQCPAQAMAAEJggOaqgAhAAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIJAAYJLwnCnADZAAAJAAYJLwnCnADZAAAAAA==.',
Il='Illimommy:BAACLgAFFH8YAAIRAAcJQBmNAgAlAgARAAcJQBmNAgAlAgAuAAQKfxcAAhEACQnAIpQKAC8DABEACQnAIpQKAC8DAAAA.',
In='Inkarok:BAABLgAECn8bAAIWAAcJ6hG4EwBRAQAWAAcJ6hG4EwBRAQAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECggJFAAXAJIhAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8RAAIQAAUJxhtqBwBkAQAQAAUJxhtqBwBkAQAuAAQKfyEAAxAACAlHHwsNAM4CABAACAlHHwsNAM4CABUABQkHCbxqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8ZAAICAAcJTg/TTQBcAQACAAcJTg/TTQBcAQAAAA==.',
Ka='Kadriel:BAAALgAECgQJBwAAAA==.Kalanrahl:BAABLgAECn8lAAIJAAgJMROjOwC1AQAJAAgJMROjOwC1AQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgUJBQAAAA==.Kapootz:BAAALgADCgQJBQAAAA==.Kathlick:BAAALgAECgcJEgAAAA==.',
Kh='Khaiduus:BAABLgAECn8fAAIQAAgJWhhQEADgAQAQAAgJWhhQEADgAQAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kirinkurai:BAABLgAECn8kAAIYAAcJTh00BADxAQAYAAcJTh00BADxAQAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmoniwnaleya:BAAALgADCgcJHgAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Kottenmouth:BAACLgAFFH8KAAINAAQJ0RXYBgBcAQANAAQJ0RXYBgBcAQAuAAQKfzQAAg0ACQkXJZgAAEsDAA0ACQkXJZgAAEsDAAAA.',
Kr='Kraven:BAAALgAECgkJAQAAAA==.Kritea:BAABLgAECn8rAAMZAAkJaRehBQBgAgAZAAkJGxehBQBgAgAaAAMJUg/QEQCLAAAAAA==.',
Ku='Kunimitsu:BAAALgAECgYJBgAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAABLgAECn8bAAIIAAcJmxvGEADtAQAIAAcJmxvGEADtAQAAAA==.',
Li='Life:BAAALgAECgEJAQAAAA==.Lizardmann:BAABLgAECn8YAAIbAAgJMRZcDgDpAQAbAAgJMRZcDgDpAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJNQADADslAA==.',
Lu='Lumiere:BAABLgAECn8UAAIcAAYJxAmAEADmAAAcAAYJxAmAEADmAAAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAUJFAAMAM4gAA==.Marshmallow:BAABLgAECn8UAAIJAAcJfgs6YwBLAQAJAAcJfgs6YwBLAQAAAA==.Maryla:BAABLgAECn8rAAICAAkJ1hn6EgBiAgACAAkJ1hn6EgBiAgAAAA==.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgYJBgAAAA==.',
Me='Metaglaive:BAAALgAECgMJAwAAAA==.Metarage:BAAALgAECgYJDAAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgEJAQAAAA==.',
Ml='Mlj:BAAALgADCgYJCAAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgIJAwAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgQJBwAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8fAAQdAAgJixFgGQCEAQAdAAgJixFgGQCEAQAeAAQJHghKZwCkAAADAAEJ4wo4XgAzAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Nativelock:BAABLgAECn8aAAIGAAYJZgeaEgADAQAGAAYJZgeaEgADAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8UAAIIAAYJ4xJqLwAQAQAIAAYJ4xJqLwAQAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
Nu='Nuka:BAAALgAECgYJEQAAAA==.',
Ny='Nynnaeve:BAABLgAECn8YAAMOAAcJIhOtHABkAQAOAAcJIhOtHABkAQABAAEJtQJxWwAhAAAAAA==.',
On='Onions:BAABLgAECn8hAAMQAAkJwRFADwDuAQAQAAkJwRFADwDuAQAVAAcJdBTWLwDIAQAAAA==.Onthecoda:BAABLgAECn8VAAMfAAkJhAgrFwCCAQAfAAkJhAgrFwCCAQAMAAgJExNZKgCBAQAAAA==.',
Op='Opani:BAAALgAECgQJBgAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8UAAIgAAYJERfvDgBSAQAgAAYJERfvDgBSAQAAAA==.',
Pa='Paigeturner:BAABLgAECn8gAAMJAAcJ1wusWwBdAQAJAAcJ1wusWwBdAQATAAYJeAcyDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgUJBgAKAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAABLgAECn8lAAIFAAYJfRzbOwB4AQAFAAYJfRzbOwB4AQAAAA==.',
Ph='Phabio:BAAALgAECgYJBgAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pinkee:BAAALgAECgEJAQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgUJBgAKAAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAAALgAECgMJBQAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qr='Qrixe:BAAALgAECgYJCwAAAA==.',
Qu='Quelthemar:BAAALgAECgIJAwAAAA==.Quesy:BAACLgAFFH8MAAIUAAQJpRqpHgBkAQAUAAQJpRqpHgBkAQAuAAQKfyIAAhQACQmCH/8NACsDABQACQmCH/8NACsDAAAA.Quickheal:BAAALgAECgMJAwAAAA==.',
Ra='Ragnabrew:BAAALgAECgUJBgABLgAFFAQJCAAQAK8LAA==.Ragnatotemzz:BAABLgAFFH8IAAIQAAQJrwtQEwAZAQAQAAQJrwtQEwAZAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgMJAwAAAA==.',
Re='Rebelmonk:BAAALgADCgMJBQABLgAECgIJAwAKAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgIJAwAKAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rennl:BAAALgAECgUJEAAAAA==.Requiemechoe:BAAALgAFFAEJAQAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgAECgIJAgAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgADCggJFwABLgAECgUJBgAKAAAAAA==.Ripsets:BAACLgAFFH8JAAMLAAMJZSPQGwAtAQALAAMJ5CLQGwAtAQAcAAEJxyJJIwBjAAAuAAQKfzEAAwsACQmvJTQEAPICAAsACAmnJTQEAPICABwACAlJIHQQALgCAAAA.',
Ro='Roflkopterz:BAABLgAECn8YAAILAAcJFxo/IwDKAQALAAcJFxo/IwDKAQAAAA==.Roflkopterzz:BAAALgAECgYJDwAAAA==.Rozalyn:BAAALgAECgEJAQAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAQJCAAQAK8LAA==.',
Sa='Saeallina:BAABLgAECn8YAAIUAAkJtRilEgBnAgAUAAkJtRilEgBnAgAAAA==.Saphíras:BAAALgADCgEJAQAAAA==.Sarezen:BAAALgADCgUJCQAAAA==.Sarigos:BAABLgAECn8VAAIgAAcJnBVPCQDLAQAgAAcJnBVPCQDLAQAAAA==.Saviorselvz:BAAALgAECgUJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8GAAIRAAIJdQ6lSQCPAAARAAIJdQ6lSQCPAAAuAAQKfysAAxEACQneG0AQAEECABEACAlDHUAQAEECABYABQn1CTdRAKUAAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn8lAAIXAAYJ7hzFEABlAQAXAAYJ7hzFEABlAQAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJNQADADslAA==.Seseren:BAAALgAECgEJAgAAAA==.',
Sh='Shabooty:BAABLgAECn8VAAIFAAYJHAQ4fwDIAAAFAAYJHAQ4fwDIAAAAAA==.Shariandel:BAABLgAECn8VAAIVAAgJZRn5EwAVAgAVAAgJZRn5EwAVAgAAAA==.Sharrin:BAAALgAECgcJDQAAAA==.Shiebert:BAAALgAECgYJCwAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAQJCAAQAK8LAA==.Shrodwrah:BAABLgAECn8fAAIOAAgJIwpMIgA3AQAOAAgJIwpMIgA3AQAAAA==.',
Si='Sippycup:BAAALgAECgYJCAAAAA==.',
Sk='Skkarrgh:BAAALgADCgQJBQAAAA==.',
So='Solomoon:BAACLgAFFH8TAAIHAAQJOxitCQBEAQAHAAQJOxitCQBEAQAuAAQKfyUABAcACQkgH5QFAPUCAAcACQkNH5QFAPUCAAEABAmiHvE+AP4AAA4AAQnhITZyAF4AAAAA.Souleatr:BAAALgAECgQJBAAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.',
St='Stabsrael:BAABLgAFFH8NAAIZAAQJDSFBBgB5AQAZAAQJDSFBBgB5AQAAAA==.Stalkurnjr:BAAALgADCgYJBgABLgAECggJFQAgAJwVAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn8vAAIhAAkJKh0+AwCaAgAhAAkJKh0+AwCaAgAAAA==.Stigmã:BAAALgADCgcJFAAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgYJDAAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syryn:BAAALgAECgYJEgAAAA==.',
Ta='Talasacerdos:BAABLgAECn8gAAIBAAcJvhltDwDXAQABAAcJvhltDwDXAQAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8ZAAIcAAcJZBGgCQBfAQAcAAcJZBGgCQBfAQAAAA==.',
Th='Theirz:BAAALgAECgUJBgAAAA==.Thorgrum:BAACLgAFFH8HAAIUAAMJIiRqOgAiAQAUAAMJIiRqOgAiAQAuAAQKfycAAhQABgkBJj4gAAgCABQABgkBJj4gAAgCAAAA.',
Ti='Tillandra:BAAALgAECgYJDwAAAA==.Tinder:BAAALgADCgcJAQAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJDQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJCQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgAKAAAAAA==.',
Tw='Twistedteas:BAAALgAECgYJDQAAAA==.',
Tz='Tzzird:BAABLgAECn8mAAMCAAgJVSFFEwBgAgACAAgJVSFFEwBgAgAiAAEJegEhbwAeAAAAAA==.',
Um='Umbralstar:BAAALgAECggJDQAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAAALgAECgcJDgAAAA==.',
Ve='Velddor:BAABLgAECn8pAAINAAgJ/iNJAwCnAgANAAgJ/iNJAwCnAgAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAAALgAECgYJDQAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8WAAMDAAYJZhx8FQB/AQADAAYJZhx8FQB/AQAeAAMJJRXuYwCyAAAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8gAAMLAAgJjQ6AMACLAQALAAgJjQ6AMACLAQAcAAIJYwCnhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8fAAIEAAgJqw4+BwBzAQAEAAgJqw4+BwBzAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAAALgAECgQJBAABLgAECggJKwAgAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn8kAAITAAYJdRDKBAA5AQATAAYJdRDKBAA5AQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgAKAAAAAA==.',
Ya='Yarndog:BAAALgADCgcJDQAAAA==.Yaviel:BAABLgAECn8kAAILAAgJZB48DgBnAgALAAgJZB48DgBnAgAAAA==.',
Yu='Yushis:BAABLgAECn8SAAIRAAYJjw4dZADWAAARAAYJjw4dZADWAAAAAA==.',
Za='Zach:BAAALgADCgkJCQAAAA==.Zackaran:BAABLgAECn8bAAMfAAcJTgoJJgANAQAfAAcJTgoJJgANAQAMAAQJTQiJbAB3AAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEBLgAECn8UAAMXAAgJkiFICwBgAgAXAAgJkiFICwBgAgAUAAMJUQaKqQCNAAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAFFAQJDAAUAKUaAA==.Zeromus:BAABLgAECn8bAAIjAAcJPAj6CAAPAQAjAAcJPAj6CAAPAQAAAA==.',
Zo='Zoidbergg:BAAALgAECgYJCwABLgAECggJJgACAFUhAA==.',
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

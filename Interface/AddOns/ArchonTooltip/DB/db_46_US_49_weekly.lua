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

local lookup = {'Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Mage-Frost','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration','Rogue-Outlaw','DemonHunter-Devourer','Druid-Feral','Shaman-Restoration','DemonHunter-Havoc','Shaman-Elemental','DemonHunter-Vengeance','Hunter-Survival','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','Warrior-Protection','Evoker-Preservation','Druid-Balance',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelresurekt:BAAALgAECgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgADCgkJHgAAAA==.',
Ag='Agawaateyaa:BAAALgAECgEJAQAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAAALgAECgYJDgAAAA==.',
Am='Amadezon:BAAALgAECgYJDAAAAA==.Ambitions:BAAALgAECgQJBAAAAA==.Ament:BAAALgAECgMJAwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn8gAAIBAAkJKSIwBABJAwABAAkJKSIwBABJAwAAAA==.Aranrùth:BAAALgADCgEJAQAAAA==.Arassa:BAAALgADCgYJCwAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAAALgAECgEJAQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arteria:BAAALgADCgMJAwAAAA==.Arthurdagon:BAAALgADCgYJBwAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashnotky:BAABLgAECn8YAAQCAAYJ1RNwHABqAQACAAYJXxNwHABqAQADAAMJowv95QCPAAAEAAIJaQxiIQBsAAAAAA==.',
Au='Auraborealis:BAAALgAECgQJCwAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.',
Ba='Balzamon:BAABLgAECn8YAAIFAAcJagVGGgC6AAAFAAcJagVGGgC6AAAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAABLgAECn8aAAIGAAgJBBs4SABfAgAGAAgJBBs4SABfAgAAAA==.Banjankri:BAAALgAECgQJCQAAAA==.Bartreant:BAAALgAECgMJAwAAAA==.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgADCgEJAQABLgAECgQJDwAHAAAAAA==.',
Bl='Blacksmoke:BAAALgAECgUJCwAAAA==.Blindaf:BAAALgADCgYJBgABLgADCgkJGQAHAAAAAA==.Blooddemon:BAAALgAECgUJDQABLgAECggJGQAIAFQUAA==.Bloodegg:BAABLgAECn8cAAIJAAcJYRLxOQDHAQAJAAcJYRLxOQDHAQAAAA==.',
Bo='Boinky:BAABLgAECn8WAAIKAAYJtCVkAwBsAgAKAAYJtCVkAwBsAgAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgIJAgAAAA==.Brickèdup:BAAALgADCgcJBgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAAALgAECgQJCgAAAA==.',
Bs='Bshoottu:BAAALgAECgMJBQAAAA==.',
Ca='Calculus:BAABLgAECn8YAAIGAAcJICMAXAAmAgAGAAcJICMAXAAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.',
Ch='Chawn:BAAALgAECgQJCwAAAA==.Chiari:BAAALgAECgUJCwAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAAALgAECgUJCQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJCQAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAMJAwAHAAAAAA==.Daeheals:BAAALgAFFAMJAwAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAMJAwAHAAAAAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgADCgcJCQAAAA==.Dauman:BAAALgADCgEJAQABLgADCgQJBQAHAAAAAA==.Dawnholck:BAAALgAECgYJDwAAAA==.',
De='Deadash:BAAALgADCgEJAQAAAA==.Deathbynade:BAABLgAECn8dAAIIAAgJgQ6SEgCOAQAIAAgJgQ6SEgCOAQAAAA==.Deathclaw:BAABLgAECn8ZAAIDAAYJERx6HQAwAQADAAYJERx6HQAwAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deldúwath:BAABLgAECn8UAAILAAYJ7RHwAQA9AQALAAYJ7RHwAQA9AQAAAA==.',
Di='Dionus:BAAALgAECgYJEQAAAA==.',
Dk='Dkragg:BAAALgAECgIJAwABLgAFFAIJAgAHAAAAAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8aAAIFAAcJugFvHwB8AAAFAAcJugFvHwB8AAAAAA==.',
Dr='Draucan:BAAALgAECgYJEgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAHAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8YAAIDAAYJZQ5kJAAHAQADAAYJZQ5kJAAHAQAAAA==.',
El='Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Fa='Falafel:BAABLgAECn8XAAIIAAcJ+RXzbgCfAQAIAAcJ+RXzbgCfAQAAAA==.Fattaco:BAAALgAECgIJBAAAAA==.',
Fe='Feederr:BAABLgAECn8VAAIMAAcJRw+bVwCbAQAMAAcJRw+bVwCbAQAAAA==.Fenrys:BAAALgAECgQJBAAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAAALgAECggJDgAAAA==.Flubber:BAAALgADCgUJBQAAAA==.',
Fo='Foresttnymph:BAAALgADCgEJAQAAAA==.',
Fr='Frostykush:BAAALgADCgEJAQAAAA==.Frozenmeat:BAAALgAECggJEgAAAA==.Frèydís:BAAALgAECgYJCwABLgAFFAIJAgAHAAAAAA==.',
Fu='Furgus:BAAALgAECgIJAgAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.',
Go='Gosudizzle:BAAALgAECgYJBwABLgAFFAEJAQAHAAAAAA==.',
Gr='Graebeard:BAAALgAECgYJDwAAAA==.',
Gw='Gwendolyn:BAABLgAECn8dAAINAAgJvyMqAgA0AwANAAgJvyMqAgA0AwABLgAECgkJIAABACkiAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hammershock:BAABLgAECn8UAAIOAAYJTyCFBgDvAQAOAAYJTyCFBgDvAQAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAAALgAECgYJCAAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECgQJBAAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyreaper:BAAALgAECgcJEAAAAA==.Howdydrüüidy:BAAALgAECgYJDgAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8XAAIGAAYJygdeOgDZAAAGAAYJygdeOgDZAAAAAA==.',
Il='Illimommy:BAACLgAFFH8PAAIMAAUJ/xz1BgC0AQAMAAUJ/xz1BgC0AQAuAAQKfxcAAgwACQnAIpwKAC8DAAwACQnAIpwKAC8DAAAA.',
In='Inkarok:BAABLgAECn8UAAIPAAYJ1BHhBwAsAQAPAAYJ1BHhBwAsAQAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgYJDwAHAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8JAAIQAAQJxhtgBwBkAQAQAAQJxhtgBwBkAQAuAAQKfx8AAxAACAlHHwUNAM4CABAACAlHHwUNAM4CAA4ABQkHCb9qAOQAAAAA.Jitsham:BAAALgAECgYJBgAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAAALgAECgMJCwAAAA==.',
Ka='Kadriel:BAAALgAECgQJBwAAAA==.Kalanrahl:BAABLgAECn8aAAIGAAcJxxALIgBKAQAGAAcJxxALIgBKAQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgADCgcJCQAAAA==.Kapootz:BAAALgADCgQJBQAAAA==.Kathlick:BAAALgAECgUJBwAAAA==.',
Kh='Khaiduus:BAAALgAECgYJEQAAAA==.',
Ki='Kieran:BAAALgADCgEJAQAAAA==.Kirinkurai:BAABLgAECn8WAAIRAAYJrR0BAgCoAQARAAYJrR0BAgCoAQAAAA==.',
Km='Kmoniwnaleya:BAAALgADCgcJEQAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Kottenmouth:BAABLgAECn8pAAISAAgJ7yRmAAC/AgASAAgJ7yRmAAC/AgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQAAAA==.Kritea:BAABLgAECn8ZAAMTAAgJrhV7AwDkAQATAAgJrhV7AwDkAQAUAAEJ2BEBHgA9AAAAAA==.',
Ku='Kunimitsu:BAAALgADCgUJBQABLgAECgUJCwAHAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAAALgAECgYJDgAAAA==.',
Li='Life:BAAALgADCgkJHgAAAA==.Lizardmann:BAAALgAECgcJCwAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJIAABACkiAA==.',
Lu='Lumiere:BAAALgAECgYJDgAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAQJDAAKABYkAA==.Marshmallow:BAAALgAECgQJBwAAAA==.Maryla:BAABLgAECn8ZAAIIAAgJVBT1EQCTAQAIAAgJVBT1EQCTAQAAAA==.Maskara:BAAALgADCgUJBgAAAA==.',
Me='Metarage:BAAALgAECgYJCgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgADCgkJHgAAAA==.',
Ml='Mlj:BAAALgADCgYJBwAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgADCgcJCgAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgQJBwAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAAALgAECgYJEQAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Nativelock:BAAALgAECgYJDQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAAALgAECgYJEAAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
Nu='Nuka:BAAALgAECgQJDwAAAA==.',
Ny='Nynnaeve:BAAALgAECgUJDQAAAA==.',
On='Onions:BAABLgAECn8WAAMOAAgJ5RXWLwDIAQAOAAcJdBTWLwDIAQAQAAgJqw4aCQBsAQAAAA==.Onthecoda:BAAALgAECgQJBQAAAA==.',
Op='Opani:BAAALgADCggJFQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAAALgAECgYJDgAAAA==.',
Pa='Paigeturner:BAAALgAECgYJEwAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCggJCwABLgAECgIJAgAHAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAAALgAECgYJEgAAAA==.',
Ph='Phabio:BAAALgADCgkJFQAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAAALgAECgMJBQAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qr='Qrixe:BAAALgADCgIJAgAAAA==.',
Qu='Quelthemar:BAAALgADCgYJBgAAAA==.Quesy:BAABLgAECn8iAAIVAAkJgh//DQArAwAVAAkJgh//DQArAwAAAA==.',
Ra='Ragnabrew:BAAALgAECgUJBQABLgAFFAIJAgAHAAAAAA==.Ragnatotemzz:BAAALgAFFAIJAgAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgADCgUJBgAAAA==.',
Re='Rebelmonk:BAAALgADCgMJBQABLgAECgEJAQAHAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgEJAQAHAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rennl:BAAALgAECgEJAgAAAA==.Requiemechoe:BAAALgAECgUJBwAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgADCgYJCQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgADCggJDAABLgAECgIJAgAHAAAAAA==.Ripsets:BAABLgAECn8mAAMJAAgJQSWIAgB7AgAWAAgJIiBSEAC3AgAJAAcJUyWIAgB7AgAAAA==.',
Ro='Roflkopterz:BAAALgAECgQJCQAAAA==.Roflkopterzz:BAAALgAECgYJCwAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAIJAgAHAAAAAA==.',
Sa='Saeallina:BAAALgAECgMJBAAAAA==.Sarigos:BAAALgAECgcJCwAAAA==.Saviorselvz:BAAALgADCggJDQABLgAECgIJAgAHAAAAAA==.',
Sc='Schieldemon:BAABLgAECn8aAAMMAAgJUxh7LgBCAgAMAAgJUxh7LgBCAgAPAAQJ6gc2UQClAAAAAA==.Scrythe:BAAALgAECgYJEgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAQABLgAECgkJIAABACkiAA==.',
Sh='Shabooty:BAAALgAECgQJCwAAAA==.Shariandel:BAAALgAECggJEAAAAA==.Shiebert:BAAALgAECgQJBAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJEAAAAA==.Shrodwrah:BAAALgAECgYJEQAAAA==.',
Sk='Skkarrgh:BAAALgADCgIJAgAAAA==.',
So='Solomoon:BAACLgAFFH8JAAIXAAQJdhGqCQBEAQAXAAQJdhGqCQBEAQAuAAQKfyIABBcACQkKH5QFAPYCABcACQn3HpQFAPYCABgAAwmiHuk+AP4AABkAAQnhISxyAF4AAAAA.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.',
St='Stabsrael:BAABLgAFFH8GAAITAAMJDR3jAwA2AQATAAMJDR3jAwA2AQAAAA==.Stalkurnjr:BAAALgADCgYJBgABLgAECgcJCwAHAAAAAA==.Steamlene:BAAALgAECgMJAwAAAA==.Steelehorn:BAABLgAECn8eAAIaAAgJmR4+AgABAgAaAAgJmR4+AgABAgAAAA==.Stigmã:BAAALgADCgcJDgAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgUJBQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syryn:BAAALgAECgQJBwAAAA==.',
Ta='Talasacerdos:BAAALgAECgYJEgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAAALgAECgYJCwAAAA==.',
Th='Theirz:BAAALgAECgQJBQAAAA==.Thorgrum:BAABLgAECn8YAAIVAAYJaiWpCADzAQAVAAYJaiWpCADzAQAAAA==.',
Ti='Tillandra:BAAALgAECgQJBwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJBQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgAHAAAAAA==.',
Tw='Twistedteas:BAAALgAECgMJAwAAAA==.',
Tz='Tzzird:BAABLgAECn8cAAIIAAgJBiDVBQA4AgAIAAgJBiDVBQA4AgAAAA==.',
Um='Umbralstar:BAAALgAECgUJBQAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAAALgAECgUJCQAAAA==.',
Ve='Velddor:BAABLgAECn8eAAISAAcJ/SFLBgCdAgASAAcJ/SFLBgCdAgAAAA==.',
Vi='Vice:BAAALgAECgUJBwAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAAALgAECgQJCgAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8VAAMJAAYJZA0BJQDbAAAJAAYJZA0BJQDbAAAWAAIJYwBRhwA0AAAAAA==.',
Wh='Whoudini:BAAALgAECgYJEgAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAAALgAECgEJAQABLgAECggJHQAbAMgeAA==.',
Xc='Xcessiv:BAAALgAECgUJCwAAAA==.',
Xe='Xerãth:BAAALgAECgYJEQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJDgAHAAAAAA==.',
Ya='Yarndog:BAAALgADCgcJBwAAAA==.Yaviel:BAABLgAECn8VAAIJAAYJqhXlQgCkAQAJAAYJqhXlQgCkAQAAAA==.',
Yu='Yushis:BAAALgAECgYJEQAAAA==.',
Za='Zackaran:BAABLgAECn8UAAMcAAcJAQo0EADxAAAcAAcJAQo0EADxAAAKAAEJzwrb3gAlAAAAAA==.Zarrgon:BAEALgAECgYJDwAAAA==.Zarvok:BAAALgADCgcJBwAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAECgkJIgAVAIIfAA==.Zeromus:BAAALgAECgYJDgAAAA==.',
Zo='Zoidbergg:BAAALgAECgEJAQABLgAECggJHAAIAAYgAA==.',
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

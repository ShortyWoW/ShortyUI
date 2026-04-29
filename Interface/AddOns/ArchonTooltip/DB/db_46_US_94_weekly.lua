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

local lookup = {'Priest-Shadow','Warlock-Affliction','Druid-Restoration','Unknown-Unknown','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Hunter-Survival','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Preservation','Druid-Balance','DemonHunter-Havoc','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warrior-Protection',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarchon:BAAALgAECgYJEQAAAA==.',
Ad='Aduin:BAAALgADCgkJEQAAAA==.',
Ae='Aedarelyn:BAAALgAECgIJAwAAAA==.Aellet:BAAALgAECgYJEAAAAA==.Aellita:BAAALgADCgYJDAAAAA==.',
Ak='Akky:BAAALgAECgYJEAAAAA==.Aksafiya:BAABLgAECn8dAAIBAAYJ3Q9SMABgAQABAAYJ3Q9SMABgAQAAAA==.',
Al='Alandras:BAAALgAECgUJCwAAAA==.Alaras:BAACLgAFFH8GAAIBAAQJSgVZBAAIAQABAAQJSgVZBAAIAQAuAAQKfxkAAgEACQnKFggaAA8CAAEACQnKFggaAA8CAAAA.Allistair:BAABLgAECn8TAAICAAYJuhUeCgCdAQACAAYJuhUeCgCdAQAAAA==.Allrianne:BAAALgADCgkJFAAAAA==.Allyriae:BAAALgAECggJDQAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAAALgAECgcJEQAAAA==.',
Am='Ambilena:BAAALgAECgQJBAAAAA==.',
An='Andoros:BAABLgAECn8bAAIDAAYJ7CCVJwAXAgADAAYJ7CCVJwAXAgAAAA==.Angiliana:BAAALgAECgEJAgAAAA==.Angvall:BAAALgAECgYJBgABLgADCgYJCQAEAAAAAA==.Anzurath:BAAALgAECgYJEQAAAA==.',
Ap='Applebow:BAAALgAECgUJCwAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgADCgMJBAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arylin:BAABLgAECn8UAAIFAAYJ8h2iFwCIAQAFAAYJ8h2iFwCIAQAAAA==.',
As='Asheerr:BAAALgAECgIJAgAAAA==.Ashkinassi:BAEALgAECgIJAwAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgcJBwAEAAAAAA==.Asnabel:BAAALgAECgUJBgAAAA==.Aspirate:BAAALgADCgcJCwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAIJBQAGAHQlAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgADCgcJCgAAAA==.Ayden:BAAALgAECgEJAQAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgADCgIJAgAAAA==.',
Bl='Blee:BAAALgAECgUJDAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAAALgAECgYJDQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAAALgAECgUJCwAAAA==.Botsugo:BAAALgAECgEJAQAAAA==.',
Br='Braelia:BAAALgAECgYJEAAAAA==.Brood:BAABLgAECn8XAAIGAAgJOQ+FEACSAQAGAAgJOQ+FEACSAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAAALgAECgMJAwAAAA==.',
Ca='Cailaranel:BAAALgAECgYJEgAAAA==.Calaul:BAAALgAECgUJCQAAAA==.Calenbraga:BAAALgAECgIJAwAAAA==.Calisim:BAAALgAECgEJAgAAAA==.Callidae:BAABLgAECn8XAAIHAAcJ/QiTSQASAQAHAAcJ/QiTSQASAQAAAA==.Calmnbald:BAAALgAECgUJEQAAAA==.Cantoria:BAAALgADCgYJCgAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8UAAIIAAYJww7iFQBqAQAIAAYJww7iFQBqAQAAAA==.Cataryn:BAAALgAECgYJDAAAAA==.Catt:BAABLgAECn8bAAIJAAYJqhQADAB/AQAJAAYJqhQADAB/AQAAAA==.',
Ce='Cellebur:BAAALgAECgIJAwAAAA==.Ceta:BAABLgAECn8UAAIHAAYJrhjYKwCYAQAHAAYJrhjYKwCYAQAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAABLgAECn8XAAMKAAcJghbwCgBMAQAKAAYJOxrwCgBMAQALAAIJLgSblABKAAAAAA==.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAAALgAECgYJDAAAAA==.Cizean:BAAALgAECgIJAwAAAA==.',
Co='Cometopapa:BAAALgAECgYJEAAAAA==.',
Cr='Creaminator:BAAALgAECgEJAQAAAA==.Crilly:BAAALgAECgYJEgAAAA==.Crowe:BAAALgAECgMJBAABLgAECgUJBQAEAAAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAAALgAECgEJAQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Damia:BAAALgAECgUJCwAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAAALgAECgYJEQAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Delvarrieth:BAAALgAECgIJAwAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAAALgAECgYJEAAAAA==.Dercuur:BAAALgAECgUJCgAAAA==.Devoursol:BAAALgAECgYJEAAAAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgADCgYJEAAAAA==.Drainmee:BAAALgAECgEJAQAAAA==.Draknol:BAAALgADCgkJCQAAAA==.Dregoth:BAAALgAECgYJEAAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJAwAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8dAAIDAAgJhx5nEAC0AgADAAgJhx5nEAC0AgAAAA==.',
Ea='Eathur:BAAALgADCgcJCgAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgEJAQAAAA==.Elynth:BAAALgAECgYJEAAAAA==.',
En='Endlessyueh:BAAALgADCgYJDQAAAA==.',
Ev='Evilis:BAAALgADCgMJBAAAAA==.Evolnasty:BAAALgADCgcJCQABLgAECgkJJAAMAEsfAA==.',
Fa='Face:BAAALgAECgYJBgAAAA==.Faethian:BAABLgAECn8bAAINAAgJ5x+rAAB/AgANAAgJ5x+rAAB/AgAAAA==.Falunia:BAAALgAECgUJDQAAAA==.Fangren:BAAALgAECgEJAQAAAA==.Fariah:BAAALgAECgEJAgAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgMJBAAAAA==.Fatalis:BAAALgAECgYJCwAAAA==.Fated:BAAALgAECgUJBgAAAA==.',
Fe='Felscythe:BAAALgAECgIJAwAAAA==.Felynn:BAAALgAECgYJEwAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgMJAwAAAA==.',
Fi='Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAAALgAECgIJAwAAAA==.',
Fl='Flaeli:BAAALgAECgUJCwAAAA==.Flemish:BAAALgADCgkJGAAAAA==.Flextame:BAAALgADCgkJFgAAAA==.Flipalicious:BAABLgAECn8eAAILAAgJsha6BQAEAgALAAgJsha6BQAEAgAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAAALgAECgUJCgAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAAALgAECgUJCQAAAA==.Gazo:BAAALgADCggJEgABLgAECgYJDgAEAAAAAA==.',
Ge='Gemboss:BAAALgAECgYJEwAAAA==.Gerbo:BAABLgAECn8dAAMFAAgJDxDfHABmAQAFAAgJDxDfHABmAQAOAAMJrwXAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8UAAIPAAYJiQYTRQACAQAPAAYJiQYTRQACAQAAAA==.Ginodh:BAAALgAECgYJCwABLgAECgcJCQAEAAAAAA==.Ginomage:BAAALgAECgcJCQAAAA==.Ginopally:BAAALgAECgQJCAABLgAECgcJCQAEAAAAAA==.Girth:BAAALgADCgEJAQAAAA==.Gizelli:BAAALgADCgMJAwAAAA==.',
Go='Gordonn:BAAALgADCgcJCgAAAA==.',
Gr='Grubetsell:BAAALgADCgUJCgABLgAECgYJFAAQAP0iAA==.Grubetsella:BAABLgAECn8UAAIQAAYJ/SKuEABTAgAQAAYJ/SKuEABTAgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIRAAYJXBvCGAA6AQARAAYJXBvCGAA6AQAAAA==.Gumpers:BAAALgAECgUJCwAAAA==.Gundras:BAAALgADCgkJCQAAAA==.Gustice:BAAALgADCgYJDgAAAA==.',
Gy='Gyda:BAAALgADCgcJCwAAAA==.',
Ha='Hanoumatoi:BAAALgAECgIJAgAAAA==.Haralambos:BAAALgAECgIJAwAAAA==.Haralogain:BAAALgADCgMJAwABLgAECgIJAwAEAAAAAA==.Harithon:BAAALgAECgUJDQAAAA==.Havvöc:BAAALgAECgYJEAAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAAALgAECgMJAwAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJCwAAAA==.Hestiamajere:BAAALgAECgEJAgAAAA==.Heyokagi:BAAALgAECgYJEAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgYJEAAEAAAAAA==.Hordkilla:BAAALgAECgYJDgAAAA==.Hownowbrncw:BAAALgAECgYJDAAAAA==.',
Hu='Huuna:BAAALgADCgcJEAAAAA==.',
Hy='Hyce:BAABLgAECn8WAAIRAAYJ4BMCFQBVAQARAAYJ4BMCFQBVAQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgMJBAAAAA==.',
Im='Imathdal:BAAALgAECgYJEAAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAEAAAAAA==.Insoniacyun:BAAALgADCggJFwAAAA==.',
Is='Iselian:BAAALgAECgYJDAAAAQ==.Ishanu:BAAALgAECgYJCwAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAEAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jax:BAABLgAECn8hAAIFAAgJPiMMEwA1AwAFAAgJPiMMEwA1AwAAAA==.',
Jb='Jblockiv:BAAALgADCgUJBQAAAA==.Jbshami:BAAALgAECgUJEAAAAA==.',
Je='Jeb:BAAALgAECgMJAwAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn8UAAIOAAYJkwqKCgAzAQAOAAYJkwqKCgAzAQAAAA==.Jetfires:BAABLgAECn8XAAISAAcJBxIBEQB2AQASAAcJBxIBEQB2AQAAAA==.',
Ji='Jinger:BAAALgAECgMJAwAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jozhua:BAAALgADCgkJIwAAAA==.',
Ka='Kaedren:BAAALgADCgcJCgAAAA==.Kaelaya:BAAALgAECgYJDgAAAA==.Kaelorien:BAABLgAECn8UAAIQAAYJlQ36DgDyAAAQAAYJlQ36DgDyAAAAAA==.Kaetta:BAAALgAECgYJCQAAAA==.Kairelia:BAAALgAECgQJBgAAAA==.Kairilean:BAAALgAECgMJAwAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kaldevayn:BAAALgADCgkJGAAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgADCgcJDQAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAAALgAECgkJBQAAAA==.Kardanis:BAAALgAECgYJEQAAAA==.Kashe:BAAALgAECgEJAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAAALgAECgYJEQAAAA==.Kaydencia:BAAALgAECgYJEQAAAA==.Kayrae:BAAALgAECgEJAQAAAA==.Kaznahla:BAAALgAECgMJAwAAAA==.Kazureshal:BAAALgADCgkJBwAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.',
Ki='Ki:BAAALgAECgMJAwAAAA==.Kiddow:BAAALgADCgkJIQAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kiri:BAAALgADCgkJEAAAAA==.Kitamii:BAAALgAECgYJEwAAAA==.Kivrin:BAAALgAECgUJCgAAAA==.',
Kr='Kringlë:BAAALgAECgcJDgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.',
Ky='Kymma:BAAALgAECgUJDgAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAAALgAECgYJBwAAAA==.Laitue:BAAALgAECgQJBQAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAgAAAA==.Lazengann:BAAALgAECgYJEwAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Legevia:BAAALgADCgcJCgAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAAALgAECgYJEwAAAA==.Leucetios:BAAALgADCgYJBgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAAALgAECgQJBAAAAA==.Lightbeard:BAAALgAECgQJBgAAAA==.Lightdawns:BAAALgAECgIJAgAAAA==.Lightforge:BAAALgAECgYJDgAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgADCgQJBAAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgADCgQJBAAAAA==.Lothwen:BAAALgADCgkJGAAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAEBLgAECn8cAAIHAAgJ2hGMLACUAQAHAAgJ2hGMLACUAQAAAA==.Luxinine:BAAALgAECgUJCQAAAA==.',
Ly='Lyon:BAAALgADCgIJBAAAAA==.Lyshai:BAAALgADCgUJCAABLgAECgIJAwAEAAAAAA==.',
Ma='Madhawi:BAAALgAECgQJBAAAAA==.Magamon:BAAALgAECgYJEQAAAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAAALgAECgIJAwAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Margerdria:BAAALgAECgIJAwAAAA==.Maskelle:BAAALgAECgUJCwAAAA==.Mauugrim:BAAALgAECgUJCgAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAAALgAECgIJAwAAAA==.',
Me='Mearadan:BAAALgAECgYJCQAAAA==.Meatsweats:BAAALgADCggJEQAAAA==.Megumim:BAAALgAECgUJCgAAAA==.Mekh:BAAALgAECgIJAwAAAA==.Mel:BAAALgADCgkJFAAAAA==.Melanara:BAAALgAECgYJDwAAAA==.Melstrom:BAAALgADCgkJGAAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgMJAwAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAAALgAECgUJBgAAAA==.Miyävii:BAAALgAECgYJEQAAAA==.',
Mj='Mjsage:BAAALgAECgYJEAAAAA==.',
Mm='Mmeow:BAAALgADCgEJAQABLgAECgYJCgAEAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAAALgAECgIJAwAAAA==.Moonflowers:BAACLgAFFH8IAAIDAAMJvCHaCgAuAQADAAMJvCHaCgAuAQAuAAQKfygAAgMACAmNJHcAAEYDAAMACAmNJHcAAEYDAAAA.Mordsevoker:BAAALgAFFAEJAQABLgAFFAMJBgAGAP4CAA==.Mousekee:BAAALgAECgUJCQAAAA==.',
Mu='Murdrmitts:BAAALgAECgUJCQAAAA==.Mustikka:BAAALgAECgIJAwAAAA==.',
My='Myuriyanka:BAAALgAECgYJDgAAAA==.',
Na='Naahommii:BAAALgAECgYJDQAAAA==.Nachtpranke:BAAALgAECgUJCQAAAA==.Nadron:BAAALgADCgkJDwAAAA==.Nagualli:BAAALgADCgkJDwAAAA==.Naturecalls:BAAALgAECgQJCQAAAA==.',
Ne='Negargra:BAAALgAECgYJEQAAAA==.Nephadin:BAAALgADCgkJFgAAAA==.Nephilum:BAAALgADCggJDAAAAA==.',
Ni='Nidarian:BAAALgAECgMJAwAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAAALgAECgQJAwAAAA==.Nikooli:BAAALgAECgMJAwAAAA==.',
No='Noopsie:BAAALgAECgIJAgAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAUJEAATABIOAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAAALgAECgYJDgAAAA==.',
Ny='Nyteweaver:BAAALgAECgIJAwAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8WAAMFAAkJUANFLwANAQAFAAkJOwNFLwANAQAOAAcJogFAEgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgIJAgAAAA==.',
Od='Oderica:BAAALgADCgcJFAAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCgUJBwAAAA==.Olympia:BAAALgAECgUJCgAAAA==.',
On='Ontai:BAAALgADCgkJFAAAAA==.',
Os='Oscarmikey:BAACLgAFFH8GAAIDAAMJMQY9CgC6AAADAAMJMQY9CgC6AAAuAAQKfxcAAwMACAl6F4g1ANIBAAMABwkbGIg1ANIBABQAAQkAAoCLACMAAAAA.',
Ot='Ottoshot:BAAALgAECgIJAwAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Pa='Panamone:BAAALgAECgIJAwAAAA==.Pandeism:BAAALgAECgQJBgAAAA==.Patrin:BAAALgAECgUJCQAAAA==.',
Pe='Peanutbritle:BAAALgAECgYJEQAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJBwAAAA==.',
Ph='Phantdoom:BAAALgADCgkJEAAAAA==.',
Pl='Plsdiddyno:BAAALgAECgEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJAwAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Punchabaal:BAAALgAECgQJBQAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgEJAQAAAA==.Raharmin:BAAALgAECgYJEAAAAA==.Rargnara:BAAALgADCgkJBwAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgADCgcJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAECggJGQAFAKglAA==.Reyrocko:BAAALgADCgYJDgAAAA==.Rezdh:BAAALgADCgMJAQABLgAECggJHgABAGchAA==.Rezshift:BAAALgAECgYJEAABLgAECggJHgABAGchAA==.Rezvoid:BAABLgAECn8eAAIBAAgJZyGOCAD7AgABAAgJZyGOCAD7AgAAAA==.',
Rh='Rhage:BAAALgADCggJCwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJBgAAAA==.Rottingturky:BAAALgAECgcJDAAAAA==.Roxane:BAABLgAECn8UAAIUAAYJRwhwSgABAQAUAAYJRwhwSgABAQAAAA==.',
Ru='Runningelk:BAAALgAECgYJEgAAAA==.Runscapemain:BAAALgAECgYJEQAAAA==.',
['Rà']='Ràni:BAAALgADCgEJAQABLgAECgkJHwAVAKgkAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAABLgAECn8ZAAIWAAgJtREULADKAQAWAAgJtREULADKAQAAAA==.Sandía:BAAALgAECgYJCgAAAA==.Sanitas:BAAALgAECgQJCgAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAEAAAAAA==.',
Se='Seeyen:BAABLgAECn8iAAISAAkJVh4HBwAfAwASAAkJVh4HBwAfAwAAAA==.Selûne:BAAALgADCgcJDAAAAA==.Sentrath:BAAALgADCgcJFQAAAA==.Seraphi:BAAALgAECgYJDAAAAA==.Serenityhate:BAAALgAECgEJAQAAAA==.',
Sh='Shandrilyn:BAAALgADCgkJIwAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8aAAITAAgJmBNIHACkAQATAAgJmBNIHACkAQAAAA==.',
Si='Sinthoras:BAAALgADCgUJBQAAAA==.',
Sk='Skala:BAAALgAECgMJAwAAAA==.Skibbie:BAACLgAFFH8IAAMXAAQJdwReAQC3AAAXAAMJfgNeAQC3AAAYAAIJ4gOSHQCCAAAuAAQKfxgAAxgACQk8FlkQAHMCABgACQk8FlkQAHMCABcABQnNBoYsALcAAAAA.Skibbward:BAABLgAECn8gAAQZAAgJxCO4AQAyAwAZAAgJxCO4AQAyAwAUAAUJxQ9RVADUAAADAAUJTgzgggDSAAABLgAFFAQJCAAXAHcEAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgQJBAAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIUAAcJPR0OHQAYAgAUAAcJPR0OHQAYAgAAAA==.',
So='Solteria:BAAALgAECgYJDgAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgADCggJFAAAAA==.Sorvina:BAAALgAECgYJDgAAAA==.Soulflame:BAAALgAECgYJEQAAAA==.Soulshifter:BAAALgAECgQJBgAAAA==.Soultrader:BAAALgADCgcJBgABLgAECgIJAwAEAAAAAA==.',
Sp='Spooñ:BAAALgADCgcJBwAAAA==.Spottedcoat:BAAALgAECgYJEQAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Stregnor:BAABLgAECn8UAAISAAYJAQ+AGgAoAQASAAYJAQ+AGgAoAQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAECgkJHwAVAKgkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn8VAAMPAAYJcRVPCQA/AQAPAAYJcRVPCQA/AQAaAAQJ7QqHZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMYAAkJDxKoEwBHAgAYAAkJfhGoEwBHAgAXAAYJoRLvHwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgYJFAAYAB0WAA==.Tachie:BAABLgAECn8UAAMYAAYJHRY5JwCDAQAYAAYJmhM5JwCDAQAXAAUJDBSuJQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAMJBQAbAH0lAA==.Taele:BAAALgAECgYJEAAAAA==.Taiche:BAABLgAECn8fAAIUAAYJoQ2CDwD9AAAUAAYJoQ2CDwD9AAAAAA==.Tamalpais:BAAALgAECgEJAQAAAA==.Tanya:BAAALgADCgEJAQAAAA==.Tareyn:BAAALgADCgkJCwAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAAALgAECgIJAwAAAA==.',
Th='Therin:BAABLgAECn8UAAIIAAYJSBH+BwA0AQAIAAYJSBH+BwA0AQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.',
To='Toofast:BAAALgAECgQJCAAAAA==.Toofurrious:BAAALgADCgkJGQAAAA==.Topswimmer:BAAALgADCggJBQAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgMJAwAAAA==.',
Tr='Trifus:BAAALgADCgkJJAAAAA==.Trydora:BAAALgAECgEJAgAAAA==.',
Ts='Tsugumi:BAAALgADCgkJGwAAAA==.',
Tu='Tulao:BAAALgAECgYJDAAAAA==.',
Tw='Twan:BAAALgAECgEJAQAAAA==.',
Ty='Tyrionel:BAAALgAECgUJCQAAAA==.',
Tz='Tzitzimitl:BAAALgADCgkJCQAAAA==.',
Ui='Uiknu:BAAALgAFFAIJAgAAAA==.',
Ut='Utheli:BAABLgAECn8ZAAIMAAgJNRbaCgDiAQAMAAgJNRbaCgDiAQAAAA==.',
Va='Vaevictis:BAAALgADCgEJAQABLgAECgUJCgAEAAAAAA==.Vaildora:BAAALgADCgYJDgABLgAECgYJFAAYAB0WAA==.Valdra:BAABLgAECn8UAAIcAAYJDw95CAAFAQAcAAYJDw95CAAFAQAAAA==.',
Vi='Viralprepped:BAAALgADCgkJFAAAAA==.Vitamix:BAAALgADCgUJCAAAAA==.',
Vl='Vlonet:BAAALgAECgcJEgAAAA==.',
Vn='Vnasty:BAABLgAECn8kAAIMAAkJSx8kCgBAAwAMAAkJSx8kCgBAAwAAAA==.',
Wa='Wart:BAAALgADCgcJDgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgADCgEJAQAAAA==.',
Wi='Wilken:BAAALgAECgQJBgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAAALgAECgYJEQAAAA==.',
Ws='Wspr:BAAALgAECgIJAgAAAA==.',
Xa='Xavencia:BAAALgAECgYJCQAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xinthos:BAAALgADCgIJAgAAAA==.',
Ya='Yanut:BAAALgAECgEJAQAAAA==.',
Ye='Yeetjin:BAAALgAECgEJAQAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Za='Zadivya:BAAALgAECgUJCwAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAAALgAECgYJEQAAAA==.',
Ze='Zelgaddis:BAAALgAECgYJEAAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAAALgAECgQJBwAAAA==.',
Zr='Zriana:BAAALgADCgkJDAAAAA==.',
Zs='Zsarilya:BAAALgAECgUJCwAAAA==.',
Zu='Zurgen:BAABLgAECn8UAAIbAAYJjxwXFABvAQAbAAYJjxwXFABvAQAAAA==.',
Zz='Zzypria:BAAALgADCgYJBgAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8VAAIDAAcJ+QgkZQAjAQADAAcJ+QgkZQAjAQABLgAECggJHAAHANoRAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
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

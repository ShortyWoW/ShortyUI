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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Mage-Frost','DeathKnight-Unholy','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Shaman-Enhancement','Shaman-Restoration','Hunter-BeastMastery','Monk-Mistweaver','Warrior-Fury','Priest-Shadow','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Devourer','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Shaman-Elemental','DemonHunter-Havoc','Monk-Brewmaster',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Accursed:BAACLgAFFH8FAAIBAAMJ/SISAQA6AQABAAMJ/SISAQA6AQAuAAQKfyIAAgEACAl5JkIAAAkDAAEACAl5JkIAAAkDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Al='Aleighta:BAAALgAECgcJDwAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgADCgIJAgAAAA==.',
Am='Amadia:BAAALgADCgYJBQAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAAALgAECgMJBAAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJCgAAAA==.Ashkillz:BAAALgAECgYJBgAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAAALgAECgYJCAAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgIJAwACAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8RAAIDAAUJDx/xBgB9AQADAAUJDx/xBgB9AQAuAAQKfxoAAgMACAn8Ij0RAAYDAAMACAn8Ij0RAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBAABLgAECggJIAAEAMYbAA==.Belan:BAABLgAECn8WAAIFAAgJ5w/ASgBPAQAFAAgJ5w/ASgBPAQAAAA==.Belladin:BAABLgAECn8gAAIDAAkJ0B/UHgCyAgADAAkJ0B/UHgCyAgAAAA==.',
Bl='Blameurself:BAAALgAECgcJCQAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgcJCQACAAAAAA==.Blaster:BAAALgAECgEJBQAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgADCgcJBwAAAA==.',
Bo='Bombakaap:BAAALgAECgUJBQAAAA==.Bomburst:BAAALgAECgUJEQAAAA==.Bonelespizza:BAABLgAECn8uAAIGAAkJhh4YFAAZAgAGAAkJhh4YFAAZAgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAABLgAECn8YAAIEAAgJsRtVCABlAgAEAAgJsRtVCABlAgAAAA==.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAUJDgAGAEccAA==.',
['Bë']='Bëz:BAAALgAECgYJEwAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgADCgUJBQAAAA==.Casteel:BAAALgAECgcJCwAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgUJBgABLgAFFAQJCwAHANkVAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAAALgAECgUJDAAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAAALgAECgQJBAAAAA==.Cosmicjay:BAEALgAECgYJDgAAAA==.Cosmicnova:BAEALgAECgYJBgABLgAECgYJDgACAAAAAA==.Costa:BAAALgADCggJFQAAAA==.',
Cr='Crentacles:BAAALgAECgcJDwAAAA==.Critshade:BAAALgAECgYJDAAAAA==.Crow:BAAALgAFFAMJCAAAAQ==.',
Da='Daffodil:BAAALgAECgUJDAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8IAAIIAAMJtgraEgDSAAAIAAMJtgraEgDSAAAuAAQKfx0AAggACAlZG0kdAFMCAAgACAlZG0kdAFMCAAAA.Darkshiver:BAAALgADCgEJAgABLgAECgEJBQACAAAAAA==.Dawnslight:BAAALgAECgQJBgAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgADCgIJAgAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAEJAQACAAAAAA==.Dephiance:BAAALgADCgkJEQABLgAECgcJEwACAAAAAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAAALgAECgYJEQAAAA==.Dinsfirë:BAAALgADCgMJAwAAAA==.Diothorn:BAAALgAECgUJCwAAAA==.Divanas:BAAALgAECgMJBgAAAA==.Divi:BAAALgAECgYJDgAAAA==.',
Do='Doxa:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAAALgAECgYJDgAAAA==.Drpepperz:BAAALgAECgcJCwAAAA==.',
Du='Durock:BAAALgADCgQJBAABLgAECgYJCwACAAAAAA==.Dusk:BAAALgAECgEJAQABLgADCgkJFgACAAAAAA==.',
Dy='Dymondsmashr:BAAALgAECgYJEwAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgQJBAACAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Everydae:BAABLgAECn8mAAIJAAkJ0R9QAgDWAgAJAAkJ0R9QAgDWAgAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgcJDAACAAAAAA==.',
Fa='Fakedruid:BAAALgAECgYJDAABLgAECggJIAAEAMYbAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feybeasts:BAAALgADCgUJBQAAAA==.Feárbomber:BAAALgADCgcJDgABLgAECgYJEwACAAAAAA==.',
Ff='Ffand:BAAALgAECgYJDwAAAA==.',
Fh='Fharia:BAAALgADCgQJBAAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flayr:BAAALgADCgQJBAAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgQJBAAAAA==.',
Fu='Fusky:BAAALgAECgcJEwAAAA==.',
Fy='Fynn:BAACLgAFFH8GAAIKAAMJ4wXvBACTAAAKAAMJ4wXvBACTAAAuAAQKfx8AAwoACAmLFQsLABwCAAoACAmLFQsLABwCAAsAAQmjAYapACQAAAAA.',
Ga='Galadria:BAAALgAFFAIJBAAAAA==.',
Ge='Gerwik:BAAALgAECgUJEgAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goliather:BAAALgADCgEJAQAAAA==.',
Gr='Greenleaves:BAAALgAECgYJEAAAAA==.Greenpepperz:BAAALgADCgIJAgAAAA==.Gregsh:BAAALgAECggJEwAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummiwormz:BAAALgAECgYJCgAAAA==.',
Ha='Hailin:BAABLgAECn8lAAIDAAgJIhwYFQASAgADAAgJIhwYFQASAgAAAA==.Halrem:BAAALgAECgEJAQAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAAALgAECgQJCwAAAA==.',
He='Hellman:BAAALgADCgUJCQAAAA==.',
Hi='Hightroller:BAABLgAECn8eAAIMAAgJ/g+6HACzAQAMAAgJ/g+6HACzAQAAAA==.Hima:BAAALgAECgYJDgAAAA==.',
Ho='Holysathh:BAAALgAECgUJDgABLgAECgYJCwACAAAAAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Homulily:BAAALgADCgcJFAAAAA==.Hornggry:BAAALgAECgQJAwABLgAECgYJEQACAAAAAA==.Horngrry:BAAALgAECgQJBAABLgAECgYJEQACAAAAAA==.Horngryerr:BAAALgAECgYJEQAAAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJAwABLgAECggJIgANAGoYAA==.',
Hu='Huntingpants:BAAALgAECgYJEQAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECgYJEQACAAAAAA==.',
In='Inspiredbox:BAAALgAECgMJAgAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBQACAAAAAA==.Jankismith:BAAALgAECgYJEAAAAA==.Jayy:BAAALgAECgYJEwAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAcJFwAOANkfAA==.Jenny:BAABLgAECn8fAAIDAAYJFxg/NwBnAQADAAYJFxg/NwBnAQAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgQJBgAAAA==.',
Ju='Junieb:BAAALgAECgcJDwAAAA==.',
Ka='Kachiko:BAAALgADCggJDAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAAALgAECgQJCAAAAA==.Kamerth:BAAALgAECgYJEgAAAA==.Kapnkrunch:BAAALgADCgcJFgAAAA==.Karluron:BAAALgAECgcJDQAAAA==.Karlutros:BAABLgAECn8VAAIPAAcJxwskFQBXAQAPAAcJxwskFQBXAQAAAA==.Katowo:BAAALgAECgQJBQABLgAFFAUJBgAQAHQkAA==.Katuwuagain:BAABLgAFFH8GAAIQAAUJdCT+AQCqAQAQAAUJdCT+AQCqAQAAAA==.Kazure:BAABLgAECn8kAAIRAAkJ+AksHgCQAQARAAkJ+AksHgCQAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn8kAAIOAAgJqwkQFwB6AQAOAAgJqwkQFwB6AQAAAA==.Keybricker:BAAALgAECgUJCAABLgAECggJIAAEAMYbAA==.',
Kh='Khaôtic:BAABLgAECn8VAAISAAYJYReBKQBAAQASAAYJYReBKQBAAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAAALgAECgYJEAAAAA==.Kittykat:BAAALgADCgIJAgAAAA==.',
Kr='Krakkin:BAAALgADCgYJBwAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJCgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgADCgMJAwABLgAECgYJEQACAAAAAA==.',
Ky='Kyllea:BAAALgAECgUJCAAAAA==.',
['Kä']='Kätniss:BAAALgADCgcJBwAAAA==.',
La='Laaksy:BAABLgAECn8cAAITAAcJNg8UFwCDAQATAAcJNg8UFwCDAQAAAA==.Ladraina:BAAALgADCgcJCAAAAA==.Landock:BAAALgADCgYJDAAAAA==.Lavaca:BAABLgAECn8UAAMUAAgJwSF/CQD5AgAUAAgJwSF/CQD5AgAVAAQJcR3IBQBgAQAAAA==.',
Le='Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAABLgAECn8nAAIIAAgJfg8WKwA2AQAIAAgJfg8WKwA2AQAAAA==.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgADCgEJAQAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Linaraline:BAAALgADCgUJBQAAAA==.Linasong:BAAALgAECgEJAQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgQJBwAAAA==.Lotharmage:BAAALgAECgYJCwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAECgUJBgAAAA==.',
Ma='Magnessa:BAAALgAECgQJCAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgADCgMJAwAAAA==.Marist:BAAALgAECgcJDwAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.',
Me='Meliodäs:BAAALgADCgkJEwAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQACAAAAAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAAALgAECgYJDgAAAA==.Miku:BAAALgADCgcJEAABLgAECggJJQADACIcAA==.Milent:BAABLgAECn8UAAIMAAcJkxTDRwD6AAAMAAcJkxTDRwD6AAAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJAgAAAA==.',
Mo='Moarteas:BAAALgADCgQJAgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAAALgAECgYJEAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJCQAAAA==.',
Mx='Mximus:BAAALgADCgEJAQABLgAECgIJAwACAAAAAA==.',
My='Mystí:BAAALgAECggJDAAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECggJIgAHADAhAA==.Nabstarr:BAABLgAECn8iAAMHAAgJMCH5AQAEAwAHAAgJMCH5AQAEAwAWAAEJRgOMhQArAAAAAA==.Nasroth:BAABLgAECn8kAAIOAAcJAhLZPACxAQAOAAcJAhLZPACxAQAAAA==.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Nightthane:BAAALgADCgkJHAAAAA==.Niibyter:BAAALgAECgYJEAAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
Od='Odînson:BAAALgADCgUJBQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMIAAYJ2BBvNQABAQAIAAYJ2BBvNQABAQAXAAYJbQqHhAAsAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8UAAMYAAYJKBB5KgAXAQAZAAYJ9gwfRAAlAQAYAAUJFRB5KgAXAQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAAALgAECgUJDwAAAA==.',
Or='Orangedrives:BAAALgADCgUJBwAAAA==.Oreeoreo:BAABLgAECn8fAAIGAAgJHREqNwBdAQAGAAgJHREqNwBdAQAAAA==.Orlis:BAAALgAECggJEwAAAA==.Oroe:BAAALgAECgYJCwAAAA==.',
Pa='Pallydan:BAAALgAECgEJAQAAAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAAALgAECggJEAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJDAABLgAECggJDAACAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8hAAMRAAgJ5hfgBAAZAgARAAgJ5hfgBAAZAgAJAAYJZBS8FwA/AQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAECggJGAAEALEbAA==.',
Pl='Plumh:BAAALgADCgIJAgAAAA==.Pläze:BAAALgAECgUJBgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgcJDQAAAA==.',
Pr='Praîmfaya:BAAALgAECgQJBQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAIaAAgJmhOEDACuAQAaAAgJmhOEDACuAQAAAA==.',
Py='Pyronorish:BAAALgADCgYJDQAAAA==.Pytthia:BAAALgAECgcJEwAAAA==.',
['Pä']='Pändamonium:BAAALgADCgcJBQAAAA==.',
Qu='Quicknclever:BAAALgADCgMJAwAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Rayquaza:BAAALgAECgcJDgABLgAFFAcJDgACAAAAAA==.Raziel:BAABLgAECn8RAAISAAgJSRk8NAAoAgASAAgJSRk8NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQAAAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDgAAAA==.',
Ri='Rikiriki:BAAALgAECgUJDAAAAA==.',
Ro='Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJBAAAAA==.Ronkzar:BAAALgADCgQJCgAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Ruth:BAAALgAECgYJBgAAAA==.',
Sa='Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgUJBQAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgQJBAAAAA==.',
Sc='Scurge:BAAALgAECgIJAwAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Setal:BAABLgAECn8dAAMJAAgJ7xaYCQDyAQAJAAgJ7xaYCQDyAQATAAEJIxHZPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8FAAIbAAQJ0xNACgA8AQAbAAQJ0xNACgA8AQAuAAQKfyMAAxsACQn2I2wBALIDABsACQn2I2wBALIDAAsABgkbGOhCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCAAAAA==.Sheenzilla:BAABLgAECn8jAAMJAAgJGQV3HQAUAQAJAAgJGQV3HQAUAQARAAYJIQF6OACnAAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shoinked:BAABLgAECn8WAAIbAAgJagaHHAAxAQAbAAgJagaHHAAxAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgADCgYJEQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAAALgAECgYJEwAAAA==.',
Sl='Slak:BAAALgAECgYJCAAAAA==.',
Sm='Smallchaos:BAABLgAECn8dAAIcAAYJzRRiEAA3AQAcAAYJzRRiEAA3AQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgYJHQAcAM0UAA==.Smallêntropy:BAAALgAECgUJCQAAAA==.Smelt:BAAALgAECgIJCQAAAA==.Smuurfette:BAEALgAECgcJDAAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgADCgYJBgAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECgcJDAACAAAAAA==.',
St='Stabbytrout:BAABLgAECn8VAAIUAAkJKxdXCADpAQAUAAkJKxdXCADpAQAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIaAAYJuRLWBABNAQAaAAYJuRLWBABNAQAuAAQKfxUAAhoACQn1IXEGABkDABoACQn1IXEGABkDAAEuAAUUBwkXAA4A2R8A.Sunetra:BAAALgAECgcJDwAAAA==.Sunraku:BAAALgAECgEJAgABLgAECgEJBQACAAAAAA==.Sunshine:BAAALgADCgkJFgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taloki:BAAALgADCgYJFgAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECgYJCAAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAAALgAECgYJEwAAAA==.',
Ti='Tinny:BAAALgAECgEJAgAAAA==.Tippshunter:BAABLgAECn8gAAIEAAgJxhu7BAA2AgAEAAgJxhu7BAA2AgAAAA==.',
To='Toph:BAACLgAFFH8HAAMTAAMJWhzxAQASAQATAAMJwBjxAQASAQAJAAEJFyHgHgBbAAAuAAQKfx0ABBMACAkZI1MJAEwCABMABgkJI1MJAEwCABEAAwljBEk9AIAAAAkAAgm/GyFCAEkAAAAA.Tophdh:BAABLgAECn8dAAIBAAgJUiK6AQD/AgABAAgJUiK6AQD/AgABLgAFFAMJBwATAFocAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECggJIwAdAL0XAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECggJIwAdAL0XAA==.Tryit:BAAALgAECgQJBAABLgAECggJIwAdAL0XAA==.Trythefox:BAABLgAECn8jAAIdAAgJvRc0DgCqAQAdAAgJvRc0DgCqAQAAAA==.',
Ts='Tseris:BAAALgAECgEJAgAAAA==.Tsukihana:BAAALgADCggJCAAAAA==.',
Tu='Tuini:BAAALgAECgYJEQAAAA==.',
Ty='Tydis:BAABLgAECn8UAAIDAAcJeQnJSQAtAQADAAcJeQnJSQAtAQAAAA==.',
['Tá']='Tálonstorm:BAAALgAECgYJEwAAAA==.',
Ul='Ultra:BAAALgAECgEJAQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.',
Va='Vaehunt:BAAALgADCgMJBAABLgAFFAQJBwASAL8PAA==.Vaesara:BAACLgAFFH8HAAISAAQJvw/WEwApAQASAAQJvw/WEwApAQAuAAQKfx0AAhIACAmTHXQlAHICABIACAmTHXQlAHICAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Vani:BAAALgAECgUJEQAAAA==.',
Ve='Velora:BAAALgAECgMJAwAAAA==.',
Vi='Vilthrax:BAAALgAECgQJBAAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwACAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwAAAA==.Waffleiron:BAABLgAECn8VAAQHAAYJJiIbIgCDAQAHAAYJlSEbIgCDAQAWAAMJsx6ISwAKAQAPAAQJRhAnHwABAQAAAA==.Watermelon:BAAALgAECgMJAwAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8YAAIMAAgJkQ6EHAC0AQAMAAgJkQ6EHAC0AQAAAA==.',
Wi='Wickedsin:BAAALgAECgUJBQAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAABLgAFFH8GAAIIAAQJTQ5yEQATAQAIAAQJTQ5yEQATAQAAAA==.',
Xa='Xaalath:BAAALgAECgUJDQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIRAAgJPwhqIQBwAQARAAgJPwhqIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECgYJEAAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.',
Yo='Yobaz:BAAALgADCgIJAgAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgADCgYJBgAAAA==.Zarinah:BAAALgAECgEJAQAAAA==.Zarorisk:BAAALgAECgUJCQAAAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgADCgEJAQAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8WAAIEAAYJFRd0EgCbAQAEAAYJFRd0EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIDAAgJXhoCJwCnAQADAAgJXhoCJwCnAQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAAALgAECgYJDQAAAA==.',
['Øn']='Ønyx:BAAALgAECgMJBAAAAA==.',
['ße']='ßeam:BAAALgAECgEJAQAAAA==.',
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

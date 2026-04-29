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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','DeathKnight-Unholy','Priest-Discipline','Druid-Restoration','Monk-Brewmaster','Evoker-Augmentation','Shaman-Enhancement','Shaman-Restoration','Hunter-BeastMastery','Monk-Mistweaver','Warrior-Fury','Evoker-Preservation','DemonHunter-Devourer','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Monk-Windwalker','Druid-Guardian','Shaman-Elemental','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Accursed:BAABLgAECn8fAAIBAAgJXyYRAAATAwABAAgJXyYRAAATAwAAAA==.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Al='Aleighta:BAAALgAECgcJDwAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.',
Am='Amadia:BAAALgADCgYJBQAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAAALgAECgMJBAAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgEJAQAAAA==.',
As='Asatrath:BAAALgAECgYJCgAAAA==.Ashkillz:BAAALgAECgYJBgAAAA==.Ashtuck:BAAALgAECgYJBgAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAAALgAECgIJAgAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgEJAQACAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJBgAAAA==.',
Ba='Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgIJAgAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8MAAIDAAQJexAJBQBEAQADAAQJexAJBQBEAQAuAAQKfxoAAgMACAn8IjcRAAYDAAMACAn8IjcRAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBAABLgAECggJHAAEANwaAA==.Belan:BAAALgAECgcJDwAAAA==.Belladin:BAABLgAECn8dAAIDAAgJXh7YHgCyAgADAAgJXh7YHgCyAgAAAA==.',
Bl='Blameurself:BAAALgAECgcJCQAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgcJCQACAAAAAA==.Blaster:BAAALgAECgEJAwAAAA==.Blite:BAAALgADCgQJDQAAAA==.',
Bo='Bombakaap:BAAALgADCgcJDQAAAA==.Bomburst:BAAALgAECgUJEAAAAA==.Bonelespizza:BAABLgAECn8oAAIFAAgJOB/XIwCvAgAFAAgJOB/XIwCvAgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAABLgAECn8UAAIEAAgJsRtTCABlAgAEAAgJsRtTCABlAgAAAA==.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAUJCgAFAFwYAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Casteel:BAAALgAECgcJBAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgUJBgABLgAFFAQJBwAGAEYNAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAAALgAECgUJCAAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAAALgADCgkJCQAAAA==.Cosmicjay:BAEALgAECgYJDgAAAA==.Costa:BAAALgADCgYJEgAAAA==.',
Cr='Crentacles:BAAALgAECgYJDAAAAA==.Critshade:BAAALgAECgYJDAAAAA==.Crow:BAAALgAFFAIJAgAAAQ==.',
Da='Daffodil:BAAALgAECgQJBwAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8FAAIHAAMJtgrUEgDSAAAHAAMJtgrUEgDSAAAuAAQKfxsAAgcACAnZGkgdAFMCAAcACAnZGkgdAFMCAAAA.Dawnslight:BAAALgAECgQJBAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAYJGQAIAOsiAA==.Dephiance:BAAALgADCggJCAABLgAECgUJDAACAAAAAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJCgAAAA==.',
Di='Diabla:BAAALgAECgYJEAAAAA==.Dinsfirë:BAAALgADCgIJAgAAAA==.Diothorn:BAAALgAECgQJBQAAAA==.Divanas:BAAALgAECgMJAwAAAA==.Divi:BAAALgAECgQJBwAAAA==.',
Dr='Dragonboi:BAAALgAECgQJBwAAAA==.Drpepperz:BAAALgAECgUJBQAAAA==.',
Du='Durock:BAAALgADCgQJBAABLgAECgUJDgACAAAAAA==.',
Dy='Dymondsmashr:BAAALgAECgUJDQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgQJBAAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgQJBAACAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJBQAAAA==.Everydae:BAABLgAECn8gAAIJAAgJqRsIAgBBAgAJAAgJqRsIAgBBAgAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgcJDAACAAAAAA==.',
Fa='Fakedruid:BAAALgAECgYJBgABLgAECggJHAAEANwaAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feybeasts:BAAALgADCgUJBQAAAA==.Feárbomber:BAAALgADCgcJDgABLgAECgYJDwACAAAAAA==.',
Ff='Ffand:BAAALgAECgYJDwAAAA==.',
Fh='Fharia:BAAALgADCgQJBAAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flayr:BAAALgADCgQJBAAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgQJBAAAAA==.',
Fu='Fusky:BAAALgAECgYJEQAAAA==.',
Fy='Fynn:BAABLgAECn8eAAMKAAgJixULCwAcAgAKAAgJixULCwAcAgALAAEJowF9qQAkAAAAAA==.',
Ga='Galadria:BAAALgAFFAEJAQAAAA==.',
Ge='Gerwik:BAAALgAECgUJCAAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDAAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goliather:BAAALgADCgEJAQAAAA==.',
Gr='Greenleaves:BAAALgAECgUJCgAAAA==.Greenpepperz:BAAALgADCgIJAgAAAA==.Gregsh:BAAALgAECgcJEAAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummiwormz:BAAALgAECgEJAgAAAA==.',
Ha='Hailin:BAABLgAECn8dAAIDAAcJeRh8EQCXAQADAAcJeRh8EQCXAQAAAA==.Halrem:BAAALgAECgEJAQAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAAALgAECgQJBwAAAA==.',
He='Hellman:BAAALgADCgUJCQAAAA==.',
Hi='Hightroller:BAABLgAECn8WAAIMAAcJYguzHwADAQAMAAcJYguzHwADAQAAAA==.Hima:BAAALgAECgQJBwAAAA==.',
Ho='Holysathh:BAAALgAECgUJDgAAAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Homulily:BAAALgADCgcJFAAAAA==.Hornggry:BAAALgAECgQJAwABLgAECgUJDQACAAAAAA==.Horngrry:BAAALgAECgQJBAABLgAECgUJDQACAAAAAA==.Horngryerr:BAAALgAECgUJDQAAAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJAwABLgAECggJHQANAGoYAA==.',
Hu='Huntingpants:BAAALgAECgYJDQAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECgUJDQACAAAAAA==.',
In='Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jankismith:BAAALgAECgYJDgAAAA==.Jayy:BAAALgAECgUJDQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAcJEgAOANkfAA==.Jenny:BAABLgAECn8ZAAIDAAYJXxHxsAAiAQADAAYJXxHxsAAiAQAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgYJDAAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgQJBgAAAA==.',
Ju='Junieb:BAAALgAECgcJDwAAAA==.',
Ka='Kachiko:BAAALgADCggJDAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAAALgAECgQJBQAAAA==.Kamerth:BAAALgAECgUJDAAAAA==.Kapnkrunch:BAAALgADCgcJFgAAAA==.Karluron:BAAALgAECgYJCAAAAA==.Karlutros:BAAALgAECgYJDgAAAA==.Katowo:BAAALgAECgQJBQABLgAFFAQJBwAIAEUgAA==.Katuwuagain:BAAALgAFFAEJAQABLgAFFAQJBwAIAEUgAA==.Kazure:BAABLgAECn8hAAIPAAgJsAorHgCQAQAPAAgJsAorHgCQAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn8cAAIOAAgJegfrDwAtAQAOAAgJegfrDwAtAQAAAA==.',
Kh='Khaôtic:BAABLgAECn8VAAIQAAYJfha8FABXAQAQAAYJfha8FABXAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgADCgYJBwAAAA==.Kiraeshh:BAAALgAECgUJDQAAAA==.Kittykat:BAAALgADCgIJAgAAAA==.',
Kr='Krakkin:BAAALgADCgEJAgAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJCAAAAA==.Krieash:BAAALgADCggJCAAAAA==.',
Ky='Kyllea:BAAALgAECgQJBwAAAA==.',
['Kä']='Kätniss:BAAALgADCgcJBwAAAA==.',
La='Laaksy:BAABLgAECn8cAAIRAAcJNg8QFwCDAQARAAcJNg8QFwCDAQAAAA==.Ladraina:BAAALgADCgYJBgAAAA==.Landock:BAAALgADCgYJBgAAAA==.Lavaca:BAABLgAECn8UAAMSAAgJwSF+CQD5AgASAAgJwSF+CQD5AgATAAQJWh0oBAAYAQAAAA==.',
Le='Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAABLgAECn8cAAIHAAcJVg6wTwBmAQAHAAcJVg6wTwBmAQAAAA==.Leprechaune:BAAALgADCgkJGQAAAA==.Leticia:BAAALgADCgEJAQAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Linaraline:BAAALgADCgUJBQAAAA==.Linasong:BAAALgAECgEJAQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgEJAwAAAA==.Lotharmage:BAAALgAECgQJBAAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAECgUJBgAAAA==.',
Ma='Magnessa:BAAALgAECgQJBQAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgADCgMJAwAAAA==.Marist:BAAALgAECgcJDwAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.',
Me='Meliodäs:BAAALgADCgcJEAAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQACAAAAAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAAALgAECgUJCAAAAA==.Miku:BAAALgADCgYJCQABLgAECgcJHQADAHkYAA==.Milent:BAAALgAECgYJEgAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJAgAAAA==.',
Mo='Moarteas:BAAALgADCgQJAgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAAALgAECgYJCgAAAA==.',
Mv='Mvpiam:BAAALgAECgQJCAAAAA==.',
Mx='Mximus:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
My='Mystí:BAAALgAECggJCwAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgcJGwAGAKUeAA==.Nabstarr:BAABLgAECn8bAAMGAAcJpR6wAQByAgAGAAcJpR6wAQByAgAUAAEJRgOBhQArAAAAAA==.Nasroth:BAABLgAECn8jAAIOAAcJAhLTPACxAQAOAAcJAhLTPACxAQAAAA==.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Nightthane:BAAALgADCgkJHAAAAA==.Niibyter:BAAALgAECgUJCgAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
Od='Odînson:BAAALgADCgUJBQAAAA==.',
Ol='Oldgreyone:BAAALgAECgYJDgAAAA==.',
On='Onlyheelz:BAAALgAECgEJAgAAAA==.Onlylocks:BAAALgAECgYJDgAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAAALgAECgUJDwAAAA==.',
Or='Orangedrives:BAAALgADCgIJAgAAAA==.Oreeoreo:BAABLgAECn8fAAIFAAgJHRH1EQCEAQAFAAgJHRH1EQCEAQAAAA==.Orlis:BAAALgAECgYJCwAAAA==.Oroe:BAAALgAECgYJBwAAAA==.',
Pa='Pallydan:BAAALgAECgEJAQAAAA==.',
Pe='Peludita:BAAALgAECggJEAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJBwABLgAECggJCwACAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8aAAIPAAgJuRe/AQAjAgAPAAgJuRe/AQAjAgAAAA==.',
Pi='Pitchfiend:BAAALgADCgcJBwAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAECggJFAAEALEbAA==.',
Pl='Plumh:BAAALgADCgIJAgAAAA==.Pläze:BAAALgAECgUJBgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgcJDQAAAA==.',
Pr='Praîmfaya:BAAALgAECgQJBQAAAA==.',
Pu='Punchpup:BAABLgAECn8iAAIVAAgJnBJIBgCCAQAVAAgJnBJIBgCCAQAAAA==.',
Py='Pyronorish:BAAALgADCgEJAQAAAA==.Pytthia:BAAALgAECgUJDAAAAA==.',
Ra='Randamonk:BAAALgAECgQJBAAAAA==.Rayquaza:BAAALgAECgcJDgABLgAFFAYJDAAHAAMOAA==.Raziel:BAABLgAECn8UAAIQAAgJBBo7NAAoAgAQAAgJBBo7NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAECggJJQAWAOQIAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJBwAAAA==.',
Rh='Rhaena:BAAALgAECgQJCAAAAA==.',
Ri='Rikiriki:BAAALgAECgUJCAAAAA==.',
Ro='Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJAgAAAA==.Ronkzar:BAAALgADCgQJCAAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Sa='Sakai:BAAALgADCgYJBgAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgQJBAAAAA==.',
Sc='Scurge:BAAALgAECgEJAQAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Setal:BAABLgAECn8VAAMJAAcJeBL4CABYAQAJAAcJeBL4CABYAQARAAEJIxHQPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAABLgAECn8gAAMXAAkJ9iNpAQCyAwAXAAkJ9iNpAQCyAwALAAYJGxjoQgB1AQAAAA==.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCAAAAA==.Sheenzilla:BAABLgAECn8cAAMJAAgJxANKDgAIAQAJAAgJxANKDgAIAQAPAAYJIQF6OACnAAAAAA==.Shelwreth:BAAALgAECgYJBgAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shoinked:BAAALgAECggJDQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgADCgUJDAAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAAALgAECgYJDwAAAA==.',
Sl='Slak:BAAALgAECgIJAgAAAA==.',
Sm='Smallchaos:BAABLgAECn8XAAIYAAYJoRTbBwAsAQAYAAYJoRTbBwAsAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgYJFwAYAKEUAA==.Smallêntropy:BAAALgAECgMJAwAAAA==.Smelt:BAAALgAECgIJBwAAAA==.Smuurfette:BAEALgAECgcJDAAAAA==.',
Sn='Snøt:BAAALgADCgYJBwAAAA==.',
So='Sokáar:BAAALgADCgYJBgAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECgcJDAACAAAAAA==.',
St='Stabbytrout:BAAALgAECggJDwAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.',
Su='Sugondis:BAABLgAFFH8IAAIVAAYJuRJsAQBQAQAVAAYJuRJsAQBQAQABLgAFFAcJEgAOANkfAA==.Sunetra:BAAALgAECgcJDwAAAA==.Sunraku:BAAALgAECgEJAgABLgAECgEJAwACAAAAAA==.Sunshine:BAAALgADCgkJFgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taloki:BAAALgADCgYJEQAAAA==.Tatsuhisa:BAAALgAECgYJBwAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAAALgAECgYJDwAAAA==.',
Ti='Tinny:BAAALgADCgcJGAAAAA==.Tippshunter:BAABLgAECn8cAAIEAAgJ3BppAQA9AgAEAAgJ3BppAQA9AgAAAA==.',
To='Toph:BAABLgAECn8aAAQRAAgJCiNTCQBMAgARAAYJ9CJTCQBMAgAPAAMJYwROPQCAAAAJAAIJvxt/HgBFAAAAAA==.Tophdh:BAABLgAECn8bAAIBAAgJUiK6AQD/AgABAAgJUiK6AQD/AgABLgAECggJGgARAAojAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECggJIwAIAL0XAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECggJIwAIAL0XAA==.Tryit:BAAALgADCgcJBQABLgAECggJIwAIAL0XAA==.Trythefox:BAABLgAECn8jAAIIAAgJvRcHBgCoAQAIAAgJvRcHBgCoAQAAAA==.',
Ts='Tseris:BAAALgAECgEJAQAAAA==.Tsukihana:BAAALgADCggJCAAAAA==.',
Tu='Tuini:BAAALgAECgYJDwAAAA==.',
Ty='Tydis:BAAALgAECgYJBwAAAA==.',
['Tá']='Tálonstorm:BAAALgAECgYJDwAAAA==.',
Ul='Ultra:BAAALgAECgEJAQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.',
Va='Vaehunt:BAAALgADCgMJAwABLgAECggJHQAQAPcdAA==.Vaesara:BAABLgAECn8dAAIQAAgJ9x2ZCwC7AQAQAAgJ9x2ZCwC7AQAAAA==.Vaestar:BAAALgAECgUJDQAAAA==.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Vani:BAAALgAECgUJEAAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwACAAAAAA==.',
Wa='Waffleiron:BAABLgAECn8UAAQGAAYJJiIcIgCDAQAGAAYJlSEcIgCDAQAUAAMJsx6DSwAKAQAZAAQJRhBwDwD/AAAAAA==.Watermelon:BAAALgADCgkJJQAAAA==.',
Wh='Whalaski:BAAALgAECgcJEwAAAA==.',
Wi='Wickedsin:BAAALgADCgYJDgAAAA==.',
Wr='Wreckitman:BAAALgAFFAIJAgAAAA==.',
Xa='Xaalath:BAAALgAECgUJCAAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIPAAgJPwhtIQBwAQAPAAgJPwhtIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECgUJCwAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.',
Yo='Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgADCgYJBgAAAA==.Zarinah:BAAALgADCgkJEQAAAA==.Zarorisk:BAAALgAECgUJCQAAAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zewse:BAAALgADCgEJAQAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAAALgAECgUJEAAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAAALgAECgcJEwAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAAALgAECgQJBgAAAA==.',
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

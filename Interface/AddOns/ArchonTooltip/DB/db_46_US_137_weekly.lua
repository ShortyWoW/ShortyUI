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

local lookup = {'Rogue-Outlaw','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Mage-Frost','Shaman-Enhancement','DeathKnight-Unholy','Priest-Discipline','Shaman-Elemental','Druid-Restoration','Monk-Brewmaster','Paladin-Holy','Priest-Holy','Evoker-Augmentation','Hunter-BeastMastery','Shaman-Restoration','Druid-Balance','Mage-Arcane','Monk-Mistweaver','Hunter-Marksmanship','Warrior-Fury','Priest-Shadow','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Devourer','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Druid-Guardian','Warrior-Arms',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acaval:BAAALgAECgUJBgABLgAECgkJHQABADsjAA==.Accursed:BAACLgAFFH8IAAICAAMJ4CNxAQA7AQACAAMJ4CNxAQA7AQAuAAQKfyIAAgIACAl4JqsAAFYDAAIACAl4JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Al='Aleighta:BAAALgAECgcJDwAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgADCgMJBAAAAA==.',
Am='Amadia:BAAALgADCgYJBQAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAAALgAECgMJBAAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgYJFAADACgYAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJCgAAAA==.Ashkillz:BAAALgAECgYJDQAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAAALgAECgcJDwAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgIJAwAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgMJAwABLgAECgUJCQAEAAAAAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIFAAYJ9CAGAwDmAQAFAAYJ9CAGAwDmAQAuAAQKfxoAAgUACAn8IjoRAAYDAAUACAn8IjoRAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBQABLgAECgkJJQAGAGgaAA==.Belan:BAABLgAECn8YAAIHAAgJuhFpTwB8AQAHAAgJuhFpTwB8AQAAAA==.Belladin:BAABLgAECn8gAAIFAAkJ0x/RHgCyAgAFAAkJ0x/RHgCyAgAAAA==.',
Bl='Blameurself:BAAALgAECgcJCgAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgcJCgAEAAAAAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgADCgcJDgAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8YAAIIAAUJcxBpEAD6AAAIAAUJcxBpEAD6AAAAAA==.Bonelespizza:BAACLgAFFH8HAAIJAAIJOQr4egCYAAAJAAIJOQr4egCYAAAuAAQKfzAAAgkACQmHHjocAB8CAAkACQmHHjocAB8CAAAA.Boogiebabe:BAAALgAECgYJBgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAABLgAECn8ZAAIGAAgJsRtWCABlAgAGAAgJsRtWCABlAgAAAA==.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJEgAJAMYbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn8YAAICAAYJjh6XBQCyAQACAAYJjh6XBQCyAQAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgADCgUJBQAAAA==.Casteel:BAAALgAECggJDAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAUJEAAKAMESAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAAALgAECgUJEAAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAAALgAECgUJCQAAAA==.Cosmicjay:BAEBLgAECn8WAAILAAgJQR+CBgB9AgALAAgJQR+CBgB9AgAAAA==.Cosmicnova:BAEALgAECgYJDAABLgAECggJFgALAEEfAA==.Costa:BAAALgAECgEJAQAAAA==.',
Cr='Crentacles:BAABLgAECn8WAAILAAgJ3xPiEwC3AQALAAgJ3xPiEwC3AQAAAA==.Critshade:BAAALgAECgYJDAAAAA==.Crow:BAAALgAFFAUJEgAAAQ==.',
Da='Daffodil:BAAALgAECgcJEwAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8KAAIMAAQJSAu6HADxAAAMAAQJSAu6HADxAAAuAAQKfx8AAgwACQl+HEcdAFMCAAwACQl+HEcdAFMCAAAA.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Dawnslight:BAAALgAECgQJCgAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgADCgIJAgAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGgANAFgfAA==.Dephiance:BAAALgAECgEJAQABLgAECggJGwAKAHQQAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8VAAIOAAYJeCTPFwBTAgAOAAYJeCTPFwBTAgAAAA==.Dinsfirë:BAAALgADCgMJAwAAAA==.Diothorn:BAAALgAECgYJEQAAAA==.Divanas:BAAALgAECgYJCQAAAA==.Divi:BAABLgAECn8UAAIPAAYJSyTpBwByAgAPAAYJSyTpBwByAgAAAA==.',
Do='Doxa:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAAALgAECgYJEwAAAA==.Drpepperz:BAAALgAECgcJCwAAAA==.',
Du='Durock:BAAALgADCgQJBAABLgAECgYJCwAEAAAAAA==.Dusk:BAAALgAECgEJAQABLgAECgEJAgAEAAAAAA==.',
Dy='Dymondsmashr:BAABLgAECn8aAAIOAAcJMQhYLAAtAQAOAAcJMQhYLAAtAQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Ensetral:BAAALgADCgQJBAAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgUJBQAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Everydae:BAACLgAFFH8FAAIQAAMJEAt/LACYAAAQAAMJEAt/LACYAAAuAAQKfyYAAhAACQnTH6UDANUCABAACQnTH6UDANUCAAAA.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgcJDQAEAAAAAA==.',
Fa='Fakedruid:BAAALgAECgcJDgABLgAECgkJJQAGAGgaAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feledris:BAAALgADCgYJBgAAAA==.Feybeasts:BAAALgADCgcJDAAAAA==.Feárbomber:BAAALgADCgcJDgABLgAECgYJGgANAKYkAA==.',
Ff='Ffand:BAABLgAECn8WAAIRAAYJ5x9LIgDPAQARAAYJ5x9LIgDPAQAAAA==.',
Fh='Fharia:BAAALgADCgQJBAAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flayr:BAAALgADCgQJBAAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgUJBQAAAA==.',
Fu='Fusky:BAABLgAECn8VAAISAAgJUwtJNgAxAQASAAgJUwtJNgAxAQAAAA==.',
Fy='Fynn:BAACLgAFFH8IAAIIAAMJ3w1HBQDxAAAIAAMJ3w1HBQDxAAAuAAQKfyAAAwgACAnFFwsLABwCAAgACAnFFwsLABwCABIAAQmjAYGpACQAAAAA.',
Ga='Galadria:BAABLgAFFH8IAAITAAMJeguWGQDZAAATAAMJeguWGQDZAAAAAA==.Ganeda:BAAALgAECgUJBQABLgAECgYJCwAEAAAAAA==.',
Ge='Gerwik:BAABLgAECn8WAAIRAAYJ0xXWPQBWAQARAAYJ0xXWPQBWAQAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAAALgADCgMJAwAAAA==.',
Gr='Greenleaves:BAAALgAECgcJEQAAAA==.Greenpepperz:BAAALgADCgIJAgAAAA==.Gregsh:BAABLgAECn8aAAMHAAgJGwoqTQCCAQAHAAgJGwoqTQCCAQAUAAEJ6APTIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAAALgAECgYJEAAAAA==.',
Ha='Hailin:BAABLgAECn8nAAIFAAkJ5xn1FQBLAgAFAAkJ5xn1FQBLAgAAAA==.Halrem:BAAALgAECgEJAQAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAAALgAECgYJDgAAAA==.',
He='Hellman:BAAALgADCgUJCQAAAA==.',
Hi='Hightroller:BAABLgAECn8fAAIRAAgJFBAFKwCkAQARAAgJFBAFKwCkAQAAAA==.Hima:BAABLgAECn8UAAIDAAYJKBjgEQBrAQADAAYJKBjgEQBrAQAAAA==.',
Ho='Holysathh:BAAALgAECgUJDgABLgAECgYJCwAEAAAAAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Homulily:BAAALgADCgcJFAAAAA==.Hornggry:BAAALgAECgQJAwABLgAECgcJFgANALwcAA==.Horngrry:BAAALgAECgQJCAABLgAECgcJFgANALwcAA==.Horngryerr:BAABLgAECn8WAAINAAcJvBzcIwDjAQANAAcJvBzcIwDjAQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECgcJFgANALwcAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJAwABLgAECggJJQAVAI0ZAA==.',
Hu='Huntingpants:BAABLgAECn8VAAIWAAcJpw1lCwA4AQAWAAcJpw1lCwA4AQAAAA==.',
Il='Ilovebagels:BAAALgADCgYJBgAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECgcJFgANALwcAA==.',
In='Inspiredbox:BAAALgAECgMJBAAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn8XAAIVAAYJsg8qKgD9AAAVAAYJsg8qKgD9AAAAAA==.Jayy:BAABLgAECn8aAAIGAAcJ+Q2WEgCKAQAGAAcJ+Q2WEgCKAQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAcJFwAXANkfAA==.Jenny:BAABLgAECn8hAAIFAAYJohh/TABgAQAFAAYJohh/TABgAQAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgQJBgAAAA==.',
Ju='Junieb:BAAALgAECgcJEAAAAA==.',
Ka='Kachiko:BAAALgADCggJDgAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAAALgAFFAEJAQAAAA==.Kamerth:BAABLgAECn8UAAMKAAcJGQU0JgD3AAAKAAcJGQU0JgD3AAAYAAYJcgaTLADpAAAAAA==.Kapnkrunch:BAAALgADCgcJGAAAAA==.Karluron:BAAALgAECggJDwAAAA==.Karlutros:BAABLgAECn8dAAIYAAgJ8hFbEgC1AQAYAAgJ8hFbEgC1AQAAAA==.Katowo:BAAALgAECgQJBQABLgAFFAUJCwAZAJAlAA==.Katuwuagain:BAABLgAFFH8LAAIZAAUJkCUdAwC1AQAZAAUJkCUdAwC1AQAAAA==.Kazure:BAABLgAECn8lAAIaAAkJAgovHgCQAQAaAAkJAgovHgCQAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn8tAAIXAAkJYQzyEgDWAQAXAAkJYQzyEgDWAQAAAA==.Keybricker:BAAALgAECgcJDwABLgAECgkJJQAGAGgaAA==.',
Kh='Khaôtic:BAABLgAECn8WAAIbAAYJMBiKNgBcAQAbAAYJMBiKNgBcAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAAALgAECgcJEwAAAA==.Kittykat:BAAALgAECgEJAQAAAA==.',
Ko='Korngry:BAAALgADCgMJAwABLgAECgcJFgANALwcAA==.',
Kr='Krakkin:BAAALgADCgYJDQAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJEgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgADCgMJAwABLgAECgcJFgANALwcAA==.',
Ky='Kyllea:BAAALgAECgYJDgAAAA==.',
['Kä']='Kätniss:BAAALgADCgcJBwAAAA==.',
La='Laaksy:BAABLgAECn8eAAIcAAgJfhDDBQB8AQAcAAgJfhDDBQB8AQAAAA==.Ladraina:BAAALgADCggJCgAAAA==.Landock:BAAALgADCgYJEgAAAA==.Lavaca:BAABLgAECn8dAAQBAAkJOyNeAQBwAgAdAAgJwSF+CQD5AgABAAYJqCJeAQBwAgAeAAYJIR+RBADIAQAAAA==.',
Le='Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAABLgAECn8pAAIMAAgJuxDoLQBsAQAMAAgJuxDoLQBsAQAAAA==.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJCQAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgQJCwAAAA==.Lotharmage:BAAALgAECgYJCwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAECgYJBwAAAA==.',
Ma='Magnessa:BAAALgAFFAEJAQAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgADCgMJAwAAAA==.Marist:BAAALgAECgcJEAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.',
Me='Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8UAAIfAAYJpRsZDgCBAQAfAAYJpRsZDgCBAQAAAA==.Miku:BAAALgAECgYJBgABLgAECgkJJwAFAOcZAA==.Milent:BAABLgAECn8bAAIRAAcJBhX4NwBtAQARAAcJBhX4NwBtAQAAAA==.Miquiztli:BAAALgAECgkJAQAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJAgAAAA==.',
Mo='Moarteas:BAAALgADCgQJAgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8WAAQgAAYJxhujBQBqAQAgAAYJaBqjBQBqAQAhAAMJdBbehAC8AAAiAAIJ/hTOJQA9AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJCgAAAA==.',
Mx='Mximus:BAAALgADCgEJAQABLgAECgIJAwAEAAAAAA==.',
My='Mystí:BAAALgAECggJDQAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJKQAKAEQfAA==.Nabstarr:BAABLgAECn8pAAMKAAkJRB/gAQBKAwAKAAkJRB/gAQBKAwAPAAEJRgOPhQArAAAAAA==.Namtar:BAAALgAECgEJAQAAAA==.Nasroth:BAABLgAECn8kAAIXAAcJAhLYPACxAQAXAAcJAhLYPACxAQAAAA==.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Nightthane:BAAALgADCgkJHAAAAA==.Niibyter:BAABLgAECn8WAAIfAAcJmBrNCQDWAQAfAAcJmBrNCQDWAQAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgEJAQABLgAECgIJAwAEAAAAAA==.',
Od='Odînson:BAAALgADCgUJBQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMMAAYJ2RC5RgD4AAAMAAYJ2RC5RgD4AAATAAYJcgo8KgDyAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8bAAMhAAYJixSJSABPAQAhAAYJNROJSABPAQAiAAUJFRB1KgAXAQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAAALgAECgcJEgAAAA==.',
Or='Orangedrives:BAAALgADCgUJBwAAAA==.Oreeoreo:BAABLgAECn8fAAIJAAgJIxF4TQBTAQAJAAgJIxF4TQBTAQAAAA==.Orlis:BAABLgAECn8aAAIPAAgJUBHLFgCcAQAPAAgJUBHLFgCcAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgIJAwAAAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAAALgAECggJEAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJDAABLgAECggJDQAEAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8hAAMaAAgJ7xcGBwAKAgAaAAgJ7xcGBwAKAgAQAAYJYhQZIABAAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAECggJGQAGALEbAA==.',
Pl='Plumh:BAAALgADCgIJAgAAAA==.Pläze:BAAALgAECgYJDAAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgcJDQAAAA==.',
Pr='Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAIjAAgJpBM4EgCkAQAjAAgJpBM4EgCkAQAAAA==.',
Py='Pyronorish:BAAALgADCgYJEgAAAA==.Pytthia:BAABLgAECn8bAAMKAAgJdBAaGQBqAQAKAAcJCBIaGQBqAQAYAAcJfg8CHQBUAQAAAA==.',
['Pä']='Pändamonium:BAAALgADCgcJBQAAAA==.',
Qu='Quicknclever:BAAALgADCgMJAwAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Rayquaza:BAAALgAECgcJDgABLgAFFAcJEgAEAAAAAA==.Raziel:BAABLgAECn8RAAIbAAgJSRk1NAAoAgAbAAgJSRk1NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAQJBwAkAOQCAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAABLgAECn8WAAIFAAgJkQpPTABgAQAFAAgJkQpPTABgAQAAAA==.',
Ri='Rikiriki:BAAALgAECgYJEgAAAA==.',
Ro='Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJBQAAAA==.Ronkzar:BAAALgADCgQJCgAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Ruth:BAAALgAECgYJDAAAAA==.',
Sa='Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgUJBQAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Sarlaana:BAAALgAECgEJAQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgUJCQAAAA==.',
Sc='Scurge:BAAALgAECgIJAwAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Setal:BAABLgAECn8dAAMQAAgJ8xavDQDyAQAQAAgJ8xavDQDyAQAcAAEJIxHYPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8IAAILAAQJVhQiDwA0AQALAAQJVhQiDwA0AQAuAAQKfyMAAwsACQn2I2wBALIDAAsACQn2I2wBALIDABIABgkbGOVCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCAAAAA==.Sheenzilla:BAABLgAECn8jAAMQAAgJGwV+JwATAQAQAAgJGwV+JwATAQAaAAYJIQF+OACnAAAAAA==.Shelltear:BAAALgADCgYJBgAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shoinked:BAABLgAECn8rAAILAAgJlgw2HQBkAQALAAgJlgw2HQBkAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgADCgcJFwAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn8aAAINAAYJpiTWCwAEAgANAAYJpiTWCwAEAgAAAA==.',
Sl='Slak:BAAALgAECggJCgAAAA==.',
Sm='Smallchaos:BAABLgAECn8eAAIDAAcJwBGuEwBRAQADAAcJwBGuEwBRAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgADAMARAA==.Smallêntropy:BAAALgAECgYJDwAAAA==.Smelt:BAAALgAECgIJCgAAAA==.Smuurfette:BAEALgAECgcJDQAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgEJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECgcJDQAEAAAAAA==.',
St='Stabbytrout:BAABLgAECn8VAAIdAAkJKhcmDQDPAQAdAAkJKhcmDQDPAQAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIjAAYJtBKkCABAAQAjAAYJtBKkCABAAQAuAAQKfxUAAiMACQn1IXAGABkDACMACQn1IXAGABkDAAEuAAUUBwkXABcA2R8A.Sunetra:BAAALgAECgcJEAAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAAALgAECgEJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgAEAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taehyung:BAAALgAECgcJBwAAAA==.Taloki:BAAALgADCgYJGgAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECgcJCwAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8aAAMSAAYJuganUwCvAAASAAUJAAWnUwCvAAALAAYJBwMnQACpAAAAAA==.',
Ti='Tinny:BAAALgAECgEJAgAAAA==.Tippshunter:BAABLgAECn8lAAIGAAkJaBquBAB2AgAGAAkJaBquBAB2AgAAAA==.',
To='Tonton:BAAALgADCgUJBQAAAA==.Toph:BAACLgAFFH8HAAMcAAMJVxwdAwAJAQAcAAMJvBgdAwAJAQAQAAEJFyHkHgBbAAAuAAQKfx4ABBwACQmwIVQJAEwCABwABwkqIVQJAEwCABoAAwljBE09AIAAABAAAgnGGwJUAEoAAAAA.Tophdh:BAABLgAECn8eAAICAAgJOSO6AQD/AgACAAgJOSO6AQD/AgABLgAFFAMJBwAcAFccAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECggJIwANAMUXAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECggJIwANAMUXAA==.Tryit:BAAALgAECgQJBAABLgAECggJIwANAMUXAA==.Trythefox:BAABLgAECn8jAAINAAgJxRceFACcAQANAAgJxRceFACcAQAAAA==.',
Ts='Tseris:BAAALgAECgMJBgAAAA==.Tsukihana:BAAALgADCggJCAAAAA==.',
Tu='Tuini:BAABLgAECn8VAAMSAAcJMRvBEwAXAgASAAcJMRvBEwAXAgALAAEJ4QC6lwAXAAAAAA==.',
Ty='Tydis:BAABLgAECn8cAAIFAAgJqwlGTgBbAQAFAAgJqwlGTgBbAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn8aAAIlAAYJeQXXIgDWAAAlAAYJeQXXIgDWAAAAAA==.',
Ul='Ultra:BAAALgAECgEJAQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCQAAAA==.',
Va='Vaehunt:BAAALgADCgMJBAABLgAFFAQJCgAbAE4QAA==.Vaesar:BAAALgADCgMJAwABLgAFFAQJCgAbAE4QAA==.Vaesara:BAACLgAFFH8KAAIbAAQJThByIgAlAQAbAAQJThByIgAlAQAuAAQKfyMAAhsACQm/HbIgAMQBABsACQm/HbIgAMQBAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Vani:BAABLgAECn8VAAIPAAUJCQ7yKwDtAAAPAAUJCQ7yKwDtAAAAAA==.',
Ve='Velora:BAAALgAECgMJAwAAAA==.',
Vi='Vilthrax:BAAALgAECgQJBAAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwAAAA==.Waffleiron:BAABLgAECn8XAAQKAAYJyyIaIgCDAQAKAAYJyyIaIgCDAQAPAAMJsx6QSwAKAQAYAAQJKRAcKgD4AAAAAA==.Watermelon:BAAALgAECgUJCAABLgAECgYJBQAEAAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8fAAIRAAgJZRC8KACuAQARAAgJZRC8KACuAQAAAA==.',
Wi='Wickedsin:BAAALgAECgYJCwAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8LAAIMAAUJNg97DwBZAQAMAAUJNg97DwBZAQAuAAQKfxgAAgwACAk7HuAJAKsCAAwACAk7HuAJAKsCAAAA.',
Xa='Xaalath:BAAALgAECgYJEwAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIaAAgJSwhuIQBwAQAaAAgJSwhuIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECgYJEAAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.',
Yo='Yobaz:BAAALgADCgUJBwAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarinah:BAAALgAECgEJAQAAAA==.Zarorisk:BAAALgAECgUJCQAAAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgADCgEJAQAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8WAAIGAAYJFRd0EgCbAQAGAAYJFRd0EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIFAAgJXxpuOQCaAQAFAAgJXxpuOQCaAQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAAALgAECgYJEwAAAA==.',
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

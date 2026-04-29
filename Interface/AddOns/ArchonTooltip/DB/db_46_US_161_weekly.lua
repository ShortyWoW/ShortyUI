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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Mage-Arcane','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Druid-Restoration','Paladin-Holy','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Priest-Discipline','DeathKnight-Unholy','Priest-Shadow','Druid-Feral','Druid-Guardian','Druid-Balance','DemonHunter-Havoc','Mage-Fire','DeathKnight-Blood',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aandra:BAABLgAECn8cAAQBAAgJ1h7mFwDFAgABAAgJax7mFwDFAgACAAIJGxY/HACRAAADAAEJBAPxfQAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJBgAAAA==.',
Ad='Adelyy:BAAALgADCgEJAQAAAA==.',
Ae='Aeliena:BAAALgADCgYJFAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8XAAIEAAYJRRmucACbAQAEAAYJRRmucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJBwAAAA==.',
Al='Alerion:BAAALgAECgcJDwAAAA==.Allan:BAABLgAECn8cAAIFAAgJ8RxLAgB8AgAFAAgJ8RxLAgB8AgAAAA==.',
Am='Amaneeda:BAAALgAECgYJEAAAAA==.Amazonia:BAAALgADCgcJEgAAAA==.Amphi:BAAALgADCgMJAwABLgAECgQJBgAGAAAAAA==.Amphibibi:BAAALgAECgQJBgAAAA==.Amphoo:BAAALgADCgIJAgAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAABLgAECn8UAAIHAAUJ7CMfAgCfAQAHAAUJ7CMfAgCfAQAAAA==.Antagonis:BAAALgAECgUJCAAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgcJBwAAAA==.',
Ar='Arganos:BAABLgAECn8fAAIIAAgJgiY7AAAaAwAIAAgJgiY7AAAaAwAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAAALgAECgUJCQAAAA==.Artherus:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgYJBgAAAA==.Atheìst:BAABLgAECn8aAAIJAAgJESXNAQBaAwAJAAgJESXNAQBaAwAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn8fAAMKAAcJUB18JQD+AQAKAAcJUB18JQD+AQALAAIJbRCdJQA9AAAAAA==.',
Au='Aurite:BAAALgAFFAQJCwAAAQ==.',
Av='Aveldea:BAAALgAECgcJDQAAAA==.Aventon:BAAALgADCggJCwABLgAECggJHwAIAIImAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAAALgAECgUJCgAAAA==.',
Ba='Baconlittle:BAAALgAECgYJEgAAAA==.Baelanoth:BAAALgAECgQJBwAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECgcJBwAAAA==.Bammbamm:BAAALgAECgYJEwAAAA==.Banewreak:BAABLgAECn8aAAIBAAcJHRMwXgCuAQABAAcJHRMwXgCuAQAAAA==.Banu:BAAALgADCgEJAQAAAA==.Baradin:BAAALgADCgUJBQAAAA==.Barind:BAABLgAECn8cAAQMAAgJshh9BACfAQANAAcJIxoLJQD9AQAMAAcJtQ99BACfAQAOAAIJuRrRnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Betrayer:BAAALgAECgQJBgAAAA==.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJCQAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDAABLgADCgYJCwAGAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAGAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgQJBAAAAA==.',
['Bú']='Búbblés:BAAALgAECgUJBwAAAA==.',
Ca='Caatia:BAAALgADCggJCAAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgYJHAABAOMXAA==.Carthel:BAABLgAECn8fAAIPAAgJICD0AgCjAgAPAAgJICD0AgCjAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCgYJBgAAAA==.',
Ch='Chasseresse:BAAALgADCgcJDQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chimarr:BAEBLgAECn8cAAIQAAgJEiIOAQD6AgAQAAgJEiIOAQD6AgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAAALgAECgcJCgAAAA==.',
Cr='Crackmonkéy:BAAALgAECgYJDwAAAA==.Cranknspank:BAAALgADCgUJBQAAAA==.Cronoz:BAABLgAECn8VAAMKAAYJfAjXWQAhAQAKAAYJfAjXWQAhAQALAAYJ2AWIUwD3AAAAAA==.Crotchshot:BAAALgAECgMJBAAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAABLgAECn8mAAIBAAgJJx/TAgBxAgABAAgJJx/TAgBxAgAAAA==.',
['Có']='Cózmik:BAAALgAECgQJCgAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAAALgAECgYJCAAAAA==.Dalya:BAAALgADCgcJCQAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAQAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgMJBAAAAA==.',
De='Deathnorris:BAAALgAECgEJAQAAAA==.Dekard:BAAALgAECgcJDAAAAA==.Dekariusly:BAAALgADCgUJCgABLgAECgcJDAAGAAAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgIJAwAGAAAAAA==.Destinÿ:BAAALgAECgYJEwAAAA==.Devourer:BAAALgAECgYJEwAAAA==.',
Di='Disploder:BAAALgAECgIJAwAAAA==.Dist:BAAALgAECgYJAwAAAA==.',
Do='Doctafuzz:BAAALgAECgEJAQAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQAAAA==.Dreathhammer:BAABLgAECn8WAAIRAAgJmx/RFgBbAgARAAgJmx/RFgBbAgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAQJDAARAMAjAA==.',
Du='Dunadin:BAAALgAECgUJCAABLgAECgYJFgAHAPUkAA==.Dundyrn:BAABLgAECn8WAAIHAAYJ9SQjAQAAAgAHAAYJ9SQjAQAAAgAAAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAMJBwASAEIUAA==.',
El='Elememetal:BAABLgAECn8eAAILAAgJzxdOBQDGAQALAAgJzxdOBQDGAQAAAA==.',
En='Enigmä:BAAALgADCgkJCQAAAA==.',
Fa='Faultless:BAAALgADCggJDQAAAA==.',
Fe='Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8UAAIKAAcJ9gc6WQAjAQAKAAcJ9gc6WQAjAQAAAA==.Fenix:BAAALgADCgEJAQAAAA==.',
Fi='Filbert:BAAALgAECgYJDAAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Fomy:BAAALgAECgEJAQAAAA==.',
Fr='Frostynaps:BAAALgAECgYJCQAAAA==.',
['Fá']='Fálola:BAABLgAECn8jAAIKAAgJoBPhKADsAQAKAAgJoBPhKADsAQAAAA==.',
Ga='Gamblex:BAAALgAECgMJBAAAAA==.Garviel:BAAALgAECgMJCAAAAA==.',
Ge='Geethatlock:BAAALgAECgQJCAAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAAALgAECgEJAQAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Gorgonzolas:BAAALgAECgQJBAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAAALgAECgYJCgAAAA==.Grogu:BAAALgAECgUJCgAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.',
Gu='Gundyr:BAAALgADCgkJHgAAAA==.',
He='Helkyrie:BAAALgADCgcJHAAAAA==.Helleer:BAAALgADCgQJBAAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hiksham:BAAALgAECgYJDQAAAA==.',
Ho='Holycheeze:BAAALgADCgQJBAAAAA==.Holyhoof:BAAALgADCgMJAwAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgYJHAABAOMXAA==.Hotsanddots:BAAALgAECgEJAQAAAA==.',
Hu='Huuan:BAAALgADCgIJAwABLgAECgUJDAAGAAAAAA==.',
Ih='Ihealzufool:BAAALgAECgQJCgAAAA==.',
Im='Imded:BAAALgAECgQJBAAAAA==.',
Ja='Jalene:BAAALgAECgUJCgAAAA==.Jargyn:BAAALgAECgYJDQAAAA==.Jarlyss:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Javieraa:BAABLgAECn8YAAITAAgJcBj7DACqAQATAAgJcBj7DACqAQAAAA==.',
Jd='Jdai:BAAALgAECgUJDAAAAA==.',
Ju='Juglight:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Kh='Khaiv:BAACLgAFFH8NAAITAAQJBiE5AwB3AQATAAQJBiE5AwB3AQAuAAQKfy4AAhMACQm7IjMBANYCABMACQm7IjMBANYCAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAAALgAECgYJEwAAAA==.Kimmi:BAAALgADCgUJCgAAAA==.Kinzen:BAABLgAECn8eAAIUAAcJFxuwCQA6AgAUAAcJFxuwCQA6AgAAAA==.',
Ku='Kulthosano:BAAALgAECgUJDAAAAA==.',
La='Labubu:BAAALgAECgYJCwAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgADCgEJAQABLgAECgYJFQAVAB0VAA==.',
Le='Lechwe:BAAALgAECgQJDAAAAA==.Legonator:BAAALgADCgcJCwAAAA==.',
Li='Lichmajor:BAABLgAECn8cAAIWAAgJihmMBwAHAgAWAAgJihmMBwAHAgAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAAALgAECgUJDAAAAA==.Lovepet:BAABLgAECn8WAAMOAAYJpAxEGQAyAQAOAAYJQgtEGQAyAQANAAYJCQdXUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgADCgYJBgAAAA==.',
Lu='Lunal:BAABLgAECn8gAAIPAAgJfR/eKgDHAgAPAAgJfR/eKgDHAgAAAA==.',
Ly='Lyda:BAAALgAECgYJEwAAAA==.',
Ma='Magice:BAAALgAECgMJBAAAAA==.Malibubarbie:BAAALgAECgUJEgAAAA==.Maneevent:BAAALgAECgYJCwAAAA==.Materesa:BAABLgAECn8VAAMVAAYJHRVVCABeAQAVAAYJHRVVCABeAQAXAAYJbgzmNQA8AQAAAA==.Maysty:BAABLgAECn8VAAIOAAYJmwYWJgDUAAAOAAYJmwYWJgDUAAAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8LAAMYAAQJchpzAABzAQAYAAQJ8RlzAABzAQAZAAEJhxPlBgA6AAAuAAQKfxsAAxgACAkvJPoBAD8DABgACAkvJPoBAD8DABkAAQkxIYcpAFQAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8bAAIJAAcJiQ1nCQBmAQAJAAcJiQ1nCQBmAQAAAA==.',
Mi='Midnightstar:BAAALgAECgEJAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.',
Mo='Monika:BAAALgAECgIJAgAAAA==.Moonbayne:BAABLgAECn8UAAIaAAcJaBidHQATAgAaAAcJaBidHQATAgAAAA==.Mooszer:BAAALgAECgMJBwAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgEJAQAAAA==.Mushu:BAAALgAECggJDAAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgADCggJDgAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJBgAAAA==.',
Ne='Nepharim:BAAALgADCgkJCQAAAA==.Nephlim:BAACLgAFFH8MAAIWAAQJRBrgEQBaAQAWAAQJRBrgEQBaAQAuAAQKfyQAAhYACQl/IJ8GAG4DABYACQl/IJ8GAG4DAAAA.',
Ni='Ninobrown:BAAALgAECgUJCwAAAA==.Ninzerp:BAAALgADCgIJAwABLgAECggJIAAPAH0fAA==.Nizano:BAAALgAECgUJCQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJBgAGAAAAAA==.Noryaa:BAAALgAECgYJCgAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.',
Nu='Nuadå:BAAALgAECgUJCgAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgQJBgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAAALgAECgMJBAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAEALgADCgEJAQABLgAECggJHAAQABIiAA==.',
Po='Pogo:BAABLgAECn8cAAIMAAgJXyNoAAC9AgAMAAgJXyNoAAC9AgAAAA==.Pogolock:BAAALgADCgEJAQABLgAECggJHAAMAF8jAA==.',
Pr='Prozac:BAAALgAECgMJBgAAAA==.',
Ps='Psiberian:BAAALgAECgYJCwAAAA==.',
Re='Redmage:BAAALgADCgYJCQABLgAECgYJFgAOAKQMAA==.Redrocket:BAAALgADCgYJBgAAAA==.Remixed:BAAALgAECgMJAwAAAA==.',
Ri='Rikaku:BAABLgAECn8ZAAIOAAcJTRHjPgCzAQAOAAcJTRHjPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgMJAwAGAAAAAA==.Rosemery:BAAALgADCgkJFgAAAA==.',
['Rä']='Räpodac:BAAALgAECgUJDgAAAA==.',
Sa='Sagaba:BAAALgAECgEJAQAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAABLgAECn8aAAIWAAcJrB7pQAA1AgAWAAcJrB7pQAA1AgAAAA==.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Sefiroth:BAABLgAECn8VAAITAAcJBQqLcwBLAQATAAcJBQqLcwBLAQAAAA==.Selillea:BAAALgADCgMJAwAAAA==.Semarius:BAAALgADCgkJCgABLgAECgYJFgAbAGQhAA==.Semdorii:BAABLgAECn8WAAIbAAYJZCFFEwA8AgAbAAYJZCFFEwA8AgAAAA==.Sephywrath:BAABLgAECn8eAAIcAAgJKxdVAAAYAgAcAAgJKxdVAAAYAgAAAA==.Seralith:BAAALgAECgYJDgAAAA==.Seranight:BAABLgAECn8gAAIdAAcJ3SL1AQAQAgAdAAcJ3SL1AQAQAgAAAA==.Seven:BAAALgAECgIJAwABLgAECgYJHAABAOMXAA==.Sevenpaws:BAAALgAECgEJAQABLgAECggJGgAJABElAA==.',
Sh='Shadowchi:BAAALgADCgcJDQAAAA==.Shaidon:BAAALgADCgkJEAAAAQ==.Shaly:BAAALgAECgYJCwAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shirohige:BAAALgAECgMJBAAAAA==.Shylan:BAAALgAECgIJAgAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgEJAgABLgAECgMJBQAGAAAAAA==.',
Sn='Snayre:BAABLgAECn8VAAIMAAcJWxREBACnAQAMAAcJWxREBACnAQAAAA==.Snipêr:BAAALgADCgYJBgAAAA==.Snowlia:BAABLgAECn8WAAIKAAcJyBPsNQCrAQAKAAcJyBPsNQCrAQAAAA==.',
So='Soularis:BAAALgAECgIJAgAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECgcJFwAEAEUZAA==.Spybro:BAAALgAECgIJAwAAAA==.',
Sq='Squidtechnic:BAAALgAECgMJBQAAAA==.',
St='Stalkingwolf:BAAALgAECgUJCgAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgADCgIJAgAAAA==.',
Sy='Sylailia:BAABLgAECn8VAAIaAAcJ6xQVCAB0AQAaAAcJ6xQVCAB0AQAAAA==.Syleta:BAAALgADCgMJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgEJAQAAAA==.',
Tc='Tcon:BAAALgAECgYJDAAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8XAAMaAAYJAR7wCABiAQAaAAYJAR7wCABiAQAYAAEJSBmsMwAzAAAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJEQAAAA==.',
Ti='Tiarcis:BAAALgAECgcJDwAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAAALgAECgUJCAAAAA==.',
Tr='Treesummoner:BAABLgAECn8aAAQDAAgJIRNxLAAMAQADAAUJ6wpxLAAMAQABAAcJrxJkKQDpAAACAAMJoQvSGgCgAAAAAA==.Tritanks:BAABLgAECn8YAAIHAAYJuR8fBwAZAgAHAAYJuR8fBwAZAgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCgcJEgAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAGAAAAAA==.',
Un='Unbantam:BAAALgADCgcJBwAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAAALgAECgQJCQAAAA==.Vasilia:BAAALgAECgYJEwAAAA==.',
Ve='Velanna:BAAALgADCggJBAAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.',
Vo='Voclus:BAAALgAECgIJAwAAAA==.',
Wa='Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgADCgQJBAAAAA==.',
Wi='Wightranger:BAAALgADCgYJBgAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgQJBAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgIJAgAAAA==.Xiles:BAAALgAECgUJCQAAAA==.',
Za='Zachxd:BAABLgAECn8cAAITAAcJ6RZxGQA1AQATAAcJ6RZxGQA1AQABLgAECgcJGgAWAKweAA==.Zanthe:BAAALgAECgMJBAAAAA==.Zapanese:BAAALgADCgIJAgAAAA==.Zaptism:BAABLgAECn8YAAMJAAgJ5BtcCwCaAgAJAAgJ5BtcCwCaAgAVAAMJSA0qQgCiAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanfury:BAAALgAECgcJCQABLgAECgUJFAAHAOwjAA==.',
Zi='Zinder:BAAALgAECgYJEAAAAA==.Zipit:BAABLgAECn8cAAIDAAgJlxRBAQC+AQADAAgJlxRBAQC+AQAAAA==.',
Zy='Zyae:BAAALgAECgEJAQAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgYJDQAGAAAAAA==.',
['Öb']='Öboron:BAABLgAECn8kAAQNAAgJtRKOKgDUAQANAAgJVhCOKgDUAQAOAAYJKRU1UwBvAQAMAAcJ8QhBFwBXAQAAAA==.',
['Üz']='Üz:BAAALgAECgYJDAAAAA==.',
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

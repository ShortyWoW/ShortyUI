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

local lookup = {'Monk-Mistweaver','Priest-Holy','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Warrior-Protection','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Priest-Shadow','Priest-Discipline','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Paladin-Holy','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Hunter-BeastMastery','DemonHunter-Vengeance','Hunter-Marksmanship',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ae='Aeralina:BAAALgADCgEJAQAAAA==.Aerandir:BAAALgAECgYJDwAAAA==.',
Ah='Ahmyra:BAAALgAECgYJBgAAAA==.',
Al='Allysson:BAAALgAECgYJDwAAAA==.Alyestra:BAAALgADCgkJKgAAAA==.',
An='Animyst:BAABLgAECn8fAAIBAAcJoh11EABVAgABAAcJoh11EABVAgABLgAECggJGgACACohAA==.Aniron:BAAALgAECgYJCgABLgAECggJGgACACohAA==.Anirot:BAABLgAECn8aAAICAAgJKiEABwDdAgACAAgJKiEABwDdAgAAAA==.',
Ar='Aranta:BAAALgAECgUJCAAAAA==.',
As='Astren:BAAALgADCgYJBgAAAA==.Asynsia:BAABLgAECn8cAAIDAAgJsB+yEAD5AgADAAgJsB+yEAD5AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Banashain:BAAALgADCgEJAgAAAA==.Bartholomew:BAAALgAECgcJDwAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn8WAAICAAYJJyZQAQCVAgACAAYJJyZQAQCVAgAAAA==.',
Bl='Bladez:BAAALgAECgEJAQAAAA==.',
Bo='Boombawks:BAAALgADCgUJBQABLgADCgYJAgAEAAAAAA==.Boryndin:BAAALgAECgUJCwAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAABLgAECn8rAAIFAAgJbRc1OgA6AgAFAAgJbRc1OgA6AgAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.',
Ch='Cherypoptart:BAAALgAECgYJDAAAAA==.Chrismeister:BAAALgADCgMJBAAAAA==.',
Co='Codah:BAAALgADCgQJDAAAAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crettephal:BAAALgAECgEJAQAAAA==.',
['Cä']='Cähira:BAAALgADCgUJBQABLgADCgYJCQAEAAAAAA==.',
Da='Daellan:BAAALgAECgMJAwAAAA==.Daisia:BAAALgAECgUJCwAAAA==.Dalarrong:BAAALgADCgYJBgAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgADCgUJCQAAAA==.Demonicadhd:BAAALgAECgYJDAAAAA==.Demonsmind:BAAALgAECgYJDgAAAA==.Derien:BAABLgAECn8WAAIGAAgJThTmEAD6AQAGAAgJThTmEAD6AQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Dezin:BAAALgADCgUJBQAAAA==.',
Do='Donkeyteeth:BAAALgAECgYJEgAAAA==.Downtownbuu:BAAALgADCgEJAQAAAA==.',
Dr='Dracorz:BAAALgAECgUJCgAAAA==.Drywater:BAAALgAECgYJDQAAAA==.',
Du='Dura:BAAALgAECgUJDQAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn8WAAIHAAYJ9gq/BQDmAAAHAAYJ9gq/BQDmAAAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn8gAAMIAAgJ0QliGwA8AQAIAAgJ0QliGwA8AQAJAAEJJwJiTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erilana:BAAALgADCgkJDgAAAA==.',
Et='Etiimasi:BAAALgADCgUJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAECggJJwAKAKMiAA==.',
Fa='Fabulosa:BAABLgAECn8aAAQLAAcJGAcXOQAnAQALAAcJGAcXOQAnAQAMAAYJSwjjLwAhAQACAAQJgQJ4ZQCXAAAAAA==.Faith:BAAALgAECgMJBQAAAA==.',
Fi='Finite:BAAALgADCgkJCQABLgAECgcJGQAFAIIZAA==.Firebug:BAAALgAECgEJAQAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgADCgYJCwAAAA==.',
Fu='Furnok:BAABLgAECn8WAAMNAAYJiA1XEQD7AAANAAYJiA1XEQD7AAAOAAMJDQ5TfACiAAAAAA==.',
Ga='Galethia:BAAALgADCgkJDgAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gh='Ghutz:BAABLgAECn8hAAMPAAgJkQ9LBABcAQAQAAcJiAsqSACDAQAPAAgJkQ9LBABcAQAAAA==.',
Gl='Glitterhoof:BAAALgAECgQJCAAAAA==.',
Go='Goliath:BAAALgAECgIJAgAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gulluon:BAAALgADCgYJBgAAAA==.Gumbercules:BAABLgAECn8WAAIRAAYJthBABgAzAQARAAYJthBABgAzAQAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAAALgAECgQJCgAAAA==.',
Ho='Hollet:BAAALgAECgIJAgAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAABLgAECn8bAAISAAkJ3yCjBQASAwASAAkJ3yCjBQASAwAAAA==.',
Hu='Huckk:BAAALgADCgUJBQAAAA==.',
Hy='Hylen:BAAALgAECgYJCAAAAA==.',
Ib='Ibrandul:BAAALgAECgYJEwAAAA==.',
Ic='Icyveins:BAAALgAECgUJCgAAAA==.',
Ir='Ironhuntress:BAAALgAECgUJCwAAAA==.',
It='Ithro:BAABLgAECn8WAAITAAcJghV9AgB3AQATAAcJghV9AgB3AQAAAA==.',
Ja='Jarlo:BAABLgAECn8WAAITAAYJxRVMAgCDAQATAAYJxRVMAgCDAQAAAA==.',
Jo='Jormungandr:BAAALgAECgcJEwAAAA==.',
Ju='Juanhunglow:BAAALgADCgcJGgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAAALgAECgcJDAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAAALgAECgYJEAAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8cAAIRAAgJjxh+DwBCAgARAAgJjxh+DwBCAgAAAA==.',
Kr='Kreltor:BAAALgAECgUJDQAAAA==.Kryptikz:BAAALgAECgQJBAABLgAECgUJCwAEAAAAAA==.Krystoferson:BAAALgAECgMJBgAAAA==.',
La='Largar:BAAALgADCgQJBAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgAAAA==.Leianii:BAAALgADCgUJCwAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIUAAcJ8QeWgwBTAQAUAAcJ8QeWgwBTAQAAAA==.Lillat:BAAALgAECgIJAgAAAA==.Liryv:BAAALgADCgYJFAAAAA==.',
Lu='Luena:BAAALgAECgQJBwAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.',
Ly='Lyrà:BAAALgAECgQJAwAAAA==.',
['Lì']='Lìesson:BAAALgAECgcJEwAAAA==.',
Ma='Mackaroni:BAAALgAECgYJDwAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn8VAAIVAAYJpxqTFQCWAQAVAAYJpxqTFQCWAQAAAA==.Makkagg:BAABLgAECn8lAAMGAAgJdx1RAQBIAgAGAAgJdx1RAQBIAgAQAAgJVgzBOQC/AQAAAA==.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAAALgAECgYJDQAAAA==.',
Mi='Milagrosa:BAAALgAECgcJEwAAAA==.Mirael:BAABLgAECn8kAAIWAAkJOx7CCAAHAwAWAAkJOx7CCAAHAwAAAA==.Mishuntsalot:BAAALgADCgYJCQAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAAALgAECgEJAQAAAA==.',
My='Myrmia:BAAALgAECgUJCwAAAA==.Mystryx:BAAALgAECgUJCQAAAA==.',
['Mà']='Màck:BAAALgAECgMJAwABLgAECgYJDwAEAAAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAAALgAECgYJDgAAAA==.',
Ne='Nekossian:BAAALgAECgUJBQABLgAECggJHAAFAM8SAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAUAPEHAA==.',
No='Nonae:BAEALgADCgUJBQAAAA==.Nota:BAAALgAECgUJCwAAAA==.',
Oa='Oathmere:BAAALgADCgUJBQAAAA==.',
Og='Ogrusao:BAAALgAECgUJCAAAAA==.',
Pa='Panasaurus:BAABLgAECn8WAAIXAAYJ9BGJBAAJAQAXAAYJ9BGJBAAJAQAAAA==.',
Pe='Pechuuga:BAAALgAECgYJEgAAAA==.Pelli:BAAALgAECgUJCwAAAA==.Pendraig:BAAALgADCgUJCAAAAA==.',
Pl='Plaza:BAAALgAECgkJCAAAAA==.',
Qu='Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgQJCAAEAAAAAA==.Rayst:BAAALgAECgQJCgAAAA==.',
Rh='Rhalek:BAAALgAECgQJBAAAAA==.Rhykis:BAAALgAECgUJCwAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAAALgAECgYJEgAAAA==.',
Ro='Role:BAAALgADCgEJAQABLgAECgYJEAAEAAAAAA==.',
Ru='Rubbin:BAAALgADCgIJAgAAAA==.',
Sa='Salindill:BAAALgADCgMJAwAAAA==.Salline:BAAALgAECgQJCAAAAA==.',
Sc='Scorned:BAAALgAECgYJEgAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.',
Sh='Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgADCgkJGwAAAA==.Shaylinn:BAAALgADCgcJFgAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgkJGwASAN8gAA==.',
Si='Siella:BAAALgAECgUJDQAAAA==.Sitrom:BAAALgAECgIJAgAAAA==.',
Sn='Snayd:BAAALgAECgUJCgAAAA==.',
So='Sonofmums:BAAALgAECgcJBgAAAA==.Soulbaine:BAAALgAECgMJBQAAAA==.',
Sp='Spazeric:BAAALgAECgYJEQAAAA==.Spheria:BAABLgAECn8VAAIUAAYJJgM4MwC2AAAUAAYJJgM4MwC2AAAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJDAAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgUJBgAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBgAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECgQJBQAEAAAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAAALgAECgQJCgAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgADCgcJEQAAAA==.',
Ti='Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8UAAIVAAYJphophwDDAQAVAAYJphophwDDAQAAAA==.',
To='Tope:BAAALgADCgUJBQAAAA==.Toray:BAAALgAECgcJBQAAAA==.',
Tr='Triplesix:BAAALgAECgYJDwAAAA==.Trittia:BAAALgAECgUJCwAAAA==.',
Tu='Tukk:BAAALgADCgcJBwAAAA==.Turtle:BAAALgAECgEJAQAAAA==.',
Tw='Twigatron:BAAALgAECgUJBQABLgAECgcJDAAEAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgIJAQAAAA==.',
Ty='Tynk:BAAALgADCgUJBQABLgADCgcJFAAEAAAAAA==.',
Ur='Urza:BAAALgAECgIJAgAAAA==.',
Va='Vaewind:BAAALgADCgEJAQAAAA==.Valethus:BAABLgAECn8cAAMWAAgJ/BSjMwDhAQAWAAgJ/BSjMwDhAQAYAAIJVAgRfgBNAAAAAA==.',
Ve='Vesp:BAAALgADCgkJKAAAAA==.Vexxa:BAAALgAECgcJEgAAAA==.',
Vy='Vynd:BAAALgADCgMJAwAAAA==.',
Wa='Walkz:BAAALgAECgUJCwAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn8WAAILAAYJ2iI+AwAGAgALAAYJ2iI+AwAGAgAAAA==.Willscarlet:BAAALgAECgIJAgAAAA==.',
Wy='Wylethia:BAAALgADCgcJBwAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgYJDwAEAAAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgADCgYJBgAAAA==.',
Za='Zarathia:BAAALgADCggJGAAAAA==.Zaritym:BAAALgAECgUJCwAAAA==.Zarrilin:BAABLgAECn8cAAIVAAgJhxNOYQAYAgAVAAgJhxNOYQAYAgAAAA==.',
Ze='Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAABLgAECn8vAAIHAAgJYhY8CAA/AgAHAAgJYhY8CAA/AgAAAA==.',
Zo='Zoeheals:BAAALgAECgQJBQAAAA==.',
Zu='Zulmahn:BAAALgAECgUJDQAAAA==.',
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

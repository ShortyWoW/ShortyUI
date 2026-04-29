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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Monk-Mistweaver','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Guardian','Priest-Discipline','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Druid-Balance','Hunter-BeastMastery','Warrior-Protection','Druid-Feral','Druid-Restoration','Hunter-Survival','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aegisthal:BAAALgAECggJDgAAAA==.Aequitasx:BAAALgADCggJCwAAAA==.',
Ah='Ahrus:BAAALgADCgMJAwABLgAECgcJDwABAAAAAA==.',
Al='Alanerazza:BAAALgADCgUJBQAAAA==.Althenzdormu:BAAALgAECgYJDQAAAA==.Altruist:BAAALgAECgYJDQABLgAECgcJEQABAAAAAA==.',
Am='Amaethon:BAAALgAECgIJAgAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8YAAICAAcJXCDsAgBdAgACAAcJXCDsAgBdAgAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAAALgAECgcJEQAAAA==.',
Ar='Arathor:BAAALgAECgEJAQAAAA==.Ari:BAABLgAECn8UAAIDAAgJtQWoOgD/AAADAAgJtQWoOgD/AAAAAA==.Ariyia:BAAALgAECgYJCgAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAAALgAECgcJEQAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAAALgAECgcJEQAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAEAGkVAA==.Balthenor:BAACLgAFFH8GAAIFAAIJqxMbIgCoAAAFAAIJqxMbIgCoAAAuAAQKfx4AAgUACAn+IY4RAAQDAAUACAn+IY4RAAQDAAAA.',
Be='Beej:BAAALgAECggJDAAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAABAAAAAA==.Berse:BAAALgAECgYJDQAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgIJBgAAAA==.',
Bl='Blightbeard:BAAALgAECgQJBQAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgIJAgABLgAFFAQJCgAGAOsPAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgEJAQAAAA==.',
Br='Brut:BAABLgAECn8ZAAIHAAcJTB08EACEAQAHAAcJTB08EACEAQAAAA==.',
Bu='Bustus:BAAALgAECgcJDgAAAA==.',
Ca='Caroll:BAAALgAECgEJAQAAAA==.Carsomavra:BAAALgADCggJCAAAAA==.Cathercy:BAAALgAECgIJAgAAAA==.',
Ch='Chilly:BAAALgAECgYJDgABLgAECggJDAABAAAAAA==.Chunt:BAAALgADCgEJAQAAAA==.',
Co='Compliance:BAAALgAECgcJEQAAAA==.Corannis:BAAALgAECgcJDAAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECggJHgAIAFgQAA==.',
Cr='Cranberries:BAAALgAECgQJBQAAAA==.',
Cu='Curtis:BAAALgAECgYJDQAAAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgADCggJCAAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAAALgAECgYJDwAAAA==.',
De='Delderach:BAAALgAECgIJAgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAAALgAECgYJEAAAAA==.',
Di='Dirkette:BAABLgAECn8YAAIJAAcJLASrCwAKAQAJAAcJLASrCwAKAQAAAA==.Dirksavoid:BAAALgADCgUJBQABLgAECgcJGAAJACwEAA==.Dixonmayas:BAAALgAECgEJAQAAAA==.',
Do='Dokai:BAAALgAECgcJDwAAAA==.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgADCgcJCwAAAA==.Dragmartigan:BAAALgAECgIJAgAAAA==.Drewella:BAAALgADCgEJAQAAAA==.',
El='Eliance:BAAALgAECgIJAgAAAA==.Elsewhere:BAAALgAECgYJEgAAAA==.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Errius:BAAALgAECgYJEwAAAA==.',
Fu='Fusaa:BAAALgAECgYJEgAAAA==.',
Ga='Gangry:BAAALgAECgIJAgAAAA==.',
Ge='Gerbzarrion:BAAALgAECgIJAgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8VAAIKAAYJhhJ4KQB4AQAKAAYJhhJ4KQB4AQAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgUJBQAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEgAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Hawknnin:BAAALgAECgIJAgAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgYJBgAAAA==.Huntrod:BAAALgADCgEJAwAAAA==.Huroona:BAAALgADCgcJCwAAAA==.Huskiè:BAAALgADCgYJBgAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgQJBQABAAAAAA==.',
Ip='Ipwnallnoobs:BAAALgAECgYJBwAAAA==.',
Ir='Irisila:BAAALgADCgcJAQABLgADCgcJCwABAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jahkwellynn:BAAALgADCgEJAQAAAA==.Jakoti:BAAALgADCgUJBgAAAA==.Jaxsi:BAAALgAECgQJBwAAAA==.Jaypharyn:BAAALgAECgYJDQAAAA==.',
['Jå']='Jåsper:BAAALgAECgYJDQAAAA==.',
Ka='Kaileena:BAAALgAECgYJDgAAAA==.Kandistars:BAAALgAECgYJEwAAAA==.Kasia:BAAALgAECgYJDQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAAALgAECgYJCwAAAA==.Kirarah:BAAALgAECgYJDAAAAA==.Kirarose:BAACLgAFFH8FAAILAAIJiBFeCACYAAALAAIJiBFeCACYAAAuAAQKfxUAAwsABwneHVsWADUCAAsABwneHVsWADUCAAwAAwmECVloAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAAALgAECgcJEgAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCggJCgAAAA==.',
Ky='Kylia:BAAALgAECgEJAQAAAA==.',
['Kí']='Kíhanna:BAAALgAECgcJEgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8eAAMIAAgJWBDeAwBTAQANAAcJ1A/sLwCIAQAIAAgJVw7eAwBTAQAAAA==.',
Li='Lizardath:BAABLgAECn8XAAIOAAYJAQnUIAD8AAAOAAYJAQnUIAD8AAAAAA==.',
Lj='Ljósálfr:BAABLgAECn8YAAIPAAYJSCQJCwBfAgAPAAYJSCQJCwBfAgAAAA==.',
Lo='Lochramae:BAAALgAECgYJEwAAAA==.Logarius:BAAALgADCgQJBAAAAA==.',
Lu='Lunargaze:BAAALgAECgYJDgAAAA==.',
Ma='Mamimisan:BAAALgAECgYJEgAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAFAKsTAA==.Medios:BAAALgAECgQJBQAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgEJAgAAAA==.Mizkat:BAABLgAECn8UAAQIAAcJAhcqEAB1AQAIAAcJAhcqEAB1AQAQAAEJNQ6IDQA+AAARAAEJxRKSzwAvAAAAAA==.',
Mo='Mormra:BAAALgAECgcJDwAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8WAAQSAAcJOSI5BgCfAgASAAcJOSI5BgCfAgAOAAEJKh6ytwBTAAATAAEJgwGnmgAXAAAAAA==.',
Na='Naklus:BAAALgADCgMJAwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgADCgkJFQABLgAECgYJFQAKAIYSAA==.',
Nl='Nlani:BAAALgAECgQJBAAAAA==.',
Nu='Nuvi:BAAALgADCgUJBgAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pl='Platura:BAAALgAECgcJDQAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAAALgAECgcJEQAAAA==.Rassaphore:BAAALgAECgIJAgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgYJDQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgcJGQAHAEwdAA==.Rionach:BAAALgAECgcJEQAAAA==.Ritsara:BAAALgAECgQJBwAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgABAAAAAA==.Rivon:BAAALgAECgYJDwAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgUJBQAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgEJAQAAAA==.',
Sc='Scoop:BAAALgAECgMJAwAAAA==.',
Se='Seanx:BAAALgAECgYJEgAAAA==.',
Sh='Shenlong:BAAALgAFFAEJAgAAAA==.Shigurexx:BAAALgAECgYJEwAAAA==.Shoe:BAABLgAECn8eAAMUAAgJxBipCgAxAgAUAAcJnBupCgAxAgAVAAYJihD5BwBtAQAAAA==.',
Si='Sigmandis:BAAALgAECgQJBwAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgYJBwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgMJAwAAAA==.',
Sw='Sweeneytodd:BAAALgADCgYJBwAAAA==.',
Ta='Taliadrin:BAAALgADCgIJAgAAAA==.Tamarins:BAAALgAECgYJDQAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAAALgAECgcJEgAAAA==.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.',
To='Toom:BAAALgAECgIJAgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Trophyhubby:BAAALgAECgYJEwAAAA==.',
Ty='Tyeren:BAAALgAECgYJCAAAAA==.Tyeriel:BAACLgAFFH8KAAIGAAQJ6w/IBwBJAQAGAAQJ6w/IBwBJAQAuAAQKfxwAAgYACAn/HtUiALQCAAYACAn/HtUiALQCAAAA.',
Va='Valat:BAAALgADCgUJBQAAAA==.Valkyriefall:BAAALgAECgIJAgAAAA==.Valvet:BAAALgADCgkJGQAAAA==.',
Vi='Vikril:BAAALgADCgkJFQAAAA==.Vincenzo:BAAALgAECgEJAQAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Volkanoth:BAABLgAECn8UAAIHAAcJ2SPdJQBvAgAHAAcJ2SPdJQBvAgAAAA==.',
Vy='Vylus:BAAALgADCgkJFwAAAA==.',
We='Weeblewobble:BAAALgADCgYJAwAAAA==.',
Wi='Wikidblade:BAAALgADCgkJEAAAAA==.William:BAAALgAECgYJBwAAAA==.Windee:BAAALgAECgQJBQAAAA==.',
Wr='Wrast:BAAALgAECgYJDAAAAA==.',
Xy='Xyara:BAABLgAECn8WAAQEAAgJ0BicAwDtAAAWAAQJDBTjIQAWAQAEAAQJWBycAwDtAAAXAAMJoBNiOwDGAAAAAA==.Xylaara:BAAALgADCgMJAgAAAA==.',
Ya='Yarine:BAAALgADCgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8WAAIYAAYJsR9ACgB7AQAYAAYJsR9ACgB7AQAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAAALgAECgQJBQAAAA==.Zatika:BAABLgAECn8UAAIZAAcJqhbkBgCgAQAZAAcJqhbkBgCgAQAAAA==.',
Zi='Zibzab:BAAALgAECgIJAgAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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

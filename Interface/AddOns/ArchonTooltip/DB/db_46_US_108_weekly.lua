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

local lookup = {'Evoker-Augmentation','Unknown-Unknown','Warlock-Demonology','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Brewmaster','Druid-Balance','Druid-Restoration','Monk-Windwalker','Mage-Frost','Mage-Arcane','Warlock-Destruction','Paladin-Retribution','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Monk-Mistweaver','Druid-Feral','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAECgQJBQAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgADCgUJBQAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAMJBwABAJcVAA==.Aiyaiyai:BAAALgAECgYJDAAAAA==.',
Al='Alall:BAAALgAECgEJBAAAAA==.Alauth:BAAALgAECgEJAQAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.',
Am='Aminall:BAAALgADCgQJCAAAAA==.',
An='Anarreth:BAAALgADCgUJBQAAAA==.Andore:BAAALgAECgQJDAAAAA==.Anewbyss:BAAALgAECgMJBAAAAA==.Angrymurloc:BAAALgAECgUJBQAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgQJBwAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Arlon:BAAALgAECgEJAQABLgAECgYJEAACAAAAAA==.Arms:BAAALgAECgEJAQAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJAgAAAA==.Ashraki:BAAALgADCgEJAQAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAAALgAECgYJDgAAAA==.',
At='Atreana:BAABLgAECn8mAAIDAAgJYRN2KQDAAQADAAgJYRN2KQDAAQAAAA==.Attykus:BAABLgAECn8mAAIEAAgJOxHPGQCYAQAEAAgJOxHPGQCYAQAAAA==.',
Av='Avalerion:BAAALgAECgQJDAAAAA==.Avij:BAAALgAECgMJBgABLgAECgUJCAACAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAgAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Barrellroll:BAAALgADCgkJCQAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIFAAkJTw+MFADsAQAFAAkJTw+MFADsAQAAAA==.Bigpoppapump:BAAALgAECgMJBAAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIGAAcJYwYTlgDxAAAGAAcJYwYTlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8ZAAIHAAYJzR/nAABKAgAHAAYJzR/nAABKAgAuAAQKfx0AAgcACQkiJJMOAKUCAAcACQkiJJMOAKUCAAAA.',
Bo='Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECgYJCgAAAA==.Bowdacious:BAAALgAECgEJAgAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAECgQJCwAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brumak:BAAALgAECgIJAgAAAA==.Bruno:BAAALgAECgcJEQAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
['Bá']='Báthory:BAAALgAECgUJBQAAAA==.',
Ca='Cal:BAAALgAECgQJBAABLgAECggJIwAIAPEbAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAABLgAECn8jAAIIAAgJ8Rt7DAD7AQAIAAgJ8Rt7DAD7AQAAAA==.Camelshammy:BAAALgAECgQJCgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJEgACAAAAAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgMJCwAAAA==.',
Ce='Cedarpoint:BAAALgADCgUJBQAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8WAAMJAAcJpxahFgCHAQAJAAcJpxahFgCHAQAKAAEJphGnzAAyAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Chizami:BAAALgAECgQJBAABLgAFFAUJCgAFAKINAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8cAAILAAkJaSDQAgDgAgALAAkJaSDQAgDgAgAAAA==.',
Ci='Circa:BAABLgAECn8YAAMMAAcJDhAFaABBAQAMAAYJSxEFaABBAQANAAQJWg7cEAC0AAAAAA==.Cithrel:BAABLgAECn8YAAIOAAkJiQ/ACgAoAQAOAAkJiQ/ACgAoAQAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Crocklock:BAAALgAECgYJEwAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8eAAIPAAcJNAX2kgDIAAAPAAcJNAX2kgDIAAAAAA==.Damnatio:BAABLgAECn8cAAIPAAkJYiRCAwAlAwAPAAkJYiRCAwAlAwAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Darkclement:BAAALgAECgYJCwABLgAECggJGAAPACIfAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgADCgkJHgAAAA==.Deathgriped:BAAALgAECgQJCQAAAA==.Deeper:BAAALgAECgIJAgAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCQAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAACAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCAACAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECggJFAADAIoPAA==.Drahalah:BAABLgAECn8eAAIQAAgJWx9AEgBqAgAQAAgJWx9AEgBqAgAAAA==.Drakeji:BAABLgAECn8nAAMBAAgJDwpAHgBNAQABAAgJDwpAHgBNAQARAAMJyACaPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAECgkJCQABLgAFFAQJEAASAFgbAA==.',
Du='Dumplingg:BAAALgAECgcJCQAAAA==.',
Ea='Earthvoodoo:BAAALgAECgUJDQAAAA==.',
Eb='Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgADCgcJBwACAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgMJBwAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAYJEwAPALEgAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJJgAEADsRAA==.',
En='Ender:BAAALgADCgEJAQAAAA==.',
Ep='Epi:BAAALgAECgcJDwAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJDgAAAA==.',
Ev='Evianda:BAAALgADCggJBwAAAA==.',
Ez='Ezale:BAAALgAECggJCwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAQAAAA==.Faramír:BAAALgADCgYJBAAAAA==.Fatébringer:BAAALgAECggJDgAAAA==.',
Fe='Fennek:BAAALgAECgYJCgAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Ga='Garaylo:BAACLgAFFH8TAAIPAAYJsSCbAwDUAQAPAAYJsSCbAwDUAQAuAAQKfygAAg8ACQn1JL8CAKwDAA8ACQn1JL8CAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAITAAkJtiLkAgAHAwATAAkJtiLkAgAHAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJLQALAG4bAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8dAAQQAAgJmxLzRwBkAQAQAAgJjw/zRwBkAQAUAAYJNA1KCQAIAQAVAAEJRx7mMABVAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnudgnimish:BAAALgAECgYJBgAAAA==.',
Go='Goldenblight:BAAALgAECgIJBQAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgEJAQAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgMJAwAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJDQAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAACAAAAAA==.Halstron:BAABLgAECn8cAAIPAAgJXhroHgAPAgAPAAgJXhroHgAPAgAAAA==.Harribel:BAABLgAECn8UAAQQAAUJYwffpgCSAAAQAAUJBgTfpgCSAAAVAAIJsQlcMQBSAAAUAAIJ8gHaFgA1AAAAAA==.',
He='Heliòs:BAAALgAECgMJAwAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQWAAkJTRWRGQCCAQAWAAkJTRWRGQCCAQAXAAMJXgfNJACLAAAHAAEJhA32gwAqAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECggJDgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8hAAIIAAkJMyHcAgDZAgAIAAkJMyHcAgDZAgAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAgAAAA==.',
Hy='Hylie:BAABLgAECn8bAAIDAAgJ1g1SWgC5AQADAAgJ1g1SWgC5AQAAAA==.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAQJEAASAFgbAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
In='Inte:BAAALgADCgYJBgAAAA==.',
Iz='Izgin:BAAALgAECgYJEgAAAA==.',
Ja='Jaime:BAAALgADCgYJCQABLgAECgYJCAACAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgACAAAAAA==.Jantar:BAABLgAECn8VAAIKAAkJxhaWEABPAgAKAAkJxhaWEABPAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAAALgAECgkJEQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgUJCQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwACAAAAAA==.',
Ju='Jugsy:BAAALgAECgYJDAAAAA==.Juliza:BAAALgADCgQJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaligo:BAABLgAECn8vAAMWAAkJ3xSnDAARAgAWAAkJ3xSnDAARAgAXAAQJrgSvIgCrAAAAAA==.Kalistus:BAAALgAECggJEgAAAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgADCgkJDwAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJBQAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8iAAILAAkJSSKfAQAUAwALAAkJSSKfAQAUAwAAAA==.Kegfupanda:BAAALgAECgEJAgAAAA==.Keleion:BAABLgAECn8lAAIGAAcJsxC1RgAkAQAGAAcJsxC1RgAkAQABLgAECggJCwACAAAAAA==.Kevonjuravis:BAAALgAECgUJEwAAAA==.',
Kh='Khalya:BAAALgADCgQJBAAAAA==.Khalyl:BAAALgAECgYJCgAAAA==.Kheart:BAAALgAECgEJAQAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGgAAAA==.',
Ko='Koder:BAACLgAFFH8HAAIBAAMJlxU5IADsAAABAAMJlxU5IADsAAAuAAQKfyMABAEACAmtIa8GABIDAAEACAmtIa8GABIDABgAAgkOAq9EAEoAABEAAQmAFR89ADoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgADCgQJBAAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kungfu:BAAALgADCgQJBAABLgAECgUJCAACAAAAAA==.Kupó:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn8lAAIQAAgJLRrfIgD6AQAQAAgJLRrfIgD6AQAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilithxander:BAAALgAECgMJBQAAAA==.Lizzybordan:BAAALgAECgMJAwAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAAALgAECgQJCAAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.',
Ma='Mariskama:BAAALgAECgcJEgAAAA==.Markusthered:BAAALgADCgYJBgAAAA==.Mazza:BAAALgAECggJCAAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Meowimabear:BAAALgADCgkJEAABLgAECgkJIwATALYiAA==.Metal:BAAALgAECgQJDQAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJDAAAAA==.',
Mi='Mikkais:BAAALgAECgMJCAAAAA==.Minimini:BAACLgAFFH8IAAIZAAQJdBI+EAAeAQAZAAQJdBI+EAAeAQAuAAQKfy0AAhkACAkzHZgIAGoCABkACAkzHZgIAGoCAAAA.Minni:BAAALgAECgcJCwAAAA==.',
Mo='Moolin:BAABLgAECn8XAAIaAAcJ6AMeFQDTAAAaAAcJ6AMeFQDTAAAAAA==.Moranthe:BAAALgAECgcJDAABLgAECgkJEgACAAAAAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJCAAAAA==.Muggypew:BAAALgAECgkJDQAAAA==.Munder:BAABLgAECn8VAAMDAAgJLxg+LACzAQADAAgJEhg+LACzAQAbAAEJkCDIEgBbAAAAAA==.Mustymuppet:BAACLgAFFH8IAAIDAAQJywaEPQDhAAADAAQJywaEPQDhAAAuAAQKfxwAAwMACAmWGcMwAKEBAAMACAmWGcMwAKEBAA4AAQlnD6tuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAAALgAECgQJEQAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAAALgAECgYJEgAAAA==.Nemini:BAAALgADCgkJGgAAAA==.Nena:BAAALgAECgQJCgAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAAALgAECgYJEQAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAAALgAECgYJDQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Notagain:BAACLgAFFH8bAAIPAAcJfxpzAgD7AQAPAAcJfxpzAgD7AQAuAAQKfykAAg8ACQkBI5QHAFoDAA8ACQkBI5QHAFoDAAAA.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgQJBQAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwAAAA==.',
Oc='Oceanic:BAAALgADCgYJBgAAAA==.',
Ol='Olgreeneyes:BAAALgAECgIJAwAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIKAAYJChglTABzAQAKAAYJChglTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJEgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Peejean:BAAALgAECgYJBgAAAA==.Peybreak:BAAALgAECgEJAQABLgAECgkJHAANAKgcAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHAANAKgcAA==.Peycicle:BAABLgAECn8cAAINAAgJqBxKAQDOAgANAAgJqBxKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHAANAKgcAA==.Peystruction:BAAALgAECgEJAQABLgAECgkJHAANAKgcAA==.Peytan:BAAALgAECgYJCwABLgAECgkJHAANAKgcAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAECgIJAgAAAA==.Pippa:BAABLgAECn8YAAIYAAcJ9RoiBgAnAgAYAAcJ9RoiBgAnAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8aAAMHAAgJQBidHADMAQAHAAgJQBidHADMAQAWAAEJFgNZcgAfAAAAAA==.',
Po='Poetuck:BAABLgAECn8iAAIMAAgJTA93RwCRAQAMAAgJTA93RwCRAQAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAACAAAAAA==.',
Pr='Proko:BAABLgAECn8YAAMWAAcJbRBRJQAtAQAWAAYJ7hJRJQAtAQAHAAEJjg23hAApAAAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBgAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.',
Qu='Quiver:BAABLgAECn8VAAIPAAYJmgsfhwDeAAAPAAYJmgsfhwDeAAAAAA==.',
['Qì']='Qìlen:BAAALgAECgYJDwAAAA==.',
Ra='Raein:BAABLgAECn8dAAMHAAcJyR5NDQBgAgAHAAcJyR5NDQBgAgAWAAYJvRPlJgAkAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAAALgAECgQJBAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Ralofurius:BAAALgAECgUJCAAAAA==.Rasril:BAAALgAECgUJCgAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBAAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Renicus:BAAALgADCgYJBwAAAA==.Renmare:BAAALgAECgUJEAAAAA==.Renmore:BAAALgAECgQJBgAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBAAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Risotto:BAAALgAECgEJAQAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJCwACAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgQJCgAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8WAAIcAAYJbwoKUwAVAQAcAAYJbwoKUwAVAQAAAA==.Ruele:BAAALgAECgkJEgAAAA==.Ruenan:BAABLgAECn8mAAMcAAgJnCaOAgAfAwAcAAgJnCaOAgAfAwAdAAMJlhKsaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn8jAAMJAAgJ+Q/QHQBGAQAJAAgJGQ7QHQBGAQAeAAYJ4g7lEgDbAAAAAA==.Ryian:BAAALgADCgkJCQAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIeAAcJNgpAGAD0AAAeAAcJNgpAGAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIfAAYJXgH2JgCJAAAfAAYJXgH2JgCJAAAAAA==.Sapthat:BAABLgAECn8bAAMgAAcJwyH7AwDqAQAgAAYJAyT7AwDqAQAhAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAAALgAECgYJDgAAAA==.Savepebble:BAABLgAECn8UAAMDAAgJig+pSgBJAQADAAcJgg2pSgBJAQAOAAMJHhL4TACHAAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAQAAAA==.',
Se='Seather:BAABLgAECn8aAAIiAAgJyRvCEwB4AgAiAAgJyRvCEwB4AgAAAA==.Seirin:BAABLgAECn8dAAIjAAcJyg9FHABnAQAjAAcJyg9FHABnAQAAAA==.Selendaa:BAAALgAECgQJDAAAAA==.Senadarra:BAACLgAFFH8LAAIdAAMJxxwjCgAfAQAdAAMJxxwjCgAfAQAuAAQKfzEAAh0ACAlUHtUCAD8CAB0ACAlUHtUCAD8CAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAAALgADCgEJAQAAAA==.Serendipity:BAAALgADCgYJCQABLgAECgcJDwACAAAAAA==.Serqet:BAAALgAECgMJAwAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAAALgAECgcJDAAAAA==.Sheri:BAAALgAECgQJDQAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAAALgAECgYJEAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.',
Si='Sillygoose:BAACLgAFFH8VAAIMAAYJxRExEQCjAQAMAAYJxRExEQCjAQAuAAQKfx4AAgwACQlJII4VACcDAAwACQlJII4VACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQAAAA==.Siong:BAAALgADCgcJCgABLgAFFAYJEwAPALEgAA==.Siorknav:BAABLgAECn8fAAIPAAgJew4dUABWAQAPAAgJew4dUABWAQAAAA==.',
Sk='Skalar:BAAALgAECgYJDAAAAA==.Skodah:BAAALgADCgkJEQAAAA==.',
Sl='Släyr:BAAALgADCgIJAgAAAA==.',
So='Solunara:BAAALgADCgYJFQAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAAALgAECgcJEgAAAA==.Sorrenda:BAAALgADCgkJCQAAAA==.Soup:BAABLgAECn8nAAIaAAkJ/g1UBwDDAQAaAAkJ/g1UBwDDAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIiAAkJdRlXBQBnAgAiAAkJdRlXBQBnAgAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBgAAAA==.Stovik:BAABLgAECn8iAAMXAAgJbxw7AwBZAgAXAAgJbxw7AwBZAgAHAAcJzgjEPwAEAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgQJDAAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBAAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJBwAAAA==.Sylira:BAACLgAFFH8MAAIjAAYJFg8EAwCyAQAjAAYJFg8EAwCyAQAuAAQKfy0AAyMACQkwHA8KAKwCACMACQkwHA8KAKwCACQAAwlrCl5SAIAAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAACAAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8QAAISAAQJWBslBQBWAQASAAQJWBslBQBWAQAuAAQKfyMAAxIACQmwIDsCAAcDABIACQlZIDsCAAcDAAQABwkrGsMsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgIJAwAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgEJAQABLgAECggJGQAlAOcLAA==.Tankie:BAAALgADCgEJAQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgADCgkJCQAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgMJAwAAAA==.Tharonix:BAAALgAECgYJEQAAAA==.Thelil:BAAALgAECgMJAwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgADCgcJCgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn8aAAIMAAgJWRrDZAAPAgAMAAgJWRrDZAAPAgAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAACAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgIJAgAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFAAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Un='Unoboxo:BAAALgADCgEJAQABLgAECgkJMAABACsdAA==.Unovoke:BAABLgAECn8wAAIBAAkJKx0xBgB8AgABAAkJKx0xBgB8AgAAAA==.',
Va='Valorash:BAABLgAECn8cAAMPAAYJ9yKXJgDnAQAPAAYJ9yKXJgDnAQAmAAYJ3hq3DwDJAQAAAA==.Valorious:BAAALgAECgEJAQAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgMJAwAAAA==.Velintha:BAAALgAECgYJBAAAAA==.Venatrix:BAAALgAECgYJDwAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCAACAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAAALgAECgYJCgAAAA==.Vonderick:BAAALgADCgkJKAAAAA==.Voodoodog:BAAALgAECgIJBAABLgAECgUJDQACAAAAAA==.',
Vy='Vynlorellas:BAAALgADCgcJCAAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQACAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgADCgcJIgABLgAECgMJAwACAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQACAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIXAAcJ6BSuDgDRAQAXAAcJ6BSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAECgcJHQALALsiAA==.',
Wy='Wynce:BAAALgADCgcJBwAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgEJAQAAAA==.Xarn:BAABLgAECn8hAAIDAAkJtQcMQABpAQADAAkJtQcMQABpAQAAAA==.',
Xc='Xcïte:BAAALgAECgcJEAAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.',
Yo='Yourlock:BAAALgADCgUJBQAAAA==.',
Yu='Yuji:BAABLgAECn8hAAIPAAgJWg3nRAB3AQAPAAgJWg3nRAB3AQAAAA==.',
Za='Zalectra:BAACLgAFFH8NAAITAAQJ8SDVAwB8AQATAAQJ8SDVAwB8AQAuAAQKfy4AAxMACQm1JUIAAMMDABMACQm1JUIAAMMDAB0AAgmlFkMZAIMAAAAA.',
Ze='Zelila:BAAALgADCgYJCAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBgAAAA==.',
['Ål']='Ålloria:BAAALgAECgEJAQAAAA==.',
['ßl']='ßlackßetty:BAAALgADCgYJBwABLgADCgkJCQACAAAAAA==.',
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

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

local lookup = {'Evoker-Augmentation','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Brewmaster','Monk-Windwalker','Warlock-Destruction','Paladin-Retribution','DeathKnight-Unholy','Evoker-Devastation','Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Evoker-Preservation','Monk-Mistweaver','Druid-Feral','Druid-Restoration','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acehuntura:BAAALgAECgEJAQAAAA==.',
Ad='Adaric:BAAALgAECgQJBAAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAMJBwABAJcVAA==.Aiyaiyai:BAAALgAECgYJDAAAAA==.',
Al='Alall:BAAALgAECgEJAQAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.',
Am='Aminall:BAAALgADCgEJAgAAAA==.',
An='Anarreth:BAAALgADCgMJAwAAAA==.Andore:BAAALgAECgQJBQAAAA==.Anewbyss:BAAALgADCgcJCQAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgADCggJGwAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgMJBAAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Arms:BAAALgADCgQJBAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgEJAQAAAA==.Ashraki:BAAALgADCgEJAQAAAA==.Astraeal:BAAALgAECgYJCQAAAA==.',
At='Atreana:BAABLgAECn8fAAICAAgJmRIGHwC6AQACAAgJmRIGHwC6AQAAAA==.Attykus:BAABLgAECn8fAAIDAAgJIA81MQDoAQADAAgJIA81MQDoAQAAAA==.',
Av='Avalerion:BAAALgAECgQJCAAAAA==.Avij:BAAALgAECgMJAwABLgAECgMJAwAEAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAQAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Barrellroll:BAAALgADCgkJCQAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8eAAIFAAgJaw75EgDBAQAFAAgJaw75EgDBAQAAAA==.Bigpoppapump:BAAALgAECgMJBAAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8SAAIGAAcJYwYLlgDxAAAGAAcJYwYLlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8VAAIHAAYJfh5NAABVAgAHAAYJfh5NAABVAgAuAAQKfx0AAgcACQkiJJYOAKUCAAcACQkiJJYOAKUCAAAA.',
Bo='Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECgUJBQAAAA==.Bowdacious:BAAALgAECgEJAQAAAA==.',
Br='Brainpath:BAAALgAECgMJBwAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brumak:BAAALgAECgIJAgAAAA==.Bruno:BAAALgAECgcJEQAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
Ca='Cal:BAAALgAECgEJAQABLgAECgcJHwAIAFobAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAABLgAECn8fAAIIAAcJWhstDgCqAQAIAAcJWhstDgCqAQAAAA==.Camelshammy:BAAALgAECgMJAwAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJDgAEAAAAAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgMJBgAAAA==.',
Ce='Cedarpoint:BAAALgADCgMJAwAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAAALgAECgYJDwAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8WAAIJAAkJXSCSAQDmAgAJAAkJXSCSAQDmAgAAAA==.',
Ci='Circa:BAAALgAECgYJEQAAAA==.Cithrel:BAABLgAECn8XAAIKAAkJWA9TCAApAQAKAAkJWA9TCAApAQAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Crocklock:BAAALgAECgUJDAAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8eAAILAAcJNAU/bwDQAAALAAcJNAU/bwDQAAAAAA==.Damnatio:BAABLgAECn8WAAILAAgJsCRdBQDEAgALAAgJsCRdBQDEAgAAAA==.Damonster:BAAALgAECgIJAgAAAA==.Darkclement:BAAALgAECgYJBgAAAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgADCgkJHgAAAA==.Deathgriped:BAAALgAECgQJBgAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAAEAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCAAEAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgcJDwAEAAAAAA==.Drahalah:BAABLgAECn8eAAIMAAgJWx8QCgCAAgAMAAgJWx8QCgCAAgAAAA==.Drakeji:BAABLgAECn8fAAMBAAgJHQYCGwAmAQABAAgJHQYCGwAmAQANAAMJyACbPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.',
Du='Dumplingg:BAAALgAECgcJCQAAAA==.',
Ea='Earthvoodoo:BAAALgAECgUJCwAAAA==.',
Eb='Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgADCgcJBwAEAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgMJBQAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAUJDwALAB4gAA==.',
Em='Emmeri:BAAALgAECgQJBAABLgAECggJHwADACAPAA==.',
Ep='Epi:BAAALgAECgYJDQAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJDgAAAA==.',
Ev='Evianda:BAAALgADCgEJAQAAAA==.',
Ez='Ezale:BAAALgADCgUJBQAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAQAAAA==.Faramír:BAAALgADCgYJBAAAAA==.Fatébringer:BAAALgAECgcJDAAAAA==.',
Fe='Fennek:BAAALgAECgUJBQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Ga='Garaylo:BAACLgAFFH8PAAILAAUJHiBBBgCLAQALAAUJHiBBBgCLAQAuAAQKfygAAgsACQn1JMACAKwDAAsACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIOAAkJtiLkAgAHAwAOAAkJtiLkAgAHAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwAAAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8XAAQPAAgJmRJaBgAgAQAMAAgJZg/BjABnAQAPAAYJMg1aBgAgAQAQAAEJRx6WJABVAAAAAA==.Gnudgnimish:BAAALgAECgYJBgAAAA==.',
Go='Goldenblight:BAAALgAECgIJAwAAAA==.Goldenchi:BAAALgADCgUJBQAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgMJAwAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJDAAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAAEAAAAAA==.Halstron:BAABLgAECn8YAAILAAcJgxZ8OwBYAQALAAcJgxZ8OwBYAQAAAA==.Harribel:BAAALgAECgUJEAAAAA==.',
He='Heliòs:BAAALgADCgkJDgAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQRAAkJTRUUEgCOAQARAAkJTRUUEgCOAQASAAMJXgfLJACLAAAHAAEJhA3WZQAqAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECgcJCgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8fAAIIAAgJGCJxAwCQAgAIAAgJGCJxAwCQAgAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAQAAAA==.',
Hy='Hylie:BAABLgAECn8bAAICAAgJ1Q1RWgC5AQACAAgJ1Q1RWgC5AQAAAA==.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAQJDAATABwZAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Iz='Izgin:BAAALgAECgYJDgAAAA==.',
Ja='Jaime:BAAALgADCgYJCQABLgAECgYJCAAEAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgAEAAAAAA==.Jantar:BAAALgAECgkJEQAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAAALgAECgcJEQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgUJBQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwAEAAAAAA==.',
Ju='Jugsy:BAAALgAECgYJCAAAAA==.Juliza:BAAALgADCgQJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgEJAQAAAA==.Kaligo:BAABLgAECn8lAAMRAAgJShQfDwCxAQARAAgJShQfDwCxAQASAAQJrgSuIgCrAAAAAA==.Kalistus:BAAALgAECgYJDwAAAA==.Karetha:BAAALgADCgYJBgAAAA==.Katreset:BAAALgAECgUJBQAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8eAAIJAAgJiSJ6AgC1AgAJAAgJiSJ6AgC1AgAAAA==.Kegfupanda:BAAALgAECgEJAgAAAA==.Keleion:BAABLgAECn8hAAIGAAcJrxCTLwAlAQAGAAcJrxCTLwAlAQAAAA==.Kevonjuravis:BAAALgAECgUJDAAAAA==.',
Kh='Khalyl:BAAALgAECgYJBgAAAA==.Kheart:BAAALgAECgEJAQAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGgAAAA==.',
Ko='Koder:BAACLgAFFH8HAAIBAAMJlxXQFgDxAAABAAMJlxXQFgDxAAAuAAQKfyMABAEACAmtIa4GABIDAAEACAmtIa4GABIDABQAAgkOAq5EAEoAAA0AAQmAFSA9ADoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgADCgQJBAAAAA==.Krytus:BAAALgAECgEJAQAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAAEAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn8dAAIMAAgJlhjsGwDgAQAMAAgJlhjsGwDgAQAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilithxander:BAAALgAECgMJBQAAAA==.Lizzybordan:BAAALgADCgcJDAABLgADCgcJIgAEAAAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAAALgAECgQJBAAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.',
Ma='Mariskama:BAAALgAECgYJCwAAAA==.Markusthered:BAAALgADCgYJBgAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAOALYiAA==.Metal:BAAALgAECgQJCwAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJCAAAAA==.',
Mi='Mikkais:BAAALgAECgMJBQAAAA==.Minimini:BAABLgAECn8pAAIVAAgJthwVBgBnAgAVAAgJthwVBgBnAgAAAA==.',
Mo='Moolin:BAABLgAECn8XAAIWAAcJ6AP8DwDZAAAWAAcJ6AP8DwDZAAAAAA==.Moranthe:BAAALgAECgcJDAABLgAECggJEAAEAAAAAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJBwAAAA==.Muggypew:BAAALgAECgkJDQAAAA==.Munder:BAAALgAECgcJEwAAAA==.Mustymuppet:BAABLgAECn8aAAMCAAgJ0hYxQAANAgACAAgJ0hYxQAANAgAKAAEJZw+rbgA4AAAAAA==.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAAALgAECgQJDAAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAAALgAECgUJDgAAAA==.Nemini:BAAALgADCgkJGgAAAA==.Nena:BAAALgAECgEJAgAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJDQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAAALgAECgUJCwAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAAALgAECgYJCgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Notagain:BAACLgAFFH8ZAAILAAYJtR79AgCxAQALAAYJtR79AgCxAQAuAAQKfyIAAgsACQk7IpUHAFoDAAsACQk7IpUHAFoDAAAA.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgADCgIJAgAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgEJAQAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAgAAAA==.',
Ol='Olgreeneyes:BAAALgAECgIJAgAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIXAAYJChgrTABzAQAXAAYJChgrTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJEgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Peejean:BAAALgAECgYJBgAAAA==.Peybreak:BAAALgAECgEJAQABLgAECgkJHAAYAKgcAA==.Peychi:BAAALgAECgQJBAABLgAECgkJHAAYAKgcAA==.Peycicle:BAABLgAECn8cAAIYAAgJqBxKAQDOAgAYAAgJqBxKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHAAYAKgcAA==.Peystruction:BAAALgADCgUJBQABLgAECgkJHAAYAKgcAA==.Peytan:BAAALgAECgYJCgABLgAECgkJHAAYAKgcAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAECgIJAgAAAA==.Pippa:BAAALgAECgYJEQAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8VAAIHAAgJ5xcRFADLAQAHAAgJ5xcRFADLAQAAAA==.',
Po='Poetuck:BAABLgAECn8bAAIZAAgJgw2zXQAhAQAZAAgJgw2zXQAhAQAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAAEAAAAAA==.',
Pr='Proko:BAAALgAECgYJEQAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBAAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.',
Qu='Quiver:BAAALgAECgYJEgAAAA==.',
['Qì']='Qìlen:BAAALgAECgQJDAAAAA==.',
Ra='Raein:BAABLgAECn8WAAMRAAYJvROqHQApAQARAAYJvROqHQApAQAHAAUJxRiQOADSAAAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAAALgAECgQJBAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Ralofurius:BAAALgAECgMJAwAAAA==.Rasril:BAAALgAECgUJCQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBAAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Renicus:BAAALgADCgYJBwAAAA==.Renmare:BAAALgAECgUJDAAAAA==.Renmore:BAAALgAECgQJBAAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBAAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Risotto:BAAALgAECgEJAQAAAA==.Riumi:BAAALgAECgMJBgAAAA==.Rivenxi:BAAALgADCgEJAQABLgAECgcJCwAEAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgQJCAAAAA==.',
Ru='Rubymoonbeam:BAAALgAECgYJEAAAAA==.Ruele:BAAALgAECggJEAAAAA==.Ruenan:BAABLgAECn8eAAMaAAgJ/yUkAgD7AgAaAAgJ/yUkAgD7AgAbAAMJlhKWaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn8bAAMcAAgJxA76HAAUAQAcAAgJBAz6HAAUAQAdAAYJ3g64DQDcAAAAAA==.Ryian:BAAALgADCgkJCQAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIdAAcJNgpDGADzAAAdAAcJNgpDGADzAAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIeAAYJXgF3HgCLAAAeAAYJXgF3HgCLAAAAAA==.Sapthat:BAABLgAECn8bAAMfAAcJxSH7AwDqAQAfAAYJBST7AwDqAQAgAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAAALgAECgYJCgAAAA==.Savepebble:BAAALgAECgcJDwAAAA==.',
Se='Seather:BAABLgAECn8aAAIhAAgJyRvFEwB4AgAhAAgJyRvFEwB4AgAAAA==.Seirin:BAABLgAECn8WAAIiAAYJtw6aHAAgAQAiAAYJtw6aHAAgAQAAAA==.Selendaa:BAAALgAECgQJCAAAAA==.Senadarra:BAACLgAFFH8IAAIbAAMJ9Bl7BwASAQAbAAMJ9Bl7BwASAQAuAAQKfy0AAhsACAklHTUCADcCABsACAklHTUCADcCAAAA.Sephenroth:BAAALgAECgMJBAAAAA==.Sephron:BAAALgADCgEJAQAAAA==.Serendipity:BAAALgADCgYJCQABLgAECgYJDQAEAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAAALgAECgcJDAAAAA==.Sheri:BAAALgAECgQJDQAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAAALgAECgQJBwAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJBwAAAA==.',
Si='Sillygoose:BAACLgAFFH8UAAIZAAYJxRGxCACyAQAZAAYJxRGxCACyAQAuAAQKfx4AAhkACQlJII4VACcDABkACQlJII4VACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQAAAA==.Siong:BAAALgADCgcJCgABLgAFFAUJDwALAB4gAA==.Siorknav:BAABLgAECn8bAAILAAgJuwx7SgArAQALAAgJuwx7SgArAQAAAA==.',
Sk='Skalar:BAAALgAECgYJCgAAAA==.Skodah:BAAALgADCgkJEQAAAA==.',
Sl='Släyr:BAAALgADCgIJAgAAAA==.',
So='Solunara:BAAALgADCgYJFQAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAAALgAECgcJCwAAAA==.Soup:BAABLgAECn8eAAIWAAgJqwztBgCSAQAWAAgJqwztBgCSAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAAALgAECgkJEgAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBgAAAA==.Stovik:BAABLgAECn8aAAMSAAcJBRoCBgCwAQASAAcJBRoCBgCwAQAHAAYJtwgaOQDPAAAAAA==.',
Sv='Sventhebrave:BAAALgAECgQJCAAAAA==.',
Sw='Sweeneytod:BAAALgAECgEJAgAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgIJAgAAAA==.Sylira:BAACLgAFFH8LAAIiAAUJgA5AAwCBAQAiAAUJgA5AAwCBAQAuAAQKfy0AAyIACQkwHBQKAKwCACIACQkwHBQKAKwCACMAAwlrCl5SAIAAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAAEAAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takedown:BAACLgAFFH8MAAITAAQJHBluAwBdAQATAAQJHBluAwBdAQAuAAQKfyMAAxMACQmwIDwCAAcDABMACQlZIDwCAAcDAAMABwkrGsYsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgIJAwAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgADCgkJCwABLgAECggJFgAkAKgLAA==.Tankie:BAAALgADCgEJAQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgADCgkJCQAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgMJAwAAAA==.Tharonix:BAAALgAECgYJDQAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgADCgcJCgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn8YAAIZAAcJNxzNZAAPAgAZAAcJNxzNZAAPAgAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAAEAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgIJAgAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.',
Tw='Twohoof:BAAALgADCgYJCwAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Un='Unoboxo:BAAALgADCgEJAQABLgAECggJKwABAAofAA==.Unovoke:BAABLgAECn8rAAIBAAgJCh+EBgA0AgABAAgJCh+EBgA0AgAAAA==.',
Va='Valorash:BAABLgAECn8WAAMlAAYJOx+3DwDJAQAlAAYJ3hq3DwDJAQALAAQJjx9zmwBHAQAAAA==.Valorious:BAAALgAECgEJAQAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgMJAwAAAA==.Velintha:BAAALgAECgEJAgAAAA==.Venatrix:BAAALgAECgYJCwAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCAAEAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgIJAgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAAALgAECgYJCgAAAA==.Vonderick:BAAALgADCgkJKAAAAA==.Voodoodog:BAAALgAECgEJAgABLgAECgUJCwAEAAAAAA==.',
Vy='Vynlorellas:BAAALgADCgcJCAAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgADCgcJIgAAAA==.Watongo:BAAALgAECgUJBwAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgAAAA==.',
Wo='Woeify:BAAALgAECgcJEwAAAA==.',
Wy='Wynce:BAAALgADCgcJBwAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgEJAQAAAA==.Xarn:BAABLgAECn8hAAICAAkJtQcaLgB0AQACAAkJtQcaLgB0AQAAAA==.',
Xc='Xcïte:BAAALgAECgcJEAAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.',
Yo='Yourlock:BAAALgADCgUJBQAAAA==.',
Yu='Yuji:BAABLgAECn8YAAILAAcJcg14QQBFAQALAAcJcg14QQBFAQAAAA==.',
Za='Zalectra:BAACLgAFFH8NAAIOAAQJ8SCTAQCRAQAOAAQJ8SCTAQCRAQAuAAQKfywAAw4ACQm1JUMAAMMDAA4ACQm1JUMAAMMDABsAAgmlFgQVAI0AAAAA.',
Ze='Zelila:BAAALgADCgIJAgAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBQAAAA==.',
['Ål']='Ålloria:BAAALgAECgEJAQAAAA==.',
['ßl']='ßlackßetty:BAAALgADCgYJBwABLgADCgkJCQAEAAAAAA==.',
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

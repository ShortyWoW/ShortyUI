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

local lookup = {'Evoker-Augmentation','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Unholy','Evoker-Devastation','Paladin-Retribution','Hunter-Survival','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Monk-Windwalker','Evoker-Preservation','Monk-Mistweaver','Druid-Restoration','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Priest-Holy','Priest-Shadow','Priest-Discipline',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acehuntura:BAAALgAECgEJAQAAAA==.',
Ad='Adaric:BAAALgAECgQJBAAAAA==.',
Ai='Aidoneiscus:BAAALgAECgQJBQABLgAECggJIwABAK0hAA==.Aiyaiyai:BAAALgAECgYJBgAAAA==.',
Al='Alall:BAAALgADCgkJDAAAAA==.Aldara:BAAALgADCgQJBAAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.',
Am='Aminall:BAAALgADCgEJAgAAAA==.',
An='Andore:BAAALgAECgEJAQAAAA==.Anewbyss:BAAALgADCgUJBwAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgADCgcJGQAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBQAAAA==.',
Ap='Aposthmighty:BAAALgAECgMJBAAAAA==.',
Ar='Artemyss:BAAALgADCgEJAQAAAA==.',
As='Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgADCgMJBQAAAA==.Ashraki:BAAALgADCgEJAQAAAA==.Astraeal:BAAALgAECgMJAwAAAA==.',
At='Atreana:BAABLgAECn8YAAICAAcJshNjGwA8AQACAAcJshNjGwA8AQAAAA==.Attykus:BAABLgAECn8YAAIDAAgJIA80MQDoAQADAAgJIA80MQDoAQAAAA==.',
Av='Avalerion:BAAALgAECgQJBAAAAA==.Avij:BAAALgADCgQJBgABLgADCgYJCwAEAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgEJAQAAAA==.',
Ba='Bat:BAAALgADCgUJBgAAAA==.',
Be='Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgEJAQAAAA==.',
Bi='Bighoot:BAAALgAECgQJCAAAAA==.Bigmancow:BAABLgAECn8WAAIFAAgJoQkyCwCMAQAFAAgJoQkyCwCMAQAAAA==.Bigpoppapump:BAAALgAECgMJAwAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8XAAIGAAcJtQdMHgAVAQAGAAcJtQdMHgAVAQAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8QAAIHAAYJKxmtAADSAQAHAAYJKxmtAADSAQAuAAQKfxkAAgcACQkdIJkOAKUCAAcACQkdIJkOAKUCAAAA.',
Bo='Bodanky:BAAALgAECgMJBAAAAA==.Bormor:BAAALgAECgUJBQAAAA==.Bowdacious:BAAALgADCgkJFgAAAA==.',
Br='Brainpath:BAAALgAECgMJBAAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brumak:BAAALgADCgkJDgAAAA==.Bruno:BAAALgAECgYJEQAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
Ca='Cal:BAAALgADCgkJHQABLgAECgcJGQAIAJEZAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAABLgAECn8ZAAIIAAcJkRnUHgALAgAIAAcJkRnUHgALAgAAAA==.Camelshammy:BAAALgAECgMJAwAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgQJCAAEAAAAAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgMJBQAAAA==.',
Ce='Celoria:BAAALgADCgUJCQAAAA==.Century:BAAALgAECgYJDwAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAAALgAECggJEwAAAA==.',
Ci='Circa:BAAALgAECgUJCwAAAA==.Cithrel:BAAALgAECgcJDwAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAAEAAAAAA==.Crocklock:BAAALgAECgQJBwAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAAALgAECgUJEwAAAA==.Damnatio:BAAALgAECggJDgAAAA==.Damonster:BAAALgADCgIJAgAAAA==.Darkclement:BAAALgAECgYJBgAAAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgADCgkJHgAAAA==.Deathgriped:BAAALgAECgIJAgAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAAEAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCAAEAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgYJCgAEAAAAAA==.Drahalah:BAABLgAECn8WAAIJAAcJPB4EDwCgAQAJAAcJPB4EDwCgAQAAAA==.Drakeji:BAABLgAECn8XAAMBAAYJdwVqPgDxAAABAAYJdwVqPgDxAAAKAAMJyACTPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.',
Du='Dumplingg:BAAALgAECgcJCQAAAA==.',
Ea='Earthvoodoo:BAAALgAECgQJBwAAAA==.',
Eb='Ebonlight:BAAALgADCgcJDQAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgIJAgAAAA==.',
El='Elsyria:BAAALgADCgIJAgABLgAFFAQJCgALAB4gAA==.',
Em='Emmeri:BAAALgADCgcJCwABLgAECggJGAADACAPAA==.',
Ep='Epi:BAAALgAECgYJDAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJCwAAAA==.',
Ez='Ezale:BAAALgADCgUJBQAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAQAAAA==.Faramír:BAAALgADCgYJBAAAAA==.Fatébringer:BAAALgAECgUJBQAAAA==.',
Fe='Fennek:BAAALgAECgUJBQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Ga='Garaylo:BAACLgAFFH8KAAILAAQJHiA9BgCLAQALAAQJHiA9BgCLAQAuAAQKfyUAAgsACQkWJL8CAKwDAAsACQkWJL8CAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8fAAIMAAkJNyLkAgAHAwAMAAkJNyLkAgAHAwAAAA==.',
Gi='Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAAALgAECgcJDwAAAA==.',
Go='Goldenchi:BAAALgADCgUJBQAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmel:BAAALgADCgcJBwAAAA==.Grimmrot:BAAALgADCgkJGgAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJCQAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAAEAAAAAA==.Halstron:BAABLgAECn8YAAILAAcJgxZNDwCsAQALAAcJgxZNDwCsAQAAAA==.Harribel:BAAALgAECgUJCwAAAA==.',
He='Heliòs:BAAALgADCgkJDgAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8YAAQNAAgJ0BPLJgDcAQANAAgJ0BPLJgDcAQAOAAMJXgfOJACLAAAHAAEJhA2TLgAtAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECgQJBAAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8eAAIIAAgJyiBHAQB+AgAIAAgJyiBHAQB+AgAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAQAAAA==.',
Hy='Hylie:BAABLgAECn8bAAICAAgJ1Q1UWgC5AQACAAgJ1Q1UWgC5AQAAAA==.',
['Hè']='Hèlla:BAAALgADCgkJDAAAAA==.',
Ig='Ignisky:BAAALgAECgcJBwABLgAFFAMJCAAPAL4YAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Iz='Izgin:BAAALgAECgQJCAAAAA==.',
Ja='Jaime:BAAALgADCgYJCQABLgAECgYJCAAEAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJBQABLgADCgYJBgAEAAAAAA==.Jantar:BAAALgAECggJDgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAAALgAECgcJDwAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgUJBQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwAEAAAAAA==.',
Ju='Jugsy:BAAALgAECgYJCAAAAA==.Juliza:BAAALgADCgQJBAAAAA==.',
Ka='Kaligo:BAABLgAECn8dAAMNAAgJshNGCAB7AQANAAgJshNGCAB7AQAOAAQJrgSxIgCrAAAAAA==.Kalistus:BAAALgAECgQJCQAAAA==.Katreset:BAAALgAECgEJAQAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8aAAIQAAcJPSQuAQBzAgAQAAcJPSQuAQBzAgAAAA==.Keleion:BAABLgAECn8bAAIGAAcJcQ0iZQByAQAGAAcJcQ0iZQByAQAAAA==.Kevonjuravis:BAAALgAECgUJCQAAAA==.',
Kh='Khalyl:BAAALgAECgMJAwAAAA==.Kheart:BAAALgAECgEJAQAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGgAAAA==.',
Ko='Koder:BAABLgAECn8jAAQBAAgJrSGuBgASAwABAAgJrSGuBgASAwARAAIJDgKvRABKAAAKAAEJgBUXPQA6AAAAAA==.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgADCgQJBAAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAAEAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn8VAAIJAAYJ0RM9igBsAQAJAAYJ0RM9igBsAQAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilithxander:BAAALgAECgMJBAAAAA==.Lizzybordan:BAAALgADCgcJDAABLgADCgcJGQAEAAAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAAALgAECgQJBAAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.',
Ma='Mariskama:BAAALgAECgMJBQAAAA==.Markusthered:BAAALgADCgYJBgAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Meowimabear:BAAALgADCgkJEAABLgAECgkJHwAMADciAA==.Metal:BAAALgAECgQJBwAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgMJAwAAAA==.',
Mi='Mikkais:BAAALgAECgMJBAAAAA==.Minimini:BAABLgAECn8hAAISAAcJfhjdBgCdAQASAAcJfhjdBgCdAQAAAA==.',
Mo='Moolin:BAAALgAECgYJEAAAAA==.Moranthe:BAAALgAECgcJDAABLgAECggJCQAEAAAAAA==.Mordsyth:BAAALgADCgYJBgAAAA==.',
Mu='Muggypew:BAAALgAECgkJBQAAAA==.Munder:BAAALgAECgYJCgAAAA==.Mustymuppet:BAAALgAFFAEJAQAAAA==.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgADCgIJAgAAAA==.Mythuneran:BAAALgAECgQJDAAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAAALgAECgUJCwAAAA==.Nemini:BAAALgADCgkJGgAAAA==.Nena:BAAALgADCggJIgAAAA==.',
Ni='Ninjamage:BAAALgADCgIJAgAAAA==.Nistis:BAAALgAECgQJBwAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAAALgAECgQJBgAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAAALgAECgMJBAAAAA==.Notagain:BAACLgAFFH8TAAILAAYJtR6DAADDAQALAAYJtR6DAADDAQAuAAQKfyIAAgsACQk7IpMHAFoDAAsACQk7IpMHAFoDAAAA.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgADCgIJAgAAAA==.Nymphàdoria:BAAALgADCgUJCAAAAA==.Nyuxx:BAAALgAECgEJAQAAAA==.',
Ol='Olgreeneyes:BAAALgAECgEJAQAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAITAAYJChgmTABzAQATAAYJChgmTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJDwAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Peejean:BAAALgAECgYJBgAAAA==.Peybreak:BAAALgAECgEJAQABLgAECggJFwAUAFYcAA==.Peychi:BAAALgAECgMJAwABLgAECggJFwAUAFYcAA==.Peycicle:BAABLgAECn8XAAIUAAgJVhxKAQDOAgAUAAgJVhxKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECggJFwAUAFYcAA==.Peystruction:BAAALgADCgUJBQABLgAECggJFwAUAFYcAA==.Peytan:BAAALgAECgYJCgABLgAECggJFwAUAFYcAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAECgIJAgAAAA==.Pippa:BAAALgAECgUJCwAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAAALgAECgYJEgAAAA==.',
Po='Poetuck:BAABLgAECn8aAAIVAAcJaQ86MAAIAQAVAAcJaQ86MAAIAQAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAAEAAAAAA==.',
Pr='Proko:BAAALgAECgUJCwAAAA==.',
Ps='Psychovoodoo:BAAALgAECgEJAQAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.',
Qu='Quiver:BAAALgAECgYJDQAAAA==.',
['Qì']='Qìlen:BAAALgAECgQJCAAAAA==.',
Ra='Raein:BAAALgAECgYJEAAAAA==.Raginghog:BAAALgADCgkJEgAAAA==.Rainn:BAAALgAECgQJBAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Ralofurius:BAAALgADCgYJCwAAAA==.Rasril:BAAALgAECgUJBwAAAA==.Raze:BAAALgAECgIJAgAAAA==.',
Re='Red:BAAALgADCgcJDgAAAA==.Renicus:BAAALgADCgYJBwAAAA==.Renmare:BAAALgAECgUJCwAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Risotto:BAAALgADCgIJAgAAAA==.Riumi:BAAALgAECgMJAwAAAA==.Rivenxi:BAAALgADCgEJAQABLgAECgcJCwAEAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgQJBAAAAA==.',
Ru='Rubymoonbeam:BAAALgAECgUJCgAAAA==.Ruele:BAAALgAECggJCQAAAA==.Ruenan:BAABLgAECn8WAAMWAAgJViI7DQDUAgAWAAcJZCM7DQDUAgAXAAMJlhKdaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn8UAAIYAAgJPAuPCwA0AQAYAAgJPAuPCwA0AQAAAA==.Ryian:BAAALgADCgkJCQAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIZAAcJNgpFGADzAAAZAAcJNgpFGADzAAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIaAAYJXgElDgCPAAAaAAYJXgElDgCPAAAAAA==.Sapthat:BAABLgAECn8ZAAMbAAcJtiD7AwDqAQAbAAYJwCL7AwDqAQAcAAMJXBrjEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAAALgAECgYJCgAAAA==.Savepebble:BAAALgAECgYJCgAAAA==.',
Se='Seather:BAABLgAECn8aAAIdAAgJyRvFEwB4AgAdAAgJyRvFEwB4AgAAAA==.Seirin:BAAALgAECgYJEAAAAA==.Selendaa:BAAALgAECgQJBAAAAA==.Senadarra:BAACLgAFFH8FAAIXAAIJJw9PBQCkAAAXAAIJJw9PBQCkAAAuAAQKfykAAhcACAnEGpcBAOgBABcACAnEGpcBAOgBAAAA.Sephenroth:BAAALgAECgMJBAAAAA==.Serendipity:BAAALgADCgYJCQABLgAECgYJDAAEAAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAAALgAECgIJAgAAAA==.Sheri:BAAALgAECgQJDAAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAAALgAECgEJAQAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJBgAAAA==.',
Si='Sillygoose:BAACLgAFFH8OAAIVAAUJLhEkHgBSAQAVAAUJLhEkHgBSAQAuAAQKfx4AAhUACQlJIIgVACcDABUACQlJIIgVACcDAAAA.Sinadara:BAAALgAECgYJDQAAAA==.Sinïster:BAAALgADCgEJAQAAAA==.Siong:BAAALgADCgcJCgABLgAFFAQJCgALAB4gAA==.Siorknav:BAABLgAECn8VAAILAAgJiQxvKQD9AAALAAgJiQxvKQD9AAAAAA==.',
Sk='Skalar:BAAALgAECgQJBwAAAA==.Skodah:BAAALgADCgkJEQAAAA==.',
Sl='Släyr:BAAALgADCgIJAgAAAA==.',
So='Solunara:BAAALgADCgYJDwAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAAALgAECgQJBAAAAA==.Soup:BAABLgAECn8WAAIeAAgJcgfJAwBxAQAeAAgJcgfJAwBxAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAAALgAECggJDwAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgADCgYJBgAAAA==.Stovik:BAAALgAECgYJEwAAAA==.',
Sv='Sventhebrave:BAAALgAECgQJBAAAAA==.',
Sw='Sweeneytod:BAAALgADCgcJBwAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgIJAgAAAA==.Sylira:BAACLgAFFH8HAAIfAAMJ3wcFCgDGAAAfAAMJ3wcFCgDGAAAuAAQKfykAAx8ACQn7GxMKAKwCAB8ACQn7GxMKAKwCACAAAwlrCldSAIAAAAAA.Sylk:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takedown:BAACLgAFFH8IAAIPAAMJvhiKAwANAQAPAAMJvhiKAwANAQAuAAQKfyEAAw8ACAk/ITsCAAcDAA8ACAnbIDsCAAcDAAMABwkrGsUsAAECAAAA.Talleral:BAAALgAECgIJAwAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgADCgIJAgABLgAECggJFAAhAJYLAA==.Tankie:BAAALgADCgEJAQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgADCgkJCQAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgMJAwAAAA==.Tharonix:BAAALgAECgQJBwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgADCgcJCgAAAA==.',
Ti='Tic:BAAALgAECgQJBAAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAAALgAECgYJEwAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAAEAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgIJAgAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJDwAAAA==.',
Tw='Twohoof:BAAALgADCgYJBgAAAA==.',
['Tä']='Tänithðurden:BAAALgADCgYJBgAAAA==.',
Un='Unoboxo:BAAALgADCgEJAQABLgAECggJJwABAAUeAA==.Unovoke:BAABLgAECn8nAAIBAAgJBR6+AgATAgABAAgJBR6+AgATAgAAAA==.',
Va='Valorash:BAAALgAECgYJEAAAAA==.Valorious:BAAALgADCgkJFQAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgMJAwAAAA==.Velintha:BAAALgAECgEJAQAAAA==.Venatrix:BAAALgAECgMJBQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCAAEAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidu:BAAALgADCgUJBQAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAAALgAECgMJBAAAAA==.Vonderick:BAAALgADCgkJHwAAAA==.Voodoodog:BAAALgAECgEJAgABLgAECgQJBwAEAAAAAA==.',
Vy='Vynlorellas:BAAALgADCgcJCAAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgADCgcJGQAAAA==.Watongo:BAAALgAECgUJBwAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgAAAA==.',
Wo='Woeify:BAAALgAECgcJEQAAAA==.',
Wy='Wynce:BAAALgADCgcJBwAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgEJAQAAAA==.Xarn:BAABLgAECn8hAAICAAkJtQc7EgB/AQACAAkJtQc7EgB/AQAAAA==.',
Xc='Xcïte:BAAALgAECgYJDQAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.',
Yo='Yourlock:BAAALgADCgUJBQAAAA==.',
Yu='Yuji:BAAALgAECgYJEQAAAA==.',
Za='Zalectra:BAACLgAFFH8HAAIMAAQJ+xnNAQAqAQAMAAQJ+xnNAQAqAQAuAAQKfycAAgwACQl9I0MAAMMDAAwACQl9I0MAAMMDAAAA.',
Ze='Zelila:BAAALgADCgIJAgAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgADCgEJAQAAAA==.',
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

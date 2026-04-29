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

local lookup = {'Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Monk-Brewmaster','Monk-Windwalker','Druid-Balance','Druid-Restoration','Evoker-Preservation','Druid-Feral','Warlock-Demonology','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Evoker-Augmentation','Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Priest-Holy','Druid-Guardian','Priest-Discipline','Shaman-Elemental','Hunter-BeastMastery','Hunter-Survival','Paladin-Holy','Priest-Shadow','DemonHunter-Vengeance','Rogue-Outlaw','Mage-Arcane','DemonHunter-Devourer',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeshath:BAAALgADCgIJAgAAAA==.',
Af='Affae:BAAALgAECgUJCwAAAA==.',
Ag='Agrios:BAAALgADCgUJBQAAAA==.',
Ak='Ak:BAABLgAECn8bAAIBAAcJ+x2kWAAvAgABAAcJ+x2kWAAvAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgUJDwACAAAAAA==.',
Am='Amare:BAAALgADCgcJBwAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgADCgUJBQAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.',
Ar='Araxe:BAABLgAECn8UAAIDAAYJ4hFoiQBuAQADAAYJ4hFoiQBuAQAAAA==.Arroyo:BAABLgAECn8XAAMDAAYJ1iFSSAAaAgADAAYJvCBSSAAaAgAEAAQJyRuaHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Askadar:BAABLgAECn8gAAIFAAgJLCapAwAaAwAFAAgJLCapAwAaAwAAAA==.',
At='Atinyhorse:BAAALgAECgYJCwAAAA==.Atryx:BAAALgAECgMJBgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgQJBwACAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.',
Ba='Baheem:BAAALgAECgEJAQAAAA==.Bams:BAAALgAECgUJCwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgUJCQAAAA==.Bauer:BAAALgADCgQJBAABLgADCgQJBAACAAAAAA==.',
Be='Benel:BAAALgAECgQJBQAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8eAAIGAAgJ6yBOGwByAgAGAAgJ6yBOGwByAgAAAA==.Bigtotempole:BAAALgAECgUJCgAAAA==.',
Bl='Blahwithpets:BAAALgAECgUJDwAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgIJAwABLgAECgYJDgACAAAAAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgADCggJEwAAAA==.Blurt:BAAALgADCgUJBQAAAA==.',
Bo='Bobble:BAAALgAECgcJEgAAAA==.Bohelranus:BAAALgADCgkJEAAAAA==.Boneman:BAAALgADCgQJBAAAAA==.',
Br='Breake:BAAALgAECgUJDAAAAA==.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAAALgAECgEJAQAAAA==.',
Ca='Cailan:BAAALgADCgQJBQAAAA==.Caladiir:BAAALgAECgUJBQABLgAECgkJFgAHANgfAA==.Cattiebuzz:BAAALgAECgEJAQABLgAECgYJDgACAAAAAA==.',
Ce='Cerealmilk:BAAALgADCgcJBwABLgAECgQJBwACAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBAACAAAAAA==.Chitung:BAAALgADCgQJBAAAAA==.Christopher:BAACLgAFFH8GAAIBAAMJlh8GEAAQAQABAAMJlh8GEAAQAQAuAAQKfxkAAgEACAnMIJMtALsCAAEACAnMIJMtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJCwABLgAECggJFgAIAMwNAA==.Cindragos:BAAALgAECgEJAQABLgAECgUJDQACAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8PAAIFAAUJVxnZAQA/AQAFAAUJVxnZAQA/AQAuAAQKfyUAAgUACAkAIhwEAAoDAAUACAkAIhwEAAoDAAAA.',
Cr='Creepychaos:BAAALgADCgkJEQABLgAECgcJGAADABMFAA==.Creepydemise:BAABLgAECn8YAAIDAAcJEwUfJgD8AAADAAcJEwUfJgD8AAAAAA==.Croixsmash:BAABLgAECn8cAAIGAAcJYRxBIgBDAgAGAAcJYRxBIgBDAgAAAA==.',
Cu='Custodian:BAAALgAECgMJAwAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgADCgkJDgAAAA==.Danoa:BAAALgADCgYJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAAALgAECgQJBwAAAA==.Davennial:BAAALgAECgcJEAAAAA==.Dawnn:BAAALgAECgQJBgAAAA==.Dayman:BAAALgAECgEJAQAAAA==.',
De='Deanwnchestr:BAAALgAECgQJBAAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAAALgAECgYJDAAAAA==.Demise:BAAALgAECgQJBQAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgUJBQAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diophantus:BAAALgAECgIJBAABLgAECgcJFQAIAGgfAA==.Divinity:BAAALgADCgMJAwAAAA==.',
Dm='Dmncgdss:BAAALgAECgQJBAAAAA==.',
Do='Doregoran:BAAALgAECgQJBwAAAA==.Dovairous:BAAALgAECgMJBgAAAA==.',
Dr='Draakell:BAAALgAECgQJAgAAAA==.Dracopeet:BAAALgAECgUJDwAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgADCgMJAwAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAAALgAECgUJCgAAAA==.',
El='Elawen:BAAALgADCgYJFAAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAABLgAECn8ZAAMJAAgJkxmSGQA6AgAJAAgJkxmSGQA6AgAKAAQJagWArABtAAAAAA==.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgMJBgAAAA==.',
En='Enlargdcrit:BAAALgADCgcJDQAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAAALgAECgUJCQAAAA==.Erodoria:BAAALgAECgQJBwAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgYJDwACAAAAAA==.',
Ev='Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgIJAgAAAA==.Evoke:BAAALgAECgMJAwAAAA==.',
Ex='Exzanthia:BAAALgADCggJCAAAAA==.',
Ey='Eyln:BAAALgAECgYJEQAAAA==.',
Fa='Falkor:BAABLgAECn8YAAILAAgJURjDEAAvAgALAAgJURjDEAAvAgAAAA==.Fanir:BAAALgADCgMJAwAAAA==.Fayway:BAABLgAECn8hAAIKAAgJ0yENAQD8AgAKAAgJ0yENAQD8AgAAAA==.',
Fe='Ferral:BAAALgAECgYJDgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAAALgAECgYJEQAAAA==.Firepower:BAAALgAECgUJCQABLgAECggJHgAMAEoSAA==.Fistatoosh:BAAALgAECgcJDQAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJHgAMAEoSAA==.',
Fr='Fries:BAEALgAECgcJCAABLgAECggJFQANACgfAA==.',
Ga='Galdavin:BAABLgAECn8XAAIOAAgJnBqfKQB+AgAOAAgJnBqfKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgACAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAAALgAECgcJEQAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAAALgAECgQJAwAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgADCgcJAwABLgAECgMJBAACAAAAAA==.',
Gr='Groddz:BAAALgAECgMJAwAAAA==.Grrum:BAAALgAECgQJBAAAAA==.',
Ha='Hanjo:BAAALgAECgUJDwAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIPAAcJixUoNgCqAQAPAAcJixUoNgCqAQAAAA==.Hardare:BAABLgAECn8WAAIIAAgJzA3pJACvAQAIAAgJzA3pJACvAQAAAA==.Hayali:BAAALgAECgYJDQAAAA==.',
He='Helledrians:BAAALgAECgQJBQAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJFgAIAMwNAA==.',
Hu='Hugostiglet:BAAALgADCgEJAQAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hypatia:BAABLgAECn8VAAIIAAcJaB+6DgCRAgAIAAcJaB+6DgCRAgAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAABLgAECn8ZAAIHAAgJOh5hFgBWAgAHAAgJOh5hFgBWAgAAAA==.',
In='Incite:BAABLgAECn8ZAAMQAAgJRg5FAgCGAQAQAAgJAA1FAgCGAQARAAUJ+g2HQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgIJAgAAAA==.',
Ja='Jarrel:BAAALgADCgUJBQAAAA==.',
Je='Jellybreak:BAABLgAECn8WAAIJAAYJLRTqNwBaAQAJAAYJLRTqNwBaAQAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAAALgAECgUJDwAAAA==.Kaelei:BAAALgADCgkJHwAAAA==.Kamine:BAAALgAECgMJAwAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAAALgAECgQJDgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAAALgAECgYJEQAAAA==.Kensington:BAAALgAECgYJCgAAAA==.',
Ki='Kiku:BAABLgAECn8bAAISAAgJOCABAQCbAgASAAgJOCABAQCbAgAAAA==.Kim:BAAALgAECgUJCAAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.',
Ko='Korlock:BAABLgAECn8kAAQNAAkJLhwnNAA8AgANAAgJXBsnNAA8AgATAAEJlRYgCABGAAAUAAEJAACdbAA7AAAAAA==.',
Kr='Kreepywife:BAAALgADCgkJEgAAAA==.Krelbelorll:BAAALgADCgQJBAAAAA==.Krowley:BAAALgAECgQJBwAAAA==.',
Ku='Kuzan:BAACLgAFFH8HAAIBAAMJ3xVzDwATAQABAAMJ3xVzDwATAQAuAAQKfxwAAgEABwl3IfI2AJgCAAEABwl3IfI2AJgCAAAA.',
La='Lacious:BAAALgADCgEJAQABLgAECgYJDgACAAAAAA==.Ladýshinobu:BAAALgAECgcJDwAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn8UAAIVAAYJkxJgGgA9AQAVAAYJkxJgGgA9AQAAAA==.Lediaa:BAAALgADCgcJBwAAAA==.',
Li='Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgMJBAAAAA==.Lineurathrot:BAAALgADCgIJAgAAAA==.Littlespyone:BAAALgAECgMJBAAAAA==.',
Lo='Locholovis:BAAALgAECgYJEAAAAA==.Locklicous:BAAALgAECgUJBQAAAA==.Longhorse:BAACLgAFFH8KAAIEAAQJVRolAgBEAQAEAAQJVRolAgBEAQAuAAQKfywAAwMACQnjI3MFADACAAQACQk/IMkFAOACAAMABgnTJXMFADACAAAA.Longknight:BAAALgADCgcJCgAAAA==.Longr:BAAALgADCgkJEAAAAA==.Lorna:BAAALgAECgEJAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJAANAC4cAA==.',
Lu='Lumi:BAAALgAECgQJCgAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAAALgAECgYJDAABLgAECgkJFgAWAJ4XAA==.Lumpia:BAAALgAFFAIJAgAAAA==.',
Ly='Lyrinir:BAAALgAECggJEQAAAA==.Lyrium:BAAALgAECgUJDgABLgAECggJEQACAAAAAA==.',
Ma='Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgQJBwAAAA==.Mairon:BAAALgAECgEJAwAAAA==.Malvorak:BAAALgAECgQJBAAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mavarasie:BAAALgAECgIJBAAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJBQAAAA==.',
Me='Mechacattie:BAAALgAECgYJDgAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAAALgAECgUJDwAAAA==.Mercas:BAAALgADCgMJAwABLgAECggJGwAXAOoZAA==.Mezi:BAABLgAECn8UAAIWAAYJ5iC8FQAvAgAWAAYJ5iC8FQAvAgAAAA==.Mezmera:BAAALgADCgUJBgAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAABLgAECn8WAAMWAAkJnhduKACtAQAWAAYJ+xluKACtAQAYAAcJKBHDIQCFAQAAAA==.',
Mo='Mofro:BAAALgADCgQJBAABLgADCgQJBAACAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIQAOABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8VAAIZAAcJwQxDDgAfAQAZAAcJwQxDDgAfAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgEJAgACAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8FAAIIAAMJcxybCQDPAAAIAAMJcxybCQDPAAAuAAQKfxYAAggABwntJAQKANcCAAgABwntJAQKANcCAAAA.Mulron:BAAALgAECgUJCAAAAA==.',
My='Myrica:BAAALgAECgEJAQAAAA==.',
Na='Natajapar:BAAALgADCgQJBAABLgADCgcJCgACAAAAAA==.',
Ne='Nefesh:BAAALgADCgUJBQAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAQAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8FAAIJAAMJHgf9FgCKAAAJAAMJHgf9FgCKAAAuAAQKfygAAgkACQnfFdAUAGsCAAkACQnfFdAUAGsCAAAA.',
On='Onlyfeigns:BAAALgADCgQJBAAAAA==.',
Or='Orileluu:BAAALgADCgYJCgAAAA==.',
Pa='Paisho:BAAALgAECgEJAQAAAA==.Palliera:BAAALgADCgYJBgAAAA==.Pawmuck:BAAALgAECgQJBAAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgIJAgAAAA==.',
Pl='Plaguebeard:BAABLgAECn8WAAMDAAcJBx97PABFAgADAAcJBx97PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAAALgAECgUJDwAAAA==.',
Po='Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Progression:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAAALgAECgUJCQAAAA==.Rainthefire:BAABLgAECn8mAAIaAAkJzhYlBQAlAgAaAAkJzhYlBQAlAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgADCgUJCAAAAA==.Ravinfire:BAAALgAECgQJBAAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgMJAwAAAA==.Redoxx:BAAALgAECgYJCAAAAA==.Restofarian:BAAALgAFFAMJBAAAAA==.',
Ri='Righteous:BAAALgAECgQJCQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAABLgAECn8gAAMaAAgJvSBnFgCFAgAaAAcJ/iFnFgCFAgAbAAcJChzNEAC2AQAAAA==.',
Ru='Rutikee:BAABLgAECn8YAAIKAAgJkQ9DDgBxAQAKAAgJkQ9DDgBxAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIWAAgJlBW1FgAmAgAWAAgJlBW1FgAmAgABLgAECggJIQANAFkcAA==.Saeris:BAAALgADCggJCAABLgADCgMJAwACAAAAAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Satorugojo:BAAALgAECgQJBAAAAA==.Savior:BAAALgADCggJGQAAAA==.',
Se='Seabush:BAAALgADCgQJBAAAAA==.Seastorm:BAAALgADCgIJAgAAAA==.Seizon:BAAALgADCggJCgAAAA==.Semila:BAAALgADCgQJBAABLgADCgcJCgACAAAAAA==.Senseicanz:BAAALgADCgEJAQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgADCgIJAgABLgAECgUJDwACAAAAAA==.Serom:BAAALgAECgQJBAAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8WAAIHAAkJ2B+sCwDTAgAHAAkJ2B+sCwDTAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgADCgQJBAACAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sherunn:BAAALgAECgQJBAAAAA==.Shiftydon:BAAALgADCgkJDAAAAA==.Shimakaze:BAABLgAECn8UAAIaAAYJIAjfHQARAQAaAAYJIAjfHQARAQAAAA==.Shirvana:BAAALgADCgcJCgAAAA==.Shooters:BAAALgAECgYJEQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgACAAAAAA==.Shymistress:BAABLgAECn8ZAAIaAAgJxBYaCQDXAQAaAAgJxBYaCQDXAQAAAA==.Shåmmy:BAABLgAECn8cAAIPAAgJ+Qu0OgCXAQAPAAgJ+Qu0OgCXAQAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAAALgAECgUJDQAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn8YAAIMAAYJ6ReOBABRAQAMAAYJ6ReOBABRAQAAAA==.Skrinkles:BAAALgAECgEJAQAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8MAAIcAAUJTiHfAADVAQAcAAUJTiHfAADVAQAuAAQKfyYAAxwACQnpH+sRAIMCABwACQnpH+sRAIMCAA4ABwkKG59BACACAAAA.Slorth:BAABLgAECn8gAAIDAAgJ8xmIDAC9AQADAAgJ8xmIDAC9AQAAAA==.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn8dAAIHAAgJbgdVCgBJAQAHAAgJbgdVCgBJAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Spicydemon:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgADCgcJCQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAAALgAECgkJEgAAAA==.',
St='Starwolfy:BAAALgADCgQJBAAAAA==.Stoneboot:BAAALgAECgYJEAAAAA==.',
Su='Sumaria:BAAALgAECgQJBAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8eAAIMAAgJShKRCwAGAgAMAAgJShKRCwAGAgAAAA==.Tandria:BAAALgADCggJDQAAAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAAALgAECgYJDQAAAA==.',
Te='Teakaachu:BAAALgAECgUJCgAAAA==.Terdanator:BAAALgAECgUJCgAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn8hAAQNAAgJWRwYCADwAQANAAgJWRwYCADwAQATAAEJAAA7KABQAAAUAAEJzgfleAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAAALgAECgYJEAAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgADCgkJEQABLgAECgYJFAATAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tridius:BAAALgAECgUJCgAAAA==.',
Tu='Turdanator:BAABLgAECn8hAAMdAAgJeg+NCwA5AQAdAAgJeg+NCwA5AQAWAAYJGw1cQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.',
Ur='Uraenus:BAAALgAECgUJBgAAAA==.Urahrotar:BAAALgADCgMJAwAAAA==.Uriah:BAAALgAECgMJAwAAAA==.Ursúla:BAAALgAECgEJAQABLgAECggJGQAJAJMZAA==.Uryu:BAAALgAECgEJAQAAAA==.Urïah:BAAALgADCgUJBQABLgAECgMJAwACAAAAAA==.',
Ut='Utherr:BAAALgAECgYJCgAAAA==.',
Va='Valaravaus:BAAALgADCggJCAAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgADCgcJEwAAAA==.',
Ve='Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violinmax:BAAALgAECgMJBQAAAA==.',
Vo='Voidnova:BAAALgADCgQJBAAAAA==.Vonnie:BAAALgAECgQJBAAAAA==.',
Vy='Vynlerinis:BAABLgAECn8UAAIeAAgJph92AAB3AgAeAAgJph92AAB3AgAAAA==.',
Wa='Wardestroyer:BAAALgAECgEJAQAAAA==.Wardwhelp:BAAALgAECgQJBwAAAA==.',
Wi='Wifehaver:BAABLgAECn8gAAIHAAgJ1h7vEgB6AgAHAAgJ1h7vEgB6AgAAAA==.Winniedapoo:BAABLgAECn8mAAINAAgJTRftPwAOAgANAAgJTRftPwAOAgAAAA==.',
Wo='Wooloo:BAACLgAFFH8NAAQUAAcJMRkUAwBvAQANAAQJlRkRDQBzAQAUAAQJ+xgUAwBvAQATAAEJAADEBABZAAAuAAQKfx0AAw0ACAkPJRQXAMoCAA0ABwkPJRQXAMoCABQABAlPHXsgAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8VAAIGAAcJJR17HgBcAgAGAAcJJR17HgBcAgAAAA==.',
Xk='Xkwon:BAAALgAECgUJBwAAAA==.Xkwøn:BAACLgAFFH8HAAIfAAMJZBHvAAAGAQAfAAMJZBHvAAAGAQAuAAQKfyEAAh8ACAl4HNIBAKMCAB8ACAl4HNIBAKMCAAAA.',
Xu='Xunie:BAAALgADCgcJBwAAAA==.',
Xx='Xximage:BAABLgAECn8ZAAMgAAgJmSRfAQDIAgAgAAgJmSRfAQDIAgABAAEJAACCWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8VAAIhAAYJ1hLqHgASAQAhAAYJ1hLqHgASAQAAAA==.',
Zb='Zbrute:BAAALgAECgUJCAAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAAAAA==.Zefphenn:BAAALgAECgQJBgAAAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8UAAIDAAgJgReACwDKAQADAAgJgReACwDKAQAAAA==.',
['Ðo']='Ðondon:BAAALgADCgEJAQAAAA==.Ðoppelgänger:BAAALgADCgEJAQAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8LAAIBAAMJExUfEQAJAQABAAMJExUfEQAJAQAuAAQKfyYAAgEACAmqHSpKAFkCAAEACAmqHSpKAFkCAAAA.',
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

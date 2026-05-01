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

local lookup = {'Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','DemonHunter-Devourer','Warrior-Fury','Paladin-Holy','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Paladin-Retribution','Druid-Balance','Druid-Restoration','Shaman-Restoration','Evoker-Preservation','Druid-Feral','Warlock-Demonology','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Warlock-Affliction','Evoker-Augmentation','Warlock-Destruction','Paladin-Protection','Priest-Discipline','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Shaman-Elemental','Hunter-Survival','Priest-Shadow','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.',
Af='Affae:BAAALgAFFAMJBAAAAA==.',
Ag='Agrios:BAAALgAECgQJBAAAAA==.',
Ak='Ak:BAABLgAECn8gAAIBAAcJBSC2KADCAQABAAcJBSC2KADCAQAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgUJEAACAAAAAA==.',
Am='Amare:BAAALgADCgcJBwAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgADCgUJBQAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgADCgMJAwAAAA==.',
Ar='Araxe:BAABLgAECn8ZAAIDAAYJ9RcgTwASAQADAAYJ9RcgTwASAQAAAA==.Arroyo:BAABLgAECn8eAAMDAAgJcSB3DwBEAgADAAgJViB3DwBEAgAEAAQJyRubHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Askadar:BAABLgAECn8lAAIFAAgJnCasAwAaAwAFAAgJnCasAwAaAwAAAA==.',
At='Atinyhorse:BAABLgAECn8YAAIGAAcJRwtIOAACAQAGAAcJRwtIOAACAQAAAA==.Atryx:BAAALgAECgMJCAAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQACAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.',
Ba='Baheem:BAAALgAECgMJBAAAAA==.Bams:BAAALgAECgYJEQAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDgAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8hAAIHAAgJNiFNGwByAgAHAAgJNiFNGwByAgAAAA==.Bighoofprint:BAAALgADCgQJAwAAAA==.Bigtotempole:BAAALgAECgUJCgAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAAALgAECgUJDwAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgIJAwABLgAECgcJEQACAAAAAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgMJAwAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgADCgUJBQAAAA==.',
Bo='Bobble:BAABLgAECn8UAAIIAAcJCha/NACqAQAIAAcJCha/NACqAQAAAA==.Bohelranus:BAAALgADCgkJEAAAAA==.Boneman:BAAALgADCgQJBAAAAA==.Booqt:BAAALgADCgUJBQABLgAECggJEAACAAAAAA==.',
Br='Breake:BAAALgAECgUJDAAAAA==.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAAALgAECgUJBgAAAA==.',
Ca='Cailan:BAAALgADCgQJBQAAAA==.Caladiir:BAAALgAECgUJBQABLgAECgkJFgAJAL4fAA==.Cattiebuzz:BAAALgAECgIJAgABLgAECgcJFwAKAEMcAA==.',
Ce='Cerealmilk:BAAALgADCgcJCgABLgAECgQJCAACAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgACAAAAAA==.Childishbro:BAAALgADCgIJAgAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAACAAAAAA==.Christopher:BAACLgAFFH8KAAIBAAQJsBoyGwBdAQABAAQJsBoyGwBdAQAuAAQKfxkAAgEACAnMIJYtALsCAAEACAnMIJYtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJFgALAMwNAA==.Cindragos:BAAALgAECgEJAQABLgAECgUJDQACAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8TAAIFAAUJ+R4SAwBzAQAFAAUJ+R4SAwBzAQAuAAQKfyUAAgUACAkAIh8EAAoDAAUACAkAIh8EAAoDAAAA.',
Cr='Creepychaos:BAAALgADCgkJGgABLgAECggJIAADADwGAA==.Creepydemise:BAABLgAECn8gAAIDAAgJPAZoOwBNAQADAAgJPAZoOwBNAQAAAA==.Croixsmash:BAABLgAECn8dAAIHAAgJzRhBIgBDAgAHAAgJzRhBIgBDAgAAAA==.Croixtemplar:BAAALgADCggJCAAAAA==.',
Cu='Custodian:BAAALgAECgQJAwAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgADCgkJDgAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAAALgAECgYJDQAAAA==.Davennial:BAABLgAECn8cAAIMAAYJ2g8oVgANAQAMAAYJ2g8oVgANAQAAAA==.Dawnn:BAAALgAECgQJCgAAAA==.Dayman:BAAALgAECgEJAgAAAA==.',
De='Deanwnchestr:BAAALgAECgYJCgAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAAALgAECgcJEgAAAA==.Demise:BAAALgAECgQJBgAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJCwAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diophantus:BAAALgAECgIJBAABLgAECggJHAALABwhAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJBwAAAA==.',
Do='Doregoran:BAAALgAECgQJCwAAAA==.Dovairous:BAAALgAECgQJCgAAAA==.',
Dr='Draakell:BAAALgAECgQJAwAAAA==.Dracopeet:BAAALgAECgUJEAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgADCgMJAwAAAA==.',
Du='Dudè:BAAALgADCgkJCQAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAAALgAECgYJEAAAAA==.',
El='Elawen:BAAALgADCgYJFAAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8FAAINAAIJUhKnFgCkAAANAAIJUhKnFgCkAAAuAAQKfxwAAw0ACQm+GpIZADoCAA0ACQm+GpIZADoCAA4ABAlqBYqsAG0AAAEuAAUUAwkEAAIAAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgQJCAAAAA==.',
En='Enlargdcrit:BAAALgADCgcJDQAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAAALgAECgYJDwAAAA==.Erodoria:BAAALgAECgUJDAAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgAAAA==.',
Ev='Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAECgMJAwABLgAFFAMJBwAPAOgRAA==.',
Ex='Exzanthia:BAAALgAECgEJAgAAAA==.',
Ey='Eyln:BAAALgAECgYJEQAAAA==.',
Fa='Falkor:BAABLgAECn8gAAIQAAgJsRjJBgDVAQAQAAgJsRjJBgDVAQAAAA==.Fanir:BAAALgADCgMJAwAAAA==.Fatkid:BAAALgAECgcJAQAAAA==.Fayway:BAABLgAECn8pAAIOAAgJ0yEpBADrAgAOAAgJ0yEpBADrAgAAAA==.',
Fe='Ferral:BAAALgAECgcJEQAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAAALgAECgYJEQAAAA==.Firepower:BAAALgAECgYJDwABLgAECggJHwARAJYTAA==.Fistatoosh:BAABLgAECn8UAAIJAAgJ4iIZBAB5AgAJAAgJ4iIZBAB5AgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJHwARAJYTAA==.',
Fr='Fries:BAEALgAECgcJDgABLgAFFAQJBgASAKIPAA==.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIMAAgJnBqeKQB+AgAMAAgJnBqeKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgACAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgACAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAAALgAECgcJEQAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAAALgAECgQJBwAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgADCggJCwABLgAECgMJBAACAAAAAA==.',
Gr='Groddz:BAAALgAECgYJCQAAAA==.Grrum:BAAALgAECgYJCgAAAA==.',
Ha='Hanjo:BAAALgAECgUJEAAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIPAAcJixUqNgCqAQAPAAcJixUqNgCqAQAAAA==.Hardare:BAABLgAECn8WAAILAAgJzA3rJACvAQALAAgJzA3rJACvAQAAAA==.Hatookorr:BAAALgAECgQJBAABLgAECggJHwARAJYTAA==.Hayali:BAAALgAECgYJEwAAAA==.',
He='Helledrians:BAAALgAECgQJBQAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJFgALAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hypatia:BAABLgAECn8cAAILAAgJHCEzBQBLAgALAAgJHCEzBQBLAgAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAABLgAECn8bAAIJAAgJ7R9jFgBWAgAJAAgJ7R9jFgBWAgAAAA==.',
In='Incite:BAABLgAECn8eAAMTAAgJhQ6iDwAWAQATAAgJgA6iDwAWAQAUAAUJ+g2LQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jarrel:BAAALgAECgIJAwAAAA==.',
Je='Jellybreak:BAABLgAECn8dAAMNAAcJABQkFwBGAQANAAcJABQkFwBGAQAVAAMJIAiVHQA4AAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAAALgAECgUJEAAAAA==.Kaelei:BAAALgADCgkJIgAAAA==.Kamine:BAAALgAECgQJCAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAAALgAECgQJDwAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8TAAMWAAYJUiDFBAApAgAWAAYJUiDFBAApAgASAAMJnBXixgDLAAAAAA==.Kensington:BAAALgAECgYJEAAAAA==.',
Ki='Kiku:BAABLgAECn8fAAIXAAgJVyNTAgDVAgAXAAgJVyNTAgDVAgAAAA==.Kim:BAAALgAECgYJDgAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQSAAkJ5x0oNAA8AgASAAgJFR0oNAA8AgAWAAEJlRYIDwBGAAAYAAEJAACkbAA7AAAAAA==.',
Kr='Kreepywife:BAAALgADCgkJGwAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAAALgAECgYJDQAAAA==.',
Ku='Kuzan:BAACLgAFFH8KAAIBAAQJMhsVFABwAQABAAQJMhsVFABwAQAuAAQKfx0AAgEABwl3Ifc2AJgCAAEABwl3Ifc2AJgCAAAA.',
Ky='Kyoyama:BAAALgADCgEJAQABLgAECggJFQASAIAfAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgcJFwAKAEMcAA==.Ladýshinobu:BAABLgAECn8VAAIIAAcJ7QlzJwAPAQAIAAcJ7QlzJwAPAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn8aAAIZAAYJzRZWDQAqAQAZAAYJzRZWDQAqAQAAAA==.Lediaa:BAAALgADCgcJBwAAAA==.',
Li='Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgMJBAAAAA==.Lineurathrot:BAAALgADCgMJAwAAAA==.Littlespyone:BAAALgAECgMJBAAAAA==.',
Lo='Locholovis:BAABLgAECn8VAAIYAAYJ2gseCwDxAAAYAAYJ2gseCwDxAAAAAA==.Locklicous:BAAALgAECgYJCQAAAA==.Longhorse:BAACLgAFFH8PAAIEAAUJyh98AwB3AQAEAAUJyh98AwB3AQAuAAQKfzAAAwQACQnWJMYFAOACAAQACQmQIsYFAOACAAMABgnTJe4XAPsBAAAA.Longknight:BAAALgADCgcJCgAAAA==.Longr:BAAALgADCgkJGAAAAA==.Lorna:BAAALgAECgYJBwAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgASAOcdAA==.',
Lu='Lumi:BAAALgAECgYJDwABLgAECgcJAQACAAAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAAALgAFFAEJAQABLgAFFAMJBgAaAOgUAA==.Lumpia:BAAALgAFFAIJAgAAAA==.',
Ly='Lyrinir:BAAALgAECggJEgAAAA==.Lyrium:BAABLgAECn8YAAMbAAcJpRy8CgC4AQAbAAUJDB+8CgC4AQAcAAYJwRLeEQAkAQABLgAECggJEgACAAAAAA==.',
Ma='Madar:BAAALgAECgUJBQAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Mairon:BAAALgAECgMJBQAAAA==.Malvorak:BAAALgAECgYJCgAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mavarasie:BAAALgAECgIJBAAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJBwAAAA==.',
Me='Mechacattie:BAABLgAECn8XAAIKAAcJQxxgFQDnAQAKAAcJQxxgFQDnAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAgAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAAALgAECgUJDwAAAA==.Mercas:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Mezi:BAABLgAECn8bAAIdAAcJ/SDmBQBfAgAdAAcJ/SDmBQBfAgAAAA==.Mezmera:BAAALgADCgUJBgAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIaAAMJ6BQBEAAJAQAaAAMJ6BQBEAAJAQAuAAQKfxYAAx0ACQmeF24oAK0BAB0ABgn7GW4oAK0BABoABwkoEcMhAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAACAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAMABghAA==.Moneyshotinc:BAAALgAECgkJBgABLgAECggJIwAMABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8WAAIeAAgJkgzAGABMAQAeAAgJkgzAGABMAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgEJAgACAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8JAAILAAQJaiRLAQCiAQALAAQJaiRLAQCiAQAuAAQKfxYAAgsABwntJAUKANcCAAsABwntJAUKANcCAAAA.Mulron:BAAALgAECgYJDgAAAA==.',
My='Myrica:BAAALgAECgIJAgAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgADCgQJBAABLgAECgQJBQACAAAAAA==.',
Ne='Nefesh:BAAALgADCgUJBQAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAQAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8JAAINAAQJRg80DAAyAQANAAQJRg80DAAyAQAuAAQKfzAAAg0ACQkGFs0UAGsCAA0ACQkGFs0UAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Or='Orileluu:BAAALgADCgYJEAAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgADCgYJBgAAAA==.Pawmuck:BAAALgAECgYJCgAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgIJAgAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMDAAcJBx9+PABFAgADAAcJBx9+PABFAgAEAAUJCRihJwABAQAAAA==.Plagueblade:BAAALgAECgUJEAAAAA==.',
Po='Poof:BAAALgADCgIJAgABLgAECgQJCAACAAAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAAALgADCgEJAQAAAA==.Progression:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAAALgAECgYJDwAAAA==.Rainthefire:BAABLgAECn8vAAIKAAkJ+RicCwBHAgAKAAkJ+RicCwBHAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgADCgUJCAAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgMJBgAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8HAAIPAAMJ6BGYGQDDAAAPAAMJ6BGYGQDDAAAuAAQKfxUAAg8ACAl+HUgXAFsCAA8ACAl+HUgXAFsCAAAA.',
Ri='Rift:BAAALgAECgEJAQAAAA==.Righteous:BAAALgAECgYJDwAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAABLgAECn8lAAMKAAgJviBnFgCFAgAKAAcJ/iFnFgCFAgAfAAgJbRrNEAC2AQAAAA==.',
Ru='Rutikee:BAABLgAECn8gAAIOAAgJDxIDGgCwAQAOAAgJDxIDGgCwAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIdAAgJlBW8FgAmAgAdAAgJlBW8FgAmAgABLgAECggJIQASAFkcAA==.Saeris:BAAALgADCggJCAABLgADCgMJAwACAAAAAA==.Sagordez:BAAALgAECgYJBgABLgAECggJHAAbAKEiAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgADCggJCAABLgAECggJHwARAJYTAA==.Satorugojo:BAAALgAECgQJBAAAAA==.Savior:BAAALgADCggJIgAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAQAAAA==.Seizon:BAAALgADCgkJDwAAAA==.Semila:BAAALgAECgEJAQABLgAECgQJBQACAAAAAA==.Senseicanz:BAAALgADCgEJAQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgADCgIJAgABLgAECgUJEAACAAAAAA==.Serom:BAAALgAECgYJCgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8WAAIJAAkJvh+tCwDTAgAJAAkJvh+tCwDTAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAACAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sherunn:BAAALgAECgYJCgAAAA==.Shiftydon:BAAALgAECgEJAQAAAA==.Shimakaze:BAABLgAECn8YAAIKAAcJpQckNQA9AQAKAAcJpQckNQA9AQAAAA==.Shirvana:BAAALgAECgQJBQAAAA==.Shooters:BAABLgAECn8UAAIfAAgJUxmmDQDuAQAfAAgJUxmmDQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgACAAAAAA==.Shymistress:BAABLgAECn8hAAIKAAgJ4BmHDgAmAgAKAAgJ4BmHDgAmAgAAAA==.Shåmmy:BAABLgAECn8eAAIPAAgJOA2xOgCXAQAPAAgJOA2xOgCXAQAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAAALgAECgUJDgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn8gAAIRAAgJqBU2BADvAQARAAgJqBU2BADvAQAAAA==.Skrinkles:BAAALgAECgUJBgAAAA==.Skyrocket:BAAALgAECgEJAQAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8MAAIIAAUJTiG6AwDDAQAIAAUJTiG6AwDDAQAuAAQKfycAAwgACQk2IOoOAJ4CAAgACQk2IOoOAJ4CAAwABwkKG51BACACAAAA.Slorth:BAABLgAECn8iAAIDAAgJDBpLKACcAQADAAgJDBpLKACcAQAAAA==.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn8lAAIJAAgJvQqTFABgAQAJAAgJvQqTFABgAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Spicybreath:BAAALgADCgMJAwABLgAECgQJBQACAAAAAA==.Spicydemon:BAAALgAECgQJBQAAAA==.Spicytotems:BAAALgADCgcJCQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAAALgAFFAIJAgAAAA==.',
St='Starwolfy:BAAALgADCgQJBAAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAAALgAECgYJCgAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8fAAIRAAgJlhORCwAGAgARAAgJlhORCwAGAgAAAA==.Tandria:BAAALgAECgMJAwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8XAAIOAAcJKBgXFADmAQAOAAcJKBgXFADmAQAAAA==.',
Te='Teakaachu:BAAALgAECgUJCgAAAA==.Terdanator:BAAALgAECgYJEAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn8hAAQSAAgJWRw/FgDzAQASAAgJWRw/FgDzAQAWAAEJAAA+KABQAAAYAAEJzgfreAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8XAAIIAAcJ1RxvCgAvAgAIAAcJ1RxvCgAvAgAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgMJAwABLgAECgYJFAAWAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tridius:BAAALgAECgUJCgAAAA==.',
Tu='Turdanator:BAABLgAECn8oAAMgAAgJMBX7CQDhAQAgAAgJMBX7CQDhAQAdAAYJGw1hQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJAgABLgAECgQJBQACAAAAAA==.',
Ur='Uraenus:BAAALgAECgYJDAAAAA==.Urahrotar:BAAALgADCgMJAwAAAA==.Uriah:BAAALgAECgQJBwAAAA==.Ursúla:BAAALgAFFAMJBAAAAA==.Uryu:BAAALgAECgIJAgAAAA==.Urïah:BAAALgADCgkJDgABLgAECgQJBwACAAAAAA==.',
Ut='Utherr:BAAALgAECgcJEAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAgAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violinmax:BAAALgAECgMJBQAAAA==.',
Vo='Voidnova:BAAALgADCgQJBAAAAA==.Vonnie:BAAALgAECgQJBAAAAA==.',
Vy='Vynlerinis:BAABLgAECn8cAAIbAAgJoSLDAAC7AgAbAAgJoSLDAAC7AgAAAA==.',
Wa='Wardestroyer:BAAALgAECgYJBwAAAA==.Wardwhelp:BAAALgAECgQJCAAAAA==.',
Wi='Wifehaver:BAABLgAECn8gAAIJAAgJ1h7vEgB6AgAJAAgJ1h7vEgB6AgAAAA==.Winniedapoo:BAABLgAECn8qAAISAAgJDhjnPwAOAgASAAgJDhjnPwAOAgAAAA==.',
Wo='Wooloo:BAACLgAFFH8UAAQYAAcJBxwZAwBvAQASAAYJ8xrlCwB1AQAYAAQJ+xgZAwBvAQAWAAEJAADEBABZAAAuAAQKfyAAAxIACQmzJRQXAMoCABIACAmzJRQXAMoCABgABAlPHX0gAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8bAAIHAAgJphx6HgBcAgAHAAgJphx6HgBcAgAAAA==.Xanthecat:BAAALgADCgQJBAAAAA==.',
Xk='Xkwon:BAAALgAECgUJBwAAAA==.Xkwøn:BAACLgAFFH8MAAIhAAMJLBknAgAIAQAhAAMJLBknAgAIAQAuAAQKfzEAAiEACAl7H9UAAHECACEACAl7H9UAAHECAAAA.',
Xu='Xunie:BAAALgAECgEJAQAAAA==.',
Xx='Xximage:BAABLgAECn8bAAMiAAgJ0yRfAQDIAgAiAAgJ0yRfAQDIAgABAAEJAACLWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8WAAIGAAYJ1hJFQgDfAAAGAAYJ1hJFQgDfAAAAAA==.',
Zb='Zbrute:BAAALgAECgYJDgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgUJBQACAAAAAA==.Zefphenn:BAAALgAECgQJBgABLgAECgUJBQACAAAAAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8cAAIDAAgJAhy4FAAUAgADAAgJAhy4FAAUAgAAAA==.',
['Ðo']='Ðondon:BAAALgADCgEJAQAAAA==.Ðoppelgänger:BAAALgAECgEJAQAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8MAAIBAAMJExUeNAD/AAABAAMJExUeNAD/AAAuAAQKfygAAgEACAm8HilKAFkCAAEACAm8HilKAFkCAAAA.',
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

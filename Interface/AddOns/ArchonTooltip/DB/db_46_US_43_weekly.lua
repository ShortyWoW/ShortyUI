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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Unknown-Unknown','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Hunter-Marksmanship','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Priest-Holy','Warlock-Affliction','Hunter-Survival','Warlock-Destruction','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgEJAQAAAA==.',
Af='Affae:BAABLgAFFH8FAAMBAAMJFBOlFwCaAAABAAIJPg6lFwCaAAACAAIJ6RZuKwCWAAAAAA==.',
Ag='Agrios:BAAALgAECgQJBAAAAA==.',
Ak='Ak:BAABLgAECn8hAAIDAAgJ7x8DJAAWAgADAAgJ7x8DJAAWAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgcJGwAEAPQVAA==.',
Am='Amare:BAAALgADCgcJBwAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECgIJAgAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgUJBQAAAA==.',
Ar='Araxe:BAABLgAECn8dAAIFAAYJAxjUTwBMAQAFAAYJAxjUTwBMAQAAAA==.Arroyo:BAABLgAECn8fAAMFAAgJcSAgEgBrAgAFAAgJViAgEgBrAgAEAAQJyRubHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Askadar:BAACLgAFFH8KAAIGAAMJqSadBQBWAQAGAAMJqSadBQBWAQAuAAQKfygAAgYACQlxJq0DABoDAAYACQlxJq0DABoDAAAA.',
At='Atinyhorse:BAABLgAECn8YAAIHAAcJRwvcTAASAQAHAAcJRwvcTAASAQAAAA==.Atrax:BAAALgAECgIJAwAAAA==.Atryx:BAAALgAECgQJCgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQAIAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azzura:BAAALgADCgMJAwAAAA==.',
Ba='Baheem:BAAALgAECgMJCAAAAA==.Bams:BAAALgAECgYJEgAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEQAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8hAAIJAAgJNiFIGwByAgAJAAgJNiFIGwByAgAAAA==.Bighoofprint:BAAALgADCgQJAwAAAA==.Bigtotempole:BAAALgAECgUJCgAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8bAAIKAAcJ5BfyJwCyAQAKAAcJ5BfyJwCyAQAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgMJBgABLgAECgkJGQALAJwbAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgMJAwAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8XAAIMAAgJAxXBNACqAQAMAAgJAxXBNACqAQAAAA==.Bohelranus:BAAALgADCgkJFgAAAA==.Boneman:BAAALgADCgQJBAAAAA==.Boolil:BAAALgAECgQJBwABLgAECgkJHAANAC4MAA==.Booqt:BAAALgADCgUJBQABLgAECgkJHAANAC4MAA==.',
Br='Breake:BAAALgAECgUJDgAAAA==.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAAALgAECgYJDAAAAA==.',
Ca='Cailan:BAAALgADCgQJBQAAAA==.Caladiir:BAAALgAECgUJBQABLgAECgkJFwACAJQgAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECggJHQAKAJkZAA==.',
Ce='Cerealmilk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAIAAAAAA==.Childishbro:BAAALgADCgIJAgAAAA==.Chilla:BAAALgADCgEJAQAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAIAAAAAA==.Christopher:BAACLgAFFH8OAAIDAAQJAB/SGAB9AQADAAQJAB/SGAB9AQAuAAQKfxsAAgMACQn3IJctALsCAAMACQn3IJctALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgUJDQAIAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8ZAAIGAAUJCySPAgCrAQAGAAUJCySPAgCrAQAuAAQKfyUAAgYACAkAIh8EAAoDAAYACAkAIh8EAAoDAAAA.',
Cr='Creepychaos:BAAALgADCgkJIwABLgAECggJKAAFAFgGAA==.Creepydemise:BAABLgAECn8oAAIFAAgJWAZCUABLAQAFAAgJWAZCUABLAQAAAA==.Croixsmash:BAABLgAECn8eAAIJAAgJzRhAIgBDAgAJAAgJzRhAIgBDAgAAAA==.Croixtemplar:BAAALgADCggJCAAAAA==.',
Cu='Custodian:BAAALgAECgQJAwAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgEJAQAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAAALgAECgYJEwAAAA==.Davennial:BAABLgAECn8iAAINAAYJdxD3ZwAdAQANAAYJdxD3ZwAdAQAAAA==.Dawnn:BAAALgAECgYJDgAAAA==.Dayman:BAAALgAFFAEJAQAAAA==.',
De='Deanwnchestr:BAAALgAECgYJEAAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAAALgAFFAMJAwAAAA==.Demise:BAAALgAECgQJBgAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHAABABwhAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJDQAAAA==.',
Do='Doregoran:BAAALgAECgUJDAAAAA==.Dovairous:BAAALgAECgQJCwAAAA==.',
Dr='Draakell:BAAALgAECgQJAwAAAA==.Dracopeet:BAABLgAECn8VAAMOAAYJngVnPgCiAAAOAAUJ4wRnPgCiAAAPAAMJwQJxGQAsAAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgADCgMJAwAAAA==.',
Du='Dudè:BAAALgADCgkJCQAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8WAAIQAAYJegdqdQDeAAAQAAYJegdqdQDeAAAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgEJAQAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8LAAMRAAQJuQ42EgAmAQARAAQJuQ42EgAmAQASAAEJTgAWSgAjAAAuAAQKfyAAAxEACQkrHvQNAO4BABEACQkrHvQNAO4BABIABAlqBYesAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgQJCQAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAAALgAECgYJEAAAAA==.Erodoria:BAABLgAECn8UAAMTAAgJiRyZCgDdAQATAAYJBSGZCgDdAQAUAAUJExFbCwAWAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgYJFQARAKwSAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAECgMJAwABLgAFFAMJCQAVAOgRAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8VAAIWAAgJaRMhBgC5AQAWAAgJaRMhBgC5AQAAAA==.',
Fa='Falkor:BAABLgAECn8pAAIXAAkJpxbwBQAvAgAXAAkJpxbwBQAvAgAAAA==.Fanir:BAAALgADCgMJAwAAAA==.Fatkid:BAAALgAECgcJBgAAAA==.Fayway:BAABLgAECn8yAAISAAkJsiF6AgBcAwASAAkJsiF6AgBcAwAAAA==.',
Fe='Ferral:BAABLgAECn8ZAAILAAkJnBvWBQDyAQALAAkJnBvWBQDyAQAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAAALgAECgYJEQAAAA==.Firepower:BAABLgAECn8XAAIDAAgJyxOPMQDaAQADAAgJyxOPMQDaAQABLgAECggJIAALAJcTAA==.Fistatoosh:BAABLgAECn8cAAICAAgJsiPmAgDXAgACAAgJsiPmAgDXAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAALAJcTAA==.',
Fr='Fries:BAEALgAFFAEJAQABLgAFFAQJBgAQAKIPAA==.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAINAAgJnBqcKQB+AgANAAgJnBqcKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAIAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAIAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAAALgAECgcJEwAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAAALgAECgYJDAAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgADCggJDAABLgAECgMJCAAIAAAAAA==.',
Gr='Groddz:BAAALgAECggJEQAAAA==.Grrum:BAAALgAECgYJDQAAAA==.',
Ha='Hanjo:BAABLgAECn8cAAIGAAcJ5CF/BQBJAgAGAAcJ5CF/BQBJAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAIVAAcJixUqNgCqAQAVAAcJixUqNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA3qJACvAQABAAgJzA3qJACvAQAAAA==.Hatookorr:BAAALgAECgQJBAABLgAECggJIAALAJcTAA==.Hayali:BAABLgAECn8SAAIHAAYJDRNrSwAWAQAHAAYJDRNrSwAWAQAAAA==.',
He='Helledrians:BAAALgAECgQJBQAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hypatia:BAABLgAECn8cAAIBAAgJHCENCABDAgABAAgJHCENCABDAgAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAABLgAECn8cAAICAAgJ7R9kFgBWAgACAAgJ7R9kFgBWAgAAAA==.',
In='Incite:BAABLgAECn8gAAMYAAkJWA8mBADXAQAYAAkJVQ8mBADXAQAZAAUJ+g2IQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn8hAAMRAAgJrROTFACcAQARAAgJrROTFACcAQAaAAMJHwhAKAA3AAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8cAAIbAAcJiRkvDQATAgAbAAcJiRkvDQATAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kamine:BAAALgAECgUJDQAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAABLgAECn8bAAIRAAcJqxYFFACjAQARAAcJqxYFFACjAQAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8TAAMcAAYJUiDFBAApAgAcAAYJUiDFBAApAgAQAAMJnBXgxgDLAAAAAA==.Kensington:BAABLgAECn8YAAIYAAgJbwinBwBjAQAYAAgJbwinBwBjAQAAAA==.',
Ki='Kiku:BAABLgAECn8hAAIOAAgJVyO7AwDRAgAOAAgJVyO7AwDRAgAAAA==.Kim:BAABLgAECn8WAAIdAAgJDQ2EDgDAAQAdAAgJDQ2EDgDAAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kissofdeáth:BAAALgAECgEJAQAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQQAAkJ5x0nNAA8AgAQAAgJFR0nNAA8AgAcAAEJlRYzFgBAAAAeAAEJAAClbAA7AAAAAA==.',
Kr='Kreepywife:BAAALgADCgkJJAAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8VAAIVAAgJGAgqNAA7AQAVAAgJGAgqNAA7AQAAAA==.',
Ku='Kuzan:BAACLgAFFH8PAAIDAAUJWB6+HgBrAQADAAUJWB6+HgBrAQAuAAQKfx0AAgMABwl3IfE2AJgCAAMABwl3IfE2AJgCAAAA.',
Ky='Kyoyama:BAAALgAECgEJAQABLgAECggJGgAQAP0fAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECggJHQAKAJkZAA==.Ladýshinobu:BAABLgAECn8cAAIMAAcJwAt1KABJAQAMAAcJwAt1KABJAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn8qAAIfAAgJyxbKCAC9AQAfAAgJyxbKCAC9AQAAAA==.Lediaa:BAAALgADCgcJBwAAAA==.',
Li='Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgYJBwAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Littlespyone:BAAALgAECgMJCAAAAA==.',
Lo='Locholovis:BAABLgAECn8aAAIeAAYJ/A7WDAAEAQAeAAYJ/A7WDAAEAQAAAA==.Locklicous:BAAALgAECggJCwAAAA==.Longhorse:BAACLgAFFH8UAAIEAAUJzh96BgBmAQAEAAUJzh96BgBmAQAuAAQKfzAAAwQACQnWJMcFAOACAAQACQmQIscFAOACAAUABgnTJVMlAOwBAAAA.Longknight:BAAALgADCgcJCgAAAA==.Longr:BAAALgADCgkJGgAAAA==.Lorna:BAAALgAECgYJCgAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAQAOcdAA==.',
Lu='Lumi:BAAALgAECgYJDwABLgAECgcJAgAIAAAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8GAAIVAAUJoA3xDQBWAQAVAAUJoA3xDQBWAQABLgAFFAMJBgAgAOgUAA==.Lumpia:BAABLgAFFH8GAAIHAAQJPxgRGQBFAQAHAAQJPxgRGQBFAQAAAA==.',
Ly='Lyrinir:BAABLgAECn8ZAAIGAAkJthh4CgDHAQAGAAkJthh4CgDHAQAAAA==.Lyrium:BAABLgAECn8YAAMUAAcJpRy8CgC4AQAUAAUJDB+8CgC4AQATAAYJwRLWGAAbAQABLgAECgkJGQAGALYYAA==.',
Ma='Madar:BAAALgAECgYJCgAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAAALgAECgYJEAAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgEJAQABLgAECgkJKQAXAKcWAA==.Marrock:BAAALgAECgEJAQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgIJBAAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJCgAAAA==.',
Me='Mechacattie:BAABLgAECn8dAAIKAAgJmRmnGAALAgAKAAgJmRmnGAALAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8bAAMhAAcJBw05IAA7AQAhAAcJBw05IAA7AQAbAAIJiAbudABVAAAAAA==.Mercas:BAAALgAECgYJBwABLgAECgkJHwAaAPwYAA==.Mezi:BAABLgAECn8fAAIbAAgJth+TBgCPAgAbAAgJth+TBgCPAgAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgEJAQAIAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIgAAMJ6BRqFgD7AAAgAAMJ6BRqFgD7AAAuAAQKfxYAAxsACQmeF3IoAK0BABsABgn7GXIoAK0BACAABwkoEcYhAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAIAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwANABghAA==.Moneyshotinc:BAAALgAECgkJBgABLgAECggJIwANABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8cAAIiAAgJlQz3IABIAQAiAAgJlQz3IABIAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJBQAIAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCSZAgCZAQABAAQJbCSZAgCZAQAuAAQKfxYAAgEABwntJAQKANcCAAEABwntJAQKANcCAAAA.Mulron:BAABLgAECn8WAAIfAAgJ4Q69DQBdAQAfAAgJ4Q69DQBdAQAAAA==.',
My='Myrica:BAAALgAECgQJBAAAAA==.',
['Mö']='Mööve:BAAALgADCgYJBgAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCAAIAAAAAA==.',
Ne='Nefesh:BAAALgADCgUJBQAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAQAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8NAAIRAAQJ2RQLDgBAAQARAAQJ2RQLDgBAAQAuAAQKfzYAAhEACQkGFsoUAGsCABEACQkGFsoUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgQJBAAAAA==.',
Or='Orileluu:BAAALgADCgYJEAAAAA==.',
Ox='Oxwon:BAAALgAECgIJAgAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgADCgYJBgAAAA==.Pallynomial:BAAALgADCgcJCAAAAA==.Pawmuck:BAAALgAECgYJDQAAAA==.',
Pe='Peer:BAAALgAECgEJAQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgIJAgAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMFAAcJBx97PABFAgAFAAcJBx97PABFAgAEAAUJCRifJwABAQAAAA==.Plagueblade:BAABLgAECn8bAAIEAAcJ9BUfEABwAQAEAAcJ9BUfEABwAQAAAA==.',
Po='Poof:BAAALgAECgYJCgAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAAALgADCgYJBwAAAA==.Progression:BAAALgAECgEJAgAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAAALgAECgYJEAAAAA==.Rainthefire:BAABLgAECn83AAIKAAkJZBoYDAB+AgAKAAkJZBoYDAB+AgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgAECgMJBQAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgMJBgAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8JAAIVAAMJ6BFMJgC7AAAVAAMJ6BFMJgC7AAAuAAQKfxUAAhUACAl3HUcXAFsCABUACAl3HUcXAFsCAAAA.',
Ri='Rianon:BAAALgADCgkJCQABLgAECgcJFgAHACcTAA==.Rift:BAAALgAECgEJAQAAAA==.Righteous:BAABLgAECn8VAAIbAAYJ5BwwEADpAQAbAAYJ5BwwEADpAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAQAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8KAAMKAAMJZBIlJwD7AAAKAAMJZBIlJwD7AAAdAAIJbgNTGACOAAAuAAQKfygAAwoACQloIWUWAIUCAAoACAmTImUWAIUCAB0ACAluGtAQALYBAAAA.',
Ru='Ruin:BAAALgAECgEJAQAAAA==.Rutikee:BAABLgAECn8oAAISAAgJ9BIiIwCuAQASAAgJ9BIiIwCuAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIbAAgJlBW6FgAmAgAbAAgJlBW6FgAmAgABLgAECgkJKgAQAIwaAA==.Saeris:BAAALgADCggJCAABLgAECgEJAQAIAAAAAA==.Sagordez:BAAALgAECggJEwABLgAECgkJHQAUACsgAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgADCggJCAABLgAECggJIAALAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgADCgkJJwAAAA==.Sazed:BAAALgAECgcJBwAAAA==.',
Sc='Scrom:BAAALgAECgEJAQAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAAALgADCgkJDwAAAA==.Semila:BAAALgAECgcJCAAAAA==.Senseicanz:BAAALgADCgEJAQAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgADCgIJAgABLgAECgcJGwAEAPQVAA==.Serom:BAAALgAECgYJEAAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8XAAICAAkJlCCsCwDTAgACAAkJlCCsCwDTAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAIAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sherunn:BAAALgAECgYJEAAAAA==.Shifty:BAAALgAECgEJAQAAAA==.Shiftydon:BAAALgAECgcJDQAAAA==.Shimakaze:BAABLgAECn8cAAIKAAgJnQn1NgBxAQAKAAgJnQn1NgBxAQAAAA==.Shirvana:BAAALgAECgQJBQABLgAECgcJCAAIAAAAAA==.Shooters:BAABLgAECn8WAAIdAAgJlxqmDQDuAQAdAAgJlxqmDQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAIAAAAAA==.Shymistress:BAABLgAECn8pAAIKAAgJfB+JCwCEAgAKAAgJfB+JCwCEAgAAAA==.Shåmmy:BAABLgAECn8nAAIVAAkJQAywOgCXAQAVAAkJQAywOgCXAQAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8XAAIRAAcJoB7LCwANAgARAAcJoB7LCwANAgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn8oAAILAAgJZh3CAgByAgALAAgJZh3CAgByAgAAAA==.Skodoosh:BAAALgAECgEJAQAAAA==.Skrinkles:BAAALgAECgUJBgAAAA==.Skyrocket:BAAALgAECgIJAgAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8MAAIMAAUJTiFUCACXAQAMAAUJTiFUCACXAQAuAAQKfycAAwwACQk2IOsOAJ4CAAwACQk2IOsOAJ4CAA0ABwkKG51BACACAAAA.Slorth:BAABLgAECn8iAAIFAAgJDBq3OwCLAQAFAAgJDBq3OwCLAQAAAA==.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn8tAAICAAgJxQ6QFgCEAQACAAgJxQ6QFgCEAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Spicybreath:BAAALgADCgMJAwABLgAECgcJCwAIAAAAAA==.Spicydemon:BAAALgAECgcJCwAAAA==.Spicytotems:BAAALgADCgcJCQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAAALgAFFAIJAgAAAA==.',
St='Starwolfy:BAAALgADCgQJBAAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAAALgAECgYJEAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJBQAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8gAAILAAgJlxORCwAGAgALAAgJlxORCwAGAgAAAA==.Tandria:BAAALgAECgMJAwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8YAAISAAgJVRcJFwANAgASAAgJVRcJFwANAgAAAA==.',
Te='Teakaachu:BAAALgAECgUJCgAAAA==.Terdanator:BAAALgAECgYJEQAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn8qAAQQAAkJjBqkEQBWAgAQAAkJjBqkEQBWAgAcAAEJAAA9KABQAAAeAAEJzgfreAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8XAAIMAAcJ1Rx8EAAYAgAMAAcJ1Rx8EAAYAgAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAcAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tridius:BAAALgAECgYJCwAAAA==.Trollins:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn8qAAMhAAkJOxQTCgAjAgAhAAkJOxQTCgAjAgAbAAYJGw1oQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJAwABLgAECgcJCwAIAAAAAA==.',
Ur='Uraenus:BAAALgAECgYJDAAAAA==.Urahrotar:BAAALgADCgMJAwAAAA==.Uriah:BAAALgAECgUJDAAAAA==.Ursúla:BAABLgAFFH8FAAIQAAMJzQcmSwDBAAAQAAMJzQcmSwDBAAABLgAFFAQJCwARALkOAA==.Uryu:BAAALgAECgMJAwAAAA==.Urïah:BAAALgADCgkJEQABLgAECgUJDAAIAAAAAA==.',
Ut='Utherr:BAAALgAFFAMJAwAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAAALgAECgEJAQABLgAECgUJDAAIAAAAAA==.Violinmax:BAAALgAECgUJDAAAAA==.',
Vo='Voidnova:BAAALgADCgQJBAAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8dAAIUAAkJKyCzAADtAgAUAAkJKyCzAADtAgAAAA==.',
Wa='Wardestroyer:BAAALgAECgYJCAAAAA==.Wardwhelp:BAAALgAECgQJCwABLgAECgYJCgAIAAAAAA==.',
Wi='Wifehaver:BAABLgAECn8kAAICAAkJfB/tEgB6AgACAAkJfB/tEgB6AgAAAA==.Winniedapoo:BAABLgAECn8xAAIQAAgJ1huOEwBGAgAQAAgJ1huOEwBGAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgcJGwAEAPQVAA==.',
Wo='Wooloo:BAACLgAFFH8UAAQeAAcJBxwcAwBvAQAQAAYJ8xoZDQBzAQAeAAQJ+xgcAwBvAQAcAAEJAADHBABZAAAuAAQKfyEAAxAACQmzJRIXAMoCABAACAmzJRIXAMoCAB4ABAlPHXkgAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8dAAMJAAgJIx16HgBcAgAJAAgJphx6HgBcAgAGAAEJ0BbgMgBCAAAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8PAAIjAAMJVhnwAAAGAQAjAAMJVhnwAAAGAQAuAAQKfzMAAiMACAl/IDIBAH8CACMACAl/IDIBAH8CAAAA.',
Xu='Xunie:BAAALgAECgcJDQAAAA==.',
Xx='Xximage:BAABLgAECn8cAAMkAAgJ0iRfAQDIAgAkAAgJ0iRfAQDIAgADAAEJAACRWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8WAAIHAAYJ1hJBaQBnAQAHAAYJ1hJBaQBnAQAAAA==.Zaretan:BAAALgADCgEJAQAAAA==.',
Zb='Zbrute:BAABLgAECn8WAAIKAAgJoRU3IADbAQAKAAgJoRU3IADbAQAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgYJCgAIAAAAAA==.Zefphenn:BAAALgAECgQJBgABLgAECgYJCgAIAAAAAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8eAAIFAAkJehvEFABVAgAFAAkJehvEFABVAgAAAA==.',
['Ðo']='Ðondon:BAAALgADCgEJAQAAAA==.Ðoppelgänger:BAAALgAECgEJAgAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8NAAIDAAMJFhVQSQD2AAADAAMJFhVQSQD2AAAuAAQKfykAAgMACAm8Hh9KAFkCAAMACAm8Hh9KAFkCAAAA.',
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

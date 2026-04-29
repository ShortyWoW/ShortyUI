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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Druid-Balance','Mage-Frost','Monk-Mistweaver','DeathKnight-Unholy','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Shaman-Restoration','DemonHunter-Devourer','Paladin-Protection','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Warrior-Fury','Shaman-Elemental','Evoker-Augmentation','Rogue-Outlaw','Monk-Brewmaster','Priest-Shadow','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','DeathKnight-Blood','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Fire','Druid-Feral','Warrior-Protection','DemonHunter-Vengeance','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abashai:BAABLgAECn8UAAMBAAYJsRl+JQDNAQABAAYJsRl+JQDNAQACAAEJoAzSIAAuAAAAAA==.Abashot:BAAALgADCgMJAwABLgAECgYJFAABALEZAA==.',
Ac='Achicken:BAAALgAECgEJAQAAAA==.',
Ad='Adeathknight:BAAALgAECgYJCgAAAA==.Adetalo:BAAALgADCggJCAAAAA==.Adouken:BAAALgAECgQJCAAAAA==.',
Ae='Aeliafaelyn:BAAALgADCgkJEAAAAA==.Aellyria:BAABLgAECn8YAAMDAAcJgg/oEwApAQADAAYJ8w7oEwApAQAEAAEJUgd2IwAwAAAAAA==.Aeloesh:BAAALgAECgYJEwAAAA==.Aestra:BAABLgAECn8hAAIFAAkJFRwiHgD9AgAFAAkJFRwiHgD9AgAAAA==.',
Ai='Ailari:BAAALgAECgUJBQAAAA==.Aipasso:BAAALgAECgEJAgAAAA==.',
Ak='Akaili:BAAALgAECgMJBgAAAA==.Aklymydia:BAAALgADCgUJBQAAAA==.',
Al='Aledria:BAAALgADCgUJBQAAAA==.Alexiya:BAAALgAECgYJEgAAAA==.Alinoven:BAABLgAECn8YAAIFAAcJDhZMoQCUAQAFAAcJDhZMoQCUAQAAAA==.Allacari:BAAALgAECgYJDgAAAA==.Almace:BAAALgAECgcJDAAAAA==.Alucardd:BAAALgADCgUJBQAAAA==.',
An='Angmaro:BAAALgAECgQJBAAAAA==.Anniki:BAAALgAECgEJAQABLgAFFAQJCAAGAP8VAA==.Antibear:BAABLgAECn8YAAIHAAcJcgqQHgApAQAHAAcJcgqQHgApAQAAAA==.Antonina:BAAALgADCgYJBgAAAA==.',
Ap='Apetoes:BAAALgADCgIJAgABLgAECgIJAgAIAAAAAA==.Aphrodita:BAAALgAECgEJAgAAAA==.Apito:BAAALgAECgIJAgAAAA==.Apitoo:BAAALgADCgUJBQABLgAECgIJAgAIAAAAAA==.Apol:BAABLgAECn8WAAIJAAcJ3xAHEAA9AQAJAAcJ3xAHEAA9AQAAAA==.',
Ar='Arachne:BAABLgAECn8hAAIFAAgJQReREgCtAQAFAAgJQReREgCtAQAAAA==.Arakar:BAABLgAECn8aAAMJAAgJ0w+ZLwDEAQAJAAgJ0w+ZLwDEAQAKAAYJggalxAD+AAAAAA==.Arakina:BAAALgADCgMJAwABLgAECggJGgAJANMPAA==.Aralynne:BAAALgAECgYJEwAAAA==.Arch:BAAALgAECgUJCgAAAA==.Archeus:BAAALgAECgUJBgAAAA==.Archyan:BAAALgADCgEJAQAAAA==.Arlïnn:BAAALgAECgYJBgAAAA==.Armorya:BAABLgAECn8hAAIKAAkJjxpIKQCAAgAKAAkJjxpIKQCAAgAAAA==.Armyofone:BAAALgAECgIJAwAAAA==.Artaius:BAABLgAECn8bAAILAAcJlCTQAABdAgALAAcJlCTQAABdAgAAAA==.Artree:BAAALgAECgYJBgAAAA==.',
As='Ashaw:BAAALgADCggJGAAAAA==.Ashwyn:BAABLgAECn8VAAIEAAcJrwJ2VQDPAAAEAAcJrwJ2VQDPAAAAAA==.Astarog:BAAALgAECgYJDwAAAA==.',
At='Atafloosy:BAEBLgAECn8cAAIMAAcJEySUAwBEAgAMAAcJEySUAwBEAgAAAA==.Athelf:BAABLgAECn8gAAIKAAkJAR0PGQDTAgAKAAkJAR0PGQDTAgAAAA==.Athelfstein:BAAALgAECgUJBgAAAA==.',
Au='Aubrie:BAAALgADCgEJAQAAAA==.Aubriell:BAAALgAECgMJAwAAAA==.Augtistic:BAAALgAECgYJCgAAAA==.',
Av='Avelone:BAAALgADCgMJAwAAAA==.Aviren:BAAALgAECggJEAAAAA==.',
Ax='Axël:BAAALgADCgYJBgAAAA==.',
Ay='Ayeamamonk:BAAALgADCgkJDgAAAA==.Ayrnerdam:BAAALgAECgQJCAAAAA==.',
Az='Azmadius:BAAALgADCgEJAQAAAA==.Azor:BAAALgAECgQJCAABLgAECgYJBgAIAAAAAA==.',
Ba='Baconbits:BAAALgADCgEJAQAAAA==.Bageldinger:BAAALgAECgEJAQABLgAECgIJAgAIAAAAAA==.Bagelss:BAAALgADCgIJAwABLgAECgIJAgAIAAAAAA==.Bagelstealth:BAAALgADCgcJDAABLgAECgIJAgAIAAAAAA==.Bairry:BAAALgADCgYJAwAAAA==.Bamberk:BAAALgAECgkJAQAAAA==.Batarang:BAAALgAECgYJEgAAAA==.',
Be='Bearbarian:BAAALgAECgYJDAAAAA==.Beastkael:BAAALgAECgYJBgAAAA==.Bellwhip:BAAALgAECgEJAgABLgAECgcJGAANALwYAA==.Berick:BAAALgAECgYJDgAAAA==.Besaaba:BAABLgAECn8XAAIDAAgJ1QKIGgDkAAADAAgJ1QKIGgDkAAAAAA==.',
Bi='Bingo:BAAALgAECgQJBAAAAA==.',
Bl='Blaize:BAAALgADCgEJAQAAAA==.Blax:BAAALgADCggJFwAAAA==.Blitzwing:BAAALgAECgMJAwAAAA==.Bloodeh:BAAALgAECgQJBgAAAA==.Bloodyaggro:BAAALgAECgMJAwAAAA==.Bloodygrip:BAAALgAECgYJCwAAAA==.',
Bo='Bodin:BAAALgAECggJEwAAAA==.Bolero:BAAALgAECgYJEQAAAA==.Bonnabelle:BAAALgAECgEJAQAAAA==.Boombawks:BAAALgAECgQJBQAAAA==.Boompd:BAAALgADCgYJBgABLgAECgQJBQAIAAAAAA==.Bootswidafur:BAAALgADCgYJCAAAAA==.Bos:BAAALgAECgcJDQAAAA==.Bowguy:BAAALgADCgcJBwABLgAFFAIJBQAOAEkVAA==.',
Br='Brasmina:BAAALgAECgQJBAAAAA==.Brazilian:BAABLgAECn8YAAMNAAcJvBiQDQCjAQANAAcJ7BaQDQCjAQAPAAQJ2RUeQQD1AAAAAA==.Briest:BAABLgAECn8jAAMQAAgJPx9DCgCVAgAQAAgJPx9DCgCVAgARAAMJJBcoXQC+AAAAAA==.Brightside:BAAALgAFFAEJAQAAAA==.Brotherconns:BAAALgADCgkJEgAAAA==.Brunadin:BAAALgADCgIJAgAAAA==.Bruneigin:BAAALgAECgQJBAAAAA==.Brunny:BAAALgADCgYJCAABLgAECggJIwAQAD8fAA==.',
Bu='Bubblohsvn:BAAALgAECgEJAQAAAA==.Bubonic:BAAALgAECgQJBwAAAA==.Bureiku:BAAALgAECgYJEAAAAA==.',
Bw='Bwomp:BAABLgAECn8aAAISAAgJSRWNIwA5AgASAAgJSRWNIwA5AgAAAA==.',
Ca='Caatos:BAAALgADCgcJDQAAAA==.Caelm:BAAALgADCggJDAAAAA==.Caias:BAAALgAECgQJBAAAAA==.Caldrea:BAAALgADCggJEgAAAA==.Calzone:BAAALgAECgQJBgAAAA==.Cambria:BAAALgAECgQJCwABLgAECgcJFAATALIVAA==.Cameltotum:BAAALgADCgYJCQAAAA==.Carceret:BAAALgAECgkJBgAAAA==.Cardian:BAAALgAECgUJCAAAAA==.Caridin:BAAALgAECgYJEwAAAA==.Carmey:BAAALgAECgMJAwAAAA==.Carpus:BAAALgADCgMJAwAAAA==.Carrin:BAACLgAFFH8LAAIKAAQJ2BTwBgAeAQAKAAQJ2BTwBgAeAQAuAAQKfyQAAgoACAlCIWIQAAwDAAoACAlCIWIQAAwDAAAA.Catalyia:BAAALgAECgEJAQAAAA==.Catris:BAAALgAECgUJCgAAAA==.',
Ce='Cedriel:BAAALgADCgUJAgAAAA==.Cenariya:BAAALgADCgYJBgAAAA==.Ceronos:BAAALgADCgQJBAAAAA==.Cerul:BAABLgAECn8WAAIUAAgJqhalAwDrAQAUAAgJqhalAwDrAQAAAA==.',
Ch='Chazzy:BAABLgAECn8hAAIUAAgJJRWXBwB2AQAUAAgJJRWXBwB2AQAAAA==.Cheapfloosy:BAAALgADCgMJAwAAAA==.Chesleon:BAAALgAECgEJAgAAAA==.Chila:BAAALgAECgQJBAAAAA==.Chinaski:BAAALgAECgQJBAAAAA==.Chissgoria:BAAALgADCgYJBgAAAA==.',
Ci='Cinamonbagel:BAAALgADCgUJBgABLgADCgcJEwAIAAAAAA==.Cirina:BAAALgAECgYJCgAAAA==.',
Cl='Cli:BAAALgADCgMJAwAAAA==.Cliss:BAAALgAECgEJAQAAAA==.',
Co='Cognitive:BAAALgADCgYJBgABLgAFFAIJBQAOAEkVAA==.Coheed:BAAALgAECgMJAwABLgAECgcJFAATALIVAA==.Coiren:BAAALgAECgQJBQAAAA==.Cokegaming:BAAALgADCgIJAgAAAA==.Concorde:BAAALgAECggJEgAAAA==.Copiousconns:BAAALgAECgYJEwAAAA==.Coreyb:BAAALgADCgMJAwAAAA==.Corlock:BAAALgAECgYJDAAAAA==.',
Cp='Cptstabn:BAACLgAFFH8FAAMVAAIJbB9RAQClAAABAAIJbB+0EADEAAAVAAIJCQhRAQClAAAuAAQKfycAAxUACAkWJEkAAFMCAAEACAnVIx0GAC8DABUABwnhIEkAAFMCAAAA.',
Cr='Creky:BAAALgADCgkJCQAAAA==.',
Cu='Cutlash:BAAALgADCgcJCAABLgAECgUJCgAIAAAAAA==.Cutslash:BAAALgADCgcJBwABLgAECgUJCgAIAAAAAA==.Cutzap:BAAALgAECgUJCgAAAA==.',
['Cà']='Càin:BAAALgAECgMJAwAAAA==.',
Da='Daemoda:BAAALgAECgYJEgAAAA==.Daemona:BAABLgAECn8dAAIPAAkJPRI/AgD+AQAPAAkJPRI/AgD+AQAAAA==.Daieniceis:BAAALgAECgQJBAAAAA==.Dalaren:BAAALgADCgMJAwAAAA==.Dariele:BAAALgAECgYJEgAAAA==.Darra:BAAALgAECgYJDQAAAA==.',
De='Decayxdd:BAAALgADCgYJBgABLgAECggJFQAWALsaAA==.Decayy:BAAALgAFFAIJAwABLgAECggJFQAWALsaAA==.Deceptakahn:BAAALgAECgcJEwAAAA==.Dellin:BAAALgADCgIJAQAAAA==.Derailedbeef:BAAALgAECgYJEgAAAA==.Deremes:BAAALgAECgMJBAAAAA==.Destrobutor:BAAALgADCgMJAgAAAA==.Devalsminion:BAAALgADCgUJBQAAAA==.Deyas:BAABLgAECn8dAAIXAAgJjBKlGQATAgAXAAgJjBKlGQATAgAAAA==.Deydora:BAAALgAECgYJDAAAAA==.Deydoralia:BAABLgAECn8iAAIJAAkJnSG3AQBnAwAJAAkJnSG3AQBnAwAAAA==.',
Di='Diabeetus:BAAALgAECgMJAwAAAA==.Dineye:BAAALgAECgEJAgAAAA==.Dislowcate:BAABLgAECn8iAAIHAAgJ3BXoEQCEAQAHAAgJ3BXoEQCEAQAAAA==.Divineknight:BAAALgADCgcJCAAAAA==.Divinesarah:BAAALgADCgcJEAABLgAFFAQJBwAFAIoIAA==.Diô:BAAALgAECgcJBwAAAA==.',
Dj='Djs:BAAALgADCgcJCQAAAA==.',
Do='Docdoom:BAAALgAECgMJAwAAAA==.Doieha:BAAALgADCgkJCQABLgAECgYJFAAYAMUcAA==.Dollos:BAAALgADCgQJBAAAAA==.Doneldus:BAAALgADCggJCAAAAA==.Donnovan:BAAALgADCgUJBQAAAA==.Dontrelease:BAABLgAECn8eAAMYAAgJexCuGQDAAQAYAAgJexCuGQDAAQAUAAUJSgjEGwBdAAAAAA==.Doore:BAAALgADCgcJCAAAAA==.Dorfdragon:BAAALgAECgYJEwAAAA==.Dorfe:BAABLgAECn8UAAICAAcJxw8NCQCzAQACAAcJxw8NCQCzAQAAAA==.Dorflock:BAAALgADCgkJGQAAAA==.',
Dr='Draconas:BAABLgAECn8YAAMZAAgJExYkCgDRAQAZAAcJExYkCgDRAQAaAAEJAACQZgBDAAAAAA==.Dragonpants:BAABLgAECn8nAAIbAAgJryA1AACqAgAbAAgJryA1AACqAgAAAA==.Drakiero:BAAALgAECgYJDwAAAA==.Drakona:BAAALgAECgYJCwAAAA==.Draych:BAABLgAECn8kAAMJAAkJ7A2aLADTAQAJAAkJ7A2aLADTAQAKAAEJvgUxXgA2AAAAAA==.Dreadnaughts:BAAALgADCgEJAQAAAA==.Drewgarymore:BAABLgAECn8WAAMEAAYJRRslCABzAQAEAAYJRRslCABzAQALAAMJZQQWLgA+AAAAAA==.',
Du='Durandall:BAABLgAECn8kAAIKAAkJyxyPIgCfAgAKAAkJyxyPIgCfAgAAAA==.Durleap:BAAALgAECgMJAwAAAA==.Duskjade:BAAALgADCgIJAQAAAA==.Dustall:BAABLgAECn8eAAIKAAkJhhyVDwASAwAKAAkJhhyVDwASAwAAAA==.',
Dy='Dylpickl:BAACLgAFFH8LAAINAAQJah1DCgAUAQANAAQJah1DCgAUAQAuAAQKfyEAAg0ACQnpJJwBAMMDAA0ACQnpJJwBAMMDAAAA.Dymàs:BAAALgAECgQJBwAAAA==.',
['Dè']='Dècay:BAABLgAECn8VAAIWAAgJuxqPAwD8AQAWAAgJuxqPAwD8AQAAAA==.',
Ea='Earthrocker:BAABLgAECn8WAAILAAYJUxTrEgBCAQALAAYJUxTrEgBCAQAAAA==.',
Ed='Edified:BAAALgAECgMJAwAAAA==.',
Ei='Einkil:BAABLgAECn8YAAIcAAgJERRjBQBjAQAcAAgJERRjBQBjAQAAAA==.',
El='Elurah:BAAALgAECgcJEgAAAA==.',
Em='Emberflame:BAAALgADCgMJAwAAAA==.Embergrove:BAAALgADCgEJAQAAAA==.Emberlée:BAAALgAECgMJAwABLgAECgkJIgAJAJ0hAA==.',
Ep='Epin:BAAALgAECgMJBQABLgAECggJFAAMAHUXAA==.',
Er='Erazminash:BAAALgAECgQJCAAAAA==.',
Es='Esdeáth:BAAALgAECgYJCgAAAA==.Ess:BAAALgAECgUJCgAAAA==.',
Ev='Even:BAAALgADCgkJEwAAAA==.',
Fa='Fae:BAAALgADCgcJCwAAAA==.Faede:BAAALgADCgcJCgAAAA==.Fangorn:BAAALgADCgQJBAAAAA==.Fantarius:BAAALgAECgcJEwAAAA==.Fantazee:BAAALgADCgQJBAAAAA==.Faromore:BAAALgAECgEJBAAAAA==.',
Fe='Felfurion:BAAALgAECgUJBQAAAA==.Feluhn:BAAALgAECgYJEwAAAA==.Fennriz:BAABLgAECn8VAAIFAAgJMRSnEwCkAQAFAAgJMRSnEwCkAQAAAA==.',
Fi='Fibbs:BAAALgAECgYJDwAAAA==.Firocios:BAAALgAECgYJDwAAAA==.Fistavus:BAAALgADCgYJBAAAAA==.',
Fl='Flappyboy:BAAALgAECgEJAQAAAA==.Flatiron:BAAALgAECgUJCgAAAA==.Flirts:BAAALgADCgMJAwAAAA==.',
Fo='Foul:BAABLgAECn8hAAIJAAgJNiL5BgD8AgAJAAgJNiL5BgD8AgABLgAFFAQJCAAGAP8VAA==.Foxybeans:BAAALgADCgcJBwAAAA==.',
Fr='Frankyzappa:BAABLgAECn8YAAMdAAgJDx54AQD0AQAdAAgJxxx4AQD0AQAeAAEJRhIWPgBIAAAAAA==.Frieda:BAAALgADCgMJAwAAAA==.Frink:BAAALgADCgkJEwABLgAECgUJCgAIAAAAAA==.Fromunda:BAAALgAECgYJDAAAAA==.Frosthot:BAAALgAECgIJAgAAAA==.',
Fy='Fyredemon:BAAALgADCgkJDwAAAA==.',
['Fë']='Fëld:BAAALgADCgUJBQAAAA==.',
Ga='Gardlier:BAAALgAECgQJBwAAAA==.Garumna:BAABLgAECn8VAAIHAAYJkRQYHwAmAQAHAAYJkRQYHwAmAQAAAA==.Garypotter:BAAALgAECgYJEwAAAA==.',
Ge='Gec:BAAALgADCgEJAQAAAA==.',
Gl='Gleave:BAABLgAECn8aAAIeAAgJjyHFAQCfAgAeAAgJjyHFAQCfAgAAAA==.Glennzig:BAAALgADCgIJAgAAAA==.Glimmerdin:BAAALgAECgMJAwABLgAECggJFwAXAG4TAA==.',
Go='Goremock:BAAALgAECgYJEwAAAA==.Gorescore:BAAALgADCgMJAwAAAA==.Gorpus:BAAALgADCgYJBgAAAA==.',
Gr='Granhiert:BAAALgAECgUJDQAAAA==.Granitor:BAAALgADCgcJBwABLgAECgEJAgAIAAAAAA==.Graven:BAAALgAECgQJBAAAAA==.Gravytrain:BAAALgADCgUJCgAAAA==.Greenonion:BAAALgADCgYJBgAAAA==.Gremer:BAAALgADCgIJAgAAAA==.Greyfear:BAAALgADCgEJAQAAAA==.Greyluxen:BAAALgADCgkJEgAAAA==.Greystoke:BAABLgAECn8UAAIMAAgJdRfuHwAfAgAMAAgJdRfuHwAfAgAAAA==.Greytusk:BAAALgADCgIJAgAAAA==.Grindelbald:BAABLgAECn8oAAIfAAcJNRxyAADtAQAfAAcJNRxyAADtAQAAAA==.Grìp:BAAALgAECgYJBwAAAA==.',
Gt='Gtfofupá:BAAALgAECgkJCgAAAA==.',
Gu='Gushee:BAAALgAECggJDAAAAA==.',
Gw='Gwenn:BAAALgAECgYJEwAAAA==.',
Ha='Haldor:BAAALgADCgcJBwABLgAECggJFAAYAJANAA==.Haldrath:BAABLgAECn8bAAIPAAgJoRhAFgAZAgAPAAgJoRhAFgAZAgAAAA==.Halse:BAAALgADCgIJAgAAAA==.Hanahiro:BAAALgADCgUJBAAAAA==.Harleyquìnn:BAAALgADCggJHQAAAA==.Hashishem:BAAALgAECgQJBAABLgAFFAQJCAAGAP8VAA==.Hawkslayer:BAAALgAECgUJCAAAAA==.',
He='Hecaate:BAAALgAECgYJCgAAAA==.Hedgelord:BAABLgAECn8fAAIEAAgJ1hifFwBOAgAEAAgJ1hifFwBOAgAAAA==.Hedy:BAAALgADCgUJCAAAAA==.Hellebore:BAAALgAECgIJAgAAAA==.Hendil:BAAALgAECgYJEgAAAA==.',
Ho='Hobe:BAAALgAECgUJBQAAAA==.Hohenhiem:BAAALgAECgIJAgAAAA==.Hollyparton:BAAALgAECgMJAwAAAA==.Holysith:BAAALgAECgQJBwAAAA==.Hornypunn:BAAALgADCgcJBwABLgAECgcJHwAZAIoaAA==.Hotzlol:BAABLgAECn8hAAMDAAgJ+h6qAgCNAgADAAgJ+h6qAgCNAgAgAAEJJBqjMABCAAAAAA==.',
Ht='Htari:BAAALgADCgkJEQABLgAECgYJFAAYAMUcAA==.',
Hu='Humoresque:BAAALgAECgUJCgAAAA==.Hunger:BAAALgAECgEJAQAAAA==.',
Ic='Icyblades:BAAALgAECgcJEQAAAA==.Icònòclast:BAAALgAECgcJEAAAAA==.',
Ii='Iifa:BAAALgADCgkJGAAAAA==.',
Ik='Ikari:BAAALgADCgMJAwAAAA==.Iknowkungfu:BAABLgAECn8bAAIWAAcJlyG6BADPAQAWAAcJlyG6BADPAQAAAA==.',
Il='Illuminate:BAAALgAECgYJEgAAAA==.',
Im='Imboutablow:BAAALgADCgEJAQAAAA==.',
In='Inori:BAABLgAECn8hAAMQAAgJGB1IAgBEAgAQAAgJGB1IAgBEAgARAAEJ0xqHeABHAAAAAA==.',
It='Ittyycakes:BAAALgADCgUJBQAAAA==.',
Ja='Jackypan:BAAALgADCgkJDgAAAA==.Jaktar:BAABLgAECn8VAAIeAAgJDwx9NQDYAQAeAAgJDwx9NQDYAQAAAA==.Jane:BAAALgAECgMJBgAAAA==.Janet:BAABLgAECn8ZAAIhAAgJXgwgGQCJAQAhAAgJXgwgGQCJAQAAAA==.',
Je='Jeroung:BAAALgAECgIJAwAAAA==.Jezak:BAAALgAECgMJAwABLgAECgcJEgAIAAAAAA==.',
Ji='Jiraipo:BAAALgAECgQJBwAAAA==.Jirikidawn:BAAALgADCgMJAwAAAA==.Jirikideath:BAAALgAECgYJBgAAAA==.',
Jo='Jojobeän:BAAALgADCgUJBAAAAA==.Jone:BAAALgAECgMJAwAAAA==.Joobs:BAAALgAECgcJEAAAAA==.',
Ju='Jurahas:BAAALgADCggJEAAAAA==.Justforkicks:BAAALgADCgYJBgAAAA==.Justíce:BAAALgAECgQJBwAAAA==.',
Ka='Kahliea:BAAALgAECgUJCgAAAA==.Kaidance:BAABLgAECn8WAAIiAAcJ3Q7xBAD1AAAiAAcJ3Q7xBAD1AAAAAA==.Kaisaze:BAAALgAECgUJCQAAAA==.Kaiser:BAAALgAECgMJAwAAAA==.Kaluno:BAAALgADCgEJAQAAAA==.Kapachka:BAAALgAECgIJAgAAAA==.Katmarie:BAAALgADCgkJHQAAAA==.Kayssa:BAAALgAECggJEAAAAA==.Kazothor:BAAALgAECgUJCgAAAA==.',
Ke='Keebo:BAAALgADCgMJAwAAAA==.Kellandriiya:BAAALgADCgUJBQAAAA==.Keria:BAACLgAFFH8WAAMPAAYJURy1AADLAQAPAAUJtR61AADLAQANAAYJgAipAwBuAQAuAAQKfy8AAw8ACQmkJY4AAN8DAA8ACQmbJY4AAN8DAA0ACQl8GgAAAAAAAAAA.',
Kh='Kharfáz:BAAALgAECgEJAQAAAA==.Khasmeen:BAAALgAECgUJBQAAAA==.Khorn:BAAALgADCgcJBwAAAA==.',
Ki='Kifd:BAABLgAECn8rAAIhAAgJ0SOAAgBDAwAhAAgJ0SOAAgBDAwAAAA==.Kinzy:BAAALgADCgkJDgAAAA==.Kiretsu:BAABLgAECn8YAAIFAAgJ2RXtUwA8AgAFAAgJ2RXtUwA8AgAAAA==.',
Ko='Koder:BAAALgAECgYJDwAAAA==.Kodykinns:BAAALgAECgcJBgAAAA==.Kovus:BAAALgAECgQJBAAAAA==.',
Kr='Kristaan:BAAALgADCgQJBAAAAA==.',
Ky='Kyliejenner:BAAALgAECgEJAQAAAA==.',
La='Ladamirea:BAABLgAECn8fAAMiAAgJiCKLAQAJAwAiAAgJiCKLAQAJAwANAAEJlAcr5wArAAAAAA==.Lamashtu:BAABLgAECn8UAAIXAAYJMhGILQBzAQAXAAYJMhGILQBzAQAAAA==.Lanardris:BAAALgADCgYJCAAAAA==.Landoras:BAAALgADCgQJBAAAAA==.Lashar:BAAALgADCgcJBwAAAA==.Lawlipopkid:BAABLgAECn8YAAIKAAgJHw26EwCDAQAKAAgJHw26EwCDAQAAAA==.Layssar:BAAALgAECgYJCAAAAA==.',
Le='Lefrench:BAACLgAFFH8JAAIjAAQJdgkJBADkAAAjAAQJdgkJBADkAAAuAAQKfxgAAiMACAkoH/sHAPoCACMACAkoH/sHAPoCAAAA.Legendarea:BAAALgADCgIJAgAAAA==.Legionstorm:BAAALgAECgEJAgAAAA==.Lemmy:BAAALgADCgkJCQAAAA==.Lexzan:BAAALgAECgYJDQAAAA==.',
Li='Lilas:BAAALgAECgMJAwAAAA==.Lilifa:BAAALgAECgYJEgAAAA==.Lilillidari:BAAALgAECgEJAQABLgAFFAQJBwAHALcZAA==.Lilmontaro:BAACLgAFFH8HAAMHAAQJtxlYIQATAQAHAAMJih1YIQATAQAkAAIJcQrlAgChAAAuAAQKfysAAgcACAlhIqsQABgDAAcACAlhIqsQABgDAAAA.Linali:BAAALgAECgYJEwAAAA==.Liona:BAAALgADCgIJAgAAAA==.Lisey:BAABLgAECn8XAAMEAAgJDRlFHwAFAgAEAAcJKxtFHwAFAgADAAYJfxQYUQBiAQAAAA==.Lisong:BAAALgADCgYJCgAAAA==.Listari:BAAALgAECgcJDQAAAA==.Littlebuns:BAAALgAECgQJCAAAAA==.',
Lo='Lohkin:BAAALgAECgYJEAAAAA==.Loreleí:BAAALgADCgkJDAABLgAECgYJEgAIAAAAAA==.Lotherun:BAAALgAECgUJCQAAAA==.',
Lu='Lucïna:BAAALgAECgYJEAAAAA==.Ludk:BAAALgAECgEJAgAAAA==.Lumiela:BAAALgADCgkJFgAAAA==.Luminah:BAAALgAECgYJEQAAAA==.Luni:BAAALgAECgEJAQAAAA==.Lunì:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.Luxanna:BAAALgADCgkJEQAAAA==.',
Ly='Lysithea:BAAALgAECgYJDQAAAA==.',
Ma='Mageblaster:BAAALgADCgQJBAAAAA==.Maggnut:BAABLgAECn8UAAISAAgJ7BeBHQBiAgASAAgJ7BeBHQBiAgAAAA==.Mairek:BAABLgAECn8XAAMlAAcJxB2MAAD+AQAlAAcJxB2MAAD+AQAFAAEJQw7lfgEpAAAAAA==.Makarios:BAAALgADCgcJAgAAAA==.Maleigoron:BAABLgAECn8VAAIZAAgJRgcRcwB4AQAZAAgJRgcRcwB4AQAAAA==.Malestrom:BAAALgADCgUJBQAAAA==.Malkuri:BAABLgAECn8cAAIdAAgJCxcOGwBNAgAdAAgJCxcOGwBNAgAAAA==.Manapoppins:BAAALgADCgUJBQAAAA==.Maranne:BAAALgAECgYJEAAAAA==.Marolt:BAAALgADCgkJCQABLgAECgYJFAAYAMUcAA==.Masonite:BAAALgADCggJCAAAAA==.Mauser:BAAALgADCgUJBQABLgAFFAQJCAAGAP8VAA==.',
Mc='Mcbasketball:BAAALgAECgYJEwAAAA==.Mcchickenman:BAABLgAECn8bAAIHAAcJqyNVJgCiAgAHAAcJqyNVJgCiAgAAAA==.',
Me='Mechagnome:BAAALgADCgEJAQAAAA==.Mechaljaxon:BAAALgAECgcJEgAAAA==.Melyssa:BAAALgADCgYJBgAAAA==.Memeologist:BAACLgAFFH8MAAIjAAQJByNLAACgAQAjAAQJByNLAACgAQAuAAQKfyMAAiMACQlUI3YBAJ4DACMACQlUI3YBAJ4DAAAA.Meowdy:BAABLgAECn8nAAIUAAgJVBxPAgAuAgAUAAgJVBxPAgAuAgAAAA==.Metapal:BAACLgAFFH8FAAIOAAIJSRVfBACOAAAOAAIJSRVfBACOAAAuAAQKfyEAAg4ACAlXGEUKACsCAA4ACAlXGEUKACsCAAAA.Metasham:BAAALgAECgcJDQABLgAFFAIJBQAOAEkVAA==.',
Mi='Mienaz:BAAALgADCggJBgAAAA==.Miiaa:BAAALgAECggJDQAAAA==.Milane:BAAALgAECgMJAwAAAA==.Milktank:BAAALgAFFAEJAQAAAA==.Millea:BAAALgAECgYJDAAAAA==.Mindsight:BAAALgADCgcJBAAAAA==.Mirian:BAAALgAECgUJBQAAAA==.Mistystrike:BAAALgAECgcJAwAAAA==.Miztaken:BAAALgAECgYJDAAAAA==.',
Mo='Moirasha:BAABLgAECn8YAAMZAAcJ6gQGJAAJAQAZAAcJ6gQGJAAJAQAaAAUJrgTCPADBAAAAAA==.Mojorisen:BAAALgAECgQJBAAAAA==.Monran:BAAALgAECgUJBQAAAA==.Moonlixer:BAAALgAECgQJBAAAAA==.Moosand:BAAALgAECgcJEgAAAA==.Morgorath:BAAALgAECgYJCwAAAA==.Mortivus:BAAALgAECgQJBAAAAA==.',
Mu='Mulgaist:BAAALgADCgYJBgAAAA==.Mulvane:BAAALgAECgQJBAAAAA==.Munkii:BAAALgADCgIJAgABLgAECgMJAwAIAAAAAA==.Murphyb:BAAALgAECgMJBAAAAA==.Mustachio:BAAALgAECgcJEgAAAA==.',
Mv='Mvpj:BAACLgAFFH8FAAMKAAIJsghNJgCeAAAKAAIJsghNJgCeAAAJAAIJog1yCQCQAAAuAAQKfxsAAwoACAmfIGACAJsCAAoACAmfIGACAJsCAAkAAwm8B0N7AIwAAAAA.',
My='Myrrim:BAABLgAECn8YAAIDAAgJVxatCQC/AQADAAgJVxatCQC/AQAAAA==.Mysweetness:BAAALgAECgQJBAAAAA==.',
Mz='Mziao:BAAALgAECgUJBgAAAA==.',
['Më']='Mëlly:BAAALgADCgMJAwAAAA==.',
['Mô']='Môruden:BAAALgADCgYJBwAAAA==.',
Na='Naahmi:BAAALgAECgQJCAAAAA==.Nalexia:BAAALgAECgIJAgAAAA==.Namma:BAAALgADCgcJCgAAAA==.Narbw:BAAALgAECgEJAQABLgAECgMJBgAIAAAAAA==.Narbzy:BAAALgAECgMJBgAAAA==.Naytear:BAAALgAECgEJAQAAAA==.Nazend:BAAALgADCgQJBAABLgAECgQJBAAIAAAAAA==.',
Ne='Neall:BAABLgAECn8YAAIhAAcJgwtgBwAhAQAhAAcJgwtgBwAhAQAAAA==.Necroflame:BAAALgADCgEJAQAAAA==.Necronym:BAAALgAFFAIJAgAAAA==.Nef:BAAALgAECgQJCgAAAA==.Negapriest:BAAALgAECgEJAQAAAA==.Nei:BAAALgAECgEJAQABLgAECgQJCgAIAAAAAA==.Nekoshade:BAAALgADCgQJBAAAAA==.Nekoshâde:BAAALgAECgEJAQAAAA==.Nemrin:BAAALgADCgIJAgAAAA==.Nendetre:BAABLgAECn8UAAMYAAYJxRxLFQD1AQAYAAYJxRxLFQD1AQAbAAQJVA1TKQDUAAAAAA==.Nerelia:BAAALgADCgYJCwAAAA==.Nevets:BAAALgADCgYJBgAAAA==.Neô:BAAALgAECgEJAQAAAA==.',
Ni='Nightbird:BAAALgADCgYJBgAAAA==.Nighthazy:BAAALgADCgMJBAAAAA==.Nimvexium:BAAALgAECgYJBgABLgAECgYJFgASAHgWAA==.',
No='Notbyworks:BAAALgAECgYJDwAAAA==.Notorious:BAAALgAECggJHQAAAQ==.',
Ny='Nykyrian:BAABLgAECn8fAAMjAAgJzBfRBACwAQAjAAcJ3RfRBACwAQAGAAMJHweZVQB6AAAAAA==.',
Ob='Oblast:BAAALgAECgcJBwAAAA==.',
Od='Odb:BAAALgAECgUJDgAAAA==.',
Ol='Oldmanjey:BAAALgAECgYJCwAAAA==.Olmanjankins:BAAALgAECgcJAgAAAA==.',
On='Onara:BAAALgADCgIJAgAAAA==.Onlydks:BAAALgAECgcJCQABLgAECgYJFgASAHgWAA==.Onlyslams:BAABLgAECn8WAAQSAAYJeBaaTABzAQASAAYJZBSaTABzAQAhAAIJcxpFNQCcAAAmAAIJJQpvNABfAAAAAA==.',
Op='Opil:BAAALgAECgMJBAAAAA==.',
Or='Orter:BAABLgAECn8dAAIHAAcJyR08CAD7AQAHAAcJyR08CAD7AQAAAA==.',
Pa='Panakoa:BAAALgADCgMJAwAAAA==.Pandishar:BAAALgAECgMJAwAAAA==.Papsfear:BAABLgAECn8XAAIZAAYJbRhmXgCuAQAZAAYJbRhmXgCuAQAAAA==.Parce:BAABLgAECn8ZAAMJAAgJISQmCwDGAgAJAAcJKCQmCwDGAgAKAAgJLxDYDgCwAQAAAA==.',
Pe='Peacebringer:BAAALgADCgcJCAAAAA==.Pengyoa:BAABLgAECn8UAAINAAcJBxlOOQAPAgANAAcJBxlOOQAPAgAAAA==.',
Ph='Phydaux:BAAALgAECgMJBgAAAA==.',
Pi='Pinkponyclub:BAAALgADCgcJBgAAAA==.Pinpow:BAAALgADCgcJCQAAAA==.Pizza:BAAALgADCgQJBAAAAA==.Pizzaman:BAAALgAECgYJCwAAAA==.',
Po='Poxi:BAABLgAECn8WAAIFAAYJ0yGzYgAUAgAFAAYJ0yGzYgAUAgABLgAECggJFgAUAA0XAA==.',
Pr='Proxima:BAAALgADCgIJAgAAAA==.',
Pt='Ptoughneigh:BAABLgAECn8WAAIKAAgJMBqtCQDxAQAKAAgJMBqtCQDxAQAAAA==.',
Pu='Publicus:BAAALgADCgkJDwABLgAECgYJDAAIAAAAAA==.Puckish:BAACLgAFFH8FAAMQAAIJCgnCFgBtAAAQAAIJTQHCFgBtAAARAAEJABEFFQBBAAAuAAQKfyQAAxAACAlUCrkhAIYBABAACAkVCbkhAIYBABEACAkWBis4AFsBAAAA.Punnisher:BAABLgAECn8fAAQZAAcJihpAEgB/AQAZAAcJihpAEgB/AQAnAAEJAACtLABFAAAaAAEJAABubQA6AAAAAA==.',
['Pä']='Päiñ:BAAALgAECgEJAQAAAA==.',
Qu='Quackys:BAAALgAECgYJEQAAAA==.Quickbeam:BAAALgAECgcJCwAAAA==.Quorrad:BAAALgAECgQJAwAAAA==.Quäckys:BAAALgADCgcJDQAAAA==.',
Ra='Radünz:BAAALgAECgEJAQABLgAECggJGAAgALsdAA==.Raelianna:BAAALgAECgYJEgABLgAECgcJFgAlANcgAA==.Raevin:BAAALgADCgMJBgAAAA==.Raewyna:BAAALgAECgIJAgAAAA==.Ragi:BAAALgADCgMJAwAAAA==.Rahlian:BAAALgAECgUJCQABLgAECgYJBgAIAAAAAA==.Rahlock:BAAALgAECgYJBgAAAA==.Raine:BAABLgAECn8dAAMMAAgJ/xuTFgBhAgAMAAgJ/xuTFgBhAgATAAEJMx58gABFAAAAAA==.Rainingblood:BAAALgADCgMJAwAAAA==.Rainjar:BAABLgAECn8ZAAIGAAYJKiSPBADqAQAGAAYJKiSPBADqAQAAAA==.Ranron:BAAALgADCgYJBgAAAA==.Raphael:BAABLgAECn8ZAAIHAAYJMQubJAAFAQAHAAYJMQubJAAFAQAAAA==.Rasik:BAABLgAECn8dAAMSAAgJBSEhBAD+AQASAAcJhCEhBAD+AQAhAAEJCR6KEQBXAAAAAA==.Ravenblood:BAAALgADCgcJBwAAAA==.Rayel:BAAALgAECgcJEAAAAA==.Raylyn:BAAALgADCgEJAQAAAA==.',
Re='Redoubtf:BAABLgAECn8ZAAIKAAgJ2BJ2TwDzAQAKAAgJ2BJ2TwDzAQAAAA==.Refourper:BAAALgADCgcJEwAAAA==.Rendingo:BAABLgAECn8YAAMiAAgJqRtMBgAyAgAiAAgJWBtMBgAyAgANAAYJdxlKEwBkAQAAAA==.Rennlei:BAABLgAECn8VAAINAAgJiyFsBgATAgANAAgJiyFsBgATAgAAAA==.',
Rh='Rhaegare:BAABLgAECn8UAAMmAAYJPhwMGAA5AQAmAAQJlhwMGAA5AQASAAUJSBFIYAAvAQAAAA==.Rhome:BAABLgAECn8ZAAMXAAcJkhmZJQCrAQAXAAcJkhmZJQCrAQARAAUJ2hNmDAArAQAAAA==.',
Ri='Rialu:BAABLgAECn8WAAIRAAgJ9Qr3CQBcAQARAAgJ9Qr3CQBcAQAAAA==.Ribald:BAAALgADCgUJBQAAAA==.Rickgrimes:BAAALgAECgYJDQAAAA==.Rime:BAABLgAECn8fAAIFAAgJeSWpCgBvAwAFAAgJeSWpCgBvAwAAAA==.Risandra:BAAALgADCgYJBwAAAA==.',
Ro='Rotcorpse:BAABLgAECn8XAAIRAAgJHyF+BQD4AgARAAgJHyF+BQD4AgAAAA==.',
Ru='Rubyred:BAAALgADCgUJBQAAAA==.Ruddam:BAAALgAECgMJAwAAAA==.Runier:BAAALgADCgUJBQABLgAECgEJAQAIAAAAAA==.Runikh:BAAALgAECgMJAwAAAA==.',
Ry='Rylandor:BAAALgADCggJCAAAAA==.',
['Rä']='Rägekäge:BAAALgADCgYJCAAAAA==.Räveñz:BAAALgAECgYJEAAAAA==.',
Sa='Saariell:BAAALgAECgYJEgAAAA==.Sabrielle:BAAALgAECgkJAQAAAA==.Sagremor:BAAALgAECgQJBAABLgAECgcJGwALAJQkAA==.Saintabes:BAABLgAECn8XAAQXAAgJbhM8GwAEAgAXAAcJWxY8GwAEAgAQAAYJOBU4IgCCAQARAAMJbwT6agB/AAAAAA==.Saintlaurent:BAAALgADCgEJAQABLgAECggJHQAIAAAAAA==.Saintthorlak:BAAALgAECgYJDgAAAA==.Saiorse:BAABLgAECn8dAAIDAAgJMArKEABOAQADAAgJMArKEABOAQAAAA==.Sandara:BAABLgAECn8YAAIXAAcJ5iKMAgApAgAXAAcJ5iKMAgApAgAAAA==.Sanguineliam:BAAALgADCgEJAQAAAA==.Sanrinn:BAAALgADCgkJCQABLgAECgYJDAAIAAAAAA==.Santocarbón:BAAALgAECgQJBAAAAA==.Saphera:BAAALgADCgEJAgAAAA==.Sarahann:BAAALgAECgUJDAAAAA==.Sarahboom:BAACLgAFFH8HAAIFAAQJighKIQA9AQAFAAQJighKIQA9AQAuAAQKfyAAAgUACAmcGr1AAHYCAAUACAmcGr1AAHYCAAAA.',
Sc='Scaia:BAAALgAECgYJDgAAAA==.Scapegoat:BAEALgAECggJHQAAAQ==.Scaryspice:BAAALgAECgYJEgAAAA==.Scraime:BAAALgAECggJCAAAAA==.',
Se='Seethe:BAAALgADCgYJCwAAAA==.Seilah:BAAALgAECgYJEwAAAA==.Seliah:BAAALgAECgYJEAAAAA==.Sennis:BAABLgAECn8VAAIBAAcJOx7xEACaAgABAAcJOx7xEACaAgAAAA==.Senpai:BAAALgAECgMJBQAAAA==.Sephora:BAAALgAECgYJCgAAAA==.Seventhshadë:BAAALgADCgEJAQAAAA==.',
Sh='Shadoris:BAAALgAECgcJEwAAAA==.Shadowglade:BAAALgAECgcJEwAAAA==.Shalanoth:BAAALgAECgYJEgAAAA==.Shalltear:BAAALgAECgUJCgAAAA==.Shamashiznit:BAAALgADCgQJAwAAAA==.Shamizzle:BAAALgAECgcJCgAAAA==.Shammydavis:BAAALgAECgcJEwAAAA==.Shammylove:BAAALgAECgQJBAAAAA==.Shessra:BAAALgAECgMJAwABLgAECgYJBgAIAAAAAA==.Shiftyloki:BAAALgAECgEJAQABLgAECgkJCgAIAAAAAA==.Shockoctopus:BAAALgADCgYJBgAAAA==.Shootinblanx:BAAALgADCgQJBAAAAA==.Shraan:BAAALgAECgQJBAAAAA==.Shrapnel:BAAALgAECgYJDwAAAA==.Shàytan:BAABLgAECn8dAAIPAAcJ/ROuHwDAAQAPAAcJ/ROuHwDAAQAAAA==.',
Si='Sinistral:BAAALgAECgEJAQAAAA==.Sinvyx:BAAALgADCgUJBQAAAA==.',
Sk='Skullchopper:BAAALgADCgkJEgABLgAECgYJDQAIAAAAAA==.',
Sl='Slashanon:BAAALgADCgYJBwABLgADCgcJEwAIAAAAAA==.Slise:BAAALgADCggJCAAAAA==.',
Sm='Smithers:BAABLgAECn8dAAQZAAgJxCEwCwDDAQAZAAUJqx8wCwDDAQAaAAMJrCNyIwA9AQAnAAIJ5x8/FgDQAAAAAA==.',
Sn='Snappycakes:BAAALgAECgMJAwAAAA==.Sneakybunny:BAABLgAECn8dAAIVAAgJPQLWAgDmAAAVAAgJPQLWAgDmAAAAAA==.Snowvocaine:BAAALgAECgcJDgAAAA==.',
So='Sorabjr:BAAALgAECgUJCgAAAA==.Sorim:BAAALgADCgcJCQAAAA==.Soulbreaker:BAAALgAECgYJDQAAAA==.Soulstice:BAAALgADCgkJGgAAAA==.',
Sp='Spandexshoe:BAAALgADCgMJAwAAAA==.Spewn:BAAALgAECgQJBAAAAA==.Spyrofella:BAABLgAECn8aAAMUAAkJlyC2BQAqAwAUAAkJlyC2BQAqAwAbAAEJshe/PwAxAAAAAA==.',
Sq='Squeance:BAAALgADCgIJAgAAAA==.',
St='Starblunder:BAAALgAECgYJBgAAAA==.Steppriest:BAAALgADCgEJAQAAAA==.Sticky:BAAALgAECgcJCQAAAA==.Stormwild:BAAALgADCgcJEAABLgAECgYJBgAIAAAAAA==.',
Su='Sundersremix:BAAALgAECgEJAQAAAA==.Sunsparrow:BAAALgAECgQJBgAAAA==.',
Sw='Swamp:BAAALgADCgMJBAAAAA==.Sweetchicka:BAAALgADCgUJBQAAAA==.Swiftysarah:BAAALgADCgMJBAABLgAFFAQJBwAFAIoIAA==.',
Sy='Syvarris:BAAALgAFFAIJAgAAAA==.',
['Sè']='Sèvènthshade:BAAALgADCgEJAQAAAA==.',
['Sú']='Súndavar:BAEALgADCgMJAwABLgAFFAQJCQAHAGQZAA==.',
Ta='Taborax:BAAALgAECgYJDAAAAA==.Taeveren:BAAALgAECgUJBwAAAA==.Taikwondoh:BAAALgADCgkJCQABLgAECgkJJAAJAOwNAA==.Tandaiff:BAAALgADCgIJAgAAAA==.Tandea:BAAALgADCgkJCQAAAA==.Taner:BAAALgAFFAEJAQAAAA==.Tankajahari:BAAALgAECgYJBgAAAA==.Tarayn:BAAALgAECgYJEwAAAA==.Tazenath:BAAALgAECgQJBAAAAA==.',
Te='Teagan:BAAALgADCgQJBAAAAA==.Tealeaf:BAAALgAECgcJBwAAAA==.Teeagan:BAAALgADCgYJBgAAAA==.Teoritta:BAEALgAECgYJEwAAAA==.',
Th='Thalimus:BAAALgADCggJDgAAAA==.Thedarkbagel:BAAALgAECgIJAgAAAA==.Thefarter:BAAALgAECgYJCwAAAA==.Thewhitelion:BAAALgAECgMJAwAAAA==.Thickbacon:BAAALgADCgMJAwAAAA==.Thorin:BAAALgADCgYJCAABLgAECggJIAAZAJUhAA==.Thorzson:BAAALgAECgEJAQAAAA==.Thudd:BAAALgADCgcJFgAAAA==.Thìerry:BAACLgAFFH8GAAIFAAIJESHnFgDBAAAFAAIJESHnFgDBAAAuAAQKfycAAwUACAlJJdQCAKYCAAUACAlAJdQCAKYCACUABglMIsQFAMoBAAAA.',
Ti='Tigg:BAABLgAECn8fAAMHAAgJySACJgCkAgAHAAgJySACJgCkAgAkAAcJXg9lAwAYAQAAAA==.Tirrenus:BAAALgAECgMJCAAAAA==.Tiwi:BAAALgADCgYJBgAAAA==.',
To='Tonytonychop:BAAALgAECgQJCwABLgAECgYJHAAEACkUAA==.Tory:BAAALgADCgEJAQAAAA==.Toshidot:BAACLgAFFH8FAAIZAAIJORmpGQChAAAZAAIJORmpGQChAAAuAAQKfyUAAhkACAn+HjUHAP8BABkACAn+HjUHAP8BAAAA.Toshy:BAAALgADCggJFgABLgAFFAIJBQAZADkZAA==.Totesmygoats:BAAALgAECgQJCgAAAA==.',
Tr='Translucent:BAABLgAECn8eAAMTAAgJNgqHCwBDAQATAAgJNgqHCwBDAQAMAAYJswSdZQD4AAAAAA==.Trap:BAAALgAECgEJAgABLgAECgYJCgAIAAAAAA==.Travaman:BAAALgAECgYJEAAAAA==.Trazatra:BAABLgAECn8UAAMYAAgJkA3AGQC/AQAYAAgJkA3AGQC/AQAUAAQJHhRDPwDsAAAAAA==.Treelock:BAAALgADCgEJAQAAAA==.Treestars:BAAALgAECgUJBgAAAA==.Truelilimain:BAAALgADCgYJCgAAAA==.',
Tu='Tunalongarms:BAAALgADCgcJDQABLgAECgQJBAAIAAAAAA==.Tuonadari:BAAALgADCgkJGgAAAA==.Tusthree:BAAALgAECgcJCAABLgAECggJGwAJAL4cAA==.Tustone:BAABLgAECn8bAAIJAAgJvhyOEgB+AgAJAAgJvhyOEgB+AgAAAA==.',
Tw='Twelfthplnet:BAAALgADCgcJEAAAAA==.',
['Tù']='Tùst:BAAALgAECgYJDwABLgAECggJGwAJAL4cAA==.',
Ur='Ursôc:BAAALgADCgMJAwABLgAFFAQJBwAFAIoIAA==.Urzukul:BAAALgADCgEJAQAAAA==.',
Us='Usodead:BAAALgAECgYJDgAAAA==.',
Va='Vacia:BAAALgAECgQJBQAAAA==.Vader:BAAALgAECgEJAQABLgAECgcJFAATALIVAA==.Valaeh:BAAALgAECgEJAQAAAA==.Valgor:BAAALgADCggJFQAAAA==.Valkurichi:BAAALgADCgYJBgABLgAFFAUJEwAHAKcmAA==.Valkuridk:BAACLgAFFH8TAAIHAAUJpyZVAQAjAgAHAAUJpyZVAQAjAgAuAAQKfx0AAgcACAlyJsYFAHkDAAcACAlyJsYFAHkDAAAA.Vallerian:BAAALgADCgQJBAAAAA==.Vandy:BAAALgAECggJEQAAAA==.Vanthe:BAAALgADCgcJBwAAAA==.Vaygrant:BAAALgADCgkJGgAAAA==.',
Ve='Vedo:BAABLgAECn8lAAMdAAgJ1CERCAAbAwAdAAgJbSERCAAbAwAeAAYJMh6LCADgAQAAAA==.Vedora:BAAALgADCgMJBQAAAA==.Velensia:BAAALgADCgkJHQAAAA==.Velf:BAAALgAECgEJAQAAAA==.Velind:BAAALgADCgkJDAAAAA==.Velnela:BAAALgADCgEJAQAAAA==.Veradis:BAAALgADCgUJBQAAAA==.Vetro:BAABLgAECn8XAAICAAcJDBWeAgBuAQACAAcJDBWeAgBuAQAAAA==.',
Vi='Vindar:BAAALgAECgQJBQAAAA==.Vinland:BAAALgADCggJDAAAAA==.Vinsmokesanj:BAAALgAECgEJAQAAAA==.Violet:BAAALgAECgQJBwAAAA==.Viris:BAABLgAECn8YAAMWAAgJMQ1ADQAcAQAWAAYJehBADQAcAQAGAAgJcwjtOwD4AAAAAA==.Virulent:BAAALgAECgMJBQAAAA==.Vissarion:BAAALgAECgYJEwAAAA==.',
Vl='Vl:BAAALgAECgcJEgAAAA==.Vladak:BAAALgAECggJEQAAAA==.',
Vo='Voc:BAAALgAECgcJCQAAAA==.Voluptus:BAAALgAECgYJDQAAAA==.',
Vu='Vulkin:BAABLgAECn8UAAITAAcJshW8CgBPAQATAAcJshW8CgBPAQAAAA==.Vulric:BAAALgADCgYJBgAAAA==.',
Vv='Vv:BAABLgAECn8aAAIeAAgJchjCFwB7AgAeAAgJchjCFwB7AgAAAA==.',
Vy='Vyridion:BAAALgADCgMJAwAAAA==.Vyridionsham:BAAALgAECgMJAwAAAA==.Vyx:BAAALgAECgUJCwAAAA==.',
Wa='Warkast:BAAALgAECgUJDgAAAA==.Waymán:BAAALgADCgcJDQAAAA==.',
We='Weebjones:BAAALgAECggJEwAAAA==.',
Wi='Windrift:BAAALgAECgYJEgAAAA==.',
Wo='Worgenformer:BAAALgADCgYJBQAAAA==.Worgenmytail:BAAALgADCgMJAwAAAA==.',
Wy='Wyldone:BAAALgADCgYJBgAAAA==.',
['Wà']='Wànderlust:BAAALgADCgMJAwAAAA==.',
['Wä']='Wäyman:BAABLgAECn8dAAIoAAgJaxLOAgC5AQAoAAgJaxLOAgC5AQAAAA==.',
['Wî']='Wînë:BAAALgADCgEJAQAAAA==.',
Xa='Xanden:BAAALgADCgYJBwAAAA==.Xaranthia:BAABLgAECn8ZAAIPAAgJLBFBGAAFAgAPAAgJLBFBGAAFAgAAAA==.',
Xe='Xembra:BAAALgAECgYJCwAAAA==.',
Xh='Xhyon:BAAALgAECgYJEgAAAA==.',
Xi='Xiamira:BAAALgAECgMJBQAAAA==.',
Xm='Xmcdizzle:BAABLgAECn8YAAIFAAcJChKmGACBAQAFAAcJChKmGACBAQAAAA==.',
Xy='Xylarra:BAABLgAECn8dAAIPAAgJthxnAgDyAQAPAAgJthxnAgDyAQAAAA==.Xyz:BAAALgAFFAEJAQAAAA==.',
Ya='Yautja:BAABLgAECn8dAAIdAAcJtxRFBABUAQAdAAcJtxRFBABUAQAAAA==.',
Yo='Yoruba:BAAALgADCgcJDAABLgAECgYJDwAIAAAAAA==.',
Yu='Yus:BAAALgAECgIJAgAAAA==.',
Za='Zaleyne:BAAALgADCgEJAQAAAA==.Zamali:BAAALgAECgYJEAAAAA==.Zantris:BAAALgAECgYJEwAAAA==.Zaralystia:BAAALgADCgkJEgAAAA==.Zartella:BAAALgAECgUJDwAAAA==.',
Ze='Zeleste:BAAALgADCggJFwAAAA==.Zelti:BAAALgAECgYJBgAAAA==.Zendraza:BAAALgAECgYJBgAAAA==.Zenowulf:BAAALgADCggJFQAAAA==.Zephyrion:BAABLgAFFH8FAAIcAAMJPgv8CwC4AAAcAAMJPgv8CwC4AAAAAA==.Zepplin:BAAALgAECgYJEAAAAA==.Zetro:BAAALgADCgYJBwAAAA==.',
Zi='Zionus:BAAALgADCgEJAQAAAA==.',
Zr='Zreydyn:BAAALgADCgMJBAAAAA==.',
Zu='Zuma:BAABLgAECn8dAAIFAAgJEhq0DQDcAQAFAAgJEhq0DQDcAQAAAA==.',
Zy='Zyhunt:BAAALgADCgUJCAAAAA==.',
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

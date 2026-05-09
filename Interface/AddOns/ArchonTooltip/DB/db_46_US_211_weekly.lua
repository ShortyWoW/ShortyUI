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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Shaman-Restoration','Druid-Feral','Druid-Restoration','Priest-Shadow','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Warlock-Affliction','Unknown-Unknown','Rogue-Assassination','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Evoker-Preservation','DeathKnight-Unholy','Warrior-Protection','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Monk-Mistweaver','Priest-Holy','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','Monk-Windwalker','Druid-Guardian',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Achooe:BAABLgAECn8eAAMBAAgJnQW2GwC2AAABAAcJMQa2GwC2AAACAAEJJgL9IAEdAAAAAA==.',
Ad='Adrel:BAAALgAECgQJBAAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQ2CAAnAwADAAgJNiQ2CAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw4DQCPAgAEAAgJ3Bo4DQCPAgAFAAYJGhHQiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn8iAAQGAAgJvQ5iDwCzAQAGAAgJow1iDwCzAQAHAAUJtQa+WwDUAAAIAAUJBAbPlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8fAAIJAAgJ3BBpOwC2AQAJAAgJ3BBpOwC2AQAAAA==.Agathorz:BAAALgAECgEJAgAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgYJCQAAAA==.',
Ak='Akiras:BAAALgADCgYJBgAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECggJFwAKADQdAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAABLgAECn8kAAMDAAgJcSGyBgCDAgADAAgJcSGyBgCDAgALAAYJ9BD3EAA9AQAAAA==.Allei:BAAALgAECgMJAwABLgAECggJJwAMAK8YAA==.Alyndrya:BAABLgAECn8TAAMEAAcJ+hR6DwCKAQAEAAcJ+hR6DwCKAQAFAAYJjRCLTgANAQAAAA==.Alyndrys:BAABLgAECn8YAAINAAcJlw4AEgCNAQANAAcJlw4AEgCNAQAAAA==.',
Am='Amelialynne:BAABLgAECn8kAAIFAAgJmBO7KQCSAQAFAAgJmBO7KQCSAQAAAA==.Amithralia:BAABLgAECn8VAAIOAAgJohycDACCAgAOAAgJohycDACCAgAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAAALgAECgUJDgAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anissel:BAABLgAECn8aAAIPAAgJHRFLGQByAQAPAAgJHRFLGQByAQAAAA==.Anzarna:BAAALgAECgYJEQAAAA==.',
Ao='Aohikari:BAAALgADCgUJBgABLgAFFAYJEwAOAH0eAA==.Aokuma:BAACLgAFFH8TAAIOAAYJfR6BAQAGAgAOAAYJfR6BAQAGAgAuAAQKfycAAw4ACQlCJNwDAC0DAA4ACQlCJNwDAC0DABAAAwlSIQdIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAAALgAECgcJEgAAAA==.',
Aq='Aquaten:BAAALgAECgUJEgAAAA==.',
Ar='Arashinigon:BAAALgAECggJEgAAAA==.Arceus:BAAALgAECgIJAwAAAA==.Archaon:BAABLgAECn8XAAMRAAYJIQ0YXAAbAQARAAYJIQ0YXAAbAQASAAEJAACGNQAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnncACaAQACAAYJeRnncACaAQAAAA==.Ariandise:BAAALgAECgMJAwAAAA==.Arick:BAABLgAECn8VAAICAAgJYRprTwDzAQACAAgJYRprTwDzAQAAAA==.Ark:BAABLgAECn86AAMMAAkJiyb/AQBrAwAMAAkJiyb/AQBrAwATAAYJIyVmDAAVAgAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgIJAgAAAA==.Asmódeus:BAABLgAECn8cAAQUAAgJoA73DQBTAQARAAgJCQp+QABoAQAUAAYJWw73DQBTAQASAAQJYQ1QPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAABLgAECn8XAAIJAAgJGAzdSQCKAQAJAAgJGAzdSQCKAQAAAA==.',
['Aì']='Aìo:BAAALgAECgUJEAABLgAECgYJCQAVAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJAgAAAA==.Baelhay:BAAALgAECgUJEgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Belitha:BAABLgAECn8jAAIFAAkJmx8JEwDoAgAFAAkJmx8JEwDoAgAAAA==.Belmaris:BAABLgAECn8eAAIWAAgJaBa/AwDrAQAWAAgJaBa/AwDrAQAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAAALgAECgYJDQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAAALgAECggJEAAAAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAAALgAECgUJDQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8WAAIXAAYJtB4GBgCjAQAXAAYJtB4GBgCjAQAAAA==.Blegh:BAABLgAECn8hAAMYAAgJLx6iCgAxAgAYAAcJNh2iCgAxAgAZAAYJIBsgHwDKAQAAAA==.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn8qAAINAAkJEB51AQDQAgANAAkJEB51AQDQAgAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMCAAgJ+Am7sAAiAQACAAYJpQq7sAAiAQAaAAgJxAklLgAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8XAAIKAAgJNB30HQASAgAKAAgJNB30HQASAgAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAVAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAAALgAECggJDgAAAA==.Buggers:BAAALgAECgIJAgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAAALgAFFAEJAQABLgAFFAcJFwAbABkeAA==.',
Ca='Caiphage:BAABLgAECn8XAAIFAAgJORiQTADCAQAFAAgJORiQTADCAQAAAA==.Caladelm:BAAALgAECgYJDAAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8XAAIcAAcJegtzVABAAQAcAAcJegtzVABAAQAAAA==.Carlarae:BAABLgAECn8UAAIJAAYJOQTooADRAAAJAAYJOQTooADRAAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAAALgAFFAIJAgAAAA==.Cegeo:BAABLgAECn8tAAISAAgJsBRABADLAQASAAgJsBRABADLAQAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn8yAAIDAAkJWCFSAgD7AgADAAkJWCFSAgD7AgAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAABLgAECn8cAAMRAAYJ5x9oWQC7AQARAAUJyiBoWQC7AQAUAAQJSBjzEgD9AAAAAA==.',
Ci='Ciennajewel:BAAALgAECgcJBwAAAA==.Cirdle:BAAALgAECgcJEAAAAA==.Cirona:BAABLgAECn8XAAIOAAYJch5iGAACAgAOAAYJch5iGAACAgAAAA==.',
Cl='Clausewitz:BAABLgAECn8UAAIdAAgJCgqLEwAwAQAdAAgJCgqLEwAwAQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAABLgAECn8ZAAIRAAgJqxncGQAVAgARAAgJqxncGQAVAgAAAA==.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAVAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8gAAITAAgJ2ALzMADvAAATAAgJ2ALzMADvAAAAAA==.Creamyweamy:BAAALgAECgYJEgAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8aAAMJAAYJ8QpmewAaAQAJAAYJ8QpmewAaAQAeAAEJ6wGuIQAmAAAAAA==.Crucifixea:BAAALgADCgUJCgAAAA==.Cruzmaster:BAABLgAECn8UAAMTAAgJ3BI8FQCqAQATAAgJ3BI8FQCqAQAfAAQJqAsDHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8XAAIJAAcJYQUuewAbAQAJAAcJYQUuewAbAQAAAA==.',
Cu='Cupp:BAAALgAECgcJDgAAAA==.Cute:BAAALgAECgYJCAABLgAFFAYJEgAgAGQTAA==.',
Da='Daamass:BAAALgADCgMJAwAAAA==.Daddy:BAACLgAFFH8XAAIhAAYJiSKlAQBkAgAhAAYJiSKlAQBkAgAuAAQKf38AAiEACQmzJgcAABgEACEACQmzJgcAABgEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAVAAAAAA==.Daggonet:BAAALgAFFAEJAQAAAA==.Dalrin:BAABLgAECn8XAAMfAAYJ7A+uFQBiAQAfAAYJ7A+uFQBiAQATAAQJzAfjZwCjAAAAAA==.Darkcarnival:BAABLgAECn8eAAIRAAgJjxthFQA3AgARAAgJjxthFQA3AgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAABLgAECn8fAAIDAAkJiRdJLAADAgADAAkJiRdJLAADAgAAAA==.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgADCgcJDQABLgAECgUJCAAVAAAAAA==.Darthraider:BAAALgAECgQJCwAAAA==.Dasnotgood:BAAALgAECgUJDAAAAA==.Datoneshammy:BAAALgAECgYJCgAAAA==.Davrøs:BAAALgAECgIJBgAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8UAAIFAAgJTxQtJQCrAQAFAAgJTxQtJQCrAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAAALgAECgcJEgAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8XAAMiAAcJcxNyGQCCAQAiAAcJcxNyGQCCAQAPAAYJcgiMMADRAAAAAA==.Denidan:BAAALgADCgcJDAAAAA==.Dertus:BAABLgAECn8YAAIQAAgJeBWHEADLAQAQAAgJeBWHEADLAQAAAA==.Desdemona:BAABLgAECn8XAAIBAAcJQB5kBwDhAQABAAcJQB5kBwDhAQAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAAALgAECgQJBAABLgAECgYJEAAVAAAAAA==.',
Di='Dianimal:BAAALgAECgYJDQAAAA==.Dings:BAAALgADCggJDQAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8YAAMaAAcJoiL/BQDCAgAaAAcJoiL/BQDCAgACAAYJqB6FOQCaAQAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIcAAUJ0CH/DwCVAQAcAAUJ0CH/DwCVAQAuAAQKf0AAAhwACQl2JswAAH8DABwACQl2JswAAH8DAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8aAAMCAAcJcRlvPwAoAgACAAcJcRlvPwAoAgABAAQJfAFbLABJAAAAAA==.Doomfeather:BAAALgAECgEJAgAAAA==.Dorigog:BAABLgAECn8kAAICAAgJdRDvSwBiAQACAAgJdRDvSwBiAQAAAA==.',
Dr='Dragee:BAAALgAECgEJAgABLgAECggJFAAFAE8UAA==.Dragon:BAAALgAECgYJCwAAAA==.Dragonpunch:BAABLgAECn8fAAIhAAkJkxm3DAAeAgAhAAkJkxm3DAAeAgAAAA==.Driftyshaman:BAAALgAECgYJEQAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAAALgAECgcJDAAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Dw='Dworflundgrn:BAABLgAECn8aAAIfAAgJeQmuCgBqAQAfAAgJeQmuCgBqAQAAAA==.',
Dy='Dyamï:BAABLgAECn8eAAIhAAgJRBW3DwDyAQAhAAgJRBW3DwDyAQAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAAALgAECgYJDwAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8YAAITAAYJUAssLwD4AAATAAYJUAssLwD4AAAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Ellä:BAAALgAECgMJAwAAAA==.Elrythe:BAACLgAFFH8FAAIIAAMJNQz9KAD2AAAIAAMJNQz9KAD2AAAuAAQKfy8AAggACQlPIHsFANsCAAgACQlPIHsFANsCAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.',
Ev='Evilmorana:BAAALgAECgMJAwAAAA==.',
Fa='Fallyynn:BAAALgAECgYJCgAAAA==.Fatalii:BAAALgADCgEJAQABLgAECgcJAgAVAAAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAAALgAECgcJEQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgADCgYJBgAAAA==.',
Fl='Floofies:BAACLgAFFH8UAAIfAAUJUiFfAQCDAQAfAAUJUiFfAQCDAQAuAAQKfx8AAh8ACQmlJLUDAO8CAB8ACQmlJLUDAO8CAAAA.Floofyfu:BAAALgAECgYJCgABLgAFFAUJFAAfAFIhAA==.',
Fr='Fredrickk:BAAALgAECgIJBAABLgAECgMJAwAVAAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgIJAgAAAA==.Furryphase:BAACLgAFFH8PAAIMAAUJZRjqCACMAQAMAAUJZRjqCACMAQAuAAQKfx8AAgwACQn0Gw0NALUCAAwACQn0Gw0NALUCAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAUJFAAfAFIhAA==.Fuzzydunlop:BAAALgAECgYJCQAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgIJAwAAAA==.Gallin:BAAALgAECgIJAwAAAA==.Gauldangit:BAAALgAECgQJBQAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJDAAAAA==.',
Gl='Glaur:BAABLgAECn8jAAIMAAgJ6B3MDgBMAgAMAAgJ6B3MDgBMAgAAAA==.',
Go='Goatjira:BAAALgADCgEJAQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECggJFgAcABoeAA==.Gripisrdy:BAABLgAECn8eAAMcAAgJPx6OIgD7AQAcAAcJTR6OIgD7AQAjAAEJ7h2eMABWAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8dAAMkAAkJJSI8AAAuAwAkAAkJJSI8AAAuAwAlAAEJugwIXgA7AAAAAA==.Guìdo:BAAALgAECgUJCAAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAAALgAECgYJCAAAAA==.Hairyjolene:BAAALgAECgUJEgAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAECgkJJQAVAAAAAA==.Handsome:BAAALgADCgcJCAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIRAAcJGh+nJQB8AgARAAcJGh+nJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJCgAAAA==.Heycarlos:BAAALgAECgYJEQAAAA==.',
Hi='Hikaridh:BAABLgAFFH8DAAIFAAEJvxNVWQBNAAAFAAEJvxNVWQBNAAABLgAFFAYJEwAOAH0eAA==.Hikarimonk:BAAALgAECgEJAQABLgAFFAYJEwAOAH0eAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAYJEwAOAH0eAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgIJAwAVAAAAAA==.Holyblimblam:BAAALgAECgYJDwAAAA==.Hosemachine:BAABLgAECn8mAAMcAAgJAx7SFwA+AgAcAAgJlh3SFwA+AgAjAAcJ1xWjHQBcAQAAAA==.Hotpants:BAABLgAECn8cAAIPAAYJNA2OJAAeAQAPAAYJNA2OJAAeAQAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJCgAAAA==.Icyjackets:BAAALgAECgUJEgAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.',
Il='Ilamuna:BAAALgAECgEJAQABLgAECggJGgAPAB0RAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgADCgEJAQAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJkw9TIADaAQAIAAkJkw9TIADaAQAAAA==.Jameson:BAABLgAECn8YAAIDAAcJ/BEJHgB5AQADAAcJ/BEJHgB5AQAAAA==.Jamiel:BAAALgADCgEJAQAAAA==.Jasmind:BAABLgAECn8lAAMOAAYJKQtfTQDeAAAOAAYJKQtfTQDeAAAQAAEJLApViAAnAAAAAA==.',
Je='Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAVAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAAALgAECgYJEAAAAA==.Jessicà:BAAALgAECgEJAQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgADCgUJBQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8YAAMMAAYJIhYMNgCrAQAMAAYJIhYMNgCrAQATAAUJbxKYMADxAAAAAA==.Jiwâ:BAACLgAFFH8QAAIPAAQJ+QqSDQAyAQAPAAQJ+QqSDQAyAQAuAAQKfzIAAg8ACQn4HboEAJgCAA8ACQn4HboEAJgCAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgEJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECgYJEAAAAA==.Joss:BAAALgAECgEJAQAAAA==.',
Ka='Kadan:BAAALgAECgYJBgABLgAECgkJIwAFAJsfAA==.Kahless:BAAALgADCgMJBQAAAA==.Kakwaa:BAABLgAECn8WAAIDAAYJDAkxNQD0AAADAAYJDAkxNQD0AAAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Keyadistor:BAABLgAECn8WAAMcAAgJGh45XQDbAQAcAAYJ7ho5XQDbAQAmAAYJCB2ACgDtAAAAAA==.',
Kh='Khazabrew:BAABLgAECn8kAAIKAAgJBx4rCABKAgAKAAgJBx4rCABKAgAAAA==.',
Ki='Kiamara:BAAALgAECgcJEQAAAA==.Kinderlin:BAABLgAECn8WAAICAAYJLBKtbAAUAQACAAYJLBKtbAAUAQAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIOAAcJbhZoIQC6AQAOAAcJbhZoIQC6AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQYAAgJfRaNDwDiAQAYAAYJNhmNDwDiAQAZAAMJfRR8QgDYAAAbAAQJlQqIMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.Lithena:BAAALgADCgQJBwAAAA==.',
Lo='Loadedtater:BAABLgAECn8pAAQIAAgJlyYAAwARAwAIAAgJXSYAAwARAwAHAAUJ3CXvJgDyAQAGAAIJ9yUYIwDhAAAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAAALgAECgUJBwABLgAECggJJwAMAK8YAA==.Lorianne:BAABLgAECn8nAAMMAAgJrxhjKQDpAQAMAAgJrxhjKQDpAQATAAUJsQu0VgDqAAAAAA==.Lorri:BAAALgADCgQJBQABLgAECggJJwAMAK8YAA==.',
Lu='Lucianas:BAAALgAECgYJDgAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.',
Ly='Lysi:BAAALgAECgUJEgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Madaea:BAABLgAECn8qAAIhAAkJ8B48BADiAgAhAAkJ8B48BADiAgAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn8kAAIJAAgJKBtXJgAKAgAJAAgJKBtXJgAKAgABLgAFFAMJCAAGAEsXAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAAALgAECgYJCwAAAA==.Makavali:BAAALgADCgYJDAABLgAECgYJCwAVAAAAAA==.Makdaddy:BAAALgAECgYJCwABLgAECgYJCwAVAAAAAA==.Malzeth:BAAALgADCgUJFQAAAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAAALgAECggJEgAAAA==.Mate:BAAALgADCggJFQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgADCgYJBgAAAA==.Meeseks:BAAALgAECgUJBQABLgAECgYJEAAVAAAAAA==.Melbeast:BAABLgAECn8WAAIIAAYJixuvMwB/AQAIAAYJixuvMwB/AQAAAA==.Melorea:BAAALgAECgMJAwAAAA==.Merdin:BAAALgAECggJEwAAAA==.Methmartion:BAAALgAECgUJEgABLgAECgcJBwAVAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mikewai:BAABLgAECn8XAAIFAAgJgQ9rUgCtAQAFAAgJgQ9rUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgADCgEJAQAAAA==.Missiah:BAABLgAECn8aAAIBAAgJVgPOGwC1AAABAAgJVgPOGwC1AAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgIJBAAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQAQAO8WAA==.Molfise:BAABLgAECn8WAAMKAAYJ8xOGIwAgAQAKAAYJOhGGIwAgAQAnAAQJpRHVRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8jAAIiAAgJkReMEgDLAQAiAAgJkReMEgDLAQAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAAALgAECgYJEAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgMJAgAAAA==.',
Mu='Mugatoo:BAAALgADCgMJAwAAAA==.Musubi:BAAALgADCgEJAQABLgAECgYJCwAVAAAAAA==.',
Mx='Mxtemlen:BAAALgAECgcJCAABLgAECgYJFgAaALUSAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCgYJDQAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgYJBwABLgAECgkJHwAhAJMZAA==.Myttus:BAEALgADCgMJAwABLgAECgQJDgAVAAAAAA==.',
['Mê']='Mêrlin:BAABLgAECn8cAAIJAAgJBgaNZgBEAQAJAAgJBgaNZgBEAQAAAA==.',
Na='Nachtelf:BAABLgAECn8yAAIIAAkJCSDHAwD9AgAIAAkJCSDHAwD9AgAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nannysham:BAAALgAECgcJDQAAAA==.Naomí:BAABLgAECn8cAAIRAAYJ0wwZagD4AAARAAYJ0wwZagD4AAAAAA==.Natadawn:BAAALgAECgEJAQAAAA==.Natalone:BAABLgAECn8rAAIJAAkJ7yFKBAA0AwAJAAkJ7yFKBAA0AwAAAA==.Natherel:BAAALgAECgUJDgAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAAALgAECgUJBgABLgAFFAYJEgAgAGQTAA==.',
Ne='Newander:BAABLgAECn8eAAIOAAgJKBHaOQAuAQAOAAgJKBHaOQAuAQAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgUJBgAAAA==.Nirra:BAAALgADCggJDQAAAA==.',
No='Nonphatmilk:BAAALgAECgMJCAAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMcAAkJmhIZHwAOAgAcAAkJmhIZHwAOAgAjAAEJGxJ3RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCB9RHQA6AgAJAAgJCB9RHQA6AgAAAA==.',
Og='Ograskygazer:BAAALgAECgUJDgAAAA==.',
Om='Omee:BAABLgAECn8VAAMEAAgJ7hb7DACxAQAEAAcJHRr7DACxAQAFAAUJyAqzYQDbAAAAAA==.Omy:BAABLgAECn8YAAIJAAYJXQRd9AARAQAJAAYJXQRd9AARAQAAAA==.',
Op='Ophela:BAAALgAECgEJAQAAAA==.',
Or='Orakio:BAAALgAECgYJBgABLgAFFAQJCAAJAAIPAA==.Oralena:BAAALgAECgUJEgAAAA==.Orioncheats:BAABLgAECn8kAAIcAAgJyRlrKADbAQAcAAgJyRlrKADbAQAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAVAAAAAA==.',
Pa='Paladingbat:BAAALgAECggJDgAAAA==.Pallygoboom:BAAALgADCgUJBQABLgAECgYJCgAVAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paull:BAAALgAECgYJEAAAAA==.',
Pe='Ped:BAABLgAECn8hAAMnAAgJ2By4CwD9AQAnAAgJ2By4CwD9AQAhAAEJ2AHZdgAXAAAAAA==.Peon:BAAALgAECgQJBAAAAA==.',
Ph='Pharune:BAABLgAECn8eAAIoAAgJTRAJDABQAQAoAAgJTRAJDABQAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAAALgAECgUJDgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAECggJBwAVAAAAAA==.Picklebob:BAAALgAECggJBwAAAA==.Pickleboe:BAAALgAECgUJBQABLgAECggJBwAVAAAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgcJBwAAAA==.',
Pl='Plandemic:BAAALgAECgQJBgAAAA==.',
Po='Pockithealz:BAAALgAECgEJAQABLgAECgcJAgAVAAAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.',
Pr='Precious:BAACLgAFFH8SAAIgAAYJZBO/BgDkAQAgAAYJZBO/BgDkAQAuAAQKfzoABCAACQlbI6UDAC4DACAACQlbI6UDAC4DACIABglwDxk2AGQBAA8ABAkxE6kyAMYAAAAA.',
['Pä']='Pängari:BAAALgADCgYJBgAAAA==.',
Qu='Quattro:BAAALgAECgcJCgAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn8sAAMDAAgJKhonDQAZAgADAAgJDBonDQAZAgALAAEJihXbNwBCAAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAAALgAECgcJEQABLgAECggJHgAOACgRAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAAALgAECgYJEQAAAA==.',
Re='Rehum:BAEALgAECgQJDgAAAA==.Remagtrepxe:BAAALgADCgMJBQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgQJBgAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8bAAMfAAgJYAwsDgAjAQAfAAUJBg4sDgAjAQAMAAUJzQVHYAB6AAAAAA==.Revèndreth:BAAALgAECgEJAQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd4PQD+AQAFAAcJGhd4PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgIJAgAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn8nAAIPAAgJNwwHGAB9AQAPAAgJNwwHGAB9AQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAAALgAECgYJEQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8cAAMcAAgJ0BvuIgD5AQAcAAgJnxvuIgD5AQAmAAYJrhWwCABaAQAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8UAAIYAAYJJw/KCAAeAQAYAAYJJw/KCAAeAQAAAA==.Roryn:BAABLgAECn81AAICAAkJ3yLmAgAwAwACAAkJ3yLmAgAwAwAAAA==.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAECgkJCwAAAA==.Rugiia:BAACLgAFFH8eAAIOAAYJWiRDAQCDAgAOAAYJWiRDAQCDAgAuAAQKfzwAAw4ACQmWJkIAAOMDAA4ACQmWJkIAAOMDAA0ABAlfJQUNAEcBAAAA.Rugiian:BAAALgAFFAMJAwABLgAFFAYJHgAOAFokAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAAALgAECgYJEAAAAA==.Ryuka:BAAALgAECgcJDAAAAA==.',
Sa='Sabindeus:BAAALgAECggJAQAAAA==.Samyria:BAAALgAECgIJBQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8VAAQnAAgJAg9AJQABAQAnAAcJKAxAJQABAQAhAAQJFQb8WABqAAAKAAEJgAH3mQAYAAAAAA==.Saucy:BAAALgAECgUJCQAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAVAAAAAA==.Scrubsauce:BAAALgAECgEJAwAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8bAAIiAAcJhxAiIABHAQAiAAcJhxAiIABHAQAAAA==.Seric:BAABLgAECn8fAAIdAAgJigxjEQBNAQAdAAgJigxjEQBNAQAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgcJEQAVAAAAAA==.',
Sh='Shadowdancèr:BAAALgAECgYJDQAAAA==.Shadowlocke:BAAALgADCgYJDQAAAA==.Shamquen:BAAALgAECgEJAgAAAA==.Shanair:BAACLgAFFH8IAAIGAAMJSxelAwC7AAAGAAMJSxelAwC7AAAuAAQKfzAAAwYACQk8IboBAO8CAAYACQkjIboBAO8CAAcABwnWHTAbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAMJCQABALkHAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJAwAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAQJBgAdAEoYAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8WAAMgAAYJvhE9MAAeAQAgAAUJiBA9MAAeAQAiAAUJfQ/CNgCgAAAAAA==.',
Sl='Slambamwhoo:BAAALgADCgEJAgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8kAAIJAAgJMRD2TwB6AQAJAAgJMRD2TwB6AQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgIJAgAAAA==.Solnar:BAABLgAECn8WAAQaAAYJtRJLNAD8AAAaAAUJ5g5LNAD8AAABAAYJQBPhFwDZAAACAAEJYBYp6wBCAAAAAA==.',
Sp='Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAVAAAAAA==.Splashdaddy:BAABLgAECn8iAAIMAAgJUyQyBQDoAgAMAAgJUyQyBQDoAgABLgADCgYJBgAVAAAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgQJCQAAAA==.',
St='Staks:BAAALgADCgQJBAAAAA==.Starii:BAABLgAECn8XAAIMAAcJ5AY6QQD+AAAMAAcJ5AY6QQD+AAAAAA==.Stas:BAAALgADCgYJBgAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgADCgQJBAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8XAAIoAAYJPCKNBgDeAQAoAAYJPCKNBgDeAQAAAA==.',
Ta='Taea:BAAALgADCgIJAgABLgAECgYJFwAOAHIeAA==.Taeus:BAACLgAFFH8IAAIJAAQJAg9xLwBKAQAJAAQJAg9xLwBKAQAuAAQKfxcAAgkACAkVGNxeAB4CAAkACAkVGNxeAB4CAAAA.Taintedkoma:BAAALgAECgcJBwAAAA==.Taladiir:BAAALgAECgEJAQAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgUJBwAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIdAAkJoiFwAwCSAgAdAAkJoiFwAwCSAgAAAA==.Tayblr:BAAALgAECgYJEgAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAECgcJBwAAAA==.Temajin:BAAALgADCgcJFwAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAAALgAECgUJEgAAAA==.Teron:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAAALgAECgcJDwAAAA==.Themyscira:BAAALgAECgEJAQAAAA==.Theonorf:BAABLgAECn8oAAIIAAgJtx8JDAB/AgAIAAgJtx8JDAB/AgAAAA==.Thetimelord:BAAALgAECgEJAQAAAA==.Thewarrior:BAAALgAECgcJDAAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8kAAICAAgJVRX5LgDBAQACAAgJVRX5LgDBAQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Torrey:BAABLgAECn8kAAIXAAgJcxAqCgAxAQAXAAgJcxAqCgAxAQAAAA==.',
Tr='Tradd:BAABLgAECn8YAAIgAAcJuyAUCABgAgAgAAcJuyAUCABgAgAAAA==.Trigg:BAAALgAECgUJBQABLgAECgkJIwAFAJsfAA==.Tristyana:BAABLgAECn8uAAIIAAkJfxc1DwBdAgAIAAkJfxc1DwBdAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn8yAAMnAAkJpSTvAABIAwAnAAkJpSTvAABIAwAhAAcJgxY+IwCZAQAAAA==.',
Tw='Twinkletoe:BAAALgADCgYJBgABLgAECgkJMgAnAKUkAA==.',
Ty='Tylurien:BAABLgAECn8eAAIaAAgJSCIdBAD2AgAaAAgJSCIdBAD2AgAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn8WAAISAAYJ9AiQEADUAAASAAYJ9AiQEADUAAAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valkoinen:BAABLgAECn8sAAIbAAYJGA6mEwAEAQAbAAYJGA6mEwAEAQAAAA==.Valora:BAABLgAECn8yAAQgAAkJpBr2CABLAgAgAAkJDBf2CABLAgAiAAcJYx30EADfAQAPAAEJchc7SwBGAAAAAA==.Valoria:BAAALgAECgQJCQAAAA==.Vanille:BAAALgAECgUJEQAAAA==.Vargen:BAABLgAECn8WAAIlAAcJmRcCDwC0AQAlAAcJmRcCDwC0AQAAAA==.Varonika:BAAALgAECgUJDgAAAA==.Vayla:BAABLgAECn8eAAIdAAgJtxZTEgDjAQAdAAgJtxZTEgDjAQAAAA==.',
Ve='Vee:BAAALgAECgEJAgABLgAECggJFAAFAE8UAA==.Veld:BAAALgAECggJBQAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJgAcAAMeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBAAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8YAAICAAYJQArdcwAEAQACAAYJQArdcwAEAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgQJCAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn8jAAIOAAgJDgM6TQDfAAAOAAgJDgM6TQDfAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAABLgAECn8hAAIJAAcJkR63MADeAQAJAAcJkR63MADeAQAAAA==.Wargrimm:BAABLgAECn8dAAITAAgJ2BpvCwAjAgATAAgJ2BpvCwAjAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8SAAIaAAQJISbiBgCuAQAaAAQJISbiBgCuAQAuAAQKf0QAAxoACQmfJhIAAPgDABoACQmfJhIAAPgDAAIABQlrE4xXAEMBAAAA.',
We='Webin:BAAALgAECgEJBAAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAInAAgJRR9+EQBtAgAnAAgJRR9+EQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQAQAO8WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQAQAO8WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQAQAO8WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQAQAO8WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQAQAO8WAA==.Whizpa:BAABLgAECn8dAAIQAAkJ7xZJCABNAgAQAAkJ7xZJCABNAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQAQAO8WAA==.',
Wi='Wickerchickn:BAAALgAECgYJDwAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQAQAO8WAA==.Wispy:BAAALgAECgYJBgAAAA==.Wizzelyfink:BAAALgAECgEJAQAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wr='Wrathbarrage:BAAALgAECgQJBAABLgAECggJEgAVAAAAAA==.Wrathbourne:BAAALgAECgYJDQABLgAECggJEgAVAAAAAA==.Wrathchoi:BAAALgAECgQJBAAAAA==.Wrathstorm:BAAALgAECgEJAgABLgAECggJEgAVAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8ZAAMGAAYJGiGoDQDLAQAIAAYJpR6QMwDhAQAGAAYJ5R2oDQDLAQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgQJCQAVAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEAAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAAALgAECggJEAAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAVAAAAAA==.Zirfireballs:BAAALgADCgUJBQAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJEAAAAA==.',
Zu='Zurazaee:BAAALgAECgUJEgAAAA==.',
['År']='Årtêmis:BAAALgAECgIJAgAAAA==.',
['Él']='Élle:BAAALgAECgMJBQAAAA==.',
['Ér']='Éric:BAABLgAECn8xAAIoAAkJKhgGBABCAgAoAAkJKhgGBABCAgAAAA==.',
['Ïr']='Ïridescent:BAAALgAECgIJAgAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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

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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-BeastMastery','Warlock-Demonology','Shaman-Enhancement','Hunter-Survival','Warrior-Protection','Paladin-Holy','Druid-Guardian','Druid-Restoration','Priest-Shadow','DeathKnight-Unholy','Warlock-Destruction','Hunter-Marksmanship','DeathKnight-Blood','Mage-Frost','Unknown-Unknown','Druid-Balance','Paladin-Protection','Warrior-Fury','Monk-Mistweaver','Evoker-Preservation','Evoker-Devastation','Monk-Windwalker','Warrior-Arms','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Mage-Fire','Priest-Holy','Mage-Arcane','DeathKnight-Frost','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aalst:BAABLgAECn8UAAIBAAYJGQhCLgDjAAABAAYJGQhCLgDjAAAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8NFAAMAgACAAYJoR8NFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acshec:BAAALgADCgYJDgABLgAECgcJGwADAPQaAA==.Acuna:BAAALgADCgkJEgAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn8gAAIBAAgJCw2NGgBgAQABAAgJCw2NGgBgAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgADCgYJBgABLgAECgcJFwAEACQNAA==.',
Ag='Aggrenox:BAABLgAECn8WAAIDAAYJ4wmgfADzAAADAAYJ4wmgfADzAAAAAA==.',
Ai='Aisathya:BAAALgAECgcJEwAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJBgAAAA==.Albina:BAAALgAECgIJBAAAAA==.Aldelvir:BAAALgAECgUJBgABLgAECgcJJwAFAI4TAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAAALgAECggJEgAAAA==.Alzhimers:BAAALgAECgIJAwAAAA==.',
Am='Amberscale:BAABLgAECn8kAAIGAAgJAh2jBwBcAgAGAAgJAh2jBwBcAgAAAA==.Amyrrin:BAAALgAECgcJEgAAAA==.',
An='Ancientiur:BAABLgAECn8VAAMHAAgJRRjlSwDFAQAHAAgJ2BXlSwDFAQAIAAMJ8xKfFQB3AAAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAAALgAECgYJEQAAAA==.Angrulus:BAABLgAECn8mAAIJAAkJ/hebDwBZAgAJAAkJ/hebDwBZAgAAAA==.Animal:BAAALgAECgEJAQAAAA==.Animlshiftr:BAABLgAECn8dAAIFAAgJbAdJEAAVAQAFAAgJbAdJEAAVAQAAAA==.',
Ap='Apollo:BAABLgAECn8UAAIKAAYJ+gcGcwDjAAAKAAYJ+gcGcwDjAAAAAA==.',
Ar='Aradunn:BAACLgAFFH8LAAIEAAQJoyEjCQCKAQAEAAQJoyEjCQCKAQAuAAQKfx8AAwQACAkYI/oGAAQDAAQACAkYI/oGAAQDAAsAAgncBxstADIAAAAA.Araedis:BAABLgAECn8bAAIMAAgJawpWEACmAQAMAAgJawpWEACmAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwANAPwJAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDAAAAA==.',
As='Ashvehtta:BAAALgAECgcJBwAAAA==.Assaelysia:BAAALgADCgYJBgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgEJAQAAAA==.Astralon:BAAALgAECgEJAgAAAA==.',
At='Atharion:BAABLgAECn8hAAMOAAcJwSCkBwCcAgAOAAcJwSCkBwCcAgADAAMJZAwiDAF/AAAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJBAAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8ZAAILAAcJWhRoCACgAQALAAcJWhRoCACgAQAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAAALgAECgcJDgAAAA==.Azémstraza:BAAALgAECgYJBgAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8ZAAIJAAYJrRtYLwD0AQAJAAYJrRtYLwD0AQAAAA==.Balinor:BAABLgAECn8UAAIOAAYJOA9LKwA0AQAOAAYJOA9LKwA0AQABLgAECggJIAANAH8dAA==.',
Be='Bearett:BAABLgAECn8fAAIPAAgJCiOhAQDDAgAPAAgJCiOhAQDDAgAAAA==.Beefynacho:BAAALgADCgMJAwAAAA==.Belyhell:BAAALgADCgUJBQAAAA==.Belylight:BAAALgAECgkJAgAAAA==.Belymoon:BAAALgAECgkJCAAAAA==.Bernd:BAABLgAECn8cAAIPAAcJwA4lEAAGAQAPAAcJwA4lEAAGAQAAAA==.Beörn:BAABLgAECn8dAAIQAAgJMyCrCQCuAgAQAAgJMyCrCQCuAgAAAA==.',
Bl='Blackgrinn:BAABLgAECn8ZAAMCAAcJLRD6FgCCAQACAAcJLRD6FgCCAQARAAUJaQahLQDiAAAAAA==.Blackkgrin:BAAALgADCgQJBAAAAA==.Blasphemous:BAABLgAECn8XAAISAAcJDhTDQQB3AQASAAcJDhTDQQB3AQAAAA==.Blasé:BAABLgAECn8qAAMKAAcJOiS5EABfAgAKAAcJOiS5EABfAgATAAEJAACZXABZAAAAAA==.Blazéoné:BAAALgAECgEJAQAAAA==.Blessin:BAAALgAECgcJBwAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMUAAIJ7xJ7HQCgAAAUAAIJ7xJ7HQCgAAAJAAIJMAgbQQCVAAAuAAQKfywABBQACAmWIY8NANgCABQACAkUHo8NANgCAAwABwnWHSYKAAECAAkAAglkHtt6AKcAAAAA.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAISAAcJdR3NSAAZAgASAAcJdR3NSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwASAHUdAA==.Bootypls:BAACLgAFFH8MAAMVAAMJOheXDgCAAAASAAIJJR4AYQC3AAAVAAIJBwyXDgCAAAAuAAQKfyAAAxUACAlZG2YVALwBABUACAlzF2YVALwBABIABQlkHgtyAP4AAAAA.',
Br='Brakevilt:BAAALgADCgQJBAAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8iAAISAAgJ7hyLFgBGAgASAAgJ7hyLFgBGAgAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bw='Bwca:BAAALgAFFAMJBAABLgAFFAMJCAAEABUGAA==.',
Ca='Caine:BAABLgAECn8gAAINAAgJfx28BwAEAgANAAgJfx28BwAEAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgQJBAABLgAECgcJFwAEACQNAA==.Casey:BAAALgAECgQJCwAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8XAAIEAAcJJA3HMQBIAQAEAAcJJA3HMQBIAQAAAA==.',
Ce='Cellina:BAAALgAECggJEQAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJBwABLgAECggJGwAWAGoRAA==.',
Ch='Chiman:BAAALgAECgUJDAABLgAECgYJDgAXAAAAAA==.Chronophage:BAAALgAECgQJBAAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Cl='Classá:BAACLgAFFH8IAAMQAAMJYhw1GgADAQAQAAMJYhw1GgADAQAYAAMJzhUuFwDuAAAuAAQKfy8AAxgACAmxIDkOALkCABgABwlsJDkOALkCABAABgnDHcRGAIcBAAAA.Clawz:BAAALgADCgYJBgABLgAFFAEJAQAXAAAAAA==.',
Co='Codedd:BAAALgAFFAEJAQAAAA==.Commit:BAAALgAECgYJCQAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAABLgAECn8bAAIDAAcJHCDSGwAhAgADAAcJHCDSGwAhAgABLgAECggJFQAWAN4LAA==.Covi:BAAALgADCgUJBAAAAA==.',
Cr='Crispìn:BAAALgAECgUJCgAAAA==.Crossbones:BAAALgAECgIJAgAAAA==.Crue:BAAALgAECgMJAwAAAA==.',
Cu='Curthar:BAABLgAECn8aAAMZAAkJyiHnAgCAAgAZAAcJLyTnAgCAAgADAAYJnR6EMwCvAQABLgAFFAEJAQAXAAAAAA==.',
Cy='Cyndee:BAABLgAECn8oAAIaAAkJLBLeDwD4AQAaAAkJLBLeDwD4AQAAAA==.Cynnafrost:BAAALgAECgEJAQAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn8hAAIUAAcJFSH0AgA5AgAUAAcJFSH0AgA5AgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJBgABLgAECgYJGQAJAK0bAA==.Dankmonk:BAABLgAECn8WAAIBAAYJ6AvpKwDwAAABAAYJ6AvpKwDwAAAAAA==.Darcnis:BAAALgADCgkJEgAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn8eAAIHAAgJ3gWaUwD/AAAHAAgJ3gWaUwD/AAAAAA==.Darklasminth:BAAALgAECgQJBwAAAA==.Darthwang:BAABLgAECn8fAAIKAAYJ6BjhWgC3AQAKAAYJ6BjhWgC3AQAAAA==.Darthwing:BAAALgADCgEJAQABLgAECgYJHwAKAOgYAA==.Dartos:BAABLgAECn8oAAISAAgJ9CKjFAAAAwASAAgJ9CKjFAAAAwAAAA==.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAYJEAAWAFgWAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAAALgAECgcJDwAAAA==.Deep:BAAALgAECgEJAQABLgAECggJIQAbAOYgAA==.Deepfister:BAABLgAECn8hAAIbAAgJ5iACBgCnAgAbAAgJ5iACBgCnAgAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECggJIQAbAOYgAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCQAAAA==.Diluvium:BAABLgAECn8aAAIDAAcJSxBMSQBpAQADAAcJSxBMSQBpAQAAAA==.Discodank:BAAALgADCgQJBQAAAA==.',
Dj='Djpleasant:BAACLgAFFH8HAAIWAAIJrhDJXQCrAAAWAAIJrhDJXQCrAAAuAAQKfyQAAhYACQl5HEEQAJgCABYACQl5HEEQAJgCAAAA.',
Dk='Dktelmtwo:BAAALgADCgYJCAAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAAALgAFFAEJAQAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAABLgAECn8aAAQcAAgJHgLkHQCBAAAcAAYJMALkHQCBAAAdAAgJpAGnEAB3AAAGAAEJLgCdbAAMAAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAABLgAECn8bAAIYAAgJ+x0LBwBnAgAYAAgJ+x0LBwBnAgAAAA==.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8WAAIWAAYJLxkfVgBqAQAWAAYJLxkfVgBqAQABLgAECggJIAAGAF0TAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgMJAwAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8KAAIBAAQJUBrhDABPAQABAAQJUBrhDABPAQAuAAQKfxUAAwEACAkVG/EUAJQBAB4ABwkpF94jALcBAAEABQmDG/EUAJQBAAAA.',
El='Elementals:BAAALgAECgkJDgAAAA==.Elixera:BAAALgADCgUJBQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.',
Em='Emilwhaury:BAAALgADCgIJAgAAAA==.',
Ep='Epia:BAABLgAECn8cAAIeAAcJ6wvjHQA0AQAeAAcJ6wvjHQA0AQAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Essaila:BAABLgAECn8YAAIFAAcJ9AlCDgAzAQAFAAcJ9AlCDgAzAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8VAAMaAAYJSx5oHACFAQAaAAYJSx5oHACFAQAfAAEJ3BbiOABMAAAAAA==.',
Ev='Evocati:BAAALgAECgYJEgABLgAFFAUJDAADABIaAA==.Evoka:BAABLgAECn8fAAMdAAcJaR7sDAAMAgAdAAcJaR7sDAAMAgAGAAUJIRcQJgAbAQAAAA==.',
Ex='Excision:BAABLgAECn8UAAMdAAcJcw2sHgA5AQAdAAcJcw2sHgA5AQAGAAMJZgeWTwBYAAAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Ez='Ezindrozath:BAABLgAECn8gAAQKAAcJkhbAMQCdAQAKAAcJtRXAMQCdAQAgAAQJcBYmEQAbAQATAAEJ7wVDeQAqAAAAAA==.',
Fa='Fahbio:BAABLgAECn8WAAIZAAYJ8gFHMQCLAAAZAAYJ8gFHMQCLAAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAABLgAECn8eAAIKAAYJeQz9WgAdAQAKAAYJeQz9WgAdAQAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgADCgQJBAABLgAECgYJFwAhAEMUAA==.Fivevolts:BAABLgAECn8YAAIiAAcJ4iCIAgAzAgAiAAcJ4iCIAgAzAgAAAA==.',
Fl='Flailuid:BAAALgAECgQJDAAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgEJBAAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJBwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAABLgAECn8sAAIeAAgJLiLJAwC3AgAeAAgJLiLJAwC3AgAAAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8fAAIGAAgJoQ0bHwBHAQAGAAgJoQ0bHwBHAQAAAA==.',
Fu='Fudd:BAABLgAECn8WAAIJAAYJ3BvOOQDHAQAJAAYJ3BvOOQDHAQAAAA==.Fupa:BAAALgAECgYJDwAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8aAAIFAAcJwx6vBQD3AQAFAAcJwx6vBQD3AQAAAA==.',
Ge='Genius:BAABLgAECn8WAAIfAAYJsRr7DADPAQAfAAYJsRr7DADPAQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAIDAAgJyhjlfgB8AQADAAgJyhjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgADCgYJCAAAAA==.Gnomad:BAABLgAECn8WAAIWAAYJTAPapQDIAAAWAAYJTAPapQDIAAAAAA==.',
Go='Gouge:BAAALgAECgkJNAAAAQ==.',
Gr='Griffynshu:BAAALgAECggJEwAAAA==.Griz:BAAALgADCgkJDwAAAA==.Grunewald:BAABLgAECn82AAIJAAcJHAk+SwArAQAJAAcJHAk+SwArAQAAAA==.',
Gu='Gula:BAABLgAECn8gAAMgAAgJExc+CQCxAQAgAAYJHRc+CQCxAQAKAAgJ0xVZMgCbAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8JAAICAAMJXRogFgAAAQACAAMJXRogFgAAAQAuAAQKfxgAAxEABwmtE5AgANQBABEABwmtE5AgANQBAAIABAnGIhEwAB8BAAAA.Hando:BAAALgADCgYJBgAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAABLgAECn8cAAIBAAkJ7BFRDAD9AQABAAkJ7BFRDAD9AQAAAA==.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIhAAgJ/xrTEwB3AgAhAAgJ/xrTEwB3AgAAAA==.Heimdall:BAAALgAECgcJDAAAAA==.Hellavva:BAAALgAECgMJAwAAAA==.Hench:BAAALgADCgIJAgAAAA==.Henchling:BAABLgAECn8sAAMEAAkJGyApCQDkAgAEAAkJGyApCQDkAgAjAAEJFQ07XABEAAAAAA==.Henchragon:BAAALgADCgEJAQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIWAAcJzxvnMgDVAQAWAAcJzxvnMgDVAQABLgAFFAMJCAAGAOUUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAhAP8aAA==.Holexios:BAAALgAECgQJBwABLgAECgYJDgAXAAAAAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAQAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAAALgAECggJDwAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Ic='Icieblade:BAAALgAECgcJDgAAAA==.Icyscorcher:BAABLgAECn8bAAMWAAgJahFuNwDFAQAWAAgJahFuNwDFAQAkAAMJpwOyCwB3AAAAAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.',
Im='Immeira:BAABLgAECn8VAAIEAAYJYAiZRADvAAAEAAYJYAiZRADvAAAAAA==.',
In='Intense:BAAALgAECgIJAgAAAA==.',
Ja='Jackheals:BAACLgAFFH8GAAIQAAIJ4g5sMgCBAAAQAAIJ4g5sMgCBAAAuAAQKfyQAAxAABwn7HWYnABgCABAABwn7HWYnABgCABgAAQnZAdKPABsAAAAA.Jaldon:BAAALgAECgQJBAABLgAECgkJHAABAOwRAA==.',
Jb='Jblackly:BAAALgAECgYJBwAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinphoenix:BAABLgAECn8bAAMJAAkJZh2vBgDGAgAJAAkJZh2vBgDGAgAUAAQJkAeEXwDDAAAAAA==.',
Jo='Jobin:BAACLgAFFH8HAAISAAMJ9w7tUwDmAAASAAMJ9w7tUwDmAAAuAAQKfxkAAhIACAnxG2lTAEMBABIACAnxG2lTAEMBAAAA.Journei:BAAALgAECgQJBwAAAA==.',
Ju='Judging:BAABLgAECn8cAAMOAAcJ9BEuJwBRAQAOAAcJ9BEuJwBRAQADAAIJTySFjQDSAAAAAA==.',
Ka='Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAEJAQAAAA==.Kalmas:BAABLgAFFH8GAAIYAAMJtgZKGwDFAAAYAAMJtgZKGwDFAAAAAA==.',
Ke='Kegz:BAAALgADCgcJBwABLgAECggJHgACAIEdAA==.Kelendrian:BAAALgADCgkJCgAAAA==.Kellayna:BAAALgAECgYJCgAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgADCgQJBAAAAA==.Kezix:BAABLgAECn8cAAIKAAgJ6w+NLgCpAQAKAAgJ6w+NLgCpAQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECgYJDgAXAAAAAA==.',
Ki='Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8gAAQGAAgJ7xCiIwChAQAGAAgJLA+iIwChAQAdAAIJ1AutFgA7AAAcAAEJwQFxTgAiAAAAAA==.',
Kl='Klerik:BAACLgAFFH8MAAIKAAUJcwh6NwD1AAAKAAUJcwh6NwD1AAAuAAQKfyEABAoACQkIH1MQAGMCAAoACAlDHlMQAGMCABMAAgkpEmdMAIgAACAAAQluJNARAGQAAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8RAAIVAAUJxx+ZBwBTAQAVAAUJxx+ZBwBTAQAuAAQKfzIAAhUACAmJIi4EAAwDABUACAmJIi4EAAwDAAAA.Kore:BAABLgAECn8WAAIQAAYJEBNkUQBgAQAQAAYJEBNkUQBgAQAAAA==.Korrag:BAAALgAECgIJAgAAAA==.Kozarke:BAABLgAECn8cAAIdAAcJmBWMBACpAQAdAAcJmBWMBACpAQAAAA==.',
Kp='Kpop:BAABLgAECn8VAAIIAAcJZR4tBwAWAgAIAAcJZR4tBwAWAgABLgAECgkJHAABAOwRAA==.',
Kr='Krissia:BAABLgAECn8gAAISAAgJzxlxLgDAAQASAAgJzxlxLgDAAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgADCgcJCAAAAA==.',
['Kî']='Kîn:BAABLgAECn8WAAIHAAYJSxcWPQBDAQAHAAYJSxcWPQBDAQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8lAAIlAAgJTxJhFgCgAQAlAAgJTxJhFgCgAQAAAA==.Lalipop:BAABLgAECn8WAAIlAAYJbBXoHQBaAQAlAAYJbBXoHQBaAQAAAA==.Landroval:BAABLgAECn8cAAIGAAcJkxovDwDfAQAGAAcJkxovDwDfAQAAAA==.Lauma:BAABLgAFFH8IAAIEAAMJFQb4KACtAAAEAAMJFQb4KACtAAAAAA==.Lawson:BAABLgAECn8bAAISAAgJ2RRRKwDOAQASAAgJ2RRRKwDOAQAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn8gAAMKAAgJ6xa5KADDAQAKAAgJNxO5KADDAQATAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgADCgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lilflame:BAAALgADCgUJCAAAAA==.Lio:BAAALgAECgYJDQAAAA==.Lissetteliz:BAAALgAECgEJAQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJCAAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.',
Ly='Lyreth:BAABLgAECn8oAAIYAAgJOBHZFQCQAQAYAAgJOBHZFQCQAQAAAA==.',
Ma='Madax:BAABLgAECn8gAAIaAAgJ8xvUDAAeAgAaAAgJ8xvUDAAeAgABLgAECggJIAAGAF0TAA==.Mageymutt:BAACLgAFFH8QAAIWAAYJWBZXDAC7AQAWAAYJWBZXDAC7AQAuAAQKfyUAAxYACAmMIJwlANwCABYACAmMIJwlANwCACYAAwkmCx4UAIQAAAAA.Maggidabeast:BAABLgAECn8UAAIWAAcJ4wMgjwD0AAAWAAcJ4wMgjwD0AAAAAA==.Maison:BAAALgAECgQJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAABLgAECn8oAAInAAkJ1xi5AgAGAgAnAAkJ1xi5AgAGAgAAAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAABLgAECn8mAAIWAAkJBxzRFQBrAgAWAAkJBxzRFQBrAgAAAA==.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAMJCAAQAGIcAA==.Missbehaving:BAABLgAECn8ZAAIlAAcJihT5GgBzAQAlAAcJihT5GgBzAQAAAA==.',
Mo='Morefire:BAAALgAECgQJBwABLgAECgkJDgAXAAAAAA==.Mosmos:BAAALgADCgUJDAAAAA==.',
Mu='Muddslinger:BAAALgAECgcJEwAAAA==.Mumra:BAABLgAECn8aAAQlAAcJgQI/LgDbAAAlAAcJgQI/LgDbAAACAAYJdgFZPwC0AAARAAEJAAB+XwAAAAAAAA==.',
My='Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECgEJAQAAAA==.Nanaki:BAABLgAECn8fAAIcAAgJOyHxBgDQAgAcAAgJOyHxBgDQAgAAAA==.Nannette:BAAALgAECgYJDgAAAA==.Nappe:BAAALgADCgcJBwABLgAECgcJGAADAMokAA==.Narag:BAABLgAECn8fAAIJAAgJmhPFJwCzAQAJAAgJmhPFJwCzAQAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJBAAAAA==.Netanyahoo:BAAALgAECgUJCQAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8UAAMEAAcJrRkbMQDCAQAEAAcJrRkbMQDCAQAjAAIJlgiZVABZAAAAAA==.',
Ni='Ninex:BAABLgAECn8aAAIOAAcJbiDQGABMAgAOAAcJbiDQGABMAgAAAA==.Ninisina:BAABLgAECn8gAAMEAAYJYh4AHQDJAQAEAAYJYh4AHQDJAQALAAEJ7wOFLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgADCgEJAgAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgYJFwAhAEMUAA==.Nowon:BAAALgAECgYJEgAAAA==.',
Nu='Nudream:BAABLgAECn8WAAIOAAgJqQOhKwAyAQAOAAgJqQOhKwAyAQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAAALgAECgYJEwAAAA==.',
Ol='Oldjerry:BAABLgAECn8XAAIhAAYJQxSyFgBSAQAhAAYJQxSyFgBSAQAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Op='Opalyte:BAABLgAECn8VAAIlAAYJyg5+JwANAQAlAAYJyg5+JwANAQAAAA==.',
Or='Orichalcum:BAABLgAECn8aAAIbAAgJyxsQCwA5AgAbAAgJyxsQCwA5AgAAAA==.Orphiee:BAAALgAECgEJAQAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAIJAwAAAQ==.',
Pa='Pakoros:BAABLgAECn8kAAMEAAkJYRI1EgAnAgAEAAkJYRI1EgAnAgAjAAQJBwpzagCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgADCgcJEgAAAA==.',
Pe='Peachy:BAAALgADCgEJAgABLgAECgcJHAAEABcXAA==.Penderin:BAAALgADCgYJBgABLgAECgcJJwAFAI4TAA==.Pensham:BAAALgAECgEJAQABLgAECgcJJwAFAI4TAA==.Perlindree:BAABLgAECn8eAAIJAAYJnAhrXwDyAAAJAAYJnAhrXwDyAAAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8mAAIJAAgJjRWBIgDOAQAJAAgJjRWBIgDOAQAAAA==.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8bAAIDAAcJbhDxTABfAQADAAcJbhDxTABfAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAXAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8UAAIKAAcJ6QHwkAChAAAKAAcJ6QHwkAChAAAAAA==.Poppers:BAAALgADCgUJBQAAAA==.',
Pr='Preacharond:BAACLgAFFH8IAAIRAAMJeQ6TEgDzAAARAAMJeQ6TEgDzAAAuAAQKfzcAAhEACAnOIFMEAKUCABEACAnOIFMEAKUCAAAA.Promir:BAAALgAECgUJCwAAAA==.',
Pu='Purdie:BAAALgAECgQJBAABLgAECgcJFwAEACQNAA==.',
Qe='Qeesa:BAAALgADCgYJBgAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAABLgAECn8ZAAIDAAcJ6BvbJADwAQADAAcJ6BvbJADwAQAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8gAAICAAgJgRtwCQBBAgACAAgJgRtwCQBBAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Relaxnerdlol:BAAALgAECgEJAQAAAA==.Reldwick:BAAALgADCgEJAQAAAA==.Renew:BAAALgAECggJEwAAAA==.Renix:BAACLgAFFH8FAAIjAAMJ5Bp+FgD5AAAjAAMJ5Bp+FgD5AAAuAAQKfycAAyMACQlzHNsGAHYCACMACQlzHNsGAHYCAAsAAQl1CxQtADIAAAAA.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgEJAQAAAA==.',
Ri='Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAAALgAECgUJEwABLgAECgkJMAAWAFEcAA==.',
Ru='Rukaillin:BAAALgAECgYJBgAAAA==.',
Ry='Ryyah:BAABLgAECn8iAAMOAAcJEA/cIACAAQAOAAcJEA/cIACAAQADAAQJLQPMwAB0AAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAECggJKAAVAOgMAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Saetyl:BAABLgAECn8YAAIYAAYJKwJ8QAB/AAAYAAYJKwJ8QAB/AAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAXAAAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAXAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semii:BAAALgAECgIJAgAAAA==.Serkesul:BAABLgAECn8eAAIRAAcJRCTMBQB+AgARAAcJRCTMBQB+AgAAAA==.Sevinas:BAAALgAECgYJDwAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shamallamá:BAAALgADCgkJCgABLgAECgcJHQAJALEgAA==.Shamthis:BAAALgAECggJCAAAAA==.Shamwoww:BAAALgAECgYJDAABLgAFFAMJCAARAHkOAA==.Shamyou:BAABLgAECn8UAAMEAAkJ1xnRGwA6AgAEAAkJ1xnRGwA6AgAjAAYJKRrUGQCBAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECggJHAAhAAkTAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAAALgAECgYJDAABLgAECgkJHAABAOwRAA==.Shlumpdragon:BAAALgAECgMJAwABLgAECgkJHAABAOwRAA==.Shokcz:BAAALgAECgEJAQAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8OAAIEAAQJ4SW1BQC6AQAEAAQJ4SW1BQC6AQAuAAQKfykAAgQACQn8JTQDAEcDAAQACQn8JTQDAEcDAAAA.',
Si='Silvey:BAABLgAECn8cAAIHAAcJQyEUEABDAgAHAAcJQyEUEABDAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAAALgAECgcJDgAAAA==.Skully:BAAALgADCgEJAQAAAA==.Skyylorne:BAAALgAECgIJAgAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgAAAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECggJHwAcADshAA==.Snowfawn:BAAALgAECgYJEQAAAA==.Snusnurae:BAAALgAECgUJCAAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Somay:BAAALgAECgMJAwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECggJHwAcADshAA==.',
Sp='Spanana:BAABLgAFFH8MAAISAAQJThKwFQBNAQASAAQJThKwFQBNAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8RAAIWAAcJzCJfBgD6AQAWAAcJzCJfBgD6AQAuAAQKfxcAAhYACAnbIRAdAAEDABYACAnbIRAdAAEDAAAA.Splishsplásh:BAAALgAECgYJDwAAAA==.Sprattyboii:BAAALgAECgYJCAAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAAALgAECggJDwAAAA==.',
St='Staltis:BAAALgAECgMJBAABLgAECggJHwAGAKENAA==.Starrling:BAAALgAECgYJBgAAAA==.Starzia:BAABLgAECn8gAAICAAgJUAemGQBlAQACAAgJUAemGQBlAQAAAA==.Stupidtree:BAABLgAECn8cAAIQAAcJzCPUCQCsAgAQAAcJzCPUCQCsAgAAAA==.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8cAAIKAAcJixwEHQACAgAKAAcJixwEHQACAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgMJBAAXAAAAAA==.Swiftblossom:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanex:BAAALgAECgQJBgAAAA==.',
['Sê']='Sêrënîty:BAAALgADCgEJAQABLgAECgkJIQADAL0YAA==.',
Ta='Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgQJBwABLgAECgYJDgAXAAAAAA==.Talarus:BAAALgAECggJCQAAAA==.Tanadria:BAAALgAECggJEgAAAA==.Tangerene:BAABLgAECn8aAAMCAAgJ3AUDLgAuAQACAAcJgQYDLgAuAQAlAAYJFAIUXgC6AAAAAA==.Tapioca:BAACLgAFFH8FAAIJAAMJmRnNHgAcAQAJAAMJmRnNHgAcAQAuAAQKfx4AAgkACAmCIK4MANoCAAkACAmCIK4MANoCAAAA.Tashyr:BAAALgADCgUJCAAAAA==.',
Te='Telm:BAABLgAECn8bAAMDAAcJ9BrHMQC2AQADAAcJNhnHMQC2AQAZAAcJShqKCwCGAQAAAA==.Tentilious:BAAALgADCggJCAAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAAALgAECgcJEAAAAA==.Thebestpally:BAABLgAECn8tAAMZAAgJpRhPBwDjAQAZAAgJHBhPBwDjAQADAAUJjQ0A5QDEAAAAAA==.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8YAAMOAAgJ4R+bCgBnAgAOAAgJ4R+bCgBnAgADAAEJJQ52QgEzAAAAAA==.Tidds:BAABLgAECn8ZAAIKAAcJNQgNVwAnAQAKAAcJNQgNVwAnAQAAAA==.',
To='Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8PAAIEAAcJAxSKAQDmAQAEAAcJAxSKAQDmAQAuAAQKfxkAAgQACAl8I2MHAP4CAAQACAl8I2MHAP4CAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8GAAIGAAIJGAgMMACJAAAGAAIJGAgMMACJAAAuAAQKfyoAAwYACAkDF9YWAB8CAAYACAkDF9YWAB8CAB0AAwkmBJ4zAHcAAAAA.Triggaman:BAAALgADCgUJBQABLgAECgcJGwADAPQaAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJBwABLgAFFAMJBQAJAJkZAA==.',
Uj='Ujio:BAABLgAECn8WAAMOAAYJixdcIACEAQAOAAYJixdcIACEAQADAAMJowcNswCPAAAAAA==.',
Un='Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgEJAgAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAECgcJHAABLgAFFAIJAwAXAAAAAQ==.',
Va='Vaden:BAAALgAECgEJAQABLgAECgYJEAAXAAAAAA==.Vaelthys:BAAALgAECgUJBQABLgAECgcJIAAKAJIWAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAABLgAECn8gAAMGAAgJXROSFQCYAQAGAAgJCxOSFQCYAQAdAAIJ2gqrOQBMAAAAAA==.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAMJBgADAN4SAA==.Vanaheim:BAAALgAECgUJBAAAAA==.Vance:BAAALgAECgYJDAAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Varala:BAAALgADCgkJIgAAAA==.',
Ve='Vel:BAACLgAFFH8TAAMSAAYJIyGpBQDtAQASAAYJIyGpBQDtAQAVAAEJAADAMAAAAAAuAAQKfzAAAhIACAmFJZ0KAEcDABIACAmFJZ0KAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgADCgUJBQABLgAECggJHgACAIEdAA==.Vellea:BAAALgAECgYJDgAAAA==.Velýth:BAAALgAECgUJDAABLgAFFAYJEwASACMhAA==.Veritas:BAAALgAECgYJCwAAAA==.Vexxius:BAABLgAECn8VAAMMAAkJGxhOBgBMAgAMAAkJ0xNOBgBMAgAUAAcJJxROCwA5AQAAAA==.',
Vi='Viero:BAAALgAECgcJBwAAAA==.',
Vo='Vorathis:BAAALgAECgYJBgABLgAFFAQJCwAEAKMhAA==.',
Vy='Vylana:BAAALgADCggJHgABLgAECgkJIQADAL0YAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8GAAIDAAMJ3hKaLgD6AAADAAMJ3hKaLgD6AAAuAAQKfyAAAgMACQneG24iAKACAAMACQneG24iAKACAAAA.',
Wa='Wack:BAAALgAECggJEgAAAA==.Wanderfoot:BAAALgAECgYJEAAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8jAAIKAAgJ0RHzLwCjAQAKAAgJ0RHzLwCjAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAINAAgJ/AkqIwAlAQANAAgJ/AkqIwAlAQAAAA==.Wavestabe:BAABLgAECn8nAAIFAAcJjhMMCgCDAQAFAAcJjhMMCgCDAQAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgcJJwAFAI4TAA==.',
Wr='Wreck:BAABLgAECn8fAAIKAAgJQgu4QgBhAQAKAAgJQgu4QgBhAQAAAA==.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
Ya='Yayrri:BAABLgAECn8cAAIjAAcJmRCvHwBRAQAjAAcJmRCvHwBRAQAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAECgkJIQAKADYgAA==.Zathamax:BAABLgAECn8VAAIWAAgJaAMlgQAPAQAWAAgJaAMlgQAPAQAAAA==.Zavya:BAAALgADCgEJAQABLgAECgYJFgABABMMAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8hAAIoAAcJTxKsEwBSAQAoAAcJTxKsEwBSAQAAAA==.',
Zi='Ziaya:BAABLgAECn8WAAIBAAYJEwzULgDhAAABAAYJEwzULgDhAAAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgEJBAABLgAECgYJDgAXAAAAAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8gAAIoAAgJAwe4FgAwAQAoAAgJAwe4FgAwAQAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Él']='Élwë:BAAALgADCgUJBQAAAA==.',
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

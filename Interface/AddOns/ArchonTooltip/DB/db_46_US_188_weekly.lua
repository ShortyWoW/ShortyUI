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

local lookup = {'Unknown-Unknown','Warrior-Protection','Warrior-Fury','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Druid-Restoration','DemonHunter-Devourer','Hunter-BeastMastery','Rogue-Subtlety','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Paladin-Protection','Shaman-Enhancement','Monk-Windwalker','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Arcane','Priest-Shadow','Evoker-Augmentation','Priest-Discipline','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJBwAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgUJCAABAAAAAA==.',
Ad='Adaluna:BAAALgADCgYJDQAAAA==.Adorabull:BAABLgAECn8hAAMCAAkJxCCCAgC7AgACAAkJxCCCAgC7AgADAAEJ0AYMrwAsAAAAAA==.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgcJDwAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgQJBAAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgADCggJFAAAAA==.Allucard:BAAALgAECgkJAQAAAA==.',
Am='Amapanda:BAAALgAECggJCAAAAA==.Amaria:BAAALgAECgMJBAABLgAECgcJEwABAAAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAABLgAECn8oAAIEAAgJ3hc4EgDPAQAEAAgJ3hc4EgDPAQAAAA==.Anorili:BAAALgADCgYJBgAAAA==.Antarias:BAABLgAECn8UAAQFAAYJgiBuBACZAQAFAAUJDSNuBACZAQAGAAUJrBQRoQAWAQAHAAIJthqWJABCAAAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arahil:BAAALgAECgMJAwAAAA==.Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn8qAAIIAAgJoyJBCQDBAgAIAAgJoyJBCQDBAgAAAA==.',
As='Ashdorei:BAAALgADCgMJAwAAAA==.Ashog:BAAALgAECgYJDwAAAA==.Astranos:BAAALgAECgEJAQABLgAECgcJHwAJAGoQAA==.',
At='Athanyr:BAABLgAECn8kAAIJAAgJAyWqAgBVAwAJAAgJAyWqAgBVAwAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAAALgAECgYJEQAAAA==.',
Aw='Awake:BAAALgAECgQJBAABLgAECggJDwABAAAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Ba='Bacuda:BAAALgAECgUJDAAAAA==.Balkris:BAAALgADCgkJCQABLgAECgYJEgABAAAAAA==.Baratheon:BAAALgAECgkJEQAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAAALgAECgYJDAAAAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blindashunae:BAACLgAFFH8SAAIKAAUJ1RUDHgAzAQAKAAUJ1RUDHgAzAQAuAAQKfxYAAgoACQlQHicVANgCAAoACQlQHicVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCggJCAAAAA==.Blook:BAAALgAECggJEQAAAA==.Bluehazey:BAAALgAECgcJDgAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Bootsy:BAAALgAECgYJBAAAAA==.Bopit:BAAALgAECgcJEAAAAA==.Botia:BAAALgAECgcJEgAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgEJAQAAAA==.Bruul:BAABLgAECn8VAAIIAAYJOxn/SQBnAQAIAAYJOxn/SQBnAQAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAABLgAECn8UAAILAAcJsQz1RAA+AQALAAcJsQz1RAA+AQAAAA==.Carcharoth:BAABLgAECn8eAAMHAAgJRBbJBwBkAQAHAAYJAhjJBwBkAQAGAAUJNg8WiwCvAAAAAA==.Carmelina:BAAALgAECgYJCwAAAA==.Catrixona:BAAALgAECgUJCAAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Chey:BAABLgAECn8lAAIMAAkJ3SGJBACBAgAMAAkJ3SGJBACBAgAAAA==.Chilai:BAABLgAECn8aAAINAAcJUhgpCgB7AQANAAcJUhgpCgB7AQAAAA==.Chipsahoy:BAABLgAECn8WAAMOAAgJFBt/CwAiAgAOAAgJFBt/CwAiAgAPAAYJdRJzRQBsAQAAAA==.Chrîstîan:BAAALgADCgUJBQAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.Ciphérdivine:BAAALgADCgUJBAAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAECggJJwAQABojAA==.',
Co='Conciete:BAAALgAFFAEJAQAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Corvo:BAAALgAECgcJEgAAAA==.Counselor:BAAALgAECgUJBQAAAA==.Courallie:BAAALgADCgUJAwAAAA==.',
Cr='Crataxxis:BAABLgAECn8iAAIRAAYJ8hYzFgA2AQARAAYJ8hYzFgA2AQAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgADCgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn8kAAINAAcJMyC9BAAjAgANAAcJMyC9BAAjAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Damienfox:BAAALgADCggJDwAAAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8cAAMIAAcJfR46KADfAQAIAAcJfR46KADfAQASAAMJlgx4IQCJAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgEJAQAAAA==.',
De='Defacto:BAAALgADCgMJAwAAAA==.Delat:BAAALgAECgEJAQAAAA==.Delrac:BAAALgAFFAEJAQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAECggJKQATAKEYAA==.Denero:BAAALgAECgcJEAAAAA==.Departure:BAAALgAECgMJBAAAAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAABLgAECn8cAAIUAAgJIxAZFACQAQAUAAgJIxAZFACQAQAAAA==.',
Di='Dic:BAAALgADCgIJAgAAAA==.',
Do='Dotbush:BAACLgAFFH8IAAMGAAMJzwN5TwCzAAAGAAMJzwN5TwCzAAAHAAEJhwIkFwA/AAAuAAQKfykAAwYACAkGFUJAAA0CAAYACAkGFUJAAA0CAAcAAwmrDHxGAJwAAAAA.Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn8uAAIVAAgJahPoAwDJAQAVAAgJahPoAwDJAQAAAA==.Dragonhammer:BAABLgAECn81AAIIAAgJZCTGCADHAgAIAAgJZCTGCADHAgAAAA==.Drakanna:BAAALgAECgIJAgAAAA==.Draxela:BAAALgADCgcJBwAAAA==.Dreaming:BAABLgAECn8nAAIQAAgJGiN+AwCbAgAQAAgJGiN+AwCbAgAAAA==.Drosidon:BAAALgAECgcJEQAAAA==.Drubo:BAAALgADCgkJGQAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCggJCAAAAA==.',
El='Ellaini:BAAALgAECgYJEwAAAA==.Ellie:BAAALgADCgkJEAABLgAFFAMJBgAWADcNAA==.Elseb:BAAALgAECgEJAQAAAA==.',
Em='Emotion:BAAALgADCgYJAQABLgAECggJJwAQABojAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn8fAAIJAAcJahAZMgBVAQAJAAcJahAZMgBVAQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Ex='Excrubilis:BAAALgAECgUJBAAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAAALgAECgYJEQAAAA==.Faevelina:BAAALgAECgUJDAABLgAECgcJCgABAAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJIwAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Feyreh:BAAALgAECgEJAQAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgADCgMJAwAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBgAAAA==.',
Fl='Florigrowl:BAAALgADCggJFAAAAA==.',
Fo='Forever:BAAALgAECgMJBQABLgAECggJJwAQABojAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAIXAAgJoiSgAQA/AwAXAAgJoiSgAQA/AwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAFFAMJBwAYAEkNAA==.Frailty:BAAALgAECgUJBgAAAA==.Frique:BAAALgADCgkJGgAAAA==.Frostfingers:BAAALgADCggJDwAAAA==.Frostyfang:BAABLgAECn8YAAMZAAgJDByCCQCPAQAZAAYJZCCCCQCPAQAaAAMJLhG0RABrAAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAACLgAFFH8HAAIYAAMJSQ3zUgDoAAAYAAMJSQ3zUgDoAAAuAAQKfx4AAxgACAnGHM8aACkCABgACAl0G88aACkCABAABwkyE8sXAJ0BAAAA.Galdrin:BAAALgAECgcJCgAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAAALgAECgcJEAAAAA==.Geta:BAAALgAECgQJBwABLgAECgkJIAADAF0iAA==.Getacast:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getaform:BAAALgAECgEJAQABLgAECgkJIAADAF0iAA==.Getalife:BAAALgADCgQJBAABLgAECgkJIAADAF0iAA==.Getarage:BAABLgAECn8gAAIDAAkJXSJzCQBRAgADAAkJXSJzCQBRAgAAAA==.',
Gh='Ghil:BAABLgAECn8iAAMFAAgJXiLFAACdAgAFAAgJXiLFAACdAgAGAAQJnxXSvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8cAAMOAAcJfBE1HwBUAQAOAAcJfBE1HwBUAQAPAAIJEgx/bABYAAAAAA==.Gildersleeve:BAAALgAECgQJBgAAAA==.Gilia:BAAALgADCgkJJgAAAA==.Girthfist:BAABLgAECn8WAAIbAAgJRSMJBQA5AwAbAAgJRSMJBQA5AwABLgAFFAYJFgACAJsgAA==.',
Gl='Glynixtwo:BAAALgAECgIJAgAAAA==.',
Go='Goldiwarlock:BAAALgADCgYJCgAAAA==.Goloron:BAAALgADCgkJDwAAAA==.',
Gr='Graymayn:BAAALgAECgYJCgAAAA==.Gremel:BAAALgAECgYJEQAAAA==.Grimmist:BAABLgAECn8hAAIcAAcJiRguFAC8AQAcAAcJiRguFAC8AQAAAA==.',
Gu='Guloot:BAABLgAECn8bAAMPAAgJAgZRSQDaAAAPAAgJAgZRSQDaAAAOAAUJtQY1SwB2AAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8WAAICAAYJmyA5AQDnAQACAAYJmyA5AQDnAQAuAAQKfxkAAgIACQmSI6EBAGsDAAIACQmSI6EBAGsDAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8dAAIIAAcJFAzxVABJAQAIAAcJFAzxVABJAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8iAAIdAAgJKxtxHQA6AgAdAAgJKxtxHQA6AgAAAA==.',
Ha='Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8XAAIRAAcJlBCZFABHAQARAAcJlBCZFABHAQAAAA==.Haquar:BAAALgADCggJFAAAAA==.Hardhitter:BAAALgAECgEJAQAAAA==.',
He='Hehe:BAAALgADCgQJBAAAAA==.Hellumph:BAABLgAECn8VAAIeAAYJmBc+CgAvAQAeAAYJmBc+CgAvAQAAAA==.Hermesconrad:BAAALgAECgEJAgAAAA==.Hevensrath:BAABLgAECn8mAAIIAAgJ2xwFFwBDAgAIAAgJ2xwFFwBDAgAAAA==.',
Ho='Hokuden:BAABLgAECn8uAAIfAAgJIxuBAgATAgAfAAgJIxuBAgATAgAAAA==.Honina:BAAALgADCgIJAgAAAA==.Hornswaggles:BAAALgAECgQJBAAAAA==.Horsebananas:BAABLgAECn8iAAMXAAgJTBn8EgCFAQALAAcJGRkTRACfAQAXAAcJeBf8EgCFAQAAAA==.',
Ht='Htari:BAAALgAECgEJAQAAAA==.',
Hu='Huddington:BAABLgAECn8ZAAIgAAgJVBcDAgDpAQAgAAgJVBcDAgDpAQAAAA==.Hussh:BAAALgAECgMJBgABLgAECgkJHgASAM0WAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
['Hø']='Hørse:BAAALgAECgEJAQAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgcJBwAAAA==.Imdarkness:BAAALgAECgUJCAAAAA==.Impquisitor:BAAALgAECgEJAQAAAA==.',
In='Indecent:BAABLgAECn8lAAQGAAgJ1xrjFQAzAgAGAAgJwRrjFQAzAgAHAAYJHBd2FACnAQAFAAMJ3hQLGAC7AAAAAA==.Indeed:BAAALgAECgEJAQAAAA==.Inibble:BAAALgADCgEJAQAAAA==.',
Is='Ishy:BAAALgAECgUJCAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgQJCQABAAAAAA==.',
Iz='Izomar:BAABLgAECn8VAAIdAAcJjxgNOQC+AQAdAAcJjxgNOQC+AQABLgAECggJLAAOAK4PAA==.',
Ja='Jackieechan:BAAALgADCgEJAQABLgAFFAMJCAAWAJAmAA==.Jackiemays:BAACLgAFFH8IAAMWAAMJkCYiDQBXAQAWAAMJkCYiDQBXAQAIAAEJsQEnZAA9AAAuAAQKfyoAAxYACAkUJJYEAOkCABYACAkUJJYEAOkCAAgACAlgGnU9AC8CAAAA.Jaded:BAAALgADCgYJBgAAAA==.Jamesin:BAAALgAECgEJAQAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAwAAAA==.Jeses:BAABLgAECn8kAAIIAAgJJxT6MAC5AQAIAAgJJxT6MAC5AQAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAABLgAECn8uAAIPAAgJ3yAGCACsAgAPAAgJ3yAGCACsAgAAAA==.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
Ka='Kaia:BAABLgAECn8cAAIMAAgJhAluEwB5AQAMAAgJhAluEwB5AQAAAA==.Kaldrich:BAAALgADCgYJBgAAAA==.Kamoto:BAAALgADCgkJHwABLgAECgcJHAAOAHwRAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAAALgAECggJEwAAAA==.Kardio:BAABLgAECn8ZAAMUAAgJqQ2mKwCBAQAUAAgJqQ2mKwCBAQAcAAEJAQpNZwA1AAAAAA==.Kayrina:BAAALgADCggJCAAAAA==.Kazeer:BAAALgAECgYJCQAAAA==.',
Kb='Kbilly:BAABLgAECn8lAAIPAAkJqRxHCQCYAgAPAAkJqRxHCQCYAgAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8SAAIMAAUJLCXnAgCxAQAMAAUJLCXnAgCxAQAuAAQKfyAAAgwACQnWGUcTAH4CAAwACQnWGUcTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8IAAIhAAMJmQTsFADOAAAhAAMJmQTsFADOAAAuAAQKfykAAiEACAmNFMISALEBACEACAmNFMISALEBAAAA.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCggJCAAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgQJBAAAAA==.',
Ko='Kobe:BAAALgAECgUJDQAAAA==.Koharu:BAAALgADCgcJDgAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn8mAAITAAgJGxMyBgDgAQATAAgJGxMyBgDgAQAAAA==.Kranok:BAAALgAECgUJDQAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAAALgAECgUJBgAAAA==.',
Ky='Kynessa:BAAALgAECgQJCQAAAA==.Kyrun:BAABLgAECn8dAAITAAcJyQvwCwBLAQATAAcJyQvwCwBLAQAAAA==.',
['Kã']='Kãne:BAABLgAECn8bAAMiAAgJyQ/FHABYAQAiAAgJyQ/FHABYAQAVAAIJvQaSOABUAAAAAA==.',
La='Lamoran:BAAALgADCgkJDwAAAA==.Lannes:BAAALgADCgEJAQAAAA==.Lapz:BAAALgAECgUJBQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8IAAISAAIJ0h1MBwCSAAASAAIJ0h1MBwCSAAAuAAQKfxQAAhIACQlbIMQDANcCABIACQlbIMQDANcCAAAA.',
Lh='Lhani:BAABLgAECn8hAAIEAAcJvQ+SHgBUAQAEAAcJvQ+SHgBUAQAAAA==.',
Li='Liadrin:BAABLgAECn8eAAISAAkJzRZzDwDNAQASAAkJzRZzDwDNAQAAAA==.Lie:BAAALgAECgYJEgAAAA==.Liliana:BAAALgADCgkJJQAAAA==.',
Ll='Llyrael:BAAALgAECgYJEQAAAA==.',
Lo='Lolineverdie:BAABLgAECn8ZAAMJAAkJdQpyPAAjAQAJAAkJdQpyPAAjAQAaAAYJnQI+QACBAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMEAAgJEQrwLQCNAQAEAAgJEQrwLQCNAQAhAAgJ1geEHABYAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJDQAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Maddeleine:BAAALgAECgYJDgAAAA==.Magicdemon:BAABLgAECn8mAAMKAAgJziJ3CQCPAgAKAAgJnSB3CQCPAgARAAQJpSSwKgBwAQAAAA==.Magichunter:BAAALgAECgEJAQABLgAECggJJgAKAM4iAA==.Makall:BAAALgADCgEJAQAAAA==.Malaah:BAABLgAECn8lAAIOAAkJgxIcFAC1AQAOAAkJgxIcFAC1AQAAAA==.Malafar:BAAALgAECgUJBQAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCggJCAAAAA==.Manofsecks:BAAALgAECgQJBgAAAA==.Mapachote:BAAALgAECgYJEgAAAA==.Marodin:BAAALgADCgkJJwAAAA==.Marthaiden:BAAALgAECgcJCwAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8dAAMjAAcJgBSSFQCRAQAjAAcJ+A+SFQCRAQAEAAQJ1hTVMQDBAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8fAAMhAAgJBREQGQBzAQAhAAgJBREQGQBzAQAjAAEJ6gE8TwAiAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCgAAAA==.Mileta:BAAALgAECgUJDwAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.',
Mo='Monki:BAAALgAECgUJBgAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAAALgAECggJEwAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQAAAA==.Muminah:BAAALgAECgMJAwAAAA==.',
['Mô']='Môlly:BAACLgAFFH8HAAIEAAMJrx4BCwAaAQAEAAMJrx4BCwAaAQAuAAQKfygAAgQACAlfIpYFAPYCAAQACAlfIpYFAPYCAAAA.',
Na='Narnluz:BAABLgAECn8WAAIEAAgJfRcTCwA1AgAEAAgJfRcTCwA1AgAAAA==.Nazor:BAABLgAECn8hAAIKAAgJ3xhqIgC6AQAKAAgJ3xhqIgC6AQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn8sAAIRAAkJsxfWBQBRAgARAAkJsxfWBQBRAgAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAAALgAECgQJBAABLgAECggJJwAQABojAA==.Nessee:BAAALgAECgQJCgAAAA==.',
Ni='Niall:BAABLgAECn8mAAIZAAgJNx7pAgBsAgAZAAgJNx7pAgBsAgAAAA==.Nilithis:BAABLgAECn8iAAMGAAgJ+RryGQAVAgAGAAgJExryGQAVAgAHAAQJGxMJEgDGAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAIOAAcJpgm7QwA6AQAOAAcJpgm7QwA6AQAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgYJEAAAAA==.Nyxlumina:BAAALgAECgEJAQAAAA==.',
['Né']='Néssima:BAABLgAECn8ZAAMIAAgJ0xflOgCWAQAIAAgJWg/lOgCWAQASAAUJYhuUIwDrAAAAAA==.',
Oa='Oak:BAAALgAECgEJAwAAAA==.Oathfinder:BAAALgAECgYJDwAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMJAAgJ2QX2UwDHAAAJAAcJBwT2UwDHAAAaAAEJZwLOYgAiAAAAAA==.Octalexane:BAAALgAECgUJBgAAAA==.',
On='Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAABLgAECn8sAAIdAAgJ6iNNCgDTAgAdAAgJ6iNNCgDTAgAAAA==.',
Pa='Pandariee:BAAALgAECgcJDAAAAA==.Parzval:BAAALgAECgEJAQAAAA==.Paxgor:BAAALgADCgUJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn8uAAIRAAgJoxX9CQDpAQARAAgJoxX9CQDpAQAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.',
Ph='Pherix:BAAALgAECgUJEAAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.',
Po='Poomacha:BAABLgAECn8aAAILAAYJ9QkMVwAJAQALAAYJ9QkMVwAJAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.',
Py='Pyree:BAABLgAECn8aAAMiAAgJNg8/LgDuAAAiAAgJgA4/LgDuAAAVAAcJZglXEAB+AAAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwABLgAFFAIJAgABAAAAAA==.',
Qu='Qu:BAAALgAECgcJCgAAAA==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Raenne:BAAALgAECgIJAwAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8eAAIKAAgJVBdCHgDTAQAKAAgJVBdCHgDTAQAAAA==.Rallsdemon:BAAALgAECgQJBAAAAA==.Rallsodins:BAAALgADCgQJBgABLgAECgQJBAABAAAAAA==.Randomguy:BAABLgAECn8rAAIMAAgJbyTvAQDqAgAMAAgJbyTvAQDqAgAAAA==.Ranulf:BAAALgAECgEJAQAAAA==.Ratava:BAAALgAECgIJAgAAAA==.Ratrot:BAAALgAECgYJEQAAAA==.',
Re='Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8fAAMjAAgJ9SGgAgAdAwAjAAgJ9SGgAgAdAwAEAAQJ+hr4RAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJBgAAAA==.Reverence:BAAALgAECggJEAAAAA==.Revilation:BAABLgAECn8cAAISAAkJYBPuCAC6AQASAAkJYBPuCAC6AQAAAA==.Rezjyk:BAAALgADCgEJAQABLgAECgcJHgAIAOYZAA==.Rezzyk:BAABLgAECn8eAAIIAAcJ5hlgMAC7AQAIAAcJ5hlgMAC7AQAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAAALgAECgUJCgAAAA==.',
Ri='Riis:BAAALgAECgQJBgAAAA==.Riiselock:BAABLgAECn8oAAMGAAgJIR47NwAvAgAGAAcJyR07NwAvAgAHAAQJFByUDQD5AAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Riptidepod:BAABLgAECn8bAAMPAAcJhgd6PAATAQAPAAcJhgd6PAATAQAOAAIJ3gK3cQAhAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAABLgAECn8WAAMMAAUJASEDJwDAAQAMAAUJASEDJwDAAQAkAAIJWRHhDQB4AAAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMEAAkJtR5mCwCaAgAEAAcJ3yRmCwCaAgAhAAcJtRSCKgCGAQAAAA==.Sagerremeseb:BAAALgADCggJFAAAAA==.Sakii:BAABLgAECn8YAAIKAAgJfAyyPgA9AQAKAAgJfAyyPgA9AQAAAA==.Samvimes:BAABLgAECn8ZAAIIAAUJBw66gwDkAAAIAAUJBw66gwDkAAAAAA==.Sangreene:BAABLgAECn8bAAIhAAgJRxqAEwBYAgAhAAgJRxqAEwBYAgAAAA==.Sargis:BAABLgAECn8uAAMIAAgJ0x8uDgCNAgAIAAgJ0x8uDgCNAgAWAAgJyBtxCgBqAgAAAA==.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwABLgAECgcJEgABAAAAAA==.Sciblasts:BAAALgADCgEJAQABLgADCgkJDAABAAAAAA==.Scott:BAACLgAFFH8aAAIKAAYJ1SOGAwANAgAKAAYJ1SOGAwANAgAuAAQKfzAAAgoACQlLJnQAAO4DAAoACQlLJnQAAO4DAAAA.Scratchh:BAABLgAECn8dAAIbAAgJlAsrNgB0AQAbAAgJlAsrNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwABLgAECggJKQATAKEYAA==.Sentis:BAABLgAECn8YAAIaAAYJ3AeQMADQAAAaAAYJ3AeQMADQAAAAAA==.',
Sh='Shadowbrooks:BAAALgAECgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8gAAIhAAcJ5BjTEADGAQAhAAcJ5BjTEADGAQAAAA==.Shamemoon:BAABLgAECn8YAAIKAAcJCxf/KwCHAQAKAAcJCxf/KwCHAQAAAA==.Shamunroe:BAABLgAECn8gAAMPAAgJoAeYOAAlAQAPAAgJoAeYOAAlAQAOAAQJKhGoWgDZAAAAAA==.Shatterhoof:BAABLgAECn8VAAIZAAYJSAqgEQADAQAZAAYJSAqgEQADAQAAAA==.Shelle:BAAALgAECgEJAQAAAA==.Shiftys:BAAALgADCgUJCgABLgAECgMJBQABAAAAAA==.Shingra:BAACLgAFFH8SAAIiAAUJzBVsEgBDAQAiAAUJzBVsEgBDAQAuAAQKfxsAAiIACAnvG90PAHkCACIACAnvG90PAHkCAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgEJAQAAAA==.Silversho:BAAALgADCgkJCQAAAA==.Silvoid:BAAALgADCgMJAwAAAA==.Silvren:BAABLgAECn8WAAMDAAYJ1BMAKQAzAQADAAYJ1BMAKQAzAQAlAAEJvwZkRgArAAAAAA==.Sindarion:BAAALgAECgQJBAAAAA==.Sinz:BAAALgAECgEJBAAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8eAAIJAAgJ4hm7EABOAgAJAAgJ4hm7EABOAgAAAA==.',
Sl='Slighttrash:BAAALgAECgYJEQAAAA==.Sloppy:BAAALgADCggJCAAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8RAAIUAAYJMR24AAACAgAUAAYJMR24AAACAgAuAAQKfxUAAhQABwkuJsEHAP8CABQABwkuJsEHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECggJGgANANcaAA==.Snowsong:BAAALgAECgEJAQAAAA==.',
Sp='Spectrose:BAAALgADCgEJAQAAAA==.Spiro:BAAALgAFFAIJAgAAAA==.',
St='Starge:BAAALgAECgQJBgAAAA==.Steffey:BAABLgAECn8UAAIPAAYJggl1RADwAAAPAAYJggl1RADwAAAAAA==.Straven:BAAALgAECgYJDgAAAA==.Sturgeson:BAACLgAFFH8SAAICAAUJ1RjmBwAuAQACAAUJ1RjmBwAuAQAuAAQKfx0AAgIACQkoHQMMAEsCAAIACQkoHQMMAEsCAAAA.',
Su='Sulwen:BAABLgAECn8lAAIEAAkJJBeODAAcAgAEAAkJJBeODAAcAgAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8dAAILAAgJZBP9JwCyAQALAAgJZBP9JwCyAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAAALgAECgUJCgAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8VAAIaAAgJ1hVhNgBiAQAaAAgJ1hVhNgBiAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAACLgAFFH8FAAIJAAMJowFWNQB4AAAJAAMJowFWNQB4AAAuAAQKfyIAAgkACAmsDNFKAHgBAAkACAmsDNFKAHgBAAAA.Targaryian:BAAALgAECgMJAwAAAA==.Taylea:BAAALgAECgcJEQABLgAECgcJHAAIAH0eAA==.',
Te='Techromancer:BAAALgAECgQJBAABLgAECgUJEAABAAAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgADCgQJBwAAAA==.',
Th='Thanatias:BAABLgAECn8UAAIQAAcJ9hQ5EABuAQAQAAcJ9hQ5EABuAQAAAA==.Thantasia:BAAALgAECgYJDwAAAA==.Thauras:BAAALgADCgcJDgAAAA==.Thom:BAACLgAFFH8FAAIfAAMJwBCUBADnAAAfAAMJwBCUBADnAAAuAAQKfykAAx8ACAmuI+cAABwDAB8ACAmuI+cAABwDABgABgmoDjCxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tifà:BAAALgAECgUJCAAAAA==.Timothy:BAAALgAECgYJDwAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Tormmok:BAAALgAECgYJDAAAAA==.Toshindo:BAAALgADCgQJBAAAAA==.',
Tr='Trashpally:BAAALgAECgEJAgAAAA==.Tremèndor:BAAALgADCgMJAwAAAA==.Trey:BAAALgAECgEJAQAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn8mAAIbAAgJfg7vFgCBAQAbAAgJfg7vFgCBAQAAAA==.',
Tu='Turkwise:BAABLgAECn8fAAMNAAgJDxdXBwDCAQANAAgJDxdXBwDCAQAZAAQJCBGqHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCggJCAAAAA==.',
Us='Usami:BAAALgAECgEJAQAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgEJAQAAAA==.',
Va='Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8GAAIUAAMJbx6TCgAoAQAUAAMJbx6TCgAoAQAuAAQKfy4AAhQACAmTJA0DANYCABQACAmTJA0DANYCAAAA.Vanillanice:BAAALgAECgQJBAAAAA==.Varrfife:BAAALgAECgMJAwAAAA==.Vaxaldan:BAABLgAECn8mAAIQAAgJNQ8YEQBgAQAQAAgJNQ8YEQBgAQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAABLgAECn8WAAIIAAcJIApNdgAAAQAIAAcJIApNdgAAAQAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Vestrae:BAACLgAFFH8GAAMJAAMJzQULKwChAAAJAAMJzQULKwChAAAaAAEJSQEfLAAxAAAuAAQKfyQAAgkACAl+Hm8TAJoCAAkACAl+Hm8TAJoCAAAA.Vex:BAAALgAECgYJEwAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.',
Vo='Vodash:BAAALgAECgYJEwABLgAECgcJHwAJAGoQAA==.Vostok:BAABLgAECn8aAAIGAAgJNhwTJQDWAQAGAAgJNhwTJQDWAQAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn8mAAIaAAgJthqwCgAgAgAaAAgJthqwCgAgAgAAAA==.',
Wy='Wyelie:BAAALgAECgYJBgAAAA==.Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgYJBgAAAA==.',
Xo='Xotha:BAABLgAECn8pAAIKAAgJ2R14DwBKAgAKAAgJ2R14DwBKAgAAAA==.',
Xu='Xuen:BAAALgAECgEJAQAAAA==.',
Xy='Xythera:BAACLgAFFH8GAAIKAAMJARnbLgD1AAAKAAMJARnbLgD1AAAuAAQKfxgAAgoACAlSIvMVANMCAAoACAlSIvMVANMCAAAA.',
Ye='Yeah:BAAALgADCgYJBgABLgAECgkJKwASANohAA==.',
Yi='Yinosai:BAAALgADCgQJBAAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8cAAIHAAYJaR3+BACyAQAHAAYJaR3+BACyAQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgcJHAAIAH0eAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zalirina:BAAALgADCgIJAgAAAA==.Zanka:BAAALgAECgIJAgAAAA==.Zaridruid:BAAALgAECgcJBAAAAA==.Zarisedra:BAACLgAFFH8SAAMWAAUJcRTVCQCBAQAWAAUJcRTVCQCBAQAIAAEJXgDUOwA2AAAuAAQKfxgAAxYACQkwF8gpAOMBABYACAkGGMgpAOMBAAgAAQktBuY9ATUAAAAA.Zarissena:BAAALgAECgMJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8XAAQEAAgJKRj+FwCQAQAEAAUJERv+FwCQAQAhAAYJ5xE9LgBvAQAjAAEJARe5QQBEAAAAAA==.Zerogasm:BAAALgAECgYJCQAAAA==.Zerolicious:BAAALgADCgUJBgAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8lAAIDAAgJJSH7BACrAgADAAgJJSH7BACrAgAAAA==.',
Zo='Zoraji:BAABLgAECn8uAAIbAAgJ/xheCgAeAgAbAAgJ/xheCgAeAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8SAAMjAAUJDQhiDgBhAQAjAAUJ4QdiDgBhAQAEAAEJ8whuFgA8AAAAAA==.Zuggar:BAABLgAECn8fAAIDAAcJVwivKQAvAQADAAcJVwivKQAvAQAAAA==.',
Zy='Zynhammer:BAABLgAECn8kAAMKAAgJghGKUQAFAQAKAAgJghGKUQAFAQARAAEJawZpRAAtAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëb']='Ëbony:BAAALgAFFAEJAQAAAA==.',
['Ëd']='Ëdën:BAAALgAECgcJCgAAAA==.',
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

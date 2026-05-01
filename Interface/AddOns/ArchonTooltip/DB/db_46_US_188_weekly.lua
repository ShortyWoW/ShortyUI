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

local lookup = {'Unknown-Unknown','Warrior-Protection','Warrior-Fury','Priest-Holy','Paladin-Retribution','Druid-Restoration','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Rogue-Subtlety','Druid-Guardian','DeathKnight-Blood','DemonHunter-Havoc','Paladin-Protection','Shaman-Enhancement','Monk-Windwalker','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','DeathKnight-Frost','Hunter-BeastMastery','Priest-Shadow','Evoker-Augmentation','Priest-Discipline',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abear:BAAALgAECgQJBQAAAA==.Abrocklock:BAAALgAECgYJBgAAAA==.',
Ac='Achilês:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.',
Ad='Adaluna:BAAALgADCgYJBwAAAA==.Adorabull:BAABLgAECn8eAAMCAAgJWCAyAwBfAgACAAgJWCAyAwBfAgADAAEJ0AYJrwAsAAAAAA==.Adrain:BAAALgAECgQJCwAAAA==.Adwae:BAAALgAECgIJAgAAAA==.',
Ae='Aelyn:BAAALgAECgUJCQAAAA==.Aerendyl:BAAALgAECgEJAQAAAA==.Aevelee:BAAALgAECgIJAgAAAA==.Aevick:BAAALgAECgQJBQAAAA==.',
Al='Alastair:BAAALgADCgEJAQAAAA==.Aleeta:BAAALgADCgcJDAAAAA==.',
Am='Amapanda:BAAALgADCgUJBQAAAA==.Amaria:BAAALgAECgMJBAAAAA==.Amoracchius:BAAALgADCgMJAwAAAA==.',
An='Angelstörm:BAABLgAECn8oAAIEAAgJ2xcGDADkAQAEAAgJ2xcGDADkAQAAAA==.Antarias:BAAALgAECgQJDQAAAA==.Antarion:BAAALgAECgQJBAAAAA==.',
Ap='Applevendor:BAAALgADCgUJBQAAAA==.',
Ar='Arcanio:BAAALgADCgQJBAAAAA==.Arcaux:BAAALgADCggJDgAAAA==.Arckenon:BAABLgAECn8jAAIFAAgJ7h+0CwBsAgAFAAgJ7h+0CwBsAgAAAA==.',
As='Ashdorei:BAAALgADCgEJAQAAAA==.Ashog:BAAALgAECgYJDAAAAA==.',
At='Athanyr:BAABLgAECn8fAAIGAAgJAiWkBwCUAgAGAAgJAiWkBwCUAgAAAA==.Atillis:BAAALgADCgYJDAAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Austenpally:BAAALgAECgUJCwAAAA==.',
Aw='Awake:BAAALgAECgQJBAABLgAECggJDwABAAAAAA==.',
Ax='Axeflack:BAAALgAECgEJAQAAAA==.Axegor:BAAALgADCgMJAwAAAA==.',
Ba='Bacuda:BAAALgAECgQJBwAAAA==.Balkris:BAAALgADCgkJCQABLgAECgYJDwABAAAAAA==.Baratheon:BAAALgAECgkJEQAAAA==.',
Be='Beartooth:BAAALgADCgUJBQAAAA==.Beggles:BAAALgADCgEJAQAAAA==.Bereit:BAAALgADCgcJBgAAAA==.',
Bi='Biancadelrio:BAAALgAECgUJBgAAAA==.Bigmode:BAAALgADCgYJBgAAAA==.',
Bl='Blackmask:BAAALgADCgUJCAAAAA==.Blindashunae:BAACLgAFFH8OAAIHAAUJwRWiEAA4AQAHAAUJwRWiEAA4AQAuAAQKfxYAAgcACQlQHisVANgCAAcACQlQHisVANgCAAAA.Blindkungfu:BAAALgAECgQJBAAAAA==.Bloodrun:BAAALgADCggJCAAAAA==.Blook:BAAALgAECgcJEAAAAA==.Bluehazey:BAAALgAECgYJDQAAAA==.Bläz:BAAALgAECgEJAQAAAA==.',
Bo='Bootsy:BAAALgAECgEJAQAAAA==.Bopit:BAAALgAECgcJEAAAAA==.Botia:BAAALgAECgQJDAAAAA==.',
Br='Bruhh:BAAALgAECgYJBwAAAA==.Brunnera:BAAALgAECgEJAQAAAA==.Bruul:BAAALgAECgYJEgAAAA==.Brynjolf:BAAALgAECgUJCQAAAA==.',
Ca='Caenji:BAAALgAECgYJDwAAAA==.Carcharoth:BAABLgAECn8YAAMIAAcJsxdRCQASAQAIAAYJlRdRCQASAQAJAAQJIBDZvgDbAAAAAA==.Carmelina:BAAALgAECgUJBQAAAA==.Catrixona:BAAALgAECgQJBwAAAA==.Caylan:BAAALgADCgQJBAAAAA==.',
Ch='Chadgar:BAAALgADCgIJAgAAAA==.Chaoscaster:BAAALgADCgkJCQABLgAECgYJBgABAAAAAA==.Chey:BAABLgAECn8lAAIKAAkJ2CFGAgCiAgAKAAkJ2CFGAgCiAgAAAA==.Chilai:BAABLgAECn8ZAAILAAYJOhjACQA2AQALAAYJOhjACQA2AQAAAA==.Chipsahoy:BAAALgAECgcJEQAAAA==.',
Ci='Cindrozetha:BAAALgADCgEJAQAAAA==.',
Cl='Close:BAAALgADCgUJBQABLgAECggJHwAMABojAA==.',
Co='Conciete:BAAALgAFFAEJAQAAAA==.Conorix:BAAALgAECgUJCAAAAA==.Corvo:BAAALgAECgYJCgABLgAECgYJDwABAAAAAA==.Counselor:BAAALgAECgUJBQAAAA==.Courallie:BAAALgADCgUJAwAAAA==.',
Cr='Crataxxis:BAABLgAECn8iAAINAAYJ7RZMEAA4AQANAAYJ7RZMEAA4AQAAAA==.Crynos:BAAALgADCgMJAwAAAA==.Crysandra:BAAALgADCgUJBQAAAA==.',
Cy='Cydon:BAABLgAECn8dAAILAAcJbB9PAwARAgALAAcJbB9PAwARAgAAAA==.',
Da='Daereth:BAAALgAECgYJCQAAAA==.Daerrith:BAAALgAECgUJCQAAAA==.Damienfox:BAAALgADCgcJBwAAAA==.Danellia:BAAALgADCgUJBQAAAA==.Darkreaper:BAAALgAECgQJBAAAAA==.Darrwin:BAABLgAECn8ZAAMFAAcJeR5qGgDsAQAFAAcJeR5qGgDsAQAOAAMJaAyOGgCNAAAAAA==.Dawicker:BAAALgADCgYJDwAAAA==.Daylight:BAAALgAECgEJAQAAAA==.',
De='Defacto:BAAALgADCgMJAwAAAA==.Delrac:BAAALgAFFAEJAQAAAA==.Demonalsa:BAAALgAECgEJAQABLgAECggJIQAPAIQVAA==.Denero:BAAALgAECgcJEAAAAA==.Departure:BAAALgAECgMJBAABLgAECgYJFQANAAIcAA==.Derith:BAAALgADCgEJAQAAAA==.',
Df='Dfabness:BAABLgAECn8ZAAIQAAcJbA5hFgA2AQAQAAcJbA5hFgA2AQAAAA==.',
Di='Dic:BAAALgADCgIJAgAAAA==.',
Do='Dotspot:BAAALgADCgQJBAABLgAECgMJBwABAAAAAA==.',
Dr='Dracthayr:BAABLgAECn8mAAIRAAgJUBLOAgDUAQARAAgJUBLOAgDUAQAAAA==.Dragonhammer:BAABLgAECn81AAIFAAgJZCSUBADTAgAFAAgJZCSUBADTAgAAAA==.Drakanna:BAAALgAECgIJAgAAAA==.Dreaming:BAABLgAECn8fAAIMAAgJGiPABAD7AgAMAAgJGiPABAD7AgAAAA==.Drosidon:BAAALgAECgcJDAAAAA==.Drubo:BAAALgADCgkJEwAAAA==.',
Ea='Earsog:BAAALgADCgEJAQAAAA==.Earthenfist:BAAALgAECgEJAQAAAA==.',
Eb='Ebebebebe:BAAALgAECgEJAQAAAA==.',
Ef='Efbomb:BAAALgADCgcJBwAAAA==.',
Ei='Eitherindel:BAAALgADCggJCAAAAA==.',
El='Elassara:BAAALgAECgEJAQAAAA==.Ellaini:BAAALgAECgYJEwAAAA==.Ellie:BAAALgADCgkJEAABLgAECgkJKAASANgcAA==.Elseb:BAAALgADCgUJBQAAAA==.',
Em='Emotion:BAAALgADCgYJAQABLgAECggJHwAMABojAA==.',
Er='Erenara:BAAALgAECgQJCwAAAA==.',
Ev='Evic:BAABLgAECn8YAAIGAAcJtA/lJgBPAQAGAAcJtA/lJgBPAQAAAA==.',
Ew='Ewson:BAAALgADCgcJCwAAAA==.',
Fa='Faandango:BAAALgAECgUJBQAAAA==.Faeleader:BAAALgAECgUJCwAAAA==.Faevelina:BAAALgAECgUJDAAAAA==.Faytadori:BAAALgADCgEJAQAAAA==.',
Fe='Felgrrl:BAAALgADCgkJGwAAAA==.Felsite:BAAALgAECgkJAQAAAA==.Feyreh:BAAALgAECgEJAQAAAA==.',
Fi='Fieona:BAAALgADCgYJCwAAAA==.Firethorns:BAAALgADCgMJAwAAAA==.Fistandilias:BAAALgADCgkJCQAAAA==.Fitzbang:BAAALgAECgUJBgAAAA==.',
Fl='Florigrowl:BAAALgADCgcJDAAAAA==.',
Fo='Forever:BAAALgAECgIJAwABLgAECggJHwAMABojAA==.Formortiis:BAAALgADCgEJAQAAAA==.Forrestior:BAABLgAECn8YAAITAAgJoiSgAQA/AwATAAgJoiSgAQA/AwAAAA==.Forsthoof:BAAALgADCgYJBgAAAA==.',
Fr='Fraga:BAAALgAECgYJDgABLgAECggJHgAUAMIcAA==.Frailty:BAAALgAECgUJBQAAAA==.Frique:BAAALgADCgcJFQAAAA==.Frostfingers:BAAALgADCggJDwAAAA==.Frostyfang:BAABLgAECn8XAAMVAAgJ4BpfDgDLAQAVAAYJxh5fDgDLAQAWAAMJIhEPNgBvAAAAAA==.Frozenyogert:BAAALgAECgQJBAAAAA==.',
Fu='Fufula:BAAALgADCgQJBAAAAA==.Funkbot:BAAALgAECgYJDAAAAA==.',
['Fä']='Färshadow:BAAALgAECgEJAQAAAA==.',
Ga='Galbur:BAABLgAECn8eAAMUAAgJwhw6EAA8AgAUAAgJaRs6EAA8AgAMAAcJMhPLFwCdAQAAAA==.Galdrin:BAAALgAECgMJAwABLgAECgUJDAABAAAAAA==.Gaspode:BAAALgADCgcJBwAAAA==.Gassann:BAAALgAECggJDgAAAA==.',
Ge='Geers:BAAALgAECgcJEAAAAA==.Geta:BAAALgAECgQJBAABLgAECgkJHAADACEgAA==.Getacast:BAAALgADCgEJAQABLgAECgkJHAADACEgAA==.Getalife:BAAALgADCgQJBAABLgAECgkJHAADACEgAA==.Getarage:BAABLgAECn8cAAIDAAkJISAjFACtAgADAAkJISAjFACtAgAAAA==.',
Gh='Ghil:BAABLgAECn8cAAMXAAcJTiGsAABPAgAXAAcJTiGsAABPAgAJAAQJnhXUvADfAAAAAA==.',
Gi='Gigawatt:BAABLgAECn8VAAMYAAcJGQmLHwAdAQAYAAcJGQmLHwAdAQAZAAIJCQw2UwBZAAAAAA==.Gildersleeve:BAAALgAECgQJBgAAAA==.Gilia:BAAALgADCgkJHgAAAA==.Girthfist:BAABLgAECn8WAAIaAAgJRSMKBQA5AwAaAAgJRSMKBQA5AwABLgAFFAYJFQACAJ0gAA==.',
Gl='Glynixtwo:BAAALgAECgIJAgAAAA==.',
Go='Goldiwarlock:BAAALgADCgYJBwAAAA==.Goloron:BAAALgADCgUJBgAAAA==.',
Gr='Graymayn:BAAALgAECgMJBAAAAA==.Gremel:BAAALgAECgYJCwAAAA==.Grimmist:BAABLgAECn8ZAAIbAAYJTxpVEgCJAQAbAAYJTxpVEgCJAQAAAA==.',
Gu='Guloot:BAABLgAECn8YAAMZAAYJGASVRwCEAAAZAAYJGASVRwCEAAAYAAUJtAYHOwB9AAAAAA==.Gunboyten:BAAALgAECgIJAgAAAA==.Gunderthirth:BAACLgAFFH8VAAICAAYJnSABAQDWAQACAAYJnSABAQDWAQAuAAQKfxkAAgIACQmSI6EBAGsDAAIACQmSI6EBAGsDAAAA.Gurkin:BAAALgADCgEJAQAAAA==.',
Gw='Gwaeniiha:BAABLgAECn8WAAIFAAcJdAkFSQAvAQAFAAcJdAkFSQAvAQAAAA==.Gward:BAAALgAECgUJBgAAAA==.Gwizz:BAABLgAECn8cAAIcAAcJ2xzhIADoAQAcAAcJ2xzhIADoAQAAAA==.',
Ha='Halinka:BAAALgADCgYJBgAAAA==.Handsoap:BAABLgAECn8WAAINAAYJ/hBpEgAeAQANAAYJ/hBpEgAeAQAAAA==.Haquar:BAAALgADCgcJDAAAAA==.Hardhitter:BAAALgAECgEJAQAAAA==.',
He='Hellumph:BAAALgAECgUJDgAAAA==.Hermesconrad:BAAALgADCgEJAQAAAA==.Hevensrath:BAABLgAECn8eAAIFAAgJVBigGwDkAQAFAAgJVBigGwDkAQAAAA==.',
Ho='Hokuden:BAABLgAECn8mAAIdAAgJcRZkAgDeAQAdAAgJcRZkAgDeAQAAAA==.Honina:BAAALgADCgIJAgAAAA==.Horsebananas:BAABLgAECn8dAAMTAAcJDhj7DQB/AQAeAAYJ/BcSRACfAQATAAcJMxb7DQB/AQAAAA==.',
Hu='Huddington:BAAALgAECggJEQAAAA==.Hussh:BAAALgAECgEJAgABLgAECgkJHAAOAEAWAA==.',
Hy='Hydraness:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
['Hø']='Hørse:BAAALgAECgEJAQAAAA==.',
Ia='Iamcammy:BAAALgAECgYJEAAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.',
Im='Imariz:BAAALgAECgYJBgAAAA==.Imdarkness:BAAALgAECgMJBAAAAA==.Impquisitor:BAAALgAECgEJAQAAAA==.',
In='Indecent:BAABLgAECn8dAAQJAAgJWRrTDgAzAgAJAAgJ+xnTDgAzAgAIAAYJHBd3FACnAQAXAAMJ3hQKGAC7AAAAAA==.Indeed:BAAALgAECgEJAQAAAA==.Inibble:BAAALgADCgEJAQAAAA==.',
Is='Ishy:BAAALgAECgQJBAAAAA==.',
Ix='Ixelle:BAAALgADCgUJDQABLgAECgQJCQABAAAAAA==.',
Iz='Izomar:BAAALgAECgcJDgABLgAECggJLAAYAKUPAA==.',
Ja='Jackieechan:BAAALgADCgEJAQABLgAFFAMJBQASADImAA==.Jackiemays:BAACLgAFFH8FAAMSAAMJMiZ2CQBUAQASAAMJMiZ2CQBUAQAFAAEJsAEmSwA9AAAuAAQKfyoAAxIACAkVJA8CAAQDABIACAkVJA8CAAQDAAUACAlgGnc9AC8CAAAA.Jaded:BAAALgADCgYJBgAAAA==.Jamesin:BAAALgADCgEJAgAAAA==.',
Je='Jedaii:BAAALgAECgYJBgAAAA==.Jeff:BAAALgAECgEJAgAAAA==.Jeses:BAABLgAECn8cAAIFAAcJoxFFNwBnAQAFAAcJoxFFNwBnAQAAAA==.',
Jo='Jollah:BAAALgAECgUJBgAAAA==.',
Ju='Jutic:BAABLgAECn8mAAIZAAgJRyDNBQCTAgAZAAgJRyDNBQCTAgAAAA==.',
Jy='Jyssa:BAAALgADCgEJAQAAAA==.',
Ka='Kaia:BAABLgAECn8WAAIKAAgJUgm7DgCAAQAKAAgJUgm7DgCAAQAAAA==.Kaldrich:BAAALgADCgYJBgAAAA==.Kamoto:BAAALgADCgkJHwABLgAECgcJFQAYABkJAA==.Kanetsu:BAAALgADCgIJAgAAAA==.Kardas:BAAALgAECgcJDQAAAA==.Kardio:BAABLgAECn8ZAAMQAAgJpA2rKwCBAQAQAAgJpA2rKwCBAQAbAAEJAQpLZwA1AAAAAA==.Kayrina:BAAALgADCggJCAAAAA==.Kazeer:BAAALgAECgQJBAAAAA==.',
Kb='Kbilly:BAABLgAECn8lAAIZAAkJpBxZBQCgAgAZAAkJpBxZBQCgAgAAAA==.',
Ke='Kegger:BAAALgAECgEJAQAAAA==.Keylerin:BAACLgAFFH8NAAIKAAUJzx+/AgCPAQAKAAUJzx+/AgCPAQAuAAQKfx8AAgoACAmrGUkTAH4CAAoACAmrGUkTAH4CAAAA.',
Ki='Kibbik:BAACLgAFFH8FAAIfAAMJbAP9DgDRAAAfAAMJbAP9DgDRAAAuAAQKfykAAh8ACAmNFP8LAMABAB8ACAmNFP8LAMABAAAA.Kitsunami:BAAALgAECgcJBgAAAA==.',
Kl='Klepal:BAAALgADCggJCAAAAA==.Klutchshield:BAAALgAECgEJAQAAAA==.',
Kn='Kneecap:BAAALgAECgQJBAAAAA==.',
Ko='Kobe:BAAALgAECgQJCAAAAA==.Koharu:BAAALgADCgUJCAAAAA==.Kookykg:BAAALgAECgEJAQAAAA==.',
Kr='Krampus:BAABLgAECn8eAAIPAAgJ3gvRBgCXAQAPAAgJ3gvRBgCXAQAAAA==.Kranok:BAAALgAECgUJDQAAAA==.Krim:BAAALgADCgUJBgAAAA==.Krimhuntress:BAAALgAECgEJAgAAAA==.',
Ku='Kunac:BAAALgAECgUJBgAAAA==.',
Ky='Kynessa:BAAALgAECgQJCQAAAA==.Kyrun:BAABLgAECn8WAAIPAAcJ/AjCCQBLAQAPAAcJ/AjCCQBLAQAAAA==.',
['Kã']='Kãne:BAABLgAECn8aAAMgAAgJXg8kFQBWAQAgAAgJXg8kFQBWAQARAAIJvQaUOABUAAAAAA==.',
La='Lamoran:BAAALgADCgUJBgAAAA==.Lannes:BAAALgADCgEJAQAAAA==.Lavetra:BAAALgAECgMJBAAAAA==.Lazerdinger:BAAALgAECgEJAQAAAA==.',
Le='Legendary:BAACLgAFFH8GAAIOAAIJ0B0cBQCTAAAOAAIJ0B0cBQCTAAAuAAQKfxQAAg4ACQlbIMQDANcCAA4ACQlbIMQDANcCAAAA.',
Lh='Lhani:BAABLgAECn8ZAAIEAAYJPg9KHwAIAQAEAAYJPg9KHwAIAQAAAA==.',
Li='Liadrin:BAABLgAECn8cAAIOAAkJQBZzDwDNAQAOAAkJQBZzDwDNAQAAAA==.Lie:BAAALgAECgYJDwAAAA==.Liliana:BAAALgADCgkJHgAAAA==.',
Ll='Llyrael:BAAALgAECgUJCgAAAA==.',
Lo='Lolineverdie:BAABLgAECn8WAAMGAAkJAAqNLwAfAQAGAAkJAAqNLwAfAQAWAAYJnAJlMgCGAAAAAA==.',
Lu='Luna:BAABLgAECn8iAAMEAAgJEQrsLQCNAQAEAAgJEQrsLQCNAQAfAAgJ8Af4EwBjAQAAAA==.',
Ly='Lyrev:BAAALgAECgYJCwAAAA==.',
['Ló']='Lórien:BAAALgADCgIJAgAAAA==.',
Ma='Maddeleine:BAAALgAECgYJDgAAAA==.Magicdemon:BAABLgAECn8eAAMHAAgJJyIkBwBpAgAHAAgJGB8kBwBpAgANAAQJpSStKgBwAQAAAA==.Magichunter:BAAALgAECgEJAQABLgAECggJHgAHACciAA==.Makall:BAAALgADCgEJAQAAAA==.Malaah:BAABLgAECn8eAAIYAAgJIRAZGQBJAQAYAAgJIRAZGQBJAQAAAA==.Malafar:BAAALgAECgUJBQAAAA==.Malatrixx:BAAALgAECgEJAQAAAA==.Maldiriel:BAAALgAECggJCAAAAA==.Mallikus:BAAALgADCggJCAAAAA==.Manofsecks:BAAALgAECgEJAQAAAA==.Mapachote:BAAALgAECgYJEgAAAA==.Marodin:BAAALgADCgkJHwAAAA==.Marthaiden:BAAALgAECgYJCgAAAA==.Maryjaina:BAAALgADCgYJBgAAAA==.Mavastus:BAAALgADCgcJBwAAAA==.Mazozul:BAABLgAECn8WAAMhAAcJQRL7EQByAQAhAAcJ5Qz7EQByAQAEAAQJ0BSMJgDIAAAAAA==.',
Me='Meatbaal:BAAALgADCgYJCAAAAA==.Melinaria:BAABLgAECn8WAAMfAAcJ2RAaHwACAQAfAAcJ2RAaHwACAQAhAAEJ6AGLPQAkAAAAAA==.Melisondraa:BAAALgADCgkJCQAAAA==.Meow:BAAALgADCgQJBAAAAA==.Merkala:BAAALgADCgYJCQAAAA==.Metalbot:BAAALgADCgkJCQAAAA==.',
Mi='Miarose:BAAALgAECgUJBgAAAA==.Miggydogg:BAAALgAECgUJCgAAAA==.Mileta:BAAALgAECgUJDwAAAA==.Mimic:BAAALgAECgIJAgAAAA==.Minthammer:BAAALgAECgIJBAAAAA==.Mirthias:BAAALgAECgMJAwAAAA==.',
Mo='Monki:BAAALgAECgEJAQAAAA==.Morgorra:BAAALgAECgMJBwAAAA==.Morvila:BAAALgAECgMJAwAAAA==.Mote:BAAALgAECgYJCgAAAA==.',
Mu='Muertes:BAAALgAECgEJAQAAAA==.Multidollar:BAAALgADCgUJBQAAAA==.Muminah:BAAALgADCggJCwAAAA==.',
['Mô']='Môlly:BAABLgAECn8oAAIEAAgJXyKXBQD2AgAEAAgJXyKXBQD2AgAAAA==.',
Na='Narnluz:BAAALgAECgYJDwAAAA==.Nazor:BAABLgAECn8ZAAIHAAgJKxU/HwB3AQAHAAgJKxU/HwB3AQAAAA==.',
Ne='Necronic:BAAALgADCgYJCwAAAA==.Necroreign:BAABLgAECn8lAAINAAgJ3xYDBwDrAQANAAgJ3xYDBwDrAQAAAA==.Neith:BAAALgADCgMJAwAAAA==.Nemera:BAAALgADCgYJCAAAAA==.Nervous:BAAALgAECgIJAgABLgAECggJHwAMABojAA==.Nessee:BAAALgAECgQJCgAAAA==.',
Ni='Niall:BAABLgAECn8mAAIVAAgJNx7cAQBuAgAVAAgJNx7cAQBuAgAAAA==.Nilithis:BAABLgAECn8aAAMJAAgJ2BVMJwCSAQAJAAcJWRVMJwCSAQAIAAQJqQufQgCqAAAAAA==.Niú:BAAALgADCgYJBgAAAA==.',
No='Norsehammer:BAABLgAECn8UAAIYAAcJpgm4QwA6AQAYAAcJpgm4QwA6AQAAAA==.Nozmua:BAAALgADCgkJDgAAAA==.',
Ny='Nyghtchyld:BAAALgAECgUJCwAAAA==.Nyxlumina:BAAALgAECgEJAQAAAA==.',
['Né']='Néssima:BAAALgAECgYJEgAAAA==.',
Oa='Oak:BAAALgAECgEJAgAAAA==.Oathfinder:BAAALgAECgYJDwAAAA==.',
Oc='Occurrence:BAABLgAECn8VAAMGAAgJ1wUvQADQAAAGAAcJBgQvQADQAAAWAAEJbgLKTgAiAAAAAA==.Octalexane:BAAALgAECgEJAQAAAA==.',
On='Onimusha:BAAALgAECgMJAwAAAA==.',
Or='Ortalbem:BAABLgAECn8kAAIcAAgJNSPLBwC8AgAcAAgJNSPLBwC8AgAAAA==.',
Pa='Pandariee:BAAALgAECgYJBgAAAA==.Parzval:BAAALgAECgEJAQAAAA==.Paxgor:BAAALgADCgUJAQAAAA==.',
Pe='Pendaemonia:BAABLgAECn8oAAINAAgJYhTQBwDVAQANAAgJYhTQBwDVAQAAAA==.Penelopie:BAAALgADCgYJBgAAAA==.',
Ph='Pherix:BAAALgAECgQJCwAAAA==.Phiirys:BAAALgAECgEJAQAAAA==.',
Pi='Picaso:BAAALgADCgEJAQAAAA==.',
Po='Poomacha:BAABLgAECn8YAAIeAAYJ9QlKQAAVAQAeAAYJ9QlKQAAVAQAAAA==.',
Pu='Puffthemagic:BAAALgADCgYJCAAAAA==.',
Py='Pyree:BAABLgAECn8YAAMgAAgJnw48MABEAQAgAAcJIg88MABEAQARAAcJZgkjDQCCAAAAAA==.',
['Pø']='Pøë:BAAALgAECgkJEwAAAA==.',
Qu='Qu:BAAALgAECgcJCgAAAA==.',
Qv='Qveemcorkie:BAAALgAECgEJAQAAAA==.',
['Qí']='Qín:BAAALgADCgUJAwAAAA==.',
Ra='Radagust:BAAALgAECgQJBAAAAA==.Raenne:BAAALgAECgEJAQAAAA==.Ragebait:BAAALgADCgIJAgAAAA==.Rainfall:BAAALgAECgEJAgAAAA==.Raistlain:BAAALgAECgYJDwAAAA==.Raitha:BAAALgADCgUJCAAAAA==.Ralli:BAABLgAECn8eAAIHAAgJexalEgDXAQAHAAgJexalEgDXAQAAAA==.Rallsodins:BAAALgADCgQJBAAAAA==.Randomguy:BAABLgAECn8jAAIKAAgJDCEZAgCsAgAKAAgJDCEZAgCsAgAAAA==.Ranulf:BAAALgADCgcJEAAAAA==.Ratava:BAAALgADCgkJHQAAAA==.Ratrot:BAAALgAECgYJCwAAAA==.',
Re='Rekrella:BAAALgADCgUJBQAAAA==.Reldarus:BAEBLgAECn8XAAMhAAgJXCCZAgDbAgAhAAgJ7R+ZAgDbAgAEAAQJ+hryRAAlAQAAAA==.Rena:BAAALgADCgcJBwAAAA==.Rendia:BAAALgADCgMJAwAAAA==.Renik:BAAALgADCgIJAQAAAA==.Revennek:BAAALgAECgUJBgAAAA==.Reverence:BAAALgAECggJCAAAAA==.Revilation:BAABLgAECn8ZAAIOAAgJYBShCACFAQAOAAgJYBShCACFAQAAAA==.Rezjyk:BAAALgADCgEJAQABLgAECgYJFgAFALgaAA==.Rezzyk:BAABLgAECn8WAAIFAAYJuBp8NQBtAQAFAAYJuBp8NQBtAQAAAA==.',
Rh='Rhonus:BAAALgAECgEJAQAAAA==.Rhyxali:BAAALgAECgUJCgAAAA==.',
Ri='Riis:BAAALgAECgQJBgAAAA==.Riiselock:BAABLgAECn8kAAMJAAgJIB4QHwC6AQAJAAcJxx0QHwC6AQAIAAMJGR9SDwC6AAAAAA==.Riktade:BAAALgADCgYJBgAAAA==.Riptidepod:BAABLgAECn8YAAMZAAYJwgdDNQDjAAAZAAYJwgdDNQDjAAAYAAEJUwNYlAAhAAAAAA==.',
Ro='Robbiebrews:BAAALgADCgUJBQAAAA==.Rowin:BAAALgADCgUJBQAAAA==.',
Ry='Rynley:BAAALgAECgUJEwAAAA==.',
Sa='Sacredscales:BAABLgAECn8hAAMEAAkJrx5rCwCaAgAEAAcJ4iRrCwCaAgAfAAcJrxSCKgCGAQAAAA==.Sagerremeseb:BAAALgADCgcJDAAAAA==.Sakii:BAABLgAECn8SAAIHAAcJoQuNOQD+AAAHAAcJoQuNOQD+AAAAAA==.Samvimes:BAABLgAECn8UAAIFAAUJdAzJZQDmAAAFAAUJdAzJZQDmAAAAAA==.Sangreene:BAABLgAECn8bAAIfAAgJRhqAEwBYAgAfAAgJRhqAEwBYAgAAAA==.Sargis:BAABLgAECn8mAAMSAAgJxhvJBQCKAgASAAgJxhvJBQCKAgAFAAUJLR8eSwApAQAAAA==.Sarial:BAAALgADCgMJAwAAAA==.',
Sc='Schrödinger:BAAALgAECgYJDwAAAA==.Sciblasts:BAAALgADCgEJAQABLgADCgkJDAABAAAAAA==.Scott:BAACLgAFFH8UAAIHAAYJGiE1AgDlAQAHAAYJGiE1AgDlAQAuAAQKfy8AAgcACQlMJnQAAO4DAAcACQlMJnQAAO4DAAAA.Scratchh:BAABLgAECn8dAAIaAAgJlAswNgB0AQAaAAgJlAswNgB0AQAAAA==.',
Se='Searalsa:BAAALgAECgUJBwABLgAECggJIQAPAIQVAA==.Sentis:BAABLgAECn8UAAIWAAYJegcDJgDTAAAWAAYJegcDJgDTAAAAAA==.',
Sh='Shadowbrooks:BAAALgADCgIJAgAAAA==.Shadowgiver:BAAALgADCgcJDwAAAA==.Shadowsdemon:BAAALgADCgEJAQAAAA==.Shagol:BAAALgAECgQJBwAAAA==.Shalriss:BAABLgAECn8YAAIfAAYJZBcQFABiAQAfAAYJZBcQFABiAQAAAA==.Shamemoon:BAAALgAECgYJEAAAAA==.Shamunroe:BAABLgAECn8ZAAMZAAgJoAd4KQAmAQAZAAgJoAd4KQAmAQAYAAQJKhGiWgDZAAAAAA==.Shatterhoof:BAAALgAECgUJEAAAAA==.Shelle:BAAALgAECgEJAQAAAA==.Shiftys:BAAALgADCgUJCgABLgAECgMJBQABAAAAAA==.Shingra:BAACLgAFFH8NAAIgAAUJYhQnDQBFAQAgAAUJYhQnDQBFAQAuAAQKfxsAAiAACAntG+MPAHkCACAACAntG+MPAHkCAAAA.Shoof:BAAALgADCgUJBQAAAA==.',
Si='Sifû:BAAALgADCgcJDgAAAA==.Sigourney:BAAALgAECgEJAQAAAA==.Silversho:BAAALgADCgkJCQAAAA==.Silvoid:BAAALgADCgMJAwAAAA==.Silvren:BAAALgAECgYJEAAAAA==.Sindarion:BAAALgAECgIJAgAAAA==.Sinz:BAAALgAECgEJAwAAAA==.Siph:BAAALgAECgEJAQAAAA==.',
Sk='Skillidan:BAABLgAECn8YAAIGAAcJdxjJFQDVAQAGAAcJdxjJFQDVAQAAAA==.',
Sl='Slighttrash:BAAALgAECgYJCwAAAA==.Sloppy:BAAALgADCggJCAAAAA==.',
Sm='Smacka:BAAALgAECgEJAQAAAA==.Smallcrow:BAACLgAFFH8MAAIQAAUJVSO3AAACAgAQAAUJVSO3AAACAgAuAAQKfxUAAhAABwkuJsMHAP8CABAABwkuJsMHAP8CAAAA.Smøke:BAAALgAECgMJAwAAAA==.',
Sn='Snallygaster:BAAALgADCgYJDAABLgAECgcJGAALAIcbAA==.',
Sp='Spectrose:BAAALgADCgEJAQAAAA==.Spiro:BAAALgAECgQJBAABLgAECgkJEwABAAAAAA==.',
St='Starge:BAAALgAECgQJBgAAAA==.Steffey:BAAALgAECgUJDwAAAA==.Straven:BAAALgAECgYJCQAAAA==.Sturgeson:BAACLgAFFH8NAAICAAUJJBYZBgAmAQACAAUJJBYZBgAmAQAuAAQKfxwAAgIACAmSHwQMAEsCAAIACAmSHwQMAEsCAAAA.',
Su='Sulwen:BAABLgAECn8eAAIEAAgJghiHCwDsAQAEAAgJghiHCwDsAQAAAA==.',
Sw='Sweetpotato:BAAALgADCgEJAQAAAA==.Swiftfeet:BAABLgAECn8XAAIeAAcJARVrJQCEAQAeAAcJARVrJQCEAQAAAA==.',
Sy='Syrasia:BAAALgADCgUJBQAAAA==.Syselea:BAAALgADCgEJAQAAAA==.',
['Sö']='Söranin:BAAALgAECgUJCgAAAA==.',
Ta='Tachichan:BAAALgAECgYJBgAAAA==.Tadum:BAAALgADCgEJAQAAAA==.Taeili:BAABLgAECn8UAAIWAAgJyhVaNgBiAQAWAAgJyhVaNgBiAQAAAA==.Talisse:BAAALgADCgYJBgAAAA==.Tanequil:BAABLgAECn8iAAIGAAgJrAzUSgB4AQAGAAgJrAzUSgB4AQAAAA==.Targaryian:BAAALgAECgMJAwAAAA==.Taylea:BAAALgAECgUJCgAAAA==.',
Te='Techromancer:BAAALgAECgQJBAABLgAECgQJCwABAAAAAA==.Tenumbras:BAAALgAECgYJDAAAAA==.Termonda:BAAALgAECgEJAQAAAA==.Terraclaw:BAAALgADCgUJBwAAAA==.Terrasia:BAAALgADCgYJBgAAAA==.Terrigino:BAAALgADCgMJAwAAAA==.',
Th='Thanatias:BAAALgAECgYJDAAAAA==.Thantasia:BAAALgAECgUJCQAAAA==.Thauras:BAAALgADCgcJDgAAAA==.Thom:BAACLgAFFH8FAAIdAAMJrBDgAgD8AAAdAAMJrBDgAgD8AAAuAAQKfykAAx0ACAl1I6UAAJgCAB0ACAl1I6UAAJgCABQABgmoDjaxACABAAAA.Thør:BAAALgADCgcJDgAAAA==.',
Ti='Tifà:BAAALgAECgMJAwAAAA==.Timothy:BAAALgAECgYJDwAAAA==.Tinkphooey:BAAALgAECgYJCwAAAA==.Tinton:BAAALgADCgEJAQAAAA==.',
To='Tormmok:BAAALgAECgYJCgAAAA==.Toshindo:BAAALgADCgQJBAAAAA==.',
Tr='Tremèndor:BAAALgADCgMJAwAAAA==.Tristra:BAAALgAECgQJBAAAAA==.',
Ts='Tsuruga:BAABLgAECn8eAAIaAAgJRg5qEACOAQAaAAgJRg5qEACOAQAAAA==.',
Tu='Turkwise:BAABLgAECn8aAAMLAAgJRhaqBgCMAQALAAcJCxmqBgCMAQAVAAQJCBGqHgDuAAAAAA==.',
Ty='Tycondrius:BAAALgAECgEJAQAAAA==.Tyresh:BAAALgAECgEJAQAAAA==.Tyrinor:BAAALgADCgUJBQAAAA==.',
Ul='Ulogasm:BAAALgADCggJCAAAAA==.',
Ut='Utako:BAAALgADCgUJCgAAAA==.',
Uv='Uvari:BAAALgAECgEJAQAAAA==.',
Va='Valhalaa:BAAALgADCgYJBgAAAA==.Valton:BAACLgAFFH8GAAIQAAMJaR6sBgAtAQAQAAMJaR6sBgAtAQAuAAQKfyoAAhAACAmTJL8BANsCABAACAmTJL8BANsCAAAA.Vanillanice:BAAALgAECgIJAgAAAA==.Varrfife:BAAALgAECgMJAwAAAA==.Vaxaldan:BAABLgAECn8eAAIMAAgJvA6IDQA3AQAMAAgJvA6IDQA3AQAAAA==.',
Ve='Velithera:BAAALgADCgMJAwAAAA==.Vellithe:BAAALgAECgYJDwAAAA==.Venj:BAAALgAECgUJBgAAAA==.Verhmax:BAAALgADCgYJCwAAAA==.Vestrae:BAACLgAFFH8FAAIGAAMJygUhHwCoAAAGAAMJygUhHwCoAAAuAAQKfyQAAgYACAl/HnITAJoCAAYACAl/HnITAJoCAAAA.Vex:BAAALgAECgUJDQAAAA==.',
Vi='Vianel:BAAALgADCggJCAAAAA==.Vilten:BAAALgAECgQJCwAAAA==.',
Vo='Vodash:BAAALgAECgYJDQABLgAECgcJGAAGALQPAA==.Vostok:BAAALgAECgcJEwAAAA==.',
Wa='Wage:BAAALgADCgQJBQAAAA==.Warmth:BAAALgADCgIJAwAAAA==.',
We='Weekend:BAAALgADCgkJDwAAAA==.Wetsock:BAAALgAECgYJBwAAAA==.',
Wi='Wikket:BAABLgAECn8eAAIWAAgJzxbnCwDQAQAWAAgJzxbnCwDQAQAAAA==.',
Wy='Wynono:BAAALgADCgcJBwAAAA==.',
Xd='Xdeadlysinz:BAAALgAECgYJBgAAAA==.',
Xo='Xotha:BAABLgAECn8fAAIHAAcJtR3/DgD8AQAHAAcJtR3/DgD8AQAAAA==.',
Xy='Xythera:BAABLgAECn8YAAIHAAgJUSL3FQDTAgAHAAgJUSL3FQDTAgAAAA==.',
Ye='Yeah:BAAALgADCgYJBgABLgAECgkJIgAOAA4hAA==.',
Yi='Yinosai:BAAALgADCgQJBAAAAA==.',
Yo='Yougot:BAAALgADCgcJCgAAAA==.',
Yu='Yuji:BAABLgAECn8cAAIIAAYJZx1kAwC7AQAIAAYJZx1kAwC7AQAAAA==.Yukì:BAAALgADCgMJAwAAAA==.Yurie:BAAALgAECgIJAgAAAA==.',
Yv='Yvonna:BAAALgADCgEJAQAAAA==.',
Za='Zaega:BAAALgADCgQJBAABLgAECgcJGQAFAHkeAA==.Zahlee:BAAALgAECgQJBAAAAA==.Zanka:BAAALgADCgMJAwAAAA==.Zaridruid:BAAALgAECgcJBAAAAA==.Zarisedra:BAACLgAFFH8NAAMSAAUJvhBzBgCKAQASAAUJvhBzBgCKAQAFAAEJXgDUOwA2AAAuAAQKfxcAAxIACAlsGMkpAOMBABIABwmNGckpAOMBAAUAAQktBuw9ATUAAAAA.Zarissena:BAAALgAECgMJAwAAAA==.Zarris:BAAALgADCgUJDAAAAA==.',
Ze='Zennith:BAAALgADCgMJAwAAAA==.Zernacho:BAABLgAECn8UAAMfAAcJsRE+LgBvAQAfAAYJ4xE+LgBvAQAEAAQJfRyUFgBZAQAAAA==.Zerogasm:BAAALgAECgUJBQAAAA==.Zerolicious:BAAALgADCgUJBgAAAA==.Zerozaddy:BAAALgAECgUJBgAAAA==.Zevvo:BAABLgAECn8dAAIDAAgJVh1TBQBmAgADAAgJVh1TBQBmAgAAAA==.',
Zo='Zoraji:BAABLgAECn8mAAIaAAgJ6BhoBwAiAgAaAAgJ6BhoBwAiAgAAAA==.',
Zu='Zuganova:BAABLgAFFH8NAAMhAAUJtQehCQBsAQAhAAUJFAehCQBsAQAEAAEJ8whsFgA8AAAAAA==.Zuggar:BAABLgAECn8XAAIDAAYJSwYQKQD9AAADAAYJSwYQKQD9AAAAAA==.',
Zy='Zynhammer:BAABLgAECn8kAAMHAAgJBRGXNgAIAQAHAAgJBRGXNgAIAQANAAEJbwYANQAwAAAAAA==.',
['Év']='Évangeline:BAAALgADCgcJBwAAAA==.',
['Ëd']='Ëdën:BAAALgAECgYJBgAAAA==.',
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

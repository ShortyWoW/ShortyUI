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

local lookup = {'Hunter-BeastMastery','Druid-Guardian','Unknown-Unknown','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','Paladin-Protection','DemonHunter-Devourer','Warrior-Fury','DeathKnight-Frost','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','Shaman-Elemental','Paladin-Holy','Druid-Feral','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Mage-Arcane','Monk-Brewmaster','Hunter-Survival','Druid-Balance',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abberleigh:BAAALgAECgIJAgAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAAALgAECgEJAQABLgAECgcJHgABAE0bAA==.Alarlia:BAABLgAECn8XAAICAAcJYwtTGADzAAACAAcJYwtTGADzAAAAAA==.Algonq:BAAALgADCgUJBQABLgAECgUJDQADAAAAAA==.Alliesofevil:BAAALgAECgQJCwAAAA==.Allsar:BAAALgAECgMJBQABLgAECggJFgAEAOsUAA==.Alsar:BAAALgAECgEJAQABLgAECggJFgAEAOsUAA==.Alsisst:BAAALgADCgQJBAAAAA==.',
Am='Amathushhg:BAABLgAECn8pAAQFAAgJ7ROiGwBwAQAFAAYJ9g2iGwBwAQAGAAYJlxfNFgBaAQAHAAEJaQdYMgA5AAAAAA==.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECgUJCgAAAA==.Andreth:BAAALgAECgIJAgAAAA==.Anthe:BAAALgADCgcJDwAAAA==.Anzul:BAABLgAECn8fAAIIAAcJriHaJACUAgAIAAcJriHaJACUAgAAAA==.',
Ar='Araestirra:BAAALgAECgQJBgAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAECggJJAAGADcOAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8WAAIEAAgJ6xSXCwCjAQAEAAgJ6xSXCwCjAQAAAA==.Arroes:BAAALgAECgYJEQAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgADCgEJAQAAAA==.',
Ay='Ayroona:BAABLgAECn8YAAIJAAcJCAmzVQAvAQAJAAcJCAmzVQAvAQAAAA==.',
Az='Azhol:BAAALgAECgMJAwAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAABLgAECn8jAAIKAAgJwhSNBACGAQAKAAgJwhSNBACGAQAAAA==.Barbaydos:BAAALgADCggJCgAAAA==.Basement:BAAALgAECgUJDwAAAA==.',
Be='Beastnite:BAAALgADCgcJCQAAAA==.Bellaburger:BAAALgAECgMJAwAAAA==.Bellissidan:BAAALgAECgEJAgAAAA==.Benedin:BAAALgAECgEJAQABLgAECggJGAAGAMoVAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAAALgAECgUJDQAAAA==.Biped:BAAALgAECgUJDwAAAA==.',
Bl='Blackdeath:BAABLgAECn8cAAILAAgJjhJUYgDMAQALAAgJjhJUYgDMAQAAAA==.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAAALgAECgUJDQAAAA==.Boondocka:BAAALgAECgQJBQAAAA==.',
Br='Brewco:BAABLgAECn8gAAMMAAgJ4R2qFACQAgAMAAgJ4R2qFACQAgACAAEJ6AcXDwAoAAAAAA==.Bruda:BAAALgAECgIJAgAAAA==.Brutalís:BAAALgAECgUJCAABLgAECgYJBwADAAAAAA==.',
Bt='Btrain:BAAALgAECgUJCAAAAA==.',
['Bó']='Bóunty:BAAALgAECgYJEwAAAA==.',
Ca='Canadia:BAAALgADCggJDwAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cavisch:BAABLgAECn8YAAMGAAgJyhVCPAAcAgAGAAgJyhVCPAAcAgAHAAIJGA4CHACTAAAAAA==.',
Ce='Cenobité:BAAALgAECgkJCwAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgADCgcJDQABLgAECgUJDwADAAAAAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAINAAMJlBUeDQAVAQANAAMJlBUeDQAVAQAAAA==.Charmeleon:BAAALgAECggJCgAAAA==.Charmin:BAAALgADCgUJBQAAAA==.',
Ci='Cirax:BAAALgAECgUJDQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgADCgEJAQAAAA==.',
Cl='Clenton:BAABLgAECn8hAAIOAAgJ/gRBIQD9AAAOAAgJ/gRBIQD9AAAAAA==.',
Co='Cobrakai:BAAALgADCgYJCgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAABLgAECn8kAAIPAAgJsCCRAwBmAgAPAAgJsCCRAwBmAgAAAA==.Cronnan:BAAALgADCgkJFwAAAA==.Crowford:BAAALgAECgYJCwAAAA==.',
Cy='Cyris:BAAALgADCgYJDwABLgAECgUJDQADAAAAAA==.',
Da='Daemonfaust:BAAALgAECgQJBwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dak:BAAALgAECgQJBAAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgUJDQADAAAAAA==.Darkmiza:BAABLgAECn8kAAMGAAgJNw5+EQCEAQAGAAgJNw5+EQCEAQAFAAIJQws5WABmAAAAAA==.Darkseer:BAAALgAECgQJBwAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAAALgAECgYJDgAAAA==.',
De='Deadmangalad:BAAALgAECgUJDQAAAA==.Deedees:BAAALgAECgMJBAAAAA==.Demonbo:BAAALgAECgcJEQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCgcJDQAAAA==.Deo:BAABLgAECn8jAAIQAAgJLSFTDAD2AgAQAAgJLSFTDAD2AgAAAA==.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8cAAIBAAgJ/BY0CADlAQABAAgJ/BY0CADlAQAAAA==.Dethphalanax:BAAALgADCgQJBAAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgADCggJFAAAAA==.Diskbänk:BAAALgAECgEJAgAAAA==.',
Dk='Dkho:BAAALgAECgcJEwAAAA==.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Dragontoast:BAAALgAECgIJAgAAAA==.Dral:BAEALgADCgkJIgAAAA==.Drphilyobody:BAAALgAECgQJCQAAAA==.Drui:BAAALgAECgcJEwAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAAALgAECgYJCwAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAAALgAECgYJBgAAAA==.Eatmyfrontal:BAAALgAECgYJEAAAAA==.',
Eb='Ebbola:BAAALgADCgcJDQAAAA==.Ebon:BAAALgAECgIJAgAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
Ep='Epikrate:BAAALgAECgYJEQAAAA==.',
Es='Escaper:BAABLgAECn8VAAIRAAYJAwzJAwAEAQARAAYJAwzJAwAEAQAAAA==.',
Ex='Extrema:BAAALgAECgIJAgAAAA==.',
Ez='Ezsdemon:BAAALgAECgkJAgAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAECggJIgASAFAkAA==.Fallenembers:BAABLgAECn8iAAISAAgJUCRJAgC9AgASAAgJUCRJAgC9AgAAAA==.Famine:BAABLgAECn8VAAMLAAYJ9QZHKgDjAAALAAYJWwVHKgDjAAARAAUJzAf5DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQAAAA==.',
Fh='Fhait:BAAALgADCggJGwABLgAECgUJDQADAAAAAA==.',
Fi='Firsttimepvp:BAAALgAECggJEwAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgADCgYJBgAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.',
Gh='Ghosty:BAABLgAECn8ZAAQTAAgJshPjCABRAQATAAcJQA/jCABRAQAUAAcJoQt1TgD+AAAVAAEJegEuJAAdAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAECgcJFQAFAAgfAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtoof:BAAALgAECgMJAwAAAA==.Goldtusk:BAAALgAECgYJDwAAAA==.Gooey:BAAALgADCggJDQAAAA==.Gostann:BAAALgAECgEJAQAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Gryphone:BAAALgADCgkJDQAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAQAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgADCgUJBQABLgAECgUJDQADAAAAAA==.',
Ha='Hakmud:BAAALgADCgUJBQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Hercyderc:BAAALgAECgEJAQABLgAECggJKAAPAPIkAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAAALgAECgUJCwAAAA==.Hondojoe:BAABLgAECn8kAAMUAAgJ5SFOCwCbAgAUAAgJ5SFOCwCbAgATAAIJ1AbAFABZAAAAAA==.Hopewell:BAAALgAECgUJDQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAAALgAECgUJDQABLgAECgUJDQADAAAAAA==.Huhu:BAABLgAECn8WAAIQAAgJEhX/BQDHAQAQAAgJEhX/BQDHAQAAAA==.Huma:BAAALgAECgYJEAAAAA==.',
Ib='Ibn:BAAALgAECgUJCwAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
In='Infectus:BAAALgAECgkJBAAAAA==.Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgADCggJGQAAAA==.',
Is='Ishanllin:BAAALgADCgUJBQAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8WAAIPAAcJYRMKFQBVAQAPAAcJYRMKFQBVAQAAAA==.Ivylyn:BAAALgADCgYJDAAAAA==.',
Ix='Ixiyá:BAAALgAECgcJEwAAAA==.Ixì:BAAALgAECgUJCAAAAA==.',
Ja='Jakeyprogue:BAAALgADCgEJAQABLgAECgcJAQADAAAAAA==.Jakota:BAAALgADCgcJCgAAAA==.Jakskeleton:BAAALgAECgQJCQAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgUJCAAAAA==.',
Jo='Joemacho:BAAALgADCgEJAQABLgAECggJJAAUAOUhAA==.Joslyn:BAAALgADCgQJBgAAAA==.',
Ju='Judax:BAABLgAECn8dAAIWAAgJGhNiCAB5AQAWAAgJGhNiCAB5AQAAAA==.Justagirl:BAAALgAECgUJDQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.',
Ka='Kadooka:BAABLgAECn8UAAIBAAYJ7BVAVQBpAQABAAYJ7BVAVQBpAQAAAA==.Kahlyn:BAAALgADCgYJBgAAAA==.Kajax:BAABLgAECn8kAAINAAgJFiMtCAANAwANAAgJFiMtCAANAwAAAA==.Kaldaran:BAAALgAECgYJCAAAAA==.Karen:BAAALgADCgcJCgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAAALgAECgUJEgAAAA==.Keelay:BAABLgAECn8XAAIXAAYJ3xOqDgBUAQAXAAYJ3xOqDgBUAQAAAA==.',
Kh='Kheegorn:BAABLgAECn8VAAIIAAgJ2hRxTwDzAQAIAAgJ2hRxTwDzAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwADAAAAAA==.',
Ko='Koffcmorbius:BAAALgADCgYJDAAAAA==.Koriban:BAAALgAECggJEQAAAA==.Korreban:BAAALgAECgYJBgABLgAECggJEQADAAAAAA==.',
Kr='Kraken:BAABLgAECn8VAAIFAAcJCB83BQCGAgAFAAcJCB83BQCGAgAAAA==.',
Ku='Kubb:BAAALgAECgUJDQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAABLgAECn8gAAIYAAgJOCIZBQDAAgAYAAgJOCIZBQDAAgAAAA==.',
['Kê']='Kêlsen:BAAALgADCgcJEgAAAA==.',
La='Lachupacabra:BAAALgADCgIJBAAAAA==.Larrissa:BAAALgAECgUJDQAAAA==.Larry:BAAALgADCgYJBgABLgAECggJHAAWAAohAA==.Laurlynn:BAAALgADCgcJEAAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lettuceprey:BAAALgAECgUJDAAAAA==.',
Li='Lies:BAAALgADCgkJCQAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.',
Lo='Lockatute:BAAALgAECgMJBQAAAA==.Lockdeath:BAAALgADCgMJAwAAAA==.Loxia:BAAALgAECgQJBgAAAA==.',
Lu='Lucille:BAAALgAECgcJDwAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAAALgAECgUJCgAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Magicdance:BAABLgAECn8YAAMJAAgJpgjWXAAXAQAJAAcJ8wTWXAAXAQAWAAcJ7AizTwAIAQAAAA==.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIYAAgJchK+CwACAgAYAAgJchK+CwACAgAAAA==.Majicbob:BAAALgAECgQJBAAAAA==.Maki:BAAALgAECgYJCwAAAA==.Mansion:BAAALgADCgMJBAABLgAECgUJDwADAAAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgADCgUJBQAAAA==.',
Mc='Mctowlie:BAAALgAECgEJAQAAAA==.',
Me='Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAAALgAECgcJEAAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAECggJGAAJAKYIAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAABLgAECn8kAAIZAAgJxCRdAADuAgAZAAgJxCRdAADuAgAAAA==.Misstreater:BAAALgAECgYJBgAAAA==.',
Mo='Momentomori:BAAALgAECgcJEgAAAA==.Morishima:BAABLgAECn8kAAINAAgJfCHaAACRAgANAAgJfCHaAACRAgAAAA==.Morthis:BAAALgAECgUJDAAAAA==.',
My='Mydarling:BAAALgAECggJEQAAAA==.Myris:BAAALgAECgcJEwAAAA==.',
Na='Naturalchi:BAAALgAECgUJEQAAAA==.',
Ne='Nefilion:BAAALgAECgMJAwAAAA==.Nemas:BAAALgAECgYJCgAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAAALgAECgUJBwAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nineadin:BAABLgAECn8gAAIXAAgJgxySAgBuAgAXAAgJgxySAgBuAgAAAA==.Nirvanas:BAAALgAECgUJCAAAAA==.',
No='Nomik:BAABLgAECn8WAAMUAAYJ4gNnWADTAAAUAAYJ4gNnWADTAAAVAAQJmQZQSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.',
Nu='Nuke:BAAALgAECgQJCQAAAA==.Nullspace:BAAALgAECgcJDQAAAA==.',
Ny='Nyxe:BAAALgADCgkJCQAAAA==.',
['Ní']='Níght:BAABLgAECn8gAAICAAYJcBYjEgBRAQACAAYJcBYjEgBRAQAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Om='Ommû:BAAALgAECgIJAgAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAECgcJFQAFAAgfAA==.',
Pa='Pakeydk:BAAALgAECgcJAQAAAA==.Pancakedealr:BAAALgAECgUJCAAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Peí:BAAALgADCgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAAALgAECgcJEgAAAA==.',
Pr='Preachêr:BAAALgADCgMJAwABLgAECgUJDQADAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8WAAIUAAYJuQ7aPQBCAQAUAAYJuQ7aPQBCAQAAAA==.',
Qu='Quelaag:BAAALgADCgQJBAAAAA==.Quiescent:BAAALgAECgUJEQAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAAALgAECgUJDAABLgAFFAMJCAAEAH8mAA==.Ramanas:BAAALgAECgUJCgAAAA==.Randomizwe:BAABLgAECn8bAAIIAAcJtBlEEACjAQAIAAcJtBlEEACjAQAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAQAAAA==.Raín:BAAALgADCgkJFwAAAA==.',
Re='Relearning:BAAALgAECgUJCAAAAA==.Resurgencê:BAAALgAECgUJDQAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAAALgAECgQJCwAAAA==.Rivfader:BAAALgAECgIJAgAAAA==.',
Ro='Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCgcJBwAAAA==.Rotandroll:BAAALgAECgYJBgAAAA==.Rothema:BAAALgAECgUJCgAAAA==.',
Rw='Rwlmaster:BAAALgAECgUJCgAAAA==.',
Ry='Rynzia:BAABLgAECn8kAAMaAAgJ3iCjAQBcAgAaAAgJ3iCjAQBcAgAbAAcJpBTpFgCFAQAAAA==.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgIJAgAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAAALgAECgcJEAAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgcJHgABAE0bAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgIJAgAAAA==.Seta:BAABLgAECn8hAAIPAAgJzhV2CQDbAQAPAAgJzhV2CQDbAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAECgcJAQADAAAAAA==.Shamarha:BAAALgAECgYJDAAAAA==.Sharriavolf:BAABLgAECn8nAAQGAAgJwh8XEwB3AQAGAAYJDB0XEwB3AQAFAAQJxCAKIABSAQAHAAEJAAB4IwBkAAAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shortmedic:BAAALgADCggJCwAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAADAAAAAA==.Siggismund:BAAALgAECgcJDwAAAA==.Simichaelton:BAAALgAECgYJDQABLgAECggJHQAZAA0YAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slimselect:BAAALgADCgMJAwAAAA==.',
So='Softbakedhoj:BAABLgAECn8XAAIIAAcJaRhiSQAGAgAIAAcJaRhiSQAGAgAAAA==.',
Sp='Spartaaxd:BAABLgAECn8WAAIRAAcJuhKYBwCBAQARAAcJuhKYBwCBAQAAAA==.Spookems:BAAALgAECgIJAgABLgAECggJDwADAAAAAA==.Spycy:BAAALgAECgYJCgAAAA==.',
St='Stagerrind:BAAALgADCgQJBAAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8ZAAIXAAgJjAu7DABzAQAXAAgJjAu7DABzAQAAAA==.Stinkyfrog:BAAALgAECgYJDgAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECgUJDQADAAAAAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8eAAISAAgJvAtLIABUAQASAAgJvAtLIABUAQAAAA==.Suka:BAAALgADCgcJDAAAAA==.Surok:BAAALgAECgMJBAAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgMJBQAAAA==.',
Sy='Sylentcurse:BAAALgAECgYJBwAAAA==.Sylentstorm:BAAALgAECgIJAgABLgAECgYJBwADAAAAAA==.Syleta:BAABLgAECn8eAAMBAAcJTRsOMADwAQABAAcJTRsOMADwAQAcAAYJCRM6RABEAQAAAA==.',
Ta='Tagalorc:BAAALgAECgYJCwAAAA==.Takamaki:BAAALgADCggJGAAAAA==.Tanksbacon:BAAALgAECgUJDQAAAA==.Taylith:BAAALgAECgUJBQAAAA==.',
Te='Teana:BAAALgAECgMJBAAAAA==.Tempestas:BAAALgADCgUJCAAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAECggJIAAMAOEdAA==.Thelegendáry:BAABLgAECn8VAAIJAAYJ+xQ/SgBZAQAJAAYJ+xQ/SgBZAQAAAA==.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgEJAQAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAAALgAECgUJCAAAAA==.',
To='Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAAALgAECgcJDQAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Trisstan:BAAALgAECgUJDQAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8XAAMdAAcJXh0HBgDAAQAdAAUJHyAHBgDAAQASAAQJlQ28SQCPAAAAAA==.Tyster:BAAALgAECggJDgAAAA==.',
Uk='Ukyo:BAAALgADCgMJBAAAAA==.',
Ul='Ullidon:BAAALgADCgEJAQAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Undol:BAAALgADCggJCwABLgAECgUJDQADAAAAAA==.',
Uz='Uzu:BAABLgAECn8dAAIeAAcJDho5IwDpAQAeAAcJDho5IwDpAQAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Vamp:BAAALgAECgcJEwAAAA==.Vandaldor:BAAALgAECgQJBAAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAABLgAECn8gAAISAAgJtR5zCAAhAgASAAgJtR5zCAAhAgAAAA==.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8WAAMBAAgJthWcLQD8AQABAAgJthWcLQD8AQAfAAIJewThKgBVAAAAAA==.',
Wa='Wanghaf:BAAALgAECgUJDAAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgYJDwADAAAAAA==.Warthog:BAAALgADCgUJBQAAAA==.Waterbender:BAAALgAECggJDQAAAA==.',
We='Weechuup:BAAALgADCgcJDwAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAAALgAECgQJCQAAAA==.Wilshaman:BAAALgADCgcJDQAAAA==.Window:BAAALgADCgQJBAABLgAECgUJDwADAAAAAA==.',
Wo='Wolf:BAABLgAECn8WAAICAAcJAxj7CwDMAQACAAcJAxj7CwDMAQAAAA==.Wolfton:BAAALgADCgQJBAAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMBAAgJIhvDHQBTAgABAAgJIhvDHQBTAgAcAAMJrAI+dABtAAAAAA==.Xanæ:BAAALgADCgQJBwAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAAALgAECgQJCQAAAA==.',
Xy='Xyro:BAAALgAECgUJBQAAAA==.',
Ya='Yamato:BAAALgAECgEJAQAAAA==.',
Za='Zaledron:BAAALgAECgYJDQAAAA==.Zapnasty:BAAALgADCgcJBwAAAA==.',
Ze='Zenno:BAAALgAECgUJCgAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAABLgAECn8fAAILAAgJDiIJAwB5AgALAAgJDiIJAwB5AgAAAA==.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAgAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAADAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.',
Zp='Zpersephone:BAAALgAECgIJAgABLgAECggJHwALAA4iAA==.',
Zu='Zultan:BAABLgAECn8YAAMGAAgJMxDzCwC6AQAGAAcJMxDzCwC6AQAFAAEJAADhewAlAAAAAA==.Zurrik:BAABLgAECn8gAAIgAAgJYxCjBgCYAQAgAAgJYxCjBgCYAQAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAABLgAECn8nAAMeAAgJhB88CQD1AgAeAAgJhB88CQD1AgAZAAMJGxkcHQBEAAAAAA==.',
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

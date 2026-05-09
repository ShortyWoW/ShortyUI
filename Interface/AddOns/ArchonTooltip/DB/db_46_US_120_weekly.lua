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

local lookup = {'Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Shaman-Enhancement','Druid-Balance','Priest-Shadow','Mage-Frost','Monk-Windwalker','Priest-Discipline','Priest-Holy','Druid-Feral','Warrior-Arms','Shaman-Elemental','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Evoker-Augmentation','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abberleigh:BAAALgAECgMJBQAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgADCgcJBwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAAALgAECgMJCAABLgAECggJNAABADceAA==.Alarlia:BAABLgAECn8hAAICAAgJvgvuEAD4AAACAAgJvgvuEAD4AAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgADCggJFAABLgAECgYJGQADAOMFAA==.Alliesofevil:BAABLgAECn8ZAAIEAAgJLQuHHwBvAQAEAAgJLQuHHwBvAQAAAA==.Allsar:BAABLgAECn8VAAICAAkJsBulAgCDAgACAAkJsBulAgCDAgAAAA==.Alsar:BAAALgAECgQJBAABLgAECgkJFQACALAbAA==.Alssar:BAAALgAECgQJBAAAAA==.',
Am='Amathushhg:BAABLgAECn8+AAQFAAkJFRe+BQCdAQAGAAkJ6RLrIADrAQAFAAcJ9ha+BQCdAQAHAAIJ+gtnFwA7AAAAAA==.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECgUJCgAAAA==.Andreth:BAAALgAECgMJCAAAAA==.Anoxyn:BAAALgADCgEJAQAAAA==.Anthe:BAAALgADCggJEwAAAA==.Anzul:BAABLgAECn8rAAIIAAkJPB5YDACfAgAIAAkJPB5YDACfAgAAAA==.',
Ar='Araestirra:BAAALgAECgQJCQAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAMJBwAGABIBAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8WAAIJAAgJ6hSYCwCjAQAJAAgJ6hSYCwCjAQABLgAECgkJFQACALAbAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8YAAIKAAcJ6B75DAAaAgAKAAcJ6B75DAAaAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgADCggJCQAAAA==.',
Ay='Ayroona:BAABLgAECn8gAAILAAcJkgltPgAKAQALAAcJkgltPgAKAQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8KAAIMAAMJdRPQEgDKAAAMAAMJdRPQEgDKAAAuAAQKfygAAgwACAmKFzINAJ8BAAwACAmKFzINAJ8BAAAA.Barbaydos:BAAALgADCggJCQAAAA==.Basement:BAABLgAECn8UAAINAAcJ/hueJQCoAQANAAcJ/hueJQCoAQAAAA==.',
Be='Beastnite:BAAALgADCggJFQABLgAECgIJAgAOAAAAAA==.Bellaburger:BAAALgAFFAQJBAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgEJAQABLgAECgkJKQAGAI8XAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn8ZAAIEAAYJKQX1OgDXAAAEAAYJKQX1OgDXAAAAAA==.Biped:BAABLgAECn8dAAIHAAcJ9g/WBQBiAQAHAAcJ9g/WBQBiAQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIPAAIJSgnnfgCTAAAPAAIJSgnnfgCTAAAuAAQKfyEAAg8ACAlRFUliAMwBAA8ACAlRFUliAMwBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAABLgAECn8ZAAIQAAYJoxe1PgBTAQAQAAYJoxe1PgBTAQAAAA==.Boondocka:BAAALgAECgQJCAAAAA==.',
Br='Brewco:BAACLgAFFH8GAAIRAAMJqRgLLQCVAAARAAMJqRgLLQCVAAAuAAQKfykAAxEACAmbHqYUAJACABEACAmbHqYUAJACAAIABQl5DxcVAMEAAAAA.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8WAAIQAAcJzg60PgBTAQAQAAcJzg60PgBTAQAAAA==.',
Bt='Btrain:BAAALgAECgUJEQAAAA==.',
['Bó']='Bóunty:BAABLgAECn8WAAQBAAcJwx8mFAB2AQABAAcJ+RwmFAB2AQAQAAQJNx5GXgBNAQASAAEJPgJomAAeAAAAAA==.',
Ca='Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cavisch:BAABLgAECn8pAAMGAAkJjxeGHAAFAgAGAAkJjxeGHAAFAgAHAAIJGA4CHACTAAAAAA==.',
Ce='Cenobité:BAABLgAECn8XAAITAAgJEQyBCAAaAQATAAgJEQyBCAAaAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgEJAQABLgAECgcJFAANAP4bAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIUAAMJlBUhDQAVAQAUAAMJlBUhDQAVAQAAAA==.Charmeleon:BAAALgAECggJCgAAAA==.Charmin:BAAALgADCgUJBQAAAA==.',
Ci='Cirax:BAABLgAECn8VAAIQAAUJ5xWEXAD6AAAQAAUJ5xWEXAD6AAAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Clenton:BAABLgAECn8yAAIVAAkJ0AWkEwAMAQAVAAkJ0AWkEwAMAQAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8IAAINAAMJWBt/KwAEAQANAAMJWBt/KwAEAQAuAAQKfyYAAg0ACAlCIRsiAIQCAA0ACAlCIRsiAIQCAAAA.Cronnan:BAAALgAECgMJAwAAAA==.Crowford:BAABLgAECn8fAAIQAAcJiBBmOABrAQAQAAcJiBBmOABrAQAAAA==.',
Cy='Cyris:BAAALgADCgkJIwABLgAECgYJGQAWAPEBAA==.',
Da='Daemonfaust:BAAALgAECgQJBwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dak:BAAALgAECggJEQAAAA==.Dalsar:BAAALgADCgcJBwAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgYJGQAVAFYgAA==.Darkmiza:BAACLgAFFH8HAAIGAAMJEgEAXwCQAAAGAAMJEgEAXwCQAAAuAAQKfzQAAwYACAl1EXEuAKkBAAYACAl1EXEuAKkBAAUAAglDC0JYAGYAAAAA.Darkseer:BAAALgAECgQJCgAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8UAAIIAAYJBBbicQCYAQAIAAYJBBbicQCYAQAAAA==.',
De='Deadmangalad:BAAALgAECgYJEwAAAA==.Deedees:BAAALgAECgYJCgAAAA==.Demonbo:BAABLgAECn8UAAINAAcJgxOpYAB/AQANAAcJgxOpYAB/AQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8JAAIEAAMJcRerFwDzAAAEAAMJcRerFwDzAAAuAAQKfygAAgQACAl+I5QHAHMCAAQACAl+I5QHAHMCAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8iAAMQAAgJqReXIQDTAQAQAAgJqReXIQDTAQABAAUJYQshIQD1AAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgADCgkJIgAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAAALgAFFAMJAwAAAA==.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgMJCAAAAA==.Dral:BAEALgADCgkJKAAAAA==.Drphilyobody:BAAALgAECgYJDwAAAA==.Drui:BAABLgAECn8WAAIXAAcJMA8VNgBkAQAXAAcJMA8VNgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAABLgAECn8UAAIYAAYJbgYGMQDOAAAYAAYJbgYGMQDOAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAAALgAECgcJEQAAAA==.Eatmyfrontal:BAABLgAECn8oAAIZAAcJ1RCiUgBzAQAZAAcJ1RCiUgBzAQAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgIJAgABLgAECgMJBgAOAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgADCgcJCQAAAA==.',
Ep='Epikrate:BAABLgAECn8dAAMGAAcJUBmKJwDJAQAGAAYJGBmKJwDJAQAFAAMJ4hilSACUAAAAAA==.',
Es='Escaper:BAABLgAECn8oAAITAAgJtBDuBACPAQATAAgJtBDuBACPAQAAAA==.',
Ex='Extrema:BAAALgAECgMJCAAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAMJCgAZAGIcAA==.Fallenembers:BAACLgAFFH8KAAIZAAMJYhzTPAAbAQAZAAMJYhzTPAAbAQAuAAQKfysAAhkACAkzJQ0LAMoCABkACAkzJQ0LAMoCAAAA.Famine:BAABLgAECn8dAAMPAAgJzwXvXQApAQAPAAgJwwTvXQApAQATAAUJzAf6DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQAAAA==.',
Fh='Fhait:BAAALgADCggJLAABLgAECgYJGQAaABwJAA==.',
Fi='Firsttimepvp:BAABLgAECn8VAAIUAAgJLgmLKwCiAQAUAAgJLgmLKwCiAQAAAA==.',
Fl='Flinnw:BAAALgADCgYJBwAAAA==.Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgMJAwAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgADCggJCAAAAA==.Gaskelmarg:BAAALgADCggJDwAAAA==.',
Gh='Ghosty:BAABLgAECn8gAAQbAAgJlhQ/EwCrAQAbAAgJuBA/EwCrAQAcAAcJpAuETgD+AAAYAAEJcAFoXAAcAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAECgcJGAAFAMsfAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8XAAIdAAgJKxBlCQCRAQAdAAgJKxBlCQCRAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAAALgAECgcJDwAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Gryphone:BAAALgADCgkJDQAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAQAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgADCggJDQABLgAECgYJGQAVAFYgAA==.',
Ha='Hakmud:BAAALgADCgUJBQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hercyderc:BAAALgAECgEJAQABLgAECgkJLQANANMjAA==.Hettokal:BAAALgADCgcJBwAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8TAAINAAcJkQ5IQAA4AQANAAcJkQ5IQAA4AQAAAA==.Hondojoe:BAACLgAFFH8JAAIcAAMJPhjxDgDhAAAcAAMJPhjxDgDhAAAuAAQKfywAAxwACAmgIkwLAJsCABwACAmgIkwLAJsCABsAAgnYBoU+AFIAAAAA.Honeydrake:BAAALgADCgYJBgAAAA==.Hopewell:BAABLgAECn8ZAAIDAAYJ4wWeNQD0AAADAAYJ4wWeNQD0AAAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8ZAAIJAAYJrQn2EACyAAAJAAYJrQn2EACyAAABLgAECgYJGQAaABwJAA==.Huhu:BAABLgAECn8ZAAIEAAkJrxRoDwD9AQAEAAkJrxRoDwD9AQAAAA==.Huma:BAAALgAECgYJEAAAAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8aAAIeAAcJtwnoEwAcAQAeAAcJtwnoEwAcAQAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infectus:BAAALgAECgkJBAAAAA==.Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgADCggJIgAAAA==.',
Is='Ishanllin:BAAALgADCgUJBQAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8aAAINAAgJfxdbIQDAAQANAAgJfxdbIQDAAQAAAA==.Ivylyn:BAAALgADCgYJDAAAAA==.',
Ix='Ixiyá:BAABLgAECn8iAAILAAcJayIJEgApAgALAAcJayIJEgApAgAAAA==.Ixì:BAAALgAECgYJEgAAAA==.',
Ja='Jakeyprogue:BAAALgADCgEJAQABLgAFFAIJBAAOAAAAAA==.Jakota:BAAALgADCggJDAAAAA==.Jakskeleton:BAAALgAECgUJDgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgUJBQAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgUJCAAAAA==.',
Jo='Joemacho:BAAALgADCgcJCAABLgAFFAMJCQAcAD4YAA==.Joshtee:BAAALgADCgYJBgAAAA==.Joslyn:BAAALgAECgIJAgAAAA==.',
Ju='Judax:BAABLgAECn8sAAIfAAgJrBhBDgD7AQAfAAgJrBhBDgD7AQAAAA==.Justagirl:BAABLgAECn8ZAAIaAAYJHAlPKADuAAAaAAYJHAlPKADuAAAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.',
Ka='Kadooka:BAABLgAECn8aAAIQAAcJehJAVQBpAQAQAAcJehJAVQBpAQAAAA==.Kahlyn:BAAALgADCgYJBgAAAA==.Kajax:BAABLgAECn8qAAIUAAgJISOFBACBAgAUAAgJISOFBACBAgAAAA==.Kaldaran:BAAALgAECgcJDAAAAA==.Karen:BAAALgADCgcJCgAAAA==.Karne:BAAALgADCgYJBgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAIMAAYJzxqbEQBYAQAMAAYJzxqbEQBYAQAAAA==.Keelay:BAABLgAECn8rAAIDAAgJzRlzCwBcAgADAAgJzRlzCwBcAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8WAAIIAAgJ2hRlTwDzAQAIAAgJ2hRlTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAOAAAAAA==.Kimiko:BAAALgADCgcJBwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAUACEjAA==.',
Ko='Koffcmorbius:BAAALgADCgYJDAAAAA==.Koriban:BAABLgAECn8aAAIZAAgJKw+0bAA3AQAZAAgJKw+0bAA3AQAAAA==.Korreban:BAAALgAECgYJBgABLgAECggJGgAZACsPAA==.',
Kr='Kraken:BAABLgAECn8YAAIFAAcJyx81BQCGAgAFAAcJyx81BQCGAgAAAA==.',
Ku='Kubb:BAABLgAECn8ZAAIWAAYJ8QF+FgCeAAAWAAYJ8QF+FgCeAAAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8KAAIdAAMJ1iFtAwA1AQAdAAMJ1iFtAwA1AQAuAAQKfyQAAh0ACQkZIxoFAMACAB0ACQkZIxoFAMACAAAA.',
['Kê']='Kêlsen:BAAALgAECgMJAwAAAA==.',
La='Lachupacabra:BAAALgADCgIJBAAAAA==.Larrissa:BAAALgAECgYJEwAAAA==.Larry:BAAALgAECgcJBwABLgAFFAMJBwALAJMJAA==.Laurlynn:BAAALgADCgkJHgAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgMJAgABLgAECgYJIgAcAOoOAA==.Lettuceprey:BAABLgAECn8XAAIcAAYJUhHUIABBAQAcAAYJUhHUIABBAQAAAA==.',
Li='Lies:BAAALgADCgkJCQAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.',
Lo='Lockatute:BAAALgAECgMJBQAAAA==.Lockdeath:BAAALgADCgQJBAAAAA==.Loxia:BAAALgAECgQJBgAAAA==.',
Lu='Lucille:BAAALgAFFAEJAQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luthion:BAAALgADCgMJAwAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8VAAMdAAYJ5ReFCwBhAQAdAAYJ5ReFCwBhAQARAAEJGwYHpQAlAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Magicdance:BAABLgAECn8hAAMLAAgJEhAkKgByAQALAAgJEhAkKgByAQAfAAcJ6QjATwAIAQAAAA==.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIdAAgJchK+CwACAgAdAAgJchK+CwACAgAAAA==.Majicbob:BAAALgAECgYJCgAAAA==.Maki:BAAALgAECgYJCwAAAA==.Mansion:BAAALgADCgMJBAABLgAECgcJFAANAP4bAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAQAAAA==.',
Mc='Mctowlie:BAAALgAECgEJAQAAAA==.',
Me='Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAAALgAECgcJEwAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAECggJIQALABIQAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8JAAIaAAMJoSIFCQA7AQAaAAMJoSIFCQA7AQAuAAQKfy0AAhoACAl0JRICAP8CABoACAl0JRICAP8CAAAA.Misstreater:BAAALgAECgcJCAAAAA==.',
Mo='Momentomori:BAABLgAECn8eAAIGAAgJHQmVRgBVAQAGAAgJHQmVRgBVAQAAAA==.Monocerotis:BAAALgADCgcJBwAAAA==.Morishima:BAACLgAFFH8JAAIUAAMJNBZNEwAAAQAUAAMJNBZNEwAAAQAuAAQKfykAAxQACAkyIvQEAHQCABQACAkyIvQEAHQCACAAAQkJFsYXAEMAAAAA.Morthis:BAABLgAECn8XAAMSAAYJYgkdFAC6AAASAAUJgwodFAC6AAABAAMJWgOJNABYAAAAAA==.',
Mu='Multipàss:BAAALgADCgYJCQAAAA==.',
My='Mydarling:BAAALgAFFAEJAQAAAA==.Myris:BAABLgAECn8eAAIPAAcJ1xuSKQDWAQAPAAcJ1xuSKQDWAQAAAA==.',
Na='Naturalchi:BAABLgAECn8ZAAMhAAgJ2iKtDAD4AQAhAAYJ7iKtDAD4AQAaAAYJCCEdMABnAQAAAA==.',
Ne='Nefilion:BAAALgAECgQJCAAAAA==.Nemas:BAABLgAECn8dAAIVAAgJrhmPBgD5AQAVAAgJrhmPBgD5AQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAAALgAECgYJEwAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nineadin:BAACLgAFFH8IAAIDAAMJ7xM3GADiAAADAAMJ7xM3GADiAAAuAAQKfyMAAgMACAk2HlYLAF0CAAMACAk2HlYLAF0CAAAA.Nirvanas:BAABLgAECn8VAAIdAAcJIgcIEQAKAQAdAAcJIgcIEQAKAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8iAAMcAAYJ6g6gJAAlAQAcAAYJ6g6gJAAlAQAYAAQJmQZUSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECgYJBgAAAA==.',
Nu='Nuke:BAAALgAECgQJEAAAAA==.Nullspace:BAABLgAECn8UAAIcAAgJthmAEADkAQAcAAgJthmAEADkAQAAAA==.',
Ny='Nyxe:BAAALgADCgkJCQAAAA==.',
['Ní']='Níght:BAABLgAECn8wAAICAAgJFxaPCQCJAQACAAgJFxaPCQCJAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAECgcJGAAFAMsfAA==.',
Pa='Pakeydk:BAAALgAFFAIJBAAAAA==.Palacia:BAAALgADCgYJBgAAAA==.Pancakedealr:BAAALgAECgUJDQAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8XAAIQAAkJlQWdNQB2AQAQAAkJlQWdNQB2AQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBAAAAA==.',
Pr='Preachêr:BAAALgAECgEJAQABLgAECgYJGQAVAFYgAA==.',
Pu='Puuhceew:BAABLgAECn8dAAIcAAYJkxDBIwArAQAcAAYJkxDBIwArAQAAAA==.',
Qu='Quelaag:BAAALgADCgQJBAAAAA==.Quiescent:BAABLgAECn8QAAINAAUJFBMajgAFAQANAAUJFBMajgAFAQAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8YAAMHAAYJvSSZAgD7AQAHAAYJvSSZAgD7AQAGAAEJAxEfyQA/AAABLgAFFAQJEAAJAKMmAA==.Ramanas:BAAALgAECgUJCgAAAA==.Randomizwe:BAABLgAECn8lAAIIAAgJZB2VGwAiAgAIAAgJZB2VGwAiAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Rawrnèss:BAAALgAECgkJBgAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8UAAIGAAYJzQo/YAAQAQAGAAYJzQo/YAAQAQAAAA==.Resurgencê:BAABLgAECn8ZAAIVAAYJViA9CQCzAQAVAAYJViA9CQCzAQAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8WAAMIAAcJMBGIXAA3AQAIAAYJUBKIXAA3AQAVAAEJkAt4MwArAAAAAA==.Rivfader:BAAALgAECgMJCAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJFAANAP4bAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJDQAAAA==.Rotandroll:BAAALgAECgcJDQAAAA==.Rothema:BAAALgAECgYJDAAAAA==.',
Rw='Rwlmaster:BAABLgAECn8WAAIMAAYJ3RK8FgAbAQAMAAYJ3RK8FgAbAQAAAA==.',
Ry='Rynzia:BAACLgAFFH8KAAMiAAMJcBFUBQCYAAAjAAMJZw6sIQDkAAAiAAIJ5AhUBQCYAAAuAAQKfy0AAyMACAlXISgGAH0CACMACAlXISgGAH0CACIABwmkFOwWAIUBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgMJCAAAAA==.Santose:BAAALgAECgEJAQAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8ZAAIPAAgJuAkxQwBzAQAPAAgJuAkxQwBzAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECggJNAABADceAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgMJCAAAAA==.Seta:BAABLgAECn8bAAINAAgJ2xNYQwDmAQANAAgJ2xNYQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBAAOAAAAAA==.Shamarha:BAAALgAECgYJEQAAAA==.Sharriavolf:BAABLgAECn80AAQGAAgJKCEaLwCmAQAGAAYJ1R4aLwCmAQAFAAQJciMJIABSAQAHAAEJAAB5IwBkAAAAAA==.Shato:BAAALgAECgQJBAAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAAOAAAAAA==.Siggismund:BAAALgAECgcJDwAAAA==.Simichaelton:BAABLgAECn8UAAIZAAcJrQzwnADYAAAZAAcJrQzwnADYAAABLgAECggJJgAaAIgcAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgADCgYJBgAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8cAAIIAAgJ6RtbSQAGAgAIAAgJ6RtbSQAGAgAAAA==.Sophrosyne:BAAALgAECgYJDQAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spartaaxd:BAABLgAECn8bAAITAAkJ9Q87BQCDAQATAAkJ9Q87BQCDAQAAAA==.Spookems:BAAALgAECgIJAgABLgAECgkJEQAOAAAAAA==.Spycy:BAAALgAECggJEQAAAA==.',
St='Stagerrind:BAAALgADCgQJBAAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8jAAIDAAkJOwx8GwCtAQADAAkJOwx8GwCtAQAAAA==.Stinkyfrog:BAABLgAECn8UAAIIAAcJ/xwbJgDpAQAIAAcJ/xwbJgDpAQAAAA==.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAOAAAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECgYJGQAWAPEBAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIZAAkJOgtUVgBqAQAZAAkJOgtUVgBqAQAAAA==.Suka:BAAALgADCggJGgAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgMJBQAAAA==.',
Sy='Sylentcurse:BAAALgAECgcJCQABLgAECgcJFgAQAM4OAA==.Sylentstorm:BAAALgAECgMJAwABLgAECgcJFgAQAM4OAA==.Syleta:BAABLgAECn80AAQBAAgJNx6xCQAJAgABAAYJ2RuxCQAJAgAQAAcJdBsLMADwAQASAAYJCRNgRABEAQAAAA==.',
Ta='Tabraxis:BAAALgADCgcJBgAAAA==.Tagalorc:BAABLgAECn8XAAIkAAcJ2BGBAwB4AQAkAAcJ2BGBAwB4AQAAAA==.Takamaki:BAAALgAECgEJAQAAAA==.Tanksbacon:BAAALgAECgcJEgAAAA==.Taylith:BAAALgAECgUJBQAAAA==.',
Te='Teana:BAAALgAECggJEwAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgADCgkJDgAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAMJBgARAKkYAA==.Thelegendáry:BAABLgAECn8XAAILAAYJlhc+SgBZAQALAAYJlhc+SgBZAQABLgAFFAMJBgAIAPoNAA==.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgUJBgAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn8ZAAMXAAcJ+RhrGwBaAQAXAAYJIRdrGwBaAQARAAcJ3wjzWgCwAAAAAA==.',
To='Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8VAAIfAAgJMAgCLQADAQAfAAgJMAgCLQADAQAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Trisstan:BAABLgAECn8ZAAMZAAYJ9QUJkADzAAAZAAYJ9QUJkADzAAAlAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8hAAMZAAgJEx5RIQAkAgAZAAgJfxpRIQAkAgAkAAUJHyAIBgDAAQAAAA==.Tyster:BAABLgAECn8XAAIIAAgJlQ/4OgCVAQAIAAgJlQ/4OgCVAQAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgEJAQAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJDQABLgAECgYJGQAWAPEBAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECggJIAAhANMZAA==.',
Uz='Uzu:BAABLgAECn8gAAIhAAgJ0xk1IwDpAQAhAAgJ0xk1IwDpAQAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Vamp:BAABLgAECn8WAAILAAcJUhjuLwDIAQALAAcJUhjuLwDIAQAAAA==.Vandaldor:BAAALgAECgYJCQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8KAAIZAAMJ3xN3RAABAQAZAAMJ3xN3RAABAQAuAAQKfyUAAhkACAldIokVAG4CABkACAldIokVAG4CAAAA.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8hAAMQAAgJERuyHwDeAQAQAAgJERuyHwDeAQABAAIJewTlKgBVAAABLgAECgcJIAAdAOsfAA==.',
Wa='Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECggJFwAdACsQAA==.Warthog:BAAALgADCgYJCQAAAA==.Waterbender:BAABLgAECn8XAAILAAkJRRrWCACfAgALAAkJRRrWCACfAgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgEJAQAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAAALgAECgYJEAAAAA==.Window:BAAALgADCgUJBQABLgAECgcJFAANAP4bAA==.',
Wo='Wolf:BAABLgAECn8ZAAICAAcJAxj8CwDMAQACAAcJAxj8CwDMAQAAAA==.Wolfton:BAAALgADCgQJBgAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMQAAgJIhu+HQBTAgAQAAgJIhu+HQBTAgASAAMJrAJZdABtAAAAAA==.Xanæ:BAAALgADCgQJBwAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8VAAIdAAYJ1Bd+CwBhAQAdAAYJ1Bd+CwBhAQAAAA==.',
Xy='Xyro:BAAALgAECgUJBQAAAA==.',
Ya='Yamato:BAAALgAECgUJBgAAAA==.',
Za='Zaledron:BAABLgAECn8ZAAIPAAcJzx71IgD5AQAPAAcJzx71IgD5AQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8WAAMWAAYJJwznDwAEAQAWAAYJJwznDwAEAQALAAIJ+gqwjABiAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8IAAIPAAMJJR2bQQAMAQAPAAMJJR2bQQAMAQAuAAQKfzIAAw8ACQk+JPsCAEADAA8ACQk+JPsCAEADABMAAglqIXIMAMEAAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAAOAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.',
Zp='Zpersephone:BAAALgAECgYJDgABLgAFFAMJCAAPACUdAA==.',
Zr='Zrii:BAAALgAECgMJAwAAAA==.',
Zu='Zultan:BAABLgAECn8hAAMGAAgJsxKpKADDAQAGAAcJsxKpKADDAQAFAAEJAADyMwAAAAAAAA==.Zurrik:BAABLgAECn8lAAIXAAgJwBDeFgCFAQAXAAgJwBDeFgCFAQAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAIhAAMJqBTVEgDjAAAhAAMJqBTVEgDjAAAuAAQKfycAAyEACAmEHzsJAPUCACEACAmEHzsJAPUCABoAAwkjGXVVAD8AAAAA.',
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

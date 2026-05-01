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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Monk-Brewmaster','Priest-Shadow','Shaman-Elemental','Evoker-Augmentation','Priest-Discipline','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Paladin-Protection',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abigt:BAAALgAECgYJEQAAAA==.',
Ad='Adalaidê:BAAALgAECgIJAwAAAA==.',
Ae='Aelusion:BAABLgAECn8WAAQBAAgJWh47GgC3AgABAAgJkh07GgC3AgACAAMJWiEULAAOAQADAAEJQCQiJwBVAAAAAA==.Aeluu:BAAALgAECgcJBwABLgAECggJHwAEALgRAA==.Aerynne:BAAALgAECgMJBwAAAA==.',
Ai='Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8eAAIFAAYJ6A0JLAAWAQAFAAYJ6A0JLAAWAQAAAA==.Aita:BAABLgAECn8bAAIGAAgJahjuBgAdAgAGAAgJahjuBgAdAgAAAA==.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJBQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Allegria:BAAALgAECgEJAQAAAA==.Alondra:BAABLgAECn8ZAAICAAgJXB+9AACKAgACAAgJXB+9AACKAgAAAA==.Alulà:BAAALgAECgYJDQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAAALgAECgQJBAAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECgUJCgAHAAAAAA==.',
An='Anaeli:BAABLgAECn8kAAIFAAcJOBuhEQDlAQAFAAcJOBuhEQDlAQAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAHAAAAAA==.Androth:BAAALgAECgYJEwAAAA==.Angita:BAAALgAECgMJAwAAAA==.Antipæn:BAACLgAFFH8IAAMIAAMJFRETHwD6AAAIAAMJFRETHwD6AAAJAAEJKiWbGQBpAAAuAAQKfy0AAwgACAlNJqoCAAMDAAgACAlNJqoCAAMDAAkABgmKH/UpAOIBAAAA.',
Ap='Apologia:BAABLgAECn8hAAIIAAcJxSMhDQBbAgAIAAcJxSMhDQBbAgAAAA==.',
Ar='Arcainus:BAAALgADCgIJAgAAAA==.Arceé:BAAALgADCgYJBgAAAA==.Archaic:BAABLgAECn8dAAIKAAgJPxE2LgCqAQAKAAgJPxE2LgCqAQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8MAAMLAAQJZxr7AgAnAQALAAQJRRr7AgAnAQAMAAIJCB7sFgCuAAAuAAQKfx4AAwsACAlOJOUBABoDAAsACAnJIuUBABoDAAwABwlHIjgZAIICAAAA.Ariellä:BAAALgADCgEJAQAAAA==.Arilynx:BAABLgAECn8gAAINAAkJjQdtCgBwAQANAAkJjQdtCgBwAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn8iAAIOAAgJjSD/AQCbAgAOAAgJjSD/AQCbAgAAAA==.Aroviaa:BAABLgAECn8mAAIPAAgJCRtqBQBtAgAPAAgJCRtqBQBtAgAAAA==.Arpmek:BAABLgAECn8UAAIQAAcJ8g8RKgA9AQAQAAcJ8g8RKgA9AQAAAA==.Artemîs:BAAALgAECgMJAwAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAAALgAECgYJBgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn8nAAIRAAgJqhf4CQB1AQARAAgJqhf4CQB1AQAAAA==.',
Av='Avanel:BAAALgADCgkJGgAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAAALgAECgYJCwAAAA==.Bahahaknight:BAABLgAECn8eAAIRAAYJTx/ACQB5AQARAAYJTx/ACQB5AQAAAA==.Barcy:BAAALgAECgEJAwAAAA==.Barnette:BAABLgAECn8tAAISAAgJdBKFAQDDAQASAAgJdBKFAQDDAQAAAA==.Barvi:BAAALgADCgEJAQABLgADCgUJBQAHAAAAAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn8iAAIIAAgJ3RnAHgDRAQAIAAgJ3RnAHgDRAQAAAA==.Berristan:BAABLgAECn8bAAMJAAkJ1BeiDAC1AgAJAAkJ1BeiDAC1AgAIAAMJgAWCLAFIAAAAAA==.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8FAAINAAMJ+BDnDwDOAAANAAMJ+BDnDwDOAAAuAAQKfxUAAg0ACAmcEYYYAM4BAA0ACAmcEYYYAM4BAAEuAAUUBAkEAAcAAAAA.Bluewitchpa:BAAALgADCgkJGQAAAA==.',
Bo='Boudiicca:BAAALgAECgQJEwAAAA==.Boxmasterr:BAABLgAECn8aAAMDAAgJbgm2BgD+AAABAAgJgwc2QQAuAQADAAcJoge2BgD+AAAAAA==.',
Br='Brasmir:BAAALgAECgUJCwAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.',
Bu='Bubblegìrl:BAAALgADCgcJCAAAAA==.Bubblement:BAAALgAFFAMJCAAAAQ==.Bushalabong:BAAALgAECgMJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAABLgAECn8tAAQTAAkJhx8sBwD3AQAUAAcJBiCIIwAwAgATAAgJNRosBwD3AQAVAAYJiBfuMQClAQAAAA==.Cardran:BAAALgADCgEJAQABLgAECgYJEwAHAAAAAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIJAAgJ3yHVBwDwAgAJAAgJ3yHVBwDwAgAAAA==.Catamay:BAAALgAECggJEwABLgADCgkJGgAHAAAAAA==.Catprincess:BAABLgAECn8fAAIEAAgJuBF7OwC3AQAEAAgJuBF7OwC3AQAAAA==.Caylara:BAAALgAECgIJAwAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgIJAwAAAA==.',
Ch='Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAAALgAECgYJEwAAAA==.',
Cl='Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgADCgIJAgAAAA==.',
Co='Coocoohead:BAAALgAECgIJAgAAAA==.Coralorchid:BAAALgAECgQJEAAAAA==.Corrupt:BAAALgADCgMJAwABLgADCgcJBwAHAAAAAA==.',
Cp='Cptdarkk:BAAALgAECgYJCgAAAA==.',
Cr='Crytal:BAAALgADCgEJAgAAAA==.',
Cu='Curissan:BAAALgAECgUJDQAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIEAAgJ/SD5BQC7AgAEAAgJ/SD5BQC7AgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgMJAwAAAA==.',
Da='Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAAALgAECgQJCgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAYJEwAWACsPAA==.Dalspin:BAACLgAFFH8TAAIWAAYJKw9xBQCkAQAWAAYJKw9xBQCkAQAuAAQKfxwAAxYACQm9GtwHANkCABYACQm9GtwHANkCABcABwm8ElMqAIoBAAAA.Dalthepal:BAAALgAFFAEJAQABLgAFFAYJEwAWACsPAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8HAAIIAAMJXRigGgAMAQAIAAMJXRigGgAMAQAuAAQKfy8AAggACAm7JJ8DAOkCAAgACAm7JJ8DAOkCAAAA.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deathsaberss:BAABLgAECn8jAAILAAgJWBWFBQDPAQALAAgJWBWFBQDPAQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgYJDAAAAA==.Debauch:BAAALgAECgYJCgAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Derke:BAAALgAECgQJBwAAAA==.',
Di='Diladrin:BAACLgAFFH8HAAIYAAMJmgRcBgCAAAAYAAMJmgRcBgCAAAAuAAQKfy4AAhgACAmREWEQAHEBABgACAmREWEQAHEBAAAA.Diode:BAACLgAFFH8QAAQZAAUJKxmQHABGAQAZAAQJ0RSQHABGAQAaAAMJdxL9AgD2AAARAAEJAABiHwAAAAAuAAQKfy0AAxoACAmIIQEBAGcCABkACAncIC4YAOoCABoACAlQHAEBAGcCAAAA.',
Do='Doileag:BAAALgAECgUJCAAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAAALgAECgUJCAAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAABLgAECn8dAAMSAAkJYRoXAgBKAgASAAgJzBcXAgBKAgAKAAgJIBVQcAD4AAAAAA==.Dreadwing:BAAALgAECgMJEAAAAA==.',
Du='Duf:BAACLgAFFH8QAAIbAAUJeBJKDQAoAQAbAAUJeBJKDQAoAQAuAAQKfy0AAhsACAkgH2YHACICABsACAkgH2YHACICAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn8gAAIPAAgJ/RuxCgD7AQAPAAgJ/RuxCgD7AQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAABLgAECn8aAAMbAAgJChoTEQCHAQAbAAcJ3BgTEQCHAQAXAAIJpBg9OQBbAAAAAA==.Dûna:BAABLgAECn8WAAIcAAgJUh2RBwAOAgAcAAgJUh2RBwAOAgABLgAECggJGgAbAAoaAA==.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn8nAAIIAAgJaiObBwCgAgAIAAgJaiObBwCgAgAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAAALgAECgYJCwAAAA==.Ellaring:BAAALgAECgQJBgAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAAALgAECgUJDQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8VAAMFAAYJux3/IwBJAQAFAAUJFBz/IwBJAQAdAAUJkQk5NwCVAAAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgQJBAABLgAECggJJgAPAAkbAA==.Erovvia:BAAALgAECgEJAQABLgAECggJJgAPAAkbAA==.',
Et='Etali:BAAALgADCgIJAgABLgAECgYJDQAHAAAAAA==.',
Ez='Ezothen:BAAALgAECgUJDAAAAA==.',
Fa='Faedoria:BAAALgAECgYJCgAAAA==.Faeryln:BAABLgAECn8gAAIPAAgJugrAFgBXAQAPAAgJugrAFgBXAQAAAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falkorr:BAAALgADCgEJAQABLgAECgQJEwAHAAAAAA==.Falorie:BAAALgADCgUJBQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAAALgAECgYJEAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgYJEAAHAAAAAA==.',
Fe='Feature:BAAALgADCgMJAQAAAA==.Felstormer:BAAALgADCggJCAABLgADCgkJDQAHAAAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgMJAwAAAA==.Fisticuffs:BAAALgADCgkJFQAAAA==.Fizzllebang:BAABLgAECn8gAAICAAgJcxBGBgBZAQACAAgJcxBGBgBZAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgMJAwAAAQ==.Flogginrenee:BAAALgAECgYJDQAAAA==.Floggsdaddy:BAAALgAECgYJDQAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAAALgAECgYJEgAAAA==.Fredrik:BAAALgAFFAEJAgAAAA==.Frewyn:BAAALgAECgQJBQAAAA==.Frostimoth:BAAALgAECgYJDAAAAA==.Frozty:BAAALgAECgMJBgAAAA==.',
Ga='Galandel:BAAALgADCgkJFQAAAA==.Galial:BAACLgAFFH8JAAIGAAMJWx2DAQAbAQAGAAMJWx2DAQAbAQAuAAQKfyEAAgYACQlZHzsBACIDAAYACQlZHzsBACIDAAAA.Gantar:BAAALgAFFAEJAQAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAMJCQAGAFsdAA==.Gaznol:BAAALgAECgYJDQAAAA==.',
Ge='Gelasera:BAAALgAECgMJAwAAAA==.',
Gh='Ghibli:BAAALgAECgcJEAAAAA==.',
Gl='Glaivethras:BAABLgAECn8gAAIGAAgJgCJMAQBxAgAGAAgJgCJMAQBxAgAAAA==.Glyphix:BAAALgAECggJCQAAAA==.',
Gn='Gnarly:BAAALgADCgcJBwAAAA==.',
Go='Goochtrap:BAAALgADCgEJAQAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8YAAQTAAYJnA3YEgA7AQATAAYJoQvYEgA7AQAUAAQJeQ4xgQDkAAAVAAQJXwULaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAAALgAECgMJAwABLgAECggJHgAIAO8VAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgEJAgAHAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8XAAIcAAgJfw9lLQBzAQAcAAgJfw9lLQBzAQABLgAECgYJBgAHAAAAAA==.Hannebal:BAABLgAECn8YAAIJAAgJ+hC6EADcAQAJAAgJ+hC6EADcAQAAAA==.Havenfire:BAAALgADCgUJBQABLgADCgcJBgAHAAAAAA==.',
He='Hearsebait:BAAALgADCgIJAgAAAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECgYJBgABLgAECggJHwAZANwiAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgADCgEJAQAAAA==.Holybeatdown:BAAALgADCgMJAwAAAA==.Holyßloodelf:BAAALgAECgQJBAABLgAECggJDwAHAAAAAA==.Hornet:BAAALgAECgcJEAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.',
Hu='Huasca:BAAALgADCgcJBwAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBgAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJDAAAAA==.',
['Hé']='Hélio:BAAALgADCgUJBQAAAA==.',
Ic='Icastfirebal:BAAALgADCgkJEAAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJBgAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAAALgAECggJEQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAAALgAECgMJAwAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAQJBAAAAQ==.Inumimi:BAAALgAECgYJEQAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8MAAIOAAUJPxtfBABLAQAOAAUJPxtfBABLAQAuAAQKfyUAAg4ACAmhI5wDABsDAA4ACAmhI5wDABsDAAAA.',
It='Ithran:BAAALgAECgUJDAAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8iAAISAAgJ5R3OAAAjAgASAAgJ5R3OAAAjAgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.James:BAABLgAECn8bAAIKAAYJ+xKjSgBPAQAKAAYJ+xKjSgBPAQABLgAFFAEJAgAHAAAAAA==.Janderick:BAAALgAECgYJEQAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAAALgAECgQJEwAAAA==.Jesterjoe:BAAALgAECgEJAgAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8QAAICAAUJ6yOjAACaAQACAAUJ6yOjAACaAQAuAAQKfy0AAgIACAk1JfMAAC8DAAIACAk1JfMAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJAwABLgAFFAEJAQAHAAAAAA==.',
Jo='Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAAALgAECgYJEgAAAA==.Joltraxi:BAAALgAECgMJAwAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAEJAQAHAAAAAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCQAAAA==.Juicethevoid:BAABLgAECn8fAAIQAAYJrQf8VQCmAAAQAAYJrQf8VQCmAAAAAA==.Juniornite:BAABLgAECn8iAAIKAAcJCiH0EwA6AgAKAAcJCiH0EwA6AgAAAA==.Justicus:BAAALgAECgUJCgABLgAECggJGgAUAI0YAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJDQAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAAALgAECgYJDQAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgMJBAAAAA==.Kalzod:BAACLgAFFH8HAAIBAAMJiBi3KAD7AAABAAMJiBi3KAD7AAAuAAQKfykAAwEACAmzJJQGAKQCAAEACAmzJJQGAKQCAAMAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Katett:BAAALgAECgcJDgAAAA==.Kativeria:BAAALgAECgMJAwAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAHAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEAAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAABLgAECn8ZAAIUAAcJuhvLKABzAQAUAAcJuhvLKABzAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgIJAgAAAA==.',
Ki='Kicker:BAAALgAECgIJAwAAAA==.Killmora:BAAALgADCgkJGQAAAA==.Kippars:BAAALgAECgYJDQAAAA==.Kiritsugo:BAAALgADCgUJCQAAAA==.Kissame:BAAALgADCgcJDgAAAA==.',
Ko='Kodazoff:BAABLgAECn8YAAMeAAgJ+g6DEQB/AQAeAAgJ+g6DEQB/AQANAAEJyASWSgAtAAAAAA==.Korevash:BAAALgAECgYJEAABLgAFFAMJBwAfAJQSAA==.Korupta:BAABLgAECn8hAAMQAAYJzA1WPgDtAAAgAAUJ3A3zPQAFAQAQAAYJog1WPgDtAAABLgAECgkJIQAMAOYQAA==.Korzilius:BAAALgAECgcJBwAAAA==.',
Kr='Kraiceru:BAAALgAECgcJEQAAAA==.Krissylu:BAAALgAECgQJCgAAAA==.Krothix:BAABLgAECn8cAAIdAAgJmQpxFwBYAQAdAAgJmQpxFwBYAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Kryshym:BAAALgADCggJHAAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgMJBQAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8gAAIDAAgJZw+UAgCtAQADAAgJZw+UAgCtAQAAAA==.Laima:BAAALgADCgUJCQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAQAAAA==.',
Le='Leheo:BAAALgAECgMJBAAAAA==.Lehua:BAAALgADCgQJBAAAAA==.Leilanii:BAAALgADCgkJFQAAAA==.Lemook:BAAALgAECgQJBAAAAA==.Leonìdas:BAAALgAECgMJAwAAAA==.',
Lh='Lhei:BAAALgAECgEJAgAAAA==.',
Li='Lightstormer:BAAALgADCgkJDQAAAA==.Lilarielle:BAABLgAECn8YAAIhAAYJLwRDFACYAAAhAAYJLwRDFACYAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECgYJEwAHAAAAAA==.Lilface:BAAALgAECgYJCgAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.Liø:BAAALgAECgEJAQAAAA==.',
Lo='Lokir:BAAALgAECgIJAgAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECgYJCwAHAAAAAA==.Lowchin:BAAALgAECgIJAgAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMcAAkJVR4tEwBcAgAcAAcJlB8tEwBcAgAPAAYJPBjFSgANAQAAAA==.Lutherion:BAAALgAECgUJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAAALgAECgMJBAAAAA==.Macoun:BAAALgAECggJEQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn8jAAIKAAgJpSWWBgDPAgAKAAgJpSWWBgDPAgAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAAALgAECgQJBwAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBQAHAAAAAA==.Martei:BAACLgAFFH8NAAIhAAUJkxKPAQBlAQAhAAUJkxKPAQBlAQAuAAQKfy0AAiEACAmUI0MCAC8DACEACAmUI0MCAC8DAAAA.Maríneth:BAAALgAECgEJAgAAAA==.Mathías:BAABLgAECn8gAAIUAAgJUxgRFQDpAQAUAAgJUxgRFQDpAQAAAA==.',
Me='Meadowfrey:BAAALgADCgIJAwAAAA==.Meowbae:BAABLgAECn8cAAMhAAcJeQ7fEQCPAQAhAAcJeQ7fEQCPAQAiAAEJLwGWUAAaAAAAAA==.Mercesdes:BAAALgAECgQJBAAAAA==.Mercina:BAAALgAECgEJAgAAAA==.',
Mi='Midnyte:BAABLgAECn8jAAMXAAgJGBeICQDgAQAXAAgJGBeICQDgAQAWAAMJngy9VQB4AAAAAA==.Milkybun:BAAALgADCgkJGQAAAA==.Mini:BAAALgADCgUJBQAAAA==.Minizee:BAAALgADCgYJBAAAAA==.Mirabella:BAAALgAECgQJBgABLgAECggJJAAWALUiAA==.Mirokushan:BAAALgAECgMJBgABLgAECgQJDgAHAAAAAA==.Mistfit:BAAALgAECgIJAgAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistrariel:BAAALgAECgYJCwAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Mojomarv:BAABLgAECn8YAAIdAAYJ3hhJHwAeAQAdAAYJ3hhJHwAeAQAAAA==.Mordemour:BAAALgAECgIJAgAAAA==.',
Mu='Mungo:BAAALgAECgYJDQAAAA==.',
My='My:BAAALgAECgYJAwAAAA==.Mynkie:BAACLgAFFH8FAAIWAAMJUQS5EwCpAAAWAAMJUQS5EwCpAAAuAAQKfxsAAhYACAm9GNkHADwCABYACAm9GNkHADwCAAAA.',
['Mæ']='Mæstra:BAAALgADCgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgEJAQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8QAAIQAAUJ9xCPEQAzAQAQAAUJ9xCPEQAzAQAuAAQKfyoAAhAACAmpG9gKAC8CABAACAmpG9gKAC8CAAAA.',
Ne='Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nimravidae:BAABLgAECn8dAAIJAAYJlBk+FACzAQAJAAYJlBk+FACzAQAAAA==.Ninelives:BAABLgAECn8UAAIiAAgJJwIhXQCtAAAiAAgJJwIhXQCtAAAAAA==.Nitecrawler:BAAALgAECgUJCwAAAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAAALgAECgUJDAAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAAALgAECgYJEwAAAA==.',
Nr='Nreaf:BAABLgAECn8rAAMIAAgJyhy9JACUAgAIAAgJyhy9JACUAgAjAAMJ5xkbJQDgAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgMJAwAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgUJCAAAAA==.',
Or='Ornstein:BAAALgAECgQJCAAAAA==.',
Ot='Ottuk:BAACLgAFFH8JAAIZAAMJdxdFNQD1AAAZAAMJdxdFNQD1AAAuAAQKfyAAAxkACQnVIawIAFgDABkACQnVIawIAFgDABEAAwlnHXonAAMBAAAA.',
Pa='Paksenarrion:BAABLgAECn8eAAIjAAYJ6xKtEAD3AAAjAAYJ6xKtEAD3AAAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECggJEAAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Patchington:BAAALgAECgEJAgAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAECgQJCQAHAAAAAA==.Pezvoker:BAAALgAECgQJCQAAAA==.',
Pi='Pienarri:BAAALgAECgEJAQAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAAALgAECgUJEQAAAA==.',
Po='Pochula:BAABLgAECn8aAAIEAAYJYhAbLgAmAQAEAAYJYhAbLgAmAQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8bAAIJAAcJ2RHbNwCbAQAJAAcJ2RHbNwCbAQAAAA==.Protricity:BAABLgAECn8kAAMcAAgJuR07BABoAgAcAAgJuR07BABoAgAPAAEJ2AJUhAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAMJCQAGAFsdAA==.',
['Pä']='Pändamönium:BAAALgAECggJDAAAAA==.',
['Pæ']='Pæn:BAABLgAECn8WAAMRAAYJniJkBgDDAQAZAAYJOiHXTQAJAgARAAYJkB9kBgDDAQABLgAFFAMJCAAIABURAA==.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgMJAwABLgAECgYJCwAHAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rancooll:BAAALgADCgkJGQAAAA==.Rasniir:BAABLgAECn8gAAIEAAgJsRq6CgBdAgAEAAgJsRq6CgBdAgAAAA==.Ravenlash:BAAALgAECgEJAwAAAA==.',
Re='Regna:BAACLgAFFH8QAAIMAAUJTCa1AADFAQAMAAUJTCa1AADFAQAuAAQKfy0AAgwACAl+JuoAABYDAAwACAl+JuoAABYDAAAA.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAAALgAECgQJCwAAAA==.Remaked:BAACLgAFFH8YAAIbAAYJRRyJAgC0AQAbAAYJRRyJAgC0AQAuAAQKfzgAAhsACQnyIuMAABYDABsACQnyIuMAABYDAAAA.Remilia:BAABLgAECn8XAAIcAAYJHRioFgBKAQAcAAYJHRioFgBKAQAAAA==.Requinix:BAABLgAECn8oAAIUAAgJlhReGwC7AQAUAAgJlhReGwC7AQAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECgcJBgAAAA==.Revwrinkle:BAAALgADCgQJBQAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJCwAAAA==.Ricochet:BAAALgAECggJEwAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn8eAAIPAAYJAhCPGwAqAQAPAAYJAhCPGwAqAQAAAA==.Ritzo:BAABLgAECn8YAAIMAAYJThA7HgBAAQAMAAYJThA7HgBAAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgQJEwAHAAAAAA==.',
Ro='Rockllobster:BAAALgAECgMJAwAAAA==.Rocksanne:BAAALgADCgYJCQAAAA==.Roguebâit:BAABLgAECn8jAAQBAAgJlxh+JQCaAQABAAYJJhd+JQCaAQADAAMJOhvNEwDzAAACAAMJJw3NRACiAAAAAA==.',
Ru='Rubywolf:BAAALgADCgkJEAABLgAECggJGQAiAKwWAA==.Rukkis:BAAALgAECgYJDwAAAA==.Rumi:BAACLgAFFH8HAAIGAAMJYRdOAgDnAAAGAAMJYRdOAgDnAAAuAAQKfy4AAgYACAkfH2gCABsCAAYACAkfH2gCABsCAAAA.',
Ry='Ryeekan:BAAALgAECgYJDgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8eAAIIAAgJ7xXsJwCjAQAIAAgJ7xXsJwCjAQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sancha:BAAALgADCgQJBAAAAA==.Sanosagara:BAABLgAECn8bAAIWAAgJ8ROIEQCTAQAWAAgJ8ROIEQCTAQAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgADCgMJAwAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAABLgAECn8eAAMMAAgJOhn0KwAFAgAMAAcJPBv0KwAFAgALAAUJpA8OFgBNAQAAAA==.Sath:BAAALgADCgQJBAAAAA==.Sathari:BAABLgAECn8YAAIQAAYJ0BQDNQAPAQAQAAYJ0BQDNQAPAQAAAA==.Satsuki:BAAALgAECgYJBgABLgAFFAMJBwAQADwVAA==.',
Sc='Schaden:BAAALgAECgEJAQABLgAECggJFAAEAP0gAA==.',
Se='Sekk:BAABLgAECn8oAAIIAAgJsh6VCgB5AgAIAAgJsh6VCgB5AgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgADCgcJBgAHAAAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn8kAAIgAAYJHx5VDQBnAQAgAAYJHx5VDQBnAQAAAA==.Shadoshiftt:BAAALgAECgYJEwAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgADCgkJGQAAAA==.Shamzee:BAABLgAECn8cAAIFAAYJ7B0zEwDUAQAFAAYJ7B0zEwDUAQAAAA==.Shandalf:BAAALgAECgQJDgAAAA==.Shuddarun:BAACLgAFFH8QAAIUAAUJXh24BAB+AQAUAAUJXh24BAB+AQAuAAQKfyoAAhQACAmXJcQDAFQDABQACAmXJcQDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAHAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAAALgAECgYJEwAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgADCgIJAQAAAA==.',
Sk='Skrai:BAAALgAECgYJCgABLgAECggJFgAOABgdAA==.',
Sl='Slayvylora:BAACLgAFFH8OAAIIAAUJHhDNDQA8AQAIAAUJHhDNDQA8AQAuAAQKfy0AAwgACAmgI+YFALsCAAgACAmgI+YFALsCAAkABAnOBGNuAMEAAAAA.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgADCgcJFAAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgUJCAABLgAECgYJDAAHAAAAAA==.Sniff:BAABLgAECn8fAAIKAAgJoBsAFQAzAgAKAAgJoBsAFQAzAgAAAA==.Snookums:BAABLgAECn8hAAIQAAYJIxc8SwDEAAAQAAYJIxc8SwDEAAAAAA==.',
So='Soulomon:BAAALgAECggJDwAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8UAAIKAAYJOhmLagAFAQAKAAYJOhmLagAFAQAAAA==.Spicymaker:BAABLgAECn8XAAILAAcJEx9oAgBcAgALAAcJEx9oAgBcAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJBwAAAA==.Steelheart:BAAALgAECgEJBAAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Strifewood:BAAALgAECgYJDQAAAA==.Stumper:BAAALgAECgQJEwAAAA==.',
Su='Sugondese:BAAALgAECgQJBQAAAA==.Summêr:BAAALgAECgQJCAAAAA==.Suri:BAAALgAECgUJCgAAAA==.Sux:BAAALgAECgUJEQAAAA==.',
Sy='Sybrina:BAAALgAECgUJCQAAAA==.Sylvia:BAAALgADCgcJBgAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAAALgAECgUJEgAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAECggJGQAiAKwWAA==.',
['Sí']='Síf:BAAALgAECgQJBQAAAA==.',
Ta='Tabernacle:BAAALgADCgEJAQAAAA==.Tamamò:BAABLgAECn8VAAIWAAcJ1BGHKABvAQAWAAcJ1BGHKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgADCgkJEwAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAAALgAECgYJDQAAAA==.Teranin:BAABLgAECn8UAAIiAAcJLgjYHgAGAQAiAAcJLgjYHgAGAQAAAA==.',
Tf='Tfortyone:BAAALgAECgMJAwAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8FAAIKAAMJgRqPKwAcAQAKAAMJgRqPKwAcAQAuAAQKfy4AAgoACAk3JCsGANUCAAoACAk3JCsGANUCAAAA.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn8oAAIRAAgJdBnEBQDTAQARAAgJdBnEBQDTAQAAAA==.',
Tr='Trepania:BAACLgAFFH8LAAIPAAUJXAadBQBGAQAPAAUJXAadBQBGAQAuAAQKfywAAg8ACAkKGtEWACUCAA8ACAkKGtEWACUCAAAA.Tristén:BAAALgAECgIJAgAAAA==.Trollycarp:BAAALgAECgUJDQAAAA==.Truvie:BAAALgADCgIJAgAAAA==.',
Tu='Tumbler:BAAALgAECgYJDAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAAALgAECgUJEgAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAAALgAECgYJDgAAAA==.',
Ul='Ulnuk:BAACLgAFFH8FAAIFAAIJthnhHgCfAAAFAAIJthnhHgCfAAAuAAQKfx4AAgUACAntHrELAC8CAAUACAntHrELAC8CAAAA.Ulster:BAAALgAECgEJAQAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAHAAAAAA==.',
Va='Vadka:BAAALgAECgIJAwAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgEJAgAAAA==.Vairian:BAAALgAECgYJEAAAAA==.Valsavis:BAABLgAECn8nAAIGAAgJHRuGAwDaAQAGAAgJHRuGAwDaAQAAAA==.Vampirä:BAABLgAECn8ZAAIEAAYJUwR6UQCLAAAEAAYJUwR6UQCLAAAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIXAAgJ7iAyCAD3AgAXAAgJ7iAyCAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgMJAwAAAA==.Verulan:BAAALgAECgQJCQAAAA==.Vexeh:BAAALgAECgMJAwAAAA==.Vexomous:BAAALgAECgUJCgAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vikss:BAABLgAECn8YAAMUAAgJrwsTLgBZAQAUAAgJrwsTLgBZAQATAAYJXQQqHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgADCgcJBgAHAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIhAAcJ6x9sCABYAgAhAAcJ6x9sCABYAgABLgAECggJGgAUAI0YAA==.',
Vo='Voidmayne:BAABLgAECn8lAAIIAAgJTw12NABxAQAIAAgJTw12NABxAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgIJAgAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.',
Vy='Vyv:BAAALgAECgcJEQAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIQAAYJqhukHwB1AQAQAAYJqhukHwB1AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAAALgAFFAEJAgAAAA==.',
We='Weiand:BAAALgAECgYJDQAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAABLgAECn8cAAQBAAgJuBPvRQD5AQABAAgJuBPvRQD5AQACAAIJ7w95VwBoAAADAAEJAAANMQA8AAAAAA==.Wholemilk:BAABLgAECn8PAAIQAAYJVx23GQCcAQAQAAYJVx23GQCcAQAAAA==.',
Wi='Wilhellena:BAABLgAECn8nAAIPAAgJgx+tAgDRAgAPAAgJgx+tAgDRAgAAAA==.Winariel:BAAALgAECgIJAgABLgAECgYJCwAHAAAAAA==.',
Wr='Wrëckagë:BAAALgAECgYJEQAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8XAAIBAAcJVw50MgBiAQABAAcJVw50MgBiAQABLgAECgkJIQAMAOYQAA==.Xandir:BAABLgAECn8XAAIjAAUJORI5LACsAAAjAAUJORI5LACsAAAAAA==.Xaric:BAABLgAECn8gAAIEAAgJcxn/GAC5AQAEAAgJcxn/GAC5AQAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyp:BAAALgAECgEJAQABLgAECgQJCQAHAAAAAA==.',
Yi='Yiago:BAAALgAECgEJAgAAAA==.',
Yo='Youknow:BAAALgAECgEJAQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAAALgAECgYJEwAAAA==.Zaxhdk:BAEALgAECgYJCwAAAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAHAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgADCgkJDQAHAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAAALgAECgYJCwAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAAALgAECggJEwAAAA==.Zinrar:BAAALgAECgYJEwAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8fAAIKAAcJfAV0YAAbAQAKAAcJfAV0YAAbAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAAALgAECgYJEwAAAA==.',
Zu='Zushi:BAAALgADCgEJAQAAAA==.',
['Äl']='Älphawolf:BAABLgAECn8ZAAIiAAgJrBYdDQC7AQAiAAgJrBYdDQC7AQAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAALgAECggJDwAAAA==.',
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

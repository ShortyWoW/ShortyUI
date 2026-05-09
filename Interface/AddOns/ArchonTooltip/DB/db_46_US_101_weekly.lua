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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Priest-Holy','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Paladin-Holy','Warlock-Destruction','Paladin-Protection','Warrior-Fury','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aegisthal:BAABLgAECn8XAAIBAAgJYBtdBgAuAgABAAgJYBtdBgAuAgAAAA==.Aequitasx:BAAALgAECgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJIQACAEMLAA==.',
Al='Alanerazza:BAAALgADCgUJBQAAAA==.Althenzdormu:BAAALgAECgYJEwAAAA==.Altruist:BAAALgAECgYJEAABLgAECgcJHwABAO4ZAA==.',
Am='Amaethon:BAAALgAECgYJCAAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8mAAIDAAgJ0R+pBwCzAgADAAgJ0R+pBwCzAgAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8fAAIEAAcJPx4ZCABfAgAEAAcJPx4ZCABfAgAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8VAAIFAAgJ1gUWOwD6AAAFAAgJ1gUWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8fAAQHAAcJmxTeBQB4AQAHAAcJmxTeBQB4AQAIAAEJsQN4YAApAAAJAAEJgQmkKgAoAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8fAAIKAAcJUAo5CABUAQAKAAcJUAo5CABUAQAAAA==.',
Az='Azbogah:BAAALgADCgYJBgAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMjIgCoAAAMAAIJqxMjIgCoAAAuAAQKfx4AAgwACAn+IZARAAQDAAwACAn+IZARAAQDAAAA.',
Be='Beej:BAABLgAECn8WAAIFAAkJBBKcDgABAgAFAAkJBBKcDgABAgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgYJEwAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgQJDAAAAA==.',
Bl='Blightbeard:BAAALgAECgUJEgAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgIJAgABLgAFFAUJFAANAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgEJAQAAAA==.',
Br='Brut:BAABLgAECn8YAAIOAAgJKB38OAAQAgAOAAgJKB38OAAQAgAAAA==.',
Bu='Bustus:BAABLgAECn8cAAIPAAcJeg5pNgA+AQAPAAcJeg5pNgA+AQAAAA==.',
Ca='Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgQJCQAAAA==.',
Ch='Chilly:BAAALgAECgYJDgABLgAFFAMJAwAGAAAAAA==.Chunt:BAAALgADCggJEQAAAA==.',
Co='Compliance:BAABLgAECn8fAAIBAAcJ7hnhCgC+AQABAAcJ7hnhCgC+AQAAAA==.Corannis:BAABLgAECn8aAAIQAAcJ6RMNGwB2AQAQAAcJ6RMNGwB2AQAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECgkJHwARAGoPAA==.',
Cr='Cranberries:BAAALgAECgkJDQAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJFgASAKUZAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8WAAIOAAcJQxpFIwC1AQAOAAcJQxpFIwC1AQAAAA==.',
De='Delderach:BAAALgAECgQJCQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8dAAINAAcJ4hddMQC0AQANAAcJ4hddMQC0AQAAAA==.',
Di='Dirkette:BAABLgAECn8hAAIEAAgJ+gPqIAAkAQAEAAgJ+gPqIAAkAQAAAA==.Dirksavoid:BAAALgAECgUJBQABLgAECggJIQAEAPoDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8dAAITAAcJLxgrEQCvAQATAAcJLxgrEQCvAQAAAA==.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgIJAgAAAA==.Dragmartigan:BAAALgAECgQJCQAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCgYJDAAAAA==.Eliance:BAAALgAECgQJCQAAAA==.Elsewhere:BAABLgAECn8WAAIIAAcJaQ0GIwAtAQAIAAcJaQ0GIwAtAQAAAA==.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8bAAIUAAcJ4xI0FwAWAQAUAAcJ4xI0FwAWAQAAAA==.',
Eu='Eunja:BAEALgADCggJCAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.',
Fu='Fusaa:BAABLgAECn8fAAIVAAcJzhMROQCCAQAVAAcJzhMROQCCAQAAAA==.',
Ga='Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gerbzarrion:BAAALgAECgQJCQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8oAAIWAAgJRBOgDAC3AQAWAAgJRBOgDAC3AQAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.Hawknnin:BAAALgAECgQJBgAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBAAAAA==.Huroona:BAAALgADCgcJDAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJDQAGAAAAAA==.',
Ip='Ipwnallnoobs:BAAALgAECgcJDwAAAA==.',
Ir='Irisila:BAAALgADCgkJBwABLgAECgQJBQAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAAALgAECgYJEwAAAA==.',
['Jå']='Jåsper:BAAALgAECgYJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8cAAIXAAgJUhYkBQDHAQAXAAgJUhYkBQDHAQAAAA==.Kandistars:BAABLgAECn8YAAIYAAcJYAzOIwAbAQAYAAcJYAzOIwAbAQAAAA==.Kasia:BAAALgAECgYJEwAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAINAAgJiBZBJwDiAQANAAgJiBZBJwDiAQAAAA==.Kirarah:BAABLgAECn8aAAICAAcJ8iHnEABMAgACAAcJ8iHnEABMAgAAAA==.Kirarose:BAACLgAFFH8NAAMZAAQJfBAbDABDAQAZAAQJfBAbDABDAQAaAAIJ2gHfGgBjAAAuAAQKfxUAAxkABwneHVwWADUCABkABwneHVwWADUCABoAAwmECWVoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8gAAIFAAgJMw+aFgChAQAFAAgJMw+aFgChAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJEQAAAA==.',
Ky='Kylia:BAAALgAECgUJCQAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8fAAICAAgJLiA3DgBoAgACAAgJLiA3DgBoAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8fAAMRAAkJag9BDABNAQAYAAgJ1w7rLwCIAQARAAgJVw5BDABNAQAAAA==.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAgppOQBnAQACAAgJAgppOQBnAQAAAA==.',
Lj='Ljósálfr:BAABLgAECn8oAAIBAAgJBiMaAwCfAgABAAgJBiMaAwCfAgAAAA==.',
Lo='Lochramae:BAABLgAECn8gAAIUAAcJeRWcFAAxAQAUAAcJeRWcFAAxAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgQJBAAAAA==.',
Lu='Lumanoughty:BAAALgADCgcJDgAAAA==.Lunargaze:BAABLgAECn8YAAIOAAcJRCAeEgAtAgAOAAcJRCAeEgAtAgAAAA==.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgQJCQAGAAAAAA==.Mahangi:BAAALgADCgkJCQAAAA==.Mamimisan:BAABLgAECn8eAAIDAAgJnR64CACgAgADAAgJnR64CACgAgAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBAAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgUJCQAAAA==.Mizkat:BAABLgAECn8eAAQRAAgJRxm9BgDYAQARAAgJRxm9BgDYAQAbAAEJNQ5bJgA4AAAPAAIJHA2azwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCgEJAQAAAA==.Mormra:BAABLgAECn8hAAMCAAgJQwsKNgB1AQACAAgJQwsKNgB1AQAcAAEJ1QF5LQAeAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8kAAQdAAcJZiVMBACDAgAdAAcJsyRMBACDAgACAAIJwSQuaQDWAAAcAAIJ/SMVEgDSAAAAAA==.',
Na='Nagsh:BAAALgADCgEJAQAAAA==.Naklus:BAAALgADCgYJCQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJCwABLgAECggJKAAWAEQTAA==.',
Nl='Nlani:BAAALgAECgUJCAAAAA==.',
Nu='Nuvi:BAAALgADCggJFQAAAA==.',
Or='Orihime:BAAALgADCgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8bAAIeAAcJVRiAFgDaAQAeAAcJVRiAFgDaAQAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8fAAIfAAcJLRBJCABYAQAfAAcJLRBJCABYAQAAAA==.Rassaphore:BAAALgAECgQJBwAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgYJEwAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAOACgdAA==.Rionach:BAABLgAECn8fAAIRAAcJDQhDFgC0AAARAAcJDQhDFgC0AAAAAA==.Ritsara:BAAALgAECgYJDQAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORcBIgB3AQAeAAYJORcBIgB3AQAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgUJBQAAAA==.Rothu:BAAALgAECgUJBQABLgAECgcJGQAOAMkcAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgYJBwAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8fAAMMAAcJ4h94GQAwAgAMAAcJ4h94GQAwAgAgAAYJhhJSEwAPAQAAAA==.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJsxn4agCmAAANAAIJsxn4agCmAAAAAA==.Shigurexx:BAABLgAECn8iAAMCAAgJiRypEABPAgACAAgJiRypEABPAgAcAAYJbRIJEwDGAAAAAA==.Shoe:BAABLgAECn8wAAMHAAkJtBl6AQB3AgAHAAkJtBl6AQB3AgAIAAYJmRBxGQBzAQAAAA==.',
Si='Sigmandis:BAAALgAECgYJDQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgYJBwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Ta='Taliadrin:BAAALgADCgYJBgAAAA==.Tamarins:BAAALgAECgYJEwAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIRAAgJqCJpAgCRAgARAAgJqCJpAgCRAgAAAA==.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgQJCQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJKAAWAEQTAA==.Trophyhubby:BAABLgAECn8bAAMaAAcJpwzqKQD8AAAaAAYJDg3qKQD8AAAZAAcJ2AOhLADoAAAAAA==.',
Tu='Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8UAAMNAAUJfxT2KwBIAQANAAQJfxT2KwBIAQAUAAEJAADCKgAAAAAuAAQKfxwAAg0ACAn/HtEiALQCAA0ACAn/HtEiALQCAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAUJFAANAH8UAA==.',
Us='Usato:BAAALgADCgYJBgABLgAECgQJCQAGAAAAAA==.',
Va='Valat:BAAALgADCgYJCwAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgMJAwAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCgcJDQAAAA==.',
Vi='Vikril:BAAALgADCgkJFQAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJ2SPfJQBvAgAOAAcJ2SPfJQBvAgAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
We='Weeblewobble:BAAALgADCgYJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCAAAAA==.William:BAAALgAECgYJDQAAAA==.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8UAAIcAAcJUwbaDwDwAAAcAAcJUwbaDwDwAAAAAA==.',
Xy='Xyara:BAABLgAECn8bAAQVAAkJzBYsNgCMAQAVAAYJnxIsNgCMAQALAAQJMx1vCwDTAAAfAAMJoBNkOwDGAAAAAA==.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8lAAIhAAgJdSDXBgCBAgAhAAgJdSDXBgCBAgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAAALgAFFAIJAgAAAA==.Zatika:BAABLgAECn8iAAMiAAgJkhWCAgC+AQAiAAcJthiCAgC+AQAjAAgJ0gbmXQBXAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAAALgAECgQJCQAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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

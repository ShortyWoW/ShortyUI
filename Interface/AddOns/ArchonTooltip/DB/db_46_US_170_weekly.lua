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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Warrior-Fury','Warrior-Protection','Warrior-Arms','DeathKnight-Frost','Priest-Shadow','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Mage-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Holy','Paladin-Retribution','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','Shaman-Elemental','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Priest-Discipline','Mage-Arcane','Hunter-BeastMastery','Paladin-Protection',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgYJFAACAKEfAA==.Aesalon:BAAALgAECgYJEQAAAA==.',
Ah='Ahsokatano:BAABLgAECn8UAAICAAYJoR92BQALAgACAAYJoR92BQALAgAAAA==.',
Ak='Akela:BAAALgAECgQJBgAAAA==.',
Al='Alvonaar:BAAALgADCgIJAgAAAA==.',
Am='Amonet:BAAALgADCggJHAAAAA==.',
An='Anaelcheese:BAAALgAECgQJCAAAAA==.Anamis:BAABLgAECn8WAAIDAAYJbBbCCQBgAQADAAYJbBbCCQBgAQAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAAALgAECgYJCwAAAA==.Angryorc:BAAALgAECgEJAQAAAA==.Anolana:BAABLgAECn8XAAMEAAYJLhqYCgAqAQAEAAUJXRyYCgAqAQAFAAEJcBHcCQBDAAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAAALgAECgYJCwAAAA==.',
Ar='Ariûs:BAAALgAECgQJCAAAAA==.Arlin:BAAALgADCggJGAAAAA==.Arlorian:BAABLgAECn8dAAIFAAcJoBFsCADKAQAFAAcJoBFsCADKAQAAAA==.Arrex:BAAALgADCgEJAQAAAA==.Arrowsmites:BAAALgAECgYJDgAAAA==.',
Au='Aubani:BAAALgAECgYJDwAAAA==.',
Ay='Ayperos:BAAALgAECgYJEgAAAA==.Ayvaria:BAAALgAECgQJBAABLgAECgcJGgAGAGUSAA==.',
Ba='Baked:BAAALgAECgQJBAAAAA==.Bakedpally:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Bandomar:BAAALgAECgYJDwAAAA==.Baniemo:BAAALgADCgIJAgAAAA==.Banigor:BAAALgAECgYJBwAAAA==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Beck:BAAALgAECgYJEAAAAA==.Bereth:BAAALgADCggJGwAAAA==.Berreydingle:BAAALgADCggJHAAAAA==.',
Bi='Bigkitty:BAABLgAECn8bAAIHAAcJfxWZCACWAQAHAAcJfxWZCACWAQAAAA==.Biz:BAAALgADCgYJBwABLgAECgQJBAABAAAAAA==.',
Bl='Blackautumn:BAAALgADCgcJDgABLgAECgYJFwAHAA4dAA==.Blindfred:BAAALgAECgYJCQAAAA==.Blitzedbust:BAAALgADCgUJCAAAAA==.Bloodredsky:BAAALgAECgMJAwAAAA==.Bloodymagi:BAAALgAECgQJBAAAAA==.Bluesummer:BAABLgAECn8XAAQHAAYJDh0KCACgAQAHAAYJORsKCACgAQAIAAUJiB64GQCCAQAJAAEJAQzhQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAgAAAA==.Boomin:BAAALgAECgYJDQAAAA==.',
Br='Brewnashot:BAAALgADCgYJBwAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAAALgAECgQJBAAAAA==.Brom:BAAALgADCgkJCgAAAA==.Brïn:BAAALgADCgYJBQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8WAAIKAAgJhRVjAQC1AQAKAAgJhRVjAQC1AQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgQJBQAAAA==.Captnhammer:BAAALgADCgUJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgADCggJDwAAAA==.Castration:BAAALgAECgYJEwAAAA==.',
Ce='Ceylan:BAAALgAECgYJDwAAAA==.',
Ch='Chadillac:BAAALgADCgEJAQAAAA==.Chaleb:BAAALgADCggJFgAAAA==.Charlz:BAABLgAECn8aAAMLAAgJZhLcCwA0AQALAAYJZhbcCwA0AQADAAQJCxG6VQDfAAAAAA==.Charsifood:BAAALgAECgYJDAAAAA==.Cheatdr:BAAALgAECgUJCQAAAA==.Cheatpriest:BAABLgAECn8XAAIDAAcJvRTLKgCeAQADAAcJvRTLKgCeAQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8WAAQMAAYJ9RicBgDQAAANAAYJvhTnawCKAQAOAAMJiRo0FQDeAAAMAAUJ/BWcBgDQAAAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgMJAwAAAA==.',
Co='Cognition:BAAALgAECgYJEgAAAA==.Coldvengance:BAABLgAECn8XAAIHAAYJqQWSFwDXAAAHAAYJqQWSFwDXAAAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgQJBQAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgQJBQABAAAAAA==.',
Cy='Cymindel:BAABLgAECn8YAAIPAAcJ7RZYBQBlAQAPAAcJ7RZYBQBlAQAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQAAAA==.Daithi:BAAALgAECgQJBQAAAA==.Dakotà:BAAALgAECgMJBQAAAA==.Darc:BAAALgADCgUJBQAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAAALgAECgYJDwAAAA==.',
De='Decaydence:BAAALgAECgIJAgAAAA==.Dejno:BAAALgAECgYJEwAAAA==.Deleted:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Demonicly:BAAALgAECgQJBQAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dezign:BAABLgAECn8iAAIQAAgJzx5UBgBJAgAQAAgJzx5UBgBJAgAAAA==.Dezígn:BAAALgAECgkJCQABLgAECggJIgAQAM8eAA==.',
Di='Discordegirl:BAAALgAECgUJCAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgYJEwABAAAAAA==.',
Do='Dolgorukov:BAAALgAECgYJDwAAAA==.Dologony:BAAALgAECgYJBwAAAA==.',
Dr='Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgADCggJFQAAAA==.Drikken:BAABLgAECn8aAAMRAAcJ7BRwGAA8AQASAAUJRxQQEQBAAQARAAcJEhNwGAA8AQAAAA==.Drougs:BAABLgAECn8ZAAITAAgJtxifAwCyAQATAAgJtxifAwCyAQAAAA==.',
Du='Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAAALgAECgMJBAAAAA==.',
Dy='Dymund:BAAALgADCgcJBwAAAA==.',
['Dö']='Dötdötdead:BAAALgAECgYJDAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgEJAQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgEJAQAAAA==.Effinfu:BAAALgAECgYJDQAAAA==.',
Ei='Eitent:BAABLgAECn8jAAMUAAgJxxzHDQCqAgAUAAgJxxzHDQCqAgAVAAcJuRIRdgCOAQAAAA==.',
El='Ele:BAAALgADCgEJAQAAAA==.Ellesthara:BAAALgAECgQJBQAAAA==.Ellysiaa:BAAALgAECgMJAwAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8YAAMWAAYJHA/TDQATAQAWAAYJHA/TDQATAQAXAAUJvAdtiQDCAAAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Enyxea:BAAALgAECgQJBQAAAA==.',
Ep='Ephemera:BAAALgAECgEJAQAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgADCgYJBgAAAA==.',
Es='Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAAALgAECgMJAwAAAA==.Eyewana:BAABLgAECn8bAAITAAcJ0xNKBgBVAQATAAcJ0xNKBgBVAQAAAA==.',
Fa='Fangalor:BAAALgADCgIJAwAAAA==.Farzix:BAAALgAECgUJDQAAAA==.Façade:BAABLgAECn8ZAAIYAAgJ5xJ6UgD6AQAYAAgJ5xJ6UgD6AQAAAA==.',
Fe='Fefifiona:BAAALgAECgcJEwAAAA==.Fefifredrich:BAAALgADCgUJBQABLgAECgcJEwABAAAAAA==.Felvira:BAAALgAECgYJDAAAAA==.',
Fi='Finnw:BAAALgADCggJFgAAAA==.Firelite:BAAALgAECgIJAwAAAA==.',
Fl='Flairlock:BAABLgAECn8XAAMOAAYJVhwOAgBbAQAOAAUJNB4OAgBbAQAMAAIJ4RQtDwBDAAAAAA==.Flee:BAAALgAECggJDwAAAA==.',
Fo='Fookster:BAAALgAECgMJBAAAAA==.Forsetee:BAAALgAECgYJCgAAAA==.',
Fr='Frowdawn:BAABLgAECn8XAAIFAAYJ1gtLBAAQAQAFAAYJ1gtLBAAQAQAAAA==.',
['Fí']='Físter:BAAALgAECgYJBgABLgAECgcJGgAYACoaAA==.',
Ga='Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgADCggJHAAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgYJDAABAAAAAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.',
Gh='Ghøst:BAAALgADCgMJAwAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.',
Gl='Glacialkitty:BAAALgAECgYJDQAAAA==.',
Go='Googoobler:BAAALgAECgQJCwAAAA==.',
Gr='Greenmagus:BAAALgADCgMJBAAAAA==.Grenadon:BAAALgADCggJFwAAAA==.Grimlilith:BAAALgAECgYJDAAAAA==.Grundy:BAAALgAECgEJAgAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn8YAAILAAYJPxZyCgBJAQALAAYJPxZyCgBJAQAAAA==.Hakitua:BAAALgAECgcJDQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgADCgkJEAAAAA==.Hazard:BAABLgAECn8YAAIHAAYJJAn6FAD0AAAHAAYJJAn6FAD0AAAAAA==.',
He='Heis:BAAALgADCggJGAAAAA==.Hellboii:BAAALgAECgcJEQAAAA==.Heyitsrat:BAABLgAECn8YAAIVAAcJFhBBFwBmAQAVAAcJFhBBFwBmAQAAAA==.',
Ho='Holo:BAACLgAFFH8KAAMCAAYJJgp+AgC9AQACAAYJJgp+AgC9AQAZAAIJzRmLFACpAAAuAAQKfyEAAxkACQlzIWUDAG0DABkACQlzIWUDAG0DAAIABwnXDgVCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJCgACACYKAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCgUJBQAAAA==.',
Ic='Icculus:BAAALgAECgYJDgAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8UAAIaAAgJIRRLIQD3AQAaAAgJIRRLIQD3AQAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIbAAcJ7xEYCwA3AQAbAAcJ7xEYCwA3AQAAAA==.Jaenei:BAAALgAECgQJBAAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Jo='Joatmoa:BAAALgAFFAEJAQAAAA==.Joeexotics:BAAALgADCgMJAwAAAA==.',
Ju='July:BAAALgAECgQJBQAAAA==.Jurac:BAAALgADCgcJEgAAAA==.',
Ka='Kaelnis:BAAALgADCgkJIQAAAA==.Kaimargonar:BAAALgAECgIJAgAAAA==.Kaitoi:BAAALgAECgMJAwAAAA==.Kallah:BAACLgAFFH8GAAIUAAQJFx+4AQCaAQAUAAQJFx+4AQCaAQAuAAQKfyUAAhQACQlyI48BAGsDABQACQlyI48BAGsDAAAA.Kalthos:BAABLgAECn8ZAAIcAAgJ1RaHAQA/AgAcAAgJ1RaHAQA/AgAAAA==.Kamakizeg:BAABLgAECn8XAAIVAAcJ4xLGhgBtAQAVAAcJ4xLGhgBtAQAAAA==.Kateria:BAAALgAECgcJDwAAAA==.',
Ke='Kestrelle:BAAALgAECgEJAQABLgAECgcJGQAXAKgOAA==.Keyzeus:BAAALgAECgYJDwAAAA==.',
Kh='Khas:BAAALgADCgkJFQAAAA==.Khui:BAACLgAFFH8HAAIbAAMJHyapAwBKAQAbAAMJHyapAwBKAQAuAAQKfx8AAhsACAkWJb4CAFkDABsACAkWJb4CAFkDAAAA.',
Kn='Knìghtmàrè:BAACLgAFFH8FAAIYAAMJExogDAATAQAYAAMJExogDAATAQAuAAQKfx8AAhgACQmEIM8SAAsDABgACQmEIM8SAAsDAAAA.Kníghtfíst:BAAALgAECgYJEAABLgAFFAMJBQAYABMaAA==.',
Ko='Koltharaz:BAAALgADCgIJAgAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgADCgcJCgABLgAECgYJFAABAAAAAQ==.Kozan:BAAALgAECgYJFAAAAQ==.',
Kr='Krazysniper:BAAALgAECgYJDAAAAA==.Krokk:BAAALgAECgYJBgAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.',
La='Laatt:BAABLgAECn8ZAAMVAAgJmh/BKgB5AgAVAAcJmSDBKgB5AgAUAAYJNRgSCwCPAQAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgADCgQJBAAAAA==.Latharel:BAAALgADCgUJBQAAAA==.Lawluss:BAAALgAECgYJDwAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgMJAwAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECgQJBAAAAA==.Lidrelle:BAAALgADCgkJEAAAAA==.Lighthouse:BAABLgAECn8VAAIVAAcJpB3cPAAxAgAVAAcJpB3cPAAxAgAAAA==.Lilbrute:BAAALgAECgYJBwAAAA==.Lileth:BAAALgADCggJBgAAAA==.Lilpaws:BAAALgADCgYJBgAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lolalazer:BAAALgAECgYJDwAAAA==.Lolhahabaha:BAAALgADCgkJDAAAAA==.Loopie:BAAALgADCgUJBQAAAA==.Loranthyr:BAAALgADCgQJBAAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAAALgAECgUJDgAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgUJEAABAAAAAA==.',
Ly='Lypally:BAAALgAECgYJCgAAAA==.',
['Ló']='Lóla:BAABLgAECn8YAAIRAAYJIyTHBwD2AQARAAYJIyTHBwD2AQAAAA==.',
['Lô']='Lônè:BAAALgAECgQJBAAAAA==.',
Ma='Madeah:BAACLgAFFH8LAAIEAAQJVQ39AgBbAQAEAAQJVQ39AgBbAQAuAAQKfx4AAwQACAlGHtYMAMsCAAQACAlGHtYMAMsCAAUAAQnoGtcaAFEAAAAA.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAAALgAECgYJBgAAAA==.Mariacuras:BAAALgAECgQJBAAAAA==.Marle:BAAALgAECgYJEgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgADCggJDwAAAA==.Marynne:BAABLgAECn8ZAAIXAAcJqA77FgAJAQAXAAcJqA77FgAJAQAAAA==.Matthis:BAAALgADCgYJBgAAAA==.Mazuko:BAAALgAECgYJDQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAAALgAECgYJDAAAAA==.Melbrooks:BAAALgADCgYJBgAAAA==.Melivant:BAAALgAECgEJAQAAAA==.Merriklade:BAAALgAECgUJDAAAAA==.',
Mi='Missyjelliot:BAAALgAECgMJAwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morthos:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAAALgADCgUJBQAAAA==.',
['Mâ']='Mâgs:BAAALgAECgYJBgAAAA==.',
Na='Nabbed:BAAALgAECgIJAgABLgAECgkJFgAJAHkbAA==.Nakasid:BAABLgAECn8aAAQDAAgJGAhVQAA4AQADAAcJewdVQAA4AQALAAYJlAjDOQAiAQAdAAIJnAbGUQBEAAAAAA==.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJCgAAAA==.',
Ne='Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAAALgAECgYJBwAAAA==.Nevaehstar:BAABLgAECn8YAAIeAAcJIRI7AQCNAQAeAAcJIRI7AQCNAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJBwAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEALgAECgYJDwAAAA==.Nini:BAAALgAECgYJCwAAAA==.Ninx:BAAALgAECgIJAgAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgYJBgAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgMJAwAAAA==.Ollifuzzle:BAAALgADCgQJBAAAAA==.',
Op='Oppaissiah:BAAALgAECgYJEgAAAA==.',
Or='Oraclespyro:BAAALgAECgUJBQAAAA==.Orlakx:BAAALgADCggJFAAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Papasbich:BAAALgADCgYJBQABLgAECgYJEgABAAAAAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Permafrost:BAAALgADCgYJBwAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBQAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchopw:BAAALgAECgcJAQAAAA==.Poundpuppy:BAAALgADCgUJBQAAAA==.',
Pr='Presap:BAAALgAECgYJEQAAAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgADCggJHAAAAA==.Pumdmuc:BAABLgAECn8mAAIDAAgJFCLdBgDfAgADAAgJFCLdBgDfAgAAAA==.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgADCgEJAQAAAA==.',
Qu='Quikglaives:BAAALgAECgMJAwAAAA==.Quille:BAAALgADCgMJBQAAAA==.',
Ra='Rahhem:BAAALgAECgcJEgAAAA==.Rayspaly:BAAALgADCgQJBgAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJCgAAAA==.Redrek:BAAALgADCgQJCAAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsmonk:BAAALgADCgUJBQAAAA==.Redwinter:BAAALgAECgIJAwABLgAECgYJFwAHAA4dAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAAALgAECgYJDQAAAA==.',
Ro='Rodeo:BAABLgAECn8XAAIWAAYJLw/RDwD3AAAWAAYJLw/RDwD3AAAAAA==.Rosa:BAAALgADCgEJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.',
Rp='Rpg:BAAALgAECgcJCwAAAA==.',
Ru='Rumie:BAABLgAECn8YAAIRAAYJeQ6YegA4AQARAAYJeQ6YegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgADCgYJBQAAAA==.Sadnhornless:BAAALgAECgEJAQAAAA==.Saeti:BAAALgAECgcJEwAAAA==.Sandril:BAAALgADCgYJBgAAAA==.Sapplesauce:BAAALgAECgcJDwAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Seresin:BAABLgAECn8YAAIXAAYJOhuiCQDAAQAXAAYJOhuiCQDAAQAAAA==.',
Sh='Shadý:BAABLgAECn8YAAIfAAcJ+QduFQBQAQAfAAcJ+QduFQBQAQAAAA==.Shonna:BAABLgAECn8YAAQMAAYJvxbKMwDoAAANAAUJHBYvjABBAQAMAAUJPBXKMwDoAAAOAAIJERlULQBEAAAAAA==.Shortwarrior:BAAALgAECgYJEQAAAA==.',
Si='Sidarya:BAAALgAECgEJAQAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAAALgAECggJEQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgQJBAAAAA==.Skymaggedon:BAEALgAECgYJDAAAAA==.',
Sl='Slappadrago:BAAALgAECgIJAgAAAA==.',
Sm='Smileyriley:BAAALgAECgMJAwAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJAwABLgAECgcJCwABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sofiophya:BAAALgADCggJHAAAAA==.Soulber:BAAALgAECgQJBQAAAA==.Sourdew:BAAALgAECgYJDwAAAA==.',
Sp='Spunklestain:BAAALgADCggJDQAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
St='Starrdust:BAEALgADCgQJCQAAAA==.Stelle:BAAALgAECgcJDwAAAA==.Stylos:BAAALgAECgYJDQAAAA==.Stãrburst:BAAALgAECgMJBAAAAA==.',
Ta='Taissa:BAAALgADCgYJBwAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tatertotz:BAAALgAECgMJCAAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Tegbless:BAAALgAECggJCAABLgAECggJDQABAAAAAA==.Tegchill:BAAALgAECggJDQAAAA==.',
Th='Tharelly:BAAALgAECgMJAwAAAA==.Theholymatt:BAABLgAECn8eAAMUAAcJHyJCDwCbAgAUAAcJHyJCDwCbAgAVAAQJsRcStgAZAQAAAA==.Thendari:BAABLgAECn8nAAIMAAYJ+xK9AwAsAQAMAAYJ+xK9AwAsAQAAAA==.Theodus:BAABLgAECn8YAAIQAAgJRRHRDwDFAQAQAAgJRRHRDwDFAQAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAAALgAECgYJDAABLgAECgcJHgAUAB8iAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAAALgAECgYJBwAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAABLgAECn8eAAIUAAgJ+hmdAwBFAgAUAAgJ+hmdAwBFAgAAAA==.Tislam:BAAALgAECgQJBQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8WAAQJAAkJeRvOBACaAgAJAAkJjRjOBACaAgAHAAYJtx9aMgDiAQAIAAEJIB+KRAA7AAAAAA==.Tobiquer:BAAALgAECgYJEgAAAA==.Tojarmar:BAAALgADCgkJGAABLgAECgQJBAABAAAAAA==.',
Tr='Traydra:BAAALgADCgcJFAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8KAAIZAAMJ7BXKBgDtAAAZAAMJ7BXKBgDtAAAuAAQKfyIAAhkACAnFIGQKAO8CABkACAnFIGQKAO8CAAAA.',
Ts='Tsonokwabain:BAAALgAECgYJEgAAAA==.',
Tw='Twistdog:BAAALgADCgEJAgAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8WAAIcAAcJJgzqBQA/AQAcAAcJJgzqBQA/AQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAAALgAECggJEgAAAA==.',
Va='Vaelith:BAAALgADCggJGAAAAA==.Vaelyra:BAABLgAECn8UAAIRAAcJZRdaTgC8AQARAAcJZRdaTgC8AQAAAA==.Vaerryn:BAAALgAECgQJBwAAAA==.Vaethund:BAAALgAECgEJAQAAAA==.Valgavoth:BAAALgAECgcJDwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Variala:BAAALgAECgQJBQAAAA==.Vassyra:BAABLgAECn8aAAIGAAcJZRJrAgBqAQAGAAcJZRJrAgBqAQAAAA==.',
Ve='Velesyn:BAAALgAECgUJCQAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECgMJBAAAAA==.Voidmage:BAAALgADCggJAgAAAA==.Volundr:BAABLgAECn8YAAIIAAYJ9hZIBwAjAQAIAAYJ9hZIBwAjAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgQJBAABAAAAAA==.',
Vy='Vynirion:BAABLgAECn8UAAIQAAcJpxIVLAAbAQAQAAcJpxIVLAAbAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCgYJBgAAAA==.Warcreaper:BAAALgAECgQJBAAAAA==.Wargtar:BAAALgAECgQJCQAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAAALgAECgYJDwAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wy='Wyrdhoof:BAAALgAECgYJBwAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8bAAIfAAgJFwsdVgBmAQAfAAgJFwsdVgBmAQAAAA==.',
Xa='Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAAALgAECgYJDwAAAA==.',
Xk='Xkwizet:BAAALgAECgYJDQAAAA==.',
Xo='Xorrin:BAAALgAECgUJCgAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAAALgAECgYJEQAAAA==.',
Yi='Yiffweaver:BAAALgAECgYJDgAAAA==.',
Yo='Yokoriazen:BAABLgAECn8hAAIgAAgJ7Q6IBQBDAQAgAAgJ7Q6IBQBDAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Za='Zarhianna:BAAALgAECgYJEQAAAA==.',
Zm='Zmona:BAABLgAECn8VAAIVAAcJ9w7UlABTAQAVAAcJ9w7UlABTAQAAAA==.',
Zo='Zorsche:BAAALgADCgIJAgAAAA==.',
Zu='Zulrok:BAAALgAECgYJDwAAAA==.',
['Ðr']='Ðre:BAAALgAECgUJDgAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8nAAIQAAgJoCLUGgAMAwAQAAgJoCLUGgAMAwAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','Druid-Guardian','DeathKnight-Frost','Priest-Shadow','Mage-Frost','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Restoration','DeathKnight-Unholy','Shaman-Elemental','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Priest-Discipline','Shaman-Enhancement','Paladin-Protection',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgcJGwACAMkdAA==.Aesalon:BAABLgAECn8ZAAMDAAgJmSI9AQCiAgADAAgJmSI9AQCiAgAEAAIJrRTUeQA+AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8bAAICAAcJyR2lCwAwAgACAAcJyR2lCwAwAgAAAA==.',
Ak='Akela:BAAALgAECgYJCwAAAA==.',
Al='Alvonaar:BAAALgADCgIJAgAAAA==.',
Am='Amonet:BAAALgADCggJIgAAAA==.',
An='Anaelcheese:BAAALgAECgYJEgAAAA==.Anamis:BAABLgAECn8dAAIFAAcJxhQ/EgCJAQAFAAcJxhQ/EgCJAQAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAAALgAECgcJDQAAAA==.Angryorc:BAAALgAECgEJAQAAAA==.Anolana:BAABLgAECn8eAAMGAAcJgRoMDgCKAQAGAAYJURwMDgCKAQAHAAEJcBHoEwA9AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAAALgAECgcJDAAAAA==.',
Ar='Ariûs:BAAALgAECgUJCQAAAA==.Arlin:BAAALgADCggJHgAAAA==.Arlorian:BAABLgAECn8iAAIHAAgJpg/MBACEAQAHAAgJpg/MBACEAQAAAA==.Arrex:BAAALgADCgcJCAAAAA==.Arrowsmites:BAABLgAECn8WAAIIAAgJBxYrGQDLAQAIAAgJBxYrGQDLAQAAAA==.',
Au='Aubani:BAABLgAECn8XAAMJAAgJIx5HBAC1AgAJAAgJIx5HBAC1AgAKAAEJDQ4pTQEuAAAAAA==.',
Ay='Ayperos:BAABLgAECn8aAAMLAAgJXBSQBgCzAQALAAgJUhSQBgCzAQAMAAYJPxAQUgBhAQAAAA==.Ayvaria:BAAALgAECgQJCAABLgAECggJIgANAPcVAA==.',
Ba='Badgerbrew:BAAALgADCgkJCQAAAA==.Baked:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.Bakedpally:BAAALgAECgQJBQAAAA==.Bandomar:BAAALgAECgYJEAAAAA==.Baniemo:BAAALgAECgIJAwAAAA==.Banigor:BAAALgAECgYJCwAAAA==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Beck:BAABLgAECn8XAAIKAAcJySDTGQDvAQAKAAcJySDTGQDvAQAAAA==.Beggars:BAAALgAECgEJAgAAAA==.Bereth:BAAALgADCggJHgAAAA==.Berreydingle:BAAALgADCggJIAAAAA==.',
Bi='Bigkitty:BAABLgAECn8fAAIMAAgJ+RQtDADrAQAMAAgJ+RQtDADrAQAAAA==.Biz:BAAALgADCgYJBwABLgAECgQJBQABAAAAAA==.',
Bl='Blackautumn:BAAALgADCgcJDgABLgAECgYJHQAMAEEhAA==.Blindfred:BAAALgAECggJDAAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAAALgAECgMJAwAAAA==.Bloodymagi:BAAALgAECgQJBAAAAA==.Bluesummer:BAABLgAECn8dAAQMAAYJQSGPCwDzAQAMAAYJQSGPCwDzAQAOAAUJiB69GQCCAQALAAEJAQzlQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAgAAAA==.Boomin:BAABLgAECn8UAAIPAAcJQBxaCgDzAQAPAAcJQBxaCgDzAQAAAA==.',
Br='Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAAALgAECgQJBQAAAA==.Brom:BAAALgADCgkJCgAAAA==.Brïn:BAAALgAECgEJAQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIQAAkJKhQRAgD3AQAQAAkJKhQRAgD3AQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgADCgUJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgADCggJFQAAAA==.Castration:BAABLgAECn8YAAIRAAYJzQmnHgAGAQARAAYJzQmnHgAGAQAAAA==.',
Ce='Ceylan:BAABLgAECn8XAAMSAAgJyRY1HgD3AQASAAgJyRY1HgD3AQATAAEJVQMTIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgADCggJGgAAAA==.Charlz:BAABLgAECn8fAAMRAAkJaxOdCAD7AQARAAkJaxOdCAD7AQAFAAQJCxG/VQDfAAAAAA==.Charsifood:BAAALgAECgYJDQAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAAALgAECgYJDwAAAA==.Cheatpriest:BAABLgAECn8fAAIFAAgJ8xT1EgCBAQAFAAgJ8xT1EgCBAQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8dAAQUAAcJohmkCAAiAQAVAAYJvhTtawCKAQAUAAYJoRekCAAiAQAWAAYJWhczFQDeAAAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgMJAwAAAA==.',
Co='Cognition:BAABLgAECn8aAAIIAAgJbiK7BACyAgAIAAgJbiK7BACyAgAAAA==.Coldvengance:BAABLgAECn8dAAIMAAcJRQUvKgD1AAAMAAcJRQUvKgD1AAAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgQJBQAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgQJBQABAAAAAA==.',
Cy='Cymindel:BAABLgAECn8gAAIXAAgJzBdJCACWAQAXAAgJzBdJCACWAQAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQAAAA==.Daithi:BAAALgAECgQJCgAAAA==.Dakotà:BAAALgAECgQJCQAAAA==.Darc:BAAALgADCgUJBQAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAABLgAECn8WAAIIAAcJ2hJLJgCAAQAIAAcJ2hJLJgCAAQAAAA==.',
De='Decaydence:BAAALgAECgYJCAAAAA==.Dejno:BAABLgAECn8UAAIMAAYJ0h+eFwB1AQAMAAYJ0h+eFwB1AQAAAA==.Deleted:BAAALgADCgEJAQABLgAECgQJBQABAAAAAA==.Demonicly:BAAALgAECgQJBgAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgQJBAAAAA==.Dezign:BAACLgAFFH8IAAISAAQJShDYIABPAQASAAQJShDYIABPAQAuAAQKfyMAAhIACAkOH5ISAEYCABIACAkOH5ISAEYCAAAA.Dezígn:BAAALgAECgkJCgABLgAFFAQJCAASAEoQAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAAALgAECgUJCAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECggJGwAVAL8hAA==.',
Do='Dolgorukov:BAABLgAECn8XAAIIAAgJPA+qJACIAQAIAAgJPA+qJACIAQAAAA==.Dologony:BAAALgAECggJDwAAAA==.',
Dr='Dracigor:BAAALgAECgIJAwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgADCggJGwAAAA==.Drikken:BAABLgAECn8iAAMYAAgJwRZhFADHAQAYAAgJKxVhFADHAQAZAAUJRxQSEQBAAQAAAA==.Drougs:BAABLgAECn8hAAIaAAgJGBoRCQC2AQAaAAgJGBoRCQC2AQAAAA==.',
Du='Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAAALgAECgQJCAAAAA==.',
Dy='Dymund:BAAALgAECgEJAQAAAA==.',
['Dö']='Dötdötdead:BAAALgAECgcJEwAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgEJAgAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgEJAQAAAA==.Effinfu:BAAALgAECgYJEQAAAA==.',
Ei='Eitent:BAABLgAECn8qAAMJAAkJPh0YBAC7AgAJAAkJPh0YBAC7AgAKAAcJuRIQdgCOAQAAAA==.',
El='Ele:BAAALgADCgEJAQAAAA==.Ellesthara:BAAALgAECgQJCQAAAA==.Ellysiaa:BAAALgAECgYJCQAAAA==.Elwynlana:BAAALgADCgYJBgAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8YAAMEAAYJHA9nHwACAQAEAAYJHA9nHwACAQAbAAUJvAdsiQDCAAAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Enyxea:BAAALgAECgQJBgAAAA==.',
Ep='Ephemera:BAAALgAECgEJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgADCgYJBgAAAA==.',
Es='Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAAALgAECgMJBQAAAA==.Eyewana:BAABLgAECn8fAAIaAAgJRRJDCwCIAQAaAAgJRRJDCwCIAQAAAA==.',
Ez='Ezzka:BAAALgAECgYJBwAAAA==.',
Fa='Fakesaint:BAAALgADCgEJAQAAAA==.Fangalor:BAAALgAECgEJAQAAAA==.Farzix:BAAALgAECgYJEwAAAA==.Façade:BAABLgAECn8kAAIcAAkJURJTGwDkAQAcAAkJURJTGwDkAQAAAA==.',
Fe='Fefifiona:BAAALgAECgcJEwAAAA==.Fefifredrich:BAAALgADCgUJBQABLgAECgcJEwABAAAAAA==.Felvira:BAAALgAECgYJEgAAAA==.',
Fi='Finnw:BAAALgADCggJFwAAAA==.Firelite:BAAALgAECgMJBwAAAA==.',
Fl='Flairlock:BAABLgAECn8eAAMWAAcJux4RAQAiAgAWAAcJux4RAQAiAgAUAAIJ4RQeHgBDAAAAAA==.Flee:BAABLgAECn8UAAIGAAgJwhEECQDcAQAGAAgJwhEECQDcAQAAAA==.',
Fo='Fookster:BAAALgAECgQJBQAAAA==.Forsetee:BAAALgAFFAIJBAAAAA==.',
Fr='Frowdawn:BAABLgAECn8eAAIHAAcJbgsdBgBUAQAHAAcJbgsdBgBUAQAAAA==.',
['Fí']='Físter:BAAALgAECgYJBwABLgAECgcJGgAcACoaAA==.',
Ga='Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgADCggJIgAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgcJEwABAAAAAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.',
Gh='Ghøst:BAAALgADCgMJAwAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.',
Gl='Glacialkitty:BAAALgAECgcJDwAAAA==.',
Go='Googoobler:BAAALgAECgQJDAAAAA==.Goudanight:BAAALgAECgMJBAABLgAECggJHwAMAPkUAA==.',
Gr='Greenmagus:BAAALgADCgMJBAAAAA==.Grenadon:BAAALgADCggJHQAAAA==.Grimlilith:BAAALgAECgcJEwAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn8fAAIRAAcJKRd1DQCtAQARAAcJKRd1DQCtAQAAAA==.Hakitua:BAABLgAECn8VAAIZAAgJUQqmCQAIAQAZAAgJUQqmCQAIAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn8fAAIMAAcJsgmYHgA+AQAMAAcJsgmYHgA+AQAAAA==.',
He='Heis:BAAALgADCggJHgAAAA==.Hellboii:BAAALgAECgcJEQAAAA==.Heyitsrat:BAABLgAECn8eAAIKAAcJFhAmOABjAQAKAAcJFhAmOABjAQAAAA==.',
Ho='Holo:BAACLgAFFH8LAAMCAAYJJgqDAgC9AQACAAYJJgqDAgC9AQAdAAMJthmNFACpAAAuAAQKfyEAAx0ACQlzIWcDAG0DAB0ACQlzIWcDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJCwACACYKAA==.Holyyknight:BAAALgAECgYJCQAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCgUJBQAAAA==.',
Ic='Icculus:BAAALgAECgYJDwAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8cAAIeAAgJ0hqSBgAzAgAeAAgJ0hqSBgAzAgAAAA==.',
It='Itankworlds:BAAALgAECgQJBAABLgAECgcJDgABAAAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIfAAcJ7xGyGwAkAQAfAAcJ7xGyGwAkAQAAAA==.Jaenei:BAAALgAECgQJBQAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Jo='Joatmoa:BAAALgAFFAIJAwAAAA==.Joeexotics:BAAALgADCgkJDAAAAA==.',
Ju='July:BAAALgAECgQJBgAAAA==.Jurac:BAAALgADCgcJFQAAAA==.',
Ka='Kaelnis:BAAALgADCgkJIQAAAA==.Kaimargonar:BAAALgAECgQJBgAAAA==.Kaitoi:BAAALgAECgMJBgAAAA==.Kallah:BAACLgAFFH8LAAIJAAUJRhwhCABsAQAJAAUJRhwhCABsAQAuAAQKfysAAgkACQlyI44BAGsDAAkACQlyI44BAGsDAAAA.Kalthos:BAABLgAECn8fAAIgAAgJFRdTBAA0AgAgAAgJFRdTBAA0AgAAAA==.Kamakizeg:BAABLgAECn8fAAIKAAgJYxIjKACiAQAKAAgJYxIjKACiAQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8UAAISAAcJKxbmPgBxAQASAAcJKxbmPgBxAQAAAA==.',
Ke='Kestrelle:BAAALgAECgEJAQABLgAECgcJIAAbALgRAA==.Keyzeus:BAAALgAECgYJEAAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8LAAIfAAQJTCWmBAC1AQAfAAQJTCWmBAC1AQAuAAQKfx8AAh8ACAkWJcICAFcDAB8ACAkWJcICAFcDAAAA.',
Kn='Knìghtmàrè:BAACLgAFFH8IAAMcAAUJKhvuGgBLAQAcAAQJKhvuGgBLAQAXAAEJAADvIwAAAAAuAAQKfyEAAhwACQmrINMSAAsDABwACQmrINMSAAsDAAAA.Kníghtfíst:BAABLgAECn8YAAIfAAgJ/xS6DQDKAQAfAAgJ/xS6DQDKAQABLgAFFAUJCAAcACobAA==.',
Ko='Koltharaz:BAAALgADCgIJAgAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgADCgcJCgABLgAECgcJGwABAAAAAQ==.Kozan:BAAALgAECgcJGwAAAQ==.',
Kr='Krazysniper:BAAALgAECgcJEwAAAA==.Krokk:BAAALgAECgYJCQAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.',
La='Laatt:BAABLgAECn8aAAMKAAgJFR63KgB5AgAKAAgJFR63KgB5AgAJAAYJNRjBGACIAQAAAA==.Lacosanostra:BAAALgADCgYJBgAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgADCgQJBAAAAA==.Latharel:BAAALgADCgUJBQAAAA==.Lawluss:BAABLgAECn8VAAIIAAYJ3RkJQACvAQAIAAYJ3RkJQACvAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgUJCAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECgQJBAAAAA==.Lidrelle:BAAALgAECgIJAgAAAA==.Lighthouse:BAABLgAECn8gAAIKAAgJpRvVPAAxAgAKAAgJpRvVPAAxAgAAAA==.Lilbrute:BAAALgAECgYJBwAAAA==.Lileth:BAAALgADCggJBgAAAA==.Lilpaws:BAAALgADCgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lolalazer:BAABLgAECn8UAAIYAAcJ2RRmKQBAAQAYAAcJ2RRmKQBAAQAAAA==.Lolhahabaha:BAAALgADCgkJDAAAAA==.Loopie:BAAALgADCgUJBQAAAA==.Loranthyr:BAAALgADCgQJBAAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAAALgAECgUJDwAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgYJBgABAAAAAA==.',
Ly='Lypally:BAAALgAECgcJCwAAAA==.',
['Ló']='Lóla:BAABLgAECn8ZAAIYAAcJWyIXCQBIAgAYAAcJWyIXCQBIAgAAAA==.',
['Lô']='Lônè:BAAALgAECgQJBAAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8QAAMHAAUJMQ+1AQBZAQAHAAUJtw61AQBZAQAGAAQJVQ1WCQBJAQAuAAQKfx4AAwYACAlGHtYMAMsCAAYACAlGHtYMAMsCAAcAAQnoGtoaAFEAAAAA.Mahimahi:BAAALgAECggJBwAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAAALgAECgYJBgAAAA==.Mariacuras:BAAALgAECgQJBAAAAA==.Marle:BAABLgAECn8aAAIYAAgJIRW4FQC7AQAYAAgJIRW4FQC7AQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgADCgkJGAAAAA==.Marynne:BAABLgAECn8gAAIbAAcJuBGsJABeAQAbAAcJuBGsJABeAQAAAA==.Matthis:BAAALgAECgQJBQAAAA==.Mazuko:BAABLgAECn8UAAIZAAcJTRK3BgBaAQAZAAcJTRK3BgBaAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAAALgAECgcJEwAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAAALgAECgEJAQAAAA==.Merriklade:BAAALgAECgYJEgAAAA==.',
Mi='Missyjelliot:BAAALgAECgMJAwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morthos:BAAALgAECgMJAwAAAA==.',
['Mà']='Màrli:BAAALgAECgEJAQAAAA==.',
['Mâ']='Mâgs:BAAALgAECgYJDAAAAA==.',
Na='Nabbed:BAAALgAECgIJAgABLgAECgkJIgALAMcdAA==.Nakasid:BAABLgAECn8hAAQRAAkJ2gbQOQAiAQARAAcJQwfQOQAiAQAFAAkJoQf2HwACAQAhAAIJnAbCUQBEAAAAAA==.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.',
Ne='Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8VAAIYAAgJhguIJgBPAQAYAAgJhguIJgBPAQAAAA==.Nevaehstar:BAABLgAECn8gAAITAAgJJBK3AQDVAQATAAgJJBK3AQDVAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8XAAIFAAgJSBLODgC2AQAFAAgJSBLODgC2AQAAAA==.Nikolia:BAAALgADCgMJAwAAAA==.Nini:BAAALgAECgYJEQAAAA==.Ninx:BAAALgAECgIJAgAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgYJBgAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJBwAAAA==.Ollifuzzle:BAAALgADCgQJBAAAAA==.',
Op='Oppaissiah:BAABLgAECn8aAAMOAAgJ8R24CQCRAQAMAAgJ8RxuLwDyAQAOAAYJZx24CQCRAQAAAA==.',
Or='Oraclespyro:BAAALgAECgUJCgAAAA==.Orlakx:BAAALgADCggJFAAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Papasbich:BAAALgAECgEJAQABLgAECggJGgAKAAoOAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchopw:BAAALgAECgcJAQAAAA==.Poundpuppy:BAAALgADCgUJBQAAAA==.',
Pr='Presap:BAAALgAECggJEwAAAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgADCggJIgAAAA==.Pumdmuc:BAABLgAECn8vAAMFAAgJMCPQAgDKAgAFAAgJMCPQAgDKAgARAAQJCAaUKAC7AAAAAA==.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgADCgEJAQAAAA==.',
Qu='Quikglaives:BAAALgAECgMJAwAAAA==.Quille:BAAALgADCgMJBQAAAA==.',
Ra='Rahhem:BAAALgAECgcJEwAAAA==.Rallo:BAAALgADCgUJBQAAAA==.Rayspaly:BAAALgADCgQJCAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJBwAAAA==.Redrek:BAAALgADCgUJCQAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsmonk:BAAALgADCgYJBwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgYJHQAMAEEhAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAAALgAECgYJDgAAAA==.',
Ro='Rodeo:BAABLgAECn8dAAIEAAYJXQ+lHwAAAQAEAAYJXQ+lHwAAAQAAAA==.Rotgutwiskey:BAAALgADCgYJBgAAAA==.Roxanne:BAAALgADCgYJBQAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8YAAIYAAYJeQ6XegA4AQAYAAYJeQ6XegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgADCgYJBQAAAA==.Sadnhornless:BAAALgAECgEJAQAAAA==.Saeti:BAABLgAECn8eAAQDAAgJlR2VBwBvAgADAAgJlR2VBwBvAgAEAAUJ9xL2HwD+AAAbAAMJ5hXopAB/AAAAAA==.Sandril:BAAALgADCgYJBgAAAA==.Sapplesauce:BAAALgAECgcJEgAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECgMJAwAAAA==.Seresin:BAABLgAECn8fAAIbAAcJLxrtEAAIAgAbAAcJLxrtEAAIAgAAAA==.',
Sh='Shadý:BAABLgAECn8eAAIIAAcJ+Qf6MgBFAQAIAAcJ+Qf6MgBFAQAAAA==.Shinbin:BAAALgAECgEJAQAAAA==.Shonna:BAABLgAECn8fAAQUAAcJZxhaAwC8AQAUAAcJZxhaAwC8AQAVAAUJHBY/jABBAQAWAAIJERlULQBEAAAAAA==.Shortwarrior:BAABLgAECn8YAAIMAAcJlRMlEwCdAQAMAAcJlRMlEwCdAQAAAA==.',
Si='Sidarya:BAAALgAECgEJAgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAAALgAFFAIJAgAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgQJBAAAAA==.Skymaggedon:BAEBLgAECn8UAAICAAgJegwYJwA1AQACAAgJegwYJwA1AQAAAA==.',
Sl='Slappadrago:BAAALgAECggJCgAAAA==.',
Sm='Smileyriley:BAAALgAECgYJCQAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBAABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBgAAAA==.Sofiophya:BAAALgADCggJIgAAAA==.Soulber:BAAALgAECgQJBgAAAA==.Sourdew:BAAALgAECgcJEAAAAA==.',
Sp='Spunklestain:BAAALgADCggJDQABLgAECggJCgABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
St='Starrdust:BAEALgADCgQJCQAAAA==.Stelle:BAAALgAECggJEwAAAA==.Stylos:BAABLgAECn8VAAIiAAgJzQlcCABtAQAiAAgJzQlcCABtAQAAAA==.Stãrburst:BAAALgAECgUJCAAAAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tatertotz:BAAALgAECgQJDAAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAAALgAECggJDQABLgAECgkJDgABAAAAAA==.',
Th='Thalodrim:BAAALgAECgEJAQABLgAECggJGQADAJkiAA==.Tharelly:BAAALgAECggJCwAAAA==.Theholymatt:BAACLgAFFH8IAAMJAAQJxxXmDgARAQAJAAMJ1BnmDgARAQAKAAIJWxgeLQBbAAAuAAQKfyYAAwkACAmHIz8PAJsCAAkABwnTIz8PAJsCAAoABwlGH38XAP8BAAAA.Thendari:BAABLgAECn80AAIUAAgJeRCnBACLAQAUAAgJeRCnBACLAQAAAA==.Theodus:BAABLgAECn8hAAISAAkJvBf0DwBdAgASAAkJvBf0DwBdAgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAAALgAECgYJDAABLgAFFAQJCAAJAMcVAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAAALgAECggJDwAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAABLgAECn8mAAIJAAgJfRqxBwBiAgAJAAgJfRqxBwBiAgAAAA==.Tislam:BAAALgAECgQJBgAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8iAAQLAAkJxx3PBACaAgALAAkJGRrPBACaAgAOAAcJDBxtBgDnAQAMAAYJtx9bMgDiAQAAAA==.Tobiquer:BAABLgAECn8aAAIFAAgJnxNGDgC+AQAFAAgJnxNGDgC+AQAAAA==.Tojarmar:BAAALgAECgcJBwABLgAECgQJBAABAAAAAA==.',
Tr='Traydra:BAAALgADCgkJGwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8PAAIdAAQJMhXnCQA+AQAdAAQJMhXnCQA+AQAuAAQKfysAAh0ACQlPIMMDAJACAB0ACQlPIMMDAJACAAAA.',
Ts='Tsonokwabain:BAABLgAECn8XAAMQAAcJnx9SAQBAAgAQAAcJnx9SAQBAAgAcAAEJlAIj0gAeAAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8XAAIgAAgJFAyfCwBTAQAgAAgJFAyfCwBTAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8bAAIGAAgJJQYZEQBgAQAGAAgJJQYZEQBgAQAAAA==.',
Va='Vaelith:BAAALgAECggJCQAAAA==.Vaelyra:BAABLgAECn8fAAIYAAgJGRWeMwAUAQAYAAgJGRWeMwAUAQAAAA==.Vaerryn:BAAALgAECgYJDQAAAA==.Vaethund:BAAALgAECgEJAgAAAA==.Vailenya:BAAALgADCgEJAQABLgAECgUJCQABAAAAAA==.Valgavoth:BAAALgAECgcJEQAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgADCgIJAgAAAA==.Variala:BAAALgAECgQJBgAAAA==.Vassyra:BAABLgAECn8iAAINAAgJ9xVDAgD5AQANAAgJ9xVDAgD5AQAAAA==.',
Ve='Velesyn:BAAALgAECgUJCQAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECgMJBAAAAA==.Volundr:BAABLgAECn8fAAIOAAcJzhS4DABXAQAOAAcJzhS4DABXAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgQJBQABAAAAAA==.',
Vy='Vynirion:BAABLgAECn8UAAISAAcJpxJMpACPAQASAAcJpxJMpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAAALgAECgUJBQAAAA==.Wargtar:BAAALgAECgQJDAAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAAALgAECgYJEAAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wy='Wyrdhoof:BAAALgAECgYJDQAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8dAAIIAAgJFwsZVgBmAQAIAAgJFwsZVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8WAAICAAcJzR5FDAAnAgACAAcJzR5FDAAnAgAAAA==.',
Xk='Xkwizet:BAAALgAECgcJDgAAAA==.',
Xo='Xorrin:BAAALgAECgUJCgAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8YAAIKAAgJzyNTBgC0AgAKAAgJzyNTBgC0AgAAAA==.',
Yi='Yiffweaver:BAAALgAECggJEAAAAA==.',
Yo='Yokoriazen:BAABLgAECn8qAAIjAAkJRw4QCQB8AQAjAAkJRw4QCQB8AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Za='Zarhianna:BAABLgAECn8YAAIEAAcJ+BGeEgB1AQAEAAcJ+BGeEgB1AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8aAAIKAAcJ9w5PRgA3AQAKAAcJ9w5PRgA3AQAAAA==.',
Zo='Zorsche:BAAALgADCgIJAgAAAA==.',
Zu='Zulrok:BAABLgAECn8XAAIMAAgJphiSCgABAgAMAAgJphiSCgABAgAAAA==.',
['Ðr']='Ðre:BAAALgAECgUJEQAAAA==.',
['Ût']='Ûther:BAAALgAECgEJAQAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8nAAISAAgJoCLWGgAMAwASAAgJoCLWGgAMAwAAAA==.',
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

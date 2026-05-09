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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Frost','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Druid-Restoration','Shaman-Elemental','Priest-Discipline','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Monk-Windwalker','Hunter-Survival','Paladin-Protection','Shaman-Enhancement','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adunei:BAAALgAECgEJAQAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECggJHwACAEUdAA==.Aesalon:BAABLgAECn8jAAQDAAgJpCNFAQDfAgADAAgJpCNFAQDfAgAEAAIJrRTaeQA+AAAFAAIJGBPiJwA4AAAAAA==.',
Ah='Ahsokatano:BAABLgAECn8fAAICAAgJRR1ZCwB5AgACAAgJRR1ZCwB5AgAAAA==.',
Ak='Akela:BAAALgAECggJEwAAAA==.',
Al='Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgIJAgAAAA==.',
Am='Amonet:BAAALgADCggJIgAAAA==.',
An='Anaelcheese:BAABLgAECn8ZAAQGAAcJlRRFGQAWAQAGAAcJlRRFGQAWAQAHAAEJkg0sLgAnAAAIAAEJywAB9wATAAAAAA==.Anamis:BAABLgAECn8eAAIJAAcJxxQCGgB8AQAJAAcJxxQCGgB8AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8WAAIKAAgJKgj8RwBjAQAKAAgJKgj8RwBjAQAAAA==.Angryorc:BAAALgAECgEJAQAAAA==.Anja:BAAALgADCgkJCQAAAA==.Anolana:BAABLgAECn8mAAMLAAcJAiItBgBQAgALAAcJAiItBgBQAgAMAAEJixEiGQA9AAAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAAALgAECgcJDQAAAA==.',
Ar='Ariûs:BAAALgAECgUJCgAAAA==.Arlin:BAAALgAECgIJAgAAAA==.Arlorian:BAABLgAECn8pAAIMAAgJLBAyBgCMAQAMAAgJLBAyBgCMAQAAAA==.Arorra:BAAALgADCggJCAAAAA==.Arrex:BAAALgAECgIJAgAAAA==.Arrowsmites:BAABLgAECn8eAAINAAgJXRgLHQDuAQANAAgJXRgLHQDuAQAAAA==.',
Au='Aubani:BAABLgAECn8fAAMOAAgJiB55BwCgAgAOAAgJiB55BwCgAgAPAAIJUREf7ABBAAAAAA==.',
Ay='Ayperos:BAABLgAECn8cAAMQAAgJYBQ/CgCiAQAQAAgJWBQ/CgCiAQARAAYJPxAQUgBhAQAAAA==.Ayvaria:BAAALgAECgUJDQABLgAECggJIgASAPwVAA==.',
Ba='Baboyago:BAAALgADCgEJAQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Baked:BAAALgAECgQJBAABLgAECgYJCgABAAAAAA==.Bakedpally:BAAALgAECgYJCgAAAA==.Bandomar:BAABLgAECn8WAAIEAAYJQAlnLADmAAAEAAYJQAlnLADmAAAAAA==.Baniemo:BAAALgAECgIJAwAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJBwABLgAFFAQJDAABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn8fAAIPAAgJzx8TEgBqAgAPAAgJzx8TEgBqAgAAAA==.Beggars:BAAALgAECgYJCQAAAA==.Bereth:BAAALgAECgIJAgAAAA==.Berreydingle:BAAALgAECgIJAgAAAA==.',
Bi='Bigkitty:BAABLgAECn8hAAIRAAgJVxiVDgAFAgARAAgJVxiVDgAFAgAAAA==.Biz:BAAALgADCgYJBwABLgAECgYJCQABAAAAAA==.',
Bl='Blackanvil:BAAALgADCgcJDQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECgcJHgARAKodAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAAALgAECgYJCQAAAA==.Bloodymagi:BAAALgAECgcJCwAAAA==.Bluesummer:BAABLgAECn8eAAQRAAcJqh31EQDgAQARAAYJQiH1EQDgAQATAAYJxBq+GQCCAQAQAAEJCAzmQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAgAAAA==.Boomin:BAABLgAECn8aAAIFAAcJEx2xBgDZAQAFAAcJEx2xBgDZAQAAAA==.',
Br='Brendameeks:BAAALgADCgcJBwAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAAALgAECgYJCQAAAA==.Brom:BAAALgADCgkJCwAAAA==.Brïn:BAAALgAECgEJAQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIUAAkJIxSZAwDQAQAUAAkJIxSZAwDQAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgADCgUJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgIJAgAAAA==.Castration:BAABLgAECn8YAAIVAAYJ3Al1KQD8AAAVAAYJ3Al1KQD8AAAAAA==.',
Ce='Ceylan:BAABLgAECn8fAAMWAAgJIhenKgD3AQAWAAgJIhenKgD3AQAXAAEJVQMUIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgIJAgAAAA==.Charlz:BAABLgAECn8iAAMVAAkJhRZxCQAtAgAVAAkJhRZxCQAtAgAJAAQJCxHGVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAAALgAECgYJEQAAAA==.Cheatpriest:BAABLgAECn8nAAIJAAgJHhahGQCAAQAJAAgJHhahGQCAAQAAAA==.Chesthyr:BAAALgADCgcJBwAAAA==.Chesto:BAABLgAECn8lAAQYAAgJ6hzzAwDXAQAYAAcJ4xrzAwDXAQAZAAYJvhTuawCKAQAaAAcJpBfPCAANAQAAAA==.Chimken:BAAALgAECgEJAQABLgAECgkJKQAQADceAA==.Chokea:BAAALgAECgMJAQAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgMJAwAAAA==.',
Co='Cognition:BAABLgAECn8iAAINAAgJZSMdBwDAAgANAAgJZSMdBwDAAgAAAA==.Coldvengance:BAABLgAECn8kAAIRAAcJyQjsKgAoAQARAAcJyQjsKgAoAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgQJBQAAAA==.Cranknstein:BAAALgADCgQJBAABLgAECgQJBQABAAAAAA==.',
Cy='Cymindel:BAABLgAECn8oAAIbAAgJWxi5CQDjAQAbAAgJWxi5CQDjAQAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgADCgEJAQABAAAAAA==.Daithi:BAAALgAECgUJDwAAAA==.Dakotà:BAAALgAECgYJEQAAAA==.Darc:BAAALgAECgIJAgAAAA==.Darklite:BAAALgADCgMJAwAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Day:BAABLgAECn8dAAINAAcJPRdxLACdAQANAAcJPRdxLACdAQAAAA==.',
De='Decaydence:BAAALgAECgYJCAAAAA==.Dejno:BAABLgAECn8XAAIRAAcJLyB6EwDRAQARAAcJLyB6EwDRAQAAAA==.Deleted:BAAALgADCgEJAQABLgAECggJGwAWAF4bAA==.Demonicly:BAAALgAECgYJCQAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgADCgQJBAAAAA==.Dezign:BAACLgAFFH8NAAIWAAUJlxm6IABnAQAWAAUJlxm6IABnAQAuAAQKfyUAAhYACAnoIPEXAFwCABYACAnoIPEXAFwCAAAA.Dezígn:BAAALgAECgkJCgABLgAFFAUJDQAWAJcZAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAAALgAECgYJEgAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECggJIwAZAJIjAA==.',
Do='Dolgorukov:BAABLgAECn8fAAINAAgJoBAALwCSAQANAAgJoBAALwCSAQAAAA==.Dologony:BAABLgAECn8WAAIcAAgJfg6XMQBYAQAcAAgJfg6XMQBYAQAAAA==.',
Dr='Dracigor:BAAALgAECgIJAwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgIJAgAAAA==.Dre:BAAALgAECgIJAgAAAA==.Drikken:BAABLgAECn8qAAMIAAgJxRbDIADEAQAIAAgJdBXDIADEAQAHAAUJRxQREQA/AQAAAA==.Drougs:BAABLgAECn8pAAIGAAgJIBoQDADBAQAGAAgJIBoQDADBAQAAAA==.',
Du='Dubbshot:BAAALgADCgkJCgAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAAALgAECgYJEAAAAA==.',
Dy='Dymund:BAAALgAECgEJAQAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8XAAMYAAcJoxFnCwAeAQAYAAcJoxFnCwAeAQAZAAIJZws6qABtAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgEJAQAAAA==.Effinfu:BAAALgAECgcJEgAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMOAAkJux3kAwD7AgAOAAkJux3kAwD7AgAPAAcJuhITdgCOAQAAAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgYJBwABAAAAAA==.Ellesthara:BAAALgAECgUJDgAAAA==.Ellysiaa:BAAALgAECgYJCwAAAA==.Elwynlana:BAAALgADCgYJBgAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8gAAMcAAcJMA2KNwA5AQAcAAcJMA2KNwA5AQAEAAcJVA0LIwAgAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Enyxea:BAAALgAECgYJCQAAAA==.',
Ep='Ephemera:BAAALgAECgQJBgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgADCgYJBgAAAA==.',
Es='Esmeray:BAAALgADCgYJBgABLgAECggJIgASAPwVAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAAALgAECgUJCgAAAA==.Eyewana:BAABLgAECn8hAAIGAAgJlRKjEAB6AQAGAAgJlRKjEAB6AQAAAA==.',
Ez='Ezzka:BAAALgAECgYJCwAAAA==.',
Fa='Fakesaint:BAAALgADCgEJAQAAAA==.Fangalor:BAAALgAECgEJAQAAAA==.Farnsworth:BAAALgAECgUJBAABLgAECggJIwADAKQjAA==.Farzix:BAABLgAECn8aAAIdAAcJsAZ7MgDnAAAdAAcJsAZ7MgDnAAAAAA==.Façade:BAABLgAECn8mAAIKAAkJDxOtJwDfAQAKAAkJDxOtJwDfAQAAAA==.',
Fe='Fefifiona:BAABLgAECn8VAAIeAAgJ7Be/CABPAgAeAAgJ7Be/CABPAgAAAA==.Fefifredrich:BAAALgADCgUJBQABLgAECggJFQAeAOwXAA==.Felvira:BAABLgAECn8YAAMIAAYJbQNxfwCXAAAIAAYJbQNxfwCXAAAGAAIJDgLdegAoAAAAAA==.',
Fi='Finnw:BAAALgAECgYJBwAAAA==.Firelite:BAAALgAECgYJDwAAAA==.',
Fl='Flairlock:BAABLgAECn8mAAMaAAcJwSD3AQAhAgAaAAcJwSD3AQAhAgAYAAIJBhXqJABBAAAAAA==.Flee:BAABLgAECn8aAAILAAgJ7xWwCQAGAgALAAgJ7xWwCQAGAgAAAA==.',
Fo='Fookster:BAAALgAECgkJBQAAAA==.Forsetee:BAABLgAFFH8FAAIfAAIJTRf9KQCfAAAfAAIJTRf9KQCfAAAAAA==.',
Fr='Frowdawn:BAABLgAECn8mAAIMAAgJJg6pBQCcAQAMAAgJJg6pBQCcAQAAAA==.',
['Fí']='Físter:BAAALgAECgYJBwABLgAECgcJGgAKACoaAA==.',
Ga='Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAAALgAECgIJAgAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgcJGQAKAEggAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.',
Gh='Ghøst:BAAALgADCgMJAwAAAA==.Ghøstlord:BAAALgADCgEJAQAAAA==.Ghøstslayer:BAAALgADCgEJAQAAAA==.',
Gl='Glacialkitty:BAABLgAECn8XAAIcAAgJXAglPQAgAQAcAAgJXAglPQAgAQAAAA==.',
Go='Googoobler:BAAALgAECgYJEgAAAA==.Goudanight:BAAALgAECgMJBAABLgAECggJIQARAFcYAA==.',
Gr='Greenmagus:BAAALgADCgMJBAAAAA==.Grenadon:BAAALgAECgIJAgAAAA==.Grimlilith:BAAALgAECgcJEwAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn8nAAIVAAcJXxstDgDoAQAVAAcJXxstDgDoAQAAAA==.Hakitua:BAABLgAECn8VAAIHAAgJVgo0DQDwAAAHAAgJVgo0DQDwAAAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn8nAAIRAAcJGw1FIwBVAQARAAcJGw1FIwBVAQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heis:BAAALgAECgIJAgAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8mAAIPAAgJ9BNrLwC/AQAPAAgJ9BNrLwC/AQAAAA==.',
Hi='Hiko:BAAALgAECgkJAQAAAA==.',
Ho='Holo:BAACLgAFFH8QAAMCAAYJJgqEAgC9AQACAAYJJgqEAgC9AQAdAAUJFB/bBwB0AQAuAAQKfyEAAx0ACQlzIWYDAG0DAB0ACQlzIWYDAG0DAAIABwnXDv1BAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEAACACYKAA==.Holyyknight:BAAALgAECgYJDAAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.',
Ib='Ibbert:BAAALgADCgcJDAAAAA==.',
Ic='Icculus:BAABLgAECn8VAAINAAYJnxSqPgBTAQANAAYJnxSqPgBTAQAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8hAAIfAAgJJh2bBwBWAgAfAAgJJh2bBwBWAgAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIgAAcJ7BEiJQAeAQAgAAcJ7BEiJQAeAQAAAA==.Jaenei:BAAALgAECgYJCAAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Jo='Joatmoa:BAAALgAFFAIJAwAAAA==.Joeexotics:BAAALgADCgkJDAAAAA==.',
Ju='July:BAAALgAECgYJCQAAAA==.Jurac:BAAALgADCgcJFQAAAA==.',
Ka='Kaelnis:BAAALgADCgkJIQAAAA==.Kaimargonar:BAAALgAECgUJCAAAAA==.Kaitoi:BAAALgAECgQJCgAAAA==.Kallah:BAACLgAFFH8QAAIOAAUJOR8oBQDQAQAOAAUJOR8oBQDQAQAuAAQKfzEAAg4ACQnsI40BAGsDAA4ACQnsI40BAGsDAAAA.Kalthos:BAABLgAECn8nAAIhAAgJLhdJBgAiAgAhAAgJLhdJBgAiAgAAAA==.Kamakizeg:BAABLgAECn8jAAIPAAgJ8RIFOACfAQAPAAgJ8RIFOACfAQAAAA==.Kamayla:BAAALgADCgYJBgAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8VAAIWAAgJXRbgPACxAQAWAAgJXRbgPACxAQAAAA==.',
Ke='Kestrelle:BAAALgAECgYJBwABLgAECgcJJwAcAEkSAA==.Keyzeus:BAABLgAECn8WAAISAAYJwhdHBgBpAQASAAYJwhdHBgBpAQAAAA==.',
Kh='Khas:BAAALgADCgkJGgAAAA==.Khui:BAACLgAFFH8QAAIgAAUJTyUxAwAeAgAgAAUJTyUxAwAeAgAuAAQKfyMAAyAACAkWJcACAFcDACAACAkWJcACAFcDACIAAwkwGE4sANgAAAAA.',
Ki='Kittkat:BAAALgADCgcJBwAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8LAAMKAAUJCh6vHwBhAQAKAAQJCh6vHwBhAQAbAAEJAABkLQAAAAAuAAQKfyEAAgoACQmrINASAAsDAAoACQmrINASAAsDAAAA.Kníghtfíst:BAABLgAECn8bAAIgAAgJDBVyEgDQAQAgAAgJDBVyEgDQAQABLgAFFAUJCwAKAAoeAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgYJCgABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krazysniper:BAABLgAECn8aAAMNAAgJZBhGJADEAQANAAcJzxpGJADEAQAjAAEJ4wnSPwA2AAAAAA==.Krokk:BAAALgAECgcJEAAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.',
La='Laatt:BAABLgAECn8aAAMPAAgJFh63KgB5AgAPAAgJFh63KgB5AgAOAAYJOBjWIQB5AQAAAA==.Lacosanostra:BAAALgADCgYJCQAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgEJAQAAAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8ZAAINAAYJ3RkLQACvAQANAAYJ3RkLQACvAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgYJDgAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lezsul:BAAALgADCgEJAQAAAA==.',
Li='Lickthecrit:BAAALgAECgYJCgAAAA==.Lidrelle:BAAALgAECgcJCAAAAA==.Lighthouse:BAABLgAECn8lAAIPAAgJHxzTPAAxAgAPAAgJHxzTPAAxAgAAAA==.Lilbrute:BAAALgAECgYJBwAAAA==.Lileth:BAAALgADCggJBgAAAA==.Lilpaws:BAAALgAECgQJAwAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIIAAgJ9BVBKgCQAQAIAAgJ9BVBKgCQAQAAAA==.Lolhahabaha:BAAALgAECgMJAwAAAA==.Loopie:BAAALgADCgUJBQAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8VAAIbAAYJMxVYFQAoAQAbAAYJMxVYFQAoAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgcJDAABAAAAAA==.',
Ly='Lypally:BAAALgAECgcJEQAAAA==.',
['Ló']='Lóla:BAABLgAECn8jAAIIAAgJTSRABQDaAgAIAAgJTSRABQDaAgAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBQAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8WAAMMAAYJZRLMAACzAQAMAAYJOw/MAACzAQALAAUJ4BKCDABMAQAuAAQKfx4AAwsACAlGHtUMAMsCAAsACAlGHtUMAMsCAAwAAQnoGtwaAFEAAAAA.Mahimahi:BAAALgAECggJBwAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAAALgAECgcJDQAAAA==.Mariacuras:BAAALgAECgUJCQAAAA==.Marle:BAABLgAECn8iAAIIAAgJcxbiIADDAQAIAAgJcxbiIADDAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgADCgkJIQAAAA==.Marynne:BAABLgAECn8nAAIcAAcJSRKELwBkAQAcAAcJSRKELwBkAQAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8bAAIHAAcJzRSxBwBxAQAHAAcJzRSxBwBxAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8ZAAMVAAcJrAtcLgDeAAAVAAYJugxcLgDeAAAJAAUJxQwsMQDFAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAAALgAECgIJAwABLgAECgMJBAABAAAAAA==.Merriklade:BAABLgAECn8UAAIRAAYJ5wdrQQC6AAARAAYJ5wdrQQC6AAAAAA==.',
Mi='Missyjelliot:BAAALgAECgQJBwAAAA==.',
Mo='Moof:BAAALgADCgEJAQAAAA==.Morthos:BAAALgAECgMJAwAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgYJBwABAAAAAA==.',
['Mà']='Màrli:BAAALgAECgEJAQAAAA==.',
['Mâ']='Mâgs:BAAALgAECgcJEwAAAA==.',
Na='Nabbed:BAAALgAECgIJAgABLgAECgkJKQAQADceAA==.Nakasid:BAABLgAECn8pAAQJAAkJOA/ZGgB0AQAJAAkJEg3ZGgB0AQAVAAcJPwfSOQAiAQAeAAQJWwqYMACoAAAAAA==.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgEJAQAAAA==.',
Ne='Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8cAAIIAAgJ6AwLOABVAQAIAAgJ6AwLOABVAQAAAA==.Nevaehstar:BAABLgAECn8oAAIXAAgJDhliAQAvAgAXAAgJDhliAQAvAgAAAA==.',
Ni='Nibuto:BAAALgAECgQJCQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8fAAIJAAgJNRPnFACwAQAJAAgJNRPnFACwAQAAAA==.Nikolia:BAAALgADCgYJBwAAAA==.Nini:BAAALgAECgYJEQAAAA==.Ninx:BAAALgAECgIJAgAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgYJBgAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJBwAAAA==.Ollifuzzle:BAAALgADCgQJBAAAAA==.',
Op='Oppaissiah:BAABLgAECn8iAAMRAAgJ9B07DAAnAgARAAgJZR07DAAnAgATAAYJah2bDQCIAQAAAA==.',
Or='Oraclespyro:BAAALgAECgYJEAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Papasbich:BAAALgAECgEJAgABLgAECggJIgAPAA4OAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgADCgEJAQAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchopw:BAAALgAECgcJAQAAAA==.Poundpuppy:BAAALgADCgUJBQAAAA==.',
Pr='Presap:BAABLgAECn8bAAMcAAgJ4SF1DgBqAgAcAAcJ2yF1DgBqAgAEAAEJAACkdgBJAAAAAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAAALgAECgIJAgAAAA==.Pumdmuc:BAABLgAECn84AAMJAAkJmiFUAwD2AgAJAAkJmiFUAwD2AgAVAAcJKgXoLADnAAAAAA==.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgADCgEJAQAAAA==.',
Qu='Quikglaives:BAAALgAECgMJAwAAAA==.Quille:BAAALgAECgUJBQAAAA==.',
Ra='Rahhem:BAABLgAECn8YAAIkAAgJixI5DQBlAQAkAAgJixI5DQBlAQAAAA==.Rallo:BAAALgADCgUJBQAAAA==.Rayspaly:BAAALgAECgEJAQAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJBwAAAA==.Redrek:BAAALgADCgYJCwAAAA==.Redshunter:BAAALgADCgIJAgAAAA==.Redsmonk:BAAALgADCgYJBwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECgcJHgARAKodAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8UAAIcAAYJog1OQAASAQAcAAYJog1OQAASAQAAAA==.',
Ro='Rodeo:BAABLgAECn8lAAIEAAcJxQ4eHwA9AQAEAAcJxQ4eHwA9AQAAAA==.Rotgutwiskey:BAAALgADCgcJDQAAAA==.Roxanne:BAAALgADCgYJBQAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8YAAIIAAYJeQ6aegA4AQAIAAYJeQ6aegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgADCgYJBQAAAA==.Sadnhornless:BAAALgAECgEJAQAAAA==.Saeti:BAABLgAECn8oAAUDAAgJlR2VBwBvAgADAAgJlR2VBwBvAgAEAAYJ1BkyFwCCAQAFAAQJvBVbFQC+AAAcAAMJ8RfipAB/AAAAAA==.Sandril:BAAALgAECgQJBgAAAA==.Sapplesauce:BAAALgAECgcJEgAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJCwAAAA==.Seresin:BAABLgAECn8nAAIcAAcJfBsOFgAUAgAcAAcJfBsOFgAUAgAAAA==.',
Sh='Shadý:BAABLgAECn8mAAINAAgJ6wkSNgB1AQANAAgJ6wkSNgB1AQAAAA==.Shinbin:BAAALgAECgEJAQAAAA==.Shonna:BAABLgAECn8nAAQYAAcJFxv/BACyAQAZAAcJXhiUKADEAQAYAAcJeBj/BACyAQAaAAIJERlULQBEAAAAAA==.Shortwarrior:BAABLgAECn8gAAIRAAgJLxjnDQAOAgARAAgJLxjnDQAOAgAAAA==.',
Si='Sidarya:BAAALgAECgYJCwAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAABLgAECn8VAAMQAAgJNxLOGQAlAQARAAcJixACSwB5AQAQAAUJ6hDOGQAlAQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgQJBAAAAA==.Skymaggedon:BAEBLgAECn8cAAICAAgJLQ2GMgBDAQACAAgJLQ2GMgBDAQAAAA==.',
Sl='Slappadrago:BAAALgAECggJCgAAAA==.',
Sm='Smileyriley:BAAALgAECgYJDwAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBAABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBgAAAA==.Sofiophya:BAAALgAECgIJAgAAAA==.Soulber:BAAALgAECgYJCQAAAA==.Sourdew:BAABLgAECn8XAAIiAAcJ5R11DADxAQAiAAcJ5R11DADxAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAAALgAECgQJBAABLgAECggJGwAcAOEhAA==.Spunklestain:BAAALgADCggJDQABLgAECggJCgABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
St='Starrdust:BAEALgADCgkJEQAAAA==.Stelle:BAABLgAECn8VAAIeAAgJBREVJABzAQAeAAgJBREVJABzAQAAAA==.Stylos:BAABLgAECn8bAAIlAAgJEQpFCgByAQAlAAgJEQpFCgByAQAAAA==.Stãrburst:BAAALgAECgYJCgAAAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tatertotz:BAAALgAECgUJDQAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAAALgAECggJDQABLgAECgkJDgABAAAAAA==.',
Th='Thalodrim:BAAALgAECgEJAQABLgAECggJIwADAKQjAA==.Tharelly:BAAALgAECggJEwAAAA==.Theholymatt:BAACLgAFFH8MAAMOAAQJMhzDFQD+AAAOAAMJ3RnDFQD+AAAPAAMJXhO6SACcAAAuAAQKfyYAAw4ACAmII0APAJsCAA4ABwnTI0APAJsCAA8ABwlHH7AjAPUBAAAA.Thendari:BAABLgAECn8+AAIYAAgJiBDBBgCAAQAYAAgJiBDBBgCAAQAAAA==.Theodus:BAABLgAECn8qAAIWAAkJMRg4GABaAgAWAAkJMRg4GABaAgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAImAAgJfhp2CQA1AgAmAAgJfhp2CQA1AgABLgAFFAQJDAAOADIcAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn8XAAMQAAgJSiFABQAkAgARAAcJtSGuJAAyAgAQAAcJMh9ABQAkAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8HAAIOAAMJmR2sEgAeAQAOAAMJmR2sEgAeAQAuAAQKfycAAg4ACAmBGioNAEMCAA4ACAmBGioNAEMCAAAA.Tislam:BAAALgAECgYJCQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQQAAkJNx7NBACaAgAQAAkJGBrNBACaAgATAAcJpCAXBgA2AgARAAYJtx9aMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn8iAAIJAAgJAhYpEADpAQAJAAgJAhYpEADpAQAAAA==.Tojarmar:BAAALgAECgcJDQABLgAECgQJBAABAAAAAA==.',
Tr='Traydra:BAAALgADCgkJGwAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8TAAIdAAUJmBehDABEAQAdAAUJmBehDABEAQAuAAQKfy0AAh0ACQmJIP4DAMECAB0ACQmJIP4DAMECAAAA.',
Ts='Tsonokwabain:BAABLgAECn8cAAQUAAcJqx86AgAnAgAUAAcJqx86AgAnAgAbAAEJah1mMQBSAAAKAAEJmAKOBAEdAAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn8fAAIhAAgJ1Q7mDQBlAQAhAAgJ1Q7mDQBlAQAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8bAAILAAgJJgbHFgBRAQALAAgJJgbHFgBRAQAAAA==.',
Un='Unc:BAAALgAECgcJBwAAAA==.',
Va='Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8fAAIIAAgJGxVYTgC8AQAIAAgJGxVYTgC8AQAAAA==.Vaerryn:BAABLgAECn8VAAQUAAcJGR/VAwDDAQAUAAYJJh7VAwDDAQAKAAIJExwKnwCjAAAbAAIJQyDoLgBeAAAAAA==.Vaethund:BAAALgAECgMJBQAAAA==.Vailenya:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgADCgUJBwAAAA==.Variala:BAAALgAECgYJCQAAAA==.Vassyra:BAABLgAECn8iAAISAAgJ/BVXAwDpAQASAAgJ/BVXAwDpAQAAAA==.',
Ve='Velesyn:BAAALgAECgYJDwAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECgcJCwAAAA==.Voidlighter:BAAALgAECgcJBwABLgAECgkJMAAOALsdAA==.Volundr:BAABLgAECn8nAAITAAcJJRjTDQCFAQATAAcJJRjTDQCFAQAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgYJCQABAAAAAA==.',
Vy='Vynirion:BAABLgAECn8UAAIWAAcJqxJNpACPAQAWAAcJqxJNpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAAALgAECgcJDAAAAA==.Wargtar:BAAALgAECgYJEgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8WAAMJAAYJ+BBsJQAeAQAJAAYJqA9sJQAeAQAeAAIJpRHgSgBqAAAAAA==.',
Wh='Whiterrina:BAAALgADCgkJCgAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAAALgAECgcJEgAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8dAAINAAgJGQsaVgBmAQANAAgJGQsaVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn8eAAICAAcJDSTtBwCvAgACAAcJDSTtBwCvAgAAAA==.',
Xk='Xkwizet:BAABLgAECn8VAAIWAAgJ2AVOaQA+AQAWAAgJ2AVOaQA+AQAAAA==.',
Xo='Xorrin:BAAALgAECgUJCgAAAA==.',
Xy='Xylpho:BAAALgADCgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8fAAIPAAgJMySyCQC8AgAPAAgJMySyCQC8AgAAAA==.',
Yi='Yiffweaver:BAABLgAECn8YAAIfAAgJ9wMyKQD/AAAfAAgJ9wMyKQD/AAAAAA==.',
Yo='Yokoriazen:BAABLgAECn8zAAIkAAkJRxNQBwDjAQAkAAkJRxNQBwDjAQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Za='Zarhianna:BAABLgAECn8gAAIEAAgJcBGFEwCoAQAEAAgJcBGFEwCoAQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8iAAIPAAgJyg3cUABUAQAPAAgJyg3cUABUAQAAAA==.',
Zo='Zorsche:BAAALgADCgUJBwAAAA==.',
Zu='Zulrok:BAABLgAECn8fAAIRAAgJdBtgDAAlAgARAAgJdBtgDAAlAgAAAA==.',
['Ðr']='Ðre:BAAALgAECgUJEQAAAA==.',
['Ût']='Ûther:BAAALgAECgEJAQAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8pAAIWAAgJyiLWGgAMAwAWAAgJyiLWGgAMAwAAAA==.',
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

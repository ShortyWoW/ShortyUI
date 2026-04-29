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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Holy','Mage-Frost','Paladin-Retribution','Rogue-Subtlety','Evoker-Preservation','Monk-Brewmaster','Druid-Balance','Druid-Guardian','Warrior-Arms','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Monk-Windwalker','Druid-Feral','Rogue-Outlaw','Hunter-Survival','Rogue-Assassination','Paladin-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abbraxys:BAAALgADCgkJDgAAAA==.',
Ad='Adios:BAACLgAFFH8PAAIBAAUJvBqMAgBzAQABAAUJvBqMAgBzAQAuAAQKfxcAAwEABwkaJFMQAHMCAAEABwkaJFMQAHMCAAIABgnDDawfADABAAAA.',
Af='Afflict:BAAALgADCgcJEwAAAA==.',
Ag='Agaar:BAAALgAECgQJCAAAAA==.',
Ai='Aidasul:BAAALgAECgQJBAAAAA==.Aireese:BAABLgAECn8eAAIDAAcJ+h2XAwCwAQADAAcJ+h2XAwCwAQAAAA==.',
Ak='Akaizhar:BAAALgADCgEJAQAAAA==.',
Al='Alareth:BAAALgAECgIJAwAAAA==.Alinity:BAAALgAECgUJBwAAAA==.Alnysh:BAAALgADCgUJCQAAAA==.',
Am='Amorilladron:BAABLgAECn8VAAIEAAgJ+gOYLADXAAAEAAgJ+gOYLADXAAAAAA==.',
An='Anakira:BAAALgADCgUJCAAAAA==.Anséis:BAAALgADCgEJAQAAAA==.Anti:BAAALgAECgMJBAAAAA==.Antury:BAAALgAECgYJDQAAAA==.',
Aq='Aquamatty:BAAALgADCgEJAQAAAA==.',
Ar='Arcayne:BAAALgAECgMJAwAAAA==.Areeya:BAAALgAECgUJDQAAAA==.Ariamis:BAAALgADCgYJBgAAAA==.Arkatt:BAABLgAECn8cAAIEAAcJ/xs2SgAUAgAEAAcJ/xs2SgAUAgAAAA==.Arrowgance:BAAALgAECgEJAQABLgAFFAUJDwABALwaAA==.Artorious:BAAALgADCgUJBQAAAA==.Arulas:BAABLgAECn8eAAIDAAkJ9AxIGACXAQADAAkJ9AxIGACXAQAAAA==.Arx:BAABLgAECn8XAAIFAAcJPyCgHQBhAgAFAAcJPyCgHQBhAgAAAA==.',
As='Ascrod:BAACLgAFFH8FAAMGAAQJMQVuHgAKAQAGAAQJMQVuHgAKAQAHAAEJwQHIGgBDAAAuAAQKfxUABAcABwn8GWcVAJ8BAAcABgkAG2cVAJ8BAAYABAlaExS0APAAAAgAAQnpFX4wAD0AAAEuAAMKBQkFAAkAAAAA.Ashami:BAAALgADCgEJAQAAAA==.Ashaxxi:BAAALgAECgMJAwABLgAFFAMJBgAKAG4FAA==.Ashildr:BAACLgAFFH8GAAIKAAMJbgU6AQCwAAAKAAMJbgU6AQCwAAAuAAQKfyEABAoACAmbFBQKAMcBAAoACAmbFBQKAMcBAAsAAgm8A7NlAE0AAAwAAgkOBRvTAE0AAAAA.Asuwish:BAABLgAECn8XAAINAAcJoxJWLgCLAQANAAcJoxJWLgCLAQAAAA==.',
At='Atcjedi:BAAALgAECgcJEwAAAA==.Atmospherew:BAAALgAFFAIJAwABLgAFFAYJEwAOAHQlAA==.Atmospherez:BAACLgAFFH8TAAIOAAYJdCVzAAAUAgAOAAYJdCVzAAAUAgAuAAQKfyUAAg4ACQnZJkEAAAkEAA4ACQnZJkEAAAkEAAAA.',
Au='Audiamer:BAAALgAECgIJAgAAAA==.Auradawn:BAAALgADCgEJAQAAAA==.',
Az='Azardel:BAAALgADCgQJBAAAAA==.Azmodan:BAAALgAECgMJAwAAAA==.',
['Añ']='Añdrew:BAAALgADCgIJAQAAAA==.',
Ba='Baalsdruid:BAAALgAECgQJBQAAAA==.Badgerdar:BAAALgAECgcJBwAAAA==.Baep:BAACLgAFFH8FAAIPAAIJSiTrGQDUAAAPAAIJSiTrGQDUAAAuAAQKfxcAAg8ACAl0JUEJAEgDAA8ACAl0JUEJAEgDAAAA.Baess:BAAALgAECgUJBQABLgAECggJGgAQALcVAA==.Balance:BAABLgAECn8jAAQCAAYJTBqwGAByAQACAAYJTBqwGAByAQABAAUJRxCkDwDzAAARAAMJwwTFPQB9AAAAAA==.Balooa:BAAALgAECgQJCgAAAA==.Bandrago:BAAALgADCgkJEAAAAA==.Banzan:BAAALgAECgQJBAAAAA==.Barktwain:BAAALgAECgYJEwABLgAECgUJDAAJAAAAAA==.Barracuda:BAAALgAECgQJBAAAAA==.Barrybrown:BAAALgAECgQJBwAAAA==.',
Bd='Bdikd:BAAALgADCgQJBwAAAA==.',
Be='Beeaarr:BAABLgAECn8WAAIPAAYJtRVTiABqAQAPAAYJtRVTiABqAQAAAA==.Beercules:BAABLgAECn8fAAISAAgJMRgKBgCoAQASAAgJMRgKBgCoAQAAAA==.Belagore:BAABLgAECn8ZAAIFAAgJVhlLGACJAgAFAAgJVhlLGACJAgAAAA==.Belegmor:BAAALgADCgEJAQAAAA==.Benfrank:BAABLgAECn8cAAMTAAgJXxbcHwAAAgATAAgJXxbcHwAAAgAUAAEJUgPIDwAfAAAAAA==.Benkkei:BAABLgAECn8dAAMFAAgJrxmaAwANAgAFAAgJJBiaAwANAgAVAAYJ4hXbEQCDAQAAAA==.Bethan:BAAALgAECgYJDwAAAA==.',
Bf='Bfillz:BAABLgAECn8XAAIMAAYJSBM5HAAhAQAMAAYJSBM5HAAhAQAAAA==.',
Bi='Bigantall:BAAALgAECgQJBQAAAA==.Bigmedic:BAAALgAECgcJDwABLgAECggJFAAWAJwYAA==.Bigtea:BAAALgAECgQJCQAAAA==.Biishess:BAAALgAECgkJBAAAAA==.Bitta:BAAALgADCgEJAQAAAA==.',
Bl='Blaart:BAAALgAECgQJCAAAAA==.Blanka:BAABLgAECn8UAAMWAAgJnBibCABVAgAWAAgJnBibCABVAgAXAAEJlgEbqgAjAAAAAA==.Blax:BAAALgAECgYJBQAAAA==.Blindhugs:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Bluexecute:BAAALgAECggJEwAAAA==.Blumez:BAAALgAECgcJDgAAAA==.Blùey:BAAALgADCgMJAwAAAA==.',
Bo='Bob:BAAALgADCgcJBwABLgAECgcJFgAGAJ4bAA==.Bodytypebig:BAABLgAECn8YAAIUAAcJpBWNDgCXAQAUAAcJpBWNDgCXAQAAAA==.Boeuf:BAAALgAECgkJDwAAAA==.Boicrystian:BAAALgAECgYJCQAAAA==.Bolillo:BAAALgAECgEJAQAAAA==.Bookitty:BAAALgADCgkJDwAAAA==.Bord:BAAALgADCgYJBgAAAA==.Bossed:BAAALgAECgMJBwAAAA==.Bossladìe:BAAALgAECgYJCQAAAA==.Boston:BAAALgAECgEJAQAAAA==.',
Br='Brewness:BAAALgAECgYJDAABLgAECggJEwAJAAAAAA==.Brommix:BAAALgAECgQJBwAAAA==.Brown:BAAALgAECgcJDQAAAA==.Broxy:BAAALgAECgEJAgAAAA==.',
Bu='Bucci:BAAALgADCgIJAwAAAA==.Buhbles:BAABLgAECn8bAAITAAcJbiNgFABvAgATAAcJbiNgFABvAgAAAA==.Buhflobill:BAAALgADCgcJCgAAAA==.Bullshiitake:BAAALgAECgMJAwAAAA==.Burberry:BAAALgAECgEJAQAAAA==.',
Ca='Cae:BAABLgAECn8XAAIMAAgJOBqQCADpAQAMAAgJOBqQCADpAQAAAA==.Calaglin:BAABLgAECn8XAAMGAAgJQRrqSwDlAQAGAAcJIx3qSwDlAQAHAAIJ9AiBSwCLAAAAAA==.Calastiria:BAAALgADCgcJDAAAAA==.Caleb:BAAALgADCgYJBgAAAA==.Cassylan:BAAALgADCgEJAQAAAA==.Cavaloris:BAABLgAECn8UAAIYAAcJvwUkSwAbAQAYAAcJvwUkSwAbAQAAAA==.',
Ce='Celesti:BAAALgAECgYJEwAAAA==.Cellia:BAAALgAECgYJDQAAAA==.Cevy:BAAALgAFFAMJAwAAAA==.',
Ch='Chekz:BAAALgADCgUJBQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chickensalad:BAAALgAECgIJAgABLgAECgYJCgAJAAAAAA==.Chilæ:BAAALgAECgUJBQABLgAECgcJGQAOAOkXAA==.Chirhoxp:BAABLgAECn8ZAAMZAAgJjw3GFwCZAQAZAAgJjw3GFwCZAQAFAAIJnwoYlwBkAAAAAA==.Chocomousse:BAAALgADCgcJDAAAAA==.Chop:BAAALgAECgEJAQAAAA==.Christi:BAAALgAECgEJAQABLgAFFAMJBgAaALcYAA==.Chubbstone:BAAALgADCgIJAgAAAA==.Chuckkyd:BAABLgAECn8XAAIPAAcJGRtfDADOAQAPAAcJGRtfDADOAQAAAA==.',
Ci='Cileo:BAAALgADCgYJCQAAAA==.',
Cl='Clanka:BAAALgAECgQJBQAAAA==.Cleb:BAAALgAECgYJBQAAAA==.Clocker:BAAALgAECgYJEwAAAA==.Clumbsykoala:BAAALgAECgMJAwAAAA==.Clâyface:BAABLgAECn8WAAITAAYJaA1/DwD9AAATAAYJaA1/DwD9AAAAAA==.',
Co='Coasta:BAAALgAECgMJCAAAAA==.Coldlunch:BAAALgAECgIJAgAAAA==.Colton:BAAALgAFFAEJBAAAAA==.Combatcow:BAABLgAECn8hAAIFAAgJMCFGCwABAwAFAAgJMCFGCwABAwAAAA==.Cozmic:BAABLgAECn8dAAIOAAgJqCEWBAB8AgAOAAgJqCEWBAB8AgAAAA==.',
Cq='Cq:BAAALgADCggJCAAAAA==.',
Cr='Crackseed:BAAALgAECgcJEAAAAA==.Craftymidget:BAABLgAECn8ZAAIbAAcJ6AhqCQDFAAAbAAcJ6AhqCQDFAAAAAA==.Crit:BAAALgAECgMJBgAAAA==.',
Ct='Ctn:BAAALgAECgMJAwAAAA==.',
Cu='Cumdropcutie:BAAALgAECgQJBgAAAA==.Curandero:BAAALgAECgQJCQAAAA==.Curie:BAABLgAECn8ZAAIOAAcJ6RepewDaAQAOAAcJ6RepewDaAQAAAA==.',
Da='Dalynar:BAAALgADCgEJAQAAAA==.Dameck:BAABLgAECn8eAAMVAAcJHBn4AgCYAQAFAAYJmRiSQgCaAQAVAAcJohb4AgCYAQAAAA==.Dampo:BAAALgADCgYJDAAAAA==.Danakira:BAAALgADCgMJBgAAAA==.Dancemonkey:BAAALgAECgUJBQAAAA==.Daralock:BAABLgAECn8fAAMGAAgJVBs0TwDaAQAGAAYJghs0TwDaAQAHAAQJGRGKMwDpAAAAAA==.Darkburley:BAAALgAECgIJAgAAAA==.Darkcastle:BAAALgADCgUJBQAAAA==.Darkholy:BAAALgADCgYJDAAAAA==.Darosh:BAAALgAECgEJAQABLgAECgYJDwAJAAAAAA==.Das:BAABLgAECn8ZAAIMAAgJKBvnCQDUAQAMAAgJKBvnCQDUAQAAAA==.Dawnbringer:BAAALgADCgEJAQAAAA==.Dayxxday:BAAALgAECgQJBgAAAA==.Dazzeler:BAAALgAECgYJDwAAAA==.',
De='Deathdisiple:BAAALgAECgMJAgAAAA==.Deathpetals:BAACLgAFFH8QAAIEAAYJqh/XBAC0AQAEAAYJqh/XBAC0AQAuAAQKfyYAAgQACQkqJo0AAOoDAAQACQkqJo0AAOoDAAAA.Decepciona:BAABLgAECn8YAAQHAAcJ1CAHLAAPAQAGAAQJFSDRfABiAQAHAAMJaiAHLAAPAQAIAAEJAAAfIwBlAAABLgAECggJDQAJAAAAAA==.Deecaye:BAAALgAECgEJAQAAAA==.Deejaypaulyd:BAAALgAECgYJDgAAAA==.Delver:BAAALgADCgIJAgAAAA==.Demongirly:BAAALgADCgcJBwAAAA==.Derailed:BAAALgAECgUJBQAAAA==.Desp:BAAALgAECgMJAgABLgAFFAYJEAAcADsUAA==.Despir:BAACLgAFFH8QAAMcAAYJOxTTBwBKAQAcAAUJ5xPTBwBKAQANAAMJUgnGBwDuAAAuAAQKfxwABA0ACAm9HbEKAKICAA0ACAm9HbEKAKICABwABglbJDwfAN4BAB0AAgnVAhdQAE4AAAAA.Destantokill:BAAALgAECgMJAwAAAA==.Destro:BAAALgADCgUJBQAAAA==.Devilpoing:BAAALgAECgUJCAAAAA==.Devounor:BAAALgAECgYJCgAAAA==.',
Di='Ding:BAAALgADCgIJAgAAAA==.',
Do='Donnamatrix:BAAALgAECgIJAgAAAA==.Dorado:BAAALgADCgIJAgAAAA==.Douchec:BAAALgADCgMJBgAAAA==.',
Dr='Dracarizz:BAAALgADCgQJBAAAAA==.Draconius:BAAALgADCgcJFQAAAA==.Draenor:BAAALgADCgcJDQAAAA==.Dragnspittle:BAABLgAECn8ZAAQRAAcJuRVwGADPAQARAAcJuRVwGADPAQABAAQJ1xrcDwDwAAACAAMJbBPtBADTAAAAAA==.Dragonforce:BAABLgAECn8WAAICAAYJ/xgDEwCxAQACAAYJ/xgDEwCxAQAAAA==.Dragonskull:BAAALgAECgYJCwAAAA==.Dragonturd:BAAALgAECgcJDwAAAA==.Drazentar:BAAALgAECgUJCwAAAA==.Dregore:BAAALgAECgYJEgABLgAECggJGQAFAFYZAA==.Drethor:BAAALgADCgIJAgABLgAECggJHgAEAOkfAA==.Drevox:BAABLgAECn8eAAIEAAgJ6R9XBQAzAgAEAAgJ6R9XBQAzAgAAAA==.Druidheals:BAAALgADCgUJBgAAAA==.',
Du='Dulgar:BAABLgAECn8eAAIXAAcJcx5cBwDaAQAXAAcJcx5cBwDaAQAAAA==.Dummythick:BAAALgADCgUJBQAAAA==.Dunsmuir:BAABLgAECn8fAAIeAAYJQRzUEwBcAQAeAAYJQRzUEwBcAQAAAA==.Dux:BAAALgAECggJEwAAAA==.',
['Dé']='Dévé:BAAALgADCgkJEAAAAA==.',
El='Elephant:BAAALgAECgEJAQAAAA==.Elleduff:BAAALgAECgYJDgAAAA==.Eloragon:BAAALgADCgcJDAAAAA==.Elspeth:BAAALgAECgQJBQAAAA==.Elviusel:BAAALgADCgMJAwAAAA==.Elydra:BAAALgAECgQJBQAAAA==.Elysstaa:BAABLgAECn8eAAMNAAcJqxP+BgCeAQANAAcJqxP+BgCeAQAcAAQJzgtGSQC5AAAAAA==.',
Eq='Equilibria:BAAALgAECgQJBQAAAA==.',
Es='Esris:BAAALgAECggJJwAAAQ==.',
Et='Etík:BAAALgAECgQJBgAAAA==.',
Ev='Evomengol:BAAALgADCgUJBwABLgAFFAMJBgATAAEMAA==.',
Ex='Exorcist:BAAALgAECgEJAQAAAA==.',
Ey='Eyebright:BAAALgAECgMJAwAAAA==.Eyye:BAAALgADCgYJBgABLgAECgEJAgAJAAAAAA==.',
Fa='Falcyn:BAAALgAECgYJDQAAAA==.Faminex:BAACLgAFFH8IAAIYAAYJ2xxnAADbAQAYAAYJ2xxnAADbAQAuAAQKfxsAAxgACAn/HzwJAP4CABgACAn/HzwJAP4CABYABAmWHhYcAAoBAAEuAAUUBgkMAAYAFxwA.Farns:BAACLgAFFH8RAAIOAAUJuCV3BQAOAgAOAAUJuCV3BQAOAgAuAAQKfxcAAg4ABwn2JTosAMICAA4ABwn2JTosAMICAAAA.',
Fe='Feiyue:BAABLgAECn8YAAMGAAcJwhEwWAC/AQAGAAcJwhEwWAC/AQAIAAEJ6g0bMAA+AAAAAA==.Felinepriest:BAAALgAECgYJBgAAAA==.Felsdh:BAAALgAECgUJCgAAAA==.Felsoaked:BAAALgADCgEJAQAAAA==.Feltotes:BAAALgADCgcJDgAAAA==.Felucia:BAAALgAECgYJCgAAAA==.Fenryr:BAAALgAECgQJBAAAAA==.Feyvorian:BAAALgADCgMJAwAAAA==.',
Fi='Fingerbone:BAAALgADCgkJEgAAAA==.Firebäne:BAABLgAECn8aAAIHAAgJvh+XAAAeAgAHAAgJvh+XAAAeAgAAAA==.Firecreep:BAAALgAECgcJDAAAAA==.Fistweave:BAAALgAECgMJAwAAAA==.',
Fl='Flaminghawk:BAACLgAFFH8JAAIOAAUJahGwHQBUAQAOAAUJahGwHQBUAQAuAAQKfyAAAg4ACAkmIY8oANACAA4ACAklIY8oANACAAAA.Flokkii:BAAALgADCgUJBQAAAA==.Floofyfire:BAAALgAECgEJAQAAAA==.',
Fm='Fmnx:BAAALgADCgMJAwABLgAFFAYJDAAGABccAA==.',
Fr='Frankazoid:BAABLgAECn8WAAIEAAcJ2RYfFABxAQAEAAcJ2RYfFABxAQAAAA==.Frankdatank:BAAALgADCgcJBwABLgAECggJFgAEANkWAA==.Freightfrayn:BAABLgAECn8lAAIXAAkJ4hv0BgAEAwAXAAkJ4hv0BgAEAwAAAA==.Freyin:BAAALgAECgYJEQAAAA==.Frolgar:BAAALgADCgMJBQAAAA==.Frostytotems:BAAALgADCgcJBgAAAA==.',
Fu='Fulldracarys:BAACLgAFFH8RAAIRAAYJLBZYAgD+AQARAAYJLBZYAgD+AQAuAAQKfx4AAhEACAlyJZoCAEUDABEACAlyJZoCAEUDAAAA.Fullgabagool:BAAALgAECgcJEQABLgAFFAYJEQARACwWAA==.Fullmist:BAAALgAECgcJBgABLgAFFAYJEQARACwWAA==.Fulltranq:BAACLgAFFH8IAAIaAAYJXAnpAQChAQAaAAYJXAnpAQChAQAuAAQKfxcAAhoABwnmIvshADYCABoABwnmIvshADYCAAEuAAUUBgkRABEALBYA.',
Fw='Fwaffy:BAAALgAFFAEJAQAAAA==.',
['Fë']='Fëanor:BAAALgAECgQJBAAAAA==.',
['Fø']='Føxz:BAABLgAECn8UAAISAAgJHBwRFgBZAgASAAgJHBwRFgBZAgAAAA==.Føxzxv:BAAALgAECggJDAAAAA==.',
Ga='Gamesucks:BAAALgAECgEJAgAAAA==.Ganster:BAAALgAECgEJAgAAAA==.Gaya:BAAALgADCgUJDAAAAA==.',
Ge='Gee:BAAALgADCgEJAQAAAA==.Geltheros:BAAALgADCggJCAAAAA==.Getzapped:BAAALgADCgEJAQAAAA==.',
Gf='Gfoo:BAABLgAECn8UAAIfAAYJ0BjhJwCaAQAfAAYJ0BjhJwCaAQAAAA==.',
Gh='Ghidorah:BAAALgAECgEJAQAAAA==.',
Gi='Gigabloke:BAAALgADCgUJBQAAAA==.Gigastar:BAAALgAECgYJBgAAAA==.',
Gl='Glacia:BAAALgADCgUJBQAAAA==.Glaticus:BAAALgAECgEJAQAAAA==.Glimpse:BAAALgAECggJEAAAAA==.Glizzgobbler:BAAALgAECgQJAwAAAA==.',
Go='Gokêe:BAAALgAECgYJCAABLgAECgcJDwAJAAAAAA==.Golddigger:BAAALgAECgQJDAAAAA==.Golok:BAAALgAECgEJAQABLgAECgYJBgAJAAAAAA==.Goof:BAAALgAECgUJCwAAAA==.Gout:BAAALgADCgEJAQAAAA==.Goyuri:BAAALgAECgMJAwAAAA==.',
Gr='Greenmonsta:BAAALgAECgYJCAAAAA==.Grimknight:BAAALgAECggJEwAAAA==.Groovi:BAAALgADCgYJCgAAAA==.Grubergeiger:BAAALgAECgUJCAABLgAECgkJDwAJAAAAAA==.Gruunele:BAABLgAECn8aAAIWAAgJZhzuAABNAgAWAAgJZhzuAABNAgAAAA==.Grü:BAAALgADCgkJCQABLgAECgkJDwAJAAAAAA==.',
Gu='Gutrigor:BAAALgAECgYJDQAAAA==.',
Gw='Gwår:BAAALgAECgYJCAAAAA==.',
['Gó']='Gókee:BAAALgAECgcJDwAAAA==.',
Ha='Habebe:BAAALgAECgYJEAAAAA==.Hair:BAAALgADCgYJBgAAAA==.Hardknockz:BAAALgAECgQJBAABLgAECggJHQAMACoaAA==.Hashbrowns:BAABLgAECn8eAAIPAAcJAiLtBABNAgAPAAcJAiLtBABNAgAAAA==.Hav:BAEBLgAECn8fAAIOAAgJZiNHBAB4AgAOAAgJZiNHBAB4AgAAAA==.Havaker:BAEALgADCgQJBAABLgAECggJHwAOAGYjAA==.Haxxorwyn:BAAALgAECgYJCQAAAA==.',
He='Heartlust:BAAALgAECgcJEAAAAA==.Hellscolon:BAAALgAECgcJEAAAAA==.Hema:BAAALgAECgMJBAABLgAECggJFAAEAOkWAA==.Herakless:BAAALgAECggJCwAAAA==.',
Hi='Highrider:BAAALgADCggJDQAAAA==.Hillybaba:BAAALgADCgcJBwAAAA==.Hitagi:BAAALgADCgQJAwAAAA==.',
Ho='Hoa:BAAALgAECgQJBgAAAA==.Holi:BAAALgAECgEJAQAAAA==.Holicow:BAABLgAFFH8FAAIPAAMJZBjTCAAGAQAPAAMJZBjTCAAGAQAAAA==.Holii:BAAALgAECgEJAQAAAA==.Holybagels:BAAALgAECgYJBgAAAA==.Holyblasts:BAAALgAECgYJBwAAAA==.Holyblowèr:BAABLgAECn8WAAIPAAYJZyQsCgDqAQAPAAYJZyQsCgDqAQAAAA==.Holydisciple:BAAALgADCgEJAQAAAA==.Holynikki:BAAALgAECgYJDwAAAA==.Holytalon:BAAALgADCgMJBAAAAA==.',
Hu='Hummingbird:BAAALgAECggJDQAAAA==.Hungus:BAAALgAECgcJEwAAAA==.Hurtszick:BAAALgADCgEJAgAAAA==.',
Hy='Hybryddin:BAAALgADCgcJBwAAAA==.Hydrotiger:BAAALgAECgEJAQAAAA==.',
['Hà']='Hàra:BAAALgADCgUJCQAAAA==.',
Ia='Iamazombie:BAAALgADCgIJAgAAAA==.Iamholyman:BAAALgADCgYJBgAAAA==.',
Ig='Igotchubruh:BAAALgAECgIJAgAAAA==.',
Ik='Ikitty:BAAALgAECgIJAgAAAA==.',
Im='Imaru:BAAALgADCgYJBgAAAA==.Imnotthtgood:BAAALgADCgkJFAAAAA==.Implosion:BAABLgAECn8gAAIGAAgJkBRyCQDaAQAGAAgJkBRyCQDaAQAAAA==.',
In='Indigolemon:BAABLgAECn8ZAAQUAAgJQBrcBQB2AgAUAAgJQBrcBQB2AgAgAAUJyBYjFgBXAQATAAEJDhwbdQBOAAAAAA==.Inkconjurer:BAABLgAECn8XAAIOAAgJDhalSQBaAgAOAAgJDhalSQBaAgAAAA==.Inouskee:BAAALgADCgUJBQAAAA==.',
Io='Iowned:BAAALgAECgYJEAAAAA==.',
Ir='Irraelina:BAAALgADCgIJAgABLgADCgUJBQAJAAAAAA==.',
Is='Ishundo:BAAALgAECgYJEQAAAA==.',
Iz='Izalithx:BAACLgAFFH8MAAMGAAYJFxzOAQAgAgAGAAYJ6xrOAQAgAgAHAAIJKhppCwCvAAAuAAQKfxgAAwYACAkUIQYqAGgCAAYABwkUIQYqAGgCAAcAAwmHFoIvAP0AAAAA.',
Ja='Jakku:BAAALgAECgcJEAAAAA==.Jamie:BAAALgAECgcJEAAAAA==.Jastiri:BAAALgADCgIJAgAAAA==.',
Je='Jelly:BAABLgAECn8UAAIOAAcJPh2xVgA1AgAOAAcJPh2xVgA1AgAAAA==.',
Ji='Jiinrop:BAEBLgAECn8WAAMHAAcJIxQdIABSAQAGAAYJuRIYbwCCAQAHAAYJXxAdIABSAQAAAA==.Jinah:BAAALgADCgQJBAAAAA==.',
Jo='Johnassassin:BAAALgAECgYJCAABLgAECggJHwAgAAIcAA==.Jollyollie:BAAALgADCgQJBAAAAA==.Jonahkin:BAAALgAECggJEwAAAA==.',
Ju='Judgewapner:BAAALgAECgEJAQAAAA==.Juicelord:BAAALgAECgMJBQAAAA==.Juiya:BAAALgADCgQJBAAAAA==.',
Ka='Kaedes:BAACLgAFFH8GAAMTAAMJAQz8CACdAAATAAIJCgv8CACdAAAgAAEJ7g3uAgBbAAAuAAQKfyMABBMACAlDIFgQAJ4CABMACAmVHlgQAJ4CACAABgmkGeoSAIABABQAAQkIFWctAEEAAAAA.Kaiwai:BAAALgADCgYJBgAAAA==.Kaizoku:BAAALgADCgQJBAAAAA==.Kaladin:BAAALgAECgQJBQAAAA==.Kaldanarys:BAAALgAECgEJAQAAAA==.Kalenlock:BAAALgAECgYJCgAAAA==.Kaleo:BAAALgADCgcJCgAAAA==.Katherrian:BAAALgADCgcJBwABLgAECgkJHgAeALMZAA==.Kathorall:BAABLgAECn8ZAAIeAAgJCRJEDQCeAQAeAAgJCRJEDQCeAQAAAA==.Kavawings:BAAALgAECgMJBAAAAA==.Kawaiihealer:BAABLgAECn8XAAINAAcJtBwYGgALAgANAAcJtBwYGgALAgAAAA==.',
Ke='Keddy:BAAALgADCgMJCQAAAA==.Kemper:BAAALgAECgUJCwAAAA==.Keoua:BAAALgADCgIJAgAAAA==.Kerrs:BAAALgAECgEJAQAAAA==.',
Kh='Khaza:BAAALgADCgMJBgAAAA==.',
Ki='Kidil:BAAALgADCgcJDQAAAA==.Kidneypopper:BAAALgAECgYJBwABLgAECggJHQAOAKghAA==.Kievit:BAAALgAECgcJEAAAAA==.Killá:BAAALgADCgMJAwAAAA==.Kir:BAAALgAECgUJEgAAAA==.',
Kk='Kkrantuq:BAABLgAECn8gAAIhAAgJSBjsAgA4AgAhAAgJSBjsAgA4AgAAAA==.',
Kl='Klarityqt:BAAALgAECgMJAwAAAA==.Klarityx:BAABLgAECn8gAAIOAAkJ7BRxPQCCAgAOAAkJ7BRxPQCCAgAAAA==.',
Ko='Kogadeath:BAAALgAECgEJAQAAAA==.Kogadraco:BAAALgAECgUJBgAAAA==.Komatos:BAABLgAECn8hAAIYAAgJpSQRAQCaAgAYAAgJpSQRAQCaAgAAAA==.Korona:BAABLgAECn8eAAIOAAcJzhetFACcAQAOAAcJzhetFACcAQAAAA==.Korra:BAAALgADCgYJCgAAAA==.',
Kr='Kraptastic:BAAALgADCgEJAQAAAA==.',
Ky='Kylar:BAAALgAECgYJCgABLgAECggJIAAhAEgYAA==.',
['Kê']='Kênsêi:BAAALgAECgMJBQABLgAECggJIAABAO4TAA==.',
['Kô']='Kôan:BAAALgADCgkJEQAAAA==.',
La='Laserbeams:BAAALgAECgQJCAAAAA==.',
Le='Leafyjoe:BAAALgAECgYJBwAAAA==.Lechencaja:BAAALgAECgQJBAABLgAECgYJCQAJAAAAAA==.Legendarybob:BAAALgAECgMJAwAAAA==.Legomyeggö:BAABLgAECn8aAAIEAAcJTBoXVAD1AQAEAAcJTBoXVAD1AQAAAA==.',
Lh='Lhera:BAABLgAECn8aAAMbAAcJSBu8AgCeAQAeAAYJkhzYMwDgAQAbAAcJ/xa8AgCeAQAAAA==.',
Li='Lilglittery:BAAALgADCgYJBgAAAA==.Lilnikki:BAAALgADCgUJCgAAAA==.Lisp:BAAALgADCgYJBgAAAA==.Livathian:BAABLgAECn8YAAIPAAgJTxQPHgA6AQAPAAgJTxQPHgA6AQAAAA==.',
Lo='Lockingdown:BAAALgADCgYJCAAAAA==.Longshotx:BAAALgADCgUJBQAAAA==.Lothuial:BAAALgADCgEJAgAAAA==.',
Lu='Lucellis:BAAALgAECgcJBwAAAA==.Lumira:BAABLgAECn8cAAIeAAgJXhysEwCZAgAeAAgJXhysEwCZAgAAAA==.Lurex:BAAALgADCgEJAgAAAA==.Luzwarlockok:BAAALgAECgcJCAAAAA==.',
Lz='Lzybys:BAAALgADCgYJBgAAAA==.',
Ma='Madris:BAAALgAECgcJEQAAAA==.Maelstroke:BAAALgADCgcJBwAAAA==.Magimagi:BAAALgAECgIJAwAAAA==.Magtharn:BAAALgAECgUJBwAAAA==.Magusdark:BAAALgAECgMJAwAAAA==.Makotoh:BAAALgADCgEJAQAAAA==.Malnorr:BAAALgAECgcJEgAAAA==.Manbeerpig:BAAALgAECgYJCgABLgAECgkJDwAJAAAAAA==.Mandykiinz:BAAALgAECgYJEQAAAA==.Mannimarco:BAAALgADCgEJAQAAAA==.Maryillo:BAACLgAFFH8XAAMUAAYJfRs2AADBAQAUAAYJghY2AADBAQATAAUJVSHMBACeAQAuAAQKfyQAAxQACAlAJJ8CAPwCABQACAkUIZ8CAPwCABMABwmAJKgNAMACAAAA.',
Mc='Mcflurry:BAAALgADCgYJBgAAAA==.',
Me='Medd:BAAALgAECgUJCQAAAA==.Mennil:BAAALgAECgQJBAAAAA==.Meolater:BAABLgAECn8UAAIRAAYJaiAYEQAqAgARAAYJaiAYEQAqAgAAAA==.Meowz:BAAALgADCgUJBQAAAA==.Mesmerise:BAAALgAECgYJDgAAAA==.',
Mh='Mhyrora:BAAALgAECgEJAQAAAA==.',
Mi='Mick:BAAALgADCgcJBwAAAA==.Midorii:BAAALgADCggJCwAAAA==.Mikeygee:BAAALgAECgEJAQABLgAECgUJBwAJAAAAAA==.Mio:BAAALgADCgcJBwAAAA==.Miraya:BAABLgAECn8jAAMGAAgJcxhNMABLAgAGAAgJwxdNMABLAgAHAAQJrQmNOgDKAAAAAA==.Misbehaved:BAAALgADCgUJBQAAAA==.Mishrakthul:BAAALgAECgEJAQAAAA==.Missfear:BAAALgADCgYJDgAAAA==.',
Mm='Mmrsdelaneys:BAAALgADCgEJAgAAAA==.',
Mo='Mokari:BAEBLgAECn8dAAMiAAcJ8R1SAgABAgAeAAcJxhztIgA0AgAiAAcJPxpSAgABAgAAAA==.Mon:BAAALgADCgQJBwAAAA==.Moonfrost:BAAALgAECggJEQAAAA==.Morbidchaos:BAACLgAFFH8KAAIMAAYJlBRAAQC3AQAMAAYJlBRAAQC3AQAuAAQKfxsAAgwACQljIcgFAGkDAAwACQljIcgFAGkDAAAA.Morbius:BAAALgAECgcJEQAAAA==.Morglum:BAABLgAECn8jAAMGAAgJxxi7OQAlAgAGAAgJxxi7OQAlAgAHAAEJAACQbAA7AAAAAA==.Morlog:BAAALgADCgUJBgAAAA==.Mosnar:BAAALgADCgEJAQAAAA==.',
Mu='Muddywalrus:BAAALgAECgIJBQAAAA==.Mukatsuku:BAAALgAECgYJDAAAAA==.Muscida:BAAALgADCgEJAQAAAA==.',
My='Myzas:BAAALgADCgcJBwAAAA==.',
['Mâ']='Mâyüri:BAABLgAECn8dAAMYAAcJHxObCwBCAQAYAAcJHxObCwBCAQAXAAIJYAJ0lABLAAABLgAECggJIAABAO4TAA==.',
Na='Naaldlooshii:BAAALgADCgYJBwABLgAECgIJAwAJAAAAAA==.Naeth:BAABLgAECn8bAAIPAAcJvhxPEQCZAQAPAAcJvhxPEQCZAQAAAA==.Nalrot:BAAALgADCgYJCAABLgAECgYJDgAJAAAAAA==.Narcine:BAABLgAECn8eAAMeAAgJsxlXCADjAQAeAAgJPRhXCADjAQAiAAYJshu2EQCnAQAAAA==.Naví:BAAALgAECgcJDAAAAA==.',
Ne='Necie:BAABLgAECn8eAAIUAAcJyRIqBABEAQAUAAcJyRIqBABEAQABLgABCgEJAQAJAAAAAA==.Neckred:BAAALgADCgEJAQAAAA==.Nedri:BAAALgAECgcJEQAAAA==.Nee:BAABLgAFFH8RAAIXAAYJ8hk3AwCmAQAXAAYJ8hk3AwCmAQAAAA==.Nelor:BAAALgAECgYJCgAAAA==.Nethya:BAAALgADCgMJAwAAAA==.',
Ni='Nibblet:BAAALgADCgEJAQAAAA==.Nightnight:BAAALgAECgYJCQAAAA==.Nikkibear:BAAALgAECgMJBAAAAA==.Nitashal:BAABLgAECn8gAAMRAAkJRh5/AADiAgARAAkJRh5/AADiAgACAAEJwAb8PwAwAAAAAA==.',
No='Nobudagero:BAAALgAECgYJDgAAAA==.Noremac:BAAALgADCgkJGgAAAA==.Norgalis:BAAALgADCgMJBQAAAA==.Nosman:BAAALgAECgMJAwAAAA==.',
Nr='Nrowtuo:BAAALgAECgQJBAAAAA==.',
Ny='Ny:BAAALgADCgEJAwAAAA==.',
['Në']='Nëzükõ:BAAALgADCgkJFgABLgAECggJIAABAO4TAA==.',
Oa='Oathbreaker:BAAALgADCgcJBQAAAA==.',
Ol='Olivabiscuit:BAABLgAECn8VAAMEAAYJ9RT5JQD9AAAEAAYJ9RT5JQD9AAADAAQJEg5UMQC2AAAAAA==.Oliviawildè:BAAALgAECgQJBgAAAA==.',
On='Onepump:BAAALgADCgMJAwAAAA==.',
Oo='Oogiessxd:BAAALgAECgUJEgAAAA==.Oops:BAAALgADCgQJBAAAAA==.',
Or='Orwata:BAAALgADCgcJBwAAAA==.',
Ou='Ouskun:BAAALgADCgQJBQAAAA==.',
Oz='Ozurot:BAAALgAECgYJEgAAAA==.',
Pa='Pakoh:BAABLgAECn8cAAQaAAgJ7iOKGwBfAgAaAAYJGCSKGwBfAgATAAgJdx+8GgAuAgAUAAMJqiKXBAAvAQAAAA==.Palabok:BAAALgAECgEJAgAAAA==.Paladang:BAAALgAECgEJAQABLgAECgEJAgAJAAAAAA==.Paladont:BAAALgAECgMJBwAAAA==.Palmarez:BAAALgADCgUJBAAAAA==.Panchita:BAAALgAECgUJCAAAAA==.Pandemoniúm:BAAALgAECgYJDgAAAA==.Panfriedrice:BAAALgAECgQJAgAAAA==.Pantyblossom:BAAALgAECgYJCgAAAA==.Pasdovqr:BAAALgAECgUJDwAAAA==.',
Pe='Peewees:BAAALgADCgcJBwAAAA==.Pegasus:BAABLgAECn8rAAIHAAgJyRkMBACnAgAHAAgJyRkMBACnAgAAAA==.Persivul:BAAALgAECgUJBgAAAA==.Pewpewz:BAAALgAECgMJAwABLgAECggJHgAFAKcRAA==.',
Ph='Phaeddrus:BAAALgAECgYJCQAAAA==.Phaedross:BAAALgAECgEJAQAAAA==.Pheret:BAAALgAECgYJCwAAAA==.Phobos:BAABLgAECn8fAAIBAAgJ2QZkCwAxAQABAAgJ2QZkCwAxAQAAAA==.Phogood:BAAALgAECgQJBAAAAA==.Phrix:BAAALgAECgMJAwABLgAFFAIJBQACAIwKAA==.',
Pi='Pineapple:BAAALgAECgUJCQABLgAECggJFQAMABIZAA==.Pineapplë:BAABLgAECn8VAAMMAAgJEhmILgBCAgAMAAgJEhmILgBCAgALAAEJBR80awA7AAAAAA==.Pinecone:BAAALgADCgUJBQABLgAECggJFQAMABIZAA==.Pinëapple:BAAALgAECgYJBgABLgAECggJFQAMABIZAA==.Pissdanger:BAAALgAECgEJAQAAAA==.Piñeapple:BAAALgAECgYJDAABLgAECggJFQAMABIZAA==.',
Pl='Plot:BAAALgAECgQJCAAAAA==.',
Po='Poekimaw:BAAALgADCgUJBwAAAA==.Polpo:BAACLgAFFH8NAAIPAAQJvh2bAgBuAQAPAAQJvh2bAgBuAQAuAAQKfxQAAg8ABwnRJB0oAIUCAA8ABwnRJB0oAIUCAAAA.Poppinin:BAAALgAECgYJEwAAAA==.Powerwordhug:BAAALgAECgEJAQAAAA==.',
Pr='Prancer:BAAALgADCgMJAwAAAA==.Prevaleon:BAAALgADCgMJAwAAAA==.Procasual:BAAALgAECgYJDAAAAA==.',
Ps='Psychritic:BAABLgAECn8aAAIOAAgJlB7OCwDzAQAOAAgJlB7OCwDzAQAAAA==.Psyence:BAAALgAECgIJAwABLgAECgcJFQAKAIsRAA==.',
Pt='Pterodactyl:BAAALgAECgYJCgAAAA==.',
Pu='Purpletotem:BAAALgAECgQJBAAAAA==.Purrsnikitty:BAABLgAECn8WAAIeAAYJvhaAEwBfAQAeAAYJvhaAEwBfAQAAAA==.',
['Pà']='Pànzer:BAAALgAECgQJBAAAAA==.',
['Pî']='Pîneapple:BAAALgADCgcJCwABLgAECggJFQAMABIZAA==.',
Qq='Qqmoarnoob:BAAALgADCgUJBQAAAA==.',
Qu='Quillmane:BAAALgAECgQJCAABLgAFFAIJBQACAIwKAA==.Quiza:BAAALgADCgIJAgAAAA==.',
Ra='Raevyn:BAAALgAECgYJDgAAAA==.Ragebate:BAABLgAECn8dAAIMAAgJKhrbLwA8AgAMAAgJKhrbLwA8AgAAAA==.Ragingbohner:BAAALgADCgcJBwAAAA==.Ragingdeath:BAAALgAECgMJAwAAAA==.Ragingson:BAAALgAECgEJAQAAAA==.Rainakamugi:BAAALgADCgcJDAAAAA==.Rakko:BAAALgADCgkJJQAAAA==.Ralphanir:BAABLgAECn8UAAIXAAYJtxb1PgCFAQAXAAYJtxb1PgCFAQAAAA==.Rangi:BAAALgADCgcJCwAAAA==.Raskreia:BAAALgAECgQJBQAAAA==.Rastalarimon:BAAALgAECgIJAwAAAA==.Ravenclaw:BAAALgADCgEJAQAAAA==.Rawdogging:BAAALgADCgYJCgAAAA==.Rawrxd:BAAALgAECgYJBgAAAA==.Raygyu:BAAALgADCgIJAwABLgAECgcJIQAeAOYkAA==.Rayshoots:BAABLgAECn8hAAQeAAcJ5iT6FwB5AgAeAAcJ5iT6FwB5AgAiAAMJLQrJFAA5AAAbAAEJhgAXnAAMAAAAAA==.',
Re='Realkaleo:BAAALgADCgYJDAABLgADCgcJCgAJAAAAAA==.Rebekil:BAABLgAECn8WAAMTAAcJzQgpSAAMAQATAAcJzQgpSAAMAQAaAAYJPQRMhQDMAAAAAA==.Rediline:BAAALgAECgUJBwAAAA==.Rekkfest:BAAALgADCgMJAwAAAA==.Rexari:BAAALgADCgkJFQAAAA==.Rezmae:BAAALgADCgEJAgAAAA==.Reznàp:BAAALgADCgUJBQAAAA==.',
Rh='Rheba:BAAALgADCgEJAQAAAA==.',
Ri='Riniedaze:BAAALgADCgcJBQAAAA==.Rinrin:BAAALgADCgYJBgAAAA==.Riot:BAAALgADCgYJBgAAAA==.Risotto:BAAALgADCgcJBwAAAA==.',
Ro='Roron:BAAALgAECgIJBwAAAA==.Rothgar:BAAALgADCgEJAQAAAA==.Roxy:BAAALgAECgUJBQAAAA==.',
Rr='Rrainmann:BAAALgADCgEJAQAAAA==.',
Ru='Rubmaps:BAAALgADCgUJBQAAAA==.',
Ry='Ryujin:BAAALgADCggJDwAAAA==.',
Sa='Sabi:BAAALgAECgYJEgAAAA==.Sadboy:BAAALgAECgQJBAAAAA==.Sadface:BAAALgAECgQJBAAAAA==.Safetyspork:BAAALgAECgEJAgAAAA==.Sagë:BAAALgAECgQJBAAAAA==.Salsa:BAAALgAECgEJAQAAAA==.Samunzo:BAAALgADCgQJBQAAAA==.',
Sc='Schobe:BAAALgADCgEJAgABLgAECgIJAwAJAAAAAA==.Schönen:BAAALgAECgYJDAAAAA==.Scojo:BAAALgAECgEJAQAAAA==.Scârecrow:BAAALgAECgYJDgAAAA==.',
Se='Seishouu:BAAALgADCgUJBQAAAA==.Sejien:BAAALgAECgUJDwAAAA==.Sermet:BAAALgADCgcJCgABLgAECgYJFQAMAGYcAA==.Serous:BAABLgAECn8ZAAIFAAcJGhxqBwCsAQAFAAcJGhxqBwCsAQAAAA==.Setal:BAACLgAFFH8FAAMCAAIJjAqPAgBVAAABAAIJtgawHACLAAACAAIJjAqPAgBVAAAuAAQKfx4AAwEACAlyG1YPAIECAAEACAnlGlYPAIECAAIABwkfGFYPAOUBAAAA.Sevrik:BAABLgAECn8iAAIGAAgJ/BtNCgDOAQAGAAgJ/BtNCgDOAQAAAA==.',
Sh='Shadowbruin:BAAALgADCgYJBgAAAA==.Shammycammy:BAAALgADCgkJCgAAAA==.Shaoling:BAAALgADCgEJAQAAAA==.Sharadra:BAAALgAECgYJCAAAAA==.Shecklethief:BAAALgAECgUJBgAAAA==.Shimmyx:BAAALgADCgYJCAAAAA==.Shinizokonai:BAAALgADCgQJBAAAAA==.Shinydude:BAAALgAECgMJAwAAAA==.Shogunz:BAAALgAECgMJAwAAAA==.Shroudedmoon:BAACLgAFFH8OAAIjAAUJYCEiAACaAQAjAAUJYCEiAACaAQAuAAQKfxgAAyMACAlBJJ0BAAYDACMACAlBJJ0BAAYDACEABAlzGQcJAOkAAAAA.',
Si='Silk:BAABLgAECn8UAAMjAAYJyRIaAwBQAQAjAAYJyRIaAwBQAQAQAAEJ+QdxXwA3AAAAAA==.Sinapaladin:BAAALgAECgYJBwAAAA==.',
Sk='Skroh:BAAALgADCgEJAQAAAA==.Skwsham:BAABLgAECn8WAAIYAAkJXRmXAgAtAgAYAAkJXRmXAgAtAgAAAA==.',
Sl='Slabbcrakle:BAAALgADCgcJCgAAAA==.Slabbhammer:BAAALgAECgYJEAAAAA==.Slaykanit:BAAALgAECgQJBQAAAA==.',
Sm='Smooshednewt:BAAALgAECgQJDAAAAA==.',
Sn='Sneakyknight:BAAALgAECgYJCgAAAA==.',
So='Sobaley:BAAALgADCgQJBAAAAA==.Soggysausage:BAAALgAECgYJBwAAAA==.Sohvar:BAAALgAECgYJCwAAAA==.Sophira:BAAALgAECgcJEQAAAA==.',
Sp='Sparkels:BAAALgADCgYJBgAAAA==.Spectre:BAAALgADCgkJCAAAAA==.Spehk:BAAALgADCgcJDgABLgAECggJGgAQALcVAA==.Speknawz:BAABLgAECn8aAAIQAAgJtxWbBgB+AQAQAAgJtxWbBgB+AQAAAA==.Splatzill:BAAALgAECgQJBAABLgAFFAEJAQAJAAAAAA==.Spoiledangel:BAABLgAECn8WAAINAAYJ+x5qBgCwAQANAAYJ+x5qBgCwAQAAAA==.Spookyhallow:BAABLgAECn8UAAINAAgJ6wj+MQB4AQANAAgJ6wj+MQB4AQAAAA==.Springz:BAABLgAFFH8YAAIdAAcJRh0yAQBAAgAdAAcJRh0yAQBAAgAAAA==.',
St='Starryniight:BAABLgAECn8VAAIGAAYJugmlIgARAQAGAAYJugmlIgARAQAAAA==.Stereodh:BAABLgAECn8cAAIMAAcJoxU5FQBTAQAMAAcJoxU5FQBTAQAAAA==.',
Su='Suetang:BAAALgAECgEJAQAAAA==.Supanova:BAAALgAECgYJDQAAAA==.Surwick:BAABLgAECn8fAAIkAAgJHA3cBgAeAQAkAAgJHA3cBgAeAQAAAA==.Sussybaka:BAAALgADCgUJBQAAAA==.',
Sv='Svelus:BAAALgAECgYJEAABLgAFFAUJDgAjAGAhAA==.',
Sw='Swingin:BAAALgAECgYJDgAAAA==.Swishers:BAAALgADCgEJAQAAAA==.',
Sy='Synapticvoid:BAAALgAECgYJCgAAAA==.',
['Sï']='Sïxx:BAAALgADCgMJAwAAAA==.',
Ta='Tanurhide:BAAALgADCgQJBgAAAA==.Tapdat:BAACLgAFFH8HAAMGAAMJtQtuEwDKAAAGAAMJ8ghuEwDKAAAHAAEJwg7qFQBTAAAuAAQKfyMAAwcACAnyHFQLAAsCAAcABwl8GVQLAAsCAAYABwkFH9hIAPABAAAA.Tarram:BAAALgAECgYJCAAAAA==.Tartin:BAABLgAECn8aAAITAAgJ0x9XDgC4AgATAAgJ0x9XDgC4AgAAAA==.Taurenmill:BAAALgAECgcJDQAAAA==.',
Te='Teapsy:BAAALgAECgYJDQAAAA==.Teener:BAAALgADCgQJBAAAAA==.Temres:BAABLgAECn8VAAQMAAYJZhz3EAB9AQAMAAYJZhz3EAB9AQAKAAUJKxRZFQABAQALAAEJfgbSdQAvAAAAAA==.Tendermulva:BAABLgAECn8gAAIIAAgJ0gmQAQB/AQAIAAgJ0gmQAQB/AQAAAA==.Tentoestwo:BAAALgAECgYJCgAAAA==.Tenzzo:BAAALgAECgUJBQAAAA==.Terekk:BAAALgADCgcJEwAAAA==.Terna:BAAALgADCgEJAQAAAA==.Tevashi:BAAALgAECgYJCwAAAA==.',
Th='Thannin:BAAALgAECgMJBgAAAA==.Tharekon:BAAALgAFFAEJAQAAAA==.Thedrink:BAAALgAECgEJAgAAAA==.Thermox:BAAALgAECgYJBwAAAA==.Thesauce:BAACLgAFFH8LAAIfAAQJRCNCAAClAQAfAAQJRCNCAAClAQAuAAQKfyAAAh8ACAmtJWACAHgDAB8ACAmtJWACAHgDAAAA.Thesmallman:BAAALgADCgcJDgAAAA==.Thexcurse:BAAALgADCgcJBwAAAA==.Thrikal:BAABLgAECn8eAAILAAcJBxfvGwDhAQALAAcJBxfvGwDhAQAAAA==.Throh:BAAALgADCgEJAQAAAA==.Thugd:BAAALgAECgQJBAAAAA==.',
Ti='Tiadalma:BAAALgAECgEJAQAAAA==.Tiek:BAABLgAECn8dAAIFAAcJExH3CQB/AQAFAAcJExH3CQB/AQAAAA==.Tindissa:BAAALgAECgMJAwAAAA==.Tivis:BAAALgAECgYJEgAAAA==.',
To='Toastydemon:BAABLgAECn8XAAIMAAcJlQ3IJADtAAAMAAcJlQ3IJADtAAAAAA==.Tokedope:BAAALgAECgQJBwAAAA==.Tomoe:BAAALgADCgkJCQAAAA==.Tomsmg:BAAALgAFFAEJAQAAAA==.Tonen:BAABLgAECn8VAAIFAAYJARajEwAEAQAFAAYJARajEwAEAQAAAA==.Toofs:BAAALgAECgUJDwAAAA==.Torno:BAAALgAECgEJAQAAAA==.Toxifay:BAAALgAECgMJAwAAAA==.Toywar:BAAALgADCgcJBgAAAA==.',
Ts='Tsilatra:BAAALgAECgQJBAAAAA==.',
Tu='Tufluk:BAAALgAECgYJEgAAAA==.',
Tw='Twelevepeers:BAAALgAECgQJBAAAAA==.Twigs:BAAALgAECgkJCAAAAA==.',
['Tì']='Tìõ:BAABLgAECn8gAAIBAAgJ7hPDGAAJAgABAAgJ7hPDGAAJAgAAAA==.',
['Tô']='Tôms:BAAALgAECggJEwAAAA==.',
['Tö']='Töms:BAAALgADCgYJCAAAAA==.',
Ud='Udderlegend:BAAALgADCgcJEAAAAA==.',
Ug='Ughtismo:BAAALgADCgYJBgAAAA==.',
Ul='Ulrikan:BAAALgADCgQJBAAAAA==.Ultarok:BAAALgAECgYJCAAAAA==.',
Un='Undeadban:BAAALgAECgEJAQAAAA==.Unfiltered:BAAALgAECgIJAgAAAA==.Unwanted:BAAALgAECgYJDQAAAA==.',
Up='Upstream:BAAALgADCgYJCwAAAA==.',
Us='Ushii:BAAALgAECgEJAQAAAA==.',
Va='Vaelindar:BAAALgADCgUJBgAAAA==.Vakarians:BAAALgADCgYJCQAAAA==.Valei:BAAALgAECgQJBAAAAA==.Valor:BAACLgAFFH8HAAIEAAMJWRd6JQAAAQAEAAMJWRd6JQAAAQAuAAQKfx0AAwQACQnbHp0gAL8CAAQACAlIIp0gAL8CACUAAQneBigIAEoAAAAA.Vampirevic:BAAALgADCgMJAwAAAA==.Vansanssra:BAAALgADCgEJAQAAAA==.Varcoh:BAABLgAECn8cAAMNAAgJdwuNMgB2AQANAAgJdwuNMgB2AQAcAAIJUgQIWgBQAAAAAA==.',
Ve='Velixar:BAAALgAECgEJAQAAAA==.Veloxen:BAAALgADCgYJBgAAAA==.Venthyr:BAAALgADCgEJAQAAAA==.Verikost:BAAALgADCgEJAQAAAA==.',
Vi='Vinda:BAABLgAECn8eAAIcAAcJtxReCABwAQAcAAcJtxReCABwAQAAAA==.',
Vl='Vladious:BAABLgAECn8dAAQGAAcJwh5PCADtAQAGAAYJnh5PCADtAQAHAAIJvB1QSACWAAAIAAEJAABtKABQAAAAAA==.',
Vy='Vynd:BAAALgAECgYJDQAAAA==.Vynllandis:BAAALgADCgMJAwAAAA==.',
Wa='Wallo:BAABLgAECn8eAAIFAAgJpxHkBwCjAQAFAAgJpxHkBwCjAQAAAA==.Warglaivez:BAAALgAECgQJCQAAAA==.Washedbolt:BAAALgAECgMJBwAAAA==.Washedpyro:BAAALgAECgcJCQAAAA==.Watchscotch:BAAALgADCgkJFQABLgAECgYJCwAJAAAAAA==.Wayfairkid:BAAALgAECgYJCgAAAA==.',
We='Werken:BAAALgAECgEJAQAAAA==.',
Wh='Whyetee:BAABLgAECn8nAAMQAAgJ4CK9CwDaAgAQAAgJCyK9CwDaAgAjAAIJzyBsFAC2AAAAAA==.',
Wi='Willywonkas:BAAALgADCgIJAgAAAA==.Windowlicker:BAAALgADCgEJAQAAAA==.Wineo:BAABLgAECn8cAAITAAgJlx+pDQDAAgATAAgJlx+pDQDAAgAAAA==.Wizzwee:BAAALgAECgIJAgABLgAECggJGAALAK8cAA==.',
Wo='Woa:BAAALgAECgEJAQAAAA==.Wonder:BAAALgAECgIJAwAAAA==.Woofwoofwoof:BAABLgAECn8ZAAIOAAcJYQvbJAA9AQAOAAcJYQvbJAA9AQAAAA==.Worn:BAAALgADCgQJBAAAAA==.Worthlesshoe:BAAALgADCgIJBAABLgADCgUJBQAJAAAAAA==.',
Wr='Wraithwok:BAAALgADCgYJBgAAAA==.',
['Wà']='Wàll:BAAALgADCgMJAwAAAA==.',
['Wå']='Wåffle:BAAALgADCgMJAwAAAA==.',
Xa='Xasther:BAABLgAECn8eAAIPAAgJkCXCCwAwAwAPAAgJkCXCCwAwAwAAAA==.Xav:BAAALgADCgkJDAAAAA==.',
Xe='Xenophilius:BAAALgAECgYJCQAAAA==.Xeruk:BAAALgAECgYJBwAAAA==.',
Ya='Yasha:BAAALgADCgEJAQABLgAECgUJCQAJAAAAAA==.',
Ye='Yearsfade:BAAALgADCgMJAwAAAA==.',
Yu='Yuka:BAAALgADCgUJBQAAAA==.Yulok:BAAALgAECgMJAwABLgAFFAYJDAAGABccAA==.Yumí:BAABLgAECn8bAAMiAAgJ9BrKCQBAAgAiAAgJ9BrKCQBAAgAbAAEJywm9iQAxAAAAAA==.Yurgling:BAAALgAECgMJBAAAAA==.',
Za='Zaberra:BAAALgADCgMJAwABLgAECgcJEQAJAAAAAA==.Zanarkand:BAAALgAECgQJBAAAAA==.Zarivara:BAAALgAECgEJAgAAAA==.',
Ze='Zepha:BAAALgADCgIJAQAAAA==.',
Zi='Zib:BAAALgAECgMJAwAAAA==.Zibrina:BAAALgADCgUJCAAAAA==.Zieg:BAAALgADCgIJAgABLgAECgkJDwAJAAAAAA==.Zina:BAAALgAECgEJAQAAAA==.Zitish:BAAALgADCgEJAQAAAA==.',
Zu='Zuko:BAAALgADCgEJAQAAAA==.',
['Ço']='Çookiemonstr:BAAALgADCgkJDwAAAA==.',
['Ëy']='Ëyë:BAAALgAECgYJCgAAAA==.',
['Ñi']='Ñina:BAAALgAECgUJCQAAAA==.',
['ßu']='ßutterworth:BAAALgADCgEJAQAAAA==.',
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

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

local lookup = {'Priest-Shadow','DemonHunter-Devourer','Hunter-Survival','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Druid-Balance','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Monk-Brewmaster','Mage-Frost','Druid-Restoration','Druid-Guardian','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Enhancement','Rogue-Subtlety','Paladin-Protection','Priest-Discipline','Warrior-Protection','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw','Mage-Fire','Monk-Mistweaver',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aazmon:BAACLgAFFH8LAAIBAAQJ0BULBwBWAQABAAQJ0BULBwBWAQAuAAQKfyIAAgEACAnyI4YGACQDAAEACAnyI4YGACQDAAAA.',
Ab='Abinjahmin:BAAALgAECgUJBwAAAA==.',
Ac='Acy:BAACLgAFFH8GAAICAAIJ0xbJLAChAAACAAIJ0xbJLAChAAAuAAQKfx0AAgIABgmuH8w4ABECAAIABgmuH8w4ABECAAAA.',
Ae='Aeman:BAAALgAECgcJEwAAAA==.Aeropunk:BAAALgAECgQJBQAAAA==.Aerys:BAAALgADCgEJAQAAAA==.Aerøs:BAAALgAECgYJDgAAAA==.Aesthetic:BAAALgAECgYJCQAAAA==.',
Af='Afflicting:BAAALgAECgEJBQAAAA==.',
Ag='Aggiz:BAAALgAECgQJBgABLgAECgcJGwADANUaAA==.',
Aj='Ajaxprime:BAAALgAFFAIJBAAAAA==.',
Al='Alabamajane:BAAALgAECgYJDgAAAA==.Alazurindron:BAAALgAECgMJAwAAAA==.Alesîa:BAAALgAECgQJBQAAAA==.Alfabika:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Alittlesalty:BAABLgAECn8iAAIFAAgJOhuwFQBjAgAFAAgJOhuwFQBjAgAAAA==.Alnec:BAAALgAECgMJBQAAAA==.Alronn:BAAALgAECgMJBQAAAA==.Alustrious:BAAALgADCgUJBQABLgAFFAIJBQAGAIgiAA==.Alzim:BAACLgAFFH8HAAIHAAMJ2hOzEAD0AAAHAAMJ2hOzEAD0AAAuAAQKfygAAgcACAmSJNQEAGcCAAcACAmSJNQEAGcCAAAA.',
Am='Amrën:BAACLgAFFH8GAAIIAAMJ4hPACgDgAAAIAAMJ4hPACgDgAAAuAAQKfyUAAwgACAlnEcAmALcBAAgACAlnEcAmALcBAAEABwmIC7wWAEkBAAAA.',
An='Animosityy:BAAALgADCgYJBgAAAA==.Antitheist:BAAALgADCgQJBAAAAA==.Antitoo:BAAALgAECgEJAQAAAA==.Antitoos:BAAALgADCggJDAAAAA==.',
Ar='Aragos:BAAALgAECgYJEwAAAA==.Arazarion:BAAALgADCgIJAgAAAA==.Arcelon:BAAALgAECgIJAwAAAA==.Arcelorz:BAAALgAECgkJBwAAAA==.Arlesia:BAAALgAECgEJAQAAAA==.Arvz:BAABLgAECn8UAAMJAAYJBBwcLwClAQAJAAYJBBwcLwClAQAKAAEJSAdnnwAxAAAAAA==.Arwenatak:BAAALgAECgYJCgAAAA==.',
As='Ashlari:BAAALgAECgUJDAAAAA==.Ashter:BAAALgAECgQJBAAAAA==.Asmuun:BAAALgADCgcJBwABLgAFFAQJCwABANAVAA==.',
At='Athren:BAABLgAECn8dAAILAAcJzyIHEQA0AgALAAcJzyIHEQA0AgAAAA==.Atøne:BAAALgADCgUJCQAAAA==.',
Av='Averyee:BAAALgADCgQJBAAAAA==.',
Az='Azealiabanks:BAAALgADCggJDQAAAA==.Azmun:BAAALgAFFAEJAQABLgAFFAQJCwABANAVAA==.Azzmun:BAAALgAFFAQJBAABLgAFFAQJCwABANAVAA==.',
Ba='Babyløn:BAAALgADCgUJBQAAAA==.Badfish:BAAALgADCgYJBgABLgAECgcJEgAEAAAAAA==.Balgart:BAAALgAECgQJBAAAAA==.Ballador:BAAALgADCgQJBAAAAA==.Barnëy:BAAALgADCgEJAQAAAA==.Barraga:BAAALgADCgMJAwABLgAECggJJQAMAO4bAA==.Barragadin:BAAALgADCgMJAwABLgAECggJJQAMAO4bAA==.Barreta:BAAALgADCgYJCQAAAA==.Basle:BAAALgADCgYJBgAAAA==.',
Be='Beauregaard:BAAALgADCgUJBQAAAA==.Beck:BAABLgAECn8dAAIKAAgJPQQSMQD6AAAKAAgJPQQSMQD6AAAAAA==.Beefykin:BAAALgADCgkJEAAAAA==.Beeowin:BAAALgADCgcJDwAAAA==.Beevoker:BAABLgAECn8VAAQMAAYJqBQSIgDzAAAMAAYJYxISIgDzAAANAAQJBBSTKgDJAAAOAAMJ0wumOgCVAAAAAA==.Bellamuerté:BAAALgAECgcJCgABLgAECgcJEwAEAAAAAA==.Bellámuerté:BAAALgAECgcJEwAAAA==.Bertox:BAAALgAFFAIJAgAAAA==.',
Bi='Bigdrandyy:BAAALgAECgYJCAAAAA==.Biggnz:BAAALgADCgcJBAAAAA==.Biggsx:BAAALgADCgYJBwAAAA==.Bijali:BAAALgADCgUJBQAAAA==.Bika:BAAALgAECgIJAgAAAA==.Binhad:BAAALgAECgUJDQAAAA==.Birdallas:BAABLgAECn8WAAIHAAgJYRfvHQAQAgAHAAgJYRfvHQAQAgAAAA==.Bizk:BAAALgAECgMJAwAAAA==.',
Bl='Bloodlordzz:BAAALgAECgYJBgAAAA==.Bloodlusst:BAABLgAECn8kAAIIAAgJhBR4EQCUAQAIAAgJhBR4EQCUAQAAAA==.Bloodreina:BAABLgAECn8cAAIPAAgJ2B60DQDoAgAPAAgJ2B60DQDoAgAAAA==.Blueburry:BAAALgADCgEJAQAAAA==.',
Bo='Bob:BAABLgAECn8aAAMQAAgJzRn+GQDaAQAQAAcJzRn+GQDaAQARAAEJAAA3IgBpAAAAAA==.Bobatea:BAAALgAECgkJCQAAAA==.Bonelee:BAABLgAECn8fAAISAAgJBQwmNAB/AQASAAgJBQwmNAB/AQAAAA==.Boomtang:BAAALgAECgEJAQAAAA==.Boshuun:BAAALgAECgMJAwAAAA==.',
Br='Brahm:BAAALgAECgMJBQABLgAECgcJFQAJABAaAA==.Brainrotkid:BAACLgAFFH8LAAITAAUJ7AocIABGAQATAAUJ7AocIABGAQAuAAQKfzEAAhMACQlQICoRAEEDABMACQlQICoRAEEDAAAA.Bravoker:BAABLgAECn8lAAMMAAgJ7hvjBgArAgAMAAgJ7hvjBgArAgAOAAIJFATNQwBQAAAAAA==.Brdua:BAAALgADCgUJBQAAAA==.Breeze:BAAALgADCgEJAQABLgAECgYJBQAEAAAAAA==.Briale:BAAALgAECgEJAgAAAA==.Brosrus:BAAALgAECgUJCgABLgAECggJHgATAMsbAA==.',
Bu='Budtender:BAABLgAECn8dAAMUAAgJGxHqQQCaAQAUAAgJGxHqQQCaAQAVAAEJJggpOAAXAAAAAA==.Bulkam:BAABLgAECn8ZAAMFAAgJAg1oRwBaAQAFAAgJAg1oRwBaAQALAAIJkgV9JQFUAAAAAA==.Bulldan:BAAALgADCgcJCAAAAA==.Burbuja:BAABLgAECn8nAAQOAAgJkR8PBgDkAgAOAAgJkR8PBgDkAgAMAAgJUyHSAgC2AgANAAUJnxVtHABNAQAAAA==.Burr:BAAALgADCgYJBgAAAA==.',
Bz='Bzap:BAAALgADCgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgUJBQAAAA==.',
Ca='Callabash:BAABLgAECn8ZAAMKAAcJMQ9oQwB0AQAKAAcJMQ9oQwB0AQAJAAMJCwe6cACAAAAAAA==.Callahan:BAAALgAECgMJBAAAAA==.Cameltotemx:BAAALgAECgQJBwAAAA==.Canuimagine:BAAALgADCgYJBgAAAA==.Capa:BAAALgADCggJEQAAAA==.Captórofsin:BAAALgADCgIJAgAAAA==.Catchacharge:BAAALgADCgQJBAAAAA==.Cav:BAABLgAECn8fAAQWAAkJ/hUSIwALAgAWAAgJmBUSIwALAgAXAAQJ9g2iRQACAQADAAUJKAWcFwABAQAAAA==.',
Ce='Celarena:BAABLgAECn8bAAIYAAYJEwQzEACwAAAYAAYJEwQzEACwAAAAAA==.',
Ch='Chabil:BAAALgAECgQJCQAAAA==.Charcol:BAAALgAECgcJDAAAAA==.Chasen:BAAALgADCgQJBQAAAA==.Cheeziit:BAABLgAECn8hAAMVAAkJWhusAgAwAgAVAAkJWhusAgAwAgAUAAIJGQpbuwBPAAAAAA==.Chomrogg:BAABLgAECn8UAAMZAAYJwx9gDwAfAQAaAAYJMBt3ggB9AQAZAAQJEx9gDwAfAQAAAA==.Chop:BAAALgAECgYJEQAAAA==.Chopzzpala:BAAALgAECgQJBAAAAA==.Chunked:BAAALgAECgYJCgAAAA==.Chyp:BAABLgAECn8iAAILAAgJIhksHwDPAQALAAgJIhksHwDPAQAAAA==.Chzdh:BAAALgAECgcJBwABLgAECggJEAAEAAAAAA==.Chzpld:BAAALgAECggJEAAAAA==.',
Ci='Cichadin:BAABLgAECn8fAAICAAgJlg/kTADBAQACAAgJlg/kTADBAQABLgAFFAYJGAAQAHcZAA==.Cichorì:BAACLgAFFH8YAAQQAAYJdxlfAQAzAgAQAAYJdxlfAQAzAgAYAAIJEQhKDQCjAAARAAEJZABTBQBXAAAuAAQKfyoAAxAACQkxIQENABIDABAACQmLGwENABIDABgABwmNHVgGAGoCAAAA.Cipa:BAAALgAECgMJBAAAAA==.',
Cl='Clae:BAABLgAECn8YAAIaAAgJZx4HPABHAgAaAAgJZx4HPABHAgAAAA==.Clone:BAAALgADCgkJCQAAAA==.',
Co='Cobramaxima:BAAALgAECgEJAQAAAA==.Colmer:BAABLgAECn8UAAIQAAYJzhZONwBPAQAQAAYJzhZONwBPAQAAAA==.Coochy:BAAALgAECgYJCgAAAA==.Cotten:BAAALgAECgIJAgAAAA==.',
Cr='Crispriest:BAAALgAFFAEJAgAAAA==.Crockito:BAACLgAFFH8aAAIJAAgJLSJCAADbAgAJAAgJLSJCAADbAgAuAAQKfx4AAgkACQl2JkcAAPQDAAkACQl2JkcAAPQDAAAA.Cryi:BAAALgADCggJDQAAAA==.',
Cu='Cub:BAAALgADCgMJAwAAAA==.',
Cy='Cymist:BAACLgAFFH8KAAIUAAQJxRepDAA/AQAUAAQJxRepDAA/AQAuAAQKfx8AAhQACQmoIKsMANgCABQACQmoIKsMANgCAAAA.',
['Cî']='Cîpa:BAAALgAECgMJBAAAAA==.',
Da='Dabu:BAAALgAECgcJEgAAAA==.Dak:BAAALgAECgYJEwAAAA==.Dampening:BAAALgAECgUJCgAAAA==.Dantar:BAABLgAECn8iAAQJAAgJCwjlOABtAQAJAAgJCwjlOABtAQAbAAYJJQUHGwAZAQAKAAYJGAJwgwCGAAAAAA==.Daroll:BAAALgADCgIJAgAAAA==.Darthidan:BAABLgAECn8cAAILAAcJGxASQwBBAQALAAcJGxASQwBBAQAAAA==.Darthir:BAAALgAECggJDwAAAA==.Daìsy:BAABLgAECn8eAAMUAAgJARXDHACaAQAUAAgJARXDHACaAQAHAAMJ8RRyWwC1AAAAAA==.',
De='Deadphen:BAAALgADCgIJAgAAAA==.Deathscythe:BAAALgADCgEJAQAAAA==.Delaroz:BAAALgAECgYJCgAAAA==.Demonbourne:BAAALgADCgEJAQAAAA==.Demonphen:BAAALgAFFAEJAQABLgAFFAMJBwAcAFseAA==.Depoprovera:BAABLgAECn8qAAIdAAkJqQ2qCACFAQAdAAkJqQ2qCACFAQAAAA==.Deqz:BAABLgAECn8iAAQDAAcJVCHTBQAXAgADAAcJNh3TBQAXAgAWAAcJnRdELADKAQAXAAYJxR3wGwC4AQAAAA==.Desmurdius:BAAALgADCgQJBAAAAA==.Destan:BAABLgAECn8VAAIVAAYJpxCsFAAmAQAVAAYJpxCsFAAmAQAAAA==.Destroy:BAAALgADCgQJBAAAAA==.',
Dh='Dhoko:BAABLgAECn8lAAILAAgJNwltOABiAQALAAgJNwltOABiAQAAAA==.',
Di='Diewithonor:BAAALgAECgYJBgAAAA==.Dilox:BAABLgAECn8gAAIIAAgJtxgZIwDMAQAIAAgJtxgZIwDMAQAAAA==.Dirtyshammy:BAAALgAECgIJBAAAAA==.Disaaya:BAABLgAECn8gAAIXAAgJsg5hIACeAQAXAAgJsg5hIACeAQAAAA==.Disbizch:BAAALgAECgQJBwAAAA==.',
Do='Dokromaa:BAABLgAECn8jAAIaAAgJmx2gGgDoAQAaAAgJmx2gGgDoAQAAAA==.Dominic:BAAALgADCgcJCAAAAA==.Doodlebug:BAACLgAFFH8QAAIZAAUJ0RNRCAAWAQAZAAUJ0RNRCAAWAQAuAAQKfyoAAhkACAmbHygEAAcCABkACAmbHygEAAcCAAAA.Dooshrocket:BAAALgAECgMJBAAAAA==.Dorck:BAAALgAECgMJAwAAAA==.Dorzan:BAAALgADCgYJDAAAAA==.Dotix:BAAALgADCgYJCgAAAA==.Doughdappy:BAAALgAECgMJBAAAAA==.Doxxz:BAAALgAECgYJCAABLgAECgcJDQAEAAAAAA==.',
Dp='Dpaw:BAAALgAECgIJAgAAAA==.',
Dr='Dracuujin:BAAALgAECgYJCwABLgAFFAUJEAAeACQhAA==.Draeyen:BAAALgAECgEJAwAAAA==.Dragonballs:BAAALgAECgMJAwAAAA==.Dralioli:BAABLgAECn8XAAMFAAcJ3gWUMADIAAAFAAcJ3gWUMADIAAALAAYJyQH3lQB5AAAAAA==.Dreadloccs:BAACLgAFFH8IAAMQAAQJihaNEwBOAQAQAAQJ/RWNEwBOAQAYAAEJIga9GABMAAAuAAQKfxwAAxgACQn4HgAdAGYBABgABAlhHgAdAGYBABAABQlTH46WACsBAAAA.Dreanil:BAABLgAECn8eAAMKAAgJSBp5HAA1AgAKAAgJSBp5HAA1AgAbAAEJiwRWLgAtAAAAAA==.Drroog:BAAALgADCgMJAwABLgADCgYJCgAEAAAAAA==.Druidesse:BAAALgADCgUJBQABLgAECgIJAgAEAAAAAA==.Drék:BAAALgADCgUJBQAAAA==.',
Du='Durbekbek:BAAALgADCgcJBwAAAA==.Durond:BAAALgAECgQJBgAAAA==.',
Dw='Dwarfsize:BAAALgAFFAIJAgAAAA==.',
Dy='Dyksuckie:BAAALgADCgUJBQABLgAECggJHAAPANgeAA==.',
Dz='Dzievana:BAAALgAECgQJBAAAAA==.',
['Dâ']='Dârn:BAABLgAECn8iAAMQAAgJOSDqDQA8AgAQAAcJOSDqDQA8AgARAAEJAACLIQBsAAAAAA==.',
Ea='Earthygirthy:BAABLgAECn8YAAIfAAcJtyOSAwBQAgAfAAcJtyOSAwBQAgAAAA==.Eaumz:BAAALgAECgEJAQAAAA==.',
Ed='Edron:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.Edwin:BAAALgAECgcJBwAAAA==.',
Ei='Eigenbra:BAACLgAFFH8GAAIWAAMJjRcECQDxAAAWAAMJjRcECQDxAAAuAAQKfxUAAxYACAniGFwHAG4BABYACAniGFwHAG4BAAMABAn8AyAjAIMAAAAA.',
El='Elissra:BAAALgAFFAEJAQAAAA==.Elori:BAAALgADCgIJAgAAAA==.Elvispræstly:BAAALgAECgQJDAAAAA==.',
Em='Emodeqz:BAAALgAECgQJBwAAAA==.',
En='Endfist:BAAALgAECgkJAwAAAA==.',
Ep='Epilepsy:BAAALgAECgQJBAAAAA==.',
Er='Eroy:BAAALgADCgUJBQAAAA==.Erzza:BAABLgAECn8eAAIFAAgJ1yLRBQCJAgAFAAgJ1yLRBQCJAgAAAA==.',
Es='Esotericzeo:BAAALgADCgIJAgAAAA==.',
Eu='Eupherine:BAABLgAECn8nAAIIAAgJsyQLAQA+AwAIAAgJsyQLAQA+AwAAAA==.',
Ev='Evildrood:BAABLgAECn8cAAIHAAgJlxkBCAAUAgAHAAgJlxkBCAAUAgAAAA==.',
Ey='Eyegouge:BAAALgADCgYJCwAAAA==.',
Fa='Fatsmellycow:BAAALgAECgYJEQAAAA==.',
Fe='Felwags:BAAALgAECgMJAwAAAA==.Fendrag:BAABLgAECn8YAAIfAAgJWxs5BgDtAQAfAAgJWxs5BgDtAQAAAA==.',
Fl='Flappii:BAAALgADCgkJDgAAAA==.Flappyfuros:BAABLgAECn8aAAIOAAgJ6wmhHQCWAQAOAAgJ6wmhHQCWAQAAAA==.Flaster:BAAALgAECgQJBQAAAA==.Fluffykat:BAABLgAECn8nAAIHAAgJNBfYDAC/AQAHAAgJNBfYDAC/AQAAAA==.',
Fo='Foonnz:BAAALgAECgcJCQAAAA==.Fosho:BAACLgAFFH8cAAMJAAYJ5xaoAgCtAQAJAAYJ5xaoAgCtAQAKAAEJ3w3IKgBRAAAuAAQKfzoAAwkACQmXItUAADkDAAkACQmXItUAADkDAAoABwm8F64kAAMCAAAA.Fourgot:BAABLgAECn8XAAMQAAcJVBCeZgCXAQAQAAcJVBCeZgCXAQAYAAMJMgewTQCFAAAAAA==.Fourwhat:BAAALgADCgQJBQAAAA==.',
Fr='Fraud:BAAALgAECgYJBgABLgAECggJHAAPANgeAA==.Freddysjr:BAAALgADCgMJAwAAAA==.Freelvlsvnty:BAAALgAECgEJAQAAAA==.Froddy:BAAALgADCgQJBAAAAA==.Frylockk:BAAALgAECgYJCwAAAA==.',
Fu='Fugoh:BAAALgADCgUJBQAAAA==.Furmancummin:BAAALgAECgUJDgAAAA==.Furrykane:BAEBLgAECn8hAAQHAAkJ2yJ0AQAEAwAHAAkJ2yJ0AQAEAwAVAAIJURnIIwB+AAAgAAEJVxpwMwA0AAAAAA==.Future:BAABLgAECn8lAAIbAAgJeRu9AwAFAgAbAAgJeRu9AwAFAgAAAA==.Fuwu:BAAALgAECgQJBAAAAA==.Fuwywowya:BAAALgAECgEJAQABLgAECgcJCwAEAAAAAA==.',
Fw='Fwuffy:BAAALgAECgEJAQAAAA==.',
Ga='Gabrrof:BAAALgADCgkJGAAAAA==.Ganonn:BAAALgADCgYJBgAAAA==.',
Gh='Ghadafi:BAAALgADCgQJBAABLgAECgYJFQAQAA0eAA==.',
Gi='Gillerd:BAAALgADCgUJCgAAAA==.Gills:BAAALgAECgMJBAAAAA==.Girthman:BAAALgAECgUJDAAAAA==.',
Go='Gobbleburble:BAAALgAECgEJAQAAAA==.Gogurt:BAAALgAECgYJDAAAAA==.Goju:BAAALgAECgUJCwAAAA==.Golfpro:BAAALgADCgcJAQAAAA==.Goobe:BAAALgAECgQJCQABLgAECgcJGwADANUaAA==.Goonela:BAAALgADCgEJAQAAAA==.',
Gr='Grinkle:BAAALgADCgQJBAAAAA==.Griselbrand:BAAALgADCgMJAwAAAA==.Gromlo:BAABLgAECn8iAAIUAAgJJBzrEwCXAgAUAAgJJBzrEwCXAgAAAA==.Grulog:BAAALgAECgUJDgAAAA==.',
Gu='Guatonfate:BAAALgADCgEJAQAAAA==.Gucciî:BAAALgAECgEJAQAAAA==.Gummiebear:BAAALgAECgYJCwAAAA==.Gunny:BAABLgAECn8XAAIWAAgJ9xXIBAC5AQAWAAgJ9xXIBAC5AQAAAA==.Guuccí:BAAALgADCgkJCQAAAA==.',
['Gã']='Gã:BAABLgAECn8dAAICAAgJjx/kBQCAAgACAAgJjx/kBQCAAgAAAA==.',
Ha='Haeliman:BAAALgADCgEJAQAAAA==.Haileigh:BAAALgAECgQJBAAAAA==.',
He='Healems:BAAALgAECgEJAgABLgAECgIJAgAEAAAAAA==.Hellbòund:BAAALgAECgEJAQAAAA==.Hellenkiller:BAAALgADCgEJAQAAAA==.',
Hi='Hikawa:BAABLgAECn8dAAMTAAgJsSHwDQBwAgATAAgJrx3wDQBwAgAhAAcJmSDpAwAbAgAAAA==.',
Ho='Honortheox:BAAALgADCgYJBgAAAA==.Hossdk:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Hosslight:BAAALgAECgYJBgAAAA==.Hottz:BAABLgAECn8lAAMUAAcJDyDZHwBCAgAUAAcJDyDZHwBCAgAgAAEJgwNCHwAzAAAAAA==.',
Hu='Hummice:BAAALgAECgIJAwAAAA==.Huntemall:BAAALgADCgcJDAABLgADCggJDwAEAAAAAA==.',
['Hà']='Hàvoc:BAAALgAECggJCgABLgAECggJHAATABgaAA==.',
['Hä']='Hävoc:BAABLgAECn8cAAITAAgJGBozPgB/AgATAAgJGBozPgB/AgAAAA==.',
Ic='Iceshards:BAABLgAECn8iAAITAAcJzQZhawADAQATAAcJzQZhawADAQAAAA==.',
Id='Idtrapthat:BAAALgAECgMJAwAAAA==.',
Ik='Ike:BAAALgAECgcJDwAAAA==.',
Il='Illidank:BAAALgADCgkJCQAAAA==.Illidankior:BAACLgAFFH8KAAIfAAQJoyFOAgCQAQAfAAQJoyFOAgCQAQAuAAQKfyEAAx8ACQlXIukEAPYCAB8ACQlXIukEAPYCAAYAAwmxC3csAJEAAAEuAAMKCQkJAAQAAAAA.Illirothas:BAABLgAECn8YAAQCAAYJUxOagQAmAQACAAYJkA+agQAmAQAiAAMJEhVvTAC9AAAjAAMJlQ4GIgByAAABLgAECgcJDgAEAAAAAA==.Illisteve:BAAALgAECgYJBgAAAA==.Ilovllamas:BAAALgAFFAEJAQAAAA==.',
Im='Imawizard:BAABLgAECn8kAAITAAgJPheEHwDvAQATAAgJPheEHwDvAQAAAA==.Immadewsh:BAAALgAECgYJAgAAAA==.Impoosh:BAABLgAECn8XAAMRAAgJ8B/+AQCxAgARAAgJ8B/+AQCxAgAQAAEJURDbqgA6AAAAAA==.Imsassy:BAAALgAECgQJBgAAAA==.',
In='Infectedbøb:BAAALgAECgYJDAAAAA==.Infekt:BAAALgAECgYJBQAAAA==.Infurnal:BAAALgAECgYJBgAAAA==.Inmortuae:BAAALgAECgMJBAABLgAECgcJDgAEAAAAAA==.Innovation:BAAALgAECgUJDAAAAA==.',
Ip='Iprayntank:BAABLgAECn8VAAIdAAYJ/AtpIAAEAQAdAAYJ/AtpIAAEAQAAAA==.',
Ir='Ir:BAAALgAECgkJDAAAAA==.Irissela:BAAALgADCgkJDQAAAA==.',
Iv='Ivalice:BAABLgAECn8eAAQDAAkJ5h59AwDuAgADAAkJ5h59AwDuAgAXAAEJ4hmEzAA5AAAWAAEJkAM/lQAkAAAAAA==.',
Iz='Izanamii:BAABLgAECn8aAAICAAgJPRGPWQCVAQACAAgJPRGPWQCVAQAAAA==.Izüal:BAAALgADCgkJCQABLgAECgcJEAAEAAAAAA==.',
Ja='Jaaros:BAAALgADCggJCQAAAA==.Jafbe:BAAALgAECgcJCAAAAA==.Jaxxid:BAAALgADCggJCQAAAA==.Jaymie:BAAALgAECgcJCgAAAA==.Jazlern:BAAALgAECgMJAwAAAA==.',
Je='Jesilpriest:BAAALgADCgYJBgAAAA==.',
Jh='Jherekal:BAAALgAECgMJBQAAAA==.',
Ji='Jimcarrey:BAABLgAECn8ZAAITAAYJJwZldADvAAATAAYJJwZldADvAAAAAA==.',
Jo='Joemauma:BAABLgAECn8bAAITAAcJ+RMsNwCKAQATAAcJ+RMsNwCKAQAAAA==.Johnnaay:BAAALgAECgIJAQAAAA==.Joslin:BAAALgADCgEJAQABLgAFFAQJCgAUAMUXAA==.',
Jp='Jpam:BAAALgAECgYJCgAAAA==.',
Ju='July:BAAALgADCgIJAgABLgAECgYJDAAEAAAAAA==.Jumbosize:BAACLgAFFH8RAAMUAAYJOBoABACiAQAUAAYJOBoABACiAQAHAAEJrAZ/HABEAAAuAAQKfzAAAhQACQl3JcMAALgDABQACQl3JcMAALgDAAAA.Junrage:BAACLgAFFH8QAAIPAAUJBhfdBwBVAQAPAAUJBhfdBwBVAQAuAAQKfxQAAw8ACQlsGxkZAIMCAA8ACAn8HRkZAIMCAAYAAQl3CSQsADgAAAAA.Jupîter:BAAALgAECgcJDQAAAA==.Justmeldit:BAAALgAECgIJAgAAAA==.',
Ka='Kaelis:BAAALgAECgEJAgAAAA==.Kaelish:BAAALgAECggJEQAAAA==.Kaerlif:BAABLgAECn8VAAIFAAgJshRSCwAhAgAFAAgJshRSCwAhAgABLgAFFAQJCQAiALYbAA==.Kaiyley:BAAALgAECgYJEgAAAA==.Kajortak:BAAALgAECgYJBwAAAA==.Kalastrian:BAAALgAECgYJEQAAAA==.Kangna:BAAALgADCgIJAgAAAA==.Karateshock:BAABLgAECn8mAAIKAAgJ4RpwCwAzAgAKAAgJ4RpwCwAzAgAAAA==.Karlor:BAABLgAECn8cAAMPAAcJ8Q6TGwBTAQAPAAcJNw6TGwBTAQAGAAEJEAvwLgAxAAAAAA==.Kasheeshb:BAAALgAECgQJBAAAAA==.Kazuren:BAABLgAECn8aAAMMAAcJAhI1IAD/AAAMAAYJ6Q41IAD/AAAOAAEJwwIXJQAhAAAAAA==.',
Ke='Keahoa:BAAALgADCgcJBwAAAA==.Keano:BAAALgAECgYJEAAAAA==.Keeldemall:BAAALgAECgQJBAAAAA==.Kelia:BAAALgAECgEJAgABLgAECgcJDgAEAAAAAA==.Kelinna:BAABLgAECn8gAAILAAcJMhTGLACPAQALAAcJMhTGLACPAQAAAA==.Kenichix:BAABLgAECn8eAAICAAkJLB4IDQASAgACAAkJLB4IDQASAgAAAA==.Kennidan:BAAALgAECgUJCQAAAA==.Kenshìn:BAAALgADCgEJAQAAAA==.Keymaster:BAAALgADCgIJAgAAAA==.',
Kf='Kfcchicken:BAAALgAECgIJAgAAAA==.',
Ki='Kiritoo:BAAALgAFFAIJAwAAAA==.Kitan:BAAALgAECgEJAQAAAA==.',
Kl='Klaye:BAAALgAECgQJDAABLgAECgcJFQAJABAaAA==.',
Ko='Kodabonk:BAABLgAECn8VAAMSAAgJhg9GKgC4AQASAAgJhg9GKgC4AQAkAAEJtQ2jgAAwAAAAAA==.Kodanorth:BAAALgADCgEJAQABLgAECggJFQASAIYPAA==.Kombata:BAAALgAECgYJDAAAAA==.Kombatant:BAAALgAECgUJCQAAAA==.Kotara:BAAALgAECgMJBAAAAA==.',
Kr='Kraur:BAAALgAECgQJBQABLgAECgcJDgAEAAAAAA==.',
Ku='Kumoj:BAAALgAECgQJBAAAAA==.Kunglaoo:BAAALgADCgEJAQAAAA==.',
La='Lag:BAAALgADCgYJBgAAAA==.Lam:BAAALgADCgEJAQAAAA==.Lame:BAAALgAECgEJAQABLgAECggJFwAKAMUdAA==.Lampp:BAAALgAECgQJBQABLgAECggJFAAaABoaAA==.Laws:BAAALgAECgYJEgAAAA==.',
Le='Leezerd:BAAALgADCgcJCQAAAA==.Lexsapphire:BAABLgAECn8aAAITAAYJwgM2fQDaAAATAAYJwgM2fQDaAAAAAA==.',
Li='Liaeda:BAABLgAECn8iAAIDAAgJzwxLEQCuAQADAAgJzwxLEQCuAQAAAA==.Lianshi:BAAALgAECgYJEwAAAA==.Lichplease:BAACLgAFFH8IAAIaAAQJSxTXGgBLAQAaAAQJSxTXGgBLAQAuAAQKfyQAAhoACQngHo8TAB0CABoACQngHo8TAB0CAAAA.Lilithandral:BAABLgAECn8bAAIfAAgJIRYFEgDnAQAfAAgJIRYFEgDnAQAAAA==.Limitedtank:BAAALgAECgQJDgAAAA==.Linainverse:BAAALgAECgUJCgAAAA==.Lithdradra:BAAALgADCgEJAQAAAA==.Livermaw:BAAALgADCgIJAgAAAA==.',
Lo='Logjammin:BAAALgADCgYJBgABLgAECggJFAAjAEkUAA==.Lolo:BAAALgAFFAIJAgABLgAFFAYJHAAJAOcWAA==.Loosie:BAABLgAECn8nAAIiAAkJ/SDwAAD6AgAiAAkJ/SDwAAD6AgAAAA==.',
Lu='Lucylepricon:BAAALgAECgQJBwAAAA==.Ludo:BAABLgAECn8VAAICAAYJ6CDaTgC6AQACAAYJ6CDaTgC6AQAAAA==.Luduhcris:BAAALgAECgQJBAAAAA==.Luebbersit:BAAALgAECgEJAgAAAA==.Luebberslueb:BAAALgAECgEJAQAAAA==.Luebberstiny:BAAALgADCgEJAwAAAA==.Lugnuts:BAAALgAECgQJBgAAAA==.Luketich:BAACLgAFFH8MAAIdAAQJHQmLAgDbAAAdAAQJHQmLAgDbAAAuAAQKfykAAh0ACAlyHoIGAIACAB0ACAlyHoIGAIACAAAA.Lumiltiand:BAACLgAFFH8JAAIaAAQJpxIaIgA0AQAaAAQJpxIaIgA0AQAuAAQKfx0ABBoACAnmIGA7AEkCABoACAnmIGA7AEkCABkAAgn1BzUjAF0AACUAAQlND4oQADgAAAAA.',
['Lú']='Lústì:BAAALgADCgcJCQAAAA==.',
Ma='Mafia:BAAALgADCgIJAgAAAA==.Mahuizmaca:BAABLgAECn8mAAMFAAgJwyDnAwDAAgAFAAgJwyDnAwDAAgALAAgJVhVQIADIAQAAAA==.Malakaa:BAAALgAECgIJAgAAAA==.Maleficante:BAAALgADCgUJBQAAAA==.Malgoros:BAABLgAECn8mAAMCAAgJVh5SBwBmAgACAAgJVh5SBwBmAgAiAAEJ1B1ebAA5AAAAAA==.Malgrendin:BAABLgAECn8bAAIXAAgJoCK4BQCcAgAXAAgJoCK4BQCcAgAAAA==.Mallock:BAAALgAECgIJAgAAAA==.Maluma:BAAALgADCgYJBgAAAA==.Malédictias:BAAALgAECgIJAgAAAA==.Mamii:BAABLgAECn8VAAIkAAYJDyNmCgDQAQAkAAYJDyNmCgDQAQAAAA==.Manaag:BAAALgAECgMJBAAAAA==.Manataurus:BAAALgADCgUJBQAAAA==.Manatreat:BAAALgADCgEJAgAAAA==.Manuall:BAAALgAECgcJEAAAAA==.Maralyn:BAABLgAECn8lAAIdAAgJ3wv6DQAgAQAdAAgJ3wv6DQAgAQAAAA==.Marshmellow:BAACLgAFFH8LAAIQAAQJvhHtFwBAAQAQAAQJvhHtFwBAAQAuAAQKfyEAAxAACAkgHs0tAFYCABAACAk/Hc0tAFYCABgABAlaF1MnACcBAAAA.Martense:BAAALgAECgYJCwAAAA==.Mawly:BAAALgAECgYJDgAAAA==.Maxidk:BAABLgAECn8tAAIaAAgJ3STVAwDyAgAaAAgJ3STVAwDyAgAAAA==.Maxilock:BAAALgADCgYJEgABLgAECggJLQAaAN0kAA==.Maximonk:BAAALgADCgkJDQABLgAECggJLQAaAN0kAA==.Maxipriest:BAAALgADCgUJBQAAAA==.Maxisdamage:BAABLgAECn8jAAITAAgJVxd1KQC/AQATAAgJVxd1KQC/AQAAAA==.Mazpaladin:BAAALgADCgUJBQAAAA==.',
Mc='Mcclownerson:BAAALgADCgYJDQABLgADCgYJBgAEAAAAAA==.',
Me='Melissarian:BAABLgAECn8YAAITAAcJWgIdgwDNAAATAAcJWgIdgwDNAAAAAA==.Mereoleona:BAABLgAECn8VAAIQAAYJDR7KPwAOAgAQAAYJDR7KPwAOAgAAAA==.',
Mi='Midgemaisel:BAAALgAECgYJDwAAAA==.Mirado:BAABLgAECn8aAAIPAAgJDhp3CgACAgAPAAgJDhp3CgACAgAAAA==.Misplacer:BAABLgAECn8UAAIUAAgJURlHKQAOAgAUAAgJURlHKQAOAgAAAA==.Mithridates:BAABLgAECn8UAAIYAAcJtQprCAAoAQAYAAcJtQprCAAoAQAAAA==.',
Mk='Mkherp:BAABLgAECn8UAAIBAAgJTRPlCgDRAQABAAgJTRPlCgDRAQAAAA==.',
Mo='Mohg:BAAALgADCgUJCAAAAA==.Momentjess:BAACLgAFFH8HAAIeAAMJVR7PDwAOAQAeAAMJVR7PDwAOAQAuAAQKfx8AAx4ACAlYIikEAB0DAB4ACAlYIikEAB0DAAgABwlcF60iAM8BAAAA.Monkragga:BAAALgADCgUJBQABLgAECggJJQAMAO4bAA==.Moolissa:BAAALgADCgEJAQAAAA==.Morrygan:BAAALgAECgEJAgAAAA==.Mortarien:BAAALgAECgQJBwAAAA==.Mortïx:BAABLgAECn8qAAIWAAkJViCiAADjAgAWAAkJViCiAADjAgAAAA==.',
My='Myrtle:BAAALgADCgEJAQAAAA==.Mystborne:BAAALgAECgIJAgABLgAECgcJEgAEAAAAAA==.',
Ne='Nevernude:BAABLgAECn8dAAIFAAcJUCJyBACwAgAFAAcJUCJyBACwAgAAAA==.Nexflamma:BAAALgAECgYJEwAAAA==.',
Ni='Niaru:BAAALgAECgYJEwAAAA==.Ninjay:BAAALgADCgUJBQAAAA==.Nirathren:BAAALgAECgEJAgABLgAECgUJDgAEAAAAAA==.Niwatori:BAABLgAECn8gAAIHAAgJpiDRAwCKAgAHAAgJpiDRAwCKAgAAAA==.',
No='Noah:BAACLgAFFH8XAAIDAAYJeCFfAADeAQADAAYJeCFfAADeAQAuAAQKfyAAAgMACAl3JjsBAFgDAAMACAl3JjsBAFgDAAAA.Nolarz:BAACLgAFFH8eAAImAAcJoSQCAAChAgAmAAcJoSQCAAChAgAuAAQKfyIAAyYACAkTJtsAAE4DACYACAkTJtsAAE4DABwAAQm+H+xeADgAAAAA.Noor:BAACLgAFFH8IAAICAAUJoR1LBgC/AQACAAUJoR1LBgC/AQAuAAQKfxYAAgIACAm9I5kVANUCAAIACAm9I5kVANUCAAEuAAUUBwkMAAsApxYA.Norbon:BAAALgADCgcJCwAAAA==.Nothhelm:BAAALgAECgUJCgAAAA==.',
Nu='Nugnug:BAACLgAFFH8LAAIaAAMJryMhLAAOAQAaAAMJryMhLAAOAQAuAAQKfxYAAhoACAn4IWMcANQCABoACAn4IWMcANQCAAAA.Nukthom:BAAALgAECgYJEgAAAA==.',
Ny='Nyahbinghi:BAAALgAECgIJAgAAAA==.Nylthoran:BAAALgADCgEJAQAAAA==.Nyneaves:BAABLgAECn8ZAAIBAAgJYBOOCgDXAQABAAgJYBOOCgDXAQAAAA==.',
Oh='Ohmenwah:BAAALgAECgQJBwAAAA==.',
Oj='Ojplosion:BAAALgAECgMJAwABLgAECgcJDAAEAAAAAA==.Ojpyroblast:BAAALgAECgcJDAAAAA==.',
Om='Omghunter:BAABLgAECn8WAAICAAgJdRDJJwBIAQACAAgJdRDJJwBIAQAAAA==.',
On='Oneesan:BAAALgADCgUJBQAAAA==.Onisprite:BAABLgAECn8ZAAMPAAcJAQ08JAAZAQAPAAcJAQ08JAAZAQAGAAMJWgNnJwBLAAAAAA==.',
Op='Optimish:BAAALgAECgEJAQAAAA==.',
Or='Orchaos:BAAALgADCgUJAQAAAA==.Ordhah:BAAALgAECgcJEAAAAA==.',
Os='Osanna:BAAALgAECgYJDAAAAA==.',
Ou='Outy:BAABLgAECn8cAAMQAAYJuhkyYwCgAQAQAAYJuhkyYwCgAQAYAAEJbgNMfQAhAAAAAA==.',
Ow='Owmyleg:BAAALgAECgYJDwAAAA==.',
Ox='Oxijinn:BAAALgAECgQJBQAAAA==.',
Pa='Pacanuch:BAAALgADCgYJCwAAAA==.Padding:BAAALgADCgMJAwAAAA==.Pakhan:BAABLgAECn8lAAImAAgJlgwhBACcAQAmAAgJlgwhBACcAQAAAA==.Paladina:BAAALgADCgEJAQAAAA==.Paladout:BAABLgAECn8iAAMLAAgJXhzPNgBHAgALAAcJvRzPNgBHAgAdAAgJ9RjGBwCbAQAAAA==.Palkia:BAAALgAECgEJAQAAAA==.Pallo:BAAALgADCgkJHwAAAA==.Paona:BAABLgAECn8jAAIHAAgJGQt5GgAoAQAHAAgJGQt5GgAoAQAAAA==.',
Pe='Pengting:BAAALgAECgYJCgAAAA==.Perajuve:BAAALgADCgYJBgABLgAECgkJHwAkAE0dAA==.Peraroll:BAABLgAECn8fAAIkAAkJTR0LCQDnAgAkAAkJTR0LCQDnAgAAAA==.Petz:BAAALgAECgUJEwAAAA==.',
Ph='Phaedrah:BAABLgAECn8WAAIMAAcJoQU7JADkAAAMAAcJoQU7JADkAAAAAA==.Phenphen:BAACLgAFFH8HAAQcAAMJWx4uEgC5AAAcAAMJmhQuEgC5AAAmAAEJ+iJPBQBlAAAnAAEJtRfxBABWAAAuAAQKfx8ABCYACAlTIt4CALcCACYACAm7Ht4CALcCACcAAwkfJK0EADsBABwABglIHxwXAB0BAAAA.Phuryphen:BAAALgADCgQJBAABLgAFFAMJBwAcAFseAA==.Physicyan:BAAALgAECgYJDAAAAA==.',
Pi='Piakchu:BAAALgADCgcJEwAAAA==.Pix:BAAALgAECgIJAwAAAA==.',
Pl='Plonterstank:BAABLgAECn8UAAIjAAgJSRQBCwCxAQAjAAgJSRQBCwCxAQAAAA==.Plzdontdie:BAAALgAECgEJAQAAAA==.',
Po='Pohealer:BAAALgAECgEJAwAAAA==.Pookie:BAAALgAECgEJAQAAAA==.Poombah:BAAALgAECgUJDgAAAA==.Popori:BAAALgADCgcJCQAAAA==.Popshampain:BAAALgAECgYJEAAAAA==.',
Pr='Preest:BAAALgAECgUJBQABLgAECggJIgAFADobAA==.Proudmoo:BAABLgAECn8hAAIFAAkJqB2fAQAZAwAFAAkJqB2fAQAZAwAAAA==.Provoke:BAAALgAECgEJAwAAAA==.',
Ps='Psion:BAAALgAECgEJAwAAAA==.',
Pu='Pumaa:BAAALgAECgYJDwAAAA==.',
Qu='Quickben:BAAALgADCgEJAQAAAA==.',
Ra='Raenlling:BAAALgADCgMJAwAAAA==.Ragehoof:BAAALgAECgcJDAAAAA==.Raise:BAABLgAECn8UAAIgAAYJZhDVFQBaAQAgAAYJZhDVFQBaAQAAAA==.Rathoril:BAABLgAECn8UAAIjAAgJYBEUBgBuAQAjAAgJYBEUBgBuAQAAAA==.Ratscum:BAAALgAECgQJDAABLgAECgYJDQAEAAAAAA==.Raxik:BAAALgADCgIJAgAAAA==.Raynor:BAAALgAECgIJAgAAAA==.Rayssa:BAABLgAECn8lAAIeAAgJCSUfAQBJAwAeAAgJCSUfAQBJAwAAAA==.',
Re='Redeker:BAABLgAECn8UAAImAAcJiw8sBQB1AQAmAAcJiw8sBQB1AQAAAA==.Regera:BAAALgAECgEJAQAAAA==.Renardfurtif:BAAALgAECgYJBwAAAA==.Reninni:BAAALgAECgUJCAAAAA==.Rentahunter:BAAALgAFFAEJAQAAAA==.Revolatiion:BAAALgADCgEJAQAAAA==.Revolationzs:BAAALgAECgEJAQAAAA==.',
Rh='Rhaanz:BAAALgADCgMJAwAAAA==.Rhynearas:BAAALgADCgUJCAABLgAECggJIgADAM8MAA==.',
Ri='Ridell:BAAALgADCgcJGQAAAA==.Rimasjobas:BAAALgAECgIJAgAAAA==.Rimestar:BAAALgAECgEJAQAAAA==.Rinda:BAAALgADCgUJBQABLgAECgYJBwAEAAAAAA==.Ripoodoo:BAAALgAECgUJBgAAAA==.',
Rn='Rngeesus:BAAALgAECgYJDgAAAA==.Rngnar:BAAALgAFFAIJAwAAAA==.',
Ro='Rocklie:BAAALgADCgYJBgAAAA==.Roguewolf:BAABLgAECn8XAAIHAAgJmhBkLQCYAQAHAAgJmhBkLQCYAQAAAA==.Roki:BAABLgAECn8XAAIOAAkJVBLwCgBjAQAOAAkJVBLwCgBjAQAAAA==.Rolow:BAABLgAECn8jAAITAAgJGhxcHgD2AQATAAgJGhxcHgD2AQAAAA==.Ronlock:BAAALgAECgIJAgAAAA==.Rooni:BAABLgAFFH8MAAILAAcJpxbUAQDUAQALAAcJpxbUAQDUAQAAAA==.Roony:BAAALgAECgcJDAABLgAFFAcJDAALAKcWAA==.Rossaruu:BAAALgAECggJCAAAAA==.Rot:BAABLgAECn8eAAQaAAgJICSIFwDuAgAaAAgJFySIFwDuAgAZAAEJ7SI/PABkAAAlAAEJxhleFABNAAAAAA==.Rotaderpz:BAAALgAECgUJCQABLgAECgYJGAACAOIVAA==.Royle:BAAALgAECggJDgAAAA==.',
Ru='Rune:BAABLgAECn8XAAMaAAYJ7RZOMAB5AQAaAAYJ7RZOMAB5AQAlAAEJfgqaEAA3AAAAAA==.Runnerjay:BAAALgADCgYJFAABLgAECgkJKgAdAKkNAA==.Rush:BAABLgAECn8bAAITAAcJrxivJwDHAQATAAcJrxivJwDHAQAAAA==.Ruswarlock:BAAALgAECgUJBQAAAA==.Ruuf:BAAALgAECgcJCwAAAA==.',
Ry='Rysango:BAABLgAECn8VAAICAAkJeSLjEQDwAgACAAkJeSLjEQDwAgAAAA==.Ryuujins:BAACLgAFFH8QAAIeAAUJJCEJBADoAQAeAAUJJCEJBADoAQAuAAQKfxwAAx4ACAl4JJsDAC8DAB4ACAl4JJsDAC8DAAgAAwmmGx9XANkAAAAA.',
Sa='Saelria:BAAALgAECgUJCgAAAA==.Saidar:BAAALgADCgcJCAAAAA==.Sainthoovr:BAABLgAECn8mAAMeAAkJOiRnAACiAwAeAAkJOiRnAACiAwABAAMJix12PgABAQAAAA==.Saintluke:BAAALgAECgQJCAAAAA==.Sakuraa:BAABLgAECn8WAAIcAAgJ0Ae/KQCtAQAcAAgJ0Ae/KQCtAQAAAA==.Sandia:BAAALgADCgYJCwAAAA==.Sausage:BAAALgADCgYJBgAAAA==.',
Sc='Scam:BAAALgADCgcJCAAAAA==.Scumrat:BAAALgAECgYJDQAAAA==.Scyon:BAABLgAECn8ZAAIhAAgJuhfxAQDAAQAhAAgJuhfxAQDAAQAAAA==.',
Se='Seladorei:BAABLgAECn8jAAInAAkJXiFDAADpAgAnAAkJXiFDAADpAgAAAA==.Senari:BAABLgAECn8WAAIdAAcJZRBmDAA6AQAdAAcJZRBmDAA6AQAAAA==.Sencia:BAAALgAECgQJBQAAAA==.',
Sh='Shadowblazer:BAABLgAECn8aAAIQAAgJshoRSwDoAQAQAAgJshoRSwDoAQAAAA==.Shadowrainz:BAABLgAECn8dAAIBAAcJThLgEgBuAQABAAcJThLgEgBuAQAAAA==.Shadozw:BAAALgADCgMJAwAAAA==.Shalizar:BAAALgAECgEJAQAAAA==.Shanda:BAABLgAECn8XAAIKAAgJxR0CDwChAgAKAAgJxR0CDwChAgAAAA==.Shankukindly:BAAALgAECgcJCQAAAA==.Shanto:BAABLgAECn8VAAMJAAcJEBqvLAC0AQAJAAcJEBqvLAC0AQAbAAEJAACBKQBDAAAAAA==.Shiftinmojo:BAAALgAECgEJAQAAAA==.Shoumei:BAABLgAECn8aAAMkAAgJ1hy9DACuAgAkAAgJ1hy9DACuAgASAAEJ1wKOjwAlAAAAAA==.Shuken:BAAALgAECgEJAwAAAA==.Shwip:BAABLgAECn8iAAMHAAgJViGrCQD6AgAHAAgJViGrCQD6AgAUAAYJ4xFaSACvAAAAAA==.',
Si='Sickamage:BAABLgAECn8eAAMTAAgJyxuCSQBaAgATAAgJgRqCSQBaAgAhAAMJZxypDwDHAAAAAA==.Silfra:BAAALgAECgcJEQAAAA==.Sillas:BAAALgAECgIJAgAAAA==.Silvinos:BAAALgAECgEJAgAAAA==.',
Sl='Slapparazzi:BAAALgADCgYJBgAAAA==.Sleepingmad:BAAALgAFFAEJAgAAAA==.Sloothix:BAAALgAECgcJCgABLgAECgkJCQAEAAAAAA==.Slothbob:BAAALgADCgEJAQAAAA==.Slushië:BAAALgAECgQJBgAAAA==.',
Sm='Smilingdev:BAAALgAECgYJCwAAAA==.Smittytank:BAAALgAECgEJAQAAAA==.',
So='Soulsproxy:BAAALgAECgIJAgAAAA==.',
Sp='Spawwn:BAAALgADCggJCAABLgAECgcJGwADANUaAA==.Spazdeath:BAAALgAECgQJBAAAAA==.Spellberg:BAAALgAECgQJBAAAAA==.Spilby:BAAALgADCgEJAgAAAA==.',
Sq='Squashee:BAAALgAECgUJBQAAAA==.Squishymonk:BAAALgADCgUJBQAAAA==.',
Ss='Ssilb:BAAALgAECgUJBQAAAA==.',
St='Stabbz:BAABLgAECn8cAAIcAAYJ7hLZEwA+AQAcAAYJ7hLZEwA+AQAAAA==.Stepdad:BAAALgAECgIJAwAAAA==.Stevetsin:BAAALgAECgMJAwAAAA==.Steviewonder:BAAALgAECgcJCwABLgAECgcJDAAEAAAAAA==.Stillasleep:BAAALgAECgYJEAAAAA==.Stonatroll:BAAALgAECgQJBAABLgAECgcJDgAEAAAAAA==.Stormdemon:BAABLgAECn8ZAAIPAAcJtRadEAC1AQAPAAcJtRadEAC1AQAAAA==.Stormspellz:BAABLgAECn8iAAIKAAgJKRm7EADvAQAKAAgJKRm7EADvAQAAAA==.Stormyspellz:BAABLgAECn8VAAIIAAYJeh4jGgALAgAIAAYJeh4jGgALAgAAAA==.',
Su='Subwayeater:BAABLgAECn8dAAIOAAgJaBHRHwCAAQAOAAgJaBHRHwCAAQAAAA==.Subzro:BAABLgAECn8YAAITAAcJohKGqQCHAQATAAcJohKGqQCHAQAAAA==.Summäurs:BAAALgADCgMJAwABLgAECgcJDQAEAAAAAA==.Supay:BAAALgAECgYJDwAAAA==.Suwgo:BAAALgADCgIJAgAAAA==.',
Sy='Sylosis:BAABLgAECn8fAAIaAAgJ3A3XLQCDAQAaAAgJ3A3XLQCDAQAAAA==.Syzzle:BAACLgAFFH8GAAITAAMJuhMUOgDrAAATAAMJuhMUOgDrAAAuAAQKfxcAAxMACAnxH5A2AJoCABMACAlnH5A2AJoCACgAAwnuHUgIAOcAAAAA.',
Ta='Takkiya:BAAALgAECgEJAQAAAA==.Talicso:BAACLgAFFH8KAAITAAQJfw9eIgBKAQATAAQJfw9eIgBKAQAuAAQKfyMAAxMACQkaHCNBAHUCABMACQkaHCNBAHUCACEABAkXEeEOANUAAAAA.Talos:BAAALgAECgUJBQABLgAECggJHAAPANgeAA==.Talzinn:BAAALgAECggJCQABLgAECggJHAAPANgeAA==.Tam:BAAALgAECgEJAQABLgAFFAYJFwADAHghAA==.Tankr:BAAALgAECgUJBQAAAA==.Tarkinal:BAABLgAECn8YAAIKAAgJvx2jBgCCAgAKAAgJvx2jBgCCAgAAAA==.',
Te='Teezee:BAABLgAECn8rAAILAAkJByF3AgAJAwALAAkJByF3AgAJAwAAAA==.Telina:BAAALgADCgQJBAAAAA==.Temetnosce:BAAALgADCgcJBgAAAA==.Tempura:BAABLgAECn8fAAITAAkJbBujCwCJAgATAAkJbBujCwCJAgAAAA==.Tenebros:BAAALgAECgEJAQAAAA==.Testament:BAAALgAECgEJAQAAAA==.',
Th='Thanatus:BAAALgAECgYJEQAAAA==.Thath:BAABLgAECn8XAAIjAAYJ0SHgCADnAQAjAAYJ0SHgCADnAQAAAA==.Thaulnor:BAAALgADCgEJAgAAAA==.Thavus:BAAALgAECgEJAwAAAA==.Thelendris:BAAALgAECgIJAgAAAA==.Themartian:BAABLgAECn8ZAAMpAAYJOBUnKABzAQApAAYJOBUnKABzAQAkAAMJOQRwZQB3AAAAAA==.Theshinigami:BAAALgAECgQJBAAAAA==.Thevinny:BAAALgADCgcJCwAAAA==.Thruumm:BAAALgAECgYJBgAAAA==.Thunsibution:BAAALgAECgQJBgABLgADCgkJCQAEAAAAAA==.Thydriel:BAAALgADCgcJBwABLgAECggJIAAUAGMcAA==.',
Ti='Tickz:BAABLgAECn8lAAQRAAgJ6CJYAQDjAgARAAcJhiNYAQDjAgAQAAgJRCDBBgChAgAYAAIJ0BmRGQBbAAAAAA==.Tidepods:BAAALgADCgIJAgAAAA==.Tistic:BAAALgAECgEJAgAAAA==.',
To='Toeran:BAABLgAECn8fAAMdAAgJLRoXBQDsAQAdAAgJLRoXBQDsAQALAAEJyQ6TvgA/AAAAAA==.Tokémon:BAAALgAECgMJAwAAAA==.Totesup:BAAALgAECgQJCAAAAA==.',
Tr='Traelin:BAAALgAECgQJCAABLgAFFAQJCgAUAMUXAA==.Traylesong:BAAALgADCgYJCgAAAA==.Tread:BAACLgAFFH8HAAIPAAQJaxY6BwBaAQAPAAQJaxY6BwBaAQAuAAQKfyEAAg8ACAlmJB0JABoDAA8ACAlmJB0JABoDAAAA.Trickee:BAABLgAECn8VAAITAAYJVA0ScAD5AAATAAYJVA0ScAD5AAABLgAECgYJFQAkAA8jAA==.Trôlol:BAAALgAECgEJAgABLgAECgcJCQAEAAAAAA==.',
Ts='Tskaha:BAAALgAECgQJCAAAAA==.',
Tu='Tulip:BAAALgADCgkJFgAAAA==.',
Ty='Tyria:BAABLgAECn8cAAIWAAgJrBK3BAC7AQAWAAgJrBK3BAC7AQAAAA==.Tyronius:BAAALgAECgUJDAAAAA==.',
Um='Umbraxion:BAABLgAECn8gAAINAAgJxwrYFQCRAQANAAgJxwrYFQCRAQAAAA==.',
Un='Undeadmerlin:BAAALgAECgYJBgAAAA==.',
Ur='Urabrask:BAAALgADCgUJBQABLgAECgYJBgAEAAAAAA==.',
Va='Vanstan:BAAALgADCgUJBQABLgAFFAUJCwATAOwKAA==.Varg:BAAALgADCgEJAQAAAA==.Varsil:BAAALgAECgQJBQAAAA==.Vashstampede:BAAALgAECgUJDQAAAA==.',
Ve='Velithiria:BAABLgAECn8kAAIXAAgJJBTyJAAoAgAXAAgJJBTyJAAoAgAAAA==.Velrik:BAABLgAECn8UAAImAAYJUhtjBACSAQAmAAYJUhtjBACSAQAAAA==.Venerable:BAAALgAECgYJDQAAAA==.Vernali:BAAALgAECgYJEQAAAA==.Vernalia:BAAALgAECgEJAgABLgAECgYJEQAEAAAAAA==.Vezdormi:BAAALgAECgQJBAABLgAFFAQJCAANAIsiAA==.Vezdormu:BAACLgAFFH8IAAINAAQJiyJfAACOAQANAAQJiyJfAACOAQAuAAQKfx4AAg0ACQnPJNkAAG4DAA0ACQnPJNkAAG4DAAAA.',
Vi='Vitrixz:BAAALgADCggJHgAAAA==.Vizdicator:BAABLgAECn8qAAIdAAgJlRW+CQBrAQAdAAgJlRW+CQBrAQAAAA==.Viztryalle:BAAALgAECgEJAQAAAA==.',
Vu='Vulcãnus:BAAALgAECgUJCwABLgAECgcJDQAEAAAAAA==.',
We='Werse:BAABLgAECn8iAAIIAAgJBRzKDgByAgAIAAgJBRzKDgByAgAAAA==.',
Wh='Whodi:BAAALgADCgIJAwAAAA==.',
Wi='Willowdusk:BAAALgAECgMJBAABLgAECgYJBgAEAAAAAA==.Willowmist:BAAALgAECgYJBgAAAA==.Willtolive:BAAALgADCggJDwAAAA==.Wind:BAAALgAECgQJBAAAAA==.',
Wr='Wrathofpride:BAAALgADCgYJBgAAAA==.',
Xa='Xackta:BAAALgADCgcJBgAAAA==.Xantom:BAAALgADCgYJBgAAAA==.Xatan:BAAALgAECgEJAwAAAA==.',
Xj='Xjeshy:BAAALgADCggJFgAAAA==.Xjoshy:BAAALgADCgcJEAAAAA==.',
Xn='Xnatem:BAABLgAECn8XAAIfAAcJcxhhCgCFAQAfAAcJcxhhCgCFAQAAAA==.',
['Xë']='Xëllos:BAAALgADCgQJBAAAAA==.',
Ya='Yashiro:BAABLgAECn8aAAIFAAcJPQ+oGwBvAQAFAAcJPQ+oGwBvAQAAAA==.',
Ye='Yeraleth:BAABLgAECn8gAAIUAAgJYxzZFwB3AgAUAAgJYxzZFwB3AgAAAA==.',
Yi='Yisiwang:BAAALgADCgMJAwAAAA==.',
Yo='Yorkj:BAAALgAECgcJDgAAAA==.',
Yv='Yvonca:BAAALgADCgEJAQAAAA==.',
Za='Zalthorax:BAAALgAECgcJDgAAAA==.Zarri:BAAALgADCgUJBQAAAA==.Zatilion:BAABLgAECn8VAAILAAcJ2wrejwBcAQALAAcJ2wrejwBcAQAAAA==.',
Ze='Zenju:BAAALgAECgEJAwAAAA==.Zenki:BAAALgAECgcJCgAAAA==.Zepharion:BAAALgAECgYJCQAAAA==.Zephiday:BAABLgAECn8fAAIBAAgJBxt5DgCcAgABAAgJBxt5DgCcAgAAAA==.Zerfonk:BAABLgAECn8UAAISAAgJ9CJEDADKAgASAAgJ9CJEDADKAgAAAA==.',
Zh='Zhushii:BAABLgAECn8eAAIHAAgJhxVAEACRAQAHAAgJhxVAEACRAQAAAA==.',
Zi='Ziggamoo:BAAALgADCgYJBgABLgAECgcJGwADANUaAA==.Ziggashot:BAABLgAECn8bAAIDAAcJ1Rr7CABTAgADAAcJ1Rr7CABTAgAAAA==.Zinsus:BAAALgAECgIJAgABLgAECgcJDgAEAAAAAA==.',
Zo='Zoromaak:BAAALgAECgIJAgABLgAECggJIwAaAJsdAA==.',
Zu='Zumbao:BAAALgAECgEJAQAAAA==.Zurahahsha:BAABLgAECn8eAAIbAAcJbAhSCwArAQAbAAcJbAhSCwArAQAAAA==.',
['Ðr']='Ðrow:BAABLgAECn8jAAIWAAgJVxgoBADSAQAWAAgJVxgoBADSAQAAAA==.',
['Óx']='Óxy:BAAALgAECgYJCQAAAA==.',
['Üh']='Ühr:BAAALgAECgYJDwAAAA==.',
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

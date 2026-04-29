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

local lookup = {'Priest-Shadow','DemonHunter-Devourer','Hunter-Survival','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Druid-Balance','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Evoker-Augmentation','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Monk-Brewmaster','Mage-Frost','Evoker-Preservation','Druid-Restoration','Druid-Guardian','Evoker-Devastation','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Unholy','Shaman-Enhancement','Rogue-Subtlety','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Blood','Priest-Discipline','Warrior-Protection','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Assassination','DeathKnight-Frost','Rogue-Outlaw','Mage-Fire','Monk-Mistweaver',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aazmon:BAACLgAFFH8LAAIBAAQJ0BUFBwBWAQABAAQJ0BUFBwBWAQAuAAQKfyIAAgEACAnyI4EGACQDAAEACAnyI4EGACQDAAAA.',
Ab='Abinjahmin:BAAALgAECgUJBwAAAA==.',
Ac='Acy:BAABLgAECn8dAAICAAYJrh/LOAARAgACAAYJrh/LOAARAgAAAA==.',
Ae='Aeman:BAAALgAECgQJBQAAAA==.Aeropunk:BAAALgAECgEJAQAAAA==.Aerøs:BAAALgAECgYJDgAAAA==.Aesthetic:BAAALgAECgYJCQAAAA==.',
Af='Afflicting:BAAALgAECgEJBQAAAA==.',
Ag='Aggiz:BAAALgAECgQJBAABLgAECgcJGwADANUaAA==.',
Aj='Ajaxprime:BAAALgAFFAIJAgAAAA==.',
Al='Alabamajane:BAAALgAECgUJCAAAAA==.Alesîa:BAAALgAECgQJBQAAAA==.Alfabika:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Alittlesalty:BAABLgAECn8iAAIFAAgJOhuyFQBjAgAFAAgJOhuyFQBjAgAAAA==.Alnec:BAAALgAECgMJBQAAAA==.Alronn:BAAALgAECgMJBQAAAA==.Alustrious:BAAALgADCgUJBQABLgAFFAIJBQAGAIgiAA==.Alzim:BAABLgAECn8kAAIHAAgJiCPfAQBQAgAHAAgJiCPfAQBQAgAAAA==.',
Am='Amrën:BAABLgAECn8dAAIIAAgJZxEICQBuAQAIAAgJZxEICQBuAQAAAA==.',
An='Animosityy:BAAALgADCgYJBgAAAA==.Antitheist:BAAALgADCgQJBAAAAA==.Antitoo:BAAALgAECgEJAQAAAA==.Antitoos:BAAALgADCggJDAAAAA==.',
Ar='Aragos:BAAALgAECgYJDQAAAA==.Arcelon:BAAALgAECgIJAgAAAA==.Arcelorz:BAAALgAECgkJBwAAAA==.Arlesia:BAAALgAECgEJAQAAAA==.Arvz:BAABLgAECn8UAAMJAAYJBBwcLwClAQAJAAYJBBwcLwClAQAKAAEJSAdonwAxAAAAAA==.Arwenatak:BAAALgAECgYJBwAAAA==.',
As='Ashlari:BAAALgAECgUJDAAAAA==.Ashter:BAAALgADCgkJDAAAAA==.Asmuun:BAAALgADCgcJBwABLgAFFAQJCwABANAVAA==.',
At='Athren:BAABLgAECn8WAAILAAYJGyMTOQA/AgALAAYJGyMTOQA/AgAAAA==.Atøne:BAAALgADCgUJCQAAAA==.',
Av='Averyee:BAAALgADCgQJBAAAAA==.',
Az='Azealiabanks:BAAALgADCgQJAwAAAA==.Azmun:BAAALgAECgYJDwABLgAFFAQJCwABANAVAA==.',
Ba='Badfish:BAAALgADCgYJBgABLgAECgYJDAAEAAAAAA==.Balgart:BAAALgAECgQJBAAAAA==.Barnëy:BAAALgADCgEJAQAAAA==.Barraga:BAAALgADCgMJAwABLgAECggJHQAMAK8YAA==.Barragadin:BAAALgADCgMJAwABLgAECggJHQAMAK8YAA==.Barreta:BAAALgADCgYJCQAAAA==.Basle:BAAALgADCgYJBgAAAA==.',
Be='Beauregaard:BAAALgADCgUJBQAAAA==.Beck:BAABLgAECn8VAAIKAAcJLwRqXQAVAQAKAAcJLwRqXQAVAQAAAA==.Beefykin:BAAALgADCgkJEAAAAA==.Beeowin:BAAALgADCgcJDwAAAA==.Beevoker:BAAALgAECgYJDwAAAA==.Bellamuerté:BAAALgAECgMJAwABLgAECgcJEAAEAAAAAA==.Bellámuerté:BAAALgAECgcJEAAAAA==.Bertox:BAAALgAECgcJEwAAAA==.',
Bi='Bigdrandyy:BAAALgAECgUJBwAAAA==.Biggnz:BAAALgADCgcJBAAAAA==.Biggsx:BAAALgADCgYJBwAAAA==.Bijali:BAAALgADCgMJAwAAAA==.Bika:BAAALgAECgIJAgAAAA==.Binhad:BAAALgAECgUJDQAAAA==.Birdallas:BAABLgAECn8WAAIHAAgJYRfyHQAQAgAHAAgJYRfyHQAQAgAAAA==.Bizk:BAAALgADCgEJAQAAAA==.',
Bl='Bloodlordzz:BAAALgAECgYJBgAAAA==.Bloodlusst:BAABLgAECn8eAAIIAAgJ3BMrBwCaAQAIAAgJ3BMrBwCaAQAAAA==.Bloodreina:BAABLgAECn8cAAINAAgJ2B6yDQDoAgANAAgJ2B6yDQDoAgAAAA==.Blueburry:BAAALgADCgEJAQAAAA==.',
Bo='Bob:BAABLgAECn8WAAMOAAcJnhu6DgCcAQAOAAYJnhu6DgCcAQAPAAEJAAA0IgBpAAAAAA==.Bobatea:BAAALgAECgkJCQAAAA==.Bonelee:BAABLgAECn8fAAIQAAgJBQwtNAB/AQAQAAgJBQwtNAB/AQAAAA==.Boomtang:BAAALgAECgEJAQAAAA==.Boshuun:BAAALgAECgMJAwAAAA==.',
Br='Brahm:BAAALgAECgIJAgABLgAECgYJEQAEAAAAAA==.Brainrotkid:BAACLgAFFH8JAAIRAAUJbgh8DQAkAQARAAUJbgh8DQAkAQAuAAQKfykAAhEACQmrHyERAEEDABEACQmrHyERAEEDAAAA.Bravoker:BAABLgAECn8dAAMMAAgJrxjuBQCfAQAMAAgJrxjuBQCfAQASAAIJFATPQwBQAAAAAA==.Brdua:BAAALgADCgUJBQAAAA==.Breeze:BAAALgADCgEJAQABLgAECgYJBQAEAAAAAA==.Brosrus:BAAALgAECgUJCgABLgAECggJGAARANcZAA==.',
Bu='Budtender:BAABLgAECn8ZAAMTAAgJ3A/jQQCaAQATAAgJ3A/jQQCaAQAUAAEJJgglOAAXAAAAAA==.Bulkam:BAABLgAECn8YAAMFAAgJAg1pRwBaAQAFAAgJAg1pRwBaAQALAAIJkgVvJQFUAAAAAA==.Bulldan:BAAALgADCgcJCAAAAA==.Burbuja:BAABLgAECn8fAAQSAAgJkR8OBgDkAgASAAgJkR8OBgDkAgAMAAcJShmMAgAdAgAVAAUJFRVkHABNAQAAAA==.Burr:BAAALgADCgYJBgAAAA==.',
Bz='Bzap:BAAALgADCgYJDwAAAA==.',
Ca='Callabash:BAABLgAECn8ZAAMKAAcJMQ9oQwB0AQAKAAcJMQ9oQwB0AQAJAAMJCwevcACAAAAAAA==.Callahan:BAAALgAECgMJBAAAAA==.Cameltotemx:BAAALgAECgQJBwAAAA==.Capa:BAAALgADCggJEQAAAA==.Captórofsin:BAAALgADCgIJAgAAAA==.Catchacharge:BAAALgADCgQJBAAAAA==.Cav:BAABLgAECn8bAAMWAAgJmBUNIwALAgAWAAgJmBUNIwALAgADAAUJKAVzCQAMAQAAAA==.',
Ce='Celarena:BAABLgAECn8VAAIXAAYJ5wOiBwC5AAAXAAYJ5wOiBwC5AAAAAA==.',
Ch='Chabil:BAAALgAECgIJAwAAAA==.Charcol:BAAALgAECgcJDAAAAA==.Chasen:BAAALgADCgQJBAAAAA==.Cheeziit:BAABLgAECn8cAAMUAAgJhRudAQD4AQAUAAgJhRudAQD4AQATAAIJGQpUuwBPAAAAAA==.Chomrogg:BAAALgAFFAEJAQAAAA==.Chop:BAAALgAECgYJEQAAAA==.Chopzzpala:BAAALgADCgEJAQAAAA==.Chunked:BAAALgAECgYJCgAAAA==.Chyp:BAABLgAECn8bAAILAAgJtRg4NwBGAgALAAgJtRg4NwBGAgAAAA==.Chzdh:BAAALgAECgcJBwABLgAECgcJCAAEAAAAAA==.Chzpld:BAAALgAECgcJCAAAAA==.',
Ci='Cichadin:BAABLgAECn8fAAICAAgJlg/oTADBAQACAAgJlg/oTADBAQABLgAFFAYJFwAOAHcZAA==.Cichorì:BAACLgAFFH8XAAQOAAYJdxleAQA0AgAOAAYJdxleAQA0AgAXAAIJEQhJDQCjAAAPAAEJZABUBQBXAAAuAAQKfyoAAw4ACQkxIfwMABIDAA4ACQmLG/wMABIDABcABwmNHVYGAGoCAAAA.Cipa:BAAALgAECgMJBAAAAA==.',
Cl='Clae:BAABLgAECn8YAAIYAAgJZx4CPABHAgAYAAgJZx4CPABHAgAAAA==.Clone:BAAALgADCgkJCQAAAA==.',
Co='Cobramaxima:BAAALgAECgEJAQAAAA==.Colmer:BAABLgAECn8UAAIOAAYJzhYZFwBXAQAOAAYJzhYZFwBXAQAAAA==.Coochy:BAAALgAECgYJCgAAAA==.Cotten:BAAALgAECgIJAgAAAA==.',
Cr='Crispriest:BAAALgAFFAEJAQAAAA==.Crockito:BAACLgAFFH8UAAIJAAcJ5SJBAADbAgAJAAcJ5SJBAADbAgAuAAQKfx0AAgkACQl2JkcAAPQDAAkACQl2JkcAAPQDAAAA.Cryi:BAAALgADCggJDQAAAA==.',
Cu='Cub:BAAALgADCgMJAwAAAA==.',
Cy='Cymist:BAACLgAFFH8GAAITAAMJMRXnBwDnAAATAAMJMRXnBwDnAAAuAAQKfx0AAhMACAk/IqwMANgCABMACAk/IqwMANgCAAAA.',
['Cî']='Cîpa:BAAALgAECgMJBAAAAA==.',
Da='Dabu:BAAALgAECgYJDAAAAA==.Dak:BAAALgAECgYJDAAAAA==.Dampening:BAAALgAECgUJBgAAAA==.Dantar:BAABLgAECn8aAAQJAAgJCwjiOABtAQAJAAgJCwjiOABtAQAZAAYJJQUGGwAZAQAKAAQJOQJvgwCGAAAAAA==.Daroll:BAAALgADCgIJAgAAAA==.Darthidan:BAABLgAECn8UAAILAAYJ6xHHkABaAQALAAYJ6xHHkABaAQAAAA==.Darthir:BAAALgAECggJDwAAAA==.Daìsy:BAABLgAECn8WAAMTAAYJsRdvEgA5AQATAAYJsRdvEgA5AQAHAAMJ8RRtWwC1AAAAAA==.',
De='Deadphen:BAAALgADCgIJAgAAAA==.Deathscythe:BAAALgADCgEJAQAAAA==.Delaroz:BAAALgAECgQJBAAAAA==.Demonbourne:BAAALgADCgEJAQAAAA==.Demonphen:BAAALgAECgQJBgABLgAFFAMJBQAaADIeAA==.Depoprovera:BAABLgAECn8hAAIbAAgJ4w7XFgBnAQAbAAgJ4w7XFgBnAQAAAA==.Deqz:BAABLgAECn8bAAMcAAcJNRwXCgDHAQAWAAcJnRc/LADKAQAcAAYJxR0XCgDHAQAAAA==.Desmurdius:BAAALgADCgQJBAAAAA==.Destan:BAAALgAECgYJDwAAAA==.',
Dh='Dhoko:BAABLgAECn8dAAILAAgJLAcVIQApAQALAAgJLAcVIQApAQAAAA==.',
Di='Diewithonor:BAAALgAECgYJBgAAAA==.Dilox:BAABLgAECn8ZAAIIAAcJPRcaIwDMAQAIAAcJPRcaIwDMAQAAAA==.Dirtyshammy:BAAALgAECgIJAgAAAA==.Disaaya:BAABLgAECn8ZAAIcAAgJLg7jDACjAQAcAAgJLg7jDACjAQAAAA==.Disbizch:BAAALgAECgQJBwAAAA==.',
Do='Dokromaa:BAABLgAECn8eAAIYAAgJaRrCSwAQAgAYAAgJaRrCSwAQAgAAAA==.Dominic:BAAALgADCgcJCAAAAA==.Doodlebug:BAACLgAFFH8LAAIdAAUJdBENAwAgAQAdAAUJdBENAwAgAQAuAAQKfyoAAh0ACAmbHxkBAGkCAB0ACAmbHxkBAGkCAAAA.Dooshrocket:BAAALgAECgMJBAAAAA==.Dorck:BAAALgADCgkJFAAAAA==.Dorzan:BAAALgADCgYJDAAAAA==.Dotix:BAAALgADCgUJCQAAAA==.Doughdappy:BAAALgAECgMJBAAAAA==.Doxxz:BAAALgADCggJFAABLgAECgcJDQAEAAAAAA==.',
Dp='Dpaw:BAAALgAECgIJAgAAAA==.',
Dr='Dracuujin:BAAALgAECgYJCwABLgAFFAUJDAAeAKUgAA==.Draeyen:BAAALgAECgEJAwAAAA==.Dragonballs:BAAALgAECgMJAwAAAA==.Dralioli:BAAALgAECgYJEAAAAA==.Dreadloccs:BAABLgAECn8aAAMXAAgJOR7+HABmAQAXAAQJYR7+HABmAQAOAAQJGx6ClgArAQAAAA==.Dreanil:BAABLgAECn8cAAMKAAgJSBqDHAA1AgAKAAgJSBqDHAA1AgAZAAEJiwRXLgAtAAAAAA==.Drroog:BAAALgADCgMJAwABLgADCgUJCQAEAAAAAA==.Druidesse:BAAALgADCgUJBQABLgAECgEJAQAEAAAAAA==.',
Du='Durbekbek:BAAALgADCgcJBwAAAA==.Durond:BAAALgAECgQJBgAAAA==.',
Dw='Dwarfsize:BAAALgAECgEJAQAAAA==.',
Dy='Dyksuckie:BAAALgADCgUJBQABLgAECggJHAANANgeAA==.',
Dz='Dzievana:BAAALgAECgQJBAAAAA==.',
['Dâ']='Dârn:BAABLgAECn8aAAMOAAgJ3B1pKwBhAgAOAAcJ3B1pKwBhAgAPAAEJAACMIQBsAAAAAA==.',
Ea='Earthygirthy:BAAALgAECgYJEQAAAA==.Eaumz:BAAALgAECgEJAQAAAA==.',
Ed='Edwin:BAAALgAECgcJBwAAAA==.',
Ei='Eigenbra:BAAALgAFFAIJAgAAAA==.',
El='Elissra:BAAALgAFFAEJAQAAAA==.Elori:BAAALgADCgIJAgAAAA==.Elvispræstly:BAAALgAECgQJCAAAAA==.',
Em='Emodeqz:BAAALgAECgIJAwAAAA==.',
En='Endfist:BAAALgAECgkJAwAAAA==.',
Ep='Epilepsy:BAAALgAECgQJBAAAAA==.',
Er='Eroy:BAAALgADCgUJBQAAAA==.Erzza:BAABLgAECn8eAAIFAAgJ1yLaAQCTAgAFAAgJ1yLaAQCTAgAAAA==.',
Es='Esotericzeo:BAAALgADCgIJAgAAAA==.',
Eu='Eupherine:BAABLgAECn8fAAIIAAgJsyQ6AABGAwAIAAgJsyQ6AABGAwAAAA==.',
Ev='Evildrood:BAABLgAECn8UAAIHAAcJPRh9BgCaAQAHAAcJPRh9BgCaAQAAAA==.',
Ey='Eyegouge:BAAALgADCgYJCwAAAA==.',
Fa='Fatsmellycow:BAAALgAECgYJCwAAAA==.',
Fe='Felwags:BAAALgAECgMJAwAAAA==.Fendrag:BAABLgAECn8UAAIfAAYJXBqpEwDRAQAfAAYJXBqpEwDRAQAAAA==.',
Fl='Flappii:BAAALgADCgkJDgAAAA==.Flappyfuros:BAABLgAECn8aAAISAAgJ6wmgHQCWAQASAAgJ6wmgHQCWAQAAAA==.Flaster:BAAALgAECgQJBAAAAA==.Fluffykat:BAABLgAECn8fAAIHAAgJWRNqBwCEAQAHAAgJWRNqBwCEAQAAAA==.',
Fo='Foonnz:BAAALgAECgYJBgAAAA==.Fosho:BAACLgAFFH8WAAIJAAYJ+RJHAQCEAQAJAAYJ+RJHAQCEAQAuAAQKfzAAAwkACQn+H8kAALUCAAkACQn+H8kAALUCAAoABwl2F68kAAMCAAAA.Fourgot:BAAALgAECgcJEQAAAA==.Fourwhat:BAAALgADCgEJAQAAAA==.',
Fr='Fraud:BAAALgAECgYJBgABLgAECggJHAANANgeAA==.Freddysjr:BAAALgADCgMJAwAAAA==.Freelvlsvnty:BAAALgAECgEJAQAAAA==.Froddy:BAAALgADCgQJBAAAAA==.Frylockk:BAAALgAECgYJCwAAAA==.',
Fu='Fugoh:BAAALgADCgUJBQAAAA==.Furmancummin:BAAALgAECgUJCQAAAA==.Furrykane:BAEBLgAECn8cAAQHAAgJ8CJjAQB2AgAHAAgJ8CJjAQB2AgAUAAIJURnKIwB+AAAgAAEJVxpoMwA0AAAAAA==.Future:BAABLgAECn8dAAIZAAgJahrXAQDzAQAZAAgJahrXAQDzAQAAAA==.Fuwu:BAAALgAECgQJBAAAAA==.',
Ga='Gabrrof:BAAALgADCgkJEQAAAA==.Ganonn:BAAALgADCgYJBgAAAA==.',
Gh='Ghadafi:BAAALgADCgQJBAABLgAECgYJFQAOAA0eAA==.',
Gi='Gillerd:BAAALgADCgUJCgAAAA==.Gills:BAAALgAECgMJBAAAAA==.Girthman:BAAALgAECgUJCwAAAA==.',
Go='Gogurt:BAAALgAECgYJBgAAAA==.Goju:BAAALgAECgUJCgAAAA==.Golfpro:BAAALgADCgcJAQAAAA==.Goobe:BAAALgAECgQJBQABLgAECgcJGwADANUaAA==.Goonela:BAAALgADCgEJAQAAAA==.',
Gr='Grinkle:BAAALgADCgQJBAAAAA==.Griselbrand:BAAALgADCgMJAwAAAA==.Gromlo:BAABLgAECn8aAAITAAgJJBzsEwCXAgATAAgJJBzsEwCXAgAAAA==.Grulog:BAAALgAECgQJCQAAAA==.',
Gu='Guatonfate:BAAALgADCgEJAQAAAA==.Gucciî:BAAALgAECgEJAQAAAA==.Gummiebear:BAAALgAECgYJBgAAAA==.Gunny:BAAALgAECgUJDwAAAA==.',
['Gã']='Gã:BAABLgAECn8WAAICAAYJ7R+vPAABAgACAAYJ7R+vPAABAgAAAA==.',
Ha='Haileigh:BAAALgADCgkJGAAAAA==.',
He='Healems:BAAALgAECgEJAQAAAA==.Hellenkiller:BAAALgADCgEJAQAAAA==.',
Hi='Hikawa:BAABLgAECn8WAAMhAAcJ1yDqAwAbAgAhAAcJmSDqAwAbAgARAAUJ+RvWHwBWAQAAAA==.',
Ho='Honortheox:BAAALgADCgYJBgAAAA==.Hosslight:BAAALgAECgYJBgAAAA==.Hottz:BAABLgAECn8lAAMTAAcJDyDWHwBCAgATAAcJDyDWHwBCAgAgAAEJgwPFDgA0AAAAAA==.',
Hu='Hummice:BAAALgAECgIJAgAAAA==.Huntemall:BAAALgADCgcJDAABLgADCggJCAAEAAAAAA==.',
['Hà']='Hàvoc:BAAALgAECgIJAgABLgAECggJHAARABgaAA==.',
['Hä']='Hävoc:BAABLgAECn8cAAIRAAgJGBovPgB/AgARAAgJGBovPgB/AgAAAA==.',
Ic='Iceshards:BAABLgAECn8cAAIRAAcJ3QW8MAAGAQARAAcJ3QW8MAAGAQAAAA==.',
Id='Idtrapthat:BAAALgAECgMJAwAAAA==.',
Ik='Ike:BAAALgAECgcJDwAAAA==.',
Il='Illidank:BAAALgADCgkJCQAAAA==.Illidankior:BAACLgAFFH8GAAIfAAMJDh94AgAfAQAfAAMJDh94AgAfAQAuAAQKfx8AAx8ACAkLIuYEAPYCAB8ACAkLIuYEAPYCAAYAAwmxC3QsAJEAAAEuAAMKCQkJAAQAAAAA.Illirothas:BAABLgAECn8YAAQCAAYJUxOYgQAmAQACAAYJkA+YgQAmAQAiAAMJEhVwTAC9AAAjAAMJlQ4JIgByAAABLgAECgcJDgAEAAAAAA==.Illisteve:BAAALgAECgYJBgAAAA==.',
Im='Imawizard:BAABLgAECn8eAAIRAAgJPhcWCgAJAgARAAgJPhcWCgAJAgAAAA==.Immadewsh:BAAALgAECgYJAgAAAA==.Impoosh:BAAALgAECgcJDwAAAA==.Imsassy:BAAALgAECgIJAgAAAA==.',
In='Infectedbøb:BAAALgAECgYJDAAAAA==.Infekt:BAAALgAECgYJBQAAAA==.Inmortuae:BAAALgAECgIJAgABLgAECgcJDgAEAAAAAA==.Innovation:BAAALgAECgQJBwAAAA==.',
Ip='Iprayntank:BAAALgAECgYJDwAAAA==.',
Ir='Ir:BAAALgAECggJCwAAAA==.Irissela:BAAALgADCgkJDQAAAA==.',
Iv='Ivalice:BAABLgAECn8bAAQDAAgJ+R98AwDuAgADAAgJ+R98AwDuAgAcAAEJ4hl9zAA5AAAWAAEJkAM5lQAkAAAAAA==.',
Iz='Izanamii:BAABLgAECn8cAAICAAgJORONWQCVAQACAAgJORONWQCVAQAAAA==.Izüal:BAAALgADCgkJCQABLgAECgYJCAAEAAAAAA==.',
Ja='Jaaros:BAAALgADCggJCQAAAA==.Jafbe:BAAALgADCgYJBwAAAA==.Jaxxid:BAAALgADCggJCQAAAA==.Jaymie:BAAALgAECgMJAwAAAA==.Jazlern:BAAALgAECgMJAwAAAA==.',
Je='Jesilpriest:BAAALgADCgMJAwAAAA==.',
Jh='Jherekal:BAAALgAECgMJBQAAAA==.',
Ji='Jimcarrey:BAAALgAECgYJDwAAAA==.',
Jo='Joemauma:BAABLgAECn8VAAIRAAcJDRNOFQCYAQARAAcJDRNOFQCYAQAAAA==.Joslin:BAAALgADCgEJAQABLgAFFAMJBgATADEVAA==.',
Jp='Jpam:BAAALgAECgYJCgAAAA==.',
Ju='July:BAAALgADCgEJAQABLgAECgYJCAAEAAAAAA==.Jumbosize:BAACLgAFFH8QAAMTAAYJOBq/AQCrAQATAAYJOBq/AQCrAQAHAAEJrAZ6HABEAAAuAAQKfygAAhMACQkjJcEAALgDABMACQkjJcEAALgDAAAA.Junrage:BAABLgAFFH8LAAINAAUJ3xXuCgBOAQANAAUJ3xXuCgBOAQAAAA==.Jupîter:BAAALgAECgYJCgAAAA==.Justmeldit:BAAALgAECgIJAgAAAA==.',
Ka='Kaelis:BAAALgAECgEJAgAAAA==.Kaelish:BAAALgAECgcJDQAAAA==.Kaerlif:BAAALgAECggJDQABLgAFFAMJBgAiAFgfAA==.Kaiyley:BAAALgAECgYJEgAAAA==.Kajortak:BAAALgAECgYJBwAAAA==.Kalastrian:BAAALgAECgYJEQAAAA==.Kangna:BAAALgADCgIJAgAAAA==.Karateshock:BAABLgAECn8eAAIKAAgJyBqpBAAiAgAKAAgJyBqpBAAiAgAAAA==.Karlor:BAABLgAECn8UAAINAAYJkA7UFAD2AAANAAYJkA7UFAD2AAAAAA==.Kasheeshb:BAAALgAECgQJBAAAAA==.Kazuren:BAAALgAECgYJEwAAAA==.',
Ke='Keahoa:BAAALgADCgcJBwAAAA==.Keano:BAAALgAECgYJEAAAAA==.Keeldemall:BAAALgAECgQJBAAAAA==.Kelia:BAAALgAECgEJAQABLgAECgcJDgAEAAAAAA==.Kelinna:BAABLgAECn8ZAAILAAYJTBVDJAAXAQALAAYJTBVDJAAXAQAAAA==.Kenichix:BAABLgAECn8WAAICAAgJ2R9FFgDRAgACAAgJ2R9FFgDRAgAAAA==.Kennidan:BAAALgAECgUJCQAAAA==.Kenshìn:BAAALgADCgEJAQAAAA==.Keymaster:BAAALgADCgIJAgAAAA==.',
Kf='Kfcchicken:BAAALgAECgEJAQAAAA==.',
Ki='Kiritoo:BAAALgAECgEJAgAAAA==.',
Kl='Klaye:BAAALgAECgQJCAABLgAECgYJEQAEAAAAAA==.',
Ko='Kodabonk:BAABLgAECn8VAAMQAAgJhg9QKgC4AQAQAAgJhg9QKgC4AQAkAAEJtQ2bgAAwAAAAAA==.Kodanorth:BAAALgADCgEJAQABLgAECggJFQAQAIYPAA==.Kombata:BAAALgAECgYJBgAAAA==.Kombatant:BAAALgAECgUJCQAAAA==.Kotara:BAAALgAECgMJBAAAAA==.',
Kr='Kraur:BAAALgAECgQJBAABLgAECgcJDgAEAAAAAA==.',
Ku='Kumoj:BAAALgADCgkJBwAAAA==.Kunglaoo:BAAALgADCgEJAQAAAA==.',
La='Lag:BAAALgADCgYJBgAAAA==.Lame:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.Lampp:BAAALgAECgQJBQABLgAECggJFAAYABoaAA==.Laws:BAAALgAECgYJDAAAAA==.',
Le='Leezerd:BAAALgADCgYJCQAAAA==.Lexsapphire:BAABLgAECn8XAAIRAAYJuwNnNwDmAAARAAYJuwNnNwDmAAAAAA==.',
Li='Liaeda:BAABLgAECn8cAAIDAAgJzwwFBwBMAQADAAgJzwwFBwBMAQAAAA==.Lianshi:BAAALgAECgYJDQAAAA==.Lichplease:BAABLgAECn8dAAIYAAgJUB+zLACGAgAYAAgJUB+zLACGAgAAAA==.Lilithandral:BAABLgAECn8bAAIfAAgJIRYDEgDnAQAfAAgJIRYDEgDnAQAAAA==.Limitedtank:BAAALgAECgQJDgAAAA==.Linainverse:BAAALgAECgMJBQAAAA==.Lithdradra:BAAALgADCgEJAQAAAA==.Livermaw:BAAALgADCgIJAgAAAA==.',
Lo='Logjammin:BAAALgADCgYJBgABLgAECgcJEwAEAAAAAA==.Lolo:BAAALgAECgYJBwABLgAFFAYJFgAJAPkSAA==.Loosie:BAABLgAECn8eAAIiAAcJdyEJAgAKAgAiAAcJdyEJAgAKAgAAAA==.',
Lu='Lucylepricon:BAAALgAECgQJBwAAAA==.Ludo:BAABLgAECn8VAAICAAYJ6CDaTgC6AQACAAYJ6CDaTgC6AQAAAA==.Luduhcris:BAAALgADCgYJBgAAAA==.Luebbersit:BAAALgAECgEJAgAAAA==.Luebberslueb:BAAALgAECgEJAQAAAA==.Luebberstiny:BAAALgADCgEJAwAAAA==.Lugnuts:BAAALgAECgQJBgAAAA==.Luketich:BAACLgAFFH8MAAIbAAQJHQmKAgDbAAAbAAQJHQmKAgDbAAAuAAQKfykAAhsACAlyHoMGAIACABsACAlyHoMGAIACAAAA.Lumiltiand:BAACLgAFFH8FAAIYAAMJ4xHdKAD1AAAYAAMJ4xHdKAD1AAAuAAQKfxkAAhgACAnmIFg7AEkCABgACAnmIFg7AEkCAAAA.',
['Lú']='Lústì:BAAALgADCgcJCQABLgAECgUJCQAEAAAAAA==.',
Ma='Mafia:BAAALgADCgIJAgAAAA==.Mahuizmaca:BAABLgAECn8eAAMFAAgJwyAiAQDPAgAFAAgJwyAiAQDPAgALAAYJmBZ+fwB7AQAAAA==.Malakaa:BAAALgAECgIJAgAAAA==.Maleficante:BAAALgADCgUJBQABLgAECgYJEwAEAAAAAA==.Malgoros:BAABLgAECn8eAAMCAAgJnhxzCQDcAQACAAgJnhxzCQDcAQAiAAEJ1B1gbAA5AAAAAA==.Malgrendin:BAABLgAECn8XAAIcAAcJfCLHEgChAgAcAAcJfCLHEgChAgAAAA==.Mallock:BAAALgAECgIJAgAAAA==.Maluma:BAAALgADCgYJBgAAAA==.Malédictias:BAAALgADCgcJDQAAAA==.Mamii:BAAALgAECgYJDwAAAA==.Manaag:BAAALgAECgMJBAAAAA==.Manataurus:BAAALgADCgUJBQAAAA==.Manatreat:BAAALgADCgEJAgAAAA==.Manuall:BAAALgAECgcJEAAAAA==.Maralyn:BAABLgAECn8dAAIbAAgJVgjEBwAEAQAbAAgJVgjEBwAEAQAAAA==.Marshmellow:BAACLgAFFH8HAAIOAAMJ8hMfDwD7AAAOAAMJ8hMfDwD7AAAuAAQKfyAAAw4ACAkgHsotAFYCAA4ACAk/HcotAFYCABcABAlaF1InACcBAAAA.Martense:BAAALgAECgYJCAAAAA==.Mawly:BAAALgAECgYJCAAAAA==.Maxidk:BAABLgAECn8lAAIYAAgJxCSYAQC5AgAYAAgJxCSYAQC5AgAAAA==.Maxilock:BAAALgADCgYJEgABLgAECggJJQAYAMQkAA==.Maximonk:BAAALgADCgkJDQABLgAECggJJQAYAMQkAA==.Maxipriest:BAAALgADCgUJBQAAAA==.Maxisdamage:BAABLgAECn8bAAIRAAgJqRavEgCsAQARAAgJqRavEgCsAQAAAA==.Mazpaladin:BAAALgADCgUJBQAAAA==.',
Mc='Mcclownerson:BAAALgADCgYJDQABLgADCgcJCwAEAAAAAA==.',
Me='Melissarian:BAAALgAECgYJEQAAAA==.Mereoleona:BAABLgAECn8VAAIOAAYJDR7NPwAOAgAOAAYJDR7NPwAOAgAAAA==.',
Mi='Midgemaisel:BAAALgAECgYJCgAAAA==.Mirado:BAAALgAECgYJEgAAAA==.Misplacer:BAAALgAECgcJEwAAAA==.Mithridates:BAAALgAECgYJDQAAAA==.',
Mk='Mkherp:BAAALgAECgcJDwAAAA==.',
Mo='Mohg:BAAALgADCgUJCAAAAA==.Momentjess:BAACLgAFFH8FAAIeAAIJ5xsSEQC3AAAeAAIJ5xsSEQC3AAAuAAQKfx8AAx4ACAlYIiYEAB0DAB4ACAlYIiYEAB0DAAgABwlcF6siAM8BAAAA.Monkragga:BAAALgADCgUJBQABLgAECggJHQAMAK8YAA==.Morrygan:BAAALgAECgEJAgAAAA==.Mortarien:BAAALgAECgQJBwAAAA==.Mortïx:BAABLgAECn8hAAIWAAgJbSJIAACkAgAWAAgJbSJIAACkAgAAAA==.',
My='Myrtle:BAAALgADCgEJAQAAAA==.Mystborne:BAAALgAECgIJAgABLgAECgYJDAAEAAAAAA==.',
Ne='Nevernude:BAABLgAECn8dAAIFAAcJUCJcAQC6AgAFAAcJUCJcAQC6AgAAAA==.Nexflamma:BAAALgAECgYJEwAAAA==.',
Ni='Niaru:BAAALgAECgUJDQAAAA==.Ninjay:BAAALgADCgUJBQAAAA==.Nirathren:BAAALgADCgEJAQABLgAECgQJCQAEAAAAAA==.Niwatori:BAABLgAECn8YAAIHAAgJVh99AQBuAgAHAAgJVh99AQBuAgAAAA==.',
No='Noah:BAACLgAFFH8WAAIDAAYJeCESAAD3AQADAAYJeCESAAD3AQAuAAQKfx8AAgMACAl3JjwBAFgDAAMACAl3JjwBAFgDAAAA.Nolarz:BAACLgAFFH8XAAIlAAYJmCQFAAALAgAlAAYJmCQFAAALAgAuAAQKfyIAAyUACAkTJtsAAE4DACUACAkTJtsAAE4DABoAAQm+H+teADgAAAAA.Noor:BAACLgAFFH8IAAICAAUJoR1NBgC/AQACAAUJoR1NBgC/AQAuAAQKfxYAAgIACAm9I5IVANUCAAIACAm9I5IVANUCAAEuAAUUBgkKAAsA8RgA.Norbon:BAAALgADCgcJCwAAAA==.Nothhelm:BAAALgAECgQJCQAAAA==.',
Nu='Nugnug:BAACLgAFFH8IAAIYAAMJLxnnIQAQAQAYAAMJLxnnIQAQAQAuAAQKfxYAAhgACAn4IV4cANQCABgACAn4IV4cANQCAAEuAAUUBAkKAAgA2BUA.Nukthom:BAAALgAECgYJEQAAAA==.',
Ny='Nyahbinghi:BAAALgADCgkJEwABLgAECgEJAQAEAAAAAA==.Nylthoran:BAAALgADCgEJAQAAAA==.Nyneaves:BAABLgAECn8ZAAIBAAgJYBPxBADHAQABAAgJYBPxBADHAQAAAA==.',
Oh='Ohmenwah:BAAALgAECgQJBwAAAA==.',
Oj='Ojplosion:BAAALgAECgMJAwABLgAECgcJDAAEAAAAAA==.Ojpyroblast:BAAALgAECgcJDAAAAA==.',
Om='Omghunter:BAAALgAECgYJEwAAAA==.',
On='Onisprite:BAABLgAECn8UAAMNAAcJzAyMVABYAQANAAcJzAyMVABYAQAGAAMJWgOSEABTAAAAAA==.',
Op='Optimish:BAAALgAECgEJAQAAAA==.',
Or='Ordhah:BAAALgAECgYJCAAAAA==.',
Os='Osanna:BAAALgAECgYJCwAAAA==.',
Ou='Outy:BAABLgAECn8WAAMOAAYJDxgxYwCgAQAOAAYJDxgxYwCgAQAXAAEJbgNHfQAhAAAAAA==.',
Ow='Owmyleg:BAAALgAECgYJCwAAAA==.',
Ox='Oxijinn:BAAALgAECgQJBQAAAA==.',
Pa='Pacanuch:BAAALgADCgYJCwAAAA==.Padding:BAAALgADCgMJAwAAAA==.Pakhan:BAABLgAECn8dAAIlAAgJzQkmAgCQAQAlAAgJzQkmAgCQAQAAAA==.Paladina:BAAALgADCgEJAQAAAA==.Paladout:BAABLgAECn8aAAMLAAgJ+RvXNgBHAgALAAcJThvXNgBHAgAbAAYJZhjRFQB0AQAAAA==.Pallo:BAAALgADCgkJHwAAAA==.Paona:BAABLgAECn8dAAIHAAgJGQtMCwA4AQAHAAgJGQtMCwA4AQAAAA==.',
Pe='Pengting:BAAALgAECgYJCgAAAA==.Perajuve:BAAALgADCgYJBgABLgAECgkJGAAkAE0dAA==.Peraroll:BAABLgAECn8YAAIkAAkJTR0LCQDnAgAkAAkJTR0LCQDnAgAAAA==.Petz:BAAALgAECgUJDgAAAA==.',
Ph='Phaedrah:BAAALgAECgYJDgAAAA==.Phenphen:BAACLgAFFH8FAAMaAAMJMh5yBwDCAAAaAAMJcRRyBwDCAAAlAAEJ+iJNBQBlAAAuAAQKfxwAAyUACAlJIt8CALcCACUACAm7Ht8CALcCABoABglIHwcLACMBAAAA.Phuryphen:BAAALgADCgQJBAABLgAFFAMJBQAaADIeAA==.Physicyan:BAAALgAECgYJBgAAAA==.',
Pi='Piakchu:BAAALgADCgcJEwAAAA==.Pix:BAAALgAECgIJAwAAAA==.',
Pl='Plonterstank:BAAALgAECgcJEwAAAA==.',
Po='Pohealer:BAAALgAECgEJAwAAAA==.Pookie:BAAALgAECgEJAQAAAA==.Poombah:BAAALgAECgUJCgAAAA==.Popori:BAAALgADCgcJCQAAAA==.Popshampain:BAAALgAECgQJCgAAAA==.',
Pr='Preest:BAAALgAECgUJBQABLgAECggJIgAFADobAA==.Proudmoo:BAABLgAECn8cAAIFAAgJ9R0JAQDWAgAFAAgJ9R0JAQDWAgAAAA==.Provoke:BAAALgAECgEJAwAAAA==.',
Ps='Psion:BAAALgAECgEJAQAAAA==.',
Pu='Pumaa:BAAALgAECgYJDAAAAA==.',
Qu='Quickben:BAAALgADCgEJAQAAAA==.',
Ra='Raenlling:BAAALgADCgMJAwAAAA==.Ragehoof:BAAALgAECgUJBQAAAA==.Raise:BAAALgAECgYJDgAAAA==.Rathoril:BAAALgAECgYJEAAAAA==.Ratscum:BAAALgAECgQJCgABLgAECgYJCAAEAAAAAA==.Raxik:BAAALgADCgIJAgAAAA==.Raynor:BAAALgAECgEJAQAAAA==.Rayssa:BAABLgAECn8dAAIeAAgJiCRsAAAnAwAeAAgJiCRsAAAnAwAAAA==.',
Re='Redeker:BAAALgAECgYJDQAAAA==.Regera:BAAALgAECgEJAQAAAA==.Renardfurtif:BAAALgAECgYJBwAAAA==.Reninni:BAAALgAECgUJCAAAAA==.Rentahunter:BAAALgAECgcJCgAAAA==.Revolatiion:BAAALgADCgEJAQAAAA==.Revolationzs:BAAALgAECgEJAQAAAA==.',
Rh='Rhaanz:BAAALgADCgMJAwAAAA==.Rhynearas:BAAALgADCgUJBQABLgAECggJHAADAM8MAA==.',
Ri='Ridell:BAAALgADCgcJGQAAAA==.Rimasjobas:BAAALgAECgIJAgAAAA==.Rimestar:BAAALgAECgEJAQAAAA==.Rinda:BAAALgADCgUJBQABLgAECgYJBwAEAAAAAA==.Ripoodoo:BAAALgAECgQJBAAAAA==.',
Rn='Rngeesus:BAAALgAECgYJDwAAAA==.Rngnar:BAAALgAECgUJDQAAAA==.',
Ro='Rocklie:BAAALgADCgYJBgAAAA==.Roguewolf:BAABLgAECn8WAAIHAAcJZBJoLQCYAQAHAAcJZBJoLQCYAQAAAA==.Roki:BAAALgAECgYJEQAAAA==.Rolow:BAABLgAECn8bAAIRAAgJGhzeEgCrAQARAAgJGhzeEgCrAQAAAA==.Ronlock:BAAALgAECgIJAgAAAA==.Rooni:BAABLgAFFH8KAAILAAYJ8RgkAgDsAQALAAYJ8RgkAgDsAQAAAA==.Roony:BAAALgAECgcJDAABLgAFFAYJCgALAPEYAA==.Rossaruu:BAAALgAECgcJBwAAAA==.Rot:BAABLgAECn8eAAQYAAgJICSEFwDuAgAYAAgJFySEFwDuAgAdAAEJ7SJAPABkAAAmAAEJxhlaFABNAAAAAA==.Royle:BAAALgAECgcJDAAAAA==.',
Ru='Rune:BAAALgAECgYJEQAAAA==.Runnerjay:BAAALgADCgYJDQABLgAECggJIQAbAOMOAA==.Rush:BAABLgAECn8UAAIRAAYJyBl3IwBEAQARAAYJyBl3IwBEAQAAAA==.Ruuf:BAAALgAECgcJBwAAAA==.',
Ry='Rysango:BAABLgAECn8XAAICAAgJFSP3AgB7AgACAAgJFSP3AgB7AgAAAA==.Ryuujins:BAACLgAFFH8MAAIeAAUJpSBSAQDWAQAeAAUJpSBSAQDWAQAuAAQKfxwAAx4ACAl4JJkDAC8DAB4ACAl4JJkDAC8DAAgAAwmmGxtXANkAAAAA.',
Sa='Saelria:BAAALgAECgUJCgAAAA==.Saidar:BAAALgADCgcJCAAAAA==.Sainthoovr:BAABLgAECn8dAAMeAAcJoiQaAQCpAgAeAAcJoiQaAQCpAgABAAMJix1rPgABAQAAAA==.Saintluke:BAAALgAECgQJCAAAAA==.Sakuraa:BAABLgAECn8UAAIaAAgJnQe/KQCtAQAaAAgJnQe/KQCtAQAAAA==.Sandia:BAAALgADCgYJCwAAAA==.Sausage:BAAALgADCgYJBgAAAA==.',
Sc='Scam:BAAALgADCgcJCAAAAA==.Scumrat:BAAALgAECgYJCAAAAA==.Scyon:BAAALgAECggJEwAAAA==.',
Se='Seladorei:BAABLgAECn8aAAInAAcJ0iNRAQDbAgAnAAcJ0iNRAQDbAgAAAA==.Senari:BAAALgAECgYJDgAAAA==.',
Sh='Shadowblazer:BAABLgAECn8ZAAIOAAgJshoQSwDoAQAOAAgJshoQSwDoAQAAAA==.Shadowrainz:BAABLgAECn8WAAIBAAYJCxUjKQCRAQABAAYJCxUjKQCRAQAAAA==.Shalizar:BAAALgAECgEJAQAAAA==.Shanda:BAAALgAFFAIJAgAAAA==.Shankukindly:BAAALgAECgcJCQAAAA==.Shanto:BAAALgAECgYJEQAAAA==.Shiftinmojo:BAAALgAECgEJAQAAAA==.Shoumei:BAABLgAECn8aAAMkAAgJ1hy7DACuAgAkAAgJ1hy7DACuAgAQAAEJ1wKFjwAlAAAAAA==.Shuken:BAAALgAECgEJAwAAAA==.Shwip:BAABLgAECn8iAAMHAAgJViGrCQD6AgAHAAgJViGrCQD6AgATAAYJ4xEWIAC1AAAAAA==.',
Si='Sickamage:BAABLgAECn8YAAMRAAgJ1xmDSQBaAgARAAgJdxiDSQBaAgAhAAMJZxynDwDHAAAAAA==.Silfra:BAAALgAECgcJEQAAAA==.Sillas:BAAALgADCgIJAgAAAA==.Silvinos:BAAALgAECgEJAgAAAA==.',
Sl='Slapparazzi:BAAALgADCgYJBgAAAA==.Sleepingmad:BAAALgAFFAEJAQAAAA==.Sloothix:BAAALgAECgcJCgABLgAECgkJCQAEAAAAAA==.Slothbob:BAAALgADCgEJAQAAAA==.Slushië:BAAALgAECgQJBgAAAA==.',
Sm='Smilingdev:BAAALgAECgUJBwABLgAECgkJHQAIAEAaAA==.Smittytank:BAAALgAECgEJAQAAAA==.',
So='Soulsproxy:BAAALgAECgIJAgAAAA==.',
Sp='Spawwn:BAAALgADCggJCAABLgAECgcJGwADANUaAA==.Spazdeath:BAAALgAECgQJBAAAAA==.Spellberg:BAAALgAECgQJBAAAAA==.Spilby:BAAALgADCgEJAgAAAA==.',
Sq='Squashee:BAAALgAECgUJBQAAAA==.Squishymonk:BAAALgADCgUJBQAAAA==.',
Ss='Ssilb:BAAALgAECgUJBQAAAA==.',
St='Stabbz:BAABLgAECn8YAAIaAAYJ7hJ1CQBAAQAaAAYJ7hJ1CQBAAQAAAA==.Stepdad:BAAALgAECgIJAgAAAA==.Steviewonder:BAAALgAECgMJAwABLgAECgcJDAAEAAAAAA==.Stillasleep:BAAALgAECgYJEAAAAA==.Stonatroll:BAAALgAECgQJBAABLgAECgcJDgAEAAAAAA==.Stormdemon:BAAALgAECgYJEgAAAA==.Stormspellz:BAABLgAECn8aAAIKAAgJ9RhaGwA9AgAKAAgJ9RhaGwA9AgAAAA==.Stormyspellz:BAAALgAECgYJDwAAAA==.',
Su='Subwayeater:BAABLgAECn8cAAISAAgJaBHQHwCAAQASAAgJaBHQHwCAAQAAAA==.Subzro:BAABLgAECn8WAAIRAAYJCBSJqQCHAQARAAYJCBSJqQCHAQAAAA==.Summäurs:BAAALgADCgMJAwABLgAECgYJCgAEAAAAAA==.Supay:BAAALgAECgYJCgAAAA==.Suwgo:BAAALgADCgIJAgAAAA==.',
Sy='Sylosis:BAABLgAECn8XAAIYAAcJLA5JggB+AQAYAAcJLA5JggB+AQAAAA==.Syzzle:BAACLgAFFH8GAAIRAAMJuhMRFADzAAARAAMJuhMRFADzAAAuAAQKfxYAAxEACAnxH442AJoCABEACAlIH442AJoCACgAAwnuHUcIAOcAAAAA.',
Ta='Takkiya:BAAALgAECgEJAQAAAA==.Talicso:BAACLgAFFH8GAAIRAAMJdAgBFQDkAAARAAMJdAgBFQDkAAAuAAQKfx8AAxEACAmKHR9BAHUCABEACAmKHR9BAHUCACEABAkXEd8OANUAAAAA.Talos:BAAALgAECgUJBQABLgAECggJHAANANgeAA==.Talzinn:BAAALgAECggJCQABLgAECggJHAANANgeAA==.Tam:BAAALgAECgEJAQABLgAFFAYJFgADAHghAA==.Tankr:BAAALgAECgUJBQAAAA==.Tarkinal:BAABLgAECn8UAAIKAAYJdR5DBgD1AQAKAAYJdR5DBgD1AQAAAA==.',
Te='Teezee:BAABLgAECn8iAAILAAgJ4iEnAgCkAgALAAgJ4iEnAgCkAgAAAA==.Telina:BAAALgADCgQJBAAAAA==.Temetnosce:BAAALgADCgcJBgAAAA==.Tempura:BAABLgAECn8bAAIRAAgJJhtVDADsAQARAAgJJhtVDADsAQAAAA==.Tenebros:BAAALgAECgEJAQAAAA==.',
Th='Thanatus:BAAALgAECgYJDAAAAA==.Thath:BAAALgAECgYJDQAAAA==.Thaulnor:BAAALgADCgEJAgAAAA==.Thavus:BAAALgAECgEJAwAAAA==.Thelendris:BAAALgAECgIJAgAAAA==.Themartian:BAABLgAECn8ZAAMpAAYJOBU3KAB0AQApAAYJOBU3KAB0AQAkAAMJOQRsZQB3AAAAAA==.Theshinigami:BAAALgAECgQJBAAAAA==.Thevinny:BAAALgADCgcJCwAAAA==.Thruumm:BAAALgAECgYJBgAAAA==.Thunsibution:BAAALgAECgQJBAABLgADCgkJCQAEAAAAAA==.Thydriel:BAAALgADCgcJBwABLgAECggJIAATAGMcAA==.',
Ti='Tickz:BAABLgAECn8dAAQPAAgJ1SJYAQDjAgAPAAcJhiNYAQDjAgAOAAYJ7hVYEgB+AQAXAAIJ0BnZDABcAAAAAA==.Tidepods:BAAALgADCgIJAgAAAA==.Tistic:BAAALgAECgEJAgAAAA==.',
To='Toeran:BAABLgAECn8eAAIbAAgJLRrxAQDyAQAbAAgJLRrxAQDyAQAAAA==.Tokémon:BAAALgAECgMJAwAAAA==.Totesup:BAAALgAECgMJBAAAAA==.',
Tr='Traelin:BAAALgAECgQJCAABLgAFFAMJBgATADEVAA==.Traylesong:BAAALgADCgYJCgAAAA==.Tread:BAABLgAECn8aAAINAAgJkx8dCQAaAwANAAgJkx8dCQAaAwAAAA==.Trickee:BAAALgAECgYJDwABLgAECgYJDwAEAAAAAA==.',
Ts='Tskaha:BAAALgAECgQJBAAAAA==.',
Tu='Tulip:BAAALgADCgkJFgAAAA==.',
Ty='Tyria:BAABLgAECn8VAAIWAAcJBxCzPQBkAQAWAAcJBxCzPQBkAQAAAA==.Tyronius:BAAALgAECgUJDAAAAA==.',
Um='Umbraxion:BAABLgAECn8cAAIVAAgJ/AnVFQCRAQAVAAgJ/AnVFQCRAQAAAA==.',
Un='Undeadmerlin:BAAALgAECgYJBgAAAA==.',
Ur='Urabrask:BAAALgADCgUJBQABLgAECgYJBgAEAAAAAA==.',
Va='Vanstan:BAAALgADCgUJBQABLgAFFAUJCQARAG4IAA==.Varg:BAAALgADCgEJAQAAAA==.Varsil:BAAALgAECgQJBQAAAA==.Vashstampede:BAAALgAECgUJCQAAAA==.',
Ve='Velithiria:BAABLgAECn8hAAIcAAgJkxP2JAAoAgAcAAgJkxP2JAAoAgAAAA==.Velrik:BAAALgAECgYJDgAAAA==.Venerable:BAAALgAECgMJBwAAAA==.Vernali:BAAALgAECgYJCwAAAA==.Vernalia:BAAALgAECgEJAgABLgAECgYJCwAEAAAAAA==.Vezdormi:BAAALgAECgQJBAABLgAECggJHAAVAC0mAA==.Vezdormu:BAABLgAECn8cAAIVAAgJLSbZAABuAwAVAAgJLSbZAABuAwAAAA==.',
Vi='Vitrixz:BAAALgADCggJFgAAAA==.Vizdicator:BAABLgAECn8jAAIbAAgJBhSpBABhAQAbAAgJBhSpBABhAQAAAA==.Viztryalle:BAAALgAECgEJAQAAAA==.',
Vu='Vulcãnus:BAAALgAECgQJBwABLgAECgYJCgAEAAAAAA==.',
We='Werse:BAABLgAECn8aAAIIAAgJVhvGDgByAgAIAAgJVhvGDgByAgAAAA==.',
Wh='Whodi:BAAALgADCgIJAwAAAA==.',
Wi='Willowdusk:BAAALgAECgMJBAABLgAECgYJBgAEAAAAAA==.Willowmist:BAAALgAECgYJBgAAAA==.Willtolive:BAAALgADCggJCAAAAA==.Wind:BAAALgAECgQJBAAAAA==.',
Wr='Wrathofpride:BAAALgADCgYJBgAAAA==.',
Xa='Xackta:BAAALgADCgcJBgAAAA==.Xantom:BAAALgADCgYJBgAAAA==.Xatan:BAAALgAECgEJAwAAAA==.',
Xj='Xjeshy:BAAALgADCggJEQAAAA==.Xjoshy:BAAALgADCgYJDAAAAA==.',
Xn='Xnatem:BAAALgAECgYJEQAAAA==.',
['Xë']='Xëllos:BAAALgADCgQJBAAAAA==.',
Ya='Yashiro:BAAALgAECgYJEwAAAA==.',
Ye='Yeraleth:BAABLgAECn8gAAITAAgJYxzZFwB4AgATAAgJYxzZFwB4AgAAAA==.',
Yi='Yisiwang:BAAALgADCgMJAwAAAA==.',
Yo='Yorkj:BAAALgAECgYJCQAAAA==.',
Yv='Yvonca:BAAALgADCgEJAQAAAA==.',
Za='Zalthorax:BAAALgAECgcJDgAAAA==.Zarri:BAAALgADCgUJBQAAAA==.Zatilion:BAABLgAECn8UAAILAAcJ2wrhjwBcAQALAAcJ2wrhjwBcAQAAAA==.',
Ze='Zenju:BAAALgAECgEJAgAAAA==.Zenki:BAAALgAECgYJCQAAAA==.Zepharion:BAAALgAECgYJCQAAAA==.Zephiday:BAABLgAECn8fAAIBAAgJBxt4DgCcAgABAAgJBxt4DgCcAgAAAA==.Zerfonk:BAAALgAECgcJEwAAAA==.',
Zh='Zhushii:BAABLgAECn8WAAIHAAcJ/xTZKQCxAQAHAAcJ/xTZKQCxAQAAAA==.',
Zi='Ziggamoo:BAAALgADCgYJBgABLgAECgcJGwADANUaAA==.Ziggashot:BAABLgAECn8bAAIDAAcJ1RqRAwDDAQADAAcJ1RqRAwDDAQAAAA==.Zinsus:BAAALgADCgQJBAABLgAECgcJDgAEAAAAAA==.',
Zu='Zumbao:BAAALgAECgEJAQAAAA==.Zurahahshá:BAABLgAECn8YAAIZAAcJLwgdBgAtAQAZAAcJLwgdBgAtAQAAAA==.',
['Ðr']='Ðrow:BAABLgAECn8cAAIWAAgJLhZ8LQDBAQAWAAgJLhZ8LQDBAQAAAA==.',
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

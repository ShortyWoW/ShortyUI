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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','Priest-Discipline','DeathKnight-Unholy','Evoker-Augmentation','DeathKnight-Frost','Evoker-Preservation','Paladin-Retribution','Paladin-Protection','Priest-Holy','Shaman-Enhancement','Priest-Shadow','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Druid-Restoration','Druid-Balance','Hunter-Survival','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Rogue-Outlaw','Hunter-BeastMastery','Druid-Guardian','Warlock-Affliction','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aalduin:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCAAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgADCggJEQAAAA==.Aetna:BAAALgAECgYJBgABLgAECggJKwACAE0jAQ==.',
Af='Affli:BAABLgAECn8jAAIDAAgJriBAGwCxAgADAAgJriBAGwCxAgAAAA==.',
Ag='Agares:BAAALgADCggJFAAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5KEQDGAgAEAAgJ1h5KEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8eAAIFAAgJXhGSCQCVAQAFAAgJXhGSCQCVAQAAAA==.Aiupriesty:BAAALgAECgcJEgABLgAECggJHgAFAF4RAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgADCgUJAQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAAALgAECgEJAgAAAA==.Aleinara:BAAALgAECgQJCAAAAA==.Aleridin:BAABLgAECn8iAAIGAAgJnySeAQDhAgAGAAgJnySeAQDhAgAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAAALgAECgQJBQABLgAECgkJIQAHAAkiAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgADCgUJBQAAAA==.Annore:BAABLgAECn8ZAAIIAAgJ+RFIJQCrAQAIAAgJ+RFIJQCrAQAAAA==.Antihero:BAABLgAECn8fAAIIAAkJeCOKBwCmAgAIAAkJeCOKBwCmAgAAAA==.',
Aq='Aquiell:BAAALgAECgYJEAAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8GAAIFAAMJXhzhBwAHAQAFAAMJXhzhBwAHAQAuAAQKfysAAwUACAneIWQCAIQCAAUACAneIWQCAIQCAAQABQnQEJ0mAAsBAAAA.Arkenomu:BAABLgAECn8bAAIJAAgJLRGDDwCXAQAJAAgJLRGDDwCXAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8bAAMKAAcJpQeCBgAaAQAKAAcJpQeCBgAaAQAIAAYJsAHB7AClAAAAAA==.Asclepius:BAABLgAECn8YAAILAAgJaw5xCAChAQALAAgJaw5xCAChAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Asmira:BAAALgADCgYJCAAAAA==.Aspirin:BAAALgAECgYJDgAAAA==.Asynic:BAAALgAECgYJEwAAAA==.',
At='Atsunvhi:BAAALgAECgMJAwAAAA==.',
Av='Avadakedevra:BAAALgAECgcJEwAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azumok:BAAALgADCgEJAQAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Barackobooma:BAAALgADCgcJBwAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAAALgAECgcJEgAAAA==.',
Be='Belgaria:BAABLgAECn8XAAMMAAYJog9glQBSAQAMAAYJNQ9glQBSAQANAAQJNwzLJwAxAAAAAA==.Berryknight:BAABLgAECn8gAAIIAAgJexo5GgDrAQAIAAgJexo5GgDrAQAAAA==.Berryqt:BAAALgAECgQJBgAAAA==.Bewlzeye:BAAALgAECgIJAgAAAA==.',
Bi='Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8KAAIOAAMJvCbiBABWAQAOAAMJvCbiBABWAQAuAAQKfx0AAg4ACAmWJIoDACIDAA4ACAmWJIoDACIDAAAA.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodydk:BAAALgADCgMJAwAAAA==.Bluezugzug:BAAALgAECgIJAgAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8hAAIPAAgJwRVjBQDFAQAPAAgJwRVjBQDFAQAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bongonnaink:BAABLgAECn8hAAMQAAgJUSFBAwCKAgAQAAgJUSFBAwCKAgAHAAEJaBbhVgA0AAAAAA==.Bownyxia:BAACLgAFFH8JAAIJAAMJQBaFEQD1AAAJAAMJQBaFEQD1AAAuAAQKfy0AAwkACQnEIjEBAB4DAAkACQnEIjEBAB4DABEABAlGDvQpAM4AAAEuAAUUBgkcAAgANR4A.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAYJHAAIADUeAA==.Bowties:BAACLgAFFH8cAAMIAAYJNR7bAwDOAQAIAAUJNR7bAwDOAQASAAEJAAA2GQA4AAAuAAQKfzoAAwgACQnLJO4AAGMDAAgACQnLJO4AAGMDABIACQk3GHkKAHECAAAA.',
Br='Braximus:BAABLgAECn8XAAITAAcJCw9BHgAmAQATAAcJCw9BHgAmAQAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIUAAkJixvtCACuAgAUAAkJixvtCACuAgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8JAAIVAAQJvA0bFwAZAQAVAAQJvA0bFwAZAQAuAAQKfx0AAhUACQl3G5UDALsCABUACQl3G5UDALsCAAEuAAUUBgkcAAgANR4A.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgcJBwABLgAECgYJEgABAAAAAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgMJBwAAAA==.',
Ca='Caarrl:BAAALgAECgMJBAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBAAAAA==.Calii:BAAALgADCgkJCwAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgADCgUJBQAAAA==.Cayllia:BAABLgAECn8WAAMWAAgJ3iSQBABFAwAWAAgJ3iSQBABFAwAXAAcJACPvGwAiAgAAAA==.',
Ce='Celaris:BAAALgAECgIJAgAAAA==.',
Ch='Chataykay:BAAALgAECgYJBgAAAA==.Cherrypepsï:BAABLgAECn8XAAMOAAgJDQ/TKwCYAQAOAAgJDQ/TKwCYAQAHAAUJdgbtOADgAAAAAA==.Chipdip:BAAALgADCgEJAQAAAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAAALgAECgYJEwAAAA==.Citrus:BAABLgAECn8gAAIYAAgJghQICQDSAQAYAAgJghQICQDSAQAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBQAAAA==.Cliqmonk:BAAALgAECgcJBgAAAA==.',
Cn='Cn:BAABLgAECn8nAAIMAAkJlyCJAgAIAwAMAAkJlyCJAgAIAwAAAA==.',
Co='Cocoabutter:BAAALgAECgYJEgAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAUAIsbAA==.Codeman:BAABLgAECn8hAAISAAgJSh7VAwAPAgASAAgJSh7VAwAPAgAAAA==.Cody:BAAALgADCgcJBwABLgAECggJIQASAEoeAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJBgAAAA==.Commiebear:BAACLgAFFH8KAAIZAAQJkBVZCwDxAAAZAAQJkBVZCwDxAAAuAAQKfz8AAxkACQn0Ir4AAHgDABkACQn0Ir4AAHgDABoAAgnpDIZsAF4AAAAA.Contemplate:BAAALgAECgIJBQAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECggJGgABLgAECgcJDgABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.',
Ct='Ctk:BAAALgADCgQJAwAAAA==.',
Cu='Culluh:BAAALgADCgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAAALgAECgYJEgAAAA==.',
Cz='Czin:BAAALgAECgYJEgAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgEJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgADCgYJBQAAAA==.Deathverses:BAACLgAFFH8WAAIbAAUJsCZIAQDTAQAbAAUJsCZIAQDTAQAuAAQKfy4AAhsACQniJigCAJQDABsACQniJigCAJQDAAAA.Deerslayer:BAAALgAECgMJAwAAAA==.Deezknights:BAAALgAECgQJBQAAAA==.Delter:BAABLgAECn8UAAIbAAgJuxzXHwAjAgAbAAgJuxzXHwAjAgABLgAECggJFAAbALscAA==.Deltritus:BAACLgAFFH8LAAIUAAQJuBd6FABvAQAUAAQJuBd6FABvAQAuAAQKfxoAAhQACQnYHvQFANkCABQACQnYHvQFANkCAAEuAAQKCAkUABsAuxwA.Demoan:BAABLgAECn8lAAIcAAkJwCE1AAAiAwAcAAkJwCE1AAAiAwAAAA==.Demonbiscuit:BAAALgAECgYJCgAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAAALgAECgYJDAAAAA==.Dikslapp:BAABLgAECn8VAAIdAAgJVB3CAwBVAgAdAAgJVB3CAwBVAgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Ditto:BAACLgAFFH8FAAISAAMJ5AssEwBuAAASAAMJ5AssEwBuAAAuAAQKfygABBIABwmGHTcHAK0BABIABwmGHTcHAK0BAAoAAwlCDtsPAJ4AAAgAAQmLCqi6ADQAAAAA.',
Dl='Dlitinaro:BAABLgAECn8iAAMIAAgJsR6aFAAVAgAIAAgJsR6aFAAVAgASAAMJwgT7PgBUAAAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMLAAMJoBd0DQAHAQALAAMJoBd0DQAHAQAJAAEJHgmeLABHAAAuAAQKfxkAAwsACAlvJLoDACEDAAsACAlvJLoDACEDAAkAAwlZGidOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Donoph:BAABLgAECn8hAAICAAgJGyLMAgDkAgACAAgJGyLMAgDkAgAAAA==.Doomar:BAABLgAECn8lAAIDAAgJtiGhBwCSAgADAAgJtiGhBwCSAgAAAA==.Doomsamdi:BAAALgAECgEJAQABLgAECgkJJQADALYhAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8ZAAMDAAgJJQh1QQAtAQADAAgJGQZ1QQAtAQAeAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgADCgcJFgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8ZAAMRAAYJSQy/HwAwAQARAAYJyAu/HwAwAQAJAAQJ/wuDMACfAAAAAA==.Drugar:BAAALgAECgUJDQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEh8AFQDCAAAEAAIJEh8AFQDCAAAuAAQKfxYAAgQACAneHbYSALkCAAQACAneHbYSALkCAAEuAAUUBwkcAA8ATSAA.',
Du='Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgMJAwAAAA==.',
Dy='Dynabol:BAABLgAECn8UAAMVAAkJWSV3AABqAwAVAAkJWSV3AABqAwAcAAMJViL3EgAiAQAAAA==.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAECggJIQAIAI4kAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgADCgEJAQAAAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8nAAIEAAkJfhR5CQASAgAEAAkJfhR5CQASAgAAAA==.Faolsabre:BAABLgAECn8VAAIIAAYJaAtNXwDpAAAIAAYJaAtNXwDpAAAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgAYAC0jAA==.',
Fi='Fishinfridge:BAABLgAECn8lAAIfAAgJlhCsBQC4AQAfAAgJlhCsBQC4AQAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8aAAIWAAgJsBXSGgCpAQAWAAgJsBXSGgCpAQAAAA==.',
Fo='Folid:BAAALgADCgcJCAAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB50CgDOAgACAAkJbB50CgDOAgAAAA==.Frostedphyre:BAAALgAECgMJAwAAAA==.',
Fu='Furrywhaco:BAAALgAECgIJAgAAAA==.Fuzzyspells:BAAALgAECgIJAgAAAA==.',
Ga='Gaft:BAABLgAECn8XAAMMAAgJNRrzSwD/AQAMAAYJsB7zSwD/AQANAAYJfA/fDwADAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.',
Gh='Ghostbladez:BAABLgAECn8kAAMgAAgJxgWMGAAPAQAgAAgJsgWMGAAPAQAhAAYJsAKREQDuAAAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQUAAgJsiQ0HwD4AgAUAAgJnSQ0HwD4AgAiAAEJnCZGFQBzAAAjAAEJiSQ/DABrAAABLgAECgkJFAAVAFklAA==.',
Gr='Grawler:BAAALgADCgkJJwAAAA==.Greeny:BAAALgAECgQJDAAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgADCgMJAwABLgAECgcJAQABAAAAAA==.',
Gu='Gumgumfury:BAAALgAECgMJBwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJCgAWAFUNAA==.Halzlok:BAAALgAECgUJDAAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAMJBgAFAF4cAA==.',
Hi='Highglide:BAAALgADCgQJBAAAAA==.Hitmonchan:BAAALgAECgMJAgABLgAECggJIgAWAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAECgYJCgABAAAAAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgADCgkJDQAAAA==.',
Im='Imysteriöus:BAABLgAECn8iAAMWAAgJBiVeAQBiAwAWAAgJBiVeAQBiAwAfAAYJCRSHEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAAALgAFFAMJBAAAAA==.Indishaman:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAABLgAECn8mAAIQAAkJVBKUCAD8AQAQAAkJVBKUCAD8AQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAABLgAECn8pAAIRAAkJHCFFAAANAwARAAkJHCFFAAANAwAAAA==.Jakett:BAAALgADCgEJAQAAAA==.Jaythirian:BAABLgAECn8YAAMkAAcJrQ6LEACUAQAkAAcJrQ6LEACUAQAEAAQJ1gQGgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8KAAIWAAQJVQ0KEgAOAQAWAAQJVQ0KEgAOAQAuAAQKfyMAAxYACAk2HNoWAH8CABYACAk2HNoWAH8CABcABQlaEmdQAOYAAAAA.Jessup:BAACLgAFFH8GAAMlAAMJNB4dAwDBAAAlAAIJPR8dAwDBAAAgAAIJMBk0EwCxAAAuAAQKfyYAAyAACQn8IX4EAFADACAACQn8IX4EAFADACUAAgmwGv8IAJsAAAAA.',
Jh='Jhara:BAAALgAECgYJDgAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8hAAQHAAkJCSJSAwCzAgAHAAkJCSJSAwCzAgAQAAQJbBpeNQBAAQAOAAEJfRSvewA6AAAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgUJBQAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgQJBQAAAA==.Kamekazi:BAAALgADCgYJBgAAAA==.Kariva:BAABLgAECn8UAAIOAAkJ/wUtFQBnAQAOAAkJ/wUtFQBnAQAAAA==.Katacemic:BAAALgAECgMJBgAAAA==.Katastrophic:BAAALgADCggJEAAAAA==.Katazul:BAABLgAECn8dAAMDAAgJSwpaOABLAQADAAgJ+AZaOABLAQAeAAYJzgqvJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.',
Ke='Keelanllan:BAAALgAECgYJCgAAAA==.Keilun:BAEALgAECgUJBQAAAA==.Kew:BAAALgAECgMJAwAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECggJGAALAGsOAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJGwAJAC0RAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Ko='Koggmaw:BAAALgAECgQJBQABLgAFFAQJCgAWAFUNAA==.Koral:BAAALgADCgkJEAAAAA==.',
Kr='Kralj:BAAALgADCgUJBQAAAA==.',
Ku='Kungfuhealya:BAABLgAECn8cAAMZAAgJxgW1HgALAQAZAAgJxgW1HgALAQAaAAEJzQEBVgAeAAAAAA==.Kuraj:BAAALgADCgkJFgAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJEwABAAAAAA==.Larrydale:BAABLgAECn8YAAMmAAgJExwWGQByAgAmAAgJExwWGQByAgAYAAEJqQMAMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJEwABAAAAAA==.Lazydaze:BAAALgAECgYJBwAAAA==.Lazyriver:BAABLgAECn8UAAMSAAYJ6QZlGQCxAAASAAYJ6QZlGQCxAAAIAAMJhQJbFgFIAAAAAA==.',
Le='Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgEJAQAAAA==.Leondis:BAABLgAECn8jAAImAAkJhh+4AgDnAgAmAAkJhh+4AgDnAgAAAA==.Lexipriest:BAACLgAFFH8PAAMOAAQJphUrBQBPAQAOAAQJIRUrBQBPAQAHAAMJlAuZEgDjAAAuAAQKfy4AAw4ACQlAHfQLAJICAAcACAkwHYYIALUCAA4ACQmYG/QLAJICAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.',
Lo='Lobais:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Lockmonster:BAAALgAECgEJAQAAAA==.Locksteady:BAAALgADCgUJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAIVAAgJRh0aEwDSAQAVAAgJRh0aEwDSAQAAAA==.Lumosmaxiima:BAAALgAECgcJBAAAAA==.Lunadesangre:BAAALgAECgEJAQAAAA==.Lunarette:BAAALgAECgIJAgAAAA==.',
Ly='Lydax:BAAALgAECgcJEwAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAAALgADCgQJBAAAAA==.Madkingzack:BAAALgAECggJDAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgADCgEJAQAAAA==.Malistavias:BAAALgAECgQJCAAAAA==.Mallikii:BAABLgAECn8XAAMWAAYJkhy9MADoAQAWAAYJkhy9MADoAQAXAAQJrSPyNwBZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8bAAIUAAkJxw2pQwBkAQAUAAkJxw2pQwBkAQAAAA==.Marimagi:BAAALgADCgkJHAAAAA==.Marnolkas:BAAALgADCggJCAABLgAECgEJAQABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAAALgAECgcJEAAAAA==.Mattdemon:BAAALgAECgcJAQAAAA==.Maudib:BAABLgAECn8VAAInAAgJSBXpCQAwAQAnAAgJSBXpCQAwAQAAAA==.Mawile:BAAALgAECgQJBAAAAA==.',
Me='Meautiful:BAAALgADCgQJBAAAAA==.Medusa:BAAALgAECgMJAwAAAA==.Meesha:BAAALgAECgIJAgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAAALgAECgEJAgAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQeAAgJBA+AHABqAQAeAAcJYw6AHABqAQADAAUJ/wraxQDNAAAoAAEJ2hVnLgBBAAAAAA==.Mendzul:BAAALgAECgEJAQABLgAECggJFgAeAAQPAA==.Merkxi:BAABLgAECn8cAAIYAAgJwR4+AwBqAgAYAAgJwR4+AwBqAgAAAA==.Messe:BAABLgAECn8gAAIlAAgJ0RuHAQAOAgAlAAgJ0RuHAQAOAgAAAA==.Methious:BAAALgAECggJEwAAAA==.',
Mi='Minigoober:BAAALgAECgMJAwAAAA==.',
Mo='Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8KAAIGAAQJvQXKFAD0AAAGAAQJvQXKFAD0AAAAAA==.Monktero:BAAALgAECgEJAQAAAA==.Montu:BAAALgAECgQJBwAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonsguard:BAAALgADCgcJCgABLgADCggJIQABAAAAAA==.Moovit:BAAALgAECgIJAgAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.',
Na='Nagumo:BAABLgAECn8ZAAMDAAgJHQMPVQDyAAADAAgJuwIPVQDyAAAeAAYJYAPzOQDMAAAAAA==.Nala:BAAALgAECgUJCAABLgAFFAQJCgAWAFUNAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAABLgAECn8qAAMJAAgJGRj5EgBtAQAJAAcJEhf5EgBtAQALAAcJYhKFCwBVAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8FAAIVAAMJEh/VFQAgAQAVAAMJEh/VFQAgAQAuAAQKfyYAAhUACQmiJfMAANgDABUACQmiJfMAANgDAAAA.Nikhammer:BAAALgADCgIJAgAAAA==.Nitza:BAAALgADCgkJCQAAAA==.Nivan:BAAALgADCgUJAQAAAA==.Niço:BAAALgAFFAEJAQAAAA==.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIWAAkJJRs5HgBNAgAWAAkJJRs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAECgcJDgAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
['Nï']='Nï:BAAALgADCgUJBQAAAA==.',
Oa='Oakmoss:BAAALgADCgcJBwAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECgcJCAAAAA==.',
Om='Ombravuota:BAAALgAECgYJDwAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMeAAkJwSMoCwANAgAeAAUJrCMoCwANAgADAAUJhCMIRQD8AQAAAA==.Orcleave:BAAALgAECgcJEgAAAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8aAAIUAAgJlhjeJADUAQAUAAgJlhjeJADUAQAAAA==.Perturabo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenyx:BAAALgAECgYJEAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMmAAcJDh0YGwC9AQAmAAcJDh0YGwC9AQAbAAMJdQtrawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJGwAUAMcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgADCgYJCgAAAA==.',
Qu='Quorra:BAAALgADCgcJCwAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8nAAIEAAkJkxxNAgDCAgAEAAkJkxxNAgDCAgAAAA==.Rakagar:BAABLgAECn8hAAIMAAgJZB3+FAATAgAMAAgJZB3+FAATAgAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8OAAIZAAQJZxv+BwBmAQAZAAQJZxv+BwBmAQAuAAQKfysAAhkACQkaHVkOAHECABkACQkaHVkOAHECAAAA.Reyz:BAABLgAECn8YAAIZAAgJGxULFQBoAQAZAAgJGxULFQBoAQAAAA==.Rezyrial:BAAALgAECgEJAQAAAA==.',
Rh='Rhaegos:BAAALgAECgEJAQAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAAALgAECgYJEQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
['Rè']='Rèd:BAAALgAECgEJAQABLgAECggJFAAmALshAA==.',
['Rë']='Rëz:BAAALgADCgYJBgAAAA==.',
Sa='Salla:BAAALgAECgMJAwAAAA==.Saltyy:BAAALgAECgIJAgAAAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8fAAMdAAgJcCAxCgC/AgAdAAgJcCAxCgC/AgAVAAYJLBcwHwB4AQABLgAECggJIgAIALEeAA==.Scripts:BAAALgAECgUJDQAAAA==.',
Sh='Shale:BAABLgAECn8pAAMLAAkJYBTsEwAGAgALAAkJYBTsEwAGAgAJAAUJSQmgRQDGAAAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAAALgAFFAEJAQAAAA==.Sharaiya:BAABLgAECn8bAAIWAAYJTwXQgQDVAAAWAAYJTwXQgQDVAAAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAAALgAECgQJCgAAAA==.Sioux:BAAALgADCgcJEgAAAA==.',
Sk='Skippybmm:BAAALgAECgEJAwABLgAECgYJDQABAAAAAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgEJAQABLgAECggJIAAlANEbAA==.',
Sm='Smexyshâmmy:BAAALgAECgQJBQAAAA==.',
So='Solaire:BAACLgAFFH8FAAINAAMJmhRUAwDTAAANAAMJmhRUAwDTAAAuAAQKfywAAg0ACQn8ILkBADMDAA0ACQn8ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAAALgAECgQJBAABLgAECggJFwACACkgAA==.Soulful:BAAALgAECgYJBgAAAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAAALgAECgYJDQAAAA==.Spot:BAAALgAECgIJAQABLgAECgkJGwAUAMcNAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAgAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.',
Sv='Svetha:BAABLgAECn8ZAAMYAAgJXBQpCADjAQAYAAgJqhEpCADjAQAbAAcJExUxCQBCAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgADCgYJBgAAAA==.Syreous:BAAALgADCgMJAwABLgAECgIJAwABAAAAAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAAALgAECgYJDQAAAA==.Tankinit:BAAALgAECgMJBwAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgADCgcJFAAAAA==.Tatterbone:BAAALgADCgkJDAAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAINAAMJswgGBACcAAANAAMJswgGBACcAAAuAAQKfyUAAg0ACAkJHX4GAIACAA0ACAkJHX4GAIACAAAA.Tenzink:BAABLgAECn8mAAIZAAkJGxwtAwDKAgAZAAkJGxwtAwDKAgAAAA==.',
Th='Thalon:BAAALgAECgMJAwABLgAECggJLQAIAK0iAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgADCgIJAgAAAA==.Thedru:BAABLgAECn8ZAAIWAAYJBw3aNgD7AAAWAAYJBw3aNgD7AAAAAA==.Thrus:BAAALgAECgIJAgABLgAECggJIAAlANEbAA==.Théworld:BAAALgADCggJIQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgEJAQABLgAECggJGgAUAJYYAA==.',
Tl='Tlnks:BAAALgADCgQJBAAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAAALgADCgIJAgAAAA==.',
Tr='Traler:BAAALgADCgkJEQABLgAECggJJQAfAJYQAA==.Tralzitashan:BAABLgAECn8aAAMiAAkJkgl0CABuAQAiAAkJkgl0CABuAQAUAAQJzAMAIgG8AAAAAA==.Trammatize:BAABLgAECn8ZAAIUAAcJZxm4ZQAMAgAUAAcJZxm4ZQAMAgAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgADCgMJAwAAAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Un='Undeadnite:BAAALgAECgUJCQAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAAALgAECgcJCAABLgAECggJHAAQANseAA==.Unglausp:BAABLgAECn8cAAIQAAgJ2x7ODQCmAgAQAAgJ2x7ODQCmAgAAAA==.',
Uz='Uzington:BAACLgAFFH8MAAIFAAQJRw71BgAYAQAFAAQJRw71BgAYAQAuAAQKfyYAAgUACQm0HPAIAI8CAAUACQm0HPAIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgEJAgAAAA==.Valeta:BAAALgAECgEJAQAAAA==.Vali:BAAALgAECgUJCQAAAA==.Valorien:BAABLgAECn8XAAIMAAgJwRe4HADdAQAMAAgJwRe4HADdAQAAAA==.Valzlok:BAAALgADCgkJFAAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgAYAC0jAA==.Velinieron:BAABLgAECn8eAAIYAAkJLSNUAQDMAgAYAAkJLSNUAQDMAgAAAA==.Vellash:BAAALgAECgYJCgAAAA==.Vendétta:BAABLgAECn8cAAImAAgJdw9qQAAUAQAmAAgJdw9qQAAUAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8UAAIUAAYJeQlwZQAQAQAUAAYJeQlwZQAQAQAAAA==.Vince:BAAALgAECgEJAQAAAA==.Virgïl:BAAALgAECgEJAQAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAAALgAECgUJEAAAAA==.',
Vy='Vynlandis:BAABLgAECn8gAAIIAAgJFRYMGAD7AQAIAAgJFRYMGAD7AQAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJCgAWAFUNAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAAALgAECgEJAQAAAA==.Werebray:BAAALgAECgYJCgAAAA==.',
Wh='Whaco:BAABLgAECn8fAAINAAgJiRviAwAbAgANAAgJiRviAwAbAgAAAA==.Whatisaggro:BAAALgAECgYJEgAAAA==.Whispertree:BAABLgAECn8ZAAIXAAgJdSDPGABBAgAXAAgJdSDPGABBAgAAAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECgYJGQARAEkMAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAABLgAECn8hAAIIAAgJjiRiDQAvAwAIAAgJjiRiDQAvAwAAAA==.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8nAAQSAAcJNxnnFADDAQASAAYJmh3nFADDAQAIAAcJrgbEYwDeAAAKAAIJcxhJEgBsAAAAAA==.Wixypoo:BAABLgAECn8iAAMGAAgJlhe5DgCkAQAGAAgJlhe5DgCkAQAZAAEJ5wEPTwAfAAAAAA==.',
Wo='Wockyslush:BAABLgAECn8cAAIgAAgJ+CLmCAADAwAgAAgJ+CLmCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.',
Wr='Wrylah:BAABLgAECn8dAAMJAAgJXBhaCQD2AQAJAAgJXBhaCQD2AQARAAYJwAMpKADfAAAAAA==.',
Wu='Wuxian:BAAALgAECgYJEAAAAA==.',
Wy='Wyyn:BAABLgAECn8gAAIUAAcJ2AunSABUAQAUAAcJ2AunSABUAQAAAA==.',
Xa='Xanboi:BAABLgAECn8hAAMYAAgJxiH0AgBzAgAYAAgJxiH0AgBzAgAmAAIJ6iK7iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAABLgAECn8lAAIEAAgJsCAZDQDtAgAEAAgJsCAZDQDtAgAAAA==.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Youknowwho:BAAALgADCgkJAwAAAA==.',
Ys='Ysar:BAAALgAECgYJCQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECgcJCAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMRAAcJ6RqDDgDyAQARAAYJkB+DDgDyAQAJAAYJGxdDIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.',
Ze='Zeebu:BAAALgAECgYJDwAAAA==.Zenboi:BAABLgAECn8cAAIVAAgJ3hUXQwDnAQAVAAgJ3hUXQwDnAQAAAA==.Zephryyn:BAAALgADCgkJEAAAAA==.',
Zh='Zhilan:BAAALgAECgQJBAAAAA==.',
Zi='Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAMJBgAlADQeAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgEJAQAAAA==.Zuzuk:BAAALgAECggJDwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.',
['Zú']='Zúz:BAAALgAECgYJBwAAAA==.',
['Áß']='Áßomination:BAAALgAECgEJAQAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.',
['Ðe']='Ðemaea:BAABLgAECn8dAAIpAAgJXQuBMAD9AAApAAgJXQuBMAD9AAAAAA==.',
['Ðÿ']='Ðÿlån:BAAALgAECgEJAQAAAA==.',
['Öd']='Ödorodun:BAAALgADCggJDAAAAA==.',
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

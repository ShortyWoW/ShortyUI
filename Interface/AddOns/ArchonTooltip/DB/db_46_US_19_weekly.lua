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

local lookup = {'Unknown-Unknown','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Hunter-BeastMastery','Mage-Frost','Shaman-Restoration','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Druid-Guardian','Rogue-Subtlety','Warlock-Demonology','Hunter-Survival','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance','Shaman-Elemental','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Mage-Fire','Druid-Feral','Rogue-Outlaw','Priest-Holy','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Priest-Discipline','Rogue-Assassination','Monk-Mistweaver','Evoker-Devastation','Warrior-Fury','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adaine:BAAALgADCgUJCQAAAA==.Adillyssa:BAAALgADCgcJBwABLgAECgUJEgABAAAAAA==.Adriana:BAABLgAECn8XAAICAAcJpB5/CQB6AgACAAcJpB5/CQB6AgAAAA==.Adru:BAAALgAECgYJEQAAAA==.',
Ae='Aeglos:BAACLgAFFH8JAAMDAAQJNx2RAQBaAQADAAQJ2xWRAQBaAQAEAAMJbBh/QgAKAQAuAAQKfx4AAwQACQkGIb4WAPMCAAQACAkKIr4WAPMCAAMABQmqHlMJAEYBAAAA.Aelera:BAAALgADCgkJDgAAAA==.Aentharion:BAABLgAECn8eAAIFAAcJrBqADwDaAQAFAAcJrBqADwDaAQAAAA==.Aer:BAAALgADCgUJBQAAAA==.Aertimis:BAAALgADCgMJAwAAAA==.Aevielyn:BAAALgAECgEJAQAAAA==.',
Ag='Aguth:BAAALgADCgMJAwAAAA==.',
Ai='Aidewey:BAAALgADCgYJBgAAAA==.Aileen:BAABLgAECn8VAAIGAAkJrhITVwAJAQAGAAkJrhITVwAJAQAAAA==.Airiya:BAAALgAECgUJBAAAAA==.',
Aj='Ajami:BAAALgADCgIJAgAAAA==.',
Al='Alacite:BAAALgAECgcJEwAAAA==.Aleyah:BAAALgAECgcJAgAAAA==.Alisonia:BAAALgADCgcJFAAAAA==.Alitikar:BAAALgADCgIJAgAAAA==.Allamura:BAAALgAECgUJBQAAAA==.Alleximage:BAACLgAFFH8FAAIHAAMJbQPGUgDVAAAHAAMJbQPGUgDVAAAuAAQKfxkAAgcACAnbFytTAD4CAAcACAnbFytTAD4CAAAA.Alorren:BAABLgAECn8cAAIIAAgJWA9OJACWAQAIAAgJWA9OJACWAQAAAA==.Althea:BAAALgADCgQJBAAAAA==.Alynia:BAAALgAECggJDwAAAA==.Alyssa:BAAALgAECgUJBQAAAA==.',
Am='Amodegas:BAABLgAECn8XAAICAAgJ5yBgCADoAgACAAgJ5yBgCADoAgAAAA==.Amonk:BAAALgAECgQJBwAAAA==.Amonra:BAAALgAECgMJAwAAAA==.Amordil:BAAALgADCgQJBAAAAA==.Amynrar:BAAALgAECgQJBgAAAA==.',
An='Ancalagrond:BAAALgAECgQJBgAAAA==.Andrâste:BAAALgAECgQJBAAAAA==.Anecia:BAAALgADCgkJDwABLgAECgUJEgABAAAAAA==.Angyaras:BAABLgAFFH8GAAIJAAYJ5RYABAB7AQAJAAYJ5RYABAB7AQAAAA==.Animos:BAAALgADCgYJBgAAAA==.Annehathaway:BAAALgAECgIJAwAAAA==.Anothercaion:BAAALgAECgUJDQAAAA==.Anthor:BAAALgADCgMJAwAAAA==.Antiihr:BAACLgAFFH8cAAIKAAcJmiFWAAB7AgAKAAcJmiFWAAB7AgAuAAQKfzoAAgoACQn4JN8AAL4DAAoACQn4JN8AAL4DAAAA.',
Ap='Apix:BAAALgAECgEJAQABLgAECggJJwALANwcAA==.',
Ar='Arcaisme:BAAALgAECgYJEwAAAA==.Arcticsnow:BAAALgAECgUJEgAAAA==.Arkose:BAAALgAECgYJDAAAAA==.Arkädia:BAAALgAECgEJAQAAAA==.Armistice:BAABLgAECn8XAAIMAAgJPiE7EwD5AgAMAAgJPiE7EwD5AgAAAA==.Artanos:BAAALgAECgYJDQAAAA==.Artiazana:BAAALgADCgUJBgAAAA==.',
As='Ashlyngrace:BAAALgAECgIJAgABLgAECgkJIAAIANMeAA==.Ashlynne:BAABLgAECn8gAAIIAAkJ0x7XCQDbAgAIAAkJ0x7XCQDbAgAAAA==.Ashlynnemia:BAAALgAECgYJBwAAAA==.Ashvara:BAAALgADCggJEwAAAA==.Aslynna:BAAALgADCgcJCAAAAA==.Asora:BAABLgAECn8VAAIHAAYJ+QNGngDWAAAHAAYJ+QNGngDWAAAAAA==.Aspect:BAAALgAECgcJCQAAAA==.Aspensong:BAABLgAECn8eAAINAAcJwh/GBAAiAgANAAcJwh/GBAAiAgAAAA==.Astracious:BAAALgAECgYJBgAAAA==.',
At='Atax:BAABLgAECn8eAAIOAAcJxhiEDADYAQAOAAcJxhiEDADYAQAAAA==.Athená:BAAALgAECgYJDgABLgAECggJDAABAAAAAA==.Atheum:BAAALgADCgQJBAAAAA==.',
Au='Auralyn:BAAALgADCgcJDgAAAA==.Aurelitrasza:BAAALgADCgkJDgAAAA==.',
Av='Avicena:BAAALgAECgUJCAAAAA==.Avicii:BAAALgADCgUJCgAAAA==.Avrice:BAAALgAECgEJAQAAAA==.',
Ax='Axfrosty:BAAALgADCgQJBAAAAA==.Axiona:BAAALgAECgEJAQAAAA==.',
Ay='Ayakia:BAAALgAECgcJDAAAAA==.Ayaku:BAAALgAECgIJAgAAAA==.',
Az='Azuraa:BAAALgADCgUJCAAAAA==.',
Ba='Badshot:BAAALgAECgYJDwAAAA==.Baiogg:BAABLgAECn8YAAIPAAcJLwWkZgAAAQAPAAcJLwWkZgAAAQAAAA==.Baldord:BAAALgADCgMJBAAAAA==.Balthromaww:BAAALgAECgYJBwAAAA==.Balung:BAAALgAECgQJBgAAAA==.Bambu:BAAALgAECgYJDQAAAA==.Bamevoker:BAAALgAECgMJAwABLgAECgYJDQABAAAAAA==.Bariggs:BAABLgAECn8YAAIQAAcJryTEBADGAgAQAAcJryTEBADGAgAAAA==.Barilia:BAAALgAECgEJAQAAAA==.',
Be='Bearlyalive:BAAALgADCgMJAwAAAA==.Beladra:BAAALgADCgUJCwAAAA==.Belekor:BAAALgAECgYJCQAAAA==.Beltayn:BAAALgAECgYJCwAAAA==.Ben:BAABLgAECn8gAAIRAAkJchrbDADqAQARAAkJchrbDADqAQAAAA==.Beriadan:BAAALgAECggJCwAAAA==.Bevee:BAAALgAECgQJCQAAAA==.Bewitchin:BAAALgAECgEJAQAAAA==.',
Bi='Bigponch:BAAALgADCgEJAQAAAA==.Birst:BAAALgADCggJBAAAAA==.Bisque:BAAALgAECgEJAQAAAA==.',
Bl='Bladesrus:BAAALgAECgMJBQAAAA==.Blaithe:BAAALgAECgEJAQAAAA==.Bleddwen:BAAALgAECgYJEwAAAQ==.Bliggix:BAAALgADCgQJBAAAAA==.Blrsama:BAAALgADCgUJBgAAAA==.',
Bo='Bodok:BAABLgAECn8fAAMSAAkJrhN/GAD5AQASAAkJrhN/GAD5AQATAAEJyAV8IQAlAAAAAA==.Bohrnir:BAABLgAECn8sAAMIAAkJBx6EDgBQAgAIAAkJBx6EDgBQAgAUAAMJ/QjRRwCIAAAAAA==.Boomonster:BAAALgADCgcJBwAAAA==.Boüh:BAAALgAECgYJEQAAAA==.',
Br='Brackiss:BAAALgAECgEJAQAAAA==.Brokiinn:BAACLgAFFH8FAAIGAAIJ9BFjFQCvAAAGAAIJ9BFjFQCvAAAuAAQKfxoAAgYACAl1GfAbAF8CAAYACAl1GfAbAF8CAAAA.Brutalix:BAAALgADCgYJDQAAAA==.Brynda:BAAALgADCgQJBAAAAA==.',
Bu='Budikah:BAAALgAECgQJAgAAAA==.Burd:BAAALgADCgcJBwAAAA==.Burmeister:BAABLgAECn8cAAMVAAcJnwqOIgAkAQAVAAcJnwqOIgAkAQAWAAYJqAfxTgDYAAAAAA==.Burnadine:BAAALgAECgYJEgAAAA==.Burnswhnpee:BAABLgAECn8WAAQXAAgJGhUdHABtAQAXAAYJ5xIdHABtAQAPAAYJDhCOegDSAAAYAAIJVAjEIgBnAAAAAA==.Burtelby:BAAALgADCgYJBgAAAA==.',
['Bù']='Bùrd:BAAALgADCgkJCQAAAA==.',
['Bû']='Bûrd:BAABLgAECn8sAAQZAAkJqxHEAQADAgAZAAkJ7g/EAQADAgAaAAYJ8A55BAAWAQAHAAYJpwoBmADjAAAAAA==.',
Ca='Cadsuàne:BAAALgADCgUJCAAAAA==.Caliie:BAABLgAECn8eAAMIAAcJFgfDPwAEAQAIAAcJFgfDPwAEAQAUAAUJaAPJRQCRAAAAAA==.Callira:BAAALgAECgUJEAAAAA==.Cambiare:BAAALgADCgYJCgAAAA==.Canaandra:BAAALgADCgkJBwAAAA==.Captclamslam:BAABLgAECn8hAAMNAAgJ/A20DgAdAQANAAgJ+g20DgAdAQAbAAcJ6QsNEAAYAQAAAA==.Carolline:BAAALgADCgkJCgAAAA==.Catherinecay:BAAALgADCgcJBwAAAA==.',
Ce='Cereania:BAAALgAECgYJEgAAAA==.Cerrabell:BAAALgADCgcJBwAAAA==.',
Ch='Charzzard:BAAALgADCgEJAQAAAA==.Checksmix:BAAALgAECgEJAQAAAA==.Chintakari:BAABLgAECn8YAAMGAAcJ5ROSOABqAQAGAAcJ5ROSOABqAQAQAAEJLwe2MAAxAAAAAA==.Chlorofill:BAAALgAECgcJCQAAAA==.Chronologic:BAAALgAECgYJEAAAAA==.',
Co='Cocidiae:BAAALgAECgEJBAAAAA==.Confusious:BAACLgAFFH8KAAIIAAQJshjeFAAgAQAIAAQJshjeFAAgAQAuAAQKfysAAwgACQmSFWAdAMYBAAgACQmSFWAdAMYBABQAAQkqCR1sACoAAAAA.Coree:BAABLgAECn8zAAIcAAYJLQ+8BwAWAQAcAAYJLQ+8BwAWAQAAAA==.Cornflower:BAABLgAECn8YAAIdAAgJ+w5AHgBXAQAdAAgJ+w5AHgBXAQAAAA==.Corvaan:BAABLgAECn8kAAISAAkJ0RFbHgDSAQASAAkJ0RFbHgDSAQAAAA==.',
Cr='Creg:BAABLgAECn8eAAISAAcJiCBjEwAiAgASAAcJiCBjEwAiAgAAAA==.Crotalhusk:BAAALgADCgcJBwAAAA==.Crowbarr:BAAALgADCgUJBQAAAA==.Cryostatic:BAAALgAECgUJBgABLgAECgYJHAAeAJoJAA==.',
Cu='Cultel:BAABLgAECn8yAAITAAgJ3h7zAgA4AgATAAgJ3h7zAgA4AgAAAA==.',
Cy='Cyendia:BAABLgAECn8bAAIIAAcJXhx4EAA5AgAIAAcJXhx4EAA5AgAAAA==.Cyer:BAAALgAECgQJBgAAAA==.',
Da='Daddyraz:BAABLgAECn8XAAISAAgJnRWcZAB0AQASAAgJnRWcZAB0AQAAAA==.Dakan:BAAALgADCgkJHwAAAA==.Daphcelyn:BAAALgAECgMJBgAAAA==.Dariusz:BAAALgAECgcJCwAAAA==.Darkalen:BAABLgAECn8qAAIfAAgJgBlKCAADAgAfAAgJgBlKCAADAgAAAA==.Darklodus:BAAALgADCgcJEwAAAA==.Darriuss:BAABLgAECn8YAAIMAAUJuQJluQCCAAAMAAUJuQJluQCCAAAAAA==.Darthvaderp:BAAALgAFFAEJAQAAAA==.Dathea:BAAALgADCgYJBgAAAA==.Davìd:BAAALgAECgEJAQAAAA==.Dawnmist:BAAALgAECgQJCAAAAA==.Daxetandh:BAAALgAECgIJBgAAAA==.Daxetanir:BAAALgADCgMJAwABLgAFFAIJBQAUABEaAA==.Daxetans:BAACLgAFFH8FAAIUAAIJERqHFACpAAAUAAIJERqHFACpAAAuAAQKfzYAAxQACQkTIagBACQDABQACQkTIagBACQDAAgABwk+DNtGAGYBAAAA.',
De='Deadmoose:BAABLgAECn8wAAIEAAkJcxWNHAAdAgAEAAkJcxWNHAAdAgAAAA==.Deathb:BAAALgADCgkJIAAAAA==.Deathjingle:BAACLgAFFH8GAAIEAAIJ6hycaACpAAAEAAIJ6hycaACpAAAuAAQKfysAAx8ACQkbHdIGACkCAB8ABwmWINIGACkCAAQACQmYF3xHAB4CAAAA.Deecayed:BAABLgAECn8cAAIMAAgJoRRmLQDIAQAMAAgJoRRmLQDIAQAAAA==.Deecoy:BAAALgAECgYJDgAAAA==.Deestroyer:BAAALgAECgUJDwAAAA==.Deetermined:BAABLgAECn8mAAIIAAkJ3B5xAwAWAwAIAAkJ3B5xAwAWAwAAAA==.Delion:BAAALgADCgIJAgAAAA==.Demhuloo:BAAALgAECgQJBwAAAA==.Demonburp:BAABLgAECn8qAAISAAgJ8CGiBwCsAgASAAgJ8CGiBwCsAgAAAA==.Denchy:BAABLgAECn8dAAIgAAcJ8QUzGwDcAAAgAAcJ8QUzGwDcAAAAAA==.Dendris:BAAALgAECgQJBAAAAA==.Desetraz:BAAALgAECgYJCwAAAQ==.Deval:BAAALgADCgQJBAAAAA==.Deyndine:BAAALgAECgUJEgAAAA==.',
Dh='Dhurza:BAAALgAFFAIJAgAAAA==.',
Di='Disdain:BAAALgAECgYJDAAAAA==.Div:BAABLgAECn84AAIeAAkJkh4gAQDhAgAeAAkJkh4gAQDhAgAAAA==.',
Do='Dogdays:BAAALgADCgkJCQAAAA==.Doki:BAAALgAECgIJAgAAAA==.Dorden:BAABLgAECn83AAMFAAkJqxDhEADKAQAFAAkJqxDhEADKAQAhAAcJJxCwEwAEAQAAAA==.Dorilax:BAABLgAECn8UAAMdAAgJqxFAIQDZAQAdAAgJqxFAIQDZAQAiAAEJvwFeXgAlAAAAAA==.Dottarus:BAAALgAECgQJBQAAAA==.',
Dr='Draevus:BAAALgAECgQJBQAAAA==.Dragooniar:BAAALgAECgYJEgAAAA==.Draizen:BAAALgAECgkJDQAAAA==.Dralara:BAAALgADCggJDgAAAA==.Dreàd:BAABLgAECn8ZAAIUAAYJkBT9JAAvAQAUAAYJkBT9JAAvAQAAAA==.Driadora:BAAALgAECgQJBQAAAA==.Drinna:BAAALgAECgMJBgAAAA==.Drizzette:BAAALgADCgEJAQAAAA==.Droataxh:BAAALgADCgMJAwABLgAECgkJOAAHAOAgAA==.Droataxm:BAABLgAECn84AAIHAAkJ4CAXBgAPAwAHAAkJ4CAXBgAPAwAAAA==.Druntress:BAABLgAECn8VAAILAAgJ0xK0LADJAQALAAgJ0xK0LADJAQAAAA==.',
Du='Duarraag:BAAALgADCgIJAQAAAA==.',
['Dà']='Dàvid:BAAALgAFFAEJAgAAAA==.Dàvìd:BAAALgAECgQJBAAAAA==.',
['Dè']='Dèmonic:BAAALgADCgQJBgAAAA==.',
['Dë']='Dëërez:BAABLgAECn8UAAIWAAYJpAdZUQDQAAAWAAYJpAdZUQDQAAAAAA==.',
Eb='Eburi:BAABLgAECn8WAAIEAAgJZBVgKwDOAQAEAAgJZBVgKwDOAQAAAA==.',
Ed='Edgybear:BAAALgADCggJCAAAAA==.',
Ei='Eililis:BAAALgAECgMJBgAAAA==.',
El='Elani:BAAALgAECgMJAwABLgAECgYJDwABAAAAAA==.Elaynaa:BAAALgAECgYJDwAAAA==.Eledweth:BAAALgADCgEJAgAAAA==.Elemengoat:BAAALgADCgQJBAAAAA==.Elfstar:BAAALgAECgYJDQAAAA==.Elihe:BAAALgADCgEJAQAAAA==.Elishaunt:BAAALgAECgUJEQAAAA==.Elivan:BAAALgAECgYJBgAAAA==.Elleth:BAAALgAECgYJEAAAAA==.Elliana:BAAALgADCgYJBgAAAA==.Eloper:BAAALgAFFAEJBAABLgAECgEJAQABAAAAAA==.Elvoidra:BAAALgAECgIJAgAAAA==.Elykk:BAAALgAECggJDAAAAA==.',
Em='Emberana:BAAALgADCgUJBQAAAA==.',
En='Endb:BAAALgADCggJGwAAAA==.Enjin:BAAALgADCgUJBQAAAA==.Envi:BAAALgADCgUJBQAAAA==.',
Er='Erisaria:BAAALgADCgQJBQAAAA==.Erixi:BAAALgAECgYJEwAAAA==.Erodoreal:BAAALgAECgcJDwAAAA==.',
Et='Etheria:BAAALgAECgYJCAAAAA==.',
Ev='Evocore:BAAALgAECgYJEAAAAA==.',
Ex='Excelimagust:BAAALgAECgMJBQAAAA==.',
Fa='Faelieline:BAAALgADCgYJBgAAAA==.Faithful:BAAALgAECgcJBwABLgAECggJIwAeAPYaAA==.Falanor:BAAALgAECgQJBAABLgAECgYJCQABAAAAAA==.Falcdhruid:BAAALgAECgQJBgAAAA==.Fangrage:BAAALgAECgMJBAAAAA==.Farundi:BAAALgAECgMJAwAAAA==.Fayemoon:BAAALgAECgUJBwAAAA==.',
Fe='Felara:BAAALgAECgYJBgABLgAECggJFwAJANkaAA==.Felbutton:BAAALgAECgUJCQAAAA==.Feldemon:BAAALgAECgQJBgAAAA==.Fellost:BAAALgAECgQJBQABLgAECggJFwAJANkaAA==.Felsen:BAAALgADCgEJAQABLgAECggJFwAJANkaAA==.Felwit:BAABLgAECn8XAAIJAAgJ2RoQDwAYAgAJAAgJ2RoQDwAYAgAAAA==.Fennec:BAABLgAECn8WAAIjAAcJTgx9CABOAQAjAAcJTgx9CABOAQAAAA==.',
Fh='Fhyn:BAAALgAECgQJBgABLgAECgQJCAABAAAAAA==.',
Fi='Fitzooth:BAAALgAFFAEJAQAAAA==.',
Fl='Flamos:BAAALgADCgYJBgAAAA==.Florabelle:BAAALgAECgMJAwABLgAECggJGAAdAPsOAA==.Florid:BAAALgAECgYJCgAAAA==.',
Fo='Foshomomo:BAABLgAECn8dAAIkAAcJQhbEEQDYAQAkAAcJQhbEEQDYAQAAAA==.Fozzle:BAABLgAECn8jAAIHAAkJBw+pKgD3AQAHAAkJBw+pKgD3AQAAAA==.',
Fr='Fredoku:BAAALgAECgMJBAAAAA==.Fredragon:BAAALgAECgEJAQAAAA==.Frenndi:BAAALgAECgQJCQAAAA==.Frostbites:BAAALgAECgEJAQAAAA==.',
Fy='Fynedge:BAABLgAECn8bAAIMAAcJcQeHbAAUAQAMAAcJcQeHbAAUAQAAAA==.Fynnyntyss:BAABLgAECn8sAAIlAAkJ8RAFAwD9AQAlAAkJ8RAFAwD9AQAAAA==.Fyrè:BAABLgAECn8rAAIGAAkJLSG5AwD+AgAGAAkJLSG5AwD+AgAAAA==.',
['Fâ']='Fârrah:BAAALgAECgIJAgAAAA==.',
Ga='Gabriels:BAAALgADCgcJFQAAAA==.Gabrielspet:BAAALgADCgIJAgAAAA==.Gainsborough:BAAALgADCgcJEAAAAA==.Galactis:BAAALgAECgYJBwAAAA==.Gavinrad:BAAALgAECgQJBAAAAA==.',
Ge='Gelirri:BAAALgADCgIJAgAAAA==.Getschwiftyy:BAAALgADCgIJAQAAAA==.',
Gi='Githnor:BAABLgAECn8sAAIMAAkJXgmgOACdAQAMAAkJXgmgOACdAQAAAA==.',
Gl='Glendara:BAAALgADCgcJBwAAAA==.',
Go='Gorellan:BAAALgADCgUJBQAAAA==.Goretall:BAAALgADCgYJCAAAAA==.Gothen:BAAALgADCgEJAQAAAA==.',
Gr='Graelyn:BAABLgAECn8XAAMMAAcJLAvujABhAQAMAAcJVgrujABhAQAeAAIJQQmOQQA3AAAAAA==.Grimseth:BAAALgADCgUJBQAAAA==.Grimwharf:BAAALgAECgUJCAAAAA==.Grum:BAAALgADCgUJBQAAAA==.Grunaelyn:BAABLgAECn8WAAIUAAgJ4g8CGwB2AQAUAAgJ4g8CGwB2AQAAAA==.',
Gu='Guerrier:BAAALgAECgYJDwAAAA==.Gustgut:BAAALgAECgMJBAAAAA==.',
Ha='Haelynn:BAAALgADCgcJDAAAAA==.Hahkolhanna:BAAALgADCggJEwAAAA==.Handrido:BAAALgAECgYJCgAAAA==.Hantaro:BAAALgADCgMJAwAAAA==.Hasuna:BAAALgAECgYJDQAAAA==.',
He='Heikuro:BAABLgAECn8gAAMTAAYJ1yDIBADWAQATAAYJoSDIBADWAQASAAYJwhnaZgBtAQAAAA==.Heiler:BAAALgAECgQJBAAAAA==.Heris:BAAALgADCgcJDAAAAA==.',
Hi='Hibby:BAAALgAECgMJBAAAAA==.',
Ho='Holymilk:BAAALgAECgIJAgAAAA==.Holysalt:BAAALgADCgUJCwAAAA==.Honadain:BAAALgAECgUJDQAAAA==.Honordin:BAABLgAECn8tAAIMAAgJNSG2DwB+AgAMAAgJNSG2DwB+AgAAAA==.Hordestalker:BAAALgAECgQJBwAAAA==.Houllian:BAAALgAECgYJDAAAAA==.',
Hu='Hucha:BAAALgADCggJDAAAAA==.Hundren:BAAALgAECgEJAQAAAA==.',
Hw='Hweilan:BAAALgADCgUJBQAAAA==.',
['Hö']='Hölyföx:BAAALgAECgQJBAAAAA==.',
Ia='Iamearl:BAAALgAECgQJBAAAAA==.Iamirishgirl:BAAALgADCgIJAgAAAA==.',
Ic='Icyhotness:BAAALgADCgYJBgAAAA==.Icê:BAAALgADCgcJEgAAAA==.',
Ik='Iklyn:BAAALgAECgMJAQAAAA==.',
Il='Illanna:BAAALgAECgMJAwAAAA==.',
Im='Imckickinit:BAAALgAECgQJBAAAAA==.Imorith:BAAALgAECgYJDwAAAA==.',
In='Inania:BAAALgAECggJEwAAAA==.Inception:BAAALgAECgIJAwAAAA==.Incidental:BAABLgAECn84AAIKAAkJHiTyAABBAwAKAAkJHiTyAABBAwAAAA==.Inconell:BAABLgAECn8dAAImAAYJsARLQQC6AAAmAAYJsARLQQC6AAAAAA==.Invega:BAAALgADCgkJDQAAAA==.',
Ip='Iport:BAAALgAECgIJAgAAAA==.',
Ir='Iric:BAAALgAECgEJAgAAAA==.Irinal:BAAALgADCgcJBwAAAA==.Ironi:BAABLgAECn8uAAMWAAgJjBdXEwAwAgAWAAgJjBdXEwAwAgAVAAUJ2AMPbABvAAAAAA==.',
Is='Isai:BAAALgAECgEJAQAAAA==.Iskandar:BAABLgAECn8oAAMmAAgJThjXDgACAgAmAAgJThjXDgACAgAgAAEJWQwJPwAxAAAAAA==.',
Iy='Iyashaau:BAAALgAECgEJAgAAAQ==.',
Iz='Izaer:BAABLgAECn8YAAIdAAYJXBI0HwBPAQAdAAYJXBI0HwBPAQAAAA==.Iziel:BAAALgAECgYJEQAAAA==.',
Ja='Jababa:BAAALgADCgMJAwAAAA==.Jabzaklok:BAAALgAECgcJEQAAAA==.Jahirah:BAABLgAECn8cAAIHAAgJ9RSBOQC9AQAHAAgJ9RSBOQC9AQABLgAECggJHAAPAJ4NAA==.Jaleika:BAAALgADCgkJEAAAAA==.Janaian:BAABLgAECn8bAAMVAAgJhBJhIwAeAQAVAAgJhBJhIwAeAQAWAAMJ7g30nACRAAAAAA==.Jarius:BAABLgAECn8XAAICAAcJSAnDKABHAQACAAcJSAnDKABHAQAAAA==.Jashah:BAAALgADCggJCAABLgAECgkJLAAlAPEQAA==.Jazaray:BAAALgADCgkJEAAAAA==.',
Je='Jean:BAABLgAECn8kAAIGAAgJMB1mEgA+AgAGAAgJMB1mEgA+AgAAAA==.Jeez:BAAALgAFFAMJBAAAAA==.Jeri:BAACLgAFFH8UAAMGAAYJmhTzIgAJAQALAAUJ6AjeEgAPAQAGAAMJhx3zIgAJAQAuAAQKfyEAAwYACQnMItw3AM8BAAsABglVHMQnAOwBAAYACAnDH9w3AM8BAAAA.Jeriaze:BAAALgADCgkJEgAAAA==.',
Jo='Jokuo:BAAALgADCgEJAQAAAA==.Jonyy:BAAALgADCgcJCAAAAA==.Joona:BAAALgADCgUJBQAAAA==.Jorianna:BAAALgAECgYJEAAAAA==.Joru:BAACLgAFFH8YAAInAAYJtx1HAAARAgAnAAYJtx1HAAARAgAuAAQKfxcAAicACAnIJJYDAPMCACcACAnIJJYDAPMCAAEuAAUUBwkOAAsAzBkA.',
Ju='Jul:BAAALgAECgEJAQABLgAECgcJCgABAAAAAA==.',
Jy='Jynxmaze:BAAALgADCgQJAwAAAA==.',
['Jí']='Jím:BAAALgADCgQJBAABLgAECggJGQAPAJQkAA==.',
Ka='Kaai:BAAALgAECgYJEwAAAA==.Kabaul:BAABLgAECn8vAAMmAAkJliFJAgCaAwAmAAkJliFJAgCaAwAgAAEJcROTPgA7AAAAAA==.Kabir:BAABLgAECn8XAAIHAAcJbgoaZgBFAQAHAAcJbgoaZgBFAQAAAA==.Kadria:BAAALgAECgYJEwAAAA==.Kady:BAAALgAECgMJAwABLgAECgYJEQABAAAAAA==.Kaelon:BAAALgAECgkJCQAAAA==.Kail:BAAALgAECgUJDwAAAA==.Kailanii:BAABLgAECn8bAAMWAAgJWxOiIADAAQAWAAgJWxOiIADAAQAVAAIJ5QZHdABRAAAAAA==.Kaiscer:BAAALgAECgMJBAAAAA==.Kaitsura:BAAALgADCgUJBQAAAA==.Kaiyne:BAABLgAECn8jAAMPAAkJFhXBKADDAQAPAAkJFhXBKADDAQAXAAEJdQ8IcQA1AAAAAA==.Kajiere:BAAALgADCgIJAgAAAA==.Kalagon:BAAALgADCgYJBgAAAA==.Kalakeri:BAAALgAECgMJAwAAAA==.Kalaman:BAAALgAECgYJCgAAAA==.Kalian:BAABLgAECn8XAAIGAAcJ+xXaKwCgAQAGAAcJ+xXaKwCgAQAAAA==.Kalito:BAAALgAECgQJDQAAAA==.Kamb:BAABLgAECn8eAAITAAcJ6hcnBgCfAQATAAcJ6hcnBgCfAQAAAA==.Karalee:BAAALgAECgMJBgAAAA==.Karn:BAAALgADCgEJAQAAAA==.Katieey:BAACLgAFFH8hAAIIAAcJPyUCAAD0AgAIAAcJPyUCAAD0AgAuAAQKfxcAAwgACQnYJMQHAPgCAAgACAmTJMQHAPgCABQABAmiHX47AF8BAAAA.Kayde:BAAALgAECgYJDAAAAA==.Kayil:BAAALgAECgYJDAAAAA==.Kayl:BAABLgAECn8kAAMFAAgJXhMTFACoAQAFAAgJBRMTFACoAQAlAAQJPxHMKADZAAAAAA==.Kaylli:BAAALgAECgQJBgAAAA==.',
Ke='Kedalin:BAAALgAECgIJAgAAAA==.Keelnin:BAAALgAECgIJBAAAAA==.Keloko:BAAALgAECgQJBgAAAA==.Kennyloggy:BAACLgAFFH8aAAIVAAcJmiHBAABWAgAVAAcJmiHBAABWAgAuAAQKfzYAAhUACQlwJlMAAIEDABUACQlwJlMAAIEDAAAA.Kevris:BAABLgAECn8cAAIPAAgJng2ePQByAQAPAAgJng2ePQByAQAAAA==.Keydan:BAAALgAECgYJEAAAAA==.',
Kh='Khaitiff:BAAALgADCgYJBgAAAA==.Khyn:BAAALgAECgQJCAAAAA==.',
Ki='Killmaim:BAAALgAECgYJBgAAAA==.Killrok:BAAALgADCgUJBQAAAA==.Kinikey:BAAALgAECgYJDQAAAA==.',
Kl='Klassy:BAABLgAECn8xAAIQAAgJ5COcAgDCAgAQAAgJ5COcAgDCAgAAAA==.',
Kn='Knardil:BAAALgADCgIJBAAAAA==.',
Ko='Kolosim:BAAALgADCgYJBgAAAA==.Koppi:BAAALgAECgMJBgAAAA==.Korru:BAAALgAECgYJEgAAAA==.Kotie:BAABLgAECn8iAAIVAAgJyxM8EADPAQAVAAgJyxM8EADPAQAAAA==.',
Kr='Kramz:BAAALgAFFAMJBAAAAA==.Kronar:BAAALgAECgMJBgAAAA==.',
Ku='Kumojo:BAAALgADCgYJBgAAAA==.Kunka:BAAALgAECgYJCQAAAA==.Kurgan:BAAALgAECgEJBQAAAA==.',
Ky='Kyojin:BAAALgAECgEJAQAAAA==.Kyoshino:BAAALgAECgMJAwAAAA==.Kyrgune:BAAALgADCgkJFwAAAA==.',
['Kî']='Kîkuko:BAAALgAECgQJBAAAAA==.',
['Kÿ']='Kÿliah:BAAALgAECgEJAQAAAA==.',
La='Lalo:BAAALgAECgQJBgAAAA==.Landilion:BAAALgADCgYJBgAAAA==.Laoftey:BAABLgAECn8mAAMIAAgJKB+UDQBcAgAIAAgJKB+UDQBcAgAUAAEJ2Q9UiQAvAAAAAA==.Laofty:BAAALgADCgYJBgAAAA==.Lar:BAAALgADCgEJAgAAAA==.Laserbeam:BAAALgAECgUJDgABLgAFFAEJAQABAAAAAA==.Lasmori:BAAALgAECgYJDwAAAA==.Lazaris:BAAALgADCgYJBgAAAA==.',
Le='Leglock:BAABLgAECn8RAAISAAYJRQ5+UwAAAQASAAYJRQ5+UwAAAQAAAA==.Leprhicon:BAAALgADCgcJBwAAAA==.Lesbihonest:BAABLgAECn8bAAMMAAcJQBL9TABeAQAMAAcJ9xH9TABeAQAeAAUJWRIcIQD+AAAAAA==.',
Li='Liendria:BAAALgADCgIJAgAAAA==.Lifensoftpaw:BAACLgAFFH8WAAMRAAYJpheEAQC9AQARAAUJIxuEAQC9AQAkAAQJSQFoGAC8AAAuAAQKfyUABBEACQnXI1kLAMQCABEACQnXI1kLAMQCAAoABQl3HJw4AGcBACQAAglwAUFzAB8AAAAA.Lightcaller:BAAALgADCgEJAQAAAA==.Lightflasher:BAAALgAECgcJEAAAAA==.Likkash:BAAALgAECgcJBwABLgAECggJKgAfAIAZAA==.Linari:BAAALgADCgMJAwAAAA==.Linthabeela:BAAALgADCgcJDgAAAA==.Lishalthen:BAAALgADCggJCAAAAA==.Lisyanthus:BAAALgAECgcJBwAAAA==.Livicecia:BAAALgAECggJEgAAAA==.',
Lo='Loaftey:BAAALgADCggJCAAAAA==.Longworth:BAAALgADCgIJAgAAAA==.Lookman:BAAALgAECgYJEwAAAA==.Lothema:BAAALgAECgYJCgAAAA==.Lowang:BAAALgAECgEJAgAAAA==.',
Lu='Lucaromu:BAAALgAECgEJAQAAAA==.Lucielinna:BAAALgAECggJDAAAAA==.Luckiiem:BAABLgAECn8oAAIHAAgJ0B+TFAB1AgAHAAgJ0B+TFAB1AgAAAA==.Luisfriendsn:BAAALgADCgEJAQABLgAECgcJHAAZAJMZAA==.Lunabreeze:BAAALgADCgkJEAAAAA==.Lunarkin:BAAALgAECgYJEQAAAA==.Luoma:BAAALgAECgUJEgAAAA==.Luthane:BAABLgAECn8ZAAIMAAcJSAgQawAXAQAMAAcJSAgQawAXAQAAAA==.',
Ly='Lyfeliss:BAAALgAECgYJDAAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lynnesa:BAAALgAECgIJAgAAAA==.',
Ma='Maccolyn:BAABLgAECn8cAAIMAAkJaxZFIAAIAgAMAAkJaxZFIAAIAgAAAA==.Magicpie:BAABLgAECn8sAAIdAAgJSR+REQBVAgAdAAgJSR+REQBVAgAAAA==.Magikar:BAAALgAECgEJAQAAAA==.Magiren:BAAALgAECgYJBwAAAA==.Mahlock:BAABLgAECn8yAAIOAAgJTBmPCQAIAgAOAAgJTBmPCQAIAgAAAA==.Mainah:BAAALgAECgIJAgAAAA==.Makanai:BAAALgAECgYJDgAAAA==.Makenai:BAAALgADCgkJEAABLgAECgYJDgABAAAAAA==.Makishi:BAABLgAECn8dAAITAAcJ0CAtAwAoAgATAAcJ0CAtAwAoAgAAAA==.Malferious:BAAALgADCgYJBgAAAA==.Malfura:BAAALgAECgYJDQAAAA==.Malário:BAAALgADCgMJAwAAAA==.Manamontana:BAABLgAECn8XAAIHAAcJaQ4DnACdAQAHAAcJaQ4DnACdAQAAAA==.Maplebunny:BAAALgADCgMJAwAAAA==.Mascdomtop:BAABLgAECn8dAAMdAAgJ/h50CADEAgAdAAgJ/h50CADEAgAoAAgJRAr+HABUAQAAAA==.Maube:BAAALgAECgEJAgABLgAFFAQJDAAeAFMNAA==.Mazzarzul:BAAALgAECgYJEwABLgAFFAQJCQAQAJcOAA==.',
Me='Meebles:BAABLgAECn8sAAINAAkJIREhCACrAQANAAkJIREhCACrAQAAAA==.Meiana:BAABLgAECn8aAAIFAAgJBhSSJwCAAQAFAAgJBhSSJwCAAQAAAA==.Mekanismz:BAAALgADCgkJCQABLgAECggJJgAmAGokAA==.Melanthia:BAAALgAECgEJAQAAAA==.Melasmus:BAAALgAECgEJAQAAAA==.Mendu:BAAALgADCgcJBwAAAA==.Mes:BAAALgAECgkJEgAAAA==.Metacarpal:BAAALgAECgkJCQAAAA==.',
Mi='Micklaa:BAABLgAECn8aAAIHAAcJ1QmKZQBGAQAHAAcJ1QmKZQBGAQAAAA==.Mightybelle:BAAALgAECgkJAgAAAA==.Mightychi:BAAALgAECgUJEgAAAA==.Milan:BAAALgADCgkJCQAAAA==.Milicka:BAAALgADCgkJBwAAAA==.Milkbunny:BAAALgADCgMJAwAAAA==.Millenium:BAAALgAECgQJCgAAAA==.Mingtai:BAAALgAECgYJEQAAAA==.Mirixa:BAAALgADCgYJBgAAAA==.Mizzakien:BAAALgAECgYJCwAAAA==.',
Mo='Monk:BAACLgAFFH8GAAIKAAMJPBvVFwCwAAAKAAMJPBvVFwCwAAAuAAQKfxwAAgoABwkzJQAaADQCAAoABwkzJQAaADQCAAAA.Monkyo:BAAALgAECgcJEgAAAA==.Monrea:BAAALgADCgcJFgABLgAECgUJDQABAAAAAA==.Moondolli:BAAALgADCgEJAQAAAA==.Moonriver:BAABLgAECn8iAAQIAAcJAQpIWgAfAQAIAAcJAQpIWgAfAQAnAAYJpQl4EAD5AAAUAAMJeAjQRwCIAAAAAA==.Moonsinde:BAABLgAECn8WAAIVAAYJHBIDJgANAQAVAAYJHBIDJgANAQAAAA==.Moranta:BAABLgAECn8UAAMoAAcJUwKKOACjAAAoAAYJkgKKOACjAAAdAAMJ3gGyQQBeAAAAAA==.Moressandra:BAAALgAECgYJDAAAAA==.',
Mu='Muncher:BAAALgAECgEJAQAAAA==.Munchiss:BAAALgADCgEJAQAAAA==.Murathiel:BAAALgAECgQJCQABLgAFFAUJDQAkAMIeAA==.Murdermass:BAAALgADCgkJEwAAAA==.',
My='Myke:BAAALgAECgEJAQAAAA==.Mykellcat:BAABLgAECn8UAAMWAAYJ+CX7CgCZAgAWAAYJ+CX7CgCZAgAVAAUJIBy7HABOAQAAAA==.Mysticarc:BAAALgAECggJEgAAAA==.Mysticmurv:BAACLgAFFH8GAAIpAAMJhwz+CgDmAAApAAMJhwz+CgDmAAAuAAQKfxkAAikACAkvHLkQAFwCACkACAkvHLkQAFwCAAAA.Myvirdaeth:BAAALgADCgEJAQAAAA==.',
Na='Naeni:BAAALgAECgEJAgAAAA==.Nahli:BAAALgAECgkJEgAAAA==.Nakkarn:BAAALgADCgQJBAAAAA==.Nalynahwe:BAAALgAECgcJEwAAAA==.Narima:BAAALgAECgUJEgAAAA==.Naura:BAAALgADCgEJAQAAAA==.Navirose:BAAALgAECgQJCAAAAA==.',
Ne='Neltheron:BAAALgADCgIJAgAAAA==.',
Nh='Nhala:BAAALgAECgIJAgABLgAECgQJBQABAAAAAA==.',
Ni='Nickspally:BAAALgADCgYJBgABLgAECggJGQAbAMMcAA==.Nightestrike:BAAALgADCgQJBAAAAA==.Nikodem:BAAALgAECgYJEwAAAA==.Ninali:BAAALgAECgYJCgAAAA==.Ninerva:BAAALgAECgkJDgAAAA==.Nivajh:BAAALgAECgEJAQAAAA==.',
No='Nore:BAABLgAECn8dAAIiAAcJmBq/CwAVAgAiAAcJmBq/CwAVAgAAAA==.',
Nv='Nvfos:BAAALgADCgUJBQAAAA==.',
Ny='Nyali:BAAALgAECgEJAQABLgAECggJGwAWAFsTAA==.',
['Nà']='Nàdya:BAABLgAECn8wAAQIAAgJeSGECADtAgAIAAgJeSGECADtAgAUAAIJNANWXABDAAAnAAEJHASyIQAqAAAAAA==.',
['Nî']='Nîghtshade:BAAALgADCgkJCAAAAA==.Nîkodemus:BAAALgADCgYJBgAAAA==.',
Ob='Oblivions:BAABLgAECn8mAAMmAAgJaiTrCQAQAwAmAAgJaiTrCQAQAwAgAAQJix7LDQBlAQAAAA==.Oblivionsdk:BAAALgAECggJCQABLgAECggJJgAmAGokAA==.',
Od='Odyfan:BAAALgADCgEJAQAAAA==.',
Of='Ofelia:BAAALgAECgYJDAAAAA==.',
Og='Ogion:BAAALgAECgEJAQAAAA==.',
Om='Omniray:BAABLgAECn8cAAIVAAcJzhKaGAB1AQAVAAcJzhKaGAB1AQAAAA==.Omnitruce:BAAALgAECgMJAwAAAA==.',
On='Onekark:BAAALgAECgQJCAABLgAFFAYJGwAIAJMbAA==.Onirei:BAAALgADCgEJAwAAAA==.',
Op='Ophèlia:BAAALgADCgMJCwAAAA==.',
Or='Orckus:BAAALgAECgMJBgAAAA==.Oreosbunny:BAAALgAECgEJAQAAAA==.',
Os='Oshrick:BAAALgADCgEJAQAAAA==.Osvaldr:BAAALgAECgQJBQAAAA==.',
Ow='Owil:BAAALgAECggJEgAAAA==.',
Pa='Palamedes:BAAALgADCgYJBgAAAA==.Pandaburn:BAABLgAECn8YAAIHAAcJ5Bi7OAC/AQAHAAcJ5Bi7OAC/AQAAAA==.Pandais:BAAALgAECgYJDwAAAA==.Paranne:BAABLgAECn8sAAIHAAkJARo/EgCHAgAHAAkJARo/EgCHAgAAAA==.Paroxism:BAABLgAECn8fAAIVAAgJhiJSBACzAgAVAAgJhiJSBACzAgAAAA==.Parthurnax:BAAALgAECgUJDgAAAA==.Patapouf:BAABLgAECn8cAAMiAAYJBCOACABWAgAiAAYJBCOACABWAgAoAAYJzxmcFwCCAQAAAA==.Patrisse:BAAALgADCgMJAwAAAA==.Pauhana:BAAALgADCgkJDwABLgAECgUJEgABAAAAAA==.',
Pe='Peanût:BAABLgAECn8sAAIWAAgJKB78CAC6AgAWAAgJKB78CAC6AgAAAA==.Pesante:BAABLgAECn8qAAIiAAkJWRjiBgB/AgAiAAkJWRjiBgB/AgAAAA==.',
Ph='Phaket:BAAALgADCgYJBwAAAA==.Phatums:BAACLgAFFH8MAAIEAAQJ7B/7HwBgAQAEAAQJ7B/7HwBgAQAuAAQKfyEAAgQACAnjInwSAA0DAAQACAnjInwSAA0DAAAA.Philippy:BAAALgADCgYJBwAAAA==.',
Pi='Pika:BAABLgAECn8XAAMVAAgJqQ6fHQBIAQAVAAgJ/gifHQBIAQAbAAQJhRLrHQD3AAAAAA==.Pinix:BAAALgAECgEJAgAAAA==.Pinulito:BAAALgADCgMJAwAAAA==.Pippá:BAAALgAECgQJCAAAAA==.',
Po='Polonius:BAAALgAECgcJDwAAAA==.',
Pr='Praline:BAAALgADCgEJAQAAAA==.Pranaverde:BAAALgAECgYJDAAAAA==.Prisevide:BAAALgAECgYJEgAAAA==.Priss:BAAALgADCgkJFwAAAA==.',
Ps='Psyched:BAAALgADCgEJAQAAAA==.',
Pu='Pumpy:BAAALgADCgcJCAAAAA==.',
Py='Pythe:BAABLgAECn8sAAIMAAkJWiGfBAAHAwAMAAkJWiGfBAAHAwAAAA==.',
Qa='Qap:BAABLgAECn8cAAIZAAgJchQjAgDcAQAZAAgJchQjAgDcAQAAAA==.Qara:BAAALgADCgYJBgAAAA==.',
Qu='Qualnorr:BAAALgAECgUJCQAAAA==.Quelastraaza:BAAALgADCgUJBQAAAA==.Queldraayan:BAAALgAECgIJBAAAAA==.Quixediah:BAACLgAFFH8JAAIWAAQJIxb0EwAuAQAWAAQJIxb0EwAuAQAuAAQKfx0AAhYACAn0IZAJAPkCABYACAn0IZAJAPkCAAAA.Quixhea:BAAALgAECgUJEQABLgAFFAQJCQAWACMWAA==.Quixxie:BAAALgADCgYJBgABLgAFFAQJCQAWACMWAA==.Quixxum:BAAALgADCgMJAwABLgAFFAQJCQAWACMWAA==.',
Ra='Radalas:BAAALgAECgYJEQAAAA==.Radreliris:BAAALgAECgUJCgAAAA==.Rahdalas:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.Rally:BAAALgAECgYJEwAAAA==.Ramanujan:BAAALgAECgIJAgAAAA==.Ramcco:BAEALgAECgYJEQAAAA==.Ranelle:BAABLgAECn8sAAIdAAkJ7xJnDAAfAgAdAAkJ7xJnDAAfAgAAAA==.Rasmira:BAAALgAECgYJEgAAAA==.Ravenis:BAABLgAECn8iAAIOAAgJHSBRAwCnAgAOAAgJHSBRAwCnAgAAAA==.Razekial:BAAALgAECgYJCQAAAA==.Razelikh:BAAALgADCgYJBgAAAA==.',
Re='Reedem:BAABLgAECn8UAAIRAAYJdwqNMADDAAARAAYJdwqNMADDAAAAAA==.Regilock:BAACLgAFFH8ZAAQPAAcJlRwiAgAVAgAPAAYJSh4iAgAVAgAXAAQJzREkAwAZAQAYAAEJUwwoBgBTAAAuAAQKfyEABA8ACQleJdMIADoDAA8ACAkpJdMIADoDABcABAnsHgwiAEUBABgAAQkAAO0jAGIAAAAA.Regilocklr:BAAALgAECgYJDwAAAA==.Reikí:BAABLgAECn8cAAIHAAgJdxGRPwCpAQAHAAgJdxGRPwCpAQAAAA==.Relarria:BAAALgAECgMJAwAAAA==.Renbe:BAAALgADCgYJCAAAAA==.Renwald:BAABLgAECn8UAAMMAAYJdhF3kwBWAQAMAAYJdhF3kwBWAQAeAAMJzQozNAB3AAAAAA==.Revgard:BAAALgAECgYJEQAAAA==.',
Rh='Rhasalgul:BAAALgAECgMJBAAAAA==.',
Ro='Rolhen:BAAALgAECgUJBwAAAA==.Ronso:BAAALgADCgQJBAAAAA==.Ronta:BAAALgADCgYJCgAAAA==.Rowain:BAAALgADCgkJEAAAAA==.',
Ru='Rustyheals:BAAALgADCgkJDwAAAA==.',
Ry='Ryanari:BAAALgAECgQJBQAAAA==.Rylacus:BAAALgAECgYJEwAAAA==.',
['Rê']='Rêgret:BAAALgADCgYJCQAAAA==.',
Sa='Saanda:BAAALgAECgUJCAAAAA==.Sagazboy:BAAALgAECgYJEQABLgAECggJJgAMAPIUAA==.Sagazpally:BAABLgAECn8mAAIMAAgJ8hQ1KwDRAQAMAAgJ8hQ1KwDRAQAAAA==.Salandre:BAAALgADCgMJAwAAAA==.Salutations:BAAALgAFFAIJAgAAAA==.Salv:BAAALgADCgIJAgAAAA==.Sandp:BAAALgAFFAEJAQAAAA==.Sapphin:BAAALgADCgQJBAAAAA==.Sarlef:BAABLgAECn8ZAAIJAAcJFBMCEABiAQAJAAcJFBMCEABiAQAAAA==.Sashafel:BAAALgADCggJCAAAAA==.',
Sc='Scyithe:BAAALgADCgEJAQAAAA==.',
Se='Sellidra:BAABLgAECn8UAAIGAAYJswyKVAARAQAGAAYJswyKVAARAQAAAA==.Sendcatpics:BAABLgAECn8sAAMCAAkJPRD/FwDMAQACAAkJPRD/FwDMAQAMAAUJBBrugwByAQABLgAFFAIJAgABAAAAAA==.Seo:BAAALgAFFAIJBAAAAA==.Serenitara:BAAALgADCgYJBgAAAA==.Serharimia:BAAALgADCgYJBgAAAA==.Sethia:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Sevotarthe:BAAALgADCgMJAwAAAA==.Seyana:BAABLgAECn8VAAIGAAYJrBjWMgCCAQAGAAYJrBjWMgCCAQAAAA==.',
Sh='Shaaddow:BAAALgADCgUJBQAAAA==.Shadowkaos:BAAALgAECgUJCAAAAA==.Shaffer:BAAALgAECgcJDgAAAA==.Shellmage:BAAALgAECgYJCwAAAA==.Shellshocker:BAACLgAFFH8HAAIUAAMJPSD7CwAtAQAUAAMJPSD7CwAtAQAuAAQKfxYAAhQACAndJfcIAAMDABQACAndJfcIAAMDAAAA.Shermantånk:BAAALgAECgEJAQAAAA==.Sheydon:BAAALgADCgQJBAAAAA==.Shiftstain:BAAALgADCgIJAgAAAA==.Shikï:BAACLgAFFH8GAAIoAAMJlBzXDgAhAQAoAAMJlBzXDgAhAQAuAAQKfyMAAigACQnjIb4EAJgCACgACQnjIb4EAJgCAAAA.Shivermoón:BAABLgAECn8oAAIWAAgJOBQFHQDbAQAWAAgJOBQFHQDbAQAAAA==.Shobek:BAAALgAECgYJBgAAAA==.Shortie:BAAALgADCgYJBgAAAA==.',
Si='Sigesar:BAABLgAECn8eAAIdAAcJjQevJgAUAQAdAAcJjQevJgAUAQAAAA==.Sigrún:BAAALgAECgUJBAAAAA==.Silvaria:BAAALgAECgMJBAAAAA==.Simina:BAAALgAECgEJAQAAAA==.Simpforsouls:BAAALgAECgYJDAAAAA==.Simura:BAAALgAFFAEJAgAAAA==.Sinamara:BAAALgADCgkJGgAAAA==.Sinsimella:BAAALgAECgMJAwAAAA==.Sinõn:BAAALgAECgYJCgAAAA==.',
Sk='Skyliner:BAAALgAECgQJBQAAAA==.Skyskitty:BAAALgAECgYJCwAAAA==.Skywatcher:BAABLgAECn8cAAIGAAYJgglGWQAEAQAGAAYJgglGWQAEAQAAAA==.',
Sl='Slaughtering:BAAALgAECgYJDwAAAA==.',
Sm='Smesus:BAAALgAECgEJAQAAAA==.Smitemare:BAAALgAECgQJBgAAAA==.',
So='Solare:BAAALgADCggJFgAAAA==.Solianti:BAAALgADCgYJBgAAAA==.Solodan:BAAALgAECgYJDQABLgAECggJGgAVAIgYAA==.Solodane:BAAALgAECgcJDAAAAA==.Sonnwar:BAABLgAECn8hAAICAAgJiBs7GwCvAQACAAgJiBs7GwCvAQAAAA==.',
Sp='Spliphtoker:BAAALgAECgQJCgAAAA==.Spookytotems:BAABLgAECn8iAAInAAcJMxZdCQCHAQAnAAcJMxZdCQCHAQAAAA==.',
St='Stenston:BAAALgAECgYJCwAAAA==.Sterede:BAAALgAECgQJBgAAAA==.Stonehenge:BAABLgAECn8UAAMMAAYJgQdzfwDtAAAMAAYJcgdzfwDtAAAeAAMJCALtLgA+AAAAAA==.Stormb:BAAALgADCgkJGwAAAA==.Stormwolves:BAAALgAECgIJAgAAAA==.',
Sy='Sylphr:BAAALgAECgQJCwAAAA==.Sylphwild:BAAALgAECgIJAgABLgAFFAMJAwABAAAAAA==.Sylvanase:BAAALgAECgcJCgAAAA==.Sylvara:BAAALgADCgYJBgAAAA==.Synapze:BAABLgAECn8dAAIHAAcJkQ83VgBqAQAHAAcJkQ83VgBqAQAAAA==.Syreite:BAABLgAECn8jAAINAAgJjhdsBgDiAQANAAgJjhdsBgDiAQAAAA==.Syreyna:BAAALgADCgIJAgAAAA==.',
Ta='Taessa:BAAALgAECgUJBQAAAA==.Tahwye:BAAALgADCgkJIAAAAA==.Tainipuni:BAAALgAECgUJEQAAAA==.Takemi:BAAALgAECggJCQAAAA==.Tal:BAAALgAECggJCAABLgAECggJKgAeAMIYAA==.Tallac:BAAALgADCgYJBgABLgAECggJKgAeAMIYAA==.Tallaric:BAAALgADCgkJFAABLgAECggJKgAeAMIYAA==.Tallic:BAABLgAECn8qAAIeAAgJwhjmCgCSAQAeAAgJwhjmCgCSAQAAAA==.Tamarah:BAAALgAECgYJDAAAAA==.Tamzyyn:BAAALgAECgYJDwAAAA==.Tandemonium:BAAALgAECgEJAQABLgAFFAUJDAApANsgAA==.Taniz:BAABLgAECn8XAAMGAAgJ9xoKGQByAgAGAAgJ5xoKGQByAgALAAMJ9Q2sdgBkAAAAAA==.Tankfu:BAAALgAECgUJBwAAAA==.Tarsi:BAAALgAECgQJCQAAAA==.Tashoonne:BAAALgADCgUJBwAAAA==.Taylin:BAAALgAECgIJAgABLgAECgQJCAABAAAAAA==.',
Te='Teareagana:BAAALgAECgYJCgABLgAECgkJGgAfAHweAA==.Tearinurside:BAAALgAECgYJEwAAAA==.Teddy:BAAALgADCgUJBQABLgAFFAMJBwAkACEcAA==.Telchar:BAAALgAECgUJDgAAAA==.Telidrel:BAAALgADCgMJAwAAAA==.Telrienn:BAAALgADCgIJAgAAAA==.Teratin:BAABLgAECn8cAAIKAAgJ/h9nBwBaAgAKAAgJ/h9nBwBaAgAAAA==.Tevellan:BAAALgADCgYJBwAAAA==.',
Th='Thaddeaus:BAABLgAECn8ZAAIJAAgJDBkZDQA6AgAJAAgJDBkZDQA6AgAAAA==.Thaddeus:BAABLgAECn8eAAIMAAcJ1hpKJwDjAQAMAAcJ1hpKJwDjAQAAAA==.Thauris:BAAALgAECgEJAwAAAA==.Thealin:BAAALgAECgMJAwAAAA==.Thebeefyone:BAABLgAECn8UAAIHAAYJvRFvZABJAQAHAAYJvRFvZABJAQAAAA==.Thelesar:BAAALgADCgYJCAAAAA==.Therizin:BAAALgAECgYJEgAAAA==.Thesummoner:BAABLgAECn8XAAMPAAgJJyDREwDeAgAPAAgJJyDREwDeAgAXAAEJxxVWawA8AAABLgAFFAEJAQABAAAAAA==.Thicciana:BAABLgAFFH8GAAIKAAQJhxn2DABOAQAKAAQJhxn2DABOAQAAAA==.Thorizan:BAAALgAECgQJBwAAAA==.Thugnificent:BAAALgADCgcJCgAAAA==.Thumpette:BAAALgADCgMJAwAAAA==.Thuviel:BAAALgAECgIJAwAAAA==.Thè:BAAALgAECgYJCwAAAA==.',
Ti='Tierant:BAAALgAECgEJAQAAAA==.Tituz:BAAALgADCgMJBAAAAA==.Tizaria:BAABLgAECn8WAAIdAAcJMhPJGQB/AQAdAAcJMhPJGQB/AQAAAA==.',
Tm='Tmai:BAAALgAECgYJEwAAAA==.',
To='Tolken:BAAALgAECgEJAQAAAA==.Tominaetor:BAABLgAECn8eAAIPAAYJLAtwYAAQAQAPAAYJLAtwYAAQAQAAAA==.Tosoto:BAABLgAECn8kAAMgAAkJoRyeAgCUAgAgAAkJmBqeAgCUAgAmAAgJIRviCgA6AgAAAA==.Toxerus:BAAALgAECgMJBAAAAA==.',
Tr='Trixigossa:BAAALgADCggJEgABLgAECgUJBwABAAAAAA==.Trobbio:BAAALgADCgIJAgAAAA==.',
Ts='Tso:BAABLgAECn8ZAAMkAAcJfBehGACMAQAkAAYJOhmhGACMAQARAAEJLQYQagAoAAAAAA==.Tsukuyomï:BAAALgAECgMJBwABLgAFFAMJBgAoAJQcAA==.',
Tu='Tuskmunkey:BAAALgAECgMJBgAAAA==.',
Ty='Tyernan:BAABLgAECn8qAAMCAAgJgwj1IgBwAQACAAgJgwj1IgBwAQAMAAIJyAQuJwFRAAAAAA==.Tyka:BAAALgADCgYJBgABLgAECgUJEgABAAAAAA==.Tym:BAAALgADCgkJDAAAAA==.Tyrael:BAABLgAECn8vAAIMAAgJ3QvFSABrAQAMAAgJ3QvFSABrAQAAAA==.Tyreanna:BAAALgADCgEJAgAAAA==.Tyrioz:BAABLgAECn8cAAMCAAgJ3g/8KgA3AQACAAcJXQ/8KgA3AQAMAAQJ2g4FxQBuAAAAAA==.',
Tz='Tzavcat:BAABLgAECn8XAAIWAAYJSweqVQDCAAAWAAYJSweqVQDCAAAAAA==.',
Ul='Uluhn:BAAALgADCggJDgABLgAECgQJBQABAAAAAA==.',
Ur='Urklesnurkle:BAAALgAECgUJCQAAAA==.',
Uv='Uvsol:BAAALgAECgYJBwAAAA==.',
Va='Vadailla:BAAALgADCgYJDgABLgAECgUJEgABAAAAAA==.Vahrik:BAAALgAECgEJAQAAAA==.Valcane:BAAALgADCgkJEgAAAA==.Valdictorian:BAAALgAECgEJAQAAAA==.Valius:BAABLgAECn8bAAIlAAcJgh5iAgAoAgAlAAcJgh5iAgAoAgAAAA==.Vallarium:BAAALgADCgYJFwAAAA==.Valornor:BAAALgAECgQJBgAAAA==.Valyerian:BAAALgAECgUJBgAAAA==.Vanacarde:BAAALgAECgUJBQAAAA==.Vandilious:BAAALgAECgYJCwABLgAECgYJEwABAAAAAA==.Vandill:BAAALgAECgYJEwAAAA==.Vaneadra:BAAALgADCgUJCwAAAA==.Vaxis:BAAALgADCgUJBQAAAA==.',
Ve='Veasnacool:BAAALgAECggJEQAAAA==.Velanlan:BAAALgADCgUJCQAAAA==.Velion:BAAALgADCgYJBgAAAA==.',
Vh='Vhesper:BAAALgAECgMJAwAAAA==.',
Vi='Vii:BAAALgAECggJEgAAAA==.Vivacia:BAAALgAECgQJBAAAAA==.',
Vo='Voidfisting:BAABLgAECn8tAAMRAAgJLAzsHgAsAQARAAcJhQvsHgAsAQAkAAgJ+wc8KQADAQAAAA==.Volfurion:BAAALgADCgQJBAAAAA==.Vontote:BAAALgAECgcJEwAAAA==.Vorix:BAAALgAECgYJEgAAAA==.Vorrel:BAAALgADCgkJFwABLgAECggJJAAFAF4TAA==.',
Vu='Vunak:BAAALgADCgcJDQAAAA==.',
['Ví']='Víc:BAABLgAECn8ZAAICAAcJcCI+BgC8AgACAAcJcCI+BgC8AgAAAA==.',
Wa='Wandorf:BAEBLgAECn8eAAIEAAcJRw7ASQBeAQAEAAcJRw7ASQBeAQAAAA==.Warbacon:BAAALgADCgMJAwAAAA==.Wargyle:BAABLgAECn8YAAMPAAcJCBD2PwBqAQAPAAcJCBD2PwBqAQAXAAEJAADCcAA1AAAAAA==.Warwolfe:BAABLgAECn8sAAMPAAgJhQjcRgBUAQAPAAgJJwjcRgBUAQAYAAUJ+QfyFgDIAAAAAA==.Wayler:BAAALgAECgIJAgAAAA==.',
We='Wealthywolf:BAABLgAECn8WAAMQAAcJwwerHgALAQAQAAcJwwerHgALAQALAAEJwgBsmwATAAAAAA==.Werepinguin:BAAALgADCgMJAwAAAA==.',
Wh='Whitewicca:BAAALgADCgQJBAAAAA==.',
Wi='Wilbrew:BAAALgAECgEJAQABLgAECggJEgABAAAAAA==.Wistful:BAAALgAECgcJCAAAAA==.',
Wl='Wlitia:BAAALgAECgQJBAAAAA==.',
Wo='Wolferunner:BAAALgAECgYJEQAAAA==.',
Wr='Wrathome:BAABLgAECn8cAAMPAAcJgxqoQAALAgAPAAcJgxqoQAALAgAXAAMJtgrQRgCbAAAAAA==.Wráth:BAAALgADCggJCAAAAA==.',
Xa='Xalatäth:BAAALgAECgMJBAAAAA==.Xaldora:BAAALgAECgEJAgAAAA==.Xandrake:BAAALgAECgYJDAABLgAFFAYJEQAFAM0dAA==.',
Xd='Xdxvuu:BAAALgAECgYJDgAAAA==.',
Xe='Xerimok:BAAALgAECgYJEwAAAA==.',
Xi='Xinya:BAAALgAECgYJDQAAAA==.Xipa:BAABLgAECn8nAAILAAgJ3Bz9AgA4AgALAAgJ3Bz9AgA4AgAAAA==.',
Xl='Xladykahlron:BAAALgADCgYJCAAAAA==.',
Xo='Xolara:BAAALgAECgIJBAAAAA==.',
Xs='Xsavior:BAAALgAECgQJCAAAAA==.Xshan:BAAALgAECgEJAgAAAA==.Xshando:BAAALgAECgQJCwAAAA==.',
Xy='Xyi:BAAALgAECggJEQAAAA==.',
Xz='Xzephyr:BAABLgAECn8sAAIVAAkJgSHCAQAcAwAVAAkJgSHCAQAcAwAAAA==.',
Ya='Yamato:BAABLgAECn8dAAIJAAgJiQfIFQAXAQAJAAgJiQfIFQAXAQAAAA==.',
Ye='Yesmín:BAAALgAECgUJCQAAAA==.',
Yo='Youwas:BAAALgAECgcJCgAAAA==.Yoveladari:BAAALgADCgIJAgAAAA==.',
Yu='Yukimenoko:BAAALgAECgUJDAAAAA==.Yukmouf:BAABLgAECn8VAAIMAAgJ2BtkIwCbAgAMAAgJ2BtkIwCbAgAAAA==.',
Za='Zabrak:BAAALgAECgQJBgAAAA==.Zakaris:BAAALgAECgQJBwAAAA==.Zalaeran:BAAALgADCgEJAQAAAA==.Zalatath:BAAALgADCgkJHgAAAA==.Zanbu:BAAALgAECgQJAgAAAA==.Zarrov:BAAALgADCgkJGgAAAA==.Zarrove:BAABLgAECn8uAAIRAAgJQSMQBACuAgARAAgJQSMQBACuAgAAAA==.',
Ze='Zea:BAAALgAECgMJBAAAAA==.Zedael:BAABLgAECn8cAAIfAAgJQRewDQCWAQAfAAgJQRewDQCWAQAAAA==.Zeltri:BAAALgAECgIJBAAAAA==.Zeritha:BAAALgAECgEJAgAAAA==.',
Zh='Zhatva:BAABLgAECn8ZAAIGAAgJKCGWCwCDAgAGAAgJKCGWCwCDAgAAAA==.Zhöe:BAABLgAECn8UAAMIAAkJXh48DQCyAgAIAAgJtR08DQCyAgAUAAcJBhoWNgB8AQAAAA==.',
Zo='Zoldor:BAABLgAECn8aAAMPAAcJqxKGOQCAAQAPAAYJqxKGOQCAAQAXAAEJAABLdwAtAAAAAA==.Zoleia:BAAALgADCgIJAgAAAA==.Zoral:BAAALgADCgUJBQAAAA==.',
Zu='Zuldokah:BAAALgADCgEJAQAAAA==.',
Zy='Zy:BAAALgAFFAIJAgAAAA==.Zycorr:BAAALgAECgYJCQAAAA==.Zyheal:BAAALgAECggJEgAAAA==.Zymor:BAAALgAECgMJBgAAAA==.Zytrex:BAAALgAECgYJDAAAAA==.',
['Äm']='Ämaterasu:BAAALgADCgcJCgABLgAFFAMJBgAoAJQcAA==.',
['Ða']='Ðaniel:BAAALgAECgYJDQAAAA==.',
['Ðr']='Ðraevus:BAAALgAECgQJDAAAAA==.',
['Ñÿ']='Ñÿx:BAABLgAECn8UAAIPAAUJtAEesABiAAAPAAUJtAEesABiAAAAAA==.',
['ßl']='ßlueshield:BAAALgAECgYJEgAAAA==.',
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

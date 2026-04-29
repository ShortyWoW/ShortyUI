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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Druid-Restoration','Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','Mage-Frost','Monk-Windwalker','Hunter-Survival','Shaman-Enhancement','Priest-Holy','Priest-Shadow','Mage-Fire','Druid-Feral','Priest-Discipline','Warrior-Protection','Shaman-Elemental','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','DeathKnight-Blood','Rogue-Subtlety','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarkan:BAABLgAECn8VAAIBAAcJ1yUtEgABAwABAAcJ1yUtEgABAwAAAA==.',
Ac='Aceboss:BAAALgADCgYJBwAAAA==.Acidburn:BAAALgADCgMJBAAAAA==.',
Ad='Adetal:BAAALgAECgYJBgAAAA==.Adoroth:BAAALgADCgMJAwAAAA==.Adrenaline:BAAALgAECgMJAwAAAA==.',
Ae='Aeiro:BAABLgAECn8eAAICAAgJuhxXCwDMAQACAAgJuhxXCwDMAQAAAA==.Aericura:BAAALgADCggJBwAAAA==.Aetheriel:BAAALgAECgYJDAAAAA==.Aethon:BAAALgADCgcJDQAAAA==.',
Ag='Aggronok:BAAALgAFFAIJAwAAAA==.',
Ah='Ahnyanka:BAAALgADCgYJBgAAAA==.',
Ai='Aiaria:BAAALgAECgUJCQAAAA==.Airi:BAAALgADCgEJAQAAAA==.Airrin:BAAALgAECgYJBQAAAA==.',
Ak='Akari:BAABLgAECn8nAAMDAAgJOB8CAQDFAgADAAgJOB8CAQDFAgAEAAYJkA2TTwAFAQAAAA==.Akasha:BAABLgAECn8dAAIFAAgJeiDiBwD0AQAFAAgJeiDiBwD0AQAAAA==.Akatala:BAABLgAECn8UAAMGAAgJfhQlJgAiAgAGAAgJfhQlJgAiAgAHAAEJUgPulwAfAAAAAA==.Akunda:BAABLgAECn8fAAIIAAgJ7hJLKQDqAQAIAAgJ7hJLKQDqAQAAAA==.',
Al='Alamaania:BAAALgAECgYJDAAAAA==.Alaterial:BAAALgAECgEJAQAAAA==.Alazara:BAAALgAECgYJBgAAAA==.Aloha:BAACLgAFFH8KAAIJAAQJ0xgqCQBSAQAJAAQJ0xgqCQBSAQAuAAQKfxgAAgkACAkCIaILAN0CAAkACAkCIaILAN0CAAAA.Aluriel:BAABLgAECn8eAAQKAAgJRh0kDAC4AQAKAAgJRh0kDAC4AQALAAEJAAAeJABhAAAMAAIJ8hfQXwBPAAAAAA==.',
Am='Ambellìna:BAAALgADCgEJAQAAAA==.Ambellína:BAAALgADCgYJBgAAAA==.Amenrah:BAAALgADCgcJGAAAAA==.Amorisx:BAAALgADCgcJEQAAAA==.',
An='Anarchy:BAABLgAECn8ZAAIFAAgJCCFoCADsAQAFAAgJCCFoCADsAQAAAA==.Androse:BAAALgAECgcJEgAAAA==.',
Ar='Arai:BAAALgAECgIJAgAAAA==.Arclîght:BAAALgAECgQJCAAAAA==.Aruj:BAAALgAECgYJCAAAAA==.',
As='Ashkari:BAABLgAECn8VAAMCAAgJxR8SBwAQAgACAAgJxR8SBwAQAgANAAIJABfrEQByAAAAAA==.Astrea:BAABLgAECn8YAAIOAAYJ7hQsEABXAQAOAAYJ7hQsEABXAQAAAA==.',
At='Athenis:BAAALgAECgMJAwAAAA==.',
Au='Aurianna:BAAALgADCgEJAQAAAA==.',
Av='Avolokden:BAAALgAECgYJEgAAAA==.',
Az='Azem:BAAALgADCgUJBQAAAA==.Azmyth:BAACLgAFFH8OAAIBAAUJlSTXAACoAQABAAUJlSTXAACoAQAuAAQKfyAAAgEACAnUJuIEAH0DAAEACAnUJuIEAH0DAAAA.Azmythr:BAAALgADCgcJDQABLgAFFAUJDgABAJUkAA==.Azzaerial:BAAALgAECgMJAwAAAA==.',
Ba='Baez:BAAALgAECgEJAgABLgAECgUJDgAPAAAAAA==.Baolin:BAAALgADCgMJAwAAAA==.Bartahk:BAAALgAECgYJBgABLgAFFAIJAwAPAAAAAA==.Bashroot:BAAALgADCgUJBgAAAA==.Bastalion:BAAALgAECgMJBgAAAA==.Baxtersin:BAAALgAECgEJAQAAAA==.Baxtersinho:BAAALgAECgEJAQABLgAECgUJEwAPAAAAAA==.Bayz:BAAALgAECgQJBAAAAA==.',
Be='Beamkin:BAAALgADCggJCAAAAA==.Beardedwiz:BAAALgADCgMJAwAAAA==.Bearys:BAAALgADCgMJAwAAAA==.Beeshoney:BAAALgAECgYJBwAAAA==.Beighblade:BAAALgADCgMJAwABLgAECggJHQAEADMPAA==.Belgar:BAAALgAECgUJBgAAAA==.Berries:BAAALgADCggJFwAAAA==.Beson:BAAALgADCgQJBAAAAA==.Betræÿer:BAAALgADCgcJFwAAAA==.Beyondthedk:BAAALgAECgUJCAAAAA==.',
Bi='Bigazzdragon:BAABLgAECn8VAAQQAAcJYATbEQDUAAAQAAcJYATbEQDUAAARAAIJEgNcEAA2AAASAAIJGwEsPwAzAAAAAA==.Bigilli:BAAALgADCgEJAQAAAA==.Bigkahunas:BAABLgAECn8UAAIGAAcJnRqINQDYAQAGAAcJnRqINQDYAQAAAA==.Bigzacky:BAAALgAFFAEJAgAAAA==.Biodiesel:BAAALgAECgYJCgAAAA==.',
Bl='Blackfire:BAAALgAECgIJBAAAAA==.Bladlast:BAABLgAECn8fAAITAAgJHRA3MADAAQATAAgJHRA3MADAAQAAAA==.Blankee:BAACLgAFFH8MAAIUAAUJcx5dFAB5AQAUAAUJcx5dFAB5AQAuAAQKfyAAAhQACAl8JYcOAFIDABQACAl8JYcOAFIDAAAA.Blargo:BAACLgAFFH8FAAIOAAMJ+xuQBgALAQAOAAMJ+xuQBgALAQAuAAQKfyIAAg4ACAmSJp4BAIsDAA4ACAmSJp4BAIsDAAAA.Blinkygg:BAAALgADCgYJBwAAAA==.Bloodraven:BAABLgAECn8UAAMGAAYJZhzGOQDHAQAGAAYJZhzGOQDHAQAHAAUJygYbZACvAAAAAA==.Bloodyfinger:BAAALgAECgEJAQABLgAECgcJGQAVAFofAA==.',
Bo='Boat:BAACLgAFFH8JAAIDAAQJiSCxAgB1AQADAAQJiSCxAgB1AQAuAAQKfyIAAgMACAkrJhQCAHADAAMACAkrJhQCAHADAAAA.Bobarker:BAAALgAECgQJCQAAAA==.Bobpet:BAACLgAFFH8NAAMGAAUJPhPHCwAEAQAGAAQJJxLHCwAEAQAWAAMJuQzEAgD9AAAuAAQKfx4AAxYACAm6H7wIAFoCABYACAk4HrwIAFoCAAYABAnQHRVYAGABAAAA.Bohdi:BAAALgADCgEJAQAAAA==.Bombisevil:BAAALgAECgMJAwABLgAFFAUJDwAQAH8ZAA==.Boomins:BAAALgADCgUJBQAAAA==.Boonims:BAAALgADCggJCQAAAA==.Booze:BAAALgAECgMJAwABLgAFFAMJBQAOAPsbAA==.Borbadin:BAAALgADCgkJDQAAAA==.Borgîr:BAABLgAECn8gAAIXAAgJVB+wBADKAgAXAAgJVB+wBADKAgAAAA==.Bossee:BAABLgAECn8VAAMYAAcJJROzLwCDAQAYAAcJJROzLwCDAQAZAAIJ+wXQWABYAAABLgAFFAUJDAAUAHMeAA==.Bowfdeez:BAAALgADCgQJBgAAAA==.',
Br='Bradadin:BAAALgAECgQJBQAAAA==.Brainlagg:BAABLgAECn8eAAMKAAgJggylEwBzAQAKAAgJggylEwBzAQAMAAIJJwS2YQBKAAAAAA==.Brewsly:BAACLgAFFH8LAAIEAAQJjAopBgAUAQAEAAQJjAopBgAUAQAuAAQKfygAAgQACAkoG/QDAOwBAAQACAkoG/QDAOwBAAAA.Brightleaf:BAAALgAECgcJEQAAAA==.Bruor:BAAALgAECgUJBwAAAA==.Brusque:BAAALgAECgUJBgAAAA==.Bruteus:BAAALgADCgQJBAAAAA==.Bruzthemoose:BAAALgADCgEJAQAAAA==.Brynä:BAABLgAECn8UAAIaAAgJ9AQfBQBzAQAaAAgJ9AQfBQBzAQAAAA==.',
Bu='Bugbug:BAAALgAECgQJBAAAAA==.Buhr:BAAALgAECggJEwAAAA==.Bullhorndh:BAAALgADCgEJAQAAAA==.Bulvie:BAAALgADCgEJAQAAAA==.Burgerpants:BAAALgADCgcJDQABLgAFFAQJCAAFAH0kAA==.Burmiya:BAAALgADCgcJCAAAAA==.Bushwookie:BAAALgAECgYJDAAAAA==.',
Ca='Caltheas:BAAALgADCgYJCQAAAA==.Cantou:BAABLgAECn8kAAIbAAgJAhQ7AgDCAQAbAAgJAhQ7AgDCAQAAAA==.Captcosmo:BAAALgAECgQJBQAAAA==.Carraig:BAAALgADCgIJAgAAAA==.Carthorís:BAAALgADCggJCAAAAA==.Catameld:BAAALgADCgcJBwAAAA==.Catpaws:BAAALgAECgEJAgAAAA==.',
Ce='Celdios:BAAALgADCgYJCQAAAA==.Celthas:BAAALgAECgYJDQAAAA==.',
Ch='Chernov:BAAALgADCggJCAAAAA==.Chithris:BAAALgAECgQJBAAAAA==.Chodoge:BAACLgAFFH8HAAMRAAMJdQdmBgDHAAARAAMJdQdmBgDHAAASAAIJHQVgBwCTAAAuAAQKfx4ABBEACAmZGOgQAC0CABEACAmZGOgQAC0CABAAAgmGH5RHALsAABIAAgkJH7UvAJkAAAAA.Chonks:BAAALgADCgUJBQAAAA==.Chrisdk:BAAALgAECgYJCwAAAA==.',
Ci='Ciimagi:BAABLgAECn8VAAIUAAcJRhpgYAAaAgAUAAcJRhpgYAAaAgAAAA==.Cirno:BAABLgAECn8eAAIZAAgJ2BtWBgCgAQAZAAgJ2BtWBgCgAQAAAA==.',
Cl='Clamcast:BAABLgAECn8cAAIUAAkJQSKUDABgAwAUAAkJQSKUDABgAwAAAA==.Clíché:BAAALgAECgQJCgAAAA==.',
Co='Combat:BAAALgADCgcJCQAAAA==.Conquêst:BAAALgAECgcJAQAAAA==.Constantino:BAAALgAECgUJCgAAAA==.Coorslite:BAAALgADCgEJAQAAAA==.Copeidan:BAAALgAECgcJCQABLgAECggJHQAFAOMjAA==.Copenfel:BAABLgAECn8dAAIFAAgJ4yO3DQASAwAFAAgJ4yO3DQASAwAAAA==.',
Cr='Crat:BAAALgAECgIJAgAAAA==.Creammachine:BAAALgADCgYJBgABLgAECggJIAAbANQgAA==.Crimpydiff:BAAALgADCgIJAgAAAA==.Crossblêssêr:BAABLgAECn8dAAIcAAgJ5hhHEQAvAgAcAAgJ5hhHEQAvAgAAAA==.',
Cw='Cwaidec:BAAALgADCgMJAwAAAA==.Cwem:BAABLgAECn8WAAIBAAcJnxnsXADMAQABAAcJnxnsXADMAQAAAA==.',
Cy='Cyndeer:BAAALgADCgUJBQAAAA==.',
Da='Daddeigh:BAAALgAECgIJAgAAAA==.Dahlias:BAAALgAECgQJBQAAAA==.Daliel:BAAALgAECgYJDwAAAA==.Danikksky:BAAALgADCgUJBQAAAA==.Daphni:BAAALgADCgcJBwABLgAECggJFAAJAEQVAA==.Darkian:BAAALgAECgUJBgAAAA==.Dasani:BAAALgADCgYJBgABLgAECgUJCAAPAAAAAA==.Daviath:BAAALgAECgQJAQAAAA==.Davinia:BAAALgAECgYJCwAAAA==.',
De='Deaddreams:BAAALgADCgEJAQAAAA==.Deadwait:BAAALgADCgUJBQAAAA==.Dean:BAABLgAECn8eAAIFAAgJ7A6WGgAtAQAFAAgJ7A6WGgAtAQAAAA==.Dedsec:BAAALgADCgEJAQAAAA==.Deel:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Defnotshadow:BAABLgAECn8WAAIFAAcJvxGnGgAsAQAFAAcJvxGnGgAsAQAAAA==.Deithknight:BAAALgAECgcJCgAAAA==.Demna:BAAALgADCggJDQAAAA==.Demonboy:BAAALgAECgEJAQAAAA==.Demoncook:BAABLgAECn8iAAIFAAcJyx4gEgBxAQAFAAcJyx4gEgBxAQAAAA==.Demonroo:BAAALgAECgMJAwAAAA==.Denishath:BAAALgADCgEJAQAAAA==.Depravity:BAAALgAECgIJAgABLgAECggJGQAFAAghAA==.Depression:BAAALgADCgcJCgABLgAFFAcJFgADALQZAA==.Deputymeow:BAAALgAECgYJEwAAAA==.Desalination:BAAALgAECgUJBQABLgAFFAQJCgAJANMYAA==.Designated:BAABLgAECn8YAAIFAAcJLCDwKQBZAgAFAAcJLCDwKQBZAgAAAA==.Designatedh:BAAALgADCgEJAQAAAA==.Designatedm:BAAALgAECgcJDAAAAA==.Destanie:BAAALgAECgYJCwAAAA==.Deusvûlt:BAAALgAECgkJBgAAAA==.Devouler:BAAALgAECgUJCwAAAA==.Dexius:BAAALgADCgcJBwAAAA==.Dezenoth:BAAALgADCgcJBwAAAA==.Deúz:BAABLgAECn8UAAIdAAgJRxjwEAD5AQAdAAgJRxjwEAD5AQAAAA==.',
Di='Diela:BAAALgAECgUJCwAAAA==.Diesel:BAAALgAECgQJCwAAAA==.Diill:BAAALgAECgcJDQAAAA==.Diillz:BAAALgAECgUJBQABLgAECgcJDQAPAAAAAA==.Dikaiosýni:BAAALgADCgYJBgABLgAECgcJFQAdAPgVAA==.',
Dk='Dkandy:BAABLgAECn8fAAINAAgJZSQvAACuAgANAAgJZSQvAACuAgAAAA==.Dkoi:BAABLgAECn8XAAIKAAgJLxwaKwBjAgAKAAgJLxwaKwBjAgAAAA==.Dkykin:BAABLgAECn8dAAIJAAgJYR8iDwCtAgAJAAgJYR8iDwCtAgAAAA==.',
Do='Dogstar:BAAALgADCgkJHgAAAA==.Domïno:BAAALgADCgMJAwAAAA==.Donklord:BAAALgAECgQJEAABLgAECggJIAAbANQgAA==.Doomzy:BAAALgAECgIJAgAAAA==.Dotcalm:BAAALgADCgcJCQAAAA==.Dotsrus:BAAALgADCgMJAwABLgAECggJGAAIAP0WAA==.Downfawl:BAAALgAECgYJEwABLgAFFAMJBwAJACsKAA==.',
Dr='Draaenor:BAAALgADCgEJAQAAAA==.Dracculus:BAAALgADCggJEAAAAA==.Draconblaze:BAAALgAECgQJBgAAAA==.Draginballz:BAAALgAECgYJEQAAAA==.Drakthor:BAAALgAECgQJBQAAAA==.Driam:BAAALgADCgcJCQAAAA==.Drocthyr:BAABLgAECn8UAAIQAAgJZwfRMwAuAQAQAAgJZwfRMwAuAQAAAA==.Droité:BAAALgADCgcJDQAAAA==.Drow:BAAALgADCgQJBAAAAA==.Druf:BAAALgAECgUJBQAAAA==.Druizu:BAAALgAECgEJAQABLgAECgUJDgAPAAAAAA==.Drujitsu:BAAALgAECgIJAgAAAA==.Druknar:BAABLgAECn8eAAIKAAgJNQKWLQDSAAAKAAgJNQKWLQDSAAAAAA==.Drágám:BAAALgAECgEJAQAAAA==.',
Dt='Dtzdrood:BAAALgADCgIJAgAAAA==.',
Du='Dundrin:BAAALgADCgIJAgAAAA==.Durbinbreath:BAAALgAECgQJBQABLgAFFAEJAQAPAAAAAA==.Durbinshalah:BAAALgAFFAEJAQAAAA==.Durf:BAAALgADCgkJEgABLgAECgUJBQAPAAAAAA==.',
Dy='Dyllata:BAAALgAECgMJAwAAAA==.Dyondra:BAAALgAECgYJEQAAAA==.',
['Dä']='Därth:BAAALgADCgEJAQAAAA==.',
Ea='Earthclad:BAAALgAECgIJAgAAAA==.',
Ed='Edah:BAAALgADCgcJDQAAAA==.',
Ee='Eevah:BAABLgAECn8ZAAQGAAcJVx4jGgBrAgAGAAcJVx4jGgBrAgAHAAIJyQiyewBUAAAWAAEJAAAaFgAAAAAAAA==.',
Eg='Eggsonrice:BAAALgAECgcJCwAAAA==.',
El='Elchacal:BAAALgAECgIJAgAAAA==.Elementsmash:BAAALgAECgYJCwAAAA==.Eleventeen:BAABLgAECn8eAAIOAAgJ1Rp/BQAkAgAOAAgJ1Rp/BQAkAgAAAA==.Elihavoc:BAAALgAECgUJBwAAAA==.Elixtempest:BAAALgADCgkJEQAAAA==.Ellariá:BAAALgADCgUJCAAAAA==.Ellmz:BAAALgADCgIJAgAAAA==.Elmz:BAAALgADCgUJBQAAAA==.Elosai:BAAALgAECgYJCwAAAA==.',
En='Enyar:BAAALgAECgkJAQAAAA==.',
Ep='Epicninja:BAAALgAECgkJCAAAAA==.',
Er='Eriis:BAAALgADCgcJBwAAAA==.',
Es='Eseri:BAAALgAECgkJDwAAAA==.',
Ev='Evokeparri:BAAALgAECgMJAwAAAA==.',
Ex='Exarch:BAAALgADCgcJDQAAAA==.Extis:BAAALgADCgcJCAAAAA==.',
Fa='Facesplat:BAAALgADCgUJBwABLgAECgcJAgAPAAAAAA==.Faedeyne:BAAALgADCgYJBgAAAA==.Famouz:BAAALgADCgEJAQAAAA==.Fangaxe:BAACLgAFFH8JAAIdAAQJFBnwAwBHAQAdAAQJFBnwAwBHAQAuAAQKfxoAAh0ACAmxIIIHALACAB0ACAmxIIIHALACAAAA.Farseer:BAABLgAECn8UAAMeAAYJWwzeEQD0AAAeAAYJWwzeEQD0AAAIAAEJxQKCpwAnAAAAAA==.',
Fe='Feniri:BAAALgADCgcJDQAAAA==.Fentrock:BAAALgAECgcJCwAAAA==.Fentshift:BAAALgAECgEJAQAAAA==.Fernãndo:BAAALgADCgQJBQAAAA==.',
Ff='Ffn:BAAALgADCgYJBgABLgAECgcJEwAPAAAAAA==.',
Fi='Fibophy:BAAALgADCgcJBgAAAA==.Fidelius:BAAALgADCgcJDwAAAA==.',
Fl='Floshotmoo:BAABLgAECn8VAAIOAAYJagVTHQDLAAAOAAYJagVTHQDLAAAAAA==.Fluffydog:BAAALgAECgEJAQAAAA==.Fly:BAACLgAFFH8QAAMSAAUJXxAOAwBHAQASAAQJJA4OAwBHAQAQAAUJWg4ZBQBAAQAuAAQKfxwAAxIACQkJHDUEAMsCABIACAnyHjUEAMsCABAABAndFHw7AAIBAAAA.',
Fo='Foxini:BAAALgAECgYJEwAAAA==.',
Fr='Fragii:BAAALgADCgcJBwAAAA==.Fragility:BAAALgAECgYJBgAAAA==.Fraglle:BAAALgAECgEJAQAAAA==.Fragon:BAAALgAECgYJDwAAAA==.Franzen:BAAALgADCgkJCQABLgAFFAEJAQAPAAAAAA==.Frosteenips:BAAALgADCgcJDQAAAA==.Frozenearth:BAAALgADCgEJAQAAAA==.',
Fu='Full:BAAALgADCgcJCwAAAA==.Funkbear:BAAALgADCgEJAQAAAA==.',
Ga='Gafgarion:BAAALgAECgYJBgAAAA==.Garfallen:BAAALgADCgcJCQAAAA==.Gartic:BAAALgAECgYJBgAAAA==.Garzha:BAAALgAECgMJBwAAAA==.Gas:BAAALgAECgMJAwAAAA==.Gaypoc:BAAALgAECgYJDQAAAA==.Gazember:BAAALgADCgcJBwABLgAECgYJFAAcAKAaAA==.',
Ge='Gehenna:BAABLgAECn8VAAIUAAYJ7xvNeQDeAQAUAAYJ7xvNeQDeAQAAAA==.Gezebel:BAAALgAECgQJBwAAAA==.',
Gh='Ghoret:BAAALgADCgIJAgAAAA==.Ghouldamn:BAAALgAECgYJCwAAAA==.Ghðst:BAABLgAECn8WAAIUAAcJJhICHwBbAQAUAAcJJhICHwBbAQAAAA==.',
Gi='Gizzum:BAAALgADCgYJBwABLgAECgYJDwAPAAAAAA==.',
Gl='Gladia:BAAALgAECgYJBwAAAA==.Glaiv:BAAALgADCgEJAQAAAA==.Glarghal:BAABLgAECn8XAAIYAAcJNBNfLgCLAQAYAAcJNBNfLgCLAQAAAA==.Gleepos:BAAALgAECgUJCAAAAA==.Gláurung:BAABLgAECn8YAAIXAAcJgBecCgAlAgAXAAcJgBecCgAlAgAAAA==.',
Go='Gokuu:BAAALgAFFAEJAQAAAA==.Goosily:BAAALgAECgIJAwAAAA==.',
Gr='Grapebevrage:BAABLgAECn8eAAIZAAgJzhjMFgAwAgAZAAgJzhjMFgAwAgAAAA==.Greenbob:BAAALgADCgkJCQAAAA==.Greentouch:BAAALgADCgYJBgAAAA==.Grewt:BAACLgAFFH8HAAIJAAMJKwrOBgDhAAAJAAMJKwrOBgDhAAAuAAQKfyMAAgkACAkfIEAMANQCAAkACAkfIEAMANQCAAAA.Grimwood:BAAALgADCgcJBwAAAA==.Grögin:BAAALgAECgUJCQAAAA==.',
Gu='Gueigh:BAAALgAECgQJBAAAAA==.Guldave:BAAALgADCgEJAQAAAA==.',
Gy='Gyatt:BAAALgAECgYJBwABLgAECgcJEwAPAAAAAA==.',
Ha='Halestormdh:BAAALgAECgQJBwAAAA==.Halløw:BAAALgADCgUJBQAAAA==.Harbin:BAAALgADCgEJAQAAAA==.Harrymason:BAABLgAECn8UAAIfAAcJPBRsEQBeAQAfAAcJPBRsEQBeAQAAAA==.Harvyr:BAABLgAECn8YAAMKAAgJex59QgAFAgAKAAYJBiB9QgAFAgAMAAIJNxUXPwC4AAAAAA==.Hashbrown:BAAALgADCgYJBgAAAA==.Hate:BAAALgAECgEJAQAAAA==.Hathaw:BAAALgAECgUJBgAAAA==.Havyk:BAAALgAECgYJBgAAAA==.Hayhay:BAABLgAECn8ZAAQGAAgJYSLNDwC9AgAGAAgJYSLNDwC9AgAHAAUJ0BUpUgAEAQAWAAEJ3Qv4LwAzAAAAAA==.',
He='Healingdabs:BAAALgADCgMJAwAAAA==.Helghast:BAAALgAECgUJBgAAAA==.Helionn:BAAALgAECgYJDgAAAA==.Herbie:BAAALgADCgMJAwAAAA==.Herja:BAAALgADCgcJCgAAAA==.',
Hi='Hidebound:BAABLgAECn8WAAIgAAgJNguVAQBiAQAgAAgJNguVAQBiAQAAAA==.Hippolyta:BAAALgAECgYJBgAAAA==.',
Ho='Hobgoblinn:BAACLgAFFH8PAAIeAAUJjw4EBQATAQAeAAUJjw4EBQATAQAuAAQKfycAAh4ACQmbGzECAEYCAB4ACQmbGzECAEYCAAAA.Holymackinaw:BAAALgADCgUJBQAAAA==.Honeybees:BAAALgAECggJEgAAAA==.Honeydutchtv:BAAALgADCgEJAQAAAA==.Hopezbanyruu:BAAALgAECgIJAwABLgAECggJIAAJAJ0hAA==.Hopezherbz:BAABLgAECn8gAAMJAAgJnSFqCwDfAgAJAAgJnSFqCwDfAgAOAAEJ3w/BNwAyAAAAAA==.',
Hu='Hubbo:BAAALgAECgQJBwAAAA==.Hugedonut:BAAALgADCgEJAQABLgADCgYJDwAPAAAAAA==.Hughmungus:BAAALgAECgMJAwABLgAECggJFwAJAKUhAA==.Hunzu:BAAALgAECgUJDgAAAA==.',
Hy='Hypojin:BAABLgAECn8cAAIJAAgJfhSfBgCYAQAJAAgJfhSfBgCYAQAAAA==.Hyposelenia:BAAALgADCgcJDAAAAA==.',
['Hó']='Hótsauce:BAAALgADCgIJAgAAAA==.',
Ia='Iamthesun:BAAALgADCgYJCQAAAA==.',
Ic='Iceaged:BAABLgAECn8bAAIUAAgJDyJQHQAAAwAUAAgJDyJQHQAAAwAAAA==.',
Ig='Igneel:BAABLgAECn8dAAMSAAcJsxiBAQCvAQASAAcJsxiBAQCvAQAQAAIJMAhwWQBYAAAAAA==.Igøtya:BAAALgAECgQJBQAAAA==.',
Il='Illos:BAAALgAECgcJEAAAAA==.',
Im='Iminthegame:BAAALgADCgEJAQAAAA==.',
In='Integra:BAAALgAECgYJBgAAAA==.Intervention:BAAALgAECgYJBgAAAA==.',
Ir='Irisvar:BAAALgADCgMJAwAAAA==.Ironcurse:BAAALgAECgEJAQAAAA==.Irondagger:BAAALgADCgYJEQAAAA==.Ironrage:BAAALgAECgIJAgAAAA==.Ironskin:BAAALgAECgUJBQAAAA==.Irontotems:BAAALgADCgYJBgAAAA==.',
It='Itadori:BAAALgAECgUJCAAAAA==.Itheron:BAABLgAECn8hAAIFAAgJjSDwFwDGAgAFAAgJjSDwFwDGAgAAAA==.',
Ja='Jabbathehunt:BAAALgADCgcJDAAAAA==.Jakkin:BAAALgAECgYJCwAAAA==.Jardin:BAAALgADCgcJFwAAAA==.Jasteer:BAAALgAECgMJBgAAAA==.',
Jb='Jbsham:BAAALgAECgIJAgAAAA==.',
Je='Jessbae:BAABLgAECn8fAAMDAAgJfg9OJwB7AQADAAgJfg9OJwB7AQAVAAQJuRobRQABAQAAAA==.',
Jf='Jfac:BAAALgADCgcJCAAAAA==.',
Ji='Jimmypage:BAABLgAECn8gAAMbAAgJ1CASBgCeAgAbAAcJMyUSBgCeAgAOAAYJLR9EBwD0AQAAAA==.',
Jo='Joebon:BAABLgAECn8dAAIhAAgJRBtsIQBIAgAhAAgJRBtsIQBIAgAAAA==.Johnnybgood:BAAALgADCgcJBwAAAA==.',
Jq='Jquellin:BAAALgADCgYJBgAAAA==.',
Jt='Jtrain:BAAALgAECgYJDAAAAA==.',
Ju='Juicedmoose:BAABLgAECn8eAAICAAgJEh6DMAB2AgACAAgJEh6DMAB2AgAAAA==.Junundu:BAAALgAECgkJAQAAAA==.Justahhtank:BAAALgAECgQJBQAAAA==.',
Ka='Kaelissa:BAAALgADCgcJCwAAAA==.Kaelisse:BAAALgADCgcJDAAAAA==.Kaelstrada:BAABLgAECn8ZAAIiAAcJdx/zCwBTAgAiAAcJdx/zCwBTAgAAAA==.Kaendndeydra:BAAALgADCgEJAgAAAA==.Kaennä:BAAALgADCgcJCgAAAA==.Kaladynn:BAAALgADCgIJAgAAAA==.Kalahari:BAAALgAECgQJBgAAAA==.Kao:BAAALgADCgEJAQABLgADCgEJAQAPAAAAAA==.Karazdormu:BAAALgADCgQJBAAAAA==.Karlyta:BAAALgADCgMJAwAAAA==.Karmà:BAAALgADCgMJAwAAAA==.Karzend:BAAALgAECgMJAwAAAA==.Kateri:BAAALgAECgEJAQAAAA==.Kattah:BAAALgAECgYJBwAAAA==.Kavikk:BAAALgAECgQJBAABLgAECgYJDQAPAAAAAA==.',
Ke='Kellbells:BAAALgAECgcJEAAAAA==.Kenchii:BAAALgAECgQJBAAAAA==.Keswickpally:BAAALgAECgYJBgAAAA==.',
Ki='Kindrella:BAABLgAECn8eAAQYAAgJhg+HPABIAQAYAAUJaROHPABIAQAZAAYJ2RBmDQAdAQAcAAQJagfsQgCdAAAAAA==.Kirana:BAAALgADCgUJBQAAAA==.Kirbe:BAAALgAECgYJBgAAAA==.Kitkatdaddy:BAAALgADCgYJDgAAAA==.',
Kl='Klaps:BAAALgADCgMJBgAAAA==.Klassus:BAAALgAECgQJAwAAAA==.',
Kn='Knoctürnal:BAABLgAECn8lAAMCAAgJUSKOBwAHAgACAAgJUSKOBwAHAgANAAYJOhHNCABVAQAAAA==.',
Ko='Kootiekween:BAAALgADCgYJCgAAAA==.Korpskawluh:BAAALgAECgQJBgABLgAECggJHQAEADMPAA==.Kotar:BAAALgAECgYJCgAAAA==.Kotetsu:BAAALgADCgIJAgAAAA==.Koufax:BAAALgAECgkJBwAAAA==.',
Kr='Kravoir:BAACLgAFFH8KAAIQAAUJVxDlDAAxAQAQAAUJVxDlDAAxAQAuAAQKfx4AAhAACAkRH8QNAJkCABAACAkRH8QNAJkCAAAA.Kruelty:BAAALgAECgcJCQAAAA==.',
Ku='Kuleviz:BAAALgAECgMJAwAAAA==.Kuuma:BAAALgADCgUJBQAAAA==.Kuwabara:BAAALgADCgUJBAAAAA==.',
Kw='Kwayludes:BAAALgADCgcJCAAAAA==.',
Ky='Kylisse:BAAALgADCgYJCwAAAA==.',
La='Labrys:BAAALgAECgYJCwAAAA==.Lala:BAAALgAECgEJAQAAAA==.Lanakane:BAAALgADCggJDgAAAA==.Lasagna:BAABLgAECn8fAAIfAAgJuRcqCQATAgAfAAgJuRcqCQATAgAAAA==.Laserturkey:BAAALgADCgUJBQABLgAFFAEJAQAPAAAAAA==.Lastina:BAAALgAECgYJCwAAAA==.Lazroz:BAAALgAECgYJBgAAAA==.',
Le='Leecy:BAAALgAECgYJCAAAAA==.Leisyr:BAAALgADCgEJAQAAAA==.Lex:BAAALgAECgEJAQABLgAECggJFAAJAEQVAA==.Lexxe:BAABLgAECn8UAAMJAAgJRBWNKgCsAQAJAAcJRBWNKgCsAQAOAAEJIhdTxQA+AAAAAA==.',
Li='Lifehack:BAAALgAECgcJEAAAAA==.Lighter:BAAALgADCgUJBQAAAA==.Lilmoist:BAAALgADCgEJAQABLgAECgQJBAAPAAAAAA==.Lilsis:BAAALgAECgYJEAAAAA==.Linstrasza:BAAALgADCgYJBwAAAA==.Linzalina:BAAALgAECgcJCgAAAA==.Littlebear:BAAALgAECgQJBQAAAA==.',
Lo='Locose:BAAALgADCgEJAQAAAA==.Lofn:BAAALgAECgYJEQAAAA==.Loingseach:BAAALgAECgUJCAABLgAECgcJIgAFAMseAA==.Lolrush:BAAALgAECgYJCwABLgAFFAUJDgAEAKQIAA==.Lolyo:BAACLgAFFH8OAAIEAAUJpAh5BQAjAQAEAAUJpAh5BQAjAQAuAAQKfyEAAgQACAnvGQEeABICAAQACAnvGQEeABICAAAA.Lorimore:BAAALgAECgEJAwAAAA==.Lostclaws:BAAALgAECgQJBAAAAA==.Lostdragon:BAAALgAECgYJBgAAAA==.Lovehots:BAAALgADCgcJCAAAAA==.Lovetea:BAABLgAECn8hAAIDAAgJoCSvBAAfAwADAAgJoCSvBAAfAwAAAA==.Loxier:BAABLgAECn8jAAQYAAgJsBM1NwBfAQAYAAcJmAo1NwBfAQAcAAcJmRFtKwA/AQAZAAgJUAdaDAAtAQAAAA==.',
Lu='Lugosh:BAAALgAECgEJAgAAAA==.Lumendevout:BAABLgAECn8ZAAIcAAcJpiDeAgAlAgAcAAcJpiDeAgAlAgAAAA==.',
Ly='Lyall:BAABLgAECn8bAAIJAAgJ6hTOBwB7AQAJAAgJ6hTOBwB7AQAAAA==.Lyrnn:BAABLgAECn8fAAIjAAgJfBzIAgAAAgAjAAgJfBzIAgAAAgAAAA==.',
Ma='Magabite:BAAALgADCgYJCQAAAA==.Mahoragâ:BAAALgAECgcJAQAAAA==.Mainmoon:BAABLgAECn8eAAIVAAgJwxt3AgATAgAVAAgJwxt3AgATAgAAAA==.Managos:BAAALgAECgIJAgAAAA==.Masadeushi:BAAALgAECgUJEwAAAA==.Masou:BAAALgAECgMJAwAAAA==.Mathvell:BAAALgAECgUJBgAAAA==.',
Mc='Mcpaladin:BAAALgAECgUJCgAAAA==.',
Me='Meg:BAAALgAECgcJEwAAAA==.Megthemage:BAAALgAECgIJAgABLgAECgcJEwAPAAAAAA==.Melathice:BAAALgADCggJEAAAAA==.Mellkor:BAAALgAECgEJAQAAAA==.Melsea:BAAALgADCgMJAwAAAA==.Menge:BAAALgAECgMJAwAAAA==.Mercifer:BAAALgAECgQJBQAAAA==.Metharian:BAAALgAECgUJCQAAAA==.',
Mi='Microcredit:BAAALgAECgcJEwAAAA==.Mightduy:BAAALgAECgUJCwAAAA==.Mintandberry:BAAALgADCgYJBgABLgADCggJFwAPAAAAAA==.Missclickies:BAAALgAECgYJCQAAAA==.',
Mk='Mk:BAEALgAECgEJAQABLgAECggJJAAVAAIjAA==.',
Mo='Moistbimbo:BAABLgAECn8UAAIIAAcJDhIxCgCbAQAIAAcJDhIxCgCbAQAAAA==.Moisturize:BAAALgADCgEJAQABLgAECgQJBAAPAAAAAA==.Mommidommi:BAAALgAECgcJCAAAAA==.Monamona:BAAALgAECggJEAAAAA==.Mondaprieta:BAAALgAECgEJAQAAAA==.Monderd:BAAALgADCgUJBQAAAA==.Monjolica:BAAALgADCgkJEAAAAA==.Moonuk:BAAALgAECgUJCwAAAA==.Mordrel:BAAALgADCgYJCQAAAA==.Morgianna:BAAALgAECgYJBgAAAA==.Morik:BAAALgAECgUJCQABLgAECgYJGgAhAOcTAA==.Morrwen:BAAALgAECgIJAgAAAA==.Mourah:BAAALgAECgYJCgAAAA==.Moìst:BAAALgAECgQJBAAAAA==.',
Mu='Mundytwo:BAABLgAECn8UAAMQAAYJIBYQKwBnAQAQAAYJIBYQKwBnAQASAAIJuQGKOgBGAAAAAA==.Muspel:BAAALgAECgQJCQAAAA==.',
['Mí']='Míssusbub:BAAALgAECgUJBQAAAA==.',
Na='Nabyar:BAAALgADCgcJBwAAAA==.Nantusk:BAAALgADCgEJAQAAAA==.Narisa:BAAALgADCgYJBgAAAA==.Nate:BAACLgAFFH8PAAIUAAUJZhu6BQBzAQAUAAUJZhu6BQBzAQAuAAQKfycAAhQACQm2H8wDAIUCABQACQm2H8wDAIUCAAAA.Natinalo:BAAALgAECgEJAQAAAA==.Navric:BAAALgAECgEJAgAAAA==.',
Ne='Necrohealnya:BAAALgAECgYJDwAAAA==.Necrolalacon:BAAALgAECgQJCAAAAA==.Neferpitou:BAAALgADCgEJAQAAAA==.Neff:BAAALgADCgQJBAAAAA==.Neso:BAAALgAECgEJAQAAAA==.Netherburn:BAAALgADCgkJEAAAAA==.Newmoon:BAAALgADCgUJBQAAAA==.Nexkaa:BAAALgADCgIJAgAAAA==.',
Ni='Nianiaa:BAAALgADCgYJAwAAAA==.Niissia:BAAALgADCgMJAwAAAA==.Nikoll:BAAALgADCgkJEgAAAA==.Nimbles:BAAALgAECgMJAwAAAA==.Nimi:BAEBLgAECn8eAAIdAAgJEQ39BgApAQAdAAgJEQ39BgApAQAAAA==.Nio:BAABLgAECn8dAAIEAAgJMw9NMgCJAQAEAAgJMw9NMgCJAQAAAA==.Niraves:BAAALgADCgEJAQAAAA==.Nith:BAAALgAECgUJBQAAAA==.Nithik:BAAALgADCgMJAwAAAA==.',
Nj='Njalulf:BAAALgADCgYJCQAAAA==.',
No='Nonhealer:BAAALgAECggJEAAAAA==.Novamane:BAAALgADCgcJCwABLgAECggJGgAUAJsdAA==.Novå:BAABLgAECn8aAAMUAAgJmx3vRgBjAgAUAAgJmx3vRgBjAgAkAAIJBAtkGABVAAAAAA==.',
Oc='Octy:BAAALgAECgIJAgAAAA==.',
Oi='Oin:BAAALgAECgEJAQAAAA==.',
On='Oneeightytwo:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Onlydans:BAABLgAECn8eAAIlAAgJeQsHCAAoAQAlAAgJeQsHCAAoAQAAAA==.Onlylight:BAAALgADCgMJAwAAAA==.',
Oo='Oogawagaboo:BAAALgADCgYJBgAAAA==.Ooraa:BAAALgADCgUJBgAAAA==.',
Or='Or:BAAALgAECgEJAgABLgADCgEJAQAPAAAAAA==.Orm:BAABLgAECn8eAAIOAAgJThGaRgCHAQAOAAgJThGaRgCHAQAAAA==.Oryine:BAAALgADCgcJCAAAAA==.',
Os='Osamwogru:BAABLgAECn8WAAIIAAgJmBpZJgD6AQAIAAgJmBpZJgD6AQAAAA==.',
Ov='Overlooker:BAAALgADCgUJBgAAAA==.',
Pa='Palanth:BAAALgAECgQJCwAAAA==.Palibro:BAAALgAECgQJBwAAAA==.Palroo:BAAALgADCgEJAQAAAA==.Pandaa:BAAALgAECgMJAwAAAA==.Pannfried:BAAALgADCgQJBAAAAA==.Parripally:BAAALgADCgcJBwABLgAECgMJAwAPAAAAAA==.Pastor:BAABLgAECn8UAAImAAYJMR1KCgDDAQAmAAYJMR1KCgDDAQABLgAECgcJHwAUAI0hAA==.Patrik:BAAALgAECgYJCwAAAA==.Pauladeen:BAAALgAECgYJCQABLgAFFAUJEAASAF8QAA==.',
Pe='Pearlzinha:BAAALgAECgcJEgAAAA==.Penta:BAABLgAECn8eAAIVAAgJEyMFAgAxAgAVAAgJEyMFAgAxAgAAAA==.Peppep:BAAALgAECgQJCAAAAA==.',
Ph='Phin:BAAALgADCgYJBgAAAA==.Phteven:BAAALgAECgcJCwABLgAFFAUJEAASAF8QAA==.Phuga:BAAALgAECgEJAQAAAA==.',
Pl='Plaguethetnk:BAAALgAECgYJBgAAAA==.Plush:BAABLgAECn8cAAIbAAgJ7weKFABqAQAbAAgJ7weKFABqAQAAAA==.',
Po='Ponix:BAAALgAECgMJAwAAAA==.Pootydk:BAAALgAECgIJAgABLgAECgcJFAAUAI8bAA==.Pootyxd:BAABLgAECn8UAAIUAAcJjxsZcQDxAQAUAAcJjxsZcQDxAQAAAA==.Popedave:BAAALgAECgYJEwAAAA==.Portlandian:BAAALgAECgQJBgAAAA==.Poxy:BAAALgAECgMJAwABLgAFFAMJBgAYAHEhAA==.',
Pr='Prathos:BAAALgAECgYJEAAAAA==.Praystationn:BAAALgADCgYJCgAAAA==.Prettyfrosty:BAAALgAECgYJDgAAAA==.',
Ps='Psychroz:BAAALgAECgUJBgAAAA==.Psykolight:BAAALgADCgIJAgAAAA==.Psywing:BAAALgADCgEJAQABLgAFFAMJBgAYAHEhAA==.',
Pu='Puffsummons:BAABLgAECn8fAAMMAAgJqhO+GQB+AQAMAAYJ5hC+GQB+AQAKAAUJjhP0ngAbAQAAAA==.Purify:BAABLgAECn8eAAIYAAgJNBNvJQC+AQAYAAgJNBNvJQC+AQAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrannor:BAAALgAECgYJDgAAAA==.',
Qe='Qez:BAAALgADCgUJBAAAAA==.',
Qu='Quinifer:BAAALgAECgYJDgAAAA==.Quinrawr:BAABLgAECn8VAAIhAAYJrxcNQACkAQAhAAYJrxcNQACkAQAAAA==.',
Ra='Raau:BAAALgAECgEJAQABLgAECggJHgAfAPAdAA==.Rabid:BAAALgADCgMJAwAAAA==.Radamantys:BAABLgAECn8pAAIGAAkJeh/7BQAuAwAGAAkJeh/7BQAuAwAAAA==.Ragnaroc:BAAALgAECgMJBQAAAA==.Raingoat:BAAALgADCgIJAgAAAA==.Raygedemon:BAAALgAECgQJBQAAAA==.Rayleigh:BAAALgADCgEJAQAAAA==.Raymongh:BAAALgADCgEJAQAAAA==.Razdurin:BAAALgAECgUJCgAAAA==.',
Re='Reagor:BAAALgAECgYJBgABLgAECgYJDQAPAAAAAA==.Redspally:BAAALgADCgEJAQAAAA==.Reltircfloda:BAAALgAECgEJAgAAAA==.Retnewb:BAAALgAECgYJEQAAAA==.Revecca:BAAALgAECgQJBAAAAA==.Reyz:BAABLgAECn8YAAIUAAcJriMdEQC5AQAUAAcJriMdEQC5AQAAAA==.Rezear:BAABLgAECn8UAAIFAAcJ2hJfEwBjAQAFAAcJ2hJfEwBjAQAAAA==.',
Rh='Rhetchid:BAAALgADCgcJDAAAAA==.',
Ri='Ribz:BAAALgADCgMJAwAAAA==.Rikez:BAAALgAECgUJBQAAAA==.Rivi:BAAALgAECgYJBgAAAA==.',
Ro='Rokrin:BAAALgAFFAEJAgAAAA==.Rook:BAAALgADCgIJAgAAAA==.Rose:BAAALgAECgMJAwAAAA==.Rotnier:BAAALgAECgIJAgABLgAECggJHQAfAGIiAA==.Rowsdower:BAABLgAECn8fAAIhAAgJKhcjIQBKAgAhAAgJKhcjIQBKAgAAAA==.',
Rt='Rtcowboy:BAABLgAFFH8IAAIEAAMJPxbHBwDwAAAEAAMJPxbHBwDwAAAAAA==.',
Ru='Rubez:BAABLgAECn8VAAIUAAYJmhA9sgB5AQAUAAYJmhA9sgB5AQAAAA==.Rufio:BAAALgADCggJCAABLgAECggJIQACAFUaAA==.Rulia:BAAALgADCgIJAgAAAA==.',
Ry='Ryte:BAAALgADCgUJBQAAAA==.',
Sa='Sacerdos:BAAALgAECgYJBgAAAA==.Safi:BAABLgAECn8VAAMSAAYJZRl9DgDyAQASAAYJZRl9DgDyAQAQAAQJ/gTnDgD+AAAAAA==.Saltherion:BAAALgADCgEJAQAAAA==.Sampink:BAAALgAECgMJAwAAAA==.Sandya:BAAALgAECgYJBwAAAA==.Sanquites:BAAALgAFFAEJAQAAAA==.Sans:BAAALgAECgYJDwAAAA==.Santilecter:BAAALgAECgQJBwAAAA==.',
Sc='Scalebait:BAAALgADCgIJAgAAAA==.Scarletraven:BAAALgAECgEJAQAAAA==.Scenekïng:BAAALgAECgMJBAAAAA==.Scotygrippen:BAABLgAECn8aAAICAAgJiBqyTAANAgACAAgJiBqyTAANAgAAAA==.',
Se='Seelzmonk:BAAALgAECgQJBwAAAA==.Seelzz:BAAALgAECgEJAQAAAA==.Seifer:BAAALgAECgYJEgAAAA==.Selistras:BAABLgAECn8eAAMDAAgJ1hsOBgC1AQADAAgJ1hsOBgC1AQAVAAYJpBnOJwCbAQAAAA==.Sembra:BAABLgAECn8eAAMnAAgJwiCCBQCeAgAnAAgJwiCCBQCeAgABAAIJ6hDCGQFmAAAAAA==.',
Sg='Sgkflame:BAAALgAECgEJAQAAAA==.',
Sh='Shada:BAAALgAECgUJBgAAAA==.Shadowbones:BAAALgADCgIJAgAAAA==.Shadowhoof:BAAALgAECgEJAQAAAA==.Shadø:BAAALgAECgMJBgAAAA==.Shakenblake:BAAALgADCgYJDwAAAA==.Shammÿ:BAABLgAECn8lAAIeAAgJbyADDQDOAgAeAAgJbyADDQDOAgAAAA==.Shayleteo:BAABLgAECn8mAAIUAAcJIiF5DgDTAQAUAAcJIiF5DgDTAQAAAA==.Sheyladh:BAAALgAECgYJDQAAAA==.Shindra:BAAALgAECgIJAgAAAA==.Shininami:BAAALgAECgQJCAAAAA==.Shnitez:BAAALgAECgYJCgAAAA==.Shocktea:BAAALgAECgUJBgAAAA==.Shumalon:BAAALgADCgUJCAABLgAECgUJCwAPAAAAAA==.Shunt:BAAALgADCgQJBQAAAA==.Shuraina:BAAALgAECgYJBwAAAA==.Shuweg:BAABLgAECn8XAAIUAAgJlRlSRQBoAgAUAAgJlRlSRQBoAgAAAA==.Shylachase:BAAALgAECgMJAwAAAA==.',
Si='Sinjar:BAAALgADCgIJAgAAAA==.',
Sk='Skitzofrenya:BAAALgAECgMJAwAAAA==.Skylane:BAAALgAECgYJBwAAAA==.',
Sm='Smashthrashn:BAABLgAECn8gAAIhAAgJARk+AwAbAgAhAAgJARk+AwAbAgAAAA==.',
Sn='Snanth:BAABLgAECn8gAAIUAAgJUhzkDQDaAQAUAAgJUhzkDQDaAQAAAA==.Sneåk:BAAALgADCgEJAQAAAA==.Sniperq:BAAALgAECgEJAQAAAA==.Snurbin:BAAALgADCgUJCQAAAA==.',
So='Sockwater:BAAALgAECgYJDAAAAA==.Solarix:BAAALgADCgQJBQAAAA==.',
Sp='Spalling:BAAALgAECgUJBwAAAA==.Speakeazy:BAAALgAECgYJEwAAAA==.Spelleria:BAAALgADCgcJDQAAAA==.Spinnyme:BAAALgAECgIJAgAAAA==.Sploòp:BAABLgAECn8fAAMKAAgJzB7GAgBzAgAKAAgJzB7GAgBzAgALAAEJAAA2KgBLAAAAAA==.Spoon:BAAALgAECgcJDgAAAA==.',
Sq='Squee:BAAALgAECgYJBwABLgAECgcJDwAPAAAAAA==.',
St='Stalebread:BAAALgADCgcJBwAAAA==.Steelhide:BAAALgAECgUJCgAAAA==.Stilledging:BAABLgAECn8dAAMSAAgJnxDaEQDCAQASAAgJnxDaEQDCAQAQAAQJywk1FwCSAAAAAA==.Stoopadin:BAAALgADCgYJBgABLgAFFAQJCQALAKoOAA==.Stoopedholy:BAABLgAECn8ZAAMcAAYJsxgGBQDCAQAcAAYJsxgGBQDCAQAYAAMJTAZiagCCAAABLgAFFAQJCQALAKoOAA==.Stormrunner:BAAALgADCgUJBQAAAA==.Stubborn:BAABLgAECn8XAAMJAAgJpSGWGQA6AgAJAAcJhCGWGQA6AgAOAAQJ1gk1jQC4AAAAAA==.Stôkes:BAAALgAECgQJCAAAAA==.',
Su='Sugardeady:BAAALgADCgUJBQAAAA==.Suhweg:BAAALgAECgEJAwABLgAECggJFwAUAJUZAA==.Sula:BAAALgADCgIJAgAAAA==.Sulthos:BAAALgADCgcJDQABLgAFFAQJCAAFAH0kAA==.Sumata:BAAALgADCgUJBwABLgAECgcJFQAdAPgVAA==.Sumato:BAABLgAECn8VAAMdAAcJ+BXBBgAwAQAdAAcJ+BXBBgAwAQAhAAIJignHkwBwAAAAAA==.Sunalae:BAAALgADCgcJDgAAAA==.Sunarristia:BAAALgADCgQJBAAAAA==.',
Sy='Sydariel:BAAALgADCgYJBgAAAA==.Syllata:BAACLgAFFH8IAAIOAAQJWxo5BABKAQAOAAQJWxo5BABKAQAuAAQKfxUAAw4ACAkLHbkWAIACAA4ACAkLHbkWAIACAAkAAQl5BS4kAC0AAAAA.Sylvianna:BAAALgAECgQJDQAAAA==.Syssä:BAABLgAECn8UAAQJAAcJZxxBGQA9AgAJAAcJYxxBGQA9AgAbAAQJEA+BIQDPAAAOAAIJJB5nngCOAAABLgADCgMJAwAPAAAAAA==.',
['Sá']='Sátan:BAAALgADCgYJBgAAAA==.',
Ta='Taanwyn:BAAALgAECgIJAgAAAA==.Tacoluv:BAAALgADCgEJAQAAAA==.Tadius:BAAALgADCgQJBAAAAA==.Taladenn:BAAALgADCgEJAQAAAA==.Talahon:BAAALgADCgMJAwABLgAECgMJAwAPAAAAAA==.Taoist:BAAALgAECgYJEQAAAA==.Tautog:BAAALgAECgcJEQAAAA==.',
Tb='Tboo:BAAALgAECgIJAgABLgAECggJHQAcAOYYAA==.',
Te='Teppic:BAABLgAECn8eAAIjAAgJ3hDWBQCVAQAjAAgJ3hDWBQCVAQAAAA==.Teralock:BAABLgAECn8dAAQMAAgJgSTyBQBzAgAMAAYJuSTyBQBzAgAKAAUJryNxEgB9AQALAAIJ4SX4BQBwAAAAAA==.Terawar:BAAALgAECgQJDAAAAA==.',
Th='Thebadthing:BAABLgAECn8WAAICAAYJ4A0KoQA+AQACAAYJ4A0KoQA+AQAAAA==.Thedie:BAAALgAECgcJDQAAAA==.Theegodofwar:BAAALgADCgEJAQAAAA==.Theloudpack:BAACLgAFFH8FAAIBAAMJ5gukCgDzAAABAAMJ5gukCgDzAAAuAAQKfxoAAgEABwkgHA9AACYCAAEABwkgHA9AACYCAAAA.Theri:BAAALgAECgUJBQAAAA==.Therla:BAAALgAECgMJAwAAAA==.Thezarien:BAAALgADCgcJCgAAAA==.Thrallamas:BAAALgADCgIJAgAAAA==.Thrallsgf:BAAALgADCgYJCQAAAA==.Thundron:BAAALgAECggJCAAAAA==.',
Ti='Tibirius:BAAALgADCgIJAgAAAA==.Tigerius:BAAALgADCgcJBwAAAA==.Tim:BAAALgAECgYJCAAAAA==.Tinly:BAAALgADCgMJAwAAAA==.Tiny:BAABLgAECn8cAAITAAgJ0yBRDAC4AgATAAgJ0yBRDAC4AgAAAA==.Tinydingo:BAAALgADCgUJBQAAAA==.Tinytifa:BAABLgAECn8VAAIdAAgJAAlTHgBTAQAdAAgJAAlTHgBTAQAAAA==.Titantelli:BAABLgAECn8bAAIjAAgJfRquEwB6AgAjAAgJfRquEwB6AgAAAA==.',
Tj='Tjd:BAAALgADCgcJBwAAAA==.',
Tr='Trixibell:BAABLgAECn8XAAIGAAgJtxI0DwCJAQAGAAgJtxI0DwCJAQAAAA==.Troutmaster:BAAALgADCgEJAQAAAA==.Trutan:BAAALgAECgEJAQAAAA==.',
Tu='Tumultus:BAAALgAECggJEgAAAA==.Turock:BAAALgAECgUJCQAAAA==.',
Ty='Tylennidar:BAACLgAFFH8HAAIKAAQJDwjVCAA4AQAKAAQJDwjVCAA4AQAuAAQKfx4AAwoABwkqG3ZVAMcBAAoABgkqG3ZVAMcBAAwAAgleEclOAIEAAAAA.Tylethian:BAAALgADCgQJBgAAAA==.Tyrance:BAABLgAECn8VAAIXAAgJFRn+AQDpAQAXAAgJFRn+AQDpAQAAAA==.',
Ud='Udderchaoz:BAAALgADCgMJAwAAAA==.',
Un='Undeadhate:BAAALgAECgIJAgAAAA==.Underhand:BAAALgAECgYJCwAAAA==.Underscore:BAAALgAECgEJAQAAAA==.Unhallowed:BAABLgAECn8fAAMKAAgJdxvUBQAXAgAKAAcJdxvUBQAXAgAMAAIJzgjLVgBqAAAAAA==.Uninterested:BAAALgAECgEJAQAAAA==.Unrl:BAACLgAFFH8LAAIQAAMJDhchCQDyAAAQAAMJDhchCQDyAAAuAAQKfx8AAxAACAmgIBIJAOYCABAACAmgIBIJAOYCABIABgm4E9EbAFIBAAAA.',
Up='Upchuck:BAAALgAECgUJBQAAAA==.',
Ur='Urukickpunch:BAAALgAECgUJBgAAAA==.Urumagus:BAAALgADCgQJBAABLgAECgUJBgAPAAAAAA==.Urupally:BAAALgADCgYJBwAAAA==.Ururok:BAAALgAECgQJBgAAAA==.',
Us='Username:BAAALgADCgIJAgAAAA==.',
Va='Valynoa:BAAALgADCgcJDQAAAA==.Vanic:BAABLgAECn8UAAIKAAcJhRFjEwB1AQAKAAcJhRFjEwB1AQAAAA==.Vanillite:BAAALgAECgcJDgAAAA==.',
Ve='Veeronica:BAAALgADCgMJAwAAAA==.Velthari:BAAALgADCgcJFgAAAA==.Vernon:BAAALgADCgYJBgAAAA==.Versal:BAABLgAECn8YAAMSAAYJxxiGFACgAQASAAYJxxiGFACgAQAQAAYJ5AaEDAAiAQAAAA==.',
Vh='Vhx:BAAALgAECgUJBQAAAA==.',
Vi='Vibeiety:BAAALgADCgEJAgAAAA==.Vindra:BAAALgADCgEJAQAAAA==.Vixelle:BAAALgAECgUJBgAAAA==.',
Vl='Vladdracule:BAAALgAECgQJCAAAAA==.Vladimix:BAAALgADCgUJBQAAAA==.Vladski:BAAALgADCgQJBAAAAA==.',
Vm='Vmjecd:BAABLgAECn8bAAIFAAcJ+xX9TgC5AQAFAAcJ+xX9TgC5AQAAAA==.Vmjecw:BAAALgAECgMJBQAAAA==.',
Vo='Voidspauun:BAABLgAECn8ZAAMFAAcJHhRGIQADAQAFAAcJHhRGIQADAQAmAAMJcg+lIAB/AAAAAA==.Voidthot:BAAALgAECgYJCgAAAA==.Vorty:BAAALgAECgYJDgAAAA==.',
['Vï']='Vïxenô:BAABLgAECn8uAAMIAAgJ/yGMBAAqAwAIAAgJ/yGMBAAqAwAeAAIJQAdDgABGAAAAAA==.',
Wa='Wanamakeóut:BAAALgADCggJDAAAAA==.Warcook:BAAALgAECgIJAwABLgAECgcJIgAFAMseAA==.Warvessel:BAAALgADCgUJBQAAAA==.Warxiez:BAAALgAECgUJCQAAAA==.Washiki:BAAALgADCgcJCgAAAA==.',
Wh='Whirt:BAABLgAECn8aAAIUAAgJFAzuHwBVAQAUAAgJFAzuHwBVAQAAAA==.Whxtxy:BAAALgAECgMJAwAAAA==.',
Wi='Widowmaker:BAABLgAECn8hAAMCAAgJVRqDPQBBAgACAAgJVBqDPQBBAgAiAAYJzhKHIgAtAQAAAA==.Wildstar:BAACLgAFFH8IAAIXAAMJSBlYAQAVAQAXAAMJSBlYAQAVAQAuAAQKfx8AAhcACAmBIUMFALQCABcACAmBIUMFALQCAAAA.Windglider:BAAALgAECgMJAwAAAA==.Wishes:BAAALgAECgUJCQAAAA==.',
Wr='Wrekonize:BAAALgADCgcJDAAAAA==.',
Wt='Wtfnoo:BAAALgAECgcJBwAAAA==.',
Wu='Wurd:BAAALgADCgYJCwAAAA==.',
Xa='Xavilic:BAABLgAECn8ZAAIVAAcJWh8aBADFAQAVAAcJWh8aBADFAQAAAA==.',
Xc='Xcelerator:BAEBLgAECn8dAAIOAAgJLSYhAgB8AwAOAAgJLSYhAgB8AwAAAA==.',
Xe='Xegion:BAAALgADCgkJCQAAAA==.Xentric:BAAALgADCgUJCAAAAA==.',
Xh='Xhav:BAAALgAECgcJDgAAAA==.',
Xx='Xxaraeline:BAAALgAECgMJAwAAAA==.Xxevos:BAAALgADCgQJBAAAAA==.',
Yo='Yonbon:BAAALgAECgUJBgAAAA==.Yourhotnan:BAAALgADCgEJAQAAAA==.',
Yu='Yuhyup:BAABLgAECn8ZAAICAAgJTxGeCgDVAQACAAgJTxGeCgDVAQAAAA==.Yurtireigns:BAAALgADCgcJBwAAAA==.Yuupp:BAAALgAECgEJAQAAAA==.',
Za='Zahlxr:BAABLgAECn8cAAITAAcJah6IFgBdAgATAAcJah6IFgBdAgAAAA==.Zalock:BAAALgADCgQJBAAAAA==.Zapraz:BAAALgAECgYJDQAAAA==.',
Ze='Zeero:BAAALgAECgYJDwAAAA==.Zelbaljin:BAAALgAECgQJBAAAAA==.Zemah:BAAALgAECgUJCQABLgAECggJFgAIAJgaAA==.Zeraphole:BAAALgAECgUJBQAAAA==.Zerolith:BAAALgAECgMJBwAAAA==.',
Zi='Zirt:BAAALgADCgcJBwAAAA==.',
Zm='Zmamaz:BAAALgAECgQJBAAAAA==.',
Zo='Zoidbergmd:BAAALgAECggJEgAAAA==.Zomat:BAAALgAECgYJBgAAAA==.Zomßie:BAAALgAECgYJBgAAAA==.Zoob:BAAALgAECgMJAwABLgAFFAMJBQAOAPsbAA==.Zoobook:BAAALgADCgEJAQABLgAECggJHgAVAMMbAA==.Zorbrix:BAABLgAECn8eAAImAAgJcB08BgA0AgAmAAgJcB08BgA0AgAAAA==.Zoroth:BAAALgAECgUJCAAAAA==.',
Zr='Zrak:BAAALgADCgMJBAAAAA==.',
Zu='Zulgeteb:BAABLgAECn8YAAMeAAYJYRbiDQAjAQAeAAYJYRbiDQAjAQAXAAMJiwB1KQBEAAAAAA==.Zuura:BAABLgAECn8cAAIZAAgJvh02DwCRAgAZAAgJvh02DwCRAgAAAA==.',
Zz='Zztank:BAABLgAECn8fAAInAAgJ0yRjAQBGAwAnAAgJ0yRjAQBGAwAAAA==.',
['Ça']='Çahn:BAAALgADCgEJAgAAAA==.',
['Ün']='Ünit:BAAALgAECgUJBQAAAA==.',
['ßl']='ßlackbear:BAAALgADCgUJBQAAAA==.',
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

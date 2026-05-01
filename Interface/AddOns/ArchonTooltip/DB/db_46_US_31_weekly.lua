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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Shaman-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Druid-Restoration','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Holy','Mage-Frost','Monk-Windwalker','Shaman-Enhancement','Priest-Holy','Priest-Shadow','Mage-Fire','Druid-Feral','Priest-Discipline','Warrior-Protection','DeathKnight-Blood','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','Rogue-Subtlety','Warrior-Arms','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarkan:BAABLgAECn8VAAIBAAcJ1yUyEgABAwABAAcJ1yUyEgABAwAAAA==.',
Ac='Aceboss:BAAALgADCgYJBwAAAA==.Acidburn:BAAALgADCgMJBAAAAA==.',
Ad='Adetal:BAAALgAECgcJDAAAAA==.Adoroth:BAAALgADCgMJAwAAAA==.Adrenaline:BAAALgAECgQJBAAAAA==.',
Ae='Aegisus:BAAALgAECgIJAgAAAA==.Aeiro:BAABLgAECn8fAAICAAgJuhzDNgBcAgACAAgJuhzDNgBcAgAAAA==.Aericura:BAAALgADCggJBwAAAA==.Aetheriel:BAAALgAECgYJEgAAAA==.Aethon:BAAALgADCgcJDQAAAA==.',
Ag='Aggronok:BAABLgAFFH8GAAIDAAMJnQRwFQDIAAADAAMJnQRwFQDIAAAAAA==.',
Ah='Ahnyanka:BAAALgADCgYJBgAAAA==.',
Ai='Aiaria:BAAALgAECgYJDwAAAA==.Airi:BAAALgADCgEJAQAAAA==.Airrin:BAAALgAECgYJCAAAAA==.',
Ak='Akari:BAABLgAECn8xAAMEAAkJrh9MAQA8AwAEAAkJrh9MAQA8AwAFAAYJkA2RTwAFAQAAAA==.Akasha:BAABLgAECn8XAAIGAAgJRiFWJQByAgAGAAgJRiFWJQByAgAAAA==.Akatala:BAABLgAECn8ZAAQHAAgJfhQjJgAiAgAHAAgJfhQjJgAiAgAIAAMJPwtbIgCLAAAJAAEJUgPxlwAfAAAAAA==.Akunda:BAABLgAECn8kAAIKAAkJNBZJKQDqAQAKAAkJNBZJKQDqAQAAAA==.',
Al='Alamaania:BAAALgAECgYJEgAAAA==.Alaterial:BAAALgAECgMJBAAAAA==.Alazara:BAAALgAECgYJBgAAAA==.Allukaa:BAAALgAECgQJBQAAAA==.Aloha:BAACLgAFFH8PAAILAAUJZRrQBwBVAQALAAUJZRrQBwBVAQAuAAQKfx0AAgsACQlMIKILAN0CAAsACQlMIKILAN0CAAAA.Aluriel:BAABLgAECn8lAAQMAAgJjSFZCwBcAgAMAAgJjSFZCwBcAgANAAEJAAAfJABhAAAOAAIJ8hfXXwBPAAAAAA==.',
Am='Ambellìna:BAAALgADCgEJAQAAAA==.Ambellína:BAAALgADCgYJBgAAAA==.Amenrah:BAAALgAECgIJAgAAAA==.Amorisx:BAAALgADCgcJEQAAAA==.',
An='Anarchy:BAABLgAECn8TAAIGAAgJ6SDaHwCSAgAGAAgJ6SDaHwCSAgAAAA==.Androse:BAABLgAECn8XAAIBAAcJWyKXKQB+AgABAAcJWyKXKQB+AgAAAA==.Anjuli:BAAALgAECgEJAQABLgAECgcJHgAHAFceAA==.',
Ar='Arai:BAAALgAECgMJAwAAAA==.Arclîght:BAAALgAECgQJCAAAAA==.Aruj:BAAALgAECgYJDAAAAA==.',
As='Ashkari:BAABLgAECn8WAAMCAAgJ/SBnJgCiAgACAAgJ/SBnJgCiAgAPAAIJABfuEQByAAAAAA==.Astrea:BAABLgAECn8bAAIQAAYJZhgUHACfAQAQAAYJZhgUHACfAQAAAA==.',
At='Athenis:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJBgAAAA==.Aurianna:BAAALgADCgEJAQAAAA==.',
Av='Avolokden:BAAALgAECgYJEgAAAA==.',
Az='Azem:BAAALgADCgUJBQAAAA==.Azmyth:BAACLgAFFH8UAAIBAAYJ7iSZAAAhAgABAAYJ7iSZAAAhAgAuAAQKfyAAAgEACAnUJukEAH0DAAEACAnUJukEAH0DAAAA.Azmythr:BAAALgAFFAEJAQABLgAFFAYJFAABAO4kAA==.Azzaerial:BAAALgAECgQJBAAAAA==.',
Ba='Baez:BAAALgAECgEJAwABLgAECgUJDwARAAAAAA==.Baolin:BAAALgADCgMJAwAAAA==.Bartahk:BAAALgAECgYJBgAAAA==.Bashroot:BAAALgADCgUJBgAAAA==.Bastalion:BAAALgAECgQJBwAAAA==.Baxtersin:BAAALgAECgEJAwAAAA==.Baxtersinho:BAAALgAECgEJAQABLgAECgUJFAACAOAcAA==.Bayz:BAAALgAECgUJCAAAAA==.',
Be='Beamkin:BAAALgADCggJCAAAAA==.Beardedwiz:BAAALgADCgMJAwAAAA==.Bearys:BAAALgADCgMJAwAAAA==.Beeshoney:BAAALgAECgYJCwAAAA==.Beetle:BAAALgAECgIJAgABLgAFFAUJEAASAF8QAA==.Behr:BAAALgAECgMJAwAAAA==.Beighblade:BAAALgADCgQJBgABLgAECggJHQAFADMPAA==.Belgar:BAAALgAECgUJBgAAAA==.Berries:BAAALgADCggJFwAAAA==.Beson:BAAALgADCgQJBAAAAA==.Betræÿer:BAAALgADCgcJFwAAAA==.Beyondthedk:BAAALgAECgYJDgAAAA==.',
Bi='Bigazzdragon:BAABLgAECn8bAAQTAAcJhQYcJgDZAAATAAcJhQYcJgDZAAASAAIJGwE0PwAzAAAUAAIJEgNEIgAuAAAAAA==.Bigilli:BAAALgADCgYJBwAAAA==.Bigkahunas:BAABLgAECn8UAAIHAAcJnRqDNQDYAQAHAAcJnRqDNQDYAQAAAA==.Bigzacky:BAAALgAFFAEJAgAAAA==.Biodiesel:BAAALgAECgYJCgAAAA==.',
Bl='Blackfire:BAAALgAECgIJBAAAAA==.Bladlast:BAABLgAECn8kAAIVAAkJARE3MADAAQAVAAkJARE3MADAAQAAAA==.Blankee:BAACLgAFFH8OAAIWAAUJ3CIQEAB/AQAWAAUJ3CIQEAB/AQAuAAQKfyEAAhYACAl8JY0OAFIDABYACAl8JY0OAFIDAAAA.Blargo:BAACLgAFFH8JAAIQAAQJUx4TCQBvAQAQAAQJUx4TCQBvAQAuAAQKfyIAAhAACAmSJp8BAIsDABAACAmSJp8BAIsDAAAA.Blinkygg:BAAALgADCgYJBwAAAA==.Bloodraven:BAABLgAECn8UAAMHAAYJZhzCOQDHAQAHAAYJZhzCOQDHAQAJAAUJygYTZACvAAAAAA==.Bloodyfinger:BAAALgAECgUJBwABLgAECgcJGQAXAFofAA==.',
Bo='Boat:BAACLgAFFH8MAAIEAAQJbSGBBgCHAQAEAAQJbSGBBgCHAQAuAAQKfyQAAgQACAkrJhkCAG4DAAQACAkrJhkCAG4DAAAA.Bobarker:BAAALgAECgcJDwAAAA==.Bobpet:BAACLgAFFH8TAAMIAAYJUxJJAQCbAQAIAAUJXQ5JAQCbAQAHAAQJJxLMCwAEAQAuAAQKfx4AAwgACAm6H78IAFoCAAgACAk4Hr8IAFoCAAcABAnQHRFYAGABAAAA.Bohdi:BAAALgADCgEJAQAAAA==.Bombisevil:BAAALgAECgMJAwABLgAFFAYJFQATAOkZAA==.Boomins:BAAALgADCgUJBQAAAA==.Boonims:BAAALgADCggJCQAAAA==.Booze:BAAALgAECgMJAwABLgAFFAQJCQAQAFMeAA==.Borbadin:BAAALgAECgEJAQAAAA==.Borgîr:BAABLgAECn8nAAIYAAgJMSEEAQC1AgAYAAgJMSEEAQC1AgAAAA==.Bossee:BAABLgAECn8aAAMZAAcJzxseCQAXAgAZAAcJzxseCQAXAgAaAAIJ+wXYWABYAAABLgAFFAUJDgAWANwiAA==.Bowfdeez:BAAALgADCgQJBgAAAA==.',
Br='Bradadin:BAAALgAECgQJBQAAAA==.Brainlagg:BAABLgAECn8fAAMMAAgJggxLMgBiAQAMAAgJggxLMgBiAQAOAAIJJwS8YQBKAAAAAA==.Brewsly:BAACLgAFFH8QAAIFAAUJyw90DgAgAQAFAAUJyw90DgAgAQAuAAQKfyoAAgUACQmaGVQFAFUCAAUACQmaGVQFAFUCAAAA.Brightleaf:BAAALgAECgcJEQAAAA==.Bruor:BAAALgAECgUJDAAAAA==.Brusque:BAAALgAECgUJCwAAAA==.Bruteus:BAAALgADCgQJBQAAAA==.Bruzthemoose:BAAALgADCgEJAQAAAA==.Brynä:BAABLgAECn8UAAIbAAgJ9AQfBQBzAQAbAAgJ9AQfBQBzAQAAAA==.',
Bu='Bugbug:BAAALgAECgQJBAAAAA==.Buhr:BAABLgAECn8XAAIQAAgJsw1PWgBDAQAQAAgJsw1PWgBDAQAAAA==.Bullhorndh:BAAALgADCgIJAgAAAA==.Bulvie:BAAALgADCgEJAQAAAA==.Burgerpants:BAAALgADCgcJDQABLgAFFAUJDAAGAKUkAA==.Burmiya:BAAALgADCgcJCAAAAA==.Bushwookie:BAAALgAECgYJDAAAAA==.',
Ca='Caelthas:BAAALgADCgIJAgAAAA==.Caltheas:BAAALgADCgYJCQAAAA==.Cantou:BAABLgAECn8mAAIcAAgJAhRsBQDBAQAcAAgJAhRsBQDBAQAAAA==.Captcosmo:BAAALgAECgUJDgAAAA==.Carl:BAAALgAECgIJAgAAAA==.Carraig:BAAALgADCgYJCAAAAA==.Carthorís:BAAALgAECgMJAwAAAA==.Catameld:BAAALgADCgcJBwAAAA==.Catpaws:BAAALgAECgEJAwAAAA==.',
Ce='Celdios:BAAALgADCgYJCQAAAA==.Celthas:BAAALgAECgYJDQAAAA==.',
Ch='Chernov:BAAALgADCggJCAAAAA==.Chithris:BAAALgAECgQJBAAAAA==.Chodoge:BAACLgAFFH8MAAMUAAQJqwmVDAAJAQAUAAQJqwmVDAAJAQASAAIJHQVfBwCTAAAuAAQKfx8ABBQACAmZGOoQACwCABQACAmZGOoQACwCABMAAgmGH59HALsAABIAAgkJH7kvAJkAAAAA.Chonks:BAAALgADCgUJBQAAAA==.Chrisdk:BAAALgAECgYJEQAAAA==.',
Ci='Ciimagi:BAABLgAECn8bAAIWAAcJRhpTYAAaAgAWAAcJRhpTYAAaAgAAAA==.Cirno:BAABLgAECn8fAAIaAAgJPRwADQCzAQAaAAgJPRwADQCzAQAAAA==.',
Cl='Clamcast:BAABLgAECn8dAAIWAAkJkCKZDABgAwAWAAkJkCKZDABgAwAAAA==.Clíché:BAAALgAECgYJEQAAAA==.',
Co='Combat:BAAALgADCgcJCQAAAA==.Conquêst:BAAALgAECgcJAQAAAA==.Constantino:BAAALgAECgYJEAAAAA==.Coorslite:BAAALgADCgEJAQAAAA==.Copeidan:BAAALgAECgcJCQABLgAECgkJIAAGAOoiAA==.Copenfel:BAABLgAECn8gAAIGAAkJ6iK9DQARAwAGAAkJ6iK9DQARAwAAAA==.',
Cr='Crat:BAAALgAECgIJAgAAAA==.Creammachine:BAAALgAECgMJAwABLgAFFAMJBQAcAFARAA==.Crimpydiff:BAAALgADCgIJAgAAAA==.Crossblêssêr:BAABLgAECn8eAAIdAAgJ/xhGEQAvAgAdAAgJ/xhGEQAvAgAAAA==.',
Cw='Cwaidec:BAAALgADCgUJBgAAAA==.Cwem:BAABLgAECn8bAAIBAAgJqhnWKQCbAQABAAgJqhnWKQCbAQAAAA==.',
Cy='Cyndeer:BAAALgADCgUJBQAAAA==.',
Da='Daddeigh:BAAALgAECgYJCAAAAA==.Dahlias:BAAALgAECggJEgAAAA==.Daliel:BAABLgAECn8WAAMaAAcJMAopFwBFAQAaAAcJMAopFwBFAQAdAAIJrwAfPAAqAAAAAA==.Danikksky:BAAALgADCgUJBQAAAA==.Dannikksky:BAAALgAECgYJBgAAAA==.Daphni:BAAALgADCgcJBwABLgAECggJFAALAEQVAA==.Darkian:BAAALgAECgUJBgAAAA==.Dasani:BAAALgADCgYJDAABLgAECgUJDAARAAAAAA==.Daviath:BAAALgAECgQJAQAAAA==.Davinia:BAAALgAECgcJEgAAAA==.',
De='Deaddreams:BAAALgADCgEJAQAAAA==.Deadwait:BAAALgADCgUJBQAAAA==.Dean:BAABLgAECn8jAAIGAAgJgxPTHACHAQAGAAgJgxPTHACHAQAAAA==.Dedsec:BAAALgADCgEJAQAAAA==.Deel:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Defnotshadow:BAABLgAECn8cAAIGAAcJYBlCFADIAQAGAAcJYBlCFADIAQAAAA==.Deithknight:BAAALgAECggJEgAAAA==.Demna:BAAALgADCggJDQAAAA==.Demonboy:BAAALgAECgEJAQAAAA==.Demoncook:BAABLgAECn8tAAIGAAgJcyCTBQCHAgAGAAgJcyCTBQCHAgAAAA==.Demonroo:BAAALgAECgMJAwAAAA==.Denishath:BAAALgADCgEJAQAAAA==.Depravity:BAAALgAECgIJAgABLgAECggJEwAGAOkgAA==.Depression:BAAALgAECgEJAQABLgAFFAgJHAAEAAkeAA==.Deputymeow:BAABLgAECn8UAAIVAAYJkgqhVgAhAQAVAAYJkgqhVgAhAQAAAA==.Desalination:BAAALgAECgUJBQABLgAFFAUJDwALAGUaAA==.Designated:BAABLgAECn8UAAIGAAcJLCD4KQBZAgAGAAcJLCD4KQBZAgAAAA==.Designatedh:BAAALgADCgEJAQAAAA==.Designatedm:BAAALgAECgcJEgAAAA==.Destanie:BAAALgAECgYJCwAAAA==.Deusvûlt:BAAALgAECgkJDQAAAA==.Devouler:BAAALgAECgUJDAAAAA==.Dexius:BAAALgADCgcJBwAAAA==.Dezenoth:BAAALgADCgcJBwAAAA==.Deúz:BAABLgAECn8UAAIeAAgJRxjuEAD5AQAeAAgJRxjuEAD5AQAAAA==.',
Di='Diela:BAAALgAECgUJCwAAAA==.Diesel:BAAALgAECgYJEAAAAA==.Diill:BAABLgAECn8UAAIWAAcJihWURABhAQAWAAcJihWURABhAQAAAA==.Diillz:BAAALgAECgcJDAABLgAECgcJFAAWAIoVAA==.Dikaiosýni:BAAALgADCgYJBgABLgAECggJHQAeAPIVAA==.',
Dk='Dkandy:BAABLgAECn8oAAIPAAkJ0SUGAACAAwAPAAkJ0SUGAACAAwAAAA==.Dkoi:BAABLgAECn8YAAIMAAgJLxwbKwBjAgAMAAgJLxwbKwBjAgAAAA==.Dkykin:BAACLgAFFH8HAAILAAQJ4RNACABSAQALAAQJ4RNACABSAQAuAAQKfyEAAgsACAlhHyIPAK0CAAsACAlhHyIPAK0CAAAA.',
Do='Dogstar:BAAALgADCgkJHgAAAA==.Domïno:BAAALgADCgMJAwAAAA==.Donklord:BAAALgAECgUJEgABLgAFFAMJBQAcAFARAA==.Doomzy:BAAALgAECgIJAgAAAA==.Dotcalm:BAAALgADCgcJCQAAAA==.Dotsrus:BAAALgAECgYJBgAAAA==.Downfawl:BAABLgAECn8cAAMCAAgJNxUJIQDBAQACAAgJNxUJIQDBAQAPAAEJqARUGQAqAAABLgAFFAQJCwALAHUKAA==.',
Dr='Draaenor:BAAALgADCgEJAQAAAA==.Dracculus:BAAALgADCggJEAAAAA==.Draconblaze:BAAALgAECgYJDAAAAA==.Draginballz:BAAALgAECgYJEQAAAA==.Drakthor:BAAALgAFFAMJBAAAAA==.Dreamsteam:BAAALgADCgcJBwAAAA==.Drelina:BAAALgADCgEJAQAAAA==.Driam:BAAALgADCgcJCwAAAA==.Drocthyr:BAABLgAECn8VAAITAAgJNAfYMwAuAQATAAgJNAfYMwAuAQAAAA==.Droité:BAAALgADCgcJDQAAAA==.Drow:BAAALgADCgQJBAAAAA==.Druf:BAAALgAECggJDQAAAA==.Druizu:BAAALgAECgEJAQABLgAECgUJDwARAAAAAA==.Drujitsu:BAAALgAECgIJAgAAAA==.Druknar:BAABLgAECn8mAAIMAAgJrAJrWADoAAAMAAgJrAJrWADoAAAAAA==.Drágám:BAAALgAECgMJBAAAAA==.',
Dt='Dtzdrood:BAAALgADCgIJAgAAAA==.',
Du='Dundrin:BAAALgADCgIJAgAAAA==.Durbinbreath:BAAALgAECgQJBQABLgAFFAEJAQARAAAAAA==.Durbinshalah:BAAALgAFFAEJAQAAAA==.Durf:BAAALgADCgkJEgABLgAECggJDQARAAAAAA==.',
Dy='Dyllata:BAAALgAECgMJAwAAAA==.Dyondra:BAABLgAECn8YAAMQAAcJeBBpIgBuAQAQAAcJeBBpIgBuAQALAAEJjgfciAAnAAAAAA==.',
['Dä']='Därth:BAAALgADCgEJAQAAAA==.',
Ea='Earthclad:BAAALgAECgQJBgAAAA==.',
Ec='Eccentrik:BAAALgADCgMJAwABLgADCgUJCAARAAAAAA==.Ecxentric:BAAALgADCgMJAwABLgADCgUJCAARAAAAAA==.',
Ed='Edah:BAAALgADCgcJDQAAAA==.',
Ee='Eevah:BAABLgAECn8eAAQHAAcJVx4jGgBrAgAHAAcJVx4jGgBrAgAJAAIJyQi3ewBUAAAIAAEJAAD6MwAAAAAAAA==.',
Eg='Eggsonrice:BAAALgAECgcJCwAAAA==.',
El='Elchacal:BAAALgAECgIJAgAAAA==.Elementsmash:BAAALgAECgYJCwAAAA==.Eleventeen:BAABLgAECn8mAAIQAAgJlRuzCQBvAgAQAAgJlRuzCQBvAgAAAA==.Elihavoc:BAAALgAECgUJBwAAAA==.Elixtempest:BAAALgADCgkJEQAAAA==.Ellariá:BAAALgADCgUJCAAAAA==.Ellará:BAAALgADCgMJBgAAAA==.Ellmz:BAAALgADCgcJDQAAAA==.Elmz:BAAALgADCgUJBQAAAA==.Elosai:BAAALgAECgYJEQAAAA==.',
Em='Empressdemon:BAAALgAECgEJAgAAAA==.',
En='Enyar:BAAALgAECgkJAQAAAA==.',
Ep='Epicninja:BAAALgAECgkJCAAAAA==.',
Er='Eriis:BAAALgADCgcJBwAAAA==.',
Es='Eseri:BAAALgAECgkJEQAAAA==.',
Ev='Evokeparri:BAAALgAECgMJAwAAAA==.',
Ex='Exarch:BAAALgAECgQJBAAAAA==.Extis:BAAALgADCgcJCAAAAA==.',
Fa='Facesplat:BAAALgADCgUJBwAAAA==.Faedeyne:BAAALgADCgYJBgAAAA==.Famouz:BAAALgADCgEJAQAAAA==.Fangaxe:BAACLgAFFH8NAAIeAAQJgBx4AwBlAQAeAAQJgBx4AwBlAQAuAAQKfxoAAh4ACAmxIIQHALACAB4ACAmxIIQHALACAAAA.Farseer:BAABLgAECn8VAAMDAAcJewqQIwAEAQADAAcJewqQIwAEAQAKAAEJxQKHpwAnAAAAAA==.',
Fe='Felaequitas:BAAALgAECgUJCAAAAA==.Feniri:BAAALgADCgcJDQAAAA==.Fentrock:BAAALgAECgcJEgAAAA==.Fentshift:BAAALgAECgEJAQAAAA==.Fernãndo:BAAALgADCgQJBQAAAA==.',
Ff='Ffn:BAAALgADCgYJBgABLgAECgcJEwARAAAAAA==.',
Fi='Fibophy:BAAALgADCgcJBgAAAA==.Fidelius:BAAALgADCgcJDwAAAA==.',
Fl='Floshotmoo:BAABLgAECn8dAAIQAAgJHQdvLwAgAQAQAAgJHQdvLwAgAQAAAA==.Fluffydog:BAAALgAECgMJBAAAAA==.Fly:BAACLgAFFH8QAAMSAAUJXxAQAwBHAQASAAQJJA4QAwBHAQATAAUJWg7FDwAyAQAuAAQKfxwAAxIACQkJHDUEAMsCABIACAnyHjUEAMsCABMABAndFIE7AAIBAAAA.',
Fo='Foxini:BAAALgAECgYJEwAAAA==.',
Fr='Fragii:BAAALgADCgcJBwAAAA==.Fragility:BAAALgAECgYJBgAAAA==.Fraglle:BAAALgAECgEJAgAAAA==.Fragon:BAABLgAECn8VAAIUAAYJ+QgEEAD9AAAUAAYJ+QgEEAD9AAAAAA==.Franzen:BAAALgADCgkJCQABLgAFFAEJAgARAAAAAA==.Frosteenips:BAAALgADCgcJDQAAAA==.Frozenearth:BAAALgADCgEJAQAAAA==.',
Fu='Full:BAAALgADCgcJCwAAAA==.Funkbear:BAAALgADCgEJAQAAAA==.',
Ga='Gafgarion:BAAALgAECgcJBwAAAA==.Garfallen:BAAALgADCgcJCQAAAA==.Gartic:BAAALgAECgYJBgAAAA==.Garzha:BAAALgAECgMJBwAAAA==.Gas:BAAALgAECgMJAwAAAA==.Gaypoc:BAAALgAECgYJEwAAAA==.Gazember:BAAALgADCgcJBwABLgAECgYJGgAdAIkbAA==.',
Ge='Gehenna:BAABLgAECn8bAAIWAAYJXRzBeQDeAQAWAAYJXRzBeQDeAQAAAA==.Gezebel:BAAALgAECgQJDQAAAA==.',
Gh='Ghoret:BAAALgADCgIJAgAAAA==.Ghouldamn:BAAALgAECgYJEQAAAA==.Ghðst:BAABLgAECn8eAAIWAAgJ4BEBNgCNAQAWAAgJ4BEBNgCNAQAAAA==.',
Gi='Gizzum:BAAALgADCgYJBwABLgAECgcJHAACAE4XAA==.',
Gl='Gladia:BAAALgAECgYJDQAAAA==.Glaiv:BAAALgADCgEJAQAAAA==.Glarghal:BAABLgAECn8YAAMZAAgJhhFeLgCLAQAZAAcJNBNeLgCLAQAdAAEJyAVWNgA2AAAAAA==.Gleepos:BAAALgAECgUJCAAAAA==.Gláurung:BAABLgAECn8hAAIYAAcJcRrzBADUAQAYAAcJcRrzBADUAQAAAA==.',
Go='Gokuu:BAAALgAFFAEJAgAAAA==.Golokhan:BAAALgADCgIJAgABLgAECgcJHwAfAF0hAA==.Goosily:BAAALgAECgIJAwAAAA==.',
Gr='Grapebevrage:BAABLgAECn8jAAIaAAkJMRfMFgAwAgAaAAkJMRfMFgAwAgAAAA==.Gravyrobbers:BAAALgAECggJCgAAAA==.Greenbob:BAAALgADCgkJCQAAAA==.Greentouch:BAAALgADCgYJBgAAAA==.Grewt:BAACLgAFFH8LAAILAAQJdQr5DAAoAQALAAQJdQr5DAAoAQAuAAQKfyMAAgsACAkfIEAMANQCAAsACAkfIEAMANQCAAAA.Grimwood:BAAALgADCgcJBwAAAA==.Grudel:BAAALgADCgYJBgAAAA==.Grögin:BAAALgAECgcJDwAAAA==.',
Gs='Gseries:BAAALgAECgQJBAAAAA==.',
Gu='Gueigh:BAAALgAECgQJBAAAAA==.Guldave:BAAALgADCgEJAQAAAA==.',
Gy='Gyatt:BAAALgAECgYJBwABLgAECgcJEwARAAAAAA==.',
Ha='Halestormdh:BAAALgAECgYJDQAAAA==.Halløw:BAAALgADCgUJBQAAAA==.Harbin:BAAALgADCgEJAQAAAA==.Harrymason:BAABLgAECn8UAAIgAAcJPBRuEQBeAQAgAAcJPBRuEQBeAQAAAA==.Harvyr:BAABLgAECn8YAAMMAAgJex54QgAFAgAMAAYJBiB4QgAFAgAOAAIJNxUYPwC4AAAAAA==.Hashbrown:BAAALgADCgYJBgAAAA==.Hate:BAAALgAECgEJAQAAAA==.Hathaw:BAAALgAECgUJCwAAAA==.Havyk:BAAALgAECgYJBgAAAA==.Hayhay:BAABLgAECn8eAAQHAAkJQyLODwC9AgAHAAkJQyLODwC9AgAJAAUJ0BUiUgAEAQAIAAQJUBbAGQDnAAAAAA==.',
He='Healingdabs:BAAALgADCgUJBgAAAA==.Helghast:BAAALgAECgUJCwAAAA==.Helionn:BAAALgAECgYJDgAAAA==.Herbie:BAAALgADCgMJAwAAAA==.Herja:BAAALgADCggJCwAAAA==.',
Hi='Hidebound:BAABLgAECn8XAAIhAAgJMwwzBABRAQAhAAgJMwwzBABRAQAAAA==.Hippolyta:BAAALgAECgYJBgAAAA==.Hisouka:BAAALgAECgQJBQABLgAFFAIJBQAHAKcTAA==.',
Ho='Hobgoblinn:BAACLgAFFH8UAAIDAAUJ2xLHCQBAAQADAAUJ2xLHCQBAAQAuAAQKfycAAgMACQmbG84GADwCAAMACQmbG84GADwCAAAA.Honeybees:BAAALgAECggJEgAAAA==.Honeydutchtv:BAAALgAECgMJAwAAAA==.Hopezbanyruu:BAAALgAECgcJCgABLgAECggJIwALAKUhAA==.Hopezherbz:BAABLgAECn8jAAMLAAgJpSFrCwDfAgALAAgJpSFrCwDfAgAQAAEJ3w+IeAAxAAAAAA==.',
Hu='Hubbo:BAAALgAECgQJBwAAAA==.Hugedonut:BAAALgADCgEJAQABLgADCgYJDwARAAAAAA==.Hughmungus:BAAALgAECgMJAwABLgAECggJGQALAKUhAA==.Hunzu:BAAALgAECgUJDwAAAA==.',
Hy='Hypojin:BAABLgAECn8dAAILAAgJfhROEACQAQALAAgJfhROEACQAQAAAA==.Hyposelenia:BAAALgAECgYJBgAAAA==.',
['Hó']='Hótsauce:BAAALgADCgIJAgAAAA==.',
Ia='Iamthesun:BAAALgAECgQJBAAAAA==.',
Ic='Iceaged:BAABLgAECn8cAAIWAAgJICJRHQAAAwAWAAgJICJRHQAAAwAAAA==.',
Ig='Igneel:BAABLgAECn8jAAMSAAgJDBp5AQA4AgASAAgJDBp5AQA4AgATAAIJMAh2WQBYAAAAAA==.Igøtya:BAAALgAECgUJBgAAAA==.',
Il='Illidawn:BAAALgAECgQJBAAAAA==.Illos:BAAALgAECgcJEgAAAA==.',
Im='Imabigboy:BAAALgADCgQJBAAAAA==.Iminthegame:BAAALgADCgEJAQAAAA==.',
In='Integra:BAAALgAECgcJDQAAAA==.Intervention:BAAALgAECgYJBgAAAA==.',
Io='Iokua:BAAALgAECgEJAQAAAA==.',
Ir='Irisvar:BAAALgADCgQJBwAAAA==.Ironcurse:BAAALgAECgUJCAAAAA==.Irondagger:BAAALgAECgMJBAAAAA==.Ironrage:BAAALgAECgIJAgAAAA==.Ironskin:BAAALgAECgcJCgAAAA==.Irontotems:BAAALgAECgEJAgAAAA==.',
Is='Isogi:BAAALgADCgUJCAABLgADCgcJCAARAAAAAA==.',
It='Itadori:BAAALgAECgUJDAAAAA==.Itheron:BAABLgAECn8hAAIGAAkJ0B/0FwDGAgAGAAkJ0B/0FwDGAgAAAA==.Itzdiill:BAAALgAECgQJBAABLgAECgcJFAAWAIoVAA==.',
Ja='Jabbathehunt:BAAALgADCgcJDAAAAA==.Jakkin:BAAALgAECgYJCwAAAA==.Jandis:BAAALgADCgMJBAAAAA==.Jardin:BAAALgADCgcJFwAAAA==.Jasteer:BAAALgAECgMJBgAAAA==.',
Jb='Jbsham:BAAALgAECgIJAgAAAA==.',
Je='Jessbae:BAABLgAECn8kAAMEAAkJ+hGpJwB3AQAEAAgJfg+pJwB3AQAXAAYJFBpnGgASAQAAAA==.',
Jf='Jfac:BAAALgADCgcJCAAAAA==.',
Ji='Jimmypage:BAACLgAFFH8FAAMcAAMJUBExAwALAQAcAAMJUBExAwALAQAQAAEJcBIOJQBGAAAuAAQKfyUAAxwACAmqIRQGAJ4CABwABwktJhQGAJ4CABAABgktH9MTAOkBAAAA.',
Jo='Joebon:BAABLgAECn8eAAIiAAgJuRtqIQBIAgAiAAgJuRtqIQBIAgAAAA==.Johnnybgood:BAAALgADCgcJBwAAAA==.',
Jq='Jquellin:BAAALgADCgYJBgAAAA==.',
Js='Jska:BAAALgAECgYJCAAAAA==.',
Jt='Jtrain:BAABLgAECn8TAAIHAAgJxhuDEAASAgAHAAgJxhuDEAASAgAAAA==.',
Ju='Juicedmoose:BAABLgAECn8jAAICAAkJoyCGEgAmAgACAAkJoyCGEgAmAgAAAA==.Junundu:BAAALgAECgkJAQAAAA==.Justahhtank:BAAALgAECgQJBQAAAA==.',
Ka='Kaelissa:BAAALgADCgcJCwAAAA==.Kaelisse:BAAALgADCgcJDAAAAA==.Kaelstrada:BAABLgAECn8fAAIfAAcJXSFTBAABAgAfAAcJXSFTBAABAgAAAA==.Kaendndeydra:BAAALgADCgEJAgAAAA==.Kaennä:BAAALgADCgcJCgAAAA==.Kaladynn:BAAALgADCgIJAgAAAA==.Kalahari:BAAALgAECgYJDAAAAA==.Kao:BAAALgADCgEJAgABLgAECgYJCQARAAAAAA==.Karazdormu:BAAALgADCgQJBAAAAA==.Karlyta:BAAALgADCgMJAwAAAA==.Karmà:BAAALgADCgMJAwAAAA==.Karzend:BAAALgAECgMJAwAAAA==.Kateri:BAAALgAECgMJBAAAAA==.Kattah:BAAALgAECgYJCwAAAA==.Kavikk:BAAALgAECgYJCQABLgAECgcJDQARAAAAAA==.',
Ke='Kellbells:BAAALgAECgcJEwAAAA==.Kenchii:BAAALgAECgYJCgAAAA==.Keswickpally:BAAALgAECgYJBgAAAA==.',
Kh='Khabib:BAAALgADCgcJBAAAAA==.',
Ki='Kindrella:BAABLgAECn8lAAQaAAgJrg89DgCiAQAaAAgJrg89DgCiAQAZAAUJaROLPABIAQAdAAQJagftQgCdAAAAAA==.Kirana:BAAALgADCgUJBQAAAA==.Kirbe:BAAALgAECgcJCAAAAA==.Kitkatdaddy:BAAALgAECgEJAQAAAA==.',
Kl='Klaps:BAAALgADCgMJBgAAAA==.Klassus:BAAALgAECgQJAwAAAA==.',
Kn='Knoctürnal:BAABLgAECn8nAAMCAAgJjiKqHADTAgACAAgJjiKqHADTAgAPAAYJOhHNCABVAQAAAA==.',
Ko='Kootiekween:BAAALgADCgYJCgAAAA==.Korpskawluh:BAAALgAECgQJBgABLgAECggJHQAFADMPAA==.Kotar:BAAALgAECgYJCgAAAA==.Kotetsu:BAAALgADCgIJAgAAAA==.Koufax:BAAALgAECgkJBwAAAA==.',
Kr='Kravoir:BAACLgAFFH8NAAITAAYJdhDoDAAxAQATAAYJdhDoDAAxAQAuAAQKfx4AAhMACAkRH8YNAJkCABMACAkRH8YNAJkCAAAA.Kruelty:BAAALgAECgcJDQAAAA==.',
Ku='Kuleviz:BAAALgAECgMJAwAAAA==.Kuuma:BAAALgADCgUJBQAAAA==.Kuwabara:BAAALgADCgUJBAAAAA==.',
Kw='Kwayludes:BAAALgADCgcJCAAAAA==.',
Ky='Kylisse:BAAALgADCgYJCwAAAA==.',
La='Labrys:BAAALgAECgcJEgAAAA==.Lala:BAAALgAECgEJAQAAAA==.Lanakane:BAAALgADCggJDgAAAA==.Lasagna:BAABLgAECn8kAAIgAAkJ4hYsCQATAgAgAAkJ4hYsCQATAgAAAA==.Laserturkey:BAAALgADCgkJDgABLgAFFAEJAgARAAAAAA==.Lashana:BAAALgADCgYJBgAAAA==.Lastina:BAAALgAECgcJEgAAAA==.Lazroz:BAAALgAECgYJBgAAAA==.Lazypos:BAAALgADCgEJAQABLgAECgYJDwARAAAAAA==.',
Le='Leecy:BAAALgAECgcJDgAAAA==.Leisyr:BAAALgADCgEJAQAAAA==.Lex:BAAALgAECgEJAQABLgAECggJFAALAEQVAA==.Lexxe:BAABLgAECn8UAAMLAAgJRBWHKgCsAQALAAcJRBWHKgCsAQAQAAEJIhdVxQA+AAAAAA==.',
Li='Lifehack:BAAALgAECgcJEgAAAA==.Lighter:BAAALgADCgUJBQAAAA==.Lilmoist:BAAALgADCgEJAQABLgAECgQJBAARAAAAAA==.Lilsis:BAAALgAECgYJEAAAAA==.Linstrasza:BAAALgADCgYJBwAAAA==.Linzalina:BAAALgAFFAIJAgAAAA==.Littlebear:BAAALgAECgQJBQAAAA==.',
Lo='Locose:BAAALgADCgEJAQAAAA==.Lofn:BAABLgAECn8YAAIVAAcJ9gqsKgD3AAAVAAcJ9gqsKgD3AAAAAA==.Loingseach:BAAALgAECgYJCQABLgAECggJLQAGAHMgAA==.Lolrush:BAAALgAECgYJEQABLgAFFAYJFAAFAO4KAA==.Lolyo:BAACLgAFFH8UAAIFAAYJ7gqCBwBeAQAFAAYJ7gqCBwBeAQAuAAQKfyEAAgUACAnvGQAeABICAAUACAnvGQAeABICAAAA.Lorimore:BAAALgAECgYJCAAAAA==.Lostclaws:BAAALgAECgQJBAAAAA==.Lostdragon:BAAALgAECgYJBgAAAA==.Lovehots:BAAALgADCgcJCAAAAA==.Lovetea:BAABLgAECn8oAAIEAAgJoCT7AQAIAwAEAAgJoCT7AQAIAwAAAA==.Loxier:BAABLgAECn8lAAQZAAgJrhY5NwBfAQAZAAcJmAo5NwBfAQAdAAgJWBVqKwA/AQAaAAgJUAcxGQA1AQAAAA==.',
Lu='Lugosh:BAAALgAECgQJBQAAAA==.Lumendevout:BAABLgAECn8eAAMdAAcJhyGfBAB+AgAdAAcJhyGfBAB+AgAaAAQJ4BP9JgDGAAAAAA==.',
Ly='Lyall:BAABLgAECn8cAAILAAgJOhVBEgB5AQALAAgJOhVBEgB5AQAAAA==.Lyrnn:BAABLgAECn8kAAIjAAkJFxqkAwBjAgAjAAkJFxqkAwBjAgAAAA==.',
Ma='Magabite:BAAALgADCgYJCQAAAA==.Mahoragâ:BAAALgAECgcJAQAAAA==.Mainmoon:BAABLgAECn8lAAIXAAgJyh9WAwCNAgAXAAgJyh9WAwCNAgAAAA==.Managos:BAAALgAECgMJBAAAAA==.Masadeushi:BAABLgAECn8UAAMCAAUJ4BwYgQCAAQACAAUJyhwYgQCAAQAfAAEJ2h5YQABMAAAAAA==.Masou:BAAALgAECgYJCQAAAA==.Mathvell:BAAALgAECgUJBwAAAA==.',
Mc='Mcpaladin:BAAALgAECgcJDQAAAA==.',
Me='Meagle:BAAALgADCgEJAgAAAA==.Meg:BAABLgAECn8YAAMkAAcJhBR8DgC1AQAkAAcJhBR8DgC1AQAiAAMJFgxSkwBxAAAAAA==.Megabonk:BAAALgAECgEJAQAAAA==.Megthemage:BAAALgAECgIJAgABLgAECgcJGAAkAIQUAA==.Melathice:BAAALgADCggJEAAAAA==.Mellkor:BAAALgAECgEJAQAAAA==.Melsea:BAAALgADCgMJAwAAAA==.Menge:BAAALgAECgQJBwAAAA==.Mercifer:BAAALgAECgYJCgAAAA==.Metharian:BAAALgAECgUJCQAAAA==.',
Mi='Microcredit:BAAALgAECgcJEwAAAA==.Mightduy:BAAALgAECgUJCwAAAA==.Mikehum:BAAALgADCgQJBAAAAA==.Mintandberry:BAAALgADCgYJBgABLgADCggJFwARAAAAAA==.Missclickies:BAAALgAECgYJDQAAAA==.Mistweaver:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgEJAQABLgAECggJKQAXAAIjAA==.',
Mo='Moistbimbo:BAABLgAECn8aAAIKAAcJDhJrGwCIAQAKAAcJDhJrGwCIAQAAAA==.Moisturize:BAAALgADCgEJAQABLgAECgQJBAARAAAAAA==.Mommidommi:BAAALgAECggJDgAAAA==.Monamona:BAAALgAECggJEQAAAA==.Mondaprieta:BAAALgAECgEJAQAAAA==.Monderd:BAAALgADCgUJBQAAAA==.Monjolica:BAAALgADCgkJEAAAAA==.Monster:BAAALgAECgEJAQAAAA==.Moonuk:BAAALgAECgUJCwAAAA==.Mordrel:BAAALgADCgYJCQAAAA==.Morgianna:BAAALgAECgYJBgAAAA==.Morik:BAAALgAECgYJDgAAAA==.Morrwen:BAAALgAECgIJAgAAAA==.Mourah:BAAALgAECgYJDgAAAA==.Moìst:BAAALgAECgQJBAAAAA==.',
Mu='Mundytwo:BAABLgAECn8WAAMTAAYJkRYWKwBnAQATAAYJkRYWKwBnAQASAAIJuQGUOgBGAAAAAA==.Muspel:BAAALgAECgQJCgAAAA==.',
['Mí']='Míssusbub:BAAALgAECgUJCAAAAA==.',
Na='Nabyar:BAAALgAECgEJAQAAAA==.Nantusk:BAAALgADCgEJAQAAAA==.Narisa:BAAALgADCgYJBgAAAA==.Nate:BAACLgAFFH8UAAIWAAUJZhsiFwBnAQAWAAUJZhsiFwBnAQAuAAQKfycAAhYACQm5H9wOAGcCABYACQm5H9wOAGcCAAAA.Natinalo:BAAALgAECgEJAQAAAA==.Navric:BAAALgAECgEJAgAAAA==.',
Ne='Necrohealnya:BAAALgAECgYJDwAAAA==.Necrolalacon:BAAALgAECgQJCAAAAA==.Neff:BAAALgADCgQJBQAAAA==.Neso:BAAALgAECgQJBAAAAA==.Nessajd:BAAALgADCgMJAwAAAA==.Netherburn:BAAALgADCgkJEAAAAA==.Newmoon:BAAALgAECgEJAgAAAA==.Nexkaa:BAAALgADCgIJAgAAAA==.',
Ni='Nianiaa:BAAALgADCgYJAwAAAA==.Niissia:BAAALgADCgYJCQAAAA==.Nikoll:BAAALgADCgkJEgAAAA==.Nimbles:BAAALgAECgMJAwAAAA==.Nimi:BAEBLgAECn8fAAIeAAgJDQ6CDwAoAQAeAAgJDQ6CDwAoAQAAAA==.Nio:BAABLgAECn8dAAIFAAgJMw9EMgCJAQAFAAgJMw9EMgCJAQAAAA==.Niraves:BAAALgADCgEJAQAAAA==.Nith:BAAALgAECgUJBQAAAA==.Nithik:BAAALgADCgMJAwAAAA==.',
Nj='Njalulf:BAAALgADCgYJCQAAAA==.',
No='Nonhealer:BAABLgAECn8VAAMKAAgJhwv/IgBPAQAKAAgJhwv/IgBPAQADAAEJ5wSijwAoAAAAAA==.Norisse:BAAALgADCgYJBgAAAA==.Novamane:BAAALgADCgcJCwABLgAECggJGgAWAJsdAA==.Novå:BAABLgAECn8aAAMWAAgJmx3wRgBjAgAWAAgJmx3wRgBjAgAlAAIJBAtkGABVAAAAAA==.',
Oc='Octy:BAAALgAECgIJAgAAAA==.',
Oi='Oin:BAAALgAECgEJAQAAAA==.',
Ol='Oliandia:BAAALgADCgIJAgABLgAECgcJGAAkAIQUAA==.',
On='Oneeightytwo:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Onlydans:BAABLgAECn8fAAImAAgJEQwwEwAVAQAmAAgJEQwwEwAVAQAAAA==.Onlylight:BAAALgADCgQJBwAAAA==.',
Oo='Oogawagaboo:BAAALgADCgYJBgAAAA==.Oonda:BAAALgADCgEJAQAAAA==.Ooraa:BAAALgADCgUJBgAAAA==.',
Or='Or:BAAALgAECgYJCQAAAA==.Orm:BAABLgAECn8fAAIQAAgJgRKeRgCHAQAQAAgJgRKeRgCHAQAAAA==.Oryine:BAAALgADCgcJCQAAAA==.',
Os='Osamwogru:BAABLgAECn8XAAIKAAgJmBpYJgD6AQAKAAgJmBpYJgD6AQAAAA==.',
Ov='Overlooker:BAAALgAECgEJAQAAAA==.',
Pa='Paladone:BAAALgADCgQJCAAAAA==.Palanth:BAAALgAECgQJCwAAAA==.Palibro:BAAALgAECgQJBwAAAA==.Palroo:BAAALgADCgEJAQAAAA==.Pandaa:BAAALgAECgMJAwAAAA==.Pannfried:BAAALgADCgQJBAAAAA==.Parripally:BAAALgADCgcJBwABLgAECgMJAwARAAAAAA==.Pastor:BAABLgAECn8UAAInAAYJMR1MCgDDAQAnAAYJMR1MCgDDAQAAAA==.Patrik:BAAALgAECggJEwAAAA==.Pauladeen:BAAALgAECgYJDQABLgAFFAUJEAASAF8QAA==.',
Pe='Pearlzinha:BAABLgAECn8YAAIJAAcJRAr/DgDaAAAJAAcJRAr/DgDaAAAAAA==.Penta:BAABLgAECn8fAAIXAAgJdCTkBwD8AgAXAAgJdCTkBwD8AgAAAA==.Peppep:BAAALgAECgQJCAAAAA==.',
Ph='Phin:BAAALgADCgYJBgAAAA==.Phteven:BAAALgAECgcJCwABLgAFFAUJEAASAF8QAA==.Phuga:BAAALgAECgYJBwAAAA==.',
Pl='Plaguethetnk:BAAALgAECgYJBgAAAA==.Plush:BAABLgAECn8cAAIcAAgJ7weNFABqAQAcAAgJ7weNFABqAQAAAA==.',
Po='Ponix:BAAALgAECgMJAwAAAA==.Pootydk:BAAALgAECgIJAgABLgAECgcJFAAWAI8bAA==.Pootyxd:BAABLgAECn8UAAIWAAcJjxsOcQDxAQAWAAcJjxsOcQDxAQAAAA==.Popedave:BAABLgAECn8iAAIZAAcJXBGTGQA8AQAZAAcJXBGTGQA8AQAAAA==.Portlandian:BAAALgAECgYJCwAAAA==.Poxy:BAAALgAECgQJBAABLgAFFAQJCgAZAIgkAA==.',
Pr='Prathos:BAABLgAECn8XAAIWAAcJUg6bRABhAQAWAAcJUg6bRABhAQAAAA==.Praystationn:BAAALgADCgYJCgAAAA==.Prettyfrosty:BAABLgAECn8WAAIWAAgJACW1BADzAgAWAAgJACW1BADzAgAAAA==.',
Ps='Psychroz:BAAALgAECgYJDQAAAA==.Psykolight:BAAALgADCgIJAgAAAA==.Psywing:BAAALgADCgEJAQABLgAFFAQJCgAZAIgkAA==.',
Pu='Puffsummons:BAABLgAECn8kAAMOAAkJchS7GQB+AQAOAAYJOBG7GQB+AQAMAAcJFRMdPAA/AQAAAA==.Purify:BAABLgAECn8fAAIZAAgJLhNwJQC+AQAZAAgJLhNwJQC+AQAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrannor:BAABLgAECn8WAAIHAAcJGQo/MQBMAQAHAAcJGQo/MQBMAQAAAA==.',
Qe='Qez:BAAALgADCgUJBAAAAA==.',
Qu='Quinifer:BAABLgAECn8XAAICAAkJ8x3JBgCyAgACAAkJ8x3JBgCyAgAAAA==.Quinrawr:BAABLgAECn8bAAIiAAYJCxm0HABLAQAiAAYJCxm0HABLAQAAAA==.',
Ra='Raau:BAAALgAECgIJAgABLgAECgkJIQAgAGcdAA==.Rabid:BAAALgADCgMJAwAAAA==.Radamantys:BAACLgAFFH8FAAIHAAIJpxOaJwCtAAAHAAIJpxOaJwCtAAAuAAQKfzAAAgcACQnvH+4DAMUCAAcACQnvH+4DAMUCAAAA.Ragnaroc:BAAALgAECgQJBgAAAA==.Raingoat:BAAALgADCgIJAgAAAA==.Raygedemon:BAAALgAECgQJBQAAAA==.Rayleigh:BAAALgADCgEJAQAAAA==.Raymongh:BAAALgADCgEJAQAAAA==.Razdurin:BAAALgAECgUJCwAAAA==.',
Re='Reagor:BAAALgAECgcJDQAAAA==.Redspally:BAAALgADCgEJAQAAAA==.Regenerate:BAAALgAFFAIJAgAAAA==.Reltircfloda:BAAALgAECgQJBgAAAA==.Retnewb:BAABLgAECn8YAAIoAAcJmiJ1AwAsAgAoAAcJmiJ1AwAsAgAAAA==.Revecca:BAAALgAECgQJBAAAAA==.Reyz:BAABLgAECn8gAAIWAAgJJSRpCQCnAgAWAAgJJSRpCQCnAgAAAA==.Rezear:BAABLgAECn8UAAMnAAcJUhxlBACuAQAnAAYJ4x1lBACuAQAGAAcJ2hI5bwBWAQAAAA==.',
Rh='Rhetchid:BAAALgAECgEJAQAAAA==.',
Ri='Ribz:BAAALgADCgMJAwAAAA==.Rikez:BAAALgAECgYJCwAAAA==.Rivi:BAAALgAECgYJDAAAAA==.',
Ro='Rokrin:BAAALgAFFAIJAwAAAA==.Rook:BAAALgADCgIJAgAAAA==.Rose:BAAALgAECgMJAwAAAA==.Rotnier:BAAALgAFFAIJAgAAAA==.Rowsdower:BAABLgAECn8kAAIiAAkJyRckIQBKAgAiAAkJyRckIQBKAgAAAA==.',
Rt='Rtcowboy:BAABLgAFFH8LAAIFAAMJ2hw1EQD0AAAFAAMJ2hw1EQD0AAAAAA==.',
Ru='Rubez:BAABLgAECn8dAAIWAAgJtRAILwCnAQAWAAgJtRAILwCnAQAAAA==.Rufio:BAAALgAECgIJAgABLgAECggJKQACAIMcAA==.Rulia:BAAALgADCgIJAgAAAA==.',
Ry='Ryte:BAAALgADCgcJEAAAAA==.',
Sa='Sacerdos:BAAALgAECgYJBgAAAA==.Safi:BAABLgAECn8XAAMSAAcJhBh9DgDyAQASAAYJZRl9DgDyAQATAAUJqBImGAA8AQAAAA==.Saltherion:BAAALgADCgEJAQAAAA==.Sampink:BAAALgAFFAIJAgAAAA==.Sandya:BAAALgAECgYJBwAAAA==.Sanguiniuss:BAAALgADCgUJBQAAAA==.Sanquites:BAAALgAFFAIJAwAAAA==.Sans:BAABLgAECn8VAAIKAAYJ6ROBIQBZAQAKAAYJ6ROBIQBZAQAAAA==.Santilecter:BAAALgAECgQJCwAAAA==.',
Sc='Scalebait:BAAALgADCgIJAgAAAA==.Scarletraven:BAAALgAECgEJAQAAAA==.Scenekïng:BAAALgAECgMJBAAAAA==.Scotygrippen:BAABLgAECn8aAAICAAgJiBqpTAANAgACAAgJiBqpTAANAgAAAA==.Scyops:BAABLgAECn8dAAIiAAYJPx0mMADuAQAiAAYJPx0mMADuAQAAAA==.',
Se='Seelzmonk:BAAALgAECgQJBwAAAA==.Seelzz:BAAALgAECgEJAQAAAA==.Seifer:BAABLgAECn8YAAIfAAYJhBZjEAARAQAfAAYJhBZjEAARAQAAAA==.Selistras:BAABLgAECn8fAAMEAAgJuRysDgC8AQAEAAgJuRysDgC8AQAXAAYJpBnRJwCbAQAAAA==.Sembra:BAABLgAECn8lAAMoAAgJVCEiAgBzAgAoAAgJVCEiAgBzAgABAAIJ6hDNGQFmAAAAAA==.',
Sg='Sgkflame:BAAALgAECgEJAQAAAA==.',
Sh='Shada:BAAALgAECgUJCQAAAA==.Shadowbones:BAAALgADCgIJAgAAAA==.Shadowhoof:BAAALgAECgMJBAAAAA==.Shadø:BAAALgAECgMJBgAAAA==.Shakenblake:BAAALgADCgYJDwAAAA==.Shammÿ:BAACLgAFFH8HAAIDAAQJFwm+DwAFAQADAAQJFwm+DwAFAQAuAAQKfykAAgMACQlSHwcNAM4CAAMACQlSHwcNAM4CAAAA.Shayleteo:BAACLgAFFH8IAAIWAAQJOwxqKAAuAQAWAAQJOwxqKAAuAQAuAAQKfyYAAhYABwnQIRw3AJgCABYABwnQIRw3AJgCAAAA.Sheyladh:BAAALgAECgYJDQAAAA==.Shindra:BAAALgAECgIJAgAAAA==.Shininami:BAAALgAECgQJCAAAAA==.Shnitez:BAAALgAECgYJCgAAAA==.Shocktea:BAAALgAECgUJCwAAAA==.Shumalon:BAAALgADCgUJCAABLgAECgUJDAARAAAAAA==.Shunt:BAAALgADCgQJBQAAAA==.Shuraina:BAAALgAECgcJDgAAAA==.Shuweg:BAABLgAECn8XAAIWAAgJlRlPRQBoAgAWAAgJlRlPRQBoAgAAAA==.Shylachase:BAAALgAECgUJCAAAAA==.',
Si='Sinjar:BAAALgADCgIJAgAAAA==.',
Sk='Skitzofrenya:BAAALgAECgMJAwAAAA==.Skybreaker:BAAALgAECgUJBwABLgAFFAQJCQABAA4OAA==.Skylane:BAAALgAECgYJDAAAAA==.',
Sm='Smashthrashn:BAABLgAECn8nAAIiAAgJJxtoBgBNAgAiAAgJJxtoBgBNAgAAAA==.Smittywerben:BAAALgAECgYJBgAAAA==.',
Sn='Snanth:BAABLgAECn8nAAIWAAgJDSF8DACAAgAWAAgJDSF8DACAAgAAAA==.Sneåk:BAAALgADCgEJAQAAAA==.Sniperq:BAAALgAECgEJAQAAAA==.Snurbin:BAAALgADCgUJCQAAAA==.',
So='Sockwater:BAABLgAECn8YAAMDAAcJcAgTUAAHAQADAAcJxgYTUAAHAQAYAAUJoweHDwDXAAAAAA==.Solarix:BAAALgADCgUJBgAAAA==.',
Sp='Spalling:BAAALgAECgcJDgAAAA==.Speakeazy:BAAALgAECgYJEwAAAA==.Spelleria:BAAALgADCgcJDgAAAA==.Spinnyme:BAAALgAECgIJAgAAAA==.Sploòp:BAABLgAECn8gAAMMAAkJQxy6BQC3AgAMAAkJQxy6BQC3AgANAAEJAAA4KgBLAAAAAA==.Spoon:BAABLgAECn8WAAIWAAgJISGSCwCLAgAWAAgJISGSCwCLAgAAAA==.',
Sq='Squee:BAAALgAECgYJBwABLgAECgcJEgARAAAAAA==.',
St='Stalebread:BAAALgADCgcJBwAAAA==.Steelhide:BAAALgAECgYJEAAAAA==.Stilledging:BAABLgAECn8dAAMSAAgJnxDcEQDCAQASAAgJnxDcEQDCAQATAAQJ0ggeNACLAAAAAA==.Stoopadin:BAAALgADCgYJBgABLgAFFAUJDQANAKoOAA==.Stoopedholy:BAABLgAECn8hAAMdAAcJyBecCQD2AQAdAAcJyBecCQD2AQAZAAMJTAZhagCCAAABLgAFFAUJDQANAKoOAA==.Stormrunner:BAAALgADCgUJBQAAAA==.Stubborn:BAABLgAECn8ZAAQLAAgJpSGUGQA6AgALAAcJhCGUGQA6AgAQAAQJ1gk2jQC4AAAgAAEJDxzwGQBQAAAAAA==.Stôkes:BAABLgAECn8UAAIWAAYJ2AryXwAcAQAWAAYJ2AryXwAcAQAAAA==.',
Su='Sugardeady:BAAALgADCgUJBQAAAA==.Suhweg:BAAALgAECgEJAwABLgAECggJFwAWAJUZAA==.Sula:BAAALgADCgIJAgAAAA==.Sulthos:BAAALgADCgcJDQABLgAFFAUJDAAGAKUkAA==.Sumata:BAAALgADCgUJBwABLgAECggJHQAeAPIVAA==.Sumato:BAABLgAECn8dAAMeAAgJ8hUxBwDQAQAeAAgJ8hUxBwDQAQAiAAIJignYkwBwAAAAAA==.Sunalae:BAAALgADCgcJDgAAAA==.Sunarristia:BAAALgADCgQJBAAAAA==.',
Sy='Sydariel:BAAALgADCgYJBgAAAA==.Syllata:BAACLgAFFH8JAAIQAAUJhxjaBwCDAQAQAAUJhxjaBwCDAQAuAAQKfxUAAxAACAkLHbcWAIACABAACAkLHbcWAIACAAsAAQl5BZJJAC0AAAAA.Sylvianna:BAAALgAECgQJEQAAAA==.Syssä:BAABLgAECn8UAAQLAAcJZxw/GQA9AgALAAcJYxw/GQA9AgAcAAQJEA+EIQDPAAAQAAIJJB51ngCOAAABLgADCgMJAwARAAAAAA==.',
['Sá']='Sátan:BAAALgADCgYJBgAAAA==.',
Ta='Taanwyn:BAAALgAECgMJBAAAAA==.Tacoluv:BAAALgAECgMJAwAAAA==.Tadius:BAAALgADCgQJBAAAAA==.Taladenn:BAAALgADCgEJAQAAAA==.Talahon:BAAALgADCgMJAwABLgAECgUJCQARAAAAAA==.Taoist:BAABLgAECn8UAAIUAAYJZhTJEADwAAAUAAYJZhTJEADwAAAAAA==.Tautog:BAAALgAECgcJEQAAAA==.',
Tb='Tboo:BAAALgAECgIJAgABLgAECggJHgAdAP8YAA==.',
Te='Teppic:BAABLgAECn8mAAIjAAgJUBNmCQDVAQAjAAgJUBNmCQDVAQAAAA==.Teralock:BAABLgAECn8fAAQOAAgJgSTyBQBzAgAOAAcJHx/yBQBzAgAMAAUJryPHLAB5AQANAAIJ4SWcCwBvAAAAAA==.Terawar:BAAALgAECgQJDQAAAA==.',
Th='Thebadthing:BAABLgAECn8aAAICAAYJYxLnXADvAAACAAYJYxLnXADvAAAAAA==.Thedie:BAAALgAECgcJDQAAAA==.Theegodofwar:BAAALgADCgEJAQAAAA==.Theloudpack:BAACLgAFFH8JAAIBAAQJDg6BEgA7AQABAAQJDg6BEgA7AQAuAAQKfxsAAgEACAl1GgpAACYCAAEACAl1GgpAACYCAAAA.Theorem:BAAALgAECgEJAQABLgAECggJEwAGAOkgAA==.Theri:BAAALgAECgUJBQAAAA==.Therla:BAAALgAECgUJCQAAAA==.Thezarien:BAAALgADCgcJCgAAAA==.Thrallamas:BAAALgADCgIJAgAAAA==.Thrallsgf:BAAALgADCgYJCQAAAA==.Thundron:BAAALgAECggJEAAAAA==.',
Ti='Tien:BAAALgAECgMJAgAAAA==.Tigerius:BAAALgADCgcJBwAAAA==.Tim:BAAALgAECgYJCAAAAA==.Tinly:BAAALgADCgMJAwAAAA==.Tiny:BAABLgAECn8dAAIVAAgJLSNPDAC4AgAVAAgJLSNPDAC4AgAAAA==.Tinydingo:BAAALgADCgUJBQAAAA==.Tinytifa:BAABLgAECn8VAAIeAAgJAAlaHgBTAQAeAAgJAAlaHgBTAQAAAA==.Titantelli:BAABLgAECn8cAAIjAAgJfRqsEwB6AgAjAAgJfRqsEwB6AgAAAA==.',
Tj='Tjd:BAAALgADCgcJBwAAAA==.',
Tr='Trixibell:BAABLgAECn8YAAIHAAgJ4xPnIQCXAQAHAAgJ4xPnIQCXAQAAAA==.Troutmaster:BAAALgAECgEJAQAAAA==.Truta:BAAALgAECgMJAwAAAA==.Trutan:BAAALgAECgEJAQAAAA==.',
Ts='Tsoni:BAAALgAECgQJBAAAAA==.',
Tu='Tumultus:BAAALgAECggJEgAAAA==.Turock:BAAALgAECgYJDwAAAA==.',
Ty='Tylennidar:BAACLgAFFH8JAAIMAAUJbgmZHgAoAQAMAAUJbgmZHgAoAQAuAAQKfx4AAwwABwkqG3dVAMcBAAwABgkqG3dVAMcBAA4AAgleEdBOAIEAAAAA.Tylethian:BAAALgADCgQJBgAAAA==.Tyrance:BAABLgAECn8dAAIYAAgJAB6CAgBEAgAYAAgJAB6CAgBEAgAAAA==.',
Ud='Udderchaoz:BAAALgADCgMJAwAAAA==.',
Un='Undeadhate:BAAALgAECgIJAgAAAA==.Underhand:BAAALgAECgYJCwAAAA==.Underscore:BAAALgAECgEJAQAAAA==.Unhallowed:BAABLgAECn8oAAMMAAkJIRkZCwBfAgAMAAgJIRkZCwBfAgAOAAIJzgjUVgBqAAAAAA==.Uninterested:BAAALgAECgEJAQAAAA==.Unrl:BAACLgAFFH8PAAITAAQJWBQTDQBGAQATAAQJWBQTDQBGAQAuAAQKfyIAAxMACAmhIBUJAOYCABMACAmhIBUJAOYCABIABgm4E9kbAFIBAAAA.',
Up='Upchuck:BAAALgAECgUJCgAAAA==.',
Ur='Urukickpunch:BAAALgAECgUJCwAAAA==.Urumagus:BAAALgADCgYJCgABLgAECgUJCwARAAAAAA==.Urupally:BAAALgADCgcJDgAAAA==.Ururok:BAAALgAECgQJBwAAAA==.',
Us='Username:BAAALgADCgIJAgAAAA==.',
Va='Valynoa:BAAALgADCgcJDQAAAA==.Vanic:BAABLgAECn8aAAIMAAcJqxWlJACeAQAMAAcJqxWlJACeAQAAAA==.Vanillite:BAABLgAECn8UAAIWAAcJkRRQMgCbAQAWAAcJkRRQMgCbAQAAAA==.',
Ve='Veeronica:BAAALgADCgMJAwAAAA==.Velthari:BAAALgADCgcJHQAAAA==.Verionas:BAAALgAECgEJAQABLgAECggJGAAMAHseAA==.Vernon:BAAALgADCgYJBgAAAA==.Versal:BAABLgAECn8YAAMSAAYJxxiJFACgAQASAAYJxxiJFACgAQATAAYJ+g1eHQAVAQAAAA==.Versinnia:BAAALgADCgMJBAAAAA==.',
Vh='Vhx:BAAALgAECgYJCwAAAA==.',
Vi='Vibeiety:BAAALgADCgEJAgAAAA==.Vindra:BAAALgADCgEJAQAAAA==.Vixelle:BAAALgAECgUJCwAAAA==.',
Vl='Vladdracule:BAABLgAECn8VAAIjAAYJ+A+dEwBBAQAjAAYJ+A+dEwBBAQAAAA==.Vladimix:BAAALgADCgUJBQAAAA==.Vladski:BAAALgADCgQJBAAAAA==.',
Vm='Vmjecd:BAABLgAECn8bAAIGAAcJ+xX7TgC5AQAGAAcJ+xX7TgC5AQAAAA==.Vmjecw:BAAALgAECgQJCQAAAA==.',
Vo='Voidspauun:BAABLgAECn8fAAMGAAcJaBXuKgA5AQAGAAcJaBXuKgA5AQAnAAMJcg+jIAB/AAAAAA==.Voidthot:BAAALgAECgYJCgAAAA==.Vorty:BAABLgAECn8WAAMBAAgJFBqwFQANAgABAAgJFBqwFQANAgAoAAIJQwqOQAA7AAAAAA==.',
['Vï']='Vïxenô:BAABLgAECn82AAMKAAkJESOLBAAqAwAKAAkJESOLBAAqAwADAAIJQAdXgABGAAAAAA==.',
Wa='Wanamakeóut:BAAALgADCggJDAAAAA==.Warcook:BAAALgAECgMJBgABLgAECggJLQAGAHMgAA==.Warvessel:BAAALgADCgUJBQAAAA==.Warxiez:BAAALgAECgUJDAAAAA==.Washiki:BAAALgADCgcJCgAAAA==.',
Wh='Whirt:BAABLgAECn8bAAIWAAgJdAyiTABKAQAWAAgJdAyiTABKAQAAAA==.Whxtxy:BAAALgAECgMJAwAAAA==.',
Wi='Widowmaker:BAABLgAECn8pAAMCAAgJgxyJPQBBAgACAAgJVBqJPQBBAgAfAAgJ1hRnDwAfAQAAAA==.Wildstar:BAACLgAFFH8JAAIYAAQJYBM5AwACAQAYAAQJYBM5AwACAQAuAAQKfx8AAhgACAmBIUUFALQCABgACAmBIUUFALQCAAAA.Windglider:BAAALgAECgMJAwAAAA==.Wishes:BAAALgAECgYJDwAAAA==.',
Wr='Wrekonize:BAAALgADCgcJDAAAAA==.',
Wt='Wtfnoo:BAAALgAECgcJBwAAAA==.',
Wu='Wurd:BAAALgADCgYJCwAAAA==.',
Xa='Xavilic:BAABLgAECn8ZAAIXAAcJWh96EAB5AgAXAAcJWh96EAB5AgAAAA==.',
Xc='Xcelerator:BAECLgAFFH8FAAIQAAMJrx5TEgALAQAQAAMJrx5TEgALAQAuAAQKfyMAAhAACAk1JiMCAHwDABAACAk1JiMCAHwDAAAA.',
Xe='Xegion:BAAALgADCgkJCQAAAA==.Xentric:BAAALgADCgUJCAAAAA==.',
Xh='Xhav:BAAALgAECgcJDgAAAA==.Xhavik:BAAALgAECgcJBwAAAA==.',
Xx='Xxaraeline:BAAALgAECgMJAwAAAA==.Xxevos:BAAALgADCgQJBAAAAA==.',
Yo='Yonbon:BAAALgAECgUJCwAAAA==.Yourhotnan:BAAALgADCgEJAQAAAA==.',
Yu='Yuhyup:BAABLgAECn8bAAICAAgJWBNkHwDLAQACAAgJWBNkHwDLAQAAAA==.Yurtireigns:BAAALgADCgcJBwAAAA==.Yuupp:BAAALgAECgIJAgAAAA==.',
Za='Zahlxr:BAABLgAECn8iAAIVAAcJeh+yCwAcAgAVAAcJeh+yCwAcAgAAAA==.Zallafiel:BAAALgAECgYJBgAAAA==.Zalock:BAAALgAECgMJAwAAAA==.Zapraz:BAAALgAECgYJDgABLgAECgcJDQARAAAAAA==.',
Ze='Zeero:BAABLgAECn8WAAIVAAYJQR85CwAjAgAVAAYJQR85CwAjAgAAAA==.Zelbaljin:BAAALgAECgQJBAAAAA==.Zemah:BAAALgAECgUJCwABLgAECggJFwAKAJgaAA==.Zeraphole:BAAALgAECgUJBQAAAA==.Zerolith:BAAALgAECgMJBwAAAA==.',
Zi='Zirt:BAAALgADCgcJBwAAAA==.',
Zm='Zmamaz:BAAALgAECgYJCgAAAA==.',
Zo='Zoidbergmd:BAABLgAECn8aAAMNAAkJhBHwBABAAQANAAcJhQ/wBABAAQAMAAgJRwzCRAAjAQAAAA==.Zomat:BAAALgAECgYJCgAAAA==.Zomßie:BAAALgAECgYJBwAAAA==.Zoob:BAAALgAECgQJBwABLgAFFAQJCQAQAFMeAA==.Zoobook:BAAALgADCgEJAQABLgAECggJJQAXAMofAA==.Zorbrix:BAABLgAECn8fAAInAAgJcB06BgA0AgAnAAgJcB06BgA0AgAAAA==.Zoroth:BAAALgAECgUJCAAAAA==.',
Zr='Zrak:BAAALgADCgUJBwAAAA==.',
Zu='Zulgeteb:BAABLgAECn8ZAAMDAAcJSRXzFwBTAQADAAcJSRXzFwBTAQAYAAMJiwB0KQBEAAAAAA==.Zuura:BAACLgAFFH8FAAMaAAMJXRBiDAD7AAAaAAMJXRBiDAD7AAAdAAEJ1wF7GwBBAAAuAAQKfyAAAhoACAlTHzcPAJECABoACAlTHzcPAJECAAAA.',
Zz='Zztank:BAABLgAECn8kAAIoAAkJKiVlAQBGAwAoAAkJKiVlAQBGAwAAAA==.',
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

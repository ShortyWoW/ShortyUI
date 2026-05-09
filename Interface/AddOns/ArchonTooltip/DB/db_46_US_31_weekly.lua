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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Shaman-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Paladin-Holy','Mage-Frost','Monk-Windwalker','Shaman-Enhancement','Priest-Shadow','Mage-Fire','Druid-Feral','DemonHunter-Vengeance','Priest-Discipline','Warrior-Protection','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','Rogue-Subtlety','Warrior-Arms','DemonHunter-Havoc','Paladin-Protection',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarkan:BAABLgAECn8VAAIBAAcJ1yUxEgABAwABAAcJ1yUxEgABAwAAAA==.',
Ac='Aceboss:BAAALgAECgEJAQAAAA==.Acidburn:BAAALgADCgMJBAAAAA==.',
Ad='Adetal:BAAALgAECggJDwAAAA==.Adoroth:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgQJBAAAAA==.',
Ae='Aegisus:BAAALgAECgIJAgAAAA==.Aeiro:BAABLgAECn8jAAICAAkJ4B2/GwAiAgACAAkJ4B2/GwAiAgAAAA==.Aericura:BAAALgADCggJBwAAAA==.Aetheriel:BAABLgAECn8ZAAIDAAcJXA2hNQBCAQADAAcJXA2hNQBCAQAAAA==.Aethon:BAAALgADCgcJDQAAAA==.',
Ag='Aggronok:BAABLgAFFH8GAAIEAAMJnQSJHQC/AAAEAAMJnQSJHQC/AAAAAA==.',
Ah='Ahnyanka:BAAALgADCgYJBgAAAA==.',
Ai='Aiaria:BAAALgAECgYJEAAAAA==.Airi:BAAALgADCgEJAQAAAA==.Airrin:BAAALgAECgYJCwAAAA==.',
Ak='Akari:BAACLgAFFH8FAAIFAAMJJRWNFQDcAAAFAAMJJRWNFQDcAAAuAAQKfzkAAwUACQmFIPcBAEsDAAUACQmFIPcBAEsDAAYABgmQDY5PAAUBAAAA.Akasha:BAABLgAECn8YAAIHAAkJgyFRJQByAgAHAAkJgyFRJQByAgAAAA==.Akatala:BAABLgAECn8bAAQIAAgJnxUjJgAiAgAIAAgJnxUjJgAiAgAJAAQJhQ1xJgDFAAAKAAEJUgP8lwAfAAAAAA==.Akunda:BAABLgAECn8pAAILAAkJFxi0DABnAgALAAkJFxi0DABnAgAAAA==.',
Al='Alamaania:BAAALgAECgYJEwAAAA==.Alaterial:BAAALgAECgMJBAAAAA==.Alazara:BAAALgAECgcJCQAAAA==.Allukaa:BAAALgAECgQJBQAAAA==.Aloha:BAACLgAFFH8PAAIMAAUJZRotDABMAQAMAAUJZRotDABMAQAuAAQKfx0AAgwACQlMIKILAN0CAAwACQlMIKILAN0CAAAA.Aluriel:BAACLgAFFH8FAAMNAAMJ5wyTXQCSAAANAAIJrQ6TXQCSAAAOAAEJWgkYCgBKAAAuAAQKfyYABA0ACAmNIeIRAFQCAA0ACAmNIeIRAFQCAA4AAQkAAB4kAGEAAA8AAgnyF9VfAE8AAAAA.',
Am='Ambellìna:BAAALgADCgEJAQAAAA==.Ambellína:BAAALgADCgYJBgAAAA==.Amenrah:BAAALgAECgMJBAAAAA==.Amorisx:BAAALgADCgcJEQAAAA==.',
An='Anarchy:BAABLgAECn8XAAIHAAkJMB/XHwCSAgAHAAkJMB/XHwCSAgAAAA==.Androse:BAABLgAECn8ZAAIBAAcJZSKXKQB+AgABAAcJZSKXKQB+AgAAAA==.Anjuli:BAAALgAECgEJAQABLgAECggJIQAIACUeAA==.',
Ar='Arai:BAAALgAECgMJAwAAAA==.Arclîght:BAAALgAECgQJCAAAAA==.Aruj:BAAALgAECgYJDAAAAA==.',
As='Ashkari:BAABLgAECn8aAAMCAAkJviLyEgBkAgACAAkJviLyEgBkAgAQAAIJABfvEQByAAAAAA==.Astrea:BAABLgAECn8bAAIDAAYJZhhzJwCTAQADAAYJZhhzJwCTAQAAAA==.',
At='Athenis:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJBwAAAA==.Aurianna:BAAALgADCgEJAQAAAA==.',
Av='Avolokden:BAAALgAECgYJEgAAAA==.',
Az='Azem:BAAALgADCgUJBQAAAA==.Azmyth:BAACLgAFFH8aAAIBAAYJOSWFAQAnAgABAAYJOSWFAQAnAgAuAAQKfyAAAgEACAnUJukEAH0DAAEACAnUJukEAH0DAAAA.Azmythr:BAAALgAFFAEJAQABLgAFFAYJGgABADklAA==.Azzaerial:BAAALgAECgQJBAAAAA==.',
Ba='Baez:BAAALgAECgEJAwABLgAECgUJEQARAAAAAA==.Baezgor:BAAALgAECgMJAwABLgAECgUJEQARAAAAAA==.Baolin:BAAALgADCgMJAwABLgADCgQJBAARAAAAAA==.Bartahk:BAAALgAECgYJCAABLgAFFAIJBwACAKMeAA==.Bashroot:BAAALgADCgUJBgAAAA==.Bastalion:BAAALgAECgQJBwAAAA==.Baxtersin:BAAALgAECgEJBAAAAA==.Baxtersinho:BAAALgAECgEJAQABLgAECgUJFAACAOAcAA==.Bayz:BAAALgAECgUJCAAAAA==.',
Be='Beamkin:BAAALgADCggJCAABLgADCgEJAQARAAAAAA==.Beardedwiz:BAAALgADCgMJAwAAAA==.Bearys:BAAALgADCgMJAwAAAA==.Beerbelly:BAAALgADCgkJCQAAAA==.Beeshoney:BAAALgAECgYJCwAAAA==.Beetle:BAAALgAFFAIJAgABLgAFFAUJEAASAF8QAA==.Behr:BAAALgAECgMJAwAAAA==.Beighblade:BAAALgADCgQJBgABLgAFFAQJCAAGAB4HAA==.Belgar:BAAALgAECgUJBgAAAA==.Berries:BAAALgADCggJFwAAAA==.Beson:BAAALgADCgQJBAAAAA==.Betræÿer:BAAALgADCgcJFwAAAA==.Beyondthedk:BAAALgAECgYJEAAAAA==.',
Bi='Bigazzdragon:BAABLgAECn8iAAQTAAgJEAaDKwD8AAATAAgJEAaDKwD8AAASAAIJGwEzPwAzAAAUAAIJFwN7KQAuAAAAAA==.Bigilli:BAAALgADCgYJBwAAAA==.Bigkahunas:BAABLgAECn8VAAIIAAgJexmGNQDYAQAIAAgJexmGNQDYAQAAAA==.Bigzacky:BAABLgAFFH8GAAIVAAQJeCOAAwCjAQAVAAQJeCOAAwCjAQAAAA==.Bilcaster:BAAALgAECgMJAwAAAA==.Biodiesel:BAAALgAECgYJCgAAAA==.',
Bl='Blackfire:BAAALgAECgUJCQAAAA==.Bladlast:BAABLgAECn8pAAIWAAkJlhHAEAAVAgAWAAkJlhHAEAAVAgAAAA==.Blankee:BAACLgAFFH8TAAIXAAYJvCCMCADoAQAXAAYJvCCMCADoAQAuAAQKfyIAAhcACAl8JY0OAFIDABcACAl8JY0OAFIDAAAA.Blargo:BAACLgAFFH8NAAIDAAQJVB7lDQBrAQADAAQJVB7lDQBrAQAuAAQKfyIAAgMACAmSJp4BAIsDAAMACAmSJp4BAIsDAAAA.Blinkygg:BAAALgADCgYJBwAAAA==.Bloodraven:BAABLgAECn8UAAMIAAYJZhzGOQDHAQAIAAYJZhzGOQDHAQAKAAUJygYmZACvAAAAAA==.Bloodyfinger:BAAALgAECgYJCgABLgAECgcJGQAYAFofAA==.',
Bo='Boat:BAACLgAFFH8RAAIFAAUJEyR+AwATAgAFAAUJEyR+AwATAgAuAAQKfyQAAgUACAkrJhcCAG4DAAUACAkrJhcCAG4DAAAA.Bobarker:BAABLgAECn8VAAIVAAcJ+hPGGACIAQAVAAcJ+hPGGACIAQAAAA==.Bobpet:BAACLgAFFH8ZAAMJAAYJOBU1AgCbAQAJAAYJ1A41AgCbAQAIAAQJihrNCwAEAQAuAAQKfx4AAwkACAm6H74IAFoCAAkACAk4Hr4IAFoCAAgABAnQHRJYAGABAAAA.Boglim:BAAALgADCgYJBwAAAA==.Bohdi:BAAALgADCgEJAQAAAA==.Bombisevil:BAAALgAECgMJAwABLgAFFAYJFQATAOkZAA==.Boomins:BAAALgADCgUJBQAAAA==.Boonims:BAAALgADCggJCQAAAA==.Booze:BAAALgAECgUJCAABLgAFFAQJDQADAFQeAA==.Borbadin:BAAALgAECgEJAgAAAA==.Borgîr:BAACLgAFFH8FAAIZAAMJ1w4FBQD4AAAZAAMJ1w4FBQD4AAAuAAQKfysAAhkACAneIbYBALECABkACAneIbYBALECAAAA.Bossee:BAACLgAFFH8FAAIVAAUJBQx3BgBdAQAVAAUJBQx3BgBdAQAuAAQKfx8AAxUABwnPG8wNAAoCABUABwnPG8wNAAoCABoAAwkvDBRMAEMAAAEuAAUUBgkTABcAvCAA.Bowfdeez:BAAALgADCgQJBgAAAA==.',
Br='Bradadin:BAAALgAECgUJCAAAAA==.Brainlagg:BAABLgAECn8jAAMNAAkJsA3NMACgAQANAAkJsA3NMACgAQAPAAIJJwS6YQBKAAAAAA==.Brewsly:BAACLgAFFH8VAAIGAAUJ8RHOEwAiAQAGAAUJ8RHOEwAiAQAuAAQKfyoAAgYACQmaGSAIAEsCAAYACQmaGSAIAEsCAAAA.Brightleaf:BAABLgAECn8UAAIMAAgJCgo4IQAtAQAMAAgJCgo4IQAtAQAAAA==.Bruor:BAAALgAECgYJDgAAAA==.Brusque:BAAALgAECgYJDQAAAA==.Bruteus:BAAALgADCgcJCAAAAA==.Bruzthemoose:BAAALgADCgEJAQAAAA==.Brynä:BAABLgAECn8UAAIbAAgJ9AQfBQBzAQAbAAgJ9AQfBQBzAQAAAA==.',
Bu='Bugbug:BAAALgAECgQJBAAAAA==.Buhr:BAABLgAECn8YAAMDAAgJtA1PWgBDAQADAAgJtA1PWgBDAQAMAAEJswa6WgAuAAAAAA==.Bullhorndh:BAAALgADCgIJAgAAAA==.Bulvie:BAAALgADCgEJAQAAAA==.Burgerpants:BAAALgADCgcJDQABLgAFFAUJEAAHAO4kAA==.Burmiya:BAAALgADCgkJCwAAAA==.Bushwookie:BAAALgAECgYJDAAAAA==.',
Ca='Caelthas:BAAALgADCgIJAgAAAA==.Caltheas:BAAALgADCgYJCQAAAA==.Calyssta:BAAALgAECgIJAgAAAA==.Cantou:BAABLgAECn8uAAIcAAkJqhdAAwBaAgAcAAkJqhdAAwBaAgAAAA==.Captcosmo:BAAALgAECgUJDgAAAA==.Carl:BAAALgAECgIJAwABLgAECgMJBgARAAAAAA==.Carraig:BAAALgADCgYJCAAAAA==.Carthorís:BAAALgAECgMJAwAAAA==.Catameld:BAAALgADCgcJBwAAAA==.Catpaws:BAAALgAECgEJAwAAAA==.',
Ce='Celdios:BAAALgADCgYJCQAAAA==.Celthas:BAAALgAECgYJDQAAAA==.',
Ch='Chernov:BAAALgADCggJCAAAAA==.Chithris:BAAALgAECgQJBAAAAA==.Chodoge:BAACLgAFFH8RAAQUAAUJfQ0UCwBlAQAUAAUJfQ0UCwBlAQASAAIJHQViBwCTAAATAAIJ4gSwMQCBAAAuAAQKfx8ABBQACAmZGOoQACwCABQACAmZGOoQACwCABMAAgmGH5xHALsAABIAAgkJH7UvAJkAAAAA.Chonks:BAAALgADCgUJBQAAAA==.Chrisdk:BAABLgAECn8ZAAICAAgJsSFhCwCvAgACAAgJsSFhCwCvAgAAAA==.',
Ci='Ciimagi:BAABLgAECn8eAAIXAAgJ7Rm2MADeAQAXAAgJ7Rm2MADeAQAAAA==.Cirno:BAABLgAECn8jAAIaAAkJ8RsNCgAjAgAaAAkJ8RsNCgAjAgAAAA==.',
Cl='Clamcast:BAABLgAECn8dAAIXAAkJkCKYDABgAwAXAAkJkCKYDABgAwAAAA==.Clíché:BAABLgAECn8WAAIXAAYJ+h1LPgCtAQAXAAYJ+h1LPgCtAQAAAA==.',
Co='Combat:BAAALgADCgcJCQAAAA==.Conquêst:BAAALgAECgcJBwAAAA==.Constantino:BAABLgAECn8WAAIdAAYJcwj5EACyAAAdAAYJcwj5EACyAAAAAA==.Coorslite:BAAALgADCgEJAQAAAA==.Copeidan:BAAALgAECgkJDgABLgAECgkJJAAHAOoiAA==.Copenfel:BAABLgAECn8kAAIHAAkJ6iJsCgCDAgAHAAkJ6iJsCgCDAgAAAA==.',
Cr='Crat:BAAALgAECgIJAgAAAA==.Creammachine:BAAALgAFFAEJAQABLgAFFAMJCwAcAKUkAA==.Crimpydiff:BAAALgADCgIJAgAAAA==.Crossblêssêr:BAACLgAFFH8HAAIeAAMJOhXoFgDzAAAeAAMJOhXoFgDzAAAuAAQKfx4AAh4ACAn/GEQRAC8CAB4ACAn/GEQRAC8CAAAA.',
Cw='Cwaidec:BAAALgAECgEJAgAAAA==.Cwem:BAABLgAECn8bAAIBAAgJqhkCPQCPAQABAAgJqhkCPQCPAQAAAA==.',
Cy='Cyndeer:BAAALgADCgUJBQAAAA==.',
Da='Daddeigh:BAAALgAECgYJCAAAAA==.Dadson:BAAALgADCgEJAQAAAA==.Dahlias:BAAALgAECggJEwAAAA==.Daliel:BAABLgAECn8eAAMaAAgJjwmEGwBfAQAaAAgJjwmEGwBfAQAeAAYJ2AMyKADoAAAAAA==.Danikksky:BAAALgADCgUJBQAAAA==.Dannikksky:BAAALgAECgYJDAAAAA==.Daphni:BAAALgADCgcJBwABLgAFFAMJBwAMAAwKAA==.Darkian:BAAALgAECgUJBgAAAA==.Dasani:BAAALgADCgYJDAABLgAECgUJDAARAAAAAA==.Daviath:BAAALgAECgQJAQAAAA==.Davinia:BAABLgAECn8YAAIPAAcJpwRKEQDNAAAPAAcJpwRKEQDNAAAAAA==.',
De='Deaddreams:BAAALgADCgEJAQAAAA==.Deadwait:BAAALgADCgUJBQAAAA==.Dean:BAACLgAFFH8EAAIHAAMJgQf/OwDAAAAHAAMJgQf/OwDAAAAuAAQKfyQAAgcACAmDE8YsAIQBAAcACAmDE8YsAIQBAAAA.Dedrater:BAAALgAECgQJBAAAAA==.Dedsec:BAAALgADCgEJAQAAAA==.Deel:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Defnotshadow:BAABLgAECn8eAAIHAAgJaBa2GgDpAQAHAAgJaBa2GgDpAQAAAA==.Deithknight:BAAALgAECggJEwAAAA==.Demna:BAAALgADCggJDQAAAA==.Demonboy:BAAALgAECgEJAQAAAA==.Demoncook:BAABLgAECn81AAIHAAgJviCNCgCBAgAHAAgJviCNCgCBAgAAAA==.Demonroo:BAAALgAECgMJAwAAAA==.Denishath:BAAALgADCgIJAgAAAA==.Denyx:BAAALgAECgQJBAAAAA==.Depravity:BAAALgAECgIJAwABLgAECgkJFwAHADAfAA==.Depression:BAAALgAECgUJBgABLgAFFAgJIAAFAFAeAA==.Deputymeow:BAABLgAECn8UAAIWAAYJkgqlVgAhAQAWAAYJkgqlVgAhAQAAAA==.Desalination:BAAALgAECgUJBQABLgAFFAUJDwAMAGUaAA==.Designated:BAABLgAECn8UAAIHAAcJLCDwKQBZAgAHAAcJLCDwKQBZAgAAAA==.Designatedh:BAAALgADCgEJAQAAAA==.Designatedm:BAAALgAECgcJEgAAAA==.Destanie:BAAALgAECgYJCwAAAA==.Deusvûlt:BAAALgAECgkJDQAAAA==.Devouler:BAAALgAECgUJDAAAAA==.Dexius:BAAALgADCgcJBwAAAA==.Dezenoth:BAAALgADCgcJBwAAAA==.Deúz:BAACLgAFFH8FAAIfAAMJ7xP8DQDWAAAfAAMJ7xP8DQDWAAAuAAQKfxUAAh8ACAliGO4QAPkBAB8ACAliGO4QAPkBAAAA.',
Di='Diela:BAAALgAECgYJEQAAAA==.Diesel:BAAALgAECgYJEAAAAA==.Diill:BAABLgAECn8VAAIXAAgJRRSjRQCWAQAXAAgJRRSjRQCWAQAAAA==.Diillz:BAAALgAECggJEwABLgAECggJFQAXAEUUAA==.Dikaiosýni:BAAALgAECgEJAQABLgAECggJIwAfAI0WAA==.',
Dk='Dkandy:BAABLgAECn8xAAIQAAkJaSYVAACCAwAQAAkJaSYVAACCAwAAAA==.Dkoi:BAABLgAECn8YAAINAAgJLxwZKwBjAgANAAgJLxwZKwBjAgAAAA==.Dkykin:BAACLgAFFH8LAAIMAAQJ0hgHCwBUAQAMAAQJ0hgHCwBUAQAuAAQKfyMAAgwACAkHICEPAK0CAAwACAkHICEPAK0CAAAA.',
Do='Dogstar:BAAALgADCgkJHgAAAA==.Domïno:BAAALgADCgMJAwAAAA==.Donklord:BAABLgAECn8aAAMHAAgJBRwoGAD7AQAHAAgJBRwoGAD7AQAdAAEJShRAKgA6AAABLgAFFAMJCwAcAKUkAA==.Doomzy:BAAALgAECgYJCAAAAA==.Dotcalm:BAAALgADCgcJCQAAAA==.Dotsrus:BAAALgAECgYJBgABLgAECgkJIgALAEYeAA==.Downfawl:BAABLgAECn8jAAMCAAgJPhrpJgDkAQACAAgJIxfpJgDkAQAQAAUJvBm0BwAvAQABLgAFFAQJDwAMAL4KAA==.',
Dr='Draaenor:BAAALgADCgEJAQAAAA==.Dracculus:BAAALgAECgQJBAAAAA==.Draconblaze:BAAALgAECgYJDAAAAA==.Draginballz:BAABLgAECn8YAAITAAcJyQ5TIwAsAQATAAcJyQ5TIwAsAQAAAA==.Drakthor:BAABLgAFFH8FAAIYAAMJSx2PCwAbAQAYAAMJSx2PCwAbAQAAAA==.Dreamsteam:BAAALgADCgcJBwAAAA==.Drelina:BAAALgADCgEJAQAAAA==.Driam:BAAALgADCgcJCwAAAA==.Drocthyr:BAABLgAECn8WAAITAAkJbwfWMwAuAQATAAkJbwfWMwAuAQAAAA==.Droité:BAAALgADCgcJDQAAAA==.Drow:BAAALgADCgQJBAAAAA==.Druf:BAABLgAECn8UAAIUAAgJrws+DACFAQAUAAgJrws+DACFAQAAAA==.Druizu:BAAALgAECgEJAQABLgAECgUJEQARAAAAAA==.Drujitsu:BAAALgAECgIJAgAAAA==.Druknar:BAABLgAECn8uAAINAAgJhAMsagD4AAANAAgJhAMsagD4AAAAAA==.Drágám:BAAALgAECgMJBAAAAA==.',
Dt='Dtzdrood:BAAALgADCgIJAgAAAA==.',
Du='Dundrin:BAAALgADCgIJAgAAAA==.Durbinbreath:BAAALgAECgQJBQABLgAFFAEJAQARAAAAAA==.Durbinshalah:BAAALgAFFAEJAQAAAA==.Durf:BAAALgADCgkJEgABLgAECggJFAAUAK8LAA==.',
Dy='Dyllata:BAAALgAECgMJAwAAAA==.Dyondra:BAABLgAECn8YAAMDAAcJeBDhLwBhAQADAAcJeBDhLwBhAQAMAAEJjgfiiAAnAAAAAA==.',
['Dä']='Därth:BAAALgADCgEJAQAAAA==.',
Ea='Earthclad:BAAALgAECgUJBwAAAA==.',
Ec='Eccentrik:BAAALgADCgMJAwABLgAECgEJAQARAAAAAA==.Ecxentric:BAAALgADCgMJAwABLgAECgEJAQARAAAAAA==.',
Ed='Edah:BAAALgADCgcJDQAAAA==.',
Ee='Eevah:BAABLgAECn8hAAQIAAgJJR4/GAAOAgAIAAgJJR4/GAAOAgAKAAIJyQjBewBUAAAJAAEJAAACRAAAAAAAAA==.',
Eg='Eggsonrice:BAAALgAECgcJCwAAAA==.',
El='Elchacal:BAAALgAECgIJAgAAAA==.Elementsmash:BAAALgAECgYJCwAAAA==.Eleventeen:BAACLgAFFH8FAAIDAAMJGxMuIQDSAAADAAMJGxMuIQDSAAAuAAQKfycAAgMACAmVGzIPAGACAAMACAmVGzIPAGACAAAA.Elfburt:BAAALgADCgEJAQAAAA==.Elihavoc:BAAALgAECgUJBwAAAA==.Elixtempest:BAAALgADCgkJEQAAAA==.Ellariá:BAAALgAECgEJAQAAAA==.Ellará:BAAALgADCgMJBgAAAA==.Ellmz:BAAALgADCgcJDQAAAA==.Elmtaro:BAAALgADCgQJBAAAAA==.Elmz:BAAALgADCgcJBQAAAA==.Elosai:BAABLgAECn8XAAMgAAYJZQhmCwAhAQAgAAYJZQhmCwAhAQAXAAYJ9AL2qADCAAAAAA==.',
Em='Empressdemon:BAAALgAECgEJAgAAAA==.',
En='Enyar:BAAALgAECgkJAQAAAA==.',
Ep='Epicninja:BAAALgAECgkJCAAAAA==.',
Er='Eriis:BAAALgADCgcJBwAAAA==.',
Es='Eseri:BAAALgAFFAEJAQAAAA==.',
Ev='Evokeparri:BAAALgAECgMJAwAAAA==.',
Ex='Exarch:BAAALgAECgUJCQAAAA==.Extis:BAAALgAECgEJAQAAAA==.',
Fa='Facesplat:BAAALgADCgUJBwABLgAECgcJAgARAAAAAA==.Faedeyne:BAAALgADCgYJBgAAAA==.Famouz:BAAALgADCgEJAQAAAA==.Fangaxe:BAACLgAFFH8SAAIfAAUJnhzgBQBRAQAfAAUJnhzgBQBRAQAuAAQKfxsAAh8ACQlQH4QHALACAB8ACQlQH4QHALACAAAA.Farseer:BAABLgAECn8WAAMEAAgJyQn6JAAvAQAEAAgJyQn6JAAvAQALAAEJxQKCpwAnAAAAAA==.',
Fe='Feebee:BAAALgAECgEJAQABLgAECgkJLgAcAKoXAA==.Felaequitas:BAAALgAECgcJDgAAAA==.Feniri:BAAALgADCgcJDQAAAA==.Fentrock:BAABLgAECn8YAAINAAcJYh43JwDLAQANAAcJYh43JwDLAQAAAA==.Fentshift:BAAALgAECgIJAgAAAA==.Fernãndo:BAAALgADCgQJBQAAAA==.',
Ff='Ffn:BAAALgADCgYJBgABLgAECgcJEwARAAAAAA==.',
Fi='Fibophy:BAAALgADCgcJBwAAAA==.Fidelius:BAAALgADCgkJEgAAAA==.',
Fl='Floshotmoo:BAABLgAECn8lAAIDAAgJRgdxPgAaAQADAAgJRgdxPgAaAQAAAA==.Fluffydog:BAAALgAECgMJBQAAAA==.Fly:BAACLgAFFH8QAAMSAAUJXxASAwBHAQASAAQJJA4SAwBHAQATAAUJWg57DQAqAQAuAAQKfxwAAxIACQkJHDcEAMsCABIACAnyHjcEAMsCABMABAndFIA7AAIBAAAA.',
Fo='Foxini:BAAALgAECgYJEwAAAA==.',
Fr='Fragii:BAAALgADCgcJBwAAAA==.Fragility:BAAALgAECgYJBgAAAA==.Fraglle:BAAALgAECgEJBAAAAA==.Fragon:BAABLgAECn8bAAIUAAYJyAkoFAD9AAAUAAYJyAkoFAD9AAAAAA==.Franzen:BAAALgAECgQJBAABLgAECggJFAAXACwRAA==.Frosteenips:BAAALgADCgcJDQAAAA==.Frozenearth:BAAALgADCgEJAQAAAA==.',
Fu='Full:BAAALgADCgcJCwAAAA==.Funkbear:BAAALgADCgEJAQAAAA==.',
Fw='Fwieddmpwng:BAAALgAECgIJAgAAAA==.',
Ga='Gafgarion:BAAALgAECggJCAAAAA==.Garfallen:BAAALgADCgcJCQAAAA==.Gartic:BAAALgAECgYJBgAAAA==.Garzha:BAAALgAECgMJBwAAAA==.Gas:BAAALgAECgMJAwAAAA==.Gaypoc:BAABLgAECn8VAAMMAAYJDRZ7IQArAQAMAAYJDRZ7IQArAQADAAMJQAw5nQCRAAAAAA==.Gazember:BAAALgADCgcJBwABLgAECgYJGgAeAIobAA==.',
Ge='Gehenna:BAABLgAECn8eAAIXAAgJuhnhNgDGAQAXAAgJuhnhNgDGAQAAAA==.Gezebel:BAAALgAECgUJEgAAAA==.',
Gh='Ghoret:BAAALgADCgIJAgAAAA==.Ghouldamn:BAABLgAECn8YAAICAAcJZQfrYwAcAQACAAcJZQfrYwAcAQAAAA==.Ghðst:BAABLgAECn8mAAIXAAgJSRNPPgCsAQAXAAgJSRNPPgCsAQAAAA==.',
Gl='Gladia:BAAALgAECgYJDQAAAA==.Glaiv:BAAALgADCgEJAQAAAA==.Glarghal:BAABLgAECn8fAAMVAAgJkBUuFAC3AQAVAAcJ0hcuFAC3AQAeAAEJyAWuRQA1AAAAAA==.Gleepos:BAAALgAECgUJCAAAAA==.Gláurung:BAABLgAECn8hAAIZAAcJcRpuBwC7AQAZAAcJcRpuBwC7AQAAAA==.Glórfindel:BAAALgAECgYJBgAAAA==.',
Go='Gokuu:BAABLgAECn8UAAIXAAgJLBE9cgDvAQAXAAgJLBE9cgDvAQAAAA==.Golokhan:BAAALgADCgIJAgABLgAECggJIgAhAEMgAA==.Goosily:BAAALgAECgIJAwAAAA==.Goremagala:BAAALgADCgQJBAAAAA==.',
Gr='Grapebevrage:BAABLgAECn8oAAIaAAkJMRfGDQDtAQAaAAkJMRfGDQDtAQAAAA==.Gravyrobbers:BAAALgAECggJDwAAAA==.Greenbob:BAAALgADCgkJCQAAAA==.Greentouch:BAAALgADCgYJBgAAAA==.Grewt:BAACLgAFFH8PAAIMAAQJvgoREwAeAQAMAAQJvgoREwAeAQAuAAQKfyUAAgwACAkfID8MANQCAAwACAkfID8MANQCAAAA.Grimwood:BAAALgADCgcJBwAAAA==.Grudel:BAAALgADCgcJCwABLgAECgkJSgACAC0XAA==.Grögin:BAAALgAECggJEgAAAA==.',
Gs='Gseries:BAAALgAECgQJBQAAAA==.',
Gu='Gueigh:BAAALgAECgQJBAAAAA==.Guldave:BAAALgADCgEJAQAAAA==.Gulunga:BAAALgAECgUJBQABLgAECgYJCgARAAAAAA==.',
Gy='Gyatt:BAAALgAECgYJBwABLgAECgcJEwARAAAAAA==.',
Ha='Halestormdh:BAAALgAECgYJEAAAAA==.Halløw:BAAALgADCgUJBQAAAA==.Harbin:BAAALgADCgEJAQAAAA==.Harrymason:BAABLgAECn8UAAIiAAcJPBRuEQBeAQAiAAcJPBRuEQBeAQAAAA==.Harvyr:BAACLgAFFH8GAAINAAQJIxXoIwArAQANAAQJIxXoIwArAQAuAAQKfxgAAw0ACAl7HnRCAAUCAA0ABgkGIHRCAAUCAA8AAgk3FRk/ALgAAAAA.Hashbrown:BAAALgADCgYJBgAAAA==.Hate:BAAALgAECgEJAQAAAA==.Hathaw:BAAALgAECgUJCwAAAA==.Havyk:BAAALgAECgYJBgAAAA==.Hayhay:BAABLgAECn8jAAQIAAkJQyLMDwC9AgAIAAkJQyLMDwC9AgAJAAUJpRNoHAAhAQAKAAUJ0BU9UgAEAQAAAA==.',
He='Healingdabs:BAAALgAECgEJAQAAAA==.Helghast:BAAALgAECgYJEQAAAA==.Helionn:BAAALgAECgYJEwAAAA==.Herbie:BAAALgADCgMJAwAAAA==.Herja:BAAALgAECgEJAQAAAA==.',
Hi='Hidebound:BAABLgAECn8bAAIjAAkJXAxRBACbAQAjAAkJXAxRBACbAQAAAA==.Hippolyta:BAAALgAECgYJBgAAAA==.Hisouka:BAAALgAECgYJCwABLgAFFAMJBwAIAFUWAA==.',
Ho='Hobgoblinn:BAACLgAFFH8bAAIEAAYJCRO1BQCXAQAEAAYJCRO1BQCXAQAuAAQKfycAAgQACQmbG2gKADMCAAQACQmbG2gKADMCAAAA.Honeybees:BAABLgAECn8cAAIVAAkJMRtjBQCvAgAVAAkJMRtjBQCvAgAAAA==.Honeydutchtv:BAAALgAECgMJAwAAAA==.Hoodritch:BAAALgAECgEJAQAAAA==.Hopezbanyruu:BAAALgAECgcJEAABLgAECggJJAAMAKUhAA==.Hopezherbz:BAABLgAECn8kAAMMAAgJpSFpCwDgAgAMAAgJpSFpCwDgAgADAAEJ3w80lQAxAAAAAA==.',
Hu='Hubbo:BAAALgAECgQJBwAAAA==.Hugedonut:BAAALgADCgEJAQABLgADCgYJDwARAAAAAA==.Hughmungus:BAAALgAECgMJAwABLgAFFAQJBwAMAIYLAA==.Hunzu:BAAALgAECgUJEQAAAA==.',
Hy='Hypojin:BAABLgAECn8hAAIMAAkJyROkDwDXAQAMAAkJyROkDwDXAQAAAA==.Hyposelenia:BAAALgAECgYJCwAAAA==.',
['Hó']='Hótsauce:BAAALgADCgIJAgAAAA==.',
Ia='Iamthemoon:BAAALgAECgEJAgAAAA==.Iamthesun:BAAALgAECgQJBQAAAA==.',
Ic='Iceaged:BAABLgAECn8iAAIXAAkJkyJRHQAAAwAXAAkJkyJRHQAAAwAAAA==.',
Ig='Igneel:BAABLgAECn8rAAMSAAgJAhsPAgBGAgASAAgJAhsPAgBGAgATAAIJMAh2WQBYAAAAAA==.Igøtya:BAAALgAECgYJCgAAAA==.',
Il='Illidawn:BAAALgAECgUJBgAAAA==.Illos:BAABLgAECn8XAAIjAAgJCRztAQA1AgAjAAgJCRztAQA1AgAAAA==.',
Im='Imabigboy:BAAALgADCgQJBAAAAA==.Iminthegame:BAAALgADCgEJAQAAAA==.',
In='Infinite:BAAALgAECgIJAgAAAA==.Integra:BAABLgAECn8QAAMeAAgJVxAiEADRAQAeAAgJVxAiEADRAQAaAAYJ5QY5KwDxAAAAAA==.Intervention:BAAALgAECgYJBgAAAA==.',
Io='Iokua:BAAALgAECgEJAQAAAA==.',
Ir='Irisvar:BAAALgADCgQJBwAAAA==.Ironcurse:BAAALgAECgUJDAAAAA==.Irondagger:BAAALgAECgUJCQAAAA==.Ironninja:BAAALgADCgIJAgAAAA==.Ironrage:BAAALgAECgYJCAAAAA==.Ironskin:BAAALgAECgcJEAAAAA==.Irontotems:BAAALgAECgEJAgAAAA==.',
Is='Isogi:BAAALgAECgEJAQABLgAECgEJAQARAAAAAA==.',
It='Itadori:BAAALgAECgUJDAAAAA==.Itheron:BAABLgAECn8iAAIHAAkJzx/zFwDGAgAHAAkJzx/zFwDGAgAAAA==.Itzdiill:BAAALgAECgcJCwABLgAECggJFQAXAEUUAA==.',
Ja='Jabbathehunt:BAAALgADCgcJDAAAAA==.Jakkin:BAAALgAECgYJCwAAAA==.Jandis:BAAALgADCgMJBAAAAA==.Jardin:BAAALgADCgcJFwAAAA==.Jasteer:BAAALgAECgQJBwAAAA==.',
Jb='Jbsham:BAAALgAECgIJAgAAAA==.',
Je='Jer:BAAALgADCgQJBAABLgAECgcJFQAHAJUeAA==.Jessbae:BAABLgAECn8mAAMFAAkJCRKrJwB3AQAFAAgJjw+rJwB3AQAYAAYJFBpdIwANAQAAAA==.',
Jf='Jfac:BAAALgAECgQJBAAAAA==.',
Ji='Jilifer:BAAALgAECgkJAwAAAA==.Jimmypage:BAACLgAFFH8LAAMcAAMJpSTtAgBPAQAcAAMJpSTtAgBPAQADAAEJcBIQJQBGAAAuAAQKfyUAAxwACAmqIRMGAJ4CABwABwktJhMGAJ4CAAMABgktHzccAOIBAAAA.',
Jo='Joebon:BAABLgAECn8iAAIkAAkJGBwZEQDpAQAkAAkJGBwZEQDpAQAAAA==.Johnnybgood:BAAALgADCgcJBwAAAA==.',
Jq='Jquellin:BAAALgADCgYJBgAAAA==.',
Js='Jska:BAAALgAECgYJDQAAAA==.',
Jt='Jtrain:BAABLgAECn8bAAIIAAgJCyABDAB/AgAIAAgJCyABDAB/AgAAAA==.',
Ju='Juicedmoose:BAABLgAECn8oAAICAAkJvCDhCQDCAgACAAkJvCDhCQDCAgAAAA==.Junundu:BAAALgAECgkJAQAAAA==.Justahhtank:BAAALgAECgQJBQAAAA==.',
Ka='Kaelissa:BAAALgADCgcJCwAAAA==.Kaelisse:BAAALgADCgcJDAAAAA==.Kaelstrada:BAABLgAECn8iAAIhAAgJQyC7BQBJAgAhAAgJQyC7BQBJAgAAAA==.Kaendndeydra:BAAALgAECgEJAQAAAA==.Kaennä:BAAALgAECgQJBAAAAA==.Kaladynn:BAAALgADCgIJAgAAAA==.Kalahari:BAAALgAECgYJEAAAAA==.Kalel:BAAALgADCggJCAAAAA==.Kao:BAAALgADCgEJAgABLgAECgYJCQARAAAAAA==.Karazdormu:BAAALgADCgQJBAAAAA==.Kari:BAAALgAECgIJAgAAAA==.Karlyta:BAAALgADCgMJAwAAAA==.Karmà:BAAALgADCgMJAwAAAA==.Karzend:BAAALgAECgMJAwAAAA==.Kateri:BAAALgAECgMJBAAAAA==.Kattah:BAAALgAECgYJCwAAAA==.Kavikk:BAAALgAECgYJCQABLgAECgcJEgAkAIgVAA==.Kazrak:BAAALgAECgMJAwAAAA==.',
Ke='Kellbells:BAABLgAECn8VAAIkAAgJeg6ZPgCqAQAkAAgJeg6ZPgCqAQAAAA==.Kenchii:BAAALgAECgYJDQAAAA==.Keswickpally:BAAALgAECgYJBgAAAA==.',
Kh='Khabib:BAAALgADCgcJBAAAAA==.',
Ki='Kindrella:BAACLgAFFH8HAAQaAAMJbwMMGwCNAAAaAAIJAgQMGwCNAAAeAAIJZAG5IwBoAAAVAAEJzQd+HgBGAAAuAAQKfyYABBoACAmuD10VAJYBABoACAmuD10VAJYBABUABQlpE5E8AEgBAB4ABAlqB+9CAJ0AAAAA.Kirana:BAAALgADCgUJBQAAAA==.Kirbe:BAAALgAECggJEAAAAA==.Kitkatdaddy:BAAALgAECgEJAQAAAA==.',
Kl='Klaps:BAAALgADCgMJBgAAAA==.Klassus:BAAALgAECgQJAwAAAA==.',
Kn='Knoctürnal:BAACLgAFFH8JAAICAAQJFhI1LgBEAQACAAQJFhI1LgBEAQAuAAQKfygAAwIACAmMIqocANMCAAIACAmMIqocANMCABAABgk6Ec8IAFUBAAAA.',
Ko='Kootiekween:BAAALgAECgEJAQAAAA==.Korpskawluh:BAAALgAECgYJDAABLgAFFAQJCAAGAB4HAA==.Kotar:BAAALgAECgYJCgAAAA==.Kotetsu:BAAALgADCgIJAgAAAA==.Koufax:BAAALgAECgkJBwAAAA==.',
Kr='Kravoir:BAACLgAFFH8RAAITAAYJkhMlCQCdAQATAAYJkhMlCQCdAQAuAAQKfx4AAhMACAkRH8ENAJkCABMACAkRH8ENAJkCAAAA.Kruelty:BAAALgAECgcJDQAAAA==.Krugerrand:BAAALgADCgcJBwAAAA==.',
Ku='Kuleviz:BAAALgAECgMJAwAAAA==.Kuuma:BAAALgADCgUJBQAAAA==.Kuwabara:BAAALgADCgUJBAAAAA==.',
Kw='Kwaikadin:BAAALgAECgYJBgAAAA==.Kwayludes:BAAALgADCgcJCAAAAA==.',
Ky='Kylisse:BAAALgADCgYJDAAAAA==.',
La='Labrys:BAABLgAECn8YAAIIAAcJWA4EOQBpAQAIAAcJWA4EOQBpAQAAAA==.Lala:BAAALgAECgEJAQAAAA==.Lanakane:BAAALgADCggJDgAAAA==.Lasagna:BAABLgAECn8pAAIiAAkJ4hYtCQATAgAiAAkJ4hYtCQATAgAAAA==.Laserturkey:BAAALgADCgkJDgABLgAECggJFAAXACwRAA==.Lashana:BAAALgADCgYJBgAAAA==.Lastina:BAABLgAECn8YAAIPAAcJLw0qCgAzAQAPAAcJLw0qCgAzAQAAAA==.Lazroz:BAAALgAECgYJBgAAAA==.Lazypos:BAAALgADCgEJAQABLgAECgYJDwARAAAAAA==.',
Le='Leecy:BAABLgAECn8ZAAIkAAcJxglVJwA8AQAkAAcJxglVJwA8AQAAAA==.Leisyr:BAAALgADCgEJAQAAAA==.Lex:BAAALgAECgEJAQABLgAFFAMJBwAMAAwKAA==.Lexxe:BAACLgAFFH8HAAIMAAMJDApxGgDPAAAMAAMJDApxGgDPAAAuAAQKfxQAAwwACAlEFYoqAKwBAAwABwlEFYoqAKwBAAMAAQkiF1vFAD4AAAAA.',
Li='Lifehack:BAAALgAECgcJEwAAAA==.Light:BAAALgADCgcJBwAAAA==.Lighter:BAAALgADCgUJBQAAAA==.Lilmoist:BAAALgADCgEJAQABLgAECgQJBAARAAAAAA==.Lilsis:BAAALgAECgYJEAAAAA==.Linstrasza:BAAALgADCgYJBwAAAA==.Linzalina:BAAALgAFFAIJAgAAAA==.Littlebear:BAAALgAECgQJBQAAAA==.',
Lo='Locose:BAAALgAECgMJAwAAAA==.Lofn:BAABLgAECn8fAAIWAAcJUQ5UJgBXAQAWAAcJUQ5UJgBXAQAAAA==.Loingseach:BAAALgAECgYJCQABLgAECggJNQAHAL4gAA==.Loladin:BAAALgAECgYJCQAAAA==.Lolrush:BAABLgAECn8XAAIHAAYJdwe8ZgDPAAAHAAYJdwe8ZgDPAAABLgAFFAYJGgAGAO8OAA==.Lolyo:BAACLgAFFH8aAAIGAAYJ7w55CgBjAQAGAAYJ7w55CgBjAQAuAAQKfyEAAgYACAnvGQEeABICAAYACAnvGQEeABICAAAA.Lorimore:BAAALgAECgYJCAAAAA==.Lostclaws:BAAALgAECgQJBAAAAA==.Lostdragon:BAAALgAECgYJCwAAAA==.Lovehots:BAAALgAECgUJBQAAAA==.Lovetea:BAACLgAFFH8GAAIFAAMJjh+4EQANAQAFAAMJjh+4EQANAQAuAAQKfysAAgUACAmfJG4DAP8CAAUACAmfJG4DAP8CAAAA.Loxier:BAABLgAECn8oAAQVAAkJ0xRANwBfAQAVAAcJmApANwBfAQAeAAkJoxMXIAAqAQAaAAgJVgcFIwApAQAAAA==.',
Lu='Lugosh:BAAALgAECgQJBQAAAA==.Lumendevout:BAABLgAECn8hAAMeAAgJUSD2BAC6AgAeAAgJUSD2BAC6AgAaAAQJ5RMaMwDDAAAAAA==.',
Ly='Lyall:BAABLgAECn8eAAIMAAkJzBMUEgC3AQAMAAkJzBMUEgC3AQAAAA==.Lyrnn:BAABLgAECn8rAAIlAAkJkhxDBACJAgAlAAkJkhxDBACJAgAAAA==.',
Ma='Magabite:BAAALgADCgYJCQAAAA==.Mageoneten:BAAALgADCggJCAAAAA==.Mahihkan:BAAALgAECgEJAQAAAA==.Mahoragâ:BAAALgAECgkJAQAAAA==.Mainmoon:BAABLgAECn8lAAIYAAgJyh93BQCFAgAYAAgJyh93BQCFAgAAAA==.Managos:BAAALgAECgQJBwAAAA==.Masadeushi:BAABLgAECn8UAAMCAAUJ4BwVgQCAAQACAAUJyhwVgQCAAQAhAAEJ2h5cQABMAAAAAA==.Masou:BAAALgAECgYJCwAAAA==.Mathvell:BAAALgAECgUJBwAAAA==.',
Mc='Mcpaladin:BAAALgAECgcJDQAAAA==.',
Me='Meagle:BAAALgADCgEJAgAAAA==.Meg:BAABLgAECn8ZAAMmAAgJeRN4DgC1AQAmAAcJhBR4DgC1AQAkAAQJdQxWkwBxAAAAAA==.Megabonk:BAAALgAECgEJAgAAAA==.Megthemage:BAAALgAECgIJAgABLgAECggJGQAmAHkTAA==.Melathice:BAAALgADCggJEAAAAA==.Mellkor:BAAALgAECgEJAQAAAA==.Melsea:BAAALgADCgMJAwAAAA==.Menge:BAAALgAECgQJBwAAAA==.Mercifer:BAAALgAECgYJCgAAAA==.Metharian:BAAALgAECgUJCgAAAA==.',
Mi='Microcredit:BAAALgAECgcJEwAAAA==.Mightduy:BAAALgAECgUJDgAAAA==.Mikehum:BAAALgADCgQJBAAAAA==.Mintandberry:BAAALgADCgYJBgABLgADCggJFwARAAAAAA==.Missclickies:BAAALgAECgYJDQAAAA==.Mistweaver:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgEJAQABLgAECggJKwAYAAIjAA==.',
Mo='Moistbimbo:BAABLgAECn8aAAILAAcJDhLRJwCAAQALAAcJDhLRJwCAAQAAAA==.Moisturize:BAAALgADCgEJAQABLgAECgQJBAARAAAAAA==.Mommidommi:BAAALgAECggJDwAAAA==.Monamona:BAAALgAECggJEwAAAA==.Mondaprieta:BAAALgAECgEJAQAAAA==.Monderd:BAAALgADCgUJBQAAAA==.Monjolica:BAAALgADCgkJEAAAAA==.Monster:BAAALgAECgEJAQAAAA==.Moonuk:BAAALgAECgUJCwAAAA==.Mordrel:BAAALgAECgUJBQAAAA==.Morgianna:BAAALgAECgYJBgAAAA==.Morik:BAAALgAECgYJDwABLgAECgcJJgAkAOQVAA==.Morrwen:BAAALgAECgIJAgAAAA==.Mourah:BAAALgAECgYJDgAAAA==.Moìst:BAAALgAECgQJBAAAAA==.',
Mu='Mundytwo:BAABLgAECn8WAAMTAAYJkRYVKwBnAQATAAYJkRYVKwBnAQASAAIJuQGSOgBGAAAAAA==.Muraina:BAAALgAECgMJBAAAAA==.Muspel:BAAALgAECgQJCgAAAA==.',
['Mí']='Míssusbub:BAAALgAECgUJCwAAAA==.',
Na='Nabyar:BAAALgAECgEJAQAAAA==.Nantusk:BAAALgADCgEJAQAAAA==.Narisa:BAAALgADCgYJBgAAAA==.Nate:BAACLgAFFH8bAAIXAAYJaxh3DQC8AQAXAAYJaxh3DQC8AQAuAAQKfycAAhcACQm5H4YXAF8CABcACQm5H4YXAF8CAAAA.Natinalo:BAAALgAECgEJAQAAAA==.Navric:BAAALgAECgEJAgAAAA==.',
Ne='Necrohealnya:BAAALgAECgYJDwAAAA==.Necrolalacon:BAAALgAECgQJCAAAAA==.Neferturtle:BAAALgADCgEJAQABLgAECgYJBgARAAAAAA==.Neff:BAAALgAECgEJAQAAAA==.Neso:BAAALgAECgUJBAAAAA==.Nessajd:BAAALgAECgMJAwABLgAFFAMJDgAJADwhAA==.Netherburn:BAAALgADCgkJEAAAAA==.Newmoon:BAAALgAECgEJAwAAAA==.Nexkaa:BAAALgADCgIJAgAAAA==.',
Ni='Nianiaa:BAAALgADCgYJAwAAAA==.Niissia:BAAALgADCgYJCQAAAA==.Nikoll:BAAALgADCgkJEgAAAA==.Nimbles:BAAALgAECgMJAwAAAA==.Nimi:BAEBLgAECn8jAAIfAAkJzA38DwBiAQAfAAkJzA38DwBiAQAAAA==.Nindara:BAAALgAECgQJBAAAAA==.Nio:BAACLgAFFH8IAAIGAAQJHge3GwD6AAAGAAQJHge3GwD6AAAuAAQKfx0AAgYACAkzDz8yAIkBAAYACAkzDz8yAIkBAAAA.Niraves:BAAALgADCgEJAQAAAA==.Nith:BAAALgAECgUJBQAAAA==.Nithaa:BAAALgAECgEJAQAAAA==.Nithik:BAAALgADCgMJAwAAAA==.',
Nj='Njalulf:BAAALgADCgYJCQAAAA==.',
No='Nonhealer:BAABLgAECn8VAAMLAAgJhwtvMABOAQALAAgJhwtvMABOAQAEAAEJ5wSgjwAoAAAAAA==.Norisse:BAAALgAECgEJAwAAAA==.Novamane:BAAALgADCgcJCwABLgAECggJGgAXAJsdAA==.Novå:BAABLgAECn8aAAMXAAgJmx3oRgBjAgAXAAgJmx3oRgBjAgAgAAIJBAtkGABVAAAAAA==.',
Oc='Octy:BAAALgAECgIJAgAAAA==.',
Oi='Oin:BAAALgAECgEJAQAAAA==.',
Ol='Oliandia:BAAALgADCgIJAgABLgAECggJGQAmAHkTAA==.',
On='Oneeightytwo:BAAALgADCgYJBgABLgAFFAUJEAASAF8QAA==.Onlydans:BAABLgAECn8jAAInAAkJGgwtFABMAQAnAAkJGgwtFABMAQAAAA==.Onlylight:BAAALgADCgQJBwAAAA==.',
Oo='Oogawagaboo:BAAALgAECgEJAQAAAA==.Oonda:BAAALgADCgEJAQAAAA==.Ooraa:BAAALgADCgUJBgAAAA==.',
Or='Or:BAAALgAECgYJCQAAAA==.Orm:BAABLgAECn8jAAIDAAkJIBIPMABhAQADAAkJIBIPMABhAQAAAA==.Oryine:BAAALgADCgcJCQAAAA==.',
Os='Osamwogru:BAABLgAECn8XAAILAAgJmBpYJgD6AQALAAgJmBpYJgD6AQAAAA==.',
Ov='Overlooker:BAAALgAECgEJAgAAAA==.',
Pa='Paladone:BAAALgADCgQJCAAAAA==.Palanth:BAAALgAECgQJCwAAAA==.Palibro:BAAALgAECgQJBwAAAA==.Palroo:BAAALgADCgEJAQAAAA==.Pandaa:BAAALgAECgMJAwAAAA==.Pangussy:BAAALgADCgUJBQAAAA==.Pannfried:BAAALgADCgQJBAAAAA==.Parripally:BAAALgADCgcJBwABLgAECgMJAwARAAAAAA==.Pastor:BAABLgAECn8VAAIdAAYJMR1KCgDDAQAdAAYJMR1KCgDDAQABLgAECggJKQAXAPYhAA==.Patrik:BAABLgAECn8SAAIHAAgJ2B1ADgBWAgAHAAgJ2B1ADgBWAgAAAA==.Pauladeen:BAAALgAECgYJDgABLgAFFAUJEAASAF8QAA==.',
Pe='Pearlzinha:BAABLgAECn8aAAIKAAgJpgmXDwD0AAAKAAgJpgmXDwD0AAAAAA==.Penta:BAABLgAECn8gAAIYAAkJpiRaBAClAgAYAAkJpiRaBAClAgAAAA==.Peonanoob:BAAALgAECgYJBwAAAA==.Peppep:BAAALgAECgYJDwAAAA==.',
Ph='Phin:BAAALgADCgYJBgAAAA==.Phteven:BAAALgAECgcJCwABLgAFFAUJEAASAF8QAA==.Phuga:BAAALgAECgYJBwAAAA==.',
Pl='Plaguethetnk:BAAALgAECgYJDQAAAA==.Plush:BAABLgAECn8cAAIcAAgJ7weMFABqAQAcAAgJ7weMFABqAQAAAA==.',
Po='Ponix:BAAALgAECgMJAwAAAA==.Pookthyr:BAAALgAECgMJAwABLgAECgkJJgAFAAkSAA==.Pootydk:BAAALgAECgIJAgABLgAECgcJFAAXAI8bAA==.Pootyxd:BAABLgAECn8UAAIXAAcJjxsLcQDxAQAXAAcJjxsLcQDxAQAAAA==.Popedave:BAABLgAECn8nAAIVAAcJXRHfIQA6AQAVAAcJXRHfIQA6AQAAAA==.Portlandian:BAAALgAECgYJCwAAAA==.Poxy:BAAALgAFFAIJAgABLgAFFAQJDAAVANIkAA==.',
Pr='Prathos:BAABLgAECn8bAAIXAAgJ5g7PRACZAQAXAAgJ5g7PRACZAQAAAA==.Praystationn:BAAALgADCgYJCgAAAA==.Prettyfrosty:BAABLgAECn8eAAIXAAgJuiV8BgAHAwAXAAgJuiV8BgAHAwAAAA==.',
Ps='Psychroz:BAAALgAECgYJEQAAAA==.Psykolight:BAAALgADCgIJAgAAAA==.Psywing:BAAALgADCgEJAQABLgAFFAQJDAAVANIkAA==.',
Pu='Puffsummons:BAABLgAECn8pAAMNAAkJyxQiKQDBAQANAAcJUBQiKQDBAQAPAAYJOBG4GQB+AQAAAA==.Purify:BAABLgAECn8jAAIVAAkJlxJzJQC+AQAVAAkJlxJzJQC+AQAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrannor:BAABLgAECn8ZAAIIAAcJOwpMQwBDAQAIAAcJOwpMQwBDAQAAAA==.',
Qe='Qez:BAAALgADCgUJBAAAAA==.',
Qu='Quinifer:BAACLgAFFH8FAAICAAMJCQ1DUQDsAAACAAMJCQ1DUQDsAAAuAAQKfyAAAgIACQkoINIGAO8CAAIACQkoINIGAO8CAAAA.Quinrawr:BAABLgAECn8eAAIkAAgJkxQIFADMAQAkAAgJkxQIFADMAQAAAA==.',
Ra='Raau:BAAALgAECgIJAgABLgAECgkJJAAiAGcdAA==.Rabid:BAAALgADCgMJAwAAAA==.Radamantys:BAACLgAFFH8HAAIIAAMJVRbWJAADAQAIAAMJVRbWJAADAQAuAAQKfzMAAggACQkdIUgFAN0CAAgACQkdIUgFAN0CAAAA.Ragnaroc:BAAALgAECgQJCgAAAA==.Raingoat:BAAALgADCgIJAgAAAA==.Rainshadow:BAAALgAECgYJBgAAAA==.Raygedemon:BAAALgAECgQJBQAAAA==.Rayleigh:BAAALgADCgEJAQAAAA==.Raymongh:BAAALgADCgEJAQAAAA==.Razdurin:BAAALgAECgYJDQAAAA==.Razknight:BAAALgAECgEJAQAAAA==.',
Re='Reagor:BAABLgAECn8SAAIkAAcJiBUbGQCeAQAkAAcJiBUbGQCeAQAAAA==.Redspally:BAAALgADCgEJAQAAAA==.Regenerate:BAABLgAFFH8GAAILAAQJJAYLHgDqAAALAAQJJAYLHgDqAAAAAA==.Reltircfloda:BAAALgAECgQJBgAAAA==.Retnewb:BAABLgAECn8fAAIoAAcJSiNkBABCAgAoAAcJSiNkBABCAgAAAA==.Revecca:BAAALgAECgQJBAAAAA==.Reyz:BAABLgAECn8oAAIXAAgJUSRxCgDRAgAXAAgJUSRxCgDRAgAAAA==.Rezear:BAABLgAECn8UAAMdAAcJUhz6BQClAQAdAAYJ4x36BQClAQAHAAcJ2hI+bwBWAQAAAA==.',
Rh='Rhetchid:BAAALgAECgEJAgAAAA==.',
Ri='Ribz:BAAALgADCgMJAwAAAA==.Rikez:BAAALgAECgYJDAAAAA==.Rivi:BAAALgAECgYJDAAAAA==.Riwwi:BAAALgAECgMJBQAAAA==.',
Ro='Rokrin:BAABLgAFFH8FAAICAAQJWA/pMwA2AQACAAQJWA/pMwA2AQAAAA==.Rook:BAAALgADCgcJAgAAAA==.Rose:BAAALgAECgMJAwAAAA==.Rotnier:BAABLgAFFH8FAAIfAAMJMRhjDADvAAAfAAMJMRhjDADvAAAAAA==.Rowsdower:BAABLgAECn8pAAIkAAkJ5hd6DgAHAgAkAAkJ5hd6DgAHAgAAAA==.',
Rt='Rtcowboy:BAABLgAFFH8PAAIGAAQJ2BuADABSAQAGAAQJ2BuADABSAQAAAA==.',
Ru='Rubez:BAABLgAECn8kAAIXAAgJ1BNKOADBAQAXAAgJ1BNKOADBAQAAAA==.Rufio:BAAALgAECgIJAgABLgAFFAMJBgACAEsVAA==.Rulia:BAAALgADCgIJAgAAAA==.',
Ry='Ryte:BAAALgADCgcJFAAAAA==.',
['Rí']='Rínzler:BAAALgADCgIJAgABLgAECgcJHgAhANIWAA==.',
Sa='Sacerdos:BAAALgAECgYJBgAAAA==.Sacrifeith:BAAALgAECgcJBwAAAA==.Safi:BAABLgAECn8XAAMSAAcJhBh/DgDyAQASAAYJZRl/DgDyAQATAAUJqBK0IAA8AQAAAA==.Saltherion:BAAALgADCgEJAQAAAA==.Sampink:BAABLgAFFH8FAAMIAAMJiQOpLgDSAAAIAAMJiAOpLgDSAAAJAAEJ8AGgHgBBAAAAAA==.Sandya:BAAALgAECgYJBwAAAA==.Sanguiniuss:BAAALgADCgUJBQAAAA==.Sanquites:BAABLgAFFH8FAAIQAAIJYwu+BgCdAAAQAAIJYwu+BgCdAAAAAA==.Sans:BAABLgAECn8cAAILAAcJFRO3JACTAQALAAcJFRO3JACTAQAAAA==.Santilecter:BAAALgAECgQJCwAAAA==.Sayer:BAAALgADCgQJBAAAAA==.',
Sc='Scalebait:BAAALgADCgIJAgAAAA==.Scarletraven:BAAALgAECgEJAQAAAA==.Scenekïng:BAAALgAECgMJBAAAAA==.Scotygrippen:BAACLgAFFH8GAAICAAMJTwKJXgC+AAACAAMJTwKJXgC+AAAuAAQKfxoAAgIACAmIGqhMAA0CAAIACAmIGqhMAA0CAAAA.Scyops:BAABLgAECn8eAAIkAAYJPx0hMADuAQAkAAYJPx0hMADuAQAAAA==.',
Se='Seelzmonk:BAAALgAECgQJBwAAAA==.Seelzz:BAAALgAECgEJAQAAAA==.Seifer:BAABLgAECn8eAAIhAAcJ0hZBEQBdAQAhAAcJ0hZBEQBdAQAAAA==.Selistras:BAABLgAECn8jAAMFAAkJtBseDwD6AQAFAAkJtBseDwD6AQAYAAYJpBnOJwCbAQAAAA==.Sembra:BAACLgAFFH8FAAIoAAMJuRXOBADRAAAoAAMJuRXOBADRAAAuAAQKfyYAAygACAlUIfYCAHwCACgACAlUIfYCAHwCAAEAAgnqENEZAWYAAAAA.',
Sg='Sgkflame:BAAALgAECgUJBgAAAA==.',
Sh='Shada:BAABLgAECn8VAAIMAAYJvAu5KQD2AAAMAAYJvAu5KQD2AAAAAA==.Shadowbones:BAAALgADCgIJAgAAAA==.Shadowhoof:BAAALgAECgMJBAAAAA==.Shadø:BAAALgAECgMJBgAAAA==.Shakenblake:BAAALgADCgYJDwAAAA==.Shammÿ:BAACLgAFFH8LAAIEAAQJeQ9tEQAmAQAEAAQJeQ9tEQAmAQAuAAQKfy4AAgQACQkHIJsFAJMCAAQACQkHIJsFAJMCAAAA.Shayleteo:BAACLgAFFH8MAAIXAAQJVw4aMgBEAQAXAAQJVw4aMgBEAQAuAAQKfywAAhcACAlwIBIaAE4CABcACAlwIBIaAE4CAAAA.Sheyladh:BAAALgAECgYJDQAAAA==.Shindra:BAAALgAECgIJAgAAAA==.Shininami:BAAALgAECgQJCAAAAA==.Shnitez:BAAALgAECgYJCgAAAA==.Shocktea:BAAALgAECgYJDQAAAA==.Shumalon:BAAALgADCgUJCAABLgAECgUJDAARAAAAAA==.Shunt:BAAALgADCgQJBQAAAA==.Shuraina:BAAALgAECgcJDwAAAA==.Shuweg:BAABLgAECn8XAAIXAAgJlRlHRQBoAgAXAAgJlRlHRQBoAgAAAA==.Shylachase:BAAALgAECgUJDAAAAA==.',
Si='Sinjar:BAAALgADCgIJAgAAAA==.',
Sk='Skitzofrenya:BAAALgAECgYJCAAAAA==.Skybreaker:BAAALgAFFAEJAQABLgAFFAQJCwABAKUOAA==.Skylane:BAAALgAECgYJDAAAAA==.',
Sm='Smashthrashn:BAABLgAECn8pAAIkAAkJnBqQBgCHAgAkAAkJnBqQBgCHAgAAAA==.Smittywerben:BAAALgAECgYJBgAAAA==.',
Sn='Snanth:BAACLgAFFH8GAAIXAAMJ4BXdQgAFAQAXAAMJ4BXdQgAFAQAuAAQKfygAAhcACAkNIZQUAHUCABcACAkNIZQUAHUCAAAA.Sneåk:BAAALgADCgEJAQAAAA==.Sniperq:BAAALgAECgEJAQAAAA==.Snurbin:BAAALgADCgUJCQAAAA==.',
So='Sockwater:BAABLgAECn8YAAMEAAcJcAgZUAAHAQAEAAcJxgYZUAAHAQAZAAUJowfsEwDFAAAAAA==.Solarix:BAAALgADCgUJBgAAAA==.Solteris:BAAALgAECgIJAgAAAA==.',
Sp='Spalling:BAABLgAECn8UAAIEAAcJuxGeIQBEAQAEAAcJuxGeIQBEAQAAAA==.Speakeazy:BAAALgAECgYJEwAAAA==.Spelleria:BAAALgADCgcJDgAAAA==.Spinnyme:BAAALgAECgIJAgAAAA==.Sploòp:BAABLgAECn8gAAMNAAkJQxxFCgCmAgANAAkJQxxFCgCmAgAOAAEJAAA2KgBLAAAAAA==.Spoon:BAEBLgAECn8eAAIXAAgJ+CQkBwD9AgAXAAgJ+CQkBwD9AgAAAA==.',
Sq='Squee:BAAALgAECgYJBwABLgAECggJFAAYALgVAA==.',
St='Stalebread:BAAALgADCgcJBwAAAA==.Steelhide:BAABLgAECn8VAAIWAAYJpxeWKgA6AQAWAAYJpxeWKgA6AQAAAA==.Stilledging:BAACLgAFFH8IAAMTAAQJSgOwHgD1AAATAAQJ8AKwHgD1AAASAAEJSwSsCABHAAAuAAQKfyIABBIACAmfEN0RAMIBABIACAmfEN0RAMIBABQABQnTCf8WANQAABMABAnSCGZDAIsAAAAA.Stoopadin:BAAALgAECgEJAQABLgAFFAUJEAAOAEAPAA==.Stoopedholy:BAABLgAECn8nAAMeAAcJBxpPCwAdAgAeAAcJBxpPCwAdAgAVAAMJTAZsagCCAAABLgAFFAUJEAAOAEAPAA==.Stormrunner:BAAALgADCgUJBQAAAA==.Stubborn:BAACLgAFFH8HAAMMAAQJhguLEgAjAQAMAAQJhguLEgAjAQADAAEJogGCSAAwAAAuAAQKfxkABAwACAmlIZYZADoCAAwABwmEIZYZADoCAAMABAnWCTmNALgAACIAAQkPHH8iAFEAAAAA.Stôkes:BAABLgAECn8VAAIXAAYJ2ArsewAZAQAXAAYJ2ArsewAZAQAAAA==.',
Su='Sugardeady:BAAALgADCgUJBQAAAA==.Suhweg:BAAALgAECgEJAwABLgAECggJFwAXAJUZAA==.Sula:BAAALgADCgIJAgAAAA==.Sulthos:BAAALgADCgcJDQABLgAFFAUJEAAHAO4kAA==.Sumata:BAAALgAECgQJBAABLgAECggJIwAfAI0WAA==.Sumato:BAABLgAECn8jAAMfAAgJjRZECQDhAQAfAAgJjRZECQDhAQAkAAIJignbkwBwAAAAAA==.Sunalae:BAAALgADCgcJDgAAAA==.Sunarristia:BAAALgADCgQJBAAAAA==.',
Sy='Sydariel:BAAALgADCgYJBgAAAA==.Syllata:BAACLgAFFH8JAAIDAAUJhxjXDAB3AQADAAUJhxjXDAB3AQAuAAQKfxUAAwMACAkLHbQWAIACAAMACAkLHbQWAIACAAwAAQl5Bc1bAC0AAAAA.Sylvianna:BAABLgAECn8YAAIKAAcJuQ64CgBFAQAKAAcJuQ64CgBFAQAAAA==.Syssä:BAABLgAECn8UAAQMAAcJZxxAGQA9AgAMAAcJYxxAGQA9AgAcAAQJEA+DIQDPAAADAAIJJB5yngCOAAABLgADCgMJAwARAAAAAA==.',
['Sá']='Sátan:BAAALgADCgYJBgAAAA==.',
Ta='Taanwyn:BAAALgAECgQJBwAAAA==.Tacoluv:BAAALgAECgMJBAAAAA==.Tadius:BAAALgADCgQJBAAAAA==.Taladenn:BAAALgADCgEJAQAAAA==.Talahon:BAAALgADCgMJAwABLgAECgUJDQARAAAAAA==.Taoist:BAABLgAECn8aAAQUAAcJ+RJpFQDsAAAUAAYJZhRpFQDsAAATAAUJYwUYQACaAAASAAEJ0QOsGQAqAAAAAA==.Tautog:BAAALgAECggJEwAAAA==.Tayswiftie:BAAALgAECgcJAgAAAA==.',
Tb='Tboo:BAAALgAECgIJAgABLgAFFAMJBwAeADoVAA==.',
Te='Teppic:BAACLgAFFH8FAAIlAAMJXQ4mFQDwAAAlAAMJXQ4mFQDwAAAuAAQKfycAAiUACAnWE7wNAMcBACUACAnWE7wNAMcBAAAA.Teralock:BAABLgAECn8iAAQPAAgJtCTxBQBzAgAPAAcJsR/xBQBzAgANAAUJrSONPQByAQAOAAMJ4hsbCQAGAQAAAA==.Terawar:BAAALgAECgQJDQAAAA==.Tesoni:BAAALgAECgEJAQAAAA==.',
Th='Thebadthing:BAABLgAECn8iAAICAAcJFRM5PgCDAQACAAcJFRM5PgCDAQAAAA==.Thedie:BAAALgAECgcJDQAAAA==.Theegodofwar:BAAALgADCgEJAQAAAA==.Theloudpack:BAACLgAFFH8LAAIBAAQJpQ6PHAA7AQABAAQJpQ6PHAA7AQAuAAQKfxwAAgEACAlHGwpAACYCAAEACAlHGwpAACYCAAAA.Theorem:BAAALgAECgEJAQABLgAECgkJFwAHADAfAA==.Theri:BAAALgAECgUJBwAAAA==.Therla:BAAALgAECgUJDQAAAA==.Thezarien:BAAALgADCgcJCgAAAA==.Thrallamas:BAAALgADCgIJAgAAAA==.Thrallsgf:BAAALgADCgYJCQAAAA==.Thundron:BAAALgAECggJEAAAAA==.',
Ti='Tien:BAAALgAFFAEJAgAAAA==.Tigerius:BAAALgADCgcJBwAAAA==.Tim:BAAALgAECgYJDgAAAA==.Tinly:BAAALgADCgMJAwAAAA==.Tiny:BAABLgAECn8hAAIWAAkJ2iFPDAC4AgAWAAkJ2iFPDAC4AgAAAA==.Tinydingo:BAAALgADCgUJBQAAAA==.Tinytifa:BAABLgAECn8VAAIfAAgJAAlVHgBTAQAfAAgJAAlVHgBTAQAAAA==.Titantelli:BAACLgAFFH8JAAIlAAQJ0RMfCwBUAQAlAAQJ0RMfCwBUAQAuAAQKfx0AAiUACAmVHKkTAHoCACUACAmVHKkTAHoCAAAA.',
Tj='Tjd:BAAALgADCgcJBwAAAA==.',
Tr='Trixibell:BAABLgAECn8cAAIIAAkJaBYdGgACAgAIAAkJaBYdGgACAgAAAA==.Troutmaster:BAAALgAECgEJAQAAAA==.Trutan:BAAALgAECgEJAQAAAA==.',
Ts='Tsoni:BAAALgAECgQJBAAAAA==.',
Tu='Tumultus:BAABLgAECn8YAAIIAAgJZiMTBABPAwAIAAgJZiMTBABPAwAAAA==.Turock:BAABLgAECn8VAAMmAAYJRRMKEgAxAQAmAAYJgBIKEgAxAQAkAAUJZwvfZQAcAQAAAA==.',
Ty='Tylennidar:BAACLgAFFH8NAAINAAUJFw08LQAUAQANAAUJFw08LQAUAQAuAAQKfx4AAw0ABwkqG29VAMcBAA0ABgkqG29VAMcBAA8AAgleEdFOAIEAAAAA.Tylethian:BAAALgADCgQJBgAAAA==.Tyrance:BAABLgAECn8gAAIZAAkJOx1aAgCJAgAZAAkJOx1aAgCJAgAAAA==.',
Ud='Udderchaoz:BAAALgADCgMJAwAAAA==.',
Un='Undeadhate:BAAALgAECgIJAgAAAA==.Underhand:BAAALgAECgYJCwAAAA==.Underscore:BAAALgAECgEJAQAAAA==.Unhallowed:BAABLgAECn8xAAMNAAkJpB1GCADBAgANAAgJpB1GCADBAgAPAAIJzgjSVgBqAAAAAA==.Uninterested:BAAALgAECgEJAgAAAA==.Unrl:BAACLgAFFH8VAAITAAUJMxWgCACkAQATAAUJMxWgCACkAQAuAAQKfyQAAxMACQmLHhMJAOYCABMACQmLHhMJAOYCABIABgm4E9MbAFIBAAAA.',
Up='Upchuck:BAAALgAECgUJCgAAAA==.',
Ur='Urukickpunch:BAAALgAECgYJDQAAAA==.Urumagus:BAAALgADCgYJDAABLgAECgYJDQARAAAAAA==.Urupally:BAAALgADCgcJDgAAAA==.Ururok:BAAALgAECgQJBwABLgAECgYJBwARAAAAAA==.',
Us='Username:BAAALgADCgIJAgAAAA==.',
Va='Vaelendrii:BAAALgADCgEJAQAAAA==.Valynoa:BAAALgADCgcJDQAAAA==.Vanic:BAABLgAECn8aAAINAAcJqxXgNACRAQANAAcJqxXgNACRAQAAAA==.Vanillite:BAABLgAECn8UAAIXAAcJkRRFRgCUAQAXAAcJkRRFRgCUAQAAAA==.',
Ve='Veeronica:BAAALgADCgQJBAAAAA==.Velthari:BAAALgADCgkJIAAAAA==.Verionas:BAAALgAECgYJBwABLgAFFAQJBgANACMVAA==.Vernon:BAAALgADCgYJBgAAAA==.Versal:BAABLgAECn8dAAMTAAgJ8Rc+EgC6AQATAAgJ7hI+EgC6AQASAAYJxxiJFACgAQAAAA==.Versinnia:BAAALgADCgkJCwAAAA==.',
Vh='Vhx:BAAALgAECgYJCwAAAA==.',
Vi='Vibeiety:BAAALgADCgEJAgAAAA==.Vindra:BAAALgADCgEJAQAAAA==.Vixelle:BAAALgAECgYJDQAAAA==.',
Vl='Vladdracule:BAABLgAECn8VAAIlAAYJ+A8PGgAwAQAlAAYJ+A8PGgAwAQAAAA==.Vladimix:BAAALgADCgUJBQAAAA==.Vladski:BAAALgAECgEJAQAAAA==.',
Vm='Vmjecd:BAABLgAECn8bAAIHAAcJ+xX8TgC5AQAHAAcJ+xX8TgC5AQAAAA==.Vmjecw:BAAALgAECgQJDQAAAA==.',
Vo='Voidspauun:BAABLgAECn8iAAMHAAgJsBS9MQBvAQAHAAgJsBS9MQBvAQAdAAMJcg+iIAB/AAAAAA==.Voidthot:BAAALgAECgYJCgAAAA==.Volkov:BAAALgADCgQJBAAAAA==.Vorty:BAABLgAECn8eAAMBAAgJMB3KFgBFAgABAAgJMB3KFgBFAgAoAAIJQwqKQAA7AAAAAA==.',
['Vï']='Vïxenô:BAABLgAECn84AAMLAAkJESOMBAAqAwALAAkJESOMBAAqAwAEAAIJQAdTgABGAAAAAA==.',
Wa='Wanamakeóut:BAAALgADCggJDAAAAA==.Warcook:BAAALgAECgMJBgABLgAECggJNQAHAL4gAA==.Warvessel:BAAALgADCgUJBQAAAA==.Warxiez:BAAALgAECgUJDAAAAA==.Washiki:BAAALgADCgcJCgAAAA==.',
Wh='Whatsthisdo:BAAALgADCgIJAgAAAA==.Whirt:BAABLgAECn8fAAIXAAkJUQ7KPgCrAQAXAAkJUQ7KPgCrAQAAAA==.Whxtxy:BAAALgAECgMJAwAAAA==.',
Wi='Widowmaker:BAACLgAFFH8GAAICAAMJSxX7RwD+AAACAAMJSxX7RwD+AAAuAAQKfyoAAwIACAnOHIY9AEICAAIACAmgGoY9AEICACEACAnWFIASAEsBAAAA.Wildstar:BAACLgAFFH8KAAIZAAQJYxNYAwBBAQAZAAQJYxNYAwBBAQAuAAQKfx8AAhkACAmBIUMFALQCABkACAmBIUMFALQCAAAA.Windglider:BAAALgAECgMJAwAAAA==.Wingsoflife:BAAALgAECgEJAQAAAA==.Wishes:BAAALgAECgYJEAAAAA==.',
Wr='Wrekonize:BAAALgADCgcJDAAAAA==.',
Wt='Wtfnoo:BAAALgAECgcJBwAAAA==.',
Wu='Wurd:BAAALgADCgYJCwAAAA==.',
Xa='Xavilic:BAABLgAECn8ZAAIYAAcJWh96EAB5AgAYAAcJWh96EAB5AgAAAA==.',
Xc='Xcelerator:BAECLgAFFH8IAAIDAAMJkB8JFwAXAQADAAMJkB8JFwAXAQAuAAQKfykAAgMACQlJJf4AAKoDAAMACQlJJf4AAKoDAAAA.',
Xe='Xegion:BAAALgADCgkJCQAAAA==.Xentric:BAAALgAECgEJAQAAAA==.',
Xh='Xhav:BAAALgAECgcJDgAAAA==.Xhavik:BAAALgAECggJCAAAAA==.',
Xx='Xxaraeline:BAAALgAECgMJAwAAAA==.Xxevos:BAAALgADCgQJBAAAAA==.',
Xy='Xylorkian:BAAALgAFFAQJBAABLgAFFAQJDAAVANIkAA==.',
Yo='Yohei:BAAALgADCgMJAwAAAA==.Yonbon:BAAALgAECgYJDQAAAA==.Yourhotnan:BAAALgADCgEJAQAAAA==.',
Yu='Yuhyup:BAABLgAECn8eAAICAAkJFRV5HAAeAgACAAkJFRV5HAAeAgAAAA==.Yurtireigns:BAAALgADCgcJBwAAAA==.Yuupp:BAAALgAECgIJAwAAAA==.',
Za='Zahlxr:BAABLgAECn8lAAIWAAgJth6dDABLAgAWAAgJth6dDABLAgAAAA==.Zallafiel:BAAALgAECgYJBwAAAA==.Zalock:BAAALgAECgMJAwAAAA==.Zapraz:BAAALgAECgYJDgABLgAECgcJEgAkAIgVAA==.',
Ze='Zeero:BAABLgAECn8XAAIWAAcJmh5GCwBeAgAWAAcJmh5GCwBeAgAAAA==.Zelbaljin:BAAALgAECgQJBAAAAA==.Zemah:BAAALgAECgUJDAABLgAECggJFwALAJgaAA==.Zeraphole:BAAALgAECgYJCwAAAA==.Zerolith:BAAALgAECgMJBwAAAA==.',
Zi='Zif:BAAALgAECgUJBQAAAA==.Zirt:BAAALgADCgcJBwAAAA==.',
Zm='Zmamaz:BAAALgAECgcJEQAAAA==.',
Zo='Zoidbergmd:BAABLgAECn8gAAMOAAkJThTPBQBjAQAOAAcJcRLPBQBjAQANAAgJAA7tVAAtAQAAAA==.Zomat:BAAALgAECgYJCgAAAA==.Zomßie:BAAALgAECgcJCAAAAA==.Zoob:BAAALgAECgQJCwABLgAFFAQJDQADAFQeAA==.Zoobook:BAAALgADCgEJAQABLgAECggJJQAYAMofAA==.Zorbrix:BAABLgAECn8jAAIdAAkJsB3ZAwAEAgAdAAkJsB3ZAwAEAgAAAA==.Zoroth:BAAALgAECgUJCAAAAA==.',
Zr='Zrak:BAAALgADCgUJBwAAAA==.',
Zu='Zulgeteb:BAABLgAECn8bAAMEAAgJCBOyGgB5AQAEAAgJCBOyGgB5AQAZAAMJiwB4KQBEAAAAAA==.Zuura:BAACLgAFFH8HAAMaAAMJXRA5EgD3AAAaAAMJXRA5EgD3AAAeAAEJ1wF/GwBBAAAuAAQKfyQAAhoACQkqHzgPAJACABoACQkqHzgPAJACAAAA.',
Zy='Zyrac:BAAALgAECgEJAQAAAA==.',
Zz='Zztank:BAABLgAECn8pAAIoAAkJKiWJAAAoAwAoAAkJKiWJAAAoAwAAAA==.',
['Ât']='Âthénä:BAAALgADCgMJAwAAAA==.',
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

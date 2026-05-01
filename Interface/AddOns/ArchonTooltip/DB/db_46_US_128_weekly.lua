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

local lookup = {'Warrior-Protection','Mage-Frost','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Priest-Discipline','Paladin-Retribution','DemonHunter-Devourer','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Hunter-Survival','Rogue-Outlaw','Shaman-Restoration',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaryn:BAAALgAECgEJAQABLgAECgcJIAABAAQTAA==.',
Ab='Absynthia:BAAALgAECgcJEAAAAA==.',
Ac='Academe:BAABLgAECn8ZAAICAAcJIxMEQABuAQACAAcJIxMEQABuAQAAAA==.Acrid:BAAALgAECgEJAQAAAA==.',
Ad='Ados:BAAALgAECgQJCQAAAA==.',
Ae='Aeity:BAAALgAECgYJCwAAAA==.Aellion:BAAALgADCgEJAQAAAA==.Aellopus:BAAALgAECgEJAQAAAA==.Aenas:BAAALgAECgcJDgAAAA==.Aero:BAABLgAECn8gAAMBAAcJBBOlCwBqAQABAAcJjRGlCwBqAQADAAYJZw6HFwA+AQAAAA==.',
Af='Afflictedd:BAAALgAECgEJAQAAAA==.',
Ag='Agapetus:BAAALgADCgYJBgAAAA==.',
Ah='Ahren:BAAALgAECgQJCwAAAA==.',
Ak='Akata:BAAALgADCgcJBwAAAA==.',
Al='Alayder:BAAALgADCgYJBgAAAA==.Almighty:BAAALgAECgMJAwAAAA==.Alomeo:BAAALgADCggJDAAAAA==.',
Am='Amarí:BAAALgADCggJGAAAAA==.Amayêlle:BAAALgADCggJGAAAAA==.Amendos:BAAALgAECgYJCQAAAA==.Amiliane:BAABLgAECn8eAAQEAAcJIQ3xCQAFAQAEAAUJeQzxCQAFAQAFAAUJ5gspWgDjAAAGAAQJvgpYHQCHAAAAAA==.Amunshi:BAAALgADCgQJBAAAAA==.Amz:BAAALgAECgMJBgAAAA==.',
An='Anadrien:BAABLgAECn8gAAMHAAcJ4RyxEQD/AQAHAAcJ4RyxEQD/AQAIAAMJyw0lLQCoAAAAAA==.Ancelagon:BAAALgADCgYJBgAAAA==.Andrae:BAAALgAECgUJBQAAAA==.Andrastae:BAAALgAECgYJBgAAAA==.Angrima:BAAALgAECgEJAQAAAA==.Angrimia:BAABLgAECn8gAAIJAAcJIhxsCQCAAQAJAAcJIhxsCQCAAQAAAA==.Anju:BAAALgAECgEJAgAAAA==.Ansticé:BAAALgADCgYJBgAAAA==.Antal:BAAALgAECgEJAQAAAA==.Anthelyn:BAAALgADCgcJBwAAAA==.',
Ar='Arannis:BAAALgADCgcJCQAAAA==.Arboria:BAAALgAECggJBQAAAA==.Archielgh:BAAALgAECgYJEQAAAA==.Areldor:BAAALgADCggJCgAAAA==.Aremethea:BAAALgADCgQJBwABLgAECgQJCQAKAAAAAA==.Ariaa:BAAALgADCggJDAAAAA==.Arkannah:BAAALgADCgcJBwAAAA==.Aronk:BAABLgAECn8eAAQLAAcJORInIgDYAAAMAAUJ3Ra4PgBKAQALAAUJDA0nIgDYAAANAAcJ6gLdKAC8AAAAAA==.Arore:BAAALgADCgEJAQABLgAECgcJHgALADkSAA==.Aroreck:BAAALgADCgMJAwABLgAECgcJHgALADkSAA==.Arorepriest:BAAALgADCgcJBwABLgAECgcJHgALADkSAA==.Articulàte:BAAALgAECgQJBAAAAA==.Arzec:BAABLgAECn8ZAAIOAAYJcAbvEQDbAAAOAAYJcAbvEQDbAAAAAA==.',
At='Atheania:BAAALgAECgkJAwAAAA==.',
Av='Avestara:BAABLgAECn8gAAIPAAcJSx0OCQACAgAPAAcJSx0OCQACAgAAAA==.',
Aw='Awenlock:BAEALgADCgUJBAAAAA==.',
Ay='Ayluid:BAAALgAECgUJCwAAAA==.',
Az='Azavtani:BAAALgADCgEJAQAAAA==.Azazill:BAAALgAECgYJCwAAAA==.Azeralle:BAAALgADCgkJCgAAAA==.Azmodeus:BAAALgAECgMJAwAAAA==.Azoril:BAABLgAECn8iAAIQAAgJNRGsJQCtAQAQAAgJNRGsJQCtAQAAAA==.Azùla:BAAALgADCgcJBwAAAA==.',
['Aí']='Aídeen:BAAALgAECgYJDAAAAA==.',
Ba='Baal:BAAALgADCgcJEQAAAA==.Babaspook:BAAALgAECggJCwAAAA==.Badseedz:BAAALgAECgYJBgAAAA==.Baelnorn:BAABLgAECn8dAAMFAAgJthpQGwDRAQAFAAcJgBtQGwDRAQAEAAMJ9RbvSgCNAAAAAA==.Bains:BAAALgADCgcJBwAAAA==.Baja:BAAALgAECgQJBwAAAA==.Bandit:BAAALgAECgUJCgAAAA==.Barress:BAAALgADCgEJAQAAAA==.Batrela:BAAALgAECgYJDwAAAA==.Battleturtle:BAAALgAECgYJCwAAAA==.Batôsai:BAAALgAECgEJAQAAAA==.Bazir:BAAALgAECgIJAgABLgAFFAQJCQACAIcRAA==.',
Bd='Bddaddy:BAAALgAECgMJBAAAAA==.',
Be='Bearjuu:BAAALgAECgIJAwABLgAECgkJHAARAPUbAA==.Bearpawz:BAABLgAECn8hAAISAAkJNBjjAQBsAgASAAkJNBjjAQBsAgAAAA==.Bearrel:BAAALgAECgYJCwAAAA==.Bearrier:BAAALgADCgEJAQAAAA==.Bekens:BAABLgAECn8UAAITAAYJrSQsIgA4AgATAAYJrSQsIgA4AgAAAA==.Belaraariaae:BAAALgADCgQJBAAAAA==.Benastiel:BAAALgADCgYJBwAAAA==.Benwetta:BAAALgAECgMJAwAAAA==.Bernardboggs:BAAALgAECgYJDgAAAA==.Bethbathory:BAABLgAECn8fAAIGAAgJChdqAQADAgAGAAgJChdqAQADAgAAAA==.',
Bh='Bheefknight:BAAALgAECgQJDQAAAA==.',
Bi='Bierbro:BAABLgAECn8VAAIUAAcJfhHpTAAZAQAUAAcJfhHpTAAZAQAAAA==.Bigfacts:BAAALgAECggJDAAAAA==.Bigoldee:BAAALgADCgUJBQAAAA==.Bigyk:BAAALgADCgYJBgAAAA==.Billié:BAABLgAECn8bAAQFAAgJvyGZBgCkAgAFAAcJfyGZBgCkAgAEAAMJ5iABKQAfAQAGAAEJ1h3iLABFAAAAAA==.',
Bk='Bk:BAAALgADCgMJAwAAAA==.',
Bl='Blightheaded:BAAALgAECgQJBwABLgAECgcJCQAKAAAAAA==.Blindëye:BAAALgAECgYJDQAAAA==.Blumir:BAAALgAECgYJCAAAAA==.',
Bn='Bnththeocean:BAAALgAECggJEAAAAA==.',
Bo='Bobmauley:BAAALgADCgQJBAAAAA==.Bombkin:BAABLgAECn8gAAIHAAcJCSRxCgBiAgAHAAcJCSRxCgBiAgAAAA==.Bonchonn:BAABLgAECn8bAAITAAgJGiBzDgDIAgATAAgJGiBzDgDIAgAAAA==.Bonkula:BAAALgAECgYJEwAAAA==.Boondox:BAAALgAECgMJAwAAAA==.Bootyfeastr:BAAALgADCgEJAwAAAA==.Bops:BAAALgADCgQJBAAAAA==.',
Br='Brae:BAAALgAECgYJCAAAAA==.Bralitha:BAAALgADCgEJAQAAAA==.Braumbastic:BAAALgADCgUJBQAAAA==.Brazonk:BAAALgADCgkJCQAAAA==.Brewzco:BAABLgAECn8oAAIMAAkJ+x8QAQAIAwAMAAkJ+x8QAQAIAwAAAA==.Bricifergoat:BAABLgAFFH8UAAIVAAUJ9SVeAgC5AQAVAAUJ9SVeAgC5AQABLgAFFAMJCgAUAIQmAA==.Briciferkong:BAACLgAFFH8KAAIUAAMJhCamFgBXAQAUAAMJhCamFgBXAQAuAAQKfxYAAxQABwklH3RQAAACABQABwklH3RQAAACABYAAQknCJ0YAC0AAAAA.Briciferyeah:BAAALgADCgQJBAABLgAFFAMJCgAUAIQmAA==.Brightblayde:BAABLgAECn8gAAIQAAcJZxv5IADFAQAQAAcJZxv5IADFAQAAAA==.Brique:BAAALgADCggJDAABLgAECgYJDQAKAAAAAA==.',
Bu='Buanto:BAAALgAECgMJBgAAAA==.Bubblegumm:BAABLgAECn8YAAIHAAcJ3hI8KgA7AQAHAAcJ3hI8KgA7AQAAAA==.Bubieh:BAAALgAECgQJBQABLgAECggJHAAJACsjAA==.Bullshatner:BAAALgADCgMJAwAAAA==.Bumpinlumps:BAAALgAECgQJBAAAAA==.Bushwookiee:BAAALgAECgYJCAAAAA==.Butterknight:BAACLgAFFH8IAAIUAAMJLBRtSACxAAAUAAMJLBRtSACxAAAuAAQKfyIAAhQACAnYI0QWAPYCABQACAnYI0QWAPYCAAAA.Buttertotem:BAAALgAFFAIJAgAAAA==.',
Ca='Caanu:BAAALgADCgUJBwAAAA==.Calypso:BAAALgAECgMJAwAAAA==.Candlelock:BAAALgAECgYJBwAAAA==.Carirmonk:BAAALgAECgEJAQAAAA==.Cattroll:BAABLgAECn8YAAIHAAgJECJ9BgCvAgAHAAgJECJ9BgCvAgAAAA==.',
Cd='Cdubb:BAAALgAECgYJDgAAAA==.',
Ce='Celidori:BAAALgAECggJDgABLgAECggJGAAHABAiAA==.Celithila:BAABLgAECn8eAAMXAAcJ7BPaEQCOAQAXAAcJ7BPaEQCOAQAPAAEJ/QY3WQAwAAAAAA==.Celithvia:BAAALgAECgcJEwAAAA==.Ceroin:BAAALgADCgEJAQAAAA==.Cervantés:BAABLgAECn8iAAMYAAkJDBtVAwBvAgAYAAkJ6xVVAwBvAgAZAAcJMBtMBgAVAgAAAA==.',
Ch='Chaia:BAABLgAECn8ZAAIHAAcJ5hUjIgBwAQAHAAcJ5hUjIgBwAQAAAA==.Chelsea:BAAALgAECgEJAQAAAA==.Cherra:BAAALgAECgYJBgABLgAECgcJEwAKAAAAAA==.Chise:BAABLgAECn8YAAIPAAcJhhN1HQCpAQAPAAcJhhN1HQCpAQAAAA==.Chrispyloa:BAAALgAECgQJCwAAAA==.Chubs:BAABLgAECn8ZAAMEAAcJfxhRDgDjAQAEAAcJoxdRDgDjAQAFAAUJPRNqvgDcAAAAAA==.',
Cl='Clann:BAABLgAECn8UAAICAAYJChCGXAAkAQACAAYJChCGXAAkAQAAAA==.Cly:BAAALgAECgYJDgAAAA==.Clydk:BAAALgAECgEJAgABLgAECgYJDgAKAAAAAA==.',
Co='Coachbeard:BAABLgAECn8uAAIaAAkJ6RCHEgDGAQAaAAkJ6RCHEgDGAQAAAA==.Colzamenta:BAABLgAFFH8IAAIRAAQJVQ5cHwDqAAARAAQJVQ5cHwDqAAAAAA==.Colzaratha:BAAALgAECgUJBQAAAA==.Contract:BAAALgAECgUJBQAAAA==.Corpsereth:BAAALgAECgkJAwAAAA==.',
Cr='Creamcicle:BAAALgADCgEJAQAAAA==.Crispytots:BAAALgAECgcJDAAAAA==.Crit:BAAALgAECgQJBQABLgAECggJGAALAM8VAA==.Critmypantz:BAABLgAECn8YAAILAAgJzxXbIADQAQALAAgJzxXbIADQAQAAAA==.Crosby:BAAALgADCgUJBQAAAA==.',
Cu='Cudguzzler:BAAALgADCggJCQAAAA==.Cursegoesmoo:BAACLgAFFH8JAAIUAAQJuBxPFABeAQAUAAQJuBxPFABeAQAuAAQKfxcAAhQACAk9IoUfAMQCABQACAk9IoUfAMQCAAAA.',
Cy='Cygna:BAABLgAECn8yAAITAAgJjiFxBwCAAgATAAgJjiFxBwCAAgAAAA==.Cyntheria:BAABLgAECn8fAAIQAAgJvBw9JgCNAgAQAAgJvBw9JgCNAgAAAA==.',
Da='Daddybeàr:BAAALgAECgQJBQAAAA==.Daendron:BAAALgADCgQJBAAAAA==.Dajubah:BAABLgAECn8fAAIBAAgJ4BmbBQABAgABAAgJ4BmbBQABAgAAAA==.Dammitdave:BAABLgAECn8aAAIQAAYJfwsVVQAPAQAQAAYJfwsVVQAPAQAAAA==.Dangereuse:BAAALgAECgQJBQAAAA==.Darinell:BAAALgAECgUJCwAAAA==.Darksaxon:BAAALgAECgYJEgAAAA==.',
De='Deathnethal:BAAALgAECgQJCAAAAA==.Deathweaver:BAAALgAECgMJAwAAAA==.Deebbzmonk:BAAALgAFFAIJAgAAAA==.Deeno:BAAALgAECgEJAwAAAA==.Defrausted:BAAALgAECggJCAAAAA==.Deltaco:BAAALgAECgQJBAABLgAFFAMJBwATALEWAA==.Deme:BAAALgADCgcJCgAAAA==.Demonica:BAAALgAECgcJEwAAAA==.Demonseedz:BAAALgAECgEJAgAAAA==.Dendrax:BAABLgAECn8XAAIFAAcJzQUdRgAeAQAFAAcJzQUdRgAeAQAAAA==.Dented:BAABLgAECn8aAAIQAAcJFQokcQDMAAAQAAcJFQokcQDMAAAAAA==.Derivation:BAAALgAECgQJCwAAAA==.Destitute:BAAALgAECgUJBQAAAA==.Detaren:BAAALgADCgEJAQAAAA==.Dethwing:BAAALgAECgIJBAAAAA==.Devadeity:BAABLgAECn8cAAIXAAcJHhSwFwBNAQAXAAcJHhSwFwBNAQAAAA==.Deviance:BAAALgAECgYJEAAAAA==.Devola:BAAALgADCgkJFAAAAA==.',
Di='Didntask:BAAALgADCgEJAQABLgAECggJGwAJAIQOAA==.Dienmage:BAABLgAECn8fAAIbAAgJWh44AQAKAgAbAAgJWh44AQAKAgAAAA==.Digìt:BAAALgAECgIJAgABLgAECgcJGgAXAC4dAA==.Dirtychai:BAABLgAECn8YAAIXAAYJsSASCAArAgAXAAYJsSASCAArAgAAAA==.Dissonance:BAAALgAECgEJAgAAAA==.Diurd:BAAALgAECgEJAQAAAA==.Divine:BAAALgADCgYJBgAAAA==.',
Dj='Djanga:BAABLgAECn8fAAMIAAgJCCNOAgDMAgAIAAgJCCNOAgDMAgAHAAQJuxodZAAlAQAAAA==.',
Dk='Dkchocobussy:BAAALgADCgMJAwAAAA==.Dkdiso:BAAALgADCgIJAgAAAA==.',
Do='Doctorevil:BAAALgAECgYJEAAAAA==.Dogglefrog:BAAALgADCgEJAQAAAA==.Dominance:BAAALgADCgEJAwAAAA==.Doranthsæ:BAAALgADCgcJBwABLgAECggJIAAIAOoaAA==.Dorito:BAAALgAFFAIJAgAAAA==.Dothausen:BAAALgAECgYJBgAAAA==.',
Dr='Dracaaron:BAAALgAECgUJBwAAAA==.Dragonevil:BAAALgADCgYJBgAAAA==.Dragooned:BAACLgAFFH8HAAICAAQJkhQkKgAMAQACAAQJkhQkKgAMAQAuAAQKfxQAAgIABwklJAwuALkCAAIABwklJAwuALkCAAAA.Dragussy:BAAALgAECgQJBAAAAA==.Drakenallure:BAAALgAECgkJEAAAAA==.Drakkisath:BAABLgAECn8gAAMcAAcJAhWSEwBnAQAcAAcJ8BSSEwBnAQAdAAUJNxMVCgDQAAAAAA==.Draknethal:BAAALgAECgIJAgAAAA==.Dramn:BAAALgADCgMJAwAAAA==.Drango:BAABLgAECn8WAAIdAAgJ2wMsCAABAQAdAAgJ2wMsCAABAQAAAA==.Draugdae:BAABLgAECn8eAAIeAAcJdh6sAwD/AQAeAAcJdh6sAwD/AQAAAA==.Drayslinger:BAAALgAECgIJAgAAAA==.Dreki:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.Drinksomuch:BAAALgADCgIJAgAAAA==.Drlechee:BAAALgADCgMJBQAAAA==.Drob:BAEALgADCgkJFQAAAA==.Drukhi:BAABLgAECn8bAAITAAgJMhriFQDjAQATAAgJMhriFQDjAQAAAA==.Drunkalicius:BAAALgAFFAEJAgAAAA==.',
Du='Dudepriest:BAAALgAECgYJEQAAAA==.Dungrough:BAAALgAECgIJAwAAAA==.Durtkal:BAABLgAECn8mAAMFAAgJgBJiHwC5AQAFAAgJDRFiHwC5AQAEAAYJZw7oHwBTAQAAAA==.',
Dw='Dwarlin:BAAALgADCgkJCQAAAA==.',
Dy='Dyonn:BAAALgADCgEJAgAAAA==.',
['Dê']='Dêädpool:BAAALgADCgYJBgAAAA==.',
Ed='Edgeboy:BAAALgAECgYJCgABLgAFFAQJCQACAIcRAA==.',
Ef='Efarel:BAABLgAECn8rAAIfAAgJdxSRDwDAAQAfAAgJdxSRDwDAAQAAAA==.Efil:BAAALgADCgkJHgAAAA==.',
El='Eleantha:BAAALgADCgYJBwAAAA==.Elinisar:BAAALgAECgUJBgAAAA==.Elsa:BAABLgAECn8eAAICAAgJ3Ay6OQCCAQACAAgJ3Ay6OQCCAQAAAA==.Elzza:BAAALgADCgYJCQAAAA==.',
Em='Embear:BAAALgADCgcJEAAAAA==.',
En='Enjaydin:BAAALgAECgUJBQAAAA==.Enjaydo:BAABLgAECn8iAAICAAgJOx4xEgBKAgACAAgJOx4xEgBKAgAAAA==.',
Ep='Epicfurry:BAAALgAECgUJCwAAAA==.',
Er='Ereile:BAAALgAECgUJCAAAAA==.Errlhickey:BAAALgADCgUJCQAAAA==.',
Es='Escanor:BAAALgADCgYJBgAAAA==.',
Eu='Eukelade:BAAALgADCgcJBwAAAA==.Eurythmics:BAABLgAECn8gAAITAAcJUxUBIgCWAQATAAcJUxUBIgCWAQAAAA==.',
Ev='Evileen:BAAALgAECgEJAQAAAA==.Evonahh:BAAALgADCgcJEwAAAA==.',
Ex='Exelion:BAABLgAECn8dAAIXAAgJAR4KCAAsAgAXAAgJAR4KCAAsAgAAAA==.Explogan:BAAALgAECgYJBwAAAA==.',
Ez='Ezanah:BAAALgADCgUJBQAAAA==.Ezrack:BAAALgADCgEJAQAAAA==.',
Fa='Faeyrin:BAABLgAECn8eAAIWAAgJgRDcBABSAQAWAAgJgRDcBABSAQAAAA==.Fahooquazaad:BAAALgADCgkJHQAAAA==.Falconsg:BAAALgADCgQJBAAAAA==.Fancy:BAAALgAECggJEwAAAA==.Faythlis:BAABLgAECn8YAAIFAAYJiAzVRwAZAQAFAAYJiAzVRwAZAQAAAA==.',
Fe='Feetlesmcdee:BAAALgAECgcJDgAAAA==.Felf:BAAALgADCgcJBwAAAA==.Felfáádaern:BAEBLgAECn8ZAAQgAAcJXQ18EQAoAQAgAAcJXQ18EQAoAQARAAIJKgEA3wAzAAAhAAEJsAXiLQAoAAAAAA==.Felporch:BAAALgAECgYJEAAAAA==.',
Fi='Filburt:BAAALgADCgEJAQAAAA==.',
Fk='Fkton:BAAALgADCgIJAgAAAA==.',
Fl='Flamediso:BAAALgADCgUJBQAAAA==.Flourchild:BAAALgADCgEJAQAAAA==.Flowermound:BAAALgAECgQJBQAAAA==.Flowerrose:BAAALgADCgYJBgAAAA==.',
Fo='Forrester:BAAALgAECgYJEAAAAA==.Fox:BAACLgAFFH8NAAIXAAUJfyLvAADuAQAXAAUJfyLvAADuAQAuAAQKfxoAAhcACAkXHg0LAJ4CABcACAkXHg0LAJ4CAAAA.',
Fr='Freight:BAAALgADCgMJAwAAAA==.Friedcry:BAAALgADCgYJBgAAAA==.Fron:BAAALgAECgMJBgAAAA==.Fronie:BAAALgADCgcJAwAAAA==.',
Fu='Fujikujaku:BAABLgAECn8UAAIHAAcJGBAXJwBOAQAHAAcJGBAXJwBOAQAAAA==.Fulmetal:BAAALgAECgQJBAAAAA==.Funerris:BAAALgADCgEJAQABLgAFFAUJCQAiAEgIAA==.Funiris:BAACLgAFFH8JAAIiAAUJSAhdBQB3AQAiAAUJSAhdBQB3AQAuAAQKfxUAAyIABwnsFekoAJMBACIABwnsFekoAJMBAA8ABQmKDiQyABABAAAA.Funkalicious:BAACLgAFFH8KAAIVAAMJohAPEgDuAAAVAAMJohAPEgDuAAAuAAQKfyYAAhUACQmfHbIDAJECABUACQmfHbIDAJECAAAA.',
['Fé']='Félo:BAABLgAECn8fAAMEAAcJEiHxAQALAgAEAAYJECTxAQALAgAFAAIJlBe4eACTAAAAAA==.',
Ga='Garathor:BAAALgAECgEJAgAAAA==.Garthoneeye:BAAALgAECgQJCAAAAA==.Gazreyna:BAAALgAECgcJEwAAAA==.',
Gc='Gcarne:BAABLgAECn8bAAIHAAgJsQjsLQAnAQAHAAgJsQjsLQAnAQAAAA==.',
Ge='Genz:BAAALgADCgEJAQAAAA==.Genós:BAABLgAECn8eAAMBAAgJ0Ro5CACzAQAfAAcJ8Bo8NQDUAQABAAcJ0xc5CACzAQAAAA==.Gerardo:BAAALgAECgMJBgAAAA==.',
Gh='Ghurri:BAAALgADCgQJBgAAAA==.',
Gi='Gibs:BAAALgAECgYJCgAAAA==.Ginnee:BAAALgAECgEJAwAAAA==.Ginnion:BAABLgAECn8UAAIOAAcJTRf9CACTAQAOAAcJTRf9CACTAQAAAA==.Girthytail:BAAALgAECgYJEQAAAA==.',
Gl='Glaedor:BAAALgAECgQJBAAAAA==.Glakenspheal:BAABLgAECn8bAAIPAAcJ9gy7EwBcAQAPAAcJ9gy7EwBcAQAAAA==.Glamorous:BAAALgAECgYJCQAAAA==.Glein:BAAALgADCgMJAwABLgAECgcJGwALAMQeAA==.',
Go='Gongfu:BAAALgADCgYJBgAAAA==.Goonie:BAAALgAECgYJCAAAAA==.',
Gr='Graestoke:BAABLgAECn8YAAICAAgJ1x9nNAChAgACAAgJ1x9nNAChAgAAAA==.Graevana:BAAALgADCgEJAQAAAA==.Gregorizz:BAAALgAECgEJBAAAAA==.Greyaura:BAAALgAECgQJBAAAAA==.Greybeast:BAAALgAECgYJDAAAAA==.Greyfoxy:BAAALgAECgYJDAAAAA==.Grianick:BAAALgAECgUJBQABLgAECgcJDwAKAAAAAA==.Growls:BAABLgAECn8aAAMHAAcJuhphGwCkAQAHAAYJaRlhGwCkAQAeAAcJBBEvCQBDAQAAAA==.',
Gu='Gurri:BAAALgAECgIJAgAAAA==.',
Gy='Gyaat:BAAALgADCggJDwAAAA==.',
['Gõ']='Gõldenchild:BAAALgAECgQJCwAAAA==.',
Ha='Habenero:BAABLgAECn8UAAIjAAUJUQrcDgDiAAAjAAUJUQrcDgDiAAAAAA==.Hagar:BAABLgAECn8XAAISAAcJChMcCAByAQASAAcJChMcCAByAQAAAA==.Hairycow:BAAALgADCgYJBgAAAA==.Hairypitts:BAABLgAECn8bAAISAAgJ7BTvAwD6AQASAAgJ7BTvAwD6AQAAAA==.Haittou:BAAALgAECgkJBQAAAA==.Halligan:BAAALgADCgUJBQAAAA==.Hammertime:BAAALgAECgcJDgAAAA==.Harabrew:BAAALgADCggJDAAAAA==.Haraniantha:BAAALgAECgcJEwAAAA==.Hardø:BAAALgADCgcJCAAAAA==.Hatean:BAAALgADCgcJBwABLgAECgYJBwAKAAAAAA==.Hazzbek:BAAALgADCgUJBQAAAA==.',
He='Heiboss:BAAALgAECgQJBQABLgAECggJHAAJACsjAA==.Heipal:BAAALgADCgYJBgABLgAECggJHAAJACsjAA==.Heiranir:BAAALgADCgYJEgABLgAECggJHAAJACsjAA==.Hellbane:BAAALgAECgQJCgAAAA==.Hemit:BAAALgAECgMJAwABLgAECggJGAACANcfAA==.Hempknight:BAAALgADCgQJBQAAAA==.',
Hi='Hickups:BAAALgAECgMJAwABLgAECgkJLgAaAOkQAA==.Hikikomori:BAAALgAECgYJBgABLgAECgkJJAAJACAiAA==.Hinomiko:BAAALgAECgMJBgABLgAECgYJDwAKAAAAAA==.',
Ho='Holycowch:BAAALgAECgcJEwAAAA==.Honeyb:BAAALgAECgQJCwAAAA==.Hoodieallen:BAAALgADCgQJBAAAAA==.Hoofthor:BAAALgADCgEJAQAAAA==.Hootiedixon:BAAALgAECgYJDAAAAA==.',
Hu='Hughjaculate:BAAALgAECgUJCQAAAA==.Huran:BAABLgAECn8cAAMJAAgJKyOCBgDOAgAJAAgJKyOCBgDOAgAUAAEJuwi6HwE2AAAAAA==.',
Id='Idcritthat:BAABLgAECn8VAAMZAAYJ7RhvCgCMAQAZAAYJaxVvCgCMAQAYAAMJFA8uVgB2AAABLgAECggJGAALAM8VAA==.',
Ig='Ignignokt:BAEBLgAECn8iAAMTAAgJGCK1DADaAgATAAgJGCK1DADaAgAkAAEJzhqwhwA0AAAAAA==.Igvoker:BAEALgAECgYJBgABLgAECggJIgATABgiAA==.',
Il='Illadont:BAAALgADCgEJAQAAAA==.Illith:BAAALgADCgEJAQAAAA==.',
Im='Imirohe:BAABLgAECn8VAAMCAAcJrggouwBrAQACAAcJrggouwBrAQAbAAEJoQOSIgAcAAAAAA==.',
In='Inarush:BAABLgAECn8fAAIhAAgJMQZjCQAOAQAhAAgJMQZjCQAOAQAAAA==.',
Ir='Ira:BAAALgADCgIJAgAAAA==.Ironfistt:BAAALgADCgYJBgAAAA==.Ironknife:BAAALgADCggJGAAAAA==.Ironshield:BAACLgAFFH8HAAITAAMJsRZ7FwAIAQATAAMJsRZ7FwAIAQAuAAQKfxwAAhMACQlnIJcFADMDABMACQlnIJcFADMDAAAA.',
Iv='Ivie:BAAALgAECgQJBgAAAA==.',
Iw='Iwishiknew:BAABLgAECn8aAAIfAAgJcA2WEQCsAQAfAAgJcA2WEQCsAQAAAA==.',
Iz='Iztras:BAAALgAECgIJBQAAAA==.Izuras:BAAALgAECgkJBwAAAA==.Izzit:BAAALgAECgQJCwAAAA==.',
Ja='Ja:BAABLgAECn8ZAAICAAgJcRhoJgDMAQACAAgJcRhoJgDMAQAAAA==.Jabbtrak:BAAALgAECgYJDwAAAA==.Jabtrakk:BAAALgADCggJCAAAAA==.Jacodin:BAAALgAECgYJDgAAAA==.Jacquestrapp:BAAALgADCgkJDAAAAA==.Jakiepoobear:BAAALgAECgYJDQAAAA==.Jambie:BAABLgAECn8UAAQFAAcJGxVKpwAKAQAFAAUJxBZKpwAKAQAEAAIJUQzMUQB5AAAGAAEJywy2LwA/AAAAAA==.',
Je='Jedery:BAABLgAECn8YAAIlAAYJpRTBGQBDAQAlAAYJpRTBGQBDAQAAAA==.',
Jg='Jgglephysyx:BAAALgAECgkJBgAAAA==.',
Ji='Jianyü:BAABLgAECn8fAAIQAAgJ2RwGJQCTAgAQAAgJ2RwGJQCTAgAAAA==.Jimbæn:BAAALgADCgYJCAAAAA==.',
Jo='Jollyandy:BAEALgAECgcJDgAAAA==.Jolynn:BAABLgAECn8bAAImAAgJ1guuEQBJAQAmAAgJ1guuEQBJAQAAAA==.Joroldess:BAABLgAECn8bAAIlAAgJ3xXPCACBAQAlAAgJ3xXPCACBAQAAAA==.',
Ju='Juzam:BAAALgAECgMJAwAAAA==.',
['Jü']='Jüggernaut:BAAALgAECgMJAwAAAA==.',
Ka='Kahndumb:BAAALgAECgcJEwAAAA==.Kaida:BAAALgAECgUJBQAAAA==.Kaio:BAAALgADCgMJAwAAAA==.Kalahan:BAAALgAECgYJEAAAAA==.Kalimaa:BAAALgAECgYJCwAAAA==.Kaotut:BAAALgADCgQJBAAAAA==.Kappakappa:BAAALgAECgMJAwAAAA==.Kardrion:BAAALgAECgIJAgAAAA==.Karigyn:BAABLgAECn8gAAIZAAcJJiNdAQBQAgAZAAcJJiNdAQBQAgAAAA==.Karun:BAABLgAECn8jAAIWAAgJxhOCAgDRAQAWAAgJxhOCAgDRAQAAAA==.Kasok:BAAALgAECgYJDgAAAA==.Katren:BAAALgADCgUJBQAAAA==.Katrienne:BAABLgAECn8WAAIlAAYJdwUcKQDBAAAlAAYJdwUcKQDBAAAAAA==.Katrya:BAAALgADCgkJFQABLgAECgYJFgAlAHcFAA==.Katsfood:BAAALgADCgkJFQAAAA==.Kauzarukus:BAAALgAECgcJBgAAAA==.Kaylid:BAABLgAECn8bAAInAAcJ4hqxAgCuAQAnAAcJ4hqxAgCuAQAAAA==.Kaylou:BAAALgADCgcJBwABLgAECgcJIAAQAIMLAA==.Kazeralana:BAAALgAECgUJBQAAAA==.Kazzoth:BAABLgAECn8eAAITAAgJ1RAjHgCrAQATAAgJ1RAjHgCrAQAAAA==.',
Ke='Keeiras:BAAALgAECgkJCgAAAA==.Keilen:BAAALgADCgUJBAAAAA==.Kelasha:BAABLgAECn8dAAIUAAYJMR96LwB8AQAUAAYJMR96LwB8AQAAAA==.',
Kh='Khadgär:BAAALgAECgYJDwAAAA==.Khalika:BAAALgAECgUJBgAAAA==.Kharanys:BAAALgADCgcJBwAAAA==.',
Ki='Kilroar:BAAALgADCgkJCQAAAA==.Kinoplex:BAAALgAECgEJAgABLgAECgMJAwAKAAAAAA==.',
Kl='Klassiq:BAAALgADCgUJBQAAAA==.Klax:BAAALgADCgkJDwAAAA==.Klokateer:BAABLgAECn8cAAMZAAgJIRinBQAuAgAZAAgJ4BenBQAuAgAYAAUJ4w/YOgBCAQAAAA==.Klzx:BAABLgAECn8eAAICAAcJPhdYMQCeAQACAAcJPhdYMQCeAQAAAA==.',
Ko='Kobold:BAAALgAECgMJAwABLgAECgUJBQAKAAAAAA==.Komo:BAAALgADCgcJBwAAAA==.Komoou:BAAALgAECgQJBAAAAA==.Komouo:BAAALgADCgMJAwABLgADCgcJBwAKAAAAAA==.Korbi:BAAALgADCgcJGAABLgAECgcJHAAVAG8YAA==.Kortek:BAABLgAECn8WAAIcAAgJcgJkJwDSAAAcAAgJcgJkJwDSAAAAAA==.Korvold:BAAALgAECgcJCwAAAA==.Kosmos:BAAALgAECggJEAAAAA==.Kozath:BAAALgAECgQJCAAAAA==.',
Kr='Kreckon:BAAALgAECgUJCAAAAA==.Kriandor:BAAALgAECgEJAgAAAA==.',
Ks='Kschnell:BAAALgAECgEJAQABLgAFFAQJCQACAIcRAA==.',
Ku='Kukulkan:BAABLgAECn8ZAAIOAAcJtQ8KHwCIAQAOAAcJtQ8KHwCIAQAAAA==.Kuulan:BAABLgAECn8eAAIQAAgJvBMEJwCnAQAQAAgJvBMEJwCnAQAAAA==.',
La='Larwock:BAAALgAECgQJDQAAAA==.Latwiz:BAAALgADCgYJCQAAAA==.Layana:BAAALgADCgUJBQAAAA==.',
Le='Leancuisine:BAAALgAECgEJAQAAAA==.Leetlebug:BAAALgAECgYJCwAAAA==.Lettÿ:BAAALgAECgQJCAAAAA==.',
Li='Lightheaded:BAAALgAECgcJCQAAAA==.Lightzwrath:BAAALgAECgYJDwABLgAECgcJCAAKAAAAAA==.Linadra:BAAALgAECgQJBAAAAA==.Liquid:BAAALgAECgYJEQAAAA==.',
Lo='Loankano:BAAALgAECgcJEQAAAA==.Lockbealady:BAAALgAECgUJCwAAAA==.Lohanoa:BAAALgAECgEJAQAAAA==.Longshanke:BAAALgAECgEJAQAAAA==.Lorebeard:BAAALgAECgEJAgAAAA==.Loreix:BAAALgAECgQJCQAAAA==.Lozzo:BAAALgADCgYJCwAAAA==.',
Lr='Lrock:BAAALgADCgMJAgAAAA==.',
Lu='Luciferluxx:BAAALgADCgQJBgAAAA==.Lumena:BAAALgADCggJCAAAAA==.Luminai:BAABLgAECn8YAAIXAAgJmBrAEQBUAgAXAAgJmBrAEQBUAgAAAA==.Luminaugty:BAAALgADCgYJDAAAAA==.Lunalea:BAAALgADCgQJBAAAAA==.Lunarthas:BAAALgADCgkJEQAAAA==.Luvinez:BAAALgAECgEJAgAAAA==.Luvinz:BAAALgAECgMJBAAAAA==.Luxkilla:BAAALgADCgEJAQAAAA==.',
Ly='Lyllia:BAAALgADCgEJAQAAAA==.Lynchmeup:BAAALgADCgYJBgABLgAECgcJFQARAKAVAA==.Lyrel:BAABLgAECn8ZAAIRAAgJRSBvDAAZAgARAAgJRSBvDAAZAgAAAA==.',
['Lî']='Lîllîth:BAAALgADCgMJAwAAAA==.',
['Lü']='Lümen:BAAALgADCggJCAABLgADCggJCAAKAAAAAA==.',
Ma='Maarc:BAAALgAECgYJEwAAAA==.Maddragon:BAAALgAECgIJAgAAAA==.Madfurion:BAAALgAECgEJAQAAAA==.Magebot:BAAALgAECggJEwAAAA==.Maggotbag:BAAALgAECgEJAQAAAA==.Magistra:BAAALgADCgcJDwAAAA==.Majestic:BAACLgAFFH8JAAICAAQJhxEKIABRAQACAAQJhxEKIABRAQAuAAQKfyMAAgIACQmKHlknANUCAAIACQmKHlknANUCAAAA.Malvenue:BAAALgAECgkJAgAAAA==.Malygor:BAAALgAECgQJBAAAAA==.Marly:BAAALgAECgYJDQAAAA==.Mauwy:BAABLgAECn8bAAMVAAgJMRU6HwAWAgAVAAgJMRU6HwAWAgAoAAEJMAp1owAsAAAAAA==.Mayabutreeks:BAAALgAECgEJAQAAAA==.Mazzerine:BAAALgAECgQJBAAAAA==.',
Mc='Mcbeardface:BAAALgAECgcJEwAAAA==.Mcbullseye:BAAALgAECgUJBAAAAA==.',
Me='Meathole:BAAALgAECgIJAgAAAA==.Megarah:BAAALgAECgMJBAAAAA==.Mental:BAAALgAECgEJAQAAAA==.Mepkaelpto:BAAALgAECgcJDQABLgAFFAQJBQACAC8LAA==.Mera:BAAALgADCgcJCAAAAA==.Mercury:BAAALgAECgYJEAAAAA==.Meretrix:BAAALgAECgYJDQAAAA==.Messatsu:BAAALgAECgQJBAAAAA==.Metanya:BAAALgAECgUJCQAAAA==.Mew:BAAALgAECgIJAgAAAA==.',
Mi='Miateh:BAAALgAECgMJBAAAAA==.Microdots:BAAALgADCgMJAwAAAA==.Midorí:BAAALgADCgYJBgAAAA==.Mimicme:BAAALgAECgYJDQAAAA==.Minorie:BAAALgADCgIJAgAAAA==.Mitchell:BAABLgAECn8YAAIQAAcJPg86NwBnAQAQAAcJPg86NwBnAQAAAA==.Miwah:BAAALgAECgUJDwAAAA==.',
Mj='Mjolnìr:BAAALgAECgMJCgAAAA==.',
Mo='Modeus:BAAALgADCgMJAwAAAA==.Modin:BAAALgAECgcJDwAAAA==.Mogarr:BAABLgAECn8XAAIBAAgJbQ0eHABpAQABAAgJbQ0eHABpAQAAAA==.Mohgwyn:BAAALgADCgEJAQAAAA==.Monkglein:BAABLgAECn8bAAMLAAcJxB4kCAD/AQALAAcJxB4kCAD/AQANAAEJmAHOUQATAAAAAA==.Monkhei:BAAALgAECgQJBAABLgAECggJHAAJACsjAA==.Mooglewing:BAAALgAECgYJCwAAAA==.Moomoobrncow:BAAALgAECgcJEwAAAA==.Moondream:BAABLgAECn8eAAMTAAcJoBUcIQCbAQATAAcJoBUcIQCbAQAkAAIJLgirewBVAAAAAA==.Mordicanta:BAABLgAECn8fAAIJAAgJ3BT6DgAkAQAJAAgJ3BT6DgAkAQAAAA==.Morphies:BAAALgADCgcJDQAAAA==.',
Mu='Muerr:BAABLgAECn8UAAITAAgJ9h5nFQCMAgATAAgJ9h5nFQCMAgAAAA==.Muerrizond:BAAALgAECgMJBgABLgAECggJFAATAPYeAA==.Muerrlin:BAAALgAECgYJBgABLgAECggJFAATAPYeAA==.Muggel:BAAALgADCgkJIwAAAA==.Mumraa:BAAALgAECgMJAwAAAA==.Mumrawr:BAAALgADCgcJCwAAAA==.Mushroohead:BAABLgAECn8ZAAIVAAgJyBrrBgA5AgAVAAgJyBrrBgA5AgAAAA==.',
My='Mystbourn:BAAALgAECgEJAQAAAA==.Mysterbyrnes:BAAALgADCgYJEAAAAA==.Myykiel:BAABLgAECn8YAAQRAAYJfBU0LAA0AQARAAUJBxk0LAA0AQAhAAYJ2QtiEwAcAQAgAAEJAABmOgAAAAAAAA==.',
Na='Naina:BAABLgAECn8eAAIoAAcJDhgTEgDhAQAoAAcJDhgTEgDhAQAAAA==.Najaja:BAAALgADCgcJBwAAAA==.Nariely:BAAALgAECgEJAQAAAA==.Natacha:BAAALgAECgQJBQAAAA==.Native:BAAALgAECgUJCAAAAA==.Nayos:BAAALgADCgIJAgAAAA==.',
Ne='Necro:BAABLgAECn8kAAIJAAkJICI2BQDvAgAJAAkJICI2BQDvAgAAAA==.Neelothe:BAAALgAECgMJAwAAAA==.Neisa:BAAALgADCgIJAgAAAA==.Nekroz:BAAALgAECgEJAQAAAA==.Nelliel:BAAALgAECgcJEwAAAA==.',
Ni='Nickodemus:BAAALgAECgIJAgAAAA==.Nightle:BAAALgADCggJCwAAAA==.Nihil:BAABLgAECn8UAAIhAAcJ6RKBBwBBAQAhAAcJ6RKBBwBBAQABLgAECgkJJAAJACAiAA==.Nikano:BAAALgADCgYJBgAAAA==.Ninmah:BAAALgADCgkJKgAAAA==.Niphredil:BAAALgADCgUJDQAAAA==.Nirø:BAABLgAECn8bAAILAAgJvghkFgA2AQALAAgJvghkFgA2AQAAAA==.',
No='Noah:BAAALgADCgcJDQAAAA==.Nooky:BAABLgAECn8eAAINAAgJPh2SBgBYAgANAAgJPh2SBgBYAgAAAA==.',
Nu='Nuatha:BAAALgAECgQJCQAAAA==.Numpty:BAAALgAECgMJBgAAAA==.',
Ny='Nyctero:BAABLgAECn8eAAIjAAgJlB92AQCTAgAjAAgJlB92AQCTAgAAAA==.Nyrikah:BAAALgADCgcJBwAAAA==.',
['Nö']='Nöstrum:BAAALgADCgMJAwABLgAECgUJBQAKAAAAAA==.',
Ob='Obidiah:BAABLgAECn8eAAMCAAcJsxW5TwBCAQACAAYJYha5TwBCAQAbAAEJRhKXGgBDAAAAAA==.',
Oe='Oedipus:BAAALgAECgMJAwAAAA==.',
Oh='Ohioaug:BAAALgADCgEJAQAAAA==.',
Or='Orah:BAAALgAECgYJEwAAAA==.Orpheon:BAAALgAECgQJCQAAAA==.',
Os='Osorn:BAAALgADCgkJCgAAAA==.',
Ot='Otterdoodad:BAAALgAECgQJBAAAAA==.',
Oz='Ozzmosis:BAAALgADCgMJAwAAAA==.',
Pa='Palagem:BAAALgADCgYJBgAAAA==.Palinyes:BAABLgAECn8UAAIlAAcJKSMQAwA/AgAlAAcJKSMQAwA/AgAAAA==.Pancetta:BAAALgADCgUJCAAAAA==.Pandabits:BAAALgADCgYJBgAAAA==.Papabill:BAABLgAECn8aAAIQAAgJCg6mLgCHAQAQAAgJCg6mLgCHAQAAAA==.Paperscissor:BAAALgADCgIJAgAAAA==.Paragorn:BAABLgAECn8YAAIQAAcJawijSgAqAQAQAAcJawijSgAqAQAAAA==.Pasiphae:BAAALgADCgIJAgABLgADCgcJBwAKAAAAAA==.Pattee:BAABLgAECn8YAAIkAAYJiyCiBQCeAQAkAAYJiyCiBQCeAQAAAA==.',
Pe='Peachums:BAAALgADCgEJAQAAAA==.Pech:BAAALgAFFAEJAQAAAA==.Peenidin:BAABLgAECn8eAAIaAAgJKSJMBwBqAgAaAAgJKSJMBwBqAgAAAA==.Pemerd:BAAALgAECgYJEwAAAA==.Petite:BAAALgADCgMJAwAAAA==.',
Ph='Phoenixfires:BAAALgADCgYJCAAAAA==.Phoze:BAABLgAECn8YAAIlAAcJXhO/CgBWAQAlAAcJXhO/CgBWAQAAAA==.Phyai:BAABLgAECn8VAAICAAYJwhOZTQBHAQACAAYJwhOZTQBHAQAAAA==.',
Pi='Pirotanaxdos:BAAALgAECgUJCQAAAA==.Pizzarollzz:BAABLgAECn8UAAITAAcJ9A0FMQBNAQATAAcJ9A0FMQBNAQAAAA==.',
Pn='Pnutt:BAAALgADCgcJBwAAAA==.',
Po='Ponymalta:BAABLgAECn8lAAIIAAgJ5BdIGwApAgAIAAgJ5BdIGwApAgAAAA==.Popeaganda:BAAALgAECgQJBwAAAA==.Poutine:BAAALgAECgQJCwAAAA==.',
Pr='Prizren:BAAALgAECgMJBQAAAA==.Promethyus:BAABLgAECn8cAAMQAAgJTAXrdADEAAAQAAgJTAXrdADEAAAlAAUJxAGtHwBhAAAAAA==.Promidan:BAAALgAECgEJAQABLgAFFAQJDQAQAAALAA==.Pryxi:BAABLgAECn8dAAICAAcJcQibWQArAQACAAcJcQibWQArAQAAAA==.',
Pu='Puffichu:BAAALgADCgMJAwABLgAECgMJAwAKAAAAAA==.Punchline:BAAALgADCgcJBwAAAA==.',
Py='Pyrogar:BAAALgADCgIJAgAAAA==.Pythius:BAAALgAECgEJAQAAAA==.',
['Pó']='Pótatò:BAAALgAECgQJBAAAAA==.',
Qu='Quandaale:BAAALgAFFAEJAQABLgAFFAEJAQAKAAAAAA==.Quell:BAAALgADCgEJAQAAAA==.Quepinga:BAAALgADCgUJCAAAAA==.Quiksylver:BAABLgAECn8aAAMaAAgJfRzOEADbAQAaAAcJaxvOEADbAQAQAAQJ/hDJ9ACoAAAAAA==.',
Ra='Rabblerousin:BAAALgAECgEJAgAAAA==.Raegnar:BAAALgADCgYJBgAAAA==.Raggnnar:BAAALgADCgEJAgAAAA==.Rainmakers:BAAALgAECgcJBQAAAA==.Rakael:BAAALgADCgMJAwAAAA==.Rava:BAAALgAECgEJAQAAAA==.',
Re='Reckoner:BAAALgAECgQJCQAAAA==.Red:BAABLgAECn8nAAQUAAgJEyIeEQAyAgAUAAgJ/x8eEQAyAgAWAAYJvCLbBAABAgAJAAcJkhFNCwBbAQAAAA==.Rellster:BAAALgAECgUJCgAAAA==.Renix:BAAALgAECgQJBQAAAA==.Rennyo:BAAALgAECgYJEwAAAA==.Resonance:BAAALgAECgUJBwAAAA==.Retsu:BAAALgADCgUJBQAAAA==.Rettbull:BAAALgADCgMJAwAAAA==.Reyujin:BAAALgAECgEJBAAAAA==.',
Rh='Rhyash:BAAALgAECgQJCQAAAA==.',
Ri='Rickdaddty:BAAALgADCgkJCQABLgAECgcJEwAKAAAAAA==.Ricoz:BAAALgAECgQJBQAAAA==.Ridicutie:BAAALgAECgYJEwAAAA==.Rigg:BAABLgAECn8VAAIRAAcJoBWYGwCPAQARAAcJoBWYGwCPAQAAAA==.Riggz:BAAALgADCgQJBAABLgAECgcJFQARAKAVAA==.Rivetro:BAAALgAECgQJCwAAAA==.',
Ro='Rocknroll:BAABLgAECn8jAAITAAgJ/RwUEwCeAgATAAgJ/RwUEwCeAgAAAA==.Roll:BAABLgAECn8ZAAIlAAYJLyK2CgAiAgAlAAYJLyK2CgAiAgAAAA==.Rozgrez:BAABLgAECn8bAAMFAAcJLBe4PQA5AQAFAAcJFRW4PQA5AQAEAAQJvxJnEACuAAAAAA==.',
Ru='Rufus:BAAALgADCgkJDgAAAA==.Rumlidorgah:BAABLgAECn8YAAMFAAgJGgs8LwBvAQAFAAgJVAk8LwBvAQAEAAQJOw1vEQCiAAAAAA==.Russbus:BAABLgAECn8eAAMQAAgJsg7yKQCaAQAQAAgJsg7yKQCaAQAaAAgJEQf1XAAJAQAAAA==.Ruune:BAAALgAECgUJBwAAAA==.',
['Ré']='Réven:BAABLgAECn8YAAIRAAgJaxvoLwAkAQARAAgJaxvoLwAkAQAAAA==.',
Sa='Sadienna:BAABLgAECn8bAAMiAAgJlwZVFgBNAQAiAAgJlwZVFgBNAQAXAAgJtAOgRgAfAQAAAA==.Salvidali:BAAALgADCgcJBgAAAA==.Sandrï:BAABLgAECn8UAAQFAAYJUQ76QgApAQAFAAYJMQ76QgApAQAGAAEJ6RNnDgBMAAAEAAEJAAB1LAAAAAAAAA==.Sane:BAAALgAECgYJEwAAAA==.Saoiirse:BAABLgAECn8VAAMRAAcJhRb/GwCMAQARAAcJOxb/GwCMAQAgAAEJsxOnLwA7AAAAAA==.Saraella:BAAALgAECgYJAgAAAA==.Sasso:BAAALgADCgIJAgAAAA==.Sawako:BAABLgAECn8VAAIiAAgJHhWPDwCSAQAiAAgJHhWPDwCSAQAAAA==.',
Sc='Scalar:BAAALgADCgEJAQAAAA==.Scalyboi:BAAALgADCgMJAwABLgAFFAQJCQACAIcRAA==.Scarletts:BAAALgADCgUJBgABLgAECgUJBQAKAAAAAA==.Schlitzie:BAAALgADCgIJAgAAAA==.Scrapes:BAAALgADCgMJAwAAAA==.Scuba:BAAALgAECgYJCwAAAA==.',
Se='Seraphyne:BAAALgAECgIJAgABLgAFFAUJFgAHAH4fAA==.Sevencharlie:BAAALgAECgUJDAAAAA==.',
Sh='Shadowho:BAAALgAECgQJBwAAAA==.Shaladro:BAAALgADCgUJCAAAAA==.Shalanaz:BAAALgAECgEJAQAAAA==.Shamutty:BAAALgAECgEJAQABLgAECggJGAACANcfAA==.Sharasdal:BAAALgAECgEJAQABLgAECgYJAgAKAAAAAA==.Sherief:BAAALgADCgQJBAAAAA==.Shinjô:BAAALgAECgQJCwAAAA==.Shiroishi:BAAALgADCgcJBwABLgAECgYJGQAOAHAGAA==.Shivaray:BAAALgADCgUJBQAAAA==.Shiveria:BAAALgADCgYJCwAAAA==.Shocklesner:BAAALgAECgYJDgAAAA==.Shorkaan:BAAALgAECgEJAQAAAA==.Shouganai:BAAALgAECgYJCwAAAA==.Shupaz:BAAALgAECgIJAgAAAA==.',
Si='Siddha:BAAALgADCgYJBgABLgAECgYJCwAKAAAAAA==.Sieria:BAAALgAECgYJDQAAAA==.Siieerr:BAAALgAFFAIJBAAAAA==.Silvermind:BAAALgAECgEJAQAAAA==.Sinaar:BAAALgAECgIJAwAAAA==.Sindena:BAABLgAECn8ZAAIFAAcJOhSjXACyAQAFAAcJOhSjXACyAQAAAA==.Sixsanity:BAAALgAECgQJCQAAAA==.',
Sk='Skavos:BAAALgAECgYJBwAAAA==.Skillcommand:BAAALgAECgQJCQAAAA==.Skipperino:BAAALgADCggJDQAAAA==.Skyemage:BAAALgAECgEJAgAAAA==.',
Sl='Slotz:BAABLgAECn8gAAIaAAcJERphLQDPAQAaAAcJERphLQDPAQAAAA==.',
Sm='Smallcoomer:BAAALgAECgcJDgAAAA==.Smallss:BAAALgAECgUJBgAAAA==.Smike:BAABLgAECn8gAAIQAAcJgwsoRgA3AQAQAAcJgwsoRgA3AQAAAA==.',
Sn='Sneeze:BAAALgAECgQJBQAAAA==.Snuggles:BAAALgADCgUJBwAAAA==.',
So='Soferan:BAABLgAECn8aAAIUAAYJkRxwLwB8AQAUAAYJkRxwLwB8AQAAAA==.Sonarr:BAAALgAECgUJBQAAAA==.',
Sp='Spacemilk:BAAALgAECggJEQAAAA==.Spark:BAAALgAECgEJAQAAAA==.Spicymeat:BAAALgADCgcJBwABLgAFFAQJCQACAIcRAA==.Sputty:BAAALgAECgYJDQABLgAECggJGAACANcfAA==.',
St='Stankmouth:BAABLgAECn8ZAAINAAQJwgU8MwB4AAANAAQJwgU8MwB4AAAAAA==.Stellas:BAAALgADCgUJCAABLgAECgUJCQAKAAAAAA==.Stesha:BAAALgADCgcJEQABLgAECgcJDwAKAAAAAA==.Steviewonder:BAABLgAECn8fAAIRAAcJixWiIQBpAQARAAcJixWiIQBpAQAAAA==.Stinkerton:BAAALgAECgYJBgAAAA==.Stonedfrog:BAAALgADCgcJBwAAAA==.Stonefather:BAABLgAECn8kAAINAAgJegxiFwBOAQANAAgJegxiFwBOAQAAAA==.Stonewall:BAAALgADCgEJAgAAAA==.Strangelets:BAAALgAECgQJBQAAAA==.Strangewayes:BAAALgADCgMJAwAAAA==.Stïtches:BAAALgAECgUJEAAAAA==.Stönk:BAAALgAECgcJEwAAAA==.',
Su='Succulentman:BAABLgAECn8gAAIRAAgJ3yIfDgAFAgARAAgJ3yIfDgAFAgAAAA==.Sufferyn:BAAALgADCgcJBwAAAA==.Sunreaver:BAAALgADCgYJCgAAAA==.Supoz:BAAALgAECgEJAQAAAA==.Surolath:BAABLgAECn8fAAIeAAgJmh4oAgBRAgAeAAgJmh4oAgBRAgAAAA==.',
Sw='Swaggles:BAABLgAECn8fAAImAAgJ3SQtAQDWAgAmAAgJ3SQtAQDWAgAAAA==.Swiftcast:BAAALgADCgYJDAAAAA==.Swiftpalms:BAAALgAECgYJBgAAAA==.Swompfox:BAAALgAECgUJBQAAAA==.',
Sy='Sygon:BAABLgAECn8gAAIkAAgJehRgBgCJAQAkAAgJehRgBgCJAQAAAA==.Sylvannaa:BAAALgAECgYJBwAAAA==.Syntherizena:BAAALgAECgYJBwAAAA==.Synthesized:BAAALgAECgUJBQAAAA==.',
['Só']='Sóng:BAABLgAECn8aAAMXAAcJLh3cEwBAAgAXAAcJLh3cEwBAAgAiAAEJSQ7sXgA7AAAAAA==.',
Ta='Tacitus:BAAALgAECgcJEQAAAA==.Tairrad:BAAALgAECgYJCAAAAA==.Takeru:BAAALgAECgMJBQAAAA==.Talasmar:BAAALgADCgUJBQAAAA==.Tapkora:BAAALgAECgQJCAAAAA==.Tapsum:BAAALgADCgUJBQAAAA==.Tarirn:BAAALgADCgEJAQAAAA==.Taurtem:BAAALgAECgQJBQAAAA==.Taylia:BAAALgAECgQJDAABLgAECgcJGAAPAIYTAA==.Tayona:BAAALgAECgIJAgAAAA==.Tazildek:BAAALgAECgEJAQAAAA==.',
Te='Technique:BAAALgAECgYJDQAAAA==.Tergrid:BAAALgAECgMJAwAAAA==.Terial:BAABLgAECn8ZAAIaAAYJ7R6IFwCTAQAaAAYJ7R6IFwCTAQAAAA==.Textoffender:BAAALgAECgQJBgAAAA==.',
Th='Thajeebus:BAAALgADCgEJAQAAAA==.Thatsneat:BAAALgAECgQJBQAAAA==.Thecapt:BAABLgAECn8lAAIfAAkJ4xkcBwA+AgAfAAkJ4xkcBwA+AgAAAA==.Theôdöræ:BAAALgAECgkJAwAAAA==.Thorinfel:BAABLgAECn8hAAIRAAkJ1xR6NgAdAgARAAkJ1xR6NgAdAgAAAA==.Thsaemage:BAAALgAECgQJBAABLgAECggJIAAIAOoaAA==.Thunderkiss:BAAALgADCgkJCQAAAA==.Thunran:BAAALgAECgQJBgAAAA==.',
Ti='Tiaoma:BAAALgAECgEJAQAAAA==.Tieria:BAABLgAECn8UAAIiAAcJ6R26CAD5AQAiAAcJ6R26CAD5AQAAAA==.Tikao:BAABLgAECn8aAAMhAAgJoAopCgD6AAAhAAgJlwopCgD6AAAgAAYJpAVfQwDqAAAAAA==.Tinna:BAAALgAECgcJBgAAAA==.',
Tj='Tjhookèr:BAAALgAECgUJCQAAAA==.',
To='Tobajal:BAABLgAECn8fAAIXAAgJXxzfBAB+AgAXAAgJXxzfBAB+AgAAAA==.Toletheus:BAABLgAECn8YAAMSAAcJWxcCBgCuAQASAAcJWxcCBgCuAQAIAAMJlw8aYQCdAAAAAA==.Tomin:BAAALgAECgUJCwAAAA==.Totemique:BAAALgADCgcJDgABLgAECgYJDQAKAAAAAA==.Totumfknpole:BAAALgADCgEJAQAAAA==.',
Tr='Treeperson:BAABLgAECn8UAAIHAAcJZiKyBwCTAgAHAAcJZiKyBwCTAgAAAA==.Treyni:BAAALgADCgIJAgAAAA==.Trickyric:BAAALgAECgUJCwAAAA==.Trilgy:BAAALgADCgkJCgAAAA==.Trowel:BAABLgAECn8WAAIIAAcJlx+TGQA6AgAIAAcJlx+TGQA6AgABLgAECggJGAACANcfAA==.',
Ts='Tsuyoimono:BAAALgAECgYJDwAAAA==.',
Tu='Turisx:BAAALgADCgMJBAAAAA==.',
Tw='Twiddydh:BAAALgAECgYJDAAAAA==.Twylan:BAAALgADCgYJBgAAAA==.',
Ty='Tydroin:BAAALgADCgMJAwAAAA==.Tytoalba:BAAALgAECgQJBQAAAA==.',
Uk='Ukiru:BAAALgADCgMJAwAAAA==.',
Un='Ungonelilith:BAAALgADCgkJDwAAAA==.',
Ur='Uratsukasama:BAAALgAECgMJBAAAAA==.Urion:BAABLgAECn8XAAQmAAYJiBySDACVAQAmAAYJlhqSDACVAQATAAMJsh/XlwCmAAAkAAEJ7Q7kiAAyAAAAAA==.',
Va='Vacaite:BAAALgAECgIJAwAAAA==.Vagiant:BAABLgAECn8ZAAISAAcJ7xGCCwAnAQASAAcJ7xGCCwAnAQAAAA==.Valyna:BAAALgADCgEJAQAAAA==.Vanya:BAABLgAECn8YAAMTAAYJ/BpSIgCUAQAmAAYJfhiLDgDdAQATAAYJCBpSIgCUAQAAAA==.Vash:BAAALgADCgYJBgABLgAECgUJCQAKAAAAAA==.Vasso:BAAALgAECgMJBAAAAA==.',
Ve='Velinae:BAAALgAECgkJBgAAAA==.Velint:BAAALgADCgIJAgAAAA==.Velveen:BAABLgAECn8cAAMVAAcJbxjRGABMAQAVAAYJ0hfRGABMAQAoAAEJtAfnYAA0AAAAAA==.Vexxia:BAAALgAECgEJAQAAAA==.',
Vi='Viallure:BAAALgAECgcJDQABLgAECgkJEAAKAAAAAA==.Vilebloom:BAEBLgAECn8XAAIHAAYJFiK6CwBNAgAHAAYJFiK6CwBNAgAAAA==.Viridius:BAAALgAECgMJBAAAAA==.Vitamind:BAAALgADCgEJAQAAAA==.',
Vo='Volwraith:BAAALgAECgcJBgAAAA==.Vonmortis:BAAALgADCgkJFwAAAA==.',
Wa='Wagguslight:BAABLgAECn8bAAIQAAcJLw8xSgArAQAQAAcJLw8xSgArAQAAAA==.Warzak:BAAALgAECgYJDQAAAA==.Wayne:BAAALgADCgUJBQAAAA==.',
We='Wendybacon:BAABLgAECn8UAAIRAAYJBxQ8bABeAQARAAYJBxQ8bABeAQAAAA==.',
Wh='Whateverdude:BAAALgAECgMJBAAAAA==.Whiskeyshots:BAAALgADCgIJAgAAAA==.Whytè:BAABLgAECn8jAAIHAAgJMCASBQDTAgAHAAgJMCASBQDTAgAAAA==.',
Wi='Wigeon:BAAALgADCggJCAABLgAECgMJAwAKAAAAAA==.Wiickett:BAABLgAECn8fAAMdAAgJtB28BAC5AgAdAAgJcx28BAC5AgAcAAYJrh+KIwChAQAAAA==.Wilbur:BAAALgAECgIJAwAAAA==.Wildebeard:BAACLgAFFH8JAAIaAAQJliI8BQCeAQAaAAQJliI8BQCeAQAuAAQKfyAAAhoACAn3JDkFABgDABoACAn3JDkFABgDAAAA.Wilferal:BAAALgAECgQJBAAAAA==.Willaá:BAAALgAECgYJCwAAAA==.Willowyn:BAABLgAECn8hAAINAAkJkhYSCQAfAgANAAkJkhYSCQAfAgAAAA==.Wingmans:BAAALgAECgQJBwAAAA==.Wizzpeaver:BAAALgAFFAEJAQAAAA==.',
Wo='Wonderwizard:BAABLgAECn8YAAICAAYJRBYMSQBTAQACAAYJRBYMSQBTAQAAAA==.',
Wr='Wraeth:BAAALgADCgYJBgAAAA==.Wrathhoof:BAAALgAECgcJCAAAAA==.',
Xa='Xahra:BAAALgADCgcJBwAAAA==.Xaralyss:BAAALgAECgQJBwAAAA==.',
Xh='Xhine:BAAALgAECgEJAQAAAA==.',
Xy='Xylias:BAAALgADCgcJCgAAAA==.',
Ya='Yamon:BAAALgADCggJEAAAAA==.',
Yo='Yodef:BAACLgAFFH8HAAIUAAIJhRHuPQCjAAAUAAIJhRHuPQCjAAAuAAQKfxkAAhQACAm/HpgSACUCABQACAm/HpgSACUCAAAA.Yorri:BAAALgAECgMJAwAAAA==.',
Yu='Yucca:BAABLgAECn8lAAMUAAkJNxa7EAA2AgAUAAkJNxa7EAA2AgAJAAEJAABPMwAAAAAAAA==.Yuda:BAAALgAECgEJBAAAAA==.Yudaneyo:BAAALgAECgEJBgAAAA==.Yukiteru:BAABLgAECn8WAAIRAAgJbRgSFQDAAQARAAgJbRgSFQDAAQAAAA==.Yurito:BAABLgAECn8ZAAIiAAYJuRqhEACGAQAiAAYJuRqhEACGAQAAAA==.',
Yz='Yzernara:BAAALgAECgEJAQABLgAECgYJAgAKAAAAAA==.',
Za='Zabrina:BAAALgAECgcJDwAAAA==.Zaiel:BAAALgADCgMJAwAAAA==.Zappybains:BAABLgAECn8fAAIoAAgJ6h4RBQCnAgAoAAgJ6h4RBQCnAgAAAA==.Zarakii:BAAALgAECgYJEQAAAA==.',
Ze='Zekken:BAAALgADCgMJBAAAAA==.Zelaina:BAAALgAECgUJCAAAAA==.',
Zi='Zi:BAAALgADCgQJBQABLgAECgkJKAAMAPsfAA==.',
Zu='Zuda:BAAALgAECgEJBgAAAA==.Zupaz:BAAALgADCgEJAQAAAA==.',
Zy='Zylluz:BAAALgAECggJCwAAAA==.Zylos:BAAALgAECgYJEwAAAA==.',
['Zì']='Zìnn:BAAALgAECgIJAgAAAA==.',
['Äs']='Äshébringer:BAACLgAFFH8JAAIQAAUJPxxxCABuAQAQAAUJPxxxCABuAQAuAAQKfx4AAhAACQkwJFACAA8DABAACQkwJFACAA8DAAAA.',
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

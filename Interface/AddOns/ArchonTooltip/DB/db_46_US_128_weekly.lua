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

local lookup = {'Warrior-Arms','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','DeathKnight-Blood','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Paladin-Retribution','Mage-Frost','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Mage-Arcane','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Vengeance','Hunter-Survival','Paladin-Protection','Rogue-Outlaw','Evoker-Preservation','DemonHunter-Devourer','Shaman-Restoration','Shaman-Enhancement',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaryn:BAAALgAECgEJAQABLgAECgcJGQABAEoPAA==.',
Ab='Absynthia:BAAALgAECgYJDgAAAA==.',
Ac='Academe:BAAALgAECgYJEgAAAA==.Acrid:BAAALgAECgEJAQAAAA==.',
Ad='Ados:BAAALgAECgQJBQAAAA==.',
Ae='Aeity:BAAALgAECgUJBQAAAA==.Aellopus:BAAALgAECgEJAQAAAA==.Aenas:BAAALgAECgMJAwAAAA==.Aero:BAABLgAECn8ZAAMBAAcJSg+EFwA+AQABAAYJZw6EFwA+AQACAAQJ9g3uDACqAAAAAA==.',
Af='Afflictedd:BAAALgAECgEJAQAAAA==.',
Ah='Ahren:BAAALgAECgQJBwAAAA==.',
Ak='Akata:BAAALgADCgcJBwAAAA==.',
Al='Alayder:BAAALgADCgYJBgAAAA==.Alomeo:BAAALgADCggJDAAAAA==.',
Am='Amarí:BAAALgADCggJGAAAAA==.Amayêlle:BAAALgADCggJGAAAAA==.Amendos:BAAALgAECgYJCQAAAA==.Amiliane:BAABLgAECn8XAAQDAAYJIA7/BwCzAAAEAAUJoAowwADYAAADAAQJvw3/BwCzAAAFAAMJ7ApaHQCHAAAAAA==.Amunshi:BAAALgADCgQJBAAAAA==.Amz:BAAALgAECgMJAwAAAA==.',
An='Anadrien:BAABLgAECn8ZAAIGAAYJCx27CwCaAQAGAAYJCx27CwCaAQAAAA==.Ancelagon:BAAALgADCgYJBgAAAA==.Andrae:BAAALgAECgUJBQAAAA==.Andrastae:BAAALgAECgYJBgAAAA==.Angrima:BAAALgAECgEJAQAAAA==.Angrimia:BAABLgAECn8ZAAIHAAcJ/hu/AwCpAQAHAAcJ/hu/AwCpAQAAAA==.Anju:BAAALgAECgEJAgAAAA==.Ansticé:BAAALgADCgYJBgAAAA==.Antal:BAAALgAECgEJAQAAAA==.Anthelyn:BAAALgADCgcJBwAAAA==.',
Ar='Arannis:BAAALgADCgcJCQAAAA==.Archielgh:BAAALgAECgYJCwAAAA==.Areldor:BAAALgADCgYJBwAAAA==.Aremethea:BAAALgADCgQJBwABLgAECgMJBQAIAAAAAA==.Ariaa:BAAALgADCggJDAAAAA==.Arkannah:BAAALgADCgcJBwAAAA==.Aronk:BAABLgAECn8XAAQJAAYJ2RO/PgBKAQAJAAUJ3Ra/PgBKAQAKAAUJDA1pRgD8AAALAAYJ5QJ7EwCsAAAAAA==.Arore:BAAALgADCgEJAQABLgAECgYJFwAJANkTAA==.Arorepriest:BAAALgADCgcJBwABLgAECgYJFwAJANkTAA==.Articulàte:BAAALgAECgQJBAAAAA==.Arzec:BAAALgAECgYJEwAAAA==.',
Av='Avestara:BAABLgAECn8ZAAIMAAcJqRxYBADcAQAMAAcJqRxYBADcAQAAAA==.',
Aw='Awenlock:BAEALgADCgQJAwAAAA==.',
Ay='Ayluid:BAAALgAECgUJCQAAAA==.',
Az='Azazill:BAAALgAECgYJCwAAAA==.Azeralle:BAAALgADCgkJCgAAAA==.Azmodeus:BAAALgAECgMJAwAAAA==.Azoril:BAABLgAECn8aAAINAAYJJhEQHABGAQANAAYJJhEQHABGAQAAAA==.',
['Aí']='Aídeen:BAAALgAECgUJBgAAAA==.',
Ba='Baal:BAAALgADCgcJEQAAAA==.Babaspook:BAAALgAECgMJAwAAAA==.Baelnorn:BAABLgAECn8YAAMEAAYJEB4/DwCYAQAEAAYJ1x0/DwCYAQADAAIJDxnuSgCNAAAAAA==.Bains:BAAALgADCgcJBwAAAA==.Baja:BAAALgAECgQJBwAAAA==.Bandit:BAAALgAECgQJBQAAAA==.Batrela:BAAALgAECgYJDwAAAA==.Battleturtle:BAAALgAECgYJCgAAAA==.Batôsai:BAAALgAECgEJAQAAAA==.Bazir:BAAALgADCgEJAQABLgAFFAMJBQAOAGUSAA==.',
Be='Bearpawz:BAABLgAECn8hAAIPAAkJNhiXAABuAgAPAAkJNhiXAABuAgAAAA==.Bearrel:BAAALgAECgYJCwAAAA==.Bearrier:BAAALgADCgEJAQAAAA==.Bekens:BAABLgAECn8UAAIQAAYJrSR8CgDBAQAQAAYJrSR8CgDBAQAAAA==.Belaraariaae:BAAALgADCgQJBAAAAA==.Benastiel:BAAALgADCgYJBwAAAA==.Bernardboggs:BAAALgAECgUJCAAAAA==.Bethbathory:BAABLgAECn8XAAIFAAcJMBRlAQCKAQAFAAcJMBRlAQCKAQAAAA==.',
Bh='Bheefknight:BAAALgAECgQJCQAAAA==.',
Bi='Bierbro:BAABLgAECn8UAAIRAAcJfhGEGwA8AQARAAcJfhGEGwA8AQAAAA==.Bigfacts:BAAALgAECggJDAAAAA==.Bigoldee:BAAALgADCgUJBQAAAA==.Bigyk:BAAALgADCgYJBgAAAA==.Billié:BAAALgAECgYJEwAAAA==.',
Bl='Blightheaded:BAAALgAECgQJBwABLgAECgcJCQAIAAAAAA==.Blindëye:BAAALgAECgYJCQAAAA==.Blumir:BAAALgAECgUJBgAAAA==.',
Bn='Bnththeocean:BAAALgAECggJCAAAAA==.',
Bo='Bobmauley:BAAALgADCgQJBAAAAA==.Bombkin:BAABLgAECn8ZAAIGAAcJRCPcBQAZAgAGAAcJRCPcBQAZAgAAAA==.Bonchonn:BAABLgAECn8ZAAIQAAgJhB9zDgDIAgAQAAgJhB9zDgDIAgAAAA==.Bonkula:BAAALgAECgUJDQAAAA==.Boondox:BAAALgAECgMJAwAAAA==.Bootyfeastr:BAAALgADCgEJAwAAAA==.Bops:BAAALgADCgQJBAAAAA==.',
Br='Brae:BAAALgAECgUJBwAAAA==.Bralitha:BAAALgADCgEJAQAAAA==.Braumbastic:BAAALgADCgUJBQAAAA==.Brazonk:BAAALgADCgkJCQAAAA==.Brewzco:BAABLgAECn8iAAIJAAkJLR9yAADoAgAJAAkJLR9yAADoAgAAAA==.Brianné:BAAALgADCgQJBAAAAA==.Bricifergoat:BAABLgAFFH8PAAISAAUJwCWYAAC5AQASAAUJwCWYAAC5AQABLgAFFAMJBwARAKcdAA==.Briciferkong:BAACLgAFFH8HAAIRAAMJpx08IwAJAQARAAMJpx08IwAJAQAuAAQKfxUAAxEABwklHxQRAIwBABEABwklHxQRAIwBABMAAQknCJgYAC0AAAAA.Briciferyeah:BAAALgADCgQJBAABLgAFFAMJBwARAKcdAA==.Brightblayde:BAABLgAECn8ZAAINAAcJPhujEACfAQANAAcJPhujEACfAQAAAA==.Brique:BAAALgADCggJDAABLgAECgYJCgAIAAAAAA==.',
Bu='Buanto:BAAALgAECgMJAwAAAA==.Bubblegumm:BAAALgAECgYJEQAAAA==.Bubieh:BAAALgAECgQJBQABLgAECggJHAAHACsjAA==.Bumpinlumps:BAAALgADCgUJCQAAAA==.Bushwookiee:BAAALgAECgEJAQAAAA==.Butterknight:BAACLgAFFH8GAAIRAAIJxxK7OgCnAAARAAIJxxK7OgCnAAAuAAQKfyIAAhEACAnYI0AWAPYCABEACAnYI0AWAPYCAAAA.Buttertotem:BAAALgADCgkJDgAAAA==.',
Ca='Caanu:BAAALgADCgUJBwAAAA==.Calypso:BAAALgAECgMJAwAAAA==.Candlelock:BAAALgAECgYJBgAAAA==.Carirmonk:BAAALgAECgEJAQAAAA==.Cattroll:BAAALgAFFAEJAQAAAA==.',
Cd='Cdubb:BAAALgAECgQJCAAAAA==.',
Ce='Celidori:BAAALgAECgYJBgABLgAFFAEJAQAIAAAAAA==.Celithila:BAABLgAECn8XAAMUAAYJuxNMCwBBAQAUAAYJuxNMCwBBAQAMAAEJ/QY2WQAwAAAAAA==.Celithvia:BAAALgAECgYJDAAAAA==.Ceroin:BAAALgADCgEJAQAAAA==.Cervantés:BAABLgAECn8iAAMVAAkJEhvqAACHAgAVAAkJ8hXqAACHAgAWAAcJMBtNBgAVAgAAAA==.',
Ch='Chaia:BAAALgAECgYJEwAAAA==.Chelsea:BAAALgAECgEJAQAAAA==.Cherra:BAAALgAECgYJBgABLgAECgYJEAAIAAAAAA==.Chise:BAABLgAECn8YAAIMAAcJhhN0HQCpAQAMAAcJhhN0HQCpAQAAAA==.Chrispyloa:BAAALgAECgQJBwAAAA==.Chubs:BAABLgAECn8XAAMDAAcJoxdQDgDjAQADAAcJoxdQDgDjAQAEAAQJbRJQvgDcAAAAAA==.',
Cl='Clann:BAAALgAECgYJDgAAAA==.Cly:BAAALgAECgYJDgAAAA==.Clydk:BAAALgAECgEJAQABLgAECgYJDgAIAAAAAA==.',
Co='Coachbeard:BAABLgAECn8fAAIXAAkJSxDgKgDcAQAXAAkJSxDgKgDcAQAAAA==.Colzamenta:BAAALgAFFAMJBAAAAA==.Contract:BAAALgAECgUJBQAAAA==.Corpsereth:BAAALgAECgcJAwAAAA==.',
Cr='Creamcicle:BAAALgADCgEJAQAAAA==.Crispytots:BAAALgAECgcJDAAAAA==.Crit:BAAALgAECgQJBQABLgAECgcJEwAIAAAAAA==.Critmypantz:BAAALgAECgcJEwAAAA==.Crosby:BAAALgADCgUJBQAAAA==.',
Cu='Cudguzzler:BAAALgADCggJCQAAAA==.Cursegoesmoo:BAACLgAFFH8FAAIRAAMJzSBsCgAiAQARAAMJzSBsCgAiAQAuAAQKfxQAAhEACAmOIX8fAMQCABEACAmOIX8fAMQCAAAA.',
Cy='Cygna:BAABLgAECn8qAAIQAAgJsh/dAwBKAgAQAAgJsh/dAwBKAgAAAA==.Cyntheria:BAABLgAECn8fAAINAAgJvBxAJgCNAgANAAgJvBxAJgCNAgAAAA==.',
Da='Daddybeàr:BAAALgAECgQJBQAAAA==.Daendron:BAAALgADCgQJBAAAAA==.Dajubah:BAABLgAECn8XAAICAAcJuRfXBAB1AQACAAcJuRfXBAB1AQAAAA==.Dammitdave:BAAALgAECgUJEwAAAA==.Dangereuse:BAAALgAECgQJBAAAAA==.Darinell:BAAALgAECgUJCwAAAA==.Darksaxon:BAAALgAECgYJDAAAAA==.',
De='Deathnethal:BAAALgAECgQJBAAAAA==.Deathweaver:BAAALgAECgMJAwAAAA==.Deebbzmonk:BAAALgAECgcJDAAAAA==.Deltaco:BAAALgAECgQJBAABLgAECgkJHAAQAGcgAA==.Deme:BAAALgADCgcJCgAAAA==.Demonica:BAAALgAECgcJDAAAAA==.Dendrax:BAABLgAECn8WAAIEAAYJ3wWnJQD/AAAEAAYJ3wWnJQD/AAAAAA==.Dented:BAAALgAECgYJEwAAAA==.Derivation:BAAALgAECgQJBwAAAA==.Destitute:BAAALgAECgUJBQAAAA==.Detaren:BAAALgADCgEJAQAAAA==.Dethwing:BAAALgAECgIJBAAAAA==.Devadeity:BAABLgAECn8UAAIUAAYJBhRNNQBoAQAUAAYJBhRNNQBoAQAAAA==.Deviance:BAAALgAECgYJDwAAAA==.Devola:BAAALgADCgkJFAAAAA==.',
Di='Didntask:BAAALgADCgEJAQABLgAECggJGAAHAIQOAA==.Dienmage:BAABLgAECn8XAAIYAAcJmSB/AAAHAgAYAAcJmSB/AAAHAgAAAA==.Digìt:BAAALgAECgIJAgABLgAECgcJGgAUAC4dAA==.Dirtychai:BAAALgAECgYJEgAAAA==.Dissonance:BAAALgAECgEJAQAAAA==.Diurd:BAAALgAECgEJAQAAAA==.Divine:BAAALgADCgYJBgAAAA==.',
Dj='Djanga:BAABLgAECn8XAAMZAAcJVh5rBQC6AQAZAAYJwx9rBQC6AQAGAAQJuxohZAAlAQAAAA==.',
Dk='Dkchocobussy:BAAALgADCgMJAwAAAA==.Dkdiso:BAAALgADCgIJAgAAAA==.',
Do='Doctorevil:BAAALgAECgYJEAAAAA==.Dogglefrog:BAAALgADCgEJAQAAAA==.Dominance:BAAALgADCgEJAgAAAA==.Doranthsæ:BAAALgADCgcJBwABLgAECggJIAAZAOoaAA==.Dorito:BAAALgAECgYJEAAAAA==.Dothausen:BAAALgADCgYJBgAAAA==.',
Dr='Dracaaron:BAAALgAECgUJBwAAAA==.Dragonevil:BAAALgADCgYJBgAAAA==.Dragonfly:BAAALgADCgEJAQAAAA==.Dragooned:BAABLgAECn8UAAIOAAcJJSQILgC5AgAOAAcJJSQILgC5AgAAAA==.Dragussy:BAAALgAECgQJBAAAAA==.Drakenallure:BAAALgAECgkJEAAAAA==.Drakkisath:BAABLgAECn8ZAAMaAAcJ8BT1BwBtAQAaAAcJ8BT1BwBtAQAbAAIJGxK3NABuAAAAAA==.Draknethal:BAAALgAECgIJAgAAAA==.Dramn:BAAALgADCgMJAwAAAA==.Drango:BAAALgAECggJDwAAAA==.Draugdae:BAABLgAECn8XAAIcAAYJ3B+aCQAGAgAcAAYJ3B+aCQAGAgAAAA==.Drayslinger:BAAALgADCgYJBgAAAA==.Drlechee:BAAALgADCgMJBQAAAA==.Drob:BAEALgADCgkJFQAAAA==.Drukhi:BAABLgAECn8WAAIQAAYJCRybFABXAQAQAAYJCRybFABXAQAAAA==.Drunkalicius:BAAALgAECgcJDgAAAA==.',
Du='Dudepriest:BAAALgAECgYJCwAAAA==.Dungrough:BAAALgAECgIJAwAAAA==.Durtkal:BAABLgAECn8eAAMEAAgJShFfDwCXAQAEAAgJqg9fDwCXAQADAAYJZw7lHwBTAQAAAA==.',
Dw='Dwarlin:BAAALgADCgkJCQAAAA==.',
Dy='Dyonn:BAAALgADCgEJAgAAAA==.',
['Dê']='Dêädpool:BAAALgADCgYJBgAAAA==.',
Ed='Edgeboy:BAAALgAECgYJCgABLgAFFAMJBQAOAGUSAA==.',
Ef='Efarel:BAABLgAECn8kAAIdAAgJhBEDCAChAQAdAAgJhBEDCAChAQAAAA==.Efil:BAAALgADCgkJHgAAAA==.',
El='Eleantha:BAAALgADCgYJBwAAAA==.Elinisar:BAAALgAECgQJBAAAAA==.Elsa:BAABLgAECn8ZAAIOAAYJMgwmKgAkAQAOAAYJMgwmKgAkAQAAAA==.Elzza:BAAALgADCgYJCQAAAA==.',
Em='Embear:BAAALgADCgcJEAAAAA==.',
En='Enjaydin:BAAALgADCgcJCAAAAA==.Enjaydo:BAABLgAECn8aAAIOAAgJHhd0DADqAQAOAAgJHhd0DADqAQAAAA==.',
Ep='Epicfurry:BAAALgAECgQJBwAAAA==.',
Er='Ereile:BAAALgAECgUJBwAAAA==.',
Es='Escanor:BAAALgADCgYJBgAAAA==.',
Eu='Eukelade:BAAALgADCgcJBwABLgAECgkJJQALANAdAA==.Eurythmics:BAABLgAECn8ZAAIQAAcJUxWJDQCbAQAQAAcJUxWJDQCbAQAAAA==.',
Ev='Evonahh:BAAALgADCgcJEwAAAA==.',
Ex='Exelion:BAABLgAECn8YAAIUAAYJvCHMFAA3AgAUAAYJvCHMFAA3AgAAAA==.Explogan:BAAALgADCgkJFwAAAA==.',
Ez='Ezanah:BAAALgADCgUJBQAAAA==.Ezrack:BAAALgADCgEJAQAAAA==.',
Fa='Faeyrin:BAABLgAECn8WAAITAAcJMBKSAgBFAQATAAcJMBKSAgBFAQAAAA==.Fahooquazaad:BAAALgADCgcJGQAAAA==.Falconsg:BAAALgADCgQJBAAAAA==.Fancy:BAAALgAECgcJEQAAAA==.Faythlis:BAAALgAECgYJEgAAAA==.',
Fe='Feetlesmcdee:BAAALgAECgQJBwAAAA==.Felf:BAAALgADCgcJBwAAAA==.Felfáádaern:BAEALgAECgYJEgAAAA==.Felporch:BAAALgAECgYJDwAAAA==.',
Fi='Filburt:BAAALgADCgEJAQAAAA==.',
Fk='Fkton:BAAALgADCgIJAgAAAA==.',
Fl='Flamediso:BAAALgADCgUJBQAAAA==.Flourchild:BAAALgADCgEJAQAAAA==.Flowermound:BAAALgAECgEJAQAAAA==.Flowerrose:BAAALgADCgYJBgAAAA==.',
Fo='Forrester:BAAALgAECgYJCgAAAA==.Fox:BAACLgAFFH8IAAIUAAMJbx87BgAbAQAUAAMJbx87BgAbAQAuAAQKfxoAAhQACAkXHgoLAJ4CABQACAkXHgoLAJ4CAAAA.',
Fr='Freight:BAAALgADCgMJAwAAAA==.Friedcry:BAAALgADCgYJBgAAAA==.Fron:BAAALgAECgMJAwAAAA==.Fronie:BAAALgADCgcJAwAAAA==.',
Fu='Fujikujaku:BAAALgAECgYJDQAAAA==.Fulmetal:BAAALgAECgQJBAAAAA==.Funerris:BAAALgADCgEJAQABLgAFFAUJCQAeAEgIAA==.Funiris:BAACLgAFFH8JAAIeAAUJSAhVBQB3AQAeAAUJSAhVBQB3AQAuAAQKfxUAAx4ABwnsFd8oAJMBAB4ABwnsFd8oAJMBAAwABQmKDiEyABABAAAA.Funkalicious:BAACLgAFFH8FAAISAAIJLg13FgCeAAASAAIJLg13FgCeAAAuAAQKfyEAAhIACQnJG2cTAIUCABIACQnJG2cTAIUCAAAA.',
['Fé']='Félo:BAABLgAECn8YAAIDAAYJMiQSBgBwAgADAAYJMiQSBgBwAgAAAA==.',
Ga='Garathor:BAAALgADCgIJAgAAAA==.Garthoneeye:BAAALgAECgMJBAAAAA==.Gazreyna:BAAALgAECgYJDAAAAA==.',
Gc='Gcarne:BAAALgAECgcJEwAAAA==.',
Ge='Genz:BAAALgADCgEJAQAAAA==.Genós:BAABLgAECn8ZAAMCAAYJbxtKBQBjAQAdAAYJkxo9NQDUAQACAAYJsRZKBQBjAQAAAA==.Gerardo:BAAALgAECgIJAgAAAA==.',
Gh='Ghurri:BAAALgADCgQJBgAAAA==.',
Gi='Gibs:BAAALgAECgYJCgAAAA==.Ginnee:BAAALgAECgEJAgAAAA==.Ginnion:BAAALgAECgYJDQAAAA==.Girthytail:BAAALgAECgYJEQAAAA==.',
Gl='Glaedor:BAAALgAECgQJBAAAAA==.Glakenspheal:BAABLgAECn8XAAIMAAYJKQvuCgAcAQAMAAYJKQvuCgAcAQAAAA==.Glamorous:BAAALgAECgYJCAAAAA==.Glein:BAAALgADCgMJAwABLgAECgcJFAAKALscAA==.',
Go='Gongfu:BAAALgADCgYJBgAAAA==.Goonie:BAAALgAECgYJBwAAAA==.',
Gr='Graestoke:BAABLgAECn8WAAIOAAgJuB5hNAChAgAOAAgJuB5hNAChAgAAAA==.Graevana:BAAALgADCgEJAQAAAA==.Gregorizz:BAAALgAECgEJAgAAAA==.Greyaura:BAAALgAECgQJBAAAAA==.Greybeast:BAAALgAECgYJDAAAAA==.Greyfoxy:BAAALgAECgYJDAAAAA==.Grianick:BAAALgADCgcJCwABLgAECgYJDQAIAAAAAA==.Growls:BAAALgAECgYJEwAAAA==.',
Gy='Gyaat:BAAALgADCggJDgAAAA==.',
['Gõ']='Gõldenchild:BAAALgAECgQJBwAAAA==.',
Ha='Habenero:BAAALgAECgUJDgAAAA==.Hagar:BAAALgAECgYJEwAAAA==.Hairycow:BAAALgADCgYJBgAAAA==.Hairypitts:BAABLgAECn8aAAIPAAgJIxRrAgCzAQAPAAgJIxRrAgCzAQAAAA==.Hammertime:BAAALgAECgYJDQAAAA==.Harabrew:BAAALgADCggJDAAAAA==.Haraniantha:BAAALgAECgYJEAAAAA==.Hardø:BAAALgADCgcJCAAAAA==.Hazzbek:BAAALgADCgUJBQAAAA==.',
He='Heiboss:BAAALgAECgQJBQABLgAECggJHAAHACsjAA==.Heipal:BAAALgADCgYJBgABLgAECggJHAAHACsjAA==.Heiranir:BAAALgADCgYJEgABLgAECggJHAAHACsjAA==.Hellbane:BAAALgAECgQJCgAAAA==.Hemit:BAAALgAECgMJAwABLgAECggJFgAOALgeAA==.Hempknight:BAAALgADCgQJBAAAAA==.',
Hi='Hinomiko:BAAALgAECgMJAwABLgAECgUJCQAIAAAAAA==.',
Ho='Holycowch:BAAALgAECgYJDAAAAA==.Honeyb:BAAALgAECgQJBwAAAA==.Hoodieallen:BAAALgADCgQJBAAAAA==.Hoofthor:BAAALgADCgEJAQAAAA==.Hootiedixon:BAAALgAECgMJBgAAAA==.',
Hu='Hughjaculate:BAAALgAECgQJBwAAAA==.Huran:BAABLgAECn8cAAMHAAgJKyOEBgDOAgAHAAgJKyOEBgDOAgARAAEJuwipHwE2AAAAAA==.',
Id='Idcritthat:BAAALgAECgYJEAABLgAECgcJEwAIAAAAAA==.',
Ig='Ignignokt:BAEBLgAECn8cAAMQAAgJyyG2DADaAgAQAAgJyyG2DADaAgAfAAEJzhqohwA0AAAAAA==.Igvoker:BAEALgAECgYJBgABLgAECggJHAAQAMshAA==.',
Il='Illadont:BAAALgADCgEJAQAAAA==.Illith:BAAALgADCgEJAQAAAA==.',
Im='Imirohe:BAABLgAECn8VAAMOAAcJrggouwBrAQAOAAcJrggouwBrAQAYAAEJoQOUIgAcAAAAAA==.',
In='Inarush:BAABLgAECn8XAAIgAAcJewYCBQDzAAAgAAcJewYCBQDzAAAAAA==.',
Ir='Ira:BAAALgADCgIJAgAAAA==.Ironfistt:BAAALgADCgYJBgAAAA==.Ironknife:BAAALgADCggJGAAAAA==.Ironshield:BAABLgAECn8cAAIQAAkJZyCYBQAzAwAQAAkJZyCYBQAzAwAAAA==.',
Iv='Ivie:BAAALgAECgQJBgAAAA==.',
Iw='Iwishiknew:BAABLgAECn8UAAIdAAgJYAkYEQAfAQAdAAgJYAkYEQAfAQAAAA==.',
Iz='Iztras:BAAALgAECgIJAgAAAA==.Izuras:BAAALgAECgkJBwAAAA==.Izzit:BAAALgAECgQJBwAAAA==.',
Ja='Ja:BAAALgAECggJEQAAAA==.Jabbtrak:BAAALgAECgUJCQAAAA==.Jabtrakk:BAAALgADCggJCAAAAA==.Jacodin:BAAALgAECgQJBAAAAA==.Jacquestrapp:BAAALgADCgkJDAAAAA==.Jakiepoobear:BAAALgAECgYJDQAAAA==.Jambie:BAAALgAECgcJEgAAAA==.',
Je='Jedery:BAAALgAECgYJEgAAAA==.',
Jg='Jgglephysyx:BAAALgAECgkJBgAAAA==.',
Ji='Jianyü:BAABLgAECn8fAAINAAgJ2RwKJQCTAgANAAgJ2RwKJQCTAgAAAA==.Jimbæn:BAAALgADCgYJCAAAAA==.',
Jo='Jollyandy:BAEALgAECgUJBwABLgAECgYJBgAIAAAAAA==.Jolynn:BAABLgAECn8XAAIhAAgJywqMBQB6AQAhAAgJywqMBQB6AQAAAA==.Joroldess:BAABLgAECn8WAAIiAAYJKhjiEwCOAQAiAAYJKhjiEwCOAQAAAA==.',
Ju='Juzam:BAAALgADCgcJFgAAAA==.',
['Jü']='Jüggernaut:BAAALgAECgMJAwAAAA==.',
Ka='Kahndumb:BAAALgAECgcJEwAAAA==.Kaida:BAAALgAECgQJBAAAAA==.Kaio:BAAALgADCgMJAwAAAA==.Kalahan:BAAALgAECgYJDwAAAA==.Kalimaa:BAAALgAECgQJBQAAAA==.Kaotut:BAAALgADCgQJBAAAAA==.Kappakappa:BAAALgAECgMJAwAAAA==.Kardrion:BAAALgAECgIJAgAAAA==.Karigyn:BAABLgAECn8ZAAIWAAcJrSKiAAAyAgAWAAcJrSKiAAAyAgAAAA==.Karun:BAABLgAECn8bAAITAAgJng6dAQCaAQATAAgJng6dAQCaAQAAAA==.Kasok:BAAALgAECgYJCAAAAA==.Katren:BAAALgADCgUJBQAAAA==.Katrienne:BAABLgAECn8WAAIiAAYJdwUYKQDBAAAiAAYJdwUYKQDBAAAAAA==.Katrya:BAAALgADCgkJFQABLgAECgYJFgAiAHcFAA==.Katsfood:BAAALgADCgkJFQAAAA==.Kauzarukus:BAAALgAECgcJBgAAAA==.Kaylid:BAABLgAECn8UAAIjAAYJUx52AQBvAQAjAAYJUx52AQBvAQAAAA==.Kaylou:BAAALgADCgcJBwABLgAECgYJGQANAGcIAA==.Kazeralana:BAAALgAECgUJBQAAAA==.Kazzoth:BAABLgAECn8ZAAIQAAYJJxQfFgBKAQAQAAYJJxQfFgBKAQAAAA==.',
Ke='Keeiras:BAAALgAECgkJCQAAAA==.Keilen:BAAALgADCgUJBAAAAA==.Kelasha:BAABLgAECn8XAAIRAAYJ3h7vEQCEAQARAAYJ3h7vEQCEAQAAAA==.',
Kh='Khadgär:BAAALgAECgYJCwAAAA==.Khalika:BAAALgAECgQJBAAAAA==.Kharanys:BAAALgADCgcJBwAAAA==.',
Ki='Kilroar:BAAALgADCgkJCQAAAA==.Kinoplex:BAAALgADCgYJDAABLgAECgMJAwAIAAAAAA==.',
Kl='Klassiq:BAAALgADCgUJBQAAAA==.Klax:BAAALgADCgkJDwAAAA==.Klokateer:BAABLgAECn8bAAMWAAgJIRilBQAuAgAWAAgJ4BelBQAuAgAVAAUJ4w/bOgBCAQAAAA==.Klzx:BAABLgAECn8XAAIOAAYJ8hb0HgBbAQAOAAYJ8hb0HgBbAQAAAA==.',
Ko='Kobold:BAAALgAECgMJAwABLgAECgUJBQAIAAAAAA==.Komo:BAAALgADCgcJBwAAAA==.Komoou:BAAALgAECgQJBAAAAA==.Komouo:BAAALgADCgMJAwABLgADCgcJBwAIAAAAAA==.Korbi:BAAALgADCgcJEQABLgAECgYJFQASAKwUAA==.Kortek:BAAALgAECgYJEQAAAA==.Korvold:BAAALgAECgcJCwAAAA==.Kosmos:BAAALgAECggJEAAAAA==.Kozath:BAAALgAECgMJBAAAAA==.',
Kr='Kreckon:BAAALgAECgMJAwAAAA==.Kriandor:BAAALgADCgYJCQAAAA==.',
Ks='Kschnell:BAAALgAECgEJAQABLgAFFAMJBQAOAGUSAA==.',
Ku='Kukulkan:BAABLgAECn8YAAIkAAcJtQ8MHwCIAQAkAAcJtQ8MHwCIAQAAAA==.Kuulan:BAABLgAECn8ZAAINAAYJjBZ2HgA4AQANAAYJjBZ2HgA4AQAAAA==.',
La='Larwock:BAAALgAECgQJCAAAAA==.Latwiz:BAAALgADCgYJCQABLgAECggJGQANAJofAA==.',
Le='Leetlebug:BAAALgAECgYJCwAAAA==.Lettÿ:BAAALgAECgMJBAAAAA==.',
Li='Liella:BAAALgADCgEJAQAAAA==.Lightheaded:BAAALgAECgcJCQAAAA==.Lightzwrath:BAAALgAECgUJCQABLgAECgYJBgAIAAAAAA==.Liquid:BAAALgAECgYJDwAAAA==.',
Lo='Loankano:BAAALgAECgYJDQAAAA==.Lockbealady:BAAALgAECgQJCQAAAA==.Lohanoa:BAAALgAECgEJAQAAAA==.Longshanke:BAAALgAECgEJAQAAAA==.Lorebeard:BAAALgADCgcJBwAAAA==.Loreix:BAAALgAECgQJBQAAAA==.Lozzo:BAAALgADCgYJCwAAAA==.',
Lu='Luciferluxx:BAAALgADCgQJBgAAAA==.Lumena:BAAALgADCggJCAAAAA==.Luminai:BAABLgAECn8YAAIUAAgJmBq9EQBUAgAUAAgJmBq9EQBUAgAAAA==.Luminaugty:BAAALgADCgYJBgAAAA==.Lunalea:BAAALgADCgQJBAAAAA==.Lunarthas:BAAALgADCgkJEQAAAA==.Luvinez:BAAALgAECgEJAQAAAA==.Luvinz:BAAALgADCgkJGwAAAA==.',
Ly='Lyllia:BAAALgADCgEJAQAAAA==.Lynchmeup:BAAALgADCgYJBgABLgAECgUJDgAIAAAAAA==.Lyrel:BAABLgAECn8XAAIlAAcJRyBfCgDNAQAlAAcJRyBfCgDNAQAAAA==.',
['Lî']='Lîllîth:BAAALgADCgMJAwAAAA==.',
['Lü']='Lümen:BAAALgADCggJCAABLgADCggJCAAIAAAAAA==.',
Ma='Maarc:BAAALgAECgUJDQAAAA==.Maddragon:BAAALgAECgIJAgAAAA==.Madfurion:BAAALgAECgEJAQAAAA==.Magebot:BAAALgAECgYJCwAAAA==.Magistra:BAAALgADCgcJDwAAAA==.Majestic:BAACLgAFFH8FAAIOAAMJZRIGEQAKAQAOAAMJZRIGEQAKAQAuAAQKfyEAAg4ACQmUHlonANUCAA4ACQmUHlonANUCAAAA.Malvenue:BAAALgAECgkJAgAAAA==.Marly:BAAALgAECgYJDAAAAA==.Mauwy:BAABLgAECn8bAAMSAAgJMRU0HwAWAgASAAgJMRU0HwAWAgAmAAEJMApxowAsAAAAAA==.Mayabutreeks:BAAALgAECgEJAQAAAA==.Mazzerine:BAAALgAECgQJBAAAAA==.',
Mc='Mcbeardface:BAAALgAECgcJEwAAAA==.Mcbullseye:BAAALgAECgUJBAAAAA==.',
Me='Meathole:BAAALgADCgcJBwAAAA==.Megarah:BAAALgAECgMJAwAAAA==.Mental:BAAALgAECgEJAQAAAA==.Mepkaelpto:BAAALgAECgcJDQAAAA==.Mera:BAAALgADCgcJCAAAAA==.Mercury:BAAALgAECgYJCgAAAA==.Meretrix:BAAALgAECgYJDQAAAA==.Messatsu:BAAALgAECgQJBAAAAA==.Metanya:BAAALgAECgUJCQAAAA==.Mew:BAAALgAECgEJAQAAAA==.',
Mi='Miateh:BAAALgAECgEJAQAAAA==.Microdots:BAAALgADCgMJAwAAAA==.Midorí:BAAALgADCgYJBgAAAA==.Mimicme:BAAALgAECgYJDQAAAA==.Minorie:BAAALgADCgIJAgAAAA==.Mitchell:BAAALgAECgcJEQAAAA==.Miwah:BAAALgAECgUJCAAAAA==.',
Mj='Mjolnìr:BAAALgAECgMJCAAAAA==.',
Mo='Modin:BAAALgAECgYJDQAAAA==.Mogarr:BAABLgAECn8WAAICAAcJNw8YHABpAQACAAcJNw8YHABpAQAAAA==.Mohgwyn:BAAALgADCgEJAQAAAA==.Monkglein:BAABLgAECn8UAAIKAAcJuxw1FwAsAgAKAAcJuxw1FwAsAgAAAA==.Monkhei:BAAALgAECgQJBAABLgAECggJHAAHACsjAA==.Mooglewing:BAAALgAECgQJBwAAAA==.Moomoobrncow:BAAALgAECgcJDAAAAA==.Moondream:BAABLgAECn8XAAMQAAYJAhV2FwBAAQAQAAYJAhV2FwBAAQAfAAIJLgimewBVAAAAAA==.Mordicanta:BAABLgAECn8XAAIHAAcJ3RRnBgA+AQAHAAcJ3RRnBgA+AQAAAA==.Morphies:BAAALgADCgcJDQAAAA==.',
Mu='Muerr:BAAALgAECggJEwAAAA==.Muerrizond:BAAALgAECgMJBQABLgAECggJEwAIAAAAAA==.Muerrlin:BAAALgAECgUJBQABLgAECggJEwAIAAAAAA==.Muggel:BAAALgADCgcJGgAAAA==.Mumraa:BAAALgAECgMJAwAAAA==.Mumrawr:BAAALgADCgcJCwAAAA==.Mushroohead:BAABLgAECn8VAAISAAcJ9BoFBQDNAQASAAcJ9BoFBQDNAQAAAA==.',
My='Mystbourn:BAAALgADCgYJCQAAAA==.Mysterbyrnes:BAAALgADCgYJDgAAAA==.Myykiel:BAAALgAECgYJEgAAAA==.',
Na='Naina:BAABLgAECn8XAAImAAYJ2RW2DABxAQAmAAYJ2RW2DABxAQAAAA==.Najaja:BAAALgADCgcJBwAAAA==.Nariely:BAAALgAECgEJAQAAAA==.Natacha:BAAALgAECgEJAQAAAA==.Native:BAAALgAECgUJCAAAAA==.Nayos:BAAALgADCgIJAgAAAA==.',
Ne='Necro:BAABLgAECn8hAAIHAAgJtCIzBQDvAgAHAAgJtCIzBQDvAgAAAA==.Neelothe:BAAALgAECgMJAwAAAA==.Neisa:BAAALgADCgIJAgAAAA==.Nekroz:BAAALgAECgEJAQAAAA==.Nelliel:BAAALgAECgcJEwAAAA==.',
Ni='Nickodemus:BAAALgAECgIJAgAAAA==.Nightle:BAAALgADCggJCwAAAA==.Nihil:BAAALgAECgYJDQABLgAECggJIQAHALQiAA==.Nikano:BAAALgADCgYJBgAAAA==.Ninmah:BAAALgADCgkJIQAAAA==.Niphredil:BAAALgADCgUJDQAAAA==.Nirø:BAABLgAECn8aAAIKAAgJgggmDAAOAQAKAAgJgggmDAAOAQAAAA==.',
No='Noah:BAAALgADCgcJDQAAAA==.Nooky:BAABLgAECn8ZAAILAAYJvx9DBQDSAQALAAYJvx9DBQDSAQAAAA==.',
Nu='Nuatha:BAAALgAECgMJBQAAAA==.Numpty:BAAALgAECgMJBgAAAA==.',
Ny='Nyctero:BAABLgAECn8WAAInAAcJWh5mAgDNAQAnAAcJWh5mAgDNAQAAAA==.Nyrikah:BAAALgADCgcJBwAAAA==.',
['Nö']='Nöstrum:BAAALgADCgMJAwABLgAECgUJBQAIAAAAAA==.',
Ob='Obidiah:BAAALgAECgYJEQAAAA==.',
Oe='Oedipus:BAAALgAECgMJAwAAAA==.',
Oh='Ohioaug:BAAALgADCgEJAQAAAA==.',
Or='Orah:BAAALgAECgUJDQAAAA==.Orpheon:BAAALgAECgMJBQAAAA==.',
Os='Osorn:BAAALgADCgkJCgAAAA==.',
Ot='Otterdoodad:BAAALgAECgQJBAAAAA==.',
Oz='Ozzmosis:BAAALgADCgMJAwAAAA==.',
Pa='Palagem:BAAALgADCgYJBgAAAA==.Palinyes:BAAALgAECgYJDQAAAA==.Pancetta:BAAALgADCgUJCAAAAA==.Pandabits:BAAALgADCgYJBgAAAA==.Papabill:BAAALgAECgYJEgAAAA==.Paperscissor:BAAALgADCgIJAgAAAA==.Paragorn:BAAALgAECgYJEQAAAA==.Pattee:BAAALgAECgYJEgAAAA==.',
Pe='Peachums:BAAALgADCgEJAQAAAA==.Pech:BAAALgAFFAEJAQAAAA==.Peenidin:BAABLgAECn8ZAAIXAAYJPSScFABtAgAXAAYJPSScFABtAgAAAA==.Pemerd:BAAALgAECgUJDQAAAA==.Petite:BAAALgADCgMJAwAAAA==.',
Ph='Phoenixfires:BAAALgADCgYJCAAAAA==.Phoze:BAAALgAECgYJEQAAAA==.Phyai:BAAALgAECgYJDwAAAA==.',
Pi='Pirotanaxdos:BAAALgAECgUJCQAAAA==.Pizzarollzz:BAAALgAECgYJDQAAAA==.',
Pn='Pnutt:BAAALgADCgcJBwAAAA==.',
Po='Ponymalta:BAABLgAECn8lAAIZAAgJ5BdKGwApAgAZAAgJ5BdKGwApAgAAAA==.Popeaganda:BAAALgAECgQJBwAAAA==.Poutine:BAAALgAECgQJBwAAAA==.',
Pr='Prizren:BAAALgAECgIJAgAAAA==.Promethyus:BAABLgAECn8WAAMNAAYJDwYvwwABAQANAAYJDwYvwwABAQAiAAUJxAENDwBlAAAAAA==.Promidan:BAAALgAECgEJAQABLgAFFAQJCQANAPIHAA==.Pryxi:BAABLgAECn8WAAIOAAYJ1Ah+LwAMAQAOAAYJ1Ah+LwAMAQAAAA==.',
Pu='Puffichu:BAAALgADCgMJAwABLgADCgcJFgAIAAAAAA==.Punchline:BAAALgADCgcJBwAAAA==.',
Py='Pyrogar:BAAALgADCgIJAgAAAA==.Pythius:BAAALgAECgEJAQAAAA==.',
['Pó']='Pótatò:BAAALgADCgUJDAAAAA==.',
Qu='Quandaale:BAAALgAECgQJCQABLgAFFAEJAQAIAAAAAA==.Quell:BAAALgADCgEJAQAAAA==.Quepinga:BAAALgADCgUJCAAAAA==.Quiksylver:BAAALgAECgYJEgAAAA==.',
Ra='Rabblerousin:BAAALgAECgEJAgAAAA==.Raegnar:BAAALgADCgYJBgAAAA==.Raggnnar:BAAALgADCgEJAQAAAA==.Rakael:BAAALgADCgMJAwAAAA==.Rava:BAAALgAECgEJAQAAAA==.',
Re='Reckoner:BAAALgAECgQJBAAAAA==.Red:BAABLgAECn8gAAQTAAgJ6x7ZBAABAgARAAgJbhWISQAWAgATAAYJvCLZBAABAgAHAAcJkhGrBQBYAQAAAA==.Rellster:BAAALgAECgUJCgAAAA==.Renix:BAAALgAECgQJBQAAAA==.Rennyo:BAAALgAECgYJEwAAAA==.Resonance:BAAALgAECgEJAgAAAA==.Retsu:BAAALgADCgUJBQAAAA==.Rettbull:BAAALgADCgMJAwAAAA==.Reyujin:BAAALgAECgEJAwAAAA==.',
Rh='Rhyash:BAAALgAECgQJCAAAAA==.',
Ri='Rickdaddty:BAAALgADCgkJCQABLgAECgcJDAAIAAAAAA==.Ricoz:BAAALgAECgQJBQAAAA==.Ridicutie:BAAALgAECgYJDQAAAA==.Rigg:BAAALgAECgUJDgAAAA==.Riggz:BAAALgADCgQJBAABLgAECgUJDgAIAAAAAA==.Rivetro:BAAALgAECgQJBwAAAA==.',
Ro='Rocknroll:BAABLgAECn8eAAIQAAgJ/RwTEwCeAgAQAAgJ/RwTEwCeAgAAAA==.Roll:BAAALgAECgYJEwAAAA==.Rozgrez:BAABLgAECn8UAAMEAAcJehPaFABpAQAEAAYJehPaFABpAQADAAIJ0A5/TQCFAAAAAA==.',
Ru='Rufus:BAAALgADCgkJDgAAAA==.Rumlidorgah:BAAALgAECgcJEAAAAA==.Russbus:BAABLgAECn8bAAMNAAgJ6A4tGQBZAQANAAcJbgwtGQBZAQAXAAgJEQf6XAAJAQAAAA==.Ruune:BAAALgAECgQJBAAAAA==.',
Ry='Rynmorelle:BAAALgADCggJDgAAAA==.',
['Ré']='Réven:BAABLgAECn8ZAAIlAAYJEh3gEgBpAQAlAAYJEh3gEgBpAQAAAA==.',
Sa='Sadienna:BAAALgAECggJEwAAAA==.Sandrï:BAAALgAECgYJDgAAAA==.Sane:BAAALgAECgYJDQAAAA==.Saoiirse:BAAALgAECgYJEgAAAA==.Saraella:BAAALgAECgIJAgAAAA==.Sasso:BAAALgADCgIJAgAAAA==.Sawako:BAAALgAECgcJDQAAAA==.',
Sc='Scalar:BAAALgADCgEJAQAAAA==.Scalyboi:BAAALgADCgMJAwABLgAFFAMJBQAOAGUSAA==.Scarletts:BAAALgADCgUJBgAAAA==.Schlitzie:BAAALgADCgIJAgAAAA==.Scrapes:BAAALgADCgMJAwAAAA==.Scuba:BAAALgAECgYJCwAAAA==.',
Se='Seraphyne:BAAALgAECgIJAgABLgAFFAUJEQAGAP4VAA==.Sevencharlie:BAAALgAECgQJBwAAAA==.',
Sh='Shadowho:BAAALgAECgQJBwAAAA==.Shaladro:BAAALgADCgUJCAAAAA==.Shalanaz:BAAALgADCgEJAQAAAA==.Shamutty:BAAALgADCgMJAwABLgAECggJFgAOALgeAA==.Sharasdal:BAAALgAECgEJAQABLgAECgIJAgAIAAAAAA==.Sherief:BAAALgADCgQJBAAAAA==.Shinjô:BAAALgAECgQJBwAAAA==.Shiroishi:BAAALgADCgcJBwABLgAECgYJEwAIAAAAAA==.Shivaray:BAAALgADCgUJBQAAAA==.Shiveria:BAAALgADCgYJCwAAAA==.Shocklesner:BAAALgAECgQJCAAAAA==.Shorkaan:BAAALgAECgEJAQAAAA==.Shouganai:BAAALgAECgQJBwAAAA==.Shupaz:BAAALgAECgIJAgAAAA==.',
Si='Siddha:BAAALgADCgYJBgABLgAECgQJBQAIAAAAAA==.Sieria:BAAALgAECgIJAwAAAA==.Siieerr:BAAALgAFFAIJAgAAAA==.Silvermind:BAAALgAECgEJAQAAAA==.Sinaar:BAAALgAECgIJAwAAAA==.Sindena:BAABLgAECn8YAAIEAAcJOhSjXACyAQAEAAcJOhSjXACyAQAAAA==.Sixsanity:BAAALgAECgQJCAAAAA==.',
Sk='Skavos:BAAALgAECgYJBwAAAA==.Skillcommand:BAAALgAECgQJCQAAAA==.Skipperino:BAAALgADCggJDQAAAA==.Skyemage:BAAALgAECgEJAgAAAA==.',
Sl='Slotz:BAABLgAECn8ZAAIXAAcJXRhgLQDPAQAXAAcJXRhgLQDPAQAAAA==.',
Sm='Smallcoomer:BAAALgAECgcJDgAAAA==.Smallss:BAAALgAECgUJBgAAAA==.Smike:BAABLgAECn8ZAAINAAYJZwh7KwDyAAANAAYJZwh7KwDyAAAAAA==.',
Sn='Sneeze:BAAALgAECgEJAQAAAA==.Snuggles:BAAALgADCgUJBwAAAA==.',
So='Soferan:BAAALgAECgYJEQAAAA==.Softpaws:BAAALgADCggJDQAAAA==.Sonarr:BAAALgAECgQJBAAAAA==.',
Sp='Spacemilk:BAAALgAECgYJDgAAAA==.Spark:BAAALgAECgEJAQAAAA==.Spicymeat:BAAALgADCgcJBwABLgAFFAMJBQAOAGUSAA==.Sputty:BAAALgAECgQJBgABLgAECggJFgAOALgeAA==.',
St='Stankmouth:BAAALgAECgMJDwAAAA==.Stellas:BAAALgADCgUJCAABLgAECgQJBwAIAAAAAA==.Stesha:BAAALgADCgcJCwABLgAECgYJDQAIAAAAAA==.Steviewonder:BAABLgAECn8YAAIlAAcJMxQjFQBUAQAlAAcJMxQjFQBUAQAAAA==.Stinkerton:BAAALgAECgYJBgAAAA==.Stonedfrog:BAAALgADCgcJBwAAAA==.Stonefather:BAABLgAECn8cAAILAAYJbg0GDgADAQALAAYJbg0GDgADAQAAAA==.Stonewall:BAAALgADCgEJAgAAAA==.Strangelets:BAAALgAECgQJBAAAAA==.Strangewayes:BAAALgADCgMJAwAAAA==.Stönk:BAAALgAECgYJDAAAAA==.',
Su='Succulentman:BAABLgAECn8eAAIlAAgJ+SBWFQDXAgAlAAgJ+SBWFQDXAgAAAA==.Sufferyn:BAAALgADCgcJBwAAAA==.Sunreaver:BAAALgADCgYJCgAAAA==.Surolath:BAABLgAECn8XAAIcAAcJ0h9uAQAJAgAcAAcJ0h9uAQAJAgAAAA==.',
Sw='Swaggles:BAABLgAECn8XAAIhAAcJ0CVBAQBNAgAhAAcJ0CVBAQBNAgAAAA==.Swiftcast:BAAALgADCgYJDAAAAA==.Swiftpalms:BAAALgAECgYJBgAAAA==.Swompfox:BAAALgADCgkJDwAAAA==.',
Sy='Sygon:BAABLgAECn8XAAIfAAcJXhMxAwCGAQAfAAcJXhMxAwCGAQAAAA==.Sylvannaa:BAAALgAECgYJBwAAAA==.Syntherizena:BAAALgAECgYJBgAAAA==.Synthesized:BAAALgAECgUJBQAAAA==.',
['Só']='Sóng:BAABLgAECn8aAAMUAAcJLh3ZEwBAAgAUAAcJLh3ZEwBAAgAeAAEJSQ7lXgA7AAAAAA==.',
Ta='Tacitus:BAAALgAECgYJCwAAAA==.Tairrad:BAAALgAECgUJBwAAAA==.Takeru:BAAALgADCgcJEAAAAA==.Talasmar:BAAALgADCgUJBQAAAA==.Tapkora:BAAALgAECgQJCAAAAA==.Tapsum:BAAALgADCgUJBQAAAA==.Tarirn:BAAALgADCgEJAQAAAA==.Taurtem:BAAALgAECgQJBQAAAA==.Taylia:BAAALgAECgQJCAABLgAECgcJGAAMAIYTAA==.Tayona:BAAALgAECgIJAgAAAA==.Tazildek:BAAALgAECgEJAQAAAA==.',
Te='Technique:BAAALgAECgYJCgAAAA==.Tergrid:BAAALgAECgMJAwAAAA==.Terial:BAABLgAECn8ZAAIXAAYJ7R79CQChAQAXAAYJ7R79CQChAQAAAA==.Textoffender:BAAALgAECgQJBgAAAA==.',
Th='Thajeebus:BAAALgADCgEJAQAAAA==.Thatsneat:BAAALgAECgQJBQAAAA==.Thecapt:BAABLgAECn8kAAIdAAkJ8xk0AgBHAgAdAAkJ8xk0AgBHAgAAAA==.Theôdöræ:BAAALgAECgkJAgAAAA==.Thorinfel:BAABLgAECn8fAAIlAAgJbRZ3NgAdAgAlAAgJbRZ3NgAdAgAAAA==.Thsaemage:BAAALgAECgQJBAABLgAECggJIAAZAOoaAA==.Thunderkiss:BAAALgADCgkJCQAAAA==.Thunran:BAAALgAECgQJBAAAAA==.',
Ti='Tiaoma:BAAALgADCgQJBgAAAA==.Tieria:BAAALgAECgYJDQAAAA==.Tikao:BAAALgAECgYJEgAAAA==.Tinna:BAAALgAECgcJBgAAAA==.',
Tj='Tjhookèr:BAAALgAECgUJCQAAAA==.',
To='Tobajal:BAABLgAECn8XAAIUAAcJnxrbAwAIAgAUAAcJnxrbAwAIAgAAAA==.Toletheus:BAAALgAECgYJEQAAAA==.Tomin:BAAALgAECgQJCAAAAA==.Totemique:BAAALgADCgcJBwABLgAECgYJCgAIAAAAAA==.Totumfknpole:BAAALgADCgEJAQAAAA==.',
Tr='Treeperson:BAAALgAECgYJDQAAAA==.Treyni:BAAALgADCgIJAgAAAA==.Trickyric:BAAALgAECgUJCwAAAA==.Trilgy:BAAALgADCgkJCgAAAA==.Trowel:BAAALgAECgcJEgABLgAECggJFgAOALgeAA==.',
Ts='Tsuyoimono:BAAALgAECgUJCQAAAA==.',
Tu='Turisx:BAAALgADCgMJBAAAAA==.',
Tw='Twiddydh:BAAALgAECgYJCwAAAA==.',
Ty='Tydroin:BAAALgADCgMJAwAAAA==.Tytoalba:BAAALgAECgMJAwAAAA==.',
Uk='Ukiru:BAAALgADCgMJAwAAAA==.',
Un='Ungonelilith:BAAALgADCgYJBgAAAA==.',
Ur='Uratsukasama:BAAALgAECgIJAwAAAA==.Urion:BAAALgAECgYJEQAAAA==.',
Va='Vacaite:BAAALgAECgIJAgAAAA==.Vagiant:BAABLgAECn8XAAIPAAYJRhSuFABoAQAPAAYJRhSuFABoAQAAAA==.Valyna:BAAALgADCgEJAQAAAA==.Vanya:BAAALgAECgYJEgAAAA==.Vash:BAAALgADCgYJBgABLgAECgQJBwAIAAAAAA==.Vasso:BAAALgAECgMJAwAAAA==.',
Ve='Velinae:BAAALgAECgkJBgAAAA==.Velveen:BAABLgAECn8VAAISAAYJrBREDwATAQASAAYJrBREDwATAQAAAA==.',
Vi='Viallure:BAAALgAECgcJDQABLgAECgkJEAAIAAAAAA==.Vilebloom:BAEALgAECgYJEQAAAA==.Viridius:BAAALgAECgEJAQAAAA==.Vitamind:BAAALgADCgEJAQAAAA==.',
Vo='Voidmulan:BAAALgADCgQJBwAAAA==.Volwraith:BAAALgAECgcJBgAAAA==.Vonmortis:BAAALgADCgkJFwAAAA==.',
Wa='Wagguslight:BAABLgAECn8ZAAINAAcJDw82IwAdAQANAAcJDw82IwAdAQAAAA==.Warzak:BAAALgAECgYJDAAAAA==.Wayne:BAAALgADCgUJBQAAAA==.',
We='Wendybacon:BAAALgAECgYJEwAAAA==.',
Wh='Whateverdude:BAAALgAECgMJAwAAAA==.Whiskeyshots:BAAALgADCgIJAgAAAA==.Whytè:BAABLgAECn8bAAIGAAgJuh/EAQDAAgAGAAgJuh/EAQDAAgAAAA==.',
Wi='Wigeon:BAAALgADCggJCAAAAA==.Wiickett:BAABLgAECn8fAAMbAAgJtB29BAC5AgAbAAgJcx29BAC5AgAaAAYJrh+BIwCiAQAAAA==.Wilbur:BAAALgAECgEJAQAAAA==.Wildebeard:BAACLgAFFH8FAAIXAAMJOSAaBQAXAQAXAAMJOSAaBQAXAQAuAAQKfx0AAhcACAnRJD0FABgDABcACAnRJD0FABgDAAAA.Wilferal:BAAALgAECgQJBAAAAA==.Willaá:BAAALgAECgUJBQAAAA==.Willowyn:BAABLgAECn8hAAILAAkJcxb8AgAsAgALAAkJcxb8AgAsAgAAAA==.Wingmans:BAAALgAECgQJBwAAAA==.Wizzpeaver:BAAALgAECgQJCAAAAA==.',
Wo='Wonderwizard:BAAALgAECgYJEgAAAA==.',
Wr='Wraeth:BAAALgADCgYJBgAAAA==.Wrathhoof:BAAALgAECgYJBgAAAA==.',
Xa='Xahra:BAAALgADCgcJBwAAAA==.Xaralyss:BAAALgAECgQJBwAAAA==.',
Xy='Xylias:BAAALgADCgMJAwAAAA==.',
Ya='Yamon:BAAALgADCggJEAAAAA==.',
Yo='Yodef:BAABLgAFFH8GAAIRAAIJhREPHACGAAARAAIJhREPHACGAAAAAA==.Yorri:BAAALgAECgMJAwAAAA==.',
Yu='Yucca:BAABLgAECn8aAAMRAAcJRBgFXADeAQARAAcJRBgFXADeAQAHAAEJAADOFwAAAAAAAA==.Yuda:BAAALgAECgEJBAAAAA==.Yudaneyo:BAAALgAECgEJAwAAAA==.Yukiteru:BAABLgAECn8UAAIlAAcJUBiHDQCjAQAlAAcJUBiHDQCjAQAAAA==.Yurito:BAAALgAECgYJEwAAAA==.',
Yz='Yzernara:BAAALgAECgEJAQABLgAECgIJAgAIAAAAAA==.',
Za='Zabrina:BAAALgAECgYJDQAAAA==.Zaiel:BAAALgADCgMJAwAAAA==.Zappybains:BAABLgAECn8XAAImAAcJWxxJBAAvAgAmAAcJWxxJBAAvAgAAAA==.Zarakii:BAAALgAECgYJCgAAAA==.',
Ze='Zekken:BAAALgADCgMJBAAAAA==.Zelaina:BAAALgAECgUJCAAAAA==.',
Zi='Zi:BAAALgADCgQJBQABLgAECgkJIgAJAC0fAA==.',
Zu='Zuda:BAAALgAECgEJAwAAAA==.Zupaz:BAAALgADCgEJAQAAAA==.',
Zy='Zylluz:BAAALgAECgYJBgAAAA==.Zylos:BAAALgAECgYJEwAAAA==.',
['Zì']='Zìnn:BAAALgADCgIJAgAAAA==.',
['Äs']='Äshébringer:BAACLgAFFH8JAAINAAUJPxxqCABuAQANAAUJPxxqCABuAQAuAAQKfx4AAg0ACQkwJJYAABIDAA0ACQkwJJYAABIDAAAA.',
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

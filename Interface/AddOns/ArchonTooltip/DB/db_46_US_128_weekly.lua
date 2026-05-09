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

local lookup = {'Warrior-Protection','Mage-Frost','Warrior-Arms','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Preservation','Priest-Discipline','Paladin-Retribution','DemonHunter-Devourer','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Paladin-Protection','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaryn:BAAALgAECgYJBwABLgAECgcJJwABAAgaAA==.',
Ab='Absynthia:BAABLgAECn8WAAICAAcJRQXdhAAIAQACAAcJRQXdhAAIAQAAAA==.',
Ac='Academe:BAABLgAECn8gAAICAAcJIxODSACOAQACAAcJIxODSACOAQAAAA==.Acrid:BAAALgAECgEJAQAAAA==.',
Ad='Ados:BAAALgAECgQJCwAAAA==.',
Ae='Aeity:BAAALgAECgYJCwAAAA==.Aellion:BAAALgADCgEJAQAAAA==.Aellopus:BAAALgAECgEJAQAAAA==.Aenas:BAAALgAECggJDwAAAA==.Aero:BAABLgAECn8nAAMBAAcJCBomCgDOAQABAAcJmxkmCgDOAQADAAYJZw6EFwA+AQAAAA==.',
Af='Afflictedd:BAAALgAECgEJAQAAAA==.',
Ag='Agapetus:BAAALgADCgYJBgAAAA==.',
Ah='Ahren:BAAALgAECgQJCwAAAA==.Ahuizott:BAAALgAECggJCAABLgAECggJCAAEAAAAAA==.',
Ak='Akata:BAAALgADCgcJBwAAAA==.',
Al='Alayder:BAAALgADCgYJBgAAAA==.Almighty:BAAALgAECgkJDgAAAA==.Alomeo:BAAALgADCggJDAAAAA==.',
Am='Amarí:BAAALgADCggJGAAAAA==.Amayêlle:BAAALgADCggJGAAAAA==.Amendos:BAAALgAECgYJCwAAAA==.Amiliane:BAABLgAECn8mAAQFAAgJchCDCgAtAQAFAAYJtRGDCgAtAQAGAAUJmwwicgDlAAAHAAUJIwpaHQCHAAAAAA==.Amunshi:BAAALgADCgQJBAAAAA==.Amz:BAAALgAECgQJBwAAAA==.',
An='Anadrien:BAABLgAECn8qAAMIAAgJ0x6lCADAAgAIAAgJ0x6lCADAAgAJAAMJzQ0uOgCgAAAAAA==.Ancelagon:BAAALgADCgYJBgAAAA==.Andrae:BAAALgAECgYJBgAAAA==.Andrastae:BAAALgAECgYJBgAAAA==.Angrima:BAAALgAECgEJAQAAAA==.Angrimia:BAABLgAECn8mAAIKAAcJhR0UCQDuAQAKAAcJhR0UCQDuAQAAAA==.Anju:BAAALgAECgEJAgAAAA==.Ansticé:BAAALgADCgYJBgAAAA==.Antal:BAAALgAECgYJBwAAAA==.Anthelyn:BAAALgADCgcJBwAAAA==.',
Ar='Arannis:BAAALgADCgcJEAAAAA==.Arboria:BAAALgAECggJCwAAAA==.Archielgh:BAAALgAECgYJEQAAAA==.Areldor:BAAALgAECggJBQAAAA==.Aremethea:BAAALgADCggJDgABLgAECgYJCwAEAAAAAA==.Ariaa:BAAALgADCggJDAAAAA==.Arkannah:BAAALgADCgcJBwAAAA==.Aronk:BAABLgAECn8mAAQLAAgJyRHVIQAYAQAMAAUJ3RayPgBKAQALAAYJPQ3VIQAYAQANAAgJ1gO1LADtAAAAAA==.Arore:BAAALgADCgEJAQABLgAECggJJgALAMkRAA==.Aroreck:BAAALgADCgMJAwABLgAECggJJgALAMkRAA==.Arorepriest:BAAALgADCgcJBwABLgAECggJJgALAMkRAA==.Articulàte:BAAALgAECgQJBAAAAA==.Arzec:BAABLgAECn8aAAIOAAcJ+wX+EwAAAQAOAAcJ+wX+EwAAAQAAAA==.Arîel:BAAALgAECgEJAQAAAA==.',
At='Atheania:BAAALgAECgkJBQAAAA==.',
Av='Avestara:BAABLgAECn8nAAIPAAcJTR2rCwAXAgAPAAcJTR2rCwAXAgAAAA==.',
Aw='Awenlock:BAEALgADCgUJBAAAAA==.',
Ay='Ayleesha:BAAALgAECgUJBAAAAA==.Ayluid:BAAALgAECgUJCwAAAA==.',
Az='Azavtani:BAAALgADCgEJAgAAAA==.Azazill:BAAALgAECggJDgAAAA==.Azeralle:BAAALgADCgkJCgAAAA==.Azmodeus:BAAALgAECgMJBAAAAA==.Azoril:BAABLgAECn8rAAIQAAgJOhESOACfAQAQAAgJOhESOACfAQAAAA==.Azùla:BAAALgADCgcJDQAAAA==.',
['Aí']='Aídeen:BAAALgAECgYJDwAAAA==.',
Ba='Baal:BAAALgADCgcJEQAAAA==.Babaspook:BAAALgAECggJCwAAAA==.Badseedz:BAAALgAECgYJBgAAAA==.Baelnorn:BAABLgAECn8gAAMGAAgJHh+/EQBVAgAGAAgJ+h6/EQBVAgAFAAMJ+RbySgCNAAAAAA==.Bains:BAAALgADCgcJBwAAAA==.Baja:BAAALgAECgQJBwAAAA==.Bandit:BAAALgAECgUJCgAAAA==.Barress:BAAALgAECgEJAQAAAA==.Batrela:BAAALgAECgYJDwAAAA==.Battleturtle:BAAALgAECgYJCwAAAA==.Batôsai:BAAALgAECgEJAgAAAA==.Bazir:BAAALgAECgIJAgABLgAFFAUJDgACAE4UAA==.',
Bd='Bddaddy:BAAALgAECgMJBAAAAA==.',
Be='Beardiso:BAAALgADCgEJAQAAAA==.Bearjuu:BAAALgAECgIJBAABLgAECgkJHAARAPQbAA==.Bearpawz:BAABLgAECn8pAAISAAkJ0xmlAgB6AgASAAkJ0xmlAgB6AgAAAA==.Bearrel:BAAALgAECgYJCwAAAA==.Bearrier:BAAALgADCgEJAQAAAA==.Bekens:BAABLgAECn8aAAITAAgJFCEMDwBeAgATAAgJFCEMDwBeAgAAAA==.Belaraariaae:BAAALgADCgQJBAAAAA==.Benastiel:BAAALgADCgYJBwAAAA==.Benwetta:BAAALgAECgMJAwAAAA==.Bernardboggs:BAABLgAECn8VAAILAAcJrBvgDADqAQALAAcJrBvgDADqAQAAAA==.Bethbathory:BAABLgAECn8nAAIHAAgJgRsaAgAXAgAHAAgJgRsaAgAXAgAAAA==.',
Bh='Bheefknight:BAAALgAECgUJEgAAAA==.',
Bi='Bierbro:BAABLgAECn8VAAIUAAcJiRHfZwATAQAUAAcJiRHfZwATAQAAAA==.Bigfacts:BAAALgAECggJDQAAAA==.Bigoldee:BAAALgADCgUJBQAAAA==.Bigyk:BAAALgADCgYJBgAAAA==.Billié:BAABLgAECn8jAAQGAAgJkiOZBgDaAgAGAAcJkiOZBgDaAgAFAAMJ5iD9KAAfAQAHAAIJ1h3hLABFAAAAAA==.',
Bk='Bk:BAAALgADCgMJAwAAAA==.',
Bl='Blightheaded:BAAALgAECgQJBwABLgAECgcJCQAEAAAAAA==.Blindëye:BAAALgAECgYJDQAAAA==.Blumir:BAAALgAECgYJCQAAAA==.',
Bn='Bnththeocean:BAAALgAECggJEgAAAA==.',
Bo='Bobmauley:BAAALgADCgQJBAAAAA==.Bombkin:BAABLgAECn8nAAIIAAcJYiToDgBlAgAIAAcJYiToDgBlAgAAAA==.Bonchonn:BAACLgAFFH8GAAITAAMJ9BO6JgD9AAATAAMJ9BO6JgD9AAAuAAQKfxsAAhMACAkcIHEOAMgCABMACAkcIHEOAMgCAAAA.Bonkula:BAABLgAECn8aAAIVAAcJkg2qOwAXAQAVAAcJkg2qOwAXAQAAAA==.Boondox:BAAALgAECgMJAwAAAA==.Bootyfeastr:BAAALgADCgEJAwAAAA==.Bops:BAAALgADCgQJBAAAAA==.Borque:BAAALgAECgUJBQABLgAECggJEgAEAAAAAA==.',
Br='Brae:BAAALgAECgYJCwAAAA==.Bralitha:BAAALgADCgEJAQAAAA==.Braumbastic:BAAALgADCgUJBQAAAA==.Brazonk:BAAALgADCgkJCQAAAA==.Brewzco:BAABLgAECn8zAAIMAAkJySSAAABiAwAMAAkJySSAAABiAwAAAA==.Bricifergoat:BAABLgAFFH8aAAIWAAYJ7yV/AQA1AgAWAAYJ7yV/AQA1AgABLgAFFAMJDQAUAIQmAA==.Briciferkong:BAACLgAFFH8NAAIUAAMJhCbbJQBUAQAUAAMJhCbbJQBUAQAuAAQKfxYAAxQABwklH21QAAACABQABwklH21QAAACABcAAQknCJ0YAC0AAAAA.Briciferyeah:BAAALgADCgQJBAABLgAFFAMJDQAUAIQmAA==.Brightblayde:BAABLgAECn8nAAIQAAcJxht7KQDZAQAQAAcJxht7KQDZAQAAAA==.Brique:BAAALgADCggJDAABLgAECggJEgAEAAAAAA==.',
Bu='Buanto:BAAALgAECgMJCQAAAA==.Bubblegumm:BAABLgAECn8gAAIIAAgJ0xSJIwCsAQAIAAgJ0xSJIwCsAQAAAA==.Bubieh:BAAALgAECgQJBQABLgAECgkJHwAKAGMjAA==.Bullshatner:BAAALgADCgQJBAAAAA==.Bumpinlumps:BAAALgAECgQJBAAAAA==.Bushwookiee:BAAALgAECgYJCAAAAA==.Butterknight:BAACLgAFFH8IAAIUAAMJNBTHOgCnAAAUAAMJNBTHOgCnAAAuAAQKfyIAAhQACAnXI0MWAPYCABQACAnXI0MWAPYCAAAA.Buttertotem:BAABLgAFFH8FAAMWAAMJBgObHgCwAAAWAAMJBgObHgCwAAAVAAIJrgTKNgBsAAAAAA==.',
Ca='Caanu:BAAALgADCgUJBwAAAA==.Calypso:BAAALgAECgMJAwAAAA==.Candlelock:BAAALgAECgYJBwAAAA==.Carirmonk:BAAALgAECgEJAQAAAA==.Cattroll:BAABLgAECn8eAAIIAAgJESIzCQC1AgAIAAgJESIzCQC1AgAAAA==.',
Cd='Cdubb:BAABLgAECn8UAAIQAAYJdhBmYwAnAQAQAAYJdhBmYwAnAQAAAA==.',
Ce='Celidori:BAAALgAECgkJDwABLgAECggJHgAIABEiAA==.Celithila:BAABLgAECn8mAAMYAAgJehVCEADoAQAYAAgJehVCEADoAQAPAAYJegp7JgD1AAAAAA==.Celithvia:BAABLgAECn8ZAAIQAAcJqRPsQACDAQAQAAcJqRPsQACDAQAAAA==.Ceroin:BAAALgADCgEJAQAAAA==.Cervantés:BAABLgAECn8rAAMZAAkJMSKXAQD/AgAZAAkJ9yCXAQD/AgAaAAcJMBtLBgAVAgAAAA==.',
Ch='Chaia:BAABLgAECn8hAAIIAAgJMhn+EgAzAgAIAAgJMhn+EgAzAgAAAA==.Chelsea:BAAALgAECgEJAQAAAA==.Cherra:BAAALgAECgcJBwABLgAECgcJFgAMABUgAA==.Chise:BAABLgAECn8aAAIPAAkJUxKrFwB6AQAPAAkJUxKrFwB6AQAAAA==.Chitanka:BAAALgADCgQJBAAAAA==.Chrispyloa:BAAALgAECgQJCwAAAA==.Chubs:BAABLgAECn8aAAMFAAcJhRhRDgDjAQAFAAcJqRdRDgDjAQAGAAUJPBNlvgDcAAAAAA==.',
Cl='Clann:BAABLgAECn8bAAICAAcJDxHHUgBzAQACAAcJDxHHUgBzAQAAAA==.Cly:BAABLgAECn8UAAIbAAYJISEaDgA2AgAbAAYJISEaDgA2AgAAAA==.Clydk:BAAALgAECgMJBAABLgAECgYJFAAbACEhAA==.',
Co='Coachbeard:BAABLgAECn8vAAIbAAkJEhJdGQDAAQAbAAkJEhJdGQDAAQAAAA==.Colzamenta:BAABLgAFFH8JAAIRAAQJYw+BMgDmAAARAAQJYw+BMgDmAAAAAA==.Colzaratha:BAAALgAFFAEJAQAAAA==.Contract:BAAALgAECgYJBgAAAA==.Corpsereth:BAAALgAECgkJAwAAAA==.',
Cr='Creamcicle:BAAALgADCgEJAQAAAA==.Crispytots:BAAALgAECgcJDAAAAA==.Crit:BAAALgAECgUJCQABLgAECggJHAALAEgWAA==.Critmypantz:BAABLgAECn8cAAILAAgJSBbaIADPAQALAAgJSBbaIADPAQAAAA==.Crosby:BAAALgADCgUJBQAAAA==.',
Cu='Cudguzzler:BAAALgADCggJCQAAAA==.Cursegoesmoo:BAACLgAFFH8JAAIUAAQJuBw+JQBVAQAUAAQJuBw+JQBVAQAuAAQKfxkAAhQACQkWIoIfAMQCABQACQkWIoIfAMQCAAAA.',
Cy='Cygna:BAABLgAECn8yAAITAAgJjiEODwBeAgATAAgJjiEODwBeAgAAAA==.Cyntheria:BAABLgAECn8iAAIQAAkJ+xw6JgCNAgAQAAkJ+xw6JgCNAgAAAA==.Cyphex:BAAALgADCgkJCAABLgAECggJMgATAI4hAA==.',
Da='Daddybeàr:BAAALgAECgQJBQAAAA==.Daendron:BAAALgADCgQJBAAAAA==.Dajubah:BAABLgAECn8nAAIBAAgJhR4qBQBVAgABAAgJhR4qBQBVAgAAAA==.Dammitdave:BAABLgAECn8dAAIQAAYJgAtycwAFAQAQAAYJgAtycwAFAQAAAA==.Dangereuse:BAAALgAECgUJBwAAAA==.Darinell:BAAALgAECgUJCwAAAA==.Darksaxon:BAABLgAECn8ZAAIBAAcJUBypCADvAQABAAcJUBypCADvAQAAAA==.Darthsidd:BAAALgAECgkJCAAAAA==.',
De='Deathnethal:BAAALgAECgYJDgAAAA==.Deathweaver:BAAALgAECgYJCAAAAA==.Deebbzmonk:BAABLgAFFH8GAAINAAIJTwd9IAB0AAANAAIJTwd9IAB0AAAAAA==.Deeno:BAAALgAECgEJBQAAAA==.Defrausted:BAAALgAECggJCAAAAA==.Deltaco:BAAALgAECgQJCAABLgAFFAQJCwATAP8WAA==.Deme:BAAALgADCgcJCgAAAA==.Demonica:BAABLgAECn8aAAQGAAcJEx6VGQAXAgAGAAYJEx6VGQAXAgAHAAMJeBIGDADIAAAFAAIJYBQTaABAAAAAAA==.Demonseedz:BAAALgAECgEJAgAAAA==.Dendrax:BAABLgAECn8hAAIGAAgJ9glEQQBlAQAGAAgJ9glEQQBlAQAAAA==.Dented:BAABLgAECn8fAAIQAAcJTAq8hQDhAAAQAAcJTAq8hQDhAAAAAA==.Derivation:BAAALgAECgQJCwAAAA==.Destitute:BAAALgAECgUJBQAAAA==.Detaren:BAAALgADCgEJAQAAAA==.Dethwing:BAAALgAECgIJBAAAAA==.Devadeity:BAABLgAECn8kAAIYAAgJBRIgHABpAQAYAAgJBRIgHABpAQAAAA==.Deviance:BAAALgAECgYJEAAAAA==.Devola:BAAALgADCgkJFAAAAA==.',
Di='Didntask:BAAALgADCgEJAQABLgAECggJGwAKAIQOAA==.Dienmage:BAABLgAECn8fAAIcAAgJch4nAQBIAgAcAAgJch4nAQBIAgAAAA==.Digìt:BAAALgAECgIJAgABLgAECgcJGgAYAC4dAA==.Dirtychai:BAABLgAECn8fAAIYAAcJih8ZCABvAgAYAAcJih8ZCABvAgAAAA==.Dissonance:BAAALgAECgcJCAAAAA==.Diurd:BAAALgAECgEJAQAAAA==.Divine:BAAALgADCgYJBgAAAA==.',
Dj='Djanga:BAABLgAECn8nAAMJAAgJaSTnAgDnAgAJAAgJaSTnAgDnAgAIAAQJvRoaZAAlAQAAAA==.Djdazzle:BAAALgAECgcJAQAAAA==.',
Dk='Dkchocobussy:BAAALgADCgMJAwAAAA==.Dkdiso:BAAALgAECgYJBgAAAA==.',
Do='Doctorevil:BAAALgAECgYJEAAAAA==.Dogglefrog:BAAALgADCgEJAQAAAA==.Dominance:BAAALgADCgcJCQAAAA==.Doranthsæ:BAAALgADCgcJBwABLgAECgkJIgAJAJEaAA==.Dorito:BAAALgAFFAMJBAAAAA==.Dothausen:BAAALgAECgcJDQAAAA==.',
Dr='Dracaaron:BAAALgAECgUJBwAAAA==.Dragonevil:BAAALgADCgYJBgAAAA==.Dragooned:BAACLgAFFH8LAAICAAQJAhhqJwBaAQACAAQJAhhqJwBaAQAuAAQKfxQAAgIABwklJA0uALkCAAIABwklJA0uALkCAAAA.Dragussy:BAAALgAECgQJBAAAAA==.Drakenallure:BAAALgAECgkJEAAAAA==.Drakkisath:BAABLgAECn8gAAMdAAcJDBXuGgBnAQAdAAcJ9xTuGgBnAQAeAAUJPxPdDADDAAAAAA==.Draknethal:BAAALgAECgIJAgAAAA==.Dramn:BAAALgADCgMJAwAAAA==.Drango:BAABLgAECn8YAAIeAAgJVgRnCgD2AAAeAAgJVgRnCgD2AAAAAA==.Draugdae:BAABLgAECn8mAAIfAAgJnB8BAwByAgAfAAgJnB8BAwByAgAAAA==.Drayslinger:BAAALgAECgMJBAAAAA==.Dreki:BAAALgADCgYJCQABLgAECgIJAgAEAAAAAA==.Drinksomuch:BAAALgAECgEJAgAAAA==.Drlechee:BAAALgADCgMJBQAAAA==.Drob:BAEALgADCgkJGwAAAA==.Drukhi:BAABLgAECn8eAAITAAgJ7BtmIADaAQATAAgJ7BtmIADaAQAAAA==.Drunkalicius:BAAALgAFFAIJAwAAAA==.',
Du='Dudepriest:BAAALgAECggJEwAAAA==.Dungrough:BAAALgAECggJCwAAAA==.Durtkal:BAABLgAECn8wAAMGAAkJjxN9GAAfAgAGAAkJjxN9GAAfAgAFAAYJZw7kHwBTAQAAAA==.',
Dw='Dwarlin:BAAALgADCgkJCQAAAA==.',
Dy='Dyonn:BAAALgADCggJCQAAAA==.',
['Dê']='Dêädpool:BAAALgADCgYJBgAAAA==.',
Ed='Edgeboy:BAAALgAECgYJCgABLgAFFAUJDgACAE4UAA==.',
Ef='Efarel:BAABLgAECn8uAAIgAAgJMhWbFQC8AQAgAAgJMhWbFQC8AQAAAA==.Efil:BAAALgAECgIJAgAAAA==.',
El='Eleantha:BAAALgADCgYJBwAAAA==.Elinisar:BAAALgAECgUJBgAAAA==.Elsa:BAABLgAECn8hAAICAAgJCg2KTQCBAQACAAgJCg2KTQCBAQAAAA==.Elzza:BAAALgADCgYJCQAAAA==.',
Em='Embear:BAAALgADCgcJEAAAAA==.',
En='Enjaydin:BAAALgAECgUJBQAAAA==.Enjaydo:BAABLgAECn8qAAICAAgJOB8sGQBUAgACAAgJOB8sGQBUAgAAAA==.',
Ep='Epicfurry:BAAALgAECgUJCwAAAA==.',
Er='Ereile:BAAALgAECgUJCAAAAA==.Errlhickey:BAAALgADCgUJCQAAAA==.',
Es='Escanor:BAAALgADCgYJBgAAAA==.',
Eu='Eukelade:BAAALgADCgcJBwABLgAECgkJMwANALEeAA==.Eurythmics:BAABLgAECn8gAAITAAcJWBVlMwCAAQATAAcJWBVlMwCAAQAAAA==.',
Ev='Evileen:BAAALgAECgEJAQAAAA==.Evonahh:BAAALgADCgcJEwAAAA==.',
Ex='Exelion:BAABLgAECn8gAAIYAAgJxh/CCgA7AgAYAAgJxh/CCgA7AgAAAA==.Explogan:BAAALgAECgYJBwAAAA==.',
Ez='Ezanah:BAAALgADCgUJBQAAAA==.Ezrack:BAAALgAECgMJAwAAAA==.',
Fa='Faeyrin:BAABLgAECn8eAAIXAAgJgRAVBgBgAQAXAAgJgRAVBgBgAQAAAA==.Fahooquazaad:BAAALgAECgIJAwAAAA==.Falconsg:BAAALgADCgQJBAAAAA==.Fancy:BAAALgAECggJEwAAAA==.Faythlis:BAABLgAECn8bAAIGAAcJBAtNUgA0AQAGAAcJBAtNUgA0AQAAAA==.',
Fe='Feetlesmcdee:BAABLgAECn8WAAIQAAgJzwWZbgAQAQAQAAgJzwWZbgAQAQAAAA==.Felf:BAAALgADCgcJBwAAAA==.Felfáádaern:BAEBLgAECn8hAAQhAAgJowxIEwBWAQAhAAgJowxIEwBWAQARAAIJKgEL3wAzAAAiAAEJsAXdLQAoAAAAAA==.Felporch:BAAALgAECgYJEQAAAA==.',
Fi='Filburt:BAAALgADCgEJAQAAAA==.',
Fk='Fkton:BAAALgADCgIJAgAAAA==.',
Fl='Flamediso:BAAALgAECgEJAQAAAA==.Fledermaus:BAAALgADCgEJAQAAAA==.Flourchild:BAAALgADCgEJAQAAAA==.Flowermound:BAAALgAECgQJBgAAAA==.Flowerrose:BAAALgADCgYJBgAAAA==.',
Fo='Forrester:BAABLgAECn8WAAIJAAYJvRkgGAB6AQAJAAYJvRkgGAB6AQAAAA==.Fourqto:BAAALgAECgYJBgAAAA==.Fox:BAACLgAFFH8SAAMYAAYJSSNoAABRAgAYAAYJSSNoAABRAgAPAAIJ9QZWIgCAAAAuAAQKfxoAAhgACAkXHgsLAJ4CABgACAkXHgsLAJ4CAAAA.',
Fr='Franklee:BAAALgAECgEJAQAAAA==.Freight:BAAALgADCgMJAwAAAA==.Friedcry:BAAALgADCgYJBgAAAA==.Fron:BAAALgAECgUJCwAAAA==.Fronie:BAAALgADCgcJAwAAAA==.',
Fu='Fujikujaku:BAABLgAECn8UAAIIAAcJFxBINQBEAQAIAAcJFxBINQBEAQAAAA==.Fulmetal:BAAALgAECgQJBAAAAA==.Funerris:BAAALgADCgEJAQABLgAFFAYJCQAdACsHAA==.Funiris:BAACLgAFFH8JAAIjAAUJSAheBQB3AQAjAAUJSAheBQB3AQAuAAQKfxUAAyMABwnsFeUoAJMBACMABwnsFeUoAJMBAA8ABQmKDiIyABABAAEuAAUUBgkJAB0AKwcA.Funkalicious:BAACLgAFFH8KAAIWAAMJpxBWGQDjAAAWAAMJpxBWGQDjAAAuAAQKfy8AAhYACQm9HlcDANgCABYACQm9HlcDANgCAAAA.',
['Fé']='Félo:BAABLgAECn8pAAMFAAgJNyNlAQB3AgAFAAcJWyRlAQB3AgAGAAUJ6x4RKADGAQAAAA==.',
Ga='Gabaghoul:BAAALgAECgYJBgAAAA==.Garathor:BAAALgAECgEJAgAAAA==.Garthoneeye:BAAALgAECgQJCwAAAA==.Gazreyna:BAABLgAECn8ZAAIUAAcJSCBwHgASAgAUAAcJSCBwHgASAgAAAA==.',
Gc='Gcarne:BAABLgAECn8iAAIIAAgJKwryNwA2AQAIAAgJKwryNwA2AQAAAA==.',
Ge='Genz:BAAALgADCgEJAQAAAA==.Genós:BAABLgAECn8hAAMBAAgJ1BqjCADwAQABAAgJ+BejCADwAQAgAAcJ8Bo8NQDUAQAAAA==.Gerardo:BAAALgAECgYJCAAAAA==.',
Gh='Ghurri:BAAALgAECgEJAQAAAA==.',
Gi='Gibs:BAAALgAECgYJCgAAAA==.Ginnee:BAAALgAECgEJAwAAAA==.Ginnion:BAABLgAECn8UAAIOAAcJTRclDACHAQAOAAcJTRclDACHAQAAAA==.Girthytail:BAAALgAECgYJEQAAAA==.',
Gl='Glaedor:BAAALgAECgQJBAAAAA==.Glakenspheal:BAABLgAECn8eAAQPAAgJzg17GgBdAQAPAAcJPQ57GgBdAQAYAAEJxQrrSwA1AAAjAAEJsQKDXAAbAAAAAA==.Glamorous:BAAALgAECgYJCQAAAA==.Glein:BAAALgAECgQJBAABLgAECggJIwALAOwgAA==.',
Go='Gongfu:BAAALgADCgYJBgAAAA==.Goonie:BAAALgAECgYJCAAAAA==.',
Gr='Graestoke:BAACLgAFFH8GAAICAAMJABmLQwADAQACAAMJABmLQwADAQAuAAQKfxgAAgIACAnWH2U0AKECAAIACAnWH2U0AKECAAAA.Graevana:BAAALgADCgEJAQAAAA==.Gregorizz:BAAALgAECgEJBAAAAA==.Greyaura:BAAALgAECgQJBAAAAA==.Greybeast:BAAALgAECgYJDAAAAA==.Greyfoxy:BAAALgAECgYJDAAAAA==.Grianick:BAAALgAECgUJBQABLgAECgcJFQAkAJEYAA==.Grimixtalis:BAAALgAECgYJBgAAAA==.Growls:BAABLgAECn8kAAQIAAgJ8xT1GgDsAQAIAAgJ8xT1GgDsAQAJAAcJphoIDwDfAQAfAAcJHhG+DABDAQAAAA==.',
Gu='Gurri:BAAALgAECgQJBgAAAA==.',
Gy='Gyaat:BAAALgADCggJDwAAAA==.',
['Gõ']='Gõldenchild:BAAALgAECgUJEAAAAA==.',
Ha='Habenero:BAABLgAECn8XAAIlAAcJ2wi8DQAqAQAlAAcJ2wi8DQAqAQAAAA==.Hagar:BAABLgAECn8XAAISAAcJDBMvCwBnAQASAAcJDBMvCwBnAQAAAA==.Hairycow:BAAALgAECgMJAwAAAA==.Hairypitts:BAABLgAECn8eAAISAAkJ8BY5AwBcAgASAAkJ8BY5AwBcAgAAAA==.Haittou:BAAALgAECgkJBQAAAA==.Halligan:BAAALgAECgYJBgAAAA==.Hammertime:BAAALgAECggJDwAAAA==.Harabrew:BAAALgADCggJDAAAAA==.Haraniantha:BAABLgAECn8WAAIMAAcJFSBGDAD+AQAMAAcJFSBGDAD+AQAAAA==.Hardø:BAAALgADCgcJCAAAAA==.Hatean:BAAALgADCggJCQABLgAECgYJBwAEAAAAAA==.Hazzbek:BAAALgADCgUJBQAAAA==.',
He='Heiboss:BAAALgAECgQJBQABLgAECgkJHwAKAGMjAA==.Heipal:BAAALgADCgYJBgABLgAECgkJHwAKAGMjAA==.Heiranir:BAAALgADCgYJEgABLgAECgkJHwAKAGMjAA==.Heiretic:BAAALgAECgQJBAABLgAECgkJHwAKAGMjAA==.Hellbane:BAAALgAECgQJCgAAAA==.Hemit:BAAALgAECgMJAwABLgAFFAMJBgACAAAZAA==.Hempknight:BAAALgADCgQJBQAAAA==.',
Hi='Hickups:BAAALgAECgYJCQABLgAECgkJLwAbABISAA==.Highestorder:BAAALgADCgYJBgAAAA==.Hikikomori:BAAALgAECggJCAABLgAECgkJMQAKAOAiAA==.Hinomiko:BAAALgAECgUJCwABLgAECgYJFQADAPEIAA==.',
Ho='Holycowch:BAABLgAECn8XAAMQAAcJLhxmJwDjAQAQAAcJnxpmJwDjAQAkAAUJyRTwHQAaAQAAAA==.Honeyb:BAAALgAECgQJCwAAAA==.Hoodieallen:BAAALgADCgQJBAAAAA==.Hoofthor:BAAALgADCgEJAQAAAA==.Hootiedixon:BAAALgAECgYJEgAAAA==.',
Hu='Hughjaculate:BAAALgAECgUJCQAAAA==.Huran:BAABLgAECn8fAAMKAAkJYyODBgDOAgAKAAkJYyODBgDOAgAUAAEJuwjJHwE2AAAAAA==.',
Id='Idcritthat:BAABLgAECn8dAAMaAAcJCRjhBAC5AQAaAAcJCRjhBAC5AQAZAAMJFA8sVgB2AAABLgAECggJHAALAEgWAA==.',
Ig='Ignignokt:BAEBLgAECn8lAAMTAAkJPyOzDADaAgATAAkJPyOzDADaAgAmAAEJzhr0hwA0AAAAAA==.Igvoker:BAEALgAECgYJBgABLgAECgkJJQATAD8jAA==.',
Il='Illadont:BAAALgADCgEJAQAAAA==.Illith:BAAALgADCgEJAQAAAA==.',
Im='Imagine:BAAALgAECgUJAwAAAA==.Imirohe:BAABLgAECn8VAAMCAAcJrggsuwBrAQACAAcJrggsuwBrAQAcAAEJoQOTIgAcAAAAAA==.',
In='Inarush:BAABLgAECn8oAAIiAAkJDggDCQBMAQAiAAkJDggDCQBMAQAAAA==.Inuyahshi:BAAALgAECggJCAAAAA==.',
Ir='Ira:BAAALgADCgIJAgAAAA==.Ironfistt:BAAALgADCgYJBgAAAA==.Ironknife:BAAALgADCggJGAAAAA==.Ironshield:BAACLgAFFH8LAAITAAQJ/xYwEABZAQATAAQJ/xYwEABZAQAuAAQKfxwAAhMACQlnIJYFADMDABMACQlnIJYFADMDAAAA.',
Iv='Ivie:BAAALgAECgQJBgAAAA==.',
Iw='Iwishiknew:BAABLgAECn8gAAIgAAgJIBJKFADKAQAgAAgJIBJKFADKAQAAAA==.',
Iz='Iztras:BAAALgAECgMJBwAAAA==.Izuras:BAAALgAECgkJBwAAAA==.Izzit:BAAALgAECgQJCwAAAA==.',
Ja='Ja:BAABLgAECn8cAAICAAkJERg0HgA1AgACAAkJERg0HgA1AgAAAA==.Jabbtrak:BAABLgAECn8VAAINAAYJAxgBGACRAQANAAYJAxgBGACRAQAAAA==.Jabtrakk:BAAALgADCggJCAAAAA==.Jacklowry:BAAALgAECggJCAAAAA==.Jacodin:BAABLgAECn8WAAIbAAgJFhntCQByAgAbAAgJFhntCQByAgAAAA==.Jacquestrapp:BAAALgADCgkJDAAAAA==.Jakiepoobear:BAAALgAECgcJEAAAAA==.Jambie:BAABLgAECn8ZAAQGAAgJnxX3OwB4AQAGAAYJGBf3OwB4AQAFAAIJUQzKUQB5AAAHAAEJywy1LwA/AAAAAA==.',
Je='Jedery:BAABLgAECn8fAAIkAAcJXBNODgBSAQAkAAcJXBNODgBSAQAAAA==.',
Jg='Jgglephysyx:BAAALgAECgkJCQAAAA==.',
Ji='Jianyü:BAABLgAECn8fAAIQAAgJ2RwDJQCTAgAQAAgJ2RwDJQCTAgAAAA==.Jimbæn:BAAALgADCgYJCAAAAA==.',
Jo='Jollyandy:BAEALgAECgcJDgAAAA==.Jolynn:BAABLgAECn8nAAInAAgJVQ+iDQDLAQAnAAgJVQ+iDQDLAQAAAA==.Joroldess:BAABLgAECn8eAAIkAAgJLRkTCQC3AQAkAAgJLRkTCQC3AQAAAA==.',
Ju='Juzam:BAAALgAECgMJAwAAAA==.',
['Jü']='Jüggernaut:BAAALgAECgMJAwABLgAECggJMgATAI4hAA==.',
Ka='Kahndumb:BAABLgAECn8VAAIgAAcJoQhVYAAvAQAgAAcJoQhVYAAvAQAAAA==.Kaida:BAAALgAECgUJCAAAAA==.Kaio:BAAALgADCgMJAwAAAA==.Kalahan:BAABLgAECn8WAAIlAAYJWxESDQA2AQAlAAYJWxESDQA2AQAAAA==.Kalimaa:BAAALgAECgYJDwAAAA==.Kaotut:BAAALgADCgQJBAAAAA==.Kappakappa:BAAALgAECgMJAwAAAA==.Kardrion:BAAALgAECgQJBQAAAA==.Karigyn:BAABLgAECn8nAAIaAAcJLCMqAgBOAgAaAAcJLCMqAgBOAgAAAA==.Karun:BAABLgAECn8nAAIXAAgJ9BS/AwDIAQAXAAgJ9BS/AwDIAQAAAA==.Kasok:BAAALgAECgYJDgAAAA==.Kasumi:BAAALgAECggJCAABLgAECgkJMwAMAMkkAA==.Katren:BAAALgADCgUJBQAAAA==.Katrienne:BAABLgAECn8WAAIkAAYJdgUZKQDBAAAkAAYJdgUZKQDBAAAAAA==.Katrya:BAAALgADCgkJFQABLgAECgYJFgAkAHYFAA==.Katsfood:BAAALgADCgkJFQAAAA==.Kauzarukus:BAAALgAECgcJBwAAAA==.Kaylid:BAABLgAECn8jAAIoAAgJYhvCAQBEAgAoAAgJYhvCAQBEAgAAAA==.Kaylou:BAAALgADCgcJBwABLgAECggJKgAQAIgKAA==.Kazeralana:BAAALgAECgUJBQAAAA==.Kazzoth:BAABLgAECn8hAAITAAgJ8hCGLQCYAQATAAgJ8hCGLQCYAQAAAA==.',
Ke='Keeiras:BAAALgAECgkJDwAAAA==.Keilen:BAAALgADCgUJBAAAAA==.Kelasha:BAABLgAECn8fAAIUAAgJVB7pHgAPAgAUAAgJVB7pHgAPAgAAAA==.',
Kh='Khadgär:BAAALgAECgYJDwAAAA==.Khalika:BAAALgAECgUJBgAAAA==.Kharanys:BAAALgADCgcJBwAAAA==.',
Ki='Kilroar:BAAALgADCgkJCQAAAA==.Kinoplex:BAAALgAECgIJBAABLgAECgYJCAAEAAAAAA==.',
Kl='Klassiq:BAAALgADCgUJBQAAAA==.Klax:BAAALgADCgkJDwAAAA==.Klokateer:BAABLgAECn8cAAMaAAgJIBimBQAuAgAaAAgJ4BemBQAuAgAZAAUJ4w/WOgBCAQAAAA==.Klzx:BAABLgAECn8mAAICAAgJyhRjNwDFAQACAAgJyhRjNwDFAQAAAA==.',
Ko='Kobold:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Komo:BAAALgADCgcJBwAAAA==.Komoou:BAAALgAECgQJBAAAAA==.Komouo:BAAALgADCgMJAwABLgADCgcJBwAEAAAAAA==.Korbi:BAAALgADCgcJGAABLgAECggJJgAWAEIVAA==.Kortek:BAABLgAECn8ZAAIdAAgJuAL0MQDcAAAdAAgJuAL0MQDcAAAAAA==.Korvold:BAAALgAECggJDgAAAA==.Kosmos:BAAALgAECggJEAAAAA==.Kozath:BAAALgAECgYJCgAAAA==.',
Kr='Kreckon:BAAALgAECgUJCAAAAA==.Kriandor:BAAALgAECgEJAgAAAA==.',
Ks='Kschnell:BAAALgAECgEJAQABLgAFFAUJDgACAE4UAA==.',
Ku='Kukulkan:BAABLgAECn8aAAIOAAcJug8LHwCIAQAOAAcJug8LHwCIAQAAAA==.Kuulan:BAABLgAECn8hAAIQAAgJxRRuMwCvAQAQAAgJxRRuMwCvAQAAAA==.',
La='Lacertidae:BAAALgADCgEJAQAAAA==.Larwock:BAAALgAECgUJEgAAAA==.Lathorâ:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.Latwiz:BAAALgADCgYJCQABLgAECggJGgAQABYeAA==.',
Le='Leancuisine:BAAALgAECgYJBwAAAA==.Leetlebug:BAAALgAECgYJEQAAAA==.Lettÿ:BAAALgAECgYJCgAAAA==.',
Li='Lightheaded:BAAALgAECgcJCQAAAA==.Lightzwrath:BAAALgAECggJEgAAAA==.Linadra:BAAALgAECgQJBAAAAA==.Liquid:BAABLgAECn8XAAIZAAYJZiSnCAAaAgAZAAYJZiSnCAAaAgAAAA==.',
Lo='Loankano:BAABLgAECn8UAAIZAAgJCQRgFwBLAQAZAAgJCQRgFwBLAQAAAA==.Lockbealady:BAAALgAECgYJDQAAAA==.Lohanoa:BAAALgAECgEJAQAAAA==.Longshanke:BAAALgAECgEJAQAAAA==.Lorebeard:BAAALgAECgYJCQAAAA==.Loreix:BAAALgAECgYJDQAAAA==.Lozzo:BAAALgADCgYJCwAAAA==.',
Lr='Lrock:BAAALgADCgMJAgAAAA==.',
Lu='Luciferluxx:BAAALgADCgQJBgAAAA==.Lumena:BAAALgADCggJCAABLgADCggJCAAEAAAAAA==.Luminai:BAABLgAECn8YAAIYAAgJmBq+EQBUAgAYAAgJmBq+EQBUAgAAAA==.Luminaris:BAAALgAECgEJAQAAAA==.Luminaugty:BAAALgADCgcJEwAAAA==.Lunalea:BAAALgADCgQJBAAAAA==.Lunarthas:BAAALgADCgkJEQAAAA==.Luvinez:BAAALgAECgEJAgAAAA==.Luvinz:BAAALgAECgYJBgAAAA==.Luxkilla:BAAALgADCgEJAQAAAA==.',
Ly='Lyllia:BAAALgADCgEJAQAAAA==.Lynchmeup:BAAALgADCgYJBgABLgAECgcJHAARAMYcAA==.Lyrel:BAABLgAECn8hAAIRAAgJICLiCQCKAgARAAgJICLiCQCKAgAAAA==.Lyshara:BAAALgADCgEJAQAAAA==.',
['Lî']='Lîllîth:BAAALgADCgMJAwAAAA==.',
['Lü']='Lümen:BAAALgADCggJCAAAAA==.',
Ma='Maarc:BAABLgAECn8aAAITAAcJyAyrOwBeAQATAAcJyAyrOwBeAQAAAA==.Maddragon:BAAALgAECgMJAwAAAA==.Madfurion:BAAALgAECgMJBAAAAA==.Magebot:BAABLgAECn8bAAICAAgJXAknUwByAQACAAgJXAknUwByAQAAAA==.Maggotbag:BAAALgAECgQJBAAAAA==.Magistra:BAAALgADCgcJDwAAAA==.Majestic:BAACLgAFFH8OAAICAAUJThTwLABPAQACAAUJThTwLABPAQAuAAQKfyUAAgIACQmxHlknANUCAAIACQmxHlknANUCAAAA.Malizar:BAAALgADCgEJAQAAAA==.Malvenue:BAAALgAECgkJAgAAAA==.Malygor:BAAALgAECgUJBwAAAA==.Marly:BAAALgAECgYJDQAAAA==.Mauwy:BAABLgAECn8eAAMWAAkJbxM5HwAWAgAWAAkJbxM5HwAWAgAVAAMJGQ1NbABYAAAAAA==.Mayabutreeks:BAAALgAECgYJBwAAAA==.Mazzerine:BAAALgAECgQJBAAAAA==.',
Mc='Mcbeardface:BAABLgAECn8WAAMPAAcJ/hXiGwC3AQAPAAcJ/hXiGwC3AQAjAAEJAADgXABAAAAAAA==.Mcbullseye:BAAALgAECgUJBAAAAA==.',
Me='Meathole:BAAALgAECgMJAwAAAA==.Megarah:BAAALgAECgQJBgAAAA==.Mental:BAAALgAECgEJAQAAAA==.Mepkaelpto:BAAALgAFFAQJBAABLgAFFAUJCQARAIsJAA==.Mera:BAAALgADCgcJCAAAAA==.Mercury:BAABLgAECn8XAAIVAAcJJRgJGQDpAQAVAAcJJRgJGQDpAQAAAA==.Meretrix:BAAALgAECgYJDQAAAA==.Messatsu:BAAALgAECgcJCwAAAA==.Metanya:BAAALgAECgcJEAAAAA==.Mew:BAAALgAECgYJBAAAAA==.',
Mi='Miateh:BAAALgAECgQJBQAAAA==.Microdots:BAAALgADCgMJAwAAAA==.Midorí:BAAALgADCgYJBgAAAA==.Mimicme:BAAALgAECggJEAAAAA==.Minorie:BAAALgADCgIJAgAAAA==.Mitchell:BAABLgAECn8gAAIQAAgJxA5QPwCIAQAQAAgJxA5QPwCIAQAAAA==.Miwah:BAAALgAECgYJEwAAAA==.',
Mj='Mjolnìr:BAAALgAECgMJDAAAAA==.',
Mo='Modeus:BAAALgADCgUJBgAAAA==.Modin:BAABLgAECn8VAAIkAAcJkRjXCwB/AQAkAAcJkRjXCwB/AQAAAA==.Mogarr:BAABLgAECn8XAAIBAAgJbQ0dHABpAQABAAgJbQ0dHABpAQAAAA==.Mohgwyn:BAAALgADCgEJAQAAAA==.Monkglein:BAABLgAECn8jAAMLAAgJ7CCKBACfAgALAAgJ7CCKBACfAgANAAEJmAFwZwASAAAAAA==.Monkhei:BAAALgAECgQJBAABLgAECgkJHwAKAGMjAA==.Mooglewing:BAAALgAECgYJDwAAAA==.Moomoobrncow:BAAALgAECgcJEwAAAA==.Moondream:BAABLgAECn8mAAMTAAgJURk6GQAIAgATAAgJURk6GQAIAgAmAAIJLgi1ewBVAAAAAA==.Moraz:BAAALgAECgQJBAAAAA==.Mordicanta:BAABLgAECn8nAAIKAAgJzhUzDgCPAQAKAAgJzhUzDgCPAQAAAA==.Morphies:BAAALgADCgcJDQAAAA==.',
Mu='Muerr:BAABLgAECn8cAAITAAkJgCHZCgCNAgATAAkJgCHZCgCNAgAAAA==.Muerrizond:BAAALgAECgUJDAABLgAECgkJHAATAIAhAA==.Muerrlin:BAAALgAECgYJDAABLgAECgkJHAATAIAhAA==.Muggel:BAAALgADCgkJJgAAAA==.Muggruith:BAAALgADCgkJDwAAAA==.Mumraa:BAAALgAECgMJAwAAAA==.Mumrawr:BAAALgADCgcJCwAAAA==.Mushroohead:BAABLgAECn8eAAIWAAgJzBrKCgAtAgAWAAgJzBrKCgAtAgAAAA==.',
My='Mystbourn:BAAALgAECgEJAQAAAA==.Mysterbyrnes:BAAALgADCgYJEgAAAA==.Myykiel:BAABLgAECn8fAAQRAAcJWxfXQgAwAQARAAUJrBnXQgAwAQAiAAYJ2QthEwAcAQAhAAQJaRmIHgDkAAAAAA==.',
Na='Naina:BAABLgAECn8mAAMVAAgJYhijEQAtAgAVAAgJYhijEQAtAgAWAAEJcwniawAqAAAAAA==.Najaja:BAAALgAECgMJAwAAAA==.Nariely:BAAALgAECgYJBwAAAA==.Natacha:BAAALgAECgQJBQAAAA==.Native:BAAALgAECgUJCAAAAA==.Nayos:BAAALgADCgIJAgAAAA==.',
Ne='Necro:BAABLgAECn8xAAIKAAkJ4CJwAQAGAwAKAAkJ4CJwAQAGAwAAAA==.Neelothe:BAAALgAECgMJAwAAAA==.Neisa:BAAALgADCgIJAgAAAA==.Nekroz:BAAALgAECgEJAQAAAA==.Nelliel:BAAALgAECgcJEwAAAA==.',
Ni='Nickodemus:BAAALgAECgIJAgAAAA==.Nightle:BAAALgADCggJCwAAAA==.Nihil:BAABLgAECn8UAAIiAAcJ6xK5CgAjAQAiAAcJ6xK5CgAjAQABLgAECgkJMQAKAOAiAA==.Nikano:BAAALgADCgYJBgAAAA==.Ninmah:BAAALgADCgkJMwAAAA==.Niphredil:BAAALgAECgEJAQAAAA==.Nirø:BAABLgAECn8dAAILAAkJLQoZFgB4AQALAAkJLQoZFgB4AQAAAA==.',
No='Noah:BAAALgADCgcJDQAAAA==.Nooky:BAABLgAECn8hAAINAAgJAx4XCQBgAgANAAgJAx4XCQBgAgAAAA==.',
Nu='Nuatha:BAAALgAECgYJCwAAAA==.Numpty:BAAALgAECgMJBgAAAA==.',
Ny='Nyctero:BAABLgAECn8eAAIlAAgJlR+fAgB6AgAlAAgJlR+fAgB6AgAAAA==.Nyrikah:BAAALgADCgcJBwAAAA==.',
['Nö']='Nöstrum:BAAALgADCgMJAwABLgAECgYJBgAEAAAAAA==.',
Ob='Obidiah:BAABLgAECn8mAAMCAAgJSBh4LgDnAQACAAgJqxd4LgDnAQAcAAEJThKXGgBDAAAAAA==.',
Oe='Oedipus:BAAALgAECgMJAwAAAA==.',
Oh='Ohioaug:BAAALgADCgEJAQAAAA==.',
Or='Orah:BAABLgAECn8aAAIJAAcJ2AznIwAbAQAJAAcJ2AznIwAbAQAAAA==.Orpheon:BAAALgAECgQJCQAAAA==.',
Os='Osorn:BAAALgADCgkJCgAAAA==.',
Ot='Otterdoodad:BAAALgAECgQJBAAAAA==.',
Oz='Ozzmosis:BAAALgADCgMJAwAAAA==.',
Pa='Palagem:BAAALgADCgYJBgAAAA==.Palinyes:BAABLgAECn8UAAIkAAcJKSOkBAA2AgAkAAcJKSOkBAA2AgAAAA==.Pancetta:BAAALgADCgUJCAAAAA==.Pandabits:BAAALgAECgUJBQAAAA==.Papabill:BAABLgAECn8iAAIQAAgJDg5MQgB+AQAQAAgJDg5MQgB+AQAAAA==.Paperscissor:BAAALgADCgIJAgAAAA==.Paragorn:BAABLgAECn8gAAIQAAgJagneUABUAQAQAAgJagneUABUAQAAAA==.Pasiphae:BAAALgADCgIJAgABLgAECgkJMwANALEeAA==.Pattee:BAABLgAECn8cAAImAAcJLCFtBAD1AQAmAAcJLCFtBAD1AQAAAA==.',
Pe='Peachums:BAAALgADCgEJAQAAAA==.Pech:BAAALgAFFAEJAQAAAA==.Peenidin:BAABLgAECn8hAAIbAAgJciPDCQB1AgAbAAgJciPDCQB1AgAAAA==.Pemerd:BAABLgAECn8aAAIJAAcJsBpnEADNAQAJAAcJsBpnEADNAQAAAA==.Petite:BAAALgADCgMJAwAAAA==.',
Ph='Phoenixfires:BAAALgADCgYJCAAAAA==.Phoze:BAABLgAECn8gAAIkAAgJOBarCADAAQAkAAgJOBarCADAAQAAAA==.Phyai:BAABLgAECn8VAAICAAYJxBOcZgBEAQACAAYJxBOcZgBEAQAAAA==.',
Pi='Pirotanaxdos:BAAALgAECgYJDwAAAA==.Pizzarollzz:BAABLgAECn8UAAITAAcJ9A0+RABAAQATAAcJ9A0+RABAAQAAAA==.',
Pn='Pnutt:BAAALgAECgMJAwAAAA==.',
Po='Ponymalta:BAABLgAECn8lAAIJAAgJ5xdMGwApAgAJAAgJ5xdMGwApAgAAAA==.Popeaganda:BAAALgAECgQJBwAAAA==.Poutine:BAAALgAECgQJCwAAAA==.',
Pr='Prizren:BAAALgAECgYJBwAAAA==.Promethyus:BAABLgAECn8eAAMQAAgJNQYYkADNAAAQAAgJNQYYkADNAAAkAAUJwAFyKABcAAAAAA==.Promidan:BAAALgAECgEJAQABLgAFFAQJDgAQAFELAA==.Pryxi:BAABLgAECn8nAAICAAgJ/QcTXABcAQACAAgJ/QcTXABcAQAAAA==.',
Pu='Puffichu:BAAALgADCgMJAwABLgAECgMJAwAEAAAAAA==.Punchline:BAAALgADCgcJBwAAAA==.',
Py='Pyrogar:BAAALgADCgIJAgAAAA==.Pythius:BAAALgAECgYJBwAAAA==.',
['Pó']='Pótatò:BAAALgAECgYJCwAAAA==.',
Qu='Quandaale:BAABLgAECn8WAAMIAAcJuhOaOQAvAQAIAAYJMxSaOQAvAQAfAAUJNxeWDwAOAQABLgAFFAEJAQAEAAAAAA==.Quell:BAAALgADCgEJAQAAAA==.Quepinga:BAAALgADCgUJCAAAAA==.Quiksylver:BAABLgAECn8iAAMbAAgJRx39FwDMAQAbAAcJTRz9FwDMAQAQAAYJyhGVSABsAQAAAA==.',
Ra='Rabblerousin:BAAALgAECgEJAgAAAA==.Raegnar:BAAALgADCgYJBgAAAA==.Raggnnar:BAAALgADCgEJAgAAAA==.Rainmakers:BAAALgAECgcJBQAAAA==.Rakael:BAAALgADCgMJAwAAAA==.Rava:BAAALgAECgEJAQAAAA==.',
Re='Reckoner:BAAALgAECgUJDgAAAA==.Red:BAABLgAECn8vAAQUAAgJHCT3FwA8AgAUAAgJ6yD3FwA8AgAXAAcJZCOdAgAOAgAKAAcJphGyEQBXAQAAAA==.Rellster:BAAALgAECgUJCgAAAA==.Renix:BAAALgAECgQJBQAAAA==.Rennyo:BAABLgAECn8dAAMLAAgJtha5FQB9AQAMAAgJ9RJDKgC4AQALAAYJ7Bi5FQB9AQAAAA==.Resonance:BAAALgAECgUJBwAAAA==.Retsu:BAAALgADCgUJBQAAAA==.Rettbull:BAAALgADCgMJAwAAAA==.Reyujin:BAAALgAECgEJBAAAAA==.',
Rh='Rhyash:BAAALgAECgYJDwAAAA==.',
Ri='Rickdaddty:BAAALgADCgkJCQABLgAECgcJGgAGABMeAA==.Ricoz:BAAALgAECgQJBQAAAA==.Ridicutie:BAAALgAECgYJEwAAAA==.Rigg:BAABLgAECn8cAAIRAAcJxhyYGgDpAQARAAcJxhyYGgDpAQAAAA==.Riggz:BAAALgADCgQJBAABLgAECgcJHAARAMYcAA==.Rivetro:BAAALgAECgQJCwAAAA==.',
Ro='Rocknroll:BAABLgAECn8uAAITAAkJGBoQEwCeAgATAAkJGBoQEwCeAgAAAA==.Roll:BAABLgAECn8jAAIkAAgJfSBpBABCAgAkAAgJfSBpBABCAgAAAA==.Rozgrez:BAABLgAECn8jAAQGAAgJTh1YNQCPAQAGAAcJ4hdYNQCPAQAHAAQJiBjJBwApAQAFAAUJyBXjDAADAQAAAA==.',
Ru='Rufus:BAAALgADCgkJDgAAAA==.Rumlidorgah:BAABLgAECn8fAAQHAAgJ6AvuBgA+AQAGAAgJVwkSQQBmAQAHAAYJWQruBgA+AQAFAAQJVQ1FFgCbAAAAAA==.Runem:BAAALgAECgIJAgAAAA==.Russbus:BAABLgAECn8fAAMQAAkJHg7pKQDXAQAQAAkJHg7pKQDXAQAbAAgJEQf2XAAJAQAAAA==.Ruune:BAAALgAECgUJBwAAAA==.',
Ry='Rynmorelle:BAAALgAECgEJAQAAAA==.',
['Ré']='Réven:BAABLgAECn8bAAIRAAgJiRsJQwAwAQARAAgJiRsJQwAwAQAAAA==.',
Sa='Sadiebella:BAAALgAECgYJBgAAAA==.Sadienna:BAABLgAECn8cAAMjAAkJYAatGAB4AQAjAAkJYAatGAB4AQAYAAgJtAOoRgAfAQAAAA==.Salvidali:BAAALgAECgIJAgABLgAECgcJFgACAEUFAA==.Sandrï:BAABLgAECn8ZAAQGAAYJ4Q/rVAAtAQAGAAYJUg/rVAAtAQAHAAEJHRYNFQBHAAAFAAEJAADHNQAAAAAAAA==.Sane:BAABLgAECn8bAAIUAAgJdBa1LgC+AQAUAAgJdBa1LgC+AQAAAA==.Saoiirse:BAABLgAECn8cAAMRAAcJsBYpLACHAQARAAcJsBYpLACHAQAhAAIJ1hM7LQB5AAAAAA==.Saraella:BAAALgAECggJAgAAAA==.Sasso:BAAALgADCgIJAgAAAA==.Sawako:BAABLgAECn8dAAIjAAgJzhd4DAD/AQAjAAgJzhd4DAD/AQAAAA==.',
Sc='Scalar:BAAALgADCgEJAQAAAA==.Scalyboi:BAAALgADCgMJAwABLgAFFAUJDgACAE4UAA==.Scarletts:BAAALgADCgUJBgABLgAECgUJBQAEAAAAAA==.Schlitzie:BAAALgADCgIJAgAAAA==.Scrapes:BAAALgADCgMJAwAAAA==.Scuba:BAAALgAECgYJCwAAAA==.',
Se='Seraphyne:BAAALgAECgIJAgABLgAFFAYJHAAIANkcAA==.Sevencharlie:BAAALgAECgYJEgAAAA==.',
Sh='Shadowho:BAAALgAECgQJCQAAAA==.Shaladro:BAAALgADCgUJCAAAAA==.Shalanaz:BAAALgAECgEJAQAAAA==.Shamutty:BAAALgAECgMJBAABLgAFFAMJBgACAAAZAA==.Sharasdal:BAAALgAECgEJAQABLgAECggJAgAEAAAAAA==.Sherief:BAAALgADCgQJBAAAAA==.Shieldz:BAAALgAECgEJAQAAAA==.Shinjô:BAAALgAECgQJCwAAAA==.Shiroishi:BAAALgADCgcJBwABLgAECgcJGgAOAPsFAA==.Shivaray:BAAALgADCgUJBQAAAA==.Shiveria:BAAALgADCgYJCwAAAA==.Shocklesner:BAAALgAECggJEAAAAA==.Shorkaan:BAAALgAECgEJAQAAAA==.Shouganai:BAAALgAECgYJDwAAAA==.Shupaz:BAAALgAECgIJAgAAAA==.',
Si='Siddha:BAAALgADCgYJBgABLgAECgYJDwAEAAAAAA==.Sieria:BAAALgAECgYJDQAAAA==.Sifu:BAAALgAECgQJBAAAAA==.Siieerr:BAABLgAFFH8HAAISAAMJuBdFBAAVAQASAAMJuBdFBAAVAQAAAA==.Silvermind:BAAALgAECgYJBwAAAA==.Sinaar:BAAALgAECgIJAwAAAA==.Sindena:BAABLgAECn8aAAIGAAcJPRSjXACyAQAGAAcJPRSjXACyAQAAAA==.Sixsanity:BAAALgAECgQJCgAAAA==.',
Sk='Skavos:BAAALgAECgYJBwAAAA==.Skillcommand:BAAALgAECgQJCgAAAA==.Skipperino:BAAALgADCggJDQAAAA==.Skyemage:BAAALgAECgEJAgAAAA==.',
Sl='Slotz:BAABLgAECn8nAAIbAAcJghv0GwCpAQAbAAcJghv0GwCpAQAAAA==.',
Sm='Smallcoomer:BAAALgAECgcJDgAAAA==.Smallss:BAAALgAECgUJBgAAAA==.Smike:BAABLgAECn8qAAIQAAgJiAr8TgBZAQAQAAgJiAr8TgBZAQAAAA==.',
Sn='Sneeze:BAAALgAECgQJBQAAAA==.Snuggles:BAAALgADCgUJBwAAAA==.',
So='Soferan:BAABLgAECn8bAAIUAAYJjhwkRQBsAQAUAAYJjhwkRQBsAQAAAA==.Softpaws:BAAALgADCgkJAwAAAA==.Sonarr:BAAALgAECgUJCAAAAA==.Sosukeaizen:BAAALgAECgEJAQAAAA==.Sourdeizal:BAAALgADCgEJAQAAAA==.',
Sp='Spacemilk:BAAALgAECggJEQAAAA==.Spark:BAAALgAECgEJAQAAAA==.Spicymeat:BAAALgADCgcJBwABLgAFFAUJDgACAE4UAA==.Sputty:BAAALgAECgYJDwABLgAFFAMJBgACAAAZAA==.',
Sq='Squishee:BAAALgAECgEJAQAAAA==.',
St='Stankmouth:BAABLgAECn8ZAAINAAQJwwXtQQB2AAANAAQJwwXtQQB2AAAAAA==.Stellas:BAAALgADCgUJCAABLgAECgUJCQAEAAAAAA==.Stesha:BAAALgADCgcJEQABLgAECgcJFgARAB8FAA==.Steviewonder:BAABLgAECn8fAAIRAAcJihXmMwBmAQARAAcJihXmMwBmAQAAAA==.Stinkerton:BAAALgAFFAMJAwAAAA==.Stonedfrog:BAAALgADCgcJBwAAAA==.Stonefather:BAABLgAECn8kAAINAAgJeQwLIABGAQANAAgJeQwLIABGAQAAAA==.Stonewall:BAAALgADCgEJAgAAAA==.Strangelets:BAAALgAECgQJBQAAAA==.Strangewayes:BAAALgADCgMJAwAAAA==.Stïtches:BAAALgAECgYJEQAAAA==.Stönk:BAABLgAECn8XAAIFAAcJjRaqBgCCAQAFAAcJjRaqBgCCAQAAAA==.',
Su='Succulentman:BAABLgAECn8oAAIRAAgJESPiDABnAgARAAgJESPiDABnAgAAAA==.Sufferyn:BAAALgADCgcJBwAAAA==.Sunreaver:BAAALgADCgYJCgAAAA==.Supoz:BAAALgAECgEJAQAAAA==.Surolath:BAABLgAECn8oAAIfAAkJpx7UAQC1AgAfAAkJpx7UAQC1AgAAAA==.Suvaun:BAAALgADCgEJAQAAAA==.',
Sw='Swaggles:BAABLgAECn8nAAInAAgJ3yRBAgDUAgAnAAgJ3yRBAgDUAgAAAA==.Swiftcast:BAAALgAECgYJBgAAAA==.Swiftpalms:BAAALgAECgYJBgAAAA==.Swompfox:BAAALgAECgYJCgAAAA==.',
Sy='Sygon:BAABLgAECn8oAAImAAgJGhqoAwAXAgAmAAgJGhqoAwAXAgAAAA==.Sylvannaa:BAAALgAECgYJBwAAAA==.Syntherizena:BAAALgAECgYJBwAAAA==.Synthesized:BAAALgAECgcJDAAAAA==.',
['Só']='Sóng:BAABLgAECn8aAAMYAAcJLh3bEwBAAgAYAAcJLh3bEwBAAgAjAAEJSQ7qXgA7AAAAAA==.',
Ta='Tacitus:BAAALgAECgcJEQAAAA==.Tairrad:BAAALgAECgYJCAAAAA==.Takeru:BAAALgAECgMJBQAAAA==.Talasmar:BAAALgADCgUJBQAAAA==.Tapkora:BAAALgAECgQJCAAAAA==.Tapsum:BAAALgADCgUJBQAAAA==.Tarirn:BAAALgADCgEJAQAAAA==.Taurtem:BAAALgAECgQJBQAAAA==.Taylia:BAAALgAECgQJDAABLgAECgkJGgAPAFMSAA==.Tayona:BAAALgAECgIJAgAAAA==.Tazildek:BAAALgAECgEJAQAAAA==.',
Te='Technique:BAAALgAECggJEgAAAA==.Tergrid:BAAALgAECgMJAwAAAA==.Terial:BAABLgAECn8iAAIbAAgJBiIQBgDAAgAbAAgJBiIQBgDAAgAAAA==.Textoffender:BAAALgAECgQJBgAAAA==.',
Th='Thajeebus:BAAALgADCgEJAQAAAA==.Thatsneat:BAAALgAECgQJBQAAAA==.Thecapt:BAABLgAECn8lAAIgAAkJGRqMDAAiAgAgAAkJGRqMDAAiAgAAAA==.Theôdöræ:BAAALgAECgkJEAAAAA==.Thorinfel:BAABLgAECn8hAAIRAAkJ1xRzNgAdAgARAAkJ1xRzNgAdAgAAAA==.Thsaemage:BAAALgAECgQJBAABLgAECgkJIgAJAJEaAA==.Thunderkiss:BAAALgAECgYJBgAAAA==.Thunran:BAAALgAECgQJBgAAAA==.',
Ti='Tiaoma:BAAALgAECgEJAQAAAA==.Tieria:BAABLgAECn8UAAIjAAcJ7R1vDQDyAQAjAAcJ7R1vDQDyAQAAAA==.Tikao:BAABLgAECn8iAAMiAAgJ0AsfDAAFAQAiAAgJ0AsfDAAFAQAhAAYJpAViQwDqAAABLgAECgkJAQAEAAAAAA==.Tinna:BAAALgAECgcJBgAAAA==.',
Tj='Tjhookèr:BAAALgAECgUJDAAAAA==.',
To='Tobajal:BAABLgAECn8nAAIYAAgJrB9IBADSAgAYAAgJrB9IBADSAgAAAA==.Toletheus:BAABLgAECn8gAAQSAAgJSRp5CACmAQASAAcJZxd5CACmAQAJAAcJVBTAFgCGAQAfAAEJzSW8HQBrAAAAAA==.Tomin:BAAALgAECgYJEQAAAA==.Totemique:BAAALgADCgcJDgABLgAECggJEgAEAAAAAA==.Totumfknpole:BAAALgADCgEJAQAAAA==.',
Tr='Treeperson:BAABLgAECn8UAAIIAAcJZiIIDACKAgAIAAcJZiIIDACKAgAAAA==.Treyni:BAAALgADCgIJAgAAAA==.Trickyric:BAAALgAECgUJCwAAAA==.Trilgy:BAAALgADCgkJCgAAAA==.Trowel:BAABLgAECn8bAAIJAAcJlx+VGQA6AgAJAAcJlx+VGQA6AgABLgAFFAMJBgACAAAZAA==.',
Ts='Tsuyoimono:BAABLgAECn8VAAMDAAYJ8QjWGQDmAAADAAYJ8QjWGQDmAAAgAAQJxAThgwCvAAAAAA==.',
Tu='Turisx:BAAALgADCgQJBQAAAA==.',
Tw='Twiddydh:BAAALgAECgYJEAAAAA==.Twylan:BAAALgADCgYJBgAAAA==.',
Ty='Tydroin:BAAALgADCgMJAwAAAA==.Tytoalba:BAAALgAECgQJBQAAAA==.',
Uk='Ukiru:BAAALgADCgMJAwAAAA==.',
Un='Ungonelilith:BAAALgADCgkJDwAAAA==.Unicrom:BAAALgAECgkJCQAAAA==.',
Ur='Uratsukasama:BAAALgAECgYJBgAAAA==.Urion:BAABLgAECn8YAAQnAAcJ2BgZDwC3AQAnAAcJOhcZDwC3AQATAAMJsh/QlwCmAAAmAAEJ7Q4liQAyAAAAAA==.',
Va='Vacaite:BAAALgAECgIJAwAAAA==.Vagiant:BAABLgAECn8aAAISAAcJ5xN+DgAvAQASAAcJ5xN+DgAvAQAAAA==.Valyna:BAAALgADCgEJAQAAAA==.Vampirica:BAAALgAECgkJBgAAAA==.Vanya:BAABLgAECn8fAAMTAAcJJyBUEwA2AgATAAcJDyBUEwA2AgAnAAYJfxiMDgDdAQAAAA==.Vash:BAAALgADCgYJBgABLgAECgUJCQAEAAAAAA==.Vasso:BAAALgAECgQJBgAAAA==.',
Ve='Velinae:BAAALgAECgkJBgAAAA==.Velint:BAAALgADCgIJAgAAAA==.Velveen:BAABLgAECn8mAAMWAAgJQhV7EgDHAQAWAAgJQhV7EgDHAQAVAAEJtQf/fAA0AAAAAA==.Vexxia:BAAALgAECggJCQAAAA==.',
Vi='Viallure:BAAALgAECgcJDQABLgAECgkJEAAEAAAAAA==.Vilebloom:BAEBLgAECn8eAAIIAAcJDSH4CgCZAgAIAAcJDSH4CgCZAgAAAA==.Viridius:BAAALgAECgQJCAAAAA==.Vitamind:BAAALgADCgEJAQAAAA==.',
Vo='Vonmortis:BAAALgADCgkJFwAAAA==.',
Wa='Wagguslight:BAABLgAECn8iAAIQAAcJNQ9dUQBSAQAQAAcJNQ9dUQBSAQAAAA==.Warzak:BAAALgAECgYJEwAAAA==.Wayne:BAAALgADCgUJBQAAAA==.',
We='Wendybacon:BAABLgAECn8VAAIRAAYJXhQ8bABeAQARAAYJXhQ8bABeAQAAAA==.',
Wh='Whateverdude:BAAALgAECgQJBwAAAA==.Whiskeyshots:BAAALgADCgIJAgAAAA==.Whytè:BAABLgAECn8nAAIIAAgJMCBKCADIAgAIAAgJMCBKCADIAgAAAA==.',
Wi='Wigeon:BAAALgADCggJCAABLgAECggJGwAkADMVAA==.Wiickett:BAABLgAECn8fAAMeAAgJtB2/BAC5AgAeAAgJcx2/BAC5AgAdAAYJrh+KIwChAQAAAA==.Wilbur:BAAALgAECgQJBwAAAA==.Wildebeard:BAACLgAFFH8JAAIbAAQJmCJOCgB7AQAbAAQJmCJOCgB7AQAuAAQKfyIAAhsACQmeJDkFABgDABsACQmeJDkFABgDAAAA.Wilferal:BAAALgAECgQJBAAAAA==.Willaá:BAAALgAECgYJEAAAAA==.Willowyn:BAABLgAECn8qAAMNAAkJfBZjDQAUAgANAAkJfBZjDQAUAgALAAkJXBFVDQDjAQAAAA==.Wingmans:BAAALgAECgQJBwAAAA==.Wizzpeaver:BAABLgAECn8VAAINAAcJgQ3RIAA+AQANAAcJgQ3RIAA+AQAAAA==.',
Wo='Wonderwizard:BAABLgAECn8fAAICAAcJmxOmTACDAQACAAcJmxOmTACDAQAAAA==.',
Wr='Wraeth:BAAALgADCgYJBgAAAA==.Wrathhoof:BAAALgAECgcJCAABLgAECggJEgAEAAAAAA==.',
Xa='Xahra:BAAALgADCgcJBwAAAA==.Xaralyss:BAAALgAECgQJBwAAAA==.',
Xh='Xhine:BAAALgAECgEJAQAAAA==.',
Xi='Xin:BAAALgAECgUJBQAAAA==.',
Xy='Xylias:BAAALgADCgcJEAAAAA==.',
Ya='Yamon:BAAALgADCggJEAAAAA==.',
Yo='Yodef:BAACLgAFFH8IAAIUAAMJ4A2bXQDBAAAUAAMJ4A2bXQDBAAAuAAQKfyAAAhQACAm2I5MKALkCABQACAm2I5MKALkCAAAA.Yorri:BAAALgAECgMJAwAAAA==.',
Yu='Yucca:BAABLgAECn8sAAMUAAkJVhdXFQBQAgAUAAkJVhdXFQBQAgAKAAEJAADxQgAAAAAAAA==.Yuda:BAAALgAECgEJBQAAAA==.Yudaneyo:BAAALgAECgEJBgAAAA==.Yukiteru:BAABLgAECn8eAAMRAAgJ0xz+FgAEAgARAAgJ0xz+FgAEAgAhAAIJ2xW/KwCEAAAAAA==.Yurito:BAABLgAECn8gAAIjAAcJShtnDwDXAQAjAAcJShtnDwDXAQAAAA==.',
Yz='Yzernara:BAAALgAECgEJAQABLgAECggJAgAEAAAAAA==.',
Za='Zabrina:BAABLgAECn8WAAIRAAcJHwX5bQC/AAARAAcJHwX5bQC/AAAAAA==.Zaiel:BAAALgADCgMJAwAAAA==.Zappybains:BAABLgAECn8nAAIVAAgJQSD2BgDBAgAVAAgJQSD2BgDBAgAAAA==.Zarakii:BAABLgAECn8ZAAITAAcJ6R69GQAEAgATAAcJ6R69GQAEAgAAAA==.',
Ze='Zekken:BAAALgADCgMJBAAAAA==.Zelaina:BAAALgAECgcJDwAAAA==.',
Zi='Zi:BAAALgADCgQJBQABLgAECgkJMwAMAMkkAA==.',
Zu='Zuda:BAAALgAECgEJBgAAAA==.Zupaz:BAAALgADCgEJAQAAAA==.',
Zy='Zylluz:BAAALgAECggJDgAAAA==.Zylos:BAAALgAECgYJEwAAAA==.',
['Zì']='Zìnn:BAAALgAECgIJAgAAAA==.',
['Äs']='Äshébringer:BAACLgAFFH8MAAIQAAUJYxxxCABuAQAQAAUJYxxxCABuAQAuAAQKfx4AAhAACQlKJLUEAAUDABAACQlKJLUEAAUDAAAA.Ästen:BAAALgAECgIJAgAAAA==.',
['Æt']='Æthelred:BAAALgAECgEJAQABLgAECgYJFgAJAL0ZAA==.',
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

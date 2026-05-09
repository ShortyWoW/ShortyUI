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

local lookup = {'Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Druid-Guardian','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Enhancement','Mage-Frost','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Mage-Arcane','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Blood','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Druid-Feral',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abadacalama:BAABLgAECn8UAAIBAAcJaROkRgByAQABAAcJaROkRgByAQAAAA==.',
Ad='Adera:BAAALgADCgEJAQAAAA==.',
Ae='Aellee:BAAALgAECgQJCAAAAA==.Aeninas:BAABLgAECn8VAAICAAYJtxi0GgBfAQACAAYJtxi0GgBfAQABLgAECgYJFgADAGYgAA==.Aeris:BAAALgADCgEJAQAAAA==.Aerynn:BAAALgADCgIJAgAAAA==.Aethwyn:BAAALgAECgcJBwAAAA==.',
Af='Afflictions:BAAALgADCgUJBQAAAA==.',
Ag='Agandaur:BAAALgAECgEJAQAAAA==.',
Ah='Ahnkala:BAAALgAECgQJCgAAAA==.Ahzi:BAABLgAECn8kAAIEAAgJ0hyWDQB1AgAEAAgJ0hyWDQB1AgAAAA==.Ahzii:BAAALgADCgYJBwAAAA==.',
Ai='Aigirlfriend:BAABLgAECn8nAAIFAAkJ2Ql9NgBcAQAFAAkJ2Ql9NgBcAQAAAA==.Ains:BAAALgAECggJEAAAAA==.Airsia:BAAALgADCggJDAAAAA==.',
Ak='Akro:BAAALgADCgkJCAAAAA==.',
Al='Allupcreepy:BAABLgAECn8aAAIGAAcJXiLCBgCLAgAGAAcJXiLCBgCLAgAAAA==.Alphaandy:BAAALgAECgMJAwAAAA==.Alphaboy:BAAALgADCgcJBwAAAA==.Alphaxdruid:BAAALgAECgMJAwAAAA==.Alphaxsham:BAAALgADCgIJAgAAAA==.Alysara:BAAALgAECgMJAwAAAA==.',
Am='Ambewlance:BAABLgAECn8XAAMHAAgJXA5NOACEAQAHAAgJOA5NOACEAQAIAAMJRA5zQQCvAAAAAA==.Ambrosious:BAAALgAECgEJAQAAAA==.Amethystra:BAABLgAECn8pAAMJAAkJew28EwCqAQAJAAkJew28EwCqAQAKAAMJwwaNMgCBAAAAAA==.Amâlynd:BAABLgAECn8ZAAIEAAgJywVFTgDbAAAEAAgJywVFTgDbAAAAAA==.',
An='Anastasiaro:BAAALgADCgEJAQAAAA==.Anien:BAAALgADCgEJAQAAAA==.Annimosity:BAAALgAECgIJAwAAAA==.Ansem:BAAALgADCgUJBgAAAA==.Anthesis:BAACLgAFFH8IAAIEAAMJgBgfHQDtAAAEAAMJgBgfHQDtAAAuAAQKfx4AAgQACAmgGS8TADECAAQACAmgGS8TADECAAAA.Anthonor:BAAALgAECgYJCAAAAA==.Anubrian:BAABLgAECn8WAAILAAYJbwUGgQDfAAALAAYJbwUGgQDfAAAAAA==.Anúbis:BAAALgAECgQJCQAAAA==.',
Ap='Apawllo:BAABLgAECn8oAAIMAAkJ2hOICQCJAQAMAAkJ2hOICQCJAQAAAA==.Apep:BAAALgAECgUJEAAAAA==.Apostle:BAACLgAFFH8ZAAIGAAYJLxlSAQC6AQAGAAYJLxlSAQC6AQAuAAQKfykAAgYACQlzIdoGAOACAAYACQlzIdoGAOACAAAA.',
Ar='Aramìs:BAAALgADCgYJBgAAAA==.Aryto:BAABLgAECn8eAAMNAAcJohyxDAD8AQANAAcJohyxDAD8AQAOAAEJOgXLWgAtAAAAAA==.',
As='Ashlar:BAAALgADCgYJCQAAAA==.Asketill:BAAALgAFFAIJAwAAAA==.Astora:BAAALgADCggJCAABLgAECggJFgACAKUZAA==.',
At='Ativan:BAEBLgAECn8jAAQPAAcJxRiLDwD0AQAPAAcJxRiLDwD0AQAQAAMJwwdGOwCRAAACAAEJcgCEeAAaAAAAAA==.',
Au='Auluras:BAAALgADCgUJBQAAAA==.',
Av='Avitus:BAAALgADCgIJBAAAAA==.',
Ay='Aylari:BAABLgAECn8vAAMBAAkJoCS9AQBSAwABAAkJjSS9AQBSAwARAAYJ+ReXEgCgAQAAAA==.',
Az='Azonya:BAAALgADCgEJAgAAAA==.Azuth:BAAALgADCgMJAwAAAA==.',
Ba='Baaloo:BAAALgAECgEJAQABLgAECgQJBwASAAAAAA==.Bachren:BAAALgAECgYJCgAAAA==.Badil:BAAALgADCgIJAgAAAA==.Baitken:BAABLgAECn8WAAIDAAYJZiDPEwD0AQADAAYJZiDPEwD0AQAAAA==.Batharel:BAABLgAECn8iAAITAAcJChcjMgDnAQATAAcJChcjMgDnAQAAAA==.',
Bd='Bdrone:BAAALgADCgYJCAAAAA==.',
Be='Bearen:BAABLgAECn8gAAIUAAgJOAkFCgB3AQAUAAgJOAkFCgB3AQAAAA==.Bedazzle:BAAALgADCgcJBwABLgAFFAYJGQAGAC8ZAQ==.Beefo:BAAALgADCgUJBAAAAA==.Beemz:BAAALgAECgcJEwAAAA==.Beertrain:BAABLgAECn8lAAILAAkJ/hT4HAAaAgALAAkJ/hT4HAAaAgAAAA==.Beesechurger:BAABLgAECn8hAAIVAAgJZBydGgBKAgAVAAgJZBydGgBKAgAAAA==.Bekindrewind:BAABLgAECn8YAAIJAAgJsBaVFwCFAQAJAAgJsBaVFwCFAQAAAA==.Belladonia:BAAALgADCgcJBwABLgAECgkJMAAEAPYTAA==.Belladue:BAAALgADCgMJBgAAAA==.Bellezza:BAABLgAECn8wAAIEAAkJ9hMzKAAUAgAEAAkJ9hMzKAAUAgAAAA==.Bex:BAAALgADCgEJAQAAAA==.',
Bh='Bheef:BAAALgADCgMJAwAAAA==.',
Bi='Bigdisc:BAAALgADCgIJAgABLgAECgMJAwASAAAAAA==.Bigdumbcatqt:BAABLgAECn8pAAIRAAkJ6CYHAACTAwARAAkJ6CYHAACTAwAAAA==.Bignjuicy:BAAALgADCggJDwAAAA==.',
Bl='Blinkk:BAAALgADCgEJAgABLgADCgMJAwASAAAAAA==.Bloodeagle:BAAALgADCgcJBwAAAA==.Bloodshhot:BAABLgAECn8rAAMTAAgJjhX2JQC9AQATAAcJlxj2JQC9AQAWAAEJVANujgAsAAAAAA==.Bloodthorne:BAAALgADCgUJBQAAAA==.Bludgen:BAAALgAECgEJAQABLgAECggJHAAOANEeAA==.',
Bo='Bobitt:BAAALgAECgYJEAAAAA==.Boddyknocker:BAAALgAECgYJDQAAAA==.Boinkusan:BAABLgAECn8jAAIPAAkJXiCdBQCzAgAPAAkJXiCdBQCzAgAAAA==.Bolthar:BAABLgAECn8WAAIBAAgJxA6jWQA9AQABAAgJxA6jWQA9AQAAAA==.Bonkler:BAABLgAECn8gAAMIAAgJ1BlREgC5AQAHAAgJnxU0IwDgAQAIAAYJyhlREgC5AQAAAA==.Boombox:BAAALgAECgYJDQAAAA==.Boomwand:BAAALgAECgUJCwABLgAECggJJAADAOcdAA==.Boonerichard:BAAALgAECgUJDAAAAA==.Bootysweatz:BAAALgADCgcJCQAAAA==.Bouchewager:BAAALgADCgcJDgAAAA==.',
Br='Braina:BAAALgAECgcJDgAAAA==.Braver:BAACLgAFFH8NAAMXAAYJDAqpCgAxAQAXAAUJpgipCgAxAQAWAAUJwgiMEQAgAQAuAAQKfysAAxYACQnFHxsJAA8DABYACQnFHxsJAA8DABcAAgmoBecvAHkAAAAA.Braverwar:BAAALgAECgYJDAABLgAFFAYJDQAXAAwKAA==.Brayedine:BAAALgAECggJDgAAAA==.Break:BAACLgAFFH8RAAIBAAcJCR2OAABxAgABAAcJCR2OAABxAgAuAAQKfxsAAgEACQm1JY4BAMwDAAEACQm1JY4BAMwDAAEuAAUUBwkRAAEACR0A.Breekachu:BAAALgADCgYJBgAAAA==.Brodin:BAAALgADCgUJBQAAAA==.Brohymn:BAAALgADCgEJAQAAAA==.Bromaldehyde:BAAALgADCgIJAgAAAA==.Brooké:BAAALgADCgEJAQAAAA==.Bruj:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebutt:BAAALgADCgEJAQAAAA==.Bubbledis:BAAALgAECgQJDAABLgAECgcJFgAQAJwPAA==.Bullfury:BAAALgADCgEJAQAAAA==.',
['Bù']='Bùbbles:BAAALgAECgQJBwAAAA==.',
Ca='Cadelsaya:BAABLgAECn8wAAMDAAkJeA8nNACtAQADAAkJeA8nNACtAQABAAIJHAIdKwFLAAAAAA==.Caletha:BAABLgAECn8WAAMGAAYJSRsXKQCpAQAGAAYJ5RgXKQCpAQAOAAUJRBeiIgB/AQAAAA==.Calimaria:BAAALgAECgEJAQAAAA==.Calixte:BAAALgAECgYJCgAAAA==.Cammandzar:BAAALgAECgYJCQABLgAECgUJBQASAAAAAA==.Canman:BAAALgAECgMJBgAAAA==.Cardeller:BAAALgADCgUJCAAAAA==.Cassei:BAACLgAFFH8JAAIDAAMJpg0lGwDLAAADAAMJpg0lGwDLAAAuAAQKf0MAAwMACAkCIOcHAJcCAAMACAkCIOcHAJcCAAEABAmNDOWfALEAAAAA.',
Ce='Celenia:BAAALgAECgUJDwAAAA==.Celorious:BAAALgAFFAEJAQAAAA==.',
Ch='Chainari:BAAALgAECgYJDwAAAA==.Chassis:BAAALgADCgcJCAABLgAECgYJFgACAKAVAA==.Chawìzawd:BAAALgADCgYJBgAAAA==.Chee:BAAALgAECgEJAgAAAA==.Cheechychong:BAAALgAECgEJAQAAAA==.Cheeksdakota:BAAALgADCgYJBgAAAA==.Cheetopaly:BAABLgAECn8XAAMDAAgJ2xuKSwBKAQADAAYJWRqKSwBKAQABAAcJFAo1gwDlAAAAAA==.Cherrycrush:BAAALgAECgMJAwAAAA==.Chummy:BAACLgAFFH8FAAIYAAMJcQlaGgDQAAAYAAMJcQlaGgDQAAAuAAQKfxwAAhgACQm4ENMMAP4BABgACQm4ENMMAP4BAAAA.Chìgusa:BAABLgAECn8oAAIGAAkJoRPDHgDpAQAGAAkJoRPDHgDpAQAAAA==.',
Ci='Cigarette:BAABLgAECn8ZAAMEAAYJkw5CPgAbAQAEAAYJkw5CPgAbAQAYAAIJ8QtkSABeAAAAAA==.Cilenzer:BAAALgAECgQJBgABLgAECgYJFgAYAHUQAA==.Cinadra:BAAALgAECgQJBAAAAA==.Circa:BAAALgADCgUJBwAAAA==.',
Cl='Clumonk:BAABLgAECn8bAAIQAAgJoxtvCgATAgAQAAgJoxtvCgATAgAAAA==.',
Co='Convoke:BAAALgAFFAIJAwABLgAFFAYJGQAGAC8ZAA==.Coosar:BAAALgAECgEJAgAAAA==.Coose:BAAALgAECgYJBwABLgAECgcJCgASAAAAAA==.Coosedaplug:BAAALgADCgEJAQABLgAECgcJCgASAAAAAA==.Coosey:BAAALgAECgcJCgAAAA==.Cooseyloosey:BAAALgAECgIJAgABLgAECgcJCgASAAAAAA==.Coosicle:BAAALgAECgIJAgABLgAECgcJCgASAAAAAA==.Coredron:BAAALgAECgMJBAAAAA==.Corellon:BAABLgAECn8fAAIBAAYJHRKrYgAoAQABAAYJHRKrYgAoAQAAAA==.Corinth:BAABLgAECn8iAAIZAAkJfxuxAACOAgAZAAkJfxuxAACOAgAAAA==.',
Cr='Cratoz:BAAALgAECgcJCQAAAA==.Craylic:BAAALgADCgkJDgAAAA==.Creepi:BAAALgAECgQJCQAAAA==.Criah:BAAALgADCggJCQAAAA==.Crixhs:BAAALgADCgUJBQAAAA==.Crossgideon:BAABLgAECn8aAAIFAAcJBAvgVQD6AAAFAAcJBAvgVQD6AAAAAA==.Crosstero:BAAALgADCgYJBgAAAA==.Crossword:BAAALgADCgcJBwAAAA==.Croswind:BAAALgADCgUJBQABLgAECgcJGgAFAAQLAA==.',
Cu='Curandero:BAAALgADCgcJDwABLgAECgMJBgASAAAAAA==.Currah:BAAALgAECgEJAQAAAA==.',
Cy='Cyndrine:BAABLgAECn8wAAIaAAkJcSUkAABfAwAaAAkJcSUkAABfAwAAAA==.Cyrani:BAAALgADCgcJBwAAAA==.Cyrcyn:BAAALgAECgkJCQAAAA==.',
Da='Dadipps:BAABLgAECn8aAAIbAAgJwSE4BQDnAgAbAAgJwSE4BQDnAgAAAA==.Daggumit:BAAALgADCgYJBwAAAA==.Dagnei:BAAALgAECgMJBAAAAA==.Daltina:BAAALgAECgYJDAAAAA==.Dannyboone:BAAALgADCgEJAQAAAA==.Darg:BAABLgAECn8cAAMcAAcJOxhpDQCbAQAcAAcJABhpDQCbAQALAAMJORUV5gC0AAAAAA==.Daurgoth:BAAALgADCgEJAQABLgADCgcJBwASAAAAAA==.',
Dd='Ddream:BAAALgADCgMJAwAAAA==.',
De='Deathpuma:BAABLgAECn8WAAIcAAcJkRmkDgCHAQAcAAcJkRmkDgCHAQAAAA==.Deathrowe:BAABLgAECn8oAAILAAgJSB9ZEQByAgALAAgJSB9ZEQByAgAAAA==.Deelyte:BAAALgAECgQJBAAAAA==.Deezenuts:BAAALgADCgMJAwAAAA==.Delorayne:BAAALgADCggJEAAAAA==.Demonic:BAAALgADCgcJDAAAAA==.Demonponii:BAAALgAECggJCwAAAA==.Demonvann:BAAALgADCgkJHAAAAA==.Denouncer:BAABLgAECn8kAAMDAAgJ5x2oEAAWAgADAAcJlB2oEAAWAgABAAYJihLkdQAAAQAAAA==.Deralth:BAAALgAECgMJAwAAAA==.Derca:BAAALgAECgUJDgAAAA==.Dercadin:BAAALgADCgYJDAAAAA==.Dethman:BAAALgAECgQJBwAAAA==.Devoider:BAAALgAECgIJAgAAAA==.',
Di='Diddyknight:BAACLgAFFH8IAAIcAAQJtw94DgD6AAAcAAQJtw94DgD6AAAuAAQKfyQAAxwACAmMEZAWAKwBABwACAmMEZAWAKwBAAsAAgmABn3CAGIAAAAA.Diddyrox:BAAALgADCgkJCAABLgAECggJHAAcADkdAA==.Dienne:BAEALgAECggJEgABLgAECgkJIwAPAMUYAA==.Diminish:BAAALgAECgQJCAABLgAECgcJCgASAAAAAA==.Diminutive:BAAALgADCgEJAQAAAA==.Dinarra:BAAALgAECgEJAQAAAA==.Diosdelaluna:BAAALgAECgEJAQAAAA==.Dipity:BAAALgADCgYJBgAAAA==.Discobirb:BAABLgAECn8mAAMHAAkJdhZrGwALAgAHAAgJpRZrGwALAgAIAAMJEBSSGACBAAAAAA==.',
Do='Docdrood:BAAALgADCgYJCQAAAA==.Dohdag:BAAALgADCgEJAQAAAA==.Dokkyun:BAAALgADCgEJAwAAAA==.Donlazul:BAABLgAECn8dAAMbAAkJ3hkjHwAlAgAbAAkJ3hkjHwAlAgAdAAUJAg6ZNgDUAAAAAA==.Dorff:BAABLgAECn8kAAMIAAgJwRMOFQCiAQAIAAYJjBUOFQCiAQAHAAgJ0g0mNACUAQAAAA==.Dotlotto:BAABLgAECn8bAAIIAAgJPxnTAgAPAgAIAAgJPxnTAgAPAgAAAA==.',
Dr='Draconoth:BAABLgAECn8aAAILAAYJHxCBWgAxAQALAAYJHxCBWgAxAQAAAA==.Dragonare:BAAALgAECgYJBgABLgAECggJHAAcADkdAA==.Dragonir:BAAALgAECgQJCwABLgAECggJGwABAPIZAA==.Dranddrand:BAABLgAECn8XAAICAAkJ5Rp3EwB1AgACAAkJ5Rp3EwB1AgAAAA==.Dreadborn:BAAALgADCgYJCAAAAA==.Dreadform:BAAALgADCgcJCwAAAA==.Drizit:BAAALgAECgQJBQAAAA==.Drunkardd:BAAALgADCgYJBgAAAA==.',
Du='Dumbbear:BAAALgADCgcJCgAAAA==.Dungard:BAAALgADCgcJBwABLgAECgkJMAADAHgPAA==.Dunstird:BAAALgAFFAMJAwAAAA==.',
Dy='Dyami:BAAALgADCgkJCQAAAA==.',
['Dè']='Dèadèyè:BAAALgADCgEJAQAAAA==.',
Ea='Earthkorra:BAAALgADCgEJAQAAAA==.Eatmorechkn:BAABLgAECn8fAAIBAAgJzxGtMwCuAQABAAgJzxGtMwCuAQAAAA==.',
Ed='Edgli:BAAALgAECgQJBAAAAA==.Edlania:BAAALgAECgEJAQAAAA==.',
Ee='Eellonwy:BAAALgAECgMJBwAAAA==.Eemerald:BAAALgAECgUJDAAAAA==.',
Eg='Egna:BAABLgAECn8pAAIdAAgJ/BHcGACJAQAdAAgJ/BHcGACJAQAAAA==.',
El='Eldiablo:BAABLgAECn8vAAILAAkJpiFHBgD4AgALAAkJpiFHBgD4AgAAAA==.Elfshots:BAAALgADCgQJBAABLgAECgcJFgAQAJwPAA==.Elizaa:BAABLgAECn8jAAMbAAgJbAlkXwAOAQAbAAcJcwdkXwAOAQAdAAcJ8geeMADxAAAAAA==.Ellemeno:BAAALgAECgUJBQAAAA==.Eloria:BAAALgADCgIJAgAAAA==.',
Em='Emmadar:BAAALgADCgkJGwABLgAECgkJLwAHACkVAA==.',
En='Ennoa:BAAALgAECgUJBAAAAA==.',
Er='Eric:BAAALgAECgYJCQAAAA==.Erinn:BAAALgADCggJDQAAAA==.Erioch:BAAALgAECgEJAQAAAA==.',
Et='Etoya:BAAALgAECgMJAwAAAA==.',
Ex='Execute:BAAALgADCgYJBwAAAA==.',
Ez='Ezykeil:BAAALgADCgYJBgAAAA==.',
Fe='Feelinbetter:BAAALgAECgIJBQAAAA==.Felicía:BAAALgAECgMJAwAAAA==.Fenrigaar:BAABLgAECn8cAAIYAAcJlBZGGAB5AQAYAAcJlBZGGAB5AQAAAA==.',
Fi='Fillin:BAAALgAECgMJBgAAAA==.Filô:BAACLgAFFH8JAAINAAQJ/wzSDQAvAQANAAQJ/wzSDQAvAQAuAAQKfyAAAg0ACQn/Hh0DAM8CAA0ACQn/Hh0DAM8CAAAA.',
Fj='Fjörd:BAAALgAECgEJAwAAAA==.',
Fl='Flanker:BAAALgAECgUJBQABLgAECggJIQAVAGQcAA==.Flashbang:BAAALgAECgYJBgABLgAECggJIwAFAF4SAA==.Flasherdemon:BAAALgAECgYJBgAAAA==.Flashoblight:BAAALgADCgYJDAABLgADCgkJDgASAAAAAA==.',
Fo='Forsakenly:BAABLgAECn8lAAITAAgJphbpIgDMAQATAAgJphbpIgDMAQAAAA==.',
Fr='Frasti:BAAALgAECgMJBgAAAA==.Freshstart:BAAALgAECgYJCQAAAA==.Frostmage:BAABLgAECn8vAAIVAAkJbR0vDAC+AgAVAAkJbR0vDAC+AgAAAA==.Frstbite:BAAALgADCgIJAgAAAA==.',
Fu='Fuegoblazeit:BAAALgAECgIJBAAAAA==.Fuhsrodah:BAAALgADCgEJAgAAAA==.Fulgure:BAABLgAECn8iAAIdAAkJWRmjCQA/AgAdAAkJWRmjCQA/AgAAAA==.Furbucket:BAABLgAECn8WAAMYAAcJAwm7MgDFAAAYAAYJYQe7MgDFAAAEAAQJLwjgkQCsAAAAAA==.Futon:BAAALgAECgQJBAAAAA==.Futonhunts:BAABLgAECn8sAAMTAAkJiyAJCQADAwATAAkJiyAJCQADAwAXAAUJgQ5mGwApAQAAAA==.',
Fy='Fylerw:BAAALgAECggJEQAAAA==.',
['Få']='Fåe:BAAALgAECgMJBQAAAA==.',
Ga='Gagoogamesh:BAABLgAECn8iAAQLAAkJ2RFwJADxAQALAAkJYhBwJADxAQAeAAkJ5ws2BwA8AQAcAAEJWgCcUAASAAAAAA==.Gailyn:BAAALgADCggJEgAAAA==.Galaxyshot:BAAALgADCgcJDAAAAA==.Garhiakitten:BAAALgADCgkJCQAAAA==.',
Ge='Gendershift:BAAALgADCgQJBAAAAA==.Getpsalm:BAAALgAECgkJBwAAAA==.',
Gh='Ghimpy:BAAALgAECgQJCgAAAA==.Ghostrideher:BAABLgAECn8lAAITAAkJMR7oBwCzAgATAAkJMR7oBwCzAgAAAA==.',
Gi='Gigadad:BAAALgAECgQJBAAAAA==.Gigafather:BAAALgAECgMJBAAAAA==.',
Gl='Glurpglurp:BAAALgADCgEJAQAAAA==.',
Go='Goochkiss:BAAALgAECgMJAwAAAA==.',
Gr='Griannee:BAABLgAECn8iAAIfAAgJ3hnsCAABAgAfAAgJ3hnsCAABAgAAAA==.Grimborn:BAAALgAECgIJAgAAAA==.Gripmedaddy:BAAALgADCgEJAQABLgAECggJKQAPAP8YAA==.Grisdrips:BAAALgAECgQJBQAAAA==.Grislix:BAABLgAECn8mAAMHAAgJtxXWKQC+AQAHAAgJtxXWKQC+AQAIAAEJkQU5LAAjAAABLgAECgQJBQASAAAAAA==.Gryffin:BAABLgAECn8oAAIVAAgJmA9HRgCUAQAVAAgJmA9HRgCUAQAAAA==.',
Gu='Gurrth:BAAALgADCgMJAwAAAA==.',
['Gâ']='Gânk:BAABLgAECn8oAAMgAAkJnwp2DQBqAQAgAAkJnwp2DQBqAQAhAAIJmQJMnQBKAAAAAA==.',
['Gå']='Gåladriel:BAAALgAECgEJAQAAAA==.',
Ha='Hael:BAAALgADCgEJAQAAAA==.Halar:BAABLgAECn8VAAIEAAgJJQ+mPgAZAQAEAAgJJQ+mPgAZAQAAAA==.Hammaford:BAAALgADCgMJAwAAAA==.Happiness:BAAALgAECgcJCgAAAA==.Hardknockers:BAABLgAECn8VAAIhAAYJBwsmLQAcAQAhAAYJBwsmLQAcAQAAAA==.Hargyll:BAAALgAECgcJDwAAAA==.',
He='Heavensbliss:BAAALgADCgkJCQABLgAECgkJLwAVAG0dAA==.Heavychevy:BAABLgAECn8WAAMhAAcJDRXgIgBYAQAhAAYJvxXgIgBYAQAgAAEJlxHIOQA7AAAAAA==.Hellbentx:BAAALgAECgcJBwAAAA==.Heriel:BAAALgAECgQJBAABLgAECggJGwABAPIZAA==.',
Hi='Hippyhunter:BAAALgAECgIJAwAAAA==.',
Ho='Hokes:BAAALgAFFAIJBAABLgAFFAMJBgAEAOELAA==.Hole:BAAALgADCgMJAwAAAA==.Homgar:BAAALgADCgYJBwAAAA==.Hoori:BAABLgAFFH8TAAIiAAkJ4yMGAABgAwAiAAkJ4yMGAABgAwAAAA==.',
Hu='Hughhoofner:BAAALgAECgUJBgAAAA==.Humphrees:BAABLgAECn8vAAMjAAkJcBMyBwA5AgAjAAkJcBMyBwA5AgAkAAEJFwaVIQAqAAAAAA==.Huraji:BAAALgAFFAIJAgABLgAFFAQJDgAOACcdAA==.',
Hy='Hydroheals:BAAALgADCgkJCwAAAA==.',
['Hà']='Hàtos:BAABLgAECn8tAAIVAAgJxxvOIQAiAgAVAAgJxxvOIQAiAgAAAA==.Hàtoz:BAAALgAECgcJAwAAAA==.',
Ii='Iironrod:BAAALgADCgcJDgAAAA==.',
Il='Illran:BAAALgAECgEJAQAAAA==.',
Im='Impawsum:BAAALgADCgUJBwAAAA==.',
In='Invissibill:BAABLgAECn8cAAIlAAcJRAZJCAAGAQAlAAcJRAZJCAAGAQAAAA==.',
Ir='Ironbark:BAAALgADCgcJFgAAAA==.',
Iv='Ivanã:BAABLgAECn8gAAIaAAcJ4xukBADeAQAaAAcJ4xukBADeAQAAAA==.',
Iz='Izax:BAABLgAECn8fAAIHAAgJUAvgPAB0AQAHAAgJUAvgPAB0AQAAAA==.',
Ja='Jamestown:BAAALgADCgcJBwAAAA==.Janebquick:BAAALgAECgUJBgAAAA==.',
Je='Jelkal:BAAALgAECgkJEgAAAA==.Jemstone:BAAALgADCgYJBgAAAA==.',
Jj='Jjl:BAAALgAFFAIJAgAAAA==.',
Jo='Johnnylingo:BAAALgAECgEJAQAAAA==.Johnwarcratf:BAAALgAECgYJDAAAAA==.',
Ju='Jupitus:BAABLgAECn8gAAIBAAgJoxY2IgD9AQABAAgJoxY2IgD9AQAAAA==.Juícewrld:BAAALgAECgQJBgAAAA==.',
['Jå']='Jåhkøtå:BAAALgADCgYJBgAAAA==.',
Ka='Kaboomkablow:BAAALgAECgQJBAABLgAECgcJFgAQAJwPAA==.Kaosz:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8YAAIQAAcJICMNBwBZAgAQAAcJICMNBwBZAgAAAA==.Katalanii:BAABLgAECn8ZAAIEAAcJvAnJTADgAAAEAAcJvAnJTADgAAAAAA==.Kathtaer:BAAALgADCggJDQAAAA==.Katja:BAABLgAECn8YAAIHAAgJbRmgKQBqAgAHAAgJbRmgKQBqAgAAAA==.',
Ke='Kegna:BAAALgADCgkJCQAAAA==.Keiwhenua:BAABLgAECn8fAAMEAAgJZg7JMgBRAQAEAAgJZg7JMgBRAQAYAAUJaAp7NAC8AAAAAA==.Keled:BAAALgAECgQJCAAAAA==.Kelinn:BAAALgAECgQJBwAAAA==.Kelle:BAAALgAECgYJBgAAAA==.Kelzier:BAAALgAECgUJCAABLgAECggJGwABAPIZAA==.Kenthel:BAABLgAECn8VAAIjAAQJrx2/FwBHAQAjAAQJrx2/FwBHAQABLgAECgYJEAASAAAAAA==.Kenthels:BAAALgAECgYJEAAAAA==.Kezt:BAAALgADCgEJAQAAAA==.',
Kh='Khaleesi:BAAALgAECgkJCAAAAA==.Khalena:BAAALgADCgUJBwAAAA==.',
Ki='Kiiya:BAAALgAECgIJAgAAAA==.Kik:BAAALgAECgEJAQAAAA==.Killerchop:BAABLgAECn8bAAMZAAgJChnhBADvAQAZAAcJ8BjhBADvAQAVAAcJKhMdfADZAQAAAA==.Kiplander:BAABLgAECn8WAAIYAAYJdRCfJQAQAQAYAAYJdRCfJQAQAQAAAA==.Kithforge:BAAALgADCgEJAQAAAA==.Kittytree:BAAALgADCgQJBAAAAA==.',
Ko='Kohii:BAAALgAECgIJAgAAAA==.Korry:BAAALgAECgUJDgAAAA==.Kortanis:BAAALgADCgkJLAAAAA==.Korzaz:BAAALgAECgYJEQAAAA==.Kosiicek:BAAALgAECgEJAQAAAA==.Kotala:BAAALgADCgUJBwAAAA==.',
Kr='Krakìn:BAAALgAECgUJDwAAAA==.Krelanllan:BAAALgADCgkJDQAAAA==.Krilliz:BAABLgAECn8UAAIfAAcJvQ9kKwBsAQAfAAcJvQ9kKwBsAQAAAA==.Krocodile:BAAALgAECgQJBwAAAA==.',
Ku='Kushage:BAAALgADCggJEAAAAA==.',
Ky='Kyndarra:BAAALgADCgcJBwABLgAECggJKAAEAI4RAA==.Kynlea:BAAALgADCgMJAwAAAA==.Kyumii:BAAALgADCgcJBwAAAA==.',
['Kì']='Kìla:BAAALgAECgEJAQABLgAECgkJLwABAKAkAA==.',
La='Landissa:BAABLgAECn8nAAIjAAgJ7hsSCAAmAgAjAAgJ7hsSCAAmAgAAAA==.Lanigosa:BAAALgADCggJBwAAAA==.Lanno:BAAALgADCgUJBgAAAA==.Laquandrae:BAABLgAECn8UAAIBAAUJ1B7KTwBXAQABAAUJ1B7KTwBXAQAAAA==.Larryholmes:BAABLgAECn8WAAIQAAcJnA/wLQB0AQAQAAcJnA/wLQB0AQAAAA==.Lasting:BAAALgADCgYJCAAAAA==.Lathmaria:BAAALgADCgEJAQAAAA==.',
Le='Leche:BAAALgAECgUJCQAAAA==.Leenaa:BAABLgAECn8oAAIEAAgJjhG8JACjAQAEAAgJjhG8JACjAQAAAA==.Lerash:BAAALgADCgIJAgAAAA==.',
Li='Liankaima:BAAALgADCgUJBQAAAA==.Lightninfury:BAAALgAECgUJBwAAAA==.Lihan:BAABLgAECn8VAAIhAAcJqhNLHgB3AQAhAAcJqhNLHgB3AQAAAA==.Lilieth:BAAALgADCgIJAgAAAA==.Lily:BAABLgAECn8nAAILAAgJSRk+JADyAQALAAgJSRk+JADyAQAAAA==.Livelyfist:BAABLgAECn8aAAIPAAcJhRlsFgCjAQAPAAcJhRlsFgCjAQAAAA==.Livelywilds:BAAALgADCgYJBgAAAA==.Livvmore:BAAALgADCgEJAQAAAA==.',
Lo='Locki:BAAALgADCgcJBwAAAA==.Loosenut:BAAALgAECgEJAQAAAA==.Lortelle:BAAALgAECgQJBAABLgAECggJHAAcADkdAA==.Losic:BAAALgADCgcJCwAAAA==.Lotzofblood:BAAALgAECgQJBAAAAA==.Loverocket:BAABLgAECn8lAAIRAAkJDh0cAgCiAgARAAkJDh0cAgCiAgAAAA==.',
Lu='Lugosi:BAAALgADCgcJDQABLgAECgkJLwAFAEEaAA==.Lullers:BAAALgAECgMJBgAAAA==.Luna:BAAALgAECgYJCwABLgAFFAIJAgASAAAAAA==.Lunastorm:BAAALgADCgYJDAAAAA==.Luroe:BAAALgADCgkJCQAAAA==.',
Ly='Lyralina:BAEALgADCgQJBAABLgAECgkJIwAPAMUYAA==.Lysergicon:BAAALgADCgEJAQAAAA==.Lyshia:BAABLgAECn8oAAIVAAkJqSG3CADnAgAVAAkJqSG3CADnAgAAAA==.Lyshion:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìch:BAAALgADCgIJAgAAAA==.',
['Lí']='Líghthand:BAABLgAECn8eAAMRAAkJPx+nAQA2AwARAAkJPx+nAQA2AwABAAEJvw4m/AA5AAABLgAFFAIJAgASAAAAAA==.',
['Lý']='Lýght:BAAALgADCggJDAAAAA==.',
Ma='Magdaanii:BAAALgAECgUJCAAAAA==.Magedown:BAABLgAECn8bAAIVAAkJQhIZJgAMAgAVAAkJQhIZJgAMAgAAAA==.Magician:BAAALgAECgQJBwABLgAECgcJFgAQAJwPAA==.Magicmallet:BAABLgAECn8dAAIDAAkJwiOHAwA6AwADAAkJwiOHAwA6AwAAAA==.Manwell:BAAALgAECgMJAwAAAA==.Martinell:BAAALgADCgYJDAAAAA==.Matap:BAAALgADCgkJGwAAAA==.Mataw:BAABLgAECn8lAAMhAAgJCR4WCABrAgAhAAgJCR4WCABrAgAgAAYJ3BCyFgBHAQAAAA==.Mattdemon:BAABLgAECn8vAAIFAAkJQRr8DgBPAgAFAAkJQRr8DgBPAgAAAA==.Maulotov:BAAALgAECgYJBgAAAA==.',
Me='Mehruna:BAAALgADCgEJAgAAAA==.Meliany:BAAALgADCgMJAwAAAA==.Meliowar:BAAALgADCgQJBAAAAA==.Melkdudd:BAAALgAECgcJBwAAAA==.Mephmonster:BAAALgADCgEJAQAAAA==.Merrciless:BAAALgAECgYJBgAAAA==.Meríin:BAAALgADCggJDgAAAA==.Meteori:BAAALgADCgEJAQAAAA==.Metroboomkin:BAAALgAECgIJAgAAAA==.',
Mi='Miksi:BAAALgADCgcJFgABLgAECgQJBwASAAAAAA==.Miradele:BAAALgAECgcJEgAAAA==.Miraxx:BAAALgAECgMJBQAAAA==.Misscleö:BAABLgAECn8iAAIBAAgJ8BL2OACcAQABAAgJ8BL2OACcAQAAAA==.Mistybrew:BAAALgADCgMJAwAAAA==.Miyoshi:BAABLgAECn8bAAIjAAgJyAd/FABsAQAjAAgJyAd/FABsAQAAAA==.Mizrhi:BAAALgAECgEJAQAAAA==.',
Mo='Monthy:BAAALgADCgUJCAAAAA==.Moonkey:BAAALgAECgIJAgAAAA==.Moosakka:BAABLgAECn8oAAMPAAkJ6ReUCwAyAgAPAAgJzBeUCwAyAgAQAAgJ5hA1FgB3AQAAAA==.Moosedluffy:BAAALgAECgYJDgAAAA==.Moosesiah:BAAALgAECgcJEQAAAA==.Moovinthru:BAAALgAECgQJCgAAAA==.Moraxes:BAABLgAECn8kAAMiAAkJLxo8BAB0AgAiAAkJLxo8BAB0AgAgAAUJORVpFgAFAQAAAA==.Mordenkainen:BAAALgAECgUJEwAAAA==.Morenor:BAABLgAECn8VAAINAAYJXAaBPQAIAQANAAYJXAaBPQAIAQAAAA==.Morphidmage:BAABLgAECn8uAAIVAAkJzgwBMADhAQAVAAkJzgwBMADhAQAAAA==.Mortetdabo:BAAALgAECgYJBwAAAA==.Motoko:BAAALgADCggJEwAAAA==.Motolei:BAAALgADCggJCAABLgAECgcJGgAFAAQLAA==.',
Mu='Muaadib:BAAALgADCgkJGQABLgAECgcJGgAFAAQLAA==.',
My='Mydin:BAABLgAECn8hAAIBAAkJEResJADwAQABAAkJEResJADwAQAAAA==.Myordarsh:BAABLgAECn8lAAMLAAgJ1xeXIgD7AQALAAgJ1xeXIgD7AQAcAAYJxgnJHgDLAAAAAA==.',
['Mì']='Mìsawa:BAAALgAECgUJDwAAAA==.',
Na='Nael:BAAALgAECgQJBAAAAA==.Naeleen:BAAALgADCgQJBwAAAA==.Nakai:BAAALgADCgkJGwAAAA==.Nasmage:BAAALgADCgkJCgAAAA==.',
Ne='Nelfgonewild:BAAALgAECgIJAgAAAA==.Nexs:BAAALgAECgcJBwAAAA==.Nexxa:BAABLgAECn8kAAITAAgJphaWHgDkAQATAAgJphaWHgDkAQAAAA==.Neyrina:BAAALgADCgUJCAAAAA==.',
Ni='Nickk:BAAALgAECgkJAQAAAA==.Nightshadow:BAAALgAECgcJEwAAAA==.Niqkle:BAABLgAECn8oAAMdAAkJvBSeDQAEAgAdAAkJvBSeDQAEAgAbAAgJXgjtOQAfAQAAAA==.Nirat:BAAALgADCgEJAQAAAA==.Nishandriel:BAAALgADCgkJDwAAAA==.Nivia:BAAALgAECgYJDgABLgAFFAYJGQAGAC8ZAA==.',
No='Nohurtscooby:BAAALgAECgMJBQAAAA==.Normond:BAAALgADCgUJDAAAAA==.Nosiaria:BAAALgAECgEJAQAAAA==.Notadh:BAAALgAECgYJDQAAAA==.Notmeanzy:BAABLgAECn8uAAMNAAkJvCDrAQAHAwANAAkJvCDrAQAHAwAOAAMJQhZhOwDOAAAAAA==.',
Ns='Nstagatr:BAAALgADCgEJAQAAAA==.',
Nu='Numeroun:BAAALgAECgQJCQAAAA==.Nunbora:BAAALgAECgEJAQAAAA==.',
['Né']='Nécrömancer:BAAALgADCgIJAgAAAA==.',
['Nï']='Nïghtknïght:BAAALgAECgMJAwAAAA==.',
Ol='Oleanna:BAABLgAECn8cAAIQAAcJxg2KHQA3AQAQAAcJxg2KHQA3AQABLgAECgkJMgABAOcZAA==.Olehanna:BAABLgAECn8yAAIBAAkJ5xmwEgBlAgABAAkJ5xmwEgBlAgAAAA==.Olendra:BAAALgAECgcJBwABLgAECgkJMgABAOcZAA==.Olestrid:BAAALgADCgkJEgABLgAECgkJMgABAOcZAA==.',
On='Onyxcaduceus:BAAALgADCgQJBAAAAA==.Onyxtear:BAAALgADCgkJHAAAAA==.',
Op='Opioid:BAABLgAECn8cAAITAAcJsRhUKgCnAQATAAcJsRhUKgCnAQAAAA==.Opsec:BAAALgAECgEJAQABLgAECggJIwAFAF4SAA==.Opsèc:BAABLgAECn8jAAIFAAgJXhJfLgB9AQAFAAgJXhJfLgB9AQAAAA==.',
Or='Orsa:BAABLgAECn8VAAIdAAcJcxQjMACfAQAdAAcJcxQjMACfAQAAAA==.',
Ot='Othon:BAAALgADCgEJAQAAAA==.',
Pe='Pebbles:BAAALgAECgEJAQABLgAECgQJBwASAAAAAA==.Pedren:BAAALgAECgQJDwAAAA==.Perfectpal:BAABLgAECn8eAAMDAAgJPRXVLwDDAQADAAgJPRXVLwDDAQABAAEJ3gckCAE0AAAAAA==.Peri:BAAALgADCgUJBQAAAA==.',
Ph='Phaeseus:BAAALgAECgUJBgAAAA==.Phexaryl:BAAALgAECgUJBgAAAA==.',
Pl='Planette:BAABLgAECn8VAAIbAAgJThD4JACSAQAbAAgJThD4JACSAQAAAA==.',
Po='Poinda:BAAALgADCgIJAgAAAA==.Poisionivy:BAAALgADCgEJAQAAAA==.Popcorners:BAABLgAECn8wAAIOAAkJSB7aBAC9AgAOAAkJSB7aBAC9AgAAAA==.Popopanda:BAAALgAECgUJDwAAAA==.Poppnlok:BAAALgADCgEJAQAAAA==.Pordgio:BAABLgAECn8aAAIjAAgJHg3vFQBbAQAjAAgJHg3vFQBbAQAAAA==.Pozzi:BAAALgAECgMJBwAAAA==.',
Pr='Praypal:BAAALgAECgQJCAAAAA==.Problematiç:BAAALgADCgEJAQAAAA==.Proxxy:BAAALgADCgMJAwAAAA==.',
Ps='Psuedolus:BAABLgAECn8cAAILAAgJciL2EgBkAgALAAgJciL2EgBkAgAAAA==.Psålm:BAAALgAECggJEQAAAA==.',
Pu='Pulshadow:BAACLgAFFH8UAAINAAUJNh/kBQCAAQANAAUJNh/kBQCAAQAuAAQKfyAAAg0ACAkYJDMFAD4DAA0ACAkYJDMFAD4DAAAA.Pumah:BAAALgAECgMJBgAAAA==.Purified:BAAALgAECgIJAgABLgAFFAcJGgACALgTAA==.',
Pw='Pweenqween:BAAALgADCgEJAQAAAA==.',
Py='Pyreska:BAAALgAECgkJDAAAAA==.Pyroklasm:BAABLgAECn8bAAIVAAcJtByAUwA9AgAVAAcJtByAUwA9AgAAAA==.',
Qt='Qthunter:BAAALgADCgkJCQABLgAECggJGwAQAMASAA==.Qtlocks:BAAALgADCgkJCQABLgAECggJGwAQAMASAA==.Qtmonk:BAABLgAECn8bAAIQAAgJwBJIEQCuAQAQAAgJwBJIEQCuAQAAAA==.',
Qu='Quartzecoatl:BAAALgADCgMJAwAAAA==.Quela:BAAALgAECgMJBgAAAA==.Quintcaster:BAAALgAECgQJBgAAAA==.Quirt:BAAALgAECgQJDAAAAA==.',
Ra='Raamen:BAAALgAECgQJBwAAAA==.Rabiéz:BAAALgAECgIJAwAAAA==.Raellia:BAABLgAECn8vAAQHAAkJKRU6JwDKAQAHAAcJ+BM6JwDKAQAIAAMJ/hdVFwCQAAAmAAIJ0hciDwCIAAAAAA==.Raimmey:BAAALgAECgMJBQAAAA==.Rajann:BAAALgADCgMJAwAAAA==.Rajia:BAAALgAECgYJDQABLgAECgcJHwAIAC0QAA==.Rakaw:BAAALgADCgMJAwAAAA==.Ralune:BAABLgAECn8fAAIYAAcJhBC3GwBXAQAYAAcJhBC3GwBXAQAAAA==.Randomdhunte:BAAALgADCgkJDAAAAA==.Randomone:BAAALgAECggJEgAAAA==.Ranes:BAABLgAECn8vAAQjAAkJ3iCxAQD4AgAjAAkJ3iCxAQD4AgAkAAQJuA/IEgDWAAAlAAEJQwdWFAAtAAAAAA==.Rathmore:BAAALgAECgQJBQAAAA==.Raylavoidles:BAAALgADCgcJDgAAAA==.Rayllee:BAAALgAECgcJEAAAAA==.',
Re='Redi:BAAALgADCgYJBgAAAA==.Redxelementz:BAABLgAECn8nAAIbAAkJYiOTAgA0AwAbAAkJYiOTAgA0AwAAAA==.Relyana:BAAALgADCgEJAQAAAA==.Remena:BAABLgAECn8WAAIQAAcJERzdFwAlAgAQAAcJERzdFwAlAgAAAA==.Renasen:BAABLgAECn8WAAMgAAgJqyJhAwBuAgAgAAcJnSNhAwBuAgAhAAcJpRYWHACHAQAAAA==.Reno:BAABLgAECn8hAAMDAAgJhho5CwBeAgADAAgJhho5CwBeAgABAAEJjBJH7gA/AAAAAA==.René:BAAALgADCgUJBwAAAA==.Resiretha:BAABLgAECn8XAAMHAAgJqwNQaAD8AAAHAAgJqwNQaAD8AAAIAAEJBQUWegAoAAAAAA==.Revelynn:BAABLgAECn8oAAIFAAkJHx3BCgB/AgAFAAkJHx3BCgB/AgAAAA==.',
Rh='Rhemedi:BAAALgAECgUJBQAAAA==.Rhico:BAAALgADCgEJAQAAAA==.Rhyin:BAAALgADCgYJBgAAAA==.',
Ri='Riolu:BAAALgAECgQJBgAAAA==.',
Rn='Rngesus:BAAALgAECgEJAQABLgAECggJMwALACAhAA==.',
Ro='Robotmonk:BAAALgAECgUJBQABLgAFFAIJAgASAAAAAA==.Rooxxy:BAAALgAECgcJEAAAAA==.Rotawna:BAAALgAECgYJCQAAAA==.Roxxye:BAAALgADCgEJAQABLgAECgcJEAASAAAAAA==.',
Ru='Rumms:BAAALgAECgcJCwAAAA==.Rustybottom:BAAALgADCgEJAQAAAA==.Ruumis:BAAALgAECgQJBAAAAA==.',
Ry='Rydric:BAABLgAECn8WAAIVAAgJFCPHEwAxAwAVAAgJFCPHEwAxAwAAAA==.Ryezn:BAAALgAECgEJAQAAAA==.Ryxhal:BAAALgADCgYJBgAAAA==.',
['Rï']='Rïnzlër:BAAALgAECgcJEwAAAA==.',
Sa='Saela:BAAALgAECgYJBgAAAA==.Sarac:BAABLgAECn8gAAIiAAgJuAKaGwDfAAAiAAgJuAKaGwDfAAAAAA==.Saratosh:BAAALgADCgEJAQAAAA==.Savira:BAAALgAECgUJCwAAAA==.',
Sc='Scaleorva:BAABLgAECn8aAAMKAAYJEQ/yCAAZAQAKAAYJEQ/yCAAZAQAJAAEJ+wgWXAAyAAAAAA==.',
Se='Selfaware:BAAALgAECgUJBQABLgAECggJFgACAKUZAA==.Seraphìm:BAABLgAECn8bAAIBAAgJzQb7YQAqAQABAAgJzQb7YQAqAQAAAA==.',
Sh='Shadefu:BAAALgADCgYJBgABLgAECgcJHAAZAMAOAA==.Shadyballs:BAABLgAECn8cAAQZAAcJwA6aAwByAQAZAAcJwA6aAwByAQAVAAYJtQhMhgAFAQAnAAUJjwguCQDDAAAAAA==.Shakypete:BAAALgAECgUJCAABLgAECgYJFgAYAHUQAA==.Shalaena:BAAALgAECgMJAwAAAA==.Shamagorn:BAAALgADCgcJBwAAAA==.Shamysosa:BAABLgAECn8dAAMdAAYJKht2GQCDAQAdAAYJKht2GQCDAQAbAAEJ6AOZpQAqAAAAAA==.Shanebentea:BAABLgAECn8hAAIhAAcJjhYoFwCuAQAhAAcJjhYoFwCuAQAAAA==.Sharpy:BAAALgAECgEJAQABLgAECggJIQAVALUZAA==.Sharpyboi:BAAALgADCgMJAwABLgAECggJIQAVALUZAA==.Sharpyy:BAAALgADCgYJBgABLgAECggJIQAVALUZAA==.Shiven:BAAALgAECgMJAwAAAA==.Shmob:BAABLgAECn8VAAIdAAYJ2Q18JAAyAQAdAAYJ2Q18JAAyAQAAAA==.Shnappz:BAABLgAECn8eAAMIAAYJYA6WFQCiAAAHAAUJ1AiVagD3AAAIAAQJmxGWFQCiAAAAAA==.Shockittome:BAAALgADCgUJBQAAAA==.Shroomee:BAABLgAFFH8SAAQEAAkJgwteBgDUAQAEAAcJZwpeBgDUAQAYAAQJkBqVEQAqAQAMAAIJkBTnCACDAAAAAA==.Shwillacus:BAAALgADCgkJCQAAAA==.Shwillarou:BAABLgAECn8vAAILAAkJsQ0NKQDZAQALAAkJsQ0NKQDZAQAAAA==.Shwillmoon:BAAALgADCgkJEgAAAA==.Shärpy:BAABLgAECn8hAAIVAAgJtRkvUwA+AgAVAAgJtRkvUwA+AgAAAA==.',
Si='Silverstring:BAAALgAECgUJDAAAAA==.Simmi:BAAALgAECgIJAgAAAA==.Sinergee:BAABLgAECn8eAAITAAcJmBIcNgB0AQATAAcJmBIcNgB0AQAAAA==.Sinfulgold:BAAALgADCgMJAwAAAA==.Sinfulkitten:BAAALgADCggJEAAAAA==.Sinnj:BAAALgAECgcJEQAAAA==.',
Sk='Skinney:BAAALgAECgIJAwAAAA==.Skinsey:BAAALgADCgcJBwAAAA==.Skycrush:BAAALgAECgQJBwAAAA==.',
Sl='Slanie:BAABLgAECn8eAAIGAAgJ0w9fGgB5AQAGAAgJ0w9fGgB5AQAAAA==.Slingerz:BAABLgAECn8wAAIiAAkJMhYxCAD5AQAiAAkJMhYxCAD5AQAAAA==.Slowmeaux:BAAALgADCgYJCgAAAA==.',
Sm='Smoky:BAABLgAECn8bAAQHAAkJZSA9OwAfAgAHAAcJMyA9OwAfAgAIAAMJPB+9LAALAQAmAAEJAACTIgBnAAAAAA==.',
Sn='Snacky:BAAALgADCgIJAgAAAA==.Sneakpastya:BAABLgAECn8hAAIjAAgJEwfdEwBzAQAjAAgJEwfdEwBzAQAAAA==.Sneakyg:BAAALgAECgEJAQABLgAECggJGwABAPIZAA==.Snooksdk:BAAALgADCgEJAQABLgAFFAYJFgAVAAAbAA==.',
So='Solkar:BAAALgAECgcJEgAAAA==.Sollis:BAAALgAECgMJCAAAAA==.Sonastii:BAABLgAECn8cAAIdAAgJbx3XCABOAgAdAAgJbx3XCABOAgAAAA==.Soulbztrd:BAABLgAECn8gAAMIAAkJ+BZtGgB5AQAIAAUJIRptGgB5AQAHAAcJBxQuTABFAQAAAA==.Soulpepper:BAAALgAECgQJBAAAAA==.Soulreaper:BAAALgAECgYJBgABLgAECgYJBgASAAAAAA==.Soulsnatcher:BAAALgAECgYJBgAAAA==.',
Sp='Spazzchel:BAAALgAECgQJBwAAAA==.Spinmedaddy:BAAALgADCggJCAABLgAECggJKQAPAP8YAA==.Spruce:BAAALgADCgkJGwAAAA==.',
St='Stahlman:BAABLgAECn8vAAIbAAkJcRyaCgCDAgAbAAkJcRyaCgCDAgAAAA==.Stalpho:BAABLgAECn8iAAIhAAgJEBHHFgCxAQAhAAgJEBHHFgCxAQAAAA==.Starflare:BAAALgADCgkJIgABLgAECgcJHwAbADQHAA==.Starkind:BAABLgAECn8fAAIbAAcJNAfLPAASAQAbAAcJNAfLPAASAQAAAA==.Stefussy:BAAALgADCgIJAgAAAA==.Stonefist:BAAALgAECgYJEAABLgAECgYJHQAdACobAA==.Stoutmist:BAAALgAECgEJAQAAAA==.Sturr:BAAALgAECgEJAQAAAA==.Styrke:BAAALgAECgIJAgAAAA==.',
Su='Subza:BAAALgADCgMJAwAAAA==.Sundalo:BAAALgAECgUJCAAAAA==.Supergood:BAAALgAECgYJBgAAAA==.Superjoyful:BAAALgADCgEJAQAAAA==.Supersweet:BAAALgADCgYJEQAAAA==.Sutterkain:BAAALgAECgMJBAAAAA==.',
Sw='Swagadin:BAABLgAECn8pAAIBAAkJ1SRVBwBdAwABAAkJ1SRVBwBdAwAAAA==.Swagika:BAAALgAECgQJBAABLgAECgkJKQABANUkAA==.',
Sy='Syine:BAAALgADCgUJBQAAAA==.Sylee:BAABLgAFFH8GAAIPAAMJRBvcFQDXAAAPAAMJRBvcFQDXAAAAAA==.',
Ta='Tabitia:BAABLgAECn8iAAMTAAkJ7RHGHQDqAQATAAkJpw/GHQDqAQAXAAYJnhL4FAB4AQAAAA==.Taladari:BAAALgADCgEJAQAAAA==.Taliss:BAAALgAECgYJEAAAAA==.Talonpepper:BAAALgADCgMJAwAAAA==.Tankmedaddy:BAABLgAECn8pAAMPAAgJ/xj1CgA8AgAPAAgJ/xj1CgA8AgAQAAEJawP7hwAoAAAAAA==.Tankopotamus:BAAALgADCgEJAQAAAA==.Tapenga:BAAALgAECgQJBAAAAA==.Tappuccino:BAAALgAECgQJCgAAAA==.Taras:BAACLgAFFH8LAAIhAAMJWiF/EQAoAQAhAAMJWiF/EQAoAQAuAAQKfxwAAiEACQkGIPEHACsDACEACQkGIPEHACsDAAAA.Taraxist:BAABLgAECn8oAAIIAAgJghzYAQBPAgAIAAgJghzYAQBPAgAAAA==.Tarcanisdk:BAABLgAECn8gAAILAAgJ3hhYIgD8AQALAAgJ3hhYIgD8AQAAAA==.Tasuma:BAAALgAECgYJDAAAAA==.Tautology:BAABLgAECn8fAAINAAgJIBgMEADPAQANAAgJIBgMEADPAQAAAA==.Tazdingo:BAAALgADCgEJAQAAAA==.',
Tc='Tchala:BAABLgAECn8bAAIBAAgJ8hmCfACBAQABAAgJ8hmCfACBAQAAAA==.Tchaumb:BAAALgADCgkJBgAAAA==.',
Te='Tedeschi:BAAALgAECgEJAgAAAA==.Teks:BAABLgAECn8oAAIDAAgJnh0tBgC9AgADAAgJnh0tBgC9AgAAAA==.Teksakah:BAAALgADCggJCAABLgAECggJKAADAJ4dAA==.Teksara:BAAALgADCgcJBwABLgAECggJKAADAJ4dAA==.Tekszen:BAAALgADCgEJAQABLgAECggJKAADAJ4dAA==.Tencup:BAABLgAECn8WAAICAAgJpRlRCwANAgACAAgJpRlRCwANAgAAAA==.Teth:BAABLgAECn8dAAMIAAgJQBMRBQCxAQAIAAgJQBMRBQCxAQAHAAEJuQFS8AAgAAAAAA==.Tetsuyo:BAAALgAECgQJBwAAAA==.',
Th='Thaine:BAABLgAECn8wAAIBAAkJtSTfAgAwAwABAAkJtSTfAgAwAwAAAA==.Theelvira:BAAALgADCgYJBgAAAA==.Theoalthor:BAAALgADCgYJFAAAAA==.Theresis:BAAALgAECgMJBAAAAA==.Therkadin:BAAALgAECgUJDQAAAA==.Theundeadone:BAAALgAECgYJCAAAAA==.Thndrwzrd:BAAALgAECgUJDwAAAA==.Thrust:BAAALgADCgIJAgAAAA==.',
Ti='Ticho:BAABLgAECn8kAAILAAkJLAYERQBtAQALAAkJLAYERQBtAQAAAA==.Tidel:BAAALgADCgMJAwAAAA==.Tindmina:BAABLgAECn8bAAIDAAcJuhmBIACDAQADAAcJuhmBIACDAQAAAA==.Tinglekin:BAAALgAECgIJAwAAAA==.',
Tl='Tlo:BAAALgAECgcJDgAAAA==.Tlol:BAAALgAECgUJBwABLgAECgcJDgASAAAAAA==.',
To='Toenails:BAAALgADCgYJBgAAAA==.Topflight:BAAALgAECgEJAQABLgAECgYJCAASAAAAAA==.Torkkit:BAAALgAECgEJAgABLgAECgUJBgASAAAAAA==.Torodisilis:BAAALgAECgIJAgABLgAECggJGwABAPIZAA==.Torqit:BAAALgAECgMJBQABLgAECgUJBgASAAAAAA==.Totemdude:BAAALgADCgEJAQAAAA==.Totemzrus:BAAALgAECgcJEgAAAA==.',
Tr='Trath:BAAALgADCgMJAwAAAA==.Trent:BAAALgADCgQJCAAAAA==.Trickette:BAAALgAECggJAwAAAA==.Trickeye:BAAALgADCgIJAgAAAA==.',
Tw='Twicks:BAABLgAFFH8KAAQQAAUJpAznAgB8AQAQAAUJkwjnAgB8AQAPAAQJOAKDFQDdAAACAAEJfRgfOQBKAAAAAA==.',
Ud='Udderlyquiff:BAAALgAECgIJAgAAAA==.Udderlyslow:BAABLgAECn8eAAIbAAcJByGcGwA7AgAbAAcJByGcGwA7AgAAAA==.',
Ug='Uglyloser:BAAALgAECgIJAwAAAA==.',
Un='Undeez:BAAALgAECgMJAwAAAA==.Unluckyfrien:BAAALgAECgIJAgAAAA==.',
Va='Vaeshta:BAABLgAECn8YAAIUAAcJHAN0EQDoAAAUAAcJHAN0EQDoAAAAAA==.Vaku:BAAALgADCgkJDQAAAA==.Valhallarama:BAABLgAECn8WAAIbAAcJhwq6QQD8AAAbAAcJhwq6QQD8AAAAAA==.Vampy:BAABLgAECn8XAAIWAAcJuRKHCAB3AQAWAAcJuRKHCAB3AQAAAA==.Vannida:BAAALgAECgUJBQAAAA==.Vanìlla:BAAALgADCgEJAQAAAA==.Varya:BAAALgAECgYJDAAAAA==.Vasuvious:BAABLgAECn8iAAICAAcJDR2YHgANAgACAAcJDR2YHgANAgAAAA==.',
Ve='Vesstara:BAAALgADCgUJDwABLgAECgMJBQASAAAAAA==.',
Vi='Vinago:BAAALgAECgMJAwAAAA==.',
Vo='Voidabyss:BAAALgADCgUJBQAAAA==.Voidixx:BAAALgADCggJEwAAAA==.Voodoo:BAAALgAECgIJBAAAAA==.',
Vy='Vyleta:BAAALgADCgYJBgAAAA==.Vyllian:BAABLgAECn8zAAMLAAgJICG1FABVAgALAAgJ/x+1FABVAgAcAAcJjA0gFwAXAQAAAA==.Vyri:BAAALgAECgEJAQAAAA==.',
['Vá']='Váz:BAAALgADCgYJBgABLgAFFAMJBgAEAOELAA==.',
Wa='Wangwang:BAAALgAECgQJCgAAAA==.Warlakaflaka:BAAALgAECgMJBAABLgAECgcJHAAZAMAOAA==.Warlboro:BAACLgAFFH8TAAIHAAYJ4A0bGABUAQAHAAYJ4A0bGABUAQAuAAQKfyUABAcACAlwHBEfAJ0CAAcACAlwHBEfAJ0CAAgABAnvClo1AOEAACYAAQnBIB0oAFEAAAAA.',
We='Welikeweed:BAAALgAECgUJBgABLgAECggJGwAbAM8dAA==.',
Wh='Whale:BAABLgAECn8dAAIiAAkJ3RnPCADrAQAiAAkJ3RnPCADrAQAAAA==.Whine:BAAALgAECgQJBwAAAA==.',
Wi='Wibbers:BAAALgAECgEJAgAAAA==.Wicked:BAABLgAECn8XAAIBAAUJliDQSwBiAQABAAUJliDQSwBiAQABLgAECgcJCgASAAAAAA==.Willôw:BAAALgADCgkJEQABLgAECggJFwAGAHUfAA==.Windwalker:BAABLgAECn8ZAAIQAAgJWBFsEwCYAQAQAAgJWBFsEwCYAQAAAA==.Winkey:BAAALgADCgYJBgAAAA==.Winston:BAAALgADCgYJBwAAAA==.',
Wo='Wolfsong:BAAALgADCgMJBAABLgAECgQJBgASAAAAAA==.Woosaah:BAAALgAECgcJBwAAAA==.',
Wr='Wreckyou:BAABLgAECn8WAAQmAAYJXA8ECgDvAAAHAAYJ/wcAqwADAQAIAAYJxgYtMgDwAAAmAAUJmw4ECgDvAAAAAA==.',
Wt='Wtfimkorgak:BAABLgAECn8jAAIGAAcJfCM+BgCXAgAGAAcJfCM+BgCXAgAAAA==.',
Wy='Wy:BAAALgADCgYJBgAAAA==.Wylestrean:BAABLgAECn8oAAMXAAgJZRzJEQCUAQAXAAYJVx7JEQCUAQATAAMJWBhChQCJAAAAAA==.',
Xa='Xandoriel:BAAALgADCgQJBAAAAA==.',
Xy='Xyrathul:BAAALgAECgEJAQAAAA==.',
Ye='Yeahigotmilk:BAAALgADCgUJBQAAAA==.Yellowgoblin:BAAALgAECgIJAgAAAA==.',
Yo='Yopali:BAAALgAECgIJAwAAAA==.',
Yu='Yugiohrox:BAABLgAECn8cAAIcAAgJOR2BCwBbAgAcAAgJOR2BCwBbAgAAAA==.Yujology:BAABLgAECn8fAAIaAAgJEAThDQDjAAAaAAgJEAThDQDjAAAAAA==.',
Ze='Zel:BAAALgAECgUJDwAAAA==.Zentradei:BAAALgAECgQJCgAAAA==.Zephirothh:BAAALgADCgcJFwAAAA==.',
Zi='Zieganfuss:BAABLgAECn8XAAIVAAcJ5R/6VAA5AgAVAAcJ5R/6VAA5AgAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zimmy:BAAALgADCgYJBgAAAA==.',
Zo='Zoho:BAABLgAECn8WAAICAAYJoBVfIgAnAQACAAYJoBVfIgAnAQAAAA==.Zoomies:BAAALgADCgMJAwAAAA==.',
Zu='Zulkai:BAABLgAECn8gAAIEAAgJ+RRrIgCzAQAEAAgJ+RRrIgCzAQAAAA==.',
Zy='Zynvar:BAAALgADCgYJBgAAAA==.',
['Zá']='Záv:BAACLgAFFH8GAAIEAAMJ4QtHJADEAAAEAAMJ4QtHJADEAAAuAAQKfxgAAwQACAlyFzAnABkCAAQACAlyFzAnABkCACgAAgkxCgIdAHMAAAAA.',
['Zä']='Zäne:BAABLgAECn8ZAAIVAAYJHxo7jQC4AQAVAAYJHxo7jQC4AQAAAA==.',
['Çl']='Çlù:BAAALgAECgYJBwAAAA==.',
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

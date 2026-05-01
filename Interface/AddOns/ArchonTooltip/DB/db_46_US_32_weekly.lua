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

local lookup = {'Monk-Brewmaster','Druid-Restoration','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Priest-Holy','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Paladin-Holy','Hunter-Survival','Druid-Balance','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Warlock-Affliction','Mage-Fire','Druid-Feral',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abadacalama:BAAALgAECgcJDQAAAA==.',
Ad='Adera:BAAALgADCgEJAQAAAA==.',
Ae='Aellee:BAAALgAECgQJCAAAAA==.Aeninas:BAABLgAECn8VAAIBAAYJtxgKFABlAQABAAYJtxgKFABlAQAAAA==.Aeris:BAAALgADCgEJAQAAAA==.Aerynn:BAAALgADCgIJAgAAAA==.Aethwyn:BAAALgAECgcJBwAAAA==.',
Af='Afflictions:BAAALgADCgUJBQAAAA==.',
Ag='Agandaur:BAAALgAECgEJAQAAAA==.',
Ah='Ahnkala:BAAALgAECgMJCAAAAA==.Ahzi:BAABLgAECn8dAAICAAgJyRypCACAAgACAAgJyRypCACAAgAAAA==.Ahzii:BAAALgADCgYJBwAAAA==.',
Ai='Aigirlfriend:BAABLgAECn8eAAIDAAgJJAqRLAAyAQADAAgJJAqRLAAyAQAAAA==.Ains:BAAALgAECggJCAAAAA==.Airsia:BAAALgADCgYJBgAAAA==.',
Ak='Akro:BAAALgADCgEJAQAAAA==.',
Al='Allupcreepy:BAAALgAECgYJEwAAAA==.Alphaandy:BAAALgAECgMJAwAAAA==.Alphaboy:BAAALgADCgcJBwAAAA==.Alphaxdruid:BAAALgAECgMJAwAAAA==.Alphaxsham:BAAALgADCgIJAgAAAA==.Alysara:BAAALgAECgMJAwAAAA==.',
Am='Ambewlance:BAABLgAECn8XAAMEAAgJXA5SKACNAQAEAAgJOA5SKACNAQAFAAMJRA5yQQCvAAAAAA==.Ambrosious:BAAALgAECgEJAQAAAA==.Amethystra:BAABLgAECn8gAAMGAAgJFQ7sEgBuAQAGAAgJFQ7sEgBuAQAHAAMJwwaRMgCBAAAAAA==.Amâlynd:BAABLgAECn8XAAICAAgJqwXzPADdAAACAAgJqwXzPADdAAAAAA==.',
An='Anastasiaro:BAAALgADCgEJAQAAAA==.Annimosity:BAAALgAECgIJAwAAAA==.Ansem:BAAALgADCgUJBgAAAA==.Anthesis:BAACLgAFFH8FAAICAAIJRBpYHwCnAAACAAIJRBpYHwCnAAAuAAQKfx4AAgIACAmgGcQMADwCAAIACAmgGcQMADwCAAAA.Anthonor:BAAALgAECgYJCAAAAA==.Anubrian:BAAALgAECgYJEQAAAA==.Anúbis:BAAALgAECgMJCAAAAA==.',
Ap='Apawllo:BAABLgAECn8hAAIIAAgJxRX0DAC5AQAIAAgJxRX0DAC5AQAAAA==.Apep:BAAALgAECgQJCwAAAA==.Apostle:BAACLgAFFH8TAAIJAAYJGxhFAQDYAQAJAAYJGxhFAQDYAQAuAAQKfyYAAgkACAmCI9wGAOACAAkACAmCI9wGAOACAAAA.',
Ar='Aramìs:BAAALgADCgYJBgAAAA==.Aryto:BAABLgAECn8XAAMKAAcJmhgKCwDPAQAKAAcJmhgKCwDPAQALAAEJOgXIWgAtAAAAAA==.',
As='Ashlar:BAAALgADCgUJBQAAAA==.Asketill:BAAALgAFFAIJAwAAAA==.Astora:BAAALgADCgcJBwABLgAECggJEwAMAAAAAA==.',
At='Ativan:BAEBLgAECn8cAAQNAAcJuxVREACkAQANAAcJuxVREACkAQAOAAMJuAecLQCTAAABAAEJcwBiXwAaAAAAAA==.',
Au='Auluras:BAAALgADCgUJBQAAAA==.',
Av='Avitus:BAAALgADCgIJBAAAAA==.',
Ay='Aylari:BAABLgAECn8mAAMPAAkJDyRyCACUAgAPAAkJ/SNyCACUAgAQAAYJ+ReWEgCgAQAAAA==.',
Az='Azonya:BAAALgADCgEJAgAAAA==.Azuth:BAAALgADCgMJAwAAAA==.',
Ba='Bachren:BAAALgAECgYJCgAAAA==.Badil:BAAALgADCgIJAgAAAA==.Baitken:BAAALgAECgYJEAABLgAECgYJFQABALcYAA==.Batharel:BAABLgAECn8cAAIRAAcJzRYgMgDnAQARAAcJzRYgMgDnAQAAAA==.',
Bd='Bdrone:BAAALgADCgYJCAAAAA==.',
Be='Bearen:BAABLgAECn8fAAISAAcJEQqxFQBiAQASAAcJEQqxFQBiAQAAAA==.Bedazzle:BAAALgADCgcJBwABLgAFFAYJEwAJABsYAQ==.Beefo:BAAALgADCgUJBAAAAA==.Beemz:BAAALgAECgcJEwAAAA==.Beertrain:BAABLgAECn8eAAITAAgJaBYgWADpAQATAAgJaBYgWADpAQAAAA==.Beesechurger:BAABLgAECn8gAAIUAAgJZBy2EABXAgAUAAgJZBy2EABXAgAAAA==.Bekindrewind:BAABLgAECn8YAAIGAAgJsBaBIAC8AQAGAAgJsBaBIAC8AQAAAA==.Belladonia:BAAALgADCgcJBwABLgAECgkJJwACAPYTAA==.Belladue:BAAALgADCgMJBgAAAA==.Bellezza:BAABLgAECn8nAAICAAkJ9hM6KAAUAgACAAkJ9hM6KAAUAgAAAA==.Bex:BAAALgADCgEJAQAAAA==.',
Bh='Bheef:BAAALgADCgMJAwAAAA==.',
Bi='Bigdisc:BAAALgADCgIJAgABLgAECgMJAwAMAAAAAA==.Bigdumbcatqt:BAABLgAECn8gAAIQAAkJzCZaAACfAwAQAAkJzCZaAACfAwAAAA==.Bignjuicy:BAAALgADCgcJBwAAAA==.',
Bl='Blinkk:BAAALgADCgEJAgABLgADCgMJAwAMAAAAAA==.Bloodeagle:BAAALgADCgcJBwAAAA==.Bloodshhot:BAABLgAECn8gAAMRAAgJJA8cPgC2AQARAAcJHBEcPgC2AQAVAAEJVANVjgAsAAAAAA==.Bludgen:BAAALgAECgEJAQABLgAECgcJGQALAF4bAA==.',
Bo='Bobitt:BAAALgAECgUJCgAAAA==.Boddyknocker:BAAALgAECgYJCgAAAA==.Boinkusan:BAABLgAECn8cAAINAAgJEiKTDQB7AgANAAgJEiKTDQB7AgAAAA==.Bolthar:BAAALgAECgYJEwAAAA==.Bonkler:BAABLgAECn8fAAMFAAcJVxxSEgC5AQAFAAYJyhlSEgC5AQAEAAcJbxf7HwC1AQAAAA==.Boombox:BAAALgAECgYJDQAAAA==.Boomwand:BAAALgAECgUJCQABLgAECggJHgAWABscAA==.Boonerichard:BAAALgAECgQJBwAAAA==.Bootysweatz:BAAALgADCgcJCQAAAA==.Bouchewager:BAAALgADCgYJBwAAAA==.',
Br='Braina:BAAALgAECgQJBwAAAA==.Braver:BAACLgAFFH8MAAMXAAUJWQxOBgA7AQAXAAUJpghOBgA7AQAVAAQJvgqGEQAgAQAuAAQKfysAAxUACQnFHyIJAAwDABUACQnFHyIJAAwDABcAAgmoBQ4kAHkAAAAA.Braverwar:BAAALgAECgYJDAABLgAFFAUJDAAXAFkMAA==.Brayedine:BAAALgAECgcJDAAAAA==.Break:BAACLgAFFH8LAAIPAAUJmSQVAwCwAQAPAAUJmSQVAwCwAQAuAAQKfxsAAg8ACQm1JY4BAMwDAA8ACQm1JY4BAMwDAAEuAAUUBQkLAA8AmSQA.Breekachu:BAAALgADCgYJBgAAAA==.Brodin:BAAALgADCgEJAQAAAA==.Brohymn:BAAALgADCgEJAQAAAA==.Bromaldehyde:BAAALgADCgIJAgAAAA==.Brooké:BAAALgADCgEJAQAAAA==.Bruj:BAAALgADCgcJAQAAAA==.',
Bu='Bubblebutt:BAAALgADCgEJAQAAAA==.Bubbledis:BAAALgAECgQJDAABLgAECgcJFgAOAJwPAA==.Bullfury:BAAALgADCgEJAQAAAA==.',
['Bù']='Bùbbles:BAAALgAECgMJAwAAAA==.',
Ca='Cadelsaya:BAABLgAECn8nAAMWAAkJvA0lNACtAQAWAAkJvA0lNACtAQAPAAIJHAIeKwFLAAAAAA==.Caletha:BAABLgAECn8WAAMJAAYJSRsUKQCpAQAJAAYJ5RgUKQCpAQALAAUJRBejIgB/AQAAAA==.Calimaria:BAAALgADCgMJBQAAAA==.Calixte:BAAALgAECgYJCgAAAA==.Cammandzar:BAAALgAECgYJCQABLgAECgUJBQAMAAAAAA==.Canman:BAAALgAECgIJAwAAAA==.Cardeller:BAAALgADCgUJCAAAAA==.Cassei:BAACLgAFFH8GAAIWAAMJpg0oEwDZAAAWAAMJpg0oEwDZAAAuAAQKfzkAAxYACAm1HxwNALACABYACAm1HxwNALACAA8ABAmKDBF6ALkAAAAA.',
Ce='Celenia:BAAALgAECgQJCgAAAA==.Celorious:BAAALgAECgcJDwAAAA==.',
Ch='Chainari:BAAALgAECgQJCQAAAA==.Chassis:BAAALgADCgcJCAABLgAECgUJDgAMAAAAAA==.Chawìzawd:BAAALgADCgYJBgAAAA==.Chee:BAAALgAECgEJAgAAAA==.Cheechychong:BAAALgAECgEJAQAAAA==.Cheeksdakota:BAAALgADCgYJBgAAAA==.Cheetopaly:BAABLgAECn8VAAMWAAgJfh2JSwBKAQAWAAUJeB2JSwBKAQAPAAcJEwr5YQDvAAAAAA==.Cherrycrush:BAAALgAECgMJAwAAAA==.Chummy:BAABLgAECn8bAAIYAAkJqA5CCwDbAQAYAAkJqA5CCwDbAQAAAA==.Chìgusa:BAABLgAECn8hAAIJAAgJ9BTDHgDpAQAJAAgJ9BTDHgDpAQAAAA==.',
Ci='Cigarette:BAAALgAECgUJEAAAAA==.Cilenzer:BAAALgAECgEJAgABLgAECgYJEwAMAAAAAA==.Cinadra:BAAALgAECgQJBAAAAA==.Circa:BAAALgADCgUJBwAAAA==.',
Cl='Clumonk:BAABLgAECn8aAAIOAAgJoxv+BgAaAgAOAAgJoxv+BgAaAgAAAA==.',
Co='Convoke:BAAALgAECgcJCgABLgAFFAYJEwAJABsYAA==.Coosedaplug:BAAALgADCgEJAQABLgAECgcJCgAMAAAAAA==.Coosey:BAAALgAECgcJCgAAAA==.Coosicle:BAAALgAECgIJAgABLgAECgcJCgAMAAAAAA==.Coredron:BAAALgAECgMJBAAAAA==.Corellon:BAABLgAECn8ZAAIPAAYJMxAbVAASAQAPAAYJMxAbVAASAQAAAA==.Corinth:BAABLgAECn8hAAIZAAgJMR0lAgCGAgAZAAgJMR0lAgCGAgAAAA==.',
Cr='Cratoz:BAAALgAECgYJCAAAAA==.Craylic:BAAALgADCgkJDgAAAA==.Creepi:BAAALgAECgQJBgAAAA==.Criah:BAAALgADCggJCQAAAA==.Crixhs:BAAALgADCgUJBQAAAA==.Crossgideon:BAABLgAECn8UAAIDAAcJCgstOwD4AAADAAcJCgstOwD4AAAAAA==.Crossword:BAAALgADCgcJBwAAAA==.Croswind:BAAALgADCgUJBQABLgAECgcJFAADAAoLAA==.',
Cu='Curandero:BAAALgADCgcJDwABLgAECgIJAwAMAAAAAA==.Currah:BAAALgAECgEJAQAAAA==.',
Cy='Cyndrine:BAABLgAECn8nAAIaAAkJVyQjAABOAwAaAAkJVyQjAABOAwAAAA==.Cyrani:BAAALgADCgcJBwAAAA==.Cyrcyn:BAAALgAECggJCAAAAA==.',
Da='Dadipps:BAAALgAECgcJEQAAAA==.Daggumit:BAAALgADCgYJBwAAAA==.Dagnei:BAAALgAECgIJAgAAAA==.Daltina:BAAALgAECgYJDAAAAA==.Dannyboone:BAAALgADCgEJAQAAAA==.Darg:BAABLgAECn8VAAMbAAcJhxaoCQB7AQAbAAcJdxWoCQB7AQATAAMJORUN5gC0AAAAAA==.Daurgoth:BAAALgADCgEJAQAAAA==.',
Dd='Ddream:BAAALgADCgMJAwAAAA==.',
De='Deathpuma:BAABLgAECn8UAAIbAAYJKx1TCgBtAQAbAAYJKx1TCgBtAQAAAA==.Deathrowe:BAABLgAECn8gAAITAAcJVR7ZFwD8AQATAAcJVR7ZFwD8AQAAAA==.Deelyte:BAAALgAECgQJBAAAAA==.Deezenuts:BAAALgADCgMJAwAAAA==.Delorayne:BAAALgADCgcJCAAAAA==.Demonic:BAAALgADCgcJDAAAAA==.Demonponii:BAAALgAECgMJAwAAAA==.Demonvann:BAAALgADCgkJEwAAAA==.Denouncer:BAABLgAECn8eAAMWAAgJGxz3FwCQAQAWAAcJhxv3FwCQAQAPAAYJihLkVwAIAQAAAA==.Deralth:BAAALgAECgMJAwAAAA==.Derca:BAAALgAECgUJCwAAAA==.Dercadin:BAAALgADCgYJBgAAAA==.Dethman:BAAALgAECgQJBwAAAA==.Devoider:BAAALgAECgIJAgAAAA==.',
Di='Diddyknight:BAACLgAFFH8FAAIbAAMJyw/TDQDFAAAbAAMJyw/TDQDFAAAuAAQKfyQAAxsACAmMEY8WAKwBABsACAmMEY8WAKwBABMAAgmABraXAGYAAAAA.Diddyrox:BAAALgADCgkJCAABLgAECggJGwAbAAgdAA==.Dienne:BAEALgAECggJEgABLgAECgkJHAANALsVAA==.Diminish:BAAALgAECgQJCAABLgAECgcJCgAMAAAAAA==.Diminutive:BAAALgADCgEJAQAAAA==.Dinarra:BAAALgADCgMJBAAAAA==.Diosdelaluna:BAAALgAECgEJAQAAAA==.Dipity:BAAALgADCgYJBgAAAA==.Discobirb:BAABLgAECn8kAAMEAAgJVBglGwDSAQAEAAcJ2hglGwDSAQAFAAMJEBTpEwCBAAAAAA==.',
Do='Docdrood:BAAALgADCgMJAwAAAA==.Dohdag:BAAALgADCgEJAQAAAA==.Dokkyun:BAAALgADCgEJAwAAAA==.Donlazul:BAABLgAECn8cAAMcAAgJGRwiHwAlAgAcAAgJGRwiHwAlAgAdAAUJAg5VKgDbAAAAAA==.Dorff:BAABLgAECn8cAAMFAAgJFBMRFQCiAQAFAAYJjBURFQCiAQAEAAgJ5gzmJQCYAQAAAA==.Dotlotto:BAAALgAECgcJEwAAAA==.',
Dr='Draconoth:BAABLgAECn8UAAITAAYJsw3GSwAcAQATAAYJsw3GSwAcAQAAAA==.Dragonare:BAAALgAECgYJBgABLgAECggJGwAbAAgdAA==.Dragonir:BAAALgAECgQJCwABLgAECggJFwAPAKoZAA==.Dranddrand:BAABLgAECn8XAAIBAAkJ5Rp4EwB1AgABAAkJ5Rp4EwB1AgAAAA==.Dreadborn:BAAALgADCgYJCAAAAA==.Dreadform:BAAALgADCgcJCwAAAA==.Drizit:BAAALgAECgQJBQAAAA==.Drunkardd:BAAALgADCgYJBgAAAA==.',
Du='Dumbbear:BAAALgADCgcJCgAAAA==.Dungard:BAAALgADCgcJBwABLgAECgkJJwAWALwNAA==.',
Dy='Dyami:BAAALgADCgkJCQAAAA==.',
['Dè']='Dèadèyè:BAAALgADCgEJAQAAAA==.',
Ea='Earthkorra:BAAALgADCgEJAQAAAA==.Eatmorechkn:BAABLgAECn8VAAIPAAgJvhDtpwAxAQAPAAgJvhDtpwAxAQAAAA==.',
Ed='Edgli:BAAALgAECgQJBAAAAA==.Edlania:BAAALgAECgEJAQAAAA==.',
Ee='Eellonwy:BAAALgAECgMJBwAAAA==.Eemerald:BAAALgAECgQJBwAAAA==.',
Eg='Egna:BAABLgAECn8hAAIdAAgJfxG9EwB8AQAdAAgJfxG9EwB8AQAAAA==.',
El='Eldiablo:BAABLgAECn8mAAITAAgJLCAxCwByAgATAAgJLCAxCwByAgAAAA==.Elfshots:BAAALgADCgQJBAABLgAECgcJFgAOAJwPAA==.Elizaa:BAABLgAECn8bAAMcAAgJYQloXwAOAQAcAAcJZwdoXwAOAQAdAAcJBwefLADPAAAAAA==.Ellemeno:BAAALgADCgUJBQAAAA==.Eloria:BAAALgADCgIJAgAAAA==.',
Em='Emmadar:BAAALgADCgkJEgABLgAECggJJgAFAAIWAA==.',
En='Ennoa:BAAALgAECgIJAgAAAA==.',
Er='Eric:BAAALgAECgYJCQAAAA==.Erinn:BAAALgADCgcJCAAAAA==.Erioch:BAAALgAECgEJAQAAAA==.',
Et='Etoya:BAAALgAECgMJAwAAAA==.',
Ex='Execute:BAAALgADCgYJBwAAAA==.',
Ez='Ezykeil:BAAALgADCgYJBgAAAA==.',
Fe='Feelinbetter:BAAALgAECgEJAgAAAA==.Fenrigaar:BAABLgAECn8YAAIYAAcJlBa4EgB0AQAYAAcJlBa4EgB0AQAAAA==.',
Fi='Fillin:BAAALgAECgIJAwAAAA==.Filô:BAACLgAFFH8FAAIKAAMJ2w+4DQDrAAAKAAMJ2w+4DQDrAAAuAAQKfxgAAgoACQkQHioCALsCAAoACQkQHioCALsCAAAA.',
Fj='Fjörd:BAAALgAECgEJAgAAAA==.',
Fl='Flanker:BAAALgADCgUJBQABLgAECggJIAAUAGQcAA==.Flashbang:BAAALgADCgYJBgABLgAECgcJIAADABAUAA==.Flasherdemon:BAAALgAECgYJBgAAAA==.Flashoblight:BAAALgADCgYJDAABLgADCgkJDgAMAAAAAA==.',
Fo='Forsakenly:BAABLgAECn8gAAIRAAgJ7RVDFgDgAQARAAgJ7RVDFgDgAQAAAA==.',
Fr='Frasti:BAAALgAECgIJAwAAAA==.Freshstart:BAAALgAECgYJCQAAAA==.Frostmage:BAABLgAECn8mAAIUAAgJPx6CDwBhAgAUAAgJPx6CDwBhAgAAAA==.',
Fu='Fuegoblazeit:BAAALgAECgIJAwAAAA==.Fuhsrodah:BAAALgADCgEJAgAAAA==.Fulgure:BAABLgAECn8hAAIdAAgJSBtHIwD2AQAdAAgJSBtHIwD2AQAAAA==.Furbucket:BAABLgAECn8WAAMYAAcJAwkLUwDaAAAYAAYJYQcLUwDaAAACAAQJLwjekQCsAAAAAA==.Futon:BAAALgAECgQJBAAAAA==.Futonhunts:BAABLgAECn8jAAIRAAkJdCANCQADAwARAAkJdCANCQADAwAAAA==.Fuzzynutz:BAAALgADCgIJAQAAAA==.',
Fy='Fylerw:BAAALgAECggJEQAAAA==.',
['Få']='Fåe:BAAALgAECgMJBAAAAA==.',
Ga='Gagoogamesh:BAABLgAECn8ZAAMeAAkJ5wuzBABZAQAeAAkJ5wuzBABZAQAbAAEJWgCbUAASAAAAAA==.Gailyn:BAAALgADCgYJCwAAAA==.Galaxyshot:BAAALgADCgcJDAAAAA==.Garhiakitten:BAAALgADCgkJCQAAAA==.',
Ge='Gendershift:BAAALgADCgQJBAAAAA==.Getpsalm:BAAALgAECgkJBwAAAA==.',
Gh='Ghimpy:BAAALgAECgMJCAAAAA==.Ghostrideher:BAABLgAECn8cAAIRAAgJjh2HEQAIAgARAAgJjh2HEQAIAgAAAA==.',
Gi='Gigadad:BAAALgAECgMJAwAAAA==.Gigafather:BAAALgAECgMJBAAAAA==.',
Go='Goochkiss:BAAALgAECgMJAwAAAA==.',
Gr='Griannee:BAABLgAECn8gAAIfAAgJnxkFBgAFAgAfAAgJnxkFBgAFAgAAAA==.Grimborn:BAAALgAECgIJAgAAAA==.Gripmedaddy:BAAALgADCgEJAQABLgAECggJIQANAAkUAA==.Grisdrips:BAAALgAECgQJBQAAAA==.Grislix:BAABLgAECn8dAAMEAAgJzhP3KQCGAQAEAAgJzhP3KQCGAQAFAAEJkQVsJAAjAAABLgAECgQJBQAMAAAAAA==.Gryffin:BAABLgAECn8gAAIUAAgJlw/+MwCVAQAUAAgJlw/+MwCVAQAAAA==.',
Gu='Gurrth:BAAALgADCgMJAwAAAA==.',
['Gâ']='Gânk:BAABLgAECn8hAAMgAAgJfAibEwBsAQAgAAgJfAibEwBsAQAhAAIJmQJKnQBKAAAAAA==.',
['Gå']='Gåladriel:BAAALgAECgEJAQAAAA==.',
Ha='Hael:BAAALgADCgEJAQAAAA==.Halar:BAABLgAECn8VAAICAAgJJQ80LgAmAQACAAgJJQ80LgAmAQAAAA==.Hammaford:BAAALgADCgMJAwAAAA==.Hardknockers:BAABLgAECn8VAAIhAAYJBwumIQAqAQAhAAYJBwumIQAqAQAAAA==.Hargyll:BAAALgAECgcJDQAAAA==.',
He='Heavychevy:BAABLgAECn8WAAMhAAcJDRWLGABsAQAhAAYJvxWLGABsAQAgAAEJlxFHKwA7AAAAAA==.Hellbentx:BAAALgAECgcJBwAAAA==.Heriel:BAAALgAECgQJBAABLgAECggJFwAPAKoZAA==.',
Hi='Hippyhunter:BAAALgAECgIJAgAAAA==.',
Ho='Hokes:BAAALgAFFAIJAwAAAA==.Hole:BAAALgADCgMJAwAAAA==.Homgar:BAAALgADCgYJBwAAAA==.Hoori:BAABLgAFFH8MAAIiAAgJJB4MAADEAgAiAAgJJB4MAADEAgAAAA==.',
Hu='Hughhoofner:BAAALgAECgIJAgAAAA==.Humphrees:BAABLgAECn8mAAMjAAgJ1A7uCQDLAQAjAAgJ1A7uCQDLAQAkAAEJFwaVIQAqAAAAAA==.Huraji:BAAALgAFFAIJAgABLgAFFAQJCgALANcYAA==.',
['Hà']='Hàtos:BAABLgAECn8lAAIUAAgJ8BrgGAAWAgAUAAgJ8BrgGAAWAgAAAA==.Hàtoz:BAAALgAECgMJAwAAAA==.',
Ii='Iironrod:BAAALgADCgcJDgAAAA==.',
Im='Impawsum:BAAALgADCgUJBwAAAA==.',
In='Invissibill:BAABLgAECn8VAAIlAAcJRgTSBgDmAAAlAAcJRgTSBgDmAAAAAA==.',
Ir='Ironbark:BAAALgADCgcJDwAAAA==.',
Iv='Ivanã:BAABLgAECn8aAAIaAAcJOBuHAwDaAQAaAAcJOBuHAwDaAQAAAA==.',
Iz='Izax:BAABLgAECn8cAAIEAAgJUAsVLQB4AQAEAAgJUAsVLQB4AQAAAA==.',
Ja='Jamestown:BAAALgADCgcJBwAAAA==.Janebquick:BAAALgAECgUJBgAAAA==.',
Je='Jelkal:BAAALgAECggJDwAAAA==.Jemstone:BAAALgADCgYJBgAAAA==.',
Jj='Jjl:BAAALgAFFAIJAgAAAA==.',
Jo='Johnnylingo:BAAALgAECgEJAQAAAA==.Johnwarcratf:BAAALgAECgYJDAAAAA==.',
Ju='Jupitus:BAABLgAECn8aAAIPAAcJ0hQ3LgCJAQAPAAcJ0hQ3LgCJAQAAAA==.Juícewrld:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåhkøtå:BAAALgADCgYJBgAAAA==.',
Ka='Kaboomkablow:BAAALgAECgQJBAABLgAECgcJFgAOAJwPAA==.Kaosz:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8WAAIOAAYJvyFvCQDiAQAOAAYJvyFvCQDiAQAAAA==.Katalanii:BAABLgAECn8XAAICAAYJ3goyQgDIAAACAAYJ3goyQgDIAAAAAA==.Kathtaer:BAAALgADCggJDQAAAA==.Katja:BAABLgAECn8YAAIEAAgJbRmfKQBqAgAEAAgJbRmfKQBqAgAAAA==.',
Ke='Keiwhenua:BAABLgAECn8ZAAICAAgJEw4qJQBbAQACAAgJEw4qJQBbAQAAAA==.Keled:BAAALgAECgQJBAAAAA==.Kelinn:BAAALgAECgQJBwAAAA==.Kelzier:BAAALgAECgUJCAABLgAECggJFwAPAKoZAA==.Kenthel:BAAALgAECgQJEwABLgAECgUJDAAMAAAAAA==.Kenthels:BAAALgAECgUJDAAAAA==.Kezt:BAAALgADCgEJAQAAAA==.',
Kh='Khalena:BAAALgADCgUJBwAAAA==.',
Ki='Kiiya:BAAALgAECgIJAgAAAA==.Kik:BAAALgAECgEJAQAAAA==.Killerchop:BAABLgAECn8bAAMZAAgJChniBADvAQAZAAcJ8BjiBADvAQAUAAcJKhMhfADZAQAAAA==.Kiplander:BAAALgAECgYJEwAAAA==.Kithforge:BAAALgADCgEJAQAAAA==.Kittytree:BAAALgADCgQJBAAAAA==.',
Ko='Kohii:BAAALgAECgEJAQAAAA==.Korry:BAAALgAECgQJCgAAAA==.Kortanis:BAAALgADCgkJKQAAAA==.Korzaz:BAAALgAECgYJEQAAAA==.Kosiicek:BAAALgAECgEJAQAAAA==.Kotala:BAAALgADCgMJBAAAAA==.',
Kr='Krakìn:BAAALgAECgQJCgAAAA==.Krelanllan:BAAALgADCgkJDQAAAA==.Krilliz:BAABLgAECn8UAAIfAAcJvQ9hKwBsAQAfAAcJvQ9hKwBsAQAAAA==.Krocodile:BAAALgAECgEJAgAAAA==.',
Ku='Kushage:BAAALgADCgcJCAAAAA==.',
Ky='Kyndarra:BAAALgADCgcJBwABLgAECggJIAACAB8QAA==.Kynlea:BAAALgADCgMJAwAAAA==.Kyumii:BAAALgADCgcJBwAAAA==.',
['Kà']='Kàstielle:BAAALgADCgYJBwAAAA==.',
['Kì']='Kìla:BAAALgAECgEJAQABLgAECgkJJgAPAA8kAA==.',
La='Landissa:BAABLgAECn8fAAIjAAgJThp3BQAqAgAjAAgJThp3BQAqAgAAAA==.Lanigosa:BAAALgADCggJBwAAAA==.Lanno:BAAALgADCgUJBgAAAA==.Laquandrae:BAAALgAECgUJEQAAAA==.Larryholmes:BAABLgAECn8WAAIOAAcJnA/yLQB0AQAOAAcJnA/yLQB0AQAAAA==.Lasting:BAAALgADCgYJCAAAAA==.Lathmaria:BAAALgADCgEJAQAAAA==.',
Le='Leche:BAAALgAECgUJBwAAAA==.Leenaa:BAABLgAECn8gAAICAAgJHxC7HQCTAQACAAgJHxC7HQCTAQAAAA==.Lerash:BAAALgADCgIJAgAAAA==.',
Li='Liankaima:BAAALgADCgUJBQAAAA==.Lightninfury:BAAALgAECgEJAgAAAA==.Lihan:BAAALgAECgUJDgAAAA==.Lilieth:BAAALgADCgIJAgAAAA==.Lily:BAABLgAECn8gAAITAAcJRRzJSwAQAgATAAcJRRzJSwAQAgAAAA==.Livelyfist:BAAALgAECgYJEwAAAA==.Livelywilds:BAAALgADCgYJBgAAAA==.Livvmore:BAAALgADCgEJAQAAAA==.',
Lo='Locki:BAAALgADCgcJBwAAAA==.Loosenut:BAAALgAECgEJAQAAAA==.Lortelle:BAAALgAECgQJBAABLgAECggJGwAbAAgdAA==.Losic:BAAALgADCgcJCwAAAA==.Lotzofblood:BAAALgAECgQJBAAAAA==.Loverocket:BAABLgAECn8cAAIQAAgJNB0/AwA0AgAQAAgJNB0/AwA0AgAAAA==.',
Lu='Lugosi:BAAALgADCgcJDQABLgAECgkJJgADAEEaAA==.Lullers:BAAALgAECgMJBgAAAA==.Luna:BAAALgAECgYJCwABLgAECgcJCgAMAAAAAA==.Lunastorm:BAAALgADCgYJBgAAAA==.Luroe:BAAALgADCgkJCQAAAA==.',
Ly='Lyralina:BAEALgADCgQJBAABLgAECgkJHAANALsVAA==.Lysergicon:BAAALgADCgEJAQAAAA==.Lyshia:BAABLgAECn8fAAIUAAkJDyAHFwAkAgAUAAkJDyAHFwAkAgAAAA==.Lyshion:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìch:BAAALgADCgIJAgAAAA==.',
['Lí']='Líghthand:BAABLgAECn8cAAIQAAkJ5x2oAQA2AwAQAAkJ5x2oAQA2AwAAAA==.',
['Lý']='Lýght:BAAALgADCggJDAAAAA==.',
Ma='Magdaanii:BAAALgAECgMJAwAAAA==.Magedown:BAABLgAECn8aAAIUAAgJGxQIlACrAQAUAAgJGxQIlACrAQAAAA==.Magician:BAAALgAECgQJBwABLgAECgcJFgAOAJwPAA==.Magicmallet:BAABLgAECn8ZAAIWAAgJYSSIAwA6AwAWAAgJYSSIAwA6AwAAAA==.Manwell:BAAALgADCgMJAwAAAA==.Martinell:BAAALgADCgYJDAAAAA==.Matap:BAAALgADCgkJEgAAAA==.Mataw:BAABLgAECn8dAAMhAAgJUhqBBwA1AgAhAAgJUhqBBwA1AgAgAAYJ3BC2FgBHAQAAAA==.Mattdemon:BAABLgAECn8mAAIDAAkJQRqRDwD2AQADAAkJQRqRDwD2AQAAAA==.',
Me='Mehruna:BAAALgADCgEJAgAAAA==.Meliany:BAAALgADCgMJAwAAAA==.Meliowar:BAAALgADCgQJBAAAAA==.Melkdudd:BAAALgAECgcJBwAAAA==.Mephmonster:BAAALgADCgEJAQAAAA==.Meríin:BAAALgADCgYJBgAAAA==.Meteori:BAAALgADCgEJAQAAAA==.Metroboomkin:BAAALgAECgIJAgAAAA==.',
Mi='Miksi:BAAALgADCgcJDwABLgAECgIJAwAMAAAAAA==.Miradele:BAAALgAECgYJEQAAAA==.Miraxx:BAAALgAECgEJAgAAAA==.Misscleö:BAABLgAECn8aAAIPAAgJmBHEKgCXAQAPAAgJmBHEKgCXAQAAAA==.Mistybrew:BAAALgADCgMJAwAAAA==.Miyoshi:BAABLgAECn8UAAIjAAgJFQd6EABoAQAjAAgJFQd6EABoAQAAAA==.Mizrhi:BAAALgADCgkJDAAAAA==.',
Mo='Monthy:BAAALgADCgUJCAAAAA==.Moonkey:BAAALgAECgIJAgAAAA==.Moosakka:BAABLgAECn8fAAMOAAgJ1BNXFgA3AQAOAAcJuhBXFgA3AQANAAYJvg3cLwCPAAAAAA==.Moosedluffy:BAAALgAECgYJDAAAAA==.Moosesiah:BAAALgAECgcJEQAAAA==.Moovinthru:BAAALgAECgMJCAAAAA==.Moraxes:BAABLgAECn8dAAIiAAgJKRpPEQDyAQAiAAgJKRpPEQDyAQAAAA==.Mordenkainen:BAAALgAECgQJDgAAAA==.Morenor:BAABLgAECn8VAAIKAAYJXAaCPQAIAQAKAAYJXAaCPQAIAQAAAA==.Morphidmage:BAABLgAECn8lAAIUAAgJ/AxcNACUAQAUAAgJ/AxcNACUAQAAAA==.Mortetdabo:BAAALgAECgYJBwAAAA==.Motoko:BAAALgADCggJEwAAAA==.Motolei:BAAALgADCggJCAABLgAECgcJFAADAAoLAA==.',
Mu='Muaadib:BAAALgADCgcJFAABLgAECgcJFAADAAoLAA==.',
My='Mydin:BAABLgAECn8hAAIPAAkJERekFwD/AQAPAAkJERekFwD/AQAAAA==.Myordarsh:BAABLgAECn8fAAMTAAgJSRfMFwD8AQATAAgJSRfMFwD8AQAbAAYJtQmqFQDSAAAAAA==.',
['Mì']='Mìsawa:BAAALgAECgQJCgAAAA==.',
Na='Nael:BAAALgAECgQJBAAAAA==.Naeleen:BAAALgADCgQJBwAAAA==.Nakai:BAAALgADCgkJGwAAAA==.Nasmage:BAAALgADCgkJCgAAAA==.',
Ne='Nelfgonewild:BAAALgAECgIJAgAAAA==.Nexs:BAAALgAECgcJBwAAAA==.Nexxa:BAABLgAECn8eAAIRAAgJoBbYEgD8AQARAAgJoBbYEgD8AQAAAA==.Neyrina:BAAALgADCgUJCAAAAA==.',
Ni='Nickk:BAAALgAECggJAQAAAA==.Nightshadow:BAAALgAECgcJDAAAAA==.Niqkle:BAABLgAECn8fAAMdAAkJEhcoDwCxAQAdAAgJ7RUoDwCxAQAcAAIJHgNFlABLAAAAAA==.Nirat:BAAALgADCgEJAQAAAA==.Nishandriel:BAAALgADCgkJDwAAAA==.Nivia:BAAALgAECgMJBgABLgAFFAYJEwAJABsYAA==.',
No='Nohurtscooby:BAAALgAECgIJAgAAAA==.Normond:BAAALgADCgUJCgAAAA==.Nosiaria:BAAALgAECgEJAQAAAA==.Notadh:BAAALgAECgYJDAAAAA==.Notmeanzy:BAABLgAECn8lAAMKAAgJNB9wAwCEAgAKAAgJNB9wAwCEAgALAAMJQhZgOwDOAAAAAA==.',
Ns='Nstagatr:BAAALgADCgEJAQAAAA==.',
Nu='Numeroun:BAAALgAECgQJBwAAAA==.',
['Né']='Nécrömancer:BAAALgADCgIJAgAAAA==.',
['Nï']='Nïghtknïght:BAAALgAECgMJAwAAAA==.',
Ol='Oleanna:BAABLgAECn8aAAIOAAYJXA48IwDRAAAOAAYJXA48IwDRAAABLgAECggJKQAPACUaAA==.Olehanna:BAABLgAECn8pAAIPAAgJJRq0EwAcAgAPAAgJJRq0EwAcAgAAAA==.Olendra:BAAALgADCgkJCQABLgAECggJKQAPACUaAA==.Olestrid:BAAALgADCgkJCQABLgAECggJKQAPACUaAA==.',
On='Onyxtear:BAAALgADCgcJEwAAAA==.',
Op='Opioid:BAABLgAECn8VAAIRAAYJoBpJJgCAAQARAAYJoBpJJgCAAQAAAA==.Opsèc:BAABLgAECn8gAAIDAAcJEBQGJgBRAQADAAcJEBQGJgBRAQAAAA==.',
Or='Orsa:BAABLgAECn8VAAIdAAcJcxQlMACfAQAdAAcJcxQlMACfAQAAAA==.',
Ot='Othon:BAAALgADCgEJAQAAAA==.',
Pe='Pebbles:BAAALgADCgIJAgABLgAECgMJAwAMAAAAAA==.Pedren:BAAALgAECgQJCwAAAA==.Perfectpal:BAABLgAECn8aAAIWAAgJPRXULwDDAQAWAAgJPRXULwDDAQAAAA==.Peri:BAAALgADCgUJBQAAAA==.',
Ph='Phaeseus:BAAALgAECgUJBQAAAA==.Phexaryl:BAAALgAECgUJBgAAAA==.',
Pl='Planette:BAAALgAECggJEwAAAA==.',
Po='Poinda:BAAALgADCgIJAgAAAA==.Poisionivy:BAAALgADCgEJAQAAAA==.Popcorners:BAABLgAECn8nAAILAAkJYx1oCAC4AgALAAkJYx1oCAC4AgAAAA==.Popopanda:BAAALgAECgQJCgAAAA==.Poppnlok:BAAALgADCgEJAQAAAA==.Pordgio:BAABLgAECn8YAAIjAAgJ7gssEQBfAQAjAAgJ7gssEQBfAQAAAA==.Pozzi:BAAALgAECgIJAwAAAA==.',
Pr='Praypal:BAAALgAECgMJBgAAAA==.Problematiç:BAAALgADCgEJAQAAAA==.Proxxy:BAAALgADCgMJAwAAAA==.',
Ps='Psuedolus:BAABLgAECn8cAAITAAgJciKRCgB6AgATAAgJciKRCgB6AgAAAA==.Psålm:BAAALgAECgQJCAAAAA==.',
Pu='Pulshadow:BAACLgAFFH8PAAIKAAUJbh0+AwCBAQAKAAUJbh0+AwCBAQAuAAQKfx8AAgoACAkYJDYFAD4DAAoACAkYJDYFAD4DAAAA.Pumah:BAAALgAECgIJAwAAAA==.',
Pw='Pweenqween:BAAALgADCgEJAQAAAA==.',
Py='Pyreska:BAAALgAECgkJBgAAAA==.Pyroklasm:BAABLgAECn8bAAIUAAcJtByKUwA9AgAUAAcJtByKUwA9AgAAAA==.',
Qt='Qthunter:BAAALgADCgkJCQABLgAECgcJEwAMAAAAAA==.Qtlocks:BAAALgADCgkJCQABLgAECgcJEwAMAAAAAA==.Qtmonk:BAAALgAECgcJEwAAAA==.',
Qu='Quartzecoatl:BAAALgADCgMJAwAAAA==.Quela:BAAALgAECgMJBgAAAA==.Quintcaster:BAAALgAECgQJBAAAAA==.Quirt:BAAALgAECgQJCwAAAA==.',
Ra='Raamen:BAAALgAECgIJAwAAAA==.Rabiéz:BAAALgAECgEJAQAAAA==.Raellia:BAABLgAECn8mAAQFAAgJAhbfEgCRAAAEAAQJ5xIncACrAAAmAAIJ2Rf6CQCfAAAFAAMJ2BffEgCRAAAAAA==.Raimmey:BAAALgAECgMJAwAAAA==.Rajann:BAAALgADCgMJAwAAAA==.Rajia:BAAALgAECgYJDQAAAA==.Rakaw:BAAALgADCgMJAwAAAA==.Ralune:BAABLgAECn8YAAIYAAcJow8CFgBQAQAYAAcJow8CFgBQAQAAAA==.Randomone:BAAALgAECggJDgAAAA==.Ranes:BAABLgAECn8mAAQjAAgJrxzhAwBaAgAjAAgJrxzhAwBaAgAkAAQJuA/IEgDWAAAlAAEJTAfFDgAvAAAAAA==.Rathmore:BAAALgAECgQJBQAAAA==.Raylavoidles:BAAALgADCgcJDgAAAA==.Rayllee:BAAALgAECgcJEAAAAA==.',
Re='Redi:BAAALgADCgYJBgAAAA==.Redxelementz:BAABLgAECn8mAAIcAAgJ6CMqBwABAwAcAAgJ6CMqBwABAwAAAA==.Relyana:BAAALgADCgEJAQAAAA==.Remena:BAABLgAECn8WAAIOAAcJERzfFwAlAgAOAAcJERzfFwAlAgAAAA==.Renasen:BAAALgAECggJEQAAAA==.Reno:BAABLgAECn8gAAIWAAgJhhpOBgB+AgAWAAgJhhpOBgB+AgAAAA==.René:BAAALgADCgUJBwAAAA==.Resiretha:BAABLgAECn8WAAMEAAgJmAMqUgD6AAAEAAgJmAMqUgD6AAAFAAEJBQUVegAoAAAAAA==.Revelynn:BAABLgAECn8hAAIDAAgJHx9nNgAdAgADAAgJHx9nNgAdAgAAAA==.',
Rh='Rhico:BAAALgADCgEJAQAAAA==.Rhyin:BAAALgADCgYJBgAAAA==.',
Ri='Riolu:BAAALgAECgQJBAAAAA==.',
Rn='Rngesus:BAAALgAECgEJAQABLgAECggJLQATAE0fAA==.',
Ro='Robotmonk:BAAALgAECgQJBAABLgAECgkJHAAQAOcdAA==.Rooxxy:BAAALgAECgcJDgAAAA==.Rotawna:BAAALgAECgMJAwAAAA==.Roxxye:BAAALgADCgEJAQABLgAECgcJDgAMAAAAAA==.',
Ru='Rumms:BAAALgAECgcJCwAAAA==.Rustybottom:BAAALgADCgEJAQAAAA==.Ruumis:BAAALgAECgQJBAAAAA==.',
Ry='Rydric:BAABLgAECn8WAAIUAAgJFCPGEwAxAwAUAAgJFCPGEwAxAwAAAA==.Ryezn:BAAALgADCgEJAQAAAA==.Ryxhal:BAAALgADCgYJBgAAAA==.',
['Rï']='Rïnzlër:BAAALgAECgcJEwAAAA==.',
Sa='Saela:BAAALgAECgYJBgAAAA==.Sarac:BAABLgAECn8ZAAIiAAgJjwLSFQDaAAAiAAgJjwLSFQDaAAAAAA==.Saratosh:BAAALgADCgEJAQAAAA==.Savira:BAAALgAECgQJCgAAAA==.',
Sc='Scaleorva:BAABLgAECn8VAAMHAAYJCg9pBgA0AQAHAAYJCg9pBgA0AQAGAAEJfQTRaAAkAAAAAA==.',
Se='Seraphìm:BAABLgAECn8ZAAIPAAgJdgb2SAAvAQAPAAgJdgb2SAAvAQAAAA==.',
Sh='Shadyballs:BAABLgAECn8VAAQZAAcJkg6tAgCCAQAZAAcJkg6tAgCCAQAnAAQJfAkwCQDDAAAUAAIJFQpXSQFtAAAAAA==.Shakypete:BAAALgAECgUJBwABLgAECgYJEwAMAAAAAA==.Shalaena:BAAALgAECgMJAwAAAA==.Shamysosa:BAABLgAECn8XAAMdAAYJcBrdFABwAQAdAAYJcBrdFABwAQAcAAEJ6AOepQAqAAAAAA==.Shanebentea:BAABLgAECn8bAAIhAAcJGw3PGQBiAQAhAAcJGw3PGQBiAQAAAA==.Sharpy:BAAALgADCgcJBwABLgAECggJGwAUACoZAA==.Sharpyboi:BAAALgADCgMJAwABLgAECggJGwAUACoZAA==.Sharpyy:BAAALgADCgYJBgABLgAECggJGwAUACoZAA==.Shiven:BAAALgAECgMJAwAAAA==.Shmob:BAABLgAECn8VAAIdAAYJ2Q1gGwA5AQAdAAYJ2Q1gGwA5AQAAAA==.Shnappz:BAABLgAECn8WAAMFAAYJDQ5mEQCiAAAEAAUJCwhVVAD0AAAFAAQJERFmEQCiAAAAAA==.Shockittome:BAAALgADCgUJBQAAAA==.Shroomee:BAABLgAFFH8KAAMCAAcJrwpMDQA4AQACAAYJlQdMDQA4AQAYAAIJfhbvEwDMAAAAAA==.Shwillarou:BAABLgAECn8mAAITAAgJbA3oKQCVAQATAAgJbA3oKQCVAQAAAA==.Shwillmoon:BAAALgADCgkJEgAAAA==.Shärpy:BAABLgAECn8bAAIUAAgJKhk3UwA+AgAUAAgJKhk3UwA+AgAAAA==.',
Si='Silverstring:BAAALgAECgQJBwAAAA==.Simmi:BAAALgAECgIJAgAAAA==.Sinergee:BAABLgAECn8ZAAIRAAcJCRGfKgBqAQARAAcJCRGfKgBqAQAAAA==.Sinfulkitten:BAAALgADCgcJCAAAAA==.Sinnj:BAAALgAECgYJCwAAAA==.',
Sk='Skinney:BAAALgAECgIJAwAAAA==.Skycrush:BAAALgAECgQJBwAAAA==.',
Sl='Slanie:BAABLgAECn8WAAIJAAYJehBoGwArAQAJAAYJehBoGwArAQAAAA==.Slingerz:BAABLgAECn8nAAIiAAkJrxUKDwAYAgAiAAkJrxUKDwAYAgAAAA==.Slowmeaux:BAAALgADCgYJCgAAAA==.',
Sm='Smoky:BAABLgAECn8ZAAQEAAgJKyFAOwAfAgAEAAYJEiFAOwAfAgAFAAMJPB+/LAALAQAmAAEJAACUIgBnAAAAAA==.',
Sn='Snacky:BAAALgADCgIJAgAAAA==.Sneakpastya:BAABLgAECn8gAAIjAAgJEgeQDgCDAQAjAAgJEgeQDgCDAQAAAA==.Sneakyg:BAAALgAECgEJAQABLgAECggJFwAPAKoZAA==.Snooksdk:BAAALgADCgEJAQAAAA==.',
So='Solkar:BAAALgAECgYJCgAAAA==.Sollis:BAAALgAECgMJBQAAAA==.Sonastii:BAABLgAECn8aAAIdAAgJXh2qBQBYAgAdAAgJXh2qBQBYAgAAAA==.Soulbztrd:BAABLgAECn8fAAMFAAkJ5RZwGgB5AQAFAAUJIRpwGgB5AQAEAAcJ8BO7OABKAQAAAA==.Soulpepper:BAAALgAECgQJBAAAAA==.Soulreaper:BAAALgAECgYJBgAAAA==.',
Sp='Spazzchel:BAAALgAECgQJBwAAAA==.Spruce:BAAALgADCgkJEgAAAA==.',
St='Stahlman:BAABLgAECn8mAAIcAAgJUx3jCQBLAgAcAAgJUx3jCQBLAgAAAA==.Stalpho:BAABLgAECn8cAAIhAAgJAg/0PQCsAQAhAAgJAg/0PQCsAQAAAA==.Starflare:BAAALgADCgcJGQABLgAECgcJGgAcADMHAA==.Starkind:BAABLgAECn8aAAIcAAcJMwdiLQAOAQAcAAcJMwdiLQAOAQAAAA==.Stefussy:BAAALgADCgIJAgAAAA==.Stonefist:BAAALgAECgYJCgABLgAECgYJFwAdAHAaAA==.Stoutmist:BAAALgAECgEJAQAAAA==.Sturr:BAAALgADCgQJBAAAAA==.',
Su='Subza:BAAALgADCgMJAwAAAA==.Sundalo:BAAALgAECgUJCAAAAA==.Superjoyful:BAAALgADCgEJAQAAAA==.Supersweet:BAAALgADCgYJEQAAAA==.Sutterkain:BAAALgAECgMJBAAAAA==.',
Sw='Swagadin:BAABLgAECn8kAAIPAAkJfyRWBwBdAwAPAAkJfyRWBwBdAwAAAA==.Swagika:BAAALgADCgYJBgABLgAECgkJJAAPAH8kAA==.',
Sy='Syine:BAAALgADCgUJBQAAAA==.Sylee:BAABLgAFFH8FAAINAAMJwhnlDwDZAAANAAMJwhnlDwDZAAAAAA==.',
Ta='Tabitia:BAABLgAECn8hAAMXAAgJVRP6FAB4AQAXAAYJnhL6FAB4AQARAAgJvBBCWQC+AAAAAA==.Taladari:BAAALgADCgEJAQAAAA==.Taliss:BAAALgAECgQJCwAAAA==.Talonpepper:BAAALgADCgMJAwAAAA==.Tankmedaddy:BAABLgAECn8hAAMNAAgJCRRODgDCAQANAAgJCRRODgDCAQAOAAEJawP3hwAoAAAAAA==.Tankopotamus:BAAALgADCgEJAQAAAA==.Tapenga:BAAALgAECgQJBAAAAA==.Tappuccino:BAAALgAECgMJBgAAAA==.Taras:BAACLgAFFH8JAAIhAAMJoiDiCwAyAQAhAAMJoiDiCwAyAQAuAAQKfxwAAiEACQkGIPQHACsDACEACQkGIPQHACsDAAAA.Taraxist:BAABLgAECn8gAAIFAAgJ2BnNAQAWAgAFAAgJ2BnNAQAWAgAAAA==.Tarcanisdk:BAABLgAECn8YAAITAAgJjxRrIwC1AQATAAgJjxRrIwC1AQAAAA==.Tasuma:BAAALgAECgYJCgAAAA==.Tautology:BAABLgAECn8fAAIKAAgJIBiBGwABAgAKAAgJIBiBGwABAgAAAA==.Tazdingo:BAAALgADCgEJAQAAAA==.',
Tc='Tchala:BAABLgAECn8XAAIPAAgJqhmEfACBAQAPAAgJqhmEfACBAQAAAA==.Tchaumb:BAAALgADCgYJBgAAAA==.',
Te='Tedeschi:BAAALgAECgEJAgAAAA==.Teks:BAABLgAECn8gAAIWAAgJCxkkBwBtAgAWAAgJCxkkBwBtAgAAAA==.Teksara:BAAALgADCgcJBwABLgAECggJIAAWAAsZAA==.Tekszen:BAAALgADCgEJAQABLgAECggJIAAWAAsZAA==.Tencup:BAAALgAECggJEwAAAA==.Teth:BAABLgAECn8VAAMFAAYJ7BKVBwA5AQAFAAYJ7BKVBwA5AQAEAAEJuQEHwwAgAAAAAA==.Tetsuyo:BAAALgAECgQJBgAAAA==.',
Th='Thaine:BAABLgAECn8nAAIPAAkJRSRWCQBHAwAPAAkJRSRWCQBHAwAAAA==.Theelvira:BAAALgADCgYJBgAAAA==.Theoalthor:BAAALgADCgYJDgAAAA==.Theresis:BAAALgAECgMJBAAAAA==.Therkadin:BAAALgAECgUJDQAAAA==.Theundeadone:BAAALgAECgYJCAAAAA==.Thndrwzrd:BAAALgAECgQJCgAAAA==.Thrust:BAAALgADCgIJAgAAAA==.',
Ti='Ticho:BAABLgAECn8iAAITAAgJQwa1QAA8AQATAAgJQwa1QAA8AQAAAA==.Tindmina:BAABLgAECn8bAAIWAAcJuhnQFgCaAQAWAAcJuhnQFgCaAQAAAA==.Tinglekin:BAAALgAECgIJAwAAAA==.',
Tl='Tlo:BAAALgAECgcJDgAAAA==.Tlol:BAAALgAECgUJBwABLgAECgcJDgAMAAAAAA==.',
To='Toenails:BAAALgADCgUJBQAAAA==.Torkkit:BAAALgAECgEJAQABLgAECgMJBAAMAAAAAA==.Torodisilis:BAAALgAECgIJAgABLgAECggJFwAPAKoZAA==.Torqit:BAAALgAECgMJBAAAAA==.Totemzrus:BAAALgAECgcJEgAAAA==.',
Tr='Trath:BAAALgADCgMJAwAAAA==.Trent:BAAALgADCgQJCAAAAA==.Trickette:BAAALgAECggJAwAAAA==.Trickeye:BAAALgADCgIJAgAAAA==.',
Tw='Twicks:BAABLgAFFH8FAAIOAAUJkwjnAgB8AQAOAAUJkwjnAgB8AQAAAA==.',
Ud='Udderlyquiff:BAAALgAECgIJAgAAAA==.Udderlyslow:BAABLgAECn8eAAIcAAcJByGbGwA7AgAcAAcJByGbGwA7AgAAAA==.',
Ug='Uglyloser:BAAALgAECgEJAQAAAA==.',
Un='Undeez:BAAALgAECgMJAwAAAA==.Unluckyfrien:BAAALgAECgIJAgAAAA==.',
Va='Vaeshta:BAAALgAECgcJEQAAAA==.Vaku:BAAALgADCgkJDQAAAA==.Valhallarama:BAABLgAECn8UAAIcAAYJ0AvsNwDVAAAcAAYJ0AvsNwDVAAAAAA==.Vampy:BAAALgAECgcJEAAAAA==.Vannida:BAAALgAECgUJBQAAAA==.Vanìlla:BAAALgADCgEJAQAAAA==.Varya:BAAALgAECgYJBwAAAA==.Vasuvious:BAABLgAECn8hAAIBAAcJDRyWHgANAgABAAcJDRyWHgANAgAAAA==.',
Ve='Vesstara:BAAALgADCgUJCwABLgAECgEJAgAMAAAAAA==.',
Vi='Vinago:BAAALgAECgMJAwAAAA==.',
Vo='Voidabyss:BAAALgADCgUJBQAAAA==.Voidixx:BAAALgADCgUJCwAAAA==.Voodoo:BAAALgAECgIJAwAAAA==.',
Vy='Vyleta:BAAALgADCgYJBgAAAA==.Vyllian:BAABLgAECn8tAAMTAAgJTR9NEwAfAgATAAgJ4h1NEwAfAgAbAAcJhw2fDwAcAQAAAA==.Vyri:BAAALgAECgEJAQAAAA==.',
['Vá']='Váz:BAAALgADCgYJBgABLgAFFAIJAwAMAAAAAA==.',
Wa='Wangwang:BAAALgAECgMJCAAAAA==.Warlakaflaka:BAAALgAECgEJAQABLgAECgcJFQAZAJIOAA==.Warlboro:BAACLgAFFH8RAAIEAAUJmQ9HFQBDAQAEAAUJmQ9HFQBDAQAuAAQKfyUABAQACAlwHBIfAJ0CAAQACAlwHBIfAJ0CAAUABAnvClw1AOEAACYAAQnBIB8oAFEAAAAA.',
Wh='Whale:BAABLgAECn8ZAAIiAAgJwxY5EQD0AQAiAAgJwxY5EQD0AQAAAA==.Whine:BAAALgAECgMJAwAAAA==.',
Wi='Wibbers:BAAALgAECgEJAQAAAA==.Wicked:BAAALgAECgQJEgABLgAECgcJCgAMAAAAAA==.Willôw:BAAALgADCgkJDgAAAA==.Windwalker:BAABLgAECn8ZAAIOAAgJWBF2DQChAQAOAAgJWBF2DQChAQAAAA==.Winkey:BAAALgADCgYJBgAAAA==.Winston:BAAALgADCgEJAgAAAA==.',
Wo='Wolfsong:BAAALgADCgMJBAABLgAECgQJBgAMAAAAAA==.Woosaah:BAAALgAECgcJBwAAAA==.',
Wr='Wreckyou:BAAALgAECgYJEAAAAA==.',
Wt='Wtfimkorgak:BAABLgAECn8cAAIJAAcJWSJrBACKAgAJAAcJWSJrBACKAgAAAA==.',
Wy='Wy:BAAALgADCgYJBgAAAA==.Wylestrean:BAABLgAECn8gAAMXAAgJoBoIDQCOAQAXAAYJJR0IDQCOAQARAAMJNhavawCBAAAAAA==.',
Xa='Xandoriel:BAAALgADCgQJBAAAAA==.',
Xy='Xyrathul:BAAALgAECgEJAQAAAA==.',
Ye='Yeahigotmilk:BAAALgADCgUJBQAAAA==.Yellowgoblin:BAAALgAECgIJAgAAAA==.',
Yo='Yopali:BAAALgAECgIJAwAAAA==.',
Yu='Yugiohrox:BAABLgAECn8bAAIbAAgJCB2CCwBbAgAbAAgJCB2CCwBbAgAAAA==.Yujology:BAABLgAECn8ZAAIaAAgJ8gOaCgDxAAAaAAgJ8gOaCgDxAAAAAA==.',
Ze='Zel:BAAALgAECgQJCgAAAA==.Zentradei:BAAALgAECgMJCAAAAA==.Zephirothh:BAAALgADCgYJDQAAAA==.',
Zi='Zieganfuss:BAABLgAECn8XAAIUAAcJ5R/+VAA5AgAUAAcJ5R/+VAA5AgAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zimmy:BAAALgADCgYJBgAAAA==.',
Zo='Zoho:BAAALgAECgUJDgAAAA==.Zoomies:BAAALgADCgMJAwAAAA==.',
Zu='Zulkai:BAABLgAECn8gAAICAAgJ+RT8FwDBAQACAAgJ+RT8FwDBAQAAAA==.',
Zy='Zynvar:BAAALgADCgYJBgAAAA==.',
['Zá']='Záv:BAABLgAECn8YAAMCAAgJchc1JwAZAgACAAgJchc1JwAZAgAoAAIJMQpYFgB0AAABLgAFFAIJAwAMAAAAAA==.',
['Zä']='Zäne:BAABLgAECn8ZAAIUAAYJHxpAjQC4AQAUAAYJHxpAjQC4AQAAAA==.',
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

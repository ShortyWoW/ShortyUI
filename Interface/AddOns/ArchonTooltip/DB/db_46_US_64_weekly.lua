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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Warrior-Protection','Warrior-Fury','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Unknown-Unknown','Priest-Holy','Priest-Shadow','Mage-Frost','Evoker-Devastation','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Devourer','Warrior-Arms','Druid-Restoration','Monk-Brewmaster','DeathKnight-Blood','Priest-Discipline','DeathKnight-Unholy','Rogue-Outlaw','Monk-Mistweaver','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Shaman-Elemental','Druid-Guardian','Mage-Arcane','Paladin-Holy','Paladin-Protection','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aamix:BAACLgAFFH8NAAIBAAQJmBCjGQA6AQABAAQJmBCjGQA6AQAuAAQKfyoAAwEACQn8HogLAFoCAAEACQn8HogLAFoCAAIAAQkAALB+ABsAAAAA.Aarom:BAABLgAECn8UAAIDAAcJkxThEQBlAQADAAcJkxThEQBlAQAAAA==.',
Ab='Abdltzach:BAAALgADCgYJBgABLgAECgYJGQAEAGYiAA==.Abhark:BAAALgAECgYJCQAAAA==.',
Ac='Acemonk:BAAALgAECggJCQAAAA==.Achifee:BAAALgAECgQJBAAAAA==.',
Ad='Adragen:BAAALgAECgUJBQAAAA==.',
Ae='Aelyn:BAAALgADCgUJBQAAAA==.Aeni:BAAALgAECgQJBAAAAA==.Aerius:BAAALgAECgMJAwAAAA==.',
Ai='Aingerfal:BAABLgAECn8VAAIFAAYJhwb4KQD3AAAFAAYJhwb4KQD3AAAAAA==.',
Ak='Akasori:BAABLgAECn8jAAIGAAgJKR3vBgCBAgAGAAgJKR3vBgCBAgAAAA==.Akira:BAABLgAECn8WAAIHAAcJvhktHwDPAQAHAAcJvhktHwDPAQAAAA==.Akorang:BAAALgADCgcJDAAAAA==.Akosori:BAAALgADCgMJAwABLgAECggJIwAGACkdAA==.',
Al='Alixx:BAAALgADCgQJBAAAAA==.Alkein:BAAALgAECgMJAwAAAA==.Allnaturale:BAAALgAECgEJAQAAAA==.Alîsonshammy:BAACLgAFFH8HAAIIAAQJQh2nBgB8AQAIAAQJQh2nBgB8AQAuAAQKfx4AAggACAnLIXAIAO8CAAgACAnLIXAIAO8CAAAA.',
Am='Ambersulfr:BAABLgAECn8UAAIJAAYJrxdnCABrAQAJAAYJrxdnCABrAQAAAA==.Ammarianar:BAAALgAECgMJAwABLgAECgYJDAAKAAAAAA==.Amrazz:BAABLgAECn8mAAMLAAkJrRhbBQBuAgALAAkJrRhbBQBuAgAMAAMJ7Aw+LwCIAAAAAA==.Amzey:BAEBLgAECn8hAAINAAgJziD1FQAsAgANAAgJziD1FQAsAgAAAA==.',
An='Anahata:BAAALgAECgEJAQAAAA==.Anari:BAABLgAECn8WAAIDAAYJcgl9PwAcAQADAAYJcgl9PwAcAQAAAA==.Andromeda:BAABLgAECn8jAAIFAAgJKRXYDwC+AQAFAAgJKRXYDwC+AQAAAA==.Anridel:BAAALgADCgIJAgAAAA==.Antimortem:BAAALgADCgQJBAAAAA==.Antwerpen:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Anyiaa:BAAALgADCgUJBQAAAA==.',
Ar='Arakis:BAAALgADCgcJEgABLgAECggJNAAOACAiAA==.Arcacia:BAAALgADCgQJBAAAAA==.Aridillo:BAAALgAECgUJBwAAAA==.Arkanum:BAAALgAECgUJCAAAAA==.Artemai:BAAALgAECgYJCQAAAA==.',
As='Ashaka:BAAALgAECgYJCwAAAA==.Ashylarry:BAAALgADCgYJDQAAAA==.Askthedm:BAAALgAECgQJBAAAAA==.Astralus:BAABLgAECn8WAAINAAgJ9haTXgAfAgANAAgJ9haTXgAfAgAAAA==.Astramis:BAABLgAECn8VAAINAAYJVwUBdQDtAAANAAYJVwUBdQDtAAAAAA==.',
Au='Aucee:BAAALgAECgYJBgAAAA==.',
Av='Avioradoramo:BAAALgADCgEJAQAAAA==.',
Az='Azariah:BAAALgADCgYJDQAAAA==.',
Ba='Babybuu:BAAALgAECgYJEwAAAA==.Backlash:BAAALgAFFAEJAQAAAA==.Balzhac:BAAALgAECgQJBQAAAA==.Bam:BAAALgADCgcJBwABLgAFFAUJEQAPAAsgAA==.Bambamcdn:BAAALgADCgEJAQAAAA==.',
Be='Beleaf:BAAALgAECgQJBAAAAA==.Bellmonte:BAAALgADCgYJCwABLgAECggJNAAOACAiAA==.Belmonk:BAAALgADCgEJAQAAAA==.Berdron:BAABLgAECn8qAAIBAAkJbQVkQQAtAQABAAkJbQVkQQAtAQAAAA==.Bessy:BAAALgAECgYJCQAAAA==.Bexton:BAABLgAECn8hAAIEAAgJYRegBwDFAQAEAAgJYRegBwDFAQAAAA==.',
Bi='Bicchoi:BAABLgAECn8XAAIDAAcJ2h1uEgBiAgADAAcJ2h1uEgBiAgAAAA==.Bigripper:BAAALgADCgcJBwAAAA==.',
Bl='Blackdot:BAABLgAECn8eAAMLAAgJlhazDgC4AQALAAgJlhazDgC4AQAMAAUJiwJwUgB/AAAAAA==.Blazin:BAABLgAECn8XAAQQAAYJgwyhOQANAQAQAAYJ+QuhOQANAQARAAIJnAIYRABOAAAOAAIJ1QUREgBCAAAAAA==.Bleddyn:BAAALgAECgYJBwAAAA==.Bledsmasher:BAABLgAECn8QAAISAAYJuxQeNQAOAQASAAYJuxQeNQAOAQAAAA==.Blinkss:BAAALgAECgEJAgAAAA==.Blouses:BAACLgAFFH8KAAMFAAQJDRw4DwAMAQAFAAQJDRw4DwAMAQATAAEJxgojEQBSAAAuAAQKfx0AAgUACQmrH/QEAFkDAAUACQmrH/QEAFkDAAAA.',
Bo='Bobowild:BAABLgAECn8UAAIUAAcJ+Q0VLAAxAQAUAAcJ+Q0VLAAxAQAAAA==.Bonbons:BAAALgAECgYJDwAAAA==.Boned:BAABLgAECn8XAAIVAAYJkR3GDAC+AQAVAAYJkR3GDAC+AQAAAA==.Bonemair:BAABLgAFFH8FAAIWAAIJpRbKDgB8AAAWAAIJpRbKDgB8AAABLgAFFAUJFQAVAJsdAA==.Bonezey:BAEALgAECgYJBgABLgAECggJIQANAM4gAA==.Bovityre:BAAALgAECgUJCgAAAA==.Bowjangles:BAAALgADCgEJAQAAAA==.Bowser:BAAALgAECgcJCQAAAA==.',
Bu='Bubbs:BAAALgADCgcJBwAAAA==.Buffnbeers:BAAALgADCgkJEQABLgAFFAQJBAAKAAAAAA==.Buffydemon:BAAALgADCgIJAgABLgAECgcJGAAHACgaAA==.Buffypaladin:BAABLgAECn8YAAIHAAcJKBpUKwCUAQAHAAcJKBpUKwCUAQAAAA==.Buffyrogue:BAAALgAECgYJDAAAAA==.Buffyshaman:BAAALgADCgEJAQABLgAECgcJGAAHACgaAA==.Buhger:BAAALgADCgEJAQAAAA==.Bup:BAABLgAECn8hAAQXAAgJ8h24DgBQAgAXAAcJsyC4DgBQAgALAAMJCBgJWADVAAAMAAEJPgZORAAvAAAAAA==.Bups:BAAALgAECgEJAQAAAA==.Burning:BAAALgAECgEJAgAAAA==.Buttjuggles:BAAALgADCgcJDwAAAA==.',
Bw='Bwonurjor:BAAALgADCgUJBQAAAA==.',
Ca='Caldec:BAACLgAFFH8VAAIYAAYJEyXQAQAIAgAYAAYJEyXQAQAIAgAuAAQKfyQAAhgACQmcJnoAAO4DABgACQmcJnoAAO4DAAAA.Caldh:BAABLgAECn8cAAISAAgJHR7HDAAVAgASAAgJHR7HDAAVAgABLgAFFAYJFQAYABMlAA==.Cardian:BAAALgAECgMJBAAAAA==.Casstiel:BAAALgAECgUJCAAAAA==.Catdog:BAAALgADCgYJDAABLgAECggJGwAJAPwbAA==.',
Ch='Chainizard:BAACLgAFFH8NAAIRAAQJMB7YCQA2AQARAAQJMB7YCQA2AQAuAAQKfyAAAhEACQlBIHEGANwCABEACQlBIHEGANwCAAAA.Chainsmash:BAAALgAECgUJBQABLgAFFAQJDQARADAeAA==.Chamonix:BAAALgAECgcJEgAAAA==.Chaoticrandy:BAAALgADCgYJBgAAAA==.Cheeno:BAACLgAFFH8GAAISAAMJyxfaGAAIAQASAAMJyxfaGAAIAQAuAAQKfycAAhIACAloJJ0NABMDABIACAloJJ0NABMDAAAA.Chillyblinks:BAACLgAFFH8HAAINAAMJuA3wNgD3AAANAAMJuA3wNgD3AAAuAAQKfxoAAg0ACAmEHu4kAN8CAA0ACAmEHu4kAN8CAAAA.Chillywings:BAAALgAECgIJAgABLgAFFAMJBwANALgNAA==.Chojii:BAAALgADCgcJDQAAAA==.Choryrth:BAAALgAECgMJBgAAAA==.Chubbymuffin:BAAALgAECggJCAAAAA==.',
Ci='Circuitry:BAAALgAECgYJCQAAAA==.',
Co='Congruent:BAABLgAFFH8GAAIIAAMJGhZxFgDWAAAIAAMJGhZxFgDWAAAAAA==.Cootin:BAAALgADCgEJAgAAAA==.Coriolanus:BAAALgADCgUJBAAAAA==.Corvus:BAAALgADCggJDAAAAA==.',
Cr='Crane:BAABLgAECn8YAAIVAAgJOhjSHgALAgAVAAgJOhjSHgALAgAAAA==.Crelam:BAACLgAFFH8aAAIJAAYJVQhnAABPAQAJAAYJVQhnAABPAQAuAAQKfyQAAgkACQnEGoIEANICAAkACQnEGoIEANICAAAA.Critz:BAAALgAECgUJCwAAAA==.Cronatherus:BAAALgAECgMJAwAAAA==.Cruentis:BAABLgAECn8iAAIZAAgJnxmrAQD/AQAZAAgJnxmrAQD/AQAAAA==.Crymsonroze:BAAALgAECgMJAwAAAA==.Crysus:BAAALgAECgYJEwAAAA==.',
Cu='Curruptor:BAAALgADCgIJAgAAAA==.',
Da='Dachiang:BAAALgAECgEJAgAAAA==.Damarisalynn:BAAALgADCgMJAwAAAA==.Dangus:BAABLgAECn8cAAQDAAgJ0RW3CgDLAQADAAgJ0RW3CgDLAQAVAAIJLQhUeQBeAAAaAAEJlwdbbgAnAAAAAA==.Danifarian:BAABLgAECn8eAAMOAAgJ9BcIDQAJAgAOAAgJ/xQIDQAJAgAQAAYJexPzKAB2AQABLgAFFAgJHwAKAAAAAA==.Dankeydemon:BAAALgADCgMJAwAAAA==.Danthrox:BAAALgADCgEJAQAAAA==.Darthneepis:BAAALgAECgcJDgAAAA==.Darthplot:BAAALgADCgMJAwAAAA==.Darwin:BAABLgAECn8VAAMYAAcJDRgyIwC2AQAYAAcJDRgyIwC2AQAbAAEJeAe1EQAvAAAAAA==.Dasmoodhayn:BAAALgAECgYJCgAAAA==.Davrock:BAAALgAECgcJBwAAAA==.Dawnglaive:BAAALgAECgMJAwAAAA==.Dayo:BAABLgAECn8ZAAIHAAcJKyWrKACCAgAHAAcJKyWrKACCAgAAAA==.',
De='Dethkløk:BAAALgAECgUJBwAAAA==.',
Di='Dibstrum:BAAALgAECgQJBAAAAA==.Dimaa:BAAALgAECgkJBwAAAA==.Dixqt:BAAALgAECgQJDQAAAA==.',
Dj='Djinn:BAAALgAECgMJAwAAAA==.',
Do='Dogbear:BAAALgADCgIJAgAAAA==.Dogfight:BAACLgAFFH8NAAIYAAMJ1B7EJwAeAQAYAAMJ1B7EJwAeAQAuAAQKfxsAAhgACAlyIzMZAOUCABgACAlyIzMZAOUCAAAA.Doilookfatou:BAAALgAECgYJCgAAAA==.Doopy:BAAALgADCgMJAwAAAA==.',
Dr='Draedawn:BAAALgADCgQJBAAAAA==.Dragonhide:BAABLgAECn8XAAIHAAgJXQiDgwBzAQAHAAgJXQiDgwBzAQAAAA==.Drailzx:BAAALgAECgYJCAAAAA==.Drakelle:BAAALgADCgIJAgAAAA==.Draxus:BAAALgAECgQJCwAAAA==.Drbigsbie:BAAALgAECgYJCgAAAA==.Dresel:BAACLgAFFH8VAAMcAAYJDyMoAAD4AQAcAAUJ2iUoAAD4AQAdAAMJ9A5MEQBeAAAuAAQKfyIABBwACQnLJj8AAOgDABwACQnLJj8AAOgDAB0ABwmrGBEyAKUBAB4AAgn9BfcpAGEAAAAA.Drewpeebahlz:BAAALgADCgcJFAABLgAECggJKAAcAPohAA==.Drezell:BAAALgADCgcJBwABLgAFFAYJFQAcAA8jAA==.Druidickhal:BAACLgAFFH8OAAMUAAQJwx5aEgALAQAUAAMJVx5aEgALAQAfAAQJaAxRDwDsAAAuAAQKfxkAAxQACAlUHGgqAAgCABQACAlUHGgqAAgCAB8ABQlfIvQuAI4BAAAA.Druindabs:BAAALgADCgUJBQAAAA==.Drybussy:BAAALgAECgMJAwAAAA==.',
Du='Dunarith:BAAALgADCgMJAwAAAA==.Dunkel:BAAALgADCgUJBQAAAA==.',
Dw='Dwarvenlight:BAAALgAECgEJAQAAAA==.',
Dy='Dyami:BAABLgAECn8iAAMcAAgJlx7wCABrAgAcAAgJlx7wCABrAgAdAAQJUhmbRQA+AQAAAA==.Dynas:BAABLgAECn8kAAMLAAgJ6BPSDwCoAQALAAgJnhHSDwCoAQAXAAYJ/REoJgBkAQAAAA==.',
Ea='Earthcake:BAACLgAFFH8HAAMIAAMJUw/YGADIAAAIAAMJUw/YGADIAAAgAAIJ6gM5HwBeAAAuAAQKfy8AAyAACAngIKgDAJMCACAACAngIKgDAJMCAAgAAQmLBeCnACcAAAAA.',
Ed='Eddiechi:BAAALgADCgYJBgABLgAFFAcJFQAYAGobAA==.Eddiedecay:BAAALgAECgUJBQABLgAFFAcJFQAYAGobAA==.Eddielich:BAACLgAFFH8VAAMYAAcJahtJAgDyAQAYAAcJahtJAgDyAQAWAAEJAAAIIQAAAAAuAAQKfy0AAxYACQlxJREBAJoCABgACQlpJZ0HAGMDABYACQlCIhEBAJoCAAAA.Eddiepope:BAAALgAECgEJAQABLgAFFAcJFQAYAGobAA==.Eddiewar:BAAALgAECgYJDwABLgAFFAcJFQAYAGobAA==.',
Eg='Eggfumonk:BAAALgAECgMJBgAAAA==.',
El='Elfpen:BAAALgADCgkJGgAAAA==.',
En='Enhancesmexy:BAAALgAECgYJBgABLgAECgYJBgAKAAAAAA==.Ents:BAAALgAECgYJDQAAAA==.',
Er='Erragal:BAAALgADCggJBAAAAA==.Eryunes:BAAALgAECgMJAwAAAA==.',
Et='Et:BAAALgAFFAMJAwABLgAFFAYJAgAKAAAAAA==.',
Eu='Euthariel:BAABLgAECn8WAAIYAAcJ+xaMMQBzAQAYAAcJ+xaMMQBzAQAAAA==.Euthindor:BAAALgADCgQJBAAAAA==.',
Ev='Evilwench:BAABLgAECn8XAAIMAAcJVA3LLgBrAQAMAAcJVA3LLgBrAQAAAA==.',
Fa='Faexi:BAAALgADCgMJAgAAAA==.Falek:BAAALgADCgUJBQAAAA==.Favii:BAAALgADCggJFgAAAA==.',
Fe='Feefiefoéfum:BAAALgAECgMJAwAAAA==.Felstórm:BAAALgADCgcJBwAAAA==.Felurián:BAABLgAECn8UAAISAAcJLRHhKQA+AQASAAcJLRHhKQA+AQAAAA==.Fexli:BAAALgADCggJBAAAAA==.',
Fi='Fiber:BAAALgADCgUJBgAAAA==.Fireteeth:BAAALgAECgEJAwAAAA==.Fizc:BAAALgADCgcJBwAAAA==.',
Fl='Flojo:BAAALgAFFAEJAQAAAA==.',
Fo='Folklore:BAABLgAECn8WAAIhAAcJfRX1CQAvAQAhAAcJfRX1CQAvAQAAAA==.Forbidi:BAAALgAECgMJBgAAAA==.',
Fr='Freaky:BAAALgAECgYJCAAAAA==.Frostytute:BAAALgAECgUJCgAAAA==.Frozown:BAAALgAECgYJEAAAAA==.Fruits:BAAALgAECgYJDwAAAA==.',
Fu='Fumanchu:BAAALgADCgMJAwAAAA==.Funfanfare:BAABLgAECn8VAAIiAAcJFhuWAQDmAQAiAAcJFhuWAQDmAQAAAA==.',
Fy='Fyvern:BAAALgADCgUJBQAAAA==.',
['Fò']='Fòrlorn:BAAALgADCgcJCAAAAA==.',
['Fö']='Fölktergeist:BAAALgAECgQJBwAAAA==.',
Ga='Gaea:BAAALgADCgEJAQAAAA==.Galaeline:BAAALgADCgkJDQAAAA==.Galram:BAABLgAECn8eAAIeAAgJ8xRnCADeAQAeAAgJ8xRnCADeAQABLgAFFAYJGgAJAFUIAA==.Gargingoyles:BAABLgAECn8iAAIYAAcJsiT3GADmAgAYAAcJsiT3GADmAgAAAA==.Garlicbred:BAAALgAECgQJBAABLgAFFAQJBwAIAEIdAA==.Gartholo:BAAALgAECgYJBgABLgAECgcJBwAKAAAAAA==.Garunah:BAAALgAECgYJCwAAAA==.',
Gi='Gimpwithmilk:BAABLgAECn8YAAIUAAgJyAnKOADxAAAUAAgJyAnKOADxAAAAAA==.Gip:BAAALgAECgIJAgAAAA==.Giselee:BAAALgADCgEJAQAAAA==.Gisellina:BAABLgAECn8dAAIcAAgJzxkIKAAYAgAcAAgJzxkIKAAYAgAAAA==.Gizzbos:BAAALgADCgUJBQAAAA==.',
Gl='Gladiatorz:BAAALgAECgcJEgABLgAECggJFwAHAF0IAA==.Glimmair:BAAALgAECgYJBgABLgAFFAUJFQAVAJsdAA==.Glimmer:BAABLgAECn8ZAAMUAAcJ3xn0EwDnAQAUAAcJ3xn0EwDnAQAfAAEJAAA7kgAOAAAAAA==.Glo:BAAALgADCggJBAAAAA==.',
Go='Gokuz:BAAALgAECgYJDgAAAA==.Goo:BAAALgAECgQJBAAAAA==.Gorbstrasz:BAAALgADCgEJAQAAAA==.',
Gr='Gregorz:BAAALgADCggJBAAAAA==.Grelda:BAAALgADCgEJAQAAAA==.Greyanna:BAAALgAECgcJCgAAAA==.Grilka:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Grimmnír:BAAALgAECgMJAwABLgAFFAYJGgARAJUeAA==.Grimrath:BAAALgAECgYJEAAAAA==.Gromthrall:BAAALgAECgIJAgAAAA==.Grumpydik:BAAALgAECgYJBgAAAA==.Grumpzilla:BAAALgAECgYJEQAAAA==.',
Gu='Gumdrops:BAAALgAECgYJDwAAAA==.Gurglem:BAAALgADCgEJAQAAAA==.Gurthrot:BAACLgAFFH8FAAIYAAIJ1hixTgCoAAAYAAIJ1hixTgCoAAAuAAQKfxsAAhgACAkxGH1GACECABgACAkxGH1GACECAAAA.',
Gw='Gworp:BAAALgADCgEJAQAAAA==.Gwynhwyfar:BAAALgAECgYJEAAAAA==.',
['Gü']='Güanentá:BAAALgAECgMJAwAAAA==.',
Ha='Haseo:BAAALgADCgYJBgAAAA==.',
Hb='Hbhealthen:BAACLgAFFH8aAAIRAAYJlR6IAQAaAgARAAYJlR6IAQAaAgAuAAQKfzUAAhEACQmCI4ABAG8DABEACQmCI4ABAG8DAAAA.Hbheathend:BAAALgAECgcJDwABLgAFFAYJGgARAJUeAA==.',
He='Heavie:BAAALgADCgYJCAAAAA==.Hellhore:BAAALgADCgkJFgAAAA==.',
Hi='Highego:BAAALgAECgEJAQAAAA==.Hitmen:BAAALgAECgcJAQAAAA==.Hitta:BAAALgAECgMJBAAAAA==.',
Hj='Hjüdas:BAAALgAECgkJBgAAAA==.',
Ho='Hobo:BAAALgADCgcJBwAAAA==.Hobodruid:BAAALgAECgEJAQAAAA==.Holdenc:BAAALgAECgYJBgABLgAECgYJCQAKAAAAAA==.Holyrandy:BAABLgAECn8hAAIHAAgJsxWnIgC7AQAHAAgJsxWnIgC7AQAAAA==.Hotzalot:BAAALgAECgYJBgAAAA==.Houla:BAAALgAECgQJBAAAAA==.Howard:BAAALgAECgcJEQAAAA==.',
Hu='Huatli:BAAALgAECgEJAQAAAA==.Hurcolo:BAAALgAECgEJAgAAAA==.Huulotta:BAAALgADCgIJAgAAAA==.',
Ia='Ianth:BAAALgAECgUJBgAAAA==.',
Ib='Ibearprofen:BAAALgAECgUJDgAAAA==.Iblees:BAAALgAECgcJDgAAAA==.',
Ic='Ichthyosis:BAAALgAECgYJDAAAAA==.Icë:BAAALgAECgYJCQAAAA==.',
Id='Idtrapdat:BAAALgAECgMJAwABLgAFFAMJAwAKAAAAAA==.',
Il='Illidarya:BAAALgADCgIJAgAAAA==.Illyana:BAABLgAECn8UAAIWAAcJLSEfDgArAgAWAAcJLSEfDgArAgAAAA==.Ilovetofish:BAAALgAECgEJAQAAAA==.Ilse:BAABLgAECn8dAAIjAAgJNB2SHgAjAgAjAAgJNB2SHgAjAgAAAA==.',
Im='Imagined:BAABLgAECn8dAAINAAgJqBq1IgDfAQANAAgJqBq1IgDfAQABLgAECggJIAARAAocAA==.',
In='Indihunter:BAAALgAECgEJAQAAAA==.Infidelity:BAAALgADCgUJBQABLgAECgcJEQAKAAAAAA==.',
Is='Iskhan:BAAALgADCgkJCQABLgAECgYJCgAKAAAAAA==.',
It='Itsmxke:BAABLgAECn8cAAIHAAYJIiOqGQDwAQAHAAYJIiOqGQDwAQAAAA==.',
Iv='Ivank:BAABLgAECn8ZAAIBAAYJ8A1FRAAkAQABAAYJ8A1FRAAkAQAAAA==.Ivannalot:BAAALgADCgkJIAAAAA==.',
Ja='Jabunken:BAACLgAFFH8LAAIjAAQJ2RkvCgBKAQAjAAQJ2RkvCgBKAQAuAAQKfx8AAyMACQkCIvQDADEDACMACQkCIvQDADEDAAcABAn+ESnqALsAAAAA.Jackiechaan:BAAALgAECgMJBAAAAA==.Jage:BAABLgAECn8VAAIkAAgJegaYIwDrAAAkAAgJegaYIwDrAAAAAA==.Jakkul:BAAALgAECgYJBwAAAA==.Jarsham:BAAALgAECgYJDQAAAA==.Jaràdan:BAAALgAECgIJAgABLgAECgkJFAAiAGYQAA==.',
Je='Jeff:BAABLgAECn8cAAMTAAgJ6xKgCgBZAQAFAAcJkQ4NQACkAQATAAgJJA2gCgBZAQAAAA==.',
Ji='Jiannaa:BAABLgAECn8sAAILAAgJNCImAwC4AgALAAgJNCImAwC4AgAAAA==.Jitzul:BAAALgADCgEJAQAAAA==.',
Jl='Jl:BAAALgAFFAIJAQABLgAFFAYJAgAKAAAAAA==.',
Jo='Johnnyderp:BAAALgAECgIJAgAAAA==.Jook:BAAALgAFFAIJAwAAAA==.Joran:BAAALgAECgMJBAAAAA==.',
Ju='Justmage:BAAALgADCgEJAQABLgAECgMJAwAKAAAAAA==.Justmonk:BAAALgAECgMJAwAAAA==.',
Jw='Jwrs:BAAALgADCgYJBgAAAA==.',
Jy='Jyaki:BAAALgAECgEJAQAAAA==.',
Ka='Kaelana:BAABLgAECn8YAAILAAgJ1hs+CgCpAgALAAgJ1hs+CgCpAgAAAA==.Kahlua:BAABLgAECn8mAAIcAAgJGBhfFQDnAQAcAAgJGBhfFQDnAQAAAA==.Kailan:BAAALgAECgYJEwABLgAECggJJAAMABAcAA==.Kailani:BAABLgAECn8eAAMUAAgJBAfMbgAJAQAUAAgJBAfMbgAJAQAfAAcJ6wl+LQCmAAAAAA==.Kaiserroll:BAAALgAECgEJAgAAAA==.Kaldro:BAAALgADCgkJFAAAAA==.Kaly:BAABLgAECn8hAAIVAAgJdgrQFABdAQAVAAgJdgrQFABdAQAAAA==.Karador:BAAALgAECgEJAQAAAA==.Kathry:BAAALgADCgkJIAAAAA==.',
Kc='Kcid:BAAALgAECgYJCgAAAA==.',
Ke='Kedibaba:BAAALgAECgYJCwAAAA==.Keeiron:BAAALgADCgYJBgABLgAECgMJBgAKAAAAAA==.Keepdreaming:BAABLgAECn8hAAIUAAgJEhHHIgBsAQAUAAgJEhHHIgBsAQAAAA==.Kellane:BAAALgAECgMJAwAAAA==.Keybricker:BAAALgAFFAQJBAAAAA==.Keymebrah:BAABLgAECn8iAAINAAgJyRzsLgC2AgANAAgJyRzsLgC2AgAAAA==.',
Kh='Khaera:BAAALgADCgQJBAAAAA==.Khansi:BAAALgADCgUJBQAAAA==.',
Ki='Killeh:BAAALgADCggJCwAAAA==.',
Kl='Kleiya:BAABLgAECn8gAAMRAAgJChwSAwByAgARAAgJChwSAwByAgAOAAEJ+hgAAAAAAAAAAA==.',
Ko='Korda:BAAALgADCgMJAwAAAA==.Korinä:BAAALgAECgYJEAAAAA==.Korveen:BAABLgAECn8kAAIMAAkJZAstCwDNAQAMAAkJZAstCwDNAQAAAA==.Kosh:BAAALgADCgkJBgAAAA==.Koyra:BAACLgAFFH8WAAMOAAYJOyIdAAAmAgAOAAUJOiUdAAAmAgAQAAMJuR92DwA0AQAuAAQKfykAAw4ACQm8JSEAAOwDAA4ACQm8JSEAAOwDABAABQnOHGUhALQBAAAA.',
Kr='Krimzin:BAAALgADCgEJAQABLgAFFAMJBQAcAKcbAA==.Krump:BAABLgAECn8cAAIEAAgJxxEtFwCfAQAEAAgJxxEtFwCfAQAAAA==.Krëyâdrón:BAAALgAECgIJAgAAAA==.',
Ku='Kubwa:BAAALgAECgMJAwAAAA==.Kungfugimp:BAAALgADCgcJBwAAAA==.Kurral:BAACLgAFFH8NAAIfAAUJaQySDAAtAQAfAAUJaQySDAAtAQAuAAQKfyQAAh8ACQkkG7sMAM0CAB8ACQkkG7sMAM0CAAAA.Kurralagos:BAABLgAECn8eAAQQAAgJ4wlSFwBDAQAQAAgJ2AhSFwBDAQAOAAYJcgrJIAAnAQARAAMJVAKBPwBuAAABLgAFFAUJDQAfAGkMAA==.Kurstina:BAAALgAECgEJAQAAAA==.Kurtîmus:BAAALgAECgQJBwAAAA==.Kuznetsov:BAAALgADCgYJBgAAAA==.Kuzushi:BAAALgADCgkJDAAAAA==.',
Ky='Kyramus:BAABLgAECn8WAAIEAAcJkyR1AgCAAgAEAAcJkyR1AgCAAgAAAA==.',
La='Laconia:BAABLgAECn80AAMOAAgJICKRAADBAgAOAAgJICKRAADBAgAQAAEJDA7LYwAvAAAAAA==.Landronor:BAAALgADCgQJBAABLgAECgYJBwAKAAAAAA==.Larox:BAAALgADCgYJCgAAAA==.Lattsatnar:BAABLgAECn8VAAIFAAcJ0xRdEwCbAQAFAAcJ0xRdEwCbAQAAAA==.',
Le='Lennel:BAAALgAECgYJCgAAAA==.Leøn:BAAALgAECgYJCwAAAA==.',
Li='Lightbrite:BAAALgADCgcJCAAAAA==.Lightstorm:BAAALgAECgMJBgAAAA==.Lilarri:BAAALgAECgEJAQABLgAECgcJCgAKAAAAAA==.Lilsnick:BAAALgAECgIJAwABLgAECgcJDgAKAAAAAA==.Lilyillidari:BAABLgAECn8aAAIlAAcJYhsNBAC+AQAlAAcJYhsNBAC+AQAAAA==.Litterbawx:BAAALgADCgYJBgAAAA==.Lizardlemons:BAAALgAECgYJEQAAAA==.',
Ll='Llanthyl:BAAALgAECgcJDgAAAA==.',
Lo='Locosmexy:BAAALgAECgQJBAABLgAECgYJBgAKAAAAAA==.Lou:BAAALgAECgEJAgAAAA==.Lovia:BAAALgAECgIJAgAAAA==.Lowdps:BAAALgAFFAEJAgABLgAFFAUJDAAdAP0VAA==.',
Lu='Luithica:BAAALgADCgUJBQAAAA==.Lunafalia:BAABLgAECn8hAAINAAgJUhWnKQC+AQANAAgJUhWnKQC+AQAAAA==.Lupon:BAAALgAECgcJAQAAAA==.Lurosa:BAACLgAFFH8PAAIUAAQJgh8fCgBgAQAUAAQJgh8fCgBgAQAuAAQKfx4ABBQACQnKIi4IAAoDABQACQnKIi4IAAoDAB8AAglNEwpoAIEAACEAAQmzIQIoAF4AAAAA.Luxeria:BAABLgAECn8eAAIHAAgJqRojLQCNAQAHAAgJqRojLQCNAQAAAA==.',
Lz='Lz:BAAALgAFFAYJAgAAAA==.',
['Lí']='Lízard:BAAALgAECgQJBAAAAA==.',
['Lî']='Lîlydan:BAAALgAECgMJBQAAAA==.',
Ma='Macready:BAACLgAFFH8JAAIEAAQJ8BswBABRAQAEAAQJ8BswBABRAQAuAAQKfx4AAgQACAnSHycGANECAAQACAnSHycGANECAAAA.Madmimm:BAAALgADCgMJAwAAAA==.Maerith:BAAALgAECgYJEAAAAA==.Magenin:BAAALgADCgYJAwAAAA==.Mahmage:BAACLgAFFH8JAAINAAQJuh+AEgB1AQANAAQJuh+AEgB1AQAuAAQKfyoAAg0ACQm0JFcLAGkDAA0ACQm0JFcLAGkDAAAA.Mairbear:BAAALgAECggJDgABLgAFFAUJFQAVAJsdAA==.Mairiachi:BAACLgAFFH8VAAIVAAUJmx2NAQDOAQAVAAUJmx2NAQDOAQAuAAQKfyQAAhUACQmDI9EDAFIDABUACQmDI9EDAFIDAAAA.Maloa:BAAALgAECgQJAgAAAA==.Marllowe:BAAALgAECgEJAQABLgAECgkJLgAcAAwfAA==.Marload:BAABLgAECn8uAAIcAAkJDB8QDADhAgAcAAkJDB8QDADhAgAAAA==.Mathy:BAABLgAECn8dAAMJAAgJURj+AgAmAgAJAAgJURj+AgAmAgAIAAgJqxhcIgARAgAAAA==.Mazaker:BAAALgADCgEJAQAAAA==.',
Me='Mearis:BAAALgAECgMJAwABLgAECggJIAARAAocAA==.Melath:BAAALgADCgkJEAAAAA==.Memesarecool:BAAALgAECgEJAQAAAA==.Meñtat:BAAALgAECgYJDgAAAA==.',
Mi='Michael:BAAALgAECgQJBAAAAA==.Midletons:BAAALgAECgYJCQAAAA==.Midran:BAABLgAECn8VAAIeAAgJJRarCQBEAgAeAAgJJRarCQBEAgAAAA==.Minbari:BAAALgADCgQJCgABLgADCgkJBgAKAAAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Minttea:BAAALgAECgYJBgAAAA==.Misfirë:BAAALgAECgcJEQAAAA==.',
Mo='Mojó:BAAALgAECggJEwAAAA==.Momenta:BAAALgADCgEJAQAAAA==.Moobubble:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.Moogul:BAAALgADCgUJBQAAAA==.Moonanoke:BAAALgADCgkJDQAAAA==.Moorawr:BAAALgADCgYJBgAAAA==.Moovoker:BAABLgAECn8fAAMQAAgJMR9tBABwAgAQAAcJaR1tBABwAgAOAAMJFSGMIgAWAQAAAA==.Mordran:BAAALgADCgMJAwAAAA==.Morseques:BAABLgAECn8hAAIYAAgJgiFJDQBbAgAYAAgJgiFJDQBbAgAAAA==.Mortimirr:BAAALgAECgEJAQAAAA==.Mozi:BAAALgAECgUJEwAAAA==.',
Mu='Muffins:BAAALgAECgUJCAAAAA==.Muggy:BAACLgAFFH8MAAMYAAQJDSQ+HgAnAQAYAAQJDSQ+HgAnAQAWAAEJAADxEgBbAAAuAAQKfzoAAxgACQm4JWMDAP4CABgACQm4JWMDAP4CABYABAmXGOMjACIBAAAA.Murphy:BAAALgADCgUJBQAAAA==.Mushrodazz:BAAALgAECgUJCwAAAA==.',
Mx='Mxke:BAAALgADCgQJBAABLgAECgYJHAAHACIjAA==.',
My='Mysts:BAAALgAECgYJEgABLgAFFAYJGgARAO4mAA==.',
Na='Narama:BAACLgAFFH8NAAMBAAUJtQXRIgAVAQABAAQJtQXRIgAVAQAmAAEJAABVBwBIAAAuAAQKfyMAAgEACQnZGEwfAJwCAAEACQnZGEwfAJwCAAAA.Naturaljuice:BAAALgADCgcJBwABLgAECgUJBwAKAAAAAA==.Nazari:BAAALgAECgUJBQAAAA==.',
Ne='Necrid:BAAALgAECgEJAgABLgAECgEJAgAKAAAAAA==.Neverlucky:BAAALgAECgEJAgAAAA==.Nezy:BAAALgAECgMJAwAAAA==.',
Ni='Ninæ:BAAALgAECgYJBwABLgAFFAQJDwAUAD8dAA==.Nitewïng:BAAALgADCgUJBgAAAA==.',
No='Nootao:BAACLgAFFH8GAAIDAAQJSRSACwDpAAADAAQJSRSACwDpAAAuAAQKfxoAAgMABwmYJIUQAHgCAAMABwmYJIUQAHgCAAAA.Nootvoker:BAAALgAECgUJCAABLgAFFAQJBgADAEkUAA==.Noraline:BAAALgAECgYJCAAAAA==.Normac:BAAALgADCgYJCwAAAA==.Nou:BAAALgAECgMJBAABLgAFFAQJBgADAEkUAA==.',
Ny='Nyoz:BAAALgAECgMJBgAAAA==.Nyxxadra:BAABLgAECn8fAAIBAAgJFw/VIwCiAQABAAgJFw/VIwCiAQAAAA==.',
Ol='Oliaa:BAAALgADCgUJBQAAAA==.',
Om='Omegadeed:BAABLgAECn8hAAIBAAgJKQ5XLwBuAQABAAgJKQ5XLwBuAQAAAA==.',
On='Onne:BAAALgADCgkJDAAAAA==.',
Or='Oraculus:BAACLgAFFH8VAAIUAAYJmxNHBADIAQAUAAYJmxNHBADIAQAuAAQKfyQAAhQACQl1FdcgAD0CABQACQl1FdcgAD0CAAAA.Orchunter:BAAALgADCgcJEgAAAA==.Orcinus:BAAALgAECgYJEQAAAA==.Orcward:BAAALgADCgcJDgABLgAECggJKAAcAPohAA==.Ordinem:BAABLgAECn8mAAINAAgJaR2pFwAfAgANAAgJaR2pFwAfAgAAAA==.Originality:BAAALgAECgQJBwAAAA==.Orlandodoom:BAAALgADCgMJAwAAAA==.Orvar:BAABLgAECn8oAAQcAAgJ+iFKBAC8AgAcAAgJ+iFKBAC8AgAdAAUJDhhOQwBJAQAeAAEJ4wH+MgAkAAAAAA==.',
Pa='Pakaru:BAABLgAECn8ZAAIHAAgJXx5nNwBFAgAHAAgJXx5nNwBFAgAAAA==.Palpapeen:BAAALgAECgEJAQAAAA==.Pam:BAACLgAFFH8RAAMPAAUJCyBfAQCOAQAPAAUJCyBfAQCOAQASAAIJwQoxLACVAAAuAAQKfzAAAw8ACAlZJkICAHEDAA8ACAlZJkICAHEDABIABgm/HGNFAN4BAAAA.Panpanpan:BAAALgAECgYJDwAAAA==.',
Pe='Penry:BAAALgAECgEJAQAAAA==.Peorä:BAABLgAECn8YAAIMAAgJrwbEFwBAAQAMAAgJrwbEFwBAAQAAAA==.Peremo:BAABLgAECn8lAAIYAAkJDyGiBwBjAwAYAAkJDyGiBwBjAwAAAA==.Perfectdark:BAACLgAFFH8TAAISAAYJpRmPAgDVAQASAAYJpRmPAgDVAQAuAAQKfyAAAhIACQkCIpMEAH4DABIACQkCIpMEAH4DAAAA.Perse:BAAALgAECgYJEQAAAA==.Petdamage:BAAALgAECgEJAQAAAA==.',
Ph='Phutz:BAAALgADCgEJAQAAAA==.',
Pi='Pickles:BAABLgAECn8bAAInAAgJ+xtcAQBRAgAnAAgJ+xtcAQBRAgAAAA==.Pieper:BAAALgADCggJBAAAAA==.Pipa:BAABLgAECn8jAAIIAAgJDCKABQCbAgAIAAgJDCKABQCbAgAAAA==.',
Pl='Plagueis:BAAALgADCgYJCwABLgAECggJNAAOACAiAA==.Plaguexrat:BAAALgAECgMJBAAAAA==.Plooptwo:BAABLgAECn8UAAIHAAYJdg95SwAoAQAHAAYJdg95SwAoAQAAAA==.Plutó:BAAALgADCgIJAwAAAA==.',
Po='Poacher:BAAALgAECgYJCgAAAA==.Poogli:BAAALgAECgYJDAAAAA==.Pooky:BAAALgAECgMJBAAAAA==.Poppapally:BAAALgAECgEJAQAAAA==.Porque:BAABLgAECn8kAAMNAAgJsB5nEABZAgANAAgJsB5nEABZAgAiAAIJyAtoFgBnAAAAAA==.Powar:BAAALgADCgQJBAAAAA==.',
Pr='Protolennel:BAAALgADCgkJHQABLgAECgYJCgAKAAAAAA==.Provence:BAAALgAECgMJBQAAAA==.',
Py='Pyreynna:BAABLgAECn8UAAIBAAYJgRd6OQBHAQABAAYJgRd6OQBHAQAAAA==.',
Qs='Qsteve:BAAALgADCgYJAwAAAA==.',
Qu='Quelamonk:BAAALgAECgcJBwAAAA==.Queso:BAAALgADCgYJBgABLgAFFAMJBgASAMsXAA==.Quinmora:BAAALgADCgcJDgAAAA==.',
Ra='Ragarn:BAAALgADCgMJAwAAAA==.Ralnorin:BAAALgAECgQJDgAAAA==.Rarren:BAAALgADCgcJEAAAAA==.Raschild:BAAALgAECgUJCgAAAA==.',
Re='Realfrojd:BAABLgAECn8gAAIWAAgJ2w21EwDoAAAWAAgJ2w21EwDoAAAAAA==.Reallybigdk:BAAALgADCgIJAgAAAA==.Regginunchuk:BAABLgAECn8aAAIDAAgJ7BxBBQBJAgADAAgJ7BxBBQBJAgAAAA==.Rejownation:BAAALgAECgcJEAAAAA==.Releronastus:BAAALgAECgYJBwAAAA==.Relief:BAABLgAECn8bAAMUAAgJYSTGBwAQAwAUAAgJYSTGBwAQAwAfAAcJRBzHEACKAQAAAA==.Rextallion:BAABLgAECn8gAAIHAAgJbB3TDABeAgAHAAgJbB3TDABeAgAAAA==.Reyson:BAABLgAECn8jAAMNAAgJKxlwJQDRAQANAAgJyxhwJQDRAQAiAAEJASA0GwA/AAAAAA==.',
Rh='Rhinoe:BAAALgAECgEJAgAAAA==.Rholden:BAAALgADCgMJAwAAAA==.Rhun:BAAALgADCgQJBAAAAA==.Rhunon:BAABLgAECn8WAAIYAAkJYxHyIQC8AQAYAAkJYxHyIQC8AQAAAA==.',
Ri='Ridor:BAAALgAECgIJAgAAAA==.Rinslaughter:BAABLgAECn8jAAIYAAgJlg9dOgBRAQAYAAgJlg9dOgBRAQAAAA==.Rinthia:BAABLgAECn8kAAIMAAgJEBygCAD7AQAMAAgJEBygCAD7AQAAAA==.Ripyeet:BAACLgAFFH8OAAIHAAQJCBo6CQBrAQAHAAQJCBo6CQBrAQAuAAQKfywAAgcACQmpIwcDAPkCAAcACQmpIwcDAPkCAAAA.',
Ro='Robinhood:BAAALgAECgcJBwABLgAFFAQJCgAFAA0cAA==.Rolden:BAAALgAECgQJDQAAAA==.Ron:BAAALgADCgUJBQAAAA==.',
Ru='Ruffaf:BAAALgADCgEJAQAAAA==.Rukaji:BAABLgAECn8VAAMTAAcJXxmJBwCXAQATAAcJSBmJBwCXAQAEAAQJ2xq+IQAwAQAAAA==.',
Ry='Ryuuter:BAAALgAECgcJDAAAAA==.',
['Rå']='Rå:BAAALgADCgUJBQAAAA==.Rågè:BAAALgAECgkJEwAAAA==.',
Sa='Saebelle:BAAALgADCggJEwAAAA==.Saetheline:BAABLgAECn8hAAMFAAgJMg/EEgChAQAFAAgJwA7EEgChAQATAAMJmA4qGAC5AAAAAA==.Sandybeans:BAAALgADCgYJDgAAAA==.Sanko:BAAALgADCgEJAQAAAA==.Sarkang:BAAALgAECgMJBAAAAA==.',
Sc='Schkate:BAABLgAECn8UAAIIAAgJwByhCwAwAgAIAAgJwByhCwAwAgAAAA==.Schutze:BAACLgAFFH8PAAIeAAQJDhbaBABYAQAeAAQJDhbaBABYAQAuAAQKfxsAAx4ACQlPI0UDAPcCAB4ACQlPI0UDAPcCAB0ABAmyDkpiALcAAAAA.Scorn:BAAALgADCgMJAwAAAA==.Scrammbles:BAAALgAECgYJDAAAAA==.Scråmmbles:BAAALgAECgEJAQAAAA==.',
Sd='Sdadfeg:BAABLgAECn8hAAIJAAgJXSKfAQCDAgAJAAgJXSKfAQCDAgAAAA==.',
Se='Selenagomez:BAABLgAFFH8JAAIDAAMJxBgRCQAIAQADAAMJxBgRCQAIAQAAAA==.Selia:BAAALgAECgYJDwAAAA==.Senlorin:BAAALgAECgMJAwAAAA==.Sephroth:BAAALgAECgUJBwAAAA==.',
Sh='Shabobado:BAAALgAECgYJEQAAAA==.Shaboo:BAAALgADCgQJBAAAAA==.Shadowleaf:BAAALgADCgkJEgAAAA==.Shallo:BAAALgADCgUJBQAAAA==.Shatoya:BAAALgADCggJFQAAAA==.Shawoman:BAAALgAECgEJAQAAAA==.Shayluh:BAAALgADCgMJAwAAAA==.Shedoo:BAAALgAECgYJCQAAAA==.Shhum:BAAALgAECgMJAwAAAA==.Shinokage:BAAALgAECgIJAgAAAA==.Shinrei:BAAALgAECgYJDAAAAA==.Shmoople:BAAALgADCgYJCwAAAA==.Shumazing:BAAALgADCgYJBgABLgAECgYJBgAKAAAAAA==.Shuten:BAAALgAECgEJAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.Shìlô:BAAALgAECgcJDQAAAA==.',
Si='Sibble:BAAALgADCgkJCQAAAA==.Silbanuz:BAAALgAECggJDAAAAA==.Simplejakk:BAAALgADCgYJCwAAAA==.Sinterklaas:BAABLgAECn8fAAMIAAgJQhEfGACkAQAIAAgJQhEfGACkAQAgAAYJ+gbTUwD2AAAAAA==.Siqma:BAAALgAECgUJBgAAAA==.',
Sj='Sj:BAAALgAECgEJAQABLgAFFAcJEAANAMsiAA==.',
Sk='Skydeed:BAAALgAECgQJBQAAAA==.',
Sl='Slapfurr:BAAALgAECgEJAwAAAA==.Slark:BAABLgAECn8kAAMaAAgJSBqzDwCsAQAaAAgJSBqzDwCsAQADAAEJGwJ7VgAbAAAAAA==.Slawth:BAAALgADCgcJAgAAAA==.Slayermonde:BAAALgADCggJBAAAAA==.Slimjerry:BAAALgAECgEJAQAAAA==.Sliprain:BAAALgAECgcJCQAAAA==.',
Sm='Smexydemon:BAAALgAECgMJAwABLgAECgYJBgAKAAAAAA==.Smexydubs:BAAALgAECgYJBgAAAA==.Smexyexpress:BAAALgAECgUJBQABLgAECgYJBgAKAAAAAA==.Smexytimes:BAAALgAECgEJAQABLgAECgYJBgAKAAAAAA==.Smeyplus:BAACLgAFFH8ZAAIHAAYJYRz6AQDNAQAHAAYJYRz6AQDNAQAuAAQKfyYAAgcACQmCJAMHAGADAAcACQmCJAMHAGADAAAA.Smokincrayon:BAAALgAECgcJAwAAAA==.',
Sn='Snickeris:BAAALgAECgcJDgAAAA==.Snofawl:BAABLgAECn8uAAIQAAgJ8BgQCgDpAQAQAAgJ8BgQCgDpAQAAAA==.Snoranir:BAABLgAECn8cAAUhAAYJSRq5EwAzAQAhAAUJ2BS5EwAzAQAUAAYJHBx5LgAkAQAGAAMJLxy/DgDtAAAfAAQJSAuGdQBNAAAAAA==.',
So='Sorisa:BAAALgADCgcJBwAAAA==.Sovereign:BAABLgAFFH8OAAMOAAYJPhkxAQCzAQAOAAUJYBUxAQCzAQAQAAQJPxfYCABqAQAAAA==.',
Sp='Spanfrontals:BAABLgAECn8cAAMlAAgJZBnhCgC1AQASAAcJ9xgVRADjAQAlAAYJtBrhCgC1AQABLgAFFAQJBAAKAAAAAA==.Spiko:BAAALgAECgUJBQABLgAECgYJCQAKAAAAAA==.Spillthetea:BAAALgADCgUJCAAAAA==.Spite:BAABLgAECn8gAAIBAAgJ3BYVHgDAAQABAAgJ3BYVHgDAAQAAAA==.',
Sq='Squidd:BAAALgAECgUJCgAAAA==.',
St='Stars:BAAALgAFFAMJAwAAAA==.Steakshot:BAAALgADCgIJAgAAAA==.Steelcow:BAAALgADCgEJAQAAAA==.Stevengotwow:BAAALgAECgcJBwAAAA==.Stryjix:BAAALgADCgQJBAAAAA==.Stuhmp:BAAALgADCgEJAQAAAA==.',
Su='Sullie:BAAALgAECgIJAgAAAA==.Sunhorn:BAAALgADCggJCAAAAA==.Sunset:BAAALgAECgQJBAAAAA==.Sureno:BAAALgAECgYJCwAAAA==.Suslord:BAAALgADCgcJCgAAAA==.',
Sx='Sxybznitch:BAAALgAECgYJCgAAAA==.Sxyhealz:BAABLgAECn8lAAILAAgJnhYkDwCxAQALAAgJnhYkDwCxAQAAAA==.',
Sy='Syntherien:BAAALgADCgEJAQAAAA==.',
Sz='Szandöra:BAABLgAECn8gAAIMAAkJQgNTUgCAAAAMAAkJQgNTUgCAAAAAAA==.',
['Sü']='Süture:BAABLgAECn8eAAIoAAkJkgNfSQDeAAAoAAkJkgNfSQDeAAAAAA==.',
Ta='Taco:BAAALgAECgUJBQAAAA==.Taggaz:BAAALgAECgYJCAAAAA==.Tandrelia:BAAALgAECgEJAQAAAA==.Tanndari:BAAALgAECgEJAQAAAA==.Tarragon:BAAALgAECgIJBAAAAA==.Tartare:BAAALgAECgYJEAAAAA==.Tashiice:BAAALgADCgYJBgABLgAECggJHQAcAM8ZAA==.',
Te='Teriheals:BAAALgADCgkJCQAAAA==.Terishon:BAAALgAECgYJCgAAAA==.',
Th='Thatsmxke:BAAALgADCgUJBQABLgAECgYJHAAHACIjAA==.Thaurex:BAAALgADCgkJEQAAAA==.Theophania:BAAALgAECgUJBgAAAA==.Thogo:BAABLgAECn8bAAIFAAgJSh9AEgC+AgAFAAgJSh9AEgC+AgAAAA==.',
Ti='Tiger:BAAALgAECgEJAQAAAA==.Tinykitsune:BAAALgADCgMJAwAAAA==.Tipnontotems:BAAALgADCgcJDQAAAA==.',
To='Toadeater:BAAALgAECgEJAgAAAA==.Tokiya:BAAALgAECgMJAwAAAA==.Tomerd:BAAALgAECgEJAQABLgAECggJIgAjAIchAA==.Tomerto:BAABLgAECn8iAAMjAAgJhyEIDQCxAgAjAAgJhyEIDQCxAgAHAAIJ9AkK0AA1AAAAAA==.Toobeastly:BAAALgAECgUJBwAAAA==.Tooner:BAABLgAECn8WAAIUAAcJ4A+4JQBXAQAUAAcJ4A+4JQBXAQAAAA==.Torques:BAAALgADCgYJDAAAAA==.Toymonkey:BAAALgAECgMJBQAAAA==.',
Tr='Trielas:BAAALgADCgMJAwAAAA==.Tryingmybest:BAAALgAECgQJBAABLgAFFAQJBAAKAAAAAA==.',
Tu='Tuxedomaask:BAAALgAECgMJBQABLgAECgUJCgAKAAAAAA==.',
Tw='Twentyone:BAABLgAECn8qAAIhAAgJXibLAAByAwAhAAgJXibLAAByAwAAAA==.Twiggz:BAAALgAECgUJBQABLgAECggJJAANALAeAA==.Twozero:BAAALgAECgYJCgAAAA==.',
Ty='Tyestaumin:BAAALgAECgQJBAABLgAECgYJBwAKAAAAAA==.Tyiesticus:BAAALgAECgYJBwAAAA==.Tyralen:BAABLgAECn8gAAIcAAgJqBn1GwBfAgAcAAgJqBn1GwBfAgABLgAECggJIQAhAOUTAA==.Tyrandras:BAABLgAECn8hAAIhAAgJ5ROeBgCPAQAhAAgJ5ROeBgCPAQAAAA==.Tyrec:BAAALgAECgUJBgABLgAECgUJCgAKAAAAAA==.Tyrïon:BAAALgAECgYJDgAAAA==.',
['Tö']='Töxxy:BAAALgAECgIJAgAAAA==.',
Ul='Uldrag:BAAALgAECgYJCwAAAA==.',
Va='Vaero:BAABLgAECn8tAAMSAAgJGCIEBACvAgASAAgJGCIEBACvAgAlAAEJWwd4GQAtAAAAAA==.Vandenar:BAABLgAECn8SAAISAAYJrhdaRADYAAASAAYJrhdaRADYAAAAAA==.Varju:BAAALgAECgYJDgAAAA==.Vauromoth:BAAALgADCgEJAQAAAA==.',
Vd='Vdarkadin:BAAALgADCgEJAQABLgAECgYJAQAKAAAAAA==.Vdarkdevour:BAAALgAECgYJAQAAAA==.Vdarksmonk:BAAALgAECgEJAQABLgAECgYJAQAKAAAAAA==.',
Ve='Vee:BAAALgADCgcJBwAAAA==.Velyssa:BAAALgADCgcJBwABLgAECgcJFgAHAL4ZAA==.Venandi:BAAALgADCgcJCQABLgAECggJFwAXAFAYAA==.Venni:BAAALgAECgQJBQAAAA==.Venoshock:BAAALgADCgEJAQAAAA==.',
Vi='Vibez:BAAALgAECgEJAQAAAA==.Vibin:BAABLgAECn8cAAIRAAgJZhiwCQCBAQARAAgJZhiwCQCBAQAAAA==.Vineeshewah:BAABLgAECn8WAAImAAcJyhtKAQAQAgAmAAcJyhtKAQAQAgAAAA==.Vision:BAAALgAECgEJAgAAAA==.Vivi:BAAALgAECgUJBQAAAA==.Vizu:BAAALgADCgcJBwAAAA==.',
Vo='Voruna:BAAALgAECgYJBgAAAA==.',
Wa='Wantedd:BAAALgAECgYJCQAAAA==.',
Wh='Whalend:BAAALgAECggJEwAAAA==.',
Wi='Wilbo:BAABLgAFFH8HAAMgAAMJ6hJzFwCZAAAgAAMJ6hJzFwCZAAAIAAEJUgGLMwAvAAABLgAFFAMJDQAYANQeAA==.Wilbodragons:BAAALgADCgMJAwABLgAFFAMJDQAYANQeAA==.Wily:BAABLgAECn8YAAIBAAYJ6geyUAD+AAABAAYJ6geyUAD+AAAAAA==.Winton:BAAALgADCgUJBQAAAA==.Wisperwing:BAAALgAECgQJDgAAAA==.',
Wo='Wolfdrudu:BAAALgAECgUJBQAAAA==.Worldfire:BAABLgAECn8YAAINAAYJxAnQaAAJAQANAAYJxAnQaAAJAQAAAA==.Wormadina:BAAALgAECgMJBAAAAA==.Wormszer:BAAALgAECgYJCwAAAA==.Woth:BAAALgAECgUJBwAAAA==.',
Wr='Wrecka:BAABLgAECn8iAAMBAAgJqCLFCgBiAgABAAgJqCLFCgBiAgAmAAEJAABNNwAlAAAAAA==.',
Ww='Ww:BAAALgAECgcJCAABLgAFFAYJAgAKAAAAAA==.',
Wy='Wylds:BAAALgAECgYJCQABLgAFFAYJGgARAO4mAA==.Wyldvyrus:BAAALgADCgUJBQAAAA==.Wynds:BAACLgAFFH8aAAIRAAYJ7iYfAAC3AgARAAYJ7iYfAAC3AgAuAAQKfyYAAhEACQk3JYwAALQDABEACQk3JYwAALQDAAAA.Wyrsa:BAABLgAECn8YAAMWAAgJVBVECQCDAQAWAAgJ9RRECQCDAQAYAAYJ5RAKkwBaAQAAAA==.Wyrsathuzad:BAAALgADCgUJBQAAAA==.',
Xa='Xaro:BAAALgADCgMJAwAAAA==.',
Xe='Xelock:BAAALgAECgcJBwAAAA==.',
Xi='Xi:BAABLgAECn8hAAIRAAgJSQtBCgB0AQARAAgJSQtBCgB0AQAAAA==.Xiaozhi:BAEBLgAECn8WAAIaAAcJ+yLZAwCrAgAaAAcJ+yLZAwCrAgAAAA==.',
Xz='Xzariana:BAAALgAECgYJEQAAAA==.',
Ya='Yakor:BAAALgAECgYJCwAAAA==.Yakub:BAACLgAFFH8MAAMdAAUJ/RUGCQDxAAAdAAMJ4RgGCQDxAAAcAAQJcQ/hHwDQAAAuAAQKfxUAAx0ACQmEHcUMAN8CAB0ACQnJG8UMAN8CABwABQmRHNIaAL8BAAAA.',
Ye='Yenalda:BAAALgAECggJCAAAAA==.Yennefer:BAAALgADCgcJBwAAAA==.Yeobsuirad:BAAALgAECgEJBQAAAA==.',
Yo='Yodda:BAAALgAECgYJDgAAAA==.',
['Yë']='Yëëter:BAAALgAECgIJAgAAAA==.',
Za='Zach:BAABLgAECn8ZAAIEAAYJZiI4BgDuAQAEAAYJZiI4BgDuAQAAAA==.Zached:BAAALgADCgYJBgABLgAECgYJGQAEAGYiAA==.Zaeix:BAAALgADCgcJBwAAAA==.Zaionis:BAAALgAECgUJCAAAAA==.Zalius:BAAALgAECgUJDQAAAA==.Zanori:BAABLgAECn8eAAMbAAgJPBMOBAB1AQAYAAgJdBLOXgDWAQAbAAcJdQ4OBAB1AQAAAA==.Zansijo:BAAALgAECgIJAgABLgAECggJHgAbADwTAA==.Zarienia:BAAALgAECgYJCgAAAA==.',
Ze='Zedmann:BAAALgADCgcJEwABLgAECgYJBwAKAAAAAA==.Zellyne:BAACLgAFFH8PAAIUAAQJPx2UCgBZAQAUAAQJPx2UCgBZAQAuAAQKfx8AAhQACQn+I20FADYDABQACQn+I20FADYDAAAA.Zenstiller:BAAALgADCgEJAQAAAA==.Zentho:BAAALgADCgYJBwAAAA==.',
Zo='Zom:BAAALgADCgkJCQAAAA==.Zorriya:BAABLgAECn8UAAIcAAgJ9hF6GwC7AQAcAAgJ9hF6GwC7AQAAAA==.Zovhia:BAAALgAECgYJEQAAAA==.',
Zy='Zygo:BAAALgADCgQJBQAAAA==.',
['Zø']='Zød:BAAALgADCgcJBwABLgAECggJIAARAAocAA==.',
['Ár']='Áries:BAAALgADCgUJBQAAAA==.',
['Çò']='Çòñvíçtíòñ:BAAALgAECgYJCQAAAA==.',
['Ìf']='Ìfrìt:BAAALgAECgcJDgAAAA==.',
['Ýu']='Ýuno:BAABLgAECn8VAAIoAAgJSRGSJwC8AQAoAAgJSRGSJwC8AQAAAA==.',
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

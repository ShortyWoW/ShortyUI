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

local lookup = {'Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Balance','Druid-Feral','Priest-Shadow','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','DemonHunter-Havoc','Druid-Guardian','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw','DeathKnight-Blood','Warlock-Affliction','Shaman-Elemental','Evoker-Preservation','Mage-Fire','Shaman-Restoration','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aakkulay:BAAALgAECgEJAgAAAA==.',
Ab='Absofsteels:BAAALgAECgYJEgAAAA==.',
Ac='Acaric:BAABLgAECn8hAAIBAAgJ6gRtdAAoAQABAAgJ6gRtdAAoAQAAAA==.Ache:BAAALgAFFAMJAwAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8dAAICAAkJRBaDIgA2AgACAAkJRBaDIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCggJDQAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgcJBwAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAECggJDwADAAAAAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alcaholic:BAAALgAECgEJAQABLgAECggJIAAEAIUfAA==.Alchemist:BAAALgADCggJFAAAAA==.Alidor:BAAALgAECgMJBAAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgQJCgAAAA==.Altharoth:BAAALgAECgQJCwAAAA==.',
Am='Amira:BAACLgAFFH8RAAIFAAUJ7COPAQDuAQAFAAUJ7COPAQDuAQAuAAQKfx4AAgUACAmMJWoCAEUDAAUACAmMJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.',
An='Anteiku:BAAALgAECgIJAwAAAA==.Anthiva:BAABLgAECn8RAAIGAAYJxA+ZTAATAQAGAAYJxA+ZTAATAQAAAA==.',
Ar='Arauial:BAAALgAECgYJDQAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8IAAICAAMJLhGoKAD3AAACAAMJLhGoKAD3AAAuAAQKfygAAgIACAlmGbYgAEECAAIACAlmGbYgAEECAAAA.Arizann:BAABLgAECn8cAAQHAAYJKyA3FgATAgAHAAYJKyA3FgATAgAIAAMJ5gyxRQBoAAAJAAEJyAvjJQA5AAAAAA==.Arobotpr:BAABLgAECn8fAAIKAAgJJxeIDQDxAQAKAAgJJxeIDQDxAQAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgAECgEJAQAAAA==.Astaren:BAAALgAECgMJBwAAAA==.Asuran:BAABLgAECn8UAAMLAAYJsiK8CQDXAQALAAYJ6iC8CQDXAQAMAAYJWx9tGgCUAQAAAA==.',
At='Atem:BAAALgAECgQJBgAAAA==.',
Au='Aulinn:BAAALgAECgEJAQAAAA==.Aurelianus:BAAALgAECgcJEwAAAA==.',
Av='Avalanche:BAAALgAECgUJCQAAAA==.',
Az='Azaris:BAABLgAECn8sAAIKAAkJdxjLBwBQAgAKAAkJdxjLBwBQAgAAAA==.',
Ba='Baelrog:BAAALgAECgUJCwAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMGAAkJBBLnRwDUAQAGAAkJBBLnRwDUAQANAAIJQgoGIAAsAAAAAA==.Baranina:BAACLgAFFH8NAAMCAAUJtiDKBwAnAQACAAMJViHKBwAnAQAOAAMJQxxtEgCYAAAuAAQKfycABA4ACAnTI0kDACkCAA4ACAkdIkkDACkCAAIABQmOHwk2ANYBAA8AAwkuIVcbAB8BAAAA.Barricaded:BAAALgAECgYJCAAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJCQADAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgADCgMJAwAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAABLgAECn8fAAIPAAgJrBgeCwDzAQAPAAgJrBgeCwDzAQAAAA==.Benji:BAEBLgAECn8VAAMBAAYJfBsJewAbAQABAAYJfBsJewAbAQAQAAEJeQYtIgAhAAAAAA==.',
Bi='Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blindaf:BAAALgAECgYJEAAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8aAAIRAAcJqhFiHgAwAQARAAcJqhFiHgAwAQAAAA==.Blite:BAAALgADCggJFgAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8bAAMSAAgJMQXVZgAgAQASAAgJMQXVZgAgAQATAAQJQAercgCxAAAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8KAAIHAAIJKQL9OgBdAAAHAAIJKQL9OgBdAAAuAAQKfxsAAgcACAl8D6YlAJ0BAAcACAl8D6YlAJ0BAAAA.Blueeyearch:BAAALgAECgUJDwAAAA==.',
Bo='Bolgan:BAAALgAECgMJBQAAAA==.Bonedecay:BAAALgAECgEJAQAAAA==.Boomadk:BAACLgAFFH8KAAIUAAQJcxOKTQD0AAAUAAQJcxOKTQD0AAAuAAQKfx4AAxQACAlgIj8fAMYCABQACAnZIT8fAMYCABUABwmfH9gCAHsCAAAA.Boomapriest:BAAALgAECgcJCQAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAAALgAECggJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgQJCAAAAA==.Brassybella:BAAALgAECgYJCgAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAAALgAECgMJBwAAAA==.Briochebun:BAABLgAECn8dAAISAAkJsxviIACnAgASAAkJsxviIACnAgAAAA==.',
Bu='Bustin:BAABLgAECn8UAAISAAgJLxoFHAAgAgASAAgJLxoFHAAgAgAAAA==.',
Bw='Bwangifer:BAABLgAECn8fAAINAAgJehS+BwBvAQANAAgJehS+BwBvAQAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgADCgYJDAABLgAECgcJIQAPAMwfAA==.Caitriona:BAAALgADCgMJAwABLgADCgUJBwADAAAAAA==.Cannala:BAAALgADCgUJEgAAAA==.Cargae:BAAALgADCgcJBwAAAA==.Cassios:BAABLgAECn8bAAIRAAgJSRbUEgCeAQARAAgJSRbUEgCeAQAAAA==.',
Ce='Celathel:BAAALgAECgUJCwAAAA==.Cellysia:BAABLgAECn8dAAMFAAgJTQWSJQAdAQAFAAgJTQWSJQAdAQAKAAcJZQLbNAC6AAAAAA==.Celsìus:BAABLgAECn8XAAIBAAYJbhNLlQDoAAABAAYJbxNLlQDoAAAAAA==.Ceramyth:BAAALgAECgQJCQAAAA==.Ceres:BAABLgAECn8fAAIWAAgJ9hQ2BADLAQAWAAgJ9hQ2BADLAQAAAA==.Cesara:BAABLgAECn8sAAMKAAkJlCC1AgDkAgAKAAkJlCC1AgDkAgAFAAEJ8gcffwAzAAAAAA==.',
Ch='Chaahck:BAAALgADCgkJEgAAAA==.Chal:BAAALgAECgUJBwAAAA==.Chbribs:BAAALgAECgUJDQAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8nAAIBAAgJ9yBMHABAAgABAAgJ9yBMHABAAgAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgcJDgAAAA==.Columbina:BAACLgAFFH8TAAIGAAUJwA80FAAwAQAGAAUJwA80FAAwAQAuAAQKfxoAAgYABwmgGbJEAOEBAAYABwmgGbJEAOEBAAAA.Comma:BAABLgAECn8UAAILAAcJFxKvHABjAQALAAcJFxKvHABjAQAAAA==.Cooperhowerd:BAAALgADCggJFgAAAA==.Corn:BAAALgAECgcJEwAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAABLgAECn8yAAMXAAkJBiGjAQDSAgAXAAkJBiGjAQDSAgALAAIJNRAzKwBpAAAAAA==.Crackundead:BAAALgADCgEJAQAAAA==.Cravens:BAAALgADCgcJCgAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8fAAIHAAgJQx4SFAApAgAHAAgJQx4SFAApAgAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgAECgQJDAAAAA==.Daen:BAAALgADCgcJCgAAAA==.Dagadus:BAAALgADCgEJAQAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgYJCgAAAA==.Damerot:BAAALgAFFAIJAgAAAA==.Dandity:BAAALgAECgcJBwAAAA==.Dangerous:BAAALgAECgEJAQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgEJAQAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAACLgAFFH8GAAIUAAIJ7CJeXwC8AAAUAAIJ7CJeXwC8AAAuAAQKfxcAAhQACAn5I8QcABwCABQACAn5I8QcABwCAAAA.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAECgYJCgAAAA==.Deathviix:BAAALgADCgQJBgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAAALgAECggJBQAAAA==.Delphina:BAAALgADCgQJAwAAAA==.Demini:BAAALgADCggJDwAAAA==.Demisê:BAAALgAECgcJEwAAAA==.Demonessa:BAAALgAECgcJEQAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAABLgAECn8WAAMYAAcJkBGxGwBgAQAYAAcJVBGxGwBgAQAZAAYJtQzuHgA3AQAAAA==.Desso:BAABLgAECn8bAAIRAAYJPBKRIAAhAQARAAYJPBKRIAAhAQAAAA==.Devilskin:BAAALgAECgMJAwAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAAAAA==.Dillinger:BAABLgAECn8VAAIJAAYJNw6bDwAfAQAJAAYJNw6bDwAfAQAAAA==.Dingodgaf:BAABLgAECn8VAAISAAcJGwS9lADFAAASAAcJGwS9lADFAAAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8XAAIBAAYJKA9XbwAyAQABAAYJKA9XbwAyAQAAAA==.',
Dr='Dragonmynutz:BAAALgAECgEJAQABLgAECgQJBAADAAAAAA==.Draknarok:BAAALgAECggJEgAAAA==.Dranius:BAABLgAECn8WAAIBAAcJGBQeiQDAAQABAAcJGBQeiQDAAQAAAA==.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAAALgAECgQJCQAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAABLgAECn8kAAIaAAgJBhumFQA1AgAaAAgJBhumFQA1AgAAAA==.Driztette:BAAALgAECgUJDwAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgAAAA==.Drystine:BAABLgAECn8eAAIbAAgJKR1UBgBBAgAbAAgJKR1UBgBBAgAAAA==.',
Du='Dubber:BAAALgADCggJCQAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgUJDQAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Ei='Eillaura:BAABLgAECn8ZAAIFAAkJcRLlDQAJAgAFAAkJcRLlDQAJAgAAAA==.',
El='Elipsis:BAABLgAECn8dAAIFAAkJqhNaLACVAQAFAAkJqhNaLACVAQAAAA==.Elm:BAABLgAECn8iAAQHAAgJIBYRJQChAQAHAAgJIBYRJQChAQAIAAYJwxHEIAAwAQAcAAEJ5BNdLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAABLgAECn8ZAAICAAgJaRUDLwD1AQACAAgJaRUDLwD1AQAAAA==.Elyssaelyend:BAAALgAECgYJBgABLgAECgcJGQAHAMgaAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emmental:BAAALgAECgYJEQAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJDgAAAA==.Enricco:BAAALgAECgYJBgAAAA==.',
Er='Ereko:BAABLgAECn8ZAAICAAcJVg2QRwA2AQACAAcJVg2QRwA2AQAAAA==.Erythorbic:BAABLgAECn8aAAMaAAcJ/B+yGwAJAgAaAAYJax6yGwAJAgAWAAMJQyChLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgUJCgAAAA==.',
Ev='Evictor:BAAALgAECgQJBQABLgAECggJDQADAAAAAA==.',
Ex='Exileelfsam:BAABLgAECn8fAAIPAAgJcAj5EgCFAQAPAAgJcAj5EgCFAQAAAA==.',
Fa='Fallensk:BAAALgADCgIJAgAAAA==.Familyvalues:BAAALgADCgUJBQAAAA==.Faranth:BAAALgAECgEJAQAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgADCgUJBgAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8XAAMdAAUJXBIZCgClAQAdAAUJXBIZCgClAQAKAAEJ1QHhIgA8AAAuAAQKfyoAAx0ACAlEHyQIAL0CAB0ACAlEHyQIAL0CAAUABgkhCC1KABABAAAA.',
Fe='Feer:BAAALgAECgMJBgAAAA==.Feldron:BAABLgAECn8cAAMeAAkJZh29CgDmAgAeAAgJGR69CgDmAgAfAAEJgxjwHQA9AAAAAA==.Felshatter:BAAALgAECgYJEwAAAA==.Feltigress:BAABLgAECn8mAAIJAAgJlh63AgB1AgAJAAgJlh63AgB1AgAAAA==.Fendag:BAAALgADCgYJCQAAAA==.',
Ff='Ffugme:BAABLgAECn8aAAIEAAYJ/Q2RIAADAQAEAAYJ/Q2RIAADAQAAAA==.Ffugoff:BAAALgADCggJCAAAAA==.Ffugtard:BAAALgAECgcJEAAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAAAAA==.Finnian:BAABLgAECn8fAAITAAgJiBvHCgBlAgATAAgJiBvHCgBlAgAAAA==.Fio:BAABLgAECn8jAAMgAAgJ9ySyAgBaAwAgAAgJ9ySyAgBaAwARAAEJSRs4cABRAAAAAA==.Firiona:BAAALgAECgYJDgAAAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIhAAgJzRfTEQC1AQAhAAgJzRfTEQC1AQAAAA==.Flinn:BAABLgAECn8YAAIcAAkJgx2HAgCIAgAcAAkJgx2HAgCIAgAAAA==.Flowers:BAABLgAECn8lAAMGAAgJhB35DQBZAgAGAAgJhB35DQBZAgAbAAIJexmCKACbAAAAAA==.Fläva:BAAALgAECgUJDAAAAA==.',
Fo='Forkinyou:BAAALgAECgQJBAAAAA==.',
Fr='Fracture:BAAALgADCgEJAQAAAA==.Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8mAAIBAAgJaxY7MgDYAQABAAgJaxY7MgDYAQAAAA==.',
Fu='Furysbubble:BAAALgAECgEJAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwADAAAAAA==.',
Ga='Gafocalypse:BAAALgAECgUJBwAAAA==.Garddidit:BAAALgADCgUJBQABLgAECgcJGwANABsdAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgcJDAAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCggJFgAAAA==.Grotok:BAAALgAECggJEwAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.Gurgatron:BAAALgAECgYJBgABLgAECgcJBwADAAAAAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJCAAAAA==.Hasklaufien:BAAALgAECgIJBAAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgADCgMJAwAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgADCgYJCwAAAA==.',
Hu='Hugulin:BAABLgAECn8YAAICAAcJ3QZeWwD+AAACAAcJ3QZeWwD+AAAAAA==.',
Ic='Icedsoul:BAAALgAECgUJDAAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8mAAIXAAgJOxtIBABGAgAXAAgJOxtIBABGAgAAAA==.',
Ik='Ikkaku:BAAALgAECgEJAQAAAA==.',
Il='Ilandras:BAABLgAECn8eAAIGAAcJrA4JQgAzAQAGAAcJrA4JQgAzAQAAAA==.Illadus:BAAALgAECggJDwAAAA==.Illed:BAAALgADCgcJBwAAAA==.Illusorybias:BAAALgAECgkJCAAAAA==.',
In='Indra:BAAALgAECgYJCAAAAA==.Intoxicated:BAAALgAECgYJEwAAAA==.',
Io='Ione:BAAALgADCgcJBAAAAA==.',
Ir='Iranna:BAACLgAFFH8RAAQfAAUJuxy0AQB3AQAfAAQJ0hq0AQB3AQAiAAQJERojAgBGAQAeAAEJAABnJAAAAAAuAAQKfyYABB8ACAmQJQEBALcCACIACAlwI0YBAN8CAB8ABwmwIAEBALcCAB4AAQkAAFxCAAAAAAAA.Irondihh:BAAALgAECgMJAwAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECggJDwADAAAAAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECggJHQAUAGAeAA==.Janaki:BAAALgAECggJEAAAAA==.',
Jo='Joenutter:BAAALgAECgMJBgAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn8qAAISAAkJnBFNLADMAQASAAkJnBFNLADMAQAAAA==.',
Ju='Juicie:BAAALgAECgQJBQAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJFQAMABkeAA==.Junrush:BAAALgAECggJDgABLgAFFAUJFQAMABkeAA==.',
['Jè']='Jèstèr:BAAALgADCgkJCQABLgAFFAUJFwAdAFwSAA==.',
Ka='Kalea:BAAALgAECgIJAwAAAA==.Kalecgo:BAAALgAECgMJAwABLgAECgcJDAADAAAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kat:BAAALgAECggJEQAAAA==.Katsuko:BAABLgAECn8fAAIjAAgJDRd3CgDRAQAjAAgJDRd3CgDRAQAAAA==.Kattnirra:BAABLgAECn8YAAICAAgJdgwiPQBZAQACAAgJdgwiPQBZAQAAAA==.Katze:BAABLgAECn80AAICAAgJqhPLKACuAQACAAgJqhPLKACuAQAAAA==.Kaylé:BAAALgAECgQJBAAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgYJBgAAAA==.Keepper:BAABLgAECn8hAAIaAAgJoBGaRwBRAQAaAAgJoBGaRwBRAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8VAAIFAAcJvhDUIQA6AQAFAAcJvhDUIQA6AQAAAA==.Ketheric:BAAALgAECgMJAwAAAA==.',
Ki='Killahaseo:BAAALgADCgkJDgABLgAECgcJGgAYAAUZAA==.Killmoedee:BAABLgAECn8gAAIEAAgJhR8fAwB2AgAEAAgJhR8fAwB2AgAAAA==.Kitwryn:BAAALgADCgUJBQAAAA==.',
Kk='Kkaell:BAAALgAECgQJCQABLgAECgUJBAADAAAAAA==.',
Kl='Klexios:BAAALgAECgMJBwAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgAECgEJAQAAAA==.',
Kr='Kracious:BAAALgAECgQJBAAAAA==.Krymson:BAAALgAECgYJBwAAAA==.',
Ku='Kui:BAABLgAECn8fAAIhAAgJQBj1CwACAgAhAAgJQBj1CwACAgAAAA==.Kurtcobrain:BAAALgAECgYJCQAAAA==.',
['Kö']='Köz:BAAALgADCgkJDAAAAA==.',
La='Laetri:BAABLgAECn8bAAIGAAgJ7RU+VACnAQAGAAgJ7RU+VACnAQAAAA==.Lasttok:BAAALgAECgYJEgAAAA==.Laylene:BAAALgAECgUJDQAAAA==.Lazloo:BAABLgAECn8bAAMXAAcJDyLwBgDwAQAMAAUJCySdLwDxAQAXAAcJOhzwBgDwAQAAAA==.Lazymidget:BAABLgAECn8eAAIOAAcJFR1OLQDFAQAOAAcJFR1OLQDFAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgADCgYJEgABLgAECgkJMgAPAAoUAA==.Legindkiller:BAAALgADCggJFgAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAcJGAAHABYfAA==.',
Li='Lightace:BAAALgAECgUJDgAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAAALgAECgcJDQAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8VAAIaAAcJzwUNjgCoAAAaAAcJzwUNjgCoAAAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAAALgAECgcJDAAAAA==.Lostdream:BAAALgAECgYJDAAAAA==.Loun:BAABLgAECn8YAAIhAAYJ9w3MJwAHAQAhAAYJ9w3MJwAHAQAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCggJFgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECgYJEwADAAAAAA==.Luvlycruelty:BAAALgADCgUJBwAAAA==.',
Ly='Lyn:BAEBLgAECn8rAAIhAAkJFiZCAAB7AwAhAAkJFiZCAAB7AwAAAA==.',
Ma='Mackenziiee:BAABLgAECn8oAAICAAkJKxubDAB5AgACAAkJKxubDAB5AgAAAA==.Mackthyra:BAAALgADCgcJBwAAAA==.Madglowup:BAAALgAECgUJBgAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8dAAIBAAgJNh1sIgAeAgABAAgJNh1sIgAeAgAAAA==.Magtaki:BAAALgAECgkJBwAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Maizepriest:BAABLgAECn8eAAIKAAcJpCEACABLAgAKAAcJpCEACABLAgAAAA==.Mannysaf:BAABLgAECn8VAAIMAAcJ8Qv/JgA+AQAMAAcJ8Qv/JgA+AQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwABLgAFFAYJEAABAJcZAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Mellowblink:BAABLgAECn8eAAIBAAgJPhOUQAClAQABAAgJPhOUQAClAQAAAA==.Mellowlink:BAABLgAECn8aAAIeAAcJzBJ7EwB4AQAeAAcJzBJ7EwB4AQAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECgYJCAAAAA==.Menara:BAAALgAECgYJCQAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgIJAgAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8bAAQOAAgJ4yFBAQCJAgAOAAgJpCBBAQCJAgAPAAMJmiPbEQDVAAACAAIJkSTXRQBmAAAuAAQKfzIABA4ACQmCJusDAGUDAA4ACAkCJusDAGUDAA8ABwnGJbMDAJYCAAIAAgktJXWVAGUAAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECggJMQAeAPMYAA==.Miravus:BAABLgAECn8xAAMeAAgJ8xjmDQDEAQAeAAgJQRjmDQDEAQAfAAUJSRJvCABPAQAAAA==.Mirlanda:BAAALgAECgUJDwAAAA==.Misttie:BAAALgAECggJEQABLgAECgkJHQAFAKoTAA==.',
Mo='Monkerick:BAAALgAECgUJCQAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCggJFgAAAA==.',
Mu='Murkoobi:BAAALgAECgEJAQAAAA==.Mursk:BAAALgAECgIJAgAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystrial:BAAALgAECgEJAgAAAA==.Mystáke:BAAALgAECgkJEQAAAA==.',
['Mä']='Mäble:BAAALgADCgYJBwAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwABLgAECggJFwACAHoWAA==.',
['Mó']='Mómo:BAAALgAECgMJAwAAAA==.Móus:BAAALgAECgUJCAABLgAECggJFwACAHoWAA==.',
Na='Narcissus:BAAALgADCggJFgAAAA==.Narivia:BAAALgAECgUJBgABLgAFFAUJFwAdAFwSAA==.Naro:BAAALgAECgYJBgAAAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAABLgAECn8YAAMcAAYJkBeUDwAOAQAcAAUJtheUDwAOAQAJAAUJqg4vIADeAAAAAA==.',
Ne='Necrotis:BAAALgADCggJFgAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn8pAAMFAAgJoyVPAQBZAwAFAAgJoyVPAQBZAwAKAAUJKxgMNwA1AQAAAA==.Neytholy:BAAALgAECgMJBgAAAA==.Nezukô:BAAALgAECgcJCAAAAA==.',
Ni='Nienna:BAAALgAECgIJAgAAAA==.Nitalan:BAAALgADCgkJIgAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgMJCAAAAA==.Noraldrys:BAAALgADCgcJDQAAAA==.Noralyne:BAAALgAECgUJBwAAAA==.Noras:BAAALgAECggJDQAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8hAAIXAAgJhxGMCgCdAQAXAAgJhxGMCgCdAQAAAA==.Notagnoblin:BAEALgAECgMJAwABLgAFFAQJDQAhAKwlAA==.',
Ny='Nysonia:BAAALgAECgcJBwAAAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIZAAkJGQ6UBACpAQAZAAkJGQ6UBACpAQAAAA==.',
Oc='Octuroun:BAAALgAECgcJDgAAAA==.',
Od='Oddsoul:BAAALgAECgQJBgAAAA==.',
Og='Ogrelurd:BAAALgAECgUJCgAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJBwAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAABLgAECn8sAAQkAAgJpiLbAgDpAQAaAAcJwh0eIQDqAQAkAAYJmSLbAgDpAQAWAAEJpgiNdAAwAAAAAA==.',
Or='Orakwa:BAAALgAECgUJDQAAAA==.',
Ou='Outen:BAAALgAECgcJBwAAAA==.',
Oz='Ozzieliem:BAAALgAECgEJAQAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Pallinda:BAABLgAECn8aAAMSAAgJvhMkhgBuAQASAAgJvhMkhgBuAQATAAYJkw8HKwA2AQAAAA==.Panakananama:BAAALgAECgYJDAAAAA==.Panz:BAABLgAECn8YAAMYAAcJsAk1KQAJAQAYAAcJUwg1KQAJAQAZAAEJIA7xFwA1AAAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgYJBgAAAA==.Papster:BAAALgADCgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgAECgIJAgAAAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgkJCwAAAA==.Pennypacker:BAAALgAECgYJCQAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAAALgAECgUJDwAAAA==.',
Ph='Phara:BAABLgAECn8YAAQKAAcJ7ApaHwBCAQAKAAcJ7ApaHwBCAQAdAAUJZgioNgDwAAAFAAIJlAFqfAA3AAAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoel:BAAALgADCggJCQAAAA==.Phoopanchu:BAABLgAECn8ZAAIgAAgJ/hB7GgB4AQAgAAgJ/hB7GgB4AQAAAA==.',
Pi='Pibble:BAAALgADCgMJAwAAAA==.Pinkbuns:BAABLgAECn8bAAIBAAYJcRhbWQBiAQABAAYJcRhbWQBiAQAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAABLgAECn8WAAINAAYJ2iIpBADzAQANAAYJ2iIpBADzAQAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsy:BAAALgAECgYJEgAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8hAAIMAAcJ6yEhCQBWAgAMAAcJ6yEhCQBWAgAAAA==.Pretzel:BAAALgADCgUJBQABLgAFFAMJBQAUAOMaAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAABLgAECn8qAAIaAAgJ8BA6OACFAQAaAAgJ8BA6OACFAQAAAA==.Profundity:BAAALgAECgYJDAAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8dAAIUAAgJYB6EFABXAgAUAAgJYB6EFABXAgAAAA==.',
Qe='Qeini:BAABLgAECn8mAAIdAAgJdhmbBwBsAgAdAAgJdhmbBwBsAgAAAA==.',
Ra='Radrin:BAAALgADCgkJEgAAAA==.Rafoff:BAAALgAECgUJDQAAAA==.Rahll:BAAALgADCggJFgAAAA==.Rancoramble:BAABLgAECn8XAAIjAAkJDATtFwANAQAjAAkJDATtFwANAQAAAA==.Randis:BAABLgAECn8hAAMUAAcJaAx6TQBTAQAUAAcJaAx6TQBTAQAVAAYJoQInDgCfAAAAAA==.Ranekk:BAAALgAECgEJAQAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razonghoul:BAABLgAECn8vAAIUAAkJAiHUBwDfAgAUAAkJAiHUBwDfAgAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgUJCwAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAAALgAECgUJCgAAAA==.Rexiis:BAABLgAECn8eAAMaAAgJaBKULACyAQAaAAgJaBKULACyAQAkAAEJAABcNAAzAAAAAA==.Reyth:BAAALgAECgQJDAAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8fAAIeAAcJOiC6EACcAgAeAAcJOiC6EACcAgAAAA==.',
Ri='Rimos:BAAALgADCgUJBQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn8gAAIlAAgJgQ0XHgBdAQAlAAgJgQ0XHgBdAQAAAA==.',
Ro='Rockadin:BAABLgAECn8YAAISAAYJ7RLyXQAzAQASAAYJ7RLyXQAzAQAAAA==.Rosael:BAAALgADCgYJDAAAAA==.Roundhouse:BAAALgAECgEJAQAAAA==.',
Ru='Rubbmytotems:BAAALgAECgYJDgAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8gAAMCAAgJJxOwJwC0AQACAAgJJxOwJwC0AQAOAAIJrQn4egBXAAAAAA==.Rumí:BAABLgAECn8gAAIGAAkJUAkUNgBdAQAGAAkJUAkUNgBdAQAAAA==.Russell:BAAALgADCgYJEwAAAA==.Rutgore:BAABLgAECn8iAAIeAAgJch6lBAB9AgAeAAgJch6lBAB9AgAAAA==.',
Rx='Rx:BAAALgAECgUJBQAAAA==.',
Sa='Sabado:BAAALgAECgQJDAAAAA==.Safewerd:BAEALgAECgcJDwAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgUJCQAAAA==.Sarahfi:BAAALgAECgIJAwAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAAALgAECgUJBwAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgYJDAAAAA==.Sathenazarke:BAACLgAFFH8FAAImAAMJ0QXjFAC8AAAmAAMJ0QXjFAC8AAAuAAQKfyoABCYACQmDF80RACECACYACAnkGM0RACECABgABwncGsMYAHoBABkAAQkrCPdCACkAAAEuAAUUBQkRAB8AuxwA.Saths:BAAALgADCgEJAQABLgAECggJEwADAAAAAA==.',
Sc='Schallue:BAABLgAECn8YAAInAAcJXQabBAAQAQAnAAcJXQabBAAQAQAAAA==.Schism:BAAALgADCgkJHgAAAA==.Scoban:BAACLgAFFH8YAAITAAUJACTAAwDyAQATAAUJACTAAwDyAQAuAAQKfyoAAhMACAl4IQsOAKgCABMACAl4IQsOAKgCAAAA.Scylla:BAAALgAECgUJDAAAAA==.',
Se='Selithel:BAABLgAECn8XAAIbAAgJ3ge7FQA7AQAbAAgJ3ge7FQA7AQAAAA==.Serioussurv:BAAALgADCgUJBQAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECggJHwAjAA0XAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAAALgAECgYJEQAAAA==.Shaeliana:BAAALgAECgQJDQAAAA==.Shalera:BAAALgAECgcJBwAAAA==.Shaqfu:BAAALgADCggJFgAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shiggyloo:BAAALgAECggJAQAAAA==.Shigure:BAAALgAECgcJEwAAAA==.Shivers:BAAALgAECgUJCAAAAA==.Shnow:BAAALgAECgkJEwAAAA==.Sholin:BAAALgAECgYJEgAAAA==.Shomea:BAAALgAECgMJBwAAAA==.Shugz:BAAALgADCggJFgAAAA==.Shumai:BAAALgAECgQJBAAAAA==.',
Si='Sikotick:BAABLgAECn8bAAIHAAgJ7R0FDACKAgAHAAgJ7R0FDACKAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAABLgAECn8yAAIBAAkJqSCRCADpAgABAAkJqSCRCADpAgAAAA==.Silverbolt:BAAALgAECgYJEQAAAA==.Simbelmyne:BAAALgADCgMJAwAAAA==.Sinderone:BAACLgAFFH8NAAITAAUJng0iCwBxAQATAAUJng0iCwBxAQAuAAQKfzoAAxMACQnlHj0DAA8DABMACQnlHj0DAA8DABIABQn9F75yAAcBAAAA.',
Sk='Skaaduush:BAAALgAECgYJCQAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn8mAAIUAAkJWBzQHQDOAgAUAAkJWBzQHQDOAgAAAA==.Sleepylune:BAAALgAECgMJBQAAAA==.Slippie:BAAALgADCgQJAgAAAA==.Sllew:BAABLgAECn8dAAIUAAgJ0CGFCgC5AgAUAAgJ0CGFCgC5AgAAAA==.Slèw:BAAALgAECgQJBAAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smoulder:BAAALgAECgEJAQAAAA==.',
Sn='Snigles:BAAALgAECgYJEgAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Somannita:BAAALgADCgcJBwAAAA==.Souei:BAAALgADCgEJAQABLgAECggJEwADAAAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgADCgQJBAAAAA==.Sposi:BAEBLgAECn8eAAIjAAcJXSF/BgAxAgAjAAcJXSF/BgAxAgAAAA==.Spraynpray:BAAALgAECgYJCQAAAA==.',
Sr='Srimrithyu:BAAALgAECgEJAQAAAA==.',
Ss='Sselionn:BAAALgAECgUJEAAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAAALgAECgcJDQAAAA==.',
Su='Subliminal:BAABLgAECn8WAAMeAAgJ7hLOEwB0AQAeAAgJ7hLOEwB0AQAiAAEJswzUEgA3AAAAAA==.',
Sv='Svartalfar:BAAALgADCgMJAQAAAA==.',
Sy='Syravia:BAABLgAECn8VAAISAAcJWQUJfwDuAAASAAcJWQUJfwDuAAAAAA==.',
['Sé']='Séraphyne:BAAALgAECgUJDAAAAA==.',
Ta='Talarin:BAAALgAECgUJCAAAAA==.Tameka:BAAALgAECgQJBgAAAA==.Tardis:BAAALgAECgkJAQAAAA==.Tatersmonk:BAECLgAFFH8NAAIhAAQJrCWmAwC9AQAhAAQJrCWmAwC9AQAuAAQKfx4AAiEACQksJL0DAFQDACEACQksJL0DAFQDAAAA.Tavinrayn:BAAALgAECgQJBAAAAA==.Tazzar:BAABLgAECn8fAAIYAAgJZgfrIQA0AQAYAAgJZgfrIQA0AQAAAA==.',
Td='Tdjin:BAAALgAECgYJCQAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECggJIgAHACAWAA==.Tekêsh:BAAALgAECgYJEQAAAA==.Telarin:BAABLgAECn8bAAMCAAcJ9RtYJQC/AQACAAcJ9RtYJQC/AQAPAAYJlQtyHQAXAQAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.Teriss:BAAALgADCgMJAwAAAA==.',
Th='Thandor:BAAALgAECgMJBwAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECggJDgAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgADCgYJCgAAAA==.Thuliaga:BAAALgAECgIJAgAAAA==.',
Ti='Tiamut:BAAALgAECgMJAwAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgYJBwABLgAECgcJGAAKAPkQAA==.Tinneas:BAAALgADCgEJAQAAAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomie:BAAALgADCgMJAwAAAA==.Tomás:BAAALgAECgYJEQAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8VAAIjAAUJ+h5ICABHAQAjAAUJ+h5ICABHAQAuAAQKfywAAiMACQmQIXMCAMkCACMACQmQIXMCAMkCAAAA.Torstai:BAAALgAECgUJDQAAAA==.Totemthis:BAAALgADCgkJCQAAAA==.',
Tr='Trueshöt:BAAALgAECgYJEAAAAA==.',
Ts='Tserendolgor:BAABLgAECn8YAAQbAAcJyRfUEwBPAQAbAAcJyRfUEwBPAQANAAEJTRUvKQBAAAAGAAEJ9AEj0QAdAAAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJHQAlAFYWAA==.Twinsha:BAABLgAECn8dAAMlAAgJVhYxEgDKAQAlAAgJVhYxEgDKAQAoAAcJJwSxWQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJHQAlAFYWAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrasong:BAAALgAECgMJBQAAAA==.Tyresious:BAAALgAECgYJDwAAAA==.',
['Tà']='Tàric:BAAALgAECgEJAQAAAA==.',
Un='Unauma:BAACLgAFFH8MAAIHAAQJwgjSGwD4AAAHAAQJwgjSGwD4AAAuAAQKfxcAAgcACAknHlQOAGwCAAcACAknHlQOAGwCAAAA.Undeadpanda:BAAALgAECgIJAgABLgAECgEJAgADAAAAAA==.Unholydk:BAAALgAECgQJCgAAAA==.',
Va='Vaa:BAAALgADCgcJEwAAAA==.Vahaghn:BAABLgAECn8sAAIXAAkJLyOoAAArAwAXAAkJLyOoAAArAwAAAA==.Valcerus:BAAALgAECgMJBwAAAA==.Valedus:BAABLgAECn8mAAISAAgJ6CNlCADNAgASAAgJ6CNlCADNAgAAAA==.Validrela:BAAALgADCgIJAgAAAA==.Vampirism:BAAALgAECgQJBAABLgAECgYJEwADAAAAAA==.',
Ve='Veelete:BAAALgADCggJDgABLgAECgcJHAATAHEbAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECggJKQAFAKMlAA==.Vespra:BAABLgAECn8/AAIoAAkJRyB+AgA3AwAoAAkJRyB+AgA3AwAAAA==.',
Vh='Vhas:BAAALgAECgkJDgAAAA==.Vhem:BAAALgAECgkJAQAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJCQADAAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8hAAIEAAcJdQakGgC/AAAEAAcJdQakGgC/AAAAAA==.Voltashi:BAABLgAECn8hAAQhAAgJmBSOEQC4AQAhAAgJmBSOEQC4AQAgAAIJtwWkYQBJAAARAAEJBAtygAAwAAAAAA==.Voltuk:BAAALgAECgcJBwAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgYJBgAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgABLgAECgYJEQADAAAAAA==.',
Wa='Wagyuboi:BAAALgAECgUJCQAAAA==.Wallypaly:BAABLgAECn8nAAMSAAgJDhaSOgCXAQASAAcJVxeSOgCXAQAEAAUJ6Ra6EwALAQAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn8eAAITAAYJGRycGwCsAQATAAYJGRycGwCsAQAAAA==.Warwarb:BAAALgADCgYJCwABLgAECggJJwAaAOoZAA==.Waterliliy:BAABLgAECn8YAAIKAAcJ+RDXJAAcAQAKAAcJ+RDXJAAcAQAAAA==.',
Wh='Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBAAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8bAAMCAAcJnBJ8MwB/AQACAAcJnBJ8MwB/AQAOAAYJkQtqEgDOAAAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgcJBwABLgAECgMJBwADAAAAAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgADCgQJBAABLgAECggJJAAaAAYbAA==.Xenhaseo:BAABLgAECn8aAAIYAAcJBRkIEQDJAQAYAAcJBRkIEQDJAQAAAA==.',
Xh='Xhuri:BAAALgAECgIJAwAAAA==.',
Xi='Xilla:BAAALgAECgQJBAAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAAALgAECgYJDwAAAA==.',
Yo='Yorllik:BAAALgADCgcJGgAAAA==.Yougotwreckd:BAAALgADCgEJAQAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8aAAIGAAcJQhf9QQAzAQAGAAcJQhf9QQAzAQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8mAAIYAAkJJCG9AwDRAgAYAAkJJCG9AwDRAgAAAA==.Zaiene:BAAALgAECgIJAwABLgAECgYJCQADAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarkhan:BAAALgAECgMJAwAAAA==.Zarulyn:BAAALgAECgQJBAAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAAALgAECgYJCAAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8dAAMoAAgJBRSYQgB2AQAoAAYJOBOYQgB2AQApAAgJnAXoCwBMAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgIJAgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgQJBgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn8cAAICAAcJ8Q4/RABAAQACAAcJ8Q4/RABAAQAAAA==.',
['Äc']='Äcid:BAABLgAECn8rAAIoAAkJ1xvjCgB/AgAoAAkJ1xvjCgB/AgAAAA==.',
['Åp']='Åpollo:BAAALgAFFAMJAwAAAA==.',
['Èa']='Èastçoast:BAAALgADCgcJEwAAAA==.',
['Êl']='Êlydala:BAAALgAECgUJBAAAAA==.',
['Ðð']='Ððå:BAAALgADCgEJAQAAAA==.',
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

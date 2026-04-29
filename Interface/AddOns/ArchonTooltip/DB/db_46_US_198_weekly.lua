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

local lookup = {'Mage-Frost','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Priest-Holy','DeathKnight-Blood','Priest-Shadow','Evoker-Preservation','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warlock-Destruction','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Warrior-Protection','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','Druid-Feral','Mage-Fire','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Survival','Druid-Guardian','Hunter-Marksmanship','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aajax:BAAALgAECgQJCwAAAA==.',
Ab='Abzdh:BAAALgAECgUJCgABLgAECggJIwABALoiAA==.Abzlock:BAAALgAECgEJAQABLgAECggJIwABALoiAA==.Abzmage:BAABLgAECn8jAAIBAAgJuiJnGgAOAwABAAgJuiJnGgAOAwAAAA==.',
Ac='Acht:BAAALgAECgYJBgAAAA==.',
Ad='Adderpal:BAAALgAECgQJCgAAAA==.Adelyreith:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.Adramelach:BAABLgAECn8VAAIDAAYJ1B1cGABeAQADAAYJ1B1cGABeAQAAAA==.Adriel:BAAALgADCgQJBAABLgAECgQJBAACAAAAAA==.',
Ae='Aeiay:BAAALgAECgQJCQAAAA==.',
Ag='Again:BAAALgAECgQJBAAAAA==.',
Ai='Ainzooalgown:BAABLgAECn8WAAIBAAgJCBWJDwDIAQABAAgJCBWJDwDIAQAAAA==.',
Al='Alastorian:BAAALgADCgMJAwABLgAECgUJCAACAAAAAA==.Alethice:BAAALgADCgMJAwABLgAECggJDgACAAAAAA==.Alexandrap:BAAALgAECgIJBAAAAA==.Alindis:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.Allmighto:BAECLgAFFH8OAAIEAAUJxRsqAgDdAQAEAAUJxRsqAgDdAQAuAAQKfyIAAgQACAl4JYQBAG0DAAQACAl4JYQBAG0DAAAA.',
An='Androstraz:BAACLgAFFH8IAAMFAAQJtB3CEAD7AAAFAAQJtB3CEAD7AAAGAAIJjgcNBwCdAAAuAAQKfx4AAwYACAlyHzQMABcCAAYABwliHDQMABcCAAUABQknH+8cAN8BAAAA.Anniesthesia:BAABLgAECn8cAAIHAAgJ5QOaDQAVAQAHAAgJ5QOaDQAVAQAAAA==.Anoobyss:BAAALgAECgYJCwAAAA==.Anorexorcist:BAAALgADCgkJEQABLgAECggJHgAIAKQWAA==.Anorxxorcist:BAABLgAECn8eAAIIAAgJpBY8AwDEAQAIAAgJpBY8AwDEAQAAAA==.Anthraxx:BAAALgAECgEJAgAAAA==.',
Ap='Appledeez:BAABLgAECn8kAAIJAAgJShuqEQBvAgAJAAgJShuqEQBvAgAAAA==.',
Ar='Arda:BAAALgAECgUJBwAAAA==.Arrax:BAACLgAFFH8FAAIKAAMJBBfdDQD9AAAKAAMJBBfdDQD9AAAuAAQKfxwAAwoACAlZIUMEABADAAoACAlZIUMEABADAAYAAQmlBq0JADwAAAAA.Arune:BAAALgAECgYJDAAAAA==.Arunem:BAAALgADCgYJCgABLgAECgYJDAACAAAAAA==.Arunen:BAAALgADCgEJAQABLgAECgYJDAACAAAAAA==.',
As='Asapgbaby:BAAALgAECgEJAQAAAA==.Ashari:BAAALgAECgEJAQAAAA==.Ashly:BAAALgAECgQJDQAAAA==.Aspyrx:BAAALgAECgcJEgAAAA==.Astelan:BAEBLgAECn8gAAMLAAgJDh99CQCjAgALAAgJDh99CQCjAgAJAAYJrxp7IQDLAQAAAA==.Astronomica:BAABLgAECn8WAAMEAAcJKhPkEAAwAQAEAAcJKhPkEAAwAQADAAUJhAjTOQCwAAAAAA==.Asunder:BAAALgAECgYJCwAAAA==.',
At='Atumsphinx:BAAALgADCgUJBQAAAA==.',
Au='Aurorä:BAAALgAECgUJCAAAAA==.',
Aw='Awfulrofl:BAAALgADCgYJCgAAAA==.',
Ay='Ayeola:BAAALgAECggJEwAAAA==.',
Az='Azareldurson:BAAALgAECgcJEAAAAA==.Azuresh:BAAALgAECgcJDgABLgAECggJGgAMAHcjAA==.',
Ba='Baalrogg:BAAALgADCgYJBwAAAA==.Babywipes:BAABLgAECn8UAAMNAAgJqh6QHABYAgANAAgJqh6QHABYAgAOAAEJqw4ohQArAAAAAA==.Bachaterah:BAAALgAECgYJCwAAAA==.Baddawg:BAAALgAECgEJAgAAAA==.Baeldaeg:BAABLgAECn8jAAIPAAgJfyInAwB0AgAPAAgJfyInAwB0AgABLgAECgQJBQACAAAAAA==.Baelin:BAAALgAECgQJCQAAAA==.Bahahahamut:BAAALgADCgYJBwABLgAECgQJBQACAAAAAA==.Baked:BAAALgADCgEJAQAAAA==.Balkar:BAAALgADCgcJCQAAAA==.Bannett:BAACLgAFFH8LAAIBAAQJnR4tBwBnAQABAAQJnR4tBwBnAQAuAAQKfxkAAgEACAn8IA43AJgCAAEACAn8IA43AJgCAAAA.Bashnveggies:BAAALgADCgMJAwAAAA==.Bastét:BAABLgAECn8VAAIJAAYJpBacJQCrAQAJAAYJpBacJQCrAQAAAA==.Bauce:BAAALgADCgYJBgAAAA==.Baxter:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Baxterlock:BAAALgAECgQJBAAAAA==.Baylifê:BAAALgADCggJEwAAAA==.',
Be='Bearymanalow:BAAALgAECgYJEAAAAA==.Beefyweefy:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.Bella:BAAALgAECgEJAQAAAA==.Belldelphiné:BAEALgAECgMJBgABLgAECgYJFwAIAFsUAA==.Bellz:BAAALgADCgYJBwAAAA==.Belmønt:BAAALgAECgIJAwAAAA==.',
Bi='Bicycle:BAABLgAECn8UAAIQAAcJshY3DAD/AQAQAAcJshY3DAD/AQAAAA==.Biddy:BAAALgADCgYJBgAAAA==.Bigpumpa:BAAALgAECgYJDgAAAA==.Billmurray:BAAALgAECgYJDwAAAA==.Billygoatgrf:BAABLgAECn8YAAIBAAgJdQw4FgCRAQABAAgJdQw4FgCRAQAAAA==.Birchy:BAAALgADCgcJBwAAAA==.',
Bl='Blakkbeard:BAABLgAECn8fAAMRAAgJASILCwDnAgARAAgJviALCwDnAgASAAYJKCHrEgCJAQAAAA==.Blakklight:BAAALgAECgYJDQABLgAECggJHwARAAEiAA==.Blazefort:BAABLgAECn8cAAMTAAkJyhbCKQCSAgATAAkJABbCKQCSAgAUAAcJRRanBQDaAQAAAA==.Blazeshifts:BAAALgADCgcJBwAAAA==.Blindedd:BAAALgAECgUJBgAAAA==.Blitzeye:BAAALgAECgQJCwAAAA==.Bloodknight:BAAALgADCgMJAwAAAA==.Bloodraine:BAABLgAECn8UAAIVAAYJ4hKoLgCNAQAVAAYJ4hKoLgCNAQAAAA==.Bloodshadow:BAAALgADCgIJAgAAAA==.Bluucat:BAAALgADCgkJCQAAAA==.Blôô:BAABLgAECn8XAAIOAAcJMBfeIgDlAQAOAAcJMBfeIgDlAQAAAA==.',
Bo='Boethius:BAAALgADCgcJEQAAAA==.Boozeftw:BAAALgADCgIJAgAAAA==.Borkhuis:BAAALgADCgYJCgAAAA==.Bouw:BAAALgADCgcJBwAAAA==.Bouz:BAAALgADCgMJAwAAAA==.Bows:BAAALgADCgIJAgAAAA==.Boysole:BAAALgAECgYJBgAAAA==.',
Bq='Bqpally:BAAALgADCgQJBAAAAA==.',
Br='Brainlesswar:BAABLgAECn8aAAIWAAgJfxIqFADJAQAWAAgJfxIqFADJAQAAAA==.Breemonic:BAABLgAECn8cAAIXAAgJqg0NIQC0AQAXAAgJqg0NIQC0AQAAAA==.Brewdie:BAAALgADCggJFAAAAA==.Bristle:BAAALgADCgYJBgAAAA==.Bruce:BAACLgAFFH8IAAQWAAMJ+RlABQCZAAAWAAIJ1RFABQCZAAAYAAEJsR4JCQBhAAAZAAEJLyMmHgBgAAAuAAQKfyIABBkACQlKIwQLAAQDABkACQn4IgQLAAQDABYACAnzHNUIAJECABgAAgkbGaIrAJcAAAAA.Brucetree:BAAALgADCgYJBgAAAA==.',
Bu='Bubblekush:BAAALgAECgYJDAAAAA==.Bubbleøseven:BAAALgAECgYJCwAAAA==.Butterz:BAAALgAECgIJAwAAAA==.Buttshank:BAAALgAECgYJDwAAAA==.',
Ca='Calyx:BAAALgAECgQJBAAAAA==.Carson:BAAALgAECgQJCgAAAA==.',
Ch='Chaosvader:BAAALgADCggJDwAAAA==.Chickenbich:BAAALgADCgkJEAAAAA==.Chobi:BAAALgAECgEJAQAAAA==.Choices:BAAALgADCgUJBQABLgAECggJEAACAAAAAA==.Chrunch:BAAALgADCgYJBgAAAA==.Chuggernaugt:BAABLgAECn8aAAIaAAcJjhK8CABJAQAaAAcJjhK8CABJAQAAAA==.',
Ci='Cinnamen:BAABLgAECn8dAAIVAAgJ3BnDEgCFAgAVAAgJ3BnDEgCFAgAAAA==.',
Cl='Cllawhan:BAAALgADCgkJCgAAAA==.Clutchcity:BAAALgADCgYJBgAAAA==.',
Co='Coaa:BAAALgAECgcJEgAAAA==.Codèx:BAABLgAECn8ZAAIBAAgJsBSPZQANAgABAAgJsBSPZQANAgAAAA==.Colossus:BAABLgAECn8cAAIDAAgJ3wrhFwBiAQADAAgJ3wrhFwBiAQAAAA==.Conclave:BAAALgADCgcJDAAAAA==.Contrap:BAAALgADCgMJAwAAAA==.Convoker:BAABLgAECn8dAAMFAAgJZBWvBADCAQAFAAgJWhOvBADCAQAGAAYJnRY0FQCYAQAAAA==.Coolbreeze:BAAALgAECgQJBQAAAA==.Cootert:BAAALgAECgUJBwAAAA==.',
Cr='Creamsnake:BAAALgAECgEJAQAAAA==.Crimo:BAAALgAECgYJBwABLgAFFAUJDQAOAJ8UAA==.Crimons:BAAALgAECgQJCgAAAA==.Cronk:BAABLgAECn8VAAMbAAYJqBoYDwDSAQAbAAUJTSAYDwDSAQADAAEJEQSCVAEpAAAAAA==.Crèscent:BAAALgADCgEJAQAAAA==.Crõwfather:BAABLgAECn8XAAIcAAgJmxzEEwB3AgAcAAgJmxzEEwB3AgAAAA==.',
Cu='Curtland:BAAALgAECgEJAQAAAA==.',
Cz='Czy:BAAALgAECgEJAQAAAA==.',
Da='Dadjokes:BAAALgAECgEJAQAAAA==.Darkakaza:BAAALgAECgYJCwAAAA==.Darkbu:BAAALgADCgcJCQABLgAFFAMJBQAFABEDAA==.Darkermagic:BAAALgAECgEJAQAAAA==.Darkmeadow:BAAALgAECgUJDAAAAA==.Dasgoose:BAAALgADCgIJAgAAAA==.Dastard:BAABLgAECn8bAAIRAAgJGhY9HwAWAgARAAgJGhY9HwAWAgAAAA==.Datmonk:BAAALgAECgcJEQAAAA==.Dave:BAAALgADCgEJAQAAAA==.',
De='Deadlymagic:BAAALgAECgMJAwAAAA==.Deadtorights:BAAALgAECgEJAQAAAA==.Deathblossom:BAAALgAECgUJCQAAAA==.Deathbrñgr:BAAALgADCgQJBAABLgAECggJGgADAK0UAA==.Deathlyfrost:BAABLgAECn8UAAIIAAcJ3hIsHQBhAQAIAAcJ3hIsHQBhAQAAAA==.Deathvader:BAAALgADCgcJFwAAAA==.Decimatore:BAAALgAECgMJAwAAAA==.Decrepitt:BAAALgADCgEJAQAAAA==.Dedara:BAAALgAECggJDgAAAA==.Deeptotes:BAAALgAECgQJBAAAAA==.Deftonia:BAAALgAECgcJEgAAAA==.Degenerate:BAABLgAECn8aAAMdAAgJhhSUDQCoAQAdAAgJpxKUDQCoAQAeAAUJbhlHDQBhAQAAAA==.Demonbläde:BAAALgAECgYJEwAAAA==.Demonbread:BAAALgADCgYJEAAAAA==.Demonmandis:BAAALgADCgEJAQAAAA==.Derriereizi:BAAALgADCgEJAQAAAA==.Devondric:BAABLgAECn8eAAILAAYJYBLjBwBrAQALAAYJYBLjBwBrAQAAAA==.Devotional:BAACLgAFFH8GAAIEAAQJmhDtAwA/AQAEAAQJmhDtAwA/AQAuAAQKfx8AAwQACAmzFHIGAO4BAAQACAmzFHIGAO4BAAMAAwktAvQgAVsAAAAA.',
Dh='Dhaos:BAAALgAECgIJAgABLgAECgcJEQACAAAAAA==.',
Di='Diekuh:BAAALgADCgEJAQAAAA==.Dinkellberg:BAAALgAECgQJBQAAAA==.Dirgens:BAACLgAFFH8NAAIdAAUJMRCVBwBIAQAdAAUJMRCVBwBIAQAuAAQKfyEAAh0ACAleIJwdAKUCAB0ACAleIJwdAKUCAAAA.Dirgenz:BAAALgADCgYJBgAAAA==.Disquietor:BAAALgADCgQJBQAAAA==.Divinacurita:BAAALgAECgQJCAAAAA==.',
Dk='Dkay:BAAALgADCgcJDQAAAA==.',
Do='Dodel:BAAALgADCgYJCgAAAA==.Dokumai:BAAALgAECgcJEQAAAA==.Dommiemommie:BAAALgADCgUJBQABLgAECgcJEQACAAAAAA==.Dooterfiddle:BAAALgAECgEJAQAAAA==.Doozerd:BAAALgAECgMJAwAAAA==.Doozerp:BAACLgAFFH8HAAILAAMJOAZPBwDMAAALAAMJOAZPBwDMAAAuAAQKfx4AAwsACAm5E1wbALwBAAsACAmAEFwbALwBAAcABQnvCyBNAAMBAAAA.Dor:BAAALgAECgEJAgAAAA==.Doraexplorer:BAAALgAECgEJAQAAAA==.Dorinmigrane:BAAALgADCgYJBgABLgAECgcJJAAPAK4eAA==.Dorinramps:BAABLgAECn8kAAIPAAcJrh4dNAApAgAPAAcJrh4dNAApAgAAAA==.Dotfearwin:BAAALgAECgYJDgAAAA==.Doviculus:BAAALgAECgQJBwAAAA==.',
Dr='Dragmcgoon:BAABLgAECn8dAAIFAAgJOhaKEwBIAgAFAAgJOhaKEwBIAgAAAA==.Drakonman:BAABLgAECn8UAAIRAAgJpQY0DQAsAQARAAgJpQY0DQAsAQAAAA==.Drakrappa:BAAALgADCgEJAgAAAA==.Drakthorr:BAAALgAECgcJEgAAAA==.Draynen:BAABLgAECn8cAAMcAAcJ/BkMIwANAgAcAAcJ/BkMIwANAgASAAIJfwO4KABQAAABLgAFFAQJBwAKAO4dAA==.Drboom:BAAALgADCgYJCgAAAA==.Drcrimo:BAACLgAFFH8NAAIOAAUJnxQsAwBHAQAOAAUJnxQsAwBHAQAuAAQKfyMAAg4ACAm6IjkIABIDAA4ACAm6IjkIABIDAAAA.Drdööm:BAAALgADCgEJAQAAAA==.Drevil:BAAALgAECgEJAQAAAA==.Drø:BAAALgADCgcJEQAAAA==.',
Du='Duck:BAAALgADCgEJAgAAAA==.Duckduck:BAAALgAECgUJBQAAAA==.Dudemanyeah:BAAALgADCgEJAQAAAA==.Dulcïnea:BAABLgAECn8bAAIPAAcJVRVCHQAbAQAPAAcJVRVCHQAbAQAAAA==.Dumbanimal:BAAALgAECgEJAQAAAA==.Durnir:BAAALgAECgMJAwAAAA==.Durut:BAAALgAECgUJDwAAAA==.',
Dw='Dwarfbussy:BAAALgADCggJFgAAAA==.',
['Dê']='Dêathany:BAAALgADCgMJBAAAAA==.',
Ea='Easley:BAAALgADCgcJCAABLgAECgcJEQACAAAAAA==.',
Ec='Ecliptic:BAAALgAECgEJAQAAAA==.',
Ed='Edrana:BAAALgADCgcJBwABLgAECgUJCAACAAAAAA==.Edurna:BAAALgADCgIJAgAAAA==.',
Eh='Ehvyn:BAAALgAECgQJCQAAAA==.',
El='Elementcreep:BAAALgADCgYJBwAAAA==.Elise:BAAALgAECgQJBAAAAA==.Eliza:BAAALgAECgYJBgAAAA==.Elizzabeth:BAAALgAECgYJDwAAAA==.Ellisis:BAAALgAECgcJEQAAAA==.Elvarg:BAAALgADCgQJBAABLgAECgQJCQACAAAAAA==.',
Em='Emriq:BAABLgAECn8UAAIDAAYJlCD7DADGAQADAAYJlCD7DADGAQAAAA==.',
En='Enmai:BAAALgAECgYJEQAAAA==.',
Ep='Ephius:BAAALgAECgUJDAAAAA==.',
Er='Eranar:BAAALgADCgMJAwAAAA==.Eraquxx:BAAALgADCgcJBwAAAA==.Ertironin:BAAALgADCgcJDgABLgAECggJGAABAHUMAA==.',
Es='Esper:BAAALgADCgcJBwABLgAECgQJBQACAAAAAA==.Esthar:BAAALgAECgYJEAAAAA==.',
Et='Etheko:BAAALgAECgQJBAAAAA==.',
Eu='Eudæmønia:BAAALgAECgYJEwAAAA==.',
Ev='Evangelise:BAAALgAECgIJAgAAAA==.Evella:BAAALgAECgUJBQAAAA==.',
Ex='Exodiusx:BAAALgAECgMJAwAAAA==.Exxitus:BAAALgAECgYJDQAAAA==.',
Ey='Eyebeam:BAAALgAECgEJAQAAAA==.Eyebrowsius:BAAALgAECgUJBQABLgAECggJGgAMAHcjAA==.',
Fa='Falorel:BAAALgADCgIJAgAAAA==.Falsoqt:BAAALgAECgYJDgAAAA==.Faragon:BAAALgAECgIJAgAAAA==.Faux:BAAALgADCgcJDgABLgAECggJHQAWAJwTAA==.Fayline:BAAALgAECgYJDAAAAA==.',
Fb='Fblthp:BAABLgAECn8VAAIBAAgJpRdPEgCvAQABAAgJpRdPEgCvAQAAAA==.',
Fe='Felachio:BAAALgAECgcJEgAAAA==.Felrush:BAAALgAECgEJAQAAAA==.Fenno:BAAALgAECgQJBQAAAA==.Fentfliction:BAAALgADCgYJBgAAAA==.',
Fi='Fidelitaslex:BAAALgADCgYJCAAAAA==.Firerage:BAAALgAECgcJEwAAAA==.Fischform:BAABLgAECn8eAAINAAgJJCXCAAAVAwANAAgJJCXCAAAVAwAAAA==.',
Fj='Fjörgyn:BAACLgAFFH8OAAIRAAUJ2R/zAgDDAQARAAUJ2R/zAgDDAQAuAAQKfyMAAhEACQmeJCEBAL8DABEACQmeJCEBAL8DAAAA.',
Fl='Flashlight:BAAALgADCgUJBQAAAA==.Flexr:BAAALgADCgMJAwAAAA==.',
Fo='Forsetí:BAAALgAECgIJAgAAAA==.Fortress:BAAALgADCgEJAQAAAA==.',
Fr='Frasierkrane:BAAALgADCgUJBQAAAA==.Frontshots:BAAALgADCgQJBAAAAA==.',
Ft='Ftfk:BAAALgADCgkJFwABLgAECggJHQAKAIUkAA==.',
Fu='Funguslice:BAAALgAECgYJCgABLgAECgUJCwACAAAAAA==.Funji:BAAALgAECgEJAQAAAA==.Funkyflank:BAAALgAECgMJAwAAAA==.',
Ga='Galactica:BAAALgADCgEJAQAAAA==.Galdoria:BAAALgAECgIJAgAAAA==.Galie:BAABLgAECn8iAAMOAAgJCBEnCQBdAQAOAAgJCBEnCQBdAQAfAAQJ3guhIgDDAAAAAA==.Galìe:BAAALgADCgcJDgAAAA==.Garrahoth:BAAALgADCgUJBQABLgAECgYJCQACAAAAAA==.Gatherith:BAAALgAECgMJAwAAAA==.',
Ge='Gekk:BAABLgAECn8VAAMKAAcJhBtmAgDwAQAKAAcJhBtmAgDwAQAFAAEJtRMbHwBBAAAAAA==.Gendarme:BAAALgAECgUJCAAAAA==.',
Gh='Ghostface:BAABLgAECn8bAAMEAAcJrQsVDwBMAQAEAAcJrQsVDwBMAQADAAEJiw7XNwE5AAAAAA==.Ghuun:BAAALgAECgEJAQAAAA==.',
Gi='Giaus:BAABLgAECn8aAAIBAAgJWxHQDgDPAQABAAgJWxHQDgDPAQAAAA==.Girthquakes:BAAALgAECgMJBQAAAA==.',
Gl='Glorified:BAAALgAECgIJAgAAAA==.Glump:BAAALgADCgMJAwAAAA==.',
Go='Gobzilla:BAABLgAECn8WAAIcAAcJSSFsEQCLAgAcAAcJSSFsEQCLAgAAAA==.Gonn:BAAALgADCgIJAgAAAA==.Goodboy:BAAALgADCggJDwAAAA==.Goonergramps:BAAALgADCgkJCQAAAA==.Goub:BAABLgAECn8ZAAMcAAgJ3B57FABxAgAcAAcJsx17FABxAgARAAYJhg4cFgDHAAAAAA==.Goubam:BAAALgAECgEJAQABLgAECggJGQAcANweAA==.',
Gr='Grapefroot:BAAALgAECgYJDwAAAA==.Grapeinator:BAAALgADCgQJBQAAAA==.Grapey:BAAALgAECgYJCQAAAA==.Greenarrow:BAAALgADCggJCAAAAA==.Greenwarlock:BAAALgAECgYJEwAAAA==.Grimhoof:BAAALgAECgMJAwAAAA==.Grimhorn:BAAALgAECgEJAQAAAA==.Gripdip:BAAALgAECgEJAQAAAA==.Grnola:BAABLgAECn8UAAITAAYJqxDengBDAQATAAYJqxDengBDAQAAAA==.',
Gu='Guldum:BAAALgADCgUJCwAAAA==.Gurvinder:BAAALgAECgYJBwAAAA==.',
Gw='Gwyne:BAABLgAECn8hAAITAAgJfiR+DQAuAwATAAgJfiR+DQAuAwAAAA==.',
Ha='Hailstorm:BAAALgADCgQJBQAAAA==.Halfstack:BAAALgAECgUJBQAAAA==.Halucid:BAAALgADCgIJAgAAAA==.Happywoodz:BAAALgAFFAEJAQAAAA==.Hardmoney:BAAALgADCgMJAwAAAA==.Harmsway:BAAALgADCgEJAQAAAA==.Hashed:BAABLgAECn8dAAIDAAgJPRnhNgBHAgADAAgJPRnhNgBHAgAAAA==.Haveanicejay:BAAALgAECgQJBQAAAA==.Haysevoker:BAACLgAFFH8MAAIKAAUJXRpJBwB5AQAKAAUJXRpJBwB5AQAuAAQKfx4AAwoACAkTISgGAOICAAoACAkTISgGAOICAAUAAgnAFs5PAI0AAAAA.Haysmonk:BAAALgAECgYJCwAAAA==.',
He='Heliumprime:BAAALgAECgEJAQAAAA==.Hellabrews:BAAALgAECgYJDAAAAA==.Hexcellent:BAAALgADCggJDwAAAA==.',
Ho='Hogra:BAAALgADCgUJBQABLgAECgYJFQAbAKgaAA==.Holstadd:BAAALgADCgcJCgAAAA==.Hoodler:BAECLgAFFH8OAAINAAUJmx/JAADzAQANAAUJmx/JAADzAQAuAAQKfyEAAg0ACAkqJm0DAFwDAA0ACAkqJm0DAFwDAAAA.Hoodlere:BAEALgAECgUJBQABLgAFFAUJDgANAJsfAA==.Hoodlery:BAEALgAECgYJBgABLgAFFAUJDgANAJsfAA==.Hortraz:BAAALgAECgUJCAAAAA==.',
Hr='Hrathen:BAAALgAECgEJAQAAAA==.',
Hu='Humphugull:BAAALgAECgYJEwAAAA==.Huntoine:BAAALgAECgYJDQABLgAFFAUJCgAJANwVAA==.Huskydots:BAABLgAECn8ZAAMdAAgJtRiAPwAPAgAdAAcJtRiAPwAPAgAQAAQJTw4UNADnAAAAAA==.',
Hy='Hyroshi:BAAALgADCgYJBgAAAA==.Hyur:BAAALgAECgQJCwAAAA==.',
Ib='Iblastpants:BAAALgAECgYJCwAAAA==.',
Ic='Ichoroath:BAAALgAECgYJCAAAAA==.',
Ig='Iggyy:BAAALgAECgMJDAAAAA==.',
Ij='Ijjii:BAAALgAECgYJBwAAAA==.',
Il='Ilgynoth:BAAALgAECgcJEwAAAA==.Illidaris:BAAALgADCgMJAwAAAA==.Illidonut:BAAALgADCgUJBAABLgAECgYJDgACAAAAAA==.',
Im='Imdeadinside:BAAALgAECgEJAQAAAA==.Imsuperlost:BAAALgADCgUJBQAAAA==.',
In='Infinitas:BAAALgADCgUJBgAAAA==.Inflammo:BAAALgAECgUJBQAAAA==.Inflic:BAAALgADCggJFQAAAA==.Inspectadeck:BAAALgAECgQJBAAAAA==.',
Ir='Irila:BAAALgAECggJEgAAAA==.Irmerlock:BAAALgADCgMJAwAAAA==.Irshadin:BAABLgAECn8eAAMDAAgJ9x6OOwA1AgADAAgJ9x6OOwA1AgAbAAIJUwaxPgBDAAAAAA==.Irshingwary:BAAALgADCggJCAAAAA==.',
Iz='Izumî:BAAALgAECgYJCQAAAA==.',
Ja='Jaebuns:BAAALgAECgQJBQAAAA==.Jakob:BAAALgAECgIJBAAAAA==.Jamiie:BAAALgAECgMJBAAAAA==.Jangosan:BAAALgADCgkJDwAAAA==.Jangutu:BAAALgAECgQJBwAAAA==.Jasonluv:BAAALgAECgQJCAAAAA==.Jaspy:BAABLgAECn8eAAIfAAgJjBJGAgDAAQAfAAgJjBJGAgDAAQAAAA==.Jaynee:BAABLgAECn8dAAIDAAgJkiRSAQDPAgADAAgJkiRSAQDPAgAAAA==.',
Ji='Jinharu:BAAALgADCgkJCQABLgAECgcJEQACAAAAAA==.',
Jo='Jomgpallie:BAAALgAECgYJDQAAAA==.Jonac:BAAALgAECgEJAQAAAA==.Josefbugman:BAAALgAECgUJDQAAAA==.',
Ju='Juicee:BAAALgADCgcJEQAAAA==.Juktal:BAAALgAECgcJEgAAAA==.Jukujo:BAAALgADCgEJAQAAAA==.Jupîter:BAAALgAECgQJCAAAAA==.Justyn:BAAALgAECgUJCQAAAA==.',
Ka='Kajoru:BAAALgADCgcJBwAAAA==.Kancho:BAAALgAECgMJBQAAAA==.Kattakuri:BAAALgADCgYJBgAAAA==.Kazuje:BAAALgAECgQJCAAAAA==.Kazzu:BAAALgAECgMJAwAAAA==.',
Ke='Ketia:BAAALgADCggJEQAAAA==.Keyal:BAEALgAECgcJCgABLgAFFAMJBQANAP8GAA==.',
Kh='Kheros:BAAALgAECgUJCwAAAA==.Khiron:BAAALgADCgUJCQAAAA==.',
Ki='Kialorstus:BAAALgAECgcJBwAAAA==.Kilarga:BAAALgADCgUJBQAAAA==.Kilo:BAAALgAECgUJCQAAAA==.Kimari:BAAALgADCgEJAgAAAA==.Kinzington:BAAALgAECgEJAQAAAA==.Kiriron:BAAALgAECgQJBgAAAA==.Kittyperry:BAAALgAECgMJAwABLgAECgcJEgACAAAAAA==.',
Ko='Kolakua:BAAALgADCgIJAgAAAA==.Kookiemonsta:BAAALgADCgcJAQAAAA==.Kouw:BAAALgAECgYJCgAAAA==.',
Kr='Kramx:BAAALgAECgUJCAAAAA==.Krankenstein:BAAALgAECgYJBgAAAA==.Krankson:BAAALgAECgYJDgAAAA==.Kriix:BAAALgAECgYJDAAAAA==.Krugah:BAAALgAECgQJCAAAAA==.Krusnik:BAAALgAECgMJBAAAAA==.',
Ks='Ksubi:BAAALgAECgEJAQAAAA==.',
Ku='Kuhnleone:BAAALgADCgcJBwAAAA==.Kujatas:BAABLgAECn8bAAIRAAcJGSIbAgBKAgARAAcJGSIbAgBKAgAAAA==.Kuls:BAAALgADCgcJBwAAAA==.Kuothe:BAABLgAECn8eAAIBAAgJNhJSFACfAQABAAgJNhJSFACfAQAAAA==.Kuroakami:BAAALgADCgkJDwAAAA==.',
Ky='Kyrael:BAAALgAECgUJCAAAAA==.',
['Kí']='Kíllahpriest:BAAALgADCgcJGgAAAA==.',
La='Laelunea:BAAALgAECggJEQAAAA==.Lambslayer:BAAALgADCgMJAwAAAA==.Lannsing:BAABLgAECn8lAAMHAAkJpByHAQCDAgAHAAgJ7B+HAQCDAgALAAkJ2gzCGwC4AQAAAA==.',
Le='Leetpkss:BAAALgADCgYJBgAAAA==.Lenaría:BAAALgADCgcJCgAAAA==.Leonheart:BAAALgADCgQJBQAAAA==.Lesnichii:BAAALgAECgcJEgAAAA==.Letemkrap:BAAALgAECgEJAwAAAA==.Lewakex:BAAALgAECgcJBgAAAA==.Leyendaz:BAAALgADCgUJBwAAAA==.Leyzormemes:BAABLgAECn8aAAIPAAgJHSJQGQC9AgAPAAgJHSJQGQC9AgAAAA==.',
Li='Lightbrngr:BAABLgAECn8aAAIDAAgJrRSaTAD9AQADAAgJrRSaTAD9AQAAAA==.Lihuai:BAABLgAECn8dAAMaAAgJ4wajCwAXAQAaAAgJ4wajCwAXAQAMAAYJ9gQHRwDAAAAAAA==.Lilbertha:BAABLgAECn8hAAMBAAgJFxL5cQDvAQABAAgJFxL5cQDvAQAgAAEJjQZsEAAyAAAAAA==.Lilconcon:BAABLgAECn8ZAAIRAAkJPxHFLACzAQARAAkJPxHFLACzAQAAAA==.Lildipster:BAAALgAECgMJAwABLgAECgQJBQACAAAAAA==.Lilthrall:BAAALgADCgkJFwAAAA==.Liptonaysti:BAAALgAECgYJCAAAAA==.Lissandine:BAABLgAECn8dAAIhAAgJYh2eBgAmAgAhAAgJYh2eBgAmAgAAAA==.Liuxin:BAAALgAECgQJBAAAAA==.Lizzywizzy:BAAALgADCgUJBQABLgAECgQJBQACAAAAAA==.',
Ll='Llaydee:BAAALgADCgUJBQAAAA==.',
Lo='Loalight:BAAALgADCgYJDAAAAA==.Lodencilly:BAAALgADCgIJAgAAAA==.Lomao:BAAALgADCgQJBQAAAA==.Longdude:BAAALgAECgcJCgAAAA==.Lorth:BAAALgADCgEJAQAAAA==.Lotharn:BAAALgAECgQJBQAAAA==.Lowdy:BAAALgAECgQJDQAAAA==.',
Lu='Lucas:BAABLgAECn8UAAIRAAcJCx8CIQAHAgARAAcJCx8CIQAHAgAAAA==.Lucifri:BAEBLgAECn8XAAIIAAYJWxTjHwBFAQAIAAYJWxTjHwBFAQAAAA==.Luckydo:BAAALgADCgUJBQABLgAECggJCgACAAAAAA==.Luckydoo:BAAALgAECggJCgAAAA==.Luvr:BAAALgADCgIJAgAAAA==.',
Ly='Lych:BAAALgAECgMJAwAAAA==.Lyclaw:BAAALgADCgMJAwAAAA==.',
['Lì']='Lìllith:BAAALgAECgYJEAAAAA==.',
Ma='Madting:BAAALgADCgEJAQAAAA==.Magnuss:BAABLgAECn8XAAIBAAgJUBR0awD/AQABAAgJUBR0awD/AQAAAA==.Majick:BAAALgADCgcJBwAAAA==.Malthaell:BAAALgAECggJEAAAAA==.Maltyablo:BAABLgAECn8UAAIhAAcJfRG8DgBnAQAhAAcJfRG8DgBnAQAAAA==.Mammutos:BAAALgAECgEJAQAAAA==.Manapaws:BAAALgAECgYJEQAAAA==.Manddarb:BAAALgADCgIJAgAAAA==.Manion:BAABLgAECn8dAAMRAAgJ3xQgBgCtAQARAAgJ3xQgBgCtAQAcAAIJWQj3iwBlAAAAAA==.Manipulating:BAAALgAECgMJAwAAAA==.Manipulation:BAAALgAECgQJCwAAAA==.Mannarchy:BAAALgAECgYJEAAAAA==.Manpan:BAAALgAECgEJAgAAAA==.Mantrà:BAAALgADCgkJFwAAAA==.Margot:BAAALgADCgQJBAABLgAECgIJBAACAAAAAA==.Marquise:BAABLgAECn8ZAAMFAAgJbRS+GQD/AQAFAAgJcxO+GQD/AQAGAAYJHxSZFwB9AQAAAA==.Masochista:BAABLgAFFH8LAAIIAAUJIiHNBABaAQAIAAUJIiHNBABaAQAAAA==.Mastavas:BAAALgADCgIJAgAAAA==.Mastric:BAEBLgAECn8dAAIdAAgJ5wQMGwA+AQAdAAgJ5wQMGwA+AQAAAA==.Matarkbro:BAABLgAECn8YAAIWAAcJEBZLFADHAQAWAAcJEBZLFADHAQAAAA==.Maudelyn:BAAALgADCgQJBgAAAA==.Mayumißrown:BAAALgADCgUJBwAAAA==.Mazrin:BAAALgADCgEJAQAAAA==.',
Mc='Mccaffrey:BAABLgAECn8VAAMZAAcJvhOWCgB2AQAZAAcJvhOWCgB2AQAYAAEJ+g+ePAA/AAAAAA==.Mcstuffings:BAAALgADCgUJBQABLgAECgcJFwAcAF8cAA==.',
Me='Meetch:BAABLgAECn8dAAITAAgJghc2QQA0AgATAAgJghc2QQA0AgAAAA==.Megdar:BAAALgAECgMJAwAAAA==.Meldbot:BAAALgAECgcJDQAAAA==.Merix:BAABLgAECn8ZAAIVAAgJeRqxCwDbAgAVAAgJeRqxCwDbAgAAAA==.Mestea:BAAALgAECgQJBQAAAA==.Mexorcistp:BAABLgAECn8XAAIEAAgJxBlhGABPAgAEAAgJxBlhGABPAgAAAA==.Mexorcists:BAAALgAECgEJAwABLgAECggJFwAEAMQZAA==.',
Mi='Mirra:BAAALgAECgIJAgAAAA==.Mirus:BAABLgAECn8aAAMiAAgJlRYUMwDjAQAiAAgJ6BMUMwDjAQAjAAYJmQ3+GAA/AQAAAA==.',
Ml='Mlee:BAAALgAECgQJBAAAAA==.',
Mo='Mojobtw:BAABLgAECn8fAAMEAAgJqSV8AwA6AwAEAAgJqSV8AwA6AwADAAEJlRSIOgE3AAAAAA==.Monkeyc:BAAALgADCgEJAQAAAA==.Monos:BAAALgADCgQJBAAAAA==.Monsterboy:BAAALgADCgcJCQAAAA==.Mooby:BAAALgADCgYJBgAAAA==.Moontouched:BAAALgAECgEJAQABLgAECgYJCwACAAAAAA==.Mord:BAAALgAECgEJAQAAAA==.Morrkoth:BAAALgADCgYJBgAAAA==.Mors:BAAALgAECgYJBgAAAA==.Mortamur:BAABLgAECn8eAAIBAAgJvxOeFQCWAQABAAgJvxOeFQCWAQAAAA==.Mortelinnos:BAABLgAECn8XAAMXAAcJBRe3GgDtAQAXAAcJBRe3GgDtAQAPAAEJAABqXgAAAAAAAA==.',
Ms='Msadventure:BAAALgADCgMJAwAAAA==.',
Mu='Murney:BAAALgADCgcJBwAAAA==.Muzzledmage:BAEALgAECgYJEgAAAA==.',
My='Myfirstlady:BAAALgADCgEJAQAAAA==.Myparse:BAABLgAECn8UAAIPAAcJlBytRQDdAQAPAAcJlBytRQDdAQAAAA==.Mysticguru:BAABLgAECn8XAAIcAAcJXxwUKQDrAQAcAAcJXxwUKQDrAQAAAA==.',
['Mà']='Mànyen:BAAALgADCgcJDgAAAA==.',
Na='Nadiaa:BAAALgADCgMJAwAAAA==.Naisu:BAAALgAECgEJAQAAAA==.Nanibear:BAAALgADCgkJEQAAAA==.Narodaran:BAAALgAECgIJAgAAAA==.Natebrew:BAAALgADCgkJEgABLgAECggJJQAPAPIeAA==.Nattsume:BAAALgADCgcJBwAAAA==.Natural:BAABLgAECn8UAAQfAAcJthrOCABNAgAfAAcJthrOCABNAgAkAAMJxBBdIQCTAAANAAIJigUovwBJAAAAAA==.Naughtÿ:BAAALgAECgEJAQAAAA==.',
Ne='Neco:BAAALgAECgQJCQAAAA==.Necropete:BAABLgAECn8bAAITAAgJPBlMCQDqAQATAAgJPBlMCQDqAQAAAA==.Nerudian:BAAALgADCgMJAwAAAA==.Nevets:BAABLgAECn8XAAMlAAcJHRjQJwDoAQAlAAcJPxfQJwDoAQAjAAUJiA+MHQAAAQAAAA==.Nevrs:BAAALgAECgQJCAAAAA==.',
Ni='Nickkshield:BAAALgADCgYJBgAAAA==.Nimit:BAABLgAECn8aAAMiAAgJQRr0BgD8AQAiAAgJWBn0BgD8AQAjAAUJKRYrGwAhAQAAAA==.Nipha:BAAALgAECgMJBQAAAA==.',
No='Noct:BAAALgAECgMJBAAAAA==.Nofoxgivn:BAAALgAECgIJAgABLgAECggJGgADAK0UAA==.Nogreencardx:BAAALgAECgUJCgAAAA==.Nooblez:BAAALgADCgYJBgAAAA==.Notsenka:BAABLgAECn8UAAIVAAcJHgemLwCHAQAVAAcJHgemLwCHAQAAAA==.Notzee:BAAALgADCgMJAwAAAA==.Novic:BAABLgAECn8eAAIHAAgJkBpgBADzAQAHAAgJkBpgBADzAQAAAA==.',
Nu='Nualia:BAABLgAECn8UAAIDAAcJPBg4TgD4AQADAAcJPBg4TgD4AQAAAA==.Nulg:BAAALgADCgIJAgAAAA==.',
Ny='Nyssathasong:BAAALgAECgcJDwAAAA==.',
['Nä']='Nägash:BAAALgAECgMJBgAAAA==.',
Oa='Oathkeeper:BAAALgAECgMJAwAAAA==.',
Oj='Ojaks:BAAALgAECgMJAwAAAA==.',
Om='Omatiaa:BAECLgAFFH8FAAIRAAIJLQ1YCwCLAAARAAIJLQ1YCwCLAAAuAAQKfyUAAhEACAm8HBQVAHUCABEACAm8HBQVAHUCAAAA.',
Oo='Oongawa:BAAALgADCgQJBAAAAA==.',
Or='Oraxus:BAAALgAECgEJAQAAAA==.Oreface:BAAALgAECgEJAQAAAA==.Orobus:BAABLgAECn8cAAIWAAgJkCCaAQAxAgAWAAgJkCCaAQAxAgAAAA==.',
Os='Oscassey:BAABLgAECn8UAAImAAcJygguAwBKAQAmAAcJygguAwBKAQAAAA==.',
Ox='Oxley:BAABLgAECn8VAAIfAAcJjxsRAgDQAQAfAAcJjxsRAgDQAQAAAA==.',
Pa='Pacifica:BAAALgAECgMJAwAAAA==.Paladingus:BAAALgAECgcJEAAAAA==.Pallumx:BAAALgAECgEJAQAAAA==.Pandidin:BAAALgAECggJEQAAAA==.Pastasaladin:BAAALgAECgEJAQAAAA==.Pauldrons:BAABLgAECn86AAITAAgJuhE1DwCeAQATAAgJuhE1DwCeAQAAAA==.',
Pe='Peenar:BAAALgAECggJEQAAAA==.',
Ph='Pharlock:BAAALgAECgUJCgAAAA==.Phlebite:BAAALgAECgYJCwAAAA==.Phobia:BAAALgADCgkJCQABLgAECggJHQAWAJwTAA==.',
Pi='Pichurri:BAAALgAECgQJDQAAAA==.Pigpen:BAAALgAECgQJCwAAAA==.Pilk:BAAALgADCgUJBwAAAA==.Pineapplexp:BAAALgADCggJBwAAAA==.',
Pk='Pk:BAABLgAECn8mAAInAAkJUh4NAAAAAwAnAAkJUh4NAAAAAwAAAA==.',
Pl='Planky:BAAALgADCggJEAAAAA==.',
Po='Pooterdiddle:BAAALgADCgUJBQAAAA==.Porunga:BAAALgAECgcJBwAAAA==.Poshinek:BAAALgAECgIJAgABLgAECgIJAgACAAAAAA==.',
Pr='Predobear:BAAALgAECgYJDwAAAA==.Prohealin:BAABLgAECn8eAAIHAAgJchXuAwAGAgAHAAgJchXuAwAGAgAAAA==.Protojack:BAAALgADCgEJAQABLgAFFAUJDAAEAK0aAA==.Pryx:BAAALgAECgcJBgAAAA==.',
Ps='Psychosís:BAAALgAECgIJBQAAAA==.',
Pu='Pumpkinq:BAACLgAFFH8FAAIVAAIJyw1XEwCyAAAVAAIJyw1XEwCyAAAuAAQKfykAAhUACAlVIxMGADADABUACAlVIxMGADADAAAA.Purin:BAABLgAECn8dAAMeAAgJByMjAACZAgAeAAcJByMjAACZAgAQAAIJnA4uRACkAAAAAA==.',
Pw='Pwnzorus:BAAALgAECgEJAwAAAA==.',
['Pì']='Pìkachu:BAABLgAECn8dAAIBAAgJPBjUDwDFAQABAAgJPBjUDwDFAQAAAA==.',
Ra='Radon:BAAALgAECgUJBgAAAA==.Raekwon:BAAALgAECgEJAQAAAA==.Ramzita:BAAALgAECgYJCQAAAA==.Randic:BAAALgAECgYJBgAAAA==.Raptok:BAAALgAECgQJDwAAAA==.Rasmus:BAABLgAECn8dAAIbAAgJBBtXAgDUAQAbAAgJBBtXAgDUAQAAAA==.Raykwan:BAAALgAECgUJBQAAAA==.Rayquaza:BAABLgAECn8dAAIKAAgJhSQwAABNAwAKAAgJhSQwAABNAwAAAA==.Razmatazz:BAABLgAECn8UAAMFAAYJ1hjrCwApAQAFAAYJ1hjrCwApAQAGAAMJbhflLgChAAAAAA==.',
Re='Reddeyes:BAAALgAECgUJCQAAAA==.Reignleif:BAAALgADCgMJAwAAAA==.Rektalhammer:BAAALgAECgcJEgAAAA==.Rescue:BAABLgAECn8ZAAIBAAgJjxeCTQBOAgABAAgJjxeCTQBOAgAAAA==.Reukha:BAAALgAECgUJCQAAAA==.Rev:BAAALgADCgUJBQABLgAECggJBwACAAAAAA==.',
Rh='Rhavik:BAAALgADCgcJCgAAAA==.',
Ri='Rickrollins:BAABLgAECn8bAAIaAAgJyiPIAACcAgAaAAgJyiPIAACcAgAAAA==.Rimreaper:BAAALgADCgYJEgAAAA==.Rinedara:BAAALgADCgMJAwAAAA==.',
Ro='Roachmonger:BAAALgAECgcJEgAAAA==.Roasted:BAAALgAECgcJEAAAAA==.Robotodh:BAAALgAECgEJAQAAAA==.Rockma:BAABLgAECn8gAAIRAAkJuRA9KQDLAQARAAkJuRA9KQDLAQAAAA==.Rockyroad:BAAALgADCgQJBAAAAA==.Rollandburn:BAAALgAECgYJCwAAAA==.Rondó:BAABLgAECn8XAAMDAAcJvRQzjwBdAQADAAcJXBAzjwBdAQAbAAQJ+RABKADJAAAAAA==.Rosao:BAAALgAECgEJAQAAAA==.Rotblack:BAAALgAECgQJBQABLgAFFAEJAQACAAAAAA==.Rotrogue:BAAALgADCgYJBgAAAA==.Rougerhaegar:BAAALgAECgIJAgAAAA==.Rozdomu:BAAALgAECgYJBgAAAA==.',
Ru='Ruff:BAAALgADCgcJDgAAAA==.Rufföaddy:BAABLgAECn8dAAIEAAgJRyFXAQC7AgAEAAgJRyFXAQC7AgAAAA==.Runeesa:BAAALgAECgUJCgAAAA==.Rustaxe:BAAALgADCgEJAQAAAA==.',
Ry='Rylena:BAAALgAECgYJEQAAAA==.Ryuke:BAAALgADCgYJBgAAAA==.Ryvalry:BAAALgAECgcJDAAAAA==.Ryzzhorn:BAAALgAECgcJEAAAAA==.',
['Rà']='Ràvenn:BAAALgAECgUJCAAAAA==.',
['Râ']='Râmên:BAAALgAECgEJAQAAAA==.',
['Rí']='Ríchter:BAABLgAECn8dAAIPAAgJSBqODQCjAQAPAAgJSBqODQCjAQAAAA==.',
Sa='Sagikos:BAECLgAFFH8FAAINAAMJ/wbYEwDJAAANAAMJ/wbYEwDJAAAuAAQKfx4AAg0ACAktIXQKAO8CAA0ACAktIXQKAO8CAAAA.Sagua:BAAALgAECgcJAwAAAA==.Saintvader:BAAALgADCgEJAgAAAA==.Saki:BAAALgAECgUJBgAAAA==.Sammiches:BAAALgADCgcJBwAAAA==.Sanstormrage:BAAALgAECgUJDQABLgAECgcJBwACAAAAAA==.Sardras:BAABLgAECn8dAAINAAgJBCOsAAAdAwANAAgJBCOsAAAdAwAAAA==.Sark:BAABLgAECn8UAAITAAgJ+ANEqAAxAQATAAgJ+ANEqAAxAQAAAA==.Sathor:BAAALgAECgkJCQAAAA==.Saucyjenkins:BAAALgAECgQJCAAAAA==.',
Sc='Scranton:BAAALgADCgEJAQAAAA==.',
Se='Sedgwin:BAAALgADCgIJAgAAAA==.Segundus:BAAALgADCgEJAQAAAA==.Sellout:BAAALgAECgcJDAAAAA==.Semprefi:BAAALgADCgYJBgAAAA==.Seph:BAAALgADCgMJAwAAAA==.Sepharion:BAAALgADCgcJBwABLgAECggJGgAdAJIjAA==.Seraphymn:BAAALgAECgQJBAAAAA==.Serenitree:BAAALgADCgMJAwAAAA==.',
Sg='Sgrios:BAEALgADCggJCQABLgAFFAIJBQARAC0NAA==.',
Sh='Shaani:BAAALgAECgYJEgAAAA==.Shadydh:BAAALgADCggJFQAAAA==.Shammehh:BAAALgADCgEJAQAAAA==.Shammooz:BAABLgAECn8UAAIRAAcJrgSWEQD4AAARAAcJrgSWEQD4AAAAAA==.Sharkimon:BAAALgADCgEJAQAAAA==.Sheefu:BAAALgADCgkJCwAAAA==.Shinier:BAAALgAECgEJAQAAAA==.Shockersz:BAAALgAECgIJAgAAAA==.Shockwoods:BAAALgAECgMJAwABLgAFFAEJAQACAAAAAA==.Shondo:BAABLgAECn8dAAMVAAcJMCOYAwDfAQAVAAYJgCSYAwDfAQAmAAMJER1nEQDyAAAAAA==.',
Si='Sidhell:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.Sigur:BAAALgADCgQJBAAAAA==.Silverin:BAAALgADCgYJBgAAAA==.Silvertraps:BAAALgADCgYJBgAAAA==.Sinthus:BAAALgAECgcJDwAAAA==.',
Sk='Skelatel:BAAALgADCgIJAgAAAA==.Skinard:BAAALgADCgcJEgAAAA==.',
Sl='Slappywappy:BAABLgAECn8YAAIBAAcJsRgMbgD5AQABAAcJsRgMbgD5AQAAAA==.',
Sm='Smashing:BAAALgADCgEJAQAAAA==.Smegghead:BAAALgADCgcJDgAAAA==.Smhitehapens:BAAALgAECgMJBwAAAA==.',
Sn='Sneekybeef:BAAALgAECgEJAQAAAA==.Snekk:BAAALgAECgcJEgAAAA==.Snooks:BAABLgAECn8cAAIMAAgJrhOwBADmAQAMAAgJrhOwBADmAQAAAA==.Snowen:BAAALgAECgMJAwABLgAECggJDgACAAAAAA==.',
So='Solegir:BAAALgADCgUJBQABLgAECgIJBAACAAAAAA==.Somthinlight:BAAALgAECgIJAgABLgAFFAMJBQAKAAQXAA==.Songas:BAAALgADCgYJBgAAAA==.Sonroku:BAAALgAECgMJAwAAAA==.Soundwaves:BAAALgAECgUJBQAAAA==.Soziin:BAAALgADCgcJBwAAAA==.',
Sp='Spellnchill:BAAALgAECgUJCAAAAA==.Spharai:BAAALgADCgMJAwAAAA==.Spintor:BAAALgAECgUJCgAAAA==.Spookyy:BAAALgADCgUJBQAAAA==.',
Sq='Squidseye:BAAALgADCgMJAwAAAA==.',
St='Stainn:BAAALgAECgQJBAAAAA==.Stinkyhippie:BAAALgADCggJCAAAAA==.Stricker:BAAALgAECgQJBgAAAA==.Strickerz:BAAALgAECgEJAQAAAA==.Strongwoman:BAAALgAECgQJBgAAAA==.',
Su='Sucrose:BAAALgAECgUJCQAAAA==.Sunshine:BAAALgADCgEJAQAAAA==.Supernovaz:BAAALgAECgUJBgAAAA==.',
Sy='Symmas:BAAALgADCgMJAwAAAA==.Synterra:BAAALgAECgYJDgAAAA==.Syphian:BAAALgADCgcJCAAAAA==.Syrenda:BAAALgADCgcJDQAAAA==.Syymmaass:BAAALgAECgEJAQAAAA==.',
Ta='Taishigi:BAABLgAECn8gAAIdAAgJ6g5iFABtAQAdAAgJ6g5iFABtAQAAAA==.Talarian:BAAALgADCgQJBAAAAA==.Tapewyrm:BAAALgAECgcJEQAAAA==.Tastylicks:BAAALgADCgYJBgAAAA==.',
Te='Techz:BAAALgADCgQJBAAAAA==.Teckni:BAABLgAECn8dAAIZAAgJShrEHwBTAgAZAAgJShrEHwBTAgAAAA==.Teedge:BAABLgAECn8UAAMFAAYJbRy5GgD0AQAFAAYJbRy5GgD0AQAGAAQJLA9DKQDVAAAAAA==.Teejadin:BAAALgADCgEJAQAAAA==.Telluride:BAAALgAECgcJEAAAAA==.Testtubegub:BAAALgAECgcJCgAAAA==.',
Th='Tharagis:BAAALgAECgYJDwAAAA==.Thecanadìan:BAAALgADCgUJBQAAAA==.Thehallowed:BAAALgADCgkJFgAAAA==.Theophrastus:BAAALgADCgYJCwAAAA==.Thepromise:BAABLgAECn8cAAIDAAgJ2wyvEgCNAQADAAgJ2wyvEgCNAQAAAA==.Thewai:BAABLgAECn8UAAIOAAcJNBGULACeAQAOAAcJNBGULACeAQAAAA==.Thralia:BAAALgADCggJBgAAAA==.',
Ti='Timberlord:BAAALgAECgEJAQAAAA==.Timmytwotoes:BAAALgADCgEJAQAAAA==.',
To='Toovok:BAAALgADCgcJHAAAAA==.Totemtartt:BAAALgADCgYJBgAAAA==.Toxicai:BAABLgAECn8UAAIoAAgJdgmPCwA2AQAoAAgJdgmPCwA2AQAAAA==.Toxicvoid:BAAALgADCgcJBwABLgAECggJFAAoAHYJAA==.',
Tr='Trakeus:BAABLgAECn8lAAIPAAgJ8h5THwCVAgAPAAgJ8h5THwCVAgAAAA==.Trinitree:BAABLgAECn8dAAIEAAgJshMfBwDcAQAEAAgJshMfBwDcAQAAAA==.Trinkler:BAAALgAECgUJDAAAAA==.Trinklr:BAAALgADCgYJBgABLgAECgUJDAACAAAAAA==.Tryhard:BAAALgAECgYJEwABLgAECggJBwACAAAAAA==.Trée:BAAALgADCgkJEAAAAA==.',
Tu='Tunka:BAAALgAECgEJAQAAAA==.Tuulikki:BAAALgADCgYJBgAAAA==.',
Tw='Twist:BAABLgAECn8TAAIBAAcJDg4l0ABMAQABAAcJDg4l0ABMAQAAAA==.',
Ty='Tychondris:BAABLgAECn8bAAIiAAcJLQwwVwBjAQAiAAcJLQwwVwBjAQAAAA==.Typobad:BAAALgAECgkJBgAAAA==.',
Ug='Ugrikester:BAAALgAECgEJAQAAAA==.',
Ul='Ulsoga:BAAALgAECgYJEQAAAA==.',
Un='Unavailidan:BAAALgAECgUJBgAAAA==.',
Ur='Urpalnanners:BAAALgAECgMJAwAAAA==.',
Va='Valkana:BAAALgAECgQJCAAAAA==.Vanicy:BAAALgAECgUJCAAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varibash:BAABLgAECn8dAAIWAAgJnBOSBACBAQAWAAgJnBOSBACBAQAAAA==.Vaspara:BAABLgAECn8YAAIEAAgJ8CCiAQCjAgAEAAgJ8CCiAQCjAgAAAA==.',
Ve='Veggiemite:BAAALgADCgYJBgAAAA==.Veggiesticks:BAAALgADCgYJDAAAAA==.Velyndra:BAAALgAECgQJBAAAAA==.Vendarius:BAAALgADCgMJAwAAAA==.Vere:BAABLgAECn8hAAISAAgJRCJqAACiAgASAAgJRCJqAACiAgAAAA==.Vestarin:BAAALgAECgcJDwAAAA==.',
Vi='Vicromano:BAAALgADCgMJAwAAAA==.Vilified:BAAALgAECgcJDgAAAA==.Vinoamante:BAAALgADCgEJAQAAAA==.Visark:BAAALgADCgYJCwAAAA==.',
Vo='Voidlìlíth:BAABLgAECn8jAAIBAAcJcBxtTABRAgABAAcJcBxtTABRAgAAAA==.Voidwak:BAAALgAECgYJDgAAAA==.Volcarona:BAAALgADCgcJDQAAAA==.Voronir:BAABLgAECn8VAAINAAcJeBVKDQCAAQANAAcJeBVKDQCAAQAAAA==.Vospox:BAAALgAECgcJBwAAAA==.',
Vu='Vulcan:BAAALgAECgYJCwAAAA==.',
Vy='Vyndra:BAAALgADCgIJAgAAAA==.',
['Vä']='Väder:BAAALgADCgEJAQAAAA==.',
Wa='Warbloom:BAAALgAECgYJBgAAAA==.Wardbirdname:BAAALgADCgYJBgAAAA==.Wardo:BAACLgAFFH8OAAMdAAUJhRYYBgBZAQAdAAUJfxIYBgBZAQAQAAQJYhQCBABUAQAuAAQKfycAAxAACAnPIdUBAP8CABAACAnPIdUBAP8CAB0ABQlNHzNTAM4BAAAA.Warplank:BAAALgAECgQJBgAAAA==.Wawwior:BAAALgAECgEJAQAAAA==.',
We='Welders:BAAALgAECgcJAQABLgAECggJGgAcALggAA==.Weleronys:BAAALgAECgUJCgAAAA==.Wellen:BAAALgAECgYJEAAAAA==.Werewolf:BAAALgADCgkJFAAAAA==.',
Wh='Whelplayed:BAAALgAECgYJEwAAAA==.Whitemaine:BAAALgAECgUJCwAAAA==.Whitepikmin:BAABLgAECn8eAAMkAAgJoBqECAAjAgAkAAgJoBqECAAjAgAfAAIJjg0xKwBtAAAAAA==.Whizzleton:BAAALgADCgMJAwAAAA==.',
Wi='Wilmer:BAABLgAECn8eAAIiAAgJXR4QEgCnAgAiAAgJXR4QEgCnAgAAAA==.Windowsvista:BAAALgAECgEJAQAAAA==.Wissa:BAAALgAECgUJBgAAAA==.Wiznasty:BAAALgADCgcJDQAAAA==.',
Wo='Wonrei:BAAALgADCgIJAgAAAA==.',
Wr='Wravc:BAAALgAECggJHwAAAQ==.Wravient:BAAALgADCgQJBAABLgAECggJHwACAAAAAQ==.',
Ww='Wwotw:BAAALgADCgcJBwAAAA==.',
Xa='Xanniheals:BAAALgAECgUJBQAAAA==.Xapphire:BAAALgADCgMJAgAAAA==.Xaspen:BAAALgAECgYJCgAAAA==.',
Xm='Xmysticxz:BAAALgADCgYJBgAAAA==.',
Xo='Xoyan:BAAALgAECgMJAwAAAA==.',
Ya='Yahs:BAAALgADCggJCAAAAA==.Yargonz:BAAALgAECgYJCwAAAA==.Yargzdk:BAACLgAFFH8OAAIIAAUJ0xHzBgAjAQAIAAUJ0xHzBgAjAQAuAAQKfywAAggACAnHHdQJAH8CAAgACAnHHdQJAH8CAAAA.Yargzvoker:BAAALgADCgcJDQAAAA==.Yatyas:BAAALgADCgEJAQAAAA==.',
Ye='Yeyin:BAAALgAECgUJCgAAAA==.Yeyol:BAAALgAECgYJCQAAAA==.',
Yi='Yitpoo:BAAALgAECgUJDQAAAA==.',
Yo='Yokubo:BAABLgAECn8UAAIdAAcJuRZRUwDNAQAdAAcJuRZRUwDNAQAAAA==.Yolius:BAAALgAECgYJBgAAAA==.Yoogi:BAAALgAECgYJCQAAAA==.Youngbullet:BAAALgADCgUJBQAAAA==.Yoyex:BAAALgAECgUJBgABLgAECgYJBgACAAAAAA==.',
Yu='Yunikon:BAAALgAECgQJBQAAAA==.',
Ze='Zellus:BAAALgAECgYJEgAAAA==.Zelrin:BAAALgADCgIJAgAAAA==.Zensei:BAAALgAECgIJAgABLgAECgYJBgACAAAAAA==.Zensix:BAAALgAECgcJEAAAAA==.',
Zh='Zhaphiria:BAAALgAECgcJBwABLgAFFAQJBwAKAO4dAA==.Zhul:BAAALgAECgYJEQABLgAECgcJEAACAAAAAA==.',
Zi='Zimmy:BAAALgADCgEJAQAAAA==.',
Zo='Zoku:BAAALgADCgIJAgAAAA==.',
Zu='Zugmà:BAABLgAECn8VAAIVAAcJYgdUOgBFAQAVAAcJYgdUOgBFAQAAAA==.Zukzug:BAAALgAECgUJCwAAAA==.',
['Äl']='Älpha:BAAALgAECgQJBAAAAA==.',
['Åz']='Åzïmvashÿak:BAAALgADCgcJBwAAAA==.',
['Çh']='Çhrõmié:BAABLgAECn8VAAIbAAcJvQ4QCAD8AAAbAAcJvQ4QCAD8AAAAAA==.',
['Çr']='Çrønus:BAAALgAECgUJBwAAAA==.',
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

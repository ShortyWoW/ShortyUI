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

local lookup = {'Unknown-Unknown','Mage-Frost','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Priest-Holy','DeathKnight-Blood','Priest-Shadow','Evoker-Preservation','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','Druid-Balance','DemonHunter-Devourer','Druid-Feral','Warlock-Destruction','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Monk-Brewmaster','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Hunter-Survival','Rogue-Assassination','Mage-Fire','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aajax:BAAALgAECgQJCwAAAA==.',
Ab='Abzdh:BAAALgAFFAIJBAAAAA==.Abzlock:BAAALgAECgEJAQABLgAFFAIJBAABAAAAAA==.Abzmage:BAABLgAECn8kAAICAAgJxiJpGgAOAwACAAgJxiJpGgAOAwABLgAFFAIJBAABAAAAAA==.',
Ac='Acht:BAAALgAECgYJBgAAAA==.',
Ad='Adderpal:BAAALgAECgQJCgAAAA==.Adelyreith:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Adramelach:BAABLgAECn8VAAIDAAYJ1B1QOwBYAQADAAYJ1B1QOwBYAQAAAA==.Adriel:BAAALgADCgQJBAABLgAECgQJBAABAAAAAA==.',
Ae='Aeiay:BAAALgAECgUJDgAAAA==.',
Ag='Again:BAAALgAECgQJBAAAAA==.',
Ai='Aibh:BAAALgAECgQJBAAAAA==.Ainzooalgown:BAABLgAECn8dAAICAAgJ/RcQQwBlAQACAAgJ/RcQQwBlAQAAAA==.',
Al='Alastorian:BAAALgADCgMJAwABLgAECgUJDAABAAAAAA==.Alethice:BAAALgADCgMJAwABLgAECggJEwABAAAAAA==.Alexandrap:BAAALgAECgIJBAAAAA==.Alindis:BAAALgADCgUJAgABLgAECgcJDAABAAAAAA==.Allmighto:BAECLgAFFH8TAAIEAAYJ1B8sAgDdAQAEAAYJ1B8sAgDdAQAuAAQKfyIAAgQACAl4JYQBAG0DAAQACAl4JYQBAG0DAAAA.',
An='Androstraz:BAACLgAFFH8LAAMFAAQJHCD5EAApAQAFAAQJHCD5EAApAQAGAAIJjgcMBwCdAAAuAAQKfx4AAwYACAlyHzUMABcCAAYABwliHDUMABcCAAUABQknH/McAN8BAAAA.Anniesthesia:BAABLgAECn8gAAIHAAgJ5QOfHgANAQAHAAgJ5QOfHgANAQAAAA==.Anoobyss:BAAALgAECgYJCwAAAA==.Anorexorcist:BAAALgADCgkJEQABLgAECggJJQAIAKQWAA==.Anorxxorcist:BAABLgAECn8lAAIIAAgJpBZyCACTAQAIAAgJpBZyCACTAQAAAA==.Anthraxx:BAAALgAECgEJAgAAAA==.',
Ap='Appledeez:BAABLgAECn8kAAIJAAgJShurEQBvAgAJAAgJShurEQBvAgAAAA==.',
Ar='Archenemyy:BAAALgAECgYJBgAAAA==.Arda:BAAALgAECgUJDAAAAA==.Arrax:BAACLgAFFH8HAAIKAAQJARfhDQD9AAAKAAQJARfhDQD9AAAuAAQKfxwAAwoACAlZIUUEABADAAoACAlZIUUEABADAAYAAQmlBrsTADYAAAAA.Arune:BAAALgAECgYJEQAAAA==.Arunem:BAAALgADCgYJCgABLgAECgYJEQABAAAAAA==.Arunen:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
As='Asapgbaby:BAAALgAECgEJAQAAAA==.Ashari:BAAALgAECgEJAQAAAA==.Ashly:BAAALgAECgQJDQAAAA==.Aspyrx:BAABLgAECn8aAAIIAAgJkw83DgAvAQAIAAgJkw83DgAvAQAAAA==.Astelan:BAECLgAFFH8GAAILAAMJpxdREAAEAQALAAMJpxdREAAEAQAuAAQKfzwAAwsACAlqJcQAAHIDAAsACAlqJcQAAHIDAAkABwlNGvQNAKUBAAAA.Astronomica:BAABLgAECn8XAAMEAAgJhRFNHgBWAQAEAAgJhRFNHgBWAQADAAUJhAi5ggCnAAAAAA==.Asunder:BAAALgAECgYJDwAAAA==.',
At='Atumsphinx:BAAALgADCgUJBQAAAA==.',
Au='Aurorä:BAAALgAECgYJDwAAAA==.',
Aw='Awfulrofl:BAAALgADCgYJCgAAAA==.',
Ay='Ayeola:BAAALgAECggJEwAAAA==.',
Az='Azareldurson:BAAALgAECgkJEAAAAA==.Azuresh:BAAALgAECgcJDgABLgAFFAIJBgAMAGYhAA==.',
Ba='Baalrogg:BAAALgADCgYJBwAAAA==.Babywipes:BAABLgAECn8aAAQNAAgJqh6PHABYAgANAAgJqh6PHABYAgAOAAYJzxxbBgCXAQAPAAEJqw42hQArAAAAAA==.Bachaterah:BAAALgAECgYJCwAAAA==.Baddawg:BAAALgAECgEJAgAAAA==.Baeldaeg:BAABLgAECn8fAAIQAAgJUyP9HACkAgAQAAgJUyP9HACkAgABLgAECgQJBQABAAAAAA==.Baelin:BAAALgAECgQJCQAAAA==.Bahahahamut:BAAALgADCgYJBwABLgAECgQJBQABAAAAAA==.Baked:BAAALgADCgEJAQAAAA==.Balkar:BAAALgADCgcJCQAAAA==.Bannett:BAACLgAFFH8QAAICAAYJex4RBgDRAQACAAYJex4RBgDRAQAuAAQKfxkAAgIACAn8IBQ3AJgCAAIACAn8IBQ3AJgCAAAA.Bashnveggies:BAAALgADCgMJAwAAAA==.Bastét:BAABLgAECn8XAAIJAAYJKBeiJQCrAQAJAAYJKBeiJQCrAQAAAA==.Bauce:BAAALgAECgUJCQAAAA==.Baxter:BAAALgADCgEJAQABLgAECgQJBAABAAAAAA==.Baxterlock:BAAALgAECgQJBAAAAA==.Baylifê:BAAALgADCggJEwAAAA==.',
Be='Bearymanalow:BAABLgAECn8WAAMOAAYJahGWFAAnAQAOAAYJahGWFAAnAQARAAEJ7wNhOAAnAAAAAA==.Beefyweefy:BAAALgADCgEJAQABLgAECgcJDAABAAAAAA==.Bella:BAAALgAECgQJBAAAAA==.Belldelphiné:BAEALgAECgMJBgABLgAECgYJFwAIAFsUAA==.Bellz:BAAALgADCgYJBwAAAA==.Belmønt:BAAALgAECgIJAwAAAA==.',
Bi='Bicycle:BAABLgAECn8cAAISAAgJlRfRAgDUAQASAAgJlRfRAgDUAQAAAA==.Biddy:BAAALgAECgIJAgAAAA==.Bigpumpa:BAAALgAECgYJDgAAAA==.Billmurray:BAAALgAECgYJDwAAAA==.Billygoatgrf:BAABLgAECn8YAAICAAgJdQyfOgB/AQACAAgJdQyfOgB/AQAAAA==.Birchy:BAAALgADCgcJBwAAAA==.',
Bl='Blakkbeard:BAACLgAFFH8FAAITAAQJVBGsEQDdAAATAAQJVBGsEQDdAAAuAAQKfx8AAxMACAkBIhELAOcCABMACAm+IBELAOcCABQABgkoIe0SAIkBAAAA.Blakklight:BAAALgAECgYJDQABLgAFFAQJBQATAFQRAA==.Blazefort:BAABLgAECn8fAAMVAAkJ3BjIKQCSAgAVAAkJExjIKQCSAgAWAAcJRRaoBQDaAQAAAA==.Blazeshifts:BAAALgADCgcJBwAAAA==.Blindedd:BAAALgAECgUJBgAAAA==.Blitzeye:BAAALgAECgQJCwAAAA==.Bloodknight:BAAALgADCgMJAwAAAA==.Bloodraine:BAABLgAECn8YAAIXAAgJqhHqDwBwAQAXAAgJqhHqDwBwAQAAAA==.Bloodshadow:BAAALgADCgIJAgAAAA==.Bluucat:BAAALgAECgEJAQAAAA==.Blôô:BAABLgAECn8cAAIPAAcJShjZIgDlAQAPAAcJShjZIgDlAQAAAA==.',
Bo='Bobmoss:BAAALgADCgUJBgAAAA==.Boethius:BAAALgADCgcJEQAAAA==.Boozeftw:BAAALgADCgIJAgAAAA==.Borkhuis:BAAALgADCgYJCgAAAA==.Bouw:BAAALgADCgcJBwAAAA==.Bouz:BAAALgADCgMJAwAAAA==.Bows:BAAALgADCgIJAgAAAA==.Boysole:BAAALgAECgYJCAAAAA==.',
Bq='Bqpally:BAAALgADCgQJBAAAAA==.',
Br='Brainlesswar:BAABLgAECn8iAAIYAAgJhxPYCgB7AQAYAAgJhxPYCgB7AQAAAA==.Breemonic:BAABLgAECn8dAAIZAAgJqg0MIQC0AQAZAAgJqg0MIQC0AQAAAA==.Brewdie:BAAALgADCggJFAAAAA==.Bristle:BAAALgADCgYJBgAAAA==.Bruce:BAACLgAFFH8MAAQaAAQJ+R3mBgBdAQAaAAQJchfmBgBdAQAYAAIJ1RHlDQCUAAAbAAEJsR4QCQBhAAAuAAQKfyQABBoACQlnJAQLAAQDABoACQkVJAQLAAQDABgACAnzHNcIAJECABsAAgkbGaUrAJcAAAAA.Brucetree:BAAALgADCgYJBgAAAA==.',
Bu='Bubblekush:BAAALgAECgcJDQAAAA==.Bubbleøseven:BAAALgAECgYJCwAAAA==.Budders:BAAALgADCgYJCwAAAA==.Butterz:BAAALgAECgIJAwAAAA==.Buttshank:BAAALgAECgYJDwAAAA==.',
Ca='Cailleach:BAAALgAECgMJAwAAAA==.Calyx:BAAALgAECgQJBAAAAA==.Carson:BAAALgAECgQJCgAAAA==.Casagrande:BAAALgADCgEJAQABLgAECggJJQAcAKceAA==.',
Ch='Chaosvader:BAAALgADCggJFQAAAA==.Chickenbich:BAAALgADCgkJEAAAAA==.Chobi:BAAALgAECgEJAQAAAA==.Choices:BAAALgADCgUJBQABLgAECgkJEQABAAAAAA==.Chrunch:BAAALgADCgYJBgAAAA==.Chuggernaugt:BAABLgAECn8aAAIdAAcJjhL0FABFAQAdAAcJjhL0FABFAQAAAA==.',
Ci='Cinnamen:BAABLgAECn8fAAIXAAgJ8RnEEgCFAgAXAAgJ8RnEEgCFAgAAAA==.',
Cl='Cllawhan:BAAALgADCgkJCgAAAA==.Clutchcity:BAAALgADCgYJBgAAAA==.',
Co='Coaa:BAABLgAECn8YAAIcAAcJ6BxeGgDCAQAcAAcJ6BxeGgDCAQAAAA==.Codèx:BAABLgAECn8hAAICAAgJfBgCLwCnAQACAAgJfBgCLwCnAQAAAA==.Colossus:BAABLgAECn8jAAIDAAgJ3woUOgBdAQADAAgJ3woUOgBdAQAAAA==.Conclave:BAAALgADCgcJDAAAAA==.Contrap:BAAALgADCgMJAwAAAA==.Convoker:BAABLgAECn8kAAMFAAgJRBYhDADGAQAFAAgJSRQhDADGAQAGAAYJnRY2FQCYAQAAAA==.Coolbreeze:BAAALgAECgUJBgAAAA==.Cootert:BAAALgAECggJDQAAAA==.',
Cp='Cptnamerica:BAAALgADCgMJAwAAAA==.',
Cr='Creamsnake:BAAALgAECgEJAgAAAA==.Crimo:BAAALgAECgYJBwABLgAFFAYJEgAPAOsZAA==.Crimons:BAAALgAECggJEgAAAA==.Cronk:BAABLgAECn8ZAAMeAAgJ4Rm1BQDWAQAeAAcJgx21BQDWAQADAAEJEQSnVAEpAAAAAA==.Crèscent:BAAALgADCgEJAQAAAA==.Crõwfather:BAABLgAECn8hAAIfAAgJXB7pBQCRAgAfAAgJXB7pBQCRAgAAAA==.',
Cu='Curtland:BAAALgAECgEJAQAAAA==.',
Cz='Czy:BAAALgAECgEJAQAAAA==.',
Da='Dadjokes:BAAALgAECgEJAQAAAA==.Darkakaza:BAAALgAECgYJCwAAAA==.Darkbu:BAAALgADCgcJCQABLgAFFAMJCAAFAC4WAA==.Darkermagic:BAAALgAECgEJAQAAAA==.Darkmeadow:BAAALgAECgYJEwAAAA==.Dasgoose:BAAALgADCgIJAgAAAA==.Dastard:BAABLgAECn8bAAITAAgJGhY9HwAWAgATAAgJGhY9HwAWAgAAAA==.Datmonk:BAABLgAECn8WAAIgAAcJaRQbGAA+AQAgAAcJaRQbGAA+AQAAAA==.Dave:BAAALgADCgEJAQAAAA==.',
De='Deadlymagic:BAAALgAECgQJBQAAAA==.Deadtorights:BAAALgAECgQJBAAAAA==.Deathblossom:BAAALgAECgUJCQAAAA==.Deathbrñgr:BAAALgADCgQJBAABLgAECggJHgADAOIWAA==.Deathlyfrost:BAABLgAECn8aAAIIAAcJPhOPDQA3AQAIAAcJPhOPDQA3AQAAAA==.Deathvader:BAAALgADCgcJHAAAAA==.Decimatore:BAAALgAECgMJAwAAAA==.Decrepitt:BAAALgADCgEJAQAAAA==.Dedara:BAAALgAECggJEwAAAA==.Deeptotes:BAAALgAECgQJBAAAAA==.Deftonia:BAABLgAECn8UAAIDAAgJCA5vcwCUAQADAAgJCA5vcwCUAQAAAA==.Degenerate:BAABLgAECn8iAAMhAAgJ8RjsEQAVAgAhAAgJ8RjsEQAVAgAiAAUJbhlIDQBhAQAAAA==.Demonbläde:BAABLgAECn8UAAMZAAYJNRQhOQAeAQAZAAUJGBYhOQAeAQAjAAMJNBAiHgCXAAAAAA==.Demonbread:BAAALgAECgEJAQAAAA==.Demonmandis:BAAALgADCgEJAQAAAA==.Derriereizi:BAAALgADCgEJAQAAAA==.Devondric:BAABLgAECn8hAAILAAYJ3xOmEgBpAQALAAYJ3xOmEgBpAQAAAA==.Devotion:BAAALgADCgYJBgABLgAFFAUJCAAEAKoQAA==.Devotional:BAACLgAFFH8IAAIEAAUJqhBYBgCLAQAEAAUJqhBYBgCLAQAuAAQKfx8AAwQACAmzFNEQANsBAAQACAmzFNEQANsBAAMAAwktAv0gAVsAAAAA.',
Dh='Dhaos:BAAALgAECgIJAgABLgAFFAEJAgABAAAAAA==.',
Di='Diekuh:BAAALgADCgEJAQAAAA==.Dinkellberg:BAAALgAECgQJBQAAAA==.Dirgens:BAACLgAFFH8SAAIhAAYJdg7WCACMAQAhAAYJdg7WCACMAQAuAAQKfyEAAiEACAleIJodAKUCACEACAleIJodAKUCAAAA.Dirgenz:BAAALgADCgYJBgAAAA==.Disquietor:BAAALgADCgQJBQAAAA==.Divinacurita:BAAALgAECgUJCwAAAA==.',
Dk='Dkay:BAAALgADCgcJDQAAAA==.',
Do='Dodel:BAAALgADCgYJCgAAAA==.Dokumai:BAABLgAECn8XAAMgAAcJGR6dDQCyAQAgAAcJDx6dDQCyAQAdAAMJ4xUvOQBbAAABLgAFFAEJAgABAAAAAA==.Dommiemommie:BAAALgADCgUJBQABLgADCgcJCQABAAAAAA==.Dooterfiddle:BAAALgAECgEJAQAAAA==.Doozerd:BAAALgAECgMJAwAAAA==.Doozerp:BAACLgAFFH8LAAILAAQJWgonDgAsAQALAAQJWgonDgAsAQAuAAQKfyIAAwsACAnsGjILANkBAAsACAlPGjILANkBAAcABQnvCyVNAAMBAAAA.Dor:BAAALgAECgEJAgAAAA==.Doraexplorer:BAAALgAECgEJAQAAAA==.Dorinmigrane:BAAALgADCgYJBgABLgAECgcJKwAQAMQfAA==.Dorinramps:BAABLgAECn8rAAIQAAcJxB8pDAAcAgAQAAcJxB8pDAAcAgAAAA==.Dotfearwin:BAAALgAECgYJDgAAAA==.Doviculus:BAAALgAECgYJDwAAAA==.',
Dr='Dragmcgoon:BAABLgAECn8jAAIFAAgJOhaPEwBIAgAFAAgJOhaPEwBIAgAAAA==.Drakonman:BAABLgAECn8WAAITAAgJnAfdHAAvAQATAAgJnAfdHAAvAQAAAA==.Drakrappa:BAAALgADCgcJCAAAAA==.Drakthorr:BAAALgAECgcJEgAAAA==.Draynen:BAABLgAECn8cAAMfAAcJ/BkIIwANAgAfAAcJ/BkIIwANAgAUAAIJfwO3KABQAAABLgAFFAUJCwAKAGAYAA==.Drboom:BAAALgADCgYJCgAAAA==.Drcrimo:BAACLgAFFH8SAAIPAAYJ6xnMAQDEAQAPAAYJ6xnMAQDEAQAuAAQKfykAAg8ACAlNIzgIABIDAA8ACAlNIzgIABIDAAAA.Drdööm:BAAALgADCgEJAQAAAA==.Drevil:BAAALgAECgEJAQAAAA==.Drø:BAAALgADCgcJEQAAAA==.',
Du='Duck:BAAALgAECgEJAQAAAA==.Duckduck:BAAALgAECgYJDAAAAA==.Dudemanyeah:BAAALgADCgEJAQAAAA==.Dulcïnea:BAABLgAECn8XAAIQAAgJqBVYVQCjAQAQAAgJqBVYVQCjAQAAAA==.Dumbanimal:BAAALgAECgUJBgAAAA==.Durnir:BAAALgAECgMJAwAAAA==.Durut:BAABLgAECn8bAAIVAAgJ1yFmCQCKAgAVAAgJ1yFmCQCKAgAAAA==.',
Dw='Dwarfbussy:BAAALgAECgMJAwAAAA==.',
['Dê']='Dêathany:BAAALgADCgMJBAAAAA==.',
Ea='Easley:BAAALgAFFAEJAgAAAA==.',
Ec='Ecliptic:BAAALgAECgEJAQAAAA==.',
Ed='Edrana:BAAALgAECgIJAgABLgAECgUJDAABAAAAAA==.Edurna:BAAALgADCgIJAgAAAA==.',
Eh='Ehvyn:BAAALgAECgQJCgAAAA==.',
El='Elementcreep:BAAALgADCgYJBwAAAA==.Elise:BAAALgAECgQJBAAAAA==.Eliza:BAAALgAECgcJCAAAAA==.Elizzabeth:BAAALgAECgYJDwAAAA==.Ellisis:BAAALgAECggJEwAAAA==.Elvarg:BAAALgADCgQJBAABLgAECgQJCgABAAAAAA==.',
Em='Emriq:BAABLgAECn8cAAIDAAgJTR8XCgB/AgADAAgJTR8XCgB/AgAAAA==.',
En='Enmai:BAABLgAECn8YAAIhAAcJhQuGPAA9AQAhAAcJhQuGPAA9AQAAAA==.',
Ep='Ephius:BAAALgAECgUJDAAAAA==.',
Er='Eranar:BAAALgAECgEJAQAAAA==.Eraquxx:BAAALgADCgcJBwAAAA==.Ertironin:BAAALgADCgcJDgABLgAECggJGAACAHUMAA==.',
Es='Esper:BAAALgADCgcJBwABLgAECgQJBQABAAAAAA==.Esthar:BAAALgAECgYJEAAAAA==.',
Et='Etheko:BAAALgAECgQJBAAAAA==.Etir:BAABLgAECn8cAAICAAgJCg5jMgCbAQACAAgJCg5jMgCbAQAAAA==.',
Eu='Eudæmønia:BAAALgAECgYJEwAAAA==.',
Ev='Evangelise:BAAALgAECgIJAgAAAA==.Evella:BAAALgAECgYJBwAAAA==.',
Ex='Exodiusx:BAAALgAECgUJCQAAAA==.Exxitus:BAAALgAECgYJDQAAAA==.',
Ey='Eyebeam:BAAALgAECgEJAQAAAA==.Eyebrowsius:BAAALgAECgUJBQABLgAFFAIJBgAMAGYhAA==.',
Fa='Falorel:BAAALgADCgIJAgAAAA==.Falsoqt:BAAALgAECgYJDgAAAA==.Faragon:BAAALgAECgIJAgAAAA==.Faux:BAAALgAECgQJBAABLgAECggJHwAYAJwTAA==.Fayline:BAAALgAECgYJDAAAAA==.',
Fb='Fblthp:BAABLgAECn8VAAICAAgJpRdLMwCXAQACAAgJpRdLMwCXAQAAAA==.',
Fe='Felachio:BAABLgAECn8ZAAIcAAgJ2BqtDQAvAgAcAAgJ2BqtDQAvAgAAAA==.Felrush:BAAALgAECgUJBgAAAA==.Fenno:BAAALgAECgUJBgAAAA==.Fentfliction:BAAALgADCgYJBgAAAA==.',
Fi='Fidelitaslex:BAAALgADCggJDAAAAA==.Firerage:BAABLgAECn8UAAIhAAcJYiFFRAD/AQAhAAcJYiFFRAD/AQAAAA==.Fischform:BAABLgAECn8iAAINAAgJZCUBAwARAwANAAgJZCUBAwARAwAAAA==.',
Fj='Fjörgyn:BAACLgAFFH8SAAITAAUJbyD6AgDDAQATAAUJbyD6AgDDAQAuAAQKfyMAAhMACQmeJCIBAL8DABMACQmeJCIBAL8DAAAA.',
Fl='Flashlight:BAAALgADCgUJBQAAAA==.Flexr:BAAALgADCgMJAwAAAA==.',
Fo='Forsetí:BAAALgAECgIJAgAAAA==.Fortress:BAAALgAECgEJAQAAAA==.',
Fr='Frasierkrane:BAAALgADCgUJBQAAAA==.Frontshots:BAAALgAECgQJBgAAAA==.',
Ft='Ftfk:BAAALgADCgkJFwABLgAECggJHwAKAIUkAA==.',
Fu='Funguslice:BAAALgAECgYJDQABLgAECgUJCwABAAAAAA==.Funji:BAAALgAECgEJAQAAAA==.Funkyflank:BAAALgAECgMJAwAAAA==.',
Ga='Galactica:BAAALgADCgEJAQAAAA==.Galdoria:BAAALgAECgIJAgABLgAECgQJCAABAAAAAA==.Galie:BAABLgAECn8pAAMPAAgJjxF7EACOAQAPAAgJjxF7EACOAQARAAUJ3gujIgDDAAAAAA==.Galìe:BAAALgADCgcJDgAAAA==.Garrahoth:BAAALgADCgUJBQABLgAECgcJDAABAAAAAA==.Gatherith:BAAALgAECgMJAwAAAA==.',
Ge='Gekk:BAABLgAECn8dAAMKAAgJmRw/BAA3AgAKAAgJmRw/BAA3AgAFAAMJSxQvKQDIAAAAAA==.Gendarme:BAAALgAECgUJCAAAAA==.',
Gh='Ghostface:BAABLgAECn8hAAMEAAcJrA5GGgB6AQAEAAcJrA5GGgB6AQADAAEJiw7zNwE5AAAAAA==.Ghuun:BAAALgAECgEJAQAAAA==.',
Gi='Giaus:BAABLgAECn8gAAICAAgJchNOJQDSAQACAAgJchNOJQDSAQAAAA==.Gimmeh:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgMJBQAAAA==.',
Gl='Glorified:BAAALgAECgIJAgAAAA==.Glump:BAAALgADCgMJAwAAAA==.',
Go='Gobzilla:BAABLgAECn8eAAIfAAgJdiBpEQCLAgAfAAgJdiBpEQCLAgAAAA==.Gonn:BAAALgADCgIJAgAAAA==.Goodboy:BAAALgADCggJEwAAAA==.Goonergramps:BAAALgADCgkJCQAAAA==.Goub:BAABLgAECn8aAAMfAAgJ3B52FABxAgAfAAcJsx12FABxAgATAAcJeg2LJgDxAAAAAA==.Goubam:BAAALgAECgEJAQABLgAECggJGgAfANweAA==.',
Gr='Gracieiris:BAAALgAECgEJAQAAAA==.Grapefroot:BAAALgAECgYJDwAAAA==.Grapeinator:BAAALgADCgQJBQAAAA==.Grapey:BAAALgAECgYJDwAAAA==.Greenarrow:BAAALgADCggJCAAAAA==.Greenwarlock:BAAALgAECgYJEwAAAA==.Grimhoof:BAAALgAECgMJAwAAAA==.Grimhorn:BAAALgAECgIJAgAAAA==.Gripdip:BAAALgAECgEJAQAAAA==.Grnola:BAABLgAECn8UAAIVAAYJqxDYngBDAQAVAAYJqxDYngBDAQAAAA==.',
Gu='Guldum:BAAALgADCgUJCwAAAA==.Gurvinder:BAAALgAECgYJBwAAAA==.',
Gw='Gwyne:BAACLgAFFH8HAAIVAAQJAR6sGABRAQAVAAQJAR6sGABRAQAuAAQKfyMAAhUACAm6JYENAC4DABUACAm6JYENAC4DAAAA.',
Ha='Hailstorm:BAAALgADCgQJBQAAAA==.Halfstack:BAAALgAECgUJBQAAAA==.Halucid:BAAALgADCgIJAgAAAA==.Happywoodz:BAAALgAFFAIJAwAAAA==.Hardmoney:BAAALgADCgMJAwAAAA==.Harmsway:BAAALgADCgEJAQAAAA==.Hashed:BAABLgAECn8fAAIDAAgJwBrZNgBHAgADAAgJwBrZNgBHAgAAAA==.Haveanicejay:BAAALgAECgQJBgAAAA==.Haysevoker:BAACLgAFFH8MAAIKAAUJXRpSBwB4AQAKAAUJXRpSBwB4AQAuAAQKfx4AAwoACAkTISkGAOICAAoACAkTISkGAOICAAUAAgnAFtNPAI0AAAAA.Haysmonk:BAAALgAECgYJEAAAAA==.',
He='Heliumprime:BAAALgAECgEJAgAAAA==.Hellabrews:BAAALgAECgYJEgAAAA==.Hexcellent:BAAALgADCggJDwAAAA==.',
Ho='Hogra:BAAALgADCgUJBQABLgAECggJGQAeAOEZAA==.Holstadd:BAAALgADCgcJCgAAAA==.Hoodler:BAECLgAFFH8TAAINAAUJuiTBAQAgAgANAAUJuiTBAQAgAgAuAAQKfyEAAg0ACAkqJm0DAFwDAA0ACAkqJm0DAFwDAAAA.Hoodlere:BAEALgAECgYJCwABLgAFFAUJEwANALokAA==.Hoodlery:BAEALgAFFAEJAQABLgAFFAUJEwANALokAA==.Horndrojo:BAAALgADCgMJAwAAAA==.Hortraz:BAAALgAECgYJDgAAAA==.Hotzcake:BAAALgAECgMJAgAAAA==.',
Hr='Hrathen:BAAALgAECgEJAQAAAA==.',
Hu='Humphugull:BAAALgAECgYJEwAAAA==.Huntoine:BAAALgAECgYJDQABLgAFFAUJCgAJANwVAA==.Huskydots:BAACLgAFFH8FAAIhAAMJIwVEPwCNAAAhAAMJIwVEPwCNAAAuAAQKfxoAAyEACAkZGX4/AA8CACEABwkZGX4/AA8CABIABAlPDhU0AOcAAAAA.',
Hy='Hyroshi:BAAALgADCgYJBgAAAA==.Hyur:BAAALgAECgYJEAAAAA==.',
['Hâ']='Hâmmy:BAAALgAECgIJAgAAAA==.',
Ib='Iblastpants:BAAALgAECgcJEgAAAA==.',
Ic='Ichoroath:BAAALgAECgYJCgAAAA==.',
Ig='Iggyy:BAAALgAECgUJEQAAAA==.',
Ij='Ijjii:BAAALgAECgYJDAAAAA==.',
Ik='Ikkirak:BAAALgAECgEJAQAAAA==.',
Il='Ilgynoth:BAABLgAECn8aAAMPAAgJxA7MMQB8AQAPAAgJxA7MMQB8AQANAAUJuwqFhQDMAAAAAA==.Illidaris:BAAALgADCgMJAwAAAA==.Illidonut:BAAALgADCgUJBAABLgAECgYJDgABAAAAAA==.',
Im='Imdeadinside:BAAALgAECgIJAgAAAA==.Imsuperlost:BAAALgADCgUJBQAAAA==.',
In='Infinitas:BAAALgADCgUJBgAAAA==.Inflammo:BAAALgAECgUJBQAAAA==.Inflic:BAAALgADCggJFQAAAA==.Inspectadeck:BAAALgAECgQJBwAAAA==.',
Ir='Irila:BAABLgAECn8YAAIOAAgJOxBfCQA/AQAOAAgJOxBfCQA/AQAAAA==.Irmerlock:BAAALgADCgMJAwAAAA==.Irshadin:BAABLgAECn8nAAMDAAkJ0B3CCACQAgADAAkJ0B3CCACQAgAeAAIJUwazPgBDAAAAAA==.Irshingwary:BAAALgADCggJCAAAAA==.',
Is='Istackspirit:BAAALgAECgQJBAAAAA==.',
Iz='Izumî:BAAALgAECgYJCQAAAA==.',
Ja='Jaebuns:BAAALgAECgQJBQAAAA==.Jakob:BAAALgAECgIJBAAAAA==.Jamiie:BAAALgAECgMJBAAAAA==.Jangosan:BAAALgADCgkJDwAAAA==.Jangutu:BAAALgAECgQJCwAAAA==.Jasonluv:BAAALgAECgQJCAAAAA==.Jaspy:BAABLgAECn8gAAIRAAgJbhZtBADnAQARAAgJbhZtBADnAQAAAA==.Jaynee:BAABLgAECn8dAAIDAAgJkiQJBQDKAgADAAgJkiQJBQDKAgAAAA==.',
Ji='Jinharu:BAAALgADCgkJCQABLgAFFAEJAgABAAAAAA==.',
Jo='Jomgpallie:BAAALgAECgYJDQAAAA==.Jonac:BAAALgAECgEJAQAAAA==.Josefbugman:BAAALgAECgUJDQAAAA==.',
Ju='Juicee:BAAALgADCgcJEQAAAA==.Juktal:BAABLgAECn8UAAIkAAgJjBO3DQCEAQAkAAgJjBO3DQCEAQAAAA==.Jukujo:BAAALgADCgEJAQAAAA==.Jupîter:BAAALgAECgQJCAAAAA==.Justyn:BAAALgAECgYJDwAAAA==.',
Ka='Kajoru:BAAALgADCgcJBwAAAA==.Kancho:BAAALgAECgQJBgAAAA==.Karlsparx:BAAALgAECgUJBQAAAA==.Kattakuri:BAAALgADCgYJBgAAAA==.Kazuje:BAAALgAFFAMJBAAAAA==.Kazzu:BAAALgAECgMJAwAAAA==.',
Ke='Ketia:BAAALgADCggJEQAAAA==.Keyal:BAEALgAECgcJCgABLgAFFAQJCAANALgQAA==.',
Kh='Kheros:BAAALgAECgUJCwAAAA==.Khiron:BAAALgADCgUJCQAAAA==.',
Ki='Kialorstus:BAAALgAECggJCQAAAA==.Kilarga:BAAALgADCgUJBQAAAA==.Kilo:BAAALgAECgYJDwAAAA==.Kimari:BAAALgADCgEJAgAAAA==.Kinzington:BAAALgAECgEJAQAAAA==.Kirbo:BAAALgAECgEJAQAAAA==.Kiriron:BAAALgAECgQJBgAAAA==.Kittyperry:BAAALgAECgMJAwABLgAECggJFAADAAgOAA==.',
Ko='Kolakua:BAAALgADCgIJAgAAAA==.Kookiemonsta:BAAALgADCgcJAQAAAA==.Kouw:BAAALgAECggJEQAAAA==.',
Kr='Kramx:BAAALgAECgYJDgAAAA==.Krankenstein:BAAALgAECgYJDAAAAA==.Krankson:BAAALgAECgYJDgAAAA==.Kriix:BAABLgAECn8TAAIlAAcJ6yLBAQAsAgAlAAcJ6yLBAQAsAgAAAA==.Krugah:BAAALgAECgQJCAAAAA==.Krusnik:BAAALgAECgUJCgAAAA==.',
Ks='Ksubi:BAAALgAECgEJAQAAAA==.',
Ku='Kuhnleone:BAAALgADCgcJBwAAAA==.Kujatas:BAABLgAECn8iAAMTAAcJQyIkBgBKAgATAAcJQyIkBgBKAgAfAAIJUBxOQQClAAAAAA==.Kuls:BAAALgADCgcJBwAAAA==.Kumdobeast:BAAALgAECgMJAwAAAA==.Kuothe:BAABLgAECn8mAAICAAgJhxaRIgDgAQACAAgJhxaRIgDgAQAAAA==.Kuroakami:BAAALgAECgEJAQAAAA==.',
Ky='Kyrael:BAAALgAECgUJDAAAAA==.',
['Kí']='Kíllahpriest:BAAALgADCgcJGgAAAA==.',
La='Laelunea:BAAALgAECggJEQAAAA==.Lambslayer:BAAALgADCgMJAwAAAA==.Lannsing:BAABLgAECn8uAAMLAAkJtR6aAQAdAwALAAkJ7xuaAQAdAwAHAAgJ7B8PBQB4AgAAAA==.',
Le='Leetpkss:BAAALgADCgYJBgAAAA==.Lenaría:BAAALgADCgcJCgAAAA==.Leonheart:BAAALgADCgQJBQAAAA==.Lesnichii:BAABLgAECn8ZAAIPAAgJuwsUEwBwAQAPAAgJuwsUEwBwAQAAAA==.Letemkrap:BAAALgAECgEJAwAAAA==.Lewakex:BAAALgAECgcJCQAAAA==.Leyendaz:BAAALgADCgUJBwABLgAECgUJBQABAAAAAA==.Leyzormemes:BAABLgAECn8cAAIQAAgJByNWGQC8AgAQAAgJByNWGQC8AgAAAA==.',
Li='Lightbrngr:BAABLgAECn8eAAIDAAgJ4hbOKQCbAQADAAgJ4hbOKQCbAQAAAA==.Lihuai:BAABLgAECn8fAAMdAAgJvQgqFQBDAQAdAAgJvQgqFQBDAQAMAAYJ9gSgRwC7AAAAAA==.Lilbertha:BAABLgAECn8oAAMCAAgJWBLwcQDvAQACAAgJWBLwcQDvAQAmAAIJ8QefCAA3AAAAAA==.Lilconcon:BAABLgAECn8gAAITAAkJsBF/GQBGAQATAAkJsBF/GQBGAQAAAA==.Lildipster:BAAALgAECgMJAwABLgAECgQJBQABAAAAAA==.Lilthrall:BAAALgADCgkJFwAAAA==.Liptonaysti:BAAALgAECgYJEAAAAA==.Lissandine:BAABLgAECn8dAAIjAAgJYh2cBgAmAgAjAAgJYh2cBgAmAgAAAA==.Liuxin:BAAALgAECgQJBQAAAA==.Lizzywizzy:BAAALgADCgUJBQABLgAECgQJBQABAAAAAA==.',
Ll='Llaydee:BAAALgADCgUJBQAAAA==.',
Lo='Loalight:BAAALgADCgYJDAAAAA==.Lodencilly:BAAALgADCgIJAgAAAA==.Lomao:BAAALgADCgQJBQAAAA==.Longdude:BAAALgAECgcJDwAAAA==.Lorth:BAAALgADCgEJAQAAAA==.Lotharn:BAAALgAECgQJBwAAAA==.Lowdy:BAABLgAECn8VAAMbAAYJNxKeEAAEAQAaAAYJCBDeJQAPAQAbAAQJQBKeEAAEAQAAAA==.',
Lu='Lucas:BAABLgAECn8UAAITAAcJCx8CIQAHAgATAAcJCx8CIQAHAgAAAA==.Lucifri:BAEBLgAECn8XAAIIAAYJWxTiHwBFAQAIAAYJWxTiHwBFAQAAAA==.Luckydo:BAAALgADCgUJBQABLgAECggJEQABAAAAAA==.Luckydoo:BAAALgAECggJEQAAAA==.Luvr:BAAALgADCgIJAgAAAA==.',
Ly='Lych:BAAALgAECgMJAwAAAA==.',
['Lì']='Lìllith:BAAALgAECgYJEQAAAA==.',
Ma='Madting:BAAALgADCgEJAQAAAA==.Magnuss:BAABLgAECn8XAAICAAgJUBRsawD/AQACAAgJUBRsawD/AQAAAA==.Majick:BAAALgADCgcJBwAAAA==.Malthaell:BAAALgAECggJEAAAAA==.Maltyablo:BAABLgAECn8cAAIjAAgJvhJiBQCGAQAjAAgJvhJiBQCGAQAAAA==.Mammutos:BAAALgAECgEJAQAAAA==.Manapaws:BAABLgAECn8YAAIHAAcJWxmhIADdAQAHAAcJWxmhIADdAQAAAA==.Manddarb:BAAALgADCgIJAgAAAA==.Manion:BAABLgAECn8dAAMTAAgJ3xSPDwCrAQATAAgJ3xSPDwCrAQAfAAIJWQj1iwBlAAAAAA==.Manipulating:BAAALgAECgYJCgAAAA==.Manipulation:BAAALgAECgcJEgAAAA==.Mannarchy:BAAALgAECgYJEQAAAA==.Manpan:BAAALgAECgEJAgAAAA==.Mantrà:BAAALgADCgkJFwAAAA==.Margot:BAAALgADCgQJBAABLgAECgIJBAABAAAAAA==.Marquise:BAABLgAECn8ZAAMFAAgJbRTFGQD/AQAFAAgJcxPFGQD/AQAGAAYJHxSeFwB9AQAAAA==.Masochista:BAABLgAFFH8MAAIIAAUJIiHSBABaAQAIAAUJIiHSBABaAQAAAA==.Mastavas:BAAALgADCgIJAgAAAA==.Mastric:BAEBLgAECn8fAAIhAAgJ5wSLPgA2AQAhAAgJ5wSLPgA2AQAAAA==.Matarkbro:BAABLgAECn8gAAIYAAgJixkLBgDzAQAYAAgJixkLBgDzAQAAAA==.Maudelyn:BAAALgADCgQJBgAAAA==.Mayumißrown:BAAALgADCgUJBwAAAA==.Mazrin:BAAALgADCgEJAQAAAA==.',
Mc='Mccaffrey:BAABLgAECn8dAAMaAAgJ7ROcDQDZAQAaAAgJ7ROcDQDZAQAbAAEJ+g+hPAA/AAAAAA==.Mcstuffings:BAAALgADCgUJBQABLgAECgcJGAAfAF8cAA==.',
Me='Meetch:BAACLgAFFH8IAAIVAAQJHBOGHgBAAQAVAAQJHBOGHgBAAQAuAAQKfx0AAhUACAmCFzpBADQCABUACAmCFzpBADQCAAAA.Megdar:BAAALgAECgMJAwAAAA==.Meldbot:BAAALgAECgcJDQABLgAFFAUJDAAIACIhAA==.Merix:BAABLgAECn8hAAIXAAkJeBx/AwBpAgAXAAkJeBx/AwBpAgAAAA==.Mestea:BAAALgAECgUJBgAAAA==.Mewing:BAAALgAECgUJBgABLgAECgcJGwADACAdAA==.Mexorcistp:BAABLgAECn8YAAIEAAgJxBlgGABPAgAEAAgJxBlgGABPAgAAAA==.Mexorcists:BAAALgAECgIJBAABLgAECggJGAAEAMQZAA==.',
Mi='Mirra:BAAALgAECgQJBQAAAA==.Mirus:BAABLgAECn8bAAMcAAgJlRYMMwDjAQAcAAgJ6BMMMwDjAQAkAAYJmQ0BGQA/AQAAAA==.',
Ml='Mlee:BAAALgAECgQJBAAAAA==.',
Mo='Mojobtw:BAABLgAECn8fAAMEAAgJqSV5AwA6AwAEAAgJqSV5AwA6AwADAAEJlRSnOgE3AAAAAA==.Monkeybiz:BAAALgAECgcJBwABLgAECggJEQABAAAAAA==.Monkeyc:BAAALgADCgEJAQAAAA==.Monos:BAAALgADCgQJBAAAAA==.Monsterboy:BAAALgADCgcJCQAAAA==.Mooby:BAAALgADCgYJBgAAAA==.Moontouched:BAAALgAECgUJCAABLgAECgYJCwABAAAAAA==.Mord:BAAALgAECgEJAgAAAA==.Morrkoth:BAAALgADCgYJBgAAAA==.Mors:BAAALgAECgYJCAAAAA==.Mortamur:BAABLgAECn8lAAICAAgJORWRJQDRAQACAAgJORWRJQDRAQAAAA==.Mortelinnos:BAABLgAECn8WAAIZAAcJBRe3GgDtAQAZAAcJBRe3GgDtAQAAAA==.',
Ms='Msadventure:BAAALgADCgMJAwAAAA==.',
Mu='Mujurro:BAAALgADCgEJAQAAAA==.Murney:BAAALgADCgcJBwAAAA==.Muzzledmage:BAEBLgAECn8YAAICAAYJmRobQgBoAQACAAYJmRobQgBoAQAAAA==.',
My='Myfirstlady:BAAALgADCgEJAQAAAA==.Myparse:BAABLgAECn8UAAIQAAgJdBqvRQDdAQAQAAgJdBqvRQDdAQAAAA==.Mysticguru:BAABLgAECn8YAAIfAAcJXxwTKQDrAQAfAAcJXxwTKQDrAQAAAA==.',
['Mà']='Mànyen:BAAALgADCgcJDgAAAA==.',
Na='Nadiaa:BAAALgADCgMJAwAAAA==.Naisu:BAAALgAECgEJAQAAAA==.Nanibear:BAAALgADCgkJEQAAAA==.Narodaran:BAAALgAECgYJBwAAAA==.Natebrew:BAAALgADCgkJEgABLgAECggJIgAQAPIeAA==.Nattsume:BAAALgADCgcJBwAAAA==.Natural:BAABLgAECn8cAAQRAAgJYxskBADyAQARAAgJYxskBADyAQAOAAMJxBBeIQCTAAANAAIJigUsvwBJAAAAAA==.Naughtÿ:BAAALgAECgEJAQAAAA==.',
Ne='Neco:BAAALgAECgQJCgAAAA==.Necropete:BAABLgAECn8bAAIVAAgJPBmlIwCzAQAVAAgJPBmlIwCzAQAAAA==.Nerudian:BAAALgADCgMJAwAAAA==.Nevets:BAABLgAECn8eAAMnAAcJhhnLBgB9AQAnAAcJGBnLBgB9AQAkAAUJiA+PHQAAAQAAAA==.Nevrs:BAAALgAECgQJCgAAAA==.',
Ni='Nickkshield:BAAALgADCgYJBgAAAA==.Nimit:BAABLgAECn8eAAMcAAgJEh3jDQAtAgAcAAgJKRzjDQAtAgAkAAUJKRYvGwAhAQAAAA==.Nipha:BAAALgAECgMJBQAAAA==.',
No='Noct:BAAALgAECgMJBAAAAA==.Nofoxgivn:BAAALgAECgIJAgABLgAECggJHgADAOIWAA==.Nogreencardx:BAAALgAECgUJCgAAAA==.Nooblez:BAAALgADCgYJBgAAAA==.Notsenka:BAABLgAECn8bAAIXAAcJjwk9EgBRAQAXAAcJjwk9EgBRAQAAAA==.Notzee:BAAALgADCgQJBwAAAA==.Novic:BAABLgAECn8lAAIHAAgJ5RoYEwBHAgAHAAgJ5RoYEwBHAgAAAA==.Noxinox:BAAALgADCgYJBgAAAA==.',
Nu='Nualia:BAABLgAECn8cAAIDAAgJABquEgAlAgADAAgJABquEgAlAgAAAA==.Nulg:BAAALgADCgIJAgAAAA==.',
Ny='Nyssathasong:BAAALgAECgcJDwAAAA==.',
['Nä']='Nägash:BAAALgAECgMJBgAAAA==.',
Oa='Oathkeeper:BAAALgAECgUJCAAAAA==.',
Oj='Ojaks:BAAALgAECgMJAwAAAA==.',
Om='Omatiaa:BAACLgAFFH8HAAITAAIJdA2EFwCZAAATAAIJdA2EFwCZAAAuAAQKfykAAhMACAkUHRUVAHUCABMACAkUHRUVAHUCAAAA.',
Oo='Oongawa:BAAALgAECgYJBgAAAA==.',
Or='Oraxus:BAAALgAECgEJAQAAAA==.Oreface:BAAALgAECgEJAQAAAA==.Orobus:BAABLgAECn8kAAIYAAgJCiLSAQCmAgAYAAgJCiLSAQCmAgAAAA==.',
Os='Oscassey:BAABLgAECn8bAAIlAAgJZQg9BQBzAQAlAAgJZQg9BQBzAQAAAA==.',
Ox='Oxley:BAABLgAECn8dAAIRAAgJNxvhAgAuAgARAAgJNxvhAgAuAgAAAA==.',
Pa='Pacifica:BAAALgAECgMJAwAAAA==.Paladingus:BAAALgAECggJEQAAAA==.Pallumx:BAAALgAECgEJAQAAAA==.Pandidin:BAABLgAECn8UAAMdAAgJyw66EQBnAQAdAAcJdxC6EQBnAQAgAAgJ+QeWMACiAAAAAA==.Pastasaladin:BAAALgAECgEJAgAAAA==.Paulblart:BAAALgAECgcJBwAAAA==.Pauldrons:BAACLgAFFH8IAAIVAAIJDATKYACMAAAVAAIJDATKYACMAAAuAAQKf0QAAhUACAkMFO8pAJQBABUACAkMFO8pAJQBAAAA.',
Pe='Peenar:BAAALgAECggJEwAAAA==.',
Ph='Pharlock:BAAALgAECgYJEAAAAA==.Pharlòck:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.Phlebite:BAAALgAECgYJDwAAAA==.Phobia:BAAALgADCgkJCQABLgAECggJHwAYAJwTAA==.',
Pi='Pichurri:BAAALgAECgUJDgAAAA==.Pigpen:BAAALgAECgQJCwAAAA==.Pilk:BAAALgADCgUJBwAAAA==.Pineapplexp:BAAALgADCggJBwAAAA==.',
Pk='Pk:BAABLgAECn8vAAIoAAkJOyAnAAASAwAoAAkJOyAnAAASAwAAAA==.',
Pl='Planky:BAAALgADCggJEAAAAA==.',
Po='Pooterdiddle:BAAALgADCgUJBQAAAA==.Popsaheal:BAEALgAECgcJBwABLgAFFAQJCAANALgQAA==.Porunga:BAAALgAECggJCAAAAA==.Poshinek:BAAALgAECgQJCAAAAA==.',
Pr='Predobear:BAAALgAECgYJDwAAAA==.Prohealin:BAABLgAECn8lAAIHAAgJZhwmBACVAgAHAAgJZhwmBACVAgAAAA==.Protojack:BAAALgADCgEJAQABLgAFFAYJDgAEAKQbAA==.Pryx:BAAALgAECgcJBgAAAA==.',
Ps='Psychosís:BAAALgAECgIJBQAAAA==.',
Pu='Pumpkinq:BAACLgAFFH8GAAIXAAMJxRFWEwCyAAAXAAMJxRFWEwCyAAAuAAQKfywAAhcACAlVIxMGADADABcACAlVIxMGADADAAAA.Purin:BAABLgAECn8fAAMiAAgJByNdAACWAgAiAAcJByNdAACWAgASAAIJnA4wRACkAAAAAA==.',
Pw='Pwnzorus:BAAALgAECgEJAwAAAA==.',
['Pì']='Pìkachu:BAABLgAECn8fAAICAAgJ4Bu3IgDfAQACAAgJ4Bu3IgDfAQAAAA==.',
Ra='Radon:BAAALgAECgUJBgAAAA==.Raekwon:BAAALgAECgYJCAAAAA==.Rainer:BAAALgADCgEJAQAAAA==.Ramzita:BAAALgAECgYJCwAAAA==.Randic:BAAALgAECgYJBgAAAA==.Raptok:BAABLgAECn8UAAMfAAUJ4hKNLwACAQAfAAUJ4hKNLwACAQATAAMJhgqWNgCZAAAAAA==.Rasmus:BAABLgAECn8fAAIeAAgJBBueBQDXAQAeAAgJBBueBQDXAQAAAA==.Raykwan:BAAALgAECgYJCwAAAA==.Rayquaza:BAABLgAECn8fAAIKAAgJhSTEAAA+AwAKAAgJhSTEAAA+AwAAAA==.Razmatazz:BAABLgAECn8cAAMFAAgJ4henCQDxAQAFAAgJ4henCQDxAQAGAAMJbhfqLgChAAAAAA==.',
Re='Reddeyes:BAAALgAECgYJDwAAAA==.Reignleif:BAAALgADCgMJAwAAAA==.Rektalhammer:BAABLgAECn8UAAIDAAgJEhBJPgBPAQADAAgJEhBJPgBPAQAAAA==.Rescue:BAABLgAECn8eAAICAAgJYxl8TQBOAgACAAgJYxl8TQBOAgAAAA==.Reukha:BAAALgAECgUJCQAAAA==.Rev:BAAALgADCgUJBQABLgAECggJBwABAAAAAA==.',
Rh='Rhavik:BAAALgADCgcJCgAAAA==.',
Ri='Rickrollins:BAABLgAECn8cAAIdAAgJyiMXAwCXAgAdAAgJyiMXAwCXAgAAAA==.Rimreaper:BAAALgADCgYJEgAAAA==.Rinedara:BAAALgADCgMJAwAAAA==.',
Ro='Roachmonger:BAABLgAECn8VAAMgAAcJvRfnNgBwAQAgAAcJvRfnNgBwAQAdAAEJwRFsewA1AAAAAA==.Roasted:BAABLgAECn8YAAICAAgJyBpqGQATAgACAAgJyBpqGQATAgAAAA==.Robotodh:BAAALgAECgEJAQAAAA==.Rockma:BAABLgAECn8iAAITAAkJuRA/KQDLAQATAAkJuRA/KQDLAQAAAA==.Rockyroad:BAAALgADCgQJBAAAAA==.Rollandburn:BAABLgAECn8XAAIcAAcJDR41EwD5AQAcAAcJDR41EwD5AQAAAA==.Rondó:BAABLgAECn8XAAMDAAcJvRQwjwBdAQADAAcJXBAwjwBdAQAeAAQJ+RAGKADJAAAAAA==.Rosao:BAAALgAECgEJAQAAAA==.Rotblack:BAAALgAECgUJCAAAAA==.Rotrogue:BAAALgADCgYJBgAAAA==.Rougerhaegar:BAAALgAECgIJAwAAAA==.Rozdomu:BAAALgAECgYJBgAAAA==.',
Ru='Ruff:BAAALgAECgEJAQAAAA==.Rufföaddy:BAABLgAECn8fAAIEAAgJRyGLBACtAgAEAAgJRyGLBACtAgAAAA==.Runeesa:BAAALgAECgYJEAAAAA==.Rustaxe:BAAALgADCgEJAQAAAA==.',
Ry='Rylena:BAABLgAECn8YAAMcAAcJhSFmDwAdAgAcAAcJhSFmDwAdAgAnAAYJcxP7OwBtAQAAAA==.Rylseekmc:BAAALgADCgMJAwABLgAECgQJCQABAAAAAA==.Ryuke:BAAALgADCgYJBgAAAA==.Ryvalry:BAAALgAECgcJDAAAAA==.Ryzzhorn:BAABLgAECn8YAAMcAAgJ4Ad5LABgAQAcAAgJ4Ad5LABgAQAnAAUJuQH7awCOAAAAAA==.',
['Rà']='Ràvenn:BAAALgAECgUJDQAAAA==.',
['Râ']='Râmên:BAAALgAECgQJBQAAAA==.',
['Rí']='Ríchter:BAABLgAECn8eAAIQAAgJGxshDAAdAgAQAAgJGxshDAAdAgAAAA==.',
Sa='Sagikos:BAECLgAFFH8IAAINAAQJuBBjFwDbAAANAAQJuBBjFwDbAAAuAAQKfyYAAw0ACAktIXEKAO8CAA0ACAktIXEKAO8CAA8ACAmgFn4KAOcBAAAA.Sagua:BAAALgAECgcJBQAAAA==.Saintvader:BAAALgADCgEJAgAAAA==.Saki:BAAALgAECgYJDAAAAA==.Sammiches:BAAALgADCgcJBwAAAA==.Sanstormrage:BAAALgAECgUJEAABLgAECggJCAABAAAAAA==.Sardras:BAABLgAECn8fAAINAAgJYiRvAgAsAwANAAgJYiRvAgAsAwAAAA==.Sark:BAABLgAECn8UAAIVAAgJ+ANFqAAxAQAVAAgJ+ANFqAAxAQAAAA==.Sathor:BAAALgAECgkJDgAAAA==.Saucyjenkins:BAAALgAECgQJCQAAAA==.',
Sc='Scranton:BAAALgADCgEJAQAAAA==.',
Se='Sedgwin:BAAALgADCgIJAgAAAA==.Segundus:BAAALgADCgEJAQAAAA==.Sellout:BAAALgAECgcJDAAAAA==.Semprefi:BAAALgADCgYJBwAAAA==.Seph:BAAALgADCgMJAwAAAA==.Sepharion:BAAALgADCgcJBwABLgAECggJGgAhAJIjAA==.Seraphymn:BAAALgAECgQJBAAAAA==.Serenitree:BAAALgADCgMJAwAAAA==.',
Sg='Sgrios:BAAALgADCggJCQABLgAFFAIJBwATAHQNAA==.',
Sh='Shaani:BAAALgAECgYJEgAAAA==.Shadydh:BAAALgADCggJFQAAAA==.Shammehh:BAAALgADCgEJAQABLgAECgcJGQAFAB0aAA==.Shammooz:BAABLgAECn8bAAITAAcJmgcWIQATAQATAAcJmgcWIQATAQAAAA==.Sharkimon:BAAALgADCgEJAQAAAA==.Shaylyn:BAAALgAECgUJBQABLgAFFAMJCAATAM4QAA==.Sheefu:BAAALgADCgkJCwAAAA==.Shinier:BAAALgAECgQJBAAAAA==.Shockersz:BAAALgAECgIJAgAAAA==.Shockwoods:BAAALgAECgQJCAABLgAFFAIJAwABAAAAAA==.Shondo:BAABLgAECn8kAAQXAAcJbySCCADmAQAXAAYJqyWCCADmAQAoAAYJ1hybAgC0AQAlAAMJER1oEQDyAAAAAA==.Shuvi:BAAALgADCgQJBAAAAA==.',
Si='Sidhell:BAAALgADCgIJAgABLgAECgYJFgAcAMUTAA==.Sigur:BAAALgADCgQJBAAAAA==.Silverin:BAAALgADCgYJBgAAAA==.Silversmage:BAAALgAECgMJAwAAAA==.Silvertraps:BAAALgADCgYJBgAAAA==.Simohiya:BAAALgADCgYJBgAAAA==.Sinthus:BAABLgAECn8UAAICAAcJmwlJxQBcAQACAAcJmwlJxQBcAQAAAA==.',
Sk='Skelatel:BAAALgADCgIJAgAAAA==.Skinard:BAAALgADCgcJEgAAAA==.',
Sl='Slappywappy:BAABLgAECn8ZAAICAAcJsRgAbgD5AQACAAcJsRgAbgD5AQAAAA==.Slutho:BAAALgAECgIJAgABLgAECgYJGAAbAPAZAA==.',
Sm='Smashing:BAAALgADCgEJAQAAAA==.Smegghead:BAAALgADCgcJDgAAAA==.Smhitehapens:BAAALgAECgQJCQAAAA==.',
Sn='Sneekybeef:BAAALgAECgQJBAAAAA==.Snekk:BAABLgAECn8aAAMKAAgJzx1gAwBiAgAKAAgJzx1gAwBiAgAFAAEJQgmVYwAvAAAAAA==.Snooks:BAABLgAECn8eAAIMAAgJPRRhDADhAQAMAAgJPRRhDADhAQAAAA==.Snowen:BAAALgAECgMJAwABLgAECggJEwABAAAAAA==.',
So='Solegir:BAAALgADCgUJBQABLgAECgIJBAABAAAAAA==.Somthinlight:BAAALgAECgIJAgABLgAFFAQJBwAKAAEXAA==.Songas:BAAALgADCgYJBgAAAA==.Sonroku:BAAALgAECgMJAwAAAA==.Soundwaves:BAAALgAECgUJBQAAAA==.Soziin:BAAALgAECgMJAwAAAA==.',
Sp='Spellnchill:BAAALgAECgYJDQAAAA==.Spharai:BAAALgADCgMJAwAAAA==.Spintor:BAAALgAECgYJEAAAAA==.Spookypaloza:BAAALgAECgcJBgAAAA==.Spookyy:BAAALgADCgUJBQAAAA==.',
Sq='Squidseye:BAAALgAECgQJBAAAAA==.',
St='Stainn:BAAALgAECgQJBAAAAA==.Stayyfrostyy:BAAALgAECgcJDQAAAA==.Sting:BAAALgAECgEJAQAAAA==.Stinkyhippie:BAAALgADCggJCAAAAA==.Stricker:BAAALgAECgYJDgAAAA==.Strickerz:BAAALgAECgQJCAAAAA==.Strongwoman:BAAALgAECgQJDAAAAA==.',
Su='Sucrose:BAAALgAECgcJEAAAAA==.Sui:BAAALgADCgQJBAAAAA==.Sunshine:BAAALgADCgEJAQAAAA==.Supernovaz:BAAALgAECgYJDAAAAA==.',
Sw='Swampygooch:BAAALgAECgEJAQABLgAECgUJCwABAAAAAA==.',
Sy='Symmas:BAAALgADCgMJAwAAAA==.Synterra:BAABLgAECn8UAAICAAYJXgrCYgAWAQACAAYJXgrCYgAWAQAAAA==.Syphian:BAAALgAECgEJAgAAAA==.Syrenda:BAAALgADCgcJDwAAAA==.Syymmaass:BAAALgAECgEJAQAAAA==.',
Ta='Taishigi:BAABLgAECn8mAAIhAAgJfQ8oJgCXAQAhAAgJfQ8oJgCXAQAAAA==.Talarian:BAAALgADCgQJBAAAAA==.Tapewyrm:BAABLgAECn8ZAAIhAAgJDBUfHwC6AQAhAAgJDBUfHwC6AQAAAA==.Tastylicks:BAAALgADCgYJBgAAAA==.',
Te='Techz:BAAALgADCgQJBAAAAA==.Teckni:BAABLgAECn8dAAIaAAgJShrCHwBTAgAaAAgJShrCHwBTAgAAAA==.Teedge:BAABLgAECn8ZAAMFAAcJHRrBGgD0AQAFAAcJHRrBGgD0AQAGAAQJLA9JKQDVAAAAAA==.Teejadin:BAAALgADCgEJAQABLgAECgcJGQAFAB0aAA==.Telluride:BAABLgAECn8WAAMHAAgJSgzCOABZAQAHAAgJSgzCOABZAQALAAEJsAIuPgAgAAAAAA==.Terraphy:BAAALgAECgMJAwAAAA==.Testtubegub:BAAALgAECgcJCgAAAA==.',
Th='Tharagis:BAABLgAECn8XAAIRAAYJ5g9jCwApAQARAAYJ5g9jCwApAQAAAA==.Thecanadìan:BAAALgADCgUJBQAAAA==.Thehallowed:BAAALgADCgkJGwAAAA==.Theophrastus:BAAALgAECgEJAgAAAA==.Thepromise:BAABLgAECn8eAAIDAAgJ5gxXMACAAQADAAgJ5gxXMACAAQAAAA==.Thewai:BAABLgAECn8cAAIPAAgJ6xFADwCdAQAPAAgJ6xFADwCdAQAAAA==.Thralia:BAAALgADCggJBgAAAA==.',
Ti='Timberlord:BAAALgAECgQJBAAAAA==.Timmytwotoes:BAAALgADCgEJAQAAAA==.',
To='Toovok:BAAALgADCgcJHAAAAA==.Totemtartt:BAAALgADCgYJBgAAAA==.Toxcinerate:BAAALgAECgMJAwABLgAECggJGAAgAJQJAA==.Toxicai:BAABLgAECn8YAAIgAAgJlAmPGQAzAQAgAAgJlAmPGQAzAQAAAA==.Toxicvoid:BAAALgADCgcJBwABLgAECggJGAAgAJQJAA==.',
Tr='Trakeus:BAABLgAECn8iAAIQAAgJ8h5VHwCVAgAQAAgJ8h5VHwCVAgAAAA==.Trinitree:BAABLgAECn8dAAIEAAgJshNvEgDHAQAEAAgJshNvEgDHAQAAAA==.Trinkler:BAAALgAECgYJEgAAAA==.Trinklr:BAAALgAECgEJAQABLgAECgYJEgABAAAAAA==.Tryhard:BAABLgAECn8ZAAQoAAYJsBpPBgD5AAAXAAYJsBrQLQCTAQAoAAQJHRJPBgD5AAAlAAEJFhU3EwBAAAABLgAECggJBwABAAAAAA==.Trée:BAAALgADCgkJEAAAAA==.',
Tu='Tunka:BAAALgAECgEJAwAAAA==.Tuulikki:BAAALgADCgYJBgAAAA==.',
Tw='Twist:BAABLgAECn8YAAICAAcJrxB8YQAZAQACAAcJrxB8YQAZAQAAAA==.',
Ty='Tychondris:BAABLgAECn8dAAIcAAgJrAoDPgAdAQAcAAgJrAoDPgAdAQAAAA==.Typobad:BAAALgAECgkJCAAAAA==.Typoblink:BAAALgAECgkJAQAAAA==.',
Ug='Ugrikester:BAAALgAECgEJAQAAAA==.',
Ul='Ulsoga:BAABLgAECn8ZAAIiAAgJZA6MAgCwAQAiAAgJZA6MAgCwAQAAAA==.',
Un='Unavailidan:BAAALgAECgUJCgAAAA==.Unhòly:BAAALgAECgYJBwAAAA==.',
Ur='Urpalnanners:BAAALgAECgMJAwAAAA==.',
Va='Valenira:BAAALgAECgcJBwAAAA==.Valkana:BAAALgAECgQJCQAAAA==.Vanicy:BAAALgAECgUJCAAAAA==.Vanitus:BAAALgAECgMJAwAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varibash:BAABLgAECn8fAAIYAAgJnBMICQChAQAYAAgJnBMICQChAQAAAA==.Vaspara:BAABLgAECn8gAAIEAAgJ3SGGBACuAgAEAAgJ3SGGBACuAgAAAA==.',
Ve='Veggiemite:BAAALgADCgYJBgAAAA==.Veggiesticks:BAAALgADCgYJDAAAAA==.Velyndra:BAAALgAECgcJCgAAAA==.Vendarius:BAAALgADCgMJAwAAAA==.Vere:BAABLgAECn8kAAIUAAkJlSFkAAAPAwAUAAkJlSFkAAAPAwAAAA==.Vestarin:BAAALgAECgcJDwAAAA==.',
Vi='Vicromano:BAAALgADCgMJAwAAAA==.Vilified:BAABLgAECn8WAAIDAAgJPiTlCACPAgADAAgJPiTlCACPAgAAAA==.Vinoamante:BAAALgADCgEJAQAAAA==.Visark:BAAALgADCgYJCwAAAA==.',
Vo='Voidlìlíth:BAABLgAECn8oAAICAAgJxRxtHwDwAQACAAgJxRxtHwDwAQAAAA==.Voidwak:BAAALgAECgYJDgAAAA==.Volcarona:BAAALgADCgcJDQAAAA==.Voronir:BAABLgAECn8cAAINAAgJZRqSCgBfAgANAAgJZRqSCgBfAgAAAA==.Vospox:BAAALgAECgcJBwAAAA==.',
Vu='Vulcan:BAAALgAECgYJCwAAAA==.',
Vy='Vyndra:BAAALgADCgIJAgAAAA==.',
['Vä']='Väder:BAAALgADCgEJAQAAAA==.',
Wa='Warbloom:BAAALgAECgYJBgAAAA==.Wardbirdname:BAAALgADCgYJBgAAAA==.Wardo:BAACLgAFFH8SAAMSAAUJfRkIBABUAQAhAAUJfRktEABdAQASAAQJYhQIBABUAQAuAAQKfy0AAxIACAkOItQBAP8CABIACAnPIdQBAP8CACEABQnPIvUUAP0BAAAA.Warplank:BAAALgAECgYJEQAAAA==.Watchmeown:BAAALgAECgEJAQAAAA==.Wawwior:BAAALgAECgMJAQAAAA==.',
We='Welders:BAAALgAECgcJAQABLgAECggJHAAfALggAA==.Weleronys:BAAALgAECgYJEAAAAA==.Wellen:BAABLgAECn8WAAIcAAYJxRO8LwBSAQAcAAYJxRO8LwBSAQAAAA==.Werewolf:BAAALgAECgIJAgAAAA==.',
Wh='Whelplayed:BAABLgAECn8ZAAQFAAYJSxuzEgBxAQAFAAYJSxuzEgBxAQAKAAQJcRC+MgDZAAAGAAIJtgdeNQBqAAAAAA==.Whitemaine:BAAALgAECgcJDQAAAA==.Whitemist:BAAALgADCgUJBQAAAA==.Whitepikmin:BAABLgAECn8gAAMOAAgJGhuGCAAjAgAOAAgJGhuGCAAjAgARAAIJjg01KwBtAAAAAA==.Whizzleton:BAAALgADCgMJAwAAAA==.',
Wi='Wilmer:BAABLgAECn8lAAIcAAgJpx63CgBSAgAcAAgJpx63CgBSAgAAAA==.Windowsvista:BAAALgAECgQJBAAAAA==.Wissa:BAAALgAECgUJCwAAAA==.Wiznasty:BAAALgADCgcJDQAAAA==.Wizylove:BAAALgADCgYJCQAAAA==.',
Wo='Wonrei:BAAALgADCgIJAgAAAA==.',
Wr='Wravc:BAAALgAECggJIAAAAQ==.Wravient:BAAALgADCgQJBAABLgAECggJIAABAAAAAQ==.',
Ww='Wwotw:BAAALgADCgcJBwAAAA==.',
Xa='Xanniheals:BAAALgAECgUJBQAAAA==.Xapphire:BAAALgADCgMJAgAAAA==.Xaspen:BAAALgAECgYJCgAAAA==.',
Xm='Xmysticxz:BAAALgADCgYJBgAAAA==.',
Xo='Xoyan:BAAALgAECgMJAwAAAA==.',
Ya='Yahs:BAAALgADCggJCAAAAA==.Yargonz:BAAALgAECgYJEQAAAA==.Yargzdk:BAACLgAFFH8UAAIIAAYJ5xBOBABiAQAIAAYJ5xBOBABiAQAuAAQKfzIAAggACAnHHdQJAH8CAAgACAnHHdQJAH8CAAAA.Yargzvoker:BAAALgADCgcJDQAAAA==.Yatyas:BAAALgADCgEJAQAAAA==.',
Ye='Yeyin:BAAALgAECgUJDQAAAA==.Yeyol:BAAALgAECgYJEwAAAA==.',
Yi='Yitpoo:BAAALgAECgUJDQAAAA==.',
Yo='Yokubo:BAABLgAECn8ZAAIhAAcJuRbANABYAQAhAAcJuRbANABYAQAAAA==.Yolius:BAAALgAECgYJCwAAAA==.Yoogi:BAAALgAECgcJDAAAAA==.Youngbullet:BAAALgADCgUJBQAAAA==.Yoyex:BAAALgAECgUJBgABLgAECgYJBgABAAAAAA==.',
Yu='Yunikon:BAAALgAECgQJBQAAAA==.',
Ze='Zellus:BAABLgAECn8aAAINAAgJdiMmBgC2AgANAAgJdiMmBgC2AgAAAA==.Zelrin:BAAALgADCgIJAgAAAA==.Zensei:BAAALgAECgIJAgABLgAECgYJBgABAAAAAA==.Zensix:BAABLgAECn8YAAIMAAgJsx40BACfAgAMAAgJsx40BACfAgAAAA==.',
Zh='Zhaphiria:BAABLgAECn8VAAMKAAcJ9BMRDABJAQAKAAUJdBYRDABJAQAFAAMJ+Bu1IQD1AAABLgAFFAUJCwAKAGAYAA==.Zhul:BAAALgAECgcJEgABLgAECggJEQABAAAAAA==.',
Zi='Zimmy:BAAALgADCgEJAQAAAA==.',
Zo='Zoku:BAAALgADCgIJAgAAAA==.',
Zu='Zugmà:BAABLgAECn8dAAIXAAgJTgmYDQCSAQAXAAgJTgmYDQCSAQAAAA==.Zukzug:BAAALgAECgUJCwAAAA==.',
['Äl']='Älpha:BAAALgAECgQJBAAAAA==.',
['Åz']='Åzïmvashÿak:BAAALgADCgcJBwAAAA==.',
['Çh']='Çhrõmié:BAABLgAECn8dAAIeAAgJ5xA2CgBhAQAeAAgJ5xA2CgBhAQAAAA==.',
['Çr']='Çrønus:BAAALgAECgYJDwAAAA==.',
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

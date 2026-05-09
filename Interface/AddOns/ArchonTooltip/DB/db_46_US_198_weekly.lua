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

local lookup = {'DemonHunter-Devourer','Mage-Frost','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Priest-Holy','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Evoker-Preservation','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','Druid-Balance','Druid-Feral','Warlock-Destruction','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Monk-Brewmaster','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Hunter-Survival','Rogue-Assassination','Mage-Arcane','Mage-Fire','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aajax:BAAALgAECgQJCwAAAA==.',
Ab='Abzdh:BAABLgAFFH8FAAIBAAIJOhTWRQCXAAABAAIJOhTWRQCXAAABLgAFFAQJCQACAMYdAA==.Abzlock:BAAALgAECgIJBQABLgAFFAQJCQACAMYdAA==.Abzmage:BAACLgAFFH8JAAICAAQJxh07GQB7AQACAAQJxh07GQB7AQAuAAQKfyQAAgIACAnGImgaAA4DAAIACAnGImgaAA4DAAAA.Abzvoker:BAAALgAECgIJAgAAAA==.',
Ac='Acht:BAAALgAECgcJCAAAAA==.',
Ad='Adderpal:BAAALgAECgQJCgAAAA==.Adelyreith:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Adramelach:BAABLgAECn8gAAIEAAcJKx5dGwAkAgAEAAcJKx5dGwAkAgAAAA==.Adriel:BAAALgADCgQJBAABLgAECgQJBAADAAAAAA==.',
Ae='Aeiay:BAABLgAECn8UAAIFAAYJjQjWIwCnAAAFAAYJjQjWIwCnAAAAAA==.',
Ag='Again:BAAALgAECgQJBAAAAA==.',
Ai='Aibh:BAAALgAECgQJBAAAAA==.Ainzooalgown:BAABLgAECn8dAAICAAgJ/hdoLwDjAQACAAgJ/hdoLwDjAQAAAA==.',
Al='Alastorian:BAAALgADCgMJAwABLgAECgUJDAADAAAAAA==.Alethice:BAAALgADCgMJAwABLgAECggJFQAGACcaAA==.Alexandrap:BAAALgAECgcJCwAAAA==.Alindis:BAAALgADCgYJCAABLgAECggJDgADAAAAAA==.Allmighto:BAECLgAFFH8UAAIHAAYJ8R8uAgDdAQAHAAYJ8R8uAgDdAQAuAAQKfyIAAgcACAl4JYIBAG0DAAcACAl4JYIBAG0DAAAA.',
An='Androstraz:BAACLgAFFH8PAAMIAAQJNiB3CwB8AQAIAAQJNiB3CwB8AQAJAAIJjgcPBwCdAAAuAAQKfx4AAwkACAlyHzYMABcCAAkABwliHDYMABcCAAgABQknH/AcAN8BAAAA.Anniesthesia:BAABLgAECn8kAAIGAAgJLgcOIwAxAQAGAAgJLgcOIwAxAQAAAA==.Anoobyss:BAAALgAECgYJDAAAAA==.Anorexorcist:BAAALgADCgkJEQABLgAECggJJQAFAKkWAA==.Anorxxorcist:BAABLgAECn8lAAIFAAgJqRa3CwC5AQAFAAgJqRa3CwC5AQAAAA==.Anthraxx:BAAALgAECgEJAwAAAA==.',
Ap='Appledeez:BAABLgAECn8kAAIKAAgJShupEQBvAgAKAAgJShupEQBvAgAAAA==.',
Ar='Archenemyy:BAAALgAECggJDgAAAA==.Arda:BAAALgAECgUJDwAAAA==.Arrax:BAACLgAFFH8IAAILAAQJARfjDQD9AAALAAQJARfjDQD9AAAuAAQKfxwAAwsACAlYIUMEABADAAsACAlYIUMEABADAAkAAQmaBn0YADIAAAAA.Arune:BAAALgAECgYJEgAAAA==.Arunem:BAAALgADCgYJCgABLgAECgYJEgADAAAAAA==.Arunen:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.',
As='Asapgbaby:BAAALgAECgEJAQAAAA==.Ashari:BAAALgAECgEJAQAAAA==.Ashly:BAAALgAECgQJDQAAAA==.Aspyrx:BAABLgAECn8iAAIFAAgJsxC/EABlAQAFAAgJsxC/EABlAQAAAA==.Astelan:BAECLgAFFH8GAAIMAAMJohfgFgD0AAAMAAMJohfgFgD0AAAuAAQKf1QABAwACQn8I3EAAMgDAAwACQn8I3EAAMgDAAoABwnlG64PANQBAAYAAQn1IOBBAF0AAAAA.Astronomica:BAABLgAECn8YAAMHAAkJug/mJQBaAQAHAAkJug/mJQBaAQAEAAUJhAgWqgCfAAAAAA==.Asunder:BAAALgAECgYJEgAAAA==.',
At='Atumsphinx:BAAALgADCgUJBQAAAA==.',
Au='Aurorä:BAABLgAECn8WAAIEAAcJWxU9PACRAQAEAAcJWxU9PACRAQAAAA==.',
Aw='Awfulrofl:BAAALgADCgYJCgAAAA==.',
Ay='Ayeola:BAAALgAECggJEwAAAA==.',
Az='Azareldurson:BAAALgAECgkJEAAAAA==.Azuresh:BAAALgAECgcJDgABLgAFFAMJCgANAOIeAA==.',
Ba='Baalrogg:BAAALgADCgYJBwAAAA==.Babywipes:BAABLgAECn8cAAQOAAkJxh6OHABYAgAOAAkJxh6OHABYAgAPAAYJ1RzoCACYAQAQAAEJqw47hQArAAAAAA==.Bachaterah:BAAALgAECgYJCwAAAA==.Baddawg:BAAALgAECgEJAgAAAA==.Baeldaeg:BAABLgAECn8lAAIBAAkJVSIkFgALAgABAAkJVSIkFgALAgAAAA==.Baelin:BAAALgAECgQJCQAAAA==.Bahahahamut:BAAALgADCgYJCAABLgAECgkJJQABAFUiAA==.Baked:BAAALgADCgEJAQAAAA==.Balkar:BAAALgADCgcJCQAAAA==.Bannett:BAACLgAFFH8VAAICAAYJbR9UCwDLAQACAAYJbR9UCwDLAQAuAAQKfxkAAgIACAn/IA43AJgCAAIACAn/IA43AJgCAAAA.Bashnveggies:BAAALgADCgMJAwAAAA==.Bastét:BAABLgAECn8dAAIKAAgJthNsGQBxAQAKAAgJthNsGQBxAQAAAA==.Bauce:BAAALgAECgYJDwAAAA==.Baxter:BAAALgADCgEJAQABLgAECgQJBAADAAAAAA==.Baxterlock:BAAALgAECgQJBAAAAA==.Baylifê:BAAALgADCggJEwAAAA==.',
Be='Bearymanalow:BAABLgAECn8WAAMPAAYJbxFSFwCoAAAPAAYJbxFSFwCoAAARAAEJ7wNiOAAnAAAAAA==.Beefyweefy:BAAALgADCgEJAgABLgAECggJDgADAAAAAA==.Bella:BAAALgAECgUJBAAAAA==.Belldelphiné:BAEALgAECgMJBgABLgAECgYJFwAFAFsUAA==.Bellz:BAAALgADCgYJBwAAAA==.Belmønt:BAAALgAECgIJAwAAAA==.',
Bi='Bicycle:BAABLgAECn8fAAISAAgJmBc1BADLAQASAAgJmBc1BADLAQAAAA==.Biddy:BAAALgAECgIJAgAAAA==.Bigpumpa:BAAALgAECgYJDgAAAA==.Billmurray:BAAALgAECgYJDwAAAA==.Billygoatgrf:BAABLgAECn8YAAICAAgJewyFTwB7AQACAAgJewyFTwB7AQAAAA==.Birchy:BAAALgADCgcJBwAAAA==.',
Bl='Blakkbeard:BAACLgAFFH8HAAITAAQJsxKjGQDhAAATAAQJsxKjGQDhAAAuAAQKfx8AAxMACAkBIhALAOcCABMACAm+IBALAOcCABQABgkoIe0SAIkBAAAA.Blakklight:BAAALgAECgYJDQABLgAFFAQJBwATALMSAA==.Blazefort:BAACLgAFFH8HAAMFAAMJZhQaFAC5AAAVAAMJphLbVADjAAAFAAMJCw0aFAC5AAAuAAQKfx8AAxUACQndGMEpAJICABUACQkTGMEpAJICABYABwlFFqgFANoBAAAA.Blazeshifts:BAAALgADCgcJBwAAAA==.Blindedd:BAAALgAECgUJBwAAAA==.Blitzeye:BAAALgAECgQJCwAAAA==.Bloodknight:BAAALgADCgMJAwAAAA==.Bloodraine:BAABLgAECn8YAAIXAAgJqxFKFQBiAQAXAAgJqxFKFQBiAQAAAA==.Bloodshadow:BAAALgADCgIJAgAAAA==.Bluucat:BAAALgAECgEJAQAAAA==.Blôô:BAABLgAECn8jAAIQAAgJlhYiEADQAQAQAAgJlhYiEADQAQAAAA==.',
Bo='Bobmoss:BAAALgAECgYJEAAAAA==.Boethius:BAAALgADCgcJEQAAAA==.Boozeftw:BAAALgADCgIJAgAAAA==.Borkhuis:BAAALgADCgYJCgAAAA==.Bouw:BAAALgADCgcJBwAAAA==.Bouz:BAAALgADCgMJAwAAAA==.Bows:BAAALgADCgIJAgAAAA==.Boysole:BAAALgAECgYJCgAAAA==.',
Bq='Bqpally:BAAALgADCgQJBAAAAA==.',
Br='Brainlesswar:BAABLgAECn8lAAIYAAgJrxY6CwC1AQAYAAgJrxY6CwC1AQAAAA==.Breemonic:BAABLgAECn8jAAIZAAgJ8Q0PIQC0AQAZAAgJ8Q0PIQC0AQAAAA==.Brewdie:BAAALgADCggJFAAAAA==.Bristle:BAAALgADCgYJBgAAAA==.Bruce:BAACLgAFFH8RAAQaAAUJZyWiAgClAQAaAAQJZyWiAgClAQAYAAIJzREbEwCKAAAbAAIJsR4SCQBhAAAuAAQKfyQABBoACQltJP8KAAQDABoACQkaJP8KAAQDABgACAnzHNcIAJECABsAAgkbGacrAJcAAAAA.Brucetree:BAAALgADCgYJBgAAAA==.',
Bu='Bubblekush:BAAALgAECgcJDgAAAA==.Bubbleøseven:BAAALgAECgYJCwAAAA==.Budders:BAAALgADCgYJCwAAAA==.Butterz:BAAALgAECgIJAwAAAA==.Buttshank:BAAALgAECgYJDwAAAA==.',
Ca='Cailleach:BAAALgAECgMJBAAAAA==.Calyx:BAAALgAECgQJBAAAAA==.Carson:BAAALgAECgQJCgAAAA==.Casagrande:BAAALgADCgEJAQABLgAFFAMJBQAcADgiAA==.',
Ch='Chaosvader:BAAALgADCggJGwAAAA==.Chickenbich:BAAALgADCgkJEAAAAA==.Chobi:BAAALgAECgEJAQAAAA==.Choices:BAAALgADCgUJBQABLgAECgkJFwAcAPwfAA==.Chrunch:BAAALgADCgYJBgAAAA==.Chuggernaugt:BAABLgAECn8aAAIdAAcJkRJlHABAAQAdAAcJkRJlHABAAQAAAA==.',
Ci='Cinnamen:BAABLgAECn8hAAIXAAkJpBnZCQADAgAXAAkJpBnZCQADAgAAAA==.',
Cl='Cleff:BAAALgAECgEJAQAAAA==.Cllawhan:BAAALgADCgkJCgAAAA==.Clutchcity:BAAALgADCgYJBgAAAA==.',
Co='Coaa:BAABLgAECn8YAAIcAAcJ6xz3KACtAQAcAAcJ6xz3KACtAQAAAA==.Codèx:BAABLgAECn8pAAICAAgJfBhHNgDJAQACAAgJfBhHNgDJAQAAAA==.Colossus:BAABLgAECn8jAAIEAAgJ5QqmUQBSAQAEAAgJ5QqmUQBSAQAAAA==.Computertan:BAAALgADCgEJAQAAAA==.Conclave:BAAALgADCgcJDAABLgAECggJJAAIAEYWAA==.Contrap:BAAALgADCgMJAwABLgAECggJJAAIAEYWAA==.Convoker:BAABLgAECn8kAAMIAAgJRhZXEQDFAQAIAAgJUBRXEQDFAQAJAAYJnRY2FQCYAQAAAA==.Coolbreeze:BAAALgAECgYJDAAAAA==.Cootert:BAAALgAECggJDgAAAA==.',
Cp='Cptnamerica:BAAALgAECgkJAQAAAA==.',
Cr='Creamsnake:BAAALgAECgEJAgAAAA==.Crimo:BAAALgAECgYJBwABLgAFFAYJFgAQAFUdAA==.Crimons:BAAALgAECggJEgAAAA==.Cronk:BAABLgAECn8aAAMeAAgJ6BkyCADLAQAeAAcJix0yCADLAQAEAAEJFgSfVAEpAAAAAA==.Crèscent:BAAALgADCgEJAQAAAA==.Crõwfather:BAABLgAECn8jAAIfAAgJXx6kCgCDAgAfAAgJXx6kCgCDAgAAAA==.',
Cu='Curtland:BAAALgAECgQJAQAAAA==.',
Cz='Czy:BAAALgAECgEJAQAAAA==.',
Da='Dadjokes:BAAALgAECgEJAQAAAA==.Daggõth:BAAALgAECgEJAQAAAA==.Darkakaza:BAAALgAECgYJCwAAAA==.Darkbu:BAAALgAECgUJBQABLgAECgkJGAABAJQZAA==.Darkermagic:BAAALgAECgEJAQAAAA==.Darkmeadow:BAABLgAECn8XAAIQAAYJwxVqIQAsAQAQAAYJwxVqIQAsAQAAAA==.Dasgoose:BAAALgADCgIJAgAAAA==.Dastard:BAACLgAFFH8GAAITAAMJyhPWFwDtAAATAAMJyhPWFwDtAAAuAAQKfxwAAhMACAmdFj0fABYCABMACAmdFj0fABYCAAAA.Datmonk:BAABLgAECn8YAAIgAAgJxBT5DwDLAQAgAAgJxBT5DwDLAQAAAA==.Dave:BAAALgADCgEJAQAAAA==.',
De='Deadlymagic:BAAALgAECgUJCQAAAA==.Deadtorights:BAAALgAECgUJBAAAAA==.Deathblossom:BAAALgAECgUJCQAAAA==.Deathbrñgr:BAAALgADCgQJBAABLgAFFAQJCAAEAHIFAA==.Deathlyfrost:BAABLgAECn8aAAIFAAcJRBPEFAAwAQAFAAcJRBPEFAAwAQAAAA==.Deathvader:BAAALgADCgcJHQAAAA==.Decimatore:BAAALgAECgMJAwAAAA==.Decrepitt:BAAALgADCgEJAQAAAA==.Dedara:BAABLgAECn8VAAIGAAgJJxoYGQATAgAGAAgJJxoYGQATAgAAAA==.Deebow:BAAALgADCgUJBgAAAA==.Deeptotes:BAAALgAECgQJBAAAAA==.Deftonia:BAABLgAECn8bAAIEAAkJ8A6yVgBFAQAEAAkJ8A6yVgBFAQAAAA==.Degenerate:BAABLgAECn8rAAMhAAkJPxgPDwBwAgAhAAkJPxgPDwBwAgAiAAUJbhlIDQBhAQAAAA==.Demonbläde:BAABLgAECn8UAAMZAAYJNBQhOQAeAQAZAAUJGBYhOQAeAQAjAAMJMxAhHgCXAAAAAA==.Demonbread:BAAALgAECgEJAQAAAA==.Demonmandis:BAAALgADCgEJAQAAAA==.Derriereizi:BAAALgAECgMJAwAAAA==.Devondric:BAABLgAECn8oAAIMAAcJ4RFIFQCUAQAMAAcJ4RFIFQCUAQAAAA==.Devotion:BAAALgADCgYJBgABLgAFFAUJCwAHALMXAA==.Devotional:BAACLgAFFH8LAAIHAAUJsxePBgC1AQAHAAUJsxePBgC1AQAuAAQKfyUAAwcACAm4Hg4FAN0CAAcACAm4Hg4FAN0CAAQAAwktAv8gAVsAAAAA.',
Dh='Dhaos:BAAALgAECgIJAgABLgAFFAEJAgADAAAAAA==.',
Di='Diekuh:BAAALgADCgEJAQAAAA==.Dinkellberg:BAAALgAECgQJBQAAAA==.Dirgens:BAACLgAFFH8SAAIhAAYJew79EgBsAQAhAAYJew79EgBsAQAuAAQKfyEAAiEACAleIJsdAKUCACEACAleIJsdAKUCAAAA.Dirgenz:BAAALgADCgYJBgAAAA==.Disquietor:BAAALgADCgQJBQAAAA==.Divinacurita:BAAALgAECgUJDQAAAA==.',
Dk='Dkay:BAAALgADCgcJDQAAAA==.',
Do='Dodel:BAAALgADCgYJCgABLgAECgEJAQADAAAAAA==.Dokumai:BAABLgAECn8ZAAMgAAcJGx6hEgCsAQAgAAcJER6hEgCsAQAdAAMJ7RVsSgBaAAABLgAFFAEJAgADAAAAAA==.Dommiemommie:BAAALgADCgUJBQABLgAECgcJEQADAAAAAA==.Dooterfiddle:BAAALgAECgEJAQAAAA==.Doozerd:BAAALgAECgMJAwAAAA==.Doozerp:BAACLgAFFH8NAAIMAAQJ1Q0zEwArAQAMAAQJ1Q0zEwArAQAuAAQKfyIAAwwACAnkGhoQANEBAAwACAlHGhoQANEBAAYABQnvCy1NAAMBAAAA.Dor:BAAALgAECgEJAgAAAA==.Doraexplorer:BAAALgAECgEJAQAAAA==.Dorinmigrane:BAEALgADCgYJBgABLgAECggJPAABABghAA==.Dorinramps:BAEBLgAECn88AAIBAAgJGCEyCACiAgABAAgJGCEyCACiAgAAAA==.Dotfearwin:BAAALgAECgYJDgAAAA==.Doviculus:BAAALgAECgYJEAAAAA==.',
Dr='Dragmcgoon:BAABLgAECn8qAAIIAAgJGhiIEwBIAgAIAAgJGhiIEwBIAgAAAA==.Drakonman:BAABLgAECn8YAAITAAgJIAp3IQBFAQATAAgJIAp3IQBFAQAAAA==.Drakrappa:BAAALgADCgcJCAAAAA==.Drakthorr:BAAALgAECgcJEgAAAA==.Draynen:BAABLgAECn8cAAMfAAcJ/BkIIwANAgAfAAcJ/BkIIwANAgAUAAIJfwO8KABQAAABLgAFFAYJDQALAGcWAA==.Drboom:BAAALgADCgYJCgAAAA==.Drcrimo:BAACLgAFFH8WAAIQAAYJVR1iAgDiAQAQAAYJVR1iAgDiAQAuAAQKfykAAhAACAlMIzYIABIDABAACAlMIzYIABIDAAAA.Drdööm:BAAALgADCgEJAQAAAA==.Drevil:BAAALgAECggJDwAAAA==.Drø:BAAALgADCgcJEQABLgAECgYJCgADAAAAAA==.',
Du='Duck:BAAALgAECgEJAgAAAA==.Duckduck:BAAALgAECgYJEgAAAA==.Dudemanyeah:BAAALgADCgEJAQAAAA==.Dulcïnea:BAABLgAECn8XAAIBAAgJpxVaVQCjAQABAAgJpxVaVQCjAQAAAA==.Dumbanimal:BAAALgAECgkJEgAAAA==.Durnir:BAAALgAECgMJAwAAAA==.Durut:BAABLgAECn8bAAIVAAgJ2iFWEQByAgAVAAgJ2iFWEQByAgAAAA==.',
Dw='Dwarfbussy:BAAALgAECgMJAwAAAA==.',
['Dê']='Dêathany:BAAALgADCgMJBAAAAA==.',
Ea='Eao:BAAALgAECgQJBQAAAA==.Easley:BAAALgAFFAEJAgAAAA==.',
Ec='Ecliptic:BAAALgAECgEJAQAAAA==.',
Ed='Edrana:BAAALgAECgIJAgABLgAECgUJDAADAAAAAA==.Edurna:BAAALgADCgIJAgAAAA==.',
Eh='Ehvyn:BAAALgAECgYJDwAAAA==.',
El='Elementcreep:BAAALgADCgYJBwAAAA==.Elise:BAAALgAECgUJCQAAAA==.Elitistjerk:BAAALgAECgUJBgAAAA==.Eliza:BAAALgAECgcJDgAAAA==.Elizzabeth:BAAALgAECgYJDwAAAA==.Ellisis:BAABLgAECn8VAAIeAAgJmRffCgCTAQAeAAgJmRffCgCTAQAAAA==.Elvarg:BAAALgADCgQJBAABLgAECgYJDwADAAAAAA==.',
Em='Emriq:BAABLgAECn8kAAIEAAgJeyA4DQCWAgAEAAgJeyA4DQCWAgAAAA==.',
En='Enmai:BAABLgAECn8fAAIhAAcJAQ6ORABbAQAhAAcJAQ6ORABbAQAAAA==.',
Ep='Ephius:BAAALgAECgUJDAAAAA==.',
Er='Eranar:BAAALgAECgEJAQAAAA==.Eraquxx:BAAALgADCgcJBwAAAA==.Ertironin:BAAALgADCgcJDgABLgAECggJGAACAHsMAA==.',
Es='Esper:BAAALgADCgcJBwABLgAECgkJJQABAFUiAA==.Esthar:BAAALgAECgYJEAAAAA==.',
Et='Etheko:BAAALgAECgQJBAAAAA==.Etir:BAABLgAECn8kAAICAAgJrw54QwCdAQACAAgJrw54QwCdAQAAAA==.',
Eu='Eudæmønia:BAAALgAECgYJEwAAAA==.',
Ev='Evangelise:BAAALgAECgIJAgAAAA==.Evella:BAAALgAECgYJBwAAAA==.',
Ex='Exodiusx:BAAALgAECgUJCQAAAA==.Exxitus:BAAALgAECgYJDQAAAA==.',
Ey='Eyebeam:BAAALgAECgEJAQAAAA==.Eyebrowsius:BAAALgAECgUJCQABLgAFFAMJCgANAOIeAA==.',
Fa='Falorel:BAAALgADCgIJAgAAAA==.Falsoqt:BAAALgAECgYJDgAAAA==.Faragon:BAAALgAECgQJBAAAAA==.Faux:BAAALgAECgQJCAABLgAECgkJIgAYAO8TAA==.Fayline:BAAALgAECgYJDAAAAA==.',
Fb='Fblthp:BAABLgAECn8VAAICAAgJqhcdRwCSAQACAAgJqhcdRwCSAQAAAA==.',
Fe='Fecalmatters:BAAALgADCgQJBAAAAA==.Felachio:BAABLgAECn8hAAIcAAgJjh9XCwCGAgAcAAgJjh9XCwCGAgAAAA==.Felrush:BAAALgAECgYJBwAAAA==.Fenno:BAAALgAECgYJDAAAAA==.Fentfliction:BAAALgADCgYJBgAAAA==.',
Fi='Fidelitaslex:BAAALgAECgEJAQAAAA==.Firerage:BAABLgAECn8UAAIhAAcJYyE9RAD/AQAhAAcJYyE9RAD/AQAAAA==.Fischform:BAABLgAECn8iAAIOAAgJZCUsBQAIAwAOAAgJZCUsBQAIAwAAAA==.',
Fj='Fjörgyn:BAACLgAFFH8TAAITAAUJFiP8AgDDAQATAAUJFiP8AgDDAQAuAAQKfyUAAhMACQmeJCIBAL8DABMACQmeJCIBAL8DAAAA.',
Fl='Flashlight:BAAALgADCgUJBQAAAA==.Flexr:BAAALgADCgMJAwAAAA==.',
Fo='Forsetí:BAAALgAECgQJBQAAAA==.Fortress:BAAALgAECgIJAgAAAA==.',
Fr='Frasierkrane:BAAALgADCgUJBQAAAA==.Frontshots:BAAALgAECgYJCAAAAA==.Fruitieloopz:BAAALgAECgcJAQAAAA==.',
Ft='Ftfk:BAAALgAECgQJBAABLgAECgkJIgALAA4jAA==.',
Fu='Funguslice:BAAALgAECgYJDQABLgAECgUJCwADAAAAAA==.Funji:BAAALgAECgEJAQAAAA==.Funkyflank:BAAALgAECgMJAwAAAA==.',
Ga='Galactica:BAAALgADCgEJAQAAAA==.Galdoria:BAAALgAECgIJAgABLgAECgUJDgADAAAAAA==.Galie:BAABLgAECn8pAAMQAAgJmxENFwCDAQAQAAgJmxENFwCDAQARAAUJ3gukIgDDAAAAAA==.Galìe:BAAALgADCgcJDgAAAA==.Garrahoth:BAAALgADCgYJCgABLgAECggJDgADAAAAAA==.Gatherith:BAAALgAECgMJAwAAAA==.',
Ge='Gekk:BAABLgAECn8lAAMLAAgJnhzuBQAvAgALAAgJnhzuBQAvAgAIAAQJ1w+JMADiAAAAAA==.Gendarme:BAAALgAECgUJCAAAAA==.',
Gh='Ghostface:BAABLgAECn8mAAMHAAcJsA4sJABnAQAHAAcJsA4sJABnAQAEAAUJIAukgQDpAAAAAA==.Ghuun:BAAALgAECgQJBAAAAA==.',
Gi='Giaus:BAABLgAECn8gAAICAAgJfBNyNQDLAQACAAgJfBNyNQDLAQAAAA==.Gimmeh:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgMJBQAAAA==.',
Gl='Glama:BAAALgAECgEJAQAAAA==.Glorified:BAAALgAECgIJAgAAAA==.Glump:BAAALgADCgMJAwAAAA==.',
Go='Gobzilla:BAABLgAECn8mAAIfAAgJlCJmEQCLAgAfAAgJlCJmEQCLAgAAAA==.Gonn:BAAALgADCgIJAgAAAA==.Goodboy:BAAALgAECgQJBQAAAA==.Goonergramps:BAAALgADCgkJCQAAAA==.Goub:BAABLgAECn8bAAMfAAkJfhxzFABxAgAfAAgJLxtzFABxAgATAAcJfg3HMgDlAAAAAA==.Goubam:BAAALgAECgEJAQABLgAECgkJGwAfAH4cAA==.',
Gr='Gracieiris:BAAALgAECgUJBQAAAA==.Grapefroot:BAABLgAECn8VAAIkAAYJQBWLFQBmAQAkAAYJQBWLFQBmAQAAAA==.Grapeinator:BAAALgADCgQJBQAAAA==.Grapey:BAABLgAECn8UAAMFAAYJHxxxEABrAQAFAAYJHxxxEABrAQAVAAEJ5QKCLwEoAAAAAA==.Greenarrow:BAAALgADCggJCAAAAA==.Greenwarlock:BAAALgAECgYJEwAAAA==.Grimhoof:BAAALgAECgQJBQAAAA==.Grimhorn:BAAALgAECgMJAwAAAA==.Gripdip:BAAALgAECgEJAQAAAA==.Grnola:BAABLgAECn8UAAIVAAYJrxDWngBDAQAVAAYJrxDWngBDAQAAAA==.Gromn:BAAALgAECgQJBAAAAA==.',
Gu='Guki:BAAALgAECgcJBwAAAA==.Guldum:BAAALgADCgUJCwAAAA==.Gurvinder:BAAALgAECgYJBwAAAA==.',
Gw='Gwyne:BAACLgAFFH8KAAIVAAQJ4CACHQBoAQAVAAQJ4CACHQBoAQAuAAQKfyYAAhUACAnhJX8NAC4DABUACAnhJX8NAC4DAAAA.',
Ha='Hailstorm:BAAALgADCgQJBQAAAA==.Halfstack:BAAALgAECgUJBQAAAA==.Halucid:BAAALgADCgIJAgAAAA==.Happywoodz:BAABLgAFFH8HAAIHAAMJUhnUFwDmAAAHAAMJUhnUFwDmAAAAAA==.Hardmoney:BAAALgADCgMJAwAAAA==.Harmsway:BAAALgADCgEJAQAAAA==.Hashed:BAABLgAECn8hAAIEAAkJWxlkJADyAQAEAAkJWxlkJADyAQAAAA==.Haveanicejay:BAAALgAECgQJBgAAAA==.Haysevoker:BAACLgAFFH8TAAILAAYJlhptBQDTAQALAAYJlhptBQDTAQAuAAQKfx4AAwsACAkTISgGAOICAAsACAkTISgGAOICAAgAAgnAFtJPAI0AAAAA.Haysmonk:BAABLgAECn8WAAMNAAYJtBZyIABCAQANAAYJtBZyIABCAQAgAAYJgAVYNADIAAAAAA==.',
He='Heliumprime:BAAALgAECgEJAwAAAA==.Hellabrews:BAABLgAECn8YAAINAAYJfxoDFAC9AQANAAYJfxoDFAC9AQAAAA==.Hexcellent:BAAALgADCggJDwAAAA==.',
Ho='Hogra:BAAALgADCgUJBQABLgAECggJGgAeAOgZAA==.Holemilk:BAAALgADCgYJBgAAAA==.Holstadd:BAAALgAECgEJAgAAAA==.Hoodler:BAECLgAFFH8XAAIOAAUJuiRfAwAcAgAOAAUJuiRfAwAcAgAuAAQKfyIAAw4ACAkqJm0DAFwDAA4ACAkqJm0DAFwDABEAAQlSGh4iAE4AAAAA.Hoodlere:BAEALgAFFAMJAwABLgAFFAUJFwAOALokAA==.Hoodlery:BAEALgAFFAIJBAABLgAFFAUJFwAOALokAA==.Horndrojo:BAAALgAECgEJAQAAAA==.Hortraz:BAAALgAECgYJDgAAAA==.Hotzcake:BAAALgAECgMJAgAAAA==.',
Hr='Hrathen:BAAALgAECgEJAQAAAA==.',
Hu='Humphugull:BAAALgAECgYJEwAAAA==.Huntoine:BAAALgAECgYJDQABLgAFFAUJCgAKANwVAA==.Huskydots:BAACLgAFFH8GAAIhAAMJRgVWPwCNAAAhAAMJRgVWPwCNAAAuAAQKfxoAAyEACAkaGXg/AA8CACEABwkaGXg/AA8CABIABAlPDhE0AOcAAAAA.',
Hy='Hyroshi:BAAALgADCgYJBgAAAA==.Hyur:BAABLgAECn8XAAITAAcJ8BJ7GwByAQATAAcJ8BJ7GwByAQAAAA==.',
['Hâ']='Hâmmy:BAAALgAECgIJAgAAAA==.',
Ib='Iblastpants:BAABLgAECn8YAAIdAAcJbxRiFQCAAQAdAAcJbxRiFQCAAQAAAA==.',
Ic='Ichoroath:BAAALgAECgcJDQAAAA==.',
Ig='Iggyy:BAAALgAECgUJEQAAAA==.',
Ij='Ijjii:BAAALgAECgcJEgAAAA==.',
Ik='Ikkirak:BAAALgAECgEJAQAAAA==.',
Il='Ilgynoth:BAABLgAECn8aAAMQAAgJxg7SMQB8AQAQAAgJxg7SMQB8AQAOAAUJuwqEhQDMAAAAAA==.Illidaris:BAAALgADCgMJAwAAAA==.Illidonut:BAAALgADCgUJBAABLgAECgYJDgADAAAAAA==.',
Im='Imdeadinside:BAAALgAECgYJBwAAAA==.Imsuperlost:BAAALgADCgUJBQAAAA==.',
In='Infinitas:BAAALgADCgUJBgAAAA==.Inflammo:BAAALgAECgcJCwAAAA==.Inflic:BAAALgADCggJFQAAAA==.Inspectadeck:BAAALgAECgYJDQAAAA==.Integ:BAAALgAECgEJAQAAAA==.',
Ir='Irila:BAABLgAECn8ZAAIPAAgJlhC9DABDAQAPAAgJlhC9DABDAQAAAA==.Irmerlock:BAAALgADCgMJAwAAAA==.Irshadin:BAABLgAECn8sAAMEAAkJwyHbCADGAgAEAAkJwyHbCADGAgAeAAIJUwaxPgBDAAAAAA==.Irshingwary:BAAALgADCggJCAAAAA==.',
Is='Istackspirit:BAAALgAECgQJBAAAAA==.',
Iz='Izumî:BAAALgAECgYJCQAAAA==.',
Ja='Jaebuns:BAAALgAECgQJBQAAAA==.Jakob:BAAALgAECgIJBAAAAA==.Jamiie:BAAALgAECgMJBAAAAA==.Jangosan:BAAALgADCgkJDwAAAA==.Jangutu:BAABLgAECn8XAAIXAAcJVhJlEACgAQAXAAcJVhJlEACgAQAAAA==.Jasonluv:BAAALgAECgQJCwAAAA==.Jaspy:BAABLgAECn8nAAIRAAkJpxUQBAAzAgARAAkJpxUQBAAzAgAAAA==.Jaynee:BAABLgAECn8dAAIEAAgJoCR+CQC/AgAEAAgJoCR+CQC/AgAAAA==.',
Ji='Jinharu:BAAALgADCgkJCQABLgAFFAEJAgADAAAAAA==.',
Jo='Jomgpallie:BAAALgAECgYJEgAAAA==.Jonac:BAAALgAECgEJAQAAAA==.Josefbugman:BAABLgAECn8UAAIkAAcJUx3OCQAHAgAkAAcJUx3OCQAHAgAAAA==.',
Ju='Juicee:BAAALgADCgcJEQAAAA==.Juktal:BAABLgAECn8WAAIkAAgJlBPPDgC7AQAkAAgJlBPPDgC7AQAAAA==.Jukujo:BAAALgAECgYJBgAAAA==.Jupîter:BAAALgAECgcJDAAAAA==.Justyn:BAABLgAECn8VAAMaAAYJ3BSCPQDMAAAaAAUJSBCCPQDMAAAbAAIJBBRsKQCBAAAAAA==.',
Ka='Kajoru:BAAALgADCgcJBwAAAA==.Kancho:BAAALgAECgUJCAAAAA==.Karlsparx:BAAALgAECgUJBQAAAA==.Kattakuri:BAAALgADCgYJBgAAAA==.Kazuje:BAAALgAFFAMJBAAAAA==.Kazzu:BAAALgAECgMJAwAAAA==.',
Ke='Ketia:BAAALgADCggJEQAAAA==.Keyal:BAEALgAECgcJCgABLgAFFAQJCwAOAIMXAA==.',
Kh='Kheros:BAAALgAECgUJCwAAAA==.Khiron:BAAALgADCgUJCQAAAA==.',
Ki='Kialorstus:BAAALgAECgkJCwAAAA==.Kiilladellph:BAAALgAECgQJBAAAAA==.Kilarga:BAAALgADCgUJBQAAAA==.Kilo:BAABLgAECn8aAAMYAAYJDhcMFQAfAQAYAAYJDhcMFQAfAQAaAAUJ4AJgUgBrAAAAAA==.Kimari:BAAALgADCgEJAgAAAA==.Kinzington:BAAALgAECgEJAQAAAA==.Kirbo:BAAALgAECgYJBwAAAA==.Kiriron:BAAALgAECgQJBgAAAA==.Kittyperry:BAAALgAECgMJAwABLgAECgkJGwAEAPAOAA==.',
Ko='Kolakua:BAAALgADCgIJAgAAAA==.Kookiemonsta:BAAALgADCgcJAQAAAA==.Kouw:BAAALgAECggJEgAAAA==.',
Kr='Kramx:BAAALgAECgcJEwAAAA==.Krankenstein:BAAALgAECgYJDQAAAA==.Krankson:BAAALgAECgYJDgAAAA==.Kriix:BAABLgAECn8bAAIlAAgJeyFJAQCZAgAlAAgJeyFJAQCZAgAAAA==.Krugah:BAAALgAECgQJCAAAAA==.Krusnik:BAAALgAECgUJCgAAAA==.',
Ks='Ksubi:BAAALgAECgEJAQAAAA==.',
Ku='Kuhnleone:BAAALgADCgcJBwAAAA==.Kujatas:BAABLgAECn8iAAMTAAcJVCKFCQBCAgATAAcJVCKFCQBCAgAfAAIJVRxcVwChAAAAAA==.Kuls:BAAALgADCgcJBwAAAA==.Kumdobeast:BAAALgAECgMJAwAAAA==.Kuothe:BAABLgAECn8vAAICAAkJ9BRLHwAvAgACAAkJ9BRLHwAvAgAAAA==.Kuroakami:BAAALgAECgEJAQAAAA==.',
Ky='Kyrael:BAAALgAECgUJDAAAAA==.',
['Kí']='Kíllahpriest:BAAALgADCgcJGgAAAA==.',
La='Laelunea:BAAALgAECggJEQAAAA==.Lambslayer:BAAALgADCgMJAwAAAA==.Lannsing:BAABLgAECn82AAMMAAkJrR7VAgATAwAMAAkJ8hvVAgATAwAGAAgJbCCmBQCoAgAAAA==.',
Le='Leetpkss:BAAALgADCgYJBgAAAA==.Lenaría:BAAALgAECgEJAQAAAA==.Leofric:BAAALgAECgIJAgAAAA==.Leonheart:BAAALgADCgQJBQAAAA==.Leonphelps:BAAALgADCgEJAQAAAA==.Lesnichii:BAABLgAECn8ZAAIQAAgJvwtjGgBkAQAQAAgJvwtjGgBkAQAAAA==.Letemkrap:BAAALgAECgEJAwAAAA==.Lewakex:BAAALgAECgcJCQAAAA==.Leyendaz:BAAALgADCgUJBwABLgAECgUJBQADAAAAAA==.Leyzormemes:BAABLgAECn8cAAIBAAgJBiNUGQC8AgABAAgJBiNUGQC8AgAAAA==.',
Li='Lifegrip:BAAALgAECgMJAwABLgAECggJCAADAAAAAA==.Lightbrngr:BAACLgAFFH8IAAIEAAQJcgUfJQAYAQAEAAQJcgUfJQAYAQAuAAQKfyQAAgQACAmeGOsqANIBAAQACAmeGOsqANIBAAAA.Lihuai:BAABLgAECn8iAAMdAAkJ6whqFgB1AQAdAAkJ6whqFgB1AQANAAYJ9gShRwC7AAAAAA==.Lilbertha:BAABLgAECn8uAAQCAAgJWhLrcQDvAQACAAgJWhLrcQDvAQAmAAEJnAuKDQA6AAAnAAIJ+AcVCwA1AAAAAA==.Lilconcon:BAABLgAECn8hAAITAAkJshFyGQCDAQATAAkJshFyGQCDAQAAAA==.Lildipster:BAAALgAECgMJAwABLgAECgkJJQABAFUiAA==.Lilthrall:BAAALgADCgkJFwAAAA==.Liptonaysti:BAAALgAECgYJEQAAAA==.Lissandine:BAACLgAFFH8IAAIjAAQJDwpzAwDQAAAjAAQJDwpzAwDQAAAuAAQKfyIAAiMACAliHZsGACYCACMACAliHZsGACYCAAAA.Liuxin:BAAALgAECgYJCAAAAA==.Lizzywizzy:BAAALgADCgUJBQABLgAECgkJJQABAFUiAA==.',
Ll='Llaydee:BAAALgADCgUJBQAAAA==.',
Lo='Loalight:BAAALgADCgYJDAAAAA==.Lodencilly:BAAALgADCgIJAgAAAA==.Lomao:BAAALgADCgQJBQAAAA==.Longdude:BAABLgAECn8VAAIgAAgJlQexIAAyAQAgAAgJlQexIAAyAQAAAA==.Lorth:BAAALgADCgEJAQAAAA==.Lotharn:BAAALgAECgQJBwAAAA==.Lowdy:BAABLgAECn8YAAMaAAcJdBFAJgBCAQAaAAcJnw9AJgBCAQAbAAQJSRKgFwD6AAAAAA==.',
Lu='Lucas:BAABLgAECn8YAAITAAcJVR9mGACNAQATAAcJVR9mGACNAQAAAA==.Lucifri:BAEBLgAECn8XAAIFAAYJWxTgHwBFAQAFAAYJWxTgHwBFAQAAAA==.Luckydo:BAAALgADCgUJBQABLgAECggJFQAkAFkOAA==.Luckydoo:BAABLgAECn8VAAIkAAgJWQ7ODQDJAQAkAAgJWQ7ODQDJAQAAAA==.Luvr:BAAALgADCgIJAgAAAA==.',
Ly='Lych:BAAALgAECgQJBAAAAA==.Lystra:BAAALgAECgEJAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8WAAIhAAYJ/gtLXAAaAQAhAAYJ/gtLXAAaAQAAAA==.',
Ma='Madting:BAAALgADCgEJAQAAAA==.Magnuss:BAABLgAECn8XAAICAAgJUhRoawD/AQACAAgJUhRoawD/AQAAAA==.Mahini:BAAALgAECgcJAQAAAA==.Majick:BAAALgADCgcJBwAAAA==.Malthaell:BAAALgAECggJEAAAAA==.Maltyablo:BAABLgAECn8fAAIjAAgJDxRXBgCaAQAjAAgJDxRXBgCaAQAAAA==.Mammutos:BAAALgAECgEJAQAAAA==.Manapaws:BAABLgAECn8fAAIGAAcJOxutDQALAgAGAAcJOxutDQALAgAAAA==.Manddarb:BAAALgADCgIJAgAAAA==.Manion:BAABLgAECn8gAAMTAAkJDRNNEQDVAQATAAkJDRNNEQDVAQAfAAQJ4gXsiwBlAAAAAA==.Manippiez:BAAALgAECgQJBAAAAA==.Manipulating:BAAALgAECgYJEAAAAA==.Manipulation:BAABLgAECn8YAAMKAAcJ5gYCJQAbAQAKAAcJ5gYCJQAbAQAMAAIJMAKxUQBEAAAAAA==.Mannarchy:BAABLgAECn8bAAMeAAYJ+xc/DQBlAQAeAAYJ+xc/DQBlAQAEAAQJTBC7mwC5AAAAAA==.Manpan:BAAALgAECgEJAgAAAA==.Mantrà:BAAALgADCgkJFwAAAA==.Margot:BAAALgAECgQJBAABLgAECgcJCwADAAAAAA==.Marquise:BAABLgAECn8ZAAMIAAgJbRS/GQD/AQAIAAgJcxO/GQD/AQAJAAYJHxSbFwB9AQAAAA==.Masochista:BAABLgAFFH8RAAIFAAUJHSHVBABaAQAFAAUJHSHVBABaAQAAAA==.Mastavas:BAAALgAECgQJBAAAAA==.Mastric:BAEBLgAECn8mAAIhAAkJzQdxRABcAQAhAAkJzQdxRABcAQAAAA==.Matarkbro:BAABLgAECn8pAAIYAAgJXh2LBQBIAgAYAAgJXh2LBQBIAgAAAA==.Maudelyn:BAAALgADCgQJBgAAAA==.Mayumißrown:BAAALgADCgUJBwAAAA==.Mazrin:BAAALgADCgEJAQAAAA==.',
Mc='Mccaffrey:BAABLgAECn8lAAMaAAgJXxe/DQAQAgAaAAgJXxe/DQAQAgAbAAEJ+g+jPAA/AAAAAA==.Mcstuffings:BAAALgADCgUJBQABLgAECgcJHQAfAGEdAA==.',
Me='Meetch:BAACLgAFFH8MAAIVAAQJnBRCLQBFAQAVAAQJnBRCLQBFAQAuAAQKfx0AAhUACAmFFzhBADQCABUACAmFFzhBADQCAAAA.Megdar:BAAALgAECgMJAwAAAA==.Meldbot:BAAALgAECgcJDQABLgAFFAUJEQAFAB0hAA==.Merix:BAACLgAFFH8GAAIXAAMJ9g1YFQDuAAAXAAMJ9g1YFQDuAAAuAAQKfycAAhcACQl8HBIGAFMCABcACQl8HBIGAFMCAAAA.Mestea:BAAALgAECgYJDAAAAA==.Mewing:BAAALgAECgUJBwABLgAECgcJGwAEACUdAA==.Mexorcistp:BAABLgAECn8YAAIHAAgJxhleGABPAgAHAAgJxhleGABPAgAAAA==.Mexorcists:BAAALgAECgIJBgABLgAECggJGAAHAMYZAA==.',
Mi='Mirra:BAAALgAECgUJBQAAAA==.Mirus:BAABLgAECn8bAAMcAAgJnhYPMwDjAQAcAAgJ8RMPMwDjAQAkAAYJnA0BGQA/AQAAAA==.',
Ml='Mlee:BAAALgAECgQJBAAAAA==.',
Mo='Mojobtw:BAACLgAFFH8JAAIHAAQJOyawBQDFAQAHAAQJOyawBQDFAQAuAAQKfx8AAwcACAmpJXgDADoDAAcACAmpJXgDADoDAAQAAQmVFKA6ATcAAAAA.Monkeybiz:BAAALgAECggJDwABLgAECggJEQADAAAAAA==.Monkeyc:BAAALgADCgEJAQAAAA==.Monos:BAAALgADCgQJBAAAAA==.Monsterboy:BAAALgADCgcJCQAAAA==.Mooby:BAAALgADCgYJBgAAAA==.Moontouched:BAAALgAECgUJCAABLgAECgYJCwADAAAAAA==.Mord:BAAALgAECgEJAgAAAA==.Morrkoth:BAAALgAECgEJAQAAAA==.Mors:BAAALgAECgYJEgAAAA==.Mortamur:BAACLgAFFH8FAAICAAMJbQy3SgDzAAACAAMJbQy3SgDzAAAuAAQKfyYAAgIACAk+FbU1AMsBAAIACAk+FbU1AMsBAAAA.Mortelinnos:BAABLgAECn8bAAIZAAgJ/RYCDgChAQAZAAgJ/RYCDgChAQAAAA==.',
Ms='Msadventure:BAAALgADCgMJAwAAAA==.',
Mu='Mujurro:BAAALgAECgEJAQAAAA==.Murney:BAAALgADCgcJBwAAAA==.Muzzledmage:BAEBLgAECn8gAAICAAgJ9xdjKAABAgACAAgJ9xdjKAABAgAAAA==.',
My='Myfirstlady:BAAALgADCgEJAQAAAA==.Myparse:BAABLgAECn8YAAIBAAkJGxo9OgBNAQABAAkJGxo9OgBNAQAAAA==.Mysticguru:BAABLgAECn8dAAIfAAcJYR3JFwD0AQAfAAcJYR3JFwD0AQAAAA==.',
['Mà']='Mànyen:BAAALgADCgcJDgAAAA==.',
Na='Nadiaa:BAAALgADCgMJAwAAAA==.Naisu:BAAALgAECgEJAQAAAA==.Nanibear:BAAALgAECgYJBgAAAA==.Narodaran:BAAALgAECgYJBwAAAA==.Natebrew:BAAALgAECgUJBQABLgAFFAQJBgABAMERAA==.Nattsume:BAAALgADCgcJBwAAAA==.Natural:BAABLgAECn8fAAQRAAgJZxsLBgDsAQARAAgJZxsLBgDsAQAOAAQJdQvaYwCTAAAPAAMJyRBdIQCTAAAAAA==.Naughtÿ:BAAALgAECgEJAQAAAA==.Nay:BAAALgAECgEJAQABLgAFFAUJDQAfAIkXAA==.',
Ne='Neco:BAAALgAECgQJCwAAAA==.Necropete:BAABLgAECn8bAAIVAAgJQhnRNACmAQAVAAgJQhnRNACmAQAAAA==.Nerudian:BAAALgADCgMJAwAAAA==.Nevets:BAABLgAECn8qAAMoAAcJUh+PAwAcAgAoAAcJUh+PAwAcAgAkAAUJiA+PHQAAAQAAAA==.Nevrs:BAAALgAECgUJDQAAAA==.',
Ni='Nickkshield:BAAALgADCgYJBgAAAA==.Nimit:BAABLgAECn8iAAMcAAgJyB4AFQAnAgAcAAgJ4B0AFQAnAgAkAAUJKRYvGwAhAQAAAA==.Nipha:BAAALgAECgMJBQAAAA==.',
No='Noct:BAAALgAECgMJBAAAAA==.Nofoxgivn:BAAALgAECgIJAgABLgAFFAQJCAAEAHIFAA==.Nogreencardx:BAAALgAECgUJCgAAAA==.Nooblez:BAAALgADCgYJBgAAAA==.Notsenka:BAABLgAECn8eAAIXAAcJjgknGABDAQAXAAcJjgknGABDAQAAAA==.Notzee:BAAALgADCgQJBwAAAA==.Novic:BAABLgAECn8mAAIGAAgJ5BoWEwBHAgAGAAgJ5BoWEwBHAgAAAA==.Noxinox:BAAALgADCgYJBgAAAA==.',
Nu='Nualia:BAABLgAECn8fAAIEAAgJxBoPGgAtAgAEAAgJxBoPGgAtAgAAAA==.Nulg:BAAALgADCgIJAgAAAA==.',
Ny='Nyssathasong:BAAALgAECgcJDwAAAA==.',
['Nä']='Nägash:BAAALgAECgMJBgAAAA==.',
Oa='Oathkeeper:BAAALgAECgUJDAAAAA==.',
Oj='Ojaks:BAAALgAECgMJAwAAAA==.',
Om='Omatiaa:BAACLgAFFH8IAAITAAMJdgoIHADPAAATAAMJdgoIHADPAAAuAAQKfysAAhMACAnkHREVAHUCABMACAnkHREVAHUCAAAA.',
Oo='Oongawa:BAAALgAFFAEJAQAAAA==.',
Or='Oraxus:BAAALgAECgEJAQAAAA==.Oreface:BAAALgAECgEJAQAAAA==.Orobus:BAABLgAECn8tAAIYAAkJ6SSXAABQAwAYAAkJ6SSXAABQAwAAAA==.',
Os='Oscassey:BAABLgAECn8jAAIlAAgJqQhIBwBuAQAlAAgJqQhIBwBuAQAAAA==.',
Ox='Oxley:BAABLgAECn8lAAIRAAgJ/hxOAwBYAgARAAgJ/hxOAwBYAgAAAA==.',
Pa='Pacifica:BAAALgAECgMJAwAAAA==.Paladingus:BAAALgAECggJEQAAAA==.Pallumx:BAAALgAECgEJAQAAAA==.Palmer:BAAALgADCgYJBgAAAA==.Pandidin:BAABLgAECn8UAAMdAAgJ2w5aGABiAQAdAAcJhxBaGABiAQAgAAgJ+gewPwCZAAAAAA==.Pastasaladin:BAAALgAECgEJAgAAAA==.Paulblart:BAAALgAECgcJBwAAAA==.Pauldrons:BAACLgAFFH8IAAIVAAIJEgSyhACIAAAVAAIJEgSyhACIAAAuAAQKf0QAAhUACAkUFPM8AIcBABUACAkUFPM8AIcBAAAA.',
Pe='Peenar:BAABLgAECn8VAAIkAAkJBx4pBADaAgAkAAkJBx4pBADaAgAAAA==.Peepeemcgee:BAAALgAECgQJBAABLgAECgkJJQABAFUiAA==.',
Ph='Pharlock:BAABLgAECn8VAAIhAAYJ8xbMTABDAQAhAAYJ8xbMTABDAQAAAA==.Pharlòck:BAAALgADCgEJAQABLgAECgYJFQAhAPMWAA==.Phlebite:BAAALgAECgYJDwAAAA==.Phobia:BAAALgADCgkJCQABLgAECgkJIgAYAO8TAA==.',
Pi='Pichurri:BAAALgAECgUJDwAAAA==.Pigpen:BAAALgAECgQJCwAAAA==.Pilk:BAAALgADCgUJBwAAAA==.Pineapplexp:BAAALgADCggJBwAAAA==.',
Pk='Pk:BAABLgAECn84AAIpAAkJfiJAAAAqAwApAAkJfiJAAAAqAwAAAA==.',
Pl='Plank:BAAALgADCgcJBwAAAA==.Planky:BAAALgADCggJEAAAAA==.',
Po='Pooterdiddle:BAAALgADCgUJBQAAAA==.Popsaheal:BAEALgAECgcJBwABLgAFFAQJCwAOAIMXAA==.Porunga:BAAALgAECggJCAAAAA==.Poshinek:BAAALgAECgUJDgAAAA==.',
Pr='Predobear:BAAALgAECgYJDwAAAA==.Prohealin:BAABLgAECn8lAAIGAAgJaRxEBwCAAgAGAAgJaRxEBwCAAgAAAA==.Protojack:BAAALgAECgQJBAABLgAFFAYJDwAHAJYdAA==.Pryx:BAAALgAECgcJBgAAAA==.',
Ps='Psychosís:BAAALgAECgIJBQAAAA==.',
Pu='Pumpkinq:BAACLgAFFH8LAAIXAAMJKiB4EAAgAQAXAAMJKiB4EAAgAQAuAAQKfy4AAhcACAmlIxMGADADABcACAmlIxMGADADAAAA.Purin:BAABLgAECn8mAAMiAAkJ1CE7AAAdAwAiAAgJ1CE7AAAdAwASAAIJnA4zRACkAAAAAA==.',
Pw='Pwnzorus:BAAALgAECgEJAwAAAA==.',
['Pì']='Pìkachu:BAABLgAECn8mAAICAAkJTxmGHgAzAgACAAkJTxmGHgAzAgAAAA==.',
Ra='Radon:BAAALgAECgUJBgAAAA==.Raekwon:BAAALgAECgYJCwAAAA==.Rainer:BAAALgADCgEJAQAAAA==.Ramzita:BAAALgAECgYJDAAAAA==.Ran:BAAALgAECgUJBQABLgAFFAQJCAALAAEXAA==.Randic:BAAALgAECgYJBgAAAA==.Raptok:BAACLgAFFH8GAAIfAAMJixPbHQDrAAAfAAMJixPbHQDrAAAuAAQKfyEAAx8ABwnvGZ8XAPUBAB8ABwnvGZ8XAPUBABMAAwmLCqxFAJEAAAAA.Rasmus:BAABLgAECn8mAAIeAAkJ0hgNBQApAgAeAAkJ0hgNBQApAgAAAA==.Raykwan:BAAALgAECgYJEQAAAA==.Raynar:BAAALgAECgIJAgAAAA==.Rayquaza:BAABLgAECn8iAAILAAkJDiOvAAB+AwALAAkJDiOvAAB+AwAAAA==.Razmatazz:BAABLgAECn8kAAMIAAgJvhjWCwAOAgAIAAgJvhjWCwAOAgAJAAMJdxfnLgChAAAAAA==.',
Re='Reddeyes:BAABLgAECn8VAAMIAAYJ9gmzMgDYAAAJAAUJDQpFJwDnAAAIAAYJnQezMgDYAAAAAA==.Reignleif:BAAALgADCgMJAwAAAA==.Rektalhammer:BAABLgAECn8UAAIEAAgJFxAQWABBAQAEAAgJFxAQWABBAQAAAA==.Rescue:BAABLgAECn8fAAICAAkJ3xdyTQBOAgACAAkJ3xdyTQBOAgAAAA==.Reukha:BAAALgAECgUJCQAAAA==.Rev:BAAALgADCgUJBQABLgAECggJBwADAAAAAA==.',
Rh='Rhavik:BAAALgADCgcJCgAAAA==.',
Ri='Rickrollins:BAABLgAECn8eAAIdAAgJgiQBBACvAgAdAAgJgiQBBACvAgAAAA==.Rimreaper:BAAALgADCgYJEgAAAA==.Rinedara:BAAALgADCgMJAwAAAA==.',
Ro='Roachmonger:BAABLgAECn8VAAMgAAcJvRfiNgBwAQAgAAcJvRfiNgBwAQAdAAEJwRFvewA1AAAAAA==.Roasted:BAABLgAECn8bAAICAAgJ0BobJgAMAgACAAgJ0BobJgAMAgAAAA==.Robotodh:BAAALgAECgEJAQAAAA==.Rockma:BAABLgAECn8iAAITAAkJuRBBKQDLAQATAAkJuRBBKQDLAQAAAA==.Rockyroad:BAAALgADCgQJBAAAAA==.Rollandburn:BAABLgAECn8eAAIcAAgJ/xoZFwAWAgAcAAgJ/xoZFwAWAgAAAA==.Rondó:BAABLgAECn8XAAMEAAcJxBQwjwBdAQAEAAcJYxAwjwBdAQAeAAQJ+RABKADJAAAAAA==.Rosao:BAAALgAECgEJAQAAAA==.Rotblack:BAAALgAFFAIJAgABLgAFFAMJBgAdAHUgAA==.Rotrogue:BAAALgADCgYJBgAAAA==.Rougerhaegar:BAAALgAECgYJCQAAAA==.Rozdomu:BAAALgAECgYJBgAAAA==.',
Ru='Ruff:BAAALgAECgEJAgAAAA==.Rufföaddy:BAABLgAECn8mAAIHAAkJkh8TBQDcAgAHAAkJkh8TBQDcAgAAAA==.Runeesa:BAAALgAECgYJEAAAAA==.Rustaxe:BAAALgADCgEJAQAAAA==.',
Ry='Rylena:BAABLgAECn8fAAMcAAcJ6yK5EABOAgAcAAcJ6yK5EABOAgAoAAYJcxM9PABtAQAAAA==.Rylseekmc:BAAALgAECgEJAQABLgAECgQJCQADAAAAAA==.Ryuke:BAAALgAFFAEJAQAAAA==.Ryvalry:BAAALgAECgcJDAAAAA==.Ryzzhorn:BAABLgAECn8bAAMcAAgJ4wcJQABOAQAcAAgJ4wcJQABOAQAoAAUJuQELbACOAAAAAA==.',
Rz='Rza:BAAALgADCgUJBQAAAA==.',
['Rà']='Ràvenn:BAAALgAECgYJEwAAAA==.',
['Râ']='Râmên:BAAALgAECgQJBQAAAA==.',
['Rí']='Ríchter:BAABLgAECn8fAAIBAAkJXhmIDgBUAgABAAkJXhmIDgBUAgAAAA==.',
Sa='Sagikos:BAECLgAFFH8LAAIOAAQJgxdSGAAOAQAOAAQJgxdSGAAOAQAuAAQKfy4AAw4ACAlJIW0KAO8CAA4ACAlJIW0KAO8CABAACAmqFj4PANwBAAAA.Sagua:BAAALgAECgcJBQAAAA==.Saintvader:BAAALgADCgcJCgAAAA==.Saki:BAAALgAECgYJEgAAAA==.Sammiches:BAAALgADCgcJBwAAAA==.Sanstormrage:BAAALgAECgUJEAABLgAECggJCAADAAAAAA==.Sapporo:BAAALgAECgEJAQAAAA==.Sardras:BAABLgAECn8mAAIOAAkJ8COaAQCGAwAOAAkJ8COaAQCGAwAAAA==.Sark:BAABLgAECn8UAAIVAAgJ+ANFqAAxAQAVAAgJ+ANFqAAxAQAAAA==.Sathor:BAAALgAECgkJEAAAAA==.Saucyjenkins:BAAALgAECgYJDwAAAA==.',
Sc='Scranton:BAAALgADCgEJAQAAAA==.',
Se='Sedgwin:BAAALgADCgIJAgAAAA==.Segundus:BAAALgADCgEJAQAAAA==.Sellout:BAAALgAECgcJDAAAAA==.Semprefi:BAAALgADCgYJBwAAAA==.Seph:BAAALgADCgMJAwAAAA==.Sepharion:BAAALgADCgcJBwABLgAFFAMJBwAiANodAA==.Seraphymn:BAAALgAECgQJBAAAAA==.Serenitree:BAAALgADCgMJAwAAAA==.',
Sg='Sgrios:BAAALgADCggJCQABLgAFFAMJCAATAHYKAA==.',
Sh='Shaani:BAABLgAECn8XAAIdAAcJZBjsFACGAQAdAAcJZBjsFACGAQAAAA==.Shadydh:BAAALgADCggJFQAAAA==.Shammehh:BAAALgADCgEJAQABLgAECgcJIAAIAHEaAA==.Shammooz:BAABLgAECn8jAAITAAgJrwsVHwBVAQATAAgJrwsVHwBVAQAAAA==.Sharkimon:BAAALgADCgEJAQAAAA==.Shaylyn:BAAALgAECgUJCQABLgAFFAMJCAATAM8QAA==.Sheefu:BAAALgADCgkJCwAAAA==.Shinier:BAAALgAECgQJBAAAAA==.Shockersz:BAAALgAECgIJAwAAAA==.Shockwoods:BAAALgAECgQJCAABLgAFFAMJBwAHAFIZAA==.Shondo:BAABLgAECn8oAAQXAAgJriTBBQBcAgAXAAcJhSXBBQBcAgApAAYJ0xwRBACpAQAlAAMJhB1oEQDyAAAAAA==.Shuvi:BAAALgADCgQJBAAAAA==.Shysti:BAAALgAECgEJAQAAAA==.',
Si='Sidhell:BAAALgADCgIJAgABLgAECggJHgAcAMMWAA==.Sigur:BAAALgADCgQJBAAAAA==.Silverin:BAAALgADCgYJBgAAAA==.Silversmage:BAAALgAECgUJAwAAAA==.Silvertraps:BAAALgADCgYJBgAAAA==.Sinthus:BAABLgAECn8UAAICAAcJnAlNxQBcAQACAAcJnAlNxQBcAQAAAA==.',
Sk='Skelatel:BAAALgADCgIJAgAAAA==.Skinard:BAAALgADCgcJEgAAAA==.',
Sl='Slappywappy:BAABLgAECn8eAAICAAcJYh3rRwCPAQACAAcJYh3rRwCPAQAAAA==.Slutho:BAAALgAECgQJBgABLgAFFAQJDQAYAPAbAA==.',
Sm='Smashing:BAAALgADCgEJAQAAAA==.Smegghead:BAAALgADCgcJDgAAAA==.Smhitehapens:BAAALgAECgQJCQAAAA==.',
Sn='Sneekybeef:BAAALgAECgUJBAAAAA==.Snekk:BAABLgAECn8aAAMLAAgJ0h34BABVAgALAAgJ0h34BABVAgAIAAEJSAmZYwAvAAAAAA==.Snooks:BAABLgAECn8jAAINAAkJChOdDQARAgANAAkJChOdDQARAgAAAA==.Snowen:BAAALgAECgMJAwABLgAECggJFQAGACcaAA==.',
So='Solegir:BAAALgADCgUJBQABLgAECgcJCwADAAAAAA==.Somthinlight:BAAALgAECgIJAgABLgAFFAQJCAALAAEXAA==.Songas:BAAALgADCgYJBgAAAA==.Sonroku:BAAALgAECgMJAwAAAA==.Soundwaves:BAAALgAECgUJBQAAAA==.Soziin:BAAALgAECgMJAwAAAA==.',
Sp='Spellnchill:BAAALgAECgYJEwAAAA==.Spharai:BAAALgADCgMJAwAAAA==.Spintor:BAABLgAECn8WAAMKAAYJSxbhHwA+AQAKAAYJSxbhHwA+AQAGAAEJHwmUgwAtAAAAAA==.Spookypaloza:BAAALgAECgcJBgAAAA==.Spookyy:BAAALgAECgEJAQAAAA==.',
Sq='Squidseye:BAAALgAECgQJBQAAAA==.',
St='Stainn:BAAALgAECgQJBAAAAA==.Stayyfrostyy:BAACLgAFFH8FAAICAAIJEhs+WAC2AAACAAIJEhs+WAC2AAAuAAQKfxcAAgIACAm8INEPAJwCAAIACAm8INEPAJwCAAAA.Sting:BAAALgAECgEJAQAAAA==.Stinkyhippie:BAAALgADCggJCAAAAA==.Stricker:BAABLgAECn8UAAIOAAYJsh3iGAD+AQAOAAYJsh3iGAD+AQAAAA==.Strickerz:BAABLgAECn8UAAIaAAcJHR6SLwAPAQAaAAcJHR6SLwAPAQAAAA==.Strongwoman:BAAALgAECgUJEgAAAA==.',
Su='Sucrose:BAAALgAECgcJEwAAAA==.Sui:BAAALgADCgQJBAAAAA==.Sunshine:BAAALgADCgEJAQAAAA==.Supernovaz:BAAALgAECgYJEgAAAA==.',
Sw='Swampygooch:BAAALgAECgEJAQABLgAECgUJCwADAAAAAA==.',
Sy='Symmas:BAAALgADCgMJAwAAAA==.Synterra:BAABLgAECn8aAAICAAYJAhGwZwBCAQACAAYJAhGwZwBCAQAAAA==.Syphian:BAAALgAECgEJAgAAAA==.Syrenda:BAAALgADCgcJDwAAAA==.Syymmaass:BAAALgAECgUJBgAAAA==.',
Ta='Taishigi:BAABLgAECn8tAAIhAAgJ1hByLQCuAQAhAAgJ1hByLQCuAQAAAA==.Talarian:BAAALgADCgQJBAAAAA==.Tapewyrm:BAABLgAECn8hAAIhAAgJDxYEIgDmAQAhAAgJDxYEIgDmAQAAAA==.Tastylicks:BAAALgADCgYJBgAAAA==.',
Te='Techz:BAAALgADCgQJBAAAAA==.Teckni:BAACLgAFFH8IAAMaAAQJUwb8FAAJAQAaAAQJUwb8FAAJAQAbAAIJxgS7EwCHAAAuAAQKfx0AAhoACAlKGsMfAFMCABoACAlKGsMfAFMCAAAA.Teedge:BAABLgAECn8gAAMIAAcJcRq7GgD0AQAIAAcJcRq7GgD0AQAJAAQJLA9FKQDVAAAAAA==.Teejadin:BAAALgADCgEJAQABLgAECgcJIAAIAHEaAA==.Telluride:BAABLgAECn8ZAAMGAAgJfg7QHwBKAQAGAAgJfg7QHwBKAQAMAAEJqwKWTwAgAAAAAA==.Terraphy:BAAALgAECgMJAwAAAA==.Testtubegub:BAAALgAECgcJCgAAAA==.',
Th='Tharagis:BAABLgAECn8XAAIRAAYJ6Q9cDwAiAQARAAYJ6Q9cDwAiAQAAAA==.Thecanadìan:BAAALgADCgUJBQAAAA==.Thehallowed:BAAALgADCgkJGwAAAA==.Theophrastus:BAAALgAECgEJAgAAAA==.Thepromise:BAABLgAECn8gAAIEAAkJSQzWMQC1AQAEAAkJSQzWMQC1AQAAAA==.Thewai:BAABLgAECn8lAAIQAAkJuBOmCgAgAgAQAAkJuBOmCgAgAgAAAA==.Thralia:BAAALgADCggJBgAAAA==.',
Ti='Timberlord:BAAALgAECgUJBAAAAA==.Timmytwotoes:BAAALgADCgEJAQAAAA==.',
To='Toovok:BAAALgADCgcJHAAAAA==.Totemtartt:BAAALgAECgEJAQAAAA==.Toxcinerate:BAAALgAECgQJBAABLgAECggJHAAgAEgNAA==.Toxicai:BAABLgAECn8cAAIgAAgJSA3tHABMAQAgAAgJSA3tHABMAQAAAA==.Toxicvoid:BAAALgADCgcJBwABLgAECggJHAAgAEgNAA==.',
Tr='Trakeus:BAACLgAFFH8GAAIBAAQJwRHlMgDlAAABAAQJwRHlMgDlAAAuAAQKfyIAAgEACAkZH1IfAJUCAAEACAkZH1IfAJUCAAAA.Trinitree:BAABLgAECn8dAAIHAAgJthPTGwCqAQAHAAgJthPTGwCqAQAAAA==.Trinkler:BAABLgAECn8UAAICAAYJJBoBVABvAQACAAYJJBoBVABvAQAAAA==.Trinklr:BAAALgAECgEJAgABLgAECgYJFAACACQaAA==.Tryhard:BAABLgAECn8ZAAQpAAYJsBrUCAD2AAAXAAYJsBrOLQCTAQApAAQJHhLUCAD2AAAlAAEJ4hQ+GABAAAABLgAECggJBwADAAAAAA==.Trée:BAAALgADCgkJEAABLgAECgQJBAADAAAAAA==.',
Tu='Tunka:BAAALgAECgUJCAAAAA==.Tuulikki:BAAALgADCgYJBgAAAA==.',
Tw='Twist:BAABLgAECn8eAAICAAcJ6xPsRgCSAQACAAcJ6xPsRgCSAQAAAA==.',
Ty='Tychondris:BAABLgAECn8kAAIcAAkJfgqKOABrAQAcAAkJfgqKOABrAQAAAA==.Typobad:BAAALgAECgkJCAAAAA==.Typoblink:BAAALgAECgkJAQAAAA==.',
Ug='Ugrikester:BAAALgAECgEJAQAAAA==.',
Ul='Ulsoga:BAABLgAECn8hAAIiAAgJOhKaAwC/AQAiAAgJOhKaAwC/AQAAAA==.',
Un='Unavailidan:BAAALgAECgUJEAAAAA==.Unhòly:BAAALgAECgYJDQAAAA==.',
Ur='Urpalnanners:BAAALgAECgMJAwAAAA==.',
Va='Valenira:BAAALgAECgcJBwAAAA==.Valkana:BAAALgAECgUJDwAAAA==.Vanicy:BAAALgAECgYJCgAAAA==.Vanite:BAAALgAECgQJBAAAAA==.Vanitus:BAAALgAECgMJAwAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varibash:BAABLgAECn8iAAIYAAkJ7xMrCQDjAQAYAAkJ7xMrCQDjAQAAAA==.Vaspara:BAABLgAECn8pAAIHAAkJgCGPAwADAwAHAAkJgCGPAwADAwAAAA==.',
Ve='Vedestril:BAAALgAECgEJAQAAAA==.Veggiemite:BAAALgADCgYJBgAAAA==.Veggiesticks:BAAALgADCgYJDAAAAA==.Velyndra:BAAALgAECgcJEQAAAA==.Vendarius:BAAALgADCgMJAwAAAA==.Vere:BAABLgAECn8kAAIUAAkJmyEAAQDuAgAUAAkJmyEAAQDuAgAAAA==.Vestarin:BAAALgAECgcJDwAAAA==.',
Vi='Vicromano:BAAALgADCgMJAwAAAA==.Vilified:BAABLgAECn8WAAIEAAgJQSQHDwCFAgAEAAgJQSQHDwCFAgAAAA==.Vinoamante:BAAALgADCgEJAQAAAA==.Visark:BAAALgADCgYJCwAAAA==.',
Vo='Voidlìlíth:BAABLgAECn8pAAICAAgJWx3qKgD2AQACAAgJWx3qKgD2AQAAAA==.Voidwak:BAAALgAECgYJDwAAAA==.Voidx:BAAALgAECgMJAwAAAA==.Volcarona:BAAALgADCgcJDQAAAA==.Voronir:BAABLgAECn8kAAIOAAgJqRtuDQB3AgAOAAgJqRtuDQB3AgAAAA==.Vospox:BAAALgAECgcJBwAAAA==.',
Vu='Vulcan:BAAALgAECgYJCwAAAA==.',
Vy='Vyndra:BAAALgADCgIJAgAAAA==.',
['Vä']='Väder:BAAALgADCgEJAQAAAA==.',
Wa='Warbloom:BAAALgAECgYJBgAAAA==.Wardbirdname:BAAALgADCgYJBgAAAA==.Wardo:BAACLgAFFH8YAAMhAAYJrxkGCQCpAQAhAAYJrRkGCQCpAQASAAQJYhQLBABUAQAuAAQKfzMAAxIACAm7ItQBAP8CABIACAnRIdQBAP8CACEABQkZJFgaABICAAAA.Warplank:BAAALgAECgcJEgAAAA==.Watchmeown:BAAALgAECgEJAQAAAA==.Wawwior:BAAALgAECgUJBwAAAA==.',
We='Welders:BAAALgAECgcJAQABLgAECggJHAAfALogAA==.Weleronys:BAAALgAECgYJEAAAAA==.Wellen:BAABLgAECn8eAAIcAAgJwxYjHQDtAQAcAAgJwxYjHQDtAQAAAA==.Werewolf:BAAALgAECgQJCgAAAA==.',
Wh='Whelplayed:BAABLgAECn8fAAQIAAYJiB3NGQBwAQAIAAYJTBvNGQBwAQAJAAQJLhwwCgD7AAALAAQJcRC9MgDZAAAAAA==.Whitemaine:BAAALgAECgcJDQAAAA==.Whitemist:BAAALgADCgcJDQAAAA==.Whitepikmin:BAABLgAECn8iAAQPAAkJaRyHCAAjAgAPAAgJKBuHCAAjAgARAAIJjg02KwBtAAAOAAEJlwNxqQAiAAAAAA==.Whizzleton:BAAALgADCgMJAwAAAA==.',
Wi='Wilmer:BAACLgAFFH8FAAIcAAMJOCLTHAAnAQAcAAMJOCLTHAAnAQAuAAQKfyYAAhwACAm3Hg4SAKcCABwACAm3Hg4SAKcCAAAA.Windowsvista:BAAALgAECgUJBAAAAA==.Wissa:BAAALgAECgYJDQAAAA==.Wiznasty:BAAALgADCgcJDQAAAA==.Wizylove:BAAALgADCgYJCQAAAA==.',
Wo='Wonrei:BAAALgADCgIJAgAAAA==.Woo:BAAALgAECgEJAQAAAA==.',
Wr='Wravc:BAAALgAECgkJIQAAAQ==.Wravient:BAAALgADCgQJBAABLgAECgkJIQADAAAAAQ==.',
Ww='Wwotw:BAAALgADCgcJBwAAAA==.',
Xa='Xanniheals:BAAALgAECgUJBQAAAA==.Xapphire:BAAALgADCgMJAgAAAA==.Xaspen:BAAALgAECgYJCgAAAA==.',
Xm='Xmysticxz:BAAALgADCgYJBgAAAA==.',
Xo='Xoyan:BAAALgAECgMJAwAAAA==.',
Ya='Yahs:BAAALgADCggJCAAAAA==.Yargonz:BAAALgAECgYJEQAAAA==.Yargzdk:BAACLgAFFH8aAAIFAAYJ6RDiBgBfAQAFAAYJ6RDiBgBfAQAuAAQKfzgAAgUACAnHHdMJAH8CAAUACAnHHdMJAH8CAAAA.Yargzvoker:BAAALgADCgcJDQAAAA==.Yatyas:BAAALgADCgEJAQAAAA==.',
Ye='Yeah:BAAALgAECggJCQAAAA==.Yeyin:BAAALgAECgUJDQAAAA==.Yeyol:BAABLgAECn8aAAMXAAgJihq/BgBDAgAXAAgJihq/BgBDAgAlAAMJ3QOWFwB7AAAAAA==.',
Yi='Yitpoo:BAAALgAECgUJDQAAAA==.',
Yo='Yokubo:BAABLgAECn8fAAIhAAgJAxY7MwCXAQAhAAgJAxY7MwCXAQAAAA==.Yolius:BAAALgAECgYJDgAAAA==.Yoogi:BAAALgAECggJDgAAAA==.Youngbullet:BAAALgADCgUJBQAAAA==.Yoyex:BAAALgAECgUJBgABLgAECgYJBgADAAAAAA==.',
Yu='Yunikon:BAAALgAECgQJCgABLgAECgkJJQABAFUiAA==.',
Ze='Zellus:BAABLgAECn8gAAIOAAkJSCLMBQD5AgAOAAkJSCLMBQD5AgAAAA==.Zelluss:BAAALgAECgEJAQABLgAECgkJIAAOAEgiAA==.Zelrin:BAAALgADCgIJAgAAAA==.Zendorta:BAAALgAECgEJAQAAAA==.Zensei:BAAALgAECgIJAgABLgAECgYJBgADAAAAAA==.Zensix:BAABLgAECn8bAAINAAgJsB6rBgCVAgANAAgJsB6rBgCVAgAAAA==.',
Zh='Zhaphiria:BAABLgAECn8VAAMLAAcJ+ROzDwBEAQALAAUJehazDwBEAQAIAAMJARz8LAD1AAABLgAFFAYJDQALAGcWAA==.Zhul:BAAALgAECgcJEgABLgAECggJEQADAAAAAA==.',
Zi='Zimmy:BAAALgADCgEJAQAAAA==.',
Zo='Zoku:BAAALgADCgIJAgAAAA==.',
Zu='Zugmà:BAABLgAECn8kAAIXAAgJ/wuyEACdAQAXAAgJ/wuyEACdAQAAAA==.Zukzug:BAAALgAECgUJCwAAAA==.',
['Äl']='Älpha:BAAALgAECgQJBAAAAA==.',
['Åz']='Åzïmvashÿak:BAAALgADCgcJBwAAAA==.',
['Çh']='Çhrõmié:BAABLgAECn8lAAIeAAgJchKuCwCCAQAeAAgJchKuCwCCAQAAAA==.',
['Çr']='Çrønus:BAABLgAECn8YAAMEAAgJ0Q3VTgBZAQAEAAcJHxDVTgBZAQAHAAQJ3gO9TQBrAAAAAA==.',
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

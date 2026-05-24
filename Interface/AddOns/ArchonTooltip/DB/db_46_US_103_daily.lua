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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Balance','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Priest-Shadow','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-05-24',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH8fAAIBAAcJNyK3AABYAgdoDAAABgBdAGkMAAAFAGAAawwAAAUAXgBqDAAABQA/AGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk3IrcAAFgCB2gMAAAGAF0AaQwAAAUAYABrDAAABQBeAGoMAAAFAD8AbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8VAAMBAAkJGiULAQC3AwABAAkJGiULAQC3AwACAAEJNBq2JQBNAAAAAA==.',
Aj='Ajtwo:BAACLgAFFH8LAAIDAAQJGQwNFwAzAQRoDAAABAA1AGkMAAAEABIAawwAAAEAIQDqDAAAAgASAAMABAkZDA0XADMBBGgMAAAEADUAaQwAAAQAEgBrDAAAAQAhAOoMAAACABIALgAECn8mAAMDAAkJ2hY7EgDxAQADAAkJ2hY7EgDxAQAEAAMJsAS0GQBfAAAAAA==.',
Ak='Akanbe:BAABLgAECn83AAIFAAkJhh0QBgAAAwloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAFAAkJhh0QBgAAAwloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8oAAMGAAkJ2gqEJgBwAQloDAAABQAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAGAAkJ2gqEJgBwAQloDAAABAAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAFAAEJ5QEeXwAhAAFoDAAAAQAEAAAA.Anxious:BAACLgAFFH8NAAIHAAYJyRPVDACsAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAHAAYJyRPVDACsAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxsAAgcACAlsFqIqAJYBAAcACAlsFqIqAJYBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbetty:BAAALgAECgQJBQAAAA==.',
Be='Beefmissile:BAAALgAECgIJAgAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEAAAAA==.',
Bo='Bosephis:BAABLgAECn8fAAIIAAYJbxYPZABRAQZoDAAABwBBAGkMAAAGADwAawwAAAYANwBqDAAABAA+AGwMAAADACoA6gwAAAUAPwAIAAYJbxYPZABRAQZoDAAABwBBAGkMAAAGADwAawwAAAYANwBqDAAABAA+AGwMAAADACoA6gwAAAUAPwAAAA==.',
Bu='Bubsecute:BAABLgAECn8WAAQJAAkJUhfRDwDJAQloDAAAAwBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAHQDqDAAABgBMAG4MAAABAC0AbwwAAAEACgAJAAgJ+xjRDwDJAQhoDAAAAgBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEA6gwAAAEATABuDAAAAQAtAG8MAAABAAoACgADCZoLvm8AcAADaAwAAAEABABtDAAAAQAdAOoMAAAEADYACwABCcQbCkAATAAB6gwAAAEARwAAAA==.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgQJDAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJCQAAAA==.',
De='Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8VAAIMAAYJIQYcHACmAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAUAEQAMAAYJIQYcHACmAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAUAEQAAAA==.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAcABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumblebob:BAAALgADCgUJEQAAAA==.Dumbledoe:BAAALgADCgUJCgAAAA==.Dumbledor:BAAALgADCgYJEgAAAA==.Dumblehunt:BAAALgADCgUJDgAAAA==.Dumblepal:BAAALgADCgYJCQAAAA==.Dumblepow:BAAALgADCgYJCwAAAA==.Dumblesham:BAAALgADCgYJDAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAABLgAECn8VAAMNAAkJBxZaJQD9AQloDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYAbwwAAAEAXQANAAgJ9RNaJQD9AQhoDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYACAABCYMk09QAYQABbwwAAAEAXQAAAA==.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAOAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwAPAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJDwAQAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgADCgYJBgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAABLgAECn8rAAMRAAkJ0B4yCACxAgloDAAABgBOAGkMAAAGAEwAawwAAAcAXQBqDAAABQBQAGwMAAAFAFsAbQwAAAMAQADqDAAABwBXAG4MAAADAFUAbwwAAAEANQARAAkJ0B4yCACxAgloDAAAAwBOAGkMAAADAEwAawwAAAMAXQBqDAAAAwBQAGwMAAADAFsAbQwAAAMAQADqDAAABQBXAG4MAAADAFUAbwwAAAEANQASAAYJfRN3UgBdAQZoDAAAAwBHAGkMAAADACQAawwAAAQAOABqDAAAAgA5AGwMAAACACwA6gwAAAIAIQAAAA==.',
Fo='Fox:BAAALgAECgUJEAAAAA==.',
Fr='Frakattack:BAAALgADCgcJCAAAAA==.Frostlord:BAAALgAECgYJDAABLgAFFAEJAQAQAAAAAA==.Frymancer:BAAALgAECgUJEQAAAA==.',
Go='Goemon:BAAALgAECgIJAwAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAAALgAECgUJBgAAAA==.',
Hu='Hudemonized:BAAALgAECgcJDAAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.',
Ir='Ironfistt:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8KAAIBAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwABAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwAuAAQKfxYAAgEACAnhHh8LAK8CAAEACAnhHh8LAK8CAAAA.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBQAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgUJDQAAAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kayde:BAAALgAECggJCQAAAA==.',
Ke='Keisel:BAABLgAECn8aAAITAAgJ5xMhKgDoAQhoDAAABQBMAGkMAAAEAE0AawwAAAQALgBqDAAABQAYAGwMAAADADsAbQwAAAEAKgDqDAAAAwBCAG4MAAABAA0AEwAICecTISoA6AEIaAwAAAUATABpDAAABABNAGsMAAAEAC4AagwAAAUAGABsDAAAAwA7AG0MAAABACoA6gwAAAMAQgBuDAAAAQANAAAA.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgEJBAAAAA==.Kissmyheals:BAAALgAECgUJEAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Li='Lilbigterd:BAABLgAECn8xAAIUAAgJ+RydMQBcAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAKADqDAAABwBQAG4MAAAEAFcAFAAICfkcnTEAXAIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFACgA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJIQAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgAECgEJAQAAAA==.',
Ly='Lychee:BAAALgAECgcJDAAAAA==.',
Ma='Magilou:BAABLgAFFH8GAAIVAAYJGQOZTwAtAQZoDAAAAQAGAGkMAAABABMAawwAAAEAAwBqDAAAAQAIAGwMAAABAAMA6gwAAAEABwAVAAYJGQOZTwAtAQZoDAAAAQAGAGkMAAABABMAawwAAAEAAwBqDAAAAQAIAGwMAAABAAMA6gwAAAEABwAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIIAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoACAACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/GgADCAAICTYgORgAdwIACAAHCS4jORgAdwIADQAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAAALgAECgYJBwAAAA==.',
Md='Mdsnista:BAABLgAECn86AAIVAAkJ0RI0QQD/AQloDAAACAA2AGkMAAAHADkAawwAAAgALgBqDAAACAAnAGwMAAAHACoAbQwAAAMALADqDAAACQA7AG4MAAAFADsAbwwAAAMAEwAVAAkJ0RI0QQD/AQloDAAACAA2AGkMAAAHADkAawwAAAgALgBqDAAACAAnAGwMAAAHACoAbQwAAAMALADqDAAACQA7AG4MAAAFADsAbwwAAAMAEwAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIWAAgJNxFpUAB0AQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAIAIADqDAAABwAnAG4MAAACADkAFgAICTcRaVAAdAEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAACACAA6gwAAAcAJwBuDAAAAgA5AAAA.',
Ne='Nerox:BAAALgAECgYJBwAAAA==.Neryssa:BAABLgAECn8dAAIXAAYJxgVoHQDLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAXAAYJxgVoHQDLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAAQAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8jAAIXAAgJmgcwFAA7AQhoDAAABgAOAGkMAAAHABYAawwAAAYAEgBqDAAABAAPAGwMAAAGACQAbQwAAAEACgDqDAAAAwATAG4MAAACAA4AFwAICZoHMBQAOwEIaAwAAAYADgBpDAAABwAWAGsMAAAGABIAagwAAAQADwBsDAAABgAkAG0MAAABAAoA6gwAAAMAEwBuDAAAAgAOAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAAQAAAAAA==.Patience:BAAALgAECgcJDQAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8dAAISAAcJChnKJgD5AQdoDAAABQBNAGkMAAAFAEcAawwAAAUARwBqDAAABQAyAGwMAAACADsA6gwAAAYAPQBuDAAAAQA4ABIABwkKGcomAPkBB2gMAAAFAE0AaQwAAAUARwBrDAAABQBHAGoMAAAFADIAbAwAAAIAOwDqDAAABgA9AG4MAAABADgAAAA=.',
Qm='Qmen:BAABLgAECn8vAAMUAAkJ5BciQwDgAQloDAAABwA9AGkMAAAGAEgAawwAAAgASABqDAAABgAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABwBBAG4MAAAEADMAbwwAAAEAKAAUAAkJ5BciQwDgAQloDAAABwA9AGkMAAAGAEgAawwAAAcASABqDAAABgAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABwBBAG4MAAAEADMAbwwAAAEAKAAHAAEJ9gYchAAqAAFrDAAAAQARAAAA.',
Qt='Qtora:BAAALgAECgQJCAAAAA==.',
Qu='Queso:BAABLgAECn8nAAMFAAgJURhfGgDTAQhoDAAABgBHAGkMAAAFAEcAawwAAAUAVABqDAAABgA8AGwMAAAFAD4AbQwAAAQAFgDqDAAABgAxAG4MAAACAEsABQAICVEYXxoA0wEIaAwAAAUARwBpDAAABQBHAGsMAAAFAFQAagwAAAQAPABsDAAABQA+AG0MAAAEABYA6gwAAAUAMQBuDAAAAgBLAAYAAwmVBphsAHcAA2gMAAABAAMAagwAAAIALgDqDAAAAQABAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgYJCgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAABLgAECn81AAIIAAkJjyGMDwCuAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAIAAkJjyGMDwCuAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgEJAQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgAECgUJBQAAAA==.Semtéc:BAAALgAECgEJAQAAAA==.Sephîroth:BAAALgAECgYJCQAAAA==.',
Sh='Shadont:BAABLgAECn8WAAIYAAgJ2BOaLQByAQhoDAAAAwAzAGkMAAADADsAawwAAAMAOgBqDAAAAgAOAGwMAAADAEsAbQwAAAIAGQDqDAAABAAxAG4MAAACACIAGAAICdgTmi0AcgEIaAwAAAMAMwBpDAAAAwA7AGsMAAADADoAagwAAAIADgBsDAAAAwBLAG0MAAACABkA6gwAAAQAMQBuDAAAAgAiAAAA.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8iAAMZAAcJeg9NNwAvAQdoDAAABwAaAGkMAAAHAB4AawwAAAgAFgBqDAAABAAWAGwMAAACAC4A6gwAAAUAGQBuDAAAAQBVABkABwl6D003AC8BB2gMAAADABoAaQwAAAMAHgBrDAAAAwAWAGoMAAABABYAbAwAAAIALgDqDAAAAQAZAG4MAAABAFUAEwAFCRkOSmkA6wAFaAwAAAQAJABpDAAABAAwAGsMAAAFADUAagwAAAMAGgDqDAAABAAPAAAA.',
Si='Sinhfyre:BAABLgAECn8bAAMaAAYJHgNRGgBeAAZoDAAABQAFAGkMAAAFABAAawwAAAYABwBqDAAAAwASAGwMAAADAAYA6gwAAAUABAAbAAYJXQJhYgCFAAZoDAAABAAFAGkMAAABAAcAawwAAAUABwBqDAAAAgAOAGwMAAACAAUA6gwAAAUABAAaAAUJegNRGgBeAAVoDAAAAQAFAGkMAAAEABAAawwAAAEABwBqDAAAAQASAGwMAAABAAYAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAIRAAgJMAbBPgDmAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAADABAAEQAICTAGwT4A5gAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAwAQAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMPAAkJ/h1yCgBxAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgAPAAgJhyByCgBxAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADgAJCXMT6ikAQgEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stillscruby:BAABLgAECn8cAAIDAAkJDg1PFQDRAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAEADQADAAkJDg1PFQDRAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAEADQAAAA==.',
Su='Sumting:BAAALgAECgQJBQAAAA==.',
['Sí']='Síntor:BAABLgAECn8uAAMUAAcJyhLnhQBFAQdoDAAACQA8AGkMAAAIAEcAawwAAAcAMwBqDAAABwAzAGwMAAAFABoA6gwAAAgANQBuDAAAAgAZABQABwnoEOeFAEUBB2gMAAAHACoAaQwAAAYARwBrDAAABQAzAGoMAAAGADMAbAwAAAIAGQDqDAAABgArAG4MAAACABkAHAAGCdASmBwABwEGaAwAAAIAPABpDAAAAgA7AGsMAAACACgAagwAAAEAEQBsDAAAAwAaAOoMAAACADUAAAA=.',
Te='Teach:BAAALgAECgUJEQAAAA==.Tenjii:BAAALgAECgQJBAABLgAECgUJCwAQAAAAAA==.Tensham:BAAALgAECgUJCwAAAA==.',
Th='Theimpaler:BAABLgAECn8YAAMJAAcJNQoeKQAAAQdoDAAABwAgAGkMAAAEACsAawwAAAMAFwBqDAAAAgAdAGwMAAACABQAbQwAAAEADwDqDAAABQAUAAkABwk1Ch4pAAABB2gMAAAGACAAaQwAAAQAKwBrDAAAAwAXAGoMAAACAB0AbAwAAAIAFABtDAAAAQAPAOoMAAAFABQACwABCZ8DJE8AHwABaAwAAAEACQABLgAFFAEJAQAQAAAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJDwAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIOAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AA4ABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIOAAgJ0CEQCgDXAgAOAAgJ0CEQCgDXAgAAAA==.Twiks:BAAALgAECgUJDQAAAA==.',
Ul='Uley:BAEALgAECgUJEQAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn8sAAIMAAkJjxtsAgBvAgloDAAABwBQAGkMAAAHAE8AawwAAAcAUgBqDAAABgA8AGwMAAAEAE0AbQwAAAMAHwDqDAAABgBYAG4MAAACADkAbwwAAAIAQwAMAAkJjxtsAgBvAgloDAAABwBQAGkMAAAHAE8AawwAAAcAUgBqDAAABgA8AGwMAAAEAE0AbQwAAAMAHwDqDAAABgBYAG4MAAACADkAbwwAAAIAQwAAAA==.',
Vo='Volker:BAABLgAECn8fAAILAAkJihCzGQBIAQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwALAAkJihCzGQBIAQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAAAA==.',
Wa='Waywa:BAAALgAECgQJBAAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwAQAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyDuBADNAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQABAAkJPyDuBADNAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQAAAA==.Xandûs:BAAALgAFFAIJAgAAAA==.',
Xe='Xeraza:BAAALgAFFAIJAgABLgAFFAQJDAAcAEsXAA==.Xerô:BAACLgAFFH8MAAIcAAQJSxdsAgDhAARoDAAABAA6AGkMAAADAEwAawwAAAIAIgDqDAAAAwBFABwABAlLF2wCAOEABGgMAAAEADoAaQwAAAMATABrDAAAAgAiAOoMAAADAEUALgAECn8sAAMcAAgJRB9ABgBdAgAcAAgJRB9ABgBdAgAUAAEJsBeQPQFHAAAAAA==.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECgcJEAAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAAALgAECgQJBQAAAA==.',
Zu='Zuf:BAACLgAFFH8TAAIRAAUJdCC4DgBxAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAFAFwAEQAFCXQguA4AcQEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABQBcAC4ABAp/MgADEQAJCTklqgEAVwMAEQAJCTklqgEAVwMAHQABCd8CJzkAJAAAAAA=.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

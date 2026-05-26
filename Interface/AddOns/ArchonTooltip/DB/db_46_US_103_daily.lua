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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Shaman-Elemental','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Balance','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-05-26',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH8fAAIBAAcJNyLkAABKAgdoDAAABgBdAGkMAAAFAGAAawwAAAUAXgBqDAAABQA/AGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk3IuQAAEoCB2gMAAAGAF0AaQwAAAUAYABrDAAABQBeAGoMAAAFAD8AbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8VAAMBAAkJGiULAQC3AwABAAkJGiULAQC3AwACAAEJNBqgJgBNAAAAAA==.',
Aj='Ajtwo:BAACLgAFFH8LAAIDAAQJGQzvFwAzAQRoDAAABAA1AGkMAAAEABIAawwAAAEAIQDqDAAAAgASAAMABAkZDO8XADMBBGgMAAAEADUAaQwAAAQAEgBrDAAAAQAhAOoMAAACABIALgAECn8mAAMDAAkJ2hbkEgDuAQADAAkJ2hbkEgDuAQAEAAMJsAS0GQBfAAAAAA==.',
Ak='Akanbe:BAABLgAECn83AAIFAAkJhh1DBgD+AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAFAAkJhh1DBgD+AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8oAAMGAAkJ2gpTJwBwAQloDAAABQAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAGAAkJ2gpTJwBwAQloDAAABAAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAFAAEJ5QEeXwAhAAFoDAAAAQAEAAAA.Anxious:BAACLgAFFH8NAAIHAAYJyRO8DQCsAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAHAAYJyRO8DQCsAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxsAAgcACAlsFowrAJYBAAcACAlsFowrAJYBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbetty:BAAALgAECgQJBQABLgAECgcJIgAIAHoPAA==.',
Be='Beefmissile:BAAALgAECgIJAgAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEAAAAA==.',
Bo='Bosephis:BAABLgAECn8fAAIJAAYJbxYdZwBRAQZoDAAABwBBAGkMAAAGADwAawwAAAYANwBqDAAABAA+AGwMAAADACoA6gwAAAUAPwAJAAYJbxYdZwBRAQZoDAAABwBBAGkMAAAGADwAawwAAAYANwBqDAAABAA+AGwMAAADACoA6gwAAAUAPwAAAA==.',
Bu='Bubsecute:BAABLgAECn8WAAQKAAkJUheuEADCAQloDAAAAwBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAHQDqDAAABgBMAG4MAAABAC0AbwwAAAEACgAKAAgJ+xiuEADCAQhoDAAAAgBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEA6gwAAAEATABuDAAAAQAtAG8MAAABAAoACwADCZoLJnIAcAADaAwAAAEABABtDAAAAQAdAOoMAAAEADYADAABCcQbdkEATAAB6gwAAAEARwAAAA==.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgQJDAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJCQAAAA==.',
De='Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8VAAINAAYJIQaxHACmAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAUAEQANAAYJIQaxHACmAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAUAEQAAAA==.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAcABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumblebob:BAAALgADCgUJEQAAAA==.Dumbledoe:BAAALgADCgUJDQAAAA==.Dumbledor:BAAALgADCgYJEgAAAA==.Dumblehunt:BAAALgADCgYJEAAAAA==.Dumblepal:BAAALgADCgYJCQAAAA==.Dumblepow:BAAALgADCgYJCwAAAA==.Dumblesham:BAAALgADCgYJDAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAABLgAECn8VAAMOAAkJBxZaJQD9AQloDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYAbwwAAAEAXQAOAAgJ9RNaJQD9AQhoDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYACQABCYMkUtoAYAABbwwAAAEAXQAAAA==.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAPAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwAQAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJDwARAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgADCgYJBgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAABLgAECn8rAAMSAAkJ0B5+CACxAgloDAAABgBOAGkMAAAGAEwAawwAAAcAXQBqDAAABQBQAGwMAAAFAFsAbQwAAAMAQADqDAAABwBXAG4MAAADAFUAbwwAAAEANQASAAkJ0B5+CACxAgloDAAAAwBOAGkMAAADAEwAawwAAAMAXQBqDAAAAwBQAGwMAAADAFsAbQwAAAMAQADqDAAABQBXAG4MAAADAFUAbwwAAAEANQATAAYJfRN3UgBdAQZoDAAAAwBHAGkMAAADACQAawwAAAQAOABqDAAAAgA5AGwMAAACACwA6gwAAAIAIQAAAA==.',
Fo='Fox:BAAALgAECgUJEAAAAA==.',
Fr='Frakattack:BAAALgADCgcJCAAAAA==.Frostlord:BAAALgAECgYJDAABLgAFFAEJAQARAAAAAA==.Frymancer:BAAALgAECgUJEQAAAA==.',
Go='Goemon:BAAALgAECgQJBQAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAAALgAECgYJCQAAAA==.',
Hu='Hudemonized:BAAALgAECgcJDAAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.',
Ir='Ironfistt:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8KAAIBAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwABAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwAuAAQKfxYAAgEACAnhHh8LAK8CAAEACAnhHh8LAK8CAAAA.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBQAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgUJDQAAAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kayde:BAAALgAECggJCQAAAA==.',
Ke='Keisel:BAABLgAECn8bAAMUAAgJ5xNSKwDoAQhoDAAABQBMAGkMAAAEAE0AawwAAAQALgBqDAAABQAYAGwMAAADADsAbQwAAAEAKgDqDAAAAwBCAG4MAAACAA0AFAAICecTUisA6AEIaAwAAAUATABpDAAABABNAGsMAAAEAC4AagwAAAUAGABsDAAAAwA7AG0MAAABACoA6gwAAAMAQgBuDAAAAQANAAgAAQm7B3GbACUAAW4MAAABABMAAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgEJBAAAAA==.Kissmyheals:BAAALgAECgUJEAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Li='Lilbigterd:BAABLgAECn8xAAIVAAgJ+RydMQBcAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAKADqDAAABwBQAG4MAAAEAFcAFQAICfkcnTEAXAIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFACgA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJIgAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgAECgMJAwAAAA==.Luxray:BAAALgAECgQJBAAAAA==.',
Ly='Lychee:BAAALgAECgcJDAAAAA==.',
Ma='Magilou:BAABLgAFFH8GAAIWAAYJGQMzUgAtAQZoDAAAAQAGAGkMAAABABMAawwAAAEAAwBqDAAAAQAIAGwMAAABAAMA6gwAAAEABwAWAAYJGQMzUgAtAQZoDAAAAQAGAGkMAAABABMAawwAAAEAAwBqDAAAAQAIAGwMAAABAAMA6gwAAAEABwAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIJAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoACQACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/HgADCQAICeUiORgAdwIACQAICeUiORgAdwIADgAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAAALgAECgYJBwAAAA==.',
Md='Mdsnista:BAABLgAECn86AAIWAAkJ0RLFQgD+AQloDAAACAA2AGkMAAAHADkAawwAAAgALgBqDAAACAAnAGwMAAAHACoAbQwAAAMALADqDAAACQA7AG4MAAAFADsAbwwAAAMAEwAWAAkJ0RLFQgD+AQloDAAACAA2AGkMAAAHADkAawwAAAgALgBqDAAACAAnAGwMAAAHACoAbQwAAAMALADqDAAACQA7AG4MAAAFADsAbwwAAAMAEwAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIXAAgJNxHUUQB0AQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAIAIADqDAAABwAnAG4MAAACADkAFwAICTcR1FEAdAEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAACACAA6gwAAAcAJwBuDAAAAgA5AAAA.',
Ne='Nerox:BAAALgAECgYJBwAAAA==.Neryssa:BAABLgAECn8dAAIYAAYJxgVzHgDLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAYAAYJxgVzHgDLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAARAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8mAAIYAAgJJQhXFABCAQhoDAAABwAYAGkMAAAIABYAawwAAAcAEgBqDAAABAAPAGwMAAAGACQAbQwAAAEACgDqDAAAAwATAG4MAAACAA4AGAAICSUIVxQAQgEIaAwAAAcAGABpDAAACAAWAGsMAAAHABIAagwAAAQADwBsDAAABgAkAG0MAAABAAoA6gwAAAMAEwBuDAAAAgAOAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAARAAAAAA==.Patience:BAAALgAECgcJDQAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8iAAITAAkJWRWyGgBTAgloDAAABQBNAGkMAAAGAEcAawwAAAUARwBqDAAABQAyAGwMAAADADsAbQwAAAEAGgDqDAAABgA9AG4MAAACADgAbwwAAAEAEQATAAkJWRWyGgBTAgloDAAABQBNAGkMAAAGAEcAawwAAAUARwBqDAAABQAyAGwMAAADADsAbQwAAAEAGgDqDAAABgA9AG4MAAACADgAbwwAAAEAEQAAAA==.',
Qm='Qmen:BAABLgAECn8vAAMVAAkJ5BcERQDgAQloDAAABwA9AGkMAAAGAEgAawwAAAgASABqDAAABgAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABwBBAG4MAAAEADMAbwwAAAEAKAAVAAkJ5BcERQDgAQloDAAABwA9AGkMAAAGAEgAawwAAAcASABqDAAABgAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABwBBAG4MAAAEADMAbwwAAAEAKAAHAAEJ9gZChgAqAAFrDAAAAQARAAAA.',
Qt='Qtora:BAAALgAECgQJCAAAAA==.',
Qu='Queso:BAABLgAECn8qAAMFAAgJURhyGwDMAQhoDAAABgBHAGkMAAAFAEcAawwAAAUAVABqDAAABgA8AGwMAAAGAD4AbQwAAAUAFgDqDAAABwAxAG4MAAACAEsABQAICVEYchsAzAEIaAwAAAUARwBpDAAABQBHAGsMAAAFAFQAagwAAAQAPABsDAAABgA+AG0MAAAFABYA6gwAAAYAMQBuDAAAAgBLAAYAAwmVBphsAHcAA2gMAAABAAMAagwAAAIALgDqDAAAAQABAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgcJDgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAABLgAECn81AAIJAAkJjyFuEACsAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAJAAkJjyFuEACsAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgUJBQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgAECgUJBQAAAA==.Semtéc:BAAALgAECgIJAgAAAA==.Sephîroth:BAAALgAECgYJCQAAAA==.',
Sh='Shadont:BAABLgAECn8WAAIZAAgJ2BOaLQByAQhoDAAAAwAzAGkMAAADADsAawwAAAMAOgBqDAAAAgAOAGwMAAADAEsAbQwAAAIAGQDqDAAABAAxAG4MAAACACIAGQAICdgTmi0AcgEIaAwAAAMAMwBpDAAAAwA7AGsMAAADADoAagwAAAIADgBsDAAAAwBLAG0MAAACABkA6gwAAAQAMQBuDAAAAgAiAAAA.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8iAAMIAAcJeg95OAAuAQdoDAAABwAaAGkMAAAHAB4AawwAAAgAFgBqDAAABAAWAGwMAAACAC4A6gwAAAUAGQBuDAAAAQBVAAgABwl6D3k4AC4BB2gMAAADABoAaQwAAAMAHgBrDAAAAwAWAGoMAAABABYAbAwAAAIALgDqDAAAAQAZAG4MAAABAFUAFAAFCRkOjWsA7AAFaAwAAAQAJABpDAAABAAwAGsMAAAFADUAagwAAAMAGgDqDAAABAAPAAAA.',
Si='Sinhfyre:BAABLgAECn8bAAMaAAYJHgPjGgBeAAZoDAAABQAFAGkMAAAFABAAawwAAAYABwBqDAAAAwASAGwMAAADAAYA6gwAAAUABAAbAAYJXQKvZACFAAZoDAAABAAFAGkMAAABAAcAawwAAAUABwBqDAAAAgAOAGwMAAACAAUA6gwAAAUABAAaAAUJegPjGgBeAAVoDAAAAQAFAGkMAAAEABAAawwAAAEABwBqDAAAAQASAGwMAAABAAYAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAISAAgJMAYgQADmAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAADABAAEgAICTAGIEAA5gAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAwAQAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMQAAkJ/h24CgBwAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgAQAAgJhyC4CgBwAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADwAJCXMTwioAQgEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stillscruby:BAABLgAECn8cAAIDAAkJDg0UFgDNAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAEADQADAAkJDg0UFgDNAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAEADQABLgAECgcJIgAIAHoPAA==.',
Su='Sumting:BAAALgAECgYJCAAAAA==.',
['Sí']='Síntor:BAABLgAECn8uAAMVAAcJyhL6iABFAQdoDAAACQA8AGkMAAAIAEcAawwAAAcAMwBqDAAABwAzAGwMAAAFABoA6gwAAAgANQBuDAAAAgAZABUABwnoEPqIAEUBB2gMAAAHACoAaQwAAAYARwBrDAAABQAzAGoMAAAGADMAbAwAAAIAGQDqDAAABgArAG4MAAACABkAHAAGCdASRR0ABwEGaAwAAAIAPABpDAAAAgA7AGsMAAACACgAagwAAAEAEQBsDAAAAwAaAOoMAAACADUAAAA=.',
Te='Teach:BAAALgAECgUJEQABLgAECgYJFAAEABMdAA==.Tenjii:BAAALgAECgQJBAABLgAECgUJCwARAAAAAA==.Tensham:BAAALgAECgUJCwAAAA==.',
Th='Theimpaler:BAABLgAECn8cAAMKAAcJOgzJJQAYAQdoDAAABwAgAGkMAAAEACsAawwAAAQANgBqDAAAAwAdAGwMAAAEABQAbQwAAAEADwDqDAAABQAUAAoABwk6DMklABgBB2gMAAAGACAAaQwAAAQAKwBrDAAABAA2AGoMAAADAB0AbAwAAAQAFABtDAAAAQAPAOoMAAAFABQADAABCZ8DJE8AHwABaAwAAAEACQABLgAFFAEJAQARAAAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJDwAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIPAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AA8ABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIPAAgJ0CEQCgDXAgAPAAgJ0CEQCgDXAgAAAA==.Twiks:BAAALgAECgUJDQAAAA==.',
Ul='Uley:BAEALgAECgUJEQAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn8sAAINAAkJjxuBAgBuAgloDAAABwBQAGkMAAAHAE8AawwAAAcAUgBqDAAABgA8AGwMAAAEAE0AbQwAAAMAHwDqDAAABgBYAG4MAAACADkAbwwAAAIAQwANAAkJjxuBAgBuAgloDAAABwBQAGkMAAAHAE8AawwAAAcAUgBqDAAABgA8AGwMAAAEAE0AbQwAAAMAHwDqDAAABgBYAG4MAAACADkAbwwAAAIAQwAAAA==.',
Vo='Volker:BAABLgAECn8fAAIMAAkJihBNGgBHAQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAMAAkJihBNGgBHAQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAAAA==.',
Wa='Waywa:BAAALgAECgQJBAAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwARAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyAvBQDMAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQABAAkJPyAvBQDMAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQAAAA==.Xandûs:BAAALgAFFAIJAgAAAA==.',
Xe='Xeraza:BAAALgAFFAIJAgABLgAFFAUJDQAcADMTAA==.Xerô:BAACLgAFFH8NAAIcAAUJMxMJBAA0AQVoDAAABAA6AGkMAAADAEwAawwAAAIAIgBsDAAAAQAHAOoMAAADAEUAHAAFCTMTCQQANAEFaAwAAAQAOgBpDAAAAwBMAGsMAAACACIAbAwAAAEABwDqDAAAAwBFAC4ABAp/LAADHAAICUQfggYAXAIAHAAICUQfggYAXAIAFQABCbAXzUQBRwAAAAA=.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECgcJEAAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAAALgAECgUJBgAAAA==.',
Zu='Zuf:BAACLgAFFH8TAAISAAUJdCCyDwBwAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAFAFwAEgAFCXQgsg8AcAEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABQBcAC4ABAp/MgADEgAJCTklyAEAVwMAEgAJCTklyAEAVwMAHQABCd8CJzkAJAAAAAA=.',
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

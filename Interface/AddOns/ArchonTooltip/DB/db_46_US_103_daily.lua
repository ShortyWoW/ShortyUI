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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Balance','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-05-30',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH8fAAIBAAcJNyIyAQA6AgdoDAAABgBdAGkMAAAFAGAAawwAAAUAXgBqDAAABQA/AGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk3IjIBADoCB2gMAAAGAF0AaQwAAAUAYABrDAAABQBeAGoMAAAFAD8AbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8WAAMBAAkJGiULAQC3AwABAAkJGiULAQC3AwACAAEJrB6kJQBYAAAAAA==.',
Aj='Ajtwo:BAACLgAFFH8PAAIDAAQJSQ0jGQAwAQRoDAAABQA1AGkMAAAFABgAawwAAAIAIQDqDAAAAwAZAAMABAlJDSMZADABBGgMAAAFADUAaQwAAAUAGABrDAAAAgAhAOoMAAADABkALgAECn8mAAMDAAkJ2hYHFADpAQADAAkJ2hYHFADpAQAEAAMJsAS0GQBfAAAAAA==.',
Ak='Akanbe:BAABLgAECn83AAIFAAkJhh3TBgD2AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAFAAkJhh3TBgD2AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAEAEwAbwwAAAIANwAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8oAAMGAAkJ2gpsKQBnAQloDAAABQAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAGAAkJ2gpsKQBnAQloDAAABAAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAFAAEJ5QEeXwAhAAFoDAAAAQAEAAAA.Anxious:BAACLgAFFH8NAAIHAAYJyROdDwChAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAHAAYJyROdDwChAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxsAAgcACAlsFjstAJQBAAcACAlsFjstAJQBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbetty:BAAALgAECgQJBQABLgAECgkJHQADABoNAA==.',
Be='Beefmissile:BAAALgAECgIJAgAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEAAAAA==.',
Bo='Bosephis:BAABLgAECn8kAAIIAAYJbxa7bQBOAQZoDAAACABBAGkMAAAHADwAawwAAAcANwBqDAAABQA+AGwMAAADACoA6gwAAAYAPwAIAAYJbxa7bQBOAQZoDAAACABBAGkMAAAHADwAawwAAAcANwBqDAAABQA+AGwMAAADACoA6gwAAAYAPwAAAA==.',
Bu='Bubsecute:BAABLgAECn8aAAQJAAkJexcgDwDkAQloDAAABABNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAHQDqDAAABwBMAG4MAAABAC0AbwwAAAEACgAJAAgJKhkgDwDkAQhoDAAAAwBNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEA6gwAAAIATABuDAAAAQAtAG8MAAABAAoACgADCZoLQHYAbwADaAwAAAEABABtDAAAAQAdAOoMAAAEADYACwABCcQb5EMASwAB6gwAAAEARwAAAA==.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgQJDAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJCQAAAA==.',
De='Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8WAAIMAAcJzgW6GQDCAAdoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkAbQwAAAEACgDqDAAABQARAAwABwnOBboZAMIAB2gMAAAEABcAaQwAAAQAEABrDAAABAALAGoMAAACAAMAbAwAAAIACQBtDAAAAQAKAOoMAAAFABEAAAA=.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAcABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumblebob:BAAALgADCgYJFwAAAA==.Dumbledoe:BAAALgADCgUJDQAAAA==.Dumbledor:BAAALgADCgYJEgAAAA==.Dumblehunt:BAAALgADCgYJEAAAAA==.Dumblepal:BAAALgADCgYJCQAAAA==.Dumblepow:BAAALgADCgYJEAAAAA==.Dumblesham:BAAALgADCgYJEgAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAACLgAFFH8GAAIIAAIJIx6gXAC4AAJoDAAABQBZAOoMAAABAEAACAACCSMeoFwAuAACaAwAAAUAWQDqDAAAAQBAAC4ABAp/GAADDQAJCfsaWiUA/QEADQAICfUTWiUA/QEACAAECZEjnnsALwEAAAA=.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAOAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwAPAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJDwAQAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgADCgYJBgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAABLgAECn8sAAMRAAkJIx94CAC6AgloDAAABgBOAGkMAAAGAEwAawwAAAcAXQBqDAAABQBQAGwMAAAFAFsAbQwAAAMAQADqDAAACABeAG4MAAADAFUAbwwAAAEANQARAAkJIx94CAC6AgloDAAAAwBOAGkMAAADAEwAawwAAAMAXQBqDAAAAwBQAGwMAAADAFsAbQwAAAMAQADqDAAABgBeAG4MAAADAFUAbwwAAAEANQASAAYJfRN3UgBdAQZoDAAAAwBHAGkMAAADACQAawwAAAQAOABqDAAAAgA5AGwMAAACACwA6gwAAAIAIQAAAA==.',
Fo='Fox:BAABLgAECn8WAAIRAAYJ8wrqRQDXAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAEAHgARAAYJ8wrqRQDXAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAEAHgAAAA==.',
Fr='Frakattack:BAAALgADCgcJCAAAAA==.Frostlord:BAAALgAECgcJDgABLgAFFAEJAgAQAAAAAA==.Frymancer:BAAALgAECgUJEQAAAA==.',
Go='Goemon:BAAALgAECgQJCAAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAAALgAECgYJEQAAAA==.',
Hu='Hudemonized:BAAALgAECgcJDAAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.',
Ir='Ironfistt:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8KAAIBAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwABAAMJ2RYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAYAOwAuAAQKfxYAAgEACAnhHh8LAK8CAAEACAnhHh8LAK8CAAAA.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBQAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgUJDQAAAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kayde:BAAALgAECggJCgAAAA==.',
Ke='Keisel:BAABLgAECn8bAAMTAAgJ5xPULQDlAQhoDAAABQBMAGkMAAAEAE0AawwAAAQALgBqDAAABQAYAGwMAAADADsAbQwAAAEAKgDqDAAAAwBCAG4MAAACAA0AEwAICecT1C0A5QEIaAwAAAUATABpDAAABABNAGsMAAAEAC4AagwAAAUAGABsDAAAAwA7AG0MAAABACoA6gwAAAMAQgBuDAAAAQANABQAAQm7B4qiACUAAW4MAAABABMAAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgEJBAAAAA==.Kissmyheals:BAAALgAECgUJEAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Le='Legendairy:BAAALgAECgkJCQABLgAECgkJGwAPAP4dAA==.',
Li='Lilbigterd:BAABLgAECn8xAAIVAAgJ+RydMQBcAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAKADqDAAABwBQAG4MAAAEAFcAFQAICfkcnTEAXAIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFACgA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJIgAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgAECgcJCQAAAA==.Luxray:BAAALgAECgQJBAAAAA==.',
Ly='Lychee:BAAALgAECgcJDAAAAA==.',
Ma='Magilou:BAABLgAFFH8MAAIWAAYJ2RAzLACLAQZoDAAAAgBOAGkMAAACABMAawwAAAIAMgBqDAAAAgAYAGwMAAACACsA6gwAAAIAFwAWAAYJ2RAzLACLAQZoDAAAAgBOAGkMAAACABMAawwAAAIAMgBqDAAAAgAYAGwMAAACACsA6gwAAAIAFwAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIIAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoACAACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/HgADCAAICeUiORgAdwIACAAICeUiORgAdwIADQAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAAALgAECgYJDQAAAA==.',
Md='Mdsnista:BAABLgAECn9DAAIWAAkJaRawLwBDAgloDAAACQBWAGkMAAAIAEcAawwAAAkALgBqDAAACQAnAGwMAAAIADEAbQwAAAQALADqDAAACgBIAG4MAAAGADsAbwwAAAQAGwAWAAkJaRawLwBDAgloDAAACQBWAGkMAAAIAEcAawwAAAkALgBqDAAACQAnAGwMAAAIADEAbQwAAAQALADqDAAACgBIAG4MAAAGADsAbwwAAAQAGwAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIXAAgJNxFNVgBrAQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAIAIADqDAAABwAnAG4MAAACADkAFwAICTcRTVYAawEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAACACAA6gwAAAcAJwBuDAAAAgA5AAAA.',
Ne='Nerox:BAAALgAECgYJBwAAAA==.Neryssa:BAABLgAECn8dAAIYAAYJxgVaIADLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAYAAYJxgVaIADLAAZoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAAQAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8tAAIYAAgJKAuBEwBeAQhoDAAACAAYAGkMAAAJABYAawwAAAgAFgBqDAAABQASAGwMAAAHACQAbQwAAAEACgDqDAAABAAoAG4MAAADACsAGAAICSgLgRMAXgEIaAwAAAgAGABpDAAACQAWAGsMAAAIABYAagwAAAUAEgBsDAAABwAkAG0MAAABAAoA6gwAAAQAKABuDAAAAwArAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAAQAAAAAA==.Patience:BAAALgAECgcJDQAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8mAAISAAkJWRXhGwBTAgloDAAABQBNAGkMAAAHAEcAawwAAAYARwBqDAAABQAyAGwMAAADADsAbQwAAAEAGgDqDAAABwA9AG4MAAADADgAbwwAAAEAEQASAAkJWRXhGwBTAgloDAAABQBNAGkMAAAHAEcAawwAAAYARwBqDAAABQAyAGwMAAADADsAbQwAAAEAGgDqDAAABwA9AG4MAAADADgAbwwAAAEAEQAAAA==.',
Qm='Qmen:BAACLgAFFH8HAAIVAAMJXgTKbQCmAANoDAAABAAWAGkMAAABAAMA6gwAAAIABwAVAAMJXgTKbQCmAANoDAAABAAWAGkMAAABAAMA6gwAAAIABwAuAAQKfy8AAxUACQnkFy1MAMoBABUACQnkFy1MAMoBAAcAAQn2BruJACoAAAAA.',
Qt='Qtora:BAAALgAECgQJCAAAAA==.',
Qu='Queso:BAABLgAECn8qAAMFAAgJURjZHQC8AQhoDAAABgBHAGkMAAAFAEcAawwAAAUAVABqDAAABgA8AGwMAAAGAD4AbQwAAAUAFgDqDAAABwAxAG4MAAACAEsABQAICVEY2R0AvAEIaAwAAAUARwBpDAAABQBHAGsMAAAFAFQAagwAAAQAPABsDAAABgA+AG0MAAAFABYA6gwAAAYAMQBuDAAAAgBLAAYAAwmVBphsAHcAA2gMAAABAAMAagwAAAIALgDqDAAAAQABAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgcJEAAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAACLgAFFH8HAAIIAAQJvBq8HQBjAQRoDAAAAgBaAGkMAAACADgAawwAAAEASgDqDAAAAgAzAAgABAm8GrwdAGMBBGgMAAACAFoAaQwAAAIAOABrDAAAAQBKAOoMAAACADMALgAECn82AAIIAAkJjyFFEgCpAgAIAAkJjyFFEgCpAgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgUJBQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgAECgUJBQAAAA==.Semtéc:BAAALgAECgIJAwAAAA==.Sephîroth:BAAALgAECgYJCgAAAA==.',
Sh='Shadont:BAABLgAECn8fAAIZAAkJRxOYGgDUAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAZAAkJRxOYGgDUAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAAAA==.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8qAAMUAAgJ6hRGIgC6AQhoDAAACAA6AGkMAAAIACsAawwAAAkAPwBqDAAABQAxAGwMAAADAC4AbQwAAAEAHQDqDAAABgAvAG4MAAACAFUAFAAICeoURiIAugEIaAwAAAQAOgBpDAAABAArAGsMAAAEAD8AagwAAAIAMQBsDAAAAwAuAG0MAAABAB0A6gwAAAIALwBuDAAAAgBVABMABQkZDlFwAOsABWgMAAAEACQAaQwAAAQAMABrDAAABQA1AGoMAAADABoA6gwAAAQADwABLgAECgkJHQADABoNAA==.',
Si='Sinhfyre:BAABLgAECn8hAAMaAAYJsgP2FwCCAAZoDAAABgAFAGkMAAAGABAAawwAAAcADwBqDAAABAASAGwMAAAEAAYA6gwAAAYABAAaAAUJMwT2FwCCAAVoDAAAAQAFAGkMAAAFABAAawwAAAIADwBqDAAAAgASAGwMAAACAAYAGwAGCV0CeGwAagAGaAwAAAUABQBpDAAAAQAHAGsMAAAFAAcAagwAAAIADgBsDAAAAgAFAOoMAAAGAAQAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAIRAAgJMAbFQgDlAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAADABAAEQAICTAGxUIA5QAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAwAQAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMPAAkJ/h1hCwBtAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgAPAAgJhyBhCwBtAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADgAJCXMTBS0AQAEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stillscruby:BAABLgAECn8dAAIDAAkJGg1SFwDJAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAIADgADAAkJGg1SFwDJAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABQAmAGwMAAAFACoAbQwAAAMAFwDqDAAABQA2AG4MAAABAC8AbwwAAAIADgAAAA==.',
Su='Sumting:BAAALgAECgYJCAAAAA==.',
['Sí']='Síntor:BAABLgAECn82AAMVAAgJBRToWQCmAQhoDAAACgA8AGkMAAAJAEgAawwAAAgASQBqDAAACAAzAGwMAAAGACwAbQwAAAEACQDqDAAACQA9AG4MAAADACQAFQAICa4S6FkApgEIaAwAAAgANwBpDAAABwBIAGsMAAAGAEkAagwAAAcAMwBsDAAAAgAZAG0MAAABAAkA6gwAAAcAPQBuDAAAAwAkABwABgk4FOYcABUBBmgMAAACADwAaQwAAAIAOwBrDAAAAgAoAGoMAAABABEAbAwAAAQALADqDAAAAgA1AAAA.',
Te='Teach:BAAALgAECgUJEQABLgAECgYJFAAEABMdAA==.Tenjii:BAAALgAECgQJBAABLgAECgUJCwAQAAAAAA==.Tensham:BAAALgAECgUJCwAAAA==.',
Th='Theimpaler:BAABLgAECn8cAAMJAAcJOgxwKAAVAQdoDAAABwAgAGkMAAAEACsAawwAAAQANgBqDAAAAwAdAGwMAAAEABQAbQwAAAEADwDqDAAABQAUAAkABwk6DHAoABUBB2gMAAAGACAAaQwAAAQAKwBrDAAABAA2AGoMAAADAB0AbAwAAAQAFABtDAAAAQAPAOoMAAAFABQACwABCZ8DJE8AHwABaAwAAAEACQABLgAFFAEJAgAQAAAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJDwAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIOAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AA4ABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIOAAgJ0CEQCgDXAgAOAAgJ0CEQCgDXAgAAAA==.Twiks:BAAALgAECgUJDQAAAA==.',
Ul='Uley:BAEALgAECgUJEQAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn81AAIMAAkJjxusAgBuAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAABwBYAG4MAAADADkAbwwAAAMAQwAMAAkJjxusAgBuAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAABwBYAG4MAAADADkAbwwAAAMAQwAAAA==.',
Vo='Volker:BAABLgAECn8fAAILAAkJihDuGwA+AQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwALAAkJihDuGwA+AQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAAAA==.',
Wa='Waywa:BAAALgAECgQJBAAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwAQAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyDfBQDEAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQABAAkJPyDfBQDEAgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQAAAA==.Xandûs:BAABLgAFFH8GAAIXAAQJLwtDRAABAQRoDAAAAgARAGkMAAACADIAawwAAAEAEwDqDAAAAQAbABcABAkvC0NEAAEBBGgMAAACABEAaQwAAAIAMgBrDAAAAQATAOoMAAABABsAAAA=.',
Xe='Xeraza:BAAALgAFFAIJAwABLgAFFAUJDQAcADMTAA==.Xerô:BAACLgAFFH8NAAIcAAUJMxN7BAAxAQVoDAAABAA6AGkMAAADAEwAawwAAAIAIgBsDAAAAQAHAOoMAAADAEUAHAAFCTMTewQAMQEFaAwAAAQAOgBpDAAAAwBMAGsMAAACACIAbAwAAAEABwDqDAAAAwBFAC4ABAp/LAADHAAICUQfDwcAWAIAHAAICUQfDwcAWAIAFQABCbAXwFABRAAAAAA=.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECggJEgAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAAALgAECgUJBwAAAA==.',
Zu='Zuf:BAACLgAFFH8TAAIRAAUJdCD1EQBfAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAFAFwAEQAFCXQg9REAXwEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABQBcAC4ABAp/MgADEQAJCTkl5wEAVQMAEQAJCTkl5wEAVQMAHQABCd8CJzkAJAAAAAA=.',
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

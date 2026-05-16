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

local lookup = {'DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Unknown-Unknown','Priest-Shadow','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Warrior-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-05-14',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJBgAAAA==.',
Ae='Aemeath:BAACLgAFFH8fAAIBAAcJPiIuAAB8AgdoDAAABgBdAGkMAAAFAGAAawwAAAUAXgBqDAAABQA/AGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk+Ii4AAHwCB2gMAAAGAF0AaQwAAAUAYABrDAAABQBeAGoMAAAFAD8AbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8UAAIBAAkJGiULAQC3AwABAAkJGiULAQC3AwAAAA==.',
Aj='Ajtwo:BAACLgAFFH8HAAICAAMJqgvAGADsAANoDAAAAwA1AGkMAAADABEA6gwAAAEAEgACAAMJqgvAGADsAANoDAAAAwA1AGkMAAADABEA6gwAAAEAEgAuAAQKfyQAAwIACAnqFQgSALEBAAIACAnqFQgSALEBAAMAAwmwBLQZAF8AAAAA.',
Ak='Akanbe:BAABLgAECn8wAAIEAAkJ/RqrBADvAgloDAAACABKAGkMAAAHAFUAawwAAAcARABqDAAABgBdAGwMAAAGAFMAbQwAAAMAIgDqDAAABwBYAG4MAAADADsAbwwAAAEAIAAEAAkJ/RqrBADvAgloDAAACABKAGkMAAAHAFUAawwAAAcARABqDAAABgBdAGwMAAAGAFMAbQwAAAMAIgDqDAAABwBYAG4MAAADADsAbwwAAAEAIAAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8kAAMFAAgJMgqbJQA9AQhoDAAABQAjAGkMAAAGABkAawwAAAYAMABqDAAABQARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAABAAEABQAICTIKmyUAPQEIaAwAAAQAIwBpDAAABgAZAGsMAAAGADAAagwAAAUAEQBsDAAABQAjAG0MAAADABYA6gwAAAUAFgBuDAAAAQABAAQAAQnlAR5fACEAAWgMAAABAAQAAAA=.Anxious:BAACLgAFFH8NAAIGAAYJyRPuBgDQAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAGAAYJyRPuBgDQAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxoAAgYABwn8FActAEsBAAYABwn8FActAEsBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbetty:BAAALgAECgQJBAAAAA==.',
Be='Beefmissile:BAAALgAECgEJAQAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJDgAAAA==.',
Bo='Bosephis:BAABLgAECn8ZAAIHAAYJgBMhUwA2AQZoDAAABgA5AGkMAAAFADcAawwAAAUAHgBqDAAAAwAxAGwMAAACACoA6gwAAAQAPwAHAAYJgBMhUwA2AQZoDAAABgA5AGkMAAAFADcAawwAAAUAHgBqDAAAAwAxAGwMAAACACoA6gwAAAQAPwAAAA==.',
Bu='Bubsecute:BAABLgAECn8UAAMIAAkJUhclCQDtAQloDAAAAwBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAHQDqDAAABABMAG4MAAABAC0AbwwAAAEACgAIAAgJ+xglCQDtAQhoDAAAAgBKAGkMAAADAEwAawwAAAMAUgBqDAAAAgAlAGwMAAACAFEA6gwAAAEATABuDAAAAQAtAG8MAAABAAoACQADCRQLtl4AZwADaAwAAAEABABtDAAAAQAdAOoMAAADADIAAAA=.Bunkerbawb:BAAALgADCgYJBgAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgQJCAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.',
Di='Diananight:BAABLgAECn8UAAIKAAYJIQaGFgCxAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAQAEQAKAAYJIQaGFgCxAAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAQAEQAAAA==.Dinorèy:BAAALgADCgYJBgAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIGAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAYABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumblebob:BAAALgADCgUJDAAAAA==.Dumbledoe:BAAALgADCgMJAwAAAA==.Dumbledor:BAAALgADCgYJDgAAAA==.Dumblehunt:BAAALgADCgQJBQAAAA==.Dumblepal:BAAALgADCgYJCQAAAA==.Dumblepow:BAAALgADCgYJBwAAAA==.Dumblesham:BAAALgADCgYJCAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAABLgAECn8VAAMLAAkJBxZaJQD9AQloDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYAbwwAAAEAXQALAAgJ9RNaJQD9AQhoDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYABwABCYMkSqgAaAABbwwAAAEAXQAAAA==.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAMAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwANAPodAA==.',
Fl='Flight:BAAALgADCgMJAwAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokighoul:BAAALgAECggJCAAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAABLgAECn8qAAMOAAkJyh6HBADPAgloDAAABgBOAGkMAAAGAEwAawwAAAcAXQBqDAAABQBQAGwMAAAFAFsAbQwAAAMAPwDqDAAABgBXAG4MAAADAFUAbwwAAAEANQAOAAkJyh6HBADPAgloDAAAAwBOAGkMAAADAEwAawwAAAMAXQBqDAAAAwBQAGwMAAADAFsAbQwAAAMAPwDqDAAABABXAG4MAAADAFUAbwwAAAEANQAPAAYJfRN3UgBdAQZoDAAAAwBHAGkMAAADACQAawwAAAQAOABqDAAAAgA5AGwMAAACACwA6gwAAAIAIQAAAA==.',
Fo='Fox:BAAALgAECgUJDAAAAA==.',
Fr='Frostlord:BAAALgAECgIJAwABLgAECgcJGAAIADUKAA==.Frymancer:BAAALgAECgUJDQAAAA==.',
Go='Goemon:BAAALgAECgEJAQAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAAALgADCgYJCQAAAA==.',
Hu='Hudemonized:BAAALgAECgYJCgAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8JAAIBAAMJVRYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAUANwABAAMJVRYHBgD1AANoDAAAAwBQAGkMAAABACMA6gwAAAUANwAuAAQKfxYAAgEACAnhHh8LAK8CAAEACAnhHh8LAK8CAAAA.',
Ju='Julian:BAAALgAECgYJEgAAAA==.',
Ka='Kaela:BAAALgAECgQJBwAAAA==.Kaleela:BAAALgAECgUJCQAAAA==.Kayde:BAAALgAECggJCAAAAA==.',
Ke='Keisel:BAABLgAECn8UAAIQAAcJYxTBJgC4AQdoDAAABABMAGkMAAADAE0AawwAAAMALgBqDAAABAAYAGwMAAACADsA6gwAAAMAQgBuDAAAAQANABAABwljFMEmALgBB2gMAAAEAEwAaQwAAAMATQBrDAAAAwAuAGoMAAAEABgAbAwAAAIAOwDqDAAAAwBCAG4MAAABAA0AAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgEJBAAAAA==.Kissmyheals:BAAALgAECgUJDAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBgAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Li='Lilbigterd:BAABLgAECn8xAAIRAAgJRCDwJgALAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAYwDqDAAABwBQAG4MAAAEAFcAEQAICUQg8CYACwIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFAGMA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJGwAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgADCgQJCAAAAA==.',
Ly='Lychee:BAAALgAECgcJDAAAAA==.',
Ma='Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIHAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoABwACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/FQADBwAICZYfORgAdwIABwAHCXMiORgAdwIACwAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBgAAAA==.Maxipriest:BAAALgADCgcJEAAAAA==.',
Md='Mdsnista:BAABLgAECn8yAAISAAkJGhJIMAADAgloDAAABwA2AGkMAAAGADkAawwAAAcALgBqDAAABwAeAGwMAAAGABsAbQwAAAMALADqDAAACAA7AG4MAAAEADsAbwwAAAIAEwASAAkJGhJIMAADAgloDAAABwA2AGkMAAAGADkAawwAAAcALgBqDAAABwAeAGwMAAAGABsAbQwAAAMALADqDAAACAA7AG4MAAAEADsAbwwAAAIAEwAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.',
Na='Naeblis:BAABLgAECn8iAAITAAgJ3w6WQgBbAQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAEAFgDqDAAABgAnAG4MAAABABgAEwAICd8OlkIAWwEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAABABYA6gwAAAYAJwBuDAAAAQAYAAAA.',
Ne='Nerox:BAAALgAECgYJBwAAAA==.Neryssa:BAABLgAECn8XAAIUAAYJoAXtFQDPAAZoDAAABgAWAGkMAAAFABAAawwAAAQACABqDAAAAgAQAGwMAAACAA0A6gwAAAQACgAUAAYJoAXtFQDPAAZoDAAABgAWAGkMAAAFABAAawwAAAQACABqDAAAAgAQAGwMAAACAA0A6gwAAAQACgAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAAVAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8YAAIUAAgJtQWYDwAtAQhoDAAABAAOAGkMAAAFABEAawwAAAUACgBqDAAAAwALAGwMAAADABMAbQwAAAEACgDqDAAAAgATAG4MAAABAAkAFAAICbUFmA8ALQEIaAwAAAQADgBpDAAABQARAGsMAAAFAAoAagwAAAMACwBsDAAAAwATAG0MAAABAAoA6gwAAAIAEwBuDAAAAQAJAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Paldorei:BAAALgADCgYJBgABLgAECgMJBAAVAAAAAA==.Patience:BAAALgAECgIJAgAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8WAAIPAAYJfRWNMwByAQZoDAAABABDAGkMAAAEADIAawwAAAQAKABqDAAABAAyAGwMAAABADsA6gwAAAUAPQAPAAYJfRWNMwByAQZoDAAABABDAGkMAAAEADIAawwAAAQAKABqDAAABAAyAGwMAAABADsA6gwAAAUAPQAAAA==.',
Qm='Qmen:BAABLgAECn8sAAMRAAkJ5Rf8KwD0AQloDAAABgA9AGkMAAAGAEgAawwAAAgASABqDAAABQAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBBAG4MAAAEADMAbwwAAAEAKAARAAkJ5Rf8KwD0AQloDAAABgA9AGkMAAAGAEgAawwAAAcASABqDAAABQAwAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBBAG4MAAAEADMAbwwAAAEAKAAGAAEJ9gYydAAqAAFrDAAAAQARAAAA.',
Qt='Qtora:BAAALgADCgUJBQAAAA==.',
Qu='Queso:BAABLgAECn8jAAMEAAgJ+BOuGQCUAQhoDAAABgBHAGkMAAAFAEcAawwAAAUAVABqDAAABgA8AGwMAAAEADMAbQwAAAMAFADqDAAABQAoAG4MAAABAAgABAAICfgTrhkAlAEIaAwAAAUARwBpDAAABQBHAGsMAAAFAFQAagwAAAQAPABsDAAABAAzAG0MAAADABQA6gwAAAQAKABuDAAAAQAIAAUAAwmVBphsAHcAA2gMAAABAAMAagwAAAIALgDqDAAAAQABAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgIJAgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAABLgAECn81AAIHAAkJjyHSBgDjAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAHAAkJjyHSBgDjAgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgEJAQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Semtéc:BAAALgAECgEJAQAAAA==.Sephîroth:BAAALgAECgYJCAAAAA==.',
Sh='Shadont:BAABLgAECn8WAAIWAAgJ1hOaLQByAQhoDAAAAwAzAGkMAAADADsAawwAAAMAOgBqDAAAAgAOAGwMAAADAEsAbQwAAAIAGQDqDAAABAAxAG4MAAACACIAFgAICdYTmi0AcgEIaAwAAAMAMwBpDAAAAwA7AGsMAAADADoAagwAAAIADgBsDAAAAwBLAG0MAAACABkA6gwAAAQAMQBuDAAAAgAiAAAA.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8ZAAMQAAYJjhDhWQDPAAZoDAAABQAhAGkMAAAFACgAawwAAAYAJwBqDAAAAwAaAGwMAAACAGMA6gwAAAQADwAQAAUJHgzhWQDPAAVoDAAAAwAhAGkMAAADACgAawwAAAQAJwBqDAAAAgAaAOoMAAAEAA8AFwAFCV0M5EYAsAAFaAwAAAIAGgBpDAAAAgAeAGsMAAACABYAagwAAAEAFgBsDAAAAgAuAAAA.',
Si='Sinhfyre:BAABLgAECn8VAAMYAAYJHgNRFQBhAAZoDAAABAAFAGkMAAAEABAAawwAAAUABwBqDAAAAgASAGwMAAACAAYA6gwAAAQABAAZAAYJXQKlTQCIAAZoDAAAAwAFAGkMAAABAAcAawwAAAQABwBqDAAAAQALAGwMAAABAAUA6gwAAAQABAAYAAUJegNRFQBhAAVoDAAAAQAFAGkMAAADABAAawwAAAEABwBqDAAAAQASAGwMAAABAAYAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8XAAIOAAgJpAV9MgDjAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAABAAYADgAICaQFfTIA4wAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAQAGAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMNAAkJ+h38BgCGAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgANAAgJhiD8BgCGAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADAAJCW4Tkh4AUwEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stillscruby:BAAALgAECggJEAAAAA==.',
Su='Sumting:BAAALgAECgQJBAAAAA==.',
['Sí']='Síntor:BAABLgAECn8gAAMaAAYJkhTIFQATAQZoDAAABwA8AGkMAAAGAEcAawwAAAUAMwBqDAAABQAzAGwMAAADABoA6gwAAAYANQAaAAUJ0BLIFQATAQVoDAAAAQA8AGkMAAABADsAawwAAAEAKABsDAAAAgAaAOoMAAABADUAEQAGCVMRLoIACgEGaAwAAAYAKgBpDAAABQBHAGsMAAAEADMAagwAAAUAMwBsDAAAAQAMAOoMAAAFACsAAAA=.',
Te='Teach:BAAALgAECgUJDQABLgAECgYJDwAVAAAAAA==.Tensham:BAAALgAECgUJCwAAAA==.',
Th='Theimpaler:BAABLgAECn8YAAMIAAcJNQq2GwAGAQdoDAAABwAgAGkMAAAEACsAawwAAAMAFwBqDAAAAgAdAGwMAAACABQAbQwAAAEADwDqDAAABQAUAAgABwk1CrYbAAYBB2gMAAAGACAAaQwAAAQAKwBrDAAAAwAXAGoMAAACAB0AbAwAAAIAFABtDAAAAQAPAOoMAAAFABQAGwABCZ8DJE8AHwABaAwAAAEACQAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgADCgEJAQABLgADCgMJAwAVAAAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIMAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AAwABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIMAAgJzyEQCgDXAgAMAAgJzyEQCgDXAgAAAA==.Twiks:BAAALgAECgUJDQAAAA==.',
Ul='Uley:BAEALgAECgUJDQAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn8mAAIKAAkJLhueAQB9AgloDAAABgBQAGkMAAAGAE8AawwAAAYAUgBqDAAABQA5AGwMAAAEAE0AbQwAAAMAHwDqDAAABQBYAG4MAAACADkAbwwAAAEAOwAKAAkJLhueAQB9AgloDAAABgBQAGkMAAAGAE8AawwAAAYAUgBqDAAABQA5AGwMAAAEAE0AbQwAAAMAHwDqDAAABQBYAG4MAAACADkAbwwAAAEAOwAAAA==.',
Vo='Volker:BAABLgAECn8bAAIbAAgJyBHgGQCAAQhoDAAABABGAGkMAAADACgAawwAAAMAJABqDAAAAwAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAABABkAGwAICcgR4BkAgAEIaAwAAAQARgBpDAAAAwAoAGsMAAADACQAagwAAAMAGQBsDAAABQAcAG0MAAADADwA6gwAAAUAOABuDAAAAQAZAAAA.',
Wi='Witz:BAAALgAECgUJDQABLgADCgcJBwAVAAAAAQ==.',
Xa='Xandus:BAABLgAECn8kAAIBAAkJGB7mBACbAgloDAAABQBaAGkMAAAFAFwAawwAAAUAWwBqDAAABABTAGwMAAAEAEcAbQwAAAIANgDqDAAABgBLAG4MAAAEADYAbwwAAAEAVQABAAkJGB7mBACbAgloDAAABQBaAGkMAAAFAFwAawwAAAUAWwBqDAAABABTAGwMAAAEAEcAbQwAAAIANgDqDAAABgBLAG4MAAAEADYAbwwAAAEAVQAAAA==.Xandûs:BAAALgAECgYJEAAAAA==.',
Xe='Xeraza:BAAALgAFFAIJAgABLgAFFAQJDAAaAEsXAA==.Xerô:BAACLgAFFH8MAAIaAAQJSxcqBAAAAQRoDAAABAA6AGkMAAADAEwAawwAAAIAIgDqDAAAAwBFABoABAlLFyoEAAABBGgMAAAEADoAaQwAAAMATABrDAAAAgAiAOoMAAADAEUALgAECn8jAAIaAAgJxBxKBwBsAgAaAAgJxBxKBwBsAgAAAA==.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECgYJCQAAAA==.',
Yo='Yogo:BAAALgAECgIJAgAAAA==.',
Zu='Zuf:BAACLgAFFH8SAAIOAAUJfB7jCQBwAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAEAEcADgAFCXwe4wkAcAEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABABHAC4ABAp/MgADDgAJCToluwAAaAMADgAJCToluwAAaAMAHAABCd8CJzkAJAAAAAA=.',
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

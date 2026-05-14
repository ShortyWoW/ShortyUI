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

local lookup = {'DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Restoration','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Unknown-Unknown','Priest-Shadow','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Warrior-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-05-13',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJBgAAAA==.',
Ae='Aemeath:BAACLgAFFH8fAAIBAAcJPiIkAACDAgdoDAAABgBdAGkMAAAFAGAAawwAAAUAXgBqDAAABQA/AGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk+IiQAAIMCB2gMAAAGAF0AaQwAAAUAYABrDAAABQBeAGoMAAAFAD8AbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8UAAIBAAkJGiULAQC3AwABAAkJGiULAQC3AwAAAA==.',
Aj='Ajtwo:BAABLgAECn8kAAMCAAgJ6hWODwDEAQhoDAAABgA+AGkMAAAFAEoAawwAAAUALQBqDAAABQAgAGwMAAAFAEEAbQwAAAMANADqDAAABQA/AG4MAAACABwAAgAICeoVjg8AxAEIaAwAAAQAPgBpDAAABABKAGsMAAAFAC0AagwAAAUAIABsDAAABQBBAG0MAAADADQA6gwAAAQAPwBuDAAAAgAcAAMAAwmwBLQZAF8AA2gMAAACAB0AaQwAAAEAAADqDAAAAQAFAAAA.',
Ak='Akanbe:BAABLgAECn8pAAIEAAgJHhzCBgCkAghoDAAABwBKAGkMAAAGAFUAawwAAAYARABqDAAABQBQAGwMAAAFAFMAbQwAAAMAIgDqDAAABgBYAG4MAAADADsABAAICR4cwgYApAIIaAwAAAcASgBpDAAABgBVAGsMAAAGAEQAagwAAAUAUABsDAAABQBTAG0MAAADACIA6gwAAAYAWABuDAAAAwA7AAAA.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8kAAMFAAgJMgqBIwBEAQhoDAAABQAjAGkMAAAGABkAawwAAAYAMABqDAAABQARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAABAAEABQAICTIKgSMARAEIaAwAAAQAIwBpDAAABgAZAGsMAAAGADAAagwAAAUAEQBsDAAABQAjAG0MAAADABYA6gwAAAUAFgBuDAAAAQABAAQAAQnlAR5fACEAAWgMAAABAAQAAAA=.Anxious:BAACLgAFFH8NAAIGAAYJyRNjBgDSAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAGAAYJyRNjBgDSAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxYAAgYABwniE3U9AIMBAAYABwniE3U9AIMBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbetty:BAAALgAECgQJBAAAAA==.',
Be='Beefmissile:BAAALgAECgEJAQAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJDgAAAA==.',
Bo='Bosephis:BAABLgAECn8ZAAIHAAYJgBPGTABAAQZoDAAABgA5AGkMAAAFADcAawwAAAUAHgBqDAAAAwAxAGwMAAACACoA6gwAAAQAPwAHAAYJgBPGTABAAQZoDAAABgA5AGkMAAAFADcAawwAAAUAHgBqDAAAAwAxAGwMAAACACoA6gwAAAQAPwAAAA==.',
Bu='Bubsecute:BAAALgAECgcJEgAAAA==.Bunkerbawb:BAAALgADCgYJBgAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgQJCAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.',
Di='Diananight:BAABLgAECn8UAAIIAAYJIQZdFQC1AAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAQAEQAIAAYJIQZdFQC1AAZoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkA6gwAAAQAEQAAAA==.Dinorèy:BAAALgADCgYJBgAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8UAAIGAAcJcghJRwBbAQdoDAAABAASAGkMAAADABAAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAYABwlyCElHAFsBB2gMAAAEABIAaQwAAAMAEABrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumblebob:BAAALgADCgUJDAAAAA==.Dumbledoe:BAAALgADCgMJAwAAAA==.Dumbledor:BAAALgADCgYJDgAAAA==.Dumblehunt:BAAALgADCgQJBAAAAA==.Dumblepal:BAAALgADCgUJBQAAAA==.Dumblepow:BAAALgADCgIJAQAAAA==.Dumblesham:BAAALgADCgYJCAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAABLgAECn8VAAMJAAkJBxZaJQD9AQloDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYAbwwAAAEAXQAJAAgJ9RNaJQD9AQhoDAAAAwBBAGkMAAADADQAawwAAAMAQABqDAAAAwA8AGwMAAACACQAbQwAAAEANwDqDAAAAwA7AG4MAAACABYABwABCYMkMKMAaQABbwwAAAEAXQAAAA==.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAKAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwALAPodAA==.',
Fl='Flight:BAAALgADCgMJAwAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokighoul:BAAALgAECggJCAAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAABLgAECn8oAAMMAAkJyh60AwDiAgloDAAABgBOAGkMAAAGAEwAawwAAAcAXQBqDAAABQBQAGwMAAAFAFsAbQwAAAIAPwDqDAAABQBXAG4MAAADAFUAbwwAAAEANQAMAAkJyh60AwDiAgloDAAAAwBOAGkMAAADAEwAawwAAAMAXQBqDAAAAwBQAGwMAAADAFsAbQwAAAIAPwDqDAAAAwBXAG4MAAADAFUAbwwAAAEANQANAAYJfRN3UgBdAQZoDAAAAwBHAGkMAAADACQAawwAAAQAOABqDAAAAgA5AGwMAAACACwA6gwAAAIAIQAAAA==.',
Fo='Fox:BAAALgAECgUJDAAAAA==.',
Fr='Frostlord:BAAALgAECgIJAwABLgAECgcJGAAOADUKAA==.Frymancer:BAAALgAECgUJDQAAAA==.',
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
Ka='Kaela:BAAALgAECgQJBwAAAA==.Kaleela:BAAALgAECgUJCQAAAA==.',
Ke='Keisel:BAABLgAECn8UAAIPAAcJYxTiIwC7AQdoDAAABABMAGkMAAADAE0AawwAAAMALgBqDAAABAAYAGwMAAACADsA6gwAAAMAQgBuDAAAAQANAA8ABwljFOIjALsBB2gMAAAEAEwAaQwAAAMATQBrDAAAAwAuAGoMAAAEABgAbAwAAAIAOwDqDAAAAwBCAG4MAAABAA0AAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgEJAwAAAA==.Kissmyheals:BAAALgAECgUJDAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBgAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Li='Lilbigterd:BAABLgAECn8xAAIQAAgJRCACIgAWAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAYwDqDAAABwBQAG4MAAAEAFcAEAAICUQgAiIAFgIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFAGMA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJGwAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgADCgQJBwAAAA==.',
Ly='Lychee:BAAALgAECgcJDAAAAA==.',
Ma='Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIHAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoABwACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/FQADBwAICZYfORgAdwIABwAHCXMiORgAdwIACQAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBgAAAA==.Maxipriest:BAAALgADCgcJEAAAAA==.',
Md='Mdsnista:BAABLgAECn8yAAIRAAkJGhLkKQASAgloDAAABwA2AGkMAAAGADkAawwAAAcALgBqDAAABwAeAGwMAAAGABsAbQwAAAMALADqDAAACAA7AG4MAAAEADsAbwwAAAIAEwARAAkJGhLkKQASAgloDAAABwA2AGkMAAAGADkAawwAAAcALgBqDAAABwAeAGwMAAAGABsAbQwAAAMALADqDAAACAA7AG4MAAAEADsAbwwAAAIAEwAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.',
Na='Naeblis:BAABLgAECn8iAAISAAgJ3w4APABjAQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAEAFgDqDAAABgAnAG4MAAABABgAEgAICd8OADwAYwEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAABABYA6gwAAAYAJwBuDAAAAQAYAAAA.',
Ne='Nerox:BAAALgAECgYJBwAAAA==.Neryssa:BAABLgAECn8XAAITAAYJoAVyFADcAAZoDAAABgAWAGkMAAAFABAAawwAAAQACABqDAAAAgAQAGwMAAACAA0A6gwAAAQACgATAAYJoAVyFADcAAZoDAAABgAWAGkMAAAFABAAawwAAAQACABqDAAAAgAQAGwMAAACAA0A6gwAAAQACgAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAAUAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8WAAITAAcJ8wUTEQAPAQdoDAAABAAOAGkMAAAFABEAawwAAAUACgBqDAAAAwALAGwMAAADABMAbQwAAAEACgDqDAAAAQASABMABwnzBRMRAA8BB2gMAAAEAA4AaQwAAAUAEQBrDAAABQAKAGoMAAADAAsAbAwAAAMAEwBtDAAAAQAKAOoMAAABABIAAAA=.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Paldorei:BAAALgADCgYJBgABLgAECgMJBAAUAAAAAA==.Patience:BAAALgAECgIJAgAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8WAAINAAYJfRUCMQB3AQZoDAAABABDAGkMAAAEADIAawwAAAQAKABqDAAABAAyAGwMAAABADsA6gwAAAUAPQANAAYJfRUCMQB3AQZoDAAABABDAGkMAAAEADIAawwAAAQAKABqDAAABAAyAGwMAAABADsA6gwAAAUAPQAAAA==.',
Qm='Qmen:BAABLgAECn8qAAMQAAkJ0Rc9JgAAAgloDAAABgA9AGkMAAAGAEgAawwAAAgASABqDAAABQAwAGwMAAAFAFEAbQwAAAIAKgDqDAAABQBBAG4MAAAEADMAbwwAAAEAKAAQAAkJ0Rc9JgAAAgloDAAABgA9AGkMAAAGAEgAawwAAAcASABqDAAABQAwAGwMAAAFAFEAbQwAAAIAKgDqDAAABQBBAG4MAAAEADMAbwwAAAEAKAAGAAEJ9gYabwAtAAFrDAAAAQARAAAA.',
Qt='Qtora:BAAALgADCgUJBQAAAA==.',
Qu='Queso:BAABLgAECn8jAAMEAAgJ+BN9FwCZAQhoDAAABgBHAGkMAAAFAEcAawwAAAUAVABqDAAABgA8AGwMAAAEADMAbQwAAAMAFADqDAAABQAoAG4MAAABAAgABAAICfgTfRcAmQEIaAwAAAUARwBpDAAABQBHAGsMAAAFAFQAagwAAAQAPABsDAAABAAzAG0MAAADABQA6gwAAAQAKABuDAAAAQAIAAUAAwmVBphsAHcAA2gMAAABAAMAagwAAAIALgDqDAAAAQABAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgIJAgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAABLgAECn81AAIHAAkJjyFYBQD2AgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAHAAkJjyFYBQD2AgloDAAACABYAGkMAAAIAFwAawwAAAgAXABqDAAABwBZAGwMAAAHAGAAbQwAAAIARQDqDAAABwBdAG4MAAAFAEAAbwwAAAEAWgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgEJAQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Semtéc:BAAALgAECgEJAQAAAA==.Sephîroth:BAAALgAECgYJCAAAAA==.',
Sh='Shadont:BAABLgAECn8WAAIVAAgJ1hOaLQByAQhoDAAAAwAzAGkMAAADADsAawwAAAMAOgBqDAAAAgAOAGwMAAADAEsAbQwAAAIAGQDqDAAABAAxAG4MAAACACIAFQAICdYTmi0AcgEIaAwAAAMAMwBpDAAAAwA7AGsMAAADADoAagwAAAIADgBsDAAAAwBLAG0MAAACABkA6gwAAAQAMQBuDAAAAgAiAAAA.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8ZAAMPAAYJjhBpVQDSAAZoDAAABQAhAGkMAAAFACgAawwAAAYAJwBqDAAAAwAaAGwMAAACAGMA6gwAAAQADwAPAAUJHgxpVQDSAAVoDAAAAwAhAGkMAAADACgAawwAAAQAJwBqDAAAAgAaAOoMAAAEAA8AFgAFCV0MqEEAvgAFaAwAAAIAGgBpDAAAAgAeAGsMAAACABYAagwAAAEAFgBsDAAAAgAuAAAA.',
Si='Sinhfyre:BAABLgAECn8VAAMXAAYJHgNEFABjAAZoDAAABAAFAGkMAAAEABAAawwAAAUABwBqDAAAAgASAGwMAAACAAYA6gwAAAQABAAYAAYJXQIASQCQAAZoDAAAAwAFAGkMAAABAAcAawwAAAQABwBqDAAAAQALAGwMAAABAAUA6gwAAAQABAAXAAUJegNEFABjAAVoDAAAAQAFAGkMAAADABAAawwAAAEABwBqDAAAAQASAGwMAAABAAYAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8XAAIMAAgJpAW5LgDzAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAABAAYADAAICaQFuS4A8wAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAQAGAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMLAAkJ+h0hBgCPAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgALAAgJhiAhBgCPAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYACgAJCW4TUhwAVwEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stillscruby:BAAALgAECggJDwAAAA==.',
Su='Sumting:BAAALgAECgQJBAAAAA==.',
['Sí']='Síntor:BAABLgAECn8gAAMZAAYJkhSnFAAWAQZoDAAABwA8AGkMAAAGAEcAawwAAAUAMwBqDAAABQAzAGwMAAADABoA6gwAAAYANQAZAAUJ0BKnFAAWAQVoDAAAAQA8AGkMAAABADsAawwAAAEAKABsDAAAAgAaAOoMAAABADUAEAAGCVMRpHkAEAEGaAwAAAYAKgBpDAAABQBHAGsMAAAEADMAagwAAAUAMwBsDAAAAQAMAOoMAAAFACsAAAA=.',
Te='Teach:BAAALgAECgUJDQABLgAECgYJDwAUAAAAAA==.Tensham:BAAALgAECgUJCwAAAA==.',
Th='Theimpaler:BAABLgAECn8YAAMOAAcJNQqsGAATAQdoDAAABwAgAGkMAAAEACsAawwAAAMAFwBqDAAAAgAdAGwMAAACABQAbQwAAAEADwDqDAAABQAUAA4ABwk1CqwYABMBB2gMAAAGACAAaQwAAAQAKwBrDAAAAwAXAGoMAAACAB0AbAwAAAIAFABtDAAAAQAPAOoMAAAFABQAGgABCZ8DJE8AHwABaAwAAAEACQAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgADCgEJAQABLgADCgMJAwAUAAAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIKAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AAoABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIKAAgJzyEQCgDXAgAKAAgJzyEQCgDXAgAAAA==.Twiks:BAAALgAECgUJDQAAAA==.',
Ul='Uley:BAEALgAECgUJDQAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn8lAAIIAAgJvht4AgA3AghoDAAABgBQAGkMAAAGAE8AawwAAAYAUgBqDAAABQA5AGwMAAAEAE0AbQwAAAMAHwDqDAAABQBYAG4MAAACADkACAAICb4beAIANwIIaAwAAAYAUABpDAAABgBPAGsMAAAGAFIAagwAAAUAOQBsDAAABABNAG0MAAADAB8A6gwAAAUAWABuDAAAAgA5AAAA.',
Vo='Volker:BAABLgAECn8bAAIaAAgJyBHgGQCAAQhoDAAABABGAGkMAAADACgAawwAAAMAJABqDAAAAwAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAABABkAGgAICcgR4BkAgAEIaAwAAAQARgBpDAAAAwAoAGsMAAADACQAagwAAAMAGQBsDAAABQAcAG0MAAADADwA6gwAAAUAOABuDAAAAQAZAAAA.',
Wi='Witz:BAAALgAECgUJDQABLgADCgcJBwAUAAAAAQ==.',
Xa='Xandus:BAABLgAECn8kAAIBAAkJGB4vBACpAgloDAAABQBaAGkMAAAFAFwAawwAAAUAWwBqDAAABABTAGwMAAAEAEcAbQwAAAIANgDqDAAABgBLAG4MAAAEADYAbwwAAAEAVQABAAkJGB4vBACpAgloDAAABQBaAGkMAAAFAFwAawwAAAUAWwBqDAAABABTAGwMAAAEAEcAbQwAAAIANgDqDAAABgBLAG4MAAAEADYAbwwAAAEAVQAAAA==.Xandûs:BAAALgAECgYJEAAAAA==.',
Xe='Xeraza:BAAALgAFFAIJAgABLgAFFAQJDAAZAEsXAA==.Xerô:BAACLgAFFH8MAAIZAAQJSxf8AwACAQRoDAAABAA6AGkMAAADAEwAawwAAAIAIgDqDAAAAwBFABkABAlLF/wDAAIBBGgMAAAEADoAaQwAAAMATABrDAAAAgAiAOoMAAADAEUALgAECn8jAAIZAAgJxBxKBwBsAgAZAAgJxBxKBwBsAgAAAA==.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECgYJCQAAAA==.',
Yo='Yogo:BAAALgAECgIJAgAAAA==.',
Zu='Zuf:BAACLgAFFH8PAAIMAAUJMBv/DABQAQVoDAAAAwA1AGkMAAAEAEQAawwAAAQAWwBqDAAAAQAEAOoMAAADAEAADAAFCTAb/wwAUAEFaAwAAAMANQBpDAAABABEAGsMAAAEAFsAagwAAAEABADqDAAAAwBAAC4ABAp/KQADDAAJCWQh1AoAOwIADAAJCWQh1AoAOwIAGwABCd8CJzkAJAAAAAA=.',
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

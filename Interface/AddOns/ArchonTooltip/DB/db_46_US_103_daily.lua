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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Balance','Druid-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-06-14',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH8jAAIBAAcJNyKaAADYAQdoDAAABwBdAGkMAAAGAGAAawwAAAYAXgBqDAAABgBLAGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk3IpoAANgBB2gMAAAHAF0AaQwAAAYAYABrDAAABgBeAGoMAAAGAEsAbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8WAAMBAAkJGiULAQC3AwABAAkJGiULAQC3AwACAAEJrB5CKgBXAAAAAA==.',
Aj='Ajtwo:BAACLgAFFH8RAAIDAAUJSQ3UHgAnAQVoDAAABQA1AGkMAAAFABgAawwAAAIAIQBqDAAAAQAJAOoMAAAEABkAAwAFCUkN1B4AJwEFaAwAAAUANQBpDAAABQAYAGsMAAACACEAagwAAAEACQDqDAAABAAZAC4ABAp/JgADAwAJCdoWzBYA5AEAAwAJCdoWzBYA5AEABAADCbAEtBkAXwAAAAA=.',
Ak='Akanbe:BAABLgAECn85AAIFAAkJ9B3YBwD6AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAFAEwAbwwAAAMAQQAFAAkJ9B3YBwD6AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAFAEwAbwwAAAMAQQAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8oAAMGAAkJ2grnLQBaAQloDAAABQAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAGAAkJ2grnLQBaAQloDAAABAAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAFAAEJ5QEeXwAhAAFoDAAAAQAEAAAA.Anxious:BAACLgAFFH8NAAIHAAYJyRNXFQB4AQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAHAAYJyRNXFQB4AQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxsAAgcACAlsFvMwAJMBAAcACAlsFvMwAJMBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbessy:BAAALgAECgEJAQABLgAFFAQJBQAIAKgVAA==.Bandaidbetty:BAAALgAECgQJBQABLgAFFAQJBQAIAKgVAA==.',
Be='Beefmissile:BAAALgAECgMJBAAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEQAAAA==.',
Bo='Bosephis:BAABLgAECn8xAAIJAAcJ3BQfYwB8AQdoDAAACgBBAGkMAAAJADwAawwAAAkANwBqDAAABwA+AGwMAAAFACoA6gwAAAgAPwBuDAAAAQAhAAkABwncFB9jAHwBB2gMAAAKAEEAaQwAAAkAPABrDAAACQA3AGoMAAAHAD4AbAwAAAUAKgDqDAAACAA/AG4MAAABACEAAAA=.',
Bu='Bubsecute:BAABLgAECn8bAAQKAAkJjBhJDAAgAgloDAAABABNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAIAMwDqDAAABwBMAG4MAAABAC0AbwwAAAEACgAKAAkJjBhJDAAgAgloDAAAAwBNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAMwDqDAAAAgBMAG4MAAABAC0AbwwAAAEACgALAAMJmgsEggBuAANoDAAAAQAEAG0MAAABAB0A6gwAAAQANgAMAAEJxBtdSgBKAAHqDAAAAQBHAAAA.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgUJDgAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJCQAAAA==.',
De='Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8cAAINAAgJAQeaFwDjAAhoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkAbQwAAAEACgDqDAAACAAkAG4MAAADABEADQAICQEHmhcA4wAIaAwAAAQAFwBpDAAABAAQAGsMAAAEAAsAagwAAAIAAwBsDAAAAgAJAG0MAAABAAoA6gwAAAgAJABuDAAAAwARAAAA.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAcABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumbldorian:BAAALgADCgUJBQAAAA==.Dumblebob:BAAALgADCgYJHwAAAA==.Dumbledoe:BAAALgADCgUJDgAAAA==.Dumbledor:BAAALgADCgYJGgAAAA==.Dumblehunt:BAAALgADCgYJFQAAAA==.Dumblepal:BAAALgADCgYJDwAAAA==.Dumblepow:BAAALgADCgYJFQAAAA==.Dumblesham:BAAALgADCgYJHAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAACLgAFFH8NAAIJAAUJpRXZOQA1AQVoDAAABgBZAGkMAAABADwAawwAAAEABwBqDAAAAgAkAOoMAAADAEAACQAFCaUV2TkANQEFaAwAAAYAWQBpDAAAAQA8AGsMAAABAAcAagwAAAIAJADqDAAAAwBAAC4ABAp/GwADDgAJCWwbWiUA/QEADgAICfUTWiUA/QEACQAECb4kvoIANgEAAAA=.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAPAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwAQAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJEwARAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgADCgYJBgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAACLgAFFH8HAAISAAQJiBlsGQBIAQRoDAAAAwBQAGkMAAABACoAawwAAAEALQDqDAAAAgBcABIABAmIGWwZAEgBBGgMAAADAFAAaQwAAAEAKgBrDAAAAQAtAOoMAAACAFwALgAECn8sAAMSAAkJIx8tCgCvAgASAAkJIx8tCgCvAgATAAYJfRN3UgBdAQAAAA==.',
Fo='Fox:BAABLgAECn8XAAISAAYJIQtpTADXAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAIAIAASAAYJIQtpTADXAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAIAIAAAAA==.',
Fr='Frakattack:BAAALgADCgcJDwAAAA==.Frostlord:BAAALgAECgcJDgABLgAECgcJHAAKADoMAA==.Frymancer:BAAALgAECgYJEwAAAA==.',
Go='Goemon:BAAALgAECgYJEQAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAAALgAECgYJEwAAAA==.',
Hu='Hudemonized:BAAALgAECgcJDAAAAA==.',
Il='Illestofdans:BAAALgAECgQJBAAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.',
Ir='Ironfistt:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8PAAIBAAUJZhuvCwBNAQVoDAAABABQAGkMAAACAFMAawwAAAEAOABqDAAAAQA4AOoMAAAHADsAAQAFCWYbrwsATQEFaAwAAAQAUABpDAAAAgBTAGsMAAABADgAagwAAAEAOADqDAAABwA7AC4ABAp/FgACAQAICeEeHwsArwIAAQAICeEeHwsArwIAAAA=.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBgAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgYJDgAAAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kayde:BAAALgAECggJCwAAAA==.',
Ke='Keepitscruby:BAAALgAECgMJAwABLgAFFAQJBQAIAKgVAA==.Keisel:BAABLgAECn8bAAMIAAgJ5xNKMwDiAQhoDAAABQBMAGkMAAAEAE0AawwAAAQALgBqDAAABQAYAGwMAAADADsAbQwAAAEAKgDqDAAAAwBCAG4MAAACAA0ACAAICecTSjMA4gEIaAwAAAUATABpDAAABABNAGsMAAAEAC4AagwAAAUAGABsDAAAAwA7AG0MAAABACoA6gwAAAMAQgBuDAAAAQANABQAAQm7B960ACUAAW4MAAABABMAAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgQJBwAAAA==.Kissmyheals:BAAALgAECgYJEgAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Le='Legendairy:BAAALgAECgkJCQABLgAECgkJGwAQAP4dAA==.',
Li='Lightfall:BAAALgAECgcJDAAAAA==.Lilbigterd:BAABLgAECn8xAAIVAAgJ+RydMQBcAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAKADqDAAABwBQAG4MAAAEAFcAFQAICfkcnTEAXAIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFACgA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJIgAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAABLgAECn8UAAILAAgJLAPCZgDCAAhoDAAABAAJAGkMAAADAAwAawwAAAQACgBqDAAAAwANAGwMAAACAAsAbQwAAAEAAQDqDAAAAgAFAG4MAAABAAUACwAICSwDwmYAwgAIaAwAAAQACQBpDAAAAwAMAGsMAAAEAAoAagwAAAMADQBsDAAAAgALAG0MAAABAAEA6gwAAAIABQBuDAAAAQAFAAAA.Luxray:BAAALgAECgQJBAAAAA==.',
Ly='Lychee:BAAALgAECgcJDQAAAA==.',
Ma='Magilou:BAABLgAFFH8PAAIWAAcJ1xAxKADVAQdoDAAAAgBOAGkMAAACABMAawwAAAIAMgBqDAAAAgAYAGwMAAACACsAbQwAAAEABwDqDAAABAA7ABYABwnXEDEoANUBB2gMAAACAE4AaQwAAAIAEwBrDAAAAgAyAGoMAAACABgAbAwAAAIAKwBtDAAAAQAHAOoMAAAEADsAAAA=.Malificent:BAAALgAECgYJBwAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIJAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoACQACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/HgADCQAICeUiORgAdwIACQAICeUiORgAdwIADgAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAAALgAECgYJEwAAAA==.',
Md='Mdsnista:BAABLgAECn9VAAIWAAkJIx8LFADfAgloDAAACwBWAGkMAAAKAE8AawwAAAsAPABqDAAACwBHAGwMAAALAEoAbQwAAAYAVADqDAAACwBIAG4MAAAIAF4AbwwAAAYAVAAWAAkJIx8LFADfAgloDAAACwBWAGkMAAAKAE8AawwAAAsAPABqDAAACwBHAGwMAAALAEoAbQwAAAYAVADqDAAACwBIAG4MAAAIAF4AbwwAAAYAVAAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.Mossyleaf:BAAALgAECgQJBAAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIXAAgJNxGeXQBtAQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAIAIADqDAAABwAnAG4MAAACADkAFwAICTcRnl0AbQEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAACACAA6gwAAAcAJwBuDAAAAgA5AAAA.',
Ne='Nerox:BAAALgAECgcJDgAAAA==.Neryssa:BAABLgAECn8iAAIYAAcJugeHHgACAQdoDAAACAAkAGkMAAAHAB0AawwAAAYACgBqDAAAAwAQAGwMAAADAA0A6gwAAAYAEQBuDAAAAQAKABgABwm6B4ceAAIBB2gMAAAIACQAaQwAAAcAHQBrDAAABgAKAGoMAAADABAAbAwAAAMADQDqDAAABgARAG4MAAABAAoAAAA=.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAARAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8uAAIYAAgJKAuJFgBXAQhoDAAACAAYAGkMAAAJABYAawwAAAgAFgBqDAAABQASAGwMAAAHACQAbQwAAAEACgDqDAAABQAoAG4MAAADACsAGAAICSgLiRYAVwEIaAwAAAgAGABpDAAACQAWAGsMAAAIABYAagwAAAUAEgBsDAAABwAkAG0MAAABAAoA6gwAAAUAKABuDAAAAwArAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAARAAAAAA==.Patience:BAAALgAECgcJEwAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn84AAITAAkJRxtuDwDXAgloDAAABwBSAGkMAAAJAFUAawwAAAgAXwBqDAAABwAyAGwMAAAGAEQAbQwAAAMANADqDAAACABEAG4MAAAFAFoAbwwAAAMAIQATAAkJRxtuDwDXAgloDAAABwBSAGkMAAAJAFUAawwAAAgAXwBqDAAABwAyAGwMAAAGAEQAbQwAAAMANADqDAAACABEAG4MAAAFAFoAbwwAAAMAIQAAAA==.',
Qm='Qmen:BAACLgAFFH8LAAIVAAQJEwiTVwD8AARoDAAABQAWAGkMAAACACEAawwAAAEAEADqDAAAAwAKABUABAkTCJNXAPwABGgMAAAFABYAaQwAAAIAIQBrDAAAAQAQAOoMAAADAAoALgAECn8wAAMVAAkJDRgwSwDjAQAVAAkJDRgwSwDjAQAHAAEJ9gbVkwAqAAAAAA==.',
Qt='Qtora:BAAALgAECgQJCwAAAA==.',
Qu='Queso:BAACLgAFFH8HAAIFAAIJihImOwCJAAJoDAAABAArAGkMAAADADIABQACCYoSJjsAiQACaAwAAAQAKwBpDAAAAwAyAC4ABAp/LgADBQAICQwaPh8A0wEABQAICQwaPh8A0wEABgADCZUGmGwAdwAAAAA=.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgcJEgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAACLgAFFH8MAAIJAAQJiRzbKQBaAQRoDAAAAwBaAGkMAAADADgAawwAAAIASgDqDAAABABGAAkABAmJHNspAFoBBGgMAAADAFoAaQwAAAMAOABrDAAAAgBKAOoMAAAEAEYALgAECn82AAIJAAkJjyEOFwCaAgAJAAkJjyEOFwCaAgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgUJBQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgAECgUJBgAAAA==.Semtéc:BAAALgAECgIJBAAAAA==.Sephîroth:BAAALgAECgYJCgAAAA==.',
Sh='Shadont:BAABLgAECn8fAAIZAAkJRxMhHQDcAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAZAAkJRxMhHQDcAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAAAA==.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAACLgAFFH8FAAMIAAQJqBVzawBiAARoDAAAAQBiAGkMAAACAFkAawwAAAEAGADqDAAAAQAIAAgAAgl4BnNrAGIAAmsMAAABABgA6gwAAAEACAAUAAIJNQO/TABcAAJoDAAAAQAEAGkMAAACAAwALgAECn8xAAMUAAgJ6RTtJgCyAQAUAAgJ6RTtJgCyAQAIAAYJbBeUQQCkAQAAAA==.',
Si='Sinhfyre:BAABLgAECn8uAAMaAAcJkgWwEwDNAAdoDAAACAASAGkMAAAIABEAawwAAAkAEABqDAAABgAiAGwMAAAGAAsA6gwAAAgAEABuDAAAAQAEABoABwmSBbATAM0AB2gMAAADABIAaQwAAAcAEQBrDAAABAAQAGoMAAAEACIAbAwAAAQACwDqDAAAAgAQAG4MAAABAAQAGwAGCV0C9nMAfAAGaAwAAAUABQBpDAAAAQAHAGsMAAAFAAcAagwAAAIADgBsDAAAAgAFAOoMAAAGAAQAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAISAAgJMAZKSQDjAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAADABAAEgAICTAGSkkA4wAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAwAQAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMQAAkJ/h3GDABpAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgAQAAgJhyDGDABpAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADwAJCXMT0DEAPAEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stayinscruby:BAAALgAECgUJBwABLgAFFAQJBQAIAKgVAA==.Stillscruby:BAABLgAECn8jAAIDAAkJlQ31GADQAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABgA2AGwMAAAGACoAbQwAAAQAGQDqDAAABgA2AG4MAAACAC8AbwwAAAMAFQADAAkJlQ31GADQAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABgA2AGwMAAAGACoAbQwAAAQAGQDqDAAABgA2AG4MAAACAC8AbwwAAAMAFQABLgAFFAQJBQAIAKgVAA==.',
Su='Sumting:BAAALgAECgcJEwAAAA==.',
['Sí']='Síntor:BAABLgAECn8+AAMVAAkJExrtKgBUAgloDAAACwBSAGkMAAAKAEgAawwAAAkATQBqDAAACQA3AGwMAAAHADYAbQwAAAIARQDqDAAACQA9AG4MAAAEACcAbwwAAAEATAAVAAkJoRjtKgBUAgloDAAACQBSAGkMAAAIAEgAawwAAAcATQBqDAAACAA3AGwMAAACABkAbQwAAAIARQDqDAAABwA9AG4MAAAEACcAbwwAAAEATAAcAAYJABWDHgAeAQZoDAAAAgA8AGkMAAACADsAawwAAAIAKABqDAAAAQARAGwMAAAFADYA6gwAAAIANQAAAA==.',
Te='Teach:BAAALgAECgYJEwAAAA==.Tenjii:BAAALgAECgQJBAABLgAECgYJDQARAAAAAA==.Tensham:BAAALgAECgYJDQAAAA==.',
Th='Theimpaler:BAABLgAECn8cAAMKAAcJOgybLgALAQdoDAAABwAgAGkMAAAEACsAawwAAAQANgBqDAAAAwAdAGwMAAAEABQAbQwAAAEADwDqDAAABQAUAAoABwk6DJsuAAsBB2gMAAAGACAAaQwAAAQAKwBrDAAABAA2AGoMAAADAB0AbAwAAAQAFABtDAAAAQAPAOoMAAAFABQADAABCZ8DJE8AHwABaAwAAAEACQAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJEwAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIPAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AA8ABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIPAAgJ0CEQCgDXAgAPAAgJ0CEQCgDXAgAAAA==.Twiks:BAAALgAECgYJDwAAAA==.',
Ul='Uley:BAEALgAECgYJEwAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn82AAINAAkJjxtLAwBlAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAACABYAG4MAAADADkAbwwAAAMAQwANAAkJjxtLAwBlAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAACABYAG4MAAADADkAbwwAAAMAQwAAAA==.',
Vo='Volker:BAACLgAFFH8FAAIMAAMJ7gqAHwCVAANoDAAAAgAaAGkMAAABAAkA6gwAAAIALwAMAAMJ7gqAHwCVAANoDAAAAgAaAGkMAAABAAkA6gwAAAIALwAuAAQKfx8AAgwACQmKEOAZAIABAAwACQmKEOAZAIABAAAA.',
Wa='Waywa:BAAALgAECgUJBQAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwARAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyBrBwC4AgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQABAAkJPyBrBwC4AgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQAAAA==.Xandûs:BAABLgAFFH8LAAIXAAQJrw3qTgD7AARoDAAAAwAcAGkMAAADAD8AawwAAAIAEwDqDAAAAwAbABcABAmvDepOAPsABGgMAAADABwAaQwAAAMAPwBrDAAAAgATAOoMAAADABsAAAA=.',
Xe='Xeraza:BAAALgAFFAIJAwABLgAFFAUJDQAcADMTAA==.Xerô:BAACLgAFFH8NAAIcAAUJMxP5BQAhAQVoDAAABAA6AGkMAAADAEwAawwAAAIAIgBsDAAAAQAHAOoMAAADAEUAHAAFCTMT+QUAIQEFaAwAAAQAOgBpDAAAAwBMAGsMAAACACIAbAwAAAEABwDqDAAAAwBFAC4ABAp/LAADHAAICUQfOAgAUgIAHAAICUQfOAgAUgIAFQABCbAX3XMBQgAAAAA=.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECggJEwAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAAALgAECgcJDwAAAA==.',
Zu='Zuf:BAACLgAFFH8TAAISAAUJdCA2GABSAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAFAFwAEgAFCXQgNhgAUgEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABQBcAC4ABAp/NgADEgAJCTklSQIAUAMAEgAJCTklSQIAUAMAHQABCd8CJzkAJAAAAAA=.',
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

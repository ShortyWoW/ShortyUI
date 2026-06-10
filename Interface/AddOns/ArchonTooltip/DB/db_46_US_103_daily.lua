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
local provider = {region='US',realm='Garithos',name='US',type='daily',zone=46,date='2026-06-09',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH8jAAIBAAcJNyKaAADYAQdoDAAABwBdAGkMAAAGAGAAawwAAAYAXgBqDAAABgBLAGwMAAADAFEAbQwAAAEAQwDqDAAABgBcAAEABwk3IpoAANgBB2gMAAAHAF0AaQwAAAYAYABrDAAABgBeAGoMAAAGAEsAbAwAAAMAUQBtDAAAAQBDAOoMAAAGAFwALgAECn8WAAMBAAkJGiULAQC3AwABAAkJGiULAQC3AwACAAEJrB7+KABXAAAAAA==.',
Aj='Ajtwo:BAACLgAFFH8RAAIDAAUJSQ0pHQAoAQVoDAAABQA1AGkMAAAFABgAawwAAAIAIQBqDAAAAQAJAOoMAAAEABkAAwAFCUkNKR0AKAEFaAwAAAUANQBpDAAABQAYAGsMAAACACEAagwAAAEACQDqDAAABAAZAC4ABAp/JgADAwAJCdoWFBYA5AEAAwAJCdoWFBYA5AEABAADCbAEtBkAXwAAAAA=.',
Ak='Akanbe:BAABLgAECn85AAIFAAkJ9B2LBwD6AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAFAEwAbwwAAAMAQQAFAAkJ9B2LBwD6AgloDAAACABKAGkMAAAIAFUAawwAAAgARABqDAAABwBdAGwMAAAHAFMAbQwAAAQANQDqDAAABwBYAG4MAAAFAEwAbwwAAAMAQQAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgAAAA==.',
An='Anniichan:BAABLgAECn8oAAMGAAkJ2gq6LABcAQloDAAABQAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAGAAkJ2gq6LABcAQloDAAABAAjAGkMAAAGABkAawwAAAcAMABqDAAABgARAGwMAAAFACMAbQwAAAMAFgDqDAAABQAWAG4MAAACACEAbwwAAAEACQAFAAEJ5QEeXwAhAAFoDAAAAQAEAAAA.Anxious:BAACLgAFFH8NAAIHAAYJyRMpEwCMAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAHAAYJyRMpEwCMAQZoDAAAAwBDAGkMAAACAEUAawwAAAIAQwBqDAAAAgAiAGwMAAABABQA6gwAAAMALQAuAAQKfxsAAgcACAlsFu4vAJMBAAcACAlsFu4vAJMBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgADCgcJBwAAAA==.Bandaidbessy:BAAALgAECgEJAQABLgAECggJMQAIAOkUAA==.Bandaidbetty:BAAALgAECgQJBQABLgAECggJMQAIAOkUAA==.',
Be='Beefmissile:BAAALgAECgMJBAAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEAAAAA==.',
Bo='Bosephis:BAABLgAECn8rAAIJAAcJ3BQsYAB/AQdoDAAACQBBAGkMAAAIADwAawwAAAgANwBqDAAABgA+AGwMAAAEACoA6gwAAAcAPwBuDAAAAQAhAAkABwncFCxgAH8BB2gMAAAJAEEAaQwAAAgAPABrDAAACAA3AGoMAAAGAD4AbAwAAAQAKgDqDAAABwA/AG4MAAABACEAAAA=.',
Bu='Bubsecute:BAABLgAECn8bAAQKAAkJjBjsCwAgAgloDAAABABNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAIAMwDqDAAABwBMAG4MAAABAC0AbwwAAAEACgAKAAkJjBjsCwAgAgloDAAAAwBNAGkMAAAEAEwAawwAAAQAUgBqDAAAAgAlAGwMAAACAFEAbQwAAAEAMwDqDAAAAgBMAG4MAAABAC0AbwwAAAEACgALAAMJmgvZfgBvAANoDAAAAQAEAG0MAAABAB0A6gwAAAQANgAMAAEJxBuISABKAAHqDAAAAQBHAAAA.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgUJDQAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJCQAAAA==.',
De='Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8aAAINAAgJIAbYFwDcAAhoDAAABAAXAGkMAAAEABAAawwAAAQACwBqDAAAAgADAGwMAAACAAkAbQwAAAEACgDqDAAABwAXAG4MAAACAA4ADQAICSAG2BcA3AAIaAwAAAQAFwBpDAAABAAQAGsMAAAEAAsAagwAAAIAAwBsDAAAAgAJAG0MAAABAAoA6gwAAAcAFwBuDAAAAgAOAAAA.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJDQAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQdoDAAABQATAGkMAAAEADkAawwAAAMAGQBqDAAAAwAQAGwMAAADAA4AbQwAAAEALwDqDAAAAwAMAAcABwnNCklHAFsBB2gMAAAFABMAaQwAAAQAOQBrDAAAAwAZAGoMAAADABAAbAwAAAMADgBtDAAAAQAvAOoMAAADAAwAAAA=.',
Du='Dumbldorian:BAAALgADCgUJBQAAAA==.Dumblebob:BAAALgADCgYJHQAAAA==.Dumbledoe:BAAALgADCgUJDgAAAA==.Dumbledor:BAAALgADCgYJGAAAAA==.Dumblehunt:BAAALgADCgYJFQAAAA==.Dumblepal:BAAALgADCgYJDwAAAA==.Dumblepow:BAAALgADCgYJFQAAAA==.Dumblesham:BAAALgADCgYJFwAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAACLgAFFH8LAAIJAAUJpRXqNAA6AQVoDAAABgBZAGkMAAABADwAawwAAAEABwBqDAAAAQAHAOoMAAACAEAACQAFCaUV6jQAOgEFaAwAAAYAWQBpDAAAAQA8AGsMAAABAAcAagwAAAEABwDqDAAAAgBAAC4ABAp/GgADDgAJCWwbWiUA/QEADgAICfUTWiUA/QEACQAECb4kmH8ANwEAAAA=.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAQJCAAPAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwAQAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJEwARAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgADCgYJBgAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAACLgAFFH8GAAISAAQJiBnXFwBKAQRoDAAAAwBQAGkMAAABACoAawwAAAEALQDqDAAAAQBcABIABAmIGdcXAEoBBGgMAAADAFAAaQwAAAEAKgBrDAAAAQAtAOoMAAABAFwALgAECn8sAAMSAAkJIx+jCQC0AgASAAkJIx+jCQC0AgATAAYJfRN3UgBdAQAAAA==.',
Fo='Fox:BAABLgAECn8XAAISAAYJIQt1SgDYAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAIAIAASAAYJIQt1SgDYAAZoDAAABAAaAGkMAAAGAB0AawwAAAUAHQBqDAAAAwAgAGwMAAADABgA6gwAAAIAIAAAAA==.',
Fr='Frakattack:BAAALgADCgcJDwAAAA==.Frostlord:BAAALgAECgcJDgABLgAECgcJHAAKADoMAA==.Frymancer:BAAALgAECgYJEgAAAA==.',
Go='Goemon:BAAALgAECgQJDAAAAA==.Gorc:BAAALgADCgIJAgAAAA==.',
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
Ji='Jinx:BAACLgAFFH8PAAIBAAUJZhttCgBRAQVoDAAABABQAGkMAAACAFMAawwAAAEAOABqDAAAAQA4AOoMAAAHADsAAQAFCWYbbQoAUQEFaAwAAAQAUABpDAAAAgBTAGsMAAABADgAagwAAAEAOADqDAAABwA7AC4ABAp/FgACAQAICeEeHwsArwIAAQAICeEeHwsArwIAAAA=.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBgAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgYJDgAAAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kayde:BAAALgAECggJCwAAAA==.',
Ke='Keisel:BAABLgAECn8bAAMUAAgJ5xO6MQDjAQhoDAAABQBMAGkMAAAEAE0AawwAAAQALgBqDAAABQAYAGwMAAADADsAbQwAAAEAKgDqDAAAAwBCAG4MAAACAA0AFAAICecTujEA4wEIaAwAAAUATABpDAAABABNAGsMAAAEAC4AagwAAAUAGABsDAAAAwA7AG0MAAABACoA6gwAAAMAQgBuDAAAAQANAAgAAQm7BxivACUAAW4MAAABABMAAAA=.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgQJBwAAAA==.Kissmyheals:BAAALgAECgYJEQAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Le='Legendairy:BAAALgAECgkJCQABLgAECgkJGwAQAP4dAA==.',
Li='Lightfall:BAAALgAECgQJBAAAAA==.Lilbigterd:BAABLgAECn8xAAIVAAgJ+RydMQBcAghoDAAACABQAGkMAAAIAFEAawwAAAUAPABqDAAABQBNAGwMAAAHAFcAbQwAAAUAKADqDAAABwBQAG4MAAAEAFcAFQAICfkcnTEAXAIIaAwAAAgAUABpDAAACABRAGsMAAAFADwAagwAAAUATQBsDAAABwBXAG0MAAAFACgA6gwAAAcAUABuDAAABABXAAAA.Linithel:BAAALgADCgkJIgAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAAALgAECggJDwAAAA==.Luxray:BAAALgAECgQJBAAAAA==.',
Ly='Lychee:BAAALgAECgcJDQAAAA==.',
Ma='Magilou:BAABLgAFFH8NAAIWAAYJuxG/NQCKAQZoDAAAAgBOAGkMAAACABMAawwAAAIAMgBqDAAAAgAYAGwMAAACACsA6gwAAAMAIgAWAAYJuxG/NQCKAQZoDAAAAgBOAGkMAAACABMAawwAAAIAMgBqDAAAAgAYAGwMAAACACsA6gwAAAMAIgAAAA==.Malificent:BAAALgAECgEJAQAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIJAAIJmCSxEADDAAJoDAAABABgAOoMAAAFAFoACQACCZgksRAAwwACaAwAAAQAYADqDAAABQBaAC4ABAp/HgADCQAICeUiORgAdwIACQAICeUiORgAdwIADgAFCXoVWUAAWAEAAAA=.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAAALgAECgYJEwAAAA==.',
Md='Mdsnista:BAABLgAECn9MAAIWAAkJ+hg3KwBoAgloDAAACgBWAGkMAAAJAEoAawwAAAoAPABqDAAACgBBAGwMAAAJADwAbQwAAAUANQDqDAAACwBIAG4MAAAHADsAbwwAAAUAKgAWAAkJ+hg3KwBoAgloDAAACgBWAGkMAAAJAEoAawwAAAoAPABqDAAACgBBAGwMAAAJADwAbQwAAAUANQDqDAAACwBIAG4MAAAHADsAbwwAAAUAKgAAAA==.',
Mi='Milff:BAAALgADCgYJBwAAAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.Mossyleaf:BAAALgAECgQJBAAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIXAAgJNxGEWwBtAQhoDAAABwAoAGkMAAAFADoAawwAAAYALQBqDAAABAAtAGwMAAAEACMAbQwAAAIAIADqDAAABwAnAG4MAAACADkAFwAICTcRhFsAbQEIaAwAAAcAKABpDAAABQA6AGsMAAAGAC0AagwAAAQALQBsDAAABAAjAG0MAAACACAA6gwAAAcAJwBuDAAAAgA5AAAA.',
Ne='Nerox:BAAALgAECgYJDQAAAA==.Neryssa:BAABLgAECn8eAAIYAAcJgQWQHwDwAAdoDAAABwAWAGkMAAAGABAAawwAAAUACgBqDAAAAwAQAGwMAAADAA0A6gwAAAUACgBuDAAAAQAKABgABwmBBZAfAPAAB2gMAAAHABYAaQwAAAYAEABrDAAABQAKAGoMAAADABAAbAwAAAMADQDqDAAABQAKAG4MAAABAAoAAAA=.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAARAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8uAAIYAAgJKAtvFQBcAQhoDAAACAAYAGkMAAAJABYAawwAAAgAFgBqDAAABQASAGwMAAAHACQAbQwAAAEACgDqDAAABQAoAG4MAAADACsAGAAICSgLbxUAXAEIaAwAAAgAGABpDAAACQAWAGsMAAAIABYAagwAAAUAEgBsDAAABwAkAG0MAAABAAoA6gwAAAUAKABuDAAAAwArAAAA.Nukacola:BAAALgAECgQJBwAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAARAAAAAA==.Patience:BAAALgAECgcJEwAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn8wAAITAAkJihfPFwCBAgloDAAABgBNAGkMAAAIAEcAawwAAAcAXwBqDAAABgAyAGwMAAAFAEQAbQwAAAIAGgDqDAAABwA9AG4MAAAEADgAbwwAAAMAIQATAAkJihfPFwCBAgloDAAABgBNAGkMAAAIAEcAawwAAAcAXwBqDAAABgAyAGwMAAAFAEQAbQwAAAIAGgDqDAAABwA9AG4MAAAEADgAbwwAAAMAIQAAAA==.',
Qm='Qmen:BAACLgAFFH8IAAIVAAQJ3QTiYQDdAARoDAAABAAWAGkMAAABAAMAawwAAAEAEADqDAAAAgAHABUABAndBOJhAN0ABGgMAAAEABYAaQwAAAEAAwBrDAAAAQAQAOoMAAACAAcALgAECn8wAAMVAAkJDRilSADlAQAVAAkJDRilSADlAQAHAAEJ9gb4kAAqAAAAAA==.',
Qt='Qtora:BAAALgAECgQJCwAAAA==.',
Qu='Queso:BAACLgAFFH8HAAIFAAIJihJGOACJAAJoDAAABAArAGkMAAADADIABQACCYoSRjgAiQACaAwAAAQAKwBpDAAAAwAyAC4ABAp/LgADBQAICQwaFB4A1AEABQAICQwaFB4A1AEABgADCZUGmGwAdwAAAAA=.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgcJEgAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAACLgAFFH8LAAIJAAQJvBoyJwBbAQRoDAAAAwBaAGkMAAADADgAawwAAAIASgDqDAAAAwAzAAkABAm8GjInAFsBBGgMAAADAFoAaQwAAAMAOABrDAAAAgBKAOoMAAADADMALgAECn82AAIJAAkJjyFxFQChAgAJAAkJjyFxFQChAgAAAA==.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgUJBQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Se='Sean:BAAALgAECgUJBgAAAA==.Semtéc:BAAALgAECgIJBAAAAA==.Sephîroth:BAAALgAECgYJCgAAAA==.',
Sh='Shadont:BAABLgAECn8fAAIZAAkJRxPNGwDhAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAZAAkJRxPNGwDhAQloDAAABAAzAGkMAAAEAEYAawwAAAQAOgBqDAAAAwAwAGwMAAAEAEsAbQwAAAMAGQDqDAAABQAzAG4MAAADACIAbwwAAAEAGgAAAA==.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAABLgAECn8xAAMIAAgJ6RSdJQCzAQhoDAAACQA6AGkMAAAJACsAawwAAAoAPwBqDAAABgAxAGwMAAAEAC4AbQwAAAEAHQDqDAAACAAvAG4MAAACAFUACAAICekUnSUAswEIaAwAAAQAOgBpDAAABAArAGsMAAAEAD8AagwAAAIAMQBsDAAAAwAuAG0MAAABAB0A6gwAAAIALwBuDAAAAgBVABQABglsF9o/AKUBBmgMAAAFADcAaQwAAAUASQBrDAAABgA1AGoMAAAEABoAbAwAAAEAPwDqDAAABgBWAAAA.',
Si='Sinhfyre:BAABLgAECn8oAAMaAAcJdwTCFAC7AAdoDAAABwAKAGkMAAAHABEAawwAAAgADwBqDAAABQAiAGwMAAAFAAcA6gwAAAcADQBuDAAAAQAEABoABwl3BMIUALsAB2gMAAACAAoAaQwAAAYAEQBrDAAAAwAPAGoMAAADACIAbAwAAAMABwDqDAAAAQANAG4MAAABAAQAGwAGCV0C+3AAfAAGaAwAAAUABQBpDAAAAQAHAGsMAAAFAAcAagwAAAIADgBsDAAAAgAFAOoMAAAGAAQAAAA=.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAISAAgJMAaERwDkAAhoDAAAAwASAGkMAAADABAAawwAAAMAEQBqDAAABAAUAGwMAAAEABcAbQwAAAEABADqDAAABAANAG4MAAADABAAEgAICTAGhEcA5AAIaAwAAAMAEgBpDAAAAwAQAGsMAAADABEAagwAAAQAFABsDAAABAAXAG0MAAABAAQA6gwAAAQADQBuDAAAAwAQAAAA.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMQAAkJ/h1bDABqAgloDAAAAwBZAGkMAAADAFcAawwAAAMATQBqDAAAAgBUAGwMAAAEAF8AbQwAAAIANwDqDAAABgBcAG4MAAADAFYAbwwAAAEAHgAQAAgJhyBbDABqAghoDAAAAgBZAGkMAAACAFcAawwAAAIATQBqDAAAAQBUAGwMAAACAF8AbQwAAAEANgDqDAAABABcAG4MAAABAFYADwAJCXMTSjAAPQEJaAwAAAEAPABpDAAAAQAnAGsMAAABACMAagwAAAEAEwBsDAAAAgA+AG0MAAABADcA6gwAAAIAOgBuDAAAAgA3AG8MAAABAB4AAAA=.',
Sp='Spippippik:BAAALgAECgUJDAAAAA==.',
St='Stayinscruby:BAAALgAECgUJBwABLgAECggJMQAIAOkUAA==.Stillscruby:BAABLgAECn8hAAIDAAkJcQ2PGADNAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABgA2AGwMAAAFACoAbQwAAAMAFwDqDAAABgA2AG4MAAACAC8AbwwAAAMAFQADAAkJcQ2PGADNAQloDAAAAgAQAGkMAAADACoAawwAAAMAGwBqDAAABgA2AGwMAAAFACoAbQwAAAMAFwDqDAAABgA2AG4MAAACAC8AbwwAAAMAFQABLgAECggJMQAIAOkUAA==.',
Su='Sumting:BAAALgAECgYJEAAAAA==.',
['Sí']='Síntor:BAABLgAECn89AAMVAAgJjBnWQAD9AQhoDAAACwBSAGkMAAAKAEgAawwAAAkATQBqDAAACQA3AGwMAAAHADYAbQwAAAIARQDqDAAACQA9AG4MAAAEACcAFQAICeYX1kAA/QEIaAwAAAkAUgBpDAAACABIAGsMAAAHAE0AagwAAAgANwBsDAAAAgAZAG0MAAACAEUA6gwAAAcAPQBuDAAABAAnABwABgkAFbcdAB4BBmgMAAACADwAaQwAAAIAOwBrDAAAAgAoAGoMAAABABEAbAwAAAUANgDqDAAAAgA1AAAA.',
Te='Teach:BAAALgAECgYJEgAAAA==.Tenjii:BAAALgAECgQJBAABLgAECgYJDAARAAAAAA==.Tensham:BAAALgAECgYJDAAAAA==.',
Th='Theimpaler:BAABLgAECn8cAAMKAAcJOgzBLAAPAQdoDAAABwAgAGkMAAAEACsAawwAAAQANgBqDAAAAwAdAGwMAAAEABQAbQwAAAEADwDqDAAABQAUAAoABwk6DMEsAA8BB2gMAAAGACAAaQwAAAQAKwBrDAAABAA2AGoMAAADAB0AbAwAAAQAFABtDAAAAQAPAOoMAAAFABQADAABCZ8DJE8AHwABaAwAAAEACQAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJEwAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8IAAIPAAQJLRLQBABDAQRoDAAAAgA4AGkMAAACACQAawwAAAIAIQDqDAAAAgA7AA8ABAktEtAEAEMBBGgMAAACADgAaQwAAAIAJABrDAAAAgAhAOoMAAACADsALgAECn8mAAIPAAgJ0CEQCgDXAgAPAAgJ0CEQCgDXAgAAAA==.Twiks:BAAALgAECgYJDgAAAA==.',
Ul='Uley:BAEALgAECgYJEgAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn82AAINAAkJjxsaAwBoAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAACABYAG4MAAADADkAbwwAAAMAQwANAAkJjxsaAwBoAgloDAAACABQAGkMAAAIAE8AawwAAAgAUgBqDAAABwA8AGwMAAAFAE0AbQwAAAQAHwDqDAAACABYAG4MAAADADkAbwwAAAMAQwAAAA==.',
Vo='Volker:BAABLgAECn8fAAIMAAkJihBVHgA4AQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAMAAkJihBVHgA4AQloDAAABABGAGkMAAADACgAawwAAAQAKwBqDAAABAAZAGwMAAAFABwAbQwAAAMAPADqDAAABQA4AG4MAAACABoAbwwAAAEACwAAAA==.',
Wa='Waywa:BAAALgAECgUJBQAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwARAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyADBwC8AgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQABAAkJPyADBwC8AgloDAAABgBaAGkMAAAGAFwAawwAAAYAWwBqDAAABQBXAGwMAAAFAFMAbQwAAAIANgDqDAAABwBcAG4MAAAFAEUAbwwAAAEAVQAAAA==.Xandûs:BAABLgAFFH8KAAIXAAQJrw13SgACAQRoDAAAAwAcAGkMAAADAD8AawwAAAIAEwDqDAAAAgAbABcABAmvDXdKAAIBBGgMAAADABwAaQwAAAMAPwBrDAAAAgATAOoMAAACABsAAAA=.',
Xe='Xeraza:BAAALgAFFAIJAwABLgAFFAUJDQAcADMTAA==.Xerô:BAACLgAFFH8NAAIcAAUJMxOqBQAjAQVoDAAABAA6AGkMAAADAEwAawwAAAIAIgBsDAAAAQAHAOoMAAADAEUAHAAFCTMTqgUAIwEFaAwAAAQAOgBpDAAAAwBMAGsMAAACACIAbAwAAAEABwDqDAAAAwBFAC4ABAp/LAADHAAICUQf7QcAVAIAHAAICUQf7QcAVAIAFQABCbAX22kBQwAAAAA=.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECggJEwAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAAALgAECgcJDAAAAA==.',
Zu='Zuf:BAACLgAFFH8TAAISAAUJdCB9FgBWAQVoDAAABABQAGkMAAAEAEQAawwAAAUAWwBqDAAAAQAEAOoMAAAFAFwAEgAFCXQgfRYAVgEFaAwAAAQAUABpDAAABABEAGsMAAAFAFsAagwAAAEABADqDAAABQBcAC4ABAp/NgADEgAJCTklLAIAUgMAEgAJCTklLAIAUgMAHQABCd8CJzkAJAAAAAA=.',
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

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

local lookup = {'Warrior-Fury','Warlock-Affliction','Paladin-Retribution','Unknown-Unknown','DeathKnight-Frost','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-11',data={Aa='Aaricus:BAAALgAECgYJBwAAAA==.',
Ab='Aberdine:BAACLgAFFH8KAAIBAAQJYwmhFQAYAQRoDAAABAAnAGkMAAADAB4AawwAAAEADADqDAAAAgAOAAEABAljCaEVABgBBGgMAAAEACcAaQwAAAMAHgBrDAAAAQAMAOoMAAACAA4ALgAECn8kAAIBAAgJaRuIJwAgAgABAAgJaRuIJwAgAgAAAA==.',
Ac='Accar:BAAALgAECgYJEwAAAA==.Achu:BAAALgAFFAIJAgABLgAFFAMJDwACAAYmAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgcJBwAAAA==.',
Ag='Agrias:BAAALgAECggJEAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Ambry:BAAALgAECgQJDAABLgAECggJIgADAPYOAA==.Ambryosia:BAABLgAECn8iAAIDAAgJ9g7OVQBZAQhoDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAACAAoAAwAICfYOzlUAWQEIaAwAAAYAQQBpDAAABQBBAGsMAAAEAB4AagwAAAQAJABsDAAABAAmAG0MAAADABAA6gwAAAYAKABuDAAAAgAKAAAA.',
An='Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgUJBQABLgAECgYJCgAEAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAQJCwAFAD8cAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIGAAYJYBHeGQAjAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAGAAYJYBHeGQAjAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAAALgADCgUJCwABLgAECgYJHAAHALQUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8ZAAMIAAkJHRdKFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAABADQAbwwAAAEAGwAIAAkJHRdKFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAABADQAbwwAAAEAGwABAAQJKRAuRgC1AARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgYJCQAEAAAAAA==.Bcwarrior:BAAALgAECgYJCQAAAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAEAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCAAAAA==.',
Bo='Boiardi:BAAALgADCgcJBgAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgQJCQAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgUJBQAAAA==.',
Ce='Celticwoman:BAABLgAECn8dAAMJAAcJDwh+awABAQdoDAAABQAZAGkMAAAFABIAawwAAAUADABqDAAABAA3AGwMAAAEACwAbQwAAAEACQDqDAAABQAMAAkABwkPCH5rAAEBB2gMAAADABkAaQwAAAMAEgBrDAAAAwAMAGoMAAADADcAbAwAAAQALABtDAAAAQAJAOoMAAADAAwACgAFCckEejsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8XAAILAAYJvARrBgDFAAZoDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAAAwAPAGwMAAACAAsA6gwAAAMADwALAAYJvARrBgDFAAZoDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAAAwAPAGwMAAACAAsA6gwAAAMADwAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIMAAIJGCJrJgDJAAJoDAAAAgBQAOoMAAADAF4ADAACCRgiayYAyQACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkLAAMAoB8A.',
Cl='Clockie:BAACLgAFFH8PAAMCAAMJBiZXBQBzAANoDAAABwBhAGkMAAACAGIA6gwAAAYAYAAJAAIJ0iWgRgDbAAJoDAAABwBhAOoMAAAGAGAAAgABCW8mVwUAcwABaQwAAAIAYgAuAAQKfzMABAkACAkSJrscAA8CAAkABglMJbscAA8CAAIABQnGJTEEAMIBAAoABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8UAAIDAAgJuQ6nQgCPAQhoDAAAAwAYAGkMAAADACgAawwAAAMAMABqDAAAAwAqAGwMAAADADcAbQwAAAEAEQDqDAAAAwAoAG4MAAABACYAAwAICbkOp0IAjwEIaAwAAAMAGABpDAAAAwAoAGsMAAADADAAagwAAAMAKgBsDAAAAwA3AG0MAAABABEA6gwAAAMAKABuDAAAAQAmAAEuAAUUBAkPAAcAGQ0A.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAEAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEgAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgQJBwAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAEAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8VAAINAAcJDx3qJQD7AQdoDAAABQBTAGkMAAADAFYAawwAAAMAQABqDAAAAgBIAGwMAAADAFsAbQwAAAEAJwDqDAAABABSAA0ABwkPHeolAPsBB2gMAAAFAFMAaQwAAAMAVgBrDAAAAwBAAGoMAAACAEgAbAwAAAMAWwBtDAAAAQAnAOoMAAAEAFIAAS4ABRQECQ8ABwAZDQA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8KAAIOAAIJMyECFQDGAAJoDAAABQBcAOoMAAAFAE0ADgACCTMhAhUAxgACaAwAAAUAXADqDAAABQBNAAEuAAUUAwkLAAMAoB8A.Duoduomoney:BAABLgAFFH8GAAMPAAIJfBNJFgCEAAJoDAAAAwAtAOoMAAADADYAAQACCXwTaSUAnwACaAwAAAEALQDqDAAAAQA2AA8AAgnjDkkWAIQAAmgMAAACACUA6gwAAAIAJgABLgAFFAMJCwADAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8JAAIQAAIJVQ61DwCnAAJoDAAABQAoAOoMAAAEACAAEAACCVUOtQ8ApwACaAwAAAUAKADqDAAABAAgAAEuAAUUAwkPAAIABiYA.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAAALgAECgcJCwAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgADCgEJAgAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIRAAYJkwraCgD7AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgARAAYJkwraCgD7AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCQAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJBQABLgAECgkJMwASAHYiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.Gixx:BAAALgAECgYJCgABLgAECggJIAADAM4UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8kAAQTAAgJsxw6CAAyAghoDAAABwBNAGkMAAAGAFQAawwAAAYAWABqDAAABQBLAGwMAAAEADYAbQwAAAEAMADqDAAABgBcAG4MAAABAEMAEwAICYYaOggAMgIIaAwAAAMARABpDAAAAwBFAGsMAAADAEkAagwAAAMAMgBsDAAAAwA2AG0MAAABADAA6gwAAAMAXABuDAAAAQBDABQABQlyHtlAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAVAAUJLBNKTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMDAAgJzhRAMgDGAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgAAwAICc4UQDIAxgEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoABYAAwkzBUMwAEUAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAGAGARAA==.',
Hi='Hikiru:BAAALgADCgkJGAAAAA==.',
Ho='Hollowbane:BAABLgAECn8eAAMXAAgJIBYxDgDLAQhoDAAABQA6AGkMAAAFAEIAawwAAAQANABqDAAAAwBSAGwMAAADACkAbQwAAAMAQQDqDAAABQBMAG4MAAACACQAFwAICXsVMQ4AywEIaAwAAAMALwBpDAAAAwBCAGsMAAADADQAagwAAAMAUgBsDAAAAwApAG0MAAADAEEA6gwAAAUATABuDAAAAgAkABgAAwmkFqEOAN4AA2gMAAACADoAaQwAAAIAPwBrDAAAAQAzAAAA.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAAALgAFFAIJAwAAAA==.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAcJDQASAJYeAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8PAAIHAAQJGQ26OgA4AQRoDAAABQA2AGkMAAAEACgAawwAAAIADgDqDAAABAAXAAcABAkZDbo6ADgBBGgMAAAFADYAaQwAAAQAKABrDAAAAgAOAOoMAAAEABcALgAECn8rAAIHAAkJyx7xGAAVAwAHAAkJyx7xGAAVAwAAAA==.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJCgAAAA==.Jonnytsunami:BAAALgAECgMJAwAAAA==.',
Ju='Juicycow:BAAALgAECgMJBgAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8YAAIZAAUJiybuAwDFAQVoDAAABgBkAGkMAAAGAGMAawwAAAQAYQBqDAAAAwBgAOoMAAAFAGEAGQAFCYsm7gMAxQEFaAwAAAYAZABpDAAABgBjAGsMAAAEAGEAagwAAAMAYADqDAAABQBhAC4ABAp/HgADGQAICcUmTAIAdwMAGQAICcUmTAIAdwMAGgABCVUh700AXQAAAAA=.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgQJBAAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8HAAIbAAMJgQhdCgCSAANoDAAABAAjAGkMAAACABEA6gwAAAEACwAbAAMJgQhdCgCSAANoDAAABAAjAGkMAAACABEA6gwAAAEACwAuAAQKfxkAAhsACAmuETkPAIgBABsACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJDgAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBAAAAA==.Klixx:BAAALgADCgcJHQAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8YAAIXAAcJLBuGGgAuAgdoDAAAAwBKAGkMAAAEAEoAawwAAAQAUgBqDAAABAAvAGwMAAABACEA6gwAAAQAOwBuDAAABABcABcABwksG4YaAC4CB2gMAAADAEoAaQwAAAQASgBrDAAABABSAGoMAAAEAC8AbAwAAAEAIQDqDAAABAA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8GAAIHAAIJYRl4NgC9AAJoDAAAAgAoAOoMAAAEAFkABwACCWEZeDYAvQACaAwAAAIAKADqDAAABABZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAAALgAECgUJDwAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAMJCQAcAJ4dAA==.Lesiania:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8XAAMQAAgJWxYeDgD9AQhoDAAABABBAGkMAAAEAEgAawwAAAQANQBqDAAAAwAVAGwMAAACADkAbQwAAAIALwDqDAAAAwBOAG4MAAABABgAEAAICVsWHg4A/QEIaAwAAAMAQQBpDAAAAwBIAGsMAAADADUAagwAAAMAFQBsDAAAAgA5AG0MAAACAC8A6gwAAAMATgBuDAAAAQAYAB0AAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAIJCAAMAFQOAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgYJDQAAAA==.',
Lu='Lucyah:BAAALgAECgMJBAAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAISAAYJSgo3igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQASAAYJSgo3igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAADAM4UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMDAAkJZhuHJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAkJZhuHJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAWAAUJQgxcHwCqAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAYJEwANAFEWAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgMJBAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mo='Monkpig:BAACLgAFFH8NAAIZAAMJJR5nGwAIAQNoDAAABgBKAGkMAAACAEwA6gwAAAUAUAAZAAMJJR5nGwAIAQNoDAAABgBKAGkMAAACAEwA6gwAAAUAUAAuAAQKfykAAhkACAmqH1gLABoCABkACAmqH1gLABoCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIGAAYJTRXLFgBCAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAGAAYJTRXLFgBCAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAEAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAEAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAISAAgJuBzhHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIAEgAICbgc4R0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIcAAYJnBZ9FwAmAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAcAAYJnBZ9FwAmAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECggJJQANALAQAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAEAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyAVFgDGAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyAVFgDGAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwAIAAQJnAsaKwB2AARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAINAAcJrB0+SwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCAA0ABwmsHT5LABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQABAAAAAA=.',
Ra='Raythe:BAABLgAECn8WAAIGAAcJdRUaFQBUAQdoDAAAAwBFAGkMAAAFAE0AawwAAAMAPQBqDAAAAwAXAGwMAAACACUAbQwAAAEAFADqDAAABQA+AAYABwl1FRoVAFQBB2gMAAADAEUAaQwAAAUATQBrDAAAAwA9AGoMAAADABcAbAwAAAIAJQBtDAAAAQAUAOoMAAAFAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAMJBwAbAIEIAA==.',
Ru='Rucker:BAABLgAECn8hAAMIAAkJfRvyAwCJAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgAIAAkJfRvyAwCJAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIStQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJAwABLgAECgkJIQAIAH0bAA==.Rucksy:BAABLgAECn8dAAMWAAgJHR0QBQCrAghoDAAABABcAGkMAAAEAF0AawwAAAYAXwBqDAAABABXAGwMAAAEAEsAbQwAAAEAKADqDAAABQBbAG4MAAABAB8AFgAICR0dEAUAqwIIaAwAAAQAXABpDAAABABdAGsMAAAFAF8AagwAAAMAVwBsDAAABABLAG0MAAABACgA6gwAAAQAWwBuDAAAAQAfAAMAAwn+EbX9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAgAfRsA.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQAIAH0bAA==.',
Ry='Ryan:BAABLgAECn8WAAMDAAYJmCL3JwDyAQZoDAAABQBhAGkMAAADAEwAawwAAAQAWABqDAAABABhAGwMAAADAFwA6gwAAAMAWAADAAYJmCL3JwDyAQZoDAAAAwBhAGkMAAACAEwAawwAAAQAWABqDAAAAQBhAGwMAAACAFwA6gwAAAEAWAAeAAUJziFGKgDgAQVoDAAAAgBdAGkMAAABAFUAagwAAAMAXQBsDAAAAQBIAOoMAAACAFcAAAA=.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAEAAAAAA==.',
Se='Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBAAAAA==.Shankzmcgee:BAABLgAECn8XAAIXAAYJngh6IQD9AAZoDAAABgAVAGkMAAAGAB0AawwAAAUAGABqDAAAAwATAGwMAAACABUA6gwAAAEADQAXAAYJngh6IQD9AAZoDAAABgAVAGkMAAAGAB0AawwAAAUAGABqDAAAAwATAGwMAAACABUA6gwAAAEADQABLgAECggJIAADAM4UAA==.Shardik:BAAALgAECgEJAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCggJDQAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAEAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shèrlock:BAAALgAECgcJDgAAAA==.',
Sk='Skippydippy:BAAALgAECgQJCgAAAA==.Skylin:BAAALgAECgEJAwAAAA==.',
Sl='Sleezee:BAAALgAECgMJBgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgADCgYJBgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAIJCAAMAFQOAA==.',
St='Stargasm:BAAALgAECgcJCAAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgADCgUJBwAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8IAAIMAAIJVA4CNwB/AAJoDAAABAAnAOoMAAAEACEADAACCVQOAjcAfwACaAwAAAQAJwDqDAAABAAhAAAA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgEJAQAAAA==.',
Ta='Taft:BAABLgAECn8qAAIfAAkJNxOiDQAEAgloDAAABAA9AGkMAAAHADgAawwAAAYAOwBqDAAABgA5AGwMAAAFACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAfAAkJNxOiDQAEAgloDAAABAA9AGkMAAAHADgAawwAAAYAOwBqDAAABgA5AGwMAAAFACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJDwAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAQAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJCwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJDwAAAA==.Tritin:BAAALgAECgYJDQAAAA==.',
Tw='Twiltock:BAAALgAECgYJCwAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8aAAIHAAYJCAYnnADtAAZoDAAABQAPAGkMAAAFABQAawwAAAUABABqDAAABAAUAGwMAAADABIA6gwAAAQAEAAHAAYJCAYnnADtAAZoDAAABQAPAGkMAAAFABQAawwAAAUABABqDAAABAAUAGwMAAADABIA6gwAAAQAEAAAAA==.Valiria:BAABLgAECn8ZAAISAAcJnRxWMQA1AgdoDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAACAE4A6gwAAAYAXwBuDAAAAQAQABIABwmdHFYxADUCB2gMAAADAFAAaQwAAAUAXQBrDAAABABKAGoMAAAEAGAAbAwAAAIATgDqDAAABgBfAG4MAAABABAAAAA=.Varzul:BAAALgADCgYJCwABLgAECgIJAgAEAAAAAA==.',
Ve='Velieda:BAABLgAECn8WAAMDAAgJpg8WRwCCAQhoDAAABAAnAGkMAAADAC0AawwAAAMAKABqDAAAAgA6AGwMAAADADEAbQwAAAEAFgDqDAAAAwAZAG4MAAADADkAAwAICQYOFkcAggEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAABABYA6gwAAAIAFABuDAAAAwA5ABYABgkbDVwaANIABmgMAAACABgAaQwAAAEALQBrDAAAAQAWAGoMAAABADoAbAwAAAEAMQDqDAAAAQAZAAAA.',
Vi='Vindication:BAACLgAFFH8JAAIcAAMJnh2TDQATAQNoDAAABABgAGkMAAACADgA6gwAAAMASgAcAAMJnh2TDQATAQNoDAAABABgAGkMAAACADgA6gwAAAMASgAuAAQKfyAAAhwACAkJIC4HAL0CABwACAkJIC4HAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaobao:BAAALgAECgQJBAAAAA==.Xiaoduoduo:BAACLgAFFH8LAAMDAAMJoB8dKAAgAQNoDAAABQBfAGkMAAABAEAA6gwAAAUAUgADAAMJoB8dKAAgAQNoDAAABABfAGkMAAABAEAA6gwAAAUAUgAeAAEJuCNbKgBlAAFoDAAAAQBbAC4ABAp/KQACAwAICeAj6gsAtAIAAwAICeAj6gsAtAIAAAA=.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJCQAAAA==.',
Ze='Zeroskills:BAABLgAECn8aAAMXAAgJ0wVOGQBFAQhoDAAABAAKAGkMAAAEABEAawwAAAQAEwBqDAAAAwAQAGwMAAADABgAbQwAAAIAAwDqDAAABAAOAG4MAAACAA4AFwAICdMFThkARQEIaAwAAAMACgBpDAAAAwARAGsMAAAEABMAagwAAAMAEABsDAAAAwAYAG0MAAACAAMA6gwAAAQADgBuDAAAAgAOABgAAglLBOUWAFsAAmgMAAABAAcAaQwAAAEADgAAAA==.',
Zu='Zulinar:BAAALgAECgUJBgAAAA==.Zumoku:BAAALgADCgkJIgAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8mAAQbAAkJcxHoCAC2AQloDAAABgBMAGkMAAAHAC0AawwAAAcAJgBqDAAABgAyAGwMAAADADMAbQwAAAEAHADqDAAABgA8AG4MAAABACMAbwwAAAEAEwAbAAkJcxHoCAC2AQloDAAABgBMAGkMAAAHAC0AawwAAAYAJgBqDAAABgAyAGwMAAADADMAbQwAAAEAHADqDAAABQA8AG4MAAABACMAbwwAAAEAEwAfAAEJ8gZuYQAtAAFrDAAAAQARAAwAAQkxCg+oACkAAeoMAAABABoAAAA=.',
['Æn']='Ænimá:BAAALgADCgEJAQAAAA==.',
['ßi']='ßiggysmalls:BAAALgADCgUJBQAAAA==.',
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

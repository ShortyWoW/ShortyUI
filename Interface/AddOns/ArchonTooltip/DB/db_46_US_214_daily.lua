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
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-12',data={Aa='Aaricus:BAAALgAECgYJBwAAAA==.',
Ab='Aberdine:BAACLgAFFH8KAAIBAAQJYwmOFgARAQRoDAAABAAnAGkMAAADAB4AawwAAAEADADqDAAAAgAOAAEABAljCY4WABEBBGgMAAAEACcAaQwAAAMAHgBrDAAAAQAMAOoMAAACAA4ALgAECn8kAAIBAAgJaRuKJwAgAgABAAgJaRuKJwAgAgAAAA==.',
Ac='Accar:BAAALgAECgYJEwAAAA==.Achu:BAAALgAFFAIJAgABLgAFFAMJDwACAAYmAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCggJDQAAAA==.',
Ag='Agrias:BAAALgAECggJEAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Ambry:BAAALgAECgQJDAABLgAECggJIgADAPYOAA==.Ambryosia:BAABLgAECn8iAAIDAAgJ9g6RVwBZAQhoDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAACAAoAAwAICfYOkVcAWQEIaAwAAAYAQQBpDAAABQBBAGsMAAAEAB4AagwAAAQAJABsDAAABAAmAG0MAAADABAA6gwAAAYAKABuDAAAAgAKAAAA.',
An='Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgUJBQABLgAECgYJCgAEAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAQJCwAFAD8cAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIGAAYJYBFZGgAjAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAGAAYJYBFZGgAjAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAAALgAECgIJAgABLgAECgYJHAAHALQUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8ZAAMIAAkJHRdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAABADQAbwwAAAEAGwAIAAkJHRdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAABADQAbwwAAAEAGwABAAQJKRA8RwC1AARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgYJCQAEAAAAAA==.Bcwarrior:BAAALgAECgYJCQAAAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAEAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCAAAAA==.',
Bo='Boiardi:BAAALgADCgcJBgAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgQJCQAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgUJBQAAAA==.',
Ce='Celticwoman:BAABLgAECn8dAAMJAAcJDwhRbQAAAQdoDAAABQAZAGkMAAAFABIAawwAAAUADABqDAAABAA3AGwMAAAEACwAbQwAAAEACQDqDAAABQAMAAkABwkPCFFtAAABB2gMAAADABkAaQwAAAMAEgBrDAAAAwAMAGoMAAADADcAbAwAAAQALABtDAAAAQAJAOoMAAADAAwACgAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8XAAILAAYJvASABgDFAAZoDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAAAwAPAGwMAAACAAsA6gwAAAMADwALAAYJvASABgDFAAZoDAAABQAOAGkMAAAFAAsAawwAAAUABwBqDAAAAwAPAGwMAAACAAsA6gwAAAMADwAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIMAAIJGCJTJwDJAAJoDAAAAgBQAOoMAAADAF4ADAACCRgiUycAyQACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkLAAMAoB8A.',
Cl='Clockie:BAACLgAFFH8PAAMCAAMJBiatBQBzAANoDAAABwBhAGkMAAACAGIA6gwAAAYAYAAJAAIJ0iVqSADbAAJoDAAABwBhAOoMAAAGAGAAAgABCW8mrQUAcwABaQwAAAIAYgAuAAQKfzMABAkACAkSJnkdAA8CAAkABglMJXkdAA8CAAIABQnGJVoEAMEBAAoABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8UAAIDAAgJuQ4aRACOAQhoDAAAAwAYAGkMAAADACgAawwAAAMAMABqDAAAAwAqAGwMAAADADcAbQwAAAEAEQDqDAAAAwAoAG4MAAABACYAAwAICbkOGkQAjgEIaAwAAAMAGABpDAAAAwAoAGsMAAADADAAagwAAAMAKgBsDAAAAwA3AG0MAAABABEA6gwAAAMAKABuDAAAAQAmAAEuAAUUBAkPAAcAGQ0A.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAEAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEgAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgQJBwAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAEAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8VAAINAAcJDx3dJgD7AQdoDAAABQBTAGkMAAADAFYAawwAAAMAQABqDAAAAgBIAGwMAAADAFsAbQwAAAEAJwDqDAAABABSAA0ABwkPHd0mAPsBB2gMAAAFAFMAaQwAAAMAVgBrDAAAAwBAAGoMAAACAEgAbAwAAAMAWwBtDAAAAQAnAOoMAAAEAFIAAS4ABRQECQ8ABwAZDQA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8KAAIOAAIJMyEKFQDGAAJoDAAABQBcAOoMAAAFAE0ADgACCTMhChUAxgACaAwAAAUAXADqDAAABQBNAAEuAAUUAwkLAAMAoB8A.Duoduomoney:BAABLgAFFH8GAAMPAAIJfBMRFwCEAAJoDAAAAwAtAOoMAAADADYAAQACCXwTYSYAnAACaAwAAAEALQDqDAAAAQA2AA8AAgnjDhEXAIQAAmgMAAACACUA6gwAAAIAJgABLgAFFAMJCwADAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8JAAIQAAIJVQ64DwCnAAJoDAAABQAoAOoMAAAEACAAEAACCVUOuA8ApwACaAwAAAUAKADqDAAABAAgAAEuAAUUAwkPAAIABiYA.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAAALgAECgcJDAAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgADCgEJAgAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIRAAYJkwoDCwD7AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgARAAYJkwoDCwD7AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCQAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJBQABLgAECgkJMwASAHYiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAADAM4UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8kAAQTAAgJsxyCCAAxAghoDAAABwBNAGkMAAAGAFQAawwAAAYAWABqDAAABQBLAGwMAAAEADYAbQwAAAEAMADqDAAABgBcAG4MAAABAEMAEwAICYYagggAMQIIaAwAAAMARABpDAAAAwBFAGsMAAADAEkAagwAAAMAMgBsDAAAAwA2AG0MAAABADAA6gwAAAMAXABuDAAAAQBDABQABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAVAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMDAAgJzhR8MwDFAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgAAwAICc4UfDMAxQEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoABYAAwkzBf4wAEUAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAGAGARAA==.',
Hi='Hikiru:BAAALgADCgkJGAAAAA==.',
Ho='Hollowbane:BAABLgAECn8eAAMXAAgJIBa3DgDHAQhoDAAABQA6AGkMAAAFAEIAawwAAAQANABqDAAAAwBSAGwMAAADACkAbQwAAAMAQQDqDAAABQBMAG4MAAACACQAFwAICXsVtw4AxwEIaAwAAAMALwBpDAAAAwBCAGsMAAADADQAagwAAAMAUgBsDAAAAwApAG0MAAADAEEA6gwAAAUATABuDAAAAgAkABgAAwmkFuAOAN4AA2gMAAACADoAaQwAAAIAPwBrDAAAAQAzAAAA.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAAALgAFFAIJAwAAAA==.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAcJEAASABAgAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8PAAIHAAQJGQ1TPAA4AQRoDAAABQA2AGkMAAAEACgAawwAAAIADgDqDAAABAAXAAcABAkZDVM8ADgBBGgMAAAFADYAaQwAAAQAKABrDAAAAgAOAOoMAAAEABcALgAECn8tAAIHAAkJyx7zGAAVAwAHAAkJyx7zGAAVAwAAAA==.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJCgAAAA==.Jonnytsunami:BAAALgAECgMJBAAAAA==.',
Ju='Juicycow:BAAALgAECgMJBgAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8YAAIZAAUJiyYtBADFAQVoDAAABgBkAGkMAAAGAGMAawwAAAQAYQBqDAAAAwBgAOoMAAAFAGEAGQAFCYsmLQQAxQEFaAwAAAYAZABpDAAABgBjAGsMAAAEAGEAagwAAAMAYADqDAAABQBhAC4ABAp/HgADGQAICcUmSwIAdwMAGQAICcUmSwIAdwMAGgABCVUhek8AXQAAAAA=.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgQJBAAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8HAAIbAAMJgQgYCwCSAANoDAAABAAjAGkMAAACABEA6gwAAAEACwAbAAMJgQgYCwCSAANoDAAABAAjAGkMAAACABEA6gwAAAEACwAuAAQKfxkAAhsACAmuETkPAIgBABsACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJDgAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBAAAAA==.Klixx:BAAALgAECgEJAQAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8YAAIXAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAEAEoAawwAAAQAUgBqDAAABAAvAGwMAAABACEA6gwAAAQAOwBuDAAABABcABcABwksG4gaAC4CB2gMAAADAEoAaQwAAAQASgBrDAAABABSAGoMAAAEAC8AbAwAAAEAIQDqDAAABAA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAIHAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkABwACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAAALgAECgYJEAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAMJCQAcAJ4dAA==.Lesiania:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8XAAMQAAgJWxZ1DgD8AQhoDAAABABBAGkMAAAEAEgAawwAAAQANQBqDAAAAwAVAGwMAAACADkAbQwAAAIALwDqDAAAAwBOAG4MAAABABgAEAAICVsWdQ4A/AEIaAwAAAMAQQBpDAAAAwBIAGsMAAADADUAagwAAAMAFQBsDAAAAgA5AG0MAAACAC8A6gwAAAMATgBuDAAAAQAYAB0AAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAIJCQAMALAOAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgYJDQAAAA==.',
Lu='Lucyah:BAAALgAECgMJBAAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAISAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQASAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAADAM4UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMDAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAWAAUJQgzZHwCpAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAYJEwANAFEWAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgMJBAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mo='Monkpig:BAACLgAFFH8NAAIZAAMJJR4sHAAIAQNoDAAABgBKAGkMAAACAEwA6gwAAAUAUAAZAAMJJR4sHAAIAQNoDAAABgBKAGkMAAACAEwA6gwAAAUAUAAuAAQKfykAAhkACAmqH5ULABoCABkACAmqH5ULABoCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIGAAYJTRVFFwBBAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAGAAYJTRVFFwBBAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAEAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAEAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAISAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIAEgAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIcAAYJnBbQFwAmAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAcAAYJnBbQFwAmAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECggJJQANALAQAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAEAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyDXFgDDAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyDXFgDDAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwAIAAQJnAtEKwB1AARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAINAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCAA0ABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQABAAAAAA=.',
Ra='Raythe:BAABLgAECn8WAAIGAAcJdRWWFQBUAQdoDAAAAwBFAGkMAAAFAE0AawwAAAMAPQBqDAAAAwAXAGwMAAACACUAbQwAAAEAFADqDAAABQA+AAYABwl1FZYVAFQBB2gMAAADAEUAaQwAAAUATQBrDAAAAwA9AGoMAAADABcAbAwAAAIAJQBtDAAAAQAUAOoMAAAFAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAMJBwAbAIEIAA==.',
Ru='Rucker:BAABLgAECn8hAAMIAAkJfRs5BACCAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgAIAAkJfRs5BACCAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJAwABLgAECgkJIQAIAH0bAA==.Rucksy:BAABLgAECn8dAAMWAAgJHR0RBQCrAghoDAAABABcAGkMAAAEAF0AawwAAAYAXwBqDAAABABXAGwMAAAEAEsAbQwAAAEAKADqDAAABQBbAG4MAAABAB8AFgAICR0dEQUAqwIIaAwAAAQAXABpDAAABABdAGsMAAAFAF8AagwAAAMAVwBsDAAABABLAG0MAAABACgA6gwAAAQAWwBuDAAAAQAfAAMAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAgAfRsA.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQAIAH0bAA==.',
Ry='Ryan:BAABLgAECn8WAAMDAAYJmCIEKQDxAQZoDAAABQBhAGkMAAADAEwAawwAAAQAWABqDAAABABhAGwMAAADAFwA6gwAAAMAWAADAAYJmCIEKQDxAQZoDAAAAwBhAGkMAAACAEwAawwAAAQAWABqDAAAAQBhAGwMAAACAFwA6gwAAAEAWAAeAAUJziFGKgDgAQVoDAAAAgBdAGkMAAABAFUAagwAAAMAXQBsDAAAAQBIAOoMAAACAFcAAAA=.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAEAAAAAA==.',
Se='Seraphae:BAAALgADCgQJBAAAAA==.Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBAAAAA==.Shankzmcgee:BAABLgAECn8XAAIXAAYJnggJIgD9AAZoDAAABgAVAGkMAAAGAB0AawwAAAUAGABqDAAAAwATAGwMAAACABUA6gwAAAEADQAXAAYJnggJIgD9AAZoDAAABgAVAGkMAAAGAB0AawwAAAUAGABqDAAAAwATAGwMAAACABUA6gwAAAEADQABLgAECggJIAADAM4UAA==.Shardik:BAAALgAECgEJAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJEgAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAEAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shèrlock:BAAALgAECgcJDgAAAA==.',
Sk='Skippydippy:BAAALgAECgQJCgAAAA==.Skylin:BAAALgAECgEJAwAAAA==.',
Sl='Sleezee:BAAALgAECgMJBgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgADCgYJBgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAIJCQAMALAOAA==.',
St='Stargasm:BAAALgAECgcJCAAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgADCgUJBwAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIMAAIJsA5AOAB/AAJoDAAABAAnAOoMAAAFACMADAACCbAOQDgAfwACaAwAAAQAJwDqDAAABQAjAAAA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgEJAQAAAA==.',
Ta='Taft:BAABLgAECn8qAAIfAAkJNxP7DQAEAgloDAAABAA9AGkMAAAHADgAawwAAAYAOwBqDAAABgA5AGwMAAAFACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAfAAkJNxP7DQAEAgloDAAABAA9AGkMAAAHADgAawwAAAYAOwBqDAAABgA5AGwMAAAFACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJDwAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAQAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJCwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJDwAAAA==.Tritin:BAAALgAECgYJDQAAAA==.',
Tw='Twiltock:BAAALgAECgYJCwAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8aAAIHAAYJCAZEngDtAAZoDAAABQAPAGkMAAAFABQAawwAAAUABABqDAAABAAUAGwMAAADABIA6gwAAAQAEAAHAAYJCAZEngDtAAZoDAAABQAPAGkMAAAFABQAawwAAAUABABqDAAABAAUAGwMAAADABIA6gwAAAQAEAAAAA==.Valiria:BAABLgAECn8ZAAISAAcJnRxZMQA1AgdoDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAACAE4A6gwAAAYAXwBuDAAAAQAQABIABwmdHFkxADUCB2gMAAADAFAAaQwAAAUAXQBrDAAABABKAGoMAAAEAGAAbAwAAAIATgDqDAAABgBfAG4MAAABABAAAAA=.Varzul:BAAALgADCgYJCwABLgAECgIJAgAEAAAAAA==.',
Ve='Velieda:BAABLgAECn8WAAMDAAgJpg+rSACCAQhoDAAABAAnAGkMAAADAC0AawwAAAMAKABqDAAAAgA6AGwMAAADADEAbQwAAAEAFgDqDAAAAwAZAG4MAAADADkAAwAICQYOq0gAggEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAABABYA6gwAAAIAFABuDAAAAwA5ABYABgkbDckaANIABmgMAAACABgAaQwAAAEALQBrDAAAAQAWAGoMAAABADoAbAwAAAEAMQDqDAAAAQAZAAAA.',
Vi='Vindication:BAACLgAFFH8JAAIcAAMJnh0HDgATAQNoDAAABABgAGkMAAACADgA6gwAAAMASgAcAAMJnh0HDgATAQNoDAAABABgAGkMAAACADgA6gwAAAMASgAuAAQKfyAAAhwACAkJIC4HAL0CABwACAkJIC4HAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaobao:BAAALgAECgQJBAAAAA==.Xiaoduoduo:BAACLgAFFH8LAAMDAAMJoB91KQAgAQNoDAAABQBfAGkMAAABAEAA6gwAAAUAUgADAAMJoB91KQAgAQNoDAAABABfAGkMAAABAEAA6gwAAAUAUgAeAAEJuCNiKwBjAAFoDAAAAQBbAC4ABAp/KQACAwAICeAjbAwAswIAAwAICeAjbAwAswIAAAA=.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJCQAAAA==.',
Za='Zabz:BAAALgADCgQJBAABLgAECggJJAADAHsgAA==.',
Ze='Zeroskills:BAABLgAECn8aAAMXAAgJ0wW0GQBEAQhoDAAABAAKAGkMAAAEABEAawwAAAQAEwBqDAAAAwAQAGwMAAADABgAbQwAAAIAAwDqDAAABAAOAG4MAAACAA4AFwAICdMFtBkARAEIaAwAAAMACgBpDAAAAwARAGsMAAAEABMAagwAAAMAEABsDAAAAwAYAG0MAAACAAMA6gwAAAQADgBuDAAAAgAOABgAAglLBEsXAFsAAmgMAAABAAcAaQwAAAEADgAAAA==.',
Zu='Zulinar:BAAALgAECgYJBwAAAA==.Zumoku:BAAALgADCgkJIgAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8mAAQbAAkJcxE0CQC2AQloDAAABgBMAGkMAAAHAC0AawwAAAcAJgBqDAAABgAyAGwMAAADADMAbQwAAAEAHADqDAAABgA8AG4MAAABACMAbwwAAAEAEwAbAAkJcxE0CQC2AQloDAAABgBMAGkMAAAHAC0AawwAAAYAJgBqDAAABgAyAGwMAAADADMAbQwAAAEAHADqDAAABQA8AG4MAAABACMAbwwAAAEAEwAfAAEJ8gYcYwAtAAFrDAAAAQARAAwAAQkxCnWqACkAAeoMAAABABoAAAA=.',
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

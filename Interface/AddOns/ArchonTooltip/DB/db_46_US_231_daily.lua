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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Warrior-Fury','Evoker-Devastation','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='daily',zone=46,date='2026-05-20',data={Ab='Abelle:BAAALgAECgQJCQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJBgABLgAECggJFQABAOwdAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgUJBQAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8eAAICAAkJ1xnLKAA0AgloDAAABQBBAGkMAAAFAEgAawwAAAQARwBqDAAAAwA0AGwMAAACADcAbQwAAAEALADqDAAABwBCAG4MAAACAFAAbwwAAAEASQACAAkJ1xnLKAA0AgloDAAABQBBAGkMAAAFAEgAawwAAAQARwBqDAAAAwA0AGwMAAACADcAbQwAAAEALADqDAAABwBCAG4MAAACAFAAbwwAAAEASQAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAUJDQADAOkdAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAYJEAAEAN0WAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBBWGwCJAQhoDAAAAwAmAGkMAAADADcAawwAAAMAIgBqDAAABAAaAGwMAAADACkAbQwAAAIAGADqDAAABQAuAG4MAAACADYABQAICXwQVhsAiQEIaAwAAAMAJgBpDAAAAwA3AGsMAAADACIAagwAAAQAGgBsDAAAAwApAG0MAAACABgA6gwAAAUALgBuDAAAAgA2AAAA.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8FAAIGAAMJIgkQEgCRAANoDAAAAgAhAGkMAAACABsAawwAAAEACAAGAAMJIgkQEgCRAANoDAAAAgAhAGkMAAACABsAawwAAAEACAAuAAQKfykAAwYACAlXGAQLAOcBAAYACAlXGAQLAOcBAAcABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BcYMACfAQdoDAAABABFAGkMAAADAEoAawwAAAQASwBqDAAAAwAwAGwMAAABABcA6gwAAAUARQBuDAAAAQA4AAgABwn4FxgwAJ8BB2gMAAAEAEUAaQwAAAMASgBrDAAABABLAGoMAAADADAAbAwAAAEAFwDqDAAABQBFAG4MAAABADgAAAA=.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJBQAJADUDAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQAKAAAAAA==.',
Bu='Bubbies:BAABLgAECn8eAAMLAAkJEBT3GADQAQloDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAAEAEAAbQwAAAIANwDqDAAABwA6AG4MAAABACcAbwwAAAEAEgALAAgJnxT3GADQAQhoDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAADAEAAbQwAAAEANwDqDAAABgA6AG8MAAABABIADAAECRwKWkUAvgAEbAwAAAEAGgBtDAAAAQATAOoMAAABABwAbgwAAAEAHQAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAICAAkJLhKtTQC1AQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAAEADwAbQwAAAMALgDqDAAABQApAG4MAAADAF4AbwwAAAMAGwACAAkJLhKtTQC1AQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAAEADwAbQwAAAMALgDqDAAABQApAG4MAAADAF4AbwwAAAMAGwAAAA==.Chiste:BAABLgAECn8iAAINAAgJow40CwBUAQhoDAAACQBMAGkMAAAGACwAawwAAAUALABqDAAAAgAxAGwMAAAEABEAbQwAAAEADQDqDAAABgArAG4MAAABABUADQAICaMONAsAVAEIaAwAAAkATABpDAAABgAsAGsMAAAFACwAagwAAAIAMQBsDAAABAARAG0MAAABAA0A6gwAAAYAKwBuDAAAAQAVAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwAKAAAAAA==.Coredellion:BAAALgADCgUJDAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn80AAIOAAkJoRsbCwDSAgloDAAACAAuAGkMAAAIAFMAawwAAAgAUgBqDAAABwBLAGwMAAAHAFAAbQwAAAQAHgDqDAAABgBTAG4MAAADAFIAbwwAAAEARQAOAAkJoRsbCwDSAgloDAAACAAuAGkMAAAIAFMAawwAAAgAUgBqDAAABwBLAGwMAAAHAFAAbQwAAAQAHgDqDAAABgBTAG4MAAADAFIAbwwAAAEARQABLgAFFAYJGgAPAJMYAA==.Dannica:BAAALgAECggJEAAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAIMAAYJxw39NQAJAQZoDAAABQAsAGkMAAAFACYAawwAAAUAIwBqDAAAAwAVAGwMAAABACAA6gwAAAMAGAAMAAYJxw39NQAJAQZoDAAABQAsAGkMAAAFACYAawwAAAUAIwBqDAAAAwAVAGwMAAABACAA6gwAAAMAGAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAYJEAAEAN0WAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8dAAICAAgJDxGnVgCeAQhoDAAABAAjAGkMAAAEABIAawwAAAQAGQBqDAAAAwAnAGwMAAAFADgAbQwAAAEAIgDqDAAABgBKAG4MAAACADsAAgAICQ8Rp1YAngEIaAwAAAQAIwBpDAAABAASAGsMAAAEABkAagwAAAMAJwBsDAAABQA4AG0MAAABACIA6gwAAAYASgBuDAAAAgA7AAAA.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAQJCgAQAIMXAA==.Donut:BAABLgAECn8VAAIRAAgJABK0PADmAQhoDAAAAgAIAGkMAAABAAkAawwAAAEABABsDAAAAwBIAG0MAAADAFIA6gwAAAUAQgBuDAAAAwBEAG8MAAADADcAEQAICQAStDwA5gEIaAwAAAIACABpDAAAAQAJAGsMAAABAAQAbAwAAAMASABtDAAAAwBSAOoMAAAFAEIAbgwAAAMARABvDAAAAwA3AAEuAAQKBwkWAAcASQ8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8GAAMSAAMJRxFUGADIAANoDAAAAwA3AGkMAAABABQA6gwAAAIAOAASAAMJRxFUGADIAANoDAAAAgA3AGkMAAABABQA6gwAAAIAOAATAAEJqQFZUAA1AAFoDAAAAQAEAC4ABAp/NgADEgAJCRcilwEAXAMAEgAJCRcilwEAXAMAEwAHCQgUySgAbgEAAAA=.Elizalynn:BAABLgAECn8kAAIUAAgJohIhHgCjAQhoDAAABgA5AGkMAAAGACcAawwAAAUALgBqDAAABQA1AGwMAAAFAC8AbQwAAAIAKADqDAAABQBZAG4MAAACAAgAFAAICaISIR4AowEIaAwAAAYAOQBpDAAABgAnAGsMAAAFAC4AagwAAAUANQBsDAAABQAvAG0MAAACACgA6gwAAAUAWQBuDAAAAgAIAAAA.',
Ev='Eveycakes:BAAALgAFFAEJAwABLgAFFAUJDQADAOkdAA==.',
Fe='Fengshui:BAABLgAECn8WAAIIAAkJsBG9HADBAQloDAAAAwBGAGkMAAADAD0AawwAAAMANQBqDAAAAwA3AGwMAAADAB4AbQwAAAIAHQDqDAAAAgApAG4MAAACADEAbwwAAAEAGQAIAAkJsBG9HADBAQloDAAAAwBGAGkMAAADAD0AawwAAAMANQBqDAAAAwA3AGwMAAADAB4AbQwAAAIAHQDqDAAAAgApAG4MAAACADEAbwwAAAEAGQAAAA==.Ferritin:BAABLgAECn8sAAIEAAkJESTcAQBjAwloDAAABwBjAGkMAAAHAGAAawwAAAcAYgBqDAAABgBjAGwMAAAGAGMAbQwAAAMAYQDqDAAABQBhAG4MAAACAFUAbwwAAAEAQAAEAAkJESTcAQBjAwloDAAABwBjAGkMAAAHAGAAawwAAAcAYgBqDAAABgBjAGwMAAAGAGMAbQwAAAMAYQDqDAAABQBhAG4MAAACAFUAbwwAAAEAQAAAAA==.Fester:BAAALgAECgEJAwAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8OAAIVAAQJABmwFgAwAQRoDAAABQA5AGkMAAAEAD4AawwAAAIANADqDAAAAwBTABUABAkAGbAWADABBGgMAAAFADkAaQwAAAQAPgBrDAAAAgA0AOoMAAADAFMALgAECn86AAMVAAkJWxvwDgBoAgAVAAkJWxvwDgBoAgAWAAkJ9xugDABJAgAAAA==.',
Fo='Focaccia:BAABLgAECn8dAAIXAAkJAR0tGgCZAgloDAAABABZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAABABXAG4MAAAEAEIAbwwAAAEAPAAXAAkJAR0tGgCZAgloDAAABABZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAABABXAG4MAAAEAEIAbwwAAAEAPAAAAA==.Foxthisup:BAAALgAECgYJBgABLgAECgYJDQAKAAAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJGAAYAJ0QAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGgAPAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQAKAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJCAAAAA==.Grultock:BAAALgAECgUJDAAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8jAAIOAAgJsh0pEACWAghoDAAABgBWAGkMAAAGAEsAawwAAAUAUABqDAAABQBZAGwMAAAEAE0AbQwAAAMAOQDqDAAABABhAG4MAAACACwADgAICbIdKRAAlgIIaAwAAAYAVgBpDAAABgBLAGsMAAAFAFAAagwAAAUAWQBsDAAABABNAG0MAAADADkA6gwAAAQAYQBuDAAAAgAsAAAA.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgQJBAAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgYJCAABLgAECgkJNQAPAFYbAA==.Hockeyhunter:BAABLgAECn81AAIPAAkJVhtNEACaAgloDAAACQBUAGkMAAAIAFUAawwAAAkAUQBqDAAABgBeAGwMAAAFADoAbQwAAAQAVgDqDAAABwBXAG4MAAAEAD4AbwwAAAEADgAPAAkJVhtNEACaAgloDAAACQBUAGkMAAAIAFUAawwAAAkAUQBqDAAABgBeAGwMAAAFADoAbQwAAAQAVgDqDAAABwBXAG4MAAAEAD4AbwwAAAEADgAAAA==.Hockeylockz:BAABLgAECn8VAAMZAAYJrAsqFADcAAZoDAAABQAkAGkMAAAFACYAawwAAAYAIwBqDAAAAwAyAGwMAAABACAA6gwAAAEABwAZAAUJ2w0qFADcAAVoDAAAAwAkAGkMAAADACYAawwAAAUAIwBqDAAAAgAvAGwMAAABACAAGgAFCcYF5bwAqAAFaAwAAAIADQBpDAAAAgATAGsMAAABABIAagwAAAEAMgDqDAAAAQAHAAEuAAQKCQk1AA8AVhsA.Hockeysticks:BAAALgADCgMJAwABLgAECgkJNQAPAFYbAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAXANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8cAAMPAAgJ2BjoKgD7AQhoDAAABABJAGkMAAAEAEgAawwAAAQASQBqDAAABAA2AGwMAAAEADgA6gwAAAUARQBuDAAAAgBCAG8MAAABACAADwAICdgY6CoA+wEIaAwAAAMASQBpDAAABABIAGsMAAAEAEkAagwAAAQANgBsDAAABAA4AOoMAAAFAEUAbgwAAAIAQgBvDAAAAQAgABgAAQkwCR81ACsAAWgMAAABABcAAS4ABRQDCQUABgAiCQA=.',
['Hè']='Hèxen:BAAALgADCgcJCAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8YAAIYAAYJnRCXEQARAQZoDAAABAAuAGkMAAAEABYAawwAAAQAJABqDAAABAAdAGwMAAAEADAA6gwAAAQAOwAYAAYJnRCXEQARAQZoDAAABAAuAGkMAAAEABYAawwAAAQAJABqDAAABAAdAGwMAAAEADAA6gwAAAQAOwAAAA==.',
Ig='Igneel:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgUJCQAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAAKAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8HAAMBAAMJbx3wCABnAANoDAAAAQA6AGoMAAADAFYA6gwAAAMAXAABAAIJBSTwCABnAAJqDAAAAwBWAOoMAAADAFwAGwABCdgWmRoASgABaAwAAAEAOgAuAAQKfyYAAwEACQkQJl8AAFMDAAEACQkQJl8AAFMDABsAAQmhFZtMAEEAAAEuAAUUBQkVABwA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8hAAIJAAkJbyPRAgDuAgloDAAABQBgAGkMAAAFAFYAawwAAAUAXQBqDAAAAwBOAGwMAAADAGAAbQwAAAEAWwDqDAAABwBdAG4MAAADAFcAbwwAAAEAUAAJAAkJbyPRAgDuAgloDAAABQBgAGkMAAAFAFYAawwAAAUAXQBqDAAAAwBOAGwMAAADAGAAbQwAAAEAWwDqDAAABwBdAG4MAAADAFcAbwwAAAEAUAAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIdAAcJlA3UNQACAQdoDAAABAAwAGkMAAAEACgAawwAAAQAIwBqDAAAAwAnAGwMAAADABsAbQwAAAEACgDqDAAABQAuAB0ABwmUDdQ1AAIBB2gMAAAEADAAaQwAAAQAKABrDAAABAAjAGoMAAADACcAbAwAAAMAGwBtDAAAAQAKAOoMAAAFAC4AAAA=.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwAKAAAAAA==.Laizee:BAABLgAECn8hAAMOAAkJzwblXwD1AAloDAAABQAFAGkMAAAFAA0AawwAAAUAFgBqDAAAAwAOAGwMAAADAAcAbQwAAAEABQDqDAAABwAFAG4MAAADAAQAbwwAAAEATQAOAAgJ3gPlXwD1AAhoDAAABQAFAGkMAAAFAA0AawwAAAUAFgBqDAAAAwAOAGwMAAADAAcAbQwAAAEABQDqDAAABwAFAG4MAAADAAQACAABCeIDQI8AJQABbwwAAAEACQAAAA==.Latrice:BAABLgAECn8lAAICAAkJ6h01IQBZAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAACAAkJ6h01IQBZAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAAAAA==.Laveyan:BAEALgAECgYJCgABLgAFFAMJBwAEAAgfAA==.',
Lo='Loki:BAABLgAECn8aAAISAAYJ8Bp5DQDIAQZoDAAABgBTAGkMAAAGAEgAawwAAAYASwBqDAAAAwA2AGwMAAACAEQA6gwAAAMAOgASAAYJ8Bp5DQDIAQZoDAAABgBTAGkMAAAGAEgAawwAAAYASwBqDAAAAwA2AGwMAAACAEQA6gwAAAMAOgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8qAAIeAAcJHhdiPwCgAQdoDAAABwBJAGkMAAAIAEUAawwAAAgARABqDAAABQBCAGwMAAAFADMAbQwAAAEAIgDqDAAACAA5AB4ABwkeF2I/AKABB2gMAAAHAEkAaQwAAAgARQBrDAAACABEAGoMAAAFAEIAbAwAAAUAMwBtDAAAAQAiAOoMAAAIADkAAAA=.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIVAAkJPBrICgCrAgloDAAABgAvAGkMAAAGAD8AawwAAAYAUgBqDAAABQBQAGwMAAAEAEMAbQwAAAMAMQDqDAAAAgBWAG4MAAACAFMAbwwAAAEAKwAVAAkJPBrICgCrAgloDAAABgAvAGkMAAAGAD8AawwAAAYAUgBqDAAABQBQAGwMAAAEAEMAbQwAAAMAMQDqDAAAAgBWAG4MAAACAFMAbwwAAAEAKwAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJOAAUAL8gAA==.',
Me='Melander:BAABLgAECn8gAAIJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABQBTAG4MAAABACoAbwwAAAEAIQAJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABQBTAG4MAAABACoAbwwAAAEAIQAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAQJCgAQAIMXAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIRAAIJeSBxOACqAAJoDAAABABJAOoMAAAFAF0AEQACCXkgcTgAqgACaAwAAAQASQDqDAAABQBdAC4ABAp/JAACEQAICXkkhhYAlgIAEQAICXkkhhYAlgIAAAA=.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECggJDwABLgAECgkJIAAJAMIbAA==.Nerzhuul:BAACLgAFFH8KAAIQAAQJgxewAwBOAQRoDAAABABbAGkMAAACAEUAawwAAAEAEwDqDAAAAwA8ABAABAmDF7ADAE4BBGgMAAAEAFsAaQwAAAIARQBrDAAAAQATAOoMAAADADwALgAECn8yAAIQAAkJlyCeBQCpAgAQAAkJlyCeBQCpAgAAAA==.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQAKAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxyJFAA1AghoDAAABQBbAGkMAAAFAEIAawwAAAUAUgBqDAAABAAtAGwMAAADAFIAbQwAAAQAMwDqDAAABQBMAG4MAAAEAEwAAwAICQMciRQANQIIaAwAAAUAWwBpDAAABQBCAGsMAAAFAFIAagwAAAQALQBsDAAAAwBSAG0MAAAEADMA6gwAAAUATABuDAAABABMAAAA.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIXAAYJFxUMxgBbAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAXAAYJFxUMxgBbAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMfAAgJBBvuJQDxAQhoDAAABABaAGkMAAAEAF8AawwAAAMAQwBqDAAABABCAGwMAAACADQAbQwAAAEAQQDqDAAABwBUAG4MAAABAB4AHwAGCbgd7iUA8QEGaAwAAAMAWgBpDAAAAwBfAGsMAAACAEMAagwAAAMAQgBsDAAAAQA0AOoMAAAHAFQAHQAHCdEOaTAAhQEHaAwAAAEALwBpDAAAAQA2AGsMAAABACsAagwAAAEAIwBsDAAAAQAjAG0MAAABABMAbgwAAAEAGQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJEAABLgAFFAYJEAAEAN0WAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8FAAIJAAIJNQONHQBfAAJoDAAAAwAMAGkMAAACAAQACQACCTUDjR0AXwACaAwAAAMADABpDAAAAgAEAC4ABAp/HwACCQAICW0NbBkAPQEACQAICW0NbBkAPQEAAAA=.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgADCgEJAQABLgAFFAYJEAAEAN0WAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8gAAQUAAgJEx9lCQCiAghoDAAABQBPAGkMAAAFAD4AawwAAAUARABqDAAABQBHAGwMAAAFAFAAbQwAAAEAWwDqDAAABQBhAG4MAAABAFIAFAAICRMfZQkAogIIaAwAAAMATwBpDAAAAwA+AGsMAAADAEQAagwAAAQARwBsDAAAAgBQAG0MAAABAFsA6gwAAAMAYQBuDAAAAQBSAAwABQkhGisxACIBBWgMAAACADoAaQwAAAIAQwBrDAAAAgBLAGoMAAABAE0AbAwAAAMAQgALAAEJNRZzWgA8AAHqDAAAAgA4AAEuAAUUAgkGAA4A/wsA.Raggnarr:BAACLgAFFH8TAAIgAAUJVx5jDQBdAQVoDAAABgBHAGkMAAAEAFoAawwAAAQAUgBqDAAAAQBjAOoMAAAEAEIAIAAFCVceYw0AXQEFaAwAAAYARwBpDAAABABaAGsMAAAEAFIAagwAAAEAYwDqDAAABABCAC4ABAp/NQACIAAJCYklKwIANAMAIAAJCYklKwIANAMAAAA=.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8LAAIUAAQJpRwhCwBQAQRoDAAAAwBOAGkMAAADADkAawwAAAEAUwDqDAAABABJABQABAmlHCELAFABBGgMAAADAE4AaQwAAAMAOQBrDAAAAQBTAOoMAAAEAEkAAAA=.Rania:BAABLgAECn8VAAIcAAgJ1CBsDQC8AghoDAAAAwBTAGkMAAADAF0AawwAAAMAWwBqDAAAAgBWAGwMAAACAFAAbQwAAAEAUgDqDAAABQBNAG4MAAACAE4AHAAICdQgbA0AvAIIaAwAAAMAUwBpDAAAAwBdAGsMAAADAFsAagwAAAIAVgBsDAAAAgBQAG0MAAABAFIA6gwAAAUATQBuDAAAAgBOAAAA.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn89AAMTAAkJnRhCEwAZAgloDAAABwBQAGkMAAAIAFMAawwAAAgAPABqDAAACABHAGwMAAAHAEYAbQwAAAYAPgDqDAAACABEAG4MAAAFADUAbwwAAAQAGAATAAgJ/RZCEwAZAghoDAAABABQAGkMAAAEAFMAawwAAAQAPABsDAAAAQAlAG0MAAAEAD4A6gwAAAQARABuDAAABQA1AG8MAAADABcAIQAICXYS9BIAswEIaAwAAAMAKABpDAAABAA9AGsMAAAEADoAagwAAAgARwBsDAAABgBGAG0MAAACACsA6gwAAAQAIABvDAAAAQAYAAAA.',
Sa='Sanctified:BAAALgAECgYJDAAAAA==.Saphíra:BAEALgAECgQJCAABLgAFFAMJBwAEAAgfAA==.Satanick:BAAALgADCgEJAQABLgAFFAQJCgAQAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAQJCgAQAIMXAA==.',
Se='Seraph:BAABLgAECn8kAAIUAAkJqBJNHAC0AQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgAUAAkJqBJNHAC0AQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJCAAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAECgkJIAAJAMIbAA==.',
So='Sojourner:BAABLgAECn8YAAMDAAYJAxGvNgA/AQZoDAAAAwAUAGkMAAAGADUAawwAAAcARQBqDAAAAQAWAGwMAAABABMA6gwAAAYATAADAAYJAxGvNgA/AQZoDAAAAgAUAGkMAAAEADUAawwAAAQARQBqDAAAAQAWAGwMAAABABMA6gwAAAUATAACAAQJzAstyADOAARoDAAAAQAnAGkMAAACAB0AawwAAAMAIADqDAAAAQASAAAA.',
Sp='Spoonzilla:BAABLgAECn8YAAIdAAYJhgkHRwC0AAZoDAAABQAXAGkMAAAGACYAawwAAAUAIQBqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAdAAYJhgkHRwC0AAZoDAAABQAXAGkMAAAGACYAawwAAAUAIQBqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIeAAgJ+R6hGgC0AghoDAAABQBfAGkMAAAFAE8AawwAAAUASgBqDAAABABeAGwMAAADADoAbQwAAAQAUADqDAAABgBgAG4MAAAEAEQAHgAICfkeoRoAtAIIaAwAAAUAXwBpDAAABQBPAGsMAAAFAEoAagwAAAQAXgBsDAAAAwA6AG0MAAAEAFAA6gwAAAYAYABuDAAABABEAAEuAAQKCQkRAAoAAAAA.',
Su='Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8hAAMfAAkJsx7kLAD7AQloDAAABQBgAGkMAAAEAEkAawwAAAUARwBqDAAABABPAGwMAAAEAEwAbQwAAAMASgDqDAAABABTAG4MAAADAFQAbwwAAAEAQgAfAAkJsx7kLAD7AQloDAAABABgAGkMAAACAEkAawwAAAMARwBqDAAAAgBPAGwMAAACAEwAbQwAAAIASgDqDAAABABTAG4MAAACAFQAbwwAAAEAQgAdAAcJWBK8KwA8AQdoDAAAAQAoAGkMAAACACcAawwAAAIASQBqDAAAAgAzAGwMAAACAC0AbQwAAAEAHQBuDAAAAQA0AAAA.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn80AAIYAAkJDiAkAgC3AgloDAAACABfAGkMAAAIAF4AawwAAAgAXQBqDAAABwBWAGwMAAAHAE4AbQwAAAQARgDqDAAABgBZAG4MAAADAEcAbwwAAAEAPgAYAAkJDiAkAgC3AgloDAAACABfAGkMAAAIAF4AawwAAAgAXQBqDAAABwBWAGwMAAAHAE4AbQwAAAQARgDqDAAABgBZAG4MAAADAEcAbwwAAAEAPgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8kAAIfAAgJhA7VQQBcAQhoDAAABgAYAGkMAAAGAB4AawwAAAYAMABqDAAABQAmAGwMAAAFADsAbQwAAAEABgDqDAAABgA6AG4MAAABAB4AHwAICYQO1UEAXAEIaAwAAAYAGABpDAAABgAeAGsMAAAGADAAagwAAAUAJgBsDAAABQA7AG0MAAABAAYA6gwAAAYAOgBuDAAAAQAeAAAA.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgADCggJCAAAAA==.',
Ti='Tinydragon:BAAALgAECggJCAABLgAFFAMJBgAeAHsKAA==.Tinyvoid:BAACLgAFFH8GAAIeAAMJewrcSwDKAANoDAAAAgAkAGkMAAACAAwA6gwAAAIAHwAeAAMJewrcSwDKAANoDAAAAgAkAGkMAAACAAwA6gwAAAIAHwAuAAQKfyEAAh4ACQmiGCUnAAYCAB4ACQmiGCUnAAYCAAAA.',
To='Togdumburz:BAACLgAFFH8KAAIaAAMJuhWXUwDkAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAaAAMJuhWXUwDkAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAuAAQKfyUAAxoACQkhGkocAFYCABoACQkhGkocAFYCAA0AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIcAAUJ3CERBAD1AQVoDAAABgBhAGkMAAAFAF4AawwAAAQAXwBsDAAAAQAyAOoMAAAFAGAAHAAFCdwhEQQA9QEFaAwAAAYAYQBpDAAABQBeAGsMAAAEAF8AbAwAAAEAMgDqDAAABQBgAC4ABAp/HAAEHAAICeQh5AkA6wIAHAAICc8h5AkA6wIAFgACCckUKlwAoAAAFQACCZ0PW1oAZQAAAAA=.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAECgkJIAAJAMIbAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECggJHwAiAAcTAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMJAAQJoxrCCwAqAQRoDAAAAgBaAGkMAAACAGEAawwAAAEARgDqDAAAAQANAAkAAwm9IcILACoBA2gMAAACAFoAaQwAAAIAYQBrDAAAAQBGACMAAQlTBf0sADQAAeoMAAABAA0ALgAECn8ZAAMJAAgJlSKICABFAgAJAAcJHySICABFAgAjAAYJExs1HwAsAQABLgAFFAUJFQAcANwhAA==.',
Vi='Vietsham:BAABLgAECn8lAAIOAAkJww+ZOgCFAQloDAAABgA/AGkMAAAGAEsAawwAAAcAHwBqDAAAAwAyAGwMAAAEAB8AbQwAAAEAFgDqDAAABgArAG4MAAADABEAbwwAAAEAGQAOAAkJww+ZOgCFAQloDAAABgA/AGkMAAAGAEsAawwAAAcAHwBqDAAAAwAyAGwMAAAEAB8AbQwAAAEAFgDqDAAABgArAG4MAAADABEAbwwAAAEAGQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAAALgAECgcJBwAAAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8QAAIEAAYJ3RYgDABMAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAcAVQAEAAYJ3RYgDABMAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAcAVQAuAAQKfyEAAgQACAmNHHULABoCAAQACAmNHHULABoCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAfAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQAAAA==.',
['Xä']='Xänthe:BAABLgAECn84AAMUAAkJvyDCBAANAwloDAAABgBdAGkMAAAHAGEAawwAAAcAYwBqDAAABwBRAGwMAAAGAFsAbQwAAAYAWADqDAAACABPAG4MAAAFADMAbwwAAAQARwAUAAkJvyDCBAANAwloDAAABQBdAGkMAAAGAGEAawwAAAcAYwBqDAAABgBRAGwMAAAFAFsAbQwAAAUAWADqDAAABwBPAG4MAAAFADMAbwwAAAQARwALAAYJshFhJgBfAQZoDAAAAQA/AGkMAAABACcAagwAAAEAKQBsDAAAAQAmAG0MAAABADYA6gwAAAEAIwAAAA==.',
Ye='Yetlian:BAACLgAFFH8NAAIDAAUJ6R1hDQCYAQVoDAAABABRAGkMAAACADwAawwAAAEAWgBsDAAAAQA2AOoMAAAFAF4AAwAFCekdYQ0AmAEFaAwAAAQAUQBpDAAAAgA8AGsMAAABAFoAbAwAAAEANgDqDAAABQBeAC4ABAp/IAADAwAICXEkfwcA4wIAAwAICXEkfwcA4wIAAgABCQABrncBEwAAAAA=.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8iAAIjAAYJ4SWGAQAmAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABQBdAGwMAAAEAFoA6gwAAAcAYwAjAAYJ4SWGAQAmAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABQBdAGwMAAAEAFoA6gwAAAcAYwAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgQJCQAAAA==.',
Zy='Zyrahh:BAAALgADCgYJBgAAAA==.',
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

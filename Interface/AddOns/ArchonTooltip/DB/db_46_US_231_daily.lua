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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Warrior-Fury','Evoker-Devastation','Warlock-Demonology','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='daily',zone=46,date='2026-05-13',data={Ab='Abelle:BAAALgAECgQJBQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgEJAQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgADCgcJBwABLgAECgcJFAABAEseAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgUJBQAAAA==.Arykiel:BAABLgAECn8bAAICAAgJOxcuMgDLAQhoDAAABQBBAGkMAAAFAEgAawwAAAQARwBqDAAAAwA0AGwMAAACADcAbQwAAAEALADqDAAABgBCAG4MAAABACgAAgAICTsXLjIAywEIaAwAAAUAQQBpDAAABQBIAGsMAAAEAEcAagwAAAMANABsDAAAAgA3AG0MAAABACwA6gwAAAYAQgBuDAAAAQAoAAAA.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAUJDQADAOkdAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAYJDwAEAN0WAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgADCggJDgAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBDMEQCnAQhoDAAAAwAmAGkMAAADADcAawwAAAMAIgBqDAAABAAaAGwMAAADACkAbQwAAAIAGADqDAAABQAuAG4MAAACADYABQAICXwQzBEApwEIaAwAAAMAJgBpDAAAAwA3AGsMAAADACIAagwAAAQAGgBsDAAAAwApAG0MAAACABgA6gwAAAUALgBuDAAAAgA2AAAA.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAABLgAECn8hAAMGAAgJ3hQuCgCqAQhoDAAABgAtAGkMAAAFAEYAawwAAAYAQABqDAAABABBAGwMAAADADQAbQwAAAEANwDqDAAABwA2AG4MAAABACAABgAICd4ULgoAqgEIaAwAAAMALQBpDAAAAwBGAGsMAAAEAEAAagwAAAMAQQBsDAAAAwA0AG0MAAABADcA6gwAAAMANgBuDAAAAQAgAAcABQl5DlcdAP8ABWgMAAADACkAaQwAAAIAJgBrDAAAAgAfAGoMAAABAA8A6gwAAAQAJAAAAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BdsIgBZAQdoDAAABABFAGkMAAADAEoAawwAAAQASwBqDAAAAwAwAGwMAAABABcA6gwAAAUARQBuDAAAAQA4AAgABwn4F2wiAFkBB2gMAAAEAEUAaQwAAAMASgBrDAAABABLAGoMAAADADAAbAwAAAEAFwDqDAAABQBFAG4MAAABADgAAAA=.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAECggJGgAJAG0NAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgYJCwABLgAECgkJEQAKAAAAAA==.',
Bu='Bubbies:BAABLgAECn8aAAILAAgJnxQaEQDjAQhoDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAADAEAAbQwAAAEANwDqDAAABgA6AG8MAAABABIACwAICZ8UGhEA4wEIaAwAAAUAUgBpDAAABABGAGsMAAADACAAagwAAAMAJwBsDAAAAwBAAG0MAAABADcA6gwAAAYAOgBvDAAAAQASAAAA.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8YAAICAAkJ/BE+MwDHAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAADADwAbQwAAAIALgDqDAAABAAlAG4MAAACAF4AbwwAAAIAGwACAAkJ/BE+MwDHAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAADADwAbQwAAAIALgDqDAAABAAlAG4MAAACAF4AbwwAAAIAGwAAAA==.Chiste:BAABLgAECn8bAAIMAAcJ7AwSDwDyAAdoDAAACABMAGkMAAAFAA4AawwAAAQAIQBqDAAAAQAKAGwMAAADAAgA6gwAAAUAKwBuDAAAAQAVAAwABwnsDBIPAPIAB2gMAAAIAEwAaQwAAAUADgBrDAAABAAhAGoMAAABAAoAbAwAAAMACADqDAAABQArAG4MAAABABUAAAA=.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwAKAAAAAA==.Coredellion:BAAALgADCgUJCAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn8sAAINAAkJ+BO4FwAUAgloDAAABwAuAGkMAAAHAEAAawwAAAcALwBqDAAABgA0AGwMAAAGAFAAbQwAAAMAGQDqDAAABQA1AG4MAAACABMAbwwAAAEARQANAAkJ+BO4FwAUAgloDAAABwAuAGkMAAAHAEAAawwAAAcALwBqDAAABgA0AGwMAAAGAFAAbQwAAAMAGQDqDAAABQA1AG4MAAACABMAbwwAAAEARQABLgAFFAYJGQAOAJMYAA==.Dannica:BAAALgAECgcJCAAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgYJEQAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAYJDwAEAN0WAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8cAAICAAgJjQ5sRwCFAQhoDAAABAAjAGkMAAAEABIAawwAAAQAGQBqDAAAAwAnAGwMAAAFADgAbQwAAAEAIgDqDAAABgBKAG4MAAABAA4AAgAICY0ObEcAhQEIaAwAAAQAIwBpDAAABAASAGsMAAAEABkAagwAAAMAJwBsDAAABQA4AG0MAAABACIA6gwAAAYASgBuDAAAAQAOAAAA.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAMJCAAPAMocAA==.Donut:BAAALgAFFAMJAQABLgAECgcJFgAHAEkPAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn8uAAMQAAkJFyL+AABtAwloDAAACABiAGkMAAAIAFwAawwAAAcAYQBqDAAABgBcAGwMAAAFAGEAbQwAAAIAWgDqDAAABgBgAG4MAAADAE0AbwwAAAEAKQAQAAkJFyL+AABtAwloDAAABwBiAGkMAAAGAFwAawwAAAUAYQBqDAAABQBcAGwMAAAFAGEAbQwAAAIAWgDqDAAABgBgAG4MAAADAE0AbwwAAAEAKQARAAQJKhHdPwDpAARoDAAAAQAyAGkMAAACACgAawwAAAIAKABqDAAAAQAmAAAA.Elizalynn:BAABLgAECn8gAAISAAgJIxBDHQB5AQhoDAAABgA5AGkMAAAGACcAawwAAAUALgBqDAAABQA1AGwMAAAEACMAbQwAAAIAKADqDAAAAwAyAG4MAAABAAcAEgAICSMQQx0AeQEIaAwAAAYAOQBpDAAABgAnAGsMAAAFAC4AagwAAAUANQBsDAAABAAjAG0MAAACACgA6gwAAAMAMgBuDAAAAQAHAAAA.',
Ev='Eveycakes:BAAALgAFFAEJAgABLgAFFAUJDQADAOkdAA==.',
Fe='Fengshui:BAAALgAECgkJDgAAAA==.Ferritin:BAABLgAECn8kAAIEAAkJlSPcAQBjAwloDAAABgBjAGkMAAAGAGAAawwAAAYAYgBqDAAABQBjAGwMAAAFAGMAbQwAAAIAYQDqDAAABABhAG4MAAABAEsAbwwAAAEAQAAEAAkJlSPcAQBjAwloDAAABgBjAGkMAAAGAGAAawwAAAYAYgBqDAAABQBjAGwMAAAFAGMAbQwAAAIAYQDqDAAABABhAG4MAAABAEsAbwwAAAEAQAAAAA==.Fester:BAAALgAECgEJAgAAAA==.',
Fi='Fish:BAAALgAECgQJBgAAAA==.Fishguts:BAACLgAFFH8KAAITAAQJ4hFsFAARAQRoDAAABAA5AGkMAAADAC8AawwAAAEAGwDqDAAAAgAzABMABAniEWwUABEBBGgMAAAEADkAaQwAAAMALwBrDAAAAQAbAOoMAAACADMALgAECn83AAMTAAkJWxvwDgBoAgATAAkJWxvwDgBoAgAUAAgJxRsTDAASAgAAAA==.',
Fo='Focaccia:BAABLgAECn8ZAAIVAAgJLRwUHgBQAghoDAAAAwBZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAAAwBVAG4MAAADACgAFQAICS0cFB4AUAIIaAwAAAMAWQBpDAAAAwBAAGsMAAADADsAagwAAAMATQBsDAAABABVAG0MAAADAE4A6gwAAAMAVQBuDAAAAwAoAAAA.Foxthisup:BAAALgAECgIJAgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJEAAKAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGQAOAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQAKAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgUJCwAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8gAAINAAgJTRsTDwBqAghoDAAABgBWAGkMAAAGAEsAawwAAAUAUABqDAAABQBZAGwMAAAEAE0AbQwAAAIANADqDAAAAwA2AG4MAAABACkADQAICU0bEw8AagIIaAwAAAYAVgBpDAAABgBLAGsMAAAFAFAAagwAAAUAWQBsDAAABABNAG0MAAACADQA6gwAAAMANgBuDAAAAQApAAAA.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgQJBgABLgAECgkJKAAOAGAYAA==.Hockeyhunter:BAABLgAECn8oAAIOAAkJYBjEEgBYAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABQA2AG4MAAADAD4AbwwAAAEADgAOAAkJYBjEEgBYAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABQA2AG4MAAADAD4AbwwAAAEADgAAAA==.Hockeylockz:BAAALgAECgYJEQABLgAECgkJKAAOAGAYAA==.Hockeysticks:BAAALgADCgMJAwABLgAECgkJKAAOAGAYAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAVANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8UAAMOAAcJKRfdMAClAQdoDAAAAwApAGkMAAADAEgAawwAAAMASQBqDAAAAwA2AGwMAAADADgA6gwAAAMALABuDAAAAgBCAA4ABwkpF90wAKUBB2gMAAACACkAaQwAAAMASABrDAAAAwBJAGoMAAADADYAbAwAAAMAOADqDAAAAwAsAG4MAAACAEIAFgABCTAJ8C0AKwABaAwAAAEAFwABLgAECggJIQAGAN4UAA==.',
['Hè']='Hèxen:BAAALgADCgcJBgAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgYJEAAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgUJCAAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAAKAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCAAAAA==.Kazum:BAAALgAECgEJAgAAAA==.',
Ke='Keralan:BAACLgAFFH8GAAMBAAMJbx13BwBoAANoDAAAAQA6AGoMAAADAFYA6gwAAAIAXAABAAIJBSR3BwBoAAJqDAAAAwBWAOoMAAACAFwAFwABCdgWcBUAUAABaAwAAAEAOgAuAAQKfyYAAwEACQkQJiwAAF8DAAEACQkQJiwAAF8DABcAAQmhFRU/AEUAAAEuAAUUBQkVABgA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8eAAIJAAgJ4CNoAwCkAghoDAAABQBgAGkMAAAFAFYAawwAAAUAXQBqDAAAAwBOAGwMAAADAGAAbQwAAAEAWwDqDAAABgBdAG4MAAACAFUACQAICeAjaAMApAIIaAwAAAUAYABpDAAABQBWAGsMAAAFAF0AagwAAAMATgBsDAAAAwBgAG0MAAABAFsA6gwAAAYAXQBuDAAAAgBVAAAA.',
Kw='Kwehlewd:BAABLgAECn8YAAIZAAcJlA2wKAAWAQdoDAAABAAwAGkMAAAEACgAawwAAAQAIwBqDAAAAwAnAGwMAAADABsAbQwAAAEACgDqDAAABQAuABkABwmUDbAoABYBB2gMAAAEADAAaQwAAAQAKABrDAAABAAjAGoMAAADACcAbAwAAAMAGwBtDAAAAQAKAOoMAAAFAC4AAAA=.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwAKAAAAAA==.Laizee:BAABLgAECn8eAAINAAgJ2gNwSgD9AAhoDAAABQAFAGkMAAAFAA0AawwAAAUAFgBqDAAAAwAOAGwMAAADAAcAbQwAAAEABQDqDAAABgAFAG4MAAACAAQADQAICdoDcEoA/QAIaAwAAAUABQBpDAAABQANAGsMAAAFABYAagwAAAMADgBsDAAAAwAHAG0MAAABAAUA6gwAAAYABQBuDAAAAgAEAAAA.Latrice:BAABLgAECn8lAAICAAkJ6h0JEwB7AgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAACAAkJ6h0JEwB7AgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAAAAA==.Laveyan:BAEALgADCgUJBQABLgAECgkJLwAEAMckAA==.',
Lo='Loki:BAAALgAECgUJDwAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8iAAIaAAYJ2hbXPgBYAQZoDAAABgBIAGkMAAAHAEMAawwAAAcAKgBqDAAABAApAGwMAAAEADMA6gwAAAYAOQAaAAYJ2hbXPgBYAQZoDAAABgBIAGkMAAAHAEMAawwAAAcAKgBqDAAABAApAGwMAAAEADMA6gwAAAYAOQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8bAAITAAkJYRSeFgDDAQloDAAABQAvAGkMAAAFAD8AawwAAAUARABqDAAABAA5AGwMAAADAD0AbQwAAAIAJwDqDAAAAQAsAG4MAAABACwAbwwAAAEAKwATAAkJYRSeFgDDAQloDAAABQAvAGkMAAAFAD8AawwAAAUARABqDAAABAA5AGwMAAADAD0AbQwAAAIAJwDqDAAAAQAsAG4MAAABACwAbwwAAAEAKwAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJOAASAL8gAA==.',
Me='Melander:BAABLgAECn8fAAIJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABABTAG4MAAABACoAbwwAAAEAIQAJAAkJwhuiBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABABTAG4MAAABACoAbwwAAAEAIQAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAMJCAAPAMocAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIbAAIJeSBibQC7AAJoDAAABABJAOoMAAAFAF0AGwACCXkgYm0AuwACaAwAAAQASQDqDAAABQBdAC4ABAp/JAACGwAICXkkvwsAxgIAGwAICXkkvwsAxgIAAAA=.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECgcJBwABLgAECgkJHwAJAMIbAA==.Nerzhuul:BAACLgAFFH8IAAIPAAMJyhyqBAAjAQNoDAAABABbAGkMAAACAEUA6gwAAAIAPAAPAAMJyhyqBAAjAQNoDAAABABbAGkMAAACAEUA6gwAAAIAPAAuAAQKfykAAg8ACQnwHZ4FAKkCAA8ACQnwHZ4FAKkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxzPDQBUAghoDAAABQBbAGkMAAAFAEIAawwAAAUAUgBqDAAABAAtAGwMAAADAFIAbQwAAAQAMwDqDAAABQBMAG4MAAAEAEwAAwAICQMczw0AVAIIaAwAAAUAWwBpDAAABQBCAGsMAAAFAFIAagwAAAQALQBsDAAAAwBSAG0MAAAEADMA6gwAAAUATABuDAAABABMAAAA.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIVAAYJFxWeiAAUAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAVAAYJFxWeiAAUAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMcAAgJBBv/HAD6AQhoDAAABABaAGkMAAAEAF8AawwAAAMAQwBqDAAABABCAGwMAAACADQAbQwAAAEAQQDqDAAABwBUAG4MAAABAB4AHAAGCbgd/xwA+gEGaAwAAAMAWgBpDAAAAwBfAGsMAAACAEMAagwAAAMAQgBsDAAAAQA0AOoMAAAHAFQAGQAHCdEOaTAAhQEHaAwAAAEALwBpDAAAAQA2AGsMAAABACsAagwAAAEAIwBsDAAAAQAjAG0MAAABABMAbgwAAAEAGQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJDwABLgAFFAYJDwAEAN0WAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAABLgAECn8aAAIJAAgJbQ2EEwBCAQhoDAAAAwAbAGkMAAADAC0AawwAAAIALQBqDAAABAAjAGwMAAAEABsAbQwAAAQAIQDqDAAABAAwAG4MAAACAAsACQAICW0NhBMAQgEIaAwAAAMAGwBpDAAAAwAtAGsMAAACAC0AagwAAAQAIwBsDAAABAAbAG0MAAAEACEA6gwAAAQAMABuDAAAAgALAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgUJCAAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8eAAQSAAcJ4h5xCgBaAgdoDAAABQBPAGkMAAAFAD4AawwAAAUARABqDAAABQBHAGwMAAAEAFAAbQwAAAEAWwDqDAAABQBhABIABwniHnEKAFoCB2gMAAADAE8AaQwAAAMAPgBrDAAAAwBEAGoMAAAEAEcAbAwAAAIAUABtDAAAAQBbAOoMAAADAGEAHQAFCSEa+iMAOwEFaAwAAAIAOgBpDAAAAgBDAGsMAAACAEsAagwAAAEATQBsDAAAAgBCAAsAAQk1FmFLAD4AAeoMAAACADgAAS4ABRQCCQQACgAAAAA=.Raggnarr:BAACLgAFFH8PAAIeAAQJVx67BwBwAQRoDAAABQBHAGkMAAADAFoAawwAAAMAUgDqDAAABABCAB4ABAlXHrsHAHABBGgMAAAFAEcAaQwAAAMAWgBrDAAAAwBSAOoMAAAEAEIALgAECn8tAAIeAAgJsCINDQDuAgAeAAgJsCINDQDuAgAAAA==.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8HAAISAAMJSxv+DwD3AANoDAAAAgBOAGkMAAACADkA6gwAAAMASQASAAMJSxv+DwD3AANoDAAAAgBOAGkMAAACADkA6gwAAAMASQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AghoDAAAAwBTAGkMAAADAF0AawwAAAMAWwBqDAAAAgBWAGwMAAACAFAAbQwAAAEAUgDqDAAABQBNAG4MAAACAE4AGAAICdQgbA0AvAIIaAwAAAMAUwBpDAAAAwBdAGsMAAADAFsAagwAAAIAVgBsDAAAAgBQAG0MAAABAFIA6gwAAAUATQBuDAAAAgBOAAAA.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn89AAMRAAkJnRjhCQBJAgloDAAABwBQAGkMAAAIAFMAawwAAAgAPABqDAAACABHAGwMAAAHAEYAbQwAAAYAPgDqDAAACABEAG4MAAAFADUAbwwAAAQAGAARAAgJ/RbhCQBJAghoDAAABABQAGkMAAAEAFMAawwAAAQAPABsDAAAAQAlAG0MAAAEAD4A6gwAAAQARABuDAAABQA1AG8MAAADABcAHwAICXYS9BIAswEIaAwAAAMAKABpDAAABAA9AGsMAAAEADoAagwAAAgARwBsDAAABgBGAG0MAAACACsA6gwAAAQAIABvDAAAAQAYAAAA.',
Sa='Sanctified:BAAALgAECgYJCwAAAA==.Saphíra:BAEALgAECgQJCAABLgAECgkJLwAEAMckAA==.Satanick:BAAALgADCgEJAQABLgAFFAMJCAAPAMocAA==.',
Se='Seraph:BAABLgAECn8kAAISAAkJqBJCFQDGAQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgASAAkJqBJCFQDGAQloDAAABgAuAGkMAAAGAD4AawwAAAYAOwBqDAAABQA4AGwMAAAFAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAbwwAAAEAOgAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgYJBgAAAA==.',
Sn='Snikit:BAAALgAECgEJAQABLgAECgkJHwAJAMIbAA==.',
So='Sojourner:BAABLgAECn8XAAMDAAYJAxFrKgBTAQZoDAAAAwAUAGkMAAAGADUAawwAAAcARQBqDAAAAQAWAGwMAAABABMA6gwAAAUATAADAAYJAxFrKgBTAQZoDAAAAgAUAGkMAAAEADUAawwAAAQARQBqDAAAAQAWAGwMAAABABMA6gwAAAQATAACAAQJzAs6mQDXAARoDAAAAQAnAGkMAAACAB0AawwAAAMAIADqDAAAAQASAAAA.',
Sp='Spoonzilla:BAABLgAECn8VAAIZAAYJ9QeAOwC1AAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAZAAYJ9QeAOwC1AAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIaAAgJ+R6hGgC0AghoDAAABQBfAGkMAAAFAE8AawwAAAUASgBqDAAABABeAGwMAAADADoAbQwAAAQAUADqDAAABgBgAG4MAAAEAEQAGgAICfkeoRoAtAIIaAwAAAUAXwBpDAAABQBPAGsMAAAFAEoAagwAAAQAXgBsDAAAAwA6AG0MAAAEAFAA6gwAAAYAYABuDAAABABEAAEuAAQKCQkRAAoAAAAA.',
Su='Supersham:BAAALgAECgEJAQAAAA==.Superspam:BAABLgAECn8eAAMcAAgJVx7kLAD7AQhoDAAABQBgAGkMAAAEAEkAawwAAAUARwBqDAAABABPAGwMAAADAEwAbQwAAAIANgDqDAAABABTAG4MAAADAFQAHAAICVce5CwA+wEIaAwAAAQAYABpDAAAAgBJAGsMAAADAEcAagwAAAIATwBsDAAAAQBMAG0MAAABADYA6gwAAAQAUwBuDAAAAgBUABkABwlYEhAgAFEBB2gMAAABACgAaQwAAAIAJwBrDAAAAgBJAGoMAAACADMAbAwAAAIALQBtDAAAAQAdAG4MAAABADQAAAA=.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn8sAAIWAAkJdx6FAQC2AgloDAAABwBfAGkMAAAHAF4AawwAAAcARgBqDAAABgBWAGwMAAAGAE4AbQwAAAMARgDqDAAABQBZAG4MAAACAD0AbwwAAAEAPgAWAAkJdx6FAQC2AgloDAAABwBfAGkMAAAHAF4AawwAAAcARgBqDAAABgBWAGwMAAAGAE4AbQwAAAMARgDqDAAABQBZAG4MAAACAD0AbwwAAAEAPgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8hAAIcAAcJ5A7dOgBEAQdoDAAABgAYAGkMAAAGAB4AawwAAAYAMABqDAAABQAmAGwMAAAEADsAbQwAAAEABgDqDAAABQA6ABwABwnkDt06AEQBB2gMAAAGABgAaQwAAAYAHgBrDAAABgAwAGoMAAAFACYAbAwAAAQAOwBtDAAAAQAGAOoMAAAFADoAAAA=.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgADCgEJAQAAAA==.',
Ti='Tinyvoid:BAABLgAECn8eAAIaAAgJeBibJADKAQhoDAAABQBSAGkMAAAFADcAawwAAAUATgBqDAAAAwA7AGwMAAADAEsAbQwAAAEAEwDqDAAABgBVAG4MAAACACkAGgAICXgYmyQAygEIaAwAAAUAUgBpDAAABQA3AGsMAAAFAE4AagwAAAMAOwBsDAAAAwBLAG0MAAABABMA6gwAAAYAVQBuDAAAAgApAAAA.',
To='Togdumburz:BAACLgAFFH8KAAIgAAMJuhUNRgDkAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAgAAMJuhUNRgDkAANoDAAABAAuAGkMAAACAEAA6gwAAAQANgAuAAQKfyUAAyAACQkhGncPAIMCACAACQkhGncPAIMCAAwAAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIYAAUJ3CEvAgADAgVoDAAABgBhAGkMAAAFAF4AawwAAAQAXwBsDAAAAQAyAOoMAAAFAGAAGAAFCdwhLwIAAwIFaAwAAAYAYQBpDAAABQBeAGsMAAAEAF8AbAwAAAEAMgDqDAAABQBgAC4ABAp/GQAEGAAICYoh5AkA6wIAGAAICXUh5AkA6wIAFAACCckUKlwAoAAAEwACCZ0PW1oAZQAAAAA=.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgcJEwAKAAAAAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8UAAMJAAcJHySIBQBdAgdoDAAABABdAGkMAAAEAF4AawwAAAQAYwBqDAAAAgBhAGwMAAACAFYAbQwAAAEAVADqDAAAAwBhAAkABwkfJIgFAF0CB2gMAAAEAF0AaQwAAAQAXgBrDAAABABjAGoMAAACAGEAbAwAAAIAVgBtDAAAAQBUAOoMAAACAGEAIQABCdseQTUAWwAB6gwAAAEATgABLgAFFAUJFQAYANwhAA==.',
Vi='Vietsham:BAABLgAECn8fAAINAAgJehAjNgBUAQhoDAAABQA/AGkMAAAFAEsAawwAAAYAHwBqDAAAAwAyAGwMAAAEAB8AbQwAAAEAFgDqDAAABQArAG4MAAACABEADQAICXoQIzYAVAEIaAwAAAUAPwBpDAAABQBLAGsMAAAGAB8AagwAAAMAMgBsDAAABAAfAG0MAAABABYA6gwAAAUAKwBuDAAAAgARAAAA.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8PAAIEAAYJ3RaWCABYAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAYAVQAEAAYJ3RaWCABYAQZoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AGwMAAABACQA6gwAAAYAVQAuAAQKfyAAAgQACAmNHNMHADECAAQACAmNHNMHADECAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAcAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgAKAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn84AAMSAAkJvyDJAgAjAwloDAAABgBdAGkMAAAHAGEAawwAAAcAYwBqDAAABwBRAGwMAAAGAFsAbQwAAAYAWADqDAAACABPAG4MAAAFADMAbwwAAAQARwASAAkJvyDJAgAjAwloDAAABQBdAGkMAAAGAGEAawwAAAcAYwBqDAAABgBRAGwMAAAFAFsAbQwAAAUAWADqDAAABwBPAG4MAAAFADMAbwwAAAQARwALAAYJshFHHABqAQZoDAAAAQA/AGkMAAABACcAagwAAAEAKQBsDAAAAQAmAG0MAAABADYA6gwAAAEAIwAAAA==.',
Ye='Yetlian:BAACLgAFFH8NAAIDAAUJ6R1YCQChAQVoDAAABABRAGkMAAACADwAawwAAAEAWgBsDAAAAQA2AOoMAAAFAF4AAwAFCekdWAkAoQEFaAwAAAQAUQBpDAAAAgA8AGsMAAABAFoAbAwAAAEANgDqDAAABQBeAC4ABAp/GgADAwAICa0ciBcAVQIAAwAICa0ciBcAVQIAAgABCQABNkIBEwAAAAA=.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8fAAIhAAYJnyXwAAAmAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABABdAGwMAAADAFcA6gwAAAYAYwAhAAYJnyXwAAAmAgZoDAAABwBgAGkMAAAHAGQAawwAAAQAYgBqDAAABABdAGwMAAADAFcA6gwAAAYAYwAuAAQKfyAAAiEACAmrIWUCAAADACEACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgQJBQAAAA==.',
Zy='Zyrahh:BAAALgADCgYJBgAAAA==.',
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

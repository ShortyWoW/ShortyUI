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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Paladin-Holy','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','Evoker-Devastation','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Unknown-Unknown','Shaman-Elemental','Mage-Frost','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Paladin-Protection','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='daily',zone=46,date='2026-05-10',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCgcJDAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8WAAIBAAcJ0hpWEQDNAQdoDAAABABMAGkMAAAEAEIAawwAAAQATwBqDAAAAwBKAGwMAAADAEsAbQwAAAEAOwDqDAAAAwA3AAEABwnSGlYRAM0BB2gMAAAEAEwAaQwAAAQAQgBrDAAABABPAGoMAAADAEoAbAwAAAMASwBtDAAAAQA7AOoMAAADADcAAAA=.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgIJAwAAAA==.',
An='Andrew:BAAALgAECgYJCQAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgkJJwABLgAECgYJFgADADICAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgEJAQAAAA==.Arieljoyeria:BAACLgAFFH8LAAMEAAQJ4B5eAQCLAQRoDAAABABVAGkMAAADAFcAawwAAAEAMQDqDAAAAwBdAAQABAngHl4BAIsBBGgMAAADAFUAaQwAAAMAVwBrDAAAAQAxAOoMAAACAF0ABQACCYwNVRQArQACaAwAAAEAOQDqDAAAAQAMAC4ABAp/IgADBQAICSgf4g0AwAIABQAICXkd4g0AwAIABAAECSoYEAoAMwEAAAA=.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgADCgQJBAAAAA==.Astar:BAAALgADCgcJDgABLgAECggJHQAHAAgeAA==.Astraea:BAABLgAECn8eAAIIAAYJ4RfwDABXAQZoDAAABQBEAGkMAAAFAEUAawwAAAUAPQBqDAAABQA+AGwMAAAFADMA6gwAAAUANgAIAAYJ4RfwDABXAQZoDAAABQBEAGkMAAAFAEUAawwAAAUAPQBqDAAABQA+AGwMAAAFADMA6gwAAAUANgABLgAECgYJJQAGAPckAA==.',
At='Athika:BAAALgADCgQJBAAAAA==.',
Au='Auddorn:BAAALgAECgIJAwAAAA==.Auria:BAAALgAECgYJEAAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAABLgAECn8hAAIBAAgJ1wtAKACXAQhoDAAABgAPAGkMAAAGACYAawwAAAUAJwBqDAAAAwAXAGwMAAADABcAbQwAAAEAEgDqDAAABQASAG4MAAAEADoAAQAICdcLQCgAlwEIaAwAAAYADwBpDAAABgAmAGsMAAAFACcAagwAAAMAFwBsDAAAAwAXAG0MAAABABIA6gwAAAUAEgBuDAAABAA6AAAA.Azralia:BAABLgAECn8XAAIJAAgJkxNtFwDcAQhoDAAABAAtAGkMAAAFAD4AawwAAAQANQBqDAAAAgAtAGwMAAACACsAbQwAAAIAJQDqDAAAAgA1AG4MAAACADoACQAICZMTbRcA3AEIaAwAAAQALQBpDAAABQA+AGsMAAAEADUAagwAAAIALQBsDAAAAgArAG0MAAACACUA6gwAAAIANQBuDAAAAgA6AAAA.',
Bb='Bbygee:BAAALgAECgYJDgAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgYJCwAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8sAAIKAAkJ2woSAgDHAQloDAAABwAVAGkMAAAHABoAawwAAAYAHwBqDAAABQASAGwMAAAFABsAbQwAAAMAFADqDAAABgATAG4MAAAEADYAbwwAAAEAFAAKAAkJ2woSAgDHAQloDAAABwAVAGkMAAAHABoAawwAAAYAHwBqDAAABQASAGwMAAAFABsAbQwAAAMAFADqDAAABgATAG4MAAAEADYAbwwAAAEAFAAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAAALgAECgcJEgAAAA==.Borgin:BAAALgAECgYJDwAAAA==.Borimor:BAAALgAECgcJEQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAAALgAECgYJDwAAAA==.Bridgetta:BAAALgADCgIJAgAAAA==.Briëlla:BAABLgAECn8eAAMLAAgJCBS2LQDPAQhoDAAABgBDAGkMAAAGAD8AawwAAAUAMwBqDAAAAwAsAGwMAAACAEEAbQwAAAEAFADqDAAABQAwAG4MAAACACoACwAICQgUti0AzwEIaAwAAAYAQwBpDAAABgA/AGsMAAAFADMAagwAAAMALABsDAAAAgBBAG0MAAABABQA6gwAAAQAMABuDAAAAgAqAAwAAQk6A29DABcAAeoMAAABAAgAAAA=.Bromdrago:BAAALgADCgYJAgAAAA==.Bromkin:BAAALgAECgYJCwAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgEJAQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAAALgAECgYJEQAAAA==.',
Ce='Ceran:BAABLgAECn8ZAAINAAcJZAuBGAAqAQdoDAAABAAcAGkMAAAEACUAawwAAAQAGgBqDAAABAAmAGwMAAADABEAbQwAAAIAGgDqDAAABAAlAA0ABwlkC4EYACoBB2gMAAAEABwAaQwAAAQAJQBrDAAABAAaAGoMAAAEACYAbAwAAAMAEQBtDAAAAgAaAOoMAAAEACUAAAA=.Cereus:BAABLgAECn8dAAMHAAgJCB6lBABsAghoDAAABAA7AGkMAAAEAFMAawwAAAQATgBqDAAABABRAGwMAAAEAFoAbQwAAAIAQADqDAAABQBcAG4MAAACAEEABwAHCbAepQQAbAIHaAwAAAQAOwBpDAAABABTAGsMAAAEAE4AagwAAAQAUQBsDAAABABaAG0MAAACAEAA6gwAAAUAXAAOAAEJ4RZiFgBDAAFuDAAAAgA6AAAA.',
Ch='Chaelenge:BAABLgAECn8ZAAMJAAcJuB2NEQAXAgdoDAAAAwA3AGkMAAADAFcAawwAAAUAXABqDAAABQBFAGwMAAAEAEMAbQwAAAEAQgDqDAAABABdAAkABwm4HY0RABcCB2gMAAADADcAaQwAAAMAVwBrDAAABABcAGoMAAAEAEUAbAwAAAMAQwBtDAAAAQBCAOoMAAAEAF0ADwADCaUJP9IAaAADawwAAAEAGgBqDAAAAQAzAGwMAAABABcAAAA=.Cheatt:BAAALgADCggJBQAAAA==.Chubbabuns:BAABLgAECn8nAAMQAAcJ9SBkCgCvAQdoDAAABwBiAGkMAAAIAFsAawwAAAcAYgBqDAAABABeAGwMAAAEAFkAbQwAAAEAJwDqDAAACABZABEABgnbIwIVAMkBBmgMAAAGAGIAaQwAAAYAWwBrDAAABQBaAGoMAAACAFMAbAwAAAMAWQDqDAAABgBZABAABwnAGGQKAK8BB2gMAAABAEgAaQwAAAIAWgBrDAAAAgBiAGoMAAACAF4AbAwAAAEACABtDAAAAQAnAOoMAAACAEcAAAA=.Chyran:BAAALgAECgYJBgAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8eAAISAAgJPBdrEADvAQhoDAAABQBHAGkMAAAFADYAawwAAAUASgBqDAAABABLAGwMAAAEAEwAbQwAAAEAKwDqDAAABQAzAG4MAAABABsAEgAICTwXaxAA7wEIaAwAAAUARwBpDAAABQA2AGsMAAAFAEoAagwAAAQASwBsDAAABABMAG0MAAABACsA6gwAAAUAMwBuDAAAAQAbAAAA.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJCgAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgMJCAAAAA==.Dalielah:BAAALgAECgEJAQAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Denvoker:BAAALgAECgQJBwAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEAAAAA==.',
Di='Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Dolleez:BAAALgAECgYJBgAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8WAAIDAAYJMgJDRQB2AAZoDAAABQAFAGkMAAAEAAkAawwAAAQAAgBqDAAAAwAOAGwMAAACAAUA6gwAAAQABAADAAYJMgJDRQB2AAZoDAAABQAFAGkMAAAEAAkAawwAAAQAAgBqDAAAAwAOAGwMAAACAAUA6gwAAAQABAAAAA==.',
Du='Dunkaroo:BAABLgAECn8YAAITAAcJlBXlOgBUAQdoDAAABABIAGkMAAAEADkAawwAAAQAMwBqDAAAAwBKAGwMAAAEADcAbQwAAAEALgDqDAAABAAvABMABwmUFeU6AFQBB2gMAAAEAEgAaQwAAAQAOQBrDAAABAAzAGoMAAADAEoAbAwAAAQANwBtDAAAAQAuAOoMAAAEAC8AAAA=.',
['Dé']='Dékü:BAAALgAECgEJAQAAAA==.',
Ei='Eikinskaldi:BAAALgADCgUJCgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAAALgAECgcJEQAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgQJBgAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECggJKgAUABAWAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgAECgIJAgABLgAECgcJDAAVAAAAAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BB1OACgAQhoDAAABAAYAGkMAAAEAEkAawwAAAQASgBqDAAAAwASAGwMAAADAC4AbQwAAAEADgDqDAAABAA1AG4MAAABACcABgAICdgQdTgAoAEIaAwAAAMAGABpDAAAAwBJAGsMAAADAEoAagwAAAMAEgBsDAAAAwAuAG0MAAABAA4A6gwAAAQANQBuDAAAAQAnABYAAwniHbttAIwAA2gMAAABAFMAaQwAAAEARQBrDAAAAQBMAAAA.Frìeren:BAABLgAECn8eAAIXAAcJaBX+TACJAQdoDAAABQBIAGkMAAAGAEMAawwAAAYALgBqDAAABAAhAGwMAAADAEUAbQwAAAEAGQDqDAAABQAvABcABwloFf5MAIkBB2gMAAAFAEgAaQwAAAYAQwBrDAAABgAuAGoMAAAEACEAbAwAAAMARQBtDAAAAQAZAOoMAAAFAC8AAAA=.',
Fu='Fuegaluna:BAAALgADCgcJBwAAAA==.Fundetected:BAABLgAECn8dAAITAAkJTBhWGgD1AQloDAAABQBFAGkMAAAEAFcAawwAAAQAPQBqDAAAAwA3AGwMAAADAEEAbQwAAAIAPADqDAAABQBCAG4MAAACACwAbwwAAAEAKAATAAkJTBhWGgD1AQloDAAABQBFAGkMAAAEAFcAawwAAAQAPQBqDAAAAwA3AGwMAAADAEEAbQwAAAIAPADqDAAABQBCAG4MAAACACwAbwwAAAEAKAAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgADCggJBAAAAA==.Grimmberly:BAAALgAECgQJBAAAAA==.Grimmothy:BAABLgAECn8iAAIYAAgJjhKdEwCpAQhoDAAABgBRAGkMAAAGADsAawwAAAYALgBqDAAABQAxAGwMAAAEAC8AbQwAAAEAGQDqDAAABQA5AG4MAAABAA4AGAAICY4SnRMAqQEIaAwAAAYAUQBpDAAABgA7AGsMAAAGAC4AagwAAAUAMQBsDAAABAAvAG0MAAABABkA6gwAAAUAOQBuDAAAAQAOAAAA.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn8gAAICAAgJJwuwOQBpAQhoDAAABwAeAGkMAAAFACsAawwAAAUALABqDAAABQAMAGwMAAAFACQAbQwAAAEAEADqDAAAAwAVAG4MAAABAAcAAgAICScLsDkAaQEIaAwAAAcAHgBpDAAABQArAGsMAAAFACwAagwAAAUADABsDAAABQAkAG0MAAABABAA6gwAAAMAFQBuDAAAAQAHAAAA.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgADCgYJCgAAAA==.Hakuri:BAAALgADCgcJDwAAAA==.Hannibow:BAAALgAECgcJBwAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8ZAAQUAAcJMBbOEgDXAQdoDAAABABeAGkMAAAEAFIAawwAAAQAGgBqDAAABAA3AGwMAAADABYAbQwAAAIAOADqDAAABAA8ABQABwkwFs4SANcBB2gMAAADAF4AaQwAAAIAUgBrDAAAAQAaAGoMAAACADcAbAwAAAIAFgBtDAAAAgA4AOoMAAADADwAGAAGCegI800ACwEGaAwAAAEAMQBpDAAAAgALAGsMAAACABMAagwAAAIADwBsDAAAAQATAOoMAAABAA4AGQABCa8NpV4ANwABawwAAAEAIwAAAA==.',
Hi='Highfever:BAAALgAECgUJEgAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgADCgUJBQAVAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECggJIQAaAP8bAA==.Huuch:BAABLgAECn8bAAICAAgJFAqVPQBaAQhoDAAABAAkAGkMAAAEABwAawwAAAQADgBqDAAABAAZAGwMAAADAC0AbQwAAAEADQDqDAAABQATAG4MAAACABYAAgAICRQKlT0AWgEIaAwAAAQAJABpDAAABAAcAGsMAAAEAA4AagwAAAQAGQBsDAAAAwAtAG0MAAABAA0A6gwAAAUAEwBuDAAAAgAWAAAA.',
Hy='Hycinari:BAAALgAECgEJAQAAAA==.',
Ic='Icrucify:BAABLgAECn8sAAICAAkJbCUVAQBZAwloDAAABgBfAGkMAAAHAGEAawwAAAYAXgBqDAAABQBjAGwMAAAFAGEAbQwAAAQAXQDqDAAABQBgAG4MAAAFAGMAbwwAAAEAWwACAAkJbCUVAQBZAwloDAAABgBfAGkMAAAHAGEAawwAAAYAXgBqDAAABQBjAGwMAAAFAGEAbQwAAAQAXQDqDAAABQBgAG4MAAAFAGMAbwwAAAEAWwAAAA==.',
Ig='Ignia:BAAALgAECgEJAQABLgAECgQJBgAVAAAAAA==.',
Il='Ilanos:BAAALgADCgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAVAAAAAA==.',
Ir='Iremoon:BAABLgAECn8iAAMLAAgJmA+IOQCfAQhoDAAABwA2AGkMAAAFADUAawwAAAUAKwBqDAAABQA9AGwMAAAFACkAbQwAAAIAFQDqDAAABAAsAG4MAAABABQACwAICZgPiDkAnwEIaAwAAAUANgBpDAAABAA1AGsMAAAFACsAagwAAAUAPQBsDAAABQApAG0MAAACABUA6gwAAAQALABuDAAAAQAUAAwAAglHBBJCAEIAAmgMAAACAAwAaQwAAAEACQAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgAFFAEJAQAAAA==.Jestyrd:BAAALgAECgMJAwABLgAFFAEJAQAVAAAAAA==.Jestyrmo:BAABLgAECn8lAAMYAAgJ0BpqHQBPAQhoDAAABQA9AGkMAAAFAEUAawwAAAYASgBqDAAABQAnAGwMAAAEAEMAbQwAAAQALADqDAAABQBMAG4MAAADAFYAGAAHCZ8Zah0ATwEHaAwAAAMAPQBpDAAAAwBFAGsMAAADAEoAagwAAAEAJwBsDAAAAQBDAG0MAAABACwA6gwAAAEATAAUAAgJgBDXIQBGAQhoDAAAAgAQAGkMAAACACoAawwAAAMALgBqDAAABAAxAGwMAAADADgAbQwAAAMALgDqDAAABAAvAG4MAAADACAAAS4ABRQBCQEAFQAAAAA=.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8IAAIZAAMJOxYaEADsAANoDAAABAAwAGkMAAACAEMA6gwAAAIANgAZAAMJOxYaEADsAANoDAAABAAwAGkMAAACAEMA6gwAAAIANgAuAAQKfzYAAxkACQmFJPsAAE4DABkACQmFJPsAAE4DABQAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJDgAAAA==.',
Ka='Kaceya:BAAALgAECgEJAQAAAA==.Kainarasa:BAAALgAECgYJEwAAAA==.Katarinea:BAABLgAECn8ZAAIDAAcJmw6AJAAiAQdoDAAABAAqAGkMAAAEABkAawwAAAQAMgBqDAAAAwAmAGwMAAADACUA6gwAAAUAIABuDAAAAgAkAAMABwmbDoAkACIBB2gMAAAEACoAaQwAAAQAGQBrDAAABAAyAGoMAAADACYAbAwAAAMAJQDqDAAABQAgAG4MAAACACQAAAA=.Kaypop:BAAALgAECgcJEwAAAA==.',
Kh='Khalessie:BAABLgAECn8bAAIbAAcJcQ73GAB6AQdoDAAABQAnAGkMAAAFABoAawwAAAUAPABqDAAABAA1AGwMAAADAA8AbQwAAAEAJADqDAAABAAaABsABwlxDvcYAHoBB2gMAAAFACcAaQwAAAUAGgBrDAAABQA8AGoMAAAEADUAbAwAAAMADwBtDAAAAQAkAOoMAAAEABoAAAA=.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMcAAkJpB70AQCnAgloDAAABgBbAGkMAAAGAFQAawwAAAUAUQBqDAAABAA7AGwMAAAEAFQAbQwAAAIAOwDqDAAABQBBAG4MAAADAFcAbwwAAAEASAAcAAkJpB70AQCnAgloDAAABgBbAGkMAAAGAFQAawwAAAUAUQBqDAAABAA7AGwMAAAEAFQAbQwAAAIAOwDqDAAABABBAG4MAAADAFcAbwwAAAEASAAGAAEJeQEJlwAaAAHqDAAAAQADAAAA.',
Ko='Korkneelious:BAAALgAECgUJBQAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgYJEwAVAAAAAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8bAAIRAAYJyRCGKQA1AQZoDAAABQAqAGkMAAAGAEMAawwAAAcAKwBqDAAAAgAfAGwMAAABABYA6gwAAAYAJgARAAYJyRCGKQA1AQZoDAAABQAqAGkMAAAGAEMAawwAAAcAKwBqDAAAAgAfAGwMAAABABYA6gwAAAYAJgAAAA==.Liths:BAABLgAECn8hAAIdAAgJCQmfDAAGAQhoDAAABgArAGkMAAAFACEAawwAAAUAFABqDAAABQAdAGwMAAAFABoAbQwAAAIADADqDAAABAASAG4MAAABAAcAHQAICQkJnwwABgEIaAwAAAYAKwBpDAAABQAhAGsMAAAFABQAagwAAAUAHQBsDAAABQAaAG0MAAACAAwA6gwAAAQAEgBuDAAAAQAHAAAA.Littlemoses:BAABLgAECn8VAAICAAYJniFKIgDTAQZoDAAABABjAGkMAAAEAE4AawwAAAQASQBqDAAAAwBSAGwMAAACAFEA6gwAAAQAYAACAAYJniFKIgDTAQZoDAAABABjAGkMAAAEAE4AawwAAAQASQBqDAAAAwBSAGwMAAACAFEA6gwAAAQAYAAAAA==.',
Lo='Lockdarkly:BAAALgAECgIJBAAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgUJCgAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEAAVAAAAAA==.Malendren:BAAALgADCgYJAgAAAA==.Malignus:BAABLgAECn8dAAIXAAgJmhNZNwDMAQhoDAAABAA9AGkMAAAEAC4AawwAAAQAMABqDAAABAA9AGwMAAAEACcAbQwAAAIANQDqDAAABQA8AG4MAAACACgAFwAICZoTWTcAzAEIaAwAAAQAPQBpDAAABAAuAGsMAAAEADAAagwAAAQAPQBsDAAABAAnAG0MAAACADUA6gwAAAUAPABuDAAAAgAoAAEuAAMKCQkXABUAAAAA.Malthaos:BAAALgADCgQJBAABLgAECgcJGwAXAOobAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgQJBQAAAA==.',
Mc='Mcdavé:BAABLgAECn8iAAIWAAgJ5w29HgBkAQhoDAAABwApAGkMAAAFACwAawwAAAUAJwBqDAAABQAgAGwMAAAFADsAbQwAAAIAEQDqDAAABAAmAG4MAAABAAkAFgAICecNvR4AZAEIaAwAAAcAKQBpDAAABQAsAGsMAAAFACcAagwAAAUAIABsDAAABQA7AG0MAAACABEA6gwAAAQAJgBuDAAAAQAJAAAA.',
Me='Meathshield:BAAALgADCgMJAwABLgAECgcJFgABANIaAA==.Meerclar:BAAALgAECgIJAwABLgAECgIJBAAVAAAAAA==.Melaila:BAABLgAECn8lAAIGAAYJ9yR4EgCCAgZoDAAABwBeAGkMAAAHAGEAawwAAAcAYABqDAAABQBiAGwMAAAFAF0A6gwAAAYAVwAGAAYJ9yR4EgCCAgZoDAAABwBeAGkMAAAHAGEAawwAAAcAYABqDAAABQBiAGwMAAAFAF0A6gwAAAYAVwAAAA==.Mellwynn:BAAALgAECgMJAwAAAA==.Melunaura:BAAALgADCggJCAABLgAECgYJJQAGAPckAA==.',
Mf='Mf:BAABLgAECn8UAAITAAcJZRISOgBXAQdoDAAAAwAnAGkMAAADAEkAawwAAAIAQABqDAAABAASAGwMAAACAB8AbQwAAAMAHQDqDAAAAwAtABMABwllEhI6AFcBB2gMAAADACcAaQwAAAMASQBrDAAAAgBAAGoMAAAEABIAbAwAAAIAHwBtDAAAAwAdAOoMAAADAC0AAAA=.',
Mi='Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgADCgMJAwAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgUJDwAAAA==.Mongrol:BAAALgAECgQJBQAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJEgAVAAAAAA==.',
Mu='Mummrakhan:BAAALgAECgEJAgAAAA==.',
Na='Naniel:BAACLgAFFH8GAAIRAAMJ4Qd0HgDSAANoDAAAAwAjAGkMAAACAA4A6gwAAAEACwARAAMJ4Qd0HgDSAANoDAAAAwAjAGkMAAACAA4A6gwAAAEACwAuAAQKfyIAAhEACAmdExssAAUCABEACAmdExssAAUCAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBgAAAA==.Neb:BAABLgAECn8rAAMeAAkJJhaLGQAfAgloDAAABgBEAGkMAAAGADoAawwAAAYAMgBqDAAABQAxAGwMAAAFADAAbQwAAAQANgDqDAAABgA4AG4MAAAEAEAAbwwAAAEANAAeAAkJJhaLGQAfAgloDAAABgBEAGkMAAAGADoAawwAAAYAMgBqDAAABAAxAGwMAAAFADAAbQwAAAQANgDqDAAABQA4AG4MAAAEAEAAbwwAAAEANAAfAAIJuRFUVwBoAAJqDAAAAQAUAOoMAAABAC0AAAA=.Necroy:BAAALgAECgYJDAAAAA==.',
Ni='Niccee:BAABLgAECn8ZAAIDAAcJcg0OIgA0AQdoDAAABAAbAGkMAAAEAB0AawwAAAQAJgBqDAAABAAoAGwMAAADACYAbQwAAAIAIQDqDAAABAAnAAMABwlyDQ4iADQBB2gMAAAEABsAaQwAAAQAHQBrDAAABAAmAGoMAAAEACgAbAwAAAMAJgBtDAAAAgAhAOoMAAAEACcAAAA=.Nick:BAACLgAFFH8RAAIeAAUJ+Bu6HABKAQVoDAAABABFAGkMAAAFAFUAawwAAAIAKQBqDAAAAgA+AOoMAAAEAFkAHgAFCfgbuhwASgEFaAwAAAQARQBpDAAABQBVAGsMAAACACkAagwAAAIAPgDqDAAABABZAC4ABAp/GAADHgAICRgjKBsAsgIAHgAICRgjKBsAsgIAHwABCQAAeIAAEAAAAAA=.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAVAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgYJBgAVAAAAAA==.Nosebleeds:BAAALgAFFAEJAQAAAA==.Notyourheals:BAABLgAECn8ZAAMWAAgJ6AqMIgBJAQhoDAAABgAxAGkMAAAFACcAawwAAAQAJgBqDAAAAwAhAGwMAAACAAkAbQwAAAEACQDqDAAAAwAVAG4MAAABABsAFgAICegKjCIASQEIaAwAAAQAMQBpDAAABAAnAGsMAAADACYAagwAAAIAIQBsDAAAAgAJAG0MAAABAAkA6gwAAAMAFQBuDAAAAQAbAAYABAlIAaKNAF8ABGgMAAACAAQAaQwAAAEAAwBrDAAAAQADAGoMAAABAAEAAAA=.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxaGFwATAgloDAAABgAyAGkMAAAGAE0AawwAAAUASgBqDAAABABCAGwMAAAEADgAbQwAAAMAHgDqDAAABgBIAG4MAAAEAEIAbwwAAAEADwAaAAkJNxaGFwATAgloDAAABgAyAGkMAAAGAE0AawwAAAUASgBqDAAABABCAGwMAAAEADgAbQwAAAMAHgDqDAAABgBIAG4MAAAEAEIAbwwAAAEADwAAAA==.',
Od='Odsum:BAABLgAECn8WAAIPAAYJKBh9fQB/AQZoDAAAAwA2AGkMAAAEAEIAawwAAAUAMgBqDAAAAgBEAGwMAAADAFUA6gwAAAUANAAPAAYJKBh9fQB/AQZoDAAAAwA2AGkMAAAEAEIAawwAAAUAMgBqDAAAAgBEAGwMAAADAFUA6gwAAAUANAAAAA==.',
Oo='Oogrutamu:BAAALgADCggJBAAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgIJAgAAAA==.Pandabear:BAAALgADCgYJBgAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papichulo:BAAALgADCgYJBgAAAA==.',
Pe='Percival:BAABLgAECn8ZAAIPAAcJyAtQYgA0AQdoDAAABAAaAGkMAAAEABwAawwAAAQALQBqDAAABAAzAGwMAAADABQAbQwAAAIAEADqDAAABAArAA8ABwnIC1BiADQBB2gMAAAEABoAaQwAAAQAHABrDAAABAAtAGoMAAAEADMAbAwAAAMAFABtDAAAAgAQAOoMAAAEACsAAAA=.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAAALgAECgYJBgABLgAECgYJEwAVAAAAAA==.',
Po='Poetbrat:BAAALgADCgMJCQABLgAECgYJFgADADICAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgQJBAAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIOAAkJswuWBACwAQloDAAABgAuAGkMAAAFACEAawwAAAUAHgBqDAAAAwAlAGwMAAADACQAbQwAAAMACADqDAAABQAaAG4MAAADACMAbwwAAAIAFAAOAAkJswuWBACwAQloDAAABgAuAGkMAAAFACEAawwAAAUAHgBqDAAAAwAlAGwMAAADACQAbQwAAAMACADqDAAABQAaAG4MAAADACMAbwwAAAIAFAAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAAALgAECgMJCAAAAA==.',
Qu='Queue:BAAALgAECgMJBQAAAA==.Quilten:BAAALgAECgYJDwAAAA==.',
Ra='Raenii:BAAALgAECgYJBgABLgAFFAEJAQAVAAAAAA==.Ramoth:BAAALgAECgQJBwAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgADCggJBAAAAA==.Rayne:BAABLgAECn8bAAIXAAcJ6htDPAC7AQdoDAAABQBbAGkMAAAFADsAawwAAAQAPgBqDAAABABFAGwMAAADADsAbQwAAAIASADqDAAABABSABcABwnqG0M8ALsBB2gMAAAFAFsAaQwAAAUAOwBrDAAABAA+AGoMAAAEAEUAbAwAAAMAOwBtDAAAAgBIAOoMAAAEAFIAAAA=.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8WAAMLAAcJFhAWeAD+AAdoDAAAAwA2AGkMAAAEAC4AawwAAAMAJQBqDAAAAwAmAGwMAAAEACcAbQwAAAEAIQDqDAAABAAjAAsABgkpEBZ4AP4ABmgMAAADADYAaQwAAAQALgBrDAAAAwAlAGoMAAADACYAbAwAAAMAJwDqDAAAAwAcACAAAwnRDKMPAJsAA2wMAAABAB0AbQwAAAEAIQDqDAAAAQAjAAAA.',
Ri='Rinnian:BAAALgAECgYJDgAAAA==.Rinny:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgQJBwAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECggJMgAYAGgRAA==.Robbiemonk:BAABLgAECn8yAAMYAAgJaBEtGAB9AQhoDAAACAA/AGkMAAAIADMAawwAAAgALgBqDAAABgAsAGwMAAAGAB8AbQwAAAMAJwDqDAAACAAvAG4MAAADACAAGAAICWgRLRgAfQEIaAwAAAcAPwBpDAAABwAzAGsMAAAHAC4AagwAAAYALABsDAAABgAfAG0MAAADACcA6gwAAAcALwBuDAAAAwAgABkABAn3AxFeAJgABGgMAAABAAcAaQwAAAEABgBrDAAAAQANAOoMAAABAA0AAAA=.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJCAAAAA==.Sannith:BAABLgAECn8iAAIXAAgJZBI+PAC7AQhoDAAABwAqAGkMAAAFAC8AawwAAAUAMwBqDAAABQA9AGwMAAAFADcAbQwAAAIALgDqDAAABAApAG4MAAABAC0AFwAICWQSPjwAuwEIaAwAAAcAKgBpDAAABQAvAGsMAAAFADMAagwAAAUAPQBsDAAABQA3AG0MAAACAC4A6gwAAAQAKQBuDAAAAQAtAAAA.Sapphi:BAABLgAECn8ZAAIhAAcJihD5EQArAQdoDAAABAAeAGkMAAAEADsAawwAAAQAQwBqDAAABAAkAGwMAAADABgAbQwAAAIAIwDqDAAABAAkACEABwmKEPkRACsBB2gMAAAEAB4AaQwAAAQAOwBrDAAABABDAGoMAAAEACQAbAwAAAMAGABtDAAAAgAjAOoMAAAEACQAAAA=.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgYJEwAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAVAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shespawn:BAAALgAECgEJAgAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDiLwDxAQloDAAAAgAjAGkMAAADACEAawwAAAMANQBqDAAAAgA2AGwMAAACADAAbQwAAAIAHADqDAAABQBAAG4MAAACAEAAbwwAAAEADAACAAkJqhDiLwDxAQloDAAAAQAjAGkMAAADACEAawwAAAMANQBqDAAAAgA2AGwMAAACADAAbQwAAAIAHADqDAAABQBAAG4MAAACAEAAbwwAAAEADAAiAAEJLQJhMgApAAFoDAAAAQAFAAAA.Shykara:BAAALgADCgMJCQABLgAECgQJBwAVAAAAAA==.Shâdê:BAAALgAECgEJAQAAAA==.',
Si='Sins:BAAALgADCggJBAAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slipperybop:BAAALgAFFAIJAgABLgAECgYJBgAVAAAAAA==.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAZrPwAXAQloDAAABgAQAGkMAAAFACQAawwAAAUAHQBqDAAABAAFAGwMAAAFAA4AbQwAAAIABADqDAAABgATAG4MAAACAAsAbwwAAAEACAAGAAkJZAZrPwAXAQloDAAABgAQAGkMAAAFACQAawwAAAUAHQBqDAAABAAFAGwMAAAFAA4AbQwAAAIABADqDAAABgATAG4MAAACAAsAbwwAAAEACAAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgADCggJBAAAAA==.Sorena:BAAALgADCgMJCAAAAA==.',
Sp='Spyman:BAAALgAECgEJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8hAAIaAAgJ/xvJDQB+AghoDAAABgBCAGkMAAAFAFUAawwAAAUAWABqDAAABQBDAGwMAAAFAEsAbQwAAAIAMwDqDAAABABYAG4MAAABADMAGgAICf8byQ0AfgIIaAwAAAYAQgBpDAAABQBVAGsMAAAFAFgAagwAAAUAQwBsDAAABQBLAG0MAAACADMA6gwAAAQAWABuDAAAAQAzAAAA.',
St='Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAVAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJDQAAAA==.Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgADCggJBAAAAA==.',
Te='Tellah:BAAALgAECggJEAABLgAECgQJDgAVAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgYJEwAVAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgUJEAAVAAAAAA==.',
Tw='Twomz:BAABLgAECn8aAAIGAAYJnQ5uPAAlAQZoDAAABAAZAGkMAAAFABYAawwAAAQAJQBqDAAABQAUAGwMAAAEADUA6gwAAAQAQAAGAAYJnQ5uPAAlAQZoDAAABAAZAGkMAAAFABYAawwAAAQAJQBqDAAABQAUAGwMAAAEADUA6gwAAAQAQAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABocAA==.',
Un='Unclebenjinn:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECggJEAAVAAAAAA==.',
Va='Vavaboom:BAAALgADCggJCAAAAA==.',
Vi='Vindication:BAAALgAECgYJEgAAAA==.Viz:BAAALgADCgMJCQAAAA==.',
Vo='Voidshådow:BAAALgAECgQJBwAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgADCgkJCQABLgAECgYJEwAVAAAAAA==.',
Vy='Vylandra:BAAALgADCgcJCQAAAA==.',
We='Weepingwillo:BAAALgADCgUJBQAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCAAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgEJAQAAAA==.',
Xa='Xaela:BAABLgAECn8YAAITAAgJnxffIwC7AQhoDAAABQBUAGkMAAADAD4AawwAAAQAJgBqDAAAAgBCAGwMAAACACcAbQwAAAEARgDqDAAABQA7AG4MAAACAEMAEwAICZ8X3yMAuwEIaAwAAAUAVABpDAAAAwA+AGsMAAAEACYAagwAAAIAQgBsDAAAAgAnAG0MAAABAEYA6gwAAAUAOwBuDAAAAgBDAAAA.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgIJBAAAAA==.Xarous:BAAALgADCgkJFAABLgAECgYJEwAVAAAAAA==.',
Xe='Xeon:BAAALgADCgcJCgAAAA==.',
Xi='Xiabal:BAABLgAECn8cAAMaAAcJYiEoDQCGAgdoDAAABQBUAGkMAAAFAFYAawwAAAUAWgBqDAAABABJAGwMAAADAFUAbQwAAAIAUwDqDAAABABdABoABwliISgNAIYCB2gMAAADAFQAaQwAAAQAVgBrDAAABABaAGoMAAAEAEkAbAwAAAMAVQBtDAAAAgBTAOoMAAAEAF0AAwADCVIYgzAA2wADaAwAAAIATQBpDAAAAQA3AGsMAAABADUAAAA=.',
Xw='Xweakling:BAAALgAECgQJBAABLgAECgkJIwARAGccAA==.Xweekling:BAABLgAECn8jAAIRAAkJZxxSBQCqAgloDAAABgBSAGkMAAAFAFwAawwAAAYATABqDAAAAwBIAGwMAAADAEAAbQwAAAIASQDqDAAABwBeAG4MAAACADQAbwwAAAEALgARAAkJZxxSBQCqAgloDAAABgBSAGkMAAAFAFwAawwAAAYATABqDAAAAwBIAGwMAAADAEAAbQwAAAIASQDqDAAABwBeAG4MAAACADQAbwwAAAEALgAAAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgADCgYJAgAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgMJCAAAAA==.',
Za='Zaraeth:BAAALgAECgIJAgABLgAECgIJBAAVAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zerostar:BAAALgAECgQJBQABLgAECgkJLQACAPwaAA==.Zevon:BAAALgADCgQJBAABLgAECgIJBAAVAAAAAA==.',
['ße']='ßeastie:BAAALgADCgQJBQAAAA==.',
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

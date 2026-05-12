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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','DemonHunter-Devourer','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Warrior-Fury','Evoker-Devastation','Hunter-Marksmanship','Warlock-Demonology','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='daily',zone=46,date='2026-05-11',data={Ab='Abelle:BAAALgAECgQJBQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgEJAQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgADCgcJBwABLgAECgEJAQABAAAAAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgUJBQAAAA==.Arykiel:BAABLgAECn8bAAICAAgJOxfGLQDYAQhoDAAABQBBAGkMAAAFAEgAawwAAAQARwBqDAAAAwA0AGwMAAACADcAbQwAAAEALADqDAAABgBCAG4MAAABACgAAgAICTsXxi0A2AEIaAwAAAUAQQBpDAAABQBIAGsMAAAEAEcAagwAAAMANABsDAAAAgA3AG0MAAABACwA6gwAAAYAQgBuDAAAAQAoAAAA.',
As='Asthar:BAAALgADCgMJBQAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAQJCwADAAQgAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAUJDQAEAAUZAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgADCggJDgAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBBuEACuAQhoDAAAAwAmAGkMAAADADcAawwAAAMAIgBqDAAABAAaAGwMAAADACkAbQwAAAIAGADqDAAABQAuAG4MAAACADYABQAICXwQbhAArgEIaAwAAAMAJgBpDAAAAwA3AGsMAAADACIAagwAAAQAGgBsDAAAAwApAG0MAAACABgA6gwAAAUALgBuDAAAAgA2AAAA.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAABLgAECn8hAAMGAAgJ3hRhCQCpAQhoDAAABgAtAGkMAAAFAEYAawwAAAYAQABqDAAABABBAGwMAAADADQAbQwAAAEANwDqDAAABwA2AG4MAAABACAABgAICd4UYQkAqQEIaAwAAAMALQBpDAAAAwBGAGsMAAAEAEAAagwAAAMAQQBsDAAAAwA0AG0MAAABADcA6gwAAAMANgBuDAAAAQAgAAcABQl5DlgdAP8ABWgMAAADACkAaQwAAAIAJgBrDAAAAgAfAGoMAAABAA8A6gwAAAQAJAAAAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BenIABcAQdoDAAABABFAGkMAAADAEoAawwAAAQASwBqDAAAAwAwAGwMAAABABcA6gwAAAUARQBuDAAAAQA4AAgABwn4F6cgAFwBB2gMAAAEAEUAaQwAAAMASgBrDAAABABLAGoMAAADADAAbAwAAAEAFwDqDAAABQBFAG4MAAABADgAAAA=.Braniti:BAAALgADCgQJBAAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAECggJFgAJACYLAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgYJCwABLgAECggJJAAKAPkeAA==.',
Bu='Bubbies:BAABLgAECn8aAAILAAgJnxQlEADmAQhoDAAABQBSAGkMAAAEAEYAawwAAAMAIABqDAAAAwAnAGwMAAADAEAAbQwAAAEANwDqDAAABgA6AG8MAAABABIACwAICZ8UJRAA5gEIaAwAAAUAUgBpDAAABABGAGsMAAADACAAagwAAAMAJwBsDAAAAwBAAG0MAAABADcA6gwAAAYAOgBvDAAAAQASAAAA.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8YAAICAAkJ/BHWMADLAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAADADwAbQwAAAIALgDqDAAABAAlAG4MAAACAF4AbwwAAAIAGwACAAkJ/BHWMADLAQloDAAABABSAGkMAAACAAgAawwAAAIACgBqDAAAAwAnAGwMAAADADwAbQwAAAIALgDqDAAABAAlAG4MAAACAF4AbwwAAAIAGwAAAA==.Chiste:BAABLgAECn8bAAIMAAcJ7AwLDgABAQdoDAAACABMAGkMAAAFAA4AawwAAAQAIQBqDAAAAQAKAGwMAAADAAgA6gwAAAUAKwBuDAAAAQAVAAwABwnsDAsOAAEBB2gMAAAIAEwAaQwAAAUADgBrDAAABAAhAGoMAAABAAoAbAwAAAMACADqDAAABQArAG4MAAABABUAAAA=.',
Co='Cobrah:BAAALgADCggJDQABLgAECgUJBQABAAAAAA==.Coredellion:BAAALgADCgUJCAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn8mAAINAAgJ3RKAIgC3AQhoDAAABgArAGkMAAAGAEAAawwAAAYALwBqDAAABQA0AGwMAAAFAFAAbQwAAAMAGQDqDAAABQA1AG4MAAACABMADQAICd0SgCIAtwEIaAwAAAYAKwBpDAAABgBAAGsMAAAGAC8AagwAAAUANABsDAAABQBQAG0MAAADABkA6gwAAAUANQBuDAAAAgATAAEuAAUUBgkZAA4AkxgA.Dannica:BAAALgAECgUJAgAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgUJCwAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAUJDQAEAAUZAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8cAAICAAgJjQ6IQgCPAQhoDAAABAAjAGkMAAAEABIAawwAAAQAGQBqDAAAAwAnAGwMAAAFADgAbQwAAAEAIgDqDAAABgBKAG4MAAABAA4AAgAICY0OiEIAjwEIaAwAAAQAIwBpDAAABAASAGsMAAAEABkAagwAAAMAJwBsDAAABQA4AG0MAAABACIA6gwAAAYASgBuDAAAAQAOAAAA.',
Do='Dobledas:BAAALgAECggJCAAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAMJBQAPADUVAA==.Donut:BAAALgAFFAMJAQABLgAECgcJFgAHAEkPAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgMJAwAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn8sAAMQAAgJUiR0AQAuAwhoDAAACABiAGkMAAAIAFwAawwAAAcAYQBqDAAABgBcAGwMAAAFAGEAbQwAAAIAWgDqDAAABgBgAG4MAAACAE0AEAAICVIkdAEALgMIaAwAAAcAYgBpDAAABgBcAGsMAAAFAGEAagwAAAUAXABsDAAABQBhAG0MAAACAFoA6gwAAAYAYABuDAAAAgBNABEABAkqEdk/AOkABGgMAAABADIAaQwAAAIAKABrDAAAAgAoAGoMAAABACYAAAA=.Elizalynn:BAABLgAECn8gAAISAAgJIxDdGwB9AQhoDAAABgA5AGkMAAAGACcAawwAAAUALgBqDAAABQA1AGwMAAAEACMAbQwAAAIAKADqDAAAAwAyAG4MAAABAAcAEgAICSMQ3RsAfQEIaAwAAAYAOQBpDAAABgAnAGsMAAAFAC4AagwAAAUANQBsDAAABAAjAG0MAAACACgA6gwAAAMAMgBuDAAAAQAHAAAA.',
Ev='Eveycakes:BAAALgAFFAEJAQABLgAFFAQJCwADAAQgAA==.',
Fe='Fengshui:BAAALgAECggJCAAAAA==.Ferritin:BAABLgAECn8eAAIEAAgJDiXcAQBjAwhoDAAABQBjAGkMAAAFAGAAawwAAAUAYgBqDAAABABjAGwMAAAEAGMAbQwAAAIAYQDqDAAABABhAG4MAAABAEsABAAICQ4l3AEAYwMIaAwAAAUAYwBpDAAABQBgAGsMAAAFAGIAagwAAAQAYwBsDAAABABjAG0MAAACAGEA6gwAAAQAYQBuDAAAAQBLAAAA.Fester:BAAALgAECgEJAgAAAA==.',
Fi='Fish:BAAALgAECgQJBgAAAA==.Fishguts:BAACLgAFFH8KAAITAAQJ4hE6EwASAQRoDAAABAA5AGkMAAADAC8AawwAAAEAGwDqDAAAAgAzABMABAniEToTABIBBGgMAAAEADkAaQwAAAMALwBrDAAAAQAbAOoMAAACADMALgAECn83AAMTAAkJWxvwDgBoAgATAAkJWxvwDgBoAgAUAAgJxRsjCwAWAgAAAA==.',
Fo='Focaccia:BAABLgAECn8ZAAIVAAgJLRyIGwBWAghoDAAAAwBZAGkMAAADAEAAawwAAAMAOwBqDAAAAwBNAGwMAAAEAFUAbQwAAAMATgDqDAAAAwBVAG4MAAADACgAFQAICS0ciBsAVgIIaAwAAAMAWQBpDAAAAwBAAGsMAAADADsAagwAAAMATQBsDAAABABVAG0MAAADAE4A6gwAAAMAVQBuDAAAAwAoAAAA.Foxthisup:BAAALgAECgIJAgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJDAABAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGQAOAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECggJJAAKAPkeAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgQJCgAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8gAAINAAgJTRvhDQBrAghoDAAABgBWAGkMAAAGAEsAawwAAAUAUABqDAAABQBZAGwMAAAEAE0AbQwAAAIANADqDAAAAwA2AG4MAAABACkADQAICU0b4Q0AawIIaAwAAAYAVgBpDAAABgBLAGsMAAAFAFAAagwAAAUAWQBsDAAABABNAG0MAAACADQA6gwAAAMANgBuDAAAAQApAAAA.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgEJAgABLgAECgkJKAAOAGAYAA==.Hockeyhunter:BAABLgAECn8oAAIOAAkJYBiTEABfAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABQA2AG4MAAADAD4AbwwAAAEADgAOAAkJYBiTEABfAgloDAAABwA/AGkMAAAGAFUAawwAAAcASgBqDAAABAA5AGwMAAAEADoAbQwAAAMAVgDqDAAABQA2AG4MAAADAD4AbwwAAAEADgAAAA==.Hockeylockz:BAAALgAECgYJEQABLgAECgkJKAAOAGAYAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAVANAPAA==.',
Hu='Hunthunthunt:BAAALgAECgcJEwABLgAECggJIQAGAN4UAA==.',
['Hè']='Hèxen:BAAALgADCgcJBgAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgYJDAAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgUJCAAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJBwAAAA==.Kazum:BAAALgAECgEJAQAAAA==.',
Ke='Keralan:BAACLgAFFH8GAAMWAAMJbx0dBwBoAANoDAAAAQA6AGoMAAADAFYA6gwAAAIAXAAWAAIJBSQdBwBoAAJqDAAAAwBWAOoMAAACAFwAFwABCdgWgRQAUAABaAwAAAEAOgAuAAQKfyAAAxYACAkjJoIAAGwDABYACAkjJoIAAGwDABcAAQmhFZU8AEYAAAEuAAUUBQkVABgA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8eAAIJAAgJ4CMOAwCrAghoDAAABQBgAGkMAAAFAFYAawwAAAUAXQBqDAAAAwBOAGwMAAADAGAAbQwAAAEAWwDqDAAABgBdAG4MAAACAFUACQAICeAjDgMAqwIIaAwAAAUAYABpDAAABQBWAGsMAAAFAF0AagwAAAMATgBsDAAAAwBgAG0MAAABAFsA6gwAAAYAXQBuDAAAAgBVAAAA.',
Kw='Kwehlewd:BAABLgAECn8YAAIZAAcJlA3HJgAYAQdoDAAABAAwAGkMAAAEACgAawwAAAQAIwBqDAAAAwAnAGwMAAADABsAbQwAAAEACgDqDAAABQAuABkABwmUDccmABgBB2gMAAAEADAAaQwAAAQAKABrDAAABAAjAGoMAAADACcAbAwAAAMAGwBtDAAAAQAKAOoMAAAFAC4AAAA=.',
La='Lachampion:BAAALgADCggJCQABLgAECgUJBQABAAAAAA==.Laizee:BAABLgAECn8eAAINAAgJ2gMWRwD9AAhoDAAABQAFAGkMAAAFAA0AawwAAAUAFgBqDAAAAwAOAGwMAAADAAcAbQwAAAEABQDqDAAABgAFAG4MAAACAAQADQAICdoDFkcA/QAIaAwAAAUABQBpDAAABQANAGsMAAAFABYAagwAAAMADgBsDAAAAwAHAG0MAAABAAUA6gwAAAYABQBuDAAAAgAEAAAA.Latrice:BAABLgAECn8lAAICAAkJ6h2xEACHAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAACAAkJ6h2xEACHAgloDAAABgBgAGkMAAAFAE8AawwAAAUAYABqDAAABABUAGwMAAAEAEMAbQwAAAIANADqDAAABwBgAG4MAAADADMAbwwAAAEASAAAAA==.',
Lo='Loki:BAAALgAECgUJDwAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8dAAIKAAYJSRNHTwAbAQZoDAAABQA6AGkMAAAGADMAawwAAAYAJABqDAAAAwAoAGwMAAADACoA6gwAAAYAOQAKAAYJSRNHTwAbAQZoDAAABQA6AGkMAAAGADMAawwAAAYAJABqDAAAAwAoAGwMAAADACoA6gwAAAYAOQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8VAAITAAgJwBF1IwBBAQhoDAAABAAaAGkMAAAEADcAawwAAAQANQBqDAAAAwAuAGwMAAACADUAbQwAAAIAJwDqDAAAAQAsAG4MAAABACwAEwAICcARdSMAQQEIaAwAAAQAGgBpDAAABAA3AGsMAAAEADUAagwAAAMALgBsDAAAAgA1AG0MAAACACcA6gwAAAEALABuDAAAAQAsAAAA.Mawikiea:BAAALgAECgEJAgABLgAECgkJLwASAL8gAA==.',
Me='Melander:BAABLgAECn8fAAIJAAkJwhuhBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABABTAG4MAAABACoAbwwAAAEAIQAJAAkJwhuhBgDEAgloDAAABQBcAGkMAAAFAFYAawwAAAUATQBqDAAABABZAGwMAAADAFQAbQwAAAMARADqDAAABABTAG4MAAABACoAbwwAAAEAIQAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAMJBQAPADUVAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIaAAIJeSD4ZwC+AAJoDAAABABJAOoMAAAFAF0AGgACCXkg+GcAvgACaAwAAAQASQDqDAAABQBdAC4ABAp/JAACGgAICXkkfwoAywIAGgAICXkkfwoAywIAAAA=.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECgcJBwABLgAECgkJHwAJAMIbAA==.Nerzhuul:BAACLgAFFH8FAAIPAAMJNRVnBQD7AANoDAAAAwBQAGkMAAABABUA6gwAAAEAPAAPAAMJNRVnBQD7AANoDAAAAwBQAGkMAAABABUA6gwAAAEAPAAuAAQKfykAAg8ACQnwHZ4FAKkCAA8ACQnwHZ4FAKkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxyEDABbAghoDAAABQBbAGkMAAAFAEIAawwAAAUAUgBqDAAABAAtAGwMAAADAFIAbQwAAAQAMwDqDAAABQBMAG4MAAAEAEwAAwAICQMchAwAWwIIaAwAAAUAWwBpDAAABQBCAGsMAAAFAFIAagwAAAQALQBsDAAAAwBSAG0MAAAEADMA6gwAAAUATABuDAAABABMAAAA.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIVAAYJFxWKggAcAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAVAAYJFxWKggAcAQZoDAAABwA9AGkMAAAGAEAAawwAAAUAOABqDAAAAwASAGwMAAACABwA6gwAAAYAOgAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMbAAgJBBt7GwD6AQhoDAAABABaAGkMAAAEAF8AawwAAAMAQwBqDAAABABCAGwMAAACADQAbQwAAAEAQQDqDAAABwBUAG4MAAABAB4AGwAGCbgdexsA+gEGaAwAAAMAWgBpDAAAAwBfAGsMAAACAEMAagwAAAMAQgBsDAAAAQA0AOoMAAAHAFQAGQAHCdEOZjAAhQEHaAwAAAEALwBpDAAAAQA2AGsMAAABACsAagwAAAEAIwBsDAAAAQAjAG0MAAABABMAbgwAAAEAGQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJDQABLgAFFAUJDQAEAAUZAA==.Pandlian:BAAALgADCgUJBQABLgAFFAQJCwADAAQgAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAABLgAECn8WAAIJAAgJJguoFAAuAQhoDAAAAwAbAGkMAAADAC0AawwAAAIALQBqDAAAAwAgAGwMAAADABUAbQwAAAMADADqDAAAAwAiAG4MAAACAAsACQAICSYLqBQALgEIaAwAAAMAGwBpDAAAAwAtAGsMAAACAC0AagwAAAMAIABsDAAAAwAVAG0MAAADAAwA6gwAAAMAIgBuDAAAAgALAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgUJCAAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8VAAQSAAcJnx5LCgBUAgdoDAAAAwBPAGkMAAADAD4AawwAAAMARABqDAAABABHAGwMAAADAFAAbQwAAAEAWwDqDAAABABdABIABwmfHksKAFQCB2gMAAADAE8AaQwAAAMAPgBrDAAAAwBEAGoMAAAEAEcAbAwAAAIAUABtDAAAAQBbAOoMAAACAF0ACwABCTUWdUgAPgAB6gwAAAIAOAAcAAEJow2pXgA7AAFsDAAAAQAiAAAA.Raggnarr:BAACLgAFFH8LAAIdAAQJdBseDQBJAQRoDAAABABHAGkMAAACAFMAawwAAAIAOwDqDAAAAwBCAB0ABAl0Gx4NAEkBBGgMAAAEAEcAaQwAAAIAUwBrDAAAAgA7AOoMAAADAEIALgAECn8pAAIdAAgJuiAMDQDuAgAdAAgJuiAMDQDuAgAAAA==.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8HAAISAAMJSxsaDwD5AANoDAAAAgBOAGkMAAACADkA6gwAAAMASQASAAMJSxsaDwD5AANoDAAAAgBOAGkMAAACADkA6gwAAAMASQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBrDQC8AghoDAAAAwBTAGkMAAADAF0AawwAAAMAWwBqDAAAAgBWAGwMAAACAFAAbQwAAAEAUgDqDAAABQBNAG4MAAACAE4AGAAICdQgaw0AvAIIaAwAAAMAUwBpDAAAAwBdAGsMAAADAFsAagwAAAIAVgBsDAAAAgBQAG0MAAABAFIA6gwAAAUATQBuDAAAAgBOAAAA.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgUJBQAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn80AAMRAAkJHxVSDAAVAgloDAAABgA/AGkMAAAHAFMAawwAAAcAPABqDAAABwBHAGwMAAAGADkAbQwAAAUAKwDqDAAABwBEAG4MAAAEAB4AbwwAAAMAGAARAAgJvhNSDAAVAghoDAAAAwA/AGkMAAADAFMAawwAAAMAPABsDAAAAQAlAG0MAAADACgA6gwAAAMARABuDAAABAAeAG8MAAACABMAHgAICcgR9BIAswEIaAwAAAMAKABpDAAABAA9AGsMAAAEADoAagwAAAcARwBsDAAABQA5AG0MAAACACsA6gwAAAQAIABvDAAAAQAYAAAA.',
Sa='Sanctified:BAAALgAECgYJCwAAAA==.Saphíra:BAEALgAECgQJCAABLgAECgkJLAAEAL4kAA==.Satanick:BAAALgADCgEJAQABLgAFFAMJBQAPADUVAA==.',
Se='Seraph:BAABLgAECn8eAAISAAgJExE4JgC6AQhoDAAABQAuAGkMAAAFACoAawwAAAUAOwBqDAAABAA2AGwMAAAEAC8AbQwAAAIAGQDqDAAABAAkAG4MAAABACUAEgAICRMROCYAugEIaAwAAAUALgBpDAAABQAqAGsMAAAFADsAagwAAAQANgBsDAAABAAvAG0MAAACABkA6gwAAAQAJABuDAAAAQAlAAAA.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgYJBgAAAA==.',
Sn='Snikit:BAAALgAECgEJAQABLgAECgkJHwAJAMIbAA==.',
So='Sojourner:BAABLgAECn8UAAMDAAYJAxG2KABUAQZoDAAAAwAUAGkMAAAFADUAawwAAAYARQBqDAAAAQAWAGwMAAABABMA6gwAAAQATAADAAYJAxG2KABUAQZoDAAAAgAUAGkMAAADADUAawwAAAQARQBqDAAAAQAWAGwMAAABABMA6gwAAAMATAACAAQJiAu0lADZAARoDAAAAQAnAGkMAAACAB0AawwAAAIAHQDqDAAAAQASAAAA.',
Sp='Spoonzilla:BAABLgAECn8VAAIZAAYJ9QcIOQC3AAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAZAAYJ9QcIOQC3AAZoDAAABAAXAGkMAAAFABoAawwAAAQAGABqDAAAAQAQAGwMAAABAAIA6gwAAAYAFwAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIKAAgJ+R6hGgC0AghoDAAABQBfAGkMAAAFAE8AawwAAAUASgBqDAAABABeAGwMAAADADoAbQwAAAQAUADqDAAABgBgAG4MAAAEAEQACgAICfkeoRoAtAIIaAwAAAUAXwBpDAAABQBPAGsMAAAFAEoAagwAAAQAXgBsDAAAAwA6AG0MAAAEAFAA6gwAAAYAYABuDAAABABEAAAA.',
Su='Supersham:BAAALgAECgEJAQAAAA==.Superspam:BAABLgAECn8eAAMbAAgJVx7jLAD7AQhoDAAABQBgAGkMAAAEAEkAawwAAAUARwBqDAAABABPAGwMAAADAEwAbQwAAAIANgDqDAAABABTAG4MAAADAFQAGwAICVce4ywA+wEIaAwAAAQAYABpDAAAAgBJAGsMAAADAEcAagwAAAIATwBsDAAAAQBMAG0MAAABADYA6gwAAAQAUwBuDAAAAgBUABkABwlYEmAeAFMBB2gMAAABACgAaQwAAAIAJwBrDAAAAgBJAGoMAAACADMAbAwAAAIALQBtDAAAAQAdAG4MAAABADQAAAA=.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn8mAAIfAAgJJR4NAwBAAghoDAAABgBRAGkMAAAGAF4AawwAAAYARgBqDAAABQBWAGwMAAAFAEgAbQwAAAMARgDqDAAABQBZAG4MAAACAD0AHwAICSUeDQMAQAIIaAwAAAYAUQBpDAAABgBeAGsMAAAGAEYAagwAAAUAVgBsDAAABQBIAG0MAAADAEYA6gwAAAUAWQBuDAAAAgA9AAAA.',
Th='Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8cAAIbAAYJ8RAiPwAoAQZoDAAABQAYAGkMAAAFAB4AawwAAAUAMABqDAAABAAmAGwMAAAEADsA6gwAAAUAOgAbAAYJ8RAiPwAoAQZoDAAABQAYAGkMAAAFAB4AawwAAAUAMABqDAAABAAmAGwMAAAEADsA6gwAAAUAOgAAAA==.Thrasherzs:BAAALgAECgEJAgAAAA==.Thy:BAAALgADCgEJAQAAAA==.',
Ti='Tinyvoid:BAABLgAECn8eAAIKAAgJeBhEIgDMAQhoDAAABQBSAGkMAAAFADcAawwAAAUATgBqDAAAAwA7AGwMAAADAEsAbQwAAAEAEwDqDAAABgBVAG4MAAACACkACgAICXgYRCIAzAEIaAwAAAUAUgBpDAAABQA3AGsMAAAFAE4AagwAAAMAOwBsDAAAAwBLAG0MAAABABMA6gwAAAYAVQBuDAAAAgApAAAA.',
To='Togdumburz:BAACLgAFFH8GAAIgAAMJRRTyRgDaAANoDAAAAwAqAGkMAAABAEAA6gwAAAIAMAAgAAMJRRTyRgDaAANoDAAAAwAqAGkMAAABAEAA6gwAAAIAMAAuAAQKfyUAAyAACQkhGvoNAIgCACAACQkhGvoNAIgCAAwAAQkAAEdnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIYAAUJ3CHsAQAEAgVoDAAABgBhAGkMAAAFAF4AawwAAAQAXwBsDAAAAQAyAOoMAAAFAGAAGAAFCdwh7AEABAIFaAwAAAYAYQBpDAAABQBeAGsMAAAEAF8AbAwAAAEAMgDqDAAABQBgAC4ABAp/GQAEGAAICYoh5AkA6wIAGAAICXUh5AkA6wIAFAACCckUKFwAoAAAEwACCZ0PW1oAZQAAAAA=.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgcJEwABAAAAAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8UAAMJAAcJHyQYBQBiAgdoDAAABABdAGkMAAAEAF4AawwAAAQAYwBqDAAAAgBhAGwMAAACAFYAbQwAAAEAVADqDAAAAwBhAAkABwkfJBgFAGICB2gMAAAEAF0AaQwAAAQAXgBrDAAABABjAGoMAAACAGEAbAwAAAIAVgBtDAAAAQBUAOoMAAACAGEAIQABCdseQTUAWwAB6gwAAAEATgABLgAFFAUJFQAYANwhAA==.',
Vi='Vietsham:BAABLgAECn8fAAINAAgJehB3MwBUAQhoDAAABQA/AGkMAAAFAEsAawwAAAYAHwBqDAAAAwAyAGwMAAAEAB8AbQwAAAEAFgDqDAAABQArAG4MAAACABEADQAICXoQdzMAVAEIaAwAAAUAPwBpDAAABQBLAGsMAAAGAB8AagwAAAMAMgBsDAAABAAfAG0MAAABABYA6gwAAAUAKwBuDAAAAgARAAAA.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8NAAIEAAUJBRlPDwAAAQVoDAAABABCAGkMAAACAE8AawwAAAEAGABqDAAAAQA8AOoMAAAFAFUABAAFCQUZTw8AAAEFaAwAAAQAQgBpDAAAAgBPAGsMAAABABgAagwAAAEAPADqDAAABQBVAC4ABAp/GgACBAAICToalQ0ANAIABAAICToalQ0ANAIAAAA=.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAbAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgYJBgAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgABAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn8vAAMSAAkJvyCwAgAfAwloDAAABQBdAGkMAAAGAGEAawwAAAYAYwBqDAAABgBRAGwMAAAFAFsAbQwAAAUAWADqDAAABwBPAG4MAAAEADMAbwwAAAMARwASAAkJvyCwAgAfAwloDAAABQBdAGkMAAAGAGEAawwAAAYAYwBqDAAABQBRAGwMAAAEAFsAbQwAAAUAWADqDAAABwBPAG4MAAAEADMAbwwAAAMARwALAAIJiA+1OwB2AAJqDAAAAQApAGwMAAABACYAAAA=.',
Ye='Yetlian:BAACLgAFFH8LAAIDAAQJBCBfDwBOAQRoDAAABABRAGkMAAACADwAawwAAAEAWgDqDAAABABeAAMABAkEIF8PAE4BBGgMAAAEAFEAaQwAAAIAPABrDAAAAQBaAOoMAAAEAF4ALgAECn8WAAMDAAgJohuHFwBVAgADAAgJohuHFwBVAgACAAEJAAGqNgEWAAAAAA==.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8ZAAIhAAYJnyX8AAASAgZoDAAABgBgAGkMAAAGAGQAawwAAAMAYgBqDAAAAwBKAGwMAAACAFcA6gwAAAUAYwAhAAYJnyX8AAASAgZoDAAABgBgAGkMAAAGAGQAawwAAAMAYgBqDAAAAwBKAGwMAAACAFcA6gwAAAUAYwAuAAQKfyAAAiEACAmrIWUCAAADACEACAmrIWUCAAADAAAA.',
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

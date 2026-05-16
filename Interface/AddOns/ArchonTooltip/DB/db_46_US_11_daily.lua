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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Paladin-Protection','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='daily',zone=46,date='2026-05-14',data={Ad='Adelyne:BAAALgAECgMJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAO0iwDOAAdoDAAABAAJAGkMAAAEABAAawwAAAQACQBqDAAABAAPAGwMAAAEAAcAbQwAAAIABgDqDAAAAwAGAAIABwmsA7SLAM4AB2gMAAAEAAkAaQwAAAQAEABrDAAAAwAIAGoMAAAEAA8AbAwAAAQABwBtDAAAAgAGAOoMAAADAAYAAwABCaoDfyQAIwABawwAAAEACQAAAA==.',
Ag='Agaze:BAACLgAFFH8VAAIEAAYJHiBDDgCgAQZoDAAABABeAGkMAAADAFIAawwAAAQAWwBqDAAABABIAGwMAAADAD8A6gwAAAMATwAEAAYJHiBDDgCgAQZoDAAABABeAGkMAAADAFIAawwAAAQAWwBqDAAABABIAGwMAAADAD8A6gwAAAMATwAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAAALgAFFAMJAwABLgAECggJFwAFAMcSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8ZAAIGAAgJEhOXQwCdAQhoDAAABgBJAGkMAAAEACIAawwAAAMAQgBqDAAAAwA3AGwMAAADACwAbQwAAAEAJwDqDAAABAAvAG4MAAABACQABgAICRITl0MAnQEIaAwAAAYASQBpDAAABAAiAGsMAAADAEIAagwAAAMANwBsDAAAAwAsAG0MAAABACcA6gwAAAQALwBuDAAAAQAkAAAA.Arma:BAABLgAECn8cAAIHAAgJjiNGBQAwAwhoDAAABABhAGkMAAAEAGEAawwAAAQAWwBqDAAAAwBgAGwMAAADAFsAbQwAAAIAUADqDAAABQBeAG4MAAADAFUABwAICY4jRgUAMAMIaAwAAAQAYQBpDAAABABhAGsMAAAEAFsAagwAAAMAYABsDAAAAwBbAG0MAAACAFAA6gwAAAUAXgBuDAAAAwBVAAAA.Armadro:BAABLgAFFH8LAAIIAAQJPBz4HQCBAQRoDAAAAwBBAGkMAAADAFAAawwAAAIALADqDAAAAwBjAAgABAk8HPgdAIEBBGgMAAADAEEAaQwAAAMAUABrDAAAAgAsAOoMAAADAGMAAAA=.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8XAAMJAAYJ6h4WBgB3AQZoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAGwMAAABAD4A6gwAAAYAWwAJAAUJjiAWBgB3AQVoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAOoMAAAGAFsACgABCb8CPkwAQgABbAwAAAEABwAuAAQKfyUAAgkACAlqJXoEAFQDAAkACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8UAAILAAgJqgvSGQApAQhoDAAAAgASAGkMAAACACMAawwAAAMANgBqDAAAAwAcAGwMAAADABwAbQwAAAMAMQDqDAAAAgARAG4MAAACAAUACwAICaoL0hkAKQEIaAwAAAIAEgBpDAAAAgAjAGsMAAADADYAagwAAAMAHABsDAAAAwAcAG0MAAADADEA6gwAAAIAEQBuDAAAAgAFAAAA.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgIJAgABLgAECgkJKwAGAHwWAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8XAAIMAAgJPAwsIABhAQhoDAAAAwApAGkMAAAEABMAawwAAAMAHABqDAAAAgASAGwMAAACABgAbQwAAAEAGADqDAAABQAvAG4MAAADACEADAAICTwMLCAAYQEIaAwAAAMAKQBpDAAABAATAGsMAAADABwAagwAAAIAEgBsDAAAAgAYAG0MAAABABgA6gwAAAUALwBuDAAAAwAhAAAA.Bubbly:BAABLgAECn8rAAIGAAkJfBb4KwD0AQloDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAIAIwDqDAAABgBAAG4MAAADAFEAbwwAAAEAGAAGAAkJfBb4KwD0AQloDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAIAIwDqDAAABgBAAG4MAAADAFEAbwwAAAEAGAAAAA==.Butes:BAAALgAECggJCAAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAABLgAECn9GAAMHAAkJGCRbAQBFAwloDAAACgBjAGkMAAAKAGEAawwAAAoAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACwBgAG4MAAAFAFoAbwwAAAIASgAHAAkJGCRbAQBFAwloDAAACgBjAGkMAAAKAGEAawwAAAkAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACQBgAG4MAAAFAFoAbwwAAAIASgANAAIJxAvdXgBSAAJrDAAAAQAUAOoMAAACACcAAAA=.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgAECgEJAQAAAA==.Chulobulo:BAABLgAECn8WAAIOAAgJFBQmDwDVAQhoDAAABQAsAGkMAAAEAD4AawwAAAMAKABqDAAAAwAaAGwMAAACAD8A6gwAAAMALwBuDAAAAQBLAG8MAAABABoADgAICRQUJg8A1QEIaAwAAAUALABpDAAABAA+AGsMAAADACgAagwAAAMAGgBsDAAAAgA/AOoMAAADAC8AbgwAAAEASwBvDAAAAQAaAAAA.Chulosdck:BAAALgAECgUJCQABLgAECggJFgAOABQUAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAFAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8jAAIBAAkJKgyPFQC+AQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQABAAkJKgyPFQC+AQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQAAAA==.Cursed:BAABLgAECn8tAAMDAAkJhCAJAQCoAgloDAAABgBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABgBYAG4MAAAEAFUAbwwAAAIAVAADAAkJhCAJAQCoAgloDAAABQBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABQBYAG4MAAAEAFUAbwwAAAIAVAACAAIJlwtVvwBoAAJoDAAAAQASAOoMAAABACkAAAA=.',
Da='Dabz:BAAALgAECgcJEQAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMKAAkJ3yOiAQB7AwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAAEAEkAbwwAAAEAUQAKAAkJ3yOiAQB7AwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAADAEkAbwwAAAEAUQAJAAEJbBoEZwBJAAFuDAAAAQBDAAAA.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8OAAIEAAUJ2QpCMAAMAQVoDAAAAwAbAGkMAAAEACsAawwAAAMADABqDAAAAQAnAOoMAAADABsABAAFCdkKQjAADAEFaAwAAAMAGwBpDAAABAArAGsMAAADAAwAagwAAAEAJwDqDAAAAwAbAC4ABAp/KAACBAAJCYsVjh4AAQIABAAJCYsVjh4AAQIAAAA=.Dezric:BAAALgADCgYJDAABLgAECgEJAQAPAAAAAA==.Dezruf:BAAALgAECgEJAQAAAA==.',
Do='Dotomic:BAAALgAECgQJBQABLgAFFAcJGQAQAAAfAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAPAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAAPAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8ZAAIRAAgJFgfbDgD5AAhoDAAABAAVAGkMAAAEABYAawwAAAQADgBqDAAAAwAKAGwMAAACAAQAbQwAAAEABgDqDAAABQAoAG4MAAACABAAEQAICRYH2w4A+QAIaAwAAAQAFQBpDAAABAAWAGsMAAAEAA4AagwAAAMACgBsDAAAAgAEAG0MAAABAAYA6gwAAAUAKABuDAAAAgAQAAAA.',
Ei='Eisenhørn:BAAALgADCgYJBgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8ZAAIGAAcJlQbfhQAEAQdoDAAABQANAGkMAAAFABQAawwAAAQAIQBqDAAAAgAIAGwMAAADAAkA6gwAAAUAEQBuDAAAAQAHAAYABwmVBt+FAAQBB2gMAAAFAA0AaQwAAAUAFABrDAAABAAhAGoMAAACAAgAbAwAAAMACQDqDAAABQARAG4MAAABAAcAAAA=.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgQJBQABLgAFFAEJAgAPAAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAYJFQASAGUbAA==.',
Fr='Fragga:BAABLgAECn8XAAITAAYJuxRxLgA0AQZoDAAAAwAkAGkMAAAGAEsAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAUAPQATAAYJuxRxLgA0AQZoDAAAAwAkAGkMAAAGAEsAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAUAPQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn86AAIUAAkJGRr3GAAyAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgAUAAkJGRr3GAAyAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAAVAKgiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgADCgcJCgAAAA==.Groovexgroov:BAAALgAECggJCwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holynight:BAAALgADCgEJAQABLgADCgcJCgAPAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMJAAYJownMSgAcAQZoDAAABAAaAGkMAAAEAB8AawwAAAQAHwBqDAAAAwAcAGwMAAACAAsA6gwAAAMAFQAJAAYJownMSgAcAQZoDAAAAgAaAGkMAAACAB8AawwAAAIAHwBqDAAAAgAcAGwMAAABAAsA6gwAAAEAFQAWAAYJ3gLVHgDiAAZoDAAAAgAEAGkMAAACAAsAawwAAAIADwBqDAAAAQAEAGwMAAABAAEA6gwAAAIABAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8uAAIBAAgJRxnWCgBZAghoDAAABwBMAGkMAAAHAEoAawwAAAcAPwBqDAAABQBTAGwMAAAEAB8AbQwAAAMAJwDqDAAACgBXAG4MAAADAD4AAQAICUcZ1goAWQIIaAwAAAcATABpDAAABwBKAGsMAAAHAD8AagwAAAUAUwBsDAAABAAfAG0MAAADACcA6gwAAAoAVwBuDAAAAwA+AAAA.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8VAAIIAAkJRxtmGwBsAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAIAAkJRxtmGwBsAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIXAAgJbRFdJQCBAQhoDAAAAwAzAGkMAAADADkAawwAAAQASwBqDAAAAgAwAGwMAAABABEAbQwAAAEAEQDqDAAABgA+AG4MAAABABoAFwAICW0RXSUAgQEIaAwAAAMAMwBpDAAAAwA5AGsMAAAEAEsAagwAAAIAMABsDAAAAQARAG0MAAABABEA6gwAAAYAPgBuDAAAAQAaAAAA.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIOAAgJuiAkEQCYAghoDAAABQBXAGkMAAAEAGEAawwAAAQAVgBqDAAAAgAlAGwMAAACAEsAbQwAAAMASwDqDAAABQBSAG4MAAABAFIADgAICbogJBEAmAIIaAwAAAUAVwBpDAAABABhAGsMAAAEAFYAagwAAAIAJQBsDAAAAgBLAG0MAAADAEsA6gwAAAUAUgBuDAAAAQBSAAAA.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8KAAIWAAQJNx+FAQCLAQRoDAAABQBhAGkMAAABAFMAawwAAAEALgDqDAAAAwBbABYABAk3H4UBAIsBBGgMAAAFAGEAaQwAAAEAUwBrDAAAAQAuAOoMAAADAFsALgAECn8bAAIWAAkJHx/BAwDuAgAWAAkJHx/BAwDuAgAAAA==.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAABLgAECn9CAAIRAAkJnBXEBAAEAgloDAAACgBEAGkMAAAJADcAawwAAAkANwBqDAAACQBGAGwMAAAIAEsAbQwAAAMARADqDAAADAA9AG4MAAAEACAAbwwAAAIAGQARAAkJnBXEBAAEAgloDAAACgBEAGkMAAAJADcAawwAAAkANwBqDAAACQBGAGwMAAAIAEsAbQwAAAMARADqDAAADAA9AG4MAAAEACAAbwwAAAIAGQAAAA==.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8bAAIYAAYJdAbJGQDKAAZoDAAABgAJAGkMAAAGABoAawwAAAUAEgBqDAAAAwARAGwMAAADAA8A6gwAAAQADQAYAAYJdAbJGQDKAAZoDAAABgAJAGkMAAAGABoAawwAAAUAEgBqDAAAAwARAGwMAAADAA8A6gwAAAQADQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIZAAkJ6RfCAgAlAgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAZAAkJ6RfCAgAlAgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAAAA==.',
Kl='Kløey:BAAALgAECgYJEwAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAIAEEeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAABLgAECn83AAMBAAkJWQ0DIgCEAQloDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAACAAiAGwMAAAIADgAbQwAAAUADQDqDAAACQAWAG4MAAAFABEAbwwAAAIAHwABAAgJ/AoDIgCEAQhoDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAABwATAGwMAAAHACoAbQwAAAIABADqDAAACQAWAG4MAAACAAQAGgAFCQsM/zEA5wAFagwAAAEAIgBsDAAAAQA4AG0MAAADAA0AbgwAAAMAEQBvDAAAAgAfAAAA.Lussypipz:BAAALgAECgYJDQAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8XAAMIAAkJnRFmNwDnAQloDAAAAwAuAGkMAAACAD8AawwAAAIALwBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAABAAqAG4MAAADAC8AbwwAAAEAJgAIAAkJnRFmNwDnAQloDAAAAgAuAGkMAAACAD8AawwAAAIALwBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAABAAqAG4MAAADAC8AbwwAAAEAJgAbAAEJJA96DgA/AAFoDAAAAQAmAAAA.',
Me='Meheret:BAABLgAECn8yAAIIAAkJ1wR8awBTAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAIAAkJ1wR8awBTAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIIAAkJQR7WFACXAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAIAAkJQR7WFACXAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIOAAgJjRqCDgDeAQhoDAAAAwBBAGkMAAADAD8AawwAAAMATgBqDAAAAwA9AGwMAAADAEwAbQwAAAIAQwDqDAAAAwBJAG4MAAADADIADgAICY0agg4A3gEIaAwAAAMAQQBpDAAAAwA/AGsMAAADAE4AagwAAAMAPQBsDAAAAwBMAG0MAAACAEMA6gwAAAMASQBuDAAAAwAyAAAA.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAIAEEeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgMJBAABLgAFFAMJBQATAOMYAA==.Mythx:BAACLgAFFH8FAAITAAMJ4xh5GgAAAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwATAAMJ4xh5GgAAAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwAuAAQKfyoAAhMACAmsIpwFAL8CABMACAmsIpwFAL8CAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8tAAIXAAkJOhliDwBJAgloDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABwA6AG4MAAACABsAbwwAAAEATAAXAAkJOhliDwBJAgloDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABwA6AG4MAAACABsAbwwAAAEATAAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgZoDAAABQBaAGkMAAAEAFEAawwAAAQASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAADAAYJph/GBQAKAgZoDAAAAwBaAGkMAAADAFEAawwAAAMASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAACAAMJ3wqC4wCTAANoDAAAAQAdAGkMAAABABwAawwAAAEAGQAcAAEJ/AgReAAsAAFoDAAAAQAXAAAA.Netharec:BAAALgADCgEJAQAAAA==.Nevai:BAABLgAECn8WAAIXAAgJXxNOGQDfAQhoDAAAAwA5AGkMAAADAFAAawwAAAMANgBqDAAAAwAjAGwMAAACAAcAbQwAAAEAIQDqDAAABQA9AG4MAAACAEIAFwAICV8TThkA3wEIaAwAAAMAOQBpDAAAAwBQAGsMAAADADYAagwAAAMAIwBsDAAAAgAHAG0MAAABACEA6gwAAAUAPQBuDAAAAgBCAAAA.',
Ni='Nielas:BAAALgAECgcJEwAAAA==.Nihilus:BAACLgAFFH8PAAIdAAUJVheTCACMAQVoDAAAAwBNAGkMAAACACcAawwAAAMALwBqDAAAAQAVAOoMAAAGAEoAHQAFCVYXkwgAjAEFaAwAAAMATQBpDAAAAgAnAGsMAAADAC8AagwAAAEAFQDqDAAABgBKAC4ABAp/FQACHQAHCRYkuS8AeQIAHQAHCRYkuS8AeQIAAAA=.Nilari:BAABLgAECn8UAAIeAAYJIQkbIACxAAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAeAAYJIQkbIACxAAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAAAA==.Nine:BAAALgADCgYJBgABLgAECgkJRgAHABgkAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAIVAAgJqCJHAQCoAghoDAAABABTAGkMAAAFAFkAawwAAAUAUQBqDAAABABXAGwMAAADAGEAbQwAAAIAXwDqDAAABABZAG4MAAABAFQAFQAICagiRwEAqAIIaAwAAAQAUwBpDAAABQBZAGsMAAAFAFEAagwAAAQAVwBsDAAAAwBhAG0MAAACAF8A6gwAAAQAWQBuDAAAAQBUAAAA.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAGAK0XAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgADCgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJEAABADIaAA==.Owls:BAACLgAFFH8QAAIBAAQJMhqpEwBBAQRoDAAABQBNAGkMAAAFAEMAawwAAAIAIgDqDAAABABYAAEABAkyGqkTAEEBBGgMAAAFAE0AaQwAAAUAQwBrDAAAAgAiAOoMAAAEAFgALgAECn82AAMBAAkJFiMrAwAoAwABAAkJhiArAwAoAwAaAAcJGyT3CgCfAgABLgAFFAQJEAABADIaAA==.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMfAAgJ3w1aBwCKAQhoDAAABAA0AGkMAAAEAD8AawwAAAQAJABqDAAABAA7AGwMAAAEACMAbQwAAAIAEADqDAAABAAcAG4MAAACAA0AHwAICd8NWgcAigEIaAwAAAMANABpDAAABAA/AGsMAAADACQAagwAAAIAOwBsDAAAAgAjAG0MAAACABAA6gwAAAMAHABuDAAAAQANAA4ABglQAZ5LAM0ABmgMAAABAAMAawwAAAEAAgBqDAAAAgAEAGwMAAACAAcA6gwAAAEAAgBuDAAAAQABAAAA.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8HAAIdAAQJrRqCKwBUAQRoDAAAAgBSAGkMAAACACkAawwAAAEAQgDqDAAAAgBSAB0ABAmtGoIrAFQBBGgMAAACAFIAaQwAAAIAKQBrDAAAAQBCAOoMAAACAFIALgAECn8yAAMdAAkJUSWeBACKAwAdAAkJUSWeBACKAwAgAAEJOSGuGABeAAAAAA==.Proved:BAABLgAECn89AAIaAAkJmRweBgDDAgloDAAACwBjAGkMAAAJAEUAawwAAAgAXQBqDAAACQBaAGwMAAAIAFcAbQwAAAMANwDqDAAACABdAG4MAAAEADoAbwwAAAEADAAaAAkJmRweBgDDAgloDAAACwBjAGkMAAAJAEUAawwAAAgAXQBqDAAACQBaAGwMAAAIAFcAbQwAAAMANwDqDAAACABdAG4MAAAEADoAbwwAAAEADAAAAA==.',
Ps='Psillycybin:BAAALgAECgcJCQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgADCgUJBQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAABLgAECn8sAAIKAAkJChNHIwDOAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAKAAkJChNHIwDOAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAAAA==.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAAAAA==.Rizy:BAABLgAECn8YAAIdAAgJsA5KSgCCAQhoDAAABAAsAGkMAAAEACcAawwAAAQAHwBqDAAAAwArAGwMAAACABoAbQwAAAEAJQDqDAAABAArAG4MAAACACkAHQAICbAOSkoAggEIaAwAAAQALABpDAAABAAnAGsMAAAEAB8AagwAAAMAKwBsDAAAAgAaAG0MAAABACUA6gwAAAQAKwBuDAAAAgApAAAA.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAABLgAECn85AAIEAAkJbSDTBQDxAgloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAEAAkJbSDTBQDxAgloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAAAA==.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiFCLADUAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwACAAYJPiFCLADUAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAECgkJRgAHABgkAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8qAAIdAAgJCRyzHgA5AghoDAAACABPAGkMAAAHAFkAawwAAAcAVQBqDAAABQBYAGwMAAAFADkAbQwAAAEAJgDqDAAABgBGAG4MAAADAFEAHQAICQkcsx4AOQIIaAwAAAgATwBpDAAABwBZAGsMAAAHAFUAagwAAAUAWABsDAAABQA5AG0MAAABACYA6gwAAAYARgBuDAAAAwBRAAAA.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8UAAIeAAcJvQxGGQDsAAdoDAAAAwAWAGkMAAAEADoAawwAAAUAHwBqDAAAAgAQAOoMAAAEACcAbgwAAAEAIgBvDAAAAQAJAB4ABwm9DEYZAOwAB2gMAAADABYAaQwAAAQAOgBrDAAABQAfAGoMAAACABAA6gwAAAQAJwBuDAAAAQAiAG8MAAABAAkAAAA=.',
Sl='Slashology:BAAALgAECgYJBwAAAA==.',
Sm='Smallpally:BAAALgAECgQJDQAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8eAAIGAAcJSBcoRgCVAQdoDAAABQBDAGkMAAAFAEUAawwAAAUANwBqDAAABABFAGwMAAAEAEAA6gwAAAYAMgBuDAAAAQAxAAYABwlIFyhGAJUBB2gMAAAFAEMAaQwAAAUARQBrDAAABQA3AGoMAAAEAEUAbAwAAAQAQADqDAAABgAyAG4MAAABADEAAAA=.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA8kUABUAQhoDAAABAA9AGkMAAAEACcAawwAAAUAKABqDAAABABLAGwMAAADAEEAbQwAAAIAGwDqDAAABAAjAG4MAAABAAQAAgAICUgPJFAAVAEIaAwAAAQAPQBpDAAABAAnAGsMAAAFACgAagwAAAQASwBsDAAAAwBBAG0MAAACABsA6gwAAAQAIwBuDAAAAQAEAAAA.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAABLgAECn8VAAMGAAcJHhfKTACCAQdoDAAABABMAGkMAAADAEEAawwAAAMAUgBqDAAABABRAGwMAAACACAA6gwAAAQATgBuDAAAAQATAAYABgk0GcpMAIIBBmgMAAABAEwAaQwAAAEAQQBrDAAAAQBSAGoMAAABAFEA6gwAAAEATgBuDAAAAQATAB4ABgnxCv4dAMEABmgMAAADABgAaQwAAAIAEgBrDAAAAgAIAGoMAAADABcAbAwAAAIAIADqDAAAAwA4AAEuAAUUAwkFABMA4xgA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIIAAgJHBvBAADdAghoDAAAAwBjAGkMAAAFAGEAawwAAAUAWwBqDAAABABFAGwMAAABAB8AbQwAAAEAIQDqDAAABQBjAG4MAAABACAACAAICRwbwQAA3QIIaAwAAAMAYwBpDAAABQBhAGsMAAAFAFsAagwAAAQARQBsDAAAAQAfAG0MAAABACEA6gwAAAUAYwBuDAAAAQAgAC4ABAp/JgACCAAJCeskYwIA2AMACAAJCeskYwIA2AMAAAA=.Touchi:BAAALgAECgEJAgABLgAECggJHQAYAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8dAAIYAAgJchpYBgARAghoDAAABgBeAGkMAAAEAEYAawwAAAQARwBqDAAAAwBSAGwMAAACADwAbQwAAAIAKwDqDAAABABEAG4MAAAEAEEAGAAICXIaWAYAEQIIaAwAAAYAXgBpDAAABABGAGsMAAAEAEcAagwAAAMAUgBsDAAAAgA8AG0MAAACACsA6gwAAAQARABuDAAABABBAAAA.Turbid:BAABLgAECn8oAAIEAAkJghNWJQDaAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAEAAkJghNWJQDaAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIGAAkJrRdSHQBAAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAGAAkJrRdSHQBAAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgYJCgAAAA==.',
Yo='Yogurt:BAAALgAECgYJCQABLgAECgkJKwAGAHwWAA==.',
Yu='Yusuke:BAABLgAECn8WAAMhAAcJfhFRHAByAQdoDAAABABEAGkMAAAEACoAawwAAAQASgBqDAAAAwAXAGwMAAADABoA6gwAAAMAJABuDAAAAQATACEABwl+EVEcAHIBB2gMAAACAEQAaQwAAAIAKgBrDAAAAgBKAGoMAAACABcAbAwAAAIAGgDqDAAAAgAkAG4MAAABABMADQAGCT0JckAA4AAGaAwAAAIAHQBpDAAAAgAnAGsMAAACABkAagwAAAEABQBsDAAAAQANAOoMAAABABsAAS4ABAoICRQACwCqCwA=.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAAALgAECgYJCwAAAA==.',
['Éz']='Ézon:BAAALgADCggJCAAAAA==.',
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

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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='daily',zone=46,date='2026-05-16',data={Ad='Adelyne:BAAALgAECgMJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMCmQDLAAdoDAAABAAJAGkMAAAEABAAawwAAAQACQBqDAAABAAPAGwMAAAEAAcAbQwAAAIABgDqDAAAAwAGAAIABwmsAwKZAMsAB2gMAAAEAAkAaQwAAAQAEABrDAAAAwAIAGoMAAAEAA8AbAwAAAQABwBtDAAAAgAGAOoMAAADAAYAAwABCaoDlCkAIAABawwAAAEACQAAAA==.',
Ag='Agaze:BAACLgAFFH8VAAIEAAYJHiAkEACfAQZoDAAABABeAGkMAAADAFIAawwAAAQAWwBqDAAABABIAGwMAAADAD8A6gwAAAMATwAEAAYJHiAkEACfAQZoDAAABABeAGkMAAADAFIAawwAAAQAWwBqDAAABABIAGwMAAADAD8A6gwAAAMATwAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJCAAAAA==.',
Ap='Applejuuice:BAABLgAFFH8FAAIFAAMJ5BI4YADyAANoDAAAAgAqAGkMAAACABcA6gwAAAEATwAFAAMJ5BI4YADyAANoDAAAAgAqAGkMAAACABcA6gwAAAEATwABLgAECggJFwAGAMcSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8fAAIHAAgJuBXWTQCUAQhoDAAABwBPAGkMAAAFADsAawwAAAQAQgBqDAAABAA3AGwMAAAEAD0AbQwAAAIAJwDqDAAABAAvAG4MAAABACQABwAICbgV1k0AlAEIaAwAAAcATwBpDAAABQA7AGsMAAAEAEIAagwAAAQANwBsDAAABAA9AG0MAAACACcA6gwAAAQALwBuDAAAAQAkAAAA.Arma:BAABLgAECn8cAAIIAAgJjiNGBQAwAwhoDAAABABhAGkMAAAEAGEAawwAAAQAWwBqDAAAAwBgAGwMAAADAFsAbQwAAAIAUADqDAAABQBeAG4MAAADAFUACAAICY4jRgUAMAMIaAwAAAQAYQBpDAAABABhAGsMAAAEAFsAagwAAAMAYABsDAAAAwBbAG0MAAACAFAA6gwAAAUAXgBuDAAAAwBVAAAA.Armadro:BAABLgAFFH8MAAIJAAQJPBzfIQB5AQRoDAAAAwBBAGkMAAADAFAAawwAAAMALADqDAAAAwBjAAkABAk8HN8hAHkBBGgMAAADAEEAaQwAAAMAUABrDAAAAwAsAOoMAAADAGMAAAA=.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8XAAMKAAYJ6h4WBgB3AQZoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAGwMAAABAD4A6gwAAAYAWwAKAAUJjiAWBgB3AQVoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAOoMAAAGAFsACwABCb8Csk8AQgABbAwAAAEABwAuAAQKfyUAAgoACAlqJXoEAFQDAAoACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAABLgAECn8UAAIMAAgJqguYHAAdAQhoDAAAAgASAGkMAAACACMAawwAAAMANgBqDAAAAwAcAGwMAAADABwAbQwAAAMAMQDqDAAAAgARAG4MAAACAAUADAAICaoLmBwAHQEIaAwAAAIAEgBpDAAAAgAjAGsMAAADADYAagwAAAMAHABsDAAAAwAcAG0MAAADADEA6gwAAAIAEQBuDAAAAgAFAAAA.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgYJCAABLgAECgkJLAAHALwWAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8cAAINAAkJxAxdGgCeAQloDAAABAApAGkMAAAFAB8AawwAAAQAIwBqDAAAAwAYAGwMAAACABgAbQwAAAEAGADqDAAABQAvAG4MAAADACEAbwwAAAEAFgANAAkJxAxdGgCeAQloDAAABAApAGkMAAAFAB8AawwAAAQAIwBqDAAAAwAYAGwMAAACABgAbQwAAAEAGADqDAAABQAvAG4MAAADACEAbwwAAAEAFgAAAA==.Bubbly:BAABLgAECn8sAAIHAAkJvBb/MQDwAQloDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAMAKADqDAAABgBAAG4MAAADAFEAbwwAAAEAGAAHAAkJvBb/MQDwAQloDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAMAKADqDAAABgBAAG4MAAADAFEAbwwAAAEAGAAAAA==.Butes:BAAALgAECggJCAAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAACLgAFFH8KAAIIAAMJxCGwCgAwAQNoDAAABQBeAGkMAAACAFEA6gwAAAMAVAAIAAMJxCGwCgAwAQNoDAAABQBeAGkMAAACAFEA6gwAAAMAVAAuAAQKf1QAAwgACQkeJf4AAFoDAAgACQkeJf4AAFoDAA4AAgnEC91eAFIAAAAA.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgAECgEJAQAAAA==.Chulobulo:BAABLgAECn8WAAIPAAgJFBQCEgDEAQhoDAAABQAsAGkMAAAEAD4AawwAAAMAKABqDAAAAwAaAGwMAAACAD8A6gwAAAMALwBuDAAAAQBLAG8MAAABABoADwAICRQUAhIAxAEIaAwAAAUALABpDAAABAA+AGsMAAADACgAagwAAAMAGgBsDAAAAgA/AOoMAAADAC8AbgwAAAEASwBvDAAAAQAaAAAA.Chulosdck:BAAALgAECgUJCQABLgAECggJFgAPABQUAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAGAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8sAAIBAAkJKgziFwC7AQloDAAABwAmAGkMAAAHADIAawwAAAcAHQBqDAAABQAfAGwMAAAFAEAAbQwAAAQADgDqDAAABAAhAG4MAAADAAgAbwwAAAIACQABAAkJKgziFwC7AQloDAAABwAmAGkMAAAHADIAawwAAAcAHQBqDAAABQAfAGwMAAAFAEAAbQwAAAQADgDqDAAABAAhAG4MAAADAAgAbwwAAAIACQAAAA==.Cursed:BAABLgAECn8tAAMDAAkJhCCNAQCMAgloDAAABgBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABgBYAG4MAAAEAFUAbwwAAAIAVAADAAkJhCCNAQCMAgloDAAABQBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABQBYAG4MAAAEAFUAbwwAAAIAVAACAAIJlwuaywBoAAJoDAAAAQASAOoMAAABACkAAAA=.',
Da='Dabz:BAAALgAFFAEJAQAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMLAAkJ3yP0AQB1AwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAAEAEkAbwwAAAEAUQALAAkJ3yP0AQB1AwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAADAEkAbwwAAAEAUQAKAAEJbBoSbQBGAAFuDAAAAQBDAAAA.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8PAAIEAAUJ2QoQMwAMAQVoDAAAAwAbAGkMAAAEACsAawwAAAMADABqDAAAAgAnAOoMAAADABsABAAFCdkKEDMADAEFaAwAAAMAGwBpDAAABAArAGsMAAADAAwAagwAAAIAJwDqDAAAAwAbAC4ABAp/LQACBAAJCfUWTx0AIAIABAAJCfUWTx0AIAIAAAA=.Dezric:BAAALgADCgYJDAABLgAECgYJDQAQAAAAAA==.Dezruf:BAAALgAECgEJAQABLgAECgYJDQAQAAAAAA==.',
Do='Dotomic:BAAALgAFFAEJAQABLgAFFAcJGQARAAAfAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAQAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAAQAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8ZAAISAAgJFgcQEAD4AAhoDAAABAAVAGkMAAAEABYAawwAAAQADgBqDAAAAwAKAGwMAAACAAQAbQwAAAEABgDqDAAABQAoAG4MAAACABAAEgAICRYHEBAA+AAIaAwAAAQAFQBpDAAABAAWAGsMAAAEAA4AagwAAAMACgBsDAAAAgAEAG0MAAABAAYA6gwAAAUAKABuDAAAAgAQAAAA.',
Ei='Eisenhørn:BAAALgADCgYJBgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8ZAAIHAAcJlQZRkwABAQdoDAAABQANAGkMAAAFABQAawwAAAQAIQBqDAAAAgAIAGwMAAADAAkA6gwAAAUAEQBuDAAAAQAHAAcABwmVBlGTAAEBB2gMAAAFAA0AaQwAAAUAFABrDAAABAAhAGoMAAACAAgAbAwAAAMACQDqDAAABQARAG4MAAABAAcAAAA=.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgQJBQABLgAFFAEJAgAQAAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAYJFQATAGUbAA==.',
Fr='Fragga:BAABLgAECn8XAAIUAAYJuxQGNQAlAQZoDAAAAwAkAGkMAAAGAEsAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAUAPQAUAAYJuxQGNQAlAQZoDAAAAwAkAGkMAAAGAEsAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAUAPQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn9IAAIVAAkJ7Rt9EwBsAgloDAAACQBUAGkMAAAJAE4AawwAAAkAVgBqDAAACgBQAGwMAAAIADsAbQwAAAUARADqDAAACwBLAG4MAAAHADMAbwwAAAQAQwAVAAkJ7Rt9EwBsAgloDAAACQBUAGkMAAAJAE4AawwAAAkAVgBqDAAACgBQAGwMAAAIADsAbQwAAAUARADqDAAACwBLAG4MAAAHADMAbwwAAAQAQwAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAAWAKgiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgYJCQAAAA==.Grizzly:BAAALgADCgcJCgABLgAECgYJEQAQAAAAAA==.Groovexgroov:BAAALgAECggJCwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holynight:BAAALgADCgEJAQABLgAECgYJEQAQAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMKAAYJownMSgAcAQZoDAAABAAaAGkMAAAEAB8AawwAAAQAHwBqDAAAAwAcAGwMAAACAAsA6gwAAAMAFQAKAAYJownMSgAcAQZoDAAAAgAaAGkMAAACAB8AawwAAAIAHwBqDAAAAgAcAGwMAAABAAsA6gwAAAEAFQAXAAYJ3gLVHgDiAAZoDAAAAgAEAGkMAAACAAsAawwAAAIADwBqDAAAAQAEAGwMAAABAAEA6gwAAAIABAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8uAAIBAAgJRxmzDABMAghoDAAABwBMAGkMAAAHAEoAawwAAAcAPwBqDAAABQBTAGwMAAAEAB8AbQwAAAMAJwDqDAAACgBXAG4MAAADAD4AAQAICUcZswwATAIIaAwAAAcATABpDAAABwBKAGsMAAAHAD8AagwAAAUAUwBsDAAABAAfAG0MAAADACcA6gwAAAoAVwBuDAAAAwA+AAAA.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istari:BAAALgAECgIJAgAAAA==.Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8VAAIJAAkJRxsrIQBcAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAJAAkJRxsrIQBcAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIYAAgJbREZKQB2AQhoDAAAAwAzAGkMAAADADkAawwAAAQASwBqDAAAAgAwAGwMAAABABEAbQwAAAEAEQDqDAAABgA+AG4MAAABABoAGAAICW0RGSkAdgEIaAwAAAMAMwBpDAAAAwA5AGsMAAAEAEsAagwAAAIAMABsDAAAAQARAG0MAAABABEA6gwAAAYAPgBuDAAAAQAaAAAA.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIPAAgJuiAkEQCYAghoDAAABQBXAGkMAAAEAGEAawwAAAQAVgBqDAAAAgAlAGwMAAACAEsAbQwAAAMASwDqDAAABQBSAG4MAAABAFIADwAICbogJBEAmAIIaAwAAAUAVwBpDAAABABhAGsMAAAEAFYAagwAAAIAJQBsDAAAAgBLAG0MAAADAEsA6gwAAAUAUgBuDAAAAQBSAAAA.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8KAAIXAAQJNx/GAQCFAQRoDAAABQBhAGkMAAABAFMAawwAAAEALgDqDAAAAwBbABcABAk3H8YBAIUBBGgMAAAFAGEAaQwAAAEAUwBrDAAAAQAuAOoMAAADAFsALgAECn8fAAIXAAkJ8B+PAQDnAgAXAAkJ8B+PAQDnAgAAAA==.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAACLgAFFH8IAAISAAMJJxNiBADVAANoDAAAAwBWAGkMAAACAAwA6gwAAAMALwASAAMJJxNiBADVAANoDAAAAwBWAGkMAAACAAwA6gwAAAMALwAuAAQKf1AAAhIACQmnFxsEADcCABIACQmnFxsEADcCAAAA.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8bAAIZAAYJdAZHHADAAAZoDAAABgAJAGkMAAAGABoAawwAAAUAEgBqDAAAAwARAGwMAAADAA8A6gwAAAQADQAZAAYJdAZHHADAAAZoDAAABgAJAGkMAAAGABoAawwAAAUAEgBqDAAAAwARAGwMAAADAA8A6gwAAAQADQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIaAAkJ6RdpAwAZAgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAaAAkJ6RdpAwAZAgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAAAA==.',
Kl='Kløey:BAAALgAECgYJEwAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAJAEEeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAACLgAFFH8IAAIbAAMJoQPyGACiAANoDAAABAARAGkMAAACAAYA6gwAAAIABAAbAAMJoQPyGACiAANoDAAABAARAGkMAAACAAYA6gwAAAIABAAuAAQKf0UAAxsACQm8DbgcAJcBABsACQk+DLgcAJcBAAEACAn8CgMiAIQBAAAA.Lussypipz:BAAALgAECgYJDQAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8eAAMJAAkJtRWIKQAyAgloDAAABAA/AGkMAAADAE8AawwAAAMALwBqDAAABABBAGwMAAAEADUAbQwAAAMAOwDqDAAABQA2AG4MAAADAC8AbwwAAAEAJgAJAAkJtRWIKQAyAgloDAAAAwA/AGkMAAADAE8AawwAAAMALwBqDAAABABBAGwMAAAEADUAbQwAAAMAOwDqDAAABQA2AG4MAAADAC8AbwwAAAEAJgAcAAEJJA9NDwA6AAFoDAAAAQAmAAAA.',
Me='Meheret:BAABLgAECn9AAAIJAAkJcQZeZwBuAQloDAAABwAKAGkMAAAHABYAawwAAAcAHwBqDAAACQAQAGwMAAAIABsAbQwAAAUADADqDAAACgANAG4MAAAHAAUAbwwAAAQACQAJAAkJcQZeZwBuAQloDAAABwAKAGkMAAAHABYAawwAAAcAHwBqDAAACQAQAGwMAAAIABsAbQwAAAUADADqDAAACgANAG4MAAAHAAUAbwwAAAQACQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIJAAkJQR5bGgCCAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAJAAkJQR5bGgCCAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIPAAgJjRqIEQDKAQhoDAAAAwBBAGkMAAADAD8AawwAAAMATgBqDAAAAwA9AGwMAAADAEwAbQwAAAIAQwDqDAAAAwBJAG4MAAADADIADwAICY0aiBEAygEIaAwAAAMAQQBpDAAAAwA/AGsMAAADAE4AagwAAAMAPQBsDAAAAwBMAG0MAAACAEMA6gwAAAMASQBuDAAAAwAyAAAA.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAJAEEeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgUJCAABLgAFFAMJBgAUAEoeAA==.Mythx:BAACLgAFFH8GAAIUAAMJSh6hGQAQAQNoDAAAAgA7AGkMAAABAFwA6gwAAAMAUAAUAAMJSh6hGQAQAQNoDAAAAgA7AGkMAAABAFwA6gwAAAMAUAAuAAQKfyoAAhQACAmsIkQHAKsCABQACAmsIkQHAKsCAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8tAAIYAAkJOhmOEQA+AgloDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABwA6AG4MAAACABsAbwwAAAEATAAYAAkJOhmOEQA+AgloDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABwA6AG4MAAACABsAbwwAAAEATAAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgZoDAAABQBaAGkMAAAEAFEAawwAAAQASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAADAAYJph/GBQAKAgZoDAAAAwBaAGkMAAADAFEAawwAAAMASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAACAAMJ3wqC4wCTAANoDAAAAQAdAGkMAAABABwAawwAAAEAGQAdAAEJ/AgReAAsAAFoDAAAAQAXAAAA.Netharec:BAAALgADCgEJAQABLgAFFAQJBwANAAEWAA==.Nevai:BAABLgAECn8WAAIYAAgJXxNtHADTAQhoDAAAAwA5AGkMAAADAFAAawwAAAMANgBqDAAAAwAjAGwMAAACAAcAbQwAAAEAIQDqDAAABQA9AG4MAAACAEIAGAAICV8TbRwA0wEIaAwAAAMAOQBpDAAAAwBQAGsMAAADADYAagwAAAMAIwBsDAAAAgAHAG0MAAABACEA6gwAAAUAPQBuDAAAAgBCAAAA.',
Ni='Nielas:BAAALgAECgcJEwAAAA==.Nihilus:BAACLgAFFH8PAAIFAAUJVheTCACMAQVoDAAAAwBNAGkMAAACACcAawwAAAMALwBqDAAAAQAVAOoMAAAGAEoABQAFCVYXkwgAjAEFaAwAAAMATQBpDAAAAgAnAGsMAAADAC8AagwAAAEAFQDqDAAABgBKAC4ABAp/FQACBQAHCRYkuS8AeQIABQAHCRYkuS8AeQIAAAA=.Nilari:BAABLgAECn8UAAIeAAYJIQniIgCoAAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAeAAYJIQniIgCoAAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAAAA==.Nine:BAAALgADCgYJBgABLgAFFAMJCgAIAMQhAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAIWAAgJqCKdAQCYAghoDAAABABTAGkMAAAFAFkAawwAAAUAUQBqDAAABABXAGwMAAADAGEAbQwAAAIAXwDqDAAABABZAG4MAAABAFQAFgAICaginQEAmAIIaAwAAAQAUwBpDAAABQBZAGsMAAAFAFEAagwAAAQAVwBsDAAAAwBhAG0MAAACAF8A6gwAAAQAWQBuDAAAAQBUAAAA.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAHAK0XAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Of='Officimeeg:BAAALgADCgEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJEQABANUbAA==.Owls:BAACLgAFFH8RAAIBAAQJ1RscFABGAQRoDAAABQBNAGkMAAAFAEMAawwAAAMAMwDqDAAABABYAAEABAnVGxwUAEYBBGgMAAAFAE0AaQwAAAUAQwBrDAAAAwAzAOoMAAAEAFgALgAECn83AAMBAAkJFiPnAwAcAwABAAkJhiDnAwAcAwAbAAcJGyT3CgCfAgABLgAFFAQJEQABANUbAA==.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMfAAgJ3w1HCAB/AQhoDAAABAA0AGkMAAAEAD8AawwAAAQAJABqDAAABAA7AGwMAAAEACMAbQwAAAIAEADqDAAABAAcAG4MAAACAA0AHwAICd8NRwgAfwEIaAwAAAMANABpDAAABAA/AGsMAAADACQAagwAAAIAOwBsDAAAAgAjAG0MAAACABAA6gwAAAMAHABuDAAAAQANAA8ABglQAZ5LAM0ABmgMAAABAAMAawwAAAEAAgBqDAAAAgAEAGwMAAACAAcA6gwAAAEAAgBuDAAAAQABAAAA.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8HAAIFAAQJrRpiMQBQAQRoDAAAAgBSAGkMAAACACkAawwAAAEAQgDqDAAAAgBSAAUABAmtGmIxAFABBGgMAAACAFIAaQwAAAIAKQBrDAAAAQBCAOoMAAACAFIALgAECn8yAAMFAAkJUSWeBACKAwAFAAkJUSWeBACKAwAgAAEJOSHvGwBbAAAAAA==.Proved:BAABLgAECn9EAAIbAAkJmRy+BgDEAgloDAAADABjAGkMAAAKAEUAawwAAAkAXQBqDAAACgBaAGwMAAAJAFcAbQwAAAQANwDqDAAACQBdAG4MAAAEADoAbwwAAAEADAAbAAkJmRy+BgDEAgloDAAADABjAGkMAAAKAEUAawwAAAkAXQBqDAAACgBaAGwMAAAJAFcAbQwAAAQANwDqDAAACQBdAG4MAAAEADoAbwwAAAEADAAAAA==.',
Ps='Psillycybin:BAAALgAECgcJDQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgADCgUJBQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAACLgAFFH8IAAILAAMJCRjXJgDvAANoDAAAAwAdAGkMAAACAD0A6gwAAAMAXQALAAMJCRjXJgDvAANoDAAAAwAdAGkMAAACAD0A6gwAAAMAXQAuAAQKfzoAAgsACQm9F8cWAD8CAAsACQm9F8cWAD8CAAAA.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgUJFAAHADMRAA==.Rizy:BAABLgAECn8ZAAIFAAkJkg4CQAC9AQloDAAABAAsAGkMAAAEACcAawwAAAQAHwBqDAAAAwArAGwMAAACABoAbQwAAAEAJQDqDAAABAArAG4MAAACACkAbwwAAAEAIwAFAAkJkg4CQAC9AQloDAAABAAsAGkMAAAEACcAawwAAAQAHwBqDAAAAwArAGwMAAACABoAbQwAAAEAJQDqDAAABAArAG4MAAACACkAbwwAAAEAIwAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAACLgAFFH8JAAIEAAMJhhclOwDtAANoDAAABABAAGkMAAACADMA6gwAAAMAQAAEAAMJhhclOwDtAANoDAAABABAAGkMAAACADMA6gwAAAMAQAAuAAQKf0cAAgQACQnGIFUGAPUCAAQACQnGIFUGAPUCAAAA.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiFnNQDDAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwACAAYJPiFnNQDDAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAFFAMJCgAIAMQhAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8qAAIFAAgJCRziJwAbAghoDAAACABPAGkMAAAHAFkAawwAAAcAVQBqDAAABQBYAGwMAAAFADkAbQwAAAEAJgDqDAAABgBGAG4MAAADAFEABQAICQkc4icAGwIIaAwAAAgATwBpDAAABwBZAGsMAAAHAFUAagwAAAUAWABsDAAABQA5AG0MAAABACYA6gwAAAYARgBuDAAAAwBRAAAA.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8aAAIeAAcJpw11FwAPAQdoDAAABAAfAGkMAAAFADoAawwAAAYAJABqDAAAAgAQAOoMAAAGACcAbgwAAAIAIgBvDAAAAQAJAB4ABwmnDXUXAA8BB2gMAAAEAB8AaQwAAAUAOgBrDAAABgAkAGoMAAACABAA6gwAAAYAJwBuDAAAAgAiAG8MAAABAAkAAAA=.',
Sl='Slashology:BAAALgAECgYJBwAAAA==.',
Sm='Smallpally:BAAALgAECgQJDQAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8eAAIHAAcJSBdPUgCIAQdoDAAABQBDAGkMAAAFAEUAawwAAAUANwBqDAAABABFAGwMAAAEAEAA6gwAAAYAMgBuDAAAAQAxAAcABwlIF09SAIgBB2gMAAAFAEMAaQwAAAUARQBrDAAABQA3AGoMAAAEAEUAbAwAAAQAQADqDAAABgAyAG4MAAABADEAAAA=.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA/nYACnAQhoDAAABAA9AGkMAAAEACcAawwAAAUAKABqDAAABABLAGwMAAADAEEAbQwAAAIAGwDqDAAABAAjAG4MAAABAAQAAgAICUgP52AApwEIaAwAAAQAPQBpDAAABAAnAGsMAAAFACgAagwAAAQASwBsDAAAAwBBAG0MAAACABsA6gwAAAQAIwBuDAAAAQAEAAAA.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAABLgAECn8WAAMHAAcJMheNWQB2AQdoDAAABABMAGkMAAADAEEAawwAAAMAUgBqDAAABABRAGwMAAACACAA6gwAAAUATwBuDAAAAQATAAcABglMGY1ZAHYBBmgMAAABAEwAaQwAAAEAQQBrDAAAAQBSAGoMAAABAFEA6gwAAAIATwBuDAAAAQATAB4ABgnxCu4fAL0ABmgMAAADABgAaQwAAAIAEgBrDAAAAgAIAGoMAAADABcAbAwAAAIAIADqDAAAAwA4AAEuAAUUAwkGABQASh4A.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIJAAgJHBvBAADdAghoDAAAAwBjAGkMAAAFAGEAawwAAAUAWwBqDAAABABFAGwMAAABAB8AbQwAAAEAIQDqDAAABQBjAG4MAAABACAACQAICRwbwQAA3QIIaAwAAAMAYwBpDAAABQBhAGsMAAAFAFsAagwAAAQARQBsDAAAAQAfAG0MAAABACEA6gwAAAUAYwBuDAAAAQAgAC4ABAp/JgACCQAJCeskYwIA2AMACQAJCeskYwIA2AMAAAA=.Touchi:BAAALgAECgMJBAABLgAECggJHQAZAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8dAAIZAAgJchprBwAEAghoDAAABgBeAGkMAAAEAEYAawwAAAQARwBqDAAAAwBSAGwMAAACADwAbQwAAAIAKwDqDAAABABEAG4MAAAEAEEAGQAICXIaawcABAIIaAwAAAYAXgBpDAAABABGAGsMAAAEAEcAagwAAAMAUgBsDAAAAgA8AG0MAAACACsA6gwAAAQARABuDAAABABBAAAA.Turbid:BAABLgAECn8oAAIEAAkJghNRLQDJAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAEAAkJghNRLQDJAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIHAAkJrRceJAAtAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAHAAkJrRceJAAtAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgYJCgAAAA==.',
Yo='Yogurt:BAAALgAECgYJCQABLgAECgkJLAAHALwWAA==.',
Yu='Yusuke:BAABLgAECn8WAAMhAAcJfhHHHwBqAQdoDAAABABEAGkMAAAEACoAawwAAAQASgBqDAAAAwAXAGwMAAADABoA6gwAAAMAJABuDAAAAQATACEABwl+EccfAGoBB2gMAAACAEQAaQwAAAIAKgBrDAAAAgBKAGoMAAACABcAbAwAAAIAGgDqDAAAAgAkAG4MAAABABMADgAGCT0JckAA4AAGaAwAAAIAHQBpDAAAAgAnAGsMAAACABkAagwAAAEABQBsDAAAAQANAOoMAAABABsAAS4ABAoICRQADACqCwA=.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAAALgAECgcJEQAAAA==.',
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

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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Paladin-Protection','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='daily',zone=46,date='2026-05-12',data={Ad='Adelyne:BAAALgAECgMJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuANVfwDZAAdoDAAABAAJAGkMAAAEABAAawwAAAQACQBqDAAABAAPAGwMAAAEAAcAbQwAAAIABgDqDAAAAwAGAAIABwmsA1V/ANkAB2gMAAAEAAkAaQwAAAQAEABrDAAAAwAIAGoMAAAEAA8AbAwAAAQABwBtDAAAAgAGAOoMAAADAAYAAwABCaoDRx8AIwABawwAAAEACQAAAA==.',
Ag='Agaze:BAACLgAFFH8QAAIEAAYJGCB8CgCGAQZoDAAAAwBeAGkMAAACAFIAawwAAAMAWwBqDAAAAwBIAGwMAAACAD4A6gwAAAMATwAEAAYJGCB8CgCGAQZoDAAAAwBeAGkMAAACAFIAawwAAAMAWwBqDAAAAwBIAGwMAAACAD4A6gwAAAMATwAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJBwAAAA==.',
Ap='Applejuuice:BAAALgAFFAMJAwABLgAECggJFwAFAMcSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8XAAIGAAcJXBNmTAB3AQdoDAAABgBJAGkMAAAEACIAawwAAAMAQgBqDAAAAwA3AGwMAAADACwAbQwAAAEAJwDqDAAAAwAnAAYABwlcE2ZMAHcBB2gMAAAGAEkAaQwAAAQAIgBrDAAAAwBCAGoMAAADADcAbAwAAAMALABtDAAAAQAnAOoMAAADACcAAAA=.Arma:BAABLgAECn8cAAIHAAgJjiNGBQAwAwhoDAAABABhAGkMAAAEAGEAawwAAAQAWwBqDAAAAwBgAGwMAAADAFsAbQwAAAIAUADqDAAABQBeAG4MAAADAFUABwAICY4jRgUAMAMIaAwAAAQAYQBpDAAABABhAGsMAAAEAFsAagwAAAMAYABsDAAAAwBbAG0MAAACAFAA6gwAAAUAXgBuDAAAAwBVAAAA.Armadro:BAABLgAFFH8IAAIIAAQJ6BbVIABxAQRoDAAAAgAiAGkMAAACADgAawwAAAIALADqDAAAAgBjAAgABAnoFtUgAHEBBGgMAAACACIAaQwAAAIAOABrDAAAAgAsAOoMAAACAGMAAAA=.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8WAAMJAAYJfR4WBgB3AQZoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAGwMAAABAD4A6gwAAAUAVgAJAAUJBiAWBgB3AQVoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAOoMAAAFAFYACgABCb8CHEgAQgABbAwAAAEABwAuAAQKfyIAAgkACAlqJXoEAFQDAAkACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAAALgAECggJEAAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgIJAgABLgAECggJKQAGAHoVAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8VAAILAAgJHQyoHABsAQhoDAAAAwApAGkMAAAEABMAawwAAAMAHABqDAAAAgASAGwMAAACABgAbQwAAAEAGADqDAAABAAtAG4MAAACACEACwAICR0MqBwAbAEIaAwAAAMAKQBpDAAABAATAGsMAAADABwAagwAAAIAEgBsDAAAAgAYAG0MAAABABgA6gwAAAQALQBuDAAAAgAhAAAA.Bubbly:BAABLgAECn8pAAIGAAgJehV3PwCcAQhoDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAIAIwDqDAAABgBAAG4MAAACAB0ABgAICXoVdz8AnAEIaAwAAAcANgBpDAAABwBKAGsMAAAGAEUAagwAAAUAPwBsDAAABgA4AG0MAAACACMA6gwAAAYAQABuDAAAAgAdAAAA.Butes:BAAALgADCgYJBgAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAABLgAECn9GAAMHAAkJGCQHAQBRAwloDAAACgBjAGkMAAAKAGEAawwAAAoAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACwBgAG4MAAAFAFoAbwwAAAIASgAHAAkJGCQHAQBRAwloDAAACgBjAGkMAAAKAGEAawwAAAkAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACQBgAG4MAAAFAFoAbwwAAAIASgAMAAIJxAvdXgBSAAJrDAAAAQAUAOoMAAACACcAAAA=.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgADCgMJAwAAAA==.Chulobulo:BAABLgAECn8WAAINAAgJFBTUCwDxAQhoDAAABQAsAGkMAAAEAD4AawwAAAMAKABqDAAAAwAaAGwMAAACAD8A6gwAAAMALwBuDAAAAQBLAG8MAAABABoADQAICRQU1AsA8QEIaAwAAAUALABpDAAABAA+AGsMAAADACgAagwAAAMAGgBsDAAAAgA/AOoMAAADAC8AbgwAAAEASwBvDAAAAQAaAAAA.Chulosdck:BAAALgAECgUJCQABLgAECggJFgANABQUAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAFAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8jAAIBAAkJKgzBEgDJAQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQABAAkJKgzBEgDJAQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQAAAA==.Cursed:BAABLgAECn8tAAMDAAkJhCCXAADUAgloDAAABgBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABgBYAG4MAAAEAFUAbwwAAAIAVAADAAkJhCCXAADUAgloDAAABQBfAGkMAAAGAFYAawwAAAUAXABqDAAABgBcAGwMAAAGAFUAbQwAAAQALQDqDAAABQBYAG4MAAAEAFUAbwwAAAIAVAACAAIJlwvJtABrAAJoDAAAAQASAOoMAAABACkAAAA=.',
Da='Dabz:BAAALgAECgcJEQAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMKAAkJ3yNUAQCCAwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAAEAEkAbwwAAAEAUQAKAAkJ3yNUAQCCAwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAADAEkAbwwAAAEAUQAJAAEJbBoJYQBMAAFuDAAAAQBDAAAA.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8LAAIEAAUJPgpELwAJAQVoDAAAAwAbAGkMAAADACoAawwAAAIABwBqDAAAAQAnAOoMAAACABsABAAFCT4KRC8ACQEFaAwAAAMAGwBpDAAAAwAqAGsMAAACAAcAagwAAAEAJwDqDAAAAgAbAC4ABAp/KAACBAAJCYsVJBgAEQIABAAJCYsVJBgAEQIAAAA=.Dezric:BAAALgADCgYJDAABLgAECgYJDQAOAAAAAA==.',
Do='Dotomic:BAAALgAECgQJBQABLgAFFAcJFAAPAEIeAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAOAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAAOAAAAAA==.',
['Dä']='Dämonjäger:BAAALgADCggJCAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8XAAIQAAgJFgfLDQD5AAhoDAAABAAVAGkMAAAEABYAawwAAAQADgBqDAAAAwAKAGwMAAACAAQAbQwAAAEABgDqDAAABAAoAG4MAAABABAAEAAICRYHyw0A+QAIaAwAAAQAFQBpDAAABAAWAGsMAAAEAA4AagwAAAMACgBsDAAAAgAEAG0MAAABAAYA6gwAAAQAKABuDAAAAQAQAAAA.',
Ei='Eisenhørn:BAAALgADCgYJBgAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8XAAIGAAcJeQa7eQAQAQdoDAAABQANAGkMAAAFABQAawwAAAQAIQBqDAAAAgAIAGwMAAACAAcA6gwAAAQAEQBuDAAAAQAHAAYABwl5Brt5ABABB2gMAAAFAA0AaQwAAAUAFABrDAAABAAhAGoMAAACAAgAbAwAAAIABwDqDAAABAARAG4MAAABAAcAAAA=.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgQJBAABLgAFFAEJAQAOAAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAYJFQARAGUbAA==.',
Fr='Fragga:BAABLgAECn8VAAISAAYJDxJtLwAfAQZoDAAAAwAkAGkMAAAFADUAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAQAMQASAAYJDxJtLwAfAQZoDAAAAwAkAGkMAAAFADUAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAQAMQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn86AAITAAkJGRrPEwBGAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgATAAkJGRrPEwBGAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAAUAKgiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgQJBwAAAA==.Grizzly:BAAALgADCgcJCgABLgAECgUJCwAOAAAAAA==.Groovexgroov:BAAALgAECgcJBwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Holynight:BAAALgADCgEJAQABLgAECgUJCwAOAAAAAA==.Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMJAAYJownMSgAcAQZoDAAABAAaAGkMAAAEAB8AawwAAAQAHwBqDAAAAwAcAGwMAAACAAsA6gwAAAMAFQAJAAYJownMSgAcAQZoDAAAAgAaAGkMAAACAB8AawwAAAIAHwBqDAAAAgAcAGwMAAABAAsA6gwAAAEAFQAVAAYJ3gLVHgDiAAZoDAAAAgAEAGkMAAACAAsAawwAAAIADwBqDAAAAQAEAGwMAAABAAEA6gwAAAIABAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8tAAIBAAgJRxnUCABoAghoDAAABwBMAGkMAAAHAEoAawwAAAcAPwBqDAAABQBTAGwMAAAEAB8AbQwAAAMAJwDqDAAACQBXAG4MAAADAD4AAQAICUcZ1AgAaAIIaAwAAAcATABpDAAABwBKAGsMAAAHAD8AagwAAAUAUwBsDAAABAAfAG0MAAADACcA6gwAAAkAVwBuDAAAAwA+AAAA.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8VAAIIAAkJRxsNFQCGAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAIAAkJRxsNFQCGAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIWAAgJbRFPIQCQAQhoDAAAAwAzAGkMAAADADkAawwAAAQASwBqDAAAAgAwAGwMAAABABEAbQwAAAEAEQDqDAAABgA+AG4MAAABABoAFgAICW0RTyEAkAEIaAwAAAMAMwBpDAAAAwA5AGsMAAAEAEsAagwAAAIAMABsDAAAAQARAG0MAAABABEA6gwAAAYAPgBuDAAAAQAaAAAA.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAINAAgJuiAkEQCYAghoDAAABQBXAGkMAAAEAGEAawwAAAQAVgBqDAAAAgAlAGwMAAACAEsAbQwAAAMASwDqDAAABQBSAG4MAAABAFIADQAICbogJBEAmAIIaAwAAAUAVwBpDAAABABhAGsMAAAEAFYAagwAAAIAJQBsDAAAAgBLAG0MAAADAEsA6gwAAAUAUgBuDAAAAQBSAAAA.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8GAAIVAAIJDSVqBgDcAAJoDAAABABhAOoMAAACAFsAFQACCQ0lagYA3AACaAwAAAQAYQDqDAAAAgBbAC4ABAp/GAACFQAJCRQdwQMA7gIAFQAJCRQdwQMA7gIAAAA=.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAABLgAECn9CAAIQAAkJnBUdBAANAgloDAAACgBEAGkMAAAJADcAawwAAAkANwBqDAAACQBGAGwMAAAIAEsAbQwAAAMARADqDAAADAA9AG4MAAAEACAAbwwAAAIAGQAQAAkJnBUdBAANAgloDAAACgBEAGkMAAAJADcAawwAAAkANwBqDAAACQBGAGwMAAAIAEsAbQwAAAMARADqDAAADAA9AG4MAAAEACAAbwwAAAIAGQAAAA==.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8WAAIXAAYJeAWHGADIAAZoDAAABQAIAGkMAAAFABoAawwAAAQABwBqDAAAAgARAGwMAAACAA4A6gwAAAQADQAXAAYJeAWHGADIAAZoDAAABQAIAGkMAAAFABoAawwAAAQABwBqDAAAAgARAGwMAAACAA4A6gwAAAQADQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIYAAkJ6RcbAgA6AgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAYAAkJ6RcbAgA6AgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAAAA==.',
Kl='Kløey:BAAALgAECgYJEwAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAIAEEeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAABLgAECn83AAMBAAkJWQ0DIgCEAQloDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAACAAiAGwMAAAIADgAbQwAAAUADQDqDAAACQAWAG4MAAAFABEAbwwAAAIAHwABAAgJ/AoDIgCEAQhoDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAABwATAGwMAAAHACoAbQwAAAIABADqDAAACQAWAG4MAAACAAQAGQAFCQsMoS8A7AAFagwAAAEAIgBsDAAAAQA4AG0MAAADAA0AbgwAAAMAEQBvDAAAAgAfAAAA.Lussypipz:BAAALgAECgYJDAAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8VAAMIAAgJ4xBYRgCnAQhoDAAAAwAuAGkMAAACAD8AawwAAAIALwBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAABAAqAG4MAAACABwACAAICeMQWEYApwEIaAwAAAIALgBpDAAAAgA/AGsMAAACAC8AagwAAAMAHQBsDAAAAwAmAG0MAAACACMA6gwAAAQAKgBuDAAAAgAcABoAAQkkD+kNAD8AAWgMAAABACYAAAA=.',
Me='Meheret:BAABLgAECn8yAAIIAAkJ1wTjXwBmAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAIAAkJ1wTjXwBmAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIIAAkJQR6GDwCzAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAIAAkJQR6GDwCzAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAINAAgJjRoPCwD9AQhoDAAAAwBBAGkMAAADAD8AawwAAAMATgBqDAAAAwA9AGwMAAADAEwAbQwAAAIAQwDqDAAAAwBJAG4MAAADADIADQAICY0aDwsA/QEIaAwAAAMAQQBpDAAAAwA/AGsMAAADAE4AagwAAAMAPQBsDAAAAwBMAG0MAAACAEMA6gwAAAMASQBuDAAAAwAyAAAA.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAIAEEeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgMJBAABLgAFFAMJBQASAOMYAA==.Mythx:BAACLgAFFH8FAAISAAMJ4xhmGAADAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwASAAMJ4xhmGAADAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwAuAAQKfyoAAhIACAmsIj0EANACABIACAmsIj0EANACAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8sAAIWAAgJohgoFQD5AQhoDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABwA6AG4MAAACABsAFgAICaIYKBUA+QEIaAwAAAcAOQBpDAAABwBPAGsMAAAHAEoAagwAAAUANABsDAAABQBPAG0MAAAEAEsA6gwAAAcAOgBuDAAAAgAbAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgZoDAAABQBaAGkMAAAEAFEAawwAAAQASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAADAAYJph/GBQAKAgZoDAAAAwBaAGkMAAADAFEAawwAAAMASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAACAAMJ3wqC4wCTAANoDAAAAQAdAGkMAAABABwAawwAAAEAGQAbAAEJ/AgReAAsAAFoDAAAAQAXAAAA.Netharec:BAAALgADCgEJAQAAAA==.Nevai:BAABLgAECn8UAAIWAAgJxxBVGgDKAQhoDAAAAwA5AGkMAAADAFAAawwAAAMANgBqDAAAAwAjAGwMAAACAAcAbQwAAAEAIQDqDAAABAA9AG4MAAABAA0AFgAICccQVRoAygEIaAwAAAMAOQBpDAAAAwBQAGsMAAADADYAagwAAAMAIwBsDAAAAgAHAG0MAAABACEA6gwAAAQAPQBuDAAAAQANAAAA.',
Ni='Nielas:BAAALgAECgcJEwAAAA==.Nihilus:BAACLgAFFH8OAAIcAAUJVheTCACMAQVoDAAAAwBNAGkMAAACACcAawwAAAMALwBqDAAAAQAVAOoMAAAFAEoAHAAFCVYXkwgAjAEFaAwAAAMATQBpDAAAAgAnAGsMAAADAC8AagwAAAEAFQDqDAAABQBKAC4ABAp/FQACHAAHCRYkuS8AeQIAHAAHCRYkuS8AeQIAAAA=.Nilari:BAABLgAECn8UAAIdAAYJIQltHgC1AAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAdAAYJIQltHgC1AAZoDAAABAAWAGkMAAADACsAawwAAAMAGgBqDAAAAwAQAGwMAAACAAkA6gwAAAUADgAAAA==.Nine:BAAALgADCgYJBgABLgAECgkJRgAHABgkAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAIUAAgJqCILAQC3AghoDAAABABTAGkMAAAFAFkAawwAAAUAUQBqDAAABABXAGwMAAADAGEAbQwAAAIAXwDqDAAABABZAG4MAAABAFQAFAAICagiCwEAtwIIaAwAAAQAUwBpDAAABQBZAGsMAAAFAFEAagwAAAQAVwBsDAAAAwBhAG0MAAACAF8A6gwAAAQAWQBuDAAAAQBUAAAA.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAGAK0XAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJDQABADIaAA==.Owls:BAACLgAFFH8NAAIBAAQJMhrWEgBEAQRoDAAABABNAGkMAAAEAEMAawwAAAIAIgDqDAAAAwBYAAEABAkyGtYSAEQBBGgMAAAEAE0AaQwAAAQAQwBrDAAAAgAiAOoMAAADAFgALgAECn8uAAMZAAkJFiP3CgCfAgAZAAcJGyT3CgCfAgABAAkJsh+vCgCNAgABLgAFFAQJDQABADIaAA==.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMeAAgJ3w1WBgCaAQhoDAAABAA0AGkMAAAEAD8AawwAAAQAJABqDAAABAA7AGwMAAAEACMAbQwAAAIAEADqDAAABAAcAG4MAAACAA0AHgAICd8NVgYAmgEIaAwAAAMANABpDAAABAA/AGsMAAADACQAagwAAAIAOwBsDAAAAgAjAG0MAAACABAA6gwAAAMAHABuDAAAAQANAA0ABglQAZ5LAM0ABmgMAAABAAMAawwAAAEAAgBqDAAAAgAEAGwMAAACAAcA6gwAAAEAAgBuDAAAAQABAAAA.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8FAAIcAAMJ4xrGTQAEAQNoDAAAAgBSAGkMAAACACkA6gwAAAEAUgAcAAMJ4xrGTQAEAQNoDAAAAgBSAGkMAAACACkA6gwAAAEAUgAuAAQKfywAAxwACQlAJZ4EAIoDABwACQlAJZ4EAIoDAB8AAQk5IQYVAGEAAAAA.Proved:BAABLgAECn87AAIZAAgJlh+HBgCmAghoDAAACwBjAGkMAAAJAEUAawwAAAgAXQBqDAAACQBaAGwMAAAIAFcAbQwAAAMANwDqDAAACABdAG4MAAADADoAGQAICZYfhwYApgIIaAwAAAsAYwBpDAAACQBFAGsMAAAIAF0AagwAAAkAWgBsDAAACABXAG0MAAADADcA6gwAAAgAXQBuDAAAAwA6AAAA.',
Ps='Psillycybin:BAAALgAECgcJCQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ranessandi:BAAALgADCgUJBQAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAABLgAECn8sAAIKAAkJChOgHwDQAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAKAAkJChOgHwDQAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAAAA==.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAAAAA==.Rizy:BAABLgAECn8WAAIcAAgJ8g3PQgCJAQhoDAAABAAsAGkMAAAEACcAawwAAAQAHwBqDAAAAwArAGwMAAACABoAbQwAAAEAJQDqDAAAAwArAG4MAAABABwAHAAICfINz0IAiQEIaAwAAAQALABpDAAABAAnAGsMAAAEAB8AagwAAAMAKwBsDAAAAgAaAG0MAAABACUA6gwAAAMAKwBuDAAAAQAcAAAA.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAABLgAECn85AAIEAAkJbSBiBAAAAwloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAEAAkJbSBiBAAAAwloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAAAA==.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiEuJQDlAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwACAAYJPiEuJQDlAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJCAABLgAECgkJRgAHABgkAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8kAAIcAAgJzxvgGQBGAghoDAAABwBPAGkMAAAGAFkAawwAAAYAUwBqDAAABABNAGwMAAAEADgAbQwAAAEAJgDqDAAABgBGAG4MAAACAFAAHAAICc8b4BkARgIIaAwAAAcATwBpDAAABgBZAGsMAAAGAFMAagwAAAQATQBsDAAABAA4AG0MAAABACYA6gwAAAYARgBuDAAAAgBQAAAA.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgYJDwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8UAAIdAAcJvQw+FwD2AAdoDAAAAwAWAGkMAAAEADoAawwAAAUAHwBqDAAAAgAQAOoMAAAEACcAbgwAAAEAIgBvDAAAAQAJAB0ABwm9DD4XAPYAB2gMAAADABYAaQwAAAQAOgBrDAAABQAfAGoMAAACABAA6gwAAAQAJwBuDAAAAQAiAG8MAAABAAkAAAA=.',
Sl='Slashology:BAAALgAECgYJBwAAAA==.',
Sm='Smallpally:BAAALgAECgQJDAAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8YAAIGAAcJpBa0QACYAQdoDAAABAA6AGkMAAAEAEUAawwAAAQANwBqDAAAAwBFAGwMAAADAEAA6gwAAAUAMgBuDAAAAQAxAAYABwmkFrRAAJgBB2gMAAAEADoAaQwAAAQARQBrDAAABAA3AGoMAAADAEUAbAwAAAMAQADqDAAABQAyAG4MAAABADEAAAA=.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA9ARQBoAQhoDAAABAA9AGkMAAAEACcAawwAAAUAKABqDAAABABLAGwMAAADAEEAbQwAAAIAGwDqDAAABAAjAG4MAAABAAQAAgAICUgPQEUAaAEIaAwAAAQAPQBpDAAABAAnAGsMAAAFACgAagwAAAQASwBsDAAAAwBBAG0MAAACABsA6gwAAAQAIwBuDAAAAQAEAAAA.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAQAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAABLgAECn8VAAMGAAcJHhcpQgCUAQdoDAAABABMAGkMAAADAEEAawwAAAMAUgBqDAAABABRAGwMAAACACAA6gwAAAQATgBuDAAAAQATAAYABgk0GSlCAJQBBmgMAAABAEwAaQwAAAEAQQBrDAAAAQBSAGoMAAABAFEA6gwAAAEATgBuDAAAAQATAB0ABgnxCs0bAMoABmgMAAADABgAaQwAAAIAEgBrDAAAAgAIAGoMAAADABcAbAwAAAIAIADqDAAAAwA4AAEuAAUUAwkFABIA4xgA.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIIAAgJHBvBAADdAghoDAAAAwBjAGkMAAAFAGEAawwAAAUAWwBqDAAABABFAGwMAAABAB8AbQwAAAEAIQDqDAAABQBjAG4MAAABACAACAAICRwbwQAA3QIIaAwAAAMAYwBpDAAABQBhAGsMAAAFAFsAagwAAAQARQBsDAAAAQAfAG0MAAABACEA6gwAAAUAYwBuDAAAAQAgAC4ABAp/JgACCAAJCeskYwIA2AMACAAJCeskYwIA2AMAAAA=.Touchi:BAAALgAECgEJAgABLgAECggJHAAXAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8cAAIXAAgJchpWBQAeAghoDAAABgBeAGkMAAAEAEYAawwAAAQARwBqDAAAAwBSAGwMAAACADwAbQwAAAIAKwDqDAAABABEAG4MAAADAEEAFwAICXIaVgUAHgIIaAwAAAYAXgBpDAAABABGAGsMAAAEAEcAagwAAAMAUgBsDAAAAgA8AG0MAAACACsA6gwAAAQARABuDAAAAwBBAAAA.Turbid:BAABLgAECn8oAAIEAAkJghMHHQDvAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAEAAkJghMHHQDvAQloDAAABwBKAGkMAAAGADsAawwAAAYAOQBqDAAABQAmAGwMAAAFADQAbQwAAAMAKgDqDAAABQAkAG4MAAACADIAbwwAAAEAGgAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIGAAkJrRdrFwBVAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAGAAkJrRdrFwBVAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgUJCQAAAA==.',
Yo='Yogurt:BAAALgAECgYJCQABLgAECggJKQAGAHoVAA==.',
Yu='Yusuke:BAABLgAECn8WAAMgAAcJfhG7GACAAQdoDAAABABEAGkMAAAEACoAawwAAAQASgBqDAAAAwAXAGwMAAADABoA6gwAAAMAJABuDAAAAQATACAABwl+EbsYAIABB2gMAAACAEQAaQwAAAIAKgBrDAAAAgBKAGoMAAACABcAbAwAAAIAGgDqDAAAAgAkAG4MAAABABMADAAGCT0JckAA4AAGaAwAAAIAHQBpDAAAAgAnAGsMAAACABkAagwAAAEABQBsDAAAAQANAOoMAAABABsAAS4ABAoICRAADgAAAAA=.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zuesulty:BAAALgADCgYJBgAAAA==.Zunden:BAAALgAECgYJCwAAAA==.',
['Éz']='Ézon:BAAALgADCggJCAAAAA==.',
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

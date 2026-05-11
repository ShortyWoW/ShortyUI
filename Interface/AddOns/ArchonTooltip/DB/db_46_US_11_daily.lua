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

local lookup = {'Priest-Discipline','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Rogue-Assassination','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='daily',zone=46,date='2026-05-10',data={Ad='Adelyne:BAAALgAECgMJAwABLgAFFAUJDgABAG0SAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMcewDYAAdoDAAABAAJAGkMAAAEABAAawwAAAQACQBqDAAABAAPAGwMAAAEAAcAbQwAAAIABgDqDAAAAwAGAAIABwmsAxx7ANgAB2gMAAAEAAkAaQwAAAQAEABrDAAAAwAIAGoMAAAEAA8AbAwAAAQABwBtDAAAAgAGAOoMAAADAAYAAwABCaoD5BwAJAABawwAAAEACQAAAA==.',
Ag='Agaze:BAACLgAFFH8QAAIEAAYJGCB4CgCGAQZoDAAAAwBeAGkMAAACAFIAawwAAAMAWwBqDAAAAwBIAGwMAAACAD4A6gwAAAMATwAEAAYJGCB4CgCGAQZoDAAAAwBeAGkMAAACAFIAawwAAAMAWwBqDAAAAwBIAGwMAAACAD4A6gwAAAMATwAuAAQKfxYAAgQACAkTIgAZAL8CAAQACAkTIgAZAL8CAAAA.',
Ai='Aiedel:BAAALgAECgUJCQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJBwAAAA==.',
Ap='Applejuuice:BAAALgAFFAMJAwABLgAECggJFwAFAMcSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8XAAIGAAcJXBMuSgBxAQdoDAAABgBJAGkMAAAEACIAawwAAAMAQgBqDAAAAwA3AGwMAAADACwAbQwAAAEAJwDqDAAAAwAnAAYABwlcEy5KAHEBB2gMAAAGAEkAaQwAAAQAIgBrDAAAAwBCAGoMAAADADcAbAwAAAMALABtDAAAAQAnAOoMAAADACcAAAA=.Arma:BAABLgAECn8cAAIHAAgJjiNFBQAwAwhoDAAABABhAGkMAAAEAGEAawwAAAQAWwBqDAAAAwBgAGwMAAADAFsAbQwAAAIAUADqDAAABQBeAG4MAAADAFUABwAICY4jRQUAMAMIaAwAAAQAYQBpDAAABABhAGsMAAAEAFsAagwAAAMAYABsDAAAAwBbAG0MAAACAFAA6gwAAAUAXgBuDAAAAwBVAAAA.Armadro:BAABLgAFFH8IAAIIAAQJ6BYAHgBzAQRoDAAAAgAiAGkMAAACADgAawwAAAIALADqDAAAAgBjAAgABAnoFgAeAHMBBGgMAAACACIAaQwAAAIAOABrDAAAAgAsAOoMAAACAGMAAAA=.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8WAAMJAAYJfR4xBgB4AQZoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAGwMAAABAD4A6gwAAAUAVgAJAAUJBiAxBgB4AQVoDAAABgBEAGkMAAAFAFoAawwAAAQAUgBqDAAAAQAXAOoMAAAFAFYACgABCb8Cy0MAQgABbAwAAAEABwAuAAQKfyIAAgkACAlqJXoEAFQDAAkACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAAALgAECggJEAAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgEJAQABLgAECggJKQAGAHoVAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8VAAILAAgJHQx0GwBsAQhoDAAAAwApAGkMAAAEABMAawwAAAMAHABqDAAAAgASAGwMAAACABgAbQwAAAEAGADqDAAABAAtAG4MAAACACEACwAICR0MdBsAbAEIaAwAAAMAKQBpDAAABAATAGsMAAADABwAagwAAAIAEgBsDAAAAgAYAG0MAAABABgA6gwAAAQALQBuDAAAAgAhAAAA.Bubbly:BAABLgAECn8pAAIGAAgJehVOPQCYAQhoDAAABwA2AGkMAAAHAEoAawwAAAYARQBqDAAABQA/AGwMAAAGADgAbQwAAAIAIwDqDAAABgBAAG4MAAACAB0ABgAICXoVTj0AmAEIaAwAAAcANgBpDAAABwBKAGsMAAAGAEUAagwAAAUAPwBsDAAABgA4AG0MAAACACMA6gwAAAYAQABuDAAAAgAdAAAA.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAABLgAECn9GAAMHAAkJGCTpAABTAwloDAAACgBjAGkMAAAKAGEAawwAAAoAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACwBgAG4MAAAFAFoAbwwAAAIASgAHAAkJGCTpAABTAwloDAAACgBjAGkMAAAKAGEAawwAAAkAXwBqDAAACABfAGwMAAAIAGAAbQwAAAYAWADqDAAACQBgAG4MAAAFAFoAbwwAAAIASgAMAAIJxAveXgBSAAJrDAAAAQAUAOoMAAACACcAAAA=.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgADCgMJAwAAAA==.Chulobulo:BAABLgAECn8WAAINAAgJFBQaCwD0AQhoDAAABQAsAGkMAAAEAD4AawwAAAMAKABqDAAAAwAaAGwMAAACAD8A6gwAAAMALwBuDAAAAQBLAG8MAAABABoADQAICRQUGgsA9AEIaAwAAAUALABpDAAABAA+AGsMAAADACgAagwAAAMAGgBsDAAAAgA/AOoMAAADAC8AbgwAAAEASwBvDAAAAQAaAAAA.Chulosdck:BAAALgAECgUJCQABLgAECggJFgANABQUAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAFAMcSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8jAAIBAAkJKgzeEQDJAQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQABAAkJKgzeEQDJAQloDAAABgAmAGkMAAAGADIAawwAAAYAHQBqDAAABAAfAGwMAAAEAEAAbQwAAAMADgDqDAAAAwAhAG4MAAACAAgAbwwAAAEACQAAAA==.Cursed:BAABLgAECn8kAAMDAAkJth0SAgCtAgloDAAABQBfAGkMAAAFAFYAawwAAAQAXABqDAAABQBcAGwMAAAFADgAbQwAAAMALQDqDAAABQBXAG4MAAADAEcAbwwAAAEARwADAAkJth0SAgCtAgloDAAABABfAGkMAAAFAFYAawwAAAQAXABqDAAABQBcAGwMAAAFADgAbQwAAAMALQDqDAAABABXAG4MAAADAEcAbwwAAAEARwACAAIJlwtFsABpAAJoDAAAAQASAOoMAAABACkAAAA=.',
Da='Dabz:BAAALgAECgcJEQAAAA==.Daddyslaps:BAAALgAECgUJBQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMKAAkJ3yMuAQCDAwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAAEAEkAbwwAAAEAUQAKAAkJ3yMuAQCDAwloDAAACABjAGkMAAAIAGIAawwAAAcAYgBqDAAABwBhAGwMAAAHAGEAbQwAAAQAUgDqDAAABwBhAG4MAAADAEkAbwwAAAEAUQAJAAEJbBolXQBMAAFuDAAAAQBDAAAA.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8LAAIEAAUJPgqcLAAKAQVoDAAAAwAbAGkMAAADACoAawwAAAIABwBqDAAAAQAnAOoMAAACABsABAAFCT4KnCwACgEFaAwAAAMAGwBpDAAAAwAqAGsMAAACAAcAagwAAAEAJwDqDAAAAgAbAC4ABAp/KAACBAAJCYsVyxYADgIABAAJCYsVyxYADgIAAAA=.Dezric:BAAALgADCgYJDAABLgAECgYJDQAOAAAAAA==.',
Do='Dotomic:BAAALgAECgQJBQABLgAFFAcJFAAPAEIeAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAAOAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAAOAAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8XAAIQAAgJFgdKDQD5AAhoDAAABAAVAGkMAAAEABYAawwAAAQADgBqDAAAAwAKAGwMAAACAAQAbQwAAAEABgDqDAAABAAoAG4MAAABABAAEAAICRYHSg0A+QAIaAwAAAQAFQBpDAAABAAWAGsMAAAEAA4AagwAAAMACgBsDAAAAgAEAG0MAAABAAYA6gwAAAQAKABuDAAAAQAQAAAA.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8UAAIGAAcJZgVVewABAQdoDAAABAAEAGkMAAAEABQAawwAAAQAIQBqDAAAAgAIAGwMAAACAAcA6gwAAAMACQBuDAAAAQAHAAYABwlmBVV7AAEBB2gMAAAEAAQAaQwAAAQAFABrDAAABAAhAGoMAAACAAgAbAwAAAIABwDqDAAAAwAJAG4MAAABAAcAAAA=.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.Erõs:BAAALgAECgQJBAABLgAFFAEJAQAOAAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAUJFAARAGsfAA==.',
Fr='Fragga:BAABLgAECn8VAAISAAYJDxJaLQAhAQZoDAAAAwAkAGkMAAAFADUAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAQAMQASAAYJDxJaLQAhAQZoDAAAAwAkAGkMAAAFADUAawwAAAUANABqDAAAAgATAGwMAAACACcA6gwAAAQAMQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn86AAITAAkJGRosEgBHAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgATAAkJGRosEgBHAgloDAAABwBMAGkMAAAHAE4AawwAAAcAVgBqDAAACABNAGwMAAAIADsAbQwAAAUARADqDAAACQBLAG4MAAAFADMAbwwAAAIAJgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAAUAKgiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgMJBAAAAA==.Grizzly:BAAALgADCgUJBQABLgAECgUJCwAOAAAAAA==.Groovexgroov:BAAALgAECgcJBwAAAA==.',
He='Healrog:BAAALgAECgYJBgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMJAAYJownKSgAcAQZoDAAABAAaAGkMAAAEAB8AawwAAAQAHwBqDAAAAwAcAGwMAAACAAsA6gwAAAMAFQAJAAYJownKSgAcAQZoDAAAAgAaAGkMAAACAB8AawwAAAIAHwBqDAAAAgAcAGwMAAABAAsA6gwAAAEAFQAVAAYJ3gLVHgDiAAZoDAAAAgAEAGkMAAACAAsAawwAAAIADwBqDAAAAQAEAGwMAAABAAEA6gwAAAIABAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8tAAIBAAgJRxlMCABoAghoDAAABwBMAGkMAAAHAEoAawwAAAcAPwBqDAAABQBTAGwMAAAEAB8AbQwAAAMAJwDqDAAACQBXAG4MAAADAD4AAQAICUcZTAgAaAIIaAwAAAcATABpDAAABwBKAGsMAAAHAD8AagwAAAUAUwBsDAAABAAfAG0MAAADACcA6gwAAAkAVwBuDAAAAwA+AAAA.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8VAAIIAAkJRxuXEwCGAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAIAAkJRxuXEwCGAgloDAAAAwBSAGkMAAADAEsAawwAAAMAWgBqDAAAAgBXAGwMAAACAFkAbQwAAAEAIwDqDAAABABKAG4MAAACAFoAbwwAAAEAEwAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIWAAgJbRFfHwCYAQhoDAAAAwAzAGkMAAADADkAawwAAAQASwBqDAAAAgAwAGwMAAABABEAbQwAAAEAEQDqDAAABgA+AG4MAAABABoAFgAICW0RXx8AmAEIaAwAAAMAMwBpDAAAAwA5AGsMAAAEAEsAagwAAAIAMABsDAAAAQARAG0MAAABABEA6gwAAAYAPgBuDAAAAQAaAAAA.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAINAAgJuiAlEQCYAghoDAAABQBXAGkMAAAEAGEAawwAAAQAVgBqDAAAAgAlAGwMAAACAEsAbQwAAAMASwDqDAAABQBSAG4MAAABAFIADQAICbogJREAmAIIaAwAAAUAVwBpDAAABABhAGsMAAAEAFYAagwAAAIAJQBsDAAAAgBLAG0MAAADAEsA6gwAAAUAUgBuDAAAAQBSAAAA.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8GAAIVAAIJDSX7BQDdAAJoDAAABABhAOoMAAACAFsAFQACCQ0l+wUA3QACaAwAAAQAYQDqDAAAAgBbAC4ABAp/GAACFQAJCRQdwQMA7gIAFQAJCRQdwQMA7gIAAAA=.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAABLgAECn82AAIQAAkJnBX6AwAHAgloDAAACABEAGkMAAAHADcAawwAAAcANwBqDAAABwBGAGwMAAAGAEsAbQwAAAMARADqDAAACgA9AG4MAAAEACAAbwwAAAIAGQAQAAkJnBX6AwAHAgloDAAACABEAGkMAAAHADcAawwAAAcANwBqDAAABwBGAGwMAAAGAEsAbQwAAAMARADqDAAACgA9AG4MAAAEACAAbwwAAAIAGQAAAA==.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8WAAIXAAYJeAVZFwDIAAZoDAAABQAIAGkMAAAFABoAawwAAAQABwBqDAAAAgARAGwMAAACAA4A6gwAAAQADQAXAAYJeAVZFwDIAAZoDAAABQAIAGkMAAAFABoAawwAAAQABwBqDAAAAgARAGwMAAACAA4A6gwAAAQADQAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIYAAkJ6Rf3AQA8AgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAYAAkJ6Rf3AQA8AgloDAAABQBDAGkMAAAEAC4AawwAAAQAPABqDAAAAwBBAGwMAAAEAEkAbQwAAAIAQADqDAAABgA+AG4MAAACAEAAbwwAAAEAMQAAAA==.',
Kl='Kløey:BAAALgAECgYJEAAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAIAEEeAA==.',
Li='Lithini:BAAALgAECgQJCAAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAABLgAECn83AAMBAAkJWQ0CIgCEAQloDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAACAAiAGwMAAAIADgAbQwAAAUADQDqDAAACQAWAG4MAAAFABEAbwwAAAIAHwABAAgJ/AoCIgCEAQhoDAAABgA1AGkMAAAGABsAawwAAAYAMQBqDAAABwATAGwMAAAHACoAbQwAAAIABADqDAAACQAWAG4MAAACAAQAGQAFCQsMii0A7AAFagwAAAEAIgBsDAAAAQA4AG0MAAADAA0AbgwAAAMAEQBvDAAAAgAfAAAA.Lussypipz:BAAALgAECgYJDAAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8VAAMIAAgJ4xAWRACiAQhoDAAAAwAuAGkMAAACAD8AawwAAAIALwBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAABAAqAG4MAAACABwACAAICeMQFkQAogEIaAwAAAIALgBpDAAAAgA/AGsMAAACAC8AagwAAAMAHQBsDAAAAwAmAG0MAAACACMA6gwAAAQAKgBuDAAAAgAcABoAAQkkD28NAD8AAWgMAAABACYAAAA=.',
Me='Meheret:BAABLgAECn8yAAIIAAkJ1wSsXABhAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAIAAkJ1wSsXABhAQloDAAABQAKAGkMAAAFAA4AawwAAAUACQBqDAAABwAOAGwMAAAIABsAbQwAAAUADADqDAAACAALAG4MAAAFAAQAbwwAAAIACQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIIAAkJQR5sDgCyAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAIAAkJQR5sDgCyAgloDAAABgBXAGkMAAAFAF8AawwAAAUAWQBqDAAABABcAGwMAAAEAFcAbQwAAAIASQDqDAAABABcAG4MAAACACgAbwwAAAEANQAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAINAAgJjRoNCgAHAghoDAAAAwBBAGkMAAADAD8AawwAAAMATgBqDAAAAwA9AGwMAAADAEwAbQwAAAIAQwDqDAAAAwBJAG4MAAADADIADQAICY0aDQoABwIIaAwAAAMAQQBpDAAAAwA/AGsMAAADAE4AagwAAAMAPQBsDAAAAwBMAG0MAAACAEMA6gwAAAMASQBuDAAAAwAyAAAA.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAIAEEeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgEJAQABLgAFFAMJBQASAOMYAA==.Mythx:BAACLgAFFH8FAAISAAMJ4xjCFgAHAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwASAAMJ4xjCFgAHAQNoDAAAAgA7AGkMAAABAFwA6gwAAAIAJwAuAAQKfyoAAhIACAmsItUDANICABIACAmsItUDANICAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8rAAIWAAgJohjfEwD/AQhoDAAABwA5AGkMAAAHAE8AawwAAAcASgBqDAAABQA0AGwMAAAFAE8AbQwAAAQASwDqDAAABgA6AG4MAAACABsAFgAICaIY3xMA/wEIaAwAAAcAOQBpDAAABwBPAGsMAAAHAEoAagwAAAUANABsDAAABQBPAG0MAAAEAEsA6gwAAAYAOgBuDAAAAgAbAAAA.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/GBQAKAgZoDAAABQBaAGkMAAAEAFEAawwAAAQASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAADAAYJph/GBQAKAgZoDAAAAwBaAGkMAAADAFEAawwAAAMASgBqDAAAAgA7AGwMAAACAEgA6gwAAAQAVAACAAMJ3wqA4wCTAANoDAAAAQAdAGkMAAABABwAawwAAAEAGQAbAAEJ/AgOeAAsAAFoDAAAAQAXAAAA.Netharec:BAAALgADCgEJAQAAAA==.Nevai:BAABLgAECn8UAAIWAAgJxxCOGADSAQhoDAAAAwA5AGkMAAADAFAAawwAAAMANgBqDAAAAwAjAGwMAAACAAcAbQwAAAEAIQDqDAAABAA9AG4MAAABAA0AFgAICccQjhgA0gEIaAwAAAMAOQBpDAAAAwBQAGsMAAADADYAagwAAAMAIwBsDAAAAgAHAG0MAAABACEA6gwAAAQAPQBuDAAAAQANAAAA.',
Ni='Nielas:BAAALgAECgcJEwAAAA==.Nihilus:BAACLgAFFH8OAAIcAAUJVheSCACMAQVoDAAAAwBNAGkMAAACACcAawwAAAMALwBqDAAAAQAVAOoMAAAFAEoAHAAFCVYXkggAjAEFaAwAAAMATQBpDAAAAgAnAGsMAAADAC8AagwAAAEAFQDqDAAABQBKAC4ABAp/FQACHAAHCRYkti8AeQIAHAAHCRYkti8AeQIAAAA=.Nilari:BAAALgAECgUJCAAAAA==.Nine:BAAALgADCgYJBgABLgAECgkJRgAHABgkAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAIUAAgJqCLyAAC4AghoDAAABABTAGkMAAAFAFkAawwAAAUAUQBqDAAABABXAGwMAAADAGEAbQwAAAIAXwDqDAAABABZAG4MAAABAFQAFAAICagi8gAAuAIIaAwAAAQAUwBpDAAABQBZAGsMAAAFAFEAagwAAAQAVwBsDAAAAwBhAG0MAAACAF8A6gwAAAQAWQBuDAAAAQBUAAAA.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAGAK0XAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJDQABADIaAA==.Owls:BAACLgAFFH8NAAIBAAQJMhqpEQBEAQRoDAAABABNAGkMAAAEAEMAawwAAAIAIgDqDAAAAwBYAAEABAkyGqkRAEQBBGgMAAAEAE0AaQwAAAQAQwBrDAAAAgAiAOoMAAADAFgALgAECn8uAAMZAAkJFiP4CgCfAgAZAAcJGyT4CgCfAgABAAkJsh+vCgCNAgABLgAFFAQJDQABADIaAA==.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAcJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMdAAgJ3w37BQCaAQhoDAAABAA0AGkMAAAEAD8AawwAAAQAJABqDAAABAA7AGwMAAAEACMAbQwAAAIAEADqDAAABAAcAG4MAAACAA0AHQAICd8N+wUAmgEIaAwAAAMANABpDAAABAA/AGsMAAADACQAagwAAAIAOwBsDAAAAgAjAG0MAAACABAA6gwAAAMAHABuDAAAAQANAA0ABglQAZtLAM0ABmgMAAABAAMAawwAAAEAAgBqDAAAAgAEAGwMAAACAAcA6gwAAAEAAgBuDAAAAQABAAAA.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8FAAIcAAMJ4xq7SAAGAQNoDAAAAgBSAGkMAAACACkA6gwAAAEAUgAcAAMJ4xq7SAAGAQNoDAAAAgBSAGkMAAACACkA6gwAAAEAUgAuAAQKfysAAhwACQlAJZ4EAIoDABwACQlAJZ4EAIoDAAAA.Proved:BAABLgAECn87AAIZAAgJlh8CBgCmAghoDAAACwBjAGkMAAAJAEUAawwAAAgAXQBqDAAACQBaAGwMAAAIAFcAbQwAAAMANwDqDAAACABdAG4MAAADADoAGQAICZYfAgYApgIIaAwAAAsAYwBpDAAACQBFAGsMAAAIAF0AagwAAAkAWgBsDAAACABXAG0MAAADADcA6gwAAAgAXQBuDAAAAwA6AAAA.',
Ps='Psillycybin:BAAALgAECgcJCQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgcJEQAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAABLgAECn8sAAIKAAkJChMwHgDRAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAKAAkJChMwHgDRAQloDAAABQAUAGkMAAAFADUAawwAAAUASwBqDAAABgAzAGwMAAAGADgAbQwAAAUAKgDqDAAABwBUAG4MAAAEABcAbwwAAAEAHAAAAA==.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJEAABLgAECgQJDwAOAAAAAA==.Rizy:BAABLgAECn8WAAIcAAgJ8g3WPwCJAQhoDAAABAAsAGkMAAAEACcAawwAAAQAHwBqDAAAAwArAGwMAAACABoAbQwAAAEAJQDqDAAAAwArAG4MAAABABwAHAAICfIN1j8AiQEIaAwAAAQALABpDAAABAAnAGsMAAAEAB8AagwAAAMAKwBsDAAAAgAaAG0MAAABACUA6gwAAAMAKwBuDAAAAQAcAAAA.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAABLgAECn85AAIEAAkJbSAOBAD+AgloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAEAAkJbSAOBAD+AgloDAAABwBaAGkMAAAHAF0AawwAAAYAYgBqDAAACABUAGwMAAAIAFkAbQwAAAUASADqDAAACQBSAG4MAAAFAFQAbwwAAAIANQAAAA==.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiFDIwDlAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwACAAYJPiFDIwDlAQZoDAAABABLAGkMAAAEAFoAawwAAAQAXQBqDAAAAQBOAGwMAAABAE0A6gwAAAYAVwAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJBwABLgAECgkJRgAHABgkAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8kAAIcAAgJzxsgGABHAghoDAAABwBPAGkMAAAGAFkAawwAAAYAUwBqDAAABABNAGwMAAAEADgAbQwAAAEAJgDqDAAABgBGAG4MAAACAFAAHAAICc8bIBgARwIIaAwAAAcATwBpDAAABgBZAGsMAAAGAFMAagwAAAQATQBsDAAABAA4AG0MAAABACYA6gwAAAYARgBuDAAAAgBQAAAA.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgIJAwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8UAAIeAAcJvQxhFgD2AAdoDAAAAwAWAGkMAAAEADoAawwAAAUAHwBqDAAAAgAQAOoMAAAEACcAbgwAAAEAIgBvDAAAAQAJAB4ABwm9DGEWAPYAB2gMAAADABYAaQwAAAQAOgBrDAAABQAfAGoMAAACABAA6gwAAAQAJwBuDAAAAQAiAG8MAAABAAkAAAA=.',
Sl='Slashology:BAAALgAECgYJBwAAAA==.',
Sm='Smallpally:BAAALgAECgQJDAAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8YAAIGAAcJpBYXPQCYAQdoDAAABAA6AGkMAAAEAEUAawwAAAQANwBqDAAAAwBFAGwMAAADAEAA6gwAAAUAMgBuDAAAAQAxAAYABwmkFhc9AJgBB2gMAAAEADoAaQwAAAQARQBrDAAABAA3AGoMAAADAEUAbAwAAAMAQADqDAAABQAyAG4MAAABADEAAAA=.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJSA+6QgBmAQhoDAAABAA9AGkMAAAEACcAawwAAAUAKABqDAAABABLAGwMAAADAEEAbQwAAAIAGwDqDAAABAAjAG4MAAABAAQAAgAICUgPukIAZgEIaAwAAAQAPQBpDAAABAAnAGsMAAAFACgAagwAAAQASwBsDAAAAwBBAG0MAAACABsA6gwAAAQAIwBuDAAAAQAEAAAA.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAQAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAAALgAECgYJDwABLgAFFAMJBQASAOMYAA==.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIIAAgJHBvBAADdAghoDAAAAwBjAGkMAAAFAGEAawwAAAUAWwBqDAAABABFAGwMAAABAB8AbQwAAAEAIQDqDAAABQBjAG4MAAABACAACAAICRwbwQAA3QIIaAwAAAMAYwBpDAAABQBhAGsMAAAFAFsAagwAAAQARQBsDAAAAQAfAG0MAAABACEA6gwAAAUAYwBuDAAAAQAgAC4ABAp/JgACCAAJCeskZQIA2AMACAAJCeskZQIA2AMAAAA=.Touchi:BAAALgAECgEJAgABLgAECggJHAAXAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8cAAIXAAgJchoRBQAZAghoDAAABgBeAGkMAAAEAEYAawwAAAQARwBqDAAAAwBSAGwMAAACADwAbQwAAAIAKwDqDAAABABEAG4MAAADAEEAFwAICXIaEQUAGQIIaAwAAAYAXgBpDAAABABGAGsMAAAEAEcAagwAAAMAUgBsDAAAAgA8AG0MAAACACsA6gwAAAQARABuDAAAAwBBAAAA.Turbid:BAABLgAECn8fAAIEAAgJkxPlKwCSAQhoDAAABgBKAGkMAAAFADQAawwAAAUAOQBqDAAABAAmAGwMAAAEACsAbQwAAAIAJADqDAAABAAkAG4MAAABADIABAAICZMT5SsAkgEIaAwAAAYASgBpDAAABQA0AGsMAAAFADkAagwAAAQAJgBsDAAABAArAG0MAAACACQA6gwAAAQAJABuDAAAAQAyAAAA.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIGAAkJrRdmFgBRAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAGAAkJrRdmFgBRAgloDAAAAwBEAGkMAAADAE4AawwAAAMAVABqDAAAAgBJAGwMAAACADcAbQwAAAIAIADqDAAAAwArAG4MAAACAFQAbwwAAAEAJQAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgUJCQAAAA==.',
Yo='Yogurt:BAAALgAECgYJCAABLgAECggJKQAGAHoVAA==.',
Yu='Yusuke:BAABLgAECn8WAAMfAAcJfhHXFwCAAQdoDAAABABEAGkMAAAEACoAawwAAAQASgBqDAAAAwAXAGwMAAADABoA6gwAAAMAJABuDAAAAQATAB8ABwl+EdcXAIABB2gMAAACAEQAaQwAAAIAKgBrDAAAAgBKAGoMAAACABcAbAwAAAIAGgDqDAAAAgAkAG4MAAABABMADAAGCT0JcUAA4AAGaAwAAAIAHQBpDAAAAgAnAGsMAAACABkAagwAAAEABQBsDAAAAQANAOoMAAABABsAAS4ABAoICRAADgAAAAA=.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zunden:BAAALgAECgYJCwAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Druid-Guardian','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Mage-Frost','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Paladin-Holy','Shaman-Enhancement','Mage-Fire','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Devourer','Priest-Holy','Druid-Feral','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Priest-Discipline','Evoker-Devastation','Hunter-Marksmanship','DeathKnight-Frost','Hunter-Survival','Monk-Brewmaster',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Aboyton:BAAALgADCgQJBwAAAA==.',
Ac='Acharr:BAAALgADCgcJBwAAAA==.Acheios:BAAALgAECgIJAgAAAA==.Acinas:BAAALgADCgcJCwAAAA==.Acosadora:BAAALgAECgcJBwAAAA==.',
Ad='Adhpally:BAAALgAECgIJBAABLgAFFAIJBAABAAAAAA==.Adurangi:BAAALgAECgEJAgAAAA==.',
Ae='Aefarshammy:BAAALgADCgEJAQAAAA==.Aelaravia:BAAALgAECgMJAwAAAA==.Aerithorn:BAABLgAECn8dAAICAAgJyB99AwBZAgACAAgJyB99AwBZAgAAAA==.Aethereon:BAAALgADCgYJDQAAAA==.Aethora:BAAALgADCgQJBAABLgAECgYJEAABAAAAAA==.Aethoric:BAAALgAECgYJEAAAAA==.Aewynn:BAAALgADCgcJBwAAAA==.',
Ag='Agirashii:BAAALgADCgUJBwAAAA==.',
Ai='Airundies:BAAALgAECgcJCAABLgAECgkJGwADAL8NAA==.',
Ak='Akoris:BAAALgADCgYJCAABLgAECgkJGgAEABMQAA==.Akorys:BAABLgAECn8aAAMEAAkJExACJACTAQAEAAkJExACJACTAQAFAAEJOAX3iwAfAAAAAA==.',
Al='Alakuna:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.Alenci:BAAALgADCgYJCAAAAA==.Alexofor:BAAALgAECgMJAwAAAA==.Allatu:BAAALgADCgUJBQAAAA==.Alliasterius:BAAALgADCgEJAQAAAA==.Althus:BAAALgAFFAEJAQAAAA==.Alturiak:BAABLgAECn8XAAMGAAYJjRYFFgBOAQAHAAUJ1hVXVwBPAQAGAAUJkhYFFgBOAQAAAA==.Alucius:BAAALgAECgEJAwAAAA==.',
Am='Amion:BAAALgADCgMJAwAAAA==.Ammodeus:BAAALgADCgMJAwAAAA==.Amortin:BAAALgADCgUJBQAAAA==.',
An='Andarriel:BAAALgADCgUJBQAAAA==.Anguskhan:BAAALgADCgcJBwAAAA==.Anwir:BAAALgAFFAEJAQAAAA==.',
Ap='Apgravessupp:BAAALgADCgEJAQAAAA==.Aph:BAAALgADCgUJBQAAAA==.',
Aq='Aquua:BAABLgAECn8vAAIIAAkJCRhwCABWAgAIAAkJCRhwCABWAgAAAA==.',
Ar='Araelen:BAAALgAFFAEJAQAAAA==.Aramann:BAAALgADCgcJDAAAAA==.Archemedes:BAAALgADCgEJAQABLgAFFAIJAgABAAAAAA==.Arcticdps:BAAALgAECgYJDQAAAA==.Ariahn:BAABLgAECn8gAAIJAAkJ4AalPACIAQAJAAkJ4AalPACIAQAAAA==.Ariell:BAAALgAECgMJAwAAAA==.Ariiel:BAAALgADCgkJDQABLgAECgMJAwABAAAAAA==.Arinysasza:BAAALgADCgEJAQAAAA==.Arkayik:BAAALgADCgEJAQAAAA==.Arnadun:BAAALgADCgEJAQAAAA==.Arnid:BAAALgADCgcJCwAAAA==.Arphazdk:BAAALgADCgQJBAAAAA==.Arphazmage:BAABLgAECn8hAAIKAAgJwwZrbQA2AQAKAAgJwwZrbQA2AQAAAA==.Arthimas:BAAALgAECgUJCQAAAA==.Arthuritucus:BAAALgADCgUJBQAAAA==.',
As='Aspenoa:BAAALgAECgYJDAAAAA==.Asralia:BAAALgADCgMJAwAAAA==.Astarthea:BAAALgADCgcJCAAAAA==.',
At='Athaisce:BAAALgAECgYJBQAAAA==.Athalia:BAACLgAFFH8MAAILAAQJxBgCAgBtAQALAAQJxBgCAgBtAQAuAAQKfyEAAgsACQm1IWcBABsDAAsACQm1IWcBABsDAAAA.Atlasien:BAABLgAECn8eAAMMAAgJqRkmIQADAgAMAAgJqRkmIQADAgANAAIJNQi6OABdAAAAAA==.',
Au='Aug:BAAALgAECgYJDAAAAA==.Augiey:BAAALgAECgQJCAAAAA==.Aulayia:BAAALgAECgIJCQAAAA==.Aurellea:BAAALgADCggJEAAAAA==.Auroraplague:BAAALgAECggJDgAAAA==.',
Av='Avex:BAABLgAECn8zAAIOAAgJGiRMBwC8AgAOAAgJGiRMBwC8AgAAAA==.',
Aw='Awentamis:BAAALgADCgEJAQAAAA==.Awetysmz:BAAALgAECgEJAwAAAA==.',
Ax='Axeboom:BAAALgADCgcJDAABLgAECgkJLgAKAI4YAA==.Axelock:BAAALgADCgYJBgABLgAECgkJLgAKAI4YAA==.Axemage:BAABLgAECn8uAAMKAAkJjhhlFQBvAgAKAAkJjhhlFQBvAgAPAAMJPgy9EQCnAAAAAA==.Axeom:BAABLgAECn8tAAMQAAkJDRGwKgDiAQAQAAkJDRGwKgDiAQAIAAYJowlmMgDnAAAAAA==.Axeshammy:BAAALgAECgUJBgABLgAECgkJLgAKAI4YAA==.',
Ay='Ayanna:BAAALgADCgQJBAAAAA==.',
Az='Azazin:BAAALgADCgUJBQAAAA==.Azendethen:BAAALgAECgEJAQAAAA==.Azmodan:BAAALgADCgYJBgAAAA==.Azurewynith:BAAALgADCgYJBgAAAA==.Azzclappin:BAAALgAECgEJAQAAAA==.Azzclappius:BAAALgAECgYJCgAAAA==.',
Ba='Backwing:BAAALgADCgYJBgAAAA==.Badragon:BAAALgAECgYJEAAAAA==.Baelfang:BAAALgADCgYJBwAAAA==.Baelgrim:BAAALgAECgMJBAAAAA==.Bagu:BAABLgAECn8sAAMMAAkJUBhvFQBOAgAMAAkJUBhvFQBOAgARAAgJ0wRfKQBCAQAAAA==.Bahn:BAAALgAECgEJAQABLgAFFAIJBgANACcJAA==.Bajaladin:BAAALgAECgcJBwAAAA==.Bambey:BAAALgADCgMJAwAAAA==.Bandanirn:BAAALgAECgEJAgAAAA==.Bandït:BAAALgAECgQJAwAAAA==.Bangki:BAAALgADCgMJBAAAAA==.Barometer:BAAALgAECgIJAgAAAA==.Bast:BAAALgAECgkJBgABLgAECgkJDAABAAAAAA==.',
Bb='Bbqchips:BAAALgADCgQJBQAAAA==.',
Bc='Bchamp:BAABLgAECn8ZAAMSAAYJShPmEwB7AQASAAYJShPmEwB7AQAQAAQJgBKhTwDAAAAAAA==.',
Be='Beamsy:BAAALgADCgkJGQABLgAECggJLwAKAHcjAA==.Beansoup:BAAALgADCgMJAwAAAA==.Beefmeister:BAABLgAECn8dAAIHAAcJGBPBGwCKAQAHAAcJGBPBGwCKAQAAAA==.Belamorte:BAAALgAECgEJAQAAAA==.Beliala:BAAALgADCgkJGQAAAA==.Belveth:BAAALgADCgEJAQAAAA==.Benwins:BAABLgAECn8VAAITAAYJ/QTEBQDOAAATAAYJ/QTEBQDOAAAAAA==.Bertoxxulous:BAAALgADCgIJAgAAAA==.Besus:BAAALgADCgUJCwAAAA==.Beyonddeath:BAAALgADCggJCAAAAA==.',
Bh='Bho:BAAALgADCgYJDAAAAA==.',
Bi='Biffedit:BAAALgAECgYJEwAAAA==.Biofarmer:BAAALgAECgEJAQAAAA==.Biscuitbabe:BAAALgAECgUJBQAAAA==.Bisholoyd:BAABLgAECn8ZAAMUAAcJhhU4BgCQAQAUAAcJIxU4BgCQAQAVAAIJCQthFwA7AAAAAA==.Bitshift:BAAALgAECgYJDAAAAA==.Bizoune:BAAALgADCgYJBwAAAA==.',
Bl='Blackwing:BAAALgAECgYJCQAAAA==.Blastoise:BAACLgAFFH8LAAIJAAQJnhSuKwBJAQAJAAQJnhSuKwBJAQAuAAQKfx8AAxYACQkmHtkHAKoCABYACQnPHdkHAKoCAAkABAnkHCxpABABAAAA.Blathian:BAAALgAECggJDAAAAA==.Blazakin:BAAALgAECgYJDQAAAA==.Blooms:BAAALgADCgUJBQABLgAECgQJBAABAAAAAA==.Bluntsmasta:BAAALgADCgkJEwAAAA==.Blupe:BAAALgADCgkJFAAAAA==.Blutang:BAAALgAECgYJBgAAAA==.Bløøms:BAAALgADCgcJBwABLgAECgQJBAABAAAAAA==.',
Bo='Boaster:BAAALgADCgEJAQAAAA==.Bobadu:BAAALgAECgEJAQAAAA==.Bodhmall:BAAALgAECgYJCgAAAA==.Bongwater:BAAALgAECgIJBAAAAA==.Booktok:BAAALgAECgEJAgAAAA==.Boombóx:BAAALgADCgkJDAABLgAECggJLwAXAKIjAA==.Boome:BAAALgAFFAIJAgABLgAFFAQJDAALAMQYAA==.Boonk:BAAALgADCgEJAQAAAA==.Boop:BAAALgADCgYJCQAAAA==.Bootydew:BAAALgAECgQJBAAAAA==.Bootysama:BAAALgAECgEJAgABLgAECgQJBAABAAAAAA==.Boris:BAAALgADCgYJBgAAAA==.Borrax:BAAALgAFFAMJAwAAAA==.Borthos:BAABLgAECn8hAAIYAAkJWCDGBQDPAgAYAAkJWCDGBQDPAgAAAA==.Bowsback:BAAALgADCgEJAQAAAA==.',
Br='Braetorius:BAAALgAECgYJBgAAAA==.Breece:BAAALgADCgEJAQAAAA==.Bretalea:BAAALgADCgcJBwAAAA==.Brewsli:BAAALgADCgQJBAAAAA==.Brickinkeys:BAABLgAECn8UAAIZAAcJTRKDGQCCAQAZAAcJTRKDGQCCAQABLgAECggJDgABAAAAAA==.Brontegorpse:BAAALgADCgUJBQAAAA==.Brynnix:BAAALgADCgUJDAAAAA==.',
Bu='Bugfishleg:BAAALgADCgcJEQAAAA==.Buttardrolls:BAAALgADCgQJBAAAAA==.',
By='Byblethumper:BAAALgADCgEJAQAAAA==.',
['Bà']='Bàne:BAAALgAECgMJBAAAAA==.',
Ca='Caadra:BAAALgADCgUJBQAAAA==.Caarny:BAAALgAECgYJDQAAAA==.Cactusjack:BAAALgAECgYJDQAAAA==.Caimie:BAAALgAECgMJAwAAAA==.Caiste:BAAALgAECgEJAQAAAA==.Camel:BAAALgADCgMJAwAAAA==.Candez:BAAALgAECgYJBgAAAA==.Canfar:BAAALgAECgUJDQAAAA==.Cassiaan:BAAALgADCgIJAgAAAA==.Catacares:BAAALgAECgkJCAAAAA==.Catalog:BAAALgAECgQJBgAAAA==.Catamandu:BAAALgAFFAEJAQAAAA==.Catismeong:BAAALgAECggJBgAAAA==.Cayiane:BAAALgAECggJDQAAAA==.Caylavibes:BAAALgAECgYJDQAAAA==.',
Ce='Cebola:BAAALgAECgYJEAAAAA==.Cerbaderp:BAAALgAECgMJAwAAAA==.',
Ch='Chackyjan:BAAALgAECgUJBQABLgAECgcJHgANAFodAA==.Chameleos:BAAALgADCgMJAwAAAA==.Chasechases:BAABLgAECn8jAAUaAAgJDQuRCwBgAQAaAAgJDQuRCwBgAQAbAAIJDwbTvQBLAAACAAIJuQgHJQBFAAAcAAIJsQLQYwAfAAAAAA==.Chazyy:BAAALgAECggJEgAAAA==.Cheetasista:BAAALgADCgMJAwAAAA==.Cherry:BAAALgAECgcJDAAAAA==.Chibichanga:BAAALgAECgMJAwAAAA==.Chibiusaa:BAAALgAECgMJAwAAAA==.Chiechan:BAAALgADCgMJAwAAAA==.Chimubai:BAABLgAECn8WAAIFAAcJCw8qOAA9AQAFAAcJCw8qOAA9AQAAAA==.Chokano:BAAALgADCgcJCgAAAA==.Chokeagoat:BAAALgADCgUJBQAAAA==.Chonker:BAAALgAECgEJAQAAAA==.Chor:BAACLgAFFH8GAAINAAIJJwmnCgBSAAANAAIJJwmnCgBSAAAuAAQKfxkAAw0ACAmvEDcNAGUBAA0ACAmvEDcNAGUBAAwAAQmnAfofAR8AAAAA.Christinei:BAAALgAECgMJAwAAAA==.Chull:BAAALgAECgMJBAAAAA==.',
Ci='Cinderkai:BAAALgADCgQJBAAAAA==.Cinemabunny:BAAALgAECgYJCAAAAA==.Circusfreak:BAAALgAECggJEgAAAA==.',
Cl='Classified:BAAALgAECgEJAQAAAA==.Cleyl:BAAALgAECgYJDgAAAA==.Clohhe:BAAALgAECgQJCAAAAA==.',
Co='Cokeftw:BAAALgAECgMJBAAAAA==.Coman:BAACLgAFFH8GAAIQAAIJwhEXMACEAAAQAAIJwhEXMACEAAAuAAQKfy0AAxAACAk0H0EJAJkCABAACAk0H0EJAJkCAAgABQleEyIzAOQAAAAA.Consecrated:BAAALgAECgcJAQAAAA==.Cosmochopper:BAABLgAECn8gAAMFAAcJECJJDQCmAgAFAAcJECJJDQCmAgAEAAMJCg1oPQCPAAAAAA==.',
Cq='Cq:BAABLgAECn8mAAIYAAkJ+xd8NQAiAgAYAAkJ+xd8NQAiAgAAAA==.',
Cr='Cremebrule:BAAALgAECgEJAwAAAA==.Cremesodax:BAABLgAECn8cAAIMAAgJfw+KPgCKAQAMAAgJfw+KPgCKAQAAAA==.Cringeknight:BAAALgAECggJEwAAAA==.Critfäce:BAAALgAECgIJAwAAAA==.Critjutsu:BAABLgAECn8eAAIEAAgJzCEqBwCJAgAEAAgJzCEqBwCJAgAAAA==.Croces:BAABLgAECn8XAAMYAAcJ0h1NFgAJAgAYAAcJrB1NFgAJAgAdAAQJVRqzQQDyAAABLgAFFAIJBAABAAAAAA==.Crushleaf:BAAALgADCgcJCQAAAA==.',
Cu='Cucubau:BAAALgADCgUJBQAAAA==.Cuppanoods:BAAALgADCgYJCgAAAA==.',
Cy='Cyndra:BAAALgAECgUJCgAAAA==.Cynsia:BAAALgADCgUJAwAAAA==.',
['Cá']='Cárnage:BAAALgADCgQJBQAAAA==.',
Da='Dadonut:BAAALgAECgcJEwAAAA==.Daemonspawnn:BAAALgADCgIJAgAAAA==.Dalthyriian:BAABLgAECn8mAAIYAAYJahtIMwBoAQAYAAYJahtIMwBoAQAAAA==.Damii:BAAALgADCgcJGQAAAA==.Dandissima:BAAALgAECgMJAwAAAA==.Danfarm:BAAALgAECgEJAQAAAA==.Danny:BAAALgAECgEJAQAAAA==.Dargonbref:BAAALgADCgUJBQABLgAECggJIQAJANwRAA==.Darjen:BAAALgAECggJDAAAAA==.Darkjestêr:BAAALgAECgIJAgAAAA==.Darlough:BAAALgADCgQJBAAAAA==.Darthra:BAAALgAECgUJCQAAAA==.Darthsteak:BAAALgADCgMJAwAAAA==.Dasblur:BAABLgAECn8ZAAIYAAgJNhvsLQBFAgAYAAgJNhvsLQBFAgAAAA==.Dawncygnu:BAAALgADCgUJBQAAAA==.',
Dc='Dcash:BAABLgAECn8vAAIMAAgJihVeJwDjAQAMAAgJihVeJwDjAQAAAA==.Dcashcrafter:BAAALgADCgMJAwAAAA==.',
De='Deadlyarrow:BAAALgAECggJEQAAAA==.Deadsilenth:BAAALgAECgUJCwAAAA==.Deamonessa:BAAALgAECgMJAwAAAA==.Deathfang:BAAALgADCgMJAwAAAA==.Deathlyy:BAABLgAECn8rAAIeAAkJsCDJAQDyAgAeAAkJsCDJAQDyAgAAAA==.Deathtress:BAAALgADCggJCAAAAA==.Deatlas:BAAALgAECgYJBwAAAA==.Debbydowner:BAABLgAECn8WAAMGAAgJkQmVGwDZAAAGAAYJXAqVGwDZAAAHAAYJRgUVQwCyAAAAAA==.Decado:BAAALgAECgkJDAAAAA==.Delatrin:BAAALgADCgUJBQAAAA==.Delnir:BAAALgADCgQJBwAAAA==.Demongoat:BAAALgAECgEJAQAAAA==.Demonroo:BAAALgADCgcJCwAAAA==.Denimdan:BAABLgAECn8pAAQfAAkJXByACACZAgAfAAkJXByACACZAgAGAAgJ2QcQEgAxAQAHAAEJEwk+ZwA3AAAAAA==.Desetaz:BAAALgADCgMJAwAAAA==.Desetren:BAAALgAECgMJAwAAAA==.Devinedrama:BAAALgAECgYJEwAAAA==.',
Dh='Dhawk:BAABLgAECn8UAAIMAAcJ7QwRZAAlAQAMAAcJ7QwRZAAlAQAAAA==.',
Di='Digkdug:BAAALgADCgQJCQAAAA==.Distance:BAAALgADCgcJBwAAAA==.Dizzypal:BAAALgADCgQJBQAAAA==.',
Dk='Dkalliru:BAABLgAECn8oAAMWAAkJDhuxBABpAgAWAAkJDhuxBABpAgAJAAYJsQNoyADyAAAAAA==.Dkisop:BAAALgAECgEJAQAAAA==.Dkpuff:BAAALgAECgYJEgAAAA==.',
Do='Docdolittle:BAAALgAECgYJEwABLgAECggJHgAKAA8ZAA==.Docfreez:BAABLgAECn8vAAIKAAgJdyPOCgDNAgAKAAgJdyPOCgDNAgAAAA==.Docfrosty:BAABLgAECn8eAAIKAAgJDxkWKwD1AQAKAAgJDxkWKwD1AQAAAA==.Docragosa:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Docrighteous:BAABLgAECn8UAAIMAAcJWRVWOQCbAQAMAAcJWRVWOQCbAQABLgAECggJHgAKAA8ZAA==.Doctafury:BAAALgAECgQJBAABLgAECggJHgAKAA8ZAA==.Dogar:BAAALgADCgIJAgAAAA==.Doggomasta:BAAALgAECgEJAQAAAA==.Dominal:BAAALgAECgEJAQAAAA==.Doomhamer:BAAALgADCgYJBgABLgAECgkJIQAYAFggAA==.Doraemee:BAAALgAECgYJDAAAAA==.Doraleous:BAAALgADCgQJBAAAAA==.Doresaingk:BAAALgADCgEJAQAAAA==.Dorllian:BAAALgADCgEJAQAAAA==.',
Dr='Drablooms:BAAALgAECgQJBAAAAA==.Dracotriface:BAAALgAECgQJBAAAAA==.Drahk:BAAALgADCggJCAAAAA==.Drain:BAAALgAECgkJBAAAAA==.Dravenholy:BAAALgAECgEJAQAAAA==.Drbaobuns:BAAALgAECgYJDQABLgAECgkJEwABAAAAAA==.Drboomnugget:BAAALgADCgcJBwAAAA==.Dreamerdr:BAAALgAECgUJBQAAAA==.Dreidel:BAAALgAECgEJAQAAAA==.Dreim:BAEALgAECgEJAQABLgAFFAMJCgAMAEIgAA==.Drezdorn:BAAALgAECgEJAgAAAA==.Drgatorwine:BAAALgADCgkJDgABLgAECgkJEwABAAAAAA==.Drizdourden:BAAALgAECgEJAQAAAA==.Drjp:BAAALgAECgYJDgAAAA==.Drkimchirice:BAAALgAECgUJBgABLgAECgkJEwABAAAAAA==.Drlocktapus:BAABLgAECn8iAAIXAAkJLRr7LwBNAgAXAAkJLRr7LwBNAgAAAA==.Drmacncheese:BAABLgAECn8WAAIUAAYJqR59BADDAQAUAAYJqR59BADDAQABLgAECgkJEwABAAAAAA==.Drpumpkinpie:BAAALgAECgQJBAABLgAECgkJEwABAAAAAA==.Drugzone:BAABLgAECn8aAAMCAAgJmA/2DAA+AQACAAcJwxH2DAA+AQAaAAEJmAJRLQAiAAAAAA==.Drwontonsoup:BAAALgAECgkJEwAAAA==.',
Du='Duddyfuddy:BAAALgAECgQJBQAAAA==.Duiunit:BAAALgAECgMJAwAAAA==.Dumblìedore:BAAALgAECgIJAgAAAA==.Dummythicc:BAAALgAECgQJBgAAAA==.Durknessa:BAAALgADCgEJAQAAAA==.Durugak:BAAALgADCgQJBAAAAA==.',
Dw='Dwag:BAAALgADCgcJDAAAAA==.',
Dx='Dxmxt:BAAALgADCgEJAQAAAA==.',
Dy='Dye:BAAALgAECgMJBAAAAA==.',
Ea='Earthhammer:BAAALgAECggJDAAAAA==.Easyy:BAABLgAECn8dAAIbAAgJKBiyFwAHAgAbAAgJKBiyFwAHAgAAAA==.',
Ec='Ecthdaran:BAAALgAFFAEJAQAAAA==.',
Ed='Edoras:BAAALgADCgcJDQAAAA==.',
Ef='Efton:BAAALgAECgUJCQAAAA==.',
Eh='Ehpsteensfav:BAAALgADCgYJBgAAAA==.',
Ek='Eksi:BAAALgAECgUJCAAAAA==.',
El='Elemjae:BAAALgAECgYJBwABLgAECgcJIwAIAEYkAA==.Elethe:BAAALgADCgkJFQABLgAFFAEJAQABAAAAAA==.Elftastic:BAAALgAECgUJBQABLgAFFAYJFQAKANwdAA==.Elgebaly:BAAALgAECgEJAQAAAA==.Eliorian:BAAALgADCgUJBQAAAA==.Elivan:BAAALgADCgEJAQAAAA==.Elizebet:BAAALgADCgYJCQAAAA==.Elladria:BAAALgADCgMJAwAAAA==.Ellicit:BAAALgADCgMJAwAAAA==.Elzaine:BAABLgAECn8ZAAIMAAkJ8yBVHgC1AgAMAAkJ8yBVHgC1AgAAAA==.',
Em='Emis:BAAALgADCgQJBwAAAA==.Emporic:BAAALgADCgUJBQAAAA==.Empress:BAAALgAECgUJBQAAAA==.',
En='Enhae:BAAALgADCgUJBQAAAA==.Entrophi:BAAALgAECgQJBQABLgAECgcJFwAVAC4fAA==.Entropi:BAABLgAECn8qAAIgAAgJzBMFEQDJAQAgAAgJzBMFEQDJAQAAAA==.Envys:BAABLgAECn8YAAIKAAgJ1RBqiwC7AQAKAAgJ1RBqiwC7AQAAAA==.Envyshunt:BAAALgAECgYJBgAAAA==.Envyspal:BAAALgAECgQJCgAAAA==.',
Er='Erisnyx:BAAALgAECgkJBwAAAA==.',
Es='Esterelore:BAAALgAECgMJBAAAAA==.Estix:BAAALgAECgUJBgAAAA==.',
Et='Etherwing:BAAALgAECgcJEwAAAA==.',
Ev='Evilwwink:BAAALgAECgEJAQAAAA==.',
Ex='Excruciator:BAAALgAECgQJBQAAAA==.Excruciators:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Ez='Ezfran:BAEALgAECgkJAQAAAA==.Ezrabridger:BAAALgAECgMJAwAAAA==.Ezranim:BAAALgADCgYJBgAAAA==.',
Fa='Faithfull:BAAALgADCgYJBgAAAA==.Falloutz:BAAALgAECgYJEgAAAA==.Falloutzhunt:BAAALgADCggJCAABLgAECgYJEgABAAAAAA==.Falthun:BAAALgADCgMJAwAAAA==.Faschlangus:BAAALgADCgEJAQAAAA==.Fatcows:BAAALgAECgcJCAAAAA==.Fawxette:BAAALgAECgEJAQABLgAECggJMQAYAJoXAA==.',
Fe='Felger:BAAALgADCgMJAwAAAA==.Felintovoid:BAABLgAECn8cAAIYAAgJYxQ7WQCWAQAYAAgJYxQ7WQCWAQAAAA==.Feliya:BAAALgAECgEJAQAAAA==.Fengami:BAAALgADCgEJAQAAAA==.Fenridinn:BAAALgADCgYJCQAAAA==.Fesha:BAAALgADCgEJAQABLgAECgQJCQABAAAAAA==.',
Fi='Fieryfrost:BAAALgADCgkJEQABLgAECgcJHgAfAEoKAA==.Finowscath:BAAALgAECgEJAQAAAA==.Fistdoc:BAAALgAECgUJDgABLgAECgYJDQABAAAAAA==.Fistynae:BAABLgAECn8fAAMFAAkJOxg5CABAAgAFAAkJOxg5CABAAgAEAAYJjRu5HADQAQAAAA==.Fizzlesaurus:BAAALgAECggJEQAAAA==.Fizzroll:BAAALgADCgIJAgAAAA==.',
Fl='Flamelece:BAAALgAECgIJAgABLgAECgYJEgABAAAAAA==.Fleshmaw:BAAALgADCgUJAwAAAA==.Flexorcist:BAAALgADCgYJBwAAAA==.Floo:BAAALgAECgEJAgAAAA==.Floralas:BAABLgAECn8lAAIbAAcJfhRuJgCZAQAbAAcJfhRuJgCZAQAAAA==.',
Fo='Fordinnir:BAAALgAECgIJAgAAAA==.Forseer:BAAALgADCgYJBgAAAA==.Foxjìtsu:BAAALgADCgEJAQAAAA==.Foxknight:BAAALgADCgkJEQABLgAECggJMQAYAJoXAA==.Foxybag:BAAALgADCgMJBAAAAA==.Foxytotes:BAAALgADCgYJBwAAAA==.',
Fr='Frapless:BAAALgAECgMJAwAAAA==.Freezzerr:BAAALgADCgEJAQAAAA==.Frickenmage:BAAALgAECgUJCwAAAA==.Friendlypal:BAABLgAECn8YAAMRAAgJHBobGQDCAQARAAgJHBobGQDCAQAMAAIJLw9vvwB2AAAAAA==.Friendofbear:BAACLgAFFH8FAAIOAAMJ8Q0mKQD1AAAOAAMJ8Q0mKQD1AAAuAAQKfysAAg4ACQmNF7IhADsCAA4ACQmNF7IhADsCAAAA.Frogo:BAAALgADCgMJAwAAAA==.',
Fu='Fudomeow:BAAALgADCgMJAwAAAA==.Fumazusha:BAAALgADCgIJAgAAAA==.Fumblebuck:BAAALgADCgkJGQABLgAECgYJEAABAAAAAA==.Funshíne:BAAALgADCgcJBwAAAA==.Furrybutted:BAAALgADCgcJAQAAAA==.Furryfeet:BAAALgAECgcJEQAAAA==.Furyofdawn:BAAALgAECgEJAQAAAA==.Fuzzpuff:BAAALgADCgMJBAAAAA==.Fuzzykuntz:BAAALgAECgkJDwAAAA==.',
Fy='Fynsdood:BAAALgADCgYJBgABLgAECgcJDAABAAAAAA==.Fynslane:BAAALgAECgYJEgABLgAECgcJDAABAAAAAA==.Fynstick:BAAALgAECgcJDAAAAA==.',
Ga='Gabelock:BAACLgAFFH8PAAIXAAUJtBSqCQCSAQAXAAUJtBSqCQCSAQAuAAQKfyIAAhcACAn/IPQcAKgCABcACAn/IPQcAKgCAAAA.Garchomp:BAABLgAECn8bAAIYAAcJ5RtpGgDrAQAYAAcJ5RtpGgDrAQAAAA==.',
Gh='Ghostreveri:BAABLgAECn8nAAIMAAgJ2xoGHgATAgAMAAgJ2xoGHgATAgAAAA==.Ghoulface:BAAALgAECgQJBQABLgAFFAYJEwAXAKcXAA==.',
Gi='Gigah:BAAALgAECgYJDwAAAA==.Gildin:BAAALgAECgYJCQAAAA==.Gingerbell:BAAALgAECgUJBgAAAA==.Gingercool:BAAALgADCgcJBwAAAA==.',
Gl='Gladys:BAAALgADCgEJAQAAAA==.Global:BAAALgADCgcJCgAAAA==.Glopthethird:BAAALgADCgYJBgAAAA==.Glorpnotl:BAAALgAECgUJBQAAAA==.',
Gn='Gnomedalf:BAAALgAECgEJAQAAAA==.Gnomedguerre:BAAALgADCgMJAwAAAA==.',
Go='Goatstatik:BAAALgAECgYJDQAAAA==.Goblinface:BAAALgADCgUJBQAAAA==.Gollie:BAAALgAECgEJAQAAAA==.Gooblash:BAAALgAECgEJAQAAAA==.Goonerrofoz:BAAALgAECgUJDQAAAA==.Goonnugget:BAAALgAECgYJEQAAAA==.Gorthmog:BAAALgADCgQJBwAAAA==.',
Gr='Grampysmack:BAAALgADCggJEAAAAA==.Gravefeet:BAAALgADCgUJBQAAAA==.Gravehands:BAAALgADCgIJAgAAAA==.Gredory:BAAALgAECgYJCgAAAA==.Greendoritos:BAAALgAECgQJCQAAAA==.Grekum:BAABLgAECn8VAAMJAAYJJhfZNQCiAQAJAAYJJhfZNQCiAQAWAAEJeQaaPAAjAAAAAA==.Grep:BAAALgADCgEJAQAAAA==.Grimtree:BAABLgAECn8aAAMVAAgJ8heeBQAPAgAVAAgJ8heeBQAPAgAXAAEJaRHIyQA/AAAAAA==.Grindor:BAAALgADCgQJBwAAAA==.Grogge:BAAALgADCgIJAgAAAA==.Grumpstraza:BAAALgAECgEJAQAAAA==.Grumpydemon:BAABLgAECn8VAAIYAAgJgQ7+MgBpAQAYAAgJgQ7+MgBpAQAAAA==.',
Gu='Guglugauthu:BAABLgAECn8VAAIHAAYJqguCWABLAQAHAAYJqguCWABLAQAAAA==.Gunwald:BAAALgADCgUJBQAAAA==.Gutcheck:BAABLgAECn8WAAIeAAcJMx72EQCMAQAeAAcJMx72EQCMAQAAAA==.',
Gw='Gwong:BAAALgADCgcJBwAAAA==.',
Gy='Gyo:BAAALgADCgcJBgABLgADCgkJDwABAAAAAA==.Gyodo:BAAALgADCgMJAwABLgADCgkJDwABAAAAAA==.Gyodoh:BAAALgADCgkJDwAAAA==.',
['Gö']='Gökû:BAAALgADCgUJBQAAAA==.',
Ha='Haaravende:BAAALgADCgUJBQAAAA==.Halfskul:BAACLgAFFH8IAAIJAAIJUwedSACSAAAJAAIJUwedSACSAAAuAAQKfy0AAgkACAnyHOUsAIUCAAkACAnyHOUsAIUCAAAA.Halinis:BAAALgAECgYJEgAAAA==.Halli:BAAALgADCgUJAQAAAA==.Halvorse:BAAALgADCgMJAwAAAA==.Harandi:BAAALgADCgEJAQAAAA==.Harugokken:BAAALgADCgYJBgAAAA==.Hasha:BAAALgADCgYJBgAAAA==.Hashah:BAABLgAECn8UAAIZAAcJ/RJJLgCLAQAZAAcJ/RJJLgCLAQABLgAECgcJFQASAPoaAA==.Hastur:BAAALgADCgYJBgAAAA==.Hatefel:BAAALgAECgEJAQABLgAECggJHgAUABUiAA==.Haveblue:BAAALgADCggJCAAAAA==.Havoke:BAAALgADCgQJBwAAAA==.Havyk:BAAALgAECgUJBQAAAA==.',
He='Healingyou:BAAALgADCgYJBgABLgAECgkJJAACAHUlAA==.Healsgobrr:BAABLgAECn8XAAIRAAkJJRq9BQDHAgARAAkJJRq9BQDHAgABLgAECgkJIgAgAMMaAA==.Hellscar:BAAALgAECgEJAgAAAA==.Herakleitos:BAAALgADCgMJAwAAAA==.Hereticdoc:BAAALgAECgYJDQAAAA==.Herrah:BAAALgADCgcJDAAAAA==.Hesha:BAABLgAECn8VAAMSAAcJ+hrwCACSAQASAAcJ+hrwCACSAQAQAAEJXQN8pgApAAAAAA==.Heytotemman:BAAALgAECgUJCQAAAA==.',
Ho='Holyaxe:BAAALgADCgMJAwABLgAECgkJLgAKAI4YAA==.Holydingi:BAAALgADCgMJBQAAAA==.Holygrammy:BAAALgADCgcJCwAAAA==.Holyligth:BAAALgAECgQJCgAAAA==.Holysock:BAAALgADCgcJBwAAAA==.Holyyaii:BAABLgAECn8XAAMDAAcJ4R2TEADIAQADAAcJ4R2TEADIAQAhAAEJzwx9SAAwAAAAAA==.Holz:BAAALgAECgYJCgAAAA==.Hoodedpando:BAAALgAECgQJDAAAAA==.Hoppah:BAAALgADCgUJBQAAAA==.Hopsing:BAAALgAECgQJDwAAAA==.Hornychicken:BAAALgADCgEJAQABLgAECgQJBQABAAAAAA==.Horsetowater:BAAALgAECgYJBgAAAA==.Hotsluttymom:BAABLgAECn8eAAIDAAcJexOjGQBvAQADAAcJexOjGQBvAQAAAA==.Hozzbek:BAAALgAECgEJAQAAAA==.',
Hu='Hugoman:BAABLgAECn8gAAIXAAcJOhA2QQBmAQAXAAcJOhA2QQBmAQABLgAECgkJKgAJAKUYAA==.Huntbugman:BAABLgAECn8WAAIOAAgJ+Q9fMwDiAQAOAAgJ+Q9fMwDiAQAAAA==.Hurash:BAAALgAECgMJAwABLgAECgcJHgANAFodAA==.Hurdtfeeling:BAAALgAECgcJDQAAAA==.',
['Hö']='Hölyheals:BAAALgADCgcJBwAAAA==.',
Ia='Iamyu:BAAALgAECgIJAwAAAA==.',
Ib='Ibun:BAABLgAECn8YAAIIAAgJURaUEQDSAQAIAAgJURaUEQDSAQAAAA==.',
Ic='Icebøx:BAAALgAECgIJAwAAAA==.Icefang:BAAALgADCgYJBgAAAA==.Icetomeetu:BAAALgADCgYJBgAAAA==.',
Ii='Iillil:BAABLgAECn8lAAIYAAkJGAmXQAA3AQAYAAkJGAmXQAA3AQAAAA==.',
Il='Illtul:BAABLgAECn8iAAIcAAgJHRp9EQC+AQAcAAgJHRp9EQC+AQAAAA==.',
Im='Imblindhelp:BAAALgAECgYJBgAAAA==.Imnotyourpal:BAAALgAECgUJCgAAAA==.Imscratchy:BAAALgADCgQJBAAAAA==.Imsomadbro:BAAALgAECgQJBAABLgAFFAYJFgAMADcgAA==.Imsweaty:BAAALgAECgkJDAAAAA==.Imzaiahfur:BAAALgAECgQJBQAAAA==.',
In='Ingraham:BAAALgADCgEJAQAAAA==.Inindorllan:BAEALgADCgkJCQABLgAECgYJEAABAAAAAA==.',
Ip='Ipwoman:BAAALgAFFAEJAgAAAA==.',
Is='Ishint:BAAALgADCgUJBQAAAA==.Isokie:BAAALgADCgIJAgAAAA==.',
It='Itradis:BAAALgAECgYJBgAAAA==.Itwasmedio:BAAALgAECgQJCQAAAA==.Itzitar:BAAALgADCgcJCgAAAA==.',
Iv='Ivanoozey:BAAALgAECgUJBQAAAA==.Ivyiina:BAAALgAECgMJCQAAAA==.',
Ja='Jae:BAABLgAECn8UAAMDAAgJYRWTDwDVAQADAAgJYRWTDwDVAQAZAAcJsBoAAAAAAAABLgAFFAIJBQAXAIYVAA==.Jaeyk:BAAALgAECgkJAQAAAA==.Jamescameron:BAAALgAECgIJAwAAAA==.Jarninn:BAAALgADCgYJDAAAAA==.Jaywaz:BAAALgAECgYJDQAAAA==.',
Jc='Jck:BAABLgAECn8qAAIKAAkJDiXfAgBUAwAKAAkJDiXfAgBUAwAAAA==.',
Je='Jearn:BAAALgAECgEJAQAAAA==.Jedsezir:BAAALgAECgIJAgAAAA==.Jessirra:BAAALgAECgEJAQAAAA==.Jessupy:BAABLgAECn8UAAIdAAYJ2BKXFgAxAQAdAAYJ2BKXFgAxAQAAAA==.Jezebelz:BAAALgADCggJEgAAAA==.',
Ji='Jimmyhot:BAABLgAECn8mAAIKAAgJ9iPoDwBJAwAKAAgJ9iPoDwBJAwAAAA==.Jimmyx:BAAALgAECgYJBgABLgAECggJJgAKAPYjAA==.Jimsywimsy:BAAALgAECgYJCwAAAA==.Jingae:BAAALgADCgQJBAAAAA==.Jirikka:BAAALgADCgEJAQAAAA==.',
Jo='Joshmrx:BAAALgADCgcJBwAAAA==.',
Jr='Jracó:BAAALgAFFAQJAQAAAA==.',
Ju='Juliettestar:BAAALgAECgEJAQAAAA==.Julz:BAABLgAECn8cAAIbAAcJ9hHPLwBiAQAbAAcJ9hHPLwBiAQAAAA==.Junepoon:BAAALgADCgIJAgAAAA==.Justiz:BAAALgAECgIJAgAAAA==.',
Jw='Jwarf:BAAALgADCgYJEQAAAA==.',
['Jø']='Jøsh:BAAALgAECgYJEwAAAA==.',
Ka='Kainga:BAAALgAECgMJAwAAAA==.Kalrendion:BAABLgAECn8VAAMiAAgJvhF/CQALAQAgAAYJbgi6NwAYAQAiAAcJ6xJ/CQALAQAAAA==.Kalru:BAAALgAECgMJAwAAAA==.Kalrufu:BAAALgAECgcJEgAAAA==.Kalzok:BAAALgADCgYJBwAAAA==.Kamuela:BAAALgAECgIJAgAAAA==.Kaptonkronic:BAAALgAECgMJAwAAAA==.Karaillyonna:BAAALgADCgcJBwABLgAECggJEQABAAAAAA==.Karasu:BAAALgAECgYJEAAAAA==.Karsiis:BAAALgAECgUJBQAAAA==.Kasion:BAAALgAECgUJBQAAAA==.Kayys:BAAALgAECgQJBAAAAA==.',
Ke='Keel:BAAALgAECgMJAwAAAA==.Keewenaw:BAAALgAECgYJCgAAAA==.Kelsier:BAABLgAECn8pAAIEAAkJviJTAQB6AwAEAAkJviJTAQB6AwAAAA==.Kerelor:BAAALgADCgcJDAAAAA==.Kesk:BAAALgAECgUJBgAAAA==.',
Kf='Kfoo:BAAALgAECgYJBgAAAA==.',
Kh='Khaosbringer:BAAALgAECgMJAwAAAA==.Khaosdragon:BAAALgADCgUJBQABLgAECgQJBQABAAAAAA==.Khaosstormz:BAAALgAECgQJBQAAAA==.Khaster:BAAALgADCgEJAQAAAA==.',
Ki='Kilavman:BAAALgADCgUJBQAAAA==.Killachefd:BAABLgAECn8fAAIJAAgJjwfyWQAzAQAJAAgJjwfyWQAzAQAAAA==.Killamanjoro:BAAALgAECgYJCQAAAA==.Killerbow:BAAALgADCgMJAwAAAA==.Kimchiwar:BAABLgAECn8gAAIHAAgJthBPGACkAQAHAAgJthBPGACkAQAAAA==.Kirasha:BAAALgAECgYJEgAAAA==.Kitchenbound:BAAALgAECggJEQAAAA==.Kittea:BAAALgADCgYJBgAAAA==.Kittychan:BAABLgAECn8qAAMJAAkJpRgqKgDTAQAJAAkJpRgqKgDTAQAWAAIJGRMqKwBzAAAAAA==.',
Kl='Klaacus:BAABLgAECn8bAAIYAAgJCxYdPwD3AQAYAAgJCxYdPwD3AQAAAA==.Kluath:BAAALgADCgcJBwAAAA==.',
Ko='Kodakdh:BAAALgAECgYJDwAAAA==.Kongol:BAAALgADCgUJBQAAAA==.Kongól:BAAALgAECgcJBwAAAA==.Koriten:BAAALgADCgUJDQAAAA==.Koschei:BAAALgADCgcJFAAAAA==.Koudelka:BAABLgAECn8YAAIdAAgJJRTuEgBbAQAdAAgJJRTuEgBbAQAAAA==.',
Kp='Kpa:BAAALgADCgcJBwAAAA==.Kpg:BAAALgAECgcJEwAAAA==.',
Kr='Kraak:BAAALgADCgMJBgAAAA==.Krilde:BAAALgAECgEJAQAAAA==.Kringelord:BAAALgAECgYJEgABLgAECggJEwABAAAAAA==.Krisus:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.Kriticál:BAAALgAECgkJBAAAAA==.Kroshivecna:BAAALgAECgYJCwAAAA==.Krustym:BAAALgADCgUJCgAAAA==.',
Ku='Kurapika:BAAALgAECgIJAgAAAA==.Kuurun:BAEALgAECgYJCgABLgAFFAMJCgAMAEIgAA==.',
Ky='Kyout:BAAALgAECggJEgAAAA==.',
La='Laeina:BAAALgADCgUJBQAAAA==.Lamerehela:BAAALgADCgYJBgAAAA==.Lathrel:BAAALgAECgYJBwAAAA==.Lazystorm:BAABLgAECn8ZAAIIAAYJZhi2HwBRAQAIAAYJZhi2HwBRAQAAAA==.',
Le='Leadfeet:BAAALgAECgMJBQAAAA==.Legiohn:BAAALgADCgEJAQAAAA==.Lelou:BAACLgAFFH8RAAMOAAQJlRufEwBOAQAOAAQJ2RifEwBOAQAjAAMJSRlgFAD8AAAuAAQKfyoAAw4ACAnmIREkAMUBACMABwnhHxUgACUCAA4ABwkNHREkAMUBAAAA.Lemartes:BAAALgADCgEJAgAAAA==.Lemmys:BAAALgADCgYJCwAAAA==.Lemoncookie:BAAALgAECgQJBgAAAA==.Lemondropped:BAAALgAECgEJAQAAAA==.Lemonsquueze:BAAALgADCgMJAgAAAA==.Leyfon:BAAALgADCgIJAgAAAA==.',
Li='Lilathiaa:BAAALgAECgcJEwAAAA==.Lilith:BAAALgAECgEJAQAAAA==.Lillymae:BAABLgAECn8XAAIjAAYJbAfpEQDTAAAjAAYJbAfpEQDTAAAAAA==.Lilshama:BAAALgADCgEJAgAAAA==.Lilsmushy:BAABLgAECn8eAAIXAAgJMRMDJwDMAQAXAAgJMRMDJwDMAQAAAA==.Limpdoodle:BAAALgAECgIJAwAAAA==.Linuspelt:BAAALgADCgcJDQAAAA==.Linuzs:BAAALgADCgQJBAAAAA==.Liondori:BAABLgAECn8VAAINAAYJLCHnDAD5AQANAAYJLCHnDAD5AQAAAA==.Lissindra:BAAALgAECgEJAQAAAA==.Lizardlad:BAAALgADCgYJBgAAAA==.Lizzang:BAAALgADCgUJBQAAAA==.',
Lm='Lmj:BAABLgAECn8jAAIIAAcJRiT+BwBeAgAIAAcJRiT+BwBeAgAAAA==.',
Lo='Lobsterfest:BAABLgAECn8XAAIOAAgJBgPWVQANAQAOAAgJBgPWVQANAQAAAA==.Lockbox:BAABLgAECn8vAAMXAAgJoiMPBwDTAgAXAAcJoiMPBwDTAgAUAAMJyh+EKAAhAQAAAA==.Lockngood:BAAALgAECgEJAQAAAA==.Lohrufal:BAAALgADCggJDQAAAA==.Lombotamy:BAAALgADCgMJAwAAAA==.Longboardpr:BAAALgADCgYJCgAAAA==.Loomin:BAACLgAFFH8VAAIKAAYJ3B3yCQDYAQAKAAYJ3B3yCQDYAQAuAAQKfx8AAgoACAkDIwMUADADAAoACAkDIwMUADADAAAA.Lorendris:BAAALgADCgQJBAAAAA==.',
Lu='Luckyfoxess:BAAALgADCgEJAQAAAA==.Luckymoo:BAAALgAECgcJEwAAAA==.Lukrid:BAAALgADCgIJAgAAAA==.Lumiru:BAAALgADCgYJBgAAAA==.Lumièrevide:BAAALgAECggJEQAAAA==.Lustee:BAAALgAECgMJAwAAAA==.',
['Lä']='Lädyæk:BAABLgAECn8VAAIOAAkJvgu4QACtAQAOAAkJvgu4QACtAQAAAA==.',
['Lì']='Lìfealèrt:BAAALgADCgcJCQAAAA==.',
Ma='Macalor:BAAALgAECgUJDQAAAA==.Madagna:BAAALgADCgcJCQAAAA==.Madboy:BAAALgAECgMJAwAAAA==.Magicwinky:BAAALgADCgYJBgABLgAECgEJAQABAAAAAA==.Mahmba:BAAALgAECgMJAwAAAA==.Mahwea:BAAALgAECgEJAQAAAA==.Makati:BAAALgADCgYJCQAAAA==.Mallidin:BAAALgAECgUJDQAAAA==.Malthoryn:BAABLgAECn8hAAIhAAcJXxhuDQD6AQAhAAcJXxhuDQD6AQAAAA==.Mamamercy:BAAALgAECgcJDQAAAA==.Manield:BAAALgAECgcJBgAAAA==.Mardys:BAAALgAECgMJBAAAAA==.Marisol:BAAALgAECgQJCQAAAA==.Masfuego:BAAALgADCgQJBAAAAA==.Mastabazzi:BAAALgADCgEJAgAAAA==.',
Me='Meal:BAAALgAECgYJDAAAAA==.Mechamike:BAAALgAECgcJEgAAAA==.Megalover:BAAALgAECgMJBQAAAA==.Melianthal:BAAALgADCgYJBgAAAA==.Melodí:BAAALgAECgEJAQAAAA==.Melorac:BAAALgAECgcJEgAAAA==.Mem:BAABLgAECn8jAAMVAAcJMx4eCADLAQAVAAcJMx4eCADLAQAXAAQJEw1kwADYAAAAAA==.Meowor:BAAALgADCgUJBQABLgAECgkJGwAEAFciAA==.Merope:BAAALgADCgYJCwAAAA==.Mertence:BAAALgADCgYJEAAAAA==.Mesandera:BAAALgAECgYJCwAAAA==.',
Mh='Mheow:BAAALgAECgMJAwAAAA==.',
Mi='Miccivxx:BAACLgAFFH8FAAIOAAMJugWbPgCcAAAOAAMJugWbPgCcAAAuAAQKfx8AAg4ACAk0GHsgANkBAA4ACAk0GHsgANkBAAAA.Microch:BAAALgADCgYJDgAAAA==.Micromortis:BAAALgAECgMJBQAAAA==.Midnightsham:BAAALgAECgMJAwAAAA==.Midnightsun:BAABLgAECn8lAAIQAAgJ9xSCIQCnAQAQAAgJ9xSCIQCnAQAAAA==.Midñight:BAAALgADCgMJAwAAAA==.Mikeoochie:BAAALgAECgEJAQAAAA==.Mimiche:BAAALgAECgUJCwAAAA==.Minxyrae:BAABLgAECn8/AAIRAAgJGA8iGQDCAQARAAgJGA8iGQDCAQAAAA==.Misamane:BAAALgAECgIJAQAAAA==.Mitufu:BAAALgAECgIJAgAAAA==.',
Mj='Mjernamir:BAABLgAECn8VAAIcAAYJOQw+KQD5AAAcAAYJOQw+KQD5AAAAAA==.',
Mo='Moistson:BAAALgAECgUJDgAAAA==.Mom:BAABLgAECn8VAAIXAAcJkxSDWQAhAQAXAAcJkxSDWQAhAQAAAA==.Momie:BAAALgADCgIJAgAAAA==.Mongorian:BAAALgADCgQJBgAAAA==.Monk:BAAALgAECgYJEgAAAA==.Monknugget:BAAALgAECggJEAAAAA==.Moofrosty:BAAALgAECgEJAgAAAA==.Moonish:BAAALgAECgEJAQABLgAECggJJgARAAUmAA==.Moonrupal:BAABLgAECn8UAAIRAAYJKyLSDwAhAgARAAYJKyLSDwAhAgAAAA==.Moonwarden:BAAALgAECgIJAgAAAA==.Mordokk:BAABLgAECn8UAAIXAAcJ9whQWAAkAQAXAAcJ9whQWAAkAQAAAA==.Morganya:BAABLgAECn8xAAIYAAgJmhfDGwDiAQAYAAgJmhfDGwDiAQAAAA==.Morgañya:BAAALgAECgYJEwABLgAECggJMQAYAJoXAA==.Morgul:BAAALgAECgcJEgAAAA==.Morphz:BAAALgAECgQJBAAAAA==.Morrtis:BAAALgADCgQJBAAAAA==.Mortics:BAAALgAECgEJAQAAAA==.Mortishaa:BAABLgAECn8dAAIVAAcJJRD2CwB6AQAVAAcJJRD2CwB6AQAAAA==.Moundask:BAAALgADCgEJAgAAAA==.',
Ms='Mseow:BAAALgADCgYJCAAAAA==.',
Mu='Muchplague:BAABLgAECn8hAAIJAAgJ3BGCQAB7AQAJAAgJ3BGCQAB7AQAAAA==.Muddbut:BAAALgAECgEJAQAAAA==.Muller:BAAALgADCgYJBgAAAA==.Mutagenooze:BAAALgADCgUJDgAAAA==.Muwoo:BAAALgAECgYJDQAAAA==.',
Mw='Mweow:BAAALgADCgUJBQAAAA==.',
My='Mycowgoesmoo:BAAALgADCgkJDwAAAA==.Mynnu:BAAALgAECgQJBgAAAA==.Mynte:BAAALgADCgUJBQABLgAECgkJGwADAL8NAA==.Mythundenan:BAAALgAECgcJBwAAAA==.',
Na='Nachoproblem:BAAALgAECgEJAQAAAA==.Naeuh:BAABLgAECn8iAAIOAAgJVhJVLgCVAQAOAAgJVhJVLgCVAQAAAA==.Nagiana:BAAALgADCgYJBgAAAA==.Nahadotha:BAAALgAECgEJAwAAAA==.Nanako:BAAALgAECgMJAwAAAA==.Nance:BAACLgAFFH8KAAIXAAQJohIWJgAmAQAXAAQJohIWJgAmAQAuAAQKfyQAAhcACAmzIe0QAPMCABcACAmzIe0QAPMCAAAA.Narasong:BAAALgAECgEJAQAAAA==.Naraysta:BAABLgAECn8xAAQJAAkJkxfgRwAcAgAJAAkJAhfgRwAcAgAWAAYJjRXgEwA5AQAkAAEJ2RLQFQA2AAAAAA==.Nasan:BAAALgAECgQJBAAAAA==.Nathette:BAAALgAECgcJCgAAAA==.Nautprepared:BAAALgADCgkJFgAAAA==.',
Ne='Necrodancer:BAAALgAECgkJCQAAAA==.Necrofêêlya:BAAALgADCgEJAQAAAA==.Neeck:BAAALgAECgEJAQAAAA==.Needhealz:BAABLgAECn8nAAIRAAgJHR1tCwBcAgARAAgJHR1tCwBcAgAAAA==.Neildasstysn:BAACLgAFFH8FAAIlAAMJgwZdEQDjAAAlAAMJgwZdEQDjAAAuAAQKfxkAAiUACAlvGR0JAFACACUACAlvGR0JAFACAAAA.Nemezyz:BAAALgADCgYJBgAAAA==.Nephey:BAAALgADCgUJBgAAAA==.Neveya:BAAALgADCgcJDwAAAA==.Newwing:BAAALgADCggJDQAAAA==.',
Ni='Niavka:BAAALgADCgUJBQAAAA==.Nickeld:BAABLgAECn8eAAMPAAgJ7ReKBwCJAQAKAAgJexJ4PgCsAQAPAAYJpxSKBwCJAQAAAA==.Nickerfritz:BAAALgAECgUJCgAAAA==.Nickhy:BAAALgAECgMJAwAAAA==.Nietherme:BAAALgAECgYJDwAAAA==.Nihildicits:BAAALgAECgIJAgAAAA==.Niverrø:BAAALgAECgYJDwABLgAECgkJLAAeAOAfAA==.',
No='Noahmedlock:BAAALgAECgQJBAAAAA==.Noblefiend:BAAALgADCgMJAwAAAA==.Nodnardd:BAAALgAECgYJEAAAAA==.Nofoamlatte:BAAALgAECgMJAwABLgAECgkJKgAJAKUYAA==.Noirwyn:BAAALgADCgYJBgAAAA==.Nokomu:BAAALgADCgcJDAAAAA==.Noliee:BAAALgAECgIJBQAAAA==.Noluckjay:BAAALgADCgcJBwAAAA==.Noodie:BAAALgAECgIJAgABLgAFFAIJAgABAAAAAA==.Noogra:BAAALgADCgEJAQAAAA==.Norinithedra:BAAALgAECgQJBgAAAA==.Nossavaria:BAAALgADCgEJAQAAAA==.Noxis:BAAALgAECgQJBwAAAA==.',
Nu='Nulva:BAAALgADCgYJDgAAAA==.',
Ny='Nyadris:BAAALgADCgkJCQAAAA==.Nyagosa:BAABLgAECn8VAAIZAAkJKxRmGQARAgAZAAkJKxRmGQARAgAAAA==.Nyalore:BAAALgAECgkJEAAAAA==.Nymesys:BAAALgADCgYJCQAAAA==.',
Oa='Oakencrush:BAAALgADCgEJAQAAAA==.',
Ol='Oldmanjankin:BAAALgAECgUJCAAAAA==.Olia:BAAALgADCgIJAgAAAA==.Oluhegar:BAAALgADCgIJAgAAAA==.',
Om='Omnimon:BAAALgADCgEJAQABLgAECggJHQAQAIElAA==.',
Oq='Oquaellii:BAAALgAECgQJCgAAAA==.',
Or='Oralen:BAACLgAFFH8OAAIRAAUJMx4CBQDTAQARAAUJMx4CBQDTAQAuAAQKfxsAAhEACAmFGPcgABQCABEACAmFGPcgABQCAAAA.Orangedorito:BAAALgAECgQJBAAAAA==.Orcthas:BAAALgAECgQJBAABLgAFFAYJFgAMADcgAA==.Ordola:BAABLgAECn8ZAAIEAAcJ8ByvFwACAgAEAAcJ8ByvFwACAgAAAA==.Orlorian:BAAALgAECgEJAQAAAA==.',
Ot='Othneil:BAAALgADCgMJAwAAAA==.',
Ou='Outtlawz:BAAALgADCgEJAQAAAA==.',
Ov='Overloader:BAABLgAECn8rAAIYAAgJfCBuEwAhAgAYAAgJfCBuEwAhAgAAAA==.',
Pa='Painreaver:BAEBLgAECn9CAAIYAAkJsRr1CQCJAgAYAAkJsRr1CQCJAgAAAA==.Palahang:BAAALgAECgIJAgAAAA==.Palimax:BAAALgAECgEJAgAAAA==.Pallyaxe:BAAALgAECgUJDQABLgAECgkJLgAKAI4YAA==.Pallygank:BAAALgADCgIJAgAAAA==.Pallysin:BAAALgADCgMJBAAAAA==.Pamn:BAAALgADCgUJBQAAAA==.Panae:BAAALgADCgIJAgABLgAECgcJDAABAAAAAA==.Pancandy:BAAALgAECgYJCgAAAA==.Paneer:BAAALgAECgQJCQAAAA==.Parryhottër:BAAALgAECgQJBAAAAA==.Pascel:BAAALgAECgYJDwAAAA==.',
Pe='Pebbletoe:BAAALgADCgUJBwAAAA==.Penta:BAAALgAECgMJAwAAAA==.Percgripper:BAAALgAECgUJBAABLgAECgcJEwABAAAAAA==.Percivis:BAAALgADCgEJAQAAAA==.Perida:BAAALgAECgEJAwAAAA==.Peronarth:BAAALgADCgIJAgAAAA==.Peruano:BAAALgAECgcJCgAAAA==.Petforheals:BAAALgAECgcJCQAAAA==.',
Ph='Phouy:BAAALgADCgIJAgAAAA==.Phyo:BAAALgAECgEJAQAAAA==.Phyoo:BAAALgAECgUJEwAAAA==.',
Pi='Picken:BAEALgADCgUJBQABLgAFFAMJCgAMAEIgAA==.Pinndrop:BAAALgADCgIJAgAAAA==.',
Pk='Pkrippa:BAAALgADCgcJCAAAAA==.',
Pl='Plu:BAABLgAECn8YAAIdAAYJEwoKHAD6AAAdAAYJEwoKHAD6AAAAAA==.',
Po='Pocahöntas:BAAALgADCgkJDgAAAA==.Pogie:BAAALgADCgUJBQAAAA==.Polkagay:BAAALgAECgcJBQAAAA==.Portick:BAAALgAECgQJCwAAAA==.Posttmasterz:BAAALgAECgQJBAAAAA==.',
Pr='Prittykitty:BAAALgADCgcJDQAAAA==.Protrunkey:BAAALgAECgEJAQAAAA==.Provolonie:BAABLgAECn8XAAIOAAYJLwgMawAnAQAOAAYJLwgMawAnAQAAAA==.',
Pu='Puppiboi:BAAALgADCggJCQAAAA==.Puritos:BAAALgAECgQJDQAAAA==.Pushti:BAAALgADCgYJBgAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrista:BAABLgAECn8cAAIOAAYJvhjKNgByAQAOAAYJvhjKNgByAQAAAA==.',
Qe='Qeikli:BAAALgADCgEJAgAAAA==.',
Qo='Qortethhunt:BAAALgAECgEJAQAAAA==.',
Qt='Qthunter:BAAALgADCgMJAwAAAA==.',
Qu='Quackapls:BAAALgAECgYJCgAAAA==.Quaratus:BAAALgAECgUJBQAAAA==.',
Ra='Raendarth:BAABLgAECn8VAAILAAYJ6g43CQA7AQALAAYJ6g43CQA7AQAAAA==.Rageslave:BAAALgAECgkJDwAAAA==.Rageth:BAABLgAECn8lAAMiAAgJCxJcBACwAQAiAAgJCxJcBACwAQAgAAIJqQjWTQBeAAAAAA==.Ragnarule:BAAALgAECgIJAgAAAA==.Ragnol:BAAALgAECgQJBQAAAA==.Rakalaag:BAEALgADCgIJAgAAAA==.Rakath:BAABLgAECn8WAAIcAAgJkQ8jIAA2AQAcAAgJkQ8jIAA2AQAAAA==.Ramchi:BAAALgAECgUJBwAAAA==.Ramlethal:BAAALgADCgEJAgAAAA==.Ramw:BAAALgAECgYJDAAAAA==.Rasmis:BAAALgAFFAIJBAAAAA==.Ravielo:BAAALgADCgQJBAAAAA==.Rawlanth:BAAALgADCgcJCQAAAA==.',
Re='Reafmon:BAAALgAECgQJCAAAAA==.Reafork:BAAALgAECgQJBQAAAA==.Reck:BAABLgAECn8YAAMGAAgJLiADBgBxAgAGAAgJGBwDBgBxAgAHAAUJoyTaMwDbAQAAAA==.Redrangerzz:BAAALgADCgUJBAAAAA==.Reduxx:BAAALgADCgIJAgAAAA==.Regulos:BAAALgAECgEJAQAAAA==.Relanni:BAAALgADCgQJBAAAAA==.Remedialtim:BAAALgADCgkJCQAAAA==.Remixtank:BAAALgADCgUJBQAAAA==.Renwick:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Reomikage:BAAALgADCgcJBwAAAA==.Reservetank:BAAALgADCgMJAwAAAA==.Retasa:BAAALgAECgQJCAAAAA==.Retwings:BAABLgAFFH8MAAIMAAMJCRpZEgASAQAMAAMJCRpZEgASAQAAAA==.Reunach:BAABLgAECn8cAAIMAAgJZQ7sQwB6AQAMAAgJZQ7sQwB6AQAAAA==.Reybekka:BAEBLgAECn8WAAIQAAgJRR32CACdAgAQAAgJRR32CACdAgAAAA==.',
Rh='Rhialto:BAAALgADCgMJAwAAAA==.Rhinegeist:BAAALgADCgEJAQAAAA==.',
Ri='Riccus:BAAALgADCgcJEQAAAA==.Rin:BAAALgAECgMJAwAAAA==.Riplee:BAAALgADCgYJBgAAAA==.Ris:BAAALgAECgEJBQAAAA==.Ritualburner:BAAALgAECgEJAQAAAA==.Riverpixie:BAAALgADCgUJDQAAAA==.',
Ro='Roachman:BAAALgAECgYJDgAAAA==.Robovac:BAAALgADCgUJCgAAAA==.Rockbrew:BAABLgAECn8WAAImAAYJlhfDGgBeAQAmAAYJlhfDGgBeAQAAAA==.Rockslice:BAAALgAECgUJBwAAAA==.Roonoa:BAAALgADCgcJBwAAAA==.Rorien:BAAALgAECgIJAgABLgAECgMJCQABAAAAAA==.Rosannas:BAAALgADCgcJDAABLgAFFAQJDAALAMQYAA==.Royallz:BAAALgADCgcJBwAAAA==.',
Ru='Ruckùs:BAABLgAECn8UAAMhAAgJiA1MGgBeAQAhAAcJdwtMGgBeAQADAAQJcQM/WQBVAAAAAA==.Rudora:BAAALgADCgcJDQAAAA==.Ruibash:BAECLgAFFH8KAAIMAAMJQiAEKgAGAQAMAAMJQiAEKgAGAQAuAAQKfzUAAgwACAkPJtkGAGMDAAwACAkPJtkGAGMDAAAA.Rule:BAAALgAECgEJAgABLgAECgYJCQABAAAAAA==.',
Ry='Ryul:BAABLgAECn8dAAImAAcJLBqIEQC4AQAmAAcJLBqIEQC4AQAAAA==.Ryuuzen:BAAALgAECgMJBAAAAA==.',
['Rê']='Rêqûiem:BAAALgAECgEJAQAAAA==.',
Sa='Sabigosa:BAAALgAECgYJCQAAAA==.Sabitha:BAABLgAFFH8JAAIhAAQJhxXpDgBYAQAhAAQJhxXpDgBYAQAAAA==.Sabpie:BAAALgADCgYJDwAAAA==.Sabrita:BAAALgAECgYJBgAAAA==.Sacredkhaos:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.Sacredknight:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.Sagoon:BAAALgADCgIJAgAAAA==.Saguun:BAAALgADCgUJBQAAAA==.Saikoumaster:BAABLgAECn8dAAIJAAcJhwt2WQA0AQAJAAcJhwt2WQA0AQAAAA==.Saje:BAABLgAECn8jAAMhAAgJXSCqAwDtAgAhAAgJXSCqAwDtAgAZAAEJfARSggAvAAABLgAECggJHQAQAIElAA==.Sakebomb:BAAALgADCgYJDQAAAA==.Sallanarya:BAAALgAECgUJCAAAAA==.Samwho:BAAALgADCgYJDAAAAA==.Sarajean:BAAALgAECgcJAgAAAA==.Sareythor:BAAALgADCgYJCAAAAA==.Sargeteeter:BAAALgADCgMJAwAAAA==.Satanonus:BAAALgADCgUJBAAAAA==.',
Sc='Scaledoc:BAAALgAECgEJAQABLgAECgYJDQABAAAAAA==.Scarelette:BAAALgADCgYJBwAAAA==.Scarletmatch:BAABLgAECn8fAAIOAAgJlBRcNwBvAQAOAAgJlBRcNwBvAQAAAA==.Scarwitch:BAAALgADCgIJAgAAAA==.Schamane:BAAALgAECgMJAwAAAA==.Schmedium:BAAALgADCgQJBAAAAA==.Sciamachy:BAAALgAECgMJAwAAAA==.Scotty:BAAALgAECgYJDAAAAA==.',
Se='Seer:BAAALgADCgYJBgAAAA==.Seldav:BAABLgAECn8iAAMgAAkJwxp5DwB/AgAgAAgJwxp5DwB/AgAiAAMJtxNqMgCCAAAAAA==.Selenyra:BAABLgAECn8aAAMDAAkJdgviGQBtAQADAAgJwQniGQBtAQAhAAgJ9QMNNgD0AAAAAA==.Selm:BAABLgAECn8rAAICAAkJOCVzAABDAwACAAkJOCVzAABDAwAAAA==.Selvarkes:BAAALgADCgMJAwAAAA==.Seraphrim:BAAALgAECgQJBgAAAA==.Seryne:BAAALgAECgYJEgAAAA==.Sevarg:BAAALgAECgYJDgAAAA==.Sevveruss:BAAALgAECgMJBQAAAA==.',
Sh='Shadowfury:BAAALgAECgQJDAAAAA==.Shadowjuve:BAAALgAECgkJCwAAAA==.Shadowsnout:BAAALgAECgEJAQAAAA==.Shalandrov:BAAALgADCgEJAQAAAA==.Shameless:BAAALgADCgkJEAAAAA==.Sharco:BAABLgAECn8wAAIKAAkJhBMaIQAlAgAKAAkJhBMaIQAlAgAAAA==.Sharkeshia:BAAALgAFFAIJAgAAAA==.Shawarmafury:BAABLgAECn8sAAIOAAkJSiUCAQBaAwAOAAkJSiUCAQBaAwAAAA==.Shaydens:BAAALgADCgcJBwAAAA==.Sheedem:BAAALgADCggJEgABLgAECgYJFQAJACYXAA==.Sherrizzahh:BAAALgAECgEJAQAAAA==.Shifhappens:BAAALgAECgEJAQAAAA==.Shinshots:BAAALgAECgUJBQAAAA==.Shinyzig:BAAALgAECgQJBAAAAA==.Shirun:BAAALgADCgcJBwAAAA==.Shockadinn:BAABLgAECn8kAAMRAAgJFBzPFQBiAgARAAcJhh7PFQBiAgAMAAcJdBcbmwBIAQAAAA==.Shooshmael:BAAALgAECgIJBAABLgAECgYJDAABAAAAAA==.Shujáa:BAABLgAECn8eAAIJAAgJBx2tFwA/AgAJAAgJBx2tFwA/AgAAAA==.Shékinah:BAAALgAECgcJEwAAAA==.',
Si='Sickbones:BAAALgAECgYJCwABLgAFFAIJBgANACcJAA==.Sighmon:BAAALgADCgIJAgAAAA==.Silvoryn:BAAALgADCgcJBwAAAA==.Silvrshh:BAAALgAECgcJDAAAAA==.Silvrsoil:BAAALgAECgEJAQAAAA==.Sinba:BAAALgAECgEJAgABLgAECggJJwAZAIEdAA==.Sinsister:BAAALgAECgYJCwAAAA==.Sinthein:BAAALgAFFAEJAQABLgAFFAEJAQABAAAAAA==.',
Sk='Skadfather:BAABLgAECn8cAAMRAAcJ8iC4EACMAgARAAcJ8iC4EACMAgAMAAEJ4AzwCQEzAAAAAA==.Skellyheals:BAAALgAECgQJCgAAAA==.Skorpekh:BAAALgADCgcJCwAAAA==.Skuumfein:BAAALgAECgYJEAAAAA==.Skydeuxlight:BAAALgAECgQJDQAAAA==.',
Sl='Slamdingo:BAAALgADCgUJBQAAAA==.Sleepingsun:BAABLgAECn8ZAAMbAAYJTBzOHQDWAQAbAAYJTBzOHQDWAQAcAAIJsQhvcgBXAAAAAA==.Sloppyspikes:BAAALgAECggJDQAAAA==.',
Sm='Smakm:BAAALgAECgQJBgAAAA==.Smeshh:BAAALgAECgQJBAAAAA==.Smidgenn:BAAALgAECgUJBQAAAA==.Smokyblast:BAAALgAECgMJBgAAAA==.',
Sn='Snailtrails:BAAALgAECgEJAQAAAA==.Snowball:BAABLgAECn8jAAIKAAgJ0gVoZQBGAQAKAAgJ0gVoZQBGAQAAAA==.',
So='Solemn:BAAALgADCgYJBgAAAA==.Solenya:BAAALgAECgUJCgABLgAECggJEwABAAAAAA==.Sonyskvirtik:BAAALgADCgYJBgAAAA==.Soozie:BAAALgAECgIJBAAAAA==.Sophiez:BAAALgADCgEJAQAAAA==.Sorvara:BAAALgADCgcJBwAAAA==.Sotan:BAABLgAECn8eAAIOAAgJtRqzGgD+AQAOAAgJtRqzGgD+AQAAAA==.Soulforge:BAAALgADCggJCQAAAA==.',
Sp='Sparowprince:BAACLgAFFH8KAAIMAAUJMRAUHQA5AQAMAAUJMRAUHQA5AQAuAAQKfyYAAgwACQlxIPUPAA8DAAwACQlxIPUPAA8DAAAA.Sparxs:BAAALgADCgUJBQAAAA==.Spazs:BAAALgADCgUJCAAAAA==.Spectraleye:BAACLgAFFH8FAAIYAAMJrCQ/GABJAQAYAAMJrCQ/GABJAQAuAAQKfx8AAhgACAn/IYgGAMACABgACAn/IYgGAMACAAAA.Spikanal:BAAALgAFFAMJAwAAAA==.Spookahuntes:BAAALgAECgQJCAAAAA==.Sproocherlou:BAABLgAECn8iAAIMAAgJQR5hEQBvAgAMAAgJQR5hEQBvAgAAAA==.',
Sq='Squirlmaster:BAAALgADCgcJBwAAAA==.',
Ss='Ssomepally:BAAALgADCgkJCQAAAA==.',
St='Stabier:BAAALgADCgQJCQAAAA==.Standalone:BAAALgADCgYJBwAAAA==.Starstryker:BAAALgADCgEJAQAAAA==.Stashdaddy:BAAALgADCgEJAQAAAA==.Stazzch:BAAALgAECgIJBAAAAA==.Stealthzu:BAABLgAECn8kAAIeAAgJvxCqDQDIAQAeAAgJvxCqDQDIAQAAAA==.Steezya:BAAALgAECgIJAwAAAA==.Stegulos:BAAALgAFFAEJAQAAAA==.Stellaatrix:BAAALgAECgEJAQAAAA==.Stellarum:BAAALgAECgEJAwAAAA==.Stonedemon:BAAALgAECgYJBgABLgAFFAUJCgAMADEQAA==.Stoneocean:BAAALgAECgEJAQAAAA==.Stormblessd:BAAALgAECgUJBgAAAA==.Stormsy:BAAALgAECgIJAgABLgAECggJJwAZADkdAA==.Stormykitty:BAABLgAECn8nAAIZAAgJOR0RBwCEAgAZAAgJOR0RBwCEAgAAAA==.Strangefate:BAAALgADCgYJBwAAAA==.Strawhatglaz:BAAALgAECgYJCwABLgAECgUJBgABAAAAAA==.Strikermain:BAAALgAECgQJBAAAAA==.Stronkchills:BAAALgADCgEJAQAAAA==.Sturtza:BAABLgAECn8aAAIOAAkJzhcsFQCOAgAOAAkJzhcsFQCOAgAAAA==.Sturtzam:BAAALgAECgYJBgABLgAECgkJGgAOAM4XAA==.',
Su='Succubussy:BAAALgAECgEJAQAAAA==.Sungayan:BAAALgAECgEJAgAAAA==.Suun:BAABLgAECn8UAAIMAAcJNBNWTQBeAQAMAAcJNBNWTQBeAQAAAA==.',
Sv='Sveella:BAAALgAECgIJAgAAAA==.',
Sw='Swoley:BAABLgAECn8lAAMRAAgJmyLhBwCYAgARAAgJmyLhBwCYAgAMAAEJCgi/DAExAAAAAA==.',
Sy='Sycotix:BAAALgAECgcJCAAAAA==.Syndraza:BAAALgADCgkJEgAAAA==.Synsei:BAAALgAECgQJBQAAAA==.Syyn:BAAALgADCgYJBwAAAA==.',
Ta='Tagobeets:BAABLgAECn8XAAIKAAgJ/QTNcwApAQAKAAgJ/QTNcwApAQAAAA==.Tahia:BAAALgAECgEJAQAAAA==.Taimaishoo:BAAALgADCgYJEQAAAA==.Talendil:BAAALgAECgcJBwAAAA==.Talisaie:BAACLgAFFH8HAAMXAAQJ2hQEEwBQAQAXAAQJGBMEEwBQAQAUAAIJ6QtxEwBQAAAuAAQKfyIAAxQACQlZI+MDAKsCABQABwnhIuMDAKsCABcACAlQIN8pAGkCAAAA.Taln:BAAALgAECgIJAgAAAA==.Talohha:BAAALgADCgcJBwAAAA==.Talzitalet:BAAALgADCgYJBgAAAA==.Tandor:BAABLgAECn8UAAIMAAYJ2hOSjQBgAQAMAAYJ2hOSjQBgAQAAAA==.Taolu:BAAALgAECgIJAgABLgAECggJIQAJANwRAA==.Tarancalime:BAAALgAECgYJEAAAAA==.Tarandris:BAAALgAECgUJBQAAAA==.Taron:BAABLgAECn8VAAIHAAYJIhwqFwCuAQAHAAYJIhwqFwCuAQAAAA==.Tazenazal:BAEALgAECgYJEAAAAA==.',
Th='Thatkindaorc:BAAALgADCgkJCQAAAA==.Thegreatestt:BAAALgADCgIJAgAAAA==.Thehumanatee:BAABLgAECn8cAAMcAAkJgB25EwB2AgAcAAkJgB25EwB2AgAbAAYJIwhRTQDeAAAAAA==.Theriondread:BAABLgAECn8WAAIbAAcJwhSQNgA9AQAbAAcJwhSQNgA9AQAAAA==.Theunholyone:BAAALgAECgYJBgAAAA==.Thicky:BAAALgADCgMJAwAAAA==.Thiquems:BAAALgAECgcJEQAAAA==.Thruoessos:BAAALgADCgYJBgAAAA==.Thuaddar:BAAALgAECgMJAwAAAA==.Thunderanvil:BAAALgADCgYJBgAAAA==.Thunderpaws:BAAALgADCgUJBQAAAA==.Thyphlo:BAAALgAECgcJEQAAAA==.',
Ti='Tiagrimtotem:BAAALgADCgYJBgAAAA==.Ticklemedady:BAEBLgAECn8YAAIMAAYJWQd5gwDlAAAMAAYJWQd5gwDlAAABLgAECgkJQgAYALEaAA==.Tiltedup:BAABLgAECn8wAAIKAAkJVx5XCQDfAgAKAAkJVx5XCQDfAgAAAA==.Tinkerßell:BAAALgAECgYJDwABLgAECggJJwAZADkdAA==.Tirich:BAAALgADCgkJCwABLgAFFAEJAQABAAAAAA==.Tirmanator:BAAALgADCgIJAgAAAA==.',
To='Toshi:BAABLgAECn8ZAAIXAAcJ9QQ0aQD6AAAXAAcJ9QQ0aQD6AAAAAA==.Totemstitch:BAAALgADCgMJAwAAAA==.Touchyfeely:BAABLgAECn8bAAIDAAkJvw1ZIgDEAQADAAkJvw1ZIgDEAQAAAA==.',
Tr='Trashgo:BAAALgADCgIJAgAAAA==.Trashgu:BAAALgAECgEJAQAAAA==.Trentonii:BAAALgADCgEJAQABLgAECgMJAwABAAAAAA==.Trolhznoname:BAAALgADCgkJEAAAAA==.',
Tt='Ttmina:BAAALgADCgUJBQAAAA==.',
Tu='Tufani:BAAALgADCgUJBQAAAA==.Tulark:BAAALgADCgIJAwAAAA==.Tullyy:BAAALgAECgMJAwAAAA==.Tums:BAABLgAECn8ZAAIeAAgJEhiHBwAxAgAeAAgJEhiHBwAxAgAAAA==.Turkatron:BAAALgAECgMJAwAAAA==.Tusaditty:BAAALgADCgYJBAAAAA==.',
Tw='Twicetwice:BAAALgAECggJDgAAAA==.Twirls:BAAALgAECggJEQAAAA==.Twotwothree:BAAALgAECgcJEwAAAA==.',
Ty='Tylenill:BAABLgAECn8WAAIFAAgJlBdtDgDSAQAFAAgJlBdtDgDSAQAAAA==.Typhoíd:BAAALgAECgEJAgAAAA==.Tyranical:BAAALgAECgYJDQAAAA==.',
Ul='Ultimatechad:BAAALgAECgIJAgABLgAECgkJIgAgAMMaAA==.Ulzulwrath:BAAALgADCgUJBgAAAA==.',
Un='Uncanny:BAAALgAECgMJAwAAAA==.',
Ur='Ursoman:BAAALgAECgEJAQAAAA==.Urtle:BAAALgAECgYJEwAAAA==.',
Us='Uselece:BAAALgAECgYJEgAAAA==.',
Uz='Uzainbolt:BAAALgAECgIJAgAAAA==.',
Va='Vaboz:BAAALgADCgEJAQAAAA==.Valeena:BAAALgAECggJEAAAAA==.Valoric:BAAALgADCgUJBQAAAA==.Valvalon:BAABLgAECn8YAAIKAAgJZxNkQwCdAQAKAAgJZxNkQwCdAQAAAA==.Vandorian:BAAALgAECgQJDAAAAA==.Vannin:BAAALgADCgQJBAAAAA==.Vardá:BAAALgADCgEJAQAAAA==.',
Ve='Veelaria:BAAALgAECgcJEAAAAA==.Velarisaa:BAAALgADCgcJEQAAAA==.Veledaa:BAAALgAECgUJCgABLgAECggJDgABAAAAAA==.Velinddrel:BAAALgAECgEJAQAAAA==.Verena:BAAALgADCgMJAwAAAA==.Vestige:BAAALgAECgEJAQAAAA==.',
Vi='Vicalaus:BAAALgAECgUJBwABLgAECggJGwAYAAsWAA==.View:BAAALgADCgcJBwAAAA==.Vikingxx:BAAALgADCgEJAQAAAA==.Vilified:BAABLgAECn8ZAAMZAAYJ+hx0EADlAQAZAAYJ+hx0EADlAQADAAIJPQJdWwAiAAAAAA==.Vincelex:BAAALgADCgMJBgAAAA==.Vincerer:BAAALgAECgQJBwAAAA==.Vitros:BAAALgADCgcJBwABLgAECgMJAwABAAAAAA==.',
Vl='Vladymir:BAAALgAECgMJAwAAAA==.',
Vo='Voidbren:BAAALgAECgcJEwAAAA==.Voidescapee:BAAALgAECgMJBQAAAA==.Voidpapi:BAAALgAECgEJAQAAAA==.Voidsav:BAAALgADCgMJBQAAAA==.Voidscarred:BAAALgADCggJDgAAAA==.Voidwitch:BAABLgAECn8eAAIUAAgJFSK5AAC8AgAUAAgJFSK5AAC8AgAAAA==.',
Vy='Vylandra:BAAALgADCgYJBgAAAA==.',
Wa='Wagar:BAAALgAECgEJAQAAAA==.Watchmecook:BAAALgAECgYJCwAAAA==.',
We='Webbfury:BAABLgAECn8XAAIHAAcJkBv3GwBtAgAHAAcJkBv3GwBtAgAAAA==.Wetpug:BAAALgAECgEJAQAAAA==.',
Wh='Wheremytotem:BAAALgADCgYJBgABLgAECggJJwARAB0dAA==.',
Wi='Wiidge:BAABLgAECn8VAAIVAAcJUhDTBQBiAQAVAAcJUhDTBQBiAQAAAA==.Wildretnuh:BAACLgAFFH8NAAIYAAQJaA/nKQAKAQAYAAQJaA/nKQAKAQAuAAQKfyUAAhgACAnKF+pDAOQBABgACAnKF+pDAOQBAAAA.Windiwithani:BAABLgAECn8kAAIfAAkJURSzCQDYAQAfAAkJURSzCQDYAQAAAA==.Wiou:BAAALgADCgMJAwAAAA==.',
Wo='Wocky:BAAALgAECgYJDgAAAA==.Worgath:BAAALgAECgUJCgAAAA==.Worldcrafter:BAABLgAECn8YAAQhAAYJkRyKDgDoAQAhAAYJ3huKDgDoAQAZAAUJRRlTNQBoAQADAAIJ4gqdQQBtAAAAAA==.',
Wr='Wrapta:BAAALgADCgkJDwABLgAECgEJAQABAAAAAA==.Wrathofdawn:BAAALgAECgEJAgAAAA==.',
Xa='Xaalai:BAAALgADCgUJBwAAAA==.Xantry:BAACLgAFFH8WAAMMAAYJNyASAwDkAQAMAAYJECASAwDkAQANAAIJ7Bb6AwCdAAAuAAQKfyIAAgwACQkGJGMIAFADAAwACQkGJGMIAFADAAAA.',
Xe='Xenons:BAAALgADCgYJBgAAAA==.',
Xi='Xillow:BAAALgAECgEJAQAAAA==.',
Xs='Xsirdrunk:BAAALgADCggJDwAAAA==.',
Xy='Xylin:BAAALgAECgMJAwAAAA==.Xymm:BAAALgAECgMJBAAAAA==.',
Ye='Yeastytree:BAABLgAECn8pAAIbAAkJSxvQCQCsAgAbAAkJSxvQCQCsAgAAAA==.Yellatuu:BAABLgAECn8UAAIUAAUJGA5zDQD7AAAUAAUJGA5zDQD7AAAAAA==.',
Ys='Yshlata:BAAALgADCgMJAwAAAA==.',
Za='Zanekraken:BAAALgADCgYJBgAAAA==.Zanthoss:BAAALgADCgkJFwAAAA==.Zarathea:BAAALgAECgcJBwAAAA==.',
Ze='Zella:BAAALgADCgYJCwAAAA==.Zemniss:BAAALgADCgcJBwAAAA==.Zendalis:BAAALgAECgYJCgAAAA==.Zenjay:BAAALgAECgQJBgAAAA==.Zerrikan:BAAALgADCgUJBQAAAA==.',
Zh='Zhalthir:BAAALgAECgEJAgAAAA==.',
Zi='Zilphah:BAAALgAECgUJBQAAAA==.Zimms:BAABLgAECn8gAAIFAAkJux36AwCwAgAFAAkJux36AwCwAgAAAA==.Zimmypup:BAAALgAECgIJAgABLgAECgkJIAAFALsdAA==.Zinng:BAAALgADCgYJBgABLgAECgkJIQADAB8SAA==.Zirakul:BAAALgAECgEJAQAAAA==.',
Zo='Zoeyredbird:BAAALgAECgcJEgAAAA==.Zombalorian:BAAALgADCgMJAgAAAA==.',
Zu='Zulamar:BAAALgAECgEJAQAAAA==.',
Zy='Zyenthia:BAAALgADCgYJBgAAAA==.',
['Zô']='Zôhan:BAAALgADCgQJBAAAAA==.',
['Zø']='Zøhan:BAAALgADCgYJBgAAAA==.',
['Äl']='Älcatraz:BAAALgAECgIJAgABLgAECgcJFgAbAMIUAA==.',
['Îs']='Îsh:BAAALgAECgUJBQAAAA==.',
['Ör']='Örgrim:BAACLgAFFH8VAAIMAAUJhSW3BAC9AQAMAAUJhSW3BAC9AQAuAAQKfzcAAgwACQn+JMIBAMcDAAwACQn+JMIBAMcDAAAA.',
['Ún']='Úndead:BAAALgADCgUJBQAAAA==.',
['ßa']='ßaßayaga:BAAALgADCgYJAwAAAA==.',
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

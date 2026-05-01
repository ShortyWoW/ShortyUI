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

local lookup = {'Unknown-Unknown','Druid-Guardian','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Mage-Frost','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Paladin-Holy','Shaman-Enhancement','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Devourer','Druid-Feral','Druid-Restoration','Druid-Balance','Rogue-Subtlety','Warrior-Protection','Warlock-Affliction','Evoker-Augmentation','Warlock-Destruction','DemonHunter-Havoc','Hunter-Marksmanship','Priest-Discipline','Hunter-Survival','Priest-Holy','Evoker-Devastation','Monk-Brewmaster',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Aboyton:BAAALgADCgQJBwAAAA==.',
Ac='Acheios:BAAALgAECgIJAgAAAA==.Acinas:BAAALgADCgcJCwAAAA==.Acosadora:BAAALgAECgcJBwAAAA==.',
Ad='Adhpally:BAAALgAECgIJBAABLgAECgYJEwABAAAAAA==.Adurangi:BAAALgAECgEJAQAAAA==.',
Ae='Aefarshammy:BAAALgADCgEJAQAAAA==.Aelaravia:BAAALgAECgMJAwAAAA==.Aerithorn:BAABLgAECn8WAAICAAgJIx+kBACiAgACAAgJIx+kBACiAgAAAA==.Aethereon:BAAALgADCgYJDQAAAA==.Aethora:BAAALgADCgQJBAABLgAECgYJEAABAAAAAA==.Aethoric:BAAALgAECgYJEAAAAA==.',
Ag='Agirashii:BAAALgADCgUJBwAAAA==.',
Ai='Airundies:BAAALgAECgYJBgABLgAECgkJGwADAL8NAA==.',
Ak='Akoris:BAAALgADCgYJCAABLgAECgkJGgAEABMQAA==.Akorys:BAABLgAECn8aAAMEAAkJExD9IwCTAQAEAAkJExD9IwCTAQAFAAEJOAXxiwAfAAAAAA==.',
Al='Alakuna:BAAALgADCgEJAQAAAA==.Alenci:BAAALgADCgYJCAAAAA==.Alexofor:BAAALgAECgMJAwAAAA==.Alliasterius:BAAALgADCgEJAQAAAA==.Althus:BAAALgAECgcJEAAAAA==.Alturiak:BAABLgAECn8XAAMGAAYJjRYIFgBOAQAHAAUJ1hVWVwBPAQAGAAUJkhYIFgBOAQAAAA==.Alucius:BAAALgAECgEJAwAAAA==.',
Am='Amion:BAAALgADCgMJAwAAAA==.Ammodeus:BAAALgADCgMJAwAAAA==.Amortin:BAAALgADCgUJBQAAAA==.',
An='Andarriel:BAAALgADCgUJBQAAAA==.Anguskhan:BAAALgADCgcJBwAAAA==.Anwir:BAAALgAFFAEJAQAAAA==.',
Ap='Apgravessupp:BAAALgADCgEJAQAAAA==.Aph:BAAALgADCgUJBQAAAA==.',
Aq='Aquua:BAABLgAECn8mAAIIAAkJHRR5CAAYAgAIAAkJHRR5CAAYAgAAAA==.',
Ar='Araelen:BAAALgAFFAEJAQAAAA==.Aramann:BAAALgADCgcJDAAAAA==.Archemedes:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.Arcticdps:BAAALgAECgIJAgAAAA==.Ariahn:BAABLgAECn8aAAIJAAgJvQbMOwBMAQAJAAgJvQbMOwBMAQAAAA==.Ariell:BAAALgAECgEJAQAAAA==.Ariiel:BAAALgADCggJBAABLgAECgEJAQABAAAAAA==.Arkayik:BAAALgADCgEJAQAAAA==.Arnadun:BAAALgADCgEJAQAAAA==.Arnid:BAAALgADCgcJCwAAAA==.Arphazmage:BAABLgAECn8bAAIKAAcJlAexYgAWAQAKAAcJlAexYgAWAQAAAA==.Arthimas:BAAALgAECgUJBwAAAA==.Arthuritucus:BAAALgADCgUJBQAAAA==.',
As='Aspenoa:BAAALgAECgYJDAAAAA==.Asralia:BAAALgADCgMJAwAAAA==.Astarthea:BAAALgADCgcJCAAAAA==.',
At='Athaisce:BAAALgAECgYJBQAAAA==.Athalia:BAACLgAFFH8IAAILAAMJKxVNAwDYAAALAAMJKxVNAwDYAAAuAAQKfyEAAgsACQm1IWcBABsDAAsACQm1IWcBABsDAAAA.Atlasien:BAABLgAECn8WAAMMAAgJURW8KgCXAQAMAAcJexe8KgCXAQANAAIJNQi9OABdAAAAAA==.',
Au='Aug:BAAALgAECgYJCwAAAA==.Augiey:BAAALgAECgQJAQAAAA==.Aulayia:BAAALgAECgIJCAAAAA==.Aurellea:BAAALgADCggJEAAAAA==.Auroraplague:BAAALgAECgcJBwAAAA==.',
Av='Avex:BAABLgAECn8tAAIOAAgJvyBDDAA/AgAOAAgJvyBDDAA/AgAAAA==.',
Aw='Awentamis:BAAALgADCgEJAQAAAA==.Awetysmz:BAAALgAECgEJAQAAAA==.',
Ax='Axeboom:BAAALgADCgUJBQABLgAECgkJJwAKAIoYAA==.Axelock:BAAALgADCgYJBgABLgAECgkJJwAKAIoYAA==.Axemage:BAABLgAECn8nAAMKAAkJihgkDQB5AgAKAAkJihgkDQB5AgAPAAMJPgy/EQCnAAAAAA==.Axeom:BAABLgAECn8tAAMQAAkJDRGyKgDiAQAQAAkJDRGyKgDiAQAIAAYJowmzJgDwAAAAAA==.Axeshammy:BAAALgAECgUJBgABLgAECgkJJwAKAIoYAA==.',
Ay='Ayanna:BAAALgADCgQJBAAAAA==.',
Az='Azazin:BAAALgADCgUJBQAAAA==.Azendethen:BAAALgAECgEJAQAAAA==.Azmodan:BAAALgADCgYJBgAAAA==.Azurewynith:BAAALgADCgYJBgAAAA==.Azzclappius:BAAALgAECgYJCgAAAA==.',
Ba='Badragon:BAAALgAECgYJCgAAAA==.Baelfang:BAAALgADCgYJBwAAAA==.Baelgrim:BAAALgAECgEJAQAAAA==.Bagu:BAABLgAECn8jAAMMAAgJFhrwUADuAQAMAAcJQBjwUADuAQARAAgJ1AR4HgBVAQAAAA==.Bahn:BAAALgAECgEJAQABLgAFFAIJAwABAAAAAA==.Bajaladin:BAAALgADCgQJAQAAAA==.Bambey:BAAALgADCgMJAwAAAA==.Bandanirn:BAAALgAECgEJAgAAAA==.Bandït:BAAALgAECgQJAwAAAA==.Bangki:BAAALgADCgMJBAAAAA==.Barometer:BAAALgAECgIJAgAAAA==.Bast:BAAALgAECgQJBgABLgAECgkJDAABAAAAAA==.',
Bb='Bbqchips:BAAALgADCgQJBQAAAA==.',
Bc='Bchamp:BAABLgAECn8XAAMSAAYJfhLmEwB7AQASAAYJfhLmEwB7AQAQAAQJfxLEOgDGAAAAAA==.',
Be='Beamsy:BAAALgADCgkJEAABLgAECggJJwAKALshAA==.Beansoup:BAAALgADCgMJAwAAAA==.Beefmeister:BAABLgAECn8WAAIHAAcJMxEuGABvAQAHAAcJMxEuGABvAQAAAA==.Belamorte:BAAALgAECgEJAQAAAA==.Beliala:BAAALgADCgkJGQAAAA==.Belveth:BAAALgADCgEJAQAAAA==.Benwins:BAAALgAECgYJDwAAAA==.Bertoxxulous:BAAALgADCgIJAgAAAA==.Besus:BAAALgADCgUJCwAAAA==.Beyonddeath:BAAALgADCggJCAAAAA==.',
Bh='Bho:BAAALgADCgYJDAAAAA==.',
Bi='Biffedit:BAAALgAECgYJEAAAAA==.Bisholoyd:BAAALgAECgcJEgAAAA==.Bitshift:BAAALgAECgYJDAAAAA==.Bizoune:BAAALgADCgYJBwAAAA==.',
Bl='Blackwing:BAAALgAECgYJCQAAAA==.Blastoise:BAABLgAECn8ZAAMTAAgJZR7ZBwCqAgATAAgJAh7ZBwCqAgAJAAEJ2BfAGAFDAAAAAA==.Blathian:BAAALgAECggJDAAAAA==.Blazakin:BAAALgAECgYJCgAAAA==.Blooms:BAAALgADCgUJBQABLgAECgQJBAABAAAAAA==.Bluntsmasta:BAAALgADCgkJEwAAAA==.Blupe:BAAALgADCgkJFAAAAA==.Blutang:BAAALgAECgYJBgAAAA==.Bløøms:BAAALgADCgcJBwABLgAECgQJBAABAAAAAA==.',
Bo='Boaster:BAAALgADCgEJAQAAAA==.Bobadu:BAAALgAECgEJAQAAAA==.Bodhmall:BAAALgAECgYJCgAAAA==.Bongwater:BAAALgAECgIJBAAAAA==.Booktok:BAAALgAECgEJAgAAAA==.Boombóx:BAAALgADCgkJDAABLgAECggJJwAUADYiAA==.Boome:BAAALgAECgcJCwABLgAFFAMJCAALACsVAA==.Boonk:BAAALgADCgEJAQAAAA==.Boop:BAAALgADCgYJCQAAAA==.Bootydew:BAAALgAECgQJBAAAAA==.Bootysama:BAAALgADCgkJHAABLgAECgQJBAABAAAAAA==.Boris:BAAALgADCgYJBgAAAA==.Borrax:BAAALgAECgYJCQAAAA==.Borthos:BAABLgAECn8YAAIVAAkJqx2KBACgAgAVAAkJqx2KBACgAgAAAA==.',
Br='Braetorius:BAAALgAECgYJBgAAAA==.Bretalea:BAAALgADCgcJBwAAAA==.Brewsli:BAAALgADCgQJBAAAAA==.Brickinkeys:BAAALgAECgYJDAABLgAECgcJBwABAAAAAA==.Brynnix:BAAALgADCgUJDAAAAA==.',
Bu='Bugfishleg:BAAALgADCgcJEQAAAA==.Buttardrolls:BAAALgADCgQJBAAAAA==.',
By='Byblethumper:BAAALgADCgEJAQAAAA==.',
['Bà']='Bàne:BAAALgAECgMJAwAAAA==.',
Ca='Caadra:BAAALgADCgUJBQAAAA==.Caarny:BAAALgAECgYJDQAAAA==.Cactusjack:BAAALgAECgYJDQAAAA==.Caimie:BAAALgAECgMJAwAAAA==.Caiste:BAAALgAECgEJAQAAAA==.Camel:BAAALgADCgMJAwAAAA==.Candez:BAAALgAECgYJBgAAAA==.Canfar:BAAALgAECgUJDQAAAA==.Cassiaan:BAAALgADCgIJAgAAAA==.Catalog:BAAALgAECgQJBgAAAA==.Cayiane:BAAALgAECggJDQAAAA==.Caylavibes:BAAALgAECgYJDQAAAA==.',
Ce='Cebola:BAAALgAECgYJEAAAAA==.Cerbaderp:BAAALgAECgMJAwAAAA==.',
Ch='Chackyjan:BAAALgAECgUJBQAAAA==.Chameleos:BAAALgADCgMJAwAAAA==.Chasechases:BAABLgAECn8hAAUWAAcJKAz+CQBFAQAWAAcJKAz+CQBFAQAXAAIJDwbRvQBLAAACAAEJFQwfIQAlAAAYAAIJsQKLTwAfAAAAAA==.Chazyy:BAAALgAECggJEgAAAA==.Cheetasista:BAAALgADCgMJAwAAAA==.Cherry:BAAALgAECgcJDAAAAA==.Chibiusaa:BAAALgAECgMJAwAAAA==.Chiechan:BAAALgADCgMJAwAAAA==.Chimubai:BAAALgAECgYJEgAAAA==.Chokano:BAAALgADCgcJCgAAAA==.Chokeagoat:BAAALgADCgUJBQAAAA==.Chonker:BAAALgAECgEJAQAAAA==.Chor:BAAALgAFFAIJAwAAAA==.Christinei:BAAALgADCgUJBQAAAA==.Chull:BAAALgAECgMJBAAAAA==.',
Ci='Cinderkai:BAAALgADCgQJBAAAAA==.Cinemabunny:BAAALgAECgYJCAAAAA==.Circusfreak:BAAALgAECgcJDwAAAA==.',
Cl='Classified:BAAALgAECgEJAQAAAA==.Cleyl:BAAALgAECgYJDgAAAA==.Clohhe:BAAALgAECgQJCAAAAA==.',
Co='Cokeftw:BAAALgAECgMJBAAAAA==.Coman:BAABLgAECn8pAAMQAAgJQB2mBwBxAgAQAAgJQB2mBwBxAgAIAAUJTxNsJwDrAAAAAA==.Consecrated:BAAALgAECgcJAQAAAA==.Cosmochopper:BAABLgAECn8cAAIFAAcJECJJDQCmAgAFAAcJECJJDQCmAgAAAA==.',
Cq='Cq:BAABLgAECn8jAAIVAAgJNhqCNQAiAgAVAAgJNhqCNQAiAgAAAA==.',
Cr='Cremebrule:BAAALgAECgEJAgAAAA==.Cremesodax:BAABLgAECn8UAAIMAAYJ7Q5NnQBEAQAMAAYJ7Q5NnQBEAQAAAA==.Cringeknight:BAAALgAECgcJEQAAAA==.Critjutsu:BAABLgAECn8eAAIEAAgJzCGdBACRAgAEAAgJzCGdBACRAgAAAA==.Croces:BAAALgAECgUJEQABLgAFFAEJAQABAAAAAA==.Crushleaf:BAAALgADCgMJAwAAAA==.',
Cu='Cuppanoods:BAAALgADCgYJCgAAAA==.',
Cy='Cyndra:BAAALgAECgQJCQAAAA==.',
Da='Dadonut:BAAALgAECgcJDQAAAA==.Daemonspawnn:BAAALgADCgIJAgAAAA==.Dalthyriian:BAABLgAECn8hAAIVAAYJcBtJIwBgAQAVAAYJcBtJIwBgAQAAAA==.Damii:BAAALgADCgYJEgAAAA==.Dandissima:BAAALgAECgMJAwAAAA==.Danny:BAAALgADCgEJAQAAAA==.Dargonbref:BAAALgADCgUJBQABLgAECggJIQAJANwRAA==.Darjen:BAAALgAECgcJCgAAAA==.Darkjestêr:BAAALgAECgIJAgAAAA==.Darlough:BAAALgADCgQJBAAAAA==.Darthra:BAAALgAECgMJBQAAAA==.Darthsteak:BAAALgADCgMJAwAAAA==.Dasblur:BAABLgAECn8ZAAIVAAgJNhvyLQBFAgAVAAgJNhvyLQBFAgAAAA==.Dawncygnu:BAAALgADCgUJBQAAAA==.',
Dc='Dcash:BAABLgAECn8iAAIMAAYJthLDUAAbAQAMAAYJthLDUAAbAQAAAA==.Dcashcrafter:BAAALgADCgMJAwAAAA==.',
De='Deadlyarrow:BAAALgAECggJEQAAAA==.Deadsilenth:BAAALgAECgUJBwAAAA==.Deamonessa:BAAALgAECgMJAwAAAA==.Deathfang:BAAALgADCgMJAwAAAA==.Deathlyy:BAABLgAECn8iAAIZAAkJlBxrBwD7AQAZAAkJlBxrBwD7AQAAAA==.Deathtress:BAAALgADCgUJBQAAAA==.Deatlas:BAAALgAECgYJBwAAAA==.Debbydowner:BAAALgAECgYJEgAAAA==.Decado:BAAALgAECgkJDAAAAA==.Delatrin:BAAALgADCgUJBQAAAA==.Delnir:BAAALgADCgQJBwAAAA==.Demongoat:BAAALgADCgUJBgAAAA==.Demonroo:BAAALgADCgcJCgAAAA==.Denimdan:BAABLgAECn8gAAIaAAkJXBx/CACZAgAaAAkJXBx/CACZAgAAAA==.Desetaz:BAAALgADCgMJAwAAAA==.Desetren:BAAALgAECgMJAwAAAA==.Devinedrama:BAAALgAECgYJDQAAAA==.',
Dh='Dhawk:BAAALgAECgYJEgAAAA==.',
Di='Digkdug:BAAALgADCgQJCQAAAA==.Distance:BAAALgADCgcJBwAAAA==.Dizzypal:BAAALgADCgQJBQAAAA==.',
Dk='Dkalliru:BAABLgAECn8fAAMTAAkJ3RmcAwAWAgATAAkJ3RmcAwAWAgAJAAYJsQNmyADyAAAAAA==.Dkisop:BAAALgAECgEJAQAAAA==.Dkpuff:BAAALgAECgYJEgAAAA==.',
Do='Docdolittle:BAAALgAECgYJEgABLgAECgcJFAAMAFkVAA==.Docfreez:BAABLgAECn8nAAIKAAgJuyGXCgCWAgAKAAgJuyGXCgCWAgAAAA==.Docfrosty:BAABLgAECn8XAAIKAAYJgBm5jgC1AQAKAAYJgBm5jgC1AQABLgAECgcJFAAMAFkVAA==.Docragosa:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Docrighteous:BAABLgAECn8UAAIMAAcJWRXxJgCnAQAMAAcJWRXxJgCnAQAAAA==.Doctafury:BAAALgAECgQJBAABLgAECgcJFAAMAFkVAA==.Dogar:BAAALgADCgIJAgAAAA==.Doggomasta:BAAALgAECgEJAQAAAA==.Doomhamer:BAAALgADCgYJBgABLgAECgkJGAAVAKsdAA==.Doraemee:BAAALgAECgYJDAAAAA==.Doraleous:BAAALgADCgQJBAAAAA==.Doresaingk:BAAALgADCgEJAQAAAA==.Dorllian:BAAALgADCgEJAQAAAA==.',
Dr='Drablooms:BAAALgAECgQJBAAAAA==.Dracotriface:BAAALgAECgQJBAAAAA==.Drahk:BAAALgADCggJCAAAAA==.Drain:BAAALgAECgkJBAAAAA==.Dravenholy:BAAALgAECgEJAQAAAA==.Drbaobuns:BAAALgAECgYJDQABLgAECggJEAABAAAAAA==.Drboomnugget:BAAALgADCgcJBwAAAA==.Dreamerdr:BAAALgAECgUJBQAAAA==.Dreidel:BAAALgADCgQJBAAAAA==.Dreim:BAEALgAECgEJAQABLgAFFAMJCAAMAEIgAA==.Drezdorn:BAAALgAECgEJAgAAAA==.Drgatorwine:BAAALgADCgUJBQABLgAECggJEAABAAAAAA==.Drizdourden:BAAALgAECgEJAQAAAA==.Drjp:BAAALgAECgQJCAAAAA==.Drkimchirice:BAAALgAECgQJBQABLgAECggJEAABAAAAAA==.Drlocktapus:BAABLgAECn8hAAIUAAgJNhz9LwBNAgAUAAgJNhz9LwBNAgAAAA==.Drmacncheese:BAAALgAECgYJEAABLgAECggJEAABAAAAAA==.Drpumpkinpie:BAAALgADCgcJDAABLgAECggJEAABAAAAAA==.Drugzone:BAABLgAECn8VAAICAAcJww8yCwAOAQACAAcJww8yCwAOAQAAAA==.Drwontonsoup:BAAALgAECggJEAAAAA==.',
Du='Duddyfuddy:BAAALgAECgMJAwAAAA==.Duiunit:BAAALgAECgMJAwAAAA==.Dumblìedore:BAAALgAECgIJAgAAAA==.Dummythicc:BAAALgAECgMJBQAAAA==.Durknessa:BAAALgADCgEJAQAAAA==.Durugak:BAAALgADCgQJBAAAAA==.',
Dw='Dwag:BAAALgADCgcJDAAAAA==.',
Dx='Dxmxt:BAAALgADCgEJAQAAAA==.',
Dy='Dye:BAAALgAECgMJBAAAAA==.',
Ea='Earthhammer:BAAALgAECggJDAAAAA==.Easyy:BAABLgAECn8cAAIXAAcJzBgaFQDcAQAXAAcJzBgaFQDcAQAAAA==.',
Ec='Ecthdaran:BAAALgAFFAEJAQAAAA==.',
Ed='Edoras:BAAALgADCgcJDQAAAA==.',
Ef='Efton:BAAALgAECgUJBgAAAA==.',
Ek='Eksi:BAAALgAECgUJCAAAAA==.',
El='Elemjae:BAAALgAECgEJAQABLgAECgcJGgAIAH8fAA==.Elethe:BAAALgADCgkJFQABLgAFFAEJAQABAAAAAA==.Elftastic:BAAALgAECgUJBQABLgAFFAYJDwAKAIsaAA==.Eliorian:BAAALgADCgUJBQAAAA==.Elivan:BAAALgADCgEJAQAAAA==.Elizebet:BAAALgADCgYJCQAAAA==.Elladria:BAAALgADCgMJAwAAAA==.Ellicit:BAAALgADCgMJAwAAAA==.Elzaine:BAABLgAECn8WAAIMAAkJySBYHgC1AgAMAAkJySBYHgC1AgAAAA==.',
Em='Emis:BAAALgADCgQJBwAAAA==.Emporic:BAAALgADCgUJBQAAAA==.Empress:BAAALgAECgUJBQAAAA==.',
En='Enhae:BAAALgADCgUJBQAAAA==.Entrophi:BAAALgAECgQJBQABLgAECgcJFwAbAC4fAA==.Entropi:BAABLgAECn8iAAIcAAgJCxPqDAC6AQAcAAgJCxPqDAC6AQAAAA==.Envys:BAABLgAECn8WAAIKAAgJsBBxiwC7AQAKAAgJsBBxiwC7AQAAAA==.Envyspal:BAAALgAECgQJCgAAAA==.',
Er='Erisnyx:BAAALgAECgkJBwAAAA==.',
Es='Esterelore:BAAALgAECgIJAwAAAA==.Estix:BAAALgAECgEJAQAAAA==.',
Et='Etherwing:BAAALgAECgcJEwAAAA==.',
Ev='Evilwwink:BAAALgAECgEJAQAAAA==.',
Ex='Excruciator:BAAALgAECgQJBQAAAA==.Excruciators:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Ez='Ezfran:BAEALgAECgkJAQAAAA==.Ezrabridger:BAAALgAECgMJAwAAAA==.Ezranim:BAAALgADCgYJBgAAAA==.',
Fa='Falloutz:BAAALgAECgQJCgAAAA==.Falloutzhunt:BAAALgADCggJCAABLgAECgQJCgABAAAAAA==.Falthun:BAAALgADCgMJAwAAAA==.Faschlangus:BAAALgADCgEJAQAAAA==.Fatcows:BAAALgAECgYJBgAAAA==.Fawxette:BAAALgAECgEJAQABLgAECggJKAAVAIcWAA==.',
Fe='Felger:BAAALgADCgMJAwAAAA==.Felintovoid:BAABLgAECn8cAAIVAAgJYxQ7WQCWAQAVAAgJYxQ7WQCWAQAAAA==.Feliya:BAAALgAECgEJAQAAAA==.Fengami:BAAALgADCgEJAQAAAA==.Fenridinn:BAAALgADCgYJCQAAAA==.Fesha:BAAALgADCgEJAQABLgAECgQJBwABAAAAAA==.',
Fi='Fieryfrost:BAAALgADCgcJCQABLgAECgcJFwAaABYHAA==.Finowscath:BAAALgAECgEJAQAAAA==.Fistdoc:BAAALgAECgQJDQABLgAECgYJDQABAAAAAA==.Fistynae:BAABLgAECn8fAAMFAAkJOxh2BQBDAgAFAAkJOxh2BQBDAgAEAAYJjRu7HADQAQAAAA==.Fizzlesaurus:BAAALgAECgYJDwAAAA==.',
Fl='Flamelece:BAAALgAECgIJAgABLgAECgYJEgABAAAAAA==.Fleshmaw:BAAALgADCgUJAwAAAA==.Flexorcist:BAAALgADCgYJBwAAAA==.Floo:BAAALgAECgEJAgAAAA==.Floralas:BAAALgAECgYJEwAAAA==.',
Fo='Fordinnir:BAAALgAECgIJAgAAAA==.Forseer:BAAALgADCgYJBgAAAA==.Foxjìtsu:BAAALgADCgEJAQAAAA==.Foxybag:BAAALgADCgMJBAAAAA==.Foxytotes:BAAALgADCgYJBgAAAA==.',
Fr='Frapless:BAAALgAECgMJAwAAAA==.Freezzerr:BAAALgADCgEJAQAAAA==.Frickenmage:BAAALgAECgUJCwAAAA==.Friendlypal:BAABLgAECn8VAAIRAAcJZBu9JgD0AQARAAcJZBu9JgD0AQAAAA==.Friendofbear:BAABLgAECn8rAAIOAAkJjRezIQA7AgAOAAkJjRezIQA7AgAAAA==.Frogo:BAAALgADCgMJAwAAAA==.',
Fu='Fudomeow:BAAALgADCgMJAwAAAA==.Fumazusha:BAAALgADCgIJAgAAAA==.Fumblebuck:BAAALgADCgkJGQABLgAECgYJCgABAAAAAA==.Funshíne:BAAALgADCgcJBwAAAA==.Furrybutted:BAAALgADCgcJAQAAAA==.Furryfeet:BAAALgAECgcJDwAAAA==.Furyofdawn:BAAALgAECgEJAQAAAA==.Fuzzpuff:BAAALgADCgMJBAAAAA==.Fuzzykuntz:BAAALgAECgkJDwAAAA==.',
Fy='Fynsdood:BAAALgADCgEJAQABLgAECgYJEgABAAAAAA==.Fynslane:BAAALgAECgYJEgAAAA==.Fynstick:BAAALgAECgUJBQABLgAECgYJEgABAAAAAA==.',
Ga='Gabelock:BAACLgAFFH8OAAIUAAUJkROoCQCSAQAUAAUJkROoCQCSAQAuAAQKfyIAAhQACAn/IPUcAKgCABQACAn/IPUcAKgCAAAA.Garchomp:BAABLgAECn8UAAIVAAYJHBkWHwB4AQAVAAYJHBkWHwB4AQAAAA==.',
Gh='Ghostreveri:BAABLgAECn8nAAIMAAgJ2xoCEwAiAgAMAAgJ2xoCEwAiAgAAAA==.Ghoulface:BAAALgAECgQJBQABLgAECgcJBwABAAAAAA==.',
Gi='Gigah:BAAALgAECgYJDgAAAA==.Gildin:BAAALgAECgYJCQAAAA==.Gingerbell:BAAALgAECgIJAgAAAA==.',
Gl='Global:BAAALgADCgcJCgAAAA==.Glopthethird:BAAALgADCgYJBgAAAA==.Glorpnotl:BAAALgAECgUJBQAAAA==.',
Gn='Gnomedalf:BAAALgAECgEJAQAAAA==.Gnomedguerre:BAAALgADCgMJAwAAAA==.',
Go='Goatstatik:BAAALgAECgYJDQAAAA==.Goblinface:BAAALgADCgUJBQAAAA==.Gollie:BAAALgAECgEJAQAAAA==.Gooblash:BAAALgAECgEJAQAAAA==.Goonerrofoz:BAAALgAECgUJDQAAAA==.Goonnugget:BAAALgAECgYJDgAAAA==.Gorthmog:BAAALgADCgQJBwAAAA==.',
Gr='Grampysmack:BAAALgADCggJEAAAAA==.Gravefeet:BAAALgADCgUJBQAAAA==.Gravehands:BAAALgADCgIJAgAAAA==.Gredory:BAAALgAECgYJCgAAAA==.Greendoritos:BAAALgAECgQJBgAAAA==.Grekum:BAAALgAECgYJEAAAAA==.Grep:BAAALgADCgEJAQAAAA==.Grimtree:BAABLgAECn8ZAAMbAAgJxxaeBQAPAgAbAAgJxxaeBQAPAgAUAAEJaRF9ogBAAAAAAA==.Grindor:BAAALgADCgQJBwAAAA==.Grogge:BAAALgADCgIJAgAAAA==.Grumpstraza:BAAALgAECgEJAQAAAA==.Grumpydemon:BAAALgAECgcJDgAAAA==.',
Gu='Guglugauthu:BAAALgAECgYJEgAAAA==.Gunwald:BAAALgADCgUJBQAAAA==.Gutcheck:BAABLgAECn8WAAIZAAcJMx6rDACeAQAZAAcJMx6rDACeAQAAAA==.',
Gw='Gwong:BAAALgADCgcJBwAAAA==.',
Gy='Gyo:BAAALgADCgcJBgABLgADCgkJDwABAAAAAA==.Gyodo:BAAALgADCgMJAwABLgADCgkJDwABAAAAAA==.Gyodoh:BAAALgADCgkJDwAAAA==.',
['Gö']='Gökû:BAAALgADCgUJBQAAAA==.',
Ha='Haaravende:BAAALgADCgUJBQAAAA==.Halfskul:BAACLgAFFH8GAAIJAAIJUweWSACSAAAJAAIJUweWSACSAAAuAAQKfysAAgkACAnyHOssAIUCAAkACAnyHOssAIUCAAAA.Halinis:BAAALgAECgYJEgAAAA==.Halvorse:BAAALgADCgMJAwAAAA==.Harandi:BAAALgADCgEJAQAAAA==.Harugokken:BAAALgADCgYJBgAAAA==.Hasha:BAAALgADCgYJBgAAAA==.Hashah:BAAALgAECgcJEwAAAA==.Hatefel:BAAALgAECgEJAQABLgAECgcJFgAdAM8eAA==.Haveblue:BAAALgADCggJCAAAAA==.Havoke:BAAALgADCgMJAwAAAA==.',
He='Healingyou:BAAALgADCgYJBgABLgAECgkJGwACABolAA==.Healsgobrr:BAAALgAECgkJDwABLgAECgkJIgAcAMMaAA==.Hellscar:BAAALgAECgEJAgAAAA==.Herakleitos:BAAALgADCgMJAwAAAA==.Hereticdoc:BAAALgAECgYJDQAAAA==.Herrah:BAAALgADCgcJDAAAAA==.Hesha:BAABLgAECn8UAAMSAAYJIB1HCABvAQASAAYJIB1HCABvAQAQAAEJXQOBpgApAAABLgAECgcJEwABAAAAAA==.Heytotemman:BAAALgAECgUJCQAAAA==.',
Ho='Holydingi:BAAALgADCgMJBQAAAA==.Holygrammy:BAAALgADCgcJCwAAAA==.Holyligth:BAAALgAECgQJBwAAAA==.Holysock:BAAALgADCgcJBwAAAA==.Holyyaii:BAABLgAECn8VAAIDAAYJ7h6yEACGAQADAAYJ7h6yEACGAQAAAA==.Holz:BAAALgAECgUJCQAAAA==.Hoodedpando:BAAALgAECgQJDAAAAA==.Hopsing:BAAALgAECgQJDwAAAA==.Hornychicken:BAAALgADCgEJAQABLgAECgQJBQABAAAAAA==.Horsetowater:BAAALgAECgYJBgAAAA==.Hotsluttymom:BAABLgAECn8ZAAIDAAcJ6hD6FABZAQADAAcJ6hD6FABZAQAAAA==.',
Hu='Hugoman:BAABLgAECn8eAAIUAAYJCxJGPQA7AQAUAAYJCxJGPQA7AQABLgAECgkJJgAJAFoYAA==.Huntbugman:BAABLgAECn8WAAIOAAgJ+Q9dMwDiAQAOAAgJ+Q9dMwDiAQAAAA==.Hurash:BAAALgAECgMJAwABLgAECgUJBQABAAAAAA==.Hurdtfeeling:BAAALgAECgcJDQAAAA==.',
['Hö']='Hölyheals:BAAALgADCgcJBwAAAA==.',
Ia='Iamyu:BAAALgAECgIJAgAAAA==.',
Ib='Ibun:BAAALgAECgYJEAAAAA==.',
Ic='Icebøx:BAAALgAECgIJAgAAAA==.Icefang:BAAALgADCgYJBgAAAA==.Icetomeetu:BAAALgADCgYJBgAAAA==.',
Ii='Iillil:BAABLgAECn8eAAIVAAgJWQbtdQBEAQAVAAgJWQbtdQBEAQAAAA==.',
Il='Illtul:BAABLgAECn8gAAIYAAgJHRpjDADGAQAYAAgJHRpjDADGAQAAAA==.',
Im='Imblindhelp:BAAALgAECgYJBgAAAA==.Imnotyourpal:BAAALgAECgUJCgAAAA==.Imscratchy:BAAALgADCgQJBAAAAA==.Imsweaty:BAAALgAECgkJDAAAAA==.Imzaiahfur:BAAALgAECgQJBQAAAA==.',
In='Ingraham:BAAALgADCgEJAQAAAA==.',
Ip='Ipwoman:BAAALgAFFAEJAgAAAA==.',
Is='Ishint:BAAALgADCgUJBQAAAA==.Isokie:BAAALgADCgIJAgAAAA==.',
It='Itradis:BAAALgADCgcJBwAAAA==.Itwasmedio:BAAALgAECgQJCQAAAA==.Itzitar:BAAALgADCgcJCgAAAA==.',
Iv='Ivyiina:BAAALgAECgMJCQAAAA==.',
Ja='Jae:BAAALgAECggJDQAAAA==.Jaeyk:BAAALgAECgcJAQAAAA==.Jamescameron:BAAALgAECgIJAwAAAA==.Jarninn:BAAALgADCgYJDAAAAA==.Jaywaz:BAAALgAECgUJBwAAAA==.',
Jc='Jck:BAABLgAECn8nAAIKAAkJzSSSAQBWAwAKAAkJzSSSAQBWAwAAAA==.',
Je='Jearn:BAAALgAECgEJAQAAAA==.Jedsezir:BAAALgAECgIJAgAAAA==.Jessirra:BAAALgAECgEJAQAAAA==.Jessupy:BAAALgAECgYJDgAAAA==.Jezebelz:BAAALgADCggJEgAAAA==.',
Ji='Jimmyhot:BAABLgAECn8mAAIKAAgJ9iPoDwBJAwAKAAgJ9iPoDwBJAwAAAA==.Jimmyx:BAAALgAECgYJBgABLgAECggJJgAKAPYjAA==.Jimsywimsy:BAAALgAECgYJCwAAAA==.Jingae:BAAALgADCgQJBAAAAA==.Jirikka:BAAALgADCgEJAQAAAA==.',
Jo='Joshmrx:BAAALgADCgcJBwAAAA==.',
Jr='Jracó:BAAALgAECgkJEwAAAA==.',
Ju='Juliettestar:BAAALgAECgEJAQAAAA==.Julz:BAABLgAECn8VAAIXAAYJ+BKhLAAuAQAXAAYJ+BKhLAAuAQAAAA==.Junepoon:BAAALgADCgIJAgAAAA==.Justiz:BAAALgAECgIJAgAAAA==.',
Jw='Jwarf:BAAALgADCgYJEQAAAA==.',
['Jø']='Jøsh:BAAALgAECgYJEwAAAA==.',
Ka='Kainga:BAAALgAECgMJAwAAAA==.Kalrendion:BAAALgAECggJEgAAAA==.Kalru:BAAALgAECgMJAwAAAA==.Kalrufu:BAAALgAECgcJEgAAAA==.Kalzok:BAAALgADCgYJBwAAAA==.Kamuela:BAAALgAECgIJAgAAAA==.Kaptonkronic:BAAALgAECgMJAwAAAA==.Karaillyonna:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Karasu:BAAALgAECgUJCwAAAA==.Karsiis:BAAALgAECgUJBQAAAA==.Kasion:BAAALgAECgUJBQAAAA==.Kayys:BAAALgAECgQJBAAAAA==.',
Ke='Keewenaw:BAAALgAECgYJCgAAAA==.Kelsier:BAABLgAECn8jAAIEAAgJLiIaAwDNAgAEAAgJLiIaAwDNAgAAAA==.Kerelor:BAAALgADCgcJDAAAAA==.Kesk:BAAALgAECgUJBgAAAA==.',
Kh='Khaosbringer:BAAALgAECgIJAgAAAA==.Khaosdragon:BAAALgADCgUJBQABLgAECgQJBQABAAAAAA==.Khaosstormz:BAAALgAECgQJBQAAAA==.Khaster:BAAALgADCgEJAQAAAA==.',
Ki='Kilavman:BAAALgADCgUJBQAAAA==.Killachefd:BAABLgAECn8ZAAIJAAgJFQeQQwAzAQAJAAgJFQeQQwAzAQAAAA==.Killamanjoro:BAAALgAECgEJAgAAAA==.Killerbow:BAAALgADCgMJAwAAAA==.Kimchiwar:BAABLgAECn8YAAIHAAYJqBJMSACDAQAHAAYJqBJMSACDAQAAAA==.Kirasha:BAAALgAECgYJEgAAAA==.Kitchenbound:BAAALgAECgYJDwAAAA==.Kittychan:BAABLgAECn8mAAMJAAkJWhi9KwCMAQAJAAkJWhi9KwCMAQATAAIJGRN9HwB4AAAAAA==.',
Kl='Klaacus:BAABLgAECn8bAAIVAAgJCxYhPwD3AQAVAAgJCxYhPwD3AQAAAA==.Kluath:BAAALgADCgcJBwAAAA==.',
Ko='Kodakdh:BAAALgAECgYJDQAAAA==.Kongol:BAAALgADCgUJBQAAAA==.Kongól:BAAALgAECgcJBwAAAA==.Koriten:BAAALgADCgQJCAAAAA==.Koschei:BAAALgADCgcJFAAAAA==.Koudelka:BAABLgAECn8WAAIeAAgJCRNoJACaAQAeAAgJCRNoJACaAQAAAA==.',
Kp='Kpa:BAAALgADCgcJBwAAAA==.Kpg:BAAALgAECgcJEwAAAA==.',
Kr='Kraak:BAAALgADCgMJBgAAAA==.Krilde:BAAALgAECgEJAQAAAA==.Kringelord:BAAALgAECgYJDAAAAA==.Kriticál:BAAALgAECgQJBAAAAA==.Kroshivecna:BAAALgAECgYJCwAAAA==.Krustym:BAAALgADCgUJCgAAAA==.',
Ku='Kurapika:BAAALgAECgIJAgAAAA==.Kuurun:BAEALgAECgYJBwABLgAFFAMJCAAMAEIgAA==.',
Ky='Kyout:BAAALgAECggJEgAAAA==.',
La='Laeina:BAAALgADCgUJBQAAAA==.Lamerehela:BAAALgADCgYJBgAAAA==.Lathrel:BAAALgAECgEJAQAAAA==.Lazystorm:BAABLgAECn8VAAIIAAYJbxUJGwA7AQAIAAYJbxUJGwA7AQAAAA==.',
Le='Leadfeet:BAAALgAECgMJBQAAAA==.Legiohn:BAAALgADCgEJAQAAAA==.Lelou:BAACLgAFFH8RAAMOAAQJlRufCABkAQAOAAQJ2RifCABkAQAfAAMJSRlcFAD8AAAuAAQKfykAAw4ACAnmIaAXANUBAB8ABwnhH6gfACUCAA4ABwkNHaAXANUBAAAA.Lemartes:BAAALgADCgEJAgAAAA==.Lemmys:BAAALgADCgYJCwAAAA==.Lemoncookie:BAAALgAECgQJBgAAAA==.Lemondropped:BAAALgAECgEJAQAAAA==.Lemonsquueze:BAAALgADCgMJAgAAAA==.Leyfon:BAAALgADCgIJAgAAAA==.',
Li='Lilathiaa:BAAALgAECgcJEwAAAA==.Lilith:BAAALgAECgEJAQAAAA==.Lillymae:BAAALgAECgYJEQAAAA==.Lilshama:BAAALgADCgEJAgAAAA==.Lilsmushy:BAABLgAECn8WAAIUAAYJABJ1PAA9AQAUAAYJABJ1PAA9AQAAAA==.Limpdoodle:BAAALgAECgIJAgAAAA==.Linuspelt:BAAALgADCgcJDQAAAA==.Linuzs:BAAALgADCgQJBAAAAA==.Liondori:BAABLgAECn8UAAINAAYJLCHqDAD5AQANAAYJLCHqDAD5AQAAAA==.Lissindra:BAAALgAECgEJAQAAAA==.Lizardlad:BAAALgADCgYJBgAAAA==.Lizzang:BAAALgADCgUJBQAAAA==.',
Lm='Lmj:BAABLgAECn8aAAIIAAcJfx+eCAAWAgAIAAcJfx+eCAAWAgAAAA==.',
Lo='Lobsterfest:BAAALgAECggJEAAAAA==.Lockbox:BAABLgAECn8nAAMUAAgJNiLIBgChAgAUAAcJNiLIBgChAgAdAAMJyh+IKAAhAQAAAA==.Lockngood:BAAALgAECgEJAQAAAA==.Lohrufal:BAAALgADCggJDQAAAA==.Lombotamy:BAAALgADCgMJAwAAAA==.Longboardpr:BAAALgADCgYJCgAAAA==.Loomin:BAACLgAFFH8PAAIKAAYJixqDBQDXAQAKAAYJixqDBQDXAQAuAAQKfx8AAgoACAkDIwQUADADAAoACAkDIwQUADADAAAA.Lorendris:BAAALgADCgMJAwAAAA==.',
Lu='Luckymoo:BAAALgAECgYJCwAAAA==.Lukrid:BAAALgADCgIJAgAAAA==.Lumiru:BAAALgADCgYJBgAAAA==.Lumièrevide:BAAALgAECgYJDwAAAA==.',
['Lä']='Lädyæk:BAABLgAECn8VAAIOAAkJvgu3QACtAQAOAAkJvgu3QACtAQAAAA==.',
['Lì']='Lìfealèrt:BAAALgADCgcJCQAAAA==.',
Ma='Macalor:BAAALgAECgUJDQAAAA==.Madagna:BAAALgADCgcJCQAAAA==.Madboy:BAAALgADCgcJEAAAAA==.Magicwinky:BAAALgADCgYJBgABLgAECgEJAQABAAAAAA==.Mahmba:BAAALgAECgMJAwAAAA==.Mahwea:BAAALgAECgEJAQAAAA==.Makati:BAAALgADCgYJCQAAAA==.Mallidin:BAAALgAECgUJDAAAAA==.Malthoryn:BAABLgAECn8aAAIgAAcJxxLnDgCdAQAgAAcJxxLnDgCdAQAAAA==.Mamamercy:BAAALgAECgYJCgAAAA==.Manield:BAAALgAECgcJAQAAAA==.Mardys:BAAALgAECgMJBAAAAA==.Marisol:BAAALgAECgQJCQAAAA==.Mastabazzi:BAAALgADCgEJAgAAAA==.',
Me='Meal:BAAALgAECgYJDAAAAA==.Mechamike:BAAALgAECgYJEAAAAA==.Megalover:BAAALgAECgMJAwAAAA==.Melodí:BAAALgAECgEJAQAAAA==.Melorac:BAAALgAECgYJEAAAAA==.Mem:BAABLgAECn8jAAMbAAcJMx4vAgDEAQAbAAcJMx4vAgDEAQAUAAQJEw1lwADYAAAAAA==.Meowor:BAAALgADCgUJBQABLgAECgkJGgAEAFciAA==.Merope:BAAALgADCgUJBQAAAA==.Mertence:BAAALgADCgYJEAAAAA==.Mesandera:BAAALgAECgYJCwAAAA==.',
Mh='Mheow:BAAALgAECgIJAgAAAA==.',
Mi='Miccivxx:BAACLgAFFH8FAAIOAAMJugU0LQCfAAAOAAMJugU0LQCfAAAuAAQKfx8AAg4ACAk0GBYUAPEBAA4ACAk0GBYUAPEBAAAA.Microch:BAAALgADCgYJDgAAAA==.Micromortis:BAAALgAECgMJAwAAAA==.Midnightsham:BAAALgADCggJDgAAAA==.Midnightsun:BAABLgAECn8kAAIQAAgJ9xRxFgCzAQAQAAgJ9xRxFgCzAQAAAA==.Mikeoochie:BAAALgAECgEJAQAAAA==.Mimiche:BAAALgAECgUJCwAAAA==.Minxyrae:BAABLgAECn8sAAIRAAYJUxLZGgB2AQARAAYJUxLZGgB2AQAAAA==.Mitufu:BAAALgAECgEJAQAAAA==.',
Mj='Mjernamir:BAABLgAECn8VAAIYAAYJOQxYHwACAQAYAAYJOQxYHwACAQAAAA==.',
Mo='Moistson:BAAALgAECgUJDgAAAA==.Mom:BAABLgAECn8VAAIUAAcJkxTcQwAlAQAUAAcJkxTcQwAlAQAAAA==.Momie:BAAALgADCgIJAgAAAA==.Mongorian:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECgYJBwAAAA==.Monknugget:BAAALgAECggJEAAAAA==.Moofrosty:BAAALgAECgEJAgAAAA==.Moonish:BAAALgAECgEJAQABLgAECggJHQARAAQmAA==.Moonrupal:BAAALgAECgQJCQAAAA==.Moonwarden:BAAALgADCgcJBwAAAA==.Mordokk:BAABLgAECn8UAAIUAAcJ9wjLQQAsAQAUAAcJ9wjLQQAsAQAAAA==.Morganya:BAABLgAECn8oAAIVAAgJhxZlFQC+AQAVAAgJhxZlFQC+AQAAAA==.Morgañya:BAAALgAECgYJDQABLgAECggJKAAVAIcWAA==.Morgul:BAAALgAECgYJDgAAAA==.Morphz:BAAALgAECgQJBAAAAA==.Morrtis:BAAALgADCgQJBAAAAA==.Mortics:BAAALgAECgEJAQAAAA==.Mortishaa:BAABLgAECn8XAAIbAAcJJRD3CwB6AQAbAAcJJRD3CwB6AQAAAA==.Moundask:BAAALgADCgEJAgAAAA==.',
Ms='Mseow:BAAALgADCgUJBQAAAA==.',
Mu='Muchplague:BAABLgAECn8hAAIJAAgJ3BFHLQCGAQAJAAgJ3BFHLQCGAQAAAA==.Muddbut:BAAALgAECgEJAQAAAA==.Mutagenooze:BAAALgADCgUJDgAAAA==.Muwoo:BAAALgAECgYJBwAAAA==.',
My='Mycowgoesmoo:BAAALgADCgkJDwAAAA==.Mynnu:BAAALgAECgQJBAAAAA==.',
Na='Nachoproblem:BAAALgAECgEJAQAAAA==.Naeuh:BAABLgAECn8iAAIOAAgJVhJ3HgCpAQAOAAgJVhJ3HgCpAQAAAA==.Nahadotha:BAAALgAECgEJAQAAAA==.Nanako:BAAALgAECgMJAwAAAA==.Nance:BAACLgAFFH8GAAIUAAMJjRX7KQD3AAAUAAMJjRX7KQD3AAAuAAQKfyQAAhQACAmzIe4QAPMCABQACAmzIe4QAPMCAAAA.Narasong:BAAALgAECgEJAQAAAA==.Naraysta:BAABLgAECn8pAAMJAAkJyxbgRwAcAgAJAAkJSxbgRwAcAgATAAYJNxRaDgAtAQAAAA==.Nasan:BAAALgAECgQJBAAAAA==.Nathette:BAAALgAECgcJCgAAAA==.Nautprepared:BAAALgADCgkJFgAAAA==.',
Ne='Necrofêêlya:BAAALgADCgEJAQAAAA==.Neeck:BAAALgAECgEJAQAAAA==.Needhealz:BAABLgAECn8fAAIRAAgJHR2KBgB5AgARAAgJHR2KBgB5AgAAAA==.Neildasstysn:BAABLgAECn8ZAAIhAAgJbxkeCQBQAgAhAAgJbxkeCQBQAgAAAA==.Nemezyz:BAAALgADCgYJBgAAAA==.Nephey:BAAALgADCgUJBgAAAA==.Neveya:BAAALgADCgcJDwAAAA==.Newwing:BAAALgADCggJDQAAAA==.',
Ni='Niavka:BAAALgADCgUJBQAAAA==.Nickeld:BAABLgAECn8YAAMKAAgJIBbkMQCcAQAKAAgJmhDkMQCcAQAPAAYJpxSKBwCJAQAAAA==.Nickerfritz:BAAALgAECgUJCgAAAA==.Nickhy:BAAALgAECgMJAwAAAA==.Nietherme:BAAALgAECgYJDwAAAA==.Nihildicits:BAAALgAECgIJAgAAAA==.Niverrø:BAAALgAECgYJDwABLgAECggJKQAZAFYcAA==.',
No='Noahmedlock:BAAALgAECgEJAQAAAA==.Noblefiend:BAAALgADCgMJAwAAAA==.Nodnardd:BAAALgAECgYJEAAAAA==.Noirwyn:BAAALgADCgYJBgAAAA==.Nokomu:BAAALgADCgcJDAAAAA==.Noliee:BAAALgAECgIJBQAAAA==.Noluckjay:BAAALgADCgcJBwAAAA==.Noodie:BAAALgAECgIJAgAAAA==.Noogra:BAAALgADCgEJAQAAAA==.Norinithedra:BAAALgAECgQJBAAAAA==.Nossavaria:BAAALgADCgEJAQAAAA==.Noxis:BAAALgAECgQJBwAAAA==.',
Nu='Nulva:BAAALgADCgYJDgAAAA==.',
Ny='Nyadris:BAAALgADCgkJCQAAAA==.Nyagosa:BAABLgAECn8VAAIiAAkJKxRoGQARAgAiAAkJKxRoGQARAgAAAA==.Nyalore:BAAALgAECgkJEAAAAA==.Nymesys:BAAALgADCgYJCQAAAA==.',
Oa='Oakencrush:BAAALgADCgEJAQAAAA==.',
Ol='Oldmanjankin:BAAALgAECgUJBQAAAA==.Olia:BAAALgADCgIJAgAAAA==.Oluhegar:BAAALgADCgIJAgAAAA==.',
Om='Omnimon:BAAALgADCgEJAQABLgAECggJHQAQAIElAA==.',
Oq='Oquaellii:BAAALgAECgQJCgAAAA==.',
Or='Oralen:BAACLgAFFH8JAAIRAAQJLRUvCwA+AQARAAQJLRUvCwA+AQAuAAQKfxsAAhEACAmFGPogABQCABEACAmFGPogABQCAAAA.Orangedorito:BAAALgAECgQJBAAAAA==.Orcthas:BAAALgAECgQJBAABLgAFFAUJEAAMAG0eAA==.Ordola:BAABLgAECn8ZAAIEAAcJ8BywFwACAgAEAAcJ8BywFwACAgAAAA==.Orlorian:BAAALgAECgEJAQAAAA==.',
Ot='Othneil:BAAALgADCgMJAwAAAA==.',
Ou='Outtlawz:BAAALgADCgEJAQAAAA==.',
Ov='Overloader:BAABLgAECn8jAAIVAAcJ+hwHKQBCAQAVAAcJ+hwHKQBCAQAAAA==.',
Pa='Painreaver:BAEBLgAECn87AAIVAAkJ3BlVBwBmAgAVAAkJ3BlVBwBmAgAAAA==.Palahang:BAAALgADCgIJAgAAAA==.Palimax:BAAALgAECgEJAgAAAA==.Pallyaxe:BAAALgAECgUJCgABLgAECgkJJwAKAIoYAA==.Pallygank:BAAALgADCgIJAgAAAA==.Pallysin:BAAALgADCgMJBAAAAA==.Pamn:BAAALgADCgUJBQAAAA==.Pancandy:BAAALgAECgMJBgAAAA==.Paneer:BAAALgAECgQJCQAAAA==.Parryhottër:BAAALgADCgMJAQAAAA==.Pascel:BAAALgAECgYJDwAAAA==.',
Pe='Pebbletoe:BAAALgADCgUJBwAAAA==.Penta:BAAALgAECgMJAwAAAA==.Percgripper:BAAALgAECgUJBAABLgAECgcJEwABAAAAAA==.Percivis:BAAALgADCgEJAQAAAA==.Perida:BAAALgAECgEJAgAAAA==.Peronarth:BAAALgADCgIJAgAAAA==.Peruano:BAAALgAECgcJCgAAAA==.Petforheals:BAAALgAECgcJCQAAAA==.',
Ph='Phouy:BAAALgADCgIJAgAAAA==.Phyoo:BAAALgAECgUJEAAAAA==.',
Pi='Picken:BAEALgADCgEJAQABLgAFFAMJCAAMAEIgAA==.',
Pk='Pkrippa:BAAALgADCgcJCAAAAA==.',
Pl='Plu:BAAALgAECgUJEwAAAA==.',
Po='Pocahöntas:BAAALgADCgkJDgAAAA==.Pogie:BAAALgADCgUJBQAAAA==.Polkagay:BAAALgAECgIJAwAAAA==.Portick:BAAALgAECgQJBwAAAA==.Posttmasterz:BAAALgAECgQJBAAAAA==.',
Pr='Prittykitty:BAAALgADCgcJBwAAAA==.Protrunkey:BAAALgAECgEJAQAAAA==.Provolonie:BAAALgAECgYJEwAAAA==.',
Pu='Puppiboi:BAAALgADCggJCQAAAA==.Puritos:BAAALgAECgQJDQAAAA==.Pushti:BAAALgADCgYJBgAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrista:BAABLgAECn8WAAIOAAYJ4RQ2MwBEAQAOAAYJ4RQ2MwBEAQAAAA==.',
Qe='Qeikli:BAAALgADCgEJAgAAAA==.',
Qo='Qortethhunt:BAAALgAECgEJAQAAAA==.',
Qu='Quackapls:BAAALgAECgUJCQAAAA==.Quaratus:BAAALgAECgUJBQAAAA==.',
Ra='Raendarth:BAAALgAECgYJDwAAAA==.Rageslave:BAAALgAECgkJDwAAAA==.Rageth:BAABLgAECn8dAAMjAAgJ1Q9tAwCzAQAjAAgJ1Q9tAwCzAQAcAAIJpQisPABeAAAAAA==.Ragnarule:BAAALgAECgIJAgAAAA==.Ragnol:BAAALgAECgQJBQAAAA==.Rakalaag:BAEALgADCgIJAgAAAA==.Rakath:BAABLgAECn8UAAIYAAcJ3hClHQAPAQAYAAcJ3hClHQAPAQAAAA==.Ramchi:BAAALgAECgUJBwAAAA==.Ramlethal:BAAALgADCgEJAgAAAA==.Ramw:BAAALgAECgYJBgAAAA==.Rasmis:BAAALgAFFAIJBAAAAA==.Ravielo:BAAALgADCgQJBAAAAA==.Rawlanth:BAAALgADCgcJCQAAAA==.',
Re='Reafmon:BAAALgAECgQJCAAAAA==.Reafork:BAAALgAECgQJBQAAAA==.Reck:BAABLgAECn8YAAMGAAgJLiAFBgBxAgAGAAgJGBwFBgBxAgAHAAUJoyTbMwDbAQAAAA==.Redrangerzz:BAAALgADCgUJBAAAAA==.Regulos:BAAALgAECgEJAQAAAA==.Relanni:BAAALgADCgQJBAAAAA==.Remedialtim:BAAALgADCgkJCQAAAA==.Renwick:BAAALgADCgkJEwABLgAFFAEJAQABAAAAAA==.Reomikage:BAAALgADCgcJBwAAAA==.Reservetank:BAAALgADCgMJAwAAAA==.Retasa:BAAALgAECgQJCAAAAA==.Retwings:BAABLgAFFH8KAAIMAAMJCRpZEgASAQAMAAMJCRpZEgASAQAAAA==.Reunach:BAABLgAECn8YAAIMAAgJmQuGNQBtAQAMAAgJmQuGNQBtAQAAAA==.Reybekka:BAEALgAECgcJDgAAAA==.',
Rh='Rhialto:BAAALgADCgMJAwAAAA==.Rhinegeist:BAAALgADCgEJAQAAAA==.',
Ri='Riccus:BAAALgADCgcJEQAAAA==.Rin:BAAALgAECgMJAwAAAA==.Ris:BAAALgAECgEJAwAAAA==.Ritualburner:BAAALgAECgEJAQAAAA==.Riverpixie:BAAALgADCgQJCAAAAA==.',
Ro='Roachman:BAAALgAECgYJCwAAAA==.Robovac:BAAALgADCgUJCgAAAA==.Rockbrew:BAAALgAECgYJEAAAAA==.Rockslice:BAAALgAECgUJBwAAAA==.Roonoa:BAAALgADCgcJBwAAAA==.Rorien:BAAALgAECgIJAgABLgAECgMJCQABAAAAAA==.Rosannas:BAAALgADCgcJDAABLgAFFAMJCAALACsVAA==.Royallz:BAAALgADCgcJBwAAAA==.',
Ru='Ruckùs:BAAALgAECgcJEgAAAA==.Rudora:BAAALgADCgcJDQAAAA==.Ruibash:BAECLgAFFH8IAAIMAAMJQiDkHQD/AAAMAAMJQiDkHQD/AAAuAAQKfzAAAgwACAkPJloEANgCAAwACAkPJloEANgCAAAA.Rule:BAAALgADCgEJAQAAAA==.',
Ry='Ryul:BAABLgAECn8XAAIkAAcJjBkvEwBuAQAkAAcJjBkvEwBuAQAAAA==.Ryuuzen:BAAALgAECgMJBAAAAA==.',
['Rê']='Rêqûiem:BAAALgAECgEJAQAAAA==.',
Sa='Sabigosa:BAAALgAECgYJCQAAAA==.Sabitha:BAABLgAFFH8FAAIgAAMJsBGrEQDwAAAgAAMJsBGrEQDwAAAAAA==.Sabpie:BAAALgADCgYJDwAAAA==.Sabrita:BAAALgADCgYJCAAAAA==.Sacredkhaos:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.Sacredknight:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.Sagoon:BAAALgADCgIJAgAAAA==.Saguun:BAAALgADCgUJBQAAAA==.Saikoumaster:BAABLgAECn8bAAIJAAcJhgvoQQA4AQAJAAcJhgvoQQA4AQAAAA==.Saje:BAABLgAECn8ZAAMgAAcJYxsEDQC5AQAgAAcJYxsEDQC5AQAiAAEJfARQggAvAAABLgAECggJHQAQAIElAA==.Sakebomb:BAAALgADCgYJDQAAAA==.Samwho:BAAALgADCgYJDAAAAA==.Sarajean:BAAALgAECgcJAgAAAA==.Sareythor:BAAALgADCgYJCAAAAA==.Sargeteeter:BAAALgADCgMJAwAAAA==.Satanonus:BAAALgADCgUJBAAAAA==.',
Sc='Scaledoc:BAAALgAECgEJAQABLgAECgYJDQABAAAAAA==.Scarelette:BAAALgADCgYJBwAAAA==.Scarletmatch:BAABLgAECn8dAAIOAAgJCBTWKABzAQAOAAgJCBTWKABzAQAAAA==.Scarwitch:BAAALgADCgIJAgAAAA==.Schamane:BAAALgAECgMJAwAAAA==.Schmedium:BAAALgADCgQJBAAAAA==.Scotty:BAAALgAECgYJDAAAAA==.',
Se='Seer:BAAALgADCgYJBgAAAA==.Seldav:BAABLgAECn8iAAMcAAkJwxp/DwB/AgAcAAgJwxp/DwB/AgAjAAMJtxNtMgCCAAAAAA==.Selenyra:BAABLgAECn8XAAMDAAgJBQmOEgBxAQADAAgJBQmOEgBxAQAgAAcJPwMPNgD0AAAAAA==.Selm:BAABLgAECn8rAAICAAkJOCWAAADWAgACAAkJOCWAAADWAgAAAA==.Selvarkes:BAAALgADCgMJAwAAAA==.Seraphrim:BAAALgADCgYJBgAAAA==.Seryne:BAAALgAECgUJDAAAAA==.Sevarg:BAAALgAECgYJDgAAAA==.Sevveruss:BAAALgAECgMJBQAAAA==.',
Sh='Shadowfury:BAAALgAECgQJDAAAAA==.Shadowjuve:BAAALgAECgkJCwAAAA==.Shadowsnout:BAAALgAECgEJAQAAAA==.Shalandrov:BAAALgADCgEJAQAAAA==.Shameless:BAAALgADCgkJEAAAAA==.Sharco:BAABLgAECn8oAAIKAAgJExNwKADDAQAKAAgJExNwKADDAQAAAA==.Sharkeshia:BAAALgAFFAIJAgAAAA==.Shawarmafury:BAABLgAECn8jAAIOAAgJ2yQBAwDgAgAOAAgJ2yQBAwDgAgAAAA==.Sheedem:BAAALgADCgcJDQABLgAECgYJEAABAAAAAA==.Sherrizzahh:BAAALgAECgEJAQAAAA==.Shifhappens:BAAALgAECgEJAQAAAA==.Shinshots:BAAALgADCgYJBgAAAA==.Shinyzig:BAAALgAECgQJBAAAAA==.Shockadinn:BAABLgAECn8gAAMRAAcJhh7QFQBiAgARAAcJhh7QFQBiAgAMAAYJLxgamwBIAQAAAA==.Shooshmael:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Shujáa:BAABLgAECn8WAAIJAAgJSRxVDgBQAgAJAAgJSRxVDgBQAgAAAA==.Shékinah:BAAALgAECgcJEQAAAA==.',
Si='Sickbones:BAAALgAECgYJCwABLgAFFAIJAwABAAAAAA==.Sighmon:BAAALgADCgIJAgAAAA==.Silvoryn:BAAALgADCgcJBwAAAA==.Silvrshh:BAAALgAECgQJBAAAAA==.Silvrsoil:BAAALgADCgEJAQAAAA==.Sinba:BAAALgAECgEJAgAAAA==.Sinsister:BAAALgAECgYJCwAAAA==.Sinthein:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Sk='Skadfather:BAABLgAECn8cAAMRAAcJ8iC2EACMAgARAAcJ8iC2EACMAgAMAAEJ4AxMyQA4AAAAAA==.Skellyheals:BAAALgAECgQJCgAAAA==.Skorpekh:BAAALgADCgcJCwAAAA==.Skuumfein:BAAALgAECgUJCgAAAA==.Skydeuxlight:BAAALgAECgQJDQAAAA==.',
Sl='Slamdingo:BAAALgADCgUJBQAAAA==.Sleepingsun:BAABLgAECn8ZAAMXAAYJTByIFADhAQAXAAYJTByIFADhAQAYAAIJsQhocgBXAAAAAA==.Sloppyspikes:BAAALgAECggJDQAAAA==.',
Sm='Smakm:BAAALgAECgMJBQAAAA==.Smeshh:BAAALgAECgQJBAAAAA==.Smidgenn:BAAALgAECgUJBQAAAA==.Smokyblast:BAAALgAECgIJAwAAAA==.',
Sn='Snailtrails:BAAALgADCgcJDQAAAA==.Snowball:BAABLgAECn8bAAIKAAgJ+gSgUwA5AQAKAAgJ+gSgUwA5AQAAAA==.',
So='Solenya:BAAALgAECgEJAgAAAA==.Sonyskvirtik:BAAALgADCgYJBgAAAA==.Soozie:BAAALgAECgIJBAAAAA==.Sophiez:BAAALgADCgEJAQAAAA==.Sorvara:BAAALgADCgcJBwAAAA==.Sotan:BAABLgAECn8eAAIOAAgJtRqPDwAbAgAOAAgJtRqPDwAbAgAAAA==.Soulforge:BAAALgADCggJCQAAAA==.',
Sp='Sparowprince:BAACLgAFFH8GAAIMAAQJwRHCIQCpAAAMAAQJwRHCIQCpAAAuAAQKfyAAAgwACQlwIPgPAA8DAAwACQlwIPgPAA8DAAAA.Sparxs:BAAALgADCgUJBQAAAA==.Spazs:BAAALgADCgUJCAAAAA==.Spectraleye:BAABLgAECn8YAAIVAAgJ/yE2AwDHAgAVAAgJ/yE2AwDHAgAAAA==.Spookahuntes:BAAALgAECgQJCAAAAA==.Sproocherlou:BAABLgAECn8aAAIMAAcJSBrQGwDjAQAMAAcJSBrQGwDjAQAAAA==.',
Sq='Squirlmaster:BAAALgADCgIJAgAAAA==.',
Ss='Ssomepally:BAAALgADCgkJCQAAAA==.',
St='Stabier:BAAALgADCgQJCQAAAA==.Standalone:BAAALgADCgYJBwAAAA==.Starstryker:BAAALgADCgEJAQAAAA==.Stashdaddy:BAAALgADCgEJAQAAAA==.Stazzch:BAAALgAECgIJAwAAAA==.Stealthzu:BAABLgAECn8gAAIZAAcJhxBlDgCFAQAZAAcJhxBlDgCFAQAAAA==.Steezya:BAAALgAECgIJAwAAAA==.Stegulos:BAAALgAFFAEJAQAAAA==.Stellarum:BAAALgAECgEJAQAAAA==.Stonedemon:BAAALgADCgYJBgABLgAFFAQJBgAMAMERAA==.Stoneocean:BAAALgADCgYJCgAAAA==.Stormblessd:BAAALgAECgIJAgAAAA==.Stormsy:BAAALgAECgEJAQABLgAECggJIgAiAOIcAA==.Stormykitty:BAABLgAECn8iAAIiAAgJ4hy+EQBUAgAiAAgJ4hy+EQBUAgAAAA==.Strawhatglaz:BAAALgAECgYJCwABLgAECgIJAgABAAAAAA==.Strikermain:BAAALgAECgQJBAAAAA==.Stronkchills:BAAALgADCgEJAQAAAA==.Sturtza:BAABLgAECn8YAAIOAAgJExouFQCOAgAOAAgJExouFQCOAgAAAA==.Sturtzam:BAAALgAECgYJBgABLgAECggJGAAOABMaAA==.',
Su='Succubussy:BAAALgAECgEJAQAAAA==.Suun:BAAALgAECgYJDQAAAA==.',
Sw='Swoley:BAABLgAECn8hAAIRAAcJwSKoDAC1AgARAAcJwSKoDAC1AgAAAA==.',
Sy='Sycotix:BAAALgAECgYJBgAAAA==.Syndraza:BAAALgADCgkJEgAAAA==.Synsei:BAAALgAECgQJBQAAAA==.Syyn:BAAALgADCgYJBwAAAA==.',
Ta='Tagobeets:BAAALgAECgYJDwAAAA==.Tahia:BAAALgAECgEJAQAAAA==.Taimaishoo:BAAALgADCgYJDAAAAA==.Talendil:BAAALgAECgcJBwAAAA==.Talisaie:BAACLgAFFH8HAAMUAAQJ2hT+EgBQAQAUAAQJGBP+EgBQAQAdAAIJ6QuHFgBSAAAuAAQKfyIAAx0ACQlZI+QDAKsCAB0ABwnhIuQDAKsCABQACAlQIN0pAGkCAAAA.Taln:BAAALgAECgIJAgAAAA==.Talohha:BAAALgADCgcJBwAAAA==.Talzitalet:BAAALgADCgYJBgAAAA==.Tandor:BAABLgAECn8UAAIMAAYJ2hOQjQBgAQAMAAYJ2hOQjQBgAQAAAA==.Taolu:BAAALgAECgIJAgABLgAECggJIQAJANwRAA==.Tarancalime:BAAALgAECgYJEAAAAA==.Tarandris:BAAALgAECgUJBQAAAA==.Taron:BAAALgAECgYJDwAAAA==.Tazenazal:BAEALgAECgYJEAAAAA==.',
Th='Thatkindaorc:BAAALgADCgkJCAAAAA==.Thegreatestt:BAAALgADCgIJAgAAAA==.Thehumanatee:BAABLgAECn8bAAMYAAkJfR27EwB2AgAYAAkJfR27EwB2AgAXAAYJIwhDOwDmAAAAAA==.Theriondread:BAAALgAECgYJDwAAAA==.Theunholyone:BAAALgAECgUJBQAAAA==.Thicky:BAAALgADCgMJAwAAAA==.Thiquems:BAAALgAECgYJCgAAAA==.Thuaddar:BAAALgAECgMJAwAAAA==.Thunderanvil:BAAALgADCgYJBgAAAA==.Thyphlo:BAAALgAECgcJDwAAAA==.',
Ti='Tiagrimtotem:BAAALgADCgYJBgAAAA==.Ticklemedady:BAEALgAECgQJCAABLgAECgkJOwAVANwZAA==.Tiltedup:BAABLgAECn8oAAIKAAgJPB/QLQC7AgAKAAgJPB/QLQC7AgAAAA==.Tinkerßell:BAAALgAECgUJBgABLgAECggJIgAiAOIcAA==.Tirich:BAAALgADCgIJAgABLgAFFAEJAQABAAAAAA==.Tirmanator:BAAALgADCgIJAgAAAA==.',
To='Toebeanss:BAAALgADCgcJFwAAAA==.Toshi:BAABLgAECn8UAAIUAAcJ5gNBWwDgAAAUAAcJ5gNBWwDgAAAAAA==.Totemstitch:BAAALgADCgMJAwAAAA==.Touchyfeely:BAABLgAECn8bAAIDAAkJvw1aIgDEAQADAAkJvw1aIgDEAQAAAA==.',
Tr='Trashgo:BAAALgADCgIJAgAAAA==.Trashgu:BAAALgAECgEJAQAAAA==.Trentonii:BAAALgADCgEJAQAAAA==.Trolhznoname:BAAALgADCgcJBwAAAA==.',
Tt='Ttmina:BAAALgADCgUJBQAAAA==.',
Tu='Tufani:BAAALgADCgUJBQAAAA==.Tulark:BAAALgADCgIJAwAAAA==.Tullyy:BAAALgAECgMJAwAAAA==.Tums:BAAALgAECggJEwAAAA==.Turkatron:BAAALgADCgQJBAAAAA==.Tusaditty:BAAALgADCgYJBAAAAA==.',
Tw='Twicetwice:BAAALgAECgcJDAAAAA==.Twirls:BAAALgAECgcJDgAAAA==.Twotwothree:BAAALgAECgcJEwAAAA==.',
Ty='Tylenill:BAAALgAECgcJEgAAAA==.Tylos:BAAALgADCgQJBQAAAA==.Typhoíd:BAAALgAECgEJAQAAAA==.Tyranical:BAAALgAECgYJDQAAAA==.',
Ul='Ulzulwrath:BAAALgADCgUJBgAAAA==.',
Un='Uncanny:BAAALgAECgMJAwAAAA==.',
Ur='Ursoman:BAAALgAECgEJAQAAAA==.Urtle:BAAALgAECgYJEgAAAA==.',
Us='Uselece:BAAALgAECgYJEgAAAA==.',
Uz='Uzainbolt:BAAALgAECgIJAgAAAA==.',
Va='Vaboz:BAAALgADCgEJAQAAAA==.Valeena:BAAALgAECgcJDgAAAA==.Valoric:BAAALgADCgUJBQAAAA==.Valvalon:BAABLgAECn8WAAIKAAcJPhV3QABtAQAKAAcJPhV3QABtAQAAAA==.Vandorian:BAAALgAECgQJBgAAAA==.Vannin:BAAALgADCgMJAwAAAA==.Vardá:BAAALgADCgEJAQAAAA==.',
Ve='Veelaria:BAAALgAECgYJCwAAAA==.Velarisaa:BAAALgADCgcJCwAAAA==.Veledaa:BAAALgAECgUJCgABLgAECgcJBwABAAAAAA==.Velinddrel:BAAALgADCgcJDgAAAA==.Verena:BAAALgADCgMJAwAAAA==.Vestige:BAAALgAECgEJAQAAAA==.',
Vi='Vicalaus:BAAALgAECgQJBQABLgAECggJGwAVAAsWAA==.View:BAAALgADCgUJBQAAAA==.Vikingxx:BAAALgADCgEJAQAAAA==.Vilified:BAAALgAECgYJEwAAAA==.Vincelex:BAAALgADCgMJBgAAAA==.Vincerer:BAAALgAECgQJBwAAAA==.Vitros:BAAALgADCgcJBwABLgAECgEJAQABAAAAAA==.',
Vl='Vladymir:BAAALgADCgYJBgAAAA==.',
Vo='Voidbren:BAAALgAECgYJDwAAAA==.Voidescapee:BAAALgAECgMJBQAAAA==.Voidpapi:BAAALgAECgEJAQAAAA==.Voidsav:BAAALgADCgMJBQAAAA==.Voidscarred:BAAALgADCggJDgAAAA==.Voidwitch:BAABLgAECn8WAAIdAAcJzx7hAQARAgAdAAcJzx7hAQARAgAAAA==.',
Vy='Vylandra:BAAALgADCgYJBgAAAA==.',
Wa='Wagar:BAAALgAECgEJAQAAAA==.Watchmecook:BAAALgAECgMJBAAAAA==.',
We='Webbfury:BAAALgAECgcJEwAAAA==.Wetpug:BAAALgAECgEJAQAAAA==.',
Wh='Wheremytotem:BAAALgADCgYJBgABLgAECggJHwARAB0dAA==.',
Wi='Wiidge:BAAALgAECgYJDgAAAA==.Wildretnuh:BAACLgAFFH8JAAIVAAQJRgxmHgDvAAAVAAQJRgxmHgDvAAAuAAQKfyUAAhUACAnKF+xDAOQBABUACAnKF+xDAOQBAAAA.Windiwithani:BAABLgAECn8gAAIaAAgJMBRXCwBwAQAaAAgJMBRXCwBwAQAAAA==.Wiou:BAAALgADCgMJAwAAAA==.',
Wo='Wocky:BAAALgAECgYJDgAAAA==.Worgath:BAAALgAECgUJCgAAAA==.Worldcrafter:BAAALgAECgYJEgAAAA==.',
Wr='Wrapta:BAAALgADCgkJDwAAAA==.Wrathofdawn:BAAALgAECgEJAgAAAA==.',
Xa='Xaalai:BAAALgADCgIJAgAAAA==.Xantry:BAACLgAFFH8QAAMMAAUJbR55CQBiAQAMAAUJvRt5CQBiAQANAAIJ7Bb7AwCdAAAuAAQKfyAAAgwACAnQJWQIAFADAAwACAnQJWQIAFADAAAA.',
Xe='Xenons:BAAALgADCgYJBgAAAA==.',
Xi='Xillow:BAAALgADCgQJBAAAAA==.',
Xs='Xsirdrunk:BAAALgADCggJDwAAAA==.',
Xy='Xylin:BAAALgAECgMJAwAAAA==.Xymm:BAAALgAECgEJAQAAAA==.',
Ye='Yeastytree:BAABLgAECn8nAAIXAAkJRBpeBwCbAgAXAAkJRBpeBwCbAgAAAA==.Yellatuu:BAAALgAECgUJEAAAAA==.',
Ys='Yshlata:BAAALgADCgMJAwAAAA==.',
Za='Zanekraken:BAAALgADCgYJBgAAAA==.Zanthoss:BAAALgADCgkJFwAAAA==.Zarathea:BAAALgAECgEJAQAAAA==.',
Ze='Zella:BAAALgADCgYJCwAAAA==.Zemniss:BAAALgADCgcJBwAAAA==.Zendalis:BAAALgAECgYJCgAAAA==.Zenjay:BAAALgAECgQJBQAAAA==.Zerrikan:BAAALgADCgUJBQAAAA==.',
Zh='Zhalthir:BAAALgAECgEJAgAAAA==.',
Zi='Zilphah:BAAALgAECgUJBQAAAA==.Zimms:BAABLgAECn8dAAIFAAgJLxsYEwBYAQAFAAgJLxsYEwBYAQAAAA==.Zimmypup:BAAALgAECgIJAgABLgAECggJHQAFAC8bAA==.Zinng:BAAALgADCgYJBgAAAA==.Zirakul:BAAALgAECgEJAQAAAA==.',
Zo='Zoeyredbird:BAAALgAECgYJDgAAAA==.Zombalorian:BAAALgADCgMJAgAAAA==.',
Zu='Zulamar:BAAALgAECgEJAQAAAA==.',
Zy='Zyenthia:BAAALgADCgYJBgAAAA==.',
['Zô']='Zôhan:BAAALgADCgQJBAAAAA==.',
['Zø']='Zøhan:BAAALgADCgYJBgAAAA==.',
['Äl']='Älcatraz:BAAALgADCgkJFQABLgAECgYJDwABAAAAAA==.',
['Îs']='Îsh:BAAALgAECgUJBQAAAA==.',
['Ör']='Örgrim:BAACLgAFFH8QAAIMAAUJhCVBAgDEAQAMAAUJhCVBAgDEAQAuAAQKfzcAAgwACQn+JMIBAMcDAAwACQn+JMIBAMcDAAAA.',
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

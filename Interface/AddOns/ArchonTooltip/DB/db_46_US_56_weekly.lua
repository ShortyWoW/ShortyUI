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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Shaman-Elemental','DeathKnight-Unholy','Mage-Frost','Rogue-Assassination','Hunter-BeastMastery','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Devourer','Paladin-Protection','Druid-Feral','Druid-Restoration','Druid-Balance','Rogue-Subtlety','Warrior-Protection','Evoker-Augmentation','Priest-Shadow','Hunter-Marksmanship','Warlock-Destruction','Monk-Brewmaster','Warlock-Affliction','Hunter-Survival','Evoker-Devastation','Druid-Guardian','Priest-Discipline','Priest-Holy',}
local provider = {region='US',realm='Daggerspine',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Aboyton:BAAALgADCgQJBwAAAA==.',
Ac='Acheios:BAAALgAECgIJAgAAAA==.Acinas:BAAALgADCgcJCwAAAA==.Acosadora:BAAALgAECgcJBwAAAA==.',
Ad='Adhpally:BAAALgAECgIJAwABLgAECgYJEwABAAAAAA==.Adurangi:BAAALgADCgQJBAAAAA==.',
Ae='Aefarshammy:BAAALgADCgEJAQAAAA==.Aelaravia:BAAALgAECgMJAwAAAA==.Aerithorn:BAAALgAECggJDgAAAA==.Aethereon:BAAALgADCgYJDQAAAA==.Aethora:BAAALgADCgQJBAABLgAECgYJEAABAAAAAA==.Aethoric:BAAALgAECgYJEAAAAA==.',
Ag='Agirashii:BAAALgADCgUJBwAAAA==.',
Ak='Akoris:BAAALgADCgYJBgABLgAECggJGAACANEQAA==.Akorys:BAABLgAECn8YAAMCAAgJ0RC+IwCXAQACAAgJ0RC+IwCXAQADAAEJOAXqiwAfAAAAAA==.',
Al='Alenci:BAAALgADCgYJCAAAAA==.Alexofor:BAAALgAECgMJAwAAAA==.Alliasterius:BAAALgADCgEJAQAAAA==.Althus:BAAALgAECgcJDwAAAA==.Alturiak:BAABLgAECn8XAAMEAAYJjRYFFgBOAQAFAAUJ1hVSVwBPAQAEAAUJkhYFFgBOAQAAAA==.Alucius:BAAALgAECgEJAgAAAA==.',
Am='Amion:BAAALgADCgMJAwAAAA==.Ammodeus:BAAALgADCgMJAwAAAA==.Amortin:BAAALgADCgUJBQAAAA==.',
An='Andarriel:BAAALgADCgUJBQAAAA==.Anguskhan:BAAALgADCgcJBwAAAA==.Anwir:BAAALgAECgUJDQAAAA==.',
Ap='Apgravessupp:BAAALgADCgEJAQAAAA==.Aph:BAAALgADCgUJBQAAAA==.',
Aq='Aquua:BAABLgAECn8dAAIGAAgJ7xOdBQC8AQAGAAgJ7xOdBQC8AQAAAA==.',
Ar='Araelen:BAAALgAECggJDgAAAA==.Aramann:BAAALgADCgcJDAAAAA==.Archemedes:BAAALgADCgEJAQABLgAFFAEJAQABAAAAAA==.Arcticdps:BAAALgADCgcJDAAAAA==.Ariahn:BAABLgAECn8aAAIHAAgJvQbxEwByAQAHAAgJvQbxEwByAQAAAA==.Ariell:BAAALgAECgEJAQAAAA==.Arkayik:BAAALgADCgEJAQAAAA==.Arnadun:BAAALgADCgEJAQAAAA==.Arnid:BAAALgADCgcJCwAAAA==.Arphazmage:BAABLgAECn8UAAIIAAcJLQfd4gAvAQAIAAcJLQfd4gAvAQAAAA==.Arthimas:BAAALgAECgMJAwAAAA==.Arthuritucus:BAAALgADCgUJBQAAAA==.',
As='Aspenoa:BAAALgAECgYJDAAAAA==.Asralia:BAAALgADCgMJAwAAAA==.Astarthea:BAAALgADCgcJBwAAAA==.',
At='Athaisce:BAAALgAECgYJBQAAAA==.Athalia:BAACLgAFFH8FAAIJAAIJjx9wAwDCAAAJAAIJjx9wAwDCAAAuAAQKfx8AAgkACAnuJGgBABsDAAkACAnuJGgBABsDAAAA.Atlasien:BAAALgAECggJDgAAAA==.',
Au='Aug:BAAALgAECgQJBQAAAA==.Aulayia:BAAALgAECgIJBgAAAA==.Aurellea:BAAALgADCggJEAAAAA==.Auroraplague:BAAALgAECgYJBgAAAA==.',
Av='Avex:BAABLgAECn8nAAIKAAgJvyCNBQAaAgAKAAgJvyCNBQAaAgAAAA==.',
Aw='Awentamis:BAAALgADCgEJAQAAAA==.Awetysmz:BAAALgADCgUJBQAAAA==.',
Ax='Axemage:BAABLgAECn8gAAMIAAgJmxV7GgB2AQAIAAgJIxV7GgB2AQALAAMJPgy+EQCnAAAAAA==.Axeom:BAABLgAECn8rAAMMAAgJ6hGyKgDiAQAMAAgJ6hGyKgDiAQAGAAYJown5EQDzAAAAAA==.Axeshammy:BAAALgAECgUJBQABLgAECggJIAAIAJsVAA==.',
Az='Azazin:BAAALgADCgUJBQAAAA==.Azendethen:BAAALgAECgEJAQAAAA==.Azmodan:BAAALgADCgYJBgAAAA==.Azurewynith:BAAALgADCgYJBgAAAA==.Azzclappius:BAAALgAECgQJBwAAAA==.',
Ba='Badragon:BAAALgAECgQJBAAAAA==.Baelfang:BAAALgADCgIJAgAAAA==.Baelgrim:BAAALgAECgEJAQAAAA==.Bagu:BAABLgAECn8bAAMNAAcJQBj3UADuAQANAAcJQBj3UADuAQAOAAEJkwGQKwAnAAAAAA==.Bahn:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Bajaladin:BAAALgADCgQJAQAAAA==.Bambey:BAAALgADCgMJAwAAAA==.Bandanirn:BAAALgAECgEJAQAAAA==.Bandït:BAAALgAECgQJAwAAAA==.Bangki:BAAALgADCgMJBAAAAA==.Barometer:BAAALgAECgIJAgAAAA==.Bast:BAAALgAECgQJBQABLgAECgYJCwABAAAAAA==.',
Bb='Bbqchips:BAAALgADCgQJBQAAAA==.',
Bc='Bchamp:BAAALgAECgYJEQAAAA==.',
Be='Beamsy:BAAALgADCggJDAABLgAECggJHwAIANEeAA==.Beansoup:BAAALgADCgMJAwAAAA==.Beefmeister:BAAALgAECgcJDwAAAA==.Belamorte:BAAALgAECgEJAQAAAA==.Beliala:BAAALgADCgkJGQAAAA==.Belveth:BAAALgADCgEJAQAAAA==.Benwins:BAAALgAECgUJCQAAAA==.Bertoxxulous:BAAALgADCgIJAgAAAA==.Besus:BAAALgADCgUJCwAAAA==.Beyonddeath:BAAALgADCggJCAAAAA==.',
Bh='Bho:BAAALgADCgYJDAAAAA==.',
Bi='Biffedit:BAAALgAECgUJBwAAAA==.Bisholoyd:BAAALgAECgYJCwAAAA==.Bitshift:BAAALgAECgYJDAAAAA==.Bizoune:BAAALgADCgYJBwAAAA==.',
Bl='Blackwing:BAAALgAECgMJAwAAAA==.Blastoise:BAABLgAECn8YAAMPAAgJWB7aBwCqAgAPAAgJ9R3aBwCqAgAHAAEJ2BenGAFDAAAAAA==.Blathian:BAAALgAECgcJCQAAAA==.Blazakin:BAAALgAECgUJCQAAAA==.Blooms:BAAALgADCgUJBQABLgAECgQJBAABAAAAAA==.Bluntsmasta:BAAALgADCggJEgAAAA==.Blupe:BAAALgADCgkJFAAAAA==.Blutang:BAAALgAECgUJBQAAAA==.Bløøms:BAAALgADCgcJBwABLgAECgQJBAABAAAAAA==.',
Bo='Boaster:BAAALgADCgEJAQAAAA==.Bobadu:BAAALgAECgEJAQAAAA==.Bodhmall:BAAALgAECgYJBgAAAA==.Bongwater:BAAALgAECgIJAwAAAA==.Booktok:BAAALgAECgEJAgAAAA==.Boombóx:BAAALgADCggJCAABLgAECggJHwAQAKAgAA==.Boome:BAAALgAECgYJBgABLgAFFAIJBQAJAI8fAA==.Boonk:BAAALgADCgEJAQAAAA==.Boop:BAAALgADCgYJCQAAAA==.Bootydew:BAAALgADCgcJEgABLgADCgcJFgABAAAAAA==.Bootysama:BAAALgADCgcJFgAAAA==.Boris:BAAALgADCgYJBgAAAA==.Borrax:BAAALgAECgQJBQAAAA==.Borthos:BAABLgAECn8XAAIRAAgJ8BlqCADsAQARAAgJ8BlqCADsAQAAAA==.',
Br='Braetorius:BAAALgAECgYJBgAAAA==.Brewsli:BAAALgADCgQJBAAAAA==.Brickinkeys:BAAALgAECgYJBgABLgAECgYJBgABAAAAAA==.Brynnix:BAAALgADCgUJDAAAAA==.',
Bu='Bugfishleg:BAAALgADCgcJEQAAAA==.Buttardrolls:BAAALgADCgQJBAAAAA==.',
By='Byblethumper:BAAALgADCgEJAQAAAA==.',
['Bà']='Bàne:BAAALgAECgMJAwAAAA==.',
Ca='Caadra:BAAALgADCgUJBQAAAA==.Caarny:BAAALgAECgYJDQAAAA==.Cactusjack:BAAALgAECgYJDQAAAA==.Caimie:BAAALgAECgMJAwAAAA==.Caiste:BAAALgAECgEJAQAAAA==.Candez:BAAALgAECgYJBgAAAA==.Canfar:BAAALgAECgUJDQAAAA==.Cassiaan:BAAALgADCgIJAgAAAA==.Catalog:BAAALgAECgQJBgAAAA==.Cayiane:BAAALgAECgQJBAAAAA==.Caylavibes:BAAALgAECgYJDQAAAA==.',
Ce='Cebola:BAAALgAECgYJDAAAAA==.Cerbaderp:BAAALgAECgMJAwAAAA==.',
Ch='Chackyjan:BAAALgAECgQJBAABLgAECgcJHQASAFodAA==.Chameleos:BAAALgADCgMJAwAAAA==.Chasechases:BAABLgAECn8YAAQTAAcJ5Qr/FwBAAQATAAcJ5Qr/FwBAAQAUAAIJDwbNvQBLAAAVAAEJlQJyjQAhAAAAAA==.Chazyy:BAAALgAECggJEgAAAA==.Cheetasista:BAAALgADCgMJAwAAAA==.Cherry:BAAALgAECgcJDAAAAA==.Chibiusaa:BAAALgADCgUJBQAAAA==.Chiechan:BAAALgADCgMJAwAAAA==.Chimubai:BAAALgAECgYJDwAAAA==.Chokano:BAAALgADCgcJCgAAAA==.Chokeagoat:BAAALgADCgUJBQAAAA==.Chonker:BAAALgAECgEJAQAAAA==.Chor:BAAALgAFFAEJAgAAAA==.Christinei:BAAALgADCgUJBQAAAA==.Chull:BAAALgAECgMJBAAAAA==.',
Ci='Cinderkai:BAAALgADCgQJBAAAAA==.Cinemabunny:BAAALgAECgYJCAAAAA==.Circusfreak:BAAALgAECgcJDgAAAA==.',
Cl='Classified:BAAALgADCgQJBAAAAA==.Cleyl:BAAALgAECgYJDgAAAA==.Clohhe:BAAALgADCgkJIAAAAA==.',
Co='Cokeftw:BAAALgAECgMJBAAAAA==.Coman:BAABLgAECn8gAAMMAAYJeB2ZLgDPAQAMAAYJeB2ZLgDPAQAGAAUJTxNyEgDtAAAAAA==.Consecrated:BAAALgAECgcJAQAAAA==.Cosmochopper:BAABLgAECn8ZAAIDAAcJECJGDQCmAgADAAcJECJGDQCmAgAAAA==.',
Cq='Cq:BAABLgAECn8kAAIRAAgJXhmCNQAiAgARAAgJXhmCNQAiAgAAAA==.',
Cr='Cremebrule:BAAALgAECgEJAQAAAA==.Cremesodax:BAABLgAECn8UAAINAAYJ7Q5JnQBEAQANAAYJ7Q5JnQBEAQAAAA==.Cringeknight:BAAALgAECgcJEQAAAA==.Critjutsu:BAABLgAECn8UAAICAAcJ2iIYEgBBAgACAAcJ2iIYEgBBAgAAAA==.Croces:BAAALgAECgUJDgABLgAECgcJCwABAAAAAA==.Crushleaf:BAAALgADCgMJAwAAAA==.',
Cu='Cuppanoods:BAAALgADCgYJCgAAAA==.',
Cy='Cyndra:BAAALgAECgQJBQAAAA==.',
Da='Dadonut:BAAALgAECgYJBgAAAA==.Daemonspawnn:BAAALgADCgIJAgAAAA==.Dalthyriian:BAABLgAECn8dAAIRAAYJQxlVTgC8AQARAAYJQxlVTgC8AQAAAA==.Damii:BAAALgADCgUJDAAAAA==.Dandissima:BAAALgAECgMJAwAAAA==.Danny:BAAALgADCgEJAQAAAA==.Dargonbref:BAAALgADCgUJBQABLgAECggJIQAHANwRAA==.Darjen:BAAALgAECgYJCAAAAA==.Darkjestêr:BAAALgAECgIJAgAAAA==.Darthra:BAAALgADCgkJHQAAAA==.Darthsteak:BAAALgADCgMJAwAAAA==.Dasblur:BAABLgAECn8fAAIRAAgJahvvLQBFAgARAAgJahvvLQBFAgAAAA==.Dawncygnu:BAAALgADCgUJBQAAAA==.',
Dc='Dcash:BAABLgAECn8dAAINAAYJthIOgwB0AQANAAYJthIOgwB0AQAAAA==.Dcashcrafter:BAAALgADCgMJAwAAAA==.',
De='Deadlyarrow:BAAALgAECggJEQAAAA==.Deadsilenth:BAAALgADCgcJDgAAAA==.Deamonessa:BAAALgAECgMJAwAAAA==.Deathfang:BAAALgADCgMJAwAAAA==.Deathlyy:BAABLgAECn8dAAIWAAgJRhkAHgAOAgAWAAgJRhkAHgAOAgAAAA==.Deathtress:BAAALgADCgUJBQAAAA==.Deatlas:BAAALgAECgYJBwAAAA==.Debbydowner:BAAALgAECgYJDgAAAA==.Decado:BAAALgAECgYJCwAAAA==.Delnir:BAAALgADCgQJBwAAAA==.Demonroo:BAAALgADCgYJCQAAAA==.Denimdan:BAABLgAECn8fAAIXAAgJjhx9CACZAgAXAAgJjhx9CACZAgAAAA==.Desetaz:BAAALgADCgMJAwAAAA==.Desetren:BAAALgAECgMJAwAAAA==.Devinedrama:BAAALgAECgYJBwAAAA==.',
Dh='Dhawk:BAAALgAECgYJDAAAAA==.',
Di='Digkdug:BAAALgADCgQJCQAAAA==.Distance:BAAALgADCgcJBwAAAA==.Dizzypal:BAAALgADCgQJBQAAAA==.',
Dk='Dkalliru:BAABLgAECn8WAAMPAAgJKBnuAgDRAQAPAAgJKBnuAgDRAQAHAAYJsQNeyADyAAAAAA==.Dkisop:BAAALgAECgEJAQAAAA==.Dkpuff:BAAALgAECgYJEgAAAA==.',
Do='Docdolittle:BAAALgAECgYJEQABLgAECgYJFAAIAIAZAA==.Docfreez:BAABLgAECn8fAAIIAAgJ0R4kIgDqAgAIAAgJ0R4kIgDqAgAAAA==.Docfrosty:BAABLgAECn8UAAIIAAYJgBnMjgC1AQAIAAYJgBnMjgC1AQAAAA==.Docragosa:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Docrighteous:BAAALgAECgUJCQABLgAECgYJFAAIAIAZAA==.Doctafury:BAAALgAECgQJBAABLgAECgYJFAAIAIAZAA==.Dogar:BAAALgADCgIJAgAAAA==.Doggomasta:BAAALgAECgEJAQAAAA==.Doomhamer:BAAALgADCgYJBgABLgAECggJFwARAPAZAA==.Doraemee:BAAALgAECgYJCwAAAA==.Doraleous:BAAALgADCgQJBAAAAA==.Doresaingk:BAAALgADCgEJAQAAAA==.Dorllian:BAAALgADCgEJAQAAAA==.',
Dr='Drablooms:BAAALgAECgQJBAAAAA==.Dracotriface:BAAALgAECgEJAQAAAA==.Drahk:BAAALgADCggJCAAAAA==.Drain:BAAALgAECgcJAQAAAA==.Dravenholy:BAAALgAECgEJAQAAAA==.Drbaobuns:BAAALgAECgYJCAABLgAECggJEAABAAAAAA==.Drboomnugget:BAAALgADCgcJBwAAAA==.Dreamerdr:BAAALgAECgUJBQAAAA==.Dreidel:BAAALgADCgQJBAAAAA==.Dreim:BAEALgAECgEJAQABLgAECggJKgANAA8mAA==.Drezdorn:BAAALgAECgEJAgAAAA==.Drgatorwine:BAAALgADCgUJBQABLgAECggJEAABAAAAAA==.Drizdourden:BAAALgAECgEJAQAAAA==.Drjp:BAAALgAECgQJBAAAAA==.Drkimchirice:BAAALgAECgQJBQABLgAECggJEAABAAAAAA==.Drlocktapus:BAABLgAECn8hAAIQAAgJNhz8LwBNAgAQAAgJNhz8LwBNAgAAAA==.Drmacncheese:BAAALgAECgYJBwABLgAECggJEAABAAAAAA==.Drpumpkinpie:BAAALgADCgcJDAABLgAECggJEAABAAAAAA==.Drugzone:BAAALgAECgYJDwAAAA==.Drwontonsoup:BAAALgAECggJEAAAAA==.',
Du='Duddyfuddy:BAAALgAECgMJAwAAAA==.Duiunit:BAAALgADCgYJBQAAAA==.Dumblìedore:BAAALgAECgIJAgAAAA==.Dummythicc:BAAALgAECgMJBQAAAA==.',
Dw='Dwag:BAAALgADCgcJDAAAAA==.',
Dx='Dxmxt:BAAALgADCgEJAQAAAA==.',
Dy='Dye:BAAALgAECgMJBAAAAA==.',
Ea='Earthhammer:BAAALgAECggJCQAAAA==.Easyy:BAABLgAECn8VAAIUAAYJ+xQ6TwBoAQAUAAYJ+xQ6TwBoAQAAAA==.',
Ec='Ecthdaran:BAAALgAFFAEJAQAAAA==.',
Ed='Edoras:BAAALgADCgcJDQAAAA==.',
Ef='Efton:BAAALgAECgQJBAAAAA==.',
Ek='Eksi:BAAALgAECgUJCAAAAA==.',
El='Elemjae:BAAALgADCgEJAQABLgAECgcJGgAGAH8fAA==.Elethe:BAAALgADCgkJDAABLgAECgUJDQABAAAAAA==.Elftastic:BAAALgAECgUJBQABLgAFFAUJCAAIANsVAA==.Eliorian:BAAALgADCgUJBQAAAA==.Elivan:BAAALgADCgEJAQAAAA==.Elizebet:BAAALgADCgYJCQAAAA==.Elladria:BAAALgADCgMJAwAAAA==.Ellicit:BAAALgADCgMJAwAAAA==.Elzaine:BAABLgAECn8VAAINAAgJ+SBZHgC1AgANAAgJ+SBZHgC1AgAAAA==.',
Em='Emis:BAAALgADCgQJBwAAAA==.Emporic:BAAALgADCgUJBQAAAA==.Empress:BAAALgAECgUJBQAAAA==.',
En='Enhae:BAAALgADCgUJBQAAAA==.Entrophi:BAAALgAECgEJAQABLgAECgcJEwABAAAAAA==.Entropi:BAABLgAECn8bAAIYAAgJxRB3BgCRAQAYAAgJxRB3BgCRAQAAAA==.Envys:BAAALgAFFAEJAQAAAA==.Envyspal:BAAALgAECgQJCAAAAA==.',
Er='Erisnyx:BAAALgAECgkJAQAAAA==.',
Es='Esterelore:BAAALgAECgIJAgAAAA==.',
Et='Etherwing:BAAALgAECgcJEwAAAA==.',
Ev='Evilwwink:BAAALgAECgEJAQAAAA==.',
Ex='Excruciator:BAAALgAECgQJBQAAAA==.Excruciators:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Ez='Ezrabridger:BAAALgAECgMJAgAAAA==.Ezranim:BAAALgADCgYJBgAAAA==.',
Fa='Falloutz:BAAALgAECgMJAwAAAA==.Falloutzhunt:BAAALgADCggJCAABLgAECgMJAwABAAAAAA==.Faschlangus:BAAALgADCgEJAQAAAA==.Fatcows:BAAALgAECgQJBQAAAA==.Fawxette:BAAALgADCgcJEAABLgAECggJIAARAAMWAA==.',
Fe='Felger:BAAALgADCgMJAwAAAA==.Felintovoid:BAABLgAECn8bAAIRAAgJfxI5WQCWAQARAAgJfxI5WQCWAQAAAA==.Feliya:BAAALgAECgEJAQAAAA==.Fengami:BAAALgADCgEJAQAAAA==.Fenridinn:BAAALgADCgYJCQAAAA==.Fesha:BAAALgADCgEJAQABLgAECgQJBwABAAAAAA==.',
Fi='Fieryfrost:BAAALgADCgcJBwABLgAECgYJEQABAAAAAA==.Finowscath:BAAALgAECgEJAQAAAA==.Fistdoc:BAAALgAECgQJDQABLgAECgYJDQABAAAAAA==.Fistynae:BAABLgAECn8ZAAMDAAgJhRbIAwDTAQADAAgJhRbIAwDTAQACAAYJjRu2HADSAQAAAA==.Fizzlesaurus:BAAALgAECgYJCwAAAA==.',
Fl='Flamelece:BAAALgAECgIJAgABLgAECgYJEgABAAAAAA==.Fleshmaw:BAAALgADCgUJAwAAAA==.Flexorcist:BAAALgADCgYJBwAAAA==.Floo:BAAALgAECgEJAQAAAA==.Floralas:BAAALgAECgYJCwAAAA==.',
Fo='Forseer:BAAALgADCgYJBgAAAA==.Foxjìtsu:BAAALgADCgEJAQAAAA==.Foxybag:BAAALgADCgMJBAAAAA==.Foxytotes:BAAALgADCgYJBgAAAA==.',
Fr='Frickenmage:BAAALgAECgUJCwAAAA==.Friendlypal:BAAALgAECgcJDwAAAA==.Friendofbear:BAABLgAECn8jAAIKAAkJFha0IQA7AgAKAAkJFha0IQA7AgAAAA==.Frogo:BAAALgADCgMJAwAAAA==.',
Fu='Fudomeow:BAAALgADCgMJAwAAAA==.Fumazusha:BAAALgADCgIJAgAAAA==.Fumblebuck:BAAALgADCgkJGQABLgAECgQJBAABAAAAAA==.Funshíne:BAAALgADCgcJBwAAAA==.Furrybutted:BAAALgADCgcJAQAAAA==.Furryfeet:BAAALgAECgYJCAAAAA==.Furyofdawn:BAAALgAECgEJAQAAAA==.Fuzzpuff:BAAALgADCgMJBAAAAA==.Fuzzykuntz:BAAALgAECggJDgAAAA==.',
Fy='Fynsdood:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.Fynslane:BAAALgAECgYJEQAAAA==.',
Ga='Garchomp:BAAALgAECgEJAQAAAA==.',
Gh='Ghostreveri:BAABLgAECn8gAAINAAgJuBinCQDxAQANAAgJuBinCQDxAQAAAA==.Ghoulface:BAAALgAECgQJBQABLgAFFAUJCgAQAKkVAA==.',
Gi='Gigah:BAAALgAECgYJCgAAAA==.Gildin:BAAALgAECgYJCQAAAA==.Gingerbell:BAAALgADCgcJFwAAAA==.',
Gl='Global:BAAALgADCgcJCgAAAA==.Glopthethird:BAAALgADCgYJBgAAAA==.Glorpnotl:BAAALgAECgUJBQAAAA==.',
Gn='Gnomedalf:BAAALgAECgEJAQAAAA==.Gnomedguerre:BAAALgADCgMJAwAAAA==.',
Go='Goatstatik:BAAALgAECgQJBQAAAA==.Goblinface:BAAALgADCgUJBQAAAA==.Gollie:BAAALgAECgEJAQAAAA==.Gooblash:BAAALgAECgEJAQAAAA==.Goonerrofoz:BAAALgAECgUJDQAAAA==.Goonnugget:BAAALgAECgUJBwAAAA==.Gorthmog:BAAALgADCgQJBwAAAA==.',
Gr='Grampysmack:BAAALgADCggJEAAAAA==.Gravefeet:BAAALgADCgUJBQAAAA==.Gravehands:BAAALgADCgIJAgAAAA==.Gredory:BAAALgAECgYJCgAAAA==.Greendoritos:BAAALgAECgQJBgAAAA==.Grekum:BAAALgAECgQJCAAAAA==.Grep:BAAALgADCgEJAQAAAA==.Grimtree:BAAALgAECgcJEwAAAA==.Grindor:BAAALgADCgMJBQAAAA==.Grogge:BAAALgADCgIJAgAAAA==.Grumpstraza:BAAALgAECgEJAQAAAA==.Grumpydemon:BAAALgAECgcJDAAAAA==.',
Gu='Guglugauthu:BAAALgAECgYJDgAAAA==.Gunwald:BAAALgADCgUJBQAAAA==.Gutcheck:BAAALgAECgcJEgAAAA==.',
Gw='Gwong:BAAALgADCgcJBwAAAA==.',
Gy='Gyo:BAAALgADCgcJBgAAAA==.Gyodo:BAAALgADCgMJAwAAAA==.Gyodoh:BAAALgADCgkJDwAAAA==.',
['Gö']='Gökû:BAAALgADCgUJBQAAAA==.',
Ha='Haaravende:BAAALgADCgUJBQAAAA==.Halfskul:BAABLgAECn8nAAIHAAgJ8hzlLACFAgAHAAgJ8hzlLACFAgAAAA==.Halinis:BAAALgAECgUJCAAAAA==.Halvorse:BAAALgADCgMJAwAAAA==.Harandi:BAAALgADCgEJAQAAAA==.Harugokken:BAAALgADCgYJBgAAAA==.Hasha:BAAALgADCgYJBgAAAA==.Hashah:BAAALgAECgYJDAAAAA==.Hatefel:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.Haveblue:BAAALgADCggJCAAAAA==.Havoke:BAAALgADCgMJAwAAAA==.',
He='Healsgobrr:BAAALgAECgkJCQABLgAECgkJIQAYAMMaAA==.Hellscar:BAAALgAECgEJAQAAAA==.Herakleitos:BAAALgADCgMJAwAAAA==.Hereticdoc:BAAALgAECgYJDQAAAA==.Herrah:BAAALgADCgcJDAAAAA==.Hesha:BAAALgAECgUJDgABLgAECgYJDAABAAAAAA==.Heytotemman:BAAALgAECgUJCQAAAA==.',
Ho='Holydingi:BAAALgADCgMJBQAAAA==.Holygrammy:BAAALgADCgcJCwABLgAECgYJCAABAAAAAA==.Holyligth:BAAALgAECgQJBwAAAA==.Holysock:BAAALgADCgcJBwAAAA==.Holyyaii:BAABLgAECn8VAAIZAAYJ7h78BwB6AQAZAAYJ7h78BwB6AQAAAA==.Holz:BAAALgAECgQJBAAAAA==.Hoodedpando:BAAALgAECgQJDAAAAA==.Hopsing:BAAALgAECgQJDwAAAA==.Hornychicken:BAAALgADCgEJAQABLgAECgQJBQABAAAAAA==.Horsetowater:BAAALgAECgUJBQAAAA==.Hotsluttymom:BAAALgAECgYJEgAAAA==.',
Hu='Hugoman:BAABLgAECn8YAAIQAAYJLRBHHAA3AQAQAAYJLRBHHAA3AQABLgAECggJHAAHAFgWAA==.Huntbugman:BAABLgAECn8WAAIKAAgJ+Q9mMwDiAQAKAAgJ+Q9mMwDiAQAAAA==.Hurash:BAAALgAECgMJAwABLgAECgcJHQASAFodAA==.Hurdtfeeling:BAAALgAECgcJDQAAAA==.',
['Hö']='Hölyheals:BAAALgADCgcJBwAAAA==.',
Ib='Ibun:BAAALgAECgYJCgAAAA==.',
Ic='Icebøx:BAAALgAECgEJAQAAAA==.Icetomeetu:BAAALgADCgYJBgAAAA==.',
Ii='Iillil:BAABLgAECn8iAAIRAAgJEAaCIgD7AAARAAgJEAaCIgD7AAAAAA==.',
Il='Illtul:BAABLgAECn8aAAIVAAgJWhbIGwAkAgAVAAgJWhbIGwAkAgAAAA==.',
Im='Imblindhelp:BAAALgAECgYJBgAAAA==.Imnotyourpal:BAAALgAECgUJCgAAAA==.Imscratchy:BAAALgADCgQJBAAAAA==.Imsweaty:BAAALgAECgkJBwAAAA==.Imzaiahfur:BAAALgAECgQJBQAAAA==.',
In='Ingraham:BAAALgADCgEJAQAAAA==.',
Ip='Ipwoman:BAAALgAECgYJEAAAAA==.',
Is='Ishint:BAAALgADCgUJBQAAAA==.Isokie:BAAALgADCgIJAgAAAA==.',
It='Itwasmedio:BAAALgAECgQJCQAAAA==.Itzitar:BAAALgADCgcJCgAAAA==.',
Iv='Ivyiina:BAAALgAECgMJCQAAAA==.',
Ja='Jaeyk:BAAALgAECgcJAQAAAA==.Jamescameron:BAAALgAECgIJAwAAAA==.Jarninn:BAAALgADCgYJDAAAAA==.Jaywaz:BAAALgAECgMJAgAAAA==.',
Jc='Jck:BAABLgAECn8eAAIIAAgJ3CFAAwCYAgAIAAgJ3CFAAwCYAgAAAA==.',
Je='Jedsezir:BAAALgAECgIJAgAAAA==.Jessirra:BAAALgAECgEJAQAAAA==.Jessupy:BAAALgAECgUJCAAAAA==.Jezebelz:BAAALgADCggJEgAAAA==.',
Ji='Jimmyhot:BAABLgAECn8gAAIIAAgJ5iPgDwBJAwAIAAgJ5iPgDwBJAwAAAA==.Jimmyx:BAAALgAECgUJBQABLgAECggJIAAIAOYjAA==.Jimsywimsy:BAAALgAECgYJCwAAAA==.Jingae:BAAALgADCgQJBAAAAA==.Jirikka:BAAALgADCgEJAQAAAA==.',
Jo='Joshmrx:BAAALgADCgcJBwAAAA==.',
Jr='Jracó:BAAALgAECgkJEwAAAA==.',
Ju='Juliettestar:BAAALgADCgEJAQAAAA==.Julz:BAAALgAECgYJDwAAAA==.Junepoon:BAAALgADCgIJAgAAAA==.Justiz:BAAALgAECgIJAgAAAA==.',
Jw='Jwarf:BAAALgADCgYJEQAAAA==.',
['Jø']='Jøsh:BAAALgAECgYJEwAAAA==.',
Ka='Kainga:BAAALgAECgMJAwAAAA==.Kalrendion:BAAALgAECggJDgAAAA==.Kalru:BAAALgAECgMJAwAAAA==.Kalrufu:BAAALgAECgcJEgAAAA==.Kalzok:BAAALgADCgYJBwAAAA==.Kamuela:BAAALgAECgIJAgAAAA==.Kaptonkronic:BAAALgAECgMJAwAAAA==.Karaillyonna:BAAALgADCgcJBwABLgAECgYJCwABAAAAAA==.Karasu:BAAALgAECgQJBwAAAA==.Karsiis:BAAALgAECgQJBAAAAA==.Kasion:BAAALgAECgUJBQAAAA==.',
Ke='Keewenaw:BAAALgAECgYJCgAAAA==.Kelsier:BAABLgAECn8cAAICAAgJJyKJAQCVAgACAAgJJyKJAQCVAgAAAA==.Kerelor:BAAALgADCgcJDAAAAA==.Kesk:BAAALgAECgQJBAAAAA==.',
Kh='Khaosbringer:BAAALgAECgEJAQAAAA==.Khaosdragon:BAAALgADCgUJBQABLgAECgMJBAABAAAAAA==.Khaosstormz:BAAALgAECgMJBAAAAA==.',
Ki='Kilavman:BAAALgADCgUJBQAAAA==.Killachefd:BAAALgAECgYJDwAAAA==.Killamanjoro:BAAALgAECgEJAQAAAA==.Killerbow:BAAALgADCgMJAwAAAA==.Kimchiwar:BAAALgAECgYJEgAAAA==.Kirasha:BAAALgAECgYJDAAAAA==.Kitchenbound:BAAALgAECgYJCwAAAA==.Kittychan:BAABLgAECn8cAAIHAAgJWBb/RQAiAgAHAAgJWBb/RQAiAgAAAA==.',
Kl='Klaacus:BAABLgAECn8aAAIRAAgJfBQiPwD3AQARAAgJfBQiPwD3AQAAAA==.Kluath:BAAALgADCgcJBwAAAA==.',
Ko='Kodakdh:BAAALgAECgYJDAAAAA==.Kongol:BAAALgADCgUJBQAAAA==.Kongól:BAAALgAECgUJBQAAAA==.Koriten:BAAALgADCgMJBgAAAA==.Koschei:BAAALgADCgcJFAAAAA==.Koudelka:BAAALgAECgcJDwAAAA==.',
Kp='Kpa:BAAALgADCgcJBwAAAA==.Kpg:BAAALgAECgcJEwAAAA==.',
Kr='Krilde:BAAALgAECgEJAQAAAA==.Kringelord:BAAALgAECgUJBQAAAA==.Kriticál:BAAALgAECgQJBAAAAA==.Kroshivecna:BAAALgAECgYJCwAAAA==.Krustym:BAAALgADCgUJCgAAAA==.',
Ku='Kurapika:BAAALgAECgIJAgAAAA==.Kuurun:BAEALgAECgYJBwABLgAECggJKgANAA8mAA==.',
Ky='Kyout:BAAALgAECggJEgAAAA==.',
La='Laeina:BAAALgADCgUJBQAAAA==.Lamerehela:BAAALgADCgYJBgAAAA==.Lazystorm:BAAALgAECgkJDwAAAA==.',
Le='Leadfeet:BAAALgAECgEJAwAAAA==.Legiohn:BAAALgADCgEJAQAAAA==.Lelou:BAACLgAFFH8NAAMKAAQJ2BabAwBQAQAKAAQJUA+bAwBQAQAaAAMJSRlKFAD8AAAuAAQKfyMAAwoACAlrIGELALUBABoABwmZH6cfACUCAAoABwlTG2ELALUBAAAA.Lemartes:BAAALgADCgEJAgAAAA==.Lemmys:BAAALgADCgYJCwAAAA==.Lemoncookie:BAAALgAECgQJBgAAAA==.Lemondropped:BAAALgAECgEJAQAAAA==.Lemonsquueze:BAAALgADCgMJAgAAAA==.',
Li='Lilathiaa:BAAALgAECgYJDAAAAA==.Lilith:BAAALgAECgEJAQAAAA==.Lillymae:BAAALgAECgYJCwAAAA==.Lilshama:BAAALgADCgEJAgAAAA==.Lilsmushy:BAAALgAECgYJEAAAAA==.Limpdoodle:BAAALgADCgQJBAAAAA==.Linuspelt:BAAALgADCgcJDQAAAA==.Linuzs:BAAALgADCgQJBAAAAA==.Liondori:BAAALgAECgYJEwAAAA==.Lissindra:BAAALgAECgEJAQAAAA==.Lizardlad:BAAALgADCgYJBgAAAA==.Lizzang:BAAALgADCgUJBQAAAA==.',
Lm='Lmj:BAABLgAECn8aAAIGAAcJfx/uAgAcAgAGAAcJfx/uAgAcAgAAAA==.',
Lo='Lobsterfest:BAAALgAECgYJBgAAAA==.Lockbox:BAABLgAECn8fAAMQAAgJoCDkOwAdAgAQAAYJmSDkOwAdAgAbAAMJyh+IKAAhAQAAAA==.Lockngood:BAAALgAECgEJAQAAAA==.Lohrufal:BAAALgADCggJDQAAAA==.Lombotamy:BAAALgADCgMJAwAAAA==.Longboardpr:BAAALgADCgYJCgAAAA==.Loomin:BAACLgAFFH8IAAIIAAUJ2xU/DQCxAQAIAAUJ2xU/DQCxAQAuAAQKfx4AAggACAkDI/0TADADAAgACAkDI/0TADADAAAA.Lorendris:BAAALgADCgMJAwAAAA==.',
Lu='Luckymoo:BAAALgAECgQJCAAAAA==.Lukrid:BAAALgADCgIJAgAAAA==.Lumiru:BAAALgADCgYJBgAAAA==.Lumièrevide:BAAALgAECgYJCwAAAA==.',
['Lä']='Lädyæk:BAAALgAECggJEwAAAA==.',
['Lì']='Lìfealèrt:BAAALgADCgcJCQAAAA==.',
Ma='Macalor:BAAALgAECgUJDQAAAA==.Madagna:BAAALgADCgcJCQAAAA==.Madboy:BAAALgADCgcJEAAAAA==.Magicwinky:BAAALgADCgYJBgABLgAECgEJAQABAAAAAA==.Mahmba:BAAALgAECgMJAwAAAA==.Makati:BAAALgADCgYJCQAAAA==.Mallidin:BAAALgAECgUJCgAAAA==.Malthoryn:BAAALgAECgYJEwAAAA==.Mamamercy:BAAALgAECgYJCgAAAA==.Mardys:BAAALgAECgMJBAAAAA==.Marisol:BAAALgAECgQJCQAAAA==.Mastabazzi:BAAALgADCgEJAgAAAA==.',
Me='Meal:BAAALgAECgYJDAAAAA==.Mechamike:BAAALgAECgYJDwAAAA==.Melodí:BAAALgAECgEJAQABLgAECgYJFwAcAI8RAA==.Melorac:BAAALgAECgYJDwAAAA==.Mem:BAABLgAECn8eAAMdAAcJzxxXAQCQAQAdAAcJzxxXAQCQAQAQAAQJEw1NwADYAAAAAA==.Meowor:BAAALgADCgUJBQABLgAECgkJFQACADgiAA==.Merope:BAAALgADCgUJBQAAAA==.Mertence:BAAALgADCgYJEAAAAA==.Mesandera:BAAALgAECgYJCwAAAA==.',
Mh='Mheow:BAAALgAECgIJAgAAAA==.',
Mi='Miccivxx:BAABLgAECn8YAAIKAAgJQhSdNQDYAQAKAAgJQhSdNQDYAQAAAA==.Microch:BAAALgADCgYJDgAAAA==.Midnightsham:BAAALgADCggJDQAAAA==.Midnightsun:BAABLgAECn8dAAIMAAgJLRIkDAB7AQAMAAgJLRIkDAB7AQAAAA==.Mikeoochie:BAAALgAECgEJAQAAAA==.Mimiche:BAAALgAECgUJCwAAAA==.Minxyrae:BAABLgAECn8eAAIOAAUJ3xJXDwBHAQAOAAUJ3xJXDwBHAQAAAA==.Miorine:BAACLgAFFH8LAAIQAAUJpQ2kCQCSAQAQAAUJpQ2kCQCSAQAuAAQKfyEAAhAACAn/IPocAKgCABAACAn/IPocAKgCAAAA.Misamane:BAAALgADCgYJCAAAAA==.Mitufu:BAAALgADCgcJDAAAAA==.',
Mj='Mjernamir:BAAALgAECgYJDwAAAA==.',
Mo='Moistson:BAAALgAECgUJCQAAAA==.Mom:BAABLgAECn8UAAIQAAcJkxTMHQAuAQAQAAcJkxTMHQAuAQAAAA==.Momie:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monknugget:BAAALgAECggJDwAAAA==.Moofrosty:BAAALgAECgEJAgAAAA==.Moonish:BAAALgADCggJHwABLgAECgcJGQAOAC0mAA==.Moonrupal:BAAALgAECgQJCQAAAA==.Moonwarden:BAAALgADCgcJBwAAAA==.Mordokk:BAAALgAECgYJEgAAAA==.Morganya:BAABLgAECn8gAAIRAAgJAxawPwD1AQARAAgJAxawPwD1AQAAAA==.Morgañya:BAAALgAECgMJBwABLgAECggJIAARAAMWAA==.Morgul:BAAALgAECgYJCwAAAA==.Morphz:BAAALgAECgQJBAAAAA==.Morrtis:BAAALgADCgQJBAAAAA==.Mortics:BAAALgADCgMJAwAAAA==.Mortishaa:BAABLgAECn8WAAIdAAYJNxL1CwB6AQAdAAYJNxL1CwB6AQAAAA==.Moundask:BAAALgADCgEJAgAAAA==.',
Mu='Muchplague:BAABLgAECn8hAAIHAAgJ3BFTDQCzAQAHAAgJ3BFTDQCzAQAAAA==.Muddbut:BAAALgADCgcJDAAAAA==.Mutagenooze:BAAALgADCgUJDgAAAA==.Muwoo:BAAALgAECgEJAQAAAA==.',
My='Mycowgoesmoo:BAAALgADCgkJDwAAAA==.Mynnu:BAAALgADCgcJCQAAAA==.',
Na='Nachoproblem:BAAALgAECgEJAQAAAA==.Naeuh:BAABLgAECn8cAAIKAAgJVhIUCwC5AQAKAAgJVhIUCwC5AQAAAA==.Nahadotha:BAAALgAECgEJAQAAAA==.Nanako:BAAALgAECgMJAwAAAA==.Nance:BAABLgAECn8gAAIQAAgJCCHsEADzAgAQAAgJCCHsEADzAgAAAA==.Narasong:BAAALgAECgEJAQAAAA==.Naraysta:BAABLgAECn8iAAIHAAgJpRffRwAcAgAHAAgJpRffRwAcAgAAAA==.Nasan:BAAALgAECgQJBAAAAA==.Nathette:BAAALgAECgcJCgAAAA==.Nautprepared:BAAALgADCgkJFgAAAA==.',
Ne='Necrofêêlya:BAAALgADCgEJAQAAAA==.Neeck:BAAALgAECgEJAQAAAA==.Needhealz:BAABLgAECn8eAAIOAAgJHR2FAwBKAgAOAAgJHR2FAwBKAgAAAA==.Neildasstysn:BAABLgAECn8ZAAIeAAgJbxkcCQBQAgAeAAgJbxkcCQBQAgAAAA==.Nephey:BAAALgADCgUJBgAAAA==.Neveya:BAAALgADCgYJCAAAAA==.Newwing:BAAALgADCggJDQAAAA==.',
Ni='Niavka:BAAALgADCgUJBQAAAA==.Nickeld:BAAALgAECgYJDwAAAA==.Nickerfritz:BAAALgAECgUJCQAAAA==.Nickhy:BAAALgAECgMJAwAAAA==.Nietherme:BAAALgAECgYJDgAAAA==.Nihildicits:BAAALgADCgIJAgAAAA==.Niverrø:BAAALgAECgYJDwABLgAECggJIwAWAHAZAA==.',
No='Noahmedlock:BAAALgADCgUJBQAAAA==.Noblefiend:BAAALgADCgMJAwAAAA==.Nodnardd:BAAALgAECgMJBAAAAA==.Noirwyn:BAAALgADCgYJBgAAAA==.Nokomu:BAAALgADCgcJDAAAAA==.Noliee:BAAALgAECgEJAgAAAA==.Noluckjay:BAAALgADCgcJBwAAAA==.Noodie:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.Noogra:BAAALgADCgEJAQAAAA==.Norinithedra:BAAALgAECgMJAwAAAA==.Nossavaria:BAAALgADCgEJAQAAAA==.Noxis:BAAALgAECgQJBwAAAA==.',
Nu='Nulva:BAAALgADCgYJCAAAAA==.',
Ny='Nyagosa:BAAALgAECggJEgAAAA==.Nyalore:BAAALgAECggJCQAAAA==.Nymesys:BAAALgADCgYJCQAAAA==.',
Oa='Oakencrush:BAAALgADCgEJAQAAAA==.',
Ol='Olia:BAAALgADCgIJAgAAAA==.Oluhegar:BAAALgADCgIJAgAAAA==.',
Om='Omnimon:BAAALgADCgEJAQABLgAECggJGAAMAIElAA==.',
Oq='Oquaellii:BAAALgAECgQJCgAAAA==.',
Or='Oralen:BAACLgAFFH8GAAIOAAMJ3RFjBgDsAAAOAAMJ3RFjBgDsAAAuAAQKfxsAAg4ACAmFGPsgABQCAA4ACAmFGPsgABQCAAAA.Orangedorito:BAAALgAECgQJBAAAAA==.Orcthas:BAAALgAECgQJBAABLgAFFAUJDQANABUeAA==.Ordola:BAABLgAECn8ZAAICAAcJ8ByrFwADAgACAAcJ8ByrFwADAgAAAA==.Orlorian:BAAALgAECgEJAQAAAA==.',
Ot='Othneil:BAAALgADCgMJAwAAAA==.',
Ou='Outtlawz:BAAALgADCgEJAQAAAA==.',
Ov='Overloader:BAABLgAECn8hAAIRAAcJGxy+RwDVAQARAAcJGxy+RwDVAQAAAA==.',
Pa='Painreaver:BAEBLgAECn8oAAIRAAkJ+hEqNgAeAgARAAkJ+hEqNgAeAgAAAA==.Palahang:BAAALgADCgIJAgAAAA==.Palimax:BAAALgAECgEJAQAAAA==.Pallyaxe:BAAALgAECgUJBwABLgAECggJIAAIAJsVAA==.Pallygank:BAAALgADCgIJAgAAAA==.Pallysin:BAAALgADCgMJBAAAAA==.Pamn:BAAALgADCgUJBQAAAA==.Pancandy:BAAALgAECgMJAwAAAA==.Paneer:BAAALgAECgQJCQAAAA==.Parryhottër:BAAALgADCgMJAQAAAA==.Pascel:BAAALgAECgYJDwAAAA==.',
Pe='Pebbletoe:BAAALgADCgUJBwAAAA==.Penta:BAAALgAECgMJAwAAAA==.Percgripper:BAAALgAECgUJBAABLgAECgcJEwABAAAAAA==.Percivis:BAAALgADCgEJAQAAAA==.Perida:BAAALgAECgEJAQAAAA==.Peronarth:BAAALgADCgIJAgAAAA==.Peruano:BAAALgAECgcJBgAAAA==.Petforheals:BAAALgAECgIJAgAAAA==.',
Ph='Phouy:BAAALgADCgIJAgAAAA==.Phyoo:BAAALgAECgUJDQAAAA==.',
Pi='Picken:BAEALgADCgEJAQABLgAECggJKgANAA8mAA==.',
Pk='Pkrippa:BAAALgADCgcJCAAAAA==.',
Pl='Plu:BAAALgAECgUJDQAAAA==.',
Po='Pocahöntas:BAAALgADCgUJBQAAAA==.Pogie:BAAALgADCgUJBQAAAA==.Polkagay:BAAALgAECgIJAwAAAA==.Portick:BAAALgADCgEJAQAAAA==.Posttmasterz:BAAALgAECgQJBAAAAA==.',
Pr='Protrunkey:BAAALgAECgEJAQAAAA==.Provolonie:BAAALgAECgYJDQAAAA==.',
Pu='Puppiboi:BAAALgADCggJCQAAAA==.Puritos:BAAALgAECgQJCgAAAA==.Pushti:BAAALgADCgYJBgAAAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Py='Pyrista:BAAALgAECgYJEAAAAA==.',
Qe='Qeikli:BAAALgADCgEJAgAAAA==.',
Qo='Qortethhunt:BAAALgAECgEJAQAAAA==.',
Qu='Quackapls:BAAALgAECgQJBAAAAA==.Quaratus:BAAALgAECgQJBAAAAA==.',
Ra='Raendarth:BAAALgAECgUJCQAAAA==.Rageslave:BAAALgAECggJDwAAAA==.Rageth:BAABLgAECn8VAAMfAAYJgRHuIAAlAQAfAAUJbxPuIAAlAQAYAAIJpQiOGgBmAAAAAA==.Ragnarule:BAAALgAECgIJAgAAAA==.Ragnol:BAAALgAECgQJBQAAAA==.Rakalaag:BAEALgADCgEJAQAAAA==.Rakath:BAAALgAECgYJEgAAAA==.Ramchi:BAAALgAECgUJBwAAAA==.Ramlethal:BAAALgADCgEJAgAAAA==.Ramw:BAAALgADCgkJCQAAAA==.Rasmis:BAAALgAFFAIJAgAAAA==.Ravielo:BAAALgADCgQJBAAAAA==.Rawlanth:BAAALgADCgcJCQAAAA==.',
Re='Reafmon:BAAALgAECgQJCAAAAA==.Reafork:BAAALgAECgQJBQAAAA==.Reck:BAABLgAECn8XAAMEAAgJHR8EBgBxAgAEAAgJCBsEBgBxAgAFAAUJoyTaMwDbAQAAAA==.Redrangerzz:BAAALgADCgUJBAAAAA==.Regulos:BAAALgAECgEJAQAAAA==.Relanni:BAAALgADCgQJBAAAAA==.Remedialtim:BAAALgADCgkJCQAAAA==.Renwick:BAAALgADCgkJEwABLgAECgUJDQABAAAAAA==.Reomikage:BAAALgADCgcJBwAAAA==.Reservetank:BAAALgADCgMJAwAAAA==.Retasa:BAAALgAECgQJCAAAAA==.Retwings:BAABLgAFFH8JAAINAAMJCRpXEgASAQANAAMJCRpXEgASAQAAAA==.Reunach:BAABLgAECn8WAAINAAcJbAvdHQA7AQANAAcJbAvdHQA7AQAAAA==.Reybekka:BAEALgAECgQJBAAAAA==.',
Rh='Rhialto:BAAALgADCgMJAwAAAA==.Rhinegeist:BAAALgADCgEJAQAAAA==.',
Ri='Riccus:BAAALgADCgcJCgAAAA==.Rin:BAAALgAECgMJAwAAAA==.Ris:BAAALgAECgEJAwAAAA==.Ritualburner:BAAALgAECgEJAQAAAA==.Riverpixie:BAAALgADCgMJBgAAAA==.',
Ro='Roachman:BAAALgAECgYJCgAAAA==.Robovac:BAAALgADCgUJCgAAAA==.Rockbrew:BAAALgAECgYJCwAAAA==.Rockslice:BAAALgAECgEJAQAAAA==.Roonoa:BAAALgADCgcJBwAAAA==.Rorien:BAAALgAECgIJAgABLgAECgMJCQABAAAAAA==.Rosannas:BAAALgADCgcJDAABLgAFFAIJBQAJAI8fAA==.Royallz:BAAALgADCgcJBwAAAA==.',
Ru='Ruckùs:BAAALgAECgYJEAAAAA==.Rudora:BAAALgADCgcJDQAAAA==.Ruibash:BAEBLgAECn8qAAINAAgJDyZyAQDIAgANAAgJDyZyAQDIAgAAAA==.Rule:BAAALgADCgEJAQABLgAECgUJCAABAAAAAA==.',
Ry='Ryul:BAABLgAECn8WAAIcAAYJKxvfJADbAQAcAAYJKxvfJADbAQAAAA==.Ryuuzen:BAAALgADCgcJBwAAAA==.',
['Rê']='Rêqûiem:BAAALgAECgEJAQAAAA==.',
Sa='Sabigosa:BAAALgAECgYJBgAAAA==.Sabitha:BAAALgAFFAIJAgAAAA==.Sabpie:BAAALgADCgYJDwAAAA==.Sacredkhaos:BAAALgAECgMJAwABLgAECgMJBAABAAAAAA==.Sacredknight:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.Sagoon:BAAALgADCgIJAgAAAA==.Saguun:BAAALgADCgUJBQAAAA==.Saikoumaster:BAABLgAECn8VAAIHAAYJRQseIwAOAQAHAAYJRQseIwAOAQAAAA==.Saje:BAAALgAECgcJEgABLgAECggJGAAMAIElAA==.Sakebomb:BAAALgADCgYJDQAAAA==.Samwho:BAAALgADCgYJDAAAAA==.Sarajean:BAAALgAECgcJAgAAAA==.Sareythor:BAAALgADCgYJCAAAAA==.Sargeteeter:BAAALgADCgMJAwAAAA==.Satanonus:BAAALgADCgUJBAAAAA==.',
Sc='Scarelette:BAAALgADCgYJBwAAAA==.Scarletmatch:BAABLgAECn8bAAIKAAcJDRDYHQARAQAKAAcJDRDYHQARAQAAAA==.Scarwitch:BAAALgADCgIJAgAAAA==.Schamane:BAAALgAECgMJAwAAAA==.Schmedium:BAAALgADCgQJBAAAAA==.Scotty:BAAALgAECgYJDAAAAA==.',
Se='Seer:BAAALgADCgYJBgAAAA==.Seldav:BAABLgAECn8hAAMYAAkJwxp6DwB/AgAYAAgJwxp6DwB/AgAfAAIJURlmMgCCAAAAAA==.Selenyra:BAAALgAECggJDwAAAA==.Selm:BAABLgAECn8iAAIgAAgJYyUGAQBgAwAgAAgJYyUGAQBgAwAAAA==.Selvarkes:BAAALgADCgMJAwAAAA==.Seryne:BAAALgAECgQJBwAAAA==.Sevarg:BAAALgAECgYJDgAAAA==.Sevveruss:BAAALgAECgEJAgAAAA==.',
Sh='Shadowfury:BAAALgAECgQJDAAAAA==.Shadowjuve:BAAALgAECggJCgAAAA==.Shadowsnout:BAAALgAECgEJAQAAAA==.Shameless:BAAALgADCgkJEAAAAA==.Sharco:BAABLgAECn8ZAAIIAAgJww1FFgCRAQAIAAgJww1FFgCRAQAAAA==.Sharkeshia:BAAALgAECgYJDAABLgAECggJIwAcAO4lAA==.Shawarmafury:BAABLgAECn8bAAIKAAgJhCS1BABCAwAKAAgJhCS1BABCAwAAAA==.Sheedem:BAAALgADCgcJDQAAAA==.Sherrizzahh:BAAALgAECgEJAQAAAA==.Shifhappens:BAAALgAECgEJAQAAAA==.Shinshots:BAAALgADCgYJBgAAAA==.Shinyzig:BAAALgAECgQJBAAAAA==.Shockadinn:BAABLgAECn8eAAMOAAcJhh7RFQBiAgAOAAcJhh7RFQBiAgANAAYJehcXmwBIAQAAAA==.Shujáa:BAAALgAECgcJDQAAAA==.Shékinah:BAAALgAECgYJCwAAAA==.',
Si='Sickbones:BAAALgAECgYJCwABLgAFFAEJAgABAAAAAA==.Sighmon:BAAALgADCgIJAgAAAA==.Silvoryn:BAAALgADCgcJBwAAAA==.Silvrshh:BAAALgAECgMJAwAAAA==.Sinba:BAAALgAECgEJAQABLgAECggJGwAhAIgVAA==.Sinsister:BAAALgAECgYJCwAAAA==.Sinthein:BAAALgAECgEJAQABLgAECgUJDQABAAAAAA==.',
Sk='Skadfather:BAABLgAECn8WAAIOAAcJ8iC7EACMAgAOAAcJ8iC7EACMAgAAAA==.Skellyheals:BAAALgAECgMJCQAAAA==.Skorpekh:BAAALgADCgcJCwAAAA==.Skuumfein:BAAALgAECgQJBwAAAA==.Skydeuxlight:BAAALgAECgQJCgAAAA==.',
Sl='Slamdingo:BAAALgADCgUJBQAAAA==.Sleepingsun:BAAALgAECgYJEgAAAA==.Sloppyspikes:BAAALgAECgcJCQAAAA==.',
Sm='Smakm:BAAALgAECgEJAQAAAA==.Smeshh:BAAALgAECgQJBAAAAA==.Smidgenn:BAAALgAECgUJBQAAAA==.Smokyblast:BAAALgAECgEJAQAAAA==.',
Sn='Snailtrails:BAAALgADCgcJDQAAAA==.Snowball:BAAALgAECggJEwAAAA==.',
So='Solenya:BAAALgAECgEJAQAAAA==.Sonyskvirtik:BAAALgADCgYJBgAAAA==.Soozie:BAAALgAECgIJAwAAAA==.Sophiez:BAAALgADCgEJAQAAAA==.Sorvara:BAAALgADCgcJBwAAAA==.Sotan:BAABLgAECn8WAAIKAAcJpRu8JwAaAgAKAAcJpRu8JwAaAgAAAA==.Soulforge:BAAALgADCgUJBQAAAA==.',
Sp='Sparowprince:BAABLgAECn8YAAINAAgJbiD0DwAPAwANAAgJbiD0DwAPAwAAAA==.Sparxs:BAAALgADCgUJBQAAAA==.Spazs:BAAALgADCgUJCAAAAA==.Spectraleye:BAABLgAECn8WAAIRAAgJQx5AAwBwAgARAAgJQx5AAwBwAgAAAA==.Spookahuntes:BAAALgAECgQJCAAAAA==.Sproocherlou:BAAALgAECgcJEwAAAA==.',
Sq='Squirlmaster:BAAALgADCgIJAgAAAA==.',
Ss='Ssomepally:BAAALgADCgkJCQAAAA==.',
St='Stabier:BAAALgADCgQJCQAAAA==.Standalone:BAAALgADCgYJBwAAAA==.Starstryker:BAAALgADCgEJAQAAAA==.Stashdaddy:BAAALgADCgEJAQAAAA==.Stazzch:BAAALgAECgIJAwAAAA==.Stealthzu:BAABLgAECn8ZAAIWAAcJpQ8EBwB1AQAWAAcJpQ8EBwB1AQAAAA==.Steezya:BAAALgAECgIJAwAAAA==.Stegulos:BAAALgAECgEJAgAAAA==.Stellarum:BAAALgAECgEJAQAAAA==.Stonedemon:BAAALgADCgEJAQABLgAECggJGAANAG4gAA==.Stoneocean:BAAALgADCgYJCAAAAA==.Stormsy:BAAALgAECgEJAQABLgAECggJHQAiANgbAA==.Stormykitty:BAABLgAECn8dAAIiAAgJ2Bu4EQBUAgAiAAgJ2Bu4EQBUAgAAAA==.Strawhatglaz:BAAALgAECgYJCwAAAA==.Strikermain:BAAALgAECgQJBAAAAA==.Stronkchills:BAAALgADCgEJAQAAAA==.Sturtza:BAABLgAECn8YAAIKAAgJExouFQCOAgAKAAgJExouFQCOAgAAAA==.',
Su='Succubussy:BAAALgAECgEJAQAAAA==.Suun:BAAALgAECgYJDAAAAA==.',
Sw='Swoley:BAABLgAECn8aAAIOAAcJqyKrDAC1AgAOAAcJqyKrDAC1AgAAAA==.',
Sy='Syndraza:BAAALgADCgkJEgAAAA==.Synsei:BAAALgAECgQJBQAAAA==.Syyn:BAAALgADCgYJBwAAAA==.',
Ta='Tagobeets:BAAALgAECgYJDwAAAA==.Tahia:BAAALgADCgMJAwAAAA==.Taimaishoo:BAAALgADCgYJBgAAAA==.Talisaie:BAACLgAFFH8HAAMQAAQJ2hT/EgBQAQAQAAQJGBP/EgBQAQAbAAIJ6QvuBQBRAAAuAAQKfyEAAxsACAlbI+YDAKsCABsABwnhIuYDAKsCABAABwnjH9spAGkCAAAA.Taln:BAAALgAECgIJAgAAAA==.Talohha:BAAALgADCgcJBwAAAA==.Talzitalet:BAAALgADCgYJBgAAAA==.Tandor:BAAALgAECgYJEwAAAA==.Taolu:BAAALgAECgIJAgABLgAECggJIQAHANwRAA==.Tarancalime:BAAALgAECgYJDQAAAA==.Taron:BAAALgAECgUJCQAAAA==.Tazenazal:BAEALgAECgQJCgAAAA==.',
Th='Thatkindaorc:BAAALgADCgcJBgAAAA==.Thegreatestt:BAAALgADCgIJAgAAAA==.Thehumanatee:BAABLgAECn8aAAMVAAgJ6R29EwB2AgAVAAgJ6R29EwB2AgAUAAYJIwhlGQDvAAAAAA==.Theriondread:BAAALgAECgQJCQAAAA==.Theunholyone:BAAALgADCgYJEgAAAA==.Thicky:BAAALgADCgMJAwAAAA==.Thiquems:BAAALgAECgQJBAAAAA==.Thuaddar:BAAALgAECgMJAwAAAA==.Thunderanvil:BAAALgADCgYJBgAAAA==.Thyphlo:BAAALgAECgYJCAAAAA==.',
Ti='Tiagrimtotem:BAAALgADCgYJBgAAAA==.Ticklemedady:BAEALgAECgMJBAABLgAECgkJKAARAPoRAA==.Tiltedup:BAABLgAECn8mAAIIAAgJPB/QLQC7AgAIAAgJPB/QLQC7AgAAAA==.Tinkerßell:BAAALgAECgIJAgABLgAECggJHQAiANgbAA==.Tirmanator:BAAALgADCgIJAgAAAA==.',
To='Toebeanss:BAAALgADCgcJDgAAAA==.Toshi:BAAALgAECgYJDQAAAA==.Totemstitch:BAAALgADCgMJAwAAAA==.Touchyfeely:BAABLgAECn8YAAIZAAgJAA5UIgDEAQAZAAgJAA5UIgDEAQAAAA==.',
Tr='Trashgo:BAAALgADCgIJAgAAAA==.Trashgu:BAAALgAECgEJAQAAAA==.Trentonii:BAAALgADCgEJAQAAAA==.',
Tt='Ttmina:BAAALgADCgUJBQAAAA==.',
Tu='Tufani:BAAALgADCgUJBQAAAA==.Tulark:BAAALgADCgIJAwAAAA==.Tullyy:BAAALgAECgMJAwAAAA==.Tums:BAAALgAECgYJBgAAAA==.',
Tw='Twicetwice:BAAALgAECgcJDAAAAA==.Twirls:BAAALgAECgcJDgAAAA==.Twotwothree:BAAALgAECgcJEwAAAA==.',
Ty='Tylenill:BAAALgAECgYJDQAAAA==.Tylos:BAAALgADCgQJBQAAAA==.Typhoíd:BAAALgAECgEJAQAAAA==.Tyranical:BAAALgAECgQJBgAAAA==.',
Ul='Ulzulwrath:BAAALgADCgIJAgAAAA==.',
Un='Uncanny:BAAALgAECgIJAgAAAA==.',
Ur='Ursoman:BAAALgAECgEJAQAAAA==.Urtle:BAAALgAECgYJDAAAAA==.',
Us='Uselece:BAAALgAECgYJEgAAAA==.',
Uz='Uzainbolt:BAAALgAECgIJAgAAAA==.',
Va='Vaboz:BAAALgADCgEJAQAAAA==.Valeena:BAAALgAECgUJCAAAAA==.Valoric:BAAALgADCgUJBQAAAA==.Valvalon:BAABLgAECn8UAAIIAAYJ1hbZIgBGAQAIAAYJ1hbZIgBGAQAAAA==.Vandorian:BAAALgAECgEJAgAAAA==.Vannin:BAAALgADCgMJAwAAAA==.Vardá:BAAALgADCgEJAQAAAA==.',
Ve='Veelaria:BAAALgAECgYJCwAAAA==.Velarisaa:BAAALgADCgcJCwAAAA==.Veledaa:BAAALgAECgUJCgABLgAECgYJBgABAAAAAA==.Velinddrel:BAAALgADCgcJDgAAAA==.Verena:BAAALgADCgMJAwAAAA==.Vestige:BAAALgADCgMJAwAAAA==.',
Vi='Vicalaus:BAAALgAECgQJBQAAAA==.View:BAAALgADCgUJBQAAAA==.Vikingxx:BAAALgADCgEJAQAAAA==.Vilified:BAAALgAECgQJDQAAAA==.Vincelex:BAAALgADCgMJBgAAAA==.Vincerer:BAAALgAECgQJBwAAAA==.Vitros:BAAALgADCgcJBwABLgAECgEJAQABAAAAAA==.',
Vl='Vladymir:BAAALgADCgYJBgAAAA==.',
Vo='Voidbren:BAAALgAECgYJDAAAAA==.Voidescapee:BAAALgAECgMJBQAAAA==.Voidpapi:BAAALgAECgEJAQAAAA==.Voidsav:BAAALgADCgMJBQAAAA==.Voidscarred:BAAALgADCggJDgAAAA==.Voidwitch:BAAALgAECgYJDwAAAA==.',
Vy='Vylandra:BAAALgADCgYJBgAAAA==.',
Wa='Wagar:BAAALgADCgQJBAAAAA==.Watchmecook:BAAALgAECgEJAQAAAA==.',
We='Webbfury:BAAALgAECgcJEAAAAA==.',
Wh='Wheremytotem:BAAALgADCgYJBgABLgAECggJHgAOAB0dAA==.',
Wi='Wiidge:BAAALgAECgUJCAAAAA==.Wildretnuh:BAACLgAFFH8GAAIRAAIJZRHJKACfAAARAAIJZRHJKACfAAAuAAQKfyIAAhEABwmAGPBDAOQBABEABwmAGPBDAOQBAAAA.Windiwithani:BAABLgAECn8eAAIXAAgJ+xJmBQBeAQAXAAgJ+xJmBQBeAQAAAA==.Wiou:BAAALgADCgMJAwAAAA==.',
Wo='Wocky:BAAALgAECgUJCQAAAA==.Worgath:BAAALgAECgMJBAAAAA==.Worldcrafter:BAAALgAECgYJDwAAAA==.',
Wr='Wrapta:BAAALgADCgkJDwAAAA==.Wrathofdawn:BAAALgAECgEJAQAAAA==.',
Xa='Xaalai:BAAALgADCgIJAgAAAA==.Xantry:BAACLgAFFH8NAAMNAAUJFR5yCQBiAQANAAUJMBpyCQBiAQASAAIJ7Bb6AwCdAAAuAAQKfyAAAg0ACAnQJWIIAFADAA0ACAnQJWIIAFADAAAA.',
Xe='Xenons:BAAALgADCgYJBgAAAA==.',
Xi='Xillow:BAAALgADCgQJBAAAAA==.',
Xs='Xsirdrunk:BAAALgADCggJDwAAAA==.',
Xy='Xylin:BAAALgAECgMJAwAAAA==.Xymm:BAAALgAECgEJAQAAAA==.',
Ye='Yeastytree:BAABLgAECn8eAAIUAAgJnRdlLQD4AQAUAAgJnRdlLQD4AQAAAA==.Yellatuu:BAAALgAECgQJDQAAAA==.',
Ys='Yshlata:BAAALgADCgMJAwAAAA==.',
Za='Zanekraken:BAAALgADCgYJBgAAAA==.Zanthoss:BAAALgADCgkJEgAAAA==.Zarathea:BAAALgADCgkJCQAAAA==.',
Ze='Zella:BAAALgADCgYJCwAAAA==.Zemniss:BAAALgADCgcJBwAAAA==.Zendalis:BAAALgAECgYJCgAAAA==.Zenjay:BAAALgAECgQJBAAAAA==.Zerrikan:BAAALgADCgUJBQAAAA==.',
Zh='Zhalthir:BAAALgAECgEJAgAAAA==.',
Zi='Zilphah:BAAALgAECgUJBQAAAA==.Zimms:BAABLgAECn8UAAIDAAYJch6VIADSAQADAAYJch6VIADSAQAAAA==.Zinng:BAAALgADCgYJBgABLgAECgkJGQAZAB8SAA==.Zirakul:BAAALgAECgEJAQAAAA==.',
Zo='Zoeyredbird:BAAALgAECgUJCwAAAA==.Zombalorian:BAAALgADCgMJAgAAAA==.',
Zu='Zulamar:BAAALgAECgEJAQAAAA==.',
Zy='Zyenthia:BAAALgADCgYJBgAAAA==.',
['Äl']='Älcatraz:BAAALgADCgcJEgABLgAECgQJCQABAAAAAA==.',
['Îs']='Îsh:BAAALgAECgUJBQAAAA==.',
['Ör']='Örgrim:BAACLgAFFH8LAAINAAQJhCV6AADJAQANAAQJhCV6AADJAQAuAAQKfzcAAg0ACQn+JL4BAMcDAA0ACQn+JL4BAMcDAAAA.',
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

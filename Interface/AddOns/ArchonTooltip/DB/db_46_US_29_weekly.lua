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

local lookup = {'Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Hunter-Survival','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Destruction','DemonHunter-Devourer','Warrior-Fury','Paladin-Retribution','Druid-Guardian','Hunter-Marksmanship','Druid-Balance','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adrianmonk:BAAALgAECgYJDAAAAA==.',
Ak='Aktuu:BAAALgADCgQJBAAAAA==.',
An='Andeys:BAAALgAECgMJAwAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHQABAJMTAA==.',
Ba='Baggigy:BAAALgAFFAEJAQAAAA==.Balance:BAAALgAECggJCQABLgAECggJHQACAFUhAA==.',
Be='Bentpanda:BAAALgAECgYJDAAAAA==.',
Bh='Bhain:BAAALgADCgYJBgABLgAECgcJIAADANMdAA==.',
Bi='Bigcocko:BAACLgAFFH8PAAIEAAUJbBx/AQC8AQAEAAUJbBx/AQC8AQAuAAQKfyAAAgQACAluJokCAHIDAAQACAluJokCAHIDAAAA.Birchwood:BAAALgAECgUJBQAAAA==.',
Bl='Blarrg:BAAALgAECgUJCwABLgAFFAEJAQAFAAAAAA==.Blocks:BAAALgADCgEJAQAAAA==.',
Bo='Boneriffik:BAAALgAECgQJBwAAAA==.Bossfury:BAAALgAECgUJBgAAAA==.',
Br='Brogh:BAAALgAECgQJCgAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIGAAkJ+gwnOQCdAQAGAAkJ+gwnOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn8jAAIHAAgJoSJfAADBAgAHAAgJoSJfAADBAgAAAA==.Caneangel:BAAALgAECgcJDQAAAA==.',
Ch='Charvhug:BAAALgAECgUJCgAAAA==.',
Co='Coldnbloodÿ:BAAALgAECgYJEQAAAA==.Corrupthell:BAAALgAECgEJAgAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJCgAAAA==.',
Da='Dadbod:BAAALgAECgYJCgAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIIAAgJZRo3XAAlAgAIAAgJZRo3XAAlAgAAAA==.',
De='Del:BAAALgAECgQJBAAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8dAAQBAAkJkxMiMACVAQABAAcJexMiMACVAQAJAAUJLxbpOwAsAQAKAAEJ0xccYwBEAAAAAA==.Driver:BAECLgAFFH8FAAIDAAMJwgdIEQDoAAADAAMJwgdIEQDoAAAuAAQKfzUAAwMACAngHvYZALkCAAMACAngHvYZALkCAAsABgniGNMUAKQBAAAA.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ex='Exemplio:BAABLgAECn8ZAAIBAAcJ9yOKBQC1AQABAAcJ9yOKBQC1AQAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHQABAJMTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgADCgEJAQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAIIAAcJzw3TqACIAQAIAAcJzw3TqACIAQAAAA==.Frybeam:BAAALgADCgQJBQAAAA==.',
Gi='Giovahni:BAABLgAECn8cAAIMAAgJQhy/HgCZAgAMAAgJQhy/HgCZAgAAAA==.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHQABAJMTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIIAAcJsAVByABYAQAIAAcJsAVByABYAQAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8YAAINAAcJkBJSDABbAQANAAcJkBJSDABbAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Janaria:BAAALgAECgYJCQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jessiescool:BAABLgAECn8UAAIOAAYJNQ7PlwBOAQAOAAYJNQ7PlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIPAAkJMw4tEAB1AQAPAAkJMw4tEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJBwAAAA==.Joyluka:BAAALgAFFAEJAQAAAA==.',
Ka='Kalvin:BAAALgAECgYJEAAAAA==.Kanari:BAAALgAECgMJBgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.',
La='Lagoles:BAABLgAECn8jAAIQAAgJfR9kEwCXAgAQAAgJfR9kEwCXAgAAAA==.Landis:BAAALgAECgUJCgAAAA==.',
Li='Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgADCgQJBAAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAPADMOAA==.',
Mi='Miggles:BAACLgAFFH8GAAIEAAMJngryCQDBAAAEAAMJngryCQDBAAAuAAQKfx4AAwQACQnIHvsQALACAAQACQnIHvsQALACABEAAglmDjlsAG8AAAAA.',
Mk='Mk:BAEBLgAECn8kAAIJAAgJAiMeBgAfAwAJAAgJAiMeBgAfAwAAAA==.',
Mo='Monzo:BAABLgAECn8dAAMCAAgJVSHzGADmAgACAAgJVSHzGADmAgASAAIJ1A+SPQBcAAAAAA==.Morvayne:BAABLgAECn8hAAIIAAgJmBn3QgBvAgAIAAgJmBn3QgBvAgABLgAECggJIwAQAH0fAA==.',
My='Myneemo:BAAALgAECgIJAgAAAA==.Myro:BAAALgADCgkJGQAAAA==.',
No='Nosam:BAAALgAECgUJCwAAAA==.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAAALgAECgYJCgAAAA==.',
Or='Ornatas:BAABLgAECn8VAAITAAgJhhuWFQBvAgATAAgJhhuWFQBvAgAAAA==.',
Pa='Pandamonium:BAAALgAECgYJEQAAAA==.',
Pe='Perdyblues:BAAALgAECgQJBAAAAA==.',
Po='Pom:BAAALgAECgEJAgAAAA==.',
Qi='Qiana:BAAALgADCgcJBwABLgAECgYJEgAFAAAAAA==.',
Qu='Quickstabbin:BAABLgAECn8UAAIJAAYJuw6fNgBEAQAJAAYJuw6fNgBEAQAAAA==.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHQABAJMTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHQABAJMTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECgcJCAAAAA==.',
Sc='Scylla:BAACLgAFFH8QAAIUAAYJHx8pAQBCAgAUAAYJHx8pAQBCAgAuAAQKfyoAAxQACQkEJh4AAOUDABQACQkEJh4AAOUDABUAAQmlDjJeAEIAAAEuAAQKBgkPAAUAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAIOAAkJCBSLQgAdAgAOAAkJCBSLQgAdAgAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgIJAgABLgAECggJIwAHAKEiAA==.',
So='Soothe:BAAALgAECgEJAQAAAA==.',
Sw='Swaggasaurus:BAAALgAECgUJDAAAAA==.',
Sy='Sylarien:BAAALgAECgQJBAAAAA==.Syriena:BAAALgADCgUJBwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAAALgAECgcJDgAAAA==.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAAALgAECgQJCAABLgAECgUJCgAFAAAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgYJBgAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Ve='Veew:BAABLgAECn8XAAMNAAgJ7BGKOgC8AQANAAgJNRGKOgC8AQAWAAUJshEIGwAZAQAAAA==.',
Wh='Whitegoddess:BAAALgAECgcJEAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Yu='Yungmage:BAABLgAECn8UAAIIAAcJYhWhggDMAQAIAAcJYhWhggDMAQAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIIAAkJKBhVRQBoAgAIAAkJKBhVRQBoAgAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJCAAAAA==.',
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

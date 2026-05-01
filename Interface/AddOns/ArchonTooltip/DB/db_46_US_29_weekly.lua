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

local lookup = {'Monk-Brewmaster','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Hunter-Survival','DemonHunter-Devourer','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Paladin-Retribution','Druid-Guardian','Rogue-Subtlety','Hunter-Marksmanship','Druid-Balance','DeathKnight-Blood','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adrianmonk:BAAALgAECgYJDQAAAA==.',
Ak='Aktuu:BAAALgADCgQJBAAAAA==.',
An='Andeys:BAAALgAECgYJCgAAAA==.Angelius:BAAALgAECgEJAQAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHQABAJMTAA==.',
Ba='Baggigy:BAAALgAFFAEJAQAAAA==.Balance:BAAALgAECggJDQABLgAECggJHQACAFUhAA==.',
Be='Bentpanda:BAAALgAECgcJDgAAAA==.',
Bh='Bhain:BAAALgAFFAEJAQAAAA==.',
Bi='Bigcocko:BAACLgAFFH8UAAIDAAUJyB45BADKAQADAAUJyB45BADKAQAuAAQKfyIAAgMACAluJooCAHIDAAMACAluJooCAHIDAAAA.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAECgUJCwABLgAFFAEJAQAEAAAAAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgQJCAAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAAALgAECgUJDAAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAIFAAkJ+gwoOQCdAQAFAAkJ+gwoOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn8sAAIGAAkJ4yCHAAAhAwAGAAkJ4yCHAAAhAwAAAA==.Caneangel:BAAALgAECgcJEQAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQAAAA==.Chilyn:BAAALgADCgEJAQAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8WAAIHAAYJKQxTgQAnAQAHAAYJKQxTgQAnAQAAAA==.Corrupthell:BAAALgAECgMJBQAAAA==.Cowi:BAAALgAECgIJAgAAAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgYJCgAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAABLgAECn8YAAIIAAgJQRosXAAlAgAIAAgJQRosXAAlAgAAAA==.',
De='Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8dAAQBAAkJkxMYMACVAQABAAcJexMYMACVAQAJAAUJLxbvOwAsAQAKAAEJ0xfuYgBEAAAAAA==.Driver:BAECLgAFFH8HAAILAAMJpQvSMADiAAALAAMJpQvSMADiAAAuAAQKfzUAAwsACAngHvIZALkCAAsACAngHvIZALkCAAwABgniGNEUAKQBAAAA.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ex='Exemplio:BAABLgAECn8iAAIBAAgJXCT+AQDOAgABAAgJXCT+AQDOAgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHQABAJMTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgADCgEJAQAAAA==.',
Fr='Frosty:BAABLgAECn8UAAIIAAcJzw3OqACIAQAIAAcJzw3OqACIAQAAAA==.Frybeam:BAAALgADCgQJBQAAAA==.',
Gi='Giovahni:BAABLgAECn8lAAIHAAgJ1x6qDAAWAgAHAAgJ1x6qDAAWAgAAAA==.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHQABAJMTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIIAAcJsAVIyABYAQAIAAcJsAVIyABYAQAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8aAAINAAgJ5RLDEgChAQANAAgJ5RLDEgChAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Janaria:BAAALgAECgYJCQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jessiescool:BAABLgAECn8UAAIOAAYJNQ7QlwBOAQAOAAYJNQ7QlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIPAAkJMw4uEAB1AQAPAAkJMw4uEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJBwAAAA==.Joyluka:BAAALgAFFAIJAgAAAA==.',
Ka='Kalvin:BAABLgAECn8UAAIQAAcJzAqxFQAsAQAQAAcJzAqxFQAsAQAAAA==.Kanari:BAAALgAECgYJDQAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.',
La='Lagoles:BAABLgAECn8qAAMGAAkJxx9RBgAKAgARAAgJfR9oEwCXAgAGAAcJMRxRBgAKAgABLgAECgkJLAAIAEkcAA==.Landis:BAAALgAECgUJCgAAAA==.',
Le='Leaf:BAAALgAECgIJAQABLgAECgkJLAAGAOMgAA==.',
Li='Liltracey:BAAALgAECgUJCgABLgAECggJHQACAFUhAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgADCgQJBAAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAPADMOAA==.',
Mi='Miggles:BAACLgAFFH8JAAIDAAMJKBGhGADTAAADAAMJKBGhGADTAAAuAAQKfyEAAwMACQnIHvoQALACAAMACQnIHvoQALACABIAAglmDjxsAG8AAAAA.',
Mk='Mk:BAEBLgAECn8pAAMJAAgJAiMeBgAfAwAJAAgJAiMeBgAfAwABAAUJpgn3KADJAAAAAA==.',
Mo='Monzo:BAABLgAECn8dAAMCAAgJVSH7GADmAgACAAgJVSH7GADmAgATAAIJ1A+NPQBcAAAAAA==.Morvayne:BAABLgAECn8sAAIIAAkJSRybCQCkAgAIAAkJSRybCQCkAgAAAA==.',
My='Myneemo:BAAALgAECgIJAgAAAA==.Myro:BAAALgADCgkJGQAAAA==.',
No='Nosam:BAAALgAECgUJEQAAAA==.',
Nt='Nthegreat:BAAALgAECgUJBQAAAA==.',
Nw='Nwf:BAAALgAECgYJEAAAAA==.',
Or='Ornatas:BAABLgAECn8WAAIUAAgJqByVFQBvAgAUAAgJqByVFQBvAgAAAA==.',
Pa='Pandamonium:BAABLgAECn8VAAQKAAYJhhT3KwBWAQAKAAYJhhT3KwBWAQABAAMJ9wOONwB8AAAJAAEJNwmMgQAvAAAAAA==.',
Pe='Perdyblues:BAAALgAECgYJCwAAAA==.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgADCgQJBAAAAA==.',
Qi='Qiana:BAAALgADCgcJBwAAAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIJAAgJBwwHGgAVAQAJAAgJBwwHGgAVAQAAAA==.',
Ra='Rainootra:BAAALgADCgIJAgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHQABAJMTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHQABAJMTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAAALgAECgcJCAAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIVAAcJwx0rAQBCAgAVAAcJwx0rAQBCAgAuAAQKfywAAxUACQn9JR8AAOUDABUACQn9JR8AAOUDABYAAQmlDjVeAEIAAAEuAAQKBgkPAAQAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAIOAAkJCBSGQgAdAgAOAAkJCBSGQgAdAgAAAA==.',
Si='Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAECgQJBAABLgAECgkJLAAGAOMgAA==.',
So='Soothe:BAAALgAECgEJAgAAAA==.',
Sw='Swaggasaurus:BAAALgAECgYJEwAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAABLgAECn8WAAINAAgJABnREwCXAQANAAgJABnREwCXAQAAAA==.',
Te='Tengoo:BAAALgAECgQJBAAAAA==.',
Th='Thewaitress:BAAALgAECgQJCAABLgAFFAEJAQAEAAAAAA==.Thylight:BAAALgADCgIJAgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Ve='Veew:BAABLgAECn8XAAMNAAgJ7BGOOgC8AQANAAgJNRGOOgC8AQAXAAUJshEMGwAZAQAAAA==.',
Wa='Warpedshadow:BAAALgAECgYJBwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8XAAIYAAcJ1QzLKwBkAQAYAAcJ1QzLKwBkAQAAAA==.',
Wo='Wontan:BAAALgAECgcJBwAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Yu='Yungmage:BAABLgAECn8YAAIIAAcJbRiRggDMAQAIAAcJbRiRggDMAQAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIIAAkJ/BdTRQBoAgAIAAkJ/BdTRQBoAgAAAA==.',
['Èl']='Èlfman:BAAALgAECgUJCgAAAA==.',
['Øm']='Ømega:BAAALgADCgEJAQAAAA==.',
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

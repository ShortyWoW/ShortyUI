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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Priest-Holy','Druid-Feral','Druid-Balance','Rogue-Subtlety','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aandheeog:BAAALgAECgYJDAAAAA==.',
Ab='Absqwas:BAAALgADCgcJEQAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8dAAMBAAgJUxiQHQBUAgABAAgJUxiQHQBUAgACAAIJsAJfgQBAAAAAAA==.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8VAAMDAAYJwyB8BwAOAgADAAUJwCV8BwAOAgAEAAYJXA+3GgAsAQAAAA==.',
An='Aneesa:BAABLgAECn8XAAMFAAYJ7hRVhgBtAQAFAAYJ7hRVhgBtAQAGAAEJmQMiFAAnAAAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8XAAIHAAcJTRE6CQBUAQAHAAcJTRE6CQBUAQAAAA==.Ashbahn:BAABLgAECn8cAAMIAAcJ0wvCUgAvAQAIAAcJ0wvCUgAvAQAFAAQJIxN3NQDDAAAAAA==.Ashes:BAAALgAECgMJCAABLgAECgcJHAAIANMLAA==.Ashmodai:BAAALgADCgQJBAAAAA==.',
Au='Auroranova:BAAALgAECgYJEgAAAA==.',
Ax='Axél:BAAALgADCgUJBgAAAA==.',
Be='Berringer:BAAALgAECgMJBgAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJBAAAAA==.',
Br='Brilleleante:BAAALgADCgQJBQAAAA==.Broxmorn:BAAALgADCgcJCwAAAA==.',
Ca='Canimai:BAABLgAECn8cAAMJAAgJNQ7hCACSAQAJAAgJNQ7hCACSAQAKAAEJ9whxSAAtAAAAAA==.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJBAAAAA==.',
Cr='Crazynaga:BAABLgAECn8ZAAIEAAYJnwUyNACZAAAEAAYJnwUyNACZAAAAAA==.Crisspy:BAABLgAECn8fAAMLAAgJaQ7yCwA8AQALAAgJaQ7yCwA8AQAMAAEJGgdwLAA1AAAAAA==.',
Cu='Cubes:BAACLgAFFH8PAAINAAUJjSV5AAAjAgANAAUJjSV5AAAjAgAuAAQKfywABA0ACQm1JRgBALcDAA0ACQm1JRgBALcDAA4ABgnNGKYtAKMBAA8AAwlEDsUTAKgAAAAA.',
Da='Daisyspark:BAAALgAECgEJAwAAAA==.',
De='Deathcrocker:BAECLgAFFH8UAAIQAAYJNSVLAACGAgAQAAYJNSVLAACGAgAuAAQKfxgAAhAACQkDJmkAAMoDABAACQkDJmkAAMoDAAAA.Decksters:BAAALgADCgYJCAAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIFAAgJBBcsTQD7AQAFAAgJBBcsTQD7AQABLgAFFAQJBwAFAL4UAA==.',
Do='Dogs:BAABLgAECn8bAAIJAAgJ6BvYDQDmAgAJAAgJ6BvYDQDmAgABLgAFFAcJDAAFAJ8VAA==.Domar:BAAALgAECgMJBAAAAA==.Doomslayer:BAABLgAECn8cAAMRAAkJbBXtRwAcAgARAAkJbBXtRwAcAgAQAAUJgAL3MwCgAAAAAA==.Dothippo:BAABLgAECn8cAAMSAAYJLhtXEADMAQASAAYJLhtXEADMAQATAAEJFgRKKAEpAAAAAA==.',
Du='Dunk:BAABLgAECn8VAAIFAAkJfxMHXQDMAQAFAAkJfxMHXQDMAQAAAA==.',
Ea='Easy:BAAALgAECgIJAgABLgAECgYJBgAUAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAMJBwAVANMYAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgADCgQJBAAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAAALgAECgcJEwAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgADCgYJBgAAAA==.Frieren:BAACLgAFFH8NAAIWAAYJGR9vCgDLAQAWAAYJGR9vCgDLAQAuAAQKfyEABBYACQl9IlUNAFsDABYACQl9IlUNAFsDABcAAQnTIAgNAFkAABgAAQkbDxwaAEcAAAAA.Froslass:BAAALgAECgYJDwAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgIJAgAAAA==.',
Gl='Gloryhammer:BAABLgAECn8iAAQGAAgJ9hqNCABPAgAGAAgJ9hqNCABPAgAIAAUJKAW4awDLAAAFAAEJaxl9QwEzAAAAAA==.',
Go='Gobbs:BAAALgAECgYJEgABLgAECgcJGQABAFUeAA==.',
Ha='Halbarad:BAAALgAECgcJBgAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgUJCwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8GAAIZAAMJOh1sAwDyAAAZAAMJOh1sAwDyAAAuAAQKfxYAAhkACAk5IdULAJQCABkACAk5IdULAJQCAAAA.Hop:BAABLgAECn8WAAIaAAgJrBZdCABZAgAaAAgJrBZdCABZAgAAAA==.Hota:BAAALgAECgYJBwABLgAFFAMJBgAZADodAA==.Hotamnk:BAAALgAECgMJAwABLgAFFAMJBgAZADodAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.',
Iv='Ivakor:BAAALgAECgUJCgAAAA==.Ivyy:BAACLgAFFH8GAAIbAAMJEiJnCwA1AQAbAAMJEiJnCwA1AQAuAAQKfxUAAhsACAnQHrUNAMACABsACAnQHrUNAMACAAEuAAUUBQkTABwABxsA.',
Ja='Jackswagz:BAABLgAECn8ZAAIMAAcJsRYIMADHAQAMAAcJsRYIMADHAQAAAA==.Jaszuny:BAAALgAECgcJEwAAAA==.',
Ka='Katsumotosan:BAAALgADCggJCAAAAA==.',
Ke='Kev:BAABLgAECn8cAAQWAAYJdiUmPQCDAgAWAAYJdiUmPQCDAgAYAAIJMiTaDwDEAAAXAAEJAAA6EgAXAAAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAAALgAECgYJDQAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgEJAQAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8HAAIFAAQJvhQvCgBbAQAFAAQJvhQvCgBbAQAuAAQKfxwAAgUABwl+HeQxAFsCAAUABwl+HeQxAFsCAAAA.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Luniaira:BAAALgAECgYJBgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAECggJDwAUAAAAAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAAALgAECgcJEgAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgADCgUJCAAAAA==.Mistake:BAAALgAECgYJCgAAAA==.',
Mo='Mockra:BAAALgADCgEJAQABLgAECgIJAgAUAAAAAA==.Monkcrocker:BAECLgAFFH8FAAIOAAQJbxssCgA3AQAOAAQJbxssCgA3AQAuAAQKfxQAAg4ABwnxJcQNALcCAA4ABwnxJcQNALcCAAEuAAUUBgkUABAANSUA.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Naztherune:BAAALgADCgEJAQAAAA==.',
Ni='Nier:BAAALgAECgMJAwAAAA==.Nightsilver:BAAALgADCgMJAwAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.',
Ny='Nylianna:BAABLgAECn8fAAIFAAkJAB1mDAArAwAFAAkJAB1mDAArAwAAAA==.',
Og='Ogganborn:BAAALgAECgYJDQAAAA==.',
On='Oneira:BAAALgADCggJDQAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8UAAIFAAcJsA+vIAArAQAFAAcJsA+vIAArAQAAAA==.',
Pr='Priestigory:BAABLgAECn8eAAMOAAcJax2FBgCaAQAOAAcJax2FBgCaAQANAAIJGBNVYwCBAAAAAA==.',
Pv='Pvtcrocker:BAAALgAECgcJCwAAAA==.',
Qu='Quink:BAAALgADCggJCAAAAA==.Quintus:BAAALgADCgYJBgAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQANABkcAA==.Railiana:BAAALgAECgMJAwAAAA==.Ravelin:BAAALgADCggJEAAAAA==.',
Re='Regrowth:BAABLgAECn8cAAQdAAcJOCKfFQCJAgAdAAcJOCKfFQCJAgAaAAEJMxbkLwBIAAAbAAEJKALjjgAeAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgQJBAAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJEwAUAAAAAA==.',
Ru='Ruby:BAACLgAFFH8LAAIKAAYJtxoMAQD/AQAKAAYJtxoMAQD/AQAuAAQKfxwAAgoACAmbJbUBAGgDAAoACAmbJbUBAGgDAAAA.Ruhai:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràistlin:BAAALgAECgYJCgAAAA==.',
Se='Sephiran:BAAALgAECgcJEQAAAA==.',
Sh='Shagra:BAAALgADCgkJEAAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgQJCwAAAA==.Shoepert:BAABLgAECn8bAAIJAAcJbx+kBQDRAQAJAAcJbx+kBQDRAQAAAA==.',
Si='Sini:BAAALgAECgcJBQAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBQABLgAECgYJBgAUAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.',
Te='Tempus:BAABLgAECn8XAAMIAAgJKBpdJAAAAgAIAAgJKBpdJAAAAgAFAAEJyQK0TgEtAAAAAA==.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgQJCQAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Un='Union:BAAALgADCgMJAwAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAAALgAECgcJEgAAAA==.',
Ve='Velawynn:BAACLgAFFH8SAAIZAAUJcRqwAACjAQAZAAUJcRqwAACjAQAuAAQKfy0AAxkACQm5HhwFAP8CABkACQm5HhwFAP8CAB4ABAkvDVsUALkAAAAA.Veronica:BAACLgAFFH8HAAIQAAUJxRMTBABvAQAQAAUJxRMTBABvAQAuAAQKfxQAAxAACAncHTESAOgBABAACAn8HDESAOgBABEABgn9Gjx+AIcBAAAA.',
Vi='Vixa:BAAALgADCggJDQAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Xa='Xamot:BAAALgADCgkJDgABLgAECgIJAwAUAAAAAA==.Xarou:BAAALgAECgIJAgAAAA==.',
Ya='Yanyan:BAAALgAECgUJBgAAAA==.',
Zi='Zilgius:BAAALgAECgYJEAABLgAECgcJEQAUAAAAAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
Zu='Zubang:BAAALgAECgcJBgAAAA==.',
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

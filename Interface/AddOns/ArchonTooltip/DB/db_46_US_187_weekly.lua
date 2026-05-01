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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow','DemonHunter-Havoc',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aandheeog:BAAALgAECgYJDAAAAA==.',
Ab='Absqwas:BAAALgADCgcJEQAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8lAAMBAAgJVhm2EgD9AQABAAgJVhm2EgD9AQACAAIJsAJngQBAAAAAAA==.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8QAAMDAAUJwCV6BwAOAgADAAUJwCV6BwAOAgAEAAEJah70dQBWAAAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgMJAwAAAA==.Aneesa:BAABLgAECn8XAAMFAAYJ7hRUhgBtAQAFAAYJ7hRUhgBtAQAGAAEJmQMAKwAiAAAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8ZAAIHAAgJKhCbEACJAQAHAAgJKhCbEACJAQAAAA==.Ashbahn:BAABLgAECn8kAAMIAAgJEwtrHwBLAQAIAAgJEwtrHwBLAQAFAAQJIxPPeQC6AAAAAA==.Ashes:BAAALgAECgQJCQABLgAECggJJAAIABMLAA==.Ashmodai:BAAALgADCgQJBAAAAA==.',
Au='Auroranova:BAABLgAECn8YAAIFAAYJTQibXwD1AAAFAAYJTQibXwD1AAAAAA==.',
Ax='Axél:BAAALgAECgMJBAAAAA==.',
Be='Berringer:BAAALgAECgMJCQAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJBQAAAA==.',
Br='Braei:BAAALgAECgMJAwAAAA==.Brilleleante:BAAALgADCgYJCwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAEJAQABLgAFFAYJDgACAOUgAA==.Canimai:BAABLgAECn8jAAMJAAgJ6hADQwCYAQAJAAgJNQ4DQwCYAQAKAAMJpxHuIABzAAAAAA==.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVElgDwAAAEAAYJnwVElgDwAAAAAA==.Crisspy:BAACLgAFFH8HAAMLAAMJfQHRFgCyAAALAAMJfQHRFgCyAAAMAAIJtwYAHACIAAAuAAQKfyMAAwsACAlkD9QUAHABAAsACAlkD9QUAHABAAwAAQkaB6lgADQAAAAA.',
Cu='Cubes:BAACLgAFFH8UAAINAAUJLSaOAADOAQANAAUJLSaOAADOAQAuAAQKfywABA0ACQm1JRcBALgDAA0ACQm1JRcBALgDAA4ABgnNGJwtAKMBAA8AAwlEDo8sAKUAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJAwAAAA==.',
De='Deathcrocker:BAECLgAFFH8ZAAIQAAYJnyVJAACGAgAQAAYJnyVJAACGAgAuAAQKfxoAAhAACQkDJmsAAMsDABAACQkDJmsAAMsDAAAA.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIFAAgJBBcmTQD7AQAFAAgJBBcmTQD7AQABLgAFFAQJCwAFAMoYAA==.',
Do='Dogs:BAACLgAFFH8LAAIJAAQJwRoXBAB3AQAJAAQJwRoXBAB3AQAuAAQKfxsAAgkACAnoG9kNAOYCAAkACAnoG9kNAOYCAAEuAAUUBwkRAAUABxgA.Domar:BAAALgAECgQJBwAAAA==.Doomslayer:BAABLgAECn8gAAMRAAkJNRgNIgC8AQARAAkJNRgNIgC8AQAQAAUJgALxMwCgAAAAAA==.Doraei:BAAALgAECgYJBgAAAA==.Dothippo:BAABLgAECn8jAAMSAAcJhBoYAwDHAQASAAcJhBoYAwDHAQATAAEJFgRhKAEpAAAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8cAAIFAAkJwBVKHADgAQAFAAkJwBVKHADgAQAAAA==.',
Ea='Easy:BAAALgAECgIJAgABLgAECgYJBgAUAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJCwAVAO0XAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgADCgQJBAAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAAALgAECgcJEwAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgADCgYJBgAAAA==.Frieren:BAACLgAFFH8RAAIWAAYJ4x99CgDLAQAWAAYJ4x99CgDLAQAuAAQKfyEABBYACQl9Il0NAFsDABYACQl9Il0NAFsDABcAAQnTIAgNAFkAABgAAQkbDxsaAEcAAAAA.Froslass:BAAALgAECgYJDwAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgQJBQAAAA==.',
Gl='Gloryhammer:BAABLgAECn8jAAQGAAgJ9hqNCABPAgAGAAgJ9hqNCABPAgAIAAUJKAW9awDLAAAFAAEJaxmlQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8YAAMZAAYJHxKICwBzAQAZAAYJ4g+ICwBzAQAaAAYJEBFiEgBPAQABLgAECggJHgABAIgbAA==.',
Gr='Gripmedaddy:BAAALgADCgcJBwAAAA==.',
Ha='Halbarad:BAAALgAECgcJBgAAAA==.Haldrian:BAAALgAECgMJAwAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMbAAQJ0xgLCgDvAAAbAAMJOh0LCgDvAAAcAAMJSQqxFAC/AAAuAAQKfxcAAxsACAk5IdcLAJMCABsACAk5IdcLAJMCABwAAQmDDyI3ADUAAAAA.Hop:BAABLgAECn8eAAIdAAgJphj3AwD5AQAdAAgJphj3AwD5AQAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAbANMYAA==.Hotamnk:BAAALgAECgMJAwABLgAFFAQJCQAbANMYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgIJAgAAAA==.',
Iv='Ivakor:BAAALgAECgUJCgAAAA==.Ivyy:BAACLgAFFH8JAAIeAAMJgCMDCwA9AQAeAAMJgCMDCwA9AQAuAAQKfxYAAh4ACAkzH7UNAMACAB4ACAkzH7UNAMACAAEuAAUUBQkXABoA1SIA.',
Ja='Jackswagz:BAABLgAECn8cAAIMAAgJWRROGQCZAQAMAAgJWRROGQCZAQAAAA==.Jaszuny:BAABLgAECn8aAAIDAAgJjBCoBQB8AQADAAgJjBCoBQB8AQAAAA==.',
Ka='Katsumotosan:BAAALgADCggJCAAAAA==.',
Ke='Kev:BAABLgAECn8jAAQWAAcJfCTMEgBEAgAWAAcJfCTMEgBEAgAYAAIJMiTcDwDEAAAXAAEJAAA9EgAXAAAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8UAAIRAAcJEBoHKACdAQARAAcJEBoHKACdAQAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8LAAIFAAQJyhg1CgBbAQAFAAQJyhg1CgBbAQAuAAQKfx0AAgUACAkzHdsxAFsCAAUACAkzHdsxAFsCAAAA.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgADCgcJBwAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAECgkJFAAHAEAHAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8ZAAMRAAcJeQ2nXADwAAARAAcJOQ2nXADwAAAQAAEJsQ22RgAtAAAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAIJAgAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgADCggJDQAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgADCgEJAQABLgAECgIJAgAUAAAAAA==.Monkcrocker:BAECLgAFFH8HAAIOAAQJlBsyCgA3AQAOAAQJlBsyCgA3AQAuAAQKfxUAAg4ABwnxJcUNALcCAA4ABwnxJcUNALcCAAEuAAUUBgkZABAAnyUA.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJCgAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8FAAIFAAIJThQsLwCnAAAFAAIJThQsLwCnAAAuAAQKfx8AAgUACQkAHWgMACsDAAUACQkAHWgMACsDAAAA.',
Og='Ogganborn:BAAALgAECgYJDwAAAA==.',
On='Oneira:BAAALgADCggJDQAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIFAAcJ0xKPMwB0AQAFAAcJ0xKPMwB0AQAAAA==.',
Pr='Priestigory:BAABLgAECn8mAAMOAAgJpx1EBQBXAgAOAAgJpx1EBQBXAgANAAIJGBNYYwCBAAAAAA==.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgEJAQAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJCAAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQANABkcAA==.Railiana:BAAALgAECgQJBgAAAA==.Ravelin:BAAALgADCggJEAAAAA==.',
Re='Regrowth:BAABLgAECn8kAAQfAAgJfh+eFQCJAgAfAAgJfh+eFQCJAgAdAAEJMxbtLwBIAAAeAAEJKALxjgAeAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJCAAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgANAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAIKAAcJZRkMAQD/AQAKAAcJZRkMAQD/AQAuAAQKfxwAAgoACAmbJbQBAGgDAAoACAmbJbQBAGgDAAAA.Ruhai:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràistlin:BAAALgAECgYJEAAAAA==.',
Sa='Saelki:BAAALgADCgcJBwAAAA==.',
Se='Sephiran:BAABLgAECn8YAAMgAAgJhxwLEgBqAgAgAAgJhxwLEgBqAgAcAAcJ1hUjEQB8AQAAAA==.',
Sh='Shagra:BAAALgADCgkJEAAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgQJCwAAAA==.Shoepert:BAABLgAECn8jAAIJAAgJhiIfAgDLAgAJAAgJhiIfAgDLAgAAAA==.',
Si='Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBgABLgAECgYJBgAUAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgMJAwAAAA==.',
Te='Tempus:BAACLgAFFH8FAAIIAAMJ1BwQDwAOAQAIAAMJ1BwQDwAOAQAuAAQKfxsAAwgACAkSG18kAAACAAgACAkSG18kAAACAAUAAQnJAtxOAS0AAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJDwAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Ty='Tyrgrim:BAAALgAECgMJAwAAAA==.',
Ul='Ulfhednósh:BAAALgADCgcJBwAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgAUAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8ZAAMhAAgJFxT6CAC4AQAhAAgJFxT6CAC4AQAEAAEJ6QEyoQAZAAAAAA==.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8XAAIbAAUJaR2aAQDFAQAbAAUJaR2aAQDFAQAuAAQKfywAAxsACQm5Hh0FAP8CABsACQm5Hh0FAP8CACAAAwmpCIczAGoAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAIQAAUJxRMXBABvAQAQAAUJxRMXBABvAQAuAAQKfxQAAxAACAncHTISAOgBABAACAn8HDISAOgBABEABgn9Gjh+AIcBAAAA.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgADCggJDQAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Xa='Xamot:BAAALgAECgEJAQABLgAECgIJAwAUAAAAAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJBwAAAA==.',
Zi='Zilgius:BAABLgAECn8XAAIJAAcJZhnBDgDKAQAJAAcJZhnBDgDKAQABLgAECggJGAAgAIccAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
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

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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Paladin-Holy','Warrior-Fury','Warrior-Protection','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation','Mage-Frost','Mage-Fire','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Druid-Feral','Druid-Balance','Druid-Restoration','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aandheeog:BAAALgAECgYJDAAAAA==.',
Ab='Absqwas:BAAALgADCggJEgAAAA==.',
Ad='Adrax:BAAALgADCgcJDAAAAA==.',
Ah='Aheeaheehahe:BAABLgAECn8rAAMBAAgJnhtEFQAlAgABAAgJnhtEFQAlAgACAAIJsAKzgQBAAAAAAA==.',
Ai='Ailanissa:BAAALgAECgQJCQAAAA==.Ailasaa:BAABLgAECn8SAAQDAAUJwCV6BwAOAgADAAUJwCV6BwAOAgAEAAIJgxfWhQCIAAAFAAEJXgGhSQAWAAAAAA==.',
Am='Ametiszt:BAAALgAECgkJAQAAAA==.',
An='Anbraxas:BAAALgAECgMJAwAAAA==.Aneesa:BAABLgAECn8YAAMGAAcJ3BUZawAXAQAGAAcJ3BUZawAXAQAHAAEJowP/NQAhAAAAAA==.',
Ar='Artax:BAAALgAECgYJDwAAAA==.',
As='Asdanot:BAABLgAECn8ZAAIIAAgJLRAiFwCJAQAIAAgJLRAiFwCJAQAAAA==.Ashbahn:BAABLgAECn8rAAMJAAkJPQpuIQB8AQAJAAkJPQpuIQB8AQAGAAUJlBMZdQACAQAAAA==.Ashes:BAAALgAECgQJCQABLgAECgkJKwAJAD0KAA==.Ashmodai:BAAALgADCgQJBAAAAA==.Astovidatu:BAAALgAECgkJBwAAAA==.',
Au='Auroranova:BAABLgAECn8dAAMGAAgJMgjKWQA9AQAGAAgJMgjKWQA9AQAJAAEJxAP/bQAiAAAAAA==.',
Ax='Axél:BAAALgAECgQJBwAAAA==.',
Be='Berringer:BAAALgAECgQJCgAAAA==.',
Bi='Bigbuns:BAAALgAECgQJBAAAAA==.',
Bl='Bluedreamm:BAAALgAECgQJCAAAAA==.',
Br='Braei:BAAALgAECgMJAwAAAA==.Brilleleante:BAAALgADCgYJCwAAAA==.Broxmorn:BAAALgAECgEJAQAAAA==.',
Ca='Cala:BAAALgAFFAMJBAABLgAFFAYJEQACAGQhAA==.Canimai:BAABLgAECn8lAAMKAAgJHhH3HACBAQAKAAgJaw73HACBAQALAAMJpxEHKgBxAAAAAA==.Carla:BAAALgADCgkJEAAAAA==.',
Ch='Chudmeister:BAAALgAECgcJBgAAAA==.',
Co='Colin:BAAALgAECgQJCQABLgAECgkJCgAMAAAAAA==.',
Cr='Crazynaga:BAABLgAECn8VAAIEAAYJnwVNlgDwAAAEAAYJnwVNlgDwAAAAAA==.Crisspy:BAACLgAFFH8HAAMNAAMJfwEAHwCqAAANAAMJfwEAHwCqAAAOAAIJtwYDHACIAAAuAAQKfyUAAw0ACAlaEKIaAHoBAA0ACAlaEKIaAHoBAA4AAQkkB8d8ADQAAAAA.',
Cu='Cubes:BAACLgAFFH8WAAMPAAYJcR95AAAjAgAPAAUJMiZ5AAAjAgAQAAEJ5RISJABQAAAuAAQKfy0ABA8ACQm1JRYBALgDAA8ACQm1JRYBALgDABEABgnNGJgtAKMBABAAAwk/DjE6AKAAAAAA.Cutebunny:BAAALgADCgYJBgAAAA==.',
Da='Daisyspark:BAAALgAECgEJAwAAAA==.',
De='Deathcrocker:BAECLgAFFH8aAAISAAYJoCVKAACGAgASAAYJoCVKAACGAgAuAAQKfxoAAhIACQkDJmwAAMsDABIACQkDJmwAAMsDAAEuAAUUBwkPABEArSIA.Decksters:BAAALgADCgYJCQAAAA==.',
Di='Divinebeef:BAABLgAECn8WAAIGAAgJBBcmTQD7AQAGAAgJBBcmTQD7AQABLgAFFAQJDwAGAN4YAA==.',
Do='Dogs:BAACLgAFFH8LAAIKAAQJxBoMCgBSAQAKAAQJxBoMCgBSAQAuAAQKfxsAAgoACAnrG9YNAOYCAAoACAnrG9YNAOYCAAEuAAUUBwkVAAYA5xsA.Domar:BAAALgAECgQJBwAAAA==.Doomslayer:BAABLgAECn8kAAMTAAkJ7BrZHgAPAgATAAkJ7BrZHgAPAgASAAUJgALzMwCgAAAAAA==.Doraei:BAAALgAECgYJDAAAAA==.Dothippo:BAABLgAECn8qAAMUAAcJthtbAwDyAQAUAAcJthtbAwDyAQAVAAEJFgRvKAEpAAAAAA==.',
Dr='Drutastic:BAAALgAECgIJAgAAAA==.',
Du='Dumach:BAAALgADCgYJBgAAAA==.Dunk:BAABLgAECn8gAAIGAAkJSReLJADxAQAGAAkJSReLJADxAQAAAA==.',
Ea='Easy:BAAALgAECgIJBAABLgAECgYJBgAMAAAAAA==.',
Ec='Eclipsus:BAAALgADCgcJCAAAAA==.',
Ed='Edamen:BAAALgAECgUJBQAAAA==.',
Eh='Ehrathorn:BAAALgAECgIJAgAAAA==.',
El='Elf:BAAALgADCgUJBQAAAA==.Elijah:BAAALgAECgYJBgAAAA==.Elunëth:BAAALgADCgQJBAABLgAFFAQJDQAWAPEXAA==.',
Ep='Ephie:BAAALgADCgcJBwAAAA==.',
Et='Ether:BAAALgAECgMJBQAAAA==.',
Fa='Faedryl:BAAALgADCgQJBAAAAA==.Fandrin:BAAALgADCgUJBQAAAA==.Farg:BAAALgAECgEJAQAAAA==.Farslaw:BAAALgAECgQJBQAAAA==.',
Fe='Feledara:BAAALgAECgcJEwAAAA==.',
Fi='Fionaweaver:BAAALgADCgIJAgAAAA==.',
Fr='Freezing:BAAALgAECgEJAgAAAA==.Frieren:BAACLgAFFH8SAAIXAAcJ5xqACgDLAQAXAAcJ5xqACgDLAQAuAAQKfyEABBcACQl9IlsNAFoDABcACQl9IlsNAFoDABgAAQnTIAcNAFkAABkAAQkbDxwaAEcAAAAA.Froslass:BAABLgAECn8VAAITAAgJSRqhJQDqAQATAAgJSRqhJQDqAQAAAA==.',
Fu='Funk:BAAALgAECgEJAQAAAA==.',
Ge='Gencrocker:BAAALgAECgMJAwAAAA==.Getoffenris:BAAALgAECgQJBQAAAA==.',
Gl='Gloryhammer:BAABLgAECn8jAAQHAAgJARuLCABPAgAHAAgJARuLCABPAgAJAAUJKAXBawDLAAAGAAEJaxmeQwEzAAAAAA==.',
Go='Gobbs:BAABLgAECn8YAAMaAAYJIBKJCwBzAQAaAAYJ4g+JCwBzAQAbAAYJEBGqGAA+AQABLgAECggJHgABAJAbAA==.',
Gr='Gripmedaddy:BAAALgADCgcJBwAAAA==.',
Ha='Haldrian:BAAALgAECgMJAwAAAA==.Havack:BAAALgADCgEJAQAAAA==.',
He='Healslvt:BAAALgAECgEJAQAAAA==.Hexkitten:BAAALgAECgYJEwAAAA==.',
Hi='Hixon:BAAALgADCgMJAgAAAA==.',
Ho='Holyhota:BAACLgAFFH8JAAMcAAQJyRimCgC6AAAcAAMJMB2mCgC6AAAdAAMJQwoWHAC3AAAuAAQKfxcAAxwACAk7IdMLAJMCABwACAk7IdMLAJMCAB0AAQmED3lHADEAAAAA.Hop:BAABLgAECn8gAAIeAAgJoxpWBQABAgAeAAgJoxpWBQABAgAAAA==.Hota:BAAALgAECgYJBwABLgAFFAQJCQAcAMkYAA==.Hotamnk:BAAALgAECgMJAwABLgAFFAQJCQAcAMkYAA==.',
Ir='Iraedies:BAAALgADCgEJAQAAAA==.Ironborn:BAAALgAECgQJBgAAAA==.',
Iv='Ivakor:BAAALgAECgUJCgAAAA==.Ivyy:BAACLgAFFH8MAAIfAAMJACQvDwA6AQAfAAMJACQvDwA6AQAuAAQKfxcAAh8ACAkSIrQNAMACAB8ACAkSIrQNAMACAAEuAAUUBQkXABsA1SIA.',
Ja='Jackswagz:BAABLgAECn8hAAMOAAkJgRNhHQDGAQAOAAkJgRNhHQDGAQANAAMJCQcoSQCBAAAAAA==.Jaszuny:BAABLgAECn8gAAIDAAgJVRSoBQCwAQADAAgJVRSoBQCwAQAAAA==.',
Je='Jezlyn:BAAALgAECgUJBQAAAA==.',
Ka='Kaladyn:BAAALgADCgIJAgABLgAECgcJDAAMAAAAAA==.Katsumotosan:BAAALgADCggJDAAAAA==.',
Ke='Kev:BAABLgAECn8qAAQXAAcJ6SQhFAB5AgAXAAcJ6SQhFAB5AgAZAAIJMiTaDwDEAAAYAAEJAAA8EgAXAAAAAA==.',
Ko='Kombatgodess:BAAALgADCgcJDQAAAA==.',
Ku='Kurgen:BAAALgADCgUJCgAAAA==.',
Kv='Kvasir:BAABLgAECn8aAAITAAcJFBopOQCVAQATAAcJFBopOQCVAQAAAA==.',
['Kâ']='Kânna:BAAALgAECgQJBQAAAA==.',
La='Lalaise:BAAALgAECgMJAwAAAA==.Lanaria:BAAALgAECgMJAwAAAA==.Lancayne:BAAALgADCgIJAQAAAA==.',
Li='Lichkingstoy:BAACLgAFFH8PAAIGAAQJ3hg1CgBbAQAGAAQJ3hg1CgBbAQAuAAQKfx0AAgYACAk0HdoxAFsCAAYACAk0HdoxAFsCAAAA.Lieb:BAAALgAECgMJAwAAAA==.Littlecutie:BAAALgADCgMJAwAAAA==.',
Lo='Lolamarie:BAAALgADCgQJCQAAAA==.',
Lu='Lunareclipse:BAAALgAECgIJAgAAAA==.Luniaira:BAAALgAECggJDgAAAA==.',
Ma='Maedy:BAAALgADCgQJBAABLgAECgkJGAAIACsIAA==.Maegii:BAAALgADCgEJAQAAAA==.Manta:BAABLgAECn8ZAAMTAAcJeQ09jwBiAQATAAcJPA09jwBiAQASAAEJsQ25RgAtAAAAAA==.Maroon:BAAALgAECggJEwAAAA==.',
Me='Menasor:BAAALgADCgQJBAAAAA==.',
Mi='Micaa:BAAALgAECgYJEAAAAA==.Minarielle:BAAALgADCgUJBQAAAA==.Miracle:BAAALgAFFAMJBAAAAA==.Mirana:BAAALgADCgEJAQAAAA==.Mirzza:BAAALgAECgEJAQAAAA==.Mistake:BAAALgAECgYJEAAAAA==.',
Mo='Mockra:BAAALgADCgEJAQABLgAECgIJAgAMAAAAAA==.Monkcrocker:BAECLgAFFH8PAAIRAAcJrSINAADaAgARAAcJrSINAADaAgAuAAQKfxUAAhEABwnxJcENALcCABEABwnxJcENALcCAAAA.',
Mv='Mvmx:BAAALgAECgIJAgAAAA==.',
['Mé']='Méthan:BAAALgADCgQJBAAAAA==.',
Na='Nabarke:BAAALgAECgMJAwAAAA==.Naztherune:BAAALgADCgQJBQAAAA==.',
Ni='Nier:BAAALgAECgMJBgAAAA==.Nightsilver:BAAALgADCggJEgAAAA==.',
No='Nosidh:BAAALgAECgMJBAAAAA==.Nospheratus:BAAALgAECgEJAQABLgAFFAMJBwASACoHAA==.Notsofresh:BAAALgADCgMJAwAAAA==.',
Ny='Nylianna:BAACLgAFFH8IAAIGAAIJRxv7PAC0AAAGAAIJRxv7PAC0AAAuAAQKfycAAgYACQkAHWYMACsDAAYACQkAHWYMACsDAAAA.',
Og='Ogganborn:BAAALgAECgYJEwAAAA==.',
On='Oneira:BAAALgADCggJDQAAAA==.',
Or='Orange:BAAALgAECgQJBQAAAA==.Orrark:BAAALgADCgEJAQAAAA==.',
Pi='Pikal:BAABLgAECn8bAAIGAAcJ2RJOSQBpAQAGAAcJ2RJOSQBpAQAAAA==.',
Pr='Priestigory:BAABLgAECn8tAAMRAAkJZhy9BACdAgARAAkJZhy9BACdAgAPAAIJIRNaYwCBAAAAAA==.',
Pv='Pvtcrocker:BAAALgAECgcJEgAAAA==.',
Py='Pyrithyr:BAAALgAECgUJBwAAAA==.',
Qu='Quelyne:BAAALgADCgMJAwAAAA==.Quink:BAAALgADCggJDwAAAA==.Quintus:BAAALgAECgQJAwAAAA==.',
Ra='Raevaela:BAAALgADCgQJBwABLgAECgcJFQAPABkcAA==.Railiana:BAAALgAECgUJCwAAAA==.Ravelin:BAAALgADCgkJGQAAAA==.',
Re='Regrowth:BAABLgAECn8qAAQgAAgJ9x+aFQCJAgAgAAgJ9x+aFQCJAgAeAAMJVxVMGwCKAAAfAAEJKAL3jgAeAAAAAA==.Reminesce:BAAALgADCgEJAQAAAA==.',
Rh='Rholune:BAAALgAECgUJCQAAAA==.',
Ro='Roberta:BAAALgADCgQJBgAAAA==.',
Rp='Rplooker:BAAALgADCgcJEgABLgAECgcJFgAPAJwPAA==.',
Ru='Ruby:BAACLgAFFH8NAAILAAcJZRkNAQD/AQALAAcJZRkNAQD/AQAuAAQKfxwAAgsACAmbJbQBAGgDAAsACAmbJbQBAGgDAAAA.Ruhai:BAAALgAECgYJCwAAAA==.',
['Rà']='Ràistlin:BAABLgAECn8VAAIXAAYJNA5XcQAuAQAXAAYJNA5XcQAuAQAAAA==.',
Sa='Saelki:BAAALgADCgcJBwAAAA==.',
Se='Sephiran:BAABLgAECn8gAAMhAAgJmBwKEgBqAgAhAAgJmBwKEgBqAgAdAAgJjheRDAAHAgAAAA==.',
Sh='Shagra:BAAALgAECgUJBQAAAA==.Shagraq:BAAALgADCgEJAQAAAA==.Shielen:BAAALgAECgUJEAAAAA==.Shoepert:BAABLgAECn8qAAIKAAkJ7CR1AABhAwAKAAkJ7CR1AABhAwAAAA==.',
Si='Sifrina:BAAALgADCgEJAQAAAA==.Sini:BAAALgAECgcJBQAAAA==.Sinna:BAAALgAECgkJBwAAAA==.',
So='Southpaw:BAAALgAECgIJAgAAAA==.',
Sp='Splatugle:BAAALgAECgcJBQAAAA==.',
Sw='Sway:BAAALgAECgUJBwABLgAECgYJBgAMAAAAAA==.',
Ta='Tairn:BAAALgADCgQJBgAAAA==.Taluria:BAAALgAECgMJAwAAAA==.',
Te='Tempus:BAACLgAFFH8HAAIJAAMJjx4lFAAQAQAJAAMJjx4lFAAQAQAuAAQKfxwAAwkACAkOG14kAAACAAkACAkOG14kAAACAAYAAQnJAtROAS0AAAAA.',
Th='That:BAAALgADCgYJBgAAAA==.',
Ti='Tikimon:BAAALgADCgYJDwAAAA==.',
To='Tobofrog:BAAALgAECgkJCwAAAA==.Toboo:BAAALgAECgcJBgAAAA==.Tolocforu:BAAALgAECgQJBgAAAA==.',
Tr='Trainedtiger:BAAALgAFFAEJAQAAAA==.',
Ty='Tyrgrim:BAAALgAECgMJAwAAAA==.',
Ul='Ulfhednósh:BAAALgAECgIJAgAAAA==.',
Un='Union:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Unwavering:BAAALgADCgEJAQAAAA==.',
Up='Uppies:BAAALgAECgQJBwAAAA==.',
Uw='Uwuforyou:BAABLgAECn8ZAAMFAAgJHxRbDQCrAQAFAAgJHxRbDQCrAQAEAAEJ5wHd0gAZAAAAAA==.',
Va='Valalexis:BAAALgADCgcJBwAAAA==.',
Ve='Velawynn:BAACLgAFFH8ZAAIcAAYJix+/AAAlAgAcAAYJix+/AAAlAgAuAAQKfy4AAxwACQm6Hh0FAP8CABwACQm6Hh0FAP8CACEABAleDtcyAMUAAAAA.Velladonna:BAAALgADCgIJAgAAAA==.Veronica:BAACLgAFFH8HAAISAAUJxRMYBABvAQASAAUJxRMYBABvAQAuAAQKfxQAAxIACAncHTISAOgBABIACAn8HDISAOgBABMABgn9Gi1+AIcBAAAA.',
Vh='Vhenir:BAAALgADCgUJCwAAAA==.',
Vi='Vixa:BAAALgAECgMJAwAAAA==.',
Vo='Voidbro:BAAALgAECgMJBQAAAA==.',
Xa='Xamot:BAAALgAECgUJBQAAAA==.Xarou:BAAALgAECgQJBgAAAA==.',
Ya='Yanyan:BAAALgAECgUJCwAAAA==.',
Zi='Zilgius:BAABLgAECn8dAAMLAAcJSRyPCwCuAQAKAAcJZRksFgC3AQALAAYJ7h2PCwCuAQABLgAECggJIAAhAJgcAA==.Zinjari:BAAALgADCgEJAQAAAA==.',
Zy='Zynri:BAAALgADCgYJBwAAAA==.',
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

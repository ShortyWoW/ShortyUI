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

local lookup = {'Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Warrior-Fury','Evoker-Preservation','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Retribution','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Druid-Guardian','Paladin-Holy','Paladin-Protection','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','Hunter-Survival','Evoker-Augmentation','Shaman-Enhancement','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abrams:BAAALgAECgYJEwAAAA==.',
Ad='Addý:BAABLgAECn8VAAIBAAgJJxmAEwDsAQABAAgJJxmAEwDsAQAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn8dAAICAAgJFhqNAwDtAQACAAgJFhqNAwDtAQAAAA==.',
Al='Alisonchains:BAABLgAECn8UAAIDAAYJRB0BDACpAQADAAYJRB0BDACpAQAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Alternate:BAABLgAECn8ZAAIEAAgJhw9eMgCbAQAEAAgJhw9eMgCbAQAAAA==.',
Am='Amillerbrew:BAABLgAECn8aAAIFAAgJTxaVJQDXAQAFAAgJTxaVJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
As='Ashenclaw:BAABLgAECn8UAAIGAAcJWBPYAwChAQAGAAcJWBPYAwChAQAAAA==.',
Au='Auzatryx:BAAALgAECgMJAwAAAA==.',
Ba='Bamboom:BAAALgAECgQJCwAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAQAAAA==.Belanik:BAAALgAECgEJAQAAAA==.',
Bi='Bigblktotem:BAAALgAECgYJDwABLgAECggJIQAHACQeAA==.Biggrnmonstr:BAAALgADCgMJAwABLgAECggJIQAHACQeAA==.Bigrabit:BAAALgADCgIJAwAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgEJAgAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8iAAMIAAgJsRsAAwA5AgAIAAgJsRsAAwA5AgAJAAEJKwmMTQAiAAAAAA==.',
Br='Breakfast:BAAALgAECgEJAQAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8GAAIKAAMJ1iNFCgBDAQAKAAMJ1iNFCgBDAQAuAAQKfxcAAgoACAnxIYAHADEDAAoACAnxIYAHADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.',
Ca='Cabooze:BAAALgADCgkJDQAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8aAAILAAgJJxcdEQAqAgALAAgJJxcdEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJFAAJAJoYAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAUJCAAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFgAAAA==.',
Da='Daevon:BAAALgAECgQJDwAAAA==.Daron:BAAALgAECgcJDgAAAA==.Darrowreaper:BAAALgAECgYJDgAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Denarrage:BAABLgAECn8jAAIMAAgJAxIyCwCKAQAMAAgJAxIyCwCKAQAAAA==.',
Di='Discordia:BAAALgAECggJDQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Dontnerfspls:BAAALgAECgMJBQABLgAECggJIQAHACQeAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgADCgcJBwAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgADCgkJDQAAAA==.Ellipsoro:BAABLgAECn8rAAIHAAgJcyVLAwABAwAHAAgJcyVLAwABAwAAAA==.Eltrol:BAAALgAECggJCAAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8UAAIJAAcJmhjpAADiAQAJAAcJmhjpAADiAQAuAAQKfyIAAgkACQmgILcCADsDAAkACQmgILcCADsDAAAA.',
Fa='Faeris:BAACLgAFFH8FAAMNAAIJrBP4FgCfAAANAAIJrBP4FgCfAAAOAAEJMQ2oEgBPAAAuAAQKfyEAAw4ACQkmItMBAFkDAA4ACQkmItMBAFkDAA0AAgmIF4JFAI0AAAAA.Faolain:BAABLgAECn8kAAIBAAgJQBFxHgCNAQABAAgJQBFxHgCNAQAAAA==.Fatalis:BAACLgAFFH8GAAIPAAQJIgNVGgD9AAAPAAQJIgNVGgD9AAAuAAQKfyIAAw8ACQnVEbIhAJgBAA8ACAktFLIhAJgBAAIACAlcBO9RAAUBAAAA.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgADCgMJAwAAAA==.Fizaw:BAABLgAECn8dAAIQAAgJKwYuIwDmAAAQAAgJKwYuIwDmAAAAAA==.',
Fl='Floydbussy:BAAALgAFFAMJAwAAAA==.',
Fr='Frøzen:BAAALgAECgEJAQAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIRAAgJ6xOvZgCzAQARAAgJ6xOvZgCzAQAAAA==.',
Ga='Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBAAAAA==.Gazzcool:BAAALgAECgQJBgAAAA==.',
Ge='Geneviere:BAAALgAECgEJAgAAAA==.Gex:BAAALgAECgYJBgAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAISAAMJWBpPCQAFAQASAAMJWBpPCQAFAQAuAAQKfx0AAhIACQlUJQkBALsDABIACQlUJQkBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMTAAgJTxHMOgCWAQATAAgJTxHMOgCWAQAUAAYJ0gzdLADNAAAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gothmogsbane:BAABLgAECn8VAAMBAAcJZhMoKQBBAQABAAYJvBEoKQBBAQAVAAcJlAS3UgDcAAAAAA==.',
Gr='Greyspirit:BAABLgAECn8dAAIWAAgJwh3FAgAqAgAWAAgJwh3FAgAqAgAAAA==.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECggJHAATALsYAA==.',
Gu='Gumpy:BAAALgAECgcJCwAAAA==.',
Ha='Halcoldrek:BAAALgADCgYJBgAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.',
He='Heyz:BAABLgAECn8hAAMNAAgJfBt3BACGAgANAAgJfBt3BACGAgAOAAEJkwCeigAhAAAAAA==.',
Hi='Himbo:BAAALgAECgcJCQAAAA==.Hipocrit:BAAALgAECgYJCAAAAA==.',
Ho='Holypoopp:BAABLgAECn8hAAMRAAgJpxmEJACyAQARAAcJUhqEJACyAQAXAAUJJBZzSgBOAQAAAA==.Hondalorian:BAABLgAECn8kAAIPAAgJQxSnFwDVAQAPAAgJQxSnFwDVAQAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgADCgYJBgAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Im='Imran:BAACLgAFFH8FAAIYAAIJXwu0BQBnAAAYAAIJXwu0BQBnAAAuAAQKfykAAxgACQmYE98FANABABgACQmYE98FANABABEABwmhBJ3PAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAAALgAECgYJDwAAAA==.',
Je='Jether:BAAALgAECgUJCAAAAA==.',
Jk='Jkingoreborn:BAAALgAECgYJDgABLgAECgYJDwAZAAAAAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECggJDwAZAAAAAA==.Jojobaggins:BAABLgAECn8XAAQaAAcJ4hnHBwAmAQADAAUJeRdgMQB9AQAbAAQJLBpUBwAwAQAaAAYJcxTHBwAmAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECggJDwAZAAAAAA==.',
Ka='Kaadriluna:BAAALgADCgEJAQAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJDQAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8IAAIcAAQJih0HCQAKAQAcAAQJih0HCQAKAQABLgAFFAcJFAAJAJoYAA==.Keyohs:BAAALgAECgIJAgABLgAFFAcJFAAJAJoYAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECggJHAATALsYAA==.',
Kk='Kkoda:BAAALgADCgIJAgAAAA==.',
Ko='Koal:BAABLgAECn8UAAIPAAgJJhWoHwCjAQAPAAgJJhWoHwCjAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAgJGwACAOchAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAAALgAECgcJDAABLgAECggJHAATAOIOAA==.',
Ku='Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMPAAgJhQ8bHQCxAQAPAAgJhQ8bHQCxAQACAAYJ/grsSgAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lettussy:BAAALgAFFAQJBAABLgAFFAUJCgAEAF4VAA==.',
Li='Lix:BAAALgAECgUJDwAAAA==.',
Lo='Loliruri:BAAALgAECgYJCAAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgADCgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúthien:BAABLgAECn8nAAIQAAkJECCLAgDpAgAQAAkJECCLAgDpAgAAAA==.',
Ma='Madoka:BAAALgAECgYJCwAAAA==.Makari:BAAALgADCgIJAgAAAA==.Matrix:BAAALgAECgEJAQAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn8oAAMHAAkJcx8ECACeAgAHAAkJcx8ECACeAgAcAAYJPQ8TJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meloo:BAAALgAECgYJEQAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mikehawncho:BAAALgAECgEJAgABLgAECgcJHAAHAFUbAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8VAAIGAAcJfhjoAwCeAQAGAAcJfhjoAwCeAQAAAA==.Morthrisia:BAAALgADCgUJBQAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAAALgAECgYJCQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
Na='Naerys:BAAALgAECgYJCgAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgADCgQJBQAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8aAAMdAAgJPhq9PgD5AQAdAAgJPhq9PgD5AQAMAAEJiRUOcAA1AAAAAA==.',
Ni='Niddalee:BAAALgADCgYJBgAAAA==.Nitesrider:BAAALgAECgQJBAAAAA==.',
No='Nora:BAACLgAFFH8SAAIRAAcJlh/4AAACAgARAAcJlh/4AAACAgAuAAQKfy4AAhEACQlLJn8BADgDABEACQlLJn8BADgDAAAA.Nori:BAAALgADCgkJDgABLgAFFAYJGgAEAPgmAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.',
Nu='Nubbs:BAABLgAECn8VAAISAAcJcRy9CgDKAQASAAcJcRy9CgDKAQAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAQJBgAFADwIAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='Onlyinusa:BAAALgAECgYJCgAAAA==.Onyxnate:BAAALgADCgkJHwAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAZAAAAAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJDwAZAAAAAA==.',
Pi='Pinkdefender:BAAALgAECgYJBgABLgAECggJIQAHACQeAA==.',
Po='Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAABLgAECn8hAAMHAAgJJB64LwB5AgAHAAgJJB64LwB5AgAcAAQJbwcWNwCJAAAAAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8XAAIdAAgJFR7XAACgAgAdAAgJFR7XAACgAgAuAAQKfyYAAx0ACQmoJXcBAMgDAB0ACQmoJXcBAMgDAAwABwn/I6QUACsCAAAA.',
Pu='Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8XAAIeAAcJwwpYIAD5AAAeAAcJwwpYIAD5AAAAAA==.',
Ra='Raelindra:BAAALgAECggJDwAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgQJBwAAAA==.',
Re='Rebuke:BAAALgAECgYJDQAAAA==.',
Ro='Rookorblood:BAAALgAECgYJCgAAAA==.Rosewalker:BAACLgAFFH8JAAIFAAQJRBp7CQA/AQAFAAQJRBp7CQA/AQAuAAQKfx4AAwUACAkCI6sMAMUCAAUACAkCI6sMAMUCABIABgnlFQMTAFkBAAAA.Rosewall:BAAALgAECgEJAQABLgAFFAQJCQAFAEQaAA==.Rottgut:BAAALgAECgUJCAAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn8fAAQPAAgJFhbTMQDoAQAPAAcJrRbTMQDoAQACAAQJNA8bXgDIAAAfAAIJgwJLKgBLAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQIAAgJ/BV8DwCkAQAKAAcJiRZPMgDjAQAIAAcJzBR8DwCkAQAJAAQJMxAiLgDRAAAAAA==.Savork:BAAALgAECgYJDwAAAA==.Sayafaed:BAAALgAECggJDgAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn8oAAQOAAgJ0BmUBgBOAgAOAAgJRBmUBgBOAgANAAYJ2xE+EgBuAQAeAAIJMgnnPgA7AAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAAALgAECggJEQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Senuna:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAAALgAECgkJDwAAAA==.Shadôwhunt:BAABLgAECn8fAAIHAAgJYxWLNABnAQAHAAgJYxWLNABnAQAAAA==.Shenlon:BAACLgAFFH8VAAMGAAUJbyXkAQB9AQAGAAUJbyXkAQB9AQAgAAIJ/iGzFADNAAAuAAQKfy4ABAYACQm9JJMAAI0DAAYACQmOIZMAAI0DAAsABQlhHT8IAKcBACAABAmJI8klAI8BAAAA.Shilor:BAABLgAECn8WAAINAAYJPhjdEACBAQANAAYJPhjdEACBAQAAAA==.Shogun:BAAALgAECgUJBwAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgAZAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinistr:BAABLgAECn8WAAMTAAcJChyiJwDyAQATAAcJChyiJwDyAQAhAAQJIAUdIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBgAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBgAZAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgADCgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stélle:BAAALgAECgMJAwAAAA==.',
Su='Supdude:BAABLgAECn8hAAMDAAgJ7ByBBABHAgADAAgJ4xyBBABHAgAbAAEJaRz2DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thorokk:BAAALgAECgEJAQAAAA==.Thynrage:BAAALgAECgUJBQAAAA==.',
Ti='Tigas:BAABLgAECn8cAAIKAAcJ5SJABQBoAgAKAAcJ5SJABQBoAgAAAA==.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJDgAZAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8gAAMGAAgJKSDpAgDNAQAgAAgJ6R2yDgCKAgAGAAgJVRzpAgDNAQAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.',
['Tö']='Töby:BAAALgAECgcJCwABLgAECgcJDgAZAAAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAAALgAECgYJEAAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECgcJEwAZAAAAAA==.',
Va='Vannacutt:BAAALgAECgcJEwAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgADCgUJBQAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAABLgAECn8fAAMdAAgJyhOLLgApAQAMAAYJghg0JgCOAQAdAAgJqQ6LLgApAQAAAA==.',
Wa='Wasabi:BAAALgAECgcJDwAAAA==.',
We='Weenygripper:BAAALgAECgUJCQABLgAFFAMJBQAEAE4XAA==.',
Wo='Wonon:BAAALgAECgEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaida:BAAALgAECgYJBgABLgAFFAgJIgALAFIaAA==.',
Xe='Xecutioner:BAAALgADCgEJAQAAAA==.',
Xi='Xilantaeki:BAAALgADCgIJAgAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEALgAECggJEQAAAA==.Zanmetsu:BAEBLgAECn8ZAAMDAAcJrRyQGABDAgADAAcJrRyQGABDAgAaAAEJjgzpHgA4AAABLgAECggJEQAZAAAAAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn8cAAMTAAgJuxiEKQDpAQATAAgJuxiEKQDpAQAUAAQJeRCgKADkAAAAAA==.Zerocool:BAABLgAECn8eAAIiAAgJwBQoQgAGAgAiAAgJwBQoQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgEJAQAAAA==.Zugzug:BAAALgADCgMJAwAAAA==.',
Zy='Zyggy:BAAALgAECgYJCgAAAA==.',
['ßa']='ßadfish:BAABLgAECn8aAAIRAAgJXSDsGADUAgARAAgJXSDsGADUAgAAAA==.',
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

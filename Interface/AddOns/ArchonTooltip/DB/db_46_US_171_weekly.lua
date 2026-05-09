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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Druid-Guardian','Paladin-Holy','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Priest-Shadow','Hunter-Survival','Shaman-Enhancement','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abrams:BAABLgAECn8VAAIBAAcJuBnbNgCiAQABAAcJuBnbNgCiAQAAAA==.',
Ad='Addý:BAABLgAECn8XAAICAAkJfxfOFQAXAgACAAkJfxfOFQAXAgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn8lAAIDAAgJhxr8AwAJAgADAAgJhxr8AwAJAgAAAA==.',
Al='Alisonchains:BAABLgAECn8aAAIEAAYJSCGNDADYAQAEAAYJSCGNDADYAQAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Alternate:BAABLgAECn8iAAIFAAkJIxRkIQAkAgAFAAkJIxRkIQAkAgAAAA==.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIGAAgJTxaVJQDXAQAGAAgJTxaVJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
As='Ashenclaw:BAABLgAECn8VAAIHAAgJLhFgBACwAQAHAAgJLhFgBACwAQAAAA==.',
Au='Auzatryx:BAAALgAECgYJCQAAAA==.',
Ba='Bamboom:BAAALgAECgQJDwAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJAgAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAAALgAECgYJDwABLgAFFAMJBwAIAKUVAA==.Biggrnmonstr:BAAALgAECgYJBgABLgAFFAMJBwAIAKUVAA==.Bigrabit:BAAALgADCgIJAwAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgIJAwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8iAAMJAAgJtBsDBQAsAgAJAAgJtBsDBQAsAgAKAAEJKwmKTQAiAAAAAA==.',
Br='Breakfast:BAAALgAECgEJAQAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8KAAILAAQJLSTlAgCfAQALAAQJLSTlAgCfAQAuAAQKfxoAAgsACAnyIX0HADEDAAsACAnyIX0HADEDAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.',
Ca='Cabooze:BAAALgAECgMJAwAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAIMAAgJeBgdEQAqAgAMAAgJeBgdEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chartreuse:BAAALgADCgMJBAABLgAECgUJBQANAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJFAAKAJ4YAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAUJDQAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJCAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgAAAA==.Darrowreaper:BAAALgAECgcJEQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Denarrage:BAABLgAECn8sAAIOAAkJ2hRICAAQAgAOAAkJ2hRICAAQAgAAAA==.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAAALgADCgIJAgAAAA==.Discordia:BAAALgAECggJDQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Dontnerfspls:BAAALgAECgMJBQABLgAFFAMJBwAIAKUVAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgAECgYJDAABLgAECgYJEQANAAAAAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elixxi:BAAALgAECgQJBAAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgEJAQAAAA==.Ellipsoro:BAACLgAFFH8GAAIPAAIJDSIMXgC/AAAPAAIJDSIMXgC/AAAuAAQKfy4AAg8ACQl2JXYBAGoDAA8ACQl2JXYBAGoDAAAA.Eltrol:BAAALgAFFAEJAQAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8UAAIKAAcJnhgTAgC/AQAKAAcJnhgTAgC/AQAuAAQKfyIAAgoACQmiILgCADsDAAoACQmiILgCADsDAAAA.',
Fa='Faeris:BAACLgAFFH8IAAMQAAMJFhJmGADiAAAQAAMJFhJmGADiAAARAAEJMQ2qEgBPAAAuAAQKfyEAAxEACQkkItMBAFkDABEACQkkItMBAFkDABAAAgmIF4NFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBGDKgCAAQACAAgJQBGDKgCAAQAAAA==.Fatalis:BAACLgAFFH8LAAISAAQJeAbQIAASAQASAAQJeAbQIAASAQAuAAQKfyIAAxIACQnbEZUwAO4BABIACAk0FJUwAO4BAAMACAlcBKpRAAYBAAAA.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgADCgMJAwAAAA==.Fizaw:BAABLgAECn8lAAITAAgJfgZwKgD7AAATAAgJfgZwKgD7AAAAAA==.',
Fl='Floydbussy:BAABLgAFFH8GAAIUAAQJWQaGHQD8AAAUAAQJWQaGHQD8AAAAAA==.',
Fr='Freeng:BAAALgADCgYJBgAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Frøzen:BAAALgAECgIJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBAAAAA==.Gazzcool:BAAALgAECgQJBwAAAA==.',
Ge='Geneviere:BAAALgAECgQJBQAAAA==.Gex:BAAALgAECgYJCgAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIVAAMJXBr5DQABAQAVAAMJXBr5DQABAQAuAAQKfx0AAhUACQlUJQgBALsDABUACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMWAAgJUBHNOgCWAQAWAAgJUBHNOgCWAQAXAAYJ3QwWLQACAQAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdRHmNwA3AQACAAYJzRHmNwA3AQAYAAgJLAS7UgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAQJDgAZAHIkAA==.Greyspirit:BAABLgAECn8mAAIaAAkJpx1OAgCWAgAaAAkJpx1OAgCWAgAAAA==.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJJQAWAEYZAA==.',
Gu='Gumpy:BAAALgAECgcJCwAAAA==.',
Ha='Halcoldrek:BAAALgADCgYJBgAAAA==.Hamburguesa:BAAALgAECgEJAQAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.',
He='Heyz:BAABLgAECn8jAAMQAAgJKRxeBgCOAgAQAAgJKRxeBgCOAgARAAEJkwCgigAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAAALgAECgcJCQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgEJAQAAAA==.Holypoopp:BAABLgAECn8qAAMBAAkJhB3dGwAhAgABAAgJgB3dGwAhAgAbAAYJKRR1SgBOAQAAAA==.Hondalorian:BAABLgAECn8sAAISAAgJSBarHQDqAQASAAgJSBarHQDqAQAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgADCgYJBgAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Im='Imran:BAACLgAFFH8KAAIcAAMJPAkbBwCWAAAcAAMJPAkbBwCWAAAuAAQKfyoAAxwACQmhE3QIAMUBABwACQmhE3QIAMUBAAEABwmhBKHPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8VAAILAAYJGhc9IABqAQALAAYJGhc9IABqAQAAAA==.',
Je='Jether:BAAALgAECgUJCwAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8UAAIcAAYJVB2CCwCGAQAcAAYJVB2CCwCGAQABLgAECgcJEwANAAAAAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECggJDwANAAAAAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8YAAQdAAcJ5Rl0CgAfAQAEAAUJeRddMQB8AQAeAAQJLBpSBwAwAQAdAAYJdxR0CgAfAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECggJDwANAAAAAA==.',
Ka='Kaadriluna:BAAALgADCgMJBAAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJDgAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8IAAIIAAQJjh1YDgD7AAAIAAQJjh1YDgD7AAABLgAFFAcJFAAKAJ4YAA==.Keyohs:BAAALgAECgIJAgABLgAFFAcJFAAKAJ4YAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECgkJJQAWAEYZAA==.',
Ki='Kittybear:BAAALgAECgUJBQABLgAFFAcJGgAKABYiAA==.',
Kk='Kkoda:BAAALgAECgMJAwAAAA==.',
Ko='Koal:BAABLgAECn8UAAISAAgJMxUiNADfAQASAAgJMxUiNADfAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAgJGwADAOMhAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAAALgAECgcJDwABLgAECggJIQAWAOQOAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgANAAAAAA==.',
Ku='Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMSAAgJhw9ELACeAQASAAgJhw9ELACeAQADAAYJ/goKSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lettussy:BAABLgAFFH8IAAQeAAQJ5wjgAgAbAQAeAAQJCgfgAgAbAQAdAAEJRwovCgBUAAAEAAEJDgTMIgBIAAABLgAFFAUJEgAFAL4XAA==.',
Li='Lix:BAAALgAECgUJEwAAAA==.',
Lo='Loliruri:BAAALgAECgYJCgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBQAAAA==.Luminyssa:BAAALgAECgYJBgAAAA==.',
['Lú']='Lúthien:BAABLgAECn8rAAITAAkJCSFyAwD+AgATAAkJCSFyAwD+AgAAAA==.',
Ma='Madoka:BAAALgAECgYJCwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Matrix:BAAALgAECgIJAgAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMPAAkJ8iF0BQAHAwAPAAkJ8iF0BQAHAwAIAAYJPQ8RJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meloo:BAAALgAECgYJEQAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgAPAFUbAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8cAAIHAAgJwxl1AgAjAgAHAAgJwxl1AgAjAgAAAA==.Morthrisia:BAAALgADCgUJBQAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAAALgAECgYJDgAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
Na='Naerys:BAAALgAECgcJCwAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgADCgQJBQAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8hAAMfAAkJKBtcCwB3AgAfAAkJKBtcCwB3AgAOAAEJiRUOcAA1AAAAAA==.',
Ni='Niddalee:BAAALgADCgYJBwAAAA==.Nioh:BAAALgAECgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8SAAIBAAcJlh/AAgDwAQABAAcJlh/AAgDwAQAuAAQKfy4AAgEACQlQJhMDACsDAAEACQlQJhMDACsDAAAA.Nori:BAAALgADCgkJDgABLgAFFAYJIAAFAPgmAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgEJAQAAAA==.',
Nu='Nubbs:BAABLgAECn8WAAIVAAgJaxwsCgAXAgAVAAgJaxwsCgAXAgAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAQJCgAGAM4PAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='Onlyinusa:BAAALgAECgYJCgAAAA==.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwANAAAAAA==.Opel:BAAALgADCgUJCAABLgAFFAQJDAAVAPQGAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJDwANAAAAAA==.',
Pi='Pinkdefender:BAAALgAECgYJBgABLgAFFAMJBwAIAKUVAA==.',
Po='Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8HAAMIAAMJpRVTHgBDAAAPAAIJsB2rXgC+AAAIAAEJkAVTHgBDAAAuAAQKfyEAAw8ACAkoHq4vAHkCAA8ACAkoHq4vAHkCAAgABAlvBxg3AIkAAAAA.Pornelius:BAAALgAECgEJAgABLgAECggJIgAJALQbAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8XAAIfAAgJUB7ZAACgAgAfAAgJUB7ZAACgAgAuAAQKfyYAAx8ACQmoJXcBAMgDAB8ACQmoJXcBAMgDAA4ABwn/I6UUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8eAAIgAAcJAhAEGwBjAQAgAAcJAhAEGwBjAQAAAA==.',
Ra='Raelindra:BAAALgAECggJDwAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgUJCQAAAA==.',
Re='Rebuke:BAAALgAECgcJEwAAAA==.',
Ro='Rookorblood:BAAALgAECgYJDwAAAA==.Rosewalker:BAACLgAFFH8NAAIGAAQJ/SFlBgCTAQAGAAQJ/SFlBgCTAQAuAAQKfyYAAwYACQmcIhECAPoCAAYACQmcIhECAPoCABUABgnqFcIZAFUBAAAA.Rosewall:BAAALgAECgEJAQABLgAFFAQJDQAGAP0hAA==.Rottgut:BAAALgAECgYJCgAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn8mAAQSAAgJmBbWMQDoAQASAAcJsRbWMQDoAQAhAAUJGQccIAD9AAADAAUJ7BDTGwBtAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQJAAgJCRZ3DwCkAQALAAcJiRZMMgDjAQAJAAcJ2xR3DwCkAQAKAAQJMxAfLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Savork:BAAALgAECgcJEwAAAA==.Sayafaed:BAABLgAECn8WAAIfAAgJwQYKTAAUAQAfAAgJwQYKTAAUAQAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn8oAAQRAAgJzhnpCgA4AgARAAgJQhnpCgA4AgAQAAYJ3hF/GQBmAQAgAAIJMwmwTwA5AAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAAALgAECggJEQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Senuna:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAAALgAECgkJDwAAAA==.Shadôwhunt:BAABLgAECn8fAAIPAAgJbhVySQBfAQAPAAgJbhVySQBfAQAAAA==.Shenlon:BAACLgAFFH8VAAMHAAUJbyXkAQB9AQAHAAUJbyXkAQB9AQAUAAIJ/iG4FADNAAAuAAQKfy4ABAcACQm+JJMAAI0DAAcACQmPIZMAAI0DAAwABQlvHRELAJ8BABQABAmKI8glAI8BAAAA.Shilor:BAABLgAECn8bAAIQAAcJiBhtDwDbAQAQAAcJiBhtDwDbAQAAAA==.Shogun:BAAALgAECgYJCwAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgANAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgEJAgAAAA==.Sinistr:BAABLgAECn8WAAMWAAcJChyiJwDyAQAWAAcJChyiJwDyAQAiAAQJIAUgIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBgAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBgANAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgADCgYJCAAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAAALgAECgMJAwAAAA==.Stélle:BAAALgAECggJCgAAAA==.',
Su='Supdude:BAABLgAECn8oAAMEAAkJvB8EAgDnAgAEAAkJvB8EAgDnAgAeAAEJaRzzDQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgUJCAAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgEJAQABLgAECgkJLwAFAIUXAA==.Thorokk:BAAALgAECgEJAQAAAA==.Thynrage:BAAALgAECgUJBQAAAA==.',
Ti='Tigas:BAABLgAECn8iAAILAAcJmCM5CABnAgALAAcJmCM5CABnAgAAAA==.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJDgANAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8gAAMUAAgJSCCtDgCLAgAUAAgJAB6tDgCLAgAHAAgJXhwIBADBAQAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.',
['Tö']='Töby:BAAALgAECgcJCwABLgAECgcJDgANAAAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8WAAIBAAYJ3hkdQACFAQABAAYJ3hkdQACFAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJCAANAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAILAAgJkgypGgCSAQALAAgJkgypGgCSAQABLgAECggJCAANAAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgAECgUJBQAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAABLgAECn8gAAMOAAgJuRU4JgCOAQAOAAYJghg4JgCOAQAfAAgJARGfQQA0AQAAAA==.',
Wa='Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAAALgAECgcJDwAAAA==.',
We='Weenygripper:BAAALgAECgcJEwABLgAFFAQJCQAFAHUbAA==.',
Wo='Wonon:BAAALgAECgEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgADCgIJAgAAAA==.Xaida:BAAALgAFFAIJAgABLgAFFAkJJAAMAPoXAA==.',
Xe='Xecutioner:BAAALgADCgEJAQAAAA==.',
Xi='Xilantaeki:BAAALgADCgIJAgAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEALgAECggJEQAAAA==.Zanmetsu:BAEBLgAECn8ZAAMEAAcJrRyLGABDAgAEAAcJrRyLGABDAgAdAAEJjgzpHgA4AAABLgAECggJEQANAAAAAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn8lAAMWAAkJRhmDKQDpAQAWAAkJRhmDKQDpAQAXAAQJmRp1IwA4AQAAAA==.Zerocool:BAABLgAECn8fAAIjAAkJBRMjQgAGAgAjAAkJBRMjQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgIJAwAAAA==.Zugzug:BAAALgADCgQJBgAAAA==.',
Zy='Zyggy:BAAALgAECggJDQAAAA==.',
['ßa']='ßadfish:BAABLgAECn8eAAIBAAkJOCDoGADUAgABAAkJOCDoGADUAgAAAA==.',
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

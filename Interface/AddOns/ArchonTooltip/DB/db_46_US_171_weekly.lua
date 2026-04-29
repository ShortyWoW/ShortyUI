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

local lookup = {'Hunter-Marksmanship','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Priest-Holy','Priest-Discipline','Druid-Restoration','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Retribution','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Druid-Guardian','Paladin-Holy','Paladin-Protection','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abrams:BAAALgAECgYJDQAAAA==.',
Ad='Addý:BAAALgAECgYJEgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn8VAAIBAAgJMxf6GgBOAgABAAgJMxf6GgBOAgAAAA==.',
Al='Alisonchains:BAAALgAECgYJDgAAAA==.Alkyri:BAAALgADCgUJCgAAAA==.Alternate:BAAALgAECgYJEQAAAA==.',
Am='Amillerbrew:BAABLgAECn8aAAICAAgJTxabJQDXAQACAAgJTxabJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
As='Ashenclaw:BAAALgAECgUJDQAAAA==.',
Au='Auzatryx:BAAALgAECgMJAwAAAA==.',
Ba='Bamboom:BAAALgAECgQJBwAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAAALgAECgYJDwABLgAECggJIQADACQeAA==.Bigrabit:BAAALgADCgIJAgAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Borgon:BAAALgAECgEJAQAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8bAAMEAAgJgRouAgDIAQAEAAgJgRouAgDIAQAFAAEJKwmITQAiAAAAAA==.',
Bu='Bulbasaurus:BAABLgAECn8XAAIGAAgJ8SGCBwAxAwAGAAgJ8SGCBwAxAwAAAA==.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.',
Ca='Cabooze:BAAALgADCgUJCQAAAA==.Cacho:BAAALgAECgQJBwAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8aAAIHAAgJJxccEQAqAgAHAAgJJxccEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgADCgEJAQABLgAFFAcJEwAFAJwXAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAMJAwAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFgAAAA==.',
Da='Daevon:BAAALgAECgQJDgAAAA==.Daron:BAAALgAECgcJDgAAAA==.Darrowreaper:BAAALgAECgYJDQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Denarrage:BAAALgAECggJEwAAAA==.',
Di='Discordia:BAAALgAECggJDQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Dontnerfspls:BAAALgAECgMJBQABLgAECggJIQADACQeAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgADCgcJBwAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgADCgkJDQAAAA==.Ellipsoro:BAABLgAECn8jAAIDAAgJ2SEWAwB4AgADAAgJ2SEWAwB4AgAAAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgcJCgAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8TAAIFAAcJnBdXAADWAQAFAAcJnBdXAADWAQAuAAQKfyEAAgUACQmgILcCADsDAAUACQmgILcCADsDAAAA.',
Fa='Faeris:BAABLgAECn8hAAMIAAkJJiLUAQBZAwAIAAkJJiLUAQBZAwAJAAIJiBd8RQCNAAAAAA==.Faolain:BAABLgAECn8cAAIKAAgJeg9cQwCUAQAKAAgJeg9cQwCUAQAAAA==.Fatalis:BAABLgAECn8hAAMLAAkJ1RG8DACkAQALAAgJLRS8DACkAQABAAgJXAT3UQAFAQAAAA==.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgADCgMJAwAAAA==.Fizaw:BAABLgAECn8VAAIMAAgJnAXiNgAUAQAMAAgJnAXiNgAUAQAAAA==.',
Fl='Floydbussy:BAAALgAECgQJCAAAAA==.',
Fr='Frøzen:BAAALgAECgEJAQAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAINAAgJ6xO2ZgCzAQANAAgJ6xO2ZgCzAQAAAA==.',
Ga='Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBAAAAA==.Gazzcool:BAAALgAECgIJAgAAAA==.',
Ge='Geneviere:BAAALgADCgUJBQAAAA==.',
Gh='Ghostzen:BAACLgAFFH8FAAIOAAMJiBZVAwD9AAAOAAMJiBZVAwD9AAAuAAQKfxsAAg4ACQkKJQoBALsDAA4ACQkKJQoBALsDAAAA.',
Gi='Gislain:BAABLgAECn8bAAMPAAcJohLOOgCWAQAPAAcJohLOOgCWAQAQAAYJ0gzIDwANAQAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gothmogsbane:BAABLgAECn8UAAMKAAYJvBGMEABSAQAKAAYJvBGMEABSAQARAAYJBwW0UgDcAAAAAA==.',
Gr='Greyspirit:BAABLgAECn8VAAISAAgJVhwzBQCNAgASAAgJVhwzBQCNAgAAAA==.Grez:BAAALgAECgQJBQAAAA==.',
Gu='Gumpy:BAAALgAECgMJBQAAAA==.',
Ha='Harkiel:BAAALgAECgUJBwAAAA==.',
He='Heyz:BAABLgAECn8bAAMJAAgJIxpMAgBCAgAJAAgJIxpMAgBCAgAIAAEJkwCTigAhAAAAAA==.',
Hi='Himbo:BAAALgAECgIJAgAAAA==.Hipocrit:BAAALgAECgUJBQAAAA==.',
Ho='Holypoopp:BAABLgAECn8ZAAMNAAgJwRtfRwANAgANAAYJLB5fRwANAgATAAUJJBZ1SgBOAQAAAA==.Hondalorian:BAABLgAECn8cAAILAAgJIxNsDACoAQALAAgJIxNsDACoAQAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgADCgYJBgAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Im='Imran:BAABLgAECn8WAAMUAAcJTg/iFwBYAQAUAAYJoRHiFwBYAQANAAYJ0ASezwDqAAAAAA==.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAAALgAECgUJCQAAAA==.',
Je='Jether:BAAALgAECgUJCAAAAA==.',
Jk='Jkingoreborn:BAAALgAECgYJCgAAAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECgYJBwAVAAAAAA==.Jojobaggins:BAAALgAECgcJEgAAAA==.Jopine:BAAALgADCgEJAgABLgAECgYJBwAVAAAAAA==.',
Ka='Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJCgAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAAALgAFFAIJBAABLgAFFAcJEwAFAJwXAA==.Keyohs:BAAALgAECgIJAgABLgAFFAcJEwAFAJwXAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECgcJFAAPAKgZAA==.',
Kk='Kkoda:BAAALgADCgIJAgAAAA==.',
Ko='Koal:BAAALgAECggJEQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAgJFwABAKsgAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAAALgAECgcJDAABLgAECgcJFQAPAOYPAA==.',
Ku='Kushage:BAAALgADCgcJEQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8aAAMLAAgJzAl1EQByAQALAAgJkwd1EQByAQABAAYJ/grySgAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lettussy:BAAALgAECggJCAABLgAFFAQJBgAWAB4RAA==.',
Li='Lix:BAAALgAECgQJCwAAAA==.',
Lo='Loliruri:BAAALgAECgYJBwAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgADCgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgEJAQAAAA==.Lumpia:BAABLgAECn8WAAIGAAcJqCKPBQDUAQAGAAcJqCKPBQDUAQAAAA==.',
['Lú']='Lúthien:BAABLgAECn8hAAIMAAgJpCC1AQCJAgAMAAgJpCC1AQCJAgAAAA==.',
Ma='Madoka:BAAALgAECgYJCwAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn8fAAMDAAgJeR2dJwCcAgADAAgJeR2dJwCcAgAXAAYJPQ8QJAAgAQAAAA==.',
Me='Meloo:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mikehawncho:BAAALgADCgIJAgABLgAECgcJGwADAGMZAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAAALgAECgYJDgAAAA==.Morthrisia:BAAALgADCgUJBQAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAAALgAECgYJCQAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
Na='Naerys:BAAALgAECgYJCQAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgADCgQJBQAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8cAAMYAAgJ9xatDACuAQAYAAgJ9xatDACuAQAZAAEJiRUPcAA1AAAAAA==.',
Ni='Nitesrider:BAAALgADCggJDwAAAA==.',
No='Nora:BAACLgAFFH8NAAINAAYJ2B4wAAABAgANAAYJ2B4wAAABAgAuAAQKfyYAAg0ACQk0JskEAH8DAA0ACQk0JskEAH8DAAAA.Nori:BAAALgADCgkJDgABLgAFFAYJFAAWAK0mAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.',
Nu='Nubbs:BAAALgAECgYJDgAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAMJBQACALoJAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='Onlyinusa:BAAALgAECgQJBAAAAA==.Onyxnate:BAAALgADCgkJHwAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAVAAAAAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgYJDAABLgAECgcJBwAVAAAAAA==.',
Pi='Pinkdefender:BAAALgAECgYJBgABLgAECggJIQADACQeAA==.',
Po='Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAABLgAECn8hAAMDAAgJJB62LwB5AgADAAgJJB62LwB5AgAXAAQJbwcYNwCJAAAAAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8XAAIYAAgJ/RzXAACgAgAYAAgJ/RzXAACgAgAuAAQKfyYAAxgACQnLJXYBAMgDABgACQnLJXYBAMgDABkABwn/I6QUACsCAAAA.',
Pu='Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAAALgAECgYJEQAAAA==.',
Ra='Raelindra:BAAALgAECgYJBwAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgQJBgAAAA==.',
Re='Rebuke:BAAALgAECgYJDAAAAA==.',
Ro='Rookorblood:BAAALgAECgYJCQAAAA==.Rosewalker:BAACLgAFFH8FAAICAAQJThd1CQA/AQACAAQJThd1CQA/AQAuAAQKfxYAAgIACAkCI6oMAMUCAAIACAkCI6oMAMUCAAAA.Rosewall:BAAALgADCgQJBAABLgAFFAQJBQACAE4XAA==.Rottgut:BAAALgAECgMJAwAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn8XAAMLAAgJFhbaMQDoAQALAAcJrRbaMQDoAQABAAQJNA8jXgDIAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQEAAgJ/BV2DwCkAQAGAAcJiRZOMgDiAQAEAAcJzBR2DwCkAQAFAAQJMxAdLgDRAAAAAA==.Savork:BAAALgAECgYJDwAAAA==.Sayafaed:BAAALgAECgYJBgAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn8fAAMIAAcJmxlcAwAdAgAIAAcJmxlcAwAdAgAaAAEJfwMnZQAuAAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAAALgAECgcJCwAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAAALgAECgcJBwAAAA==.Shadôwhunt:BAABLgAECn8fAAIDAAgJYxXJDwCZAQADAAgJYxXJDwCZAQAAAA==.Shenlon:BAACLgAFFH8NAAMbAAQJahziAQB9AQAbAAQJOxziAQB9AQAcAAIJ/iGsFADNAAAuAAQKfy0ABBsACQn0I5MAAI0DABsACQmOIZMAAI0DAAcABQlhHXADALIBABwABAn3IcglAI8BAAAA.Shilor:BAAALgAECgYJEAAAAA==.Shogun:BAAALgAECgMJBQAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgAVAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinistr:BAABLgAECn8WAAMPAAcJChymJwDyAQAPAAcJChymJwDyAQAdAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgEJAQABLgAECgIJAQAVAAAAAA==.Skyrun:BAAALgAECgIJAQAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
Su='Supdude:BAABLgAECn8bAAMeAAgJTRtPAgAYAgAeAAgJRRtPAgAYAgAfAAEJaRz1DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thorokk:BAAALgADCgYJCAAAAA==.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJDgAVAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8fAAMcAAgJ2B+uDgCLAgAcAAgJ6R2uDgCLAgAbAAcJahtaAgBvAQAAAA==.Trauma:BAAALgADCgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.',
['Tö']='Töby:BAAALgAECgYJCgAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAAALgAECgUJCgAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECgYJDAAVAAAAAA==.',
Va='Vannacutt:BAAALgAECgYJDAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgADCgUJBQAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAABLgAECn8YAAMZAAgJwhI0JgCOAQAYAAgJJQxmWACYAQAZAAYJghg0JgCOAQAAAA==.',
Wa='Wasabi:BAAALgAECgYJCAAAAA==.',
We='Weenygripper:BAAALgAECgEJAQAAAA==.',
Wo='Wonon:BAAALgADCgcJCQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xi='Xilantaeki:BAAALgADCgIJAgAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEALgAECgcJCAABLgAECgcJGQAeAK0cAA==.Zanmetsu:BAEBLgAECn8ZAAMeAAcJrRyRGABDAgAeAAcJrRyRGABDAgAgAAEJjgzmHgA4AAAAAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn8UAAMPAAcJqBmEKQDpAQAPAAcJqBmEKQDpAQAQAAQJjQ0gFADaAAAAAA==.Zerocool:BAABLgAECn8bAAIhAAgJwBQvQgAGAgAhAAgJwBQvQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugzug:BAAALgADCgIJAgAAAA==.',
Zy='Zyggy:BAAALgAECgQJBQAAAA==.',
['ßa']='ßadfish:BAABLgAECn8XAAINAAgJTSDmGADUAgANAAgJTSDmGADUAgAAAA==.',
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

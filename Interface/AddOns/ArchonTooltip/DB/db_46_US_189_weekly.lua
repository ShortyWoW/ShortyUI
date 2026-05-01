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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Paladin-Retribution','Priest-Shadow','Mage-Frost','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Druid-Restoration','Warrior-Fury','Warrior-Arms','Priest-Discipline','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Paladin-Protection','Warrior-Protection','Mage-Fire','Druid-Balance','Paladin-Holy','Shaman-Elemental','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECgQJBQAAAA==.',
Ad='Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJBQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgYJBgAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.',
Am='Amarokk:BAAALgAECgUJCwAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAAALgAECgQJCgAAAA==.Anish:BAAALgAECgEJAQAAAA==.Anzalone:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
As='Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAAALgAECgEJAQAAAA==.',
Au='Auv:BAACLgAFFH8QAAMCAAQJEiZ+BwCtAQACAAQJEiZ+BwCtAQADAAEJlQBXGwA6AAAuAAQKfxQAAwMABwmJJkETALEBAAIABQkZJltMAOMBAAMABAkgJkETALEBAAAA.',
Ax='Axël:BAAALgAFFAEJAQAAAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAABLgAECn8gAAIEAAgJ0B3gCwC3AgAEAAgJ0B3gCwC3AgAAAA==.Azmora:BAAALgAECgIJAgAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAIJBQAFANIlAA==.Batreaux:BAAALgAECgUJBwAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgIJAgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Bepallylol:BAABLgAECn8YAAIFAAgJYh2xLQBsAgAFAAgJYh2xLQBsAgAAAA==.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQABAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgIJAwAAAA==.',
Br='Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJBwAAAA==.Bubby:BAAALgAECgcJEgAAAA==.Burbuja:BAAALgAECgUJCgAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAQAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgADCgcJBwAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cetraa:BAAALgAECgYJBgAAAA==.',
Ch='Chocobro:BAAALgAECgEJAgAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgADCgkJCAAAAA==.',
Co='Colhap:BAABLgAECn8YAAIGAAcJJxwuFwBFAQAGAAcJJxwuFwBFAQAAAA==.Conjure:BAABLgAECn8bAAMCAAYJlRKjhwBKAQACAAYJfBCjhwBKAQADAAMJkxNjQgCrAAAAAA==.Corbina:BAABLgAECn8YAAIHAAcJ1yJ0NQCeAgAHAAcJ1yJ0NQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAABLgAECn8zAAIHAAgJpxb5IADoAQAHAAgJpxb5IADoAQAAAA==.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cygwin:BAABLgAECn8YAAIIAAYJQhstEwDUAQAIAAYJQhstEwDUAQAAAA==.',
Da='Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJKwAJANMZAA==.Darklon:BAAALgAECgcJCwAAAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Datmage:BAABLgAECn8ZAAIHAAcJdR9xXgAfAgAHAAcJdR9xXgAfAgAAAA==.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8cAAIFAAgJ2xI2UADxAQAFAAgJ2xI2UADxAQAAAA==.Derpatron:BAAALgAECgcJDwAAAA==.Destruction:BAAALgAECgcJEAAAAA==.Devo:BAEALgADCgIJAgABLgAECggJJQAEAHAZAA==.',
Di='Disgusti:BAAALgAECgYJDAAAAA==.Divinespark:BAABLgAECn8dAAIKAAcJwhWAFQBjAQAKAAcJwhWAFQBjAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Doinkbigs:BAABLgAECn8cAAICAAgJnAz4JgCTAQACAAgJnAz4JgCTAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAABAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgAAAA==.',
Dr='Dredd:BAAALgAECgQJBwAAAA==.Drewsilla:BAAALgAECgIJAgAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8ZAAILAAcJhhx9DgAmAgALAAcJhhx9DgAmAgAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAAALgADCgEJAQAAAA==.',
Ea='Eap:BAAALgAECgUJCAAAAA==.Eazye:BAACLgAFFH8FAAIGAAIJGArGEgCeAAAGAAIJGArGEgCeAAAuAAQKfyoAAgYACAkWGTQIAAQCAAYACAkWGTQIAAQCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8YAAMMAAcJ9Qf4IAAuAQAMAAcJWgb4IAAuAQANAAUJZQj4JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAABAAAAAA==.',
El='Elentiya:BAABLgAECn8gAAMKAAkJ5RqaDgB1AgAKAAkJ5RqaDgB1AgAOAAEJegd1WgAtAAAAAA==.Elphzz:BAAALgAECggJEwAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgQJCQAAAA==.',
Ez='Ez:BAACLgAFFH8QAAMPAAUJCBKyCwC0AAAPAAQJqxKyCwC0AAAQAAEJIBCUIwBZAAAuAAQKfykAAw8ACAneH3kFAKQBAA8ACAneH3kFAKQBABAAAgmSDS6DAEwAAAAA.Ezarath:BAAALgAECgYJEwAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIJAAYJywwhSgDHAAAJAAYJywwhSgDHAAAAAA==.',
Fe='Felenn:BAEALgADCgYJCQABLgAECgYJEAABAAAAAA==.Felorc:BAAALgAECgYJCwAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIMAAgJ/Rn+GQB8AgAMAAgJ/Rn+GQB8AgAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJGAARAMQXAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJCgAAAA==.Gelektrael:BAABLgAECn8dAAMCAAcJuQrnPAA8AQACAAcJ2wnnPAA8AQADAAEJXAzydQAvAAAAAA==.',
Gh='Ghostwarrior:BAAALgADCgMJAwABLgAECggJOgAFAJkfAA==.Ghostzz:BAABLgAECn86AAMFAAgJmR/WCQCCAgAFAAgJOx/WCQCCAgASAAMJAR/qDgASAQAAAA==.',
Gl='Glzygldiator:BAACLgAFFH8HAAIRAAMJfhRHLgDhAAARAAMJfhRHLgDhAAAuAAQKfyEAAhEABwlQHWAmAKUBABEABwlQHWAmAKUBAAAA.',
Gn='Gnomelock:BAAALgAECgYJCQABLgAECgYJCQABAAAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Govegan:BAAALgADCgQJBQAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAIJAgABAAAAAA==.Greyhairs:BAAALgAECgQJDAAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAABLgAECn8lAAIJAAgJfx1MIgCEAgAJAAgJfx1MIgCEAgAAAA==.Gromit:BAACLgAFFH8OAAIKAAUJ3RS/AgCRAQAKAAUJ3RS/AgCRAQAuAAQKfyMAAwoACQlMIZQDACEDAAoACQlMIZQDACEDAA4AAgmnEUZKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAAALgAECggJDgAAAA==.',
Ha='Haldire:BAAALgAECgIJBQAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8gAAMNAAgJdhbJBADqAQANAAgJTxbJBADqAQATAAMJ9Q6KOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCAAAAA==.',
Ho='Hofarmer:BAAALgAECggJEwAAAA==.Hollywoóodxx:BAAALgAECgcJDwAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgQJBAAAAA==.',
Hy='Hycisan:BAAALgAECgYJEQAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.Icon:BAAALgADCgEJAgAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgMJAwAAAA==.',
Jb='Jbirdlol:BAAALgADCgQJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAECgcJCgABAAAAAA==.Jetmage:BAABLgAECn8aAAIUAAgJ7CLpAADgAgAUAAgJ7CLpAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAAALgAECgYJDQAAAA==.',
Ju='Jurassthicc:BAAALgADCgEJAQAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8WAAIJAAgJrhtjDQANAgAJAAgJrhtjDQANAgABLgAECggJIAAEANAdAA==.Karraa:BAAALgAECgUJEQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8WAAIUAAYJuwnEAwAKAQAUAAYJuwnEAwAKAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQABAAAAAA==.Kerze:BAAALgAECgQJCQAAAA==.Kesatrix:BAAALgAECgYJEgAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJCQABLgAECggJFQACAOwWAA==.Khaztharion:BAAALgADCggJCAABLgAECggJFQACAOwWAA==.Khendrick:BAAALgAECgYJEAAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAQAAAA==.Kittykatt:BAABLgAECn8iAAIVAAgJUBuuBgAxAgAVAAgJUBuuBgAxAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgEJAQAAAA==.',
Kr='Kraggo:BAAALgAECgMJBgAAAA==.Krimzin:BAACLgAFFH8IAAIFAAMJ4BtaFwAeAQAFAAMJ4BtaFwAeAQAuAAQKfxYAAwUACAkKIc4XANoCAAUACAkKIc4XANoCABYAAQkdIZ2JAFYAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8dAAIHAAcJ5CFPEgBJAgAHAAcJ5CFPEgBJAgAAAA==.Larsen:BAABLgAECn8dAAIXAAcJ4h3dDQDBAQAXAAcJ4h3dDQDBAQAAAA==.',
Le='Leap:BAAALgAECgYJDAAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgADCgcJCAAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn8aAAIGAAgJcQ+aEACHAQAGAAgJcQ+aEACHAQAAAA==.',
Ll='Llarker:BAEALgAECgYJEAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIQAAcJLyEVHwBLAgAQAAcJLyEVHwBLAgAAAA==.',
Lu='Luminia:BAAALgADCgcJDwAAAA==.',
Ly='Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgADCgYJBgABLgAECggJJAAHAM4VAA==.Magisterium:BAAALgAECgYJEwAAAA==.Malady:BAABLgAECn8bAAIGAAcJnyBJDQCvAQAGAAcJnyBJDQCvAQAAAA==.Malt:BAABLgAECn8VAAIJAAcJlSFyFgC0AQAJAAcJlSFyFgC0AQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAECgYJCQAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgIJAgAAAA==.',
Md='Mdeag:BAAALgAECgMJBQAAAA==.',
Me='Mefistofeles:BAABLgAECn8YAAIYAAgJaxbbBgAHAgAYAAgJaxbbBgAHAgAAAA==.Meingaree:BAAALgAECgEJAQAAAA==.Merlinus:BAABLgAECn8gAAIFAAcJ+Qm1lABTAQAFAAcJ+Qm1lABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn8iAAITAAgJPA0cEAAeAQATAAgJPA0cEAAeAQAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moomkin:BAABLgAECn8cAAIVAAgJhgtzOQBRAQAVAAgJhgtzOQBRAQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Narpul:BAAALgAECggJEQAAAA==.Natë:BAACLgAFFH8IAAITAAMJMxhBCQDtAAATAAMJMxhBCQDtAAAuAAQKfywAAhMACQktIWEDACMDABMACQktIWEDACMDAAAA.Nazend:BAAALgADCgQJBAAAAA==.',
Ne='Necrotalon:BAAALgAECgQJCQAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8DAAIJAAIJ8CJdJQDLAAAJAAIJ8CJdJQDLAAAuAAQKfyYAAgkACAkAJBQNABcDAAkACAkAJBQNABcDAAAA.Nerzhùl:BAAALgAECggJEQAAAA==.',
Nh='Nharuna:BAABLgAECn8bAAIQAAgJBg3VHwCiAQAQAAgJBg3VHwCiAQAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn8ZAAMWAAgJABO3EgDEAQAWAAgJABO3EgDEAQAFAAYJ+QTb0ADoAAAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8XAAQZAAYJcSTLAgCoAQAYAAYJAyOjHAAaAgAaAAYJzh5mBgARAgAZAAQJ9yPLAgCoAQAAAA==.',
No='Noboundss:BAAALgAECgcJBwAAAA==.Nobóunds:BAAALgAECggJCQAAAA==.Nomnoms:BAAALgAECgYJCgAAAA==.Nomoreheals:BAAALgADCgIJAgAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAABLgAFFH8HAAMbAAMJLx1ZCAAUAQAbAAMJnBhZCAAUAQAQAAEJvyDQHgBkAAAAAA==.Noztra:BAABLgAECn8eAAIHAAcJ/g1OawADAQAHAAcJ/g1OawADAQAAAA==.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ob='Obsideon:BAAALgAECgcJEAAAAA==.',
Oh='Ohgr:BAAALgADCgUJDQAAAA==.Ohshifty:BAABLgAECn8kAAIVAAkJQQ8uDgCsAQAVAAkJQQ8uDgCsAQAAAA==.',
Ol='Olie:BAABLgAECn8XAAIQAAgJZAeUKQBvAQAQAAgJZAeUKQBvAQAAAA==.',
Or='Orbsicles:BAAALgAECggJDgAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAAALgAECgcJEQAAAA==.Passtheflask:BAAALgAECgQJEQAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8GAAIRAAMJXQ/vRwCUAAARAAMJXQ/vRwCUAAAuAAQKfzMAAxEACQnVIckFAMQCABEACQnVIckFAMQCABwAAQnEEYtHACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8VAAIIAAgJABAHPwCEAQAIAAgJABAHPwCEAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgADCgcJBwABAAAAAA==.Powpow:BAAALgAECgYJDgAAAA==.',
Pr='Prejudice:BAABLgAECn8WAAIWAAcJtBNrEgDHAQAWAAcJtBNrEgDHAQAAAA==.Prowlcow:BAABLgAECn8cAAILAAcJehaFFgDPAQALAAcJehaFFgDPAQAAAA==.',
Ps='Psychosis:BAABLgAECn8fAAIRAAgJ5xoELgCAAgARAAgJ5xoELgCAAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIHAAMJ+A9aLAAFAQAHAAMJ+A9aLAAFAQAuAAQKfyUAAgcACAkdHI8/AHoCAAcACAkdHI8/AHoCAAAA.Rainhoof:BAABLgAECn8dAAMdAAcJmhdABQDHAQAdAAcJmhdABQDHAQALAAUJYAh9hwDHAAAAAA==.Ralneth:BAACLgAFFH8IAAMeAAQJIBfkAwAOAQAeAAMJABnkAwAOAQAEAAEJYROPJwBdAAAuAAQKfyQAAx4ACAmrIE4DAOsCAB4ACAmfH04DAOsCAAQABgnYG0EYABACAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAAALgAECgYJEwAAAA==.Rapalaa:BAAALgADCgEJAQABLgAECgYJEwABAAAAAA==.Raspútin:BAABLgAECn8hAAMfAAgJPRTECwDMAQAfAAgJPRTECwDMAQAgAAQJ8AfNVQC5AAAAAA==.Rawkfice:BAAALgADCggJDQAAAA==.',
Re='Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgEJAgAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAECggJDQAAAA==.',
Rj='Rjolz:BAABLgAECn8mAAIRAAgJwyUkAwAEAwARAAgJwyUkAwAEAwAAAA==.',
Ro='Rootzi:BAAALgAECgIJAwABLgAECgkJGAARAMQXAA==.Rootzidk:BAABLgAECn8YAAIRAAgJxBdgXADdAQARAAgJxBdgXADdAQAAAA==.',
Ru='Rucks:BAABLgAECn8cAAMgAAcJBhqDEwBUAQAgAAcJEQ2DEwBUAQAfAAYJzRrmFQBSAQAAAA==.',
Sa='Saelem:BAAALgADCgcJBQAAAA==.Sandalfon:BAAALgAECgYJCwAAAA==.Sanleron:BAAALgADCgcJBwAAAA==.Sarith:BAAALgAECgEJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQABAAAAAA==.',
Sc='Scargon:BAAALgAECgQJBwAAAA==.',
Se='Selidori:BAAALgADCgUJBQAAAA==.Seralicht:BAABLgAFFH8LAAIKAAUJGgsoBABnAQAKAAUJGgsoBABnAQAAAA==.',
Sh='Shaliri:BAAALgADCgEJBAAAAA==.Sharayse:BAABLgAECn8VAAIHAAgJSgq0sgB5AQAHAAgJSgq0sgB5AQAAAA==.Sharmee:BAAALgAECgEJAgAAAA==.Shockohôlic:BAABLgAECn8WAAMIAAYJTxChSwBUAQAIAAYJTxChSwBUAQAhAAEJnApbKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8dAAIRAAgJlRUjHgDTAQARAAgJlRUjHgDTAQAAAA==.',
Sl='Slingablade:BAABLgAECn8QAAIJAAgJERH7HQB/AQAJAAgJERH7HQB/AQAAAA==.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8FAAIFAAIJ0iWLJADfAAAFAAIJ0iWLJADfAAAuAAQKfygAAwUACAlHJQUKAEEDAAUACAlHJQUKAEEDABYAAQnCHm5DAFsAAAAA.',
So='Solvi:BAABLgAECn8fAAILAAcJ6ReXKABEAQALAAcJ6ReXKABEAQAAAA==.Sonira:BAAALgADCgMJAwAAAA==.Soulbrand:BAABLgAECn8dAAIGAAcJAQn4FwA+AQAGAAcJAQn4FwA+AQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAhAPAfAA==.',
Sp='Spellz:BAAALgAECgYJEAAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8VAAIiAAcJsAufCQAJAQAiAAcJsAufCQAJAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.',
Su='Sufiya:BAABLgAECn8cAAIQAAgJLA+xHwCiAQAQAAgJLA+xHwCiAQAAAA==.Suhwoo:BAAALgAECgYJDgAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sy='Sylvershadow:BAAALgAECgUJDgAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgIJAgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Tandarilada:BAAALgAFFAEJAQAAAA==.Tanknspankn:BAAALgAECgUJBwAAAA==.Tankurface:BAAALgAECgEJAQAAAA==.',
Th='Thalvint:BAABLgAECn8jAAMNAAgJ4h/OAQCFAgANAAgJ4h/OAQCFAgAMAAYJ1RIcWwBCAQAAAA==.Theblackhand:BAABLgAECn8aAAMXAAYJ1RXKSgAcAQAXAAUJaxPKSgAcAQAIAAYJqA/dLQAMAQAAAA==.Thickdk:BAABLgAECn8VAAIRAAcJTBhNbgCtAQARAAcJTBhNbgCtAQAAAA==.Thoriel:BAAALgADCgMJAwAAAA==.',
Ti='Timefall:BAAALgAECgcJBQAAAA==.Titanic:BAAALgAECgUJCQAAAA==.',
To='Tomcruise:BAAALgAECgYJBgAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAAALgAFFAEJAQAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJDQAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8qAAIMAAgJ2BPJKAAZAgAMAAgJ2BPJKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Va='Vanarn:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Vanlin:BAABLgAECn8dAAILAAcJDR5JDQA2AgALAAcJDR5JDQA2AgAAAA==.',
Ve='Vexxdr:BAABLgAECn8aAAILAAgJihHVOQC+AQALAAgJihHVOQC+AQAAAA==.Vexxs:BAAALgAECgUJCgABLgAECggJGgALAIoRAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBgAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECggJGwASAMUQAA==.',
Vu='Vulperas:BAABLgAECn8cAAIXAAgJJQ+xGwA3AQAXAAgJJQ+xGwA3AQAAAA==.',
Vy='Vynastallan:BAABLgAECn8UAAMQAAcJTiKqCwBGAgAQAAcJTiKqCwBGAgAPAAEJehdthgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIEAAgJcBm2BwAXAgAEAAgJcBm2BwAXAgAAAA==.',
Wa='Waroo:BAABLgAECn8YAAIVAAgJkgoxFABiAQAVAAgJkgoxFABiAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAECgIJAgAAAA==.',
Wi='Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgIJAgAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAAALgAECgYJCwAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn8bAAISAAgJxRB0CQBzAQASAAgJxRB0CQBzAQAAAA==.',
Yi='Yiang:BAABLgAECn8bAAIgAAgJdxdiIgDDAQAgAAgJdxdiIgDDAQAAAA==.',
Yl='Ylndrysa:BAABLgAECn8pAAILAAgJNBaxLAD8AQALAAgJNBaxLAD8AQAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAAALgAECgkJBQAAAA==.',
Ze='Zedrock:BAABLgAECn8kAAIHAAgJzhWYWQAsAgAHAAgJzhWYWQAsAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8ZAAMVAAcJshm6DQCzAQAVAAcJaRi6DQCzAQAjAAQJPAofJAB8AAAAAA==.Zeropistol:BAAALgAECgYJDAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgQJDAAAAA==.',
Zu='Zuro:BAABLgAECn8UAAMQAAcJxwsVMABQAQAQAAcJxwsVMABQAQAPAAEJCgG+mQAaAAAAAA==.',
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

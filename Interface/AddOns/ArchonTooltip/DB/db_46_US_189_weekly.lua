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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Paladin-Retribution','Unknown-Unknown','Mage-Frost','Priest-Holy','Priest-Shadow','Priest-Discipline','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Fury','DeathKnight-Unholy','Paladin-Protection','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Paladin-Holy','Mage-Fire','Druid-Balance','Shaman-Elemental','Hunter-Survival','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Druid-Restoration','Evoker-Devastation','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Vengeance','Shaman-Restoration','Druid-Guardian',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECgQJBQAAAA==.',
Ad='Adreane:BAAALgAECgMJBAAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgADCgEJAQAAAA==.',
Al='Alispere:BAAALgADCgUJBQAAAA==.',
Am='Amarokk:BAAALgAECgUJBwAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAAALgAECgQJCgAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
As='Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAAALgADCgYJCAAAAA==.',
Au='Auv:BAACLgAFFH8MAAMBAAQJ3CX2AADFAQABAAQJ3CX2AADFAQACAAEJlQBXGwA6AAAuAAQKfxQAAwIABwmJJkQTALEBAAEABQkZJltMAOQBAAIABAkgJkQTALEBAAAA.',
Ax='Axël:BAAALgAECggJEwAAAA==.',
Az='Azimondius:BAABLgAECn8cAAIDAAgJYxzcCwC3AgADAAgJYxzcCwC3AgAAAA==.Azmora:BAAALgAECgIJAgAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJAwABLgAECggJIQAEAOskAA==.Batreaux:BAAALgAECgUJBwAAAA==.',
Be='Bearkake:BAAALgAECgEJAQAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Bepallylol:BAABLgAECn8YAAIEAAgJYh24LQBsAgAEAAgJYh24LQBsAgAAAA==.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQAFAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgEJAQAAAA==.',
Br='Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJBgAAAA==.Bubby:BAAALgAECgcJEQAAAA==.Burbuja:BAAALgAECgUJBgAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAQAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgADCgYJBgAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cetraa:BAAALgADCgkJHgAAAA==.',
Ch='Chewÿ:BAAALgADCgYJBgAAAA==.Chocobro:BAAALgAECgEJAgAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgADCgcJBwAAAA==.',
Co='Colhap:BAAALgAECgYJDgAAAA==.Conjure:BAAALgAECgYJEwAAAA==.Corbina:BAAALgAFFAEJAQAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQAFAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECggJDQAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAABLgAECn8lAAIGAAgJGxXnDwDEAQAGAAgJGxXnDwDEAQAAAA==.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cygwin:BAAALgAECgYJEgAAAA==.',
Da='Darcyonys:BAAALgAECgIJBQAAAA==.Darklon:BAAALgAECgcJCwAAAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Datmage:BAABLgAECn8XAAIGAAYJNCF4XgAfAgAGAAYJNCF4XgAfAgAAAA==.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQAFAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8cAAIEAAgJ2xIcFgBwAQAEAAgJ2xIcFgBwAQAAAA==.Derpatron:BAAALgAECgYJCAAAAA==.Destruction:BAAALgAECgcJCQAAAA==.Devo:BAEALgADCgIJAgABLgAECggJHQADAPQUAA==.',
Di='Disgusti:BAAALgAECgQJBgAAAA==.Divinespark:BAABLgAECn8WAAIHAAcJwhUpCQBsAQAHAAcJwhUpCQBsAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Doinkbigs:BAABLgAECn8UAAIBAAYJGAynHAA0AQABAAYJGAynHAA0AQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAAFAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAECgcJCwABLgAFFAIJBAAFAAAAAA==.',
Dr='Dredd:BAAALgAECgQJBwAAAA==.Drewsilla:BAAALgAECgEJAQAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAAALgAECgYJEgAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAAALgADCgEJAQAAAA==.',
Ea='Eap:BAAALgAECgUJBgAAAA==.Eazye:BAABLgAECn8jAAIIAAgJoRZnGQAWAgAIAAgJoRZnGQAWAgAAAA==.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAAALgAECgcJEQAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAAFAAAAAA==.',
El='Elentiya:BAABLgAECn8aAAMHAAgJXxmXDgB1AgAHAAgJXxmXDgB1AgAJAAEJegdzWgAtAAAAAA==.Elphzz:BAAALgAECggJEgAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgQJCQAAAA==.',
Ez='Ez:BAACLgAFFH8MAAMKAAUJCBKMFwDaAAAKAAQJqxKMFwDaAAALAAEJIBCQIwBZAAAuAAQKfycAAwoACAneH28CAK4BAAoACAneH28CAK4BAAsAAgmSDV88AE4AAAAA.Ezarath:BAAALgAECgYJDQAAAA==.',
Fa='Fadedaf:BAAALgAECgcJEAAAAA==.',
Fe='Felorc:BAAALgAECgYJCwAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIMAAgJ/RkCGgB8AgAMAAgJ/RkCGgB8AgAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJFwANAN0WAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgUJBQAAAA==.Gelektrael:BAABLgAECn8WAAMBAAcJ2wlAGgBDAQABAAcJ+ghAGgBDAQACAAEJXAzsdQAvAAAAAA==.',
Gh='Ghostwarrior:BAAALgADCgMJAwABLgAECggJMQAEACgfAA==.Ghostzz:BAABLgAECn8xAAMEAAgJKB9jJQCRAgAEAAgJcB5jJQCRAgAOAAMJAR88BwAUAQAAAA==.',
Gl='Glzygldiator:BAABLgAECn8bAAINAAYJfR3NVQDwAQANAAYJfR3NVQDwAQAAAA==.',
Gn='Gnomelock:BAAALgAECgYJCQABLgAECgYJCQAFAAAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Govegan:BAAALgADCgQJBQAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAIJBAAFAAAAAA==.Greyhairs:BAAALgAECgQJCAAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAABLgAECn8kAAIPAAgJfx1GIgCEAgAPAAgJfx1GIgCEAgAAAA==.Gromit:BAACLgAFFH8MAAIHAAQJphfeAQBFAQAHAAQJphfeAQBFAQAuAAQKfyEAAwcACAn6JJMDACEDAAcACAn6JJMDACEDAAkAAgmnEUhKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAAALgAECggJDgAAAA==.',
Ha='Haldire:BAAALgAECgIJBAAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8eAAMQAAgJrBW4AQDqAQAQAAgJhRW4AQDqAQARAAMJ9Q6FOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCAAAAA==.',
Ho='Hofarmer:BAAALgAECggJEwAAAA==.Hollywoóodxx:BAAALgAECgcJDwAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgEJAQAAAA==.',
Hu='Hurtak:BAAALgADCggJCAAAAA==.',
Hy='Hycisan:BAAALgAECgYJCwAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAQABLgADCgQJBQAFAAAAAA==.Icon:BAAALgADCgEJAQAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQAFAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgMJAwAAAA==.',
Jb='Jbirdlol:BAAALgADCgQJBAAAAA==.',
Je='Jesse:BAAALgAECgUJCgABLgAFFAIJBQASAIoSAA==.Jetmage:BAABLgAECn8XAAITAAgJhCLqAADgAgATAAgJhCLqAADgAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAAALgAECgUJCQAAAA==.',
Ju='Jurassthicc:BAAALgADCgEJAQAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQAFAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8VAAIPAAgJlRVbDwCNAQAPAAgJlRVbDwCNAQABLgAECggJHAADAGMcAA==.Karraa:BAAALgAECgQJCAAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAAALgAECgYJEAAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQAFAAAAAA==.Kerze:BAAALgAECgQJBQAAAA==.Kesatrix:BAAALgAECgYJDAAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khaztharion:BAAALgADCggJCAABLgAECgcJEAAFAAAAAA==.Khendrick:BAAALgAECgYJDgAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAQAAAA==.Kittykatt:BAABLgAECn8aAAIUAAgJUhkWAwAKAgAUAAgJUhkWAwAKAgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgADCgIJAgAAAA==.',
Kr='Kraggo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8FAAIEAAIJUBYoDgCxAAAEAAIJUBYoDgCxAAAuAAQKfxYAAwQACAkKIcsXANoCAAQACAkKIcsXANoCABIAAQkdIZqJAFYAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8WAAIGAAcJtSB0CgAEAgAGAAcJtSB0CgAEAgAAAA==.Larsen:BAABLgAECn8WAAIVAAcJnRvIBwCGAQAVAAcJnRvIBwCGAQAAAA==.',
Le='Leap:BAAALgAECgQJBgAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgADCgcJBwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAAALgAECggJEgAAAA==.',
Ll='Llarker:BAEALgAECgUJCgAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAILAAcJLyEXHwBLAgALAAcJLyEXHwBLAgAAAA==.',
Lu='Luminia:BAAALgADCgcJDwAAAA==.',
Ly='Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgADCgYJBgABLgAECggJHAAGAMgVAA==.Magisterium:BAAALgAECgYJDwAAAA==.Malady:BAABLgAECn8VAAIIAAYJtiCUFgAzAgAIAAYJtiCUFgAzAgAAAA==.Malt:BAABLgAECn8VAAIPAAcJHCH1BgAGAgAPAAcJHCH1BgAGAgAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAECgYJCQAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgIJAgAAAA==.',
Md='Mdeag:BAAALgADCgMJAwAAAA==.',
Me='Mefistofeles:BAAALgAECgcJDgAAAA==.Merlinus:BAABLgAECn8dAAIEAAcJ+QmylABTAQAEAAcJ+QmylABTAQAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn8aAAIRAAYJJxHRIAA5AQARAAYJJxHRIAA5AQAAAA==.Mitchelle:BAAALgAECgMJBAAAAA==.',
Mo='Moomkin:BAABLgAECn8aAAIUAAgJZQt4OQBRAQAUAAgJZQt4OQBRAQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Narpul:BAAALgAECgcJCgAAAA==.Natë:BAACLgAFFH8FAAIRAAMJkQvpAwDZAAARAAMJkQvpAwDZAAAuAAQKfyUAAhEACQkRIV0DACMDABEACQkRIV0DACMDAAAA.Nazend:BAAALgADCgQJBAAAAA==.',
Ne='Necrotalon:BAAALgAECgQJBQAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAABLgAECn8kAAIPAAgJsCMODQAXAwAPAAgJsCMODQAXAwAAAA==.Nerzhùl:BAAALgAECgcJDgAAAA==.',
Nh='Nharuna:BAAALgAECgcJEwAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAAALgAECgcJEQAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAAALgAECgYJEwAAAA==.',
No='Nobóunds:BAAALgAECggJCAAAAA==.Nomnoms:BAAALgAECgQJBAAAAA==.Notkarl:BAAALgAECgIJAgAAAA==.Nowimpissed:BAABLgAFFH8GAAMWAAMJdBuDAgAcAQAWAAMJ4BaDAgAcAQALAAEJvyDJHgBkAAAAAA==.Noztra:BAABLgAECn8eAAIGAAcJBQ52LgAQAQAGAAcJBQ52LgAQAQAAAA==.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ob='Obsideon:BAAALgAECgcJDgAAAA==.',
Oh='Ohgr:BAAALgADCgQJBwAAAA==.Ohshifty:BAABLgAECn8dAAIUAAgJuhAKKQC3AQAUAAgJuhAKKQC3AQAAAA==.',
Ol='Olie:BAABLgAECn8VAAILAAYJ1AdtHAAbAQALAAYJ1AdtHAAbAQAAAA==.',
Or='Orbsicles:BAAALgAECgYJCwAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAAALgAECgYJCwABLgAECggJGgAXAEkfAA==.Passtheflask:BAAALgAECgQJDQAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAABLgAECn8pAAMNAAkJTyCnEgAMAwANAAkJTyCnEgAMAwAYAAEJxBGPRwAqAAAAAA==.',
Ph='Phaesphoros:BAAALgAECgYJEgAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFAAGANoXAA==.Powpow:BAAALgAECgQJCAAAAA==.',
Pr='Prejudice:BAAALgAECgcJDwAAAA==.Prowlcow:BAAALgAECgYJEwAAAA==.',
Ps='Psychosis:BAABLgAECn8fAAINAAgJ5xoALgCAAgANAAgJ5xoALgCAAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8HAAIGAAMJ+A8AEwD9AAAGAAMJ+A8AEwD9AAAuAAQKfyUAAgYACAkdHEgQAMABAAYACAkdHEgQAMABAAAA.Rainhoof:BAABLgAECn8WAAMZAAcJOhN5BABUAQAZAAcJOhN5BABUAQAaAAUJYAh5hwDHAAAAAA==.Ralneth:BAACLgAFFH8GAAMbAAQJIBfkAwAOAQAbAAMJABnkAwAOAQADAAEJYRObDwBjAAAuAAQKfyQAAxsACAmrIFADAOsCABsACAmfH1ADAOsCAAMABgnYGz0YABACAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAAALgAECgYJDgAAAA==.Rapalaa:BAAALgADCgEJAQABLgAECgYJDgAFAAAAAA==.Raspútin:BAABLgAECn8ZAAMcAAgJTxEYBgCnAQAcAAgJTxEYBgCnAQAXAAQJ8AfOVQC5AAAAAA==.Rawkfice:BAAALgADCgYJBgAAAA==.',
Re='Renfield:BAAALgADCgUJBQAAAA==.Revok:BAAALgAECgEJAgAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAECggJDAAAAA==.',
Rj='Rjolz:BAABLgAECn8eAAINAAgJGiNqAwBuAgANAAgJGiNqAwBuAgAAAA==.',
Ro='Rootzi:BAAALgAECgEJAQABLgAECgkJFwANAN0WAA==.Rootzidk:BAABLgAECn8XAAINAAcJ3RZjXADdAQANAAcJ3RZjXADdAQAAAA==.',
Ru='Rucks:BAABLgAECn8WAAMXAAcJnBXNBwBdAQAcAAYJ2hThLQCiAQAXAAcJEQ3NBwBdAQAAAA==.',
Sa='Saelem:BAAALgADCgYJBAAAAA==.Sandalfon:BAAALgAECgQJBQAAAA==.Sanleron:BAAALgADCgcJBwAAAA==.Sarith:BAAALgAECgEJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQAFAAAAAA==.',
Sc='Scargon:BAAALgAECgQJBwAAAA==.',
Se='Selidori:BAAALgADCgUJBQAAAA==.Seralicht:BAABLgAFFH8HAAIHAAQJaQf5AgAMAQAHAAQJaQf5AgAMAQAAAA==.',
Sh='Shaliri:BAAALgADCgEJAwAAAA==.Sharayse:BAAALgAECggJDgAAAA==.Sharmee:BAAALgAECgEJAQAAAA==.Shockohôlic:BAAALgAECgYJEAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8VAAINAAgJVggIEQCMAQANAAgJVggIEQCMAQAAAA==.',
Sl='Slingablade:BAAALgAECggJEAAAAA==.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQAFAAAAAA==.',
Sn='Sniffsniff:BAABLgAECn8hAAIEAAgJ6yQBCgBBAwAEAAgJ6yQBCgBBAwAAAA==.',
So='Solvi:BAABLgAECn8aAAIaAAYJmRjPVQBSAQAaAAYJmRjPVQBSAQAAAA==.Soulbrand:BAABLgAECn8WAAIIAAcJ+QVTDgAQAQAIAAcJ+QVTDgAQAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAdAPAfAA==.',
Sp='Spellz:BAAALgAECgYJCgAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQAFAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8UAAIeAAcJsAsZBAAdAQAeAAcJsAsZBAAdAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.',
Su='Sufiya:BAABLgAECn8YAAILAAgJ1Q5LDACqAQALAAgJ1Q5LDACqAQAAAA==.Suhwoo:BAAALgAECgYJDgAAAA==.Sumig:BAAALgADCgEJAwAAAA==.',
Sy='Sylvershadow:BAAALgAECgQJCQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgIJAgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQAFAAAAAA==.Tandarilada:BAAALgAECgYJCwAAAA==.Tanknspankn:BAAALgAECgUJBwAAAA==.',
Th='Thalvint:BAABLgAECn8bAAMQAAgJ5RqcAQD0AQAQAAgJmBqcAQD0AQAMAAYJ1RIVWwBCAQAAAA==.Theblackhand:BAABLgAECn8VAAMfAAYJ9guIWQAiAQAfAAYJ9guIWQAiAQAVAAUJaxO/SgAcAQAAAA==.Thickdk:BAAALgAECgcJEwAAAA==.',
Ti='Timefall:BAAALgAECgcJBQAAAA==.Titanic:BAAALgAECgUJCQAAAA==.',
To='Tomcruise:BAAALgADCgIJAgAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgQJBwAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Té']='Téz:BAAALgADCgYJCgABLgAECgQJBAAFAAAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8qAAIMAAgJ2BPIKAAZAgAMAAgJ2BPIKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Va='Vanarn:BAAALgADCgEJAQABLgADCgQJBQAFAAAAAA==.Vanlin:BAABLgAECn8WAAIaAAcJDR4JBQAxAgAaAAcJDR4JBQAxAgAAAA==.',
Ve='Vexxdr:BAABLgAECn8aAAIaAAgJihHROQC+AQAaAAgJihHROQC+AQAAAA==.Vexxs:BAAALgAECgMJBgABLgAECggJGgAaAIoRAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECgYJEwAFAAAAAA==.',
Vu='Vulperas:BAABLgAECn8UAAIVAAgJ6Q6mLwCiAQAVAAgJ6Q6mLwCiAQAAAA==.',
Vy='Vynastallan:BAAALgAFFAEJAgAAAA==.Vyper:BAEBLgAECn8dAAIDAAgJ9BRuBQCsAQADAAgJ9BRuBQCsAQAAAA==.',
Wa='Waroo:BAABLgAECn8VAAIUAAYJKAurDgAIAQAUAAYJKAurDgAIAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAECgIJAgAAAA==.',
Wi='Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgADCgkJCQAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAAALgAECgUJBgAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAAALgAECgYJEwAAAA==.',
Yi='Yiang:BAABLgAECn8YAAIXAAgJMhZiIgDDAQAXAAgJMhZiIgDDAQAAAA==.',
Yl='Ylndrysa:BAABLgAECn8hAAIaAAgJNBaxLAD8AQAaAAgJNBaxLAD8AQAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAAALgAECgkJBAAAAA==.',
Ze='Zedrock:BAABLgAECn8cAAIGAAgJyBWkWQAsAgAGAAgJyBWkWQAsAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8UAAMUAAYJUhpjCQBZAQAUAAYJxhhjCQBZAQAgAAQJPAogJAB8AAAAAA==.Zeropistol:BAAALgAECgYJDAAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgQJCAAAAA==.',
Zu='Zuro:BAAALgAECgcJDQAAAA==.',
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

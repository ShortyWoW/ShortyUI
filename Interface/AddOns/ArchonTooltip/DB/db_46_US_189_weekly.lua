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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Evoker-Augmentation','Paladin-Retribution','Priest-Shadow','Mage-Frost','Shaman-Restoration','Priest-Holy','Druid-Restoration','Warrior-Fury','Warrior-Arms','Priest-Discipline','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Paladin-Protection','Monk-Windwalker','Warrior-Protection','Druid-Guardian','Paladin-Holy','Mage-Fire','Monk-Mistweaver','Druid-Balance','Shaman-Elemental','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Hunter-Survival','DeathKnight-Blood','Druid-Feral','Evoker-Devastation','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Ablestract:BAAALgADCggJCQAAAA==.',
Ac='Acid:BAAALgAECgQJBgAAAA==.',
Ad='Adreane:BAAALgAECgMJBAAAAA==.',
Af='Aftrlyfe:BAAALgAECgkJBQAAAA==.',
Ai='Aiyana:BAAALgADCgkJEQAAAA==.',
Ak='Akamma:BAAALgAECgcJDQAAAA==.Akarimos:BAAALgADCgMJAwAAAA==.',
Al='Alealle:BAAALgADCgMJAwAAAA==.Alispere:BAAALgADCgUJBQAAAA==.Alizaranna:BAAALgADCgEJAQABLgAECgQJBQABAAAAAA==.',
Am='Amarokk:BAAALgAECgUJEQAAAA==.Ameliae:BAAALgAECgEJAQAAAA==.',
An='Ancestor:BAAALgAECgQJCgAAAA==.Anish:BAAALgAECgEJAQAAAA==.',
Aq='Aqurore:BAAALgADCgYJBgAAAA==.',
As='Assyla:BAAALgAECgEJAQAAAA==.Astraeos:BAAALgAECgQJBQAAAA==.',
Au='Auv:BAACLgAFFH8QAAMCAAQJESb4BwCyAQACAAQJESb4BwCyAQADAAEJlQBbGwA6AAAuAAQKfxQAAwMABwmJJkITALEBAAIABQkZJlZMAOMBAAMABAkgJkITALEBAAEuAAUUBQkFAAQAmQ8A.',
Ax='Axël:BAAALgAFFAEJAQABLgAFFAIJAwABAAAAAA==.',
Ay='Aylranoa:BAAALgADCgkJCQAAAA==.',
Az='Azimondius:BAABLgAECn8kAAIFAAgJeR/dCwC3AgAFAAgJeR/dCwC3AgAAAA==.Azmora:BAAALgAECgIJBAAAAA==.Azzix:BAAALgADCgQJBQAAAA==.',
Ba='Baddragons:BAAALgADCgYJBgAAAA==.Bandit:BAAALgAECgEJAQAAAA==.Bastis:BAAALgAECgEJBAABLgAFFAMJCQAGAMclAA==.Batreaux:BAAALgAECgUJBwAAAA==.',
Be='Beaman:BAAALgADCgEJAQAAAA==.Bearkake:BAAALgAECgMJBgAAAA==.Bellgrande:BAAALgADCgYJBgAAAA==.Bepallylol:BAABLgAECn8YAAIGAAgJYh2vLQBsAgAGAAgJYh2vLQBsAgAAAA==.',
Bi='Bigkeith:BAAALgADCgEJAQAAAA==.Biraj:BAEALgADCggJDgABLgAECgYJFwAGABwFAA==.',
Bl='Blaqichan:BAAALgADCgEJAwABLgADCgQJBQABAAAAAA==.Blight:BAAALgADCgcJBQAAAA==.Bloodybecky:BAAALgAECgMJBAAAAA==.',
Br='Browntotem:BAAALgADCgUJCAAAAA==.',
Bu='Bubblecheeks:BAAALgAECgQJBQAAAA==.Bubblehëarth:BAAALgAECgYJCAAAAA==.Bubby:BAAALgAECgcJEwAAAA==.Burbuja:BAAALgAECgUJCgAAAA==.',
Ca='Cadfile:BAAALgAECgQJBgAAAA==.Careco:BAAALgADCgYJBgAAAA==.Carpetcrumbs:BAAALgAECgUJBQAAAA==.Catnsevrmeme:BAAALgAECgEJAgAAAA==.',
Ce='Cecilio:BAAALgAECgMJAwAAAA==.Cel:BAAALgAECgEJAQAAAA==.Celzara:BAAALgAECgEJAQAAAA==.Cetraa:BAAALgAFFAEJAQAAAA==.',
Ch='Chastise:BAAALgAECgkJCgAAAA==.Chewÿ:BAAALgAECgcJAgAAAA==.Chocobro:BAAALgAECgQJBgAAAA==.Chäös:BAAALgAECgUJBQAAAA==.',
Cl='Clingy:BAAALgADCgkJCAAAAA==.',
Co='Cobble:BAAALgAECgYJBgAAAA==.Colhap:BAABLgAECn8ZAAIHAAcJJhzHIQDJAQAHAAcJJhzHIQDJAQAAAA==.Conjure:BAABLgAECn8dAAMDAAYJbBRRFwCQAAACAAYJfBA3awD1AAADAAMJoxZRFwCQAAAAAA==.Corbina:BAABLgAECn8cAAIIAAcJcCNxNQCeAgAIAAcJcCNxNQCeAgAAAA==.Cousinlarry:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.',
Cr='Cramlutin:BAAALgADCgUJBQAAAA==.Cru:BAAALgAECgkJDgAAAA==.Crui:BAAALgADCgcJBwAAAA==.',
Cu='Culligan:BAABLgAECn9DAAIIAAkJAxnTFgBkAgAIAAkJAxnTFgBkAgAAAA==.Cuttingcrew:BAAALgADCggJCAAAAA==.',
Cy='Cygwin:BAABLgAECn8fAAIJAAcJdRjSFgD8AQAJAAcJdRjSFgD8AQAAAA==.',
Da='Darcyonys:BAAALgAECgIJBQAAAA==.Dariao:BAAALgAECgIJAgABLgAECgkJKwAEAM8ZAA==.Darklon:BAAALgAECggJDwAAAA==.Darkpun:BAAALgADCgcJCQAAAA==.Darîus:BAAALgAECgMJAwAAAA==.Datmage:BAACLgAFFH8HAAIIAAIJ+Ri0WAC1AAAIAAIJ+Ri0WAC1AAAuAAQKfxkAAggABwl3H2teAB8CAAgABwl3H2teAB8CAAAA.',
De='Deathshockz:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.Demunzz:BAAALgADCgUJCQAAAA==.Deriah:BAABLgAECn8hAAIGAAgJBRM3UADxAQAGAAgJBRM3UADxAQAAAA==.Derpatron:BAAALgAECgcJDwAAAA==.Destruction:BAAALgAECggJEwAAAA==.Devo:BAEALgAFFAIJAgAAAA==.',
Di='Disgusti:BAAALgAECgcJDQAAAA==.Divinespark:BAABLgAECn8gAAIKAAgJOhS0FwCTAQAKAAgJOhS0FwCTAQAAAA==.',
Dk='Dkins:BAAALgAECgIJAgAAAA==.',
Do='Dogeform:BAAALgADCgEJAQAAAA==.Doinkbigs:BAABLgAECn8iAAICAAgJXQ2RNQCOAQACAAgJXQ2RNQCOAQAAAA==.Doomo:BAAALgADCgYJBgABLgABCgQJBAABAAAAAA==.Dotsfired:BAAALgADCgQJBAAAAA==.Dotñtrot:BAAALgAFFAIJAgABLgAFFAMJCAAJADUZAA==.',
Dr='Dredd:BAAALgAECgQJBwAAAA==.Drewsilla:BAAALgAECgQJBQAAAA==.Druidrose:BAAALgAECgMJAwAAAA==.Druidtrix:BAAALgADCgYJCwAAAA==.Drylogic:BAABLgAECn8iAAILAAgJmB3pCwCLAgALAAgJmB3pCwCLAgAAAA==.',
Du='Duckworth:BAAALgAECgEJAQAAAA==.Duruk:BAAALgADCgEJAgAAAA==.Dustbroom:BAAALgAECgEJAQAAAA==.',
Ea='Eap:BAAALgAECgcJDwAAAA==.Eazye:BAACLgAFFH8HAAIHAAIJpw7gGACgAAAHAAIJpw7gGACgAAAuAAQKfywAAgcACAkIGswKABcCAAcACAkIGswKABcCAAAA.',
Eb='Ebone:BAAALgADCgMJAQAAAA==.',
Ec='Ectoscourge:BAAALgADCgcJBgAAAA==.',
Ed='Edgeffs:BAABLgAECn8bAAMMAAgJ1QnpIQBeAQAMAAgJdgjpIQBeAQANAAUJZQj5JADFAAAAAA==.',
Ek='Eklipse:BAAALgADCgMJAwABLgABCgQJBAABAAAAAA==.',
El='Elentiya:BAABLgAECn8gAAMKAAkJ6RqXDgB1AgAKAAkJ6RqXDgB1AgAOAAEJegd4WgAtAAAAAA==.Elphzz:BAAALgAECggJEwAAAA==.',
Em='Emoose:BAAALgAECgEJAQAAAA==.',
Er='Eriius:BAAALgAECgQJCQAAAA==.',
Ez='Ez:BAACLgAFFH8TAAMPAAUJhRmhFwDaAAAPAAQJqxKhFwDaAAAQAAIJuBlWNQCwAAAuAAQKfykAAw8ACAnlH50YAGcCAA8ACAnlH50YAGcCABAAAgmXDXylAEoAAAAA.Ezarath:BAAALgAECgYJEwAAAA==.',
Fa='Fadedaf:BAABLgAECn8UAAIEAAYJjQ2YagDHAAAEAAYJjQ2YagDHAAAAAA==.',
Fe='Felenn:BAEALgADCgYJCQABLgAECgYJFwAGABwFAA==.Felorc:BAAALgAECgYJCwAAAA==.Feyla:BAAALgAECgUJCQAAAA==.',
Fo='Foofs:BAAALgADCgUJBQAAAA==.Foulmuffn:BAAALgADCgYJCQAAAA==.Foulplay:BAAALgADCgMJAwAAAA==.Fovos:BAAALgAECgEJAQAAAA==.',
Fr='Freakonleash:BAABLgAECn8YAAIMAAgJ/Rn8GQB8AgAMAAgJ/Rn8GQB8AgAAAA==.',
Fu='Fuegodotz:BAAALgADCgUJBQABLgAECgkJIAARAG4cAA==.',
Ga='Ganjåfarian:BAAALgAECgIJAgAAAA==.',
Ge='Gekatta:BAAALgAECgYJCgAAAA==.Gelektrael:BAABLgAECn8gAAMCAAgJMgoTQgBjAQACAAgJdAkTQgBjAQADAAEJXAzydQAvAAAAAA==.',
Gh='Ghostwarrior:BAAALgADCgMJAwABLgAECgkJRQAGAJshAA==.Ghostzz:BAABLgAECn9FAAMGAAkJmyHXAwAWAwAGAAkJmyHXAwAWAwASAAUJEh7cDQBbAQAAAA==.',
Gl='Glzygldiator:BAACLgAFFH8IAAIRAAMJehROLgDhAAARAAMJehROLgDhAAAuAAQKfyEAAhEABwlQHec4AJYBABEABwlQHec4AJYBAAAA.',
Gn='Gnomelock:BAAALgAECgYJCwAAAA==.',
Go='Gobblin:BAAALgAECgUJDQAAAA==.Govegan:BAAALgADCgQJBwAAAA==.',
Gr='Graavey:BAAALgAECgcJAwABLgAFFAMJCAAJADUZAA==.Greyhairs:BAAALgAECgYJDwAAAA==.Grimthor:BAAALgAECgcJBwAAAA==.Grippy:BAABLgAECn8lAAIEAAgJfx1HIgCEAgAEAAgJfx1HIgCEAgAAAA==.Gromit:BAACLgAFFH8OAAIKAAUJ2hRTBQB1AQAKAAUJ2hRTBQB1AQAuAAQKfyMAAwoACQlNIZMDACEDAAoACQlNIZMDACEDAA4AAgmnEURKAG0AAAAA.Grym:BAAALgADCgcJDgAAAA==.',
Gu='Gustófwind:BAABLgAECn8UAAITAAkJEh/yAgDaAgATAAkJEh/yAgDaAgAAAA==.',
Ha='Haldire:BAAALgAECgIJBgAAAA==.Harrypotture:BAAALgADCgEJAQAAAA==.Haschel:BAABLgAECn8nAAMNAAgJlxvdBAAvAgANAAgJchvdBAAvAgAUAAMJ9Q6GOACFAAAAAA==.',
He='Hexerfender:BAAALgAECgUJBQAAAA==.Heypal:BAAALgADCgUJCwAAAA==.',
Ho='Hofarmer:BAABLgAECn8UAAIVAAkJrRETCQCTAQAVAAkJrRETCQCTAQAAAA==.Hollywoóodxx:BAAALgAFFAEJAgAAAA==.Holychris:BAAALgADCgEJAQAAAA==.Holycöw:BAAALgADCgkJCQAAAA==.Holywood:BAAALgAECgYJBwAAAA==.',
Hu='Hurtak:BAAALgAECgQJBAAAAA==.',
Hy='Hycisan:BAABLgAECn8XAAIWAAYJbx7aEQAKAgAWAAYJbx7aEQAKAgAAAA==.',
Ic='Icanlust:BAAALgADCgIJAgAAAA==.Icant:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.Icon:BAAALgAECgIJAgAAAA==.Icydoodad:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.',
Ig='Ignis:BAAALgADCgMJAwAAAA==.',
Ja='Jacklawin:BAAALgAECgMJAwAAAA==.Jasmyn:BAAALgADCgMJAwAAAA==.',
Jb='Jbirdlol:BAAALgADCgUJBAAAAA==.',
Je='Jesse:BAAALgAECgYJEAABLgAFFAIJBwAWAHYXAA==.Jetmage:BAABLgAECn8cAAIXAAkJviLoAADfAgAXAAkJviLoAADfAgAAAA==.',
Ji='Jire:BAAALgAECgUJDQAAAA==.Jittkal:BAAALgADCgMJAwAAAA==.',
Jo='Josh:BAAALgADCgMJAgAAAA==.',
Jp='Jpally:BAAALgAECgcJEwAAAA==.',
Ju='Jurassthicc:BAAALgAECgEJAgAAAA==.',
Jw='Jwøww:BAAALgADCgEJAgABLgADCgQJBQABAAAAAA==.',
Ka='Kafka:BAAALgADCgcJBgAAAA==.Kanastra:BAABLgAECn8ZAAIEAAgJtR0kDgBYAgAEAAgJtR0kDgBYAgABLgAECggJJAAFAHkfAA==.Karraa:BAABLgAECn8YAAIUAAYJSBr0DgBzAQAUAAYJSBr0DgBzAQAAAA==.Katil:BAAALgAECgEJAQAAAA==.Kaylib:BAABLgAECn8cAAIXAAYJdguUBAAQAQAXAAYJdguUBAAQAQAAAA==.',
Ke='Kea:BAAALgADCgIJAgABLgAECgUJCQABAAAAAA==.Kerze:BAAALgAECgUJDgAAAA==.Kesatrix:BAABLgAECn8YAAIYAAYJUw9cJQAcAQAYAAYJUw9cJQAcAQAAAA==.Kesi:BAAALgADCgQJBAAAAA==.',
Kh='Khai:BAAALgAECgQJBAAAAA==.Khazador:BAAALgADCgkJEgABLgAECggJFwACADAXAA==.Khaztharion:BAAALgADCggJCAABLgAECggJFwACADAXAA==.Khendrick:BAAALgAECgYJEQAAAA==.',
Ki='Kimsmage:BAAALgADCgYJBgAAAA==.Kith:BAAALgAECgEJAQAAAA==.Kitridge:BAAALgAECgcJBwAAAA==.Kittykatt:BAABLgAECn8mAAIZAAgJDhwmCQA8AgAZAAgJDhwmCQA8AgAAAA==.',
Ko='Kolchak:BAAALgADCgYJDQAAAA==.Korel:BAAALgAECgEJBAAAAA==.',
Kr='Kraggo:BAAALgAECgYJCQAAAA==.Krimzin:BAACLgAFFH8MAAIGAAQJfR0hDAB6AQAGAAQJfR0hDAB6AQAuAAQKfxgAAwYACQlnIcwXANoCAAYACAkOIcwXANoCABYAAgkRFaddADsAAAAA.',
Ku='Kumala:BAAALgAECgMJBQAAAA==.',
Ky='Kylea:BAAALgAECgQJBAAAAA==.',
La='Laffiel:BAAALgADCgQJBAAAAA==.Landoh:BAABLgAECn8gAAIIAAgJYCKBDgCoAgAIAAgJYCKBDgCoAgAAAA==.Larsen:BAABLgAECn8gAAIaAAgJMB4PCwApAgAaAAgJMB4PCwApAgAAAA==.',
Le='Leap:BAAALgAECgYJDQAAAA==.Lefthorn:BAAALgADCgIJAgAAAA==.Lenneth:BAAALgAECgIJAgAAAA==.',
Li='Lightofdawn:BAAALgAECgMJAwAAAA==.Lightstyle:BAAALgADCgMJAwAAAA==.Lilow:BAABLgAECn8iAAIHAAgJHxByFQCVAQAHAAgJHxByFQCVAQAAAA==.',
Ll='Llarker:BAEBLgAECn8XAAMGAAYJHAXnpgClAAAGAAYJFAXnpgClAAASAAYJSwHRJgBkAAAAAA==.',
Lo='Lockendron:BAAALgADCgQJBAAAAA==.Locketharion:BAAALgADCgQJBAAAAA==.Lockpebbles:BAAALgADCgMJAwAAAA==.Lokomachina:BAABLgAECn8UAAIQAAcJLyESHwBLAgAQAAcJLyESHwBLAgAAAA==.',
Lu='Luminia:BAAALgADCgcJDwAAAA==.',
Ly='Lynngosa:BAAALgADCgEJAQAAAA==.Lyrana:BAAALgADCgQJBAAAAA==.Lyrasa:BAAALgADCgQJBAAAAA==.',
Ma='Maelidrael:BAAALgAECgIJAgABLgAECggJJgAIADMWAA==.Magisterium:BAABLgAECn8ZAAIKAAYJiAPDMQDBAAAKAAYJiAPDMQDBAAAAAA==.Malady:BAABLgAECn8fAAIHAAgJix/iCgAWAgAHAAgJix/iCgAWAgAAAA==.Malt:BAABLgAECn8XAAIEAAgJuyCnFwD/AQAEAAgJuyCnFwD/AQAAAA==.Malthorial:BAAALgADCgEJAQAAAA==.Mario:BAAALgAECgYJCgABLgAECgYJCwABAAAAAA==.Mattenom:BAAALgADCgYJCAAAAA==.Maulware:BAAALgADCgEJAQAAAA==.',
Mb='Mbrodh:BAAALgAECgQJBAAAAA==.Mbrosmites:BAAALgAECgIJAwAAAA==.',
Md='Mdeag:BAAALgAECgMJBgAAAA==.',
Me='Mefistofeles:BAABLgAECn8YAAIbAAgJahZICwDtAQAbAAgJahZICwDtAQAAAA==.Meingaree:BAAALgAECgUJBwAAAA==.Merlinus:BAABLgAECn8lAAIGAAcJ4gpAeQD5AAAGAAcJ4gpAeQD5AAAAAA==.Merton:BAAALgADCggJDAAAAA==.',
Mi='Mightyguzz:BAABLgAECn8rAAIUAAgJvQ52EABbAQAUAAgJvQ52EABbAQAAAA==.Mitchelle:BAAALgAECgMJBQAAAA==.',
Mo='Moomkin:BAABLgAECn8oAAIZAAgJgwwTGwBdAQAZAAgJgwwTGwBdAQAAAA==.',
My='Mythicblade:BAAALgADCgEJAQAAAA==.',
['Mø']='Møønchild:BAAALgAECgMJAwAAAA==.',
Na='Nai:BAAALgAECgQJDAAAAA==.Nanaish:BAAALgADCgIJAgAAAA==.Narpul:BAABLgAECn8YAAISAAcJxxVxDAB0AQASAAcJxxVxDAB0AQAAAA==.Natë:BAACLgAFFH8LAAIUAAMJOhh+DQDdAAAUAAMJOhh+DQDdAAAuAAQKfy4AAhQACQkvIWIDACMDABQACQkvIWIDACMDAAAA.Nazend:BAAALgADCgQJBAAAAA==.',
Ne='Necrotalon:BAAALgAECgYJDAAAAA==.Nelosi:BAAALgAECgMJCAAAAA==.Neondh:BAACLgAFFH8HAAIEAAMJYSPrGwA6AQAEAAMJYSPrGwA6AQAuAAQKfygAAgQACAkRJA4NABcDAAQACAkRJA4NABcDAAAA.Nerzhùl:BAABLgAECn8aAAIaAAkJcghNHABrAQAaAAkJcghNHABrAQAAAA==.',
Nh='Nharuna:BAABLgAECn8hAAIQAAgJ5w9IKgCnAQAQAAgJ5w9IKgCnAQAAAA==.',
Ni='Nickolaos:BAAALgAECgEJAQAAAA==.Nieloriel:BAABLgAECn8gAAMWAAgJBBPYGwCqAQAWAAgJBBPYGwCqAQAGAAYJ+QTf0ADoAAAAAA==.Nightwishing:BAAALgAECgQJBAAAAA==.Niupiadps:BAAALgAECgIJAgAAAA==.Niykee:BAABLgAECn8aAAQcAAgJXyFuAgAKAgAbAAcJEyGiHAAaAgAdAAcJDx5mBgARAgAcAAUJ3CNuAgAKAgAAAA==.',
No='Noboundss:BAAALgAECgcJDgAAAA==.Nobóunds:BAAALgAECggJDgAAAA==.Nomnoms:BAAALgAECgYJDgAAAA==.Nomoreheals:BAAALgAECgYJBgAAAA==.Notkarl:BAAALgAECgIJAwAAAA==.Nowimpissed:BAABLgAFFH8MAAMeAAMJ9x/aCwAdAQAeAAMJ9x/aCwAdAQAQAAEJvyDVHgBkAAAAAA==.Noztra:BAABLgAECn8eAAIIAAcJEg4qtQB1AQAIAAcJEg4qtQB1AQAAAA==.',
Nu='Nuker:BAAALgAECgEJAQAAAA==.',
Ny='Nysrogh:BAAALgAECgQJCAABLgAFFAIJAgABAAAAAA==.',
Ob='Obsideon:BAAALgAECgcJEQAAAA==.',
Oh='Ohgr:BAAALgAECgUJBQAAAA==.Ohshifty:BAABLgAECn8tAAIZAAkJpRACEADSAQAZAAkJpRACEADSAQAAAA==.',
Ol='Olie:BAABLgAECn8XAAIQAAgJZwcLPABdAQAQAAgJZwcLPABdAQAAAA==.',
Or='Orbsicles:BAAALgAECggJEAAAAA==.',
Pa='Paedrig:BAAALgADCgIJAgAAAA==.Papitomyrey:BAABLgAECn8ZAAMMAAgJnSOdCABfAgAMAAgJnSOdCABfAgANAAUJpxzaFgABAQAAAA==.Passtheflask:BAABLgAECn8XAAICAAYJfwSOgwC/AAACAAYJfwSOgwC/AAAAAA==.',
Pe='Perdition:BAAALgAECgEJAQAAAA==.Pestílence:BAACLgAFFH8IAAIRAAMJHBgdWwDKAAARAAMJHBgdWwDKAAAuAAQKfzMAAxEACQnXIekLAKkCABEACQnXIekLAKkCAB8AAQnEEY1HACoAAAAA.',
Ph='Phaesphoros:BAABLgAECn8XAAIJAAgJLhAFPwCEAQAJAAgJLhAFPwCEAQAAAA==.Phenor:BAAALgAECgQJBAAAAA==.',
Po='Poe:BAAALgADCgYJBgABLgAECgcJFQAIAOEXAA==.Powpow:BAAALgAECgYJDgAAAA==.',
Pr='Prejudice:BAABLgAECn8ZAAIWAAgJshQeEgAHAgAWAAgJshQeEgAHAgAAAA==.Prowlcow:BAABLgAECn8dAAILAAgJYxSGHADfAQALAAgJYxSGHADfAQAAAA==.',
Ps='Psychosis:BAABLgAECn8nAAIRAAgJQR4aGwAoAgARAAgJQR4aGwAoAgAAAA==.',
Pu='Putrescence:BAAALgADCgEJAQAAAA==.',
['Pû']='Pûff:BAAALgAECgcJDwAAAA==.',
Qm='Qmpel:BAAALgADCgMJAwAAAA==.',
Ra='Raiiz:BAACLgAFFH8IAAIIAAMJBBBdLAAFAQAIAAMJBBBdLAAFAQAuAAQKfyYAAggACAkhHIc/AHoCAAgACAkhHIc/AHoCAAAA.Rainhoof:BAABLgAECn8gAAMgAAgJBRjuBAASAgAgAAgJBRjuBAASAgALAAUJYAh7hwDHAAAAAA==.Ralneth:BAACLgAFFH8OAAMFAAYJYBbaBwCvAQAFAAUJLBbaBwCvAQAhAAMJABnmAwAOAQAuAAQKfyQAAyEACAmrIFADAOsCACEACAmfH1ADAOsCAAUABgnYGzoYABACAAAA.Randomtask:BAAALgADCgUJBgAAAA==.Rapala:BAABLgAECn8ZAAICAAgJzxbRHwDyAQACAAgJzxbRHwDyAQAAAA==.Rapalaa:BAAALgAECgIJAwABLgAECggJGQACAM8WAA==.Raspútin:BAABLgAECn8lAAMiAAgJQxQ8EQC8AQAiAAgJQxQ8EQC8AQATAAQJ8AfOVQC5AAAAAA==.Rawkfice:BAAALgADCggJEgAAAA==.',
Re='Renfield:BAAALgADCgYJBwAAAA==.Revok:BAAALgAECgcJCgAAAA==.Revoker:BAAALgADCgYJCAAAAA==.',
Ri='Riordan:BAAALgAECggJDwAAAA==.',
Rj='Rjolz:BAACLgAFFH8FAAIRAAMJhh6DPAAbAQARAAMJhh6DPAAbAQAuAAQKfywAAhEACQl4JZQBAGYDABEACQl4JZQBAGYDAAAA.',
Ro='Rootzi:BAAALgAECgIJAwABLgAECgkJIAARAG4cAA==.Rootzidk:BAABLgAECn8gAAIRAAgJbhxuHQAYAgARAAgJbhxuHQAYAgAAAA==.',
Ru='Rucks:BAABLgAECn8fAAMTAAgJzhnzEgCcAQATAAgJ4A/zEgCcAQAiAAYJzBqcHABPAQAAAA==.',
Sa='Saelem:BAAALgADCgcJBQAAAA==.Sandalfon:BAAALgAECgYJCwAAAA==.Sanleron:BAAALgAECgEJAQAAAA==.Sarith:BAAALgAECgEJAQAAAA==.Saske:BAAALgADCgMJBwABLgAECgEJAQABAAAAAA==.',
Sc='Scargon:BAAALgAECgQJBwAAAA==.',
Se='Selidori:BAAALgADCgUJBQAAAA==.Seralicht:BAABLgAFFH8NAAIKAAUJVQ3HBgBXAQAKAAUJVQ3HBgBXAQAAAA==.',
Sh='Shaliri:BAAALgADCgEJBAAAAA==.Sharayse:BAABLgAECn8WAAIIAAgJSgqefAAYAQAIAAgJSgqefAAYAQAAAA==.Sharmee:BAAALgAECgEJAgAAAA==.Shockohôlic:BAABLgAECn8eAAQaAAgJvRMbFAC1AQAaAAgJvRMbFAC1AQAJAAYJTxCaSwBUAQAjAAEJoApfKwA4AAAAAA==.Shocky:BAAALgAECgcJCgAAAA==.',
Sk='Skullkìng:BAABLgAECn8jAAIRAAkJuhSuHAAcAgARAAkJuhSuHAAcAgAAAA==.',
Sl='Slingablade:BAABLgAECn8VAAIEAAgJcRJ9KACYAQAEAAgJcRJ9KACYAQAAAA==.',
Sm='Smashnskullz:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.',
Sn='Sniffsniff:BAACLgAFFH8JAAIGAAMJxyWhFwBLAQAGAAMJxyWhFwBLAQAuAAQKfykAAwYACAlHJQMKAEEDAAYACAlHJQMKAEEDABYAAQnCHt5TAFcAAAAA.',
So='Solvi:BAABLgAECn8fAAILAAcJ9hctNwA6AQALAAcJ9hctNwA6AQAAAA==.Sonira:BAAALgADCgMJAwAAAA==.Soulbrand:BAABLgAECn8gAAIHAAgJsAj6GwBcAQAHAAgJsAj6GwBcAQAAAA==.Southpawclaw:BAAALgAECgEJAQABLgAECggJFwAjAPAfAA==.',
Sp='Spellz:BAABLgAECn8XAAIHAAcJkhx2DAD/AQAHAAcJkhx2DAD/AQAAAA==.Spuggle:BAAALgAECgQJBAAAAA==.',
St='Stabathuh:BAAALgADCgYJBgAAAA==.Starman:BAAALgAECgkJCQAAAA==.Stoopidrood:BAAALgADCgQJBAABLgADCgUJBQABAAAAAA==.Stoopidtroll:BAAALgADCgUJBQAAAA==.Stormclaw:BAABLgAECn8YAAIkAAgJXwrkCgAgAQAkAAgJXwrkCgAgAQAAAA==.Straeka:BAAALgAECgIJAgAAAA==.',
Su='Sufiya:BAABLgAECn8fAAIQAAkJLw+SIADZAQAQAAkJLw+SIADZAQAAAA==.Suhwoo:BAAALgAECgYJDgAAAA==.Sumig:BAAALgADCgEJBAAAAA==.',
Sy='Sylvershadow:BAABLgAECn8UAAIQAAYJ3g3UTAAnAQAQAAYJ3g3UTAAnAQAAAA==.Sym:BAAALgADCgcJCQAAAA==.',
Ta='Taintedsoulv:BAAALgADCgUJBgAAAA==.Taliri:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Tandarilada:BAAALgAFFAEJAwAAAA==.Tanknspankn:BAAALgAECgUJBwAAAA==.Tankurface:BAAALgAECgEJAQAAAA==.',
Th='Thalvint:BAABLgAECn8pAAMNAAkJACLVAAAcAwANAAkJACLVAAAcAwAMAAYJ1RIbWwBCAQAAAA==.Theblackhand:BAABLgAECn8dAAMaAAYJ1RXOSgAcAQAaAAUJaxPOSgAcAQAJAAYJrQ99PwAGAQAAAA==.Thefira:BAAALgADCgkJCQAAAA==.Thickdk:BAABLgAECn8YAAIRAAgJHRZJbgCtAQARAAgJHRZJbgCtAQAAAA==.Thoriel:BAAALgAECgEJAQAAAA==.',
Ti='Timefall:BAAALgAECgcJBQAAAA==.Titanic:BAAALgAECgUJCQAAAA==.',
To='Tomcruise:BAAALgAECggJDgAAAA==.Toshiro:BAAALgADCgcJBwAAAA==.Totemlyawsum:BAAALgAFFAIJAwAAAA==.Touchymcfeel:BAAALgADCgMJAwAAAA==.',
Tr='Trckr:BAAALgADCgIJAgAAAA==.Treeiage:BAAALgAECgUJCAAAAA==.Trooblu:BAAALgAECgYJEgAAAA==.',
Tw='Twotone:BAAALgAECgEJAQAAAA==.',
['Tê']='Têzeret:BAAALgAECgEJAgAAAA==.',
Ul='Ulkthar:BAABLgAECn8wAAIMAAgJ2BPGKAAZAgAMAAgJ2BPGKAAZAgAAAA==.Ultrauchuva:BAAALgADCgEJAQAAAA==.',
Va='Vanarn:BAAALgADCgEJAQABLgADCgQJBQABAAAAAA==.Vanlin:BAABLgAECn8gAAILAAgJTx69CwCOAgALAAgJTx69CwCOAgAAAA==.',
Ve='Vexxdr:BAABLgAECn8fAAILAAgJHBLTOQC+AQALAAgJHBLTOQC+AQAAAA==.Vexxs:BAAALgAECgUJDgABLgAECggJHwALABwSAA==.',
Vi='Virtey:BAAALgADCgUJBQAAAA==.Virtuous:BAAALgADCgYJBwAAAA==.',
Vl='Vladzy:BAAALgADCgcJAwAAAA==.',
Vo='Voidsuzu:BAAALgAECgMJAwABLgAECggJJAASAMURAA==.Vormedicus:BAAALgAECgEJAQABLgAECggJJQAiAEMUAA==.Voutezhan:BAAALgAECgQJBQAAAA==.',
Vu='Vulperas:BAABLgAECn8cAAIaAAgJJw+nLwCiAQAaAAgJJw+nLwCiAQAAAA==.',
Vy='Vynastallan:BAABLgAECn8ZAAMQAAcJDSPXEABNAgAQAAcJDSPXEABNAgAPAAEJehfPhgA1AAAAAA==.Vyper:BAEBLgAECn8lAAIFAAgJchlFCwAWAgAFAAgJchlFCwAWAgABLgAFFAIJAgABAAAAAA==.',
Wa='Waroo:BAABLgAECn8YAAIZAAgJmAqrGwBXAQAZAAgJmAqrGwBXAQAAAA==.',
We='Wellcole:BAAALgADCgYJBgAAAA==.Wenden:BAAALgAECgIJAgAAAA==.',
Wi='Wilbert:BAAALgADCgEJAQAAAA==.Winniethepo:BAAALgAECgQJBAAAAA==.Witherflow:BAAALgAECgIJAgAAAA==.',
Wo='Woodey:BAAALgADCgcJCAAAAA==.',
Wu='Wulffric:BAAALgAECgYJCwAAAA==.',
Xe='Xeo:BAAALgADCgMJAwAAAA==.',
Ya='Yachirú:BAABLgAECn8kAAISAAgJxRGPDAByAQASAAgJxRGPDAByAQAAAA==.',
Yi='Yiang:BAABLgAECn8fAAITAAkJWxpgEAC5AQATAAkJWxpgEAC5AQAAAA==.',
Yl='Ylndrysa:BAABLgAECn8xAAMLAAgJWxitLAD8AQALAAgJWxitLAD8AQAZAAMJoRjCLQDeAAAAAA==.',
Yt='Ytho:BAAALgADCgYJBgAAAA==.',
Za='Zalithar:BAAALgAECgkJDAAAAA==.',
Ze='Zedrock:BAABLgAECn8mAAIIAAgJMxaPWQAsAgAIAAgJMxaPWQAsAgAAAA==.Zekodian:BAAALgADCgcJDQAAAA==.Zentner:BAABLgAECn8jAAMZAAgJgx0sCABQAgAZAAgJgx0sCABQAgAVAAQJPAoeJAB8AAAAAA==.Zeropistol:BAAALgAECgcJEwAAAA==.Zexrous:BAAALgADCgEJAQAAAA==.',
Zh='Zhas:BAAALgAECgYJDwAAAA==.',
Zu='Zuro:BAABLgAECn8VAAMQAAcJxwuURQA9AQAQAAcJxwuURQA9AQAPAAEJCgHKmQAaAAAAAA==.',
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

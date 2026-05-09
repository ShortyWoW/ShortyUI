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

local lookup = {'Rogue-Outlaw','Warrior-Fury','Druid-Balance','Unknown-Unknown','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Druid-Feral','Mage-Frost','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Priest-Discipline','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','Druid-Restoration','Paladin-Protection','Mage-Arcane','Hunter-Marksmanship','Druid-Guardian','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Arms','DemonHunter-Havoc','Hunter-Survival',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgEJAQAAAA==.Aevie:BAAALgAECgMJAwAAAA==.',
Af='Afterlìfe:BAAALgAECgQJCAAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgQJCAAAAA==.Altair:BAAALgAECgUJCgABLgAECggJGwACAFEfAA==.',
An='Andelynn:BAAALgAECgEJAQAAAA==.',
Ap='Applejuic:BAAALgAECggJDgAAAA==.Appless:BAAALgAECgMJBAAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIDAAkJjAzmGgBfAQADAAkJjAzmGgBfAQAAAA==.Aridella:BAAALgAECgYJDQAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAEAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autumn:BAAALgADCgEJAgAAAA==.',
Av='Avalorne:BAAALgAECgIJAgABLgAECggJGwACAFEfAA==.Avena:BAAALgADCgEJAQAAAA==.',
Az='Azaizel:BAAALgAECgUJCQABLgAECgYJBgAEAAAAAA==.Azusie:BAABLgAECn8iAAIFAAgJKRDxCACSAQAFAAgJKRDxCACSAQAAAA==.',
Ba='Baddate:BAAALgAECgMJAwAAAA==.Baddragøn:BAABLgAECn8qAAMGAAgJ0xXyBgAMAgAGAAgJ0xXyBgAMAgAHAAEJzQNvQgArAAAAAA==.Bangen:BAAALgAECgYJDQAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgADCgYJBgAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAUJCQAIACodAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECggJGwAJAGsXAA==.Billywitchdr:BAABLgAECn8bAAIJAAgJaxcyFgCgAQAJAAgJaxcyFgCgAQAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJDwAEAAAAAA==.',
Bl='Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8jAAIKAAgJYRNSBQB+AQAKAAgJYRNSBQB+AQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgIJAgAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAAALgAECgYJCQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECgcJEwAEAAAAAA==.Breloom:BAAALgADCgEJAQAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBQAAAA==.',
Ch='Chahaein:BAAALgAECgUJBQAAAA==.Charbaby:BAAALgAECgQJCgAAAA==.Charhartt:BAAALgAECgYJCgAAAA==.Charming:BAACLgAFFH8KAAILAAQJFh/PCAB2AQALAAQJFh/PCAB2AQAuAAQKfyAAAgsACAnXGcQcAB0CAAsACAnXGcQcAB0CAAAA.Chelseah:BAAALgAECgYJEAABLgAECgYJDQAEAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.',
Co='Coldknight:BAABLgAECn8UAAMKAAYJgwI/DwCIAAAKAAYJgwI/DwCIAAAMAAQJSwDSRwApAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAAALgAECgYJDgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Cornpop:BAAALgAECgIJAgAAAA==.Cowret:BAABLgAECn8rAAMNAAkJmR70AQBAAwANAAkJmR70AQBAAwAOAAEJAABhJgEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8UAAIPAAYJDAUpFgDHAAAPAAYJDAUpFgDHAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAAALgAECgQJEQAAAA==.Darkjager:BAABLgAECn8oAAIIAAkJexq2EgA7AgAIAAkJexq2EgA7AgAAAA==.Darkways:BAAALgADCgMJAwAAAA==.Darlah:BAAALgAECgcJCgAAAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDQAAAA==.',
De='Deadcobra:BAABLgAECn8WAAIQAAgJCwQLhAAJAQAQAAgJCwQLhAAJAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAEAAAAAA==.Debtknight:BAABLgAECn8nAAIRAAgJoxuXHAAdAgARAAgJoxuXHAAdAgAAAA==.Deelo:BAAALgAECgEJAQAAAA==.Dehumidifier:BAABLgAECn8fAAISAAkJlx6iBgCOAgASAAkJlx6iBgCOAgAAAA==.Deltria:BAAALgAECgQJCAAAAA==.Demonicron:BAAALgADCgQJBAAAAA==.Demonrot:BAAALgAECgUJDgAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAITAAgJkx+ZCgCBAgATAAgJkx+ZCgCBAgAAAA==.Devussi:BAABLgAECn8dAAITAAgJZxRcNgBcAQATAAgJZxRcNgBcAQAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCggJDAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAAAAA==.Donangus:BAABLgAECn8VAAIUAAcJCxH+IwBzAQAUAAcJCxH+IwBzAQAAAA==.Dotero:BAAALgAECgQJBQAAAA==.',
Dr='Dracreina:BAABLgAECn8YAAMHAAUJeBZtCQANAQAHAAQJeBZtCQANAQAGAAEJQQYAKwAnAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAAALgAECgYJEwAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgEJAQAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elissauna:BAAALgAECgIJBAAAAA==.Elylea:BAABLgAECn8YAAICAAgJDROcFgCzAQACAAgJDROcFgCzAQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgADCgcJDgAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgQJCAAAAA==.Feorahir:BAAALgADCgYJBgAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8iAAIIAAgJog5aMQCIAQAIAAgJog5aMQCIAQAAAA==.Fionna:BAAALgAECgUJBQAAAA==.Firereina:BAAALgADCgcJDgABLgAECgUJGAAHAHgWAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxFCEwDTAQACAAkJBxFCEwDTAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8bAAIMAAgJxRzzCwC1AQAMAAgJxRzzCwC1AQAAAA==.',
Fr='Frieia:BAAALgAECgUJEwAAAA==.Frostiilocks:BAAALgAECgEJAQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.',
Fu='Fuze:BAAALgADCgcJBwAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMVAAMJASGWAgDCAAAWAAMJASFhNgD5AAAVAAIJ9B+WAgDCAAAuAAQKfyoABBUACAkXJKAAALACABYACAlwHT8XAMkCABUACAlpIqAAALACABcAAQkAAHhjAEgAAAAA.Galarína:BAABLgAECn8jAAMYAAkJTB27AwC6AgAYAAkJTB27AwC6AgAZAAYJ6iG9EgA4AgAAAA==.Gandora:BAABLgAECn8gAAMRAAkJvBb6HAAaAgARAAkJvBb6HAAaAgAKAAEJ/wPLFwAsAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJIBpHIABqAQACAAgJABdHIABqAQAaAAYJXBdnIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAECgQJBQABLgAECgcJHQAOAGUUAA==.',
Gr='Greasemunkey:BAABLgAECn8WAAIPAAYJtxAtFQBiAQAPAAYJtxAtFQBiAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAABLgAECn8jAAIOAAgJzSEeFgDlAgAOAAgJzSEeFgDlAgAAAA==.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgEJAQAAAA==.Hamburger:BAAALgAECgcJEwAAAA==.Hammerhard:BAAALgADCgQJBAAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJAAbAMgaAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgADCgEJAQAAAA==.',
Ho='Holybean:BAAALgADCgcJDAABLgAECgUJDwAEAAAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCAAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAAALgAECgYJDgAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgADCgcJBwAAAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAEAAAAAA==.',
In='Inferbloom:BAAALgADCgkJDwABLgAFFAQJCwAEAAAAAA==.Infernum:BAAALgAFFAQJCwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8bAAMGAAkJxSASAQBIAwAGAAkJxSASAQBIAwAHAAMJqRl5JwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgYJDQAEAAAAAA==.Jetaime:BAAALgADCgUJBQAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQAAAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAgAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kalidormi:BAAALgAECgQJBgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8bAAMDAAkJEQ7hEQC5AQADAAkJEQ7hEQC5AQAcAAMJNgElwgBDAAAAAA==.',
Kd='Kd:BAAALgADCgMJAwAAAA==.',
Ke='Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAILAAkJwh8BAwDUAgALAAkJwh8BAwDUAgAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8HAAITAAQJWxiYFgBQAQATAAQJWxiYFgBQAQAuAAQKfxsAAhMACAmbGw4VABQCABMACAmbGw4VABQCAAEuAAQKAQkBAAQAAAAA.',
Kh='Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgEJAQAAAA==.Kilan:BAAALgAECgQJEQAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAQAOEXAA==.',
Kr='Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn8hAAIIAAgJHhp/FQAjAgAIAAgJHhp/FQAjAgAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgYJDQAEAAAAAA==.Kyokin:BAABLgAECn8dAAMOAAgJsQqAawAWAQAOAAYJ0A6AawAWAQAdAAcJOAIfNAB4AAAAAA==.Kyzula:BAAALgAECgYJDQAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAgAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilylocks:BAAALgAECgYJCAAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgUJBgAAAA==.',
Lo='Lockology:BAAALgAECgEJAwAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAABLgAECn8oAAMeAAkJIBy0AQCpAgAeAAgJXR60AQCpAgAQAAMJtBB7oADSAAABLgAFFAQJCAACAA0WAA==.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8NAAIcAAQJuAYbHgDmAAAcAAQJuAYbHgDmAAAuAAQKfyQAAhwACAmRFXgwAOkBABwACAmRFXgwAOkBAAAA.Lyniah:BAAALgAECgQJBAAAAA==.',
Ma='Machete:BAAALgAECgQJAwAAAA==.Maelius:BAABLgAECn8gAAINAAkJ0RbpIgAIAgANAAkJ0RbpIgAIAgAAAA==.Maggrus:BAAALgAECgcJEwAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8aAAIfAAgJghEhCQBpAQAfAAgJghEhCQBpAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Matheney:BAABLgAFFH8JAAIgAAUJUwggBAAIAQAgAAUJUwggBAAIAQABLgAECggJHgAhAOIfAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwADADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgEJAQABLgADCgUJBgAEAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCAAAAA==.Melidin:BAAALgAECggJDwAAAA==.Melinda:BAAALgADCgYJBgAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgUJCAAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAABLgAECn8VAAIIAAYJ1xTwQgBFAQAIAAYJ1xTwQgBFAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJDwAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAQAAAA==.Moontann:BAAALgADCggJCAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgUJDgAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIcAAgJshVuJwCTAQAcAAgJshVuJwCTAQAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgADCgQJBwABLgAECgQJBQAEAAAAAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECggJFQAJAEMdAA==.Natstryker:BAABLgAECn8lAAQLAAkJNyNpBwBaAgALAAkJ5CJpBwBaAgAYAAYJiiJFFQBCAgAZAAYJsA+yJAAiAQAAAA==.Naturemyth:BAAALgAFFAEJAgAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8dAAITAAYJphUnPABGAQATAAYJphUnPABGAQAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAgABLgAECgYJDQAEAAAAAA==.',
No='Nonaha:BAAALgADCgkJDAAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgAECgQJBAAAAA==.',
Or='Organa:BAAALgAECgUJEgAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAEAAAAAA==.',
Pe='Petal:BAAALgAECgYJBgABLgAECggJDwAEAAAAAA==.',
Pl='Plowmcballs:BAABLgAECn8ZAAIOAAYJtxI0fgB+AQAOAAYJtxI0fgB+AQAAAA==.Plugley:BAABLgAECn8ZAAMQAAgJBRqYJAATAgAQAAgJBRqYJAATAgAeAAEJARSFHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8XAAISAAcJcyGDBwB7AgASAAcJcyGDBwB7AgAAAA==.Potooòooóoo:BAABLgAECn8ZAAIKAAcJDhjzBgBGAQAKAAcJDhjzBgBGAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAgAAAA==.',
Pu='Purebeef:BAAALgAECgEJAQAAAA==.',
Py='Pygos:BAABLgAECn8ZAAIiAAgJ5BiJBwANAgAiAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgQJCAAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAAALgAECgYJCwAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgYJDQAEAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAAALgAECgUJCQAAAA==.Ratheen:BAABLgAECn8VAAIOAAYJEBGMkwBWAQAOAAYJEBGMkwBWAQAAAA==.Raytar:BAABLgAECn8ZAAMDAAgJ/x7BCwANAgADAAcJMSDBCwANAgAcAAMJ9Bv7mgCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECggJKgAGANMVAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgADCgMJAQABLgAECgcJGQALAHgXAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Ros:BAAALgAECgMJAwAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn8nAAIJAAgJUwaLLQAAAQAJAAgJUwaLLQAAAQAAAA==.Ruu:BAAALgAECgkJAgAAAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIbAAgJHRWnGAAcAgAbAAgJHRWnGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAAALgAECgUJEwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJCgAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECgcJGAADAGwVAA==.Seshiro:BAAALgAECgQJBAABLgAECggJKQAdACQlAA==.',
Sh='Shadoweave:BAABLgAFFH8JAAMSAAQJVRRCCQAwAQASAAQJVRRCCQAwAQAbAAIJ+wRhGwCIAAABLgAFFAcJGgAIAB4SAA==.Shalalia:BAAALgAECgEJAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAEAAAAAA==.Shentsu:BAABLgAECn8YAAIZAAkJ0CD4BQD/AgAZAAkJ0CD4BQD/AgAAAA==.Shhanks:BAAALgADCgUJBQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAIOAAgJDwysVwBCAQAOAAgJDwysVwBCAQAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAABLgAECn8ZAAIOAAcJaBQLQACFAQAOAAcJaBQLQACFAQAAAA==.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8gAAMIAAgJmA1eNwDRAQAIAAgJmA1eNwDRAQAfAAQJMwKKIQBNAAAAAA==.',
So='Songstar:BAABLgAECn8eAAIIAAkJkCJcBgDMAgAIAAkJkCJcBgDMAgAAAA==.Soullraven:BAAALgADCgcJJAAAAA==.',
Sp='Spy:BAAALgAECgEJAwAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8WAAIQAAYJBwgCiQAAAQAQAAYJBwgCiQAAAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.Starblaze:BAAALgAECgUJBwAAAA==.Starseek:BAAALgAECgYJEwAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAABLgAECn8bAAIMAAYJ2B1hEQD1AQAMAAYJ2B1hEQD1AQAAAA==.Sugarpop:BAACLgAFFH8GAAINAAMJNw2jGgDPAAANAAMJNw2jGgDPAAAuAAQKfygAAg0ACQnXHIESAH4CAA0ACQnXHIESAH4CAAAA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAgJJAARAEocAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgQJBAAAAA==.Syntheria:BAAALgADCgUJBgAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAECggJGgAZAPwWAA==.',
Ta='Taediah:BAAALgAECgIJAgAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgEJAQAAAA==.Thesarius:BAABLgAECn8ZAAIaAAgJXxmTDQAxAgAaAAgJXxmTDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAEAAAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8ZAAIQAAYJvAdZnADaAAAQAAYJvAdZnADaAAAAAA==.Toetagger:BAAALgAECgYJEgAAAA==.Tofino:BAAALgAECgQJBQAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAECgIJBQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgYJDQAEAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8WAAIOAAYJJRpyPgCKAQAOAAYJJRpyPgCKAQAAAA==.Tyshus:BAAALgAECgYJDAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgUJCAAEAAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgAAAA==.',
Va='Valarion:BAABLgAECn8aAAIjAAcJXgplFQBVAQAjAAcJXgplFQBVAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAAALgAECgcJCwAAAA==.Valinis:BAAALgADCggJDwAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn8lAAMCAAkJFSARDAApAgACAAkJSx8RDAApAgAaAAMJ8xm7LABhAAAAAA==.Valtaa:BAAALgADCgMJAwAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn81AAIQAAgJtyDXEQCKAgAQAAgJtyDXEQCKAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJEAAEAAAAAA==.Velandriel:BAAALgADCgkJCQAAAA==.Verra:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJCAAAAA==.Volbain:BAABLgAECn8ZAAMkAAUJ0R2sFgAxAQAkAAUJ0R2sFgAxAQATAAEJ0wJ/0AAeAAAAAA==.Volklin:BAABLgAECn8bAAMIAAcJaRTbTQB/AQAIAAcJaRTbTQB/AQAlAAMJBAZjJwB+AAAAAA==.Voltagex:BAABLgAECn8YAAITAAcJHBcfRwDXAQATAAcJHBcfRwDXAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8UAAIWAAUJshXlXwARAQAWAAUJshXlXwARAQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIDAAcJeg1RPABDAQADAAcJeg1RPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn8mAAMRAAgJbA6SRgBoAQARAAcJ0g+SRgBoAQAMAAEJBQY1PAAkAAAAAA==.Wildkitty:BAAALgAECgYJBwAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wt='Wtfguën:BAABLgAECn8WAAIgAAUJXA5OFwCoAAAgAAUJXA5OFwCoAAAAAA==.Wtftäzmikell:BAAALgADCgYJBgABLgAECgUJFgAgAFwOAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8YAAIDAAcJbBVcJgDKAQADAAcJbBVcJgDKAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yu='Yuck:BAAALgAECgIJAwAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJDwAAAA==.',
Zo='Zorell:BAAALgADCgMJAwAAAA==.Zovaal:BAAALgADCgYJBgAAAA==.',
['Ál']='Áltá:BAABLgAECn8fAAMWAAkJvhViLACyAQAWAAkJvhViLACyAQAXAAIJNwyEHABlAAAAAA==.',
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

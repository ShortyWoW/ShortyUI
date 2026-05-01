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

local lookup = {'Rogue-Outlaw','Unknown-Unknown','Druid-Balance','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Frost','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Priest-Discipline','Warrior-Fury','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Druid-Restoration','Paladin-Protection','Mage-Arcane','Hunter-Marksmanship','Druid-Guardian','Evoker-Augmentation','DemonHunter-Vengeance','Priest-Shadow','Warrior-Arms','DemonHunter-Havoc','Hunter-Survival',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aevie:BAAALgADCgkJFQAAAA==.',
Af='Afterlìfe:BAAALgAECgQJBAAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJCQABLgAECgcJEwACAAAAAA==.',
An='Andelynn:BAAALgADCgYJBgAAAA==.',
Ap='Applejuic:BAAALgAECggJDQAAAA==.Appless:BAAALgAECgMJBAAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIDAAkJiwyuEwBoAQADAAkJiwyuEwBoAQAAAA==.Aridella:BAAALgAECgYJDQAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwACAAAAAA==.',
Au='Autumn:BAAALgADCgEJAgAAAA==.',
Av='Avena:BAAALgADCgEJAQAAAA==.',
Az='Azaizel:BAAALgAECgUJCQABLgAECgYJBgACAAAAAA==.Azusie:BAABLgAECn8hAAIEAAgJKRAcBgCsAQAEAAgJKRAcBgCsAQAAAA==.',
Ba='Baddate:BAAALgADCgkJDwAAAA==.Baddragøn:BAABLgAECn8mAAMFAAgJGxPQBQD1AQAFAAgJGxPQBQD1AQAGAAEJzQNwQgArAAAAAA==.Bangen:BAAALgAECgYJDQAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgADCgYJBgAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAUJBgAHAFUWAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgcJFAAIALISAA==.Billywitchdr:BAABLgAECn8UAAIIAAcJshJ5MwCLAQAIAAcJshJ5MwCLAQAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJDgACAAAAAA==.',
Bl='Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8jAAIJAAgJXhNMAwCcAQAJAAgJXhNMAwCcAQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgIJAgAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAAALgAECgMJAwAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJBwAAAA==.Brainfart:BAAALgADCgUJBQABLgAECgUJDAACAAAAAA==.Breloom:BAAALgADCgEJAQAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJBwAAAA==.',
Ca='Cariandria:BAAALgAECgUJBQAAAA==.',
Ch='Charbaby:BAAALgAECgQJCQAAAA==.Charhartt:BAAALgAECgMJBAAAAA==.Charming:BAACLgAFFH8GAAIKAAMJ/xqaEwD+AAAKAAMJ/xqaEwD+AAAuAAQKfx0AAgoACAmpGcMcAB0CAAoACAmpGcMcAB0CAAAA.Chelseah:BAAALgAECgYJDAABLgAECgYJDQACAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECggJEgAAAA==.',
Co='Coldknight:BAAALgAECgYJDgAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAAALgAECgUJCgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Cornpop:BAAALgAECgIJAgAAAA==.Cowret:BAABLgAECn8nAAMLAAgJtx+RAwDLAgALAAgJtx+RAwDLAgAMAAEJAABe6QAAAAAAAA==.',
Cr='Crystalwolf:BAAALgAECgYJDgAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAAALgAECgQJDwAAAA==.Darkjager:BAABLgAECn8jAAIHAAkJQBrkDAA3AgAHAAkJQBrkDAA3AgAAAA==.Darkways:BAAALgADCgMJAwAAAA==.Darlah:BAAALgAECgcJCgAAAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDQAAAA==.',
De='Deadcobra:BAABLgAECn8UAAINAAgJlQOjcQD1AAANAAgJlQOjcQD1AAAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgQJCgACAAAAAA==.Debtknight:BAABLgAECn8fAAIOAAgJoRuuEAA3AgAOAAgJoRuuEAA3AgAAAA==.Deelo:BAAALgADCgcJCgAAAA==.Dehumidifier:BAABLgAECn8fAAIPAAkJlx67AwCkAgAPAAkJlx67AwCkAgAAAA==.Deltria:BAAALgAECgQJBAAAAA==.Demonicron:BAAALgADCgMJAwAAAA==.Demonrot:BAAALgAECgUJCQAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIQAAgJPh+dBQCGAgAQAAgJPh+dBQCGAgAAAA==.Devussi:BAABLgAECn8dAAIQAAgJPRTtIgBiAQAQAAgJPRTtIgBiAQAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCgQJBQAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAAAAA==.Donangus:BAABLgAECn8UAAIRAAcJwQ7/IwBzAQARAAcJwQ7/IwBzAQAAAA==.Dotero:BAAALgAECgEJAgAAAA==.',
Dr='Dracreina:BAAALgAECgQJEwAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAAALgAECgYJEgAAAA==.',
Dv='Dvsmage:BAAALgAECgQJCgAAAA==.',
Eg='Egaik:BAAALgAECgEJAQAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elissauna:BAAALgAECgIJAwAAAA==.Elylea:BAABLgAECn8XAAISAAgJWRJaFwB3AQASAAgJWRJaFwB3AQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgADCgcJCAAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgQJBAAAAA==.Feorahir:BAAALgADCgYJBgAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8aAAIHAAgJVQ5xKQBwAQAHAAgJVQ5xKQBwAQAAAA==.Firereina:BAAALgADCgcJCAABLgAECgQJEwACAAAAAA==.',
Fl='Fleurminator:BAABLgAECn8gAAISAAkJBREADADtAQASAAkJBREADADtAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8UAAITAAcJvBxpDwAVAgATAAcJvBxpDwAVAgAAAA==.',
Fr='Frieia:BAAALgAECgQJDgAAAA==.Frostiilocks:BAAALgAECgEJAQAAAA==.Frostitutte:BAAALgAECgUJEAAAAA==.',
Ga='Galakrosh:BAACLgAFFH8FAAIUAAMJASHdIwAQAQAUAAMJASHdIwAQAQAuAAQKfyEAAxQACAlwHUEXAMkCABQACAlwHUEXAMkCABUAAQkAAHpjAEgAAAAA.Galarína:BAABLgAECn8jAAMWAAkJTB0/AgDCAgAWAAkJTB0/AgDCAgAXAAYJ6iG+EgA4AgAAAA==.Gandora:BAABLgAECn8gAAMOAAkJuhadEQAuAgAOAAkJuhadEQAuAgAJAAEJ/wMgEQAzAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMSAAgJFRoMFwB6AQASAAgJ8hYMFwB6AQAYAAYJWBdqIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAECgQJBQABLgAECgcJGQAMAFMUAA==.',
Gr='Greasemunkey:BAAALgAECgYJEAAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAABLgAECn8jAAIMAAgJzCEiFgDkAgAMAAgJzCEiFgDkAgAAAA==.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgEJAQAAAA==.Hamburger:BAAALgAECgcJEwAAAA==.Hampter:BAAALgAECgYJCQAAAA==.',
He='Heights:BAAALgAECgUJCQAAAA==.',
Ho='Holybean:BAAALgADCgcJBwABLgAECgQJCgACAAAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCAAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAAALgAECgUJCQAAAA==.Huntt:BAAALgADCgcJBwAAAA==.',
Hy='Hyphira:BAAALgAECgMJBgABLgAECgUJCgACAAAAAA==.',
In='Inferbloom:BAAALgADCgkJDwABLgAFFAMJBwACAAAAAA==.Infernum:BAAALgAFFAMJBwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ja='Jackyvoker:BAABLgAECn8aAAMFAAkJvyCeAABSAwAFAAkJvyCeAABSAwAGAAMJqRl9JwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgYJDQACAAAAAA==.Jetaime:BAAALgADCgUJBQAAAA==.',
Ji='Jinksey:BAAALgAECgcJCwAAAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAgAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgEJAQAAAA==.',
Ka='Kalidormi:BAAALgAECgIJAgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kayelalynn:BAABLgAECn8bAAMDAAkJDg5wDADFAQADAAkJDg5wDADFAQAZAAMJNgEhwgBDAAAAAA==.',
Kd='Kd:BAAALgADCgMJAwAAAA==.',
Ke='Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8hAAIKAAgJlCDLAwCDAgAKAAgJlCDLAwCDAgAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAABLgAECn8ZAAIQAAgJtRjCDgD/AQAQAAgJtRjCDgD/AQABLgAECgEJAQACAAAAAA==.',
Kh='Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgADCgYJBQAAAA==.Kilan:BAAALgAECgQJEQAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.',
Ko='Korz:BAAALgADCgcJBwAAAA==.',
Kr='Krynj:BAAALgAFFAEJAgAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn8ZAAIHAAcJXBawKAB0AQAHAAcJXBawKAB0AQAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgYJDQACAAAAAA==.Kyokin:BAABLgAECn8WAAMMAAgJ3Qm/XgD4AAAMAAYJpw2/XgD4AAAaAAYJXwIhNAB4AAAAAA==.Kyzula:BAAALgAECgQJBwAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAQAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilylocks:BAAALgAECgYJCAAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.',
Lo='Lockology:BAAALgAECgEJAwAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAABLgAECn8lAAIbAAgJWB60AQCpAgAbAAgJWB60AQCpAgABLgAECggJHgASAOEbAA==.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8GAAIZAAMJJwjzHwCiAAAZAAMJJwjzHwCiAAAuAAQKfyMAAhkACAmQFXswAOkBABkACAmQFXswAOkBAAAA.Lyniah:BAAALgAECgQJBAAAAA==.',
Ma='Machete:BAAALgAECgQJAwAAAA==.Maelius:BAABLgAECn8gAAILAAkJ0RavEADcAQALAAkJ0RavEADcAQAAAA==.Maggrus:BAAALgAECgUJDAAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8aAAIcAAgJdxF5BgCHAQAcAAgJdxF5BgCHAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Matheney:BAABLgAFFH8GAAIdAAUJ/wW+AgAWAQAdAAUJ/wW+AgAWAQABLgAECgcJHAAeAK0eAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwADAC0PAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgEJAQAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCAAAAA==.Melidin:BAAALgAECggJDQAAAA==.Melinda:BAAALgADCgYJBgAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgUJCAAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAAALgAECgYJEAAAAA==.',
Mo='Monk:BAAALgAECggJDgAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgMJBQAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIZAAgJshUHHACfAQAZAAgJshUHHACfAQAAAA==.',
My='Mystahmurdah:BAAALgADCgQJBwABLgAECgQJBAACAAAAAA==.Mysterioñ:BAAALgAECgQJCwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nasine:BAAALgAECgYJCAABLgAECgcJDQACAAAAAA==.Natstryker:BAABLgAECn8lAAQKAAkJMSPqBABgAgAKAAkJ2yLqBABgAgAWAAYJiiJIFQBCAgAXAAYJrg98GwAmAQAAAA==.Naturemyth:BAAALgAFFAEJAgAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8YAAIQAAYJThIkPQDxAAAQAAYJThIkPQDxAAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
No='Nonaha:BAAALgADCgkJDAAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgAECgQJBAAAAA==.',
Or='Organa:BAAALgAECgQJDQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgACAAAAAA==.',
Pe='Petal:BAAALgAECgYJBgABLgAECggJDgACAAAAAA==.',
Pl='Plowmcballs:BAABLgAECn8YAAIMAAYJtRIwfgB+AQAMAAYJtRIwfgB+AQAAAA==.Plugley:BAABLgAECn8XAAMNAAcJ7RxXIQDmAQANAAcJ7RxXIQDmAQAbAAEJARSEHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8WAAIPAAYJWSFICAAnAgAPAAYJWSFICAAnAgAAAA==.Potooòooóoo:BAAALgAECgUJEwAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.',
Pu='Purebeef:BAAALgAECgEJAQAAAA==.',
Py='Pygos:BAABLgAECn8ZAAIfAAgJ4xgfBAC7AQAfAAgJ4xgfBAC7AQAAAA==.',
['Pë']='Përdü:BAAALgAECgQJBAAAAA==.',
Ra='Raegnarok:BAAALgAECgQJBAAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgYJDQACAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAAALgAECgQJBAAAAA==.Ratheen:BAABLgAECn8VAAIMAAYJEBGPkwBWAQAMAAYJEBGPkwBWAQAAAA==.Raytar:BAABLgAECn8XAAMDAAgJ/B6mEQCOAgADAAcJLSCmEQCOAgAZAAMJ8hv8mgCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECggJJgAFABsTAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgADCgMJAQABLgAECgcJFgAKAMIUAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Ros:BAAALgAECgMJAwAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn8jAAIIAAgJ3wVUJAD/AAAIAAgJ3wVUJAD/AAAAAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIgAAgJHRWrGAAcAgAgAAgJHRWrGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAAALgAECgQJDgAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJBwAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBQABLgAECgcJFwADAGwVAA==.Seshiro:BAAALgAECgQJBAAAAA==.',
Sh='Shadoweave:BAABLgAFFH8GAAIPAAQJJBSuBQBFAQAPAAQJJBSuBQBFAQABLgAFFAUJCQAZAG8MAA==.Shalalia:BAAALgADCgcJDAAAAA==.Shentsu:BAABLgAECn8YAAIXAAkJ0CD5BQD/AgAXAAkJ0CD5BQD/AgAAAA==.Shhanks:BAAALgADCgUJBQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8UAAIMAAcJXA2xTwAdAQAMAAcJXA2xTwAdAQAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAAALgAECgYJEwAAAA==.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8cAAMHAAgJ8AxbNwDRAQAHAAgJ8AxbNwDRAQAcAAQJMQIpGwBXAAAAAA==.',
So='Songstar:BAABLgAECn8eAAIHAAkJiCJ9AgDvAgAHAAkJiCJ9AgDvAgAAAA==.Soullraven:BAAALgADCgcJIwAAAA==.',
Sp='Spy:BAAALgAECgEJAwAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAAALgAECgUJEgAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAACAAAAAA==.Starblaze:BAAALgAECgUJBgAAAA==.Starseek:BAAALgAECgYJEwAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAABLgAECn8VAAITAAYJ2B1jEQD1AQATAAYJ2B1jEQD1AQAAAA==.Sugarpop:BAABLgAECn8oAAILAAkJ2ByBEgB+AgALAAkJ2ByBEgB+AgAAAA==.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAcJGQAOAH4eAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQAAAA==.',
Ta='Taediah:BAAALgAECgIJAgAAAA==.Tamius:BAAALgADCgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgEJAQAAAA==.Thesarius:BAABLgAECn8ZAAIYAAgJXhmQBwDGAQAYAAgJXhmQBwDGAQAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAACAAAAAA==.',
Ti='Tiestto:BAAALgAECgYJCQAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8ZAAINAAYJvAeAfADbAAANAAYJvAeAfADbAAAAAA==.Toetagger:BAAALgAECgYJEgAAAA==.Tofino:BAAALgAECgEJAQAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tonimâster:BAAALgAECgIJBAAAAA==.Toyotama:BAAALgAECgUJCgAAAA==.',
Tr='Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgYJDQACAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAAALgAECgUJEgAAAA==.Tyshus:BAAALgAECgYJDAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgUJCAACAAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgAAAA==.',
Va='Valarion:BAABLgAECn8aAAIhAAcJWQpnFQBVAQAhAAcJWQpnFQBVAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAAALgAECgYJCgAAAA==.Valinis:BAAALgADCggJDwAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn8lAAMSAAkJDyDOBgBFAgASAAkJRR/OBgBFAgAYAAMJ8hksIwBiAAAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn8xAAINAAgJtyC0DAB9AgANAAgJtyC0DAB9AgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJEAACAAAAAA==.Velandriel:BAAALgADCgkJCQAAAA==.Verra:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJCAAAAA==.Volbain:BAABLgAECn8UAAMiAAQJ0R1fEgAeAQAiAAQJ0R1fEgAeAQAQAAEJ+wFfnwAeAAAAAA==.Volklin:BAABLgAECn8aAAMHAAYJcxTZTQB/AQAHAAYJcxTZTQB/AQAjAAMJBAZiJwB+AAAAAA==.Voltagex:BAABLgAECn8VAAIQAAcJGBcgRwDXAQAQAAcJGBcgRwDXAQAAAA==.',
Vu='Vulpsinculta:BAAALgAECgQJDwAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8eAAIDAAcJeApLPABDAQADAAcJeApLPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn8iAAMOAAgJ+A2JNQBjAQAOAAcJTA+JNQBjAQATAAEJ/QXCLQAlAAAAAA==.Wildkitty:BAAALgAECgYJBgAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wt='Wtfguën:BAAALgAECgQJEQAAAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8XAAIDAAcJbBVXJgDKAQADAAcJbBVXJgDKAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yu='Yuck:BAAALgAECgIJAwAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJDwAAAA==.',
['Ál']='Áltá:BAABLgAECn8fAAMUAAkJvhWhHgC9AQAUAAkJvhWhHgC9AQAVAAIJMwxvFwBlAAAAAA==.',
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

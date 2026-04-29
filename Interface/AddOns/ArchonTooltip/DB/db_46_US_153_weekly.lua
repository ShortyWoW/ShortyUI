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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Warrior-Protection','Warrior-Arms','Warlock-Demonology','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Rogue-Outlaw','Warrior-Fury','Paladin-Protection','Druid-Restoration','Monk-Brewmaster','Evoker-Devastation','Warlock-Affliction','Warlock-Destruction','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','Shaman-Restoration',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aakkulay:BAAALgAECgEJAgAAAA==.',
Ab='Absofsteels:BAAALgAECgQJCQAAAA==.',
Ac='Acaric:BAAALgAECgcJEgAAAA==.Ache:BAAALgAECgMJBAAAAA==.',
Ad='Adriel:BAAALgAECgYJBwAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8XAAIBAAgJ3RaGIgA2AgABAAgJ3RaGIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCgYJBgAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgUJBQAAAA==.',
Ak='Akairo:BAAALgAECgcJCwAAAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alchemist:BAAALgADCgUJDQAAAA==.Alidor:BAAALgAECgEJAQAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgIJAgAAAA==.Altharoth:BAAALgAECgEJAQAAAA==.',
Am='Amira:BAACLgAFFH8JAAICAAQJMSAYAgCUAQACAAQJMSAYAgCUAQAuAAQKfxsAAgIACAklJWoCAEUDAAIACAklJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.',
An='Anteiku:BAAALgADCgcJCwAAAA==.Anthiva:BAAALgAECgYJCgAAAA==.',
Ar='Arauial:BAAALgAECgUJBgAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAABLgAECn8lAAIBAAgJchj7BgD8AQABAAgJchj7BgD8AQAAAA==.Arizann:BAAALgAECgYJEAAAAA==.Arobotpr:BAAALgAECgYJEAAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgADCgUJCAAAAA==.Astaren:BAAALgAECgEJAgAAAA==.Asuran:BAAALgAECgYJCgAAAA==.',
At='Atem:BAAALgADCggJCgAAAA==.',
Au='Aulinn:BAAALgAECgEJAQAAAA==.Aurelianus:BAAALgAECgYJDQAAAA==.',
Av='Avalanche:BAAALgAECgIJAgAAAA==.',
Az='Azaris:BAABLgAECn8bAAIDAAcJYxo5CABzAQADAAcJYxo5CABzAQAAAA==.',
Ba='Baelrog:BAAALgAECgIJAgAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8cAAMEAAkJvBHnRwDUAQAEAAkJvBHnRwDUAQAFAAEJRQt4KwAzAAAAAA==.Baranina:BAACLgAFFH8IAAMBAAQJxxrHBwAnAQABAAMJph3HBwAnAQAGAAIJ7RV0HACkAAAuAAQKfyUABAYACAmyI6wOAMoCAAYACAmsHqwOAMoCAAEABQmOHwo2ANYBAAcAAwkuIU8bAB8BAAAA.Barricaded:BAAALgAECgYJCAAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJAwAIAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgADCgMJAwAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAAALgAECgYJEAAAAA==.Benji:BAEALgAECgQJDwAAAA==.',
Bi='Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blindaf:BAAALgAECgQJCQAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAAALgAECgcJDgAAAA==.Blite:BAAALgADCgUJDQAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAAALgAECggJDwAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAAALgAECgEJAQAAAA==.Blueeyearch:BAAALgAECgQJBQAAAA==.',
Bo='Bonedecay:BAAALgAECgEJAQAAAA==.Boomadk:BAABLgAECn8eAAMJAAgJYCI7HwDGAgAJAAgJ2iE7HwDGAgAKAAcJnx/WAgB7AgAAAA==.Boomapriest:BAAALgAECgUJBgAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAAALgAECggJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgIJAgAAAA==.Brassybella:BAAALgADCggJFAAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAAALgAECgEJAgAAAA==.Briochebun:BAABLgAECn8bAAILAAgJsB3tIACnAgALAAgJsB3tIACnAgAAAA==.',
Bu='Bustin:BAAALgAECgYJDAAAAA==.',
Bw='Bwangifer:BAAALgAECgYJEAAAAA==.',
['Bë']='Bëcky:BAAALgAFFAEJAQAAAA==.',
Ca='Caerus:BAAALgADCgYJDAABLgAECgYJEwAIAAAAAA==.Caitriona:BAAALgADCgMJAwABLgADCgUJBwAIAAAAAA==.Cannala:BAAALgADCgUJDQAAAA==.Cargae:BAAALgADCgMJAwAAAA==.Cassios:BAABLgAECn8WAAIMAAcJtRVuCABPAQAMAAcJtRVuCABPAQAAAA==.',
Ce='Celathel:BAAALgAECgIJAgAAAA==.Cellysia:BAAALgAECgYJEgAAAA==.Celsìus:BAAALgAECgYJEgAAAA==.Ceramyth:BAAALgAECgMJBgAAAA==.Ceres:BAAALgAECgYJEAAAAA==.Cesara:BAABLgAECn8gAAMDAAgJoR4LCwDRAgADAAgJoR4LCwDRAgACAAEJ8gcPfwAzAAAAAA==.',
Ch='Chaahck:BAAALgADCgkJCQAAAA==.Chal:BAAALgAECgEJAQAAAA==.Chbribs:BAAALgAECgIJAgAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8fAAINAAcJ9R9BDwDLAQANAAcJ9R9BDwDLAQAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgYJBgAAAA==.Columbina:BAACLgAFFH8MAAIEAAQJuQwuFAAwAQAEAAQJuQwuFAAwAQAuAAQKfx0AAgQABwmgGbVEAOEBAAQABwmgGbVEAOEBAAAA.Comma:BAABLgAECn8UAAIOAAcJFRKoHABjAQAOAAcJFRKoHABjAQAAAA==.Cooperhowerd:BAAALgADCgUJDQAAAA==.Corn:BAAALgAECgQJBgAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAABLgAECn8pAAMPAAgJRRxXAQANAgAPAAgJRRxXAQANAgAOAAIJGxBEEABoAAAAAA==.Cravens:BAAALgADCgcJCgAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAAALgAECgYJEAAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgADCgYJEgAAAA==.Daen:BAAALgADCgcJCgAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgIJAgAAAA==.Damerot:BAAALgAECgUJDAAAAA==.Dandity:BAAALgAECgEJAQAAAA==.Dangerous:BAAALgADCgcJBwAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgEJAQAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAAALgAFFAEJAQAAAA==.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAECgYJBgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Delphina:BAAALgADCgQJAwAAAA==.Demini:BAAALgADCgcJDgAAAA==.Demisê:BAAALgAECgcJEwAAAA==.Demonessa:BAAALgAECgcJBQAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAAALgAECgYJCAAAAA==.Desso:BAAALgAECgYJDwAAAA==.',
Di='Dihhdevil:BAAALgAECgEJAgAAAA==.Dillinger:BAAALgAECgUJCgAAAA==.Dingodgaf:BAAALgAECgYJCwAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAAALgAECgUJCwAAAA==.',
Dr='Draknarok:BAAALgAECgYJCgAAAA==.Dranius:BAABLgAECn8WAAINAAcJFBQ1iQDAAQANAAcJFBQ1iQDAAQAAAA==.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAAALgAECgMJAwAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAABLgAECn8ZAAIQAAgJPhQFEgCAAQAQAAgJPhQFEgCAAQAAAA==.Driztette:BAAALgAECgQJBQAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgAAAA==.Drystine:BAAALgAECgYJEQAAAA==.',
Ee='Eedeeweewee:BAAALgADCgUJDQAAAA==.Eevee:BAAALgAECgQJBAAAAA==.',
Ei='Eillaura:BAAALgAECggJDQAAAA==.',
El='Elipsis:BAABLgAECn8WAAICAAgJ6AxZLACVAQACAAgJ6AxZLACVAQAAAA==.Elm:BAAALgAECgYJEwAAAA==.Elybella:BAABLgAECn8WAAIBAAgJ7xIHLwD1AQABAAgJ7xIHLwD1AQAAAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emmental:BAAALgAECgYJCgAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJCAAAAA==.Enricco:BAAALgAECgYJBgAAAA==.',
Er='Ereko:BAAALgAECgYJDAAAAA==.Erythorbic:BAAALgAECgYJEgAAAA==.',
Es='Estralage:BAAALgAECgQJBQAAAA==.',
Ev='Evictor:BAAALgADCgUJBQABLgAECgYJCgAIAAAAAA==.',
Ex='Exileelfsam:BAAALgAECgcJEQAAAA==.',
Fa='Fallensk:BAAALgADCgIJAgAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgADCgUJBQAAAA==.Fatherrick:BAAALgAECgIJAgAAAA==.Faîle:BAACLgAFFH8NAAIRAAQJmw1fCgA5AQARAAQJmw1fCgA5AQAuAAQKfygAAxEACAkrHyEIAL0CABEACAkrHyEIAL0CAAIABgkhCB9KABABAAAA.',
Fe='Feer:BAAALgAECgEJAQAAAA==.Feldron:BAABLgAECn8bAAMSAAkJZB2+CgDmAgASAAgJFx6+CgDmAgATAAEJgxjsHQA9AAAAAA==.Felshatter:BAAALgAECgUJCQAAAA==.Feltigress:BAABLgAECn8YAAIUAAcJaRvTCQAzAgAUAAcJaRvTCQAzAgAAAA==.Fendag:BAAALgADCgEJAQAAAA==.',
Ff='Ffugme:BAAALgAECgYJDgAAAA==.Ffugtard:BAAALgAECgQJBAAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAAAAA==.Finnian:BAAALgAECgYJEAAAAA==.Fio:BAABLgAECn8eAAMVAAgJ9ySxAgBcAwAVAAgJ9ySxAgBcAwAMAAEJQxsscABRAAAAAA==.Firiona:BAAALgAECgQJBQAAAA==.',
Fl='Flashferment:BAAALgAECgcJEQAAAA==.Flinn:BAAALgAECgYJEwAAAA==.Flowers:BAABLgAECn8VAAIEAAYJZhrdUQCvAQAEAAYJZhrdUQCvAQAAAA==.Fläva:BAAALgAECgUJCwAAAA==.',
Fr='Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8YAAINAAcJbxP0fgDTAQANAAcJbxP0fgDTAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDwAIAAAAAA==.',
Ga='Gafocalypse:BAAALgAECgMJAwAAAA==.Garddidit:BAAALgADCgUJBQABLgAECgYJFAAFAGwZAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgUJDQAAAA==.Grotok:BAAALgAECggJEwAAAA==.',
Gu='Guacamole:BAAALgADCgEJAQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJBwAAAA==.Hasklaufien:BAAALgAECgIJAgAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgADCgMJAwAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgADCgYJCwAAAA==.',
Hu='Hugulin:BAAALgAECgYJEgAAAA==.',
Ic='Icedsoul:BAAALgAECgMJBAAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8XAAIPAAcJlhRfBQA4AQAPAAcJlhRfBQA4AQAAAA==.',
Ik='Ikkaku:BAAALgADCggJEQAAAA==.',
Il='Ilandras:BAAALgAECgYJDwAAAA==.Illadus:BAAALgADCggJEgAAAA==.Illed:BAAALgADCgcJBwAAAA==.Illusorybias:BAAALgAECgkJCAAAAA==.',
In='Indra:BAAALgAECgUJBgAAAA==.Intoxicated:BAAALgAECgQJBwAAAA==.',
Io='Ione:BAAALgADCgIJAgAAAA==.',
Ir='Iranna:BAACLgAFFH8KAAIWAAQJFhq1AAARAQAWAAQJFhq1AAARAQAuAAQKfxcAAhYACAlFI0YBAN8CABYACAlFI0YBAN8CAAAA.Irondihh:BAAALgADCgQJAwAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECgcJCwAIAAAAAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgYJFQAJAM0cAA==.Janaki:BAAALgAECgQJBgAAAA==.',
Jo='Joenutter:BAAALgAECgEJAQAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn8ZAAILAAgJkxBZWgDUAQALAAgJkxBZWgDUAQAAAA==.',
Ju='Juicie:BAAALgAECgQJBQAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJCwAXAN8VAA==.Junrush:BAAALgAECggJCwABLgAFFAUJCwAXAN8VAA==.',
['Jè']='Jèstèr:BAAALgADCgkJCQABLgAFFAQJDQARAJsNAA==.',
Ka='Kalea:BAAALgAECgEJAQAAAA==.Kalecgo:BAAALgAECgIJAgABLgAECgYJCAAIAAAAAA==.Kat:BAAALgAECgcJBwAAAA==.Katsuko:BAAALgAECgYJEAAAAA==.Kattnirra:BAAALgAECgYJEwAAAA==.Katze:BAABLgAECn8oAAIBAAcJhRNwSQCNAQABAAcJhRNwSQCNAQAAAA==.Kaylé:BAAALgAECgIJAgAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keepper:BAABLgAECn8fAAIQAAcJmhHQHQAuAQAQAAcJmhHQHQAuAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8VAAICAAcJuhDVCgBKAQACAAcJuhDVCgBKAQAAAA==.Ketheric:BAAALgADCgkJFgAAAA==.',
Ki='Killahaseo:BAAALgADCgkJDgABLgAECgYJCwAIAAAAAA==.Killmoedee:BAABLgAECn8VAAIYAAYJbyAQAwCqAQAYAAYJbyAQAwCqAQAAAA==.',
Kk='Kkaell:BAAALgAECgQJBQABLgAECgUJBAAIAAAAAA==.',
Kl='Klexios:BAAALgAECgEJAgAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgADCgYJCQAAAA==.',
Kr='Kracious:BAAALgAECgIJAgAAAA==.Krymson:BAAALgAECgEJAQAAAA==.',
Ku='Kui:BAAALgAECgYJEAAAAA==.',
['Kö']='Köz:BAAALgADCgkJDAAAAA==.',
La='Laetri:BAABLgAECn8UAAIEAAcJxBQ7VACnAQAEAAcJxBQ7VACnAQAAAA==.Lasttok:BAAALgAECgYJCAAAAA==.Laylene:BAAALgAECgQJCwAAAA==.Lazloo:BAAALgAECgYJDQAAAA==.Lazymidget:BAABLgAECn8eAAIGAAcJFh2zLQDAAQAGAAcJFh2zLQDAAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgADCgYJEgABLgAECggJIAAHAMMVAA==.Legindkiller:BAAALgADCgUJDQAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAYJFQAZAFEiAA==.',
Li='Lightace:BAAALgAECgUJBQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAAALgAECgYJCwAAAA==.Lithice:BAAALgAECgMJAwAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAAALgAECgYJCgAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAAALgAECgMJAwAAAA==.Lostdream:BAAALgAECgIJAwAAAA==.Loun:BAAALgAECgYJDAAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCgUJDQAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECgYJCwAIAAAAAA==.Luvlycruelty:BAAALgADCgUJBwAAAA==.',
Ly='Lyn:BAEBLgAECn8XAAIaAAgJpiMFBgAnAwAaAAgJpiMFBgAnAwAAAA==.',
Ma='Mackalroy:BAAALgAECggJAQAAAA==.Mackenziiee:BAABLgAECn8eAAIBAAgJtxOCKAAVAgABAAgJtxOCKAAVAgAAAA==.Mackthyra:BAAALgADCgcJBwAAAA==.Madglowup:BAAALgAECgQJBAAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8ZAAINAAYJlCI2VwAzAgANAAYJlCI2VwAzAgAAAA==.Magtaki:BAAALgAECgkJAgAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Maizepriest:BAAALgAECgYJDwAAAA==.Mannysaf:BAAALgAECgYJCgAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwAAAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Mellowblink:BAABLgAECn8XAAINAAYJbxQaLAAbAQANAAYJbxQaLAAbAQAAAA==.Mellowlink:BAAALgAECgYJEwAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECgYJCAAAAA==.Menara:BAAALgAECgQJBgAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgEJAQAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8XAAMGAAgJqyAcAAAiAgAGAAgJqyAcAAAiAgABAAEJAADMGQAAAAAuAAQKfyoABAYACQmCJusDAGQDAAYACAkCJusDAGQDAAcABAnSJdgXAE4BAAEAAQmiJlSoAHUAAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECggJGwASAHgUAA==.Miravus:BAABLgAECn8bAAMSAAgJeBQMHgANAgASAAgJeBQMHgANAgATAAQJcAx/BAAHAQAAAA==.Mirlanda:BAAALgAECgQJBQAAAA==.Misttie:BAAALgAECggJDwABLgAECggJFgACAOgMAA==.',
Mo='Moonana:BAAALgADCgIJAgAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgUJDQAAAA==.',
Mu='Murkoobi:BAAALgAECgEJAQAAAA==.Mursk:BAAALgAECgEJAQAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystáke:BAAALgAECgYJDAAAAA==.',
['Mä']='Mäble:BAAALgADCgYJBwAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwAAAA==.',
['Mó']='Móus:BAAALgADCggJEAABLgAECgYJEwAIAAAAAA==.',
Na='Narcissus:BAAALgADCgUJDQAAAA==.Naro:BAAALgADCgkJDAAAAA==.Nathadon:BAAALgADCgYJBgAAAA==.Nathalin:BAAALgAECgQJCQAAAA==.',
Ne='Necrotis:BAAALgADCgUJDQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn8ZAAMCAAgJQCNYAAAnAwACAAgJQCNYAAAnAwADAAUJKxj9NgA1AQAAAA==.Nezukô:BAAALgAECgYJAwAAAA==.',
Ni='Nitalan:BAAALgADCggJGQAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgIJAwAAAA==.Noraldrys:BAAALgADCgcJBwAAAA==.Noralyne:BAAALgAECgQJAwAAAA==.Noras:BAAALgAECgYJCgAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAAALgAECgYJEgAAAA==.',
Ob='Obnyxion:BAABLgAECn8eAAIbAAkJYwvNAQCYAQAbAAkJYwvNAQCYAQAAAA==.',
Oc='Octuroun:BAAALgAECgIJAgAAAA==.',
Od='Oddsoul:BAAALgAECgIJAgAAAA==.',
Og='Ogrelurd:BAAALgAECgQJBwAAAA==.',
Ol='Oliveia:BAAALgADCgYJCQAAAA==.',
Om='Omontanha:BAAALgAECgEJAQAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAABLgAECn8cAAQQAAgJnRykDgCdAQAQAAYJ9hykDgCdAQAcAAMJlBveEwDyAAAdAAEJpgiIdAAwAAAAAA==.',
Or='Orakwa:BAAALgAECgIJAwAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Pallinda:BAABLgAECn8VAAMLAAYJkBQjhgBuAQALAAYJkBQjhgBuAQAeAAYJkQ8JDgBfAQAAAA==.Panakananama:BAAALgAECgEJAQAAAA==.Panz:BAAALgAECgYJCwAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papiperkins:BAAALgADCggJCAAAAA==.Pappyoblues:BAAALgAECgEJAQAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgADCgYJCwAAAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgEJAgAAAA==.Pennypacker:BAAALgAECgIJAgAAAA==.Petmycat:BAAALgAECgQJBQAAAA==.',
Ph='Phara:BAAALgAECgcJDwAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoopanchu:BAAALgAECgYJEQAAAA==.',
Pi='Pinkbuns:BAAALgAECgYJDwAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAAALgAECgUJCgAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Popsy:BAAALgAECgUJDAAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAAALgAECgYJEwAAAA==.Pretzel:BAAALgADCgUJBQABLgAECgkJGwAJAP4iAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAABLgAECn8VAAIQAAYJKwsbHwAmAQAQAAYJKwsbHwAmAQAAAA==.Profundity:BAAALgAECgMJBgAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8VAAIJAAYJzRyeDQCvAQAJAAYJzRyeDQCvAQAAAA==.',
Qe='Qeini:BAABLgAECn8WAAIRAAYJaxqcBgCQAQARAAYJaxqcBgCQAQAAAA==.',
Ra='Radrin:BAAALgADCgkJCQAAAA==.Rafoff:BAAALgAECgIJAgAAAA==.Rahll:BAAALgADCgUJDQAAAA==.Rancoramble:BAAALgAECgYJEgAAAA==.Randis:BAAALgAECgYJEwAAAA==.Ranekk:BAAALgADCgcJFgAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJBQAAAA==.Razonghoul:BAABLgAECn8eAAIJAAcJnRxxDwCbAQAJAAcJnRxxDwCbAQAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAQAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgIJBQAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAAALgAECgEJAQAAAA==.Rexiis:BAABLgAECn8UAAMQAAYJrBEPGgBEAQAQAAYJrBEPGgBEAQAcAAEJAABcNAAzAAAAAA==.Reyth:BAAALgAECgIJAgAAAA==.',
Rh='Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAAALgAECgcJEwAAAA==.',
Ri='Rimos:BAAALgADCgUJBQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn8VAAIfAAYJ1woVEgDxAAAfAAYJ1woVEgDxAAAAAA==.',
Ro='Rockadin:BAAALgAECgYJDAAAAA==.Rosael:BAAALgADCgYJBgAAAA==.',
Ru='Rubbmytotems:BAAALgAECgMJAwAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAAALgAECgYJEwAAAA==.Rumí:BAABLgAECn8bAAIEAAgJzgcFHwARAQAEAAgJzgcFHwARAQAAAA==.Russell:BAAALgADCgUJDQAAAA==.Rutgore:BAAALgAFFAEJAQAAAA==.',
Rx='Rx:BAAALgADCgcJBwAAAA==.',
Sa='Sabado:BAAALgAECgIJAgAAAA==.Safewerd:BAEALgAECgYJCwAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgADCgMJBAAAAA==.Sarahfi:BAAALgAECgEJAQAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAAALgAECgQJBgAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgUJBgAAAA==.Sathenazarke:BAABLgAECn8nAAQgAAgJnRjNEQAhAgAgAAcJWhrNEQAhAgAhAAcJ0hqDBwB3AQAbAAEJKwjwQgApAAABLgAFFAQJCgAWABYaAA==.Saths:BAAALgADCgEJAQABLgAECggJEwAIAAAAAA==.',
Sc='Schallue:BAAALgAECgYJCwAAAA==.Schism:BAAALgADCgYJDAAAAA==.Scoban:BAACLgAFFH8OAAIeAAUJbx0DAQDJAQAeAAUJbx0DAQDJAQAuAAQKfyoAAh4ACAl4IXYDAE0CAB4ACAl4IXYDAE0CAAAA.Scylla:BAAALgAECgUJBgAAAA==.',
Se='Selithel:BAAALgAECgYJDwAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgYJEAAIAAAAAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAAALgAECgUJCAAAAA==.Shaeliana:BAAALgAECgQJCgAAAA==.Shaqfu:BAAALgADCgUJDQAAAA==.Shavemybush:BAAALgADCgcJCwAAAA==.Shigure:BAAALgAECgYJBgAAAA==.Shivers:BAAALgADCgIJAgAAAA==.Shnow:BAAALgAECggJEwAAAA==.Sholin:BAAALgAECgYJDAAAAA==.Shomea:BAAALgAECgEJAgAAAA==.Shugz:BAAALgADCgUJDQAAAA==.',
Si='Sikotick:BAAALgAECgYJEQAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAABLgAECn8nAAINAAgJZiDoCQAMAgANAAgJZiDoCQAMAgAAAA==.Silverbolt:BAAALgAECgYJBwAAAA==.Simbelmyne:BAAALgADCgMJAwAAAA==.Sinderone:BAABLgAECn8rAAMeAAkJgRoyHAA0AgAeAAkJgRoyHAA0AgALAAUJ+BflJQAPAQAAAA==.',
Sk='Skaaduush:BAAALgAECgYJBgAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn8mAAIJAAkJWBwFBgAlAgAJAAkJWBwFBgAlAgAAAA==.Sleepylune:BAAALgAECgEJAgAAAA==.Sllew:BAAALgAECgYJDgAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smoulder:BAAALgAECgEJAQAAAA==.',
Sn='Snigles:BAAALgAECgYJCAAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Souei:BAAALgADCgEJAQABLgAECggJEwAIAAAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgADCgQJBAAAAA==.Sposi:BAEALgAECgYJDwAAAA==.Spraynpray:BAAALgADCgcJBwAAAA==.',
Sr='Srimrithyu:BAAALgADCgcJBwAAAA==.',
Ss='Sselionn:BAAALgAECgQJDQAAAA==.',
St='Stabathaa:BAAALgAECgQJBAAAAA==.',
Su='Subliminal:BAABLgAECn8VAAMSAAgJ6xEXBgCMAQASAAgJ6xEXBgCMAQAWAAEJ9wvPBQA+AAAAAA==.',
Sv='Svartalfar:BAAALgADCgEJAQAAAA==.',
Sy='Syravia:BAAALgAECgQJBwAAAA==.',
['Sé']='Séraphyne:BAAALgAECgIJAgAAAA==.',
Ta='Talarin:BAAALgAECgMJAwAAAA==.Tameka:BAAALgAECgEJAQAAAA==.Tatersmonk:BAEBLgAECn8aAAIaAAkJKiS6AwBUAwAaAAkJKiS6AwBUAwAAAA==.Tavinrayn:BAAALgADCgUJCgAAAA==.Tazzar:BAAALgAECgYJEAAAAA==.',
Td='Tdjin:BAAALgAECgMJAwAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECgYJEwAIAAAAAA==.Tekêsh:BAAALgAECgYJCgAAAA==.Telarin:BAABLgAECn8UAAMBAAYJ3xrGTQB/AQABAAYJ3xrGTQB/AQAHAAIJUQW9FAA6AAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.Teriss:BAAALgADCgMJAwAAAA==.',
Th='Thandor:BAAALgAECgEJAgAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECgcJDQAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgADCgQJBAAAAA==.',
Ti='Tiamut:BAAALgADCgQJBAAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgIJAgABLgAECgYJEgAIAAAAAA==.',
To='Tomás:BAAALgAECgYJBwAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8LAAIiAAQJIhlCAgA+AQAiAAQJIhlCAgA+AQAuAAQKfx8AAiIACQm0IBEDADEDACIACQm0IBEDADEDAAAA.Torstai:BAAALgAECgIJAgAAAA==.',
Tr='Trueshöt:BAAALgAECgQJBwAAAA==.',
Ts='Tserendolgor:BAAALgAECgQJDwAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECgcJEwAIAAAAAA==.Twinsha:BAAALgAECgcJEwAAAA==.Twín:BAAALgADCgYJCAABLgAECgcJEwAIAAAAAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyresious:BAAALgAECgUJBQAAAA==.',
Un='Unauma:BAAALgAFFAIJAgAAAA==.Unholydk:BAAALgAECgQJBwAAAA==.',
Va='Vaa:BAAALgADCgcJEwAAAA==.Vahaghn:BAABLgAECn8gAAIPAAgJnCAXAgAOAwAPAAgJnCAXAgAOAwAAAA==.Valcerus:BAAALgAECgEJAgAAAA==.Valedus:BAABLgAECn8XAAILAAcJWiJWBQBDAgALAAcJWiJWBQBDAgAAAA==.Validrela:BAAALgADCgIJAgAAAA==.',
Ve='Veelete:BAAALgADCgcJBwABLgAECgcJEgAIAAAAAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECggJGQACAEAjAA==.Vespra:BAABLgAECn8oAAIjAAgJvB2dAgBsAgAjAAgJvB2dAgBsAgAAAA==.',
Vh='Vhas:BAAALgAECgkJBwAAAA==.',
Vi='Viix:BAAALgADCgYJAwABLgAECgYJBgAIAAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgQJBAAAAA==.Volcker:BAAALgAECgYJEwAAAA==.Voltashi:BAABLgAECn8YAAQaAAcJ2BSMCgBGAQAaAAcJ2BSMCgBGAQAVAAIJtwUnYQBLAAAMAAEJBAtmgAAwAAAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgQJAQAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgAAAA==.',
Wa='Wagyuboi:BAAALgADCgcJBwAAAA==.Wallypaly:BAABLgAECn8eAAMLAAgJABPqIAAqAQALAAcJnxTqIAAqAQAYAAUJAQiYKADFAAAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn8UAAIeAAYJWhuXCgCXAQAeAAYJWhuXCgCXAQAAAA==.Warwarb:BAAALgADCgYJCwABLgAECgcJGAAQALAZAA==.Waterliliy:BAAALgAECgYJEgAAAA==.',
Wh='Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgYJAQAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAAALgAECgYJDQAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgADCgQJBAABLgAECggJGQAQAD4UAA==.Xenhaseo:BAAALgAECgYJCwAAAA==.',
Xh='Xhuri:BAAALgAECgEJAQAAAA==.',
Xi='Xilla:BAAALgADCgkJCwAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAAALgAECgQJCAAAAA==.',
Yo='Yorllik:BAAALgADCgcJDQAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8bAAIEAAYJuBcudwBBAQAEAAYJuBcudwBBAQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8iAAIhAAgJch/dAQBMAgAhAAgJch/dAQBMAgAAAA==.Zaiene:BAAALgADCgYJBwABLgAECgQJBgAIAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarulyn:BAAALgAECgQJBAAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAAALgADCggJDQAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAAALgAECgYJEgAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgADCgcJBwAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAAALgAECgYJDwAAAA==.',
['Äc']='Äcid:BAABLgAECn8fAAIjAAgJ2h2AFABxAgAjAAgJ2h2AFABxAgAAAA==.',
['Åp']='Åpollo:BAAALgAECgYJCQAAAA==.',
['Èa']='Èastçoast:BAAALgADCgYJBwAAAA==.',
['Êl']='Êlydala:BAAALgAECgUJBAAAAA==.',
['Ðð']='Ððå:BAAALgADCgEJAQAAAA==.',
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

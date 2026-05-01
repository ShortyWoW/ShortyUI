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

local lookup = {'Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Druid-Restoration','Priest-Shadow','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warrior-Protection','Warrior-Arms','Warlock-Demonology','DemonHunter-Havoc','Druid-Balance','Druid-Guardian','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Paladin-Protection','Monk-Mistweaver','Monk-Brewmaster','Rogue-Outlaw','Warrior-Fury','DeathKnight-Blood','Evoker-Devastation','Warlock-Affliction','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','Shaman-Enhancement',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aakkulay:BAAALgAECgEJAgAAAA==.',
Ab='Absofsteels:BAAALgAECgYJDwAAAA==.',
Ac='Acaric:BAABLgAECn8aAAIBAAgJAwSQYQAZAQABAAgJAwSQYQAZAQAAAA==.Ache:BAAALgAFFAIJAgAAAA==.',
Ad='Adriel:BAAALgAECgYJCQAAAA==.Adrielon:BAAALgADCgYJCgAAAA==.Adøra:BAABLgAECn8ZAAICAAgJRheEIgA2AgACAAgJRheEIgA2AgAAAA==.',
Ae='Aelanesh:BAAALgADCgYJCgAAAA==.',
Ai='Aircann:BAAALgADCgMJAwAAAA==.Aireola:BAAALgADCgUJBQAAAA==.',
Ak='Akairo:BAAALgAECgcJCwABLgAECggJCgADAAAAAA==.Akata:BAAALgAECgYJAgAAAA==.',
Al='Alchemist:BAAALgADCgUJEAAAAA==.Alidor:BAAALgAECgMJBAAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allixis:BAAALgADCgMJAwAAAA==.Alluriel:BAAALgAECgQJBgAAAA==.Altharoth:BAAALgAECgQJCAAAAA==.',
Am='Amira:BAACLgAFFH8KAAIEAAQJMSAZAgCUAQAEAAQJMSAZAgCUAQAuAAQKfxsAAgQACAklJWoCAEUDAAQACAklJWoCAEUDAAAA.Amorillis:BAAALgADCgcJDQAAAA==.Amphitrite:BAAALgADCgEJAQAAAA==.',
An='Anteiku:BAAALgAECgEJAgAAAA==.Anthiva:BAAALgAECgYJDwAAAA==.',
Ar='Arauial:BAAALgAECgYJCgAAAA==.Arcos:BAAALgADCgkJCQAAAA==.Aribella:BAACLgAFFH8FAAICAAMJIQl9HgDgAAACAAMJIQl9HgDgAAAuAAQKfygAAgIACAliGaMSAP0BAAIACAliGaMSAP0BAAAA.Arizann:BAABLgAECn8XAAIFAAYJKSBWDwAbAgAFAAYJKSBWDwAbAgAAAA==.Arobotpr:BAABLgAECn8XAAIGAAcJQxbEDQCoAQAGAAcJQxbEDQCoAQAAAA==.Artpandalay:BAAALgAECgQJBQAAAA==.',
As='Asima:BAAALgAECgEJAQAAAA==.Astaren:BAAALgAECgIJBAAAAA==.Asuran:BAAALgAFFAEJAQAAAA==.',
At='Atem:BAAALgAECgIJAgAAAA==.',
Au='Aulinn:BAAALgAECgEJAQAAAA==.Aurelianus:BAAALgAECgYJEgAAAA==.',
Av='Avalanche:BAAALgAECgQJCAAAAA==.',
Az='Azaris:BAABLgAECn8jAAIGAAgJkRhiCgDaAQAGAAgJkRhiCgDaAQAAAA==.',
Ba='Baelrog:BAAALgAECgQJBgAAAA==.Bananaslamma:BAAALgADCgMJBQAAAA==.Bandalar:BAABLgAECn8dAAMHAAkJvBHlRwDUAQAHAAkJvBHlRwDUAQAIAAIJQwoPGQAwAAAAAA==.Baranina:BAACLgAFFH8NAAMCAAUJvCDLBwAnAQACAAMJVSHLBwAnAQAJAAMJTxwnDQCgAAAuAAQKfycABAkACAnQIxUCAD8CAAkACAkWIhUCAD8CAAIABQmOHwU2ANYBAAoAAwkuIVYbAB8BAAAA.Barricaded:BAAALgAECgYJCAAAAA==.Bashems:BAAALgADCgcJCQABLgAECgMJAwADAAAAAA==.Battosi:BAAALgADCgIJAgAAAA==.',
Be='Bealzebuub:BAAALgADCgMJAwAAAA==.Bearpaws:BAAALgADCgQJBAAAAA==.Beastums:BAABLgAECn8XAAIKAAcJMxi2CgC1AQAKAAcJMxi2CgC1AQAAAA==.Benji:BAEALgAECgQJDwAAAA==.',
Bi='Bigload:BAAALgADCgEJAQAAAA==.Bigunc:BAAALgAECgQJBgAAAA==.Bihgnuts:BAAALgAECgQJBgAAAA==.Bittybubble:BAAALgAECgEJAQAAAA==.',
Bl='Blazinitup:BAAALgADCgQJCQAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blindcauze:BAAALgADCgEJAQAAAA==.Blindmonk:BAABLgAECn8WAAILAAcJjA7KGQAXAQALAAcJjA7KGQAXAQAAAA==.Blite:BAAALgADCgUJEgAAAA==.Bloodlòck:BAAALgADCgUJCgAAAA==.Bloodmary:BAABLgAECn8UAAMMAAgJngMOZADqAAAMAAgJngMOZADqAAANAAQJQAelcgCxAAAAAA==.Bloombriar:BAAALgAECgEJAQAAAA==.Bloöm:BAACLgAFFH8IAAIFAAIJFALzLABeAAAFAAIJFALzLABeAAAuAAQKfxsAAgUACAl5D6waAKoBAAUACAl5D6waAKoBAAAA.Blueeyearch:BAAALgAECgUJCgAAAA==.',
Bo='Bolgan:BAAALgAECgMJAwAAAA==.Bonedecay:BAAALgAECgEJAQAAAA==.Boomadk:BAACLgAFFH8JAAIOAAMJLhSaMgD8AAAOAAMJLhSaMgD8AAAuAAQKfx4AAw4ACAlgIkEfAMYCAA4ACAnaIUEfAMYCAA8ABwmfH9gCAHsCAAAA.Boomapriest:BAAALgAECgYJBwAAAA==.Boosh:BAAALgAECgIJAgAAAA==.Booshler:BAAALgAECgUJCgAAAA==.Booshlia:BAAALgAECggJCgAAAA==.Bowjoemojo:BAAALgADCgIJAgAAAA==.Bowsho:BAAALgAECgQJBQAAAA==.',
Br='Bradburn:BAAALgAECgMJBgAAAA==.Brassybella:BAAALgAECgQJBAAAAA==.Brewswillis:BAAALgADCgYJBgAAAA==.Brice:BAAALgAECgIJBAAAAA==.Briochebun:BAABLgAECn8bAAIMAAgJsB3mIACnAgAMAAgJsB3mIACnAgAAAA==.',
Bu='Bustin:BAAALgAECggJEAAAAA==.',
Bw='Bwangifer:BAABLgAECn8XAAIIAAcJFBRVDQCCAQAIAAcJFBRVDQCCAQAAAA==.',
['Bë']='Bëcky:BAAALgAFFAMJAwAAAA==.',
Ca='Caerus:BAAALgADCgYJDAABLgAECgYJGQACABshAA==.Caitriona:BAAALgADCgMJAwABLgADCgUJBwADAAAAAA==.Cannala:BAAALgADCgUJEgAAAA==.Cargae:BAAALgADCgMJAwAAAA==.Cassios:BAABLgAECn8WAAILAAcJtRUbFABNAQALAAcJtRUbFABNAQAAAA==.',
Ce='Celathel:BAAALgAECgQJBgAAAA==.Cellysia:BAABLgAECn8ZAAMEAAcJsQU8IAAAAQAEAAcJsQU8IAAAAQAGAAYJhQIPKwCoAAAAAA==.Celsìus:BAABLgAECn8XAAIBAAYJbBPEdQDsAAABAAYJbBPEdQDsAAAAAA==.Ceramyth:BAAALgAECgMJBwAAAA==.Ceres:BAABLgAECn8XAAIQAAcJMhRaBQB0AQAQAAcJMhRaBQB0AQAAAA==.Cesara:BAABLgAECn8pAAMGAAgJ8R+aAwB+AgAGAAgJ8R+aAwB+AgAEAAEJ8gccfwAzAAAAAA==.',
Ch='Chaahck:BAAALgADCgkJEgAAAA==.Chal:BAAALgAECgUJBgAAAA==.Chbribs:BAAALgAECgQJCAAAAA==.Chichimounki:BAAALgADCgUJBQAAAA==.Chiptewth:BAAALgADCgEJAQAAAA==.',
Ci='Cinderella:BAABLgAECn8lAAIBAAcJGyCfMwCkAgABAAcJGyCfMwCkAgAAAA==.',
Cl='Clumsey:BAAALgADCgEJAQAAAA==.',
Co='Cocoshan:BAAALgAECgYJDAAAAA==.Columbina:BAACLgAFFH8PAAIHAAUJsA8uGQAOAQAHAAUJsA8uGQAOAQAuAAQKfxoAAgcABwmgGbNEAOEBAAcABwmgGbNEAOEBAAAA.Comma:BAABLgAECn8UAAIRAAcJFRKuHABjAQARAAcJFRKuHABjAQAAAA==.Cooperhowerd:BAAALgADCgUJEgAAAA==.Corn:BAAALgAECgUJDAAAAA==.Couremese:BAAALgADCgYJBgAAAA==.',
Cr='Crackmonger:BAABLgAECn8wAAMSAAgJXSAPAgBuAgASAAgJXSAPAgBuAgARAAIJGxCpIQBsAAAAAA==.Cravens:BAAALgADCgcJCgAAAA==.Craze:BAAALgADCgUJBQAAAA==.',
Cy='Cyphr:BAABLgAECn8XAAIFAAcJER5jJAAoAgAFAAcJER5jJAAoAgAAAA==.',
['Cë']='Cërbërus:BAAALgAECgQJBQAAAA==.',
Da='Dacs:BAAALgAECgQJCwAAAA==.Daen:BAAALgADCgcJCgAAAA==.Daggergarnet:BAAALgADCgYJBgAAAA==.Dajango:BAAALgAECgYJCAAAAA==.Damerot:BAAALgAFFAEJAQAAAA==.Dandity:BAAALgAECgMJBQAAAA==.Dangerous:BAAALgADCgcJCQAAAA==.Dangi:BAAALgADCgMJAwAAAA==.Dansharo:BAAALgAECgEJAQAAAA==.Darnel:BAAALgADCgQJBAAAAA==.',
De='Deadbeard:BAAALgAFFAIJAgAAAA==.Deathknut:BAAALgADCggJCQAAAA==.Deathmethods:BAAALgAECgYJCQAAAA==.Deathviix:BAAALgADCgIJAgAAAA==.Dekillerty:BAAALgADCgYJCQAAAA==.Deli:BAAALgAECggJBQAAAA==.Delphina:BAAALgADCgQJAwAAAA==.Demini:BAAALgADCgcJDgAAAA==.Demisê:BAAALgAECgcJEwAAAA==.Demonessa:BAAALgAECgcJCgAAAA==.Dermus:BAAALgADCgEJAQAAAA==.Deserter:BAAALgAECgcJEQAAAA==.Desso:BAABLgAECn8WAAILAAYJxBFZGQAbAQALAAYJxBFZGQAbAQAAAA==.Devilskin:BAAALgAECgIJAgAAAA==.',
Di='Dihhdevil:BAAALgAECgIJBAAAAA==.Dillinger:BAAALgAECgYJEAAAAA==.Dingodgaf:BAAALgAECgYJDwAAAA==.',
Do='Doomsdae:BAAALgAECgQJCgAAAA==.Doomstir:BAABLgAECn8WAAIBAAYJKA8EVQA2AQABAAYJKA8EVQA2AQAAAA==.',
Dr='Draknarok:BAAALgAECggJDgAAAA==.Dranius:BAABLgAECn8WAAIBAAcJFBQkiQDAAQABAAcJFBQkiQDAAQAAAA==.Drayeda:BAAALgADCgMJAwAAAA==.Dreadlord:BAAALgADCgEJAQAAAA==.Dreamclaw:BAAALgAECgQJBgAAAA==.Dredda:BAAALgADCgEJAQAAAA==.Drendar:BAAALgADCgUJBQAAAA==.Drippindots:BAABLgAECn8bAAITAAgJgxheFAACAgATAAgJgxheFAACAgAAAA==.Driztette:BAAALgAECgUJCgAAAA==.Drnewport:BAAALgADCgkJDwAAAA==.Drock:BAAALgADCgIJAgAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Drustor:BAAALgAECgYJBgAAAA==.Drystine:BAABLgAECn8ZAAIUAAgJHh0IBABIAgAUAAgJHh0IBABIAgAAAA==.',
Du='Dubber:BAAALgADCgUJBQAAAA==.',
Ed='Edd:BAAALgADCgYJBgAAAA==.',
Ee='Eedeeweewee:BAAALgADCgUJDQAAAA==.Eevee:BAAALgAECgYJCgAAAA==.',
Ei='Eillaura:BAABLgAECn8WAAIEAAgJ7BAKDgDCAQAEAAgJ7BAKDgDCAQAAAA==.',
El='Elipsis:BAABLgAECn8ZAAIEAAgJuRFVLACVAQAEAAgJuRFVLACVAQAAAA==.Elm:BAABLgAECn8bAAQFAAgJHBY1GgCuAQAFAAgJHBY1GgCuAQAVAAQJ+hPeUgDbAAAWAAEJ5BNcLwA4AAAAAA==.Elyas:BAAALgADCgEJAQAAAA==.Elybella:BAABLgAECn8ZAAICAAgJaRUCLwD1AQACAAgJaRUCLwD1AQAAAA==.',
Em='Emanon:BAAALgAECgQJBQAAAA==.Emmental:BAAALgAECgYJEQAAAA==.',
En='Endload:BAAALgADCgEJAQAAAA==.Enquea:BAAALgAECgYJDAAAAA==.Enricco:BAAALgAECgYJBgAAAA==.',
Er='Ereko:BAAALgAECgYJEQAAAA==.Erythorbic:BAABLgAECn8YAAMTAAYJxSBnHgC+AQATAAUJ5R5nHgC+AQAQAAMJPyCiLwD8AAAAAA==.',
Es='Estralage:BAAALgAECgQJBQAAAA==.',
Ev='Evictor:BAAALgAECgQJBAABLgAECgcJCwADAAAAAA==.',
Ex='Exileelfsam:BAABLgAECn8YAAIKAAcJBggOEABeAQAKAAcJBggOEABeAQAAAA==.',
Fa='Fallensk:BAAALgADCgIJAgAAAA==.Fargenstines:BAAALgADCgMJAwAAAA==.Fatass:BAAALgADCgUJBgAAAA==.Fatherrick:BAAALgAECgQJBAAAAA==.Faîle:BAACLgAFFH8SAAIXAAUJaRE1BgCwAQAXAAUJaRE1BgCwAQAuAAQKfyoAAxcACAlEHycIAL0CABcACAlEHycIAL0CAAQABgkhCCRKABABAAAA.',
Fe='Feer:BAAALgAECgIJAwAAAA==.Feldron:BAABLgAECn8cAAMYAAkJZB2+CgDmAgAYAAgJFx6+CgDmAgAZAAEJgxjwHQA9AAAAAA==.Felshatter:BAAALgAECgYJCwAAAA==.Feltigress:BAABLgAECn8gAAIaAAgJgRyGAgBEAgAaAAgJgRyGAgBEAgAAAA==.Fendag:BAAALgADCgYJBAAAAA==.',
Ff='Ffugme:BAABLgAECn8UAAIbAAYJuA2UIAADAQAbAAYJuA2UIAADAQAAAA==.Ffugtard:BAAALgAECgQJCQAAAA==.Ffugyou:BAAALgADCgQJBAAAAA==.',
Fi='Fingerfister:BAAALgAECgQJBAAAAA==.Finnian:BAABLgAECn8XAAINAAcJixg8GgB6AQANAAcJixg8GgB6AQAAAA==.Fio:BAABLgAECn8jAAMcAAgJ9yS0AgBaAwAcAAgJ9yS0AgBaAwALAAEJQxs3cABRAAAAAA==.Firiona:BAAALgAECgYJCgAAAA==.',
Fl='Flashferment:BAABLgAECn8ZAAIdAAgJyRdTDADEAQAdAAgJyRdTDADEAQAAAA==.Flinn:BAABLgAECn8WAAIWAAgJ9h2YAgA4AgAWAAgJ9h2YAgA4AgAAAA==.Flowers:BAABLgAECn8dAAIHAAgJuBckEQDlAQAHAAgJuBckEQDlAQAAAA==.Fläva:BAAALgAECgUJCwAAAA==.',
Fr='Fresca:BAAALgADCgEJAQAAAA==.Fridgerollin:BAAALgADCggJFgAAAA==.Frifrah:BAAALgAECgMJBAAAAA==.Frosht:BAABLgAECn8gAAIBAAgJehVCKADEAQABAAgJehVCKADEAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQAAAA==.',
Ga='Gafocalypse:BAAALgAECgUJBwAAAA==.Garddidit:BAAALgADCgUJBQABLgAECgYJFAAIAGwZAA==.',
Gl='Glonor:BAAALgAECgQJBgAAAA==.',
Go='Goldberg:BAAALgADCgYJBgAAAA==.Goopmaster:BAAALgADCgUJBQAAAA==.',
Gr='Grabmytusk:BAAALgADCgcJBwAAAA==.Gramthyr:BAAALgADCgUJEgAAAA==.Grotok:BAAALgAECggJEwAAAA==.',
Gu='Guacamole:BAAALgAECgUJBQAAAA==.Gub:BAAALgAECgMJAwAAAA==.Gumer:BAAALgAECgYJBwAAAA==.',
Ha='Halraku:BAAALgADCgEJAQAAAA==.Halsin:BAAALgADCgQJBAAAAA==.Halygos:BAAALgAECgYJCAAAAA==.Hasklaufien:BAAALgAECgIJAgAAAA==.',
He='Herpecluster:BAAALgAECgcJBgAAAA==.',
Hi='Hinderberg:BAAALgADCgMJAwAAAA==.',
Ho='Holyraz:BAAALgADCgMJAwAAAA==.Holystrikes:BAAALgADCgYJCwAAAA==.',
Hu='Hugulin:BAABLgAECn8YAAICAAcJ3QYpRAAHAQACAAcJ3QYpRAAHAQAAAA==.',
Ic='Icedsoul:BAAALgAECgUJCQAAAA==.Icee:BAAALgADCgcJCgAAAA==.',
Ig='Iggey:BAABLgAECn8eAAISAAcJbBzQAwASAgASAAcJbBzQAwASAgAAAA==.',
Ik='Ikkaku:BAAALgADCggJEQAAAA==.',
Il='Ilandras:BAABLgAECn8VAAIHAAYJLQ4dNgAKAQAHAAYJLQ4dNgAKAQAAAA==.Illadus:BAAALgAECgcJCAAAAA==.Illed:BAAALgADCgcJBwAAAA==.Illusorybias:BAAALgAECgkJCAAAAA==.',
In='Indra:BAAALgAECgUJBgAAAA==.Intoxicated:BAAALgAECgUJDQAAAA==.',
Io='Ione:BAAALgADCgcJAgAAAA==.',
Ir='Iranna:BAACLgAFFH8PAAMZAAQJNxx3AQBlAQAZAAQJrBN3AQBlAQAeAAQJFhrbAAASAQAuAAQKfx4AAx4ACAmGI0YBAN8CAB4ACAlxI0YBAN8CABkAAgl9EE8QAGEAAAAA.Irondihh:BAAALgADCgQJBAAAAA==.',
Iu='Iudi:BAAALgAECgQJBAABLgAECggJCgADAAAAAA==.',
Iy='Iyasu:BAAALgADCgQJBAAAAA==.',
Ja='Jachan:BAAALgADCgkJDwAAAA==.Jackblãck:BAAALgAECgQJBQABLgAECgcJGwAOAOEfAA==.Janaki:BAAALgAECggJDAAAAA==.',
Jo='Joenutter:BAAALgAECgIJAwAAAA==.Joia:BAAALgADCgQJBAAAAA==.Jonnyquestt:BAABLgAECn8hAAIMAAgJkxDEOgBaAQAMAAgJkxDEOgBaAQAAAA==.',
Ju='Juicie:BAAALgAECgQJBQAAAA==.Junrage:BAAALgADCgMJAwABLgAFFAUJEAAfAAYXAA==.Junrush:BAAALgAECggJDgABLgAFFAUJEAAfAAYXAA==.',
['Jè']='Jèstèr:BAAALgADCgkJCQABLgAFFAUJEgAXAGkRAA==.',
Ka='Kalea:BAAALgAECgEJAQAAAA==.Kalecgo:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.Kanaezz:BAAALgADCggJCAAAAA==.Kat:BAAALgAECggJDQAAAA==.Katsuko:BAABLgAECn8XAAIgAAcJ2RS2CgBmAQAgAAcJ2RS2CgBmAQAAAA==.Kattnirra:BAABLgAECn8UAAICAAYJKgsYXwBKAQACAAYJKgsYXwBKAQAAAA==.Katze:BAABLgAECn8pAAICAAcJtRNoSQCNAQACAAcJtRNoSQCNAQAAAA==.Kaylé:BAAALgAECgMJAwAAAA==.',
Ke='Keannor:BAAALgADCgMJAwAAAA==.Keco:BAAALgADCgYJBgAAAA==.Keepper:BAABLgAECn8fAAITAAcJmhGOZgCYAQATAAcJmhGOZgCYAQAAAA==.Kelaatun:BAAALgAECgEJAgAAAA==.Kennan:BAAALgADCgIJAgAAAA==.Kenslynn:BAABLgAECn8VAAIEAAcJuhDqGABCAQAEAAcJuhDqGABCAQAAAA==.Ketheric:BAAALgAECgMJAwAAAA==.',
Ki='Killahaseo:BAAALgADCgkJDgABLgAECgYJEQADAAAAAA==.Killmoedee:BAABLgAECn8cAAIbAAcJ0yArAwA4AgAbAAcJ0yArAwA4AgAAAA==.Kitwryn:BAAALgADCgUJBQAAAA==.',
Kk='Kkaell:BAAALgAECgQJBQABLgAECgUJBAADAAAAAA==.',
Kl='Klexios:BAAALgAECgIJBAAAAA==.',
Ko='Koopa:BAAALgAECgQJBQAAAA==.Korbandallas:BAAALgAECgEJAQAAAA==.',
Kr='Kracious:BAAALgAECgQJBAAAAA==.Krymson:BAAALgAECgEJAQAAAA==.',
Ku='Kui:BAABLgAECn8XAAIdAAcJ+RfEDAC+AQAdAAcJ+RfEDAC+AQAAAA==.',
['Kö']='Köz:BAAALgADCgkJDAAAAA==.',
La='Laetri:BAABLgAECn8XAAIHAAcJxBQ8VACnAQAHAAcJxBQ8VACnAQAAAA==.Lasttok:BAAALgAECgYJDAAAAA==.Laylene:BAAALgAECgQJCwAAAA==.Lazloo:BAABLgAECn8UAAMSAAcJkiHXBwCRAQAfAAUJCyShLwDxAQASAAYJ6BrXBwCRAQAAAA==.Lazymidget:BAABLgAECn8eAAIJAAcJFh23LQDAAQAJAAcJFh23LQDAAQAAAA==.',
Le='Leaana:BAAALgADCgUJBQAAAA==.Leftÿ:BAAALgADCgYJEgABLgAECgkJKQAKAAIUAA==.Legindkiller:BAAALgADCgUJEgAAAA==.Lenie:BAAALgADCgYJBgABLgAFFAYJFgAFAFEiAA==.',
Li='Lightace:BAAALgAECgUJCQAAAA==.Lilyia:BAAALgADCgcJDAAAAA==.Linkkil:BAAALgAECgYJDAAAAA==.Lithice:BAAALgAECgMJAwAAAA==.',
Lo='Loastotem:BAAALgADCgcJBwAAAA==.Lobos:BAABLgAECn8UAAITAAYJgQXDtADvAAATAAYJgQXDtADvAAAAAA==.Lokni:BAAALgAECgYJBwAAAA==.Lostdraco:BAAALgAECgQJBQAAAA==.Lostdream:BAAALgAECgQJBQAAAA==.Loun:BAAALgAECgYJEwAAAA==.Lowku:BAAALgAECgEJAQAAAA==.Lowrise:BAAALgADCgkJCgAAAA==.',
Lu='Luciellia:BAAALgAECgEJAQAAAA==.Luiss:BAAALgAECgMJAwAAAA==.Luken:BAAALgADCgUJEgAAAA==.Luminara:BAAALgADCgcJDAAAAA==.Luminism:BAAALgADCgYJCAABLgAECgYJDwADAAAAAA==.Luvlycruelty:BAAALgADCgUJBwAAAA==.',
Ly='Lyn:BAEBLgAECn8iAAIdAAkJkSVTAABeAwAdAAkJkSVTAABeAwAAAA==.',
Ma='Mackalroy:BAAALgAECggJAQAAAA==.Mackenziiee:BAABLgAECn8lAAICAAgJMhjiEwDzAQACAAgJMhjiEwDzAQAAAA==.Mackthyra:BAAALgADCgcJBwAAAA==.Madglowup:BAAALgAECgUJBQAAAA==.Magicbunga:BAAALgADCgIJAgAAAA==.Magicwater:BAABLgAECn8dAAIBAAgJMh17FgAoAgABAAgJMh17FgAoAgAAAA==.Magtaki:BAAALgAECgkJBwAAAA==.Magyar:BAAALgAECgUJBQAAAA==.Maizepriest:BAABLgAECn8VAAIGAAYJziAzCgDeAQAGAAYJziAzCgDeAQAAAA==.Mannysaf:BAAALgAECgcJEQAAAA==.Manter:BAAALgADCgIJAgAAAA==.Mariota:BAAALgAECgQJAwAAAA==.Marus:BAAALgADCgMJAwAAAA==.',
Me='Mechalia:BAAALgADCgQJBAAAAA==.Mellowblink:BAABLgAECn8aAAIBAAcJpxIjaAAKAQABAAcJpxIjaAAKAQAAAA==.Mellowlink:BAABLgAECn8ZAAIYAAcJzhL2DQCMAQAYAAcJzhL2DQCMAQAAAA==.Melorian:BAAALgADCgkJEAAAAA==.Memeñtomori:BAAALgAECgYJCAAAAA==.Menara:BAAALgAECgQJBgAAAA==.Metaviix:BAAALgAECgQJBAAAAA==.',
Mi='Midnightmage:BAAALgAECgUJBgAAAA==.Migglet:BAAALgAECgIJAgAAAA==.Millhi:BAAALgAECgcJBwAAAA==.Mimi:BAACLgAFFH8bAAQJAAgJ5yE9AQCJAgAJAAgJqyA9AQCJAgAKAAMJmiPfCwDaAAACAAIJkSQMMgBvAAAuAAQKfzIABAkACQmDJusDAGQDAAkACAkCJusDAGQDAAoABwm/JQYCAJ4CAAIAAgksJUF0AGkAAAAA.Mintyice:BAAALgAECgcJBgAAAA==.Miramage:BAAALgAECgQJCQABLgAECggJKgAYAOUXAA==.Miravus:BAABLgAECn8qAAMYAAgJ5Re0CgC+AQAYAAgJMRe0CgC+AQAZAAUJSxIMBgBWAQAAAA==.Mirlanda:BAAALgAECgUJCgAAAA==.Misttie:BAAALgAECggJDwABLgAECggJGQAEALkRAA==.',
Mo='Monkerick:BAAALgAECgQJBAAAAA==.Moonana:BAAALgADCgIJAgAAAA==.Morphingtime:BAAALgADCgIJAgAAAA==.Mowte:BAAALgADCgUJEgAAAA==.',
Mu='Murkoobi:BAAALgAECgEJAQAAAA==.Mursk:BAAALgAECgIJAgAAAA==.',
My='Myhoovesrhot:BAAALgAECgIJAgAAAA==.Mystáke:BAAALgAECggJDwAAAA==.',
['Mä']='Mäble:BAAALgADCgYJBwAAAA==.',
['Mê']='Mêrcy:BAAALgADCgYJBgAAAA==.',
['Mò']='Mòus:BAAALgAECgYJEwABLgAECggJEAADAAAAAA==.',
['Mó']='Móus:BAAALgAECgUJBwABLgAECggJEAADAAAAAA==.',
Na='Narcissus:BAAALgADCgUJEgAAAA==.Narivia:BAAALgAECgQJBAABLgAFFAUJEgAXAGkRAA==.Naro:BAAALgADCgkJDAAAAA==.Nathadon:BAAALgAECgEJAQAAAA==.Nathalin:BAAALgAECgUJEAAAAA==.',
Ne='Necrotis:BAAALgADCgUJEgAAAA==.Nectarion:BAAALgAECgEJAQAAAA==.Neftearii:BAAALgADCgEJAQAAAA==.Nevelia:BAABLgAECn8hAAMEAAgJtiT6AABGAwAEAAgJtiT6AABGAwAGAAUJKxgLNwA1AQAAAA==.Nezukô:BAAALgAECgcJAwAAAA==.',
Ni='Nitalan:BAAALgADCgkJIgAAAA==.Nithenseth:BAAALgADCggJDQAAAA==.Nixk:BAAALgAECgYJDwAAAA==.',
No='Noavail:BAAALgADCgMJAwAAAA==.Noixi:BAAALgAECgMJBgAAAA==.Noraldrys:BAAALgADCgcJBwAAAA==.Noralyne:BAAALgAECgQJAwAAAA==.Noras:BAAALgAECgcJCwAAAA==.Noraxia:BAAALgADCgkJEAAAAA==.Nordicslayer:BAABLgAECn8YAAISAAcJywzfDAA1AQASAAcJywzfDAA1AQAAAA==.Notagnoblin:BAEALgAECgMJAwABLgAFFAQJCQAdAJEkAA==.',
Ob='Obnyxion:BAABLgAECn8mAAIhAAkJFA4VAwDDAQAhAAkJFA4VAwDDAQAAAA==.',
Oc='Octuroun:BAAALgAECgYJCQAAAA==.',
Od='Oddsoul:BAAALgAECgIJAgAAAA==.',
Og='Ogrelurd:BAAALgAECgUJCgAAAA==.',
Ol='Oliveia:BAAALgADCgcJCgAAAA==.',
Om='Omontanha:BAAALgAECgUJBwAAAA==.',
On='Oniryoshi:BAAALgAECgQJBAAAAA==.Onlyzugs:BAAALgADCgEJAgAAAA==.',
Op='Ophelia:BAABLgAECn8kAAQTAAgJkiByFgDyAQATAAcJwB1yFgDyAQAiAAQJtyC5BQAjAQAQAAEJpgiNdAAwAAAAAA==.',
Or='Orakwa:BAAALgAECgUJCAAAAA==.',
Pa='Pakleader:BAAALgADCgIJAgAAAA==.Pallinda:BAABLgAECn8WAAMMAAcJrxMhhgBuAQAMAAcJrxMhhgBuAQANAAYJkQ9nHwBMAQAAAA==.Panakananama:BAAALgAECgYJCAAAAA==.Panz:BAAALgAECgYJEQAAAA==.Papablock:BAAALgADCgMJAwAAAA==.Papiperkins:BAAALgAECgEJAQAAAA==.Pappyoblues:BAAALgAECgYJBgAAAA==.Parati:BAAALgAECgIJAgAAAA==.Paylot:BAAALgADCgYJCwAAAA==.',
Pe='Peachmangogt:BAAALgADCgUJBgAAAA==.Pendulum:BAAALgADCgkJCwAAAA==.Pennypacker:BAAALgAECgUJCAAAAA==.Personality:BAAALgADCggJCAAAAA==.Petmycat:BAAALgAECgUJCgAAAA==.',
Ph='Phara:BAAALgAECgcJEQAAAA==.Phenomenon:BAAALgADCgUJBQAAAA==.Phoel:BAAALgADCgUJBQAAAA==.Phoopanchu:BAABLgAECn8XAAIcAAYJbBS+GQA2AQAcAAYJbBS+GQA2AQAAAA==.',
Pi='Pinkbuns:BAABLgAECn8WAAIBAAYJCRhtSQBSAQABAAYJCRhtSQBSAQAAAA==.Pirimus:BAAALgADCgEJAQAAAA==.',
Pn='Pneuma:BAAALgAECgYJEAAAAA==.',
Po='Pofella:BAAALgAECgMJAwAAAA==.Pokinsmot:BAAALgADCgYJCwAAAA==.Pollonius:BAAALgADCgIJAgAAAA==.Popsy:BAAALgAECgUJDQAAAA==.',
Pr='Precarity:BAAALgAECgEJAQAAAA==.Prenton:BAABLgAECn8ZAAIfAAYJHh7RDgDKAQAfAAYJHh7RDgDKAQAAAA==.Pretzel:BAAALgADCgUJBQABLgAECgkJJQAOAEElAA==.Prideflag:BAAALgAECgMJAwAAAA==.Primaldead:BAABLgAECn8aAAITAAcJegzENABYAQATAAcJegzENABYAQAAAA==.Profundity:BAAALgAECgYJDAAAAA==.',
Pu='Punchmyface:BAAALgADCgUJCAAAAA==.Puny:BAABLgAECn8bAAIOAAcJ4R9gEwAfAgAOAAcJ4R9gEwAfAgAAAA==.',
Qe='Qeini:BAABLgAECn8eAAIXAAgJcxggBQBtAgAXAAgJcxggBQBtAgAAAA==.',
Ra='Radrin:BAAALgADCgkJCQAAAA==.Rafoff:BAAALgAECgQJCAAAAA==.Rahll:BAAALgADCgUJEgAAAA==.Rancoramble:BAABLgAECn8VAAIgAAgJNwTvGAC1AAAgAAgJNwTvGAC1AAAAAA==.Randis:BAABLgAECn8ZAAMOAAYJewvXSgAeAQAOAAYJewvXSgAeAQAPAAYJoQIwCgCtAAAAAA==.Ranekk:BAAALgADCgcJFgAAAA==.Razglaive:BAAALgADCgYJBgAAAA==.Razhunt:BAAALgAECgUJCgAAAA==.Razonghoul:BAABLgAECn8mAAIOAAgJTCBbCwBxAgAOAAgJTCBbCwBxAgAAAA==.',
Re='Redheat:BAAALgADCgUJBQAAAA==.Redwyn:BAAALgADCgMJAwAAAA==.Reemonhunter:BAAALgAECgEJAgAAAA==.Regarded:BAAALgADCgcJBwAAAA==.Renge:BAAALgADCgEJAQAAAA==.Rengår:BAAALgAECgUJCwAAAA==.Renx:BAAALgAECgQJBQAAAA==.Reticent:BAAALgAECgUJBgAAAA==.Rexiis:BAABLgAECn8WAAMTAAcJRxFULwBuAQATAAcJRxFULwBuAQAiAAEJAABcNAAzAAAAAA==.Reyth:BAAALgAECgQJCAAAAA==.',
Rh='Rhaul:BAAALgAECgEJAQAAAA==.Rhuby:BAAALgADCgkJDwAAAA==.Rhyl:BAABLgAECn8aAAIYAAcJOSC7EACcAgAYAAcJOSC7EACcAgAAAA==.',
Ri='Rimos:BAAALgADCgUJBQAAAA==.Ripcord:BAAALgADCggJDQAAAA==.Riptîde:BAABLgAECn8cAAIjAAcJEgr0HgAgAQAjAAcJEgr0HgAgAQAAAA==.',
Ro='Rockadin:BAAALgAECgYJEgAAAA==.Rosael:BAAALgADCgYJBgAAAA==.',
Ru='Rubbmytotems:BAAALgAECgUJCAAAAA==.Rulen:BAAALgADCgMJCQAAAA==.Ruleti:BAABLgAECn8aAAMCAAcJbBIBKQByAQACAAcJbBIBKQByAQAJAAIJrQnxegBXAAAAAA==.Rumí:BAABLgAECn8cAAIHAAgJNQn7LgAoAQAHAAgJNQn7LgAoAQAAAA==.Russell:BAAALgADCgUJEgAAAA==.Rutgore:BAABLgAECn8aAAIYAAgJxRfABQAiAgAYAAgJxRfABQAiAgAAAA==.',
Rx='Rx:BAAALgADCgcJDgAAAA==.',
Sa='Sabado:BAAALgAECgQJCAAAAA==.Safewerd:BAEALgAECgYJDQAAAA==.Saitáma:BAAALgADCgQJBAAAAA==.Samíra:BAAALgAECgMJBAAAAA==.Santapaws:BAAALgAECgMJAwAAAA==.Santrious:BAAALgAECgQJBAAAAA==.Sarahfi:BAAALgAECgEJAQAAAA==.Saraisabella:BAAALgADCgMJAwAAAA==.Saralanna:BAAALgAECgQJBgAAAA==.Sarcastrophe:BAAALgADCgMJAwAAAA==.Sarefina:BAAALgAECgUJBgAAAA==.Sathenazarke:BAABLgAECn8qAAQkAAkJghfMEQAhAgAkAAgJ5BjMEQAhAgAlAAcJ0hq+EQB8AQAhAAEJKwj4QgApAAABLgAFFAQJDwAZADccAA==.Saths:BAAALgADCgEJAQABLgAECggJEwADAAAAAA==.',
Sc='Schallue:BAAALgAECgcJEQAAAA==.Schism:BAAALgADCgkJFQAAAA==.Scoban:BAACLgAFFH8TAAINAAUJIyJJAgDzAQANAAUJIyJJAgDzAQAuAAQKfyoAAg0ACAl4IQsOAKgCAA0ACAl4IQsOAKgCAAAA.Scylla:BAAALgAECgUJCgAAAA==.',
Se='Selithel:BAAALgAECgYJDwAAAA==.Serioussurv:BAAALgADCgQJBAAAAA==.Setsunachan:BAAALgADCgIJAgABLgAECgcJFwAgANkUAA==.',
Sh='Shadeebear:BAAALgADCgMJAwAAAA==.Shadowmander:BAAALgAECgYJDQAAAA==.Shaeliana:BAAALgAECgQJDQAAAA==.Shalera:BAAALgAECgcJBwAAAA==.Shaqfu:BAAALgADCgUJEgAAAA==.Shavemybush:BAAALgAECgEJAQAAAA==.Shigure:BAAALgAECgYJDAAAAA==.Shivers:BAAALgAECgUJBQAAAA==.Shnow:BAAALgAECggJEwAAAA==.Sholin:BAAALgAECgYJDAAAAA==.Shomea:BAAALgAECgIJBAAAAA==.Shugz:BAAALgADCgUJEgAAAA==.',
Si='Sikotick:BAABLgAECn8ZAAIFAAgJfB1XCACHAgAFAAgJfB1XCACHAgAAAA==.Sikxbetrayer:BAAALgAECgcJDwAAAA==.Siliconista:BAABLgAECn8uAAIBAAgJrSDPIQDsAgABAAgJrSDPIQDsAgAAAA==.Silverbolt:BAAALgAECgYJCwAAAA==.Simbelmyne:BAAALgADCgMJAwAAAA==.Sinderone:BAACLgAFFH8IAAINAAQJgAo/DQAlAQANAAQJgAo/DQAlAQAuAAQKfzEAAw0ACQmRHAsEALwCAA0ACQmRHAsEALwCAAwABQn4F+9VAA0BAAAA.',
Sk='Skaaduush:BAAALgAECgYJCQAAAA==.Skypaw:BAAALgAECgEJAwAAAA==.',
Sl='Slavon:BAABLgAECn8mAAIOAAkJWBzVHQDOAgAOAAkJWBzVHQDOAgAAAA==.Sleepylune:BAAALgAECgEJAwAAAA==.Sllew:BAABLgAECn8UAAIOAAcJ3R62GgDnAQAOAAcJ3R62GgDnAQAAAA==.',
Sm='Smitestuff:BAAALgAECgYJDwAAAA==.Smoulder:BAAALgAECgEJAQAAAA==.',
Sn='Snigles:BAAALgAECgYJDAAAAA==.',
So='Sokrash:BAAALgADCgcJDQAAAA==.Souei:BAAALgADCgEJAQABLgAECggJEwADAAAAAA==.Soulgiver:BAAALgAECgMJAwAAAA==.',
Sp='Spartos:BAAALgADCgQJBAAAAA==.Sposi:BAEBLgAECn8VAAIgAAYJUSGiBQDXAQAgAAYJUSGiBQDXAQAAAA==.Spraynpray:BAAALgAECgUJBQAAAA==.',
Sr='Srimrithyu:BAAALgADCgcJBwAAAA==.',
Ss='Sselionn:BAAALgAECgUJDwAAAA==.',
St='Stabathaa:BAAALgAECgUJCQAAAA==.Stomps:BAAALgAECgYJBgAAAA==.',
Su='Subliminal:BAABLgAECn8VAAMYAAgJ6xH/DgB9AQAYAAgJ6xH/DgB9AQAeAAEJ9wuCDQA6AAAAAA==.',
Sv='Svartalfar:BAAALgADCgEJAQAAAA==.',
Sy='Syravia:BAAALgAECgYJDQAAAA==.',
['Sé']='Séraphyne:BAAALgAECgQJCAAAAA==.',
Ta='Talarin:BAAALgAECgMJAwAAAA==.Tameka:BAAALgAECgQJBQAAAA==.Tardis:BAAALgAECgkJAQAAAA==.Tatersmonk:BAECLgAFFH8JAAIdAAQJkSSCAgC1AQAdAAQJkSSCAgC1AQAuAAQKfx4AAh0ACQkqJL4DAFQDAB0ACQkqJL4DAFQDAAAA.Tavinrayn:BAAALgAECgQJBAAAAA==.Tazzar:BAABLgAECn8XAAIlAAcJVAe1HgALAQAlAAcJVAe1HgALAQAAAA==.',
Td='Tdjin:BAAALgAECgMJAwAAAA==.',
Te='Teddygraham:BAAALgADCgcJCAAAAA==.Teera:BAAALgADCgEJAQABLgAECggJGwAFABwWAA==.Tekêsh:BAAALgAECgYJEQAAAA==.Telarin:BAABLgAECn8UAAMCAAYJ3xrBTQB/AQACAAYJ3xrBTQB/AQAKAAIJUQU3MAA6AAAAAA==.Tentpoles:BAAALgADCgEJAQAAAA==.Teriss:BAAALgADCgMJAwAAAA==.',
Th='Thandor:BAAALgAECgIJBAAAAA==.Thehonored:BAAALgADCgcJBwAAAA==.Theladyboy:BAAALgAECggJDgAAAA==.Thomss:BAAALgADCgQJCAAAAA==.Throhk:BAAALgADCgQJBAAAAA==.Thuliaga:BAAALgADCgIJAwAAAA==.',
Ti='Tiamut:BAAALgADCgQJBAAAAA==.Tieeny:BAAALgAECgEJAQAAAA==.Tigerliley:BAAALgAECgIJAgABLgAECgYJFwAGALoRAA==.',
To='Tokenhealz:BAAALgAECgQJBAAAAA==.Tomás:BAAALgAECgYJCwAAAA==.Tonyhands:BAAALgADCgMJBgAAAA==.Tonyy:BAACLgAFFH8QAAIgAAUJIhnSBgAtAQAgAAUJIhnSBgAtAQAuAAQKfyMAAiAACQnJIBQDADEDACAACQnJIBQDADEDAAAA.Torstai:BAAALgAECgQJCAAAAA==.',
Tr='Trueshöt:BAAALgAECgYJCgAAAA==.',
Ts='Tserendolgor:BAABLgAECn8UAAQUAAYJ9BhGNQAzAQAUAAYJ9BhGNQAzAQAIAAEJSBUzKQBAAAAHAAEJ0gHYnwAdAAAAAA==.',
Tu='Tuskfury:BAAALgADCgcJDQAAAA==.',
Tw='Twinight:BAAALgAECgEJAQABLgAECggJGwAjAFMWAA==.Twinsha:BAABLgAECn8bAAMjAAgJUxa7DADQAQAjAAgJUxa7DADQAQAmAAcJJwS3WQAhAQAAAA==.Twín:BAAALgADCgYJCAABLgAECggJGwAjAFMWAA==.',
Ty='Tyranastrasz:BAAALgADCgMJAwAAAA==.Tyrasong:BAAALgAECgMJBQAAAA==.Tyresious:BAAALgAECgUJCQAAAA==.',
['Tà']='Tàric:BAAALgAECgEJAQAAAA==.',
Un='Unauma:BAACLgAFFH8GAAIFAAMJLQVeKQB3AAAFAAMJLQVeKQB3AAAuAAQKfxcAAgUACAknHggJAHoCAAUACAknHggJAHoCAAAA.Undeadpanda:BAAALgAECgIJAgABLgAECgEJAgADAAAAAA==.Unholydk:BAAALgAECgQJCQAAAA==.',
Va='Vaa:BAAALgADCgcJEwAAAA==.Vahaghn:BAABLgAECn8pAAISAAgJPyIeAQC+AgASAAgJPyIeAQC+AgAAAA==.Valcerus:BAAALgAECgIJBAAAAA==.Valedus:BAABLgAECn8eAAIMAAcJ9CNWDABkAgAMAAcJ9CNWDABkAgAAAA==.Validrela:BAAALgADCgIJAgAAAA==.',
Ve='Veelete:BAAALgADCggJDQAAAA==.Veinyhawg:BAAALgAECgYJCQAAAA==.Velissena:BAAALgADCgIJAgABLgAECggJIQAEALYkAA==.Vespra:BAABLgAECn8uAAImAAgJGh7sBgB9AgAmAAgJGh7sBgB9AgAAAA==.',
Vh='Vhas:BAAALgAECgkJDgAAAA==.Vhem:BAAALgAECggJAQAAAA==.',
Vi='Viix:BAAALgAECgIJAgABLgAECgYJCQADAAAAAA==.',
Vo='Voidmommy:BAAALgADCgYJBgAAAA==.Voidweaver:BAAALgAECgUJBgAAAA==.Volcker:BAABLgAECn8ZAAIbAAYJWgebFwCpAAAbAAYJWgebFwCpAAAAAA==.Voltashi:BAABLgAECn8gAAQdAAgJQxRSDADEAQAdAAgJQxRSDADEAQAcAAIJtwWiYQBJAAALAAEJBAtugAAwAAAAAA==.Volus:BAAALgADCgUJBQAAAA==.Vorp:BAAALgADCgQJAQAAAA==.',
Vy='Vyniellas:BAAALgADCgYJBgAAAA==.',
Wa='Wagyuboi:BAAALgAECgUJBQAAAA==.Wallypaly:BAABLgAECn8mAAMMAAgJYhWvKACgAQAMAAcJkBavKACgAQAbAAUJ5hYGDwAQAQAAAA==.Walrustusk:BAAALgADCgYJCAAAAA==.Warbourne:BAAALgAECgIJAgAAAA==.Wariius:BAABLgAECn8aAAINAAYJWhuyGACIAQANAAYJWhuyGACIAQAAAA==.Warwarb:BAAALgADCgYJCwABLgAECggJIAATAEgZAA==.Waterliliy:BAABLgAECn8XAAIGAAYJuhHJLgBrAQAGAAYJuhHJLgBrAQAAAA==.',
Wh='Whir:BAAALgADCgUJBQAAAA==.',
Wi='Windfurypie:BAAALgAECgkJBAAAAA==.',
Wo='Wolfbayin:BAAALgADCgYJCgAAAA==.Wolfbish:BAABLgAECn8UAAMCAAcJvA/GKABzAQACAAcJsA7GKABzAQAJAAYJiAtmDgDjAAAAAA==.Wongidan:BAAALgAECgIJAgAAAA==.Woofee:BAAALgADCgQJBwAAAA==.Woxy:BAAALgADCgMJAwAAAA==.',
Wt='Wtfwipeitup:BAAALgAECgMJAwAAAA==.',
Xa='Xanather:BAAALgADCgYJBgABLgAECgIJBAADAAAAAA==.Xandrodron:BAAALgADCgUJBQAAAA==.',
Xe='Xelence:BAAALgADCgQJBAABLgAECggJGwATAIMYAA==.Xenhaseo:BAAALgAECgYJEQAAAA==.',
Xh='Xhuri:BAAALgAECgEJAQAAAA==.',
Xi='Xilla:BAAALgADCgkJCwAAAA==.',
Xs='Xst:BAAALgADCgEJAQAAAA==.',
['Xë']='Xëna:BAAALgAECgYJDgAAAA==.',
Yo='Yorllik:BAAALgADCgcJFAAAAA==.',
Ys='Yserà:BAAALgAECgIJAgAAAA==.',
Yt='Yt:BAABLgAECn8aAAIHAAcJThcaLAA0AQAHAAcJThcaLAA0AQAAAA==.',
Za='Zaboomavoid:BAAALgADCgYJDAAAAA==.Zaes:BAABLgAECn8lAAIlAAkJHiFXAgDUAgAlAAkJHiFXAgDUAgAAAA==.Zaiene:BAAALgAECgIJAgABLgAECgQJBgADAAAAAA==.Zal:BAAALgADCggJEgAAAA==.Zarkhan:BAAALgADCgcJBwAAAA==.Zarulyn:BAAALgAECgQJBAAAAA==.Zavadin:BAAALgAECgYJCQAAAA==.',
Ze='Zeffy:BAAALgAECgQJBAAAAA==.Zeneras:BAAALgAECgYJCgAAAA==.',
Zh='Zhorvan:BAABLgAECn8YAAMmAAcJVxOcQgB2AQAmAAYJOBOcQgB2AQAnAAcJAwVqCwApAQAAAA==.',
Zi='Zigbis:BAAALgADCgYJBgAAAA==.Ziggleton:BAAALgADCgEJAQAAAA==.Zilstar:BAAALgAECgIJAgAAAA==.Zink:BAAALgADCgcJDgAAAA==.',
Zu='Zuginside:BAAALgADCgMJAwAAAA==.',
Zw='Zwolfe:BAAALgADCgIJAgAAAA==.',
Zy='Zya:BAAALgAECgEJAQAAAA==.',
['Âr']='Ârtëmïs:BAABLgAECn8WAAICAAcJGA2qNwA0AQACAAcJGA2qNwA0AQAAAA==.',
['Äc']='Äcid:BAABLgAECn8oAAImAAgJ2h0ZCwA5AgAmAAgJ2h0ZCwA5AgAAAA==.',
['Åp']='Åpollo:BAAALgAFFAMJAwAAAA==.',
['Èa']='Èastçoast:BAAALgADCgcJDQAAAA==.',
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

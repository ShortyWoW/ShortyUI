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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Druid-Guardian','Monk-Windwalker','Druid-Feral','Warrior-Arms','Hunter-Marksmanship','Rogue-Subtlety','DemonHunter-Devourer','Warrior-Fury','Druid-Restoration','Warrior-Protection',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aendean:BAAALgADCgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgADCgcJDwABLgADCgUJCgABAAAAAA==.',
Ar='Arcueid:BAABLgAECn8fAAICAAcJRh8kFwBdAgACAAcJRh8kFwBdAgAAAA==.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn8hAAIDAAgJEiOOAwCOAgADAAgJEiOOAwCOAgAAAA==.',
Ba='Bartholdson:BAAALgAECgEJAQAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgEJAQAAAA==.Berzerkirz:BAAALgADCgEJAQAAAA==.',
Bl='Blacksnow:BAAALgADCgUJBQAAAA==.Blcksnowcrow:BAABLgAECn8VAAIEAAcJqBeWDAB2AQAEAAcJqBeWDAB2AQAAAA==.',
Bo='Bonfire:BAABLgAECn8WAAQFAAcJrSJXHwDHAQAFAAcJrSJXHwDHAQAGAAMJFyKZIwALAQAHAAIJSgKDRABLAAABLgAFFAEJAQABAAAAAA==.Boochili:BAABLgAECn8dAAIIAAgJPSYeAAD/AgAIAAgJPSYeAAD/AgAAAA==.',
Br='Braveling:BAAALgAECgYJCgAAAA==.',
Bu='Bubblës:BAAALgAECgMJBQAAAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8KAAMJAAQJJh5ABwB8AQAJAAQJJh5ABwB8AQAIAAEJ+CKGAgBpAAAuAAQKfyIAAwkACAmrJBwIAFMDAAkACAmrJBwIAFMDAAgAAgkhFO45AFgAAAAA.Chicken:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn83AAMCAAgJKBxMEgCDAgACAAgJKBxMEgCDAgAKAAQJFAieGgCWAAAAAA==.',
Da='Daniedk:BAABLgAECn8XAAILAAgJPxDhZADFAQALAAgJPxDhZADFAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgMJAwAAAA==.',
De='Deathtouch:BAABLgAECn8WAAMLAAcJwx+nCQDkAQALAAcJXx6nCQDkAQAMAAEJDh2CBwBXAAAAAA==.Devona:BAAALgAECgYJDwAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAAALgAECgUJCAAAAA==.Dirtychorizo:BAAALgADCgUJBAAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAANAAwiAA==.Dragoonnick:BAABLgAECn8uAAIOAAgJgBwVBAB0AgAOAAgJgBwVBAB0AgAAAA==.',
Es='Esh:BAAALgAECgYJBgAAAA==.',
Eu='Euphal:BAABLgAECn8cAAIPAAcJFA52GQBIAQAPAAcJFA52GQBIAQAAAA==.',
Ey='Eyekicku:BAAALgAECgYJDgAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBAAAAA==.',
Fi='Fitz:BAAALgAECgMJAwAAAA==.Fitzwell:BAAALgADCgMJAwAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.',
Gh='Ghost:BAAALgAECgMJBAAAAA==.',
Gr='Graycieden:BAAALgADCggJIgAAAA==.',
Gu='Guldangit:BAACLgAFFH8VAAMPAAYJPR6lAADbAQAPAAYJPR6lAADbAQAQAAEJAAA9AwBgAAAuAAQKfykAAw8ACQnCI2wIAD4DAA8ACQkBI2wIAD4DABEABAmOIjAaAHsBAAAA.',
Ha='Hanora:BAAALgADCggJCgAAAA==.',
He='Hellspawn:BAABLgAECn8hAAISAAgJqAtPBQBzAQASAAgJqAtPBQBzAQAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8XAAITAAYJOSQFAABhAgATAAYJOSQFAABhAgAuAAQKfxwAAxMACAlJJeEBAFcDABMACAlJJeEBAFcDABQAAQlPCVkhADUAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn8hAAQVAAgJIB0WAQCrAgAVAAgJIB0WAQCrAgAUAAQJww+BQQDtAAATAAQJrQt/XQC8AAAAAA==.Howii:BAABLgAECn8jAAIWAAgJayLPAACHAgAWAAgJayLPAACHAgAAAA==.',
Im='Imperator:BAAALgAECgMJAwAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAAALgAECgYJDgAAAA==.',
Je='Jellyfïsh:BAAALgAECgUJCQAAAA==.Jeraziah:BAAALgAECgQJCgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgQJBgAAAA==.',
La='Laggers:BAABLgAECn8bAAIXAAYJLBkTEAB3AQAXAAYJLBkTEAB3AQAAAA==.',
Li='Litbit:BAAALgAECgYJCgAAAA==.Litbitonme:BAAALgADCgkJIwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostunholy:BAAALgAECgYJDgAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ma='Maggikal:BAAALgAECgYJEAAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgQJBQAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAAALgAECgcJEwAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECggJIQAVACAdAA==.',
Pe='Periodic:BAABLgAECn8pAAICAAkJ4CPyAACZAwACAAkJ4CPyAACZAwAAAA==.',
Pl='Platen:BAAALgAECgYJDgAAAA==.',
Po='Potter:BAABLgAECn8hAAIDAAgJiBz5DQDaAQADAAgJiBz5DQDaAQAAAA==.',
Ra='Raffa:BAABLgAECn8aAAIYAAcJ+xVIIgDEAQAYAAcJ+xVIIgDEAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Rataiga:BAAALgAECgYJCwAAAA==.',
Rh='Rheynah:BAAALgAECgYJCwAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8OAAIZAAUJtyBKAADyAQAZAAUJtyBKAADyAQAuAAQKfyMAAhkACAlWI94BAEUDABkACAlWI94BAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8XAAIaAAYJ7BWIEgB6AQAaAAYJ7BWIEgB6AQAAAA==.',
Ry='Rynne:BAAALgAECgYJEQAAAA==.',
Sa='Sansundertal:BAABLgAECn8eAAIHAAgJZySAAgBJAwAHAAgJZySAAgBJAwAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAAALgAECgYJDgAAAA==.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBAAAAA==.',
Sh='Shamu:BAAALgAFFAEJAQAAAA==.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgIJAgAAAA==.',
Si='Silvertiger:BAABLgAECn8hAAMNAAgJiRZbAgD+AQANAAgJiRZbAgD+AQAbAAcJgg9mPQBmAQAAAA==.',
Sl='Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgUJBQAAAA==.',
Sn='Sneaki:BAABLgAECn8fAAMcAAgJrRxYAwDqAQAcAAgJrRxYAwDqAQAOAAEJdhZ8CQBIAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQTAAYJbRfbLACTAQATAAYJbRfbLACTAQAUAAQJ5gMXTQChAAAVAAIJkQhXTQBdAAAAAA==.',
So='Sorynia:BAAALgAECgMJAwAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAABLgAECn8UAAIdAAcJAyHGBgAKAgAdAAcJAyHGBgAKAgAAAA==.Startawar:BAABLgAECn8dAAIJAAgJ4SG+AgCNAgAJAAgJ4SG+AgCNAgAAAA==.',
Su='Sukii:BAAALgAECgQJBQAAAA==.Sulfuricvein:BAAALgAECgMJBQAAAA==.',
['Sø']='Sømebody:BAAALgADCgcJCAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgUJBQAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIeAAcJjRj4LwDvAQAeAAcJjRj4LwDvAQAAAA==.',
Tu='Tunny:BAAALgAECgYJBwAAAA==.Turnleft:BAABLgAECn8VAAIfAAcJbyKyEACyAgAfAAcJbyKyEACyAgAAAA==.',
Va='Vauntmonk:BAAALgADCgMJAwABLgAECgkJFQAgAGgeAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgEJAQAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8bAAILAAgJxxxVMQByAgALAAgJxxxVMQByAgAAAA==.Vishlock:BAABLgAECn8hAAMQAAgJtRUHAQCxAQAQAAcJ/xYHAQCxAQAPAAYJLAz5kwAwAQAAAA==.',
Vo='Voddie:BAAALgAECgYJDQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Wapta:BAAALgAFFAEJAQAAAA==.',
Wi='Wizwiztheliz:BAAALgAECgUJCQAAAA==.',
Wo='Wolf:BAAALgAECgUJDQAAAA==.Woof:BAAALgAECgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBgAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Ze='Zenithmage:BAAALgAECgUJCAAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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

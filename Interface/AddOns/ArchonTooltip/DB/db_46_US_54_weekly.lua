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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Rogue-Assassination','Warlock-Demonology','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','Druid-Feral','Warrior-Arms','Hunter-Marksmanship','Rogue-Subtlety','Warrior-Fury','Druid-Restoration',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgADCgcJDwABLgAECgEJAQABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8gAAICAAcJRh8gFwBdAgACAAcJRh8gFwBdAgAAAA==.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn8qAAIDAAkJdSKjAwALAwADAAkJdSKjAwALAwAAAA==.',
Ba='Bartholdson:BAAALgAECgUJBgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8XAAIEAAgJuxYbFgChAQAEAAgJuxYbFgChAQAAAA==.',
Bo='Bonfire:BAABLgAECn8cAAQFAAcJ1CJmFQBUAQAFAAcJrSJmFQBUAQAGAAUJ2yChIwALAQAHAAIJSgKCRABLAAABLgAFFAEJAQABAAAAAA==.Boochili:BAABLgAECn8mAAIIAAkJMSYPAACBAwAIAAkJMSYPAACBAwAAAA==.',
Br='Braveling:BAAALgAECgYJEAAAAA==.',
Bu='Bubblës:BAAALgAECgMJBQAAAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8OAAMJAAQJsx/VBgB+AQAJAAQJsx/VBgB+AQAIAAEJ+CKKBgBpAAAuAAQKfykAAwkACQkFJQcEAN8CAAkACQnhJAcEAN8CAAgAAwlTGCAgAF4AAAAA.Chicken:BAAALgADCgMJAwABLgAECgYJEwABAAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn9CAAMCAAkJMB1LEgCDAgACAAkJMB1LEgCDAgAKAAUJZg6+KQDeAAAAAA==.',
Da='Daniedk:BAABLgAECn8cAAILAAgJ4xFhMAB4AQALAAgJ4xFhMAB4AQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgQJBgAAAA==.',
De='Deathtouch:BAACLgAFFH8FAAILAAMJRRzBMgD8AAALAAMJRRzBMgD8AAAuAAQKfxsAAwsACAlEI+EIAJACAAsACAnFIuEIAJACAAwAAQkOHeoNAFYAAAAA.Devona:BAABLgAECn8VAAMEAAYJlB+GFACxAQAEAAYJlB+GFACxAQAJAAEJZAc8UwEqAAAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAAALgAECgUJDgAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAANAAwiAA==.Dragoonnick:BAABLgAECn8uAAIOAAgJgBwVBAB0AgAOAAgJgBwVBAB0AgAAAA==.',
Es='Esh:BAAALgAECgYJBgAAAA==.',
Eu='Euphal:BAABLgAECn8fAAIPAAcJzRGYNABYAQAPAAcJzRGYNABYAQAAAA==.',
Ey='Eyekicku:BAABLgAECn8UAAIQAAYJQSHUCQDZAQAQAAYJQSHUCQDZAQAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgADCgYJCQAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gu='Guldangit:BAACLgAFFH8bAAMPAAYJ1h6yAQAmAgAPAAYJ1h6yAQAmAgARAAEJAAA9AwBgAAAuAAQKfykAAw8ACQnCI2sIAD4DAA8ACQkBI2sIAD4DABIABAmOIiwaAHsBAAAA.',
Ha='Hanora:BAAALgAECgEJAQAAAA==.',
He='Hellspawn:BAABLgAECn8qAAITAAkJqg7fBwDUAQATAAkJqg7fBwDUAQAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8YAAIUAAYJOSQaAABvAgAUAAYJOSQaAABvAgAuAAQKfxwAAxQACAlJJeABAFcDABQACAlJJeABAFcDABUAAQlPCbZBADUAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn8qAAQWAAkJBB5LAQA2AwAWAAkJBB5LAQA2AwAVAAQJww+MQQDtAAAUAAQJrQuFXQC8AAAAAA==.Howii:BAABLgAECn8sAAIXAAkJHyOvAADBAgAXAAkJHyOvAADBAgAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8UAAIYAAYJtxM0NQA8AQAYAAYJtxM0NQA8AQAAAA==.',
Je='Jellyfïsh:BAAALgAECgUJCgAAAA==.Jeraziah:BAAALgAECgUJDAAAAA==.',
Jo='Johnnyjr:BAAALgAECgkJCQAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEQAAAA==.',
La='Laggers:BAABLgAECn8iAAIZAAgJdhb1BwBlAQAZAAgJdhb1BwBlAQAAAA==.',
Li='Litbit:BAAALgAECgYJCgAAAA==.Litbitonme:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8UAAILAAYJjSK2HwDJAQALAAYJjSK2HwDJAQAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ma='Maggikal:BAABLgAECn8XAAIDAAYJtAz3YgAVAQADAAYJtAz3YgAVAQAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJCwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8YAAMTAAgJoxueEQBRAgATAAgJoxueEQBRAgAaAAQJ+wSQaQBsAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJKgAWAAQeAA==.',
Pe='Periodic:BAABLgAECn8sAAICAAkJ5SPzAACZAwACAAkJ5SPzAACZAwAAAA==.',
Pl='Platen:BAABLgAECn8UAAIYAAYJyg0XVwBjAQAYAAYJyg0XVwBjAQAAAA==.',
Po='Potter:BAABLgAECn8qAAIDAAkJnRyYDAB/AgADAAkJnRyYDAB/AgAAAA==.',
Ra='Raffa:BAABLgAECn8aAAIQAAcJ+xVJIgDDAQAQAAcJ+xVJIgDDAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Rataiga:BAAALgAECgYJEQAAAA==.',
Rh='Rheynah:BAAALgAECgYJEQAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8SAAIbAAYJBB8jAADVAQAbAAYJBB8jAADVAQAuAAQKfyYAAhsACQkRJdwBAEUDABsACQkRJdwBAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8fAAIcAAgJVBYJBAAHAgAcAAgJVBYJBAAHAgAAAA==.',
Ry='Rynne:BAAALgAECgYJEQAAAA==.',
Sa='Sansundertal:BAABLgAECn8nAAIHAAkJYSGAAgBJAwAHAAkJYSGAAgBJAwAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8UAAIXAAYJLhgJDgAxAQAXAAYJLhgJDgAxAQAAAA==.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBQAAAA==.',
Sh='Shamu:BAAALgAFFAIJAgAAAA==.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgIJAgAAAA==.',
Si='Silvertiger:BAABLgAECn8qAAMNAAkJTBrzAQCjAgANAAkJTBrzAQCjAgAdAAcJgg9mPQBmAQAAAA==.',
Sl='Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgMJAwABLgAECgkJKgAWAAQeAA==.Sneaki:BAABLgAECn8oAAMeAAkJoCArAgCnAgAeAAkJHiArAgCnAgAOAAEJsxxREQBUAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQUAAYJbRfcLACTAQAUAAYJbRfcLACTAQAVAAQJ5gMaTQChAAAWAAIJkQhWTQBdAAAAAA==.',
So='Sorynia:BAAALgAECgUJCQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8FAAIaAAMJFhKOLACiAAAaAAMJFhKOLACiAAAuAAQKfxUAAhoACAmNIRsLACsCABoACAmNIRsLACsCAAAA.Startawar:BAABLgAECn8dAAIJAAgJ4SFjCQCIAgAJAAgJ4SFjCQCIAgAAAA==.',
Su='Sukii:BAAALgAECgQJBQAAAA==.Sulfuricvein:BAAALgAECgMJBQAAAA==.',
['Sø']='Sømebody:BAAALgADCgcJCAAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgUJBQAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIfAAcJjRj6LwDvAQAfAAcJjRj6LwDvAQAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8cAAIgAAgJ7iOUAwD8AgAgAAgJ7iOUAwD8AgAAAA==.',
Va='Vauntmonk:BAAALgADCgMJAwAAAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8eAAILAAkJqhqHIADEAQALAAkJqhqHIADEAQAAAA==.Vishlock:BAABLgAECn8qAAMRAAkJzBROAQAOAgARAAgJeBZOAQAOAgAPAAcJIQwFlAAwAQAAAA==.',
Vo='Voddie:BAAALgAECgYJEwAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgYJBgABLgAECgcJFwAFAIAWAA==.Wapta:BAAALgAFFAEJAQAAAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAAALgAECgYJEwAAAA==.Woof:BAAALgAECgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgUJBQAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
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

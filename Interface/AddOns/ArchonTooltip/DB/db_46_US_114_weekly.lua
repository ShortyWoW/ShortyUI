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

local lookup = {'DeathKnight-Unholy','Warlock-Demonology','Priest-Holy','Warlock-Destruction','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Druid-Restoration','DemonHunter-Devourer','Hunter-BeastMastery','Monk-Windwalker',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aeri:BAAALgAECgUJBwAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgMJAwAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
Ar='Arin:BAAALgAECgEJAQABLgAECggJJgABAF8jAA==.',
As='Asuya:BAAALgADCgEJAQAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Bc='Bc:BAEBLgAECn8YAAICAAgJ+CYyAwCOAwACAAgJ+CYyAwCOAwAAAA==.',
Be='Beep:BAABLgAECn8ZAAICAAcJEB54CwC/AQACAAcJEB54CwC/AQAAAA==.',
Bl='Blackthunder:BAAALgAECgMJAwAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAIDAAYJKROYDAAoAQADAAYJKROYDAAoAQAAAA==.',
Bu='Budleaf:BAAALgADCgQJAwAAAA==.Bunkley:BAAALgAECgUJDAAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAABLgAECn8bAAMCAAgJOhzpOQAkAgACAAcJLB7pOQAkAgAEAAUJzhe3GwBwAQAAAA==.',
Ca='Cantfireme:BAAALgADCgcJBwABLgAECgcJEwAFAAAAAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAAALgAECgYJBgAAAA==.',
Ch='Chaoticus:BAAALgAECgYJBwAAAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgUJBQAAAA==.',
Cu='Culdan:BAAALgAECgMJBgAAAA==.',
Da='Dalirus:BAAALgADCgcJBwABLgAECgcJEwAFAAAAAA==.Darksuaza:BAAALgAECgYJCAAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAAALgAECgYJDgAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Do='Doomhead:BAAALgAECgYJDgAAAA==.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAABLgAECn8UAAIGAAYJGCWkEgB9AgAGAAYJGCWkEgB9AgAAAA==.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgADCgcJEgAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAAALgAECgYJDgAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJAwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgIJAgABLgAECgMJAwAFAAAAAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAAALgAECgcJDQAAAA==.',
Gu='Gulvid:BAAALgAECgcJDAABLgAFFAUJCgACAJcQAA==.',
Ha='Haluak:BAABLgAECn8UAAIHAAYJeBf0LwCgAQAHAAYJeBf0LwCgAQAAAA==.',
He='Healthyself:BAAALgADCgUJBQAAAA==.',
Ho='Houndtamer:BAAALgAECgYJEQAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMIAAYJ9BzlhADIAQAIAAYJCRnlhADIAQAJAAMJzRktDwDQAAAAAA==.',
It='Itshela:BAACLgAFFH8HAAMBAAQJmBBjDgADAQABAAMJmBBjDgADAQAKAAEJAABfDgAAAAAuAAQKfxsAAgEABwkrI+VNAAkCAAEABwkrI+VNAAkCAAAA.',
Ja='Jayrad:BAAALgAECgQJBwAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgMJAwAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgADCgIJAgAAAA==.Kairos:BAAALgAECgMJBgAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgQJBwAAAA==.Kethrym:BAAALgADCgYJCwAAAA==.',
Kh='Khanor:BAAALgAECgYJBgAAAA==.',
Ki='Kiltro:BAAALgAECgEJAgAAAA==.Kimchichi:BAAALgAECgEJAQAAAA==.Kintaro:BAAALgADCgQJBAAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECgEJAQAAAA==.Lapriestess:BAAALgADCgcJDAAAAA==.Latoya:BAAALgADCggJEwAAAA==.',
Li='Lilbeemo:BAAALgAECgUJBgAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAAALgAECgYJEAAAAA==.',
Lu='Luckyxpain:BAAALgAECgcJEwAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAAALgAECgYJDAAAAA==.',
Me='Melancholic:BAABLgAECn8VAAMLAAYJHxr7OQC+AQALAAYJHxr7OQC+AQAMAAEJnQTGFAA2AAAAAA==.Mellisa:BAAALgAECggJEQAAAA==.',
Mo='Mooshmoo:BAAALgADCgEJAQAAAA==.',
Mu='Murog:BAAALgAECgYJCQAAAA==.',
Na='Nazarite:BAAALgADCgYJCQAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Op='Ophellia:BAAALgADCgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAUJDQANACojAA==.Purrformance:BAACLgAFFH8NAAINAAUJKiOcAwCrAQANAAUJKiOcAwCrAQAuAAQKfyIAAg0ACQmiJQ0BAKcDAA0ACQmiJQ0BAKcDAAEuAAUUBQkNAA0AKiMA.',
Py='Pyrophobiac:BAACLgAFFH8MAAMCAAQJihSKEgBSAQACAAQJihSKEgBSAQAEAAIJWwI/DwB/AAAuAAQKfyMAAwIACQnaI4EDAIcDAAIACQmYI4EDAIcDAAQABwmhHUUHAFQCAAAA.',
Ra='Ra:BAAALgAECgQJBAAAAA==.Radagast:BAABLgAECn8ZAAIOAAgJ+RDlDACsAQAOAAgJ+RDlDACsAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgADCgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgEJAQAAAA==.Roxyfox:BAAALgADCgUJBQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.',
Sh='Shakaboom:BAAALgAECgQJBwAAAA==.Sheffurs:BAAALgAECgYJDgAAAA==.Shepardl:BAACLgAFFH8OAAIGAAUJlCKUAAD1AQAGAAUJlCKUAAD1AQAuAAQKfyEAAgYACAnkJhoBAIEDAAYACAnkJhoBAIEDAAAA.Shárkbait:BAAALgADCgcJDAAAAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgQJBQAAAA==.Smacmywand:BAAALgAECgIJBAAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAAALgAECgYJDgAAAA==.',
Sp='Spoons:BAAALgAECgQJBAAAAA==.Spyromu:BAAALgADCgEJAQAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECgYJCAAAAA==.',
Sw='Swiss:BAABLgAECn8WAAIGAAgJrQ1NNACsAQAGAAgJrQ1NNACsAQAAAA==.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgEJAQAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJCwAAAA==.Thunderrod:BAABLgAECn8bAAIPAAgJnhTOPgC0AQAPAAgJnhTOPgC0AQAAAA==.',
Ti='Tim:BAAALgADCgYJDQAAAA==.',
To='To:BAAALgADCgYJCwAAAA==.Tovisar:BAAALgAECgMJBAAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgMJAwAAAA==.',
Ug='Uglykasanova:BAAALgAECgQJBwAAAA==.',
Ul='Ulfrir:BAAALgAECgEJAQAAAA==.',
Va='Vastian:BAAALgAECgUJCQAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.',
We='Wexew:BAAALgAFFAEJAQAAAA==.Wexwex:BAAALgAECgUJDwABLgAFFAEJAQAFAAAAAA==.',
Wi='Wishing:BAAALgAECgQJBAAAAA==.',
Wu='Wunderwazard:BAABLgAECn8hAAIIAAgJex9uBgBHAgAIAAgJex9uBgBHAgAAAA==.',
Xe='Xevikan:BAAALgAECgcJDgAAAA==.',
Ya='Yadead:BAAALgADCgcJDwAAAA==.',
Za='Zaylen:BAAALgAECgYJDwABLgAECggJGAAQAE4fAA==.',
Ze='Zendjin:BAAALgADCgQJBAAAAA==.',
Zi='Zistormstout:BAAALgAECgYJEgAAAA==.',
Zu='Zuhgonemad:BAAALgAECgEJAgAAAA==.',
['Äl']='Älektra:BAAALgAECgYJDgAAAA==.',
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

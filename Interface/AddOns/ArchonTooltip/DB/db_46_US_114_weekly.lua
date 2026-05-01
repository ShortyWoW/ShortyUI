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

local lookup = {'Warlock-Demonology','Priest-Holy','Warlock-Destruction','Paladin-Retribution','Unknown-Unknown','Hunter-Survival','Paladin-Holy','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Paladin-Protection','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian',}
local provider = {region='US',realm="Gul'dan",name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aeri:BAAALgAECgUJBwAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgMJBgAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ar='Arin:BAAALgAECgIJAwAAAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Bc='Bc:BAEBLgAECn8YAAIBAAgJ+CYzAwCNAwABAAgJ+CYzAwCNAwAAAA==.',
Be='Beep:BAABLgAECn8eAAIBAAcJix5nGwDQAQABAAcJix5nGwDQAQAAAA==.',
Bl='Blackthunder:BAAALgAECgQJBAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAICAAYJKRMOHQAcAQACAAYJKRMOHQAcAQAAAA==.',
Bu='Budleaf:BAAALgAECgIJAgAAAA==.Bunkley:BAAALgAECgUJEQAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8GAAIBAAMJwRfIHQANAQABAAMJwRfIHQANAQAuAAQKfyMAAwEACAn8IckHAJACAAEACAnTIckHAJACAAMABQnOF7QbAHABAAAA.',
Ca='Cantfireme:BAAALgADCgcJBwABLgAECgcJHAAEAFsUAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAAALgAECgYJDAAAAA==.',
Ch='Chaoticus:BAAALgAECgYJDQAAAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgYJCwAAAA==.',
Cu='Culdan:BAAALgAECgQJCwAAAA==.',
Da='Dalirus:BAAALgADCgcJDgABLgAECgcJHAAEAFsUAA==.Darci:BAAALgAECgQJBAABLgADCggJGgAFAAAAAA==.Darksuaza:BAAALgAECgcJCgAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn8WAAIDAAgJLhJSBACYAQADAAgJLhJSBACYAQAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Discipline:BAAALgAECgYJBgABLgAFFAYJEwAGAFMSAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAAALgAECgcJEQAAAA==.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAABLgAECn8XAAIHAAgJ3CGgEgB9AgAHAAgJ3CGgEgB9AgAAAA==.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgADCgkJGwAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn8WAAIIAAgJcglUMgBwAQAIAAgJcglUMgBwAQAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJAwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgQJBgAAAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAABLgAECn8UAAIJAAcJ4yODBgCvAgAJAAcJ4yODBgCvAgAAAA==.',
Gu='Gulvid:BAAALgAECgcJDAABLgAFFAYJEAABAOsPAA==.',
Ha='Haluak:BAABLgAECn8ZAAIKAAgJYhb1LwCgAQAKAAgJYhb1LwCgAQAAAA==.',
He='Healthyself:BAAALgADCgkJDgAAAA==.',
Ho='Houndtamer:BAABLgAECn8XAAILAAYJsg+ROgApAQALAAYJsg+ROgApAQAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMMAAYJ9BzVhADIAQAMAAYJCRnVhADIAQANAAMJzRkvDwDQAAAAAA==.',
It='Itshela:BAACLgAFFH8MAAMIAAUJMRsBFgBZAQAIAAQJMRsBFgBZAQAOAAEJAACOIQAAAAAuAAQKfxsAAggABwkrI+BNAAkCAAgABwkrI+BNAAkCAAAA.',
Ja='Jayrad:BAAALgAECgQJBwAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgMJAwAAAA==.Jorkoh:BAAALgAECgMJAwAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgMJAwAAAA==.Kairos:BAAALgAECgYJCgAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgQJBwAAAA==.Kethrym:BAAALgAECgEJAQAAAA==.',
Kh='Khanor:BAAALgAECgYJDAAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAAALgAECgQJBQAAAA==.Kintaro:BAAALgADCgQJBAAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECgQJCwAAAA==.Lapriestess:BAAALgADCgkJFQAAAA==.Latoya:BAAALgAECgMJAwAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgADCgkJCQAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8WAAIIAAYJAyChKQCWAQAIAAYJAyChKQCWAQAAAA==.',
Lo='Loudog:BAAALgAECgEJAgAAAA==.',
Lu='Luckyxpain:BAABLgAECn8cAAMEAAcJWxQfZgC0AQAEAAcJWxQfZgC0AQAPAAUJ5wLHMgCAAAAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAAALgAECgYJEQAAAA==.',
Me='Melancholic:BAABLgAECn8VAAMQAAYJHxr/OQC+AQAQAAYJHxr/OQC+AQARAAEJnQRKLwAwAAAAAA==.Mellisa:BAAALgAECggJEwAAAA==.',
Mo='Mooshmoo:BAAALgADCgYJCwAAAA==.',
Mu='Murog:BAAALgAECgcJDAAAAA==.',
Na='Nazarite:BAAALgADCgcJDAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAUJEQAJACIkAA==.Purrformance:BAACLgAFFH8RAAIJAAUJIiTnAgDzAQAJAAUJIiTnAgDzAQAuAAQKfyIAAgkACQmiJQ4BAKcDAAkACQmiJQ4BAKcDAAAA.',
Py='Pyrophobiac:BAACLgAFFH8RAAMBAAYJTxeLEgBSAQABAAYJTxeLEgBSAQADAAIJWwI9DwB/AAAuAAQKfyMAAwEACQnaI4IDAIcDAAEACQmYI4IDAIcDAAMABwmhHUUHAFQCAAAA.',
Ra='Ra:BAAALgAECgQJBQAAAA==.Radagast:BAABLgAECn8TAAISAAgJ6AzJawBfAQASAAgJ6AzJawBfAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgADCgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgEJAQAAAA==.Roxyfox:BAAALgADCgkJDgAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.',
Sh='Shakaboom:BAAALgAECgQJBwAAAA==.Sheffurs:BAABLgAECn8WAAITAAgJ9QH0FAB2AAATAAgJ9QH0FAB2AAAAAA==.Shepardl:BAACLgAFFH8UAAIHAAYJwCN0AABiAgAHAAYJwCN0AABiAgAuAAQKfyEAAgcACAnkJhsBAIEDAAcACAnkJhsBAIEDAAAA.Shárkbait:BAAALgADCgcJDAABLgAECggJHwAOABsbAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgUJCAAAAA==.Smacmywand:BAAALgAECgIJBQAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn8WAAMEAAgJqgy2fgCwAAAEAAYJcga2fgCwAAAHAAgJeAV5NgChAAAAAA==.',
Sp='Spoons:BAAALgAECgQJBAAAAA==.Spyromu:BAAALgAECgEJAQAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECgYJCAAAAA==.',
Sw='Swiss:BAABLgAECn8YAAIHAAgJrQ0SGwB0AQAHAAgJrQ0SGwB0AQAAAA==.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgEJAwAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8gAAILAAgJTRVtIACeAQALAAgJTRVtIACeAQAAAA==.',
Ti='Tim:BAAALgADCgYJDQAAAA==.',
To='To:BAAALgAECgEJAQAAAA==.Tovisar:BAAALgAECgMJBAAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJCQAAAA==.',
Ug='Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgEJAQAAAA==.',
Va='Vastian:BAAALgAECgUJCQAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.',
We='Wexew:BAAALgAFFAEJAgAAAA==.Wexwex:BAAALgAECgUJDwABLgAFFAEJAgAFAAAAAA==.',
Wi='Wishing:BAAALgAECgYJBwAAAA==.',
Wu='Wunderwazard:BAABLgAECn8pAAIMAAgJKCBVCwCNAgAMAAgJKCBVCwCNAgAAAA==.',
Xe='Xevikan:BAAALgAECgcJEgAAAA==.',
Ya='Yadead:BAAALgADCgkJGAAAAA==.',
Za='Zaylen:BAAALgAECgYJEwAAAA==.',
Ze='Zendjin:BAAALgADCgYJCQAAAA==.',
Zi='Zistormstout:BAABLgAECn8YAAIKAAYJohGmHQApAQAKAAYJohGmHQApAQAAAA==.',
Zu='Zuhgonemad:BAAALgAECgEJAgAAAA==.',
['Äl']='Älektra:BAAALgAECgcJEAAAAA==.',
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

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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Demonology','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Rogue-Subtlety','Mage-Frost','Druid-Guardian','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Priest-Shadow','Mage-Fire','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaphrodite:BAAALgADCgcJCwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8MAAIBAAUJsBBOCwB8AQABAAUJsBBOCwB8AQAuAAQKfxYAAwIACAlUGL8jAJ8BAAIABwnaGL8jAJ8BAAEABgkJFRlYAJkBAAEuAAUUBgkUAAMAThsA.',
Ac='Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJDwABLgAFFAYJEgAEAB4YAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAAALgAECggJEwAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJBgAFAAAAAA==.Alius:BAAALgADCgQJBAAAAA==.',
Am='Ambellina:BAABLgAECn8cAAMGAAgJZhqJFABuAgAGAAgJZhqJFABuAgAHAAMJTAhvOwCnAAAAAA==.Amp:BAAALgAECgEJAQABLgAFFAMJCgAIAA8WAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.',
Au='Auxiliry:BAAALgADCgEJAQAAAA==.',
Av='Avenger:BAAALgADCgQJCAABLgAFFAUJFQAJAHMgAA==.',
Be='Beefycrits:BAABLgAECn8aAAIKAAgJ6iG+FwAcAwAKAAgJ6iG+FwAcAwAAAA==.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgEJAQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Capriestson:BAAALgAECgYJDwAAAA==.Cardrin:BAABLgAECn8bAAMLAAcJQg+aEwA2AQALAAcJQg+aEwA2AQAMAAYJ4gPUWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8SAAIDAAUJHxVzAgCPAQADAAUJHxVzAgCPAQAuAAQKfx0AAgMACAluIBkIAPgCAAMACAluIBkIAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAAALgAFFAIJAQAAAA==.',
Cl='Clearance:BAAALgADCgcJBwABLgAFFAUJEQAEAO0YAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgADCgkJEQAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQAAAA==.Cyxopal:BAAALgADCgEJAQABLgADCgEJAQAFAAAAAA==.',
Da='Daemon:BAACLgAFFH8SAAQEAAYJHhh/CACgAQAEAAYJgBJ/CACgAQANAAMJaQz9BwDrAAAOAAEJLx/7AABlAAAuAAQKfysABAQACQmdIxUFACoCAAQACQkgIxUFACoCAA4ABAlOIb0NAFgBAA0AAwk5FI8xAPMAAAAA.Dalekin:BAAALgAECgcJEwAAAA==.Darkurge:BAAALgAECgQJBAAAAA==.Dattsu:BAAALgAECgcJEwAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJDgAAAA==.Demonius:BAAALgADCgMJAwABLgAECgkJCAAFAAAAAA==.Derangedxo:BAACLgAFFH8fAAQEAAgJthtJAACPAgAEAAcJsx5JAACPAgANAAUJ5RDLAQC9AQAOAAEJAACJAwBeAAAuAAQKfxsAAwQACQmUJUQCAKUDAAQACQmUJUQCAKUDAA0AAwmgI+slAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJBgABLgAECggJGAAPAOQTAA==.',
Do='Dominina:BAAALgAECgEJAQAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDAAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAAALgAECgYJDgAAAA==.',
En='Enana:BAAALgAECgUJCQAAAA==.Enkor:BAABLgAECn8bAAIDAAgJShQeHQDxAQADAAgJShQeHQDxAQAAAA==.',
Ev='Everblack:BAABLgAECn8jAAINAAgJcByMAAApAgANAAgJcByMAAApAgAAAA==.Evilcretin:BAACLgAFFH8HAAIKAAMJfRzZDgAYAQAKAAMJfRzZDgAYAQAuAAQKfxYAAgoABQlKJCZwAPQBAAoABQlKJCZwAPQBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Faraah:BAABLgAECn8mAAMQAAkJVh0ZAgA5AwAQAAkJVh0ZAgA5AwARAAEJ0gTh2wAnAAAAAA==.',
Fr='Friérén:BAABLgAECn8gAAMKAAgJKx6sUgBAAgAKAAgJKx6sUgBAAgASAAEJuAUsIQApAAAAAA==.',
Ga='Garro:BAABLgAECn8ZAAITAAgJAx7UGwBuAgATAAgJAx7UGwBuAgAAAA==.',
Ge='Genjidh:BAABLgAECn8UAAQUAAgJgh9SDwBdAQACAAQJGyLqJgCJAQAUAAUJFR5SDwBdAQABAAQJzxabgwAhAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gorggononson:BAAALgADCgkJGwAAAA==.',
Gr='Graud:BAAALgAFFAEJAQAAAA==.Grimdark:BAABLgAECn8WAAIVAAYJbQ+yUABCAQAVAAYJbQ+yUABCAQAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAECgQJBAAAAA==.Grumpypants:BAABLgAECn8UAAILAAYJOBSgEwA1AQALAAYJOBSgEwA1AQAAAA==.Grunge:BAABLgAECn8dAAQNAAgJDBbXIwA6AQANAAUJoRDXIwA6AQAEAAYJ7RUOJAAJAQAOAAEJOBrDLQBDAAAAAA==.',
Gu='Gumbomage:BAABLgAECn8hAAIKAAgJMCGjIgDoAgAKAAgJMCGjIgDoAgAAAA==.',
Ha='Haven:BAABLgAECn8hAAIWAAgJkh/yCQDjAgAWAAgJkh/yCQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn8ZAAIXAAgJFRehAADAAQAXAAgJFRehAADAAQAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Ho='Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgADCgYJBgAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAAALgAFFAEJAQAAAA==.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Inmelancholy:BAAALgAECgEJAQAAAA==.',
Ir='Irishbaby:BAAALgADCgUJBQAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAAALgAECggJEwAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8RAAMEAAYJ6xdIEABeAQAEAAQJ/hRIEABeAQANAAMJIhtUBgAKAQAuAAQKfx4ABA4ACAnHIi4FABsCAAQABwm6IawdAKQCAA4ABQlrJS4FABsCAA0AAgkYG1hEAKQAAAAA.Jamboni:BAAALgAECgEJAQAAAA==.Jarmamathu:BAAALgAECgYJCQAAAA==.Jay:BAAALgAECgQJBQABLgAFFAEJAQAFAAAAAA==.',
Jo='Joje:BAAALgAECgYJEgAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgADCgUJBQAAAA==.Jumper:BAAALgADCgYJCwAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAQAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAAALgAECggJAwAAAA==.Keora:BAAALgAECggJEQAAAA==.',
Kh='Khronos:BAAALgAECggJDgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgQJBQAAAA==.Kittier:BAAALgAECgYJBgAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Kronik:BAAALgADCgMJAwAAAA==.Krow:BAAALgADCggJFAAAAA==.',
La='Large:BAAALgAECgYJDQAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightsmith:BAABLgAECn8VAAIGAAYJpSOOGQBGAgAGAAYJpSOOGQBGAgAAAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lorez:BAABLgAFFH8KAAIEAAQJZguSCQAuAQAEAAQJZguSCQAuAQAAAA==.Low:BAAALgAECgYJEgAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAAALgAECgQJCAAAAA==.Mageaurora:BAAALgADCgkJCwAAAA==.Marax:BAAALgAECgYJDgAAAA==.Maugrim:BAAALgADCgkJEQAAAA==.Maxiepadjr:BAAALgADCgUJBwAAAA==.Mazzh:BAAALgAFFAYJAgABLgAFFAcJAwAFAAAAAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgADCggJCwAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mistabones:BAAALgADCgEJAgAAAA==.Miyara:BAABLgAECn8cAAMBAAkJQAr6XgCEAQABAAkJEAr6XgCEAQACAAYJEAlGOwATAQAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAAALgAECgYJCQAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nighttwister:BAAALgAECgcJCQAAAA==.Nitekiller:BAAALgADCgkJCQAAAA==.',
No='Noctilucent:BAAALgAECgQJBAAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgADCgcJDQAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgADCgYJBwAAAA==.Paredes:BAAALgADCggJCwAAAA==.',
Pe='Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAAALgAFFAEJAQAAAA==.',
Po='Pompkin:BAAALgADCgQJBAABLgAECggJIAAKACseAA==.',
Pr='Pride:BAAALgAECgYJDQAAAA==.Prophesy:BAABLgAECn8dAAIHAAgJcBzCKACCAgAHAAgJcBzCKACCAgAAAA==.Proteus:BAABLgAECn8gAAMYAAgJqRBDYQDPAQAYAAgJqRBDYQDPAQAZAAQJFwy0DgC3AAAAAA==.',
Pu='Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgADCgUJBQAAAA==.',
Re='Reflex:BAAALgAECgUJBQAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAAALgAECggJEwAAAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Runninscared:BAAALgAECgkJCAAAAA==.',
['Rü']='Rüntzz:BAAALgAECgIJAwAAAA==.',
Se='Senada:BAAALgAECgYJDgAAAA==.Senkait:BAAALgAECgYJDwAAAA==.',
Sh='Shamoura:BAACLgAFFH8XAAIPAAYJFRpPAQAXAgAPAAYJFRpPAQAXAgAuAAQKfx0AAg8ACAmcIykJAP8CAA8ACAmcIykJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgMJAwAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulszaura:BAACLgAFFH8SAAIHAAYJrBK3BQCUAQAHAAYJrBK3BQCUAQAuAAQKfyoAAgcACQnfIAUSAAIDAAcACQnfIAUSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAABLgAECn8nAAIBAAgJWR07BgAYAgABAAgJWR07BgAYAgAAAA==.Steampunk:BAAALgAECgcJEgAAAA==.',
Sw='Swade:BAAALgAECgYJDQAAAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAECggJIAAKACseAA==.Synarri:BAACLgAFFH8IAAIGAAMJ5hNDDgDyAAAGAAMJ5hNDDgDyAAAuAAQKfx0AAwYACQmPGuQNAKkCAAYACQmPGuQNAKkCAAcABwnAG7YwAGACAAEuAAUUBgkWAAYA+BkA.Syneria:BAACLgAFFH8WAAMGAAYJ+BkDAQAZAgAGAAYJ+BkDAQAZAgAHAAEJ6QGKGwBCAAAuAAQKfzoAAwYACAnoIE0LAMQCAAYACAnoIE0LAMQCAAcACAmRHPUsAHACAAAA.Synpai:BAABLgAECn8hAAMGAAkJQBUCLADXAQAGAAcJLhQCLADXAQAHAAYJOxsmYADEAQABLgAFFAYJFgAGAPgZAA==.',
Ta='Taccitus:BAACLgAFFH8MAAIBAAQJKBQeCAAwAQABAAQJKBQeCAAwAQAuAAQKfyAAAgEACAkwIkAdAKICAAEACAkwIkAdAKICAAAA.Tailzz:BAAALgAECgEJAQAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.',
Te='Teach:BAAALgAFFAEJAQAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAAALgAECgYJDAAAAA==.',
To='Toomato:BAAALgADCgUJDQAAAA==.Totemterror:BAEBLgAECn8eAAIVAAcJbiaOAQClAgAVAAcJbiaOAQClAgAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Ty='Tydradul:BAABLgAECn8aAAIEAAgJbBBXSADxAQAEAAgJbBBXSADxAQAAAA==.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn8UAAIRAAcJgxn7NADUAQARAAcJgxn7NADUAQAAAA==.Valy:BAAALgAECgQJCQAAAA==.',
Ve='Veladria:BAABLgAECn8WAAIYAAcJhBtvWgDiAQAYAAcJhBtvWgDiAQAAAA==.Vellion:BAAALgADCgYJCAAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAQAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAABLgAECn8cAAIBAAcJSyI0DAC0AQABAAcJSyI0DAC0AQAAAA==.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAYJEQAEAOsXAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBgABLgAECgkJCAAFAAAAAA==.',
Wi='Wikkid:BAAALgAECgYJEgAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBAAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgMJAwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.',
Yi='Yiesus:BAAALgAECgcJDAABLgAFFAYJFwABAMEkAA==.',
Ym='Ymir:BAABLgAECn8bAAMNAAgJ9BL6DQDnAQANAAgJ9BL6DQDnAQAEAAQJDgRx4wCTAAAAAA==.',
Yo='Yomato:BAABLgAECn8kAAIRAAgJ+RwdBgASAgARAAgJ+RwdBgASAgAAAA==.',
Yp='Yppah:BAABLgAECn8YAAIPAAcJvA5tNwB1AQAPAAcJvA5tNwB1AQAAAA==.',
Yu='Yuhmato:BAAALgAECgUJBQAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAAALgAECggJEQAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8MAAIBAAQJMhwVBwA9AQABAAQJMhwVBwA9AQAuAAQKfyMAAgEACAmGIxcNABcDAAEACAmGIxcNABcDAAAA.',
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

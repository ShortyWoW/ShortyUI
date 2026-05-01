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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Evoker-Augmentation','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8LAAIBAAUJsBBOCwB8AQABAAUJsBBOCwB8AQAuAAQKfxsAAwEACAlBGrIjAF4BAAIABwnaGMMjAJ8BAAEACAlRGLIjAF4BAAEuAAUUBgkUAAMAThsA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJDwABLgAFFAYJGAAEAPgaAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8bAAIFAAgJaiB9BgCQAgAFAAgJaiB9BgCQAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJBgAGAAAAAA==.Alius:BAAALgADCgQJBAAAAA==.',
Am='Ambellina:BAABLgAECn8lAAMHAAgJGBuGFABuAgAHAAgJGBuGFABuAgAIAAMJDQyXfQCyAAAAAA==.Amp:BAAALgAECgEJAQAAAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.',
Au='Auxiliry:BAAALgADCgEJAQAAAA==.',
Av='Avenger:BAAALgAECgMJAwABLgAFFAcJGwAJAFodAA==.',
Ay='Aythrior:BAAALgAECgMJAwAAAA==.',
Be='Beefycrits:BAACLgAFFH8FAAIKAAIJ5CViMwDOAAAKAAIJ5CViMwDOAAAuAAQKfx0AAgoACAkpJMEXABwDAAoACAkpJMEXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgADCgcJCAAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Capriestson:BAABLgAECn8VAAILAAYJPhgKFgBQAQALAAYJPhgKFgBQAQAAAA==.Cardrin:BAABLgAECn8dAAMMAAgJLw+pCwAFAQAMAAgJLw+pCwAFAQANAAYJ4gPZWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8TAAIDAAUJHxV1AgCPAQADAAUJHxV1AgCPAQAuAAQKfx4AAgMACAluIBoIAPgCAAMACAluIBoIAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAAALgAFFAQJAQAAAA==.',
Cl='Clearance:BAAALgAFFAIJAgAAAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgMJAwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQAAAA==.Cyxopal:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Da='Daemon:BAACLgAFFH8YAAQEAAYJ+BqECACgAQAEAAYJgBKECACgAQAOAAMJKhEJCADrAAAPAAEJLx+9AgBhAAAuAAQKfy4ABAQACQmdI/QSAOQCAAQACQkgI/QSAOQCAA8ABAlOIbwNAFgBAA4AAwk5FJAxAPMAAAAA.Dalekin:BAAALgAFFAEJAQAAAA==.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAAALgADCgIJAgABLgAECgYJGAAQAMcKAA==.Dattsu:BAABLgAECn8ZAAMEAAcJwRIPPgA4AQAEAAcJ/hEPPgA4AQAOAAUJDxAELQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgIJAgABLgAFFAMJBwAKAGoTAA==.Demonius:BAAALgADCgMJAwABLgAECgkJCQAGAAAAAA==.Derangedxo:BAACLgAFFH8fAAQEAAgJrxtJAACPAgAEAAcJrB5JAACPAgAOAAUJ5RDOAQC9AQAPAAEJAACJAwBeAAAuAAQKfx0AAwQACQk+Jp4CAJsDAAQACQk+Jp4CAJsDAA4AAwmgI+wlAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgARAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDAAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAABLgAECn8VAAINAAcJWwpyGgAoAQANAAcJWwpyGgAoAQAAAA==.',
En='Enana:BAAALgAECgYJCgAAAA==.Enkor:BAABLgAECn8bAAIDAAgJShQhHQDxAQADAAgJShQhHQDxAQAAAA==.',
Ev='Everblack:BAABLgAECn8rAAIOAAgJih37AABmAgAOAAgJih37AABmAgAAAA==.Evilcretin:BAACLgAFFH8IAAIKAAMJ/xy0JwAUAQAKAAMJ/xy0JwAUAQAuAAQKfyMAAgoABQnKJaEqALoBAAoABQnKJaEqALoBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Faraah:BAABLgAECn8vAAMSAAkJXR4aAQCuAgASAAkJXR4aAQCuAgATAAEJ0gTm2wAnAAAAAA==.',
Fl='Florleesa:BAAALgADCgYJBgAAAA==.Flowstate:BAABLgAFFH8HAAIQAAQJHg0LEQAQAQAQAAQJHg0LEQAQAQAAAA==.',
Fr='Friérén:BAACLgAFFH8HAAIKAAMJahMXMgAEAQAKAAMJahMXMgAEAQAuAAQKfyEAAwoACAkrHqNSAEACAAoACAkrHqNSAEACABQAAQm4BSshACkAAAAA.',
Ga='Garhkanis:BAAALgADCgYJBgAAAA==.Garro:BAACLgAFFH8FAAIVAAMJVBLkEAAAAQAVAAMJVBLkEAAAAQAuAAQKfxkAAhUACAkDHtIbAG4CABUACAkDHtIbAG4CAAAA.',
Ge='Genjidh:BAABLgAECn8cAAQBAAgJyh/xGQCaAQABAAYJwxvxGQCaAQACAAQJGyLqJgCJAQAWAAUJFR5TDwBdAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAAALgAFFAIJAwAAAA==.Grimdark:BAABLgAECn8aAAIXAAYJ5RGuUABCAQAXAAYJ5RGuUABCAQAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAECgYJCwAAAA==.Grumpypants:BAABLgAECn8bAAIMAAcJjBP4CwD+AAAMAAcJjBP4CwD+AAAAAA==.Grunge:BAACLgAFFH8HAAMEAAQJGgTgKgD1AAAEAAQJGgTgKgD1AAAOAAEJWADcEQAmAAAuAAQKfyAABA4ACAkMFtcjADoBAA4ABQmhENcjADoBAAQABwmGFoFNAAgBAA8AAQk4GsUtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAIKAAgJMCGiIgDoAgAKAAgJMCGiIgDoAgAAAA==.',
Ha='Haven:BAABLgAECn8hAAILAAgJkh/3CQDjAgALAAgJkh/3CQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn8dAAIYAAgJJRrCAAApAgAYAAgJJRrCAAApAgAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Ho='Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgADCgYJBgAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAAALgAFFAEJAQAAAA==.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Inmelancholy:BAAALgAECgEJAQAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8cAAIXAAgJ5g9HHgBxAQAXAAgJ5g9HHgBxAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8SAAMEAAYJ6xdOEABeAQAEAAQJ/hROEABeAQAOAAMJIhtfBgAKAQAuAAQKfx4ABA8ACAnHIi4FABsCAAQABwm6IaodAKQCAA8ABQlrJS4FABsCAA4AAgkYG1lEAKQAAAAA.Jamboni:BAAALgAECgMJBAAAAA==.Jarmamathu:BAAALgAECgYJCQAAAA==.Jay:BAAALgAECgQJBQABLgAFFAEJAQAGAAAAAA==.',
Jo='Joje:BAABLgAECn8YAAMEAAYJ4BSgNQBUAQAEAAYJ4BSgNQBUAQAOAAIJVgmkWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgADCgYJCwAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAgAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAAALgAECgkJCQAAAA==.Keora:BAABLgAECn8aAAIZAAgJYxCoEwBmAQAZAAgJYxCoEwBmAQAAAA==.',
Kh='Khronos:BAAALgAECggJDgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAAALgAFFAIJAgAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Kronik:BAAALgADCgMJAwAAAA==.Krow:BAAALgADCggJGgAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAAALgAECgYJDQAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightsmith:BAABLgAECn8ZAAIHAAgJSB6PGQBGAgAHAAgJSB6PGQBGAgAAAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAECgUJBQAAAA==.Lorez:BAABLgAFFH8OAAIEAAQJHgyDHwAkAQAEAAQJHgyDHwAkAQAAAA==.Low:BAABLgAECn8YAAIEAAYJyRMAPAA/AQAEAAYJyRMAPAA/AQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAAALgAECgcJDwAAAA==.Mageaurora:BAAALgADCgkJDQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCAAAAA==.Mazzh:BAABLgAFFH8FAAMFAAMJOx0TFgAPAQAFAAMJhRcTFgAPAQAaAAIJmxndGQC2AAABLgAFFAgJBwAKAD0mAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgADCggJCwAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJQAr9XgCEAQABAAkJEAr9XgCEAQACAAYJEAlFOwATAQAAAA==.',
Mo='Mortikhan:BAAALgADCgEJAQAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAAALgAECgYJCwAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nighttwister:BAAALgAECgcJEAAAAA==.Nitekiller:BAAALgADCgkJCQAAAA==.',
No='Noctilucent:BAAALgAECgQJBAAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgADCgYJBwAAAA==.Paredes:BAAALgADCgkJDQAAAA==.',
Pe='Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAAALgAFFAEJAgAAAA==.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAMJBwAKAGoTAA==.',
Pr='Pride:BAAALgAECgYJEQAAAA==.Prophesy:BAABLgAECn8iAAIIAAgJlhzBKACCAgAIAAgJlhzBKACCAgAAAA==.Proteus:BAABLgAECn8gAAMbAAgJqRBBYQDPAQAbAAgJqRBBYQDPAQAcAAQJFwy1DgC3AAAAAA==.',
Pu='Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCQAAAA==.',
Re='Reflex:BAAALgAECgUJBQAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAABLgAECn8cAAIbAAgJQQ4tKgCTAQAbAAgJQQ4tKgCTAQAAAA==.',
Rh='Rhaena:BAAALgADCgEJAQABLgAFFAYJGAAEAPgaAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Runninscared:BAAALgAECgkJCQAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJCQAAAA==.',
Se='Senada:BAABLgAECn8VAAIKAAYJzQKQjAC5AAAKAAYJzQKQjAC5AAAAAA==.Senkait:BAABLgAECn8WAAMRAAcJiRkJDQDMAQARAAcJiRkJDQDMAQAXAAUJWh3LOQCbAQAAAA==.',
Sh='Shamoura:BAACLgAFFH8YAAIRAAYJFRpRAQAXAgARAAYJFRpRAQAXAgAuAAQKfx0AAhEACAmcIy0JAP8CABEACAmcIy0JAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulszaura:BAACLgAFFH8XAAIIAAYJrBJ5BgCBAQAIAAYJrBJ5BgCBAQAuAAQKfywAAggACQkeIgoSAAIDAAgACQkeIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8HAAIBAAMJ0xeYHAD6AAABAAMJ0xeYHAD6AAAuAAQKfygAAgEACQmPHQ8HAGoCAAEACQmPHQ8HAGoCAAAA.Steampunk:BAAALgAFFAEJAQAAAA==.',
Sw='Swade:BAABLgAECn8YAAIQAAYJxwpHIQD5AAAQAAYJxwpHIQD5AAAAAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAMJBwAKAGoTAA==.Synarri:BAACLgAFFH8PAAMHAAQJMxr7CABdAQAHAAQJMxr7CABdAQAIAAEJYAe8RwBIAAAuAAQKfyYAAwgACQnkHuwEAMwCAAgACQnkHuwEAMwCAAcACQmPGt8NAKkCAAEuAAUUBgkXAAcA+BkA.Syneria:BAACLgAFFH8XAAMHAAYJ+BkDAQAZAgAHAAYJ+BkDAQAZAgAIAAEJ6QG5SgA/AAAuAAQKfzoAAwcACAnoIEgLAMQCAAcACAnoIEgLAMQCAAgACAmRHPAsAHACAAAA.Synpai:BAABLgAECn8hAAMHAAkJQBUCLADXAQAHAAcJLhQCLADXAQAIAAYJOxsiYADEAQABLgAFFAYJFwAHAPgZAA==.',
Ta='Taccitus:BAACLgAFFH8RAAIBAAUJnRYOEgAxAQABAAUJnRYOEgAxAQAuAAQKfyQAAgEACAkgIkIdAKICAAEACAkgIkIdAKICAAAA.Tailzz:BAAALgAECgEJAgAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.',
Te='Teach:BAAALgAFFAEJAQAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAAALgAECgYJEQAAAA==.',
Ti='Tiazy:BAAALgADCgQJBAAAAA==.',
To='Toomato:BAAALgAECgQJAwAAAA==.Totemterror:BAEBLgAECn8gAAIXAAgJwiWvAABrAwAXAAgJwiWvAABrAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Ty='Tydradul:BAABLgAECn8hAAIEAAgJqhQzGQDfAQAEAAgJqhQzGQDfAQAAAA==.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn8hAAITAAgJPh37CQBqAgATAAgJPh37CQBqAgAAAA==.Valy:BAAALgAECgUJDQAAAA==.',
Ve='Veladria:BAACLgAFFH8FAAIbAAMJ4x/IKQAWAQAbAAMJ4x/IKQAWAQAuAAQKfxcAAhsABwm1G2paAOIBABsABwm1G2paAOIBAAAA.Vellion:BAAALgADCgYJCAAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAABLgAECn8XAAIBAAYJvSOEJQBxAgABAAYJvSOEJQBxAgAAAA==.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAYJEgAEAOsXAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBgABLgAECgkJCQAGAAAAAA==.',
Wi='Wikkid:BAABLgAECn8eAAINAAYJAwpNJADfAAANAAYJAwpNJADfAAAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgMJAwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.',
Yi='Yiesus:BAAALgAFFAQJBAABLgAFFAYJGAABAMEkAA==.',
Ym='Ymir:BAABLgAECn8cAAMOAAgJjxP7DQDnAQAOAAgJjxP7DQDnAQAEAAQJDgSA4wCTAAAAAA==.',
Yo='Yomato:BAABLgAECn8tAAITAAgJbB9cBgCyAgATAAgJbB9cBgCyAgAAAA==.',
Yp='Yppah:BAABLgAECn8aAAIRAAgJtA0sGABRAQARAAgJtA0sGABRAQAAAA==.',
Yu='Yuhmato:BAAALgAECgUJBwAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQdAAgJIBBnKwCaAQAdAAcJThFnKwCaAQAeAAMJJAg6MQBPAAALAAEJhwpRYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8QAAIBAAUJNR9tCwBaAQABAAUJNR9tCwBaAQAuAAQKfyMAAgEACAmGIxwNABcDAAEACAmGIxwNABcDAAAA.',
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

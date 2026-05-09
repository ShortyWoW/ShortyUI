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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Monk-Windwalker','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Shaman-Enhancement','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','Warrior-Protection','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8QAAIBAAYJQBJSCwB8AQABAAYJQBJSCwB8AQAuAAQKfxwAAwEACAm2HBgkALABAAEACAkcGxgkALABAAIABwnaGMcjAJ8BAAAA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAcJHwADAM0YAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8bAAIEAAgJaiBYDQBxAgAEAAgJaiBYDQBxAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJBgAFAAAAAA==.Alius:BAAALgADCgQJBgAAAA==.',
Am='Ambellina:BAACLgAFFH8GAAIGAAIJCxyoHQCyAAAGAAIJCxyoHQCyAAAuAAQKfycAAwYACAkYG4YUAG4CAAYACAkYG4YUAG4CAAcABAnmCgiJANoAAAAA.Amp:BAAALgAECgEJAQABLgAFFAQJDgAIAFcQAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.',
Au='Auxiliry:BAAALgADCgEJAQAAAA==.',
Av='Avenger:BAABLgAFFH8FAAIHAAQJRRgYEQBiAQAHAAQJRRgYEQBiAQABLgAFFAcJIQAJAFQhAA==.',
Ay='Aythrior:BAAALgAECgYJCgAAAA==.',
Be='Beefycrits:BAACLgAFFH8IAAIKAAMJLCaNLgBMAQAKAAMJLCaNLgBMAQAuAAQKfyEAAgoACAkpJL8XABwDAAoACAkpJL8XABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgIJAgAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Capriestson:BAABLgAECn8dAAILAAgJ2hUeEADOAQALAAgJ2hUeEADOAQAAAA==.Cardrin:BAABLgAECn8gAAMMAAkJUw7lDAA/AQAMAAkJUw7lDAA/AQANAAYJ4gPhWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8WAAIOAAUJkhV1AgCPAQAOAAUJkhV1AgCPAQAuAAQKfx8AAg4ACAm+IhsIAPgCAA4ACAm+IhsIAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8LAAIKAAUJbSHTFwCAAQAKAAUJbSHTFwCAAQAAAA==.',
Cl='Clearance:BAABLgAFFH8GAAIPAAQJ8xA7FQA0AQAPAAQJ8xA7FQA0AQABLgAFFAcJFwADALYaAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgMJBgAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAgAFAAAAAA==.',
Da='Daemon:BAACLgAFFH8fAAQDAAcJzRiGCACgAQADAAYJfxKGCACgAQAQAAQJXhCYBgC2AAARAAEJLx/oBgBZAAAuAAQKfy4ABAMACQmdI/MSAOQCAAMACQkgI/MSAOQCABEABAlOIb0NAFgBABAAAwk5FI0xAPMAAAAA.Dalekin:BAAALgAFFAEJAQAAAA==.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAAALgAECgcJDAAAAA==.Dattsu:BAABLgAECn8aAAMDAAcJwRLpQgBgAQADAAcJ/hHpQgBgAQAQAAUJDxACLQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgUJCQABLgAFFAMJCQAKAG0TAA==.Demonius:BAAALgADCgMJAwABLgAECgkJCgAFAAAAAA==.Derangedxo:BAACLgAFFH8nAAQDAAkJUBtJAACPAgADAAgJ0h1JAACPAgAQAAUJ5RDPAQC9AQARAAEJAACMAwBeAAAuAAQKfx0AAwMACQk+Jp8CAJsDAAMACQk+Jp8CAJsDABAAAwmgI+glAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgASAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAABLgAECn8cAAINAAcJLQs3IgAnAQANAAcJLQs3IgAnAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIOAAgJShQfHQDxAQAOAAgJShQfHQDxAQAAAA==.',
Ev='Everblack:BAABLgAECn8tAAIQAAgJiB2dAQBfAgAQAAgJiB2dAQBfAgAAAA==.Evilcretin:BAACLgAFFH8JAAIKAAMJ/xy5JwAUAQAKAAMJ/xy5JwAUAQAuAAQKfykAAgoABgn0IwcmAAwCAAoABgn0IwcmAAwCAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Faraah:BAABLgAECn84AAMTAAkJcCBkAQDWAgATAAkJcCBkAQDWAgAUAAEJ0gTr2wAnAAAAAA==.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8OAAIIAAQJVxCiFAAeAQAIAAQJVxCiFAAeAQAAAA==.',
Fr='Friérén:BAACLgAFFH8JAAIKAAMJbRPMLwD2AAAKAAMJbRPMLwD2AAAuAAQKfyEAAwoACAkrHplSAEACAAoACAkrHplSAEACABUAAQm4BSwhACkAAAAA.',
Ga='Garhkanis:BAAALgAECgYJCwAAAA==.Garro:BAACLgAFFH8HAAIWAAMJqRWnFwDzAAAWAAMJqRWnFwDzAAAuAAQKfx4AAhYACAkDHs8bAG4CABYACAkDHs8bAG4CAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Genjidh:BAABLgAECn8cAAQBAAgJyh9FKQCVAQABAAYJwxtFKQCVAQACAAQJGyLuJgCJAQAXAAUJFR5RDwBdAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAABLgAFFH8FAAIPAAIJGBBJKwCdAAAPAAIJGBBJKwCdAAAAAA==.Grimdark:BAABLgAECn8dAAIYAAYJ5RENNwAtAQAYAAYJ5RENNwAtAQAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAECgYJCwAAAA==.Grumpypants:BAABLgAECn8jAAIMAAgJuxU2CgB6AQAMAAgJuxU2CgB6AQAAAA==.Grunge:BAACLgAFFH8HAAMDAAQJGgQHPwDeAAADAAQJGgQHPwDeAAAQAAEJWADoFwAkAAAuAAQKfyIABAMACQnTFR05AIEBAAMACAk0Fh05AIEBABAABQmhENIjADoBABEAAQk4GsMtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAIKAAgJMCGiIgDoAgAKAAgJMCGiIgDoAgAAAA==.',
Ha='Haven:BAABLgAECn8hAAILAAgJkh/2CQDjAgALAAgJkh/2CQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn8hAAIZAAgJ8BsOAQAyAgAZAAgJ8BsOAQAyAgAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Ho='Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgADCgYJBgAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAAALgAFFAIJAwAAAA==.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8eAAIYAAgJ2hCqKQB1AQAYAAgJ2hCqKQB1AQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8UAAMDAAcJOBZSEABeAQADAAQJ/RRSEABeAQAQAAQJyRdjBgAKAQAuAAQKfx8ABBEACAn5Ii4FABsCAAMABwnsIakdAKQCABEABQlrJS4FABsCABAAAgkYG1xEAKQAAAAA.Jamboni:BAAALgAECgQJBgAAAA==.Jarmamathu:BAAALgAECgcJCgAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJBgAAAA==.',
Jo='Joje:BAABLgAECn8aAAMDAAcJyBXGLgCoAQADAAcJyBXGLgCoAQAQAAIJVgmhWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgADCgYJCwAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAAALgAECgkJDQAAAA==.Keora:BAABLgAECn8cAAIPAAgJ7hCvGAB7AQAPAAgJ7hCvGAB7AQAAAA==.',
Kh='Khronos:BAAALgAECggJEQAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAAALgAFFAIJBAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Kronik:BAAALgADCgYJCQAAAA==.Krow:BAAALgADCggJGgAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAAALgAECgYJDQAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBQAAAA==.Lightsmith:BAABLgAECn8cAAIGAAgJ7yGNGQBGAgAGAAgJ7yGNGQBGAgAAAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAQAAAA==.Lorez:BAABLgAFFH8RAAIDAAUJmwypMQAIAQADAAUJmwypMQAIAQAAAA==.Low:BAABLgAECn8eAAIDAAYJDRn4PgBtAQADAAYJDRn4PgBtAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8WAAIaAAgJpwfiCwBMAQAaAAgJpwfiCwBMAQAAAA==.Mageaurora:BAAALgAECgEJAQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Mazzh:BAABLgAFFH8FAAMEAAMJOx0rJgD/AAAEAAMJhRcrJgD/AAAbAAIJmxnkGQC2AAABLgAFFAgJBwAKAD0mAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgADCggJCwAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJQAr+XgCEAQABAAkJEAr+XgCEAQACAAYJEAlGOwATAQAAAA==.',
Mo='Moobie:BAAALgADCgYJCAAAAA==.Mortikhan:BAAALgAECgIJAgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAAALgAECgcJDwAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nighttwister:BAAALgAECgcJEgAAAA==.Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAQAAAA==.',
No='Noctilucent:BAAALgAECgQJBAAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgADCgYJBwAAAA==.Paredes:BAAALgAECgEJAQAAAA==.',
Pe='Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAABLgAECn8UAAIcAAgJXx/TGQAwAgAcAAgJXx/TGQAwAgABLgAFFAUJEwADAO8fAA==.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAMJCQAKAG0TAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8YAAIaAAgJfxjNBwCxAQAaAAgJfxjNBwCxAQAAAA==.Prophesy:BAABLgAECn8jAAIHAAgJlhzBKACCAgAHAAgJlhzBKACCAgAAAA==.Proteus:BAABLgAECn8gAAMcAAgJqRA8YQDPAQAcAAgJqRA8YQDPAQAdAAQJFwy1DgC3AAAAAA==.',
Pu='Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECgYJBwAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAABLgAECn8eAAIcAAgJPw+DNwCbAQAcAAgJPw+DNwCbAQAAAA==.',
Rh='Rhaena:BAAALgADCgEJAQABLgAFFAcJHwADAM0YAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAAALgAECgkJCgAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJCgAAAA==.',
Se='Senada:BAABLgAECn8cAAIKAAcJjwPFjwDzAAAKAAcJjwPFjwDzAAAAAA==.Senkait:BAABLgAECn8eAAMSAAgJ7Bg1DQAJAgASAAgJ7Bg1DQAJAgAYAAYJthvMOQCbAQAAAA==.',
Sh='Shamoura:BAACLgAFFH8aAAISAAcJ9xdTAQAXAgASAAcJ9xdTAQAXAgAuAAQKfx0AAhIACAmcIy8JAP8CABIACAmcIy8JAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shinoa:BAAALgAECgYJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAgAFAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulszaura:BAACLgAFFH8cAAIHAAYJ4B9mAwDaAQAHAAYJ4B9mAwDaAQAuAAQKfywAAgcACQkeIgcSAAIDAAcACQkeIgcSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8LAAIBAAQJwRNJIAAsAQABAAQJwRNJIAAsAQAuAAQKfygAAgEACQmPHbwMAGgCAAEACQmPHbwMAGgCAAAA.Steampunk:BAABLgAECn8UAAIKAAcJzQ/bZABIAQAKAAcJzQ/bZABIAQAAAA==.',
Sw='Swade:BAABLgAECn8YAAIIAAYJxwonLADuAAAIAAYJxwonLADuAAABLgAECgcJDAAFAAAAAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAMJCQAKAG0TAA==.Synarri:BAACLgAFFH8PAAMGAAQJMxqpDgBDAQAGAAQJMxqpDgBDAQAHAAEJYAfLXwBIAAAuAAQKfy8AAwcACQnFIUUDACUDAAcACQnFIUUDACUDAAYACQmPGt4NAKkCAAEuAAUUBwkZAAYAOBgA.Syneria:BAACLgAFFH8ZAAMGAAcJOBgEAQAZAgAGAAcJOBgEAQAZAgAHAAEJ6QGgYwA/AAAuAAQKfzsAAwYACAnpIEgLAMQCAAYACAnpIEgLAMQCAAcACAm6HO4sAHACAAAA.Synn:BAAALgAFFAEJAQABLgAFFAcJGQAGADgYAA==.Synpai:BAACLgAFFH8GAAMGAAQJjxR3EAAxAQAGAAQJjxR3EAAxAQAHAAEJfws2XQBMAAAuAAQKfyEAAwYACQlAFQIsANcBAAYABwkuFAIsANcBAAcABgk7GyFgAMQBAAEuAAUUBwkZAAYAOBgA.',
Ta='Taccitus:BAACLgAFFH8WAAIBAAUJ8RjpDwBPAQABAAUJ8RjpDwBPAQAuAAQKfykAAwEACQliIT8dAKICAAEACQliIT8dAKICAAIAAgltGTwpAJYAAAAA.Tailzz:BAAALgAECgUJBgAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAECgEJAQAAAA==.',
Te='Teach:BAABLgAECn8YAAMPAAYJaRewIwApAQAPAAQJGBmwIwApAQAeAAYJ3QswKwAZAQAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAABLgAECn8WAAIfAAYJ0hZ9FQAbAQAfAAYJ0hZ9FQAbAQAAAA==.',
Ti='Tiazy:BAAALgADCgQJCAAAAA==.',
To='Toomato:BAAALgAECgQJBgAAAA==.Totemterror:BAEBLgAECn8jAAIYAAkJKyYiAADiAwAYAAkJKyYiAADiAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgADCgIJAgAAAA==.',
Ty='Tydradul:BAABLgAECn8iAAIDAAgJKRVCIwDgAQADAAgJKRVCIwDgAQAAAA==.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn8sAAIUAAgJyx1VDACGAgAUAAgJyx1VDACGAgAAAA==.Valy:BAAALgAECgUJDQAAAA==.',
Ve='Veladria:BAACLgAFFH8KAAIcAAQJORkWKABPAQAcAAQJORkWKABPAQAuAAQKfxcAAhwABwm1G15aAOIBABwABwm1G15aAOIBAAAA.Vellion:BAAALgADCgYJCAAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAABLgAECn8XAAIBAAYJvSN/JQBxAgABAAYJvSN/JQBxAgAAAA==.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJFAADADgWAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBgABLgAECgkJCgAFAAAAAA==.',
Wi='Wikkid:BAABLgAECn8vAAINAAcJnw7AHQBHAQANAAcJnw7AHQBHAQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgMJAwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Yi='Yiesus:BAABLgAFFH8HAAILAAQJ+Qt1DQA0AQALAAQJ+Qt1DQA0AQABLgAFFAcJHwABAPoiAA==.',
Ym='Ymir:BAABLgAECn8cAAMQAAgJjxP8DQDnAQAQAAgJjxP8DQDnAQADAAQJDgSM4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8GAAIUAAIJHBPIMACFAAAUAAIJHBPIMACFAAAuAAQKfy8AAhQACAlsHxsKAKcCABQACAlsHxsKAKcCAAAA.',
Yp='Yppah:BAABLgAECn8dAAISAAkJTw6+FgCcAQASAAkJTw6+FgCcAQAAAA==.',
Yu='Yuhmato:BAAALgAFFAIJAgAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQgAAgJIBBqKwCaAQAgAAcJThFqKwCaAQAhAAMJJAg9PwBPAAALAAEJhwpQYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8VAAIBAAYJLx1xCAC2AQABAAYJLx1xCAC2AQAuAAQKfyMAAgEACAmGIxgNABcDAAEACAmGIxgNABcDAAAA.',
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

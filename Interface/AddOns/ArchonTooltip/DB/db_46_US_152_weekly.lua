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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Paladin-Holy','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Hunter-Survival','Shaman-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Protection','Evoker-Devastation','Druid-Guardian',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaylasecura:BAABLgAECn8lAAIBAAkJwB1AAQDhAgABAAkJwB1AAQDhAgAAAA==.',
Ab='Absolutezero:BAABLgAECn8jAAMCAAgJgR/yCwCGAgACAAgJZB/yCwCGAgADAAIJ7hb4FAB3AAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAABLgAECn8tAAMEAAkJcht3BAAuAgAEAAkJcht3BAAuAgAFAAEJaQVpSgAtAAAAAA==.Alexjuander:BAAALgAECggJBQAAAA==.Alphard:BAABLgAECn8gAAMGAAcJBR3sCQDLAQAGAAcJBR3sCQDLAQAHAAEJvBvSHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8gAAIIAAcJ/xjtGgAHAgAIAAcJ/xjtGgAHAgAAAA==.',
Ap='Apocal:BAACLgAFFH8MAAIJAAUJmxjWAABNAQAJAAUJmxjWAABNAQAuAAQKfxQAAgkACAmnG3gGACsCAAkACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Arete:BAAALgAECgYJEQAAAA==.Artaimya:BAAALgAECgYJCwAAAA==.Artemìs:BAAALgADCggJEQAAAA==.',
At='Atmosphere:BAAALgAECgUJBQAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgUJBQAKAAAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAECggJIwACAGsWAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgQJBQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgQJBAAAAA==.Basutai:BAAALgAECgkJEQAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgQJBAAAAA==.Birgetta:BAABLgAECn8hAAMLAAgJkgnKTgB8AQALAAgJkgnKTgB8AQAMAAYJbgMzEgCvAAAAAA==.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIEAAgJNhlGDABxAgAEAAgJNhlGDABxAgAAAA==.Blasphemous:BAAALgAECgEJAgAAAA==.Blee:BAABLgAECn8YAAINAAgJNBtWCQCCAQANAAgJNBtWCQCCAQAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAAKAAAAAA==.',
Bo='Bobodaklown:BAABLgAECn8hAAIOAAkJYRaIFQAOAgAOAAkJYRaIFQAOAgAAAA==.Boomnblood:BAAALgADCgEJAQABLgAECggJIwAPAA4NAA==.Boomnbrew:BAABLgAECn8jAAIPAAgJDg1DEwBuAQAPAAgJDg1DEwBuAQAAAA==.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8XAAMMAAgJWQzlDAD/AAAMAAcJAArlDAD/AAALAAMJThQfVgDIAAAAAA==.',
Br='Brewman:BAABLgAECn8mAAMQAAkJ9hliCgAGAgAQAAYJcR1iCgAGAgAPAAgJ3A2BFABgAQAAAA==.',
Bu='Bubonic:BAABLgAECn8bAAIRAAgJlBZfHQDXAQARAAgJlBZfHQDXAQAAAA==.Buenasalud:BAABLgAECn8YAAISAAcJcxtuCAAkAgASAAcJcxtuCAAkAgAAAA==.',
Ca='Caylea:BAACLgAFFH8NAAITAAQJyg1tCgBCAQATAAQJyg1tCgBCAQAuAAQKfycAAhMACAlZHPoGAEECABMACAlZHPoGAEECAAAA.',
Ch='Chalis:BAABLgAECn8ZAAMUAAcJ/xu/CgATAgAUAAYJ5h2/CgATAgAVAAUJwxRipAAPAQAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAAALgAFFAEJAQAAAA==.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAABLgAECn8oAAMCAAkJWBAxHwDxAQACAAkJWBAxHwDxAQAWAAEJugNhEQArAAAAAA==.Corvus:BAAALgAECgQJCAAAAA==.',
Cr='Crowdcontrol:BAAALgAECgYJEQAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAABLgAECn8oAAMXAAkJjxC3BQDKAQAXAAkJWA63BQDKAQAYAAIJ+BC4KABAAAAAAA==.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAAALgAECgMJAwAAAA==.Daelin:BAABLgAECn8gAAIOAAcJlSOSCwBtAgAOAAcJlSOSCwBtAgAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darknous:BAAALgADCgMJAwAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAAALgADCgMJAwAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathrite:BAAALgAECgcJDgAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCQAAAA==.Demo:BAAALgAECgQJBgABLgAFFAEJAQAKAAAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAABLgAECn8iAAIZAAgJqRIKDwCyAQAZAAgJqRIKDwCyAQAAAA==.',
Dh='Dhchin:BAAALgAECgEJAQABLgAFFAQJCgAGAOgZAA==.Dhomsak:BAAALgAECgUJBQABLgAFFAUJEAACAJoiAA==.',
Di='Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgUJBQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQAAAA==.',
Do='Doadin:BAABLgAECn8qAAMaAAkJnhsLAwDcAgAaAAkJnhsLAwDcAgAOAAEJ1gG/XQEgAAAAAA==.Doominatrix:BAABLgAECn8hAAMVAAgJxBEDJQCcAQAVAAcJxBEDJQCcAQAbAAEJAAClKgBKAAAAAA==.',
Dr='Draggum:BAAALgAFFAEJAQAAAA==.Dreadraven:BAABLgAECn87AAMTAAgJ9RKVJgAmAgATAAgJ9RKVJgAmAgAXAAEJZAQNMgAnAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8cAAMBAAcJPRZnIQCxAQABAAcJFBVnIQCxAQAcAAcJhhGVNwAEAQABLgAECgEJAQAKAAAAAA==.Dreddstorm:BAAALgADCgcJDQAAAA==.Drewuw:BAABLgAECn8aAAIdAAgJ3BWGGQAVAgAdAAgJ3BWGGQAVAgAAAA==.Druidhams:BAABLgAECn8jAAIeAAgJ8x2xCQBvAgAeAAgJ8x2xCQBvAgAAAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgQJBQAAAA==.Elisha:BAABLgAECn8yAAIOAAkJAhXpEwAbAgAOAAkJAhXpEwAbAgAAAA==.Elsyra:BAAALgADCgcJCQAAAA==.',
Er='Erebostro:BAABLgAECn8gAAILAAcJKRoyHAC2AQALAAcJKRoyHAC2AQAAAA==.',
Ev='Evillux:BAABLgAECn8mAAMVAAkJBRBaLgBzAQAVAAgJBw5aLgBzAQAUAAUJ5gx/KgAXAQAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMcAAkJ+huaJwBmAgAcAAkJBxmaJwBmAgABAAQJ+h+uNgAsAQAAAA==.',
Fa='Fathercow:BAABLgAECn8hAAIfAAgJNB5XAwCyAgAfAAgJNB5XAwCyAgAAAA==.',
Fi='Fingies:BAABLgAECn8rAAMVAAkJ1B9KBQDAAgAVAAcJnyBKBQDAAgAUAAUJBh1KFQCgAQAAAA==.Fistin:BAAALgAECgQJBQAAAA==.',
Fu='Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAABLgAECn8iAAMLAAgJCh3gJAApAgALAAgJCh3gJAApAgAgAAUJlA2DFwACAQAAAA==.',
Ga='Gaijin:BAAALgADCgMJAwABLgAECgkJKgAfAMMdAA==.Galaxsea:BAABLgAECn8UAAIdAAcJMh1DCQDlAQAdAAcJMh1DCQDlAQAAAA==.',
Ge='Gerthquake:BAABLgAECn8YAAMhAAcJYCDAJgD4AQAhAAYJkB/AJgD4AQAZAAYJxRjNFQBnAQAAAA==.',
Gf='Gfour:BAABLgAECn8cAAIQAAgJqBpwEwAwAgAQAAgJqBpwEwAwAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAAALgAECgIJAgAAAA==.Goodytwoshoe:BAAALgAECgIJBQAAAA==.',
Gr='Grimmreefer:BAAALgAECgQJBAAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgMJBQAAAA==.',
He='Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAAALgAECgYJEAABLgAFFAUJEAACAJoiAA==.Homsorc:BAACLgAFFH8QAAMCAAUJmiLcBwDlAQACAAUJmiLcBwDlAQADAAEJLCQwAQBtAAAuAAQKfyMAAgIACQlIJTMFAK8DAAIACQlIJTMFAK8DAAAA.Homtard:BAABLgAFFH8LAAMMAAUJkCJ/AwBxAQAMAAUJlSF/AwBxAQAgAAQJPBivAwBnAQABLgAFFAUJEAACAJoiAA==.Hope:BAABLgAECn8oAAIaAAkJgxZqDQADAgAaAAkJgxZqDQADAgAAAA==.',
Id='Idun:BAAALgAECgMJAwAAAA==.',
Il='Illiandray:BAABLgAECn8hAAMUAAgJ6xQ3BQB5AQAUAAcJPBU3BQB5AQAVAAgJTwpqOQBIAQAAAA==.Ilswyn:BAAALgADCgMJAwABLgAECgcJGgAcAPQjAA==.',
Im='Imu:BAACLgAFFH8FAAIgAAMJvB0wBwAnAQAgAAMJvB0wBwAnAQAuAAQKfxkABCAABwm2Ig4EAEwCACAABwm2Ig4EAEwCAAwABQk/Dc9UAPYAAAsAAgmLCtKnAHYAAAEuAAUUBAkOAA4AcCUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn8aAAIcAAcJ9CMrBwBpAgAcAAcJ9CMrBwBpAgAAAA==.',
Io='Ionise:BAAALgAECgkJEgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Isklar:BAACLgAFFH8HAAINAAIJIhySDgC4AAANAAIJIhySDgC4AAAuAAQKfy8AAg0ACAm5I4QEAAIDAA0ACAm5I4QEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAAALgAECgYJEQAAAA==.',
Je='Jer:BAABLgAECn8cAAIGAAkJ1BA/CgDFAQAGAAkJ1BA/CgDFAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAECgkJKgAfAMMdAA==.',
Ka='Kairi:BAAALgAECgYJBgAAAA==.Kammo:BAACLgAFFH8FAAIRAAMJzyANKAAdAQARAAMJzyANKAAdAQAuAAQKfy0AAhEACQkLI6oBAD8DABEACQkLI6oBAD8DAAAA.Kazypher:BAAALgAECgEJAQAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIQAAkJCQf0MQAvAQAQAAkJCQf0MQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAECgkJKgAfAMMdAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8OAAIMAAUJZBcGBQBMAQAMAAUJZBcGBQBMAQAuAAQKfx0AAgwABwnHIVcYAGYCAAwABwnHIVcYAGYCAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwikin:BAABLgAECn8gAAICAAcJ8BqLVQA3AgACAAcJ8BqLVQA3AgABLgAFFAEJAQAKAAAAAA==.',
Ky='Kyreen:BAAALgAECgYJEgAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgcJFAAdADIdAA==.',
La='Laaz:BAABLgAECn8jAAIcAAkJIQ6QMAAhAQAcAAkJIQ6QMAAhAQAAAA==.Lamalen:BAABLgAECn8UAAIOAAcJnRoTYQDBAQAOAAcJnRoTYQDBAQAAAA==.Lasercow:BAAALgADCgQJBAABLgAECggJIQAfADQeAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Linthvia:BAAALgAECgQJBQAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgADCgIJAgAAAA==.',
Lu='Luciuos:BAAALgAECgcJEwAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECggJGgAdANwVAA==.Lukafox:BAACLgAFFH8UAAIhAAYJ3Bx2AQADAgAhAAYJ3Bx2AQADAgAuAAQKfyAAAyEACQlZH6cHAPoCACEACQlZH6cHAPoCABkAAQmKAnqWAB0AAAAA.Lunastarvale:BAABLgAECn8hAAILAAgJlRmcEAARAgALAAgJlRmcEAARAgAAAA==.Luscinia:BAAALgADCgEJAQAAAA==.',
Ma='Madith:BAAALgAFFAEJAQAAAA==.Magicjamo:BAAALgAECgUJBQAAAA==.Malefisico:BAABLgAECn8UAAMVAAcJORHAbQCFAQAVAAcJORHAbQCFAQAUAAEJAAB/eAArAAAAAA==.Malgarok:BAABLgAECn8lAAIVAAgJVxydHgCfAgAVAAgJVxydHgCfAgABLgAECgYJEAAKAAAAAA==.Mardríft:BAABLgAECn8vAAIiAAkJNR2HAwCUAgAiAAkJNR2HAwCUAgAAAA==.Mazga:BAABLgAECn8aAAIjAAcJ/RLqBgCVAQAjAAcJ/RLqBgCVAQAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8dAAIgAAgJCRQKBwD6AQAgAAgJCRQKBwD6AQAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgADCgcJBwAAAA==.Mezoti:BAAALgAECggJDgAAAA==.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCggJCAAAAA==.',
Mo='Moji:BAABLgAECn8hAAIQAAgJUhYDGgDrAQAQAAgJUhYDGgDrAQAAAA==.Monstermayi:BAABLgAECn8jAAITAAgJ+Q96DwDBAQATAAgJ+Q96DwDBAQAAAA==.Mooknight:BAABLgAECn8gAAINAAcJHhAoEQAHAQANAAcJHhAoEQAHAQAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIdAAgJWxqzBwAKAgAdAAgJWxqzBwAKAgAAAA==.',
Mu='Muggy:BAABLgAECn8XAAIHAAgJOgwwBQB1AQAHAAgJOgwwBQB1AQAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAAALgAECgQJBwAAAA==.Mytastical:BAABLgAECn8jAAICAAgJaxZAQwBlAQACAAgJaxZAQwBlAQAAAA==.',
['Mæ']='Mæve:BAABLgAECn8oAAMeAAkJthgGCgBqAgAeAAkJthgGCgBqAgAiAAUJERAbRgAVAQAAAA==.',
Na='Namalis:BAABLgAECn8bAAQVAAcJPSYBOQAoAgAVAAUJdCYBOQAoAgAUAAIJFiKfPADCAAAbAAEJAAAwIQBtAAAAAA==.Nanielito:BAABLgAECn8ZAAICAAkJyBoCDACFAgACAAkJyBoCDACFAgAAAA==.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8FAAICAAMJXBVONgD5AAACAAMJXBVONgD5AAAuAAQKfxsAAgIACAndG3A7AIkCAAIACAndG3A7AIkCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nonae:BAABLgAECn8gAAILAAgJix0dEgCnAgALAAgJix0dEgCnAgAAAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.',
Ob='Obiwon:BAAALgADCgcJDwAAAA==.',
Om='Omegá:BAABLgAECn8eAAIkAAgJEROtEgCfAQAkAAgJEROtEgCfAQAAAA==.',
Op='Optìmusprìme:BAABLgAECn8gAAIYAAcJ0BsICAC4AQAYAAcJ0BsICAC4AQAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAABLgAECn8nAAQUAAgJXx7FAgDWAgAUAAcJUiHFAgDWAgAVAAUJmBy/HgC8AQAbAAUJtRzqAwBtAQAAAA==.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAECgIJBAAAAA==.',
Po='Pockets:BAABLgAECn8YAAICAAcJthUQNgCNAQACAAcJthUQNgCNAQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAAALgAECgYJDQAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAABLgAECn8qAAIfAAkJwx33BAByAgAfAAkJwx33BAByAgAAAA==.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJDgAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAFFAEJAQAKAAAAAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAABLgAECn8mAAIkAAkJTBXaDgDXAQAkAAkJTBXaDgDXAQAAAA==.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAAALgAECgQJDAAAAA==.',
Re='Reaper:BAAALgAFFAEJAQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAAALgADCgYJCQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8KAAMGAAQJ6BnKBQBpAQAGAAQJ6BnKBQBpAQAHAAEJzQ73BQBeAAAuAAQKfyQAAwYACAk6JGsEAEkCAAYABwmfJGsEAEkCAAcAAwnpI/8NADoBAAAA.Rokkgar:BAAALgAECgYJEgAAAA==.Roosterr:BAAALgADCgkJEAAAAA==.',
Ru='Ruwazi:BAAALgAECgYJCgAAAA==.',
Sa='Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8ZAAITAAcJLhIDGQBoAQATAAcJLhIDGQBoAQAAAA==.Sehnsucht:BAABLgAECn8oAAMeAAkJLBwKHgBOAgAeAAkJLBwKHgBOAgAiAAEJABqSdgBJAAAAAA==.Serius:BAAALgAECgQJBAABLgAECggJGgAdANwVAA==.',
Sh='Shmadu:BAAALgAECgYJCQAAAA==.Shockk:BAABLgAECn8gAAMZAAkJFxb8CgDqAQAZAAkJFxb8CgDqAQAhAAMJ4AKTigBpAAAAAA==.',
Si='Siovhan:BAAALgAECgUJCgAAAA==.',
Sm='Smóóthbói:BAABLgAECn8bAAICAAgJtxNaKgC7AQACAAgJtxNaKgC7AQAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn8hAAIFAAcJrxOoEgBxAQAFAAcJrxOoEgBxAQAAAA==.Soola:BAAALgAECgcJDwAAAA==.',
Sp='Spoopadin:BAAALgAECgIJBAAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.',
St='Stack:BAAALgAECgQJBwABLgAFFAEJAQAKAAAAAA==.Stompycouch:BAABLgAECn8qAAIZAAgJ3hxFCAAcAgAZAAgJ3hxFCAAcAgAAAA==.Stoned:BAABLgAECn8nAAMaAAkJIh9oBACxAgAaAAkJIh9oBACxAgAOAAMJ3gpwfwCuAAAAAA==.Stonedpriest:BAABLgAECn8ZAAISAAgJ1R8/BwDYAgASAAgJ1R8/BwDYAgAAAA==.',
Su='Sunreaver:BAABLgAECn8kAAIRAAkJwSDQBQDEAgARAAkJwSDQBQDEAgAAAA==.Surtain:BAABLgAECn8XAAIiAAcJoBusHgAKAgAiAAcJoBusHgAKAgAAAA==.',
Sw='Sweetmask:BAAALgAECgYJEAAAAA==.',
Sy='Syl:BAABLgAECn8bAAMLAAcJ5haGMQBLAQALAAYJWhiGMQBLAQAMAAUJUwpTWQDfAAAAAA==.Sylvanäs:BAAALgADCgkJEQABLgAECggJIQAUAOsUAA==.',
Ta='Tahitian:BAAALgAECgcJDwAAAA==.Tahlreth:BAABLgAECn8dAAICAAcJ/B4xJQDSAQACAAcJ/B4xJQDSAQAAAA==.Tanickz:BAABLgAECn8XAAICAAcJxA47PwBwAQACAAcJxA47PwBwAQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJKgAZAPocAA==.Tanidgetotem:BAABLgAECn8qAAIZAAkJ+hwSBACGAgAZAAkJ+hwSBACGAgAAAA==.Tanya:BAABLgAECn8rAAIgAAgJlBvqBgD9AQAgAAgJlBvqBgD9AQAAAA==.Tayanna:BAAALgAECgYJDgAAAA==.',
Te='Teias:BAABLgAECn8mAAMSAAkJzhgWEwBHAgASAAkJzhgWEwBHAgAIAAQJ1hdrRADZAAAAAA==.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwAKAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8XAAICAAgJtR60EQBOAgACAAgJtR60EQBOAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAAKAAAAAA==.',
Tr='Tricko:BAABLgAECn8hAAILAAcJSx6HEwD2AQALAAcJSx6HEwD2AQAAAA==.Trollskingx:BAAALgAECgcJEQAAAA==.Trollzy:BAABLgAECn8gAAMjAAcJ5xzPBQC2AQAjAAcJ5xzPBQC2AQAhAAEJhgMspgApAAAAAA==.Trunkmonkey:BAABLgAECn8VAAIVAAgJDwz/OQBGAQAVAAgJDwz/OQBGAQAAAA==.',
Ts='Tsaagan:BAABLgAECn8iAAQVAAgJiSEDEAAnAgAVAAcJtR4DEAAnAgAbAAQJACP9CgCMAQAUAAQJBx62IABOAQAAAA==.',
Tu='Tucker:BAABLgAECn8iAAIQAAkJ7hjxAwCoAgAQAAkJ7hjxAwCoAgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ul='Ultramagnús:BAAALgADCgEJAQAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAAALgAECgYJDgAAAA==.Under:BAAALgADCgcJDgABLgAECgYJDgAKAAAAAA==.Unparalleled:BAABLgAECn8VAAMlAAYJiAhKCAD+AAAlAAUJiAhKCAD+AAAEAAYJIQdxFQCoAAAAAA==.',
Va='Valkyruid:BAACLgAFFH8NAAIeAAQJABagDwAiAQAeAAQJABagDwAiAQAuAAQKfxcAAh4ABwnCF4o2AM0BAB4ABwnCF4o2AM0BAAAA.',
Vi='Vixus:BAAALgAECgYJEAAAAA==.',
Vx='Vxs:BAAALgAECgcJBwAAAA==.',
['Vø']='Vøødu:BAAALgAECgUJBQAAAA==.',
Wa='Walshidan:BAAALgAECgYJEQAAAA==.Waywatcher:BAAALgAECgUJBgAAAA==.',
Wi='Wiccaflame:BAAALgAFFAEJAQAAAA==.Wiccasham:BAAALgADCgEJAQAAAA==.',
Wu='Wullgan:BAAALgAECggJDwAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAAALgAFFAIJAgAAAA==.',
Xo='Xole:BAABLgAECn8YAAMcAAcJ9BLXbQBaAQAcAAcJ9BLXbQBaAQAJAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8YAAIcAAgJzRyVMAA5AgAcAAgJzRyVMAA5AgABLgAECggJGgAdANwVAA==.',
Ya='Yareli:BAABLgAECn8YAAIJAAgJswT8CQD/AAAJAAgJswT8CQD/AAAAAA==.Yawa:BAAALgAECgEJAQAAAA==.',
Ye='Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQAKAAAAAA==.Zarill:BAAALgADCgcJBwAAAA==.Zazie:BAAALgAECgIJAgAAAA==.',
Ze='Zekröm:BAABLgAECn8UAAImAAkJNw6GDADxAAAmAAkJNw6GDADxAAAAAA==.Zekrøm:BAABLgAECn8VAAIZAAgJ0BnsGQBEAgAZAAgJ0BnsGQBEAgABLgAECgkJFAAmADcOAA==.Zeno:BAABLgAFFH8YAAIOAAYJ0R+VAQDgAQAOAAYJ0R+VAQDgAQAAAA==.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQAKAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQAKAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAAALgAECgYJEgABLgAECgYJEgAKAAAAAA==.',
Zi='Zinbar:BAAALgAECgcJCQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8WAAQdAAcJ2xrLCQDaAQAdAAcJoBrLCQDaAQAPAAQJ9BVWVADzAAAQAAEJTQJpcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQAKAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAICAAgJXCBeLwC1AgACAAgJXCBeLwC1AgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8kAAMfAAgJZyFhBQBkAgAfAAgJZyFhBQBkAgASAAUJABr7OgBPAQAAAA==.',
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

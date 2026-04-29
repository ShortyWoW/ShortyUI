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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Paladin-Holy','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Hunter-Survival','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Druid-Balance','Paladin-Protection','Evoker-Augmentation','Priest-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaylasecura:BAABLgAECn8dAAIBAAkJGBiUAQArAgABAAkJGBiUAQArAgAAAA==.',
Ab='Absolutezero:BAABLgAECn8bAAMCAAcJLCGFCwD3AQACAAcJ9CCFCwD3AQADAAIJ7hb4FAB3AAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAABLgAECn8lAAIEAAkJchuPAQA7AgAEAAkJchuPAQA7AgAAAA==.Alexjuander:BAAALgAECggJBQAAAA==.Alphard:BAABLgAECn8ZAAMFAAcJZBlqAwDnAQAFAAcJZBlqAwDnAQAGAAEJvBvOHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8ZAAIHAAcJ/xixBwB+AQAHAAcJ/xixBwB+AQAAAA==.',
Ap='Apocal:BAABLgAFFH8KAAIIAAQJcRdTAABEAQAIAAQJcRdTAABEAQAAAA==.Apothecary:BAAALgAECgEJAQAAAA==.',
Ar='Arete:BAAALgAECgYJCgAAAA==.Artaimya:BAAALgAECgUJCgAAAA==.Artemìs:BAAALgADCggJEQAAAA==.',
At='Atmosphere:BAAALgADCgkJFwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgUJBQAJAAAAAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgQJBQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgQJBAAAAA==.Basutai:BAAALgAECggJCAAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgADCgkJFAAAAA==.Birgetta:BAABLgAECn8ZAAMKAAcJhwrSTgB8AQAKAAcJhwrSTgB8AQALAAYJlQFdDAB7AAAAAA==.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIEAAgJNhlCDABxAgAEAAgJNhlCDABxAgAAAA==.Blasphemous:BAAALgAECgEJAgAAAA==.Blee:BAAALgAECgYJEQAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAAJAAAAAA==.',
Bo='Bobodaklown:BAABLgAECn8YAAIMAAgJWxejOgA5AgAMAAgJWxejOgA5AgAAAA==.Boomnblood:BAAALgADCgEJAQABLgAECgcJGwANAOoLAA==.Boomnbrew:BAABLgAECn8bAAINAAcJ6gs+DAAsAQANAAcJ6gs+DAAsAQAAAA==.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAAALgAECgcJEgAAAA==.',
Br='Brewman:BAABLgAECn8YAAMNAAgJ8Q/eQgA4AQANAAYJ+A/eQgA4AQAOAAMJxhbGEADUAAAAAA==.',
Bu='Bubonic:BAAALgAECgYJEwAAAA==.Buenasalud:BAAALgAECgcJEQAAAA==.',
Ca='Caylea:BAACLgAFFH8GAAIPAAIJagfIGwCYAAAPAAIJagfIGwCYAAAuAAQKfycAAg8ACAlZHDcCAEcCAA8ACAlZHDcCAEcCAAAA.',
Ch='Chalis:BAABLgAECn8WAAMQAAcJnhu8CgATAgAQAAYJ5h28CgATAgARAAUJThRMpAAPAQAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAAALgAECgcJBwAAAA==.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAABLgAECn8fAAMCAAgJ1RAWEwCpAQACAAgJ1RAWEwCpAQASAAEJugNeEQArAAAAAA==.Corvus:BAAALgAECgMJBQAAAA==.',
Cr='Crowdcontrol:BAAALgAECgYJEQAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAABLgAECn8fAAMTAAgJzQ4wDADeAQATAAgJJA4wDADeAQAUAAEJAQx5RwAwAAAAAA==.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daelin:BAABLgAECn8ZAAIMAAcJiSKXBwASAgAMAAcJiSKXBwASAgAAAA==.Dardanis:BAAALgAECgUJBwAAAA==.Darknous:BAAALgADCgMJAwAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAAALgADCgMJAwAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathrite:BAAALgAECgcJDgAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgQJBQAAAA==.Demo:BAAALgAECgQJBgABLgAECgUJDwAJAAAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgQJBgAAAA==.Deäthrose:BAABLgAECn8aAAIVAAcJ3wx+PABaAQAVAAcJ3wx+PABaAQAAAA==.',
Dh='Dhchin:BAAALgAECgEJAQABLgAFFAIJBgAFALYUAA==.',
Di='Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgUJBQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQAAAA==.',
Do='Doadin:BAABLgAECn8hAAMWAAkJBxrIDQCqAgAWAAkJBxrIDQCqAgAMAAEJ1gGaXQEgAAAAAA==.Doominatrix:BAABLgAECn8ZAAMRAAcJVxMmFQBnAQARAAYJVxMmFQBnAQAXAAEJAACjKgBKAAAAAA==.',
Dr='Draggum:BAAALgAECgMJBAABLgAECgcJGgACAPMZAA==.Dreadraven:BAABLgAECn87AAMPAAgJ9RKRJgAmAgAPAAgJ9RKRJgAmAgATAAEJZAT8FQAtAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8YAAMBAAcJ9hRoIQCxAQABAAcJNxRoIQCxAQAYAAYJXw1sLwCzAAABLgAECgEJAQAJAAAAAA==.Dreddstorm:BAAALgADCgcJDQAAAA==.Drewuw:BAABLgAECn8YAAIZAAgJIBWDGQAVAgAZAAgJIBWDGQAVAgABLgAECggJGAAYAMIcAA==.Druidhams:BAABLgAECn8bAAIaAAcJ3x7dBQAYAgAaAAcJ3x7dBQAYAgAAAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgIJAgAAAA==.Elisha:BAABLgAECn8mAAIMAAgJ/xLHGQBVAQAMAAgJ/xLHGQBVAQAAAA==.Elsyra:BAAALgADCgUJBQAAAA==.',
Er='Erebostro:BAABLgAECn8ZAAIKAAcJnRikDQCaAQAKAAcJnRikDQCaAQAAAA==.',
Ev='Evillux:BAABLgAECn8gAAMQAAgJ7A1/KgAXAQARAAcJPQvqmQAlAQAQAAUJ5gx/KgAXAQAAAA==.',
Ey='Eyeguy:BAABLgAECn8UAAMYAAgJrR6RJwBmAgAYAAgJThuRJwBmAgABAAQJ+h+tNgAsAQAAAA==.',
Fa='Fathercow:BAABLgAECn8ZAAIbAAcJmR+HAgA4AgAbAAcJmR+HAgA4AgAAAA==.',
Fi='Fingies:BAABLgAECn8jAAMRAAkJNR74AgBrAgARAAcJixz4AgBrAgAQAAUJcxxMFQCgAQAAAA==.Fistin:BAAALgAECgMJBAAAAA==.',
Fu='Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAABLgAECn8aAAMKAAcJ3x7mJAApAgAKAAcJ3x7mJAApAgAcAAUJGgqvCwDPAAAAAA==.',
Ga='Gaijin:BAAALgADCgMJAwABLgAECggJIwAbAD4eAA==.Galaxsea:BAAALgAECgYJEAAAAA==.',
Ge='Gerthquake:BAAALgAECgcJEgAAAA==.',
Gf='Gfour:BAABLgAECn8bAAIOAAgJShp5EwAxAgAOAAgJShp5EwAxAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Goodytwoshoe:BAAALgAECgIJBQAAAA==.',
Gr='Grimmreefer:BAAALgAECgQJBAAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgMJBAAAAA==.',
He='Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAAALgAECgYJEAABLgAFFAUJDQACAAUgAA==.Homsorc:BAACLgAFFH8NAAICAAUJBSDUBwDlAQACAAUJBSDUBwDlAQAuAAQKfyAAAgIACQlGJC8FAK8DAAIACQlGJC8FAK8DAAAA.Homtard:BAABLgAFFH8GAAILAAUJlSHSAACPAQALAAUJlSHSAACPAQABLgAFFAUJDQACAAUgAA==.Hope:BAABLgAECn8hAAIWAAgJthT7KwDXAQAWAAgJthT7KwDXAQAAAA==.',
Id='Idun:BAAALgAECgMJAwAAAA==.',
Il='Illiandray:BAABLgAECn8ZAAIQAAcJQhUjAgCAAQAQAAcJQhUjAgCAAQAAAA==.',
Im='Imu:BAABLgAECn8ZAAQcAAcJtCIoCQBPAgAcAAcJtCIoCQBPAgALAAUJPw3WVAD2AAAKAAIJiwrIpwB2AAABLgAFFAQJCwAMAColAA==.',
In='Insomniac:BAABLgAECn8ZAAIYAAcJuiO+BABBAgAYAAcJuiO+BABBAgAAAA==.',
Io='Ionise:BAAALgAECgkJCQAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Isklar:BAACLgAFFH8FAAIdAAIJTRmKBgCRAAAdAAIJTRmKBgCRAAAuAAQKfygAAh0ACAmiI4IEAAIDAB0ACAmiI4IEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEAAAAA==.Jangles:BAAALgAECgUJCwAAAA==.',
Je='Jer:BAABLgAECn8UAAIFAAkJyg81FABzAgAFAAkJyg81FABzAgAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAECggJIwAbAD4eAA==.',
Ka='Kairi:BAAALgAECgYJBgAAAA==.Kammo:BAABLgAECn8lAAIeAAkJ/x+rAAAGAwAeAAkJ/x+rAAAGAwAAAA==.Kazypher:BAAALgADCgcJCQAAAA==.',
Ke='Keeah:BAAALgAECgMJBAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8XAAIOAAgJbAeJMQA0AQAOAAgJbAeJMQA0AQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAECggJIwAbAD4eAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8KAAILAAQJVBDyAQBBAQALAAQJVBDyAQBBAQAuAAQKfx0AAgsABwnHIVoDAH4BAAsABwnHIVoDAH4BAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwikin:BAABLgAECn8aAAICAAcJ8xmVVQA3AgACAAcJ8xmVVQA3AgAAAA==.',
Ky='Kyreen:BAAALgAECgYJDgAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgYJEAAJAAAAAA==.',
La='Laaz:BAABLgAECn8gAAIYAAgJSQ79VgCdAQAYAAgJSQ79VgCdAQAAAA==.Lamalen:BAAALgAECgcJEwAAAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Linthvia:BAAALgAECgIJAgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgADCgIJAgAAAA==.',
Lu='Luciuos:BAAALgAECgYJDAAAAA==.Lucreesha:BAAALgADCgkJFQABLgAECggJGAAYAMIcAA==.Lukafox:BAACLgAFFH8OAAIfAAUJGhjrBgBWAQAfAAUJGhjrBgBWAQAuAAQKfyAAAx8ACQlZH6QHAPoCAB8ACQlZH6QHAPoCABUAAQmKAmiWAB0AAAAA.Lunastarvale:BAABLgAECn8ZAAIKAAcJCBpBCwC2AQAKAAcJCBpBCwC2AQAAAA==.',
Ma='Madith:BAAALgAECgIJBAAAAA==.Magicjamo:BAAALgAECgUJBQAAAA==.Malefisico:BAABLgAECn8UAAMRAAcJORG7bQCFAQARAAcJORG7bQCFAQAQAAEJAAB5eAArAAAAAA==.Malgarok:BAABLgAECn8lAAIRAAgJVxyfHgCfAgARAAgJVxyfHgCfAgABLgAECgYJEAAJAAAAAA==.Mardríft:BAABLgAECn8rAAIgAAgJ5R5LAgAxAgAgAAgJ5R5LAgAxAgAAAA==.Mazga:BAAALgAECgYJEgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8VAAIcAAcJCBCmBQB1AQAcAAcJCBCmBQB1AQAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Mezoti:BAAALgAECggJCAAAAA==.',
Mi='Mick:BAAALgAECgMJAwAAAA==.',
Mo='Moji:BAABLgAECn8YAAIOAAcJ9BcKGgDsAQAOAAcJ9BcKGgDsAQAAAA==.Monstermayi:BAABLgAECn8bAAIPAAcJug1sDABZAQAPAAcJug1sDABZAQAAAA==.Mooknight:BAABLgAECn8ZAAIdAAcJwg34BwAVAQAdAAcJwg34BwAVAQAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8gAAIZAAYJKBwhJQCuAQAZAAYJKBwhJQCuAQAAAA==.',
Mu='Muggy:BAAALgAECgYJDwAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAAALgAECgQJBgAAAA==.Mytastical:BAABLgAECn8gAAICAAcJChZ2fgDUAQACAAcJChZ2fgDUAQAAAA==.',
['Mæ']='Mæve:BAABLgAECn8fAAMaAAgJFBndBgD+AQAaAAgJFBndBgD+AQAgAAUJERAWRgAVAQAAAA==.',
Na='Namalis:BAABLgAECn8bAAQRAAcJPSYAOQAoAgARAAUJdCYAOQAoAgAQAAIJFiKcPADCAAAXAAEJAAAxIQBtAAAAAA==.Nanielito:BAAALgAECgkJEQAAAA==.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgADCgUJBwAAAA==.',
Ne='Neffer:BAABLgAECn8YAAICAAcJVx1rOwCJAgACAAcJVx1rOwCJAgAAAA==.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nonae:BAABLgAECn8gAAIKAAgJix0dEgCnAgAKAAgJix0dEgCnAgAAAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.',
Ob='Obiwon:BAAALgADCgcJCQAAAA==.',
Om='Omegá:BAABLgAECn8WAAIhAAcJUhWrEgCfAQAhAAcJUhWrEgCfAQAAAA==.',
Op='Optìmusprìme:BAABLgAECn8ZAAIUAAcJTBgRBQBrAQAUAAcJTBgRBQBrAQAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAABLgAECn8gAAQQAAgJXx7HAgDWAgAQAAcJUiHHAgDWAgARAAUJmBxiCwDAAQAXAAEJrQyXLgBBAAAAAA==.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAECgIJBAAAAA==.',
Po='Pockets:BAAALgAECgYJEQAAAA==.Porditum:BAAALgAECgQJBgAAAA==.Pouches:BAAALgAECgYJBwAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAABLgAECn8jAAIbAAgJPh6hDQBfAgAbAAgJPh6hDQBfAgAAAA==.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJCwAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAECgcJGgACAPMZAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAABLgAECn8gAAIhAAgJhhTYDgDXAQAhAAgJhhTYDgDXAQAAAA==.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAAALgAECgMJBAAAAA==.',
Re='Reaper:BAAALgAECgUJDwAAAA==.Reeb:BAAALgAECgUJBgAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Roguechin:BAACLgAFFH8GAAMFAAIJthTvBwC7AAAFAAIJthTvBwC7AAAGAAEJzQ72BQBeAAAuAAQKfyIAAwUACAk6JKYCAAcCAAUABwmfJKYCAAcCAAYAAwnpI/0NADoBAAAA.Rokkgar:BAAALgAECgYJEgAAAA==.Roosterr:BAAALgADCgkJEAAAAA==.',
Ru='Ruwazi:BAAALgAECgYJBwAAAA==.',
Sa='Samael:BAAALgAECgQJCQAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Sehnsucht:BAABLgAECn8lAAMaAAgJHB0IHgBOAgAaAAgJHB0IHgBOAgAgAAEJABqLdgBJAAAAAA==.Serius:BAAALgAECgQJBAABLgAECggJGAAYAMIcAA==.',
Sh='Shmadu:BAAALgAECgUJBQAAAA==.Shockk:BAABLgAECn8XAAMVAAgJ7RQnKwC+AQAVAAYJzBsnKwC+AQAfAAMJ4AKSigBpAAAAAA==.',
Si='Siovhan:BAAALgAECgQJCQAAAA==.',
Sm='Smóóthbói:BAAALgAECgYJEwAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn8aAAIiAAcJdA0lCgBDAQAiAAcJdA0lCgBDAQAAAA==.Soola:BAAALgAECgUJDQAAAA==.',
Sp='Spoopadin:BAAALgAECgIJAwAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.',
St='Stack:BAAALgAECgMJAwABLgAECgUJDwAJAAAAAA==.Stompycouch:BAABLgAECn8jAAIVAAgJ3hw6AwARAgAVAAgJ3hw6AwARAgAAAA==.Stoned:BAABLgAECn8fAAMWAAkJ2h7zCADhAgAWAAkJ2h7zCADhAgAMAAMJ3gpZOAC3AAAAAA==.Stonedpriest:BAABLgAECn8ZAAIjAAgJ1R9ABwDYAgAjAAgJ1R9ABwDYAgAAAA==.',
Su='Sunreaver:BAABLgAECn8dAAIeAAgJPiBEHQDQAgAeAAgJPiBEHQDQAgAAAA==.Surtain:BAAALgAECgcJEQAAAA==.',
Sw='Sweetmask:BAAALgAECgUJCgAAAA==.',
Sy='Syl:BAABLgAECn8bAAMKAAcJ5hYtFQBSAQAKAAYJWhgtFQBSAQALAAUJUwpaWQDfAAAAAA==.Sylvanäs:BAAALgADCgkJEQABLgAECgcJGQAQAEIVAA==.',
Ta='Tahitian:BAAALgAECgQJBAAAAA==.Tahlreth:BAABLgAECn8WAAICAAcJVB0EEADDAQACAAcJVB0EEADDAQAAAA==.Tanickz:BAAALgAECgcJEAAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJIQAVAKQbAA==.Tanidgetotem:BAABLgAECn8hAAIVAAkJpBv1CQD0AgAVAAkJpBv1CQD0AgAAAA==.Tanya:BAABLgAECn8jAAIcAAgJNRoZCABqAgAcAAgJNRoZCABqAgAAAA==.Tayanna:BAAALgAECgUJDAAAAA==.',
Te='Teias:BAABLgAECn8gAAMjAAgJXBoSEwBHAgAjAAgJXBoSEwBHAgAHAAMJUhliRADZAAAAAA==.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwAJAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAAALgAECgYJDwAAAA==.',
To='Torvald:BAAALgADCgEJAQABLgADCgUJCAAJAAAAAA==.',
Tr='Tricko:BAABLgAECn8ZAAIKAAYJ7yBBDACqAQAKAAYJ7yBBDACqAQAAAA==.Trollskingx:BAAALgAECgcJEQAAAA==.Trollzy:BAABLgAECn8ZAAMkAAcJ5xwnAgDfAQAkAAcJ5xwnAgDfAQAfAAEJhgMopgApAAAAAA==.Trunkmonkey:BAAALgAECgcJDQAAAA==.',
Ts='Tsaagan:BAABLgAECn8aAAQXAAcJiSH8CgCMAQAXAAQJeCL8CgCMAQARAAYJiRrrFABpAQAQAAQJBx60IABOAQAAAA==.',
Tu='Tucker:BAABLgAECn8ZAAIOAAkJcxNLBADzAQAOAAkJcxNLBADzAQAAAA==.',
Ty='Tychus:BAAALgAECgUJCQAAAA==.',
Ul='Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAAALgAECgQJBwAAAA==.Under:BAAALgADCgcJDgABLgAECgQJBwAJAAAAAA==.Unparalleled:BAAALgAECgYJDQAAAA==.',
Va='Valkyruid:BAACLgAFFH8JAAIaAAQJEhKmBQAhAQAaAAQJEhKmBQAhAQAuAAQKfxcAAhoABwnCF4Q2AM0BABoABwnCF4Q2AM0BAAAA.',
Vi='Vixus:BAAALgAECgUJCgAAAA==.',
Wa='Walshidan:BAAALgAECgYJEQAAAA==.Waywatcher:BAAALgAECgEJAQAAAA==.',
Wi='Wiccaflame:BAAALgAECgYJDgAAAA==.',
Wu='Wullgan:BAAALgAECggJDwAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAAALgAFFAEJAQAAAA==.',
Xo='Xole:BAABLgAECn8VAAMYAAYJMBPTbQBaAQAYAAYJMBPTbQBaAQAIAAQJIQSHIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8YAAIYAAgJwhyVMAA5AgAYAAgJwhyVMAA5AgAAAA==.',
Ya='Yareli:BAAALgAECgYJEAAAAA==.',
Ye='Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQAJAAAAAA==.Zarill:BAAALgADCgcJBwAAAA==.',
Ze='Zekröm:BAAALgAFFAEJAQAAAA==.Zekrøm:BAABLgAECn8VAAIVAAgJ0BnrGQBEAgAVAAgJ0BnrGQBEAgABLgAFFAEJAQAJAAAAAA==.Zeno:BAABLgAFFH8SAAIMAAYJCRyLAADBAQAMAAYJCRyLAADBAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQAJAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQAJAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAAALgAECgYJEgABLgAECgYJEgAJAAAAAA==.',
Zi='Zinbar:BAAALgAECgMJBAAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAAALgAECgYJEgAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQAJAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAICAAgJXCBbLwC1AgACAAgJXCBbLwC1AgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8cAAMbAAcJsiEZCQCqAgAbAAcJsiEZCQCqAgAjAAUJABr4OgBPAQAAAA==.',
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

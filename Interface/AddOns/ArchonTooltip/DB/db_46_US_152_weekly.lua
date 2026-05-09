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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Arms','Warrior-Protection','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Hunter-Survival','Evoker-Devastation','Druid-Balance','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaylasecura:BAACLgAFFH8JAAIBAAMJlh3NBwAfAQABAAMJlh3NBwAfAQAuAAQKfy4AAgEACQknILsBAPUCAAEACQknILsBAPUCAAAA.',
Ab='Absolutezero:BAABLgAECn8jAAMCAAgJgR+xEwB8AgACAAgJZB+xEwB8AgADAAIJ7hb2FAB3AAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAACLgAFFH8JAAIEAAMJOhWqEgDhAAAEAAMJOhWqEgDhAAAuAAQKfzYAAwQACQmKHRQEAHoCAAQACQmKHRQEAHoCAAUAAQluBRheAC0AAAAA.Alexjuander:BAAALgAECggJEAAAAA==.Alexsander:BAAALgAECgYJDgAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAIJCAAGAI8BAA==.Alphard:BAABLgAECn8kAAMHAAgJWx9KBACIAgAHAAgJWx9KBACIAgAIAAEJvBvSHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8kAAIJAAgJTBhkDAD/AQAJAAgJTBhkDAD/AQAAAA==.',
Ap='Apocal:BAACLgAFFH8NAAIKAAUJnRh1AQA4AQAKAAUJnRh1AQA4AQAuAAQKfxUAAgoACAmnG3gGACsCAAoACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Arete:BAAALgAECgYJEgAAAA==.Artaimya:BAAALgAECgYJCwAAAA==.Artemìs:BAAALgADCggJEQAAAA==.',
At='Atmosphere:BAAALgAECgUJBgAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgUJBQALAAAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAECggJJAACAGsWAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgQJBgAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgQJBwAAAA==.Basutai:BAABLgAECn8aAAIMAAkJjyOAAAChAwAMAAkJjyOAAAChAwAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgUJCQAAAA==.Birgetta:BAABLgAECn8pAAMNAAgJSA82KwCjAQANAAgJSA82KwCjAQAOAAYJbQOWFgCfAAAAAA==.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIEAAgJNhlCDABxAgAEAAgJNhlCDABxAgAAAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8bAAIPAAgJXh01CgDYAQAPAAgJXh01CgDYAQAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAALAAAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMGAAkJ9BaiIQAAAgAGAAkJYhaiIQAAAgAQAAIJmxUsIwB8AAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAIJBQARAEoEAA==.Boomnbrew:BAACLgAFFH8FAAIRAAIJSgQqMgB4AAARAAIJSgQqMgB4AAAuAAQKfysAAhEACAm9EYITAKMBABEACAm9EYITAKMBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8XAAMOAAgJWAxEEADpAAAOAAcJBwpEEADpAAANAAMJSxSNcQC/AAAAAA==.',
Br='Brewman:BAACLgAFFH8FAAISAAIJQR3ZGgCnAAASAAIJQR3ZGgCnAAAuAAQKfygAAxIACQlaGkcOAAYCABIABgkIHkcOAAYCABEACAnhDbscAE4BAAAA.',
Bu='Bubonic:BAABLgAECn8bAAITAAgJmBaXLQDEAQATAAgJmBaXLQDEAQAAAA==.Buenasalud:BAABLgAECn8cAAIUAAgJBxsKCQBcAgAUAAgJBxsKCQBcAgAAAA==.',
Ca='Caball:BAAALgAECgEJAQAAAA==.Carcharias:BAAALgAECgUJBQAAAA==.Caylea:BAACLgAFFH8TAAIVAAUJ2xf0CwBFAQAVAAUJ2xf0CwBFAQAuAAQKfycAAhUACAllHCkMACgCABUACAllHCkMACgCAAAA.',
Ch='Chalis:BAABLgAECn8ZAAMWAAcJBBy/CgATAgAWAAYJ5h2/CgATAgAXAAUJyRRnpAAPAQAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAABLgAECn8WAAMYAAgJfBARHwC6AQAYAAgJfBARHwC6AQAZAAEJXAAfdAAVAAAAAA==.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAABLgAECn8qAAMCAAkJ1RAzKwD1AQACAAkJ1RAzKwD1AQAaAAEJugNhEQArAAAAAA==.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgQJCQAAAA==.',
Cr='Crowdcontrol:BAABLgAECn8ZAAIQAAgJWiFRAwBtAgAQAAgJWiFRAwBtAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAABLgAECn8qAAMbAAkJbBOHCQCxAQAbAAkJWQ6HCQCxAQAcAAQJSRSPHgDIAAAAAA==.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAAALgAECgMJAwAAAA==.Daelin:BAABLgAECn8kAAMGAAgJiyINCQDEAgAGAAgJiyINCQDEAgAMAAEJJw0QZAAuAAAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darknous:BAAALgADCgMJAwAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAAALgAECgQJAgAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAAALgAECggJCAABLgAECggJGwAEADYZAA==.Deathrite:BAAALgAECgcJDgAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAEJAQABLgAFFAIJBAALAAAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAABLgAECn8iAAIZAAgJrBKvFQClAQAZAAgJrBKvFQClAQAAAA==.',
Dh='Dhchin:BAAALgAECgEJAQABLgAFFAUJDwAHAIojAA==.Dhomsak:BAAALgAECgcJDAABLgAFFAUJEgACAD4jAA==.',
Di='Diamonds:BAAALgADCgEJAQAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgUJBQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQAAAA==.',
Do='Doadin:BAABLgAECn8sAAMMAAkJoBtOBgC7AgAMAAkJoBtOBgC7AgAGAAEJ1gG4XQEgAAAAAA==.Doominatrix:BAACLgAFFH8FAAMXAAIJGwdEagB8AAAXAAIJGwdEagB8AAAdAAEJAwZ6CgBGAAAuAAQKfykAAxcACAlVFSIlANYBABcABwlVFSIlANYBAB0AAQkAAKMqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8WAAMFAAgJzxhQCwAWAgAFAAgJzxhQCwAWAgAEAAMJpxAaGwCiAAABLgAECgcJIAACAPAaAA==.Dreadraven:BAABLgAECn87AAMVAAgJ9RKUJgAmAgAVAAgJ9RKUJgAmAgAbAAEJZQSNQwAnAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8gAAMeAAgJgBRBMQBxAQABAAcJFRVqIQCxAQAeAAgJhBBBMQBxAQABLgAECgEJAQALAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIfAAkJwBaFGQAVAgAfAAkJwBaFGQAVAgAAAA==.Druidhams:BAACLgAFFH8FAAIgAAIJGBH5MACFAAAgAAIJGBH5MACFAAAuAAQKfysAAiAACAk2HmAMAIUCACAACAk2HmAMAIUCAAAA.',
Ea='Eamon:BAAALgAECgMJAwABLgAECgkJLwAhAGQeAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8IAAIGAAIJjwFlUQB5AAAGAAIJjwFlUQB5AAAuAAQKfzoAAgYACQnEFWsaACoCAAYACQnEFWsaACoCAAAA.Elsyra:BAAALgAECgQJBAAAAA==.',
Er='Erebostro:BAABLgAECn8kAAINAAgJqxkIGgACAgANAAgJqxkIGgACAgAAAA==.',
Ev='Everclear:BAAALgAECggJCAABLgAFFAIJBQAQAPYLAA==.Evillux:BAACLgAFFH8FAAMXAAIJbQXqbABxAAAXAAIJbQXqbABxAAAWAAEJZADdFwApAAAuAAQKfycAAxcACQkGEGtAAGgBABcACAkJDmtAAGgBABYABQnmDHwqABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMeAAkJHxyUJwBmAgAeAAkJLBmUJwBmAgABAAQJ+h+vNgAsAQAAAA==.',
Fa='Fathercow:BAACLgAFFH8FAAIhAAIJLSNoGgDNAAAhAAIJLSNoGgDNAAAuAAQKfyIAAiEACAk2HnYFAKoCACEACAk2HnYFAKoCAAAA.',
Fi='Fingies:BAACLgAFFH8IAAMXAAMJzhMQPQDiAAAXAAMJzhMQPQDiAAAdAAEJ6gViCgBHAAAuAAQKfzQAAxcACQmbIhwHANICABcABwlPIxwHANICABYABQngHUkVAKABAAAA.Fistin:BAAALgAECgQJBQAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8FAAINAAIJ1B3iMgC5AAANAAIJ1B3iMgC5AAAuAAQKfyoAAw0ACAntIg8HAMECAA0ACAntIg8HAMECACIABQmiDcIgAPcAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAECgkJLwAhAGQeAA==.Galaxsea:BAABLgAECn8WAAIfAAgJQR2ACAA5AgAfAAgJQR2ACAA5AgAAAA==.',
Ge='Gerthquake:BAABLgAECn8aAAMYAAgJ7yDAJgD4AQAYAAYJkB/AJgD4AQAZAAcJLBc2FQCrAQAAAA==.',
Gf='Gfour:BAABLgAECn8cAAISAAgJqBpyEwAwAgASAAgJqBpyEwAwAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAAALgAECgMJBAAAAA==.Goodytwoshoe:BAAALgAECgIJBQAAAA==.',
Gr='Grimmreefer:BAAALgAECgQJBAAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
He='Heart:BAAALgAECgYJBgABLgAFFAIJBAALAAAAAA==.Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAAALgAECgYJEAABLgAFFAUJEgACAD4jAA==.Homsorc:BAACLgAFFH8SAAMCAAUJPiPeBwDlAQACAAUJPiPeBwDlAQADAAEJByS6AQBqAAAuAAQKfyMAAgIACQlLJTMFAK8DAAIACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8NAAMOAAYJWyOsAgDHAQAOAAYJiyKsAgDHAQAiAAQJxRiRBgBfAQABLgAFFAUJEgACAD4jAA==.Hope:BAABLgAECn8rAAIMAAkJShsNCgBwAgAMAAkJShsNCgBwAgAAAA==.',
Id='Idun:BAAALgAECgMJAwAAAA==.',
Il='Illiandray:BAABLgAECn8pAAMWAAkJnxgCAgBAAgAWAAkJnxgCAgBAAgAXAAgJUAoFTgBAAQAAAA==.Ilswyn:BAAALgADCgMJAwABLgAECggJHgAeAF0jAA==.',
Im='Imu:BAACLgAFFH8IAAIiAAMJoCELCwAqAQAiAAMJoCELCwAqAQAuAAQKfx0ABCIABwnSJE4EAIMCACIABwnSJE4EAIMCAA4ABQk/DehUAPYAAA0AAgmLCs+nAHYAAAEuAAUUBQkTAAYAeiUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn8eAAIeAAgJXSNTBgDFAgAeAAgJXSNTBgDFAgAAAA==.',
Io='Ionise:BAABLgAECn8bAAIFAAkJnhctCABQAgAFAAkJnhctCABQAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAIPAAIJJBx2FAC0AAAPAAIJJBx2FAC0AAAuAAQKfy8AAg8ACAm4I4UEAAIDAA8ACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8YAAQFAAYJLxy8FQCWAQAFAAYJLxy8FQCWAQAEAAMJbwywOQCdAAAjAAEJ7xcLFQBHAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIHAAkJ1RAwFABzAgAHAAkJ1RAwFABzAgAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAECgkJLwAhAGQeAA==.',
Ka='Kairi:BAAALgAECgYJBgAAAA==.Kammo:BAACLgAFFH8LAAITAAMJbiZdIwBZAQATAAMJbiZdIwBZAQAuAAQKfzYAAhMACQmLJaYBAGQDABMACQmLJaYBAGQDAAAA.Kazypher:BAAALgAECgMJBAAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAISAAkJCgfxMQAvAQASAAkJCgfxMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAECgkJLwAhAGQeAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8OAAIOAAUJXxeVCAA3AQAOAAUJXxeVCAA3AQAuAAQKfx0AAg4ABwnLIakYAGYCAA4ABwnLIakYAGYCAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwikin:BAABLgAECn8gAAICAAcJ8BqEVQA3AgACAAcJ8BqEVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8WAAINAAYJywogZwAyAQANAAYJywogZwAyAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECggJFgAfAEEdAA==.',
La='Laaz:BAACLgAFFH8FAAIeAAIJfAbBUAB8AAAeAAIJfAbBUAB8AAAuAAQKfyUAAh4ACQkeDitJAB0BAB4ACQkeDitJAB0BAAAA.Lamalen:BAABLgAECn8UAAIGAAcJnxoTYQDBAQAGAAcJnxoTYQDBAQAAAA==.Lasercow:BAAALgAECgcJBwABLgAFFAIJBQAhAC0jAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Linthvia:BAAALgAECgQJBQAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgADCgIJAgAAAA==.',
Lo='Locknloaded:BAAALgAECgQJBAAAAA==.',
Lu='Luciuos:BAABLgAECn8VAAMgAAgJ3gEnagB/AAAgAAcJ9QEnagB/AAAkAAcJuQCVTgBKAAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJGwAfAMAWAA==.Lukafox:BAACLgAFFH8VAAIYAAYJ3hwQAwD5AQAYAAYJ3hwQAwD5AQAuAAQKfyAAAxgACQlZH6gHAPoCABgACQlZH6gHAPoCABkAAQmKAniWAB0AAAAA.Lunastarvale:BAABLgAECn8pAAINAAkJ9xjNDgBhAgANAAkJ9xjNDgBhAgAAAA==.Luscinia:BAAALgADCgEJAQAAAA==.',
Ma='Madith:BAABLgAECn8XAAIeAAgJEhsmEgAtAgAeAAgJEhsmEgAtAgAAAA==.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECgYJBgABLgAFFAIJBQAlAMcIAA==.Malefisico:BAABLgAECn8YAAMXAAgJxRC9bQCFAQAXAAgJxRC9bQCFAQAWAAEJAAB/eAArAAAAAA==.Malgarok:BAABLgAECn8lAAIXAAgJWBydHgCfAgAXAAgJWBydHgCfAgABLgAECgYJEAALAAAAAA==.Mardríft:BAABLgAECn82AAIkAAkJ9CAAAwDkAgAkAAkJ9CAAAwDkAgAAAA==.Mazga:BAABLgAECn8hAAImAAgJ8RMjBwDDAQAmAAgJ8RMjBwDDAQAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8lAAIiAAgJthUZCgACAgAiAAgJthUZCgACAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgADCgcJBwAAAA==.Mezoti:BAAALgAFFAIJAgAAAA==.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCggJCAAAAA==.',
Mo='Moji:BAABLgAECn8kAAISAAkJhBc0DwD5AQASAAkJhBc0DwD5AQAAAA==.Monstermayi:BAACLgAFFH8FAAIVAAIJigzGJACTAAAVAAIJigzGJACTAAAuAAQKfyYAAhUACAk9FhsPAP8BABUACAk9FhsPAP8BAAAA.Mooknight:BAABLgAECn8kAAIPAAgJbxEzDwB/AQAPAAgJbxEzDwB/AQAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIfAAgJXBpiCwADAgAfAAgJXBpiCwADAgAAAA==.',
Mu='Muggy:BAABLgAECn8fAAIIAAgJhA15BgCFAQAIAAgJhA15BgCFAQAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAAALgAECgYJCQAAAA==.Mytastical:BAABLgAECn8kAAICAAgJaxYTWwBeAQACAAgJaxYTWwBeAQAAAA==.',
['Mæ']='Mæve:BAABLgAECn8qAAMgAAkJvBjIDwBZAgAgAAkJvBjIDwBZAgAkAAUJ3xAiRgAVAQAAAA==.',
Na='Namalis:BAACLgAFFH8HAAIXAAQJRhOTJgAkAQAXAAQJRhOTJgAkAQAuAAQKfxsABBcABwk9Jv84ACgCABcABQl0Jv84ACgCABYAAgkWIp48AMIAAB0AAQkAADEhAG0AAAAA.Nanielito:BAABLgAECn8iAAICAAkJax72CQDXAgACAAkJax72CQDXAgAAAA==.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8FAAICAAMJXBW4NQDAAAACAAMJXBW4NQDAAAAuAAQKfyIAAgIACQlNGuUeADECAAIACQlNGuUeADECAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nonae:BAABLgAECn8gAAINAAgJjh0bEgCnAgANAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgADCgUJBQAAAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.',
Ob='Obiwon:BAAALgADCgcJEwAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Om='Omegá:BAACLgAFFH8FAAIQAAIJ9gvTCABvAAAQAAIJ9gvTCABvAAAuAAQKfx4AAhAACAkSE64SAJ8BABAACAkSE64SAJ8BAAAA.',
Oo='Oopsalldruid:BAAALgADCgMJAwABLgAECgcJIAACAPAaAA==.',
Op='Optìmusprìme:BAABLgAECn8kAAIcAAgJZRpPCAD2AQAcAAgJZRpPCAD2AQAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAABLgAECn8pAAQWAAkJCyHFAgDWAgAWAAcJUSHFAgDWAgAdAAYJTyE2AwDWAQAXAAUJoRy9KwC1AQAAAA==.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAECgIJBAAAAA==.',
Po='Pockets:BAABLgAECn8eAAICAAcJAxagSQCLAQACAAcJAxagSQCLAQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAAALgAECgYJDQAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAABLgAECn8vAAMhAAkJZB59BwBwAgAhAAkJZB59BwBwAgAJAAIJnBLUSwBEAAAAAA==.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJDwAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAECgcJIAACAPAaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAACLgAFFH8FAAIQAAIJfg8oCAB8AAAQAAIJfg8oCAB8AAAuAAQKfygAAhAACQlrFtoOANcBABAACQlrFtoOANcBAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAAALgAECgYJEwAAAA==.',
Re='Reaper:BAAALgAFFAIJAwABLgAFFAIJBAALAAAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAAALgAECgYJBwAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8PAAMHAAUJiiNWBACSAQAHAAUJiiNWBACSAQAIAAEJzQ74BQBeAAAuAAQKfyYAAwcACAllJREGAFMCAAcABwn7JREGAFMCAAgAAwnpI/8NADoBAAAA.Rokkgar:BAABLgAECn8YAAIZAAYJpQ3QLgD5AAAZAAYJpQ3QLgD5AAAAAA==.Roosterr:BAAALgADCgkJFgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Ry='Ryujin:BAAALgAECgEJAQAAAA==.',
Sa='Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAIVAAgJnhASFQDBAQAVAAgJnhASFQDBAQAAAA==.Sehnsucht:BAABLgAECn8oAAMgAAkJLRwIHgBOAgAgAAkJLRwIHgBOAgAkAAEJABqXdgBJAAAAAA==.Serius:BAAALgAECgQJBAABLgAECgkJGwAfAMAWAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMZAAkJGBZyEADeAQAZAAkJGBZyEADeAQAYAAMJ4AKJigBpAAAAAA==.',
Si='Siovhan:BAAALgAECgUJCgAAAA==.',
Sl='Sly:BAAALgAFFAIJBAAAAA==.',
Sm='Smóóthbói:BAABLgAECn8bAAICAAgJvBNPOwC2AQACAAgJvBNPOwC2AQAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn8lAAIFAAgJeBMtEQDHAQAFAAgJeBMtEQDHAQAAAA==.Soola:BAABLgAECn8XAAMYAAgJagmIMgBDAQAYAAgJagmIMgBDAQAZAAQJuQwzZgCrAAAAAA==.',
Sp='Spoopadin:BAAALgAECgIJBQAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.',
St='Stack:BAAALgAFFAIJAwABLgAFFAIJBAALAAAAAA==.Stompycouch:BAABLgAECn8rAAIZAAgJ8hxTDAAWAgAZAAgJ8hxTDAAWAgAAAA==.Stoned:BAABLgAECn8nAAMMAAkJJh/wCADhAgAMAAkJJh/wCADhAgAGAAMJ3wpApwCkAAAAAA==.Stonedpriest:BAABLgAECn8fAAIUAAgJ1h8+BwDYAgAUAAgJ1h8+BwDYAgAAAA==.Stripes:BAAALgADCgUJBQAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAITAAkJcyP/AwAmAwATAAkJcyP/AwAmAwAAAA==.Surtain:BAABLgAECn8ZAAIkAAgJXhy4EADJAQAkAAgJXhy4EADJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8ZAAITAAYJrSTDIQD/AQATAAYJrSTDIQD/AQAAAA==.',
Sy='Syl:BAABLgAECn8jAAMNAAgJxxdKGgAAAgANAAgJpxdKGgAAAgAOAAUJVQpoWQDfAAAAAA==.Sylvanäs:BAAALgADCgkJEQABLgAECgkJKQAWAJ8YAA==.',
Ta='Tahitian:BAAALgAECggJEgAAAA==.Tahlreth:BAABLgAECn8hAAICAAgJjx2TFgBmAgACAAgJjx2TFgBmAgAAAA==.Tanickz:BAABLgAECn8ZAAICAAgJCQ43OgC6AQACAAgJCQ43OgC6AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAZAPscAA==.Tanidgetotem:BAABLgAECn8sAAIZAAkJ+xysBgB5AgAZAAkJ+xysBgB5AgAAAA==.Tanya:BAACLgAFFH8JAAIiAAMJxxPiDQAHAQAiAAMJxxPiDQAHAQAuAAQKfzIAAiIACQnEGhQGAFECACIACQnEGhQGAFECAAAA.Tayanna:BAAALgAECgYJEAAAAA==.',
Te='Teias:BAACLgAFFH8FAAIUAAIJ4R25EwCsAAAUAAIJ4R25EwCsAAAuAAQKfygAAxQACQnOGBMTAEcCABQACQnOGBMTAEcCAAkABAnfF21EANkAAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwALAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8cAAICAAgJth7MGQBQAgACAAgJth7MGQBQAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAALAAAAAA==.',
Tr='Tricko:BAABLgAECn8oAAINAAgJKx4DEgBBAgANAAgJKx4DEgBBAgAAAA==.Trollskingx:BAAALgAECgcJEQAAAA==.Trollzy:BAABLgAECn8kAAMmAAgJhB7CAgB0AgAmAAgJhB7CAgB0AgAYAAEJhgMnpgApAAAAAA==.Trunkmonkey:BAABLgAECn8VAAIXAAgJFgzqTgA9AQAXAAgJFgzqTgA9AQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8FAAMXAAIJgxrfUQCrAAAXAAIJSxrfUQCrAAAdAAEJMxF4CABSAAAuAAQKfyUABBcACAm6If4NAHsCABcACAnAHv4NAHsCAB0ABAn/Iv0KAIwBABYABAkHHrIgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8iAAISAAkJ7xheBgCdAgASAAkJ7xheBgCdAgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ul='Ultramagnús:BAAALgADCgEJAQAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8UAAITAAYJoA9TWQA0AQATAAYJoA9TWQA0AQAAAA==.Under:BAAALgADCgcJDgABLgAECgYJFAATAKAPAA==.Unparalleled:BAABLgAECn8bAAMjAAYJiwnSCgDtAAAjAAUJiwnSCgDtAAAEAAYJogc5GADFAAAAAA==.',
Va='Valkyruid:BAACLgAFFH8PAAIgAAUJ4BFfEABRAQAgAAUJ4BFfEABRAQAuAAQKfxcAAiAABwnCF4k2AM0BACAABwnCF4k2AM0BAAAA.',
Vi='Vixus:BAAALgAECgYJEAAAAA==.',
Vx='Vxs:BAAALgAFFAEJAQAAAA==.',
['Vø']='Vøødu:BAAALgAECgUJBQABLgAECgcJGAAYAJEQAA==.',
Wa='Walshidan:BAABLgAECn8ZAAIeAAgJ6RF0MgBsAQAeAAgJ6RF0MgBsAQAAAA==.Waywatcher:BAAALgAECgUJCAAAAA==.',
Wi='Wiccaflame:BAABLgAECn8WAAICAAgJ1x9FUgBAAgACAAgJ1x9FUgBAAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAAALgAECgkJEQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAAALgAFFAIJAwAAAA==.',
Xo='Xole:BAABLgAECn8aAAMeAAgJjxPYbQBaAQAeAAgJjxPYbQBaAQAKAAQJIQSDIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8ZAAIeAAkJnRuNMAA5AgAeAAkJnRuNMAA5AgABLgAECgkJGwAfAMAWAA==.Xyrna:BAAALgADCgYJBgABLgAFFAIJBQAQAH4PAA==.',
Ya='Yareli:BAABLgAECn8YAAIKAAgJvQTJDQDlAAAKAAgJvQTJDQDlAAAAAA==.Yawa:BAAALgAECgEJAQAAAA==.',
Ye='Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQALAAAAAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgADCgEJAQAAAA==.Zayzoo:BAAALgADCgcJDgAAAA==.Zazie:BAAALgAECgUJBgAAAA==.',
Ze='Zekröm:BAACLgAFFH8FAAIlAAIJxwgACwBhAAAlAAIJxwgACwBhAAAuAAQKfxYAAiUACQk5Dr4NAC4BACUACQk5Dr4NAC4BAAAA.Zekrøm:BAABLgAECn8VAAIZAAgJ0BnrGQBEAgAZAAgJ0BnrGQBEAgABLgAFFAIJBQAlAMcIAA==.Zeno:BAABLgAFFH8aAAIGAAcJ1R1pAQAtAgAGAAcJ1R1pAQAtAgAAAA==.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQALAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQALAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8YAAIIAAYJpwwYCgAoAQAIAAYJpwwYCgAoAQABLgAECgYJGAAZAKUNAA==.',
Zi='Zinbar:BAAALgAECgcJCQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8YAAQfAAgJ+xlpCgATAgAfAAgJyBlpCgATAgARAAQJ9BVTVADzAAASAAEJTQJrcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQALAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAICAAgJXCBeLwC1AgACAAgJXCBeLwC1AgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8qAAQhAAgJ2yFyBQCrAgAhAAgJ2yFyBQCrAgAUAAUJABoCOwBPAQAJAAEJBhijSgBHAAAAAA==.',
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

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

local lookup = {'Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-05-29',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgUJBQAAAA==.Bazthrax:BAAALgAECgMJAgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8UAAIBAAYJTQFZMwBBAAZoDAAABQADAGkMAAADAAIAawwAAAMABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJTQFZMwBBAAZoDAAABQADAGkMAAADAAIAawwAAAMABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJBgAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh28JwDwAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh28JwDwAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIu8WACICAAIACAnWIu8WACICAAAA.Blarneystone:BAAALgAECgUJDgAAAA==.Bluemoon:BAAALgADCgYJDAAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8hAAIDAAYJziJsBgD4AQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAYAYQADAAYJziJsBgD4AQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAYAYQAuAAQKfzUAAwMACQkiI+UDAPECAAMACQkiI+UDAPECAAQAAQl8FmQiADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5AvZIADWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAFAAYJ5AvZIADWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAAALgAECgYJEAABLgAECggJJAAGABocAA==.Bullievit:BAACLgAFFH8JAAIHAAQJyBNTGgAZAQRoDAAAAwA8AGkMAAABACkAawwAAAIAHQDqDAAAAwBHAAcABAnIE1MaABkBBGgMAAADADwAaQwAAAEAKQBrDAAAAgAdAOoMAAADAEcALgAECn8kAAMHAAkJXh0kGADzAQAHAAkJXh0kGADzAQAIAAQJLQU8ngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn89AAIJAAkJRBGqCgCSAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAHADQAbQwAAAYAIADqDAAACAAkAG4MAAAGAFgAbwwAAAMAEwAJAAkJRBGqCgCSAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAHADQAbQwAAAYAIADqDAAACAAkAG4MAAAGAFgAbwwAAAMAEwAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIKAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAKAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJBgAAAA==.Chunly:BAABLgAECn8YAAQLAAcJTxV7IQCLAQdoDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAOoMAAAEAEEAbgwAAAMAMgBvDAAAAQApAAsABwlPFXshAIsBB2gMAAADADsAaQwAAAMAPQBrDAAAAwAxAGoMAAACADAA6gwAAAQAQQBuDAAAAwAyAG8MAAABACkADAADCSIOlmYAaAADaQwAAAEAHABrDAAAAQArAGoMAAABABkADQACCZsEJmQAQAACaQwAAAEACwBrDAAAAQALAAAA.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8VAAIOAAgJRw/6GABcAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABAAoAG4MAAABABwADgAICUcP+hgAXAEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAQAKABuDAAAAQAcAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQALAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMPAAkJcBOmHADVAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAPAAkJkBGmHADVAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgAQAAYJcBDiDQAcAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJEwAAAA==.Davik:BAABLgAECn8YAAIRAAYJ/gyIPgDwAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwARAAYJ/gyIPgDwAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgMJAwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJBwAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8XAAISAAgJgwwmhQBIAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAABABIAEgAICYMMJoUASAEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAQASAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAPAEILAQ==.Dracene:BAAALgAECgUJDgAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAATAAAAAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCwATAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMNAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQANAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAMAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMUAAgJkxTBGwANAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AFAAICZMUwRsADQIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABIAAQnxBG+bARwAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMRAAQJ8hrNHADkAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABEAAwmwGc0cAOQAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABUAAwnJDy0nANUAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEFQAJCUod4QYA8wIAFQAJCUod4QYA8wIAEQAICeUcAw4AowIAFgACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECggJMAALABQXAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8IAAIXAAMJcSSONQAoAQNoDAAAAwBfAGkMAAACAFwA6gwAAAMAWwAXAAMJcSSONQAoAQNoDAAAAwBfAGkMAAACAFwA6gwAAAMAWwAuAAQKfz8AAhcACAn4JekIAP4CABcACAn4JekIAP4CAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgQJCwAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgAXAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAILAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAAsABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8QAAIIAAUJaw/1HgA/AQVoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAOoMAAADAC8ACAAFCWsP9R4APwEFaAwAAAUAPwBpDAAABQA8AGsMAAACABYAagwAAAEABADqDAAAAwAvAC4ABAp/LwACCAAJCbMh0wQAXgMACAAJCbMh0wQAXgMAAAA=.',
Kr='Krazedwolf:BAACLgAFFH8HAAISAAUJzBEoMgAtAQVoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAOoMAAABACIAEgAFCcwRKDIALQEFaAwAAAIAVABpDAAAAgAjAGsMAAABABoAagwAAAEAJADqDAAAAQAiAC4ABAp/KAACEgAJCUYh5xIAvAIAEgAJCUYh5xIAvAIAAAA=.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJBwAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIRAAgJJx3eAACpAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEQAICScd3gAAqQIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEQAJCSUmQAEAwAMAEQAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIYAAYJMQ78pwAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAYAAYJMQ78pwAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn89AAMRAAkJdRNVGADnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwARAAkJdRNVGADnAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAACwBEAG4MAAAFABgAbwwAAAMAKwAVAAEJSwzTawAwAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8GAAIVAAMJihYwJgDeAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAVAAMJihYwJgDeAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8YAAIOAAkJZiLHBADBAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAOAAkJZiLHBADBAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIOAAkJHx56BADKAgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAOAAkJHx56BADKAgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAMJCAAZAGESAA==.',
Me='Melarac:BAABLgAECn8VAAQHAAYJjQniRwDNAAZoDAAABAAbAGkMAAAEABsAawwAAAQAEgBqDAAAAwAoAGwMAAABABYA6gwAAAUAGQAHAAYJjQniRwDNAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAIAAUJCAhJfwCpAAVoDAAAAQAJAGkMAAABACAAawwAAAEADABqDAAAAQAjAOoMAAABAAwABgAFCdQGhkYAYQAFaAwAAAIAEwBpDAAAAgARAGsMAAACAA8AagwAAAEADQDqDAAAAgAQAAAA.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8UAAMaAAQJNRwyQQBIAQRoDAAABgBOAGkMAAAFAEwAawwAAAMATQDqDAAABgA4ABoABAk1HDJBAEgBBGgMAAAFAE4AaQwAAAUATABrDAAAAwBNAOoMAAAGADgAGwABCQQIzAQAQAABaAwAAAEAFAAuAAQKfzwAAhoACQlIJCgIACcDABoACQlIJCgIACcDAAAA.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQNAAgJzh4ZFwA4AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEADQAHCa4eGRcAOAIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAMAAUJ7hsfLQBAAQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoACwAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgATAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgATAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAABLgAECn82AAIaAAgJXyP7IADwAghoDAAACQBfAGkMAAAJAGEAawwAAAoAXQBqDAAACgBiAGwMAAAGAF0AbQwAAAEARQDqDAAABgBiAG4MAAADAFUAGgAICV8j+yAA8AIIaAwAAAkAXwBpDAAACQBhAGsMAAAKAF0AagwAAAoAYgBsDAAABgBdAG0MAAABAEUA6gwAAAYAYgBuDAAAAwBVAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJBwAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAAALgAECggJEAABLgAFFAgJGAAPAIUWAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQATAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQALAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAgABLgAECgkJPQARAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgADCgUJBQAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8cAAIYAAcJuRVNdABlAQdoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwBuDAAAAQAzABgABwm5FU10AGUBB2gMAAAGAEoAaQwAAAYAOABrDAAABQAyAGoMAAACADQAbAwAAAMANQDqDAAABQAvAG4MAAABADMAAAA=.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQALAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgUJDgAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgIJAwAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgATAAAAAA==.Roidsnmolly:BAAALgAECgcJAgAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAUJEAAIAGsPAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECgcJCwAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn86AAIcAAkJThfdGAACAgloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAcAAkJThfdGAACAgloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAARACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8lAAMYAAgJog28awB4AQhoDAAABgAvAGkMAAAGAB4AawwAAAYAEwBqDAAABQAoAGwMAAAFADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAGAAICaINvGsAeAEIaAwAAAYALwBpDAAABQAeAGsMAAAGABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAkAAwknBQszACgAA2kMAAABABIAagwAAAEABQDqDAAAAQAIAAAA.',
Sn='Sncak:BAACLgAFFH8eAAMDAAYJVhzcCQCtAQZoDAAACABfAGkMAAAHAGEAawwAAAYASQBqDAAAAgAgAG0MAAABAAUA6gwAAAYAWwADAAYJVhzcCQCtAQZoDAAACABfAGkMAAAGAGEAawwAAAYASQBqDAAAAgAgAG0MAAABAAUA6gwAAAYAWwAEAAEJOQ08BgBcAAFpDAAAAQAhAC4ABAp/KgADAwAJCQ8kKAIAkAMAAwAJCQ8kKAIAkAMABAAECb8bpA8AFgEAAAA=.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8IAAIFAAQJ2g8WCwDZAARoDAAAAwA6AGkMAAACACIAagwAAAEANwDqDAAAAgAdAAUABAnaDxYLANkABGgMAAADADoAaQwAAAIAIgBqDAAAAQA3AOoMAAACAB0ALgAECn8bAAIFAAkJ9iE7BADdAgAFAAkJ9iE7BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgQJCQAAAA==.Syrax:BAABLgAECn8fAAMQAAcJqhZhCQB+AQdoDAAABgBMAGkMAAAHAEEAawwAAAYAJwBqDAAABAA5AGwMAAADAEwA6gwAAAQATABuDAAAAQAOABAABgkIGmEJAH4BBmgMAAAGAEwAaQwAAAMAQQBrDAAAAwAmAGoMAAAEADkAbAwAAAMATADqDAAAAwBMAA8ABAlrDMRVALIABGkMAAAEACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQDCQgAGQBhEgA=.Syrieal:BAACLgAFFH8IAAIZAAMJYRK1IAC2AANoDAAAAwAoAGkMAAACADUA6gwAAAMALwAZAAMJYRK1IAC2AANoDAAAAwAoAGkMAAACADUA6gwAAAMALwAuAAQKfzcAAxkACQmfHOwMAB8CABkACQn3GuwMAB8CAAkABwnHGJYIALsBAAAA.',
Ta='Taiyla:BAABLgAECn81AAIaAAkJmxEFRQD0AQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAaAAkJmxEFRQD0AQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAAAA==.Talithiala:BAAALgAECgYJCQAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMNAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ADQAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAAsABwmKCoxSAKYAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAUJEAAIAGsPAA==.',
Tr='Trip:BAABLgAECn8kAAMdAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAdAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAeAAcJBw1ZFwApAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Tu='Tubbybuddy:BAABLgAECn8WAAIeAAYJORmKEgBqAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAeAAYJORmKEgBqAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJIgAWABwcAA==.Unilock:BAACLgAFFH8HAAIfAAQJthNiOgA9AQRoDAAAAgAsAGkMAAACAFIAawwAAAEALwDqDAAAAgAbAB8ABAm2E2I6AD0BBGgMAAACACwAaQwAAAIAUgBrDAAAAQAvAOoMAAACABsALgAECn8gAAIfAAkJshnBIwBDAgAfAAkJshnBIwBDAgABLgAFFAcJIgAWABwcAA==.Unipray:BAACLgAFFH8iAAMWAAcJHBzIAgAjAgdoDAAABwBAAGkMAAAHAF8AawwAAAYAOgBqDAAABABXAGwMAAABACsAbQwAAAEANgDqDAAACABjABYABwkcHMgCACMCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAHAGMAEQAFCYAXLBIAOQEFaAwAAAMASQBpDAAAAgA6AGsMAAACACsAagwAAAEAHgDqDAAAAQBBAC4ABAp/JwADFgAJCbAiUAEAbwMAFgAJCbAiUAEAbwMAEQAHCese0hQARwIAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIbAAYJcgEWEABQAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAbAAYJcgEWEABQAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgQJBgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJJgAYAOYkAA==.',
Ye='Yefercas:BAAALgAECgYJCwAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIgAAkJGRb6AQA7AgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAgAAkJGRb6AQA7AgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8tAAIXAAgJvQuFVgCFAQhoDAAABgBEAGkMAAAHABgAawwAAAkAFABqDAAABAAeAGwMAAAFABwAbQwAAAQADADqDAAABQAeAG4MAAAFABkAFwAICb0LhVYAhQEIaAwAAAYARABpDAAABwAYAGsMAAAJABQAagwAAAQAHgBsDAAABQAcAG0MAAAEAAwA6gwAAAUAHgBuDAAABQAZAAAA.',
Yo='You:BAABLgAECn8kAAIZAAkJsxeXEgDIAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAZAAkJsxeXEgDIAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8GAAMZAAMJXh1sGAD0AANoDAAAAgAzAGkMAAABAFAA6gwAAAMAXQAZAAMJXh1sGAD0AANoDAAAAgAzAGkMAAABAFAA6gwAAAIAXQAYAAEJ4wIB8gA3AAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQATAAAAAA==.',
Ze='Zemzelett:BAAALgAECgUJCwAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

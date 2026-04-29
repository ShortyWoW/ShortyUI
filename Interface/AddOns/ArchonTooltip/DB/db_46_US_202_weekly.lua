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

local lookup = {'Warrior-Fury','Warrior-Arms','Mage-Frost','Unknown-Unknown','Shaman-Enhancement','Mage-Arcane','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Monk-Brewmaster','DemonHunter-Devourer','Druid-Balance','Paladin-Protection','Monk-Windwalker','Warlock-Affliction','Mage-Fire','Paladin-Retribution','Evoker-Preservation','Paladin-Holy','Druid-Restoration','Warrior-Protection','Priest-Discipline','DeathKnight-Frost','Hunter-BeastMastery','Rogue-Outlaw','Rogue-Subtlety','Monk-Mistweaver','Rogue-Assassination','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJBgAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Admaris:BAAALgAECgYJCgAAAA==.',
Ag='Age:BAABLgAECn8dAAMBAAgJRBfrBQDIAQABAAgJRBfrBQDIAQACAAMJoA0NJwC2AAAAAA==.Agni:BAACLgAFFH8LAAIDAAQJASOCDwCbAQADAAQJASOCDwCbAQAuAAQKfyUAAgMACQnmI6UEALYDAAMACQnmI6UEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8YAAIBAAYJtRK0DQBIAQABAAYJtRK0DQBIAQAAAA==.',
Al='Alavendis:BAAALgAECgYJDgABLgAECgQJBgAEAAAAAA==.Alexá:BAAALgAECgMJAwABLgAECgYJEgAEAAAAAA==.Almight:BAAALgAECgEJAQAAAA==.Alnasham:BAACLgAFFH8NAAIFAAUJBxulAADLAQAFAAUJBxulAADLAQAuAAQKfxcAAgUACAl5H5wGAIwCAAUACAl5H5wGAIwCAAAA.Alphashadow:BAAALgADCgUJBQAAAA==.Alvoka:BAABLgAECn8XAAMDAAgJxRKdagAAAgADAAgJxRKdagAAAgAGAAQJlg95AgAMAQAAAA==.',
Am='Amarillos:BAAALgADCgIJAgAAAA==.Amarillys:BAACLgAFFH8FAAIHAAIJQh1zCwCsAAAHAAIJQh1zCwCsAAAuAAQKfxkAAwcACQliFRkOAHoCAAcACQliFRkOAHoCAAgAAQnYFIpjADEAAAAA.Ambrotos:BAAALgAECgYJDgAAAA==.Ammutseba:BAABLgAECn8cAAIJAAgJ2RixCADsAQAJAAgJ2RixCADsAQAAAA==.',
An='Angermeier:BAABLgAECn8WAAIBAAYJ3RjONgDNAQABAAYJ3RjONgDNAQAAAA==.Angrylady:BAAALgAECgEJAQAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAQAAAA==.Arg:BAAALgAECgEJAQAAAA==.Arowin:BAAALgAECggJCwAAAA==.Arthaniis:BAABLgAECn8aAAIKAAgJfiD5CAACAwAKAAgJfiD5CAACAwAAAA==.',
As='Asdar:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgEJBAAAAA==.',
Au='Audideath:BAAALgAECgQJBQAAAA==.Augtistic:BAABLgAECn8bAAMLAAkJRRJ6CABiAQALAAkJRRJ6CABiAQAMAAYJcwL/KgDFAAAAAA==.Aulrelle:BAAALgAECgUJDAABLgAECgQJBAAEAAAAAA==.Auurdeath:BAAALgAECgYJCgAAAA==.',
Av='Avidswolf:BAAALgAECgYJEwAAAA==.Avãcyn:BAAALgAECgYJDwAAAA==.',
Aw='Aw:BAACLgAFFH8LAAINAAYJiSMPAADEAQANAAYJiSMPAADEAQAuAAQKfxgAAg0ACAmdJooBAJEDAA0ACAmdJooBAJEDAAAA.Awppenheimer:BAABLgAECn8fAAMOAAgJZB0UCQDgAQAOAAcJOhsUCQDgAQAPAAYJdRyOEADKAQAAAA==.',
Ax='Ax:BAEBLgAFFH8LAAMQAAUJLAlzCQAuAQAQAAQJLAlzCQAuAQARAAEJAADKGwArAAAAAA==.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAAALgAFFAEJAQAAAA==.',
Ba='Babycarrots:BAAALgAECgYJBwAAAA==.Baconz:BAABLgAECn8XAAMKAAgJZBRrJADtAQAKAAgJZBRrJADtAQASAAEJ9QIjMQAmAAAAAA==.Bakeon:BAABLgAECn8UAAMSAAcJbhGsPQCKAQASAAcJbhGsPQCKAQAKAAMJYAQXdABxAAAAAA==.Baldozhi:BAAALgAECgUJBwAAAA==.Bangbang:BAAALgAFFAEJAQAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAAALgAECgQJBAAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECgYJDgAEAAAAAA==.Beardcheese:BAAALgADCgcJDAAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAAALgAECgYJEAAAAA==.',
Bi='Bink:BAABLgAECn8ZAAITAAkJ9xpCBADXAgATAAkJ9xpCBADXAgAAAA==.Birblock:BAAALgAFFAIJAgABLgAFFAgJFwAUAJ4WAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAAALgAECgUJDgAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAAALgAECgYJCwAAAA==.',
Bo='Bobbo:BAAALgADCgIJAgAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Boomin:BAAALgAECgYJCwAAAA==.',
Br='Braass:BAAALgADCgUJBgABLgAECgQJBAAEAAAAAA==.Breachnclear:BAAALgAECgQJBAAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8hAAIVAAgJUBrtAwDsAQAVAAgJUBrtAwDsAQAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgADCgYJBgABLgAECgUJCAAEAAAAAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8aAAISAAgJgyGfAAD8AgASAAgJgyGfAAD8AgAAAA==.',
Bu='Buffygirl:BAAALgAECggJEwAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECggJEAAAAA==.',
['Bå']='Båne:BAAALgAECgYJDwAAAA==.',
Ca='Carnal:BAAALgADCgUJCAAAAA==.Casini:BAAALgADCgMJAwAAAA==.Cazic:BAAALgAECgEJAgAAAA==.',
Ce='Cedren:BAACLgAFFH8GAAIWAAMJexVzDAD6AAAWAAMJexVzDAD6AAAuAAQKfxcAAhYACAnQIO8dAJ4CABYACAnQIO8dAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIWAAcJsyKjIQCHAgAWAAcJsyKjIQCHAgAAAA==.',
Ch='Cheapheal:BAABLgAECn8lAAIXAAkJMiB/AAD6AgAXAAkJMiB/AAD6AgAAAA==.Cheburashka:BAACLgAFFH8NAAIKAAUJMx6gAwCwAQAKAAUJMx6gAwCwAQAuAAQKfxcAAgoACAnNIggPALYCAAoACAnNIggPALYCAAAA.Chewymentos:BAAALgAECgUJBgABLgAECgcJGQAYAP0KAA==.Chimerabob:BAAALgAECgYJCwAAAA==.Chunkymonkey:BAACLgAFFH8JAAMZAAQJbg7MAQA+AQAZAAQJzw3MAQA+AQAVAAIJGA6tHACKAAAuAAQKfxsAAxkACAlKISgLAMcCABkACAlKISgLAMcCABUABQlxGvo9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cl='Clappncheeks:BAAALgAECgUJEQAAAA==.Claudefrollo:BAAALgAECgYJDwAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corrüpt:BAAALgAECgMJAwAAAA==.',
Cr='Crimsa:BAABLgAECn8YAAIaAAcJbgTXDwAwAQAaAAcJbgTXDwAwAQAAAA==.Crimsongost:BAAALgAECgEJAQAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Cryogen:BAABLgAECn8ZAAIXAAgJEyDCAgAaAgAXAAgJEyDCAgAaAgAAAA==.',
Cs='Cs:BAABLgAECn8mAAIVAAkJnB/RAwBSAwAVAAkJnB/RAwBSAwAAAA==.',
Cu='Curufin:BAAALgAECgMJBgAAAA==.',
Da='Daddysmooth:BAAALgADCgYJBgAAAA==.Daemon:BAABLgAECn8YAAIQAAcJcB1EQgAwAgAQAAcJcB1EQgAwAgAAAA==.Daemonproph:BAAALgAECgYJDQAAAA==.Dakini:BAAALgAECgYJEQAAAA==.Daktaklakpak:BAAALgAECgQJBAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8hAAIYAAgJCx9VBADDAgAYAAgJCx9VBADDAgAAAA==.Dangerruss:BAAALgAECgYJEQAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAABLgAECn8dAAMbAAgJ9R0gAQDAAgAbAAgJ9R0gAQDAAgADAAQJKwhBGQHMAAAAAA==.Dasmonkey:BAAALgADCgkJGAAAAA==.Daxos:BAABLgAECn8ZAAIDAAgJ7xeVSwBUAgADAAgJ7xeVSwBUAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJCQAAAA==.Deelahn:BAAALgAECgYJDgAAAA==.Demonicchoas:BAABLgAECn8pAAMPAAkJeSAaAQAmAwAPAAgJJyIaAQAmAwAOAAcJVxZhGQBIAQAAAA==.Denagorn:BAABLgAECn8pAAIcAAkJWxyMFwDbAgAcAAkJWxyMFwDbAgABLgAFFAYJEQAQABQVAA==.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAAALgAECgYJBgAAAA==.Deutzfr:BAAALgAFFAEJAQAAAA==.',
Do='Dominant:BAABLgAECn8dAAIDAAgJcRwpBwA5AgADAAgJcRwpBwA5AgAAAA==.Dooma:BAAALgAFFAMJAwAAAA==.Dorgie:BAAALgAECgUJDwABLgAFFAEJAwAEAAAAAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIDAAgJSiHaIQDsAgADAAgJSiHaIQDsAgAAAA==.',
Dr='Draco:BAAALgADCgEJAQAAAA==.Drag:BAAALgAECgQJBQAAAA==.Dragon:BAABLgAECn8WAAIdAAgJXxFXFgDoAQAdAAgJXxFXFgDoAQAAAA==.Drbob:BAAALgAECgQJBQAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAAALgAECgYJDAABLgAFFAUJDQAeAPcjAA==.Drock:BAAALgAECgYJDwAAAA==.Druidgale:BAABLgAECn8WAAIfAAgJ+whYGwDcAAAfAAgJ+whYGwDcAAAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAAALgAECgYJCgAAAA==.Drybonez:BAAALgAECgYJDwAAAA==.Drygth:BAAALgAECggJEQAAAA==.',
Du='Dubshox:BAABLgAECn8YAAIKAAgJUBtTBADmAQAKAAgJUBtTBADmAQAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ei='Eisador:BAAALgAECgYJDwAAAA==.',
El='Elemotional:BAAALgAECgcJCwAAAA==.',
Eq='Equilibrio:BAABLgAECn8aAAIgAAgJKxzqAQAXAgAgAAgJKxzqAQAXAgAAAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAAALgAECgYJEgAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECgYJFgALAJ4VAA==.',
Fa='Faelthas:BAACLgAFFH8OAAIVAAUJByTIAQDvAQAVAAUJByTIAQDvAQAuAAQKfygAAhUACAkJJtgCAGkDABUACAkJJtgCAGkDAAAA.Fathercoast:BAABLgAECn8iAAMIAAgJEx4XBADjAQAIAAgJEx4XBADjAQAhAAYJWBbyHwCUAQAAAA==.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAAALgAECgYJBgAAAA==.Felstrider:BAAALgAECgQJBwAAAA==.Fembouyant:BAABLgAECn8VAAIiAAgJ/RSEBAAVAgAiAAgJ/RSEBAAVAgAAAA==.Ferador:BAACLgAFFH8QAAMUAAUJjAmSBAC5AAAUAAQJfgWSBAC5AAAjAAEJtRVYIQBeAAAuAAQKfxkAAxQACAlgHWsjAAkCABQACAnFFWsjAAkCACMABAmZGbprACUBAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.',
Fl='Flowmo:BAAALgAECgYJBwABLgAECggJFwAVANobAA==.',
Fo='Fourbees:BAAALgAECgYJCwAAAA==.',
Fr='Frizly:BAABLgAECn8VAAMHAAgJ2AV+QwArAQAHAAgJ2AV+QwArAQAIAAEJ3ABwJAARAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIDAAkJ/hGiXQAhAgADAAkJ/hGiXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.',
Ga='Galdrell:BAAALgAECgYJCwAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgADCgEJAQAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8fAAMQAAkJKh9GEwAIAwAQAAkJKh9GEwAIAwAiAAEJDgcOGQArAAAAAA==.',
Gn='Gnnome:BAABLgAECn8UAAIDAAcJ9gozIwBFAQADAAcJ9gozIwBFAQAAAA==.',
Go='Gog:BAAALgAECgYJBwAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIRAAkJ3yVaAADPAwARAAkJ3yVaAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8aAAIQAAgJyxzRCQDhAQAQAAgJyxzRCQDhAQAAAA==.Grimaldus:BAABLgAECn8XAAIYAAgJih98BAC9AgAYAAgJih98BAC9AgAAAA==.Grimmortal:BAAALgADCgYJDAAAAA==.Grimreaper:BAABLgAECn8fAAMkAAgJVB3PAADUAQAkAAcJkx/PAADUAQAlAAIJexAzUwCRAAAAAA==.Groag:BAAALgAECgUJCwAAAA==.Groovytony:BAAALgAECgYJBgAAAA==.Gruffles:BAAALgAECgYJDwAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8cAAIWAAgJOxsaCwDCAQAWAAgJOxsaCwDCAQAAAA==.',
Ha='Haarp:BAAALgAECgQJBAAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handimage:BAAALgADCgEJAQABLgAECgYJEAAEAAAAAA==.Handipriest:BAAALgAECgYJEAAAAA==.Haqq:BAAALgAECgcJDQAAAA==.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgADCgYJBgAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8aAAIQAAYJ/BCLHQAvAQAQAAYJ/BCLHQAvAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgADCgQJBAAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8XAAIQAAgJ9xwwBQA4AgAQAAgJ9xwwBQA4AgAAAA==.',
Ho='Hoafustis:BAAALgADCgYJCQAAAA==.Hobo:BAAALgAECgUJBwAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBAAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Hundard:BAAALgAECgIJAgAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAAALgAECgUJBwABLgAECggJGQABAMwlAA==.Iblisshaytan:BAAALgAECgcJDgABLgAECggJFAADAOkUAA==.Ibtrollin:BAAALgAECgEJAQAAAA==.',
Ig='Ignacious:BAABLgAECn8pAAQSAAgJGyXjAgBQAwASAAgJGyXjAgBQAwAKAAYJIR1LBwCSAQAFAAEJVg8RLAA1AAAAAA==.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAAALgAECgYJDQAAAA==.Immolate:BAABLgAECn8aAAQOAAkJzyEFNgA0AgAOAAcJbx8FNgA0AgAPAAUJsCKUFgCVAQAaAAEJAAAxJABhAAAAAA==.',
In='Infamous:BAAALgAECgQJBAAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJDQAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAgAAAA==.',
Is='Ischia:BAACLgAFFH8MAAIHAAUJLQ9EAgCNAQAHAAUJLQ9EAgCNAQAuAAQKfxgAAwcACAkdEi8gAOABAAcACAkdEi8gAOABAAgAAQm/AZpqACEAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIlAAIJpx+hEADFAAAlAAIJpx+hEADFAAAuAAQKfxgAAiUABwliI8MXAEsCACUABwliI8MXAEsCAAAA.Jallypally:BAAALgADCgcJCAAAAA==.Janokdiso:BAAALgAECgEJAQAAAA==.Javeighqueas:BAAALgADCgQJAgABLgAECggJFQAWABUUAA==.',
Jc='Jch:BAACLgAFFH8PAAMjAAYJYR1+AADCAQAjAAUJgB1+AADCAQAUAAEJ5hzpBgBmAAAuAAQKfyEAAyMACQnbI/wBAH8DACMACQnbI/wBAH8DABQAAQmiByePACwAAAAA.',
Je='Jedijed:BAAALgAECgYJBgABLgAECgYJBgAEAAAAAA==.Jedikepjr:BAAALgAECgYJBgAAAA==.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECgEJAQAAAA==.Joneztown:BAABLgAECn8WAAIZAAkJQRqzCwC/AgAZAAkJQRqzCwC/AgAAAA==.Jordantheorc:BAABLgAECn8lAAMjAAgJ/B5FBAA+AgAjAAgJ/B5FBAA+AgAUAAIJvwKSgQBAAAAAAA==.',
Jp='Jprottsoo:BAAALgAECgYJDgAAAA==.',
Jt='Jtee:BAABLgAECn8gAAIeAAgJchEOCQCzAQAeAAgJchEOCQCzAQAAAA==.',
Ju='Jukkrit:BAAALgADCgEJAQAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8fAAIfAAgJmQreFQAVAQAfAAgJmQreFQAVAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECggJEwAEAAAAAA==.Karoo:BAAALgADCgYJBgAAAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAQAAAA==.Keizzer:BAABLgAECn8eAAIcAAgJfCAPHgC3AgAcAAgJfCAPHgC3AgAAAA==.Keshisaru:BAAALgAECggJDgAAAA==.',
Kh='Kharms:BAAALgAECgYJEQAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.',
Kl='Klunder:BAABLgAECn8UAAISAAcJ6h9FAgB/AgASAAcJ6h9FAgB/AgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIVAAgJ2htoBQC4AQAVAAgJ2htoBQC4AQAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAAALgAECggJEwAAAA==.Kostik:BAAALgAECgQJBAAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAABLgAECn8ZAAIWAAgJaQ1WFABbAQAWAAgJaQ1WFABbAQAAAA==.Krux:BAAALgAECgIJAgAAAA==.',
La='Lacie:BAAALgADCgUJBQAAAA==.Laennaya:BAABLgAECn8cAAIaAAcJHwnzDABmAQAaAAcJHwnzDABmAQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAAALgAECgQJBQAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgIJAwAAAA==.Lazyfrost:BAABLgAECn8XAAIDAAgJ1BkWQAB5AgADAAgJ1BkWQAB5AgAAAA==.Lazyunholy:BAAALgADCgkJCAAAAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8WAAMeAAcJfh+YEwB2AgAeAAcJfh+YEwB2AgAcAAEJXA71PgE1AAAAAA==.Lethô:BAABLgAECn8fAAIfAAgJOiOIAAAyAwAfAAgJOiOIAAAyAwAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Liesx:BAAALgADCgQJBAAAAA==.Lilboothang:BAAALgAECgYJEQAAAA==.Lilzarthe:BAAALgAECgMJAwABLgAECgYJDgAEAAAAAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAABLgAECn8pAAIWAAkJnSQUAgC3AwAWAAkJnSQUAgC3AwAAAA==.Loko:BAACLgAFFH8NAAIXAAUJUxSzCQBMAQAXAAUJUxSzCQBMAQAuAAQKfycAAhcACAk4JfADAGkDABcACAk4JfADAGkDAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAECgQJBAAAAA==.Louiie:BAAALgAECgYJDgAAAA==.',
Lu='Luckygrapes:BAABLgAECn8ZAAImAAcJtR/IDgBrAgAmAAcJtR/IDgBrAgAAAA==.Lukdanuke:BAAALgAECgYJCgAAAA==.Luxxus:BAAALgAECgcJCwABLgAECggJHgAcAHwgAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAAALgAECgYJEQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8XAAIOAAcJVRHLXgCsAQAOAAcJVRHLXgCsAQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAIZAAcJnh0GFABPAgAZAAcJnh0GFABPAgAAAA==.Mantakore:BAACLgAFFH8GAAIdAAMJvgb8DwDLAAAdAAMJvgb8DwDLAAAuAAQKfycAAh0ACAnOF3URACUCAB0ACAnOF3URACUCAAAA.Maubles:BAAALgAECgYJBgABLgAFFAIJBgAYAGwUAA==.',
Me='Meiling:BAAALgADCgcJBwAAAA==.Meladra:BAAALgADCgcJBwAAAA==.Menopaws:BAAALgAECggJDgAAAA==.Mertrik:BAABLgAECn8aAAMKAAgJvxy7EAChAgAKAAgJvxy7EAChAgAFAAEJuBh+KQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8cAAIRAAgJfx9pCwBdAgARAAgJfx9pCwBdAgAAAA==.Mikailla:BAAALgAECgcJBwABLgAECgEJAQAEAAAAAA==.Mikayy:BAACLgAFFH8MAAIlAAQJAyWuAACbAQAlAAQJAyWuAACbAQAuAAQKfycAAyUACAm/JRYBAG8CACUACAlyJRYBAG8CACcAAQlWJbYHAG0AAAAA.Milenko:BAABLgAECn8aAAINAAYJrST/AQALAgANAAYJrST/AQALAgAAAA==.Milly:BAAALgAECgEJAgABLgAECgYJGgANAK0kAA==.Mimid:BAAALgAECgYJBwAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minteafresh:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8MAAIBAAUJgg5KBQCdAQABAAUJgg5KBQCdAQAuAAQKfyEAAwEACAnuHfoRAMACAAEACAnuHfoRAMACAAIABAk3Gc4YADEBAAAA.Moort:BAAALgAECgYJDwAAAA==.Mordecaii:BAAALgADCgcJCQAAAA==.Morganlefay:BAAALgADCgcJDAAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAAALgAECgYJCwAAAA==.Moyana:BAAALgAECgIJAgAAAA==.',
Ms='Msbehaven:BAAALgAECgYJEQAAAA==.',
Mt='Mthafknfreez:BAABLgAECn8UAAIDAAgJ6RQ5ZgALAgADAAgJ6RQ5ZgALAgAAAA==.',
My='Mynuturchin:BAAALgADCgYJCAAAAA==.',
['Mî']='Mîg:BAABLgAECn8UAAIWAAgJoAdpeAA9AQAWAAgJoAdpeAA9AQAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJBAABLgAECgQJBAAEAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgYJBgABLgAECgkJHwAQACofAA==.',
Ni='Nippy:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.',
No='Noriva:BAAALgADCgkJEAAAAA==.Notthechosen:BAAALgAECgEJAQABLgAECgcJGgABAOAZAA==.',
Ny='Nymeriã:BAAALgAECgMJAwAAAA==.Nymeriå:BAAALgADCgYJBwAAAA==.',
Ob='Obzy:BAAALgADCgYJBgABLgAECggJFQAWABUUAA==.',
Od='Odiedude:BAAALgADCgUJBQAAAA==.Odieous:BAAALgAECgIJBAAAAA==.',
Ok='Okamy:BAAALgAECgYJDAABLgAECgYJEgAEAAAAAA==.',
Om='Omeganemesis:BAAALgADCgQJBAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8VAAIWAAgJFRTJOAARAgAWAAgJFRTJOAARAgAAAA==.',
Or='Orghujon:BAAALgADCggJGQAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgADCgEJAQAAAA==.Palamon:BAAALgAECgMJBAAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBQAAAA==.Parthos:BAAALgAECgEJAQAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAABLgAFFH8JAAIVAAMJhxnmBgADAQAVAAMJhxnmBgADAQAAAA==.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgADCgEJAQAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAAALgAECgIJAwABLgAFFAMJCQAVAIcZAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pokedone:BAAALgADCgEJAQAAAA==.Polskashaman:BAAALgAECgYJEwAAAA==.Poptart:BAABLgAECn8UAAIcAAgJZhMlXQDLAQAcAAgJZhMlXQDLAQAAAA==.Power:BAAALgAECgYJCQABLgAFFAQJCwAcAColAA==.',
Pr='Prea:BAAALgAECgUJBgAAAA==.Primecarry:BAACLgAFFH8NAAIeAAUJ9yNOAQCwAQAeAAUJ9yNOAQCwAQAuAAQKfxcAAh4ACAkCI6YJANcCAB4ACAkCI6YJANcCAAAA.',
Pu='Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgQJBwAAAA==.',
['Pë']='Pëpsï:BAAALgAECgYJBwAAAA==.',
Qu='Quanah:BAAALgAECgMJBgAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgAEAAAAAA==.Raigko:BAAALgAECgQJBQAAAA==.Raintolin:BAAALgAECgQJBAABLgAECgcJGAAQAHAdAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Rassputen:BAABLgAECn8oAAIRAAkJPhmEAQA1AgARAAkJPhmEAQA1AgAAAA==.',
Re='Redjive:BAAALgAECgIJAQAAAA==.Redonkulos:BAAALgAFFAEJAwAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAVAPwPAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAABLgAECn8aAAMIAAcJYCMQEwBdAgAIAAYJECQQEwBdAgAHAAYJ1hx7DAAqAQAAAA==.Reliri:BAAALgAECgEJAQAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgcJCAAAAA==.Rider:BAAALgADCgYJBgABLgAFFAUJDQAeALQWAA==.Rinth:BAABLgAECn8eAAIUAAgJnCHeCQADAwAUAAgJnCHeCQADAwAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIYAAgJQhpDCABWAgAYAAgJQhpDCABWAgAAAA==.Roguen:BAABLgAECn8nAAIlAAgJnxIyBwBxAQAlAAgJnxIyBwBxAQABLgAECggJFAADAOkUAA==.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAAALgAECgUJCQABLgAECggJIwAUAEYaAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAAALgAECgYJDgAAAA==.Roulduke:BAAALgAECgYJEwAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Ryna:BAAALgADCgMJAgAAAA==.',
['Rù']='Rùckús:BAABLgAECn8ZAAIQAAgJzh2FJQCnAgAQAAgJzh2FJQCnAgABLgAECgkJGwALAEUSAA==.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8ZAAMYAAcJ/QoLIgD3AAAYAAcJ/QoLIgD3AAAcAAEJbQMEWAEmAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAFFAEJAQAEAAAAAA==.Sakiara:BAAALgAECgQJBQAAAA==.Sammybeans:BAABLgAECn8WAAIcAAcJ0hbDWADYAQAcAAcJ0hbDWADYAQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAAALgAECgUJCgAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAAALgAECgYJCwAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Se='Seceron:BAAALgAECgUJBQAAAA==.Sekai:BAAALgADCgQJBAAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8dAAMHAAgJ2AYtSQAUAQAHAAYJiwgtSQAUAQAIAAgJIwODEADvAAAAAA==.Serpentsin:BAAALgAECgEJAQAAAA==.',
Sg='Sgtslappy:BAABLgAECn8YAAIBAAcJ+BMAQwCYAQABAAcJ+BMAQwCYAQAAAA==.',
Sh='Shanarelle:BAABLgAECn8aAAIfAAgJzxkdHgBNAgAfAAgJzxkdHgBNAgAAAA==.Shasa:BAABLgAECn8iAAIjAAgJ3RsMCADoAQAjAAgJ3RsMCADoAQAAAA==.Shazik:BAAALgAECgEJAQAAAA==.Shinanìgans:BAAALgADCgkJCQAAAA==.Shmoopy:BAAALgAECgYJBgAAAA==.Shortyman:BAAALgAECgUJBQABLgAECgkJHwAQACofAA==.Shruikan:BAAALgAECgcJEwAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgQJBQAEAAAAAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAABLgAECn8UAAMQAAYJ1xxXcQClAQAQAAUJaR1XcQClAQARAAEJjhohQABNAAAAAA==.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAQAAAA==.Sisturfistur:BAAALgAECgQJBQAAAA==.',
Sk='Skunkpaw:BAAALgADCgUJBQAAAA==.Skysong:BAACLgAFFH8PAAMMAAUJmBNTAQCmAQAMAAUJjw9TAQCmAQALAAMJEw7hEgDoAAAuAAQKfxkABAwACAnJHcQMAA4CAAwABwlhG8QMAA4CAB0ABQl+EdwqABsBAAsAAwnVFz5CANoAAAAA.',
Sl='Slashedeye:BAABLgAECn8iAAIbAAgJ6BNEAgA3AgAbAAgJ6BNEAgA3AgAAAA==.',
Sm='Smellsoftree:BAAALgADCgQJBwAAAA==.',
Sn='Snowynn:BAAALgAECggJDwAAAA==.Snubby:BAABLgAECn8eAAMPAAgJwiNvDAD7AQAOAAYJ9yRHJACCAgAPAAUJriJvDAD7AQAAAA==.',
So='Soleil:BAAALgAECggJDQAAAA==.Solheim:BAACLgAFFH8GAAIUAAIJHB06BQCmAAAUAAIJHB06BQCmAAAuAAQKfx8AAhQACAkoIrsKAPcCABQACAkoIrsKAPcCAAAA.Souffle:BAABLgAECn8cAAMOAAcJYBc5EgB/AQAOAAcJYBc5EgB/AQAPAAEJAABjbQA6AAAAAA==.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMVAAgJ/A8kMgCJAQAVAAgJ/A8kMgCJAQAZAAEJ/wcXIgAzAAAAAA==.Spookypink:BAABLgAECn8WAAIcAAgJOCJEEAANAwAcAAgJOCJEEAANAwAAAA==.',
Sq='Squirtz:BAAALgAECgUJBQAAAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Strathz:BAABLgAECn8gAAMPAAgJOx6aCgAVAgAPAAYJOR+aCgAVAgAOAAYJaRtzEwB1AQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIeAAgJ1hq6GABNAgAeAAgJ1hq6GABNAgAAAA==.Summerset:BAAALgAECgYJCgAAAA==.Sushi:BAAALgAECgIJAwAAAA==.',
Sy='Sylatis:BAACLgAFFH8XAAMUAAgJnha/AwAIAgAUAAYJiRS/AwAIAgATAAUJZReaAgAaAQAuAAQKfxYAAxQACAk0JTgNANoCABQACAk0JTgNANoCABMAAwmiHuMPAGoAAAAA.Sylvanâs:BAAALgAECgEJAQAAAA==.Sylvara:BAAALgAECgMJAwAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.',
['Sö']='Söultender:BAAALgAECgUJEQABLgAECgYJBgAEAAAAAA==.',
Ta='Taichi:BAACLgAFFH8FAAImAAIJrgwnCQCEAAAmAAIJrgwnCQCEAAAuAAQKfyAAAiYACAmVHEUMAJACACYACAmVHEUMAJACAAAA.Talys:BAACLgAFFH8PAAIdAAYJ/xLMAADoAQAdAAYJ/xLMAADoAQAuAAQKfyEAAh0ACQmUGIEIALICAB0ACQmUGIEIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgADCgUJBQAAAA==.Tarth:BAACLgAFFH8QAAIoAAUJWiQ/AACxAQAoAAUJWiQ/AACxAQAuAAQKfxcAAigACAkEJmsBAEIDACgACAkEJmsBAEIDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8UAAIdAAcJfBnEAwChAQAdAAcJfBnEAwChAQAAAA==.Taïko:BAAALgADCgEJAQAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgUJCAABLgAECgcJGAAQAHAdAA==.Tenniell:BAAALgAECgQJCQAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAAALgAECgYJEAAAAA==.',
Th='Thab:BAAALgAECgMJBAABLgAECgYJFgALAJ4VAA==.Thabk:BAABLgAECn8WAAMLAAYJnhUQJwCEAQALAAYJnhUQJwCEAQAMAAEJaAc2QwAoAAAAAA==.Thalian:BAAALgAECgMJAQAAAA==.Tharit:BAAALgADCgYJCgAAAA==.Theshortbuss:BAAALgAECgUJCAAAAA==.Thingtwò:BAAALgADCgUJBQAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDQAAAA==.',
Ti='Tiddybear:BAAALgAECgEJAQAAAA==.Timerunhunt:BAAALgADCgMJAwAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAAALgAECgQJBwAAAA==.Tokken:BAACLgAFFH8JAAIBAAQJKgp6AwA6AQABAAQJKgp6AwA6AQAuAAQKfyEAAgEACQnpHEQMAPYCAAEACQnpHEQMAPYCAAAA.',
Tr='Treebeast:BAACLgAFFH8FAAIKAAIJGhANFwCbAAAKAAIJGhANFwCbAAAuAAQKfxQAAgoABwlnH4QcAC0CAAoABwlnH4QcAC0CAAAA.Trojen:BAAALgADCgcJBwAAAA==.',
Tu='Tubularoso:BAAALgAECgQJCQAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Ul='Ulanda:BAAALgAECgMJBQAAAA==.',
Um='Umako:BAACLgAFFH8KAAMnAAUJ8hyVAQBvAQAnAAQJTB6VAQBvAQAlAAIJAxwkEwCzAAAuAAQKfyEAAycACQmuIfIAAEQDACcACQmUIfIAAEQDACUACAlGFyQdABYCAAAA.',
Un='Underbogg:BAAALgADCgUJBQAAAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Va='Vaedric:BAAALgADCgUJBgAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgYJEAAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAABLgAECn8aAAIBAAcJ4Bm2JwAfAgABAAcJ4Bm2JwAfAgAAAA==.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8ZAAIBAAgJzCWFFwCQAgABAAgJzCWFFwCQAgAAAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8aAAIWAAgJJQrtFgBHAQAWAAgJJQrtFgBHAQAAAA==.Voids:BAAALgADCgcJCgAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAAALgAECgYJBwABLgAECggJIwAUAEYaAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgAEAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMSAAgJwBqIIwAKAgASAAgJwBqIIwAKAgAKAAQJ6QWTGwCKAAAAAA==.',
Wa='Walkerwhite:BAAALgAECgUJCAABLgAECggJGAADAAAZAA==.Warjd:BAAALgAECgUJDAAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Wesjin:BAABLgAECn8WAAImAAgJIBtVDwBjAgAmAAgJIBtVDwBjAgAAAA==.',
Wh='Whiskee:BAABLgAECn8dAAMpAAgJdSGzBADNAgApAAgJdSGzBADNAgAfAAEJJQMt1wAqAAAAAA==.Whitey:BAAALgADCgUJBQAAAA==.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgADCggJFQAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wy='Wyndia:BAAALgAECgUJCgAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJBgAAAA==.',
Xb='Xbert:BAAALgADCgcJBwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8OAAIDAAUJ1RgLDgCqAQADAAUJ1RgLDgCqAQAuAAQKfxYAAgMACAn+IYguALgCAAMACAn+IYguALgCAAAA.',
Xi='Xiia:BAAALgAECgYJEgAAAA==.',
Xx='Xxoouu:BAAALgAECgcJBgABLgAECgkJCQAEAAAAAA==.Xxuusham:BAAALgAECgcJDQAAAA==.Xxuuvoker:BAAALgAECgkJCQAAAA==.',
Ya='Yaoguai:BAAALgAECgcJEgAAAA==.Yasei:BAAALgAECgEJAQAAAA==.Yawgmoth:BAAALgAECggJEwAAAA==.',
Za='Zammboomafoo:BAAALgAECgYJCgAAAA==.Zanian:BAAALgAECgYJDgAAAA==.Zarthie:BAAALgADCgYJBgABLgAECgYJDgAEAAAAAA==.Zarthy:BAAALgAECgYJDgAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgQJBAAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zo='Zodd:BAAALgADCgEJAgAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgMJBgABLgAECggJGQADAEshAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAIpAAgJMBv0BQCjAgApAAgJMBv0BQCjAgAAAA==.',
['Zà']='Zàánn:BAAALgAECgQJBwAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAECggJHQAbAPUdAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAECggJHQAbAPUdAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgADCgcJBwAAAA==.',
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

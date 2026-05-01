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

local lookup = {'Warrior-Fury','Warrior-Arms','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Hunter-Marksmanship','Shaman-Enhancement','Mage-Arcane','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Hunter-Survival','Monk-Brewmaster','Evoker-Preservation','Druid-Balance','Paladin-Protection','Warlock-Affliction','Paladin-Holy','Mage-Fire','Paladin-Retribution','Druid-Restoration','Priest-Discipline','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJDAAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Admaris:BAAALgAECgYJEgAAAA==.',
Ag='Age:BAABLgAECn8dAAMBAAgJRBdDDwDEAQABAAgJRBdDDwDEAQACAAMJoA0PJwC2AAAAAA==.Agni:BAACLgAFFH8QAAIDAAUJASOSDwCbAQADAAUJASOSDwCbAQAuAAQKfyUAAgMACQnmI6gEALYDAAMACQnmI6gEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8YAAIBAAYJtRKTHQBEAQABAAYJtRKTHQBEAQAAAA==.',
Al='Alavendis:BAABLgAECn8UAAIEAAYJoBzeHACGAQAEAAYJoBzeHACGAQABLgAECgQJBgAFAAAAAA==.Alexá:BAAALgAECgQJBwABLgAECgcJFAAGABsaAA==.Almight:BAAALgAECgIJAgAAAA==.Alnasham:BAACLgAFFH8RAAIHAAUJJR2mAADMAQAHAAUJJR2mAADMAQAuAAQKfxwAAgcACAl5H5wGAIwCAAcACAl5H5wGAIwCAAAA.Alphashadow:BAAALgAECgQJBAAAAA==.Alvoka:BAABLgAECn8ZAAMDAAgJCRSWagAAAgADAAgJCRSWagAAAgAIAAQJlg/wBAAFAQAAAA==.',
Am='Amarillos:BAAALgADCgIJAgAAAA==.Amarillys:BAACLgAFFH8FAAIJAAIJQh1wCwCsAAAJAAIJQh1wCwCsAAAuAAQKfyMAAwkACQlCHYgFAGkCAAkACQlCHYgFAGkCAAoAAQnYFJNjADEAAAAA.Ambrotos:BAAALgAECgYJDgAAAA==.Amither:BAAALgAECgYJBgAAAA==.Ammutseba:BAABLgAECn8iAAILAAgJZhphBACvAQALAAgJZhphBACvAQAAAA==.Amperage:BAAALgAECgEJAQAAAA==.',
An='Anfall:BAAALgAECgcJBwAAAA==.Angermeier:BAABLgAECn8XAAIBAAYJ3RjONgDNAQABAAYJ3RjONgDNAQAAAA==.Angrylady:BAAALgAECgEJAQAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAgAAAA==.Arg:BAAALgAECgEJAQAAAA==.Arowin:BAAALgAECggJDQAAAA==.Arthaniis:BAABLgAECn8bAAIMAAgJfiD9CAACAwAMAAgJfiD9CAACAwAAAA==.',
As='Asdar:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgQJCAAAAA==.',
Au='Audideath:BAAALgAECgYJCwAAAA==.Audry:BAAALgADCgUJBQAAAA==.Augtistic:BAABLgAECn8bAAMNAAkJRRI2FABgAQANAAkJRRI2FABgAQAOAAYJcwIDKwDFAAAAAA==.Aulrelle:BAABLgAECn8UAAMPAAcJwxOYEQCTAQAPAAcJwxOYEQCTAQAQAAQJBAaxLgCMAAABLgAECgQJDAAFAAAAAA==.Auurdeath:BAAALgAECgYJCgAAAA==.',
Av='Avidswolf:BAABLgAECn8XAAIDAAYJyxHtYQAYAQADAAYJyxHtYQAYAQAAAA==.Avãcyn:BAABLgAECn8VAAMCAAYJxAYZGwChAAABAAYJCAXNbwD5AAACAAUJngUZGwChAAAAAA==.',
Aw='Aw:BAACLgAFFH8MAAIRAAYJiSMYAAAuAgARAAYJiSMYAAAuAgAuAAQKfxgAAhEACAmdJowBAJEDABEACAmdJowBAJEDAAAA.Awppenheimer:BAABLgAECn8fAAMSAAgJZB2NEADKAQATAAcJOhsSGgDZAQASAAYJdRyNEADKAQAAAA==.',
Ax='Ax:BAEBLgAFFH8PAAMUAAUJdA+RIgAyAQAUAAQJdA+RIgAyAQAVAAEJAABJJQAAAAAAAA==.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAAALgAFFAIJAgAAAA==.',
Ba='Babycarrots:BAAALgAECgYJBwAAAA==.Baconz:BAABLgAECn8bAAMMAAgJMxZuJADtAQAMAAgJMxZuJADtAQAWAAEJ9QIwagAkAAAAAA==.Bakeon:BAABLgAECn8cAAMWAAgJ0hUXEAD2AQAWAAgJ0hUXEAD2AQAMAAMJYAQkdABxAAAAAA==.Bakkaz:BAAALgADCgYJBgAAAA==.Baldozhi:BAAALgAECgYJCgAAAA==.Bangbang:BAAALgAFFAEJAQAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAAALgAECgQJDAAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECgYJFAAXAAcOAA==.Beardcheese:BAAALgAECgIJAQAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAAALgAECgYJEQAAAA==.',
Bi='Bink:BAABLgAECn8ZAAIYAAkJ9xpEBADXAgAYAAkJ9xpEBADXAgAAAA==.Birblock:BAABLgAFFH8HAAITAAUJAA0THwAlAQATAAUJAA0THwAlAQABLgAFFAgJHQAYAKQYAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAABLgAECn8TAAIEAAYJ8gatSgDGAAAEAAYJ8gatSgDGAAAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAAALgAECgcJEgAAAA==.',
Bo='Bobbo:BAAALgADCgIJAgAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Boomin:BAAALgAECggJDgAAAA==.',
Br='Braass:BAAALgADCgYJCgABLgAECgQJDAAFAAAAAA==.Breachnclear:BAAALgAECgQJBAAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8jAAIZAAgJAhscCQD9AQAZAAgJAhscCQD9AQAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgAECgQJBAABLgAECgUJCQAFAAAAAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8cAAIWAAgJgyHEAgDwAgAWAAgJgyHEAgDwAgAAAA==.Brutechaos:BAAALgADCgQJBAABLgAECggJHAAWAIMhAA==.',
Bu='Buffygirl:BAABLgAECn8bAAMNAAgJ5xX1CgDZAQANAAgJ5xX1CgDZAQAaAAUJbA0DGACCAAAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECgkJEgAAAA==.',
['Bå']='Båne:BAABLgAECn8VAAIEAAYJRg4hQADmAAAEAAYJRg4hQADmAAAAAA==.',
Ca='Carnal:BAAALgADCgUJCAAAAA==.Casini:BAAALgADCgMJAwAAAA==.Cazic:BAAALgAECgEJAwAAAA==.',
Ce='Cedren:BAACLgAFFH8FAAIEAAMJOxcJJwCkAAAEAAMJOxcJJwCkAAAuAAQKfxkAAgQACQnbHfAdAJ4CAAQACQnbHfAdAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIEAAcJsyKqIQCHAgAEAAcJsyKqIQCHAgAAAA==.Certified:BAAALgAECgYJAwAAAA==.',
Ch='Chalix:BAAALgAECgEJAQAAAA==.Cheapheal:BAABLgAECn8tAAIbAAkJjiAyAQATAwAbAAkJjiAyAQATAwAAAA==.Cheburashka:BAACLgAFFH8RAAIMAAUJox6oAwCwAQAMAAUJox6oAwCwAQAuAAQKfxcAAgwACAnNIgsPALYCAAwACAnNIgsPALYCAAAA.Chewymentos:BAAALgAECgUJBwABLgAECggJGwAcAGUKAA==.Chimerabob:BAAALgAECgYJDAAAAA==.Chunkyhunter:BAAALgAECgYJBgABLgAFFAUJDQAQAEcWAA==.Chunkymonkey:BAACLgAFFH8NAAMQAAUJRxbaBABMAQAQAAUJRxbaBABMAQAZAAIJGA6yHACKAAAuAAQKfxsAAxAACAlKISoLAMcCABAACAlKISoLAMcCABkABQlxGvI9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cl='Clappncheeks:BAABLgAECn8ZAAIYAAcJOh9OBQAmAgAYAAcJOh9OBQAmAgAAAA==.Claudefrollo:BAAALgAECgYJEwAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corlem:BAAALgAECgMJAgAAAA==.Corrüpt:BAAALgAECgYJCQAAAA==.',
Cr='Crimsa:BAABLgAECn8fAAIdAAcJEwbXDwAwAQAdAAcJEwbXDwAwAQAAAA==.Crimsongost:BAAALgAECgEJAQAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Cryogen:BAABLgAECn8ZAAIbAAgJEyDRBwAYAgAbAAgJEyDRBwAYAgAAAA==.',
Cs='Cs:BAABLgAECn8oAAIZAAkJFCDUAwBSAwAZAAkJFCDUAwBSAwAAAA==.',
Cu='Curufin:BAAALgAECgMJBgAAAA==.',
Da='Daddysmooth:BAAALgAECgIJAgAAAA==.Daemon:BAABLgAECn8ZAAIUAAcJgB5IQgAwAgAUAAcJgB5IQgAwAgAAAA==.Daemonproph:BAAALgAECgYJEgAAAA==.Dakini:BAABLgAECn8XAAIeAAYJ6yPNCQA6AgAeAAYJ6yPNCQA6AgAAAA==.Daktaklakpak:BAAALgAFFAMJBAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8jAAIcAAgJhh9WBADDAgAcAAgJhh9WBADDAgAAAA==.Dangerruss:BAABLgAECn8XAAIcAAYJXhIdFwBjAQAcAAYJXhIdFwBjAQAAAA==.Darkhaven:BAAALgADCgIJAgAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAACLgAFFH8GAAIfAAMJIhuGAAAVAQAfAAMJIhuGAAAVAQAuAAQKfx4AAx8ACAn1HR8BAMACAB8ACAn1HR8BAMACAAMABAkrCFUZAcwAAAAA.Dasmonkey:BAAALgAECgIJAgAAAA==.Daxos:BAABLgAECn8iAAIDAAkJEBbeGQARAgADAAkJEBbeGQARAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJCgAAAA==.Deelahn:BAABLgAECn8UAAMJAAYJJwoGIQD5AAAJAAYJJwoGIQD5AAAKAAEJXQB0SAAZAAAAAA==.Demideudle:BAAALgAECgEJAQAAAA==.Demonicchoas:BAABLgAECn8wAAMSAAkJeSAZAQAmAwASAAgJJyIZAQAmAwATAAcJIhq9DQA+AgAAAA==.Denagorn:BAABLgAECn8wAAIgAAkJTxwXGADYAgAgAAkJTxwXGADYAgAAAA==.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAAALgAECgcJDQAAAA==.Deutzfr:BAAALgAFFAEJAQAAAA==.',
Do='Dominant:BAABLgAECn8fAAIDAAgJcRxaFwAiAgADAAgJcRxaFwAiAgAAAA==.Dooma:BAABLgAFFH8JAAITAAYJXRW+BQCpAQATAAYJXRW+BQCpAQAAAA==.Dorgie:BAAALgAECgUJDwABLgAFFAIJBAAFAAAAAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIDAAgJSiHZIQDsAgADAAgJSiHZIQDsAgAAAA==.',
Dr='Draco:BAAALgADCgEJAQAAAA==.Drag:BAAALgAECgQJBQAAAA==.Dragon:BAABLgAECn8YAAIaAAkJFhBWFgDoAQAaAAkJFhBWFgDoAQAAAA==.Drbob:BAAALgAECgQJBQAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAAALgAFFAMJAwABLgAFFAUJEQAeAC0kAA==.Drock:BAABLgAECn8TAAIEAAcJlx2jDwD1AQAEAAcJlx2jDwD1AQAAAA==.Druidgale:BAABLgAECn8cAAIhAAgJKgwdMQAXAQAhAAgJKgwdMQAXAQAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAAALgAECgcJEQAAAA==.Drybonez:BAABLgAECn8WAAMMAAcJ5BPBGgA9AQAMAAYJFxfBGgA9AQAWAAEJxgcObAAhAAAAAA==.Drygth:BAABLgAECn8YAAQKAAkJiSCdDgCZAgAKAAcJGiKdDgCZAgAJAAcJ4RpWBwA7AgAiAAEJbwm6VAA4AAAAAA==.',
Du='Dubshox:BAABLgAECn8gAAIMAAgJNRwSCAAfAgAMAAgJNRwSCAAfAgAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ea='Earthly:BAAALgAECgEJAQAAAA==.',
Ei='Eisador:BAABLgAECn8XAAIjAAgJWw5mKQBwAQAjAAgJWw5mKQBwAQAAAA==.',
El='Elemotional:BAABLgAECn8UAAIHAAgJlx0OAgBiAgAHAAgJlx0OAgBiAgAAAA==.',
Eq='Equilibrio:BAABLgAECn8aAAIkAAgJKxyRBAAkAgAkAAgJKxyRBAAkAgAAAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAABLgAECn8UAAQGAAcJGxolCQBDAQAGAAYJNBklCQBDAQAYAAIJMB+nHQC7AAAjAAEJkRoAAAAAAAAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECgYJFwANAJ4VAA==.',
Fa='Faelthas:BAACLgAFFH8TAAIZAAUJ5STIAQDvAQAZAAUJ5STIAQDvAQAuAAQKfzAAAhkACAkrJnQBAOkCABkACAkrJnQBAOkCAAAA.Fathercoast:BAABLgAECn8kAAMKAAgJEx5iCAAAAgAKAAgJEx5iCAAAAgAiAAYJWBbxHwCUAQAAAA==.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAAALgAECgcJDQAAAA==.Felstrider:BAAALgAECgQJBwAAAA==.Fembouyant:BAABLgAECn8XAAIlAAkJsxSGBAAVAgAlAAkJsxSGBAAVAgAAAA==.Ferador:BAACLgAFFH8VAAMGAAUJWhFaCgDQAAAGAAQJ6wZaCgDQAAAjAAIJURt5JAC1AAAuAAQKfxkAAwYACAlgHW4jAAkCAAYACAnFFW4jAAkCACMABAmZGbRrACUBAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.Fistsphoyou:BAAALgADCgQJBAAAAA==.',
Fl='Flowmo:BAAALgAECgYJBwABLgAECggJFwAZANobAA==.',
Fo='Fortou:BAAALgADCgMJAgAAAA==.Fourbees:BAAALgAECgYJCwAAAA==.',
Fr='Frizly:BAABLgAECn8cAAMJAAgJ2QbqGwAmAQAJAAgJ2QbqGwAmAQAKAAEJ3ADHSAATAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIDAAkJ/hGXXQAhAgADAAkJ/hGXXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.',
Ga='Galdrell:BAAALgAECgYJCwAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgADCgEJAQAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8gAAMUAAkJKh9LEwAIAwAUAAkJKh9LEwAIAwAlAAEJDgcTGQArAAAAAA==.',
Gn='Gnnome:BAABLgAECn8ZAAIDAAgJDAoCQgBoAQADAAgJDAoCQgBoAQAAAA==.',
Go='Gog:BAAALgAECgYJCAAAAA==.Goodolruss:BAAALgADCgUJBQAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIVAAkJ3yVeAADPAwAVAAkJ3yVeAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8gAAIUAAgJrB7uEwAaAgAUAAgJrB7uEwAaAgAAAA==.Grimaldus:BAABLgAECn8ZAAIcAAkJah99BAC9AgAcAAkJah99BAC9AgAAAA==.Grimmortal:BAAALgAECgcJBwAAAA==.Grimreaper:BAABLgAECn8oAAMmAAkJux81AAD9AgAmAAkJux81AAD9AgAXAAIJexAxUwCRAAAAAA==.Groag:BAAALgAECgYJDAAAAA==.Groovytony:BAAALgAECgYJBgAAAA==.Gruffles:BAABLgAECn8VAAIhAAYJAiHXGgCpAQAhAAYJAiHXGgCpAQAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8aAAIEAAcJjx1SIwBgAQAEAAcJjx1SIwBgAQAAAA==.',
Ha='Haarp:BAAALgAECgQJBQAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handimage:BAAALgADCgEJAQABLgAECgcJFwAKALwSAA==.Handipriest:BAABLgAECn8XAAIKAAcJvBK4EACFAQAKAAcJvBK4EACFAQAAAA==.Haqq:BAABLgAECn8WAAIBAAgJHAtOFACSAQABAAgJHAtOFACSAQAAAA==.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgADCgYJBgABLgAECgYJBgAFAAAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8iAAIUAAcJGBGXMQBzAQAUAAcJGBGXMQBzAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgAECgUJBQAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8fAAIUAAgJ3CIeBgC+AgAUAAgJ3CIeBgC+AgAAAA==.',
Ho='Hoafustis:BAAALgADCgYJCQAAAA==.Hobo:BAAALgAECgYJEQAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBQAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Hundard:BAAALgAECgIJAgAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAAALgAECgYJDQABLgAECggJGQABAMwlAA==.Iblisshaytan:BAAALgAECgcJEQABLgAECggJIgADAK4ZAA==.Ibtrollin:BAAALgAECgEJAQAAAA==.',
Ig='Ignacious:BAABLgAECn8rAAQWAAgJGyXiAgBQAwAWAAgJGyXiAgBQAwAMAAYJIR0CEgCPAQAHAAEJVg8PLAA1AAAAAA==.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAAALgAECgYJEwAAAA==.Immolate:BAABLgAECn8aAAQTAAkJzyECNgA0AgATAAcJbx8CNgA0AgASAAUJsCKTFgCVAQAdAAEJAAAyJABhAAAAAA==.',
In='Infamous:BAAALgAECgQJBAAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJEQAAAA==.',
Io='Ionissa:BAAALgAECgcJBwAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAgAAAA==.',
Is='Ischia:BAACLgAFFH8QAAIJAAUJLQ9FAgCNAQAJAAUJLQ9FAgCNAQAuAAQKfxgAAwkACAkdEjEgAOABAAkACAkdEjEgAOABAAoAAQm/AaVqACEAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIXAAIJpx+fEADFAAAXAAIJpx+fEADFAAAuAAQKfxgAAhcABwliI8MXAEsCABcABwliI8MXAEsCAAAA.Jallypally:BAAALgADCggJCQAAAA==.Janokdiso:BAAALgAECgEJAQAAAA==.Javeighqueas:BAAALgADCgQJAgABLgAFFAIJAgAFAAAAAA==.',
Jc='Jch:BAACLgAFFH8VAAMjAAYJ1x1+AADCAQAjAAUJEx5+AADCAQAGAAEJ5hy0EABhAAAuAAQKfyEAAyMACQnbI/0BAH8DACMACQnbI/0BAH8DAAYAAQmiBy6PACwAAAAA.',
Je='Jedijed:BAAALgAECgYJBgABLgAFFAMJAwAFAAAAAA==.Jedikepjr:BAAALgAFFAMJAwAAAA==.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECgIJAgAAAA==.Joneztown:BAABLgAECn8WAAIQAAkJQRq0CwC/AgAQAAkJQRq0CwC/AgAAAA==.Jordantheorc:BAABLgAECn8lAAMjAAgJ/B5IEQCvAgAjAAgJ/B5IEQCvAgAGAAIJvwKZgQBAAAAAAA==.',
Jp='Jprottsoo:BAABLgAECn8cAAIbAAkJih59AgDDAgAbAAkJih59AgDDAgAAAA==.',
Jt='Jtee:BAABLgAECn8oAAIeAAgJexXzDAAIAgAeAAgJexXzDAAIAgAAAA==.',
Ju='Jukkrit:BAAALgADCgEJAQAAAA==.',
Jy='Jy:BAAALgADCgMJAwAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8iAAIhAAgJiAvqLQAnAQAhAAgJiAvqLQAnAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECgkJFgAdAFUWAA==.Karoo:BAAALgADCgYJBgAAAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAQAAAA==.Keizzer:BAABLgAECn8hAAIgAAkJkh8PHgC3AgAgAAkJkh8PHgC3AgAAAA==.Kelesa:BAAALgADCgEJAQAAAA==.Keshisaru:BAAALgAECggJDgAAAA==.',
Kh='Kharms:BAABLgAECn8aAAIQAAgJNByIBgAkAgAQAAgJNByIBgAkAgAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.',
Kl='Klunder:BAABLgAECn8cAAIWAAgJiR/XAwDJAgAWAAgJiR/XAwDJAgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIZAAgJ2hv9DAC7AQAZAAgJ2hv9DAC7AQAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAABLgAECn8XAAIjAAkJUxuqCABvAgAjAAkJUxuqCABvAgAAAA==.Kostik:BAAALgAECgQJBAAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAABLgAECn8hAAIEAAkJSxMWDgAGAgAEAAkJSxMWDgAGAgAAAA==.Krux:BAAALgAECgIJAwAAAA==.',
Ky='Kybinc:BAAALgADCgMJAwAAAA==.',
La='Lacie:BAAALgADCgUJBQAAAA==.Laennaya:BAABLgAECn8kAAIdAAgJLQs7BABeAQAdAAgJLQs7BABeAQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAAALgAECgQJBQAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgIJAwAAAA==.Lazyfrost:BAABLgAECn8dAAIDAAkJGBobQAB5AgADAAkJGBobQAB5AgAAAA==.Lazyunholy:BAAALgADCgkJCAAAAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8cAAMeAAcJoR+WEwB2AgAeAAcJoR+WEwB2AgAgAAEJXA4aPwE1AAAAAA==.Lethô:BAABLgAECn8oAAIhAAkJCyELAQB5AwAhAAkJCyELAQB5AwAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Lickemlow:BAAALgAECgEJAQAAAA==.Liesx:BAAALgADCgQJBAAAAA==.Lilboothang:BAABLgAECn8ZAAITAAgJXxPYGQDbAQATAAgJXxPYGQDbAQAAAA==.Lilzarthe:BAAALgAECgMJAwABLgAECgYJFAANALAVAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Loachella:BAAALgADCgUJBQAAAA==.Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAABLgAECn8nAAIEAAkJnSQZAgC3AwAEAAkJnSQZAgC3AwAAAA==.Loko:BAACLgAFFH8RAAIbAAUJuhooBgBmAQAbAAUJuhooBgBmAQAuAAQKfy0AAhsACQnXI9wAADcDABsACQnXI9wAADcDAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAECgcJCQAAAA==.Louiie:BAABLgAECn8UAAIXAAYJBw4LFAA8AQAXAAYJBw4LFAA8AQAAAA==.',
Lu='Luckygrapes:BAABLgAECn8ZAAIPAAcJtR/KDgBqAgAPAAcJtR/KDgBqAgAAAA==.Lukdanuke:BAAALgAECgYJCgAAAA==.Luxxus:BAAALgAECgcJCwABLgAECgkJIQAgAJIfAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAABLgAECn8XAAIMAAYJuRAOJAAAAQAMAAYJuRAOJAAAAQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8XAAITAAcJVRHLXgCsAQATAAcJVRHLXgCsAQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAIQAAcJnh0JFABPAgAQAAcJnh0JFABPAgAAAA==.Mantakore:BAACLgAFFH8KAAIaAAQJeAiJDAAKAQAaAAQJeAiJDAAKAQAuAAQKfy8AAhoACAmNGTMFAAwCABoACAmNGTMFAAwCAAAA.Marcdruid:BAAALgAECgEJAQAAAA==.Maubles:BAAALgAECgYJBgABLgAFFAIJCAAcAGwUAA==.',
Me='Meadöw:BAAALgADCgIJAgAAAA==.Meiling:BAAALgADCgcJBwAAAA==.Meladra:BAAALgADCgcJBwAAAA==.Menopaws:BAAALgAECgkJEQAAAA==.Mertrik:BAABLgAECn8aAAMMAAgJvxy6EAChAgAMAAgJvxy6EAChAgAHAAEJuBh8KQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8eAAIVAAgJeiBqCwBdAgAVAAgJeiBqCwBdAgAAAA==.Mikailla:BAAALgAFFAIJAwABLgAECgEJAQAFAAAAAA==.Mikayy:BAACLgAFFH8RAAIXAAUJAyXIAgCOAQAXAAUJAyXIAgCOAQAuAAQKfykAAxcACQk+JM0BALsCABcACQn7I80BALsCACcAAQlWJWoPAGsAAAAA.Milenko:BAABLgAECn8iAAIRAAcJnSTmAgB6AgARAAcJnSTmAgB6AgAAAA==.Milly:BAAALgAECgEJAgABLgAECgcJIgARAJ0kAA==.Mimid:BAAALgAECgYJDAAAAA==.Mimonk:BAAALgAECgQJBAAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minii:BAAALgADCgUJBQAAAA==.Minteafresh:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8QAAMBAAUJpBNQBQCdAQABAAUJhxJQBQCdAQACAAEJDBLhDwBXAAAuAAQKfyEAAwEACAnuHfgRAMACAAEACAnuHfgRAMACAAIABAk3GdAYADABAAAA.Moort:BAAALgAECgYJDwAAAA==.Moothafacka:BAAALgADCgcJBwAAAA==.Mordecaii:BAAALgAECgIJAQAAAA==.Morganlefay:BAAALgADCgcJEgAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAAALgAECgYJDwAAAA==.Moyana:BAAALgAECgQJBQAAAA==.',
Ms='Msbehaven:BAABLgAECn8XAAITAAYJCgUGZgDEAAATAAYJCgUGZgDEAAAAAA==.',
Mt='Mthafknfreez:BAABLgAECn8iAAIDAAgJrhnwGwAEAgADAAgJrhnwGwAEAgAAAA==.',
My='Mynuturchin:BAAALgADCgYJCQAAAA==.',
['Mî']='Mîg:BAABLgAECn8YAAIEAAcJ3A0NQADnAAAEAAcJ3A0NQADnAAAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJBAABLgAECgQJDAAFAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgYJBgABLgAECgkJIAAUACofAA==.',
Ni='Nilfalath:BAAALgADCgYJBwAAAA==.Nippy:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.',
No='Noriva:BAAALgAECgEJAQAAAA==.Notthechosen:BAAALgAECgEJAQABLgAECggJHAABAE8YAA==.',
Ny='Nymeriã:BAAALgAECgQJBwAAAA==.Nymeriå:BAAALgADCgYJBwAAAA==.',
Ob='Obzy:BAAALgADCgYJBgABLgAFFAIJAgAFAAAAAA==.Obzz:BAAALgAFFAIJAgAAAA==.',
Od='Odiedude:BAAALgADCgUJBQAAAA==.Odieous:BAAALgAECgIJBAAAAA==.',
Ok='Okamy:BAAALgAECgcJEwABLgAECgcJFAAGABsaAA==.',
Om='Omeganemesis:BAAALgADCgQJBAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8VAAIEAAgJFRTKOAARAgAEAAgJFRTKOAARAgABLgAFFAIJAgAFAAAAAA==.',
Or='Orghujon:BAAALgAECgUJCAAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgAECgcJBwAAAA==.Palamon:BAAALgAECgMJBgAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBgAAAA==.Papadaddy:BAAALgADCgUJBQAAAA==.Parthos:BAAALgAECgYJCwAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAABLgAFFH8MAAIZAAMJDx3XEgADAQAZAAMJDx3XEgADAQAAAA==.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgAECgEJAQAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAAALgAECgIJAwABLgAFFAMJDAAZAA8dAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pokedone:BAAALgADCgEJAQAAAA==.Polskashaman:BAABLgAECn8ZAAIHAAYJgBMaCgBEAQAHAAYJgBMaCgBEAQAAAA==.Poptart:BAACLgAFFH8FAAIgAAMJVgdAJgDPAAAgAAMJVgdAJgDPAAAuAAQKfxQAAiAACAlmEyFdAMsBACAACAlmEyFdAMsBAAAA.Power:BAAALgAECgYJCQABLgAFFAQJDgAgAHAlAA==.',
Pr='Prea:BAAALgAECgUJBgAAAA==.Premiumferal:BAAALgAECgYJBgABLgAECgkJIAAUACofAA==.Primecarry:BAACLgAFFH8RAAIeAAUJLSSpAQAJAgAeAAUJLSSpAQAJAgAuAAQKfxcAAh4ACAkCI6EJANcCAB4ACAkCI6EJANcCAAAA.',
Pu='Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgYJDQAAAA==.',
['Pë']='Pëpsï:BAAALgAECgYJBwAAAA==.',
Qu='Quanah:BAAALgAECgMJBgAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgAFAAAAAA==.Raigko:BAAALgAECgQJBQAAAA==.Raintolin:BAAALgAECgQJCAABLgAECgcJGQAUAIAeAA==.Raiva:BAAALgADCgcJBwABLgAECgcJGwAUAAIdAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Rassputen:BAABLgAECn8oAAIVAAkJPhlxBQDbAQAVAAkJPhlxBQDbAQAAAA==.',
Re='Redjive:BAAALgAECgIJAQAAAA==.Redonkulos:BAAALgAFFAIJBAAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAZAPwPAA==.Redthorne:BAAALgADCgMJAwAAAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAABLgAECn8cAAMKAAgJ4R4SEwBdAgAKAAcJsx4SEwBdAgAJAAYJ1hwvHAAkAQAAAA==.Reliri:BAAALgAECgEJAgAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgcJDAAAAA==.Rider:BAAALgADCgYJBgABLgAFFAUJEQAeAL0XAA==.Rinth:BAABLgAECn8hAAMGAAkJKCLiCQADAwAGAAgJnCHiCQADAwAjAAMJkyH+OAAvAQAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIcAAgJQhpDCABWAgAcAAgJQhpDCABWAgAAAA==.Roguen:BAABLgAECn8vAAIXAAgJ5RSiBwD3AQAXAAgJ5RSiBwD3AQABLgAECggJIgADAK4ZAA==.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAAALgAECgUJCQABLgAFFAMJBwAGAKMJAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAAALgAECgYJDgAAAA==.Roulduke:BAAALgAECgYJEwAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Rylearria:BAAALgADCgMJAwAAAA==.Ryna:BAAALgADCgYJAgAAAA==.',
['Rù']='Rùckús:BAABLgAECn8iAAIUAAgJryCbCwBtAgAUAAgJryCbCwBtAgABLgAECgkJGwANAEUSAA==.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8bAAMcAAgJZQrQEAD1AAAcAAgJZQrQEAD1AAAgAAEJbQMmWAEmAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Sakiara:BAAALgAECgQJBgAAAA==.Sammybeans:BAABLgAECn8bAAIgAAcJ0ha8WADYAQAgAAcJ0ha8WADYAQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAAALgAECgYJCwAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAAALgAECggJDgAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Sc='Scrandle:BAAALgADCgEJAQABLgADCgMJAwAFAAAAAA==.Screwball:BAAALgADCgEJAQAAAA==.',
Se='Seceron:BAAALgAECgYJCwAAAA==.Sekai:BAAALgAECgEJAQAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8kAAMKAAgJMAS5HAAXAQAKAAgJMAS5HAAXAQAJAAYJiwgySQAUAQAAAA==.Serpentsin:BAAALgAECgMJBAAAAA==.',
Sg='Sgtslappy:BAABLgAECn8hAAIBAAgJrRfaCgD9AQABAAgJrRfaCgD9AQAAAA==.',
Sh='Shanarelle:BAABLgAECn8aAAIhAAgJzxkgHgBNAgAhAAgJzxkgHgBNAgAAAA==.Shasa:BAABLgAECn8qAAIjAAgJshyZEQAHAgAjAAgJshyZEQAHAgAAAA==.Shazik:BAAALgAECgEJAQAAAA==.Sheroko:BAAALgAECgEJAQAAAA==.Shinanìgans:BAAALgADCgkJCQAAAA==.Shmoopy:BAAALgAECgYJBgAAAA==.Shortyman:BAAALgAECgUJBQABLgAECgkJIAAUACofAA==.Shruikan:BAABLgAECn8UAAQNAAcJTBk7HADlAQANAAcJ1xg7HADlAQAOAAcJ7g8JGQBvAQAaAAMJlgWlPACFAAAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgYJCwAFAAAAAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAABLgAECn8bAAMUAAcJAh2yOwBMAQAUAAYJfx2yOwBMAQAVAAEJjhohQABNAAAAAA==.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAgAAAA==.Sisturfistur:BAAALgAECgQJBQAAAA==.',
Sk='Skunkpaw:BAAALgADCgYJCwAAAA==.Skysong:BAACLgAFFH8TAAMOAAUJ0RRTAQCmAQAOAAUJjw9TAQCmAQANAAMJtQ/lEgDoAAAuAAQKfxkABA4ACAnJHcgMAA4CAA4ABwlhG8gMAA4CABoABQl+EdkqABsBAA0AAwnVF0JCANoAAAAA.',
Sl='Slashedeye:BAABLgAECn8iAAIfAAgJ6BNGAgA3AgAfAAgJ6BNGAgA3AgAAAA==.',
Sm='Smellsoftree:BAAALgADCgYJDAAAAA==.',
Sn='Snowynn:BAABLgAECn8VAAMoAAgJdglFDQDjAAAoAAgJdglFDQDjAAAhAAEJWwHp6gAZAAAAAA==.Snubby:BAABLgAECn8hAAMSAAkJDyRzDAD7AQATAAcJIiVIJACCAgASAAUJriJzDAD7AQAAAA==.',
So='Soleil:BAAALgAECggJDwAAAA==.Solheim:BAACLgAFFH8KAAMYAAQJyhYRBABiAQAYAAQJcxQRBABiAQAGAAIJHB30DQCXAAAuAAQKfyQAAwYACAkXI78KAPcCAAYACAkoIr8KAPcCABgABAlFHfkWAAkBAAAA.Souffle:BAABLgAECn8cAAMTAAcJYBfWLAB5AQATAAcJYBfWLAB5AQASAAEJAABqbQA6AAAAAA==.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMZAAgJ/A8aMgCJAQAZAAgJ/A8aMgCJAQAQAAEJ/we2SQAzAAAAAA==.Spookypink:BAABLgAECn8YAAIgAAkJjyJGEAANAwAgAAkJjyJGEAANAwAAAA==.',
Sq='Squirtz:BAAALgAECgUJBQAAAA==.',
Sr='Srirachajane:BAAALgADCgQJBAABLgAECggJGQApADAbAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Strathin:BAAALgADCgQJBAAAAA==.Strathz:BAABLgAECn8iAAMSAAgJByCcCgAVAgASAAYJOR+cCgAVAgATAAYJgh0EKACOAQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIeAAgJ1hq4GABNAgAeAAgJ1hq4GABNAgAAAA==.Summerset:BAAALgAECgYJEAAAAA==.Sushi:BAAALgAECgIJAwAAAA==.',
Sy='Sylatis:BAACLgAFFH8dAAMYAAgJpBgdAAApAgAYAAcJ+hgdAAApAgAGAAYJiRTCAwAIAgAuAAQKfxYAAwYACAk0JTkNANoCAAYACAk0JTkNANoCABgAAwmiHvAlAGcAAAAA.Sylvanâs:BAAALgAECgUJBQAAAA==.Sylvara:BAAALgAECgMJBgAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.',
['Sö']='Söultender:BAABLgAECn8ZAAQiAAgJZgsCDgCqAQAiAAgJQgsCDgCqAQAKAAEJvAlKYwAyAAAJAAEJbAy5ggAvAAAAAA==.',
Ta='Taichi:BAACLgAFFH8FAAIPAAIJzAz6FgCBAAAPAAIJzAz6FgCBAAAuAAQKfyEAAg8ACAkBHkgMAI4CAA8ACAkBHkgMAI4CAAAA.Talys:BAACLgAFFH8UAAIaAAYJfxebAgDoAQAaAAYJfxebAgDoAQAuAAQKfyEAAhoACQmUGIUIALICABoACQmUGIUIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgADCgUJBQAAAA==.Tarth:BAACLgAFFH8VAAIoAAUJrCSCAAD0AQAoAAUJrCSCAAD0AQAuAAQKfxcAAigACAkEJmwBAEEDACgACAkEJmwBAEEDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8YAAIaAAcJjhpCBgDnAQAaAAcJjhpCBgDnAQAAAA==.Taïko:BAAALgADCgQJBAAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgYJDQABLgAECgcJGQAUAIAeAA==.Tenniell:BAAALgAECgQJDAAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAABLgAECn8YAAIDAAgJAg+OLQCtAQADAAgJAg+OLQCtAQAAAA==.',
Th='Thab:BAAALgAECgUJBgABLgAECgYJFwANAJ4VAA==.Thabk:BAABLgAECn8XAAMNAAYJnhUXJwCEAQANAAYJnhUXJwCEAQAOAAEJaAc9QwAoAAAAAA==.Thaelorn:BAAALgAECgMJAwAAAA==.Tharit:BAAALgADCgYJCgAAAA==.Theshortbuss:BAAALgAECgUJCQAAAA==.Thesuffering:BAAALgAECgQJBgAAAA==.Thesyra:BAAALgADCgcJDAAAAA==.Thingtwò:BAAALgADCgUJBQAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDgAAAA==.',
Ti='Tiddybear:BAAALgAECgEJAQAAAA==.Timerunhunt:BAAALgADCgUJBgAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAAALgAECgYJDQAAAA==.Tokken:BAACLgAFFH8NAAIBAAQJTBHeCABOAQABAAQJTBHeCABOAQAuAAQKfyEAAgEACQnpHEMMAPcCAAEACQnpHEMMAPcCAAAA.',
Tr='Treebeast:BAACLgAFFH8GAAIMAAMJDBMQFwCbAAAMAAMJDBMQFwCbAAAuAAQKfxUAAgwABwlnH4UcAC0CAAwABwlnH4UcAC0CAAAA.Trojen:BAAALgADCgcJBwAAAA==.',
Tu='Tubularoso:BAAALgAECgYJDwAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Tw='Twobtn:BAAALgAECgUJBQAAAA==.',
Ty='Tyras:BAAALgADCgYJBgAAAA==.',
Ul='Ulanda:BAAALgAECgQJCQAAAA==.',
Um='Umako:BAACLgAFFH8KAAMnAAUJ8hyUAQBvAQAnAAQJTB6UAQBvAQAXAAIJAxwiEwCzAAAuAAQKfyEAAycACQmuIfEAAEQDACcACQmUIfEAAEQDABcACAlGFyEdABYCAAAA.',
Un='Underbogg:BAAALgADCgUJBQAAAA==.Unus:BAAALgADCgQJBAABLgAECggJHwADAHEcAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Ux='Ux:BAAALgADCgkJCQAAAA==.',
Va='Vaedric:BAAALgADCgYJCwAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgcJEQAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAABLgAECn8cAAIBAAgJTxi5JwAfAgABAAgJTxi5JwAfAgAAAA==.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8ZAAIBAAgJzCWAFwCQAgABAAgJzCWAFwCQAgAAAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8cAAIEAAgJmA0QJgBRAQAEAAgJmA0QJgBRAQAAAA==.Voids:BAAALgADCgcJDAAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAAALgAECgYJBwABLgAFFAMJBwAGAKMJAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgAFAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMWAAgJwBqGIwAKAgAWAAgJwBqGIwAKAgAMAAQJ6QV8OQCIAAAAAA==.',
Wa='Walkerwhite:BAAALgAECggJDgAAAA==.Warjd:BAAALgAECgUJDQAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Weebo:BAAALgADCgQJBQAAAA==.Wesjin:BAABLgAECn8aAAIPAAkJbxqyDgBrAgAPAAkJbxqyDgBrAgAAAA==.',
Wh='Whiskee:BAACLgAFFH8HAAIpAAMJPxfhAgAWAQApAAMJPxfhAgAWAQAuAAQKfyEABCkACAmQIbQEAM0CACkACAl1IbQEAM0CABsAAQmfEy5CAD8AACEAAQklAzPXACoAAAAA.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Wintulyn:BAAALgADCgIJAgAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgADCggJFQAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wy='Wyndia:BAAALgAECgUJCgAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJBgABLgAECggJGQAiAGYLAA==.',
Xb='Xbert:BAAALgADCgcJBwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8SAAIDAAUJSx0ZDgCqAQADAAUJSx0ZDgCqAQAuAAQKfxYAAgMACAn+IYsuALgCAAMACAn+IYsuALgCAAAA.',
Xi='Xihuang:BAAALgADCgMJAwABLgAECggJIgADAK4ZAA==.Xiia:BAABLgAECn8aAAIGAAgJcxpEAwD6AQAGAAgJcxpEAwD6AQAAAA==.',
Xx='Xxoouu:BAAALgAECgcJBgABLgAECgkJCQAFAAAAAA==.Xxuublue:BAAALgAFFAYJAQAAAA==.Xxuuvoker:BAAALgAECgkJCQAAAA==.',
Ya='Yaoguai:BAABLgAECn8VAAMbAAgJohDfMgB1AQAbAAgJohDfMgB1AQAhAAEJwAO84wAhAAAAAA==.Yasei:BAAALgAECgEJAQAAAA==.Yawgmoth:BAABLgAECn8WAAMdAAkJVRb9BAAiAgAdAAkJVRb9BAAiAgATAAEJHQzfrwA3AAAAAA==.',
Yd='Ydalflow:BAAALgADCgQJBAAAAA==.',
Za='Zammboomafoo:BAAALgAECgYJEAAAAA==.Zanian:BAABLgAECn8UAAMhAAYJvhbpIQByAQAhAAYJvhbpIQByAQApAAIJjAOIGQBWAAAAAA==.Zarthie:BAAALgADCgYJBgABLgAECgYJFAANALAVAA==.Zarthy:BAABLgAECn8UAAINAAYJsBW1JACXAQANAAYJsBW1JACXAQAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgYJCgAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zo='Zodd:BAAALgADCgEJAgAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgMJBgABLgAECggJIQADAN0iAA==.Zuo:BAAALgAECgMJAwAAAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAIpAAgJMBv2BQCjAgApAAgJMBv2BQCjAgAAAA==.',
['Zà']='Zàánn:BAAALgAECgYJEgAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAFFAMJBgAfACIbAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAFFAMJBgAfACIbAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgAECgEJAQAAAA==.',
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

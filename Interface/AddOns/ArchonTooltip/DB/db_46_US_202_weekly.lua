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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Fury','Warrior-Arms','Mage-Frost','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Mage-Arcane','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Paladin-Retribution','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Monk-Brewmaster','Evoker-Preservation','Druid-Balance','Paladin-Protection','Warlock-Affliction','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Priest-Discipline','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Druid-Feral','Rogue-Assassination','Druid-Guardian',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJDAABLgAECgcJBwABAAAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Admaris:BAABLgAECn8UAAICAAYJFB1jOwC3AQACAAYJFB1jOwC3AQAAAA==.',
Ag='Age:BAABLgAECn8gAAMDAAkJpxniCwAsAgADAAkJpxniCwAsAgAEAAMJoA0PJwC2AAAAAA==.Agni:BAACLgAFFH8VAAIFAAUJASOVDwCbAQAFAAUJASOVDwCbAQAuAAQKfyUAAgUACQnnI6gEALYDAAUACQnnI6gEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8fAAIDAAgJ3RSLFADHAQADAAgJ3RSLFADHAQAAAA==.',
Al='Alavendis:BAABLgAECn8VAAIGAAcJRRzwHwDJAQAGAAcJRRzwHwDJAQABLgAECgQJBgABAAAAAA==.Alexá:BAAALgAECgUJCQABLgAECgcJGwAHANIeAA==.Almight:BAAALgAECgIJAgAAAA==.Alnasham:BAACLgAFFH8SAAIIAAUJQh2mAADMAQAIAAUJQh2mAADMAQAuAAQKfxwAAggACAl5H50GAIwCAAgACAl5H50GAIwCAAAA.Alphashadow:BAAALgAECgQJBAAAAA==.Alvoka:BAABLgAECn8cAAMFAAkJyhORagAAAgAFAAkJyhORagAAAgAJAAQJpQ8nBgD8AAAAAA==.',
Am='Amarillos:BAAALgAECgYJBgAAAA==.Amarillys:BAACLgAFFH8FAAIKAAIJQh1yCwCsAAAKAAIJQh1yCwCsAAAuAAQKfyMAAwoACQlDHRcOAHoCAAoACQlDHRcOAHoCAAsAAQnYFJFjADEAAAAA.Ambrotos:BAAALgAECgYJDgAAAA==.Amither:BAAALgAECgYJBgAAAA==.Ammutseba:BAABLgAECn8pAAMMAAkJFhrXAwAEAgAMAAkJFhrXAwAEAgAGAAEJXQoRwgArAAAAAA==.Amperage:BAAALgAECgEJAQAAAA==.',
An='Anfall:BAAALgAECgcJCgAAAA==.Angermeier:BAABLgAECn8dAAIDAAgJXBkwEAD0AQADAAgJXBkwEAD0AQAAAA==.Angryjeid:BAAALgAECgYJBgABLgAFFAMJBgANAA8KAA==.Angrylady:BAAALgAECgEJAQAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAgAAAA==.Arg:BAAALgAECgYJBwAAAA==.Arowin:BAAALgAECggJEwAAAA==.Arthaniis:BAACLgAFFH8FAAIOAAMJYQ/SGQDgAAAOAAMJYQ/SGQDgAAAuAAQKfxwAAg4ACAnMIP4IAAIDAA4ACAnMIP4IAAIDAAAA.',
As='Asdar:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgQJCAAAAA==.',
Au='Audideath:BAAALgAECgYJCwAAAA==.Audry:BAAALgADCgcJCQAAAA==.Augtistic:BAABLgAECn8bAAMPAAkJShL8GwBeAQAPAAkJShL8GwBeAQAQAAYJcwIAKwDFAAABLgAECgkJJQARABUfAA==.Aulrelle:BAABLgAECn8UAAMSAAcJxRO7GACLAQASAAcJxRO7GACLAQATAAQJDAa4PACKAAABLgAECgQJDgABAAAAAA==.Auurdeath:BAAALgAECgYJCgAAAA==.',
Av='Avidswolf:BAABLgAECn8eAAIFAAcJdA/QZQBGAQAFAAcJdA/QZQBGAQAAAA==.Avãcyn:BAABLgAECn8cAAMEAAcJhwbKIAC3AAADAAYJSwZFNgDuAAAEAAYJGgXKIAC3AAAAAA==.',
Aw='Aw:BAACLgAFFH8OAAIUAAcJVyIRAACJAgAUAAcJVyIRAACJAgAuAAQKfxgAAhQACAmeJowBAJEDABQACAmeJowBAJEDAAAA.Awppenheimer:BAABLgAECn8hAAMVAAkJ6x18FAA9AgAVAAgJFRx8FAA9AgAWAAYJdRyOEADKAQAAAA==.',
Ax='Ax:BAEBLgAFFH8QAAMRAAUJlxHWNAA0AQARAAQJlxHWNAA0AQAXAAEJAADAMQAAAAAAAA==.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAAALgAFFAMJAwAAAA==.',
Ba='Babycarrots:BAAALgAECgcJCAAAAA==.Baconz:BAABLgAECn8cAAMOAAkJPxRuJADtAQAOAAkJPxRuJADtAQAYAAEJ/QJ7iQAkAAAAAA==.Bakeon:BAABLgAECn8cAAMYAAgJ1hV0GQDmAQAYAAgJ1hV0GQDmAQAOAAMJYAQbdABxAAAAAA==.Bakkaz:BAAALgADCgYJBgAAAA==.Baldozhi:BAAALgAECgYJCwAAAA==.Bangbang:BAAALgAFFAEJAQAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAAALgAECgQJDgAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECgcJFgAZAIgMAA==.Beardcheese:BAAALgAECgIJAQAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAABLgAECn8ZAAMTAAgJhxUeHQDxAQATAAYJOh0eHQDxAQAaAAgJsQqpHABOAQAAAA==.',
Bi='Bink:BAABLgAECn8ZAAIHAAkJ9xpEBADXAgAHAAkJ9xpEBADXAgAAAA==.Birblock:BAABLgAFFH8LAAMVAAUJDxd4HgA8AQAVAAUJBxd4HgA8AQAWAAEJWQvIEwBPAAABLgAFFAgJHgAHAKYYAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAABLgAECn8YAAIGAAYJRAg/YwDYAAAGAAYJRAg/YwDYAAAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAABLgAECn8YAAMSAAgJEgebJwAOAQASAAgJEgebJwAOAQAaAAEJJxsBfwBMAAAAAA==.Blãckheart:BAAALgAECgEJAQAAAA==.',
Bo='Bobbo:BAAALgAECgQJBAAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Bolterguy:BAAALgADCgkJCQAAAA==.Boomin:BAAALgAECggJDgAAAA==.',
Br='Braass:BAAALgAECgEJAQABLgAECgQJDgABAAAAAA==.Breachnclear:BAAALgAECgUJBQAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8mAAIaAAkJdRqwCAA+AgAaAAkJdRqwCAA+AgAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgAECgQJBAABLgAECgYJDwABAAAAAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8fAAIYAAkJmSCSAgA0AwAYAAkJmSCSAgA0AwAAAA==.Brutechaos:BAAALgADCgQJBAABLgAECgkJHwAYAJkgAA==.Bruteflappy:BAAALgADCgkJCQABLgAECgkJHwAYAJkgAA==.',
Bu='Buffygirl:BAABLgAECn8bAAMPAAgJ8BWsDwDZAQAPAAgJ8BWsDwDZAQAbAAUJcg1/HgB7AAAAAA==.Bustle:BAAALgADCgkJCQAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECgkJEgAAAA==.',
['Bå']='Båne:BAABLgAECn8cAAIGAAcJCQ5FSQAdAQAGAAcJCQ5FSQAdAQAAAA==.',
Ca='Carnal:BAAALgADCgUJCAAAAA==.Casini:BAAALgADCgMJAwAAAA==.Caydened:BAAALgADCgQJBAAAAA==.Cazic:BAAALgAECgYJCQAAAA==.',
Ce='Cedren:BAACLgAFFH8IAAIGAAMJlhnTMADtAAAGAAMJlhnTMADtAAAuAAQKfxkAAgYACQnbHe0dAJ4CAAYACQnbHe0dAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIGAAcJsyKlIQCHAgAGAAcJsyKlIQCHAgAAAA==.Certified:BAAALgAECgYJBwAAAA==.',
Ch='Chalix:BAAALgAECgEJAQAAAA==.Cheapheal:BAABLgAECn82AAMcAAkJOiQnAQBBAwAcAAkJOiQnAQBBAwACAAYJVhlYHwDJAQAAAA==.Cheburashka:BAACLgAFFH8TAAIOAAYJ5iBpAwDRAQAOAAYJ5iBpAwDRAQAuAAQKfxcAAg4ACAnNIg0PALYCAA4ACAnNIg0PALYCAAAA.Chewymentos:BAAALgAECgUJCgABLgAECggJIgAdAL4KAA==.Chimerabob:BAAALgAECgYJDAAAAA==.Chunkyhunter:BAAALgAECgYJBgABLgAFFAUJEQATAMIcAA==.Chunkymonkey:BAACLgAFFH8RAAMTAAUJwhwwBQBrAQATAAUJwhwwBQBrAQAaAAIJGA61HACKAAAuAAQKfxsAAxMACAlKISkLAMcCABMACAlKISkLAMcCABoABQlxGuw9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cj='Cjpriestly:BAAALgADCgcJBwAAAA==.',
Cl='Clappncheeks:BAABLgAECn8fAAIHAAcJPB+sCAAcAgAHAAcJPB+sCAAcAgAAAA==.Claudefrollo:BAABLgAECn8aAAIcAAYJRBA6JwAGAQAcAAYJRBA6JwAGAQAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corlem:BAAALgAECgUJBgAAAA==.Corrüpt:BAAALgAECgcJCwAAAA==.',
Cr='Crimsa:BAABLgAECn8jAAIeAAgJTAdBBgBVAQAeAAgJTAdBBgBVAQAAAA==.Crimsongost:BAAALgAECgEJAQAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Cryogen:BAABLgAECn8ZAAIcAAgJJiCQCwARAgAcAAgJJiCQCwARAgAAAA==.',
Cs='Cs:BAABLgAECn8pAAIaAAkJzCIgAgD3AgAaAAkJzCIgAgD3AgAAAA==.',
Cu='Curufin:BAAALgAECgUJCwAAAA==.',
Da='Daddysmooth:BAAALgAECgYJCAAAAA==.Daemon:BAABLgAECn8aAAIRAAcJryBbKADcAQARAAcJryBbKADcAQAAAA==.Daemonproph:BAABLgAECn8ZAAIUAAcJyhPeDwCFAQAUAAcJyhPeDwCFAQAAAA==.Dakini:BAABLgAECn8ZAAIfAAcJWiSSBwCeAgAfAAcJWiSSBwCeAgAAAA==.Daktaklakpak:BAABLgAFFH8HAAQgAAMJOBmpMwC1AAAgAAIJDxqpMwC1AAAHAAIJSw9wFQCpAAAhAAEJihf7GgBPAAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8mAAIdAAkJ1B9VBADDAgAdAAkJ1B9VBADDAgAAAA==.Dangerruss:BAABLgAECn8ZAAIdAAcJQhIeFwBjAQAdAAcJQhIeFwBjAQAAAA==.Darkhaven:BAAALgADCgIJAgAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAACLgAFFH8KAAIiAAQJhxxBAAB+AQAiAAQJhxxBAAB+AQAuAAQKfx4AAyIACAn1HR8BAMACACIACAn1HR8BAMACAAUABAkrCFcZAcwAAAAA.Dasmonkey:BAAALgAECgIJAgAAAA==.Daxos:BAABLgAECn8mAAIFAAkJ9BipHgAyAgAFAAkJ9BipHgAyAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJEQAAAA==.Deelahn:BAABLgAECn8YAAMKAAgJzQjmIABBAQAKAAgJzQjmIABBAQALAAEJXADgXAAZAAAAAA==.Demideudle:BAAALgAECgEJAQAAAA==.Demonicchoas:BAABLgAECn81AAMWAAkJhyAaAQAmAwAWAAgJJyIaAQAmAwAVAAcJQhtREwBHAgAAAA==.Denagorn:BAABLgAECn82AAINAAkJehwUGADYAgANAAkJehwUGADYAgABLgAFFAYJGQARAAUYAA==.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAABLgAECn8UAAICAAgJwh+5BwDRAgACAAgJwh+5BwDRAgAAAA==.Deutzfr:BAAALgAFFAEJAQAAAA==.',
Do='Dominant:BAABLgAECn8iAAIFAAkJTB31DQCuAgAFAAkJTB31DQCuAgAAAA==.Dooma:BAABLgAFFH8LAAMVAAcJ3xT6DQCHAQAVAAYJYxX6DQCHAQAeAAIJSxO1AgC9AAAAAA==.Dorgie:BAAALgAECgUJDwABLgAFFAIJBAABAAAAAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIFAAgJSiHaIQDsAgAFAAgJSiHaIQDsAgAAAA==.',
Dr='Draco:BAAALgADCgEJAQAAAA==.Drag:BAAALgAECgQJBgAAAA==.Dragon:BAABLgAECn8YAAIbAAkJFhBZFgDoAQAbAAkJFhBZFgDoAQAAAA==.Drbob:BAAALgAECgQJBQAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAAALgAFFAMJBAABLgAFFAYJEwAfAM0jAA==.Drock:BAABLgAECn8aAAIGAAgJjx10DwBLAgAGAAgJjx10DwBLAgAAAA==.Druidgale:BAABLgAECn8jAAICAAkJowtCNgA+AQACAAkJowtCNgA+AQAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAABLgAECn8YAAIaAAgJuhWqDgDdAQAaAAgJuhWqDgDdAQAAAA==.Drybonez:BAABLgAECn8ZAAMOAAcJ5BNuJAAzAQAOAAYJFxduJAAzAQAYAAQJdwa+WgCTAAAAAA==.Drygth:BAABLgAECn8YAAQLAAkJlyCeDgCZAgALAAcJMCKeDgCZAgAKAAcJ5BogDAAkAgAjAAEJbwm7VAA4AAAAAA==.',
Du='Dubshox:BAABLgAECn8gAAIOAAgJOhyKDAATAgAOAAgJOhyKDAATAgAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ea='Earthly:BAAALgAECgEJAQAAAA==.',
Ei='Eisador:BAABLgAECn8fAAIgAAgJnA6bMQCHAQAgAAgJnA6bMQCHAQAAAA==.',
El='Elemotional:BAABLgAECn8UAAIIAAgJnB2cAwBFAgAIAAgJnB2cAwBFAgAAAA==.',
Eq='Equilibrio:BAABLgAECn8bAAIkAAgJjh71BQA6AgAkAAgJjh71BQA6AgAAAA==.',
Er='Erilee:BAAALgAECgMJAwAAAA==.',
Et='Ettle:BAAALgAECgEJAQABLgAECgUJBgABAAAAAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAABLgAECn8bAAQHAAcJ0h6VCQALAgAHAAcJwRyVCQALAgAhAAYJNxnBCwAxAQAgAAEJjxoUpwBIAAAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECggJGwAPAKYWAA==.',
Fa='Faelthas:BAACLgAFFH8XAAIaAAUJ5iTHAQDvAQAaAAUJ5iTHAQDvAQAuAAQKfzEAAhoACAksJtkCAGkDABoACAksJtkCAGkDAAAA.Fathercoast:BAABLgAECn8mAAMLAAkJQhx5BwBWAgALAAkJQhx5BwBWAgAjAAYJWBbxHwCUAQAAAA==.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAABLgAECn8UAAIGAAgJ7R+PCQCOAgAGAAgJ7R+PCQCOAgAAAA==.Felstrider:BAAALgAECgUJCAAAAA==.Fembouyant:BAABLgAECn8XAAIlAAkJtBSHBAAVAgAlAAkJtBSHBAAVAgAAAA==.Ferador:BAACLgAFFH8XAAMhAAYJZhPDCwAAAQAgAAMJAh6SIAATAQAhAAUJZwXDCwAAAQAuAAQKfxkAAyEACAlgHfoiAA4CACEACAnFFfoiAA4CACAABAmZGbNrACUBAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.Fistsphoyou:BAAALgADCgUJBwAAAA==.',
Fl='Flowmo:BAAALgAECgYJBwABLgAECggJFwAaANobAA==.',
Fo='Forsakken:BAAALgAECgUJBQAAAA==.Fortou:BAAALgADCgMJAgAAAA==.Fourbees:BAAALgAECgYJDQAAAA==.',
Fr='Frizly:BAABLgAECn8dAAMKAAgJ2QbYJAAjAQAKAAgJ2QbYJAAjAQALAAEJ5ABNXQATAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIFAAkJ/hGQXQAhAgAFAAkJ/hGQXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.',
Ga='Galdrell:BAAALgAECgcJDwAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgADCgIJAgAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8gAAMRAAkJKh9IEwAIAwARAAkJKh9IEwAIAwAlAAEJDgcTGQArAAAAAA==.',
Gn='Gnnome:BAABLgAECn8ZAAIFAAgJDAoSWABlAQAFAAgJDAoSWABlAQAAAA==.',
Go='Gog:BAAALgAECggJDwAAAA==.Goodolruss:BAAALgADCgUJBQAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIXAAkJ3yVfAADPAwAXAAkJ3yVfAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8nAAIRAAkJHRwKFQBTAgARAAkJHRwKFQBTAgAAAA==.Grimaldus:BAABLgAECn8ZAAIdAAkJah97BAC9AgAdAAkJah97BAC9AgAAAA==.Grimmortal:BAAALgAECggJCAAAAA==.Grimreaper:BAABLgAECn8qAAMmAAkJuR9+AADwAgAmAAkJuR9+AADwAgAZAAIJeRAuUwCRAAAAAA==.Groag:BAAALgAECgYJDQAAAA==.Groovytony:BAAALgAECgYJBgAAAA==.Gruffles:BAABLgAECn8cAAICAAcJWSDhEwAqAgACAAcJWSDhEwAqAgAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8bAAIGAAgJ/h0jIwC2AQAGAAgJ/h0jIwC2AQAAAA==.',
Ha='Haarp:BAAALgAECgQJBQAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handicat:BAAALgADCgEJAQABLgAECggJGQALAJISAA==.Handimage:BAAALgADCgEJAQABLgAECggJGQALAJISAA==.Handipriest:BAABLgAECn8ZAAILAAgJkhIoEQDCAQALAAgJkhIoEQDCAQAAAA==.Haqq:BAABLgAECn8aAAIDAAgJMwu6HACDAQADAAgJMwu6HACDAQAAAA==.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgADCgcJEgABLgAECggJDAABAAAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8pAAIRAAgJuA9iNwCcAQARAAgJuA9iNwCcAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgAECgUJBQAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8gAAIRAAkJcSB6BgD0AgARAAkJcSB6BgD0AgAAAA==.',
Ho='Hoafustis:BAAALgAECgEJAQAAAA==.Hobo:BAAALgAECgYJEgAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBQAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Hundard:BAAALgAECgIJAgAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAAALgAFFAEJAgAAAA==.Iblisshaytan:BAABLgAECn8XAAMUAAcJOBXsEQBqAQAUAAcJOBXsEQBqAQAGAAUJJAt5hQCJAAABLgAECggJIgAFAK8ZAA==.Ibtrollin:BAAALgAECgEJAQAAAA==.',
Ic='Icepak:BAAALgADCgUJBQAAAA==.',
Ig='Ignacious:BAABLgAECn8tAAQYAAkJCiTjAgBQAwAYAAkJCiTjAgBQAwAOAAYJKh1LGQCEAQAIAAEJVg8TLAA1AAAAAA==.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAABLgAECn8aAAInAAcJ1hNsCQCQAQAnAAcJ1hNsCQCQAQAAAA==.Immolate:BAABLgAECn8aAAQVAAkJzyEANgA0AgAVAAcJbx8ANgA0AgAWAAUJsCKRFgCVAQAeAAEJAAAxJABhAAAAAA==.',
In='Infamous:BAAALgAECgYJCgAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJEQAAAA==.',
Io='Ionissa:BAAALgAECgcJBwAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAgAAAA==.',
Is='Ischia:BAACLgAFFH8RAAIKAAUJQw9FAgCNAQAKAAUJQw9FAgCNAQAuAAQKfxgAAwoACAkdEjMgAOABAAoACAkdEjMgAOABAAsAAQm/AaZqACEAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIZAAIJpx+hEADFAAAZAAIJpx+hEADFAAAuAAQKfxgAAhkABwliI8AXAEsCABkABwliI8AXAEsCAAAA.Jallypally:BAAALgADCggJCQAAAA==.Janokdiso:BAAALgAECgEJAQAAAA==.Javeighqueas:BAAALgADCgQJAgABLgAFFAIJBAABAAAAAA==.',
Jc='Jch:BAACLgAFFH8XAAMgAAcJFhp+AADCAQAgAAYJihl+AADCAQAhAAEJ1hzOFgBdAAAuAAQKfyIAAyAACQlkJP0BAH8DACAACQlkJP0BAH8DACEAAQmiB0qPACwAAAAA.',
Je='Jedijed:BAAALgAECgYJBgABLgAFFAMJBgANAA8KAA==.Jedikepjr:BAABLgAFFH8GAAINAAMJDwpxOADMAAANAAMJDwpxOADMAAAAAA==.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECgcJCAAAAA==.Joneztown:BAABLgAECn8WAAITAAkJQRqzCwC/AgATAAkJQRqzCwC/AgAAAA==.Jordantheorc:BAABLgAECn8nAAMgAAkJhBxvDgBlAgAgAAkJhBxvDgBlAgAhAAIJvwLogQBAAAAAAA==.',
Jp='Jprottsoo:BAABLgAECn8dAAIcAAkJhx41BAC4AgAcAAkJhx41BAC4AgAAAA==.',
Jt='Jtee:BAABLgAECn8sAAMfAAgJehUCFQDoAQAfAAgJehUCFQDoAQANAAEJbApTBgE1AAAAAA==.',
Ju='Jukkrit:BAAALgADCgEJAQAAAA==.',
Jy='Jy:BAAALgADCgMJAwAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8jAAICAAgJuQtLPAAjAQACAAgJuQtLPAAjAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECgkJFgAeAFYWAA==.Karoo:BAAALgADCgYJBgAAAA==.Kataris:BAAALgAECgEJAQAAAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAgAAAA==.Keizzer:BAABLgAECn8kAAINAAkJlh8MHgC3AgANAAkJlh8MHgC3AgAAAA==.Kelesa:BAAALgADCgEJAQAAAA==.Keshisaru:BAAALgAECggJDgAAAA==.',
Kh='Kharms:BAABLgAECn8eAAITAAkJ+RwvBQCMAgATAAkJ+RwvBQCMAgAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.',
Kl='Klunder:BAABLgAECn8fAAIYAAkJlx4/BAD/AgAYAAkJlx4/BAD/AgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIaAAgJ2hvTFABmAgAaAAgJ2hvTFABmAgAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAABLgAECn8bAAIgAAkJlBsWDQB0AgAgAAkJlBsWDQB0AgAAAA==.Kostik:BAAALgAECgQJBAAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAABLgAECn8hAAIGAAkJ2hNXFwABAgAGAAkJ2hNXFwABAgAAAA==.Krux:BAAALgAECgIJBAAAAA==.',
Ky='Kybinc:BAAALgADCgQJBAAAAA==.',
La='Lacie:BAAALgADCgkJDAAAAA==.Laennaya:BAABLgAECn8tAAIeAAgJngsxBQB8AQAeAAgJngsxBQB8AQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAAALgAECgUJEwAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgIJBQAAAA==.Lazyfrost:BAABLgAECn8eAAIFAAkJGRoTQAB5AgAFAAkJGRoTQAB5AgAAAA==.Lazyunholy:BAAALgADCgkJCAAAAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8dAAMfAAcJox+VEwB2AgAfAAcJox+VEwB2AgANAAEJZA4TPwE1AAAAAA==.Lethô:BAABLgAECn8qAAICAAkJxyGZAQCHAwACAAkJxyGZAQCHAwAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Lickemlow:BAAALgAECgEJAQAAAA==.Liesx:BAAALgADCgQJBAAAAA==.Lilboothang:BAABLgAECn8ZAAIVAAgJZxPtJQDRAQAVAAgJZxPtJQDRAQAAAA==.Lillìth:BAAALgAECgEJAQAAAA==.Lilzarthe:BAAALgAECgMJAwABLgAECgcJFgAPAMcTAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Loachella:BAAALgADCgUJBQAAAA==.Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAACLgAFFH8GAAIGAAMJ6iQBIADXAAAGAAMJ6iQBIADXAAAuAAQKfycAAgYACQmdJBgCALcDAAYACQmdJBgCALcDAAAA.Loko:BAACLgAFFH8VAAIcAAYJGRzYAgDPAQAcAAYJGRzYAgDPAQAuAAQKfy0AAhwACQnYI2sBAC8DABwACQnYI2sBAC8DAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAECgcJCQAAAA==.Louiie:BAABLgAECn8WAAIZAAcJiAy2FQBdAQAZAAcJiAy2FQBdAQAAAA==.',
Lu='Luckygrapes:BAABLgAECn8ZAAISAAcJtR/KDgBpAgASAAcJtR/KDgBpAgAAAA==.Lukdanuke:BAAALgAECgYJCgAAAA==.Lumi:BAAALgAECgEJAQAAAA==.Luxxus:BAAALgAECgcJCwABLgAECgkJJAANAJYfAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAABLgAECn8ZAAIOAAcJHQ+xJQArAQAOAAcJHQ+xJQArAQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8YAAIVAAgJnQ9sSQBMAQAVAAgJnQ9sSQBMAQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAITAAcJnh0GFABPAgATAAcJnh0GFABPAgAAAA==.Mantakore:BAACLgAFFH8PAAIbAAQJ7AiZEAANAQAbAAQJ7AiZEAANAQAuAAQKfzAAAhsACAmOGYUHAPsBABsACAmOGYUHAPsBAAAA.Marcdruid:BAAALgAECgQJBAAAAA==.Maubles:BAAALgAECgYJBgABLgAFFAQJDAAdAFMNAA==.',
Me='Meadöw:BAAALgAECgYJBwAAAA==.Meiling:BAAALgAECgUJBQAAAA==.Meladra:BAAALgADCgcJBwAAAA==.Menopaws:BAAALgAECgkJEQAAAA==.Mertrik:BAABLgAECn8dAAMOAAkJghu5EAChAgAOAAkJghu5EAChAgAIAAEJuBiAKQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8lAAIXAAkJlx9qCAAAAgAXAAkJlx9qCAAAAgAAAA==.Mikailla:BAAALgAFFAIJAwABLgAECgEJAQABAAAAAA==.Mikayy:BAACLgAFFH8SAAIZAAUJAiUfBACzAQAZAAUJAiUfBACzAQAuAAQKfykAAxkACQk+JKEDAJ4CABkACQn7I6EDAJ4CACgAAQlYJdITAGoAAAAA.Milenko:BAABLgAECn8jAAIUAAgJpSOxAgDGAgAUAAgJpSOxAgDGAgAAAA==.Milly:BAAALgAECgEJAwABLgAECggJIwAUAKUjAA==.Mimid:BAAALgAECgYJDgAAAA==.Mimonk:BAAALgAECgQJBAAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minii:BAAALgAECgQJBAAAAA==.Minteafresh:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8SAAMDAAYJoxBRBQCdAQADAAUJWxNRBQCdAQAEAAIJrQk7EwCNAAAuAAQKfyEAAwMACAnuHfIRAMACAAMACAnuHfIRAMACAAQABAk3Gc0YADEBAAAA.Moort:BAAALgAECgYJDwAAAA==.Moothafacka:BAAALgADCgcJBwAAAA==.Mordecaii:BAAALgAECgIJAQAAAA==.Morganlefay:BAAALgADCgcJEgAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAAALgAECgcJEQAAAA==.Moyana:BAAALgAECgQJBQAAAA==.',
Ms='Msbehaven:BAABLgAECn8ZAAIVAAcJOAVnbwDsAAAVAAcJOAVnbwDsAAAAAA==.',
Mt='Mthafknfreez:BAABLgAECn8iAAIFAAgJrxmEKQD8AQAFAAgJrxmEKQD8AQAAAA==.',
My='Mynuturchin:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîg:BAABLgAECn8cAAIGAAcJOBHkRQAnAQAGAAcJOBHkRQAnAQAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJBAABLgAECgQJDgABAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgYJBgABLgAECgkJIAARACofAA==.',
Ne='Neytiri:BAAALgADCggJCAAAAA==.',
Ni='Nilfalath:BAAALgAECgQJBAAAAA==.Nippy:BAAALgAECgUJCgABLgAECgYJBgABAAAAAA==.',
No='Noriva:BAAALgAECgEJAQAAAA==.Notthechosen:BAAALgAECgEJAQABLgAFFAQJBwADAM0GAA==.',
Ny='Nymeriã:BAAALgAECgQJCwAAAA==.Nymeriå:BAAALgADCggJCQAAAA==.',
Ob='Obzy:BAAALgADCgYJBgABLgAFFAIJBAABAAAAAA==.Obzz:BAAALgAFFAIJBAAAAA==.',
Od='Odiedude:BAAALgADCgUJBQAAAA==.Odieous:BAAALgAECgcJCgAAAA==.',
Ok='Okamy:BAABLgAECn8aAAIRAAgJUiBKEQBzAgARAAgJUiBKEQBzAgABLgAECgcJGwAHANIeAA==.',
Om='Omeganemesis:BAAALgADCgQJBAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8dAAMUAAgJ6hWpDwCIAQAGAAgJFhTCOAASAgAUAAgJfQ+pDwCIAQABLgAFFAIJBAABAAAAAA==.',
Or='Orghujon:BAAALgAECgUJCQAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgAECggJDgAAAA==.Palamon:BAAALgAECgMJBgAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBgAAAA==.Papadaddy:BAAALgADCgUJBQAAAA==.Parthos:BAAALgAECgcJDAAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAACLgAFFH8SAAIaAAMJESG8EwAjAQAaAAMJESG8EwAjAQAuAAQKfxYAAhoABwlFI7sHAFMCABoABwlFI7sHAFMCAAAA.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgAECgEJAQAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAAALgAECgUJBwABLgAFFAMJEgAaABEhAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pokedone:BAAALgADCgEJAQAAAA==.Polskashaman:BAABLgAECn8cAAIIAAgJBxHZCACVAQAIAAgJBxHZCACVAQAAAA==.Poptart:BAACLgAFFH8HAAINAAMJCgnhNgDYAAANAAMJCgnhNgDYAAAuAAQKfxUAAg0ACAm/EyJdAMsBAA0ACAm/EyJdAMsBAAAA.Power:BAAALgAECgYJDAABLgAFFAUJEwANAHolAA==.',
Pr='Prea:BAAALgAECgUJCgAAAA==.Premiumferal:BAAALgAECgYJCgABLgAECgkJIAARACofAA==.Primecarry:BAACLgAFFH8TAAIfAAYJzSMnAQBdAgAfAAYJzSMnAQBdAgAuAAQKfxcAAh8ACAkCI6IJANcCAB8ACAkCI6IJANcCAAAA.',
Pu='Pumpmedaddy:BAAALgAECgUJBQAAAA==.Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgYJDgAAAA==.',
['Pë']='Pëpsï:BAAALgAECgcJDgAAAA==.',
Qu='Quanah:BAAALgAECgUJCwAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgABAAAAAA==.Raigko:BAAALgAECgQJBQAAAA==.Raintolin:BAAALgAECgYJEAABLgAECgcJGgARAK8gAA==.Raiva:BAAALgADCgkJEAABLgAECggJIwARAKMcAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Raspberri:BAAALgADCgYJBgAAAA==.Rassputen:BAABLgAECn8oAAIXAAkJPhm2BgAsAgAXAAkJPhm2BgAsAgAAAA==.',
Re='Redjive:BAAALgAECgMJAgAAAA==.Redonkulos:BAAALgAFFAIJBAAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAaAPwPAA==.Redthorne:BAAALgADCgMJAwAAAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAACLgAFFH8HAAMLAAQJ4BNvCQBYAQALAAQJ4BNvCQBYAQAKAAMJFh4WCwAYAQAuAAQKfxwAAwsACAnhHhATAF0CAAsABwm0HhATAF0CAAoABgnQHJclAB0BAAAA.Reliri:BAAALgAECgEJAgAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgkJFQAAAA==.Rider:BAAALgADCgYJBgABLgAFFAYJFwAfAG8aAA==.Rinth:BAABLgAECn8hAAMhAAkJMSLzCQAEAwAhAAgJpiHzCQAEAwAgAAMJlSFzTwAfAQAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIdAAgJQhpBCABWAgAdAAgJQhpBCABWAgAAAA==.Roguen:BAABLgAECn8yAAIZAAgJohV+CwDoAQAZAAgJohV+CwDoAQABLgAECggJIgAFAK8ZAA==.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAAALgAECgUJCQABLgAFFAQJCgAhAH4IAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAAALgAECgYJDgAAAA==.Roulduke:BAABLgAECn8ZAAIOAAgJKBFcHgBaAQAOAAgJKBFcHgBaAQAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Rylearria:BAAALgADCgMJAwAAAA==.Ryna:BAAALgADCgkJBgAAAA==.',
['Rù']='Rùckús:BAABLgAECn8lAAIRAAkJFR9aDACkAgARAAkJFR9aDACkAgAAAA==.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8iAAMdAAgJvgqnFAD/AAAdAAgJvgqnFAD/AAANAAEJbgUJFAEtAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.Sakiara:BAAALgAECgQJBgAAAA==.Sammybeans:BAABLgAECn8jAAINAAgJ5RgpKQDbAQANAAgJ5RgpKQDbAQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAABLgAECn8YAAIgAAgJzxuREQBFAgAgAAgJzxuREQBFAgAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAABLgAECn8UAAIXAAgJxgNfJACjAAAXAAgJxgNfJACjAAAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Sc='Scrandle:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.Screwball:BAAALgADCgEJAQAAAA==.',
Se='Seceron:BAAALgAECgcJDQAAAA==.Sekai:BAAALgAECgMJAwAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8kAAMKAAgJ3gY7SQAUAQAKAAYJiwg7SQAUAQALAAgJNgTnJgAOAQAAAA==.Serpentsin:BAAALgAECgMJBAAAAA==.',
Sg='Sgtslappy:BAABLgAECn8mAAIDAAgJjxo8DAAnAgADAAgJjxo8DAAnAgAAAA==.',
Sh='Shanarelle:BAABLgAECn8aAAICAAgJzxkdHgBNAgACAAgJzxkdHgBNAgAAAA==.Shasa:BAABLgAECn8qAAIgAAgJsRzoGQBtAgAgAAgJsRzoGQBtAgAAAA==.Shazik:BAAALgAECgEJAQAAAA==.Sheroko:BAAALgAECgEJAQAAAA==.Shinanìgans:BAAALgAECgYJBgAAAA==.Shmoopy:BAAALgAECgYJBgAAAA==.Shortyman:BAAALgAECgUJBQABLgAECgkJIAARACofAA==.Shruikan:BAABLgAECn8UAAQPAAcJTRk3HADlAQAPAAcJ2Rg3HADlAQAQAAcJ7g8GGQBvAQAbAAMJlgWqPACFAAAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgYJCwABAAAAAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAABLgAECn8jAAMRAAgJoxxPGwAmAgARAAgJuxtPGwAmAgAXAAEJjhojQABNAAAAAA==.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAgAAAA==.Sisturfistur:BAAALgAECgQJBgAAAA==.',
Sk='Skunkpaw:BAAALgADCgYJEQAAAA==.Skysong:BAACLgAFFH8UAAMQAAYJvBFTAQCmAQAQAAUJ9Q9TAQCmAQAPAAQJrwzqEgDoAAAuAAQKfxkABBAACAnJHcYMAA4CABAABwlhG8YMAA4CABsABQl+EdkqABsBAA8AAwnVF0VCANoAAAAA.',
Sl='Slashedeye:BAABLgAECn8tAAIiAAkJlBgmAQAdAgAiAAkJlBgmAQAdAgAAAA==.',
Sm='Smellsoftree:BAAALgADCgYJDAAAAA==.',
Sn='Snowynn:BAABLgAECn8dAAMpAAkJGwsuDQA6AQApAAkJGwsuDQA6AQACAAEJWwHw6gAZAAAAAA==.Snubby:BAABLgAECn8kAAMWAAkJEyR0DAD7AQAVAAcJISVHJACCAgAWAAUJuCJ0DAD7AQAAAA==.',
So='Soleil:BAABLgAECn8UAAMLAAkJkg+0IwAkAQALAAkJkg+0IwAkAQAjAAMJZRMqOgBkAAAAAA==.Solheim:BAACLgAFFH8LAAMHAAQJzxb+BgBbAQAHAAQJshX+BgBbAQAhAAIJHB2WGgCvAAAuAAQKfyQAAyEACAkYI9AKAPgCACEACAkoItAKAPgCAAcABAlFHWcfAAQBAAAA.Souffle:BAABLgAECn8cAAMVAAcJaBf6SwDlAQAVAAcJaBf6SwDlAQAWAAEJAABrbQA6AAABLgAFFAQJCgANAKUVAA==.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMaAAgJ/A8VMgCJAQAaAAgJ/A8VMgCJAQATAAEJ/wcPYgAwAAAAAA==.Spookypink:BAABLgAECn8ZAAINAAkJkCJDEAANAwANAAkJkCJDEAANAwAAAA==.Spárda:BAAALgAECgEJAQABLgAECgcJGwAHANIeAA==.',
Sq='Squirtz:BAAALgAECgUJBQAAAA==.',
Sr='Srirachajane:BAAALgADCgkJDQABLgAECggJGQAnADAbAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Strathin:BAAALgADCgkJDQAAAA==.Strathz:BAABLgAECn8lAAMWAAkJpCCdCgAVAgAWAAYJPx+dCgAVAgAVAAcJjh4IHwD3AQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIfAAgJ1hq2GABNAgAfAAgJ1hq2GABNAgAAAA==.Summerset:BAAALgAECgYJEAAAAA==.Sushi:BAAALgAECgIJAwAAAA==.',
Sy='Sylatis:BAACLgAFFH8eAAMHAAgJphhfAAATAgAHAAcJ/RhfAAATAgAhAAYJiRTGAwAIAgAuAAQKfxYAAyEACAk0JVQNANsCACEACAk0JVQNANsCAAcAAwmkHoEyAGUAAAAA.Sylvara:BAAALgAECgMJBgAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.',
['Sö']='Söultender:BAABLgAECn8dAAQjAAgJaAs9FACfAQAjAAgJRAs9FACfAQALAAEJvAlIYwAyAAAKAAIJzAe7ggAvAAAAAA==.',
Ta='Taichi:BAACLgAFFH8LAAISAAQJhRWtDgAzAQASAAQJhRWtDgAzAQAuAAQKfyIAAhIACAkAHkcMAI4CABIACAkAHkcMAI4CAAAA.Talys:BAACLgAFFH8WAAIbAAcJVRl8AQBcAgAbAAcJVRl8AQBcAgAuAAQKfyMAAhsACQkRGYUIALICABsACQkRGYUIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgADCgUJBQAAAA==.Tarth:BAACLgAFFH8XAAIpAAYJkSKTAAAAAgApAAYJkSKTAAAAAgAuAAQKfxcAAikACAkEJmwBAEEDACkACAkEJmwBAEEDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8gAAIbAAcJrR3NBQA0AgAbAAcJrR3NBQA0AgAAAA==.Taïko:BAAALgADCgQJBAAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgYJDQABLgAECgcJGgARAK8gAA==.Tenniell:BAAALgAECgQJDQAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAABLgAECn8bAAIFAAkJTA8iKAACAgAFAAkJTA8iKAACAgAAAA==.',
Th='Thab:BAAALgAECgUJCAABLgAECggJGwAPAKYWAA==.Thabk:BAABLgAECn8bAAMPAAgJphbMEwCqAQAPAAgJphbMEwCqAQAQAAEJaAc8QwAoAAAAAA==.Thaelorn:BAAALgAECgMJAwAAAA==.Tharit:BAAALgADCgYJCgAAAA==.Theshortbuss:BAAALgAECgYJDwAAAA==.Thesuffering:BAAALgAECgUJBwAAAA==.Thesyra:BAAALgAECgYJBgAAAA==.Thingtwò:BAAALgADCgUJBQAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDgAAAA==.',
Ti='Tiddybear:BAAALgAECgEJAQAAAA==.Timerunhunt:BAAALgADCgUJBgAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAABLgAECn8UAAIXAAcJ2AWwHwDFAAAXAAcJ2AWwHwDFAAAAAA==.Toastz:BAAALgAECgEJAQAAAA==.Tokken:BAACLgAFFH8NAAIDAAQJTRGrDwAzAQADAAQJTRGrDwAzAQAuAAQKfyIAAgMACQnpHDwMAPcCAAMACQnpHDwMAPcCAAAA.',
Tr='Treebeast:BAACLgAFFH8GAAIOAAMJDRMWFwCbAAAOAAMJDRMWFwCbAAAuAAQKfxUAAg4ABwlnH4QcAC0CAA4ABwlnH4QcAC0CAAAA.Trojen:BAAALgADCgcJBwAAAA==.Trolladin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.',
Tu='Tubularoso:BAAALgAECgcJEAAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Tw='Twobtn:BAAALgAECgUJBQAAAA==.',
Ty='Tyras:BAAALgADCgYJBgAAAA==.',
Ul='Ulanda:BAAALgAECgYJEAAAAA==.',
Um='Umako:BAACLgAFFH8KAAMoAAUJ8hyUAQBvAQAoAAQJTB6UAQBvAQAZAAIJAxwkEwCzAAAuAAQKfyEAAygACQmuIfEAAEQDACgACQmUIfEAAEQDABkACAlGFyAdABYCAAAA.',
Un='Underbogg:BAAALgADCgUJBQAAAA==.Unus:BAAALgADCgQJBAABLgAECgkJIgAFAEwdAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Ux='Ux:BAAALgAECgcJBwAAAA==.',
Va='Vaedric:BAAALgAECgEJAQAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgcJEQAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAACLgAFFH8HAAIDAAQJzQaTFAANAQADAAQJzQaTFAANAQAuAAQKfxwAAgMACAlPGLgnAB8CAAMACAlPGLgnAB8CAAAA.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8hAAIDAAgJNSbhBACtAgADAAgJNSbhBACtAgABLgAFFAEJAgABAAAAAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8cAAIGAAgJew2QOQBQAQAGAAgJew2QOQBQAQAAAA==.Voids:BAAALgADCgcJDAAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAAALgAFFAIJAgABLgAFFAQJCgAhAH4IAA==.',
['Vé']='Vénandi:BAAALgAECgIJAgAAAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgABAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMYAAgJwBqFIwAKAgAYAAgJwBqFIwAKAgAOAAQJ7AVBSQCBAAAAAA==.',
Wa='Walkerwhite:BAAALgAECggJDgABLgAECggJIQALAN0ZAA==.Warjd:BAAALgAECgcJEgAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Weebo:BAAALgADCgQJBQAAAA==.Wesjin:BAABLgAECn8aAAISAAkJcRqyDgBrAgASAAkJcRqyDgBrAgAAAA==.Wez:BAAALgAECgYJBgAAAA==.',
Wh='Whiskee:BAACLgAFFH8KAAInAAMJtxoWBAAbAQAnAAMJtxoWBAAbAQAuAAQKfyMABCcACQmAIrQEAM0CACcACQmAIrQEAM0CABwAAQmhE4RSAD8AAAIAAQklAzfXACoAAAAA.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Wintulyn:BAAALgADCggJCgAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgADCggJFQAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wy='Wyndia:BAAALgAECgUJCgAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJCQABLgAECggJHQAjAGgLAA==.',
Xb='Xbert:BAAALgADCgcJBwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8UAAIFAAYJxBe6EACmAQAFAAYJxBe6EACmAQAuAAQKfxYAAgUACAn+IY0uALgCAAUACAn+IY0uALgCAAAA.',
Xi='Xihuang:BAAALgAECgMJAwABLgAECggJIgAFAK8ZAA==.Xiia:BAABLgAECn8jAAIhAAkJ3xsLAgB2AgAhAAkJ3xsLAgB2AgAAAA==.',
Xx='Xxoouu:BAABLgAFFH8FAAISAAUJNgThDwAiAQASAAUJNgThDwAiAQABLgAFFAYJAQABAAAAAA==.Xxuu:BAAALgAFFAYJAQAAAA==.Xxuublue:BAAALgAFFAYJAQAAAA==.Xxuuvoker:BAAALgAECgkJCQABLgAFFAYJAQABAAAAAA==.',
Ya='Yaoguai:BAABLgAECn8WAAMcAAgJrRGPFgCIAQAcAAgJrRGPFgCIAQACAAEJwAPD4wAhAAAAAA==.Yasei:BAAALgAECgEJAQAAAA==.Yawgmoth:BAABLgAECn8WAAMeAAkJVhb9BAAiAgAeAAkJVhb9BAAiAgAVAAEJKgzY2AA3AAAAAA==.',
Yd='Ydalflow:BAAALgADCgkJDQAAAA==.',
Za='Zammboomafoo:BAABLgAECn8WAAIdAAYJMiDkCAC7AQAdAAYJMiDkCAC7AQAAAA==.Zanian:BAABLgAECn8WAAMCAAcJ2BWCJQCeAQACAAcJ2BWCJQCeAQAnAAIJoAN3IQBTAAAAAA==.Zarthie:BAAALgADCgYJBgABLgAECgcJFgAPAMcTAA==.Zarthy:BAABLgAECn8WAAIPAAcJxxMrHQBVAQAPAAcJxxMrHQBVAQAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgYJEAAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zi='Zip:BAAALgADCgkJCQAAAA==.',
Zo='Zodd:BAAALgADCgEJAgAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgUJCwABLgAECgkJKgAFAFUjAA==.Zuo:BAAALgAECgMJBAAAAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAInAAgJMBv2BQCjAgAnAAgJMBv2BQCjAgAAAA==.',
['Zà']='Zàánn:BAABLgAECn8UAAIOAAcJbxA0IgBAAQAOAAcJbxA0IgBAAQAAAA==.',
['Ær']='Æris:BAAALgADCgYJBgAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAFFAQJCgAiAIccAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAFFAQJCgAiAIccAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgAECgEJAgAAAA==.',
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

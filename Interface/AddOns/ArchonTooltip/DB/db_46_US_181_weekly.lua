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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Frost','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Priest-Holy','Hunter-Survival','Warrior-Arms','Warlock-Destruction','Priest-Discipline','Priest-Shadow','Shaman-Elemental','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ag='Agnor:BAABLgAECn8nAAIBAAgJPBUGNgChAQABAAgJPBUGNgChAQAAAA==.',
Al='Alatir:BAAALgADCgQJCgAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAMJBwACAJMJAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8YAAIBAAkJNB3YCgC1AgABAAkJNB3YCgC1AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8IAAIDAAMJ4RhVGADhAAADAAMJ4RhVGADhAAAuAAQKfyoAAwMACAlJG7wiAAkCAAMACAlJG7wiAAkCAAQACAneDBtHAHABAAAA.',
Ar='Argus:BAABLgAECn8XAAIFAAYJaiCJEgDaAQAFAAYJaiCJEgDaAQAAAA==.Arithfury:BAAALgAECgIJAgABLgAECggJIAAGAOQXAA==.Arithkick:BAABLgAECn8gAAIGAAgJ5BdvFABrAgAGAAgJ5BdvFABrAgAAAA==.',
As='Asayo:BAAALgAECgUJEgAAAA==.Aske:BAAALgAECgYJEAAAAA==.',
At='Atonga:BAAALgADCgcJBwAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAAALgAECgcJBwAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIHAAcJzRHDPgBTAQAHAAcJzRHDPgBTAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQAIAAAAAA==.',
Be='Beatin:BAAALgAECgEJAQAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgUJDAAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloopydoo:BAAALgAECgUJBwAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8XAAIHAAgJqxq4MQCHAQAHAAgJqxq4MQCHAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgUJBQAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgADCgMJAwAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgADCgUJBQAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJGAABADQdAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgADCgUJBQAAAA==.',
Ch='Chestie:BAABLgAECn8fAAMBAAkJcx3WGwAiAgABAAgJ6B3WGwAiAgAJAAEJOhpwEgBZAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cindy:BAABLgAECn8aAAMHAAkJYRpPDAB8AgAHAAkJYRpPDAB8AgAKAAEJ3gWYkQApAAAAAA==.Cindyx:BAAALgAECgIJBQABLgAECgkJGgAHAGEaAA==.',
Co='Coast:BAAALgAECggJDgAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJJwALAOEZAA==.Coldsore:BAABLgAECn8nAAILAAkJ4RnXAwBZAgALAAkJ4RnXAwBZAgAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8wAAIEAAkJ+xsYDACiAgAEAAkJ+xsYDACiAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgADCgkJDQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAABLgAECn8tAAIFAAgJOhaYFgCzAQAFAAgJOhaYFgCzAQAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJBgAAAA==.Darkprophetc:BAAALgAECggJEgAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Demious:BAAALgAECggJDQAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAABLgAECn8ZAAIFAAgJQxo2HABrAgAFAAgJQxo2HABrAgAAAA==.Demonkiller:BAAALgAECgUJCgAAAA==.Denastiest:BAAALgAECgYJEAAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgMJAwAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8iAAMMAAYJ/iT9BABgAgAMAAYJ/iT9BABgAgANAAMJhhD7UgCdAAAAAA==.Dokta:BAAALgAECgYJCwAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAAALgAECgYJEgAAAA==.Drippydraws:BAAALgADCgIJAgAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgEJAQAAAA==.',
El='Elfgonewild:BAAALgAECgEJAQAAAA==.Ellessra:BAAALgAECgYJCQAAAA==.Elnegrouno:BAABLgAECn8fAAIOAAcJfR/OCgBkAgAOAAcJfR/OCgBkAgAAAA==.Eloper:BAAALgAECgEJAQAAAA==.',
Er='Eragone:BAAALgADCgcJBAAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8GAAIPAAIJ7RgdAwCuAAAPAAIJ7RgdAwCuAAAuAAQKfx0AAg8ACAmuIAcBAAIDAA8ACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8HAAILAAIJ9Bg8BwCTAAALAAIJ9Bg8BwCTAAAuAAQKfxcAAwsABglQH7oRAKwBAAsABglQH7oRAKwBAAQAAQlyB/NQASsAAAAA.',
Fa='Faeyri:BAAALgAECgYJEAAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAAALgAECgUJEQAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJBQAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8HAAIQAAMJAhkvPQAZAQAQAAMJAhkvPQAZAQAuAAQKfxoAAhAACAl2JQgTAIACABAACAl2JQgTAIACAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
Ga='Gallyn:BAAALgAFFAMJAwAAAA==.Gamm:BAAALgADCgcJEQAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAAALgAECgYJDwAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAAALgAECgYJDAAAAA==.Grelvisse:BAAALgAECgIJAgAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.',
Gw='Gwenie:BAABLgAECn8UAAIRAAYJ6wx6WgAeAQARAAYJ6wx6WgAeAQAAAA==.',
Ha='Halenicion:BAAALgAECgQJBgAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8dAAISAAgJ8w6oGACJAQASAAgJ8w6oGACJAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgQJBAAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAMJCAADAOEYAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huntardiness:BAABLgAECn8bAAMTAAgJ/Q6LEQCYAQATAAgJnQmLEQCYAQAHAAYJ3RFJUAB4AQAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAABLgAECn8WAAMFAAgJUSTvDgDcAgAFAAgJUSTvDgDcAgAUAAIJBxqTJQCbAAAAAA==.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Iv='Ive:BAABLgAECn8ZAAQVAAgJaiJ1EQDBAQARAAcJnSKxTgDcAQAVAAcJzBp1EQDBAQAPAAIJHBDyJABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgMJBAAAAA==.Jarnunvosk:BAAALgAECgYJCQAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8aAAMWAAYJyQtuIAAoAQAWAAYJyQtuIAAoAQAXAAEJmQDJXQAIAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECgcJCwAIAAAAAA==.',
Ka='Kadri:BAAALgAECgMJAwAAAA==.Kaffee:BAABLgAECn8fAAILAAgJkgrLEgAVAQALAAgJkgrLEgAVAQAAAA==.Kamakaz:BAAALgAECgYJCAAAAA==.Kamasdruid:BAAALgAECgMJBQAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaywhy:BAAALgAECggJDwAAAA==.',
Ki='Kichack:BAAALgAECgYJEAAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8eAAINAAgJ7x3iBAByAgANAAgJ7x3iBAByAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAAALgAECgUJCAAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAAALgAECgcJEwAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Krelo:BAAALgAECgYJEAAAAA==.',
Kt='Ktom:BAABLgAECn8kAAIYAAgJQiMqBAC9AgAYAAgJQiMqBAC9AgAAAA==.',
Ku='Kurimbory:BAAALgAECgQJBAAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMHAAgJmwdHUgByAQAHAAgJmwdHUgByAQAKAAYJ6gLCWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgEJAQAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAAALgAECgcJEwAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAABLgAECn8fAAIBAAgJZxv2GAA2AgABAAgJZxv2GAA2AgAAAA==.Lostwarrior:BAAALgAECgUJBQAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAAALgAECggJDAAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAAALgAECgUJCAAAAA==.Magêyalook:BAABLgAECn8ZAAIQAAgJghFLNQDMAQAQAAgJghFLNQDMAQAAAA==.Manzz:BAAALgAECgUJBgAAAA==.Marcelline:BAAALgADCgYJBgAAAA==.Mattob:BAAALgADCgUJBQAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Mazyme:BAAALgADCgQJCAAAAA==.',
Me='Meandmypal:BAACLgAFFH8RAAITAAUJ+yGbAgCQAQATAAUJ+yGbAgCQAQAuAAQKfy0AAhMACAkiJrkAAHwDABMACAkiJrkAAHwDAAAA.Mello:BAAALgAECggJEQAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgADCgIJAgAAAA==.Milim:BAAALgAECgIJAwAAAA==.Mirba:BAAALgAECgYJEAAAAA==.',
Mo='Mongo:BAABLgAECn8gAAIBAAgJnh5jFwBAAgABAAgJnh5jFwBAAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8VAAIQAAgJuwlZZgBEAQAQAAgJuwlZZgBEAQAAAA==.Morené:BAAALgAECgEJAQAAAA==.Moxxee:BAAALgADCgUJEQAAAA==.',
Mu='Mushhmelu:BAAALgADCgUJBQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAABLgAECn8fAAIZAAgJYg9kVQCjAQAZAAgJYg9kVQCjAQAAAA==.',
Ne='Neutrallee:BAAALgADCgcJBwAAAA==.Newa:BAAALgAECgUJBQAAAA==.',
Ni='Nightwater:BAABLgAECn8jAAMaAAgJrBioIQC4AQAaAAgJrBioIQC4AQAbAAIJXwlvHgBoAAAAAA==.',
['Né']='Nébulien:BAABLgAECn8XAAIcAAgJYxwuCQBHAgAcAAgJYxwuCQBHAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIQAAYJ8hCBwABjAQAQAAYJ8hCBwABjAQAAAA==.',
Or='Orchop:BAAALgAECgUJCgAAAA==.Orkrist:BAAALgAECgYJDAAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Paulterian:BAAALgAECgQJBAAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAAALgAECggJEAAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgUJEAAAAA==.Power:BAAALgAECgQJCAAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAgABLgAECggJGQAVAGoiAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8XAAIDAAgJOxTjEwD0AQADAAgJOxTjEwD0AQAAAA==.Rayshano:BAAALgAECgYJEgAAAA==.',
Re='Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgUJDAAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ru='Rustynails:BAABLgAECn8gAAIdAAgJKiS6AAC/AgAdAAgJKiS6AAC/AgAAAA==.',
Sa='Saffire:BAAALgADCgEJAQAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgAIAAAAAA==.Samwitch:BAAALgAECgEJAQAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgUJCAAAAA==.',
Sc='Scott:BAACLgAFFH8QAAIOAAQJvCO2AgCmAQAOAAQJvCO2AgCmAQAuAAQKfyMAAg4ACAmXJNIDABMDAA4ACAmXJNIDABMDAAAA.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8YAAINAAYJjRiiEQBuAQANAAYJjRiiEQBuAQAAAA==.Scynx:BAAALgAECgYJCAAAAA==.',
Se='Seaka:BAABLgAECn8aAAMaAAgJohepKQCGAQAaAAcJYBapKQCGAQAeAAUJQBT1NgCwAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAECgQJBgAIAAAAAA==.Sernix:BAAALgAECgYJDgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shaeia:BAACLgAFFH8IAAIYAAMJzxCvGADoAAAYAAMJzxCvGADoAAAuAAQKfx8AAhgACQn0HLQNAMYCABgACQn0HLQNAMYCAAAA.Shangi:BAAALgADCgMJAgABLgAFFAIJBwALAPQYAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIGAAYJgSEsBQClAQAGAAYJgSEsBQClAQAuAAQKfxoAAgYACAmDHRMRAI8CAAYACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8bAAINAAcJIRnyGQD0AQANAAcJIRnyGQD0AQAAAA==.Slyavane:BAABLgAECn8hAAQPAAgJkwodBgBZAQAPAAgJRgodBgBZAQAVAAcJawfDDQD2AAARAAQJWwT94ACYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8IAAIEAAMJDxQeFgD7AAAEAAMJDxQeFgD7AAAuAAQKfxkAAwsACAkiHrsFABMCAAsACAkHGrsFABMCAAQACAlAGZRKAAMCAAEuAAUUBAkEAAgAAAAA.',
Sn='Snowwind:BAAALgAECgUJBQAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIHAAkJ8R+/BADnAgAHAAkJ8R+/BADnAgAAAA==.Sonasai:BAAALgADCgUJEQAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJDAAAAA==.Soxs:BAABLgAECn8aAAMfAAgJJBKsFAC1AQAfAAgJJBKsFAC1AQAgAAEJAgrJXwAyAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBgAAAA==.Stardris:BAABLgAECn8aAAIZAAgJOQIhlABnAAAZAAgJOQIhlABnAAAAAA==.Stompygnome:BAAALgAECgQJBwAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Tartanus:BAABLgAECn8iAAIZAAgJQBYLIADIAQAZAAgJQBYLIADIAQAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAECgcJGAAcANYeAA==.',
Te='Teramiah:BAAALgADCgUJDQAAAA==.',
Th='Theadona:BAAALgAECgUJCgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.',
Ti='Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8JAAIJAAMJdBvBAwACAQAJAAMJdBvBAwACAQAuAAQKfyoAAwkACQkEIB0CALECAAkACQkEIB0CALECAAEAAwkNBsMDAXAAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8MAAIgAAQJlB1wBAB0AQAgAAQJlB1wBAB0AQAuAAQKfx4AAiAACAmwIrwIAO0CACAACAmwIrwIAO0CAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn8oAAIeAAgJTgb5JQAOAQAeAAgJTgb5JQAOAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8cAAIYAAcJxxHSHgBXAQAYAAcJxxHSHgBXAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBAAAAA==.',
Un='Underdog:BAABLgAECn8WAAIKAAgJjRDKDwDxAAAKAAgJjRDKDwDxAAAAAA==.',
Va='Vaern:BAAALgAECgYJEAAAAA==.Vagindivin:BAAALgAECgEJAQAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAAALgAECgYJEAAAAA==.',
Vi='Virus:BAAALgAECgMJBQAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Warfield:BAABLgAECn8WAAMhAAgJ8BKkCQCHAQAhAAgJ8BKkCQCHAQAbAAEJWgMqLQAjAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIZAAkJYRU6LQCCAQAZAAkJYRU6LQCCAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAQAAAA==.',
Wr='Wrathsome:BAAALgAECgYJEAAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAAIAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Za='Zaio:BAAALgAECgMJAwAAAA==.Zarkus:BAAALgAECgQJCgAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAAALgAFFAQJBAAAAA==.',
['Åy']='Åylå:BAAALgAECgEJAQAAAA==.',
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

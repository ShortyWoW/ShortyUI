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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warlock-Affliction','Mage-Frost','Priest-Holy','Hunter-Survival','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAQAAAA==.',
Ag='Agnor:BAABLgAECn8bAAIBAAcJ1xGlewCNAQABAAcJ1xGlewCNAQAAAA==.',
Al='Alatir:BAAALgADCgQJCgAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAECgcJBwACAAAAAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8WAAIBAAgJtx6CCgB7AgABAAgJtx6CCgB7AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8FAAIDAAMJ7hfkEADyAAADAAMJ7hfkEADyAAAuAAQKfyYAAwMACAlHG70iAAkCAAMACAlHG70iAAkCAAQABgnLDbJgAPMAAAAA.',
Ar='Argus:BAAALgAECgYJEQAAAA==.Arithfury:BAAALgAECgIJAgABLgAECggJIAAFAOQXAA==.Arithkick:BAABLgAECn8gAAIFAAgJ5BduFABrAgAFAAgJ5BduFABrAgAAAA==.',
As='Asayo:BAAALgAECgUJEgAAAA==.Aske:BAAALgAECgYJDQAAAA==.',
At='Atonga:BAAALgADCgcJBwAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAAALgADCgkJCQAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIGAAcJzBF+LABgAQAGAAcJzBF+LABgAQAAAA==.Barlee:BAAALgADCgEJAQABLgAECgQJCAACAAAAAA==.',
Be='Beatin:BAAALgAECgEJAQAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgQJBwAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloopydoo:BAAALgAECgIJBAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8UAAIGAAgJKxrnIwCMAQAGAAgJKxrnIwCMAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgEJAQAAAA==.Borim:BAAALgADCgIJAgAAAA==.',
Br='Brandymae:BAAALgADCgMJAwAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECggJFgABALceAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
Ch='Chestie:BAABLgAECn8eAAIBAAgJ4h0HEAA9AgABAAgJ4h0HEAA9AgAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cindy:BAABLgAECn8YAAMGAAgJjRjpDwAYAgAGAAgJjRjpDwAYAgAHAAEJ3gWGkQApAAAAAA==.Cindyx:BAAALgAECgIJAwABLgAECggJGAAGAI0YAA==.',
Co='Coast:BAAALgAECggJDgAAAA==.Coldsore:BAABLgAECn8nAAIIAAkJ2RlaAgBmAgAIAAkJ2RlaAgBmAgAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8nAAIEAAkJ7hm+CgB3AgAEAAkJ7hm+CgB3AgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgADCgMJBQAAAA==.Cynthea:BAAALgAECgkJCAAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAABLgAECn8sAAIJAAgJKxYqDwDFAQAJAAgJKxYqDwDFAQAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJBgAAAA==.Darkprophetc:BAAALgAECggJDAAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Demious:BAAALgAECgYJCgAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAABLgAECn8VAAIJAAgJLBk6HABrAgAJAAgJLBk6HABrAgAAAA==.Demonkiller:BAAALgAECgMJBQAAAA==.Denastiest:BAAALgAECgYJDQAAAA==.Denji:BAAALgAECggJDwAAAA==.Devvmonk:BAAALgAECgMJAwAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8dAAMKAAYJ/iT9BABgAgAKAAYJ/iT9BABgAgALAAMJhhD5UgCdAAAAAA==.Dokta:BAAALgAECgMJBQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAAALgAECgQJBQAAAA==.Drippydraws:BAAALgADCgIJAgAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgEJAQAAAA==.',
El='Elfgonewild:BAAALgADCgcJCQAAAA==.Ellessra:BAAALgAECgYJBgAAAA==.Elnegrouno:BAABLgAECn8YAAIMAAcJfB/OCgBkAgAMAAcJfB/OCgBkAgAAAA==.Eloper:BAAALgAECgEJAQAAAA==.',
Er='Eragone:BAAALgADCgYJAgAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8FAAINAAIJCRV3AQC1AAANAAIJCRV3AQC1AAAuAAQKfx0AAg0ACAmqIAcBAAIDAA0ACAmqIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8FAAIIAAIJ5xWTBQCFAAAIAAIJ5xWTBQCFAAAuAAQKfxcAAwgABglQH7kRAKwBAAgABglQH7kRAKwBAAQAAQlyB/tQASsAAAAA.',
Fa='Faeyri:BAAALgAECgYJDQAAAA==.Fassandin:BAAALgAECgEJAQAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAAALgAECgQJDAAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJCwAAAA==.Fourid:BAAALgAECgQJBQAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAABLgAECn8XAAIOAAgJQSInEQBTAgAOAAgJQSInEQBTAgAAAA==.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
Ga='Gallyn:BAAALgAFFAIJAgAAAA==.Gamm:BAAALgADCgcJEQAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAAALgAECgYJDwAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAAALgAECgYJCAAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Guimon:BAAALgAECgMJBAAAAA==.',
Gw='Gwenie:BAAALgAECgYJDgAAAA==.',
Ha='Halenicion:BAAALgAECgQJBQABLgAECgQJBQACAAAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8YAAIPAAcJDA8fFQBnAQAPAAcJDA8fFQBnAQAAAA==.',
Ho='Honestlee:BAAALgAECgEJAQAAAA==.Honourablee:BAAALgAECgQJBAAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huntardiness:BAABLgAECn8XAAMGAAYJ1hFKUAB4AQAGAAYJ1hFKUAB4AQAQAAYJaAkgFAArAQAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAABLgAECn8UAAMJAAgJFyT0DgDcAgAJAAgJFyT0DgDcAgARAAIJARqLGwCdAAAAAA==.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Iv='Ive:BAABLgAECn8WAAQSAAYJSCJ2EQDBAQATAAYJSyG4TgDcAQASAAYJNhp2EQDBAQANAAIJHBDzJABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgMJAwAAAA==.Jarnunvosk:BAAALgAECgYJBgAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAAALgAECgYJDwAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECgQJBAACAAAAAA==.',
Ka='Kadri:BAAALgAECgIJAgAAAA==.Kaffee:BAABLgAECn8ZAAIIAAYJfQ0PFADNAAAIAAYJfQ0PFADNAAAAAA==.Kamakaz:BAAALgAECgYJBgAAAA==.Kamasdruid:BAAALgAECgIJAgAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBgAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaywhy:BAAALgAECgYJDAAAAA==.',
Ki='Kichack:BAAALgAECgYJDQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8aAAILAAgJoBvpBQAIAgALAAgJoBvpBQAIAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAAALgAECgUJBQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAAALgAECgYJEQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Krelo:BAAALgAECgYJDQAAAA==.',
Kt='Ktom:BAABLgAECn8iAAIUAAgJiiH9AgCsAgAUAAgJiiH9AgCsAgAAAA==.',
Ku='Kurimbory:BAAALgADCgIJAgAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMGAAgJmwdIUgByAQAGAAgJmwdIUgByAQAHAAYJ6gKrWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgEJAQAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAAALgAECgcJEQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAABLgAECn8YAAIBAAcJgRvtIADCAQABAAcJgRvtIADCAQAAAA==.Lostwarrior:BAAALgADCgYJBgAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAAALgAECgcJBwAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCgAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAAALgAECgUJCAAAAA==.Magêyalook:BAAALgAECgUJCwAAAA==.Manzz:BAAALgAECgUJBgAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Mazyme:BAAALgADCgQJBwAAAA==.',
Me='Meandmypal:BAACLgAFFH8OAAIQAAUJShwFAQB5AQAQAAUJShwFAQB5AQAuAAQKfy0AAhAACAkiJrkAAHwDABAACAkiJrkAAHwDAAAA.Mello:BAAALgAECggJDgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Milim:BAAALgAECgIJAwAAAA==.Mirba:BAAALgAECgYJDQAAAA==.',
Mo='Mongo:BAABLgAECn8gAAIBAAgJnh5LDQBaAgABAAgJnh5LDQBaAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8VAAIOAAgJuAl9TQBIAQAOAAgJuAl9TQBIAQAAAA==.Morené:BAAALgAECgEJAQAAAA==.Moxxee:BAAALgADCgQJDAAAAA==.',
My='Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAABLgAECn8fAAIVAAgJZA9jVQCjAQAVAAgJZA9jVQCjAQAAAA==.',
Ne='Neutrallee:BAAALgADCgcJBwAAAA==.Newa:BAAALgAECgIJAgAAAA==.',
Ni='Nightwater:BAABLgAECn8iAAMWAAgJpxh4FwDGAQAWAAgJpxh4FwDGAQAXAAEJxQaFIAAuAAAAAA==.',
['Né']='Nébulien:BAABLgAECn8XAAIYAAgJZBwuCQBHAgAYAAgJZBwuCQBHAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIOAAYJ8hB6wABjAQAOAAYJ8hB6wABjAQAAAA==.',
Or='Orchop:BAAALgAECgMJAwAAAA==.Orkrist:BAAALgAECgUJBgAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Paulterian:BAAALgAECgQJBAAAAA==.Paymeforpi:BAAALgADCgUJBQAAAA==.',
Ph='Phelaeshio:BAAALgAECggJEAAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgQJCwAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.Purpz:BAAALgAECgQJBAAAAA==.',
['På']='Pårts:BAAALgAECgQJCAAAAA==.',
['Pù']='Pùff:BAAALgAECgUJBgAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAgAAAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAAALgAECgYJEgAAAA==.Rayn:BAAALgADCgkJEAAAAA==.Rayshano:BAAALgAECgYJDQAAAA==.',
Re='Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgQJBwAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ru='Rustynails:BAABLgAECn8YAAIZAAgJZiG2AQD9AQAZAAgJZiG2AQD9AQAAAA==.',
Sa='Saly:BAAALgADCgIJAQABLgADCggJDgACAAAAAA==.Samwitch:BAAALgADCgkJDQAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgUJBQAAAA==.',
Sc='Scott:BAACLgAFFH8MAAIMAAQJex44AwBiAQAMAAQJex44AwBiAQAuAAQKfyEAAgwACAlZI9EDABMDAAwACAlZI9EDABMDAAAA.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAAALgAECgQJEAAAAA==.Scynx:BAAALgAECgQJBgAAAA==.',
Se='Seaka:BAABLgAECn8VAAMWAAcJXRa5HQCTAQAWAAcJXRa5HQCTAQAaAAQJhRSmXACwAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQAAAA==.Sernix:BAAALgAECgYJDgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shaeia:BAACLgAFFH8IAAIUAAMJzhAdEQD2AAAUAAMJzhAdEQD2AAAuAAQKfxsAAhQACQmFG7INAMYCABQACQmFG7INAMYCAAAA.Shangi:BAAALgADCgMJAgABLgAFFAIJBQAIAOcVAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Sivtekeda:BAAALgAECgQJCAAAAA==.',
Sk='Sktibrew:BAACLgAFFH8QAAIFAAUJoCF0BACRAQAFAAUJoCF0BACRAQAuAAQKfxoAAgUACAmDHRURAI8CAAUACAmDHRURAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8bAAILAAcJGxnwGQD0AQALAAcJGxnwGQD0AQAAAA==.Slyavane:BAABLgAECn8dAAQSAAcJUAp6CgD9AAANAAYJ9ArMBQAeAQASAAcJZQd6CgD9AAATAAQJWwTz4ACYAAAAAA==.Slyice:BAAALgAECgEJBQAAAA==.',
Sm='Smokess:BAACLgAFFH8IAAIEAAMJCxQdFgD7AAAEAAMJCxQdFgD7AAAuAAQKfxkAAwgACAkWHswDAB4CAAgACAn5GcwDAB4CAAQACAlAGZNKAAMCAAAA.',
Sn='Snowwind:BAAALgADCgQJDAAAAA==.',
So='Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8iAAIGAAkJ9BxdBwCBAgAGAAkJ9BxdBwCBAgAAAA==.Sonasai:BAAALgADCgQJDAAAAA==.Sonnybear:BAAALgADCgQJDAAAAA==.Soulhatcher:BAAALgAECgQJBwAAAA==.Soxs:BAABLgAECn8ZAAMbAAgJIhKCDgC/AQAbAAgJIhKCDgC/AQAcAAEJBAr8SAA0AAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBgAAAA==.Stardris:BAABLgAECn8aAAIVAAgJPAKnawBoAAAVAAgJPAKnawBoAAAAAA==.Stompygnome:BAAALgAECgQJBAAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Tartanus:BAABLgAECn8gAAIVAAgJrxWjFADFAQAVAAgJrxWjFADFAQAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAECgcJFwAYANYeAA==.',
Te='Teramiah:BAAALgADCgQJCAAAAA==.',
Th='Theadona:BAAALgAECgUJCgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.',
Ti='Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8GAAIdAAMJ0xShAgAEAQAdAAMJ0xShAgAEAQAuAAQKfyUAAx0ACAnlIB0CALECAB0ACAnlIB0CALECAAEAAwkNBr8DAXAAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8IAAIcAAMJKBpkCAASAQAcAAMJKBpkCAASAQAuAAQKfxsAAhwACAnkIL4IAO0CABwACAnkIL4IAO0CAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn8hAAIaAAgJUwW2HQAOAQAaAAgJUwW2HQAOAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8VAAIUAAYJPBFsIgALAQAUAAYJPBFsIgALAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJAwAAAA==.',
Un='Underdog:BAABLgAECn8VAAIHAAcJvREeOACCAQAHAAcJvREeOACCAQAAAA==.',
Va='Vaern:BAAALgAECgYJDQAAAA==.Vagindivin:BAAALgAECgEJAQAAAA==.Valrie:BAAALgADCgYJBgAAAA==.Valyteil:BAAALgAECgEJAQAAAA==.',
Ve='Venngance:BAAALgAECgYJDQAAAA==.',
Vi='Virus:BAAALgAECgIJAgAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Warfield:BAAALgAECgcJEAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8YAAIVAAkJsBN6VQCjAQAVAAkJsBN6VQCjAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.',
Wr='Wrathsome:BAAALgAECgYJDQAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAACAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Za='Zaio:BAAALgAECgMJAwAAAA==.Zarkus:BAAALgAECgQJBwAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
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

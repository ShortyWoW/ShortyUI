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

local lookup = {'Monk-Windwalker','Priest-Holy','Warrior-Fury','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','Priest-Discipline','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Priest-Shadow','DemonHunter-Vengeance','Warlock-Demonology','Druid-Balance','Paladin-Holy','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','DeathKnight-Blood','Warlock-Affliction','Monk-Mistweaver','Monk-Brewmaster','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abanados:BAAALgAECgYJDgAAAA==.',
Ak='Akatsuki:BAABLgAECn8qAAIBAAkJ/yK4AAAoAwABAAkJ/yK4AAAoAwAAAA==.',
Al='Althea:BAABLgAECn8kAAICAAgJMxFlEQCUAQACAAgJMxFlEQCUAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAECgkJHwADAJoXAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgMJAwAAAA==.',
Ar='Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIEAAgJMCBKHADAAgAEAAgJMCBKHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEALgAECgYJEQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgIJBAAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgAAAA==.Bajamama:BAABLgAECn8YAAMFAAYJsRBbPABbAQAFAAYJsRBbPABbAQAGAAYJ/g7zTABPAQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAECgMJAwABLgAECggJJwAHAHQhAA==.Betarius:BAAALgAECgQJBAABLgAECgYJDgAIAAAAAA==.Betiff:BAAALgAECgYJDgAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJKQAJAFkRAA==.Blooded:BAAALgAECgkJEAAAAA==.Bloodydraco:BAABLgAECn8qAAMKAAkJkhUgBAA8AgAKAAkJkhUgBAA8AgALAAEJsAUFFAA0AAAAAA==.',
Bo='Bolden:BAAALgADCgcJGAAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgEJAgAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn8pAAIMAAkJmR8eAgCZAgAMAAkJmR8eAgCZAgAAAA==.Camembert:BAABLgAECn8hAAINAAgJfSMlAQCZAgANAAgJfSMlAQCZAgAAAA==.Casii:BAAALgAECgYJDQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIOAAYJsBLRJwBXAQAOAAYJsBLRJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAABLgAECn8WAAIPAAYJVR/qLQCDAQAPAAYJVR/qLQCDAQAAAA==.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAAALgAECgYJBgABLgAECggJIQADADUiAA==.',
Co='Coggette:BAABLgAECn8UAAIQAAYJxgSwhgDGAAAQAAYJxgSwhgDGAAAAAA==.',
Cr='Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAAALgAECgMJBAAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgQJBAAAAA==.Darkcurve:BAAALgAECgYJCgAAAA==.Darkhope:BAAALgAECgYJCgAAAA==.',
De='Deija:BAABLgAECn8VAAIRAAYJGR0cIgBmAQARAAYJGR0cIgBmAQAAAA==.Dekoo:BAABLgAECn8YAAIHAAYJ4yH9DAA7AgAHAAYJ4yH9DAA7AgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Deusene:BAABLgAECn8YAAISAAYJHhAGHQAUAQASAAYJHhAGHQAUAQAAAA==.',
Dr='Drakula:BAAALgAECgIJAgAAAA==.Dreadfang:BAABLgAECn8qAAIPAAkJLyMCAwAHAwAPAAkJLyMCAwAHAwAAAA==.Droka:BAABLgAECn8YAAIGAAYJwh/mHgAmAgAGAAYJwh/mHgAmAgAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.',
En='Endel:BAAALgADCgcJBQAAAA==.',
Eu='Eurotophobia:BAAALgAECgYJEQAAAA==.',
Ex='Exodia:BAAALgAECgYJEgAAAA==.',
Fa='Faldrithor:BAAALgADCgkJCQAAAA==.',
Fe='Fellaria:BAABLgAECn8mAAMTAAkJnyNTAAD9AgATAAkJnyNTAAD9AgARAAEJWwtrjgAwAAAAAA==.',
Fh='Fhyllo:BAAALgAECgYJDAAAAA==.',
Fo='Follaglas:BAAALgAECgYJEgAAAA==.',
Ga='Gairen:BAAALgAECgQJBAAAAA==.Galadisis:BAABLgAECn8qAAIDAAkJ7RkJBQBuAgADAAkJ7RkJBQBuAgAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn8WAAIUAAcJOR01IwClAQAUAAcJOR01IwClAQABLgAECgMJBAAIAAAAAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECggJDwAAAA==.',
Gr='Gryari:BAAALgAECgIJAgAAAA==.',
Gu='Guiche:BAAALgAECgEJAgAAAA==.',
Gw='Gwiynevere:BAAALgAECgYJDwAAAA==.',
He='Heathclif:BAAALgADCgUJCgABLgAECggJIQADADUiAA==.Hellao:BAABLgAECn8jAAIVAAgJuxU/CwDbAQAVAAgJuxU/CwDbAQAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Hoxpox:BAAALgADCgcJDQAAAA==.',
Hr='Hrimceald:BAAALgAECgYJCgAAAA==.',
Hy='Hylts:BAABLgAECn8ZAAIJAAYJORTBCQBLAQAJAAYJORTBCQBLAQAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECgEJAQAAAA==.',
Im='Imalockyo:BAAALgAECgEJAQAAAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn8YAAMEAAYJrRr7OwBWAQAEAAYJrRr7OwBWAQAWAAYJ4AcZWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECgYJFQARABkdAA==.',
Ke='Kejiabaobei:BAABLgAECn8pAAIXAAkJkSWTAABZAwAXAAkJkSWTAABZAwAAAA==.Kesta:BAAALgADCgkJEgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQAAAA==.',
Ko='Koi:BAAALgAECgEJAQABLgADCgEJAQAIAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8dAAMRAAgJoyKOJQBxAgARAAgJoyKOJQBxAgAYAAIJ2wrgaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgQJBQABLgAECgYJEQAIAAAAAA==.Krayel:BAAALgAECgEJAQAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8pAAIKAAkJdhrwAQC5AgAKAAkJdhrwAQC5AgAAAA==.',
Kt='Kt:BAAALgAECgEJAQABLgADCgUJBQAIAAAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.',
La='Lachdanan:BAABLgAECn8WAAIZAAYJywqvFADFAAAZAAYJywqvFADFAAAAAA==.Lament:BAABLgAECn8VAAIRAAcJ1R4eEwDSAQARAAcJ1R4eEwDSAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAIXAAgJwh4qEwCeAgAXAAgJwh4qEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8WAAMJAAYJBRaHCQBPAQAJAAYJBRaHCQBPAQAGAAYJfxXMKgAdAQAAAA==.Lolly:BAAALgADCgUJBQAAAA==.Loralin:BAAALgADCgcJBwAAAA==.',
Ly='Lyreshade:BAABLgAECn8lAAIFAAkJDBI3JQDnAQAFAAkJDBI3JQDnAQAAAA==.',
Ma='Maatdemon:BAAALgADCgYJBgABLgAECgkJKgABAP8iAA==.Madbunny:BAAALgADCgUJBwAAAA==.Mahrah:BAABLgAECn8WAAINAAYJhhU9CgAnAQANAAYJhhU9CgAnAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgADCgcJBwAAAA==.Marija:BAAALgADCgYJBwABLgAECgYJFQARABkdAA==.',
Me='Melevolence:BAABLgAECn8qAAMUAAkJ8RjBDQA+AgAUAAkJ8RjBDQA+AgAaAAMJ9wZgQQCvAAAAAA==.Mep:BAAALgADCgkJCQABLgAECgUJBwAIAAAAAA==.Meplastered:BAAALgAECgYJDAAAAA==.',
Mi='Mirithari:BAAALgADCgcJBwAAAA==.',
Mo='Molby:BAAALgAECgEJAQABLgAECgYJEwAIAAAAAA==.Moolinda:BAABLgAECn8eAAIGAAgJNBdaEADzAQAGAAgJNBdaEADzAQAAAA==.Morticia:BAABLgAECn8UAAMbAAgJgxwlCACZAQAbAAgJgxwlCACZAQAPAAIJjASJCQFiAAAAAA==.Motgul:BAAALgAECgUJBwAAAA==.',
My='Mythbras:BAAALgAECgEJAQAAAA==.Mythfurry:BAAALgAECgMJAwAAAA==.',
Na='Naxria:BAAALgAECgQJBAAAAA==.',
Ne='Nezanu:BAAALgAECgUJBwAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nimithriel:BAABLgAECn8hAAISAAgJ3RT+DQClAQASAAgJ3RT+DQClAQAAAA==.',
No='Notweso:BAABLgAECn8lAAIRAAgJ0yNhBQCLAgARAAgJ0yNhBQCLAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Pa='Pallywack:BAAALgADCgcJBwAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAECgYJEgAIAAAAAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAECggJIQADADUiAA==.',
Po='Poovey:BAABLgAECn8fAAIDAAkJmhdzHwBVAgADAAkJmhdzHwBVAgAAAA==.',
Pu='Purpletoe:BAAALgAECgYJDAAAAA==.',
Py='Pyronae:BAABLgAECn8YAAIUAAYJhxRbQQAuAQAUAAYJhxRbQQAuAQAAAA==.',
Ra='Rargh:BAAALgAECgYJEgAAAA==.',
Re='Redonkeylous:BAAALgAECgMJAwAAAA==.Reya:BAABLgAECn8WAAIPAAYJbxtpLQCFAQAPAAYJbxtpLQCFAQAAAA==.',
Ri='Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAAALgAECgMJAwAAAA==.',
Sa='Saeli:BAABLgAECn8hAAIVAAkJtBXnCQDxAQAVAAkJtBXnCQDxAQAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn8YAAIcAAYJbRl8CADCAQAcAAYJbRl8CADCAQAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Se='Sentien:BAAALgAECgcJAQAAAA==.',
Sh='Shadowstripe:BAABLgAECn8YAAQBAAgJzw/1EQBkAQABAAcJPhH1EQBkAQAdAAMJ8QPtZQA6AAAeAAEJGAaCjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgEJAQAAAA==.Shigglez:BAABLgAECn8oAAIQAAgJ+hv0EgBDAgAQAAgJ+hv0EgBDAgAAAA==.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Sonatina:BAACLgAFFH8VAAIOAAgJLx41AADfAgAOAAgJLx41AADfAgAuAAQKfx0AAw4ACAmxJQABAFQDAA4ACAmxJQABAFQDABIAAQl3F29bAEgAAAAA.Soulfly:BAABLgAECn8rAAMBAAgJQhYJDgCZAQABAAgJQhYJDgCZAQAeAAMJgwe3eQBcAAAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn8gAAIdAAYJlRSWGwAlAQAdAAYJlRSWGwAlAQAAAA==.Sulfuric:BAAALgADCgYJDQAAAA==.Sumtongue:BAAALgAECgMJAwAAAA==.',
Sy='Sylphrenä:BAAALgAECgYJEgAAAA==.',
Te='Tembtree:BAAALgAECgYJDgABLgAECgYJGwAaAF0TAA==.Temlock:BAABLgAECn8bAAMaAAYJXROxCAAiAQAaAAYJXROxCAAiAQAUAAMJ8AEC+wBkAAAAAA==.',
Th='Thrawnn:BAABLgAECn8hAAIDAAgJNSIfAwClAgADAAgJNSIfAwClAgAAAA==.',
Tr='Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgADCgYJDgAAAA==.',
Ty='Tyrenari:BAAALgAECgQJBQAAAA==.',
Ul='Ultear:BAABLgAECn8YAAQTAAYJFBgFCAAyAQARAAYJBA/JZQBwAQATAAYJpBcFCAAyAQAYAAIJ/xBnXABuAAAAAA==.',
Ve='Velkyn:BAABLgAECn8kAAIfAAgJ+RJNCwC0AQAfAAgJ+RJNCwC0AQAAAA==.Vetenarae:BAAALgADCgMJAwABLgAECgYJGQAJADkUAA==.',
Vo='Volkren:BAABLgAECn8rAAIbAAgJvh39BQDMAQAbAAgJvh39BQDMAQAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgYJCgAIAAAAAA==.Xaos:BAAALgAECgYJCwAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn8qAAIGAAkJzxuRCwAxAgAGAAkJzxuRCwAxAgAAAA==.',
Yo='Yonst:BAABLgAFFH8FAAICAAMJxQzyCwDOAAACAAMJxQzyCwDOAAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAAALgAECgYJDQAAAA==.Zeref:BAAALgADCgUJBgABLgAECgkJKgABAP8iAA==.Zethlahr:BAABLgAECn8mAAMSAAkJ1xvLAwB2AgASAAkJ1xvLAwB2AgACAAQJow2gUgDtAAAAAA==.',
Zo='Zoros:BAAALgAECgIJBAAAAA==.',
Zy='Zytheri:BAAALgADCgEJAQAAAA==.',
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

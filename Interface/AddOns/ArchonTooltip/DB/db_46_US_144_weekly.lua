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

local lookup = {'Mage-Frost','DemonHunter-Devourer','Druid-Balance','Evoker-Augmentation','Evoker-Preservation','Priest-Shadow','Priest-Discipline','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Priest-Holy','Paladin-Holy','Monk-Brewmaster','Rogue-Assassination','Hunter-Survival','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Paladin-Protection','Druid-Feral','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abdervoke:BAAALgAECgYJEQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aethos:BAAALgAECgkJBQAAAA==.',
Al='Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8aAAIBAAgJhx98FwAhAgABAAgJhx98FwAhAgAAAA==.Alistus:BAABLgAECn8hAAICAAgJZyR7AgDjAgACAAgJZyR7AgDjAgAAAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgEJAQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn8VAAIDAAYJxArAIwDjAAADAAYJxArAIwDjAAAAAA==.',
Ar='Arcanegarm:BAAALgAECgYJDwAAAA==.Archeyois:BAABLgAECn8YAAMEAAgJbwoKFgBOAQAEAAgJbwoKFgBOAQAFAAUJhQIJNwCzAAAAAA==.Armitage:BAAALgAECggJDwAAAA==.Arthonos:BAABLgAECn8pAAMGAAkJmRHjBwAIAgAGAAkJmRHjBwAIAgAHAAgJ5AUVGQAgAQAAAA==.Arugall:BAAALgADCgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgUJBQAAAA==.',
Ay='Ayraa:BAAALgADCgMJAwAAAA==.',
Az='Azerphage:BAAALgAECgUJCAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgMJBAAAAA==.Azzog:BAAALgAECgEJAgAAAA==.',
Ba='Baindyn:BAAALgAECgMJBAAAAA==.Barator:BAAALgAECgIJAgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJCwAAAA==.',
Bl='Blackröse:BAAALgAECgYJEAAAAA==.Bladebane:BAAALgAECgcJEwAAAA==.Blksunshine:BAAALgAECgIJAgAAAA==.',
Bo='Bolash:BAAALgAECgQJCAAAAA==.Bort:BAAALgAECgEJAgAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgMJBAAAAA==.',
Bu='Bulvhine:BAAALgAECgYJDwAAAA==.',
Ca='Camford:BAAALgAECgcJCAAAAA==.Cantatrix:BAAALgADCgcJHwAAAA==.Capslok:BAAALgAECgQJBAAAAA==.Captinmeat:BAAALgAECgEJAQAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.',
Ce='Cecilx:BAAALgAECgYJEgAAAA==.Cellybelleri:BAAALgADCgUJBQAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chimerax:BAABLgAECn8eAAMIAAgJhx8AAgCwAgAIAAcJBiMAAgCwAgAJAAcJWxRFWQDlAAAAAA==.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIKAAgJKwbUUgAVAQAKAAgJKwbUUgAVAQAAAA==.Chronic:BAAALgAECgEJAgAAAA==.Chully:BAABLgAECn8lAAMCAAkJdxm1CgAwAgACAAkJdxm1CgAwAgALAAMJiATHWQB9AAAAAA==.',
Cl='Clairíty:BAAALgAECgUJCQAAAA==.Clarky:BAAALgAECgMJAwAAAA==.Click:BAABLgAECn8ZAAIMAAcJCw7pKQBuAQAMAAcJCw7pKQBuAQAAAA==.Cloutfarmer:BAABLgAECn8tAAMMAAkJjSILAQA1AwAMAAkJjSILAQA1AwANAAYJShvhKADgAQAAAA==.',
Co='Comadore:BAABLgAECn8aAAIKAAcJMhzXOABAAgAKAAcJMhzXOABAAgAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEALgAECgkJEAABLgADCgYJBgAOAAAAAA==.',
Cy='Cylithina:BAAALgAECgMJBAAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAgAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deathslead:BAAALgAECgUJBQAAAA==.Decrepe:BAABLgAECn8tAAIPAAkJXB1SCQB2AgAPAAkJXB1SCQB2AgAAAA==.Delph:BAAALgAECgcJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Discostar:BAABLgAECn8ZAAIPAAcJHxVHIwBoAQAPAAcJHxVHIwBoAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAcJEwAQACUgAA==.',
Do='Dominicm:BAAALgAECgYJEQAAAA==.',
Dr='Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgIJAgAAAA==.Druth:BAABLgAECn8kAAIRAAgJzx2gBQAAAgARAAgJzx2gBQAAAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgMJBAAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einark:BAABLgAECn8VAAMSAAYJSyGhCgAAAgASAAYJSyGhCgAAAgATAAEJNBbReAA5AAAAAA==.',
El='Eldrond:BAAALgAECgMJBAAAAA==.Elinis:BAAALgADCgMJAwAAAA==.',
En='Ennauríon:BAAALgAECgQJBAAAAA==.Entropy:BAEALgADCgcJDwABLgAECgYJFAAUAIcWAA==.',
Er='Eridor:BAAALgAECgYJCwAAAA==.',
Ex='Exek:BAABLgAECn8VAAMVAAYJowqRUQDxAAAVAAYJowqRUQDxAAAGAAMJnQJdNQBhAAAAAA==.',
Fa='Fabaztard:BAAALgAECgYJCgAAAA==.Faline:BAABLgAECn8eAAIPAAgJ5glJKABGAQAPAAgJ5glJKABGAQAAAA==.',
Fe='Felgetabouit:BAABLgAECn8eAAICAAgJnBfLNAAlAgACAAgJnBfLNAAlAgAAAA==.Fenrakar:BAAALgAECgEJAQAAAA==.Feywynn:BAAALgAECggJBgAAAA==.',
Fi='Fights:BAABLgAECn8fAAIWAAgJ2B1pBACxAgAWAAgJ2B1pBACxAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJBgAAAA==.Foxknight:BAAALgAECgMJBAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAgAAAA==.Franksnbeans:BAAALgAECgEJAQABLgAECgYJDgAOAAAAAA==.',
Ft='Ftx:BAABLgAECn8fAAMXAAgJuh+sDQC4AgAXAAgJlR+sDQC4AgATAAQJ2hm3RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8oAAIKAAkJ9RmEDgBNAgAKAAkJ9RmEDgBNAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaidan:BAACLgAFFH8HAAIDAAQJ/glNDQAkAQADAAQJ/glNDQAkAQAuAAQKfx0AAgMACQk/FqwSAIECAAMACQk/FqwSAIECAAAA.Gameslayer:BAAALgAECgcJEwAAAA==.Gankzilla:BAABLgAECn8eAAMYAAgJvRphCQCqAQAQAAYJ4RfTJQDKAQAYAAUJxxthCQCqAQAAAA==.Gatanikaz:BAAALgAECgEJAQAAAA==.',
Gh='Ghalumvhar:BAAALgAECgUJCQAAAA==.Ghrìmm:BAABLgAECn8XAAMMAAgJvg6WHQCuAQAMAAgJvg6WHQCuAQANAAEJ1gaPJAArAAAAAA==.',
Gi='Gila:BAAALgAECgEJAgAAAA==.Gingasorrow:BAAALgAECgYJEgAAAA==.Gizzle:BAABLgAECn8cAAIKAAcJShk8TgD4AQAKAAcJShk8TgD4AQAAAA==.',
Gr='Greekfire:BAABLgAECn8YAAIWAAgJ3yE6GwA7AgAWAAgJ3yE6GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8dAAIMAAcJiiF5HwBIAgAMAAcJiiF5HwBIAgAAAA==.',
Ha='Hanjha:BAABLgAECn8XAAMZAAcJcBIqDQCMAQAZAAYJcBIqDQCMAQAMAAEJAAA3zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJDAAOAAAAAA==.Helldozer:BAABLgAECn8dAAIaAAcJ/BD4GQBDAQAaAAcJ/BD4GQBDAQAAAA==.',
Ho='Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJAQAAAA==.',
Hw='Hwore:BAAALgADCggJCAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCQAOAAAAAA==.Hypnocide:BAEBLgAECn8UAAICAAYJAw5TQgDfAAACAAYJAw5TQgDfAAAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
['Hü']='Hüngry:BAABLgAECn8fAAIQAAgJaByvBQAkAgAQAAgJaByvBQAkAgAAAA==.',
Ib='Ibuki:BAAALgAECgQJBAABLgAECggJHwAWABkIAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Il='Illandren:BAAALgAFFAIJAgAAAA==.',
Im='Impsane:BAAALgADCgkJCQAAAA==.',
In='Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8WAAIBAAYJqQfYdQDrAAABAAYJqQfYdQDrAAAAAA==.Innøminate:BAAALgAECgUJBQABLgAECgYJEAAOAAAAAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQYAAgJhxrDAQAqAgAYAAgJwRnDAQAqAgAQAAUJoxxQMwBwAQAbAAQJjg9mCQDZAAAAAA==.',
Is='Isadorah:BAAALgADCgUJBQAAAA==.Isekai:BAAALgAECgEJAQAAAA==.Issadruiid:BAAALgADCgYJBgAAAA==.',
Ja='Jaxxa:BAAALgAECgYJEgAAAA==.',
Je='Jeddiah:BAAALgAECgYJEwAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAAALgAECgQJBwAAAA==.',
Jp='Jpank:BAAALgAECgEJAQAAAA==.',
Ju='Jubei:BAAALgAFFAIJAgAAAA==.Judis:BAABLgAECn8uAAIYAAcJdRaYAwCwAQAYAAcJdRaYAwCwAQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAAALgAECggJEQAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgYJCQAAAA==.Kanajotoma:BAAALgAECgMJBAAAAA==.Karlai:BAABLgAECn8ZAAIcAAcJgRfkBAAAAgAcAAcJgRfkBAAAAgABLgAFFAQJBwADAP4JAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keleena:BAEBLgAECn8VAAIWAAYJix5EDgD3AQAWAAYJix5EDgD3AQAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Ki='Kinst:BAABLgAECn8VAAMNAAYJzRGYPwBbAQANAAYJKBGYPwBbAQAMAAYJAgnsSAD3AAAAAA==.Kisäi:BAABLgAECn8hAAICAAkJzxw1DQAQAgACAAkJzxw1DQAQAgAAAA==.Kitanyia:BAAALgAECgYJDQAAAA==.Kittiy:BAABLgAECn8UAAMPAAYJaQUHQQDMAAAPAAYJaQUHQQDMAAADAAMJOAFNhAAsAAAAAA==.',
Ko='Kordelia:BAABLgAECn8VAAIBAAgJNxvKEwA8AgABAAgJNxvKEwA8AgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAAALgAECgYJDwAAAA==.',
La='Lamanira:BAAALgAECgIJAgAAAA==.Lancier:BAAALgAECgIJAgAAAA==.',
Le='Lecleme:BAAALgAECgcJEwAAAA==.Lejend:BAABLgAECn8cAAMdAAYJsyMIBAAIAgAdAAYJsyMIBAAIAgAeAAMJfRWrfwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgADCgkJDwAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAEAOYLAA==.Lockheéd:BAAALgAECgEJAQAAAA==.Lonelyhearts:BAAALgAECgYJEAAAAA==.Lonestar:BAAALgAECgYJCgAAAA==.Lonestarr:BAAALgAECgQJCQAAAA==.',
Lu='Lumiya:BAABLgAECn8pAAIVAAkJ2g1SEQCVAQAVAAkJ2g1SEQCVAQAAAA==.',
Ly='Lytol:BAAALgAECgYJEgAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAECgEJAQAOAAAAAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maeple:BAABLgAECn8UAAIVAAcJPCCvBACDAgAVAAcJPCCvBACDAgAAAA==.Magikin:BAAALgADCgYJBgAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8IAAMZAAUJVB2UAQCRAQAZAAQJhiOUAQCRAQANAAEJjAShJABVAAAuAAQKfxYAAxkABwlVJFsEANQCABkABwn6I1sEANQCAA0AAQksI+52AGMAAAEuAAUUBwkZAAEAIyQA.',
Me='Mechagnome:BAABLgAECn8oAAMTAAkJ/R5lAQDvAgATAAkJ/R5lAQDvAgASAAgJCQQEOgAAAQAAAA==.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMKAAYJkRbKegCEAQAKAAYJEhbKegCEAQAfAAQJSQkhGQCaAAAAAA==.Meigna:BAABLgAECn8gAAIGAAcJshclDAC+AQAGAAcJshclDAC+AQAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8VAAIgAAUJUB+5AACOAQAgAAUJUB+5AACOAQAuAAQKfyIAAyAABwlnJlYDAAMDACAABwlnJlYDAAMDACEAAwmFINUKABYBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgAECgQJBAAAAA==.Merelandra:BAAALgADCgQJBAAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgEJAgAAAA==.Mithrandir:BAAALgAECgkJBwAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAAALgAECggJEAAAAA==.',
Mo='Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgUJCQAAAA==.Mushuwoonter:BAAALgAECgEJAQAAAA==.Muztang:BAAALgAECgcJEgAAAA==.',
Mw='Mwmmwmm:BAAALgAECgMJAwAAAA==.',
My='Mythandwel:BAAALgAECgYJDQAAAA==.',
['Mä']='Mäddiey:BAAALgADCgIJAgAAAA==.',
['Mô']='Mônkii:BAABLgAECn8tAAIXAAkJKCR9AABGAwAXAAkJKCR9AABGAwAAAA==.',
Na='Nace:BAABLgAECn8iAAIQAAkJPBMkBwAAAgAQAAkJPBMkBwAAAgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgADCgQJBAAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAABLgAECn8VAAMKAAgJRwiKkABbAQAKAAgJdgaKkABbAQAfAAIJ7w5hKAAuAAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECgcJCwAAAA==.Nikiso:BAAALgADCgQJBAAAAA==.',
No='Nocainus:BAABLgAECn8dAAIiAAcJjBrTBwCfAQAiAAcJjBrTBwCfAQAAAA==.Nosehole:BAAALgAECgYJDwAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAAALgAECgYJEAAAAA==.',
Ob='Obsidia:BAABLgAECn8UAAIJAAcJ7QjDVADyAAAJAAcJ7QjDVADyAAAAAA==.',
Oc='Octopusprime:BAAALgAECgkJDgAAAA==.',
Om='Omelette:BAAALgAECgUJCwAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgMJBAAOAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAIBAAkJtCJiBwCRAwABAAkJtCJiBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgIJBAAAAA==.Orangutan:BAAALgAECgMJBAAAAA==.Oriigami:BAAALgAECgMJBQAAAA==.Orinoheal:BAAALgADCgUJBQAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgMJBAAAAA==.Pewpëw:BAAALgADCgkJDQAAAA==.',
Ph='Phoelar:BAAALgADCgMJBAAAAA==.Phuumyn:BAABLgAECn8cAAITAAcJYh81BgAsAgATAAcJYh81BgAsAgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8RAAIBAAUJShQKDQCzAQABAAUJShQKDQCzAQAuAAQKfx4AAgEACAnPIt8cAAIDAAEACAnPIt8cAAIDAAAA.Piccopew:BAAALgADCgcJEQABLgAFFAUJEQABAEoUAA==.Pichus:BAAALgAECgEJAQAAAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAECgMJAwABLgAFFAMJCQANAIAZAA==.Piickles:BAACLgAFFH8TAAMVAAUJxA+wBQAoAQAVAAQJLhKwBQAoAQAHAAQJEwdtDgAnAQAuAAQKfx8AAhUABwndIuALAJMCABUABwndIuALAJMCAAAA.Pinkcanibus:BAAALgAECgYJDAAAAA==.Pity:BAAALgAECgYJBwAAAA==.',
Pl='Plutø:BAABLgAECn8cAAMiAAgJ4hsKDABRAgAiAAcJaB4KDABRAgAjAAgJvwzzLACHAQAAAA==.',
Po='Polylocks:BAAALgADCgQJBAABLgAECgIJAgAOAAAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAEBLgAECn8UAAIUAAYJhxbgBwB/AQAUAAYJhxbgBwB/AQAAAA==.Promethius:BAAALgAECgcJCQABLgAECgkJBwAOAAAAAA==.Protein:BAABLgAECn8aAAIeAAYJ1hasGABrAQAeAAYJ1hasGABrAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCQAOAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn8bAAIPAAgJ0hfKDgAhAgAPAAgJ0hfKDgAhAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECgIJAgAOAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAABLgAECn8hAAIVAAgJsCMnBAASAwAVAAgJsCMnBAASAwAAAA==.',
Ra='Raelynn:BAABLgAECn8dAAIVAAcJhxRoFABvAQAVAAcJhxRoFABvAQAAAA==.Raevenhart:BAABLgAECn8aAAINAAgJihSrJAD/AQANAAgJihSrJAD/AQAAAA==.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCgcJBwAAAA==.Raymond:BAAALgADCgcJBwAAAA==.',
Re='Rebarbative:BAAALgAECgcJEwAAAA==.Redvex:BAABLgAECn8xAAQJAAkJsyQnAQBMAwAJAAkJUyQnAQBMAwAkAAUJMSCLEgC3AQAIAAIJcSPpHwBzAAAAAA==.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8YAAMKAAcJHxCKRgA2AQAKAAcJkQqKRgA2AQAfAAUJfBXpHQAaAQAAAA==.Resjamyn:BAAALgADCgEJAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8eAAIWAAgJlxcEDAAXAgAWAAgJlxcEDAAXAgAAAA==.',
Rh='Rhedman:BAAALgAECgUJCQAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgIJAgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJCAAAAA==.Rotyr:BAAALgAECgYJDwAAAA==.',
Ru='Ruana:BAEALgAECgMJBAAAAA==.Rubyrazor:BAAALgAECgEJAQAAAA==.',
Sa='Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgEJAQAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAAALgAECgYJDQAAAA==.Scubbs:BAABLgAECn8eAAIlAAgJLRZKIgARAgAlAAgJLRZKIgARAgAAAA==.Scubbsboo:BAAALgAECgQJBAABLgAECggJHgAlAC0WAA==.',
Se='Servantes:BAABLgAECn8aAAIPAAcJbQwoMwANAQAPAAcJbQwoMwANAQAAAA==.',
Sh='Shackleford:BAABLgAECn8XAAMHAAcJFx/iEQAnAgAHAAcJFx/iEQAnAgAVAAEJMRiaeQBCAAAAAA==.Shamwõwz:BAAALgAECgcJBwAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECgEJAQAAAA==.Shotya:BAABLgAECn8dAAIMAAcJdwcfOQAuAQAMAAcJdwcfOQAuAQAAAA==.',
Si='Siath:BAABLgAECn8UAAMEAAgJ5gvvFgBGAQAEAAgJ5gvvFgBGAQAmAAIJ6gg1PQA5AAAAAA==.Sixthknight:BAAALgADCgcJGQAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8aAAIWAAcJ9SUhAgAAAwAWAAcJ9SUhAgAAAwAAAA==.',
Sn='Snarkypony:BAAALgAECgIJAgAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCQAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorsere:BAABLgAECn8UAAIJAAYJ9hUYbACJAQAJAAYJ9hUYbACJAQAAAA==.',
Sp='Spcecialk:BAAALgAECgYJDwAAAA==.Specialk:BAABLgAECn8nAAMaAAcJsg6vHQApAQAaAAcJsg6vHQApAQAlAAEJsAHdbAAgAAAAAA==.',
Sq='Squallie:BAAALgAECgYJBgAAAA==.',
St='Steamedhams:BAAALgAECgMJAwABLgAECgUJCAAOAAAAAA==.Stromm:BAABLgAECn8UAAICAAgJ+hXcGACiAQACAAgJ+hXcGACiAQABLgAFFAQJBwADAP4JAA==.',
Su='Sundorei:BAAALgADCgEJAQAAAA==.',
Ta='Tahoe:BAAALgADCgIJAgAAAA==.Talshekar:BAABLgAECn8WAAImAAcJ5wZ3BwAVAQAmAAcJ5wZ3BwAVAQAAAA==.',
Te='Teiana:BAABLgAECn8lAAIKAAkJyB6qBQC/AgAKAAkJyB6qBQC/AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAAALgAECgYJCwAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAABLgAECn8YAAIPAAgJuxR9HwCEAQAPAAgJuxR9HwCEAQAAAA==.Thordak:BAAALgADCggJDQAAAA==.',
Ti='Timbuktoo:BAAALgAECgEJAQAAAA==.Tinypoop:BAABLgAECn8VAAIBAAYJTxXORgBaAQABAAYJTxXORgBaAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAAALgAECgMJCAAAAA==.Tors:BAABLgAECn8rAAIDAAgJSxUFDQC8AQADAAgJSxUFDQC8AQAAAA==.',
Tr='Trogdore:BAAALgAECgQJBAAAAA==.Trollololo:BAABLgAECn8dAAMBAAcJEwuuUABAAQABAAcJEwuuUABAAQAnAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8bAAIBAAgJXRioGgAMAgABAAgJXRioGgAMAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgIJAgAAAA==.',
Tt='Ttaartt:BAACLgAFFH8VAAIFAAUJSBG3BwBhAQAFAAUJSBG3BwBhAQAuAAQKfx0AAgUABwmqGecSABICAAUABwmqGecSABICAAAA.',
Ty='Typh:BAACLgAFFH8FAAIYAAMJURWJAgAVAQAYAAMJURWJAgAVAQAuAAQKfy0AAhgACQksIi0AADwDABgACQksIi0AADwDAAAA.Tyrone:BAAALgAECgcJEwAAAA==.',
Uf='Uffish:BAAALgADCgUJBgAAAQ==.',
Ug='Uglymagi:BAAALgAECgEJAQAAAA==.',
Un='Undeaddemon:BAABLgAECn8fAAQJAAkJ/xzFDQA+AgAJAAgJ/xzFDQA+AgAIAAIJ/QgQHwB4AAAkAAEJkAa+eAAqAAAAAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJHwAJAP8cAA==.Undeadscaly:BAAALgAECgUJBQABLgAECgkJHwAJAP8cAA==.Undignified:BAAALgAECgYJEwAAAA==.Unholysixth:BAAALgADCgYJBgAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgMJBAAAAA==.',
Vi='Vidikan:BAAALgAECgMJBAAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAABLgAECn8fAAIlAAgJ5BXtDwD4AQAlAAgJ5BXtDwD4AQAAAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8YAAIlAAcJYhsbFwCtAQAlAAcJYhsbFwCtAQAAAA==.',
Wa='Waldón:BAABLgAECn8dAAInAAgJwghGAwAoAQAnAAgJwghGAwAoAQAAAA==.',
We='Werrik:BAAALgAECgYJEQABLgAFFAIJAgAOAAAAAA==.',
Wi='Wildsoul:BAABLgAECn8dAAIlAAcJPxJ5GwCIAQAlAAcJPxJ5GwCIAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgMJBAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAUJFQAgAFAfAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgYJEAAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.',
Xi='Xilphira:BAAALgAECgEJAQAAAA==.',
Xl='Xlithz:BAABLgAECn8iAAMdAAgJSRTpBQDFAQAdAAgJOBLpBQDFAQAeAAYJURfHRACRAQAAAA==.',
['Xí']='Xílo:BAEBLgAECn8cAAMCAAcJpxcUHACLAQACAAcJpxcUHACLAQALAAEJ8QeBMwAzAAAAAA==.',
Yl='Ylene:BAAALgAECgYJCQAAAA==.',
Yo='Yoink:BAABLgAECn8kAAIjAAkJDB8FBQDWAgAjAAkJDB8FBQDWAgAAAA==.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgADCgkJCQAAAA==.Zarinfur:BAABLgAECn8cAAIgAAgJKxN6BwCEAQAgAAgJKxN6BwCEAQAAAA==.Zazikalestra:BAABLgAECn8bAAQFAAgJDRdVFwDcAQAFAAgJDRdVFwDcAQAEAAQJhQSbTwCPAAAmAAEJAAAdPwAzAAAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgIJAgAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAABLgAECn8bAAMMAAcJzxOSRgCXAQAMAAcJzxOSRgCXAQANAAEJ9QCBmQAbAAAAAA==.Zequill:BAABLgAECn8fAAIRAAgJVSFBAgCKAgARAAgJVSFBAgCKAgAAAA==.Zevsticles:BAABLgAECn8kAAIMAAkJah56BgCQAgAMAAkJah56BgCQAgAAAA==.',
Zh='Zhom:BAACLgAFFH8JAAINAAMJgBlJCAD/AAANAAMJgBlJCAD/AAAuAAQKfywAAg0ACQk9HhsJAA0DAA0ACQk9HhsJAA0DAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn8cAAIoAAcJkgwoCQBYAQAoAAcJkgwoCQBYAQAAAA==.Zorlak:BAAALgAECgQJBwAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAAALgAECgQJBwAAAA==.',
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

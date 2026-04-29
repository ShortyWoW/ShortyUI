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

local lookup = {'Mage-Frost','DemonHunter-Devourer','Priest-Shadow','Priest-Discipline','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Priest-Holy','Paladin-Holy','Monk-Brewmaster','Monk-Windwalker','Druid-Balance','Rogue-Assassination','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Hunter-Survival','Monk-Mistweaver','Druid-Feral','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Paladin-Protection','Shaman-Restoration','Evoker-Devastation','Mage-Fire','Evoker-Preservation','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abdervoke:BAAALgAECgYJCwAAAA==.',
Al='Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8VAAIBAAcJwyGATQBOAgABAAcJwyGATQBOAgAAAA==.Alistus:BAABLgAECn8dAAICAAgJOiPjAwBZAgACAAgJOiPjAwBZAgAAAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgEJAQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAAALgAECgYJDwAAAA==.',
Ar='Arcanegarm:BAAALgAECgYJCwAAAA==.Archeyois:BAAALgAECgcJEAAAAA==.Armitage:BAAALgAECgYJBgAAAA==.Arthonos:BAABLgAECn8gAAMDAAgJvA4VKQCRAQADAAcJvg0VKQCRAQAEAAgJ5AVaCgArAQAAAA==.Arugall:BAAALgADCgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Az='Azerphage:BAAALgAECgMJAwAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgEJAQAAAA==.Azzog:BAAALgAECgEJAgAAAA==.',
Ba='Baindyn:BAAALgAECgMJBAAAAA==.Barator:BAAALgADCgkJFAAAAA==.Bas:BAAALgAECgQJBAAAAA==.',
Bi='Bigwhisky:BAAALgAECgcJCwAAAA==.',
Bl='Blackröse:BAAALgAECgYJCgAAAA==.Bladebane:BAAALgAECgYJEQAAAA==.Blksunshine:BAAALgADCgkJEAAAAA==.',
Bo='Bolash:BAAALgAECgQJBwAAAA==.Bort:BAAALgAECgEJAgAAAA==.',
Br='Bradthomas:BAAALgAECgQJBAAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgMJBAAAAA==.',
Bu='Bulvhine:BAAALgAECgUJBwAAAA==.',
Ca='Camford:BAAALgAECgcJCAAAAA==.Cantatrix:BAAALgADCgcJGQAAAA==.Captinmeat:BAAALgADCgEJAQAAAA==.',
Ce='Cecilx:BAAALgAECgUJDAAAAA==.Cellybelleri:BAAALgADCgUJBQAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chimerax:BAABLgAECn8bAAMFAAgJhx8AAgCwAgAFAAcJBiMAAgCwAgAGAAUJIhB8ngAbAQAAAA==.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIHAAgJKwb5IgAfAQAHAAgJKwb5IgAfAQAAAA==.Chronic:BAAALgADCgkJEAAAAA==.Chully:BAABLgAECn8kAAMCAAgJgxhWCQDdAQACAAgJgxhWCQDdAQAIAAMJiATIWQB9AAAAAA==.',
Cl='Clairíty:BAAALgAECgMJBAAAAA==.Clarky:BAAALgAECgMJAwAAAA==.Click:BAAALgAECgYJEgAAAA==.Cloutfarmer:BAABLgAECn8kAAMJAAgJayGeAwBRAgAJAAcJ4SGeAwBRAgAKAAYJShveKADgAQAAAA==.',
Co='Comadore:BAABLgAECn8YAAIHAAcJ7RveOABAAgAHAAcJ7RveOABAAgAAAA==.',
Cr='Crankshanker:BAAALgADCgUJBQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEALgAECgkJCAABLgADCgYJBgALAAAAAA==.',
Cy='Cylithina:BAAALgAECgMJBAAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAgAAAA==.Dawggbiscuit:BAAALgAECgEJAQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Decrepe:BAABLgAECn8kAAIMAAgJFB6zFACQAgAMAAgJFB6zFACQAgAAAA==.Delph:BAAALgAECgcJDgAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Discostar:BAAALgAECgYJEQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAYJEQANAKsgAA==.',
Do='Dominicm:BAAALgAECgYJEQAAAA==.',
Dr='Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgADCgkJFAAAAA==.Druth:BAABLgAECn8dAAIOAAgJURrqCgBiAgAOAAgJURrqCgBiAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgMJBAAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einark:BAAALgAECgYJDwAAAA==.',
El='Eldrond:BAAALgAECgMJBAAAAA==.',
En='Ennauríon:BAAALgAECgQJBAAAAA==.Entropy:BAEALgADCgcJDgABLgAECgYJEAALAAAAAA==.',
Er='Eridor:BAAALgAECgYJCAAAAA==.',
Ex='Exek:BAABLgAECn8UAAMPAAUJ5wuIUQDxAAAPAAUJ5wuIUQDxAAADAAQJYgLwFwB+AAAAAA==.',
Fa='Fabaztard:BAAALgAECgQJBgAAAA==.Faline:BAABLgAECn8WAAIMAAcJIQn6EwAoAQAMAAcJIQn6EwAoAQAAAA==.',
Fe='Felgetabouit:BAABLgAECn8bAAICAAgJmxfJNAAlAgACAAgJmxfJNAAlAgAAAA==.Fenrakar:BAAALgAECgEJAQAAAA==.Feywynn:BAAALgAECgYJBgAAAA==.',
Fi='Fights:BAABLgAECn8XAAIQAAcJPB5hAwBPAgAQAAcJPB5hAwBPAgAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJBgAAAA==.Foxknight:BAAALgAECgMJBAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.',
Ft='Ftx:BAABLgAECn8fAAMRAAgJuh+rDQC4AgARAAgJlR+rDQC4AgASAAQJ2hm0RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8fAAIHAAgJCRtHCQD2AQAHAAgJCRtHCQD2AQAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaidan:BAABLgAECn8dAAITAAkJPxatEgCBAgATAAkJPxatEgCBAgAAAA==.Gameslayer:BAAALgAECgYJEQAAAA==.Gankzilla:BAABLgAECn8bAAMUAAgJvBpjCQCqAQANAAYJ4RfUJQDKAQAUAAUJxxtjCQCqAQAAAA==.Gatanikaz:BAAALgAECgEJAQAAAA==.',
Gh='Ghalumvhar:BAAALgADCggJDgAAAA==.Ghrìmm:BAAALgAECgcJDwAAAA==.',
Gi='Gila:BAAALgAECgEJAQAAAA==.Gingasorrow:BAAALgAECgUJDAAAAA==.Gizzle:BAABLgAECn8ZAAIHAAcJcxdDTgD4AQAHAAcJcxdDTgD4AQAAAA==.',
Gr='Greekfire:BAABLgAECn8WAAIQAAYJcSM9GwA7AgAQAAYJcSM9GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBQAAAA==.Grunbar:BAABLgAECn8cAAIJAAcJiiF/HwBIAgAJAAcJiiF/HwBIAgAAAA==.',
Ha='Hanjha:BAAALgAECgYJEAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJDAALAAAAAA==.Helldozer:BAABLgAECn8WAAIVAAYJ2hCZDwAQAQAVAAYJ2hCZDwAQAQAAAA==.',
Ho='Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJBQAAAA==.',
Hw='Hwore:BAAALgADCggJCAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCQALAAAAAA==.Hypnocide:BAEALgAECgYJDgAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
['Hü']='Hüngry:BAABLgAECn8VAAINAAgJ8BhwEgCJAgANAAgJ8BhwEgCJAgAAAA==.',
Ib='Ibuki:BAAALgADCgkJCQABLgAECggJGwAQALMGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Il='Illandren:BAAALgAECggJCAAAAA==.',
Im='Impsane:BAAALgADCgkJCQAAAA==.',
In='Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAAALgAECgYJEAAAAA==.',
Ir='Irv:BAABLgAECn8WAAQUAAgJhxqOAAA+AgAUAAgJwRmOAAA+AgANAAUJoxxVMwBwAQAWAAQJjg9mCQDZAAAAAA==.',
Is='Isadorah:BAAALgADCgUJBQAAAA==.Issadruiid:BAAALgADCgYJBgAAAA==.',
Ja='Jaxxa:BAAALgAECgYJEgAAAA==.',
Je='Jeddiah:BAAALgAECgYJDQAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAAALgAECgQJBAAAAA==.',
Jp='Jpank:BAAALgADCgQJBAAAAA==.',
Ju='Jubei:BAAALgAFFAEJAQAAAA==.Judis:BAABLgAECn8jAAIUAAYJUhfxAgBbAQAUAAYJUhfxAgBbAQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.',
Ka='Kainel:BAAALgADCgkJEAAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAAALgAECggJDwAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kaliscales:BAAALgAECgQJBAAAAA==.Kamiportal:BAAALgAECgYJCQAAAA==.Kanajotoma:BAAALgAECgMJBAAAAA==.Karlai:BAABLgAECn8ZAAIXAAcJgRfiBAAAAgAXAAcJgRfiBAAAAgABLgAECgkJHQATAD8WAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keleena:BAEALgAECgYJDwAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Ki='Kinst:BAAALgAECgYJDwAAAA==.Kisäi:BAABLgAECn8aAAICAAkJWhxXIACPAgACAAkJWhxXIACPAgAAAA==.Kitanyia:BAAALgAECgYJDAAAAA==.Kittiy:BAAALgAECgYJDgAAAA==.',
Ko='Kordelia:BAAALgAECgcJDAAAAA==.Korvus:BAAALgAECgYJCgAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgADCggJDgAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAAALgAECgYJCwAAAA==.',
La='Lamanira:BAAALgADCgkJFAAAAA==.Lancier:BAAALgADCgkJDwAAAA==.',
Le='Lecleme:BAAALgAECgcJDgAAAA==.Lejend:BAABLgAECn8WAAMYAAYJISN9AQD/AQAYAAYJISN9AQD/AQAZAAMJfRWkfwC+AAAAAA==.Lenthalis:BAAALgAECgUJCQAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgADCgkJDwAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAaAOYLAA==.Lonelyhearts:BAAALgAECgYJCgAAAA==.Lonestar:BAAALgAECgUJBQAAAA==.Lonestarr:BAAALgAECgQJBwAAAA==.',
Lu='Lumiya:BAABLgAECn8gAAIPAAgJkQ4iCwBEAQAPAAgJkQ4iCwBEAQAAAA==.',
Ly='Lytol:BAAALgAECgYJEgAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAECgcJGwAaAL4bAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maeple:BAAALgAECgYJEgAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAABLgAECn8WAAMbAAcJVSRZBADUAgAbAAcJ+iNZBADUAgAKAAEJLCPndgBjAAABLgAFFAYJFwABAPIkAA==.',
Me='Mechagnome:BAABLgAECn8fAAMSAAgJyRuhAQBPAgASAAgJyRuhAQBPAgAcAAgJCQTEOQAEAQAAAA==.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8WAAIHAAYJEhbRegCEAQAHAAYJEhbRegCEAQAAAA==.Meigna:BAABLgAECn8ZAAIDAAcJaBJHJAC1AQADAAcJaBJHJAC1AQAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8MAAIdAAQJZhldAAB9AQAdAAQJZhldAAB9AQAuAAQKfx8AAh0ABwlnJlYDAAMDAB0ABwlnJlYDAAMDAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgADCgkJEgAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgEJAgAAAA==.Mithrandir:BAAALgAECgkJBAAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAAALgAECggJDgAAAA==.',
Mo='Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgMJBgAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAECgcJGwAaAL4bAA==.Muztang:BAAALgAECgYJCwAAAA==.',
Mw='Mwmmwmm:BAAALgAECgMJAwAAAA==.',
My='Mythandwel:BAAALgAECgYJBwAAAA==.',
['Mä']='Mäddiey:BAAALgADCgIJAgAAAA==.',
['Mô']='Mônkii:BAABLgAECn8kAAIRAAgJtyAoAgA+AgARAAgJtyAoAgA+AgAAAA==.',
Na='Nace:BAABLgAECn8bAAINAAkJMROxGQA2AgANAAkJMROxGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgADCgQJBAAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAAALgAECggJDgAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECgQJBAABLgAECggJGwAPAK8HAA==.',
No='Nocainus:BAABLgAECn8WAAIeAAYJiBSLBwAeAQAeAAYJiBSLBwAeAQAAAA==.Nosehole:BAAALgAECgYJDAAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAAALgAECgYJDQAAAA==.',
Ob='Obsidia:BAAALgAECgYJEwAAAA==.',
Oc='Octopusprime:BAAALgAECgkJDQAAAA==.',
Om='Omelette:BAAALgAECgUJCgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgMJBAALAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAIBAAkJtCJaBwCRAwABAAkJtCJaBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgEJAgAAAA==.Orangutan:BAAALgAECgMJBAAAAA==.Oriigami:BAAALgAECgMJAwAAAA==.Orinoheal:BAAALgADCgUJBQAAAA==.',
Pe='Perilous:BAAALgAECgMJBAAAAA==.Pewpëw:BAAALgADCgkJDQAAAA==.',
Ph='Phoelar:BAAALgADCgMJBAAAAA==.Phuumyn:BAABLgAECn8VAAISAAYJixsHBgCKAQASAAYJixsHBgCKAQAAAA==.',
Pi='Piccoblast:BAACLgAFFH8NAAIBAAUJkBH9DACzAQABAAUJkBH9DACzAQAuAAQKfx4AAgEACAnPItscAAIDAAEACAnPItscAAIDAAAA.Piccopew:BAAALgADCgcJEQABLgAFFAUJDQABAJARAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAECgMJAwAAAA==.Piickles:BAACLgAFFH8MAAIPAAQJLhJOAgAtAQAPAAQJLhJOAgAtAQAuAAQKfx8AAg8ABwndIt4LAJMCAA8ABwndIt4LAJMCAAAA.Pinkcanibus:BAAALgAECgYJDAAAAA==.Pity:BAAALgAECgEJAQAAAA==.',
Pl='Plutø:BAABLgAECn8UAAMeAAcJaB4JDABRAgAeAAcJaB4JDABRAgAfAAYJmwjhswAbAQAAAA==.',
Po='Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAEALgAECgYJEAAAAA==.Promethius:BAAALgAECgcJCQABLgAECgkJBAALAAAAAA==.Protein:BAABLgAECn8UAAIZAAYJRRVpQgCbAQAZAAYJRRVpQgCbAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCQALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAAALgAECgYJEwAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgADCgkJEAALAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAABLgAECn8eAAIPAAgJVCInBAASAwAPAAgJVCInBAASAwAAAA==.',
Ra='Raelynn:BAABLgAECn8WAAIPAAYJ6hXgCgBJAQAPAAYJ6hXgCgBJAQAAAA==.Raevenhart:BAABLgAECn8XAAIKAAgJgBCrJAD/AQAKAAgJgBCrJAD/AQAAAA==.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCgcJBwAAAA==.Raymond:BAAALgADCgcJBwAAAA==.',
Re='Rebarbative:BAAALgAECgYJEQAAAA==.Redvex:BAABLgAECn8pAAQGAAgJsCN7BAA5AgAGAAgJQiN7BAA5AgAgAAUJMSCNEgC3AQAFAAIJcSPqHwBzAAAAAA==.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8WAAMHAAYJpxKlIwAbAQAHAAYJ7wqlIwAbAQAhAAUJfBXoHQAbAQAAAA==.Resjamyn:BAAALgADCgEJAQAAAA==.Rewrew:BAABLgAECn8WAAIQAAcJvRZICADCAQAQAAcJvRZICADCAQAAAA==.',
Rh='Rhedman:BAAALgADCggJDQAAAA==.',
Ri='Ricasti:BAAALgAECgUJBQAAAA==.Rinahrune:BAAALgADCgcJEQAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJCAAAAA==.Rotyr:BAAALgAECgUJCgAAAA==.',
Ru='Ruana:BAEALgAECgMJBAAAAA==.Rubyrazor:BAAALgAECgEJAQAAAA==.',
Sa='Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgEJAQAAAA==.Samesh:BAAALgAECgQJBwAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAAALgAECgYJDAAAAA==.Scubbs:BAABLgAECn8bAAIiAAgJQBVSIgARAgAiAAgJQBVSIgARAgAAAA==.Scubbsboo:BAAALgADCgkJEgABLgAECggJGwAiAEAVAA==.',
Se='Servantes:BAAALgAECgYJEwAAAA==.',
Sh='Shackleford:BAAALgAECgYJEAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shotya:BAABLgAECn8WAAIJAAYJ/wTZbwAYAQAJAAYJ/wTZbwAYAQAAAA==.',
Si='Siath:BAABLgAECn8UAAMaAAgJ5gvhCABaAQAaAAgJ5gvhCABaAQAjAAIJ6ggtPQA5AAAAAA==.Sixthknight:BAAALgADCgcJEgAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAAALgAECgYJEwAAAA==.',
Sn='Snarkypony:BAAALgADCgkJFAAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCQAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorsere:BAAALgAECgYJDgAAAA==.',
Sp='Spcecialk:BAAALgAECgYJDQAAAA==.Specialk:BAABLgAECn8cAAMVAAcJlA4IQQBFAQAVAAcJlA4IQQBFAQAiAAEJsAE4MgAhAAAAAA==.',
Sq='Squallie:BAAALgADCgUJCwAAAA==.',
St='Steamedhams:BAAALgAECgMJAwAAAA==.Stromm:BAAALgAECgcJEQABLgAECgkJHQATAD8WAA==.',
Su='Sundorei:BAAALgADCgEJAQAAAA==.',
Ta='Tahoe:BAAALgADCgIJAgAAAA==.Talshekar:BAAALgAECgYJDwAAAA==.',
Te='Teiana:BAABLgAECn8cAAIHAAkJWBhoKwB2AgAHAAkJWBhoKwB2AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAAALgAECgYJCQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAAALgAECgYJEAAAAA==.Thordak:BAAALgADCggJDQAAAA==.',
Ti='Timbuktoo:BAAALgADCgYJBgAAAA==.Tinypoop:BAAALgAECgYJDQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAAALgAECgMJBQAAAA==.Tors:BAABLgAECn8jAAITAAgJIxPwBwB4AQATAAgJIxPwBwB4AQAAAA==.',
Tr='Trogdore:BAAALgADCgkJEQAAAA==.Trollololo:BAABLgAECn8WAAMBAAYJ9gyCMQADAQABAAYJ9gyCMQADAQAkAAMJ+wfrCgCPAAAAAA==.Troy:BAAALgAECgcJEwAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgADCgkJEAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8MAAIlAAQJCRSFCQBRAQAlAAQJCRSFCQBRAQAuAAQKfx0AAiUABwmqGeoSABICACUABwmqGeoSABICAAAA.',
Ty='Typh:BAABLgAECn8kAAIUAAgJESI+AACfAgAUAAgJESI+AACfAgAAAA==.Tyrone:BAAALgAECgQJDAAAAA==.',
Uf='Uffish:BAAALgADCgUJBgAAAQ==.',
Ug='Uglymagi:BAAALgAECgEJAQAAAA==.',
Un='Undeaddemon:BAABLgAECn8WAAQGAAkJ7BsRSADyAQAGAAgJ7BsRSADyAQAFAAIJ/QgRHwB4AAAgAAEJkAa4eAAqAAAAAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJFgAGAOwbAA==.Undeadscaly:BAAALgAECgUJBQABLgAECgkJFgAGAOwbAA==.Undignified:BAAALgAECgYJDQAAAA==.Unholysixth:BAAALgADCgYJBgAAAA==.Unicornquen:BAAALgADCgcJCAAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgMJBAAAAA==.',
Vi='Vidikan:BAAALgAECgMJBAAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAABLgAECn8XAAIiAAcJWhJCDQBpAQAiAAcJWhJCDQBpAQAAAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8UAAIiAAcJDxfjOACeAQAiAAcJDxfjOACeAQAAAA==.',
Wa='Waldón:BAABLgAECn8VAAIkAAYJ3QqJBgAzAQAkAAYJ3QqJBgAzAQAAAA==.',
We='Werrik:BAAALgAECgYJEAAAAA==.',
Wi='Wildsoul:BAABLgAECn8WAAIiAAYJExRhDAB3AQAiAAYJExRhDAB3AQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgMJBAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAQJDAAdAGYZAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgUJCgAAAA==.',
Xi='Xilphira:BAAALgAECgEJAQAAAA==.',
Xl='Xlithz:BAABLgAECn8aAAMYAAcJ5xQKBQBDAQAZAAYJURfARACRAQAYAAYJFxAKBQBDAQAAAA==.',
['Xí']='Xílo:BAEBLgAECn8VAAMCAAYJ9BajXgCFAQACAAYJ9BajXgCFAQAIAAEJ8Qc0FwA1AAAAAA==.',
Yl='Ylene:BAAALgAECgMJAwAAAA==.',
Yo='Yoink:BAABLgAECn8bAAIfAAgJBhnDBwADAgAfAAgJBhnDBwADAgAAAA==.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinfur:BAABLgAECn8UAAIdAAYJTBgUEACtAQAdAAYJTBgUEACtAQAAAA==.Zazikalestra:BAABLgAECn8bAAQlAAgJDRcaBQBhAQAlAAgJDRcaBQBhAQAaAAQJhQSWTwCPAAAjAAEJAAAVPwAzAAAAAA==.',
Ze='Zedrin:BAAALgAECgEJAQAAAA==.Zein:BAAALgADCgkJFAAAAA==.Zente:BAABLgAECn8YAAMJAAYJ3BWcRgCXAQAJAAYJ3BWcRgCXAQAKAAEJ9QB+mQAbAAAAAA==.Zequill:BAABLgAECn8XAAIOAAcJDyEkAgAHAgAOAAcJDyEkAgAHAgAAAA==.Zevsticles:BAABLgAECn8bAAIJAAkJlRoXFwCAAgAJAAkJlRoXFwCAAgAAAA==.',
Zh='Zhom:BAACLgAFFH8JAAIKAAMJgBmHAgAbAQAKAAMJgBmHAgAbAQAuAAQKfywAAgoACQk9HhYJAA0DAAoACQk9HhYJAA0DAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJBwAAAA==.Zooj:BAABLgAECn8VAAImAAYJPAvXBgAUAQAmAAYJPAvXBgAUAQAAAA==.Zorlak:BAAALgAECgQJBQAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAAALgAECgMJBgAAAA==.',
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

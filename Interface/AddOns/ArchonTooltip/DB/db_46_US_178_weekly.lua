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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Paladin-Retribution','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','Rogue-Subtlety','Priest-Shadow','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Monk-Mistweaver','Monk-Brewmaster','Druid-Balance','DemonHunter-Vengeance','Shaman-Restoration','Warrior-Arms','Shaman-Elemental','Warlock-Demonology','Unknown-Unknown','Mage-Arcane','Warlock-Destruction','Paladin-Protection','DeathKnight-Unholy',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgADCgkJDAAAAA==.',
Ah='Ahote:BAABLgAECn8XAAIBAAYJUyBHAQDjAQABAAYJUyBHAQDjAQAAAA==.',
Ai='Airrows:BAABLgAECn8fAAMCAAgJQx+cEAC0AgACAAcJbiOcEAC0AgADAAQJIRhoGAD4AAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgUJBgAAAA==.Alurea:BAABLgAECn8XAAIEAAYJ4gr1OgDnAAAEAAYJ4gr1OgDnAAAAAA==.',
An='Ang:BAABLgAECn8dAAIFAAgJixLQLAABAgAFAAgJixLQLAABAgAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.',
Ap='Apathy:BAABLgAECn8oAAIGAAgJfRsfBwBuAgAGAAgJfRsfBwBuAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIGAAcJLyJ2GABPAgAGAAcJLyJ2GABPAgAAAA==.Argonäut:BAABLgAECn8jAAIHAAgJIiQ2AQDkAgAHAAgJIiQ2AQDkAgAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8eAAIIAAcJ5g+OQABtAQAIAAcJ5g+OQABtAQAAAA==.Astragos:BAABLgAECn8ZAAQJAAcJVxTJBAByAQAJAAYJ/hfJBAByAQAKAAYJaA82OAAVAQALAAIJdB6zFACyAAAAAA==.',
Az='Azagorod:BAAALgAECgEJAQAAAA==.',
Ba='Baern:BAABLgAECn8YAAIMAAYJCCI/BgDtAQAMAAYJCCI/BgDtAQAAAA==.',
Be='Beaconstrips:BAABLgAECn8pAAMGAAgJixSHDwDpAQAGAAcJFBeHDwDpAQANAAYJ1AkGmAB1AAAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BnQLgC6AQACAAYJ6BnQLgC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8XAAIOAAYJpRmRDwCDAQAOAAYJpRmRDwCDAQAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8ZAAIPAAcJlQseBABjAQAPAAcJlQseBABjAQAAAA==.',
Bo='Boney:BAAALgAECgEJAgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn8nAAIIAAgJNR2IFQAvAgAIAAgJNR2IFQAvAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8GAAIQAAMJjQ13CQDPAAAQAAMJjQ13CQDPAAABLgAFFAUJEQAIAPQYAA==.',
Ca='Caiki:BAAALgAECgQJBAAAAA==.Catelaya:BAABLgAECn8nAAIRAAkJmxWMDAA7AgARAAkJmxWMDAA7AgAAAA==.Cathulu:BAAALgADCgYJBgAAAA==.',
Ce='Celithatha:BAAALgAECggJDQAAAA==.',
Ch='Chaness:BAABLgAECn8ZAAINAAgJfRpfJgCqAQANAAgJfRpfJgCqAQAAAA==.Chexk:BAABLgAECn8fAAISAAgJyRiXBQAmAgASAAgJyRiXBQAmAgAAAA==.Chillfu:BAABLgAECn8WAAIOAAYJAhstEAB7AQAOAAYJAhstEAB7AQAAAA==.Chixnu:BAAALgADCgkJCQAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Cryblood:BAABLgAECn8XAAITAAYJzQ4mHAAcAQATAAYJzQ4mHAAcAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn8dAAIUAAgJShc7BQC6AQAUAAgJShc7BQC6AQAAAA==.',
Cy='Cynthic:BAAALgAECgQJCQAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Dalynn:BAAALgAECgYJEAAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgADCggJEAAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8mAAIMAAgJ+B2VBAAiAgAMAAgJ+B2VBAAiAgAAAA==.Djiink:BAAALgAECggJEwAAAA==.',
Do='Doomlocke:BAAALgADCgEJAQAAAA==.',
Dr='Drottningu:BAABLgAECn8cAAIVAAgJtgt+KABFAQAVAAgJtgt+KABFAQAAAA==.',
Du='Dunkie:BAAALgAECgQJCAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgADCgQJBAAAAA==.',
Em='Em:BAABLgAECn8VAAQWAAcJKRw/DwBKAgAWAAcJKRw/DwBKAgATAAQJUBFSRgDMAAAQAAEJNQ0gggAvAAAAAA==.',
Er='Eraline:BAABLgAECn8nAAIXAAgJORMUDgDFAQAXAAgJORMUDgDFAQAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAAALgAECgcJEAAAAA==.',
Fl='Flaciddream:BAAALgAECgQJBAAAAA==.',
Fr='Frostblood:BAAALgAECgEJAwAAAA==.Froststorm:BAAALgAECgEJAQAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8XAAIYAAYJpBuLAgDGAQAYAAYJpBuLAgDGAQAuAAQKfxoAAhgACAmDJPwFACgDABgACAmDJPwFACgDAAAA.',
Ge='Genocya:BAAALgAECgYJEAAAAA==.',
Gh='Ghost:BAAALgAECggJEQAAAA==.',
Gi='Gilden:BAAALgAECgQJCAAAAA==.',
Gn='Gnot:BAAALgADCgcJGQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8kAAMEAAgJABy7HQBQAgAEAAcJ8Bu7HQBQAgAZAAUJWRO4FwBBAQAAAA==.',
['Gò']='Gòddess:BAAALgAECgYJBwAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8kAAMRAAgJQw1EHwClAQARAAgJMA1EHwClAQACAAcJHAVfTgAWAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAAALgAECgYJCQAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn8rAAILAAcJ/hPlBwCwAQALAAcJ/hPlBwCwAQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAAALgAECgQJCAAAAA==.',
Iw='Iwantmore:BAABLgAECn8pAAMaAAkJVCRXAAD5AgAHAAgJrCQ2AwBSAwAaAAkJ3CBXAAD5AgAAAA==.',
Iy='Iyotanka:BAAALgAECgEJAQAAAA==.',
Ju='Juicebox:BAAALgAECgYJDwABLgAECggJIgAYABkLAA==.Juuzau:BAAALgAECgYJBwAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAABLgAECn8eAAIWAAgJ/xB9CgDmAQAWAAgJ/xB9CgDmAQAAAA==.Kasey:BAAALgAECgIJAgAAAA==.Katheryn:BAABLgAECn8bAAINAAcJCyFnEQAwAgANAAcJCyFnEQAwAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJGwANAAshAA==.Katie:BAAALgAECgcJDQABLgAFFAcJHAAbAD8lAA==.',
Ke='Kealey:BAAALgAECgUJBgAAAA==.Kessik:BAABLgAECn8ZAAMFAAgJmBD3HgA7AQAFAAgJSBD3HgA7AQAcAAQJ1gqvGgClAAAAAA==.',
Kh='Khaless:BAAALgAECgQJCAAAAA==.',
Ki='Kiamors:BAABLgAECn8XAAMdAAYJfwHnOgB+AAAdAAYJfwHnOgB+AAAbAAEJdwHjqwAcAAAAAA==.Kieru:BAAALgADCgkJCQABLgAECggJKAAGAH0bAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAAALgAECgYJDwAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.',
Le='Leda:BAAALgAECgEJAQAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.',
Li='Liandra:BAAALgAECgYJEQAAAA==.Lightfighter:BAAALgAECgYJDAAAAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lilkiwi:BAAALgAECgQJCAAAAA==.',
Lo='Louhfu:BAAALgAECgYJDAAAAA==.',
Lu='Lunchbox:BAABLgAECn8UAAIDAAYJRgQHGQDxAAADAAYJRgQHGQDxAAAAAA==.Lunecy:BAABLgAECn8YAAQDAAgJwhwiBQArAgADAAgJVRsiBQArAgARAAUJdSCDQwCiAQACAAEJaQcWjwAsAAAAAA==.',
Ma='Magul:BAABLgAECn8rAAIIAAgJuRntVwAxAgAIAAgJuRntVwAxAgAAAA==.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgUJBgABLgAFFAUJEQAIAPQYAA==.',
Mc='Mcpheex:BAAALgAECgcJDQAAAA==.',
Me='Medie:BAABLgAECn8oAAMQAAgJ7CD8BgDdAgAQAAgJ7CD8BgDdAgATAAQJ1wugKwCjAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8iAAMNAAkJEhrrCACOAgANAAkJEhrrCACOAgAGAAgJuRDeLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAUJDwANANoiAA==.Najinsky:BAACLgAFFH8PAAINAAUJ2iKnAwCkAQANAAUJ2iKnAwCkAQAuAAQKfzAAAg0ACQk6JYcAAG8DAA0ACQk6JYcAAG8DAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgEJAQAAAA==.Neikko:BAAALgAECgEJAQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nellir:BAABLgAECn8kAAMPAAgJdBNzCADDAQAPAAcJBhZzCADDAQAeAAMJUgIUEAE+AAAAAA==.Nerestrin:BAAALgADCgYJBgAAAA==.',
Ni='Nitefall:BAAALgADCgEJAQAAAA==.',
No='Norlert:BAAALgAECgQJBgAAAA==.Nosfinariel:BAAALgAECgQJCAAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgEJAQAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Po='Poncho:BAAALgAECgIJBwAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJEQAfAAAAAA==.',
Pu='Pulaski:BAAALgADCgkJDwAAAA==.Punchite:BAAALgAECgYJBgABLgAECggJKwAgAFElAA==.',
Ra='Raymane:BAAALgAECgEJAQAAAA==.',
Re='Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgEJAQAAAA==.Revenger:BAAALgADCgYJBgAAAA==.',
Rh='Rhau:BAABLgAECn8YAAIhAAYJvR9XCQAqAgAhAAYJvR9XCQAqAgAAAA==.',
Ro='Rombo:BAAALgAECgYJEQAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgEJAQAAAA==.Ryukie:BAAALgAECgUJBgAAAA==.',
Sa='Saiden:BAABLgAECn8bAAINAAkJKCAuGwDGAgANAAkJKCAuGwDGAgAAAA==.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgQJBwAAAA==.',
Se='Serenna:BAAALgAECgIJAgAAAA==.Serios:BAAALgAECgEJAQAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAECgYJIQAiAHwhAQ==.Sharun:BAAALgAECgEJAQABLgAECgQJBwAfAAAAAA==.Sharundito:BAAALgAECgQJBwAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8oAAILAAgJjyEdAQAMAwALAAgJjyEdAQAMAwAAAA==.Sinistra:BAAALgAECgkJEAAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAAALgAECgMJAwAAAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn84AAINAAkJbR1kCACVAgANAAkJbR1kCACVAgAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIjAAYJVRuuQwAzAQAjAAYJVRuuQwAzAQAAAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.',
Su='Suicidestyle:BAABLgAECn8WAAMhAAcJTw7CCwDkAAAhAAcJTw7CCwDkAAAPAAMJewanCwBvAAAAAA==.',
Sy='Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgMJAwAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8aAAMFAAYJthLFHwA3AQAFAAYJfg/FHwA3AQAMAAMJOhKcMwCoAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgQJBAAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgADCgQJBAAAAA==.Touraine:BAAALgAECgUJEQAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgMJAwAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn8kAAIdAAgJnwpWGABPAQAdAAgJnwpWGABPAQAAAA==.',
Va='Valcoree:BAAALgAECgMJAwAAAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAIRAAgJByIvCQABAwARAAgJByIvCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgEJAgAAAA==.',
Vo='Vorastrix:BAAALgAECgEJAgAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
Wa='Waivern:BAABLgAECn8UAAIGAAgJJhUtEgDLAQAGAAgJJhUtEgDLAQAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIXAAcJ3RTEIQClAQAXAAcJ3RTEIQClAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECggJHQAUAEoXAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgEJAQAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgUJBgAfAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn8rAAIgAAgJUSVfAABQAwAgAAgJUSVfAABQAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJAwAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgYJBwAAAA==.Zeldoris:BAABLgAECn8oAAIiAAgJVSDTBACyAgAiAAgJVSDTBACyAgAAAA==.',
Zu='Zula:BAAALgAECgEJAQAAAA==.',
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

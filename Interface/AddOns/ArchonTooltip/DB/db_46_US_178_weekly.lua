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

local lookup = {'Hunter-Marksmanship','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','Druid-Guardian','Warrior-Protection','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','Priest-Holy','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Evoker-Preservation','Shaman-Restoration','Warrior-Arms','Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Shaman-Elemental',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgADCgkJDAAAAA==.',
Ah='Ahote:BAAALgAECgYJEQAAAA==.',
Ai='Airrows:BAABLgAECn8XAAIBAAcJMyOdEAC0AgABAAcJMyOdEAC0AgAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgUJBQAAAA==.Alurea:BAAALgAECgYJEQAAAA==.',
An='Ang:BAABLgAECn8dAAICAAgJixLQLAABAgACAAgJixLQLAABAgAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.',
Ap='Apathy:BAABLgAECn8gAAIDAAgJLBlrIgALAgADAAgJLBlrIgALAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIDAAcJLyJ4GABPAgADAAcJLyJ4GABPAgAAAA==.Aratiri:BAAALgAECgIJAgAAAA==.Argonäut:BAABLgAECn8bAAIEAAgJ8yIwBgAGAwAEAAgJ8yIwBgAGAwAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8YAAIFAAcJ3g5fJwAxAQAFAAcJ3g5fJwAxAQAAAA==.Astragos:BAAALgAECgYJEgAAAA==.',
Az='Azagorod:BAAALgAECgEJAQAAAA==.',
Ba='Baern:BAAALgAECgYJEgAAAA==.',
Be='Beaconstrips:BAABLgAECn8dAAMDAAcJ+w57PACIAQADAAYJAxF7PACIAQAGAAYJ1Am7RAB1AAAAAA==.Beleth:BAABLgAECn8UAAIBAAYJ6BnMLgC6AQABAAYJ6BnMLgC6AQAAAA==.',
Bi='Billamong:BAAALgAECgYJEQAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAAALgAECgYJEgAAAA==.',
Bo='Boney:BAAALgAECgEJAgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn8fAAIFAAgJThkyTwBJAgAFAAgJThkyTwBJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAAALgAFFAMJBAABLgAFFAUJDAAFAGEYAA==.',
Ca='Caiki:BAAALgAECgQJBAAAAA==.Catelaya:BAABLgAECn8eAAIHAAgJ1hIcCgDHAQAHAAgJ1hIcCgDHAQAAAA==.Cathulu:BAAALgADCgYJBgAAAA==.',
Ce='Celithatha:BAAALgADCgcJDAAAAA==.',
Ch='Chaness:BAAALgAECgcJEgAAAA==.Chexk:BAABLgAECn8XAAIIAAcJ1RnqGgAqAgAIAAcJ1RnqGgAqAgAAAA==.Chillfu:BAAALgAECgYJEQAAAA==.Chixnu:BAAALgADCgkJCQAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Cryblood:BAAALgAECgUJEQAAAA==.',
Cu='Cutsiecow:BAABLgAECn8aAAIJAAcJbxQzDwCIAQAJAAcJbxQzDwCIAQAAAA==.',
Cy='Cynthic:BAAALgAECgQJBwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Dalynn:BAAALgAECgYJCgAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgADCggJDwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8ZAAIKAAgJPhuQCQCBAgAKAAgJPhuQCQCBAgAAAA==.Djiink:BAAALgAECggJEAAAAA==.',
Dr='Drottningu:BAABLgAECn8UAAILAAYJnAwnfQAxAQALAAYJnAwnfQAxAQAAAA==.',
Du='Dunkie:BAAALgAECgQJBAAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgADCgQJBAAAAA==.',
Em='Em:BAABLgAECn8UAAQMAAcJKRxCDwBKAgAMAAcJKRxCDwBKAgANAAQJUBFIRgDMAAAOAAEJNQ0TggAvAAAAAA==.',
Er='Eraline:BAABLgAECn8hAAIPAAgJ7hKrBQDBAQAPAAgJ7hKrBQDBAQAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAAALgAECgcJCgAAAA==.',
Fr='Frostblood:BAAALgAECgEJAgAAAA==.Froststorm:BAAALgAECgEJAQAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8RAAIQAAUJah+JAgDGAQAQAAUJah+JAgDGAQAuAAQKfxoAAhAACAmDJPoFACgDABAACAmDJPoFACgDAAAA.',
Ge='Genocya:BAAALgAECgYJEAAAAA==.',
Gh='Ghost:BAAALgAECggJEAAAAA==.',
Gi='Gilden:BAAALgAECgQJBAAAAA==.',
Gn='Gnot:BAAALgADCgcJGQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8dAAIRAAcJ8Bu2HQBQAgARAAcJ8Bu2HQBQAgAAAA==.',
['Gò']='Gòddess:BAAALgAECgYJBwAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAQAAAA==.Haukkah:BAABLgAECn8cAAMHAAgJaAq5IQD1AAABAAcJHAVkTgAWAQAHAAUJ3Qy5IQD1AAAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAAALgAECgQJBAAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn8kAAISAAYJShIiBgA3AQASAAYJShIiBgA3AQAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAAALgAECgQJBAAAAA==.',
Iw='Iwantmore:BAABLgAECn8gAAIEAAgJrCQ0AwBSAwAEAAgJrCQ0AwBSAwAAAA==.',
Iy='Iyotanka:BAAALgADCgYJCgAAAA==.',
Ju='Juicebox:BAAALgAECgYJCQABLgAECggJFQAQAF0HAA==.Juuzau:BAAALgAECgYJBwAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAAALgAECgYJEAAAAA==.Katheryn:BAABLgAECn8UAAIGAAcJSxxKQgAeAgAGAAcJSxxKQgAeAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJFAAGAEscAA==.Katie:BAAALgAECgcJDQABLgAFFAcJFwATAD8lAA==.',
Ke='Kealey:BAAALgAECgEJAQAAAA==.Kessik:BAABLgAECn8UAAMCAAgJEA8hPwCoAQACAAgJhw4hPwCoAQAUAAQJ1gqWCwCnAAAAAA==.',
Kh='Khaless:BAAALgAECgQJBAAAAA==.',
Ki='Kiamors:BAAALgAECgYJEgAAAA==.Kieru:BAAALgADCgkJCQABLgAECggJIAADACwZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAAALgAECgQJBQAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.',
Le='Leda:BAAALgADCgYJCgAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.',
Li='Liandra:BAAALgAECgYJCwAAAA==.Lightfighter:BAAALgAECgUJCQAAAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lilkiwi:BAAALgAECgQJBAAAAA==.',
Lo='Louhfu:BAAALgAECgYJBgAAAA==.',
Lu='Lunchbox:BAAALgAECgYJDgAAAA==.Lunecy:BAAALgAECgYJEAAAAA==.',
Ma='Magul:BAABLgAECn8lAAIFAAgJWxn3VwAxAgAFAAgJWxn3VwAxAgAAAA==.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgQJBAABLgAFFAUJDAAFAGEYAA==.',
Me='Medie:BAABLgAECn8gAAIOAAgJ7CD8BgDdAgAOAAgJ7CD8BgDdAgAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8ZAAMDAAgJuRDgLgDHAQADAAgJuRDgLgDHAQAGAAIJFhZcQACOAAAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgAAAA==.Najinsky:BAACLgAFFH8KAAIGAAQJDiAdAQCYAQAGAAQJDiAdAQCYAQAuAAQKfywAAgYACQkOJDsAAFADAAYACQkOJDsAAFADAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neikko:BAAALgAECgEJAQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nellir:BAABLgAECn8eAAMVAAgJEBN1CADDAQAVAAcJkRV1CADDAQAWAAMJUgIIEAE+AAAAAA==.Nerestrin:BAAALgADCgYJBgAAAA==.',
Ni='Nitefall:BAAALgADCgEJAQAAAA==.',
No='Norlert:BAAALgAECgQJBQAAAA==.Nosfinariel:BAAALgAECgQJBAAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJBwAAAA==.',
['Nä']='Nämeless:BAAALgAECgMJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Po='Poncho:BAAALgAECgEJBAAAAA==.',
Pr='Proticus:BAAALgAECgYJCAABLgAECggJEAAXAAAAAA==.',
Pu='Pulaski:BAAALgADCgcJDQAAAA==.Punchite:BAAALgADCgYJBgABLgAECggJJAAYAE8lAA==.',
Ra='Raymane:BAAALgAECgEJAQAAAA==.',
Re='Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgADCgQJBgAAAA==.Revenger:BAAALgADCgYJBgAAAA==.',
Rh='Rhau:BAABLgAECn8YAAIZAAYJvR+MAQCpAQAZAAYJvR+MAQCpAQAAAA==.',
Ro='Rombo:BAAALgAECgYJCwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgEJAQAAAA==.Ryukie:BAAALgAECgUJBgAAAA==.',
Sa='Saiden:BAABLgAECn8bAAIGAAkJKCAwGwDGAgAGAAkJKCAwGwDGAgAAAA==.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgQJBwAAAA==.',
Se='Serenna:BAAALgAECgIJAgAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAECgQJFwAaAJkhAQ==.Sharun:BAAALgADCgkJEAABLgAECgQJBAAXAAAAAA==.Sharundito:BAAALgAECgQJBAAAAA==.',
Si='Sidehussy:BAABLgAECn8gAAISAAgJ1RxJDQBiAgASAAgJ1RxJDQBiAgAAAA==.Sinistra:BAAALgAECggJCAAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn8mAAIGAAgJxBxZMgBZAgAGAAgJxBxZMgBZAgAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.',
Sq='Squirt:BAAALgAECgYJEAAAAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.',
Su='Suicidestyle:BAABLgAECn8WAAMZAAcJTw6CBQDsAAAZAAcJTw6CBQDsAAAVAAMJewYFBgBvAAAAAA==.',
Sy='Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgADCgkJHAAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAAALgAECgYJEwAAAA==.',
Ti='Tinymittenz:BAAALgADCgcJCAAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgADCgQJBAAAAA==.Touraine:BAAALgAECgUJDAAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgADCgkJGgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn8cAAIbAAgJSgjrOQBnAQAbAAgJSgjrOQBnAQAAAA==.',
Va='Valcoree:BAAALgADCgUJBQABLgAECgYJGAANAM8QAA==.',
Ve='Vendle:BAABLgAECn8ZAAIHAAgJByIuCQACAwAHAAgJByIuCQACAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgEJAQAAAA==.',
Vo='Vorastrix:BAAALgADCgcJDAAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
Wa='Waivern:BAAALgAECgYJDAAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIPAAcJ3RTQIQCmAQAPAAcJ3RTQIQCmAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgcJGgAJAG8UAA==.Windrunners:BAAALgADCgQJBQAAAA==.',
Wo='Wooly:BAAALgAECgEJAQAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgUJBQAXAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn8kAAIYAAgJTyUKAADPAgAYAAgJTyUKAADPAgAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJAwAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgYJBwAAAA==.Zeldoris:BAABLgAECn8gAAIaAAgJ6h7SBACyAgAaAAgJ6h7SBACyAgAAAA==.',
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

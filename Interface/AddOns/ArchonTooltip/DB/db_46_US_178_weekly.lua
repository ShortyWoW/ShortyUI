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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Paladin-Retribution','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','Rogue-Subtlety','Priest-Shadow','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Protection','Monk-Brewmaster','Druid-Balance','DemonHunter-Vengeance','Shaman-Restoration','Warrior-Arms','Shaman-Elemental','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Druid-Feral',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8eAAIBAAcJ6SDyAABFAgABAAcJ6SDyAABFAgAAAA==.',
Ai='Airrows:BAABLgAECn8jAAMCAAgJCiSgBADtAQACAAgJCiSgBADtAQADAAQJKRhkIQDzAAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgUJBwAAAA==.Alurea:BAABLgAECn8dAAIEAAYJ4wpHTADiAAAEAAYJ4wpHTADiAAAAAA==.',
An='Ang:BAABLgAECn8dAAIFAAgJkBLNLAABAgAFAAgJkBLNLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIGAAkJbxmsCACIAgAGAAkJbxmsCACIAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIGAAcJLyJ0GABPAgAGAAcJLyJ0GABPAgAAAA==.Argonäut:BAABLgAECn8sAAIHAAkJBSOyAABBAwAHAAkJBSOyAABBAwAAAA==.Arimalo:BAAALgAECgMJAwAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8gAAIIAAgJ2w0ETQCCAQAIAAgJ2w0ETQCCAQAAAA==.Astragos:BAABLgAECn8bAAQJAAgJ7xebAwDaAQAJAAcJwBubAwDaAQAKAAYJZg80OAAVAQALAAIJdR7nGQCwAAAAAA==.',
Az='Azagorod:BAAALgAECgEJAQAAAA==.',
Ba='Baern:BAABLgAECn8eAAIMAAYJuyP5BwD+AQAMAAYJuyP5BwD+AQAAAA==.',
Be='Beaconstrips:BAABLgAECn8xAAMGAAgJchd+DQA+AgAGAAgJchd+DQA+AgANAAYJ1AnQwgBxAAAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlILwC6AQACAAYJ6BlILwC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8dAAIOAAYJXhvsEwCSAQAOAAYJXhvsEwCSAQAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8ZAAIPAAcJlwveBgBAAQAPAAcJlwveBgBAAQAAAA==.',
Bo='Boney:BAAALgAECgEJAgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn8oAAIIAAkJChp1FgBnAgAIAAkJChp1FgBnAgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8IAAIQAAMJRRV4CQDPAAAQAAMJRRV4CQDPAAABLgAFFAUJFQAIAH8ZAA==.',
Ca='Caiki:BAAALgAECgYJCgAAAA==.Catelaya:BAABLgAECn8wAAIRAAkJViC/AwD9AgARAAkJViC/AwD9AgAAAA==.Cathulu:BAAALgADCgYJBgAAAA==.',
Ce='Celithatha:BAAALgAECgkJEAAAAA==.',
Ch='Chaness:BAABLgAECn8ZAAINAAgJfRroQwAYAgANAAgJfRroQwAYAgAAAA==.Chexk:BAABLgAECn8kAAISAAgJgx19BgBJAgASAAgJgx19BgBJAgAAAA==.Chillfu:BAABLgAECn8ZAAIOAAcJwBiXEQCrAQAOAAcJwBiXEQCrAQAAAA==.Chixnu:BAAALgADCgkJCQAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAAALgAECgUJBQABLgAFFAMJCAAEAJseAA==.Cryblood:BAABLgAECn8ZAAITAAcJAw+8HABWAQATAAcJAw+8HABWAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn8lAAIUAAgJ8xfcBgDVAQAUAAgJ8xfcBgDVAQAAAA==.',
Cy='Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Dalynn:BAABLgAECn8YAAINAAcJpwcDaQAbAQANAAcJpwcDaQAbAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAQAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAIMAAgJex8WBQBYAgAMAAgJex8WBQBYAgAAAA==.Djiink:BAAALgAECggJEwAAAA==.',
Do='Doomlocke:BAAALgADCgEJAQAAAA==.',
Dr='Drakatoa:BAAALgADCgkJCQAAAA==.Drottningu:BAABLgAECn8kAAIVAAgJEg0OOQBSAQAVAAgJEg0OOQBSAQAAAA==.',
Du='Dunkie:BAAALgAECgUJCwAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgADCgQJBAAAAA==.',
El='Ellaryas:BAAALgAECgEJAQAAAA==.',
Em='Em:BAACLgAFFH8IAAIWAAQJyxVaEABGAQAWAAQJyxVaEABGAQAuAAQKfxUABBYABwkpHD4PAEoCABYABwkpHD4PAEoCABMABAlQEVRGAMwAABAAAQk1DSGCAC8AAAAA.',
Er='Eraline:BAABLgAECn8tAAIXAAgJlhPPEwC/AQAXAAgJlhPPEwC/AQAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8WAAIYAAcJwCK3HgAQAgAYAAcJwCK3HgAQAgAAAA==.',
Fi='Fizzlepriest:BAAALgADCgkJDgABLgAECgcJJwAZAEcfAQ==.',
Fl='Flaciddream:BAAALgAECgQJBAAAAA==.',
Fr='Frostblood:BAAALgAECgEJAwAAAA==.Frostlight:BAAALgAECgEJAQAAAA==.Froststorm:BAAALgAECgEJAQAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8YAAIaAAYJohuLAgDGAQAaAAYJohuLAgDGAQAuAAQKfxoAAhoACAmDJPoFACgDABoACAmDJPoFACgDAAAA.',
Ge='Genivan:BAAALgADCgMJAwAAAA==.Genocya:BAAALgAECgYJEAAAAA==.',
Gh='Ghost:BAAALgAECggJEQAAAA==.',
Gi='Gilden:BAAALgAECgYJDQAAAA==.',
Gn='Gnot:BAAALgADCgcJGQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8lAAMEAAgJlBy5HQBQAgAEAAcJlhy5HQBQAgAbAAUJXBOrHwA5AQAAAA==.',
Gy='Gyoza:BAAALgAECggJCAABLgAECgkJKQAGAG8ZAA==.',
['Gò']='Gòddess:BAAALgAECgcJDAAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8qAAMRAAgJbxL9IgDLAQARAAgJbxL9IgDLAQACAAcJHAW2TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAAALgAECgYJDwAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn8yAAQLAAgJfBJ3CQDHAQALAAgJfBJ3CQDHAQAJAAQJkA9zCwDgAAAKAAIJygpIXAAyAAAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAAALgAECgYJDAAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMcAAkJeSS+AADoAgAHAAkJySOIAQACAwAcAAkJ3iC+AADoAgAAAA==.',
Iy='Iyotanka:BAAALgAECgEJAQAAAA==.',
Ju='Juicebox:BAAALgAECgYJDwABLgAECggJHQAaAF8IAA==.Juuzau:BAAALgAECgcJCAAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAABLgAECn8jAAIWAAgJbhJgDgDrAQAWAAgJbhJgDgDrAQAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Katheryn:BAABLgAECn8eAAINAAcJDyFwGwAkAgANAAcJDyFwGwAkAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJHgANAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAcJIQAdAD8lAA==.',
Ke='Kealey:BAAALgAECgUJBwAAAA==.Keine:BAAALgAECgEJAQAAAA==.Kessik:BAABLgAECn8ZAAMFAAgJmBAmPwCoAQAFAAgJSBAmPwCoAQAeAAQJ2wrLJACgAAAAAA==.',
Kh='Khaless:BAAALgAECgYJDQAAAA==.',
Ki='Kiamors:BAABLgAECn8eAAMfAAYJnAGNSQB/AAAfAAYJnAGNSQB/AAAdAAEJdwHgqwAcAAAAAA==.Kieru:BAAALgADCgkJCQABLgAECgkJKQAGAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8VAAMFAAgJWRkmDQAZAgAFAAgJWRkmDQAZAgAeAAIJUQr4PwAvAAAAAA==.Kreleing:BAAALgAECgQJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAAALgAECgEJAQAAAA==.',
Le='Leda:BAAALgAECgEJAQAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.',
Li='Liandra:BAAALgAECgYJEQAAAA==.Lightfighter:BAAALgAECgcJEAABLgAECggJDgAgAAAAAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECggJDgAgAAAAAA==.Lilkiwi:BAAALgAECgYJDQAAAA==.',
Lo='Louhfu:BAAALgAECgcJEwAAAA==.',
Lu='Lunchbox:BAABLgAECn8aAAIDAAYJcQWrHwACAQADAAYJcQWrHwACAQAAAA==.Lunecy:BAABLgAECn8gAAQDAAgJ6h7sBABvAgADAAgJVh7sBABvAgARAAUJdSCEQwCiAQACAAEJaQcyjwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8GAAIIAAMJ4Q91SAD4AAAIAAMJ4Q91SAD4AAAuAAQKfy0AAggACAkJG+dXADECAAgACAkJG+dXADECAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgYJCAABLgAFFAUJFQAIAH8ZAA==.',
Mc='Mcpheex:BAAALgAECgcJEAAAAA==.',
Me='Medie:BAABLgAECn8pAAMQAAkJQx/7BgDdAgAQAAkJQx/7BgDdAgATAAQJ4wtNOQCfAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8oAAMNAAkJyBztCQC6AgANAAkJyBztCQC6AgAGAAgJWhLfLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAUJFAANAOQjAA==.Najinsky:BAACLgAFFH8UAAINAAUJ5CPcBQCuAQANAAUJ5CPcBQCuAQAuAAQKfzEAAg0ACQk7JS4BAGYDAA0ACQk7JS4BAGYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgEJAQABLgAECggJIwATAMQXAA==.Neikko:BAAALgAECgUJBQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nellir:BAABLgAECn8qAAMPAAgJ8BWUAwDAAQAPAAgJ8BWUAwDAAQAhAAMJUwIfEAE+AAAAAA==.Nerestrin:BAAALgADCgYJBgAAAA==.',
Ni='Nitefall:BAAALgADCgEJAQAAAA==.',
No='Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAAALgAECgYJDQAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECgEJAQAAAA==.',
Po='Poncho:BAAALgAECgIJBwAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJEQAgAAAAAA==.',
Pu='Pulaski:BAAALgAECgMJAwAAAA==.Punchite:BAAALgAECgYJBgABLgAECggJMQAiAGUlAA==.',
Ra='Ramarl:BAAALgADCgkJCgABLgAECgkJMQAZAJ4fAA==.Raymane:BAAALgAECgIJAgAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAUJFQAIAH8ZAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgMJAwAAAA==.Revenger:BAAALgADCgYJBgAAAA==.',
Rh='Rhau:BAABLgAECn8YAAIjAAYJvR9YCQAqAgAjAAYJvR9YCQAqAgAAAA==.',
Ro='Rombo:BAABLgAECn8XAAIkAAYJgRsYCQCXAQAkAAYJgRsYCQCXAQAAAA==.Rosastrasza:BAAALgADCgIJAgAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgUJCAAAAA==.Ryukie:BAAALgAECgUJBgAAAA==.',
Sa='Saiden:BAACLgAFFH8HAAINAAMJExtTJAAbAQANAAMJExtTJAAbAQAuAAQKfx8AAg0ACQm5ICsbAMYCAA0ACQm5ICsbAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgQJBwAAAA==.',
Se='Serenna:BAAALgAECgIJAwAAAA==.Serios:BAAALgAECgIJAwAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAECgcJJwAZAEcfAQ==.Sharun:BAAALgAECgYJBgAAAA==.Sharundito:BAAALgAECgQJBwABLgAECgYJBgAgAAAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.',
Si='Sidehussy:BAABLgAECn8pAAILAAkJvR8ZAQBFAwALAAkJvR8ZAQBFAwAAAA==.Sinistra:BAABLgAECn8ZAAIhAAkJqROyGQAWAgAhAAkJqROyGQAWAgAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAAALgAECgQJBgAAAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn86AAINAAkJbx3XDACaAgANAAkJbx3XDACaAgAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIYAAYJVRscXQArAQAYAAYJVRscXQArAQABLgAECgcJEwAgAAAAAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.',
Su='Suicidestyle:BAABLgAECn8YAAQjAAgJJw1NDAAOAQAjAAgJJw1NDAAOAQAPAAMJiAZKEgBgAAAhAAEJhAfV4gAwAAAAAA==.',
Sy='Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgMJBAAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMFAAgJpxWHIgBaAQAFAAYJsxSHIgBaAQAMAAUJKBWvIQCwAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgQJBAAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgADCgQJBAAAAA==.Touraine:BAABLgAECn8YAAIfAAcJKxwnDwDvAQAfAAcJKxwnDwDvAQAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgYJCAAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn8sAAIfAAgJ4QszHwBUAQAfAAgJ4QszHwBUAQAAAA==.',
Va='Valcoree:BAAALgAECgMJAwABLgAECgcJGQATAFkOAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAIRAAgJByIsCQABAwARAAgJByIsCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgEJAgAAAA==.',
Vo='Vorastrix:BAAALgAECgEJAgAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJEgAAAA==.',
Wa='Waivern:BAABLgAECn8cAAIGAAgJYxsIDABTAgAGAAgJYxsIDABTAgAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIXAAcJ3RTIIQClAQAXAAcJ3RTIIQClAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECggJJQAUAPMXAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgEJAQAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgUJBwAgAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn8xAAIiAAgJZSVfAABQAwAiAAgJZSVfAABQAwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgYJBwAAAA==.Zeldoris:BAABLgAECn8xAAIZAAkJnh+2AQC4AgAZAAkJnh+2AQC4AgAAAA==.Zenelf:BAAALgAECgUJBgABLgAECggJEQAgAAAAAA==.',
Zu='Zula:BAAALgAECgEJAgAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJBwABLgAECgcJCwAgAAAAAA==.',
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

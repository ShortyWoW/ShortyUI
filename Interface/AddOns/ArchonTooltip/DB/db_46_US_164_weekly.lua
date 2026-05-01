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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Druid-Guardian','Mage-Fire','Warrior-Fury','Warrior-Arms','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Mage-Frost','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Evoker-Devastation','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCgYJBwAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8WAAIBAAcJ0BrRCgDTAQABAAcJ0BrRCgDTAQAAAA==.',
Am='Ambrozyn:BAAALgAECgIJAwAAAA==.',
An='Andrew:BAAALgAECgYJBgAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFAACAIwNAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgkJFQABLgAECgYJEAADAAAAAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Arieljoyeria:BAACLgAFFH8JAAMEAAQJDxorAQB1AQAEAAQJDxorAQB1AQAFAAIJjA1QFACtAAAuAAQKfyIAAwUACAkoH+ANAMACAAUACAl5HeANAMACAAQABAkhGP8GADoBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgADCgQJBAAAAA==.Astar:BAAALgADCgcJDgABLgAECgcJDwADAAAAAA==.Astraea:BAABLgAECn8YAAIHAAYJyRPtCgAUAQAHAAYJyRPtCgAUAQABLgAECgYJHwAGAK4kAA==.',
At='Athika:BAAALgADCgQJBAAAAA==.',
Au='Auddorn:BAAALgAECgIJAwAAAA==.Auria:BAAALgAECgYJCgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAABLgAECn8gAAIBAAgJ7wg/KACXAQABAAgJ7wg/KACXAQAAAA==.Azralia:BAAALgAECggJDwAAAA==.',
Bb='Bbygee:BAAALgAECgYJDQAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgYJCwAAAA==.Beyblade:BAAALgAECgEJAgAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8kAAIIAAkJrAh1AQDMAQAIAAkJrAh1AQDMAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Boggy:BAAALgAECgYJEAAAAA==.Borgin:BAAALgAECgUJCQAAAA==.Borimor:BAAALgAECgYJCwABLgAECgkJFAACAIwNAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braylia:BAAALgADCggJCAAAAA==.Briaella:BAAALgAECgYJCAAAAA==.Bridgetta:BAAALgADCgIJAgAAAA==.Briëlla:BAAALgAECgYJDgAAAA==.Bromdrago:BAAALgADCgYJAgAAAA==.Bromkin:BAAALgAECgUJBQAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgEJAQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAAALgAECgYJDAAAAA==.',
Ce='Ceran:BAAALgAECgYJEAAAAA==.Cereus:BAAALgAECgcJDwAAAA==.',
Ch='Chaelenge:BAAALgAECgYJEAAAAA==.Cheatt:BAAALgADCggJBQAAAA==.Chubbabuns:BAABLgAECn8iAAMJAAcJcCCGDADnAQAJAAYJ2SOGDADnAQAKAAYJShDsDwANAQAAAA==.Chyran:BAAALgADCgMJAwAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8UAAILAAYJXhrdDwCnAQALAAYJXhrdDwCnAQAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJCgAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgIJAgAAAA==.Dalielah:BAAALgAECgEJAQAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Denvoker:BAAALgAECgMJBgAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJDwAAAA==.',
Di='Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Dolleez:BAAALgADCgkJCQAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAAALgAECgYJEAAAAA==.',
Du='Dunkaroo:BAABLgAECn8RAAIMAAYJPhYkNwAGAQAMAAYJPhYkNwAGAQAAAA==.',
Ei='Eikinskaldi:BAAALgADCgQJBQAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAAALgAECgYJCgAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgQJBgAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECggJJQANAEwUAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgADCgcJDgAAAA==.Frogan:BAAALgAECgQJBQAAAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BByOACgAQAGAAgJ2BByOACgAQAOAAMJ4h27bQCMAAAAAA==.Frìeren:BAABLgAECn8aAAIPAAcJLBVmOQCDAQAPAAcJLBVmOQCDAQAAAA==.',
Fu='Fundetected:BAABLgAECn8UAAIMAAgJfBg6UQCyAQAMAAgJfBg6UQCyAQAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgADCgUJBQAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgADCggJHQAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgADCggJBAAAAA==.Grimmberly:BAAALgADCgEJAQAAAA==.Grimmothy:BAABLgAECn8UAAIQAAYJaRQ5GgAtAQAQAAYJaRQ5GgAtAQAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guthunnel:BAABLgAECn8YAAICAAYJ6Qn8QAASAQACAAYJ6Qn8QAASAQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgADCgYJCgAAAA==.Hakuri:BAAALgADCgYJCAAAAA==.Hannibow:BAAALgAECgcJBgAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAAALgAECgYJEAAAAA==.',
Hi='Highfever:BAAALgAECgQJCAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgADCgUJBQADAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgcJGQARAGQaAA==.Huuch:BAABLgAECn8YAAICAAcJHQpRMABPAQACAAcJHQpRMABPAQAAAA==.',
Ic='Icrucify:BAABLgAECn8lAAICAAkJCyWJAABbAwACAAkJCyWJAABbAwAAAA==.',
Ig='Ignia:BAAALgADCgEJAQAAAA==.',
Il='Ilanos:BAAALgADCgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBQAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAADAAAAAA==.',
Ir='Iremoon:BAABLgAECn8aAAMSAAcJDw/5QgA1AQASAAcJDw/5QgA1AQATAAIJRwQOQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgADCgIJAQABLgAECggJHAANAOMPAA==.Jestyrd:BAAALgAECgMJAwABLgAECggJHAANAOMPAA==.Jestyrmo:BAABLgAECn8cAAMNAAgJ4w/aGAA/AQANAAgJ4w/aGAA/AQAQAAQJhBthQwA1AQAAAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAABLgAECn8tAAMUAAkJSCSCAABGAwAUAAkJSCSCAABGAwANAAEJngfobAAoAAAAAA==.',
Jo='Jodi:BAAALgAECgYJDgAAAA==.',
Ka='Kainarasa:BAAALgAECgYJEwAAAA==.Katarinea:BAABLgAECn8ZAAIVAAcJlg4/GgAqAQAVAAcJlg4/GgAqAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Kh='Khalessie:BAABLgAECn8WAAIWAAcJHAvCEwBbAQAWAAcJHAvCEwBbAQAAAA==.Kheldar:BAAALgADCgYJAgAAAA==.Khrone:BAAALgADCgEJAQAAAA==.',
Ki='Kirsi:BAABLgAECn8jAAMXAAkJpR7RAADLAgAXAAkJpR7RAADLAgAGAAEJeAGbbgAaAAAAAA==.',
Ko='Korkneelious:BAAALgADCgEJAQAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgYJEwADAAAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8VAAIJAAYJEQvVKAD+AAAJAAYJEQvVKAD+AAAAAA==.Liths:BAABLgAECn8ZAAIYAAcJbQlJDADQAAAYAAcJbQlJDADQAAAAAA==.Littlemoses:BAAALgAECgYJDwAAAA==.',
Lo='Lockdarkly:BAAALgAECgIJBAAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgUJCgAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJDwADAAAAAA==.Malendren:BAAALgADCgYJAgAAAA==.Malignus:BAAALgAECgcJDwABLgADCgkJFwADAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgYJEgADAAAAAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgMJAwAAAA==.',
Mc='Mcdavé:BAABLgAECn8aAAIOAAcJnA37IAATAQAOAAcJnA37IAATAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECgcJFgABANAaAA==.Meerclar:BAAALgAECgEJAgABLgAECgIJBAADAAAAAA==.Melaila:BAABLgAECn8fAAIGAAYJriR7EgCCAgAGAAYJriR7EgCCAgAAAA==.Mellwynn:BAAALgADCgUJBQAAAA==.',
Mf='Mf:BAABLgAECn8OAAIMAAcJdBENMAAjAQAMAAcJdBENMAAjAQAAAA==.',
Mi='Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgADCgMJAwAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgMJBgAAAA==.Mongrol:BAAALgAECgEJAQAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgQJCAADAAAAAA==.',
Mu='Mummrakhan:BAAALgADCggJKAAAAA==.',
Na='Naniel:BAABLgAECn8dAAIJAAgJVxEdLAAFAgAJAAgJVxEdLAAFAgAAAA==.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neb:BAABLgAECn8iAAMZAAkJKRVbEQAaAgAZAAkJKRVbEQAaAgAaAAIJuRFQVwBoAAAAAA==.Necroy:BAAALgAECgYJCQAAAA==.',
Ni='Niccee:BAAALgAECgYJEAAAAA==.Nick:BAACLgAFFH8QAAIZAAUJ+BucDQBrAQAZAAUJ+BucDQBrAQAuAAQKfxgAAxkACAkYIycbALECABkACAkYIycbALECABoAAQkAAG+AABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQADAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgYJEgADAAAAAA==.Nosebleeds:BAAALgAECgYJDQAAAA==.Notyourheals:BAABLgAECn8VAAMOAAYJxQs7JAD/AAAOAAYJxQs7JAD/AAAGAAQJSAGmjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8lAAIRAAkJMha+DgAiAgARAAkJMha+DgAiAgAAAA==.',
Od='Odsum:BAABLgAECn8VAAIbAAYJEBhIMwB1AQAbAAYJEBhIMwB1AQAAAA==.',
Oo='Oogrutamu:BAAALgADCggJBAAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgEJAQAAAA==.Pandabear:BAAALgADCgYJBgAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papichulo:BAAALgADCgEJAQAAAA==.',
Pe='Percival:BAAALgAECgYJEAAAAA==.',
Pi='Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAAALgAECgYJBgABLgAECgYJEwADAAAAAA==.',
Po='Poetbrat:BAAALgADCgIJAwABLgAECgYJEAADAAAAAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgEJAQAAAA==.',
Pu='Pumpshire:BAABLgAECn8gAAIcAAkJUQrsAwCeAQAcAAkJUQrsAwCeAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAAALgAECgMJAwAAAA==.',
Qu='Queue:BAAALgADCgcJDgAAAA==.Quilten:BAAALgAECgUJCQAAAA==.',
Ra='Raenii:BAAALgADCgEJAQABLgAECgYJEwADAAAAAA==.Ramoth:BAAALgAECgMJBgAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgADCggJBAAAAA==.Rayne:BAAALgAECgYJEgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAAALgAECgYJEgAAAA==.',
Ri='Rinnian:BAAALgAECgYJCQAAAA==.Rinny:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgMJBgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECggJKgAQAAgQAA==.Robbiemonk:BAABLgAECn8qAAMQAAgJCBDKEQB+AQAQAAgJCBDKEQB+AQAUAAQJ9wMIXgCYAAAAAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFAACAIwNAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgUJBQAAAA==.Sannith:BAABLgAECn8aAAIPAAcJJQ/kTwBCAQAPAAcJJQ/kTwBCAQAAAA==.Sapphi:BAAALgAECgYJEAAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgMJCAAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQADAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shespawn:BAAALgAECgEJAgAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8UAAMCAAkJjA3gLwDxAQACAAkJjA3gLwDxAQAdAAEJLQJfMgApAAAAAA==.Shykara:BAAALgADCgIJAwABLgAECgMJBgADAAAAAA==.',
Si='Siegmeyer:BAAALgADCgEJAQABLgADCgYJCAADAAAAAA==.Sins:BAAALgADCggJBAAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slipperybop:BAAALgAECggJEgABLgABCgQJAwADAAAAAA==.Slugbow:BAAALgADCggJFwAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJYgbHKwAXAQAGAAkJYgbHKwAXAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgADCggJBAAAAA==.Sorena:BAAALgADCgIJAgAAAA==.',
Sp='Spyman:BAAALgAECgEJAgAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8ZAAIRAAcJZBoCEQAHAgARAAcJZBoCEQAHAgAAAA==.',
St='Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAADAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgADCggJBAAAAA==.',
Te='Tellah:BAAALgAECgQJBwABLgAECgQJDgADAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgADCgUJBgAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgYJEwADAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgUJDAADAAAAAA==.',
Tw='Twomz:BAABLgAECn8UAAIGAAYJlw71KAApAQAGAAYJlw71KAApAQAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJKAAGAOMbAA==.',
Un='Unclebenjin:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECggJCQADAAAAAA==.',
Va='Vavaboom:BAAALgADCggJCAAAAA==.',
Vi='Vindication:BAAALgAECgYJDAAAAA==.Viz:BAAALgADCgIJAwAAAA==.',
Vo='Voidshådow:BAAALgAECgMJBgAAAA==.',
Vu='Vulpain:BAAALgADCgkJCQABLgAECgYJEwADAAAAAA==.',
Vy='Vylandra:BAAALgADCgEJAgAAAA==.',
We='Weepingwillo:BAAALgADCgUJBQAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgADCgkJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgEJAQAAAA==.',
Xa='Xaela:BAABLgAECn8VAAIMAAcJFxSgKABFAQAMAAcJFxSgKABFAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgIJBAAAAA==.Xarous:BAAALgADCgkJFAABLgAECgYJEwADAAAAAA==.',
Xe='Xeon:BAAALgADCgcJCgAAAA==.',
Xi='Xiabal:BAAALgAECgYJEAAAAA==.',
Xw='Xweakling:BAAALgADCgEJAQABLgAECggJGgAJAJAZAA==.Xweekling:BAABLgAECn8aAAIJAAgJkBnsDgDJAQAJAAgJkBnsDgDJAQAAAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgADCgYJAgAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgIJAgAAAA==.',
Za='Zaraeth:BAAALgADCgYJDAABLgAECgIJBAADAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEQAAAA==.Zerostar:BAAALgADCgYJDgABLgAECgIJAwADAAAAAA==.Zevon:BAAALgADCgQJBAABLgAECgIJBAADAAAAAA==.',
['ße']='ßeastie:BAAALgADCgQJBQAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Priest-Shadow','Mage-Fire','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Devourer','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Druid-Balance','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Evoker-Devastation','Mage-Frost',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.',
Ad='Addison:BAAALgAECgEJAQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAAALgAECgYJDwAAAA==.',
Am='Ambrozyn:BAAALgAECgEJAQAAAA==.',
An='Andrew:BAAALgAECgUJBQAAAA==.Animalz:BAAALgADCgYJBgABLgAECggJEwABAAAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgYJDAABLgAECgUJCgABAAAAAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Arieljoyeria:BAACLgAFFH8FAAMCAAMJ2A+5AwC8AAACAAIJmxG5AwC8AAADAAIJjA1SFACtAAAuAAQKfyIAAwMACAkoH+ANAMACAAMACAl5HeANAMACAAIABAkhGDYDAEgBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAEANgQAA==.',
As='Ashog:BAAALgADCgQJBAAAAA==.Astar:BAAALgADCgcJDgABLgAECgYJBgABAAAAAA==.Astraea:BAAALgAECgYJEgABLgAECgYJGQAEAK4kAA==.',
At='Athika:BAAALgADCgQJBAAAAA==.',
Au='Auddorn:BAAALgAECgEJAQAAAA==.Auria:BAAALgAECgUJCQAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAABLgAECn8cAAIFAAgJ7wg5KACXAQAFAAgJ7wg5KACXAQAAAA==.Azralia:BAAALgAECgYJCQAAAA==.',
Bb='Bbygee:BAAALgAECgYJCgAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgEJAQAAAA==.Beyblade:BAAALgAECgEJAgAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8fAAIGAAgJjgfpAACEAQAGAAgJjgfpAACEAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.',
Bo='Boggy:BAAALgAECgYJCgAAAA==.Borgin:BAAALgAECgQJBAAAAA==.Borimor:BAAALgAECgUJBQABLgAECggJEwABAAAAAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braylia:BAAALgADCggJCAAAAA==.Briaella:BAAALgAECgEJAgAAAA==.Bridgetta:BAAALgADCgIJAgAAAA==.Briëlla:BAAALgAECgYJDAAAAA==.Bromdrago:BAAALgADCgYJAgAAAA==.Bromkin:BAAALgADCgkJEAAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgADCgYJEQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAAALgAECgYJDAAAAA==.',
Ce='Ceran:BAAALgAECgYJCgAAAA==.Cereus:BAAALgAECgYJBgAAAA==.',
Ch='Chaelenge:BAAALgAECgYJCgAAAA==.Cheatt:BAAALgADCggJBQAAAA==.Chubbabuns:BAABLgAECn8bAAMHAAYJIyOZOwC3AQAHAAYJIyOZOwC3AQAIAAUJgxD8CADaAAAAAA==.Chyran:BAAALgADCgMJAwAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAAALgAECgYJDgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJCQAAAA==.',
Cr='Crazyelf:BAAALgADCgQJBQAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgIJAgAAAA==.Dalielah:BAAALgAECgEJAQAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Denvoker:BAAALgAECgIJAwAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJDwAAAA==.',
Di='Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAAALgAECgUJCgAAAA==.',
Du='Dunkaroo:BAAALgAECgYJDwAAAA==.',
Ei='Eikinskaldi:BAAALgADCgMJBAAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAAALgAECgQJBAAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgIJAwAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgcJHgAJABAVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgADCgcJDgABLgAECgUJDQABAAAAAA==.Frogan:BAAALgAECgEJAQAAAA==.Frosh:BAABLgAECn8YAAMEAAgJ2BBzOACgAQAEAAgJ2BBzOACgAQAKAAMJ4h2ybQCMAAAAAA==.Frìeren:BAAALgAECgYJEwAAAA==.',
Fu='Fundetected:BAABLgAECn8WAAILAAcJ2hr7EgBoAQALAAcJ2hr7EgBoAQAAAA==.',
Ga='Garross:BAAALgADCgIJAgAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgADCgUJBQAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgADCggJHQAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgADCggJBAAAAA==.Grimmothy:BAAALgAECgYJDgAAAA==.Grindr:BAAALgADCgcJAwAAAA==.',
Gu='Guthunnel:BAAALgAECgYJEwAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgADCgYJCgAAAA==.Hakuri:BAAALgADCgEJAgAAAA==.Hannibow:BAAALgAECgcJBgAAAA==.Happydru:BAAALgADCgUJCAAAAA==.',
He='Helle:BAAALgAECgYJCgAAAA==.',
Hi='Highfever:BAAALgAECgEJAQAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgADCgUJBQABAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgcJEwABAAAAAA==.Huuch:BAAALgAECgYJEQAAAA==.',
Ic='Icrucify:BAABLgAECn8gAAIMAAgJiCTtAADZAgAMAAgJiCTtAADZAgAAAA==.',
Ig='Ignia:BAAALgADCgEJAQAAAA==.',
Il='Ilanos:BAAALgADCgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBQAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBQANANcLAA==.',
Ir='Iremoon:BAABLgAECn8UAAMOAAcJuwgRIgAUAQAOAAcJuwgRIgAUAQAPAAIJRwQTQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgADCgIJAQABLgAECggJHAAJAOMPAA==.Jestyrd:BAAALgAECgMJAwABLgAECggJHAAJAOMPAA==.Jestyrmo:BAABLgAECn8cAAMJAAgJ4w/YCQBSAQAJAAgJ4w/YCQBSAQAQAAQJhBtlQwA1AQAAAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAABLgAECn8oAAMRAAgJWCRsAADeAgARAAgJWCRsAADeAgAJAAEJngfnbQAoAAAAAA==.',
Jo='Jodi:BAAALgAECgYJCgAAAA==.',
Ka='Kainarasa:BAAALgAECgYJEwAAAA==.Katarinea:BAABLgAECn8XAAISAAcJIg32CwAuAQASAAcJIg32CwAuAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Kh='Khalessie:BAAALgAECgYJDwAAAA==.Kheldar:BAAALgADCgYJAgAAAA==.Khrone:BAAALgADCgEJAQAAAA==.',
Ki='Kirsi:BAABLgAECn8eAAITAAgJ3hj3AQDrAQATAAgJ3hj3AQDrAQAAAA==.',
Ko='Korkneelious:BAAALgADCgEJAQAAAA==.',
Kr='Kretor:BAAALgAECgQJCwAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgYJEwABAAAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAAALgAECgYJEwAAAA==.Liths:BAAALgAECgcJEwAAAA==.Littlemoses:BAAALgAECgUJCQAAAA==.',
Lo='Lockdarkly:BAAALgAECgEJAgAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgUJBQAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJDwABAAAAAA==.Malendren:BAAALgADCgYJAgAAAA==.Malignus:BAAALgAECgYJBgABLgADCgkJFwABAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.',
Mc='Mcdavé:BAABLgAECn8UAAIKAAcJkQqyFADVAAAKAAcJkQqyFADVAAAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECgYJDwABAAAAAA==.Meerclar:BAAALgAECgEJAQAAAA==.Melaila:BAABLgAECn8ZAAIEAAYJriR/EgCCAgAEAAYJriR/EgCCAgAAAA==.Mellwynn:BAAALgADCgMJAwAAAA==.',
Mf='Mf:BAAALgAECgcJDgAAAA==.',
Mi='Minthe:BAAALgAECgEJAQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgADCgMJAwAAAA==.',
Mo='Moardotz:BAAALgADCgQJBQAAAA==.Moldthinur:BAAALgAECgMJAwAAAA==.Mongrol:BAAALgADCggJGAAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgEJAQABAAAAAA==.',
Mu='Mummrakhan:BAAALgADCggJKAAAAA==.',
Na='Naniel:BAABLgAECn8cAAIHAAgJVxEcLAAEAgAHAAgJVxEcLAAEAgAAAA==.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neb:BAABLgAECn8dAAMUAAgJExVzCgDMAQAUAAgJiBRzCgDMAQAVAAIJuRFFVwBoAAAAAA==.Necroy:BAAALgAECgYJCAAAAA==.',
Ni='Niccee:BAAALgAECgYJCgAAAA==.Nick:BAACLgAFFH8MAAIUAAUJCRopBgBYAQAUAAUJCRopBgBYAQAuAAQKfxgAAxQACAkYIycbALICABQACAkYIycbALICABUAAQkAAGiAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.',
No='Noodles:BAAALgAECgMJAwABLgAECgUJDQABAAAAAA==.Nosebleeds:BAAALgAECgYJBwAAAA==.Notyourheals:BAAALgAECgYJEAAAAA==.',
Oa='Oakay:BAAALgADCgcJDAAAAA==.',
Ob='Obee:BAABLgAECn8gAAIWAAgJMhgDCADjAQAWAAgJMhgDCADjAQAAAA==.',
Od='Odsum:BAAALgAECgYJEAAAAA==.',
Oo='Oogrutamu:BAAALgADCggJBAAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgEJAQAAAA==.Pandabear:BAAALgADCgYJBgAAAA==.Papamidnight:BAAALgAECgEJAQAAAA==.',
Pe='Percival:BAAALgAECgYJCgAAAA==.',
Pi='Pizzaslice:BAAALgAECgYJBgABLgAECgYJEwABAAAAAA==.',
Po='Poetbrat:BAAALgADCgIJAwABLgAECgUJCgABAAAAAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pu='Pumpshire:BAABLgAECn8XAAIXAAgJ9wjsFgCFAQAXAAgJ9wjsFgCFAQAAAA==.',
Pw='Pwongo:BAAALgADCgYJDwAAAA==.',
Qu='Queue:BAAALgADCgcJDgAAAA==.Quilten:BAAALgAECgQJBAAAAA==.',
Ra='Raenii:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.Ramoth:BAAALgAECgIJAwAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgADCggJBAAAAA==.Rayne:BAAALgAECgYJDAAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAAALgAECgYJDAAAAA==.',
Ri='Rinnian:BAAALgAECgQJBAAAAA==.Rinny:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgIJAwAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgYJIAAQAG8RAA==.Robbiemonk:BAABLgAECn8gAAMQAAYJbxHXEADmAAAQAAYJbxHXEADmAAARAAQJ9wMHXgCYAAAAAA==.Rodric:BAAALgADCgMJAwABLgAECggJEwABAAAAAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sannith:BAABLgAECn8UAAIYAAcJOQuWKgAiAQAYAAcJOQuWKgAiAQAAAA==.Sapphi:BAAALgAECgYJCgAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgMJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQABAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shespawn:BAAALgAECgEJAQAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAAALgAECggJEwAAAA==.Shykara:BAAALgADCgIJAwABLgAECgIJAwABAAAAAA==.',
Si='Siegmeyer:BAAALgADCgEJAQABLgADCgEJAgABAAAAAA==.Sins:BAAALgADCggJBAAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBAAAAA==.',
Sk='Skulcrack:BAAALgADCgUJCAAAAA==.',
Sl='Slipperybop:BAAALgAECggJEQAAAA==.Slugbow:BAAALgADCgcJEAAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8cAAIEAAgJYgLJXwANAQAEAAgJYgLJXwANAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgADCggJBAAAAA==.Sorena:BAAALgADCgIJAgAAAA==.',
Sr='Srhubbabubba:BAAALgAECgcJEwAAAA==.',
St='Staticbdk:BAAALgAECgEJAQABLgAFFAQJBQANANcLAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJCgAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgADCggJBAAAAA==.',
Te='Tellah:BAAALgAECgQJBAABLgAECgQJCwABAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgADCgUJBQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgYJEwABAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgQJBwABAAAAAA==.',
Tw='Twomz:BAAALgAECgYJDQAAAA==.',
Un='Unclebenjin:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.',
Va='Vavaboom:BAAALgADCggJCAAAAA==.',
Vi='Vindication:BAAALgAECgUJBgAAAA==.Viz:BAAALgADCgIJAwAAAA==.',
Vo='Voidshådow:BAAALgAECgIJAwAAAA==.',
Vy='Vylandra:BAAALgADCgEJAgAAAA==.',
We='Weepingwillo:BAAALgADCgUJBQAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCgAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgADCgkJCQAAAA==.Wiseman:BAAALgADCgUJDAAAAA==.',
Wo='Wolfowl:BAAALgADCgYJEQAAAA==.',
Xa='Xaela:BAAALgAECgYJEwAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Xarous:BAAALgADCgkJFAABLgAECgYJEwABAAAAAA==.',
Xe='Xeon:BAAALgADCgcJCgAAAA==.',
Xi='Xiabal:BAAALgAECgYJCgAAAA==.',
Xw='Xweakling:BAAALgADCgEJAQABLgAECgcJGAAHALsaAA==.Xweekling:BAABLgAECn8YAAIHAAcJuxqACQCHAQAHAAcJuxqACQCHAQAAAA==.',
Ye='Yendara:BAAALgADCgYJAgAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgIJAgAAAA==.',
Za='Zaraeth:BAAALgADCgYJDAABLgAECgEJAQABAAAAAA==.',
Ze='Zedra:BAAALgAECgQJCwAAAA==.Zerostar:BAAALgADCgYJDgABLgAECggJHwAMAD0ZAA==.Zevon:BAAALgADCgQJBAABLgAECgEJAQABAAAAAA==.',
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

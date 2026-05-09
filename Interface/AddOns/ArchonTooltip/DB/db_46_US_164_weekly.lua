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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Paladin-Holy','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Devastation','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Unknown-Unknown','Shaman-Elemental','Mage-Frost','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCgcJDAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8WAAIBAAcJ0hozEADNAQABAAcJ0hozEADNAQAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgIJAwAAAA==.',
An='Andrew:BAAALgAECgYJCQAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFAACAIsNAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgkJHgABLgAECgYJFgADADICAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgEJAQAAAA==.Arieljoyeria:BAACLgAFFH8LAAMEAAQJ5B50AQCEAQAEAAQJ5B50AQCEAQAFAAIJjA1SFACtAAAuAAQKfyIAAwUACAkoH98NAMACAAUACAl5Hd8NAMACAAQABAkqGJ0JADMBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgADCgQJBAAAAA==.Astar:BAAALgADCgcJDgABLgAECggJFwAHAH4cAA==.Astraea:BAABLgAECn8eAAIIAAYJ4RfPCwBVAQAIAAYJ4RfPCwBVAQABLgAECgYJJQAGAPckAA==.',
At='Athika:BAAALgADCgQJBAAAAA==.',
Au='Auddorn:BAAALgAECgIJAwAAAA==.Auria:BAAALgAECgYJEAAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAABLgAECn8hAAIBAAgJ1ws+KACXAQABAAgJ1ws+KACXAQAAAA==.Azralia:BAABLgAECn8XAAIJAAgJkxOtFQDiAQAJAAgJkxOtFQDiAQAAAA==.',
Bb='Bbygee:BAAALgAECgYJDgAAAA==.',
Be='Bearskyspear:BAAALgAFFAEJAQAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgYJCwAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8sAAIKAAkJ2wrxAQDHAQAKAAkJ2wrxAQDHAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAAALgAECgcJEgAAAA==.Borgin:BAAALgAECgYJDwAAAA==.Borimor:BAAALgAECgcJEQABLgAECgkJFAACAIsNAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAAALgAECgYJDwAAAA==.Bridgetta:BAAALgADCgIJAgAAAA==.Briëlla:BAABLgAECn8YAAMLAAgJCBQ8KwDOAQALAAgJCBQ8KwDOAQAMAAEJOgO4QAAXAAAAAA==.Bromdrago:BAAALgADCgYJAgAAAA==.Bromkin:BAAALgAECgYJCwAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgEJAQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAAALgAECgYJEAAAAA==.',
Ce='Ceran:BAAALgAECgcJEgAAAA==.Cereus:BAABLgAECn8XAAMHAAgJfhxTBQBGAgAHAAcJ7hxTBQBGAgANAAEJ4RZ4FQBEAAAAAA==.',
Ch='Chaelenge:BAABLgAECn8UAAMJAAYJpR2PLADTAQAJAAYJpR2PLADTAQAOAAMJpQnIyQBoAAAAAA==.Cheatt:BAAALgADCggJBQAAAA==.Chubbabuns:BAABLgAECn8nAAMPAAcJ9SBzCQCzAQAQAAYJ2yNVEwDTAQAPAAcJwBhzCQCzAQAAAA==.Chyran:BAAALgADCgMJAwAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8aAAIRAAYJXRpvFwCVAQARAAYJXRpvFwCVAQAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJCgAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgMJBQAAAA==.Dalielah:BAAALgAECgEJAQAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Denvoker:BAAALgAECgQJBwAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEAAAAA==.',
Di='Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Dolleez:BAAALgADCgkJCQAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8WAAIDAAYJMgIjQgB2AAADAAYJMgIjQgB2AAAAAA==.',
Du='Dunkaroo:BAABLgAECn8YAAISAAcJlBUIOABVAQASAAcJlBUIOABVAQAAAA==.',
['Dé']='Dékü:BAAALgAECgEJAQAAAA==.',
Ei='Eikinskaldi:BAAALgADCgUJCQAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAAALgAECgcJEQAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgQJBgAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECggJKgATABAWAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgAECgIJAgABLgAECgcJDAAUAAAAAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BByOACgAQAGAAgJ2BByOACgAQAVAAMJ4h23bQCMAAAAAA==.Frìeren:BAABLgAECn8eAAIWAAcJaBXpRwCPAQAWAAcJaBXpRwCPAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgcJBwAAAA==.Fundetected:BAABLgAECn8dAAISAAkJTBjNGAD2AQASAAkJTBjNGAD2AQAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgADCggJHQAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgADCggJBAAAAA==.Grimmberly:BAAALgAECgEJAQAAAA==.Grimmothy:BAABLgAECn8aAAIXAAYJ/xVjHQBJAQAXAAYJ/xVjHQBJAQAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn8gAAICAAgJJwvvMwB+AQACAAgJJwvvMwB+AQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgADCgYJCgAAAA==.Hakuri:BAAALgADCgcJDwAAAA==.Hannibow:BAAALgAECgcJBgAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAAALgAECgcJEgAAAA==.',
Hi='Highfever:BAAALgAECgQJDQAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgADCgUJBQAUAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECggJIQAYAP8bAA==.Huuch:BAABLgAECn8bAAICAAgJFArBNwBuAQACAAgJFArBNwBuAQAAAA==.',
Hy='Hycinari:BAAALgAECgEJAQAAAA==.',
Ic='Icrucify:BAABLgAECn8sAAICAAkJbCXOAABkAwACAAkJbCXOAABkAwAAAA==.',
Ig='Ignia:BAAALgAECgEJAQABLgAECgQJBgAUAAAAAA==.',
Il='Ilanos:BAAALgADCgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBQAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAUAAAAAA==.',
Ir='Iremoon:BAABLgAECn8iAAMLAAgJmA92NgCfAQALAAgJmA92NgCfAQAMAAIJRwQRQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgAECgEJAQABLgAECggJJQAXANAaAA==.Jestyrd:BAAALgAECgMJAwABLgAECggJJQAXANAaAA==.Jestyrmo:BAABLgAECn8lAAMXAAgJ0BpRHABRAQAXAAcJnxlRHABRAQATAAgJgBBbHwBMAQAAAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8FAAIZAAMJOxaZFQCoAAAZAAMJOxaZFQCoAAAuAAQKfzYAAxkACQmFJNkAAFADABkACQmFJNkAAFADABMAAQmeB+lsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJDgAAAA==.',
Ka='Kaceya:BAAALgAECgEJAQAAAA==.Kainarasa:BAAALgAECgYJEwAAAA==.Katarinea:BAABLgAECn8ZAAIDAAcJmw7HIgAiAQADAAcJmw7HIgAiAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Kh='Khalessie:BAABLgAECn8bAAIaAAcJcQ54FwB8AQAaAAcJcQ54FwB8AQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMbAAkJpB63AQCwAgAbAAkJpB63AQCwAgAGAAEJeQEXjwAaAAAAAA==.',
Ko='Korkneelious:BAAALgADCgEJAQAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgYJEwAUAAAAAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8bAAIQAAYJyRBZJgBCAQAQAAYJyRBZJgBCAQAAAA==.Liths:BAABLgAECn8hAAIcAAgJCQkTDAAGAQAcAAgJCQkTDAAGAQAAAA==.Littlemoses:BAABLgAECn8VAAICAAYJniHnHwDdAQACAAYJniHnHwDdAQAAAA==.',
Lo='Lockdarkly:BAAALgAECgIJBAAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgUJCgAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEAAUAAAAAA==.Malendren:BAAALgADCgYJAgAAAA==.Malignus:BAABLgAECn8XAAIWAAgJVREnPQCwAQAWAAgJVREnPQCwAQABLgADCgkJFwAUAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgcJFAAWAC0bAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgQJBQAAAA==.',
Mc='Mcdavé:BAABLgAECn8iAAIVAAgJ5w0RHQBlAQAVAAgJ5w0RHQBlAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECgcJFgABANIaAA==.Meerclar:BAAALgAECgIJAwABLgAECgIJBAAUAAAAAA==.Melaila:BAABLgAECn8lAAIGAAYJ9yR4EgCCAgAGAAYJ9yR4EgCCAgAAAA==.Mellwynn:BAAALgADCgYJCQAAAA==.Melunaura:BAAALgADCggJCAABLgAECgYJJQAGAPckAA==.',
Mf='Mf:BAABLgAECn8UAAISAAcJZRJ+NwBYAQASAAcJZRJ+NwBYAQAAAA==.',
Mi='Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgADCgMJAwAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgMJBgAAAA==.Mongrol:BAAALgAECgEJAQAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgQJDQAUAAAAAA==.',
Mu='Mummrakhan:BAAALgADCgkJMQAAAA==.',
Na='Naniel:BAABLgAECn8hAAIQAAgJnRMZLAAFAgAQAAgJnRMZLAAFAgAAAA==.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBgAAAA==.Neb:BAABLgAECn8rAAMdAAkJJhbXFwAkAgAdAAkJJhbXFwAkAgAeAAIJuRFPVwBoAAAAAA==.Necroy:BAAALgAECgYJCgAAAA==.',
Ni='Niccee:BAAALgAECgcJEgAAAA==.Nick:BAACLgAFFH8RAAIdAAUJ+BvXGQBMAQAdAAUJ+BvXGQBMAQAuAAQKfxgAAx0ACAkYIyYbALECAB0ACAkYIyYbALECAB4AAQkAAHCAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAUAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgYJBgAUAAAAAA==.Nosebleeds:BAAALgAECgYJDQAAAA==.Notyourheals:BAABLgAECn8ZAAMVAAgJ6AqxIABKAQAVAAgJ6AqxIABKAQAGAAQJSAGdjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIYAAkJNxZdFgASAgAYAAkJNxZdFgASAgAAAA==.',
Od='Odsum:BAABLgAECn8WAAIOAAYJKBh9fQB/AQAOAAYJKBh9fQB/AQAAAA==.',
Oo='Oogrutamu:BAAALgADCggJBAAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgIJAgAAAA==.Pandabear:BAAALgADCgYJBgAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papichulo:BAAALgADCgYJBgAAAA==.',
Pe='Percival:BAAALgAECgcJEgAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAAALgAECgYJBgABLgAECgYJEwAUAAAAAA==.',
Po='Poetbrat:BAAALgADCgMJBgABLgAECgYJFgADADICAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgIJAgAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAINAAkJswtdBACwAQANAAkJswtdBACwAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAAALgAECgMJCAAAAA==.',
Qu='Queue:BAAALgAECgMJAwAAAA==.Quilten:BAAALgAECgYJDwAAAA==.',
Ra='Raenii:BAAALgAECgYJBgAAAA==.Ramoth:BAAALgAECgQJBwAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgADCggJBAAAAA==.Rayne:BAABLgAECn8UAAIWAAcJLRvxTgB9AQAWAAcJLRvxTgB9AQAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAAALgAECgYJEwAAAA==.',
Ri='Rinnian:BAAALgAECgYJDgAAAA==.Rinny:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgQJBwAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECggJMgAXAGgRAA==.Robbiemonk:BAABLgAECn8yAAMXAAgJaBGcFgCDAQAXAAgJaBGcFgCDAQAZAAQJ9wMKXgCYAAAAAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFAACAIsNAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJCAAAAA==.Sannith:BAABLgAECn8iAAIWAAgJZBJ0OADBAQAWAAgJZBJ0OADBAQAAAA==.Sapphi:BAAALgAECgcJEgAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgYJDgAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAUAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shespawn:BAAALgAECgEJAgAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8UAAMCAAkJiw3iLwDxAQACAAkJiw3iLwDxAQAfAAEJLQJfMgApAAAAAA==.Shykara:BAAALgADCgMJBgABLgAECgQJBwAUAAAAAA==.',
Si='Sins:BAAALgADCggJBAAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slipperybop:BAAALgAFFAIJAgABLgAECgYJBgAUAAAAAA==.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAaxOwAXAQAGAAkJZAaxOwAXAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgADCggJBAAAAA==.Sorena:BAAALgADCgMJBQAAAA==.',
Sp='Spyman:BAAALgAECgEJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8hAAIYAAgJ/xsFDQB9AgAYAAgJ/xsFDQB9AgAAAA==.',
St='Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAUAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJDAAAAA==.Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgADCggJBAAAAA==.',
Te='Tellah:BAAALgAECgcJDgABLgAECgQJDgAUAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgYJEwAUAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgUJEAAUAAAAAA==.',
Tw='Twomz:BAABLgAECn8aAAIGAAYJnQ7nOAAkAQAGAAYJnQ7nOAAkAQAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABocAA==.',
Un='Unclebenjin:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECggJEAAUAAAAAA==.',
Va='Vavaboom:BAAALgADCggJCAAAAA==.',
Vi='Vindication:BAAALgAECgYJEgAAAA==.Viz:BAAALgADCgMJBgAAAA==.',
Vo='Voidshådow:BAAALgAECgQJBwAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgADCgkJCQABLgAECgYJEwAUAAAAAA==.',
Vy='Vylandra:BAAALgADCgcJCQAAAA==.',
We='Weepingwillo:BAAALgADCgUJBQAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgADCgkJCgAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgEJAQAAAA==.',
Xa='Xaela:BAABLgAECn8YAAISAAgJnxcUIgC8AQASAAgJnxcUIgC8AQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgIJBAAAAA==.Xarous:BAAALgADCgkJFAABLgAECgYJEwAUAAAAAA==.',
Xe='Xeon:BAAALgADCgcJCgAAAA==.',
Xi='Xiabal:BAABLgAECn8VAAMYAAcJPR9EFgATAgAYAAcJPR9EFgATAgADAAMJPRbhMQDJAAAAAA==.',
Xw='Xweakling:BAAALgAECgIJAgABLgAECgkJIwAQAGccAA==.Xweekling:BAABLgAECn8jAAIQAAkJZxyRBAC1AgAQAAkJZxyRBAC1AgAAAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgADCgYJAgAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgMJBQAAAA==.',
Za='Zaraeth:BAAALgAECgIJAgABLgAECgIJBAAUAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zerostar:BAAALgAECgEJAQABLgAECgMJBQAUAAAAAA==.Zevon:BAAALgADCgQJBAABLgAECgIJBAAUAAAAAA==.',
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

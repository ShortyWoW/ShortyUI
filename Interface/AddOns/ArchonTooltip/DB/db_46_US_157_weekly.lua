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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Shaman-Restoration','Warrior-Protection','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Hunter-Marksmanship','Mage-Arcane','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Shaman-Elemental',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaralia:BAABLgAECn8fAAMBAAkJ/BvlEgBfAgABAAgJ6B3lEgBfAgACAAIJBgwAOABwAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgADCgYJBwAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJDQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECggJDwADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgYJHwAEAOATAA==.Alearia:BAAALgADCgEJAQAAAA==.Alewynt:BAAALgAECgEJBAAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgADCgcJDwAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgYJCAAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgADCgcJDgAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Arkin:BAAALgAECgkJBwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJAwAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJCAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAXaLADEAAACAAYJxAXaLADEAAAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xT+HACgAQAFAAgJ5xT+HACgAQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgEJAgAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAUJCgAGAAkTAA==.',
Be='Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAAALgAECgYJDgAAAA==.Bloodedge:BAABLgAECn8ZAAIHAAgJRRwgBgBIAgAHAAgJRRwgBgBIAgAAAA==.',
Bo='Bobbyswagger:BAAALgAFFAIJAwAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Brentobox:BAABLgAECn8aAAIIAAYJUyNMCQBbAgAIAAYJUyNMCQBbAgAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgUJCwAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.',
Bu='Bungeholio:BAABLgAECn8eAAIBAAgJoA50IQAzAQABAAgJoA50IQAzAQAAAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAUJCgAGAAkTAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Caltora:BAAALgAECgIJAgAAAA==.Cannelle:BAABLgAECn8XAAIEAAcJjwbkeAAfAQAEAAcJjwbkeAAfAQAAAA==.Carden:BAABLgAECn8aAAMGAAYJdx/nCwC2AQAGAAYJdx/nCwC2AQAJAAEJzwpvHwE3AAAAAA==.Carimknight:BAAALgAECgQJBgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8WAAIKAAgJFiR1CwAmAwAKAAgJFiR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAABLgAECn8UAAIJAAcJZATpdwDyAAAJAAcJZATpdwDyAAAAAA==.Chillywillie:BAABLgAECn8YAAILAAYJow+yJwA6AQALAAYJow+yJwA6AQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgADCgcJBwAAAA==.Chrodne:BAAALgAECgEJAgAAAA==.Chromax:BAAALgADCgUJBQAAAA==.Chucknorrîs:BAAALgAECgEJAgAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBgAAAA==.Cleptodog:BAAALgAECgkJAwAAAA==.Clintbarton:BAAALgAECgQJBQAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgUJBwAAAA==.',
Ct='Cthullu:BAABLgAFFH8KAAIGAAUJCROGFQCnAAAGAAUJCROGFQCnAAAAAA==.',
['Cø']='Cøldshoulder:BAABLgAECn8XAAIJAAcJYxwUPgCEAQAJAAcJYxwUPgCEAQAAAA==.',
Da='Dabi:BAAALgAECgMJCAAAAA==.Daemon:BAAALgAECgcJEgAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAABLgAECn8wAAQMAAkJ+xy9EABfAgAMAAkJ+xy9EABfAgANAAQJXxLWKAAfAQAOAAEJshnYFQBCAAAAAA==.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Dayday:BAAALgAECgIJAgABLgAECggJEQADAAAAAA==.',
De='Deathsend:BAABLgAECn8VAAIJAAUJnQNcnwCiAAAJAAUJnQNcnwCiAAAAAA==.Decamoose:BAAALgAECgYJCwAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAAALgAFFAIJBAAAAA==.Deepstate:BAAALgAECgIJAgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgYJDQABLgAFFAMJBwAIAGQVAA==.Demonaholio:BAAALgAECgEJAQABLgAECggJHgABAKAOAA==.Demonicade:BAABLgAECn8eAAMMAAgJQQsBRgBXAQAMAAcJQQsBRgBXAQANAAEJAABbdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.',
Di='Dima:BAABLgAECn8oAAIPAAgJDiCjCwCDAgAPAAgJDiCjCwCDAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgMJAwAAAA==.',
Dn='Dne:BAABLgAECn8jAAIJAAgJUA9yYgDMAQAJAAgJUA9yYgDMAQAAAA==.',
Do='Donavon:BAABLgAECn8rAAIFAAkJuyA0AwAQAwAFAAkJuyA0AwAQAwAAAA==.Dornnbryda:BAAALgAECggJEAAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn8kAAQQAAgJISE9BQCPAQARAAcJIh2TFAChAQAQAAYJxyE9BQCPAQASAAYJuAV8FQDrAAAAAA==.Drecarus:BAAALgAECggJEwAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAUJCgAGAAkTAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Ec='Echidna:BAAALgADCggJDQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgcJEwAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8VAAMLAAcJpRQXRwCIAQALAAcJpRQXRwCIAQATAAEJYwKORwAPAAAAAA==.',
Es='Estinzione:BAAALgADCgYJBgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAAALgAECgYJEQAAAA==.',
['Eö']='Eöath:BAAALgAECgQJBgAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgADCgcJDAAAAA==.Feltank:BAAALgADCgEJAQABLgAFFAUJCgAGAAkTAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCgAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8WAAIBAAgJZQ+UFQCUAQABAAgJZQ+UFQCUAQAAAA==.',
Ga='Gailinn:BAAALgAECgQJBgAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAAALgAECggJEwAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8fAAIUAAgJORq3FAAPAgAUAAgJORq3FAAPAgAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJBwABLgAFFAMJBwAIAGQVAA==.Grimmlockk:BAAALgAECgUJCQABLgAFFAYJFAAKAJIcAA==.Grimroc:BAAALgADCgMJAwAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8nAAIVAAgJhwz6EgA4AQAVAAgJhwz6EgA4AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCgYJBgABLgADCgkJGAADAAAAAA==.',
Ha='Hanuufalem:BAAALgAECgYJDAAAAA==.Hassad:BAAALgADCgcJDQAAAA==.',
He='Healaton:BAAALgAECggJDwAAAA==.Healmonger:BAABLgAECn8WAAMWAAgJ0g3iGgB0AQAWAAgJ0g3iGgB0AQABAAUJjgQVPACOAAAAAA==.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAABLgAFFH8FAAMJAAMJMwrtWADVAAAJAAMJMwrtWADVAAAXAAEJEQLwCgA/AAAAAA==.',
Hi='Hilgasmic:BAAALgAECgYJCQAAAA==.',
Ho='Hohenhaim:BAAALgAECgcJDgAAAA==.Holly:BAAALgAECgYJCAAAAA==.Holykal:BAEBLgAECn8gAAIYAAgJDB4yEgBpAgAYAAgJDB4yEgBpAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH8eAAIWAAYJvAIDBgBoAQAWAAYJvAIDBgBoAQAuAAQKfzsAAhYACQnvFtYIAF8CABYACQnvFtYIAF8CAAAA.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgMJBwAAAA==.Jarixx:BAAALgAECgEJAgAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8YAAIZAAgJ8xeyDADVAQAZAAgJ8xeyDADVAQAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8ZAAIKAAYJAyC7BADyAQAKAAYJAyC7BADyAQAuAAQKfzQAAwoACQmUJUMBAFYDAAoACQmUJUMBAFYDAAcABwmMJE0JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgADCgYJBgAAAA==.Kaho:BAAALgAECgQJBgAAAA==.Karkas:BAAALgAECgUJCQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8fAAMJAAgJrAozQwBzAQAJAAgJwAkzQwBzAQAXAAIJQw5fEABxAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECggJHAAVAGIVAA==.Kayroonrangi:BAAALgAECgEJAgAAAA==.',
Ke='Kearyn:BAABLgAECn8cAAMVAAgJYhV/CwCvAQAVAAgJYhV/CwCvAQALAAQJIgpUOwDWAAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgADCgkJCQAAAA==.Kevrad:BAAALgADCgYJBgAAAA==.',
Kh='Khephris:BAABLgAECn8fAAIEAAYJ4BOOYwBKAQAEAAYJ4BOOYwBKAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn8oAAIEAAgJcyJbDQCzAgAEAAgJcyJbDQCzAgAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCggJCAAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.Lazulion:BAAALgADCgIJAgAAAA==.',
Le='Leap:BAABLgAECn8UAAIaAAkJaA68BgCOAQAaAAkJaA68BgCOAQAAAA==.Leonîdas:BAAALgAECgEJAQAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJBgAAAA==.Lightrider:BAAALgAECgUJBQAAAA==.Lionroar:BAACLgAFFH8UAAIbAAUJ+heaCwCHAQAbAAUJ+heaCwCHAQAuAAQKfy0AAxsACAlhIXgSAKICABsACAlhIXgSAKICABwABgnqFTg1AGkBAAAA.',
Ll='Llaothtaed:BAAALgAECgkJBgAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAECgkJIAAdAO4XAA==.Lorellei:BAABLgAECn8XAAIWAAYJ7A/EIwArAQAWAAYJ7A/EIwArAQAAAA==.Lothgow:BAAALgAECgIJAwAAAA==.Lourdes:BAABLgAECn8VAAIEAAgJXQLNkwDrAAAEAAgJXQLNkwDrAAAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAUJCgAGAAkTAA==.',
Ma='Magchro:BAAALgADCgEJAQAAAA==.Maggzz:BAAALgAECgEJAgAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJCAAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn8gAAIYAAgJuSArDAChAgAYAAgJuSArDAChAgAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgYJFwAFAGEcAA==.Mewzi:BAAALgAECgQJCQAAAA==.',
Mi='Miah:BAABLgAECn8cAAIeAAYJaxaWCwA0AQAeAAYJaxaWCwA0AQAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAECgIJBwADAAAAAA==.Milkmissile:BAAALgADCgkJDgAAAA==.Milkyflower:BAAALgAECgYJEgAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAABLgAECn8rAAMMAAgJRh+jGgAQAgAMAAYJbSCjGgAQAgANAAIJXBh9QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgMJAwAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCgcJBwAAAA==.',
Mu='Muffinn:BAABLgAECn8ZAAIPAAgJWwcJUAB5AQAPAAgJWwcJUAB5AQAAAA==.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECggJEQAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAAALgAECgUJCAAAAA==.',
Na='Nala:BAACLgAFFH8GAAILAAIJABBfIgCdAAALAAIJABBfIgCdAAAuAAQKfyEAAgsACQk5IP0CAOYCAAsACQk5IP0CAOYCAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8UAAQWAAcJ6xStHQBcAQAWAAcJ6xStHQBcAQACAAIJhwRoUQBGAAABAAEJYQPWaAAnAAAAAA==.',
Ni='Niame:BAAALgAECgYJEgAAAA==.Nitraina:BAAALgADCgUJBgAAAA==.Niyabelle:BAABLgAECn8YAAIZAAcJJBc1EACjAQAZAAcJJBc1EACjAQAAAA==.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.',
Oa='Oakmane:BAAALgAECgcJDgAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECgYJCgADAAAAAA==.Okinawa:BAAALgAECgEJAQAAAA==.',
Ol='Oleevia:BAABLgAECn8cAAIBAAgJvhXIDgDgAQABAAgJvhXIDgDgAQAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAMJBwAIAGQVAA==.Oreiel:BAAALgADCgIJAgAAAA==.Orgdh:BAACLgAFFH8bAAIKAAYJmRQtDQCJAQAKAAYJmRQtDQCJAQAuAAQKfzIAAgoACQkrIU8FANgCAAoACQkrIU8FANgCAAAA.Orgdynamite:BAAALgAECgUJCAAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgMJAwAAAA==.Paladareian:BAABLgAECn8oAAMFAAgJyxejDwAjAgAFAAgJyxejDwAjAgAYAAEJJQWfGAEpAAAAAA==.Pandalin:BAAALgAECgYJCQABLgAECgYJCgADAAAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAYJGQAKAAMgAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECgcJCAAAAA==.',
Pi='Pinheadd:BAAALgAECgUJCQAAAA==.Pink:BAAALgADCgYJBgAAAA==.',
Pm='Pmsm:BAAALgAECgQJBwAAAA==.',
Po='Powerslavé:BAAALgAECgYJEAABLgAFFAMJBgAEAJoQAA==.',
Pr='Priestitoot:BAAALgAECgQJBgAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.',
Qu='Quadzilla:BAAALgADCgUJCAAAAA==.Qudenos:BAAALgAECgcJCwAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJDwAAAA==.Raiden:BAABLgAECn8bAAIYAAYJJAsbbwAPAQAYAAYJJAsbbwAPAQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgcJDAAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgQJBgAAAA==.',
Ri='Riels:BAAALgAECgEJAgAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAMJBwAIAGQVAA==.Rockbìter:BAABLgAFFH8HAAIIAAMJZBV2FQDeAAAIAAMJZBV2FQDeAAAAAA==.Rockthyr:BAAALgAECgQJBQABLgAFFAMJBwAIAGQVAA==.Rojas:BAAALgAECgcJDwAAAA==.',
['Ré']='Réåper:BAABLgAECn8VAAIYAAgJog9MQwB8AQAYAAgJog9MQwB8AQAAAA==.',
['Rö']='Römana:BAABLgAECn8VAAIPAAYJmxFPSgAuAQAPAAYJmxFPSgAuAQAAAA==.',
Sa='Saaran:BAAALgAECgYJCgAAAA==.Sandoriel:BAAALgADCgcJCgAAAA==.Sapmedaddy:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Sathenasand:BAAALgAECgYJEgAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJCgAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn8oAAIEAAgJ4xp7HgAzAgAEAAgJ4xp7HgAzAgAAAA==.',
Sh='Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAAALgAECgUJCQAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAECggJHgABAKAOAA==.Shatterfrost:BAABLgAECn8dAAMfAAYJSBmECgA1AQAEAAYJdRbdWABjAQAfAAUJIBOECgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAECgcJCgADAAAAAA==.Shirraz:BAAALgADCgkJEQAAAA==.',
Si='Sicksdeep:BAACLgAFFH8JAAMTAAMJPggkDgDGAAATAAMJxAckDgDGAAALAAIJXgULLQBMAAAuAAQKfx0AAxMACAncFvYJAAsCABMACAncFvYJAAsCAAsABQltCZRsAAQBAAAA.Silverstorm:BAAALgAECgYJCwAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgIJAgAAAA==.Skewpin:BAAALgADCgQJBAAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn8lAAIeAAgJeCGDAQClAgAeAAgJeCGDAQClAgAAAA==.',
Sl='Slamma:BAACLgAFFH8aAAILAAYJBSWFAAANAgALAAYJBSWFAAANAgAuAAQKfzQAAwsACQnBJjQAAPgDAAsACQnBJjQAAPgDABMAAQmVIpwvAGIAAAAA.Slicedbread:BAACLgAFFH8QAAIIAAYJ5BF5BwCvAQAIAAYJ5BF5BwCvAQAuAAQKfyQABAgACQnqHLcGAJQCAAgACAl7HbcGAJQCACAABgkNIeQVAIoBACEAAQniF4BSAEYAAAEuAAUUBQkMAAUAVCEA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgEJAQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgUJBQAAAA==.Sols:BAACLgAFFH8GAAIEAAMJmhBPRwD7AAAEAAMJmhBPRwD7AAAuAAQKfxsAAgQACQkEGxIcAEICAAQACQkEGxIcAEICAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgADCgQJBgAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgQJBgAAAA==.Speoghii:BAAALgAECgYJEgAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAAALgAECgYJCwAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAAALgAECgUJCgAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMQpzGgBoAQABAAgJMQpzGgBoAQACAAcJ4QodNQD7AAAWAAIJdQQfdQBVAAAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgQJBwAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAIJBgALAAAQAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAAALgAECggJEQAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Taurriel:BAABLgAECn8dAAIPAAgJphkEGQAJAgAPAAgJphkEGQAJAgAAAA==.Tazzm:BAAALgAECgYJBgAAAA==.',
Te='Teranok:BAABLgAECn8gAAIhAAkJsSA7AgD5AgAhAAkJsSA7AgD5AgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8mAAIdAAkJOyNoAABEAwAdAAkJOyNoAABEAwAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Them:BAAALgAECgcJEQAAAA==.Thoir:BAACLgAFFH8eAAIUAAYJLyEjAQD/AQAUAAYJLyEjAQD/AQAuAAQKfzwAAhQACQl3JPwAAJgDABQACQl3JPwAAJgDAAEuAAUUBgkeABYAvAIA.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgADCgEJAQAAAA==.Tickells:BAABLgAECn8pAAMBAAkJIw1hEADLAQABAAkJIw1hEADLAQACAAYJLwVSNQD6AAAAAA==.Tipsylorcet:BAABLgAECn8jAAIgAAgJPRm2CwAGAgAgAAgJPRm2CwAGAgAAAA==.Tirohunt:BAAALgAECgUJCQAAAA==.',
Tr='Tricktìckler:BAAALgAECgMJAwAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgADCgIJAgABLgADCggJFAADAAAAAA==.Turiell:BAAALgAECgEJAQAAAA==.',
Ty='Tybird:BAABLgAECn8dAAIXAAgJryG1AQBUAgAXAAgJryG1AQBUAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAYJHgABAGcdAA==.Ulyssi:BAACLgAFFH8eAAIBAAYJZx0lAgDcAQABAAYJZx0lAgDcAQAuAAQKfzsAAgEACQkIJbkAAFwDAAEACQkIJbkAAFwDAAAA.',
Va='Valethara:BAAALgADCgIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgYJCAAAAA==.Ven:BAABLgAECn8jAAIBAAcJrQczJAAhAQABAAcJrQczJAAhAQAAAA==.Venturecap:BAAALgAECgIJBwAAAA==.Verxina:BAABLgAECn8YAAIiAAgJFBukCgD4AQAiAAgJFBukCgD4AQAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgAECgQJBgAAAA==.Vondeuce:BAAALgADCgYJBgAAAA==.',
Vu='Vullrog:BAABLgAECn8lAAIeAAgJKxXNCQBbAQAeAAgJKxXNCQBbAQAAAA==.',
We='Weehunt:BAABLgAECn8YAAIPAAgJhhlzIADaAQAPAAgJhhlzIADaAQAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn8mAAIUAAgJKyRYAwAaAwAUAAgJKyRYAwAaAwAAAA==.Widowfang:BAAALgAECgUJCgAAAA==.Wikka:BAAALgAECgUJCAAAAA==.Wildriver:BAABLgAECn8cAAIbAAcJ7SDvCgCaAgAbAAcJ7SDvCgCaAgAAAA==.',
Xa='Xaehyun:BAACLgAFFH8eAAMhAAYJjCP9AQCpAQAhAAQJiyT9AQCpAQAIAAIJyiTRFQDYAAAuAAQKfzwAAyEACQnPJhAAAAoEACEACQnPJhAAAAoEAAgABQlEHUshAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQaAAYJiiA3BQDDAQAaAAUJiiA3BQDDAQAHAAUJhB0oKgBzAQAKAAQJoRKmmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8vAAMjAAgJ8guMHgBZAQAjAAgJ8guMHgBZAQAUAAMJkQN2iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8eAAIGAAYJdRrEAwCkAQAGAAYJdRrEAwCkAQAuAAQKfzsAAgYACQmZIscBAPICAAYACQmZIscBAPICAAAA.Xmrpmonk:BAAALgAECgcJEgABLgAFFAYJHgAGAHUaAA==.',
Xo='Xohan:BAABLgAECn8qAAILAAkJBCB9AgD1AgALAAkJBCB9AgD1AgAAAA==.',
Xy='Xyr:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAAALgAFFAEJAQAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAQAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8eAAISAAYJaR22AgAeAgASAAYJaR22AgAeAgAuAAQKfzwAAxIACQn/IvwAAFMDABIACQn/IvwAAFMDABAABQkeHcsJAAUBAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAIJBgALAAAQAA==.Zanne:BAACLgAFFH8LAAIeAAMJJRnsCwD9AAAeAAMJJRnsCwD9AAAuAAQKfx4AAh4ACAlMHfUZAFsCAB4ACAlMHfUZAFsCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgADCgcJGAAAAA==.',
Ze='Zehara:BAAALgAECgcJEgAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH8eAAQPAAYJNSB0AwBmAQAPAAUJQh90AwBmAQAeAAQJbhMZGADTAAAiAAIJhQ5uFgCjAAAuAAQKfzwABA8ACQlOJsoAAGUDAA8ACQkyJsoAAGUDAB4ABwkaIC8YAGsCACIAAgmEGo0pAKwAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAAALgAECggJEAAAAA==.',
['Úl']='Úlfa:BAAALgAECgcJDgAAAA==.',
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

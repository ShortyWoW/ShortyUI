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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Shaman-Restoration','Warrior-Protection','Paladin-Retribution','DemonHunter-Vengeance','Priest-Holy','Rogue-Subtlety','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','Hunter-Survival','Shaman-Elemental','Evoker-Preservation',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaralia:BAABLgAECn8cAAMBAAcJ7h7lEgBfAgABAAcJ7h7lEgBfAgACAAEJ/BBlNgA2AAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgADCgIJAwAAAA==.',
Ad='Adarae:BAAALgAECgYJCgAAAA==.Ademal:BAAALgADCgUJBQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAQAAAA==.Aerwen:BAAALgAECgYJDAAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgcJDQADAAAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgYJHQAEAOETAA==.Alearia:BAAALgADCgEJAQAAAA==.Alewynt:BAAALgAECgEJAwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgADCgYJCQAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgMJBQAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgADCgYJBgAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJAwAAAA==.Arîane:BAAALgAECgEJAQAAAA==.',
As='Asapferg:BAAALgAECgcJBwAAAA==.Ashaman:BAABLgAECn8bAAICAAYJwgUzIQDLAAACAAYJwgUzIQDLAAAAAA==.Astanah:BAABLgAECn8ZAAIFAAcJHBadGgB3AQAFAAcJHBadGgB3AQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgEJAgAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAQJCAAGAAITAA==.',
Be='Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAAALgAECgYJDgAAAA==.Bloodedge:BAAALgAECggJEwAAAA==.',
Bo='Bobbyswagger:BAAALgAECgUJBgAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Brentobox:BAABLgAECn8UAAIHAAYJfiLXBgBRAgAHAAYJfiLXBgBRAgAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgQJBgAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.',
Bu='Bungeholio:BAABLgAECn8cAAIBAAgJUg7jGAA3AQABAAgJUg7jGAA3AQAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Caltora:BAAALgAECgIJAgAAAA==.Cannelle:BAAALgAECgcJEQAAAA==.Carden:BAABLgAECn8UAAMGAAYJmR58BwCnAQAGAAYJmR58BwCnAQAIAAEJzwphHwE3AAAAAA==.Carimknight:BAAALgAECgQJBAAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8WAAIJAAgJFiR7CwAmAwAJAAgJFiR7CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAAALgAECgYJDQAAAA==.Chillywillie:BAABLgAECn8WAAIKAAYJhA4SHgBBAQAKAAYJhA4SHgBBAQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgADCgcJBwAAAA==.Chrodne:BAAALgAECgEJAQAAAA==.Chromax:BAAALgADCgUJBQAAAA==.Chucknorrîs:BAAALgADCgEJAQAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBAAAAA==.Clintbarton:BAAALgAECgMJBAAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgQJBgAAAA==.',
Ct='Cthullu:BAABLgAFFH8IAAIGAAQJAhMADwCxAAAGAAQJAhMADwCxAAAAAA==.',
['Cø']='Cøldshoulder:BAABLgAECn8XAAIIAAcJYhwEKgCUAQAIAAcJYhwEKgCUAQAAAA==.',
Da='Dabi:BAAALgAECgMJBgAAAA==.Daemon:BAAALgAECgcJEgAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAABLgAECn8kAAQLAAgJnhsAJACDAgALAAgJnhsAJACDAgAMAAQJXxLbKAAfAQANAAEJuRloDgBMAAAAAA==.Dayday:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.',
De='Deathsend:BAAALgAECgUJEQAAAA==.Decamoose:BAAALgAECgYJBgAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAAALgAFFAIJAwAAAA==.Deepstate:BAAALgAECgEJAQAAAA==.Deidamia:BAAALgAECgEJAQAAAA==.Deimosz:BAAALgAECgYJDAABLgAFFAMJBAADAAAAAA==.Demonaholio:BAAALgAECgEJAQABLgAECggJHAABAFIOAA==.Demonicade:BAABLgAECn8WAAMLAAYJeQ1BTgAGAQALAAUJeQ1BTgAGAQAMAAEJAABbdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.',
Di='Dima:BAABLgAECn8gAAIOAAgJIBwwCwBMAgAOAAgJIBwwCwBMAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgADCgkJKAAAAA==.',
Dn='Dne:BAABLgAECn8iAAIIAAgJUA92YgDMAQAIAAgJUA92YgDMAQAAAA==.',
Do='Donavon:BAABLgAECn8oAAIFAAgJeSDTAwDDAgAFAAgJeSDTAwDDAgAAAA==.Dornnbryda:BAAALgAECgYJCAAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn8cAAMPAAYJ+CEqBACRAQAPAAYJwiEqBACRAQAQAAYJ8B0dFQBXAQAAAA==.Drecarus:BAAALgAECgcJDQAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAQJCAAGAAITAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Ec='Echidna:BAAALgADCggJDQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgUJDQAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAAALgAECgcJEAAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAAALgAECgYJEQAAAA==.',
['Eö']='Eöath:BAAALgAECgQJBgAAAA==.',
Fa='Falaurenta:BAAALgAECgUJCgAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgADCgcJDAAAAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCQAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAAALgAECgUJDgAAAA==.',
Ga='Gailinn:BAAALgAECgMJAwAAAA==.Galreth:BAAALgAECgIJBQAAAA==.Ganon:BAAALgAECggJEgAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8XAAIRAAgJqxeAKgAfAQARAAgJqxeAKgAfAQAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgEJAQABLgAFFAMJBAADAAAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8dAAISAAgJagwfGwBzAQASAAgJagwfGwBzAQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.',
Ha='Hanuufalem:BAAALgAECgYJDAAAAA==.Hassad:BAAALgADCgcJDQAAAA==.',
He='Healaton:BAAALgAECgcJDQAAAA==.Healmonger:BAAALgAECgYJDgAAAA==.Healpants:BAAALgAECgcJBQAAAA==.Heruin:BAAALgAFFAMJBAAAAA==.',
Hi='Hilgasmic:BAAALgAECgYJCAAAAA==.',
Ho='Hohenhaim:BAAALgAECgYJCwAAAA==.Holly:BAAALgAECgMJBQAAAA==.Holykal:BAEBLgAECn8YAAITAAYJXCKhGAD3AQATAAYJXCKhGAD3AQAAAA==.Hope:BAAALgADCgYJBgABLgAECgYJHAAUAIkgAA==.Horse:BAACLgAFFH8YAAIVAAYJQQJNBABkAQAVAAYJQQJNBABkAQAuAAQKfzgAAhUACQnaFv8EAHoCABUACQnaFv8EAHoCAAAA.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgMJBwAAAA==.Jarixx:BAAALgAECgEJAgAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8WAAIWAAcJHBi1DACeAQAWAAcJHBi1DACeAQAAAA==.',
Ju='Jun:BAACLgAFFH8TAAIJAAYJuR+AAgDZAQAJAAYJuR+AAgDZAQAuAAQKfy8AAwkACQmAJa0AAFYDAAkACQmAJa0AAFYDABcABwmMJE8JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kaho:BAAALgAECgMJBAAAAA==.Karkas:BAAALgAECgQJBAAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8aAAIIAAgJswgaNABpAQAIAAgJswgaNABpAQAAAA==.Kateera:BAAALgAECgYJCQABLgAECggJFAASALwTAA==.Kayroonrangi:BAAALgAECgEJAQAAAA==.',
Ke='Kearyn:BAABLgAECn8UAAMSAAgJvBNhHQBbAQASAAgJvBNhHQBbAQAKAAQJEQqJLQDgAAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kevrad:BAAALgADCgYJBgAAAA==.',
Kh='Khephris:BAABLgAECn8dAAIEAAYJ4RMJTABLAQAEAAYJ4RMJTABLAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn8gAAIEAAgJeyG3DQByAgAEAAgJeyG3DQByAgAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCggJCAAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgEJAwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.',
Le='Leap:BAAALgAECgkJDwABLgAFFAIJAwADAAAAAA==.Leonîdas:BAAALgAECgEJAQAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgUJBQAAAA==.Lightrider:BAAALgAECgQJBQAAAA==.Lionroar:BAACLgAFFH8QAAIYAAUJ/BcRBwCPAQAYAAUJ/BcRBwCPAQAuAAQKfy0AAxgACAldIXsSAKICABgACAldIXsSAKICABkABgnqFTU1AGkBAAAA.',
Ll='Llaothtaed:BAAALgAECgcJAQAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lorellei:BAAALgAECgYJEQAAAA==.Lothgow:BAAALgADCgQJBAAAAA==.Lourdes:BAAALgAECgYJDQAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAgABLgAFFAQJCAAGAAITAA==.',
Ma='Maggzz:BAAALgAECgEJAgAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJBwAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn8YAAITAAgJoh4xDQBaAgATAAgJoh4xDQBaAgAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgUJEAADAAAAAA==.Mewzi:BAAALgAECgQJCQAAAA==.',
Mi='Miah:BAABLgAECn8WAAIaAAYJfhSZCwAVAQAaAAYJfhSZCwAVAQAAAA==.Miip:BAAALgADCgYJCgAAAA==.Milkmissile:BAAALgADCgcJBwAAAA==.Milkyflower:BAAALgAECgYJDAAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAABLgAECn8lAAMLAAgJnh5FFQD7AQALAAYJsR9FFQD7AQAMAAIJLBh5QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgADCgkJKAAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCgcJBwAAAA==.',
Mu='Muffinn:BAAALgAECggJEwAAAA==.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECggJEQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgUJCQAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAAALgAECgMJAwAAAA==.',
Na='Nala:BAABLgAECn8gAAIKAAgJpR+yAwCTAgAKAAgJpR+yAwCTAgAAAA==.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAAALgAECgUJEQAAAA==.',
Ni='Niame:BAAALgAECgYJDwAAAA==.Nitraina:BAAALgADCgUJBgAAAA==.Niyabelle:BAAALgAECgcJEgAAAA==.',
No='Noether:BAAALgAECggJDgAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.',
Oa='Oakmane:BAAALgAECgQJBwAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECgYJCgADAAAAAA==.',
Ol='Oleevia:BAABLgAECn8bAAIBAAgJLBQcCwDNAQABAAgJLBQcCwDNAQAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAMJBAADAAAAAA==.Oreiel:BAAALgADCgIJAgAAAA==.Orgdh:BAACLgAFFH8VAAIJAAYJgxRDBgCNAQAJAAYJgxRDBgCNAQAuAAQKfy8AAgkACQkzISsDAMgCAAkACQkzISsDAMgCAAAA.Orgdynamite:BAAALgAECgQJBwAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgADCgkJKAAAAA==.Paladareian:BAABLgAECn8cAAMFAAgJuxVWCwAhAgAFAAgJuxVWCwAhAgATAAEJJAXb2gAtAAAAAA==.Pandalin:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.',
Pe='Pejbolt:BAAALgAECgYJDgABLgAFFAYJEwAJALkfAA==.Pennywiseit:BAAALgAECgEJAQAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECgYJBwAAAA==.',
Pi='Pinheadd:BAAALgAECgUJCQAAAA==.Pink:BAAALgADCgYJBgAAAA==.',
Pm='Pmsm:BAAALgAECgQJBQAAAA==.',
Po='Powerslavé:BAAALgAECgYJEAABLgAECgYJFQAEAAEeAA==.',
Pr='Priestitoot:BAAALgAECgQJBgAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.',
Qu='Quadzilla:BAAALgADCgMJAwAAAA==.Qudenos:BAAALgAECgcJCwAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJDwAAAA==.Raiden:BAABLgAECn8ZAAITAAYJCgtfUgAWAQATAAYJCgtfUgAWAQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgcJCgAAAA==.Revoker:BAAALgADCgcJFQABLgAECgYJHAAUAIkgAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgIJAgAAAA==.',
Ri='Riels:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAMJBAADAAAAAA==.Rockbìter:BAAALgAFFAMJBAAAAA==.Rockthyr:BAAALgAECgQJBQABLgAFFAMJBAADAAAAAA==.Rojas:BAAALgAECgQJBAAAAA==.',
['Ré']='Réåper:BAAALgAECggJEQAAAA==.',
['Rö']='Römana:BAAALgAECgYJDwAAAA==.',
Sa='Saaran:BAAALgAECgYJCgAAAA==.Sandoriel:BAAALgADCgcJCgAAAA==.Sathenasand:BAAALgAECgYJEgABLgAECggJFAAIALYaAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJCgAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn8gAAIEAAgJ0RmnFgAnAgAEAAgJ0RmnFgAnAgAAAA==.',
Sh='Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAAALgAECgUJBQAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAECggJHAABAFIOAA==.Shatterfrost:BAABLgAECn8bAAMbAAYJURmDCgA1AQAbAAUJIBODCgA1AQAEAAYJgxZcbwD6AAAAAA==.Shayd:BAAALgAECgYJBwABLgAECgYJHAAUAIkgAA==.Shiggles:BAAALgAECgQJBAAAAA==.Shirraz:BAAALgADCgkJEQAAAA==.',
Si='Sicksdeep:BAACLgAFFH8JAAMcAAMJPgilCADWAAAcAAMJxAelCADWAAAKAAIJXgXOIwBNAAAuAAQKfxsAAxwABwlKGPgJAAsCABwABwlKGPgJAAsCAAoABQltCZNsAAQBAAAA.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgIJAgAAAA==.Skewpin:BAAALgADCgQJBAAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn8dAAIaAAgJERrqCgAhAQAaAAgJERrqCgAhAQAAAA==.',
Sl='Slamma:BAACLgAFFH8UAAIKAAYJgCFBAAAAAgAKAAYJgCFBAAAAAgAuAAQKfy8AAwoACQl5JjQAAPgDAAoACQl5JjQAAPgDABwAAQmpIvMiAGMAAAAA.Slicedbread:BAACLgAFFH8JAAIHAAUJPBEiCABjAQAHAAUJPBEiCABjAQAuAAQKfxwAAwcABwmrH34GAFoCAAcABwmrH34GAFoCAB0ABQlTIVMmANEBAAEuAAUUBQkMAAUATiEA.',
Sm='Smokadaganga:BAAALgAECgYJCgAAAA==.',
Sn='Snoball:BAAALgAECgEJAQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Sols:BAABLgAECn8VAAIEAAYJAR5NLwCmAQAEAAYJAR5NLwCmAQAAAA==.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgADCgQJBgAAAA==.',
Sp='Spatula:BAAALgADCgYJCQAAAA==.Speoghii:BAAALgAECgYJDAAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAAALgAECgUJCQAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAAALgAECgMJBQAAAA==.Stillfrazier:BAABLgAECn8VAAQBAAcJ6QabHAAXAQABAAcJ6QabHAAXAQACAAYJUQsfNQD7AAAVAAIJdQQZdQBVAAAAAA==.',
Su='Subcintus:BAAALgADCgIJAgAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgMJAwAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAECggJIAAKAKUfAA==.',
['Sö']='Söphie:BAAALgAECgkJBgAAAA==.',
Ta='Tainema:BAAALgAECgYJCwAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Taurriel:BAABLgAECn8dAAIOAAgJpRl8DgAmAgAOAAgJpRl8DgAmAgAAAA==.Tazzm:BAAALgAECgYJBgAAAA==.',
Te='Teranok:BAABLgAECn8bAAIeAAgJSSKBAgC1AgAeAAgJSSKBAgC1AgAAAA==.Terozon:BAAALgAECgYJCgAAAA==.',
Th='Tharianrex:BAABLgAECn8fAAIfAAgJCCSZAADoAgAfAAgJCCSZAADoAgAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Them:BAAALgAECgYJDgAAAA==.Thoir:BAACLgAFFH8YAAIRAAYJTSAhAQASAgARAAYJTSAhAQASAgAuAAQKfzkAAhEACQl3JPsAAJgDABEACQl3JPsAAJgDAAEuAAUUBgkYABUAQQIA.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgADCgEJAQAAAA==.Tickells:BAABLgAECn8gAAMBAAgJ0gwrEQCAAQABAAgJ0gwrEQCAAQACAAYJLwVUNQD6AAAAAA==.Tipsylorcet:BAABLgAECn8bAAIdAAYJgxtCEACQAQAdAAYJgxtCEACQAQAAAA==.Tirohunt:BAAALgAECgMJBAAAAA==.',
Tr='Tricktìckler:BAAALgADCgkJKAAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECgYJDQAAAA==.Turiell:BAAALgADCgkJEwAAAA==.',
Ty='Tybird:BAABLgAECn8VAAIgAAgJyx87AgDpAQAgAAgJyx87AgDpAQAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECgcJGQAFABwWAA==.',
['Tø']='Tøuchmeeh:BAAALgAECggJCQAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAYJGAABAPMcAA==.Ulyssi:BAACLgAFFH8YAAIBAAYJ8xzyAADaAQABAAYJ8xzyAADaAQAuAAQKfzgAAgEACQn1JE8AAGMDAAEACQn1JE8AAGMDAAAA.',
Va='Valethara:BAAALgADCgIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgEJAgAAAA==.Ven:BAABLgAECn8cAAIBAAYJpwfHIAD1AAABAAYJpwfHIAD1AAAAAA==.Venturecap:BAAALgAECgIJBgAAAA==.Verxina:BAABLgAECn8WAAIhAAYJnR1ADgDjAQAhAAYJnR1ADgDjAQAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgADCgcJCQAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgMJAwADAAAAAA==.',
Vu='Vullrog:BAABLgAECn8cAAIaAAgJCxJ5JgDyAQAaAAgJCxJ5JgDyAQAAAA==.',
We='Weehunt:BAAALgAECgYJEQAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn8eAAIRAAcJ5SQiBADAAgARAAcJ5SQiBADAAgAAAA==.Widowfang:BAAALgAECgUJCgAAAA==.Wikka:BAAALgAECgIJAwAAAA==.Wildriver:BAAALgAECgUJEAAAAA==.',
Xa='Xaehyun:BAACLgAFFH8YAAMeAAYJVyMcAQCpAQAeAAQJSSQcAQCpAQAHAAIJVSTzDwDYAAAuAAQKfzkAAx4ACQnLJggAAJsDAB4ACQnLJggAAJsDAAcABQlEHUghAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQUAAYJiSC/AwDOAQAUAAUJiSC/AwDOAQAXAAUJhB0kKgBzAQAJAAQJoRKhmwDhAAAAAA==.Xanni:BAABLgAECn8sAAMiAAgJ7gsLFgBlAQAiAAgJ7gsLFgBlAQARAAMJkQOCiQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8YAAIGAAYJvxc8AwB+AQAGAAYJvxc8AwB+AQAuAAQKfzgAAgYACQmZIh4BAJUCAAYACQmZIh4BAJUCAAAA.Xmrpmonk:BAAALgAECgYJDgABLgAFFAYJGAAGAL8XAA==.',
Xo='Xohan:BAABLgAECn8pAAIKAAkJ/h/oAAAXAwAKAAkJ/h/oAAAXAwAAAA==.',
Xy='Xyr:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAAALgAFFAEJAQAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAQAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8YAAIjAAYJUxxxAQAdAgAjAAYJUxxxAQAdAgAuAAQKfzgAAyMACQn6IpQAAFwDACMACQn6IpQAAFwDAA8ABQkXHb0HAA0BAAAA.Zamosc:BAAALgADCgEJAQABLgAECggJIAAKAKUfAA==.Zanne:BAACLgAFFH8IAAIaAAMJNBCLCQDlAAAaAAMJNBCLCQDlAAAuAAQKfxwAAhoACAkyHY8ZAFsCABoACAkyHY8ZAFsCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgADCgcJEgAAAA==.',
Ze='Zehara:BAAALgAECgcJDQAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH8YAAQOAAYJzR51AwBmAQAOAAQJgR11AwBmAQAaAAQJbBMTGADTAAAhAAIJcQ65DwCkAAAuAAQKfzgABA4ACQkVJksAAHEDAA4ACQn5JUsAAHEDABoABwkaINgXAGsCACEAAgmDGskeALAAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAAALgAECgYJCQAAAA==.',
['Úl']='Úlfa:BAAALgAECgcJCAAAAA==.',
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

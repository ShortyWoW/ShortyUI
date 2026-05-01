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

local lookup = {'Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Rogue-Assassination','DeathKnight-Unholy','Mage-Frost','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Monk-Brewmaster','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Warrior-Fury','Warrior-Arms','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ag='Agonie:BAAALgAECgEJAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAECggJFgABAIQfAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgADCgcJGgAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8HAAICAAMJuSGkEQAfAQACAAMJuSGkEQAfAQAuAAQKfxUAAwIACAl+H0AQALgCAAIACAl+H0AQALgCAAMAAgnUGeIkAKIAAAAA.',
An='Anoiche:BAABLgAECn8OAAIEAAgJwBkmOgAMAgAEAAgJwBkmOgAMAgAAAA==.',
As='Asmodeus:BAACLgAFFH8KAAIEAAQJLxJPEgAwAQAEAAQJLxJPEgAwAQAuAAQKfyIAAgQABwnaGxgvAEACAAQABwnaGxgvAEACAAAA.',
At='Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAFAAAAAA==.',
Av='Avanzo:BAAALgAECgMJAwAAAA==.',
Ax='Axeldaur:BAAALgADCgMJAwAAAA==.Axelrod:BAAALgAECgQJBgAAAA==.',
Az='Azucena:BAAALgAECgMJAwAAAA==.',
Ba='Bananos:BAABLgAECn8dAAMGAAgJOBzzAQC1AgAGAAgJOBzzAQC1AgAHAAMJNQhVpAA+AAAAAA==.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAAALgAFFAIJAgAAAA==.Bertram:BAABLgAECn8VAAIIAAYJSAQILwDCAAAIAAYJSAQILwDCAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgQJBAAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgUJCgAAAA==.Booze:BAABLgAECn8WAAMBAAgJhB9UBQAvAgABAAcJJB9UBQAvAgAJAAIJhhyLDACvAAAAAA==.Borgar:BAAALgAECgQJBwABLgAFFAIJAwAFAAAAAA==.',
Ch='Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAAALgAECgcJEAABLgAFFAQJCQAIAGgJAA==.',
Ci='Cirrce:BAAALgAECgYJBgAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Covenant:BAAALgAECgQJCAAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.',
De='Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAgAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAAALgAECgEJAQAAAA==.',
Di='Disruptive:BAAALgAECgUJBQAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAAALgAECgcJEgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIKAAQJlRAtHAAzAQAKAAQJlRAtHAAzAQAuAAQKfyIAAgoACAnoIAIcANYCAAoACAnoIAIcANYCAAAA.Eco:BAACLgAFFH8HAAILAAMJ/xsCLAAaAQALAAMJ/xsCLAAaAQAuAAQKfxsAAgsACAkuHx05AJECAAsACAkuHx05AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgADCgYJBgABLgADCgcJCwAFAAAAAA==.',
El='Elmono:BAACLgAFFH8RAAILAAUJvBVeIABQAQALAAUJvBVeIABQAQAuAAQKfzAAAgsACQl/H90UACsDAAsACQl/H90UACsDAAAA.Elusivepanda:BAAALgAECgYJEAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAAALgAECgkJDwAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8LAAIMAAQJGxNhDwBAAQAMAAQJGxNhDwBAAQAuAAQKfyYAAwwACAlMJEkEAEsDAAwACAlMJEkEAEsDAAIABgmTDhZNABwBAAAA.',
Es='Espresso:BAAALgADCgcJBwAAAA==.',
Eu='Eucharistica:BAACLgAFFH8JAAIEAAUJ6xbeDABOAQAEAAUJ6xbeDABOAQAuAAQKfzMAAgQACQnKIloCAOsCAAQACQnKIloCAOsCAAAA.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8bAAINAAcJbx9yCADGAQANAAcJbx9yCADGAQABLgAFFAIJAwAFAAAAAA==.Far:BAACLgAFFH8HAAMMAAUJ0w1+DwA/AQAMAAQJ0w1+DwA/AQADAAEJAACQFgAAAAAuAAQKfyYABAwACAl9IBwRALECAAwACAlSIBwRALECAAMABwmRHBMGABACAAIABAmjDtBZANwAAAAA.Fathergoose:BAABLgAECn8gAAMOAAgJ7BkBDwCHAgAOAAgJ7BkBDwCHAgAPAAMJtRFMGQByAAAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8nAAINAAkJOCSMAAAsAwANAAkJOCSMAAAsAwAAAA==.',
Fu='Fuddytotem:BAABLgAECn8XAAMQAAYJdx+2IgAPAgAQAAYJdx+2IgAPAgAIAAYJgRFOTQASAQABLgAECggJFQARAPsNAA==.Funnelcake:BAAALgADCgcJBwAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8VAAIRAAgJ+w1ZFADHAQARAAgJ+w1ZFADHAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJFQARAPsNAA==.Fzyy:BAAALgADCgMJAwABLgAECggJFQARAPsNAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAIJAwAFAAAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAABLgAECn8XAAISAAgJPBF/DAC5AQASAAgJPBF/DAC5AQAAAA==.Goril:BAAALgAFFAIJAwAAAA==.Goryious:BAACLgAFFH8HAAIKAAMJowpILQDmAAAKAAMJowpILQDmAAAuAAQKfx4AAgoACQmbFhJAADgCAAoACQmbFhJAADgCAAAA.',
Gw='Gweg:BAABLgAECn8iAAMDAAgJSx6PBgAEAgAMAAgJwBwIIgA5AgADAAcJNhyPBgAEAgAAAA==.',
Ha='Halarda:BAABLgAECn8WAAMMAAcJCRpBJwB7AQAMAAYJ0h1BJwB7AQACAAUJAhDJUQAFAQAAAA==.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8lAAIQAAgJXBxuKgDkAQAQAAgJXBxuKgDkAQAAAA==.',
Ho='Hooves:BAACLgAFFH8TAAITAAUJphroAQBGAQATAAUJphroAQBGAQAuAAQKfy8AAhMACQkMI/cAAGQDABMACQkMI/cAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn8mAAMUAAgJZBsbDwAeAgAUAAgJZBsbDwAeAgAVAAMJYQ7JKgC2AAAAAA==.',
In='Inukari:BAAALgADCgcJBwAAAA==.Invincible:BAAALgADCgQJBAAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn8rAAMQAAgJGhQOHgBzAQAQAAYJlRUOHgBzAQAWAAgJKgYWDAAbAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAFAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCQABLgAFFAEJAQAFAAAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgcJLQALAG8kAA==.Kamidh:BAAALgADCgkJFQABLgAECgcJLQALAG8kAA==.Kamihunt:BAAALgADCgQJBAABLgAECgcJLQALAG8kAA==.Kamikozy:BAABLgAECn8tAAILAAcJbyRjEQBRAgALAAcJbyRjEQBRAgAAAA==.Kasharas:BAABLgAECn8VAAMQAAcJaA7NIgBQAQAQAAcJaA7NIgBQAQAIAAEJ6QW1kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMXAAcJvyPZHAC9AgAXAAcJvyPZHAC9AgAYAAIJEgXhhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgADCgcJFQAAAA==.Khealer:BAAALgAECgcJDwAAAA==.',
Ki='Kindi:BAAALgAECgYJEgAAAA==.Kitymeowmeow:BAACLgAFFH8LAAIZAAQJnSBzAgCQAQAZAAQJnSBzAgCQAQAuAAQKfysAAhkACQkhJksCAHwDABkACQkhJksCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8JAAIIAAQJaAniDQAcAQAIAAQJaAniDQAcAQAuAAQKfy4AAggACQm+FykaAEICAAgACQm+FykaAEICAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIaAAYJHR9FEACQAQAaAAYJHR9FEACQAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAAALgADCgYJBgABLgAECgcJHQALAIodAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAAALgAECgYJBgAAAA==.',
Li='Lilithe:BAAALgADCgkJCQAAAA==.Lillyvera:BAAALgADCgcJFwAAAA==.Lilpsycho:BAAALgADCgYJDAAAAA==.',
Lo='Lokie:BAAALgAECgMJBgAAAA==.',
Lu='Lucia:BAABLgAECn8UAAIXAAcJHA+sOwBXAQAXAAcJHA+sOwBXAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Magnusbane:BAAALgADCgYJBgABLgAECgcJGwAFAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn8cAAMBAAcJHhcCDQCaAQABAAcJYBICDQCaAQAbAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn8nAAIcAAgJDyT0AACeAgAcAAgJDyT0AACeAgAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECggJIAAOAOwZAA==.Maylida:BAAALgAECgQJBAABLgAFFAMJBwACALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgMJAwAAAA==.',
Mo='Mojojuice:BAABLgAECn8dAAIIAAgJFSQPAgDXAgAIAAgJFSQPAgDXAgAAAA==.Montar:BAABLgAECn8WAAIMAAYJ4SDLFgDbAQAMAAYJ4SDLFgDbAQAAAA==.Moonjuice:BAABLgAECn8dAAIUAAgJXhCrJwBKAQAUAAgJXhCrJwBKAQAAAA==.',
Na='Nahaii:BAABLgAECn8fAAIKAAgJORkBHQDaAQAKAAgJORkBHQDaAQABLgAFFAUJBwAMANMNAA==.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Nelos:BAABLgAECn8cAAIdAAcJlBpSDADhAQAdAAcJlBpSDADhAQAAAA==.Neovisus:BAAALgAECgYJDwAAAA==.',
Ni='Nia:BAAALgAECggJEAAAAA==.Nineline:BAAALgADCgEJAQABLgAECgYJGAAaAP8bAA==.',
No='Nozarashi:BAABLgAECn8VAAIKAAYJZRxOKwCOAQAKAAYJZRxOKwCOAQAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIaAAMJaxHIFgDjAAAaAAMJaxHIFgDjAAAuAAQKfyoAAhoACQnnHfwLAMkBABoACQnnHfwLAMkBAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAUJEQALALwVAA==.',
Oo='Oopsikeelu:BAAALgADCgYJBgAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Po='Poisontips:BAAALgAECgEJAQAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8dAAIMAAYJpiKOFQDlAQAMAAYJpiKOFQDlAQAAAA==.',
Ra='Randlidan:BAABLgAECn8YAAINAAgJ+x92CQDLAgANAAgJ+x92CQDLAgAAAA==.Randomcow:BAABLgAECn8aAAIKAAYJkA6VoAA/AQAKAAYJkA6VoAA/AQAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgcJDQAAAA==.Sanctu:BAAALgAECgUJDgABLgAFFAQJCgAEAC8SAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgADCgQJAwAAAA==.',
Si='Silicos:BAAALgADCgIJAgABLgADCgYJBgAFAAAAAA==.',
Sk='Skywarp:BAAALgAECgcJBwAAAA==.',
Sl='Slapnchop:BAAALgADCgYJBgAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAAALgAECgYJEAAAAA==.Smol:BAAALgAECgYJEQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECgMJAwAFAAAAAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgcJDgAAAA==.Supersayan:BAAALgAECgEJAQABLgAECgYJDwAFAAAAAA==.Superspike:BAACLgAFFH8OAAILAAQJGB55EQB5AQALAAQJGB55EQB5AQAuAAQKfysAAgsACQmKIyEYABoDAAsACQmKIyEYABoDAAAA.Surshock:BAABLgAECn8dAAIIAAgJ4BQ8KQDLAQAIAAgJ4BQ8KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgYJCAAAAA==.',
Ta='Taekay:BAAALgAFFAMJAwABLgAFFAcJGgAaAE0hAA==.Takamine:BAABLgAECn8cAAIeAAgJIAnKCABgAQAeAAgJIAnKCABgAQAAAA==.Talath:BAABLgAECn8VAAIOAAYJKBWCLQBWAQAOAAYJKBWCLQBWAQAAAA==.Talos:BAABLgAECn8SAAIEAAgJAAl7gQAmAQAEAAgJAAl7gQAmAQAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8dAAQfAAcJ2xy8LQD8AQAfAAcJxBy8LQD8AQARAAMJ6w0JHAChAAAgAAIJ0xb8LACNAAAAAA==.Twysted:BAAALgAECgcJDAAAAA==.',
Ug='Ugin:BAAALgADCgYJCAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8aAAIhAAgJKh8RAgBMAgAhAAgJKh8RAgBMAgAAAA==.Vanillarista:BAAALgAECggJCwAAAA==.Varwyn:BAAALgADCgMJAwAAAA==.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAAALgAFFAEJAQAAAA==.',
We='Wesdarian:BAAALgAECgUJBQAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAAALgAECgYJEAAAAA==.',
Xe='Xer:BAABLgAECn8UAAILAAUJsg3MdwDnAAALAAUJsg3MdwDnAAAAAA==.',
Xi='Xirious:BAAALgAFFAEJAQAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8hAAIEAAgJPhx+CQBCAgAEAAgJPhx+CQBCAgAAAA==.',
Yo='Yonko:BAABLgAECn8hAAMZAAgJBBt9FABJAgAZAAgJBBt9FABJAgAaAAQJhgvJLQCwAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
['Ís']='Ísolde:BAABLgAECn8dAAQLAAcJih0nJQDTAQALAAcJih0nJQDTAQAiAAEJpBmgCQBPAAAhAAEJNgn5CAAyAAAAAA==.',
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

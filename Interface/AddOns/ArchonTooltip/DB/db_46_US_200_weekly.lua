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

local lookup = {'DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Warlock-Demonology','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','DeathKnight-Blood','Warlock-Destruction','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline','Hunter-BeastMastery','Monk-Brewmaster','Monk-Mistweaver','Paladin-Protection','Priest-Shadow','Evoker-Augmentation','Priest-Holy','DemonHunter-Vengeance',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Achoo:BAAALgAECgQJBAAAAA==.',
Ai='Aitnd:BAAALgADCgcJCAAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECggJCAAAAA==.Amongor:BAABLgAECn8YAAIBAAYJ3h+wFwBVAQABAAYJ3h+wFwBVAQAAAA==.',
An='Anarisa:BAABLgAECn8WAAMCAAgJPxEpbwD2AQACAAgJ+w4pbwD2AQADAAUJcRGCCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAQJDQAEABgdAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAICAAcJkBeuaQADAgACAAcJkBeuaQADAgABLgAECggJCAAFAAAAAA==.Averse:BAABLgAECn8WAAIBAAYJbxMPigBtAQABAAYJbxMPigBtAQAAAA==.',
Az='Azazygos:BAAALgADCgUJBQAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgcJAQABLgAECggJGgAGAEMbAA==.Barley:BAAALgADCgMJAwAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgADCggJFQAAAA==.Bepid:BAABLgAECn8bAAMHAAgJAx/wDQC+AQAIAAYJPyHRKQASAgAHAAUJCh3wDQC+AQAAAA==.',
Bl='Bluetide:BAACLgAFFH8NAAIEAAQJGB33BQBpAQAEAAQJGB33BQBpAQAuAAQKfxwAAgQACAlRJVgCAF8DAAQACAlRJVgCAF8DAAAA.',
Br='Brokemav:BAABLgAECn8dAAIJAAcJuiCYAgCTAgAJAAcJuiCYAgCTAgAAAA==.Brooklin:BAABLgAECn8gAAICAAgJAB/YKwDDAgACAAgJAB/YKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8bAAIEAAgJuhVZKwDfAQAEAAgJuhVZKwDfAQAAAA==.',
Ca='Carboncredit:BAABLgAECn8VAAIKAAkJTgwHCgAyAgAKAAkJTgwHCgAyAgAAAA==.Cassiopea:BAAALgAECgYJDwAAAA==.',
Ce='Cellcept:BAAALgAECgQJAwAAAA==.',
Ch='Chareth:BAABLgAECn8aAAICAAgJxgcQJgA3AQACAAgJxgcQJgA3AQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgYJBgAAAA==.Chinchillada:BAAALgAECgMJAwAAAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
Da='Dabajabaza:BAAALgAECgYJDgAAAA==.Dabergerak:BAABLgAECn8VAAIIAAgJiiHeAACiAgAIAAgJiiHeAACiAgAAAA==.Daenys:BAAALgAECgMJAwABLgAFFAYJEgALAB4YAA==.Daggart:BAAALgAECgEJAQAAAA==.Dagrimreaper:BAAALgADCgcJAQAAAA==.Dakrus:BAABLgAECn8hAAMMAAgJxRa1IAAdAgAMAAgJqRa1IAAdAgANAAUJQgfsCgDlAAAAAA==.Dawin:BAAALgADCgEJAQAAAA==.',
De='Dejanira:BAABLgAECn8YAAIOAAkJVgyCTAByAQAOAAkJVgyCTAByAQAAAA==.Demonslayerr:BAAALgADCgMJAwAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAFAAAAAA==.',
Di='Diddily:BAAALgAECgYJDAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCggJDQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAAALgAECgYJCAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8WAAIPAAgJHhLvFgCnAQAPAAgJHhLvFgCnAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8WAAIIAAgJuglBEQAdAQAIAAgJuglBEQAdAQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQAAAA==.Elise:BAABLgAECn8fAAMQAAgJSxYgCQAvAgAQAAgJSxYgCQAvAgAJAAYJgw72DgBBAQAAAA==.Elstrid:BAAALgAECgYJEQAAAA==.',
Eu='Euphoria:BAAALgADCgcJDAABLgAECggJGQARAOYkAA==.',
Ev='Evochre:BAAALgAECgMJBgAAAA==.',
Fa='Fantasy:BAABLgAECn8ZAAIRAAgJ5iTzAwBgAwARAAgJ5iTzAwBgAwAAAA==.',
Fe='Felbourn:BAABLgAECn8XAAMSAAgJWCCLCADZAgASAAgJWCCLCADZAgATAAIJsglXzABdAAAAAA==.',
Fi='Figurefour:BAAALgAECgYJBwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAABLgAECn8jAAIGAAgJRRyyBABTAgAGAAgJRRyyBABTAgAAAA==.Frigamortis:BAAALgAECgMJAwAAAA==.',
Ge='Gemini:BAAALgADCgcJDAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAAALgAECgMJAwABLgAFFAUJCAAUALUGAA==.',
Gn='Gnarfok:BAAALgAECgMJAwAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgEJAQAFAAAAAA==.',
Gr='Graamps:BAAALgAECgEJAQAAAA==.Gravedigger:BAABLgAECn8dAAIPAAgJRh2KAgDqAQAPAAgJRh2KAgDqAQAAAA==.',
Gu='Gust:BAAALgAECgQJCwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgEJAQABLgAECggJFwAVAAYWAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
In='Inarios:BAAALgAECgYJCwAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECggJFgAWAO4aAA==.Ironnmonk:BAABLgAECn8WAAMWAAgJ7hp+GwAnAgAWAAgJ7hp+GwAnAgAXAAEJUgRfdQAcAAAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECgYJEQAFAAAAAA==.',
Ju='Jujufya:BAAALgADCgYJBgAAAA==.Jujukni:BAAALgADCgUJCAABLgADCgYJBgAFAAAAAA==.Jujumon:BAAALgADCgMJAwABLgADCgYJBgAFAAAAAA==.Jujuzul:BAAALgADCgUJBgABLgADCgYJBgAFAAAAAA==.Justimp:BAABLgAECn8WAAILAAgJ6hKiPQAWAgALAAgJ6hKiPQAWAgAAAA==.',
Ka='Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAAALgAECgYJDQAAAA==.',
Ko='Konsistency:BAABLgAECn8XAAITAAYJ3w+bcgBNAQATAAYJ3w+bcgBNAQAAAA==.Konviction:BAABLgAECn8WAAMGAAgJAxB6fACBAQAGAAgJAxB6fACBAQAYAAEJewG0TgAVAAAAAA==.',
Kr='Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAAALgAECgMJAwAAAA==.Lan:BAAALgADCgEJAQAAAA==.',
Li='Liari:BAEALgAECgYJDAABLgAECggJGgAGAEMbAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8IAAIUAAUJtQbBCABRAQAUAAUJtQbBCABRAQAuAAQKfxwAAxQACQmpGGwSACECABQACAk0GWwSACECABkABwmmFzwhAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAABLgAECn8ZAAIaAAgJUwcrMgA3AQAaAAgJUwcrMgA3AQAAAA==.',
Lu='Lumie:BAABLgAECn8aAAIbAAgJLx+kCADCAgAbAAgJLx+kCADCAgAAAA==.Lunie:BAAALgAECgYJCQABLgAECggJGgAbAC8fAA==.',
Ma='Magadeoz:BAAALgAECgQJBgAAAA==.Magicshow:BAABLgAECn8aAAICAAgJ7A8MlQCqAQACAAgJ7A8MlQCqAQAAAA==.Malzahar:BAAALgADCgEJAQAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgADCgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAAALgAFFAEJAQAAAA==.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAAALgAECgcJCwAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAAALgADCgcJEwABLgAFFAQJDQAWAL8kAA==.Noobmonkey:BAACLgAFFH8NAAIWAAQJvyS6AAC0AQAWAAQJvyS6AAC0AQAuAAQKfyYAAhYACAljJR0EAEsDABYACAljJR0EAEsDAAAA.Noobwarr:BAAALgADCgcJDQABLgAFFAQJDQAWAL8kAA==.Novax:BAAALgADCgcJCgAAAA==.',
Nu='Numeral:BAAALgAFFAIJAgAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAAALgAECgUJCAAAAA==.',
Pi='Pinktide:BAAALgADCgcJEwABLgAFFAQJDQAEABgdAA==.',
Po='Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAAALgAECgQJCwAAAA==.',
Pu='Putz:BAABLgAECn8nAAITAAgJFCDMBQAjAgATAAgJFCDMBQAjAgAAAA==.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAQJDQAEABgdAA==.Rainbow:BAAALgAECgYJDgABLgAECggJGQARAOYkAA==.Ratfondler:BAAALgAECggJDwAAAA==.',
Re='Reialaleigh:BAAALgADCggJDgAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8PAAITAAUJqRWaCQCQAQATAAUJqRWaCQCQAQAuAAQKfyMAAhMACQnLH9AHAE0DABMACQnLH9AHAE0DAAAA.Saberdiva:BAABLgAECn8WAAIGAAcJUwmxlQBRAQAGAAcJUwmxlQBRAQAAAA==.Saberthyr:BAAALgADCgkJCQAAAA==.Sagesteppe:BAAALgADCggJCAAAAA==.',
Sc='Scotticus:BAAALgAECgcJEgAAAA==.',
Se='Seditionist:BAAALgAECgIJAgAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgcJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.',
Si='Sidthekid:BAAALgADCgUJBwAAAA==.Sinayion:BAAALgAECgQJCAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAFAAAAAA==.',
Su='Sunarena:BAABLgAECn8UAAIGAAcJkA0ZfgB+AQAGAAcJkA0ZfgB+AQAAAA==.',
Ta='Tankobell:BAAALgAECgYJDQAAAA==.',
Th='Thejuiciest:BAAALgADCgEJAgAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8UAAICAAYJkhVzIQBNAQACAAYJkhVzIQBNAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Uh='Uh:BAAALgADCgYJBgAAAA==.',
Va='Valesko:BAAALgAECgEJAgAAAA==.Varfus:BAACLgAFFH8NAAIcAAQJuiIpAAB6AQAcAAQJuiIpAAB6AQAuAAQKfyYAAhwACAmPJa8AAFQDABwACAmPJa8AAFQDAAAA.',
Ve='Velentre:BAAALgAECgIJAgAAAA==.',
Vi='Vichy:BAAALgAECgIJAwAAAA==.Vikstyn:BAAALgAECgEJAQAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.',
Wo='Wouka:BAABLgAECn8kAAMLAAgJuyX4AADgAgALAAgJuyX4AADgAgAJAAYJLCPVAwBQAgAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgMJAwAAAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAAALgAECgYJCQABLgAECggJFgAEAC4ZAA==.Zeptide:BAABLgAECn8WAAMEAAgJLhn1IgANAgAEAAcJqBj1IgANAgARAAEJLgkOKQAyAAAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAECggJKgALAPYSAA==.',
Zu='Zugnuts:BAAALgADCgcJEQAAAA==.',
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

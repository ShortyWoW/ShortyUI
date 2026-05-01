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

local lookup = {'DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Warlock-Demonology','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Warlock-Destruction','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Protection','Priest-Shadow','Evoker-Augmentation','Priest-Holy','DemonHunter-Vengeance',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Achoo:BAAALgAECgQJBwAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQAAAA==.Amongor:BAABLgAECn8YAAIBAAYJ3h93UAAAAgABAAYJ3h93UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn8jAAMCAAgJThX8IwDYAQACAAgJThX8IwDYAQADAAUJcRGCCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAUJEgAEAKscAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgADCgEJAQAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAICAAcJkBeoaQADAgACAAcJkBeoaQADAgABLgAECgkJEQAFAAAAAA==.Averse:BAABLgAECn8gAAIBAAgJyxtnDQBZAgABAAgJyxtnDQBZAgAAAA==.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgcJAQABLgAECggJHwAGALkcAA==.Barley:BAAALgADCgQJBwAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJBgAAAA==.Bepid:BAABLgAECn8jAAMHAAgJRyF4CQBsAQAIAAYJ9SHUKQASAgAHAAUJqB94CQBsAQAAAA==.',
Bl='Bluetide:BAACLgAFFH8SAAIEAAUJqxwlBACsAQAEAAUJqxwlBACsAQAuAAQKfx8AAgQACQmZJVcCAF8DAAQACQmZJVcCAF8DAAAA.',
Br='Brokemav:BAABLgAECn8jAAIJAAcJuiCXAgCTAgAJAAcJuiCXAgCTAgAAAA==.Brooklin:BAABLgAECn8pAAICAAkJBx7+EwA6AgACAAkJBx7+EwA6AgAAAA==.',
Bu='Busky:BAABLgAECn8dAAMEAAgJgRZZKwDfAQAEAAgJgRZZKwDfAQAKAAEJtRPlFwBAAAAAAA==.',
Ca='Carboncredit:BAABLgAECn8cAAIKAAkJoA0HCgAyAgAKAAkJoA0HCgAyAgAAAA==.Cassiopea:BAAALgAECgYJEwAAAA==.Caysia:BAAALgAECgcJDAABLgAECgkJEQAFAAAAAA==.',
Ce='Cellcept:BAAALgAECgUJBgAAAA==.',
Ch='Chareth:BAABLgAECn8eAAICAAgJIAjdVgAxAQACAAgJIAjdVgAxAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgYJCQAAAA==.Chinchillada:BAAALgAECgUJCAAAAA==.',
Co='Cowladin:BAAALgADCgYJBgABLgAECgcJFAALALceAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
Da='Dabajabaza:BAABLgAECn8UAAIMAAYJjwloGAC5AAAMAAYJjwloGAC5AAAAAA==.Dabergerak:BAABLgAECn8eAAIIAAgJoSRlAQD2AgAIAAgJoSRlAQD2AgAAAA==.Daenys:BAAALgAECgMJAwABLgAFFAYJGAALAPgaAA==.Daggart:BAAALgAECgcJCAAAAA==.Dakrus:BAABLgAECn8hAAMNAAgJxRa1IAAdAgANAAgJqRa1IAAdAgAOAAUJQgdjGgDgAAAAAA==.Dawin:BAAALgADCgEJAQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAECgQJBgAAAA==.Dejanira:BAABLgAECn8cAAIPAAkJbA6ETAByAQAPAAkJbA6ETAByAQAAAA==.Demonslayerr:BAAALgADCgMJAwAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAFAAAAAA==.',
Di='Diddily:BAAALgAECgYJDgAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCggJDQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAAALgAECgYJCgAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8iAAIMAAgJuxWECgBqAQAMAAgJuxWECgBqAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8YAAIIAAgJBgukFQCHAQAIAAgJBgukFQCHAQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQAAAA==.Elise:BAABLgAECn8iAAMQAAgJyRciAwDGAQAQAAgJyRciAwDGAQAJAAcJmhD3DgBBAQAAAA==.Elstrid:BAABLgAECn8UAAILAAcJtx42PAAcAgALAAcJtx42PAAcAgAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgADCgcJDAABLgAECggJJgARADMlAA==.',
Ev='Evochre:BAAALgAECgQJBwAAAA==.',
Fa='Fantasy:BAABLgAECn8mAAIRAAgJMyXxAQDfAgARAAgJMyXxAQDfAgAAAA==.',
Fe='Felbourn:BAABLgAECn8ZAAMSAAgJgSGPCADZAgASAAgJgSGPCADZAgATAAIJsglfzABdAAAAAA==.',
Fi='Figurefour:BAAALgAECgYJBwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAABLgAECn8uAAIGAAgJKx5ZCwBxAgAGAAgJKx5ZCwBxAgAAAA==.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgQJBAAAAA==.',
Ge='Gemini:BAAALgADCgcJDAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAICAAUJagS7KgAhAQACAAUJagS7KgAhAQABLgAFFAUJCgAUABoHAA==.',
Gn='Gnarfok:BAAALgAECgMJCQAAAA==.',
Go='Goopster:BAAALgADCgcJCQAAAA==.',
Gr='Graamps:BAAALgAECgEJAQAAAA==.Gravedigger:BAABLgAECn8lAAIMAAgJNh4hBQDmAQAMAAgJNh4hBQDmAQAAAA==.',
Gu='Gust:BAAALgAECgQJDgAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgEJAQABLgAECggJHQAVAOQYAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
In='Inarios:BAAALgAECgYJEQAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECggJGAAWAO4aAA==.Ironnmonk:BAABLgAECn8YAAQWAAgJ7hqAGwAnAgAWAAgJ7hqAGwAnAgAXAAEJhxGUQwA9AAAYAAEJUgQtdQAcAAAAAA==.',
Ja='Javlin:BAAALgADCgcJBwAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECgcJFAALALceAA==.',
Ju='Jujufya:BAAALgADCgYJBgAAAA==.Jujukni:BAAALgADCgUJCAABLgADCgYJBgAFAAAAAA==.Jujumon:BAAALgADCgMJAwABLgADCgYJBgAFAAAAAA==.Jujuzul:BAAALgADCgUJBgABLgADCgYJBgAFAAAAAA==.Justimp:BAABLgAECn8eAAILAAgJBRUHHQDGAQALAAgJBRUHHQDGAQAAAA==.',
Ka='Kanon:BAAALgAECgUJBQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAAALgAFFAIJAgAAAA==.',
Ko='Konsistency:BAABLgAECn8ZAAITAAcJdg6bcgBNAQATAAcJdg6bcgBNAQAAAA==.Konviction:BAABLgAECn8XAAMGAAgJAxB8fACBAQAGAAgJAxB8fACBAQAZAAEJewG2TgAVAAAAAA==.',
Kr='Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAAALgAECgUJCAAAAA==.Lan:BAAALgADCgEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEALgAECgYJEQABLgAECggJHwAGALkcAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8KAAIUAAUJGgfBCABRAQAUAAUJGgfBCABRAQAuAAQKfxwAAxQACQmpGGsSACECABQACAk0GWsSACECABoABwmmF0UhAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAABLgAECn8dAAIbAAgJYwo0MgA3AQAbAAgJYwo0MgA3AQAAAA==.Lootadots:BAAALgADCgkJDgABLgAECgEJBgAFAAAAAA==.',
Lu='Lumie:BAABLgAECn8jAAMcAAgJECClCADCAgAcAAgJECClCADCAgAaAAYJIBFyFwBCAQAAAA==.Lunie:BAAALgAECgYJCQABLgAECggJIwAcABAgAA==.',
Ma='Magadeoz:BAAALgAECgYJCwAAAA==.Magicshow:BAABLgAECn8bAAICAAgJ7A/5lACqAQACAAgJ7A/5lACqAQAAAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCgAAAA==.',
Mu='Musky:BAAALgAECgEJAQAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAAALgAFFAEJAQAAAA==.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAAALgAECgcJCwAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAAALgAFFAEJAQABLgAFFAQJEQAWAB4lAA==.Noobmonkey:BAACLgAFFH8RAAIWAAQJHiV0AgC2AQAWAAQJHiV0AgC2AQAuAAQKfykAAhYACQk0JSAEAEsDABYACQk0JSAEAEsDAAAA.Noobwarr:BAAALgADCgcJDQABLgAFFAQJEQAWAB4lAA==.Novax:BAAALgADCgkJDAAAAA==.',
Nu='Numeral:BAAALgAFFAIJAgAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAAALgAECgUJCwABLgAECgcJEgAFAAAAAA==.',
Pi='Pinktide:BAAALgAECgYJBgABLgAFFAUJEgAEAKscAA==.',
Po='Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAAALgAECgYJEQAAAA==.',
Pu='Putz:BAABLgAECn8wAAITAAkJkyAPAwDMAgATAAkJkyAPAwDMAgAAAA==.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAUJEgAEAKscAA==.Rainbow:BAABLgAECn8UAAIYAAYJbh9HDgDCAQAYAAYJbh9HDgDCAQABLgAECggJJgARADMlAA==.Rastasham:BAAALgADCgcJCgAAAA==.Ratfondler:BAABLgAECn8cAAMXAAkJUx94AQDrAgAXAAkJUx94AQDrAgAYAAEJ0gL0bQAnAAAAAA==.',
Re='Reialaleigh:BAAALgADCgkJEQAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8TAAITAAUJsRaaCQCQAQATAAUJsRaaCQCQAQAuAAQKfygAAhMACQnLH9QHAE0DABMACQnLH9QHAE0DAAAA.Saberdiva:BAABLgAECn8eAAIGAAgJsQt3QwA/AQAGAAgJsQt3QwA/AQAAAA==.Saberthyr:BAAALgADCgkJCQAAAA==.Sagesteppe:BAAALgAECgMJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8YAAIBAAcJiwgsngBEAQABAAcJiwgsngBEAQAAAA==.',
Se='Seditionist:BAAALgAECgUJDAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgADCgkJEQAFAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.',
Si='Sidthekid:BAAALgADCgUJBwAAAA==.Sinayion:BAAALgAECgYJDgAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAFAAAAAA==.',
Su='Sunarena:BAABLgAECn8YAAIGAAcJ6w0ZfgB+AQAGAAcJ6w0ZfgB+AQAAAA==.',
Ta='Tankobell:BAAALgAECgcJDgAAAA==.',
Th='Thannatos:BAAALgADCgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8aAAICAAYJOBgHQwBlAQACAAYJOBgHQwBlAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Va='Valesko:BAAALgAECgIJAwAAAA==.Varfus:BAACLgAFFH8SAAIdAAUJQSRIAACkAQAdAAUJQSRIAACkAQAuAAQKfykAAh0ACQmMJa8AAFQDAB0ACQmMJa8AAFQDAAAA.',
Ve='Velentre:BAAALgAECgIJAgAAAA==.',
Vi='Vichy:BAAALgAECgMJBAAAAA==.Vikstyn:BAAALgAECgEJAwAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgEJAQAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.',
Wo='Wouka:BAABLgAECn8lAAMLAAkJRCVhAQA/AwALAAkJRCVhAQA/AwAJAAYJLCPVAwBQAgAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgMJAwAAAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAAALgAECgYJDQABLgAECggJIwAEAGMZAA==.Zeptide:BAABLgAECn8jAAMEAAgJYxm5DwD6AQAEAAgJYxm5DwD6AQARAAUJNQuwLQDJAAAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECgEJAQAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAECggJMQALAPoWAA==.',
Zu='Zugnuts:BAAALgADCgcJFgAAAA==.',
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

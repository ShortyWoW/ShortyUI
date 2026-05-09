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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Unknown-Unknown','Evoker-Augmentation','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Druid-Guardian','Druid-Restoration','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','Warrior-Arms','DeathKnight-Unholy','Paladin-Protection','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abomination:BAAALgAECgYJEwAAAA==.',
Ad='Addison:BAACLgAFFH8GAAIBAAUJhCIXBwBiAQABAAUJhCIXBwBiAQAuAAQKfxYAAwEABwlGJl8MAMkCAAEABwlGJl8MAMkCAAIAAQmaFTx1AEEAAAEuAAUUBwkmAAMAPCYA.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgUJBQAAAA==.Adina:BAAALgAFFAEJAQAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAEAAAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJBwAAAA==.Arieon:BAAALgAECgIJAgABLgAFFAQJBwAFAAoJAA==.',
As='Ashfallen:BAAALgAECgYJCwAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAABLgAECn8iAAIGAAgJjB/0BgB/AgAGAAgJjB/0BgB/AgAAAA==.',
Au='Audric:BAABLgAECn8gAAIHAAgJQgzQFwCAAQAHAAgJQgzQFwCAAQAAAA==.Auryx:BAAALgADCgUJBwAAAA==.',
Az='Azrel:BAAALgAECgYJBgAAAA==.',
Ba='Baddragon:BAACLgAFFH8SAAQIAAUJ5B4HAQBxAQAIAAUJ9BwHAQBxAQAFAAQJ4Bp7DgAZAQAJAAEJxAfpGwBKAAAuAAQKfyIABAgACAlEJUYKADoCAAUABgmOJXEQAHECAAgABwkBHEYKADoCAAkAAQk0CY9JAC8AAAAA.Baldow:BAAALgADCgYJBgAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8UAAIKAAUJeSZ1AADCAQAKAAUJeSZ1AADCAQAuAAQKfy4AAwoACQnqJhQAAAUEAAoACQnqJhQAAAUEAAsABwlcJOwCAHUCAAAA.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAAALgAECggJCAAAAA==.Bayleef:BAABLgAECn8oAAIMAAkJwxksEQBIAgAMAAkJwxksEQBIAgAAAA==.',
Be='Beardik:BAAALgAECgUJCQAAAA==.Beccs:BAAALgADCgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAECggJGgANAOAOAA==.Beldr:BAAALgAECggJDgAAAA==.Benito:BAAALgAECgUJDAAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgADCgEJAQAAAA==.Brujochingon:BAAALgAECgcJEgAAAA==.Brèè:BAABLgAECn8qAAIOAAkJ4xz1BwDkAgAOAAkJ4xz1BwDkAgAAAA==.',
Ca='Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgMJAwABLgAECgUJCAAEAAAAAA==.Chiz:BAABLgAECn8XAAIPAAYJMBn4iQC+AQAPAAYJMBn4iQC+AQAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAABLgAECn8aAAINAAgJ4A63MwCVAQANAAgJ4A63MwCVAQAAAA==.',
Co='Conall:BAABLgAECn8rAAIQAAkJsxjSFQBMAgAQAAkJsxjSFQBMAgAAAA==.Confetti:BAAALgAECgYJEQAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJEgAAAA==.',
Cr='Croissants:BAAALgAECgQJBAAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Da='Dajova:BAAALgAECgMJAwAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgADCgcJDAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJAgAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgEJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAEAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMCAAYJagxWJQABAQACAAYJagxWJQABAQARAAYJdwbhQgDTAAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8oAAMRAAkJvw9yJACPAQARAAkJvw9yJACPAQACAAcJChBzHQA4AQAAAA==.Doñagladys:BAAALgAECgEJAQAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAQAAAA==.Dragonsloot:BAACLgAFFH8QAAMFAAUJmRGPFQAyAQAFAAUJmRGPFQAyAQAJAAIJVwGWGQBvAAAuAAQKfywABAUACQl3GncHAF8CAAUACQl3GncHAF8CAAkABwmgBMQTAAMBAAgAAgk1GMk7AD4AAAAA.Draks:BAAALgADCgUJBQAAAA==.Drizzitt:BAAALgAECgQJCgAAAA==.Drubeastin:BAABLgAECn8VAAISAAcJmhg3NwDRAQASAAcJmhg3NwDRAQAAAA==.Druidia:BAAALgADCggJCAAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dó']='Dónkey:BAAALgADCgQJBAAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgADCgQJBAAAAA==.Elementtamer:BAAALgADCgIJAgAAAA==.',
Er='Erza:BAAALgAECgEJAQAAAA==.',
Es='Esh:BAABLgAECn8aAAMNAAgJxCEFJwB1AgANAAYJwiMFJwB1AgATAAQJSRldIwA9AQAAAA==.',
Ev='Evildarkness:BAAALgADCgEJAQAAAA==.Evilemt:BAAALgAECgEJAgAAAA==.Evilmt:BAAALgADCgEJBAAAAA==.',
Fa='Fappio:BAAALgAECgMJAwABLgAECggJHwAJAGUgAA==.Faîth:BAAALgAECgUJCAABLgAECgkJIgAPAKkdAA==.',
Fl='Flamesshadow:BAAALgAECgUJBQAAAA==.',
Fo='Forgiven:BAACLgAFFH8HAAIUAAQJYiCJDgCAAQAUAAQJYiCJDgCAAQAuAAQKfx8AAhQACAl1ItkHAKgCABQACAl1ItkHAKgCAAAA.',
Fr='Frogsbreath:BAAALgAECgYJBwAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgADCgEJAQAAAA==.',
Ga='Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgEJAgAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgADCggJCQAAAA==.Gullveig:BAAALgAECgcJEwAAAA==.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAAALgAECgUJBgABLgAECgYJFQAOAPAVAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8bAAIPAAcJRBKMUAB5AQAPAAcJRBKMUAB5AQAAAA==.Hellmagi:BAAALgAECgcJDQAAAA==.Helmon:BAAALgAECgMJAwAAAA==.Hexson:BAABLgAECn8XAAQNAAgJpxIIbQCHAQANAAgJpxIIbQCHAQATAAQJUQ0oUQB6AAAVAAEJ6Al8FwA6AAAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMWAAcJJhAgQACAAQAWAAcJJhAgQACAAQAXAAMJ7R1NMgDoAAAAAA==.',
Ho='Hordeelf:BAACLgAFFH8fAAIQAAgJ9CMnAADmAgAQAAgJ9CMnAADmAgAuAAQKfxwAAhAACAlrJiwFAHoDABAACAlrJiwFAHoDAAAA.Hordeforsure:BAABLgAECn8UAAMYAAYJLh6kMACxAQAYAAYJGh6kMACxAQASAAEJbiASuABTAAABLgAFFAgJHwAQAPQjAA==.Hornfu:BAAALgAECgYJCQAAAA==.',
Hu='Humanwolf:BAAALgAECgEJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Inovar:BAACLgAFFH8IAAINAAMJYx+yMQAIAQANAAMJYx+yMQAIAQAuAAQKfyQAAg0ACQkHIWQHAM4CAA0ACQkHIWQHAM4CAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAUJFAACAKMYAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAECgkJLQAQAOIkAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAAALgAECgYJDAABLgAECggJMQAZAHAXAA==.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAABLgAECn8VAAMOAAYJ8BWKEwBTAQAOAAYJ8BWKEwBTAQAaAAMJTgSZIwBlAAAAAA==.Kangarooz:BAAALgAECgUJCgAAAA==.Karlthuzad:BAAALgAECgQJBAAAAA==.Katrint:BAABLgAECn8dAAMbAAgJDyTiBgBAAgAbAAgJDyTiBgBAAgAcAAMJ3BuCFQCiAAAAAA==.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8QAAMdAAQJDiOJBQBwAQAdAAQJDiOJBQBwAQAHAAEJRQ28FABRAAAuAAQKfxoAAh0ACAmgHkUQAGMCAB0ACAmgHkUQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAQJBwAPAIYFAA==.Kiramouse:BAABLgAFFH8OAAMNAAQJBxpYIgD7AAANAAMJABlYIgD7AAATAAEJGh3PDgBcAAAAAA==.Kirawrxd:BAAALgAECgMJAwAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAUJFAACAKMYAA==.',
Ky='Kyrié:BAABLgAECn8dAAIdAAYJgCG9HgDqAQAdAAYJgCG9HgDqAQAAAA==.',
La='Lanzadora:BAAALgAECgQJBgAAAA==.',
Le='Leiya:BAAALgAECgQJCAAAAA==.',
Li='Liability:BAABLgAECn8jAAIeAAkJ/ANGFgASAQAeAAkJ/ANGFgASAQAAAA==.Linez:BAAALgADCgQJBAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8FAAISAAMJ+w/QKAD2AAASAAMJ+w/QKAD2AAAuAAQKfygAAhIACAnRIFEOAGcCABIACAnRIFEOAGcCAAAA.',
Ma='Magital:BAAALgADCgcJCwABLgAFFAUJEAAFAJkRAA==.Makisan:BAAALgAECgcJDQAAAA==.Malis:BAAALgAECgcJBgABLgAECgkJGgAQAMsVAA==.',
Mc='Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgEJAQAAAA==.Melara:BAAALgAECgEJAQAAAA==.Meowmeowmeow:BAAALgADCgYJBgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8oAAIfAAgJCRs1AgAoAgAfAAgJCRs1AgAoAgAAAA==.Mikeoxlongg:BAAALgAECggJCQAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgMJBAAAAA==.',
Na='Naianasha:BAAALgAECgMJAwABLgAECgUJEwAEAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn82AAIMAAkJmiB/AwA5AwAMAAkJmiB/AwA5AwAAAA==.',
Ne='Nenizaurio:BAAALgAECgQJBgAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBQAAAA==.Noma:BAAALgADCgEJAQAAAA==.',
Nu='Nuxo:BAAALgAECgMJAwAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIgAAMJ3RheAwAEAQAgAAMJ3RheAwAEAQABLgAFFAUJFAAKAHkmAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgQJBgABLgAECgUJCAAEAAAAAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECggJDwAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDgAEAAAAAA==.',
Pr='Profitt:BAABLgAECn8mAAIPAAkJQB72CwDBAgAPAAkJQB72CwDBAgAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAABLgAECn8tAAIQAAkJ4iSpAgA4AwAQAAkJ4iSpAgA4AwAAAA==.Quâsar:BAAALgAECggJCAABLgAECgkJIgAPAKkdAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQAAAA==.Rabbidlight:BAAALgAECgYJEQAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasoon:BAAALgAECgUJBgAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8hAAIQAAgJChkMJQDuAQAQAAgJChkMJQDuAQAAAA==.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCQAEAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJCwAAAA==.Satoru:BAAALgAECgEJAQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAcJHgANACcdAA==.',
Se='Segen:BAAALgAECgQJDAAAAA==.Semip:BAAALgAECgUJDwAAAA==.Sen:BAABLgAECn8jAAQSAAgJISTnCQCYAgASAAgJiCLnCQCYAgAYAAYJ6iE7JAAGAgAhAAIJDxVWLQCNAAAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgEJAQABLgAECgUJCQAEAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAAALgAECgcJEAABLgAECgYJFQAOAPAVAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgEJAQAAAA==.Shîver:BAABLgAECn8iAAIPAAkJqR2lKQDMAgAPAAkJqR2lKQDMAgAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8UAAICAAUJoxjNBgBVAQACAAUJoxjNBgBVAQAuAAQKfygAAwIACQkAHa8HAAADAAIACQkAHa8HAAADAAEAAwmXFLBiALcAAAAA.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAEAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sn='Snipedyou:BAAALgAECgEJAQAAAA==.Snomed:BAABLgAFFH8GAAIVAAIJOiLWAADaAAAVAAIJOiLWAADaAAABLgAFFAUJFAAKAHkmAA==.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8cAAIRAAYJBhf4GACIAQARAAYJBhf4GACIAQAAAA==.',
St='Stantic:BAACLgAFFH8MAAQSAAYJaAeaDQDvAAASAAQJhwuaDQDvAAAYAAMJJAFFIwBjAAAhAAEJHAIyHgBGAAAuAAQKfx0AAxIACAmgHzogAEQCABIACAnBGzogAEQCABgABwmeGwciABUCAAAA.Statuskwo:BAAALgAECgUJBgABLgAECggJGgANAOAOAA==.Stevethuzad:BAAALgAECgQJBQAAAA==.Stormydaniel:BAAALgAECgQJBAAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAECgcJBwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8hAAIUAAgJqh3iEQAwAgAUAAgJqh3iEQAwAgAAAA==.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAECgIJAwAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAABLgAECn8ZAAIDAAgJjCC8BQBJAgADAAgJjCC8BQBJAgAAAA==.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAEAAAAAA==.Trigodun:BAABLgAECn8iAAMGAAgJxxc5JAA1AgAGAAgJ6hQ5JAA1AgAiAAIJXhMQKgB8AAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECggJIQAUAKodAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgQJCQAAAA==.',
Un='Undedagaindk:BAACLgAFFH8bAAIjAAYJMR81AgD1AQAjAAYJMR81AgD1AQAuAAQKfxYAAyMACQkCJiUKAEoDACMACQkCJiUKAEoDAAMAAgkLIJ4hALgAAAAA.',
Up='Uppercut:BAAALgAECgIJAgAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAAALgAECgcJCQAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAAALgAECgUJEwAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8nAAQkAAgJFxOhDwA/AQAkAAgJ0BChDwA/AQAQAAQJ5g412wDWAAAZAAEJ7QEloQAnAAAAAA==.',
Vo='Volteil:BAABLgAECn8XAAICAAgJvx3jCAAwAgACAAgJvx3jCAAwAgAAAA==.',
Vy='Vyrric:BAABLgAECn8bAAIRAAgJQR55BQC3AgARAAgJQR55BQC3AgAAAA==.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAUJFAAKAHkmAA==.',
Wh='Whitelove:BAABLgAECn8oAAMlAAgJXRpnCABYAgAlAAgJXRpnCABYAgAdAAQJag1EZACdAAAAAA==.Whitest:BAAALgAECgYJCwAAAA==.Whixx:BAAALgADCgEJAQABLgAECggJHQAmAJcUAA==.Whý:BAAALgAECggJDgAAAA==.',
Wi='Wikm:BAAALgAECgQJCAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJDwAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgADCgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEQAAAA==.',
Xa='Xalithrya:BAAALgAECgUJCgABLgAECgkJLQAQAOIkAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8hAAIWAAgJMho7CwB7AgAWAAgJMho7CwB7AgAAAA==.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJBgAAAA==.',
Yo='Yorna:BAAALgADCgEJAQAAAA==.',
Za='Zapey:BAABLgAECn8dAAImAAgJlxTQBgDLAQAmAAgJlxTQBgDLAQAAAA==.',
Ze='Zem:BAAALgAECgYJBgAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8GAAMWAAMJThUXIgDPAAAWAAMJThUXIgDPAAAXAAEJuRjLKQBSAAAuAAQKfxUAAxYACAlBGZ89AIoBABYABQnHG589AIoBABcABwnpHLsnAB8BAAAA.',
Zo='Zoomies:BAAALgAECgYJBgABLgAECggJHwAJAGUgAA==.',
['Zé']='Zémzel:BAAALgAECgQJBwAAAA==.',
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

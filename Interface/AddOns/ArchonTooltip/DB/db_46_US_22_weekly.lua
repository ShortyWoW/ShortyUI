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

local lookup = {'Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Hunter-BeastMastery','Warrior-Protection','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','DeathKnight-Frost','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adnerb:BAAALgAECgYJDwABLgAFFAUJBgABAKcPAA==.',
Ah='Ahriman:BAABLgAECn8XAAICAAYJLw5ZWwDrAAACAAYJLw5ZWwDrAAAAAA==.',
Al='Alystra:BAABLgAECn8YAAIDAAcJGwdvJwALAQADAAcJGwdvJwALAQAAAA==.',
An='Anjedin:BAAALgAECgYJCwAAAA==.',
Ao='Aoki:BAABLgAECn8aAAIEAAcJmB10IQA8AgAEAAcJmB10IQA8AgAAAA==.',
Ar='Archdemon:BAABLgAECn8fAAIFAAgJNBj+CADnAQAFAAgJNBj+CADnAQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAECgUJBQABLgAFFAUJBgABAKcPAA==.Arkanoas:BAACLgAFFH8MAAIGAAQJNAu4NQA6AQAGAAQJNAu4NQA6AQAuAAQKfykAAgYACQmwFgc4AJQCAAYACQmwFgc4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBgABAKcPAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBgAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIHAAYJ/Aj+LQDPAAAHAAYJ/Aj+LQDPAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Bloody:BAAALgADCgEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8XAAIIAAgJgRuRPQBBAgAIAAgJgRuRPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAIJAAkJTxMZGwDrAQAJAAkJTxMZGwDrAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8cAAIGAAYJaAOAqgC/AAAGAAYJaAOAqgC/AAAAAA==.',
Ch='Charliemen:BAAALgADCgcJBgAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAABLgAECn8yAAIKAAkJ0CM7CAASAwAKAAkJ0CM7CAASAwAAAA==.Churrasco:BAAALgAECgMJBAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn8tAAMLAAgJJBZsEQDUAQALAAgJJBZsEQDUAQAMAAYJsQpIWQAjAQAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAABLgAECn8gAAIIAAgJqBlKGwAmAgAIAAgJqBlKGwAmAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Dutchess:BAABLgAECn8cAAINAAgJPBj8JQDqAQANAAgJPBj8JQDqAQAAAA==.',
Dy='Dylan:BAACLgAFFH8MAAIGAAQJ0hhOIABoAQAGAAQJ0hhOIABoAQAuAAQKfyIAAgYACQmfJF0DAEgDAAYACQmfJF0DAEgDAAAA.Dylanj:BAAALgAECgQJBAAAAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elowen:BAAALgAFFAEJAQAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgYJBgAAAA==.Eríngo:BAAALgAECgcJCwAAAA==.',
Es='Esna:BAAALgADCgUJBgAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8OAAMOAAQJ0hXCEABCAQAOAAQJURTCEABCAQAPAAIJVBNXDQCTAAAuAAQKfx0AAw8ACQn7GXkMAIwCAA8ACQlBGXkMAIwCAA4ABwkPFa4iABQBAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAABLgAECn8jAAIGAAgJkxe8NQDLAQAGAAgJkxe8NQDLAQAAAA==.',
Fr='Frozenscorch:BAAALgAECggJDwAAAA==.',
['Fä']='Fälkor:BAABLgAECn8jAAMQAAgJigbGKAAMAQAQAAgJXwbGKAAMAQARAAUJNAQ1DwCUAAAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJEQASAAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAAALgAECgUJBwAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8aAAITAAYJRSFvEwD4AQATAAYJRSFvEwD4AQAAAA==.',
He='Helpingyou:BAAALgAECggJDgAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8VAAITAAYJNhRfIgB0AQATAAYJNhRfIgB0AQAAAA==.',
Im='Impaladin:BAAALgADCgYJCgAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJCwAAAA==.Izzia:BAABLgAECn8WAAIJAAcJzBpYEwAwAgAJAAcJzBpYEwAwAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgUJBQAAAA==.Jasia:BAAALgADCgUJBwAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8jAAMOAAcJIREaHABNAQAOAAcJIREaHABNAQADAAUJyAhhRADZAAAAAA==.Kayewyn:BAABLgAECn8XAAIJAAcJehD0MQBWAQAJAAcJehD0MQBWAQAAAA==.',
Kb='Kbdh:BAAALgAECgYJBwABLgAFFAIJAwASAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwASAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwASAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwASAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwASAAAAAA==.',
Ke='Keiji:BAAALgAECgUJBgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgUJCQABLgAFFAMJCQAJACEdAA==.Kynn:BAACLgAFFH8JAAIJAAMJIR0KGQAKAQAJAAMJIR0KGQAKAQAuAAQKfy8AAgkACQmWIvQBAIEDAAkACQmWIvQBAIEDAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8iAAINAAcJdxJ1SwBjAQANAAcJdxJ1SwBjAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJCAAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJFwALACAZAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAQJDgAOANIVAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8kAAMUAAgJMyA5BABIAgAVAAcJ+B/yGACDAgAUAAgJWBw5BABIAgAAAA==.',
Mu='Muddless:BAABLgAECn8aAAMUAAcJ7x0MBgAIAgAUAAcJ7x0MBgAIAgAVAAEJ6gvIpQA5AAAAAA==.Mudds:BAABLgAECn8cAAIHAAgJnyB1EAB5AgAHAAgJnyB1EAB5AgAAAA==.',
Na='Naelia:BAAALgAECgQJBAAAAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ni='Nicodemus:BAAALgADCgEJAQAAAA==.Nightrush:BAABLgAECn8oAAMEAAgJICUzCgCUAgAEAAYJBCYzCgCUAgAWAAYJqSHWBQDCAQAAAA==.',
No='Noodles:BAABLgAECn8XAAICAAYJ2hXHVwD1AAACAAYJ2hXHVwD1AAAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAIJAAYJbgUyVQDDAAAJAAYJbgUyVQDDAAAAAA==.',
Ok='Okomo:BAAALgAECgEJAQABLgAECgMJAwASAAAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMTAAgJdRGaJQBdAQATAAcJrBKaJQBdAQANAAQJUAxlrgCYAAAAAA==.Pantsu:BAABLgAECn8xAAMIAAgJfiW6BwDhAgAIAAgJfiW6BwDhAgAXAAYJ6yEVAwDyAQAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAAALgAECgYJEQAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIPAAYJHRHaJgASAQAPAAYJHRHaJgASAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8GAAIHAAIJkBHDFgCgAAAHAAIJkBHDFgCgAAAuAAQKfyIAAgcACQmoHa4EAJoCAAcACQmoHa4EAJoCAAAA.',
Pu='Punchize:BAABLgAECn8XAAMYAAcJnB8JDAACAgAYAAcJnB8JDAACAgAZAAIJ8QqnTgBKAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgQJBAAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgcJCgABLgAECggJGAACAEAXAA==.',
Re='Remote:BAAALgADCggJIAAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEAAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8bAAIaAAcJ3B2KBQD3AQAaAAcJ3B2KBQD3AQAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgMJBQAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8GAAMBAAUJpw/iEQC6AAABAAUJpw/iEQC6AAAbAAEJrwlZCgBTAAAuAAQKfx8ABBsABwmTGyoHAPQBABsABgnVHioHAPQBAAEABQnGFzolAM8AABwAAQn7F8cQAEoAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJBgABLgAECggJHwAPADgYAA==.Shzam:BAAALgADCgYJCQAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIdAAkJAA6VDQBfAQAdAAkJAA6VDQBfAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQeAAkJnBePHAAFAgAeAAgJeRaPHAAFAgAfAAMJ6QoRQwCpAAAgAAIJLRE4FABOAAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8RAAMVAAcJaBVrBQB7AQAVAAcJaBVrBQB7AQAUAAEJoAa2CwBTAAAuAAQKfyYAAxUACAmIJMYTALACABUACAlhI8YTALACABQABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBgABAKcPAA==.',
Sp='Spongeybob:BAAALgADCgEJAQAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgADCgQJBgAAAA==.',
Ta='Taelia:BAACLgAFFH8LAAIIAAQJBAsxOAAqAQAIAAQJBAsxOAAqAQAuAAQKfzUAAggACQkJIMQHAOACAAgACQkJIMQHAOACAAAA.Tahine:BAAALgAECgYJDQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAECggJKQAPAO8ZAA==.Timetwoflame:BAABLgAECn8ZAAIhAAgJ5RGZCADbAQAhAAgJ5RGZCADbAQAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJBwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAAALgAECgYJEgAAAA==.',
Ur='Urkel:BAAALgADCgIJAgAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8fAAIfAAgJmQZjDAAMAQAfAAgJmQZjDAAMAQAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgUJBQAAAA==.',
Wi='Willowleaf:BAAALgAECgEJAQABLgAECggJHwAPADgYAA==.',
Wo='Wolffie:BAAALgAECggJDgAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAQJDAAGADQLAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8fAAMHAAgJZBygCAA3AgAHAAgJZBygCAA3AgAZAAMJ5QThSwBSAAAAAA==.',
Za='Zaelyse:BAAALgADCgMJAwAAAA==.Zaton:BAABLgAECn8WAAIGAAcJMxI5UQB3AQAGAAcJMxI5UQB3AQAAAA==.',
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

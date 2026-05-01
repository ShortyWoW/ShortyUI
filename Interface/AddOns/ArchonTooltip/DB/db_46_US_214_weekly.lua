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

local lookup = {'Warrior-Fury','Paladin-Retribution','DeathKnight-Frost','DemonHunter-Havoc','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms','Unknown-Unknown','Priest-Shadow','Evoker-Devastation','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','DeathKnight-Blood','Druid-Restoration','Paladin-Protection','DeathKnight-Unholy','Warrior-Protection','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaricus:BAAALgAECgEJAQAAAA==.',
Ab='Aberdine:BAACLgAFFH8GAAIBAAMJVAffEwDkAAABAAMJVAffEwDkAAAuAAQKfyIAAgEABwkGHYcnACACAAEABwkGHYcnACACAAAA.',
Ac='Accar:BAAALgAECgUJDQAAAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ag='Agrias:BAAALgAECgYJDAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Ambry:BAAALgAECgQJCQABLgAECggJIQACAOwOAA==.Ambryosia:BAABLgAECn8hAAICAAgJ7A6gNwBmAQACAAgJ7A6gNwBmAQAAAA==.',
An='Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAQJBwADAHoYAA==.',
Au='Auh:BAAALgADCgUJBQAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8YAAIEAAYJcA6wFgDsAAAEAAYJcA6wFgDsAAAAAA==.',
Aw='Awfulshotz:BAAALgADCgUJCwABLgAECgYJHAAFALQUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAAALgAECgcJEQAAAA==.',
Bc='Bcwarrior:BAAALgAECgYJCQAAAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bl='Blizzaga:BAAALgAECgQJBQAAAA==.',
Bo='Boiardi:BAAALgADCgcJBgAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAgAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgEJAQAAAA==.',
Bu='Burrgold:BAAALgAECgYJCwAAAA==.',
Ce='Celticwoman:BAABLgAECn8dAAMGAAcJCAjaSwANAQAGAAcJCAjaSwANAQAHAAUJyQR6OwDGAAAAAA==.',
Ch='Champina:BAAALgAECgYJCAAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAAALgAECgYJEwAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAAALgAFFAIJAgABLgAFFAIJBgAIACohAA==.',
Cl='Clockie:BAACLgAFFH8JAAIGAAIJ0CR9MwDZAAAGAAIJ0CR9MwDZAAAuAAQKfyQABAkACAnBJTUIAMgBAAYABgkIJXJFAPsBAAkABAmbJjUIAMgBAAcABAkKH7YjADsBAAEuAAUUAwkKAAoA1xgA.Clõüd:BAAALgAECgcJDQABLgAFFAQJCwAFABYNAA==.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAgAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAALAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECgcJEQAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgQJBAAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQALAAAAAA==.',
Dk='Dkcloud:BAAALgAECgYJDgABLgAFFAQJCwAFABYNAA==.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgUJBQAAAA==.',
Du='Duoduo:BAABLgAFFH8GAAIIAAIJKiH5FADGAAAIAAIJKiH5FADGAAAAAA==.Duoduomoney:BAAALgAFFAIJAgABLgAFFAIJBgAIACohAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8GAAIMAAIJIQ6wDwCnAAAMAAIJIQ6wDwCnAAABLgAFFAMJCgAKANcYAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAAALgAECgIJAwAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8aAAINAAYJmAn4BwAGAQANAAYJmAn4BwAGAQAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgIJAwABLgAECgkJLgAOANYiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgQJBwAAAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgEJAQAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8bAAQPAAYJ4xuCDQCHAQAQAAUJch7WQACsAQAPAAYJuxeCDQCHAQARAAUJLBMmTwASAQAAAA==.Grimtyr:BAAALgADCgkJEQAAAA==.Grëëdo:BAABLgAECn8YAAICAAcJqhN0LgCIAQACAAcJqhN0LgCIAQAAAA==.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJGAAEAHAOAA==.',
Hi='Hikiru:BAAALgADCgkJDgAAAA==.',
Ho='Hollowbane:BAABLgAECn8bAAMSAAgJixRJCQDXAQASAAgJ4hNJCQDXAQATAAMJpBYYCgDkAAAAAA==.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgMJAwAAAA==.Holylordpig:BAAALgAECgMJBQAAAA==.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgADCgUJBQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAcJDAAOAIgeAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8LAAIFAAQJFg1pIwBGAQAFAAQJFg1pIwBGAQAuAAQKfygAAgUACQmSHu8YABUDAAUACQmSHu8YABUDAAAA.Jand:BAAALgAECgYJDAAAAA==.Jazashi:BAAALgAECgYJDwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJBwAAAA==.Jonnytsunami:BAAALgAECgQJBAAAAA==.',
Ju='Juicycow:BAAALgAECgMJBQAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8TAAIUAAUJ+SX/AQDAAQAUAAUJ+SX/AQDAAQAuAAQKfxwAAxQACAm6Jk0CAHcDABQACAm6Jk0CAHcDABUAAQlPIfc3AF8AAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgADCgUJBQAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8FAAIWAAMJNwe6BQCTAAAWAAMJNwe6BQCTAAAuAAQKfxkAAhYACAmnETgPAIgBABYACAmnETgPAIgBAAAA.Kittyhawk:BAAALgAECggJDQAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgMJAQAAAA==.Klixx:BAAALgADCgcJHQAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8YAAISAAcJKxuFGgAuAgASAAcJKxuFGgAuAgAAAA==.',
Ku='Kuromeow:BAABLgAFFH8FAAIFAAIJYxluNgC9AAAFAAIJYxluNgC9AAAAAA==.',
La='Larake:BAAALgAECgMJBQAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgIJAgABLgAFFAMJBQAXABgcAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAAALgAECgYJDwAAAA==.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAIJBgAYAE4OAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgYJCwAAAA==.',
Lu='Lucyah:BAAALgAECgMJBAAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgEJAgAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAAALgAECgYJEgABLgAECgcJGAACAKoTAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMCAAkJYRuIJgCMAgACAAkJYRuIJgCMAgAZAAUJPwz0FgCvAAAAAA==.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAUJEAAaAM8YAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgEJAQAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mo='Monkpig:BAACLgAFFH8HAAIUAAIJsxbJIACUAAAUAAIJsxbJIACUAAAuAAQKfyMAAhQACAlpHaYLAM8BABQACAlpHaYLAM8BAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAAALgAECgYJEAAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAALAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAALAAAAAA==.',
Nd='Ndeh:BAAALgAECgQJBAAAAA==.',
Ne='Nena:BAAALgADCgIJAgAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIOAAgJuBzhHQCeAgAOAAgJuBzhHQCeAgAAAA==.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIXAAYJixZADgAuAQAXAAYJixZADgAuAQAAAA==.Omie:BAAALgAECgEJAgAAAA==.',
Ov='Ovix:BAAALgADCgMJAQABLgAECgQJCwALAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBQAAAA==.',
Pe='Peaf:BAABLgAECn8aAAMBAAYJGBl6NgDOAQABAAYJGBl6NgDOAQAbAAQJlwsAHwCGAAAAAA==.Petesfeets:BAAALgADCgIJAgAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBgAAAA==.',
Qu='Quill:BAABLgAECn8eAAIaAAcJrB07SwARAgAaAAcJrB07SwARAgAAAA==.',
Ra='Raythe:BAAALgAECggJEAAAAA==.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgIJBAABLgAFFAMJBQAWADcHAA==.',
Ru='Rucker:BAABLgAECn8bAAMbAAgJChg/BQALAgAbAAgJChg/BQALAgABAAEJWAIOtQAdAAABLgAECggJHQAZAB0dAA==.Rucksy:BAABLgAECn8dAAMZAAgJHR0SBQCrAgAZAAgJHR0SBQCrAgACAAMJ/hGq/QCZAAAAAA==.Ruxsi:BAAALgAECgUJCAABLgAECggJHQAZAB0dAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwALAAAAAA==.',
Se='Sereb:BAAALgAECgQJAwAAAA==.',
Sh='Shankzmcgee:BAABLgAECn8VAAISAAYJggePGQAFAQASAAYJggePGQAFAQABLgAECgcJGAACAKoTAA==.Shardik:BAAALgAECgEJAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgcJCwAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAECgcJHgAaAKwdAA==.Shrus:BAAALgADCggJCgAAAA==.Shèrlock:BAAALgAECgcJDQAAAA==.',
Sk='Skippydippy:BAAALgAECgQJBgAAAA==.Skylin:BAAALgAECgEJAgAAAA==.',
Sl='Sleezee:BAAALgAECgMJBgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgADCgYJBgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAIJBgAYAE4OAA==.',
St='Stargasm:BAAALgAECgcJCAAAAA==.Stdmachine:BAAALgAECgYJBgAAAA==.Stonedstoner:BAAALgADCgUJBwAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8GAAIYAAIJTg7HJQCGAAAYAAIJTg7HJQCGAAAAAA==.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgEJAQAAAA==.',
Ta='Taft:BAABLgAECn8aAAIcAAgJUw7EFgBJAQAcAAgJUw7EFgBJAQAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJCQAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Ti='Timewing:BAAALgADCggJDgAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgUJCQAAAA==.Tritin:BAAALgAECgYJDQAAAA==.',
Tw='Twiltock:BAAALgAECgYJCwAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8UAAIFAAYJSgXYfADbAAAFAAYJSgXYfADbAAAAAA==.Valiria:BAABLgAECn8ZAAIOAAcJyRzUHACHAQAOAAcJyRzUHACHAQAAAA==.Varzul:BAAALgADCgYJCwABLgAECgIJAgALAAAAAA==.',
Ve='Velieda:BAAALgAECgcJDgAAAA==.',
Vi='Vindication:BAACLgAFFH8FAAIXAAMJGByECAASAQAXAAMJGByECAASAQAuAAQKfxoAAhcACAkDICsHAL0CABcACAkDICsHAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJBgAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaoduoduo:BAACLgAFFH8GAAICAAIJDx0fHwCxAAACAAIJDx0fHwCxAAAuAAQKfyEAAgIACAnDIv4RACoCAAIACAnDIv4RACoCAAEuAAUUAgkGAAgAKiEA.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgIJAwAAAA==.',
Ze='Zeroskills:BAAALgAECggJEwAAAA==.',
Zu='Zulinar:BAAALgAECgEJAQAAAA==.Zumoku:BAAALgADCgkJFgAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8UAAIWAAgJbQ9cFwAAAQAWAAgJbQ9cFwAAAQAAAA==.',
['Æn']='Ænimá:BAAALgADCgEJAQAAAA==.',
['ßi']='ßiggysmalls:BAAALgADCgUJBQAAAA==.',
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

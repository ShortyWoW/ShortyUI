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

local lookup = {'Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Mage-Frost','Priest-Shadow','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Evoker-Devastation','Priest-Holy','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Unknown-Unknown','Paladin-Retribution','Monk-Mistweaver','Priest-Discipline','Shaman-Enhancement','Shaman-Elemental','Druid-Restoration','DemonHunter-Devourer','Warlock-Affliction','Monk-Brewmaster','Druid-Feral','Druid-Guardian','Paladin-Protection','DeathKnight-Frost','Hunter-Survival',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Ado:BAAALgAECgEJAQAAAA==.',
Ae='Aelestus:BAABLgAECn8eAAIBAAgJqyKDAAC2AgABAAgJqyKDAAC2AgAAAA==.Aelèna:BAABLgAECn8dAAMCAAcJTSBIBAB7AgACAAcJTSBIBAB7AgADAAMJEg1sVACXAAAAAA==.Aerion:BAAALgAECgEJAQAAAA==.Aethylthryth:BAAALgADCgMJAwAAAA==.',
Af='Aft:BAACLgAFFH8LAAIEAAQJLxNCAwAaAQAEAAQJLxNCAwAaAQAuAAQKfxsAAgQACQn3GC0MAE4CAAQACQn3GC0MAE4CAAAA.Aftdruid:BAAALgAECgYJBwABLgAFFAQJCwAEAC8TAA==.',
Ag='Agonize:BAAALgADCgUJCAAAAA==.Agörab:BAAALgAECgIJAgAAAA==.',
Ai='Airdeezy:BAABLgAFFH8GAAIFAAQJJQwiDABBAQAFAAQJJQwiDABBAQAAAA==.Aislin:BAAALgADCgYJDAAAAQ==.',
Ak='Akkord:BAAALgAECgYJBwAAAA==.Akumu:BAABLgAECn8eAAMGAAcJ4xnYDQDoAQAGAAcJcRnYDQDoAQAHAAYJBxRFdQBzAQAAAA==.',
Al='Alarkin:BAAALgAECgUJBQABLgAFFAQJCQAIAGARAA==.Alcarde:BAABLgAECn8jAAIJAAgJUA8IFQCaAQAJAAgJUA8IFQCaAQAAAA==.Aldoan:BAAALgAECgMJAwAAAA==.Alfurian:BAAALgADCgYJBgAAAA==.Alistiri:BAABLgAECn8bAAIKAAgJux62AQBeAgAKAAgJux62AQBeAgAAAA==.Alistraza:BAACLgAFFH8TAAILAAQJ0BGNBgBXAQALAAQJ0BGNBgBXAQAuAAQKfy0AAgsACAkAI/QWAPICAAsACAkAI/QWAPICAAAA.Alix:BAABLgAECn8UAAMMAAYJbCFmBQA4AgAMAAYJbCFmBQA4AgANAAIJ/B4WUQCiAAAAAA==.Allforge:BAABLgAECn8WAAIFAAYJJhXmEAAhAQAFAAYJJhXmEAAhAQAAAA==.Almina:BAAALgAECgYJCwAAAA==.Alpal:BAACLgAFFH8LAAIOAAQJ8yUjAwC5AQAOAAQJ8yUjAwC5AQAuAAQKfywAAg4ACAkPJmMAACIDAA4ACAkPJmMAACIDAAAA.',
An='Andalya:BAAALgAECgYJEQAAAA==.Ando:BAAALgADCgYJBgABLgAFFAUJDwAPAE8YAA==.Angelenaholy:BAABLgAECn8UAAIQAAgJYRS9GwD/AQAQAAgJYRS9GwD/AQAAAA==.Animantarx:BAAALgADCgcJCgAAAA==.',
Ap='Aprix:BAAALgAECgQJBQAAAA==.',
Ar='Aralyn:BAAALgADCgMJAwAAAA==.Arejay:BAAALgAECgIJAgAAAA==.Arshika:BAABLgAECn8bAAIJAAYJfxiMHwBYAQAJAAYJfxiMHwBYAQAAAA==.Arthonix:BAAALgAFFAEJAQAAAA==.Arthurleywin:BAABLgAECn8hAAMJAAgJwQ/LIQBMAQAJAAgJwQ/LIQBMAQARAAEJzQG7IQAlAAAAAA==.Arvis:BAAALgADCgYJBgAAAA==.',
As='Ascadian:BAAALgAECgYJAwAAAA==.Ashaki:BAAALgAECgYJDAAAAA==.Asmodéus:BAAALgADCgYJCgAAAA==.',
At='Athena:BAEALgADCgMJAwAAAQ==.Atla:BAAALgAECgQJCAAAAA==.Atretes:BAAALgADCgcJCQAAAA==.',
Au='Audi:BAAALgAECgcJEwAAAA==.Auroramoon:BAAALgAECgUJCQAAAA==.Autobots:BAAALgADCgQJBAAAAA==.',
Ax='Axionar:BAABLgAECn8iAAQSAAgJAxXqHACdAQASAAYJBBfqHACdAQATAAgJLBVADAAlAQAPAAIJ9w7CNABuAAAAAA==.',
Az='Azeroth:BAAALgAECgMJAwAAAA==.Azshauria:BAAALgADCgEJAQAAAA==.Azurend:BAABLgAECn8YAAMTAAYJ5BViCgA/AQAPAAYJRRL9GgBZAQATAAYJXRRiCgA/AQAAAA==.',
Ba='Babunii:BAAALgADCgcJEQAAAA==.Baeblades:BAAALgADCgYJBgABLgAFFAQJCQAIAGARAA==.Bahula:BAABLgAECn8bAAIUAAcJAQY8VwAqAQAUAAcJAQY8VwAqAQAAAA==.Bainehuln:BAAALgAECgYJDAAAAA==.Bainezhull:BAAALgAECgMJBAAAAA==.Bastianos:BAAALgAECgYJEQAAAA==.Batsom:BAAALgAECgcJDgAAAA==.Batsop:BAAALgADCgMJAwAAAA==.Battlekattel:BAAALgADCgIJAgAAAA==.',
Be='Bearbuttkick:BAAALgADCgcJEQABLgAFFAUJCwANAAMIAA==.Beekeeper:BAAALgAECgEJAQAAAA==.Bellapearl:BAAALgAECgMJBAAAAA==.Belvis:BAAALgAECgMJAwAAAA==.Benthus:BAAALgADCgYJBgAAAA==.Benzoth:BAAALgADCgYJCgAAAA==.Bergin:BAAALgAECgcJEwAAAA==.Bernes:BAAALgADCgUJBQAAAA==.Besticando:BAAALgADCgUJCAAAAA==.',
Bi='Bigteef:BAAALgADCgEJAQAAAA==.Bigtimestuff:BAAALgADCgEJAQAAAA==.Bigzaddy:BAAALgADCgYJBgAAAA==.Biozone:BAAALgADCgYJBgAAAA==.Birdhouse:BAAALgAECgUJCwAAAA==.',
Bl='Blackthornn:BAACLgAFFH8LAAMNAAQJgBNoCABjAQANAAQJgBNoCABjAQAMAAEJyggRAwBZAAAuAAQKfywAAw0ACAkXItEJAPUCAA0ACAlpIdEJAPUCAAwABgm0I0MLAHgBAAAA.Blade:BAAALgADCgEJAQAAAA==.Blkmagic:BAAALgAECgUJBwAAAA==.Bloodcircus:BAABLgAECn8aAAMFAAgJziM7BQBUAwAFAAgJziM7BQBUAwAVAAEJxwduPABAAAAAAA==.Bloodreign:BAABLgAECn8XAAICAAcJixcMAwBcAQACAAcJixcMAwBcAQAAAA==.Blotto:BAAALgAECgQJBAAAAA==.Blottzilla:BAACLgAFFH8LAAISAAQJqRqwAgBtAQASAAQJqRqwAgBtAQAuAAQKfywAAhIACAmVIzsAAEIDABIACAmVIzsAAEIDAAAA.',
Bo='Bobbyray:BAAALgADCgYJBgAAAA==.Bobertbigg:BAAALgAFFAEJAQAAAA==.Bobó:BAAALgADCgYJCAAAAA==.Bowbuttkick:BAAALgADCgUJBQABLgAFFAUJCwANAAMIAA==.Bowfle:BAAALgAECgMJBwAAAA==.Boxiebounce:BAAALgADCgQJBAAAAA==.Boxiebrown:BAABLgAECn8dAAMWAAkJ1RYiGgBrAgAWAAkJ1RYiGgBrAgAXAAEJRQHmmgAWAAAAAA==.',
Br='Bralae:BAAALgADCgcJCAABLgAECgcJFAAJAHgbAA==.Breaya:BAAALgAECgUJCQAAAA==.Brewskiez:BAAALgAECgEJAQAAAA==.Brokuo:BAACLgAFFH8HAAMLAAUJkBbnBQBdAQALAAQJkBbnBQBdAQAEAAEJAAAbDAAAAAAuAAQKfxYAAgsACAmAGiJRAP4BAAsACAmAGiJRAP4BAAAA.Brøwnies:BAAALgADCgUJBQAAAA==.Brüdilicious:BAAALgADCgEJAQAAAA==.',
Bu='Bustinyabutt:BAAALgADCgYJBgABLgAECggJHQAYADQSAA==.Buzzlez:BAACLgAFFH8HAAIQAAQJRA2IBQArAQAQAAQJRA2IBQArAQAuAAQKfysAAxAACAmgICUBAKwCABAACAmgICUBAKwCAAoAAQn+A5BoACcAAAAA.',
['Bé']='Béchamel:BAAALgADCgMJAwABLgAFFAUJDwAPAE8YAA==.',
Ca='Cace:BAAALgADCgQJBAABLgAFFAQJBgAFACgUAA==.Calboltz:BAAALgADCgMJAwAAAA==.Camspally:BAAALgAECgQJBwAAAA==.Camthomp:BAEALgAECggJEgAAAA==.Carnage:BAAALgAECgYJDQAAAA==.Carvo:BAAALgADCgQJBgAAAA==.Cassady:BAABLgAECn8aAAMLAAgJFB9OLQCDAgALAAgJFB9OLQCDAgAEAAEJeBWCQwA7AAAAAA==.Cat:BAABLgAECn8UAAIYAAcJ9xzuBADIAQAYAAcJ9xzuBADIAQAAAA==.Caìrin:BAAALgAECgUJBwABLgADCgIJFAAZAAAAAA==.',
Ce='Celd:BAEALgAECgcJEgAAAA==.Celmac:BAAALgAECgEJAQAAAA==.',
Ch='Chaddrique:BAAALgAECgUJDAAAAA==.Chanterelle:BAAALgAECgYJEgAAAA==.Cheerwine:BAAALgAECgMJBQAAAA==.Cheezits:BAABLgAECn8WAAIaAAgJ3SOyEgD9AgAaAAgJ3SOyEgD9AgAAAA==.Chellevisty:BAAALgADCgYJBgAAAA==.Chiforce:BAABLgAECn8fAAIbAAYJUBkpKAB1AQAbAAYJUBkpKAB1AQAAAA==.Chronicle:BAAALgAECgQJBwAAAA==.Chrysus:BAAALgADCgcJDgAAAA==.',
Cl='Clinician:BAABLgAECn8cAAMQAAgJaheIFgAoAgAQAAgJ+xaIFgAoAgAcAAEJEyUbEwBsAAAAAA==.Clowncar:BAAALgADCgkJCQAAAA==.',
Cn='Cndr:BAAALgAECgEJAQAAAA==.',
Co='Cowbunga:BAAALgADCggJCAAAAA==.',
Cr='Crazzenburns:BAAALgAECgYJEAABLgAECggJHwASAOoRAA==.Creamer:BAABLgAECn8cAAQUAAgJagooEwAbAQAUAAgJagooEwAbAQAdAAIJAgicJwBiAAAeAAEJSQGqLAAfAAAAAA==.Crunched:BAACLgAFFH8LAAMYAAQJUgrlCwArAQAYAAQJUgrlCwArAQAfAAIJ4APhDQB6AAAuAAQKfywAAxgACAmkHAIDAA4CABgACAmkHAIDAA4CAB8AAwntClmtAGsAAAAA.Crunches:BAAALgAECgEJAQABLgAFFAQJCwAYAFIKAA==.',
Cu='Cutedwarfxd:BAACLgAFFH8OAAIEAAUJ9CMZAQCHAQAEAAUJ9CMZAQCHAQAuAAQKfxcAAgQACQn/IycCAFUDAAQACQn/IycCAFUDAAAA.',
Cw='Cwds:BAAALgAECgUJCwAAAA==.',
['Cä']='Cärtä:BAAALgADCgMJAwAAAA==.',
['Cø']='Cøøkies:BAAALgADCgEJAQAAAA==.',
Da='Dabstar:BAAALgADCgUJBQAAAA==.Danìel:BAACLgAFFH8LAAIgAAQJBhGnCAAqAQAgAAQJBhGnCAAqAQAuAAQKfywAAiAACAmqIycCAJ4CACAACAmqIycCAJ4CAAAA.Darkarts:BAAALgAECgYJEQAAAA==.Darkblyte:BAAALgADCgEJAQAAAA==.Darkdaddy:BAAALgAECgYJDgAAAA==.Dartwo:BAAALgAECgQJBgAAAA==.',
De='Deadly:BAAALgAECgEJAQAAAA==.Deadlyshot:BAAALgAECgMJAwAAAA==.Deadlysniper:BAAALgADCgQJBAAAAA==.Deadnord:BAAALgAECgEJAQAAAA==.Deannisa:BAAALgAECgUJBQAAAA==.Deathmos:BAAALgADCgQJBAAAAA==.Deathshand:BAAALgADCgEJAQAAAA==.Debuffle:BAAALgADCgIJAgAAAA==.Deftonezz:BAAALgAECgYJBgAAAA==.Delecto:BAAALgADCgEJAQAAAA==.Dementedsage:BAAALgADCgEJAQAAAA==.Dendalaus:BAACLgAFFH8LAAINAAQJJSMNAQCLAQANAAQJJSMNAQCLAQAuAAQKfycAAw0ACAlHJNQDAF0DAA0ACAlHJNQDAF0DAAwABgngF6wMAFYBAAAA.Denny:BAAALgAECgMJAwABLgAECggJKQAUAPkdAA==.Denriak:BAAALgADCgcJCwAAAA==.Destoroyah:BAAALgADCgkJCQAAAA==.Desy:BAABLgAECn8UAAMHAAcJoiVsFQDVAgAHAAcJoiVsFQDVAgAGAAEJAADAZABFAAAAAA==.Devi:BAAALgAECgYJDwAAAA==.Devilsspawn:BAAALgADCgQJBAABLgAECgQJCwAZAAAAAA==.Devora:BAEALgADCgEJAQAAAA==.Dewdadew:BAAALgADCgMJAwAAAA==.',
Di='Diddyb:BAAALgAECgcJAwAAAA==.Dimsumbun:BAAALgAECgUJCgAAAA==.Dinklecold:BAAALgAECgEJAQAAAA==.Dinoxeye:BAAALgAECgYJCgAAAA==.Dizzies:BAAALgAECgEJAQAAAA==.',
Do='Donmar:BAAALgADCgQJBAABLgAECgYJEgAZAAAAAA==.Donmu:BAAALgAECgYJEgAAAA==.Donut:BAAALgAECgUJBgAAAA==.Donyi:BAAALgADCgUJBQAAAA==.Donzen:BAAALgADCgYJCwABLgAECgYJEgAZAAAAAA==.Dotholiday:BAABLgAECn8VAAMHAAYJ2Q2hIAAdAQAHAAYJ2Q2hIAAdAQAGAAEJAABFegAoAAAAAA==.Dotyoudead:BAAALgAECgQJBAAAAA==.',
Dr='Draacarys:BAAALgAECgQJBQAAAA==.Dramonk:BAACLgAFFH8PAAMIAAUJ/xSDAwD4AAAIAAMJdReDAwD4AAAbAAMJQgeoEACXAAAuAAQKfyAAAwgACQmcIOcIAOoCAAgACAmkIucIAOoCABsAAQn5DjBjAEQAAAAA.Drewmert:BAAALgAECgEJAQAAAA==.Druinlock:BAAALgAECgMJBwAAAA==.',
Du='Dustybuds:BAABLgAECn8UAAIBAAgJhRSrEgDeAQABAAgJhRSrEgDeAQAAAA==.Dustydrewid:BAAALgADCgEJAQAAAA==.',
Dw='Dwaynà:BAAALgAECgYJEwAAAA==.',
Dy='Dyre:BAABLgAECn8WAAIWAAgJyxJAMQDrAQAWAAgJyxJAMQDrAQAAAA==.Dyrefang:BAAALgADCggJCAAAAA==.',
['Dè']='Dèxx:BAAALgADCgEJAQABLgADCgUJBQAZAAAAAA==.',
['Dë']='Dëxx:BAAALgADCgUJBQAAAA==.',
Ed='Edam:BAAALgAECgQJBgAAAA==.Edgy:BAAALgADCgcJBwAAAA==.',
El='Elaris:BAAALgADCgcJEQAAAA==.Elementdeath:BAAALgAECgUJCQAAAA==.Eltariel:BAAALgADCggJCwAAAA==.Elyiana:BAAALgAECgYJCgAAAA==.',
Em='Emeraldjin:BAABLgAECn8UAAIbAAYJGRXKJwB4AQAbAAYJGRXKJwB4AQAAAA==.Emeria:BAAALgADCgQJBAAAAA==.Emerialock:BAAALgAECgMJBAAAAA==.Emrots:BAAALgADCgEJAQAAAA==.',
En='Ensera:BAAALgAECgUJCQAAAA==.Envymonkk:BAAALgAECgEJAQAAAA==.',
Es='Esdraa:BAAALgAECgYJCAAAAA==.',
Eu='Eugenekrabs:BAAALgADCgkJCQAAAA==.',
Ev='Evilbang:BAAALgADCgcJBwABLgAECgQJBgAZAAAAAA==.',
Ex='Exton:BAAALgAECgIJAwAAAA==.Extraho:BAABLgAECn8UAAIQAAcJyCE0CgCqAgAQAAcJyCE0CgCqAgAAAA==.',
Ez='Ezo:BAAALgAECgYJEgAAAA==.',
Fa='Fabed:BAAALgADCgYJBgAAAA==.Fabled:BAACLgAFFH8PAAQGAAUJPRirAQC2AAAHAAMJyhRiIgD7AAAGAAMJXhWrAQC2AAAhAAEJAABKAgAAAAAuAAQKfyAAAwYACQk2I+kHAEcCAAYABglVIukHAEcCAAcABgkUIgk3ADACAAAA.Faeyice:BAAALgAECgYJEQAAAA==.Falcondawn:BAAALgADCgYJCAAAAA==.Fat:BAAALgAECgQJCQAAAA==.',
Fe='Feldrie:BAAALgADCgEJAQAAAA==.Feta:BAAALgADCgQJBAAAAA==.Feyden:BAAALgAECgYJEQAAAA==.Feärless:BAABLgAECn8VAAIgAAYJahckWACZAQAgAAYJahckWACZAQAAAA==.',
Ff='Ffxivcatgirl:BAAALgAFFAIJAgAAAA==.',
Fi='Fijaswarerth:BAAALgAECgYJCwAAAA==.Fijaswitcher:BAAALgAECgEJAQAAAA==.Fimbulvargr:BAAALgAECgYJEQAAAA==.Fingerless:BAAALgAECgEJAgABLgAECgEJAwAZAAAAAA==.Finiith:BAACLgAFFH8JAAMIAAQJYBFeBQAzAQAIAAQJYBFeBQAzAQAbAAEJPgKYGQA0AAAuAAQKfyYABAgACAmdIasAALECAAgACAmdIasAALECACIABwltG0kmANIBABsAAQnMAkJ0AB4AAAAA.Firedragonoo:BAAALgADCgMJAwAAAA==.Firegirl:BAAALgADCgUJBQAAAA==.',
Fl='Fluffykicks:BAAALgAECgMJAwAAAA==.Fluffyokami:BAABLgAECn8bAAIjAAcJohXSDQDWAQAjAAcJohXSDQDWAQAAAA==.Fluggerblub:BAAALgAECgMJAwAAAA==.',
Fo='Foehn:BAAALgADCgEJAQAAAA==.Fohl:BAAALgAECgQJCAAAAA==.Foneer:BAAALgADCgUJBQAAAA==.Fonkadin:BAAALgADCgUJBQAAAA==.Fooba:BAAALgAECgcJEQAAAA==.Forestsky:BAAALgAECgYJEQAAAA==.Foxybeast:BAAALgADCgEJAQAAAA==.',
Fr='Frenchieboi:BAAALgAECgcJDAAAAA==.Frostbitedew:BAAALgAECgQJCAAAAA==.Frosttynips:BAAALgADCgYJBQAAAA==.',
Ga='Gampo:BAAALgADCgUJBQAAAA==.',
Gh='Gherim:BAAALgADCgUJDQAAAA==.Ghosimoon:BAABLgAECn8bAAMjAAcJ2RjkDQDVAQAjAAcJGhjkDQDVAQAYAAcJCBV1KwCmAQAAAA==.',
Gi='Gimixx:BAAALgAECgYJEAAAAA==.',
Gl='Glaivier:BAABLgAECn8XAAIgAAYJzxbSXgCEAQAgAAYJzxbSXgCEAQAAAA==.Glavestation:BAAALgADCgYJCQAAAA==.',
Go='Goregrind:BAACLgAFFH8JAAILAAQJ+RHzBgBTAQALAAQJ+RHzBgBTAQAuAAQKfywAAgsACAlFIpkBALkCAAsACAlFIpkBALkCAAAA.Gorius:BAAALgADCgkJGgAAAA==.',
Gr='Gravik:BAAALgADCgMJBgAAAA==.Gremory:BAABLgAECn8YAAIYAAYJBB2EBwCCAQAYAAYJBB2EBwCCAQAAAA==.Grommak:BAAALgADCgYJBgAAAA==.',
Gu='Guizee:BAAALgAFFAIJAwAAAA==.Guretta:BAAALgAECgYJEQAAAA==.',
Ha='Haeneros:BAAALgAECgYJEAAAAA==.Halokitty:BAAALgADCgYJCwAAAA==.Handmemytank:BAAALgAECggJDQAAAA==.Harumi:BAABLgAECn8dAAMjAAcJtRphCgAkAgAjAAcJtRphCgAkAgAkAAIJUg/uKQBTAAAAAA==.',
He='Heaf:BAAALgADCgIJAgABLgAECgcJEAAZAAAAAA==.Heafk:BAAALgAECgQJCAABLgAECgcJEAAZAAAAAA==.Heafstaag:BAAALgADCgQJBAABLgAECgcJEAAZAAAAAA==.Heavyburden:BAAALgAECgMJAwAAAA==.Hedgehog:BAABLgAECn8eAAIbAAgJLx58CgCqAgAbAAgJLx58CgCqAgAAAA==.Heelwhoopya:BAAALgADCgkJFgAAAA==.Helious:BAAALgAECgEJAQAAAA==.Hellastupid:BAAALgADCgUJBQAAAA==.Hellsham:BAAALgAECgMJBAAAAA==.Hextrathicc:BAABLgAECn8VAAIHAAgJiBRvRAD+AQAHAAgJiBRvRAD+AQAAAA==.Heywood:BAAALgAECgUJBQAAAA==.',
Hi='Hiddenmight:BAACLgAFFH8LAAINAAUJAwj+CgA8AQANAAUJAwj+CgA8AQAuAAQKfxwAAg0ACQkgHKYNAMICAA0ACQkgHKYNAMICAAAA.Hindü:BAAALgAECgQJCgAAAA==.',
Ho='Hogglefard:BAABLgAECn8UAAIaAAcJdCA9KACEAgAaAAcJdCA9KACEAgAAAA==.Holybuttkick:BAAALgAECgcJEwABLgAFFAUJCwANAAMIAA==.Holycöw:BAAALgADCgQJBAAAAA==.Holyrei:BAAALgADCgYJCgAAAA==.Hons:BAACLgAFFH8RAAIgAAUJDCBdBQDTAQAgAAUJDCBdBQDTAQAuAAQKfyMAAiAACQkOJhIBANMDACAACQkOJhIBANMDAAAA.',
Hu='Huneybunz:BAABLgAECn8UAAIkAAYJfgjMHQCzAAAkAAYJfgjMHQCzAAAAAA==.Hunglee:BAAALgADCgYJBwAAAA==.',
Ib='Ibis:BAAALgADCgYJBgAAAA==.',
Ic='Iceloving:BAAALgADCgEJAQABLgAECgYJEAAZAAAAAA==.',
Id='Idomagic:BAAALgAECgMJBAAAAA==.',
Ig='Igne:BAAALgADCgEJAQAAAA==.Igniting:BAAALgAECgIJAwABLgAECgYJFwAgAM8WAA==.',
Im='Implant:BAACLgAFFH8QAAIfAAUJACVkAAAnAgAfAAUJACVkAAAnAgAuAAQKfxwAAx8ACQnmJCMBAKMDAB8ACQnmJCMBAKMDABgAAwmnIR1HABEBAAAA.Impression:BAAALgADCgYJBgABLgAFFAUJEAAfAAAlAA==.Impweaver:BAAALgADCgcJCwABLgAFFAUJEAAfAAAlAA==.',
In='Incursion:BAAALgAECgYJEAAAAA==.',
Io='Ioboma:BAAALgADCgYJBgAAAA==.',
Ir='Ironwolf:BAABLgAECn8eAAIBAAgJOxJSFQC4AQABAAgJOxJSFQC4AQAAAA==.',
Is='Isharuu:BAAALgAECgYJCwAAAA==.',
Ja='Jabbawockey:BAABLgAECn8WAAIgAAkJVhyRAgCLAgAgAAkJVhyRAgCLAgAAAA==.Jackpot:BAAALgAECgUJBgAAAA==.Jademoot:BAAALgAECgYJDQAAAA==.Jaden:BAAALgAECgYJEAAAAA==.Janoria:BAAALgAECgYJCwAAAA==.Jaxurbate:BAAALgADCgcJCwAAAA==.Jaylaah:BAAALgAECgMJAwAAAA==.',
Ji='Jiinn:BAAALgAECgQJBwAAAA==.',
Jj='Jjman:BAAALgAECgcJBwABLgAECgkJCgAZAAAAAA==.Jjuicyfruit:BAAALgAECgMJBwAAAA==.',
Jo='Joftokal:BAAALgAECgYJDAAAAA==.Joranji:BAAALgADCgUJBQAAAA==.Jovick:BAAALgADCgMJAwAAAA==.Joyboy:BAABLgAECn8oAAMOAAgJLiTnBwDwAgAOAAcJyiXnBwDwAgAaAAEJ4xCpVABDAAAAAA==.',
Ju='Judeau:BAAALgAECgEJAQAAAA==.Jueya:BAAALgAECgYJCgAAAA==.',
Ka='Kalenex:BAAALgADCgkJGAAAAA==.Kalim:BAAALgAECgUJBwAAAA==.Kargran:BAAALgAECgUJDQAAAA==.Kattle:BAABLgAECn8sAAIdAAgJsiNSAAC+AgAdAAgJsiNSAAC+AgAAAA==.',
Ke='Keisero:BAAALgADCgQJBAAAAA==.Keyrasky:BAAALgADCgkJDAAAAA==.',
Kh='Khailyn:BAAALgADCgUJBQAAAA==.Kharrock:BAAALgADCgcJBwAAAA==.Khrysus:BAABLgAECn8WAAMGAAgJQBQlAgCAAQAGAAcJdhQlAgCAAQAHAAYJnga5sgDzAAAAAA==.',
Ki='Kidkill:BAAALgAECgQJCAAAAA==.Kikuu:BAABLgAECn8UAAMlAAYJGhkaFACLAQAlAAYJGhkaFACLAQAaAAIJ3wdwIAFcAAAAAA==.Killadin:BAABLgAECn8fAAIaAAgJZAwxGgBTAQAaAAgJZAwxGgBTAQAAAA==.Killian:BAAALgADCgMJAwAAAA==.Kitå:BAEBLgAECn8bAAIUAAcJyB+iEgCBAgAUAAcJyB+iEgCBAgAAAA==.',
Kl='Kloud:BAAALgAECgcJBwABLgAECgEJAQAZAAAAAA==.',
Kn='Knoks:BAAALgAECgQJBQAAAA==.Knotty:BAAALgADCgYJBQAAAA==.Knuckleup:BAAALgADCgYJBgABLgAECgQJCgAZAAAAAA==.',
Ko='Koff:BAACLgAFFH8NAAIbAAUJ8hzkBACPAQAbAAUJ8hzkBACPAQAuAAQKfyMAAhsACQnTJi8AAPADABsACQnTJi8AAPADAAAA.Koino:BAAALgADCgkJCQAAAA==.Koreshei:BAAALgAECgUJBQAAAA==.Kothar:BAAALgADCggJGwAAAA==.',
Kr='Krenerokos:BAAALgAECgEJAQAAAA==.Kruxvoidscar:BAAALgADCgcJBwAAAA==.',
Ku='Kungfuchino:BAAALgADCgQJBwAAAA==.Kuni:BAAALgAECgYJEQAAAQ==.Kurius:BAAALgADCgEJAQAAAA==.',
Kw='Kwille:BAAALgADCgEJAQAAAA==.',
Ky='Kylian:BAABLgAECn8ZAAMmAAgJyBSjBwB/AQALAAgJUw95cACnAQAmAAYJxhajBwB/AQAAAA==.Kyouk:BAAALgADCgcJCgAAAA==.',
Kz='Kz:BAAALgAECgUJBQAAAA==.',
La='Ladrious:BAAALgAECgQJBQAAAA==.Lamynx:BAAALgADCgkJCgAAAA==.Landarel:BAAALgADCgIJAgABLgADCgIJFAAZAAAAAA==.Lanestina:BAAALgADCgMJAwAAAA==.Lawctor:BAABLgAECn8XAAIOAAYJRhslDgBcAQAOAAYJRhslDgBcAQAAAA==.Lawordan:BAAALgADCggJEgAAAA==.Laylã:BAAALgADCgQJBAAAAA==.Lazydragon:BAAALgAECgYJCAAAAA==.',
Le='Leatherbelt:BAAALgAECgQJBQAAAA==.Leebruce:BAAALgAECgUJDwAAAA==.Leoella:BAAALgAECgYJDAAAAA==.Leone:BAABLgAECn8dAAILAAgJTRpOCgDaAQALAAgJTRpOCgDaAQAAAA==.',
Li='Liberation:BAABLgAECn8VAAIgAAYJHhgzHAAhAQAgAAYJHhgzHAAhAQAAAA==.Lickapop:BAAALgAECgIJAgAAAA==.Lileda:BAAALgADCgcJEwAAAA==.Lilgirlblue:BAAALgAECgYJEAAAAA==.Lilvoids:BAAALgAECgcJEwAAAA==.Lilwang:BAAALgADCgUJBQAAAA==.Lion:BAAALgAECgUJBwAAAA==.Littlelight:BAAALgADCgEJAQAAAA==.Livray:BAAALgADCgEJAQAAAA==.',
Ll='Llyolis:BAAALgADCgcJBwABLgAECgQJCgAZAAAAAA==.',
Ln='Lnetrapx:BAAALgAFFAEJAQAAAA==.',
Lo='Lonepanda:BAACLgAFFH8LAAIBAAQJaBQTBQAkAQABAAQJaBQTBQAkAQAuAAQKfywAAwEACAnWIIkBADcCAAEACAnWIIkBADcCAAUABwmuGaAxAOYBAAAA.Loriella:BAACLgAFFH8IAAIfAAQJFQYyDgAEAQAfAAQJFQYyDgAEAQAuAAQKfycAAh8ACAmMG+gUAI4CAB8ACAmMG+gUAI4CAAAA.Lorstus:BAAALgADCgEJAQAAAA==.',
Lu='Luciliv:BAAALgAECgUJBQAAAA==.Lucille:BAAALgAECgUJBgAAAA==.Lunabomb:BAAALgADCgIJAgAAAA==.Lupinaea:BAAALgADCgcJDwAAAA==.',
Ly='Lylithh:BAAALgADCgMJAwAAAA==.',
['Lí']='Lílith:BAAALgAECgIJAgAAAA==.',
Ma='Maalk:BAABLgAECn8WAAMeAAgJUBfYIAAIAgAeAAYJdx/YIAAIAgAUAAYJEBESTABTAQAAAA==.Mabellah:BAAALgADCgQJBwAAAA==.Maemikyu:BAABLgAECn8iAAIQAAgJ/iHlBgDfAgAQAAgJ/iHlBgDfAgAAAA==.Magusultimis:BAAALgAECgYJCwAAAA==.Makaveli:BAAALgAECgQJCAAAAA==.Makepoop:BAABLgAECn8UAAIKAAgJoBvSEAB6AgAKAAgJoBvSEAB6AgAAAA==.Marbared:BAAALgAECgYJCwAAAA==.Marianita:BAAALgAECgQJBQAAAA==.Marlb:BAAALgAECggJEQAAAA==.Marvolio:BAAALgADCgQJBAAAAA==.Masharo:BAAALgADCgcJBwAAAA==.Mastaßlasta:BAAALgADCgMJAwAAAA==.Mathranis:BAAALgADCgUJBQABLgAECgYJEQAZAAAAAA==.',
Me='Mechasxz:BAAALgADCgEJAQAAAA==.Mediarahan:BAABLgAECn8VAAIUAAYJfx7PBwDOAQAUAAYJfx7PBwDOAQAAAA==.Melfist:BAAALgAECgUJCQAAAA==.Menara:BAAALgAECgUJCAAAAA==.Mercia:BAAALgAECgYJDQAAAA==.',
Mi='Michimichi:BAAALgADCgIJAgAAAA==.Mikiko:BAAALgAECgYJEwAAAA==.Millcreek:BAAALgAECgYJEgAAAA==.Mimiruu:BAAALgADCgIJAgAAAA==.Missindragon:BAAALgAECgYJDAAAAA==.Mistical:BAAALgADCgIJAgABLgAECgYJCgAZAAAAAA==.Mistyelliott:BAAALgAECgUJBQAAAA==.Misu:BAAALgAECgcJBwAAAA==.Mitikai:BAAALgADCgQJBAAAAA==.Mizhealin:BAAALgADCgcJDgAAAA==.Mizoafe:BAAALgADCgQJBAAAAA==.Mizof:BAAALgADCgYJBgAAAA==.Mizofee:BAAALgAECgEJAQAAAA==.Mizofer:BAAALgAECgIJAgAAAA==.',
Mn='Mntdew:BAAALgADCgIJAgAAAA==.',
Mo='Moarass:BAABLgAECn8aAAIbAAYJmhfhIwCWAQAbAAYJmhfhIwCWAQAAAA==.Mogrokrim:BAAALgADCgcJDgAAAA==.Moistyman:BAAALgAECgYJEAAAAA==.Mojogrippy:BAABLgAECn8cAAILAAgJVCHzEQAQAwALAAgJVCHzEQAQAwAAAA==.Molson:BAAALgAECgQJBAAAAA==.Monkeyfu:BAAALgAECgEJAQAAAA==.Monkuo:BAAALgAECgEJAQAAAA==.Morcaila:BAAALgAECgQJCAAAAA==.Mordif:BAAALgAECgMJAwAAAA==.Mormel:BAAALgAECgYJDwAAAA==.Mormonmom:BAAALgADCgEJAQAAAA==.Morticus:BAAALgADCgMJAwAAAA==.Motspur:BAABLgAECn8aAAMIAAcJnAVkTgDYAAAiAAYJygVJVQDvAAAIAAYJCARkTgDYAAAAAA==.Motteraxz:BAAALgAECgYJEwAAAA==.',
My='Mydland:BAAALgADCgQJBAAAAA==.Mythicc:BAAALgADCgQJBAAAAA==.',
['Mà']='Màní:BAAALgADCgIJAgAAAA==.',
Na='Nall:BAAALgADCgIJAgAAAA==.Nalliella:BAABLgAECn8UAAMFAAYJ3Qh1YwAkAQAFAAYJvwh1YwAkAQABAAEJpANTSwAmAAAAAA==.Namelesshymn:BAAALgADCgIJAwAAAA==.Naomill:BAAALgAECgEJAQAAAA==.Narial:BAAALgAECgMJAwAAAA==.Narru:BAACLgAFFH8GAAIWAAMJGB0bCQAYAQAWAAMJGB0bCQAYAQAuAAQKfyYABBYACAkSJHcFADUDABYACAkSJHcFADUDABcABgm+D45GADkBACcAAQlSCCQxAC8AAAAA.Nawah:BAAALgAECgEJAQAAAA==.Naztee:BAABLgAECn8XAAIaAAYJwiL0OwA0AgAaAAYJwiL0OwA0AgAAAA==.',
Ne='Nebyula:BAAALgAECgYJEgAAAA==.Necrovis:BAAALgAECgMJBgAAAA==.Nephylem:BAAALgADCgEJAQAAAA==.Nevervister:BAAALgADCgUJBQAAAA==.',
Ni='Nightcrwler:BAAALgAECgEJAQAAAA==.Nirathen:BAAALgADCgMJAwABLgADCgUJBwAZAAAAAA==.',
No='Nokim:BAAALgAECgEJAQAAAA==.Norieka:BAAALgAECgUJCAAAAA==.Northumbria:BAAALgADCgQJCAABLgAECgYJDQAZAAAAAA==.Noskillidan:BAACLgAFFH8LAAIgAAQJGBa8BgBAAQAgAAQJGBa8BgBAAQAuAAQKfzAAAyAACAmiILgCAIUCACAACAmiILgCAIUCAAMABgmvDTA2AC4BAAAA.Nosral:BAAALgADCgQJBAAAAA==.Nothgiel:BAAALgADCgcJBwAAAA==.Notvegan:BAABLgAECn8UAAIUAAgJnxYtLADbAQAUAAgJnxYtLADbAQAAAA==.',
Nu='Numinous:BAAALgADCggJEwABLgAECggJHwAFANkYAA==.',
Ny='Nykoleus:BAABLgAECn8bAAQhAAgJ+xWuBAAtAgAhAAgJ+xWuBAAtAgAHAAEJBwJPLgEjAAAGAAEJ8wFRfQAhAAAAAA==.Nyste:BAAALgAECgYJEwAAAA==.',
Od='Odeliah:BAAALgADCgYJBgAAAA==.Odell:BAAALgADCgEJAwAAAA==.Odinn:BAAALgAECgcJEQAAAA==.',
Oo='Oopsidiéd:BAAALgAECgYJCgAAAA==.',
Or='Orionpax:BAAALgAECgMJBQAAAA==.Orionsson:BAAALgADCgEJAQAAAA==.',
Os='Osò:BAAALgAECgYJCwAAAA==.',
Pa='Pandaboi:BAAALgAECgMJBgAAAA==.Pandapri:BAABLgAECn8cAAQcAAcJBR8QCwCGAgAcAAcJ2B4QCwCGAgAQAAQJ4heMTAAGAQAKAAIJaA7EWgBMAAAAAA==.Passivetréé:BAAALgADCgQJBAAAAA==.Patron:BAAALgAECgEJAwAAAA==.Pawnisher:BAAALgADCgMJAwAAAA==.',
Pe='Peaceviper:BAAALgADCgIJAQAAAA==.Perkyy:BAAALgADCgMJAwAAAA==.',
Ph='Philosophic:BAAALgAECgMJBAAAAA==.Phreakoff:BAAALgADCgEJAQAAAA==.Phyntom:BAAALgAECgYJBgAAAA==.',
Pi='Pibbs:BAACLgAFFH8IAAIJAAQJlB+UAwCLAQAJAAQJlB+UAwCLAQAuAAQKfyQAAgkACAm6IwgUADADAAkACAm6IwgUADADAAAA.',
Pl='Pleaseclap:BAAALgAECgUJBwAAAA==.',
Po='Poose:BAAALgAECgQJCAABLgAECgYJBgAZAAAAAA==.Porsche:BAABLgAECn8bAAIaAAgJ9h2vHgCzAgAaAAgJ9h2vHgCzAgAAAA==.Potato:BAAALgAECgMJBQAAAA==.',
Pr='Prevention:BAAALgAECgEJAQAAAA==.Priestologyy:BAAALgADCgUJBQAAAA==.Protagoras:BAAALgADCgIJAgAAAA==.',
Pu='Pulsar:BAAALgADCgkJCQABLgAECgQJBAAZAAAAAA==.',
Py='Pyreanda:BAAALgADCgEJAQAAAA==.Pyrocalypse:BAAALgADCgUJBwAAAA==.',
Ra='Raerra:BAAALgADCggJFgAAAA==.Rafig:BAACLgAFFH8LAAIJAAQJViC1AgCbAQAJAAQJViC1AgCbAQAuAAQKfywAAwkACAkxJXABAOwCAAkACAkcJXABAOwCABEABQk8I8UGAKQBAAAA.Ralii:BAABLgAECn8aAAIYAAgJeBg0CABxAQAYAAgJeBg0CABxAQAAAA==.Ralobii:BAAALgAECgMJAwABLgAECggJGgAYAHgYAA==.Ramses:BAACLgAFFH8LAAIeAAQJ1wglBgD5AAAeAAQJ1wglBgD5AAAuAAQKfyoAAh4ACAkIHJ8DAP4BAB4ACAkIHJ8DAP4BAAAA.Rasmodeus:BAAALgAECgMJBAAAAA==.Rats:BAAALgADCgMJAwAAAA==.Rayy:BAAALgAECgUJCgAAAA==.Razzuul:BAAALgAECgYJEgAAAA==.',
Re='Redhood:BAAALgAECgQJBQAAAA==.Reformed:BAAALgAECggJEwAAAA==.Regoran:BAAALgADCgIJAgAAAA==.Reinerbraun:BAAALgAECgEJAQAAAA==.Renade:BAAALgADCgcJBwAAAA==.Reshape:BAAALgADCgMJAwABLgADCgcJDAAZAAAAAA==.Restitution:BAAALgADCgMJAwAAAA==.Retdaddy:BAAALgAECgQJBwAAAA==.Return:BAAALgADCgYJBgAAAA==.Rewellus:BAAALgADCgMJBAAAAA==.',
Rh='Rhazzah:BAAALgADCggJAwABLgAECgYJDwAZAAAAAA==.',
Ri='Rigidsxz:BAAALgAECgcJCQAAAA==.Riona:BAAALgADCgMJAwABLgAECggJFQAHAIgUAA==.Riskyshammy:BAABLgAECn8fAAIUAAgJnB0EGABWAgAUAAgJnB0EGABWAgAAAA==.Riteaid:BAAALgAECgQJBQAAAA==.',
Ro='Rocfeather:BAAALgAECgUJBwAAAA==.Rodolfblanne:BAAALgAECgQJBQAAAA==.Rokushichi:BAAALgADCgIJAwABLgAECggJHgAbAC8eAA==.Roll:BAAALgAECgUJCAAAAA==.Ronok:BAABLgAECn8ZAAIFAAcJPx65BQDNAQAFAAcJPx65BQDNAQAAAA==.Rootz:BAAALgAECgYJDAAAAA==.Rorthach:BAAALgAECgQJBgAAAA==.Roseire:BAAALgAECgQJBgAAAA==.Rosemoon:BAAALgADCggJKAAAAA==.Rosethebrute:BAABLgAECn8bAAIFAAcJqhmkJQAsAgAFAAcJqhmkJQAsAgAAAA==.Rosetheholy:BAAALgAECgQJBAABLgAECgcJGwAFAKoZAA==.Rougeloving:BAAALgAECgYJEAAAAA==.Roushi:BAABLgAECn8YAAIiAAYJLCRZAwADAgAiAAYJLCRZAwADAgAAAA==.',
Ru='Ruler:BAAALgAECgUJCwAAAA==.Ruli:BAABLgAECn8hAAIWAAgJcxdPKAAXAgAWAAgJcxdPKAAXAgAAAA==.Rusticdiino:BAAALgAECgYJCwAAAA==.Ruvia:BAAALgAECgIJBQAAAA==.Ruyhunter:BAAALgADCgEJAQABLgAECgQJBgAZAAAAAA==.',
Ry='Ryshin:BAACLgAFFH8FAAINAAIJ7gTtCQCeAAANAAIJ7gTtCQCeAAAuAAQKfyQAAw0ACAkTFTYcAB0CAA0ACAnOEjYcAB0CAAwABQleFpwLAHABAAAA.',
['Ré']='Réxx:BAAALgAFFAEJAQAAAA==.',
['Rö']='Rörs:BAAALgADCgYJBgAAAA==.',
['Rø']='Røøster:BAAALgAECgQJBwAAAA==.',
Sa='Sabeck:BAAALgAECgkJCgAAAA==.Sacrébrew:BAAALgAECgIJAgAAAA==.Safi:BAAALgAECgYJDAAAAA==.Saltine:BAEALgADCgcJDQABLgAECgkJGwAUAMgfAA==.Sanctano:BAABLgAECn8kAAIOAAgJ1h/dCwC+AgAOAAgJ1h/dCwC+AgAAAA==.Sar:BAAALgADCgUJBQAAAA==.Sarrath:BAAALgAECgEJAQAAAA==.Saticdh:BAAALgAECgIJAgAAAA==.Savagesage:BAABLgAECn8dAAMWAAgJ1R3jBAAtAgAWAAgJ1R3jBAAtAgAXAAQJ1QuGZACuAAAAAA==.Saylavee:BAAALgADCgYJCQAAAA==.Sayn:BAAALgAFFAEJAQAAAA==.',
Sc='Scarringpain:BAAALgADCgEJAQAAAA==.Schultzies:BAAALgADCgcJCwABLgAECgYJDAAZAAAAAA==.Sconestorm:BAAALgAECgIJAgAAAA==.',
Sd='Sdog:BAAALgAECgQJBAAAAA==.',
Se='Seanboyylzps:BAAALgAECgQJCAABLgAECgYJEAAZAAAAAA==.Seanboyymage:BAAALgAECgYJEAAAAA==.Seina:BAAALgAECgYJEQAAAA==.Selohssa:BAAALgADCgMJAwAAAA==.Selvara:BAAALgADCgYJAwAAAA==.Sensei:BAABLgAECn8XAAINAAgJfg79HgADAgANAAgJfg79HgADAgAAAA==.Sep:BAABLgAECn8YAAIEAAcJPhQ2BwAnAQAEAAcJPhQ2BwAnAQAAAA==.Seraphymm:BAAALgAECgMJBAAAAA==.Setup:BAAALgADCgEJAQAAAA==.',
Sh='Shammydavis:BAAALgAECgQJCAAAAA==.Shammyspoons:BAACLgAFFH8PAAMeAAUJfBjXAwCqAQAeAAUJfBjXAwCqAQAUAAEJ4gqCEABLAAAuAAQKfxgAAh4ACAltIvcIAAIDAB4ACAltIvcIAAIDAAAA.Shampayn:BAAALgADCgEJAQAAAA==.Shamshiel:BAAALgADCgUJBQAAAA==.Shanke:BAAALgAECgUJBgAAAA==.Shankee:BAAALgADCgYJCwAAAA==.Shankiee:BAAALgAECgQJBAAAAA==.Shanti:BAAALgAECgYJDgAAAA==.Shaynke:BAAALgADCgMJAwAAAA==.Shaynkee:BAAALgAECgQJBwAAAA==.Shenvin:BAAALgADCgcJBwAAAA==.Shiroompa:BAAALgADCgYJBgAAAA==.Shrìke:BAAALgAECgEJAgABLgADCgIJFAAZAAAAAA==.Shupasins:BAAALgAFFAEJAQAAAA==.Shyamablue:BAAALgADCgcJCQAAAA==.',
Si='Simphoid:BAAALgADCgcJBwAAAA==.Simpleyfire:BAAALgADCgYJBgABLgAECgYJCwAZAAAAAA==.Sinadin:BAAALgADCgQJBAAAAA==.Sindraylea:BAABLgAECn8YAAILAAcJnBRJHQAxAQALAAcJnBRJHQAxAQAAAA==.Sithkill:BAAALgAECgYJDwAAAA==.',
Sk='Skelahoe:BAAALgADCgQJBAAAAA==.Skreebo:BAAALgADCgIJAgAAAA==.Skândranon:BAAALgADCgEJAQAAAA==.Skÿ:BAAALgAECgIJAgAAAA==.',
Sl='Slurpee:BAABLgAECn8XAAIJAAcJixZdGgB2AQAJAAcJixZdGgB2AQAAAA==.',
So='Sorscha:BAAALgAECgEJAQAAAA==.Sourdough:BAAALgADCgkJDAAAAA==.',
Sp='Spacekraken:BAAALgADCgYJBgABLgAFFAUJDwAeAAEUAA==.Spammy:BAABLgAECn8YAAMOAAkJxhCtAwBCAgAOAAkJxhCtAwBCAgAaAAEJCwMqTQEuAAAAAA==.Sparlyy:BAACLgAFFH8HAAIKAAQJvRp7AQBnAQAKAAQJvRp7AQBnAQAuAAQKfysAAgoACAmuJWMAAP8CAAoACAmuJWMAAP8CAAAA.Sparticus:BAAALgADCgUJBQAAAA==.Spoonsworn:BAABLgAECn8XAAMHAAgJrx8uOgAjAgAHAAcJdR4uOgAjAgAGAAMJkRWONwDXAAAAAA==.',
Ss='Sswordy:BAACLgAFFH8LAAIWAAQJTApXBAA9AQAWAAQJTApXBAA9AQAuAAQKfywAAhYACAnOHcwDAEwCABYACAnOHcwDAEwCAAAA.',
St='Stavissia:BAAALgADCggJCAAAAA==.Stimulus:BAAALgAECgcJDwAAAA==.Stonedmom:BAAALgAECgIJAgAAAA==.Stormfang:BAAALgAECgYJCAAAAA==.Straathond:BAAALgADCgEJAQABLgAECgYJEQAZAAAAAA==.',
Su='Suetonius:BAAALgADCgcJBwAAAA==.Sulfogan:BAAALgAECgYJDAABLgAECggJEQAZAAAAAA==.Sunflora:BAAALgADCgMJBwAAAA==.Sunkist:BAAALgAECgEJAQAAAA==.Sunnidi:BAAALgAECgYJEAAAAA==.Sunwell:BAAALgAECgIJAgAAAA==.Sureina:BAAALgADCgYJBQAAAA==.Surlym:BAABLgAECn8hAAIbAAgJkCADAQDFAgAbAAgJkCADAQDFAgAAAA==.Suunny:BAAALgADCgEJAQAAAA==.Suzuka:BAAALgAECgEJAQAAAA==.',
Sw='Switchglaive:BAABLgAECn8gAAMDAAgJZxRIGAAFAgADAAgJZxRIGAAFAgACAAQJDQzVBgCuAAAAAA==.',
Sy='Sylvania:BAAALgAECgUJBQAAAA==.Symphoid:BAAALgAECgUJBQAAAA==.Symphoidd:BAAALgADCgYJBgAAAA==.Syndere:BAAALgADCgYJCAAAAA==.Syrasmine:BAAALgADCgYJBwAAAA==.Syseloris:BAABLgAECn8dAAICAAgJPx0kAQAAAgACAAgJPx0kAQAAAgAAAA==.Sythion:BAAALgAECgQJBgABLgAECgUJCAAZAAAAAA==.',
['Sâ']='Sâlisbury:BAAALgADCgYJCgAAAA==.',
['Së']='Sëphy:BAAALgAECgMJBQAAAA==.',
Ta='Tabdotwin:BAAALgAECgYJEAAAAA==.Taeolen:BAAALgADCgYJBgABLgAECgYJEQAZAAAAAA==.Takova:BAAALgADCgUJDgAAAA==.Tanao:BAAALgAECgYJCgAAAA==.Tasalia:BAAALgADCgIJAgABLgAFFAQJEwALANARAA==.Taurox:BAAALgAECgQJBgAAAA==.',
Te='Teholyone:BAAALgAECgQJBwAAAA==.Tenshi:BAAALgAECgQJBAAAAA==.Terravesh:BAAALgAECgYJDQABLgAECgYJDwAZAAAAAA==.Tessia:BAAALgADCgYJCgAAAA==.',
Th='Theselin:BAAALgADCgMJAwABLgAECgYJEQAZAAAAAA==.Thog:BAAALgADCgEJAQABLgAECgYJEgAZAAAAAA==.Thundergunt:BAAALgAECgUJBgABLgAFFAEJAQAZAAAAAA==.',
Ti='Timid:BAAALgAECgMJBQAAAA==.Timidiot:BAAALgAECgYJDAAAAA==.Tintaglia:BAABLgAECn8YAAIaAAYJFQ8kJwAJAQAaAAYJFQ8kJwAJAQAAAA==.Tipsydoodles:BAABLgAECn8cAAMbAAgJ3wwVKwBfAQAbAAgJ3wwVKwBfAQAIAAEJ9gdjIwAwAAAAAA==.Tiratore:BAAALgAECgQJBAAAAA==.',
To='Toaster:BAAALgAECgYJCwAAAA==.Toni:BAAALgADCgkJHgAAAA==.Tonylazuto:BAAALgADCgQJAQAAAA==.Toodles:BAAALgADCgMJAwAAAA==.Toranaar:BAAALgADCgMJAwAAAA==.Toruk:BAAALgAECgcJEgAAAA==.',
Tr='Trigger:BAAALgADCgcJDAAAAA==.Triggers:BAAALgADCgIJAgAAAA==.Triptan:BAAALgAECgQJBAAAAA==.Trust:BAAALgAECgYJDAAAAA==.',
Tu='Tunawhale:BAABLgAECn8UAAMVAAYJSgiPIgDYAAAVAAYJdwSPIgDYAAABAAQJpgk0DAC4AAAAAA==.',
Ty='Tyloriavis:BAAALgADCgcJDwAAAA==.Tyrie:BAAALgADCgYJBwAAAA==.Tyríon:BAAALgADCgkJEgAAAA==.',
['Tù']='Tùsk:BAAALgAECgcJEwAAAA==.',
Ul='Ulfberht:BAAALgADCgIJAgAAAA==.',
Un='Uncletouchie:BAAALgAECgYJEAAAAA==.',
Va='Vados:BAAALgADCgMJAwAAAA==.Vaeliir:BAAALgAECgUJDAAAAA==.Valhart:BAABLgAECn8jAAIFAAgJkhvtAwAEAgAFAAgJkhvtAwAEAgAAAA==.Vampt:BAAALgAECgEJAgAAAA==.Vandsong:BAAALgAECgYJDwAAAA==.Vasukin:BAABLgAECn8UAAIJAAcJeBtPDgDVAQAJAAcJeBtPDgDVAQAAAA==.',
Ve='Veloura:BAAALgAECgQJBQAAAA==.Veneration:BAAALgAECgUJBgAAAA==.Vesani:BAAALgADCgYJDwAAAA==.',
Vi='Vinsama:BAAALgAECgQJBgAAAA==.Vinsamo:BAAALgADCgYJBgAAAA==.Virgocelest:BAAALgAECgYJCAAAAA==.Viridion:BAABLgAECn8YAAISAAYJwSTsAACIAgASAAYJwSTsAACIAgAAAA==.Virtues:BAABLgAECn8aAAIFAAgJHBUqJwAiAgAFAAgJHBUqJwAiAgAAAA==.',
Vo='Voidblade:BAAALgADCgYJEQAAAA==.Voido:BAAALgADCggJEgABLgAECggJHgAbAC8eAA==.Vonmack:BAAALgADCgYJDwAAAA==.Vorlos:BAAALgAECgMJAwAAAA==.Vorquin:BAABLgAFFH8IAAILAAQJsg59BwBNAQALAAQJsg59BwBNAQAAAA==.',
Vr='Vreeg:BAABLgAECn8YAAIhAAYJiBwKBwDmAQAhAAYJiBwKBwDmAQAAAA==.',
Vt='Vtec:BAABLgAECn8WAAIeAAgJRwx3NACGAQAeAAgJRwx3NACGAQAAAA==.',
Vy='Vynayro:BAAALgAECgMJAwAAAA==.',
['Vö']='Vörðr:BAAALgADCgEJAQAAAA==.',
Wa='Wargodx:BAAALgADCgUJBQAAAA==.',
We='Weep:BAAALgADCgEJAQABLgAECgcJBgAZAAAAAA==.',
Wh='Whatthehelly:BAABLgAECn8dAAMYAAgJNBLkJQDOAQAYAAgJNBLkJQDOAQAkAAYJnQHcJwBfAAAAAA==.Whoopycushin:BAAALgAECgEJAQAAAA==.Whyamialive:BAACLgAFFH8LAAIEAAQJVyVVAQB2AQAEAAQJVyVVAQB2AQAuAAQKfywAAgQACAn0JU4AAPACAAQACAn0JU4AAPACAAAA.',
Wi='Wide:BAAALgADCgYJDAAAAA==.Wiffles:BAAALgAECgQJBQAAAA==.Willowest:BAEALgAECgYJCQABLgAFFAQJDQAQAP4YAA==.Willowing:BAEALgAECgQJBwABLgAFFAQJDQAQAP4YAA==.Willowish:BAECLgAFFH8NAAIQAAQJ/hjkBQAiAQAQAAQJ/hjkBQAiAQAuAAQKfycAAhAACQnYID0BAHMDABAACQnYID0BAHMDAAAA.Willowly:BAEALgAECgUJBQABLgAFFAQJDQAQAP4YAA==.Winnhao:BAAALgADCgEJAQABLgAECggJIgASAAMVAA==.Wiskii:BAABLgAECn8XAAIlAAYJViFtCgAoAgAlAAYJViFtCgAoAgAAAA==.',
Wo='Wormwort:BAAALgAECgMJAwAAAA==.',
Wy='Wytnarthom:BAAALgAECgYJCwABLgAECggJIwAIANkUAA==.Wytohne:BAABLgAECn8jAAIIAAgJ2RSaBAC2AQAIAAgJ2RSaBAC2AQAAAA==.Wytvori:BAAALgADCgYJBgABLgAECggJIwAIANkUAA==.',
['Wý']='Wýnn:BAAALgADCgYJCQAAAA==.',
Xa='Xanrawr:BAAALgADCgUJBQAAAA==.Xaree:BAABLgAECn8YAAMbAAYJrhyvBADmAQAbAAYJrhyvBADmAQAIAAIJah6YYQCJAAAAAA==.',
Xc='Xcat:BAACLgAFFH8JAAIaAAQJ2QiBEAAiAQAaAAQJ2QiBEAAiAQAuAAQKfx4AAhoACQlFG48jAJoCABoACQlFG48jAJoCAAAA.',
Xd='Xdog:BAAALgADCgYJDQAAAA==.Xdrake:BAAALgAECgcJDQAAAA==.',
Ya='Yarnad:BAAALgADCgEJAQAAAA==.',
Yi='Yim:BAABLgAECn8UAAIaAAYJuCD2DgCvAQAaAAYJuCD2DgCvAQAAAA==.Yirtkalii:BAAALgADCgkJEwAAAA==.Yismypetdead:BAAALgADCgUJBQABLgAECgQJCgAZAAAAAA==.',
Yl='Ylifiz:BAAALgAECgEJAQAAAA==.',
Yo='Yorshka:BAABLgAECn8hAAIQAAgJLxyLCgClAgAQAAgJLxyLCgClAgAAAA==.',
Yu='Yumiella:BAAALgADCgcJBwAAAA==.',
Za='Zaelthar:BAAALgAECgUJDAAAAA==.Zatrekas:BAAALgAECgQJBAAAAA==.',
Ze='Zee:BAABLgAECn8fAAIlAAgJphFjEQCxAQAlAAgJphFjEQCxAQAAAA==.Zeff:BAABLgAECn8VAAIfAAYJzxAuFAAmAQAfAAYJzxAuFAAmAQAAAA==.Zeldris:BAAALgADCgEJAQAAAA==.Zephuros:BAAALgAECgcJEQAAAA==.',
Zi='Ziunepaws:BAAALgAECgUJBwAAAA==.',
Zo='Zompt:BAAALgAECgMJAwAAAA==.Zorionsson:BAAALgADCgEJAQAAAA==.',
Zw='Zwaard:BAAALgAECgEJAQAAAA==.',
Zy='Zyasa:BAABLgAECn8dAAMcAAgJFBI/BQC6AQAcAAgJFBI/BQC6AQAQAAMJLAKreABGAAAAAA==.Zymar:BAAALgAECgIJBQABLgAECgYJEAAZAAAAAA==.',
['År']='Årfårf:BAAALgAECgEJAQAAAA==.',
['Æl']='Ælgernon:BAAALgADCgkJCQAAAA==.',
['Æz']='Æzio:BAAALgADCgYJCQAAAA==.',
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

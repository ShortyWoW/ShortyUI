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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Mage-Fire','Unknown-Unknown','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Preservation','DeathKnight-Blood','DemonHunter-Vengeance','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Priest-Shadow','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Hunter-Survival','Rogue-Subtlety','Druid-Feral','DeathKnight-Frost','Warlock-Affliction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAMJCgABAHsWAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgADCgEJAQAAAA==.Allice:BAABLgAECn8XAAMCAAcJ3xtgAwA8AgACAAcJixtgAwA8AgABAAQJmQwupQB5AAAAAA==.Alterion:BAAALgAECgEJAgAAAA==.Altimusprime:BAAALgAECgYJBwAAAA==.',
An='Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgUJBQAAAA==.',
Au='Augnyxia:BAABLgAECn8gAAMDAAcJKBKoJACYAQADAAcJRxCoJACYAQAEAAMJBxH9NABsAAAAAA==.Augtism:BAABLgAECn8ZAAMFAAcJLyHpJwByAgAFAAcJLyHpJwByAgAGAAEJAADOXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgEJAQAAAA==.Bandobras:BAAALgAECgUJCAAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAcJFAADAEwfAA==.',
Be='Beefquake:BAAALgAECgIJAgAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Bersh:BAABLgAECn8bAAQHAAgJ1xtMBwB4AgAHAAgJ7xhMBwB4AgAIAAYJ3haXGgA/AQAJAAEJAQiOngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8UAAIKAAYJ4Rb0XwDEAQAKAAYJ4Rb0XwDEAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAAALgAECgcJEQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8bAAMLAAgJpwn6BAB9AQALAAcJtwn6BAB9AQABAAcJpQjeVQAzAQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgUJBwAAAA==.Bruceleela:BAAALgADCggJCAABLgAECgcJDwAMAAAAAA==.Brunarr:BAAALgAECgQJEAAAAA==.',
Bu='Bushetti:BAABLgAECn8ZAAMNAAcJsha+KQA+AQANAAcJsha+KQA+AQAOAAIJghdOcQBbAAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMIAAkJYBEkJQDoAQAIAAkJYBEkJQDoAQAJAAYJDhW8HgBuAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgMJBQAAAA==.Cazisham:BAAALgAECgYJDwAAAA==.',
Ce='Cevianne:BAABLgAECn8bAAIPAAgJUxJNIwCQAQAPAAgJUxJNIwCQAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chaoticsaint:BAABLgAECn8XAAIQAAgJERGFEAA1AQAQAAgJERGFEAA1AQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Co='Coal:BAABLgAECn8aAAIRAAYJ/yP9JQBvAgARAAYJ/yP9JQBvAgAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgYJGgARAP8jAA==.Coltonater:BAABLgAECn8tAAIBAAgJ7R0gDwBkAgABAAgJ7R0gDwBkAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAABLgAECn8ZAAIBAAgJFxplPACGAgABAAgJFxplPACGAgAAAA==.',
Da='Dampening:BAAALgAECgMJAwAAAA==.Danbi:BAABLgAECn8cAAISAAgJkRZPBQAHAgASAAgJkRZPBQAHAgAAAA==.',
De='Deathdylan:BAABLgAECn8YAAITAAgJ4hmaDgAkAgATAAgJ4hmaDgAkAgAAAA==.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAAALgAECgcJDwAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethpally:BAAALgADCgUJBQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgEJAQAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAAALgAECgYJDQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxKNQCeAgABAAgJmhxKNQCeAgAAAA==.Druqz:BAABLgAECn8VAAIBAAgJUQaDTwBCAQABAAgJUQaDTwBCAQAAAA==.Drævn:BAAALgAECgYJEQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8NAAMRAAQJpR8OCQBvAQARAAQJpR8OCQBvAQAUAAIJOgv5AwCLAAAuAAQKfx0AAhEABwn9IiEhAIoCABEABwn9IiEhAIoCAAAA.',
Dw='Dwimbear:BAAALgADCgEJAQAAAA==.Dwimhoof:BAAALgADCgcJCAAAAA==.',
El='Eldin:BAABLgAECn8YAAIVAAgJ6x75DwA/AgAVAAgJ6x75DwA/AgAAAA==.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgIJAgAAAA==.',
En='Enchantress:BAABLgAECn8eAAMBAAgJIQzvNgCKAQABAAgJIQzvNgCKAQACAAIJOgZRGQBNAAAAAA==.Endofdays:BAAALgAECgEJAQAAAA==.Enro:BAABLgAECn8hAAMQAAgJXBcCEgBMAgAQAAgJXBcCEgBMAgARAAQJqgdwtQCdAAAAAA==.',
Er='Erovia:BAAALgAECgcJEQAAAA==.',
Es='Esclipse:BAAALgAECgEJAQAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgADCgMJBAAAAA==.',
Fe='Felony:BAABLgAECn8aAAIQAAcJPCSGBAA1AgAQAAcJPCSGBAA1AgAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavah:BAABLgAECn8UAAIOAAcJ2x2PHAAdAgAOAAcJ2x2PHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8fAAIWAAkJIhO3VwDqAQAWAAkJIhO3VwDqAQAAAA==.Flower:BAAALgAECgcJEQAAAA==.',
Fo='Foodex:BAAALgAECgYJEAAAAA==.Fourleaf:BAABLgAECn8hAAIXAAgJmBemHwAlAgAXAAgJmBemHwAlAgAAAA==.',
Fr='Frydayx:BAAALgADCggJCwAAAA==.',
Fu='Furral:BAAALgAECgcJCgAAAA==.',
Ga='Gaeth:BAABLgAECn8fAAINAAgJaBEIQgCZAQANAAgJaBEIQgCZAQAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8UAAIRAAYJqhjPJABYAQARAAYJqhjPJABYAQAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Handlebar:BAAALgAECgEJAQABLgAECgcJDwAMAAAAAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAECgEJAQABLgAECgUJCgAMAAAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAAALgAECgYJEQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgMJAQAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAAALgAECgYJCwAAAA==.',
Is='Ishi:BAAALgAECgUJBQAAAA==.Ishpoo:BAABLgAECn8fAAIKAAgJfAySOgBbAQAKAAgJfAySOgBbAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jelqer:BAABLgAECn8VAAMEAAYJsCCTEgC4AQAEAAYJsCCTEgC4AQADAAUJZBQUMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8jAAINAAgJEB9rCACFAgANAAgJEB9rCACFAgAAAA==.',
Jo='Job:BAACLgAFFH8KAAIRAAMJZCM7EwAsAQARAAMJZCM7EwAsAQAuAAQKfygAAxEACAniI0UDAMUCABEACAniI0UDAMUCABAABgnFINAjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgEJAQAAAA==.Judoriel:BAAALgAECgUJCAAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8XAAIPAAgJ1xKHFgDeAQAPAAgJ1xKHFgDeAQAAAA==.Kaimin:BAABLgAECn8bAAIWAAgJaBqlLACJAQAWAAgJaBqlLACJAQAAAA==.Karthas:BAAALgAECgIJAwAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAMAAAAAA==.Kennypowers:BAAALgAECgQJBAAAAA==.Kezeshi:BAABLgAECn8gAAMVAAgJaxRCCAAUAgAVAAgJaxRCCAAUAgAYAAMJFAPCVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8iAAIJAAgJkgxILAAUAQAJAAgJkgxILAAUAQAAAA==.Khonsu:BAAALgAECgYJBgAAAA==.',
Ki='Kiba:BAAALgAECgYJEAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAAALgAECgYJCwAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8UAAIZAAgJOwoxDwANAQAZAAgJOwoxDwANAQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAABLgAECn8kAAMaAAkJ/h5oAwC9AgAaAAkJ/h5oAwC9AgAbAAMJdQ5wKQCrAAAAAA==.',
La='Larethiana:BAABLgAECn8UAAMNAAgJ6RSjTABxAQANAAcJjBWjTABxAQAOAAYJ9RbzNABqAQAAAA==.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMcAAYJXQMWagDSAAAcAAYJXQMWagDSAAAKAAQJRQF7IQFbAAAAAA==.',
Li='Lightbright:BAABLgAECn8WAAIKAAgJjCSWBwBaAwAKAAgJjCSWBwBaAwAAAA==.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAAALgAECgMJBQAAAA==.Linnasha:BAABLgAECn8iAAINAAgJNBWhNQDSAQANAAgJNBWhNQDSAQAAAA==.Litlefoot:BAAALgADCgkJCQAAAA==.',
Lo='Lornzap:BAAALgAFFAIJAwAAAA==.Lostwanderer:BAAALgAECgUJBwAAAA==.',
Ma='Magoo:BAAALgAECgEJAQAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8lAAIQAAgJwRR3CwCEAQAQAAgJwRR3CwCEAQAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Marble:BAAALgAECgMJAwAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8gAAMPAAgJvB2SDAA7AgAPAAcJRSKSDAA7AgAdAAIJaQxdJAB1AAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Miridian:BAAALgADCgYJBgAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgADCggJCwAAAA==.Moogician:BAAALgAECgEJAQABLgAECgUJCQAMAAAAAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8gAAINAAgJXgtfKwA0AQANAAgJXgtfKwA0AQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgMJAwAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8YAAIeAAcJNRClFAA3AQAeAAcJNRClFAA3AQAAAA==.',
My='Mydira:BAAALgAECgMJAwAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAAALgAECgQJBAABLgAECggJKgAaAOQLAA==.Nalthexon:BAAALgAECgYJBgABLgAECggJKgAaAOQLAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECggJFgAcAKUeAA==.',
Ni='Niavanith:BAAALgAECgYJBgAAAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAABLgAECn8gAAIEAAgJYRxPBgCQAgAEAAgJYRxPBgCQAgAAAA==.Nizo:BAABLgAECn8WAAINAAgJyA8HJgBVAQANAAgJyA8HJgBVAQAAAA==.',
No='Novastrike:BAABLgAECn8bAAMIAAcJFhBhSQAiAQAIAAYJBw1hSQAiAQAJAAcJ7Be/NQDgAAAAAA==.',
Ny='Nyrif:BAABLgAECn8fAAITAAgJcRrGBgC5AQATAAgJcRrGBgC5AQAAAA==.',
Oj='Ojoon:BAAALgADCgEJAQAAAA==.',
Om='Omnisllash:BAAALgAECgMJAwAAAA==.',
Or='Orisana:BAACLgAFFH8FAAMPAAMJTxAgJwCuAAAPAAIJMhUgJwCuAAAdAAEJiQbIFABPAAAuAAQKfzAABBcACQlOHtIMAN8CABcACQnAGtIMAN8CAA8ABQmAGc0lAIIBAB0AAQmmFkQoAFYAAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8IAAMSAAQJzwVmDQAIAQASAAQJzwVmDQAIAQADAAEJjghiLABIAAAAAA==.',
Ph='Phyter:BAAALgADCgQJBgAAAA==.',
Pi='Pillin:BAAALgAECgEJAQAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAAALgAECgcJEQAAAA==.Powerwordmoo:BAAALgADCgYJBwABLgAECgUJCQAMAAAAAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Provi:BAAALgAECgYJCgAAAA==.',
Ps='Psyffe:BAAALgAECgIJAgAAAA==.Psyrge:BAAALgAECgEJAQAAAA==.',
Qu='Queue:BAABLgAECn8YAAITAAcJbwvjJgAHAQATAAcJbwvjJgAHAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgIJAgAAAA==.Redle:BAAALgAECgMJAwAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAEBLgAECn8XAAMXAAgJ/RcmHgAyAgAXAAgJEhYmHgAyAgAdAAcJ7wz1DgBvAQAAAA==.',
Ro='Rokkitok:BAAALgAECgYJCwAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
['Rå']='Råwrshåk:BAAALgAECgcJEwAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgAAAA==.',
Se='Sea:BAACLgAFFH8PAAIJAAUJ/BL9BACbAQAJAAUJ/BL9BACbAQAuAAQKfyAAAgkACQmSIOQBAG4DAAkACQmSIOQBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgADCgkJCQAAAA==.Shadowrose:BAABLgAECn8XAAIfAAcJMxQWBwCOAQAfAAcJMxQWBwCOAQAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAAALgAECgQJCAAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAgAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAMAAAAAA==.Shunsui:BAABLgAECn8ZAAMFAAgJohRlUADWAQAFAAgJohRlUADWAQAGAAEJAAAabwA3AAAAAA==.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Siley:BAABLgAECn8WAAIcAAgJpR7DFABrAgAcAAgJpR7DFABrAgAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgADCgIJAgAAAA==.',
Sl='Sleepytree:BAAALgAECgYJCAAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAAALgAECgEJAwAAAA==.',
So='Sooner:BAACLgAFFH8FAAIWAAMJGh+XLAAMAQAWAAMJGh+XLAAMAQAuAAQKfxUAAyAABwkeHfAEAP0BACAABgmaH/AEAP0BABYABQkGHO1GACoBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.',
Sq='Squeaky:BAAALgAECgEJAQAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgIJAgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.',
Te='Temporary:BAAALgADCgcJFgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
Tr='Triplenine:BAEALgAECgIJAgABLgAFFAYJEwABAKIgAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.',
Tu='Tucktoo:BAAALgAECgIJAQAAAA==.',
Ty='Tyundric:BAAALgADCgUJCgAAAA==.',
Un='Unholysage:BAABLgAECn8fAAIYAAkJuA2/CQDmAQAYAAkJuA2/CQDmAQAAAA==.',
Uw='Uwurailme:BAABLgAECn8VAAQGAAcJNg8LMgDwAAAFAAYJcQxiiwBCAQAGAAUJHAoLMgDwAAAhAAIJrRN3HQCGAAAAAA==.',
Va='Valenix:BAABLgAECn8cAAMbAAgJEBGRGwAJAQAbAAcJQBCRGwAJAQAaAAcJzxLrPwDiAAAAAA==.Valkryi:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgIJAgAAAA==.',
Vo='Vo:BAAALgAECgYJDQAAAA==.',
Wa='Warder:BAAALgAECgYJEQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJBgAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wincks:BAAALgAECgUJDgAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAAALgAECgcJEAAAAA==.Zackman:BAABLgAECn8iAAIcAAgJWQicHwBKAQAcAAgJWQicHwBKAQAAAA==.',
Zi='Zinagos:BAAALgAECggJDAABLgAECggJHAAbABARAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAECgQJBQAAAA==.',
Zu='Zulrea:BAAALgAECgIJAgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJBgAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAECgUJCgAMAAAAAA==.',
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

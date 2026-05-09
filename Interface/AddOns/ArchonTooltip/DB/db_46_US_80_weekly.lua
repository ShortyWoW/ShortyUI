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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Mage-Fire','Unknown-Unknown','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','DemonHunter-Vengeance','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Paladin-Holy','Hunter-Survival','Rogue-Subtlety','Warrior-Fury','Druid-Feral','DeathKnight-Frost','Warlock-Affliction',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAMJCgABAHsWAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgADCgEJAQAAAA==.Allice:BAABLgAECn8XAAMCAAcJ3xtfAwA8AgACAAcJixtfAwA8AgABAAQJmQylrwC1AAAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAECgYJBwAAAA==.',
An='Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgYJBwAAAA==.',
Au='Augnyxia:BAABLgAECn8pAAQDAAcJqhKnJACYAQADAAcJxhCnJACYAQAEAAQJIAR5HQCFAAAFAAQJ8Q7oEABzAAAAAA==.Augtism:BAABLgAECn8hAAMGAAgJryDqFAA6AgAGAAgJryDqFAA6AgAHAAEJAADNXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgEJAQAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAgJGQADABAfAA==.',
Be='Beefquake:BAAALgAECgYJCQAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Bersh:BAABLgAECn8kAAQIAAkJEh0jBQADAgAIAAkJBhojBQADAgAJAAYJrBdJIQBGAQAKAAEJAQiGngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8YAAILAAYJohj0XwDEAQALAAYJohj0XwDEAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAAALgAECggJEgAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8iAAMBAAkJowm9SwCFAQABAAgJdQm9SwCFAQAMAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgUJDAAAAA==.Bruceleela:BAAALgADCggJCAABLgAECgcJEQANAAAAAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8aAAMOAAgJBRUYLwBmAQAOAAgJBRUYLwBmAQAPAAIJghdUcQBbAAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMJAAkJYBEkJQDoAQAJAAkJYBEkJQDoAQAKAAYJDhU7LABnAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgMJBgAAAA==.Cazisham:BAAALgAECgYJEQAAAA==.',
Ce='Cevianne:BAABLgAECn8iAAIQAAgJ8xIILQCaAQAQAAgJ8xIILQCaAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chaoticsaint:BAABLgAECn8XAAIRAAgJERHAFgAwAQARAAgJERHAFgAwAQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Cl='Claros:BAAALgAECgEJAQAAAA==.',
Co='Coal:BAABLgAECn8iAAISAAgJ2yHXCACYAgASAAgJ2yHXCACYAgAAAA==.Coalesce:BAAALgADCgQJBAABLgAECggJIgASANshAA==.Coltonater:BAABLgAECn8zAAIBAAgJiR5nFAB3AgABAAgJiR5nFAB3AgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAABLgAECn8ZAAIBAAgJFxpePACGAgABAAgJFxpePACGAgAAAA==.',
Da='Dampening:BAAALgAECgMJAwAAAA==.Danbi:BAABLgAECn8lAAQEAAkJBxe1BwD0AQAEAAgJpRa1BwD0AQADAAgJzQ44EADRAQAFAAEJAADrHAAAAAAAAA==.',
De='Deathdylan:BAABLgAECn8gAAITAAgJAxy/BwAQAgATAAgJAxy/BwAQAgAAAA==.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAAALgAECgcJEQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAABLgAECn8aAAIBAAgJTweKWgBfAQABAAgJTweKWgBfAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxINQCeAgABAAgJmhxINQCeAgAAAA==.Druqz:BAABLgAECn8VAAIBAAgJUQZuaABAAQABAAgJUQZuaABAAQAAAA==.Drævn:BAABLgAECn8ZAAMBAAYJfxABhgAGAQABAAYJcxABhgAGAQAMAAMJYw9UBgC3AAAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8SAAMSAAUJtR8pEgBoAQASAAUJtR8pEgBoAQAUAAIJQgvVBQB5AAAuAAQKfyUAAhIACAmlInkHAK8CABIACAmlInkHAK8CAAAA.',
Dw='Dwimbear:BAAALgADCgEJAQAAAA==.Dwimhoof:BAAALgADCgcJCQAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAABLgAECn8ZAAIVAAgJ6x72DwA/AgAVAAgJ6x72DwA/AgAAAA==.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJCAAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJzQsZMwDUAQABAAkJzQsZMwDUAQACAAIJOgZSGQBNAAAAAA==.Endofdays:BAAALgAECgYJBgAAAA==.Enro:BAABLgAECn8pAAMRAAgJSBiXCgDdAQARAAgJSBiXCgDdAQASAAQJqgd0tQCdAAAAAA==.',
Er='Erovia:BAABLgAECn8XAAIQAAgJtQZqXgBMAQAQAAgJtQZqXgBMAQAAAA==.',
Es='Esclipse:BAAALgAECgcJCAAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgADCgMJBAAAAA==.',
Fe='Felony:BAABLgAECn8pAAIRAAgJPSQZAgDfAgARAAgJPSQZAgDfAgAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavah:BAABLgAECn8WAAIPAAgJMR2SHAAdAgAPAAgJMR2SHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8mAAMWAAkJJROuVwDqAQAWAAkJJROuVwDqAQATAAcJDQQmIQC7AAAAAA==.Flower:BAAALgAECgcJEQAAAA==.',
Fo='Foodex:BAAALgAECgYJEAAAAA==.Fourleaf:BAABLgAECn8nAAIXAAgJVxvPBgClAQAXAAgJVxvPBgClAQAAAA==.',
Fr='Frydayx:BAAALgAECgMJAwAAAA==.',
Fu='Furral:BAAALgAFFAEJAQAAAA==.',
Ga='Gaeth:BAABLgAECn8jAAIOAAkJTxAEQgCZAQAOAAkJTxAEQgCZAQAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8UAAISAAYJqhhKOABVAQASAAYJqhhKOABVAQAAAA==.Grimvess:BAAALgAECgUJBQAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Handlebar:BAAALgAECgEJAQABLgAECgcJEQANAAAAAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAECgMJBAABLgAECgUJCgANAAAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8XAAILAAcJDBMgRwBwAQALAAcJDBMgRwBwAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgUJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Il='Ilkkarid:BAAALgADCgEJAQAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAAALgAECgYJCwAAAA==.',
Is='Ishpoo:BAABLgAECn8kAAILAAkJuQzpLgDBAQALAAkJuQzpLgDBAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jelqer:BAABLgAECn8VAAMFAAYJsCCTEgC4AQAFAAYJsCCTEgC4AQADAAUJZBQRMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8mAAIOAAkJexzACQCtAgAOAAkJexzACQCtAgAAAA==.',
Jo='Job:BAACLgAFFH8PAAISAAUJmx6REQBsAQASAAUJmx6REQBsAQAuAAQKfzUAAxIACQmCJIQBAE4DABIACQmCJIQBAE4DABEABgnFINQjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgEJAQAAAA==.Judoriel:BAAALgAECgUJCAAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8fAAIQAAgJ+BjiFQAgAgAQAAgJ+BjiFQAgAgAAAA==.Kaimin:BAABLgAECn8jAAIWAAgJUx7WGQAwAgAWAAgJUx7WGQAwAgAAAA==.Karthas:BAAALgAECgIJAwAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQANAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8oAAMVAAgJaRmHCABVAgAVAAgJaRmHCABVAgAYAAMJFAPCVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8nAAIKAAkJvRACIACzAQAKAAkJvRACIACzAQAAAA==.Khonsu:BAAALgAECgcJCwAAAA==.',
Ki='Kiba:BAABLgAECn8YAAMZAAYJeg2dJwAOAQAZAAYJeg2dJwAOAQAaAAMJTQjaPACJAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAAALgAECgYJEQAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8cAAIbAAgJpwoqEwARAQAbAAgJpwoqEwARAQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAABLgAECn8tAAMZAAkJTyBMAgA1AwAZAAkJTyBMAgA1AwAaAAMJdA4UNgCpAAAAAA==.',
La='Larethiana:BAABLgAECn8UAAMOAAgJ6RSdTABxAQAOAAcJjBWdTABxAQAPAAYJ9Rb5NABqAQAAAA==.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMcAAYJXQMaagDSAAAcAAYJXQMaagDSAAALAAQJRQF+IQFbAAAAAA==.',
Li='Lightbright:BAABLgAECn8XAAILAAgJ7ySVBwBaAwALAAgJ7ySVBwBaAwAAAA==.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAAALgAECgYJDQAAAA==.Linnasha:BAABLgAECn8nAAIOAAgJShXvJAChAQAOAAgJShXvJAChAQAAAA==.Litlefoot:BAAALgADCgkJDwAAAA==.',
Lo='Lornzap:BAAALgAFFAIJAwAAAA==.Lostwanderer:BAAALgAECgUJCAAAAA==.',
Ma='Machine:BAAALgAECgUJBQAAAA==.Magoo:BAAALgAECgIJAgAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8mAAIRAAgJIBaODwCJAQARAAgJIBaODwCJAQAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8oAAMQAAgJuh8JDQB0AgAQAAgJuh8JDQB0AgAdAAIJPRAPLgCIAAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Miridian:BAAALgAECgEJAQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgADCggJDAAAAA==.Moogician:BAAALgAECgEJAwABLgAECgkJIAAQAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8kAAIOAAgJtwzNNABGAQAOAAgJtwzNNABGAQAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgMJAwAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8hAAIeAAgJWRKgDADWAQAeAAgJWRKgDADWAQAAAA==.',
My='Mydira:BAAALgAECgMJAwAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAAALgAECgcJCQABLgAECggJKgAZAOQLAA==.Nalthexon:BAAALgAECgYJBgABLgAECggJKgAZAOQLAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAcANscAA==.',
Ni='Niavanith:BAAALgAECgYJDAAAAA==.Nights:BAAALgAECgEJAQABLgAECgUJBQANAAAAAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAABLgAECn8oAAIFAAgJph6TAQBsAgAFAAgJph6TAQBsAgAAAA==.Nizo:BAABLgAECn8dAAIOAAgJ0BweCwCXAgAOAAgJ0BweCwCXAgAAAA==.',
No='Novastrike:BAABLgAECn8jAAMKAAgJoherHwC1AQAKAAgJoherHwC1AQAJAAYJBw1lSQAiAQAAAA==.',
Ny='Nyrif:BAABLgAECn8gAAITAAgJfxrKCAD3AQATAAgJfxrKCAD3AQAAAA==.',
Oj='Ojoon:BAAALgADCgMJAwAAAA==.',
Om='Omnisllash:BAAALgAFFAEJAQAAAA==.',
Or='Orisana:BAACLgAFFH8IAAMdAAMJvBO7DwD4AAAdAAMJ6A27DwD4AAAQAAIJNxVTOQCnAAAuAAQKfzgABBcACQlkH3MMAOUCABcACQnAGnMMAOUCAB0ACQkLFvIFAFUCABAABQmAGds3AG0BAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8NAAMEAAUJQgtSCwBgAQAEAAUJQgtSCwBgAQADAAEJjgigOgBEAAAAAA==.',
Ph='Phyter:BAAALgAECgIJAwAAAA==.',
Pi='Pillin:BAAALgAECgMJBAAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8UAAIfAAcJMxsNLgD5AQAfAAcJMxsNLgD5AQAAAA==.Powerwordmoo:BAAALgADCgYJBwABLgAECgkJIAAQAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Provi:BAAALgAECgcJCwAAAA==.',
Ps='Psyffe:BAAALgAECgUJBgAAAA==.Psyrge:BAAALgAECgEJAQAAAA==.',
Qu='Queue:BAABLgAECn8gAAITAAgJBQ5+EwA+AQATAAgJBQ5+EwA+AQAAAA==.',
Re='Rebeccayaros:BAAALgAECgQJBQAAAA==.Redle:BAAALgAECgcJDAAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAEBLgAECn8dAAMXAAgJCBn4HQA3AgAXAAgJEhb4HQA3AgAdAAcJghRGEACmAQAAAA==.',
Ro='Rokkitok:BAAALgAECgYJDAAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8aAAIQAAcJvh5BIADbAQAQAAcJvh5BIADbAQAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgAAAA==.',
Se='Sea:BAACLgAFFH8PAAIKAAUJ/BJ4CACSAQAKAAUJ/BJ4CACSAQAuAAQKfyAAAgoACQmSIOYBAG4DAAoACQmSIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgYJBgAAAA==.Shadowrose:BAABLgAECn8fAAIgAAgJ0RTZBgDQAQAgAAgJ0RTZBgDQAQAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAAALgAECggJDwAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAgAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAANAAAAAA==.Shiemi:BAAALgAECgIJAgAAAA==.Shunsui:BAABLgAECn8eAAMGAAgJlxUsNwCIAQAGAAgJlxUsNwCIAQAHAAEJAAAabwA3AAAAAA==.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Siley:BAABLgAECn8YAAIcAAkJ2xzCFABrAgAcAAkJ2xzCFABrAgAAAA==.Sinnister:BAAALgAECgYJBgAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgUJBQAAAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAAALgAECgEJBAAAAA==.',
So='Sooner:BAACLgAFFH8IAAIWAAMJGh9QQwAIAQAWAAMJGh9QQwAIAQAuAAQKfxkAAyEABwl1HfAEAPwBACEABgl0IPAEAPwBABYABQkGHJRkABoBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgEJAQAAAA==.',
Sq='Squeaky:BAAALgAECgQJAQAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECggJCQAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.',
Te='Temporary:BAAALgADCgcJFgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAcJFQABAOMbAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgIJAwAAAA==.',
Tu='Tucktoo:BAAALgAECgIJAwAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAABLgAECn8oAAIYAAkJmRTWCAA6AgAYAAkJmRTWCAA6AgAAAA==.',
Uw='Uwurailme:BAABLgAECn8VAAQHAAcJNg8JMgDwAAAGAAYJcQxiiwBCAQAHAAUJHAoJMgDwAAAiAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAABLgAECn8dAAMaAAgJEBHPJAAEAQAaAAcJQBDPJAAEAQAZAAcJ0BLsPwDiAAAAAA==.Valkryi:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgIJAgAAAA==.',
Vo='Vo:BAAALgAECgYJDwAAAA==.',
Wa='Warder:BAAALgAECgYJEgAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wincks:BAAALgAECgYJEwAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAAALgAECgcJEgAAAA==.Zackman:BAABLgAECn8qAAIcAAgJTAs8HQCdAQAcAAgJTAs8HQCdAQAAAA==.',
Zi='Zinagos:BAAALgAECggJDQABLgAECggJHQAaABARAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAECgQJBQAAAA==.',
Zu='Zulrea:BAAALgAECgIJAgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJBgAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAECgUJCgANAAAAAA==.',
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

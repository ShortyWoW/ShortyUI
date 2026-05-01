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

local lookup = {'Hunter-Survival','Warlock-Affliction','Unknown-Unknown','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Priest-Holy','Warlock-Destruction','Rogue-Subtlety','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','DemonHunter-Havoc','Shaman-Restoration','DeathKnight-Unholy','Evoker-Devastation','Mage-Frost','DemonHunter-Vengeance','Evoker-Augmentation','DeathKnight-Blood','Shaman-Elemental',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Ademar:BAABLgAECn8eAAIBAAYJwRbPEwAvAQABAAYJwRbPEwAvAQAAAA==.',
Ag='Agrius:BAAALgAECgYJCQAAAA==.',
Ak='Akurumira:BAAALgADCgIJAgAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgAECgEJAQAAAA==.Allectra:BAAALgAECgMJBAAAAA==.Allupinya:BAAALgADCgEJAQAAAA==.',
Am='Amnon:BAABLgAECn8bAAICAAcJMhp4AgC0AQACAAcJMhp4AgC0AQAAAA==.',
As='Asaelis:BAAALgAECgUJCgAAAA==.Astauren:BAAALgADCgMJBAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECgcJEgADAAAAAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJDAAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAABLgAECn8eAAMEAAgJiQj1FABcAQAEAAgJiQj1FABcAQAFAAEJ7QD5dwAPAAAAAA==.Azulå:BAAALgADCgEJAQAAAA==.',
Ba='Bach:BAABLgAFFH8HAAIGAAMJvBwoDgAXAQAGAAMJvBwoDgAXAQAAAA==.Balloffur:BAAALgAECgYJCgAAAA==.Bamboostixx:BAAALgAECgYJEwAAAA==.',
Be='Bellgirls:BAAALgAECgMJAwAAAA==.Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAABLgAECn8eAAIHAAgJ7hQVDQDfAQAHAAgJ7hQVDQDfAQAAAA==.Berastú:BAAALgAECgYJCwAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQADAAAAAA==.Bloodlusst:BAAALgADCgQJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAABLgAECn8TAAIIAAYJHxg6MAAiAQAIAAYJHxg6MAAiAQAAAA==.Bors:BAABLgAECn8fAAMJAAkJQhmlCQD8AgAJAAkJQhmlCQD8AgAKAAUJARG1UgABAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJCQAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAABLgAECn8UAAIJAAYJvAnxYwA7AQAJAAYJvAnxYwA7AQAAAA==.Calyse:BAABLgAECn8WAAILAAcJRx1PBAAIAgALAAcJRx1PBAAIAgAAAA==.Casblind:BAACLgAFFH8QAAIIAAUJ/BrzCACZAQAIAAUJ/BrzCACZAQAuAAQKfx8AAggACQniH38QAPoCAAgACQniH38QAPoCAAAA.Casima:BAAALgAECgYJCwAAAA==.',
Ch='Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn8eAAIMAAgJjwxTFQBlAQAMAAgJjwxTFQBlAQAAAA==.Chicknwaffle:BAAALgAECgMJAwAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAABLgAECn8ZAAIEAAYJiRSsFwBCAQAEAAYJiRSsFwBCAQAAAA==.',
Ci='Ciri:BAAALgADCgYJCgAAAA==.',
Co='Cornmoon:BAAALgADCgQJAgAAAA==.',
Cr='Crank:BAAALgAFFAMJAwABLgAFFAcJGAANAN0iAA==.',
Da='Dalanorea:BAAALgAECgQJBAAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgAECgEJAQAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECggJGwAOADAhAA==.',
Di='Diménsional:BAAALgAECgYJEwAAAA==.Dinbek:BAAALgADCgkJGQAAAA==.Dindroc:BAAALgADCgcJCAAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAAALgAECgYJEwAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.',
Du='Duronimo:BAAALgADCgcJCgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
Ec='Eclipze:BAACLgAFFH8HAAMPAAMJ9gV/DgDdAAAPAAMJ9gV/DgDdAAAQAAEJhAFQHAA5AAAuAAQKfxsABA8ACAlcFkAWADYCAA8ACAlcFkAWADYCABAAAQkoB9NbACsAAAwAAQnmARWKACIAAAAA.Eclipzee:BAAALgADCgMJAwABLgAFFAMJBwAPAPYFAA==.Eclipzé:BAABLgAECn8WAAMRAAYJMRG0PAA8AQARAAYJMRG0PAA8AQACAAIJzwvyHwByAAABLgAFFAMJBwAPAPYFAA==.',
Ei='Eifel:BAAALgAECgYJDQABLgAECgkJGwASABYeAA==.',
El='Elessardan:BAABLgAECn8YAAMTAAgJPBh8LwDuAQATAAgJPBh8LwDuAQAGAAIJXhGhawBxAAAAAA==.',
En='Endilli:BAAALgAECgIJAgAAAA==.',
Eq='Equinoxis:BAEALgAECgYJBgABLgAFFAYJEwAPAAAQAA==.',
Et='Eternal:BAAALgAFFAEJAQAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn8gAAIOAAYJLheSDwB1AQAOAAYJLheSDwB1AQAAAA==.',
Fe='Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn8cAAIEAAcJpg5qFgBNAQAEAAcJpg5qFgBNAQAAAA==.',
Fi='Filho:BAABLgAECn8XAAMJAAYJ8BMmNQA9AQAJAAYJ8BMmNQA9AQAKAAIJqAKlgABEAAAAAA==.',
Fr='Friedtips:BAAALgADCgIJAgABLgAECggJIAAUADEfAA==.',
Ga='Gabe:BAAALgAECgEJAgAAAA==.Galvek:BAACLgAFFH8GAAQJAAMJ4QxzKwCjAAAJAAIJZgtzKwCjAAABAAEJ1w+mEwBVAAAKAAEJnwNVLABBAAAuAAQKfyEABAEACQlnHEYPAGoBAAkABgkDHa1BAKkBAAEACAl7EkYPAGoBAAoABgmhEEo+AGIBAAAA.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJCQAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Go='Gojira:BAAALgADCgIJAgAAAA==.',
Gr='Greyswandir:BAAALgAECgQJCAAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gw='Gwarr:BAAALgADCgUJCQAAAA==.',
Ha='Hatani:BAAALgADCggJCAABLgAECgYJCwADAAAAAA==.Haylee:BAAALgADCgkJEwAAAA==.',
Hu='Husky:BAAALgAECgUJDAAAAA==.',
Ic='Icyfurball:BAAALgADCgkJIwABLgAECgYJCwADAAAAAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgAECgEJAQAAAA==.',
In='Indigobleue:BAABLgAECn8cAAMMAAcJUxvZCwDnAQAMAAcJUxvZCwDnAQAQAAUJoxf+EwBZAQAAAA==.',
Ja='Japplen:BAAALgAECgQJBAAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJGgAVAEMWAA==.Jinn:BAAALgADCgUJBQAAAA==.Jiñ:BAAALgAECgQJBAAAAA==.',
Jo='Jorenson:BAABLgAECn8dAAIWAAcJSBT2MwBpAQAWAAcJSBT2MwBpAQAAAA==.',
Ka='Kaether:BAAALgAECgYJDwAAAA==.Kalzdemar:BAAALgAECgUJDAABLgAECgYJHgABAMEWAA==.Kasitus:BAABLgAECn8XAAIWAAcJ+iIzFwABAgAWAAcJ+iIzFwABAgAAAA==.',
Ke='Keldanor:BAAALgADCgIJAgAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kilometraje:BAAALgAECgQJCgAAAA==.Kissey:BAAALgAECgEJAQAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAAALgAFFAIJAgAAAA==.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgYJCAADAAAAAA==.',
Ky='Kyrak:BAAALgAECgEJAQAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Lainey:BAABLgAECn8jAAIJAAgJ9xkIEwD6AQAJAAgJ9xkIEwD6AQAAAA==.Landocamando:BAAALgAECgYJDwAAAA==.Larrusbain:BAAALgAECgUJDAAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECgYJIAAOAC4XAA==.Lerya:BAABLgAECn8bAAIXAAgJ+BFNEQDKAQAXAAgJ+BFNEQDKAQAAAA==.Lexnn:BAABLgAECn8dAAIIAAcJfAtsNgAJAQAIAAcJfAtsNgAJAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgADCgEJAQAAAA==.Ligetnoone:BAAALgAECgYJCwAAAA==.Lighte:BAABLgAECn8gAAIYAAgJLhpaGAAbAgAYAAgJLhpaGAAbAgAAAA==.Lilyith:BAAALgAECgIJAgAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAABLgAECn8YAAIGAAYJQBWnFwBCAQAGAAYJQBWnFwBCAQAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAABLgAECn8XAAIYAAYJhxB+WwAmAQAYAAYJhxB+WwAmAQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgAECgUJBQAAAA==.',
Me='Mefisto:BAAALgADCgUJDQABLgAECgMJBAADAAAAAA==.Mellesaun:BAAALgAECgUJCwAAAA==.Merie:BAAALgADCgEJAQAAAA==.Mewtwo:BAAALgAECgEJAQAAAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgADCgcJDAAAAA==.',
Mo='Moonsaw:BAAALgAECgYJEQAAAA==.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.',
My='Myrling:BAAALgAECgYJDwAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAABLgAECn8eAAQIAAgJtRnSHQCAAQAUAAcJkxadIAC4AQAIAAcJ1w/SHQCAAQAZAAEJnQIjGgAoAAAAAA==.',
Ni='Nimbus:BAABLgAFFH8GAAIYAAMJoQnzOgDnAAAYAAMJoQnzOgDnAAABLgAFFAYJEQAaAKEXAA==.Nishikki:BAECLgAFFH8TAAIPAAYJABAaAwCFAQAPAAYJABAaAwCFAQAuAAQKfzMAAg8ACQmSIA0BAAcDAA8ACQmSIA0BAAcDAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.',
Ny='Nydie:BAABLgAECn8iAAISAAgJGBgnHADhAQASAAgJGBgnHADhAQAAAA==.Nymuellyn:BAABLgAECn8bAAIOAAcJMCGrDwCqAgAOAAcJMCGrDwCqAgAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Pa='Palmanance:BAAALgAECggJCgAAAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAQAAAA==.Phibalan:BAAALgAECgEJAQAAAA==.',
Pi='Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAAALgAECgYJEgAAAA==.',
Pr='Pradigy:BAAALgAECgYJDgAAAA==.',
Pu='Pubba:BAAALgAECgYJCAAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgYJCAADAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Ra='Raelyndria:BAAALgAECgYJEQAAAA==.Raengurth:BAAALgAECgEJAQAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Rakkali:BAAALgAECgQJBwABLgAECgUJDAADAAAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJGgAVAEMWAA==.Razaller:BAABLgAECn8UAAMaAAkJhg5VHAAcAQAaAAkJhg5VHAAcAQAXAAEJFgE5RgAbAAAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJGgAVAEMWAA==.',
Re='Redrogue:BAABLgAECn8ZAAINAAYJJQmZCwDnAAANAAYJJQmZCwDnAAAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8HAAIWAAMJKRFmOgDmAAAWAAMJKRFmOgDmAAAuAAQKfy0AAhYACAnRIewaANwCABYACAnRIewaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAAALgAECgMJBQAAAA==.',
Ro='Rogun:BAAALgAECgUJBwAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJGgAVAEMWAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Satele:BAAALgAECgEJAgAAAA==.',
Sc='Scarypoppins:BAABLgAECn8XAAIbAAYJsCL4BADrAQAbAAYJsCL4BADrAQAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECgYJBgAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Serracha:BAAALgAECgYJDAABLgAECggJHgAEAIkIAA==.Seònaid:BAAALgAECgQJBwABLgAFFAIJAgADAAAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgADCgUJBQABLgAECgYJDQADAAAAAA==.Shammywaddle:BAAALgAECgcJEgAAAA==.Shamtraxx:BAABLgAECn8aAAMVAAgJQxb1LwDIAQAVAAcJPBb1LwDIAQAcAAcJTw1qRgAvAQAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgYJBwAAAA==.',
Sk='Skorpius:BAAALgAECgQJCAAAAA==.Skumi:BAAALgAECgUJCQAAAA==.',
Sl='Slaytanic:BAABLgAECn8aAAISAAcJKBsRHQDbAQASAAcJKBsRHQDbAQAAAA==.Slymick:BAAALgAECgYJCgAAAA==.',
So='Solora:BAABLgAECn8ZAAIcAAYJ9Qb/KQDcAAAcAAYJ9Qb/KQDcAAAAAA==.Soluna:BAABLgAECn8ZAAISAAcJLhSALgCIAQASAAcJLhSALgCIAQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgEJAQAAAA==.Stuffedbear:BAAALgAECgYJDgAAAA==.',
Su='Subiegrl:BAAALgADCggJCAAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAABLgAECn8gAAIUAAgJMR+kCADAAQAUAAgJMR+kCADAAQAAAA==.',
['Sã']='Sãrik:BAAALgAECgQJBAAAAA==.',
['Sí']='Sílver:BAABLgAECn8kAAIcAAgJoxD9EgCEAQAcAAgJoxD9EgCEAQAAAA==.',
Ta='Taebeck:BAAALgADCgQJBAAAAA==.Tasty:BAAALgADCgYJBgABLgAFFAMJBgAVALccAA==.',
Th='Thirstrap:BAAALgAECggJEAAAAA==.Thorge:BAAALgAECgYJCwAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Tokesmasmoke:BAAALgADCggJCAAAAA==.Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgYJDgAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8aAAIKAAgJJxE9CABXAQAKAAgJJxE9CABXAQAAAA==.Ventt:BAACLgAFFH8QAAIcAAUJfg81BQByAQAcAAUJfg81BQByAQAuAAQKfygAAhwACQmMIpgBAPECABwACQmMIpgBAPECAAAA.',
Vo='Volstaag:BAAALgAECgEJAQAAAA==.Voluus:BAAALgAECgYJCgAAAA==.',
Vr='Vrorag:BAAALgAECgcJEwAAAA==.',
Wa='Walfar:BAAALgAECgMJBAAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgAECgEJAgABLgAECgYJDgADAAAAAA==.Wayme:BAAALgAECgUJCAAAAA==.',
We='Wendorf:BAAALgADCgkJCQAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgAECgMJAwAAAA==.',
Xa='Xahle:BAAALgAECgYJEwAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgADCgUJBQAAAA==.',
Za='Zadkiel:BAAALgAECgQJBQAAAA==.',
Ze='Zeparu:BAAALgAECgcJBwAAAA==.Zero:BAAALgAECgUJBwABLgAECggJGgAFADYWAA==.',
Zi='Zitillidan:BAAALgADCgUJBgABLgAECgYJHgABAMEWAA==.',
Zo='Zogz:BAAALgAECgYJDgAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8bAAISAAkJFh4bIQCmAgASAAkJFh4bIQCmAgAAAA==.',
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

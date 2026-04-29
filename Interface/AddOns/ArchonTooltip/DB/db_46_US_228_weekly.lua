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

local lookup = {'Hunter-Survival','Warlock-Affliction','Unknown-Unknown','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Devourer','Priest-Holy','Warlock-Destruction','Rogue-Subtlety','Priest-Shadow','Priest-Discipline','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Unholy','Evoker-Devastation','Mage-Frost','DemonHunter-Vengeance','Evoker-Augmentation','Shaman-Elemental','Shaman-Restoration',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Ademar:BAABLgAECn8XAAIBAAYJoRReFQBxAQABAAYJoRReFQBxAQAAAA==.',
Ag='Agrius:BAAALgAECgUJBgAAAA==.',
Ak='Akurumira:BAAALgADCgIJAgAAAA==.',
Al='Alexändros:BAAALgADCgUJCAAAAA==.Alkie:BAAALgADCgcJCgAAAA==.Allectra:BAAALgAECgMJAwAAAA==.',
Am='Amnon:BAABLgAECn8UAAICAAYJbBtDBwDgAQACAAYJbBtDBwDgAQAAAA==.',
As='Asaelis:BAAALgAECgUJBQAAAA==.Astauren:BAAALgADCgMJBAAAAA==.',
Au='Augwaddles:BAAALgAECgUJBwABLgAECgYJEQADAAAAAA==.',
Av='Avataraang:BAAALgADCgEJAQAAAA==.Avramora:BAAALgAECgUJBwAAAA==.',
Ax='Axila:BAAALgAECgIJAwAAAA==.',
Az='Azdaja:BAABLgAECn8cAAMEAAgJwAcSCQBiAQAEAAgJwAcSCQBiAQAFAAEJ7QDydwAPAAAAAA==.',
Ba='Bach:BAAALgAFFAIJAwAAAA==.Balloffur:BAAALgAECgYJCgAAAA==.Bamboostixx:BAAALgAECgYJDQAAAA==.',
Be='Belnetukent:BAAALgADCgEJAQAAAA==.Berastu:BAABLgAECn8YAAIGAAgJLBP0BQDHAQAGAAgJLBP0BQDHAQAAAA==.Berastú:BAAALgAECgYJCwAAAA==.',
Bl='Blackbear:BAAALgAECgMJAwABLgADCgEJAQADAAAAAA==.Bloodlusst:BAAALgADCgQJBAAAAA==.Bloodraina:BAAALgADCgYJBgAAAA==.',
Bo='Bonechill:BAAALgADCgYJDAAAAA==.Boogyboo:BAAALgADCgEJAQAAAA==.Booz:BAAALgAECgYJEwAAAA==.Bors:BAABLgAECn8bAAMHAAkJvxilCQD8AgAHAAkJvxilCQD8AgAIAAUJARG9UgABAQAAAA==.',
Bu='Bubbleõseven:BAAALgADCggJCAAAAA==.Bunnystalker:BAAALgADCgYJBwAAAA==.',
Ca='Callee:BAAALgAECgYJEAAAAA==.Calyse:BAAALgAECgYJDwAAAA==.Casblind:BAACLgAFFH8NAAIJAAUJrxf0CACZAQAJAAUJrxf0CACZAQAuAAQKfx8AAgkACQniH3MQAPoCAAkACQniH3MQAPoCAAAA.Casima:BAAALgAECgUJBQAAAA==.',
Ch='Chesterblat:BAAALgADCgIJAgAAAA==.Cheydinhal:BAABLgAECn8XAAIKAAcJNw2TDgAGAQAKAAcJNw2TDgAGAQAAAA==.Chicknwaffle:BAAALgADCggJEQAAAA==.Chocó:BAAALgADCgEJAQAAAA==.Chumlee:BAAALgAECgYJEwAAAA==.',
Ci='Ciri:BAAALgADCgYJCgAAAA==.',
Co='Cornmoon:BAAALgADCgQJAgAAAA==.',
Cr='Crank:BAAALgAECgQJBAABLgAFFAYJFgALAE8iAA==.',
Da='Dalanorea:BAAALgADCgQJBAAAAA==.Dandorn:BAAALgADCgIJAgAAAA==.Darksushi:BAAALgADCgcJDwAAAA==.Daylate:BAAALgADCgUJBQAAAA==.',
Dh='Dhabyss:BAAALgADCggJCAABLgAECggJGAAMAA8hAA==.',
Di='Diménsional:BAAALgAECgYJDQAAAA==.Dinbek:BAAALgADCgkJGQAAAA==.Dindroc:BAAALgADCgEJAQAAAA==.Dingread:BAAALgAECgYJBgAAAA==.',
Dr='Dragin:BAAALgAECgYJDwAAAA==.Dreyla:BAAALgADCgQJCAAAAA==.',
Du='Duronimo:BAAALgADCgcJCgAAAA==.Dusksurge:BAAALgADCgIJAgAAAA==.',
Ec='Eclipze:BAABLgAECn8fAAQNAAgJsBk8FgA2AgANAAgJsBk8FgA2AgAOAAEJKAfQWwArAAAKAAEJ5gEKigAiAAAAAA==.Eclipzee:BAAALgADCgMJAwABLgAECggJHwANALAZAA==.Eclipzé:BAAALgAECgYJEAABLgAECggJHwANALAZAA==.',
Ei='Eifel:BAAALgAECgUJCQABLgAECggJFAAPAEsgAA==.',
El='Elessardan:BAAALgAECgcJEgAAAA==.',
En='Endilli:BAAALgADCgkJHwAAAA==.',
Eq='Equinoxis:BAEALgADCgEJAQABLgAFFAUJEgANAJMVAA==.',
Et='Eternal:BAAALgAECgYJDAAAAA==.',
Ev='Evaki:BAAALgADCgEJAgAAAA==.',
Ez='Ezekiel:BAAALgAECgEJAQAAAA==.',
Fa='Faein:BAAALgADCgIJAgAAAA==.Fallynangel:BAABLgAECn8aAAIMAAYJEBboBgB3AQAMAAYJEBboBgB3AQAAAA==.',
Fe='Fearlock:BAAALgADCgUJCAAAAA==.Felrafram:BAAALgADCgQJAwAAAA==.Fenyx:BAABLgAECn8VAAIEAAcJfQyFPABVAQAEAAcJfQyFPABVAQAAAA==.',
Fi='Filho:BAAALgAECgYJEQAAAA==.',
Fr='Friedtips:BAAALgADCgIJAgABLgAECggJGwAQALAZAA==.',
Ga='Gabe:BAAALgAECgEJAQAAAA==.Galvek:BAABLgAECn8fAAQHAAgJsBm4QQCpAQAHAAYJAx24QQCpAQAIAAYJoRBKPgBiAQABAAYJ0w4XDADGAAAAAA==.Garjzlaa:BAAALgAECgYJBwAAAA==.Garugamesh:BAAALgADCgcJCQAAAA==.',
Gi='Gigglebytes:BAAALgAECgIJAQAAAA==.',
Gr='Greyswandir:BAAALgAECgQJBAAAAA==.Gryssli:BAAALgADCgIJAgAAAA==.',
Gw='Gwarr:BAAALgADCgUJCQAAAA==.',
Ha='Haylee:BAAALgADCgkJEwAAAA==.',
Hu='Husky:BAAALgAECgQJBwAAAA==.',
Ic='Icyfurball:BAAALgADCgkJGgABLgAECgQJBQADAAAAAA==.',
Ik='Ikillyounows:BAAALgAECgQJBAAAAA==.',
Il='Ilovesanta:BAAALgADCgcJDwAAAA==.',
In='Indigobleue:BAABLgAECn8VAAMKAAYJAR6FBQDKAQAKAAYJAR6FBQDKAQAOAAMJ0BCVPwCyAAAAAA==.',
Ja='Japplen:BAAALgAECgQJBAAAAA==.',
Ji='Jinkalou:BAAALgAECgQJBAABLgAECggJEgADAAAAAA==.Jinn:BAAALgADCgUJBQAAAA==.Jiñ:BAAALgAECgQJBAAAAA==.',
Jo='Jorenson:BAABLgAECn8WAAIRAAcJEhPuGABMAQARAAcJEhPuGABMAQAAAA==.',
Ka='Kaether:BAAALgAECgYJCQAAAA==.Kalzdemar:BAAALgAECgQJBgABLgAECgYJFwABAKEUAA==.Kasitus:BAAALgAECgYJEQAAAA==.',
Ke='Keldanor:BAAALgADCgIJAgAAAA==.',
Kh='Khei:BAAALgADCgIJAgAAAA==.',
Ki='Kilometraje:BAAALgAECgQJBQAAAA==.Kissey:BAAALgAECgEJAQAAAA==.Kivi:BAAALgADCgEJAQAAAA==.',
Ko='Korneliuz:BAAALgAECgQJDQAAAA==.',
Kr='Kraink:BAAALgADCgEJAQAAAA==.Krayvin:BAAALgADCgIJAgAAAA==.',
Ku='Kungmoofu:BAAALgADCgIJAgABLgAECgIJAgADAAAAAA==.',
Ky='Kyrak:BAAALgADCgcJEgAAAA==.',
La='Labiamajorah:BAAALgADCgIJAgAAAA==.Lainey:BAABLgAECn8bAAIHAAgJkhaXKwAGAgAHAAgJkhaXKwAGAgAAAA==.Landocamando:BAAALgAECgYJCgAAAA==.Larrusbain:BAAALgAECgUJBwAAAA==.',
Le='Leafin:BAAALgADCgUJCQABLgAECgYJGgAMABAWAA==.Lerya:BAABLgAECn8bAAISAAgJ+BFMEQDKAQASAAgJ+BFMEQDKAQAAAA==.Lexnn:BAABLgAECn8WAAIJAAcJPAt3cwBLAQAJAAcJPAt3cwBLAQAAAA==.Lexonidas:BAAALgADCgEJAgAAAA==.',
Li='Liantelva:BAAALgAECgcJEQAAAA==.Lifepriest:BAAALgADCgEJAQAAAA==.Ligetnoone:BAAALgAECgQJBQAAAA==.Lighte:BAABLgAECn8YAAITAAgJFBcqDgDXAQATAAgJFBcqDgDXAQAAAA==.Lilyith:BAAALgADCgcJBwAAAA==.Lips:BAAALgAECgMJAwAAAA==.',
Lo='Logicx:BAAALgAECgYJEgAAAA==.Lorvoldenord:BAAALgADCgIJAgAAAA==.',
Lu='Lunarìa:BAAALgADCggJCwAAAA==.',
['Lê']='Lêssa:BAAALgAECgQJBQAAAA==.',
Ma='Magici:BAAALgAECgYJEQAAAA==.Magnyesis:BAAALgADCgEJAQAAAA==.Mahavailo:BAAALgADCgcJCgAAAA==.',
Me='Mefisto:BAAALgADCgQJCAABLgAECgEJAQADAAAAAA==.Mellesaun:BAAALgAECgUJBgAAAA==.Merie:BAAALgADCgEJAQAAAA==.',
Mi='Miikeey:BAAALgADCgIJAgAAAA==.Mirei:BAAALgADCggJCQAAAA==.Mithrios:BAAALgADCgUJBQAAAA==.',
Mo='Moonsaw:BAAALgAECgYJCwAAAA==.Mordella:BAAALgADCgIJAwAAAA==.Moriartus:BAAALgADCgEJAQAAAA==.',
My='Myrling:BAAALgAECgUJCQAAAA==.Mythrial:BAAALgAECgYJCgAAAA==.',
Ne='Nenni:BAAALgADCgYJBgAAAA==.Neph:BAAALgADCgkJCQAAAA==.Newt:BAABLgAECn8bAAQQAAcJkxafIAC4AQAQAAcJkxafIAC4AQAJAAQJRwpSOACAAAAUAAEJnQIZDAApAAAAAA==.',
Ni='Nimbus:BAAALgAFFAEJAgABLgAFFAYJEAAVAAwVAA==.Nishikki:BAECLgAFFH8SAAINAAUJkxV3AQBoAQANAAUJkxV3AQBoAQAuAAQKfzAAAg0ACQmSHq0AAMcCAA0ACQmSHq0AAMcCAAAA.',
No='Nocanno:BAAALgADCgYJBgAAAA==.',
Ny='Nydie:BAABLgAECn8ZAAIPAAgJGxcVEgCSAQAPAAgJGxcVEgCSAQAAAA==.Nymuellyn:BAABLgAECn8YAAIMAAcJDyGsDwCqAgAMAAcJDyGsDwCqAgAAAA==.',
Nz='Nzonah:BAAALgADCgEJAQAAAA==.',
Pa='Palmanance:BAAALgAECgUJBwAAAA==.',
Pe='Penumbral:BAAALgAECgYJDwAAAA==.',
Ph='Phalst:BAAALgAECgEJAQAAAA==.',
Pi='Pixil:BAAALgADCgEJAQAAAA==.Pixishot:BAAALgAECgUJDQAAAA==.',
Pr='Pradigy:BAAALgAECgQJBwAAAA==.',
Pu='Pubba:BAAALgAECgIJAgAAAA==.Pubbazug:BAAALgAECgUJCwABLgAECgIJAgADAAAAAA==.Pubismaximus:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
Ra='Raelyndria:BAAALgAECgUJCwAAAA==.Raengurth:BAAALgADCggJEgAAAA==.Raenraug:BAAALgADCgMJAwAAAA==.Rakkali:BAAALgAECgQJBQABLgAECgUJBwADAAAAAA==.Rancavus:BAAALgADCgMJAwAAAA==.Rastakehn:BAAALgADCgYJBgAAAA==.Ratraxx:BAAALgADCgYJBgABLgAECggJEgADAAAAAA==.Razaller:BAAALgAFFAEJAQAAAA==.',
Rc='Rctraxx:BAAALgAECgYJBwABLgAECggJEgADAAAAAA==.',
Re='Redrogue:BAAALgAECgYJEwAAAA==.Revela:BAAALgADCgcJDQAAAA==.',
Ri='Riftan:BAACLgAFFH8FAAIRAAMJKRE0EQDpAAARAAMJKRE0EQDpAAAuAAQKfyUAAhEACAnRIecaANwCABEACAnRIecaANwCAAAA.Rightousnes:BAAALgADCgcJCQAAAA==.Riviee:BAAALgAECgMJAwAAAA==.',
Ro='Rogun:BAAALgAECgQJBgAAAA==.Roredge:BAAALgAECgEJAQABLgAECggJEgADAAAAAA==.Rosealie:BAAALgADCgMJAwAAAA==.',
Ry='Rycbar:BAAALgADCgkJCQAAAA==.Rynthanuu:BAAALgADCgEJAQAAAA==.',
Sa='Satele:BAAALgAECgEJAQAAAA==.',
Sc='Scarypoppins:BAAALgAECgYJEQAAAA==.',
Se='Seloki:BAAALgADCgQJBAAAAA==.Senia:BAAALgAECgYJBgAAAA==.Seniortank:BAAALgADCgEJAQAAAA==.Seònaid:BAAALgAECgQJBwAAAA==.',
Sh='Shadowkaizen:BAAALgADCgEJAQAAAA==.Shambullance:BAAALgADCgUJBQABLgAECgYJDQADAAAAAA==.Shammywaddle:BAAALgAECgYJEQAAAA==.Shamtraxx:BAAALgAECggJEgAAAA==.Sheraania:BAAALgADCgcJCAAAAA==.',
Si='Sinistress:BAAALgADCgYJBgAAAA==.',
Sk='Skorpius:BAAALgAECgQJBAAAAA==.Skumi:BAAALgAECgUJCAAAAA==.',
Sl='Slaytanic:BAAALgAECgYJEwAAAA==.Slymick:BAAALgAECgYJCQAAAA==.',
So='Solora:BAAALgAECgYJEwAAAA==.Soluna:BAABLgAECn8UAAIPAAcJ1xHTFQByAQAPAAcJ1xHTFQByAQAAAA==.',
St='Stiflerd:BAAALgADCgEJAQAAAA==.Strawry:BAAALgAECgEJAQAAAA==.Stuffedbear:BAAALgAECgUJCQAAAA==.',
Sw='Swll:BAAALgAECgYJDQAAAA==.',
Sy='Sylanann:BAAALgADCgMJAwAAAA==.Syrüs:BAABLgAECn8bAAIQAAgJsBkAEwA/AgAQAAgJsBkAEwA/AgAAAA==.',
['Sã']='Sãrik:BAAALgAECgQJBAAAAA==.',
['Sí']='Sílver:BAABLgAECn8cAAIWAAgJew4ACgBbAQAWAAgJew4ACgBbAQAAAA==.',
Ta='Tasty:BAAALgADCgYJBgABLgAECggJJAAXAHoiAA==.',
Th='Thirstrap:BAAALgAECgUJCAAAAA==.Thorge:BAAALgAECgUJBQAAAA==.Thyrus:BAAALgADCgQJBAAAAA==.',
Ti='Tips:BAAALgADCgQJBAAAAA==.',
To='Toragos:BAAALgADCgQJBAAAAA==.',
Tr='Träshley:BAAALgAECgUJCQAAAA==.',
Uk='Uknak:BAAALgAECgQJBwAAAA==.',
Ur='Urma:BAAALgAECgQJBQAAAA==.',
Va='Vaediirn:BAAALgADCgQJBAAAAA==.Vallcore:BAAALgADCgUJBgAAAA==.',
Ve='Vennt:BAABLgAECn8aAAIIAAgJJxH1AwBhAQAIAAgJJxH1AwBhAQAAAA==.Ventt:BAACLgAFFH8MAAIWAAQJHw6WCwAxAQAWAAQJHw6WCwAxAQAuAAQKfx8AAhYACQm+IHsGACsDABYACQm+IHsGACsDAAAA.',
Vo='Volstaag:BAAALgAECgEJAQAAAA==.Voluus:BAAALgAECgYJBgAAAA==.',
Vr='Vrorag:BAAALgAECgYJDAAAAA==.',
Wa='Walfar:BAAALgAECgEJAQAAAA==.Walterlight:BAAALgADCgcJCwAAAA==.Warbuckss:BAAALgADCgUJBQABLgAECgQJBwADAAAAAA==.Wayme:BAAALgAECgMJAwAAAA==.',
We='Wendorf:BAAALgADCgkJCQAAAA==.',
Wh='Whispyr:BAAALgADCgcJCAAAAA==.Whiteclaw:BAAALgADCgkJFQAAAA==.',
Xa='Xahle:BAAALgAECgYJDwAAAA==.Xanado:BAAALgADCgEJAQAAAA==.',
Xs='Xsanguinate:BAAALgADCgQJBAAAAA==.',
Za='Zadkiel:BAAALgAECgEJAQAAAA==.',
Ze='Zero:BAAALgAECgUJBwAAAA==.',
Zo='Zogz:BAAALgAECgYJDAAAAA==.',
['Âi']='Âid:BAAALgADCgkJCQAAAA==.',
['Ëi']='Ëifel:BAABLgAECn8UAAIPAAgJSyAgIQCmAgAPAAgJSyAgIQCmAgAAAA==.',
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

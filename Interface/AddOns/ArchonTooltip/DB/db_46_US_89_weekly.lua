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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Druid-Balance','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Warrior-Fury','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Druid-Guardian','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Arcane','Priest-Holy','Paladin-Holy','Mage-Fire','Druid-Feral','Hunter-Survival','Warlock-Affliction','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgEJAQAAAA==.',
Ac='Acepriest:BAAALgAECgEJAQAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Admired:BAAALgAECgcJEwAAAA==.Adyr:BAABLgAECn8dAAMBAAgJBB9DAwBPAgABAAgJBB9DAwBPAgACAAUJtxc6TQATAQAAAA==.',
Ai='Aidra:BAAALgAECgQJCwAAAA==.',
Al='Alaira:BAAALgAECgMJAwAAAA==.Alamora:BAAALgADCgkJGgAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgUJBQAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgUJCwAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAAALgAFFAEJAQAAAA==.Alicemalkin:BAABLgAECn8WAAIDAAgJKRXxPQD8AQADAAgJKRXxPQD8AQAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJCQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amsip:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Amsroeb:BAAALgAECgYJCwAAAA==.',
An='Anelavenger:BAABLgAECn8qAAMFAAkJKhvIDACpAgAFAAkJKhvIDACpAgAGAAMJWgEuRABNAAAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Ar='Arathor:BAAALgAECgYJDwAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn8aAAIHAAgJsRH3DACEAQAHAAgJsRH3DACEAQAAAA==.Arfy:BAAALgADCgMJAgABLgAECgYJDQAEAAAAAA==.Argøn:BAABLgAECn8VAAMIAAgJfhYqKwAIAgAIAAgJfhYqKwAIAgAJAAEJkAb7kQAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgMJAwAAAA==.Artemislives:BAAALgAECgcJCAAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgYJDAAAAA==.Ashog:BAAALgADCgUJBQAAAA==.Assateague:BAAALgADCgkJGgAAAA==.Astralie:BAAALgADCgYJBgAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Atrosity:BAABLgAECn8aAAIKAAgJPSH7AABtAgAKAAgJPSH7AABtAgAAAA==.',
Au='Aurorabane:BAAALgADCgUJBQAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgADCgcJBwAAAA==.Barrathfrogy:BAAALgADCgUJBwAAAA==.',
Be='Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgEJAQAAAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8eAAILAAgJOQ+kCQBUAQALAAgJOQ+kCQBUAQAAAA==.',
Bl='Blasuoff:BAAALgADCgEJAQAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.',
Bo='Bonës:BAAALgADCgEJAQAAAA==.Borzoi:BAAALgAFFAEJAgAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJEAAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.',
['Bò']='Bò:BAABLgAECn8cAAILAAgJVhA6CABxAQALAAgJVhA6CABxAQAAAA==.',
Ca='Caduceus:BAAALgADCgcJEgAAAA==.Caesus:BAAALgAECgUJBgAAAA==.Cagedancer:BAAALgAECgYJEAAAAA==.Callio:BAABLgAECn8dAAIIAAgJbw/uCwCuAQAIAAgJbw/uCwCuAQAAAA==.Cantor:BAAALgAECgEJAQAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAAALgAECgQJBwAAAA==.Cavagos:BAABLgAECn8nAAIMAAgJIh9lAABkAgAMAAgJIh9lAABkAgAAAA==.Caycay:BAACLgAFFH8GAAINAAQJqheNAgBmAQANAAQJqheNAgBmAQAuAAQKfy0AAg0ACQmKI+8AAL4DAA0ACQmKI+8AAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Cerrulli:BAAALgAECgQJCAAAAA==.',
Ch='Chaosknight:BAAALgAECgUJCQAAAA==.Chaostrip:BAABLgAECn8gAAIDAAgJ0CDqDwD/AgADAAgJ0CDqDwD/AgAAAA==.Chillbros:BAACLgAFFH8KAAIOAAQJGR+CAABoAQAOAAQJGR+CAABoAQAuAAQKfyEAAw4ACAmOJPkBADwDAA4ACAkQJPkBADwDAAIABAmqH+M5AGcBAAAA.Chillmage:BAAALgADCgcJCgABLgAFFAQJCgAOABkfAA==.Chindi:BAABLgAECn8XAAIPAAgJeg+MCACXAQAPAAgJeg+MCACXAQAAAA==.Choiminasue:BAAALgAECgEJAQAAAA==.Chunga:BAABLgAECn8UAAICAAYJoAOjGwCJAAACAAYJoAOjGwCJAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAABLgAECn8eAAIQAAgJcRgLAwAOAgAQAAgJcRgLAwAOAgAAAA==.Churdicus:BAAALgADCgkJEQAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAAALgAECgQJCAAAAA==.',
Ci='Ciceroe:BAAALgAECgIJAgAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAAALgAECgEJAQAAAA==.',
Co='Coalystra:BAABLgAECn8gAAIDAAgJ1RaNCwC8AQADAAgJ1RaNCwC8AQAAAA==.Cocopuffs:BAACLgAFFH8FAAILAAIJGAqkFACfAAALAAIJGAqkFACfAAAuAAQKfyYAAgsACQl8HSIJAAMDAAsACQl8HSIJAAMDAAAA.Colostrom:BAABLgAECn8dAAIRAAgJ+CCgAQAKAgARAAgJ+CCgAQAKAgAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAAALgAECgYJCgAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAAALgAECgYJCAAAAA==.',
Cp='Cplusmc:BAAALgADCgYJBgAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIIAAgJdxS8OQDHAQAIAAgJdxS8OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgEJAQAAAA==.',
Da='Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAAALgADCgcJBwABLgAECgcJGAASAD8TAA==.Darkdeeds:BAAALgADCggJCgAAAA==.Darkpallo:BAABLgAECn8YAAISAAcJPxPYbwCdAQASAAcJPxPYbwCdAQAAAA==.Daten:BAABLgAECn8jAAISAAgJRRB5ZgCzAQASAAgJRRB5ZgCzAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
De='Deathbycow:BAABLgAECn8XAAITAAgJDxmtAQDvAQATAAgJDxmtAQDvAQAAAA==.Decayed:BAAALgAECgYJDwAAAA==.Demonchalk:BAAALgAECgEJAQABLgAFFAMJBwAOAOEbAA==.',
Di='Diagonalli:BAAALgAECgYJCwAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgMJBAAAAA==.',
Dj='Djpriest:BAAALgADCgYJBwAAAA==.Djshadowhunt:BAAALgADCgYJBgAAAA==.Djshadowlock:BAAALgADCgMJAwAAAA==.Djshadowrog:BAAALgADCgUJBQAAAA==.Djshaolin:BAAALgADCgUJBwAAAA==.Djzhadow:BAAALgADCgMJAwAAAA==.',
Dm='Dmitrì:BAAALgADCgEJAQAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakmon:BAAALgADCgUJBQAAAA==.Draktând:BAAALgAECgYJDwAAAA==.Drippysilk:BAAALgAECgQJBwABLgAECgYJGgAMAPwiAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8YAAMUAAcJEBbNJACOAQAUAAcJEBbNJACOAQAVAAYJDgfgRwD1AAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAAALgAECgUJCAAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAABLgAECn8bAAINAAgJIhaLAgDpAQANAAgJIhaLAgDpAQAAAA==.',
El='Elaine:BAAALgAECgYJCgAAAA==.Elberon:BAAALgADCgQJBgAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgADCgYJEwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAISAAYJjRZYfwB7AQASAAYJjRZYfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgEJAQABLgAECgUJCwAEAAAAAA==.Errane:BAACLgAFFH8IAAIHAAMJzSMXBQAwAQAHAAMJzSMXBQAwAQAuAAQKfyYAAwcACAlzI44EAEYDAAcACAlzI44EAEYDAAsAAQnHFTt4AEQAAAAA.Eruiluvatar:BAAALgAECgYJBgAAAA==.',
Et='Etalia:BAAALgADCgUJBQAAAA==.Etcetera:BAAALgADCgYJBAAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAAALgAECgQJCQAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Fistoffury:BAAALgAECgcJEAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAEAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floppydisk:BAAALgAECgMJBwAAAA==.',
Fo='Fortiss:BAAALgAECgcJEAAAAA==.',
Fr='Frost:BAAALgAFFAIJAgABLgAFFAUJDQAIAD4TAA==.Frostmon:BAAALgAECgQJCgAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECggJEgAEAAAAAA==.Furbee:BAAALgAECgcJBwAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAEAAAAAA==.',
Ga='Galeandra:BAAALgADCggJDgAAAA==.Garim:BAAALgADCgEJAQABLgAECgQJCQAEAAAAAA==.',
Ge='Geraltofrvia:BAAALgAECgYJCgAAAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJBwAAAA==.',
Gn='Gnar:BAAALgAECgQJBAAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAABLgAECn8fAAIWAAgJPRGTBgCZAQAWAAgJPRGTBgCZAQAAAA==.',
Gr='Gregzug:BAAALgADCgkJCQAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgEJAQAAAA==.Gruxxiron:BAAALgAECgUJBQABLgAECggJHwAXAN8dAA==.',
Gu='Gulnn:BAABLgAECn8bAAMYAAgJwhgcBwAAAgAYAAgJwhgcBwAAAgAZAAIJVhTvVABvAAAAAA==.',
Ha='Haelena:BAAALgAECgUJCQAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Helfire:BAAALgADCgYJBgABLgAECgMJAwAEAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAAALgAECggJEgAAAA==.',
Ia='Iamfubar:BAAALgADCgMJAwAAAA==.',
Ig='Igris:BAAALgAECgcJCAAAAA==.',
Ii='Iimit:BAAALgAECgQJBQAAAA==.',
Il='Illidead:BAACLgAFFH8JAAIaAAQJsBNdGwBeAQAaAAQJsBNdGwBeAQAuAAQKfxsAAxoACAldISY7AIoCABoACAkcHiY7AIoCABsAAQnXHxYXAGEAAAAA.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAAALgADCgkJGgAAAA==.Insrik:BAAALgAECgEJAgAAAA==.',
Io='Iompróirbáis:BAAALgAECgYJDwAAAA==.',
Ir='Irdeadohnoz:BAAALgAECgQJCAAAAA==.',
It='Itchigo:BAAALgAECgUJBQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAAALgAECgYJDAAAAA==.',
Ja='Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jazilyne:BAAALgADCgYJEwAAAA==.',
Je='Jenka:BAAALgAECgMJBQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJHwAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kambative:BAAALgAECgcJEwABLgAECggJJAAGAF4cAA==.Kammunion:BAAALgADCgMJAwABLgAECggJJAAGAF4cAA==.Kamphiyer:BAABLgAECn8kAAQGAAgJXhxMAgD4AQAGAAcJZhtMAgD4AQAFAAcJeRXNKAB3AQAMAAMJFwu1MQCIAAAAAA==.Kamscendance:BAAALgADCgMJAwABLgAECggJJAAGAF4cAA==.Kamsumerage:BAAALgADCgkJCQABLgAECggJJAAGAF4cAA==.Kantheal:BAAALgAECgYJDAAAAA==.Kaulana:BAAALgADCgYJCgAAAA==.',
Ke='Keirmania:BAAALgADCgMJAwAAAA==.',
Ki='Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAECggJIAAJAJEgAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAAALgAECgUJCwAAAA==.Krixxa:BAABLgAECn8XAAIcAAgJtCAZCwCdAgAcAAgJtCAZCwCdAgAAAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECgcJCAAAAA==.',
La='Larayvia:BAABLgAECn8dAAIIAAgJIw5EOwDBAQAIAAgJIw5EOwDBAQAAAA==.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leesala:BAABLgAECn8eAAMBAAgJkBOEKADuAQABAAgJkBOEKADuAQAOAAEJ0QSWDgAzAAAAAA==.Lerazer:BAAALgAECgMJAwAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECggJHwADAM4dAA==.',
Li='Lic:BAAALgADCgYJDgAAAA==.Liliatrix:BAAALgAECgMJAwAAAA==.Lillabet:BAAALgADCggJEgAAAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgYJGgAMAPwiAA==.Limpylarva:BAAALgADCgMJAwABLgAECgYJGgAMAPwiAA==.Limpypal:BAAALgADCgIJAgABLgAECgYJGgAMAPwiAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECgUJBwAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8kAAIHAAkJHRxlAgCaAgAHAAkJHRxlAgCaAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIMAAYJ/CJ6CgA0AgAMAAYJ/CJ6CgA0AgAAAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgADCgEJAQAAAA==.Maddrox:BAAALgADCgcJDgAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAAALgAECgYJDgAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAEAAAAAA==.Malanath:BAAALgAECggJDwAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgADCgcJCAAAAA==.Mattyfu:BAAALgAECgcJBwAAAA==.Mavíel:BAAALgAECgYJDAAAAA==.Maxrogue:BAAALgAECgEJAQABLgAECgQJCgAEAAAAAA==.Mazikeen:BAAALgAECgEJAQAAAA==.',
Mc='Mcscoots:BAAALgADCgcJCgAAAA==.',
Me='Meatsupreme:BAABLgAECn8eAAISAAgJ6wtKFwBmAQASAAgJ6wtKFwBmAQAAAA==.Meepin:BAACLgAFFH8HAAIdAAMJDRaHCAChAAAdAAMJDRaHCAChAAAuAAQKfyIAAh0ACAkiJQcFABwDAB0ACAkiJQcFABwDAAAA.Meepmorp:BAAALgADCgIJAgAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Mesopyro:BAAALgADCgkJGgAAAA==.',
Mi='Mileenä:BAAALgADCgIJAgAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAAALgAECgYJDAAAAA==.Mograiné:BAAALgADCgQJBAAAAA==.Monkaw:BAAALgADCgUJBQAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAMJBwAOAOEbAA==.Moondevil:BAAALgADCgUJBgAAAA==.Morta:BAEALgAECgUJCwAAAA==.Mortkavaliro:BAAALgAECgQJBAAAAA==.',
Ms='Mslockness:BAAALgADCgUJBQAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAAALgAECgUJCQAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAECggJGwALAKEdAA==.Narrodus:BAAALgAECgYJDAAAAA==.Nasht:BAAALgAECgUJCwAAAA==.Nashxi:BAAALgADCgkJEAABLgAECgUJCwAEAAAAAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.',
Ni='Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAABLgAECn8qAAICAAcJxyEvEQCcAgACAAcJxyEvEQCcAgABLgAFFAYJEAAFAAwVAA==.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAQABLgAECggJHwAXAEkdAA==.Noshoba:BAAALgAECgEJAQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Numbers:BAAALgAECgEJAQAAAA==.',
Ny='Nyterage:BAAALgAECgEJAQAAAA==.Nytesage:BAACLgAFFH8NAAIeAAQJcCQGAACzAQAeAAQJcCQGAACzAQAuAAQKfyMAAh4ACAkMJj8AAH4DAB4ACAkMJj8AAH4DAAAA.',
Oo='Ookle:BAABLgAECn8YAAMfAAgJSgXyBQAdAQAfAAgJSgXyBQAdAQAHAAYJvga7egDoAAAAAA==.',
Or='Oresh:BAAALgAECgYJDAAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAAALgAECgcJAwAAAA==.',
Pa='Painavolian:BAABLgAECn8hAAIaAAgJzByFCgADAgAaAAgJzByFCgADAgAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgYJCQAAAA==.Paopu:BAAALgADCgYJBgABLgAECggJFwAYADIgAA==.',
Pe='Peeches:BAAALgAECgYJCQAAAA==.Pelor:BAAALgAECgMJAwAAAA==.',
Pi='Pisspadpanda:BAABLgAECn8kAAIYAAgJFyHYAgBxAgAYAAgJFyHYAgBxAgAAAA==.',
Po='Poggies:BAACLgAFFH8NAAIeAAUJwyQWAAC/AQAeAAUJwyQWAAC/AQAuAAQKfyEAAx4ACAk0JjkAAIIDAB4ACAk0JjkAAIIDABsAAQkOIPsWAGIAAAAA.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAQALcfAA==.Pontacos:BAABLgAECn8VAAIQAAYJtx+2IADTAQAQAAYJtx+2IADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAECgkJFQAgAI8VAA==.Pozh:BAABLgAECn8UAAIYAAYJlA3wkAA2AQAYAAYJlA3wkAA2AQAAAA==.',
Pr='Praynes:BAABLgAECn8fAAIcAAgJXxrDEgBKAgAcAAgJXxrDEgBKAgAAAA==.Precedence:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pupperputh:BAAALgADCgkJEgABLgAECggJHwADAM4dAA==.Puppet:BAAALgAECgEJAQAAAA==.',
Ra='Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAAALgAECgcJDwAAAA==.Ravyniel:BAAALgADCgEJAQAAAA==.Razji:BAABLgAECn8jAAQgAAgJxCPjAAByAgAgAAgJtRzjAAByAgAJAAcJsSHDFwBsAgAIAAIJiSbOgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgADCgcJBwAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAEAAAAAA==.Reznick:BAAALgAECgYJEAAAAA==.',
Ro='Rokd:BAAALgADCgcJBwAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAAALgADCgkJGQAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAAALgAECggJEwAAAA==.',
Sa='Sadeel:BAABLgAECn8fAAMhAAgJHhZ2AQCGAQAYAAgJKxKnRQD6AQAhAAYJ2hd2AQCGAQAAAA==.Sadewolf:BAABLgAECn8eAAIDAAgJeBuNBQAqAgADAAgJeBuNBQAqAgAAAA==.Sadpanduh:BAAALgADCgkJFQAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAABLgAECn8eAAIdAAgJUxUtBAAwAgAdAAgJUxUtBAAwAgAAAA==.Samgal:BAAALgAECgYJCQAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgYJCgABLgAECggJFwAcALQgAA==.Saurphang:BAACLgAFFH8KAAIXAAQJ9Q8KGABFAQAXAAQJ9Q8KGABFAQAuAAQKfykAAhcACAn/ImYDAG4CABcACAn/ImYDAG4CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECgYJDAAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sh='Shadiepope:BAAALgAECgEJAQAAAA==.Shadora:BAAALgAECggJEgAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAEJAQAEAAAAAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8HAAIOAAMJ4RscAQAnAQAOAAMJ4RscAQAnAQAuAAQKfyQAAw4ACAnvJeYCAA8DAA4ACAnvJeYCAA8DAAIAAglPERocAIIAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAEAAAAAA==.Shrooclaw:BAAALgAFFAEJAQAAAA==.',
Si='Sibbiah:BAAALgAECgMJAgAAAA==.Silanre:BAAALgAECgUJCwAAAA==.',
Sk='Skaðï:BAABLgAECn8gAAQJAAgJkSAlDwDFAgAJAAgJkSAlDwDFAgAIAAMJLxiKLwCRAAAgAAEJPQgFFQA2AAAAAA==.',
Sm='Smolshrapnel:BAAALgAECgUJBQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAMJBwAOAOEbAA==.',
So='Solaraze:BAAALgAECgcJEgAAAA==.Solinarie:BAAALgADCgIJAgAAAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECgYJBgAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8dAAMIAAgJ2R8JBQApAgAIAAgJ2R8JBQApAgAJAAIJJAyxeABeAAABLgAECggJHQAIANkfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgEJAQAAAA==.',
St='Strahm:BAAALgAECgQJCgAAAA==.Strehm:BAAALgADCgEJAQABLgAECgQJCgAEAAAAAA==.Strohmy:BAAALgADCgEJAQABLgAECgQJCgAEAAAAAA==.Stryhm:BAAALgADCgMJBAABLgAECgQJCgAEAAAAAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Syssare:BAAALgAECgYJEAAAAA==.',
Ta='Tabbie:BAAALgADCgYJBgAAAA==.Talasam:BAAALgADCgcJBwAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAABLgAECn8gAAIaAAgJKR1rDQDfAQAaAAgJKR1rDQDfAQAAAA==.Tazdrin:BAABLgAECn8gAAIiAAgJ2hMzAQCXAQAiAAgJ2hMzAQCXAQAAAA==.',
Te='Telidrus:BAACLgAFFH8JAAIaAAQJSxmhBwBjAQAaAAQJSxmhBwBjAQAuAAQKfyYABBoACAkBIGIxAK0CABoABwkmI2IxAK0CABsAAwkUG34CAAsBAB4AAglVE5UDAE8AAAAA.Temok:BAAALgADCgEJAQAAAA==.Teyrlis:BAAALgAECgQJBAAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thias:BAAALgAECgYJCwAAAA==.Thukwarlock:BAABLgAECn8cAAIYAAcJ7xgpSQDuAQAYAAcJ7xgpSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgADCgYJDQAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAAALgAECgYJCQABLgAECggJIAADANAgAA==.Tronko:BAAALgAECgcJEQAAAA==.Trumpinator:BAAALgADCgEJAQAAAA==.',
Ts='Tsireya:BAAALgADCgcJCQABLgAECgQJCwAEAAAAAA==.',
Tu='Turntsnaco:BAABLgAECn8WAAIjAAcJ5xxlEgCKAgAjAAcJ5xxlEgCKAgAAAA==.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgcJBwAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmccpl:BAAALgADCgkJFAAAAA==.Usmcsemperfi:BAAALgADCgYJBgAAAA==.',
Va='Valengarde:BAAALgAECggJEgAAAA==.Vanette:BAAALgAECgEJAQAAAA==.Vannix:BAABLgAECn8fAAIQAAgJxiGwAQBfAgAQAAgJxiGwAQBfAgAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECgcJDAAEAAAAAA==.Velthas:BAAALgADCggJHwAAAA==.',
Vi='Virmethir:BAAALgAECgUJCgAAAA==.Viruz:BAAALgADCgcJCgAAAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAECgMJBAAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgYJDAAEAAAAAA==.Waq:BAAALgAECgYJCAAAAA==.',
Wi='Wiwi:BAABLgAECn8fAAMXAAgJSR16PABFAgAXAAgJ2Rt6PABFAgAkAAIJCRvEBQCiAAAAAA==.',
Xa='Xares:BAABLgAECn8eAAIaAAgJvRh6CwD3AQAaAAgJvRh6CwD3AQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgADCggJDwAAAA==.',
Ya='Yalda:BAAALgAECgUJBgAAAA==.',
Yf='Yfra:BAAALgAECgYJDQAAAA==.',
Yo='Yobama:BAAALgAECgQJCAABLgAECgYJGgAXAJwfAA==.Yochangsvegn:BAAALgAECgcJDwAAAA==.Yoseph:BAAALgAECgYJCQAAAA==.',
Yu='Yurimancer:BAAALgAECgUJEgAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAEAAAAAA==.Zappythile:BAABLgAECn8UAAIBAAcJbhnpLwDIAQABAAcJbhnpLwDIAQAAAA==.Zarkamental:BAAALgADCgYJCwABLgAECgYJFgADAI8QAA==.',
Ze='Zect:BAAALgAECgUJDQAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAAALgADCgkJFwAAAA==.',
Zu='Zulfrik:BAABLgAECn8VAAIaAAgJVBY/EQC4AQAaAAgJVBY/EQC4AQAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
['Zõ']='Zõke:BAAALgADCgEJAQAAAA==.',
['Òd']='Òdb:BAAALgADCgEJAQAAAA==.',
['ße']='ßeef:BAAALgADCgcJBwAAAA==.',
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

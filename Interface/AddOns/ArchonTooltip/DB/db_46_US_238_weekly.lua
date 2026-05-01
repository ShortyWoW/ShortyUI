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

local lookup = {'Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Warrior-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Warlock-Affliction','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Warrior-Arms','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warrior-Fury','Monk-Windwalker','Paladin-Holy','Paladin-Protection','Mage-Arcane','DeathKnight-Blood','Druid-Balance',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Acesmash:BAABLgAECn8eAAIBAAgJ3SFrAwCRAgABAAgJ3SFrAwCRAgAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAECgcJCAABLgAECgcJDwACAAAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.',
Al='Aldannia:BAAALgAECgkJDwAAAA==.Alextros:BAEALgAECgYJEQAAAA==.Alloren:BAAALgAECgEJAQAAAA==.Almond:BAAALgADCgEJAQAAAA==.',
Am='Amrax:BAABLgAECn8cAAIDAAcJKRCVSgAqAQADAAcJKRCVSgAqAQAAAA==.Amynre:BAABLgAECn8aAAMEAAkJJRCfFQD5AQAEAAkJJRCfFQD5AQAFAAMJ6A3xVABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAABLgAECn8dAAQGAAgJ3SB8BAA9AgAHAAcJqx8eGwBNAgAGAAcJOB98BAA9AgAIAAUJcCUYKAAYAgAAAA==.',
Ar='Arvyy:BAABLgAECn8aAAIJAAgJphjGSQBaAgAJAAgJphjGSQBaAgAAAA==.',
As='Ashbringer:BAABLgAECn8aAAIDAAgJSR+kHAC+AgADAAgJSR+kHAC+AgAAAA==.',
At='Atria:BAABLgAECn8WAAIJAAYJBhG4xwBYAQAJAAYJBhG4xwBYAQAAAA==.Attia:BAAALgAECgUJCgAAAA==.',
Av='Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8eAAIKAAgJchiVBgDjAQAKAAgJchiVBgDjAQAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAABLgAECn8lAAILAAgJCB8yAwC3AgALAAgJCB8yAwC3AgAAAA==.Barrels:BAAALgAFFAEJAQAAAA==.Bartab:BAABLgAECn8cAAMMAAgJYBNCEwDTAQAMAAgJYBNCEwDTAQANAAEJDwPoWQAkAAABLgAECggJGgAOAEUNAA==.Baruku:BAAALgAECggJCwAAAA==.Bastadi:BAAALgAECgIJAwABLgAECgYJFAAPAL4gAA==.',
Be='Beau:BAABLgAECn8mAAIQAAkJnSLxAAD5AgAQAAkJnSLxAAD5AgAAAA==.Beauwi:BAAALgAECgIJBAABLgAECgkJJgAQAJ0iAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.',
Bo='Bombur:BAABLgAECn8lAAMRAAcJAxgkJgCXAQARAAcJAxgkJgCXAQASAAEJAAAVZABGAAAAAA==.Boston:BAAALgAECggJEQAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAMJCAATAKMhAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQUAAcJEhnSGgDzAQAUAAcJEhnSGgDzAQAVAAUJJwj9MADpAAAWAAEJAACuPgA1AAABLgAFFAMJCQAEAJcLAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgYJCQABLgAFFAUJEgAVAEYRAA==.Buzzkill:BAAALgADCgMJAwAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8UAAIXAAgJqRzlGwCNAQAXAAgJqRzlGwCNAQAAAA==.Calzraxx:BAAALgAECgUJCgAAAA==.Carstaller:BAAALgAECgMJAwAAAA==.Cartons:BAAALgAECggJDQAAAA==.',
Cc='Ccaan:BAAALgAECgcJBwAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAABLgAECn8gAAILAAgJ7h3BBwAyAgALAAgJ7h3BBwAyAgAAAA==.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Charliek:BAAALgAECgIJAgAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgMJAwAAAA==.Chimalma:BAAALgAECgMJAwABLgAECgkJFAALABYfAA==.',
Cl='Clarabow:BAAALgAECggJDQAAAA==.Closure:BAAALgAECggJEAAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJFh+hEQBVAgALAAgJRSGhEQBVAgAFAAUJXhTBMQBXAQAAAA==.Coby:BAAALgAECgYJEQAAAA==.Coffins:BAAALgAECgYJEQABLgAECggJDQACAAAAAA==.Covell:BAAALgAECgUJBwAAAA==.',
Cr='Crates:BAAALgAECgMJBgABLgAECggJDQACAAAAAA==.Crimsonmagic:BAAALgAECgEJAQAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgMJBAABLgAECgIJBAACAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8UAAMQAAcJmxCcMABMAQAQAAcJmxCcMABMAQAXAAIJHgIK2QA9AAAAAA==.',
Da='Damer:BAAALgADCgkJCgAAAA==.Damues:BAAALgAECggJDQAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAAALgAECgYJDwAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8VAAIQAAcJCBkkCADNAQAQAAcJCBkkCADNAQAAAA==.Darknyss:BAAALgADCgEJAQAAAA==.',
De='Dekumime:BAAALgAECgQJBAAAAA==.Demandred:BAAALgAECgkJCAAAAA==.Demongrass:BAABLgAECn8oAAIXAAgJCB4kDAAdAgAXAAgJCB4kDAAdAgAAAA==.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAECgUJBgAAAA==.',
Di='Diviñehymn:BAAALgAECgYJBwAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJAwABLgAECgIJBAACAAAAAA==.Dragondznuts:BAACLgAFFH8SAAIVAAUJRhEUBgCFAQAVAAUJRhEUBgCFAQAuAAQKfyoABBUACQktG1QLAIACABUACQktG1QLAIACABQAAQlRGGxCAEgAABYAAQlzA3UUAC4AAAAA.Draxtos:BAEALgAECgYJCQABLgAECgYJEQACAAAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAAALgAECgUJDAAAAA==.',
El='Elementony:BAABLgAECn85AAINAAkJoxByIwD1AQANAAkJoxByIwD1AQAAAA==.Elkdruid:BAABLgAECn8dAAMYAAgJsxCWTwBnAQAYAAgJsxCWTwBnAQAZAAEJQAzmNgAbAAAAAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgYJBgAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8VAAMKAAgJbBLPCwBnAQAKAAgJVRDPCwBnAQAaAAQJLA4XJwC2AAAAAA==.Erre:BAABLgAECn8fAAIRAAgJ1R+dCACDAgARAAgJ1R+dCACDAgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgADCgMJAwABLgAECgUJBgACAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgUJBgAAAA==.Failure:BAEBLgAECn8WAAIGAAkJbhQHDQD6AQAGAAkJbhQHDQD6AQAAAA==.Farmtoon:BAAALgAECgYJDQAAAA==.',
Fe='Feardapain:BAACLgAFFH8KAAIRAAQJjA+hGQA6AQARAAQJjA+hGQA6AQAuAAQKfzMABBEACQk5IhgPAAEDABEACAk5IhgPAAEDABIAAQkAACtcAFoAAA8AAQkAAP84AAwAAAAA.Feardatpain:BAAALgAECgQJBAAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAAALgAECgEJAQAAAA==.',
Fl='Flar:BAAALgAECgUJCgAAAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgADCgEJAQAAAA==.Foxymoron:BAAALgAECgUJBQAAAA==.Fozzi:BAABLgAECn8mAAIbAAkJQSEuAQBJAwAbAAkJQSEuAQBJAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8tAAIFAAkJUR2PAwCAAgAFAAkJUR2PAwCAAgAAAA==.Fritzyp:BAAALgAECgcJDQAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJCAAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJAQAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Geörge:BAACLgAFFH8QAAIFAAUJUhivBABqAQAFAAUJUhivBABqAQAuAAQKfyUAAgUACAmGHyMIAAMDAAUACAmGHyMIAAMDAAAA.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgACAAAAAA==.',
Gr='Grimel:BAAALgAECgMJAwAAAA==.Grimghoul:BAAALgAECgEJAQAAAA==.Grimgram:BAAALgAECgYJCgAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8cAAIcAAgJ4g5QBgCmAQAcAAgJ4g5QBgCmAQAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Halconotachi:BAABLgAECn8oAAIGAAgJYhY2CgA2AgAGAAgJYhY2CgA2AgAAAA==.Hammerfoot:BAAALgADCgYJBwAAAA==.Haranir:BAAALgAECgEJAQAAAA==.Harcat:BAAALgAECgYJDAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAAALgAECgYJEwAAAA==.Hawgdream:BAAALgAECgQJBwAAAA==.',
He='Hellequin:BAACLgAFFH8PAAIdAAUJ/x3qAACEAQAdAAUJ/x3qAACEAQAuAAQKfzEAAx0ACQlPITwBACsDAB0ACQlPITwBACsDAB4AAQkpA4YPACoAAAAA.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDAAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hirogon:BAAALgAECgEJAgAAAA==.',
Ho='Hobb:BAABLgAECn8jAAIDAAgJzB0BDABpAgADAAgJzB0BDABpAgAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJwxKLMQCeAQAJAAkJwxKLMQCeAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgADCgUJBwAAAA==.Hondoe:BAAALgAECgQJBwAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgACAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxIpKwAJAQAJAAMJfxIpKwAJAQAuAAQKfx8AAgkABwkGHSlXADMCAAkABwkGHSlXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgEJAQAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdh16KgDJAgAJAAgJdh16KgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAAALgAECgcJDwAAAA==.',
Im='Imagine:BAAALgAECgYJEgAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgEJAQAAAA==.',
Ja='Jasmirangel:BAABLgAECn8vAAIYAAgJhB/sCQBrAgAYAAgJhB/sCQBrAgAAAA==.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Ju='Juka:BAAALgAECgcJCQAAAA==.Jukks:BAAALgAECgcJBwAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8IAAIIAAQJHRoxCwAIAQAIAAQJHRoxCwAIAQAuAAQKfyEAAggACAkhIB8NANYCAAgACAkhIB8NANYCAAAA.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Kh='Khory:BAAALgAECgUJBgAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMIAAgJeRaEJACJAQAIAAcJNBSEJACJAQAGAAYJUhYmFQB1AQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBgAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAACAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuraihikari:BAAALgAECgUJCwAAAA==.Kustaa:BAAALgADCgkJCgABLgAECgYJCgACAAAAAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgIJAgAAAA==.Lapsung:BAAALgAECgEJAQABLgAECgUJCgACAAAAAA==.Lattemocha:BAAALgAECgYJCgAAAA==.',
Le='Lenden:BAAALgADCgcJFwAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAQAAAA==.',
Li='Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJDAAAAA==.',
Lu='Ludlow:BAABLgAECn8VAAIIAAYJtgUcUgDVAAAIAAYJtgUcUgDVAAAAAA==.Lunastra:BAABLgAECn8lAAIJAAgJoxn8HQD4AQAJAAgJoxn8HQD4AQABLgAECgUJBgACAAAAAA==.Luneztoprime:BAAALgAECgEJAQAAAA==.',
Ly='Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAAALgAECgQJDgAAAA==.Maggore:BAAALgAECgIJBAAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgAAAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJCQAIAMAaAA==.Mantonso:BAABLgAECn8qAAIfAAgJ2SGHAwCZAgAfAAgJ2SGHAwCZAgAAAA==.Matt:BAAALgAECggJEwAAAA==.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgEJAQABLgAECgcJHwAIALkhAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgYJCwACAAAAAA==.Megå:BAAALgAECgYJCwAAAA==.Mewtwô:BAAALgAECgUJBQAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJBwAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8JAAIIAAQJwBq6BgBvAQAIAAQJwBq6BgBvAQAuAAQKfxwAAwgABwm9IkoJAGcCAAgABwm9IkoJAGcCAAcABQnAFlNAAFcBAAAA.Monstroqt:BAAALgADCgQJBAAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAAALgAECggJEgAAAA==.',
Mu='Muffers:BAABLgAECn8aAAIgAAYJEBN0FwAtAQAgAAYJEBN0FwAtAQAAAA==.Muffpuff:BAAALgAECgEJAQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
Na='Napkuntt:BAAALgADCgUJBQAAAA==.Napokin:BAAALgADCgEJAQAAAA==.Napshade:BAABLgAECn8bAAMFAAcJLBtoDwCUAQAFAAYJShxoDwCUAQALAAYJExBMXADCAAAAAA==.Nathanael:BAAALgADCgIJAgAAAA==.Natsuu:BAAALgAECgYJCAAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAUJDwAIAGEfAA==.',
Ne='Necroticoath:BAAALgAECgIJBQABLgAECgYJFAAPAL4gAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAUJEAAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8bAAMRAAcJGxSvJQCZAQARAAcJGxSvJQCZAQASAAUJNA+JLQAHAQAAAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Or='Oran:BAAALgAECgYJCgAAAA==.Orctrax:BAABLgAECn8aAAMIAAgJUxFDJACKAQAIAAgJUxFDJACKAQAHAAEJBAJhkgAoAAAAAA==.',
Os='Osheat:BAABLgAECn8cAAITAAgJhR8oDgBRAgATAAgJhR8oDgBRAgAAAA==.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgADCgcJBwAAAA==.Pandaari:BAABLgAECn8UAAIFAAcJOwQ3IgDpAAAFAAcJOwQ3IgDpAAAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAQAAAA==.',
Pe='Persimmon:BAABLgAECn8VAAIhAAcJZxYKEgDMAQAhAAcJZxYKEgDMAQAAAA==.Peyton:BAAALgAECgUJBgAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgQJCAABLgAECgYJEwACAAAAAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Ps='Psythera:BAAALgAECgEJAgABLgAECggJHgAFADkcAA==.Psythern:BAAALgADCgYJCQABLgAECggJHgAFADkcAA==.',
Pu='Punkybrewstr:BAABLgAECn8aAAMgAAgJlAvgGwAGAQAgAAgJZArgGwAGAQABAAQJrgeHNQCHAAAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgADCgcJDQAAAA==.Pyrri:BAABLgAECn8dAAQEAAgJ9B3mCQDxAQAEAAcJxh7mCQDxAQALAAQJ4RXVUQDwAAAFAAIJmxTQLgCLAAAAAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgADCgEJAQAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAAALgAECgEJAQAAAA==.',
Ra='Rabuf:BAAALgAECgYJCgAAAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAECgEJAgAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIgAAYJOQX4RwD1AAAgAAYJOQX4RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIiAAkJDCJUAgATAwAiAAkJDCJUAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8QAAIEAAUJ3RV0BgCrAQAEAAUJ3RV0BgCrAQAuAAQKfyQABAsACAncHBIoAK8BAAQABwkPFuMbALcBAAsABgkyHBIoAK8BAAUABQnSEuU2ADYBAAAA.Reginrune:BAAALgAECgkJCgAAAA==.Resonance:BAAALgAECgcJEwAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ro='Rohdoog:BAABLgAECn8aAAIUAAgJIhUlCwDWAQAUAAgJIhUlCwDWAQAAAA==.Roundabugman:BAABLgAECn8aAAMNAAgJhxrnEACcAQANAAgJhxrnEACcAQAMAAMJpxTidwCyAAAAAA==.',
Ry='Ryanno:BAABLgAECn8gAAIIAAgJsh/UCQBfAgAIAAgJsh/UCQBfAgAAAA==.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sahomi:BAABLgAECn8eAAMEAAkJEgjkGAAiAQAEAAkJEgjkGAAiAQALAAIJTQWHdwBMAAAAAA==.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJBgAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8cAAIiAAcJlBU6CQB4AQAiAAcJlBU6CQB4AQAAAA==.Satrina:BAABLgAECn8hAAITAAgJGSJHCQCLAgATAAgJGSJHCQCLAgAAAA==.Savvy:BAAALgAECgQJBAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCAAFANIPAA==.',
Sh='Shamander:BAAALgAFFAEJAQAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8pAAIXAAgJLhf4GAChAQAXAAgJLhf4GAChAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIcAAMJnBE3AwADAQAcAAMJnBE3AwADAQAuAAQKfxgAAhwACAmEH/AEAMECABwACAmEH/AEAMECAAAA.',
Sl='Slaik:BAAALgAECgIJAgAAAA==.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAABLgAECn8eAAIMAAkJyxVcLgDQAQAMAAkJyxVcLgDQAQAAAA==.Sothren:BAAALgAECgEJAQABLgADCgkJCQACAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.',
Su='Sugar:BAABLgAECn8iAAMMAAgJlRFMIgBUAQAMAAgJlRFMIgBUAQANAAUJtw6aVgDrAAAAAA==.Sugars:BAAALgAECgEJAQAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQAAAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgIJAgAAAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8FAAMXAAQJwgzAIQDfAAAXAAMJhBDAIQDfAAAQAAIJeAS+CgCTAAAuAAQKfzEAAxcACAkxHj0KADcCABAACAm8F0oRAFUCABcACAlwHT0KADcCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAAALgAECgYJCwAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJXBaXHwDvAQAJAAgJXBaXHwDvAQAjAAQJrxREDQD1AAAAAA==.Thedarkkness:BAABLgAECn8dAAIkAAcJ0RQ7HQBgAQAkAAcJ0RQ7HQBgAQAAAA==.',
Ti='Tidalwave:BAABLgAECn8fAAIMAAgJqhQvMQDCAQAMAAgJqhQvMQDCAQAAAA==.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJAwAAAA==.Tissue:BAABLgAECn8VAAIQAAcJbgnOLABjAQAQAAcJbgnOLABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQAAAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8qAAMlAAgJRwR/HQAQAQAlAAgJRwR/HQAQAQAYAAYJgAgrdgD1AAAAAA==.Tolipally:BAAALgAECgQJBwABLgAECggJKgAlAEcEAA==.Tolipicious:BAAALgADCgUJCQABLgAECggJKgAlAEcEAA==.',
Tr='Trauts:BAAALgAECgQJBQAAAA==.Treeadin:BAAALgAECgYJCgAAAA==.Trollcula:BAAALgAECggJDAABLgAECggJHQAYALMQAA==.Truthwithin:BAAALgAECgUJBQAAAA==.',
Ts='Tsarrubus:BAABLgAECn8aAAIQAAgJOgltDgBTAQAQAAgJOgltDgBTAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgADCgkJDQAAAA==.',
Tw='Twingert:BAAALgADCggJDgAAAA==.Twitch:BAAALgAECgYJDAAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8VAAIhAAgJGQyyOgCPAQAhAAgJGQyyOgCPAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8UAAIfAAkJrxq3JAAyAgAfAAkJrxq3JAAyAgAAAA==.',
Ur='Ursock:BAAALgAECgcJCgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8dAAIYAAcJ5yTLCAB/AgAYAAcJ5yTLCAB/AgAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanbrook:BAAALgAECgQJBAAAAA==.Vanden:BAAALgAECgYJBwAAAA==.Vanrion:BAAALgAECggJDAAAAA==.Varrodd:BAAALgADCgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAACAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDAAAAA==.',
Wh='Whohaveaggro:BAAALgADCgEJAgAAAA==.',
Wi='Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAAALgAECgcJCQAAAA==.Wiqui:BAAALgAECgEJAQAAAA==.Witulow:BAABLgAECn8ZAAIbAAcJnw8KGgA0AQAbAAcJnw8KGgA0AQAAAA==.',
Wo='Wolfadin:BAABLgAECn8jAAIDAAgJIxfqPQAtAgADAAgJIxfqPQAtAgAAAA==.Woopac:BAABLgAECn8aAAIfAAgJthq0BgBHAgAfAAgJthq0BgBHAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDgAAAA==.',
Xe='Xenophics:BAACLgAFFH8OAAIDAAQJiw78EQA9AQADAAQJiw78EQA9AQAuAAQKfygAAgMABwnZIBU3AEYCAAMABwnZIBU3AEYCAAEuAAQKBgkaAAkAZxIA.Xenophicstwo:BAABLgAECn8aAAIJAAYJZxLtsQB6AQAJAAYJZxLtsQB6AQAAAA==.',
Xu='Xuen:BAAALgAECgYJBgABLgAECggJGgADAEkfAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAABLgAECn8VAAQDAAcJFRcrlABUAQADAAcJLxYrlABUAQAhAAYJARiWJQAbAQAiAAIJDRViNAB2AAAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8bAAIJAAgJDg6mNACTAQAJAAgJDg6mNACTAQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECgQJBAAAAA==.Zetzu:BAAALgAECgcJBwAAAA==.',
['Ål']='Ålucard:BAAALgAECgYJCgAAAA==.',
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

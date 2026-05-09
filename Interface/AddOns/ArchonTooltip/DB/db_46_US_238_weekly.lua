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

local lookup = {'Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Warlock-Affliction','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Warrior-Arms','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warrior-Fury','Monk-Windwalker','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaddonaxx:BAAALgADCgYJBgAAAA==.',
Ac='Acesmash:BAABLgAECn8lAAIBAAkJGCLJAQAGAwABAAkJGCLJAQAGAwAAAA==.Ackrenezoth:BAAALgAECgQJBwAAAA==.',
Ad='Adymisk:BAAALgADCgEJAQAAAA==.',
Ag='Agorot:BAAALgAECggJDQABLgAFFAEJAQACAAAAAA==.',
Ak='Akadion:BAAALgADCgcJCgAAAA==.Akatali:BAAALgAECgQJBAAAAA==.',
Al='Aldannia:BAAALgAECgkJEAAAAA==.Alextros:BAEALgAECgYJEQABLgAECgcJCgACAAAAAA==.Alloren:BAAALgAECgEJAQAAAA==.Almond:BAAALgAECgEJAgAAAA==.',
Am='Amrax:BAABLgAECn8cAAIDAAcJMBBUWQA+AQADAAcJMBBUWQA+AQAAAA==.Amynre:BAABLgAECn8aAAMEAAkJKRCeFQD5AQAEAAkJKRCeFQD5AQAFAAMJ6w3xVABvAAAAAA==.',
An='Anarsa:BAAALgAECgUJCgAAAA==.Angstyboi:BAAALgAECgQJBAAAAA==.',
Aq='Aquabat:BAACLgAFFH8GAAQGAAMJVRXENwCrAAAGAAMJgBDENwCrAAAHAAEJARmlGQBcAAAIAAEJ8xvlJABVAAAuAAQKfyIABAcACAnfIIUHADMCAAgABwmrH3YbAE0CAAcABwk7H4UHADMCAAYABQlwJRgoABgCAAAA.',
Ar='Arvyy:BAABLgAECn8aAAIJAAgJpxi+SQBaAgAJAAgJpxi+SQBaAgAAAA==.',
As='Ashbringer:BAABLgAECn8gAAIDAAgJuCG9EgBkAgADAAgJuCG9EgBkAgAAAA==.',
At='Atria:BAABLgAECn8YAAIJAAgJTA6+xwBYAQAJAAgJTA6+xwBYAQAAAA==.Attia:BAAALgAECgYJCwAAAA==.',
Av='Avaris:BAAALgADCgIJAgAAAA==.Avatarbambi:BAAALgADCgUJAgAAAA==.',
Ax='Axtar:BAABLgAECn8lAAIKAAkJ5xjzBQA6AgAKAAkJ5xjzBQA6AgAAAA==.',
Ay='Ayyitzrich:BAAALgADCgQJBAAAAA==.',
Ba='Babarazzar:BAAALgADCgYJBgAAAA==.Baladoria:BAABLgAECn8tAAILAAkJESFqAQBSAwALAAkJESFqAQBSAwAAAA==.Bananabowman:BAAALgAECgEJAgAAAA==.Barrels:BAABLgAECn8YAAMHAAkJAhgKBgBSAgAHAAkJmxUKBgBSAgAGAAgJNQ6rLACcAQAAAA==.Bartab:BAABLgAECn8kAAMMAAgJURgcDwBJAgAMAAgJURgcDwBJAgANAAEJEwO8cAAjAAABLgAECggJIgAOAGscAA==.Baruku:BAAALgAECggJCwAAAA==.Bastadi:BAAALgAECgMJBQABLgAECgYJFAAPAL8gAA==.',
Be='Beau:BAABLgAECn8sAAIQAAkJDCMNAQAgAwAQAAkJDCMNAQAgAwAAAA==.Beauwi:BAAALgAECgQJBgABLgAECgkJLAAQAAwjAA==.',
Bi='Bigshekels:BAAALgAECgEJAQAAAA==.Bigulsworth:BAAALgADCgMJAwAAAA==.',
Bl='Blackadder:BAAALgAECgcJEgAAAA==.Blenton:BAAALgAECgEJAQAAAA==.Bloodussy:BAAALgADCgUJBQAAAA==.Bluck:BAAALgADCgcJEQAAAA==.Blueeyesdrag:BAAALgADCgEJAQAAAA==.',
Bo='Bombur:BAABLgAECn8pAAMRAAgJMxmWIQDoAQARAAgJMxmWIQDoAQASAAEJAAAUZABGAAAAAA==.Boston:BAAALgAECggJEwAAAA==.',
Bu='Bubagony:BAAALgADCgQJBAABLgAFFAQJCwATAFwdAA==.Bullmedic:BAAALgADCgYJBgAAAA==.Burakku:BAABLgAECn8VAAQUAAcJEhnJGgDzAQAUAAcJEhnJGgDzAQAVAAUJJwj9MADpAAAWAAEJAACtPgA1AAABLgAFFAMJDAAEAAESAA==.Burguerkiing:BAAALgADCgMJAwAAAA==.Burph:BAAALgADCggJCAAAAA==.Buttonsmash:BAAALgAECgcJEAABLgAFFAUJFgAVAMwTAA==.Buzzkill:BAAALgADCgMJAwAAAA==.',
['Bâ']='Bâbyrage:BAAALgADCgcJDwAAAA==.',
Ca='Cairen:BAABLgAECn8bAAIXAAkJARvTHgDPAQAXAAkJARvTHgDPAQAAAA==.Calzraxx:BAAALgAECgcJEQAAAA==.Carstaller:BAAALgAECgMJAwAAAA==.Cartons:BAAALgAECggJDQAAAA==.',
Cc='Ccaan:BAAALgAECgkJDwAAAA==.Ccian:BAAALgAECgQJBAAAAA==.',
Ce='Celinn:BAABLgAECn8iAAILAAgJ7h19DAAeAgALAAgJ7h19DAAeAgAAAA==.',
Ch='Chadgar:BAAALgADCgUJBwAAAA==.Chalupacabra:BAAALgADCgIJAgAAAA==.Charliek:BAAALgAECgQJBgAAAA==.Cherches:BAAALgADCgEJAQAAAA==.Childish:BAAALgAECgUJCAAAAA==.Chimalma:BAAALgAFFAIJAgAAAA==.',
Cl='Clarabow:BAAALgAFFAIJAgAAAA==.Closure:BAAALgAECggJEgAAAA==.Cloudsx:BAAALgADCgMJAwAAAA==.',
Co='Coatlicue:BAABLgAECn8UAAMLAAkJGB+gEQBVAgALAAgJRSGgEQBVAgAFAAUJZBTBMQBXAQABLgAFFAIJAgACAAAAAA==.Coby:BAAALgAECgYJEQAAAA==.Coffins:BAAALgAECgYJEQABLgAECggJDQACAAAAAA==.Covell:BAAALgAECgUJBwAAAA==.',
Cr='Crates:BAAALgAECgUJCAABLgAECggJDQACAAAAAA==.Crimsonmagic:BAAALgAECgEJAgAAAA==.Crosswalkk:BAAALgADCgMJAwAAAA==.Crygore:BAAALgAECgMJBwABLgAECgIJBgACAAAAAA==.',
Cy='Cypherrellik:BAABLgAECn8VAAMQAAcJnRCeMABMAQAQAAcJnRCeMABMAQAXAAIJHgIW2QA9AAAAAA==.',
Da='Damer:BAAALgADCgkJCgAAAA==.Damues:BAAALgAECggJDwAAAA==.Danaric:BAAALgAECgMJBgAAAA==.Dannyphentom:BAABLgAECn8UAAQYAAYJgxRMCwDZAAATAAUJVw6JgwDZAAAYAAMJxhdMCwDZAAAZAAMJmA7iKwBuAAAAAA==.Dargar:BAAALgAECgEJAQAAAA==.Darkling:BAABLgAECn8XAAIQAAcJDhl9DAC5AQAQAAcJDhl9DAC5AQAAAA==.Darknyss:BAAALgADCgEJAQAAAA==.',
De='Dekumime:BAAALgAECgQJBAAAAA==.Demandred:BAAALgAECgkJEQAAAA==.Demongrass:BAABLgAECn8oAAIXAAgJ/x7kFAAVAgAXAAgJ/x7kFAAVAgAAAA==.Denaric:BAAALgAECgYJEAAAAA==.Derty:BAAALgAECgUJBgAAAA==.',
Di='Diviñehymn:BAAALgAECgYJCAAAAA==.',
Do='Donet:BAAALgADCgEJAQAAAA==.',
Dr='Dragondeezz:BAAALgAECgIJBAABLgAECgIJBgACAAAAAA==.Dragondznuts:BAACLgAFFH8WAAIVAAUJzBPeBwCfAQAVAAUJzBPeBwCfAQAuAAQKfy0ABBUACQkcHFMLAIACABUACQkcHFMLAIACABYAAglHCOcSAF0AABQAAQmIG4NRAFIAAAAA.Draxtos:BAEALgAECgcJCgAAAA==.Dreamevil:BAAALgAECgkJBgAAAA==.Drroxso:BAAALgAECgQJBAAAAA==.',
Ea='Eazybake:BAAALgADCgEJAQAAAA==.',
Ei='Eilerra:BAAALgAECgUJEQAAAA==.',
El='Elementony:BAABLgAECn85AAINAAkJpBBxIwD1AQANAAkJpBBxIwD1AQAAAA==.Elkdruid:BAABLgAECn8dAAMaAAgJshCTTwBnAQAaAAgJshCTTwBnAQAOAAEJQAzqNgAbAAAAAA==.Elladamri:BAAALgAECgEJAQAAAA==.Elodi:BAAALgAECgEJAQAAAA==.',
Em='Emberglow:BAAALgAECgYJDAAAAA==.Empyrean:BAAALgADCgQJBQAAAA==.Emylia:BAAALgAECgcJEAAAAA==.',
Er='Eresdelor:BAABLgAECn8WAAMKAAgJpxO7DgB3AQAKAAgJnxG7DgB3AQAbAAQJLA4WJwC2AAAAAA==.Erre:BAABLgAECn8mAAIRAAkJ3x6SBwDMAgARAAkJ3x6SBwDMAgAAAA==.',
Es='Esdeáth:BAAALgADCgEJAQAAAA==.Estia:BAAALgADCgMJAwABLgAECgUJDgACAAAAAA==.',
Ev='Evoktor:BAAALgAECgEJAQAAAA==.',
Fa='Facasdeath:BAAALgAECgUJCgAAAA==.Failure:BAEBLgAECn8ZAAIHAAkJ+hQHDQD6AQAHAAkJ+hQHDQD6AQAAAA==.Farmtoon:BAAALgAECgYJDQAAAA==.',
Fe='Feardapain:BAACLgAFFH8LAAIRAAQJdRFRKAAgAQARAAQJdRFRKAAgAQAuAAQKfzQABBEACQk5IpULAJUCABEACAk5IpULAJUCABIAAQkAAChcAFoAAA8AAQkAAP44AAwAAAAA.Feardatpain:BAAALgAECgcJDAAAAA==.Fellyn:BAAALgADCggJCwAAAA==.',
Ff='Ff:BAABLgAFFH8FAAIJAAMJsgBZYgCkAAAJAAMJsgBZYgCkAAAAAA==.',
Fl='Flar:BAAALgAECgUJCgAAAA==.Flixie:BAAALgAECgQJCwABLgAFFAUJGAAVAKITAA==.',
Fo='Foenix:BAAALgADCgYJBgAAAA==.Foxoffire:BAAALgAECgEJAQAAAA==.Foxymoron:BAAALgAECgUJBQAAAA==.Fozzi:BAABLgAECn8oAAIcAAkJQSETAgBBAwAcAAkJQSETAgBBAwAAAA==.',
Fr='Freakazoid:BAABLgAECn8uAAIFAAkJgR1cBgByAgAFAAkJgR1cBgByAgAAAA==.Fritark:BAAALgAECgcJBwABLgAECgcJDQACAAAAAA==.Fritzyp:BAAALgAECgcJDQAAAA==.Frogzqc:BAAALgAECgEJAgAAAA==.Frostyburn:BAAALgAECgYJDAAAAA==.Frozenrage:BAAALgADCgcJCwAAAA==.',
['Fë']='Fëanor:BAAALgAECggJBAAAAA==.',
Ga='Gabos:BAAALgADCgEJAQAAAA==.Garayice:BAAALgADCgIJAgAAAA==.Gaxxen:BAAALgAECgUJBQAAAA==.',
Ge='Geörge:BAACLgAFFH8VAAIFAAUJfRwPBwBwAQAFAAUJfRwPBwBwAQAuAAQKfycAAgUACAmHHyIIAAMDAAUACAmHHyIIAAMDAAAA.',
Gl='Glary:BAAALgAECgEJAQAAAA==.Glavendale:BAAALgADCgUJBQAAAA==.',
Go='Goatcheezey:BAAALgADCgYJDAAAAA==.Goblinsox:BAAALgAECgQJBAAAAA==.Goluck:BAAALgAECgEJAQAAAA==.Gordothe:BAAALgADCgUJBQABLgAECgUJBgACAAAAAA==.',
Gr='Grimel:BAAALgAECgQJBwABLgAECgYJCwACAAAAAA==.Grimghoul:BAAALgAECgQJBQABLgAECgYJCwACAAAAAA==.Grimgram:BAAALgAECgYJCwAAAA==.Gripyoulol:BAAALgAECgQJBQAAAA==.Grotelek:BAABLgAECn8hAAIdAAkJTRPrBAAKAgAdAAkJTRPrBAAKAgAAAA==.Grotret:BAAALgAECgIJAgAAAA==.Grouchy:BAAALgADCgMJAwAAAA==.Grumpywaltz:BAAALgAECgQJBAAAAA==.',
Gu='Gulimath:BAAALgAECgUJBgAAAA==.',
Ha='Halconotachi:BAABLgAECn8pAAIHAAgJYhY1CgA2AgAHAAgJYhY1CgA2AgAAAA==.Hammerfoot:BAAALgADCgYJBwAAAA==.Haranir:BAAALgAECgEJAgAAAA==.Harcat:BAAALgAECggJEAAAAA==.Hartracks:BAAALgAECgUJBQAAAA==.Hatijo:BAAALgAECgYJBwAAAA==.Hawgbawl:BAAALgAECgYJEwAAAA==.Hawgdream:BAAALgAECgQJBwAAAA==.',
He='Hellequin:BAACLgAFFH8TAAIeAAUJBh6FAQB/AQAeAAUJBh6FAQB/AQAuAAQKfzEAAx4ACQlQITwBACsDAB4ACQlQITwBACsDAB8AAQkpA4QPACoAAAAA.Heyitzlock:BAAALgAECgYJCQAAAA==.Heyyitzrich:BAAALgAECgQJDQAAAA==.Heyyitzrichh:BAAALgAFFAEJAQAAAA==.Heyytaco:BAAALgAECggJEgAAAA==.',
Hi='Hirogon:BAAALgAECgEJAgAAAA==.',
Ho='Hobb:BAABLgAECn8pAAIDAAkJcB6YBwDXAgADAAkJcB6YBwDXAgAAAA==.Hollinar:BAABLgAECn8YAAIJAAkJxxJORACaAQAJAAkJxxJORACaAQAAAA==.Holyfaux:BAAALgADCgYJBgAAAA==.Holysteel:BAAALgADCgUJBwAAAA==.Hondoe:BAAALgAECgQJBwAAAA==.',
Hu='Huntoor:BAAALgAECgEJAQABLgAECgYJBgACAAAAAA==.',
Ic='Icemark:BAACLgAFFH8FAAIJAAMJfxIsKwAJAQAJAAMJfxIsKwAJAQAuAAQKfx8AAgkABwkGHSJXADMCAAkABwkGHSJXADMCAAAA.',
Ih='Ihavecookies:BAAALgAECgEJAQAAAA==.',
Ij='Ijur:BAAALgAECgQJBwAAAA==.',
Ik='Ikayro:BAABLgAECn8cAAIJAAgJdx17KgDJAgAJAAgJdx17KgDJAgAAAA==.',
Il='Ilostmyphone:BAAALgAECgEJAQAAAA==.Ilovemysword:BAAALgAECgUJCQAAAA==.Iluvatar:BAAALgAFFAEJAQAAAA==.',
Im='Imagine:BAABLgAECn8UAAQVAAcJTg6kDQBqAQAVAAcJTg6kDQBqAQAUAAYJFgagPgDwAAAWAAEJtgKOGgAhAAAAAA==.',
In='Infoxticated:BAAALgAECgEJAQAAAA==.',
Ir='Iratedemon:BAAALgAECgMJBAAAAA==.',
Ja='Jasmirangel:BAACLgAFFH8FAAIaAAMJBh0vLwCKAAAaAAMJBh0vLwCKAAAuAAQKfzMAAhoACAmCIXEHANYCABoACAmCIXEHANYCAAAA.',
Je='Jede:BAAALgADCgMJAwAAAA==.',
Ju='Juka:BAAALgAECggJCgAAAA==.Jukks:BAAALgAECgcJBwAAAA==.Juno:BAAALgADCgkJEwAAAA==.Justsumfoo:BAAALgAECgIJBAAAAA==.',
Ka='Kano:BAACLgAFFH8MAAIGAAQJKxswCwAIAQAGAAQJKxswCwAIAQAuAAQKfyUAAgYACQmpHxwNANYCAAYACQmpHxwNANYCAAAA.Katarm:BAAALgAECgQJBAAAAA==.Katarru:BAAALgAECgYJDQAAAA==.Kataru:BAAALgADCgIJAgAAAA==.',
Ke='Kegpaw:BAAALgAECgMJBAAAAA==.',
Kh='Khory:BAAALgAECgUJDgAAAA==.',
Ki='Kirito:BAAALgADCgYJBgAAAA==.',
Kk='Kkiinnoopp:BAABLgAECn8jAAMGAAgJgRZyNQB3AQAGAAcJRBRyNQB3AQAHAAYJVhYkFQB1AQAAAA==.',
Ko='Korgigor:BAAALgAECgQJBwAAAA==.Kovu:BAAALgAECgcJEgAAAA==.',
Kr='Krisanthemum:BAAALgADCgcJCwAAAA==.Krystrasz:BAAALgAECgQJCwAAAA==.',
Kt='Kt:BAAALgADCgIJAgABLgAECgQJBAACAAAAAA==.Ktrogue:BAAALgAECgQJBAAAAA==.',
Ku='Kuraihikari:BAAALgAFFAEJAQAAAA==.Kustaa:BAAALgADCgkJCgABLgAECggJEgACAAAAAA==.',
La='Ladezar:BAAALgADCgcJDQAAAA==.Laissen:BAAALgAECgIJAgAAAA==.Lapsung:BAAALgAECgEJAQABLgAECgYJCwACAAAAAA==.Lattemocha:BAAALgAECggJEgAAAA==.',
Le='Lenden:BAAALgAECgMJAwAAAA==.Leprechaun:BAAALgADCgcJCQAAAA==.Leví:BAAALgADCgUJBQAAAA==.Leylas:BAAALgAECgEJAgAAAA==.',
Li='Lighthoove:BAAALgAECgcJBwAAAA==.Lilliaz:BAAALgAECgYJBwAAAA==.Linianna:BAAALgAECgYJEgAAAA==.Liriel:BAAALgAECgcJBgAAAA==.',
Lu='Ludlow:BAABLgAECn8WAAIGAAYJ8wUrawDQAAAGAAYJ8wUrawDQAAAAAA==.Lunastra:BAACLgAFFH8GAAIJAAIJNRYCWwCvAAAJAAIJNRYCWwCvAAAuAAQKfyUAAgkACAmiGUctAOwBAAkACAmiGUctAOwBAAEuAAQKBQkOAAIAAAAA.Luneztoprime:BAAALgAECgEJAQAAAA==.',
Ly='Lydarra:BAAALgAECgIJAgABLgAECgYJFAAgAFAZAA==.Lyiann:BAAALgADCggJEgAAAA==.Lyákadion:BAAALgAECgEJAQAAAA==.',
['Lâ']='Lâdypriest:BAAALgADCgUJBQAAAA==.',
Ma='Mafi:BAABLgAECn8UAAIGAAYJGRt9LQCYAQAGAAYJGRt9LQCYAQAAAA==.Maggore:BAAALgAECgIJBgAAAA==.Magikiwiks:BAAALgAECgEJAQAAAA==.Magsdk:BAAALgAFFAIJAgABLgAFFAUJFwAUADcdAA==.Mainlander:BAAALgAECgMJAwAAAA==.Malusmittens:BAAALgAECgQJBQABLgAFFAQJCgAGAMAaAA==.Mantonso:BAABLgAECn8qAAIgAAgJ3CH8BgB/AgAgAAgJ3CH8BgB/AgAAAA==.Matt:BAACLgAFFH8HAAIaAAQJMQsvGwD9AAAaAAQJMQsvGwD9AAAuAAQKfx4AAhoACQkUG3YIAMQCABoACQkUG3YIAMQCAAAA.',
Me='Meddicus:BAAALgAECgUJCAAAAA==.Meechydarko:BAAALgAECgEJAQABLgAECggJIgAGAP0gAA==.Megalomaniä:BAAALgADCgYJBgABLgAECgYJDwACAAAAAA==.Megå:BAAALgAECgYJDwAAAA==.Mewtwô:BAAALgAECgUJBQAAAA==.',
Mi='Microbrew:BAAALgAECgMJBQAAAA==.Miezra:BAAALgAECgYJCAAAAA==.Mikah:BAAALgAECgYJDwAAAA==.',
Mo='Modayus:BAAALgAECgEJAQAAAA==.Mojomittens:BAACLgAFFH8KAAIGAAQJwBrREABXAQAGAAQJwBrREABXAQAuAAQKfx0AAwYABwloI2MPAFsCAAYABwloI2MPAFsCAAgABQnAFpZAAFcBAAAA.Monstroqt:BAAALgADCgQJBAAAAA==.Morøs:BAAALgADCgYJBgAAAA==.Moxx:BAABLgAECn8ZAAIhAAkJtg6eGABgAQAhAAkJtg6eGABgAQAAAA==.',
Mu='Muffers:BAABLgAECn8gAAIhAAYJThOSHgAvAQAhAAYJThOSHgAvAQAAAA==.Muffpuff:BAAALgAECgQJBQAAAA==.Mutige:BAAALgADCgEJAQAAAA==.',
My='Mylotus:BAAALgAECgEJAQAAAA==.',
Na='Napkuntt:BAAALgADCgUJBQAAAA==.Napokin:BAAALgAFFAEJAQAAAA==.Napshade:BAABLgAECn8bAAMFAAcJMhuWFgCKAQAFAAYJSRyWFgCKAQALAAYJEhA9LgDbAAABLgAFFAEJAQACAAAAAA==.Nathanael:BAAALgAECgkJCQAAAA==.Natsuu:BAAALgAECgcJCgAAAA==.',
Nb='Nbayoungboyy:BAAALgADCgYJBgABLgAFFAUJFAAGAAMlAA==.',
Ne='Necroticoath:BAAALgAECgIJBgABLgAECgYJFAAPAL8gAA==.',
Ni='Nightor:BAAALgAECgEJAQAAAA==.Nikodemos:BAAALgAFFAUJFQAAAQ==.Nivahoof:BAAALgADCgEJAQAAAA==.',
No='Noc:BAABLgAECn8cAAMRAAgJVxJ3KQDAAQARAAgJVxJ3KQDAAQASAAUJNA+ILQAHAQAAAA==.Nomemage:BAAALgADCgEJAQAAAA==.',
Ob='Obe:BAAALgAFFAIJAgAAAA==.Obsidiangel:BAAALgADCggJEAAAAA==.',
Or='Oran:BAAALgAECggJEgAAAA==.Orctrax:BAABLgAECn8aAAMGAAgJVhG+NQB2AQAGAAgJVhG+NQB2AQAIAAEJBAK7jgAsAAAAAA==.',
Os='Osheat:BAABLgAECn8jAAITAAkJ1x+aCwCtAgATAAkJ1x+aCwCtAgAAAA==.Osmodeus:BAAALgAECgUJCAAAAA==.',
Ou='Outplay:BAAALgADCgUJBQAAAA==.',
Ox='Oxheart:BAAALgAECgEJAQAAAA==.',
Pa='Paltis:BAAALgAECgQJBAAAAA==.Paltonso:BAAALgADCgkJCQAAAA==.Pandaari:BAABLgAECn8WAAIFAAgJFAR3KAAEAQAFAAgJFAR3KAAEAQAAAA==.Papaschristo:BAAALgADCgUJBQAAAA==.Papasdiablo:BAAALgAECgEJAgAAAA==.',
Pe='Persimmon:BAABLgAECn8ZAAIiAAcJbxaNGwCsAQAiAAcJbxaNGwCsAQAAAA==.Peyton:BAAALgAECgUJBgAAAA==.',
Ph='Philip:BAAALgADCgcJDAAAAA==.Phyrie:BAAALgAECgUJCgABLgAECgYJFAAgAFAZAA==.',
Pi='Pittpete:BAAALgAECgEJAQAAAA==.',
Ps='Psythera:BAAALgAECgIJBAAAAA==.Psythern:BAAALgADCgYJCQABLgAECgIJBAACAAAAAA==.',
Pu='Punkybrewstr:BAABLgAECn8nAAMhAAgJHxAwJQACAQAhAAgJZAowJQACAQABAAYJhQ8QLgDkAAAAAA==.Pureshock:BAAALgAECggJDQAAAA==.Purpderf:BAAALgAFFAEJAQAAAA==.',
Pw='Pwnstar:BAAALgAECgQJCAAAAA==.',
Py='Pykei:BAAALgADCgcJDQAAAA==.Pyrri:BAABLgAECn8kAAQEAAkJQh0ACABhAgAEAAgJaR4ACABhAgALAAQJ4RXdUQDwAAAFAAMJdRQCMgDJAAAAAA==.',
Pz='Pznt:BAAALgAECgEJAQAAAA==.',
['Pé']='Péyton:BAAALgADCgEJAQAAAA==.',
['Pì']='Pì:BAAALgADCgEJAgAAAA==.',
['Pô']='Pôws:BAAALgAECgIJAwAAAA==.',
Qu='Quantonbomb:BAAALgAECggJCQAAAA==.',
Ra='Rabuf:BAAALgAECggJEgAAAA==.Raccoonadin:BAAALgADCgEJAQAAAA==.Ragingwater:BAAALgAECgYJEAAAAA==.Ranadheer:BAAALgAECgEJAgAAAA==.Raspaigus:BAAALgAECgQJBAAAAA==.Ratfu:BAABLgAECn8UAAIhAAYJOQX2RwD1AAAhAAYJOQX2RwD1AAAAAA==.Raudson:BAABLgAECn8UAAIjAAkJDCJTAgATAwAjAAkJDCJTAgATAwAAAA==.',
Re='Redizle:BAACLgAFFH8VAAIEAAUJgxfLCQCqAQAEAAUJgxfLCQCqAQAuAAQKfyQABAsACAnhHBYoAK8BAAQABwkUFuQbALcBAAsABgkyHBYoAK8BAAUABQnSEuY2ADYBAAAA.Reginrune:BAAALgAECgkJDQAAAA==.Resonance:BAAALgAECgcJEwAAAA==.Restroll:BAAALgADCgQJBAAAAA==.',
Rh='Rhaigar:BAAALgAECgUJCQAAAA==.Rhónatar:BAAALgADCgQJBAAAAA==.',
Ro='Rohdoog:BAABLgAECn8iAAIUAAgJahadDQDzAQAUAAgJaRadDQDzAQAAAA==.Roundabugman:BAACLgAFFH8GAAINAAIJRRmZHwClAAANAAIJRRmZHwClAAAuAAQKfxoAAw0ACAmIGgEYAJEBAA0ACAmIGgEYAJEBAAwAAwmnFNl3ALIAAAAA.',
Ru='Runedyu:BAAALgAECgUJBQAAAA==.',
Ry='Ryanno:BAABLgAECn8gAAIGAAgJsR8JEgBBAgAGAAgJsR8JEgBBAgAAAA==.Ryujinhalco:BAAALgADCgMJAwAAAA==.',
Sa='Sahomi:BAABLgAECn8gAAMEAAkJFQjLIQAcAQAEAAkJFQjLIQAcAQALAAIJTQWNdwBMAAAAAA==.Salana:BAAALgADCgcJBwAAAA==.Samwise:BAAALgAECgYJBgAAAA==.Sarai:BAAALgADCgEJAQAAAA==.Sarcini:BAABLgAECn8gAAIjAAgJuhTjCQClAQAjAAgJuhTjCQClAQAAAA==.Satrina:BAABLgAECn8hAAITAAgJHyJBEQBzAgATAAgJHyJBEQBzAgAAAA==.Savvy:BAAALgAECgQJBAAAAA==.',
Sc='Scrappy:BAAALgAECgEJAQAAAA==.',
Se='Selanthe:BAAALgAECgQJBgAAAA==.Seruk:BAAALgAECgEJBAAAAA==.Seventhghost:BAEALgAECgIJAgABLgAFFAQJCQAFADEQAA==.',
Sh='Shamander:BAAALgAFFAEJAQAAAA==.Shamsham:BAAALgADCgcJDAAAAA==.Sharky:BAAALgADCgEJAQAAAA==.Shocka:BAAALgADCgQJBAAAAA==.Shokanki:BAAALgAECgYJCwAAAA==.',
Si='Sicara:BAABLgAECn8sAAIXAAkJNBaHGgDqAQAXAAkJNBaHGgDqAQAAAA==.Silentmage:BAAALgADCgcJCAAAAA==.Silentslock:BAAALgADCgYJBQAAAA==.Sillylilguy:BAACLgAFFH8JAAIdAAMJnBE3AwADAQAdAAMJnBE3AwADAQAuAAQKfxgAAh0ACAmEH+8EAMECAB0ACAmEH+8EAMECAAAA.',
Sl='Slaik:BAAALgAECgQJBgAAAA==.',
So='Solemnograve:BAAALgAECgIJAgAAAA==.Somazugzug:BAABLgAECn8hAAIMAAkJZxdcLgDQAQAMAAkJZxdcLgDQAQAAAA==.Sothren:BAAALgAECgEJAgABLgADCgkJCQACAAAAAA==.',
Sp='Spacedguy:BAAALgADCgMJAwAAAA==.Spry:BAAALgAECgEJAQAAAA==.',
St='Staccato:BAAALgAECgEJAQAAAA==.',
Su='Sugar:BAABLgAECn8iAAMMAAgJlxE3OQCdAQAMAAgJlxE3OQCdAQANAAUJtw6hVgDrAAAAAA==.Sugars:BAAALgAECgEJAQAAAA==.Sulin:BAAALgADCgUJBwAAAA==.Sungôd:BAAALgADCgEJAQAAAA==.',
Sw='Swonks:BAAALgAECgMJAwAAAA==.Swyper:BAAALgAECgMJAwAAAA==.',
Sy='Synicism:BAAALgADCgcJDQAAAA==.',
Ta='Taintbubble:BAAALgAECgIJAgAAAA==.Tarnished:BAAALgADCgcJCAAAAA==.Tarquitus:BAACLgAFFH8JAAMXAAUJwA5FNADgAAAXAAQJLBNFNADgAAAQAAIJeAS+CgCTAAAuAAQKfzQAAxcACAndH5QMAGkCABcACAkcH5QMAGkCABAACAm8F0kRAFUCAAAA.Tattoosguy:BAAALgADCgEJAQAAAA==.',
Te='Teef:BAABLgAECn8VAAIkAAYJ+BTFFQBdAQAkAAYJ+BTFFQBdAQAAAA==.',
Th='Thanatös:BAABLgAECn8cAAMJAAgJbBatLgDmAQAJAAgJbBatLgDmAQAlAAQJrxRDDQD1AAAAAA==.Thedarkkness:BAABLgAECn8dAAIZAAcJ2BQ7HQBgAQAZAAcJ2BQ7HQBgAQAAAA==.Thrasher:BAAALgAECgEJAgAAAA==.',
Ti='Tidalwave:BAABLgAECn8lAAIMAAgJAxYvMQDCAQAMAAgJAxYvMQDCAQAAAA==.Tidus:BAAALgAECgYJEQAAAA==.Tinytotem:BAAALgAECgEJBAAAAA==.Tissue:BAABLgAECn8WAAIQAAcJbgnRLABjAQAQAAcJbgnRLABjAQAAAA==.',
To='Toasted:BAAALgADCgYJCQAAAA==.Tobibi:BAAALgAECgIJAgABLgAECgYJFAAPAL8gAA==.Todo:BAAALgADCgQJBAAAAA==.Tolip:BAABLgAECn8qAAMmAAgJSgTrJgAIAQAmAAgJSgTrJgAIAQAaAAYJgAgndgD1AAAAAA==.Tolipally:BAAALgAECgQJBwABLgAECggJKgAmAEoEAA==.Tolipicious:BAAALgADCgUJCQABLgAECggJKgAmAEoEAA==.',
Tr='Trauts:BAAALgAECgQJCAAAAA==.Treeadin:BAAALgAECggJEgAAAA==.Trollcula:BAAALgAECggJDgABLgAECggJHQAaALIQAA==.Truthwithin:BAAALgAECgUJDAAAAA==.',
Ts='Tsarrubus:BAABLgAECn8hAAIQAAkJcgn9DwCDAQAQAAkJcgn9DwCDAQAAAA==.',
Tu='Tula:BAAALgAECgUJCwAAAA==.Tusck:BAAALgAECgIJAgAAAA==.',
Tw='Twingert:BAAALgADCggJFAAAAA==.Twitch:BAAALgAECgYJEgAAAA==.',
Ty='Tyedyemess:BAAALgAECgMJAwAAAA==.',
['Tà']='Tàylor:BAABLgAECn8cAAIiAAkJOQsWJABnAQAiAAkJOQsWJABnAQAAAA==.',
Ub='Ubbaa:BAAALgAECgEJAQAAAA==.',
Ul='Ulghar:BAABLgAECn8WAAIgAAkJICBmFADJAQAgAAkJICBmFADJAQAAAA==.',
Ur='Ursock:BAAALgAECggJDgAAAA==.',
Uw='Uwuhshake:BAABLgAECn8dAAIaAAcJ5iQyBwDbAgAaAAcJ5iQyBwDbAgAAAA==.',
Va='Valdria:BAAALgAECgMJAwAAAA==.Valssien:BAAALgADCgkJCQAAAA==.Vanaria:BAAALgAECgQJBAAAAA==.Vanbrook:BAAALgAECgQJBAAAAA==.Vanden:BAAALgAECgYJCgAAAA==.Vanrion:BAAALgAFFAIJAgAAAA==.Varrodd:BAAALgADCgEJAQAAAA==.Vastextent:BAAALgADCgMJBAAAAA==.',
Ve='Velcro:BAAALgAECgYJEgAAAA==.Velsera:BAAALgAECgYJCAAAAA==.Velvet:BAAALgADCgQJCAAAAA==.Velyn:BAAALgAECgcJDwAAAA==.Velynara:BAAALgADCgIJAgABLgAECgYJCAACAAAAAA==.Vengefulcry:BAAALgAECgMJAwAAAA==.Vengefül:BAAALgADCgYJCAAAAA==.Vexara:BAAALgAECgQJBAAAAA==.',
Wa='Wanaaga:BAAALgAECggJDgAAAA==.',
Wh='Whohaveaggro:BAAALgADCgEJAgAAAA==.',
Wi='Wilmington:BAAALgADCgIJAgAAAA==.Wino:BAAALgAECggJCgAAAA==.Wiqui:BAAALgAECgEJAQAAAA==.Witulow:BAABLgAECn8ZAAIcAAcJog/YIgAvAQAcAAcJog/YIgAvAQAAAA==.',
Wo='Wolfadin:BAABLgAECn8sAAIDAAkJrRYEIgD+AQADAAkJrRYEIgD+AQAAAA==.Woopac:BAABLgAECn8iAAIgAAgJhhzsCABZAgAgAAgJhhzsCABZAgAAAA==.',
Wu='Wulfharth:BAAALgAECgYJDgAAAA==.',
Xe='Xenophics:BAACLgAFFH8TAAIDAAUJIBEcGgBEAQADAAUJIBEcGgBEAQAuAAQKfy4AAgMABwlaIWEsAMsBAAMABwlaIWEsAMsBAAEuAAUUAwkFAAkAIgcA.Xenophicstwo:BAACLgAFFH8FAAIJAAMJIge+MgDUAAAJAAMJIge+MgDUAAAuAAQKfyEAAgkABgnJFlhqADwBAAkABgnJFlhqADwBAAAA.',
Xu='Xuen:BAAALgAECgYJCQABLgAECggJIAADALghAA==.',
Ya='Yajsooblwj:BAAALgADCgMJAwAAAA==.',
Za='Zal:BAABLgAECn8aAAQDAAcJIxd6RwBvAQADAAcJbBZ6RwBvAQAiAAYJAhhUMQAOAQAjAAIJDRVeNAB2AAAAAA==.Zanor:BAAALgAECgIJAgAAAA==.Zarranora:BAAALgAECgEJAQAAAA==.Zatannå:BAAALgADCgYJCQAAAA==.',
Ze='Zect:BAABLgAECn8jAAIJAAkJoQ7xLQDpAQAJAAkJoQ7xLQDpAQAAAA==.Zenshin:BAAALgAECgIJAgAAAA==.Zentaur:BAAALgAECgQJBAAAAA==.Zetzu:BAAALgAECggJDgAAAA==.',
['Ål']='Ålucard:BAAALgAECggJEgAAAA==.',
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

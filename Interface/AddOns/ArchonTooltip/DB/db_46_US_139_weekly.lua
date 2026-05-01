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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Druid-Balance','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Frost','Warlock-Demonology','Druid-Feral','Monk-Windwalker','Hunter-Marksmanship','Warrior-Fury','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.',
Ac='Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAABLgAECn8kAAIBAAgJRheiFgAnAgABAAgJRheiFgAnAgAAAA==.',
Al='Aleraz:BAACLgAFFH8FAAMBAAMJjB73DAC/AAABAAIJwCD3DAC/AAACAAEJ1wc4GABQAAAuAAQKfykABAEACAm9H+IVAC0CAAEABwnZIOIVAC0CAAIACAm1GS8PAJYBAAMAAwkmB20pAIEAAAAA.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0RdXIwCYAQAEAAcJ0RdXIwCYAQAAAA==.Alucart:BAAALgADCgMJAwAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJCQAAAA==.',
An='Anewrbyss:BAAALgAECgQJBwAAAA==.Angela:BAABLgAECn8gAAIDAAgJexhRCAATAgADAAgJexhRCAATAgAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAABLgAECn8jAAIFAAkJ4iBZAQAiAwAFAAkJ4iBZAQAiAwAAAA==.Apocalýpsè:BAAALgADCggJCQAAAA==.Applebottum:BAAALgAECgUJBwAAAA==.Appärition:BAABLgAECn8XAAIGAAgJJxqhAQAoAgAGAAgJJxqhAQAoAgAAAA==.',
Ar='Arleance:BAAALgADCgcJFAAAAA==.Arondael:BAABLgAECn8VAAIFAAgJSRI+AwDHAQAFAAgJSRI+AwDHAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn8bAAIHAAYJjBbfQgBmAQAHAAYJjBbfQgBmAQAAAA==.Avendeloria:BAAALgADCgYJBgAAAA==.',
Az='Azrahn:BAAALgADCgEJAQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECgQJBwAIAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAABLgAECn8qAAIBAAkJ8SWaAgA9AwABAAkJ8SWaAgA9AwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgIJAgABLgAFFAIJBQAJACodAA==.Bartholomoo:BAABLgAECn8nAAIJAAgJJyENCACdAgAJAAgJJyENCACdAgAAAA==.Bayonetta:BAAALgAECgcJCwAAAA==.',
Be='Beeftornado:BAAALgAECgQJBAAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAQAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJDAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAAALgAECgQJEQAAAA==.Blazeknight:BAABLgAECn8gAAIKAAcJrxl+FgAXAgAKAAcJrxl+FgAXAgAAAA==.Blazemaker:BAABLgAECn8UAAIHAAYJLRAVYQAaAQAHAAYJLRAVYQAaAQAAAA==.Blazemaster:BAAALgAECgQJCAAAAA==.Blinduru:BAACLgAFFH8EAAILAAIJtB+mKAC3AAALAAIJtB+mKAC3AAAuAAQKfyMAAgsACQklItIFAIICAAsACQklItIFAIICAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJGAALAIoOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgADCgYJBwAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgIJAgAAAA==.',
Bp='Bpaìn:BAAALgAECgYJDAAAAA==.',
Br='Brink:BAAALgAECgQJBgAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Bromaster:BAAALgAECgQJBAAAAA==.Brones:BAAALgAECgcJAQAAAA==.Brossiere:BAABLgAECn8VAAQMAAgJihoBFwCYAQAMAAUJjhkBFwCYAQANAAYJMBHHqAAwAQAOAAUJExXfEAD1AAAAAA==.Bru:BAABLgAECn8hAAIBAAgJIh3vDACGAgABAAgJIh3vDACGAgAAAA==.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.',
Bu='Bullsmcgee:BAABLgAECn8XAAMJAAgJ7h/VDgBKAgAJAAgJ7h/VDgBKAgAPAAEJAAASQwA9AAAAAA==.Burninghunt:BAAALgADCgYJBgAAAA==.Burningtree:BAAALgAECgYJDAAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECgcJCQAAAA==.',
Ca='Camamoonmana:BAAALgAECggJEQAAAA==.Captcorndog:BAABLgAECn8XAAQQAAYJ0A8fNQAnAQAQAAYJ0A8fNQAnAQARAAUJ8wNvOACnAAASAAEJAACvQAAvAAAAAA==.Catdog:BAABLgAECn8ZAAITAAYJDxfQDwB8AQATAAYJDxfQDwB8AQAAAA==.Catechism:BAAALgAECgYJEAAAAA==.',
Ce='Cemeo:BAAALgAECgcJEwAAAA==.Cerberusalfa:BAABLgAECn8nAAIKAAkJoyVZAwBOAwAKAAkJoyVZAwBOAwAAAA==.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgYJEAAIAAAAAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAABLgAECn8bAAIHAAYJkBvwOQCBAQAHAAYJkBvwOQCBAQAAAA==.Chiphoof:BAAALgAECgYJDAAAAA==.Chocofox:BAAALgAECgYJCwAAAA==.Chokemagic:BAAALgAECgEJAgAAAA==.Chopndot:BAAALgAECgEJAwAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAAALgAECgIJAgAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAUJDgAMAHUPAA==.Clarabuns:BAACLgAFFH8OAAIMAAUJdQ+CBwB2AQAMAAUJdQ+CBwB2AQAuAAQKfxQAAgwACAnTFmUlAPsBAAwACAnTFmUlAPsBAAAA.Clarasbuns:BAAALgADCgQJBAABLgAFFAUJDgAMAHUPAA==.Clawdragoon:BAACLgAFFH8JAAMUAAQJxAb0DgALAQAUAAQJxAb0DgALAQAVAAMJ/ACZJACKAAAuAAQKfyIAAxQACAlkGWoUAG8CABQACAlkGWoUAG8CABUABQkwBNybAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn8jAAIMAAgJnhb3EQDOAQAMAAgJnhb3EQDOAQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8JAAIWAAMJdhrQEwDwAAAWAAMJdhrQEwDwAAAuAAQKfzAAAxYACAlKHXYIAGMCABYACAlKHXYIAGMCABcAAwlXE2hjALUAAAAA.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgADCggJDwAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8YAAMXAAgJRwp9FwBYAQAXAAgJRwp9FwBYAQAWAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAAALgAECgYJEQAAAA==.',
Da='Daddybod:BAABLgAECn8bAAIYAAgJbxJtDgCnAQAYAAgJbxJtDgCnAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Darktaynt:BAAALgAECgIJAwAAAA==.Darthfox:BAAALgAECgEJAQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathtracker:BAAALgAECgcJDQAAAA==.Deathwarden:BAAALgAECgYJCwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJBwAAAA==.Demise:BAABLgAECn8fAAIHAAgJuR04MQCtAgAHAAgJuR04MQCtAgAAAA==.Demonclem:BAAALgAECggJDAAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAABLgAECn8pAAMKAAkJDhG4BgDzAQAKAAkJDhG4BgDzAQALAAYJpwuGiAAUAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAECgYJDQAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAAALgAECgYJDwAAAA==.Distia:BAAALgAECgYJBwAAAA==.Divinedragon:BAABLgAECn8cAAMCAAgJYxP4CgDQAQACAAgJYxP4CgDQAQADAAcJ6wrmLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8gAAINAAgJ/BhiJgCqAQANAAgJ/BhiJgCqAQAAAA==.Dreya:BAABLgAECn8YAAIZAAcJqR/HAwADAgAZAAcJqR/HAwADAgAAAA==.Drinkcoolaid:BAAALgAECgYJEQAAAA==.Dritzle:BAABLgAECn8aAAMaAAgJ+RRPDQCWAQAaAAgJ+RRPDQCWAQAFAAQJHgi3EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dutchman:BAACLgAFFH8NAAIbAAUJcB35BAB8AQAbAAUJcB35BAB8AQAuAAQKfxwAAhsACAkNIWkIAAsDABsACAkNIWkIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgMJAwAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRqDgBvAgAEAAYJRSRqDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn8YAAMHAAgJABuzGQASAgAHAAgJABuzGQASAgAcAAEJ7hOUHAA6AAAAAA==.Elfstomper:BAAALgADCgEJAQAAAA==.Elitepaladin:BAABLgAECn8iAAIMAAgJ0xbhIQAPAgAMAAgJ0xbhIQAPAgAAAA==.Ellexi:BAAALgAECgYJCgAAAA==.Elyseia:BAABLgAECn8bAAIbAAcJbAUUUwDSAAAbAAcJbAUUUwDSAAAAAA==.',
Em='Empkin:BAAALgAECgcJEgAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.',
Ep='Epicsause:BAAALgADCgkJCQAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAEBLgAECn8hAAQPAAgJbRs8CgB2AgAPAAgJbRs8CgB2AgAdAAMJ+wjKCgCdAAAJAAEJAAAm1gAAAAAAAA==.Essdeath:BAAALgADCgkJFwAAAA==.',
Fa='Farael:BAAALgAECgQJBAAAAA==.Farmerbrown:BAAALgAECgEJAQABLgAECggJHQANAOwhAA==.Fatalmann:BAAALgAECgkJEQAAAA==.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgADCgEJAQAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flèxion:BAABLgAECn8oAAIJAAgJACWpBADfAgAJAAgJACWpBADfAgAAAA==.',
Fo='Foskin:BAAALgADCgcJBwABLgAECgYJEAAIAAAAAA==.',
Fr='Frassk:BAABLgAECn8oAAMGAAgJRRRpCQARAQAGAAYJuhNpCQARAQAeAAQJyhAqcACrAAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQABLgAECgcJCQAIAAAAAA==.Frostydru:BAABLgAECn8qAAIfAAgJtRxcAwATAgAfAAgJtRxcAwATAgAAAA==.Frozat:BAACLgAFFH8QAAIRAAYJiRSQBQCdAQARAAYJiRSQBQCdAQAuAAQKfyEAAxEACAkTH40GANoCABEACAkTH40GANoCABAAAQmAEY5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgYJIgALABMcAA==.',
Fu='Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Garbarn:BAAALgAECgkJEwAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAECggJHwAgAD8cAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJAwAAAA==.',
Gi='Gia:BAABLgAECn8bAAIEAAgJKhQnDQDTAQAEAAgJKhQnDQDTAQAAAA==.',
Gl='Glamoroüs:BAABLgAECn8YAAILAAgJ1xIWQgDrAQALAAgJ1xIWQgDrAQAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAAALgAECgYJDAAAAA==.Goodtimesm:BAAALgAECgEJAQAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAABLgAECn8rAAMbAAkJWSHaCwDjAgAbAAkJWSHaCwDjAgAhAAIJVgdXegBZAAAAAA==.Goretaint:BAAALgAECgQJBAAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJCwAAAA==.Gottamoo:BAAALgAECgkJDgAAAA==.',
Gr='Greenstank:BAAALgADCgMJAwABLgAECgcJCQAIAAAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn8nAAITAAgJuRzNAwD5AQATAAgJuRzNAwD5AQAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAQAAAA==.Hajin:BAAALgAECgYJCgAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECgcJBgAAAA==.Hawthorn:BAAALgAECgMJBQAAAA==.Hazyblades:BAAALgAECgEJAQAAAA==.',
He='Helacookie:BAAALgAECgcJDAAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgQJBwAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgADCgIJAgABLgAECgYJDwAIAAAAAA==.Hiver:BAAALgAECgEJAgAAAA==.',
Ho='Holes:BAAALgADCgIJAgAAAA==.Holier:BAABLgAECn8jAAINAAcJGBPEagCpAQANAAcJGBPEagCpAQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgcJCAABLgAECggJKQARAOUaAA==.Hopperstotem:BAAALgAECgIJAgAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAQAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJAwAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgMJAwAAAA==.Invysion:BAABLgAECn8kAAIDAAgJSA6RDQCwAQADAAgJSA6RDQCwAQAAAA==.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Ja='Jaidess:BAAALgADCgcJDQAAAA==.',
Je='Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgADCgIJAgAAAA==.Jeep:BAACLgAFFH8JAAIbAAMJTxsVFgAPAQAbAAMJTxsVFgAPAQAuAAQKfyMAAhsACAkwJVMEAEoDABsACAkwJVMEAEoDAAAA.Jellybea:BAABLgAECn8hAAIBAAgJiiMwBAASAwABAAgJiiMwBAASAwAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgUJCgAAAA==.Jump:BAAALgAECgQJCgAAAA==.Jurisdiction:BAAALgAECgYJDgAAAA==.',
Jz='Jz:BAAALgADCgQJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8fAAIVAAcJhiFOEwCbAgAVAAcJhiFOEwCbAgAAAA==.Kadath:BAAALgADCgEJAQAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJCgAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJCgAIAAAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQAAAA==.Karma:BAAALgAECgMJAwAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keho:BAAALgAECgYJEAAAAA==.Kenalia:BAABLgAECn8ZAAIEAAgJuROkEACgAQAEAAgJuROkEACgAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAINAAgJMSCQDABiAgANAAgJMSCQDABiAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAABLgAECn8oAAMiAAkJHB3bGwBuAgAiAAkJHB3bGwBuAgAjAAMJ3BBPKwCaAAAAAA==.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn8dAAINAAgJ7CE+CwByAgANAAgJ7CE+CwByAgAAAA==.Kissmydots:BAABLgAECn8pAAIeAAgJYhvrDwAoAgAeAAgJYhvrDwAoAgAAAA==.Kitja:BAABLgAECn8WAAIBAAYJ+xxgCwDuAQABAAYJ+xxgCwDuAQAAAA==.Kitla:BAAALgADCgUJBQABLgAECgYJFgABAPscAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECggJGwAVANUeAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAUJEgAUABoWAA==.Kohman:BAABLgAECn8aAAIeAAYJ5RTEfABiAQAeAAYJ5RTEfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kr='Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8LAAIKAAQJaiXHAACjAQAKAAQJaiXHAACjAQAuAAQKfxYAAgoACAmhIjYEADcDAAoACAmhIjYEADcDAAAA.Krom:BAABLgAECn8hAAMiAAgJYhdSDwDDAQAiAAgJYhdSDwDDAQAjAAEJMwl7MAAtAAAAAA==.Kronas:BAAALgAECgcJDQAAAA==.Kronophyne:BAABLgAECn8rAAIHAAkJ+B34OgCLAgAHAAkJ+B34OgCLAgAAAA==.Kronotality:BAABLgAECn8tAAIPAAgJmyKjAgA8AgAPAAgJmyKjAgA8AgAAAA==.Kronotek:BAAALgAECgYJBgAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.Kynbrochel:BAAALgAECgEJAQAAAA==.',
La='Laars:BAAALgAECgEJAQAAAA==.Laimaster:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn8bAAIZAAYJRRWnCABkAQAZAAYJRRWnCABkAQAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lapsu:BAABLgAECn8aAAIgAAgJfxRjCwC/AQAgAAgJfxRjCwC/AQAAAA==.Lascivia:BAABLgAECn8hAAMiAAgJ4B5NJgAnAgAiAAgJTBxNJgAnAgAkAAcJXw5mMADBAAAAAA==.Lawhanx:BAAALgADCgEJAQABLgAECgcJGgALALIXAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMeAAYJyRchiQBHAQAeAAUJyRchiQBHAQAGAAIJxQF9YQBLAAAAAA==.',
Le='Leademon:BAABLgAECn8lAAMLAAcJ7h24LQBGAgALAAcJ7h24LQBGAgAKAAIJTRrQWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgcJJQALAO4dAA==.Leftlane:BAABLgAECn8bAAIWAAcJwiMIBADDAgAWAAcJwiMIBADDAgAAAA==.Legato:BAAALgAECgcJCAABLgAFFAYJFgAWAA0eAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8bAAIVAAgJ1R7ODAA8AgAVAAgJ1R7ODAA8AgAAAA==.',
Li='Liberté:BAAALgADCgcJCAAAAA==.Lie:BAABLgAECn8bAAIaAAgJ/RFoJQDNAQAaAAgJ/RFoJQDNAQAAAA==.Lightsdown:BAAALgADCgcJDgAAAA==.Lilbeebs:BAAALgAECgkJDwAAAA==.Lileth:BAAALgAECggJAgAAAA==.Lilflea:BAAALgAECgcJCgAAAA==.Lilzuki:BAAALgAECgYJDgAAAA==.Lilïth:BAACLgAFFH8KAAIPAAQJ8h8RBQBPAQAPAAQJ8h8RBQBPAQAuAAQKfxsAAg8ABwmDJPAGAMICAA8ABwmDJPAGAMICAAAA.Linguine:BAAALgAECgEJAQABLgAFFAMJBQABAIweAA==.Lisalisa:BAABLgAECn8ZAAIWAAYJFxcfIABkAQAWAAYJFxcfIABkAQAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAHAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAAALgAECgUJDQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Magicmoo:BAAALgAECgEJAQABLgAECggJHQANAOwhAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAABLgAECn8oAAIUAAkJuQpwEwBrAQAUAAkJuQpwEwBrAQAAAA==.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgUJBQABLgAECgYJDAAIAAAAAA==.Markamanimal:BAACLgAFFH8KAAIfAAQJ6hJ4AQBrAQAfAAQJ6hJ4AQBrAQAuAAQKfx8AAh8ACAkqIYYDAPwCAB8ACAkqIYYDAPwCAAAA.Marnix:BAAALgAECgYJEAAAAA==.',
Me='Medikus:BAABLgAECn8ZAAIWAAgJkRoeCQBYAgAWAAgJkRoeCQBYAgAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Menil:BAABLgAECn8VAAMEAAgJwBtSFgAQAgAEAAcJJhpSFgAQAgAgAAMJ8xleMACAAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAEBLgAECn8qAAMHAAgJYyCCFgAoAgAHAAgJYyCCFgAoAgAlAAEJAADoDABcAAAAAA==.',
Mo='Mockra:BAABLgAECn8mAAMHAAgJ6R6KEwA+AgAHAAgJ6R6KEwA+AgAcAAIJuBipGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgADCgMJAwAAAA==.Moolou:BAABLgAECn8eAAIOAAgJvh+6AgBQAgAOAAgJvh+6AgBQAgAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAYJGQANABMXAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECggJFwAJAO4fAA==.Morechie:BAABLgAECn8YAAImAAcJVQ/EAwB0AQAmAAcJVQ/EAwB0AQAAAA==.Mortiferon:BAABLgAECn8gAAIJAAgJ9hs4IADGAQAJAAgJ9hs4IADGAQAAAA==.',
Mu='Muhgunguh:BAAALgADCgYJBgAAAA==.Munnky:BAABLgAECn8VAAIEAAYJjB+ECwDvAQAEAAYJjB+ECwDvAQAAAA==.',
My='Mythrandere:BAAALgADCgUJBQAAAA==.',
['Má']='Mánflu:BAABLgAECn8rAAMjAAkJ3x4TAwDiAgAjAAkJ3x4TAwDiAgAiAAcJSRpONADZAQAAAA==.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgADCgUJBQAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgADCgEJAQABLgAECgcJCAAIAAAAAA==.Narn:BAABLgAECn8rAAQSAAgJ8RrQCQBCAgASAAcJrRjQCQBCAgAQAAYJsw9bJQDdAAARAAIJLQh+QQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgcJBgAAAA==.Necrotion:BAAALgAECgYJEQAAAA==.Nerrisa:BAABLgAECn8fAAICAAgJchN6DQCtAQACAAgJchN6DQCtAQAAAA==.Nertt:BAAALgADCgYJBgAAAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgUJBQAAAA==.',
No='Noblewarrior:BAACLgAFFH8OAAIiAAQJhxW4BwBXAQAiAAQJhxW4BwBXAQAuAAQKfyUAAiIACAmcJCACAMsCACIACAmcJCACAMsCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nooj:BAACLgAFFH8fAAMFAAcJOiISAABxAgAFAAcJOiISAABxAgAaAAYJZBRAAQDAAQAuAAQKfx4AAwUACQl/IToAAMMDAAUACQl/IToAAMMDABoABgmFEow6AEQBAAAA.Notakoala:BAACLgAFFH8SAAIUAAUJGhZ5CQBIAQAUAAUJGhZ5CQBIAQAuAAQKfyEAAhQACAmuIlANAMUCABQACAmuIlANAMUCAAAA.Nothnx:BAAALgAECgEJAgAAAA==.Notoriouspat:BAAALgAECgQJDgAAAA==.Notsamadeath:BAAALgAECgQJBAAAAA==.Noyber:BAAALgADCgYJBgAAAA==.Noydin:BAAALgAECgYJCQAAAA==.',
['Nü']='Nüll:BAAALgAECgYJCQAAAA==.',
Ob='Obern:BAAALgAECggJDQAAAA==.Oblïna:BAAALgAECgYJEAAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJBQAAAA==.',
On='Onetozerosix:BAABLgAECn8WAAIJAAkJlhYgJACxAQAJAAkJlhYgJACxAQAAAA==.',
Oo='Oogak:BAAALgAECgEJAQAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgADCgEJAQAAAA==.Operation:BAAALgAECgQJBwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgADCgcJBwAAAA==.Pairadeez:BAAALgAECgQJBQAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgMJAwAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAAALgAECgcJEQAAAA==.Parakka:BAABLgAECn8XAAIWAAgJgBHDFgCwAQAWAAgJgBHDFgCwAQAAAA==.Pavle:BAAALgADCgUJBQAAAA==.Pawp:BAAALgAECgQJBAABLgAECgcJHgABAPITAA==.',
Pe='Pepsidew:BAAALgADCgcJCwAAAA==.Pepsisprite:BAABLgAECn8UAAIBAAgJzxOwDwCpAQABAAgJzxOwDwCpAQAAAA==.Pesky:BAAALgAECgYJDAAAAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAAALgAECgYJCgABLgAFFAQJCgAPAPIfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIHAAkJQRwHIQDvAgAHAAkJQRwHIQDvAgAAAA==.',
Pi='Picklez:BAAALgAECgYJEQAAAA==.Pissflizzle:BAAALgAECgYJEgAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAAALgAECgYJDQAAAA==.',
Pr='Praye:BAAALgAECgMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgEJAQABLgAECgMJBAAIAAAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAAALgAECgYJEQAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgMJCQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgUJDAAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECgMJAwABLgAECggJDQAIAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECggJDQAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn8pAAIHAAgJqiK5CgCUAgAHAAgJqiK5CgCUAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAECgQJBAAAAA==.Riivan:BAAALgAECgYJDgAAAA==.Rishi:BAABLgAECn8rAAINAAgJ4hLxMgB3AQANAAgJ4hLxMgB3AQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8aAAIEAAcJ9w4mLwBAAQAEAAcJ9w4mLwBAAQAAAA==.Rokmog:BAAALgADCgUJBQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECggJIwAMAJ4WAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJEwABLgAECggJJQAgAAQgAA==.Sainsei:BAAALgAECgQJBAAAAA==.Saith:BAAALgAECgEJBAAAAA==.Samasear:BAABLgAECn8UAAIiAAgJ0w8uMgDjAQAiAAgJ0w8uMgDjAQABLgAFFAQJDgAJACIfAA==.Sandwitch:BAABLgAECn8pAAMeAAgJZxKDHwC4AQAeAAgJZxKDHwC4AQAGAAIJmxBuUwB0AAAAAA==.Sargatana:BAABLgAECn8eAAIYAAgJ1RZNCgDmAQAYAAgJ1RZNCgDmAQAAAA==.Sars:BAAALgAECgYJDQAAAA==.Sauronxd:BAAALgAECgMJAwAAAA==.',
Sc='Scalion:BAABLgAECn8aAAMLAAcJshcuSADTAQALAAcJFxcuSADTAQAKAAQJ+BG5SwDAAAAAAA==.Schrodinger:BAAALgAECgYJDAAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn8YAAIkAAgJcxGgCgB/AQAkAAgJcxGgCgB/AQAAAA==.',
Sh='Shadowtiger:BAABLgAECn8WAAIbAAcJPgYxOQAuAQAbAAcJPgYxOQAuAQAAAA==.Shadrad:BAAALgAECggJEQAAAA==.Shamanor:BAEALgAECgcJCAAAAA==.Shammoo:BAAALgAECgEJAQABLgAFFAYJGQANABMXAA==.Shantz:BAABLgAECn8UAAIPAAYJBQ2MEgD2AAAPAAYJBQ2MEgD2AAAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8ZAAIXAAgJZBo0DwCwAQAXAAgJZBo0DwCwAQAAAA==.Shortbuss:BAAALgADCgYJDwAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silx:BAABLgAECn8VAAMDAAcJMBE9IQCJAQADAAcJMBE9IQCJAQACAAEJoBY/XQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.',
Sk='Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgADCgYJBgAAAA==.Slâte:BAAALgAFFAEJAQAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.',
So='Somaliabiggs:BAAALgAECgYJCgAAAA==.Sorraba:BAAALgAECgQJBAAAAA==.Soryan:BAAALgAECggJEAAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8KAAIeAAMJQiFGGQAnAQAeAAMJQiFGGQAnAQAuAAQKfxwABB4ABwk8IygXAMkCAB4ABwk8IygXAMkCACYAAQkAAO4fAHIAAAYAAQm1GkBiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8WAAMNAAgJNhSFKwCUAQANAAgJNhSFKwCUAQAMAAUJowh1YwDuAAABLgABCgYJCwAIAAAAAA==.Spannky:BAAALgADCgYJCgABLgAECgYJFQAEAIwfAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAABLgAECn8WAAIYAAYJzBjSLgCcAQAYAAYJzBjSLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJFgAYAMwYAA==.Stormcharred:BAABLgAECn8eAAIHAAgJ5SCbKADQAgAHAAgJ5SCbKADQAgAAAA==.Stormknight:BAAALgAECgQJBgAAAA==.Straka:BAABLgAECn8XAAIVAAgJIRMaPgCrAQAVAAgJIRMaPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdruid:BAAALgADCgUJBQABLgAFFAUJDwANACsdAA==.Supermonks:BAAALgAECgQJBAABLgAFFAUJDwANACsdAA==.Superpi:BAAALgAECgYJDgABLgAFFAUJDwANACsdAA==.Superret:BAACLgAFFH8PAAINAAUJKx3BCQBfAQANAAUJKx3BCQBfAQAuAAQKfyEAAg0ACAn+IfcOABYDAA0ACAn+IfcOABYDAAAA.Superskeet:BAABLgAECn8lAAIMAAgJcxceCQBGAgAMAAgJcxceCQBGAgAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMhAAYJlBb9OgBzAQAhAAYJjhT9OgBzAQAbAAUJAw06TgDjAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAABLgAECn8iAAMFAAgJ8AufBACKAQAnAAgJmwqtBAC5AQAFAAgJzwmfBACKAQAAAA==.Synhunt:BAAALgADCgYJBwAAAA==.Synicc:BAAALgAECgEJAQAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8HAAINAAQJ0xjXCABuAQANAAQJ0xjXCABuAQAuAAQKfx4AAg0ACQlJHqkPABEDAA0ACQlJHqkPABEDAAAA.Tano:BAAALgAECgUJBwABLgAECggJJgAHAOkeAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tasty:BAAALgAECgQJCgAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Taírn:BAAALgAECgYJDwAAAA==.',
Te='Tehpredator:BAAALgAECgIJAwAAAA==.Teilin:BAACLgAFFH8WAAIWAAYJDR5aAQAHAgAWAAYJDR5aAQAHAgAuAAQKfyIAAhYACQmLI7IEACcDABYACQmLI7IEACcDAAAA.',
Th='Theaterthug:BAAALgADCgcJEgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgEJAQABLgAECgQJBAAIAAAAAA==.Theßigshot:BAABLgAECn8VAAIVAAYJICO/IgAyAgAVAAYJICO/IgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAABLgAECn8kAAMLAAgJXCMMAwDMAgALAAgJXCMMAwDMAgAKAAcJWB0KFAAyAgAAAA==.Thundurus:BAABLgAECn8eAAIXAAgJdhLQHQAoAQAXAAgJdhLQHQAoAQAAAA==.',
Ti='Timmayy:BAABLgAECn8eAAIeAAgJBBZ3OQAmAgAeAAgJBBZ3OQAmAgAAAA==.Tindrill:BAABLgAECn8XAAIjAAgJ+B+VAwDKAgAjAAgJ+B+VAwDKAgAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAAALgAECgYJEAAAAA==.Totemagoat:BAACLgAFFH8LAAMWAAQJ1BjHCwA1AQAWAAQJ1BjHCwA1AQAXAAEJFAMmJQBAAAAuAAQKfykAAxYACAkYE9YsANcBABYACAkYE9YsANcBABcABgmOF+BIACQBAAAA.Totemlyfine:BAABLgAECn8dAAIWAAcJ1yIiBgCNAgAWAAcJ1yIiBgCNAgAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJDQAAAA==.Treechains:BAAALgAECgYJEQAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAAALgAECgcJEwAAAA==.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgIJAgAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjB1mEABUAgAEAAkJjB1mEABUAgAAAA==.',
Un='Undeadmonks:BAABLgAECn8iAAMYAAgJEhB+FABgAQAYAAgJNg9+FABgAQAgAAMJdgq4ZQB2AAAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgQJBAAAAA==.Valeshot:BAABLgAECn8cAAIbAAgJQAloPwCxAQAbAAgJQAloPwCxAQAAAA==.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgMJAwAAAA==.Valssra:BAAALgAECgYJEQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8IAAQoAAQJKRNdBABeAQAoAAQJcRJdBABeAQAbAAIJgA9MKgCmAAAhAAEJgA+iJwBNAAAuAAQKfxcABBsACAmdIiEUAJUCABsACAmsISEUAJUCACEABAnyHxE8AG0BACgAAgnhG5sfAKYAAAAA.Vedronas:BAAALgAECgcJEwAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Verdict:BAAALgADCgcJCwAAAA==.Vern:BAABLgAECn8YAAMDAAgJ9xfxCgDeAQADAAgJ9xfxCgDeAQACAAIJgwYjWQBWAAAAAA==.Vernah:BAAALgADCgQJBAABLgAECggJGAADAPcXAA==.Verybad:BAABLgAECn86AAIHAAYJpRyFPQB1AQAHAAYJpRyFPQB1AQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgADCgYJBgAAAA==.',
Wa='Waamchifu:BAABLgAECn8VAAIYAAgJ/RICEgB8AQAYAAgJ/RICEgB8AQAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAAALgAECgYJCgAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgADCgMJAwABLgAECggJHQANAOwhAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgYJCAAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8YAAINAAYJ1BpIKwCVAQANAAYJ1BpIKwCVAQABLgAECgYJEAAIAAAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.',
Yu='Yudah:BAABLgAECn8fAAQoAAgJ8hR8BgAGAgAoAAgJwxN8BgAGAgAhAAUJvQoBWQDhAAAbAAcJqApDVQDLAAAAAA==.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBgAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn8lAAMgAAgJBCDEAwB9AgAgAAgJBCDEAwB9AgAEAAEJSRXSZAA+AAAAAA==.Zarinaria:BAABLgAECn8YAAILAAYJig7ifQAvAQALAAYJig7ifQAvAQAAAA==.',
Zh='Zhael:BAABLgAECn8WAAILAAgJuhkLEwDTAQALAAgJuhkLEwDTAQAAAA==.',
Zo='Zodstrike:BAAALgAECgYJDwAAAA==.Zomara:BAAALgAECgIJBgAAAA==.Zooboo:BAAALgAECgcJEwAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJBgAAAA==.',
['Äú']='Äúra:BAAALgAECgQJBwAAAA==.',
['Åi']='Åir:BAAALgADCgIJAgAAAA==.',
['Ðô']='Ðôôm:BAAALgAECgEJAQAAAA==.',
['Öv']='Överpöwered:BAAALgADCgIJAgAAAA==.',
['Öð']='Öðïn:BAAALgADCgQJBAAAAA==.',
['ßl']='ßlisster:BAAALgADCgYJBgAAAA==.',
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

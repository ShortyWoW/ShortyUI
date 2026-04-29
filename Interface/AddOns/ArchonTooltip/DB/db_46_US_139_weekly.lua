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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Rogue-Assassination','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Druid-Balance','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Paladin-Retribution','Rogue-Subtlety','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Druid-Guardian','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Monk-Windwalker','Warrior-Protection','Mage-Fire','Mage-Arcane','Paladin-Protection','Warlock-Affliction','Evoker-Devastation','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.Absolution:BAAALgAECgMJAwAAAA==.',
Ac='Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAABLgAECn8cAAIBAAgJ0RacFgAnAgABAAgJ0RacFgAnAgAAAA==.',
Al='Aleraz:BAABLgAECn8hAAQBAAgJAh4VBQDaAQABAAcJ2SAVBQDaAQACAAcJYBTVLQBxAQADAAEJWwxKVgA1AAAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8WAAIEAAYJQxhlIwCZAQAEAAYJQxhlIwCZAQAAAA==.Alucart:BAAALgADCgMJAwAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.',
An='Anewrbyss:BAAALgAECgQJBwAAAA==.Angela:BAABLgAECn8eAAIDAAgJaxgzAwASAgADAAgJaxgzAwASAgAAAA==.Anna:BAAALgAECgIJAgAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAABLgAECn8dAAIFAAgJJiFaAQAiAwAFAAgJJiFaAQAiAwAAAA==.Apocalýpsè:BAAALgADCgIJAgAAAA==.Applebottum:BAAALgAECgUJBwAAAA==.Appärition:BAAALgAECgYJDwAAAA==.',
Ar='Arleance:BAAALgADCgcJFAAAAA==.Arondael:BAAALgAECgYJDQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgUJBgAAAA==.',
Av='Avanti:BAABLgAECn8VAAIGAAYJuhOoIQBMAQAGAAYJuhOoIQBMAQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECgQJBwAHAAAAAA==.',
Ba='Backmoist:BAAALgAECgEJAQAAAA==.Bagmaster:BAABLgAECn8kAAIBAAgJ2CWZAgA+AwABAAgJ2CWZAgA+AwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgIJAgABLgAECgYJEAAHAAAAAA==.Bartholomoo:BAABLgAECn8fAAIIAAgJpRidBwAGAgAIAAgJpRidBwAGAgAAAA==.Bayonetta:BAAALgAECgcJCAAAAA==.',
Be='Beeftornado:BAAALgADCggJCQAAAA==.Belakor:BAAALgADCgIJAgAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bigmanblasto:BAAALgADCgMJBAAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgQJBgAAAA==.Bizniz:BAAALgAECgQJCQAAAA==.',
Bl='Blazefury:BAAALgAECgQJDQAAAA==.Blazeknight:BAABLgAECn8dAAIJAAcJrxl9FgAXAgAJAAcJrxl9FgAXAgAAAA==.Blazemaker:BAAALgAECgYJEwAAAA==.Blazemaster:BAAALgAECgQJCAAAAA==.Blinduru:BAABLgAECn8iAAIKAAkJqCGEDAAcAwAKAAkJqCGEDAAcAwAAAA==.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJFQAKABIOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgADCgEJAQAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgIJAgAAAA==.',
Bp='Bpaìn:BAAALgAECgQJBgAAAA==.',
Br='Brink:BAAALgAECgQJBgAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Bromaster:BAAALgAECgIJAgAAAA==.Brones:BAAALgAECgcJAQAAAA==.Brossiere:BAAALgAECgcJDAAAAA==.Bru:BAABLgAECn8eAAIBAAgJjBztDACGAgABAAgJjBztDACGAgAAAA==.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.',
Bu='Bubblegal:BAAALgADCgMJAwAAAA==.Bullsmcgee:BAAALgAECgYJDwAAAA==.Burningtree:BAAALgAECgQJBgAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECgcJCQAAAA==.',
Ca='Camamoonmana:BAAALgAECggJEQAAAA==.Captcorndog:BAAALgAECgYJEgAAAA==.Catdog:BAAALgAECgYJDgAAAA==.Catechism:BAAALgAECgQJCgAAAA==.',
Ce='Cemeo:BAAALgAECgcJEgAAAA==.Cerberusalfa:BAABLgAECn8hAAIJAAgJAiRYAwBOAwAJAAgJAiRYAwBOAwAAAA==.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgYJEgAHAAAAAA==.Chewbaca:BAAALgAECgEJAgAAAA==.Chickennuggi:BAAALgAECgYJEgAAAA==.Chiphoof:BAAALgAECgQJBgAAAA==.Chocofox:BAAALgAECgYJCgAAAA==.Chokemagic:BAAALgAECgEJAgAAAA==.Chopndot:BAAALgAECgEJAQAAAA==.Chozen:BAAALgADCgcJBwAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAQJCQALAEcQAA==.Clarabuns:BAACLgAFFH8JAAILAAQJRxBBBAAzAQALAAQJRxBBBAAzAQAuAAQKfxQAAgsACAnTFmMlAPsBAAsACAnTFmMlAPsBAAAA.Clarasbuns:BAAALgADCgQJBAABLgAFFAQJCQALAEcQAA==.Clawdragoon:BAABLgAECn8iAAMMAAgJZBlsFABvAgAMAAgJZBlsFABvAgANAAUJMATSmwCUAAAAAA==.',
Co='Colosie:BAAALgAECgUJDQAAAA==.Comegetpsalm:BAABLgAECn8bAAILAAgJ+RVOBwDXAQALAAgJ+RVOBwDXAQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8GAAIOAAMJ5xZoBgDzAAAOAAMJ5xZoBgDzAAAuAAQKfygAAw4ACAlkHNgEAB0CAA4ACAlkHNgEAB0CAA8AAwlXE15jALUAAAEuAAUUBAkJAAQANxQA.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgADCggJDAAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAAALgAECggJEgAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAAALgAECgYJEAAAAA==.',
Da='Daddybod:BAABLgAECn8YAAIQAAgJbxFUBgCfAQAQAAgJbxFUBgCfAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Darktaynt:BAAALgAECgEJAQAAAA==.Darío:BAAALgADCgMJAwAAAA==.',
De='Deadsean:BAAALgAECgQJCAAAAA==.Deathtracker:BAAALgAECgYJBgAAAA==.Deathwarden:BAAALgAECgYJCwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJBwAAAA==.Demise:BAABLgAECn8fAAIGAAgJuR04MQCtAgAGAAgJuR04MQCtAgAAAA==.Demonclem:BAAALgAECggJDAAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAABLgAECn8gAAMJAAgJ5w4pBACdAQAJAAgJ5w4pBACdAQAKAAYJpwuHiAAUAQAAAA==.Destructor:BAAALgAECgYJDAAAAA==.Devourera:BAAALgAECgUJBwAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAAALgAECgQJCQAAAA==.Distia:BAAALgAECgUJBgAAAA==.Divinedragon:BAABLgAECn8aAAMCAAgJtRPfBQCsAQACAAcJXRTfBQCsAQADAAcJ6wrnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8eAAIRAAgJehcbEACkAQARAAgJehcbEACkAQAAAA==.Dreya:BAAALgAECgYJEQAAAA==.Drinkcoolaid:BAAALgAECgYJDAAAAA==.Dritzle:BAABLgAECn8aAAMSAAgJ+RQ2BQCnAQASAAgJ+RQ2BQCnAQAFAAQJHgi3EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dutchman:BAACLgAFFH8IAAITAAMJ/BnxCQASAQATAAMJ/BnxCQASAQAuAAQKfxwAAhMACAkNIWcIAAsDABMACAkNIWcIAAsDAAAA.',
Eh='Ehhmuh:BAAALgADCgkJFAAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRnDgBxAgAEAAYJRSRnDgBxAgAAAA==.',
El='Eldrene:BAAALgAECgYJDwAAAA==.Elfstomper:BAAALgADCgEJAQAAAA==.Elitepaladin:BAABLgAECn8aAAILAAgJ0xbiIQAOAgALAAgJ0xbiIQAOAgAAAA==.Ellexi:BAAALgAECgYJCgAAAA==.Elyseia:BAABLgAECn8VAAITAAcJbAUSJQDbAAATAAcJbAUSJQDbAAAAAA==.',
Em='Empkin:BAAALgAECgcJEgAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.',
Ep='Epicsause:BAAALgADCgMJAwAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAEBLgAECn8eAAQUAAgJbRs7CgB2AgAUAAgJbRs7CgB2AgAVAAMJ+wisBQCmAAAIAAEJAAC0XgAAAAAAAA==.Essdeath:BAAALgADCgcJDgAAAA==.',
Fa='Farael:BAAALgAECgQJBAAAAA==.Farmerbrown:BAAALgAECgEJAQABLgAECggJHAARAOwhAA==.Fatalmann:BAAALgAECggJCQAAAA==.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.',
Fe='Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAQAAAA==.Flèxion:BAABLgAECn8gAAIIAAgJpyJWAgCXAgAIAAgJpyJWAgCXAgAAAA==.',
Fo='Foskin:BAAALgADCgcJBwABLgAECgYJEgAHAAAAAA==.',
Fr='Frassk:BAABLgAECn8gAAMWAAcJABEsKgAZAQAWAAUJMw8sKgAZAQAXAAQJRhDJugDjAAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQAAAA==.Frostydru:BAABLgAECn8kAAIYAAgJ/xsPAgDRAQAYAAgJ/xsPAgDRAQAAAA==.Frozat:BAACLgAFFH8PAAIZAAUJfheHBQCdAQAZAAUJfheHBQCdAQAuAAQKfyAAAxkACAkTH4sGANoCABkACAkTH4sGANoCABoAAQmAEYpeAEAAAAAA.Frösting:BAAALgADCgcJDgAAAA==.',
Fu='Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Garbarn:BAAALgAECgkJEwAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgIJAgAAAA==.',
Gi='Gia:BAAALgAECgYJEwAAAA==.',
Gl='Glamoroüs:BAABLgAECn8YAAIKAAgJ1xIYQgDsAQAKAAgJ1xIYQgDsAQAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAAALgAECgYJBgAAAA==.Goodtimesm:BAAALgADCgMJAwAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAABLgAECn8lAAMTAAgJ0SHbCwDjAgATAAgJ0SHbCwDjAgAbAAIJVgdSegBZAAAAAA==.Goretaint:BAAALgAECgEJAQAAAA==.Gothladriel:BAAALgAECgYJCgAAAA==.Gottamoo:BAAALgAECgkJDgAAAA==.',
Gr='Greenstank:BAAALgADCgMJAwABLgAECgUJDQAHAAAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn8fAAIcAAgJ7xuvAQDvAQAcAAgJ7xuvAQDvAQAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgADCgEJAQAAAA==.Hajin:BAAALgAECgYJCgAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Hawthorn:BAAALgAECgMJBQAAAA==.Hazyblades:BAAALgAECgEJAQAAAA==.',
He='Helacookie:BAAALgAECgcJDAAAAA==.Heomors:BAAALgADCgcJCAAAAA==.Hexxan:BAAALgAECgMJAwAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgADCgIJAgABLgAECgYJDwAHAAAAAA==.Hiver:BAAALgAECgEJAgAAAA==.',
Ho='Holier:BAABLgAECn8dAAIRAAcJ/xHEagCpAQARAAcJ/xHEagCpAQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgcJCAABLgAFFAQJCgAXAJwWAA==.Hopperstotem:BAAALgAECgIJAgAAAA==.Horuu:BAAALgAECgIJAwAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAQAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJAgAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgMJAgAAAA==.Invysion:BAABLgAECn8cAAIDAAgJWAgkIgCDAQADAAgJWAgkIgCDAQAAAA==.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Ja='Jaidess:BAAALgADCgcJBwAAAA==.',
Je='Jeanjean:BAAALgAECgcJBwAAAA==.Jeannjeann:BAAALgAECgcJEAAAAA==.Jediknîght:BAAALgADCgIJAgAAAA==.Jeep:BAACLgAFFH8GAAITAAMJGxOlBwAKAQATAAMJGxOlBwAKAQAuAAQKfyEAAhMACAkwJVMEAEoDABMACAkwJVMEAEoDAAAA.Jellybea:BAABLgAECn8eAAIBAAgJ8SIuBAASAwABAAgJ8SIuBAASAwAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgUJBwAAAA==.Jump:BAAALgAECgQJCgAAAA==.Jurisdiction:BAAALgAECgQJCAAAAA==.',
Jz='Jz:BAAALgADCgQJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgQJCgAAAA==.',
Ka='Kaan:BAABLgAECn8fAAINAAcJhiFNEwCbAgANAAcJhiFNEwCbAgAAAA==.Kadath:BAAALgADCgEJAQAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgMJBAAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJCgAHAAAAAA==.Kamela:BAAALgAECgIJAgAAAA==.Karael:BAAALgAECgUJDwAAAA==.Karma:BAAALgADCggJEwAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgYJDwAAAA==.',
Ke='Keho:BAAALgAECgQJCgAAAA==.Kenalia:BAAALgAECggJEwAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAECgMJAwAAAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8cAAIRAAgJ6x0vBQBHAgARAAgJ6x0vBQBHAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAABLgAECn8iAAMdAAgJYRzbGwBuAgAdAAgJYRzbGwBuAgAeAAMJ3BBLKwCaAAAAAA==.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn8cAAIRAAgJ7CF0AwB1AgARAAgJ7CF0AwB1AgAAAA==.Kissmydots:BAABLgAECn8hAAIXAAgJ0hp0BgAMAgAXAAgJ0hp0BgAMAgAAAA==.Kitja:BAAALgAECgYJDwAAAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECggJGAANANUeAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAUJDgAMALEQAA==.Kohman:BAABLgAECn8ZAAIXAAYJ5RS8fABiAQAXAAYJ5RS8fABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kr='Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8HAAIJAAMJYyWUAwBNAQAJAAMJYyWUAwBNAQAuAAQKfxQAAgkACAmPIjcEADcDAAkACAmPIjcEADcDAAAA.Krom:BAABLgAECn8ZAAIdAAcJ4xdDCACcAQAdAAcJ4xdDCACcAQAAAA==.Kronas:BAAALgAECgUJCwAAAA==.Kronophyne:BAABLgAECn8lAAIGAAgJWBzzOgCLAgAGAAgJWBzzOgCLAgAAAA==.Kronotality:BAABLgAECn8jAAIUAAcJFSKnBwCvAgAUAAcJFSKnBwCvAgAAAA==.Kronotek:BAAALgAECgYJBgAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.',
La='Laars:BAAALgAECgEJAQAAAA==.Laimaster:BAAALgADCgYJCwAAAA==.Lakiri:BAABLgAECn8VAAIfAAYJURPJBABdAQAfAAYJURPJBABdAQAAAA==.Landaeda:BAAALgAECgYJCgAAAA==.Lapsu:BAABLgAECn8YAAIgAAgJ5BIVBQCoAQAgAAgJ5BIVBQCoAQAAAA==.Lascivia:BAABLgAECn8eAAMdAAgJ7B1JJgAnAgAdAAYJ3yFJJgAnAgAhAAcJXw5fMADBAAAAAA==.Lawhanx:BAAALgADCgEJAQABLgAECgcJGAAKACcVAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMXAAYJyRcTiQBHAQAXAAUJyRcTiQBHAQAWAAIJxQF3YQBLAAAAAA==.',
Le='Leademon:BAABLgAECn8jAAMKAAcJrR21LQBGAgAKAAcJrR21LQBGAgAJAAIJTRrSWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgcJIwAKAK0dAA==.Leftlane:BAABLgAECn8UAAIOAAYJDSb/AQCMAgAOAAYJDSb/AQCMAgAAAA==.Legato:BAAALgAECgEJAQABLgAFFAUJEAAOAIocAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8YAAINAAgJ1R4hBABRAgANAAgJ1R4hBABRAgAAAA==.',
Li='Liberté:BAAALgADCgcJBwAAAA==.Lie:BAABLgAECn8bAAISAAgJ/RFrCgAtAQASAAgJ/RFrCgAtAQAAAA==.Lightsdown:BAAALgADCgcJDgAAAA==.Lilbeebs:BAAALgAECgkJDAAAAA==.Lileth:BAAALgAECgcJAQAAAA==.Lilflea:BAAALgAECgcJCgAAAA==.Lilzuki:BAAALgAECgYJCQAAAA==.Lilïth:BAACLgAFFH8IAAIUAAQJ/Rw7BAD6AAAUAAQJ/Rw7BAD6AAAuAAQKfxYAAhQABwmDJPAGAMICABQABwmDJPAGAMICAAAA.Linguine:BAAALgAECgEJAQABLgAECggJIQABAAIeAA==.Lisalisa:BAAALgAECgUJEgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAGAEEcAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAAALgAECgUJCgAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Magicmoo:BAAALgAECgEJAQABLgAECggJHAARAOwhAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAABLgAECn8fAAIMAAgJxAt3CQBXAQAMAAgJxAt3CQBXAQAAAA==.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Markamanimal:BAACLgAFFH8GAAIYAAMJXxNrAQD9AAAYAAMJXxNrAQD9AAAuAAQKfx0AAhgACAmFH4YDAPwCABgACAmFH4YDAPwCAAAA.Marnix:BAAALgAECgYJCgAAAA==.',
Me='Medikus:BAABLgAECn8WAAIOAAYJ4B9uBQAMAgAOAAYJ4B9uBQAMAgAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Menil:BAAALgAECgcJEwAAAA==.Merryl:BAAALgAECgYJBgAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAEBLgAECn8iAAMGAAcJkR94GgB2AQAGAAcJkR94GgB2AQAiAAEJAADoDABcAAAAAA==.',
Mo='Mockra:BAABLgAECn8hAAMGAAgJRB4zBwA4AgAGAAgJRB4zBwA4AgAjAAIJuBirGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moolou:BAABLgAECn8bAAIkAAYJGR/BDAD7AQAkAAYJGR/BDAD7AQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAYJFAARALEWAA==.Moraei:BAAALgADCgEJAQAAAA==.Morechie:BAABLgAECn8WAAIlAAYJXhE2AgBOAQAlAAYJXhE2AgBOAQAAAA==.Mortiferon:BAABLgAECn8eAAIIAAgJORmvDAC7AQAIAAgJORmvDAC7AQAAAA==.',
Mu='Muhgunguh:BAAALgADCgYJBgAAAA==.Munnky:BAAALgAECgYJCwAAAA==.',
My='Mythrandere:BAAALgADCgUJBQAAAA==.',
['Má']='Mánflu:BAABLgAECn8lAAMeAAgJgx8SAwDiAgAeAAgJgx8SAwDiAgAdAAcJSRpONADZAQAAAA==.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgADCgUJBQAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgADCgEJAQABLgAFFAQJBQAOAHQMAA==.Narn:BAABLgAECn8jAAQmAAcJwRvQCQBCAgAmAAcJrRjQCQBCAgAaAAQJDA4xQgDaAAAZAAIJLQiDQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgcJBgAAAA==.Necrotion:BAAALgAECgYJDgAAAA==.Nerrisa:BAABLgAECn8bAAICAAcJjBIHIwC/AQACAAcJjBIHIwC/AQAAAA==.Nertt:BAAALgADCgYJBgABLgAECggJIQAmAFkdAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgADCgUJBQAAAA==.',
No='Noblewarrior:BAACLgAFFH8KAAIdAAQJcBNZAgBeAQAdAAQJcBNZAgBeAQAuAAQKfyQAAh0ACAmcJIwAANICAB0ACAmcJIwAANICAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nooj:BAACLgAFFH8aAAMFAAYJ2SASAABxAgAFAAYJ2SASAABxAgASAAYJdBQ4AADcAQAuAAQKfx4AAwUACQl/ITkAAMMDAAUACQl/ITkAAMMDABIABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8OAAIMAAUJsRC5BAAUAQAMAAUJsRC5BAAUAQAuAAQKfyEAAgwACAmuIlANAMUCAAwACAmuIlANAMUCAAAA.Nothnx:BAAALgAECgEJAgAAAA==.Notoriouspat:BAAALgAECgQJDgAAAA==.Notsamadeath:BAAALgAECgQJBAAAAA==.Noydin:BAAALgAECgQJBAAAAA==.',
['Nü']='Nüll:BAAALgADCgIJAgAAAA==.',
Ob='Obern:BAAALgAECggJDQAAAA==.Oblïna:BAAALgAECgQJCgAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgIJBAAAAA==.',
On='Onetozerosix:BAAALgAECgkJEgAAAA==.',
Oo='Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Operation:BAAALgAECgQJBwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgADCgIJAgAAAA==.Pairadeez:BAAALgAECgEJAQAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Panterarey:BAAALgADCgYJCwAAAA==.Papalego:BAAALgAECgYJEAAAAA==.Parakka:BAABLgAECn8UAAIOAAgJcgzzCwB+AQAOAAgJcgzzCwB+AQAAAA==.Pavle:BAAALgADCgUJBQAAAA==.Pawp:BAAALgAECgQJBAABLgAECgcJFwABAGkRAA==.',
Pe='Pepsidew:BAAALgADCgcJCwAAAA==.Pepsisprite:BAAALgAECgYJCwAAAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAAALgAECgYJCAABLgAFFAQJCAAUAP0cAA==.Phlemm:BAAALgADCgcJFwAAAA==.Phoivos:BAABLgAECn8VAAIGAAkJQRwGIQDvAgAGAAkJQRwGIQDvAgAAAA==.',
Pi='Picklez:BAAALgAECgUJCwAAAA==.Pissflizzle:BAAALgAECgYJCgAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAAALgAECgUJCgAAAA==.',
Pr='Praye:BAAALgADCgUJBQAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgADCggJCAABLgAECgMJBAAHAAAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAAALgAECgQJBgAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgMJCQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razzberry:BAAALgADCgQJBAAAAA==.',
Re='Rebrowth:BAAALgAECgUJCAAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECgIJAgAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECggJDQAAAA==.Repete:BAAALgAECgUJCQAAAA==.Resyek:BAABLgAECn8hAAIGAAgJeCKhAwCMAgAGAAgJeCKhAwCMAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAECgQJBAAAAA==.Riivan:BAAALgAECgQJCAAAAA==.Rishi:BAABLgAECn8jAAIRAAcJHxXWXADMAQARAAcJHxXWXADMAQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8aAAIEAAcJ9w51DQAMAQAEAAcJ9w51DQAMAQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJEgABLgAECgcJHQAgAOYfAA==.Sainsei:BAAALgADCgEJAQAAAA==.Saith:BAAALgAECgEJAgAAAA==.Samasear:BAABLgAECn8UAAIdAAgJ0w8tMgDjAQAdAAgJ0w8tMgDjAQABLgAFFAMJCgAIAJEaAA==.Sandwitch:BAABLgAECn8hAAMXAAgJUg+8DwCTAQAXAAgJTQ+8DwCTAQAWAAIJmxBnUwB0AAAAAA==.Sargatana:BAABLgAECn8eAAIQAAgJ1RYnBADjAQAQAAgJ1RYnBADjAQAAAA==.Sars:BAAALgAECgUJCgAAAA==.Sauronxd:BAAALgADCgIJAgAAAA==.',
Sc='Scalion:BAABLgAECn8YAAMKAAcJJxUvSADTAQAKAAcJjBQvSADTAQAJAAQJ+BG6SwDAAAAAAA==.Schrodinger:BAAALgAECgQJBgAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAAALgAECgYJDwAAAA==.',
Sh='Shadowtiger:BAAALgAECgYJDwAAAA==.Shadrad:BAAALgAECggJDgAAAA==.Shamanor:BAEALgAECgcJCAAAAA==.Shammoo:BAAALgAECgEJAQABLgAFFAYJFAARALEWAA==.Shantz:BAAALgAECgYJDgAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAAALgAECggJEwAAAA==.Shortbuss:BAAALgADCgYJDgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJCQAAAA==.Silx:BAABLgAECn8VAAMDAAcJMBFAIQCJAQADAAcJMBFAIQCJAQACAAEJoBY0XQA/AAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.',
Sk='Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slâte:BAAALgAECgUJBQAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.',
So='Somaliabiggs:BAAALgAECgQJBQAAAA==.Sorraba:BAAALgAECgEJAQAAAA==.Soryan:BAAALgAECggJEAAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8HAAIXAAMJ6x5HGQAnAQAXAAMJ6x5HGQAnAQAuAAQKfxwABBcABwk8IycXAMkCABcABwk8IycXAMkCACUAAQkAAO8fAHIAABYAAQm1GjpiAEoAAAAA.',
Sp='Spankenstine:BAAALgAECggJDgABLgABCgYJCwAHAAAAAA==.Spannky:BAAALgADCgYJCgABLgAECgYJCwAHAAAAAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAAALgAECgYJEQAAAA==.Stormcharred:BAABLgAECn8dAAIGAAgJ8R+aKADQAgAGAAgJ8R+aKADQAgAAAA==.Stormknight:BAAALgAECgQJBQAAAA==.Straka:BAABLgAECn8WAAINAAgJIRMUPgCrAQANAAgJIRMUPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdruid:BAAALgADCgUJBQABLgAFFAUJDgARAOEZAA==.Supermonks:BAAALgAECgQJBAABLgAFFAUJDgARAOEZAA==.Superpi:BAAALgAECgYJCAABLgAFFAUJDgARAOEZAA==.Superret:BAACLgAFFH8OAAIRAAUJ4Rm6CQBfAQARAAUJ4Rm6CQBfAQAuAAQKfyEAAhEACAn+IfMOABYDABEACAn+IfMOABYDAAAA.Superskeet:BAABLgAECn8dAAILAAgJkRWYAwBHAgALAAgJkRWYAwBHAgAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAAALgAECgYJEAAAAA==.Swiftybutt:BAAALgAECgQJBgAAAA==.',
Sy='Sylphièl:BAABLgAECn8hAAMFAAgJ6gvrAQCfAQAnAAgJmwqtBAC5AQAFAAgJygnrAQCfAQAAAA==.Synhunt:BAAALgADCgYJBwAAAA==.Synicc:BAAALgAECgEJAQAAAA==.Syrene:BAAALgAECgMJBQAAAA==.',
Ta='Tandarì:BAABLgAECn8cAAIRAAkJSR6oDwARAwARAAkJSR6oDwARAwAAAA==.Tano:BAAALgAECgIJAwABLgAECggJIQAGAEQeAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tasty:BAAALgAECgQJCgAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Taírn:BAAALgAECgYJCgAAAA==.',
Te='Tehpredator:BAAALgAECgIJAwAAAA==.Teilin:BAACLgAFFH8QAAIOAAUJihy2BACEAQAOAAUJihy2BACEAQAuAAQKfyEAAg4ACQkwIrMEACcDAA4ACQkwIrMEACcDAAAA.',
Th='Theaterthug:BAAALgADCgcJDwAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgEJAQABLgADCgcJCwAHAAAAAA==.Theßigshot:BAABLgAECn8VAAINAAYJICO/IgAyAgANAAYJICO/IgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAABLgAECn8iAAMKAAgJox+nAgCHAgAKAAgJch6nAgCHAgAJAAcJWB0LFAAyAgAAAA==.Thundurus:BAABLgAECn8ZAAIPAAgJ/RDIMACbAQAPAAgJ/RDIMACbAQAAAA==.',
Ti='Timmayy:BAABLgAECn8eAAIXAAgJBBZ2OQAmAgAXAAgJBBZ2OQAmAgAAAA==.Tindrill:BAABLgAECn8VAAIeAAgJcB6VAwDKAgAeAAgJcB6VAwDKAgAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAAALgAECgYJEAABLgAECgYJEgAHAAAAAA==.Totemagoat:BAACLgAFFH8HAAMOAAMJAhfjDwDpAAAOAAMJAhfjDwDpAAAPAAEJFAPzDwBAAAAuAAQKfyUAAw4ACAkYE9YsANcBAA4ACAkYE9YsANcBAA8ABgktFNhIACQBAAAA.Totemlyfine:BAABLgAECn8WAAIOAAYJVCDXHQAtAgAOAAYJVCDXHQAtAgAAAA==.Totesmugoats:BAAALgAECggJEQAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJBwAAAA==.Treechains:BAAALgAECgYJDgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAAALgAECgYJEAABLgAECgcJGgANABATAA==.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgIJAgAAAA==.',
Uh='Uhnderstood:BAABLgAECn8hAAIEAAgJkRtpEABWAgAEAAgJkRtpEABWAgAAAA==.',
Un='Undeadmonks:BAABLgAECn8bAAMQAAgJKA4BCgBQAQAQAAgJkQwBCgBQAQAgAAMJdgq1ZQB2AAAAAA==.',
Va='Vahe:BAAALgADCgcJDgAAAA==.Vale:BAAALgADCgEJAQAAAA==.Valeshot:BAABLgAECn8ZAAITAAgJQAlxPwCxAQATAAgJQAlxPwCxAQAAAA==.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgMJAwAAAA==.Valssra:BAAALgAECgYJCwAAAA==.Vampiricvrus:BAAALgAECgIJAwAAAA==.',
Ve='Vedbow:BAABLgAECn8VAAMTAAgJnSIhFACVAgATAAgJrCEhFACVAgAbAAQJ8h8NPABtAQAAAA==.Vedronas:BAAALgAECgcJEQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Vern:BAAALgAECgYJDwAAAA==.Vernah:BAAALgADCgQJBAABLgAECgYJDwAHAAAAAA==.Verybad:BAABLgAECn8oAAIGAAYJpRwqewDbAQAGAAYJpRwqewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgADCgYJBgAAAA==.',
Wa='Waamchifu:BAAALgAECgYJDAAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgQJBAAAAA==.Waltersight:BAAALgAECgQJBQAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgYJCAAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAAALgAECgYJEgAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.',
Yu='Yudah:BAABLgAECn8XAAQTAAgJLgziJQDVAAAbAAUJvQoIWQDhAAATAAcJqAriJQDVAAAoAAIJYQYKKgBgAAAAAA==.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBgAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn8dAAMgAAcJ5h9mAwDmAQAgAAcJ5h9mAwDmAQAEAAEJSRXZZAA+AAAAAA==.Zarinaria:BAABLgAECn8VAAIKAAYJEg7ifQAvAQAKAAYJEg7ifQAvAQAAAA==.',
Zh='Zhael:BAAALgAECgYJDQAAAA==.',
Zo='Zodstrike:BAAALgAECgYJCQAAAA==.Zomara:BAAALgAECgIJBgAAAA==.Zooboo:BAAALgAECgYJDAAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
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

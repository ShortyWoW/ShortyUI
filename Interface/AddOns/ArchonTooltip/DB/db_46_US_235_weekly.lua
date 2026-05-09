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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Mage-Frost','Warlock-Affliction','DemonHunter-Devourer','Shaman-Enhancement','Druid-Guardian','Shaman-Elemental','Mage-Fire','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','DemonHunter-Havoc','Druid-Feral','Monk-Brewmaster','Rogue-Assassination','Priest-Discipline','Monk-Windwalker','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Frost','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Addisyn:BAAALgAECgEJAgAAAA==.',
Ae='Aemetris:BAAALgAECgQJCgAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgEJAgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgAECgMJAwAAAA==.',
Aj='Ajheria:BAAALgADCgcJCAAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anavel:BAAALgADCgUJBQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgADCgMJAwAAAA==.Andari:BAAALgADCgEJAQAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAABLgAECn8yAAMBAAkJwCTzAADoAgABAAgJkiTzAADoAgACAAEJBib3jgBwAAAAAA==.',
Ap='Aponi:BAAALgADCggJIAAAAA==.',
Ar='Ardour:BAAALgAECgMJBgAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8dAAIDAAgJSxYTIQC9AQADAAgJSxYTIQC9AQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAAALgAECgcJEQAAAA==.Asparagus:BAAALgAECgcJEQAAAA==.',
At='Atlass:BAABLgAECn8XAAIEAAcJ8RmCYwDJAQAEAAcJ8RmCYwDJAQAAAA==.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBAABLgAFFAYJFAAFABwYAA==.Aust:BAAALgAECggJDwAAAA==.',
Av='Averlis:BAAALgAECgYJDwAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgYJDQAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8YAAIGAAcJEAh4bQASAQAGAAcJEAh4bQASAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8qAAIHAAgJox9tFQDVAgAHAAgJox9tFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgUJBwAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECgUJBgAAAA==.Beeble:BAAALgAECgMJAwAAAA==.Belii:BAAALgAECgUJBgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJCAAAAA==.',
Bi='Bigbooty:BAAALgAECgQJCwAAAA==.Bigbootyjudi:BAAALgADCgEJAQAAAA==.',
Bl='Blikey:BAAALgAFFAIJBAAAAA==.Bloodyrott:BAAALgAECgQJCQAAAA==.Bluedrake:BAABLgAECn8hAAMIAAgJXx69BAC5AgAIAAgJhh29BAC5AgAJAAgJ+BVKGQADAgABLgAFFAQJCwAKAHAVAA==.Blueparrot:BAABLgAECn8iAAILAAgJaRHjEgDHAQALAAgJaRHjEgDHAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8XAAIMAAgJrhphEQDmAQAMAAgJrhphEQDmAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8QAAMEAAUJ/yABGAB1AQAEAAQJ/yABGAB1AQANAAEJAADgKAAAAAAuAAQKfyAAAwQACQmqIZ4XAO4CAAQACQmqIZ4XAO4CAA0ABAmuE7IiALAAAAAA.Bowkatan:BAAALgAECgEJAQAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIOAAYJUx4yJQD8AQAOAAYJUx4yJQD8AQAAAA==.Bringinlight:BAAALgADCgkJFgAAAA==.',
Bu='Bubbleicious:BAAALgAECgIJAgAAAA==.Bubbletea:BAAALgAECgUJCwABLgAECgkJKQACAIgiAA==.Bulletz:BAABLgAECn8VAAIBAAcJmRquCABzAQABAAcJmRquCABzAQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBAABLgAECgUJBwAPAAAAAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8jAAMDAAcJqw7tNQBAAQADAAcJqw7tNQBAAQAKAAcJdAkvLADnAAAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.',
Ce='Cedrick:BAAALgADCgcJCQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgQJBwAAAA==.Celticsinsix:BAAALgAECgEJAQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn8bAAIQAAYJEA0wfAAZAQAQAAYJEA0wfAAZAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAAALgAECgYJCgAAAA==.Choglana:BAAALgAECgMJAwAAAA==.Chogric:BAABLgAECn8rAAIOAAkJXB+MBQATAwAOAAkJXB+MBQATAwABLgAECgMJAwAPAAAAAA==.',
Ci='Civetta:BAAALgAECgYJDQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBQAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgIJAgAAAA==.Convalesor:BAAALgAECgYJDQAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8GAAIEAAIJJR85OwCmAAAEAAIJJR85OwCmAAAAAA==.Crona:BAABLgAECn8YAAIOAAgJaQ8JPACJAQAOAAgJaQ8JPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8NAAIQAAUJpBPYMABHAQAQAAUJpBPYMABHAQAuAAQKfxcAAhAACAnmH2M5AJACABAACAnmH2M5AJACAAAA.Crzzy:BAAALgAECgQJBwAAAA==.',
Cu='Cuddlez:BAABLgAECn8aAAILAAcJVA2gHwBLAQALAAcJVA2gHwBLAQAAAA==.Cultera:BAAALgAECggJDgAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8fAAIRAAgJDB+lAQBAAgARAAgJDB+lAQBAAgABLgAECgkJNgASALkYAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Danda:BAAALgAECgUJBQAAAA==.Daricepicker:BAABLgAECn8pAAICAAkJiCJOBQA3AwACAAkJiCJOBQA3AwAAAA==.Darkyn:BAABLgAECn8WAAIHAAgJBA9oMQCeAQAHAAgJBA9oMQCeAQAAAA==.Davedadude:BAAALgAECggJEwAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAAALgAFFAEJAQAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIEAAgJ8wvebACwAQAEAAgJ8wvebACwAQAAAA==.Deadscar:BAABLgAECn8rAAITAAkJsyUpAABzAwATAAkJsyUpAABzAwAAAA==.Deathmasterj:BAAALgADCggJCAAAAA==.Deaths:BAAALgAECgUJDwAAAA==.Dedfrosty:BAAALgADCgkJCwAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAPAAAAAA==.Demonio:BAAALgADCgQJBAAAAA==.Demonpimp:BAAALgAECgQJBAAAAA==.Deviously:BAAALgADCgQJBAABLgAECgcJFQABAJkaAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJAwAAAA==.Dithariaa:BAAALgAECgQJBgAAAA==.',
Do='Docryktor:BAABLgAECn8hAAITAAgJCBYlBgDiAQATAAgJCBYlBgDiAQAAAA==.Doomgears:BAAALgAECgQJBgAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Dragonair:BAAALgAECgUJDAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAAALgAECgQJDgAAAA==.Dro:BAAALgAECgQJBwAAAA==.Dropbear:BAAALgAECggJDAAAAA==.Drtybear:BAAALgAECgYJDAAAAA==.Drulissa:BAABLgAECn8XAAIOAAgJuxmXLQDNAQAOAAgJuxmXLQDNAQAAAA==.Druu:BAAALgADCgMJAwABLgAECgcJGwAQACkfAA==.',
Du='Duogear:BAAALgADCgIJAgAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgQJCAAAAA==.',
Ed='Ediana:BAABLgAECn8jAAIQAAcJMgnZbgAzAQAQAAcJMgnZbgAzAQAAAA==.',
El='Elmô:BAABLgAECn8fAAIOAAgJ+x2JBgC1AgAOAAgJ+x2JBgC1AgAAAA==.Elvara:BAAALgAECgQJBwAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8hAAIUAAcJYxekCwDUAQAUAAcJYxekCwDUAQAAAA==.',
Ex='Exash:BAABLgAECn8gAAIVAAgJLSIzCQD/AgAVAAgJLSIzCQD/AgAAAA==.Excizion:BAAALgAECgYJBgAAAA==.',
Fa='Fari:BAAALgADCgEJAQAAAA==.Fathertim:BAAALgAECgQJBgAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAAALgAECgYJEAAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fugryktor:BAAALgAECgUJDAAAAA==.',
Fy='Fyrebug:BAAALgAECgQJCwAAAA==.',
Ga='Galandor:BAAALgAECgQJCQAAAA==.Gandaalf:BAABLgAECn8VAAMWAAcJth3WAQBrAgAWAAcJth3WAQBrAgAQAAIJ4Q9CRgFzAAAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8XAAIXAAgJjgobCwAjAQAXAAgJjgobCwAjAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAYAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIDAAgJRSAHCADMAgADAAgJRSAHCADMAgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityahunter:BAAALgADCgcJBwABLgADCgkJFgAPAAAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn8nAAIGAAgJEB1WFwBAAgAGAAgJEB1WFwBAAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAYJDwAZAMcjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgAECgMJBgAAAA==.Graysurv:BAACLgAFFH8PAAIZAAYJxyMEAACBAgAZAAYJxyMEAACBAgAuAAQKfyIAAhkACQn6JgUAABIEABkACQn6JgUAABIEAAAA.Gromlin:BAAALgAECgMJAwAAAA==.',
['Gä']='Gäreth:BAAALgADCgUJBQAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgADCgIJAgABLgAFFAYJFAAFABwYAA==.Hasalia:BAAALgAECggJCAABLgAECggJFwAOALsZAA==.',
He='Healsforu:BAAALgAECgQJCAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMUAAgJORiHDQAyAQAUAAUJ8RqHDQAyAQAKAAYJAhEyMQDMAAAAAA==.Heunno:BAAALgADCgYJBgABLgADCgcJBwAPAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAABLgAECn8WAAIDAAkJTyO1BQAxAwADAAkJTyO1BQAxAwAAAA==.Highbrittz:BAAALgAECgYJDQAAAA==.',
Ho='Hoakaren:BAABLgAECn8WAAISAAcJ8BWOKACYAQASAAcJ8BWOKACYAQAAAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgMJBAAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAAALgAECgYJDgAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwAPAAAAAA==.',
Il='Illyy:BAABLgAECn8iAAILAAcJcwzpIgAyAQALAAcJcwzpIgAyAQAAAA==.',
In='Indawhole:BAABLgAFFH8RAAISAAYJ9BcOCQCYAQASAAYJ9BcOCQCYAQAAAA==.',
Ir='Iridori:BAABLgAECn8nAAILAAcJWCGCBgCRAgALAAcJWCGCBgCRAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgAECgQJCgAAAA==.',
Ja='Jamerius:BAAALgADCgIJAgAAAA==.Jasmean:BAAALgADCgMJAwAAAA==.Javaluminous:BAABLgAECn8eAAIGAAcJJiBfGwAkAgAGAAcJJiBfGwAkAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJEgAaAEQbAA==.Jaytsukitori:BAACLgAFFH8KAAMDAAQJRB4gDQB0AQADAAQJRB4gDQB0AQAKAAEJgwiCKABGAAAuAAQKfx0AAwMACAmKIbkMANcCAAMACAmKIbkMANcCAAoAAQlmEFdXADQAAAAA.',
Jh='Jhaeriao:BAAALgAECgQJCgAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8RAAIEAAUJ3haVLQBFAQAEAAUJ3haVLQBFAQAAAA==.Jonah:BAAALgAECgUJCAABLgAECggJGAAEAGUjAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIQAAYJUQ5o0ABMAQAQAAYJUQ5o0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAFFAEJAgAPAAAAAA==.Kilrah:BAABLgAECn8rAAIbAAkJOBQCCgDpAQAbAAkJOBQCCgDpAQAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAAALgAECgQJDQAAAA==.Kissmycrits:BAABLgAECn8UAAICAAQJ/BlPSAA0AQACAAQJ/BlPSAA0AQAAAA==.Kiyana:BAABLgAECn8eAAIbAAcJhAukHAD0AAAbAAcJhAukHAD0AAAAAA==.Kiyoine:BAABLgAECn8ZAAIcAAcJAhLqCgBuAQAcAAcJAhLqCgBuAQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8OAAIGAAUJWBieCgBXAQAGAAUJWBieCgBXAQAuAAQKfxcAAgYABwlzIIckAJUCAAYABwlzIIckAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAPAAAAAA==.Knoxreaps:BAAALgAECgIJAgABLgAECgMJBAAPAAAAAA==.Knoxstaggers:BAABLgAECn8eAAIdAAcJiiH2EgB6AgAdAAcJiiH2EgB6AgABLgAECgMJBAAPAAAAAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAAALgAECggJEgAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgUJCwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8eAAIQAAgJMxNhNgDIAQAQAAgJMxNhNgDIAQAAAA==.',
Li='Licht:BAAALgAECgYJCgAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8XAAIeAAgJLwd7CQA1AQAeAAgJLwd7CQA1AQAAAA==.Lit:BAAALgAECgEJAQAAAA==.Littledog:BAABLgAECn8sAAMFAAgJbhfRDgDgAQAFAAgJbhfRDgDgAQAfAAMJHRSrPQC/AAAAAA==.',
Lo='Loky:BAABLgAECn8cAAMHAAkJvR5LPwAQAgAHAAcJvR5LPwAQAgAXAAQJfhjHJAA1AQAAAA==.Longshanks:BAAALgADCgUJDAAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgQJBgAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lunitari:BAAALgADCggJCAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECgcJFgAcAJ0MAA==.',
Ly='Lynnali:BAAALgADCggJFAAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8UAAIQAAcJOhehRwCQAQAQAAcJOhehRwCQAQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Malafang:BAAALgAECgIJAgAAAA==.Malanah:BAAALgAECgQJBQAAAA==.Marandra:BAAALgADCgcJDAAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgADCgkJEgAAAA==.Maverick:BAACLgAFFH8SAAIaAAUJRBvaCgBWAQAaAAUJRBvaCgBWAQAuAAQKfxsAAxoABwlUIsAVAGECABoABwlNIsAVAGECAB4ABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAAALgAECgYJDQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgMJAwABLgAECggJKwAgAAIjAA==.',
Mo='Mogar:BAAALgAECgUJBwAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monster:BAAALgAECgQJBAAAAA==.Moonzhine:BAABLgAECn8eAAINAAgJYxTyDACkAQANAAgJYxTyDACkAQAAAA==.Moosejaw:BAAALgAECgQJBAAAAA==.Mordread:BAAALgADCgcJEwAAAA==.Morgalruk:BAAALgAECgUJCgAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8WAAQCAAYJKR8DAgCBAQACAAUJeR0DAgCBAQAZAAMJkA1FEADyAAABAAIJRRSmFAByAAAuAAQKfyoABAIACAlWI30IAAoDAAIACAlWI30IAAoDABkABQlTGNYaAC4BAAEABQkFEeRMAB4BAAAA.',
Na='Narukin:BAABLgAECn8VAAISAAcJ1BRTKwCKAQASAAcJ1BRTKwCKAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAYJFAAFABwYAA==.',
Ni='Nivmizzet:BAABLgAECn8nAAMHAAcJHRmQJgDOAQAHAAcJzBiQJgDOAQAXAAQJERcqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAABLgAECn8uAAMhAAkJPiIgCQCbAgAhAAkJPiIgCQCbAgAVAAcJwxtZGACNAQAAAA==.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAQAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMYAAgJzxxXCwBYAgAYAAcJgB1XCwBYAgAMAAgJhRoTIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAAALgAFFAQJBAAAAA==.',
Ox='Oxxo:BAAALgAECgQJBgAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAAALgAECgUJDAAAAA==.',
Pe='Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phuriosa:BAAALgAECgQJBAABLgAECggJIQADABsZAA==.Phury:BAABLgAECn8hAAIDAAgJGxkmFQAeAgADAAgJGxkmFQAeAgAAAA==.Physta:BAAALgADCgUJAwAAAA==.',
Pi='Pizza:BAAALgAECgQJBgAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJAwAAAA==.Porkmancer:BAAALgAECgYJCgAAAA==.Porkslope:BAABLgAECn8dAAIEAAcJvR3qKQDUAQAEAAcJvR3qKQDUAQAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgMJBgAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn8bAAMHAAgJ7RmFGAAeAgAHAAgJ7RmFGAAeAgARAAEJAABQLABGAAAAAA==.Raiflock:BAAALgAECgIJAgAAAA==.Ranalastus:BAAALgAECgQJBAAAAA==.Ravenblack:BAAALgAECgEJAQAAAA==.Raveneyes:BAEBLgAECn8eAAIHAAgJDA99NQCPAQAHAAgJDA99NQCPAQAAAA==.',
Re='Reiena:BAAALgAECgYJCQAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8cAAIiAAkJ1xBzFAC4AQAiAAkJ1xBzFAC4AQAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8YAAISAAcJLhHdTwAJAQASAAcJLhHdTwAJAQAAAA==.',
Ri='Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAABLgAECn8dAAIXAAcJjSKmAQBdAgAXAAcJjSKmAQBdAgAAAA==.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMSAAkJgCAMFQDZAgASAAkJgCAMFQDZAgAbAAEJ+RRfaQBAAAAAAA==.Rocksann:BAAALgADCggJDQAAAA==.Rodel:BAAALgAECgEJAQAAAA==.Roquan:BAABLgAECn8nAAIjAAcJXxwjAwDsAQAjAAcJXxwjAwDsAQAAAA==.Roulette:BAAALgAECgQJBAAAAA==.',
Ru='Rubmyrott:BAAALgAECgMJBAAAAA==.Runalot:BAAALgADCgUJBQAAAA==.',
['Rê']='Rêdd:BAAALgAECgUJBwAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Salswarriah:BAAALgAECgQJBwAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottee:BAAALgAECgEJAQABLgAECgUJFQAVAFwTAA==.Scottlee:BAAALgADCgIJBAABLgAECgUJFQAVAFwTAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAPAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtpunchy:BAAALgADCgMJBQABLgAECgQJCAAPAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shamanizim:BAABLgAECn8oAAQVAAcJYB18DgD3AQAVAAcJ4hx8DgD3AQATAAYJWha2CwBQAQAhAAIJJwYwdwBAAAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAECggJFwAOALsZAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAAALgAECggJEQAAAA==.Shinotenshi:BAAALgAECgYJCQABLgAECggJEQAPAAAAAA==.Shirase:BAAALgAECgkJEgABLgAECgkJLgAhAD4iAA==.Shugarae:BAABLgAECn8VAAMKAAcJdQStWADBAAAKAAcJdQStWADBAAADAAUJcASJagB9AAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgYJCgAAAA==.Skuls:BAAALgADCggJCQAAAA==.',
Sl='Slashemup:BAABLgAECn8eAAIbAAgJcxQXDADAAQAbAAgJcxQXDADAAQAAAA==.Slayter:BAABLgAECn8kAAIDAAkJ2B8KDwBiAgADAAkJ2B8KDwBiAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAABLgAECn8WAAIiAAkJlSCpBgDzAgAiAAkJlSCpBgDzAgAAAA==.Snufulafagus:BAAALgAECgQJCQAAAA==.',
So='Soju:BAABLgAECn8UAAMhAAcJ4BGMOAAmAQAhAAcJ4BGMOAAmAQAVAAIJ6xEuSwB2AAABLgAECgkJKQACAIgiAA==.Songwind:BAABLgAECn8UAAIgAAYJ0gOkPACKAAAgAAYJ0gOkPACKAAAAAA==.Soonie:BAAALgADCgEJAQAAAA==.',
Sq='Squishypal:BAAALgAECgUJDQAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAAALgAECgQJCgAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgADCgcJBwAAAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8bAAMCAAcJRx62EwAzAgACAAcJRx62EwAzAgABAAQJ2BPsVgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgADCgkJEQAAAA==.Tentreeadvos:BAAALgADCggJGQABLgAECgQJCAAPAAAAAA==.Tetris:BAABLgAECn8yAAIQAAkJoCKtBQAWAwAQAAkJoCKtBQAWAwAAAA==.',
Th='Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECggJDQAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJDAAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgADCgcJCQABLgAFFAQJCgADAEQeAA==.',
Tr='Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAAALgAECgkJEAAAAA==.Truthfully:BAAALgAECgYJDgAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgQJBAAAAA==.',
Tu='Tuckncloak:BAAALgAECgIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgUJBgAAAA==.',
Uj='Ujabula:BAAALgAECgUJCwAAAA==.',
Ul='Ulurak:BAABLgAECn8WAAMcAAcJnQwYGwAaAQAcAAYJkwkYGwAaAQADAAMJHgnqqgBxAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIkAAcJ0wdzFgBJAQAkAAcJ0wdzFgBJAQAAAA==.Unhappytoast:BAAALgAECgYJDQAAAA==.Unstobubble:BAAALgAECgMJBAAAAA==.',
Va='Valeriya:BAAALgADCgMJAwABLgAECgEJAQAPAAAAAA==.Valisanna:BAAALgADCgUJBQAAAA==.Vallorien:BAAALgAECgQJCwAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJNgASALkYAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velnia:BAAALgAECgYJCgAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgADCgQJCQAAAA==.',
Wa='Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgADCgUJBQAAAA==.',
Wi='Wickedromeo:BAAALgADCgIJBAAAAA==.',
Wo='Wolfmother:BAABLgAECn8VAAIVAAUJXBNSLwD3AAAVAAUJXBNSLwD3AAAAAA==.',
Xa='Xaanii:BAAALgAECgQJCwAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAAALgAECgQJBgAAAA==.',
Xe='Xeeria:BAACLgAFFH8IAAIhAAMJnhKTJADCAAAhAAMJnhKTJADCAAAuAAQKfygAAiEACAliIgsNALUCACEACAliIgsNALUCAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIDAAgJ3xYOLgD1AQADAAgJ3xYOLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgEJAgAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.Zanthor:BAAALgAECgUJEgAAAA==.Zaralina:BAABLgAECn8dAAIFAAkJ7Q3hEwClAQAFAAkJ7Q3hEwClAQAAAA==.Zartox:BAABLgAECn8UAAIlAAYJCReoAwBvAQAlAAYJCReoAwBvAQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zaryssa:BAABLgAECn8UAAIVAAgJlwT6MgDkAAAVAAgJlwT6MgDkAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDQAAAA==.Zephystra:BAAALgADCgQJBAABLgAECgkJLgAhAD4iAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgADCgkJCwAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAAALgAECggJEwAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAAALgAECgYJDQAAAA==.',
['Ût']='Ûthèr:BAAALgADCgEJAQAAAA==.',
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

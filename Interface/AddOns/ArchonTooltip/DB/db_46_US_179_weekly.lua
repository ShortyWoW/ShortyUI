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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Preservation','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Warlock-Demonology','Druid-Guardian','Priest-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Paladin-Holy','Warrior-Arms','Warrior-Fury','Priest-Discipline','Rogue-Subtlety',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECgcJFQABADsfAA==.',
Ae='Aered:BAAALgAECgQJCAAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Ah='Ahira:BAABLgAECn8qAAICAAgJQCI5BwC7AgACAAgJQCI5BwC7AgAAAA==.',
Ak='Akuria:BAABLgAECn8cAAIDAAgJnhJhIgAtAQADAAgJnhJhIgAtAQAAAA==.',
Al='Alahna:BAAALgAECgYJEAAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAABLgAECn8oAAMEAAgJAw6LEQBZAQAEAAgJAw6LEQBZAQAFAAQJSQJT+gCHAAAAAA==.',
Aq='Aquarian:BAAALgAECgYJCwAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Ardgas:BAAALgAECgQJBQABLgAECgcJDgAGAAAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgUJBwAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgADCgUJBAAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgYJBgAAAA==.',
Au='Aureline:BAABLgAECn8kAAIHAAgJpBKULwBjAQAHAAgJpBKULwBjAQAAAA==.Aurna:BAAALgAECgcJDgAAAA==.',
Ba='Babegnome:BAAALgAECgEJAQAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgYJDwAAAA==.',
Be='Beartank:BAAALgADCgYJBgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8LAAIIAAQJVhjNGABnAQAIAAQJVhjNGABnAQAuAAQKf0UAAwgACQn3JN0FAKUDAAgACQn3JN0FAKUDAAkAAQndIaMIAGEAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJGwAIAAoeAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAAALgAECgYJCwAAAA==.Beroldin:BAAALgADCgIJAgABLgAECgYJCwAGAAAAAA==.Bevar:BAAALgADCgIJAgABLgAECgQJBAAGAAAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIKAAYJoB7OJQDVAQAKAAYJoB7OJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAAALgAECgkJDgAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAQAAAA==.Blkrend:BAABLgAECn82AAIEAAkJ9yU9AABuAwAEAAkJ9yU9AABuAwAAAA==.',
Br='Bradycam:BAABLgAECn8kAAILAAgJIBkIIwD5AQALAAgJIBkIIwD5AQAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgIJAQAAAA==.Bruddah:BAAALgAFFAEJAQABLgAFFAMJCgAMAD0KAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJAQAAAA==.Carebeär:BAAALgAECgYJEwAAAA==.Casella:BAABLgAECn82AAIKAAkJQCAtAgD0AgAKAAkJQCAtAgD0AgAAAA==.',
Ce='Celissara:BAAALgAECgUJDwABLgAECgcJDgAGAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCwAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn8XAAILAAYJ1Ba8SwBiAQALAAYJ1Ba8SwBiAQAAAA==.Clouzot:BAAALgADCgMJAwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn8dAAINAAcJQQYBCgD/AAANAAcJQQYBCgD/AAAAAA==.',
Cp='Cptbarnacles:BAAALgAECgYJDgAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAOACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8bAAMFAAgJlRFUNQCkAQAFAAgJ5xBUNQCkAQAPAAgJmgxOBwA6AQAAAA==.Danskan:BAAALgAECgYJCQAAAA==.Darkvale:BAAALgAECgMJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8eAAIQAAgJPhbfCwDmAQAQAAgJPhbfCwDmAQAAAA==.Dashii:BAAALgAECgEJAQAAAA==.Datewoo:BAAALgAECgUJEQAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgAECgQJBAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgMJBQABLgADCgcJJAAGAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Devoroyal:BAAALgAECgcJDQAAAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgQJCAAAAA==.',
Do='Dooda:BAAALgAECgQJCgAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgQJCAAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECgcJFQABADsfAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAAALgAECgUJBQAAAA==.Dracfu:BAABLgAECn8XAAIRAAgJpQfVJgATAQARAAgJpQfVJgATAQAAAA==.Dracserion:BAAALgADCgQJBAABLgAFFAQJCwAIAFYYAA==.Dracsknight:BAAALgAECgUJBwABLgAECggJFwARAKUHAA==.Dracslana:BAAALgAECgUJCgABLgAECggJFwARAKUHAA==.Draffel:BAAALgAECggJEAAAAA==.Drathi:BAAALgAECgYJDwAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drowgon:BAAALgAECgcJDwAAAA==.Druwgon:BAAALgAECgEJAQAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJBQAAAA==.Dukaos:BAACLgAFFH8LAAIOAAQJNQ2cKQALAQAOAAQJNQ2cKQALAQAuAAQKfyQAAw4ABwk9G7MvAD0CAA4ABwk9G7MvAD0CABIABAlCDWUaAMEAAAAA.Dunzer:BAABLgAECn8lAAILAAgJwBijOwA1AgALAAgJwBijOwA1AgAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8YAAIHAAYJ9hskIQC8AQAHAAYJ9hskIQC8AQAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgADCgUJBQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8bAAIIAAgJCh7pOgCLAgAIAAgJCh7pOgCLAgAAAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8YAAITAAkJqh8PBQC6AgATAAkJqh8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgIJAwAAAA==.Emolock:BAAALgAECgUJBQAAAA==.Empressjojo:BAAALgAECgMJBAAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJBgAAAA==.',
Ep='Epiphaný:BAAALgAECgMJBAAAAA==.',
Er='Eradoria:BAAALgAECgYJEQAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgADCgYJBgAAAA==.',
Es='Essylt:BAAALgAECgEJAQAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECgYJBgAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8XAAIUAAgJGAnfDgBTAQAUAAgJGAnfDgBTAQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAGAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJBQABLgAECgYJGAAHAPYbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgIJAwAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJCwAIAFYYAA==.Fenn:BAABLgAECn8jAAIVAAcJkBUBGQCHAQAVAAcJkBUBGQCHAQAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCgAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAABLgAECn8lAAICAAgJ2xl7FwD3AQACAAgJ2xl7FwD3AQAAAA==.',
Fr='Freak:BAABLgAECn8YAAMHAAgJHhLOKACKAQAHAAgJHhLOKACKAQAWAAYJsgkwTQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgQJBQAAAA==.',
Ga='Galerodra:BAAALgADCgEJAQAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgQJCQAAAA==.',
Ge='Gertroz:BAAALgAECgMJBQABLgAECgcJDgAGAAAAAA==.',
Gn='Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8kAAIXAAgJxyIACQCkAgAXAAgJxyIACQCkAgAAAA==.Gope:BAABLgAECn8ZAAMCAAcJ2xgLOwCWAQACAAcJ2xgLOwCWAQAVAAQJ3gZFdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIQAAgJSxcsCQBPAgAQAAgJSxcsCQBPAgAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8lAAMYAAkJPB4DEgCoAgAYAAgJ3R0DEgCoAgAQAAcJDR4cCAAmAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJJQAYADweAA==.Grr:BAABLgAECn8eAAIOAAkJ7RwrEQA3AgAOAAkJ7RwrEQA3AgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gó']='Gójira:BAAALgAECgYJCgAAAA==.',
Ha='Hartis:BAABLgAECn8jAAMXAAgJzRDILgD2AQAXAAgJzRDILgD2AQAYAAQJ5wBaewBWAAAAAA==.Hashmal:BAAALgAECgQJBAAAAA==.Hazo:BAABLgAECn8aAAMKAAYJIAn+PgCcAAAKAAUJDwr+PgCcAAAZAAMJqAQSbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgIJAgAAAA==.Heizou:BAAALgAECgEJAQAAAA==.Hellkat:BAAALgAECgQJBgAAAA==.',
Hi='Highbull:BAAALgAECgEJAQAAAA==.',
Ho='Holiblade:BAABLgAECn8nAAILAAgJaAlMWgA8AQALAAgJaAlMWgA8AQAAAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgABLgAECgcJFwACALwSAA==.Hooligun:BAABLgAECn8hAAIVAAgJzA0dHwBVAQAVAAgJzA0dHwBVAQAAAA==.',
Hu='Huntlord:BAAALgADCgcJBwAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAAALgAECggJEgAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8WAAIBAAcJXgu4GQDIAAABAAcJXgu4GQDIAAAAAA==.',
Ij='Ijustshotyou:BAAALgAECgQJDAABLgAECggJLQABAKUYAA==.',
Il='Illyría:BAAALgADCgcJBwAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAECggJIAAaAO4dAA==.Jakob:BAAALgAECgEJAQAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgUJCAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAAALgAECgUJEwAAAA==.Jenanila:BAAALgAECgEJAgAAAA==.',
Ji='Jibbs:BAABLgAECn8eAAMFAAgJxwdIXAAtAQAFAAcJpAhIXAAtAQAEAAEJmALOPgAcAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAGAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJDQAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jollakeratu:BAABLgAECn8dAAIbAAcJzBFKDQA3AQAbAAcJzBFKDQA3AQAAAA==.Jonnygordo:BAAALgAECgUJDAAAAA==.Jorahh:BAAALgAECgcJEgAAAA==.',
Ju='Jugram:BAAALgADCgkJHAAAAA==.Jusmissiner:BAABLgAECn8eAAIXAAgJ8h5yFgCEAgAXAAgJ8h5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8WAAIEAAgJShijFgCrAQAEAAgJShijFgCrAQAAAA==.',
['Jø']='Jønty:BAAALgADCgUJCAAAAA==.',
Ka='Kaelyra:BAAALgADCgUJCAAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJJQACAKkcAA==.',
Ke='Keelhorn:BAABLgAECn8iAAICAAkJGRTpFwDzAQACAAkJGRTpFwDzAQAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJBQAWAKoOAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAAALgAECgUJDgAAAA==.Kinkyhawt:BAEALgAECgYJEgAAAA==.Kirio:BAAALgADCgcJBwAAAA==.Kitsunenohi:BAAALgAECgcJEQAAAA==.',
Ko='Kodiakk:BAAALgAECgYJEgAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Kramden:BAAALgADCgYJBwAAAA==.Krattos:BAAALgAECgIJAwAAAA==.Krimzin:BAAALgADCgYJBgABLgAFFAQJCQAXAD8bAA==.',
Ku='Kuddles:BAAALgADCgEJAwAAAA==.Kural:BAAALgAECgUJBgABLgAECggJJgABALwiAA==.',
Kw='Kwazii:BAABLgAECn8YAAMcAAcJzxlmJgC5AQAcAAcJzxlmJgC5AQADAAQJVQKOVQBrAAAAAA==.',
Ky='Kyantzmi:BAAALgAECgIJAgAAAA==.Kyogre:BAAALgAECgQJCAAAAA==.',
La='Laefnia:BAAALgAECgYJDgAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAZAD0QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAAALgAECgcJCwAAAA==.Leviosä:BAABLgAECn8jAAIIAAgJTBMPQQCkAQAIAAgJTBMPQQCkAQAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8kAAIFAAkJTCSlAgBIAwAFAAkJTCSlAgBIAwAAAA==.Liten:BAAALgADCgUJCAAAAA==.Littlebev:BAAALgAECgQJBAAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJCgAAAA==.',
['Lí']='Lírii:BAAALgAECgcJEAAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn8sAAMdAAgJLh1YAgAKAgAdAAgJLh1YAgAKAgAeAAcJhBVLGwByAQAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Malaurray:BAAALgAECgYJEwABLgABCgQJBgAGAAAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAAALgAECgkJCQAAAA==.',
Mc='Mckennah:BAABLgAECn8VAAMBAAcJOx99BQAaAgABAAcJOx99BQAaAgALAAEJDgwrAwE2AAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAECgcJIAAIABEVAA==.Mereidith:BAABLgAECn8gAAMIAAcJERWjXABaAQAIAAcJARSjXABaAQAfAAEJchoSGQBPAAAAAA==.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8pAAMgAAgJrgdPLAAuAQAgAAgJrgdPLAAuAQALAAIJyQGfGQEoAAAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJGwAIAAoeAA==.Miriya:BAABLgAECn8jAAIKAAkJyCSVAABZAwAKAAkJyCSVAABZAwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIZAAcJPRBQGwBJAQAZAAcJPRBQGwBJAQAAAA==.Moobáca:BAAALgAECgEJAgAAAA==.Moostradamas:BAABLgAECn8ZAAMPAAcJ/wTBCwDQAAAPAAcJ/wTBCwDQAAAFAAIJsgAcAAEkAAAAAA==.Morcilla:BAAALgAECgUJCgAAAA==.',
Ms='Msg:BAABLgAECn8ZAAIHAAgJtByUDwBbAgAHAAgJtByUDwBbAgAAAA==.',
Mu='Munassa:BAAALgADCgQJBAAAAA==.Muppets:BAAALgAECgUJBgAAAA==.',
My='Myssidia:BAAALgADCgUJCAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nastrodamus:BAAALgADCgYJBgAAAA==.Naturegoob:BAABLgAECn8bAAMHAAgJqBocNADYAQAHAAgJqBocNADYAQAWAAMJ4REINgC1AAAAAA==.Naughtynurse:BAABLgAECn8iAAIHAAkJ1w7dLQBsAQAHAAkJ1w7dLQBsAQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAAALgAECgQJEwAAAA==.',
Ni='Nicfurry:BAAALgADCgIJAgAAAA==.Nightflower:BAABLgAECn8hAAMfAAkJAQUgDwDRAAAIAAcJqwTJfQAWAQAfAAYJAwQgDwDRAAAAAA==.',
No='Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJCgABLgAECgYJDQAGAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn82AAILAAkJ6CDsAwAVAwALAAkJ6CDsAwAVAwAAAA==.Obietide:BAAALgAECgYJCAABLgAECgkJNgALAOggAA==.',
Od='Oddball:BAABLgAECn8cAAIVAAgJgRzSDAAPAgAVAAgJgRzSDAAPAgAAAA==.',
Of='Ofthecircle:BAAALgAECgcJCgAAAA==.',
Ok='Okamiblooded:BAAALgADCgYJDQAAAA==.',
Ol='Olly:BAAALgADCgQJBAAAAA==.',
Oo='Oodles:BAAALgAECgYJEQAAAA==.',
Or='Orangekeg:BAAALgAECgUJEQABLgAECgcJFQAVAPQfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgMJBAAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn8kAAIEAAkJ+xsnBAB+AgAEAAkJ+xsnBAB+AgABLgAECggJJgABALwiAA==.Peso:BAAALgADCgUJAwAAAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8GAAIRAAQJQQzhEgABAQARAAQJQQzhEgABAQABLgAFFAQJCAAgAGESAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIIAAgJOQlcVgBpAQAIAAgJOQlcVgBpAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECggJJwACACUiAA==.',
Pr='Primafox:BAAALgAECgQJCgAAAA==.Prkchopxpres:BAAALgAECgYJDQAAAA==.Protoheal:BAAALgADCgEJAQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBQAAAA==.',
['Pä']='Päw:BAABLgAECn8YAAIFAAgJ8xRIJwDiAQAFAAgJ8xRIJwDiAQAAAA==.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Radge:BAABLgAECn8lAAMhAAgJjiG8AgCOAgAhAAgJVSG8AgCOAgAiAAMJKR0idgDiAAAAAA==.Rainjar:BAABLgAECn81AAMQAAkJzCGoAQD0AgAQAAkJXB+oAQD0AgAXAAgJAiLrCAClAgAAAA==.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8dAAIBAAgJxx0iCwAaAgABAAgJxx0iCwAaAgAAAA==.Ralanar:BAAALgAECgEJAQABLgAECgcJDgAGAAAAAA==.Raljah:BAABLgAECn8qAAQdAAgJJiRyAADaAgAdAAcJJiRyAADaAgAaAAcJjR5qDwBsAgAeAAUJFh18FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAAALgAECgYJEQAAAA==.Rasaltghul:BAAALgADCgQJBAABLgAECgMJBgAGAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJAQAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAAALgAECgcJCgAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8MAAIjAAMJLhd5FgD6AAAjAAMJLhd5FgD6AAAuAAQKfxUAAyMACAmMGUwRAC4CACMACAmMGUwRAC4CAAMAAQk4FcdNAD4AAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJCAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn8cAAMXAAgJxROTIQDTAQAXAAgJSROTIQDTAQAYAAcJdgkIDgALAQAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJCAAAAA==.',
Sa='Sachaann:BAAALgAECgEJAQAAAA==.Salinan:BAABLgAECn82AAMdAAkJliQjAABAAwAdAAkJliQjAABAAwAaAAQJqBcPdgDcAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgcJGQAkADEYAA==.Saric:BAAALgADCgMJAwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAAALgAECgcJEAAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAAALgAECgYJDgAAAA==.',
Sh='Shak:BAAALgAECgYJCAAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgEJAQABLgAECggJLAAdAC4dAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgADCgcJFAAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8VAAIDAAcJJAnpIwAjAQADAAcJJAnpIwAjAQAAAA==.',
Sk='Skilltotem:BAAALgAECggJDwAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgQJCQAAAA==.Skullyy:BAAALgAECgIJBAABLgAECgYJDQAGAAAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8WAAIWAAcJlw7eKAD7AAAWAAcJlw7eKAD7AAAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgEJAQABLgAECgcJFgAWAJcOAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgADCgkJCQAAAA==.Soulsrequiem:BAAALgAECgYJCwAAAA==.',
Sp='Spookydeath:BAACLgAFFH8GAAIIAAMJcQfNUQDbAAAIAAMJcQfNUQDbAAAuAAQKfyQAAggACQkyDvAsAO0BAAgACQkyDvAsAO0BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8VAAILAAUJ0xPcXAA2AQALAAUJ0xPcXAA2AQAAAA==.',
St='Stileto:BAAALgAECgYJCgAAAA==.Stoneydracco:BAAALgAECgYJDQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgQJCAAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAABLgAECn8eAAILAAgJxg00QACFAQALAAgJxg00QACFAQAAAA==.Supervicious:BAAALgAECggJEgAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgUJCAAAAA==.Sylenne:BAABLgAECn8kAAIHAAkJ/RXeEABLAgAHAAkJ/RXeEABLAgAAAA==.Sylur:BAAALgAECgQJBQABLgAECgYJGAAHAPYbAA==.',
Ta='Taemea:BAAALgAECggJEQAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAQJDQAjABAYAA==.Tahren:BAACLgAFFH8NAAMjAAQJEBgqEQA+AQAjAAQJFBQqEQA+AQAcAAEJvCU3GgBtAAAuAAQKfx0ABBwACAltIHIQAGECABwABwn0IHIQAGECACMABQleE1QrAEABAAMABAlGB+JQAIkAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Talerion:BAAALgAECgYJEAAAAA==.',
Te='Tens:BAABLgAECn8bAAIiAAgJJiNVDAD1AgAiAAgJJiNVDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgQJCAAAAA==.Theafflictor:BAAALgAECgQJBAAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgQJCAAGAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn8cAAIZAAcJ3QU1KADvAAAZAAcJ3QU1KADvAAAAAA==.Thrallsux:BAAALgAECgEJAQAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8jAAILAAgJzxGlagCpAQALAAgJzxGlagCpAQAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMRAAYJxxvdEQDXAQARAAYJxxvdEQDXAQAZAAQJqg+QTQDbAAAAAA==.Tokidormi:BAAALgADCgcJCgAAAA==.Toralus:BAAALgADCgYJCQAAAA==.',
Tr='Tremmørs:BAABLgAECn8XAAIVAAcJ0wuBKgAQAQAVAAcJ0wuBKgAQAQAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAECgcJCwAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgUJCAAAAA==.',
Um='Umbrarogue:BAAALgAECggJEgAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8UAAILAAkJOg4GcgCYAQALAAkJOg4GcgCYAQAAAA==.Vellestrix:BAAALgAECgIJAgAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Viddysouls:BAAALgAECgUJEgAAAA==.Viscerai:BAABLgAECn8nAAIcAAgJDib1AABxAwAcAAgJDib1AABxAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgIJAgAAAA==.',
Vo='Vonmiller:BAABLgAECn8YAAMdAAcJ+RVABgD5AQAdAAcJ+RVABgD5AQAaAAIJEgzw+wBiAAAAAA==.Vozluz:BAAALgAECgEJAQABLgAECggJLAAdAC4dAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJFgAWAJcOAA==.',
['Væ']='Væda:BAAALgADCgQJBAAAAA==.',
Wa='Wanted:BAABLgAECn8ZAAIkAAcJMRjdDQDEAQAkAAcJMRjdDQDEAQAAAA==.Warfaxis:BAAALgAECgMJBAAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAHAB4SAA==.',
Wi='Wiseoldgoob:BAAALgAECgcJCAAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJAwAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAECgcJCwAAAA==.',
Ze='Zenclaw:BAABLgAECn8bAAIRAAcJdAuoIwApAQARAAcJdAuoIwApAQAAAA==.Zencore:BAABLgAECn8VAAIIAAgJdw+oRwCQAQAIAAgJdw+oRwCQAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAIAHcPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAIAHcPAA==.',
Zi='Ziel:BAAALgAECgEJAQABLgAECgkJIwAKAMgkAA==.',
Zo='Zoramite:BAAALgADCgQJAgAAAA==.',
['Ñö']='Ñövä:BAAALgADCgMJBAAAAA==.',
['ßu']='ßubba:BAAALgAECgQJCQAAAA==.',
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

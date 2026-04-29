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

local lookup = {'Shaman-Restoration','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Shaman-Elemental','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Windwalker','Paladin-Protection','Warlock-Demonology','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Paladin-Holy','Warrior-Arms','Warrior-Fury','Priest-Discipline','Priest-Holy','Monk-Mistweaver',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgADCgcJDwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgAAAA==.',
Ae='Aered:BAAALgAECgQJBAAAAA==.Aerylith:BAAALgAECgYJBgAAAA==.',
Ah='Ahira:BAABLgAECn8aAAIBAAgJoiBgBAAsAgABAAgJoiBgBAAsAgAAAA==.',
Ak='Akuria:BAABLgAECn8bAAICAAcJ7hGLCQBXAQACAAcJ7hGLCQBXAQAAAA==.',
Al='Alahna:BAAALgAECgUJCQAAAA==.Aleahrose:BAAALgAECgYJDwAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAABLgAECn8WAAMDAAYJLg0rJQAWAQADAAYJLg0rJQAWAQAEAAQJSQIx+gCHAAAAAA==.',
Aq='Aquarian:BAAALgAECgIJBQAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Ardgas:BAAALgAECgQJBQABLgAECgcJDgAFAAAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgMJAwAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgADCgUJBAAAAA==.',
Au='Aureline:BAABLgAECn8aAAIGAAcJmBNKEwAwAQAGAAcJmBNKEwAwAQAAAA==.Aurna:BAAALgAECgcJDgAAAA==.',
Ba='Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgQJBAAAAA==.',
Be='Beartank:BAAALgADCgYJBgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8HAAIHAAQJuhXCGABnAQAHAAQJuhXCGABnAQAuAAQKfzMAAwcACQkJJNcFAKUDAAcACQkJJNcFAKUDAAgAAQm7IT8DAGMAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECggJFwAHAI4dAA==.Bernir:BAAALgADCgIJAgAAAA==.Berol:BAAALgAECgYJCQAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIJAAYJoB7VJQDVAQAJAAYJoB7VJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAAALgAECggJCAAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAQAAAA==.Blkrend:BAABLgAECn8kAAIDAAgJGCZ+AADEAgADAAgJGCZ+AADEAgAAAA==.',
Br='Bradycam:BAABLgAECn8dAAIKAAcJBxs9DgC3AQAKAAcJBxs9DgC3AQAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruddah:BAAALgAECgEJAQABLgAFFAIJAwAFAAAAAA==.',
Ca='Carebeär:BAAALgAECgYJDQAAAA==.Casella:BAABLgAECn8lAAIJAAgJGSA5AQCIAgAJAAgJGSA5AQCIAgAAAA==.',
Ce='Celissara:BAAALgAECgUJDwABLgAECgcJDgAFAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCQAAAA==.Chôsenône:BAAALgAECgQJBAAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAAALgAECgYJEQAAAA==.Clouzot:BAAALgADCgMJAwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAAALgAECgYJEwAAAA==.',
Cp='Cptbarnacles:BAAALgAECgEJAQAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBAAFAAAAAA==.Crunchylock:BAAALgAECgYJCAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAAALgAECgcJDQAAAA==.Danskan:BAAALgAECgIJAgAAAA==.Darkñess:BAAALgAECgYJCgAAAA==.Darmorae:BAAALgAECgcJEwAAAA==.Dashii:BAAALgAECgEJAQAAAA==.Datewoo:BAAALgAECgUJCwAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgADCgQJBAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desertpunk:BAAALgADCggJFAAAAA==.Devoroyal:BAAALgAECgcJDQAAAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgQJBAAAAA==.',
Do='Dooda:BAAALgAECgMJAwAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgQJBAAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECgYJBgAFAAAAAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracfu:BAAALgAECgcJDgAAAA==.Dracsknight:BAAALgAECgMJBAABLgAECgcJDgAFAAAAAA==.Dracslana:BAAALgAECgUJCgABLgAECgcJDgAFAAAAAA==.Draffel:BAAALgADCgEJAQAAAA==.Drathi:BAAALgAECgQJBQAAAA==.Drestla:BAAALgAECgcJCgAAAA==.Drowgon:BAAALgAECgUJBQAAAA==.Druwgon:BAAALgAECgEJAQAAAA==.',
Du='Dukaos:BAACLgAFFH8FAAILAAMJtQt1KQCeAAALAAMJtQt1KQCeAAAuAAQKfx4AAwsABwn1GrgvAD0CAAsABwn1GrgvAD0CAAwABAlCDWMaAMEAAAAA.Dunzer:BAABLgAECn8dAAIKAAgJtxiuOwA1AgAKAAgJtxiuOwA1AgAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAAALgAECgUJEQAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgADCgUJBQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8XAAIHAAgJjh3pOgCLAgAHAAgJjh3pOgCLAgAAAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAAALgAECggJEQAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgADCggJEQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgADCgYJBgAAAA==.',
Ep='Epiphaný:BAAALgAECgMJBAAAAA==.',
Er='Eradoria:BAAALgAECgYJDQAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgADCgYJBgAAAA==.',
Es='Este:BAAALgADCgQJBAAAAA==.',
Ev='Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAAALgAECgcJDwAAAA==.',
Ex='Exidore:BAAALgAECgYJCwAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAFAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgADCgYJBgABLgAECgUJEQAFAAAAAA==.Falfogan:BAAALgAECgEJAQAAAA==.Fangy:BAAALgADCggJDgAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAQABLgAFFAQJBwAHALoVAA==.Fenn:BAABLgAECn8cAAINAAYJBhnDCQBgAQANAAYJBhnDCQBgAQAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJBwAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgQJCAAAAA==.',
Fo='Fonddle:BAAALgADCgUJBQAAAA==.Foxyboo:BAABLgAECn8dAAIBAAgJjhVeIgARAgABAAgJjhVeIgARAgAAAA==.',
Fr='Freak:BAAALgAECggJEgAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.',
Fu='Fulv:BAAALgAECgQJCAABLgAECgUJCgAFAAAAAA==.',
['Fâ']='Fâith:BAAALgADCgMJBAAAAA==.',
Ga='Galerodra:BAAALgADCgEJAQAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgQJBAAAAA==.',
Ge='Gertroz:BAAALgAECgMJBQABLgAECgcJDgAFAAAAAA==.',
Gn='Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8VAAIOAAgJBSFyAgB+AgAOAAgJBSFyAgB+AgAAAA==.Gope:BAAALgAECgcJEgAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIPAAgJSxcqCQBPAgAPAAgJSxcqCQBPAgAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8eAAMQAAgJph5KEgCiAgAQAAgJ3B1KEgCiAgAPAAUJYxGaCQAIAQAAAA==.Grr:BAABLgAECn8dAAILAAgJ4h0LCADyAQALAAgJ4h0LCADyAQAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gó']='Gójira:BAAALgAECgQJBAAAAA==.',
Ha='Hartis:BAABLgAECn8UAAMOAAgJyQ7KLgD2AQAOAAgJyQ7KLgD2AQAQAAQJ5wBNewBWAAAAAA==.Hazo:BAABLgAECn8VAAMJAAYJTgfRXgDHAAAJAAUJyQfRXgDHAAARAAMJqAQJbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Heizou:BAAALgADCgIJAgAAAA==.Hellkat:BAAALgAECgQJBAAAAA==.',
Hi='Highbull:BAAALgADCgIJAgAAAA==.',
Ho='Holiblade:BAABLgAECn8XAAIKAAcJ3whALQDpAAAKAAcJ3whALQDpAAAAAA==.Holyhannah:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJBAAAAA==.Hooligun:BAAALgAECgYJEgAAAA==.',
Hu='Huntlord:BAAALgADCgcJBwAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAAALgAECgYJDwAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAAALgAECgYJDgAAAA==.',
Ij='Ijustshotyou:BAAALgAECgQJCgABLgAECgcJHAASAIsXAA==.',
Il='Illyría:BAAALgADCgcJBwAAAA==.',
Ir='Ironlotss:BAAALgADCgYJCQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAECggJFgATABwaAA==.Jakob:BAAALgADCgMJAwAAAA==.Jardal:BAAALgADCgMJAwAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAAALgAECgQJCgAAAA==.Jenanila:BAAALgADCgcJCwAAAA==.',
Ji='Jibbs:BAABLgAECn8VAAIEAAYJAwiSJgD5AAAEAAYJAwiSJgD5AAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAFAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJCAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jollakeratu:BAAALgAECgYJEwAAAA==.Jonnygordo:BAAALgAECgQJAwAAAA==.Jorahh:BAAALgAECgUJCgAAAA==.',
Ju='Jugram:BAAALgADCgkJFgAAAA==.Jusmissiner:BAABLgAECn8VAAIOAAcJ/SB0FgCFAgAOAAcJ/SB0FgCFAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAAALgAECgYJEgAAAA==.',
['Jø']='Jønty:BAAALgADCgMJAwAAAA==.',
Ka='Kaelyra:BAAALgADCgMJAwAAAA==.Kamehame:BAAALgAECgYJCQAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECggJHgABACMcAA==.',
Ke='Keelhorn:BAABLgAECn8dAAIBAAgJMhKJDgBXAQABAAgJMhKJDgBXAQAAAA==.Kevin:BAAALgAECgYJDAABLgAECgkJIwAUAKwcAA==.Keyadorath:BAAALgADCgEJAQAAAA==.',
Ki='Kibon:BAAALgAECgQJCQAAAA==.Kinkyhawt:BAEALgAECgYJEgAAAA==.Kirio:BAAALgADCgcJBwAAAA==.Kitsunenohi:BAAALgAECgYJDQAAAA==.',
Ko='Kodiakk:BAAALgAECgQJBgAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAECgIJAwAAAA==.Krimzin:BAAALgADCgYJBgABLgAFFAIJBQAKAFAWAA==.',
Ku='Kuddles:BAAALgADCgEJAgAAAA==.Kural:BAAALgADCgMJBAABLgAECgcJEQAFAAAAAA==.',
Kw='Kwazii:BAAALgAECgcJEgAAAA==.',
Ky='Kyantzmi:BAAALgAECgEJAQAAAA==.Kyogre:BAAALgAECgMJAwAAAA==.',
La='Laefnia:BAAALgAECgYJDQAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJEwAFAAAAAA==.Lavaburstya:BAAALgAECgcJCQAAAA==.',
Le='Leomist:BAAALgAECgUJBgAAAA==.Leviosä:BAABLgAECn8bAAIHAAgJmhKJEgCuAQAHAAgJmhKJEgCuAQAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJFAAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8UAAIEAAgJRyEYFAACAwAEAAgJRyEYFAACAwAAAA==.Liten:BAAALgADCgMJAwAAAA==.Littlebev:BAAALgADCgYJBgAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJBwAAAA==.',
['Lí']='Lírii:BAAALgAECgYJBgAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn8aAAMVAAcJzBghBQAcAgAVAAcJzBghBQAcAgAWAAYJexRSGwByAQAAAA==.Magejackky:BAAALgAECgMJBwAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Malaurray:BAAALgAECgYJDQABLgABCgQJBgAFAAAAAA==.Mavanta:BAAALgADCgkJEQAAAA==.',
Mc='Mckennah:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAECgcJEwAHAAwQAA==.Mereidith:BAABLgAECn8TAAMHAAcJDBDLnwCXAQAHAAcJsw7LnwCXAQAXAAEJchoRGQBPAAAAAA==.Meshulk:BAAALgADCgUJBQAAAA==.Mesohungry:BAABLgAECn8dAAMYAAgJ7Qi/VAAnAQAYAAcJcwe/VAAnAQAKAAEJeAHWZwAQAAAAAA==.',
Mi='Mikehunte:BAAALgADCgkJCgABLgAECggJFwAHAI4dAA==.Miriya:BAABLgAECn8UAAIJAAgJSCSVAwBYAwAJAAgJSCSVAwBYAwAAAA==.',
Mo='Monkeycheese:BAAALgAECgcJEwAAAA==.Moobáca:BAAALgAECgEJAQAAAA==.Moostradamas:BAAALgAECgYJDAAAAA==.Morcilla:BAAALgAECgUJBQAAAA==.',
Ms='Msg:BAAALgAECgcJEwAAAA==.',
Mu='Muppets:BAAALgAECgUJBQAAAA==.',
My='Myssidia:BAAALgADCgMJAwAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgEJAQAAAA==.Nastrodamus:BAAALgADCgUJBQAAAA==.Naturegoob:BAABLgAECn8YAAMGAAgJVxkYNADYAQAGAAgJVxkYNADYAQAUAAMJ1BHxEwDAAAAAAA==.Naughtynurse:BAABLgAECn8bAAIGAAgJ9g4rEwAyAQAGAAgJ9g4rEwAyAQAAAA==.',
Ne='Nemrak:BAAALgAECgMJBAAAAA==.Neuma:BAAALgAECgQJDQAAAA==.',
Ni='Nicfurry:BAAALgADCgIJAgAAAA==.Nightflower:BAAALgAECgcJEwAAAA==.',
No='Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgMJAwAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn8kAAIKAAgJQx5aBgAsAgAKAAgJQx5aBgAsAgAAAA==.Obietide:BAAALgAECgYJCAABLgAECggJJAAKAEMeAA==.',
Od='Oddball:BAAALgAECggJEwAAAA==.',
Of='Ofthecircle:BAAALgAECgQJAQAAAA==.',
Oo='Oodles:BAAALgAECgYJEQAAAA==.',
Or='Orangekeg:BAAALgAECgUJEAABLgAECgYJEgAFAAAAAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgADCgkJGwAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn8YAAIDAAgJEhgqBACYAQADAAgJEhgqBACYAQABLgAECgcJEQAFAAAAAA==.Peso:BAAALgADCgUJAwAAAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAAALgAECgYJCAABLgAFFAMJBgAYAN4VAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAAALgAECggJEgAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgcJGQABAAMhAA==.',
Pr='Primafox:BAAALgAECgMJAwAAAA==.Prkchopxpres:BAAALgAECgYJCQAAAA==.',
Pu='Punchandkick:BAAALgAECgIJBAAAAA==.',
['Pä']='Päw:BAAALgAECgcJCwAAAA==.',
Qu='Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAQAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Radge:BAABLgAECn8dAAMZAAcJvCP9AgDlAgAZAAcJeSP9AgDlAgAaAAMJKR0adgDiAAAAAA==.Rainjar:BAABLgAECn8lAAMOAAgJJCOLAQCsAgAPAAgJvyBuAgAZAwAOAAgJryCLAQCsAgAAAA==.Rainne:BAAALgADCgUJBgAAAA==.Raistyn:BAAALgAECgYJDgAAAA==.Raljah:BAABLgAECn8aAAQTAAcJcR3XCADkAQATAAYJghrXCADkAQAWAAUJFh1/FACnAQAVAAQJTR7pDgBCAQAAAA==.Rampart:BAAALgAECgUJCgAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAAALgAECgIJAgAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEAAAAA==.Renpriest:BAABLgAFFH8GAAIbAAIJMBcfCACmAAAbAAIJMBcfCACmAAAAAA==.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgMJAwAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAAALgAECgYJDAAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJAQAAAA==.',
Sa='Sachaann:BAAALgAECgEJAQAAAA==.Salinan:BAABLgAECn8kAAMVAAgJcSJgAQDhAgAVAAcJUCRgAQDhAgATAAMJaxlDOACXAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgYJEgAFAAAAAA==.Saric:BAAALgADCgMJAwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAAALgAECgYJCgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAAALgAECgQJBAAAAA==.',
Sh='Shak:BAAALgAECgUJBQAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shellingtun:BAAALgAECgUJCAAAAA==.Shyandrial:BAAALgADCgYJCQAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAAALgAECgYJBgAAAA==.',
Sk='Skilltotem:BAAALgAECgYJDQAAAA==.Skk:BAAALgADCggJCAAAAA==.Sksteve:BAAALgAECgQJBAAAAA==.Skullyy:BAAALgAECgEJAgAAAA==.Skychades:BAAALgAECgYJCAAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAAALgAECgYJDgAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgEJAQABLgAECgYJDgAFAAAAAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgADCgEJAQAAAA==.Soulsrequiem:BAAALgADCgkJFgAAAA==.',
Sp='Spookydeath:BAABLgAECn8VAAIHAAcJtgmOtgBzAQAHAAcJtgmOtgBzAQAAAA==.',
Sr='Srsnacksalot:BAAALgAECgUJDgAAAA==.',
St='Stileto:BAAALgAECgYJCgAAAA==.Stoneydracco:BAAALgAECgUJBwAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgQJBAAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAAALgAECgYJDwAAAA==.Supervicious:BAAALgAECgYJDgAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgMJAwAAAA==.Sylenne:BAABLgAECn8UAAIGAAgJoQ0hRwCFAQAGAAgJoQ0hRwCFAQAAAA==.Sylur:BAAALgAECgQJBQABLgAECgUJEQAFAAAAAA==.',
Ta='Taemea:BAAALgAECgYJBwAAAA==.Tahran:BAAALgADCgEJAQABLgAFFAMJBgAbAM8PAA==.Tahren:BAACLgAFFH8GAAIbAAMJzw9/BgDtAAAbAAMJzw9/BgDtAAAuAAQKfxwABBwACAltIG8QAGECABwABwn0IG8QAGECABsABQleE1UrAEABAAIAAwnfBtxQAIkAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Talerion:BAAALgAECgYJEAAAAA==.',
Te='Tens:BAABLgAECn8ZAAIaAAcJZSRdDAD1AgAaAAcJZSRdDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgQJBAAAAA==.Theafflictor:BAAALgAECgQJBAAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgQJBAAFAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAAALgAECgUJEgAAAA==.Thraun:BAAALgAECgYJDAAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8fAAIKAAcJ4BKkagCpAQAKAAcJ4BKkagCpAQAAAA==.',
To='Toki:BAAALgAECgUJDwAAAA==.Toralus:BAAALgADCgYJCQAAAA==.',
Tr='Tremmørs:BAAALgAECgYJDwAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAECgcJCwAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweis:BAAALgADCgMJAwAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEgAAAA==.',
Va='Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAAALgAECggJDgAAAA==.Vellestrix:BAAALgADCgIJAgAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Viddysouls:BAAALgAECgQJCQAAAA==.Viscerai:BAABLgAECn8WAAIcAAcJuyXkAADOAgAcAAcJuyXkAADOAgAAAA==.Vite:BAAALgAECgYJDwAAAA==.',
Vo='Vonmiller:BAABLgAECn8XAAMVAAcJ+RVABgD5AQAVAAcJ+RVABgD5AQATAAIJEgzb+wBiAAAAAA==.Vozluz:BAAALgAECgEJAQABLgAECgcJGgAVAMwYAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgYJDgAFAAAAAA==.',
Wa='Wanted:BAAALgAECgYJEgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECggJEgAFAAAAAA==.',
Wi='Wiseoldgoob:BAAALgAECgEJAQAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAECgQJBgAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAECgQJBgAAAA==.',
Ze='Zenclaw:BAABLgAECn8UAAIdAAYJDAw1DgAAAQAdAAYJDAw1DgAAAQAAAA==.Zencore:BAAALgAECgYJDAAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECgYJDAAFAAAAAA==.Zenlock:BAAALgADCgIJAgABLgAECgYJDAAFAAAAAA==.',
Zi='Ziel:BAAALgADCgQJBgABLgAECggJFAAJAEgkAA==.',
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

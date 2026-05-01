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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Mage-Frost','Mage-Fire','Monk-Brewmaster','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','DemonHunter-Vengeance','Shaman-Enhancement','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Paladin-Protection','Warlock-Demonology','Druid-Guardian','Priest-Holy','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Paladin-Holy','Warrior-Fury','Priest-Discipline','Rogue-Subtlety',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECgYJEgABAAAAAA==.',
Ae='Aered:BAAALgAECgQJBAAAAA==.Aerylith:BAAALgAECgYJDAAAAA==.',
Ah='Ahira:BAABLgAECn8iAAICAAgJJyIWCABqAgACAAgJJyIWCABqAgAAAA==.',
Ak='Akuria:BAABLgAECn8YAAIDAAgJmhCIHQAQAQADAAgJmhCIHQAQAQAAAA==.',
Al='Alahna:BAAALgAECgYJDwAAAA==.Aleahrose:BAAALgAECggJEQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAABLgAECn8eAAMEAAcJuA+LDQA3AQAEAAcJuA+LDQA3AQAFAAQJSQJK+gCHAAAAAA==.',
Aq='Aquarian:BAAALgAECgYJCwAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Ardgas:BAAALgAECgQJBQABLgAECgcJDgABAAAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgUJBwAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgADCgUJBAAAAA==.',
Au='Aureline:BAABLgAECn8iAAIGAAgJ7xE7JwBNAQAGAAgJ7xE7JwBNAQAAAA==.Aurna:BAAALgAECgcJDgAAAA==.',
Ba='Babegnome:BAAALgAECgEJAQAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgUJCQAAAA==.',
Be='Beartank:BAAALgADCgYJBgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8JAAIHAAQJuhXKGABnAQAHAAQJuhXKGABnAQAuAAQKfz0AAwcACQnXJN4FAKUDAAcACQnXJN4FAKUDAAgAAQm7IcQGAGMAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECggJGgAHAAYeAA==.Bernir:BAAALgADCgIJAgAAAA==.Berol:BAAALgAECgYJCwAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAIJAAYJoB7PJQDVAQAJAAYJoB7PJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAAALgAECgkJDgAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAQAAAA==.Blkrend:BAABLgAECn8tAAIEAAkJzyUrAAABAwAEAAkJzyUrAAABAwAAAA==.',
Br='Bradycam:BAABLgAECn8kAAIKAAgJGBm4FgAFAgAKAAgJGBm4FgAFAgAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruddah:BAAALgAECgMJBAABLgAFFAMJBgALADcKAA==.',
Ca='Cadovenia:BAAALgAECgEJAQAAAA==.Carebeär:BAAALgAECgYJDQAAAA==.Casella:BAABLgAECn8uAAIJAAkJgh9RAQDwAgAJAAkJgh9RAQDwAgAAAA==.',
Ce='Celissara:BAAALgAECgUJDwABLgAECgcJDgABAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCwAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAAALgAECgYJEwAAAA==.Clouzot:BAAALgADCgMJAwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn8VAAIMAAYJsgV9CQDeAAAMAAYJsgV9CQDeAAAAAA==.',
Cp='Cptbarnacles:BAAALgAECgUJCQAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwANACMdAA==.Crunchylock:BAAALgAECgYJCQAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8VAAMFAAgJGBHZJACtAQAFAAgJvxDZJACtAQAOAAcJ+QviBgAOAQAAAA==.Danskan:BAAALgAECgQJBAAAAA==.Darkvale:BAAALgADCgEJAQAAAA==.Darkñess:BAAALgAECggJDAAAAA==.Darmorae:BAABLgAECn8aAAIPAAcJXRhaCgC8AQAPAAcJXRhaCgC8AQAAAA==.Dashii:BAAALgAECgEJAQAAAA==.Datewoo:BAAALgAECgUJDwAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgADCgQJBAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgIJAgABLgADCgcJIwABAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Devoroyal:BAAALgAECgcJDQAAAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgQJBAAAAA==.',
Do='Dooda:BAAALgAECgMJBgAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgQJBAAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECgYJEgABAAAAAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracfu:BAABLgAECn8VAAIQAAcJgAjqIwDgAAAQAAcJgAjqIwDgAAAAAA==.Dracsknight:BAAALgAECgMJBAABLgAECgcJFQAQAIAIAA==.Dracslana:BAAALgAECgUJCgABLgAECgcJFQAQAIAIAA==.Draffel:BAAALgAECggJCAAAAA==.Drathi:BAAALgAECgQJCQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drowgon:BAAALgAECgcJCQAAAA==.Druwgon:BAAALgAECgEJAQAAAA==.',
Du='Dukaos:BAACLgAFFH8JAAINAAQJNQ0IGQAPAQANAAQJNQ0IGQAPAQAuAAQKfyQAAw0ABwn1GrgvAD0CAA0ABwn1GrgvAD0CABEABAlCDWMaAMEAAAAA.Dunzer:BAABLgAECn8fAAIKAAgJtBilOwA1AgAKAAgJtBilOwA1AgAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8XAAIGAAYJ8xtaFwDHAQAGAAYJ8xtaFwDHAQAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgADCgUJBQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8aAAIHAAgJBh7uOgCLAgAHAAgJBh7uOgCLAgAAAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8YAAISAAkJrh9ZAgBMAgASAAkJrh9ZAgBMAgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgADCggJEQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.Empressjojo:BAAALgADCgQJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJBgAAAA==.',
Ep='Epiphaný:BAAALgAECgMJBAAAAA==.',
Er='Eradoria:BAAALgAECgYJEQAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgADCgYJBgAAAA==.',
Es='Este:BAAALgADCgQJBAAAAA==.',
Ev='Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAAALgAECgcJDwAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAABAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgADCgYJBgABLgAECgYJFwAGAPMbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgADCggJDgAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAQABLgAFFAQJCQAHALoVAA==.Fenn:BAABLgAECn8jAAITAAcJdxUEEgCPAQATAAcJdxUEEgCPAQAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCQAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAABLgAECn8fAAICAAgJRBdXIgARAgACAAgJRBdXIgARAgAAAA==.',
Fr='Freak:BAABLgAECn8YAAMGAAgJGxLWHACZAQAGAAgJGxLWHACZAQAUAAYJsgkrTQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.',
Fu='Fulv:BAAALgAECgUJDwAAAA==.',
['Fâ']='Fâith:BAAALgAECgMJAwAAAA==.',
Ga='Galerodra:BAAALgADCgEJAQAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgQJCAAAAA==.',
Ge='Gertroz:BAAALgAECgMJBQABLgAECgcJDgABAAAAAA==.',
Gn='Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8cAAIVAAgJKyI6BgCUAgAVAAgJKyI6BgCUAgAAAA==.Gope:BAABLgAECn8WAAMCAAcJLxYMOwCWAQACAAcJLxYMOwCWAQATAAMJPQdOdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIPAAgJSxctCQBPAgAPAAgJSxctCQBPAgAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8lAAMPAAkJPB69BAA2AgAWAAgJ3B1OEgCiAgAPAAcJCx69BAA2AgAAAA==.Grr:BAABLgAECn8eAAINAAkJ9BzoCQA8AgANAAkJ9BzoCQA8AgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gó']='Gójira:BAAALgAECgQJBAAAAA==.',
Ha='Hartis:BAABLgAECn8bAAMVAAgJGRDHLgD2AQAVAAgJGRDHLgD2AQAWAAQJ5wBSewBWAAAAAA==.Hazo:BAABLgAECn8ZAAMJAAYJXgf7NgB/AAAJAAUJ3Qf7NgB/AAAXAAMJqAQPbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Heizou:BAAALgAECgEJAQAAAA==.Hellkat:BAAALgAECgQJBAAAAA==.',
Hi='Highbull:BAAALgADCgIJAgAAAA==.',
Ho='Holiblade:BAABLgAECn8fAAIKAAgJiAjjRAA7AQAKAAgJiAjjRAA7AQAAAA==.Holyhannah:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgABLgAECgcJCgABAAAAAA==.Hooligun:BAABLgAECn8ZAAITAAcJiQ37HgAgAQATAAcJiQ37HgAgAQAAAA==.',
Hu='Huntlord:BAAALgADCgcJBwAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAAALgAECggJEQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAAALgAECgYJEAAAAA==.',
Ij='Ijustshotyou:BAAALgAECgQJCgABLgAECggJJQAYAHcYAA==.',
Il='Illyría:BAAALgADCgcJBwAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAECggJHgAZAIUdAA==.Jakob:BAAALgADCgUJBQAAAA==.Jardal:BAAALgADCgUJCAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAAALgAECgQJDgAAAA==.Jenanila:BAAALgAECgEJAgAAAA==.',
Ji='Jibbs:BAABLgAECn8XAAMFAAcJpwdgYQDkAAAFAAYJqghgYQDkAAAEAAEJmAIAMAAcAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwABAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJCAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jollakeratu:BAABLgAECn8VAAIaAAYJGBBkFwAAAQAaAAYJGBBkFwAAAQAAAA==.Jonnygordo:BAAALgAECgQJAwAAAA==.Jorahh:BAAALgAECgcJDgAAAA==.',
Ju='Jugram:BAAALgADCgkJHAAAAA==.Jusmissiner:BAABLgAECn8cAAIVAAcJ/SB1FgCEAgAVAAcJ/SB1FgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8UAAIEAAcJOxqiFgCrAQAEAAcJOxqiFgCrAQAAAA==.',
['Jø']='Jønty:BAAALgADCgUJCAAAAA==.',
Ka='Kaelyra:BAAALgADCgUJCAAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJJQACAKQcAA==.',
Ke='Keelhorn:BAABLgAECn8hAAICAAgJURT3FADDAQACAAgJURT3FADDAQAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJBQAUAKUOAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAAALgAECgQJCQAAAA==.Kinkyhawt:BAEALgAECgYJEgAAAA==.Kirio:BAAALgADCgcJBwAAAA==.Kitsunenohi:BAAALgAECgYJDwAAAA==.',
Ko='Kodiakk:BAAALgAECgYJDAAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Krattos:BAAALgAECgIJAwAAAA==.Krimzin:BAAALgADCgYJBgABLgAFFAMJBQAVAKcbAA==.',
Ku='Kuddles:BAAALgADCgEJAgAAAA==.Kural:BAAALgAECgEJAQABLgAECggJHgAYAIUiAA==.',
Kw='Kwazii:BAABLgAECn8YAAMbAAcJ0BkLEgCMAQAbAAcJ0BkLEgCMAQADAAQJVQKOVQBrAAAAAA==.',
Ky='Kyantzmi:BAAALgAECgIJAgAAAA==.Kyogre:BAAALgAECgQJBwAAAA==.',
La='Laefnia:BAAALgAECgYJDgAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAXAD0QAA==.Lavaburstya:BAAALgAECgcJCwAAAA==.',
Le='Leomist:BAAALgAECgUJBwAAAA==.Leviosä:BAABLgAECn8jAAIHAAgJTBMJLwCnAQAHAAgJTBMJLwCnAQAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8bAAIFAAgJJCMeFAACAwAFAAgJJCMeFAACAwAAAA==.Liten:BAAALgADCgUJCAAAAA==.Littlebev:BAAALgAECgEJAQAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJCAAAAA==.',
['Lí']='Lírii:BAAALgAECgcJCgAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn8kAAMcAAgJLxoiBQAcAgAcAAgJIRkiBQAcAgAdAAYJIBdQGwByAQAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Malaurray:BAAALgAECgYJEwABLgABCgQJBgABAAAAAA==.Mavanta:BAAALgADCgkJEQAAAA==.Mayonæse:BAAALgAECgkJAwAAAA==.',
Mc='Mckennah:BAAALgAECgYJEgAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAECgcJGQAHAAwQAA==.Mereidith:BAABLgAECn8ZAAMHAAcJDBDAnwCXAQAHAAcJsw7AnwCXAQAeAAEJchoQGQBPAAAAAA==.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8jAAMfAAgJ7Qi+VAAnAQAfAAcJcwe+VAAnAQAKAAIJywHP3gAqAAAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECggJGgAHAAYeAA==.Miriya:BAABLgAECn8aAAIJAAgJgiSYAwBYAwAJAAgJgiSYAwBYAwAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIXAAcJPRAFFABOAQAXAAcJPRAFFABOAQAAAA==.Moobáca:BAAALgAECgEJAgAAAA==.Moostradamas:BAAALgAECgYJEgAAAA==.Morcilla:BAAALgAECgUJCQAAAA==.',
Ms='Msg:BAABLgAECn8VAAIGAAcJCx3GKgAGAgAGAAcJCx3GKgAGAgAAAA==.',
Mu='Muppets:BAAALgAECgUJBQAAAA==.',
My='Myssidia:BAAALgADCgUJCAAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAgAAAA==.Nastrodamus:BAAALgADCgYJBgAAAA==.Naturegoob:BAABLgAECn8ZAAMGAAgJpxofNADYAQAGAAgJpxofNADYAQAUAAMJ1BHyKQC7AAAAAA==.Naughtynurse:BAABLgAECn8iAAIGAAkJ1w44IQB3AQAGAAkJ1w44IQB3AQAAAA==.',
Ne='Nemrak:BAAALgAECgMJBAAAAA==.Neuma:BAAALgAECgQJDQAAAA==.',
Ni='Nicfurry:BAAALgADCgIJAgAAAA==.Nightflower:BAABLgAECn8bAAMeAAgJLQUiDwDRAAAHAAYJ3wS9fADbAAAeAAYJAwQiDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJBgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDQAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn8tAAIKAAkJiR5AAwDyAgAKAAkJiR5AAwDyAgAAAA==.Obietide:BAAALgAECgYJCAABLgAECgkJLQAKAIkeAA==.',
Od='Oddball:BAABLgAECn8bAAITAAgJgRzMCAASAgATAAgJgRzMCAASAgAAAA==.',
Of='Ofthecircle:BAAALgAECgUJBgAAAA==.',
Ol='Olly:BAAALgADCgQJBAAAAA==.',
Oo='Oodles:BAAALgAECgYJEQAAAA==.',
Or='Orangekeg:BAAALgAECgUJEQABLgAECgcJEwABAAAAAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgEJAQAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn8bAAIEAAgJPxl4BwCoAQAEAAgJPxl4BwCoAQABLgAECggJHgAYAIUiAA==.Peso:BAAALgADCgUJAwAAAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAAALgAFFAIJAgABLgAFFAQJCAAfAGISAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIHAAgJNQl8QABtAQAHAAgJNQl8QABtAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgQJBAABAAAAAA==.',
Pr='Primafox:BAAALgAECgMJBgAAAA==.Prkchopxpres:BAAALgAECgYJDAAAAA==.Protoheal:BAAALgADCgEJAQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBQAAAA==.',
['Pä']='Päw:BAAALgAECggJEgAAAA==.',
Qu='Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Radge:BAABLgAECn8dAAMLAAcJvCMAAwDkAgALAAcJeSMAAwDkAgAgAAMJKR0ddgDiAAAAAA==.Rainjar:BAABLgAECn8sAAMVAAkJqCBXBQCkAgAPAAkJkB5uAgAZAwAVAAgJryBXBQCkAgAAAA==.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8bAAIYAAcJ5x8jCwAaAgAYAAcJ5x8jCwAaAgAAAA==.Raljah:BAABLgAECn8iAAQZAAgJtB5KCQB5AgAZAAcJhx5KCQB5AgAdAAUJFh19FACnAQAcAAQJTR7qDgBCAQAAAA==.Rampart:BAAALgAECgYJEQAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAAALgAECgcJCQAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAABLgAFFH8JAAIhAAMJMxUPEQD5AAAhAAMJMxUPEQD5AAAAAA==.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJCAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn8VAAMWAAgJSA+4CgAkAQAWAAcJdgm4CgAkAQAVAAIJVRruYACnAAAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJBwAAAA==.',
Sa='Sachaann:BAAALgAECgEJAQAAAA==.Salinan:BAABLgAECn8tAAMcAAkJOSIyAADgAgAcAAgJgSQyAADgAgAZAAQJoRe7WQDkAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgcJGQAiADUYAA==.Saric:BAAALgADCgMJAwAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAAALgAECgYJEAAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAAALgAECgQJCAAAAA==.',
Sh='Shak:BAAALgAECgUJBQAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgEJAQABLgAECggJJAAcAC8aAA==.Shellingtun:BAAALgAECgYJCQAAAA==.Shyandrial:BAAALgADCgYJDQAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAAALgAECgYJCwAAAA==.',
Sk='Skilltotem:BAAALgAECggJDwAAAA==.Skk:BAAALgADCggJCAAAAA==.Sksteve:BAAALgAECgQJBQAAAA==.Skullyy:BAAALgAECgEJAwAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAAALgAECgYJEAAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgEJAQABLgAECgYJEAABAAAAAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgADCgEJAQAAAA==.Soulsrequiem:BAAALgAECgUJBQAAAA==.',
Sp='Spookydeath:BAABLgAECn8cAAIHAAcJGg/DQgBmAQAHAAcJGg/DQgBmAQAAAA==.',
Sr='Srsnacksalot:BAAALgAECgUJEgAAAA==.',
St='Stileto:BAAALgAECgYJCgAAAA==.Stoneydracco:BAAALgAECgUJDAAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgQJBAAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAABLgAECn8VAAIKAAYJgAy0WAAGAQAKAAYJgAy0WAAGAQAAAA==.Supervicious:BAAALgAECgcJEAAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgUJCAAAAA==.Sylenne:BAABLgAECn8bAAIGAAgJNhXFGQCyAQAGAAgJNhXFGQCyAQAAAA==.Sylur:BAAALgAECgQJBQABLgAECgYJFwAGAPMbAA==.',
Ta='Taemea:BAAALgAECgYJDgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAMJCQAhAN4VAA==.Tahren:BAACLgAFFH8JAAIhAAMJ3hUOEQD5AAAhAAMJ3hUOEQD5AAAuAAQKfxwABBsACAltIHQQAGECABsABwn0IHQQAGECACEABQleE1QrAEABAAMAAwnfBuNQAIkAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Talerion:BAAALgAECgYJEAAAAA==.',
Te='Tens:BAABLgAECn8bAAIgAAgJJSNcDAD1AgAgAAgJJSNcDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgQJBAAAAA==.Theafflictor:BAAALgAECgQJBAAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgQJBAABAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn8UAAIXAAYJGQQcLgCQAAAXAAYJGQQcLgCQAAAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8hAAIKAAgJzRGjagCpAQAKAAgJzRGjagCpAQAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8VAAMQAAYJfRtsDQDPAQAQAAYJfRtsDQDPAQAXAAQJqg+QTQDbAAAAAA==.Tokidormi:BAAALgADCgMJAwAAAA==.Toralus:BAAALgADCgYJCQAAAA==.',
Tr='Tremmørs:BAAALgAECgkJEwAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAECgcJCwAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweis:BAAALgADCgUJCAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAAALgAECggJEQAAAA==.Vellestrix:BAAALgAECgIJAgAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Viddysouls:BAAALgAECgQJDQAAAA==.Viscerai:BAABLgAECn8fAAIbAAgJwyWeAABkAwAbAAgJwyWeAABkAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.',
Vo='Vonmiller:BAABLgAECn8XAAMcAAcJ+RVABgD5AQAcAAcJ+RVABgD5AQAZAAIJEgzj+wBiAAAAAA==.Vozluz:BAAALgAECgEJAQABLgAECggJJAAcAC8aAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgYJEAABAAAAAA==.',
['Væ']='Væda:BAAALgADCgQJBAAAAA==.',
Wa='Wanted:BAABLgAECn8ZAAIiAAcJNRjGCADgAQAiAAcJNRjGCADgAQAAAA==.Warfaxis:BAAALgAECgMJAwAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECggJGAAGABsSAA==.',
Wi='Wiseoldgoob:BAAALgAECgYJBwAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAECgQJBwAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAECgcJCwAAAA==.',
Ze='Zenclaw:BAABLgAECn8bAAIQAAcJcguQGgAvAQAQAAcJcguQGgAvAQAAAA==.Zencore:BAAALgAECgcJEwAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECgcJEwABAAAAAA==.Zenlock:BAAALgADCgIJAgABLgAECgcJEwABAAAAAA==.',
Zi='Ziel:BAAALgAECgEJAQABLgAECggJGgAJAIIkAA==.',
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

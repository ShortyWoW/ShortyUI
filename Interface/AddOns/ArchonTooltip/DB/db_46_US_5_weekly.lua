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

local lookup = {'Unknown-Unknown','Priest-Holy','Monk-Brewmaster','Druid-Restoration','Mage-Frost','DeathKnight-Unholy','Warrior-Protection','Monk-Mistweaver','Paladin-Holy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Evoker-Devastation','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Evoker-Preservation','Priest-Shadow','Priest-Discipline','Druid-Feral','Shaman-Restoration','Rogue-Outlaw','Druid-Balance','Hunter-Survival','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Shaman-Enhancement',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Accost:BAAALgAECgQJBAAAAA==.',
Ad='Adagar:BAAALgAECgYJBgAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAEJAQAAAA==.Aethandor:BAAALgAECgQJBQAAAA==.',
Ak='Akassa:BAAALgAECgYJBwAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
Al='Alecto:BAAALgAECgcJDwAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amarah:BAABLgAECn8iAAICAAcJ8x6SEABfAgACAAcJ8x6SEABfAgAAAA==.',
An='Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgEJAQABLgAECgkJFQADAJEcAA==.',
Ap='Applemonster:BAAALgADCgQJBAAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argdru:BAAALgAECgYJDQAAAA==.Argrekd:BAAALgADCgMJAwABLgAECgYJDQABAAAAAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arknox:BAAALgAECgcJEQAAAA==.Arthaslk:BAAALgAECgYJBwABLgAECgYJDAABAAAAAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAQJCQAEAHwdAA==.Ashallel:BAAALgAECgQJBAABLgAFFAQJCQAEAHwdAA==.Ashx:BAAALgADCgIJBAABLgAECggJGwAFAA8XAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Atlette:BAACLgAFFH8KAAICAAQJNBzFAQBMAQACAAQJNBzFAQBMAQAuAAQKfyUAAgIACQluH2MCAEUDAAIACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8MAAIGAAQJ0w2kHgAjAQAGAAQJ0w2kHgAjAQAuAAQKfzwAAgYACAnXIcgQABcDAAYACAnXIcgQABcDAAAA.Attman:BAAALgAECgIJAgAAAA==.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgYJCwAAAA==.Ballsofire:BAABLgAECn8VAAIHAAYJIRlDFwCeAQAHAAYJIRlDFwCeAQAAAA==.Basherz:BAAALgAECgMJAwAAAA==.',
Be='Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAAALgAECgQJDAAAAA==.Belithel:BAABLgAECn8bAAIFAAgJDxcLdgDmAQAFAAgJDxcLdgDmAQAAAA==.Bencreepin:BAAALgAECgQJCAAAAA==.Beniz:BAAALgAECgYJCgAAAA==.Bernoulli:BAAALgAECgYJDQAAAA==.',
Bi='Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.Bironic:BAAALgAECgMJBAABLgAECgYJCgABAAAAAA==.',
Bl='Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAYJFQAIAGcZAA==.Bloodymyst:BAABLgAFFH8VAAIIAAYJZxnWAADyAQAIAAYJZxnWAADyAQAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boopsnoopems:BAAALgAECgQJCQAAAA==.',
Br='Briannajade:BAAALgAECgcJEAAAAA==.Brisha:BAACLgAFFH8OAAIJAAQJMB/fBgBoAQAJAAQJMB/fBgBoAQAuAAQKfy4AAwkACQk9JHUAALUDAAkACQk9JHUAALUDAAoAAQkaEkoSADsAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgADCgcJBwAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAECggJIwAGAKwfAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8WAAMLAAgJex27DgDFAgALAAgJex27DgDFAgAMAAYJag3NTwAPAQABLgAECggJIwAGAKwfAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIEAAkJ1yKzAQCJAwAEAAkJ1yKzAQCJAwAAAA==.Cammi:BAAALgAECgYJCAAAAA==.Casare:BAABLgAECn8VAAIMAAYJwwaXXgDHAAAMAAYJwwaXXgDHAAAAAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAAALgAECgIJAgABLgAECgcJGQAFACMUAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chapito:BAAALgAECgQJBAAAAA==.Chipmonked:BAABLgAECn8cAAQNAAgJkQhbDQD6AAANAAYJNQpbDQD6AAAIAAUJIwOsUACSAAADAAIJdwRmHwBPAAAAAA==.Chlop:BAABLgAECn8ZAAIGAAgJahxmHADUAgAGAAgJahxmHADUAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn8UAAIOAAYJ/gYGBQDNAAAOAAYJ/QYGBQDNAAAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECgYJBwAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgYJCwAAAA==.Congdh:BAACLgAFFH8KAAIPAAQJWSJGCAChAQAPAAQJWSJGCAChAQAuAAQKfxoAAg8ACAl4JJ4MABsDAA8ACAl4JJ4MABsDAAAA.Conmann:BAAALgAECgYJCwAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAAAAA==.Crossy:BAAALgAECgQJBQAAAA==.Cryogenic:BAAALgADCgcJCAAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAAALgAECgQJAwAAAA==.',
Da='Daak:BAAALgADCgUJBQABLgAECgYJEgABAAAAAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAABLgAECn8XAAIGAAkJMx1XBgAfAgAGAAkJMx1XBgAfAgAAAA==.Darkacedia:BAABLgAECn8eAAMQAAgJcSEABwACAgAQAAgJcSEABwACAgARAAMJyQ9TQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgADCgMJAwAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAAALgAECgQJCQAAAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAECgMJBQAAAA==.Dealosed:BAABLgAECn8eAAMSAAgJoCDMEQCRAgASAAcJziDMEQCRAgATAAEJjx+ZGQBfAAAAAA==.Decrepit:BAAALgAECgYJDQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diremane:BAAALgAECgIJAgAAAA==.Disastasmite:BAAALgADCgEJAQABLgAECgYJFgAUAGckAA==.Dive:BAABLgAECn8jAAMFAAkJbCELCAAoAgAFAAgJ1CALCAAoAgAVAAUJbRx4CwAfAQAAAA==.',
Dk='Dkeruu:BAAALgAECgQJBAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIDAAkJkRw5DgCxAgADAAkJkRw5DgCxAgAAAA==.Dondozo:BAAALgAECgUJBwAAAA==.Doogru:BAABLgAECn8VAAIWAAgJRgsHCACgAQAWAAgJRgsHCACgAQAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCgAAAA==.Dragoneggs:BAABLgAECn8eAAMXAAkJUR3sCADpAgAXAAkJUR3sCADpAgAYAAcJGQ5iHwCEAQAAAA==.Dragonforce:BAAALgAECgYJDAABLgAECgcJDAABAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8iAAIZAAgJeiL/AACaAgAZAAgJeiL/AACaAgAAAA==.Driipp:BAAALgAECggJCAAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAAALgAECgUJDAAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAIJBQAaAAoEAA==.Duhhellolady:BAAALgAECgEJAQAAAA==.',
Dy='Dyab:BAAALgADCgUJBQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMbAAcJnCFkCwAKAgAbAAYJbiNkCwAKAgAEAAYJKxDXWABIAQAAAA==.',
Ec='Echidona:BAABLgAECn8bAAISAAgJERn+EwB2AgASAAgJERn+EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgYJEQAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAQJCgAQAI4YAA==.',
El='Elenix:BAABLgAECn8aAAMUAAkJyRytCAAGAwAUAAkJyRytCAAGAwAcAAMJhA31gACQAAAAAA==.Elinras:BAAALgAFFAEJAQAAAA==.Elliott:BAAALgADCgMJBQABLgADCggJDQABAAAAAA==.Elrizon:BAAALgAECgIJAQAAAA==.Elvar:BAAALgAECgYJCwABLgAECgQJBQABAAAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAICAAcJ2RUBIADhAQACAAcJ2RUBIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAQAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAABLgAECn8iAAIdAAgJJSHlAAAMAwAdAAgJJSHlAAAMAwAAAA==.',
En='Endboss:BAAALgAECgUJBQAAAA==.Endorsi:BAAALgAECgUJBgAAAA==.Enfuega:BAAALgAECgMJAwAAAA==.Eniar:BAAALgAFFAQJBAAAAA==.',
Er='Eroninja:BAAALgAECgQJBwABLgAECggJGwAFAA8XAA==.',
Eu='Eurong:BAACLgAFFH8IAAIeAAQJExbQBQD6AAAeAAQJExbQBQD6AAAuAAQKfxkAAh4ABwkYIEQaADICAB4ABwkYIEQaADICAAAA.',
Ev='Evangelune:BAAALgAECgMJBQAAAA==.',
Ez='Ezynuff:BAAALgAECgEJAQABLgAECgYJCgABAAAAAA==.',
['Eï']='Eïr:BAAALgADCgUJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAAQAB8fAA==.Fapple:BAAALgAECgEJAQABLgAECgYJFQAYAAoiAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAABLgAECn8jAAMLAAgJVx3LEQCqAgALAAgJVx3LEQCqAgAfAAQJggszIwC2AAAAAA==.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felheart:BAAALgAECgUJBQAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgUJDAABAAAAAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAAALgAECgMJBgAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgMJAwAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8cAAMYAAgJCg5qJABVAQAYAAcJJQxqJABVAQAXAAgJ+AjICQBJAQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgYJFQAHACEZAA==.',
Fr='Fries:BAEBLgAECn8VAAMQAAgJKB8aCADwAQAQAAgJKB8aCADwAQARAAEJhxoRYABPAAAAAA==.Frozenpyre:BAAALgAECgYJDAAAAA==.',
Fu='Funch:BAABLgAECn8hAAIRAAgJ1xMXAQDMAQARAAgJ1xMXAQDMAQAAAA==.',
['Fè']='Fènrir:BAAALgADCgIJAgAAAA==.',
Ga='Gainzbrew:BAAALgADCgYJCQAAAA==.Gainzz:BAAALgAECgMJAwAAAA==.Galesdeyn:BAAALgAECgEJAQAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAFAD4dAA==.Garonnaa:BAAALgAFFAEJAQAAAA==.',
Gh='Ghari:BAAALgAECgcJDwAAAA==.',
Gi='Gilrog:BAAALgAECgUJDAAAAA==.Gingerlock:BAAALgAECgUJBgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.Glizzyghost:BAAALgADCgYJBgABLgAECgcJHgAgAAMgAA==.',
Gn='Gnoblin:BAAALgAECgQJBgAAAA==.Gnzz:BAAALgAECgcJCQAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAAALgAECgIJAwAAAA==.Greylooms:BAAALgAECgcJEwAAAA==.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8FAAMaAAIJCgTLFQCFAAAaAAIJCgTLFQCFAAAZAAEJZAD9DAA2AAAuAAQKfx4AAxkACAlQEHUkALQBABkABwmiEXUkALQBABoACAkJENUdAKYBAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgIJAgAAAA==.Hermitpurple:BAAALgADCgcJEwAAAA==.Heàl:BAAALgAECgQJBgAAAA==.',
Hi='Hidejames:BAAALgADCgkJFgAAAA==.Hims:BAAALgAECgYJEwABLgAFFAYJFgAXAF4kAA==.',
Ho='Hoguy:BAAALgAECgYJDAAAAA==.Holofox:BAACLgAFFH8NAAIEAAQJZR1BBABJAQAEAAQJZR1BBABJAQAuAAQKfyYAAgQACAm7JE0BAOYCAAQACAm7JE0BAOYCAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Horman:BAAALgAECgYJDQAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJCgABAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgQJBAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQAAAA==.',
Ic='Iclapu:BAAALgADCgIJAgAAAA==.',
Ig='Igosduikanna:BAAALgADCgQJAwAAAA==.',
Ik='Ikerous:BAABLgAECn8ZAAMhAAcJ8BoyBwAWAgAhAAcJ8BoyBwAWAgAiAAMJ1AmOVgCNAAAAAA==.',
Il='Ilililililli:BAAALgAECgYJEAAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIUAAcJrR6DEgCOAgAUAAcJrR6DEgCOAgAAAA==.Imhammered:BAAALgAECgQJCAAAAA==.Impullse:BAAALgAECgMJAwAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAECggJIQAXAPgfAA==.',
It='Ithilwen:BAABLgAECn8eAAIaAAgJuR4eDQBnAgAaAAgJuR4eDQBnAgAAAA==.Itiswhatitiz:BAAALgAECgYJEQAAAA==.Itsybityshiv:BAABLgAECn8gAAMSAAgJoxazAgAFAgASAAgJoxazAgAFAgATAAEJoBjtHwAzAAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jahq:BAABLgAECn8VAAIPAAYJAyF4NAAnAgAPAAYJAyF4NAAnAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.',
Jh='Jhani:BAAALgAECgYJCgAAAA==.',
Ji='Jinu:BAAALgAECgYJCwAAAA==.Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8cAAIFAAgJTxrmDADlAQAFAAgJTxrmDADlAQAAAA==.Jormojo:BAAALgAECgEJAQAAAA==.Jotwnky:BAABLgAECn8eAAQgAAcJAyC3BQAMAgAgAAUJSSO3BQAMAgARAAQJsxo7IwA+AQAQAAMJFR80uADoAAAAAA==.',
Ju='Jungol:BAAALgADCgkJDgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaltank:BAAALgAECgMJAwAAAA==.Kamin:BAABLgAECn8jAAIHAAgJwiHeAwARAwAHAAgJwiHeAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAAALgAECgcJDgAAAA==.Kaykaypally:BAABLgAECn8UAAIjAAYJwheNFgBrAQAjAAYJwheNFgBrAQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAQJCgAQAI4YAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8dAAIjAAcJbRv0DADGAQAjAAcJbRv0DADGAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAQABAAAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8dAAIJAAgJZSL1AADdAgAJAAgJZSL1AADdAgAAAA==.Kidori:BAAALgAECgEJAQABLgAECggJHQAJAGUiAA==.Kilgharra:BAAALgADCgUJAQAAAA==.Kinji:BAAALgADCgYJCAABLgAECggJGwAFAA8XAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koriandar:BAAALgAECgUJBQAAAA==.',
Kr='Kristysavage:BAABLgAECn8ZAAIfAAYJbB8EBACyAQAfAAYJbB8EBACyAQAAAA==.Krul:BAAALgADCgkJCgAAAA==.',
Ku='Kulaesca:BAAALgADCgkJDgAAAA==.',
Ky='Kynar:BAACLgAFFH8QAAMGAAUJ1hpQBQBjAQAGAAQJ1hpQBQBjAQAkAAEJAABcEQBnAAAuAAQKfxcAAgYACAkuH6E/ADoCAAYACAkuH6E/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyua:BAAALgAECgQJBQAAAA==.',
La='Lambshot:BAAALgAECgYJEAAAAA==.Lambsy:BAACLgAFFH8XAAMWAAYJnRo/AACwAQAWAAYJnRo/AACwAQAlAAEJLwBCDgAgAAAuAAQKfxgAAxYACAmnIBYRAMgCABYACAl1HhYRAMgCACUAAQnuIzk5AEsAAAAA.Landwhalexxl:BAABLgAECn8UAAIFAAcJuxGQpACPAQAFAAcJuxGQpACPAQAAAA==.Laneera:BAAALgAECgQJBAAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8jAAIOAAgJSyFHAACEAgAOAAgJSyFHAACEAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Lightofhope:BAAALgAECgcJEAAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgAAAA==.Lilyy:BAAALgAECgYJEQAAAA==.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAAALgAECgUJCwAAAA==.Liulei:BAAALgAECgQJAwAAAA==.',
Lo='Loraen:BAAALgAECgIJAgAAAA==.Lorelei:BAAALgAECgEJAQABLgAECggJHQAlANgbAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lunarmon:BAAALgAECgQJCgAAAA==.Lunchable:BAABLgAECn8dAAIUAAgJnBmJFgBlAgAUAAgJnBmJFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgYJCgABAAAAAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lé']='Léblanc:BAABLgAECn8bAAIFAAgJoBw+DgDWAQAFAAgJoBw+DgDWAQAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Mari:BAAALgAECgMJBQABLgAECgcJIgACAPMeAA==.Matroxx:BAAALgAECgYJCgABLgAFFAQJDAAGANMNAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAABLgAECn8jAAIGAAgJrB9iJgCiAgAGAAgJrB9iJgCiAgAAAA==.Melysia:BAACLgAFFH8JAAIEAAQJfB2/AgB9AQAEAAQJfB2/AgB9AQAuAAQKfygAAgQACQl/HgENANUCAAQACQl/HgENANUCAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgADCgYJCwAAAA==.Mizby:BAAALgADCgIJAwAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8dAAMRAAgJqyOsAwAuAQAQAAQJ0iO5GwA6AQARAAQJdiOsAwAuAQAAAA==.Moby:BAAALgAECgMJAwAAAA==.Moistmender:BAAALgAECgQJBQAAAA==.Monktyson:BAAALgAECgYJBgAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgEJAgABAAAAAA==.Murridan:BAABLgAECn8kAAIPAAkJxSGcCQA7AwAPAAkJxSGcCQA7AwAAAA==.',
My='Myraela:BAAALgADCgUJBQABLgAECgYJDgABAAAAAA==.',
['Më']='Mëow:BAAALgAECgMJBQAAAA==.',
['Mø']='Møldy:BAAALgAECgUJBwAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgADCgYJBgAAAA==.Nexes:BAAALgADCgcJEgAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgEJAQAAAA==.Nirina:BAAALgAECgQJCQAAAA==.Nixie:BAAALgAECgYJAwAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgADCgQJBAABLgAECggJGwAFAA8XAA==.Notdicey:BAAALgADCgEJAQABLgAECgkJGgAXACQgAA==.Novo:BAAALgAECgUJCQAAAA==.',
Nu='Nukefury:BAABLgAECn8WAAIUAAYJZyRtGgBAAgAUAAYJZyRtGgBAAgAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8HAAIPAAQJ1hO0BgBBAQAPAAQJ1hO0BgBBAQAuAAQKfxwAAg8ACQmzH60PAAEDAA8ACQmzH60PAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
Op='Oppose:BAAALgAECgYJBgAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Ormagöden:BAABLgAECn8aAAImAAkJ5RKJAwBPAgAmAAkJ5RKJAwBPAgAAAA==.',
Pa='Palladean:BAAALgAECgYJEQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwABAAAAAA==.Pastasauce:BAABLgAECn8VAAIjAAcJEAsEJQAUAQAjAAcJEAsEJQAUAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgYJBQABLgAECggJIwAHAMIhAA==.Penwork:BAAALgAECgYJAwAAAA==.Penz:BAAALgADCgMJAwAAAA==.Perrian:BAAALgADCgMJBAAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Phøenixbane:BAAALgAECgQJCAAAAA==.',
Pi='Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgIJAwAAAA==.',
Pl='Plaguefist:BAAALgAECgcJDAAAAA==.Plata:BAAALgAECgMJAwAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.',
Po='Pocketmage:BAAALgAECgEJAQAAAA==.',
Pr='Premonitions:BAABLgAECn8XAAIcAAcJ8Q7CDQBiAQAcAAcJ8Q7CDQBiAQAAAA==.Premune:BAABLgAECn8gAAMJAAkJeh5gDQCuAgAJAAkJeh5gDQCuAgAjAAIJOgiaGwFjAAAAAA==.Prion:BAAALgAECgcJDAAAAA==.',
Ps='Psycs:BAAALgADCgYJCAAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAECgkJIwAFAGwhAA==.Purplemage:BAAALgAECgkJCgAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8eAAMQAAgJoxtICADtAQAQAAgJoxtICADtAQARAAEJkxEVbQA6AAAAAA==.Quíts:BAAALgADCgEJAQAAAA==.',
Ra='Rainbowdots:BAAALgAECgcJCgAAAA==.Raine:BAACLgAFFH8RAAIcAAYJMQiFAgC9AQAcAAYJMQiFAgC9AQAuAAQKfxYAAxwACAkLHzEfACUCABwACAkLHzEfACUCABQABAkKGVNVAPAAAAAA.Raistlin:BAAALgAECgYJEgAAAA==.Ralfio:BAABLgAECn8VAAIYAAYJCiJrDwBDAgAYAAYJCiJrDwBDAgAAAA==.Ralfiosky:BAAALgAECgYJBgABLgAECgYJFQAYAAoiAA==.Ramennoodlez:BAAALgADCggJDgAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAABLgAECn8UAAMbAAcJ1R+5CgAaAgAbAAcJ1R+5CgAaAgAeAAEJAAC1gQAvAAAAAA==.',
Re='Readycheck:BAAALgADCggJFQAAAA==.Redcows:BAAALgADCggJFAAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8aAAIjAAgJSR3gBgAgAgAjAAgJSR3gBgAgAgAAAA==.Remulous:BAAALgAECgQJBwAAAA==.Revelaen:BAACLgAFFH8GAAIXAAMJ2gqJDQCcAAAXAAMJ2gqJDQCcAAAuAAQKfyEAAxcACAmtIAkJAOcCABcACAmtIAkJAOcCAA4ABQlYBoAoANwAAAAA.',
Ri='Rick:BAACLgAFFH8HAAMLAAMJlyMiBABEAQALAAMJlyMiBABEAQAMAAEJXBruJABUAAAuAAQKfyUAAwsACAnPI2gBALcCAAwACAlpI8kJAAQDAAsACAm2H2gBALcCAAAA.Rickers:BAAALgAECgMJAwAAAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAAALgAECgYJDAABLgAECggJGwAYAI4lAA==.Roust:BAAALgAECgUJBQABLgAECgkJIwAFAGwhAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saba:BAAALgAECgIJAgAAAA==.Saephora:BAAALgAECgYJDwAAAA==.Saerea:BAABLgAECn8YAAIGAAcJJh53MwBpAgAGAAcJJh53MwBpAgAAAA==.Sahhm:BAAALgAECgQJBwAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBQABLgAECgUJBgABAAAAAA==.Sammel:BAAALgAECggJDgAAAA==.Sandmanslim:BAAALgADCgkJEAAAAA==.Sathreina:BAABLgAECn8WAAIjAAgJ5hHcRgAPAgAjAAgJ5hHcRgAPAgAAAA==.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8UAAIDAAgJgR1rEgCAAgADAAgJgR1rEgCAAgAAAA==.Scootzmcgee:BAAALgADCgEJAQAAAA==.',
Se='Seki:BAECLgAFFH8KAAIQAAQJjhgMBgBZAQAQAAQJjhgMBgBZAQAuAAQKfxsABBAACAl7HUUdAKYCABAACAl7HUUdAKYCABEAAglGGU1JAJIAACAAAQkAAJ8qAEoAAAAA.Sekimaru:BAABLgAECn8gAAISAAgJzxQiGwAnAgASAAgJzxQiGwAnAgAAAA==.Selok:BAAALgAFFAEJAQAAAA==.',
Sh='Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgADCgQJBAAAAA==.Shaeledoran:BAABLgAECn8pAAIGAAkJkxzhHADSAgAGAAkJkxzhHADSAgAAAA==.Shamaneggs:BAAALgAECgIJAgAAAA==.Shamatroxx:BAACLgAFFH8HAAInAAQJhwfpAAA9AQAnAAQJhwfpAAA9AQAuAAQKfx0AAicACQn4FswBAPgBACcACQn4FswBAPgBAAEuAAUUBAkMAAYA0w0A.Shampomaster:BAAALgADCgMJAwAAAA==.Shieetz:BAAALgAECgYJDAAAAA==.Shlomie:BAAALgADCgcJDwAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgADCgMJAwAAAA==.Shänk:BAAALgAECgYJCgAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgYJBgAAAA==.Silre:BAAALgAECgQJBwAAAA==.Silverfangg:BAAALgADCgkJEQAAAA==.Sinergy:BAABLgAECn8UAAIQAAYJHx83RAD/AQAQAAYJHx83RAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJCgABAAAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snaxx:BAAALgADCgYJBgABLgAECgYJCwABAAAAAA==.Snorunt:BAAALgAECgYJDAAAAA==.Snuudle:BAACLgAFFH8JAAMGAAMJJBksJgD9AAAGAAMJJBksJgD9AAAmAAEJuRVvAwBfAAAuAAQKfzIAAgYACQmuIZgAABEDAAYACQmuIZgAABEDAAAA.',
So='Solokills:BAAALgAECgcJBwAAAA==.Soulreaperqt:BAAALgADCgEJAQABLgAECgUJCwABAAAAAA==.Soundtrack:BAAALgADCgEJAQAAAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAIJBQAaAAoEAA==.',
Sq='Sqlpal:BAABLgAECn8hAAMPAAcJ6R7uCQDTAQAPAAcJ6R7uCQDTAQAiAAQJOB72PgAAAQAAAA==.Squirrels:BAAALgAECgYJEgAAAA==.Squirtstorm:BAABLgAECn8UAAIcAAYJ4COHAwBHAgAcAAYJ4COHAwBHAgAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8cAAISAAkJexY8AQBiAgASAAkJexY8AQBiAgAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Stompy:BAAALgADCgkJCQABLgAFFAMJBwAZAKoJAA==.Storienn:BAAALgAECgUJBQAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Suküna:BAABLgAECn8iAAIPAAgJwh4mGQC+AgAPAAgJwh4mGQC+AgAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAABLgAECn8gAAIcAAgJViQiDAC/AgAcAAgJViQiDAC/AgAAAA==.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAIGAAcJOBTTEgB8AQAGAAcJOBTTEgB8AQAAAA==.Syrelia:BAABLgAECn8ZAAIFAAcJIxQ0FQCZAQAFAAcJIxQ0FQCZAQAAAA==.',
Ta='Takèda:BAAALgAECgYJDgAAAA==.Taldain:BAAALgAECgMJBQAAAA==.Talonstrykz:BAAALgAECggJEQAAAA==.Tankdeesnuts:BAAALgAECgUJEQAAAA==.Tashalle:BAAALgAECgEJAQABLgAECggJHgAaALkeAA==.Tauloe:BAAALgAECgMJBQAAAA==.Tayna:BAAALgADCgMJAwAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAAALgAECgYJDAAAAA==.Tetanus:BAAALgAECgQJBQAAAA==.',
Th='Thomo:BAAALgAECgYJCwAAAA==.Throatfist:BAAALgAFFAIJAwABLgAFFAQJCgAPAFkiAA==.Thunk:BAACLgAFFH8FAAIUAAMJixbJDQAQAQAUAAMJixbJDQAQAQAuAAQKfx4AAhQACAmnJfQDAGADABQACAmnJfQDAGADAAAA.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Tomotostein:BAABLgAECn8dAAIjAAgJHRgEOQA/AgAjAAgJHRgEOQA/AgAAAA==.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAAALgADCgYJBgABLgAECgUJDAABAAAAAA==.',
Tr='Tradrael:BAAALgADCgYJBgAAAA==.Tristîtia:BAAALgAECggJDwAAAA==.',
Ts='Tsume:BAAALgAECgQJBwAAAA==.',
Tu='Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyv:BAABLgAECn8bAAMVAAgJvBFZBwCPAQAVAAYJoBZZBwCPAQAFAAIJhAUKWgBTAAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAAALgAECgQJBwAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8gAAIFAAgJoyD0BwApAgAFAAgJoyD0BwApAgAAAA==.Valyndra:BAAALgAECgEJAQABLgAECgMJBQABAAAAAA==.Vampÿ:BAAALgADCgYJBgABLgAECggJIwALAFcdAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAAALgAECgYJDgAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQAAAA==.Velectran:BAAALgAECgcJDwABLgAECgcJGQAFACMUAA==.',
Vi='Vish:BAAALgAECgUJBgAAAA==.',
Vo='Vortash:BAAALgADCgcJCAAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAFABMDAA==.',
Wa='Warheimer:BAAALgADCgYJEgAAAA==.Warrgodx:BAAALgAECgYJDAAAAA==.',
We='Wengja:BAABLgAECn8gAAQIAAcJryUEBwDsAgAIAAcJryUEBwDsAgADAAEJ9QSHjgAnAAANAAEJAACSiQAlAAAAAA==.',
Wh='Whoknows:BAAALgAECgEJAgAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEAAAAA==.',
Wr='Wrongwookie:BAABLgAECn8aAAIUAAkJoxygCAAHAwAUAAkJoxygCAAHAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgMJBgAAAA==.',
Xi='Xiak:BAAALgADCgYJBgABLgAECgcJFAAbANUfAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yi='Yinshai:BAAALgAECgYJCwAAAA==.',
Yo='Yoomesbonds:BAAALgAECgMJBQAAAA==.Youtube:BAACLgAFFH8WAAMXAAYJXiQxAQB1AgAXAAYJXiQxAQB1AgAOAAMJayGFAwAlAQAuAAQKfx8AAw4ACQknJVMDAOoCAA4ABwmsJVMDAOoCABcABAlsHz8oAHsBAAAA.Yozki:BAABLgAECn8UAAIFAAYJbCESVAA8AgAFAAYJbCESVAA8AgAAAA==.',
Yu='Yuulia:BAABLgAECn8dAAMlAAgJ2BvRAABQAgAlAAgJWRvRAABQAgAHAAYJeRhkGQCGAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgADCgYJCwABLgAECgYJDQABAAAAAA==.Zariee:BAAALgAECgEJAQAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIFAAMJEwPUFQDTAAAFAAMJEwPUFQDTAAAuAAQKfzAAAwUACQnOGDoKAAcCAAUACQnOGDoKAAcCABUAAgneBb8ZAEoAAAAA.Zetta:BAACLgAFFH8HAAIZAAMJqgmwDADhAAAZAAMJqgmwDADhAAAuAAQKfyIAAhkACAmGHuUMALUCABkACAmGHuUMALUCAAAA.',
Zo='Zoltan:BAABLgAECn8VAAIFAAYJnQvE2QA9AQAFAAYJnQvE2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAAALgAECgYJBwAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAABLgAECn8cAAIDAAcJWxxPFwBMAgADAAcJWxxPFwBMAgAAAA==.',
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

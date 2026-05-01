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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Mage-Frost','DeathKnight-Unholy','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Evoker-Devastation','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Mage-Arcane','Warrior-Fury','Evoker-Augmentation','Evoker-Preservation','Priest-Shadow','Priest-Discipline','Druid-Feral','Shaman-Restoration','Rogue-Outlaw','Druid-Balance','Hunter-Survival','Warlock-Affliction','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Accost:BAAALgAECgQJBAAAAA==.',
Ad='Adagar:BAAALgAECgYJBgAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAMJAwABAAAAAA==.Aethandor:BAAALgAECgQJCAAAAA==.',
Ak='Akassa:BAAALgAECgYJDAAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
Al='Alecto:BAABLgAECn8VAAICAAcJtgxtSQAuAQACAAcJtgxtSQAuAQAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amarah:BAABLgAECn8tAAIDAAkJuBp6BQBrAgADAAkJuBp6BQBrAgAAAA==.',
An='Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgEJAQABLgAECgkJFQAEAJEcAA==.',
Ap='Applemonster:BAAALgAECgcJBwAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argdru:BAAALgAECgYJDQAAAA==.Argrekd:BAAALgADCgMJAwABLgAECgYJDQABAAAAAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgEJAQAAAA==.Arknox:BAABLgAECn8YAAIFAAcJrw/xFwCQAQAFAAcJrw/xFwCQAQAAAA==.Arthaslk:BAAALgAECgcJCAABLgAECgYJDAABAAAAAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAUJDgAGAFMeAA==.Ashallel:BAAALgAECgQJBAABLgAFFAUJDgAGAFMeAA==.Ashx:BAAALgADCgIJBAABLgAECggJGwAHAAQXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Atlette:BAACLgAFFH8NAAIDAAQJNBxiBABiAQADAAQJNBxiBABiAQAuAAQKfycAAgMACQluH2ICAEUDAAMACQluH2ICAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8MAAIIAAQJ0w2zHgAjAQAIAAQJ0w2zHgAjAQAuAAQKfz8AAggACAnZI84QABcDAAgACAnZI84QABcDAAEuAAUUBQkTAAkAGBQA.Attman:BAAALgAFFAEJAQAAAA==.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgADCgQJBAABLgAECgYJEAABAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAAAAA==.Ballsofire:BAABLgAECn8bAAIKAAcJsRiFDABaAQAKAAcJsRiFDABaAQAAAA==.Basherz:BAAALgAECgMJAwAAAA==.',
Be='Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAAALgAECgUJEQAAAA==.Belithel:BAABLgAECn8bAAIHAAgJBBcAdgDmAQAHAAgJBBcAdgDmAQAAAA==.Bencreepin:BAAALgAECgQJDAAAAA==.Beniz:BAAALgAECgcJEAAAAA==.Bernoulli:BAAALgAECgYJEwAAAA==.',
Bi='Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.',
Bl='Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAcJHAALALYfAA==.Bloodymyst:BAABLgAFFH8cAAILAAcJth9lAACVAgALAAcJth9lAACVAgAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boopsnoopems:BAAALgAECgQJDQAAAA==.',
Br='Briannajade:BAABLgAECn8XAAIHAAgJOghpUABAAQAHAAgJOghpUABAAQAAAA==.Brisha:BAACLgAFFH8TAAIFAAUJ5h90BACvAQAFAAUJ5h90BACvAQAuAAQKfy4AAwUACQk9JHUAALUDAAUACQk9JHUAALUDAAwAAQkaEs4lADwAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgADCgcJBwAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAECggJHgANAHsdAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMNAAgJex26DgDFAgANAAgJex26DgDFAgAOAAYJag3GTwAPAQAAAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIGAAkJ1yK0AQCJAwAGAAkJ1yK0AQCJAwAAAA==.Cammi:BAAALgAECgYJDwAAAA==.Casare:BAABLgAECn8XAAIOAAYJ3gePXgDHAAAOAAYJ3gePXgDHAAAAAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAAALgAECgIJAwABLgAECggJHgAHAGoVAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chapito:BAAALgAECgQJBAAAAA==.Chipmonked:BAABLgAECn8iAAQPAAgJkQg2HgD0AAAPAAYJNQo2HgD0AAAEAAcJ5wPgIwDnAAALAAUJIwPHUACQAAAAAA==.Chlop:BAABLgAECn8ZAAIIAAgJahxsHADUAgAIAAgJahxsHADUAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn8eAAIQAAcJxAhiBgA1AQAQAAcJxAhiBgA1AQAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECgYJBwAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgYJCwAAAA==.Congdh:BAACLgAFFH8OAAIRAAQJWSJFCgBkAQARAAQJWSJFCgBkAQAuAAQKfx4AAhEACAm8JKYMABsDABEACAm8JKYMABsDAAAA.Conmann:BAAALgAECgYJEAAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAAAAA==.Crossy:BAAALgAECgQJBQAAAA==.Cryogenic:BAAALgAECgQJBQAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAAALgAECgQJAwAAAA==.',
Da='Daak:BAAALgADCgYJCgABLgAECgcJFAAEANUGAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAABLgAECn8YAAIIAAkJqB6LDwBDAgAIAAkJqB6LDwBDAgAAAA==.Darkacedia:BAABLgAECn8jAAMSAAgJIB9MDgA4AgASAAgJIB9MDgA4AgATAAMJyQ9WQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgADCgMJAwAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAAALgAECgQJDQAAAA==.Deadcells:BAAALgADCgEJAQABLgAECgQJDQABAAAAAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAECgQJCQAAAA==.Dealosed:BAACLgAFFH8HAAMUAAQJGg6nAgAPAQAUAAMJsxKnAgAPAQAVAAQJ0gcQDwD/AAAuAAQKfyMAAxUACAkJIcsRAJECABUABwnOIMsRAJECABQABQkoIi4EAJkBAAAA.Decrepit:BAABLgAECn8UAAIIAAcJcRRoMwBrAQAIAAcJcRRoMwBrAQAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Dex:BAAALgAECgEJAQAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diddious:BAAALgADCgMJAgAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgADCgcJBwAAAA==.Disastasmite:BAAALgADCgEJAQABLgAECgYJGgAWAGckAA==.Dive:BAABLgAECn8jAAMHAAkJDSLnJgDXAgAHAAgJjCHnJgDXAgAXAAUJbRx5CwAfAQAAAA==.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIEAAkJkRw2DgCxAgAEAAkJkRw2DgCxAgAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAABLgAECn8dAAIYAAgJbBBkDwDDAQAYAAgJbBBkDwDDAQAAAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCgAAAA==.Dragoneggs:BAACLgAFFH8FAAMZAAMJ4xStFQD6AAAZAAMJ4xStFQD6AAAaAAEJwgEyGQA3AAAuAAQKfyAAAxkACQnYHu4IAOoCABkACQnYHu4IAOoCABoABwkZDmAfAIQBAAAA.Dragonforce:BAAALgAECgYJDAABLgAECgcJDQABAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8qAAIbAAgJrCOXAQDgAgAbAAgJrCOXAQDgAgAAAA==.Driipp:BAAALgAECggJCgAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAAALgAECgUJDwAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAMJCAAcACgPAA==.',
Dy='Dyab:BAAALgADCgUJBQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMdAAcJnCFkCwAKAgAdAAYJbiNkCwAKAgAGAAYJKxDZWABIAQABLgAFFAgJHAAZALoYAA==.',
Ec='Echidona:BAABLgAECn8bAAIVAAgJERn/EwB2AgAVAAgJERn/EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAUJDwASAPAYAA==.',
El='Elenix:BAABLgAECn8aAAMWAAkJyRyxCAAGAwAWAAkJyRyxCAAGAwAeAAMJhA33gACQAAAAAA==.Elinras:BAAALgAFFAIJAwAAAA==.Elliott:BAAALgADCgMJBQABLgADCggJDQABAAAAAA==.Elrizon:BAAALgAECgIJAQAAAA==.Elvar:BAAALgAECgcJDAABLgAECgQJBQABAAAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIDAAcJ2RUEIADhAQADAAcJ2RUEIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAABLgAECn8jAAIfAAgJqyHlAAAMAwAfAAgJqyHlAAAMAwAAAA==.',
En='Endboss:BAAALgAECgUJBQAAAA==.Endorsi:BAAALgAFFAIJAgAAAA==.Enfuega:BAAALgAECgQJBwAAAA==.Eniar:BAAALgAFFAQJBAAAAA==.',
Er='Eroninja:BAAALgAECgQJCAABLgAECggJGwAHAAQXAA==.',
Eu='Eurong:BAACLgAFFH8MAAIgAAQJwxjuCABMAQAgAAQJwxjuCABMAQAuAAQKfxsAAiAACAlvH0QaADICACAACAlvH0QaADICAAAA.',
Ev='Evangelune:BAAALgAECgQJBgAAAA==.',
Ew='Ewright:BAAALgAECgEJAQAAAA==.',
Ez='Ezynuff:BAAALgAECgUJCQABLgAECgYJEAABAAAAAA==.',
['Eï']='Eïr:BAAALgADCgcJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAASAB8fAA==.Fapple:BAAALgAECgQJBAABLgAECggJGAAaACogAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAABLgAECn8rAAMNAAgJNR4gDABAAgANAAgJNR4gDABAAgAhAAQJggs1IwC2AAAAAA==.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felheart:BAAALgAECgYJBwAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgUJDwABAAAAAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAAALgAECgMJBwAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgMJAwAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8dAAMaAAgJCg5mJABVAQAaAAcJJQxmJABVAQAZAAgJIQ4pFgBNAQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJGwAKALEYAA==.',
Fr='Fries:BAECLgAFFH8GAAISAAQJow+uHgAnAQASAAQJow+uHgAnAQAuAAQKfxcAAxIACAmmHyYVAPwBABIACAmmHyYVAPwBABMAAQmHGhZgAE8AAAAA.Frozenpyre:BAAALgAECgYJEAAAAA==.',
Fu='Funch:BAABLgAECn8lAAITAAgJQxQAAwDMAQATAAgJQxQAAwDMAQAAAA==.',
['Fè']='Fènrir:BAAALgADCgcJCQAAAA==.',
Ga='Gainzbrew:BAAALgADCgYJCQAAAA==.Gainzz:BAAALgAECgMJAwAAAA==.Galesdeyn:BAAALgAECgQJBgAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAHAD4dAA==.Garonnaa:BAAALgAFFAEJAgAAAA==.',
Gh='Ghari:BAABLgAECn8UAAIIAAgJHg1tSgAfAQAIAAgJHg1tSgAfAQAAAA==.',
Gi='Gilrog:BAAALgAECgUJEQAAAA==.Gingerlock:BAAALgAECgUJBgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.Glizzyghost:BAAALgAECgYJCAABLgAECgcJHgAiAAMgAA==.',
Gn='Gnoblin:BAAALgAECgQJCAAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAAALgAECgYJDAAAAA==.Greylooms:BAABLgAECn8gAAMjAAgJDCFqAQCjAgAjAAgJ4R9qAQCjAgAYAAYJhB3rMgDgAQAAAA==.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8IAAMcAAMJKA8bEgDqAAAcAAMJKA8bEgDqAAAbAAEJZABDGwA5AAAuAAQKfyAAAxsACAlQEH0kALQBABsABwmiEX0kALQBABwACAmNEdQdAKYBAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwAAAA==.Heàl:BAAALgAECgUJCAAAAA==.',
Hi='Hidejames:BAAALgAECgEJAQAAAA==.Hims:BAAALgAECgYJEwABLgAFFAcJHQAZAPUkAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8RAAIGAAQJZR0CCwBTAQAGAAQJZR0CCwBTAQAuAAQKfzMAAgYACAkwJgwBAHgDAAYACAkwJgwBAHgDAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAAALgAECgYJEwAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJCgABAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQAAAA==.',
Ic='Iclapu:BAAALgAECgEJAQAAAA==.',
Ig='Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8ZAAMkAAcJ8BoxBwAWAgAkAAcJ8BoxBwAWAgAlAAMJ1AmNVgCNAAAAAA==.',
Il='Ilililililli:BAAALgAECgcJEgAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIWAAcJrR6CEgCOAgAWAAcJrR6CEgCOAgAAAA==.Imhammered:BAAALgAECgQJDAAAAA==.Impullse:BAAALgAECgMJAwAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQAAAA==.',
It='Ithilwen:BAABLgAECn8iAAIcAAgJux6FBwAnAgAcAAgJux6FBwAnAgAAAA==.Itiswhatitiz:BAAALgAECgYJEQAAAA==.Itsybityshiv:BAABLgAECn8jAAMVAAgJLxfdBgAHAgAVAAgJLxfdBgAHAgAUAAEJoBjxHwAzAAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgEJAQAAAA==.Jahq:BAABLgAECn8VAAIRAAYJAyF5NAAnAgARAAYJAyF5NAAnAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.',
Jh='Jhani:BAAALgAECgYJDwAAAA==.',
Ji='Jinu:BAAALgAECgYJDQAAAA==.Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8kAAIHAAgJTxwVEgBLAgAHAAgJTxwVEgBLAgAAAA==.Jormojo:BAAALgAECgQJBQAAAA==.Jotwnky:BAABLgAECn8eAAQiAAcJAyC3BQAMAgAiAAUJSSO3BQAMAgATAAQJsxo8IwA+AQASAAMJFR9JuADoAAAAAA==.',
Ju='Jungol:BAAALgADCgkJDgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaltank:BAAALgAECgMJAwAAAA==.Kamin:BAABLgAECn8jAAIKAAgJwiHhAwARAwAKAAgJwiHhAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAAALgAFFAMJAwAAAA==.Kaykaypally:BAABLgAECn8UAAICAAYJwhdyNwBmAQACAAYJwhdyNwBmAQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAUJDwASAPAYAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8dAAICAAcJbxhALACRAQACAAcJbxhALACRAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgABAAAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8hAAIFAAgJZSJYAwDSAgAFAAgJZSJYAwDSAgAAAA==.Kidori:BAAALgAECgEJAQABLgAECggJIQAFAGUiAA==.Kilgharra:BAAALgADCgcJCAAAAA==.Kinji:BAAALgADCgYJCAABLgAECggJGwAHAAQXAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koriandar:BAAALgAECgYJCwAAAA==.',
Kr='Kristysavage:BAABLgAECn8fAAIhAAYJlyBhCgC7AQAhAAYJlyBhCgC7AQAAAA==.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAAAAA==.',
Ku='Kulaesca:BAAALgADCgkJDgAAAA==.',
Ky='Kynar:BAACLgAFFH8WAAMIAAcJqhsoAQAkAgAIAAYJqhsoAQAkAgAmAAEJAABgEQBnAAAuAAQKfxcAAggACAkuH6c/ADoCAAgACAkuH6c/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyua:BAAALgAECgYJDAAAAA==.',
La='Lambshot:BAAALgAECgYJEAAAAA==.Lambsy:BAACLgAFFH8eAAMYAAcJoRcvAAAUAgAYAAcJzRYvAAAUAgAjAAEJXgUpEgBNAAAuAAQKfxsAAxgACAmnIBMRAMgCABgACAl1HhMRAMgCACMAAQnuIzo5AEsAAAAA.Landwhalexxl:BAABLgAECn8WAAIHAAcJ9BH5XwAcAQAHAAcJ9BH5XwAcAQAAAA==.Laneera:BAAALgAECgQJCAAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8qAAIQAAgJdiKlAACsAgAQAAgJdiKlAACsAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Lightofhope:BAAALgAECgcJEAAAAA==.Lihandra:BAAALgADCgUJBQAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgAAAA==.Lilyy:BAABLgAECn8VAAIHAAcJpRpCkgCuAQAHAAcJpRpCkgCuAQAAAA==.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAAALgAECgYJEQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Lizzimcguire:BAAALgAECgEJAQAAAA==.',
Lo='Loraen:BAAALgAECgMJBQAAAA==.Lorelei:BAAALgAECgEJAQABLgAECggJIQAjAIkcAA==.Lostep:BAAALgADCgIJAgABLgAFFAcJGAAeAHYKAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAAALgAECgYJBwABLgABCgIJAgABAAAAAA==.Lunarmon:BAAALgAECgQJCgAAAA==.Lunchable:BAABLgAECn8eAAIWAAgJnBmIFgBlAgAWAAgJnBmIFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgYJDwABAAAAAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lé']='Léblanc:BAABLgAECn8bAAIHAAgJlRyFKADDAQAHAAgJlRyFKADDAQAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makaroni:BAAALgADCgEJAQAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Mari:BAAALgAECgMJBQABLgAECgkJLQADALgaAA==.Matroxx:BAAALgAECgcJDwABLgAFFAUJEwAJABgUAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAABLgAECn8jAAIIAAgJrB9mJgCiAgAIAAgJrB9mJgCiAgABLgAECggJHgANAHsdAA==.Melysia:BAACLgAFFH8OAAIGAAUJUx4PBADOAQAGAAUJUx4PBADOAQAuAAQKfzEAAwYACQnOHwENANQCAAYACQnOHwENANQCAB0AAgmmCRUZAFoAAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgADCgYJCwAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwABAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8lAAMTAAgJNCUYBwBEAQASAAQJgCWIIACyAQATAAQJziQYBwBEAQAAAA==.Moby:BAAALgAECgUJBwAAAA==.Moistmender:BAAALgAECgYJCwAAAA==.Monktyson:BAAALgAFFAQJBAAAAA==.Mortui:BAAALgADCgQJBgABLgAFFAUJEwAJABgUAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgYJCAABAAAAAA==.Murridan:BAABLgAECn8gAAIRAAkJxSGaCQA7AwARAAkJxSGaCQA7AwAAAA==.',
My='Mykaela:BAAALgAECgEJAQAAAA==.Myraela:BAAALgAECgQJBAABLgAECgYJEAABAAAAAA==.',
['Më']='Mëow:BAAALgAECgQJBgAAAA==.',
['Mø']='Møldy:BAAALgAECgUJBwAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAAALgAECgEJAQAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgADCgcJDQAAAA==.Nexes:BAAALgADCgcJEgAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJAwAAAA==.Nirina:BAAALgAECgQJDQAAAA==.Nixie:BAAALgAECgYJBQAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECggJGwAHAAQXAA==.Notdicey:BAAALgADCggJCQABLgAFFAMJBQAZACkaAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAABLgAECn8aAAIWAAYJZyRwGgBAAgAWAAYJZyRwGgBAAgAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8LAAIRAAQJ1hOzDwA8AQARAAQJ1hOzDwA8AQAuAAQKfx4AAhEACQmzH7MPAAEDABEACQmzH7MPAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECgEJAQAAAA==.',
Op='Oppose:BAAALgAECgYJDAAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Ormagöden:BAABLgAECn8iAAInAAkJJxSLAwBPAgAnAAkJJxSLAwBPAgAAAA==.',
Oz='Ozzpoxzo:BAAALgADCgQJBAAAAA==.',
Pa='Palladean:BAABLgAECn8XAAICAAYJcg88SgArAQACAAYJcg88SgArAQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwABAAAAAA==.Pastasauce:BAABLgAECn8VAAICAAcJEAsgVwAKAQACAAcJEAsgVwAKAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgcJCgABLgAECggJIwAKAMIhAA==.Penwork:BAAALgAECgYJBQAAAA==.Penz:BAAALgADCgMJAwAAAA==.Perrian:BAAALgADCgMJBAAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Philex:BAEALgADCgQJBAABLgAFFAUJDwASAPAYAA==.Phøenixbane:BAAALgAECgQJDAAAAA==.',
Pi='Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgMJBQAAAA==.',
Pl='Plaguefist:BAAALgAECgcJDQAAAA==.Plata:BAAALgAECgQJBAAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.',
Pr='Premonitions:BAABLgAECn8eAAIeAAcJuxTBFwCnAQAeAAcJuxTBFwCnAQAAAA==.Premune:BAABLgAECn8oAAQFAAkJeh5cDQCuAgAFAAkJeh5cDQCuAgAMAAgJ9A4/CgBgAQACAAIJOgilGwFjAAAAAA==.Prion:BAACLgAFFH8FAAIRAAMJSAkxJADTAAARAAMJSAkxJADTAAAuAAQKfxQAAhEACAnnEqQXAKsBABEACAnnEqQXAKsBAAAA.',
Ps='Psycs:BAAALgAECgYJBgAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAECgkJIwAHAA0iAA==.Purplemage:BAAALgAECgkJCgAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMSAAgJPx09EwALAgASAAgJoxs9EwALAgATAAMJzxeHEQCgAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgASAD8dAA==.',
Ra='Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH8YAAIeAAcJdgqtAQD5AQAeAAcJdgqtAQD5AQAuAAQKfxYAAx4ACAkLHywfACUCAB4ACAkLHywfACUCABYABAkKGVpVAPAAAAAA.Raistlin:BAABLgAECn8ZAAMlAAgJ4xWwDABxAQAlAAgJ4xWwDABxAQARAAEJywOS8AAiAAAAAA==.Ralfio:BAABLgAECn8YAAIaAAgJKiBvDwBDAgAaAAgJKiBvDwBDAgAAAA==.Ralfiosky:BAAALgAECgYJBgABLgAECggJGAAaACogAA==.Ramennoodlez:BAAALgADCggJDgAAAA==.Rat:BAAALgAFFAIJAgAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAABLgAECn8bAAQdAAcJ6h+5CgAaAgAdAAcJ1R+5CgAaAgAoAAUJvRS/DADtAAAgAAEJAADCgQAvAAAAAA==.',
Re='Readycheck:BAAALgAECgUJBQAAAA==.Redcows:BAAALgADCggJFAAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8hAAICAAgJyh3DEQAtAgACAAgJyh3DEQAtAgAAAA==.Remulous:BAAALgAECgYJDQAAAA==.Revelaen:BAACLgAFFH8IAAIZAAQJCA5qDwA1AQAZAAQJCA5qDwA1AQAuAAQKfyMAAxkACQl7HQ4JAOcCABkACQl7HQ4JAOcCABAABQlYBocoANwAAAAA.',
Ri='Rick:BAACLgAFFH8LAAMNAAQJUR27EgAlAQANAAQJUR27EgAlAQAOAAEJXBryJABUAAAuAAQKfycAAw4ACAnPI80JAAQDAA4ACAlpI80JAAQDAA0ACAm2H6RPAN4AAAAA.Rickers:BAAALgAECgMJAwABLgAFFAQJCwANAFEdAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAAALgAECgYJEgABLgAFFAMJBQAaAIolAA==.Roust:BAAALgAECgUJBQABLgAECgkJIwAHAA0iAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saephora:BAAALgAECgYJEgAAAA==.Saerea:BAABLgAECn8gAAIIAAgJKx8iDwBHAgAIAAgJKx8iDwBHAgAAAA==.Sahhm:BAAALgAECgQJCwAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAIJAgABAAAAAA==.Sammel:BAABLgAECn8VAAMbAAgJihhSFABOAgAbAAgJihhSFABOAgAcAAEJCxF7NgA2AAAAAA==.Sandmanslim:BAAALgADCgkJEAAAAA==.Sathreina:BAABLgAECn8eAAICAAgJ2BPiJgCoAQACAAgJ2BPiJgCoAQAAAA==.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIEAAkJLxtrEgCAAgAEAAkJLxtrEgCAAgAAAA==.Scootzmcgee:BAAALgAECgUJCQAAAA==.',
Se='Seki:BAECLgAFFH8PAAISAAUJ8BgGFABNAQASAAUJ8BgGFABNAQAuAAQKfxsABBIACAl7HUIdAKYCABIACAl7HUIdAKYCABMAAglGGVBJAJIAACIAAQkAAKEqAEoAAAAA.Sekii:BAEALgAECgQJBAABLgAFFAUJDwASAPAYAA==.Sekimaru:BAABLgAECn8oAAMVAAgJ8xWTCgDAAQAVAAgJ8xWTCgDAAQAUAAEJyQfdFQAyAAAAAA==.Selok:BAAALgAFFAEJAgAAAA==.',
Sh='Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJCAAAAA==.Shaeledoran:BAABLgAECn8yAAIIAAkJYh3mHADSAgAIAAkJYR3mHADSAgAAAA==.Shamaneggs:BAAALgAECgMJAwAAAA==.Shamatroxx:BAACLgAFFH8TAAIJAAUJGBTtAQAFAQAJAAUJGBTtAQAFAQAuAAQKfycAAgkACQk/GU0DABcCAAkACQk/GU0DABcCAAAA.Shampomaster:BAAALgADCgMJAwAAAA==.Shieetz:BAAALgAECgYJEAAAAA==.Shlomie:BAAALgADCggJFQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgADCgMJAwAAAA==.Shorttemper:BAAALgADCgQJBAAAAA==.Shänk:BAAALgAECgYJDwAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgYJDAAAAA==.Silith:BAAALgADCgYJBwAAAA==.Silre:BAAALgAECgQJBwAAAA==.Silverfangg:BAAALgADCgkJEQAAAA==.Sinergy:BAABLgAECn8UAAISAAYJHx8yRAD/AQASAAYJHx8yRAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJCgABAAAAAA==.Slappeey:BAAALgAECggJCAABLgAECgkJCgABAAAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECggJGAAaACogAA==.Snaxx:BAAALgADCgYJBgABLgAECgYJCwABAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8MAAMIAAMJwx2dLQAJAQAIAAMJwx2dLQAJAQAnAAEJuRUBBgBZAAAuAAQKfzIAAggACQmuISwHAKsCAAgACQmuISwHAKsCAAAA.',
So='Solokills:BAAALgAECgcJDwAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwABAAAAAA==.Soundtrack:BAAALgADCgEJAQAAAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAMJCAAcACgPAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMRAAcJpx6zLwA9AgARAAcJpx6zLwA9AgAlAAQJOB72PgAAAQAAAA==.Squirrels:BAABLgAECn8UAAMEAAcJ1QZLKwC9AAAEAAcJ1QZLKwC9AAALAAQJuwXpUgCGAAAAAA==.Squirtstorm:BAABLgAECn8bAAIeAAcJOCGrBwBxAgAeAAcJOCGrBwBxAgAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8kAAIVAAkJCB1dAQDdAgAVAAkJCB1dAQDdAgAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Stompy:BAAALgADCgkJCQABLgAFFAQJCQAbAHMKAA==.Storienn:BAAALgAECgYJCwAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Suküna:BAACLgAFFH8HAAIRAAMJTRMjHwDrAAARAAMJTRMjHwDrAAAuAAQKfyYAAhEACAkjICkZAL0CABEACAkjICkZAL0CAAAA.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAABLgAECn8hAAIeAAgJViQgDAC/AgAeAAgJViQgDAC/AgAAAA==.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAIIAAcJOBTKOgBPAQAIAAcJOBTKOgBPAQAAAA==.Syrelia:BAABLgAECn8eAAIHAAgJahXNIwDZAQAHAAgJahXNIwDZAQAAAA==.',
Ta='Takèda:BAAALgAECgYJEgAAAA==.Taldain:BAAALgAECgMJBQAAAA==.Talonstrykz:BAAALgAECggJEQAAAA==.Tankdeesnuts:BAABLgAECn8WAAIKAAYJlgSjHQCSAAAKAAYJlgSjHQCSAAAAAA==.Tashalle:BAAALgAECgEJAQABLgAECggJIgAcALseAA==.Tauloe:BAAALgAECgUJCgAAAA==.Tayna:BAAALgADCgMJAwAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8UAAICAAgJqBOpJQCtAQACAAgJqBOpJQCtAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEAABAAAAAA==.',
Th='Thomo:BAAALgAECgYJEQAAAA==.Throatfist:BAAALgAFFAIJAwABLgAFFAQJDgARAFkiAA==.Thunk:BAACLgAFFH8HAAIWAAMJPBfMDQAQAQAWAAMJPBfMDQAQAQAuAAQKfyEAAhYACQmAJfYDAGADABYACQmAJfYDAGADAAAA.',
Ti='Timdawg:BAAALgAECgMJAwABLgAECgUJEwABAAAAAA==.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Tomotostein:BAABLgAECn8kAAICAAgJFhr+OAA/AgACAAgJFhr+OAA/AgAAAA==.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAAALgADCgYJBgABLgAECgUJDwABAAAAAA==.',
Tr='Tradrael:BAAALgADCgYJBgAAAA==.Tristîtia:BAAALgAECgkJEAAAAA==.',
Ts='Tsume:BAAALgAECgYJDgAAAA==.',
Tu='Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAECgcJBwAAAA==.Tyv:BAABLgAECn8jAAMXAAgJWBJbBwCPAQAXAAYJoBZbBwCPAQAHAAUJkQaUiADCAAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAAALgAECgQJCAAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIHAAkJ6CCPDAB/AgAHAAkJ6CCPDAB/AgAAAA==.Valyndra:BAAALgAECgIJAgABLgAECgMJBQABAAAAAA==.Vampÿ:BAAALgAECgMJAwABLgAECggJKwANADUeAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAABLgAECn8UAAIKAAYJTwgYFwDOAAAKAAYJTwgYFwDOAAAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQAAAA==.Velectran:BAABLgAECn8VAAICAAcJjhJLRgA3AQACAAcJjhJLRgA3AQABLgAECggJHgAHAGoVAA==.',
Vi='Virdreth:BAAALgADCgEJAQAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Vortash:BAAALgADCgcJCAAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAHABMDAA==.',
Wa='Warheimer:BAAALgADCggJFQAAAA==.Warrgodx:BAAALgAECgYJDAAAAA==.Wartroxx:BAAALgADCgYJBgABLgAFFAUJEwAJABgUAA==.',
We='Wengja:BAABLgAECn8gAAQLAAcJryULBwDqAgALAAcJryULBwDqAgAEAAEJ9QSPjgAnAAAPAAEJAACaiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECggJIQAjAIkcAA==.Whoknows:BAAALgAECgYJCAAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIWAAkJwx2kCAAIAwAWAAkJwx2kCAAIAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgMJBgAAAA==.',
Xi='Xiak:BAAALgADCgYJBgABLgAECgcJGwAdAOofAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yi='Yinshai:BAAALgAECgcJEQAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH8dAAMZAAcJ9SSGAAB8AgAZAAcJ9SSGAAB8AgAQAAMJayGHAwAlAQAuAAQKfx8AAxAACQknJVIDAOoCABAABwmsJVIDAOoCABkABAlsH0EoAHsBAAAA.Yoyohunty:BAAALgAECgEJAQAAAA==.Yozki:BAABLgAECn8cAAIHAAcJ3yBsGwAHAgAHAAcJ3yBsGwAHAgAAAA==.',
Yu='Yuuki:BAAALgADCgEJAgABLgAFFAIJAgABAAAAAA==.Yuulia:BAABLgAECn8hAAMjAAgJiRyRAgBQAgAjAAgJChyRAgBQAgAKAAYJeRhqGQCGAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgAECgEJAQABLgAECgkJEwABAAAAAA==.Zariee:BAAALgAECgEJAQAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIHAAMJEwP6MQDgAAAHAAMJEwP6MQDgAAAuAAQKfzAAAwcACQmdGNsfAO4BAAcACQmdGNsfAO4BABcAAgneBb0ZAEoAAAAA.Zenyea:BAAALgAECgQJBAABLgAFFAQJCQAbAHMKAA==.Zetta:BAACLgAFFH8JAAIbAAQJcwpFDgDiAAAbAAQJcwpFDgDiAAAuAAQKfyQAAhsACAlpH+YMALUCABsACAlpH+YMALUCAAAA.',
Zo='Zoltan:BAABLgAECn8VAAIHAAYJnQvN2QA9AQAHAAYJnQvN2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8UAAICAAcJtRmiHADeAQACAAcJtRmiHADeAQAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAABLgAECn8tAAIEAAgJDR5tBgA2AgAEAAgJDR5tBgA2AgAAAA==.',
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

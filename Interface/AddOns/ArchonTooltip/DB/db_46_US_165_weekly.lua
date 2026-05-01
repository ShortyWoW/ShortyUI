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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Druid-Feral','Paladin-Protection','Paladin-Holy','Hunter-Survival','Priest-Holy','Mage-Arcane','Priest-Discipline','Mage-Fire','Monk-Brewmaster',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8bAAIBAAcJCRQVQwBlAQABAAcJCRQVQwBlAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECgcJEAACAAAAAA==.Acslater:BAAALgAECgMJAwAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8JAAIDAAQJwhqMBwBTAQADAAQJwhqMBwBTAQAuAAQKfxUAAgMACAncI5IEAFIDAAMACAncI5IEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAECggJDAAAAA==.Aissae:BAACLgAFFH8JAAIEAAQJ7hzjEQAyAQAEAAQJ7hzjEQAyAQAuAAQKfyQAAgQACAksJHoLACYDAAQACAksJHoLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgIJAgAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgADCgcJCQAAAA==.Aliasx:BAAALgADCgIJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgQJBAAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgIJAgAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthur:BAAALgAECgQJCAAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.',
Au='Augonly:BAACLgAFFH8OAAIFAAQJpxVhCQA9AQAFAAQJpxVhCQA9AQAuAAQKfyMAAgUACQnoIC4GAOECAAUACQnoIC4GAOECAAAA.Augy:BAAALgAECgIJAgABLgAECggJDQACAAAAAA==.Autoshot:BAAALgADCgEJAQAAAA==.',
Av='Averisbelia:BAAALgADCgIJAgAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECgQJCAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAAALgAECgcJEwAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECgEJAQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8cAAIGAAgJYBLrMgB3AQAGAAgJYBLrMgB3AQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAAALgAFFAEJAQAAAA==.',
Be='Beastlieduke:BAAALgADCgUJCQABLgAFFAMJBgAHAPEKAA==.Beastlièduke:BAACLgAFFH8GAAIHAAMJ8QrQDQDqAAAHAAMJ8QrQDQDqAAAuAAQKfyIAAgcACAkwHfAOAJQCAAcACAkwHfAOAJQCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJDgAAAA==.Bellaruhbz:BAABLgAECn8dAAIIAAkJjA7MCQA2AQAIAAkJjA7MCQA2AQAAAA==.Berenstain:BAABLgAECn8aAAIJAAgJHhJQCQBAAQAJAAgJHhJQCQBAAQAAAA==.Berple:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Bestoresto:BAAALgAECggJDgAAAA==.',
Bi='Bibahabibi:BAABLgAECn8VAAMKAAYJMRK0GgAdAQAKAAYJMRK0GgAdAQALAAMJzQiGhwChAAAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8eAAMKAAcJJhleBgC4AQAKAAcJJhleBgC4AQALAAIJ3gcrmQBcAAAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJGgAMAEQjAA==.',
Bl='Blabbybootze:BAAALgADCgEJAQAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQANAIEkAA==.Blightfangs:BAABLgAECn8dAAIBAAcJEBBZlACrAQABAAcJEBBZlACrAQAAAA==.Blindnautdef:BAABLgAECn8hAAIEAAgJRw7eJQBSAQAEAAgJRw7eJQBSAQAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgADCgEJAQAAAA==.Bodakye:BAABLgAECn8WAAMOAAgJcRrBMwDgAQAOAAgJcRrBMwDgAQAIAAIJtAHlgABDAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgADCgMJAwAAAA==.',
Br='Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAAALgAECgcJEgAAAA==.Butane:BAAALgADCgIJAgAAAA==.',
Ca='Cap:BAAALgADCgEJAQAAAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgADCgQJBAAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn8cAAIEAAgJhQ77IgBiAQAEAAgJhQ77IgBiAQAAAA==.Chapelgnome:BAAALgAECgIJAgABLgAECggJHgAPADoPAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgYJDAAAAA==.Chipmonkey:BAAALgADCgMJAwABLgAECggJHgANAJINAA==.Chiptime:BAABLgAECn8eAAINAAgJkg2/LAAtAQANAAgJkg2/LAAtAQABLgAECggJHgANAJINAA==.Chomby:BAAALgADCgUJBwAAAA==.Chriifrio:BAAALgADCgQJBAAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgMJAwAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJAwAAAA==.',
Ci='Cinnamóróll:BAAALgAECggJDwAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8WAAMQAAgJchK9RQAtAQAQAAgJchK9RQAtAQARAAEJpwMSGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAAALgAFFAEJAQAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Corita:BAAALgAECgIJAgAAAA==.Cowhealer:BAABLgAECn8hAAMNAAgJgSSlAgAhAwANAAgJgSSlAgAhAwASAAEJTwUFgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgQJBAAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Cutestxx:BAAALgAECgcJBQAAAA==.',
Cy='Cyraxis:BAAALgADCgYJBgAAAA==.Cyxo:BAAALgADCgEJAQAAAA==.',
Da='Daftxshade:BAAALgAECgQJBAAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDAAAAA==.Darkcrusader:BAAALgAECgYJCQAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darthsyde:BAAALgAECgMJAwAAAA==.Dasdk:BAAALgAFFAEJAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAEJAQACAAAAAA==.',
De='Deadergriff:BAAALgAECgUJCQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAQAAAA==.Deadicated:BAAALgAECgYJCQAAAA==.Deadsies:BAAALgADCgIJAgABLgAECgUJCAACAAAAAA==.Delan:BAAALgAECgEJAQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAQAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Desunaito:BAACLgAFFH8NAAIRAAQJKh6CAAB6AQARAAQJKh6CAAB6AQAuAAQKfyAAAhEACAmzJLQAADkDABEACAmzJLQAADkDAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8FAAIEAAIJrBoTJACvAAAEAAIJrBoTJACvAAAuAAQKfxoAAwQACAkKIU04ABQCAAQABwnEH004ABQCABMABQmNJI4eAMoBAAAA.',
Di='Diddlefiddle:BAAALgAECgIJAgAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dirtycow:BAAALgAECgMJAwAAAA==.',
Dk='Dkzilong:BAAALgAFFAEJAQABLgAFFAIJBQAEAKwaAA==.',
Do='Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8WAAMUAAgJnBGWJwCQAQAUAAgJnBGWJwCQAQAVAAEJtgLKcgAzAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dormist:BAAALgADCgMJAwABLgAECggJEgACAAAAAA==.',
Dr='Dracnogard:BAAALgAECgQJBwAAAA==.Dracowulf:BAAALgAECgcJDwAAAA==.Dragonx:BAABLgAECn8cAAIOAAgJBg7lQwCgAQAOAAgJBg7lQwCgAQAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn8YAAIWAAYJYQNHCwCxAAAWAAYJYQNHCwCxAAAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAAALgAFFAMJAwAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8cAAIGAAgJxQtQNQBuAQAGAAgJxQtQNQBuAQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAAALgADCgkJEgAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAAALgAECggJEgAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ef='Effloria:BAAALgAECggJEQAAAA==.',
El='Elegia:BAACLgAFFH8JAAIUAAQJ+gsQHwAlAQAUAAQJ+gsQHwAlAQAuAAQKfycAAxQACQlIGyEZAL4CABQACQlIGyEZAL4CABUAAQkAAP5lAEMAAAAA.Elerianor:BAAALgAECgYJDQAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgMJAwAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Enjoi:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8eAAQMAAcJCx1cCwCpAQAMAAYJnBtcCwCpAQAEAAUJ/hGWOwD3AAATAAEJ4RABcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJDwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECgcJBwAAAA==.Evoextoons:BAAALgADCgUJCAAAAA==.',
Fa='Fallen:BAAALgAECgUJDQAAAA==.Fallingvoid:BAABLgAECn9hAAIEAAkJqCMWAQA3AwAEAAkJqCMWAQA3AwAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIEAAYJbRWLKQBAAQAEAAYJbRWLKQBAAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgADCgEJAQAAAA==.',
Fe='Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAABLgAECn8iAAIIAAgJ2xgaBADTAQAIAAgJ2xgaBADTAQAAAA==.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAABLgAECn8nAAIGAAgJHh/ZFAAUAgAGAAgJHh/ZFAAUAgAAAA==.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIEAAcJKx88KQBdAgAEAAcJKx88KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAAALgAECgYJDQAAAA==.',
Fo='Forsight:BAABLgAECn8XAAIQAAgJTBSTKgCRAQAQAAgJTBSTKgCRAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAABLgAECn8qAAMXAAgJEB2zDACHAgAXAAgJEB2zDACHAgAYAAIJRCBDJgC/AAAAAA==.Fremder:BAABLgAECn8kAAIFAAgJNBwfBwDJAQAFAAgJNBwfBwDJAQAAAA==.Fresher:BAABLgAECn8VAAIQAAUJyxwLPQBIAQAQAAUJyxwLPQBIAQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgQJBAACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgQJBwAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAABLgAECn8UAAIBAAYJeg8EbgD9AAABAAYJeg8EbgD9AAAAAA==.',
Fu='Funeral:BAACLgAFFH8WAAMVAAcJfRg3AQBnAQAVAAQJ0hw3AQBnAQAUAAMJ0w9lMACyAAAuAAQKfykABBUACQlzIT4EAKECABUABwnSID4EAKECABQACAkgF+lEAP0BABkAAQkIE4EpAEwAAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gi='Gimmedatmouf:BAAALgAFFAMJAwAAAA==.Gimmedatneck:BAABLgAECn8VAAMaAAgJPyOoCQDQAQAaAAgJPyOoCQDQAQAbAAEJNhLdHABDAAAAAA==.Gingy:BAAALgADCgYJCwAAAA==.',
Gl='Glead:BAAALgAECggJDwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJAwAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgADCgUJBQAAAA==.Graegor:BAAALgADCgEJAQAAAA==.Grandmoo:BAAALgAECgEJAQAAAA==.Grastim:BAAALgAECgQJBAAAAA==.Greenfanta:BAAALgADCgYJCwAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAABLgAECn8nAAIcAAgJWhKFFwCqAQAcAAgJWhKFFwCqAQAAAA==.Gripopotamus:BAAALgADCgYJBwAAAA==.Gristle:BAAALgADCgkJDAAAAA==.',
Gu='Gunner:BAAALgADCgYJEQABLgAECgQJBwACAAAAAA==.',
Ha='Hakaishaz:BAAALgADCgMJAwAAAA==.Halfwatt:BAAALgAECgMJAwAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8UAAIGAAcJmBK3OwBXAQAGAAcJmBK3OwBXAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8aAAMMAAkJRCNMAACDAwAMAAkJRCNMAACDAwATAAQJJRByPwD+AAAAAA==.Haru:BAAALgAECgYJDwAAAA==.Harvaal:BAAALgADCgQJBAAAAA==.Hasaro:BAABLgAECn8XAAIJAAkJNxLIDQCmAQAJAAkJNxLIDQCmAQAAAA==.Havokvacano:BAAALgAECggJDgAAAA==.',
He='Healmachine:BAAALgADCgkJDQAAAA==.Hellbrringer:BAAALgAECgQJBAAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hotsordots:BAAALgAECggJCQAAAA==.Hounskul:BAABLgAECn8WAAIUAAgJ2QdviwBCAQAUAAgJ2QdviwBCAQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8FAAIQAAMJbBUXOADuAAAQAAMJbBUXOADuAAAuAAQKfy8AAhAACAmqHX8YAPcBABAACAmqHX8YAPcBAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJAwAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJBwAAAA==.',
Ir='Iridellis:BAAALgAECgYJDQAAAA==.',
It='Itssofluffy:BAABLgAECn8dAAQdAAgJixR0CABpAQAdAAgJPRJ0CABpAQAJAAUJBhfZEwAyAQASAAIJWQk/RwAxAAAAAA==.Itwon:BAAALgADCgYJDAAAAA==.',
Ja='Jacus:BAAALgAECgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Jaycers:BAABLgAECn8ZAAMeAAgJNyA6AgBuAgAeAAgJNyA6AgBuAgAfAAEJ2AL0ngAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAAALgAECgYJDAAAAA==.Jokestarfist:BAAALgAECgQJCQAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
Ka='Kaitokit:BAAALgAECgUJCAAAAA==.Kajamando:BAABLgAECn8XAAITAAcJ6AZ4FAAGAQATAAcJ6AZ4FAAGAQAAAA==.Kalith:BAABLgAECn8WAAIgAAgJ+QKGFgAOAQAgAAgJ+QKGFgAOAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAAALgAECggJDQAAAA==.Kayotic:BAABLgAECn8XAAITAAYJ2QStGgDGAAATAAYJ2QStGgDGAAAAAA==.Kayww:BAAALgADCgYJBwAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAAALgAECggJEgAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Ki='Kikiana:BAAALgAECgIJAgABLgAECggJJQAhAKEhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAAALgAECgYJDAAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8XAAIEAAgJ7hWoXgCFAQAEAAgJ7hWoXgCFAQAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8VAAMLAAcJxxwZPQCwAQALAAcJnxoZPQCwAQAKAAQJvRO1GAC0AAAAAA==.',
Kr='Krushgar:BAAALgAFFAEJAQAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgADCgUJBQAAAA==.',
La='Lackluster:BAABLgAECn8ZAAIBAAgJAAdEuQBuAQABAAgJAAdEuQBuAQAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgEJAQAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Le='Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.',
Li='Lightingbolt:BAAALgADCgkJDQAAAA==.Lilthin:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgQJBQAAAA==.Littledude:BAAALgADCgMJAwAAAA==.Littlemorsel:BAAALgAECggJCwAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAAALgAECgQJEwAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchn:BAAALgAECggJEwAAAA==.',
['Lú']='Lúná:BAAALgAECgEJAQAAAA==.',
Ma='Maggieaugers:BAABLgAECn8eAAIPAAgJOg+tDwCUAQAPAAgJOg+tDwCUAQAAAA==.Magicmech:BAAALgADCgcJBwAAAA==.Magivacano:BAAALgAECgcJEAAAAA==.Mahnon:BAAALgAECgcJDAAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAAALgAECgQJBgAAAA==.',
Me='Metalhedface:BAAALgAFFAEJAQAAAA==.',
Mi='Mikecoxwall:BAABLgAECn8lAAMBAAgJ0wz4NgCKAQABAAgJ0wz4NgCKAQAiAAYJ3wj6CgAqAQAAAA==.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgADCgEJAQAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgQJBAAAAA==.Misary:BAAALgAECgQJBAAAAA==.',
Mo='Moltganus:BAAALgADCgUJBgAAAA==.Monkeli:BAAALgAECgUJBgAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAUJCgAdAPgRAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moogrim:BAAALgADCgYJBwAAAA==.Moonsiand:BAACLgAFFH8IAAIgAAMJsQMiDADRAAAgAAMJsQMiDADRAAAuAAQKfyAAAyAACAleE1sOAOEBACAACAleE1sOAOEBAAgAAQmqAU6ZABwAAAAA.Moosafur:BAABLgAECn8UAAMJAAkJOhwcAgBWAgAJAAcJeiQcAgBWAgAdAAIJeQPDNQAuAAAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Morphyr:BAAALgADCgIJAgAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgMJBQAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Mutuusami:BAAALgAECgEJAQAAAA==.',
Mx='Mx:BAAALgAECgMJBQAAAA==.',
My='Myraine:BAAALgADCgYJBgAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAAALgAECgYJEgAAAA==.Narexia:BAAALgAECgYJEwAAAA==.',
Ne='Nekuma:BAAALgAECgcJEQABLgAFFAQJDQARACoeAA==.Nellaa:BAAALgAECgcJCgAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8jAAIHAAkJ+xh+BQA/AgAHAAkJ+xh+BQA/AgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8bAAIBAAgJuxQARQBgAQABAAgJuxQARQBgAQAAAA==.',
Nu='Nutellaa:BAAALgAECgQJDgAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obie:BAAALgAECgQJBAAAAA==.Oborax:BAEALgAECgYJDwAAAA==.',
Od='Od:BAAALgAECgMJBAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIGAAgJNRnTKwB0AgAGAAgJNRnTKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAAALgAECgYJDAAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECgcJCwAAAA==.',
Pe='Perelia:BAABLgAECn8ZAAIjAAYJtAyRFQBHAQAjAAYJtAyRFQBHAQAAAA==.Pewpewqt:BAAALgAECgEJAQABLgAECgcJIAANACMZAA==.',
Pl='Plaguehammer:BAABLgAECn8UAAIQAAYJ3wYdWgD2AAAQAAYJ3wYdWgD2AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Popcola:BAAALgADCgEJAQAAAA==.Popopopopopo:BAAALgAECgEJAQAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAAALgADCgUJBQAAAA==.Punizher:BAAALgADCgcJBwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAEJAQACAAAAAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJCgACAAAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgQJCAAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgUJBQABLgAECgYJCgACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJCwAAAA==.Raevalinaa:BAAALgAECgMJBAAAAA==.Raevelinaa:BAAALgAECgIJAwABLgAECgMJBAACAAAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAAALgAECgYJEQAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Reeseepieces:BAAALgAECgQJCAAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn8dAAMHAAgJ2hYVDAC/AQAHAAgJ2hYVDAC/AQAjAAEJdx3YLwBWAAAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAAALgAECgQJBQAAAA==.Rezz:BAACLgAFFH8IAAIBAAMJ0Ap9OQDuAAABAAMJ0Ap9OQDuAAAuAAQKfx4AAgEACAm7H4MpAM0CAAEACAm7H4MpAM0CAAAA.',
Ri='Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgADCgkJCgAAAA==.',
Ry='Ryzen:BAAALgAECgYJBwAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgYJBgAAAA==.Scrufies:BAAALgAECgYJDgAAAA==.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgADCgYJDgAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAAALgAECgYJEAAAAA==.Shamncheese:BAAALgAECgQJCQAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8KAAIJAAQJGSIGAQCVAQAJAAQJGSIGAQCVAQAuAAQKfycAAgkACAlqJXABAEEDAAkACAlqJXABAEEDAAAA.Shisuiuchiha:BAAALgAECgMJAwAAAA==.Shuhari:BAAALgAECgkJDgAAAQ==.',
Si='Siilas:BAABLgAECn8dAAMUAAgJyw6EMwBdAQAUAAgJyw6EMwBdAQAVAAQJSAf+QACxAAAAAA==.Sinamon:BAABLgAECn8fAAIGAAcJzSDhGQDvAQAGAAcJzSDhGQDvAQAAAA==.Sinani:BAABLgAECn8UAAIBAAcJAgShggDOAAABAAcJAgShggDOAAAAAA==.Sinnamon:BAAALgAECgYJBwABLgAECgcJHwAGAM0gAA==.',
Sj='Sjdh:BAAALgAECgcJBQAAAA==.Sjrogue:BAABLgAECn8mAAIaAAgJ6RNcCgDDAQAaAAgJ6RNcCgDDAQAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgIJAwAAAA==.',
Sl='Slammydooker:BAABLgAECn8XAAMaAAgJWhXvCADdAQAaAAgJWhXvCADdAQAbAAEJ1QcJIQAtAAAAAA==.Sleeptoken:BAAALgAECgMJBQAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgADCgUJBgAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgEJAQAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgUJBgAAAA==.',
Sp='Sprayandpray:BAAALgAECgMJAgAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAAALgAFFAIJAgAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8hAAIOAAgJsQnPJQCCAQAOAAgJsQnPJQCCAQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAgAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgADCgMJAwAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sunpali:BAAALgAECgQJBQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacodaboss:BAAALgAECgUJDQAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8dAAIgAAgJXxujBwB3AgAgAAgJXxujBwB3AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Taupo:BAABLgAECn8fAAIXAAgJhh+lDQB6AgAXAAgJhh+lDQB6AgAAAA==.',
Tb='Tbanger:BAAALgADCgYJBgAAAA==.Tbh:BAAALgADCgcJBwABLgAFFAEJAQACAAAAAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8aAAIkAAgJUhF6AQDIAQAkAAgJUhF6AQDIAQAAAA==.Techsmexx:BAAALgAECgIJAwAAAA==.Tenebron:BAAALgAECgQJDAAAAA==.Tenlucis:BAAALgAECgIJAgAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAAALgAECgYJEgAAAA==.Thecanmurk:BAAALgADCgYJBgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJBAAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8KAAIdAAUJ+BGfAQBWAQAdAAUJ+BGfAQBWAQAuAAQKfy0AAx0ACQmOIhEDAA4DAB0ACQlGIhEDAA4DAAkABwmzHjkDABYCAAAA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAABLgAFFH8IAAIQAAMJqRhKMQD/AAAQAAMJqRhKMQD/AAABLgAFFAUJCgAdAPgRAA==.Thórin:BAAALgAECgcJCAAAAA==.',
Ti='Tipsy:BAABLgAECn8VAAIcAAgJgQekJABFAQAcAAgJgQekJABFAQAAAA==.',
To='Tomfoolary:BAAALgADCgEJAQAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Total:BAAALgADCgkJDAAAAA==.',
Tr='Tralleth:BAABLgAECn8UAAIPAAYJQRGRIgDwAAAPAAYJQRGRIgDwAAAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgADCgkJDgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgQJBAAAAA==.',
Tw='Twinklord:BAAALgAECgYJCwAAAA==.',
Ty='Tylolight:BAAALgADCgMJAwAAAA==.Tylototem:BAAALgAECgYJDgAAAA==.',
Ug='Uglyboi:BAAALgAECgcJCAAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8WAAIHAAgJaQ+/EQB5AQAHAAgJaQ+/EQB5AQAAAA==.Urk:BAAALgAECgYJBgAAAA==.',
Ut='Uthur:BAAALgADCgYJCgAAAA==.',
Va='Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAAALgAECggJDgAAAA==.Vape:BAAALgAECgQJBwAAAA==.',
Ve='Veinripp:BAAALgADCgUJBQAAAA==.Velarael:BAAALgAECgYJEwAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAAALgAECgYJDwAAAA==.Velian:BAAALgADCgMJBAAAAA==.Verdesalsa:BAAALgADCgQJBAAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAAALgAECgQJCAAAAA==.',
Vi='Vicv:BAABLgAECn8PAAIHAAgJSAwRNABIAQAHAAgJSAwRNABIAQAAAA==.',
Wa='Wachonaso:BAABLgAECn8jAAMUAAcJMR+dNAA5AgAUAAcJFx6dNAA5AgAVAAUJkBxaFwCPAQAAAA==.Wanbahl:BAAALgADCgMJAwAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8IAAIUAAMJuR3lPACxAAAUAAMJuR3lPACxAAAuAAQKfxwAAxQABwn6IaE5ACUCABQABwn6IaE5ACUCABUAAgm6Dh9SAHcAAAAA.',
Wi='Wildthree:BAABLgAECn8VAAMYAAYJKR2HDACuAQAYAAYJKR2HDACuAQAlAAMJ2RQoYgC5AAAAAA==.Willenda:BAAALgADCgYJBgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8FAAIhAAMJHyMtBgA6AQAhAAMJHyMtBgA6AQAuAAQKfzMAAiEACAneJeMAAEwDACEACAneJeMAAEwDAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBQAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJCQANAOcRAA==.Wut:BAAALgADCgcJBwAAAA==.',
['Wõ']='Wõnderful:BAAALgAECgMJAwABLgAFFAMJBQAQAGwVAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgADCgkJGgAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yahro:BAABLgAECn8eAAIGAAgJoxugJgCLAgAGAAgJoxugJgCLAgAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJAQAAAA==.Zalind:BAAALgAECggJEQAAAA==.Zalvianna:BAAALgAECgEJBAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAIJBQAEAKwaAA==.Zilongmage:BAAALgAFFAEJAQAAAA==.Zinnia:BAAALgADCgEJAQAAAA==.',
Zo='Zonedk:BAAALgAECgQJBwAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgQJBwACAAAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgADCgEJAQABLgAECggJHwAXAIYfAA==.',
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

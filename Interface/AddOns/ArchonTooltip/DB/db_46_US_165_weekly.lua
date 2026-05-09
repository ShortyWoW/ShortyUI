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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Evoker-Augmentation','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Druid-Feral','Paladin-Protection','Paladin-Holy','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8iAAIBAAcJdRe5OgC4AQABAAcJdRe5OgC4AQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECgcJEAACAAAAAA==.Acslater:BAAALgAECgMJAwAAAA==.Actionman:BAAALgAECgkJBgAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8LAAIDAAQJEx4NCgBaAQADAAQJEx4NCgBaAQAuAAQKfxYAAgMACAncI5AEAFIDAAMACAncI5AEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAECggJEAAAAA==.Aissae:BAACLgAFFH8NAAIEAAQJ7hymDwB5AQAEAAQJ7hymDwB5AQAuAAQKfyQAAgQACAlAJHYLACYDAAQACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAgAAAA==.Aliasx:BAAALgAECgIJAgAAAA==.Alphrank:BAAALgAECgEJAQAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBgAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgIJAgAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthasl:BAAALgADCgIJAgAAAA==.Arthur:BAAALgAECgQJCQAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgEJAQAAAA==.',
Au='Augonly:BAACLgAFFH8SAAIFAAQJrBV9DQA6AQAFAAQJrBV9DQA6AQAuAAQKfyMAAgUACQnpIC0GAOECAAUACQnpIC0GAOECAAAA.Augy:BAAALgAFFAIJAgAAAA==.Autoshot:BAAALgAECgQJBQAAAA==.',
Av='Averisbelia:BAAALgADCgIJAgAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECgQJCAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgIJAgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8UAAIGAAgJ7g8RGgBsAQAGAAgJ7g8RGgBsAQAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECgMJAwAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIHAAkJDRFNNACsAQAHAAkJDRFNNACsAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAAALgAFFAIJAwAAAA==.',
Be='Beastlieduke:BAAALgADCgUJCQABLgAFFAQJCgAGAJUKAA==.Beastlièduke:BAACLgAFFH8KAAIGAAQJlQpAEQABAQAGAAQJlQpAEQABAQAuAAQKfygAAgYACAm2HvAOAJQCAAYACAm2HvAOAJQCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAIIAAkJjA9aDAAmAQAIAAkJjA9aDAAmAQAAAA==.Berenstain:BAABLgAECn8fAAIJAAgJ1hIGDQA9AQAJAAgJ1hIGDQA9AQAAAA==.Bergmire:BAAALgAECgMJBAAAAA==.Berple:BAAALgADCgUJBQABLgAFFAUJEQABAMwiAA==.Bestoresto:BAAALgAECggJEAAAAA==.',
Bh='Bhori:BAAALgAECgEJAQAAAA==.',
Bi='Bibahabibi:BAABLgAECn8WAAMKAAYJBxOyGgAdAQAKAAYJBxOyGgAdAQALAAMJzQiMhwChAAAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8lAAMKAAgJzxr2BAAtAgAKAAgJzxr2BAAtAgALAAIJ3gcumQBcAAAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJGgAMAEQjAA==.',
Bl='Blabbybootze:BAAALgADCgEJAQAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQANAIIkAA==.Blightfangs:BAABLgAECn8jAAIBAAgJFxCPUAB5AQABAAgJFxCPUAB5AQAAAA==.Blindnautdef:BAABLgAECn8pAAIEAAgJmRDoMwBmAQAEAAgJmRDoMwBmAQAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgADCgEJAQAAAA==.Bodakye:BAABLgAECn8aAAMOAAgJ0BzDMwDgAQAOAAgJ0BzDMwDgAQAIAAIJtAEKgQBDAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgADCgMJAwAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECggJCAAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAAALgAECggJEwAAAA==.Butane:BAAALgADCgIJAgAAAA==.',
Ca='Cainn:BAAALgAECgYJBgAAAA==.Cap:BAAALgADCgEJAQABLgAFFAMJCAABAMkYAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn8fAAIEAAkJOA7BKwCIAQAEAAkJOA7BKwCIAQAAAA==.Chapelgnome:BAAALgAECgIJAgABLgAECggJJQAPAPYPAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chipmonkey:BAAALgADCgMJAwABLgAECggJHgANAJ4NAA==.Chiptime:BAABLgAECn8eAAINAAgJng1BPAAjAQANAAgJng1BPAAjAQABLgAECggJHgANAJ4NAA==.Chomby:BAAALgAECgEJAQAAAA==.Chriifrio:BAAALgADCgQJBAAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJBgAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJAwAAAA==.',
Ci='Cinnamóróll:BAABLgAECn8WAAIQAAgJOAbnFABtAQAQAAgJOAbnFABtAQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8eAAMRAAgJlBIUOgCRAQARAAgJlBIUOgCRAQASAAEJpwMSGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8FAAMTAAQJ3gedFgDOAAATAAQJ3gedFgDOAAAUAAEJrA5JIABJAAAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMNAAgJgiSKBAAXAwANAAgJgiSKBAAXAwAVAAEJTwULgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgQJBAAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Cutestxx:BAAALgAECgcJBwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAgACAAAAAA==.',
Da='Daftxshade:BAAALgAECgQJBAAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDAAAAA==.Darkcrusader:BAAALgAECgYJCQAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgADCgcJCQAAAA==.Darthsyde:BAAALgAECgMJAwAAAA==.Dasdk:BAAALgAFFAIJAwAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAIJAwACAAAAAA==.',
De='Deadergriff:BAAALgAECgYJCgAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAQAAAA==.Deadicated:BAAALgAECgYJDwAAAA==.Deadsies:BAAALgADCgIJAgABLgAECgUJCQACAAAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwARAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAAALgAECgUJBQAAAA==.Desunaito:BAACLgAFFH8SAAISAAUJpiA8AACGAQASAAUJpiA8AACGAQAuAAQKfyIAAhIACQkxJbQAADkDABIACQkxJbQAADkDAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8KAAIEAAUJWBOOKAAPAQAEAAUJWBOOKAAPAQAuAAQKfxsAAwQACAlHIUc4ABQCAAQABwkMIEc4ABQCABYABQmNJI0eAMoBAAAA.',
Di='Diddlefiddle:BAAALgAECgQJBQAAAA==.Dihcum:BAAALgAECgEJAQAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinpala:BAAALgADCgUJBQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJAgABLgAFFAUJCgAEAFgTAA==.',
Do='Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8WAAMXAAgJnxFsNwCHAQAXAAgJnxFsNwCHAQAYAAEJtgLKcgAzAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAAALgAECgYJCAAAAA==.Dormist:BAAALgADCgMJAwABLgAECgkJFQAYAE8SAA==.',
Dr='Dracnogard:BAAALgAECgYJCgAAAA==.Dracowulf:BAAALgAECgcJDwAAAA==.Dragonx:BAABLgAECn8gAAIOAAgJBw7mQwCgAQAOAAgJBw7mQwCgAQAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn8fAAIZAAcJpANwDADMAAAZAAcJpANwDADMAAAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAAALgAFFAMJAwAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8mAAIHAAkJlBNjGwAkAgAHAAkJlBNjGwAkAgAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAAALgAFFAMJAwAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8VAAMYAAkJTxKHBQCkAQAYAAgJLxOHBQCkAQAaAAMJ3w/bCwDLAAAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ef='Effloria:BAAALgAECgkJEwAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
El='Elegia:BAACLgAFFH8NAAIXAAUJrw3DLAAVAQAXAAUJrw3DLAAVAQAuAAQKfycAAxcACQlJGyAZAL4CABcACQlJGyAZAL4CABgAAQkAAP5lAEMAAAAA.Elerianor:BAAALgAECgYJDQAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.Elsocio:BAAALgADCgEJAQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJBwAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Enjoi:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8fAAQMAAcJCx1cCwCpAQAMAAYJnBtcCwCpAQAEAAUJ0xOuUAAHAQAWAAEJ4RABcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJDwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJDgAAAA==.Evoextoons:BAAALgADCgYJDAAAAA==.',
Fa='Fallen:BAAALgAECgYJDgAAAA==.Fallingvoid:BAABLgAECn9gAAIEAAkJJiQZAgC3AwAEAAkJJiQZAgC3AwAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIEAAYJVBUsPwA8AQAEAAYJVBUsPwA8AQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgADCgEJAQAAAA==.',
Fe='Fellbian:BAAALgADCgcJCwAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAABLgAECn8rAAIIAAgJ5hzoAgA7AgAIAAgJ5hzoAgA7AgAAAA==.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAABLgAECn8pAAIHAAgJMCIeEQByAgAHAAgJMCIeEQByAgAAAA==.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIEAAcJKx82KQBdAgAEAAcJKx82KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAAALgAECgYJEwAAAA==.',
Fo='Forsight:BAABLgAECn8XAAIRAAgJVxTNPQCEAQARAAgJVxTNPQCEAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAABLgAECn8qAAMTAAgJER2xDACHAgATAAgJER2xDACHAgAUAAIJRSDDMQC9AAAAAA==.Fremder:BAACLgAFFH8HAAIFAAMJWxR0EQD9AAAFAAMJWxR0EQD9AAAuAAQKfyQAAgUACAk6HLkJAL8BAAUACAk6HLkJAL8BAAAA.Fresher:BAABLgAECn8VAAIRAAUJyxylVgA7AQARAAUJyxylVgA7AQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgYJCgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAABLgAECn8bAAIBAAcJbhBnUQB2AQABAAcJbhBnUQB2AQAAAA==.',
Fu='Funeral:BAACLgAFFH8bAAMYAAcJLBo8AQB/AQAYAAQJtx08AQB/AQAXAAMJFhNwMACyAAAuAAQKfysABBgACQkzIz4EAKECABgABwnSID4EAKECABcACAngGOREAP0BABoAAQkIE38pAEwAAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gi='Gimmedatmouf:BAAALgAFFAMJAwAAAA==.Gimmedatneck:BAABLgAECn8VAAMbAAgJTSMDDwC0AQAbAAgJTSMDDwC0AQAcAAEJNhLdHABDAAAAAA==.Gingy:BAAALgADCgYJCwAAAA==.',
Gl='Glead:BAAALgAECggJEwAAAA==.',
Gn='Gneeduh:BAAALgAECgEJAQAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJBQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgEJAQAAAA==.Grastim:BAAALgAECgQJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAABLgAECn8nAAIdAAgJWhKVIgCgAQAdAAgJWhKVIgCgAQAAAA==.Gripopotamus:BAAALgADCgYJBwAAAA==.Gristle:BAAALgADCgkJFQAAAA==.',
Gu='Gunner:BAAALgAECgQJBQABLgAECgQJCgACAAAAAA==.',
Ha='Hakaishaz:BAAALgADCgMJAwAAAA==.Halfwatt:BAAALgAECgQJBwAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8ZAAIHAAgJ/BM7OwCUAQAHAAgJ/BM7OwCUAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8aAAMMAAkJRCNNAACDAwAMAAkJRCNNAACDAwAWAAQJJRB2PwD+AAAAAA==.Haru:BAAALgAECgYJDwAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAABLgAECn8XAAIJAAkJRRLIDQCmAQAJAAkJRRLIDQCmAQAAAA==.Havokvacano:BAAALgAECggJEgAAAA==.',
He='Healmachine:BAAALgAECgIJAgAAAA==.Hellbrringer:BAAALgAECgQJBAAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8eAAIXAAgJKgiQUQA2AQAXAAgJKgiQUQA2AQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8IAAIRAAMJaRW1UgDpAAARAAMJaRW1UgDpAAAuAAQKfzEAAhEACAlyIBMQAH4CABEACAlyIBMQAH4CAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgEJAQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJDQAAAA==.',
Ir='Iridellis:BAAALgAECgcJDgAAAA==.',
Is='Ispankutank:BAAALgADCgQJBAAAAA==.',
It='Itssofluffy:BAABLgAECn8fAAQeAAgJjBSJCwBgAQAeAAgJQRKJCwBgAQAJAAUJBhfZEwAyAQAVAAIJUgmyWAAxAAAAAA==.Itwon:BAAALgADCgcJEwAAAA==.',
Iz='Izzelda:BAAALgADCgQJBAAAAA==.',
Ja='Jacus:BAAALgAECgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Jaycers:BAABLgAECn8bAAMfAAkJFB/kAQCuAgAfAAkJFB/kAQCuAgAgAAEJ2AL+ngAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAAALgAECgYJDAAAAA==.Jokestarfist:BAAALgAECgQJDwAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
Ka='Kaitokit:BAAALgAECgUJCQAAAA==.Kajamando:BAABLgAECn8eAAIWAAgJ7gf3FQA4AQAWAAgJ7gf3FQA4AQAAAA==.Kalith:BAABLgAECn8WAAIQAAgJ+wIjHwAHAQAQAAgJ+wIjHwAHAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8UAAIRAAgJowOUYwAdAQARAAgJowOUYwAdAQAAAA==.Kayotic:BAABLgAECn8aAAIWAAYJGgX7IgDEAAAWAAYJGgX7IgDEAAAAAA==.Kayww:BAAALgAECgIJAgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8VAAIMAAkJkRsuAgBmAgAMAAkJkRsuAgBmAgAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJAQAAAA==.',
Ki='Kikiana:BAAALgAECgQJBwABLgAECggJJQAhAKUhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAAALgAECgcJEQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8XAAIEAAgJ7hWnXgCFAQAEAAgJ7hWnXgCFAQAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8VAAMLAAcJxxwXPQCwAQALAAcJnxoXPQCwAQAKAAQJyxO5IgCsAAAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMRAAcJsRf+XADbAQARAAcJsRf+XADbAQASAAEJsxBdFgAzAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgADCgUJBQAAAA==.',
La='Lackluster:BAABLgAECn8fAAIBAAgJTQn2fwASAQABAAgJTQn2fwASAQAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgMJBAAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Le='Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.',
Li='Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAAALgAECgQJCAAAAA==.Liore:BAAALgAECgMJAwAAAA==.Lisathe:BAAALgAECgQJBQAAAA==.Littledude:BAAALgADCgMJAwAAAA==.Littlemorsel:BAAALgAECgkJDgAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8ZAAIgAAUJcw5EMwACAQAgAAUJcw5EMwACAQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchn:BAABLgAECn8gAAIBAAkJswb7XABaAQABAAkJswb7XABaAQAAAA==.',
['Lú']='Lúná:BAAALgAECgUJBgAAAA==.',
Ma='Maggieaugers:BAABLgAECn8lAAIPAAgJ9g9WFQCaAQAPAAgJ9g9WFQCaAQAAAA==.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECgcJEAAAAA==.Mahnon:BAAALgAECggJEwAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAAALgAECgQJBwAAAA==.Matias:BAAALgAECgEJAQAAAA==.',
Me='Metalhedface:BAABLgAECn8YAAMKAAgJaBE1DAB+AQAKAAcJ5hM1DAB+AQALAAUJ4BC2ZAAgAQAAAA==.',
Mi='Mikecoxwall:BAABLgAECn8oAAMBAAkJcg33LwDhAQABAAkJcg33LwDhAQAiAAYJ3wj7CgAqAQAAAA==.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgADCgEJAQAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Misary:BAAALgAECgQJBAAAAA==.Mischeif:BAAALgAECgIJAgAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAAALgADCgcJDAAAAA==.Monkeli:BAAALgAECgcJDQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAUJDAAeAPYSAA==.Monkup:BAAALgAECgEJAQAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8LAAIQAAQJHgN0DQALAQAQAAQJHgN0DQALAQAuAAQKfyAAAxAACAleE1sOAOEBABAACAleE1sOAOEBAAgAAQmqAVqZABwAAAAA.Moosafur:BAABLgAECn8bAAMJAAkJdxz8AgBzAgAJAAcJzCT8AgBzAgAeAAIJeQPFNQAuAAAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Morphyr:BAAALgADCgIJAgAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgQJBgAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgQJBgAAAA==.',
My='Myraine:BAAALgADCgYJBgAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8ZAAMLAAcJ/xIhKgAtAQALAAYJwhEhKgAtAQAKAAEJLxmYNQBKAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAECggJFwAdAN8UAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn8dAAIjAAYJExdQDABFAQAjAAYJExdQDABFAQAAAA==.Natureboyy:BAAALgADCgUJBQAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAUJEgASAKYgAA==.Nellaa:BAAALgAECgcJCgAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8rAAIGAAkJOhwwCQAzAgAGAAkJOhwwCQAzAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBbzOQC7AQABAAgJGBbzOQC7AQAAAA==.',
Nu='Nutellaa:BAAALgAECgQJDgAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obie:BAAALgAECgUJBgAAAA==.Oborax:BAEBLgAECn8VAAIHAAYJ2BVNTwBYAQAHAAYJ2BVNTwBYAQAAAA==.',
Od='Od:BAAALgAECgMJBAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIHAAgJORnRKwB0AgAHAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8WAAIbAAcJjwUUIQDzAAAbAAcJjwUUIQDzAAAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECgcJCwAAAA==.',
Pe='Perelia:BAABLgAECn8gAAIkAAcJrAudGABvAQAkAAcJrAudGABvAQAAAA==.Pewpewqt:BAAALgAECgEJAQABLgAECgcJJQANACMZAA==.',
Pl='Plaguehammer:BAABLgAECn8VAAIRAAYJtwcZdQD3AAARAAYJtwcZdQD3AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Popcola:BAAALgADCgEJAQAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAAALgAECgYJCQAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAQJBQATAN4HAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJCgACAAAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJCQAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgUJBQABLgAECgcJDQACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJCwAAAA==.Raevalinaa:BAAALgAECgMJBgABLgAECgcJGwABAG4QAA==.Raevelinaa:BAAALgAECgIJAwABLgAECgcJGwABAG4QAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAAALgAECgYJEQAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn8gAAMGAAkJ4RVpCgAeAgAGAAkJ4RVpCgAeAgAkAAEJdx34PQBUAAAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAAALgAECgYJCwAAAA==.Rezz:BAACLgAFFH8MAAIBAAQJ7gnxNgA1AQABAAQJ7gnxNgA1AQAuAAQKfx4AAgEACAm7H4IpAM0CAAEACAm7H4IpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgADCgkJCgAAAA==.',
Ry='Ryzen:BAAALgAECgYJBwAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgYJBgAAAA==.Scrufies:BAAALgAECgcJEQAAAA==.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgADCgYJDgAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8XAAIDAAcJeB6TDAATAgADAAcJeB6TDAATAgAAAA==.Shamncheese:BAAALgAECgYJDAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8OAAIJAAQJHiKKAQCSAQAJAAQJHiKKAQCSAQAuAAQKfygAAgkACAlaJW8BAEEDAAkACAlaJW8BAEEDAAAA.Shioz:BAAALgADCgQJBQAAAA==.Shisuiuchiha:BAAALgAECgMJAwAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEAAAAQ==.',
Si='Siilas:BAACLgAFFH8KAAQXAAQJEgXdVwCaAAAXAAMJlgHdVwCaAAAaAAEJhw/NCABRAAAYAAIJ7QBFFwA9AAAuAAQKfyEAAxcACQlvDgkpAMIBABcACQlvDgkpAMIBABgABAlQB/9AALEAAAAA.Sinamon:BAABLgAECn8jAAIHAAcJGyHfIAAFAgAHAAcJGyHfIAAFAgAAAA==.Sinani:BAABLgAECn8UAAIBAAcJAgSvowDMAAABAAcJAgSvowDMAAAAAA==.Sinista:BAAALgADCgkJCQAAAA==.Sinnamon:BAAALgAECgYJDAABLgAECgcJIwAHABshAA==.',
Sj='Sjdh:BAAALgAECggJEQAAAA==.Sjrogue:BAABLgAECn8mAAIbAAgJ6RMlDwCyAQAbAAgJ6RMlDwCyAQAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgIJAwAAAA==.',
Sl='Slammydooker:BAABLgAECn8ZAAMbAAkJlhVOCAAhAgAbAAkJlhVOCAAhAgAcAAEJ1QcJIQAtAAAAAA==.Sleeptoken:BAAALgAECgMJBQAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgADCgUJBgAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAAALgAECgQJBAAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAABLgAFFH8HAAIYAAMJ6gCcCQCXAAAYAAMJ6gCcCQCXAAAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8jAAIOAAgJDAqANgBzAQAOAAgJDAqANgBzAQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAgAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgADCgMJAwAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sunpali:BAAALgAECgUJBgAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacodaboss:BAAALgAECgUJDwAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8dAAIQAAgJXhujBwB3AgAQAAgJXhujBwB3AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Taupo:BAACLgAFFH8HAAITAAMJIBxTEwD8AAATAAMJIBxTEwD8AAAuAAQKfyEAAhMACAkfIKUNAHoCABMACAkfIKUNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgQJBQAAAA==.Tbh:BAAALgADCgcJBwABLgAFFAQJBQATAN4HAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8jAAIlAAkJ9hqAAAChAgAlAAkJ9hqAAAChAgAAAA==.Techsmexx:BAAALgAECgIJAwAAAA==.Tenebron:BAABLgAECn8XAAImAAYJPRHsFgALAQAmAAYJPRHsFgALAQAAAA==.Tenlucis:BAAALgAECgYJCAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8ZAAMNAAcJ/BR7UgBcAQANAAcJ/BR7UgBcAQAVAAUJmg5eMADRAAAAAA==.Thecanmurk:BAAALgADCgcJDQAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJBQAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8MAAIeAAUJ9hKfAQBWAQAeAAUJ9hKfAQBWAQAuAAQKfy0AAx4ACQmOIhEDAA4DAB4ACQlEIhEDAA4DAAkABwm8HgIFABgCAAAA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAABLgAFFH8IAAIRAAMJphiCTAD2AAARAAMJphiCTAD2AAABLgAFFAUJDAAeAPYSAA==.Thórin:BAAALgAECgcJCAAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8YAAIdAAkJmgliJQCPAQAdAAkJmgliJQCPAQAAAA==.',
To='Tomfoolary:BAAALgAECgEJAQAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgADCgYJBgABLgAECggJDwACAAAAAA==.',
Tr='Tralleth:BAABLgAECn8ZAAMPAAYJQhFxKAAOAQAPAAYJQhFxKAAOAQAFAAEJGggMKQAxAAAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgQJBQAAAA==.',
Tu='Tuskor:BAAALgADCgEJAQAAAA==.',
Tw='Twinklord:BAAALgAECgcJDAAAAA==.',
Ty='Tylolight:BAAALgADCgMJAwAAAA==.Tylototem:BAAALgAECgcJDwAAAA==.',
Ug='Uglyboi:BAAALgAECggJCQAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8YAAIGAAgJdA/zGQBsAQAGAAgJdA/zGQBsAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAAALgAECggJDgAAAA==.Vape:BAAALgAECgQJCgAAAA==.',
Ve='Veinripp:BAAALgADCgUJBQAAAA==.Velarael:BAABLgAECn8aAAIXAAYJlAq5bgDtAAAXAAYJlAq5bgDtAAAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAAALgAECgYJDwAAAA==.Velian:BAAALgADCgMJBAAAAA==.Verdesalsa:BAAALgAECgUJBgAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAAALgAECgUJDgAAAA==.',
Vi='Vicv:BAABLgAECn8PAAIGAAgJSAwSNABIAQAGAAgJSAwSNABIAQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8IAAIXAAQJlw3QNAD+AAAXAAQJlw3QNAD+AAAuAAQKfygAAxcABwlJH7ggAOwBABcABwkwHrggAOwBABgABgnIHFcXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8MAAMXAAQJIhuiHgA7AQAXAAQJIhuiHgA7AQAaAAEJRQdgCgBHAAAuAAQKfyAAAxcACAmQICorALgBABcACAmQICorALgBABgAAgm6Dh5SAHcAAAAA.',
Wi='Wildthree:BAABLgAECn8WAAMUAAcJoBxSDAD0AQAUAAcJoBxSDAD0AQAnAAMJ2RQqYgC5AAAAAA==.Willenda:BAAALgADCgYJBgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8JAAIhAAQJ8CK8AwCdAQAhAAQJ8CK8AwCdAQAuAAQKfzcAAiEACAnjJbQBAEQDACEACAnjJbQBAEQDAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBQAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJCgANAOYRAA==.Wut:BAAALgADCgcJBwAAAA==.',
['Wõ']='Wõnderful:BAAALgAFFAEJAQABLgAFFAMJCAARAGkVAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJBwAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yahro:BAACLgAFFH8FAAIHAAIJ7BHnQwClAAAHAAIJ7BHnQwClAAAuAAQKfyIAAgcACAmjG54mAIsCAAcACAmjG54mAIsCAAAA.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgMJAwAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJAgAAAA==.Zalind:BAAALgAECggJEQAAAA==.Zalvianna:BAAALgAECgQJCAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJCgAEAFgTAA==.Zilongmage:BAAALgAFFAEJAgAAAA==.Zilongwar:BAAALgAFFAEJAQAAAA==.Zinnia:BAAALgADCgEJAQAAAA==.',
Zo='Zonedk:BAAALgAECgUJDQAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgUJDQACAAAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgADCgEJAQABLgAFFAMJBwATACAcAA==.',
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

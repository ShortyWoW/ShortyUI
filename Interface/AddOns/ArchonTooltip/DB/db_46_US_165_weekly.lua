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

local lookup = {'Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','Evoker-Augmentation','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Druid-Feral','Paladin-Protection','Paladin-Holy','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Mage-Fire','Priest-Holy',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8WAAIBAAcJYBG9HgBcAQABAAcJYBG9HgBcAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJAwACAAAAAA==.',
Ac='Ackerman:BAAALgAECgQJBAABLgAECgcJEAACAAAAAA==.Acslater:BAAALgADCgYJCwAAAA==.',
Ag='Agoobagoo:BAAALgAFFAQJBAAAAA==.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAECgcJCwAAAA==.Aissae:BAACLgAFFH8HAAIDAAMJbhrGFwASAQADAAMJbhrGFwASAQAuAAQKfyIAAgMACAntI3cLACYDAAMACAntI3cLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgADCgcJCQAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgQJBAAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgIJAgAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthur:BAAALgAECgQJCAAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgIJAwAAAA==.',
Au='Augonly:BAACLgAFFH8JAAIEAAMJqwv7BQDcAAAEAAMJqwv7BQDcAAAuAAQKfyEAAgQACAmoIC0GAOECAAQACAmoIC0GAOECAAAA.',
Av='Averisbelia:BAAALgADCgIJAgAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECgQJCAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQAAAA==.Balthasar:BAAALgAECgYJEQAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECgEJAQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8ZAAIFAAcJvxI7YQDBAQAFAAcJvxI7YQDBAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAAALgAECgQJBwAAAA==.',
Be='Beastlieduke:BAAALgADCgUJCQABLgAECggJIAAGALYcAA==.Beastlièduke:BAABLgAECn8gAAIGAAgJthzvDgCUAgAGAAgJthzvDgCUAgAAAA==.Beauslay:BAAALgADCgIJAgAAAA==.Belephon:BAAALgAECgUJCQAAAA==.Bellaruhbz:BAABLgAECn8cAAIHAAkJjA6zBABEAQAHAAkJjA6zBABEAQAAAA==.Berenstain:BAABLgAECn8aAAIIAAgJHhI9BABBAQAIAAgJHhI9BABBAQAAAA==.Berple:BAAALgADCgUJBQABLgAFFAQJCwABAFAiAA==.Bestoresto:BAAALgAECgcJBwAAAA==.',
Bi='Bibahabibi:BAAALgAECgYJDgAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8WAAMJAAYJ+RqKDADYAQAJAAYJ+RqKDADYAQAKAAIJ3gcamQBcAAAAAA==.Binggus:BAAALgAECgMJAwABLgAECgkJGgALAEQjAA==.',
Bl='Blabbybootze:BAAALgADCgEJAQAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJHwAMAKciAA==.Blightfangs:BAABLgAECn8aAAIBAAcJCxCtIgBHAQABAAcJCxCtIgBHAQAAAA==.Blindnautdef:BAABLgAECn8ZAAIDAAgJ5QtwWwCPAQADAAgJ5QtwWwCPAQAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgADCgEJAQAAAA==.Bodakye:BAAALgAECgYJEwAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.',
Br='Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAAALgAECgYJDAAAAA==.Butane:BAAALgADCgIJAgAAAA==.',
Ca='Cap:BAAALgADCgEJAQAAAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgADCgQJBQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn8ZAAIDAAcJvw7KGgArAQADAAcJvw7KGgArAQAAAA==.Chapelgnome:BAAALgADCgcJDAABLgAECgcJGAANAAUQAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgUJCwAAAA==.Chiptime:BAABLgAECn8eAAIMAAgJkg1eEgA6AQAMAAgJkg1eEgA6AQABLgAECggJHgAMAJINAA==.Chomby:BAAALgADCgUJBwAAAA==.Chriifrio:BAAALgADCgQJBAAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgMJAwAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJAwAAAA==.',
Ci='Cinnamóróll:BAAALgAECgYJBwAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAAALgAECgcJDwAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECggJCAAAAA==.Cocoon:BAAALgAECgUJBgABLgAECgYJCQACAAAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Corita:BAAALgAECgIJAgAAAA==.Cowhealer:BAABLgAECn8fAAMMAAgJpyJpCAAIAwAMAAgJpyJpCAAIAwAOAAEJTwX6gAAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.',
Cu='Cutestxx:BAAALgAECgcJAQAAAA==.',
Cy='Cyraxis:BAAALgADCgYJBgAAAA==.Cyxo:BAAALgADCgEJAQAAAA==.',
Da='Daftxshade:BAAALgAECgMJAwAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJBAAAAA==.Darkcrusader:BAAALgAECgYJBgAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkshields:BAAALgADCgEJAQAAAA==.Daspriest:BAAALgADCgYJDQAAAA==.',
De='Deadergriff:BAAALgAECgQJBwAAAA==.Deadhippycb:BAAALgAECgEJAQAAAA==.Deadhippyxy:BAAALgAECgEJAQAAAA==.Deadicated:BAAALgAECgYJCAAAAA==.Deadsies:BAAALgADCgIJAgABLgAECgUJCAACAAAAAA==.Delan:BAAALgADCgQJBAAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAPAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Desunaito:BAACLgAFFH8JAAIQAAQJwRw7AACGAQAQAAQJwRw7AACGAQAuAAQKfx8AAhAACAnrI7QAADkDABAACAnrI7QAADkDAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAABLgAECn8bAAMDAAgJCiFNOAAUAgADAAcJxB9NOAAUAgARAAUJjSSMHgDKAQAAAA==.',
Di='Diddlefiddle:BAAALgAECgIJAgAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dirtycow:BAAALgAECgMJAwAAAA==.',
Dk='Dkzilong:BAAALgAFFAEJAQABLgAECggJGwADAAohAA==.',
Do='Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8WAAMSAAgJnBHFDgCcAQASAAgJnBHFDgCcAQATAAEJtgLFcgAzAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAQAAAA==.Dorlanlemeth:BAAALgADCggJDQAAAA==.',
Dr='Dracnogard:BAAALgAECgMJAwAAAA==.Dracowulf:BAAALgAECgYJCAAAAA==.Dragonx:BAAALgAECgcJEQAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAAALgAECgYJEgAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAAALgAECgEJAQAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8ZAAIFAAgJ+govHwA0AQAFAAgJ+govHwA0AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAAALgADCgkJEgAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAAALgAECgcJDwAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ef='Effloria:BAAALgAECgcJDwAAAA==.',
El='Elegia:BAACLgAFFH8HAAISAAMJAwm1EQDiAAASAAMJAwm1EQDiAAAuAAQKfyMAAxIACQk+GyIZAL4CABIACQk+GyIZAL4CABMAAQkAAPdlAEMAAAAA.Elerianor:BAAALgAECgMJBwAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.',
En='Enash:BAAALgAECgQJBgAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8bAAQLAAcJCx1bCwCpAQALAAYJnBtbCwCpAQADAAIJlRYivQCIAAARAAEJ4RACcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJCgAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evoextoons:BAAALgADCgUJCAAAAA==.',
Fa='Fallen:BAAALgAECgUJDQAAAA==.Fallingvoid:BAABLgAECn9TAAIDAAkJqCOEAAAXAwADAAkJqCOEAAAXAwAAAA==.Fatchungus:BAAALgAECgcJBwABLgAFFAMJAwACAAAAAA==.Fatherben:BAAALgAECgQJEAAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgADCgEJAQAAAA==.',
Fe='Ferozz:BAABLgAECn8bAAIHAAgJnxMjKgDYAQAHAAgJnxMjKgDYAQAAAA==.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAABLgAECn8mAAIFAAgJ8R7KCQDvAQAFAAgJ8R7KCQDvAQAAAA==.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8YAAIDAAcJKx82KQBdAgADAAcJKx82KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAAALgAECgYJCwAAAA==.',
Fo='Forsight:BAABLgAECn8XAAIPAAgJTBQXDADCAQAPAAgJTBQXDADCAQAAAA==.',
Fr='Fracker:BAAALgAECgQJCAAAAA==.Frankzzorz:BAABLgAECn8nAAIUAAgJWBy7AwALAgAUAAgJWBy7AwALAgAAAA==.Fremder:BAABLgAECn8eAAIEAAgJuhosFAADAgAEAAgJuhosFAADAgAAAA==.Fresher:BAAALgAECgQJEAAAAA==.Freyjen:BAAALgADCgkJGAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgMJAwAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAAALgAECgYJDgAAAA==.',
Fu='Funeral:BAACLgAFFH8UAAMTAAYJrBrJAAAEAQATAAMJ5yHJAAAEAQASAAMJ0w+CFgCxAAAuAAQKfyUABBMACQlxH0AEAKECABMABwnSIEAEAKECABIACAkeFe1EAP0BABUAAQkIE34pAEwAAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gi='Gimmedatmouf:BAAALgAFFAMJAwAAAA==.Gimmedatneck:BAABLgAECn8VAAMWAAgJPyO2AwDbAQAWAAgJPyO2AwDbAQAXAAEJNhLcHABDAAAAAA==.Gingy:BAAALgADCgUJBQAAAA==.',
Gl='Glead:BAAALgAECggJDwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Gooklover:BAAALgADCggJCwAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgADCgUJBQAAAA==.Graegor:BAAALgADCgEJAQAAAA==.Grandmoo:BAAALgADCggJEgAAAA==.Grastim:BAAALgAECgQJBAAAAA==.Greenfanta:BAAALgADCgUJBQAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAABLgAECn8fAAIYAAgJnBHTCgCQAQAYAAgJnBHTCgCQAQAAAA==.Gripopotamus:BAAALgADCgQJBAAAAA==.Gristle:BAAALgADCgMJAwAAAA==.',
Gu='Gunner:BAAALgADCgYJDAABLgAECgQJBwACAAAAAA==.',
Ha='Hakaishaz:BAAALgADCgMJAwAAAA==.Halfwatt:BAAALgADCgkJEgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAAALgAECgcJDgAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8aAAMLAAkJRCNNAACDAwALAAkJRCNNAACDAwARAAQJJRBzPwD+AAAAAA==.Haru:BAAALgAECgYJDwAAAA==.Harvaal:BAAALgADCgQJBAAAAA==.Hasaro:BAABLgAECn8VAAIIAAgJRRPIDQCmAQAIAAgJRRPIDQCmAQAAAA==.Havokvacano:BAAALgAECgcJBwAAAA==.',
He='Healmachine:BAAALgADCgQJBAAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hotsordots:BAAALgAECggJCAAAAA==.Hounskul:BAAALgAECgcJEwAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBQAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAABLgAECn8oAAIPAAgJwRs+KQCVAgAPAAgJwRs+KQCVAgAAAA==.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJAwAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgIJAQAAAA==.',
Ir='Iridellis:BAAALgAECgYJDQAAAA==.',
It='Itssofluffy:BAABLgAECn8aAAQZAAcJvBVDEwB7AQAZAAcJCxNDEwB7AQAIAAUJBhfZEwAyAQAOAAIJWQnYIQA2AAAAAA==.Itwon:BAAALgADCgYJBgAAAA==.',
Ja='Jacus:BAAALgADCgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Jaycers:BAABLgAECn8ZAAMaAAgJNyDAAABzAgAaAAgJNyDAAABzAgAbAAEJ2ALgngAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAAALgAECgUJCQAAAA==.Jokestarfist:BAAALgAECgQJCAAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBAAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
Ka='Kaitokit:BAAALgAECgUJCAAAAA==.Kajamando:BAAALgAECgYJEAAAAA==.Kalith:BAAALgAECggJDwAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAAALgAECgcJDAAAAA==.Kayotic:BAAALgAECgYJEgAAAA==.Kayww:BAAALgADCgQJBAAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kelmorphic:BAAALgAECgcJDwAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Ki='Kikiana:BAAALgAECgIJAgAAAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAAALgAECgYJDAAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8aAAIDAAgJeBShDACvAQADAAgJeBShDACvAQAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAAALgAECgYJEgAAAA==.',
Kr='Krushgar:BAAALgAFFAEJAQAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.',
La='Lackluster:BAABLgAECn8WAAIBAAcJIAdDuQBuAQABAAcJIAdDuQBuAQAAAA==.Lamatrick:BAAALgAECgMJAwAAAA==.Lanadelslayy:BAAALgADCgIJAgAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Le='Lennon:BAAALgAECgkJBQAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.',
Li='Lilthin:BAAALgAECgEJAgAAAA==.Lisathe:BAAALgAECgEJAQAAAA==.Littledude:BAAALgADCgMJAwAAAA==.Littlemorsel:BAAALgAECgcJCAAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAAALgAECgQJDwAAAA==.Lurchn:BAAALgAECgUJCQAAAA==.',
['Lú']='Lúná:BAAALgAECgEJAQAAAA==.',
Ma='Maggieaugers:BAABLgAECn8YAAINAAcJBRAKNgAhAQANAAcJBRAKNgAhAQAAAA==.Magicmech:BAAALgADCgcJBwAAAA==.Magivacano:BAAALgAECgcJEAAAAA==.Mahnon:BAAALgAECgcJCwAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAAALgAECgQJBQAAAA==.',
Me='Metalhedface:BAAALgAECgUJCwAAAA==.',
Mi='Mightychi:BAAALgAECgQJCAAAAA==.Mikecoxwall:BAABLgAECn8fAAMBAAgJ3gmcIQBNAQABAAgJoAmcIQBNAQAcAAYJ3wj6CgAqAQAAAA==.Mikuru:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgADCgkJFgABLgADCgkJGAACAAAAAA==.Misary:BAAALgAECgQJBAAAAA==.',
Mo='Moltganus:BAAALgADCgUJBgAAAA==.Monkeli:BAAALgAECgUJBQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAQJBgAZADMMAA==.Moocifer:BAAALgADCgMJAwAAAA==.Moogrim:BAAALgADCgYJBwAAAA==.Moonsiand:BAACLgAFFH8FAAIdAAIJGAQ9BQCYAAAdAAIJGAQ9BQCYAAAuAAQKfxoAAx0ABwn2FFgOAOEBAB0ABwn2FFgOAOEBAAcAAQmqAUuZABwAAAAA.Moosafur:BAAALgAECgkJDQAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Morphyr:BAAALgADCgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgMJBQAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mx='Mx:BAAALgAECgEJAQAAAA==.',
My='Myway:BAAALgADCggJBwAAAA==.',
Na='Naari:BAAALgAECgUJDAAAAA==.Narexia:BAAALgAECgYJCwAAAA==.',
Ne='Nekuma:BAAALgAECgYJEAABLgAFFAQJCQAQAMEcAA==.Nellaa:BAAALgAECgcJCgAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8hAAIGAAgJ9RaFAwD6AQAGAAgJ9RaFAwD6AQAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8bAAIBAAgJuxTLEAC8AQABAAgJuxTLEAC8AQAAAA==.',
Nu='Nutellaa:BAAALgAECgQJDQAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Oborax:BAEALgAECgYJDwAAAA==.',
Od='Od:BAAALgAECgMJBAAAAA==.',
Ok='Okiro:BAAALgAECgIJAgAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAAALgAFFAMJAwAAAA==.Papaozz:BAAALgAECgYJCwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECgQJBAAAAA==.',
Pe='Perelia:BAAALgAECgYJEwAAAA==.Pewpewqt:BAAALgAECgEJAQABLgAECgcJHQAMACMZAA==.',
Pl='Plaguehammer:BAAALgAECgYJDgAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Po='Popcola:BAAALgADCgEJAQAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Punizher:BAAALgADCgcJBwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQAAAA==.',
Py='Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgADCggJCAAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Ra='Radiantharm:BAAALgAECgUJCwAAAA==.Raevalinaa:BAAALgAECgMJBAAAAA==.Raevelinaa:BAAALgAECgIJAwABLgAECgMJBAACAAAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAAALgAECgYJEQAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Reesepuffs:BAAALgAECgMJBAAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn8aAAIGAAcJHRc4CAB0AQAGAAcJHRc4CAB0AQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Reynard:BAAALgAECgQJBQAAAA==.Rezz:BAACLgAFFH8FAAIBAAIJ5AVGSgCXAAABAAIJ5AVGSgCXAAAuAAQKfx4AAgEACAm7H4MpAM0CAAEACAm7H4MpAM0CAAAA.',
Ri='Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgADCgYJBgAAAA==.',
Ry='Ryzen:BAAALgAECgYJBwAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scrufies:BAAALgAECgYJDgAAAA==.',
Se='Senorfiesta:BAAALgAECgQJBAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgADCgMJAwAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAAALgAECgYJCgAAAA==.Shamncheese:BAAALgAECgQJCAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8GAAIIAAMJniE7AQAQAQAIAAMJniE7AQAQAQAuAAQKfyMAAggACAn9JG8BAEEDAAgACAn9JG8BAEEDAAAA.Shisuiuchiha:BAAALgADCgYJCwAAAA==.Shuhari:BAAALgAECgkJDgAAAQ==.',
Si='Siilas:BAABLgAECn8WAAMTAAgJ5g0AQQCxAAASAAUJHg8IngAcAQATAAQJSAcAQQCxAAAAAA==.Sinamon:BAABLgAECn8YAAIFAAcJOhy5QgAcAgAFAAcJOhy5QgAcAgAAAA==.Sinani:BAAALgAECgcJDgAAAA==.Sinnamon:BAAALgADCgcJBwAAAA==.',
Sj='Sjrogue:BAABLgAECn8eAAIWAAgJUxJaGwAmAgAWAAgJUxJaGwAmAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgIJAwAAAA==.',
Sl='Slammydooker:BAABLgAECn8UAAMWAAcJ7RVVBQCjAQAWAAcJ7RVVBQCjAQAXAAEJ1QcHIQAtAAAAAA==.Sleeptoken:BAAALgAECgIJAgAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smightymouse:BAAALgADCgEJAQAAAA==.',
So='Solas:BAAALgAECgMJBgAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgEJAQAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgQJBQAAAA==.',
Sp='Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAAALgAECgMJBQAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8ZAAIeAAcJSwqRFABXAQAeAAcJSwqRFABXAQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgADCgMJAwAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sunpali:BAAALgAECgQJBQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacodaboss:BAAALgAECgUJBwAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8cAAIdAAgJXxugBwB3AgAdAAgJXxugBwB3AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Taupo:BAABLgAECn8dAAIUAAcJKyCiDQB8AgAUAAcJKyCiDQB8AgAAAA==.',
Tb='Tbh:BAAALgADCgcJBwABLgAECgYJCQACAAAAAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8UAAIfAAgJsA+YAADKAQAfAAgJsA+YAADKAQAAAA==.Techsmexx:BAAALgAECgIJAwAAAA==.Tenebron:BAAALgAECgQJDAAAAA==.Tenlucis:BAAALgADCgkJFQAAAA==.',
Th='Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAAALgAECgUJDAAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thickumz:BAAALgAECgEJAQAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8GAAIZAAQJMwyfAQBWAQAZAAQJMwyfAQBWAQAuAAQKfysAAxkACAlZIhEDAA4DABkACAkHIhEDAA4DAAgABwmzHkUBABwCAAAA.Thorïn:BAAALgADCgIJAgAAAA==.Thorýn:BAABLgAFFH8FAAIPAAMJZAn3EADtAAAPAAMJZAn3EADtAAABLgAFFAQJBgAZADMMAA==.Thórin:BAAALgAECgUJBQAAAA==.',
Ti='Tipsy:BAABLgAECn8UAAIYAAcJTghoEAA9AQAYAAcJTghoEAA9AQAAAA==.',
To='Toofy:BAAALgAECgEJAQAAAA==.Total:BAAALgADCgkJDAAAAA==.',
Tr='Tralleth:BAAALgAECgYJDgAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgADCgkJDgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgQJBAAAAA==.',
Tw='Twinklord:BAAALgAECgYJCwAAAA==.',
Ty='Tylolight:BAAALgADCgMJAwAAAA==.Tylototem:BAAALgAECgYJDAAAAA==.',
Ug='Uglyboi:BAAALgAECgcJCAAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCgAAAA==.',
Ur='Urgh:BAAALgAFFAEJAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.',
Ut='Uthur:BAAALgADCgYJCgAAAA==.',
Va='Vanillaface:BAAALgAECgQJBgAAAA==.Vape:BAAALgAECgQJBwAAAA==.',
Ve='Veinripp:BAAALgADCgUJBQAAAA==.Velarael:BAAALgAECgUJDQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAAALgAECgYJDwAAAA==.Velian:BAAALgADCgMJBAAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAAALgAECgEJAgAAAA==.',
Vi='Vicv:BAAALgAECgYJEQAAAA==.',
Wa='Wachonaso:BAABLgAECn8eAAMSAAcJMR+bNAA5AgASAAcJuhubNAA5AgATAAUJkBxbFwCPAQAAAA==.Wanbahl:BAAALgADCgMJAwAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8GAAISAAMJZBzeDQAFAQASAAMJZBzeDQAFAQAuAAQKfxcAAxIABwm+IKM5ACUCABIABgm+IKM5ACUCABMAAgm6DhhSAHcAAAAA.',
Wi='Wildthree:BAAALgAECgYJDgAAAA==.Willenda:BAAALgADCgYJBgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAABLgAECn8uAAIgAAgJsCSgAADvAgAgAAgJsCSgAADvAgAAAA==.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBAAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAECgUJBQABLgAFFAQJCQAMAOcRAA==.Wut:BAAALgADCgcJBwAAAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgIJAgAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgADCgkJEwAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yahro:BAABLgAECn8ZAAIFAAgJoxukJgCLAgAFAAgJoxukJgCLAgAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zalind:BAAALgAECgYJDAAAAA==.Zalvianna:BAAALgAECgEJAgAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJAwACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAECggJGwADAAohAA==.Zilongmage:BAAALgAECgUJBgAAAA==.Zinnia:BAAALgADCgEJAQAAAA==.',
Zo='Zonedk:BAAALgAECgIJAwAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgIJAwACAAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgADCgcJCQAAAA==.',
['Ør']='Ørsted:BAAALgADCgEJAQABLgAECgcJHQAUACsgAA==.',
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

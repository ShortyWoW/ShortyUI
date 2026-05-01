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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Priest-Shadow','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Balance','Priest-Holy','Mage-Fire','Mage-Frost','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Protection','Priest-Discipline','Warrior-Fury','Paladin-Holy','Druid-Guardian','Hunter-Survival','Paladin-Protection','DeathKnight-Blood','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','Warrior-Arms','Shaman-Enhancement','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Aberendh:BAAALgADCgkJBwAAAA==.Aberenmonk:BAABLgAECn8XAAQBAAcJixjzEgBaAQACAAYJnRpjKQC9AQABAAcJOxDzEgBaAQADAAIJMQMVZQA9AAAAAA==.Abiz:BAAALgAECgQJAwAAAA==.Abonde:BAAALgAECgUJDQAAAA==.Abraxes:BAAALgAECgUJCgAAAA==.Abysmalguard:BAAALgADCgUJBQAAAA==.',
Ac='Acidemon:BAABLgAECn8ZAAMEAAcJRBTwIgBiAQAEAAcJFRHwIgBiAQAFAAQJBhe/QQDyAAAAAA==.',
Ad='Adalaide:BAAALgAECgcJEAAAAA==.',
Ae='Aehda:BAAALgADCgcJDwAAAA==.Aeluna:BAAALgADCgcJCwAAAA==.Aethas:BAAALgADCgMJBAAAAA==.Aevari:BAABLgAECn8VAAIGAAYJPxckHACCAQAGAAYJPxckHACCAQAAAA==.',
Ah='Ahkna:BAAALgAECgMJBQAAAA==.',
Ai='Aieo:BAABLgAECn8ZAAIHAAgJQA7HaAC8AQAHAAgJQA7HaAC8AQAAAA==.',
Aj='Ajaâx:BAAALgAECgYJEwAAAA==.',
Al='Alanath:BAAALgADCgYJBgAAAA==.Alathia:BAAALgADCgYJBgAAAA==.Albatross:BAAALgAECgMJAwAAAA==.Aldarya:BAAALgAECgUJCwAAAA==.Aliraeda:BAABLgAECn8hAAQIAAgJHw0LQgArAQAIAAcJHQoLQgArAQAJAAQJNRFiEwD4AAAKAAMJSgwoWQBjAAAAAA==.Alisara:BAACLgAFFH8FAAILAAIJ3hn/JACzAAALAAIJ3hn/JACzAAAuAAQKfxUAAgsACAm0H1YNANMCAAsACAm0H1YNANMCAAAA.Alish:BAAALgAECgcJBwAAAA==.Alissia:BAAALgAECgMJBQAAAA==.Alistraea:BAAALgAECgYJEAAAAA==.Alitrullbrat:BAAALgAECggJEwAAAA==.Allargara:BAAALgAECggJCgAAAA==.Allexx:BAABLgAECn8gAAILAAcJyB9IEQAKAgALAAcJyB9IEQAKAgAAAA==.Alliin:BAAALgADCgcJBwAAAA==.Allyssel:BAABLgAECn8gAAIFAAgJriU8BAA2AwAFAAgJriU8BAA2AwAAAA==.Alyssanan:BAAALgADCgUJBQAAAA==.Alyssarae:BAAALgADCgIJAgAAAA==.',
Am='Amasu:BAACLgAFFH8QAAIMAAQJ6x0iBQBjAQAMAAQJ6x0iBQBjAQAuAAQKfycAAgwACAk/I5QJAOoCAAwACAk/I5QJAOoCAAAA.Ammathendis:BAAALgADCgQJBAAAAA==.',
An='Anastriana:BAAALgAECgYJCAAAAA==.Andrei:BAAALgADCgcJBAAAAA==.Angeal:BAABLgAECn8JAAILAAUJbRYIQgAOAQALAAUJbRYIQgAOAQAAAA==.Animus:BAABLgAECn8bAAINAAgJ5g2lFAByAQANAAgJ5g2lFAByAQAAAA==.Annamei:BAAALgAECgQJBwAAAA==.',
Ao='Aoife:BAAALgADCgcJFwAAAA==.Aorina:BAAALgAECgYJDwAAAA==.',
Ap='Aphis:BAAALgAECgYJDAAAAA==.Apocalyptica:BAABLgAECn8UAAIOAAcJrQmblABTAQAOAAcJrQmblABTAQAAAA==.',
Ar='Arazalor:BAABLgAECn8fAAIPAAgJ3A7MHQCSAQAPAAgJ3A7MHQCSAQAAAA==.Arcangel:BAACLgAFFH8QAAIPAAQJ4B52BwBbAQAPAAQJ4B52BwBbAQAuAAQKfyUAAw8ACAnaJfQFAC0DAA8ACAnaJfQFAC0DABAABAnWIbZAAC4BAAAA.Arcbane:BAAALgAECgEJAQAAAA==.Arclight:BAAALgAECgEJAQAAAA==.Argand:BAABLgAECn8bAAIPAAgJDB6lBgCsAgAPAAgJDB6lBgCsAgAAAA==.Arkahnon:BAAALgADCgUJBgAAAA==.Arthurdent:BAABLgAECn8fAAINAAgJUyKIAgDAAgANAAgJUyKIAgDAAgAAAA==.',
As='Ashenrain:BAAALgAECgYJCgAAAA==.Ashvia:BAAALgAECgQJCgAAAA==.Ashyslashy:BAABLgAECn8YAAIEAAcJMBKpKQA/AQAEAAcJMBKpKQA/AQAAAA==.',
At='Atheren:BAABLgAECn8fAAIGAAgJmSBpAwDZAgAGAAgJmSBpAwDZAgAAAA==.Athshu:BAAALgADCgEJAgAAAA==.Atulan:BAAALgAECggJDQAAAA==.',
Au='Augmented:BAAALgADCggJFAAAAA==.Auntiemimi:BAAALgAECgYJDAAAAA==.Aurenthos:BAAALgADCggJCwAAAA==.Auressali:BAAALgAECgcJDwAAAA==.',
Av='Avalina:BAABLgAECn8XAAMRAAcJDyAPDQCFAgARAAcJDyAPDQCFAgAMAAUJNhV+HAAYAQAAAA==.Avannar:BAAALgADCgkJIAAAAA==.Avelyn:BAACLgAFFH8UAAMSAAUJ/CYDAABAAgASAAUJkyYDAABAAgATAAMJpSN8PQDTAAAuAAQKfxsAAxIACAklJkQAAHMDABIACAklJkQAAHMDABMAAgnlILupAG8AAAAA.Aviae:BAAALgADCgkJDgAAAA==.',
Ay='Ayani:BAABLgAECn8eAAMMAAcJgxOSEACHAQAMAAcJgxOSEACHAQARAAQJLQiqMwBlAAAAAA==.',
Az='Azrine:BAAALgADCgcJDQAAAA==.',
Ba='Bacongrease:BAAALgADCgEJAgAAAA==.Baddkharma:BAAALgAECgEJAQAAAA==.Badras:BAABLgAECn8rAAILAAgJGiS5BQAyAwALAAgJGiS5BQAyAwAAAA==.Bagelz:BAACLgAFFH8QAAIDAAQJyiTGAwCxAQADAAQJyiTGAwCxAQAuAAQKfygAAgMACAlVJR8EAC4DAAMACAlVJR8EAC4DAAAA.Balafre:BAAALgADCgUJBQABLgAECgQJBAAUAAAAAA==.Balforyn:BAAALgADCggJCQAAAA==.Bambi:BAAALgAECgYJBgAAAA==.Bathool:BAAALgAECgYJEwAAAA==.Bayla:BAAALgAFFAIJAgABLgAFFAYJFwATAFoWAA==.Bazzlock:BAAALgAECgYJDQAAAA==.',
Be='Beeblebroxx:BAAALgADCgMJAwAAAA==.Beefcat:BAAALgAECgQJBQABLgAECgYJCAAUAAAAAA==.Beefycow:BAAALgADCgEJAgAAAA==.Belwar:BAAALgADCgcJCAAAAA==.Beric:BAACLgAFFH8GAAIVAAMJKRpbAgAeAQAVAAMJKRpbAgAeAQAuAAQKfysAAxUACAkYHFADAJsCABUACAkYHFADAJsCABYAAwltDO8mAIIAAAAA.Berriuster:BAAALgAECgIJAgAAAA==.Betadine:BAAALgAECgcJEwAAAA==.',
Bi='Bigboymanguy:BAAALgAECgUJBQAAAA==.Bigdkenergy:BAAALgAECgEJAQAAAA==.Billd:BAAALgADCgIJAgAAAA==.Billiemays:BAAALgAECgEJAwAAAA==.',
Bl='Blade:BAABLgAECn8aAAIFAAgJcQ2KDABzAQAFAAgJcQ2KDABzAQAAAA==.Blaydesong:BAAALgAECgEJAQAAAA==.Blayse:BAAALgADCgUJBQABLgAECgQJBwAUAAAAAA==.Blayseknight:BAAALgAECgQJBwAAAA==.Blazinjohnny:BAABLgAECn8VAAIOAAYJ+B+hHQDYAQAOAAYJ+B+hHQDYAQAAAA==.Blightburn:BAAALgAECgYJDgAAAA==.Blingblang:BAAALgADCgEJAQAAAA==.Blurpleberry:BAAALgADCgUJAwAAAA==.',
Bo='Boldan:BAAALgADCgUJBwAAAA==.Bondarias:BAAALgAECgYJEwAAAA==.Boohaha:BAABLgAECn8UAAIGAAYJqyLNJgD3AQAGAAYJqyLNJgD3AQAAAA==.Borris:BAAALgAFFAEJAQAAAA==.',
Br='Brightwing:BAACLgAFFH8HAAIXAAQJFhPbCgAnAQAXAAQJFhPbCgAnAQAuAAQKfyAAAhcACAmAIXAEAAwDABcACAmAIXAEAAwDAAAA.Brigoryn:BAAALgAECgUJDQAAAA==.Brokenarro:BAAALgADCggJDgAAAA==.Browneyepie:BAAALgAECgQJBAAAAA==.',
Bu='Bullshivek:BAABLgAECn8cAAIPAAcJQxaXFgDOAQAPAAcJQxaXFgDOAQAAAA==.Bussincider:BAAALgAECgQJBgAAAA==.',
Ca='Caale:BAAALgAECgYJCgAAAA==.Caecus:BAABLgAECn8cAAIHAAcJVh1jJACwAQAHAAcJVh1jJACwAQAAAA==.Callsaul:BAAALgADCgMJCgAAAA==.Careillena:BAABLgAECn8WAAIHAAcJwB6OFQANAgAHAAcJwB6OFQANAgAAAA==.Cate:BAAALgADCgYJCAAAAA==.Caylessa:BAAALgADCgcJBwAAAA==.Caylissa:BAAALgAECgYJEgAAAA==.',
Ce='Celithsong:BAAALgADCgMJAwABLgADCgkJDgAUAAAAAA==.Celryth:BAAALgADCgIJAgAAAA==.Cenvoked:BAABLgAECn8bAAMXAAgJehYQGADUAQAXAAcJlxcQGADUAQAYAAcJsAv1GAA2AQAAAA==.',
Cf='Cfs:BAAALgAECgQJBQAAAA==.',
Ch='Charcrash:BAACLgAFFH8GAAIEAAMJvBiwGQALAQAEAAMJvBiwGQALAQAuAAQKfx8AAwQACAn5H9MeAHkBAAQACAn5H9MeAHkBABkABglbEnoIACUBAAAA.Charl:BAAALgADCgcJDQAAAA==.Charlicious:BAABLgAFFH8HAAIIAAMJxR8pIgAYAQAIAAMJxR8pIgAYAQABLgAFFAMJBgAEALwYAA==.Chedwiwwiper:BAAALgADCgIJAgABLgADCgYJBwAUAAAAAA==.Cheylia:BAAALgAECgQJBwAAAA==.Chiller:BAAALgAECgQJBwAAAA==.Chimster:BAABLgAECn8cAAILAAcJFiAJIQA/AgALAAcJFiAJIQA/AgAAAA==.Chimydakilla:BAAALgAECgUJDgAAAA==.Chiva:BAAALgADCgIJAgAAAA==.Chknlttl:BAABLgAECn8cAAIaAAcJFSPfBgDZAQAaAAcJFSPfBgDZAQAAAA==.Chocomochi:BAAALgAECgcJDQAAAA==.Chrønic:BAAALgADCgUJCgAAAA==.Chuckstrike:BAAALgAECgUJDQAAAA==.Chyna:BAAALgADCgYJBwAAAA==.',
Ci='Cieara:BAAALgADCgYJCgAAAA==.Cinnamonbuns:BAAALgAECgIJAwABLgAECgYJDAAUAAAAAA==.',
Cl='Clicked:BAAALgADCgQJBAAAAA==.Clouver:BAAALgADCgYJBgAAAA==.Clown:BAAALgADCgcJBwAAAA==.',
Co='Cody:BAAALgAECgYJDwAAAA==.Constipated:BAAALgADCgUJCAAAAA==.Coolbeans:BAAALgAECgEJAQABLgAECgYJCAAUAAAAAA==.Corvò:BAAALgAECgQJBwABLgAECgcJHAAaABUjAA==.',
Cr='Craeus:BAABLgAECn8bAAIGAAgJOCHiAwDIAgAGAAgJOCHiAwDIAgAAAA==.Credit:BAABLgAECn8pAAQMAAgJ6x2kEwBWAgAMAAgJ6x2kEwBWAgAbAAYJ4B3EHACvAQARAAEJrxKNPAA7AAAAAA==.Crine:BAAALgADCgEJAQABLgAECggJGQAYAAoYAA==.Criztal:BAAALgADCggJGQAAAA==.Crotalus:BAAALgADCgEJAwAAAA==.Crux:BAAALgADCgMJAwAAAA==.',
Cu='Cupofnoodles:BAAALgAECgUJCQAAAA==.Cursedmayo:BAAALgADCgMJAwAAAA==.',
Cy='Cyerius:BAAALgADCgYJBQAAAA==.Cyonarah:BAAALgAECgYJDwAAAA==.',
Da='Dad:BAAALgAECgIJBQAAAA==.Dahlìa:BAAALgAECgQJBQAAAA==.Daquarius:BAAALgAECgcJCQAAAA==.Darem:BAAALgAECgkJDQAAAA==.Darthis:BAAALgADCgUJBQAAAA==.Daywalker:BAAALgAECgcJCwABLgAECgcJFwAEALwfAA==.Daísy:BAAALgAECgEJAwAAAA==.',
De='Deadsword:BAAALgADCgEJAQAAAA==.Deanlol:BAAALgAECgEJAwABLgAECgMJBgAUAAAAAA==.Deaorva:BAAALgAECgMJAwAAAA==.Deathbringr:BAAALgAECgQJCgAAAA==.Deathspecter:BAAALgAECgUJCQAAAA==.Deidra:BAAALgADCggJFwAAAA==.Deigh:BAAALgADCgEJAQAAAA==.Delryth:BAAALgADCgUJBQAAAA==.Demonsitter:BAAALgAECgYJDwAAAA==.Denham:BAAALgAECgMJAwABLgAECggJHwADAKUgAA==.Dersdomkie:BAAALgAECgcJDQAAAA==.Deshathoris:BAAALgAECgMJAwAAAA==.',
Di='Diggi:BAAALgAECgcJEgAAAA==.Diosa:BAABLgAECn8eAAIKAAcJRRWpBQBqAQAKAAcJRRWpBQBqAQAAAA==.Dish:BAAALgAECgUJCgAAAA==.Divinekat:BAAALgAECggJDwAAAA==.',
Dk='Dkagon:BAAALgAECgYJCwAAAA==.',
Do='Docfeelgood:BAAALgADCgIJAgAAAA==.Docholiday:BAAALgAECgcJCgAAAA==.Doode:BAAALgAECggJDwAAAA==.Dooderonomy:BAABLgAECn8cAAMMAAcJZxCCEwBoAQAMAAcJZxCCEwBoAQARAAcJfgf7VgDZAAAAAA==.Doria:BAAALgAECgEJAQAAAA==.',
Dp='Dpsguide:BAAALgAECgEJBQAAAA==.',
Dr='Drac:BAAALgAECgYJBgAAAA==.Dragaan:BAABLgAECn8WAAITAAYJGwnQZAARAQATAAYJGwnQZAARAQAAAA==.Dragonbait:BAABLgAECn8/AAIOAAgJACEtDQBaAgAOAAgJACEtDQBaAgAAAA==.Dragondude:BAAALgAECgcJDQAAAA==.Dragonoodles:BAAALgADCgUJBQABLgAECgcJDAAUAAAAAA==.Dragonzbane:BAAALgAECgYJEAAAAA==.Drawk:BAAALgAECgIJAQAAAA==.Drdoom:BAABLgAECn8oAAQbAAgJ6hvSBAB4AgAbAAgJ6hvSBAB4AgARAAgJ5QqeLgCJAQAMAAIJgwd2NQBhAAAAAA==.Dreamawake:BAABLgAECn8ZAAITAAcJ4hmaMwCWAQATAAcJ4hmaMwCWAQAAAA==.Drek:BAAALgAECgEJAQAAAA==.Drenched:BAAALgAECgYJDAAAAA==.Drenea:BAAALgAECgEJAQAAAA==.Drimlek:BAAALgAECgEJAQAAAA==.Drin:BAAALgAECgUJBQAAAA==.Drunkey:BAABLgAECn8YAAICAAcJdBmiIwDlAQACAAcJdBmiIwDlAQAAAA==.Drâxus:BAAALgAECgIJAgAAAA==.',
Du='Dualeafa:BAAALgAECgEJAQAAAA==.Duplicitous:BAAALgADCgkJEgAAAA==.',
Dw='Dwarfsham:BAAALgAECgMJBgAAAA==.Dwarvenrogue:BAAALgADCgMJAwAAAA==.',
Dy='Dyriana:BAAALgAECgEJAQAAAA==.',
Ea='Earthmother:BAAALgAECgQJBAAAAA==.',
Ed='Edum:BAAALgAECgUJDwAAAA==.',
El='Elcie:BAAALgADCgkJEQAAAA==.Elektraka:BAAALgADCgYJBwAAAA==.Ellasian:BAAALgAECgYJCwAAAA==.Eltria:BAACLgAFFH8QAAITAAQJqBtOFQBsAQATAAQJqBtOFQBsAQAuAAQKfygAAhMACAlaJIMTADMDABMACAlaJIMTADMDAAAA.Elyndy:BAABLgAECn8iAAIaAAgJ4B1cBwC0AgAaAAgJ4B1cBwC0AgAAAA==.',
Em='Emishalle:BAAALgADCgMJAwAAAA==.Empathy:BAAALgADCgYJBgAAAA==.',
En='Ensoc:BAAALgAECgcJEQAAAA==.',
Ep='Ephel:BAABLgAECn8cAAMRAAcJsRADOwBOAQARAAcJsRADOwBOAQAMAAYJfwYeIQDyAAAAAA==.',
Er='Erenia:BAAALgADCgMJAwAAAA==.Erí:BAAALgAECgYJEAAAAA==.',
Es='Essential:BAACLgAFFH8QAAIcAAQJQRN9CABRAQAcAAQJQRN9CABRAQAuAAQKfygAAhwACAnKH4wQAM0CABwACAnKH4wQAM0CAAAA.',
Et='Ethop:BAAALgAECgIJAwABLgAECgYJCAAUAAAAAA==.',
Eu='Eulali:BAAALgADCgIJAgAAAA==.',
Ez='Ezalth:BAAALgADCgQJBAAAAA==.Ezz:BAAALgADCgYJBwAAAA==.',
Fa='Fachzile:BAAALgADCgUJBQAAAA==.Faden:BAAALgAECgQJBAABLgAECggJGAACAJUjAA==.Faenara:BAABLgAECn8eAAMdAAgJaRIIMwCyAQAdAAgJaRIIMwCyAQAOAAYJYgkYXQD8AAAAAA==.Faint:BAAALgAECgQJBAABLgAECggJIgAdAKsfAA==.Falafelguy:BAABLgAECn8bAAITAAgJRhy3GAAXAgATAAgJRhy3GAAXAgAAAA==.Fayzon:BAABLgAECn8aAAIWAAcJkxaoCwCuAQAWAAcJkxaoCwCuAQAAAA==.',
Fe='Fedange:BAABLgAECn8aAAIeAAgJQQIOJQB0AAAeAAgJQQIOJQB0AAAAAA==.Felartamiel:BAAALgAECgIJAQAAAA==.Felician:BAAALgADCgcJBwAAAA==.Felii:BAAALgAECgEJAQAAAA==.Felini:BAAALgADCgcJBgAAAA==.Felkieler:BAABLgAECn8VAAIEAAYJcQOMXACSAAAEAAYJcQOMXACSAAAAAA==.Ferror:BAAALgADCgMJAwAAAA==.Festermight:BAAALgADCgEJAQAAAA==.Fey:BAABLgAECn8TAAIEAAYJsSE/KQBBAQAEAAYJsSE/KQBBAQAAAA==.Feydris:BAAALgADCgYJBgABLgADCgYJBgAUAAAAAA==.',
Fi='Fieperskaivu:BAAALgAECgYJCAABLgAECgcJFwAEALwfAA==.Fiorstrasza:BAAALgADCgIJBQAAAA==.Fireyfox:BAAALgADCgUJBgABLgAECgcJHAAXABMYAA==.',
Fj='Fjc:BAAALgADCgEJAQAAAA==.Fjshamie:BAAALgADCgcJCQABLgAECgEJAQAUAAAAAA==.',
Fl='Flavoune:BAAALgAECgEJAQAAAA==.Flee:BAAALgADCgYJCgAAAA==.',
Fo='Forestspirit:BAABLgAECn8dAAIPAAgJdBPzGgCoAQAPAAgJdBPzGgCoAQAAAA==.Forkliftcert:BAABLgAECn8RAAIEAAYJrA1ljAAJAQAEAAYJrA1ljAAJAQAAAA==.Foxxee:BAAALgADCgYJCQAAAA==.',
Fr='Friednoodle:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzlessly:BAACLgAFFH8GAAIdAAMJfyCVDQAiAQAdAAMJfyCVDQAiAQAuAAQKfyUAAh0ACQkEIsUCAEsDAB0ACQkEIsUCAEsDAAAA.',
['Fí']='Físted:BAAALgADCgUJAwAAAA==.',
Ga='Galaxyman:BAAALgADCgYJCwAAAA==.Gano:BAAALgADCgcJBwAAAA==.Gapeilous:BAAALgAECgMJAwAAAA==.Garbanzo:BAAALgADCgYJBgAAAA==.Gargosa:BAABLgAECn8bAAMLAAgJbA26JACIAQALAAgJcwy6JACIAQAfAAYJFAykGQA1AQAAAA==.Garybusey:BAAALgAECgEJAQAAAA==.',
Ge='Geist:BAACLgAFFH8QAAMOAAQJgBafCwBPAQAOAAQJgBafCwBPAQAgAAEJ7gULCQArAAAuAAQKfygAAw4ACAlMIsgpAH0CAA4ACAlMIsgpAH0CACAACAlhDpQUAIUBAAAA.Geraith:BAACLgAFFH8QAAIhAAQJtB8hBABmAQAhAAQJtB8hBABmAQAuAAQKfygAAiEACAnLI7cDABsDACEACAnLI7cDABsDAAAA.Gerios:BAABLgAECn8WAAILAAgJOhHrGQDFAQALAAgJOhHrGQDFAQAAAA==.',
Gg='Ggparts:BAAALgADCgIJAgABLgAECgUJCgAUAAAAAA==.',
Gh='Ghefgar:BAAALgAECgYJCwAAAA==.Ghostflair:BAAALgADCgcJCQAAAA==.Ghostflare:BAABLgAECn8bAAIRAAgJVB1PCwCbAgARAAgJVB1PCwCbAgAAAA==.',
Gi='Girth:BAAALgAECgEJAQAAAA==.',
Gl='Glendra:BAABLgAECn8hAAIgAAgJGxgjBgDIAQAgAAgJGxgjBgDIAQAAAA==.Gloomfx:BAAALgAECgUJEAAAAA==.Glowfish:BAABLgAECn8YAAICAAgJkRANFgBRAQACAAgJkRANFgBRAQAAAA==.Glowleaf:BAAALgAECgEJAQAAAA==.',
Go='Goatboat:BAAALgADCgYJCgAAAA==.Gohan:BAAALgADCgYJBgAAAA==.Goopz:BAAALgADCgcJBwAAAA==.Gorasu:BAAALgADCgYJBgAAAA==.Gorbosplort:BAAALgAECgEJAQABLgAFFAUJDgAFAIgVAA==.',
Gr='Grandeeny:BAAALgAECgYJDwAAAA==.Grandgrimm:BAAALgAECgQJBwAAAA==.Grandzob:BAAALgAECgUJEQAAAA==.Gravix:BAAALgADCgYJBgABLgAECggJFQAfAIwkAA==.Greensleeves:BAAALgAECgEJAQAAAA==.Gregoriusz:BAACLgAFFH8HAAIiAAMJPhFmCQDpAAAiAAMJPhFmCQDpAAAuAAQKfyEAAiIACAlPIMYVAH8CACIACAlPIMYVAH8CAAAA.Greygull:BAAALgAECgQJDAAAAA==.Grimfrost:BAAALgAECgQJBwAAAA==.Grimshadows:BAAALgADCgEJAQAAAA==.Grissle:BAAALgADCgQJBAAAAA==.Grunin:BAAALgADCgUJBQAAAA==.',
Gu='Guntank:BAABLgAECn8aAAMcAAcJ6RwfDQDfAQAcAAcJ6RwfDQDfAQAaAAQJwhLCLgDNAAAAAA==.Guntenk:BAAALgAECgQJBAAAAA==.Guzzi:BAAALgAECgQJBQAAAA==.',
Gy='Gyaltsen:BAAALgAECgIJBAAAAA==.',
Ha='Halliestar:BAAALgAECgYJBgABLgAECgYJDwAUAAAAAA==.Hategnomer:BAAALgAECgEJAQAAAA==.Havenfell:BAABLgAECn8UAAIaAAgJ0hrOBwC+AQAaAAgJ0hrOBwC+AQAAAA==.Hawkfist:BAABLgAECn8gAAILAAgJdhf2GQDFAQALAAgJdhf2GQDFAQAAAA==.',
He='Hecate:BAABLgAECn8WAAIIAAkJqAUfmAAoAQAIAAkJqAUfmAAoAQAAAA==.Heinzz:BAAALgAECgcJDAAAAA==.Helah:BAAALgAECgYJBwAAAA==.Hercules:BAABLgAECn8VAAIHAAgJjxMsIwC2AQAHAAgJjxMsIwC2AQAAAA==.',
Hi='Hierodoulos:BAABLgAECn8eAAIPAAcJjCUDBADvAgAPAAcJjCUDBADvAgAAAA==.Histano:BAAALgAECgcJDAAAAA==.',
Ho='Holopearl:BAAALgAECgEJAQAAAA==.Houdro:BAAALgAECgEJAgAAAA==.Howleyberry:BAAALgAECgEJAQAAAA==.',
Hr='Hroth:BAAALgAECgUJBQABLgAECggJIgAdAKsfAA==.Hrothgar:BAAALgAECgUJBQABLgAECggJIgAdAKsfAA==.',
Hu='Hunteroni:BAAALgADCgMJAwABLgAECgcJDAAUAAAAAA==.Huonn:BAAALgAECgYJDgAAAA==.',
Hy='Hyper:BAAALgADCgMJAwAAAA==.Hypoluxo:BAAALgAECgEJAQAAAA==.',
['Hô']='Hôjack:BAAALgADCgMJAwAAAA==.',
Ib='Ibanangel:BAAALgAECgMJAwAAAA==.',
Ic='Icenea:BAAALgADCgcJDAABLgAFFAIJBQALAN4ZAA==.',
Il='Illeiria:BAAALgADCgUJBQAAAA==.Illerdanu:BAAALgADCgIJAgAAAA==.Illtud:BAAALgADCgYJBgAAAA==.',
Im='Impastable:BAAALgADCgcJCgABLgAECgcJDAAUAAAAAA==.Impastabrew:BAAALgAECgYJDQABLgAECgcJDAAUAAAAAA==.',
In='Inohoe:BAAALgADCgYJBgAAAA==.Inola:BAABLgAECn8fAAIRAAcJKxKeFgBYAQARAAcJKxKeFgBYAQAAAA==.Intheron:BAAALgAECgQJBAAAAA==.',
Ir='Ironfur:BAAALgADCgcJDAABLgAECgcJFwAaAK8fAA==.',
Is='Iskrå:BAAALgAECgYJDgAAAA==.',
Iv='Ivellos:BAAALgAECgQJBwABLgAECgcJEQAUAAAAAA==.',
Ja='Jacynth:BAAALgAECgEJAQAAAA==.Jaimers:BAABLgAECn8lAAQbAAgJUx+TAgDcAgAbAAgJuB6TAgDcAgARAAcJ8xv4FAA1AgAMAAMJAAfQVABwAAAAAA==.Januz:BAAALgAECgYJCQAAAA==.Javlos:BAAALgAECgMJBAAAAA==.Jaxen:BAAALgAECggJEgAAAA==.Jaywilde:BAAALgAECggJEwAAAA==.Jaína:BAAALgADCgcJEwAAAA==.',
Je='Jedzia:BAAALgAECgEJAQAAAA==.Jeeffee:BAAALgAECgUJCgAAAA==.Jeep:BAABLgAECn8dAAIHAAgJWgtuLQCFAQAHAAgJWgtuLQCFAQAAAA==.Jezell:BAAALgADCgMJAwAAAA==.',
Ji='Jizakazam:BAAALgAECgUJBgAAAA==.',
Jo='Joode:BAAALgAECgEJAQAAAA==.',
Ju='Juggyspally:BAAALgAECgIJAgAAAA==.Julls:BAAALgAECgEJAQAAAA==.Justbringit:BAEALgADCgIJAgABLgAECggJGgAEAMwjAA==.',
Ka='Kammi:BAAALgADCgkJCQAAAA==.Karot:BAAALgAECgYJDwABLgAECgcJHgAHAPcYAA==.Karotten:BAABLgAECn8eAAMHAAcJ9xgxJwChAQAHAAcJ9xgxJwChAQAhAAIJwAJ9MQAYAAAAAA==.Karthair:BAABLgAECn8cAAQXAAcJExguBQANAgAXAAcJExguBQANAgAYAAMJ5QmRUACJAAAjAAEJgAijQgAqAAAAAA==.Katsumotto:BAAALgADCgMJAwAAAA==.Kaylessa:BAAALgAECgEJAQAAAA==.Kazi:BAAALgADCgkJCQAAAA==.',
Ke='Keello:BAAALgAECgkJBwAAAA==.Kezialilly:BAAALgAECgEJAgAAAA==.',
Kh='Khalasar:BAAALgAECgQJBAAAAA==.Khaleessi:BAAALgADCgYJBgAAAA==.',
Ki='Kianlan:BAAALgADCgUJBgAAAA==.Kiaraa:BAAALgADCggJEQAAAA==.Kintsugi:BAAALgAECgQJCAAAAA==.Kisatchie:BAABLgAECn8UAAIeAAYJHxUvCgApAQAeAAYJHxUvCgApAQAAAA==.Kival:BAAALgAECgUJDAAAAA==.Kivrin:BAAALgAECgEJAQAAAA==.',
Kn='Knawls:BAABLgAECn8VAAMkAAYJTxlvEQCWAQAkAAYJuxdvEQCWAQAQAAUJBBF0JADeAAAAAA==.',
Ko='Koalitsiya:BAABLgAECn8XAAQIAAYJ0QM0bwCtAAAIAAYJ5QI0bwCtAAAKAAIJ0ATmXwBPAAAJAAEJQAOHNQAwAAAAAA==.Kookykrum:BAAALgAECgQJBQAAAA==.Korlys:BAAALgADCgEJAQABLgAECgUJBQAUAAAAAA==.Korvidia:BAAALgAECgYJDAAAAA==.Kozãk:BAAALgADCgUJBQAAAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Kracklin:BAAALgAECgIJBwAAAA==.Krimez:BAABLgAECn8ZAAIYAAgJChjBEgBwAQAYAAgJChjBEgBwAQAAAA==.Krow:BAAALgAECgEJAwAAAA==.Kruzex:BAAALgAECgEJAQABLgAECgEJAwAUAAAAAA==.Kryne:BAAALgAECgYJEwABLgAECggJGQAYAAoYAA==.Krynez:BAAALgADCgUJBQABLgAECggJGQAYAAoYAA==.',
Ku='Kurgash:BAAALgAECgQJBwAAAA==.',
Ky='Kyari:BAAALgAECgYJCAAAAA==.Kymerah:BAAALgAECgIJAgAAAA==.Kyrhios:BAAALgAECgYJDwAAAA==.',
['Kä']='Käggai:BAABLgAECn8XAAMcAAYJ1yGPMADsAQAcAAYJYiCPMADsAQAlAAQJwRkqHAAPAQAAAA==.',
La='Laindra:BAAALgADCgMJAwAAAA==.Lark:BAABLgAECn8ZAAIaAAYJJRTWEAAVAQAaAAYJJRTWEAAVAQAAAA==.Larthas:BAAALgAECgYJBwAAAA==.Lascie:BAABLgAECn8ZAAITAAgJNxjxGwAEAgATAAgJNxjxGwAEAgAAAA==.Latrunculon:BAAALgADCgQJBAAAAA==.Lazra:BAAALgADCgcJDQAAAA==.',
Le='Leafykat:BAAALgADCggJFwAAAA==.Leaila:BAAALgAECgcJCQAAAA==.Lealia:BAABLgAECn8ZAAMNAAYJtSFEIgD9AQANAAYJtSFEIgD9AQAmAAEJAALfLwAkAAABLgAFFAIJBQALAN4ZAA==.Legendfox:BAAALgADCgIJAgAAAA==.Leiha:BAAALgAECgMJBAAAAA==.',
Lg='Lgfuad:BAAALgAECgcJDQAAAA==.',
Li='Liams:BAAALgAECgUJDAAAAA==.Lidori:BAAALgADCggJEwAAAA==.Lightsent:BAAALgADCgUJBQABLgADCggJHAAUAAAAAA==.Lilíth:BAAALgAECgcJDgAAAA==.Linux:BAABLgAECn8bAAILAAcJPxe9IgCTAQALAAcJPxe9IgCTAQAAAA==.Lisânalgaib:BAAALgAECgQJDAAAAA==.Livide:BAABLgAECn8YAAMRAAgJAR7VCwCUAgARAAcJ9h/VCwCUAgAbAAgJsA19GwC6AQAAAA==.',
Ll='Llama:BAABLgAECn8cAAICAAcJiBRMEwBtAQACAAcJiBRMEwBtAQAAAA==.',
Lo='Lokzilla:BAAALgAECgYJBgAAAA==.Lonamire:BAAALgADCgcJCQAAAA==.',
Lu='Lucithance:BAAALgAECgYJEgAAAA==.Luminarra:BAAALgADCgMJAwAAAA==.Luminianna:BAABLgAECn8eAAMjAAgJ/RwhAQBmAgAjAAgJ/RwhAQBmAgAYAAYJcw8aMgA4AQAAAA==.',
Ly='Lydrin:BAAALgAECgQJBQAAAA==.Lynerys:BAAALgAECgUJCQAAAA==.Lynnsbussy:BAAALgAECgQJEgAAAA==.Lytol:BAAALgADCgkJIwAAAA==.',
Ma='Macloc:BAAALgAECgMJBAAAAA==.Madmike:BAAALgAECgQJBAAAAA==.Maedae:BAABLgAECn8UAAIbAAgJ8AY3EwBiAQAbAAgJ8AY3EwBiAQAAAA==.Magmyr:BAAALgAECgcJEQAAAA==.Mahli:BAABLgAECn8aAAMIAAgJex/eEAAfAgAIAAcJHx7eEAAfAgAKAAMJJxsBMgDwAAAAAA==.Maimah:BAABLgAECn8YAAITAAYJ3R8eawD/AQATAAYJ3R8eawD/AQAAAA==.Manpandalock:BAAALgAECgEJAgAAAA==.Maplefire:BAAALgADCggJHAAAAA==.Marrias:BAAALgAECgUJBwAAAA==.Mawrix:BAABLgAECn8YAAMVAAcJlxMyBACYAQAVAAcJlxMyBACYAQAWAAIJvAPYWQBXAAAAAA==.Maxieflames:BAAALgADCgYJCwAAAA==.',
Mc='Mcguzzler:BAAALgAECgMJAwAAAA==.',
Me='Melwazul:BAAALgADCgUJBQAAAA==.Meoshi:BAABLgAECn8WAAITAAcJmhC1QwBjAQATAAcJmhC1QwBjAQAAAA==.Merk:BAAALgAECgcJDAAAAA==.Mesuryte:BAACLgAFFH8UAAIfAAUJHSHbAQCJAQAfAAUJHSHbAQCJAQAuAAQKfyYAAh8ACAnuJBQCACgDAB8ACAnuJBQCACgDAAAA.',
Mi='Mibs:BAABLgAECn8fAAIcAAgJ1R4yBgBRAgAcAAgJ1R4yBgBRAgAAAA==.Mickal:BAABLgAECn8bAAIOAAgJTQiMPQBRAQAOAAgJTQiMPQBRAQAAAA==.Mikaelangelo:BAAALgAECgcJEgAAAA==.Mintebrew:BAAALgAECgYJCAAAAA==.Mip:BAAALgAECgcJDgAAAA==.Mirie:BAAALgAECgQJCgAAAA==.Misfires:BAAALgADCgEJAQAAAA==.',
Mn='Mnrogar:BAAALgADCgMJBAAAAA==.',
Mo='Mohegon:BAAALgADCgMJAwAAAA==.Mohini:BAABLgAECn8eAAMQAAgJJRwcCQD+AQAQAAgJJRwcCQD+AQAPAAQJLQ/viADDAAAAAA==.Mohproblems:BAAALgAECgQJBAAAAA==.Mojhohammers:BAAALgADCggJFQAAAA==.Mokaki:BAAALgAECgYJEwAAAA==.Molumens:BAAALgAECgYJCAAAAA==.Monkified:BAAALgADCgcJBwABLgAFFAIJBAAUAAAAAA==.Monzil:BAAALgAECgYJCwABLgAECggJKAAWAMkdAA==.Moogician:BAAALgAECgcJEgAAAA==.Moomama:BAAALgADCgIJAgAAAA==.Moonren:BAAALgADCgYJBgAAAA==.Moonsinna:BAAALgADCggJEwAAAA==.Mooshoofasa:BAAALgADCgMJAwAAAA==.Mooter:BAABLgAECn8qAAIVAAkJBhccAwDPAQAVAAkJBhccAwDPAQAAAA==.Mornix:BAAALgAECgcJEQABLgAECgEJAQAUAAAAAA==.Moronic:BAAALgAECgEJAQAAAA==.Mortincarne:BAAALgADCgIJAgAAAA==.',
Mu='Munc:BAAALgADCgYJBgAAAA==.Munchwizard:BAAALgAECgEJAgAAAA==.Murglun:BAAALgAECgQJBAAAAA==.Mushroom:BAABLgAECn8fAAITAAYJkSYUFAA6AgATAAYJkSYUFAA6AgAAAA==.',
My='Mystic:BAAALgAECgYJDAAAAA==.',
Na='Nahaz:BAAALgAECgEJAQAAAA==.Namuswanbrok:BAAALgADCgIJAQAAAA==.Naota:BAABLgAECn8fAAIHAAgJPBxxEAA5AgAHAAgJPBxxEAA5AgAAAA==.Naqii:BAAALgAECgMJAwAAAA==.Naqsx:BAAALgAECgYJDwAAAA==.Nareda:BAAALgADCggJBgAAAA==.Narfox:BAABLgAECn8VAAMGAAcJKAmBMgDyAAAGAAcJKAmBMgDyAAANAAEJeQLHlQAfAAAAAA==.Naryb:BAAALgAFFAEJAQAAAA==.Naughtia:BAAALgADCgEJAQAAAA==.',
Ne='Neameto:BAABLgAECn8eAAMYAAcJoRafHADiAQAYAAcJoRafHADiAQAjAAIJSwiYOABUAAAAAA==.Necrophyle:BAABLgAECn8VAAMhAAgJggu8EQAAAQAHAAYJTAYouAASAQAhAAgJ0wm8EQAAAQAAAA==.Nefarox:BAAALgAECgYJEwAAAA==.Neon:BAABLgAECn8oAAINAAgJlR+SBAB2AgANAAgJlR+SBAB2AgAAAA==.Nerfdarts:BAAALgADCgIJAgAAAA==.Ness:BAAALgADCgYJCgAAAA==.',
Nh='Nhugpow:BAAALgADCgkJCQAAAA==.',
Ni='Nicholas:BAACLgAFFH8IAAIYAAQJwgwpDQAuAQAYAAQJwgwpDQAuAQAuAAQKfycAAhgACAl+IeQIAOoCABgACAl+IeQIAOoCAAEuAAUUBAkIABgAwgwA.Nightriderr:BAAALgAECgEJAgAAAA==.Nightstealer:BAAALgAECgYJDwAAAA==.Nika:BAACLgAFFH8JAAMHAAQJYhfeEQBnAQAHAAQJYhfeEQBnAQAnAAIJnQcJBQCbAAAuAAQKfyAAAgcACAnPHxknAJ8CAAcACAnPHxknAJ8CAAAA.Nikkikayama:BAACLgAFFH8OAAMLAAQJvhsnBABdAQALAAQJvhsnBABdAQAiAAEJnQLSLAA/AAAuAAQKfx8AAwsACAk6IxILAOwCAAsACAk6IxILAOwCACIAAgmiBDd7AFYAAAAA.',
No='Nobzz:BAAALgADCggJEAAAAA==.Nofuratu:BAABLgAECn8WAAMQAAgJsAnbGgAlAQAQAAgJsAnbGgAlAQAPAAMJTQX2qwBuAAAAAA==.Noncomplex:BAAALgAECgYJBgAAAA==.Nonextinct:BAAALgADCggJFwAAAA==.Nonstopped:BAAALgADCgYJBgAAAA==.Nooglet:BAAALgAECgIJAgAAAA==.Noriel:BAAALgADCgEJAgAAAA==.Norikoff:BAACLgAFFH8JAAIcAAMJchWUEAADAQAcAAMJchWUEAADAQAuAAQKfywAAxwACQljIXMCAL0CABwACQljIXMCAL0CACUAAgnrHmwoAKwAAAAA.Norrad:BAAALgADCgYJCAAAAA==.',
Nu='Nubblz:BAAALgAECgQJBQAAAA==.Nutbar:BAAALgADCgYJBgAAAA==.',
Ny='Nyalla:BAAALgADCgkJCQAAAA==.Nynox:BAABLgAECn8aAAMLAAgJCwtAKQBxAQALAAgJCwtAKQBxAQAiAAQJZgRqbgCFAAAAAA==.',
['Nê']='Nêin:BAABLgAECn8XAAIIAAcJfAm9PgA2AQAIAAcJfAm9PgA2AQAAAA==.',
['Nó']='Nóvà:BAAALgADCgYJBgAAAA==.',
Od='Odenpanda:BAAALgADCgEJAQABLgADCgQJBAAUAAAAAA==.',
Of='Offdensen:BAAALgADCgMJAwAAAA==.',
Oh='Ohdii:BAAALgADCgIJAgAAAA==.',
Ok='Okämi:BAAALgAECgMJAwAAAA==.',
Ol='Oldmims:BAAALgAECgUJBgABLgAECgcJFwAJAIchAA==.Oldmimse:BAABLgAECn8XAAMJAAcJhyEgBgD+AQAJAAcJhyEgBgD+AQAIAAUJcxJZOgBEAQAAAA==.Oldmimsy:BAAALgADCgEJAgABLgAECgcJFwAJAIchAA==.',
On='Onedge:BAAALgAECgEJAQAAAA==.Onlybatfans:BAAALgAECgUJBQAAAA==.Onlyvlprfans:BAACLgAFFH8OAAImAAQJPxuIAQAPAQAmAAQJPxuIAQAPAQAuAAQKfygAAiYACAlHJCoCADEDACYACAlHJCoCADEDAAAA.',
Oo='Oojoc:BAAALgADCgEJAQAAAA==.Oojocadin:BAAALgAECgYJDwAAAA==.Oojocshan:BAAALgADCgUJCgABLgAECgYJDwAUAAAAAA==.',
Op='Ophina:BAAALgAECgUJDAAAAA==.',
Or='Orangejello:BAABLgAECn8VAAIOAAYJaxB0SwAoAQAOAAYJaxB0SwAoAQAAAA==.Ormar:BAABLgAECn8UAAIRAAgJeBtMBgBVAgARAAgJeBtMBgBVAgAAAA==.Orodruin:BAAALgADCggJEwAAAA==.Orpseroth:BAABLgAECn8WAAIMAAgJwQ2mJQCrAQAMAAgJwQ2mJQCrAQAAAA==.',
Ow='Own:BAAALgAECgkJBQAAAA==.',
Ox='Oxensham:BAABLgAECn8dAAINAAcJGRaUFwBXAQANAAcJGRaUFwBXAQAAAA==.',
Pa='Paiah:BAAALgADCgQJBgAAAA==.Paladintank:BAABLgAECn8fAAMgAAkJ+RdJBAAJAgAgAAgJHhtJBAAJAgAOAAEJ9AEAAAAAAAAAAA==.Pallyboo:BAAALgADCgUJBQAAAA==.Pallymedic:BAAALgADCgIJAgAAAA==.Pana:BAABLgAECn8VAAIOAAgJIyDxOAA/AgAOAAgJIyDxOAA/AgAAAA==.Pandaoden:BAAALgADCgQJBAAAAA==.Pandoora:BAAALgAECgQJBwAAAA==.Pandy:BAAALgAECgYJDAAAAA==.Pandóra:BAACLgAFFH8KAAITAAMJPxvQLAAWAQATAAMJPxvQLAAWAQAuAAQKfx8AAhMACQl2HT4zAKYCABMACQl2HT4zAKYCAAAA.Panko:BAABLgAECn8fAAQDAAgJphiHFQAYAgADAAgJphiHFQAYAgACAAMJtwLmPABlAAABAAEJxQiaiAAnAAAAAA==.Pannifer:BAAALgAECgQJBAAAAA==.Paolon:BAABLgAECn8UAAMNAAcJxR4YCQANAgANAAcJxR4YCQANAgAGAAEJDBifngAyAAAAAA==.Papasmurph:BAAALgADCgMJBAAAAA==.Papst:BAAALgADCgMJAwAAAA==.Passmidnight:BAAALgADCgEJAgAAAA==.',
Pe='Peeperoni:BAAALgADCgYJBgAAAA==.Pepperbacca:BAAALgADCgcJEwAAAA==.Persepolïs:BAAALgAECgIJAwAAAA==.Pescara:BAAALgAECgYJEgAAAA==.Pestîlence:BAAALgADCgUJBQAAAA==.Peter:BAAALgADCgYJBgAAAA==.Petestreat:BAAALgAECgUJCAAAAA==.Pewster:BAAALgADCgUJBQAAAA==.',
Ph='Phantõm:BAAALgADCgYJCAAAAA==.Phinns:BAAALgAECgQJAwAAAA==.Phylo:BAAALgADCgEJAQAAAA==.',
Pi='Pian:BAAALgADCgkJFgAAAA==.Picker:BAAALgAECgYJCwAAAA==.Pinecones:BAAALgAECgQJBAAAAA==.',
Po='Poledra:BAAALgADCgUJCAAAAA==.Polycurious:BAAALgAECgEJAwAAAA==.Porterah:BAAALgAECggJDgAAAA==.Poughkeepsie:BAAALgADCgkJDgAAAA==.',
Pr='Profanus:BAAALgADCgkJCQABLgAECggJGAACAJUjAA==.',
Pt='Ptolemus:BAAALgADCggJDgAAAA==.',
Pu='Puffthemagic:BAAALgADCgMJAwABLgAECgYJCAAUAAAAAA==.Punchkun:BAABLgAECn8cAAIIAAgJ8hiRKgBlAgAIAAgJ8hiRKgBlAgAAAA==.Punkvc:BAABLgAECn8ZAAILAAgJBiEjCAB2AgALAAgJBiEjCAB2AgAAAA==.',
['Pá']='Párts:BAAALgADCggJDwABLgAECgUJCgAUAAAAAA==.',
Qu='Quaeras:BAABLgAECn8XAAIiAAcJBBHQCABLAQAiAAcJBBHQCABLAQAAAA==.Quonnoth:BAABLgAECn8dAAMYAAgJaQ70EQB5AQAYAAgJaQ70EQB5AQAjAAEJUQG4RgAVAAAAAA==.',
Ra='Raevynn:BAAALgAFFAIJBAAAAA==.Ragath:BAAALgAECgYJDQAAAA==.Ragé:BAEBLgAECn8aAAMEAAgJzCMxAwDHAgAEAAgJzCMxAwDHAgAFAAEJRB54ZABSAAAAAA==.Ralphe:BAABLgAECn8bAAMVAAgJ0RrJBQBgAQAWAAcJ/xs5GwAnAgAVAAcJeBbJBQBgAQAAAA==.Ranahu:BAAALgAECggJDQAAAA==.Rawrionik:BAAALgADCgMJAwAAAA==.Raytow:BAAALgAECgIJBAAAAA==.Raytwo:BAAALgADCgQJBAAAAA==.Razelle:BAABLgAECn8cAAITAAcJDwZyZwALAQATAAcJDwZyZwALAQAAAA==.',
Re='Reckies:BAABLgAECn8XAAIQAAgJigq+PABBAQAQAAgJigq+PABBAQAAAA==.Reconpalymix:BAAALgAECgQJBgAAAA==.Remus:BAAALgAECgcJCQAAAA==.Reshad:BAAALgAECgcJEQAAAA==.Respectwomen:BAAALgAECgEJAgAAAA==.Ressix:BAABLgAECn8fAAIOAAgJHyCMCQCGAgAOAAgJHyCMCQCGAgAAAA==.Retahdin:BAAALgADCgYJBgAAAA==.Retriblution:BAAALgAECgMJAwAAAA==.Rettungslos:BAAALgAECgQJCgABLgAECggJDwAUAAAAAA==.',
Rh='Rhaeyn:BAAALgADCgIJAgABLgAECgQJCQAUAAAAAA==.',
Ri='Ricktick:BAAALgADCgYJBgAAAA==.Rickybobby:BAAALgAECgQJBAAAAA==.Rininewblood:BAAALgADCgcJBwAAAA==.Rivvik:BAAALgAECgEJAQAAAA==.',
Ro='Rockhunter:BAAALgAECgYJDAAAAA==.Rokstarr:BAAALgAECgMJAwABLgAFFAQJEAAPAOAeAA==.Rolis:BAAALgAECgQJCAAAAA==.Ronborules:BAABLgAECn8ZAAIcAAcJ6BC2FgB9AQAcAAcJ6BC2FgB9AQAAAA==.Rosales:BAAALgAECgEJAQABLgAECgUJBgAUAAAAAA==.Rosenta:BAABLgAECn8VAAIRAAYJIBYCFQBoAQARAAYJIBYCFQBoAQAAAA==.Rozencrantz:BAAALgAECgUJEgAAAA==.Rozzel:BAAALgADCgkJFQAAAA==.',
Ru='Rubber:BAAALgAECggJDwAAAA==.Rumlock:BAABLgAECn8VAAMIAAcJMxG/SgAQAQAIAAUJ4Q+/SgAQAQAKAAMJuhTESACUAAAAAA==.',
Sa='Sabai:BAAALgADCgkJIwABLgAECgYJGQAaACUUAA==.Sabing:BAAALgAECgEJAQAAAA==.Sadiewolf:BAAALgAECgEJAQAAAA==.Saeberis:BAAALgADCgYJCQAAAA==.Saganck:BAAALgADCgcJBwAAAA==.Saiah:BAAALgADCgcJBwAAAA==.Sal:BAABLgAECn8fAAIMAAgJRCHSBABUAgAMAAgJRCHSBABUAgAAAA==.Salivan:BAAALgAECgYJEwAAAA==.Sapchat:BAAALgAECgEJAQAAAA==.Sargaris:BAAALgAECgYJCwAAAA==.Sariva:BAAALgADCgIJAwABLgAECgcJFwARAA8gAA==.Sarss:BAAALgAECgQJBAAAAA==.Sarvajna:BAAALgAECgcJDAAAAA==.Sarzphids:BAAALgAECgEJAQAAAA==.Sasara:BAAALgAECgEJAQAAAA==.Satyricon:BAAALgAECgYJDwAAAA==.Savvywalnut:BAAALgAECgUJCQAAAA==.Sawfang:BAAALgAECgQJBAABLgAECggJKwALABokAA==.',
Se='Sedo:BAAALgADCgYJBgAAAA==.Seiya:BAAALgAECgYJEQAAAA==.Selenne:BAAALgADCgQJBAAAAA==.Sendrada:BAAALgAECgEJAQAAAA==.Senji:BAAALgADCgUJBQAAAA==.Sepult:BAAALgAECgIJAwAAAA==.Sevalina:BAAALgAECgcJCQAAAA==.Seål:BAAALgAECgQJDgAAAA==.',
Sh='Shabadoo:BAAALgADCgYJBgABLgAFFAYJGAAMAOwlAA==.Shadowstep:BAAALgAECgQJBAAAAA==.Shambalamps:BAAALgADCgcJCgAAAA==.Shamhuntzu:BAECLgAFFH8PAAIEAAQJgw9PFgAdAQAEAAQJgw9PFgAdAQAuAAQKfyQAAgQACAn/H/wSAOgCAAQACAn/H/wSAOgCAAAA.Shampaign:BAABLgAECn8mAAMGAAgJ4h5OFQC/AQAGAAUJ/x5OFQC/AQANAAgJYRStFgBfAQAAAA==.Shantii:BAAALgAECgQJBwAAAA==.Shaoevoker:BAAALgAECgcJCAAAAA==.Sharnara:BAAALgAECgYJDwAAAA==.Shatterskull:BAABLgAECn8XAAIaAAcJrx9RCgBvAgAaAAcJrx9RCgBvAgAAAA==.Shazera:BAAALgADCgcJDQABLgAECgcJIgAdAMIgAA==.Shazira:BAABLgAECn8iAAIdAAcJwiACCABaAgAdAAcJwiACCABaAgAAAA==.Sheffield:BAAALgAECgMJAwAAAA==.Sheman:BAAALgADCgUJBQAAAA==.Shep:BAAALgAECgQJBAAAAA==.Shermuta:BAAALgAECgMJAwAAAA==.Shocknthaw:BAAALgAFFAIJAwAAAA==.Shortyrn:BAAALgAECgMJAwAAAA==.Shred:BAAALgAECgMJAwAAAA==.Shyvanâ:BAAALgAECgEJAQAAAA==.',
Si='Sidewinder:BAAALgAECgEJAgAAAA==.Silentwounds:BAABLgAECn8lAAMZAAgJIB3xBABiAgAZAAcJnh/xBABiAgAFAAQJJAxURwDXAAAAAA==.Silvercircle:BAABLgAECn8ZAAIIAAYJdBCNPgA2AQAIAAYJdBCNPgA2AQAAAA==.Silverlord:BAAALgAECgQJDwAAAA==.Sinafay:BAACLgAFFH8GAAITAAIJigL7SwCBAAATAAIJigL7SwCBAAAuAAQKfyYAAhMACAmjEkRoAAYCABMACAmjEkRoAAYCAAAA.Sineu:BAAALgADCgcJCQABLgAECggJGAACAJUjAA==.Sinsong:BAABLgAECn8lAAIOAAgJHBX3SQAEAgAOAAgJHBX3SQAEAgAAAA==.Siv:BAABLgAECn8YAAICAAgJlSMLBQA5AwACAAgJlSMLBQA5AwAAAA==.Sivormu:BAAALgADCgcJCQABLgAECggJGAACAJUjAA==.Siwel:BAAALgADCgcJBwAAAA==.',
Sk='Skooks:BAAALgADCgYJBwAAAA==.Skyprincess:BAAALgADCgIJAgAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.',
Sm='Smallbud:BAAALgADCggJDgAAAA==.',
Sn='Snackpaack:BAAALgAECgcJBwAAAA==.Snapjutsu:BAABLgAFFH8FAAICAAMJFBI0GADZAAACAAMJFBI0GADZAAAAAA==.Snorg:BAABLgAECn8XAAMTAAgJbg88LgCqAQATAAgJZw88LgCqAQAoAAIJbwiuGABTAAAAAA==.Snêaky:BAABLgAECn8dAAIWAAgJEB+EAwBoAgAWAAgJEB+EAwBoAgAAAA==.',
So='Solarnova:BAAALgAECgYJEwAAAA==.Soliloquy:BAAALgADCgYJCgAAAA==.Solorn:BAAALgAECggJJgAAAQ==.Sooze:BAABLgAECn8fAAICAAgJfh2pBABnAgACAAgJfh2pBABnAgAAAA==.Sorsen:BAAALgADCgcJCAAAAA==.',
Sp='Sports:BAAALgAECgYJCAAAAA==.Spygon:BAAALgADCgEJAQAAAA==.',
Sr='Srzbisnis:BAAALgADCgYJBgAAAA==.',
St='Stennch:BAAALgADCgYJCQAAAA==.Stianis:BAAALgAECgYJEwAAAA==.Stolinaya:BAABLgAECn8dAAIEAAgJSR56CQBCAgAEAAgJSR56CQBCAgABLgAECgMJAwAUAAAAAA==.Stormcleave:BAAALgAECgQJBgABLgAFFAUJFAANAKwaAA==.Strawberr:BAAALgADCgEJAQAAAA==.Strobila:BAAALgADCgYJBgAAAA==.',
Su='Sudoxe:BAAALgADCgcJBwAAAA==.Supervillain:BAAALgAECgQJBAAAAA==.',
Sy='Sylvèè:BAAALgADCgMJAwAAAA==.Symuelil:BAAALgADCgcJEQAAAA==.Sync:BAAALgADCgYJBgAAAA==.Syrathos:BAACLgAFFH8TAAIEAAcJ+CGZAQBZAgAEAAcJ+CGZAQBZAgAuAAQKfx8AAgQACQl9JB8FAHQDAAQACQl9JB8FAHQDAAAA.Syrioforel:BAAALgAECgQJDQAAAA==.',
['Sø']='Søcks:BAAALgAECgQJBwAAAA==.',
Ta='Talah:BAAALgADCggJFwAAAA==.Talarar:BAAALgADCgQJBAAAAA==.Talfirith:BAAALgADCgIJAgAAAA==.Talla:BAAALgADCgEJAQAAAA==.Tarayn:BAAALgADCgkJEgAAAA==.Tariès:BAAALgAECgEJAQAAAA==.',
Te='Teclis:BAACLgAFFH8JAAITAAQJRRw0FQBtAQATAAQJRRw0FQBtAQAuAAQKfx8AAxMACAkNIqopAMwCABMACAkNIqopAMwCACgABQl2FCYMABABAAAA.Teelove:BAAALgAECgUJCwAAAA==.Telzindrov:BAABLgAECn8WAAIXAAcJlQypCwBSAQAXAAcJlQypCwBSAQAAAA==.Tenden:BAAALgAECgMJAwAAAA==.',
Th='Thalgar:BAAALgAECgUJBwAAAA==.Thalmick:BAABLgAECn8oAAIWAAgJyR1/EQCUAgAWAAgJyR1/EQCUAgAAAA==.Thanoslykev:BAAALgAECgMJAwAAAA==.Thatonetime:BAAALgADCgUJBQAAAA==.Theblackfish:BAABLgAECn8gAAILAAkJ7BDsHACyAQALAAkJ7BDsHACyAQAAAA==.Therealchuck:BAAALgADCgcJCAAAAA==.Thimbles:BAAALgADCgcJDQAAAA==.Thogarn:BAAALgADCgIJAgAAAA==.Thorb:BAAALgAFFAEJAQAAAA==.Thozan:BAAALgADCgIJAgAAAA==.Thundertem:BAAALgADCgIJAgAAAA==.Théière:BAABLgAECn8UAAMYAAcJ9RRdJACaAQAYAAcJ9RRdJACaAQAjAAMJ5wR/MwB5AAAAAA==.',
Ti='Tiraeda:BAAALgAECgYJEgAAAA==.Titoxs:BAAALgAECgMJAwAAAA==.',
To='Tofper:BAAALgAECgIJAgAAAA==.Tonelyn:BAAALgAECgQJCAAAAA==.Toomuchrum:BAABLgAECn8eAAMHAAcJ/iCeFgAFAgAHAAcJ3yCeFgAFAgAnAAIJKiGGDwClAAAAAA==.Torpedo:BAAALgAECgYJDwAAAA==.Totalvision:BAAALgAECgEJAQAAAA==.Totembot:BAABLgAECn8lAAINAAgJXRYgDwCxAQANAAgJXRYgDwCxAQAAAA==.Toughlove:BAAALgAECgQJBgAAAA==.',
Tr='Traver:BAACLgAFFH8LAAITAAQJRhK9GgBfAQATAAQJRhK9GgBfAQAuAAQKfxgAAhMACQkBFg4RAFQCABMACQkBFg4RAFQCAAAA.Trev:BAABLgAECn8oAAITAAkJVB/SDQBxAgATAAkJVB/SDQBxAgAAAA==.Triboluminal:BAAALgADCgEJAQAAAA==.Tripletka:BAAALgAECgEJAQAAAA==.Trogdorgos:BAAALgAECgcJDQABLgAECggJFgAMAMENAA==.Truedemon:BAAALgADCgIJAgAAAA==.Trustfäll:BAAALgAECgYJDwAAAA==.',
Ts='Tsukifang:BAABLgAECn8aAAMQAAcJwwpaGgApAQAQAAcJwwpaGgApAQAPAAEJiwGr6wAXAAAAAA==.',
Tu='Tuc:BAABLgAECn8ZAAIMAAYJ8AwAGwAlAQAMAAYJ8AwAGwAlAQAAAA==.Tulfagen:BAAALgAECgQJBAAAAA==.Turtledots:BAABLgAECn8cAAMKAAgJ2RCRJAA3AQAKAAUJNxWRJAA3AQAIAAYJQgwnUgD6AAAAAA==.Tuxie:BAAALgADCgUJBQAAAA==.',
Ty='Tyndareos:BAAALgAECgUJBgAAAA==.Typhoontravv:BAABLgAECn8mAAMOAAgJHh+BKgB6AgAOAAcJGiOBKgB6AgAgAAgJ+Q/DEQCsAQAAAA==.',
['Tø']='Tøkakagé:BAAALgAECgYJDgAAAA==.',
Uf='Ufearme:BAAALgAECgQJCgAAAA==.',
Ug='Ugabooga:BAABLgAECn8VAAQoAAgJBh8lCQBaAQATAAcJ9xhJcwDsAQAoAAUJ8BwlCQBaAQASAAQJXySQBgAyAQAAAA==.Uggon:BAAALgAECgYJEQAAAA==.',
Um='Umordruid:BAABLgAECn8bAAIkAAcJ/hpOBgClAQAkAAcJ/hpOBgClAQAAAA==.',
Un='Unable:BAAALgAECgcJDgAAAA==.',
Ut='Uthur:BAABLgAECn8VAAIgAAcJsQx1EAD6AAAgAAcJsQx1EAD6AAAAAA==.Utterchaos:BAACLgAFFH8LAAIIAAQJ8QoqHwAlAQAIAAQJ8QoqHwAlAQAuAAQKfx8ABAgACAk1GSpBAAoCAAgACAnsGCpBAAoCAAoABQk3FBgkADkBAAkAAQkAACcuAEIAAAAA.',
Va='Vaea:BAAALgAECgEJAgAAAA==.Vaelaven:BAAALgAECgYJDAAAAA==.Vaelric:BAAALgADCgMJAwAAAA==.Vaeredor:BAABLgAECn8VAAMkAAgJzRdqBADoAQAkAAgJWRVqBADoAQAeAAYJeRYJEQBlAQAAAA==.Valack:BAAALgADCgYJBgAAAA==.Valdaroshi:BAAALgAECgEJAQAAAA==.Valizor:BAAALgAECgIJAwAAAA==.Varaylina:BAAALgADCgUJBQAAAA==.Varty:BAAALgAECgEJAQAAAA==.Vasila:BAABLgAECn8UAAMIAAgJJR/rFQD2AQAIAAYJVhzrFQD2AQAKAAMJoSMYDQDUAAAAAA==.',
Ve='Velaari:BAAALgADCgMJAwAAAA==.Velasti:BAAALgADCgEJAQAAAA==.Velivan:BAAALgAECgMJBgAAAA==.Venruki:BAAALgAECgEJAQAAAA==.Veraa:BAAALgAECgYJDgAAAA==.Vetta:BAACLgAFFH8MAAINAAQJogkoDgAaAQANAAQJogkoDgAaAQAuAAQKfygAAw0ACAmqF64dACMCAA0ACAmqF64dACMCAAYABQnEBpBrAOEAAAAA.',
Vg='Vger:BAAALgADCgkJJgAAAA==.',
Vi='Vineriul:BAAALgADCgYJBgAAAA==.Vinh:BAABLgAECn8dAAIDAAYJ6xelFABtAQADAAYJ6xelFABtAQAAAA==.Vinick:BAAALgAECgEJAQAAAA==.',
Vl='Vl:BAAALgAECgIJAgAAAA==.',
Vo='Voideffects:BAAALgAFFAEJAQAAAA==.Voideon:BAAALgADCgMJBQAAAA==.Volathis:BAAALgADCgcJBwAAAA==.Volgagrad:BAAALgADCgYJCAAAAA==.Volgorion:BAAALgAECgIJAgABLgAFFAQJDgAlAFQdAA==.',
Wa='Walden:BAAALgADCgUJBQAAAA==.Walshaman:BAAALgAECgIJAgABLgAFFAYJGAAMAOwlAA==.Walshy:BAAALgADCgkJCQABLgAFFAYJGAAMAOwlAA==.Wardren:BAAALgADCgcJBwAAAA==.Warmspray:BAAALgAECgQJBgAAAA==.Wauchula:BAAALgAECgYJDwAAAA==.',
We='Websdh:BAAALgAECgQJBAAAAA==.Welkin:BAAALgAECgYJEQAAAA==.',
Wh='Whisp:BAAALgAECgQJCAAAAA==.Whitearrows:BAABLgAECn8UAAQiAAcJExBeEQC5AAALAAUJyQXbVwDCAAAiAAYJKRFeEQC5AAAfAAIJAgZRJwBcAAABLgAECggJIgAPAKEhAA==.Whiteowls:BAABLgAECn8iAAIPAAgJoSF9CwDlAgAPAAgJoSF9CwDlAgAAAA==.Whitetotem:BAAALgAECgYJBgABLgAECggJIgAPAKEhAA==.',
Wi='Wickfel:BAAALgAECgYJCgAAAA==.Willferrell:BAAALgAECgQJBwAAAA==.Winchesters:BAAALgADCgQJBAAAAA==.Windsong:BAAALgADCgEJAQABLgAECggJJQAOABwVAA==.Windstone:BAAALgAECgQJBgABLgAECggJJQAOABwVAA==.Windwalker:BAAALgAECgEJAgABLgAECgEJAwAUAAAAAA==.',
Wo='Wolfgrimm:BAAALgAECgYJEAAAAA==.Wolfsbanne:BAAALgAECgEJAQAAAA==.Woodyy:BAAALgADCgYJDwABLgADCgcJCAAUAAAAAA==.Wooferq:BAAALgADCgYJCQAAAA==.',
Wr='Wreckie:BAAALgAFFAIJAwAAAA==.',
Wu='Wupain:BAAALgAECgQJBAAAAA==.',
Wy='Wyld:BAAALgAECgYJDwAAAA==.',
Xa='Xanid:BAAALgAECgQJCAAAAA==.',
Xd='Xdwarf:BAAALgAECgYJCAABLgAECggJLQAVAOwXAA==.',
Xe='Xeroxoxo:BAACLgAFFH8IAAIHAAQJ7xoxGQBQAQAHAAQJ7xoxGQBQAQAuAAQKfyUAAgcACQmuIX8HAGQDAAcACQmuIX8HAGQDAAAA.Xevric:BAAALgAECgEJAQABLgAECgcJFwABAIsYAA==.',
Ya='Yasman:BAAALgADCgYJBgAAAA==.',
Ye='Yesenia:BAABLgAECn8XAAMcAAYJzCKHDADnAQAcAAYJzCKHDADnAQAaAAEJWA2SKgA2AAABLgAECgcJFwARAA8gAA==.',
Yh='Yhòrm:BAAALgADCgYJBwAAAA==.',
Ym='Ymedead:BAACLgAFFH8OAAMbAAQJIRWhCQBFAQAbAAQJIRWhCQBFAQARAAEJtgZIFwBGAAAuAAQKfygAAxsACAkrH0EHAM8CABsACAkrH0EHAM8CABEABwnlFgwqAKIBAAEuAAMKAQkBABQAAAAA.Ymedruid:BAAALgADCgEJAQAAAA==.',
Yo='Yoroichi:BAABLgAECn8tAAIVAAgJ7BdHAgAJAgAVAAgJ7BdHAgAJAgAAAA==.Yourmomsride:BAAALgAECgUJCAAAAA==.',
Yu='Yudawl:BAAALgADCgUJCAAAAA==.Yueyue:BAAALgAECgUJBgAAAA==.Yuyutsu:BAAALgADCggJFwABLgAECgQJCgAUAAAAAA==.',
['Yá']='Yáng:BAABLgAECn8VAAIXAAcJ4R+BAgCPAgAXAAcJ4R+BAgCPAgAAAA==.',
Za='Zacapan:BAAALgAECgcJEQAAAA==.Zakila:BAAALgADCgMJBAAAAA==.Zamali:BAABLgAECn8iAAIdAAgJqx97AwDOAgAdAAgJqx97AwDOAgAAAA==.Zaraxxi:BAAALgAECgQJBAAAAA==.Zarean:BAAALgAECgcJBwAAAA==.Zaridi:BAAALgAECgYJDAABLgAECgYJGQAaACUUAA==.Zarrgos:BAAALgAECgYJBgAAAA==.Zarye:BAAALgAECgQJBAAAAA==.',
Ze='Zeldorie:BAABLgAECn8UAAIIAAgJQQdIPgA3AQAIAAgJQQdIPgA3AQAAAA==.Zempaï:BAAALgAECgMJAwAAAA==.Zerelion:BAAALgAECgEJAQAAAA==.',
Zi='Zindi:BAABLgAECn8WAAILAAgJhhJVJACKAQALAAgJhhJVJACKAQAAAA==.Ziral:BAAALgADCggJEgAAAA==.',
Zo='Zodd:BAAALgADCgQJBAAAAA==.Zoobee:BAAALgAECgYJEgAAAA==.Zoog:BAACLgAFFH8QAAIdAAQJcxVrBwBeAQAdAAQJcxVrBwBeAQAuAAQKfygAAh0ACAkgG9IdACgCAB0ACAkgG9IdACgCAAAA.',
Zu='Zugalicious:BAAALgAECgcJCAABLgAFFAMJBQAFAF8PAA==.Zuz:BAAALgAECgIJAgAAAA==.',
Zy='Zykex:BAAALgAECgUJCQAAAA==.Zyphera:BAAALgAECgMJAwABLgAECgYJCwAUAAAAAA==.Zyvara:BAAALgAECgYJEwAAAA==.',
['Zä']='Zärèlíä:BAABLgAECn8nAAIBAAgJ4xnqCADsAQABAAgJ4xnqCADsAQAAAA==.',
['Às']='Àstrid:BAABLgAECn8YAAIgAAgJkxZoDAABAgAgAAgJkxZoDAABAgABLgAFFAIJAgAUAAAAAA==.',
['Áp']='Ápollia:BAAALgADCgkJEQAAAA==.Ápollo:BAAALgAECgYJDwAAAA==.',
['Æz']='Æz:BAAALgAECgMJAwAAAA==.',
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

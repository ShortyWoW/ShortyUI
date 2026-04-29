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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Priest-Shadow','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Balance','Shaman-Restoration','Mage-Fire','Mage-Frost','Priest-Holy','Monk-Mistweaver','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Warrior-Protection','Priest-Discipline','Monk-Brewmaster','Warrior-Fury','Paladin-Holy','Druid-Guardian','Paladin-Protection','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','Evoker-Devastation','Warrior-Arms','Shaman-Enhancement','DeathKnight-Frost','Monk-Windwalker','Mage-Arcane','Druid-Feral',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Aberenmonk:BAAALgAECgYJEAAAAA==.Abiz:BAAALgAECgQJAwAAAA==.Abonde:BAAALgAECgUJCgAAAA==.Abraxes:BAAALgAECgUJBgAAAA==.Abysmalguard:BAAALgADCgUJBQAAAA==.',
Ac='Acidemon:BAABLgAECn8VAAMBAAcJnxEBFgBNAQABAAcJww4BFgBNAQACAAQJBhe8QQDyAAAAAA==.',
Ad='Adalaide:BAAALgAECgcJEAAAAA==.',
Ae='Aehda:BAAALgADCgcJDwAAAA==.Aeluna:BAAALgADCgcJCQAAAA==.Aethas:BAAALgADCgMJBAAAAA==.Aevari:BAAALgAECgUJCQAAAA==.',
Ah='Ahkna:BAAALgAECgMJBAAAAA==.',
Ai='Aieo:BAABLgAECn8ZAAIDAAgJQA4zHgArAQADAAgJQA4zHgArAQAAAA==.',
Aj='Ajaâx:BAAALgAECgUJCwAAAA==.',
Al='Alanath:BAAALgADCgYJBgAAAA==.Alathia:BAAALgADCgYJBgAAAA==.Albatross:BAAALgAECgMJAwAAAA==.Aldarya:BAAALgAECgUJBwAAAA==.Aliraeda:BAABLgAECn8aAAQEAAgJCw1iEwD4AAAFAAcJhQluIwANAQAEAAQJNRFiEwD4AAAGAAMJ+QgeWQBjAAAAAA==.Alisara:BAABLgAECn8UAAIHAAgJtB9XDQDTAgAHAAgJtB9XDQDTAgAAAA==.Alish:BAAALgAECgcJBgAAAA==.Alissia:BAAALgAECgIJAwAAAA==.Alistraea:BAAALgAECgQJBQAAAA==.Alitrullbrat:BAAALgAECgYJDgAAAA==.Allargara:BAAALgAECgcJCAAAAA==.Allexx:BAABLgAECn8ZAAIHAAcJyB+RBQAaAgAHAAcJyB+RBQAaAgAAAA==.Alliin:BAAALgADCgcJBwAAAA==.Allyssel:BAABLgAECn8ZAAICAAgJ/SM9BAA2AwACAAgJ/SM9BAA2AwAAAA==.Alyssanan:BAAALgADCgUJBQAAAA==.Alyssarae:BAAALgADCgIJAgAAAA==.',
Am='Amasu:BAACLgAFFH8JAAIIAAQJyBrjBQBrAQAIAAQJyBrjBQBrAQAuAAQKfycAAggACAlqIY8JAOoCAAgACAlqIY8JAOoCAAAA.Ammathendis:BAAALgADCgQJBAAAAA==.',
An='Anastriana:BAAALgAECgYJBwAAAA==.Andrei:BAAALgADCgcJBAAAAA==.Angeal:BAAALgAECgYJDgAAAA==.Animus:BAABLgAECn8WAAIJAAYJQwtKEQD8AAAJAAYJQwtKEQD8AAAAAA==.Annamei:BAAALgAECgMJAwAAAA==.',
Ao='Aoife:BAAALgADCgcJFwAAAA==.Aorina:BAAALgAECgYJDwAAAA==.',
Ap='Aphis:BAAALgAECgYJCgAAAA==.Apocalyptica:BAABLgAECn8UAAIKAAcJrQmXlABTAQAKAAcJrQmXlABTAQAAAA==.',
Ar='Arazalor:BAABLgAECn8VAAILAAcJNwyWFQAYAQALAAcJNwyWFQAYAQAAAA==.Arcangel:BAACLgAFFH8JAAILAAQJPBlzBwBcAQALAAQJPBlzBwBcAQAuAAQKfyQAAwsACAnaJfUFAC0DAAsACAnaJfUFAC0DAAwAAwnXIrVAAC4BAAAA.Arcbane:BAAALgAECgEJAQAAAA==.Arclight:BAAALgAECgEJAQAAAA==.Argand:BAABLgAECn8WAAILAAYJSyGPBABBAgALAAYJSyGPBABBAgAAAA==.Arkahnon:BAAALgADCgUJBgAAAA==.Arthurdent:BAABLgAECn8aAAIJAAYJtCThAgAeAgAJAAYJtCThAgAeAgAAAA==.',
As='Ashenrain:BAAALgAECgQJBAAAAA==.Ashvia:BAAALgAECgQJBQAAAA==.Ashyslashy:BAABLgAECn8UAAIBAAcJuA0TIgD+AAABAAcJuA0TIgD+AAAAAA==.',
At='Atheren:BAABLgAECn8VAAINAAcJvyCoAwBCAgANAAcJvyCoAwBCAgAAAA==.Athshu:BAAALgADCgEJAgAAAA==.Atulan:BAAALgAECggJDQAAAA==.',
Au='Augmented:BAAALgADCggJFAAAAA==.Auntiemimi:BAAALgAECgMJBAAAAA==.Aurenthos:BAAALgADCggJCwAAAA==.Auressali:BAAALgAECgcJDwAAAA==.',
Av='Avalina:BAAALgAECgcJEQAAAA==.Avannar:BAAALgADCgkJIAAAAA==.Avelyn:BAACLgAFFH8QAAMOAAUJ4SYDAABAAgAOAAUJkyYDAABAAgAPAAIJbiOnFQDXAAAuAAQKfxsAAw4ACAklJkQAAHMDAA4ACAklJkQAAHMDAA8AAgnlIHVPAHEAAAAA.Aviae:BAAALgADCgkJDgAAAA==.',
Ay='Ayani:BAABLgAECn8XAAMIAAcJ/RbxKwB9AQAIAAYJeBTxKwB9AQAQAAQJLQh6GABpAAAAAA==.',
Az='Azrine:BAAALgADCgcJDQAAAA==.',
Ba='Bacongrease:BAAALgADCgEJAgAAAA==.Baddkharma:BAAALgADCgYJCwAAAA==.Badras:BAABLgAECn8jAAIHAAgJASS4BQAyAwAHAAgJASS4BQAyAwAAAA==.Bagelz:BAACLgAFFH8JAAIRAAQJaiTFAwCyAQARAAQJaiTFAwCyAQAuAAQKfycAAhEACAk+JR0EAC8DABEACAk+JR0EAC8DAAAA.Balafre:BAAALgADCgUJBQABLgAECgQJBAASAAAAAA==.Balforyn:BAAALgADCggJCQAAAA==.Bathool:BAAALgAECgYJDQAAAA==.Bayla:BAAALgAFFAIJAgABLgAFFAUJEwAPAHUVAA==.Bazzlock:BAAALgAECgYJDQAAAA==.',
Be='Beeblebroxx:BAAALgADCgMJAwAAAA==.Beefcat:BAAALgAECgMJAwABLgAECgYJBgASAAAAAA==.Belwar:BAAALgADCgcJBwAAAA==.Beric:BAABLgAECn8jAAMTAAgJuxtSAwCaAgATAAgJyBlSAwCaAgAUAAMJ4QqHVgB0AAAAAA==.Berriuster:BAAALgAECgIJAgAAAA==.Betadine:BAAALgAECgYJEAAAAA==.',
Bi='Billd:BAAALgADCgIJAgAAAA==.',
Bl='Blade:BAAALgAECgYJEgAAAA==.Blaydesong:BAAALgAECgEJAQAAAA==.Blayse:BAAALgADCgUJBQABLgAECgQJBwASAAAAAA==.Blayseknight:BAAALgAECgQJBwAAAA==.Blazinjohnny:BAAALgAECgYJEAAAAA==.Blightburn:BAAALgAECgYJDQAAAA==.Blurpleberry:BAAALgADCgUJAwAAAA==.',
Bo='Boldan:BAAALgADCgUJBwAAAA==.Bondarias:BAAALgAECgYJDwAAAA==.Boohaha:BAABLgAECn8UAAINAAYJqyLRJgD3AQANAAYJqyLRJgD3AQAAAA==.Borris:BAAALgAFFAEJAQAAAA==.',
Br='Brightwing:BAABLgAECn8dAAIVAAgJgCFtBAAMAwAVAAgJgCFtBAAMAwAAAA==.Brigoryn:BAAALgAECgUJCQAAAA==.Brokenarro:BAAALgADCggJCQAAAA==.',
Bu='Bullshivek:BAABLgAECn8VAAILAAcJnBGaDQB7AQALAAcJnBGaDQB7AQAAAA==.Bussincider:BAAALgAECgQJBgAAAA==.',
Ca='Caale:BAAALgAECgQJBAAAAA==.Caecus:BAABLgAECn8VAAIDAAcJAhwIDwCgAQADAAcJAhwIDwCgAQAAAA==.Callsaul:BAAALgADCgMJCgAAAA==.Careillena:BAAALgAECgYJEAAAAA==.Cate:BAAALgADCgYJCAAAAA==.Caylessa:BAAALgADCgcJBwAAAA==.Caylissa:BAAALgAECgUJCgAAAA==.',
Ce='Celithsong:BAAALgADCgMJAwABLgADCgkJDgASAAAAAA==.Celryth:BAAALgADCgIJAgAAAA==.Cenvoked:BAABLgAECn8ZAAMVAAgJehYOGADUAQAVAAcJlxcOGADUAQAWAAcJewvBDAAdAQAAAA==.',
Cf='Cfs:BAAALgAECgQJBQAAAA==.',
Ch='Charcrash:BAABLgAECn8aAAMBAAYJSCBQNQAjAgABAAYJSCBQNQAjAgAXAAYJWxLIAwAwAQAAAA==.Charl:BAAALgADCgYJBgAAAA==.Charlicious:BAAALgAFFAIJAwABLgAECgYJGgABAEggAA==.Chedwiwwiper:BAAALgADCgIJAgABLgADCgYJBwASAAAAAA==.Cheylia:BAAALgAECgQJBQAAAA==.Chiller:BAAALgAECgQJBwAAAA==.Chimster:BAABLgAECn8XAAIHAAcJtR8KIQA/AgAHAAcJtR8KIQA/AgAAAA==.Chimydakilla:BAAALgAECgUJDgAAAA==.Chiva:BAAALgADCgIJAgAAAA==.Chknlttl:BAABLgAECn8VAAIYAAcJKiFdCwBYAgAYAAcJKiFdCwBYAgAAAA==.Chocomochi:BAAALgAECgcJDQAAAA==.Chrønic:BAAALgADCgUJCgAAAA==.Chuckstrike:BAAALgAECgUJCQAAAA==.Chyna:BAAALgADCgYJBwAAAA==.',
Ci='Cieara:BAAALgADCgYJCgAAAA==.Cinnamonbuns:BAAALgAECgIJAgABLgAECgYJCwASAAAAAA==.',
Cl='Clicked:BAAALgADCgQJBAAAAA==.Clouver:BAAALgADCgYJBgAAAA==.Clown:BAAALgADCgcJBwAAAA==.',
Co='Cody:BAAALgAECgYJDwAAAA==.Constipated:BAAALgADCgUJCAAAAA==.Coolbeans:BAAALgADCgYJBwABLgAECgYJBgASAAAAAA==.Corvò:BAAALgAECgQJBQABLgAECgcJFQAYACohAA==.',
Cr='Craeus:BAABLgAECn8ZAAINAAgJOCEaAQDGAgANAAgJOCEaAQDGAgAAAA==.Credit:BAABLgAECn8hAAMIAAgJuR2kEwBWAgAIAAgJuR2kEwBWAgAZAAYJFxvDHACvAQAAAA==.Criztal:BAAALgADCggJGQAAAA==.Crotalus:BAAALgADCgEJAQAAAA==.Crux:BAAALgADCgMJAwAAAA==.',
Cu='Cupofnoodles:BAAALgAECgQJBAAAAA==.Cursedmayo:BAAALgADCgMJAwAAAA==.',
Cy='Cyerius:BAAALgADCgYJBQAAAA==.Cyonarah:BAAALgAECgUJCQAAAA==.',
Da='Dad:BAAALgAECgIJBQAAAA==.Dahlìa:BAAALgAECgQJBAAAAA==.Daquarius:BAAALgAECgcJCAAAAA==.Darem:BAAALgAECgQJBwAAAA==.Darthis:BAAALgADCgUJBQAAAA==.Daywalker:BAAALgAECgcJCwABLgAECgcJFwABALwfAA==.Daísy:BAAALgAECgEJAgAAAA==.',
De='Deadsword:BAAALgADCgEJAQAAAA==.Deanlol:BAAALgAECgEJAwABLgAECgIJBAASAAAAAA==.Deaorva:BAAALgAECgMJAwAAAA==.Deathbringr:BAAALgAECgQJCQAAAA==.Deathspecter:BAAALgAECgUJCAAAAA==.Deidra:BAAALgADCggJFwAAAA==.Delryth:BAAALgADCgUJBQAAAA==.Demonsitter:BAAALgAECgYJDwAAAA==.Dersdomkie:BAAALgAECgUJBgAAAA==.Deshathoris:BAAALgAECgMJAwAAAA==.',
Di='Diggi:BAAALgAECgYJCwAAAA==.Diosa:BAABLgAECn8XAAIGAAcJpxMpAwBDAQAGAAcJpxMpAwBDAQAAAA==.Dish:BAAALgAECgUJBgAAAA==.Divinekat:BAAALgAECgUJBQAAAA==.',
Dk='Dkagon:BAAALgAECgYJCwAAAA==.',
Do='Docfeelgood:BAAALgADCgIJAgAAAA==.Docholiday:BAAALgAECgYJBwAAAA==.Doode:BAAALgAECgcJDgAAAA==.Dooderonomy:BAABLgAECn8UAAMIAAcJjQ2FDwD+AAAIAAcJjQ2FDwD+AAAQAAUJGwf2VgDZAAAAAA==.Doria:BAAALgAECgEJAQAAAA==.',
Dp='Dpsguide:BAAALgAECgEJBAAAAA==.',
Dr='Drac:BAAALgAECgYJBgAAAA==.Dragaan:BAAALgAECgYJEAAAAA==.Dragonbait:BAABLgAECn8wAAIKAAgJHR83DgC4AQAKAAgJHR83DgC4AQAAAA==.Dragondude:BAAALgAECgcJDQAAAA==.Dragonzbane:BAAALgAECgYJCgAAAA==.Drdoom:BAABLgAECn8lAAMZAAgJ6huDAQB+AgAZAAgJ6huDAQB+AgAQAAgJ5QqhLgCJAQAAAA==.Dreamawake:BAAALgAECgYJEgAAAA==.Drek:BAAALgAECgEJAQAAAA==.Drenched:BAAALgAECgYJCwAAAA==.Drenea:BAAALgADCgkJBQAAAA==.Drimlek:BAAALgAECgEJAQAAAA==.Drunkey:BAABLgAECn8XAAIaAAcJuBenIwDlAQAaAAcJuBenIwDlAQAAAA==.Drâxus:BAAALgAECgIJAgAAAA==.',
Du='Duplicitous:BAAALgADCgkJEgAAAA==.',
Dw='Dwarfsham:BAAALgAECgMJBgAAAA==.Dwarvenrogue:BAAALgADCgMJAwAAAA==.',
Dy='Dyriana:BAAALgADCgkJBQAAAA==.',
Ea='Earlgrei:BAAALgADCgMJAwAAAA==.Earthmother:BAAALgADCgkJCQAAAA==.',
Ed='Edum:BAAALgAECgUJCQAAAA==.',
El='Elcie:BAAALgADCgkJEQAAAA==.Elektraka:BAAALgADCgYJBwAAAA==.Ellasian:BAAALgAECgYJCwAAAA==.Eltria:BAACLgAFFH8JAAIPAAQJwhf6FwBqAQAPAAQJwhf6FwBqAQAuAAQKfycAAg8ACAlaJH4TADMDAA8ACAlaJH4TADMDAAAA.Elyndy:BAABLgAECn8aAAIYAAgJ4B1bBwC0AgAYAAgJ4B1bBwC0AgAAAA==.',
Em='Emishalle:BAAALgADCgMJAwAAAA==.Empathy:BAAALgADCgYJBgAAAA==.',
En='Ensoc:BAAALgAECgcJDwAAAA==.',
Ep='Ephel:BAABLgAECn8VAAIQAAYJjhIBOwBPAQAQAAYJjhIBOwBPAQAAAA==.',
Er='Erenia:BAAALgADCgMJAwAAAA==.Erí:BAAALgAECgYJEAAAAA==.',
Es='Essential:BAACLgAFFH8JAAIbAAQJSxDYCwBFAQAbAAQJSxDYCwBFAQAuAAQKfycAAhsACAnKH5AQAM0CABsACAnKH5AQAM0CAAAA.',
Et='Ethop:BAAALgADCgQJBQABLgAECgYJBgASAAAAAA==.',
Eu='Eulali:BAAALgADCgIJAgAAAA==.',
Ez='Ezalth:BAAALgADCgQJBAAAAA==.Ezz:BAAALgADCgYJBwAAAA==.',
Fa='Fachzile:BAAALgADCgUJBQAAAA==.Faden:BAAALgAECgQJBAABLgAECggJEgASAAAAAA==.Faenara:BAABLgAECn8UAAMcAAcJNREIMwCyAQAcAAcJNREIMwCyAQAKAAUJ+QTNOAC1AAAAAA==.Falafelguy:BAABLgAECn8ZAAIPAAgJ9BvOBwAsAgAPAAgJ9BvOBwAsAgAAAA==.Fayzon:BAABLgAECn8TAAIUAAYJAxYOCABbAQAUAAYJAxYOCABbAQAAAA==.',
Fe='Fedange:BAABLgAECn8UAAIdAAgJtgF1CQCHAAAdAAgJtgF1CQCHAAAAAA==.Felartamiel:BAAALgAECgIJAQAAAA==.Felician:BAAALgADCgcJBwAAAA==.Felii:BAAALgAECgEJAQAAAA==.Felkieler:BAAALgAECgYJDwAAAA==.Ferror:BAAALgADCgMJAwAAAA==.Festermight:BAAALgADCgEJAQAAAA==.Fey:BAAALgAECgYJEwAAAA==.Feydris:BAAALgADCgYJBgABLgADCgYJBgASAAAAAA==.',
Fi='Fieperskaivu:BAAALgAECgYJCAABLgAECgcJFwABALwfAA==.Fiorstrasza:BAAALgADCgEJAwAAAA==.Fireyfox:BAAALgADCgUJBgABLgAECgcJFQAVAGARAA==.',
Fj='Fjshamie:BAAALgADCgcJCAABLgAECgEJAQASAAAAAA==.',
Fl='Flavoune:BAAALgAECgEJAQAAAA==.Flee:BAAALgADCgYJCgAAAA==.',
Fo='Forestspirit:BAABLgAECn8WAAILAAgJdBNUDACOAQALAAgJdBNUDACOAQAAAA==.Forkliftcert:BAAALgAECgYJEwAAAA==.Foxxee:BAAALgADCgYJCQAAAA==.',
Fr='Friednoodle:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzlessly:BAACLgAFFH8FAAIcAAMJ/R7vBAAeAQAcAAMJ/R7vBAAeAQAuAAQKfyMAAhwACQlaIccCAEsDABwACQlaIccCAEsDAAAA.',
['Fí']='Físted:BAAALgADCgUJAwAAAA==.',
Ga='Galaxyman:BAAALgADCgYJCgAAAA==.Gano:BAAALgADCgcJBwAAAA==.Gapeilous:BAAALgAECgMJAwAAAA==.Gargosa:BAAALgAECgYJEwAAAA==.Garybusey:BAAALgADCgEJAQAAAA==.',
Ge='Geist:BAACLgAFFH8JAAMKAAQJlBSaCwBPAQAKAAQJkBSaCwBPAQAeAAEJ7gUKCQArAAAuAAQKfycAAwoACAlMIs4pAH0CAAoACAlMIs4pAH0CAB4ACAlhDpMUAIUBAAAA.Geraith:BAACLgAFFH8JAAIfAAQJwxxXBQBMAQAfAAQJwxxXBQBMAQAuAAQKfycAAh8ACAnLI7UDABsDAB8ACAnLI7UDABsDAAAA.Gerios:BAAALgAECgcJDgAAAA==.',
Gh='Ghefgar:BAAALgAECgUJCgAAAA==.Ghostflair:BAAALgADCgcJCQAAAA==.Ghostflare:BAABLgAECn8VAAIQAAgJVB1NCwCbAgAQAAgJVB1NCwCbAgAAAA==.',
Gl='Glendra:BAABLgAECn8aAAIeAAgJgxbXAwCEAQAeAAgJgxbXAwCEAQAAAA==.Gloomfx:BAAALgAECgUJCwAAAA==.Glowfish:BAAALgAECgYJEAAAAA==.Glowleaf:BAAALgAECgEJAQAAAA==.',
Go='Goatboat:BAAALgADCgYJCgAAAA==.Gohan:BAAALgADCgYJBgAAAA==.Goopz:BAAALgADCgcJBwAAAA==.Gorasu:BAAALgADCgYJBgAAAA==.Gorbosplort:BAAALgAECgEJAQABLgAFFAQJCQACAAEQAA==.',
Gr='Grandeeny:BAAALgAECgYJDwAAAA==.Grandgrimm:BAAALgAECgQJBwAAAA==.Grandzob:BAAALgAECgUJEQAAAA==.Gravix:BAAALgADCgYJBgABLgAECggJFQAgAIwkAA==.Greensleeves:BAAALgADCgkJBQAAAA==.Gregoriusz:BAABLgAECn8fAAIhAAgJUB3EFQB/AgAhAAgJUB3EFQB/AgAAAA==.Greygull:BAAALgAECgQJCAAAAA==.Grimfrost:BAAALgAECgQJBwAAAA==.Grimshadows:BAAALgADCgEJAQAAAA==.Grunin:BAAALgADCgUJBQAAAA==.',
Gu='Guntank:BAABLgAECn8XAAMbAAcJ9he5BwCmAQAbAAcJ9he5BwCmAQAYAAQJwhK9LgDNAAAAAA==.Guntenk:BAAALgADCgkJCQAAAA==.Guzzi:BAAALgAECgQJBQAAAA==.',
Gy='Gyaltsen:BAAALgAECgIJBAAAAA==.',
Ha='Halliestar:BAAALgAECgQJBAABLgAECgQJBAASAAAAAA==.Hategnomer:BAAALgADCgkJCgAAAA==.Havenfell:BAABLgAECn8UAAIYAAgJ0hqMAwCxAQAYAAgJ0hqMAwCxAQAAAA==.Hawkfist:BAABLgAECn8ZAAIHAAgJdhd0CgDCAQAHAAgJdhd0CgDCAQAAAA==.',
He='Hecate:BAAALgAECgcJEgAAAA==.Heinzz:BAAALgAECgYJCwAAAA==.Helah:BAAALgAECgYJBwAAAA==.Hercules:BAAALgAECgYJEwAAAA==.',
Hi='Hierodoulos:BAABLgAECn8XAAILAAcJUCUcAgCqAgALAAcJUCUcAgCqAgAAAA==.Histano:BAAALgAECgcJDAAAAA==.',
Ho='Houdro:BAAALgAECgEJAgAAAA==.',
Hr='Hroth:BAAALgADCgQJBAABLgAECggJGwAcAJodAA==.Hrothgar:BAAALgAECgIJAgABLgAECggJGwAcAJodAA==.',
Hu='Hunteroni:BAAALgADCgMJAwABLgAECgYJBwASAAAAAA==.Huonn:BAAALgAECgYJCgAAAA==.',
Hy='Hyper:BAAALgADCgMJAwAAAA==.',
['Hô']='Hôjack:BAAALgADCgMJAwAAAA==.',
Ic='Icenea:BAAALgADCgcJDAABLgAECggJFAAHALQfAA==.',
Il='Illeiria:BAAALgADCgUJBQAAAA==.',
Im='Impastable:BAAALgADCgcJCgABLgAECgYJBwASAAAAAA==.Impastabrew:BAAALgAECgQJBwABLgAECgYJBwASAAAAAA==.',
In='Inohoe:BAAALgADCgYJBgAAAA==.Inola:BAABLgAECn8YAAIQAAcJtxHICgBLAQAQAAcJtxHICgBLAQAAAA==.Intheron:BAAALgADCgkJEgAAAA==.',
Ir='Ironfur:BAAALgADCgcJDAABLgAECgcJFwAYAK8fAA==.',
Is='Iskrå:BAAALgAECgUJCAAAAA==.',
Iv='Ivellos:BAAALgAECgQJBwABLgAECgcJDwASAAAAAA==.',
Ja='Jacynth:BAAALgAECgEJAQAAAA==.Jaimers:BAABLgAECn8bAAQZAAcJ0BxwAwAGAgAQAAcJ8xvyFAA2AgAZAAYJ/hxwAwAGAgAIAAMJAAfKVABwAAAAAA==.Januz:BAAALgAECgYJCQAAAA==.Javlos:BAAALgAECgMJBAAAAA==.Jaxen:BAAALgAECgYJDQAAAA==.Jaywilde:BAAALgAECgYJCwAAAA==.Jaína:BAAALgADCgcJEwAAAA==.',
Je='Jedzia:BAAALgADCgkJBgAAAA==.Jeeffee:BAAALgAECgUJCgAAAA==.Jeep:BAAALgAECgcJEwAAAA==.Jezell:BAAALgADCgMJAwAAAA==.',
Ji='Jizakazam:BAAALgAECgUJBgAAAA==.',
Jo='Joode:BAAALgAECgEJAQAAAA==.',
Ju='Julls:BAAALgAECgEJAQAAAA==.Justbringit:BAEALgADCgIJAgABLgAECgcJEQASAAAAAA==.',
Ka='Karot:BAAALgAECgYJDQABLgAECgcJGQADAJ8YAA==.Karotten:BAABLgAECn8ZAAIDAAcJnxhhDwCcAQADAAcJnxhhDwCcAQAAAA==.Karthair:BAABLgAECn8VAAQVAAcJYBF1AwCxAQAVAAcJYBF1AwCxAQAWAAMJ5QmMUACJAAAiAAEJgAibQgAqAAAAAA==.Katsumotto:BAAALgADCgMJAwABLgAECgEJAQASAAAAAA==.',
Ke='Keello:BAAALgAECgkJBwAAAA==.',
Kh='Khalasar:BAAALgAECgIJAgAAAA==.Khaleessi:BAAALgADCgYJBgAAAA==.',
Ki='Kianlan:BAAALgADCgUJBgAAAA==.Kiaraa:BAAALgADCggJCwAAAA==.Kintsugi:BAAALgAECgIJAgAAAA==.Kisatchie:BAAALgAECgYJDgAAAA==.Kival:BAAALgAECgQJBwAAAA==.Kivrin:BAAALgAECgEJAQAAAA==.',
Kn='Knawls:BAAALgAECgYJEAAAAA==.',
Ko='Koalitsiya:BAAALgAECgYJEQAAAA==.Kookykrum:BAAALgAECgQJBQAAAA==.Korlys:BAAALgADCgEJAQAAAA==.Korvidia:BAAALgAECgYJDAAAAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Kracklin:BAAALgAECgIJBAAAAA==.Krimez:BAABLgAECn8TAAIWAAcJeBQaIQC3AQAWAAcJeBQaIQC3AQAAAA==.Krow:BAAALgAECgEJAQABLgAECgEJAQASAAAAAA==.Kruzex:BAAALgAECgEJAQAAAA==.Kryne:BAAALgAECgYJCwABLgAECgcJEwAWAHgUAA==.Krynez:BAAALgADCgUJBQABLgAECgcJEwAWAHgUAA==.',
Ku='Kurgash:BAAALgAECgQJBwAAAA==.',
Ky='Kyari:BAAALgAECgIJAgAAAA==.Kymerah:BAAALgADCgcJDQAAAA==.Kyrhios:BAAALgAECgYJDwAAAA==.',
['Kä']='Käggai:BAABLgAECn8XAAMbAAYJ1yGOMADsAQAbAAYJYiCOMADsAQAjAAQJwRkhHAAPAQAAAA==.',
La='Laindra:BAAALgADCgMJAwAAAA==.Lark:BAAALgAECgYJEwAAAA==.Larthas:BAAALgAECgEJAgAAAA==.Lascie:BAAALgAECgYJDwAAAA==.Latrunculon:BAAALgADCgQJBAAAAA==.Lazra:BAAALgADCgYJBgAAAA==.',
Le='Leafykat:BAAALgADCggJFwAAAA==.Leaila:BAAALgAECgIJAgAAAA==.Lealia:BAABLgAECn8ZAAMJAAYJtSFDIgD9AQAJAAYJtSFDIgD9AQAkAAEJAALfLwAkAAABLgAECggJFAAHALQfAA==.Legendfox:BAAALgADCgIJAgAAAA==.Leiha:BAAALgAECgIJAgAAAA==.',
Lg='Lgfuad:BAAALgAECgcJDAAAAA==.',
Li='Liams:BAAALgAECgUJCQAAAA==.Lidori:BAAALgADCgcJDAAAAA==.Lightsent:BAAALgADCgUJBQABLgADCggJFQASAAAAAA==.Lilíth:BAAALgAECgcJBwAAAA==.Linux:BAABLgAECn8UAAIHAAYJbBajSACQAQAHAAYJbBajSACQAQAAAA==.Lisânalgaib:BAAALgAECgQJDAAAAA==.Livide:BAABLgAECn8YAAMQAAgJAR7UCwCUAgAQAAcJ9h/UCwCUAgAZAAgJsA18GwC6AQAAAA==.',
Ll='Llama:BAABLgAECn8VAAIaAAcJCRTyCQBRAQAaAAcJCRTyCQBRAQAAAA==.',
Lo='Lokzilla:BAAALgAECgYJBgAAAA==.Lonamire:BAAALgADCgcJCQAAAA==.',
Lu='Lucithance:BAAALgAECgYJCQAAAA==.Luminarra:BAAALgADCgMJAwAAAA==.Luminianna:BAABLgAECn8ZAAMiAAYJwh1TAQDDAQAiAAYJwh1TAQDDAQAWAAYJcw8SMgA4AQAAAA==.',
Ly='Lydrin:BAAALgAECgQJBQAAAA==.Lynerys:BAAALgAECgQJBAAAAA==.Lynnsbussy:BAAALgAECgQJEgAAAA==.Lytol:BAAALgADCgkJGgAAAA==.',
Ma='Macloc:BAAALgAECgMJBAAAAA==.Madmike:BAAALgAECgQJBAAAAA==.Maedae:BAAALgAECgYJDwAAAA==.Magmyr:BAAALgAECgcJEQAAAA==.Mahli:BAABLgAECn8UAAMFAAcJZh/OWAC9AQAFAAYJ0B3OWAC9AQAGAAMJJxsCMgDwAAAAAA==.Maimah:BAABLgAECn8YAAIPAAYJ3R8oawD/AQAPAAYJ3R8oawD/AQAAAA==.Manpandalock:BAAALgAECgEJAgAAAA==.Maplefire:BAAALgADCggJFQAAAA==.Marrias:BAAALgAECgUJBwAAAA==.Mawrix:BAAALgAECgYJEwAAAA==.Maxieflames:BAAALgADCgYJCwAAAA==.',
Mc='Mcguzzler:BAAALgAECgIJAgAAAA==.',
Me='Melwazul:BAAALgADCgUJBQAAAA==.Meoshi:BAAALgAECgQJDgAAAA==.Merk:BAAALgAECgcJDAAAAA==.Mesuryte:BAACLgAFFH8OAAIgAAQJvyC7AACOAQAgAAQJvyC7AACOAQAuAAQKfyYAAiAACAnuJBUCACgDACAACAnuJBUCACgDAAAA.',
Mi='Mibs:BAABLgAECn8aAAIbAAgJ1R75AQBTAgAbAAgJ1R75AQBTAgAAAA==.Mickal:BAAALgAECgYJEQAAAA==.Mikaelangelo:BAAALgAECgcJEgAAAA==.Mintebrew:BAAALgAECgEJAQAAAA==.Mip:BAAALgAECgYJCwAAAA==.Mirie:BAAALgAECgQJBAAAAA==.',
Mn='Mnrogar:BAAALgADCgMJBAAAAA==.',
Mo='Mohegon:BAAALgADCgMJAwAAAA==.Mohini:BAABLgAECn8aAAMMAAgJHhyJAwD6AQAMAAgJHhyJAwD6AQALAAQJLQ/viADDAAAAAA==.Mohproblems:BAAALgADCgEJAQAAAA==.Mojhohammers:BAAALgADCggJFQAAAA==.Mokaki:BAAALgAECgYJEwAAAA==.Molumens:BAAALgAECgYJCAAAAA==.Monkified:BAAALgADCgcJBwABLgAFFAUJDgAVAOUTAA==.Moogician:BAAALgAECgYJCwAAAA==.Moomama:BAAALgADCgIJAgAAAA==.Moonren:BAAALgADCgYJBgAAAA==.Moonsinna:BAAALgADCggJEwAAAA==.Mooshoofasa:BAAALgADCgMJAwAAAA==.Mooter:BAABLgAECn8iAAITAAgJsRhCBQA9AgATAAgJsRhCBQA9AgAAAA==.Mornix:BAAALgAECgcJCgABLgAECgEJAQASAAAAAA==.Moronic:BAAALgAECgEJAQAAAA==.Mortincarne:BAAALgADCgIJAgAAAA==.',
Mu='Munc:BAAALgADCgYJBgAAAA==.Munchwizard:BAAALgAECgEJAgAAAA==.Murglun:BAAALgAECgQJBAAAAA==.Mushroom:BAAALgAECgYJEwAAAA==.',
My='Mystic:BAAALgAECgYJDAAAAA==.',
Na='Nahaz:BAAALgADCgkJBQAAAA==.Namuswanbrok:BAAALgADCgIJAQAAAA==.Naota:BAABLgAECn8VAAIDAAcJLA/bGwA5AQADAAcJLA/bGwA5AQAAAA==.Naqii:BAAALgAECgMJAwAAAA==.Naqsx:BAAALgAECgYJDwAAAA==.Nareda:BAAALgADCggJBgAAAA==.Narfox:BAABLgAECn8VAAMNAAcJKAlsFQACAQANAAcJKAlsFQACAQAJAAEJeQK2lQAfAAAAAA==.Naryb:BAAALgAFFAEJAQAAAA==.Naughtia:BAAALgADCgEJAQAAAA==.',
Ne='Neameto:BAABLgAECn8eAAMWAAcJoRaWHADiAQAWAAcJoRaWHADiAQAiAAIJSwiPOABUAAAAAA==.Necrophyle:BAAALgAECgYJDQAAAA==.Nefarox:BAAALgAECgUJCwAAAA==.Neon:BAABLgAECn8hAAIJAAgJVR4PAgBMAgAJAAgJVR4PAgBMAgAAAA==.Nerfdarts:BAAALgADCgIJAgAAAA==.Ness:BAAALgADCgYJCgAAAA==.',
Nh='Nhugpow:BAAALgADCgkJCQAAAA==.',
Ni='Nicholas:BAACLgAFFH8FAAIWAAQJDQsmDQAuAQAWAAQJDQsmDQAuAQAuAAQKfyUAAhYACAn4IOEIAOoCABYACAn4IOEIAOoCAAEuAAUUBAkFABYADQsA.Nightriderr:BAAALgAECgEJAgAAAA==.Nightstealer:BAAALgAECgUJCQAAAA==.Nika:BAACLgAFFH8FAAMlAAIJag3bAgCjAAAlAAIJnQfbAgCjAAADAAIJKAyvSACSAAAuAAQKfx4AAgMACAnPHxInAJ8CAAMACAnPHxInAJ8CAAAA.Nikkikayama:BAACLgAFFH8HAAMHAAQJ+hQnBABdAQAHAAQJ+hQnBABdAQAhAAEJnQLPLAA/AAAuAAQKfxwAAwcACAkHIBQLAOwCAAcACAkHIBQLAOwCACEAAgmiBDJ7AFYAAAAA.',
No='Nobzz:BAAALgADCggJEAAAAA==.Nofuratu:BAAALgAECgcJDgAAAA==.Noncomplex:BAAALgAECgYJBgAAAA==.Nonextinct:BAAALgADCggJFwAAAA==.Nonstopped:BAAALgADCgUJBQAAAA==.Noriel:BAAALgADCgEJAgAAAA==.Norikoff:BAACLgAFFH8GAAIbAAMJchWSEAADAQAbAAMJchWSEAADAQAuAAQKfyMAAxsACAnsIqIHAC8DABsACAnsIqIHAC8DACMAAgnrHmgoAKwAAAAA.Norrad:BAAALgADCgMJAwAAAA==.',
Nu='Nubblz:BAAALgAECgEJAQAAAA==.Nutbar:BAAALgADCgYJBgAAAA==.',
Ny='Nyalla:BAAALgADCgkJBQAAAA==.Nynox:BAABLgAECn8VAAMHAAYJZwtEGwAjAQAHAAYJZwtEGwAjAQAhAAQJZgRubgCFAAAAAA==.',
['Nê']='Nêin:BAAALgAECgYJEAAAAA==.',
Oh='Ohdii:BAAALgADCgIJAgAAAA==.',
Ok='Okämi:BAAALgAECgMJAwAAAA==.',
Ol='Oldmims:BAAALgAECgUJBQABLgAECgcJEAASAAAAAA==.Oldmimse:BAAALgAECgcJEAAAAA==.Oldmimsy:BAAALgADCgEJAgABLgAECgcJEAASAAAAAA==.',
On='Onlybatfans:BAAALgAECgUJBQAAAA==.Onlyvlprfans:BAACLgAFFH8HAAIkAAQJ8heqAQBvAQAkAAQJ8heqAQBvAQAuAAQKfycAAiQACAkzJCsCADEDACQACAkzJCsCADEDAAAA.',
Oo='Oojoc:BAAALgADCgEJAQAAAA==.Oojocadin:BAAALgAECgYJDwAAAA==.Oojocshan:BAAALgADCgUJCgABLgAECgYJDwASAAAAAA==.',
Op='Ophina:BAAALgAECgUJCQAAAA==.',
Or='Orangejello:BAAALgAECgYJDwAAAA==.Ormar:BAAALgAECgYJDwAAAA==.Orodruin:BAAALgADCgcJDAAAAA==.Orpseroth:BAABLgAECn8WAAIIAAgJwQ2fJQCrAQAIAAgJwQ2fJQCrAQAAAA==.',
Ow='Own:BAAALgAECgkJBAAAAA==.',
Ox='Oxensham:BAABLgAECn8dAAIJAAcJGRYvCgBZAQAJAAcJGRYvCgBZAQAAAA==.',
Pa='Paiah:BAAALgADCgQJBgAAAA==.Paladintank:BAABLgAECn8UAAIeAAcJgxlEBAByAQAeAAcJgxlEBAByAQAAAA==.Pallyboo:BAAALgADCgUJBQAAAA==.Pallymedic:BAAALgADCgIJAgAAAA==.Pana:BAAALgAECgYJEAAAAA==.Pandaoden:BAAALgADCgQJBAAAAA==.Pandoora:BAAALgAECgQJBwAAAA==.Pandy:BAAALgAECgYJBgAAAA==.Pandóra:BAACLgAFFH8GAAIPAAMJAhBBOQC4AAAPAAMJAhBBOQC4AAAuAAQKfx0AAg8ACAmsHTszAKYCAA8ACAmsHTszAKYCAAAA.Panko:BAABLgAECn8cAAMRAAgJphhXFQAcAgARAAgJphhXFQAcAgAmAAEJxQiViAAnAAAAAA==.Pannifer:BAAALgAECgQJBAAAAA==.Paolon:BAAALgAECgcJDgAAAA==.Papasmurph:BAAALgADCgMJAwAAAA==.Passmidnight:BAAALgADCgEJAgAAAA==.',
Pe='Peeperoni:BAAALgADCgYJBgAAAA==.Pepperbacca:BAAALgADCgcJEwAAAA==.Persepolïs:BAAALgAECgEJAQAAAA==.Pescara:BAAALgAECgYJDAAAAA==.Pestîlence:BAAALgADCgUJBQAAAA==.Peter:BAAALgADCgYJBgAAAA==.Petestreat:BAAALgAECgQJBQAAAA==.Pewster:BAAALgADCgUJBQAAAA==.',
Ph='Phantõm:BAAALgADCgYJCAAAAA==.Phinns:BAAALgAECgQJAwAAAA==.Phylo:BAAALgADCgEJAQAAAA==.',
Pi='Pian:BAAALgADCgkJFgAAAA==.Picker:BAAALgAECgYJCwAAAA==.Pinecones:BAAALgAECgQJBAAAAA==.',
Po='Poledra:BAAALgADCgUJBQAAAA==.Porterah:BAAALgAECgcJCwAAAA==.Poughkeepsie:BAAALgADCgkJDgAAAA==.',
Pr='Profanus:BAAALgADCgkJCQABLgAECggJEgASAAAAAA==.',
Pt='Ptolemus:BAAALgADCggJDgAAAA==.',
Pu='Punchkun:BAABLgAECn8aAAIFAAgJ8hiRKgBlAgAFAAgJ8hiRKgBlAgAAAA==.Punkvc:BAAALgAECgYJEQAAAA==.',
['Pá']='Párts:BAAALgADCggJDQABLgAECgUJCgASAAAAAA==.',
Qu='Quaeras:BAABLgAECn8UAAIhAAcJnw1dBQAxAQAhAAcJnw1dBQAxAQAAAA==.Quonnoth:BAAALgAECgYJEwAAAA==.',
Ra='Raevynn:BAAALgAECgUJBgABLgAFFAUJDgAVAOUTAA==.Ragath:BAAALgAECgYJDQAAAA==.Ragé:BAEALgAECgcJEQAAAA==.Ralphe:BAABLgAECn8XAAMUAAgJ0Ro8GwAnAgAUAAcJ/xs8GwAnAgATAAYJGRYqBAAYAQAAAA==.Ranahu:BAAALgAECgQJBQAAAA==.Rawrionik:BAAALgADCgMJAwAAAA==.Raytow:BAAALgAECgIJBAAAAA==.Raytwo:BAAALgADCgQJBAAAAA==.Razelle:BAABLgAECn8VAAIPAAcJzAUhOgDaAAAPAAcJzAUhOgDaAAAAAA==.',
Re='Reckies:BAABLgAECn8XAAIMAAgJigq9PABBAQAMAAgJigq9PABBAQAAAA==.Reconpalymix:BAAALgAECgIJBAAAAA==.Remus:BAAALgAECgcJCAAAAA==.Reshad:BAAALgAECgYJCgAAAA==.Respectwomen:BAAALgAECgEJAQAAAA==.Ressix:BAABLgAECn8VAAIKAAcJxCBYDADOAQAKAAcJxCBYDADOAQAAAA==.Retahdin:BAAALgADCgYJBgAAAA==.Retriblution:BAAALgAECgMJAwAAAA==.Rettungslos:BAAALgAECgQJCQAAAA==.',
Rh='Rhaeyn:BAAALgADCgIJAgABLgAECgQJBwASAAAAAA==.',
Ri='Ricktick:BAAALgADCgYJBgAAAA==.Rickybobby:BAAALgADCgYJBwAAAA==.Rininewblood:BAAALgADCgcJBwAAAA==.Rivvik:BAAALgAECgEJAQAAAA==.',
Ro='Rockhunter:BAAALgAECgYJBgAAAA==.Rokstarr:BAAALgAECgMJAwABLgAFFAQJCQALADwZAA==.Rolis:BAAALgAECgQJCAAAAA==.Ronborules:BAAALgAECgYJEgAAAA==.Rosales:BAAALgAECgEJAQAAAA==.Rosenta:BAAALgAECgYJDwAAAA==.Rozencrantz:BAAALgAECgUJDgAAAA==.Rozzel:BAAALgADCgkJFQAAAA==.',
Ru='Rubber:BAAALgAECgcJDgAAAA==.Rumlock:BAABLgAECn8VAAMFAAcJMxEyIAAgAQAFAAUJ4Q8yIAAgAQAGAAMJuhTBSACUAAAAAA==.',
Sa='Sabai:BAAALgADCgkJGgABLgAECgYJEwASAAAAAA==.Sabing:BAAALgADCgkJCgAAAA==.Sadiewolf:BAAALgADCgkJEgAAAA==.Saeberis:BAAALgADCgIJAgAAAA==.Saiah:BAAALgADCgcJBwAAAA==.Sal:BAABLgAECn8bAAIIAAgJuB2yDAC3AgAIAAgJuB2yDAC3AgAAAA==.Salivan:BAAALgAECgUJCwAAAA==.Sargaris:BAAALgAECgYJCwAAAA==.Sarss:BAAALgAECgMJAwAAAA==.Sarvajna:BAAALgAECgUJBwAAAA==.Sarzphids:BAAALgADCggJCwAAAA==.Sasara:BAAALgAECgEJAQAAAA==.Satyricon:BAAALgAECgUJCQAAAA==.Savvywalnut:BAAALgAECgQJBAAAAA==.Sawfang:BAAALgADCgEJAQABLgAECggJIwAHAAEkAA==.',
Se='Sedo:BAAALgADCgYJBgAAAA==.Seiya:BAAALgAECgYJDwAAAA==.Selenne:BAAALgADCgQJBAAAAA==.Sendrada:BAAALgAECgEJAQAAAA==.Senji:BAAALgADCgUJBQAAAA==.Sepult:BAAALgAECgIJAwAAAA==.Sevalina:BAAALgAECgcJBwAAAA==.Seål:BAAALgAECgQJDgAAAA==.',
Sh='Shabadoo:BAAALgADCgYJBgABLgAFFAYJEwAIAGklAA==.Shadowstep:BAAALgAECgQJBAAAAA==.Shambalamps:BAAALgADCgcJCgAAAA==.Shamhuntzu:BAECLgAFFH8JAAIBAAQJVAwrFwAXAQABAAQJVAwrFwAXAQAuAAQKfycAAgEACAkAIPQSAOgCAAEACAkAIPQSAOgCAAAA.Shampaign:BAABLgAECn8cAAMJAAcJHhJXMwCMAQAJAAcJHhJXMwCMAQANAAQJjB/BDABxAQAAAA==.Shantii:BAAALgAECgMJAwAAAA==.Shaoevoker:BAAALgAECgcJCAAAAA==.Sharnara:BAAALgAECgYJDwAAAA==.Shatterskull:BAABLgAECn8XAAIYAAcJrx9RCgBvAgAYAAcJrx9RCgBvAgAAAA==.Shazera:BAAALgADCgcJDQABLgAECgcJHAAcAJwcAA==.Shazira:BAABLgAECn8cAAIcAAcJnByEGABOAgAcAAcJnByEGABOAgAAAA==.Sheffield:BAAALgAECgMJAwAAAA==.Sheman:BAAALgADCgUJBQAAAA==.Shep:BAAALgAECgIJAgAAAA==.Shocknthaw:BAAALgAFFAIJAwAAAA==.Shred:BAAALgADCgYJDAAAAA==.Shyvanâ:BAAALgAECgEJAQAAAA==.',
Si='Sidewinder:BAAALgAECgEJAQAAAA==.Silentwounds:BAABLgAECn8eAAMXAAgJrRzzBABiAgAXAAcJFx/zBABiAgACAAQJJAxRRwDXAAAAAA==.Silvercircle:BAAALgAECgUJEgAAAA==.Silverlord:BAAALgAECgQJCwAAAA==.Sinafay:BAABLgAECn8mAAIPAAgJoxJIaAAGAgAPAAgJoxJIaAAGAgAAAA==.Sineu:BAAALgADCgcJCQABLgAECggJEgASAAAAAA==.Sinsong:BAABLgAECn8lAAIKAAgJHBUESgAEAgAKAAgJHBUESgAEAgAAAA==.Siv:BAAALgAECggJEgAAAA==.Sivormu:BAAALgADCgcJCQABLgAECggJEgASAAAAAA==.Siwel:BAAALgADCgcJBwAAAA==.',
Sk='Skooks:BAAALgADCgYJBwAAAA==.Skyprincess:BAAALgADCgIJAgAAAA==.',
Sm='Smallbud:BAAALgADCggJDgAAAA==.',
Sn='Snackpaack:BAAALgAECgcJBQAAAA==.Snapjutsu:BAAALgAFFAEJAQAAAA==.Snorg:BAAALgAECgYJDgAAAA==.Snêaky:BAABLgAECn8WAAIUAAgJjx51AQBRAgAUAAgJjx51AQBRAgAAAA==.',
So='Solarnova:BAAALgAECgYJDQAAAA==.Soliloquy:BAAALgADCgYJCgAAAA==.Solorn:BAAALgAECgYJHAAAAQ==.Sooze:BAABLgAECn8VAAIaAAcJbhwNGgAzAgAaAAcJbhwNGgAzAgAAAA==.Sorsen:BAAALgADCgcJCAAAAA==.',
Sp='Sports:BAAALgAECgYJBgAAAA==.Spygon:BAAALgADCgEJAQAAAA==.',
Sr='Srzbisnis:BAAALgADCgYJBgAAAA==.',
St='Stennch:BAAALgADCgYJCQAAAA==.Stianis:BAAALgAECgYJDwAAAA==.Stolinaya:BAABLgAECn8UAAIBAAcJyxzUNAAlAgABAAcJyxzUNAAlAgABLgADCgMJAwASAAAAAA==.Stormcleave:BAAALgAECgQJBgABLgAFFAUJDwAJACwZAA==.Strobila:BAAALgADCgYJBgAAAA==.',
Su='Supervillain:BAAALgAECgQJBAAAAA==.',
Sy='Sylvèè:BAAALgADCgMJAwAAAA==.Symuelil:BAAALgADCgcJEQAAAA==.Sync:BAAALgADCgYJBgAAAA==.Syrathos:BAACLgAFFH8SAAIBAAYJuCGZAQBZAgABAAYJuCGZAQBZAgAuAAQKfx4AAgEACQl9JBsFAHQDAAEACQl9JBsFAHQDAAAA.Syrioforel:BAAALgAECgQJCgAAAA==.',
['Sø']='Søcks:BAAALgAECgQJBwAAAA==.',
Ta='Talah:BAAALgADCggJFwAAAA==.Talarar:BAAALgADCgQJBAAAAA==.Talla:BAAALgADCgEJAQAAAA==.Tarayn:BAAALgADCgkJCQAAAA==.Tariès:BAAALgADCgcJCQAAAA==.',
Te='Teclis:BAACLgAFFH8GAAIPAAQJyxCkHQBUAQAPAAQJyxCkHQBUAQAuAAQKfx4AAw8ACAkNIqkpAMwCAA8ACAkNIqkpAMwCACcABQl2FCQMABABAAAA.Teelove:BAAALgAECgUJCAAAAA==.Telzindrov:BAAALgAECgcJDwAAAA==.Tenden:BAAALgAECgMJAwAAAA==.',
Th='Thalgar:BAAALgAECgUJBwAAAA==.Thalmick:BAABLgAECn8nAAIUAAgJyR2BEQCUAgAUAAgJyR2BEQCUAgAAAA==.Thanoslykev:BAAALgAECgMJAwAAAA==.Theblackfish:BAABLgAECn8aAAIHAAgJMhKlPAC8AQAHAAgJMhKlPAC8AQAAAA==.Thimbles:BAAALgADCgcJDQAAAA==.Thundertem:BAAALgADCgIJAgAAAA==.Théière:BAABLgAECn8UAAMWAAcJ9RRUJACaAQAWAAcJ9RRUJACaAQAiAAMJ5wR4MwB5AAAAAA==.',
Ti='Tiraeda:BAAALgAECgUJCgAAAA==.Titoxs:BAAALgADCgMJAwAAAA==.',
To='Tonelyn:BAAALgAECgQJBwAAAA==.Toomuchrum:BAABLgAECn8WAAMDAAYJPSLhCgDRAQADAAYJGCLhCgDRAQAlAAIJKiGFDwClAAAAAA==.Torpedo:BAAALgAECgYJCgAAAA==.Totembot:BAABLgAECn8iAAIJAAgJRBY9BgCrAQAJAAgJRBY9BgCrAQAAAA==.Toughlove:BAAALgAECgQJBQAAAA==.',
Tr='Traver:BAAALgAFFAMJBAAAAA==.Trev:BAABLgAECn8bAAIPAAgJTR9wJwDVAgAPAAgJTR9wJwDVAgAAAA==.Triboluminal:BAAALgADCgEJAQAAAA==.Tripletka:BAAALgAECgEJAQAAAA==.Trogdorgos:BAAALgAECgcJBwABLgAECggJFgAIAMENAA==.Truedemon:BAAALgADCgIJAgAAAA==.Trustfäll:BAAALgAECgUJCQAAAA==.',
Ts='Tsukifang:BAAALgAECgcJEwAAAA==.',
Tu='Tuc:BAAALgAECgYJEwAAAA==.Tulfagen:BAAALgAECgIJAgAAAA==.Turtledots:BAABLgAECn8cAAMGAAgJ2RCQJAA3AQAGAAUJNxWQJAA3AQAFAAYJQgzxJQD9AAAAAA==.Tuxie:BAAALgADCgUJBQAAAA==.',
Ty='Tyndareos:BAAALgAECgQJBAAAAA==.Typhoontravv:BAABLgAECn8mAAMKAAgJHh+IKgB6AgAKAAcJGiOIKgB6AgAeAAgJ+Q/CEQCsAQAAAA==.',
['Tø']='Tøkakagé:BAAALgAECgYJCAAAAA==.',
Uf='Ufearme:BAAALgAECgMJBgAAAA==.',
Ug='Ugabooga:BAABLgAECn8VAAQnAAgJBh8kCQBaAQAPAAcJ9xhVcwDsAQAnAAUJ8BwkCQBaAQAOAAQJXySQBgAyAQAAAA==.Uggon:BAAALgAECgUJCQAAAA==.',
Um='Umordruid:BAABLgAECn8YAAIoAAcJOBjwAgCYAQAoAAcJOBjwAgCYAQAAAA==.',
Un='Unable:BAAALgAECgYJBwAAAA==.',
Ut='Uthur:BAAALgAECgYJEAAAAA==.Utterchaos:BAACLgAFFH8GAAIFAAQJmgMgGwAbAQAFAAQJmgMgGwAbAQAuAAQKfx4ABAUACAk1GS1BAAoCAAUACAnsGC1BAAoCAAYABQk3FBckADkBAAQAAQkAACQuAEIAAAAA.',
Va='Vaea:BAAALgAECgEJAgAAAA==.Vaelaven:BAAALgAECgYJBgAAAA==.Vaeredor:BAAALgAECgYJDQAAAA==.Valack:BAAALgADCgYJBgAAAA==.Valdaroshi:BAAALgAECgEJAQAAAA==.Valizor:BAAALgAECgIJAwAAAA==.Varty:BAAALgAECgEJAQAAAA==.Vasila:BAAALgAECgcJDAAAAA==.',
Ve='Velaari:BAAALgADCgMJAwAAAA==.Velasti:BAAALgADCgEJAQAAAA==.Velivan:BAAALgAECgIJBAAAAA==.Venruki:BAAALgAECgEJAQAAAA==.Veraa:BAAALgAECgYJDgAAAA==.Vetta:BAACLgAFFH8GAAIJAAMJtAjdEQDZAAAJAAMJtAjdEQDZAAAuAAQKfycAAwkACAmJF60dACMCAAkACAmJF60dACMCAA0ABQnEBo5rAOEAAAAA.',
Vg='Vger:BAAALgADCgkJHQAAAA==.',
Vi='Vineriul:BAAALgADCgYJBgAAAA==.Vinh:BAAALgAECgYJEgAAAA==.Vinick:BAAALgAECgEJAQAAAA==.',
Vl='Vl:BAAALgAECgIJAgAAAA==.',
Vo='Voideffects:BAAALgAFFAEJAQAAAA==.Voideon:BAAALgADCgMJBQAAAA==.Volathis:BAAALgADCgcJBwAAAA==.Volgagrad:BAAALgADCgYJCAAAAA==.',
Wa='Walden:BAAALgADCgUJBQAAAA==.Walshaman:BAAALgAECgIJAgABLgAFFAYJEwAIAGklAA==.Walshy:BAAALgADCgkJCQABLgAFFAYJEwAIAGklAA==.Wardren:BAAALgADCgcJBwAAAA==.Warmspray:BAAALgAECgQJBQAAAA==.Wauchula:BAAALgAECgQJBAAAAA==.',
We='Websdh:BAAALgAECgQJBAAAAA==.Welkin:BAAALgAECgYJEAAAAA==.',
Wh='Whisp:BAAALgAECgQJBAAAAA==.Whitearrows:BAAALgAECgYJDQABLgAECggJIgALAKEhAA==.Whiteowls:BAABLgAECn8iAAILAAgJoSF8CwDlAgALAAgJoSF8CwDlAgAAAA==.Whitetotem:BAAALgAECgYJBgABLgAECggJIgALAKEhAA==.',
Wi='Wickfel:BAAALgAECgQJBAAAAA==.Willferrell:BAAALgAECgQJBgAAAA==.Winchesters:BAAALgADCgQJBAAAAA==.Windsong:BAAALgADCgEJAQABLgAECggJJQAKABwVAA==.Windstone:BAAALgAECgQJBgABLgAECggJJQAKABwVAA==.Windwalker:BAAALgAECgEJAQABLgAECgEJAQASAAAAAA==.',
Wo='Wolfgrimm:BAAALgAECgYJCAAAAA==.Wolfsbanne:BAAALgAECgEJAQAAAA==.Woodyy:BAAALgADCgYJDwAAAA==.Wooferq:BAAALgADCgYJCQAAAA==.',
Wr='Wreckie:BAAALgAFFAIJAgAAAA==.',
Wu='Wupain:BAAALgADCgkJEgAAAA==.',
Wy='Wyld:BAAALgAECgUJCQAAAA==.',
Xa='Xanid:BAAALgAECgQJBQAAAA==.',
Xd='Xdwarf:BAAALgAECgYJBgABLgAECgcJJQATAIIYAA==.',
Xe='Xeroxoxo:BAABLgAECn8lAAIDAAkJriF/BwBkAwADAAkJriF/BwBkAwAAAA==.Xevric:BAAALgADCgkJCgABLgAECgYJEAASAAAAAA==.',
Ya='Yasman:BAAALgADCgYJBgAAAA==.',
Ye='Yesenia:BAAALgAECgUJDAABLgAECgcJEQASAAAAAA==.',
Yh='Yhòrm:BAAALgADCgYJBwAAAA==.',
Ym='Ymedead:BAACLgAFFH8IAAMZAAQJuhKhCQBFAQAZAAQJuhKhCQBFAQAQAAEJtgYnCQBGAAAuAAQKfycAAxkACAkGHzwHAM8CABkACAkGHzwHAM8CABAABwnlFgsqAKIBAAEuAAMKAQkBABIAAAAA.Ymedruid:BAAALgADCgEJAQAAAA==.',
Yo='Yoroichi:BAABLgAECn8lAAITAAcJghhyAQDFAQATAAcJghhyAQDFAQAAAA==.Yourmomsride:BAAALgAECgUJAwAAAA==.',
Yu='Yudawl:BAAALgADCgUJBQAAAA==.Yueyue:BAAALgAECgUJBgAAAA==.Yuyutsu:BAAALgADCggJFwABLgAECgQJBQASAAAAAA==.',
['Yá']='Yáng:BAAALgAECgYJDgAAAA==.',
Za='Zacapan:BAAALgAECgYJCwAAAA==.Zakila:BAAALgADCgMJBAAAAA==.Zamali:BAABLgAECn8bAAIcAAgJmh1mAgB2AgAcAAgJmh1mAgB2AgAAAA==.Zaraxxi:BAAALgAECgQJBAAAAA==.Zarean:BAAALgAECgcJBwAAAA==.Zaridi:BAAALgAECgYJBgABLgAECgYJEwASAAAAAA==.Zarrgos:BAAALgAECgYJBgAAAA==.Zarye:BAAALgAECgQJBAAAAA==.',
Ze='Zeldorie:BAAALgAECgYJDQAAAA==.Zempaï:BAAALgAECgMJAwAAAA==.Zerelion:BAAALgAECgEJAQAAAA==.',
Zi='Zindi:BAAALgAECgYJDgAAAA==.Ziral:BAAALgADCgYJCwAAAA==.',
Zo='Zodd:BAAALgADCgQJBAAAAA==.Zoobee:BAAALgAECgYJEgAAAA==.Zoog:BAACLgAFFH8JAAIcAAQJyRNeBwBeAQAcAAQJyRNeBwBeAQAuAAQKfycAAhwACAkJG9MdACgCABwACAkJG9MdACgCAAAA.',
Zu='Zugalicious:BAAALgAECgcJCAABLgAECgkJJQACAEYiAA==.Zuz:BAAALgADCgQJBAAAAA==.',
Zy='Zykex:BAAALgAECgUJCQAAAA==.Zyvara:BAAALgAECgYJDQAAAA==.',
['Zä']='Zärèlíä:BAABLgAECn8kAAImAAgJ0xntEABzAgAmAAgJ0xntEABzAgAAAA==.',
['Às']='Àstrid:BAABLgAECn8YAAIeAAgJkxZnDAABAgAeAAgJkxZnDAABAgAAAA==.',
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

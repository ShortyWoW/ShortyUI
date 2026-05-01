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

local lookup = {'Shaman-Restoration','Warlock-Destruction','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Hunter-Survival','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Monk-Brewmaster','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Druid-Balance','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Warrior-Arms','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aartoo:BAAALgADCgUJBwAAAA==.',
Ac='Ackreshanot:BAAALgAECgQJBQABLgAFFAQJCgABAE4dAA==.Acuminada:BAAALgADCgUJBQAAAA==.Acuna:BAABLgAECn8VAAICAAYJTg7GIQBHAQACAAYJTg7GIQBHAQAAAA==.',
Ae='Aere:BAAALgAECgMJBAAAAA==.Aerotika:BAAALgADCgcJBwAAAA==.',
Ai='Airz:BAABLgAECn8XAAIDAAYJdxlMDwCyAQADAAYJdxlMDwCyAQAAAA==.',
Ak='Akennethpaly:BAAALgADCgQJBwAAAA==.Aknou:BAAALgADCgQJBAAAAA==.Akrichie:BAAALgAECgEJAQABLgAFFAYJCgAEAF8JAA==.Akudama:BAAALgAECgQJBwAAAA==.Akâkiôs:BAABLgAECn8UAAIFAAcJthOpIAAVAQAFAAcJthOpIAAVAQAAAA==.',
Al='Aladorman:BAAALgAECgQJDAAAAA==.Albertlin:BAAALgAECgcJBwAAAA==.Aldin:BAAALgAECgUJDgAAAA==.Aleisterr:BAAALgADCgEJAQAAAA==.Alexpaladin:BAAALgADCgEJAQAAAA==.Altarya:BAAALgAECgYJBgABLgAECgcJDgAGAAAAAA==.Altex:BAABLgAECn8hAAIHAAkJ3xmwEwA9AgAHAAkJ3xmwEwA9AgAAAA==.Altexa:BAAALgADCgMJAwABLgAECggJFAAFALkcAA==.Altriimus:BAAALgAECgQJBgAAAA==.',
Am='Amakuagsak:BAABLgAECn8WAAIIAAYJEg+wTQDlAAAIAAYJEg+wTQDlAAAAAA==.Amicus:BAABLgAECn8WAAIJAAYJdw1EMwAMAQAJAAYJdw1EMwAMAQAAAA==.',
An='Anadarmas:BAAALgAECgEJAgAAAA==.Ancestor:BAAALgADCgUJBQAAAA==.Aneki:BAAALgADCgEJAQAAAA==.Angelcastiel:BAAALgADCgEJAQAAAA==.Anothertalas:BAAALgAECgIJAQAAAA==.Anthren:BAAALgADCgYJBgABLgAECgIJAwAGAAAAAA==.Anthrun:BAAALgADCgEJAQABLgAECgIJAwAGAAAAAA==.',
Ao='Aoifè:BAAALgAECgMJBgAAAA==.',
Ap='Apollo:BAABLgAECn8cAAMKAAgJ/xspJgCrAQAKAAcJ2xwpJgCrAQALAAMJdgfQdQCjAAAAAA==.Apolynnae:BAAALgADCgMJAwABLgAFFAEJAQAGAAAAAA==.Apolynnæ:BAAALgAFFAEJAQAAAA==.',
Aq='Aquanoria:BAAALgADCggJEwAAAA==.',
Ar='Aragaren:BAAALgAECgYJBgAAAA==.Arasthel:BAAALgAECggJCwAAAA==.Arthalion:BAAALgAECgEJAQAAAA==.Arvellonwen:BAAALgADCgEJAQAAAA==.',
As='Ascalapha:BAAALgAECgcJBwAAAA==.Ashe:BAACLgAFFH8SAAMMAAUJBCN9AQCVAQAMAAQJ8R59AQCVAQANAAUJ2Ru9CQB9AQAuAAQKfygAAw0ACQmiJkIAAO8DAA0ACQmdJkIAAO8DAAwAAwkxJsUQAFUBAAAA.',
At='Attabubble:BAAALgADCgEJAQABLgAFFAQJCwAIAGAdAA==.Attaraxia:BAACLgAFFH8LAAIIAAQJYB2CCABkAQAIAAQJYB2CCABkAQAuAAQKfycAAwgACQkSI/0JAPgCAAgACQkSI/0JAPgCAA0AAQm4AXiZABsAAAAA.',
Au='Aure:BAAALgADCgMJAwAAAA==.Aurelith:BAAALgADCgMJBAAAAA==.Auvona:BAAALgAECgYJCAAAAA==.',
Av='Avalora:BAAALgADCgcJCQAAAA==.',
Az='Azaleth:BAAALgAECgYJBgAAAA==.Azavin:BAABLgAECn8WAAILAAgJNAwGNgCkAQALAAgJNAwGNgCkAQAAAA==.',
Ba='Babba:BAAALgADCgQJBAAAAA==.Baegar:BAAALgAECgYJBgAAAA==.Bakugo:BAACLgAFFH8MAAIEAAMJgxbmEAD7AAAEAAMJgxbmEAD7AAAuAAQKfyMABAQACAm1IcEJAJ4CAAQACAl/H8EJAJ4CAA4ABgmNH+4gANsBAA8ABgkhF0wSAHMBAAAA.Bamfbutcher:BAABLgAECn8aAAIQAAkJXRcOCQAZAgAQAAkJXRcOCQAZAgAAAA==.Banang:BAAALgADCgUJBQAAAA==.Barrimen:BAABLgAECn8XAAIKAAcJgQdnZgDkAAAKAAcJgQdnZgDkAAAAAA==.Bartolomew:BAAALgAECggJGwAAAQ==.Bashton:BAAALgADCgMJAwAAAA==.Bastian:BAAALgADCgEJAQAAAA==.Batboy:BAAALgAECgYJEgAAAA==.',
Be='Beepers:BAABLgAECn8bAAIIAAkJHQ59FwDWAQAIAAkJHQ59FwDWAQAAAA==.Behodahlia:BAABLgAECn8ZAAIDAAcJBgl4IAD8AAADAAcJBgl4IAD8AAAAAA==.Benezra:BAAALgAECgEJAQAAAA==.Bexurk:BAABLgAECn8YAAMRAAgJTAWvCQBMAQARAAgJTAWvCQBMAQAFAAEJwgMoWAAoAAAAAA==.',
Bi='Biaku:BAAALgADCgIJAgAAAA==.Bibleman:BAAALgADCgIJAgABLgAECgcJFgADACAYAA==.Bigbilly:BAAALgADCgkJCQAAAA==.Bigcalcium:BAABLgAECn8iAAIKAAgJnyWNBgBmAwAKAAgJnyWNBgBmAwAAAA==.Bighimbo:BAABLgAECn8VAAIDAAYJUiCJCAArAgADAAYJUiCJCAArAgAAAA==.Biltix:BAACLgAFFH8JAAISAAMJNCKXCwA1AQASAAMJNCKXCwA1AQAuAAQKfyAAAhIACAmIIMkSAHwCABIACAmIIMkSAHwCAAAA.Bimzelx:BAAALgAECgMJBQAAAA==.Bipolar:BAAALgAECgUJBwAAAA==.Bitterblood:BAAALgAECgYJDAAAAA==.',
Bl='Blanche:BAAALgADCgYJBgAAAA==.Blastgamer:BAAALgAECgMJBQAAAA==.Blindbob:BAAALgADCgUJBwAAAA==.Blueb:BAAALgADCgkJEgABLgAECggJJQAOAGQaAA==.',
Bo='Bocaj:BAAALgADCgEJAQABLgAECggJJAAHAPUcAA==.Boltbourne:BAAALgADCgUJBQAAAA==.Bolyn:BAAALgAECgIJAQAAAA==.Bonami:BAAALgADCgYJBgAAAA==.Bongwizard:BAAALgADCgUJBQAAAA==.Booshi:BAABLgAECn8cAAIJAAgJbhUaNwDLAQAJAAgJbhUaNwDLAQAAAA==.Bowiiesenpai:BAABLgAECn8fAAIPAAgJ5CCRBQA9AgAPAAgJ5CCRBQA9AgAAAA==.Bowmarc:BAABLgAECn8ZAAIKAAkJCwxlRQA5AQAKAAkJCwxlRQA5AQAAAA==.Boykisser:BAAALgAECgUJBQAAAA==.',
Br='Bravehearth:BAAALgAECgIJAwABLgAECgQJBAAGAAAAAA==.Brewcifer:BAAALgADCgYJBgAAAA==.Brightxan:BAABLgAECn8fAAITAAkJJBdcCgApAgATAAkJJBdcCgApAgAAAA==.Broamdar:BAAALgAECgkJBgAAAA==.Brotha:BAAALgADCgUJCgAAAA==.Brownbeard:BAAALgAECgcJEwAAAA==.',
Bu='Bubbapriest:BAAALgADCgMJAwAAAA==.Bubbashaman:BAAALgAECgYJDQAAAA==.Budgetsushi:BAAALgADCgcJCwAAAA==.Burninator:BAABLgAECn8ZAAQUAAkJ4hWFEwCrAQAUAAYJrhmFEwCrAQAVAAkJYBGyIgCpAQAWAAIJJw1JQABoAAAAAA==.Bus:BAABLgAFFH8IAAIXAAUJhCIYAQD5AQAXAAUJhCIYAQD5AQABLgAFFAcJDQAYAH4hAA==.Butterrs:BAAALgAECgUJDAAAAQ==.Butterz:BAABLgAECn8fAAIFAAkJuB5CCwDkAgAFAAkJuB5CCwDkAgABLgAECgUJDAAGAAAAAA==.',
Ca='Caelan:BAAALgAECgEJAgAAAA==.Caloren:BAABLgAECn8fAAIZAAgJFSGlFwDIAgAZAAgJFSGlFwDIAgAAAA==.Calqlated:BAAALgADCgYJBgABLgAECgcJCgAGAAAAAA==.Caorou:BAAALgADCgYJBgAAAA==.',
Ce='Cedrid:BAAALgAECgIJAwAAAA==.Cenauria:BAAALgADCgYJBgAAAA==.',
Ch='Chanit:BAABLgAECn8VAAIKAAgJTRM4QgBDAQAKAAgJTRM4QgBDAQAAAA==.Chaosbeast:BAAALgADCgEJAQAAAA==.Charuzu:BAAALgAECgYJEAAAAA==.Chaurana:BAABLgAECn8aAAIaAAcJRxZNBgBnAQAaAAcJRxZNBgBnAQAAAA==.Chenzio:BAAALgADCgUJBQAAAA==.Chikorita:BAAALgAECgcJDgAAAA==.Chilidan:BAAALgAECgIJAgAAAA==.Chimichurri:BAAALgAECgMJAwAAAA==.Chipo:BAAALgAECgEJAgAAAA==.Chrilynn:BAABLgAECn8UAAMKAAYJohXcRwAyAQAKAAYJKhTcRwAyAQATAAQJhRJIKADHAAAAAA==.Chuwee:BAAALgADCgIJAgAAAA==.',
Ci='Cind:BAAALgADCgcJCAAAAA==.Cinderatrath:BAACLgAFFH8PAAIUAAUJZxEzAQBSAQAUAAUJZxEzAQBSAQAuAAQKfyoAAhQACAkRIkcDAOsCABQACAkRIkcDAOsCAAAA.',
Cn='Cnydemon:BAAALgADCgEJAQAAAA==.',
Co='Corsaro:BAAALgAECgQJBwAAAA==.Corvixius:BAABLgAECn8WAAIQAAcJ4AkPIwAgAQAQAAcJ4AkPIwAgAQAAAA==.',
Cr='Crunchwrap:BAAALgAECgYJEAAAAA==.',
Cu='Cuigy:BAABLgAECn8ZAAIBAAcJiCGsCABeAgABAAcJiCGsCABeAgAAAA==.',
Cy='Cyriene:BAABLgAECn8UAAIIAAYJGg9lRwD8AAAIAAYJGg9lRwD8AAAAAA==.Cyrik:BAAALgAECgcJEgAAAA==.',
Da='Daevas:BAAALgADCgEJAQABLgAECgcJFgADACAYAA==.Danksinatra:BAAALgAECgUJDwAAAA==.Danté:BAABLgAECn8bAAIHAAcJ+BvCUgA/AgAHAAcJ+BvCUgA/AgAAAA==.Dardorian:BAAALgAECgEJAgAAAA==.Darkfist:BAAALgADCgYJBQAAAA==.Darko:BAAALgAECgQJCgAAAA==.Darou:BAAALgAECgcJEgAAAA==.Daylen:BAAALgAECgcJEwAAAA==.',
De='Deactrim:BAAALgAFFAEJAQAAAA==.Deadploo:BAAALgADCgMJAwAAAA==.Deadpòól:BAAALgADCgUJBQABLgAECgIJAgAGAAAAAA==.Deafknights:BAAALgAECgQJBwABLgAECggJFAAFALkcAA==.Deathgoat:BAAALgADCgIJAgAAAA==.Deku:BAAALgAECgMJCAABLgAECgcJEwAGAAAAAA==.Demiglace:BAABLgAECn8iAAQSAAgJSyboAAAVAwASAAgJSyboAAAVAwAbAAEJMRm0PgBJAAADAAEJxxS9aAAwAAABLgAFFAYJFwAZACAmAA==.Demonfloozie:BAAALgADCgkJCQAAAA==.Demongal:BAAALgADCgQJBAAAAA==.Dendrada:BAAALgAECgcJEwAAAA==.Dewbie:BAACLgAFFH8GAAIMAAMJcRjNBwAcAQAMAAMJcRjNBwAcAQAuAAQKfyAAAgwACQnwFJMJAEYCAAwACQnwFJMJAEYCAAAA.',
Di='Dirtyshim:BAAALgAECgMJAwAAAA==.Dizimo:BAAALgAECgcJDQAAAA==.',
Dm='Dminn:BAAALgAECgQJBQAAAA==.',
Do='Dogmeat:BAACLgAFFH8LAAIIAAQJeRxVAgB6AQAIAAQJeRxVAgB6AQAuAAQKfx8AAggABwmgIqcWAIMCAAgABwmgIqcWAIMCAAEuAAUUBgkMABwAhBAA.Doomslayer:BAAALgADCgcJDgAAAA==.Doreniel:BAAALgAECgkJAgAAAA==.Dotisa:BAAALgAECgUJBwAAAA==.',
Dr='Draxker:BAABLgAECn8ZAAIUAAcJ8w+qBAB3AQAUAAcJ8w+qBAB3AQAAAA==.Dreadmourne:BAAALgAECgUJBQAAAA==.Drfumanchu:BAAALgADCgUJCAABLgAECgQJBAAGAAAAAA==.Druddigon:BAAALgAECgUJBgABLgAECgcJCgAGAAAAAA==.',
Du='Duna:BAAALgAECgYJEAAAAA==.Duvidressra:BAABLgAECn8iAAMdAAgJaA20AwB4AQAdAAgJaA20AwB4AQAeAAMJUAVo/QBgAAAAAA==.',
Dx='Dxmvn:BAAALgADCgEJAQAAAA==.',
Dy='Dyingmight:BAAALgAECgQJBAAAAA==.',
['Dä']='Dävïs:BAAALgAECggJEwAAAA==.',
Ed='Edea:BAAALgAECgQJBwAAAA==.Edisonn:BAACLgAFFH8HAAIeAAQJrAzTHQArAQAeAAQJrAzTHQArAQAuAAQKfyQAAx4ACAkiHsQKAGICAB4ACAkiHsQKAGICAAIAAwl/HD07AMcAAAAA.',
El='Eldarya:BAAALgAECgEJAQAAAA==.Eldermoon:BAAALgAECgYJCAAAAA==.Elghinn:BAABLgAECn8jAAIfAAgJWBN3CADEAQAfAAgJWBN3CADEAQAAAA==.Ellie:BAABLgAECn8gAAIIAAcJhh8REgACAgAIAAcJhh8REgACAgAAAA==.Elponch:BAAALgAECgcJBgAAAA==.Elroy:BAABLgAECn8hAAIKAAgJOBPzJgCnAQAKAAgJOBPzJgCnAQAAAA==.',
Em='Embold:BAACLgAFFH8WAAINAAYJaSILAgBRAgANAAYJaSILAgBRAgAuAAQKfy0AAg0ACQnqJWcAAOYDAA0ACQnqJWcAAOYDAAAA.Emernantus:BAABLgAECn8eAAITAAgJrg4rDgAdAQATAAgJrg4rDgAdAQAAAA==.Emozi:BAABLgAECn8oAAMeAAgJLxNKHgC/AQAeAAgJThJKHgC/AQAdAAYJoBHOCwB9AQAAAA==.',
Eu='Eunbyeol:BAABLgAECn8eAAIQAAgJcxvoDQDUAQAQAAgJcxvoDQDUAQAAAA==.',
Ex='Excidium:BAAALgAECgYJDQAAAA==.Expired:BAAALgADCgQJBAAAAA==.',
Fa='Faeria:BAABLgAECn8ZAAIOAAYJbxmFEQCTAQAOAAYJbxmFEQCTAQAAAA==.Fangwalker:BAAALgAECgQJDAAAAA==.Farmerdotcom:BAAALgADCgEJAQAAAA==.Fatnchunkydk:BAAALgAECgYJEwAAAA==.Fatpigeon:BAAALgAECgQJBAAAAA==.',
Fe='Feeblemind:BAABLgAECn8aAAIIAAcJaBhQIwCPAQAIAAcJaBhQIwCPAQAAAA==.Feesherman:BAAALgAECgcJEwAAAA==.Feli:BAABLgAECn8WAAIQAAcJbwmoHwA3AQAQAAcJbwmoHwA3AQAAAA==.Felldor:BAAALgADCgUJAgAAAA==.Felmommy:BAAALgADCgYJBgAAAA==.Felrindan:BAAALgAECgYJDAAAAA==.Felscream:BAAALgADCgUJBQAAAA==.Fender:BAAALgAECgcJEwAAAA==.Ferchrian:BAAALgADCgEJAQAAAA==.',
Fi='Finfangfoom:BAAALgAECgQJBAAAAA==.Fingertoes:BAABLgAECn8kAAIHAAgJ9RyyFAA1AgAHAAgJ9RyyFAA1AgAAAA==.Fistamista:BAAALgAECgUJBQAAAA==.Fizban:BAAALgADCggJFAAAAA==.',
Fl='Flaygar:BAAALgAECgYJDAAAAA==.Flory:BAABLgAECn8hAAIKAAkJphghKACEAgAKAAkJphghKACEAgAAAA==.Flowpro:BAAALgADCgMJAwAAAA==.Flyinweasle:BAAALgAECgUJBQAAAA==.',
Fo='Foundation:BAAALgAECgYJCgAAAA==.Foxxycontin:BAABLgAECn8aAAMOAAcJEBDgMAB9AQAOAAcJEBDgMAB9AQAPAAEJFQZ3ZgAsAAAAAA==.',
Fr='Frostyrican:BAAALgAECgEJAQAAAA==.',
Fu='Fuglybaby:BAAALgADCgUJBQAAAA==.',
Fw='Fwakos:BAAALgADCgUJCQAAAA==.',
['Fé']='Fénnie:BAAALgADCgMJAwAAAA==.',
Ga='Gaivahros:BAAALgAECggJEwAAAA==.Gakpaladin:BAABLgAECn8jAAITAAgJNhgZBgDKAQATAAgJNhgZBgDKAQAAAA==.Galileo:BAAALgAECgQJCAAAAA==.Garland:BAAALgAECgcJDAAAAA==.',
Ge='Gerasstrois:BAAALgAECgcJEQABLgAECggJIgAdAGgNAA==.Gerionier:BAAALgADCgEJAQABLgAECgYJCgAGAAAAAA==.Gethael:BAAALgAECgEJAQAAAA==.',
Gh='Ghalathor:BAAALgADCgMJAwAAAA==.',
Gl='Glimsy:BAAALgADCgYJCQAAAA==.Glittermilk:BAAALgADCgUJBQAAAA==.',
Go='Golosan:BAABLgAECn8dAAISAAkJGR1FBABzAgASAAkJGR1FBABzAgAAAA==.Goododie:BAABLgAECn8WAAIKAAYJbx19LQCMAQAKAAYJbx19LQCMAQAAAA==.Gordil:BAAALgAECgUJBQAAAA==.Gorokan:BAAALgAECgIJAwAAAA==.',
Gr='Grayback:BAAALgAECgcJBgABLgAECgkJDAAGAAAAAA==.Grimsdeath:BAAALgADCgUJBQAAAA==.',
Gu='Guila:BAABLgAECn8WAAIeAAYJ1w9DRAAkAQAeAAYJ1w9DRAAkAQAAAA==.Gulaken:BAAALgAECgYJCwAAAA==.',
Ha='Hafnia:BAAALgAECgYJDQAAAA==.Hai:BAAALgAECgEJAQAAAA==.Halphion:BAAALgADCgYJBwABLgAECgcJFgALAEIdAA==.Hangry:BAAALgAECgEJAQAAAA==.Hanoe:BAAALgADCgYJBgAAAA==.Haoasakura:BAABLgAECn8rAAIKAAgJ6SOsCACSAgAKAAgJ6SOsCACSAgAAAA==.Haybuse:BAABLgAECn8iAAIMAAkJ4x/9AQCgAgAMAAkJ4x/9AQCgAgAAAA==.',
He='Healmd:BAAALgADCgMJAwAAAA==.Healzforfood:BAAALgAECgUJCAAAAA==.Healzyou:BAAALgADCgMJAwAAAA==.Heap:BAABLgAECn8fAAIYAAkJKQypEQBbAQAYAAkJKQypEQBbAQAAAA==.Hectavius:BAAALgAECgEJAQAAAA==.Hells:BAAALgAECgEJAQAAAA==.Hellslinger:BAAALgAECgQJBgAAAA==.Hewnoshaqa:BAABLgAECn8cAAIIAAgJ9wwCJACMAQAIAAgJ9wwCJACMAQAAAA==.Hexeñ:BAAALgAECggJDwAAAA==.Hexorcist:BAACLgAFFH8IAAIBAAMJZR/YFQDbAAABAAMJZR/YFQDbAAAuAAQKfxcAAwEACAnPGYcbADwCAAEACAnPGYcbADwCAAUAAwnVGbVaANkAAAAA.',
Hi='Hickerbilly:BAAALgAECgkJCAAAAA==.Higgintoot:BAAALgAECgIJAgAAAA==.Hitormist:BAABLgAECn8WAAIDAAcJIBiNCwDuAQADAAcJIBiNCwDuAQAAAA==.',
Ho='Holyshoot:BAAALgAECgMJBQAAAA==.Holyspanks:BAAALgADCgEJAQABLgAECggJIAAVAGgZAA==.Horous:BAAALgADCgkJAgAAAA==.Hotdoog:BAAALgADCgUJBQABLgAECgQJCgAGAAAAAA==.',
Hr='Hruuli:BAAALgAECgIJAgAAAA==.',
Hu='Hungweilow:BAAALgADCgUJBgABLgAECgQJBAAGAAAAAA==.Huugar:BAAALgAECgcJEwAAAA==.',
['Hæ']='Hædés:BAABLgAECn8aAAITAAcJxx5qBQDfAQATAAcJxx5qBQDfAQAAAA==.',
Ib='Ibeamwork:BAAALgAECgcJEAAAAA==.',
Ic='Icoulddowork:BAAALgADCgQJBAABLgAECgcJEAAGAAAAAA==.Icyconjurer:BAAALgADCgMJAwAAAA==.',
Id='Idoworkz:BAAALgADCgcJBwABLgAECgcJEAAGAAAAAA==.',
Ii='Iiquorice:BAAALgAECgMJAwAAAA==.',
Ik='Ikazuchi:BAABLgAECn8cAAIgAAgJqhOPAgDMAQAgAAgJqhOPAgDMAQAAAA==.',
Il='Illcutabish:BAABLgAECn8nAAIhAAkJZRj1BAA4AgAhAAkJZRj1BAA4AgAAAA==.',
Im='Imk:BAABLgAECn8UAAIZAAcJdhFYJABbAQAZAAcJdhFYJABbAQAAAA==.',
In='Ineedatarget:BAAALgADCgEJAQAAAA==.Intbuff:BAAALgADCggJFAABLgAECgQJCAAGAAAAAA==.Invadiah:BAAALgAECgcJDQAAAA==.Invited:BAAALgAFFAEJAQAAAA==.',
Io='Iock:BAEALgAECgUJCAAAAA==.',
Ir='Ironarms:BAAALgADCgUJBQAAAA==.',
Iw='Iwdominate:BAAALgADCgMJAwAAAA==.',
Iy='Iyana:BAAALgAECgMJBgAAAA==.',
Iz='Izümi:BAABLgAECn8bAAIMAAcJzBlmCQDMAQAMAAcJzBlmCQDMAQAAAA==.',
Ja='Jazz:BAAALgADCgcJDgAAAA==.',
Je='Jennypoo:BAABLgAECn8qAAMJAAgJGB79DQAsAgAJAAgJGB79DQAsAgAcAAIJQwrOPABTAAAAAA==.Jessd:BAAALgAECgIJAgAAAA==.',
Ji='Jild:BAAALgAECgQJBwAAAA==.Jinwoosung:BAAALgAECgYJDQAAAA==.',
Jo='Johnwarrior:BAAALgAECggJEQAAAA==.Jorrix:BAABLgAECn8gAAIKAAcJ3BK5LwCDAQAKAAcJ3BK5LwCDAQAAAA==.',
Ju='Juduspriestt:BAABLgAECn8bAAIKAAcJShhSNABxAQAKAAcJShhSNABxAQAAAA==.Jurt:BAAALgADCgcJDQAAAA==.',
Ka='Kaalysto:BAAALgADCgMJAwAAAA==.Kaekko:BAAALgADCgYJBgABLgAECgkJHgAKAOIcAA==.Kaeko:BAABLgAECn8aAAIPAAgJXRtsEACAAgAPAAgJXRtsEACAAgABLgAECgkJHgAKAOIcAA==.Kaelathaniel:BAABLgAECn8nAAMeAAgJUw6DJgCVAQAeAAgJUQ6DJgCVAQACAAEJeA7DdQAvAAAAAA==.Kalerito:BAABLgAECn8cAAIJAAgJMyC2BQDBAgAJAAgJMyC2BQDBAgAAAA==.Kalistae:BAABLgAECn8ZAAMPAAcJrR2lCAD7AQAPAAcJrR2lCAD7AQAOAAEJ6h+5cwBZAAAAAA==.Kallivath:BAAALgADCgYJCAAAAA==.Kamdrixa:BAAALgADCgYJDAAAAA==.Karinus:BAAALgADCgUJBQAAAA==.Karkaroff:BAAALgAECgcJAwABLgAECgkJDAAGAAAAAA==.Karl:BAABLgAECn8YAAIHAAUJXgzKdwDnAAAHAAUJXgzKdwDnAAAAAA==.Karlack:BAAALgADCgUJBQAAAA==.Kaserr:BAACLgAFFH8MAAIhAAQJwBhCBgBlAQAhAAQJwBhCBgBlAQAuAAQKfyYAAiEACQksIOYCAHcDACEACQksIOYCAHcDAAAA.Kayserdh:BAAALgAECgYJEQAAAA==.Kazaf:BAAALgAECgQJEQAAAA==.',
Ke='Keeirian:BAAALgADCgEJAQAAAA==.Keikoh:BAABLgAECn8eAAIKAAkJ4hzPCgB2AgAKAAkJ4hzPCgB2AgAAAA==.Keitrek:BAABLgAECn8jAAILAAgJrQdFHABpAQALAAgJrQdFHABpAQAAAA==.Kelthias:BAAALgADCgYJCgAAAA==.Kelypsoc:BAAALgAECgQJBgAAAA==.Kenichï:BAAALgAECgYJDwABLgAECggJDwAGAAAAAA==.Keomag:BAAALgAECgQJBwAAAA==.Kerwîck:BAAALgAECggJDwAAAA==.Keyen:BAABLgAECn8aAAILAAcJvQcAJgAZAQALAAcJvQcAJgAZAQAAAA==.',
Kh='Khallan:BAABLgAECn8ZAAIJAAcJgAYLOAD1AAAJAAcJgAYLOAD1AAAAAA==.Khazsz:BAABLgAECn8ZAAMYAAYJMiK4BwA6AgAYAAYJMiK4BwA6AgAiAAMJ/RSpJACuAAAAAA==.',
Ki='Kibalion:BAAALgAECgYJCwAAAA==.Kiljaezyn:BAAALgAECgEJAgAAAA==.Killbent:BAAALgAECgQJBwAAAA==.Kilowatts:BAAALgADCgYJBgAAAA==.Kimjongwork:BAAALgAECgEJAQABLgAECgcJEAAGAAAAAA==.Kinnky:BAABLgAECn8YAAIHAAcJsBd+MQCeAQAHAAcJsBd+MQCeAQAAAA==.Kino:BAAALgAECgUJCQAAAA==.Kiratsuna:BAAALgAECgYJBgAAAA==.Kiriya:BAAALgAECgYJEQAAAA==.Kismiasu:BAAALgAECgYJBgAAAA==.Kitticakes:BAAALgADCgUJBQAAAA==.Kivdruid:BAACLgAFFH8FAAIJAAQJNQbCFADyAAAJAAQJNQbCFADyAAAuAAQKfyAAAwkACQmyGEoIAIcCAAkACQmyGEoIAIcCABwABAk4D/8xAIkAAAAA.Kivpriest:BAAALgADCgYJCwABLgAFFAQJBQAJADUGAA==.',
Kk='Kkty:BAAALgADCgQJBwAAAA==.',
Ko='Koore:BAABLgAECn8ZAAITAAcJWB0YBQDrAQATAAcJWB0YBQDrAQAAAA==.Korraavatar:BAAALgAECgIJAgAAAA==.',
Kp='Kpop:BAABLgAECn8QAAIZAAcJ0h+GCwAlAgAZAAcJ0h+GCwAlAgAAAA==.Kpopkhan:BAABLgAECn8PAAIZAAgJJQz6awBfAQAZAAgJJQz6awBfAQAAAA==.',
Kr='Kreettip:BAABLgAECn8aAAIOAAgJhRAZLACXAQAOAAgJhRAZLACXAQAAAA==.Krispy:BAAALgADCggJCAABLgAECggJIgAJAGYZAA==.',
Ku='Kugamoo:BAABLgAECn8gAAIcAAkJORWYDQC1AQAcAAkJORWYDQC1AQAAAA==.Kulgen:BAAALgADCgIJAgAAAA==.Kurgen:BAABLgAECn8WAAIKAAYJkBPuSwAnAQAKAAYJkBPuSwAnAQAAAA==.',
Ky='Kylex:BAAALgAECgEJAgAAAA==.',
['Kà']='Kàkárót:BAAALgADCgcJEAAAAA==.',
['Kí']='Kísámé:BAAALgAECgEJAQAAAA==.',
La='Lamasacre:BAAALgAECgEJAQAAAA==.Lannybarby:BAABLgAECn8ZAAIKAAYJ4wYdaQDeAAAKAAYJ4wYdaQDeAAAAAA==.Laotzu:BAABLgAECn8ZAAMVAAgJ0gi8LgBNAQAVAAcJNQm8LgBNAQAWAAgJ7AN3JwA4AQAAAA==.',
Lc='Lckdown:BAAALgAECgcJCgAAAA==.',
Le='Legomyegolas:BAAALgAECgcJEgAAAA==.Leviticus:BAAALgADCgEJAQAAAA==.',
Li='Liara:BAAALgADCgEJAQAAAA==.Licentious:BAAALgADCgIJAgAAAA==.Lightsauce:BAAALgAECgYJCQAAAA==.Lilianis:BAAALgAECgIJAgAAAA==.Lilybloom:BAAALgAECgQJBAAAAA==.',
Lo='Loden:BAACLgAFFH8OAAIjAAQJdR7bFgBXAQAjAAQJdR7bFgBXAQAuAAQKfxsAAiMACAnYIgsZAOYCACMACAnYIgsZAOYCAAAA.Lodex:BAAALgAECgEJAQAAAA==.Lokthal:BAAALgADCgYJBgAAAA==.Lootzu:BAAALgAECgkJAQAAAA==.Lovi:BAABLgAECn8aAAIBAAcJQxyiFADGAQABAAcJQxyiFADGAQAAAA==.',
Lu='Lucifero:BAAALgAECgYJEAAAAA==.Luckyboi:BAAALgAECgYJEAAAAA==.Luckymonk:BAAALgAECggJEwABLgAECgYJEAAGAAAAAA==.Lucyl:BAAALgAECgMJAwAAAA==.Lumina:BAAALgAECgYJDwAAAA==.Lunaruu:BAAALgADCgEJAQAAAA==.Lusciifi:BAACLgAFFH8RAAIKAAUJ6SI6CABwAQAKAAUJ6SI6CABwAQAuAAQKfyUAAgoACAnUJRsGAGwDAAoACAnUJRsGAGwDAAAA.Luvva:BAAALgAECgIJAgAAAA==.',
Ly='Lykie:BAABLgAECn8iAAITAAkJvBv8BwBbAgATAAkJvBv8BwBbAgAAAA==.Lyllith:BAAALgADCgYJBgAAAA==.Lyone:BAAALgAECgYJDwAAAA==.',
['Lú']='Lúvaa:BAABLgAECn8kAAMjAAgJHCKvCQCFAgAjAAgJHCKvCQCFAgAkAAMJPSOjJAAbAQAAAA==.',
Ma='Maahun:BAAALgAECgEJAQAAAA==.Maficwar:BAABLgAECn8pAAIXAAkJ/Rl4AwBUAgAXAAkJ/Rl4AwBUAgAAAA==.Mageyuwu:BAAALgAECgEJAQAAAA==.Magikkisback:BAAALgAECgcJEAAAAA==.Manarez:BAAALgAECgYJCgAAAA==.Mandorius:BAAALgAECgYJDAAAAA==.Manywagons:BAAALgAECgcJDQABLgAFFAkJJwAHAEIfAA==.Margherita:BAAALgAECgUJBQAAAA==.Mariora:BAAALgAECgEJAQAAAA==.Masacre:BAAALgAECgQJCAAAAA==.Mavalynal:BAAALgADCgcJEgAAAA==.Mavdeath:BAAALgAFFAEJAQAAAA==.Mavidari:BAABLgAECn8ZAAIZAAgJDB4iIQCKAgAZAAgJDB4iIQCKAgAAAA==.',
Mc='Mchammered:BAAALgADCgMJBgAAAA==.',
Me='Meeshie:BAABLgAECn8lAAQOAAgJZBo+EABkAgAOAAgJZBo+EABkAgAPAAQJUAs4IwDhAAAEAAUJ4xLBHwDZAAAAAA==.Meleys:BAAALgADCgcJCAAAAA==.',
Mi='Midoriya:BAACLgAFFH8LAAMeAAMJtCbcEgBRAQAeAAMJtCbcEgBRAQACAAEJNhdYEwBYAAAuAAQKfyEABB4ACAl+JiIQACUCAB4ABglWJiIQACUCAAIAAwn5JZkhAEgBAB0AAgmBJi0LAHYAAAAA.Mightyhunts:BAAALgAECgMJBAAAAA==.Mikuzume:BAAALgAECgQJBgAAAA==.Milkmage:BAABLgAECn8eAAIHAAgJNx2eEABXAgAHAAgJNx2eEABXAgAAAA==.Mintt:BAAALgAECgEJAQAAAA==.Mishima:BAAALgADCgMJAwAAAA==.Miznewbooty:BAABLgAECn8nAAMEAAkJXg8oCAAXAgAEAAkJXg8oCAAXAgAPAAQJog5TRADaAAAAAA==.',
Mo='Moggark:BAAALgADCgQJBAAAAA==.Monknack:BAAALgAECgEJAQAAAA==.Moondofrond:BAAALgAECgIJAgAAAA==.Moonq:BAAALgAECgcJEwAAAA==.Moorti:BAABLgAECn8VAAMHAAYJ/RswOQCDAQAHAAYJ/RswOQCDAQAlAAEJww7xHAA5AAAAAA==.Moosaurus:BAABLgAECn8VAAIaAAgJjBHgDQB3AQAaAAgJjBHgDQB3AQAAAA==.Mosrael:BAAALgADCgEJAgAAAA==.',
Mu='Muffy:BAAALgAECgYJDwAAAA==.Multishoted:BAAALgADCgEJAQAAAA==.Murlouh:BAAALgADCgUJCAAAAA==.Mushudoobey:BAAALgAECgIJAgABLgAECggJIAAHAHQgAA==.',
My='Mylthrad:BAAALgADCgMJAwAAAA==.Mythnarra:BAACLgAFFH8KAAMaAAMJWyFEAQArAQAaAAMJWyFEAQArAQAZAAEJiwYTRQBGAAAuAAQKfysAAxoACAlqJVwAAPgCABoACAlqJVwAAPgCABkABAl0Hc4jAF0BAAAA.',
['Mí']='Mísanthrope:BAAALgAECgMJBQAAAA==.',
['Mô']='Mônster:BAAALgAECgUJCQAAAA==.',
['Mö']='Mönk:BAACLgAFFH8FAAIDAAMJthfcCgD7AAADAAMJthfcCgD7AAAuAAQKfx4AAgMACAmsHskMAIYCAAMACAmsHskMAIYCAAAA.',
['Mø']='Mønstèr:BAAALgAECgUJCQAAAA==.',
Na='Nachtimbess:BAAALgADCgYJBgABLgAFFAEJAQAGAAAAAA==.Nadaline:BAAALgADCgcJBwAAAA==.Nadíne:BAABLgAECn8aAAIHAAgJaR8/QwBuAgAHAAgJaR8/QwBuAgAAAA==.Naha:BAAALgAECgkJBwAAAA==.Naimi:BAAALgAECgQJCQAAAA==.Nanukimon:BAAALgAECgYJEwAAAA==.Nastymcdirty:BAAALgADCgcJBwAAAA==.',
Ne='Nelivath:BAAALgAECgEJAQAAAA==.Nene:BAAALgAFFAIJAwAAAA==.Nevaera:BAAALgAECgcJEQAAAA==.',
Ni='Nichan:BAAALgAECgEJAwAAAA==.Nick:BAACLgAFFH8bAAMjAAUJNxwxEwBVAQAjAAQJNxwxEwBVAQAkAAEJAAA4FwA+AAAuAAQKfy0AAiMACQmSI/wEAIQDACMACQmSI/wEAIQDAAAA.Nightcraft:BAAALgAECgEJAQAAAA==.Nightshine:BAAALgAECgcJEQAAAA==.Nikor:BAAALgAECgUJCgAAAA==.Nisan:BAAALgADCgcJBwAAAA==.',
No='Nocabevoli:BAAALgADCgUJBQABLgAECgIJAwAGAAAAAA==.Nokorii:BAABLgAECn8WAAIOAAYJrxAiGABJAQAOAAYJrxAiGABJAQAAAA==.Nomecoma:BAAALgAECgQJAQAAAA==.Nomercy:BAAALgADCgEJAQAAAA==.Norgatha:BAAALgAECgUJCgAAAA==.Notches:BAAALgAECgMJBQAAAA==.Nowheres:BAAALgAECgIJAgABLgAECgUJDAAGAAAAAA==.Noxturn:BAABLgAECn8VAAIIAAgJtBFFUQB1AQAIAAgJtBFFUQB1AQAAAA==.',
Nu='Nuikang:BAAALgAECgEJAQAAAA==.',
Ny='Nyxx:BAAALgAECgYJDQABLgAECgUJCQAGAAAAAA==.',
['Nè']='Nèlo:BAABLgAECn8ZAAIXAAcJNAymEQALAQAXAAcJNAymEQALAQAAAA==.',
Oc='Oceansoul:BAAALgAECgYJEwAAAA==.',
Oh='Ohh:BAAALgADCgMJAQAAAA==.',
Ok='Ok:BAAALgADCgYJCgAAAA==.',
On='Ondestra:BAAALgAECgIJAgAAAA==.',
Op='Oppenheimerx:BAAALgADCgMJBQAAAA==.',
Or='Orave:BAAALgAECgUJCgAAAA==.Origin:BAAALgAECgIJAwAAAA==.Orionah:BAAALgAECgQJBAAAAA==.',
Os='Osywar:BAAALgAECgYJEwABLgAFFAEJAQAGAAAAAA==.',
Ou='Oulawdpriest:BAACLgAFFH8MAAIPAAUJpAhMCwAIAQAPAAUJpAhMCwAIAQAuAAQKfywABA8ACAl6HkkMAL4CAA8ACAl6HkkMAL4CAAQAAgk4HE9DAJoAAA4AAgkHFWRzAFoAAAAA.',
Ov='Overture:BAABLgAECn8UAAMJAAYJ8wxIOAD0AAAJAAYJ8wxIOAD0AAAcAAQJBxD6XQCqAAAAAA==.',
Pa='Palaslap:BAAALgADCgMJAwAAAA==.Panacea:BAAALgAECgYJCQAAAA==.Parkour:BAAALgAECgYJEAAAAA==.Pastorale:BAAALgADCgYJBgABLgAECggJGQAVANIIAA==.Patata:BAAALgADCgIJAgAAAA==.Paullymorph:BAABLgAECn8dAAIHAAkJCCG1CACxAgAHAAkJCCG1CACxAgAAAA==.Pawpawbear:BAAALgADCgEJAQAAAA==.Payal:BAAALgADCgQJBAABLgAFFAQJBwAeAKwMAA==.',
Ph='Phenyl:BAABLgAECn8aAAIDAAgJAQitGwAlAQADAAgJAQitGwAlAQAAAA==.Pheurton:BAAALgAECgkJBwAAAA==.',
Pi='Pithers:BAAALgAECgQJBgAAAA==.',
Po='Ponchohunter:BAAALgADCgEJAQAAAA==.Poohpocket:BAAALgADCgQJAwAAAA==.Popkorn:BAACLgAFFH8XAAMZAAYJICasAAA3AgAZAAUJICasAAA3AgAaAAEJAAAPBABqAAAuAAQKfx4ABBkACAmSJrkQAPgCABkABwnEJrkQAPgCAB8ABQmUIboqAHABABoAAQlnJW0iAG8AAAAA.Popkornvoke:BAAALgAECgMJAwABLgAFFAYJFwAZACAmAA==.Poplocks:BAAALgADCgIJAwAAAA==.Porrana:BAABLgAECn8UAAMQAAYJvR1+EAC2AQAQAAYJvR1+EAC2AQAmAAEJQQ9YLAA3AAAAAA==.Powaqa:BAABLgAECn8gAAICAAcJFQM3EgCYAAACAAcJFQM3EgCYAAAAAA==.',
Ps='Psy:BAAALgAECggJEQAAAA==.',
Pu='Pumpkinspice:BAAALgAECgUJBQAAAA==.Punchkin:BAABLgAECn8bAAMDAAkJEhcTCAA3AgADAAkJEhcTCAA3AgAbAAEJWwJIiQAmAAAAAA==.Purify:BAAALgAECgQJBQABLgAFFAUJFAADADslAA==.Puzzledmonk:BAAALgADCgcJDQAAAA==.',
Qu='Quasient:BAAALgAECgQJBAAAAA==.Quickspell:BAABLgAECn8gAAIHAAgJwR8OEgBLAgAHAAgJwR8OEgBLAgAAAA==.Quickstep:BAAALgAECgkJBwAAAA==.',
Ra='Rabidpopcorn:BAAALgADCgcJBwAAAA==.Radaghast:BAAALgAECgcJEwAAAA==.Raedyyn:BAABLgAECn8YAAIVAAcJjw8KFwBFAQAVAAcJjw8KFwBFAQAAAA==.Ragarth:BAAALgAECgUJBQAAAA==.Ragendecay:BAABLgAECn8ZAAIjAAcJxBKgNgBfAQAjAAcJxBKgNgBfAQAAAA==.Ragequits:BAACLgAFFH8XAAMQAAcJ2R81AABcAgAQAAYJRCM1AABcAgAmAAIJQRQQCgBbAAAuAAQKfycAAxAACQmbJpgAAN8DABAACQmbJpgAAN8DACYABgnPJWMDACQCAAAA.Ragæ:BAAALgAECgUJBgAAAA==.Rakshassa:BAAALgAECgYJEgAAAA==.Ralcar:BAAALgAECgcJEQAAAA==.Razrscale:BAAALgADCgcJCwAAAA==.',
Re='Redhuntsman:BAAALgAECgIJAgAAAA==.Regrow:BAAALgAECgQJCAAAAA==.Renstrider:BAAALgADCggJCgAAAA==.',
Rh='Rheas:BAAALgAECgIJAQAAAA==.Rholdentodor:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Ro='Rockabye:BAAALgAECgUJBQABLgAFFAMJBwAjAKYPAA==.Rohra:BAABLgAECn8eAAIJAAgJoQ2GJABfAQAJAAgJoQ2GJABfAQAAAA==.Rombaz:BAAALgAECggJDgAAAA==.Ronspoomage:BAAALgADCgkJEQAAAA==.Rosemary:BAAALgADCgQJBAAAAA==.Roóz:BAAALgAECgQJEQAAAA==.',
Ru='Ruah:BAAALgADCgMJAwAAAA==.Runecast:BAAALgADCgcJFQAAAA==.',
Ry='Rynk:BAABLgAECn8hAAISAAgJZCTiAgCmAgASAAgJZCTiAgCmAgAAAA==.Rynkidari:BAAALgAECggJCAABLgAECggJIQASAGQkAA==.Ryuoxel:BAAALgAECgcJDAAAAA==.',
['Rá']='Rágnarok:BAAALgADCgMJAwAAAA==.Ráwkfist:BAABLgAFFH8LAAIVAAUJJhqjEwAOAQAVAAUJJhqjEwAOAQAAAA==.',
Sa='Sabbybunnee:BAAALgADCgcJDAAAAA==.Sabertrek:BAAALgADCgMJAwAAAA==.Saelyrinth:BAAALgADCgUJCAAAAA==.Saltybonez:BAAALgADCgUJBQAAAA==.Sambor:BAAALgAECgkJEgAAAA==.Sarapheena:BAABLgAECn8iAAIBAAkJIBLeFwCmAQABAAkJIBLeFwCmAQAAAA==.Saravian:BAAALgADCgUJBQAAAA==.Sardeench:BAAALgAECgEJAQAAAA==.Satanbomb:BAAALgAECgEJAgAAAA==.Satansbride:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.Saterli:BAACLgAFFH8HAAIOAAQJugjUCAALAQAOAAQJugjUCAALAQAuAAQKfy0AAw4ACAlhFNQNAMUBAA4ACAlhFNQNAMUBAA8ABgloA+EpALEAAAAA.Saturno:BAAALgAECggJDQAAAA==.Saucypirate:BAAALgAECgYJDwAAAA==.Saulgoodman:BAAALgADCgMJAwAAAA==.Sauronknight:BAABLgAFFH8HAAIjAAMJpg/0OADrAAAjAAMJpg/0OADrAAAAAA==.',
Sc='Scalvert:BAAALgAECgYJBwAAAA==.Scalypanda:BAABLgAECn8iAAMVAAkJOxNhCQD2AQAVAAkJOxNhCQD2AQAUAAIJ0gzTNABuAAAAAA==.Scamander:BAAALgAECgkJDAAAAA==.Scarléth:BAAALgADCggJCgAAAA==.Scoobs:BAAALgAECgMJBQAAAA==.Scorpinom:BAAALgADCgQJBAAAAA==.Sculi:BAAALgADCgcJBwAAAA==.Scurge:BAAALgAECgIJAgAAAA==.Scuttle:BAAALgADCgIJBAABLgAECgcJFgADACAYAA==.',
Se='Sei:BAAALgADCgIJAgAAAA==.Seiishiro:BAABLgAECn8aAAMcAAcJPAjfHQANAQAcAAcJPAjfHQANAQAJAAEJTATX4gAiAAAAAA==.Seldon:BAABLgAECn8XAAIKAAYJhxxEMACBAQAKAAYJhxxEMACBAQAAAA==.Sennistian:BAAALgADCgMJBAABLgAECggJIgAdAGgNAA==.Senyor:BAABLgAECn8aAAITAAcJwxaoCACFAQATAAcJwxaoCACFAQAAAA==.Seraphiel:BAAALgAECgYJCgAAAA==.Seraphymm:BAAALgAECgMJBwAAAA==.',
Sh='Shacklebolt:BAABLgAECn8hAAMeAAgJLhjwJAB/AgAeAAgJLhjwJAB/AgACAAQJWg+/MwDoAAABLgAECgkJDAAGAAAAAA==.Shadowsneak:BAAALgAECgUJEwAAAA==.Shaelistra:BAABLgAECn8WAAIiAAYJGRSTCQBPAQAiAAYJGRSTCQBPAQAAAA==.Shalai:BAAALgADCggJDgAAAA==.Shalilama:BAACLgAFFH8KAAIBAAQJTh0CDwAZAQABAAQJTh0CDwAZAQAuAAQKfzYAAgEACQk4JXkAAIcDAAEACQk4JXkAAIcDAAAA.Shamanana:BAAALgAECgYJBwAAAA==.Shamboli:BAAALgADCgMJAwAAAA==.Shanazure:BAABLgAECn8gAAMVAAgJaBnpDAC6AQAVAAgJWRfpDAC6AQAUAAcJyhM6EwCvAQAAAA==.Sheikai:BAAALgADCggJEgAAAA==.Shenderp:BAABLgAECn8UAAMOAAYJwBBjGgA0AQAOAAYJwBBjGgA0AQAPAAIJowJsWwBIAAAAAA==.Shinerbock:BAAALgAECgcJEQAAAA==.Shivä:BAAALgADCgcJCgABLgAECgcJFAAFALYTAA==.Shriven:BAAALgAECgIJAgAAAA==.',
Si='Sianvar:BAAALgAECgUJCAAAAA==.Silvanus:BAAALgAECgMJAwAAAA==.Silverjustis:BAABLgAECn8aAAIKAAcJbwTOWAAGAQAKAAcJbwTOWAAGAQAAAA==.Siwe:BAABLgAECn8fAAQBAAgJqBwNCwA6AgABAAcJRR0NCwA6AgARAAYJIxuJEgCOAQAFAAEJpBJhgwA8AAAAAA==.',
Sk='Skadoosh:BAAALgAECgYJEgAAAA==.Skribblez:BAABLgAECn8YAAMKAAcJkR9qQwAaAgAKAAcJkR9qQwAaAgALAAYJ5xmxFQClAQAAAA==.Skrilled:BAABLgAECn8hAAIIAAYJLQ4KPgAdAQAIAAYJLQ4KPgAdAQAAAA==.',
Sl='Slackback:BAAALgAECgkJBAABLgAFFAMJCwAFAKoVAA==.Sloot:BAAALgAECgYJCgAAAA==.Slughorn:BAAALgAECgcJBQABLgAECgkJDAAGAAAAAA==.Slyv:BAAALgADCgcJBwAAAA==.',
Sm='Smellidan:BAAALgADCgEJAwAAAA==.Smïte:BAAALgAECgUJDAAAAA==.',
Sn='Snape:BAAALgADCggJCAAAAA==.Snowcones:BAAALgAECgcJDQAAAA==.Snowman:BAAALgAECgMJBQAAAA==.Snw:BAAALgAECgQJCQAAAA==.',
So='Soul:BAABLgAECn8aAAIiAAgJ1SLQBADKAgAiAAgJ1SLQBADKAgAAAA==.Soulls:BAAALgAECgIJAgAAAA==.Soulsy:BAAALgAECgEJAgAAAA==.Sourgrip:BAABLgAECn8eAAIgAAgJ8RdAAgDnAQAgAAgJ8RdAAgDnAQAAAA==.',
Sp='Splendorae:BAABLgAECn8iAAILAAkJjBGgIwAFAgALAAkJjBGgIwAFAgAAAA==.Sprints:BAABLgAECn8gAAIBAAgJwRULFgC3AQABAAgJwRULFgC3AQAAAA==.Spritz:BAAALgAECgEJAQAAAA==.Sprylf:BAAALgADCgMJBAAAAA==.Spwany:BAABLgAECn8WAAQQAAgJ3Ar+GwBQAQAQAAcJeQX+GwBQAQAXAAUJoA0WKgDwAAAmAAEJAACiNQAAAAAAAA==.Spyderelite:BAABLgAECn8oAAICAAgJ6xScAgDkAQACAAgJ6xScAgDkAQAAAA==.',
Sq='Squeekems:BAAALgAECgIJAwAAAA==.Squirrel:BAAALgAECgkJDQAAAA==.',
St='Stainedhero:BAAALgADCgEJAQAAAA==.Stankstarstu:BAAALgADCgYJCAABLgAECgQJBAAGAAAAAA==.Starspeaker:BAAALgAECgYJEgAAAA==.Starykniight:BAAALgADCgMJAwABLgAECgcJFgADACAYAA==.Steveaustin:BAAALgAECgYJEQABLgAECgcJFgADACAYAA==.Stinkypeen:BAAALgAECgIJAgAAAA==.Stonecypher:BAAALgAECgYJDgAAAA==.Stoogotz:BAAALgADCgYJCAAAAA==.Stormlesbian:BAAALgADCgUJBQAAAA==.',
Su='Suhe:BAAALgADCgYJBgAAAA==.Sunwing:BAABLgAECn8iAAIOAAkJuBqUDwBqAgAOAAkJuBqUDwBqAgAAAA==.Sutileza:BAAALgADCgMJAwABLgAECgYJFAAJAPMMAA==.Suvien:BAAALgAECgMJAwAAAA==.',
Sw='Swagette:BAAALgADCgcJBwAAAA==.Swingkitti:BAAALgAECgUJBwAAAA==.',
Sx='Sxtitan:BAAALgAECggJEQAAAA==.',
Sy='Sylvarian:BAABLgAECn8aAAInAAcJ+w2EAgBkAQAnAAcJ+w2EAgBkAQAAAA==.Syrodeus:BAAALgAECgQJBAAAAA==.',
Sz='Szz:BAABLgAECn8dAAIUAAgJnCV4AADVAgAUAAgJnCV4AADVAgAAAA==.',
['Sÿ']='Sÿn:BAAALgADCgcJFwAAAA==.',
Ta='Taelgar:BAAALgAECgcJEgAAAA==.Targaryenelf:BAAALgADCgMJBAAAAA==.Taterdotz:BAAALgAECggJEwAAAA==.Tatortwats:BAAALgAECgIJAgAAAA==.Tatyrra:BAAALgADCgUJBQAAAA==.Tayswift:BAAALgADCgQJBAABLgAECgUJDAAGAAAAAA==.',
Te='Tenast:BAAALgADCgIJAgAAAA==.Tepicoyotl:BAABLgAECn8YAAIBAAYJqhOpRABvAQABAAYJqhOpRABvAQAAAA==.',
Th='Thaymor:BAAALgADCgkJGQAAAA==.Thelonecone:BAACLgAFFH8MAAMgAAQJqhWJAgAIAQAgAAMJtxWJAgAIAQAjAAQJlQ8TJQABAQAuAAQKf0IAAyMACAkLJIgVAPsCACMACAkfIogVAPsCACAACAmBIuQCAHkCAAAA.Theoganth:BAAALgAECgYJBgAAAA==.Theraphee:BAAALgADCgcJDQAAAA==.Therimor:BAABLgAECn8YAAMBAAcJoQgkNQDkAAABAAYJZgkkNQDkAAAFAAEJHwEIXAAZAAAAAA==.Theronshan:BAAALgADCgYJCgAAAA==.Thevoid:BAAALgAECgYJBgABLgAECggJGQAVANIIAA==.Thomwizard:BAAALgAECgMJAwAAAA==.Thongrin:BAAALgADCgcJBwAAAA==.Thormorn:BAAALgADCgEJAgAAAA==.Thornarlenan:BAAALgADCgkJDgAAAA==.Thunnha:BAABLgAECn8fAAMeAAgJ/SE5BwCZAgAeAAgJ/SE5BwCZAgACAAEJHBtOZgBDAAAAAA==.Thurlando:BAAALgADCgIJBAAAAA==.',
Ti='Tierali:BAAALgAECgMJAwAAAA==.',
To='Toastedsushi:BAAALgAECgQJBgAAAA==.Toetagg:BAAALgAECgEJAQAAAA==.Toobooku:BAAALgADCgEJAQAAAA==.Toofwess:BAAALgADCgkJCQABLgAECgcJFgADACAYAA==.Torí:BAAALgADCgYJCAAAAA==.Tosala:BAAALgAECgYJDQAAAA==.Totemkiller:BAABLgAECn8bAAIFAAgJaw9UFAB1AQAFAAgJaw9UFAB1AQAAAA==.Totemtwiddlr:BAABLgAECn8UAAIFAAgJuRzHFAB3AgAFAAgJuRzHFAB3AgAAAA==.',
Tr='Traael:BAABLgAECn8XAAIIAAcJNhjCHgCnAQAIAAcJNhjCHgCnAQAAAA==.Trashbeard:BAAALgADCgIJAgAAAA==.Treebranch:BAAALgAECgEJAQAAAA==.Treesap:BAABLgAECn8iAAIoAAkJrxocAQBHAgAoAAkJrxocAQBHAgAAAA==.Trinityeve:BAAALgAECgMJBAAAAA==.Trnz:BAAALgAECggJEAABLgAECggJFAAFALkcAA==.Trnzlock:BAAALgAECgQJBgABLgAECggJFAAFALkcAA==.',
Tu='Tulanii:BAAALgADCgIJAgAAAA==.Tularana:BAABLgAECn8bAAIHAAgJWxb3KADBAQAHAAgJWxb3KADBAQABLgAFFAEJAQAGAAAAAA==.Tumble:BAAALgAECgcJEwAAAA==.Tummyissues:BAAALgAECgIJAgAAAA==.Tums:BAAALgAECgQJCQAAAA==.',
Tw='Twignberryz:BAAALgADCgQJBwABLgAECgQJBAAGAAAAAA==.Twinkie:BAAALgAECgYJEgAAAA==.Twodogz:BAABLgAECn8ZAAIIAAYJDiR/GQBvAgAIAAYJDiR/GQBvAgAAAA==.',
Ty='Tyious:BAABLgAECn8jAAMjAAkJ/xtGEQAxAgAjAAkJ/xtGEQAxAgAkAAUJBQyNLADaAAAAAA==.Tyndara:BAABLgAECn8WAAIKAAYJGA7SSAAvAQAKAAYJGA7SSAAvAQAAAA==.',
['Tü']='Tüesdaÿ:BAAALgAECgcJCwAAAA==.',
Uc='Uchihazephyr:BAAALgADCgIJAgABLgAFFAQJCgABAE4dAA==.',
Un='Unbeat:BAAALgAECgYJDAAAAA==.Unhoe:BAAALgADCggJEgAAAA==.Unholussie:BAACLgAFFH8FAAIjAAMJtAxyOADtAAAjAAMJtAxyOADtAAAuAAQKfycAAiMACAn0G/8UABICACMACAn0G/8UABICAAAA.Unholybowner:BAAALgADCgcJDAAAAA==.Unstablè:BAAALgAECgQJBAAAAA==.',
Ur='Ursane:BAABLgAECn8nAAIQAAgJ+BodBwA+AgAQAAgJ+BodBwA+AgAAAA==.Ursully:BAABLgAECn8WAAIYAAYJxiAxBQC9AQAYAAYJxiAxBQC9AQAAAA==.',
Uz='Uzi:BAAALgAECgYJCgAAAA==.',
Va='Vaardux:BAABLgAECn8WAAMLAAcJQh2BCABQAgALAAcJQh2BCABQAgAKAAUJRiIYWADaAQAAAA==.Vaelithra:BAAALgADCgEJAQAAAA==.Valamarl:BAAALgADCgcJCAAAAA==.Valkeria:BAAALgAECgEJAQAAAA==.Valíthria:BAAALgAECgYJBgAAAA==.Vampulla:BAABLgAECn8bAAIZAAgJEgdmOAACAQAZAAgJEgdmOAACAQAAAA==.Vanncint:BAAALgAECgQJBAAAAA==.Vanndrygos:BAAALgAECgYJCgAAAA==.Varea:BAAALgAECgIJAgAAAA==.Vashie:BAAALgAECggJEQAAAA==.',
Ve='Veigar:BAAALgAECgcJDgAAAA==.Velanis:BAAALgADCgUJBwAAAA==.Velmir:BAAALgAECgkJBwAAAA==.Velorius:BAAALgAECgEJAgAAAA==.Vexus:BAACLgAFFH8LAAIFAAMJqhXJEQDwAAAFAAMJqhXJEQDwAAAuAAQKfyEAAgUACAmKI8AJAPcCAAUACAmKI8AJAPcCAAAA.Vexuss:BAAALgAECgkJAgABLgAFFAMJCwAFAKoVAA==.',
Vi='Vidya:BAAALgADCgMJAwAAAA==.',
Vl='Vladios:BAAALgAECgYJCgAAAA==.',
Vo='Voidwraith:BAAALgADCgEJAQAAAA==.Vordarian:BAABLgAECn8WAAMDAAgJXQp6MwAlAQADAAgJXQp6MwAlAQASAAMJlAHROgBsAAAAAA==.',
Vy='Vynciaagn:BAAALgADCgcJEgAAAA==.',
Wa='Wafflehouse:BAAALgAECgcJEwAAAA==.Walolas:BAAALgADCgcJEAAAAA==.Watchmeburst:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgEJAQAAAA==.',
Wh='Whaler:BAABLgAECn8VAAIQAAcJgyM3DADqAQAQAAcJgyM3DADqAQAAAA==.Whìndy:BAAALgAECgQJBAABLgAECgQJCAAGAAAAAA==.',
Wi='Wildspanks:BAAALgADCgYJCQAAAA==.',
Xe='Xenos:BAAALgAECgIJAwAAAA==.Xenyodk:BAABLgAECn8ZAAIjAAkJqR4sCwByAgAjAAkJqR4sCwByAgAAAA==.Xenyovoker:BAAALgAECgkJAwAAAA==.',
Xi='Xideris:BAABLgAECn8jAAIWAAgJFCHmAQC9AgAWAAgJFCHmAQC9AgAAAA==.Xiderís:BAAALgAECgYJBgAAAA==.',
Xt='Xtraxtra:BAABLgAECn8iAAMJAAgJZhm+HABWAgAJAAgJZhm+HABWAgAcAAgJ4A3AEQB/AQAAAA==.',
Ya='Yaku:BAAALgAECgUJCAAAAA==.',
Ye='Yetzi:BAAALgADCgIJAgAAAA==.Yetzibel:BAAALgADCgQJBAAAAA==.',
Yo='Yoan:BAAALgAFFAIJAgAAAQ==.Yoga:BAAALgAECgIJAgAAAA==.Yonicbonnet:BAAALgAECgYJEgAAAA==.Yoondo:BAAALgAECgUJBwAAAA==.Yorde:BAAALgADCgcJBwAAAA==.',
Ys='Yshtola:BAAALgAECgcJEAAAAA==.',
Yu='Yuffie:BAAALgAECgQJBAAAAA==.Yunara:BAABLgAECn8aAAIZAAcJKR5ZEQDjAQAZAAcJKR5ZEQDjAQAAAA==.Yunge:BAAALgADCgQJBAAAAA==.',
Za='Zabra:BAAALgAECgUJDQAAAA==.Zachpally:BAAALgADCgUJBQAAAA==.Zahvoker:BAAALgAECgUJCgAAAA==.Zapkitti:BAAALgADCgQJBAAAAA==.Zareline:BAAALgAECgQJBgAAAA==.Zathaeus:BAABLgAECn8VAAIZAAgJ0RRxVQCjAQAZAAgJ0RRxVQCjAQAAAA==.Zaylian:BAABLgAECn8eAAIfAAgJQBmQBgD3AQAfAAgJQBmQBgD3AQAAAA==.Zayragossa:BAABLgAFFH8FAAIeAAIJEBz8PACwAAAeAAIJEBz8PACwAAAAAA==.',
Ze='Zeerkk:BAABLgAECn8dAAIeAAgJNhebGQDdAQAeAAgJNhebGQDdAQAAAA==.Zelanta:BAAALgADCgQJBAAAAA==.Zergmark:BAAALgADCgMJAwAAAA==.Zero:BAAALgADCgIJAgAAAA==.',
Zo='Zouris:BAAALgAECgIJAgAAAA==.',
Zt='Ztaziki:BAAALgADCgQJBAAAAA==.',
Zu='Zulkraa:BAAALgAECgQJBQAAAA==.Zulmex:BAAALgAECgYJCwAAAA==.Zunda:BAAALgAECgkJBwAAAA==.Zurtogg:BAABLgAECn8ZAAMQAAcJPBdGEAC5AQAQAAcJnhZGEAC5AQAmAAMJVxQHJQDFAAAAAA==.',
['Ài']='Àirén:BAAALgAECgEJAQAAAA==.',
['Ön']='Öndi:BAAALgADCgYJBgAAAA==.',
['ßr']='ßrûh:BAAALgADCgEJAQAAAA==.',
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

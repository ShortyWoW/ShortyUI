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

local lookup = {'Shaman-Restoration','Paladin-Retribution','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','DeathKnight-Unholy','Evoker-Preservation','Warlock-Affliction','Druid-Restoration','Druid-Balance','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Unknown-Unknown','Monk-Brewmaster','Warrior-Protection','Paladin-Protection','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Hunter-Marksmanship','Druid-Guardian','Hunter-Survival','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Feral','Evoker-Devastation','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abcede:BAAALgAECgIJAgABLgAECggJHQABAGUWAA==.',
Ac='Achillguy:BAAALgADCgYJBgAAAA==.',
Ae='Aelene:BAABLgAECn8iAAMCAAkJ/Q7AbQCiAQACAAgJpA3AbQCiAQADAAcJBRAROACaAQAAAA==.Aelthryn:BAAALgADCgEJAQAAAA==.Aetrix:BAAALgADCgQJBAAAAA==.',
Ag='Agonybehold:BAAALgADCgkJCQAAAA==.Agrolloch:BAAALgAECgYJCgAAAA==.',
Ah='Ahgain:BAAALgAFFAEJAgAAAA==.Ahino:BAAALgADCgkJJgAAAA==.',
Ai='Aica:BAAALgAECgEJAQABLgAFFAcJHgAEAHocAA==.Aisa:BAACLgAFFH8eAAMEAAcJehxbAwDMAQAEAAYJbR5bAwDMAQAFAAQJ0Bo3BQAkAQAuAAQKfy8AAwQACQm/Jf0AAM0DAAQACQmfJf0AAM0DAAUABgmuJQkFAIsCAAAA.Aish:BAACLgAFFH8hAAICAAcJliUlAAB+AgACAAcJliUlAAB+AgAuAAQKfyMAAgIACQlnJv0AAN4DAAIACQlnJv0AAN4DAAAA.',
Ak='Akorvis:BAAALgADCgIJAQAAAA==.',
Al='Aldofio:BAAALgAECgYJBQAAAA==.Alenhall:BAAALgAECgYJCgAAAA==.Aleson:BAABLgAECn8fAAMGAAgJqwPKbwD5AAAGAAgJqwPKbwD5AAAHAAQJ0gDdGQBJAAAAAA==.Alexgreece:BAAALgAECgYJBgABLgAFFAcJDgAIAEwTAA==.Alirann:BAAALgAECgQJBAAAAA==.Alisu:BAAALgADCgEJAQAAAA==.Aljoumeiro:BAABLgAECn8hAAIJAAgJixhUDQA5AgAJAAgJixhUDQA5AgAAAA==.Alvln:BAACLgAFFH8NAAIKAAUJzhZoDgBEAQAKAAUJzhZoDgBEAQAuAAQKfx4AAgoACAmLHc0pAFoCAAoACAmLHc0pAFoCAAAA.',
Am='Amarasha:BAAALgADCgUJAQAAAA==.',
An='Andyrios:BAAALgAECgYJDgAAAA==.Aniki:BAAALgAECgkJEwAAAA==.',
Ap='Apathy:BAAALgAECgYJBwAAAA==.Aphoristic:BAAALgAFFAEJAQABLgAFFAQJBgAFAOMCAA==.Apothecary:BAAALgADCgUJCAAAAA==.',
Ar='Arahat:BAAALgAECgcJEQAAAA==.Arakk:BAABLgAECn8ZAAIKAAcJthX7PgDqAAAKAAcJthX7PgDqAAAAAA==.Aralinya:BAACLgAFFH8RAAILAAUJaRsAAgCzAQALAAUJaRsAAgCzAQAuAAQKfygAAwsACQkaHNoKAKECAAsACQkbHNoKAKECAAgAAQmwBxljADIAAAAA.Arasenpai:BAAALgAECggJCgAAAA==.Ardentflame:BAABLgAECn8iAAIEAAgJgRMWJQCcAQAEAAgJgRMWJQCcAQAAAA==.Arleric:BAAALgADCgkJEgAAAA==.Arlerknight:BAAALgADCgYJBgAAAA==.Arlermage:BAAALgADCgUJBwAAAA==.Arrine:BAAALgAECgEJAQAAAA==.Artpop:BAAALgAECgMJAgABLgAFFAQJDAAMAP8UAA==.',
As='Asiris:BAAALgAECgIJAgAAAA==.Asperonia:BAACLgAFFH8eAAIDAAcJ7hnTAAA9AgADAAcJ7hnTAAA9AgAuAAQKfy8AAwMACQl2JT8CAFkDAAMACQl2JT8CAFkDAAIAAQlvJMYWAWoAAAAA.Aster:BAABLgAECn8fAAINAAgJzB+uDABiAgANAAgJzB+uDABiAgABLgAFFAUJDQAKAM4WAA==.Asteriøn:BAAALgADCgUJBQAAAA==.Astinous:BAAALgAECgQJCAAAAA==.Astral:BAAALgAECgcJDwAAAA==.Astrid:BAACLgAFFH8TAAIOAAYJbRwsAQAuAgAOAAYJbRwsAQAuAgAuAAQKfxoAAg4ACAmuHfEKAIYCAA4ACAmuHfEKAIYCAAAA.',
At='Ataraxia:BAABLgAECn8VAAICAAYJZhLAXgD4AAACAAYJZhLAXgD4AAAAAA==.',
Au='Ausdemonic:BAABLgAECn8VAAMEAAYJUhm+MgBhAQAEAAYJ2ha+MgBhAQAPAAIJhR8uDQBcAAAAAA==.',
Av='Avell:BAABLgAECn8fAAIDAAgJZyXUBQAOAwADAAgJZyXUBQAOAwAAAA==.Avocardio:BAAALgAECgUJDwAAAA==.',
Ax='Axiomatic:BAACLgAFFH8GAAMFAAQJ4wINDwCJAAAFAAIJhgANDwCJAAAEAAMJoAMKUQCFAAAuAAQKfy0ABAQACQmhHdASAOUCAAQACQlpHNASAOUCAAUABgkkFvATAKsBAA8AAgmaFuIZAKkAAAAA.',
Az='Azsharia:BAAALgAECgIJAgAAAA==.Azzielliea:BAABLgAECn8iAAIGAAgJORI5NQCQAQAGAAgJORI5NQCQAQAAAA==.',
Ba='Babytroll:BAABLgAECn8dAAMQAAkJpgoLMQAXAQAQAAkJpgoLMQAXAQARAAIJIAGcjgAeAAAAAA==.Badds:BAABLgAECn8jAAIQAAkJtBrQGgBkAgAQAAkJtBrQGgBkAgAAAA==.Barleybrew:BAAALgADCgYJBgAAAA==.Battletank:BAABLgAECn8bAAMSAAgJchRmDADaAQASAAgJchRmDADaAQATAAYJjwtbXAA+AQABLgAFFAUJDQAKAM4WAA==.',
Be='Beefchar:BAABLgAECn8UAAIUAAYJwhebFABcAQAUAAYJwhebFABcAQAAAA==.Beefpalmy:BAAALgAECgEJAQABLgAECgYJFAAUAMIXAA==.Beefybone:BAAALgADCgcJBAAAAA==.Beerofftap:BAAALgAECgUJCwAAAA==.Beerontap:BAAALgADCgQJBQAAAA==.Belalugosi:BAABLgAECn8ZAAIMAAgJviK0AQAbAwAMAAgJviK0AQAbAwAAAA==.Bethc:BAAALgAECgcJCwAAAA==.Betray:BAABLgAECn8ZAAIGAAgJTxoLOgCOAgAGAAgJTxoLOgCOAgAAAA==.Beàr:BAAALgAECgYJDwAAAA==.',
Bi='Bielobog:BAAALgAECgUJBgAAAA==.Bigbadbaka:BAACLgAFFH8cAAMTAAcJrx1UAADwAQATAAYJ6x5UAADwAQASAAUJ0RqtAADKAQAuAAQKfykAAxMACQlWJcwBAKwDABMACQlWJcwBAKwDABIACQktHG0BADkDAAAA.Bigsimón:BAAALgAECgQJBAAAAA==.Bink:BAAALgAECgQJBQAAAA==.Biscuitpaw:BAAALgADCggJFQAAAA==.Bizz:BAAALgAECgUJBgAAAA==.',
Bl='Blackwind:BAABLgAECn8XAAIIAAYJPR50JwCdAQAIAAYJPR50JwCdAQAAAA==.Bladeripper:BAAALgADCgYJBgAAAA==.Blazez:BAACLgAFFH8IAAICAAUJgxnZGQAQAQACAAUJgxnZGQAQAQAuAAQKfyYAAgIACQnJIHAJAEUDAAIACQnJIHAJAEUDAAAA.',
Bo='Bogart:BAACLgAFFH8OAAMEAAUJ1BwWDgBrAQAEAAUJ1BwWDgBrAQAPAAEJSQmPBABQAAAuAAQKfygAAgQACQlgI+ACAJUDAAQACQlgI+ACAJUDAAAA.Bomohdh:BAACLgAFFH8MAAIKAAUJihbGDwBQAQAKAAUJihbGDwBQAQAuAAQKfyYAAgoACQmjITIGAGMDAAoACQmjITIGAGMDAAAA.Bomohdk:BAAALgAECgcJBQABLgAFFAUJDAAKAIoWAA==.Boogeymayne:BAAALgAECgYJCQAAAA==.',
Br='Braeburn:BAAALgAECgQJBgAAAA==.Brawny:BAAALgAECgYJCgAAAA==.Brevren:BAABLgAECn8WAAINAAcJeR8+QAA3AgANAAcJeR8+QAA3AgAAAA==.Brevrin:BAAALgAECgEJAQABLgAECggJFgANAHkfAA==.Brewtality:BAAALgAECgEJAQAAAA==.Brexan:BAAALgAECgUJBwAAAA==.Brüder:BAAALgADCgEJAQABLgAECgYJCwAVAAAAAA==.',
Bu='Buibuis:BAABLgAFFH8HAAIWAAUJLxUeBQCDAQAWAAUJLxUeBQCDAQABLgAFFAcJEgAXANgdAA==.Buikia:BAACLgAFFH8SAAIXAAcJ2B1YAAA6AgAXAAcJ2B1YAAA6AgAuAAQKfxUAAhcACQntJAkBAI0DABcACQntJAkBAI0DAAAA.Bullmon:BAAALgAECgEJAQABLgAFFAcJGAARALUmAA==.Buysfeetpics:BAACLgAFFH8SAAIGAAYJKhkNBQAXAgAGAAYJKhkNBQAXAgAuAAQKfywAAgYACQkkJe0CANADAAYACQkkJe0CANADAAAA.',
['Bâ']='Bânê:BAABLgAECn8dAAIYAAgJiSSCAgAMAwAYAAgJiSSCAgAMAwAAAA==.',
Ca='Cannicus:BAACLgAFFH8YAAMGAAcJaSEDAQBWAgAGAAcJaSEDAQBWAgAHAAIJiRHIAACqAAAuAAQKfy8AAwYACQmXJkACANoDAAYACQllJkACANoDAAcABwnRJCsCAIMCAAAA.Careshield:BAAALgAECgcJDgABLgAFFAUJDQAKAM4WAA==.Careßear:BAAALgAFFAEJAQABLgAFFAcJFAAOAKUUAA==.Caridee:BAAALgAECgQJCwAAAA==.Cavoker:BAAALgADCgEJAQAAAA==.',
Ce='Celavii:BAABLgAECn8VAAIZAAgJtxJqLgD4AQAZAAgJtxJqLgD4AQAAAA==.',
Ch='Chappell:BAAALgAECgYJCgAAAA==.Chargeplox:BAAALgAECgYJEAAAAA==.Cherrybelles:BAABLgAECn8YAAQaAAgJABwOBACWAgAaAAgJABwOBACWAgAIAAQJpw4lRADbAAALAAEJFA1VfAA3AAAAAA==.Chiihiro:BAAALgAECgEJAgAAAA==.Chillicheese:BAAALgAECgQJBAAAAA==.Chinnohoho:BAABLgAECn8gAAIZAAgJkyGvDQDQAgAZAAgJkyGvDQDQAgAAAA==.Chinnosaurus:BAAALgAECggJCAAAAA==.Chinnozoic:BAAALgADCgIJAgAAAA==.Chokobo:BAACLgAFFH8VAAIRAAUJVxdMBACoAQARAAUJVxdMBACoAQAuAAQKfycAAxEACAkqI7QMAM0CABEACAkqI7QMAM0CABAAAwnVGCacAJMAAAAA.Chunkz:BAAALgAECgQJBAAAAA==.',
Ci='Cindermoon:BAAALgADCgkJEAAAAA==.Cinema:BAAALgADCggJCAABLgAFFAQJCwAYALoTAA==.',
Co='Colena:BAAALgAECgYJCAAAAA==.Comai:BAAALgADCgcJBwABLgAFFAUJDAAbABMUAA==.Conquest:BAABLgAECn8YAAMRAAcJmQqAQwAhAQARAAcJmQqAQwAhAQAQAAYJTwZ1gADZAAAAAA==.Corbulus:BAABLgAECn8bAAICAAgJVxpOIwC4AQACAAgJVxpOIwC4AQAAAA==.Cowboytridda:BAAALgAECgIJAgAAAA==.',
Cr='Creepzpewpew:BAAALgAECgEJAQAAAA==.Crispyarrowz:BAAALgAECggJEgAAAA==.Crispymage:BAAALgAECggJCQABLgAECggJEgAVAAAAAA==.Cronus:BAACLgAFFH8FAAIZAAIJSxCfFQCuAAAZAAIJSxCfFQCuAAAuAAQKfygAAxkACAlmJf8GAB8DABkACAlmJf8GAB8DABwABgnuFLA5AHkBAAAA.Crsd:BAAALgADCgQJCAABLgAFFAMJBAAVAAAAAA==.',
Cy='Cyndi:BAABLgAECn8UAAIdAAYJWQmfEgCTAAAdAAYJWQmfEgCTAAAAAA==.',
Da='Dad:BAAALgAECgIJAgAAAA==.Dahlee:BAABLgAECn8dAAIOAAgJzBIdCACqAQAOAAgJzBIdCACqAQAAAA==.Dahyunn:BAAALgAECgkJDgAAAA==.Daice:BAACLgAFFH8IAAIeAAMJPgbiAgDvAAAeAAMJPgbiAgDvAAAuAAQKfxsAAh4ACAn3FnAIAGMCAB4ACAn3FnAIAGMCAAAA.Darcious:BAABLgAECn8dAAMCAAcJoxSXKACgAQACAAcJoxSXKACgAQADAAUJNBnEIgAwAQABLgAECggJFQAZALcSAA==.Darkcinders:BAAALgADCgkJEwAAAA==.Darkxeno:BAABLgAECn8iAAMNAAgJVxV4HADdAQANAAgJVxV4HADdAQAfAAIJBg5yDwBCAAAAAA==.Daydreamer:BAAALgAECgYJBgABLgAECggJKAAIAFQlAA==.',
De='Deadlly:BAABLgAECn8mAAIYAAgJfhkbCABZAgAYAAgJfhkbCABZAgAAAA==.Deadz:BAAALgAECgQJCAAAAA==.Dearest:BAAALgADCgMJAwAAAA==.Deathbybelf:BAAALgAECgQJCAAAAA==.Deathchup:BAAALgAECgkJAwAAAA==.Deathdemons:BAAALgAECgEJAQABLgAFFAQJBQANAJYWAA==.Deathlink:BAAALgAECgMJBgAAAA==.Deathmage:BAAALgADCgEJAQABLgAFFAQJBQANAJYWAA==.Deathmonks:BAAALgAECgEJAgABLgAFFAQJBQANAJYWAA==.Deathrocks:BAABLgAFFH8FAAINAAQJlhaTHABGAQANAAQJlhaTHABGAQAAAA==.Deathweezy:BAAALgAECgUJBwABLgAECgkJEwAVAAAAAA==.Deejaboo:BAAALgAECgQJBgAAAA==.Demöníc:BAACLgAFFH8MAAIKAAMJFhgeHQD3AAAKAAMJFhgeHQD3AAAuAAQKfzkAAwoACAmVJP0FAH0CAAoACAmVJP0FAH0CACAABAmGGkwYANwAAAAA.Deplock:BAAALgAECgQJCAABLgAECggJIAANAKIeAA==.Destcrypt:BAAALgAECgUJBQABLgAFFAMJBwAMAMQgAA==.Destwind:BAACLgAFFH8HAAIMAAMJxCBsDQAFAQAMAAMJxCBsDQAFAQAuAAQKfzQAAgwACAk4JAEEADEDAAwACAk4JAEEADEDAAAA.',
Di='Dirtypapa:BAAALgAECgUJDgAAAA==.Divïne:BAABLgAECn8WAAQCAAgJuRrSSQAFAgACAAgJ6xfSSQAFAgAYAAMJ1BY0JwDPAAADAAEJ8AOSkQA6AAAAAA==.',
Do='Doeji:BAAALgAECgkJDgAAAA==.Dotdotseckz:BAAALgADCgcJBwABLgAECggJLQACAEYZAA==.',
Dr='Drackor:BAAALgAECgEJAQAAAA==.Dragonboar:BAAALgADCgcJCAAAAA==.Dragos:BAAALgAECgkJCQAAAA==.Dreadnok:BAAALgAECgUJCAAAAA==.Drethalis:BAAALgADCggJFgAAAA==.Drewstormio:BAAALgAECgYJDAAAAA==.',
Ds='Dsdh:BAACLgAFFH8MAAIKAAcJUxNzBADqAQAKAAcJUxNzBADqAQAuAAQKfysAAwoACQk8JQ8EAIgDAAoACQnuJA8EAIgDACEABwniGX0cAN0BAAAA.',
Du='Dulang:BAABLgAFFH8KAAIZAAQJzQ+UCwAGAQAZAAQJzQ+UCwAGAQAAAA==.',
['Dé']='Déáth:BAAALgAECgUJBgAAAA==.',
Ec='Ectruby:BAACLgAFFH8GAAIiAAQJ7wWVAgAiAQAiAAQJ7wWVAgAiAQAuAAQKfycAAyIACQkvGgEEAOcCACIACQkvGgEEAOcCABEAAQllDn59ADYAAAAA.',
Eg='Eg:BAAALgAECgIJAQAAAA==.',
Ej='Ejae:BAACLgAFFH8JAAIKAAQJJwOVIQDgAAAKAAQJJwOVIQDgAAAuAAQKfxYAAgoACAn5FWwSANkBAAoACAn5FWwSANkBAAEuAAUUBwkUABkAmiEA.',
El='Elagrom:BAABLgAECn8WAAIbAAcJEg/XJAD8AAAbAAcJEg/XJAD8AAAAAA==.Elertricsoup:BAABLgAECn8UAAIZAAYJUgSSTADqAAAZAAYJUgSSTADqAAAAAA==.Elladea:BAAALgAECgQJBgAAAA==.Ellieakita:BAAALgADCgUJBgAAAA==.Elwarlocko:BAABLgAECn8mAAMEAAgJvh8OEwAMAgAEAAcJqyAOEwAMAgAFAAcJpBw1BgBaAQAAAA==.Elwhy:BAAALgAFFAIJBAAAAA==.Elyndre:BAACLgAFFH8UAAMOAAcJpRTgAgDcAQAOAAYJ3xLgAgDcAQAUAAEJ4xXnHgBaAAAuAAQKfx0ABA4ACQlXGhQYANQBAA4ABwlBFxQYANQBABQACAlbIs8PAJMBACMAAQlnFng8ADwAAAAA.',
Em='Emberis:BAAALgAECgQJBQAAAA==.',
En='Endari:BAABLgAFFH8IAAIEAAYJLRT+EQBVAQAEAAYJLRT+EQBVAQAAAA==.Endris:BAAALgADCgUJCQAAAA==.',
Er='Erikk:BAACLgAFFH8VAAIKAAcJxg2OBQDOAQAKAAcJxg2OBQDOAQAuAAQKfysAAgoACQkHImUIAEcDAAoACQkHImUIAEcDAAAA.Eru:BAAALgAECgcJEQAAAA==.',
Es='Escher:BAAALgAECgYJCQAAAA==.Espresso:BAABLgAECn8VAAMBAAgJGA2PNQCtAQABAAgJGA2PNQCtAQAbAAYJaAklTgAOAQABLgAFFAYJEwASAAEWAA==.',
Ev='Evanlyn:BAAALgADCgEJAgABLgAECgYJCwAVAAAAAA==.',
Ex='Excelfron:BAAALgAECgYJDwAAAA==.',
Ey='Eyanos:BAAALgAECgcJCAAAAA==.',
Fa='Fake:BAAALgAECgEJAwAAAA==.Famine:BAABLgAECn8gAAQNAAgJoh5fHwDLAQANAAgJAh5fHwDLAQAfAAEJFh6jDQBbAAAJAAEJzwTkLAAqAAAAAA==.Fatzreaver:BAABLgAECn8fAAINAAgJlgzrNwBaAQANAAgJlgzrNwBaAQAAAA==.',
Fe='Fearran:BAAALgADCgcJCAAAAA==.Fenrirneco:BAAALgADCgEJAQAAAA==.Fenrith:BAAALgADCgMJAwAAAA==.',
Ff='Ffdeathpunch:BAAALgADCgUJBQABLgAECggJFgANAHkfAA==.Ffen:BAAALgAECgcJCAAAAA==.',
Fi='Fibanocci:BAAALgAECgEJAQABLgAECgcJCQAVAAAAAA==.Fired:BAAALgAECgEJAQAAAA==.',
Fl='Flamerage:BAAALgAECggJCAAAAA==.Flogarcus:BAAALgAECgUJBgAAAA==.',
Fr='Frankadelic:BAABLgAECn8gAAIcAAcJixWDBgCGAQAcAAcJixWDBgCGAQAAAA==.Frodolol:BAACLgAFFH8bAAIGAAYJVh6cBADmAQAGAAYJVh6cBADmAQAuAAQKfyEAAgYACQmFJLkIAIEDAAYACQmFJLkIAIEDAAAA.Frogwash:BAAALgADCgcJBwAAAA==.Frostik:BAABLgAFFH8LAAMfAAQJqBrJAABpAQAfAAQJqBrJAABpAQANAAMJ9g1rRQCZAAAAAA==.Frostyfruit:BAABLgAECn8gAAIGAAgJjx3TGgAKAgAGAAgJjx3TGgAKAgAAAA==.Frozenhell:BAABLgAECn8hAAIGAAkJPxW1MAChAQAGAAkJPxW1MAChAQAAAA==.',
Fu='Fufamace:BAAALgAECgMJAwAAAA==.Fufina:BAAALgAECgMJBQAAAA==.',
Fw='Fwooplin:BAABLgAECn8ZAAMaAAgJ1SCKCAANAgAaAAUJaySKCAANAgAIAAYJWh/eGwD+AQAAAA==.',
Fy='Fya:BAAALgAECgcJDwAAAA==.',
['Fó']='Fóx:BAAALgADCgkJDQAAAA==.',
Ga='Gannina:BAACLgAFFH8MAAIkAAUJPxQkBQBHAQAkAAUJPxQkBQBHAQAuAAQKfx4AAiQACQntIQsHAA0DACQACQntIQsHAA0DAAAA.',
Ge='Georgecloney:BAAALgAECgQJBAABLgAECgkJIAASAA8VAA==.',
Gi='Gillemon:BAAALgAECgQJBAAAAA==.Gizzy:BAAALgAECgYJCgAAAA==.',
Go='Goblincave:BAACLgAFFH8FAAIbAAMJTQt9EwDhAAAbAAMJTQt9EwDhAAAuAAQKfxoAAhsACAkLIKUNAMcCABsACAkLIKUNAMcCAAAA.Goodra:BAAALgAFFAEJAQABLgAFFAUJDQAKAM4WAA==.Goodwill:BAABLgAECn8tAAQZAAgJwyMBBwCHAgAcAAgJyB4HEQCwAgAZAAgJzyEBBwCHAgAeAAcJVBqbBwDuAQAAAA==.',
Gr='Graoul:BAACLgAFFH8IAAIMAAUJYwy+DAAQAQAMAAUJYwy+DAAQAQAuAAQKfycAAgwACAlyIAcJAMICAAwACAlyIAcJAMICAAAA.Greatpals:BAAALgAECgUJCQAAAA==.Grewsome:BAAALgAECgQJBAAAAA==.Grindelwald:BAAALgAECgYJDgAAAA==.Gryffin:BAABLgAECn8kAAIIAAgJ9BKHCwDHAQAIAAgJ9BKHCwDHAQAAAA==.',
Gt='Gtamage:BAAALgADCggJCAAAAA==.',
Gu='Gugudan:BAABLgAECn8WAAMEAAcJoRebLQB2AQAEAAcJ+BabLQB2AQAFAAQJChbUOwDFAAAAAA==.Guh:BAAALgAECgYJDQAAAA==.Guiltyclown:BAABLgAECn8vAAIWAAkJ7CAJAgDMAgAWAAkJ7CAJAgDMAgAAAA==.Gummyworms:BAAALgAECgEJAgAAAA==.Gunnina:BAAALgAECgcJCgAAAA==.Gutsc:BAABLgAECn8hAAMMAAgJ/hS4DwCsAQAMAAgJ/hS4DwCsAQAkAAIJCQsXNwBiAAAAAA==.Gutt:BAAALgADCgEJAQABLgAECgEJAQAVAAAAAA==.Gutts:BAAALgAECgQJEQAAAA==.Guzzan:BAAALgAECgYJCgAAAA==.',
['Gû']='Gûilty:BAAALgADCgcJBwAAAA==.',
Ha='Hammerboltie:BAAALgAECgcJCQAAAA==.Hamuchivt:BAAALgAECgYJEQAAAA==.Haoso:BAAALgAECgEJAQAAAA==.Haravell:BAAALgADCgEJAQAAAA==.Harmony:BAAALgAECgcJBAAAAA==.Haroze:BAAALgAFFAIJBAAAAA==.Hawkaye:BAAALgADCgMJAwAAAA==.Haydos:BAAALgAECgQJBAAAAA==.',
He='Helios:BAAALgADCgkJDgAAAA==.Hemloque:BAAALgAECgMJAwAAAA==.Hershéy:BAABLgAECn8hAAIQAAgJLyGSCQD5AgAQAAgJLyGSCQD5AgAAAA==.Hert:BAAALgAECgMJAwAAAA==.',
Ho='Hothotseckz:BAABLgAECn8tAAMCAAgJRhkDGAD8AQACAAgJRhkDGAD8AQADAAUJEQ/1WwANAQAAAA==.',
Hu='Hukk:BAAALgADCgUJBQAAAA==.Hurricanebom:BAAALgAECgYJBgAAAA==.',
Hy='Hypervoltage:BAAALgAECgcJEgAAAA==.Hyve:BAAALgAECggJBQAAAA==.',
Ia='Ial:BAABLgAECn8oAAIIAAgJVCWmAQDZAgAIAAgJVCWmAQDZAgAAAA==.',
Ic='Icysun:BAAALgAECgkJEAAAAA==.',
Id='Idgit:BAAALgADCgEJAQAAAA==.',
Im='Imnotacat:BAAALgAECgMJBAAAAA==.Imnotholy:BAABLgAECn8dAAIDAAgJiyLdAwDBAgADAAgJiyLdAwDBAgABLgAECggJKAAIAFQlAA==.Imthebaglady:BAAALgAECgkJAgAAAA==.',
In='Invaderbull:BAABLgAECn8hAAMTAAYJjBQJTwBrAQATAAYJdxIJTwBrAQASAAQJjQ5kFwC+AAAAAA==.',
Is='Isatarp:BAABLgAECn8cAAIcAAgJdR/aDQDSAgAcAAgJdR/aDQDSAgABLgAFFAcJHgAEAHocAA==.Isee:BAAALgADCgYJCQAAAA==.Ish:BAAALgAECgkJAwAAAA==.Isopod:BAAALgAECgYJDQAAAA==.Isyldia:BAAALgAECgkJEAAAAA==.',
Iv='Ivee:BAAALgAECgYJEAAAAA==.',
Ja='Jakhoul:BAAALgADCgQJBAAAAA==.Janlul:BAABLgAECn8XAAIZAAkJOReaIQA8AgAZAAkJOReaIQA8AgAAAA==.Jashy:BAAALgAECgUJBQABLgAFFAUJCwAZAOMdAA==.Jasmean:BAACLgAFFH8LAAMZAAUJ4x1SAwCLAQAZAAQJ4x1SAwCLAQAcAAMJAA4FHwCaAAAuAAQKfygABBwACQlLJKsNANUCABwACAnTIasNANUCABkABQkLJPMuAFUBAB4AAQnUFBQrAEgAAAAA.Jaxxyn:BAABLgAECn8aAAMfAAcJ1CAYBQD0AQAfAAYJ+R0YBQD0AQANAAYJcRktUQANAQAAAA==.',
Je='Jennatelia:BAABLgAECn8UAAINAAgJFxCELACJAQANAAgJFxCELACJAQAAAA==.',
Jo='Jodric:BAAALgADCgcJDQAAAA==.Johnevoker:BAACLgAFFH8FAAIOAAMJhQ5IDwDNAAAOAAMJhQ5IDwDNAAAuAAQKfxkABA4ACAnhDkcZAMUBAA4ACAnhDkcZAMUBACMAAwlaCEAyAIQAABQAAQndAU9pACMAAAAA.Johnthefury:BAAALgADCgQJBAABLgAFFAMJBQAOAIUOAA==.Jombii:BAAALgAECgMJAQAAAA==.Jordoom:BAAALgAECgYJCgAAAA==.Jostwia:BAAALgADCgkJCQAAAA==.',
Ka='Kafra:BAABLgAECn8VAAIQAAgJ2hwZEAC3AgAQAAgJ2hwZEAC3AgAAAA==.Kamazira:BAAALgAECgYJCwAAAA==.Kariiyon:BAABLgAECn8UAAIRAAYJpxCwHgAHAQARAAYJpxCwHgAHAQAAAA==.Katalen:BAAALgAECgQJBQAAAA==.Kayapau:BAACLgAFFH8TAAIbAAUJ/Q+GBgByAQAbAAUJ/Q+GBgByAQAuAAQKfyQAAxsACAlLHcgfABECABsACAlLHcgfABECAAEABglVDo5XACkBAAAA.',
Ke='Kerìnne:BAAALgAECgMJBQAAAA==.Kevd:BAABLgAECn9AAAIQAAcJpiIpEgCkAgAQAAcJpiIpEgCkAgABLgAFFAYJMgABABIkAA==.Kevin:BAACLgAFFH8yAAIBAAYJEiQ/AABlAgABAAYJEiQ/AABlAgAuAAQKfzAAAwEACQknJjIAAN0DAAEACQknJjIAAN0DABsAAQmyDaWHADIAAAAA.',
Kh='Khaii:BAACLgAFFH8RAAIGAAUJGCalBgDKAQAGAAUJGCalBgDKAQAuAAQKfygAAwYACQnSJigBAO8DAAYACQnSJigBAO8DAAcAAQm2JTwIAHAAAAAA.',
Ki='Kizen:BAAALgADCgMJAwAAAA==.',
Kj='Kj:BAABLgAECn8UAAIUAAgJnBfMBwAUAgAUAAgJnBfMBwAUAgABLgAFFAYJFAAlAFwbAA==.',
Ko='Komai:BAACLgAFFH8MAAMbAAUJExRqDAAnAQAbAAUJExRqDAAnAQABAAIJNCCpGQDDAAAuAAQKfygAAxsACQmnIT0JAP4CABsACQmnIT0JAP4CAAEACAlQHoEVAGkCAAAA.Kopikia:BAABLgAECn8iAAMKAAkJgBKUMAA5AgAKAAkJgBKUMAA5AgAhAAYJwgUtPgAEAQAAAA==.Kora:BAAALgADCgUJBAAAAA==.',
Kp='Kpôp:BAAALgAECggJEAAAAA==.',
Kr='Krosis:BAABLgAECn8hAAIMAAgJXhjWEQBDAgAMAAgJXhjWEQBDAgAAAA==.Kru:BAACLgAFFH8QAAMNAAUJqhQTHQBEAQANAAQJqhQTHQBEAQAJAAEJAABEHgAAAAAuAAQKfyAAAg0ACAm5I/sQABYDAA0ACAm5I/sQABYDAAAA.Krucify:BAABLgAFFH8GAAIXAAUJNAciCQDvAAAXAAUJNAciCQDvAAAAAA==.Kruukk:BAABLgAECn8eAAIeAAgJjhcECwAlAgAeAAgJjhcECwAlAgAAAA==.',
Kt='Ktd:BAAALgAECgcJCQABLgAFFAQJCwAEAEMTAA==.Ktl:BAACLgAFFH8LAAIEAAQJQxN5HAAwAQAEAAQJQxN5HAAwAQAuAAQKfx8AAwQACAlgH0seAKECAAQACAlzHUseAKECAAUAAgkMJa4VAG4AAAAA.Ktz:BAAALgADCgYJBgABLgAFFAQJCwAEAEMTAA==.',
Ku='Kueipeh:BAAALgAECgIJAwAAAA==.Kulak:BAAALgADCgMJAwAAAA==.Kungfufa:BAAALgAECgIJAgAAAA==.Kuroski:BAAALgADCggJDwAAAA==.',
Ky='Kyall:BAABLgAECn8xAAIhAAkJaR59CQDKAgAhAAkJaR59CQDKAgAAAA==.Kyrisa:BAAALgADCgIJAgAAAA==.Kyrâ:BAAALgADCgUJBQAAAA==.',
La='Lacktoes:BAAALgAECgQJBAAAAA==.Lafret:BAABLgAECn8aAAIQAAYJohtvJABgAQAQAAYJohtvJABgAQAAAA==.Lamerzz:BAABLgAECn8WAAMPAAUJQBSiDgBHAQAPAAUJOhSiDgBHAQAEAAUJXA+kUwD2AAAAAA==.Laszal:BAAALgADCgMJAwAAAA==.',
Le='Legôlas:BAAALgADCgEJAQAAAA==.Lettuce:BAABLgAECn8eAAIRAAkJah1/BwAeAwARAAkJah1/BwAeAwAAAA==.Lexianna:BAAALgADCgQJBQAAAA==.',
Lh='Lh:BAAALgADCgcJBQAAAA==.',
Li='Lilgrnbstd:BAAALgAECgIJAgABLgAECgYJHQAGAEIhAA==.Liquidbreath:BAAALgAECgEJAQABLgAECgkJKgALAE4gAA==.Liquidsnake:BAAALgADCgMJBAAAAA==.Liquidvoid:BAABLgAECn8qAAILAAkJTiBOAQAnAwALAAkJTiBOAQAnAwAAAA==.Littlehill:BAAALgAECgQJBgAAAA==.',
Lo='Lockley:BAAALgAECgIJAwAAAA==.Lokomoco:BAABLgAECn8WAAIXAAgJBCMBBAAOAwAXAAgJBCMBBAAOAwAAAA==.Lolcarni:BAAALgADCgEJAwAAAA==.Loneboi:BAAALgAECgEJAQAAAA==.Loom:BAAALgADCgEJAgAAAA==.Lorellon:BAAALgAECgEJAgAAAA==.Lowcarbbeer:BAAALgAECgYJEAAAAA==.',
Lu='Lupercal:BAAALgAECgkJBQAAAA==.Luxen:BAAALgAECgEJAgAAAA==.',
Ly='Lyadrin:BAAALgADCgEJAQAAAA==.Lycán:BAAALgAECgcJCQAAAA==.Lyla:BAAALgADCgIJAgAAAA==.Lyntia:BAAALgAECgYJCAAAAA==.Lythium:BAABLgAECn8fAAIXAAgJ7CTVAAD3AgAXAAgJ7CTVAAD3AgAAAA==.',
Ma='Maceson:BAAALgAECgYJCwAAAA==.Magnifico:BAAALgAECgEJAQAAAA==.Majicboner:BAAALgAECgYJDwAAAA==.Manark:BAAALgAECgEJAgAAAA==.Mangtash:BAAALgAECgQJCQABLgAFFAEJAgAVAAAAAA==.Maozhuxi:BAAALgAECgQJBAAAAA==.Marvik:BAAALgAECgIJBAAAAA==.Masquerapet:BAACLgAFFH8eAAIJAAcJPhW0AQC1AQAJAAcJPhW0AQC1AQAuAAQKfy8AAgkACQkEIGIEAAYDAAkACQkEIGIEAAYDAAAA.',
Me='Megadeath:BAABLgAECn8eAAMNAAcJDBcrYwDKAQANAAcJDBcrYwDKAQAfAAEJkgFXGgAiAAAAAA==.Melondawize:BAAALgAFFAEJAQAAAA==.Meulah:BAAALgAECgcJBwABLgAECggJFQAQANocAA==.',
Mi='Miah:BAACLgAFFH8SAAIKAAcJ2BMtBACtAQAKAAcJ2BMtBACtAQAuAAQKfysAAgoACQl8IPQLACEDAAoACQl8IPQLACEDAAAA.Miao:BAACLgAFFH8PAAIBAAQJ1RPMDwATAQABAAQJ1RPMDwATAQAuAAQKfyIAAwEACQmzH9UMAB4CAAEACAm4H9UMAB4CABsAAQllCWGKAC4AAAEuAAUUBwkdABAADBkA.Miaomiaomiao:BAACLgAFFH8dAAIQAAcJDBnqAABXAgAQAAcJDBnqAABXAgAuAAQKfzAAAhAACQlHJjUAAOsDABAACQlHJjUAAOsDAAAA.Miaomiaorawr:BAACLgAFFH8LAAMLAAQJZw9XCADjAAAaAAQJVglCDgAqAQALAAMJrhFXCADjAAAuAAQKfx8AAxoABwmuGmIKAOgBABoABwlRGGIKAOgBAAsABgmhFdMyAHQBAAEuAAUUBwkdABAADBkA.Mightyz:BAABLgAECn8WAAIdAAcJFhTgCABMAQAdAAcJFhTgCABMAQAAAA==.Minamai:BAABLgAECn8fAAMLAAcJZhPpFABpAQALAAcJZhPpFABpAQAIAAMJowtjKgCuAAABLgAECggJHQABAGUWAA==.Mirrormaze:BAAALgADCgEJAQAAAA==.Mishougan:BAAALgADCgkJAgAAAA==.',
Mm='Mmfgh:BAAALgAFFAIJAgABLgAFFAcJIQACAJYlAA==.Mmjunior:BAAALgADCgIJAgAAAA==.',
Mo='Mollywhop:BAAALgADCgEJAQAAAA==.Monkthejohn:BAACLgAFFH8KAAIWAAQJoRkoBwBhAQAWAAQJoRkoBwBhAQAuAAQKfyYAAhYACQlwIjkGACMDABYACQlwIjkGACMDAAAA.Montise:BAAALgADCgQJBAAAAA==.Moongrass:BAAALgAECgYJEgAAAA==.Moontise:BAABLgAECn8cAAICAAcJhw/LdwCLAQACAAcJhw/LdwCLAQAAAA==.Moosemoose:BAAALgAECgUJBQAAAA==.Mousemarâ:BAABLgAECn8hAAIlAAgJbQ7nCwCqAQAlAAgJbQ7nCwCqAQAAAA==.Moñgo:BAABLgAECn8eAAMSAAgJohh0BgBkAgASAAgJohh0BgBkAgATAAIJyhJpkwBxAAAAAA==.',
Na='Nagaridar:BAAALgAECgYJAwAAAA==.Nanana:BAABLgAECn8XAAIGAAcJrhCalACqAQAGAAcJrhCalACqAQAAAA==.',
Ne='Necrobrew:BAABLgAECn8eAAIkAAYJnBvOEwBQAQAkAAYJnBvOEwBQAQABLgAFFAQJEQANACUbAA==.Necroticlol:BAACLgAFFH8RAAINAAQJJRuWFwBUAQANAAQJJRuWFwBUAQAuAAQKfy4AAg0ACQkwJVACALgDAA0ACQkwJVACALgDAAAA.Necroticlól:BAACLgAFFH8GAAIKAAMJ6wp7JADRAAAKAAMJ6wp7JADRAAAuAAQKfxAAAgoABgkMC/ZjAHsAAAoABgkMC/ZjAHsAAAEuAAUUBAkRAA0AJRsA.Neegu:BAAALgAFFAEJAQAAAA==.Neff:BAAALgAECggJDAAAAA==.Nefpore:BAAALgADCgQJBAAAAA==.Nehnehh:BAABLgAECn8mAAINAAgJxQ35KQCUAQANAAgJxQ35KQCUAQAAAA==.Neveress:BAABLgAECn8iAAIPAAcJUA1nCgCYAQAPAAcJUA1nCgCYAQAAAA==.',
Ni='Nigl:BAAALgADCgUJBgAAAA==.Niij:BAAALgAECgYJCgAAAA==.Nitox:BAABLgAECn8UAAIhAAYJKAncFQD1AAAhAAYJKAncFQD1AAAAAA==.',
No='Norrin:BAAALgAECgQJBAAAAA==.Noruid:BAAALgAECgYJAQABLgAECgkJEwAVAAAAAA==.Norvanish:BAAALgAECgcJDAABLgAECgkJEwAVAAAAAA==.Nosok:BAAALgAECgMJBgABLgAECgYJDgAVAAAAAA==.Notwithdeath:BAABLgAECn8hAAINAAgJyxLzIwCyAQANAAgJyxLzIwCyAQAAAA==.Nought:BAABLgAECn8hAAIKAAgJ7g23JgBOAQAKAAgJ7g23JgBOAQAAAA==.Novis:BAABLgAECn8nAAIWAAgJhiOOAgC1AgAWAAgJhiOOAgC1AgAAAA==.',
Nt='Nthope:BAAALgAFFAcJHgAAAQ==.Nthuntz:BAAALgAECgMJAwAAAA==.',
Nu='Nukz:BAAALgADCggJCAAAAA==.',
Od='Oddleif:BAAALgAECgUJCwAAAA==.Odyne:BAAALgADCgUJBQAAAA==.',
Oo='Oomowl:BAABLgAECn8sAAIQAAgJqSEgBgC2AgAQAAgJqSEgBgC2AgAAAA==.Oonnfire:BAAALgADCgcJBgAAAA==.',
Or='Orcgydecay:BAABLgAECn8dAAINAAgJuxsUOABWAgANAAgJuxsUOABWAgAAAA==.',
Os='Oscarr:BAABLgAFFH8GAAICAAMJnhY3HAAFAQACAAMJnhY3HAAFAQAAAA==.',
Pa='Palabean:BAAALgADCgcJBwAAAA==.Pamie:BAAALgAECgUJBQAAAA==.Pancitnoodle:BAAALgAECgYJBgABLgAECggJEgAVAAAAAA==.Paperplater:BAAALgAECgUJCQAAAA==.Parascribin:BAAALgAECgYJBgAAAA==.Paz:BAAALgAECgEJAQAAAA==.',
Pe='Peedles:BAAALgAECgcJDAAAAA==.Pennificent:BAACLgAFFH8FAAICAAMJwwfQGADlAAACAAMJwwfQGADlAAAuAAQKfxoAAgIACAn3FvQ0AE4CAAIACAn3FvQ0AE4CAAAA.Penta:BAAALgADCggJGAAAAA==.Percy:BAAALgAECgQJCAAAAA==.',
Ph='Phandrea:BAAALgAECgMJAwAAAA==.',
Pi='Pinkwink:BAAALgAECgMJAwAAAA==.',
Po='Pocketpie:BAAALgADCgYJBgAAAA==.Pog:BAACLgAFFH8PAAINAAUJ4CDrAgDcAQANAAUJ4CDrAgDcAQAuAAQKfxYAAg0ACQnGI0IgAMACAA0ACQnGI0IgAMACAAAA.Pohu:BAABLgAECn8UAAIDAAYJrhfQNACpAQADAAYJrhfQNACpAQAAAA==.Poros:BAAALgAECgcJEgABLgAECggJKgANAEkgAA==.Porosdk:BAABLgAECn8qAAINAAgJSSAPCwB0AgANAAgJSSAPCwB0AgAAAA==.Poroz:BAAALgAECgYJDwABLgAECggJKgANAEkgAA==.Poteb:BAAALgAECgQJBAAAAA==.Powerangers:BAAALgAECgMJBQAAAA==.Powercut:BAAALgAECgQJBwAAAA==.',
Pr='Prncesstata:BAAALgADCgEJAQAAAA==.Prodigal:BAACLgAFFH8LAAIgAAQJjQuRAQDxAAAgAAQJjQuRAQDxAAAuAAQKfyUAAiAACQk7CwENAIgBACAACQk7CwENAIgBAAAA.Protadiin:BAAALgAECgQJBAAAAA==.',
Pt='Pterion:BAAALgAFFAEJAQAAAA==.Pterionn:BAAALgADCgUJBQAAAA==.',
Pu='Pumba:BAAALgADCgYJBgAAAA==.Pumbz:BAABLgAECn8gAAQZAAgJyhzaHwBGAgAZAAYJ6B/aHwBGAgAcAAUJrxaDCgAoAQAeAAEJWA8AAAAAAAAAAA==.Punprepared:BAEBLgAECn8eAAMKAAgJnSU0BQBzAwAKAAgJnSU0BQBzAwAgAAYJjhg4BgBqAQAAAA==.',
Pw='Pweedoy:BAABLgAECn8bAAIKAAgJySMqBgB6AgAKAAgJySMqBgB6AgAAAA==.',
Qe='Qeb:BAACLgAFFH8YAAMmAAYJXyMlAAAMAgAmAAYJJCIlAAAMAgAlAAUJ7iHjAQDpAQAuAAQKfy8AAyUACQm/JVsAAOoDACUACQmGJVsAAOoDACYACQnBIHMCAP0BAAAA.Qeliss:BAAALgADCgEJAQAAAA==.Qezam:BAAALgAECgEJAQAAAA==.',
Qz='Qzzdh:BAAALgAECgEJAQAAAA==.',
['Qí']='Qíqi:BAAALgADCgYJBgAAAA==.',
Ra='Rainrain:BAAALgADCgYJBgABLgADCgcJBQAVAAAAAA==.Raluca:BAAALgADCgIJAgAAAA==.Rastianthrel:BAAALgADCgUJAgAAAA==.Ravenn:BAAALgAECgYJDAABLgAECgYJDAAVAAAAAA==.Razoxaynne:BAABLgAECn8UAAIRAAYJZAYQKQDBAAARAAYJZAYQKQDBAAAAAA==.',
Re='Recrute:BAAALgADCgcJBgABLgADCgcJCQAVAAAAAA==.Renesh:BAABLgAECn8rAAIDAAkJXRnpBwBdAgADAAkJXRnpBwBdAgAAAA==.Rerolling:BAAALgAECgQJCAAAAA==.Resolute:BAABLgAECn8WAAICAAYJdBjKYgC9AQACAAYJdBjKYgC9AQAAAA==.',
Ri='Richrump:BAAALgAECgEJAQAAAA==.Rightmind:BAAALgADCgIJAgAAAA==.Rimreaper:BAAALgAECgYJCQAAAA==.Riplilpeep:BAAALgADCgMJAwAAAA==.',
Ro='Rootwalker:BAAALgADCgYJBgAAAA==.Roshanx:BAAALgAECgIJAwAAAA==.Roughlly:BAAALgAECgMJAwAAAA==.',
Ru='Rualgathor:BAABLgAECn8ZAAMIAAcJ8hOnIADTAQAIAAcJ8hOnIADTAQAaAAIJcgJcUQBGAAAAAA==.Ruptured:BAABLgAECn8zAAMmAAgJYyTpAABGAwAmAAgJYyTpAABGAwAlAAEJaxaZXABAAAAAAA==.',
Ry='Rykiel:BAAALgAECgIJAgABLgAFFAUJDQAKAM4WAA==.Ryo:BAABLgAECn8gAAIKAAcJmCP+DAASAgAKAAcJmCP+DAASAgAAAA==.',
['Rï']='Rïsing:BAAALgADCgEJAQAAAA==.',
Sa='Sammy:BAAALgAECgMJBQABLgAECgcJEQAVAAAAAA==.Satria:BAAALgADCgcJCQAAAA==.',
Sc='Scarqúeen:BAAALgAECgIJAgABLgAECgIJAgAVAAAAAA==.Scott:BAAALgAECgQJBQAAAA==.',
Se='Senpei:BAAALgADCgMJAwABLgAECgMJAwAVAAAAAA==.Seraphize:BAABLgAECn8kAAMaAAkJNBjZAwCeAgAaAAkJyBXZAwCeAgALAAcJbxLwKgCdAQAAAA==.Seveneleven:BAAALgAECgUJBQABLgAFFAUJDgAEANQcAA==.',
Sh='Shadowboiz:BAAALgAECgQJBAAAAA==.Shalongbao:BAAALgAECgEJAQABLgAECgcJCQAVAAAAAA==.Shazarah:BAAALgAECgYJCAAAAA==.Shidann:BAACLgAFFH8YAAIRAAcJtSYMAAC0AgARAAcJtSYMAAC0AgAuAAQKfysAAhEACQn1JgoAABMEABEACQn1JgoAABMEAAAA.Shin:BAABLgAECn8gAAIKAAgJoh8EGQC+AgAKAAgJoh8EGQC+AgABLgAFFAcJGAARALUmAA==.Shintopal:BAAALgAECgYJCwAAAA==.Shions:BAAALgAECgMJAwAAAA==.Shirlik:BAAALgADCgcJBwAAAA==.Shneakypeach:BAAALgAECgYJCgAAAA==.',
Si='Sildriel:BAAALgAECgEJAQABLgAFFAEJAgAVAAAAAA==.Silentsnipe:BAAALgAECgEJAgAAAA==.Sillyshammy:BAAALgAECgcJCgAAAA==.Silverbow:BAAALgAECgIJAgAAAA==.Sinorph:BAACLgAFFH8HAAIhAAMJHguUBwDpAAAhAAMJHguUBwDpAAAuAAQKfygAAiEACQnVHmoFABgDACEACQnVHmoFABgDAAAA.',
Sl='Slappee:BAAALgAECgQJBQAAAA==.Slappuccino:BAABLgAECn8dAAIMAAgJlRspCAA0AgAMAAgJlRspCAA0AgAAAA==.Slug:BAAALgADCgUJBQAAAA==.',
Sm='Smalls:BAAALgAECgEJAQAAAA==.Smolpotato:BAABLgAECn8YAAMXAAcJaxNQDQBLAQAXAAcJaxNQDQBLAQATAAQJ4QJnhwCiAAABLgAFFAMJBwAhAB4LAA==.',
Sn='Snaketooth:BAAALgADCggJDQAAAA==.Sneakyitch:BAAALgAECgUJDQAAAA==.Snowflake:BAAALgADCgcJDgAAAA==.',
So='Soil:BAACLgAFFH8PAAIOAAUJlRqoAwDLAQAOAAUJlRqoAwDLAQAuAAQKfyoABA4ACAlVHGAMAG8CAA4ACAlVHGAMAG8CABQABAlbE/wqAL4AACMAAQnfBho/ADMAAAAA.Solstickan:BAAALgAECgYJBgAAAA==.Somedruid:BAAALgAECgYJBwABLgAECgcJFgAYANgXAA==.Somelock:BAAALgADCgcJDAABLgAECgcJFgAYANgXAA==.Somepally:BAABLgAECn8WAAIYAAcJ2BeKCACIAQAYAAcJ2BeKCACIAQAAAA==.Songfíre:BAAALgAECgEJAQAAAA==.',
Sp='Spartà:BAAALgAECgcJEQAAAA==.Spiras:BAAALgAECggJCQAAAA==.',
St='Stacksp:BAAALgAECggJCwAAAA==.Stan:BAACLgAFFH8UAAMZAAcJmiEsAAAZAgAZAAYJuiEsAAAZAgAcAAQJ8xIoEAAwAQAuAAQKfx4AAxwACQnvHyAIABsDABwACQn/GyAIABsDABkABgkDJEUaAMMBAAAA.Starbarks:BAAALgAECgQJBQAAAA==.Stealthunt:BAAALgADCgQJBAAAAA==.Stormscythe:BAAALgAECgYJEgAAAA==.Stormsét:BAAALgAFFAIJAgAAAA==.Stuntroast:BAABLgAECn8VAAIGAAYJ4h7zOgB+AQAGAAYJ4h7zOgB+AQAAAA==.',
Su='Sumdk:BAAALgAECgIJBAABLgAECgUJBgAVAAAAAA==.Sumguy:BAAALgAECgQJBwABLgAECgUJBgAVAAAAAA==.Superfly:BAAALgAECgQJCgAAAA==.Supermayhem:BAAALgAECgUJBwAAAA==.Supermortis:BAAALgADCgIJAgAAAA==.Sutiao:BAACLgAFFH8TAAIGAAUJFR/VBgDyAQAGAAUJFR/VBgDyAQAuAAQKfyoAAgYACAmvJR0LAGsDAAYACAmvJR0LAGsDAAAA.',
Sw='Swissarmy:BAAALgAECgIJBgAAAA==.Swissroll:BAAALgAECgIJAwAAAA==.Switchknife:BAABLgAECn8pAAQlAAkJnBv/BgAgAwAlAAkJnBv/BgAgAwAnAAIJ2w5XCgByAAAmAAEJ1wpEHwA2AAAAAA==.',
Sy='Synasta:BAACLgAFFH8HAAIEAAMJDA3HJADwAAAEAAMJDA3HJADwAAAuAAQKfx0AAwQACAm3IMUGAKECAAQACAm3IMUGAKECAAUAAQm6AWZ4ACsAAAAA.Systher:BAABLgAECn8WAAICAAgJ5A0LegCGAQACAAgJ5A0LegCGAQAAAA==.',
Ta='Tammys:BAAALgAECgUJBQABLgAECgcJDwAVAAAAAA==.Tanason:BAAALgAECgMJAwABLgAECgQJBgAVAAAAAA==.Tancs:BAAALgAECgUJCgAAAA==.Taurium:BAAALgAECgYJDAAAAA==.',
Te='Teaki:BAABLgAECn8UAAIGAAgJMRBcNQCQAQAGAAgJMRBcNQCQAQAAAA==.Teekz:BAABLgAECn8ZAAMBAAcJwhivHgBuAQABAAcJwhivHgBuAQAbAAQJaAzOYgC4AAAAAA==.Teloredrolor:BAAALgADCgEJAQAAAA==.Temperance:BAAALgADCgMJBAAAAA==.Temsik:BAAALgAECgEJAgAAAA==.',
Th='Thalloom:BAABLgAECn8VAAIXAAYJvhAoIQA2AQAXAAYJvhAoIQA2AQAAAA==.Thewaterboy:BAAALgAECgcJEwAAAA==.Thoth:BAACLgAFFH8JAAMEAAMJYhCILQDtAAAEAAMJYhCILQDtAAAFAAEJVAwXGABOAAAuAAQKfz0ABAUACAliIPQCAM4CAAUACAn1HfQCAM4CAA8ABwlzHmEDAGgCAAQABQkCHDAwAGoBAAAA.Thrallish:BAAALgAECgUJBQAAAA==.Thrayneqt:BAAALgADCgIJAgAAAA==.Threiann:BAAALgAECgcJEQAAAA==.Thrux:BAABLgAECn8jAAIGAAgJlhrdGgAKAgAGAAgJlhrdGgAKAgAAAA==.Thumpelina:BAAALgAECgYJEAAAAA==.Thura:BAAALgAECggJCwAAAA==.',
Ti='Tiddlyniblit:BAAALgAECgcJCAAAAA==.Tifa:BAAALgAECgUJBgAAAA==.Timei:BAABLgAECn8TAAQaAAcJdBN6JgBhAQAaAAcJOhB6JgBhAQALAAUJwwycTAAGAQAIAAQJGQUMLwCJAAAAAA==.',
To='Tommyh:BAACLgAFFH8OAAIIAAcJTBNrAQAYAgAIAAcJTBNrAQAYAgAuAAQKfyUAAggACQmAJXgAAOoDAAgACQmAJXgAAOoDAAAA.Toothdk:BAAALgAECgYJEwAAAA==.Topuzzible:BAAALgAECgQJBAABLgAECggJLQAZAMMjAA==.Torgaddon:BAAALgADCgMJAwAAAA==.Torress:BAAALgAECgIJAgAAAA==.',
Tr='Trianth:BAAALgAECgQJCQAAAA==.Tribbie:BAACLgAFFH8TAAMNAAUJvB11EwBiAQANAAQJvB11EwBiAQAJAAEJAACpIwAAAAAuAAQKfysAAw0ACAndI5QOACYDAA0ACAndI5QOACYDAB8AAQnDBGQZACkAAAAA.Trippinz:BAAALgADCgMJAwAAAA==.',
Tw='Twice:BAAALgAECgcJEwABLgAECggJKAAIAFQlAA==.Twizzle:BAAALgAECgQJCwAAAA==.Twljh:BAAALgAECgQJCgAAAA==.',
Ty='Tyraeel:BAAALgAECgEJAQABLgAFFAQJBQANAJYWAA==.Tyranadia:BAACLgAFFH8PAAINAAQJwRqrHwA8AQANAAQJwRqrHwA8AQAuAAQKfy4AAg0ACQnEIKUVAPoCAA0ACQnEIKUVAPoCAAAA.Tystus:BAAALgAECgEJAQAAAA==.',
Un='Unalive:BAAALgAFFAMJBAAAAA==.',
Up='Upstairs:BAAALgAECgcJCgABLgAFFAMJBQAOAIUOAA==.',
Va='Vaelyra:BAAALgAECgEJAQABLgAECgYJHwAhAPISAA==.Valdemar:BAAALgAECgYJDQAAAA==.Valefâr:BAAALgAECgEJBQAAAA==.Valiant:BAAALgAECgIJCAAAAA==.Varnoxx:BAACLgAFFH8OAAMNAAUJ8CNbCACYAQANAAQJ8CNbCACYAQAJAAEJAADCHAAAAAAuAAQKfygAAg0ACQnAItcKAEUDAA0ACQm/ItcKAEUDAAAA.',
Ve='Veinar:BAAALgAECgEJAQAAAA==.',
Vi='Vicioûs:BAABLgAECn8aAAMJAAgJowfEGgClAAANAAYJygS6wAACAQAJAAgJ2AbEGgClAAAAAA==.Viciðus:BAAALgAECgQJBwAAAA==.Violetteè:BAAALgAECgEJAgAAAA==.Vitamindee:BAAALgAECgYJDAAAAA==.',
Vl='Vl:BAAALgAECgEJAQABLgAECggJKAAIAFQlAA==.Vll:BAAALgAECgQJBwABLgAECggJKAAIAFQlAA==.',
Vo='Voidshock:BAAALgAECgQJBAAAAA==.Voltage:BAAALgADCgYJDAABLgAECgUJBgAVAAAAAA==.Vortex:BAAALgAECgkJEwAAAA==.',
Vu='Vulpareon:BAAALgADCgcJBwAAAA==.',
Vv='Vvoo:BAAALgADCgMJAwAAAA==.',
Vw='Vw:BAAALgAECggJCQABLgAECggJKAAIAFQlAA==.',
Wa='Wander:BAAALgAECgYJEwAAAA==.Wards:BAAALgADCgEJAQAAAA==.Wardz:BAAALgAECgYJDwAAAA==.Warmazo:BAAALgADCgUJBQAAAA==.Warmpanties:BAAALgADCgEJAQAAAA==.Watersports:BAAALgAECgkJBAAAAA==.Wazaldin:BAAALgADCgUJBQAAAA==.',
We='Weke:BAAALgADCgMJAwAAAA==.Wetpantees:BAAALgADCgEJAQAAAA==.',
Wh='Whiskas:BAAALgAECggJCgAAAA==.Whispess:BAABLgAECn8UAAIhAAYJcRqyDgBPAQAhAAYJcRqyDgBPAQAAAA==.',
Wi='Winnievoid:BAAALgAECgEJAgAAAA==.Wish:BAAALgAECgUJBQAAAA==.',
Wo='Woodro:BAAALgAFFAMJBAAAAA==.Wowsuchmage:BAAALgAECgcJCQAAAA==.',
Wt='Wtfoxsays:BAAALgAECgQJBwAAAA==.',
Wy='Wyrda:BAACLgAFFH8TAAIZAAQJhSUOAQC0AQAZAAQJhSUOAQC0AQAuAAQKf0AAAhkACQk6JX0AAF4DABkACQk6JX0AAF4DAAAA.',
['Wâ']='Wârlôrd:BAAALgADCgEJAQAAAA==.',
Xa='Xahara:BAAALgADCgcJBwAAAA==.',
Xi='Xiaomonks:BAACLgAFFH8OAAIMAAUJoR8mBgBqAQAMAAUJoR8mBgBqAQAuAAQKfygAAgwACAl+IocGAPUCAAwACAl+IocGAPUCAAAA.Xiaoputang:BAAALgADCgQJBAABLgAFFAUJDgAMAKEfAA==.Xiaosneaky:BAAALgAECgMJAwABLgAFFAUJDgAMAKEfAA==.',
Xt='Xtion:BAACLgAFFH8NAAMcAAUJdx3UCgDDAAAZAAIJXhpxIQDDAAAcAAQJjxrUCgDDAAAuAAQKfyYAAxwACQkgIE8LAPECABwACQkOH08LAPECABkABQmiHPgZAMUBAAAA.',
['Xì']='Xìn:BAAALgAECgcJCQAAAA==.',
Ya='Yagnatia:BAAALgADCgIJAgAAAA==.',
Yi='Yiffie:BAABLgAECn8YAAIMAAYJsyPiCAAiAgAMAAYJsyPiCAAiAgABLgAECggJHwADAGclAA==.Yinz:BAAALgAECgYJBwABLgAECgQJBwAVAAAAAA==.',
Yl='Ylaena:BAAALgADCgMJAwAAAA==.',
Yo='Yongbok:BAABLgAECn8UAAIFAAYJGwMpEgCYAAAFAAYJGwMpEgCYAAAAAA==.',
Yr='Yrano:BAAALgAECgYJCAAAAA==.',
Yv='Yva:BAAALgAECgkJDgAAAA==.',
Za='Zana:BAAALgAECgMJAwAAAA==.Zaraxes:BAAALgAECggJEQAAAA==.',
Ze='Zelgaira:BAAALgAECgYJBgAAAA==.Zelvaris:BAACLgAFFH8YAAInAAcJMh0HAABGAgAnAAcJMh0HAABGAgAuAAQKfysAAicACQlbJRIAANgDACcACQlbJRIAANgDAAAA.Zerkerman:BAAALgAECgIJAgAAAA==.',
Zi='Zipo:BAAALgADCgUJBAABLgAECggJGQAoAOoZAA==.Zips:BAABLgAECn8ZAAQoAAcJ6hknDAADAgAoAAcJ6hknDAADAgABAAcJzBULMgC9AQAbAAIJEhgJcwB2AAAAAA==.',
Zu='Zucc:BAAALgAECgYJCgAAAA==.',
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

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

local lookup = {'Shaman-Restoration','Paladin-Retribution','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Arcane','Priest-Shadow','DeathKnight-Blood','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','Warlock-Affliction','Druid-Restoration','Druid-Balance','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','Unknown-Unknown','Monk-Brewmaster','Warrior-Protection','Paladin-Protection','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abcede:BAAALgAECgIJAgABLgAECggJGQABAN8VAA==.',
Ac='Achillguy:BAAALgADCgYJBgAAAA==.',
Ae='Aelene:BAABLgAECn8hAAMCAAkJ/Q7BbQCiAQACAAgJpA3BbQCiAQADAAcJxA4TOACaAQAAAA==.Aelthryn:BAAALgADCgEJAQAAAA==.Aetrix:BAAALgADCgQJBAAAAA==.',
Ag='Agonybehold:BAAALgADCgkJCQAAAA==.Agrolloch:BAAALgAECgYJCgAAAA==.',
Ah='Ahgain:BAAALgAFFAEJAQAAAA==.Ahino:BAAALgADCgkJHQAAAA==.',
Ai='Aica:BAAALgAECgEJAQABLgAFFAYJFwAEAIkdAA==.Aisa:BAACLgAFFH8XAAMEAAYJiR2sAADZAQAEAAYJoBusAADZAQAFAAMJsCAuBQAlAQAuAAQKfywAAwQACQmpJfwAAM0DAAQACQmJJfwAAM0DAAUABgmuJQoFAIsCAAAA.Aish:BAACLgAFFH8ZAAICAAYJLSZZAACbAgACAAYJLSZZAACbAgAuAAQKfyMAAgIACQlnJvoAAN4DAAIACQlnJvoAAN4DAAAA.',
Al='Aldofio:BAAALgAECgQJAwAAAA==.Alenhall:BAAALgAECgYJCgAAAA==.Aleson:BAABLgAECn8WAAMGAAYJ+AMP/wD9AAAGAAYJ+AMP/wD9AAAHAAQJ0gDeGQBJAAAAAA==.Alexgreece:BAAALgAECgYJBgABLgAFFAYJDgAIAGUWAA==.Alirann:BAAALgAECgQJBAAAAA==.Aljoumeiro:BAABLgAECn8aAAIJAAgJEBhUDQA5AgAJAAgJEBhUDQA5AgAAAA==.Alvln:BAACLgAFFH8MAAIKAAUJmBVjBQBRAQAKAAUJmBVjBQBRAQAuAAQKfx0AAgoACAlUHMUpAFoCAAoACAlUHMUpAFoCAAAA.',
Am='Amarasha:BAAALgADCgUJAQAAAA==.',
An='Andyrios:BAAALgAECgYJCQAAAA==.Aniki:BAAALgAECgkJEwAAAA==.',
Ap='Apathy:BAAALgAECgYJBwAAAA==.Apothecary:BAAALgADCgUJCAAAAA==.',
Ar='Arahat:BAAALgAECgIJAgAAAA==.Arakk:BAABLgAECn8XAAIKAAgJ1BRzYAB/AQAKAAgJ1BRzYAB/AQAAAA==.Aralinya:BAACLgAFFH8LAAILAAQJMRYxBABGAQALAAQJMRYxBABGAQAuAAQKfycAAwsACQnbGtcKAKECAAsACQnbGtcKAKECAAgAAQmwBxBjADIAAAAA.Arasenpai:BAAALgAECggJCgAAAA==.Ardentflame:BAABLgAECn8YAAIEAAcJ5RRJUgDRAQAEAAcJ5RRJUgDRAQAAAA==.Arleric:BAAALgADCgkJEgAAAA==.Arlerknight:BAAALgADCgYJBgAAAA==.Arlermage:BAAALgADCgUJBwAAAA==.Arrine:BAAALgAECgEJAQAAAA==.Artpop:BAAALgAECgMJAgABLgAFFAQJDAAMANAUAA==.',
As='Asiris:BAAALgAECgIJAgAAAA==.Asperonia:BAACLgAFFH8XAAIDAAYJoRs7AQANAgADAAYJoRs7AQANAgAuAAQKfywAAwMACQlyJUECAFkDAAMACAlJJUECAFkDAAIAAQlvJLoWAWoAAAAA.Aster:BAAALgAFFAEJAQABLgAFFAUJDAAKAJgVAA==.Asteriøn:BAAALgADCgUJBQAAAA==.Astinous:BAAALgAECgEJBAAAAA==.Astral:BAAALgAECgcJDwAAAA==.Astrid:BAACLgAFFH8RAAINAAUJvRvdAADiAQANAAUJvRvdAADiAQAuAAQKfxoAAg0ACAmuHekKAIYCAA0ACAmuHekKAIYCAAAA.',
At='Ataraxia:BAAALgAECgYJEgAAAA==.',
Au='Ausdemonic:BAAALgAECgQJDQAAAA==.',
Av='Avell:BAABLgAECn8dAAIDAAgJYiXXBQAOAwADAAgJYiXXBQAOAwAAAA==.Avocardio:BAAALgAECgQJCwAAAA==.',
Ax='Axiomatic:BAACLgAFFH8GAAMFAAQJ4wIPDwCJAAAEAAMJoAO7GwCSAAAFAAIJhgAPDwCJAAAuAAQKfywABAQACQmhHdASAOUCAAQACQlpHNASAOUCAAUABgkkFvMTAKsBAA4AAgmaFuMZAKkAAAAA.',
Az='Azsharia:BAAALgAECgIJAgAAAA==.Azzielliea:BAAALgAECggJEwAAAA==.',
Ba='Babytroll:BAABLgAECn8XAAMPAAkJ1QbvfwDaAAAPAAgJEAPvfwDaAAAQAAEJmwGOjgAeAAAAAA==.Badds:BAABLgAECn8gAAIPAAgJIxvOGgBkAgAPAAgJIxvOGgBkAgAAAA==.Barleybrew:BAAALgADCgYJBgAAAA==.Battletank:BAABLgAECn8ZAAMRAAgJexJjDADaAQARAAgJexJjDADaAQASAAYJjwtTXAA+AQABLgAFFAUJDAAKAJgVAA==.',
Be='Beefchar:BAAALgAECgQJDAAAAA==.Beefpalmy:BAAALgAECgEJAQAAAA==.Beefybone:BAAALgADCgcJBAAAAA==.Beerofftap:BAAALgAECgUJCgAAAA==.Belalugosi:BAAALgAECgYJEQAAAA==.Bethc:BAAALgAECgYJCgAAAA==.Betray:BAABLgAECn8ZAAIGAAgJTxoGOgCOAgAGAAgJTxoGOgCOAgAAAA==.Beàr:BAAALgAECgYJDwAAAA==.',
Bi='Bielobog:BAAALgAECgQJBAAAAA==.Bigbadbaka:BAACLgAFFH8VAAMSAAYJ9yDvAAAFAgASAAUJ4SPvAAAFAgARAAUJYRqsAADKAQAuAAQKfyYAAxIACQnrJMwBAKwDABIACQnrJMwBAKwDABEACQktHGsBADkDAAAA.Bigsimón:BAAALgAECgQJBAAAAA==.Bink:BAAALgAECgQJBQAAAA==.Biscuitpaw:BAAALgADCggJFQAAAA==.Bizz:BAAALgAECgUJBgAAAA==.',
Bl='Blackwind:BAABLgAECn8XAAIIAAYJPR5uJwCdAQAIAAYJPR5uJwCdAQAAAA==.Bladeripper:BAAALgADCgYJBgAAAA==.Blazez:BAACLgAFFH8FAAICAAQJNxgJFQABAQACAAQJNxgJFQABAQAuAAQKfyUAAgIACQmOIG0JAEUDAAIACQmOIG0JAEUDAAAA.',
Bo='Bogart:BAACLgAFFH8LAAMEAAQJ1BwPDgBrAQAEAAQJ1BwPDgBrAQAOAAEJSQm2AQBTAAAuAAQKfycAAgQACQlgI+ACAJUDAAQACQlgI+ACAJUDAAAA.Bomohdh:BAACLgAFFH8JAAIKAAQJzBXEDwBQAQAKAAQJzBXEDwBQAQAuAAQKfysAAgoACQmjIS4GAGMDAAoACQmjIS4GAGMDAAAA.Boogeymayne:BAAALgAECgMJAwAAAA==.',
Br='Braeburn:BAAALgAECgEJAgAAAA==.Brawny:BAAALgAECgQJBAAAAA==.Brevren:BAABLgAECn8WAAITAAcJeR85QAA3AgATAAcJeR85QAA3AgAAAA==.Brewtality:BAAALgAECgEJAQAAAA==.Brexan:BAAALgADCgcJFQAAAA==.Brüder:BAAALgADCgEJAQABLgAECgUJBQAUAAAAAA==.',
Bu='Buibuis:BAABLgAFFH8FAAIVAAUJLxUeBQCDAQAVAAUJLxUeBQCDAQABLgAFFAYJDAAWAKoaAA==.Buikia:BAABLgAFFH8MAAIWAAYJqhqSAACzAQAWAAYJqhqSAACzAQAAAA==.Buysfeetpics:BAACLgAFFH8SAAIGAAYJKhkKBQAXAgAGAAYJKhkKBQAXAgAuAAQKfywAAgYACQkkJe4CANADAAYACQkkJe4CANADAAAA.',
['Bâ']='Bânê:BAABLgAECn8bAAIXAAgJiSSCAgAMAwAXAAgJiSSCAgAMAwAAAA==.',
Ca='Cannicus:BAACLgAFFH8RAAMGAAYJQhjuAwA0AgAGAAYJQhjuAwA0AgAHAAIJiRHIAACqAAAuAAQKfywAAwYACQlnJj0CANoDAAYACQk0Jj0CANoDAAcABwnRJC0CAIMCAAAA.Careshield:BAAALgAECgcJDgABLgAFFAUJDAAKAJgVAA==.Careßear:BAAALgAFFAEJAQABLgAFFAYJDQANAPYRAA==.Caridee:BAAALgAECgQJCwAAAA==.Cavoker:BAAALgADCgEJAQAAAA==.',
Ce='Celavii:BAABLgAECn8VAAIYAAgJtxJsLgD4AQAYAAgJtxJsLgD4AQAAAA==.',
Ch='Chappell:BAAALgAECgQJBAAAAA==.Chargeplox:BAAALgAECgYJDAAAAA==.Cherrybelles:BAABLgAECn8YAAQZAAgJ7xslJAByAQAZAAgJ7xslJAByAQAIAAQJpw4cRADbAAALAAEJFA1LfAA3AAAAAA==.Chiihiro:BAAALgAECgEJAgAAAA==.Chillicheese:BAAALgADCgMJAwAAAA==.Chinnohoho:BAABLgAECn8gAAIYAAgJkyGvDQDRAgAYAAgJkyGvDQDRAgAAAA==.Chinnozoic:BAAALgADCgIJAgAAAA==.Chokobo:BAACLgAFFH8PAAIQAAUJVxdJBACoAQAQAAUJVxdJBACoAQAuAAQKfyQAAxAACAkZI7QMAM0CABAACAkZI7QMAM0CAA8AAwnVGBycAJMAAAAA.Chunkz:BAAALgAECgQJBAAAAA==.',
Ci='Cindermoon:BAAALgADCgkJDQAAAA==.Cinema:BAAALgADCggJCAABLgAFFAQJBwAXAI4NAA==.',
Co='Colena:BAAALgAECgYJCAAAAA==.Comai:BAAALgADCgcJBwABLgAFFAQJBwAaABsRAA==.Conquest:BAABLgAECn8WAAMQAAYJEAx/QwAhAQAQAAYJEAx/QwAhAQAPAAYJTwZxgADZAAAAAA==.Corbulus:BAABLgAECn8ZAAICAAgJBxlrEQCYAQACAAgJBxlrEQCYAQAAAA==.Cowboytridda:BAAALgAECgIJAgAAAA==.',
Cr='Crispyarrowz:BAAALgAECggJEAAAAA==.Crispymage:BAAALgAECggJCQABLgAECggJEAAUAAAAAA==.Cronus:BAABLgAECn8mAAMYAAgJZiX+BgAfAwAYAAgJZiX+BgAfAwAbAAYJ7hSxOQB5AQAAAA==.Crsd:BAAALgADCgQJCAABLgAFFAEJAQAUAAAAAA==.',
Cy='Cyndi:BAAALgAECgYJDgAAAA==.',
Da='Dad:BAAALgAECgIJAgAAAA==.Dahlee:BAABLgAECn8ZAAINAAgJmgzZHgCJAQANAAgJmgzZHgCJAQAAAA==.Dahyunn:BAAALgAECgkJBQAAAA==.Daice:BAACLgAFFH8FAAIcAAMJPgbkAgDvAAAcAAMJPgbkAgDvAAAuAAQKfxoAAhwACAn3Fm0IAGMCABwACAn3Fm0IAGMCAAAA.Darcious:BAAALgAECgYJEQABLgAECggJFQAYALcSAA==.Darkcinders:BAAALgADCgkJEQAAAA==.Darkxeno:BAABLgAECn8YAAMTAAcJWRMHdACfAQATAAcJWRMHdACfAQAdAAIJBg6JCABCAAAAAA==.Daydreamer:BAAALgAECgUJBQABLgAECggJHQADAIsiAA==.',
De='Deadlly:BAABLgAECn8gAAIXAAgJfhkbCABZAgAXAAgJfhkbCABZAgAAAA==.Deadz:BAAALgAECgQJBAAAAA==.Dearest:BAAALgADCgMJAwAAAA==.Deathbybelf:BAAALgAECgQJCAAAAA==.Deathchup:BAAALgAECgkJAwAAAA==.Deathdemons:BAAALgAECgEJAQABLgAFFAEJAgAUAAAAAA==.Deathlink:BAAALgAECgMJBgAAAA==.Deathmonks:BAAALgAECgEJAQABLgAFFAEJAgAUAAAAAA==.Deathrocks:BAAALgAFFAEJAgAAAA==.Demöníc:BAACLgAFFH8HAAIKAAMJ7RSkGgD7AAAKAAMJ7RSkGgD7AAAuAAQKfzcAAwoACAmVJG4MAB0DAAoACAmVJG4MAB0DAB4AAwm/F0wYANwAAAAA.Deplock:BAAALgAECgQJBgABLgAECggJGQATAOAZAA==.Destwind:BAABLgAECn8vAAIMAAgJxCP+AwAyAwAMAAgJxCP+AwAyAwAAAA==.',
Di='Dirtypapa:BAAALgAECgUJCQAAAA==.Divïne:BAABLgAECn8WAAQCAAgJuRrcSQAFAgACAAgJ6xfcSQAFAgAXAAMJ1BYuJwDPAAADAAEJ8AOHkQA6AAAAAA==.',
Do='Doeji:BAAALgAECgkJBgAAAA==.Dotdotseckz:BAAALgADCgcJBwABLgAECggJKgACAEYZAA==.',
Dr='Dracdoy:BAAALgAECggJAwABLgAECggJFAAKAEQgAA==.Drackor:BAAALgAECgEJAQAAAA==.Dragonboar:BAAALgADCgUJBQAAAA==.Dragos:BAAALgAECgkJCQAAAA==.Dreadnok:BAAALgAECgQJBAAAAA==.Drethalis:BAAALgADCggJFAAAAA==.Drewstormio:BAAALgAECgQJBgAAAA==.',
Ds='Dsdh:BAACLgAFFH8LAAIKAAcJTBJ1BADqAQAKAAcJTBJ1BADqAQAuAAQKfysAAwoACQk8JQsEAIgDAAoACQnuJAsEAIgDAB8ABwniGX0cAN0BAAAA.',
Du='Dulang:BAABLgAFFH8GAAIYAAMJPhKPCwAGAQAYAAMJPhKPCwAGAQAAAA==.',
['Dé']='Déáth:BAAALgAECgUJBgAAAA==.',
Ec='Ectruby:BAACLgAFFH8GAAIgAAQJ7wXpAAAoAQAgAAQJ7wXpAAAoAQAuAAQKfycAAyAACQkvGgAEAOcCACAACQkvGgAEAOcCABAAAQllDnV9ADYAAAAA.',
Eg='Eg:BAAALgAECgIJAQAAAA==.',
Ej='Ejae:BAABLgAFFH8GAAIKAAQJ0wK5DgDlAAAKAAQJ0wK5DgDlAAABLgAFFAYJDQAYAEobAA==.',
El='Elagrom:BAABLgAECn8VAAIaAAYJBQ8WSAAnAQAaAAYJBQ8WSAAnAQAAAA==.Elertricsoup:BAAALgAECgYJDgAAAA==.Elladea:BAAALgAECgQJBQAAAA==.Ellieakita:BAAALgADCgUJBgAAAA==.Elwarlocko:BAABLgAECn8gAAMEAAgJvh+fBgAJAgAEAAYJqyCfBgAJAgAFAAUJ0xeZGwBwAQAAAA==.Elwhy:BAAALgAFFAIJBAAAAA==.Elyndre:BAACLgAFFH8NAAMNAAYJ9hErAgCIAQANAAUJTQ8rAgCIAQAhAAEJHBKfDwBiAAAuAAQKfxoABA0ACAklGREYANQBAA0ABwlBFxEYANQBACEABwkmIqopAHEBACIAAQlnFm88ADwAAAAA.',
Em='Emberis:BAAALgAECgEJAQAAAA==.',
En='Endari:BAAALgAFFAQJBAAAAA==.Endris:BAAALgADCgUJCQAAAA==.',
Er='Erikk:BAACLgAFFH8TAAIKAAYJPhCQBQDOAQAKAAYJPhCQBQDOAQAuAAQKfywAAgoACQmTIGcIAEcDAAoACQmTIGcIAEcDAAAA.Eru:BAAALgAECgcJEQAAAA==.',
Es='Escher:BAAALgAECgUJBQAAAA==.Espresso:BAABLgAECn8VAAMBAAgJGA2PNQCtAQABAAgJGA2PNQCtAQAaAAYJaAkfTgAOAQABLgAFFAYJDwARAJoVAA==.',
Ev='Evanlyn:BAAALgADCgEJAgABLgAECgYJCgAUAAAAAA==.',
Ex='Excelfron:BAAALgAECgYJDAAAAA==.',
Ey='Eyanos:BAAALgAECgcJCAAAAA==.',
Fa='Famine:BAABLgAECn8ZAAMTAAgJ4BnBPgA9AgATAAgJ4BnBPgA9AgAJAAEJzwRDFQArAAAAAA==.Fatzreaver:BAABLgAECn8YAAITAAgJEgnMegCOAQATAAgJEgnMegCOAQAAAA==.',
Fe='Fearran:BAAALgADCgcJCAAAAA==.Fenrith:BAAALgADCgMJAwAAAA==.',
Ff='Ffdeathpunch:BAAALgADCgUJBQABLgAECggJFgATAHkfAA==.Ffen:BAAALgAECgcJCAAAAA==.',
Fi='Fibanocci:BAAALgAECgEJAQABLgAECgcJCAAUAAAAAA==.Fired:BAAALgADCgcJCQAAAA==.',
Fl='Flamerage:BAAALgAECggJCAAAAA==.Flogarcus:BAAALgAECgQJBQAAAA==.',
Fr='Frankadelic:BAABLgAECn8YAAIbAAYJ3xOlBQAnAQAbAAYJ3xOlBQAnAQAAAA==.Frodolol:BAACLgAFFH8QAAIGAAUJ6x4MCADiAQAGAAUJ6x4MCADiAQAuAAQKfyEAAgYACQmFJLQIAIEDAAYACQmFJLQIAIEDAAAA.Frogwash:BAAALgADCgcJBwAAAA==.Frostik:BAABLgAFFH8HAAMdAAMJPx7WAAAaAQAdAAMJPx7WAAAaAQATAAIJ6AxmRQCZAAAAAA==.Frostyfruit:BAABLgAECn8gAAIGAAgJjx02CAAlAgAGAAgJjx02CAAlAgAAAA==.Frozenhell:BAABLgAECn8eAAIGAAgJnRQSZgALAgAGAAgJnRQSZgALAgAAAA==.',
Fu='Fufamace:BAAALgADCgYJBgAAAA==.Fufina:BAAALgAECgMJBQAAAA==.',
Fw='Fwoopie:BAAALgAECgcJAwABLgAECggJFwAZANUgAA==.Fwooplin:BAABLgAECn8XAAMZAAgJ1SAyAwATAgAZAAUJayQyAwATAgAIAAYJQR3ZGwD+AQAAAA==.',
Fy='Fya:BAAALgAECgcJDwAAAA==.',
['Fó']='Fóx:BAAALgADCgkJDQAAAA==.',
Ga='Gannina:BAACLgAFFH8HAAIjAAMJkhBsCADvAAAjAAMJkhBsCADvAAAuAAQKfx0AAiMACQnnIQwHAA4DACMACQnnIQwHAA4DAAAA.',
Ge='Georgecloney:BAAALgADCgcJBwABLgAECgkJIAARAA8VAA==.',
Gi='Gillemon:BAAALgAECgMJAwAAAA==.Gizzy:BAAALgAECgQJBAAAAA==.',
Go='Goblincave:BAABLgAECn8aAAIaAAgJCyChDQDHAgAaAAgJCyChDQDHAgAAAA==.Goodra:BAAALgAFFAEJAQABLgAFFAUJDAAKAJgVAA==.Goodwill:BAABLgAECn8mAAMYAAgJwyMTAgCRAgAbAAgJyB4HEQCwAgAYAAgJzyETAgCRAgAAAA==.',
Gr='Graoul:BAACLgAFFH8FAAIMAAMJwgybDADbAAAMAAMJwgybDADbAAAuAAQKfyMAAgwACAlyIAcJAMQCAAwACAlyIAcJAMQCAAAA.Greatpals:BAAALgAECgUJCQAAAA==.Grindelwald:BAAALgAECgUJCgAAAA==.Grisance:BAAALgADCgcJBwAAAA==.Gryffin:BAABLgAECn8eAAIIAAgJ1xGXBQC0AQAIAAgJ1xGXBQC0AQAAAA==.',
Gt='Gtamage:BAAALgADCggJCAAAAA==.',
Gu='Gugudan:BAAALgAECgcJEAAAAA==.Guh:BAAALgAECgYJDQAAAA==.Guiltyclown:BAABLgAECn8mAAIVAAgJESBkAgAyAgAVAAgJESBkAgAyAgAAAA==.Gummyworms:BAAALgAECgEJAQAAAA==.Gunnina:BAAALgAECgcJCQAAAA==.Gutsc:BAAALgAECgUJDwAAAA==.Gutt:BAAALgADCgEJAQABLgADCgIJAgAUAAAAAA==.Gutts:BAAALgAECgQJDgAAAA==.Guzzan:BAAALgAECgQJBAAAAA==.',
['Gû']='Gûilty:BAAALgADCgcJBwAAAA==.',
Ha='Hammerboltie:BAAALgAECgcJCAAAAA==.Hamuchivt:BAAALgAECgYJEQAAAA==.Haoso:BAAALgADCgUJBQAAAA==.Haravell:BAAALgADCgEJAQAAAA==.Harmony:BAAALgAECgQJBAAAAA==.Haroze:BAAALgAFFAIJAgAAAA==.Hawkaye:BAAALgADCgMJAwAAAA==.Haydos:BAAALgAECgQJBAAAAA==.',
He='Helios:BAAALgADCgkJDgAAAA==.Hemloque:BAAALgAECgIJAgAAAA==.Hershéy:BAABLgAECn8gAAIPAAgJLyGRCQD6AgAPAAgJLyGRCQD6AgAAAA==.Hert:BAAALgAECgMJAwAAAA==.',
Ho='Hothotseckz:BAABLgAECn8qAAMCAAgJRhmuCAD/AQACAAgJRhmuCAD/AQADAAUJEQ/7WwANAQAAAA==.',
Hu='Hurricanebom:BAAALgAECgMJAwAAAA==.',
Hy='Hypervoltage:BAAALgAECgYJEAAAAA==.Hyve:BAAALgAECggJBQAAAA==.',
Ia='Ial:BAABLgAECn8YAAIIAAgJ9iT/AwBZAwAIAAgJ9iT/AwBZAwABLgAECggJHQADAIsiAA==.',
Ic='Icysun:BAAALgAECgYJCAAAAA==.',
Im='Imnotacat:BAAALgAECgMJBAAAAA==.Imnotholy:BAABLgAECn8dAAIDAAgJiyIqAQDLAgADAAgJiyIqAQDLAgAAAA==.Imthebaglady:BAAALgAECgkJAgAAAA==.',
In='Invaderbull:BAABLgAECn8eAAMSAAYJdxIBTwBrAQASAAYJdxIBTwBrAQARAAQJxAdXFQAyAAAAAA==.',
Is='Isatarp:BAABLgAECn8cAAIbAAgJdB/YDQDSAgAbAAgJdB/YDQDSAgABLgAFFAYJFwAEAIkdAA==.Isee:BAAALgADCgYJCQAAAA==.Ish:BAAALgAECgkJAwAAAA==.Isopod:BAAALgAECgYJBwAAAA==.Isvelte:BAAALgAECggJBAABLgAFFAUJDQAEADQaAA==.Isyldia:BAAALgAECgkJDwAAAA==.',
Iv='Ivee:BAAALgAECgQJCAAAAA==.',
Ja='Jakhoul:BAAALgADCgQJBAAAAA==.Janlul:BAABLgAECn8WAAIYAAgJ+BibIQA8AgAYAAgJ+BibIQA8AgAAAA==.Jasmean:BAACLgAFFH8HAAMYAAMJdyUfBABEAQAYAAMJdyUfBABEAQAbAAIJAA78HgCaAAAuAAQKfycABBsACQkoJKoNANUCABsACAnTIaoNANUCABgABQnTI6cVAE4BABwAAQnUFCwSAEsAAAAA.Jaxxyn:BAABLgAECn8XAAMdAAYJ+R0XBQD0AQAdAAYJ+R0XBQD0AQATAAQJfhNi0ADhAAAAAA==.',
Je='Jennatelia:BAABLgAECn8UAAITAAgJFxAPDQC2AQATAAgJFxAPDQC2AQAAAA==.',
Jo='Jodric:BAAALgADCgcJDQAAAA==.Johnevoker:BAACLgAFFH8FAAINAAMJhQ7BBQDmAAANAAMJhQ7BBQDmAAAuAAQKfxkABA0ACAnhDkgZAMUBAA0ACAnhDkgZAMUBACIAAwlaCDkyAIQAACEAAQndAURpACMAAAAA.Johnthefury:BAAALgADCgQJBAABLgAFFAMJBQANAIUOAA==.Jombii:BAAALgAECgMJAQAAAA==.Jordoom:BAAALgAECgQJBAAAAA==.',
Ka='Kafra:BAABLgAECn8UAAIPAAgJ2hwbEAC3AgAPAAgJ2hwbEAC3AgAAAA==.Kamazira:BAAALgAECgYJCwAAAA==.Kariiyon:BAAALgAECgYJDgAAAA==.Katalen:BAAALgAECgMJBAAAAA==.Kayapau:BAACLgAFFH8NAAIaAAUJag5/BgByAQAaAAUJag5/BgByAQAuAAQKfyEAAxoACAnnHMQfABECABoACAnnHMQfABECAAEABglVDotXACkBAAAA.',
Ke='Kerìnne:BAAALgAECgIJAgAAAA==.Kevd:BAABLgAECn8yAAIPAAcJoCErEgCkAgAPAAcJoCErEgCkAgABLgAFFAYJJwABAAAkAA==.Kevin:BAACLgAFFH8nAAIBAAYJACQKAABuAgABAAYJACQKAABuAgAuAAQKfzAAAwEACQknJjEAAN0DAAEACQknJjEAAN0DABoAAQmyDZKHADIAAAAA.',
Kh='Khaii:BAACLgAFFH8LAAIGAAQJuCHxAwCGAQAGAAQJuCHxAwCGAQAuAAQKfycAAwYACQnNJioBAO8DAAYACQnNJioBAO8DAAcAAQm2JXwEAHEAAAAA.',
Ki='Kizen:BAAALgADCgMJAwAAAA==.',
Kj='Kj:BAAALgAECgUJBQABLgAFFAUJDwAkAE8fAA==.',
Ko='Komai:BAACLgAFFH8HAAIaAAQJGxFmDAAnAQAaAAQJGxFmDAAnAQAuAAQKfycAAxoACQlFIToJAP4CABoACQlFIToJAP4CAAEACAlQHoUVAGkCAAAA.Kopikia:BAABLgAECn8aAAMKAAkJcRKWMAA5AgAKAAkJcRKWMAA5AgAfAAYJwgUtPgAEAQAAAA==.Kora:BAAALgADCgUJBAAAAA==.',
Kp='Kpôp:BAAALgAECgcJCQAAAA==.',
Kr='Krosis:BAABLgAECn8hAAIMAAgJXhjYEQBEAgAMAAgJXhjYEQBEAgAAAA==.Kru:BAACLgAFFH8MAAMTAAUJMg5tEQDlAAATAAQJMg5tEQDlAAAJAAEJAACcDAAAAAAuAAQKfyAAAhMACAm5I/MQABYDABMACAm5I/MQABYDAAAA.Krucify:BAAALgAECggJDwAAAA==.Kruukk:BAABLgAECn8YAAIcAAgJDhMACwAlAgAcAAgJDhMACwAlAgAAAA==.',
Kt='Ktd:BAAALgAECgcJCQABLgAFFAMJCAAEADYZAA==.Ktl:BAACLgAFFH8IAAIEAAMJNhmSHQAOAQAEAAMJNhmSHQAOAQAuAAQKfx0AAwQACAkOH00eAKECAAQACAlzHU0eAKECAAUAAgnQIrELAGYAAAAA.Ktz:BAAALgADCgYJBgABLgAFFAMJCAAEADYZAA==.',
Ku='Kueipeh:BAAALgAECgIJAgAAAA==.Kulak:BAAALgADCgMJAwAAAA==.Kungfufa:BAAALgAECgIJAgAAAA==.Kuroski:BAAALgADCggJDwAAAA==.',
Ky='Kyall:BAABLgAECn8xAAIfAAkJaR56CQDKAgAfAAkJaR56CQDKAgAAAA==.Kyrisa:BAAALgADCgIJAgAAAA==.Kyrâ:BAAALgADCgUJBQAAAA==.',
La='Lacktoes:BAAALgAECgQJBAAAAA==.Lafret:BAABLgAECn8UAAIPAAYJShk7PACzAQAPAAYJShk7PACzAQAAAA==.Lamerzz:BAAALgAECgUJEQAAAA==.',
Le='Legôlas:BAAALgADCgEJAQAAAA==.Lettuce:BAABLgAECn8eAAIQAAkJah1/BwAeAwAQAAkJah1/BwAeAwAAAA==.Lexianna:BAAALgADCgQJBQAAAA==.',
Lh='Lh:BAAALgADCgcJBQAAAA==.',
Li='Liquidsnake:BAAALgADCgMJBAAAAA==.Liquidvoid:BAABLgAECn8iAAILAAgJNyHcAADTAgALAAgJNyHcAADTAgAAAA==.Littlehill:BAAALgAECgEJAQAAAA==.',
Lo='Lockley:BAAALgAECgIJAwAAAA==.Lokomoco:BAAALgAECggJDgAAAA==.Lolcarni:BAAALgADCgEJAwAAAA==.Loneboi:BAAALgAECgEJAQAAAA==.Loom:BAAALgADCgEJAgAAAA==.Lorellon:BAAALgAECgEJAgAAAA==.Lowcarbbeer:BAAALgAECgEJAQAAAA==.',
Lu='Lupercal:BAAALgAECgcJBQAAAA==.Luxen:BAAALgAECgEJAgAAAA==.',
Ly='Lyadrin:BAAALgADCgEJAQAAAA==.Lycán:BAAALgAECgcJCAAAAA==.Lyntia:BAAALgAECgYJCAAAAA==.Lythium:BAABLgAECn8XAAIWAAgJWSRAAADwAgAWAAgJWSRAAADwAgAAAA==.',
Ma='Maceson:BAAALgAECgQJCQAAAA==.Magnifico:BAAALgAECgEJAQAAAA==.Majicboner:BAAALgAECgYJCgAAAA==.Manark:BAAALgAECgEJAgAAAA==.Mangtash:BAAALgAECgQJCQAAAA==.Maozhuxi:BAAALgAECgQJBAAAAA==.Marvik:BAAALgAECgIJBAAAAA==.Masquerapet:BAACLgAFFH8XAAIJAAYJbhETAwCTAQAJAAYJbhETAwCTAQAuAAQKfywAAgkACQliH2IEAAYDAAkACQliH2IEAAYDAAAA.',
Me='Megadeath:BAABLgAECn8eAAMTAAcJDBcyYwDKAQATAAcJDBcyYwDKAQAdAAEJkgFSGgAiAAAAAA==.Melondawize:BAAALgAECgcJBgAAAA==.',
Mi='Miah:BAACLgAFFH8QAAIKAAYJTA9LBQDVAQAKAAYJTA9LBQDVAQAuAAQKfywAAgoACQkHIO8LACEDAAoACQkHIO8LACEDAAAA.Miao:BAACLgAFFH8LAAIBAAQJzxPVDgDyAAABAAQJzxPVDgDyAAAuAAQKfxkAAwEABwmhIMskAAICAAEABgnPIMskAAICABoAAQllCVGKAC4AAAEuAAUUBgkWAA8A+RkA.Miaomiaomiao:BAACLgAFFH8WAAIPAAYJ+RmbAAAEAgAPAAYJ+RmbAAAEAgAuAAQKfy8AAg8ACQlHJjQAAOsDAA8ACQlHJjQAAOsDAAAA.Miaomiaorawr:BAACLgAFFH8HAAILAAMJrhFZCADjAAALAAMJrhFZCADjAAAuAAQKfxcAAxkABgmZGB8iAIMBABkABgnDEx8iAIMBAAsABgmhFc8yAHQBAAEuAAUUBgkWAA8A+RkA.Mightyz:BAAALgAECgYJDgAAAA==.Minamai:BAAALgAECgYJEwABLgAECggJGQABAN8VAA==.Mirrormaze:BAAALgADCgEJAQAAAA==.',
Mm='Mmfgh:BAAALgAECgYJBgABLgAFFAYJGQACAC0mAA==.Mmjunior:BAAALgADCgIJAgAAAA==.',
Mo='Mollywhop:BAAALgADCgEJAQAAAA==.Monkthejohn:BAACLgAFFH8GAAIVAAMJ2h6lBQAeAQAVAAMJ2h6lBQAeAQAuAAQKfyQAAhUACAnkIjYGACMDABUACAnkIjYGACMDAAAA.Montise:BAAALgADCgQJBAAAAA==.Moongrass:BAAALgAECgQJCgAAAA==.Moontise:BAABLgAECn8YAAICAAcJPw7KdwCLAQACAAcJPw7KdwCLAQAAAA==.Moosemoose:BAAALgAECgUJBQAAAA==.Mousemarâ:BAABLgAECn8bAAIkAAgJqw3pBACxAQAkAAgJqw3pBACxAQAAAA==.Moñgo:BAABLgAECn8dAAMRAAgJohhzBgBkAgARAAgJohhzBgBkAgASAAIJyhJYkwBxAAAAAA==.',
Na='Nagaridar:BAAALgAECgMJAwAAAA==.Nanana:BAABLgAECn8XAAIGAAcJrhCulACqAQAGAAcJrhCulACqAQAAAA==.',
Ne='Necrobrew:BAABLgAECn8dAAIjAAYJnBs/CABUAQAjAAYJnBs/CABUAQABLgAFFAQJDQATAJcZAA==.Necroticlol:BAACLgAFFH8NAAITAAQJlxlEEgBYAQATAAQJlxlEEgBYAQAuAAQKfywAAhMACQktJU8CALgDABMACQktJU8CALgDAAAA.Necroticlól:BAAALgAECgYJEgABLgAFFAQJDQATAJcZAA==.Neegu:BAAALgAFFAEJAQAAAA==.Neff:BAAALgAECggJBQAAAA==.Nefpore:BAAALgADCgQJBAAAAA==.Nehnehh:BAAALgAECgYJEwAAAA==.Neveress:BAABLgAECn8eAAIOAAcJugtoCgCYAQAOAAcJugtoCgCYAQAAAA==.',
Ni='Nigl:BAAALgADCgUJBgAAAA==.Niij:BAAALgAECgQJBAAAAA==.Nitox:BAAALgAECgYJDgAAAA==.',
No='Norrin:BAAALgADCgcJCQAAAA==.Norvanish:BAAALgAECgcJDAABLgAECgkJDgAUAAAAAA==.Nosok:BAAALgAECgMJBgABLgAECgYJDgAUAAAAAA==.Notwithdeath:BAABLgAECn8bAAITAAgJBhGJDQCwAQATAAgJBhGJDQCwAQAAAA==.Nought:BAABLgAECn8gAAIKAAgJ6AwvHgAWAQAKAAgJ6AwvHgAWAQAAAA==.Novis:BAABLgAECn8fAAIVAAgJviEVAgBCAgAVAAgJviEVAgBCAgAAAA==.Noweechi:BAAALgAECggJBgABLgAECgkJDgAUAAAAAA==.',
Nt='Nthope:BAAALgAFFAYJFwAAAQ==.',
Nu='Nukz:BAAALgADCggJCAAAAA==.',
Od='Oddleif:BAAALgAECgUJCgAAAA==.Odyne:BAAALgADCgUJBQAAAA==.',
Oo='Oomowl:BAABLgAECn8kAAIPAAgJMSBHAgCfAgAPAAgJMSBHAgCfAgAAAA==.Oonnfire:BAAALgADCgcJBgAAAA==.',
Or='Orcgydecay:BAABLgAECn8UAAITAAgJahoNOABWAgATAAgJahoNOABWAgAAAA==.',
Os='Oscarr:BAAALgAFFAMJAwAAAA==.',
Pa='Palabean:BAAALgADCgEJAQAAAA==.Pamie:BAAALgAECgUJBQAAAA==.Parascribin:BAAALgAECgYJBgAAAA==.Paz:BAAALgADCgIJAgAAAA==.',
Pe='Peedles:BAAALgAECgcJBgAAAA==.Pennificent:BAACLgAFFH8FAAICAAMJwwfIGADlAAACAAMJwwfIGADlAAAuAAQKfxgAAgIACAnSFv00AE4CAAIACAnSFv00AE4CAAAA.Penta:BAAALgADCggJEgAAAA==.Percy:BAAALgAECgQJCAAAAA==.',
Ph='Phandrea:BAAALgAECgMJAwAAAA==.',
Pi='Pinkwink:BAAALgAECgMJAwAAAA==.',
Po='Pocketpie:BAAALgADCgYJBgAAAA==.Pog:BAACLgAFFH8NAAITAAUJgB/tAgDcAQATAAUJgB/tAgDcAQAuAAQKfxQAAhMACAnvIjsgAMACABMACAnvIjsgAMACAAAA.Pohu:BAAALgAECgYJDgAAAA==.Poros:BAAALgAECgcJEgABLgAECggJIwATANIbAA==.Porosdk:BAABLgAECn8jAAITAAgJ0htPKQCUAgATAAgJ0htPKQCUAgAAAA==.Poroz:BAAALgAECgYJDAABLgAECggJIwATANIbAA==.Poteb:BAAALgADCgMJBAAAAA==.Powerangers:BAAALgAECgMJBQAAAA==.Powercut:BAAALgAECgQJBAAAAA==.',
Pr='Prncesstata:BAAALgADCgEJAQAAAA==.Prodigal:BAACLgAFFH8LAAIeAAQJjQuRAQDxAAAeAAQJjQuRAQDxAAAuAAQKfyUAAh4ACQk7CwINAIgBAB4ACQk7CwINAIgBAAAA.Protadiin:BAAALgAECgQJBAAAAA==.',
Pt='Pterion:BAAALgAECgYJCgAAAA==.Pterionn:BAAALgADCgUJBQAAAA==.',
Pu='Pumbz:BAABLgAECn8eAAMYAAgJ3BzcHwBGAgAYAAYJ6B/cHwBGAgAbAAUJxxaEYAC+AAAAAA==.Punprepared:BAEBLgAECn8gAAIKAAgJcyalAAAEAwAKAAgJcyalAAAEAwAAAA==.',
Pw='Pweedoy:BAABLgAECn8UAAIKAAgJRCAGGADGAgAKAAgJRCAGGADGAgAAAA==.',
Qe='Qeb:BAACLgAFFH8TAAMlAAYJtCIaAACmAQAkAAUJ7iHjAQDpAQAlAAUJvB8aAACmAQAuAAQKfywAAyQACQmcJVoAAOoDACQACQmGJVoAAOoDACUABwmSI0sGABUCAAAA.Qeliss:BAAALgADCgEJAQAAAA==.Qezam:BAAALgAECgEJAQAAAA==.',
Qz='Qzzdh:BAAALgAECgEJAQAAAA==.',
Ra='Raluca:BAAALgADCgIJAgAAAA==.Rastianthrel:BAAALgADCgUJAgAAAA==.Ravenn:BAAALgAECgQJBgABLgAECgQJBgAUAAAAAA==.Razoxaynne:BAAALgAECgYJDgAAAA==.',
Re='Recrute:BAAALgADCgcJBgABLgADCgcJCQAUAAAAAA==.Renesh:BAABLgAECn8eAAIDAAkJERhtDwCZAgADAAkJERhtDwCZAgAAAA==.Rerolling:BAAALgAECgQJBAAAAA==.Resolute:BAAALgAECgYJEAAAAA==.',
Ri='Richrump:BAAALgADCgUJBgAAAA==.Rimreaper:BAAALgAECgMJAwAAAA==.Riplilpeep:BAAALgADCgMJAwAAAA==.',
Ro='Rootwalker:BAAALgADCgYJBgAAAA==.Roshanx:BAAALgAECgIJAwAAAA==.',
Ru='Rualgathor:BAABLgAECn8ZAAMIAAcJ8hOdIADTAQAIAAcJ8hOdIADTAQAZAAIJcgJfUQBGAAAAAA==.Ruptured:BAABLgAECn8wAAMlAAgJLiTrAABGAwAlAAgJLiTrAABGAwAkAAEJaxaXXABAAAAAAA==.',
Ry='Ryo:BAABLgAECn8eAAIKAAcJmCM9GQC9AgAKAAcJmCM9GQC9AgAAAA==.',
['Rï']='Rïsing:BAAALgADCgEJAQAAAA==.',
Sa='Sammy:BAAALgAECgMJBAABLgAECgcJEAAUAAAAAA==.Satria:BAAALgADCgcJCQAAAA==.',
Sc='Scott:BAAALgAECgQJBQAAAA==.',
Se='Senpei:BAAALgADCgMJAwABLgAECgMJAwAUAAAAAA==.Seraphize:BAABLgAECn8bAAMZAAgJZRNBBADfAQAZAAgJFQ5BBADfAQALAAcJbxLyKgCdAQAAAA==.',
Sh='Shalongbao:BAAALgAECgEJAQABLgAECgcJCAAUAAAAAA==.Shazarah:BAAALgAECgYJCAAAAA==.Shidann:BAACLgAFFH8TAAIQAAYJvCYPAAA+AgAQAAYJvCYPAAA+AgAuAAQKfygAAhAACQnyJgoAABMEABAACQnyJgoAABMEAAAA.Shin:BAABLgAECn8VAAIKAAgJ6x4CGQC/AgAKAAgJ6x4CGQC/AgABLgAFFAYJEwAQALwmAA==.Shions:BAAALgAECgMJAwAAAA==.Shirlik:BAAALgADCgcJBwAAAA==.Shneakypeach:BAAALgAECgQJBAAAAA==.',
Si='Sildriel:BAAALgAECgEJAQAAAA==.Silentsnipe:BAAALgAECgEJAgAAAA==.Sillyshammy:BAAALgAECgcJCgAAAA==.Silverbow:BAAALgAECgEJAQAAAA==.Sinorph:BAACLgAFFH8FAAIfAAMJGgpPAgDmAAAfAAMJGgpPAgDmAAAuAAQKfycAAh8ACQm3HmkFABgDAB8ACQm3HmkFABgDAAAA.',
Sl='Slappee:BAAALgAECgMJAwAAAA==.Slappuccino:BAABLgAECn8bAAIMAAcJMhuZBADpAQAMAAcJMhuZBADpAQAAAA==.Slug:BAAALgADCgUJBQAAAA==.',
Sm='Smolpotato:BAAALgAECgYJDwABLgAFFAMJBQAfABoKAA==.',
Sn='Snaketooth:BAAALgADCggJDQAAAA==.Sneakyitch:BAAALgAECgUJBwAAAA==.Snowflake:BAAALgADCgcJDgAAAA==.',
So='Soil:BAACLgAFFH8MAAINAAUJbBqgAwDLAQANAAUJbBqgAwDLAQAuAAQKfycABA0ACAkFHF4MAG8CAA0ACAkFHF4MAG8CACEABAlbEzYUALgAACIAAQnfBhI/ADMAAAAA.Solstickan:BAAALgAECgYJBgAAAA==.Somedruid:BAAALgAECgIJAgABLgAECgYJDgAUAAAAAA==.Somelock:BAAALgADCgcJDAABLgAECgYJDgAUAAAAAA==.Somepally:BAAALgAECgYJDgAAAA==.',
Sp='Spartà:BAAALgAECgcJDgAAAA==.Spiras:BAAALgAECgcJBwAAAA==.',
St='Stacksp:BAAALgAECggJCwAAAA==.Stan:BAACLgAFFH8NAAMYAAYJShvVAACPAQAYAAUJJR3VAACPAQAbAAQJqw8bEAAwAQAuAAQKfxkAAxsACQmNHx0IABsDABsACQn/Gx0IABsDABgABQlSI+QYADQBAAAA.Starbarks:BAAALgADCgcJBwAAAA==.Stealthunt:BAAALgADCgQJBAAAAA==.Stormscythe:BAAALgAECgYJDAAAAA==.Stormsét:BAAALgAECgQJCQAAAA==.Stuntroast:BAAALgAECgYJDwAAAA==.',
Su='Sumdk:BAAALgAECgIJBAABLgAECgUJBgAUAAAAAA==.Sumguy:BAAALgAECgQJBAABLgAECgUJBgAUAAAAAA==.Superfly:BAAALgAECgQJCgAAAA==.Supermayhem:BAAALgAECgUJBwAAAA==.Supermortis:BAAALgADCgIJAgAAAA==.Sutiao:BAACLgAFFH8NAAIGAAUJEh/PBgDyAQAGAAUJEh/PBgDyAQAuAAQKfycAAgYACAmvJRULAGsDAAYACAmvJRULAGsDAAAA.',
Sw='Swissarmy:BAAALgAECgIJAwAAAA==.Swissroll:BAAALgADCgYJCAAAAA==.Switchknife:BAABLgAECn8gAAMkAAkJnBv/BgAgAwAkAAkJnBv/BgAgAwAlAAEJ1wpBHwA2AAAAAA==.',
Sy='Synasta:BAACLgAFFH8FAAIEAAMJDA3GJADwAAAEAAMJDA3GJADwAAAuAAQKfx0AAwQACAm3ILwBAKUCAAQACAm3ILwBAKUCAAUAAQm6AWB4ACsAAAAA.Systher:BAABLgAECn8WAAICAAgJ5A0NegCGAQACAAgJ5A0NegCGAQAAAA==.',
Ta='Tammys:BAAALgAECgUJBQABLgAECgcJDwAUAAAAAA==.Tanason:BAAALgAECgMJAwABLgAECgQJBgAUAAAAAA==.Tancs:BAAALgAECgQJBQAAAA==.Taurium:BAAALgAECgYJDAAAAA==.',
Te='Teaki:BAAALgAECggJEgAAAA==.Teekz:BAABLgAECn8WAAMBAAYJLRpqMwC3AQABAAYJLRpqMwC3AQAaAAQJaAzEYgC4AAAAAA==.Temperance:BAAALgADCgMJBAAAAA==.Temsik:BAAALgAECgEJAgAAAA==.',
Th='Thalloom:BAABLgAECn8VAAIWAAYJvhAnIQA2AQAWAAYJvhAnIQA2AQAAAA==.Thewaterboy:BAAALgAECgUJCgAAAA==.Thoth:BAACLgAFFH8GAAMFAAIJDhQXGABOAAAFAAEJVAwXGABOAAAEAAIJDhQAAAAAAAAuAAQKfzkABAUACAkaIPYCAM4CAAUACAmrHfYCAM4CAA4ABwlzHmEDAGgCAAQABAm8HQHgAJoAAAAA.Thrallish:BAAALgAECgUJBQAAAA==.Thrayneqt:BAAALgADCgIJAgAAAA==.Threiann:BAAALgAECgcJCAAAAA==.Thrux:BAABLgAECn8iAAIGAAgJfhkBCgAKAgAGAAgJfhkBCgAKAgAAAA==.Thumpelina:BAAALgAECgYJDwAAAA==.Thura:BAAALgAECggJCwAAAA==.',
Ti='Tiddlyniblit:BAAALgAECgYJBgAAAA==.Tifa:BAAALgAECgUJBgAAAA==.Timei:BAABLgAECn8UAAQZAAcJdBN7JgBhAQAZAAcJMBB7JgBhAQALAAUJwwyXTAAGAQAIAAUJmQQAAAAAAAAAAA==.',
To='Tommyh:BAACLgAFFH8OAAIIAAYJZRZpAQAYAgAIAAYJZRZpAQAYAgAuAAQKfyIAAggACQlYJXcAAOoDAAgACQlYJXcAAOoDAAAA.Toothdk:BAAALgAECgQJCwAAAA==.Torgaddon:BAAALgADCgMJAwAAAA==.Torress:BAAALgAECgEJAQAAAA==.',
Tr='Trianth:BAAALgAECgMJBwAAAA==.Tribbie:BAACLgAFFH8NAAMTAAUJPxZfEgBYAQATAAQJPxZfEgBYAQAJAAEJAAD9GwApAAAuAAQKfygAAxMACAnJI5EOACcDABMACAnJI5EOACcDAB0AAQnDBF8ZACkAAAAA.',
Tw='Twice:BAAALgAECgcJEwABLgAECggJHQADAIsiAA==.Twizzle:BAAALgAECgQJBgAAAA==.Twljh:BAAALgAECgQJCgAAAA==.',
Ty='Tyranadia:BAACLgAFFH8LAAITAAQJwRr5BABnAQATAAQJwRr5BABnAQAuAAQKfysAAhMACQlWHp4VAPoCABMACQlWHp4VAPoCAAAA.',
Un='Unalive:BAAALgAFFAEJAQAAAA==.',
Up='Upstairs:BAAALgAECgcJCgABLgAFFAMJBQANAIUOAA==.',
Va='Vaelyra:BAAALgAECgEJAQABLgAECgYJHgAfAOERAA==.Valdemar:BAAALgAECgYJDAAAAA==.Valefâr:BAAALgAECgEJAwAAAA==.Valiant:BAAALgAECgIJBwAAAA==.Varnoxx:BAACLgAFFH8IAAITAAQJ3BjsFABPAQATAAQJ3BjsFABPAQAuAAQKfycAAhMACQmXItIKAEUDABMACQmXItIKAEUDAAAA.',
Ve='Veinar:BAAALgAECgEJAQAAAA==.',
Vi='Vicioûs:BAAALgAECggJDgAAAA==.Viciðus:BAAALgAECgQJBwAAAA==.Violetteè:BAAALgAECgEJAgAAAA==.Vitamindee:BAAALgAECgYJCwAAAA==.',
Vl='Vl:BAAALgADCgYJBgABLgAECggJHQADAIsiAA==.Vll:BAAALgAECgQJBwABLgAECggJHQADAIsiAA==.',
Vo='Voidshock:BAAALgAECgQJBAAAAA==.Voltage:BAAALgADCgYJDAABLgAECgUJBgAUAAAAAA==.Vortex:BAAALgAECgkJDgAAAA==.',
Vu='Vulpareon:BAAALgADCgcJBwAAAA==.',
Vv='Vvoo:BAAALgADCgMJAwAAAA==.',
Vw='Vw:BAAALgAECgEJAQABLgAECggJHQADAIsiAA==.',
Wa='Wander:BAAALgAECgYJEAAAAA==.Wards:BAAALgADCgEJAQAAAA==.Wardz:BAAALgAECgUJCQAAAA==.Warmazo:BAAALgADCgUJBQAAAA==.Warmpanties:BAAALgADCgEJAQAAAA==.Watersports:BAAALgAECgkJCAAAAA==.Wazaldin:BAAALgADCgUJBQAAAA==.',
We='Weke:BAAALgADCgMJAwAAAA==.Wetpantees:BAAALgADCgEJAQAAAA==.',
Wh='Whiskas:BAAALgAECggJCgAAAA==.Whispess:BAAALgAECgYJDgAAAA==.',
Wi='Winnievoid:BAAALgAECgEJAgAAAA==.Wish:BAAALgAECgUJBQAAAA==.',
Wo='Woodro:BAAALgAFFAEJAQAAAA==.Wowsuchmage:BAAALgAECgEJAQAAAA==.',
Wt='Wtfoxsays:BAAALgAECgQJBwAAAA==.',
Wy='Wyrda:BAACLgAFFH8PAAIYAAMJZCYbBQBSAQAYAAMJZCYbBQBSAQAuAAQKfywAAhgACQn2IyIDAGIDABgACQn2IyIDAGIDAAAA.',
['Wâ']='Wârlôrd:BAAALgADCgEJAQAAAA==.',
Xi='Xiaomonks:BAACLgAFFH8JAAIMAAQJtxwmBgBqAQAMAAQJtxwmBgBqAQAuAAQKfyUAAgwACAl+IoUGAPYCAAwACAl+IoUGAPYCAAAA.Xiaoputang:BAAALgADCgQJBAABLgAFFAQJCQAMALccAA==.Xiaosneaky:BAAALgAECgMJAwABLgAFFAQJCQAMALccAA==.',
Xt='Xtion:BAACLgAFFH8IAAMYAAQJ3hNtDAC2AAAbAAMJxhB3FgDmAAAYAAIJ2hVtDAC2AAAuAAQKfyAAAxsACQkCH0sLAPECABsACQkCH0sLAPECABgAAgnRDcc4AFsAAAAA.',
Yi='Yiffie:BAABLgAECn8YAAIMAAYJsyOBDwBhAgAMAAYJsyOBDwBhAgABLgAECggJHQADAGIlAA==.Yinz:BAAALgAECgYJBwABLgAECgQJBwAUAAAAAA==.',
Yo='Yongbok:BAAALgAECgYJDgAAAA==.',
Yr='Yrano:BAAALgAECgIJAgAAAA==.',
Za='Zana:BAAALgAECgMJAwAAAA==.Zaraxes:BAAALgAECgUJCgAAAA==.',
Ze='Zelvaris:BAACLgAFFH8TAAImAAUJIiQUAAD5AQAmAAUJIiQUAAD5AQAuAAQKfygAAiYACQn+JBIAANgDACYACQn+JBIAANgDAAAA.Zerkerman:BAAALgADCgYJBgAAAA==.',
Zi='Zipo:BAAALgADCgUJBAABLgAECggJGQAnAOoZAA==.Zips:BAABLgAECn8ZAAQnAAcJ6hkmDAADAgAnAAcJ6hkmDAADAgABAAcJzBUKMgC9AQAaAAIJEhj+cgB2AAAAAA==.',
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

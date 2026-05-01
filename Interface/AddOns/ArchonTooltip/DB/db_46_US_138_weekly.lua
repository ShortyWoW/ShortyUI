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

local lookup = {'Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','DeathKnight-Unholy','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Druid-Guardian','Shaman-Elemental','Paladin-Holy','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Monk-Windwalker','Druid-Feral','Paladin-Protection','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarix:BAAALgADCgkJCQAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJBwAAAA==.Aegia:BAAALgAECgYJEAAAAA==.Aendillan:BAAALgAECgYJDgAAAA==.',
Af='Affonasei:BAAALgAECgcJEwAAAA==.',
Ak='Akashi:BAAALgAECgMJAwABLgAFFAMJBQABAM4JAA==.',
Al='Alladorn:BAAALgADCgEJAQAAAA==.',
An='Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgEJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAAALgAECgcJEQAAAA==.',
Ar='Aragorno:BAABLgAECn8aAAMCAAcJIxIeMQBMAQACAAcJIxIeMQBMAQADAAQJQwY4GgDiAAAAAA==.Araziel:BAAALgAECgEJAQAAAA==.Arcturen:BAAALgAECgQJCAAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgIJAgAEAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgcJEgAEAAAAAA==.Ashiera:BAABLgAECn8bAAMFAAcJUwNddwDoAAAFAAcJUwNddwDoAAAGAAEJ7AHuIgATAAAAAA==.',
At='Atomic:BAAALgAECgMJAwAAAA==.',
Au='Ausuna:BAAALgAECgUJBQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECggJJwABAFccAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJEwAAAA==.Badonka:BAAALgAECgQJBAABLgAECgcJGgAHALMbAA==.Bahaana:BAAALgADCgYJCAAAAA==.Balentine:BAABLgAECn8WAAMIAAYJhRK5SQASAQAIAAUJIBK5SQASAQAJAAUJxwPzRwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAgJHwAKAK8bAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn8aAAIHAAcJsxvzCgDaAQAHAAcJsxvzCgDaAQAAAA==.Baspir:BAABLgAECn8kAAILAAgJARe6EACLAQALAAgJARe6EACLAQAAAA==.',
Be='Belly:BAAALgAECgIJAgABLgAECggJJwABAFccAA==.Belrae:BAABLgAECn8kAAIMAAkJPxGVEQDhAQAMAAkJPxGVEQDhAQAAAA==.Bezieck:BAABLgAECn8ZAAIJAAUJRA0hKAC+AAAJAAUJRA0hKAC+AAAAAA==.',
Bi='Bigdawg:BAAALgAECgcJBgAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8VAAIFAAcJwQkSWAAuAQAFAAcJwQkSWAAuAQAAAA==.',
Bl='Bloodarrow:BAAALgAECgEJAQAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAAALgAECgYJEAAAAA==.Bonegavel:BAAALgAECgQJBgAAAA==.Bookhuntress:BAABLgAECn8cAAMNAAcJ3RtBJgAfAgANAAcJ3RtBJgAfAgALAAMJGRlhIwDlAAAAAA==.',
Br='Branaxe:BAAALgAECgcJBAABLgAECgkJBQAEAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Brewdeez:BAABLgAECn8jAAIOAAgJfR43BAB1AgAOAAgJfR43BAB1AgAAAA==.Brewzer:BAACLgAFFH8IAAIPAAMJJgVTEwCvAAAPAAMJJgVTEwCvAAAuAAQKfx8AAg8ACAmHE8kQAJ0BAA8ACAmHE8kQAJ0BAAAA.Brint:BAAALgAECgMJAwAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8RAAIFAAMJxR0MJgAbAQAFAAMJxR0MJgAbAQAuAAQKfxoAAgUABwkjJc4jAOMCAAUABwkjJc4jAOMCAAAA.Broomhandle:BAAALgAECgYJCwABLgAECgYJEAAEAAAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8KAAIQAAQJehUKCwA8AQAQAAQJehUKCwA8AQAuAAQKfxQAAxAABwkVHigkADUCABAABwkVHigkADUCABEAAgnfGNIrAJUAAAAA.Burinn:BAAALgAECgEJAQABLgAECgcJGwAIAO4KAA==.',
Ca='Caeus:BAAALgAECgYJEAAAAA==.Cam:BAABLgAECn8nAAIFAAgJaCVVBQDmAgAFAAgJaCVVBQDmAgAAAA==.Care:BAABLgAECn8ZAAIFAAkJhAwdiADBAQAFAAkJhAwdiADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAAALgAECgEJAQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgADCgMJAwAAAA==.Chelan:BAABLgAECn8bAAMIAAcJ7gpFUQDyAAAIAAUJ9QtFUQDyAAAJAAcJ7ALUJADVAAAAAA==.Chilljaeden:BAAALgAECgUJBwAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAYJFgAFAAQeAA==.Cinnabunz:BAAALgAECgcJDgAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgQJBgABLgAECgYJGgASANweAA==.',
Co='Codythedead:BAAALgAECgIJAwAAAA==.Compadre:BAAALgAECgYJEgAAAA==.Contekst:BAAALgAECgcJEgAAAA==.Coolsbeans:BAAALgADCgEJAgAAAA==.Coraf:BAACLgAFFH8TAAITAAUJcB0hAwDFAQATAAUJcB0hAwDFAQAuAAQKfy0AAhMACQkZI78BAHQDABMACQkZI78BAHQDAAAA.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgEJAQAAAA==.Cruoris:BAABLgAECn8VAAIUAAcJMQ2wBgBEAQAUAAcJMQ2wBgBEAQAAAA==.',
Cu='Cuvier:BAAALgAECgYJCQAAAA==.',
Da='Daddle:BAAALgAECggJEwAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgIJAgAAAA==.Dahaxors:BAABLgAECn8ZAAIVAAcJ1xjFKgCQAQAVAAcJ1xjFKgCQAQAAAA==.Danak:BAAALgADCgEJAQAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAAALgAECgUJEQAAAA==.',
De='Deadlyfrosty:BAAALgAECgEJAQAAAA==.Debixie:BAACLgAFFH8JAAIUAAMJpxlXAgAeAQAUAAMJpxlXAgAeAQAuAAQKfx0AAhQACAkbIE0BACUDABQACAkbIE0BACUDAAAA.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAAALgAECgcJEAAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAgJHwAKAK8bAA==.Destorr:BAAALgADCgQJBAAAAA==.',
Di='Diasundra:BAABLgAECn8nAAICAAgJhx9QDgDKAgACAAgJhx9QDgDKAgAAAA==.Digiornos:BAABLgAECn8VAAIKAAgJdxZ2XQCwAQAKAAgJdxZ2XQCwAQAAAA==.',
Dj='Djyinn:BAAALgADCgUJCAAAAA==.',
Do='Doorknob:BAAALgAECgYJBwAAAA==.Dottingyou:BAACLgAFFH8SAAIKAAUJDBd5FABLAQAKAAUJDBd5FABLAQAuAAQKfygAAwoACQlJHxoZAL4CAAoACAlJHxoZAL4CABYAAwlMHzUsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.Dragonpo:BAAALgADCgEJAQAAAA==.Drakkonde:BAAALgAECgQJCAAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgADCgEJAQAAAA==.Dryan:BAAALgAECgMJBAAAAA==.Dryon:BAAALgAECgcJEQAAAA==.',
Du='Duo:BAABLgAECn8kAAICAAgJTxPMGgC/AQACAAgJTxPMGgC/AQAAAA==.Duragon:BAABLgAECn8iAAQHAAgJihN6DADBAQAHAAgJihN6DADBAQAXAAYJPgeuEwDAAAAYAAcJEwWbCwCnAAAAAA==.',
['Dí']='Díznutz:BAAALgAECggJEwAAAA==.',
Em='Emilia:BAAALgAECggJDAAAAA==.',
En='Endressa:BAABLgAECn8bAAIZAAgJGQdtEwBgAQAZAAgJGQdtEwBgAQAAAA==.English:BAABLgAECn8iAAIFAAgJ8BjuIgDeAQAFAAgJ8BjuIgDeAQAAAA==.',
Er='Erelios:BAAALgAECgYJDgAAAA==.',
Ev='Evangelina:BAACLgAFFH8XAAMHAAYJPRxkBAC4AQAHAAYJPRxkBAC4AQAYAAEJygryCQBTAAAuAAQKfx4AAwcACAkpI70GABEDAAcACAkNI70GABEDABgABgmRI7gPAN8BAAAA.Everlight:BAAALgAECgEJAQABLgAECgYJFQAaALYTAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8lAAICAAgJdRUEFQDqAQACAAgJdRUEFQDqAQAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAYJFwAHAD0cAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgADCgkJIQAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAYJFgAFAAQeAA==.Fish:BAACLgAFFH8OAAIJAAUJwybhAQCtAQAJAAUJwybhAQCtAQAuAAQKfysAAgkACAleJgYBAAkDAAkACAleJgYBAAkDAAEuAAUUBwkWAAkARyUA.',
Fl='Flight:BAACLgAFFH8FAAIBAAMJzgmNFACsAAABAAMJzgmNFACsAAAuAAQKfxkAAwEACAmmG3gUAG8CAAEACAn4GngUAG8CABQAAQkBDikeADwAAAAA.Fluxyouup:BAABLgAECn8VAAMTAAgJOQJScQDKAAATAAgJOQJScQDKAAAbAAYJ3AQYMgCxAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAAALgAFFAMJAwABLgAFFAQJCgAQAHoVAA==.Forsynth:BAAALgAECgcJEQAAAA==.',
Ge='Gewitt:BAABLgAECn8nAAMTAAgJqiDnBQCRAgATAAgJqiDnBQCRAgAbAAcJ9RXXKADNAQAAAA==.',
Gg='Ggiven:BAAALgADCgUJCAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8TAAIFAAUJniUkCAC4AQAFAAUJniUkCAC4AQAuAAQKfz8AAgUACQmCJVQDAMoDAAUACQmCJVQDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAgJHwAKAK8bAA==.Grazienne:BAAALgADCgEJAQAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8nAAIaAAgJcyHMAQBqAgAaAAgJcyHMAQBqAgAAAA==.Grimbaine:BAAALgAECgcJDQAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAAALgAECgYJDgAAAA==.Gurney:BAABLgAECn8hAAIcAAgJ+RJvFACxAQAcAAgJ+RJvFACxAQAAAA==.Guzfu:BAAALgAECgcJDwAAAA==.',
Gw='Gwenory:BAAALgADCgEJAQAAAA==.',
Gy='Gying:BAAALgAECgUJEwAAAA==.',
Ha='Hanjabs:BAAALgAECgQJBwAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgADCgEJAQAAAA==.',
He='Heatseeka:BAAALgAECggJEQAAAA==.Hexxiz:BAAALgADCgIJAgABLgAECggJIAANAGIkAA==.',
Hi='Hiphopinator:BAABLgAECn8bAAMQAAcJPR+zCAAfAgAQAAcJ7x6zCAAfAgAdAAQJax4uHwBJAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgQJCAAAAA==.Holyterror:BAAALgADCgEJAQAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgADCgIJAQAAAA==.',
Ia='Iamcro:BAAALgAECgQJBAAAAA==.Ianthe:BAAALgAECgQJCAAAAA==.',
Ib='Iboga:BAAALgADCgUJBQAAAA==.Ibrahimovic:BAABLgAECn8dAAMWAAcJdCFOBACZAQAWAAUJRSNOBACZAQAKAAMJxx3QVADyAAAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAYJFwAHAD0cAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgEJAQAAAA==.Infoxicated:BAAALgAECgUJCgAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAABLgAECn8ZAAMIAAgJER0CCAAtAgAIAAgJER0CCAAtAgAZAAMJkgx7QwCZAAAAAA==.',
Ix='Ixtabay:BAABLgAECn8jAAQeAAgJXxxSBQAXAgAeAAcJjx9SBQAXAgAKAAUJnhVAmQAmAQAWAAIJuhJ4UwB0AAAAAA==.',
Ja='Jakobey:BAAALgAECgIJAgAAAA==.Jamurra:BAAALgAECgIJBAAAAA==.Jaylinn:BAABLgAECn8jAAICAAgJOA2iIQCYAQACAAgJOA2iIQCYAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8WAAIZAAcJUCMrCAAXAgAZAAcJUCMrCAAXAgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8VAAIcAAYJUB45DgD4AQAcAAYJUB45DgD4AQAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAAALgAECgQJCAAAAA==.Kaleberry:BAAALgAECgcJDwAAAA==.Kalyandra:BAAALgAECgUJCAAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgAECgMJAwABLgAECgYJEgAEAAAAAA==.Karkevon:BAAALgAECgYJCgAAAA==.Karlach:BAAALgAECggJEQAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karumie:BAABLgAECn8jAAITAAgJ7RriDgAEAgATAAgJ7RriDgAEAgAAAA==.Kateera:BAAALgAECgUJCgAAAA==.',
Ke='Keden:BAAALgADCgEJAQAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAAALgADCgYJAwABLgAECgcJFgAMAIIjAA==.Kels:BAABLgAECn8WAAIMAAcJgiNcLABNAgAMAAcJgiNcLABNAgAAAA==.',
Kh='Kheyra:BAABLgAECn8VAAIaAAYJthPCEwAzAQAaAAYJthPCEwAzAQAAAA==.',
Ki='Kidashia:BAAALgAECgQJBAAAAA==.',
Ko='Kohnor:BAAALgADCgEJAQAAAA==.Kopi:BAAALgAECgEJAQABLgAECgcJEQAEAAAAAA==.Korlatt:BAABLgAECn8WAAMMAAcJlRCcKQBAAQAMAAcJlRCcKQBAAQAfAAEJUwsXcwAyAAAAAA==.Kowalabear:BAABLgAECn8nAAMgAAgJGSIxAQD+AgAgAAgJGSIxAQD+AgAhAAQJMgplIABwAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgAAAA==.',
Kt='Kthanid:BAAALgAECgEJAQAAAA==.',
Ku='Kurston:BAABLgAECn8cAAINAAcJQBv2DwATAgANAAcJQBv2DwATAgAAAA==.',
Ky='Kymakazie:BAAALgAECgYJBwAAAA==.',
['Kã']='Kãtniss:BAAALgADCgEJAQAAAA==.',
La='Laih:BAAALgAECgcJEQAAAA==.Lathelinis:BAAALgADCgIJAgAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAABLgAECn8UAAITAAcJyQ4oJgA7AQATAAcJyQ4oJgA7AQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMiAAYJZBoZNABRAQAiAAUJkxYZNABRAQAOAAQJ+xkMRgAqAQABLgAECggJGAAhAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAAALgAECgYJDgAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAAALgAECgYJCQAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAAALgAECgcJEAAAAA==.Lynniebee:BAABLgAECn8XAAIGAAcJnQjeAwA7AQAGAAcJnQjeAwA7AQAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAAALgAECgcJEQAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAAALgAECgcJEQAAAA==.Matthad:BAAALgAECgYJDgAAAA==.Mazìkene:BAACLgAFFH8JAAIKAAMJCwevNADVAAAKAAMJCwevNADVAAAuAAQKfyEAAgoACQkpFisXAO0BAAoACQkpFisXAO0BAAAA.',
Mc='Mccone:BAAALgAECgEJAQAAAA==.Mcsluts:BAAALgAECgMJBgAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAYJFwAHAD0cAA==.Melmirict:BAACLgAFFH8GAAIBAAMJqg+iDwD2AAABAAMJqg+iDwD2AAAuAAQKfyAAAwEACQlAGYgGAA4CAAEACQlAGYgGAA4CABQAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn8cAAIaAAcJqRF8DADzAAAaAAcJqRF8DADzAAAAAA==.',
Mi='Milyyanna:BAAALgADCgEJAQAAAA==.Minaby:BAAALgAECgYJEAAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8UAAIKAAcJIBfTOgBDAQAKAAcJIBfTOgBDAQAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8VAAMCAAcJhR4BKwAJAgACAAYJKR0BKwAJAgADAAcJdRTdCgCyAQAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAYJFwAHAD0cAA==.Monkle:BAABLgAECn8jAAIiAAgJLyJTAgC/AgAiAAgJLyJTAgC/AgAAAA==.Monkoku:BAAALgAECgQJBAABLgAECggJHAABAK8aAA==.Moonsii:BAAALgAECgUJDAAAAA==.Mooroth:BAABLgAECn8dAAIdAAcJTRp1CQCXAQAdAAcJTRp1CQCXAQAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAAALgAECgQJCwAAAA==.',
Mu='Muddler:BAABLgAECn8dAAIWAAcJhAKHEACtAAAWAAcJhAKHEACtAAAAAA==.Murgut:BAAALgAECgMJAwAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAAALgAECgMJAwAAAA==.Naledi:BAABLgAECn8UAAILAAYJLA8lIAD8AAALAAYJLA8lIAD8AAAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn8UAAIFAAcJcBzJKADBAQAFAAcJcBzJKADBAQAAAA==.Narella:BAAALgAECgcJEwAAAA==.',
Ne='Negrido:BAABLgAECn8iAAMKAAgJiCUvCACKAgAKAAcJ2SEvCACKAgAWAAMJNCWIJAA3AQAAAA==.Nei:BAABLgAECn8XAAISAAcJyBHiNgBoAQASAAcJyBHiNgBoAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn8cAAMLAAcJ9RLGEgBzAQALAAcJ9RLGEgBzAQAaAAEJ0wKNOwAPAAAAAA==.',
No='Noelle:BAAALgADCgMJAwAAAA==.Noraelyn:BAABLgAECn8bAAMcAAcJlR2jJQD5AQAcAAYJ/h2jJQD5AQASAAMJjgMjswBMAAAAAA==.Norelei:BAAALgAECgMJAwABLgAECgYJFQAaALYTAA==.Noriyuki:BAAALgAECgUJEAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAYJFgAFAAQeAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAAALgAFFAEJAgABLgAECgYJBgAEAAAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8VAAIfAAcJsgz/EwALAQAfAAcJsgz/EwALAQAAAA==.',
Om='Omegâ:BAAALgADCgQJBAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgADCgkJCQAAAA==.Oppcookies:BAAALgAECgUJCgABLgAECgcJBwAEAAAAAA==.Oppressin:BAAALgADCggJDAABLgAECgcJBwAEAAAAAA==.Oppshot:BAAALgAECgcJBwAAAA==.',
Or='Orin:BAAALgADCgEJAQAAAA==.',
Os='Oshìe:BAABLgAECn8kAAIcAAkJbhxQDAC4AgAcAAkJbhxQDAC4AgAAAA==.',
Ov='Overdoom:BAABLgAECn8lAAIVAAgJLh6CEAA5AgAVAAgJLh6CEAA5AgAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCgUJCwAAAA==.Paladinjohn:BAACLgAFFH8RAAISAAUJZB5XBwB6AQASAAUJZB5XBwB6AQAuAAQKfycAAhIACQkPJWMBANEDABIACQkPJWMBANEDAAAA.Palykat:BAAALgAECgQJBAAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pennywisé:BAABLgAECn8aAAIVAAgJRBkZFwABAgAVAAgJRBkZFwABAgAAAA==.Pessimal:BAAALgADCgEJAQABLgADCgcJBwAEAAAAAA==.',
Ph='Phoeniix:BAABLgAECn8hAAMaAAgJ0hYNCgD6AQAaAAgJFBYNCgD6AQALAAQJvReoUgDcAAAAAA==.',
Pl='Plaguegying:BAAALgAECgcJCgABLgAECgUJEwAEAAAAAA==.Ploofee:BAAALgAECgYJCwAAAA==.',
Pr='Progresz:BAAALgAECgcJDgAAAA==.',
Ps='Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8iAAILAAgJmAm9HAAWAQALAAgJmAm9HAAWAQAAAA==.',
Qa='Qaren:BAAALgAECgEJAQAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raizo:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn8jAAMjAAgJhRqABADjAQAjAAgJLhmABADjAQAaAAEJmhytGQBRAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAAALgAECgEJAQABLgAECggJIwAeAF8cAA==.Ratabi:BAAALgADCgIJAgAAAA==.Rawrski:BAAALgADCgEJAQABLgAECgcJFQATAPYLAA==.',
Re='Reeven:BAAALgAECggJHAAAAQ==.Ressurectjin:BAAALgAECgQJCgAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAABLgAFFH8FAAIFAAMJrh5TJwA0AQAFAAMJrh5TJwA0AQAAAA==.Rhetegast:BAABLgAECn8jAAIkAAgJKRXGDwDIAQAkAAgJKRXGDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECgIJBAAEAAAAAA==.',
Ri='Rike:BAEBLgAECn8VAAMSAAcJAB9gPQAvAgASAAcJAB9gPQAvAgAkAAMJgRbsEwDOAAAAAA==.',
Ro='Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwAAAA==.Roflhazotime:BAABLgAECn8XAAIMAAgJjyL/AwCvAgAMAAgJjyL/AwCvAgAAAA==.Roland:BAABLgAECn8UAAMNAAYJMxM7LwAhAQANAAYJMxM7LwAhAQALAAEJ8AUjSwAqAAAAAA==.Rolandin:BAABLgAECn8VAAIcAAcJuBFtGQCBAQAcAAcJuBFtGQCBAQAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rook:BAAALgAECgIJAwABLgAFFAUJEwATAHAdAA==.Roscjou:BAAALgADCgUJBQAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.',
Ry='Rylagosa:BAABLgAECn8dAAMXAAcJhBdmCQCIAQAXAAYJXxhmCQCIAQAHAAMJEAkFVQBwAAAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8UAAIFAAgJ5BEwKgC8AQAFAAgJ5BEwKgC8AQAAAA==.',
['Rê']='Rêdrum:BAAALgAECgUJBQABLgAFFAMJCQAKAAsHAA==.',
Sa='Sabithia:BAAALgADCgYJCwAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAAALgAECgYJEwAAAA==.Sarvin:BAAALgADCgcJBwABLgAECggJIQATAL8cAA==.Sarvinblue:BAABLgAECn8hAAMTAAgJvxyRFQBpAgATAAgJvxyRFQBpAgAbAAMJLQ8KagCbAAAAAA==.Saucestash:BAAALgAECgEJAQAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAAALgAECgcJEgAAAA==.Shazlulu:BAAALgAECgQJCAAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8VAAIGAAcJRwqcCgAyAQAGAAcJRwqcCgAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8nAAIBAAgJVxxsBQArAgABAAgJVxxsBQArAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8VAAIcAAcJBBvaCQA4AgAcAAcJBBvaCQA4AgAAAA==.Sloe:BAAALgAECgcJEgAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBAAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgMJAwAAAA==.',
Sp='Speedmeat:BAAALgAECgYJCgAAAA==.Sporkulous:BAABLgAECn8gAAMCAAcJiA0fSwDvAAACAAcJiA0fSwDvAAAlAAEJEwHEJgAUAAAAAA==.',
Sq='Squal:BAABLgAECn8aAAMSAAYJ3B4YVwDdAQASAAYJ3B4YVwDdAQAkAAQJRxglNQBxAAAAAA==.Squiggle:BAABLgAECn8cAAIkAAcJ0RwmBgDIAQAkAAcJ0RwmBgDIAQAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgUJBQAAAA==.Stickybunz:BAAALgAECgYJEAABLgAECggJJgAJAFwTAA==.Striker:BAEALgAECgEJAQABLgAECgcJFQASAAAfAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAEAAAAAA==.Stunseed:BAABLgAECn8fAAIaAAgJRBfVBADMAQAaAAgJRBfVBADMAQAAAA==.',
Su='Sungjinwu:BAAALgAECgMJAwAAAA==.Sunshíne:BAAALgAECgQJCwAAAA==.Surf:BAAALgAECgEJAQAAAA==.',
Sw='Sweetbunz:BAABLgAECn8mAAMJAAgJXBM/KQCQAQAJAAcJthU/KQCQAQAIAAgJWw5gEgCIAQAAAA==.',
Sy='Synaminaphyn:BAAALgADCgMJAwAAAA==.Syver:BAABLgAECn8XAAIVAAcJaxglJACxAQAVAAcJaxglJACxAQAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgMJBgAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgcJFAAKACAXAA==.Taniss:BAABLgAECn8XAAImAAcJ3wSGBgDwAAAmAAcJ3wSGBgDwAAAAAA==.Tanner:BAABLgAECn8bAAMlAAgJDglMSwAkAQAlAAgJuQdMSwAkAQACAAIJoBF+ogCHAAAAAA==.',
Te='Tedman:BAABLgAECn8VAAMbAAcJEA8DJQD7AAAbAAcJEA8DJQD7AAATAAIJDAdYjwBaAAAAAA==.Temel:BAABLgAECn8VAAMTAAcJ9gsgMQD6AAATAAYJUAkgMQD6AAAbAAcJ/wdjJQD5AAAAAA==.Tenelum:BAAALgADCgEJAQABLgAECgcJFQATAPYLAA==.Testoecles:BAAALgAECgMJBQAAAA==.',
Th='Thadrack:BAABLgAECn8UAAIFAAgJowSAWgAoAQAFAAgJowSAWgAoAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAEAAAAAA==.Thalonstin:BAAALgADCgEJAQAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQAEAAAAAA==.Theodrid:BAACLgAFFH8HAAISAAQJTg+0GADnAAASAAQJTg+0GADnAAAuAAQKfyIAAhIACAmOHy8kAJcCABIACAmOHy8kAJcCAAAA.Thraxia:BAABLgAECn8XAAIKAAgJWAX7lQAsAQAKAAgJWAX7lQAsAQAAAA==.',
Ti='Tinkíe:BAAALgAECggJEwAAAA==.Tirzahdozier:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.',
Tl='Tla:BAAALgADCgEJAQAAAA==.',
Tr='Treat:BAABLgAECn8cAAIJAAcJYiKZBABaAgAJAAcJYiKZBABaAgAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAAALgAECgEJAQABLgAFFAgJHwAKAK8bAA==.Tristitia:BAAALgAECgUJDAAAAA==.',
Tu='Tubbs:BAAALgAECggJEAAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAEJAQAEAAAAAA==.',
Ty='Tyche:BAAALgAECgEJAQAAAA==.Tysbich:BAAALgADCgcJBwABLgAECgcJEQAEAAAAAA==.',
Ui='Uiewedaoez:BAABLgAECn8jAAINAAgJXCTWAQBIAwANAAgJXCTWAQBIAwAAAA==.',
Um='Umakkel:BAAALgADCgcJCwAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8eAAIVAAgJExHHJACuAQAVAAgJExHHJACuAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMWAAYJGhD6HgBZAQAWAAYJGhD6HgBZAQAKAAIJ4wHcLwEhAAAAAA==.Vains:BAACLgAFFH8FAAISAAIJCRmMHgCzAAASAAIJCRmMHgCzAAAuAAQKfyIAAhIACQktIb8EANACABIACQktIb8EANACAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAAALgADCgkJFgAAAA==.Vardis:BAABLgAECn8kAAIFAAgJSSCoEgBFAgAFAAgJSSCoEgBFAgAAAA==.',
Ve='Venato:BAAALgADCgEJAwABLgAECgcJFQATAPYLAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8VAAIFAAcJYhd5OgB/AQAFAAcJYhd5OgB/AQAAAA==.Verren:BAAALgAECgcJEQAAAA==.',
Vi='Virse:BAAALgAECgQJBgAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.',
Vy='Vyerith:BAABLgAECn8hAAIKAAgJ0B36DABHAgAKAAgJ0B36DABHAgAAAA==.',
We='Weltamus:BAAALgAECgYJEQAAAA==.Weltasaur:BAAALgAECgEJAQAAAA==.Weltazar:BAAALgAECgcJEwAAAA==.Westside:BAACLgAFFH8WAAIFAAYJBB6IBADnAQAFAAYJBB6IBADnAQAuAAQKfxkAAgUACAnTJp8JAHkDAAUACAnTJp8JAHkDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECggJEwAEAAAAAA==.Wildtiger:BAABLgAECn8WAAIjAAYJQwyzDAARAQAjAAYJQwyzDAARAQAAAA==.',
Wu='Wulfenhide:BAABLgAECn8ZAAQUAAcJ3hbXAwCmAQAUAAcJ3hbXAwCmAQABAAMJoAfiUACkAAAmAAEJeAVfDwArAAAAAA==.',
Wy='Wyzsky:BAAALgADCgEJBAABLgAECgcJFQATAPYLAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgIJAgAEAAAAAA==.Xalreth:BAAALgAECgcJEQAAAA==.Xaviana:BAAALgAECgcJHQAAAQ==.',
Xc='Xcedrin:BAABLgAECn8eAAMJAAgJAAgoHAAcAQAJAAcJ0AYoHAAcAQAIAAMJXwV0OQBKAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8bAAIMAAgJGRogHgB+AQAMAAgJGRogHgB+AQAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8gAAIcAAgJAiSZDwCXAgAcAAgJAiSZDwCXAgAAAA==.Yushi:BAABLgAECn8cAAIBAAgJwxpyBQArAgABAAgJwxpyBQArAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJCQAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAAALgAECgUJBQAAAA==.Zenweaver:BAACLgAFFH8IAAIOAAMJeBfIFAD0AAAOAAMJeBfIFAD0AAAuAAQKfxwAAg4ACQkIIVcEAEcDAA4ACQkIIVcEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zu='Zud:BAAALgAECgcJDAAAAA==.',
['Zö']='Zödd:BAAALgAECgEJAQAAAA==.',
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

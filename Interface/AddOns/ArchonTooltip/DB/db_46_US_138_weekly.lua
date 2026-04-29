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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Shaman-Restoration','Rogue-Assassination','Hunter-BeastMastery','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Evoker-Augmentation','Shaman-Elemental','Druid-Guardian','Paladin-Holy','Warrior-Protection','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Blood','Monk-Windwalker','DeathKnight-Unholy','Druid-Feral','Paladin-Protection','Hunter-Marksmanship','Priest-Holy',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarix:BAAALgADCgUJBQAAAA==.',
Ae='Aedrelyn:BAAALgADCgcJDgAAAA==.Aegia:BAAALgAECgQJCgAAAA==.Aendillan:BAAALgAECgYJDgAAAA==.',
Af='Affonasei:BAAALgAECgYJDAAAAA==.',
Ak='Akashi:BAAALgAECgMJAwABLgAFFAMJBQABAM4JAA==.',
Al='Alladorn:BAAALgADCgEJAQAAAA==.',
An='Ancbow:BAAALgADCgUJBQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAAALgAECgYJDQAAAA==.',
Ar='Aragorno:BAAALgAECgUJEAAAAA==.Araziel:BAAALgADCgYJBgAAAA==.Arcturen:BAAALgAECgQJBAAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgIJAgACAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgYJCwAAAA==.Ashiera:BAABLgAECn8UAAMDAAYJpwI8BQHxAAADAAYJpwI8BQHxAAAEAAEJ7AHwIgATAAAAAA==.',
At='Atomic:BAAALgAECgMJAwAAAA==.',
Au='Ausuna:BAAALgAECgMJAwAAAA==.',
Aw='Awhiteboy:BAAALgAECgUJCAAAAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJEwAAAA==.Badonka:BAAALgADCgkJFwABLgAECgUJEAACAAAAAA==.Bahaana:BAAALgADCgEJAgAAAA==.Balentine:BAAALgAECgYJEgAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAgJHwAFALYbAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAAALgAECgUJEAAAAA==.Baspir:BAABLgAECn8dAAIGAAgJ5RVnIAD6AQAGAAgJ5RVnIAD6AQAAAA==.',
Be='Belly:BAAALgAECgIJAgABLgAECggJJQABAOobAA==.Belrae:BAABLgAECn8VAAIHAAYJTwzUgAAoAQAHAAYJTwzUgAAoAQAAAA==.Bezieck:BAABLgAECn8YAAIIAAUJRA37OgAaAQAIAAUJRA37OgAaAQAAAA==.',
Bi='Bigollock:BAAALgAECgEJAwAAAA==.Billyhikz:BAAALgAECgYJDgAAAA==.',
Bl='Bloodarrow:BAAALgADCgkJEwAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAAALgAECgYJDAAAAA==.Bonegavel:BAAALgAECgQJBgAAAA==.Bookhuntress:BAABLgAECn8YAAIJAAcJ3Rs5JgAfAgAJAAcJ3Rs5JgAfAgAAAA==.',
Br='Branaxe:BAAALgAECgcJBAABLgAECgkJBAACAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAABLgAECn8bAAIKAAgJXB3cAQBTAgAKAAgJXB3cAQBTAgAAAA==.Brewzer:BAACLgAFFH8FAAILAAIJtwIiCgBmAAALAAIJtwIiCgBmAAAuAAQKfx8AAgsACAmHE3IGAKgBAAsACAmHE3IGAKgBAAAA.Brint:BAAALgADCgkJCQAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8PAAIDAAMJ6hgQJgAbAQADAAMJ6hgQJgAbAQAuAAQKfxgAAgMABwkjJcwjAOMCAAMABwkjJcwjAOMCAAAA.Broomhandle:BAAALgAECgUJBQABLgAECgYJDwACAAAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8KAAIMAAQJehUcAwBHAQAMAAQJehUcAwBHAQAuAAQKfxQAAwwABwkVHiUkADUCAAwABwkVHiUkADUCAA0AAgnfGM8rAJUAAAAA.Burinn:BAAALgAECgEJAQABLgAECgYJEQACAAAAAA==.',
Ca='Caeus:BAAALgAECgUJCAAAAA==.Cam:BAABLgAECn8lAAIDAAgJLSV2AQDqAgADAAgJLSV2AQDqAgAAAA==.Care:BAABLgAECn8ZAAIDAAkJhAwuiADBAQADAAkJhAwuiADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Cauud:BAAALgADCgkJGQAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgADCgMJAwAAAA==.Chelan:BAAALgAECgYJEQAAAA==.Chilljaeden:BAAALgAECgQJBwAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAUJEAADABIlAA==.Cinnabunz:BAAALgAECgQJBAAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgEJAQABLgAECgYJFwAOANweAA==.',
Co='Codythedead:BAAALgAECgIJAwAAAA==.Compadre:BAAALgAECgYJEgAAAA==.Contekst:BAAALgAECgYJCwAAAA==.Coolsbeans:BAAALgADCgEJAgAAAA==.Coraf:BAACLgAFFH8OAAIPAAQJTxsUBgBnAQAPAAQJTxsUBgBnAQAuAAQKfy0AAg8ACQkZI78BAHQDAA8ACQkZI78BAHQDAAAA.Corina:BAAALgAECgQJBAAAAA==.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgEJAQAAAA==.Cruoris:BAAALgAECgYJDgAAAA==.',
Cu='Cuvier:BAAALgAECgMJAwAAAA==.',
Da='Daddle:BAAALgAECgYJCwAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Dahaxors:BAAALgAECgYJEgAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAAALgAECgQJDQAAAA==.',
De='Deadlyfrosty:BAAALgADCgkJFwAAAA==.Debixie:BAACLgAFFH8FAAIQAAIJaRTbAwC4AAAQAAIJaRTbAwC4AAAuAAQKfx0AAhAACAkbIE0BACUDABAACAkbIE0BACUDAAAA.Demisi:BAAALgAECgYJEgAAAA==.Demoness:BAAALgAECgYJCwAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAgJHwAFALYbAA==.Destorr:BAAALgADCgQJBAAAAA==.',
Di='Diasundra:BAABLgAECn8gAAIRAAgJah9QDgDKAgARAAgJah9QDgDKAgAAAA==.Digiornos:BAABLgAECn8TAAIFAAcJbBh4XQCwAQAFAAcJbBh4XQCwAQAAAA==.',
Dj='Djyinn:BAAALgADCgMJAwAAAA==.',
Do='Doorknob:BAAALgAECgUJBgAAAA==.Dottingyou:BAACLgAFFH8NAAIFAAQJDhVREgBTAQAFAAQJDhVREgBTAQAuAAQKfygAAwUACQlJHxwZAL4CAAUACAlJHxwZAL4CABIAAwlMHzQsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Drakkonde:BAAALgAECgQJBwAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Dryan:BAAALgAECgMJBAAAAA==.Dryon:BAAALgAECgYJCgAAAA==.',
Du='Duo:BAABLgAECn8cAAIRAAgJ5hLjCQDKAQARAAgJ5hLjCQDKAQAAAA==.Duragon:BAABLgAECn8aAAMTAAgJ0wsICQDWAAATAAYJPgcICQDWAAAUAAcJEwW7BQCsAAAAAA==.',
['Dí']='Díznutz:BAAALgAECggJEgAAAA==.',
En='Endressa:BAABLgAECn8YAAIVAAcJoQcpCQBKAQAVAAcJoQcpCQBKAQAAAA==.English:BAABLgAECn8aAAIDAAgJIRSSEgCtAQADAAgJIRSSEgCtAQAAAA==.',
Er='Erelios:BAAALgAECgUJCAAAAA==.',
Ev='Evangelina:BAACLgAFFH8RAAMWAAUJOR5XBADKAQAWAAUJOR5XBADKAQAUAAEJygrxCQBTAAAuAAQKfx4AAxYACAkpI7wGABEDABYACAkNI7wGABEDABQABgmRI7cPAN8BAAAA.Everlight:BAAALgADCgcJCgABLgAECgYJDwACAAAAAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8jAAIRAAgJqBRSBwD0AQARAAgJqBRSBwD0AQAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAUJEQAWADkeAA==.',
Fe='Feliseda:BAAALgADCgYJBwAAAA==.Felysambre:BAAALgADCgkJHwAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAUJEAADABIlAA==.Fish:BAACLgAFFH8JAAIIAAQJwyaAAgDUAQAIAAQJwyaAAgDUAQAuAAQKfyMAAggACAleJlYCAIwDAAgACAleJlYCAIwDAAEuAAUUBgkVAAgAxyYA.',
Fl='Flight:BAACLgAFFH8FAAIBAAMJzgmrCQCkAAABAAMJzgmrCQCkAAAuAAQKfxkAAwEACAmmG3kUAG8CAAEACAn4GnkUAG8CABAAAQkBDiUeADwAAAAA.Fluxyouup:BAABLgAECn8VAAMPAAgJOQJNcQDKAAAPAAgJOQJNcQDKAAAXAAYJ3AQVGACzAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Forsynth:BAAALgAECgUJDwAAAA==.',
Ge='Gewitt:BAABLgAECn8lAAMPAAgJqiCVAQCjAgAPAAgJqiCVAQCjAgAXAAcJ9RXUKADNAQAAAA==.',
Gg='Ggiven:BAAALgADCgUJCAAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8OAAIDAAQJjCMyDwCeAQADAAQJjCMyDwCeAQAuAAQKfz4AAgMACQmOJVIDAMoDAAMACQmOJVIDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAgJHwAFALYbAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8lAAIYAAgJDiGvAABuAgAYAAgJDiGvAABuAgAAAA==.Grimbaine:BAAALgAECgYJBgAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Gryphin:BAAALgADCgEJAQAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAAALgAECgUJCQAAAA==.Gurney:BAABLgAECn8YAAIZAAcJexNkMwCwAQAZAAcJexNkMwCwAQAAAA==.Guzfu:BAAALgAECgYJDgAAAA==.',
Gy='Gying:BAAALgAECgUJDwAAAA==.',
Ha='Hanjabs:BAAALgAECgQJBwAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.',
He='Heatseeka:BAAALgAECgYJDQAAAA==.',
Hi='Hiphopinator:BAABLgAECn8UAAMMAAYJjx5MBwCtAQAMAAYJMh5MBwCtAQAaAAQJax4qHwBJAQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgQJBgAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
Ia='Iamcro:BAAALgAECgQJBAAAAA==.Ianthe:BAAALgAECgQJBAAAAA==.',
Ib='Iboga:BAAALgADCgUJBQAAAA==.Ibrahimovic:BAABLgAECn8VAAMSAAYJxiEyAwBBAQASAAQJaCQyAwBBAQAFAAIJ0x2A2gCkAAAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAUJEQAWADkeAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgADCgkJCQAAAA==.Infoxicated:BAAALgAECgUJCgAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAAALgAECggJEgAAAA==.',
Ix='Ixtabay:BAABLgAECn8hAAQbAAgJ7htSBQAXAgAbAAcJjx9SBQAXAgAFAAUJnxMxmQAmAQASAAIJuhJuUwB0AAAAAA==.',
Ja='Jakobey:BAAALgAECgIJAgAAAA==.Jamurra:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Jaylinn:BAABLgAECn8bAAIRAAgJ4QrTDgCNAQARAAgJ4QrTDgCNAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8VAAIVAAYJXSOsDQBfAgAVAAYJXSOsDQBfAgAAAA==.',
Ju='Judgekoopa:BAAALgAECgYJDwAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAAALgAECgQJBAAAAA==.Kaleberry:BAAALgAECgYJCwAAAA==.Kalyandra:BAAALgAECgMJAwAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgADCggJDwABLgAECgUJDAACAAAAAA==.Karkevon:BAAALgAECgYJCQAAAA==.Karlach:BAAALgAECgYJCQAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karumie:BAABLgAECn8cAAIPAAgJQholCADHAQAPAAgJQholCADHAQAAAA==.Kateera:BAAALgAECgUJCgAAAA==.',
Ke='Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAAALgADCgYJAwABLgAECgYJDwACAAAAAA==.Kels:BAAALgAECgYJDwAAAA==.',
Kh='Kheyra:BAAALgAECgYJDwAAAA==.',
Ki='Kidashia:BAAALgAECgQJBAAAAA==.',
Ko='Kopi:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.Korlatt:BAAALgAECgYJEwAAAA==.Kowalabear:BAABLgAECn8gAAMcAAgJGSIxAQD+AgAcAAgJGSIxAQD+AgAdAAQJMgoXEABsAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCgQJBAAAAA==.',
Kt='Kthanid:BAAALgADCgkJGQAAAA==.',
Ku='Kurston:BAAALgAECgYJEgAAAA==.',
Ky='Kymakazie:BAAALgAECgEJAQAAAA==.',
La='Laih:BAAALgAECgUJDwAAAA==.Lathelinis:BAAALgADCgIJAgAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAAALgAECgYJDQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Linora:BAAALgADCgcJCgAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMeAAYJZBoZNABRAQAeAAUJkxYZNABRAQAKAAQJ+xkQRgAqAQABLgAECggJGAAdAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAAALgAECgUJCAAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAAALgAECgMJAwAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAAALgAECgYJDQAAAA==.Lynniebee:BAAALgAECgYJEAAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgYJEgAAAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAAALgAECgUJDwAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAAALgAECgUJDwAAAA==.Matthad:BAAALgAECgUJCAAAAA==.Mazìkene:BAACLgAFFH8FAAIFAAIJQQcnHACNAAAFAAIJQQcnHACNAAAuAAQKfx8AAgUACAmhFwMSAIABAAUACAmhFwMSAIABAAAA.',
Mc='Mcsluts:BAAALgAECgMJBgAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAUJEQAWADkeAA==.Melmirict:BAABLgAECn8eAAMBAAcJ8hxRBgCGAQABAAcJ8hxRBgCGAQAQAAMJgBqUEgDZAAAAAA==.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAAALgAECgYJEgAAAA==.',
Mi='Minaby:BAAALgAECgYJDwAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAAALgAECgYJDgAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAAALgAECgYJDgAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAUJEQAWADkeAA==.Monkle:BAABLgAECn8bAAIeAAgJHB9RAQBoAgAeAAgJHB9RAQBoAgAAAA==.Monkoku:BAAALgAECgQJBAABLgAECggJGQABABoZAA==.Moonsii:BAAALgAECgQJCgAAAA==.Mooroth:BAABLgAECn8VAAIaAAYJpx2tEQDtAQAaAAYJpx2tEQDtAQAAAA==.Morozko:BAAALgAECgQJCwAAAA==.',
Mu='Muddler:BAABLgAECn8VAAISAAYJRAJLCgB0AAASAAYJRAJLCgB0AAAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAAALgADCgkJHgAAAA==.Naledi:BAAALgAECgYJDgAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAAALgAECgUJDQAAAA==.Narella:BAAALgAECgUJDAAAAA==.',
Ne='Negrido:BAABLgAECn8aAAMFAAgJRCVkAwBfAgAFAAcJdCFkAwBfAgASAAMJcCWHJAA3AQAAAA==.Nei:BAAALgAECgcJEQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn8VAAMGAAYJhQ2oDgAIAQAGAAYJhQ2oDgAIAQAYAAEJ0wKKOwAPAAAAAA==.',
No='Noelle:BAAALgADCgIJAgAAAA==.Noraelyn:BAAALgAECgYJEwAAAA==.Norelei:BAAALgADCgcJCAABLgAECgYJDwACAAAAAA==.Noriyuki:BAAALgAECgUJEAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAUJEAADABIlAA==.',
Nu='Nugatory:BAAALgAFFAEJAQABLgAECgYJBgACAAAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBgAAAA==.',
Ol='Olrong:BAAALgAECgYJDgAAAA==.',
Om='Omegâ:BAAALgADCgEJAQAAAA==.',
On='Onlypaws:BAAALgAECgYJDgAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgADCgkJCQAAAA==.Oppcookies:BAAALgAECgUJCgAAAA==.Oppressin:BAAALgADCgUJBQABLgAECgUJCgACAAAAAA==.Oppshot:BAAALgAECgUJBQABLgAECgUJCgACAAAAAA==.',
Or='Orin:BAAALgADCgEJAQAAAA==.',
Os='Oshìe:BAABLgAECn8iAAIZAAgJ6RxUDAC4AgAZAAgJ6RxUDAC4AgAAAA==.',
Ov='Overdoom:BAABLgAECn8dAAIfAAgJGhlODAC/AQAfAAgJGhlODAC/AQAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCgUJBwAAAA==.Paladinjohn:BAACLgAFFH8MAAIOAAQJPh6xBwB3AQAOAAQJPh6xBwB3AQAuAAQKfycAAg4ACQkQJWABANEDAA4ACQkQJWABANEDAAAA.Palykat:BAAALgAECgQJBAAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pennywisé:BAABLgAECn8VAAIfAAgJ9xNNhwByAQAfAAgJ9xNNhwByAQAAAA==.Pessimal:BAAALgADCgEJAQABLgAECggJGAAfAAsfAA==.',
Ph='Phoeniix:BAABLgAECn8aAAMYAAgJNBYKCgD6AQAYAAgJWRUKCgD6AQAGAAQJvRelUgDcAAAAAA==.',
Pl='Ploofee:BAAALgAECgYJCgAAAA==.',
Pr='Progresz:BAAALgAECgYJCwAAAA==.',
Ps='Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8bAAIGAAgJcQhaPgA5AQAGAAgJcQhaPgA5AQAAAA==.',
Qa='Qaren:BAAALgADCgkJGQAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgIJAgAAAA==.',
Ra='Raizo:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn8bAAMgAAgJaBMcAwCQAQAgAAgJrBIcAwCQAQAYAAEJXRjWDABIAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAAALgADCgIJAgAAAA==.Ratabi:BAAALgADCgIJAgAAAA==.',
Re='Reeven:BAAALgAECgcJGAAAAQ==.Ressurectjin:BAAALgAECgQJCQAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAAALgAFFAEJAQAAAA==.Rhetegast:BAABLgAECn8cAAIhAAgJnBLDDwDIAQAhAAgJnBLDDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.',
Ri='Rike:BAEALgAECgYJDgAAAA==.',
Ro='Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwAAAA==.Roflhazotime:BAABLgAECn8UAAIHAAgJcSEnBQA1AgAHAAgJcSEnBQA1AgAAAA==.Roland:BAAALgAECgUJDQAAAA==.Rolandin:BAAALgAECgYJDgAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rook:BAAALgAECgIJAgABLgAFFAQJDgAPAE8bAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.',
Ry='Rylagosa:BAABLgAECn8VAAMTAAYJ2xZHBQBZAQATAAYJ2xZHBQBZAQAWAAIJngr/VABwAAAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAAALgAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAALgAECgIJAgABLgAFFAIJBQAFAEEHAA==.',
Sa='Sabithia:BAAALgADCgYJCwAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCgAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAAALgAECgUJDQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECggJIQAPAL8cAA==.Sarvinblue:BAABLgAECn8hAAMPAAgJvxyUFQBpAgAPAAgJvxyUFQBpAgAXAAMJLQ8AagCbAAAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seizo:BAAALgAECgYJDwAAAA==.Seshu:BAAALgAECgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAAALgAECgYJCwAAAA==.Shazlulu:BAAALgAECgQJBAAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAAALgAECgYJDgAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8lAAIBAAgJ6hsJAgAoAgABAAgJ6hsJAgAoAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAAALgAECgYJDgAAAA==.Sloe:BAAALgAECgYJCwAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBAAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgMJAwAAAA==.',
Sp='Speedmeat:BAAALgAECgYJCgAAAA==.Sporkulous:BAABLgAECn8cAAMRAAYJ4Q4qZwAyAQARAAYJ4Q4qZwAyAQAiAAEJEwF9FQAVAAAAAA==.',
Sq='Squal:BAABLgAECn8XAAMOAAYJ3B4bVwDdAQAOAAYJ3B4bVwDdAQAhAAIJMxckNQBxAAAAAA==.Squiggle:BAABLgAECn8UAAIhAAYJfx+bCwARAgAhAAYJfx+bCwARAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgADCgMJAwAAAA==.Stickybunz:BAAALgAECgYJCwABLgAECgYJGQAIADwXAA==.Striker:BAEALgADCgYJBgABLgAECgYJDgACAAAAAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAACAAAAAA==.Stunseed:BAABLgAECn8XAAIYAAgJ3w/cBAAgAQAYAAgJ3w/cBAAgAQAAAA==.',
Su='Sungjinwu:BAAALgAECgMJAwAAAA==.Sunshíne:BAAALgAECgQJCgAAAA==.Surf:BAAALgAECgEJAgAAAA==.',
Sw='Sweetbunz:BAABLgAECn8ZAAIIAAYJPBc5KQCQAQAIAAYJPBc5KQCQAQAAAA==.',
Sy='Synaminaphyn:BAAALgADCgMJAwAAAA==.Syver:BAAALgAECgYJEAAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgMJAwAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Tanagra:BAAALgADCgYJDAABLgAECgYJDgACAAAAAA==.Taniss:BAAALgAECgYJEAAAAA==.Tanner:BAABLgAECn8ZAAMiAAgJDglSSwAkAQAiAAgJuQdSSwAkAQARAAIJoBF6ogCHAAAAAA==.',
Te='Tedman:BAAALgAECgYJEwAAAA==.Temel:BAAALgAECgYJDgAAAA==.Testoecles:BAAALgAECgMJBQAAAA==.',
Th='Thadrack:BAAALgAECgYJDQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQACAAAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQACAAAAAA==.Theodrid:BAACLgAFFH8FAAIOAAMJYQyuGADnAAAOAAMJYQyuGADnAAAuAAQKfyIAAg4ACAmOHzQkAJcCAA4ACAmOHzQkAJcCAAAA.Thraxia:BAABLgAECn8XAAIFAAgJWAXwlQAsAQAFAAgJWAXwlQAsAQAAAA==.',
Ti='Tinkíe:BAAALgAECgYJEAAAAA==.Tirzahdozier:BAAALgAECgEJAQAAAA==.',
Tr='Treat:BAAALgAECgYJEgAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAAALgAECgEJAQABLgAFFAgJHwAFALYbAA==.Tristitia:BAAALgAECgUJCAAAAA==.',
Tu='Tubbs:BAAALgAECggJEAAAAA==.Turkeltin:BAAALgAECgYJEAAAAA==.',
Ty='Tyche:BAAALgADCgkJGQAAAA==.',
Ui='Uiewedaoez:BAABLgAECn8bAAIJAAgJlB7NBAA5AgAJAAgJlB7NBAA5AgAAAA==.',
Um='Umakkel:BAAALgADCgUJBAAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8cAAIfAAgJSA/HDQCtAQAfAAgJSA/HDQCtAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMSAAYJGhD3HgBZAQASAAYJGhD3HgBZAQAFAAIJ4wHDLwEhAAAAAA==.Vains:BAACLgAFFH8FAAIOAAIJCRlFDgCwAAAOAAIJCRlFDgCwAAAuAAQKfyAAAg4ACAkMIosHABMCAA4ACAkMIosHABMCAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAAALgADCgkJEAAAAA==.Vardis:BAABLgAECn8bAAIDAAgJVx8KPACHAgADAAgJVx8KPACHAgAAAA==.',
Ve='Venato:BAAALgADCgEJAwABLgAECgYJDgACAAAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAAALgAECgYJDgAAAA==.Verren:BAAALgAECgUJDwAAAA==.',
Vi='Virse:BAAALgAECgQJBgAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.',
Vy='Vyerith:BAABLgAECn8fAAIFAAgJgBxIBABAAgAFAAgJgBxIBABAAgAAAA==.',
We='Weltamus:BAAALgAECgYJDwAAAA==.Weltasaur:BAAALgADCgkJFgAAAA==.Weltazar:BAAALgAECgUJDAAAAA==.Westside:BAACLgAFFH8QAAIDAAUJEiXsBAAbAgADAAUJEiXsBAAbAgAuAAQKfxkAAgMACAnTJpQJAHkDAAMACAnTJpQJAHkDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgYJCwACAAAAAA==.Wildtiger:BAAALgAECgYJEQAAAA==.',
Wu='Wulfenhide:BAAALgAECgYJEAAAAA==.',
Wy='Wyzsky:BAAALgADCgEJBAABLgAECgYJDgACAAAAAA==.',
Xa='Xal:BAAALgADCgEJAQAAAA==.Xalreth:BAAALgAECgUJDwAAAA==.Xaviana:BAAALgAECgYJFQAAAQ==.',
Xc='Xcedrin:BAABLgAECn8WAAMIAAgJpAeBEQDfAAAIAAYJOwWBEQDfAAAjAAMJ7gRycQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8bAAIHAAgJ6BgNLwBAAgAHAAgJ6BgNLwBAAgAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8XAAIZAAgJAiSbDwCXAgAZAAgJAiSbDwCXAgAAAA==.Yushi:BAABLgAECn8UAAIBAAgJnRQOAwD3AQABAAgJnRQOAwD3AQAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zayfall:BAAALgAECgUJDAAAAA==.',
Ze='Zenweaver:BAACLgAFFH8HAAIKAAMJPhdMBwD6AAAKAAMJPhdMBwD6AAAuAAQKfxwAAgoACQkIIVkEAEYDAAoACQkIIVkEAEYDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zu='Zud:BAAALgAECgYJCwAAAA==.',
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

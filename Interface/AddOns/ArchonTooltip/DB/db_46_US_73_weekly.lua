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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Holy','Mage-Frost','Paladin-Retribution','Rogue-Subtlety','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Druid-Balance','Warrior-Arms','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Restoration','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Paladin-Protection','Druid-Feral','Rogue-Outlaw','Hunter-Survival','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abbraxys:BAAALgADCgkJDgAAAA==.',
Ad='Adios:BAACLgAFFH8RAAIBAAYJDBy5AwDIAQABAAYJDBy5AwDIAQAuAAQKfxgAAwEACAkPJFgQAHMCAAEACAkPJFgQAHMCAAIABgnDDbUfADABAAAA.',
Af='Afflict:BAAALgADCgcJEwAAAA==.',
Ag='Agaar:BAAALgAECgQJDQAAAA==.',
Ai='Aidasul:BAAALgAECgQJCAAAAA==.Aireese:BAABLgAECn8nAAIDAAkJyR2nAgA8AgADAAkJyR2nAgA8AgAAAA==.',
Ak='Akaizhar:BAAALgADCgEJAQAAAA==.',
Al='Alareth:BAAALgAECgYJCQAAAA==.Alinity:BAAALgAECgUJBwAAAA==.Alnysh:BAAALgADCgUJCQAAAA==.',
Am='Amorilladron:BAABLgAECn8bAAIEAAgJ/wMpZgDXAAAEAAgJ/wMpZgDXAAAAAA==.',
An='Anakira:BAAALgADCggJEgAAAA==.Anséis:BAAALgAECgIJAQAAAA==.Anti:BAAALgAECgMJBAAAAA==.Antury:BAAALgAECgkJEwAAAA==.',
Aq='Aquamatty:BAAALgADCgEJAQAAAA==.',
Ar='Arcayne:BAAALgAECgMJAwAAAA==.Areeya:BAABLgAECn8UAAMFAAcJahbsKgBoAQAFAAYJvhXsKgBoAQAGAAUJPBQXSAAzAQAAAA==.Ariamis:BAAALgADCgYJBgAAAA==.Arkatt:BAABLgAECn8lAAIEAAkJbhr9CwBqAgAEAAkJbhr9CwBqAgAAAA==.Arrowgance:BAAALgAECgQJBAABLgAFFAYJEQABAAwcAA==.Artorious:BAAALgADCgUJBQAAAA==.Arulas:BAABLgAECn8iAAIDAAkJ9w/HDgAnAQADAAkJ9w/HDgAnAQAAAA==.Arx:BAABLgAECn8XAAIHAAcJPyCcHQBhAgAHAAcJPyCcHQBhAgAAAA==.',
As='Ascrod:BAACLgAFFH8GAAMIAAQJMQVqHgAKAQAIAAQJMQVqHgAKAQAJAAEJwQHIGgBDAAAuAAQKfxUABAkABwn8GWUVAJ8BAAkABgkAG2UVAJ8BAAgABAlaEye0APAAAAoAAQnpFYAwAD0AAAEuAAMKBQkFAAsAAAAA.Ashami:BAAALgADCgEJAQAAAA==.Ashaxxi:BAAALgAECgMJAwABLgAFFAQJCgAMADQGAA==.Ashildr:BAACLgAFFH8KAAIMAAQJNAZLAgDnAAAMAAQJNAZLAgDnAAAuAAQKfyMABAwACQnVEhUKAMcBAAwACQnVEhUKAMcBAA0AAgm8A7JlAE0AAA4AAgkOBSLTAE0AAAAA.Asuwish:BAABLgAECn8fAAIPAAgJxBFcFgBbAQAPAAgJxBFcFgBbAQAAAA==.',
At='Atcjedi:BAAALgAECgcJEwAAAA==.Atmospherew:BAABLgAFFH8FAAIIAAIJBh1qOgC7AAAIAAIJBh1qOgC7AAABLgAFFAYJGQAQADomAA==.Atmospherez:BAACLgAFFH8ZAAIQAAYJOiaxAQAvAgAQAAYJOiaxAQAvAgAuAAQKfyUAAhAACQnZJkMAAAkEABAACQnZJkMAAAkEAAAA.',
Au='Audiamer:BAAALgAECgIJAgAAAA==.Auradawn:BAAALgADCgEJAQAAAA==.',
Az='Azardel:BAAALgADCgQJBAAAAA==.Azmodan:BAAALgAECgMJAwAAAA==.',
['Añ']='Añdrew:BAAALgADCgIJAQAAAA==.',
Ba='Baalsdruid:BAAALgAECgYJCAAAAA==.Badgerdar:BAAALgAECggJDwAAAA==.Baep:BAACLgAFFH8IAAIRAAMJwyUPDQBUAQARAAMJwyUPDQBUAQAuAAQKfxgAAhEACAl0JUQJAEcDABEACAl0JUQJAEcDAAAA.Baess:BAAALgAECgUJBQABLgAECggJGwASALcVAA==.Bagels:BAAALgAECgYJCgAAAA==.Balance:BAABLgAECn8vAAQCAAcJexjUBABwAQACAAcJexjUBABwAQABAAYJ/RBOGgAsAQATAAMJwwTAPQB9AAAAAA==.Balooa:BAAALgAECgUJCwAAAA==.Bandrago:BAAALgAECgYJBwAAAA==.Banzan:BAAALgAECgQJBAAAAA==.Barktwain:BAABLgAECn8UAAIUAAYJTQkKHADGAAAUAAYJTQkKHADGAAABLgAECgUJDAALAAAAAA==.Barracuda:BAAALgAECgQJBAAAAA==.Barrybrown:BAAALgAECgQJBwAAAA==.',
Bd='Bdikd:BAAALgADCgQJBwAAAA==.',
Be='Beeaarr:BAABLgAECn8XAAIRAAcJAhVRiABqAQARAAcJAhVRiABqAQAAAA==.Beercules:BAABLgAECn8nAAIVAAgJThn4DAC7AQAVAAgJThn4DAC7AQAAAA==.Belagore:BAABLgAECn8hAAIHAAgJTB69BQBcAgAHAAgJTB69BQBcAgAAAA==.Belegmor:BAAALgADCgEJAgAAAA==.Benfrank:BAABLgAECn8eAAMWAAgJXxbYHwAAAgAWAAgJXxbYHwAAAgAUAAIJ/gSbHgAyAAAAAA==.Benkkei:BAABLgAECn8lAAMHAAgJ9xwJBgBWAgAHAAgJNRwJBgBWAgAXAAYJ4hXiEQCDAQAAAA==.Bethan:BAABLgAECn8VAAIQAAYJzQQGfADdAAAQAAYJzQQGfADdAAAAAA==.',
Bf='Bfillz:BAABLgAECn8VAAIOAAcJ2BKFRQDVAAAOAAcJ2BKFRQDVAAAAAA==.',
Bi='Bibi:BAAALgAECgYJCQAAAA==.Bigantall:BAAALgAECgQJBQAAAA==.Bigmedic:BAAALgAECgcJDwABLgAFFAIJBQAYAEUMAA==.Bigtea:BAAALgAECgQJCQAAAA==.Biishess:BAAALgAECgkJBAAAAA==.Bitta:BAAALgAECgIJAgAAAA==.',
Bl='Blaart:BAAALgAECgcJDwAAAA==.Blacksheep:BAAALgAECgEJAgAAAA==.Blanka:BAACLgAFFH8FAAIYAAIJRQyDBACiAAAYAAIJRQyDBACiAAAuAAQKfxYAAxgACAneGJoIAFUCABgACAneGJoIAFUCABkAAQmWASaqACMAAAAA.Blax:BAAALgAECgYJBQAAAA==.Blindhugs:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Bluexecute:BAAALgAECggJEwAAAA==.Blumez:BAAALgAECgcJDgAAAA==.Blùey:BAAALgADCgMJAwAAAA==.',
Bo='Bob:BAAALgADCgcJBwABLgAECggJGgAIAM0ZAA==.Bodytypebig:BAABLgAECn8gAAIUAAgJZRY/BgCaAQAUAAgJZRY/BgCaAQAAAA==.Boeuf:BAAALgAECgkJDwAAAA==.Boicrystian:BAAALgAECgYJDAAAAA==.Bolillo:BAAALgAECgEJAQAAAA==.Bookitty:BAAALgAECgEJAQAAAA==.Bord:BAAALgADCgYJBgAAAA==.Bossed:BAAALgAECgMJBwAAAA==.Bossladìe:BAAALgAECgcJCgAAAA==.Boston:BAAALgAECgEJAQAAAA==.',
Br='Brewness:BAAALgAECgcJEQABLgAECggJEwALAAAAAA==.Brommix:BAAALgAECgQJCQAAAA==.Brown:BAAALgAECgcJEgAAAA==.Broxy:BAAALgAECgEJAgAAAA==.',
Bu='Bucci:BAAALgADCgIJAwAAAA==.Buhbles:BAACLgAFFH8FAAIWAAUJ4Rv6BQBoAQAWAAUJ4Rv6BQBoAQAuAAQKfyEAAhYABwnXI/AHABUCABYABwnXI/AHABUCAAAA.Buhflobill:BAAALgADCgcJCgAAAA==.Bullshiitake:BAAALgAECgUJCgAAAA==.Burberry:BAAALgAECgEJAQAAAA==.',
Ca='Cae:BAABLgAECn8WAAIOAAgJiBnNIQBoAQAOAAgJiBnNIQBoAQAAAA==.Calaglin:BAABLgAECn8XAAMIAAgJQRroSwDlAQAIAAcJIx3oSwDlAQAJAAIJ9AiJSwCLAAAAAA==.Calastiria:BAAALgADCgcJDAAAAA==.Caleb:BAAALgADCgYJBgABLgAECgYJBwALAAAAAA==.Camdragon:BAAALgADCgEJAQABLgAECgQJCAALAAAAAA==.Cassylan:BAAALgADCgEJAQAAAA==.Catdancingif:BAAALgAFFAMJAwABLgAFFAYJDwAOABEgAA==.Cavaloris:BAABLgAECn8UAAIaAAcJvwUvSwAbAQAaAAcJvwUvSwAbAQAAAA==.',
Ce='Celesti:BAABLgAECn8ZAAIRAAcJ0BSdQwA/AQARAAcJ0BSdQwA/AQAAAA==.Cellia:BAABLgAECn8VAAIRAAgJ7hlDGAD6AQARAAgJ7hlDGAD6AQAAAA==.Cevy:BAACLgAFFH8HAAIVAAQJMyEDBgBxAQAVAAQJMyEDBgBxAQAuAAQKfxUAAhUACAlQJS4FADYDABUACAlQJS4FADYDAAAA.',
Ch='Chekz:BAAALgADCgUJBQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chickensalad:BAAALgAECgIJAgABLgAECgYJCgALAAAAAA==.Chilæ:BAAALgAECgYJCgABLgAECggJHQAQAFEXAA==.Chirhoxp:BAACLgAFFH8FAAIbAAIJZgWkDQBwAAAbAAIJZgWkDQBwAAAuAAQKfyUAAxsACAl7EMoXAJkBABsACAl7EMoXAJkBAAcAAgmfCiuXAGQAAAAA.Chocomousse:BAAALgADCgcJEQAAAA==.Chop:BAAALgAECgQJBAAAAA==.Christi:BAAALgAECgMJBAABLgAFFAQJCgAcABgTAA==.Chubbstone:BAAALgADCgIJAgAAAA==.Chuckkyd:BAABLgAECn8eAAIRAAgJBB1uFwAAAgARAAgJBB1uFwAAAgAAAA==.',
Ci='Cileo:BAAALgADCgYJCQAAAA==.',
Cl='Clanka:BAAALgAECgQJBQAAAA==.Cleb:BAAALgAECgYJBwAAAA==.Clocker:BAABLgAECn8ZAAIZAAYJGyBNHQAwAgAZAAYJGyBNHQAwAgAAAA==.Clumbsykoala:BAAALgAECgQJBgAAAA==.Clâyface:BAABLgAECn8dAAIWAAcJeQ2YGgAnAQAWAAcJeQ2YGgAnAQAAAA==.',
Co='Coasta:BAAALgAECgMJCAAAAA==.Coldlunch:BAAALgAECgIJAgAAAA==.Colton:BAABLgAFFH8FAAITAAEJKgbKFgBKAAATAAEJKgbKFgBKAAAAAA==.Combatcow:BAACLgAFFH8HAAIHAAMJ2BOXEAACAQAHAAMJ2BOXEAACAQAuAAQKfyMAAgcACAmqIUYLAAEDAAcACAmqIUYLAAEDAAAA.Cozmic:BAABLgAECn8jAAIQAAgJWiL1CQCfAgAQAAgJWiL1CQCfAgAAAA==.',
Cq='Cq:BAAALgADCggJCAAAAA==.',
Cr='Crackseed:BAABLgAECn8WAAIcAAcJIB/qCgBaAgAcAAcJIB/qCgBaAgAAAA==.Craftymidget:BAABLgAECn8hAAIGAAgJSQsWBwB1AQAGAAgJSQsWBwB1AQAAAA==.Crit:BAAALgAECgQJCgABLgAFFAQJDgAEAPAfAA==.',
Ct='Ctn:BAAALgAECgMJBgAAAA==.',
Cu='Curandero:BAAALgAECgQJCgAAAA==.Curie:BAABLgAECn8dAAIQAAgJURcaPwBwAQAQAAgJURcaPwBwAQAAAA==.',
Da='Dalynar:BAAALgADCgEJAQAAAA==.Dameck:BAABLgAECn8nAAMXAAkJAxVGAwArAgAXAAkJNRRGAwArAgAHAAYJmRibQgCaAQAAAA==.Dampo:BAAALgADCgYJDAAAAA==.Danakira:BAAALgADCgMJBgAAAA==.Dancemonkey:BAAALgAECgUJCQAAAA==.Daralock:BAABLgAECn8fAAMIAAgJVBs1TwDaAQAIAAYJghs1TwDaAQAJAAQJGRGKMwDpAAAAAA==.Darkburley:BAAALgAECgUJBwAAAA==.Darkcastle:BAAALgADCgYJCQAAAA==.Darkholy:BAAALgADCgYJDgAAAA==.Darosh:BAAALgAECgIJAgABLgAECgcJFgAEAIgYAA==.Das:BAABLgAECn8ZAAIOAAgJbyBGCwApAgAOAAgJbyBGCwApAgAAAA==.Dawnbringer:BAAALgADCgEJAQAAAA==.Dayxxday:BAAALgAECgQJBgAAAA==.Dazzeler:BAABLgAECn8WAAIEAAcJiBhIJgCmAQAEAAcJiBhIJgCmAQAAAA==.',
De='Deathdisiple:BAAALgAECgMJAgAAAA==.Deathpetals:BAACLgAFFH8WAAIEAAcJ3CE/AgD4AQAEAAcJ3CE/AgD4AQAuAAQKfyYAAgQACQkqJo4AAOoDAAQACQkqJo4AAOoDAAAA.Decepciona:BAABLgAECn8gAAQIAAcJJyEiGgDZAQAIAAUJliAiGgDZAQAJAAMJaiAHLAAPAQAKAAEJAAAiIwBlAAAAAA==.Deecaye:BAAALgAECgEJAQAAAA==.Deejaypaulyd:BAAALgAECgYJEQAAAA==.Delver:BAAALgADCgIJAgAAAA==.Demongirly:BAAALgADCgcJBwAAAA==.Derailed:BAAALgAECgUJBQAAAA==.Desp:BAAALgAECgMJAgABLgAFFAcJFgAdALUVAA==.Despir:BAACLgAFFH8WAAMdAAcJtRXPBgBPAQAdAAYJTBTPBgBPAQAPAAMJUgnGBwDuAAAuAAQKfx0ABA8ACAm9HbIKAKICAA8ACAm9HbIKAKICAB0ABglbJEUfAN4BAB4AAgnVAhNQAE4AAAAA.Destantokill:BAAALgAECgMJAwAAAA==.Destro:BAAALgADCgUJBQAAAA==.Devilpoing:BAAALgAECgUJCAAAAA==.Devounor:BAAALgAECgYJCgAAAA==.',
Di='Ding:BAAALgADCgIJAgAAAA==.',
Do='Donnamatrix:BAAALgAECgIJAgAAAA==.Dorado:BAAALgADCgIJAgAAAA==.Douchec:BAAALgADCgMJBgAAAA==.',
Dr='Dracarizz:BAAALgADCgQJBAAAAA==.Draconius:BAAALgADCgkJGAAAAA==.Draenor:BAAALgADCgcJDQAAAA==.Dragnspittle:BAABLgAECn8iAAQTAAkJEhviAgB8AgATAAgJahriAgB8AgABAAUJmRoCFwBFAQACAAMJbBODCgDGAAAAAA==.Dragonforce:BAABLgAECn8dAAICAAcJvRaEAwCvAQACAAcJvRaEAwCvAQAAAA==.Dragonskull:BAAALgAECgYJEAAAAA==.Dragonturd:BAABLgAECn8WAAIRAAgJVxA2JgCrAQARAAgJVxA2JgCrAQAAAA==.Drazentar:BAAALgAECgYJEgAAAA==.Dregore:BAAALgAECgYJEgABLgAECggJIQAHAEweAA==.Drethor:BAAALgADCgIJAgABLgAECggJJAAEAOkfAA==.Drevox:BAABLgAECn8kAAIEAAgJ6R9LDgBQAgAEAAgJ6R9LDgBQAgAAAA==.Druidheals:BAAALgAECgIJAgAAAA==.',
Du='Dulgar:BAABLgAECn8nAAIZAAkJ/RrqAwDHAgAZAAkJ/RrqAwDHAgAAAA==.Dummythick:BAAALgAECgEJAQAAAA==.Dunsmuir:BAABLgAECn8rAAIFAAcJOh5xEAASAgAFAAcJOh5xEAASAgAAAA==.Dux:BAABLgAECn8NAAIOAAgJQR7zQwDkAQAOAAgJQR7zQwDkAQAAAA==.',
['Dé']='Dévé:BAAALgADCgkJEAAAAA==.',
Ea='Eamonn:BAAALgADCgUJBQABLgAECgEJAwALAAAAAA==.',
El='Elephant:BAAALgAECgEJAQAAAA==.Elhokar:BAAALgAECgYJBgAAAA==.Elleduff:BAABLgAECn8VAAIfAAcJLA7JFQA9AQAfAAcJLA7JFQA9AQAAAA==.Eloragon:BAAALgADCgcJDAAAAA==.Elspeth:BAAALgAECgUJBwAAAA==.Elviusel:BAAALgADCgMJAwAAAA==.Elydra:BAAALgAECgQJBQAAAA==.Elyssabeta:BAAALgAECgEJAQAAAA==.Elysstaa:BAABLgAECn8hAAMPAAkJQxLuCQAJAgAPAAkJQxLuCQAJAgAdAAQJzgtMSQC5AAAAAA==.',
En='Energizér:BAAALgAECgIJAwAAAA==.',
Eq='Equilibria:BAAALgAECgQJCQAAAA==.',
Es='Esris:BAAALgAECggJKgAAAQ==.',
Et='Etík:BAAALgAECgQJBgAAAA==.',
Ev='Evomengol:BAAALgADCgUJBwABLgAFFAMJBwAWAFYNAA==.',
Ex='Exorcist:BAAALgAECgEJAQAAAA==.',
Ey='Eyebright:BAAALgAECgMJAwAAAA==.Eyye:BAAALgADCgYJBgABLgAECgcJAQALAAAAAA==.',
Fa='Falcyn:BAABLgAECn8XAAIRAAYJYBABjgBfAQARAAYJYBABjgBfAQAAAA==.Faminex:BAACLgAFFH8OAAIaAAcJwCFeAABgAgAaAAcJwCFeAABgAgAuAAQKfxsAAxoACAn/Hz8JAP4CABoACAn/Hz8JAP4CABgABAmWHhMcAAoBAAAA.Famr:BAAALgADCgEJAQABLgAFFAcJDgAaAMAhAA==.Farns:BAACLgAFFH8TAAIQAAYJ/yKzBQDUAQAQAAYJ/yKzBQDUAQAuAAQKfxgAAhAACAnnJTgsAMICABAACAnnJTgsAMICAAAA.',
Fe='Feiyue:BAABLgAECn8YAAMIAAcJwhEvWAC/AQAIAAcJwhEvWAC/AQAKAAEJ6g0dMAA+AAAAAA==.Felinepriest:BAAALgAECgYJCAAAAA==.Felsdh:BAAALgAECgUJCgAAAA==.Felsoaked:BAAALgAECgQJBwAAAA==.Feltotes:BAAALgADCgcJDgAAAA==.Felucia:BAAALgAECgYJCgAAAA==.Fenryr:BAAALgAECggJCwAAAA==.Feyvorian:BAAALgADCgMJAwAAAA==.',
Fi='Fingerbone:BAAALgADCgkJEgAAAA==.Firebäne:BAABLgAECn8bAAIJAAgJpCCdAQAoAgAJAAgJpCCdAQAoAgAAAA==.Firecreep:BAAALgAECgcJDAAAAA==.Fistweave:BAAALgAECgMJAwAAAA==.Fiññ:BAAALgAECgEJAQAAAA==.',
Fl='Flaminghawk:BAACLgAFFH8OAAIQAAYJYxK1HQBUAQAQAAYJYxK1HQBUAQAuAAQKfycAAhAACAmYIY0oANACABAACAmYIY0oANACAAAA.Flokkii:BAAALgAECgQJBwAAAA==.Floofyfire:BAAALgAECgEJAQAAAA==.',
Fm='Fmnx:BAAALgADCgMJAwABLgAFFAcJDgAaAMAhAA==.',
Fo='Foxmonk:BAAALgADCgYJBgAAAA==.',
Fr='Frankazoid:BAABLgAECn8WAAIEAAcJ2RZVPABKAQAEAAcJ2RZVPABKAQAAAA==.Frankdatank:BAAALgADCgcJBwABLgAECggJFgAEANkWAA==.Freightfrayn:BAABLgAECn8rAAIZAAkJLxz0BgAEAwAZAAkJLxz0BgAEAwAAAA==.Freyin:BAAALgAECgYJEgAAAA==.Frolgar:BAAALgAECgIJAgAAAA==.Frostytotems:BAAALgADCgcJBgAAAA==.',
Fu='Fulldracarys:BAACLgAFFH8RAAITAAYJLBZaAgD+AQATAAYJLBZaAgD+AQAuAAQKfx8AAhMACAlyJZsCAEUDABMACAlyJZsCAEUDAAEuAAUUBwkPABwAKg8A.Fullgabagool:BAABLgAFFH8IAAIeAAQJrRf1CgBVAQAeAAQJrRf1CgBVAQABLgAFFAcJDwAcACoPAA==.Fullmist:BAAALgAECgcJBgABLgAFFAcJDwAcACoPAA==.Fulltranq:BAACLgAFFH8PAAIcAAcJKg8YAgATAgAcAAcJKg8YAgATAgAuAAQKfxcAAhwABwnmIv4hADYCABwABwnmIv4hADYCAAAA.',
Fw='Fwaffy:BAAALgAFFAEJAQAAAA==.',
['Fë']='Fëanor:BAAALgAECgQJBAAAAA==.',
['Fø']='Føxz:BAABLgAECn8UAAIVAAgJHBwTFgBZAgAVAAgJHBwTFgBZAgAAAA==.Føxzxv:BAAALgAECggJDAAAAA==.',
Ga='Gamesucks:BAAALgAECgEJAgAAAA==.Ganster:BAAALgAECgEJAgAAAA==.Gaya:BAAALgADCgYJEQAAAA==.',
Ge='Gee:BAAALgADCgEJAgAAAA==.Geltheros:BAAALgADCggJCAAAAA==.Getzapped:BAAALgAECgQJAwAAAA==.',
Gf='Gfoo:BAABLgAECn8UAAIfAAYJ0BjkJwCaAQAfAAYJ0BjkJwCaAQAAAA==.',
Gh='Ghidorah:BAAALgAECgMJBAAAAA==.',
Gi='Gigabloke:BAAALgADCgUJBQAAAA==.Gigastar:BAAALgAECgYJBgAAAA==.',
Gl='Glacia:BAAALgADCgUJBQAAAA==.Glaticus:BAAALgAECgEJAQAAAA==.Glimpse:BAAALgAECggJEQAAAA==.Glizzgobbler:BAAALgAECgQJAwAAAA==.',
Go='Gokêe:BAAALgAECgcJDgABLgAECgcJFQADAEMcAA==.Golddigger:BAAALgAECgYJEQAAAA==.Golok:BAAALgAECgEJAgABLgAECgYJBgALAAAAAA==.Goof:BAAALgAECgYJEQAAAA==.Gout:BAAALgADCgEJAQAAAA==.Goyuri:BAAALgAECgQJBwAAAA==.',
Gr='Greenmonsta:BAAALgAECgcJDwAAAA==.Grimknight:BAAALgAECggJEwAAAA==.Groovi:BAAALgADCgYJCgAAAA==.Grubergeiger:BAAALgAECgUJCAABLgAECgkJDwALAAAAAA==.Gruunele:BAABLgAECn8gAAIYAAgJehwrAgBaAgAYAAgJehwrAgBaAgAAAA==.Grü:BAAALgADCgkJCQABLgAECgkJDwALAAAAAA==.',
Gu='Gutrigor:BAAALgAECgYJDQAAAA==.',
Gw='Gwår:BAAALgAECgYJCAAAAA==.',
['Gó']='Gókee:BAABLgAECn8VAAMDAAcJQxxiBwCqAQADAAcJQxxiBwCqAQAEAAEJKgXuMAEnAAAAAA==.',
Ha='Habebe:BAAALgAFFAEJAQAAAA==.Hair:BAAALgADCgYJBgAAAA==.Hardknockz:BAAALgAECgQJBAABLgAECggJHwAOAHIcAA==.Hashbrowns:BAABLgAECn8nAAIRAAkJfSBtAgAKAwARAAkJfSBtAgAKAwAAAA==.Hav:BAEBLgAECn8lAAIQAAkJaSLoBgDKAgAQAAkJaSLoBgDKAgAAAA==.Havaker:BAEALgAECgYJCQABLgAECgkJJQAQAGkiAA==.Haxxorwyn:BAAALgAECgYJCQAAAA==.',
He='Heartlust:BAABLgAECn8XAAIQAAcJYxgtcgDvAQAQAAcJYxgtcgDvAQAAAA==.Hefemusprime:BAAALgADCgcJBwAAAA==.Hellscolon:BAABLgAECn8ZAAIIAAkJ1gijMQBlAQAIAAkJ1gijMQBlAQAAAA==.Hema:BAAALgAECgMJBAABLgAECggJFAAEAOkWAA==.Herakless:BAAALgAECggJDgAAAA==.',
Hi='Highrider:BAAALgADCggJDQAAAA==.Hillybaba:BAAALgADCgcJBwAAAA==.Hitagi:BAAALgAECgYJDQAAAA==.',
Ho='Hoa:BAAALgAECgQJBgAAAA==.Holi:BAAALgAECgEJAgAAAA==.Holicow:BAABLgAFFH8GAAIRAAMJnh/JFwAcAQARAAMJnh/JFwAcAQAAAA==.Holii:BAAALgAECgIJAwAAAA==.Holybagels:BAAALgAECgYJBgAAAA==.Holyblasts:BAAALgAECgYJDAAAAA==.Holyblowèr:BAABLgAECn8cAAIRAAcJQSMoEAA8AgARAAcJQSMoEAA8AgAAAA==.Holydicsadin:BAAALgAECgQJBAAAAA==.Holydisciple:BAAALgADCgEJAQAAAA==.Holynikki:BAABLgAECn8UAAIgAAYJagVxGAChAAAgAAYJagVxGAChAAAAAA==.Holytalon:BAAALgADCgMJBAAAAA==.',
Hu='Hummingbird:BAAALgAECggJEAABLgAECgcJIAAIACchAA==.Hungus:BAABLgAECn8aAAINAAcJcRvKCAC8AQANAAcJcRvKCAC8AQAAAA==.Hurtszick:BAAALgADCgEJAgAAAA==.',
Hy='Hybryddin:BAAALgADCgcJBwAAAA==.Hydrotiger:BAAALgAECgQJCAAAAA==.',
['Hà']='Hàra:BAAALgADCgUJCQAAAA==.',
Ia='Iamazombie:BAAALgADCgIJAgAAAA==.Iamholyman:BAAALgADCgYJBgAAAA==.',
Ig='Igotchubruh:BAAALgAECgIJAgAAAA==.',
Ik='Ikitty:BAAALgAECgIJAgAAAA==.',
Il='Ilovemymommy:BAAALgAECgYJDAAAAA==.',
Im='Imaru:BAAALgADCgYJBgAAAA==.Imnotthtgood:BAAALgADCgkJHQAAAA==.Impact:BAAALgADCgkJCQABLgAECgcJLwACAHsYAA==.Implosion:BAABLgAECn8mAAIIAAgJyBS8GgDVAQAIAAgJyBS8GgDVAQAAAA==.',
In='Indigolemon:BAABLgAECn8aAAQUAAgJQBrdBQB2AgAUAAgJQBrdBQB2AgAhAAUJyBYlFgBXAQAWAAEJDhwgdQBOAAAAAA==.Inkconjurer:BAABLgAECn8dAAIQAAgJsBmfKwC1AQAQAAgJsBmfKwC1AQAAAA==.Inouskee:BAAALgADCgUJBQAAAA==.',
Io='Iowned:BAABLgAECn8UAAIgAAgJrBBaEAD7AAAgAAgJrBBaEAD7AAAAAA==.',
Ir='Irraelina:BAAALgADCgIJAgABLgAFFAQJCQAXAPQOAA==.',
Is='Ishundo:BAABLgAECn8YAAIfAAcJLBesEQBoAQAfAAcJLBesEQBoAQAAAA==.Isplash:BAAALgADCgMJAwAAAA==.',
Iz='Izalithx:BAACLgAFFH8MAAMIAAYJFxzOAQAgAgAIAAYJ6xrOAQAgAgAJAAIJKhpsCwCvAAAuAAQKfxgAAwgACAkUIQoqAGgCAAgABwkUIQoqAGgCAAkAAwmHFoQvAP0AAAEuAAUUBwkOABoAwCEA.',
Ja='Jakku:BAABLgAECn8WAAIQAAcJBgy7swB3AQAQAAcJBgy7swB3AQAAAA==.Jamie:BAAALgAECgcJEwAAAA==.Jastiri:BAAALgADCgIJAgAAAA==.',
Je='Jelly:BAABLgAECn8UAAIQAAcJPh2oVgA1AgAQAAcJPh2oVgA1AgAAAA==.',
Ji='Jiinrop:BAEBLgAECn8WAAMJAAcJIxQgIABSAQAIAAYJuRIfbwCCAQAJAAYJXxAgIABSAQAAAA==.Jinah:BAAALgADCgQJBAAAAA==.',
Jo='Johnassassin:BAAALgAECgYJCgAAAA==.Jollyollie:BAAALgAECgYJCQAAAA==.Jonahkin:BAABLgAECn8YAAIWAAgJWBvwGwAiAgAWAAgJWBvwGwAiAgAAAA==.',
Ju='Judgewapner:BAAALgAECgEJAQAAAA==.Juicelord:BAAALgAECgMJBQAAAA==.Juiya:BAAALgADCgQJBAAAAA==.Juuice:BAAALgAECgEJAQAAAA==.',
Ka='Kaedes:BAACLgAFFH8HAAMWAAMJVg2iFACfAAAWAAIJCg2iFACfAAAhAAEJ7g0YBwBYAAAuAAQKfy0ABRYACAl2IscDAIsCABYACAkGIscDAIsCACEABgmkGewSAIABABwAAgknGXtMAJ8AABQAAQkIFWstAEEAAAAA.Kailyn:BAAALgAECgEJAQAAAA==.Kaiwai:BAAALgADCgYJBgAAAA==.Kaizoku:BAAALgADCgQJBAAAAA==.Kaladin:BAAALgAECgQJBQAAAA==.Kaldanarys:BAAALgAECgEJAQAAAA==.Kalenlock:BAAALgAECgYJCgAAAA==.Kaleo:BAAALgADCgcJDQABLgAECgcJCgALAAAAAA==.Kaorii:BAAALgADCgcJBwAAAA==.Karsus:BAAALgAECgIJAgAAAA==.Katherrian:BAAALgADCgcJBwABLgAECgkJJgAFAHcdAA==.Kathorall:BAABLgAECn8bAAIFAAgJNRPNIACcAQAFAAgJNRPNIACcAQAAAA==.Kavawings:BAAALgAECgQJBgAAAA==.Kawaiihealer:BAABLgAECn8dAAIPAAcJtBwfGgALAgAPAAcJtBwfGgALAgAAAA==.',
Ke='Keddy:BAAALgADCgMJCQAAAA==.Kemper:BAAALgAECgYJEQAAAA==.Keoua:BAAALgADCgIJAgAAAA==.Kerrs:BAAALgAECgEJAQAAAA==.Kerrz:BAAALgAECgEJAgAAAA==.',
Kh='Khaza:BAAALgADCgMJBgAAAA==.',
Ki='Kidil:BAAALgADCgkJEAAAAA==.Kidneypopper:BAAALgAECgYJDQABLgAECggJIwAQAFoiAA==.Kievit:BAAALgAECgcJEAAAAA==.Killá:BAAALgADCgMJAwAAAA==.Kir:BAABLgAECn8XAAMOAAYJ2xuZLQAtAQANAAUJyB2OJQCSAQAOAAYJexKZLQAtAQAAAA==.',
Kk='Kkrantuq:BAABLgAECn8mAAIiAAkJ1xciAgDaAQAiAAkJ1xciAgDaAQAAAA==.',
Kl='Klarityqt:BAAALgAECgQJBgAAAA==.Klarityx:BAABLgAECn8hAAIQAAkJ9RR3PQCCAgAQAAkJ9RR3PQCCAgAAAA==.',
Ko='Kogadeath:BAAALgAECgEJAQAAAA==.Kogadraco:BAAALgAECgYJBwAAAA==.Komatos:BAACLgAFFH8HAAIaAAMJUyUQCABOAQAaAAMJUyUQCABOAQAuAAQKfygAAhoACAnqJMoCALUCABoACAnqJMoCALUCAAAA.Korona:BAABLgAECn8nAAIQAAkJ1RRqFgApAgAQAAkJ1RRqFgApAgAAAA==.Korra:BAAALgADCgYJCgAAAA==.',
Kr='Kraptastic:BAAALgADCgEJAQAAAA==.',
Ky='Kylar:BAAALgAECgYJCwABLgAECgkJJgAiANcXAA==.',
['Kê']='Kênsêi:BAAALgAECgMJBQABLgAECggJJAABAO4TAA==.',
['Kô']='Kôan:BAAALgADCgkJEQAAAA==.',
La='Laserbeams:BAAALgAECgYJDQAAAA==.',
Le='Leafyjoe:BAAALgAECgYJBwAAAA==.Lechencaja:BAAALgAECgQJBAAAAA==.Legendarybob:BAAALgAECgMJAwAAAA==.Legomyeggö:BAABLgAECn8cAAIEAAcJsRsSVAD1AQAEAAcJsRsSVAD1AQAAAA==.',
Lh='Lhera:BAABLgAECn8iAAQGAAgJnhfkBQCXAQAFAAYJkhzRMwDgAQAjAAgJKhB6CQDKAQAGAAcJ/xbkBQCXAQAAAA==.',
Li='Lilglittery:BAAALgADCgYJBgAAAA==.Lilnikki:BAAALgADCgUJCgAAAA==.Lisp:BAAALgADCgYJBgAAAA==.Livathian:BAABLgAECn8YAAIRAAgJTxSrRgA2AQARAAgJTxSrRgA2AQAAAA==.',
Lo='Lockingdown:BAAALgADCgYJCAAAAA==.Longshotx:BAAALgADCgUJBQAAAA==.Lothuial:BAAALgADCgEJAgAAAA==.',
Lu='Lucellis:BAAALgAECgcJBwAAAA==.Lumira:BAABLgAECn8kAAIFAAgJuBxsDgAnAgAFAAgJuBxsDgAnAgAAAA==.Lurex:BAAALgADCgEJAgAAAA==.Luzwarlockok:BAAALgAECgcJCAAAAA==.',
Lz='Lzybys:BAAALgADCgYJBgAAAA==.',
Ma='Madris:BAABLgAECn8XAAMeAAcJlhlDDADFAQAeAAcJlhlDDADFAQAdAAQJug6zIQDuAAAAAA==.Maelstroke:BAAALgADCgcJBwAAAA==.Magimagi:BAAALgAECgUJCAAAAA==.Magtharn:BAAALgAECgUJBwAAAA==.Magusdark:BAAALgAECgYJBwAAAA==.Makkascholar:BAAALgAECgIJAgAAAA==.Makotoh:BAAALgADCgEJAQAAAA==.Malnorr:BAABLgAECn8WAAMIAAgJaxl1QwAnAQAIAAcJaxl1QwAnAQAJAAEJAACJaQA/AAAAAA==.Manbeerpig:BAAALgAECgYJCgABLgAECgkJDwALAAAAAA==.Mandykiinz:BAAALgAECgYJEQAAAA==.Mannimarco:BAAALgADCgEJAQAAAA==.Maryillo:BAACLgAFFH8eAAMUAAcJSxpPAAD/AQAUAAcJJRhPAAD/AQAWAAUJVSHRBACeAQAuAAQKfyQAAxQACAlAJKACAPwCABQACAkUIaACAPwCABYABwmAJKgNAMACAAAA.',
Mc='Mcflurry:BAAALgAECgEJAQAAAA==.',
Me='Medd:BAAALgAECgUJCQAAAA==.Mengol:BAAALgADCgMJAwABLgAFFAMJBwAWAFYNAA==.Mennil:BAAALgAECgQJCAAAAA==.Meolater:BAABLgAECn8aAAITAAcJtCBsBAAvAgATAAcJtCBsBAAvAgAAAA==.Meowz:BAAALgADCgUJBQAAAA==.Mesmerise:BAAALgAECgYJEAAAAA==.',
Mh='Mhyrora:BAAALgAECgEJAQAAAA==.',
Mi='Mick:BAAALgADCgcJBwAAAA==.Midorii:BAAALgADCggJCwAAAA==.Mikeygee:BAAALgAECgEJAQABLgAECgUJBwALAAAAAA==.Mio:BAAALgADCgcJBwAAAA==.Miraya:BAACLgAFFH8FAAIIAAMJlAwXPACaAAAIAAMJlAwXPACaAAAuAAQKfyUAAwgACAlzGE4wAEsCAAgACAnDF04wAEsCAAkABAmtCZA6AMoAAAAA.Misbehaved:BAAALgADCgcJDAAAAA==.Mishrakthul:BAAALgAECgQJBQAAAA==.Missfear:BAAALgADCggJFwAAAA==.',
Mm='Mmrsdelaneys:BAAALgADCgEJAgAAAA==.',
Mo='Mokari:BAEBLgAECn8mAAMjAAkJASHGAAD8AgAjAAkJDyDGAAD8AgAFAAcJxhzrIgA0AgAAAA==.Mon:BAAALgADCgQJBwAAAA==.Moonfrost:BAAALgAECggJEQAAAA==.Morbidchaos:BAACLgAFFH8JAAIOAAUJpxdIDwBUAQAOAAUJpxdIDwBUAQAuAAQKfxsAAg4ACQljIcsFAGkDAA4ACQljIcsFAGkDAAAA.Morbius:BAAALgAECgcJEQAAAA==.Morglum:BAABLgAECn8pAAMIAAgJ8hu9OQAlAgAIAAgJ8hu9OQAlAgAJAAEJAACXbAA7AAAAAA==.Morlog:BAAALgADCgUJBgAAAA==.Mosnar:BAAALgADCgEJAQAAAA==.',
Mu='Muddywalrus:BAAALgAECgIJCAAAAA==.Mukatsuku:BAAALgAECgYJDAAAAA==.Muscida:BAAALgADCgEJAQAAAA==.',
My='Myzas:BAAALgADCgcJBwAAAA==.',
['Mâ']='Mâyüri:BAABLgAECn8dAAMaAAcJHxM3GgBBAQAaAAcJHxM3GgBBAQAZAAIJYAJxlABLAAABLgAECggJJAABAO4TAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQABLgAECgIJAwALAAAAAA==.Naeth:BAABLgAECn8jAAIRAAgJXR66EgAkAgARAAgJXR66EgAkAgAAAA==.Nalrot:BAAALgADCgYJCAABLgAECgYJEAALAAAAAA==.Narcine:BAABLgAECn8mAAMFAAkJdx3wAgDhAgAFAAkJdx3wAgDhAgAjAAYJshu2EQCnAQAAAA==.Narina:BAAALgAECggJCAAAAA==.Naví:BAAALgAECgcJDAAAAA==.',
Ne='Necie:BAABLgAECn8nAAIUAAkJRhUuBQC9AQAUAAkJRhUuBQC9AQABLgABCgEJAQALAAAAAA==.Neckred:BAAALgADCgEJAQAAAA==.Nedri:BAABLgAECn8VAAMIAAcJgBD+MQBjAQAIAAcJUw3+MQBjAQAKAAQJMgw5FwDEAAAAAA==.Nee:BAABLgAFFH8TAAIZAAYJ8hk+AwCmAQAZAAYJ8hk+AwCmAQAAAA==.Nelor:BAAALgAECgYJCwAAAA==.Nethya:BAAALgADCgMJAwAAAA==.',
Ni='Nibblet:BAAALgADCgEJAQAAAA==.Nightnight:BAAALgAECgYJCQAAAA==.Nikkibear:BAAALgAECgMJBAAAAA==.Ninjason:BAAALgAECgEJAQAAAA==.Nissa:BAAALgAECgEJAQAAAA==.Nitashal:BAABLgAECn8gAAMTAAkJRh6/AQDKAgATAAkJRh6/AQDKAgACAAEJwAYEQAAwAAAAAA==.',
No='Nobudagero:BAAALgAECgYJDgAAAA==.Noremac:BAAALgADCgkJGgAAAA==.Norgalis:BAAALgADCgMJBQAAAA==.Nosman:BAAALgAECgMJAwAAAA==.',
Nr='Nrowtuo:BAAALgAECgYJDwAAAA==.',
Ny='Ny:BAAALgADCgEJAwAAAA==.',
['Në']='Nëzükõ:BAAALgADCgkJFgABLgAECggJJAABAO4TAA==.',
Oa='Oathbreaker:BAAALgADCgcJBQAAAA==.',
Ol='Olivabiscuit:BAABLgAECn8VAAMEAAYJ9RSTkgBbAQAEAAYJ9RSTkgBbAQADAAQJEg5QMQC2AAAAAA==.Oliviawildè:BAAALgAECgQJBgAAAA==.Olivya:BAAALgADCgYJBgAAAA==.',
On='Onepump:BAAALgADCgMJAwAAAA==.',
Oo='Oogiessxd:BAAALgAECgUJEwAAAA==.Oops:BAAALgADCgQJBAAAAA==.',
Or='Orwata:BAAALgADCgcJBwAAAA==.',
Ou='Ouskun:BAAALgADCgQJBQAAAA==.',
Ow='Owynn:BAAALgAECgMJAwAAAA==.',
Oz='Ozurot:BAABLgAECn8aAAIfAAgJBw/3DwB9AQAfAAgJBw/3DwB9AQAAAA==.',
Pa='Pakoh:BAACLgAFFH8FAAIcAAIJ8BfnGACaAAAcAAIJ8BfnGACaAAAuAAQKfyEABBwACAnuI4obAF8CABwABgkYJIobAF8CABYACAmUILwaAC4CABQAAwmqIvkJAC4BAAAA.Palabok:BAAALgAECgYJBwAAAA==.Paladang:BAAALgAECgcJAQAAAA==.Paladont:BAAALgAECgMJBwAAAA==.Palmarez:BAAALgADCgUJBAAAAA==.Panchita:BAAALgAECgYJCwAAAA==.Pandemoniúm:BAABLgAECn8VAAIfAAYJuxrZEAByAQAfAAYJuxrZEAByAQAAAA==.Panfriedrice:BAAALgAECgQJAgAAAA==.Pantyblossom:BAAALgAECgYJDwAAAA==.Pasdovqr:BAAALgAECgUJEAAAAA==.',
Pe='Peewees:BAAALgADCgcJBwAAAA==.Pegasus:BAABLgAECn8rAAIJAAgJyRkKBACnAgAJAAgJyRkKBACnAgAAAA==.Persivul:BAAALgAECgUJBgAAAA==.Pewpewz:BAAALgAECgMJBAABLgAECggJKQAHAEESAA==.',
Ph='Phaeddrus:BAAALgAECgYJCwAAAA==.Phaedross:BAAALgAECgEJAQAAAA==.Pheret:BAAALgAFFAIJAgAAAA==.Phobos:BAABLgAECn8nAAIBAAgJ3weAGQAyAQABAAgJ3weAGQAyAQAAAA==.Phogood:BAAALgAECgUJCAAAAA==.Phrix:BAAALgAECgQJBgABLgAFFAMJCQACAM8TAA==.',
Pi='Pineapple:BAAALgAECgUJCQABLgAECggJEAAOABIZAA==.Pineapplelol:BAAALgAECgcJCwABLgAECggJEAAOABIZAA==.Pineapplë:BAABLgAECn8QAAMOAAgJEhmPLgBCAgAOAAgJEhmPLgBCAgANAAEJBR8xawA7AAAAAA==.Pinecone:BAAALgADCgUJBQABLgAECggJEAAOABIZAA==.Pinëapple:BAAALgAECgYJCgABLgAECggJEAAOABIZAA==.Pissdanger:BAAALgAECgEJAQAAAA==.Piñeapple:BAAALgAECgYJDAABLgAECggJEAAOABIZAA==.',
Pl='Plot:BAAALgAECgQJCAAAAA==.',
Po='Poekimaw:BAAALgAECgQJAwAAAA==.Polpo:BAACLgAFFH8SAAIRAAUJzCPZAgC0AQARAAUJzCPZAgC0AQAuAAQKfxYAAhEACAkWJRsoAIQCABEACAkWJRsoAIQCAAAA.Poppinin:BAABLgAECn8aAAIRAAcJABcSKQCeAQARAAcJABcSKQCeAQAAAA==.Powerwordhug:BAAALgAECgEJAQAAAA==.',
Pr='Prancer:BAAALgADCgMJAwAAAA==.Prevaleon:BAAALgADCgMJAwAAAA==.Procasual:BAAALgAECgYJEAAAAA==.',
Ps='Psychritic:BAABLgAECn8iAAIQAAgJFiJWCAC1AgAQAAgJFiJWCAC1AgAAAA==.Psyence:BAAALgAECgIJAwABLgAECggJFwAMAIQRAA==.',
Pt='Pterodactyl:BAAALgAECgYJCgAAAA==.',
Pu='Purpletotem:BAAALgAECgQJBAAAAA==.Purrsnikitty:BAABLgAECn8dAAIFAAcJbxaYHQCuAQAFAAcJbxaYHQCuAQAAAA==.',
['Pà']='Pànzer:BAAALgAECgQJBAAAAA==.',
['Pî']='Pîneapple:BAAALgADCgcJCwABLgAECggJEAAOABIZAA==.',
['Pô']='Pô:BAAALgAECgEJAQABLgAECggJFQARAO4ZAA==.',
Qq='Qqmoarnoob:BAAALgADCgYJBgAAAA==.',
Qu='Quillmane:BAAALgAECgQJDAABLgAFFAMJCQACAM8TAA==.Quiza:BAAALgADCgIJAgAAAA==.',
Ra='Raevyn:BAAALgAECgYJDgAAAA==.Ragebate:BAABLgAECn8fAAIOAAgJchzbLwA8AgAOAAgJchzbLwA8AgAAAA==.Ragingbohner:BAAALgADCgcJBwAAAA==.Ragingdeath:BAAALgAECgQJAwAAAA==.Ragingson:BAAALgAECgQJAgAAAA==.Rainakamugi:BAAALgAECgQJBAABLgAECgUJBQALAAAAAA==.Rakko:BAAALgAECgEJAQAAAA==.Ralphanir:BAABLgAECn8bAAIZAAcJIxdfFgC0AQAZAAcJIxdfFgC0AQAAAA==.Rangi:BAAALgADCgcJCwAAAA==.Raskreia:BAAALgAECgQJBgAAAA==.Rastalarimon:BAAALgAECgIJAwAAAA==.Ravenclaw:BAAALgADCgEJAQAAAA==.Rawdogging:BAAALgADCgYJCgAAAA==.Rawrxd:BAAALgAECgYJCgAAAA==.Raygyu:BAAALgAECgQJBgABLgAECgcJKAAFAOYkAA==.Rayshoots:BAABLgAECn8oAAQFAAcJ5iT6FwB5AgAFAAcJ5iT6FwB5AgAjAAYJOBV6DgB2AQAGAAEJhgAbnAAMAAAAAA==.',
Re='Realkaleo:BAAALgAECgcJCgAAAA==.Rebekil:BAABLgAECn8WAAMWAAcJzQgsSAAMAQAWAAcJzQgsSAAMAQAcAAYJPQRPhQDMAAAAAA==.Rediline:BAAALgAECgUJCwAAAA==.Rekkfest:BAAALgADCgMJAwAAAA==.Rexari:BAAALgADCgkJFQAAAA==.Rezmae:BAAALgAECgQJBAAAAA==.Reznàp:BAAALgADCgUJBQAAAA==.',
Rh='Rheba:BAAALgADCgEJAQAAAA==.',
Ri='Rinrin:BAAALgADCgYJBgAAAA==.Riot:BAAALgAECgEJAgABLgAFFAQJDgAEAPAfAA==.Risotto:BAAALgADCgcJBwAAAA==.',
Ro='Roron:BAAALgAECgIJCAAAAA==.Rothgar:BAAALgADCgEJAQAAAA==.Roxy:BAAALgAECgUJBQAAAA==.',
Rr='Rrainmann:BAAALgADCgEJAQAAAA==.',
Ru='Rubmaps:BAAALgADCgUJBQAAAA==.',
Ry='Ryujin:BAAALgADCggJDwAAAA==.',
Sa='Sabi:BAAALgAECgYJEgAAAA==.Sadboy:BAAALgAECgUJCQAAAA==.Sadface:BAAALgAECgQJBAAAAA==.Safetyspork:BAAALgAECgEJAwABLgAECgcJAQALAAAAAA==.Sagë:BAAALgAECgQJCwAAAA==.Salamasina:BAAALgADCgEJAQAAAA==.Salsa:BAAALgAECgEJAQAAAA==.Samunzo:BAAALgADCgQJBQAAAA==.',
Sc='Schobe:BAAALgADCgEJAgABLgAECgIJAwALAAAAAA==.Schönen:BAAALgAECgYJEAAAAA==.Scojo:BAAALgAECgEJAQAAAA==.Scârecrow:BAAALgAECgYJEwAAAA==.',
Se='Sehtherria:BAAALgAECgEJAQAAAA==.Seishouu:BAAALgADCgUJBQAAAA==.Sejien:BAABLgAECn8VAAMIAAYJjRpVJwCRAQAIAAYJjRpVJwCRAQAJAAEJAAD8dQAvAAAAAA==.Senjou:BAAALgAECgIJAgAAAA==.Sermet:BAAALgADCgcJCgABLgAECgcJFgAOAAwfAA==.Serous:BAABLgAECn8gAAIHAAcJAB0wDgDRAQAHAAcJAB0wDgDRAQAAAA==.Setal:BAACLgAFFH8JAAMCAAMJzxMmAgAIAQACAAMJzxMmAgAIAQABAAIJtgavHACLAAAuAAQKfyEAAwEACAnjG1oPAIECAAEACAnlGloPAIECAAIACAkTGFcPAOUBAAAA.Sevrik:BAABLgAECn8jAAIIAAgJ/BvtEAAeAgAIAAgJ/BvtEAAeAgAAAA==.',
Sh='Shadowbruin:BAAALgADCgYJBgAAAA==.Shammycammy:BAAALgAECgQJCAAAAA==.Shaoling:BAAALgADCgEJAQAAAA==.Sharadra:BAAALgAECgYJCAAAAA==.Shecklethief:BAAALgAECgYJDAAAAA==.Shimmyx:BAAALgADCgYJDgAAAA==.Shinizokonai:BAAALgADCgQJBAAAAA==.Shinydude:BAAALgAECgMJBgAAAA==.Shogunz:BAAALgAECgMJAwAAAA==.Shroudedmoon:BAACLgAFFH8OAAIkAAUJYCHoAACFAQAkAAUJYCHoAACFAQAuAAQKfxgAAyQACAlBJJwBAAYDACQACAlBJJwBAAYDACIABAlzGQgJAOkAAAAA.Shàmshii:BAAALgADCgIJAgAAAA==.',
Si='Silk:BAABLgAECn8VAAMkAAYJyRJyBgBLAQAkAAYJyRJyBgBLAQASAAEJ+QdxXwA3AAAAAA==.Sinapaladin:BAAALgAECgYJDAAAAA==.Sinavyr:BAAALgADCgMJAwAAAA==.',
Sk='Skroh:BAAALgADCgEJAQAAAA==.Skwsham:BAABLgAECn8WAAIaAAkJXRnnBwAiAgAaAAkJXRnnBwAiAgAAAA==.',
Sl='Slabbcrakle:BAAALgADCgcJCgAAAA==.Slabbhammer:BAABLgAECn8XAAIRAAcJTRr/KgCWAQARAAcJTRr/KgCWAQAAAA==.Slappers:BAAALgADCgIJAgAAAA==.Slaykanit:BAAALgAECgQJBQAAAA==.',
Sm='Smooshednewt:BAAALgAECgQJDwAAAA==.',
Sn='Sneakyknight:BAAALgAECgcJEQAAAA==.',
So='Sobaley:BAAALgADCgQJBAAAAA==.Soggysausage:BAAALgAECgYJBwAAAA==.Sohvar:BAAALgAECgYJCwAAAA==.Sophira:BAABLgAECn8ZAAIWAAgJmxQeFwBGAQAWAAgJmxQeFwBGAQAAAA==.',
Sp='Sparkels:BAAALgADCgYJBgAAAA==.Spectre:BAAALgAECgEJAQABLgAFFAQJDgAEAPAfAA==.Spehk:BAAALgADCgcJDgABLgAECggJGwASALcVAA==.Speknawz:BAABLgAECn8bAAISAAgJtxVHCwC0AQASAAgJtxVHCwC0AQAAAA==.Splatzill:BAAALgAECgUJCAABLgAECggJGQAZAJwVAA==.Spoiledangel:BAABLgAECn8dAAIPAAcJgh2KCgD+AQAPAAcJgh2KCgD+AQAAAA==.Spookyhallow:BAABLgAECn8YAAIPAAgJ2wsCMgB4AQAPAAgJ2wsCMgB4AQAAAA==.Springz:BAABLgAFFH8bAAIeAAcJph0zAQBAAgAeAAcJph0zAQBAAgAAAA==.',
St='Starryniight:BAABLgAECn8iAAIIAAcJ/whTQQAuAQAIAAcJ/whTQQAuAQAAAA==.Stereodh:BAABLgAECn8dAAIOAAcJ/RYwIAByAQAOAAcJ/RYwIAByAQAAAA==.',
Su='Suetang:BAAALgAECgQJBAAAAA==.Supanova:BAAALgAECgYJDQAAAA==.Surwick:BAABLgAECn8nAAIgAAgJqxCECQBxAQAgAAgJqxCECQBxAQAAAA==.Sussybaka:BAAALgADCgUJBQAAAA==.',
Sv='Svelus:BAACLgAFFH8FAAIRAAUJxhrGCwBbAQARAAUJxhrGCwBbAQAuAAQKfxQAAhEABgkzI3g7ADYCABEABgkzI3g7ADYCAAEuAAUUBQkOACQAYCEA.',
Sw='Swangin:BAAALgADCgkJCQAAAA==.Swingin:BAABLgAECn8UAAIgAAcJaAuEIgD0AAAgAAcJaAuEIgD0AAAAAA==.Swishers:BAAALgAECgUJBgAAAA==.',
Sy='Synapticvoid:BAAALgAECgYJDwAAAA==.',
['Sï']='Sïxx:BAAALgADCgMJAwAAAA==.',
Ta='Tanurhide:BAAALgAECgEJAgAAAA==.Tapdat:BAACLgAFFH8KAAMIAAMJ6QuZNADVAAAIAAMJ6QuZNADVAAAJAAEJwg7pFQBTAAAuAAQKfyQAAwkACAlTHVgLAAsCAAkABwl8GVgLAAsCAAgABwl2H9ZIAPABAAAA.Tarram:BAAALgAECgYJCAAAAA==.Tartin:BAABLgAECn8aAAIWAAgJ0x9XDgC4AgAWAAgJ0x9XDgC4AgAAAA==.Taurenmill:BAAALgAFFAMJAwAAAA==.',
Te='Teapsy:BAAALgAECgcJDwAAAA==.Techi:BAAALgAECgQJBAAAAA==.Teener:BAAALgADCgQJBAAAAA==.Temres:BAABLgAECn8WAAQOAAcJDB+nDAAXAgAOAAcJDB+nDAAXAgAMAAUJKxRaFQABAQANAAEJfgbUdQAvAAAAAA==.Tendermulva:BAABLgAECn8gAAIKAAgJ0glXCADFAQAKAAgJ0glXCADFAQAAAA==.Tentoestwo:BAAALgAECgYJCgAAAA==.Tenzzo:BAAALgAECgUJBQAAAA==.Terekk:BAAALgADCgcJEwAAAA==.Terna:BAAALgADCgYJBwAAAA==.Tevashi:BAAALgAECgYJCwAAAA==.',
Th='Thannin:BAAALgAECgMJBgAAAA==.Tharekon:BAAALgAFFAEJAgAAAA==.Thedrink:BAAALgAECgEJAgAAAA==.Thermox:BAAALgAECgYJBwAAAA==.Thesauce:BAACLgAFFH8PAAIfAAQJ5SMmAQCnAQAfAAQJ5SMmAQCnAQAuAAQKfyMAAh8ACQm+JGACAHgDAB8ACQm+JGACAHgDAAAA.Thesmallman:BAAALgADCgcJDgAAAA==.Thexcurse:BAAALgADCgcJBwAAAA==.Thimo:BAAALgADCgIJAgABLgAECgQJBgALAAAAAA==.Thrikal:BAABLgAECn8fAAINAAgJ2BTwGwDhAQANAAgJ2BTwGwDhAQAAAA==.Throh:BAAALgADCgEJAQAAAA==.Thugd:BAAALgAECgYJDgAAAA==.',
Ti='Tiadalma:BAAALgAECgEJAQAAAA==.Tiek:BAABLgAECn8lAAIHAAgJHBL9DgDIAQAHAAgJHBL9DgDIAQAAAA==.Tindissa:BAAALgAECgMJAwAAAA==.Tivis:BAABLgAECn8aAAIJAAgJywXKCgD3AAAJAAgJywXKCgD3AAAAAA==.',
To='Toastydemon:BAABLgAECn8ZAAIOAAgJcxITGQCgAQAOAAgJcxITGQCgAQAAAA==.Tokedope:BAAALgAECgUJCwAAAA==.Tomoe:BAAALgADCgkJCQAAAA==.Tomsmg:BAAALgAFFAIJAwAAAA==.Tonen:BAABLgAECn8XAAIHAAcJEhRBKgD1AAAHAAcJEhRBKgD1AAAAAA==.Toofs:BAAALgAECgYJEAAAAA==.Torno:BAAALgAECgEJAQAAAA==.Toxifay:BAAALgAECgMJAwAAAA==.Toywar:BAAALgADCgcJBgAAAA==.',
Ts='Tsilatra:BAAALgAECgQJBAAAAA==.',
Tu='Tufluk:BAABLgAECn8ZAAINAAcJlBYGDwBKAQANAAcJlBYGDwBKAQAAAA==.Tuktirey:BAAALgAECgEJAQAAAA==.',
Tw='Twelevepeers:BAAALgAECgQJBAAAAA==.Twigs:BAAALgAECgkJCAAAAA==.',
['Tì']='Tìõ:BAABLgAECn8kAAIBAAgJ7hPIGAAJAgABAAgJ7hPIGAAJAgAAAA==.',
['Tô']='Tôms:BAAALgAECggJEwAAAA==.',
['Tö']='Töms:BAAALgADCgYJCAAAAA==.',
Ud='Udderlegend:BAAALgADCgcJEAAAAA==.',
Ug='Ughtismo:BAAALgADCgYJBgAAAA==.',
Ul='Ulrikan:BAAALgAECgEJAQAAAA==.Ultarok:BAAALgAECgYJCAAAAA==.',
Un='Undeadban:BAAALgAECgEJAQAAAA==.Unfiltered:BAAALgAECgQJBgAAAA==.Unwanted:BAAALgAECgYJEQAAAA==.',
Up='Upstream:BAAALgADCgYJCwAAAA==.',
Us='Usagiknight:BAAALgADCgEJAQAAAA==.Ushii:BAAALgAECgMJBgAAAA==.',
Va='Vaelindar:BAAALgADCgUJBgAAAA==.Vakarians:BAAALgADCgYJCQAAAA==.Vakkd:BAAALgADCgIJAgAAAA==.Valei:BAAALgAECgQJBAAAAA==.Valor:BAACLgAFFH8OAAIEAAQJ8B/yDgBzAQAEAAQJ8B/yDgBzAQAuAAQKfx0AAwQACQnbHqEgAL8CAAQACAlIIqEgAL8CACUAAQneBhgPAEYAAAAA.Vampirevic:BAAALgAECgYJBgAAAA==.Vansanssra:BAAALgADCgEJAQAAAA==.Varcoh:BAABLgAECn8kAAMPAAgJsA7XEgCDAQAPAAgJsA7XEgCDAQAdAAIJUgQRWgBQAAAAAA==.',
Ve='Velixar:BAAALgAECgEJAQAAAA==.Veloxen:BAAALgAFFAEJAQAAAA==.Venthyr:BAAALgADCgEJAQABLgAFFAQJDgAEAPAfAA==.Verikost:BAAALgADCgEJAQAAAA==.',
Vi='Vinda:BAABLgAECn8nAAIdAAkJBhRLBgAsAgAdAAkJBhRLBgAsAgAAAA==.',
Vl='Vladious:BAABLgAECn8dAAQIAAcJwh48FwDtAQAIAAYJnh48FwDtAQAJAAIJvB1TSACWAAAKAAEJAABvKABQAAAAAA==.',
Vy='Vynd:BAAALgAECgYJEwAAAA==.Vynllandis:BAAALgADCgMJAwAAAA==.',
Wa='Wallo:BAABLgAECn8pAAIHAAgJQRIQDwDHAQAHAAgJQRIQDwDHAQAAAA==.Warglaivez:BAAALgAECgQJDQAAAA==.Washedbolt:BAAALgAFFAEJAQAAAA==.Washedpyro:BAAALgAECgcJCQAAAA==.Watchscotch:BAAALgADCgkJFQABLgAECgcJEgALAAAAAA==.Wayfairkid:BAAALgAECgYJCwAAAA==.',
We='Werken:BAAALgAECgIJBAAAAA==.',
Wh='Whyetee:BAACLgAFFH8FAAISAAIJOw8bFACsAAASAAIJOw8bFACsAAAuAAQKfy0AAxIACAlMI74LANoCABIACAkLIr4LANoCACQAAglKImwUALYAAAAA.',
Wi='Willywonkas:BAAALgADCgkJDwAAAA==.Windowlicker:BAAALgADCgEJAQAAAA==.Wineo:BAABLgAECn8jAAIWAAgJeiA8BwAkAgAWAAgJeiA8BwAkAgAAAA==.Wizzwee:BAAALgAECgIJAgABLgAECggJGgANAK8cAA==.',
Wo='Woa:BAAALgAECgEJAQAAAA==.Wonder:BAAALgAECgIJAwAAAA==.Woofwoofwoof:BAABLgAECn8eAAIQAAcJ6gudUwA5AQAQAAcJ6gudUwA5AQAAAA==.Worn:BAAALgADCgQJBAAAAA==.Worthlesshoe:BAAALgADCgIJBAABLgADCgUJBQALAAAAAA==.',
Wr='Wraithwok:BAAALgADCgYJBgAAAA==.Wrld:BAAALgAECgEJAQAAAA==.',
['Wà']='Wàll:BAAALgADCgMJAwAAAA==.',
['Wå']='Wåffle:BAAALgADCgMJAwAAAA==.',
Xa='Xasther:BAABLgAECn8jAAIRAAgJlCT0BADMAgARAAgJlCT0BADMAgAAAA==.Xav:BAAALgADCgkJDAAAAA==.',
Xe='Xenophilius:BAAALgAECgcJDgAAAA==.Xeruk:BAAALgAECgYJCgAAAA==.',
Ya='Yasha:BAAALgADCgEJAQABLgAECgUJCQALAAAAAA==.',
Ye='Yearsfade:BAAALgADCgMJAwAAAA==.',
Yu='Yuka:BAAALgADCgUJBAAAAA==.Yulok:BAAALgAECgQJBQABLgAFFAcJDgAaAMAhAA==.Yumí:BAABLgAECn8dAAMjAAgJ4BzNCQBAAgAjAAgJ4BzNCQBAAgAGAAEJywnEiQAxAAAAAA==.Yurgling:BAAALgAECgMJBAAAAA==.',
Za='Zaberra:BAAALgADCgMJAwABLgAECggJGQAWAJsUAA==.Zanarkand:BAAALgAECgYJCQAAAA==.Zarivara:BAAALgAECgEJAgAAAA==.',
Ze='Zepha:BAAALgADCgIJAQAAAA==.',
Zi='Zib:BAAALgAECgkJBgAAAA==.Zibrina:BAAALgADCgUJCAAAAA==.Zieg:BAAALgADCgIJAgABLgAECgkJDwALAAAAAA==.Zina:BAAALgAECgEJAQAAAA==.Zitish:BAAALgADCgEJAQAAAA==.',
Zo='Zomby:BAAALgAECgUJAwAAAA==.',
Zu='Zuko:BAAALgADCgEJAQAAAA==.',
['Ço']='Çookiemonstr:BAAALgADCgkJDwAAAA==.',
['Ëy']='Ëyë:BAAALgAFFAEJAQAAAA==.',
['Ñi']='Ñina:BAAALgAECgUJCQAAAA==.',
['ßu']='ßutterworth:BAAALgADCgEJAQAAAA==.',
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

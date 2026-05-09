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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Priest-Holy','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Priest-Shadow','Warlock-Demonology','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Paladin-Retribution','Monk-Windwalker','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Priest-Discipline','Paladin-Protection','Paladin-Holy','Druid-Guardian','Rogue-Outlaw','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarix:BAAALgAECggJCAAAAA==.',
Ae='Aedrelyn:BAAALgAECgcJBwAAAA==.Aegia:BAABLgAECn8WAAMBAAYJlxBPNgAxAQABAAYJlxBPNgAxAQACAAMJTQGBgABFAAAAAA==.Aendillan:BAAALgAECgYJDwAAAA==.',
Af='Affonasei:BAABLgAECn8aAAIDAAcJkQhuWAA2AQADAAcJkQhuWAA2AQAAAA==.',
Ak='Akashi:BAAALgAECgMJAwABLgAFFAMJCAAEAKYYAA==.',
Al='Alladorn:BAAALgADCgEJAQAAAA==.',
An='Ancbow:BAAALgADCgUJBQAAAA==.Angyll:BAAALgADCgEJAQAAAA==.Annaborshen:BAAALgADCgcJCgAAAA==.Antoccino:BAABLgAECn8VAAIFAAcJyRtEGACXAQAFAAcJyRtEGACXAQAAAA==.',
Ar='Aragorno:BAABLgAECn8iAAMGAAgJwBPGJADCAQAGAAgJwBPGJADCAQAHAAQJRAYNJADZAAAAAA==.Araziel:BAAALgAECgMJBAAAAA==.Arcturen:BAAALgAECgYJDgAAAA==.Arenthal:BAAALgAECgQJBQAAAA==.Artemisha:BAAALgADCgEJAQABLgAECgMJAwAIAAAAAA==.Arturaan:BAAALgADCgYJBwAAAA==.',
As='Ashalana:BAAALgAECgcJEAAAAA==.Asheby:BAAALgAECgEJAQABLgAECgcJGQAJAFsdAA==.Ashiera:BAABLgAECn8hAAMKAAcJcgP2lADpAAAKAAcJcgP2lADpAAALAAEJ7AHvIgATAAAAAA==.',
At='Atomic:BAAALgAECgMJBgAAAA==.',
Au='Ausuna:BAAALgAECgUJBQAAAA==.',
Aw='Awhiteboy:BAAALgAECgcJDgABLgAECgkJKgAEAJcfAA==.',
Az='Azeral:BAAALgADCgYJBgAAAA==.Azylstrid:BAAALgAECgQJBAAAAA==.',
Ba='Babyshred:BAAALgADCggJEwAAAA==.Badonka:BAAALgAECgQJBAABLgAECggJKAAMADcbAA==.Bahaana:BAAALgADCgYJCAAAAA==.Balentine:BAABLgAECn8XAAMJAAYJhRLESQASAQAJAAUJIRLESQASAQANAAUJxwP2RwDBAAAAAA==.Bananasloth:BAAALgAECgcJEQABLgAFFAkJJwAOAEQbAA==.Banjali:BAAALgADCgMJAwAAAA==.Banostraza:BAABLgAECn8oAAIMAAgJNxtdCQA3AgAMAAgJNxtdCQA3AgAAAA==.Baspir:BAABLgAECn8mAAIPAAgJBRfLFgCGAQAPAAgJBRfLFgCGAQAAAA==.',
Be='Belly:BAAALgAECgIJAgABLgAECgkJKgAEAJcfAA==.Belrae:BAABLgAECn8kAAIQAAkJdBEcHQDaAQAQAAkJdBEcHQDaAQAAAA==.Belrinthe:BAAALgAECgcJBwAAAA==.Bezieck:BAABLgAECn8fAAINAAYJVg4SJQAbAQANAAYJVg4SJQAbAQAAAA==.',
Bi='Bigdawg:BAAALgAECgcJBgAAAA==.Bigollock:BAAALgAECgEJBAAAAA==.Billyhikz:BAABLgAECn8bAAIKAAgJxAksWQBjAQAKAAgJxAksWQBjAQAAAA==.',
Bl='Bloodarrow:BAAALgAECgMJBAAAAA==.',
Bo='Bobino:BAAALgADCgEJAQAAAA==.Bockchi:BAAALgAECgYJEgAAAA==.Bonegavel:BAAALgAECgQJBgAAAA==.Bookhuntress:BAABLgAECn8cAAMRAAcJ3Rs+JgAfAgARAAcJ3Rs+JgAfAgAPAAMJGBldLQDhAAAAAA==.',
Br='Branaxe:BAAALgAECgcJCQABLgAECgkJBQAIAAAAAA==.Brandisheer:BAAALgAECgUJBQAAAA==.Branthor:BAAALgADCgIJAgAAAA==.Brewdeez:BAABLgAECn8qAAISAAkJHh6wAwC+AgASAAkJHh6wAwC+AgAAAA==.Brewzer:BAACLgAFFH8LAAITAAMJKQUSGwClAAATAAMJKQUSGwClAAAuAAQKfx8AAhMACAmEE8kXAJQBABMACAmEE8kXAJQBAAAA.Brint:BAAALgAECgQJCAAAAA==.Brokenhorn:BAAALgADCgYJGAAAAA==.Bronad:BAACLgAFFH8VAAIKAAQJIyIGFACSAQAKAAQJIyIGFACSAQAuAAQKfxwAAgoACAkXJc8jAOMCAAoACAkXJc8jAOMCAAAA.Broomhandle:BAAALgAECggJDwAAAA==.',
Bu='Bubbletea:BAAALgAECgYJDAAAAA==.Bumbushka:BAACLgAFFH8NAAIUAAQJERo6CABfAQAUAAQJERo6CABfAQAuAAQKfxQAAxQABwkVHickADUCABQABwkVHickADUCABUAAgnfGNQrAJUAAAAA.Burinn:BAAALgAECgEJAQABLgAECggJJAAJALkOAA==.',
Ca='Caeus:BAABLgAECn8XAAIDAAcJzyOMEgBnAgADAAcJzyOMEgBnAgAAAA==.Cam:BAABLgAECn8uAAIKAAkJkiV+AgBeAwAKAAkJkiV+AgBeAwAAAA==.Cardo:BAAALgADCgUJBQABLgAFFAUJEQAWAEsbAA==.Care:BAABLgAECn8ZAAIKAAkJjAwWiADBAQAKAAkJjAwWiADBAQAAAA==.Carolinabele:BAAALgAECgcJBAAAAA==.Carrowend:BAAALgADCgcJBwAAAA==.Cauud:BAAALgAECgMJBAAAAA==.',
Cb='Cbd:BAAALgADCgcJCAAAAA==.',
Ch='Charmed:BAAALgADCgQJBAAAAA==.Chelan:BAABLgAECn8kAAMJAAgJuQ59FwCVAQAJAAgJuQ59FwCVAQANAAgJxQKXLADpAAAAAA==.Chilljaeden:BAAALgAECgUJCAAAAA==.Chizuko:BAAALgADCgMJAwAAAA==.',
Ci='Cigs:BAAALgAECgYJBgABLgAFFAYJFwAKAAUeAA==.Cinnabunz:BAAALgAECgcJDgAAAA==.',
Cl='Cleaväge:BAAALgADCgYJBgAAAA==.Cloudlol:BAAALgAECgQJBgAAAA==.Clueless:BAAALgADCgMJAwAAAA==.',
Cn='Cnova:BAAALgAECgQJBwABLgAECgYJHAAXANweAA==.',
Co='Codythedead:BAAALgAECgIJAwAAAA==.Compadre:BAABLgAECn8UAAQYAAcJOhzFHQDrAQAYAAcJLRrFHQDrAQASAAQJUiAiRAAyAQATAAUJURE2RADMAAAAAA==.Contekst:BAABLgAECn8XAAMRAAcJphGFRAABAQARAAYJixCFRAABAQAPAAcJwwYcMQDNAAAAAA==.Coolsbeans:BAAALgAECgQJBQAAAA==.Coraf:BAACLgAFFH8YAAIBAAUJ0iFQAwDxAQABAAUJ0iFQAwDxAQAuAAQKfzIAAgEACQnUI8ABAHQDAAEACQnUI8ABAHQDAAAA.Cosmon:BAAALgADCgcJBwAAAA==.',
Cr='Crankzilla:BAAALgADCggJFgAAAA==.Cravix:BAAALgADCgEJAQAAAA==.Cruoris:BAABLgAECn8bAAIZAAcJww3yBwBcAQAZAAcJww3yBwBcAQAAAA==.',
Cu='Cunfuzed:BAAALgAECgEJAQAAAA==.Cuvier:BAAALgAECgYJDwAAAA==.',
Da='Daddle:BAABLgAECn8aAAQOAAkJ5SE2AwAgAwAOAAkJ5SE2AwAgAwAaAAEJAAAYGwAAAAAbAAEJAACfNQAAAAAAAA==.Daemonxblack:BAAALgAECgEJAQAAAA==.Daeth:BAAALgAECgIJAgAAAA==.Dahaxors:BAABLgAECn8iAAIDAAgJRBqQGgArAgADAAgJRBqQGgArAgAAAA==.Danak:BAAALgADCgEJAQAAAA==.Darthwader:BAAALgAECgUJCAAAAA==.Dascrazy:BAAALgAECgUJEgAAAA==.',
De='Deadlyfrosty:BAAALgAECgMJBAAAAA==.Debixie:BAACLgAFFH8MAAIZAAMJsR86AwAmAQAZAAMJsR86AwAmAQAuAAQKfx8AAhkACQmKIk0BACUDABkACQmKIk0BACUDAAAA.Demisi:BAAALgAECgcJEwAAAA==.Demoness:BAABLgAECn8WAAIQAAgJRCEtCQCSAgAQAAgJRCEtCQCSAgAAAA==.Derangedsp:BAAALgADCgkJCQABLgAFFAkJJwAOAEQbAA==.Destorr:BAAALgADCgQJBAAAAA==.',
Di='Diasundra:BAABLgAECn8pAAIGAAgJ3B9ODgDKAgAGAAgJ3B9ODgDKAgAAAA==.Digiornos:BAABLgAECn8WAAIOAAgJehZ4XQCwAQAOAAgJehZ4XQCwAQAAAA==.',
Dj='Djyinn:BAAALgADCgcJCgAAAA==.',
Do='Doorknob:BAAALgAECgYJCQAAAA==.Dottingyou:BAACLgAFFH8TAAIOAAUJDRdXEgBTAQAOAAUJDRdXEgBTAQAuAAQKfykAAw4ACQlvHxkZAL4CAA4ACAlvHxkZAL4CABsAAwlMHzQsAA4BAAAA.',
Dr='Draenei:BAAALgAECgEJAQAAAA==.Draeziq:BAAALgAECgEJAgABLgAECgIJBAAIAAAAAA==.Dragonpo:BAAALgADCgEJAQAAAA==.Drakkonde:BAAALgAECgYJDwAAAA==.Dravin:BAAALgADCgYJBgAAAA==.Drazarth:BAAALgAECgUJDQAAAA==.Drransom:BAAALgADCgEJAQAAAA==.Dryan:BAAALgAECgMJBAAAAA==.Dryon:BAABLgAECn8YAAIcAAcJlRU1DgB/AQAcAAcJlRU1DgB/AQAAAA==.',
Du='Duo:BAABLgAECn8rAAIGAAkJFhMTGwD7AQAGAAkJFhMTGwD7AQAAAA==.Duragon:BAABLgAECn8oAAQMAAgJZBWhDwDZAQAMAAgJZBWhDwDZAQAdAAYJPwf9GAC7AAAeAAcJHAWmDgCfAAAAAA==.',
['Dí']='Díznutz:BAAALgAECggJEwAAAA==.',
Em='Emilia:BAAALgAECggJDAAAAA==.',
En='Endressa:BAABLgAECn8gAAMfAAkJ+wfXEwCkAQAfAAkJ+wfXEwCkAQANAAEJFAxTVAAxAAAAAA==.English:BAABLgAECn8pAAIKAAkJmRkYGABbAgAKAAkJmRkYGABbAgAAAA==.',
Er='Erelios:BAABLgAECn8VAAIgAAcJoBkLDQBpAQAgAAcJoBkLDQBpAQAAAA==.',
Eu='Eureka:BAEALgADCgIJAgABLgAECgkJJwAhAI0lAA==.',
Ev='Evangelina:BAACLgAFFH8YAAMMAAYJiRxfBADJAQAMAAYJiRxfBADJAQAeAAEJygr1CQBTAAAuAAQKfx4AAwwACAkpI70GABEDAAwACAkNI70GABEDAB4ABgmRI7oPAN8BAAAA.Everlight:BAAALgAECgQJBAABLgAECgcJGwAiAOkSAA==.',
Ey='Eyezoffury:BAAALgAECgIJAgAAAA==.',
Fa='Faddeyshnek:BAABLgAECn8oAAIGAAkJQxboEgA5AgAGAAkJQxboEgA5AgAAAA==.Fatgirljuice:BAAALgADCgMJAwABLgAFFAYJGAAMAIkcAA==.',
Fe='Feliseda:BAAALgADCgkJCwAAAA==.Felysambre:BAAALgADCgkJKwAAAA==.',
Fi='Filibertos:BAAALgAECgQJBAABLgAFFAYJFwAKAAUeAA==.Fish:BAACLgAFFH8TAAINAAUJwyYDAwC/AQANAAUJwyYDAwC/AQAuAAQKfysAAg0ACAlmJlcCAIwDAA0ACAlmJlcCAIwDAAEuAAUUBwkcAA0ASiUA.',
Fl='Flight:BAACLgAFFH8IAAMEAAMJphiPFACsAAAEAAMJKRGPFACsAAAjAAIJWg1+BgCHAAAuAAQKfxkAAwQACAmmG3UUAG8CAAQACAn3GnUUAG8CABkAAQkBDikeADwAAAAA.Fluxyouup:BAABLgAECn8fAAMBAAkJmgj+KwBoAQABAAkJmgj+KwBoAQACAAYJ3gTnPwCqAAAAAA==.',
Fo='Follow:BAAALgAECgQJBQAAAA==.Footfinger:BAAALgAFFAMJAwABLgAFFAQJDQAUABEaAA==.Forsynth:BAAALgAECggJEwAAAA==.',
Ge='Gewitt:BAABLgAECn8qAAMBAAkJgh5iBwC4AgABAAkJgh5iBwC4AgACAAcJ9RXXKADNAQAAAA==.',
Gg='Ggiven:BAAALgAECgYJBwAAAA==.',
Gn='Gnow:BAAALgADCgEJAQAAAA==.',
Gr='Grabomage:BAACLgAFFH8YAAIKAAUJxiUODwCxAQAKAAUJxiUODwCxAQAuAAQKfz8AAgoACQmrJVQDAMoDAAoACQmrJVQDAMoDAAAA.Grag:BAAALgADCgMJBQAAAA==.Grapekoolaid:BAAALgAECgYJDwAAAA==.Grapesloth:BAAALgAECgQJBAABLgAFFAkJJwAOAEQbAA==.Grazienne:BAAALgADCgEJAQAAAA==.Gretchen:BAAALgADCgUJBQAAAA==.Grif:BAAALgADCgMJAwAAAA==.Grilm:BAABLgAECn8qAAIiAAkJ9R7nAQCwAgAiAAkJ9R7nAQCwAgAAAA==.Grimbaine:BAABLgAECn8UAAIXAAcJYiEGFgBKAgAXAAcJYiEGFgBKAgAAAA==.Grimbane:BAAALgAECgMJBAAAAA==.Gryphin:BAAALgADCgcJBwAAAA==.',
Gu='Gulmok:BAAALgADCgUJDQAAAA==.Gumbles:BAAALgAECgYJEwAAAA==.Gurney:BAABLgAECn8hAAIhAAgJ+hJJHQCdAQAhAAgJ+hJJHQCdAQAAAA==.Guzfu:BAABLgAECn8UAAIYAAcJgg0NJQADAQAYAAcJgg0NJQADAQAAAA==.',
Gw='Gwenory:BAAALgADCgEJAQAAAA==.',
Gy='Gying:BAABLgAECn8ZAAMSAAYJkBjsHQBFAQASAAYJDBfsHQBFAQAYAAUJcg/4PwAZAQAAAA==.',
Ha='Hanjabs:BAAALgAECgQJBwAAAA==.Hanmine:BAAALgAECgYJDQAAAA==.Hannie:BAAALgADCgEJAQAAAA==.Hatike:BAAALgAECgEJAQAAAA==.',
He='Heatseeka:BAABLgAECn8XAAIBAAgJDg69LQBeAQABAAgJDg69LQBeAQAAAA==.Hexxiz:BAAALgADCgIJAgABLgAECgkJJAARAAckAA==.',
Hi='Hiphopinator:BAABLgAECn8hAAMUAAcJEiNRDQAXAgAUAAcJpx9RDQAXAgAcAAUJsiUsCwC3AQAAAA==.',
Ho='Holydeath:BAAALgAECgEJAQAAAA==.Holyshock:BAAALgAECgYJCwAAAA==.Holyterror:BAAALgADCgEJAQAAAA==.',
Hy='Hydril:BAAALgADCgEJAQAAAA==.',
['Hø']='Hødør:BAAALgADCgIJAQAAAA==.',
Ia='Iamcro:BAAALgAECgQJBAAAAA==.Ianthe:BAAALgAECgYJDgAAAA==.',
Ib='Iboga:BAAALgADCgUJBQAAAA==.Ibrahimovic:BAABLgAECn8jAAMbAAcJHCIHBgCVAQAbAAUJSyMHBgCVAQAOAAQJARz6RQBXAQAAAA==.',
Ig='Ignitecro:BAAALgADCgUJBQAAAA==.',
Ih='Iheal:BAAALgADCgcJCgAAAA==.',
Im='Imauggin:BAAALgADCgYJBgAAAA==.Imbobbymom:BAAALgAECgEJAgABLgAFFAYJGAAMAIkcAA==.Imhim:BAAALgAECgEJAQAAAA==.',
In='Inafume:BAAALgAECgEJAgAAAA==.Infoxicated:BAAALgAECgUJCgAAAA==.Inoxia:BAAALgAECgQJBgAAAA==.Intrépidice:BAAALgAECgMJAwAAAA==.',
Io='Iowastyle:BAABLgAECn8hAAMJAAgJZB5PBwB/AgAJAAgJZB5PBwB/AgAfAAMJlgx9QwCZAAAAAA==.',
Ix='Ixtabay:BAACLgAFFH8HAAMaAAMJ+RxoAQAbAQAaAAMJ+RxoAQAbAQAOAAEJlA0JewBFAAAuAAQKfyYABBoACQmmIN4BACsCABoACQmmIN4BACsCAA4ABQmfFT+ZACYBABsAAgm6EnlTAHQAAAAA.',
Ja='Jakobey:BAAALgAECgIJAgAAAA==.Jamurra:BAAALgAECgIJBAAAAA==.Jaylinn:BAABLgAECn8qAAIGAAkJuA3TIADXAQAGAAkJuA3TIADXAQAAAA==.Jazzmend:BAAALgADCgEJAQAAAA==.',
Jo='Jocko:BAAALgADCgYJBgAAAA==.Josie:BAABLgAECn8WAAIfAAcJUyOoDQBfAgAfAAcJUyOoDQBfAgAAAA==.',
Ju='Judgekoopa:BAABLgAECn8bAAIhAAYJ0x/+EAASAgAhAAYJ0x/+EAASAgAAAA==.',
Ka='Kaeiria:BAAALgAECgUJCgAAAA==.Kalaanri:BAAALgAECgYJDgAAAA==.Kaleberry:BAAALgAECgcJEwAAAA==.Kalyandra:BAAALgAECgYJDgAAAA==.Kalógeros:BAAALgADCgMJAwAAAA==.Kanra:BAAALgAECgMJAwABLgAECgYJGAAhAOgZAA==.Karkevon:BAAALgAECgYJDQAAAA==.Karlach:BAABLgAECn8UAAIUAAgJcBmWDgAFAgAUAAgJcBmWDgAFAgAAAA==.Karlachs:BAAALgADCgYJBwAAAA==.Karrla:BAAALgAECgUJBQAAAA==.Karumie:BAABLgAECn8lAAIBAAgJ9huGFAAQAgABAAgJ9huGFAAQAgAAAA==.Kateera:BAAALgAECgUJCgAAAA==.',
Ke='Keden:BAAALgADCgEJAQAAAA==.Keelivan:BAAALgAECgMJAwAAAA==.Kelivann:BAAALgADCgUJBQAAAA==.Keljaden:BAAALgAECgMJBgABLgAECggJHwAQAOciAA==.Kels:BAABLgAECn8fAAIQAAgJ5yLYCwBxAgAQAAgJ5yLYCwBxAgAAAA==.',
Kh='Kheyra:BAABLgAECn8bAAIiAAcJ6RJ0DwAQAQAiAAcJ6RJ0DwAQAQAAAA==.',
Ki='Kidashia:BAAALgAECgQJBAAAAA==.',
Ko='Kohnor:BAAALgADCgEJAQAAAA==.Kopi:BAAALgAECgEJAQABLgAECgcJFQAFAMkbAA==.Korlatt:BAABLgAECn8cAAQQAAcJxxV2NgBcAQAQAAcJFRN2NgBcAQAkAAIJdhnAEwCPAAAlAAEJUwsVcwAyAAAAAA==.Kowalabear:BAABLgAECn8pAAMmAAgJGCIxAQD+AgAmAAgJGCIxAQD+AgAFAAQJPwrzKwBuAAAAAA==.',
Kr='Kryptrix:BAAALgAECgQJBAAAAA==.Krìmzar:BAAALgADCggJCgABLgAECgYJFAAKADgXAA==.',
Kt='Kthanid:BAAALgAECgMJBAAAAA==.',
Ku='Kurston:BAABLgAECn8lAAIRAAgJ9xodEABVAgARAAgJ9xodEABVAgAAAA==.',
Ky='Kymakazie:BAAALgAECgYJBwAAAA==.',
['Kã']='Kãtniss:BAAALgADCgEJAQAAAA==.',
La='Laih:BAAALgAECggJEwAAAA==.Lathelinis:BAAALgAECgcJCAAAAA==.Layssara:BAAALgADCgMJAwAAAA==.',
Le='Leafbloom:BAAALgAECgEJAQAAAA==.Letmeout:BAAALgAECgEJAQAAAA==.Leyote:BAABLgAECn8bAAIBAAcJWQ+0MwA9AQABAAcJWQ+0MwA9AQAAAA==.',
Li='Liady:BAAALgADCgcJBwAAAA==.Lightshop:BAAALgADCgIJAQAAAA==.Linora:BAAALgAECgIJAQAAAA==.',
Lo='Lolabunny:BAABLgAECn8UAAMYAAYJZBoYNABRAQAYAAUJkxYYNABRAQASAAQJ+xkKRgAqAQABLgAECggJGAAFAOIiAA==.Lorianne:BAAALgADCgIJAgAAAA==.Lousseur:BAAALgADCgEJAgAAAA==.Lowdangle:BAABLgAECn8VAAIQAAcJjxRgLwB5AQAQAAcJjxRgLwB5AQAAAA==.',
Lu='Lulz:BAAALgAECgkJEwAAAA==.Lumini:BAAALgAECgYJDwAAAA==.Luminias:BAAALgAECgUJDQAAAA==.Luxroy:BAAALgAECgYJEQAAAA==.',
Ly='Lygma:BAABLgAECn8UAAIXAAcJ9wl7egD3AAAXAAcJ9wl7egD3AAAAAA==.Lynniebee:BAABLgAECn8fAAILAAgJJQxJAwCHAQALAAgJJQxJAwCHAQAAAA==.Lynntasha:BAAALgADCgkJCQAAAA==.',
Ma='Madalyn:BAAALgAECgcJEwAAAA==.Magdelyne:BAAALgAECgkJBQAAAA==.Magni:BAAALgAECgQJBQAAAA==.Makklehaney:BAAALgAECggJEwAAAA==.Mallaah:BAAALgADCgYJCgAAAA==.Malthorin:BAAALgADCgMJAwAAAA==.Marovingian:BAAALgAECggJEwAAAA==.Matthad:BAABLgAECn8VAAIBAAcJZRCQLgBZAQABAAcJZRCQLgBZAQAAAA==.Mazìkene:BAACLgAFFH8MAAIOAAMJMwl4SADIAAAOAAMJMwl4SADIAAAuAAQKfyEAAg4ACQkyFjEjAOABAA4ACQkyFjEjAOABAAAA.',
Mc='Mccone:BAAALgAECgMJBAAAAA==.Mcsluts:BAAALgAECgQJCwAAAA==.',
Me='Megadumb:BAAALgAECgQJBAABLgAFFAYJGAAMAIkcAA==.Melmirict:BAACLgAFFH8JAAIEAAMJrxPyEwD7AAAEAAMJrxPyEwD7AAAuAAQKfyAAAwQACQlCGS4KAP0BAAQACQlCGS4KAP0BABkAAwmAGpQSANkAAAAA.Meng:BAAALgADCgYJBgAAAA==.Merciala:BAABLgAECn8lAAIiAAgJ2hE1DABOAQAiAAgJ2hE1DABOAQAAAA==.',
Mi='Milyyanna:BAAALgADCgEJAQAAAA==.Minaby:BAAALgAECgYJEAABLgAECggJDwAIAAAAAA==.Mitochondria:BAAALgADCgQJBAAAAA==.',
Mo='Moddoxx:BAABLgAECn8bAAMOAAcJGRjHNwCGAQAOAAcJGRjHNwCGAQAaAAEJAAByHAAAAAAAAA==.Mohaxors:BAAALgADCgcJDwAAAA==.Moko:BAAALgADCgIJAgAAAA==.Mokopal:BAAALgADCgMJAwAAAA==.Mokøtrollz:BAABLgAECn8WAAMHAAgJSRx3CwDtAQAGAAYJKR0BKwAJAgAHAAgJqhN3CwDtAQAAAA==.Mommyjuice:BAAALgAECgYJBgABLgAFFAYJGAAMAIkcAA==.Monkle:BAABLgAECn8qAAIYAAgJOyLBAwC4AgAYAAgJOyLBAwC4AgAAAA==.Monkoku:BAAALgAECgQJBAABLgAFFAMJBgAEAEIeAA==.Moonsii:BAAALgAECgYJDgAAAA==.Mooroth:BAABLgAECn8jAAIcAAcJtBrvCQDTAQAcAAcJtBrvCQDTAQAAAA==.Morekk:BAAALgADCgYJBgAAAA==.Morozko:BAAALgAECgQJCwAAAA==.',
Mu='Muddler:BAABLgAECn8jAAIbAAcJ2AJQFACuAAAbAAcJ2AJQFACuAAAAAA==.Murgut:BAAALgAECgMJAwAAAA==.Muscuees:BAAALgADCgEJAQAAAA==.Mush:BAAALgADCgMJAwAAAA==.',
Na='Nadd:BAAALgAECgQJBwAAAA==.Naledi:BAABLgAECn8aAAIPAAcJOxDQHwA4AQAPAAcJOxDQHwA4AQAAAA==.Nancy:BAAALgAECgQJBAAAAA==.Naomas:BAABLgAECn8bAAIKAAcJwx2lLADvAQAKAAcJwx2lLADvAQAAAA==.Narella:BAABLgAECn8ZAAIKAAcJQRKvSwCFAQAKAAcJQRKvSwCFAQAAAA==.',
Ne='Negrido:BAABLgAECn8pAAMOAAkJtSXhBAD6AgAOAAgJfCLhBAD6AgAbAAMJNiWGJAA3AQAAAA==.Nei:BAABLgAECn8dAAIXAAcJRROGQwB7AQAXAAcJRROGQwB7AQAAAA==.Newt:BAAALgADCgUJBQAAAA==.Nezzarector:BAAALgAECgUJCwAAAA==.',
Ni='Nikem:BAABLgAECn8iAAMPAAcJDBUGFgCOAQAPAAcJDBUGFgCOAQAiAAEJ0wKQOwAPAAAAAA==.',
No='Noelle:BAAALgAECgQJCAAAAA==.Noraelyn:BAABLgAECn8hAAMhAAcJwx+GFwDRAQAhAAYJhyCGFwDRAQAXAAMJjwM74wBLAAAAAA==.Norelei:BAAALgAECgQJBAABLgAECgcJGwAiAOkSAA==.Noriyuki:BAABLgAECn8WAAIYAAYJdAH+UQBHAAAYAAYJdAH+UQBHAAAAAA==.Northside:BAAALgADCgQJBAABLgAFFAYJFwAKAAUeAA==.Notkorlatt:BAAALgADCgIJAgAAAA==.',
Nu='Nugatory:BAABLgAFFH8FAAMHAAMJfhtsDAAVAQAHAAMJfhtsDAAVAQAWAAEJwAG4HgA5AAABLgAECgYJBgAIAAAAAA==.',
Ny='Nyxahlia:BAAALgAECgYJEQAAAA==.',
Og='Ogkagìsttv:BAAALgAECgYJBwAAAA==.',
Ol='Olrong:BAABLgAECn8cAAIlAAcJBA+/EwBQAQAlAAcJBA+/EwBQAQAAAA==.',
Om='Omegâ:BAAALgADCgQJBAAAAA==.',
On='Onlypaws:BAAALgAECgYJEgAAAA==.',
Op='Opaalite:BAAALgAECgMJAwAAAA==.Opacuslupus:BAAALgAECgEJAQAAAA==.Oppcookies:BAAALgAECgYJCwABLgAECggJDAAIAAAAAA==.Oppressin:BAAALgADCggJDAABLgAECggJDAAIAAAAAA==.Oppshot:BAAALgAECggJDAAAAA==.',
Or='Orin:BAAALgADCgEJAQAAAA==.',
Os='Oshìe:BAABLgAECn8kAAIhAAkJbRxQDAC4AgAhAAkJbRxQDAC4AgAAAA==.',
Ov='Overdoom:BAABLgAECn8sAAMDAAkJ9RrQGwAiAgADAAgJMh7QGwAiAgAFAAUJHAY2JgCXAAAAAA==.Ovscur:BAAALgAECgMJBwAAAA==.',
Pa='Packapipe:BAAALgADCgUJCwAAAA==.Paladinjohn:BAACLgAFFH8WAAIXAAUJuh5+DAB4AQAXAAUJuh5+DAB4AQAuAAQKfycAAhcACQkbJWMBANEDABcACQkbJWMBANEDAAAA.Palykat:BAAALgAECgYJCgAAAA==.Paradox:BAAALgAECgEJAQAAAA==.',
Pe='Pennywisé:BAABLgAECn8hAAIDAAkJXB0ACwCzAgADAAkJXB0ACwCzAgAAAA==.Pessimal:BAAALgADCgEJAQABLgAECgkJHgADAEMfAA==.',
Ph='Phoeniix:BAABLgAECn8jAAMiAAgJgxcOCgD6AQAiAAgJxBYOCgD6AQAPAAQJvResUgDcAAAAAA==.',
Pl='Plaguegying:BAAALgAECgcJCgABLgAECgYJGQASAJAYAA==.Ploofee:BAAALgAECgYJDAAAAA==.',
Po='Porker:BAAALgADCgEJAQAAAA==.',
Pr='Progresz:BAAALgAECgcJEwAAAA==.',
Ps='Psychosis:BAAALgADCgQJAwAAAA==.',
Py='Pykel:BAABLgAECn8kAAIPAAgJyQkaJQATAQAPAAgJyQkaJQATAQAAAA==.Pyrexea:BAAALgADCgYJBgAAAA==.',
Qa='Qaren:BAAALgAECgMJBAAAAA==.',
Qi='Qikeyy:BAAALgAECgEJAQAAAA==.',
Qu='Quadraxis:BAAALgADCgcJCQAAAA==.',
Ra='Raishun:BAAALgADCgYJBgAAAA==.Raizo:BAAALgADCgEJAQAAAA==.Rake:BAABLgAECn8qAAMnAAkJLRrYAwA8AgAnAAkJABnYAwA8AgAiAAEJohyOIgBQAAAAAA==.Raminthórn:BAAALgADCgIJAgAAAA==.Rannï:BAAALgAECgcJBwABLgAFFAMJBwAaAPkcAA==.Ratabi:BAAALgADCgIJAgAAAA==.Rawrski:BAAALgADCgEJAgABLgAECggJHgACAEAKAA==.',
Re='Reeven:BAAALgAECgkJJAAAAQ==.Ressurectjin:BAAALgAECgUJCwAAAA==.',
Rh='Rhaistlin:BAAALgADCgMJAwAAAA==.Rhcpmage:BAABLgAFFH8FAAIKAAMJrh5OOQAsAQAKAAMJrh5OOQAsAQAAAA==.Rhetegast:BAABLgAECn8lAAIgAAgJLRXGDwDIAQAgAAgJLRXGDwDIAQAAAA==.Rhymaek:BAAALgAECgEJAwABLgAECgIJBAAIAAAAAA==.',
Ri='Rike:BAEBLgAECn8cAAMXAAcJAiFfPQAvAgAXAAcJiyBfPQAvAgAgAAMJER/FEwAKAQAAAA==.',
Ro='Roflbackpack:BAAALgAECgkJBwAAAA==.Roflbalanced:BAAALgAECgQJCAAAAA==.Roflgotnerfd:BAAALgADCgMJAwABLgAECgkJBwAIAAAAAA==.Roflhazotime:BAABLgAECn8eAAIQAAkJiCJAAwANAwAQAAkJiCJAAwANAwAAAA==.Roland:BAABLgAECn8dAAMRAAYJMxNDPgAbAQARAAYJMxNDPgAbAQAPAAMJywYPQACBAAAAAA==.Rolandin:BAABLgAECn8cAAIhAAcJ+BFWIgB0AQAhAAcJ+BFWIgB0AQAAAA==.Rollaen:BAAALgADCgYJDAAAAA==.Rook:BAAALgAECgcJCQABLgAFFAUJGAABANIhAA==.Roscjou:BAAALgADCgYJCwAAAA==.Ross:BAAALgAECgYJDwAAAA==.',
Ru='Rubisco:BAAALgAECgYJCwAAAA==.',
Ry='Rylagosa:BAABLgAECn8jAAMdAAcJYhinCgCnAQAdAAYJYhmnCgCnAQAMAAMJFAkEVQBwAAAAAA==.Rynehardt:BAAALgADCgcJBwAAAA==.Ryzesmidge:BAABLgAECn8UAAIKAAgJ6BF2OwC2AQAKAAgJ6BF2OwC2AQAAAA==.',
['Rê']='Rêdrum:BAAALgAECgUJBQABLgAFFAMJDAAOADMJAA==.',
Sa='Sabithia:BAAALgAECgEJAQAAAA==.Salandria:BAAALgAECgYJEAAAAA==.Salandriath:BAAALgAECgYJCwAAAA==.Sange:BAAALgAECgcJDQAAAA==.Sarionian:BAABLgAECn8aAAIRAAcJ1w45PgAbAQARAAcJ1w45PgAbAQAAAA==.Sarvin:BAAALgADCgcJBwABLgAECggJIwABAL8cAA==.Sarvinblue:BAABLgAECn8jAAMBAAgJvxyPFQBpAgABAAgJvxyPFQBpAgACAAMJLQ8KagCbAAAAAA==.Saucestash:BAAALgAECgEJAQAAAA==.Sauronic:BAAALgAECgYJCgAAAA==.',
Se='Seshu:BAAALgAECgEJAQAAAA==.',
Sh='Shambúlance:BAAALgAECgIJAgAAAA==.Shanir:BAAALgADCgMJAwAAAA==.Shanksie:BAABLgAECn8ZAAIZAAcJkAboCgAVAQAZAAcJkAboCgAVAQAAAA==.Shazlulu:BAAALgAECgYJDgAAAA==.Shedoa:BAAALgAECgYJBgAAAA==.Shiftywelt:BAAALgADCggJDAAAAA==.Shinmothee:BAABLgAECn8VAAILAAcJTAqdCgAyAQALAAcJTAqdCgAyAQAAAA==.Shinsura:BAAALgADCgcJEAAAAA==.Shtamman:BAAALgADCgUJBQAAAA==.',
Si='Silvantis:BAAALgADCgEJAQAAAA==.Siobhán:BAABLgAECn8qAAIEAAkJlx8SAwCvAgAEAAkJlx8SAwCvAgAAAA==.',
Sk='Skandle:BAAALgADCgMJAwAAAA==.',
Sl='Sleepypanda:BAABLgAECn8WAAIhAAgJyxi1DABJAgAhAAgJyxi1DABJAgAAAA==.Sloe:BAABLgAECn8ZAAIJAAcJWx1iEADmAQAJAAcJWx1iEADmAQAAAA==.',
Sm='Smokalot:BAAALgADCgEJAQAAAA==.',
So='Somebody:BAAALgAECgQJBAAAAA==.Soulitude:BAAALgAECgEJAQAAAA==.Southerngal:BAAALgADCgMJAwAAAA==.',
Sp='Speedmeat:BAAALgAECgYJCgAAAA==.Sporkulous:BAABLgAECn8mAAMGAAgJEg6HOgBjAQAGAAgJEg6HOgBjAQAWAAEJFwErLgAUAAAAAA==.',
Sq='Squal:BAABLgAECn8cAAMXAAYJ3B4YVwDdAQAXAAYJ3B4YVwDdAQAgAAQJShhMGwC6AAAAAA==.Squiggle:BAABLgAECn8gAAIgAAcJ0xyaCwARAgAgAAcJ0xyaCwARAgAAAA==.',
St='Stalkêr:BAAALgADCgIJAgAAAA==.Stewy:BAAALgAECgYJBgAAAA==.Stickybunz:BAAALgAECgYJEAABLgAECggJKwANAOYUAA==.Striker:BAEALgAECgMJBAABLgAECgcJHAAXAAIhAA==.Strombone:BAAALgADCgEJAgABLgAECgIJEAAIAAAAAA==.Stunseed:BAABLgAECn8hAAIiAAgJ0xfEBgDYAQAiAAgJ0xfEBgDYAQAAAA==.',
Su='Sungjinwu:BAAALgAECgUJBQAAAA==.Sunshíne:BAAALgAECgQJEAAAAA==.Surf:BAAALgAECgEJAgAAAA==.',
Sw='Sweetbunz:BAABLgAECn8rAAMNAAgJ5hQ/KQCQAQANAAcJghc/KQCQAQAJAAgJWQ63GQB/AQAAAA==.',
Sy='Synaminaphyn:BAAALgAECgEJAQAAAA==.Syver:BAABLgAECn8fAAIDAAgJ0hf6JgDjAQADAAgJ0hf6JgDjAQAAAA==.',
['Sì']='Sìrfuzywuzy:BAAALgAECgMJCAAAAA==.',
Ta='Taisty:BAAALgADCgQJBAAAAA==.Tanagra:BAAALgAECgEJAQABLgAECgcJGwAOABkYAA==.Taniss:BAABLgAECn8fAAIjAAgJCgfiBgAxAQAjAAgJCgfiBgAxAQAAAA==.Tanner:BAABLgAECn8bAAMWAAgJDgm8SgAnAQAWAAgJwQe8SgAnAQAGAAIJoBF6ogCHAAAAAA==.',
Te='Tedman:BAABLgAECn8VAAMCAAcJEw8bPgBSAQACAAcJEw8bPgBSAQABAAIJDAdRjwBaAAAAAA==.Temel:BAABLgAECn8eAAMCAAgJQAoHIgBBAQACAAgJQAoHIgBBAQABAAYJUwkJQwD2AAAAAA==.Tenelum:BAAALgADCgEJAQABLgAECggJHgACAEAKAA==.Testoecles:BAAALgAECgMJBQAAAA==.',
Th='Thadrack:BAABLgAECn8dAAIKAAgJuwT8cwApAQAKAAgJuwT8cwApAQAAAA==.Thaine:BAAALgADCgEJAQABLgAECgcJDQAIAAAAAA==.Thalonstin:BAAALgADCgEJAQAAAA==.Thanevoker:BAAALgAECgcJDQAAAA==.Thayn:BAAALgAECgYJDAABLgAECgcJDQAIAAAAAA==.Theodrid:BAACLgAFFH8KAAIXAAUJVA+1GADnAAAXAAUJVA+1GADnAAAuAAQKfyIAAhcACAmPHywkAJcCABcACAmPHywkAJcCAAAA.Thraxia:BAABLgAECn8XAAIOAAgJWAX6lQAsAQAOAAgJWAX6lQAsAQAAAA==.Thutpithyuth:BAAALgAECggJAwABLgAECggJEwAIAAAAAA==.',
Ti='Tinkíe:BAABLgAECn8YAAQYAAkJLxqUFgBzAQAYAAcJphmUFgBzAQASAAQJQRmSTgAJAQATAAUJ2QwxLgDjAAAAAA==.Tirzahdozier:BAAALgAECgIJAwABLgAECgIJBAAIAAAAAA==.Tiwohnne:BAAALgADCgEJAQAAAA==.',
Tl='Tla:BAAALgADCgEJAQAAAA==.',
Tr='Treat:BAABLgAECn8lAAINAAgJMiMWAwDRAgANAAgJMiMWAwDRAgAAAA==.Tremblement:BAAALgADCgMJAwAAAA==.Trippyshock:BAAALgAECgEJAQABLgAFFAkJJwAOAEQbAA==.Tristitia:BAAALgAECgcJEwAAAA==.',
Tu='Tubbs:BAAALgAECggJEAAAAA==.Turkeltin:BAAALgAECgYJEAABLgAFFAIJAgAIAAAAAA==.',
Ty='Tyche:BAAALgAECgMJBAAAAA==.Tysbich:BAAALgAECgQJBAABLgAECggJEwAIAAAAAA==.',
Ui='Uiewedaoez:BAABLgAECn8qAAIRAAkJgCNKAQCWAwARAAkJgCNKAQCWAwAAAA==.',
Um='Umakkel:BAAALgADCgcJCwAAAA==.Umiko:BAAALgADCgUJBQAAAA==.',
Ur='Urd:BAABLgAECn8hAAIDAAkJ7xBPJADyAQADAAkJ7xBPJADyAQAAAA==.',
Va='Vaelrelyn:BAABLgAECn8UAAMbAAYJJhD1HgBZAQAbAAYJJhD1HgBZAQAOAAIJ4gHpLwEhAAAAAA==.Vains:BAACLgAFFH8IAAIXAAMJuSChIQAnAQAXAAMJuSChIQAnAQAuAAQKfyIAAhcACQkvIU4JAMECABcACQkvIU4JAMECAAAA.Valoras:BAAALgADCgEJAQAAAA==.Valrith:BAAALgAECgMJAwAAAA==.Vardis:BAABLgAECn8oAAIKAAkJlR5WEQCPAgAKAAkJlR5WEQCPAgAAAA==.',
Ve='Velinami:BAAALgAECgEJAQAAAA==.Venato:BAAALgADCgEJBAABLgAECggJHgACAEAKAA==.Vendettuh:BAAALgADCgEJAQAAAA==.Verenthirl:BAAALgAECgUJBAAAAA==.Veronica:BAABLgAECn8cAAIKAAcJoxh5RgCUAQAKAAcJoxh5RgCUAQAAAA==.Verren:BAAALgAECggJEwAAAA==.',
Vi='Virse:BAAALgAECgQJBgAAAA==.Virtigo:BAAALgADCgQJCAAAAA==.',
Vy='Vyerith:BAABLgAECn8hAAIOAAgJ2B3JFAA7AgAOAAgJ2B3JFAA7AgAAAA==.',
We='Weltamus:BAABLgAECn8XAAIDAAYJ3wzHYgAeAQADAAYJ3wzHYgAeAQAAAA==.Weltasaur:BAAALgAECgMJBAAAAA==.Weltazar:BAABLgAECn8aAAICAAcJBBTRJQAqAQACAAcJBBTRJQAqAQAAAA==.Westside:BAACLgAFFH8XAAMKAAYJBR7yBAAbAgAKAAYJBR7yBAAbAgALAAEJqAkTAgBQAAAuAAQKfxkAAgoACAnTJp8JAHkDAAoACAnTJp8JAHkDAAAA.',
Wi='Wickedfluff:BAAALgADCgYJBgAAAA==.Wickët:BAAALgAECgQJBwABLgAECgkJGgAOAOUhAA==.Wildtiger:BAABLgAECn8dAAInAAYJ1w1jEAAUAQAnAAYJ1w1jEAAUAQAAAA==.',
Wr='Wrecken:BAAALgADCgQJBAAAAA==.',
Wu='Wulfenhide:BAABLgAECn8iAAQZAAgJMx39AQBdAgAZAAgJMx39AQBdAgAEAAMJoAfeUACkAAAjAAEJeAVdDwArAAAAAA==.',
Wy='Wyzsky:BAAALgAECgEJAgABLgAECggJHgACAEAKAA==.',
Xa='Xal:BAAALgADCgEJAQABLgAECgIJAgAIAAAAAA==.Xalreth:BAAALgAECggJEwAAAA==.Xaviana:BAAALgAECgcJIwAAAQ==.',
Xc='Xcedrin:BAABLgAECn8fAAMNAAkJOggnHABbAQANAAgJOAcnHABbAQAJAAMJXwV6cQBhAAAAAA==.',
Ya='Yastinfect:BAABLgAECn8cAAIQAAgJFRqQJACuAQAQAAgJFRqQJACuAQAAAA==.Yastypoo:BAAALgAECgEJAQAAAA==.',
Yu='Yurika:BAEBLgAECn8nAAIhAAkJjSXsAgAbAwAhAAkJjSXsAgAbAwAAAA==.Yushi:BAABLgAECn8jAAIEAAkJxh5xAgDRAgAEAAkJxh5xAgDRAgAAAA==.',
Za='Zareen:BAAALgADCgkJCQAAAA==.Zaru:BAAALgADCgcJCQAAAA==.Zayfall:BAAALgAECgYJEwAAAA==.',
Ze='Zelenor:BAAALgAECgYJDAAAAA==.Zenweaver:BAACLgAFFH8LAAISAAMJzxvzGgD+AAASAAMJzxvzGgD+AAAuAAQKfxwAAhIACQkIIVYEAEcDABIACQkIIVYEAEcDAAAA.',
Zi='Ziur:BAAALgADCgEJAQAAAA==.',
Zo='Zonde:BAAALgADCgEJAQAAAA==.',
Zu='Zud:BAABLgAECn8XAAIDAAgJ4CCWDAChAgADAAgJ4CCWDAChAgAAAA==.',
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

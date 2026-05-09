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

local lookup = {'Mage-Frost','Priest-Holy','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Warrior-Arms','Druid-Balance','Druid-Restoration','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Evoker-Preservation','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Warrior-Protection','Rogue-Subtlety','Paladin-Holy','Monk-Mistweaver','Druid-Feral','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abysmal:BAAALgADCgYJBgABLgAECggJHAABAGUNAA==.Abÿss:BAAALgAECgMJBQAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgYJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8cAAICAAgJFg3SHABjAQACAAgJFg3SHABjAQAAAA==.Aellart:BAAALgAECgEJAQAAAA==.Aeriona:BAABLgAECn8cAAIDAAcJJxmvMwCuAQADAAcJJxmvMwCuAQAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIEAAgJcQtdDQAWAQAEAAgJcQtdDQAWAQAAAA==.',
Ai='Aine:BAABLgAECn8VAAMCAAcJJBYCFgCkAQACAAYJwRkCFgCkAQAFAAYJ6wA5WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAECgYJBwABLgAECgkJHgAGABMSAA==.',
Aj='Ajani:BAAALgAECgYJCgAAAA==.',
Ak='Akyospirit:BAABLgAECn8cAAIHAAcJ0AxIMgBFAQAHAAcJ0AxIMgBFAQAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAECgkJGwAIALEYAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn8hAAMJAAkJBA9VFgCKAQAJAAkJBA9VFgCKAQAKAAEJmgiOpwAjAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Alpha:BAABLgAECn8oAAIBAAgJ7htzHQA6AgABAAgJ7htzHQA6AgAAAA==.Alroy:BAAALgAECgkJCwAAAA==.Aluina:BAAALgAECgQJBAAAAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn8jAAIGAAgJlRW3DwDOAQAGAAgJlRW3DwDOAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn8cAAILAAcJfw7+BQBdAQALAAcJfw7+BQBdAQAAAA==.Amonet:BAAALgADCgYJCwAAAA==.',
An='Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgMJBwAAAA==.Anglico:BAAALgAECgQJBQABLgAECggJFgAMABEYAA==.Angliko:BAAALgAECgUJBQABLgAECggJFgAMABEYAA==.Anglikoo:BAAALgADCggJCAABLgAECggJFgAMABEYAA==.Anomandaris:BAABLgAECn8UAAINAAgJhhKFFwCVAQANAAgJhhKFFwCVAQAAAA==.Anquan:BAABLgAECn8WAAIOAAcJQBioMQCzAQAOAAcJQBioMQCzAQAAAA==.',
Ap='Apedemak:BAAALgADCgUJBAAAAA==.Aphobias:BAAALgADCgIJAgAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothicc:BAAALgAECgQJBQAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8cAAIPAAcJAgSVWgAAAQAPAAcJAgSVWgAAAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8fAAIBAAcJTAVpggANAQABAAcJTAVpggANAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwAQAAAAAA==.Argobow:BAAALgAECgQJBQAAAA==.Argonaut:BAAALgAECgYJBgAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAAALgAECgQJCAABLgAECggJKwARAOQfAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAIPAAgJgRBFLgCVAQAPAAgJgRBFLgCVAQAAAA==.',
As='Ascender:BAAALgADCgMJBgAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8WAAISAAcJ+yHCCQCaAgASAAcJ+yHCCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIDAAgJeBZlTABgAQADAAgJeBZlTABgAQAAAA==.Askr:BAABLgAECn8VAAMPAAYJQwz6UgAVAQAPAAYJEwr6UgAVAQAEAAYJnwrfEgDIAAAAAA==.Asphar:BAABLgAECn8iAAMPAAgJJiGYBwC3AgAPAAgJJiGYBwC3AgAEAAMJChM6GgB4AAAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAABLgAECn8wAAITAAgJqiUOAgB4AwATAAgJqiUOAgB4AwAAAA==.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgcJHQAUAK0GAA==.Avralis:BAAALgADCgMJAwABLgAECggJFAAVADYYAA==.',
Az='Azamii:BAABLgAECn8vAAMNAAgJLSDYBQCOAgANAAgJLSDYBQCOAgAHAAYJQRgQOwCVAQAAAA==.Azarion:BAABLgAECn8vAAMWAAgJmhy0BQCdAQAWAAcJoRq0BQCdAQAXAAYJRxWAQgBhAQAAAA==.Azill:BAACLgAFFH8OAAIYAAUJyBdaBABQAQAYAAUJyBdaBABQAQAuAAQKfyIAAhgACAmvHS4KANUCABgACAmvHS4KANUCAAAA.Azzrael:BAABLgAECn8mAAIZAAkJaRDHDwBmAQAZAAkJaRDHDwBmAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgUJBgAAAA==.Bartrak:BAABLgAECn8WAAMFAAgJfRS+EwCmAQAFAAgJfRS+EwCmAQARAAMJ0g4lQwCcAAAAAA==.',
Be='Bearrific:BAABLgAECn8aAAIaAAgJgRgFDQDRAQAaAAgJgRgFDQDRAQAAAA==.Beawulf:BAAALgADCggJGQAAAA==.Belista:BAAALgADCggJGQAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bf='Bfresh:BAAALgADCgUJBQAAAA==.',
Bi='Billie:BAAALgADCgQJAgAAAA==.Billthekid:BAAALgAECgEJAQAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgADCgkJEQABLgAECgEJAQAQAAAAAA==.Binksy:BAACLgAFFH8LAAIUAAQJFhPwDgA2AQAUAAQJFhPwDgA2AQAuAAQKfygAAhQACQn2G7MNAOgCABQACQn2G7MNAOgCAAAA.Biscuit:BAACLgAFFH8cAAIZAAYJdiNVAQDwAQAZAAYJdiNVAQDwAQAuAAQKfxkAAhkACQn0JO4AAJYDABkACQn0JO4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgMJCgAAAA==.Blazin:BAACLgAFFH8NAAIBAAQJsw6LMQBGAQABAAQJsw6LMQBGAQAuAAQKfxsAAgEACAk5Hm0UAHYCAAEACAk5Hm0UAHYCAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgcJCAAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Bloui:BAAALgAECgQJBgAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAYJHAAZAHYjAA==.Bongrips:BAAALgADCgIJAgAAAA==.Boomboom:BAAALgAECgIJAwAAAA==.Borlok:BAAALgAFFAEJAQAAAQ==.',
Br='Brannigan:BAABLgAECn8cAAIZAAcJuSTwAwB+AgAZAAcJuSTwAwB+AgAAAA==.Braulioo:BAAALgAECgEJAgAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAAALgAECgcJEgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgIJAgAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJDQAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAAALgAECgYJEwAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8XAAIIAAgJ5CGSAgCXAgAIAAgJ5CGSAgCXAgAAAA==.',
['Bé']='Béckley:BAAALgAECgcJDAAAAA==.Béckléy:BAAALgAECgUJDQABLgAECgcJDAAQAAAAAA==.',
Ca='Caatha:BAAALgADCggJGQAAAA==.Caleanone:BAAALgAECgYJBgABLgAECgkJGwAIALEYAA==.Callox:BAABLgAECn8bAAMIAAgJsRjsEQCCAQAUAAgJ2xP5KwAFAgAIAAUJJxvsEQCCAQAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgMJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAABLgAECn8bAAIKAAcJ9RWzIAC/AQAKAAcJ9RWzIAC/AQAAAA==.Catriona:BAABLgAECn8YAAIPAAgJuAqRPQBXAQAPAAgJuAqRPQBXAQAAAA==.Cazmeer:BAAALgAECgMJAwAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8dAAIGAAYJOh3IAwC6AQAGAAYJOh3IAwC6AQAuAAQKfxgAAgYACQn+IF0JAPMCAAYACQn+IF0JAPMCAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgADCgEJAQABLgAECggJFAAGAIoUAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMXAAMJ4wvaRQDOAAAXAAMJ4wvaRQDOAAAWAAIJrwIbDwCHAAAuAAQKfyYAAxYACAkiF40JACcCABYACAmBFY0JACcCABcACAl1FIcmAM4BAAAA.Chillainkor:BAABLgAECn8eAAIGAAkJExIILACtAQAGAAkJExIILACtAQAAAA==.Chillidán:BAABLgAECn8OAAIVAAgJ9wJcbwC8AAAVAAgJ9wJcbwC8AAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9BowIwAaAgABAAgJ9BowIwAaAgAAAA==.Chippndots:BAAALgAECgUJBgABLgAECggJIAABAPQaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAABLgAECn8dAAIbAAgJ9BOWGwCsAQAbAAgJ9BOWGwCsAQAAAA==.Chronosaren:BAAALgAECggJEAAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgcJHAAZALkkAA==.',
Cj='Cjrej:BAABLgAECn8ZAAIBAAcJRg1aXgBWAQABAAcJRg1aXgBWAQAAAA==.',
Cl='Claytonis:BAAALgADCgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Cons:BAABLgAECn8aAAQRAAgJnBa0EQC+AQARAAcJrhW0EQC+AQACAAMJ8QrRZQCWAAAFAAEJ+xL9TQA+AAAAAA==.Corellon:BAABLgAECn8iAAIPAAgJ0RyTHwDeAQAPAAgJ0RyTHwDeAQAAAA==.Costcohotdog:BAABLgAFFH8HAAMGAAMJLR1EGACsAAAGAAMJLR1EGACsAAAcAAEJOQBjGgAYAAABLgAFFAYJHAAZAHYjAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn8XAAIXAAcJshBRPQBzAQAXAAcJshBRPQBzAQAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8eAAIPAAYJoiLsHABYAgAPAAYJoiLsHABYAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1oKQD9AQABAAgJWB1oKQD9AQAAAA==.Cryoshock:BAAALgAFFAIJAgAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
Da='Daario:BAABLgAECn8TAAIVAAcJsB+fNQAhAgAVAAcJsB+fNQAhAgAAAA==.Dabare:BAAALgADCgEJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECggJIAAdAPUdAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8gAAQdAAgJ9R3nEQD/AAAdAAUJLR3nEQD/AAAJAAYJ+xzAKQD2AAAeAAcJUwklHADFAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAQAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgEJAQABLgAECggJGgABAJcYAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAAALgAECgYJDgAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgEJAQAAAA==.Davidbowy:BAABLgAECn8VAAMPAAgJDg39QQBHAQAPAAcJYQ79QQBHAQAfAAUJ7AgnGgA0AQABLgAECgYJBwAQAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgADCgQJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECggJGgABAJcYAA==.Demina:BAAALgADCgUJBQABLgAECggJFAAVADYYAA==.Demonainkor:BAAALgAECgYJBgABLgAECgkJHgAGABMSAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn8cAAMRAAcJdxc5GgBfAQARAAYJyxI5GgBfAQACAAYJJBf/IgAxAQAAAA==.Desden:BAABLgAECn8cAAIeAAcJfhQ/CwBhAQAeAAcJfhQ/CwBhAQAAAA==.Destined:BAAALgADCgIJAQAAAA==.Devianchi:BAABLgAECn8iAAMcAAgJ+B+CCQC5AgAcAAgJ+B+CCQC5AgAYAAcJIh/xCQAcAgAAAA==.Devitodevour:BAABLgAECn8eAAMXAAgJPRt4GgASAgAXAAcJmxl4GgASAgAWAAMJXBkDNQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIOAAMJoCKRPQAYAQAOAAMJoCKRPQAYAQAuAAQKfzIAAg4ACAk9I7YLAKsCAA4ACAk9I7YLAKsCAAAA.',
Dh='Dhbert:BAABLgAECn8eAAIgAAkJfw1OFgAfAQAgAAkJfw1OFgAfAQAAAA==.Dhomeli:BAAALgAECgEJAQAAAA==.',
Di='Disastrophy:BAAALgAECgYJEQAAAA==.Disturbed:BAABLgAECn8lAAQXAAgJXRzGGAAdAgAXAAcJBxvGGAAdAgALAAMJpR+PDQCrAAAWAAEJAADSYgBJAAAAAA==.Disturbio:BAAALgADCgIJAwABLgAECggJJQAXAF0cAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgADCgMJAwAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAXABoiAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dooridash:BAAALgADCgcJCwAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECggJDgAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgAECgMJAwAAAA==.Dramûl:BAABLgAECn8aAAIPAAgJ0RYIIQDWAQAPAAgJ0RYIIQDWAQAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgADCgIJAgAAAA==.Drunkdragon:BAABLgAECn8UAAIYAAgJRRLgGwD9AQAYAAgJRRLgGwD9AQAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAAALgAECgkJDwAAAA==.Dustyknight:BAABLgAECn8XAAIgAAgJcQfRGgDwAAAgAAgJcQfRGgDwAAAAAA==.',
Dw='Dwell:BAAALgADCgkJGwAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgADCgMJAwABLgAECggJGwAhADMVAA==.',
Ed='Edge:BAABLgAECn8bAAIHAAgJyxTAIACtAQAHAAgJyxTAIACtAQAAAA==.',
Ee='Eelenna:BAABLgAECn8YAAMiAAkJ5xtgBgCSAgAiAAkJ5xtgBgCSAgANAAUJwRBhUwD4AAAAAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAECgQJCQABLgAECggJFAAVADYYAA==.Eleros:BAABLgAECn8oAAIVAAgJ/R+MCgCBAgAVAAgJ/R+MCgCBAgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8hAAMaAAgJhxZdCgD6AQAaAAgJhxZdCgD6AQAjAAEJ4BFiIAAxAAAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgADCgcJHAAAAA==.Emt:BAAALgADCgcJBwAAAA==.',
En='Endarial:BAAALgAECgQJBgAAAA==.Enoki:BAABLgAFFH8IAAIHAAMJ3hmPEADkAAAHAAMJ3hmPEADkAAABLgAFFAYJGwAKAN0jAA==.',
Er='Eraduckated:BAAALgAECgYJBgABLgAECggJGwAhADMVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgADCggJFgABLgAECgcJHAAJAHYNAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAECgIJCAAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgYJBgAAAA==.',
Fa='Falconpunch:BAAALgAECgEJAQAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwAQAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAgAAAA==.',
Fe='Fedders:BAABLgAECn8kAAIDAAkJPiaFBwBbAwADAAkJPiaFBwBbAwAAAA==.Felaids:BAACLgAFFH8KAAMXAAQJTgykTQC6AAAXAAQJtgikTQC6AAALAAEJSBCmCABSAAAuAAQKfyoAAxcACAlDHEYWADACABcABwlDHEYWADACABYAAwkSCLZEAKIAAAAA.Felimonk:BAAALgAECgQJAwABLgABCgQJBQAQAAAAAA==.Felpecs:BAAALgAECgQJBgAAAA==.Feyda:BAABLgAECn8WAAIBAAgJlQaFXgBVAQABAAgJlQaFXgBVAQAAAA==.',
Fi='Fillon:BAABLgAECn8rAAIDAAgJjCSSDQCTAgADAAgJjCSSDQCTAgAAAA==.Firessar:BAAALgAECgIJBAAAAA==.Fishfood:BAABLgAECn8cAAIkAAcJNRUUBQCKAQAkAAcJNRUUBQCKAQAAAA==.Fixer:BAAALgAECgEJAQAAAA==.',
Fk='Fk:BAAALgAECgcJCAABLgAECgkJDwAQAAAAAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECgUJBQAAAA==.Frimthemage:BAABLgAECn8sAAIBAAkJOB8FDADAAgABAAkJOB8FDADAAgAAAA==.Frostmaster:BAABLgAECn8WAAIBAAcJ/BtNLADwAQABAAcJ/BtNLADwAQAAAA==.',
['Fí']='Fízban:BAAALgAECgIJAgAAAA==.',
['Fø']='Førd:BAACLgAFFH8LAAMlAAQJFQx9AgAwAQAlAAQJFQx9AgAwAQAmAAIJjQhfMACIAAAuAAQKfycAAyUACAmIHBkLACoCACUABwlLGhkLACoCACYABgllGRwkAJwBAAAA.',
Ga='Gammon:BAABLgAECn8aAAINAAgJ7hvlCQA7AgANAAgJ7hvlCQA7AgAAAA==.Gangrene:BAABLgAECn8uAAMOAAgJVRRUNwCcAQAOAAgJUhNUNwCcAQAgAAgJCQshFgAhAQAAAA==.Gary:BAAALgAECgQJBgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn8bAAIjAAgJPRWNAwD5AQAjAAgJPRWNAwD5AQAAAA==.Gaviin:BAABLgAECn8qAAIjAAgJiCEyAQChAgAjAAgJiCEyAQChAgAAAA==.',
Ge='Gearador:BAAALgADCgMJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwAQAAAAAA==.Gerhart:BAABLgAECn8cAAQVAAgJTRhUdwBAAQAVAAcJYxlUdwBAAQAMAAUJrQ9gHACqAAATAAEJSg5icwAxAAAAAA==.Getcarried:BAAALgADCgMJAwAAAA==.Getty:BAAALgAECgMJBQAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAgAAAA==.Gigarius:BAABLgAECn8ZAAIhAAgJVySZAQDAAgAhAAgJVySZAQDAAgAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAAALgAECgUJCAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAABLgAECn8eAAMkAAgJeh9wAQBpAgAkAAgJMB9wAQBpAgAgAAUJBSKJDgCJAQABLgAECgkJGAAiAOcbAA==.Gonnosuke:BAAALgAECgQJBAAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECggJIAAdAPUdAA==.Griffmonk:BAABLgAECn8qAAIcAAgJbRtbCwA1AgAcAAgJbRtbCwA1AgAAAA==.Grumpymage:BAABLgAECn8oAAIBAAgJrR1gGABZAgABAAgJrR1gGABZAgAAAA==.',
Ha='Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgADCgkJJgAAAA==.Hara:BAABLgAECn8aAAIKAAYJPRrnKQCEAQAKAAYJPRrnKQCEAQAAAA==.Hardord:BAABLgAECn8UAAIaAAYJFw6PGgAsAQAaAAYJFw6PGgAsAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJBQAAAA==.Hayanne:BAABLgAECn8vAAIZAAgJcRugBgAlAgAZAAgJcRugBgAlAgAAAA==.',
He='Healchucky:BAAALgAECgYJDAAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJCgAAAA==.Heina:BAAALgAECgYJBgAAAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAABLgAECn8YAAMRAAkJ/A5UEADPAQARAAkJxQpUEADPAQACAAkJugkYOwBOAQAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAAALgAECggJEQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8WAAIbAAkJvQwLIACGAQAbAAkJvQwLIACGAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIDAAgJixS4OgCWAQADAAgJixS4OgCWAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8cAAIHAAcJaBzAEgAiAgAHAAcJaBzAEgAiAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAECgkJDwAQAAAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.',
['Hâ']='Hârley:BAABLgAECn8gAAIKAAgJPxuCFAAlAgAKAAgJPxuCFAAlAgAAAA==.',
['Hí']='Híram:BAABLgAECn8kAAIDAAgJQhTRMwCuAQADAAgJQhTRMwCuAQAAAA==.',
Id='Idyllwild:BAAALgAECgEJAwAAAA==.',
Ih='Ihsan:BAABLgAECn8WAAIDAAcJwBHoRQB0AQADAAcJwBHoRQB0AQAAAA==.',
Il='Ilharess:BAACLgAFFH8HAAIBAAMJKQdRTwDmAAABAAMJKQdRTwDmAAAuAAQKfyAAAgEACAkeFbVUAG4BAAEACAkeFbVUAG4BAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAQJCgAZAAkcAA==.Inkpot:BAAALgAECgEJAQABLgAECgcJJgAKAAAmAA==.Inkwell:BAABLgAECn8mAAIKAAcJACb4CAAAAwAKAAcJACb4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgIJAgAAAA==.',
Ja='Jaardrius:BAABLgAECn8hAAMcAAcJ1CPsBQCrAgAcAAcJ1CPsBQCrAgAYAAMJjguuXgCVAAAAAA==.Jackransom:BAAALgADCgcJBwAAAA==.Jakobo:BAAALgAECgcJCgAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgEJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgMJAwAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAYJGwAKAN0jAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgEJAQAAAA==.',
Ju='Junebuge:BAAALgADCgcJFAAAAA==.Junknthtrunk:BAAALgADCggJEAAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAaAIYjAA==.',
Ke='Keanew:BAABLgAECn8mAAQTAAgJyxzXEQBrAQATAAgJdxzXEQBrAQAMAAUJkQ80DgDdAAAVAAMJNgOkmgBdAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8iAAMbAAYJcCGjIAAWAgAbAAYJcCGjIAAWAgADAAEJIwHVYQEUAAAAAA==.Kenry:BAAALgAECgQJBgAAAA==.Keonna:BAAALgAECgQJBgAAAA==.Keppra:BAAALgAECgMJBQAAAA==.Kerlin:BAACLgAFFH8GAAIKAAMJ+QBWMgCBAAAKAAMJ+QBWMgCBAAAuAAQKfxoAAwoACAkND19YAEkBAAoABwnVC19YAEkBAAkAAQnkAmuIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMXAAYJmgWdeADXAAAXAAYJewWdeADXAAALAAMJagNxHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Khurst:BAAALgAECgcJBwAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAYJGwAKAN0jAA==.Kimmex:BAAALgADCgQJAgAAAA==.Kinoxo:BAACLgAFFH8aAAMUAAYJtRkyCgBVAQAUAAQJsBwyCgBVAQAIAAUJfhLSDADeAAAuAAQKfxcAAxQACAkDIeQaAHUCABQACAnrHeQaAHUCAAgAAwlwHakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8eAAIDAAgJmRLPMAC5AQADAAgJmRLPMAC5AQAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgYJBgAAAA==.',
Kr='Kragge:BAAALgADCgcJBwAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Kryven:BAAALgADCggJCAAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgEJAQAAAA==.Kynlas:BAAALgADCgIJAgAAAA==.Kyratinx:BAAALgAECgEJAgAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAECgkJDwAQAAAAAA==.Larious:BAABLgAECn8nAAIDAAgJkBl5HAAdAgADAAgJkBl5HAAdAgAAAA==.',
Le='Ledikens:BAAALgADCgkJEQAAAA==.Legnase:BAABLgAECn8tAAMRAAkJcB6MAgAhAwARAAkJXR6MAgAhAwACAAIJRRYoPQB0AAABLgAECggJLwANAC0gAA==.Leht:BAABLgAECn8cAAMJAAcJdg2QHgBBAQAJAAcJdg2QHgBBAQAKAAEJawGO7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIUAAcJPh/WGgB1AgAUAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgADCgcJBwAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lilgaspump:BAAALgADCgIJAQAAAA==.Lili:BAAALgADCgQJAgAAAA==.Lilnasty:BAABLgAECn8cAAIBAAgJZQ1USwCGAQABAAgJZQ1USwCGAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Livesey:BAAALgAECgQJBQAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAYAEUSAA==.Lockpie:BAAALgADCgcJBwAAAA==.Lokahn:BAABLgAECn8WAAIYAAYJ2Rl7IwC6AQAYAAYJ2Rl7IwC6AQAAAA==.Longhornpibe:BAABLgAECn80AAMUAAgJcRcGDwAAAgAUAAgJcRcGDwAAAgAIAAMJTA4KIwCqAAAAAA==.Loudog:BAABLgAECn8oAAMOAAgJOhTjNgCeAQAOAAgJ/BLjNgCeAQAgAAYJIQ75HADbAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIFAAgJWQ/mFwB/AQAFAAgJWQ/mFwB/AQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgADCggJFgAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIGAAcJliBqEACXAgAGAAcJliBqEACXAgABLgAFFAYJHAAZAHYjAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAAALgAECgUJCgABLgAECgcJHQAUAE8RAA==.Malus:BAABLgAECn8YAAIXAAgJLQ6xYQClAQAXAAgJLQ6xYQClAQAAAA==.Manders:BAAALgADCgQJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgADCggJGQAAAA==.Mattydruid:BAAALgAECgIJAgAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAABLgAECn8mAAMPAAgJNhciJQDAAQAPAAcJ4hkiJQDAAQAEAAgJpQzKEgDJAAAAAA==.Mayge:BAABLgAECn8gAAIBAAkJLhkbFQBxAgABAAkJLhkbFQBxAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8VAAIKAAcJyBtlHQDYAQAKAAcJyBtlHQDYAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Mels:BAAALgAECgQJBAAAAA==.Mendinna:BAABLgAECn8hAAITAAgJvQrfFABEAQATAAgJvQrfFABEAQAAAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAGAJYQAA==.Methir:BAAALgADCgYJCQAAAA==.',
Mi='Miffed:BAAALgAECggJEgABLgAFFAUJFQAhANcLAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECgYJDQAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgIJAgAQAAAAAA==.Mirage:BAABLgAECn8VAAIaAAcJhiMNFwBSAgAaAAcJhiMNFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn8oAAIYAAkJ/h8LBACuAgAYAAkJ/h8LBACuAgAAAA==.',
Mo='Montebrew:BAAALgAECgMJAwAAAA==.Mooky:BAABLgAECn8fAAIJAAgJXA6uGQBrAQAJAAgJXA6uGQBrAQAAAA==.Mopeia:BAABLgAECn8aAAIKAAYJghdqJgCZAQAKAAYJghdqJgCZAQABLgAECgYJEwAQAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgYJGwAOALcjAA==.Mortemore:BAACLgAFFH8RAAIVAAUJ4hdNHwAvAQAVAAUJ4hdNHwAvAQAuAAQKfxwAAhUACQl7Hl8rAFICABUACQl7Hl8rAFICAAAA.Motet:BAAALgAECgYJCwAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECggJEQAAAA==.',
My='Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Naproxen:BAABLgAECn8oAAIfAAgJWR63BAB1AgAfAAgJWR63BAB1AgAAAA==.Naraku:BAACLgAFFH8LAAMXAAQJwgzrLgAQAQAXAAQJHAzrLgAQAQAWAAEJFhKqFABVAAAuAAQKfycAAxcACAktHzkeAKECABcACAkqHjkeAKECABYABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Netty:BAAALgAECgIJAgAAAA==.',
Ni='Nightshaulea:BAAALgAECgEJAQAAAA==.Niklaus:BAABLgAECn8aAAIDAAcJdhZXaACvAQADAAcJdhZXaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAQAAAAAA==.',
Ny='Nymeera:BAABLgAECn8fAAMeAAgJ2gbhFQC4AAAeAAgJZgbhFQC4AAAdAAIJPAM6IgBNAAAAAA==.Nymphetamine:BAABLgAECn8nAAMCAAgJThlHCgBDAgACAAgJThlHCgBDAgARAAQJ4ARFMQCkAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8YAAIFAAgJ4QwIGwBjAQAFAAgJ4QwIGwBjAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIOAAYJXRjXbgCrAQAOAAYJXRjXbgCrAQAAAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn8cAAIEAAgJUg3JCQBbAQAEAAgJUg3JCQBbAQAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.',
Ow='Owenwilson:BAAALgAECgEJAQAAAA==.Owful:BAAALgAECgEJAQAAAA==.',
Pa='Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAAALgAECggJDgAAAA==.Papaya:BAACLgAFFH8bAAIKAAYJ3SOYAQD+AQAKAAYJ3SOYAQD+AQAuAAQKfxwAAwoACQnZIcMGAB8DAAoACQnZIcMGAB8DAAkABgleIpAjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8fAAIBAAgJYRW2LgDmAQABAAgJYRW2LgDmAQAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJDAAAAA==.',
Ph='Phaith:BAAALgADCgUJCwAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECggJGgANAO4bAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Po='Porteagarder:BAAALgAECgYJDwABLgAECgYJGQAKAKoKAA==.Potatodruid:BAAALgAECgQJCwAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAAALgAECgkJDQAAAA==.Preront:BAACLgAFFH8jAAMiAAgJAx8IAACBAgAiAAYJoiMIAACBAgANAAgJBxvZAABpAgAuAAQKfx8AAyIACQngJikAAOYDACIACQngJikAAOYDAA0AAwksJqg+AFABAAAA.Pringler:BAAALgAECgQJBAABLgAFFAYJHAAZAHYjAA==.Producktive:BAABLgAECn8bAAIhAAgJMxXBEAC6AQAhAAgJMxXBEAC6AQAAAA==.Prometeus:BAAALgADCggJCAAAAA==.Pros:BAABLgAECn8iAAIWAAkJWRRZDQDvAQAWAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgMJAwABLgAECgcJHAAJAHYNAA==.Príestly:BAAALgAECgEJAQAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1BuJCABJAgAmAAgJ1BuJCABJAgABLgAFFAUJEQAVAOIXAA==.Puffthemagic:BAAALgAECggJDQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8jAAILAAgJbhvDAQA0AgALAAgJbhvDAQA0AgAAAA==.',
['Pú']='Púff:BAAALgADCgEJAQAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAQAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAAALgAECgQJBAABLgAECgYJGQAKAKoKAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8gAAIBAAgJEhjbLgDlAQABAAgJEhjbLgDlAQAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Razzleyi:BAAALgADCggJGQAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAECgkJDwAQAAAAAA==.Rebuke:BAAALgAECgUJBQAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgQJBAAAAA==.Rendezvous:BAAALgAECgEJAwAAAA==.Renkà:BAAALgADCgMJAwABLgAECggJIQAaAIcWAA==.Requestor:BAAALgAECgUJBQABLgAECgYJCgAQAAAAAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8JAAIDAAMJdQ2HMgDtAAADAAMJdQ2HMgDtAAAuAAQKfyMAAgMACAkhG4kuAGkCAAMACAkhG4kuAGkCAAAA.Revaerlous:BAABLgAECn8uAAIOAAkJiR3bFABUAgAOAAkJiR3bFABUAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwAQAAAAAA==.Rhei:BAABLgAECn8RAAIVAAgJIBkWLgBEAgAVAAgJIBkWLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8VAAIhAAUJ1wvPAgDPAAAhAAUJ1wvPAgDPAAAuAAQKfyQAAiEACQkBEqgSAKABACEACQkBEqgSAKABAAAA.',
Ro='Roereker:BAABLgAECn8nAAIDAAgJ/hYAJQDvAQADAAgJ/hYAJQDvAQAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgADCgYJBgAAAA==.Roketraccoon:BAAALgAECgMJBwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8UAAIfAAgJbhoEDwC5AQAfAAgJbhoEDwC5AQAAAA==.Roshamandes:BAABLgAECn8WAAIMAAgJERhzBADnAQAMAAgJERhzBADnAQAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8iAAIDAAkJnh4LCADRAgADAAkJnh4LCADRAgAAAA==.',
['Rè']='Rèi:BAAALgADCgcJBwABLgAECgYJHgAPAKIiAA==.',
['Ré']='Réstofarian:BAACLgAFFH8TAAIKAAQJIB7lDwBVAQAKAAQJIB7lDwBVAQAuAAQKfy0AAwoACQm0I1wCAHYDAAoACQm0I1wCAHYDAAkAAgkoGedmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAAALgAECggJEwAAAA==.Saiki:BAAALgAECgEJAQAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwAQAAAAAA==.Sandvichus:BAABLgAECn8ZAAIJAAkJ+x4IBwBoAgAJAAkJ+x4IBwBoAgAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDQABLgAFFAYJGwAKAN0jAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAABLgAECn8gAAITAAkJOCK7AgDEAgATAAkJOCK7AgDEAgAAAA==.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Sefik:BAAALgAECgYJDQAAAA==.Selaana:BAABLgAECn8YAAINAAYJPh9jIgD8AQANAAYJPh9jIgD8AQAAAA==.Serkis:BAAALgAECgIJAgAAAA==.Seyekosis:BAAALgAECgQJBAAAAA==.',
Sg='Sgathaich:BAEBLgAECn8iAAIbAAgJchctFwDUAQAbAAgJchctFwDUAQAAAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECggJJAAHACMZAA==.Shaio:BAABLgAECn8VAAIYAAYJ3Q9ZNgBGAQAYAAYJ3Q9ZNgBGAQAAAA==.Shallistiah:BAAALgADCggJCAABLgAECgcJIQAcANQjAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgUJCQAAAA==.Shambulence:BAABLgAFFH8HAAIHAAQJeAsTGgADAQAHAAQJeAsTGgADAQAAAA==.Shammlock:BAACLgAFFH8TAAQLAAUJYBB9AQCvAAAXAAMJYxFNQQDYAAALAAQJ+xB9AQCvAAAWAAIJxwIYFgBGAAAuAAQKfyYABAsACQnNHeECAIMCAAsACAmKHuECAIMCABcACQmGGScqAGcCABYABQl6EFgkADgBAAAA.Shampriest:BAAALgAECgIJAQAAAA==.Shamuel:BAAALgAECggJDgAAAA==.Shaylis:BAAALgADCgIJAgABLgAECggJIQAaAIcWAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJBQABLgAECgkJGwAIALEYAA==.Shobadon:BAAALgADCgcJBwAAAA==.Shole:BAABLgAECn8tAAMNAAkJTB1BBgCCAgANAAkJTB1BBgCCAgAHAAcJFByMEgAkAgAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAFFAIJAgAQAAAAAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwAQAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwAQAAAAAA==.Silchar:BAAALgADCgEJAQAAAA==.Silicon:BAABLgAECn8bAAIBAAgJwxT4OAC/AQABAAgJwxT4OAC/AQAAAA==.Sinfulangel:BAABLgAECn8hAAIOAAgJmxn9GwAhAgAOAAgJmxn9GwAhAgAAAA==.Siona:BAABLgAECn8uAAIPAAgJ0Qv3MACKAQAPAAgJ0Qv3MACKAQAAAA==.',
Sk='Skadie:BAABLgAECn8hAAMPAAkJ2hJRHADzAQAPAAkJ2hJRHADzAQAEAAEJ6wNFKwAqAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwop:BAAALgAECgEJAgABLgAECgkJDwAQAAAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgIJAwAAAA==.Slavalous:BAAALgAECgMJBQAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8bAAIeAAgJsRDHEgBFAQAeAAgJsRDHEgBFAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgcJIQAcANQjAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.',
Sp='Sparrkle:BAABLgAECn8dAAIWAAgJAgpcCwAfAQAWAAgJAgpcCwAfAQAAAA==.Spinjitzu:BAAALgAECgMJCgAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgMJCgAAAA==.',
Sq='Squadw:BAACLgAFFH8SAAITAAQJYx3NAgB2AQATAAQJYx3NAgB2AQAuAAQKfzgAAhMACQmtJIYAAFgDABMACQmtJIYAAFgDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAQAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgQJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn8nAAIhAAgJ9xbqCQCkAQAhAAgJ9xbqCQCkAQAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgADCgcJCgAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAQAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgADCgUJBQABLgAECgcJDQAQAAAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8UAAIVAAgJNhh7OAATAgAVAAgJNhh7OAATAgAAAA==.Sunsmite:BAABLgAECn8dAAIDAAcJrhb1PgCJAQADAAcJrhb1PgCJAQAAAA==.Suramar:BAAALgAECggJEgAAAA==.',
Sw='Sweetbippy:BAABLgAECn8cAAIBAAcJqQE3tACrAAABAAcJqQE3tACrAAAAAA==.Swifthealss:BAABLgAECn8XAAMKAAgJewZhQQANAQAKAAgJewZhQQANAQAJAAUJqwlKNQC4AAAAAA==.Swirls:BAAALgAECgEJAQAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwAQAAAAAA==.Sylunae:BAAALgADCgkJGwABLgAECgYJGQAKAKoKAA==.Syluné:BAABLgAECn8ZAAIKAAYJqgqBcQABAQAKAAYJqgqBcQABAQAAAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn8bAAIBAAgJIwqVTwB7AQABAAgJIwqVTwB7AQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAECgkJJAADAD4mAA==.Tacomonk:BAAALgAECggJCgAAAA==.Taelight:BAAALgADCggJDgABLgAECggJJAAHACMZAA==.Taelyx:BAABLgAECn8kAAMHAAgJIxlcIgCiAQAHAAgJIxlcIgCiAQANAAIJ3gkKfgBOAAAAAA==.Taicheeze:BAABLgAECn8UAAIGAAgJihQjEADKAQAGAAgJihQjEADKAQAAAA==.Tambot:BAAALgAECgQJCwAAAA==.Tariced:BAAALgAECgQJBAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgADCggJEwABLgAECgcJHAABAKkBAA==.Tazmina:BAABLgAECn8nAAITAAgJ/R7yBwDkAgATAAgJ/R7yBwDkAgAAAA==.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgEJAQABLgAECggJJwANAPYbAA==.Tessa:BAABLgAECn8nAAINAAgJ9humCABSAgANAAgJ9humCABSAgAAAA==.Texasfight:BAAALgADCgIJAgABLgAECggJNAAUAHEXAA==.Teyo:BAAALgAECgQJDgAAAA==.',
Th='Thedoctorwho:BAAALgAFFAEJAQAAAA==.Theholytaz:BAABLgAECn8XAAIDAAgJDBZiQQAhAgADAAgJDBZiQQAhAgAAAA==.Thunderr:BAAALgAECgcJBwAAAA==.Thörn:BAAALgAECgYJEQABLgAECgcJGwAKAPUVAA==.',
Ti='Time:BAAALgAECgMJAwAAAA==.Tinyjapeto:BAAALgAECgMJAwAAAA==.Titanbow:BAAALgADCgYJBgABLgAECggJKAAVAP0fAA==.',
To='Tomcatt:BAABLgAECn8vAAIPAAgJmx4LDAB/AgAPAAgJmx4LDAB/AgAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.',
Tr='Trailis:BAAALgAECgIJAgAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8dAAIZAAgJQATqHADUAAAZAAgJQATqHADUAAAAAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8cAAIgAAcJHhVFEABuAQAgAAcJHhVFEABuAQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn8eAAIiAAgJ3CF/AQDBAgAiAAgJ3CF/AQDBAgAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAIPAAYJIgevYQDrAAAPAAYJIgevYQDrAAAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAAALgAECgcJDQAAAA==.Unstable:BAAALgAECgQJBgAAAA==.',
Up='Upchucky:BAAALgADCgYJBwAAAA==.',
Va='Vaedeath:BAABLgAECn8mAAIgAAgJACBNBQBWAgAgAAgJACBNBQBWAgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgAECgEJAQAAAA==.Valaryon:BAAALgADCgkJHgAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn8vAAIKAAgJYxULGwDrAQAKAAgJYxULGwDrAQAAAA==.Valyteilssra:BAAALgAECgMJBQAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varindra:BAAALgAECgMJBAABLgAFFAIJAgAQAAAAAA==.',
Ve='Vegà:BAABLgAECn8eAAIGAAgJjBAvFwB/AQAGAAgJjBAvFwB/AQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgUJBgAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAQAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAQAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgIJAgAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAQJCwAlABUMAA==.',
Vo='Voidhax:BAAALgADCgUJBQAAAA==.Voidi:BAABLgAECn8XAAQaAAcJVyOpFQBiAgAaAAcJtCKpFQBiAgAjAAQJESEBDQBPAQAnAAEJtAOhDwAoAAAAAA==.Voidyo:BAABLgAFFH8GAAIVAAMJZhvWKgAGAQAVAAMJZhvWKgAGAQAAAA==.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn8YAAIFAAcJ0AkSIgAvAQAFAAcJ0AkSIgAvAQAAAA==.Vortice:BAABLgAECn8wAAQHAAgJjw18NAA6AQAHAAgJjw18NAA6AQANAAcJlhBEJQAtAQAiAAIJQAfaKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgADCgUJAwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECggJFwAMAEccAA==.Warraxmonk:BAAALgADCgYJBgABLgAECggJFwAMAEccAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgUJBwAAAA==.Whiskeyjak:BAABLgAECn8XAAMUAAgJzRkDJgBDAQAUAAYJOhIDJgBDAQAZAAMJoh+uFgANAQAAAA==.',
Wi='Willowest:BAABLgAECn8cAAIPAAcJNxlpJADEAQAPAAcJNxlpJADEAQAAAA==.',
Wr='Wrathstorm:BAABLgAECn8eAAIiAAgJBxvgBQDrAQAiAAgJBxvgBQDrAQAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8QAAIOAAUJ+BYyGABEAQAOAAUJ+BYyGABEAQAuAAQKfysAAg4ACQm+Ir8QABgDAA4ACQm+Ir8QABgDAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECggJJwAKAFsXAA==.Wurmy:BAABLgAECn8nAAMKAAgJWxchFwAMAgAKAAgJWxchFwAMAgAJAAYJSBNXIQAsAQAAAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIFAAYJaxaRKwB/AQAFAAYJaxaRKwB/AQAAAA==.Xanier:BAAALgAECgQJBgAAAA==.',
Xe='Xelagos:BAABLgAECn8ZAAQSAAgJchJiIwBeAQASAAcJdBFiIwBeAQAlAAMJCBy5JgDsAAAmAAMJ5BWnUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8WAAMCAAgJDhEBGQCGAQACAAgJDhEBGQCGAQARAAEJcwWkWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgMJBgAAAA==.Yisshaman:BAABLgAECn8eAAINAAkJXhvWDADQAgANAAkJXhvWDADQAgAAAA==.',
Yo='Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAGAJYQAA==.Yogimonk:BAABLgAECn8UAAIGAAUJlhCALwDdAAAGAAUJlhCALwDdAAAAAA==.',
Za='Zandarbribbs:BAABLgAECn8WAAIDAAYJixZlTgBbAQADAAYJixZlTgBbAQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgADCgkJFAAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8hAAIKAAgJMRh6FwAJAgAKAAgJMRh6FwAJAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn8nAAIGAAgJFh26BwBTAgAGAAgJFh26BwBTAgAAAA==.',
Zt='Ztropos:BAAALgAECgcJBwAAAA==.',
Zy='Zygal:BAAALgAECgMJBgAAAA==.',
['Zè']='Zèrà:BAAALgAECgEJAQAAAA==.',
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

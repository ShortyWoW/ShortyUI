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

local lookup = {'Mage-Frost','Priest-Holy','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Warrior-Arms','Druid-Balance','Warlock-Affliction','DemonHunter-Vengeance','Hunter-BeastMastery','Evoker-Preservation','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Devourer','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Warrior-Protection','Priest-Discipline','Rogue-Subtlety','Unknown-Unknown','Druid-Restoration','Paladin-Holy','Monk-Mistweaver','Druid-Feral','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','DeathKnight-Frost','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abysmal:BAAALgADCgYJBgABLgAECggJFwABAGUNAA==.Abÿss:BAAALgAECgIJAgAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgQJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8cAAICAAgJFA0MFQBoAQACAAgJFA0MFQBoAQAAAA==.Aeriona:BAABLgAECn8VAAIDAAYJbxnXMwBzAQADAAYJbxnXMwBzAQAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIEAAgJcQtQCgAsAQAEAAgJcQtQCgAsAQAAAA==.',
Ai='Aine:BAABLgAECn8VAAMCAAcJJBY/DwCwAQACAAYJwRk/DwCwAQAFAAYJ6wA5WABcAAAAAA==.Ainek:BAAALgAECgQJBgAAAA==.Ainkor:BAAALgAECgYJBgABLgAECgkJHAAGACwRAA==.',
Aj='Ajani:BAAALgAECgQJBAAAAA==.',
Ak='Akyospirit:BAABLgAECn8VAAIHAAYJgAtrLwADAQAHAAYJgAtrLwADAQAAAA==.',
Al='Al:BAAALgAECgYJDAABLgAECgkJGgAIALEYAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn8ZAAIJAAgJwQ5WGQAyAQAJAAgJwQ5WGQAyAQAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Alpha:BAABLgAECn8gAAIBAAgJbxp0GAAaAgABAAgJbxp0GAAaAgAAAA==.Alroy:BAAALgAECgkJCAAAAA==.Aluina:BAAALgAECgQJBAAAAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn8bAAIGAAgJYA86EACRAQAGAAgJYA86EACRAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn8VAAIKAAYJ4wwxBQA3AQAKAAYJ4wwxBQA3AQAAAA==.Amonet:BAAALgADCgYJCwAAAA==.',
An='Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgEJAQAAAA==.Anglico:BAAALgAECgQJBQABLgAECggJFgALAAIYAA==.Angliko:BAAALgAECgEJAQABLgAECggJFgALAAIYAA==.Anglikoo:BAAALgADCggJCAABLgAECggJFgALAAIYAA==.Anomandaris:BAAALgAECggJEgAAAA==.Anquan:BAAALgAECgcJEAAAAA==.',
Ap='Aphradite:BAAALgADCgYJBgAAAA==.Apothicc:BAAALgADCgIJAgAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8VAAIMAAYJ0QNqTgDjAAAMAAYJ0QNqTgDjAAAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8bAAIBAAcJKwW9ZQAPAQABAAcJKwW9ZQAPAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgAAAA==.Argobow:BAAALgAECgQJBAAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAAALgAECgQJBQAAAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAIMAAgJgRCdHgCoAQAMAAgJgRCdHgCoAQAAAA==.',
As='Ascender:BAAALgADCgMJBgAAAA==.Ashvalis:BAABLgAECn8WAAINAAcJ+CHDCQCaAgANAAcJ+CHDCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8jAAIDAAgJchYbXgDJAQADAAgJchYbXgDJAQAAAA==.Askr:BAAALgAECgYJDwAAAA==.Asphar:BAABLgAECn8aAAMMAAgJ3hrHDAA4AgAMAAgJ3hrHDAA4AgAEAAMJ8hIrFgB8AAAAAA==.',
Au='Aung:BAABLgAECn8rAAIOAAgJpyUOAgB4AwAOAAgJpyUOAgB4AwAAAA==.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgADCgYJEgABLgAECgcJHQAPAK0GAA==.Avralis:BAAALgADCgMJAwABLgAECggJFAAQAOIXAA==.',
Az='Azamii:BAABLgAECn8nAAMRAAgJZx6ABAB4AgARAAgJZx6ABAB4AgAHAAYJQRgQOwCVAQAAAA==.Azarion:BAABLgAECn8pAAMSAAgJuhoCGQCDAQASAAYJZBsCGQCDAQATAAUJoBcYPgA4AQAAAA==.Azill:BAACLgAFFH8KAAIUAAQJAhZaBABQAQAUAAQJAhZaBABQAQAuAAQKfyIAAhQACAmvHS4KANUCABQACAmvHS4KANUCAAAA.Azzrael:BAABLgAECn8mAAIVAAkJZxCZCwBrAQAVAAkJZxCZCwBrAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgMJAwAAAA==.Bartrak:BAABLgAECn8VAAMFAAcJHhVPEgBzAQAFAAcJHhVPEgBzAQAWAAMJ0g4jQwCcAAAAAA==.',
Be='Bearrific:BAABLgAECn8YAAIXAAgJ/hfhCADfAQAXAAgJ/hfhCADfAQAAAA==.Beawulf:BAAALgADCggJEQAAAA==.Belista:BAAALgADCggJEQAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bi='Billie:BAAALgADCgIJAgAAAA==.Billthekid:BAAALgADCgcJHgAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgADCgkJEQABLgAECgEJAQAYAAAAAA==.Binksy:BAACLgAFFH8HAAIPAAMJjg9JEgD2AAAPAAMJjg9JEgD2AAAuAAQKfycAAg8ACQn2G7gNAOgCAA8ACQn2G7gNAOgCAAAA.Biscuit:BAACLgAFFH8bAAIVAAYJgyL+AADXAQAVAAYJgyL+AADXAQAuAAQKfxkAAhUACQn0JO4AAJYDABUACQn0JO4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgMJBwAAAA==.Blazin:BAACLgAFFH8HAAIBAAQJ8QrKJQA9AQABAAQJ8QrKJQA9AQAuAAQKfxQAAgEACAncFk9wAPMBAAEACAncFk9wAPMBAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgYJBgAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Bloui:BAAALgAECgIJAgAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAYJGwAVAIMiAA==.Bongrips:BAAALgADCgIJAgAAAA==.Boomboom:BAAALgAECgIJAwAAAA==.Borlok:BAAALgAFFAEJAQAAAQ==.',
Br='Brannigan:BAABLgAECn8VAAIVAAYJnyTcBAAYAgAVAAYJnyTcBAAYAgAAAA==.Braulioo:BAAALgAECgEJAQAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAAALgAECgYJDgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgADCgEJAQAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJDQAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAAALgAECgYJEgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8XAAIIAAgJ4yFmAQClAgAIAAgJ4yFmAQClAgAAAA==.',
['Bé']='Béckley:BAAALgAECgcJDAAAAA==.Béckléy:BAAALgAECgUJDQABLgAECgcJDAAYAAAAAA==.',
Ca='Caatha:BAAALgADCggJEQAAAA==.Callox:BAABLgAECn8aAAMIAAgJsRjxEQCCAQAPAAgJ3hP9KwAFAgAIAAUJJxvxEQCCAQAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgMJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAABLgAECn8UAAIZAAUJNBZZYAAxAQAZAAUJNBZZYAAxAQAAAA==.Catriona:BAABLgAECn8YAAIMAAgJuAq3KgBpAQAMAAgJuAq3KgBpAQAAAA==.Cazmeer:BAAALgADCgkJEwAAAA==.',
Ch='Charcuterie:BAACLgAFFH8cAAIGAAYJAx2/AQDHAQAGAAYJAx2/AQDHAQAuAAQKfxgAAgYACQn+IF4JAPMCAAYACQn+IF4JAPMCAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMTAAMJ4wt+MADjAAATAAMJ4wt+MADjAAASAAIJrwIWDwCHAAAuAAQKfyYAAxIACAkiF4wJACcCABIACAmBFYwJACcCABMACAlzFBYaANkBAAAA.Chillainkor:BAABLgAECn8cAAIGAAkJLBEMLACtAQAGAAkJLBEMLACtAQAAAA==.Chillidán:BAABLgAECn8OAAIQAAgJ/QI1TQC+AAAQAAgJ/QI1TQC+AAAAAA==.Chippmagi:BAABLgAECn8YAAIBAAcJRxwuIwDcAQABAAcJRxwuIwDcAQAAAA==.Chippndots:BAAALgAECgEJAQABLgAECgcJGAABAEccAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAABLgAECn8VAAIaAAgJFxLoFACtAQAaAAgJFxLoFACtAQAAAA==.Chronosaren:BAAALgAECggJDgAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgYJFQAVAJ8kAA==.',
Cj='Cjrej:BAAALgAECgYJEgAAAA==.',
Cl='Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Cons:BAABLgAECn8aAAQWAAgJlxYJDADJAQAWAAcJrBUJDADJAQACAAMJ8QrGZQCWAAAFAAEJ7xLIPAA/AAAAAA==.Corellon:BAABLgAECn8gAAIMAAgJvBt9EwD2AQAMAAgJvBt9EwD2AQAAAA==.Costcohotdog:BAABLgAFFH8FAAMGAAMJPhlBGACsAAAGAAMJPhlBGACsAAAbAAEJOQBeGgAYAAABLgAFFAYJGwAVAIMiAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAAALgAECgYJEAAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8eAAIMAAYJnCLnFADrAQAMAAYJnCLnFADrAQAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB2AGwAGAgABAAgJWB2AGwAGAgAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
Da='Daario:BAABLgAECn8TAAIQAAcJsB+lNQAhAgAQAAcJsB+lNQAhAgAAAA==.Dabare:BAAALgADCgEJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECggJIAAcAPQdAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8gAAQcAAgJ9B2kDQABAQAcAAUJLh2kDQABAQAJAAYJ+Rx7IAD5AAAdAAcJVQknHADFAAAAAA==.Daenerys:BAAALgAECgIJBQAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAYAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgEJAQABLgAECggJGgABAJYYAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAAALgAECgMJBgAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgADCgcJDAAAAA==.Davidbowy:BAAALgAECgcJDQABLgAECgYJBwAYAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgADCgQJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECggJGgABAJYYAA==.Demina:BAAALgADCgUJBQABLgAECggJFAAQAOIXAA==.Demonainkor:BAAALgAECgEJAQABLgAECgkJHAAGACwRAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn8VAAMWAAYJqxd0FgA9AQAWAAYJixF0FgA9AQACAAUJ4xdxIAD+AAAAAA==.Desden:BAABLgAECn8VAAIdAAYJfxHoCwAAAQAdAAYJfxHoCwAAAQAAAA==.Devianchi:BAABLgAECn8iAAMbAAgJ9x+CCQC5AgAbAAgJ9x+CCQC5AgAUAAcJHh+VBgAjAgAAAA==.Devitodevour:BAABLgAECn8eAAMTAAgJOBsWEQAdAgATAAcJlRkWEQAdAgASAAMJXBkGNQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8HAAIeAAMJUiGwLAAMAQAeAAMJUiGwLAAMAQAuAAQKfzEAAh4ACAk9IxcGAL4CAB4ACAk9IxcGAL4CAAAA.',
Dh='Dhbert:BAABLgAECn8ZAAIfAAgJAg/6GwBtAQAfAAgJAg/6GwBtAQAAAA==.Dhomeli:BAAALgAECgEJAQAAAA==.',
Di='Disastrophy:BAAALgAECgYJEQAAAA==.Disturbed:BAABLgAECn8dAAQTAAgJnBkgFQD8AQATAAcJnBkgFQD8AQASAAEJAADUYgBJAAAKAAEJAABGNwAlAAAAAA==.Disturbio:BAAALgADCgIJAwABLgAECggJHQATAJwZAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgADCgMJAwAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwATABgiAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgEJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECggJDgAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgADCgcJFwAAAA==.Dramûl:BAAALgAECggJDAAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgADCgIJAgAAAA==.Drunkdragon:BAABLgAECn8UAAIUAAgJRBLiGwD9AQAUAAgJRBLiGwD9AQAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAAALgAECggJDgAAAA==.Duress:BAAALgADCgEJAQAAAA==.Dustyknight:BAABLgAECn8WAAIfAAcJMwjqGAC1AAAfAAcJMwjqGAC1AAAAAA==.',
Dw='Dwell:BAAALgADCgkJGwAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgADCgMJAwABLgAECggJGwAgADAVAA==.',
Ed='Edge:BAABLgAECn8ZAAIHAAgJyBR7FgCzAQAHAAgJyBR7FgCzAQAAAA==.',
Ee='Eelenna:BAABLgAECn8WAAMhAAgJ1BxgBgCSAgAhAAgJ1BxgBgCSAgARAAUJwRBaUwD4AAABLgAECggJGQAiACYfAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAECgQJCQABLgAECggJFAAQAOIXAA==.Eleros:BAABLgAECn8gAAIQAAgJ/BpYCwAoAgAQAAgJ/BpYCwAoAgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8ZAAMXAAgJvxA1CwC2AQAXAAgJvxA1CwC2AQAjAAEJ4BFiIAAxAAAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgADCgcJHAAAAA==.',
En='Endarial:BAAALgAECgIJAgAAAA==.Enoki:BAABLgAFFH8GAAIHAAMJQxaNEADkAAAHAAMJQxaNEADkAAABLgAFFAYJGgAZAOgjAA==.',
Er='Eraduckated:BAAALgAECgMJAwABLgAECggJGwAgADAVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgADCggJDgABLgAECgYJFQAJAMEKAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAECgIJBgAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.',
Fa='Farnesë:BAAALgADCgUJBwABLgADCgcJBwAYAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAQAAAA==.',
Fe='Fedders:BAABLgAECn8jAAIDAAgJiCaFBwBbAwADAAgJiCaFBwBbAwAAAA==.Felaids:BAACLgAFFH8HAAITAAQJOghMNwDIAAATAAQJOghMNwDIAAAuAAQKfyoAAxMACAk8HEcOADgCABMABwk8HEcOADgCABIAAwkSCLVEAKIAAAAA.Felimonk:BAAALgADCgQJBAABLgABCgQJBQAYAAAAAA==.Felpecs:BAAALgAECgMJAwAAAA==.Feyda:BAAALgAECgcJEwAAAA==.',
Fi='Fillon:BAABLgAECn8kAAIDAAgJgSN7CQCHAgADAAgJgSN7CQCHAgAAAA==.Firessar:BAAALgAECgEJAgAAAA==.Fishfood:BAABLgAECn8VAAIiAAYJExCgBQA1AQAiAAYJExCgBQA1AQAAAA==.Fixer:BAAALgADCgkJFAAAAA==.',
Fk='Fk:BAAALgAECgIJAwABLgAECggJDgAYAAAAAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECgUJBQAAAA==.Frimthemage:BAABLgAECn8lAAIBAAgJXB7MEwA8AgABAAgJXB7MEwA8AgAAAA==.Frostmaster:BAAALgAECgUJEQAAAA==.',
['Fø']='Førd:BAACLgAFFH8HAAMkAAMJiwtHBgCrAAAkAAIJfRBHBgCrAAAlAAIJiwj6IwCMAAAuAAQKfyYAAyQACAmIHBcLACoCACQABwlLGhcLACoCACUABgljGSAkAJwBAAAA.',
Ga='Gammon:BAAALgAECgcJEgAAAA==.Gangrene:BAABLgAECn8mAAIeAAgJUBMgJgCnAQAeAAgJUBMgJgCnAQAAAA==.Gary:BAAALgAECgQJBgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAAALgAECgcJEwAAAA==.Gaviin:BAABLgAECn8iAAIjAAgJgiGsAACvAgAjAAgJgiGsAACvAgAAAA==.',
Ge='Gearador:BAAALgADCgEJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEgAYAAAAAA==.Gerhart:BAABLgAECn8cAAQQAAgJUxhPTQC+AAAQAAcJahlPTQC+AAALAAUJlg9gHACqAAAOAAEJSg5kcwAxAAAAAA==.Getty:BAAALgAECgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAgAAAA==.Gigarius:BAABLgAECn8ZAAIgAAgJSyT4AADKAgAgAAgJSyT4AADKAgAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAAALgAECgMJBgAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAABLgAECn8ZAAIiAAgJJh+1AACKAgAiAAgJJh+1AACKAgAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECggJIAAcAPQdAA==.Griffmonk:BAABLgAECn8iAAIbAAgJLximDQDLAQAbAAgJLximDQDLAQAAAA==.Grumpymage:BAABLgAECn8gAAIBAAgJoxwpFgArAgABAAgJoxwpFgArAgAAAA==.',
Ha='Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgADCgkJJgAAAA==.Hara:BAABLgAECn8aAAIZAAYJOxpUHgCOAQAZAAYJOxpUHgCOAQAAAA==.Hardord:BAAALgAECgUJDgAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgADCgkJEwAAAA==.Hayanne:BAABLgAECn8nAAIVAAgJyxh1BQAGAgAVAAgJyxh1BQAGAgAAAA==.',
He='Healchucky:BAAALgAECgQJBwAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgQJBQAAAA==.Heina:BAAALgAECgYJBgAAAA==.',
Hi='Hitnrun:BAAALgADCgkJEQAAAA==.',
Ho='Hochunk:BAAALgAECgkJCgAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAAALgAECggJEQAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8VAAIaAAgJdgxzHgBVAQAaAAgJdgxzHgBVAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8YAAIDAAcJZRS+PwBKAQADAAcJZRS+PwBKAQAAAA==.Honeybun:BAAALgADCgIJAgAAAA==.Honorlife:BAABLgAECn8YAAIHAAcJUxgpGQCaAQAHAAcJUxgpGQCaAQAAAA==.Hopeudie:BAAALgAECgUJBgABLgAECggJDgAYAAAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgQJBQAAAA==.Hughass:BAAALgADCgEJAQAAAA==.',
['Hâ']='Hârley:BAABLgAECn8YAAIZAAYJiyCQFgDOAQAZAAYJiyCQFgDOAQAAAA==.',
['Hí']='Híram:BAABLgAECn8gAAIDAAgJHxTNIwC2AQADAAgJHxTNIwC2AQAAAA==.',
Id='Idyllwild:BAAALgAECgEJAQAAAA==.',
Ih='Ihsan:BAAALgAECgYJDwAAAA==.',
Il='Ilharess:BAABLgAECn8aAAIBAAgJhxOwewDaAQABAAgJhxOwewDaAQAAAA==.',
In='Inko:BAAALgADCgYJCQABLgAFFAMJBgAVAF4cAA==.Inkpot:BAAALgAECgEJAQABLgAECgcJJgAZAAAmAA==.Inkwell:BAABLgAECn8mAAIZAAcJACb8CAAAAwAZAAcJACb8CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgIJAgAAAA==.',
Ja='Jaardrius:BAABLgAECn8aAAMbAAYJfiOSBwBBAgAbAAYJfiOSBwBBAgAUAAMJjgusXgCVAAAAAA==.Jakobo:BAAALgAECgQJBQAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgEJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgADCgcJEwAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAYJGgAZAOgjAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgADCgYJBgAAAA==.',
Ju='Junebuge:BAAALgADCgcJDQAAAA==.Junknthtrunk:BAAALgADCggJEAAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAXAIYjAA==.',
Ke='Keanew:BAABLgAECn8jAAQOAAgJaBwjDQBqAQAOAAgJFBwjDQBqAQALAAUJkA/FCgDuAAAQAAMJwQJbcQBeAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8iAAMaAAYJcSGlIAAWAgAaAAYJcSGlIAAWAgADAAEJIwHcYQEUAAAAAA==.Kenry:BAAALgAECgIJAgAAAA==.Keonna:BAAALgAECgIJAgAAAA==.Keppra:BAAALgAECgIJAgAAAA==.Kerlin:BAABLgAECn8aAAMZAAgJDQ9eWABJAQAZAAcJ1QteWABJAQAJAAEJ5AJliAAnAAAAAA==.Keyaira:BAAALgADCgYJBgAAAA==.Keybash:BAABLgAECn8UAAMTAAYJmQVXXQDaAAATAAYJegVXXQDaAAAKAAMJagNuHwB1AAAAAA==.Keíga:BAAALgAECgIJAgAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAYJGgAZAOgjAA==.Kimmex:BAAALgADCgIJAgAAAA==.Kinoxo:BAACLgAFFH8UAAMPAAYJuBkwCgBVAQAPAAQJqxwwCgBVAQAIAAUJzxHZBgCnAAAuAAQKfxcAAw8ACAkDIeYaAHQCAA8ACAnrHeYaAHQCAAgAAwlwHasgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8dAAIDAAcJRBRgLQCMAQADAAcJRBRgLQCMAQAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgMJAwAAAA==.',
Kr='Kragge:BAAALgADCgcJBwAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgADCgcJDAAAAA==.Kynlas:BAAALgADCgIJAgAAAA==.Kyratinx:BAAALgAECgEJAgAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAECggJDgAYAAAAAA==.Larious:BAABLgAECn8gAAIDAAgJvhhoFAAYAgADAAgJvhhoFAAYAgAAAA==.',
Le='Ledikens:BAAALgADCgkJEQAAAA==.Legnase:BAABLgAECn8kAAMWAAgJoh5NAwC1AgAWAAgJAR5NAwC1AgACAAIJWxYYMAB8AAABLgAECggJJwARAGceAA==.Leht:BAABLgAECn8VAAMJAAYJwQqEIAD5AAAJAAYJwQqEIAD5AAAZAAEJawGG7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIPAAcJPh/YGgB1AgAPAAcJPh/YGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgADCgcJBwAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lili:BAAALgADCgIJAgAAAA==.Lilnasty:BAABLgAECn8XAAIBAAgJZQ0LOQCEAQABAAgJZQ0LOQCEAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Livesey:BAAALgAECgQJBQAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAUAEQSAA==.Lokahn:BAABLgAECn8WAAIUAAYJ1hl6IwC6AQAUAAYJ1hl6IwC6AQAAAA==.Longhornpibe:BAABLgAECn8sAAMPAAcJxhZPFgCBAQAPAAcJxhZPFgCBAQAIAAMJQQ4IGQCxAAAAAA==.Loudog:BAABLgAECn8iAAMeAAgJOBQxKgCTAQAeAAgJ+xIxKgCTAQAfAAYJEQ5MFADhAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.',
Ly='Lynxie:BAABLgAECn8fAAIFAAgJ1Q6gEACGAQAFAAgJ1Q6gEACGAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgADCggJDgAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIGAAcJliBsEACXAgAGAAcJliBsEACXAgABLgAFFAYJGwAVAIMiAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAAALgAECgMJBwAAAA==.Malus:BAABLgAECn8YAAITAAgJLA6xYQClAQATAAgJLA6xYQClAQAAAA==.Manders:BAAALgADCgIJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgADCggJEQAAAA==.Mattydruid:BAAALgAECgIJAgAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAABLgAECn8lAAMMAAgJZxXFGQDGAQAMAAcJwRfFGQDGAQAEAAgJmQxwDwDUAAAAAA==.Mayge:BAABLgAECn8fAAIBAAgJAhsjFgArAgABAAgJAhsjFgArAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAAALgAECgYJDgAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Mels:BAAALgAECgQJBAAAAA==.Mendinna:BAABLgAECn8XAAIOAAYJqQrGNwAmAQAOAAYJqQrGNwAmAQAAAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAGAJQQAA==.Methir:BAAALgADCgYJCQAAAA==.',
Mi='Miffed:BAAALgAECggJEgABLgAFFAQJEAAgADUGAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECgUJCwAAAA==.Mirage:BAABLgAECn8VAAIXAAcJhiMQFwBSAgAXAAcJhiMQFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn8kAAIUAAkJoR57AgC1AgAUAAkJoR57AgC1AgAAAA==.',
Mo='Montebrew:BAAALgAECgMJAwAAAA==.Mooky:BAABLgAECn8fAAIJAAgJXw69EgB0AQAJAAgJXw69EgB0AQAAAA==.Mopeia:BAABLgAECn8ZAAIZAAYJgBftJABdAQAZAAYJgBftJABdAQABLgAECgYJEwAYAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgYJGgAeADIjAA==.Mortemore:BAACLgAFFH8MAAIQAAQJWBdXEgAwAQAQAAQJWBdXEgAwAQAuAAQKfxsAAhAACQlRHmYrAFICABAACQlRHmYrAFICAAAA.Motet:BAAALgAECgYJCwAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECggJEQAAAA==.',
My='Mynoghra:BAAALgAECgYJDQAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Naproxen:BAABLgAECn8gAAImAAgJ5R1nAwBkAgAmAAgJ5R1nAwBkAgAAAA==.Naraku:BAACLgAFFH8HAAMTAAQJvQwUHQAuAQATAAQJFQwUHQAuAQASAAEJFhKmFABVAAAuAAQKfyQAAxMACAnAHTweAKECABMACAl/HDweAKECABIABglbHucNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Netty:BAAALgAECgIJAgAAAA==.',
Ni='Niklaus:BAABLgAECn8YAAIDAAcJchZTaACvAQADAAcJchZTaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAYAAAAAA==.',
Ny='Nymeera:BAABLgAECn8YAAMdAAgJfAbQEQCdAAAdAAcJ1gbQEQCdAAAcAAIJSwNCGgBPAAAAAA==.Nymphetamine:BAABLgAECn8fAAMCAAcJmxnsCAAaAgACAAcJmxnsCAAaAgAWAAQJ3QQQJQCqAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8YAAIFAAgJ8AwaEwBsAQAFAAgJ8AwaEwBsAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIeAAYJXhjZbgCrAQAeAAYJXhjZbgCrAQAAAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn8cAAIEAAgJUg0SBwB2AQAEAAgJUg0SBwB2AQAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.',
Ow='Owful:BAAALgADCgkJDwAAAA==.',
Pa='Pagerduty:BAAALgADCgcJCwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAAALgAECggJDgAAAA==.Papaya:BAACLgAFFH8aAAIZAAYJ6COYAQD+AQAZAAYJ6COYAQD+AQAuAAQKfxwAAxkACQnZIcUGAB8DABkACQnZIcUGAB8DAAkABgleIo4jAOABAAAA.',
Pe='Penelopea:BAABLgAECn8bAAIBAAcJYRN7NACTAQABAAcJYRN7NACTAQAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJBgAAAA==.',
Ph='Phaith:BAAALgADCgUJCwAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECgcJEgAYAAAAAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Po='Porteagarder:BAAALgAECgYJDwABLgAECgYJGQAZAKcKAA==.Potatodruid:BAAALgAECgQJBwAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAAALgAECgkJDQAAAA==.Preront:BAACLgAFFH8cAAMhAAcJTSAIAACBAgAhAAYJoiMIAACBAgARAAcJCRqMAQDlAQAuAAQKfx8AAyEACQngJikAAOYDACEACQngJikAAOYDABEAAwktJqY+AFABAAAA.Pringler:BAAALgAECgQJBAABLgAFFAYJGwAVAIMiAA==.Producktive:BAABLgAECn8bAAIgAAgJMBXBEAC6AQAgAAgJMBXBEAC6AQAAAA==.Prometeus:BAAALgADCggJCAAAAA==.Pros:BAABLgAECn8iAAISAAkJORRYDQDvAQASAAkJORRYDQDvAQAAAA==.Pruulia:BAAALgADCgMJAwABLgAECgYJFQAJAMEKAA==.Príestly:BAAALgAECgEJAQAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAAALgAECgYJEgABLgAFFAQJDAAQAFgXAA==.Puffthemagic:BAAALgAECggJDQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8bAAIKAAgJlBiBAQD+AQAKAAgJlBiBAQD+AQAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAYAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAAALgADCgkJIgABLgAECgYJGQAZAKcKAA==.Quiny:BAAALgADCgEJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgADCgcJBwAAAA==.Rassputin:BAABLgAECn8gAAIBAAgJDhjgHwDtAQABAAgJDhjgHwDtAQAAAA==.Ravnmoon:BAAALgADCgcJBwAAAA==.Razzleyi:BAAALgADCggJEQAAAA==.',
Re='Realmack:BAAALgAECggJCgABLgAECggJDgAYAAAAAA==.Rebuke:BAAALgAECgUJBQAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgQJBAAAAA==.Rendezvous:BAAALgAECgEJAgAAAA==.Renkà:BAAALgADCgMJAwABLgAECggJGQAXAL8QAA==.Requestor:BAAALgAECgUJBQAAAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8GAAIDAAMJcw2cIQDwAAADAAMJcw2cIQDwAAAuAAQKfyMAAgMACAkhG4wuAGkCAAMACAkhG4wuAGkCAAAA.Revaerlous:BAABLgAECn8mAAIeAAkJhh0wCwByAgAeAAkJhh0wCwByAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEgAYAAAAAA==.Rhei:BAABLgAECn8RAAIQAAgJIBkcLgBEAgAQAAgJIBkcLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8QAAIgAAQJNQbRAgDPAAAgAAQJNQbRAgDPAAAuAAQKfyQAAiAACQn/EacSAKABACAACQn/EacSAKABAAAA.',
Ro='Roereker:BAABLgAECn8fAAIDAAcJiBb2KgCWAQADAAcJiBb2KgCWAQAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgADCgYJBgAAAA==.Roketraccoon:BAAALgAECgMJBwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAAALgAECggJEQAAAA==.Roshamandes:BAABLgAECn8WAAILAAgJAhgIAwD0AQALAAgJAhgIAwD0AQAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8ZAAIDAAgJKx0NDgBSAgADAAgJKx0NDgBSAgAAAA==.',
['Ré']='Réstofarian:BAACLgAFFH8PAAIZAAQJIx43CgBeAQAZAAQJIx43CgBeAQAuAAQKfywAAxkACQmzI10CAHYDABkACQmzI10CAHYDAAkAAgkoGd5mAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAAALgAECggJEwAAAA==.Saiki:BAAALgADCgkJDgAAAA==.Saloriavis:BAEBLgAECn8dAAIeAAcJ3htyGQDwAQAeAAcJ3htyGQDwAQAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEgAYAAAAAA==.Sandvichus:BAABLgAECn8VAAIJAAgJSCCpCAAHAgAJAAgJSCCpCAAHAgAAAA==.Sanitarìum:BAAALgAECgQJBwAAAA==.Sardine:BAAALgAECgcJDQABLgAFFAYJGgAZAOgjAA==.Sasukie:BAAALgAECgEJBAAAAA==.Savagesmonk:BAAALgAECgIJAgAAAA==.Saxa:BAABLgAECn8aAAIOAAkJJCJCBwDyAgAOAAkJJCJCBwDyAgAAAA==.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Sefik:BAAALgAECgYJDQAAAA==.Selaana:BAABLgAECn8YAAIRAAYJOh8pEwCCAQARAAYJOh8pEwCCAQAAAA==.',
Sg='Sgathaich:BAEBLgAECn8eAAIaAAgJ3hZkJQD7AQAaAAgJ3hZkJQD7AQAAAA==.',
Sh='Shaio:BAABLgAECn8VAAIUAAYJ2g9dNgBGAQAUAAYJ2g9dNgBGAQAAAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgUJBQAAAA==.Shambulence:BAAALgAFFAMJAwAAAA==.Shammlock:BAACLgAFFH8PAAQKAAQJTg59AQCvAAATAAMJWBHoLADuAAAKAAIJUQp9AQCvAAASAAIJxALWDwBOAAAuAAQKfyYABAoACQnNHeECAIMCAAoACAmKHuECAIMCABMACQmEGScqAGcCABIABQl6EFwkADgBAAAA.Shamuel:BAAALgAECgYJBgAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJBQABLgAECgkJGgAIALEYAA==.Shobadon:BAAALgADCgcJBwAAAA==.Shole:BAABLgAECn8lAAMRAAkJZhv9BQBPAgARAAkJZhv9BQBPAgAHAAcJrhtADAAnAgAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQAAAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEgAYAAAAAA==.Sigvalden:BAAALgAECggJDQABLgAECggJEgAYAAAAAA==.Sigvolden:BAAALgAECgYJAQABLgAECggJEgAYAAAAAA==.Silchar:BAAALgADCgEJAQAAAA==.Silicon:BAABLgAECn8bAAIBAAgJwhTVJwDGAQABAAgJwhTVJwDGAQAAAA==.Siona:BAABLgAECn8mAAIMAAgJGAlLKAB2AQAMAAgJGAlLKAB2AQAAAA==.',
Sk='Skadie:BAABLgAECn8eAAMMAAgJHhOFHAC0AQAMAAgJHhOFHAC0AQAEAAEJ6APOJAAqAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwop:BAAALgAECgEJAgABLgAECggJDgAYAAAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgIJAwAAAA==.Slavalous:BAAALgAECgMJBQAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAAALgAECgYJEwAAAA==.Snnorri:BAAALgADCggJFgABLgAECgYJGgAbAH4jAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.',
Sp='Sparrkle:BAABLgAECn8dAAISAAgJBQqLCAAlAQASAAgJBQqLCAAlAQAAAA==.Spinjitzu:BAAALgAECgMJBwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgMJBwAAAA==.',
Sq='Squadw:BAACLgAFFH8OAAIOAAQJ/xhTAwBdAQAOAAQJ/xhTAwBdAQAuAAQKfzEAAg4ACQmXI50AACADAA4ACQmXI50AACADAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAYAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgIJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn8nAAIgAAgJ+BYCBwCuAQAgAAgJ+BYCBwCuAQAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgADCgcJCgAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAYAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgADCgQJBAABLgAECgcJDQAYAAAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8UAAIQAAgJ4heCOAATAgAQAAgJ4heCOAATAgAAAA==.Sunsmite:BAABLgAECn8dAAIDAAcJpxYGKwCWAQADAAcJpxYGKwCWAQAAAA==.Suramar:BAAALgAECggJDQAAAA==.',
Sw='Sweetbippy:BAABLgAECn8VAAIBAAYJlgGLnACQAAABAAYJlgGLnACQAAAAAA==.Swifthealss:BAAALgAECggJEgAAAA==.Swirls:BAAALgAECgEJAQAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEgAYAAAAAA==.Sylunae:BAAALgADCgkJEgABLgAECgYJGQAZAKcKAA==.Syluné:BAABLgAECn8ZAAIZAAYJpwr0QwDAAAAZAAYJpwr0QwDAAAAAAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAAALgAECgcJEwAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAECggJIwADAIgmAA==.Tacomonk:BAAALgAECgcJCAAAAA==.Taelight:BAAALgADCggJDgAAAA==.Taelyx:BAABLgAECn8iAAMHAAgJ/xYmHACCAQAHAAgJ/xYmHACCAQARAAIJ3gkOfgBOAAAAAA==.Taicheeze:BAAALgAECggJEgAAAA==.Tambot:BAAALgAECgQJCwAAAA==.Tariced:BAAALgADCggJGAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgADCggJCwABLgAECgYJFQABAJYBAA==.Tazmina:BAABLgAECn8iAAIOAAgJ/R7zBwDkAgAOAAgJ/R7zBwDkAgAAAA==.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgEJAQABLgAECggJHwARACIYAA==.Tessa:BAABLgAECn8fAAIRAAgJIhjgCQD9AQARAAgJIhjgCQD9AQAAAA==.Texasfight:BAAALgADCgIJAgABLgAECggJLAAPAMYWAA==.Teyo:BAAALgAECgQJDgAAAA==.',
Th='Thedoctorwho:BAAALgAECggJDgAAAA==.Theholytaz:BAABLgAECn8XAAIDAAgJDBZiQQAhAgADAAgJDBZiQQAhAgAAAA==.Thörn:BAAALgAECgUJDwABLgAECgUJFAAZADQWAA==.',
Ti='Time:BAAALgADCgcJDQAAAA==.Titanbow:BAAALgADCgYJBgABLgAECggJIAAQAPwaAA==.',
To='Tomcatt:BAABLgAECn8nAAIMAAgJ2BmUDQAxAgAMAAgJ2BmUDQAxAgAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.',
Tr='Trailis:BAAALgAECgIJAgAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Treè:BAAALgAECgMJBwAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8dAAIVAAgJPwQbFgDXAAAVAAgJPwQbFgDXAAAAAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8YAAIfAAcJxRRrCgBrAQAfAAcJxRRrCgBrAQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn8WAAIhAAcJlhweBAD1AQAhAAcJlhweBAD1AQAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8UAAIMAAYJIgc2SQD2AAAMAAYJIgc2SQD2AAAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAAALgAECgMJAwAAAA==.Unstable:BAAALgAECgQJBgAAAA==.',
Up='Upchucky:BAAALgADCgYJBwAAAA==.',
Va='Vaedeath:BAABLgAECn8fAAIfAAcJEiI6AwAjAgAfAAcJEiI6AwAjAgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgADCgkJFAAAAA==.Valaryon:BAAALgADCgkJHgAAAA==.Valkorin:BAAALgAECgUJBgAAAA==.Valoryan:BAABLgAECn8nAAIZAAgJBQ/0JABcAQAZAAgJBQ/0JABcAQAAAA==.Valyteilssra:BAAALgAECgIJAgAAAA==.Varindra:BAAALgAECgEJAQABLgAECgEJAQAYAAAAAA==.',
Ve='Vegà:BAABLgAECn8ZAAIGAAgJ1wyzEgB0AQAGAAgJ1wyzEgB0AQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAYAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAYAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgIJAgAAAA==.',
Vo='Voidhax:BAAALgADCgUJBQAAAA==.Voidi:BAABLgAECn8XAAQXAAcJVyOrFQBiAgAXAAcJtCKrFQBiAgAjAAQJESEBDQBPAQAnAAEJtAOjDwAoAAAAAA==.Voidyo:BAAALgAFFAIJBAAAAA==.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn8VAAIFAAYJZwqFHQAQAQAFAAYJZwqFHQAQAQAAAA==.Vortice:BAABLgAECn8qAAQRAAcJORXrHwAaAQARAAYJjxPrHwAaAQAHAAcJow2nLgAHAQAhAAIJQAfVKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgADCgUJAwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECggJFQALAM4bAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgUJBwAAAA==.Whiskeyjak:BAAALgAECggJEQAAAA==.',
Wi='Willowest:BAABLgAECn8VAAIMAAYJXxlZJACKAQAMAAYJXxlZJACKAQAAAA==.',
Wr='Wrathstorm:BAABLgAECn8eAAIhAAgJCRueAwAKAgAhAAgJCRueAwAKAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8MAAIeAAQJ9BYsGABEAQAeAAQJ9BYsGABEAQAuAAQKfysAAh4ACQmxIsIQABgDAB4ACQmxIsIQABgDAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgcJHwAZAOYYAA==.Wurmy:BAABLgAECn8fAAMZAAcJ5hi4EgD0AQAZAAcJ5hi4EgD0AQAJAAIJRhFvbABuAAAAAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAAALgAECgYJEwAAAA==.Xanier:BAAALgAECgIJAgAAAA==.',
Xe='Xelagos:BAABLgAECn8ZAAQNAAgJahJhIwBeAQANAAcJaxFhIwBeAQAkAAMJCBy9JgDsAAAlAAMJ3hWpUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8WAAMCAAgJEBFgEQCVAQACAAgJEBFgEQCVAQAWAAEJcwWhWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgMJBgAAAA==.Yisshaman:BAABLgAECn8eAAIRAAkJXhvUDADQAgARAAkJXhvUDADQAgAAAA==.',
Yo='Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAGAJQQAA==.Yogimonk:BAABLgAECn8UAAIGAAUJlBDxJADgAAAGAAUJlBDxJADgAAAAAA==.',
Za='Zandarbribbs:BAAALgAECgYJEAAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgADCgkJFAAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8ZAAIZAAgJWRZRGQC2AQAZAAgJWRZRGQC2AQAAAA==.Zeon:BAAALgAECgYJEQAAAA==.',
Zi='Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn8fAAIGAAcJYRsrCgDoAQAGAAcJYRsrCgDoAQAAAA==.',
Zy='Zygal:BAAALgAECgMJBQAAAA==.',
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

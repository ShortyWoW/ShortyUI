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

local lookup = {'Unknown-Unknown','Priest-Holy','Monk-Brewmaster','Druid-Balance','Mage-Frost','Priest-Discipline','Hunter-BeastMastery','Evoker-Preservation','Paladin-Retribution','Hunter-Marksmanship','DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Warrior-Protection','Rogue-Subtlety','Warrior-Fury','Warrior-Arms','Druid-Restoration','DemonHunter-Devourer','Druid-Feral','Druid-Guardian','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Holy','Priest-Shadow','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abysmal:BAAALgADCgYJBgABLgAECgYJEwABAAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgQJBQAAAA==.',
Ae='Aeliis:BAABLgAECn8UAAICAAcJDg27CwA4AQACAAcJDg27CwA4AQAAAA==.Aeriona:BAAALgAECgYJDwAAAA==.',
Ag='Agamsi:BAAALgAECgYJEgAAAA==.',
Ai='Aine:BAAALgAECgkJDwAAAA==.Ainek:BAAALgAECgQJBQAAAA==.Ainkor:BAAALgADCgYJCgABLgAECggJGwADAOEQAA==.',
Aj='Ajani:BAAALgAECgQJBAAAAA==.',
Ak='Akyospirit:BAAALgAECgYJDwAAAA==.',
Al='Al:BAAALgAECgYJBgAAAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn8YAAIEAAgJwQ7GCgBBAQAEAAgJwQ7GCgBBAQAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Alpha:BAABLgAECn8YAAIFAAcJvhTIGACAAQAFAAcJvhTIGACAAQAAAA==.Alroy:BAAALgAECgkJCAAAAA==.Aluina:BAAALgAECgQJBAAAAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAAALgAECgcJEwAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAAALgAECgYJDwAAAA==.Amonet:BAAALgADCgYJBwAAAA==.',
An='Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgADCgkJJgAAAA==.Anglico:BAAALgAECgQJBQABLgAECggJDgABAAAAAA==.Angliko:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.Anomandaris:BAAALgAECgcJEAAAAA==.Anquan:BAAALgAECgQJBgAAAA==.',
Ap='Aphradite:BAAALgADCgYJBgAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAAALgAECgYJDwAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8UAAIFAAYJIAXSPQDKAAAFAAYJIAXSPQDKAAAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgIJAgAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECgcJEQAAAA==.Argobow:BAAALgAECgQJBAAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAAALgAECgQJBQABLgAECgcJGwAGABckAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8aAAIHAAgJcw7NDQCYAQAHAAgJcw7NDQCYAQAAAA==.',
As='Ascender:BAAALgADCgMJBgAAAA==.Ashvalis:BAABLgAECn8VAAIIAAcJ5R++CQCaAgAIAAcJ5R++CQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8bAAIJAAcJ4hUfXgDJAQAJAAcJ4hUfXgDJAQAAAA==.Askr:BAAALgAECgQJCQAAAA==.Asphar:BAABLgAECn8UAAMHAAcJLB1BNgDVAQAHAAcJLB1BNgDVAQAKAAMJ8hI5DACAAAAAAA==.',
Au='Aung:BAABLgAECn8kAAILAAgJnyUMAgB4AwALAAgJnyUMAgB4AwAAAA==.Auri:BAAALgADCgkJGAAAAA==.',
Av='Avatan:BAAALgADCgYJDAABLgAECgcJEgABAAAAAA==.Avralis:BAAALgADCgMJAwABLgAECggJEQABAAAAAA==.',
Az='Azamii:BAABLgAECn8fAAMMAAcJfh5OBADmAQAMAAcJfh5OBADmAQANAAYJQRgROwCWAQABLgAECggJHAAGAAEZAA==.Azarion:BAABLgAECn8iAAMOAAcJlhgGGQCDAQAOAAUJ4hsGGQCDAQAPAAUJGRMekQA2AQAAAA==.Azill:BAACLgAFFH8HAAIQAAQJoRNaBABQAQAQAAQJoRNaBABQAQAuAAQKfx8AAhAACAmvHS0KANUCABAACAmvHS0KANUCAAAA.Azzrael:BAABLgAECn8dAAIRAAgJERLLFADAAQARAAgJERLLFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgEJAQAAAA==.Bandi:BAAALgADCgQJBQABLgAECgEJAQABAAAAAA==.Bartrak:BAAALgAECgYJDgAAAA==.',
Be='Bearrific:BAABLgAECn8UAAISAAcJvRk9BQCnAQASAAcJvRk9BQCnAQAAAA==.Beawulf:BAAALgADCgYJCQAAAA==.Belista:BAAALgADCgYJCQAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bi='Billie:BAAALgADCgIJAgAAAA==.Billthekid:BAAALgADCgcJFwAAAA==.Billybobb:BAAALgAECgYJCgAAAA==.Biney:BAAALgADCgcJDwABLgAECgEJAQABAAAAAA==.Binksy:BAABLgAECn8lAAITAAkJ9hu2DQDoAgATAAkJ9hu2DQDoAgAAAA==.Biscuit:BAACLgAFFH8WAAIRAAYJPB4AAQAJAgARAAYJPB4AAQAJAgAuAAQKfxkAAhEACQn0JO8AAJYDABEACQn0JO8AAJYDAAAA.Bitcoìn:BAAALgAECgEJAQAAAA==.',
Bl='Blaam:BAAALgAECgMJBAAAAA==.Blazin:BAAALgAFFAIJAgAAAA==.Blep:BAAALgAECgYJCgAAAA==.Blinkzy:BAAALgAECgUJCAAAAA==.Bloui:BAAALgADCggJHAAAAA==.',
Bo='Bongrips:BAAALgADCgIJAgAAAA==.Boomboom:BAAALgAECgIJAgAAAA==.Borlok:BAAALgAECgcJHwAAAQ==.',
Br='Brannigan:BAAALgAECgYJDwAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAAALgAECgYJDgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgcJIgAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgADCgEJAQAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJDQAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAAALgAECgQJCQAAAA==.',
['Bä']='Bärkler:BAAALgAECggJDwAAAA==.',
['Bé']='Béckley:BAAALgAECgcJDAAAAA==.Béckléy:BAAALgAECgUJDQABLgAECgcJDAABAAAAAA==.',
Ca='Caatha:BAAALgADCgYJCQAAAA==.Callox:BAABLgAECn8YAAMUAAgJMRfqEQCCAQATAAgJXRL7KwAFAgAUAAUJJxvqEQCCAQAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgMJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAABLgAECn8UAAIVAAUJNBZZYAAxAQAVAAUJNBZZYAAxAQAAAA==.Catriona:BAABLgAECn8UAAIHAAcJNgu0GAA2AQAHAAcJNgu0GAA2AQAAAA==.Cazmeer:BAAALgADCgYJDwAAAA==.',
Ch='Charcuterie:BAACLgAFFH8WAAIDAAYJyRZ3AQCMAQADAAYJyRZ3AQCMAQAuAAQKfxgAAgMACQn+IF0JAPMCAAMACQn+IF0JAPMCAAAA.Chaír:BAAALgAECgEJAwAAAA==.Cherudim:BAABLgAECn8eAAMOAAgJgRWJCQAnAgAOAAgJgRWJCQAnAgAPAAQJjQpN0AC5AAAAAA==.Chillainkor:BAABLgAECn8bAAIDAAgJ4RASLACtAQADAAgJ4RASLACtAQAAAA==.Chillidán:BAAALgAECgYJDAAAAA==.Chippmagi:BAAALgAECgYJEQAAAA==.Chippndots:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAAALgAECgcJDQAAAA==.Chronosaren:BAAALgAECgcJDAAAAA==.',
Ci='Cinterax:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.',
Cj='Cjrej:BAAALgAECgYJDwAAAA==.',
Cl='Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Cons:BAAALgAECgcJEgAAAA==.Corellon:BAABLgAECn8YAAIHAAYJgCDuLQD7AQAHAAYJgCDuLQD7AQAAAA==.Costcohotdog:BAAALgAFFAMJAwABLgAFFAYJFgARADweAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAAALgAECgYJCgAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8YAAIHAAYJPiLyHABYAgAHAAYJPiLyHABYAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8XAAIFAAcJ6hx4WAAwAgAFAAcJ6hx4WAAwAgAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
Da='Daario:BAABLgAECn8WAAIWAAgJ3R5gFABaAQAWAAgJ3R5gFABaAQAAAA==.Dabare:BAAALgADCgEJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECggJGQAXAHMaAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8ZAAQXAAgJcxqqGgAgAQAXAAQJQB6qGgAgAQAEAAUJnh2NRAAcAQAYAAcJVQkpHADFAAAAAA==.Daenerys:BAAALgAECgIJBAAAAA==.Dahouse:BAAALgADCgMJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgEJAQABLgAECggJEgAFABwYAA==.Darrow:BAAALgAECgYJBgAAAA==.Darthspawn:BAAALgAECgEJAgAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgADCgcJDAAAAA==.Davidbowy:BAAALgAECgcJDAABLgAECgUJBQABAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgADCgEJAQAAAA==.Delver:BAAALgADCgYJBgABLgAECggJEgAFABwYAA==.Demina:BAAALgADCgUJBQABLgAECggJEQABAAAAAA==.Demonainkor:BAAALgAECgEJAQABLgAECggJGwADAOEQAA==.Demonicfury:BAAALgAECgUJBQAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAAALgAECgYJDwAAAA==.Desden:BAAALgAECgYJDwAAAA==.Devianchi:BAABLgAECn8aAAMZAAgJwiK8CQC3AgAZAAcJ9CK8CQC3AgAQAAMJQRCiEwCgAAAAAA==.Devitodevour:BAABLgAECn8WAAMPAAgJLxsaCgDRAQAPAAYJohoaCgDRAQAOAAMJXBkINQDiAAAAAA==.',
Dg='Dgbugs:BAABLgAECn8mAAIaAAgJHh5XHwDFAgAaAAgJHh5XHwDFAgAAAA==.',
Dh='Dhbert:BAABLgAECn8YAAIbAAgJAg/6GwBtAQAbAAgJAg/6GwBtAQAAAA==.Dhomeli:BAAALgAECgEJAQAAAA==.',
Di='Disastrophy:BAAALgAECgYJCwAAAA==.Disturbed:BAABLgAECn8VAAQPAAgJcxhnPwAQAgAPAAcJcxhnPwAQAgAOAAEJAADOYgBJAAAcAAEJAABFNwAlAAAAAA==.Disturbio:BAAALgADCgIJAwABLgAECggJFQAPAHMYAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgADCgMJAwAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAPABgiAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgEJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECggJCAAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgADCgcJFwAAAA==.Dramûl:BAAALgAECgcJCgAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJBgAAAA==.Druknatsu:BAAALgADCgIJAgAAAA==.Drunkdragon:BAAALgAECggJDQAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAAALgAECggJDgAAAA==.Duress:BAAALgADCgEJAQAAAA==.Dustyknight:BAAALgAECgYJEAAAAA==.',
Dw='Dwell:BAAALgADCggJGQAAAA==.',
Ea='Earthquack:BAAALgADCgMJAwABLgAECggJGwAdADAVAA==.',
Ed='Edge:BAAALgAECgYJEwAAAA==.',
Ee='Eelenna:BAABLgAECn8UAAMeAAgJ7BtfBgCSAgAeAAgJ7BtfBgCSAgAMAAUJwRBSUwD4AAAAAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAECgQJCQABLgAECggJEQABAAAAAA==.Eleros:BAABLgAECn8aAAIWAAgJEhnXDgCTAQAWAAgJEhnXDgCTAQAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAAALgAECgYJEQAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgADCgcJFQAAAA==.',
En='Endarial:BAAALgADCggJHAAAAA==.Enoki:BAAALgAFFAMJBAABLgAFFAYJFQAVAOgjAA==.',
Er='Eraduckated:BAAALgADCgcJCgABLgAECggJGwAdADAVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgADCgYJBgABLgAECgYJDwABAAAAAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAECgIJBQAAAA==.',
Fa='Farnesë:BAAALgADCgUJBwAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAQAAAA==.',
Fe='Fedders:BAABLgAECn8jAAIJAAgJiCaEBwBbAwAJAAgJiCaEBwBbAwAAAA==.Felaids:BAACLgAFFH8GAAIPAAQJ8wKEEwDJAAAPAAQJ8wKEEwDJAAAuAAQKfyUAAw8ABwm7HQkUAHABAA8ABgm7HQkUAHABAA4AAwkSCLNEAKIAAAAA.Felimonk:BAAALgADCgQJBAABLgABCgQJBAABAAAAAA==.Felpecs:BAAALgAECgMJAwAAAA==.Feyda:BAAALgAECgcJDgAAAA==.',
Fi='Fillon:BAABLgAECn8eAAIJAAgJxSI5BABfAgAJAAgJxSI5BABfAgAAAA==.Firessar:BAAALgAECgEJAQAAAA==.Fishfood:BAAALgAECgYJDwAAAA==.Fixer:BAAALgADCgcJEgAAAA==.',
Fk='Fk:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECgUJBQAAAA==.Frimthemage:BAABLgAECn8eAAIFAAgJ1hjGEgCrAQAFAAgJ1hjGEgCrAQAAAA==.Frostmaster:BAAALgAECgUJDgAAAA==.',
['Fø']='Førd:BAABLgAECn8kAAMfAAgJiBwYCwAqAgAfAAcJSxoYCwAqAgAgAAYJTBkXJACcAQAAAA==.',
Ga='Gammon:BAAALgAECgYJCwAAAA==.Gangrene:BAABLgAECn8eAAIaAAcJGRPOEgB8AQAaAAcJGRPOEgB8AQAAAA==.Gary:BAAALgAECgQJBgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAAALgAECgYJDAAAAA==.Gaviin:BAABLgAECn8aAAIhAAgJTBgNAQDwAQAhAAgJTBgNAQDwAQAAAA==.',
Ge='Gearador:BAAALgADCgEJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECgcJEQABAAAAAA==.Gerhart:BAABLgAECn8YAAQWAAgJ3BVYdwBAAQAWAAYJlxhYdwBAAQAiAAUJeA9fHACqAAALAAEJSg5lcwAxAAAAAA==.Getty:BAAALgAECgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigarius:BAABLgAECn8VAAIdAAcJTiQAAQBWAgAdAAcJTiQAAQBWAgAAAA==.Gigglesworth:BAAALgADCgcJCgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAAALgAECgMJBgAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAABLgAECn8VAAIjAAcJISGdAAAqAgAjAAcJISGdAAAqAgABLgAECggJFAAeAOwbAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECggJGQAXAHMaAA==.Griffmonk:BAABLgAECn8aAAIZAAcJUhnaBgCdAQAZAAcJUhnaBgCdAQAAAA==.Grumpymage:BAABLgAECn8YAAIFAAcJFRgUFwCMAQAFAAcJFRgUFwCMAQAAAA==.',
Ha='Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgADCgkJJgAAAA==.Hara:BAABLgAECn8ZAAIVAAYJOxqOEABSAQAVAAYJOxqOEABSAQAAAA==.Hardord:BAAALgAECgQJCQAAAA==.Haryle:BAAALgADCgkJEwAAAA==.Hayanne:BAABLgAECn8fAAIRAAcJbBpIAwDBAQARAAcJbBpIAwDBAQAAAA==.',
He='Healchucky:BAAALgAECgQJBwAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgQJBQAAAA==.Heina:BAAALgAECgYJBgAAAA==.',
Hi='Hitnrun:BAAALgADCgkJEQAAAA==.',
Ho='Hochunk:BAAALgAECggJCQAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAAALgAECgcJEAAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8UAAIkAAgJQQwDDgBfAQAkAAgJQQwDDgBfAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8YAAIJAAcJZRTOGQBVAQAJAAcJZRTOGQBVAQAAAA==.Honeybun:BAAALgADCgIJAgAAAA==.Honorlife:BAAALgAECgcJEQAAAA==.Hopeudie:BAAALgAECgUJBgABLgAECggJDgABAAAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgQJBQAAAA==.Hughass:BAAALgADCgEJAQAAAA==.',
['Hâ']='Hârley:BAABLgAECn8YAAIVAAYJiyAwCADfAQAVAAYJiyAwCADfAQAAAA==.',
['Hí']='Híram:BAAALgAECgYJEgAAAA==.',
Id='Idyllwild:BAAALgADCgYJCgAAAA==.',
Ih='Ihsan:BAAALgAECgYJDwAAAA==.',
Il='Ilharess:BAABLgAECn8YAAIFAAcJKhS8ewDaAQAFAAcJKhS8ewDaAQAAAA==.',
In='Inko:BAAALgADCgYJCQABLgAECggJHwARAPkfAA==.Inkpot:BAAALgAECgEJAQABLgAECgcJHwAVAPklAA==.Inkwell:BAABLgAECn8fAAIVAAcJ+SX8CAAAAwAVAAcJ+SX8CAAAAwAAAA==.',
Is='Isobell:BAAALgAECgIJAgAAAA==.',
Ja='Jaardrius:BAABLgAECn8UAAMZAAYJ4yLoAwACAgAZAAYJ4yLoAwACAgAQAAMJjgurXgCVAAAAAA==.Jakobo:BAAALgAECgQJBQAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgEJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgADCgcJDQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAYJFQAVAOgjAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Ju='Junebuge:BAAALgADCgYJBgAAAA==.Junknthtrunk:BAAALgADCgcJDwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQASAIYjAA==.',
Ke='Keanew:BAABLgAECn8bAAMLAAgJSBqaBgBNAQALAAgJSBqaBgBNAQAWAAMJwQKcQABdAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8dAAMkAAYJZCCmIAAWAgAkAAYJZCCmIAAWAgAJAAEJIwG3YQEUAAAAAA==.Kenry:BAAALgADCggJHQAAAA==.Keonna:BAAALgADCggJHAAAAA==.Keppra:BAAALgADCgkJGAAAAA==.Kerlin:BAABLgAECn8aAAMVAAgJDQ9dWABJAQAVAAcJ1QtdWABJAQAEAAEJ5AJXiAAnAAAAAA==.Keyaira:BAAALgADCgYJBgAAAA==.Keybash:BAAALgAECgUJEgAAAA==.Keíga:BAAALgAECgIJAgAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAYJFQAVAOgjAA==.Kimmex:BAAALgADCgIJAgAAAA==.Kinoxo:BAACLgAFFH8QAAMTAAUJJBglCgBVAQATAAQJRxclCgBVAQAUAAMJAhDVBgCnAAAuAAQKfxcAAxMACAkDIesaAHQCABMACAnrHesaAHQCABQAAwlwHaQgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8WAAIJAAcJRBTwkABaAQAJAAcJRBTwkABaAQAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgADCgMJAwAAAA==.',
Kr='Krampusnacht:BAAALgAECgYJBgAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgADCgcJDAAAAA==.Kyratinx:BAAALgAECgEJAgAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAECggJDgABAAAAAA==.Larious:BAABLgAECn8SAAIJAAYJFRfTawCmAQAJAAYJFRfTawCmAQAAAA==.',
Le='Ledikens:BAAALgADCgkJEQAAAA==.Legnase:BAABLgAECn8cAAMGAAgJARllEgAhAgAGAAgJBxhlEgAhAgACAAIJWxazFgCAAAAAAA==.Leht:BAAALgAECgYJDwAAAA==.Lessgibbon:BAABLgAECn8XAAITAAcJPh/dGgB1AgATAAcJPh/dGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgADCgcJBwAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lili:BAAALgADCgIJAgAAAA==.Lilnasty:BAAALgAECgYJEwAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Livesey:BAAALgAECgQJBQAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJDQABAAAAAA==.Lokahn:BAABLgAECn8WAAIQAAYJ1hl2IwC6AQAQAAYJ1hl2IwC6AQAAAA==.Longhornpibe:BAABLgAECn8kAAITAAcJNhWPNQDSAQATAAcJNhWPNQDSAQAAAA==.Loudog:BAABLgAECn8aAAMbAAcJzhMaCgDhAAAaAAYJdRL0jwBgAQAbAAYJEQ4aCgDhAAAAAA==.',
Lu='Lupardus:BAAALgADCgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.',
Ly='Lynxie:BAABLgAECn8WAAIlAAgJVwg6KgCIAQAlAAgJVwg6KgCIAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgADCgYJBgAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIDAAcJliBrEACXAgADAAcJliBrEACXAgABLgAFFAYJFgARADweAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAAALgAECgMJAwABLgAECgYJDAABAAAAAA==.Malus:BAAALgAECgcJEwAAAA==.Manders:BAAALgADCgIJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgADCgYJCQAAAA==.Mattydruid:BAAALgAECgEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAABLgAECn8eAAMKAAgJKQ+RCADYAAAHAAYJMBDNbwAYAQAKAAgJmQyRCADYAAAAAA==.Mayge:BAABLgAECn8ZAAIFAAgJbBrWCgD/AQAFAAgJbBrWCgD/AQAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAAALgAECgYJDgAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Mendinna:BAAALgAECgYJEQAAAA==.Mercs:BAAALgADCgQJBQABLgAECgUJCAABAAAAAA==.Methir:BAAALgADCgYJCQAAAA==.',
Mi='Miffed:BAAALgAECggJCwABLgAFFAQJCwAdADEGAA==.Mincksie:BAAALgAECgQJBgAAAA==.Mirage:BAABLgAECn8VAAISAAcJhiMSFwBSAgASAAcJhiMSFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn8eAAIQAAgJDx+oAQBMAgAQAAgJDx+oAQBMAgAAAA==.',
Mo='Montebrew:BAAALgAECgMJAwAAAA==.Mooky:BAABLgAECn8XAAIEAAcJ4w0oDwACAQAEAAcJ4w0oDwACAQAAAA==.Mopeia:BAAALgAECgUJEgABLgAECgYJEwABAAAAAA==.Mord:BAAALgAECgQJCAAAAA==.Mork:BAAALgADCgMJAwABLgAECgYJFgAaAKkiAA==.Mortemore:BAACLgAFFH8KAAIWAAMJgRXuCgAMAQAWAAMJgRXuCgAMAQAuAAQKfxoAAhYACAkUH1wrAFICABYACAkUH1wrAFICAAAA.Motet:BAAALgAECgYJCwAAAA==.',
Mu='Muikkie:BAAALgADCgEJAQAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgcJDwAAAA==.',
My='Mynoghra:BAAALgAECgYJDQAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Naproxen:BAABLgAECn8YAAImAAcJnx1dAgD+AQAmAAcJnx1dAgD+AQAAAA==.Naraku:BAABLgAECn8hAAMPAAgJpx0/HgChAgAPAAgJShw/HgChAgAOAAYJWx7mDQDnAQAAAA==.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Netty:BAAALgAECgIJAgAAAA==.',
Ni='Niklaus:BAABLgAECn8XAAIJAAcJchZTaACvAQAJAAcJchZTaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nirala:BAAALgADCgcJBwAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwABAAAAAA==.',
Ny='Nymeera:BAAALgAECgYJDwAAAA==.Nymphetamine:BAABLgAECn8YAAMCAAYJFxfnLQCNAQACAAYJFxfnLQCNAQAGAAQJ3QTADwCxAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8YAAIlAAgJ8AzpCABkAQAlAAgJ8AzpCABkAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIaAAYJXhjdbgCrAQAaAAYJXhjdbgCrAQAAAA==.',
Od='Odessa:BAAALgADCgQJBAAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn8UAAIKAAgJ/gl1TAAfAQAKAAgJ/gl1TAAfAQAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgUJBwAAAA==.',
Ow='Owful:BAAALgADCgkJDwAAAA==.',
Pa='Pagerduty:BAAALgADCgcJCwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAAALgAECggJDgAAAA==.Papaya:BAACLgAFFH8VAAIVAAYJ6COUAAAKAgAVAAYJ6COUAAAKAgAuAAQKfxwAAxUACQnZIccGAB8DABUACQnZIccGAB8DAAQABgleIoojAOABAAAA.',
Pe='Penelopea:BAABLgAECn8UAAIFAAYJNhD1IABQAQAFAAYJNhD1IABQAQAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJBgAAAA==.',
Ph='Phaith:BAAALgADCgUJCwAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECgYJCwABAAAAAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Po='Porteagarder:BAAALgAECgYJBgABLgAECgYJEwABAAAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAAALgAECgUJBQAAAA==.Preront:BAACLgAFFH8WAAMeAAcJTSAHAACBAgAeAAYJoiMHAACBAgAMAAMJUw0lFQClAAAuAAQKfx4AAx4ACQngJikAAOYDAB4ACQngJikAAOYDAAwAAwktJqA+AFABAAAA.Pringler:BAAALgAECgQJBAABLgAFFAYJFgARADweAA==.Producktive:BAABLgAECn8bAAIdAAgJMBW+EAC6AQAdAAgJMBW+EAC6AQAAAA==.Prometeus:BAAALgADCggJCAAAAA==.Pros:BAABLgAECn8iAAIOAAkJQRRjAgBtAQAOAAkJQRRjAgBtAQAAAA==.Pruulia:BAAALgADCgMJAwABLgAECgYJDwABAAAAAA==.Príestly:BAAALgADCgYJBgAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAAALgAECgYJDAABLgAFFAMJCgAWAIEVAA==.Puffthemagic:BAAALgAECgYJBwAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAAALgAECggJEwAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQABAAAAAA==.Quilae:BAAALgADCgkJGQABLgAECgYJEwABAAAAAA==.Quiny:BAAALgADCgEJAQAAAA==.',
Ra='Raerlynn:BAAALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgADCgcJBwAAAA==.Rassputin:BAABLgAECn8YAAIFAAcJFRasFACcAQAFAAcJFRasFACcAQAAAA==.Ravnmoon:BAAALgADCgcJBwAAAA==.Razzleyi:BAAALgADCgYJCQAAAA==.',
Re='Realmack:BAAALgAECgYJBgABLgAECggJDgABAAAAAA==.Rebuke:BAAALgAECgUJBQAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgQJBgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgADCgcJBwAAAA==.Rendezvous:BAAALgAECgEJAgAAAA==.Requestor:BAAALgAECgUJBQAAAA==.Ret:BAABLgAECn8dAAIJAAgJiBmTLgBpAgAJAAgJiBmTLgBpAgAAAA==.Revaerlous:BAABLgAECn8dAAIaAAkJUxUiLACIAgAaAAkJUxUiLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECgcJEQABAAAAAA==.Rhei:BAABLgAECn8aAAIWAAkJ8Rr8AgB6AgAWAAkJ8Rr8AgB6AgAAAA==.',
Ri='Ribeye:BAACLgAFFH8LAAIdAAQJMQbRAgDPAAAdAAQJMQbRAgDPAAAuAAQKfyEAAh0ACQnvEaYSAKABAB0ACQnvEaYSAKABAAAA.',
Ro='Roereker:BAABLgAECn8YAAIJAAYJbRa5GQBWAQAJAAYJbRa5GQBWAQAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgADCgYJBgAAAA==.Roketraccoon:BAAALgAECgMJBAAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAAALgAECgYJDgAAAA==.Roshamandes:BAAALgAECggJDgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAAALgAECggJEQAAAA==.',
['Ré']='Réstofarian:BAACLgAFFH8LAAIVAAQJIhx1AwBjAQAVAAQJIhx1AwBjAQAuAAQKfyoAAxUACQmzI1wCAHYDABUACQmzI1wCAHYDAAQAAgkoGddmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAAALgAECggJDgAAAA==.Saiki:BAAALgADCgcJDAAAAA==.Saloriavis:BAEBLgAECn8WAAIaAAYJTBZNGwA9AQAaAAYJTBZNGwA9AQAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECgcJEQABAAAAAA==.Sandvichus:BAABLgAECn8UAAIEAAgJSCAQAwALAgAEAAgJSCAQAwALAgAAAA==.Sanitarìum:BAAALgAECgQJBwAAAA==.Sardine:BAAALgAECgcJDQABLgAFFAYJFQAVAOgjAA==.Sasukie:BAAALgAECgEJAwAAAA==.Saxa:BAABLgAECn8ZAAILAAkJ0yA+BwDyAgALAAkJ0yA+BwDyAgAAAA==.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Sefik:BAAALgAECgYJBgAAAA==.Selaana:BAABLgAECn8YAAIMAAYJOh/dBwCEAQAMAAYJOh/dBwCEAQAAAA==.',
Sg='Sgathaich:BAEBLgAECn8aAAIkAAgJ/hVhJQD7AQAkAAgJ/hVhJQD7AQAAAA==.',
Sh='Shaio:BAAALgAECgYJDwAAAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgADCgEJAQAAAA==.Shambulence:BAAALgAECgUJCQAAAA==.Shammlock:BAACLgAFFH8KAAQcAAMJWgx9AQCvAAAPAAMJ0AsuEADyAAAcAAIJUQp9AQCvAAAOAAEJWAB+GwAxAAAuAAQKfyIABBwACAn5IOECAIICABwACAmKHuECAIICAA8ACAmJGyMqAGcCAA4ABQl6EFskADgBAAAA.Shampriest:BAAALgADCgQJBAAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJBQAAAA==.Shobadon:BAAALgADCgcJBwAAAA==.Shole:BAABLgAECn8cAAMNAAgJ0hgEBAA4AgANAAcJrhsEBAA4AgAMAAQJ2R2JTgANAQAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAECggJGgAGAOofAA==.Siggopotomus:BAAALgADCgUJBQABLgAECgcJEQABAAAAAA==.Sigvalden:BAAALgAECgcJCQABLgAECgcJEQABAAAAAA==.Sigvolden:BAAALgAECgYJAQABLgAECgcJEQABAAAAAA==.Silchar:BAAALgADCgEJAQAAAA==.Silicon:BAAALgAECgcJEwAAAA==.Siona:BAABLgAECn8eAAIHAAcJ8AnDEwBdAQAHAAcJ8AnDEwBdAQAAAA==.',
Sk='Skadie:BAABLgAECn8XAAIHAAgJDRNzCgDCAQAHAAgJDRNzCgDCAQAAAA==.Skialin:BAAALgADCgkJCQAAAA==.Skiye:BAAALgADCgcJCAAAAA==.Skyler:BAAALgAECgcJEwAAAA==.',
Sl='Slackness:BAAALgAECgIJAgAAAA==.Slavalous:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAAALgAECgYJDQAAAA==.Snnorri:BAAALgADCgYJDgABLgAECgYJFAAZAOMiAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.',
Sp='Sparrkle:BAABLgAECn8VAAIOAAcJHwtMJgAtAQAOAAcJHwtMJgAtAQAAAA==.Spinjitzu:BAAALgAECgMJBAAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgMJBAAAAA==.',
Sq='Squadw:BAACLgAFFH8KAAILAAMJZBPUBQD5AAALAAMJZBPUBQD5AAAuAAQKfygAAgsACQnzITYCAHMDAAsACQnzITYCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgUJBQABAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgIJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn8fAAIdAAcJ2xc9BABzAQAdAAcJ2xc9BABzAQAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAAALgAECgEJAQAAAA==.Stupidgnome:BAAALgADCgcJCgAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEQABAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAAALgAECggJEQAAAA==.Sunsmite:BAABLgAECn8WAAIJAAcJfRUvFgBvAQAJAAcJfRUvFgBvAQAAAA==.Suramar:BAAALgAECgYJCwAAAA==.',
Sw='Sweetbippy:BAAALgAECgYJDwAAAA==.Swifthealss:BAAALgAECgcJDgAAAA==.Swirls:BAAALgADCgcJCQAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECgcJEQABAAAAAA==.Sylunae:BAAALgADCgkJCQABLgAECgYJEwABAAAAAA==.Syluné:BAAALgAECgYJEwAAAA==.Syläs:BAAALgAECgUJDQAAAA==.Syndrassil:BAAALgAECgYJDAAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
Ta='Tacodog:BAAALgAECgQJCAABLgAECggJIwAJAIgmAA==.Tacomonk:BAAALgAECgMJBAAAAA==.Taelight:BAAALgADCggJCAAAAA==.Taelyx:BAABLgAECn8aAAMNAAgJ/xaXCgCUAQANAAgJ/xaXCgCUAQAMAAIJ3gn8fQBOAAAAAA==.Taicheeze:BAAALgAECgcJEAAAAA==.Tambot:BAAALgAECgQJCQAAAA==.Tariced:BAAALgADCggJGAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgADCgMJAwABLgAECgYJDwABAAAAAA==.Tazmina:BAABLgAECn8fAAILAAgJ/R7xBwDkAgALAAgJ/R7xBwDkAgAAAA==.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgEJAQABLgAECgcJFwAMAJMYAA==.Tessa:BAABLgAECn8XAAIMAAcJkxidBgChAQAMAAcJkxidBgChAQAAAA==.Texasfight:BAAALgADCgIJAgABLgAECggJJAATADYVAA==.Teyo:BAAALgAECgQJDQAAAA==.',
Th='Thedoctorwho:BAAALgAECgQJBgAAAA==.Theholytaz:BAABLgAECn8XAAIJAAgJDBZnQQAhAgAJAAgJDBZnQQAhAgAAAA==.Thörn:BAAALgAECgQJCgABLgAECgUJFAAVADQWAA==.',
Ti='Time:BAAALgADCgcJDQAAAA==.',
To='Tomcatt:BAABLgAECn8fAAIHAAcJtxVnDACoAQAHAAcJtxVnDACoAQAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.',
Tr='Trailis:BAAALgADCgcJDgAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Treè:BAAALgAECgMJBAAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8VAAIRAAcJHQTFLQDUAAARAAcJHQTFLQDUAAAAAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAAALgAECgcJEQAAAA==.Twos:BAAALgADCggJEgAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn8WAAIeAAcJlhy6AQD7AQAeAAcJlhy6AQD7AQAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAAALgAECgUJDgAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unstable:BAAALgAECgQJBQAAAA==.',
Up='Upchucky:BAAALgADCgYJBwAAAA==.',
Va='Vaedeath:BAABLgAECn8YAAIbAAYJDSNGAwDCAQAbAAYJDSNGAwDCAQAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgADCgcJEgAAAA==.Valaryon:BAAALgADCgkJHgAAAA==.Valkorin:BAAALgAECgMJAwAAAA==.Valoryan:BAABLgAECn8fAAIVAAcJyQ+4EgA3AQAVAAcJyQ+4EgA3AQAAAA==.Valyteilssra:BAAALgADCggJEgAAAA==.Varindra:BAAALgAECgEJAQABLgAECggJGgAGAOofAA==.',
Ve='Vegà:BAABLgAECn8VAAIDAAcJFQkTDAAvAQADAAcJFQkTDAAvAQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQABAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQABAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgIJAgAAAA==.',
Vo='Voidhax:BAAALgADCgUJBQAAAA==.Voidi:BAABLgAECn8XAAQSAAcJVyOuFQBiAgASAAcJtCKuFQBiAgAhAAQJESEADQBPAQAnAAEJtAOiDwAoAAAAAA==.Voidyo:BAAALgAFFAIJAwAAAA==.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAAALgAECgYJDwAAAA==.Vortice:BAABLgAECn8dAAQMAAYJ/RFfPwBMAQAMAAYJ/RFfPwBMAQANAAYJpQ9DUQBAAQAeAAIJQAfXKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgADCgUJAwAAAA==.Ware:BAAALgADCgYJBgAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECgcJFgAiAAcdAA==.',
Wh='Wheatstraw:BAAALgADCgUJBwAAAA==.Whiskeyjak:BAAALgAECgYJCQAAAA==.',
Wi='Willowest:BAAALgAECgYJDwAAAA==.',
Wr='Wrathstorm:BAABLgAECn8WAAIeAAgJPBdjDQDoAQAeAAgJPBdjDQDoAQAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8JAAIaAAQJjxQkGABEAQAaAAQJjxQkGABEAQAuAAQKfygAAhoACQmxIrsQABgDABoACQmxIrsQABgDAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgYJGAAVAEQZAA==.Wurmy:BAABLgAECn8YAAMVAAYJRBmZDQB7AQAVAAYJRBmZDQB7AQAEAAIJRhFrbABuAAAAAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAAALgAECgYJEwAAAA==.Xanier:BAAALgADCggJHAAAAA==.',
Xe='Xelagos:BAABLgAECn8XAAQIAAcJaxFiIwBeAQAIAAcJaxFiIwBeAQAfAAMJCBy3JgDsAAAgAAIJZxegUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Ya='Yanella:BAAALgAECggJDgAAAA==.',
Yi='Yispally:BAAALgAECgMJBAAAAA==.Yisshaman:BAABLgAECn8eAAIMAAkJXhvUDADQAgAMAAkJXhvUDADQAgAAAA==.',
Yo='Yogibearz:BAAALgAECgQJBwABLgAECgUJCAABAAAAAA==.Yogimonk:BAAALgAECgUJCAAAAA==.',
Za='Zandarbribbs:BAAALgAECgYJDwAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgADCgkJFAAAAA==.',
Ze='Zenmetsu:BAAALgAECgIJAgAAAA==.Zennya:BAAALgAECgcJEQAAAA==.Zeon:BAAALgAECgYJCwAAAA==.',
Zi='Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn8YAAIDAAYJehtbCQBcAQADAAYJehtbCQBcAQAAAA==.',
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

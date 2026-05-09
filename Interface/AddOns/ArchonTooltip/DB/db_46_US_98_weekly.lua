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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Fury','Mage-Frost','Mage-Arcane','Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Shaman-Elemental','Warlock-Demonology','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Evoker-Preservation','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJDxUNGgBnAQABAAcJDxUNGgBnAQAAAA==.',
Ac='Accalon:BAABLgAECn8cAAMCAAgJFhjYBgDyAQACAAgJFhjYBgDyAQADAAEJ+wdPqQA1AAABLgAECgYJFwAEAIscAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8PAAMEAAUJAxOoLABQAQAEAAUJAxOoLABQAQAFAAEJbxN/AQBVAAAuAAQKfyUAAwUACAllH/8BAJACAAUACAmWGv8BAJACAAQACAkDHENQAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Aimer:BAAALgAECgEJAQAAAA==.Airi:BAAALgADCgYJCAAAAA==.',
Ak='Akrama:BAABLgAECn8kAAIGAAgJQx3jDwAgAgAGAAgJQx3jDwAgAgAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgIJAgAAAA==.Alectrona:BAAALgAECgMJBQAAAA==.Aletriss:BAAALgAECgQJBgAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgAECgQJBQAAAA==.Amnorpse:BAABLgAECn8YAAIDAAYJCxwRGQCeAQADAAYJCxwRGQCeAQAAAA==.',
An='Anabana:BAAALgAECgQJCwAAAA==.Angler:BAABLgAECn8WAAIHAAgJEBkLCgBMAgAHAAgJEBkLCgBMAgAAAA==.Anruu:BAAALgAECgUJBQAAAA==.',
Ap='Appollis:BAAALgADCgQJBAAAAA==.Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgAECgIJAgAAAA==.Arkthurus:BAAALgAECgYJDAAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgUJCAAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashijin:BAACLgAFFH8PAAIIAAQJTxoPEQBjAQAIAAQJTxoPEQBjAQAuAAQKfycAAggACQlVIQ0mAI4CAAgACQlVIQ0mAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.Astei:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgAECgQJBAABLgAECgUJEwAJAAAAAA==.Atroce:BAAALgAECgEJAwAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn8tAAIGAAkJQhiUCACJAgAGAAkJQhiUCACJAgAAAA==.Auxilium:BAABLgAECn8UAAIIAAcJxBjPSAAIAgAIAAcJxBjPSAAIAgAAAA==.',
Aw='Awnen:BAAALgAECgUJDAAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balebrew:BAAALgADCgQJBAABLgAECgkJMQAKAAImAA==.Balethar:BAAALgAECgYJEwABLgAECgkJMQAKAAImAA==.Ballador:BAAALgAECgQJBgAAAA==.Balluh:BAABLgAECn8gAAILAAgJoxYODADjAQALAAgJoxYODADjAQAAAA==.',
Be='Beartest:BAAALgAECgMJBAABLgAFFAMJBgAMAEcNAA==.Beezen:BAACLgAFFH8SAAIMAAUJFxl2AwBoAQAMAAUJFxl2AwBoAQAuAAQKfyUAAgwACAm/IUYFADADAAwACAm/IUYFADADAAAA.Belara:BAAALgADCgYJBwAAAA==.Bellevo:BAAALgAECgQJBAABLgAECggJJwAEAMIhAA==.Bellmage:BAABLgAECn8nAAMEAAgJwiHNDgCmAgAEAAgJwiHNDgCmAgAFAAEJxAlqHwAxAAAAAA==.Belttoash:BAABLgAECn8iAAIIAAcJNxWzYADCAQAIAAcJNxWzYADCAQAAAA==.Beneficiary:BAAALgAECgQJBQAAAA==.Bercey:BAAALgAECggJEAAAAA==.Beybladetest:BAACLgAFFH8GAAMMAAMJRw3sEgDHAAAMAAMJxQjsEgDHAAANAAIJkw+HGwCQAAAuAAQKfxwAAw0ACAnmGgIWAFoCAA0ACAnmGgIWAFoCAAcABAldCgM8AJYAAAAA.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJDQABLgAECgkJGgAOAM0aAA==.Bigscott:BAAALgAECgMJAwABLgAFFAQJEQAPAE0WAA==.Bilmuri:BAAALgADCgEJAQAAAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgAECgMJAwAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAFFAEJAQAAAA==.Blizzlock:BAABLgAECn8kAAIQAAgJeBArMwCYAQAQAAgJeBArMwCYAQAAAA==.Blood:BAAALgAECgIJBAAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn8yAAIRAAkJ5CFbBQADAwARAAkJ5CFbBQADAwAAAA==.Boogiepop:BAAALgAECgcJDQAAAA==.Bootylika:BAABLgAECn8YAAIDAAgJ1BOfLgD3AQADAAgJ1BOfLgD3AQAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgADCgkJEgAAAA==.Boutdatbass:BAAALgAECgQJBgAAAA==.',
Br='Braxxar:BAAALgAECgUJCQAAAA==.Brendelf:BAAALgADCgMJAwAAAA==.Brett:BAAALgAECgEJAgAAAA==.Briellia:BAAALgAECgYJCQAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bryagh:BAABLgAECn8YAAMSAAcJBRfzFQCUAQASAAcJBRfzFQCUAQATAAIJnwwaNwBfAAAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECgEJAQAAAA==.Bulge:BAAALgADCgUJBQABLgAECggJGwAUAN4bAA==.Bullycow:BAABLgAECn8XAAIVAAYJJgVtEwDMAAAVAAYJJgVtEwDMAAAAAA==.Bushybrowsy:BAABLgAECn8hAAQWAAgJZwvUCQCjAQAWAAgJjwrUCQCjAQAQAAcJSQhvWQAhAQAXAAMJRwJvXQBWAAAAAA==.Buttercupz:BAABLgAECn8WAAIYAAgJoQucMgBRAQAYAAgJoQucMgBRAQAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8gAAMZAAgJdxdKFQAJAgAZAAgJdxdKFQAJAgAPAAQJmgNiagCaAAAAAA==.',
Ca='Cacho:BAAALgAECggJCQAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgYJBwAAAA==.Carpulations:BAABLgAECn8XAAIQAAYJEBilhABQAQAQAAYJEBilhABQAQAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Cerofewol:BAAALgADCgMJAwABLgAECgUJBwAJAAAAAA==.Cerridwen:BAAALgAECgYJEQAAAA==.',
Ch='Chantini:BAAALgAECgUJBQAAAA==.Chartreuze:BAAALgAECgIJAgAAAA==.Chazmonk:BAAALgAECgEJAQABLgAFFAMJBQAZACYOAA==.Chazzie:BAABLgAFFH8FAAIZAAMJJg5YJQC/AAAZAAMJJg5YJQC/AAAAAA==.Cheonsul:BAAALgADCgQJBgAAAA==.Chia:BAACLgAFFH8TAAMaAAUJVBLNMAA+AQAaAAQJVBLNMAA+AQAbAAEJAADJMwAAAAAuAAQKfyMAAhoACAlVH8ASAGYCABoACAlVH8ASAGYCAAAA.Chikn:BAABLgAECn8XAAIHAAgJ8xRUGAD7AQAHAAgJ8xRUGAD7AQAAAA==.Chirichiri:BAAALgADCgIJBAAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAUJDgADAEMVAA==.Chomboslice:BAABLgAECn8iAAMGAAkJXBz/CwBUAgAGAAkJXBz/CwBUAgAIAAMJOQxwuACEAAAAAA==.',
Cl='Clary:BAAALgADCgEJAQABLgAECgYJBwAJAAAAAA==.Classy:BAAALgAECgUJBgAAAA==.',
Cm='Cmil:BAACLgAFFH8RAAMGAAUJQxH/CwBlAQAGAAUJQxH/CwBlAQAIAAEJkQGBZQAvAAAuAAQKfx8AAwYACAnwC8g4AJcBAAYACAnwC8g4AJcBAAgAAQnODcNCATMAAAAA.',
Co='Coffeebrew:BAAALgAECgUJBwABLgAECgcJDQAJAAAAAA==.Coffeecrem:BAAALgAECgcJDQAAAA==.Coffie:BAAALgADCgUJBQABLgAECgcJDQAJAAAAAA==.Coldnoodles:BAAALgADCgMJAgABLgAECgkJLAAMAKoeAA==.Combat:BAACLgAFFH8RAAIDAAUJARg9DgA6AQADAAUJARg9DgA6AQAuAAQKfx4AAgMACAktHkoVAKMCAAMACAktHkoVAKMCAAAA.Cornish:BAECLgAFFH8QAAIHAAYJzSDUAQBcAgAHAAYJzSDUAQBcAgAuAAQKfyoAAwcACQn3I60AALMDAAcACQn3I60AALMDAAwABQlbFbsiABEBAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAYJEAAHAM0gAA==.Cosmo:BAAALgADCgcJCQABLgAECgkJFAAMAC8YAA==.',
Cr='Crackjaw:BAAALgAECgMJBQAAAA==.Crockodk:BAAALgAECgEJAQAAAA==.',
Cu='Curserodlock:BAAALgAECgcJCAAAAA==.',
Cy='Cyanide:BAAALgAECgYJBwAAAA==.',
Da='Dabbinshamin:BAAALgAECggJCgAAAA==.Dadanbing:BAAALgAECgYJBgABLgAECgkJDAAJAAAAAA==.Daddyomg:BAAALgAECgYJCAABLgAFFAcJHQAPAEUXAA==.Dads:BAACLgAFFH8dAAMPAAcJRRcYBQCkAQAPAAYJ7hcYBQCkAQAZAAQJNAh6IwDHAAAuAAQKfxsAAw8ACQkWJSAQAKgCAA8ABwm6JCAQAKgCABkACQloF70iAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAFFAMJBgAMAEcNAA==.Dakeyras:BAABLgAECn8bAAMcAAgJDRQ1HgBUAQAcAAgJDRQ1HgBUAQADAAMJHwT0aAA1AAAAAA==.Darcevoker:BAACLgAFFH8LAAIdAAUJ9wdSDAAiAQAdAAUJ9wdSDAAiAQAuAAQKfyQAAh0ACAmrGOUNAFkCAB0ACAmrGOUNAFkCAAAA.Darcmonk:BAAALgAFFAMJBAABLgAFFAUJCwAdAPcHAA==.Darcpaladin:BAAALgAECgQJBQABLgAFFAUJCwAdAPcHAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAUJCwAdAPcHAA==.Darkrune:BAAALgAECgYJEwAAAA==.Darkschneide:BAAALgAECgQJBQAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.Davris:BAAALgAECgQJBQAAAA==.',
Db='Dbmagic:BAAALgAECgUJBwAAAA==.',
De='Dealsun:BAABLgAECn8bAAMQAAgJdBOTRAD+AQAQAAgJdBOTRAD+AQAXAAUJ2QdHOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJAQAAAA==.Demodorn:BAECLgAFFH8SAAIeAAUJSAVrAgCvAAAeAAUJSAVrAgCvAAAuAAQKfycAAh4ACAmfFE4IAPgBAB4ACAmfFE4IAPgBAAAA.Demondudez:BAAALgAECgUJCwAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demyst:BAACLgAFFH8NAAMPAAUJlBCeEAArAQAPAAUJlBCeEAArAQAZAAIJPQRQJQBBAAAuAAQKfyEAAw8ACQlVHycSAJICAA8ACQlVHycSAJICABkAAgmkDVZ6ADkAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECgUJCQAAAA==.Dezeraz:BAECLgAFFH8MAAIdAAQJbBwTBwB+AQAdAAQJbBwTBwB+AQAuAAQKfyMAAh0ACAkDJv4BAFsDAB0ACAkDJv4BAFsDAAEuAAUUBgkQAAcAzSAA.',
Dh='Dhecaye:BAAALgADCgkJDwABLgAFFAIJAwAJAAAAAA==.',
Di='Dieuscum:BAAALgAECgUJBQAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAUJEQADAAEYAA==.Dislogic:BAABLgAECn8kAAMQAAkJZiL0AwAPAwAQAAgJZiL0AwAPAwAXAAQJTSCfGwBwAQAAAA==.',
Dl='Dlorpglorp:BAAALgAECgIJAgABLgAECgcJHwAEAEMgAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgYJCQAAAA==.Donmega:BAAALgADCgYJCQAAAA==.Doraleous:BAABLgAECn8XAAIGAAcJAx0/EgAFAgAGAAcJAx0/EgAFAgAAAA==.Dotzmybitzup:BAACLgAFFH8NAAMQAAQJnB5SKgAbAQAQAAQJnB5SKgAbAQAXAAEJNA2MEwBQAAAuAAQKfzEABBAACAmFJQAOAHsCABAACAmFJQAOAHsCABYAAglqEzEdAIgAABcAAQlXDmZjAEgAAAEuAAUUBQkLABIAehQA.Dougalleone:BAACLgAFFH8PAAIOAAUJoSKeBQCAAQAOAAUJoSKeBQCAAQAuAAQKfyUAAw4ACQmJIoMHABgDAA4ACQmJIoMHABgDAB8AAQmtEfgdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Dreadknott:BAACLgAFFH8HAAIaAAIJwRUIeQCaAAAaAAIJwRUIeQCaAAAuAAQKfykAAhoACQleHXENAJgCABoACQleHXENAJgCAAAA.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAISAAUJryAULgBRAQASAAUJryAULgBRAQAAAA==.Dreko:BAAALgADCgQJBQAAAA==.Drezzakmage:BAACLgAFFH8GAAIEAAIJYASzbACSAAAEAAIJYASzbACSAAAuAAQKfyEAAgQACQldFlpgABoCAAQACQldFlpgABoCAAAA.Drezzakzdh:BAAALgADCgYJBgABLgAFFAIJBgAEAGAEAA==.Druidiac:BAAALgADCgYJEwABLgAECggJJAAYAAAaAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAECgcJCAABLgAECggJFQAeAEIMAA==.Elaidine:BAABLgAECn8VAAMeAAgJQgyxCwAPAQAeAAgJQgyxCwAPAQAgAAEJAADI2gAAAAAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgIJAwAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enferno:BAAALgAECgYJDgAAAA==.Enfernum:BAAALgADCgEJAQAAAA==.Enolad:BAAALgADCgcJBwABLgAECgcJDAAJAAAAAA==.',
Er='Eradius:BAAALgADCgIJAgAAAA==.Errai:BAABLgAECn8rAAIQAAkJBB/hBgDWAgAQAAkJBB/hBgDWAgAAAA==.',
Eu='Eureka:BAABLgAECn8XAAIBAAkJsxcVCABRAgABAAkJsxcVCABRAgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJEQAAAA==.Evion:BAABLgAECn8YAAIhAAgJxxuALwDzAQAhAAgJxxuALwDzAQAAAA==.',
Ey='Eyedoll:BAAALgADCgYJBgAAAA==.Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Faemalis:BAAALgAECgEJAQAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgQJCAAAAA==.Feelthepower:BAAALgAECgYJEAAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQABLgAECgkJLwAbAMkjAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Frenzi:BAAALgADCgEJAQAAAA==.Friendulum:BAAALgAECgcJBwAAAA==.Frostey:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIiAAgJMx6oBgCLAgAiAAgJMx6oBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgMJBAAAAA==.Gangactivity:BAAALgAECgQJCwABLgAFFAMJBQAMAIUaAA==.Garm:BAAALgAECgEJAQAAAA==.Garrt:BAAALgAECgYJDAAAAA==.Gartalvanise:BAAALgAECggJDAAAAA==.Gavinrad:BAAALgAECgUJCAAAAA==.',
Ge='Gep:BAAALgAECgcJDwAAAA==.',
Gl='Glaalinix:BAAALgADCgkJGAAAAA==.Glaciiel:BAAALgAECgMJAwAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgQJBQAAAA==.Goobman:BAAALgADCgQJBQABLgAFFAMJBgARABgaAA==.Goodman:BAABLgAECn8kAAIIAAgJ4B2SEgBmAgAIAAgJ4B2SEgBmAgAAAA==.Goomei:BAACLgAFFH8KAAIMAAQJDxw8BQBqAQAMAAQJDxw8BQBqAQAuAAQKfyoAAgwACQngIfwBAAIDAAwACQngIfwBAAIDAAEuAAUUBwkQACAAhxgA.Goomi:BAACLgAFFH8QAAIgAAcJhxjPBADxAQAgAAcJhxjPBADxAQAuAAQKfyEAAiAACQk+IxADAJ4DACAACQk+IxADAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgQJCgAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAAALgAECggJDwAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8XAAIEAAcJExIRXQBZAQAEAAcJExIRXQBZAQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJBAAAAA==.Greygavel:BAAALgAECgYJDQAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8UAAIVAAUJciRSAQCFAQAVAAUJciRSAQCFAQAuAAQKfyUAAhUACAkJJvsAAH4DABUACAkJJvsAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJEwAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIIAAcJLyTbMABfAgAIAAcJLyTbMABfAgAAAA==.Gundral:BAAALgADCgEJAQAAAA==.Gunnysack:BAAALgADCggJDgAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgAJAAAAAA==.',
Gy='Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn8lAAIRAAkJxSBuAwA7AwARAAkJxSBuAwA7AwAAAA==.Harie:BAABLgAECn8ZAAIEAAYJog3wcQAtAQAEAAYJog3wcQAtAQAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgIJAgAAAA==.',
He='Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAACLgAFFH8FAAMaAAMJbCAeQAARAQAaAAMJ2xoeQAARAQAjAAIJeRjGBQCwAAAuAAQKfxoABBoACQlIJgUFAA8DABoACAlVJgUFAA8DACMABAl8Je0DAMABABsABgkEETomAA0BAAAA.Heinyheinyho:BAABLgAECn8pAAIGAAgJPiRTBQDUAgAGAAgJPiRTBQDUAgABLgAFFAMJBQAaAGwgAA==.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJAwAAAA==.',
Ho='Hoid:BAAALgAECgEJAgAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQAJAAAAAA==.Hoofmetoo:BAABLgAECn8iAAIaAAgJ3xyzFQBNAgAaAAgJ3xyzFQBNAgAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAAALgAECgYJEQAAAA==.',
['Hô']='Hôlyblight:BAAALgADCgEJAQABLgAFFAQJCgAPAKsLAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMEAAgJihbaVAA5AgAEAAgJihbaVAA5AgAFAAQJ7gLlEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8qAAIEAAgJmxvMUgA/AgAEAAgJmxvMUgA/AgAAAA==.',
Ig='Igris:BAAALgAECgQJBgAAAA==.',
Ih='Ihavewater:BAAALgADCgkJCQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAUJDgADAEMVAA==.Illidori:BAABLgAECn8VAAIgAAcJ2ge+VwD1AAAgAAcJ2ge+VwD1AAAAAA==.Illidrag:BAAALgAECgkJEwAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAFFAUJCwAMAC8QAA==.Imladris:BAAALgAECgYJDgAAAA==.Immòrtlzed:BAACLgAFFH8UAAMdAAUJMCL+BQDGAQAdAAUJMCL+BQDGAQATAAEJfQcuCABMAAAuAAQKfyAAAh0ACAliIHIJAJ8CAB0ACAliIHIJAJ8CAAAA.',
In='Invective:BAAALgADCgkJIAAAAA==.',
Is='Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIhAAcJUgxlSQAxAQAhAAcJUgxlSQAxAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgUJDAAJAAAAAA==.Jadelin:BAAALgAECgIJAgABLgAECgYJFAAEAJ0IAA==.Jaxek:BAABLgAECn8sAAIiAAkJFiLCAAASAwAiAAkJFiLCAAASAwAAAA==.Jaxs:BAACLgAFFH8PAAIZAAYJSBrbAgD+AQAZAAYJSBrbAgD+AQAuAAQKfyAAAhkACAlAG5oVAGgCABkACAlAG5oVAGgCAAAA.Jaylen:BAAALgAECgQJCAAAAA==.Jaymo:BAAALgAECgUJCAAAAA==.',
Je='Jebke:BAAALgAECgMJBAABLgAECgYJBwAJAAAAAA==.Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJCgAAAA==.Jenifur:BAABLgAECn8VAAIRAAYJqgv6SgDnAAARAAYJqgv6SgDnAAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8IAAINAAMJkQ3kIgDQAAANAAMJkQ3kIgDQAAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgAECggJGQANABIdAA==.',
Jm='Jml:BAACLgAFFH8SAAIgAAUJ0SI3CQCWAQAgAAUJ0SI3CQCWAQAuAAQKfxsAAiAACQnRIQAFAHYDACAACQnRIQAFAHYDAAAA.',
Jo='Jopha:BAACLgAFFH8TAAIDAAUJTiG9BwBkAQADAAUJTiG9BwBkAQAuAAQKfyUAAwMACAlKJQIGAEcDAAMACAkpJQIGAEcDAAIABwkQH/EEAJQCAAAA.Jophr:BAAALgAECgQJAQABLgAFFAUJEwADAE4hAA==.',
Jp='Jpbruiser:BAABLgAECn8zAAIIAAgJYSNACADOAgAIAAgJYSNACADOAgAAAA==.',
Ju='Judged:BAAALgAECgUJDgAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpn:BAAALgAECgkJCQABLgAFFAUJDgAbANgZAA==.Jumpndeath:BAACLgAFFH8OAAIbAAUJ2Bk9CQA6AQAbAAUJ2Bk9CQA6AQAuAAQKfyAAAxsACQn2IBsKANoBABsABglwIhsKANoBABoABglYHIl+AIYBAAAA.Jumpnpunch:BAABLgAECn8lAAQNAAgJahwCGgA0AgANAAcJQBwCGgA0AgAMAAgJ6Q+5FACIAQAHAAcJoQwIOAALAQABLgAFFAUJDgAbANgZAA==.Junknugget:BAAALgADCgYJBgAAAA==.Justgetme:BAABLgAECn8xAAMKAAkJAiYiAAB3AwAKAAkJAiYiAAB3AwAIAAIJAA6lGwFjAAAAAA==.',
Jw='Jwad:BAABLgAECn8bAAMQAAYJ8BbrQQBjAQAQAAUJ8BbrQQBjAQAXAAIJ8Qz+UgB1AAAAAA==.',
Ka='Kaan:BAAALgAECgEJAwAAAA==.Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJCQABLgAFFAQJCwAaACgdAA==.Kagger:BAACLgAFFH8JAAIIAAMJrRj7JwAMAQAIAAMJrRj7JwAMAQAuAAQKfzQAAggACQn2Iu4EAH0DAAgACQn2Iu4EAH0DAAAA.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCwABLgAECgcJBwAJAAAAAA==.Kake:BAAALgAECgQJBAABLgAECgcJCgAJAAAAAA==.Kalloh:BAABLgAECn8hAAMQAAYJGxNPWAAkAQAQAAYJGxNPWAAkAQAXAAIJ4RVhGACEAAAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Kardoroth:BAACLgAFFH8LAAIaAAQJLyUJCgC4AQAaAAQJLyUJCgC4AQAuAAQKfzMAAhoACQmJJrIAAIIDABoACQmJJrIAAIIDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karnaege:BAAALgADCgMJAwAAAA==.Karîba:BAACLgAFFH8VAAQaAAUJQhzSIgBaAQAaAAQJxxvSIgBaAQAbAAMJPxO7DgB+AAAjAAEJMgvZCQBKAAAuAAQKfycAAxoACAn8HkwfAMUCABoACAn8HkwfAMUCABsAAQkrCTFNABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgUJCQAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Ke='Keerrilee:BAABLgAECn8WAAIMAAgJ9hyjIQDJAQAMAAgJ9hyjIQDJAQAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAAALgAECgQJEAAAAA==.Kelsaz:BAACLgAFFH8UAAMLAAUJeBmIBgBfAQALAAUJNhiIBgBfAQAhAAMJchV6CwAGAQAuAAQKfx8ABCEACAkqIzISAKYCACEABwlIIzISAKYCACQABglBGO9GADgBAAsABAnvFg8lANAAAAAA.Kelsi:BAABLgAECn8UAAIMAAkJLxj5DwC9AQAMAAkJLxj5DwC9AQAAAA==.Kenný:BAAALgADCgMJBAAAAA==.Kerrìgàn:BAACLgAFFH8VAAIeAAYJeBafAACJAQAeAAYJeBafAACJAQAuAAQKfycAAh4ACQlMIWkCANYCAB4ACQlMIWkCANYCAAAA.Kestral:BAACLgAFFH8JAAMSAAUJWQFfJADUAAASAAUJWQFfJADUAAAdAAMJ6gjeFAC9AAAuAAQKfyYAAx0ACAkMFCMUAAMCAB0ACAkMFCMUAAMCABIAAwn7CpRAAJgAAAAA.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgAECgEJAQAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAUJDgADAEMVAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.',
Ko='Kookiie:BAACLgAFFH8UAAMlAAUJnSI5AgCFAQAlAAUJnSI5AgCFAQAgAAIJWQ12KwCYAAAuAAQKfyUAAyUACAkTIb4JAMYCACUABwnbJb4JAMYCACAACAkuHLkkAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosian:BAABLgAECn8UAAIKAAcJjwhlJwDOAAAKAAcJjwhlJwDOAAAAAA==.Kosigan:BAAALgAECgIJAgABLgAFFAQJBgASAOgRAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Krepuscular:BAAALgAECgMJAwAAAA==.Kromdor:BAABLgAECn8YAAIXAAgJSxoKBgBxAgAXAAgJSxoKBgBxAgAAAA==.Krosis:BAABLgAECn8WAAIaAAkJSBvsOABTAgAaAAkJSBvsOABTAgAAAA==.Krumee:BAAALgADCgYJBgAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAwABLgAFFAQJEQAPAE0WAA==.Kuromi:BAAALgAECgQJBAAAAA==.',
Ky='Kynei:BAABLgAECn8WAAIgAAgJsR6LDwBKAgAgAAgJsR6LDwBKAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgcJBwAJAAAAAA==.Larra:BAACLgAFFH8OAAMmAAUJXxDcCwCLAQAmAAUJMA7cCwCLAQAnAAMJmgv8CADYAAAuAAQKfyEABCcACQnqGioPAG8CACcACAlrHSoPAG8CABgABgnvGy8tAHUBACYABgkJDpkaAFwBAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levitas:BAABLgAECn8kAAIcAAgJvBM3CwC2AQAcAAgJvBM3CwC2AQAAAA==.Lewieballz:BAAALgADCgMJAwABLgAECggJHgAJAAAAAA==.',
Li='Liberater:BAAALgAECgEJAQAAAA==.Liljit:BAAALgAECgcJDgAAAA==.Lithel:BAAALgAECgEJAQAAAA==.',
Lo='Loaded:BAAALgAECgEJAQAAAA==.Lockxeno:BAABLgAECn8YAAMQAAgJ8hibGQAXAgAQAAcJ8hibGQAXAgAXAAEJAAAdNwAAAAAAAA==.Lodidodii:BAAALgAECgcJCAAAAA==.Logics:BAABLgAECn8pAAIYAAkJ+SDgAQAIAwAYAAkJ+SDgAQAIAwAAAA==.Lon:BAABLgAECn8YAAIMAAgJxRJeLAB9AQAMAAgJxRJeLAB9AQAAAA==.Longsham:BAAALgADCgEJAQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJGQASAJEXAA==.Lostmylimbs:BAACLgAFFH8GAAIbAAQJHwnZCgDQAAAbAAQJHwnZCgDQAAAuAAQKfyMAAhsACAmFFz4QAG4BABsACAmFFz4QAG4BAAEuAAUUBgkVAB4AeBYA.Lostmyvigor:BAAALgAECgMJBwAAAA==.Lostvoker:BAABLgAECn8ZAAMSAAgJkRe0FQAtAgASAAgJkRe0FQAtAgATAAUJehDlIgATAQAAAA==.Loueballz:BAAALgAECggJHgAAAQ==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8rAAIMAAgJ9hhRCwAFAgAMAAgJ9hhRCwAFAgAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn8oAAIWAAgJAhqbBAAwAgAWAAgJAhqbBAAwAgAAAA==.Lumafist:BAACLgAFFH8FAAIMAAMJhRqZDAAPAQAMAAMJhRqZDAAPAQAuAAQKfyoAAgwACQm3IRQDANQCAAwACQm3IRQDANQCAAAA.',
['Lè']='Lènneth:BAABLgAECn8oAAMnAAkJRBwrBgCZAgAnAAkJRBwrBgCZAgAYAAIJzBDdPgB7AAAAAA==.',
['Lí']='Líghtning:BAAALgAECggJDgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQAJAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Mahiru:BAAALgADCgMJAwAAAA==.Makkaflocka:BAAALgAECgUJBQABLgAECgcJHgAgACQgAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAABLgAECn8XAAMKAAcJnQ5cEQAoAQAKAAcJnQ5cEQAoAQAIAAEJzgXnEwEtAAAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8NAAIPAAQJgRVEDwAzAQAPAAQJgRVEDwAzAQAuAAQKfx4AAg8ACQkqHrcUAHgCAA8ACQkqHrcUAHgCAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCgAAAA==.Mazkova:BAAALgAECggJDgAAAA==.Mazur:BAABLgAECn8hAAIIAAgJcCEKDQCYAgAIAAgJcCEKDQCYAgAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAAALgAECgUJEwAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAECLgAFFH8IAAIoAAQJNBnxAgA4AQAoAAQJNBnxAgA4AQAuAAQKfykAAygACQnFJHcAAD0DACgACQnFJHcAAD0DACIAAglWEbocAHYAAAAA.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8WAAMVAAYJ0x7XDAD1AQAVAAYJph3XDAD1AQAPAAUJWx6MPABaAQAAAA==.Minislayer:BAAALgAECgcJEQAAAA==.Minyprayers:BAACLgAFFH8VAAMYAAYJZBTDBwBoAQAYAAUJ2BjDBwBoAQAnAAEJvAr8GwBTAAAuAAQKfyEAAhgACQmlJEUKAN4CABgACQmlJEUKAN4CAAAA.Minywon:BAAALgADCgcJCgABLgAFFAYJFQAYAGQUAA==.Misosalty:BAABLgAECn8sAAMMAAkJqh6CBACgAgAMAAkJqh6CBACgAgANAAUJ2BdkLADtAAAAAA==.Misowet:BAAALgADCgYJCQABLgAECgkJLAAMAKoeAA==.',
Ml='Mlorpglorp:BAABLgAECn8fAAIEAAcJQyB0PQCCAgAEAAcJQyB0PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn8rAAMMAAkJoBsdBgBzAgAMAAkJoBsdBgBzAgANAAUJABF5MADZAAAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8pAAINAAgJmyPMCQAoAgANAAgJmyPMCQAoAgAAAA==.Monkma:BAAALgAECgIJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAQJDQAPAIEVAA==.Morguth:BAACLgAFFH8NAAMhAAUJaxI4FgBFAQAhAAUJaxI4FgBFAQAkAAIJUQCiIwBdAAAuAAQKfx0ABCEACQl6HSUUAJUCACEACQl6HSUUAJUCACQABAkeBK5nAKAAAAsAAglcD+I8AD4AAAAA.Moriaug:BAAALgAECgUJBgABLgAFFAUJDAAQACIfAA==.Moriko:BAABLgAECn8UAAImAAcJTQyxKwA9AQAmAAcJTQyxKwA9AQAAAA==.',
Mu='Muggy:BAAALgAECgEJAQAAAA==.Murky:BAABLgAECn8dAAIOAAcJJRvlDADTAQAOAAcJJRvlDADTAQAAAA==.Musicmichael:BAAALgAECgYJCQAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn8iAAMdAAgJJgdcEwAIAQAdAAgJJgdcEwAIAQASAAYJewYWSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Nancybrew:BAABLgAECn8hAAMMAAgJXB/dBwBHAgAMAAgJXB/dBwBHAgAHAAIJdRJzWABtAAAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgcJEwAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAAALgAECgYJEgAAAA==.Nesqwik:BAAALgAECgMJBQAAAA==.Nevan:BAABLgAECn8dAAMGAAgJuSNUEQCIAgAGAAgJuSNUEQCIAgAIAAEJORP+7gA/AAAAAA==.Neverender:BAAALgAECgEJAgABLgAECgYJDgAJAAAAAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nidalee:BAAALgAECgUJBwAAAA==.Nippyvixen:BAAALgADCgcJBwAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn8mAAIfAAgJFCFwAQCLAgAfAAgJFCFwAQCLAgAAAA==.Norex:BAACLgAFFH8IAAMaAAUJmRfZHwBhAQAaAAQJmRfZHwBhAQAbAAEJAABmLwAAAAAuAAQKfyEAAxoACQkhEwJCAHcBABoACQmuEgJCAHcBABsABgmfCLUsANkAAAAA.Norm:BAAALgAECgYJCgAAAA==.Notekk:BAAALgAECgQJBwAAAA==.',
Nu='Nuggie:BAABLgAECn8dAAMQAAgJkhtPGgATAgAQAAcJkhtPGgATAgAXAAEJAAC9YgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutlips:BAAALgADCgUJCwAAAA==.',
Ny='Nylariaa:BAAALgAECgYJDwAAAA==.Nymia:BAABLgAECn8gAAIRAAgJBR6ZJAAoAgARAAgJBR6ZJAAoAgAAAA==.',
['Næ']='Næon:BAABLgAECn8bAAIHAAgJZxdzHQDKAQAHAAgJZxdzHQDKAQAAAA==.',
Ob='Oblake:BAABLgAECn8YAAIOAAcJkBQhIQDwAQAOAAcJkBQhIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAAALgAECgYJEQAAAA==.Olizza:BAAALgAECgIJAgABLgAECgYJFQAhAA0MAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECgkJDgAAAA==.',
Oo='Ooglaboogla:BAABLgAECn8qAAMPAAkJrBuiBQCTAgAPAAkJrBuiBQCTAgAZAAIJhxyLggCJAAAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.',
Os='Osserc:BAAALgADCgYJBgAAAA==.',
Ox='Oxyrotten:BAABLgAECn8YAAIaAAYJ/wsubAAKAQAaAAYJ/wsubAAKAQAAAA==.',
Pa='Pablo:BAABLgAECn82AAMLAAkJcyFfAQAHAwALAAkJcyFfAQAHAwAkAAEJZREPhwA1AAAAAA==.Pancho:BAABLgAECn8ZAAIMAAgJkhivCgAOAgAMAAgJkhivCgAOAgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAFFAIJAgAAAA==.Panzeria:BAABLgAECn8dAAIYAAcJPSU6CQDwAgAYAAcJPSU6CQDwAgAAAA==.Papito:BAAALgAECgkJDQAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECgUJCQAAAA==.Ponkofox:BAABLgAECn8bAAIVAAgJaRHeCQB6AQAVAAgJaRHeCQB6AQAAAA==.',
Pr='Prah:BAAALgAECgYJCgAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prise:BAAALgAECgEJAgAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prizefighter:BAAALgAECgYJCwAAAA==.Proditus:BAAALgAECgMJAwAAAA==.',
Ps='Pseudoholy:BAAALgADCgEJAQAAAA==.',
Pu='Putridvigor:BAAALgAFFAIJAgAAAA==.Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAAALgAECgcJDwAAAA==.',
['Pä']='Pälii:BAABLgAECn8eAAMGAAgJKQeFJgBWAQAGAAgJKQeFJgBWAQAIAAQJhA4g4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQABLgAFFAUJCwASAHoUAA==.Ragz:BAAALgAECgYJBgAAAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAABLgAECn8YAAIZAAkJ0xrXBQDaAgAZAAkJ0xrXBQDaAgAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn8rAAMlAAgJPSSQAgDLAgAlAAgJPSSQAgDLAgAeAAMJlhNVHgCVAAAAAA==.Ravissante:BAABLgAECn8eAAIgAAcJiAYvWwDsAAAgAAcJiAYvWwDsAAAAAA==.Rawranator:BAAALgAECgUJDAAAAA==.',
Re='Reesecupthis:BAABLgAECn8fAAIKAAgJGiJxAgCSAgAKAAgJGiJxAgCSAgABLgAFFAUJEwAKAEEcAA==.Remagix:BAAALgAECgEJAQAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECggJHQAGALkjAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECgkJDgAJAAAAAA==.Rhonis:BAAALgAECgMJAwAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMQAAcJJCDlKQC+AQAQAAYJ4B7lKQC+AQAXAAQJIB0uJAA4AQAAAA==.Rickyspanish:BAAALgAECgcJBAAAAA==.Ricochet:BAABLgAECn8eAAIGAAYJqRPCJwBOAQAGAAYJqRPCJwBOAQAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Rollmybitzup:BAAALgAFFAEJAQABLgAFFAUJCwASAHoUAA==.Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAABLgAECn8YAAMVAAgJwwf6DQAmAQAVAAgJ/gb6DQAmAQAPAAMJvwYsdwBmAAAAAA==.Roreck:BAAALgAECgkJBAAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAABLgAECn8jAAImAAgJmiVuBwDLAgAmAAgJmiVuBwDLAgAAAA==.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAAALgAECgUJDAAAAA==.',
Ry='Rybes:BAAALgAECgUJDAAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQAJAAAAAA==.',
Sa='Safehaven:BAAALgADCggJEAAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgAECgYJBwAAAA==.Samwìse:BAACLgAFFH8PAAInAAQJGA8PDAAMAQAnAAQJGA8PDAAMAQAuAAQKfycAAycACAncG3QOAHYCACcACAncG3QOAHYCABgABAkzEOk8AIgAAAAA.Sareir:BAAALgADCgMJAwAAAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgYJDgAAAA==.',
Sc='Scarlla:BAAALgAECggJEAAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgADCgQJBAABLgAECggJGgAMAEYXAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senpaii:BAAALgAECgEJAgAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECggJGAAQAPIYAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAFFAEJAQAAAA==.Serenidin:BAAALgAECgEJAQAAAA==.Serenio:BAAALgAECgEJBAAAAA==.Sereniswift:BAAALgAECgQJBQAAAA==.Serephita:BAABLgAECn8sAAIEAAkJFQjARwCQAQAEAAkJFQjARwCQAQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAABLgAECn8XAAMEAAYJixwvRwCRAQAEAAYJixwvRwCRAQApAAEJrwiUCwAwAAAAAA==.Shalaylea:BAAALgAECgQJBgAAAA==.Shamwich:BAAALgAECgYJDwAAAA==.Shanondorf:BAABLgAECn8bAAMUAAgJ3hvPAQA/AgAUAAgJ5RrPAQA/AgAOAAUJdxr3GQAxAQAAAA==.Shark:BAAALgAECgYJEwABLgAFFAUJEwAaAFQSAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn8oAAMSAAkJBBNpDgDoAQASAAkJBBNpDgDoAQATAAQJLgJANAByAAAAAA==.Shiggyll:BAAALgADCgIJAgAAAA==.Shildo:BAABLgAECn8kAAMYAAgJABpdCwAOAgAYAAgJABpdCwAOAgAmAAEJQQuqVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgYJCwAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgAECgEJAQAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAAALgAECgcJDgABLgAFFAQJEQAPAE0WAA==.Silecra:BAAALgADCgcJBwABLgAECggJIwAmAJolAA==.Sinscale:BAAALgAECgQJBAABLgAFFAUJFAAIAAwfAA==.Sinswrath:BAACLgAFFH8UAAIIAAUJDB8jCAByAQAIAAUJDB8jCAByAQAuAAQKfyUAAggACAkWJIEJAEUDAAgACAkWJIEJAEUDAAAA.',
Sk='Skarre:BAABLgAECn8hAAIgAAcJ2xwqMAA6AgAgAAcJ2xwqMAA6AgAAAA==.Skcusnor:BAAALgAECgcJEQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECgkJEwAAAA==.',
Sm='Smiteheal:BAAALgADCgMJAwAAAA==.Smores:BAACLgAFFH8OAAIRAAUJph+XBgDQAQARAAUJph+XBgDQAQAuAAQKfyAAAhEACQkAJacEAEQDABEACQkAJacEAEQDAAEuAAUUBwkZABEADR8A.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAACLgAFFH8JAAMTAAMJdghcBAC8AAATAAMJiAJcBAC8AAASAAMJIQh3LgCQAAAuAAQKfycAAxIACQm0EfggALgBABIACQm0EfggALgBABMAAQnBAGxGABkAAAAA.Snaccidentsh:BAAALgADCgMJAgABLgAFFAMJCQATAHYIAA==.Snaccidentww:BAABLgAECn8UAAIMAAgJDgqcGwBGAQAMAAgJDgqcGwBGAQABLgAFFAMJCQATAHYIAA==.Sneakyteeth:BAABLgAECn8fAAIOAAgJuQ2uEQCQAQAOAAgJuQ2uEQCQAQAAAA==.Snotzz:BAAALgAECgUJBgAAAA==.',
So='Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIaAAgJECJzKACZAgAaAAgJECJzKACZAgAAAA==.Soulwhisper:BAACLgAFFH8UAAIaAAUJoRoNKQBOAQAaAAUJoRoNKQBOAQAuAAQKfyUAAhoACAlWI00VAPwCABoACAlWI00VAPwCAAAA.',
Sp='Spaghetifire:BAABLgAFFH8LAAISAAUJehTmEgBAAQASAAUJehTmEgBAAQAAAA==.Sparklybeach:BAAALgADCggJCAAAAA==.Sphyr:BAAALgAECggJEQAAAA==.Spicynoodi:BAABLgAECn8cAAMTAAgJgAfPHQA/AQATAAcJfAfPHQA/AQASAAMJ0QXWRQB/AAAAAA==.Spyrodruid:BAAALgAFFAEJAQABLgAFFAMJDAAbAO0WAA==.Spyromonk:BAAALgAFFAEJAQABLgAFFAMJDAAbAO0WAA==.',
Sq='Sqoots:BAABLgAECn8hAAIEAAgJDiJkFgBnAgAEAAgJDiJkFgBnAgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgcJDwAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8lAAMPAAgJhhikEgDFAQAPAAgJhhikEgDFAQAZAAgJERF9TgBJAQAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8NAAMPAAUJIRyJCQBIAQAPAAQJIRyJCQBIAQAVAAEJAABPCgAAAAAuAAQKfyMAAg8ACAkDJAgLAOcCAA8ACAkDJAgLAOcCAAAA.Sukker:BAAALgAECgMJAwAAAA==.Sukkler:BAAALgADCgYJCAAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8OAAMDAAUJQxWxDwAMAQADAAUJ0xOxDwAMAQACAAEJegmXCwBUAAAuAAQKfyEAAwMACQkIIc8hAEYCAAMABwk0Ic8hAEYCAAIAAgmDIKMfAL4AAAAA.Supadoc:BAAALgAECgkJEQAAAA==.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylliseas:BAAALgADCgYJBgAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverhooves:BAAALgAECgMJAwAAAA==.Sylverlock:BAAALgAECgIJAgAAAA==.',
Ta='Ta:BAAALgADCgIJAgAAAA==.Tacosdk:BAAALgAECgUJCAAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Taladiira:BAAALgADCgcJAgAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECggJJQAPAIYYAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgADCggJCwAAAA==.Tayswiftagos:BAAALgAECgcJDwAAAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgcJBwAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thechadlad:BAAALgADCgYJBgAAAA==.Thedevilssin:BAAALgAECgYJCgAAAA==.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDwAAAA==.Theodas:BAAALgAFFAEJAQAAAA==.Therru:BAAALgADCggJGAABLgAECgcJFAAmAE0MAA==.Thien:BAAALgADCgkJCQAAAA==.Thorimm:BAAALgAECgEJAQAAAA==.Throbbert:BAAALgADCgcJBwABLgAECggJGwAUAN4bAA==.Thunderwater:BAAALgAECgQJCAAAAA==.',
Ti='Tiken:BAAALgAECgEJAgAAAA==.Tiktok:BAAALgAECgUJEQABLgAECgcJDwAJAAAAAA==.Tippss:BAACLgAFFH8JAAInAAQJDCBaBQB1AQAnAAQJDCBaBQB1AQAuAAQKfzQAAycACQmyJfgBAFQDACcACQmyJfgBAFQDACYACAmqFo0JAD8CAAAA.Tipsygypsy:BAABLgAECn8fAAIEAAcJDgihbAA4AQAEAAcJDgihbAA4AQAAAA==.',
To='Tokenbeef:BAACLgAFFH8GAAIZAAMJ9RGQIQDSAAAZAAMJ9RGQIQDSAAAuAAQKfyIAAxkACAl5GocPAEQCABkACAl5GocPAEQCAA8AAwlEBAt2AGoAAAAA.Tokenshaman:BAABLgAECn8bAAIVAAYJfAwGEAACAQAVAAYJfAwGEAACAQAAAA==.Torlon:BAAALgADCgEJAQAAAA==.Toxicdk:BAAALgAECgEJAQAAAA==.Toxicshamy:BAACLgAFFH8FAAMVAAIJPQk6BwCbAAAVAAIJ8gg6BwCbAAAPAAIJKQS/GQCIAAAuAAQKfyAABBUACQk5F84DADwCABUACAmdGc4DADwCAA8ABwnQEycpAMsBABkAAQmtGHt0AEYAAAAA.',
Tr='Trafficcones:BAAALgAECgMJAwAAAA==.Traugdor:BAAALgADCgkJDgAAAA==.Traylay:BAACLgAFFH8NAAIIAAUJUhZzGABJAQAIAAUJUhZzGABJAQAuAAQKfyEAAggACQnWJJ0MACkDAAgACQnWJJ0MACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAUJDQAIAFIWAA==.Tremana:BAAALgAECgMJAwAAAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8WAAIIAAYJUQlzqwArAQAIAAYJUQlzqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8RAAIPAAQJTRZJDQA+AQAPAAQJTRZJDQA+AQAuAAQKfyoAAg8ACQnUInYDANICAA8ACQnUInYDANICAAAA.',
Tu='Tujori:BAACLgAFFH8JAAImAAQJNRHyDgDgAAAmAAQJNRHyDgDgAAAuAAQKfx4AAycACAmfEpsuAIkBACcACAlJC5suAIkBACYABwm/ErQlAGcBAAAA.Turuce:BAAALgADCgYJBgAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwAJAAAAAA==.',
Tw='Twherk:BAAALgAECgcJDgABLgAFFAUJDQAmAM8SAA==.Twinmoonfury:BAABLgAECn8zAAMBAAgJNhtSCQA5AgABAAgJNhtSCQA5AgARAAYJPBO1WgBCAQAAAA==.Twobit:BAAALgAECgYJBgAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAABLgAECn8XAAIgAAgJRRSjJACuAQAgAAgJRRSjJACuAQAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8cAAIhAAgJsBxNNQDZAQAhAAgJsBxNNQDZAQAAAA==.',
Uh='Uhh:BAAALgADCgYJBwAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Va='Vaeros:BAABLgAECn8YAAISAAYJ5RFgJQAfAQASAAYJ5RFgJQAfAQAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgAECgYJCAAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8kAAIGAAkJTx7UCgBkAgAGAAkJTx7UCgBkAgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAABLgAECn8fAAICAAgJ3xgwBQAmAgACAAgJ3xgwBQAmAgAAAA==.Velithice:BAAALgAECgYJBwAAAA==.Venture:BAAALgAECgQJBAAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJDQABLgAECggJJQAPAIYYAA==.Warhéad:BAAALgAECgUJDAAAAA==.Wartonxp:BAABLgAECn8sAAIYAAgJfh5iCQAuAgAYAAgJfh5iCQAuAgAAAA==.Waterbôy:BAACLgAFFH8KAAIPAAQJqwtNEwAZAQAPAAQJqwtNEwAZAQAuAAQKfzQABA8ACQm4IGADANYCAA8ACQm4IGADANYCABkABQliCZFnAPAAABUAAgktBQcoAFwAAAAA.Waynee:BAAALgAECgYJCgAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAACLgAFFH8GAAISAAQJ6BFHFAA5AQASAAQJ6BFHFAA5AQAuAAQKfzMAAxIACQkvJc4AAGUDABIACQkvJc4AAGUDABMABglJFyQcAE8BAAAA.',
Wi='Wiggle:BAABLgAECn8qAAIFAAkJJB9pAADIAgAFAAkJJB9pAADIAgAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8NAAImAAUJzxL+CQA/AQAmAAUJzxL+CQA/AQAuAAQKfxoAAiYACAljIbEFAPMCACYACAljIbEFAPMCAAAA.',
Xa='Xanistra:BAACLgAFFH8MAAIQAAUJZxc+IgAwAQAQAAUJZxc+IgAwAQAuAAQKfyEAAxAACQkpH0wNABADABAACQkpH0wNABADABcABAm/HFQtAAgBAAAA.Xaylor:BAAALgADCgcJCgAAAA==.',
Xg='Xgamesmode:BAAALgADCgEJAQABLgAFFAMJBQAMAIUaAA==.',
Xz='Xzlemina:BAAALgAECgcJCQAAAA==.',
Ya='Yalaforth:BAABLgAECn8iAAIIAAgJWxIHNwCiAQAIAAgJWxIHNwCiAQAAAA==.Yamashaman:BAABLgAECn8nAAMZAAkJuRiYEAA4AgAZAAkJuRiYEAA4AgAPAAEJwwesbQAoAAAAAA==.Yardgnome:BAAALgAECgQJCAAAAA==.',
Ye='Yebefd:BAAALgADCgcJBwAAAA==.',
Yu='Yungbluudd:BAAALgAECgIJAwAAAA==.',
Za='Zaleth:BAAALgAECgQJBAAAAA==.Zamasu:BAABLgAECn8eAAIgAAcJJCA0EQA2AgAgAAcJJCA0EQA2AgAAAA==.Zapmybitzup:BAAALgAFFAMJBAABLgAFFAUJCwASAHoUAA==.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8RAAIIAAUJNiTRBQCuAQAIAAUJNiTRBQCuAQAuAAQKfyYAAggACAntIugZAM0CAAgACAntIugZAM0CAAAA.Zaszhadoom:BAEALgAECgEJAQABLgAFFAUJEQAIADYkAA==.Zaxxon:BAABLgAECn8rAAMSAAkJIBsLBQCgAgASAAkJIBsLBQCgAgATAAEJDQ3EPgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCwAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8pAAIdAAgJ9RvXBQAyAgAdAAgJ9RvXBQAyAgAAAA==.',
Zi='Zigfury:BAAALgAECgYJDwAAAA==.Zillagoth:BAAALgAECgMJAgAAAA==.Zira:BAABLgAECn8mAAIHAAgJ+RKUEwDCAQAHAAgJ+RKUEwDCAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgYJCAAAAA==.Zoìdberg:BAACLgAFFH8NAAIZAAIJcRWWFwCdAAAZAAIJcRWWFwCdAAAuAAQKfzAAAhkACAkEIrMHAPoCABkACAkEIrMHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAABLgAECn8aAAIaAAgJNhmWHQAXAgAaAAgJNhmWHQAXAgAAAA==.',
Zz='Zzor:BAACLgAFFH8VAAIEAAUJoR4iGgB4AQAEAAUJoR4iGgB4AQAuAAQKfyMAAgQACAnAJRAPAE8DAAQACAnAJRAPAE8DAAAA.Zzorfel:BAAALgAECgEJAgABLgAFFAUJFQAEAKEeAA==.Zzorshock:BAAALgAECgYJBgABLgAFFAUJFQAEAKEeAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAABLgAECn8WAAIEAAYJ3RMfrgCAAQAEAAYJ3RMfrgCAAQABLgAECggJQgANAEkfAA==.',
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

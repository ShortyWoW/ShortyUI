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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Priest-Holy','Shaman-Restoration','DeathKnight-Unholy','Druid-Guardian','Mage-Frost','Monk-Mistweaver','Druid-Feral','Druid-Restoration','Priest-Shadow','Mage-Arcane','Evoker-Devastation','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Affliction','Paladin-Holy','DeathKnight-Frost','Evoker-Preservation','Monk-Windwalker','Rogue-Subtlety','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn8mAAMBAAgJvyWuAAAKAwABAAgJvyWuAAAKAwACAAEJAADhgQA/AAAAAA==.',
Ad='Adorian:BAAALgAECgMJBQAAAA==.Adros:BAABLgAECn8XAAIDAAYJwhcHFQB+AQADAAYJwhcHFQB+AQAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAYJEQACAJANAA==.Adrrelle:BAACLgAFFH8RAAMCAAYJkA2CBgAsAQACAAYJYwyCBgAsAQAEAAIJLQYFJABYAAAuAAQKfyMABAIACQncHckTAJMCAAIACAmXH8kTAJMCAAEABAnZFxgXAAcBAAQAAgmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIFAAgJxQePrwAkAQAFAAgJxQePrwAkAQAAAA==.',
Ai='Ailaith:BAABLgAECn8lAAIEAAgJ8h84BgCUAgAEAAgJ8h84BgCUAgABLgAECgYJBgAGAAAAAA==.',
Ak='Akariliselle:BAAALgAECgYJDgAAAA==.Aknologia:BAAALgAECgIJAgAAAA==.',
Al='Alan:BAAALgAECgQJBwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgEJAQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAHALUfAA==.Alydrostage:BAAALgAECgYJDwAAAA==.Alystriaz:BAAALgAECgYJEgAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn8lAAIIAAgJTRCKDwCrAQAIAAgJTRCKDwCrAQAAAA==.Ameliya:BAAALgADCgkJEQAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Andaya:BAABLgAECn8bAAIJAAgJ6BerMgC6AQAJAAgJ6BerMgC6AQAAAA==.Andemeli:BAAALgADCgkJCQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAHALUfAA==.Aninja:BAEALgADCgQJBAABLgAFFAMJBgAKAHsgAA==.Anivia:BAAALgAECggJEAAAAA==.Ankoubailith:BAAALgAECgIJAgAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAAALgAECgYJCgAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8dAAILAAgJuhpyAwAMAgALAAgJuhpyAwAMAgAAAA==.Arctica:BAAALgAECgMJBwAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8UAAIMAAYJVQ9FVAA3AQAMAAYJVQ9FVAA3AQAAAA==.Arjurn:BAABLgAECn8mAAIMAAgJPR4ODwBlAgAMAAgJPR4ODwBlAgAAAA==.Armpitbutter:BAABLgAECn8mAAINAAgJBCTIBACKAgANAAgJBCTIBACKAgAAAA==.Artymiss:BAAALgAECgYJBwAAAA==.',
As='Ashireita:BAAALgAECgYJEAAAAA==.Astraleth:BAAALgAECgUJCgAAAA==.',
At='Atama:BAAALgADCggJCgAAAA==.',
Au='Authority:BAAALgADCggJCAAAAA==.Autry:BAABLgAECn8WAAMOAAYJMw8LCwAwAQAOAAYJMw8LCwAwAQAPAAYJCQzmMwAJAQAAAA==.',
Av='Avelina:BAAALgADCgcJDgAAAA==.Avocat:BAAALgAECgYJEAAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAYJFwALAIUeAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAGAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8cAAIFAAcJDg2XQABIAQAFAAcJDg2XQABIAQAAAA==.Balgar:BAABLgAECn8VAAMEAAYJLyOlEgD9AQAEAAYJKCOlEgD9AQACAAUJyxl6PgBhAQAAAA==.Balghas:BAABLgAECn8dAAIFAAgJwxsXHwDPAQAFAAgJwxsXHwDPAQAAAA==.Baumstrum:BAAALgAECgQJBQAAAA==.',
Be='Beezlbubba:BAAALgAECgQJBAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn8iAAIOAAgJCxBRBgCkAQAOAAgJCxBRBgCkAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAAALgAECgYJEgAAAA==.',
Bo='Boomchick:BAAALgADCgkJFQABLgAECgYJCgAGAAAAAA==.Boomparapara:BAAALgAECgUJEAAAAA==.Borrkbuster:BAAALgADCgcJBwAAAA==.Bosta:BAAALgADCgQJBAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgAAAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAAALgAECggJEAAAAA==.Brew:BAAALgAECgUJEgAAAA==.Brughe:BAABLgAECn8eAAIEAAcJfgtwZgA0AQAEAAcJfgtwZgA0AQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8PAAIQAAYJnBk1AQDJAQAQAAYJnBk1AQDJAQAuAAQKfxwAAhAACQm6HfQLAMMCABAACQm6HfQLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAAALgAECgcJEgABLgADCgYJBgAGAAAAAA==.Catty:BAABLgAECn8ZAAIOAAcJ+BPvBwB3AQAOAAcJ+BPvBwB3AQAAAA==.',
Ce='Celestyl:BAABLgAECn8YAAIRAAYJTQjsBAAFAQARAAYJTQjsBAAFAQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECgYJFwASAOYaAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgYJDAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAAALgAECgYJCAAAAA==.Chillybovine:BAAALgAECgYJDQAAAA==.Chromstrasza:BAABLgAECn8UAAISAAcJTRc9AwC7AQASAAcJTRc9AwC7AQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAIJAgAGAAAAAA==.',
Co='Conjarr:BAABLgAECn8eAAIIAAgJaxjgJQC8AQAIAAgJaxjgJQC8AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgMJBwAAAA==.Cougarsixsix:BAAALgAECgMJBQAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8WAAITAAYJ1CNVBQAJAgATAAYJ1CNVBQAJAgAAAA==.Creideam:BAAALgADCgYJBgAAAA==.Crimos:BAABLgAECn8kAAIKAAgJgRQCJQCsAQAKAAgJgRQCJQCsAQAAAA==.Crystalliney:BAAALgADCgYJBgAAAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8YAAIDAAYJyxxhCQB0AQADAAYJyxxhCQB0AQAAAA==.Dalind:BAAALgAECgMJBQAAAA==.Dalshiro:BAAALgAECgMJBAAAAA==.Damaclies:BAABLgAECn8bAAMUAAgJmRF7NgBRAQAUAAYJXw97NgBRAQAVAAUJLBGdMgDtAAAAAA==.Damedolla:BAABLgAECn8XAAMHAAYJPA7sQADjAAAWAAUJnw6+QAD3AAAHAAYJ/gvsQADjAAAAAA==.Dammerung:BAAALgAECgYJBwAAAA==.Darksyn:BAAALgAECgYJCgAAAA==.Darthbane:BAAALgADCggJHAAAAA==.Darude:BAAALgADCgcJEAAAAA==.',
De='Deadstout:BAAALgAECgQJBAAAAA==.Deepspace:BAABLgAECn8UAAIWAAYJbiZyBAA5AgAWAAYJbiZyBAA5AgAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demòn:BAAALgADCgIJAgAAAA==.Denounce:BAAALgAECgYJEQAAAA==.',
Di='Dia:BAAALgADCggJEgAAAA==.Diabetes:BAABLgAFFH8HAAINAAQJGRd4CgA0AQANAAQJGRd4CgA0AQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Diend:BAABLgAECn8lAAIJAAgJhx7pEACPAgAJAAgJhx7pEACPAgAAAA==.Dill:BAAALgADCgcJCgABLgAECggJJgABAL8lAA==.Dillathis:BAAALgADCgEJAQAAAA==.Dissonanita:BAAALgAECgEJAQAAAA==.',
Dj='Djthelock:BAAALgAECgYJDwAAAA==.',
Do='Dormoon:BAAALgAECgYJEQAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgQJCwAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAAALgAECgUJEAABLgAECgYJDgAGAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8dAAIOAAgJPBdlAwARAgAOAAgJPBdlAwARAgAAAA==.Drunkenpo:BAABLgAECn8lAAIXAAgJ+x9RBAByAgAXAAgJ+x9RBAByAgAAAA==.Drïzl:BAEALgADCgQJBAABLgAFFAMJBgAKAHsgAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8TAAIHAAYJhQkJUAC2AAAHAAYJhQkJUAC2AAAAAA==.',
Dw='Dwarfoo:BAAALgAECgMJBQAAAA==.Dweñde:BAABLgAECn8UAAIUAAcJ3gVxTgAFAQAUAAcJ3gVxTgAFAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIKAAUJngxldgCxAAAKAAUJngxldgCxAAAAAA==.',
Ed='Eddrick:BAAALgAECgYJEgAAAA==.Edrani:BAAALgADCgIJAwAAAA==.',
Ei='Eilethen:BAAALgAECgYJEgAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAECgkJPAAYALgbAA==.Elissabethh:BAAALgAECgMJBQAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.',
Em='Employee:BAAALgAECgQJCAAAAA==.',
En='Engo:BAABLgAECn8kAAIIAAgJISNrAQAgAwAIAAgJISNrAQAgAwAAAA==.',
Er='Eradrá:BAABLgAECn88AAMYAAkJuBvoAAAOAwAYAAkJjxvoAAAOAwAUAAgJJhQCGgDaAQAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAECggJJwAPAKoYAA==.Ersèlla:BAABLgAECn8nAAIPAAgJqhgBEQAHAgAPAAgJqhgBEQAHAgAAAA==.',
Eu='Eureka:BAAALgAECgYJCgAAAA==.',
Ev='Evandra:BAABLgAECn8YAAIJAAYJqxr0FADDAQAJAAYJqxr0FADDAQAAAA==.Evanorah:BAAALgAECgYJCwAAAA==.',
Ex='Exïle:BAEALgADCgcJDAABLgAFFAMJBgAKAHsgAA==.',
Fa='Faelithia:BAAALgAECgYJDwAAAA==.Fatalbrew:BAAALgADCgcJCQAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECgYJFwASAOYaAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Ferheim:BAAALgADCgkJDgAAAA==.',
Fi='Fiddyone:BAABLgAECn8XAAIKAAgJcR0ADQBeAgAKAAgJcR0ADQBeAgAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIZAAcJpBwJHgAmAgAZAAcJpBwJHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgMJAwAAAA==.',
Fo='Fodurzin:BAAALgADCgEJAQABLgADCgcJBwAGAAAAAA==.Fonta:BAAALgADCgEJAQAAAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8gAAIaAAgJthdlAgDdAQAaAAgJthdlAgDdAQAAAA==.Frosten:BAAALgADCgkJHwAAAA==.',
Fu='Furenio:BAABLgAECn8dAAILAAgJIRSdCABSAQALAAgJIRSdCABSAQAAAA==.',
Fy='Fyyre:BAAALgAECgMJBAAAAA==.',
Ga='Gabaghoul:BAABLgAECn8qAAIFAAgJJiGABwCiAgAFAAgJJiGABwCiAgAAAA==.Gaff:BAAALgAECgUJDAAAAA==.Galvan:BAAALgAECgEJAwAAAA==.Gasheth:BAAALgAECgMJAwAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgMJBAAAAA==.Grido:BAAALgADCgYJCAAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZBZAC5AQAFAAcJdBVBZAC5AQADAAUJghrFFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.',
Gu='Gulishdaniel:BAAALgAECgcJBwABLgAFFAYJDwAQAJwZAA==.',
Ha='Hadin:BAABLgAECn8jAAMMAAgJZiC3CgCUAgAMAAgJEyC3CgCUAgARAAMJqhytDwDHAAAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn8lAAMLAAgJZxYgCABgAQALAAgJZxYgCABgAQAOAAEJVBNeGwBFAAAAAA==.Hazenpryde:BAAALgAECgYJCwAAAA==.',
He='Hearsay:BAAALgAECgYJCgAAAA==.Hephaistian:BAAALgADCgcJEwAAAA==.Hespera:BAABLgAECn8bAAIPAAgJoSHrGABwAgAPAAgJoSHrGABwAgAAAA==.',
Hi='Hirari:BAAALgAECgcJEgAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAAALgAECgYJDwAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMUAAgJSRdOSQDuAQAUAAgJSRdOSQDuAQAVAAEJAAAAAAAAAAAAAA==.Husbando:BAAALgADCggJCgAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAAALgAECgcJCQAAAA==.Hydrá:BAAALgAECgcJBwAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwAAAA==.',
Ic='Iceamaris:BAAALgAECgYJDwAAAA==.',
Ie='Iechu:BAAALgAECgEJAQAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgEJAgAGAAAAAA==.',
Is='Isoth:BAAALgADCgYJBgAAAA==.',
Iv='Ivern:BAAALgAFFAEJAgABLgAFFAYJFwAbAJ0XAA==.',
Ja='Jaod:BAAALgADCgYJCAAAAA==.',
Jd='Jdghoul:BAAALgAECgYJBgAAAA==.',
Ji='Jindrac:BAAALgAECgIJAgAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECggJGQAHAL0hAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECgYJBgAAAA==.Kaltharion:BAAALgAECgQJBQAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn8jAAQUAAgJexboOgBCAQAUAAcJexboOgBCAQAVAAMJYwUDTACJAAAYAAIJuQbKIgBnAAAAAA==.Kantong:BAABLgAECn8ZAAIcAAgJchkWCQDpAQAcAAgJchkWCQDpAQAAAA==.Kapp:BAAALgADCgQJBAAAAA==.Karabar:BAABLgAECn8mAAMDAAgJaB5fAgBmAgADAAgJ+R1fAgBmAgAFAAYJsCG2OwA1AgAAAA==.Kasarra:BAAALgAECgYJDAAAAA==.Kazagol:BAABLgAECn8mAAIHAAgJ5B89BwBnAgAHAAgJ5B89BwBnAgAAAA==.',
Kh='Khamaracy:BAAALgAECgMJBQAAAA==.Khronni:BAAALgAECgIJAgAAAA==.Khrooze:BAAALgAECgMJBwAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAAALgAECgMJBQAAAA==.Kittei:BAABLgAECn8mAAILAAgJlxB7CgAfAQALAAgJlxB7CgAfAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.',
Ku='Kurick:BAAALgADCggJEgABLgADCgkJDwAGAAAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAAALgAECgYJEgAAAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Latte:BAAALgADCgIJAgAAAA==.',
Le='Leeli:BAAALgADCgUJBQAAAA==.Lenity:BAABLgAECn8ZAAIdAAYJGRThEgBKAQAdAAYJGRThEgBKAQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lilithene:BAAALgAECgIJAgABLgAECgYJEAAGAAAAAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.',
Lo='Lokinah:BAAALgAECgYJCgAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAAALgAECgYJCwAAAA==.Lukeduke:BAAALgAFFAIJAgABLgAFFAYJFwALAIUeAA==.Luketheduke:BAACLgAFFH8XAAMLAAYJhR6AAADTAQALAAUJhR6AAADTAQAOAAEJAAAHBwA3AAAuAAQKfycAAwsACQkqJSABAFcDAAsACQkqJSABAFcDAA4ABAmxFXkcAAkBAAAA.Lumilia:BAAALgADCgUJBQAAAA==.Lunä:BAABLgAECn8UAAIJAAgJ1BVrIgAQAgAJAAgJ1BVrIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8bAAIMAAgJ2BnpGgAKAgAMAAgJ2BnpGgAKAgAAAA==.',
['Lô']='Lôckrocks:BAAALgAECgYJBwAAAA==.',
['Lý']='Lýsendra:BAAALgADCgEJAQAAAA==.',
Ma='Magictomb:BAABLgAECn8cAAQeAAcJbQ9HQQBEAQAeAAcJbQ9HQQBEAQAJAAYJ6A2lMAD8AAAfAAEJmwM0GwAqAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Maldrake:BAAALgAECgQJBAABLgAECgYJBgAGAAAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECgYJBgAGAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAAALgAECgQJBAABLgAECgYJBgAGAAAAAA==.Mallord:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Malthanas:BAABLgAECn8lAAQBAAgJhxi8BwDsAQABAAgJjRe8BwDsAQACAAQJtggvYwCzAAAEAAEJmRFShwBGAAAAAA==.Mandarin:BAAALgAECgYJEgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAAALgAFFAEJAQAAAA==.Marashades:BAAALgADCgQJBAABLgAECgYJFgATANQjAA==.',
Mc='Mcbadden:BAAALgAECgYJBgAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwAAAA==.Mercia:BAABLgAECn8cAAIDAAcJehbxCgBTAQADAAcJehbxCgBTAQAAAA==.Merekoma:BAAALgAECgUJCAAAAA==.',
Mi='Milarra:BAAALgAECgMJAwAAAA==.Milhouse:BAAALgAECgEJAQAAAA==.Minalan:BAAALgADCgYJCgABLgAECgMJBwAGAAAAAA==.Mingonashoba:BAAALgAECgUJBQAAAA==.Miragosa:BAABLgAECn8eAAIbAAgJwwQ9KgAgAQAbAAgJwwQ9KgAgAQAAAA==.Misschris:BAABLgAECn8WAAINAAYJBwkPIwDnAAANAAYJBwkPIwDnAAAAAA==.Mizu:BAAALgADCgcJDgAAAA==.',
Mo='Moadeed:BAAALgAECgYJBwAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgEJAQAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAAALgADCgIJAgAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAAALgAECgYJCwAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAECgEJAQABLgAECgcJHAAeAG0PAA==.Nausican:BAABLgAECn8WAAIaAAYJYQqFCwAFAQAaAAYJYQqFCwAFAQAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAABLgAECn8YAAIFAAgJHRTwHQDWAQAFAAgJHRTwHQDWAQAAAA==.Necrotherys:BAAALgAECgYJEwAAAA==.Nelandra:BAAALgAECgMJBQAAAA==.',
Ni='Nicklaus:BAAALgAECgYJCwAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8GAAIKAAMJeyAqJgAkAQAKAAMJeyAqJgAkAQAuAAQKfyUAAwoACAndIzgGALsCAAoACAndIzgGALsCABoAAQmqG/kNAFUAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwAAAA==.Nomahuata:BAABLgAECn8nAAIeAAgJqhMvEQCYAQAeAAgJqhMvEQCYAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyxi:BAAALgAECgIJAgAAAA==.',
['Né']='Néo:BAAALgADCgIJAgAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAAALgAECgUJEgABLgAECggJFwAKAHEdAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgcJDQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgADCgcJBwAAAA==.Palanas:BAAALgAECgcJDwAAAA==.Palochka:BAAALgAECgIJAgAAAA==.Paradots:BAABLgAECn8WAAIbAAYJtRqVBwC5AQAbAAYJtRqVBwC5AQABLgADCgYJBgAGAAAAAA==.Paranitis:BAAALgAECgYJCgAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAECgUJEAAGAAAAAA==.',
Pe='Petronella:BAABLgAECn8kAAMgAAgJxAilFABeAQAgAAgJxAilFABeAQAhAAQJ+wNVgwCxAAAAAA==.Pezmage:BAAALgAECgEJAQAAAA==.',
Ph='Phatboi:BAAALgADCgIJAwAAAA==.',
Pi='Pixystix:BAAALgAECgMJBQAAAA==.',
Po='Poisonspain:BAAALgADCggJCgAAAA==.Potscold:BAACLgAFFH8LAAIMAAYJWBh/DAC5AQAMAAYJWBh/DAC5AQAuAAQKfzsAAgwACAnaJTQEAPwCAAwACAnaJTQEAPwCAAAA.Poxi:BAAALgAECgIJAgABLgAECggJFgAiAA0XAA==.',
Pr='Prion:BAAALgAECgQJDwAAAA==.',
Pu='Pull:BAABLgAECn8YAAILAAcJhxsFBgCgAQALAAcJhxsFBgCgAQAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDgAAAA==.Raega:BAAALgADCggJCAAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAAALgAECgIJAgAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgAECgIJAgAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8WAAIUAAYJGQREZwDBAAAUAAYJGQREZwDBAAAAAA==.Reliala:BAAALgADCgYJCAAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECgYJDgAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAGAAAAAA==.',
Rh='Rhobes:BAAALgADCgkJFgAAAA==.Rhondta:BAABLgAECn8YAAIUAAYJxQ5eQQAuAQAUAAYJxQ5eQQAuAQAAAA==.',
Ri='Rickormortis:BAAALgAECgYJCAABLgAECgYJFgANAAcJAA==.Rictus:BAABLgAECn8eAAIMAAgJTCMGCwCQAgAMAAgJTCMGCwCQAgAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAAALgAECgYJEgAAAA==.',
Ro='Roades:BAAALgADCgcJCwAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJAwAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgAECgQJBQABLgAECgYJCgAGAAAAAA==.Rurry:BAACLgAFFH8XAAIbAAYJnRc9AwDPAQAbAAYJnRc9AwDPAQAuAAQKfykABBsACQlkIrQCAEADABsACQlkIrQCAEADABIABQm6GRYWAI8BACIAAwlTF+xGAL8AAAAA.',
Ry='Ryuj:BAAALgADCgYJBgAAAA==.Ryumi:BAABLgAECn8ZAAIHAAgJvSFNFQC/AQAHAAgJvSFNFQC/AQAAAA==.Ryur:BAAALgAECgQJCAAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgYJFgANAAcJAA==.Sahwe:BAAALgADCgcJBwAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCggJHwAAAA==.Saphisha:BAAALgAECgYJCwAAAA==.Sasora:BAAALgAECgUJCgAAAA==.Saucemagic:BAAALgAECgYJCAAAAA==.Savonah:BAAALgADCggJHwAAAA==.',
Sc='Scaledaddy:BAAALgAECgUJBQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAUJDgAKABgZAA==.Scaryl:BAAALgADCgkJFQAAAA==.Scourgespawn:BAACLgAFFH8OAAMKAAUJGBllGABSAQAKAAQJGBllGABSAQAjAAIJqQixGAA1AAAuAAQKfyMAAwoACQleIDMkAK0CAAoACQleIDMkAK0CACMAAwlqEycfAHsAAAAA.',
Se='Selenë:BAAALgAECgMJAwAAAA==.Sengoku:BAAALgADCggJCgAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8WAAIEAAYJxR3JIACdAQAEAAYJxR3JIACdAQAAAA==.Sharivee:BAAALgAECgUJDAAAAA==.Sharko:BAABLgAECn8XAAMDAAcJzBWRDwDMAQADAAcJzBWRDwDMAQAZAAIJwgN+iwBPAAAAAA==.Shibui:BAABLgAECn8lAAMWAAgJ4RQfGgDyAQAWAAgJohQfGgDyAQAHAAcJOgYhowDNAAAAAA==.Shiggles:BAAALgAECgYJBgAAAA==.Shinhaein:BAABLgAECn8UAAIMAAYJzhSYSwBNAQAMAAYJzhSYSwBNAQABLgAFFAMJBgAKAGIaAA==.Shockazilla:BAABLgAECn8kAAMZAAgJ8xzXBwBeAgAZAAgJ8xzXBwBeAgAFAAMJVw+l/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAECgQJCAAAAA==.Silverhorn:BAAALgAECgQJCAAAAA==.',
Sk='Skoduh:BAAALgAECgUJEQAAAA==.Skyelene:BAABLgAECn8UAAMeAAYJCg+1QwA6AQAeAAYJCg+1QwA6AQAJAAIJ0gXzVwBLAAAAAA==.',
Sl='Slaanesh:BAAALgAECgYJDAAAAA==.Sluggo:BAAALgAECgMJAwAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgRrEwAHAQACAAQJhgRrEwAHAQAuAAQKfyIAAwIACAkLGS8cAEMCAAIACAnYGC8cAEMCAAQABAmEDTaaAJ8AAAAA.',
Sm='Smeagosses:BAAALgADCgcJBwAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgQJBgAAAA==.Solinaara:BAAALgADCgEJAQAAAA==.Soraka:BAAALgAFFAIJAgAAAA==.',
Sp='Spiralist:BAAALgAECgYJEgAAAA==.',
St='Starge:BAAALgAECgQJBAAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJCAAGAAAAAA==.Stonedalways:BAAALgAECgMJAwAAAA==.',
Su='Sunfuri:BAABLgAECn8kAAIhAAgJ0Ab4GgBYAQAhAAgJ0Ab4GgBYAQAAAA==.Sunjan:BAAALgADCggJDwAAAA==.Sus:BAACLgAFFH8TAAIWAAYJ6xoyAQCTAQAWAAYJ6xoyAQCTAQAuAAQKfyIAAhYACQmXI5YDAEcDABYACQmXI5YDAEcDAAAA.Susanoo:BAAALgAECgYJEgAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAAALgAECgQJDQAAAA==.Takeko:BAAALgADCgcJDgABLgAECgMJBQAGAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJCgAAAA==.Taranad:BAAALgAECgQJBQAAAA==.Tarathor:BAAALgAECgMJBQAAAA==.Tasha:BAAALgAECgEJAQABLgAECgQJDwAGAAAAAA==.Tauroctony:BAABLgAECn8WAAILAAcJPyGhBACiAgALAAcJPyGhBACiAgAAAA==.',
Te='Tea:BAAALgADCgkJCwABLgAECggJJQAIAE0QAA==.Teknofarious:BAAALgAECgEJAgAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgADCggJDgABLgAECggJJQABAIcYAA==.Thesafe:BAAALgAECgIJAgAAAA==.Thialia:BAAALgAECgYJBgAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn8mAAIkAAgJgSHdAQAMAwAkAAgJgSHdAQAMAwAAAA==.',
To='Toenailjuice:BAAALgADCgUJBQABLgAECggJJgANAAQkAA==.Torrey:BAABLgAECn8YAAIZAAgJHiVuAwA8AwAZAAgJHiVuAwA8AwAAAA==.',
Tr='Trix:BAABLgAECn8mAAIJAAgJdAykIABgAQAJAAgJdAykIABgAQAAAA==.',
Tu='Tulsi:BAABLgAECn8fAAIlAAgJtiFiAQBPAgAlAAgJtiFiAQBPAgAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8VAAIFAAYJ2RV1VAARAQAFAAYJ2RV1VAARAQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgIJAgAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIHAAgJtR/oEgDUAQAHAAgJtR/oEgDUAQAAAA==.Valdr:BAABLgAECn8YAAMiAAYJLBTOFgBHAQAiAAYJLBTOFgBHAQASAAQJowzSKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAHALUfAA==.Vas:BAAALgADCgYJEQAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vevicenth:BAAALgADCggJGAAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8SAAIMAAUJcB5eCgDMAQAMAAUJcB5eCgDMAQAuAAQKfxsAAwwACQlNIbchAOwCAAwACQlNIbchAOwCABEAAgl2FLYTAIkAAAAA.',
Wh='Whakan:BAAALgADCggJHwABLgAECgYJCwAGAAAAAA==.',
Wo='Wolfos:BAAALgAECgUJBgABLgAECggJJgANAFwlAA==.',
Wt='Wtfox:BAEALgAECgQJBwABLgAECgcJFgAeALEXAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgEJAgAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgMJBQAAAA==.Xalatos:BAAALgADCgEJAQAAAA==.Xalfein:BAAALgADCggJEgAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECggJJQAEALcbAA==.',
Ya='Yanakana:BAAALgAECgIJAgAAAA==.',
Yd='Ydalise:BAAALgAECgEJAQAAAA==.Ydrassil:BAAALgAECgQJBQABLgAECgYJCgAGAAAAAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJBwAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8ZAAMEAAcJpRLPJgB9AQAEAAcJpRLPJgB9AQACAAIJ4wTdfQBOAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAAALgAECgUJBQAAAA==.Zeusinator:BAAALgAECgYJEAAAAA==.',
Zi='Zinu:BAABLgAECn8lAAIEAAgJtxspFwB/AgAEAAgJtxspFwB/AgAAAA==.Zivalisse:BAAALgAECgQJBAAAAA==.',
Zu='Zulfionn:BAAALgAECgYJDgAAAA==.',
['Áy']='Áyrá:BAABLgAECn8YAAIZAAYJUB7pEQDOAQAZAAYJUB7pEQDOAQAAAA==.',
['Åp']='Åpollyon:BAAALgAECgIJAgAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8XAAMSAAYJ5hp1FAChAQASAAYJ5hp1FAChAQAiAAMJ4heHRQDHAAAAAA==.',
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

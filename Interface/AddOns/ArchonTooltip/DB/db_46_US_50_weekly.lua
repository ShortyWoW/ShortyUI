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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Priest-Holy','Shaman-Restoration','Druid-Guardian','Mage-Frost','Monk-Mistweaver','Druid-Feral','Priest-Shadow','Evoker-Devastation','Warlock-Demonology','DeathKnight-Unholy','Monk-Brewmaster','DemonHunter-Havoc','Warlock-Affliction','Druid-Restoration','Paladin-Holy','DeathKnight-Frost','Mage-Arcane','Warlock-Destruction','Evoker-Preservation','Evoker-Augmentation','Shaman-Elemental','Warrior-Arms','Warrior-Fury','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn8dAAMBAAYJoiZrAQA9AgABAAYJoiZrAQA9AgACAAEJAADZgQA/AAAAAA==.',
Ad='Adorian:BAAALgAECgIJAgAAAA==.Adros:BAABLgAECn8XAAIDAAYJwhcHFQB+AQADAAYJwhcHFQB+AQAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAUJEAACAB0NAA==.Adrrelle:BAACLgAFFH8QAAMCAAUJHQ25AwDkAAACAAUJpAu5AwDkAAAEAAIJLQYCJABYAAAuAAQKfx4AAwIACAmXH8UTAJMCAAIACAmXH8UTAJMCAAQAAQmMH1y4AFIAAAAA.',
Ae='Aelon:BAABLgAECn8aAAIFAAYJ3QiHrwAkAQAFAAYJ3QiHrwAkAQAAAA==.',
Ai='Ailaith:BAABLgAECn8cAAIEAAgJZB7jBQATAgAEAAgJZB7jBQATAgABLgAECgEJAQAGAAAAAA==.',
Ak='Akariliselle:BAAALgAECgYJDQAAAA==.Aknologia:BAAALgADCgkJEAAAAA==.',
Al='Alan:BAAALgAECgQJBwAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIQAHANMcAA==.Alydrostage:BAAALgAECgUJCQAAAA==.Alystriaz:BAAALgAECgYJEAAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn8cAAIIAAgJ6gmiMgB1AQAIAAgJ6gmiMgB1AQAAAA==.Ameliya:BAAALgADCgkJCwAAAA==.Ameng:BAAALgAECgIJBAAAAA==.',
An='Andaya:BAABLgAECn8XAAIJAAcJvhSrMgC6AQAJAAcJvhSrMgC6AQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIQAHANMcAA==.Anivia:BAAALgAECgcJDwAAAA==.Ankoubailith:BAAALgAECgIJAgAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAAALgAECgMJBAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8VAAIKAAYJFh3RAgCPAQAKAAYJFh3RAgCPAQAAAA==.Arctica:BAAALgAECgIJAwAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAAALgAECgYJCgAAAA==.Arjurn:BAABLgAECn8dAAILAAYJvhwaFQCaAQALAAYJvhwaFQCaAQAAAA==.Armpitbutter:BAABLgAECn8dAAIMAAYJzSQXDgB1AgAMAAYJzSQXDgB1AgAAAA==.Artymiss:BAAALgAECgUJBQAAAA==.',
As='Ashireita:BAAALgAECgYJEAAAAA==.Astraleth:BAAALgAECgQJBQAAAA==.',
At='Atama:BAAALgADCgIJAgAAAA==.',
Au='Autry:BAAALgAECgYJEAAAAA==.',
Av='Avelina:BAAALgADCgYJCQAAAA==.Avocat:BAAALgAECgYJCgAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAUJEgAKADAcAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAGAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8VAAIFAAYJ0QoNJQATAQAFAAYJ0QoNJQATAQAAAA==.Balgar:BAAALgAECgYJEwAAAA==.Balghas:BAABLgAECn8dAAIFAAgJwxuRCwDZAQAFAAgJwxuRCwDZAQAAAA==.Baumstrum:BAAALgAECgQJBAAAAA==.',
Be='Beezlbubba:BAAALgADCgMJAwAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn8ZAAINAAYJxA/WBQAgAQANAAYJxA/WBQAgAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAAALgAECgYJDAAAAA==.',
Bo='Boomchick:BAAALgADCgcJDAABLgAECgMJBAAGAAAAAA==.Boomparapara:BAAALgAECgQJCQABLgAECgUJBQAGAAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgAAAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAAALgAECgcJDwAAAA==.Brew:BAAALgAECgUJCwAAAA==.Brughe:BAABLgAECn8XAAIEAAcJ4wogGQAzAQAEAAcJ4wogGQAzAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8NAAIOAAUJFxm+AQBdAQAOAAUJFxm+AQBdAQAuAAQKfxkAAg4ACQn6GfULAMMCAA4ACQn6GfULAMMCAAAA.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAAALgAECgUJCwABLgADCgYJBgAGAAAAAA==.Catty:BAABLgAECn8ZAAINAAcJ+BNSAwCGAQANAAcJ+BNSAwCGAQAAAA==.',
Ce='Celestyl:BAAALgAECgYJEgAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECgYJFwAPAOYaAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgYJCgAAAA==.Cheesehead:BAAALgADCgYJEAAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAAALgAECgYJCAAAAA==.Chillybovine:BAAALgAECgQJBQAAAA==.Chromstrasza:BAAALgAECgYJDQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAUJEQAQAO0YAA==.',
Co='Conjarr:BAABLgAECn8ZAAIIAAYJ+hneJQC8AQAIAAYJ+hneJQC8AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgIJAgAAAA==.Cougarsixsix:BAAALgAECgIJAgAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAAALgAECgYJDgAAAA==.Crimos:BAABLgAECn8dAAIRAAgJPhIrEgCCAQARAAgJPhIrEgCCAQAAAA==.Crystalliney:BAAALgADCgYJBgABLgAECggJHAASAPIlAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAAALgAECgYJEAAAAA==.Dalind:BAAALgAECgIJAgAAAA==.Dalshiro:BAAALgAECgMJAwAAAA==.Damaclies:BAAALgAECgcJEgAAAA==.Damedolla:BAABLgAECn8XAAMTAAYJZgy8QAD3AAATAAUJnw68QAD3AAAHAAYJKAjPMQCnAAAAAA==.Dammerung:BAAALgAECgUJBQAAAA==.Darksyn:BAAALgAECgQJBAAAAA==.Darthbane:BAAALgADCggJFAAAAA==.Darude:BAAALgADCgcJEAAAAA==.',
De='Deadstout:BAAALgAECgQJBAAAAA==.Deepspace:BAAALgAECgYJDgAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dekkan:BAAALgAECgYJDwAAAA==.Demòn:BAAALgADCgIJAgAAAA==.Denounce:BAAALgAECgYJEQAAAA==.',
Di='Dia:BAAALgADCgUJCgAAAA==.Diabetes:BAAALgAFFAMJAwAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Diend:BAABLgAECn8cAAIJAAgJmRzsEACPAgAJAAgJmRzsEACPAgAAAA==.Dill:BAAALgADCgYJBgABLgAECgYJHQABAKImAA==.Dillathis:BAAALgADCgEJAQAAAA==.Dissonanita:BAAALgAECgEJAQAAAA==.',
Dj='Djthelock:BAAALgAECgYJCwAAAA==.',
Do='Dormoon:BAAALgAECgYJEQAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgQJCwAAAA==.Drakur:BAAALgAECgYJBwAAAA==.Drbrad:BAAALgAECgQJCQABLgAECgYJDgAGAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8VAAINAAYJQxikAwB4AQANAAYJQxikAwB4AQAAAA==.Drunkenpo:BAABLgAECn8cAAISAAgJHx+YEACVAgASAAgJHx+YEACVAgAAAA==.Drïzl:BAEALgADCgQJBAABLgAECgYJHAARAEYlAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAAALgAECgYJEAAAAA==.',
Dw='Dwarfoo:BAAALgAECgIJAgAAAA==.Dweñde:BAABLgAECn8UAAIQAAcJ3gW9IgARAQAQAAcJ3gW9IgARAQAAAA==.',
['Dë']='Dëthmetal:BAAALgAECgUJDwAAAA==.',
Ed='Eddrick:BAAALgAECgYJDAAAAA==.Edrani:BAAALgADCgEJAQAAAA==.',
Ei='Eilethen:BAAALgAECgYJEAAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAECgkJMQAUAI8bAA==.Elissabethh:BAAALgAECgIJAgAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.',
Em='Employee:BAAALgAECgQJCAAAAA==.',
En='Engo:BAABLgAECn8dAAIIAAgJSSJvAAAQAwAIAAgJSSJvAAAQAwAAAA==.',
Er='Eradrá:BAABLgAECn8xAAIUAAkJjxvoAAAOAwAUAAkJjxvoAAAOAwAAAA==.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgQJBAAAAA==.Ersèlla:BAABLgAECn8jAAIVAAgJJxadCADWAQAVAAgJJxadCADWAQAAAA==.',
Eu='Eureka:BAAALgAECgUJBwAAAA==.',
Ev='Evandra:BAAALgAECgYJEAAAAA==.Evanorah:BAAALgAECgUJCgAAAA==.',
Ex='Exïle:BAEALgADCgcJDAABLgAECgYJHAARAEYlAA==.',
Fa='Faelithia:BAAALgAECgYJCwAAAA==.Fatalbrew:BAAALgADCgIJAgAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECgYJFwAPAOYaAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Ferheim:BAAALgADCgkJDgAAAA==.',
Fi='Fiddyone:BAAALgAECggJDwAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIWAAcJpBwLHgAmAgAWAAcJpBwLHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgADCgIJAgAAAA==.',
Fo='Fonta:BAAALgADCgEJAQAAAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8XAAIXAAcJpxgWAgBtAQAXAAcJpxgWAgBtAQAAAA==.Frosten:BAAALgADCgkJFgAAAA==.',
Fu='Furenio:BAABLgAECn8YAAIKAAcJCxYyEgBQAQAKAAcJCxYyEgBQAQAAAA==.',
Fy='Fyyre:BAAALgAECgIJAgAAAA==.',
Ga='Gabaghoul:BAABLgAECn8iAAIFAAgJsB8+BgAuAgAFAAgJsB8+BgAuAgAAAA==.Gaff:BAAALgAECgQJBwAAAA==.Galvan:BAAALgAECgEJAQAAAA==.Gasheth:BAAALgAECgMJAwAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Graycen:BAAALgAECgEJAQAAAA==.Grido:BAAALgADCgMJAwAAAA==.Grimbrindral:BAABLgAECn8hAAMFAAcJ5hZHZAC5AQAFAAcJdBVHZAC5AQADAAUJghrFFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAFAOYWAA==.',
Gu='Gulishdaniel:BAAALgAECgcJBwABLgAFFAUJDQAOABcZAA==.',
Ha='Hadin:BAABLgAECn8aAAMLAAgJEBv2CgD+AQALAAgJvRr2CgD+AQAYAAMJqhypDwDHAAAAAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn8cAAIKAAgJYRQwDQC0AQAKAAgJYRQwDQC0AQAAAA==.Hazenpryde:BAAALgAECgUJCgAAAA==.',
He='Hearsay:BAAALgAECgQJBAAAAA==.Hephaistian:BAAALgADCgYJDAAAAA==.Hespera:BAABLgAECn8bAAIVAAgJoSHsGABwAgAVAAgJoSHsGABwAgAAAA==.',
Hi='Hirari:BAAALgAECgcJCwAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAAALgAECgUJCQAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMQAAgJSRfNDACwAQAQAAgJSRfNDACwAQAZAAEJAABSFgAAAAAAAA==.Husbando:BAAALgADCggJCgAAAA==.Husey:BAAALgAECgMJAwAAAA==.',
Hy='Hydrangea:BAAALgAECgMJBAAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgYJBgABLgADCggJEgAGAAAAAA==.',
Ic='Iceamaris:BAAALgAECgYJDgAAAA==.',
Ie='Iechu:BAAALgADCggJEgAAAA==.',
In='Innanna:BAAALgADCgQJBAABLgAECgEJAQAGAAAAAA==.',
Is='Isoth:BAAALgADCgYJBgAAAA==.',
Iv='Ivern:BAAALgAFFAEJAQABLgAFFAUJEgAaALEaAA==.',
Jd='Jdghoul:BAAALgADCgIJAgAAAA==.',
Ji='Jindrac:BAAALgADCgYJBgAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECggJGwAHAMccAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECgYJBgAAAA==.Kaltharion:BAAALgAECgQJBAAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kana:BAAALgADCggJEAAAAA==.Kanade:BAABLgAECn8bAAQQAAgJbhPADQCmAQAQAAcJbhPADQCmAQAZAAMJYwX8SwCJAAAUAAIJuQbIIgBnAAAAAA==.Kantong:BAAALgAECgcJEQAAAA==.Karabar:BAABLgAECn8dAAMDAAYJ9CGwAgDCAQAFAAYJsCG7OwA1AgADAAYJ6h6wAgDCAQAAAA==.Kasarra:BAAALgAECgUJBQAAAA==.Kazagol:BAABLgAECn8dAAIHAAYJHR5nFABaAQAHAAYJHR5nFABaAQAAAA==.',
Kh='Khamaracy:BAAALgAECgIJAgAAAA==.Khronni:BAAALgAECgEJAQAAAA==.Khrooze:BAAALgAECgMJBgAAAA==.',
Ki='Kidos:BAAALgAECgMJAwAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAAALgAECgIJAgAAAA==.Kittei:BAABLgAECn8dAAIKAAYJmRGgFAAnAQAKAAYJmRGgFAAnAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.',
Ku='Kurick:BAAALgADCggJEgAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAAALgAECgYJEAABLgAECggJFQAbAJobAA==.',
La='Latte:BAAALgADCgIJAgAAAA==.',
Le='Leeli:BAAALgADCgUJBQAAAA==.Lenity:BAAALgAECgYJEgAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.',
Lo='Lokinah:BAAALgAECgQJBAAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgMJAwAAAA==.Lucoryphus:BAAALgAECgUJCgAAAA==.Lukeduke:BAAALgAFFAIJAgABLgAFFAUJEgAKADAcAA==.Luketheduke:BAACLgAFFH8SAAMKAAUJMByCAABwAQAKAAQJMByCAABwAQANAAEJAAAIBwA3AAAuAAQKfyQAAwoACQkeIx4BAFcDAAoACQkeIx4BAFcDAA0ABAmxFXgcAAkBAAAA.Lumilia:BAAALgADCgUJBQAAAA==.',
Ly='Lydia:BAAALgAECgcJEwAAAA==.',
['Lô']='Lôckrocks:BAAALgAECgIJAgAAAA==.',
Ma='Magictomb:BAABLgAECn8VAAMcAAYJAQ9GQQBEAQAcAAYJAQ9GQQBEAQAJAAUJLASzcgDEAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Maldrake:BAAALgAECgQJBAAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECgQJBAAGAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAAALgADCggJGgABLgAECgQJBAAGAAAAAA==.Malthanas:BAABLgAECn8cAAMBAAgJEhWdCgAuAgABAAgJEhWdCgAuAgACAAQJtgg2YwCzAAAAAA==.Mandarin:BAAALgAECgYJDAAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAAALgAECgYJCAAAAA==.Marashades:BAAALgADCgQJBAABLgAECgYJDgAGAAAAAA==.',
Mc='Mcbadden:BAAALgAECgYJBgAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwAAAA==.Mercia:BAABLgAECn8VAAIDAAYJIRbmFwBYAQADAAYJIRbmFwBYAQAAAA==.Merekoma:BAAALgAECgMJAwAAAA==.',
Mi='Milarra:BAAALgAECgMJAwAAAA==.Milhouse:BAAALgADCgYJDwAAAA==.Minalan:BAAALgADCgYJCgABLgAECgMJBgAGAAAAAA==.Mingonashoba:BAAALgADCgkJGAAAAA==.Miragosa:BAABLgAECn8cAAIaAAgJwwRAKgAgAQAaAAgJwwRAKgAgAQAAAA==.Misschris:BAAALgAECgYJDgAAAA==.Mizu:BAAALgADCgcJDgAAAA==.',
Mo='Moadeed:BAAALgAECgUJBQAAAA==.Moisthealz:BAABLgAECn8UAAIJAAgJ1BVwIgAQAgAJAAgJ1BVwIgAQAgAAAA==.Mooluv:BAAALgADCgcJBwAAAA==.Moonstrike:BAAALgADCgcJCAAAAA==.Mortesque:BAAALgAECgcJDAAAAA==.',
Mu='Muttblitzed:BAAALgADCgIJAgAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAAALgAECgUJCgAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Nausican:BAAALgAECgYJEAAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAAALgAECggJEAAAAA==.Necrotherys:BAAALgAECgYJDQAAAA==.Nelandra:BAAALgAECgIJAgAAAA==.',
Ni='Nicklaus:BAAALgAECgUJCgAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgMJBgAAAA==.Ninjadk:BAEBLgAECn8cAAMRAAYJRiVLNQBhAgARAAYJRiVLNQBhAgAXAAEJqhulBwBUAAAAAA==.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAECggJFgAbAPsUAA==.Nomahuata:BAABLgAECn8dAAIcAAcJvRG3DgAZAQAcAAcJvRG3DgAZAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyxi:BAAALgAECgIJAgAAAA==.',
['Né']='Néo:BAAALgADCgIJAgAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAAALgAECgUJEAABLgAECggJDwAGAAAAAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgcJDQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgADCgcJBwAAAA==.Palanas:BAAALgAECgcJDwAAAA==.Palochka:BAAALgADCgkJFgAAAA==.Paradots:BAABLgAECn8WAAIaAAYJtRoTAwDJAQAaAAYJtRoTAwDJAQABLgADCgYJBgAGAAAAAA==.Paranitis:BAAALgAECgQJBAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQAAAA==.',
Pe='Petronella:BAABLgAECn8bAAMdAAgJFgifFABeAQAdAAgJFgifFABeAQAeAAQJ+wNMgwCxAAAAAA==.Pezmage:BAAALgAECgEJAQAAAA==.',
Ph='Phatboi:BAAALgADCgIJAwAAAA==.',
Pi='Pixystix:BAAALgAECgIJAgAAAA==.',
Po='Poisonspain:BAAALgADCgIJAgAAAA==.Potscold:BAACLgAFFH8JAAILAAUJ5hhyDAC5AQALAAUJ5hhyDAC5AQAuAAQKfzIAAgsACAk5I7URAD0DAAsACAk5I7URAD0DAAAA.Poxi:BAAALgAECgIJAgABLgAECggJFgAbAA0XAA==.',
Pr='Prion:BAAALgAECgQJDwAAAA==.',
Pu='Pull:BAABLgAECn8VAAIKAAYJsRuqDQCqAQAKAAYJsRuqDQCqAQAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgYJDAAAAA==.Raega:BAAALgADCggJCAAAAA==.Raenar:BAAALgADCgMJAwAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAAALgAECgIJAgAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgADCgkJFAAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAAALgAECgYJDgAAAA==.Reliala:BAAALgADCgMJAwAAAA==.Relluth:BAAALgAECgQJBAAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECgYJBgAAAA==.Resles:BAAALgADCgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAGAAAAAA==.',
Rh='Rhobes:BAAALgADCggJDQAAAA==.Rhondta:BAAALgAECgYJEAAAAA==.',
Ri='Rictus:BAABLgAECn8XAAILAAgJfR46BgBLAgALAAgJfR46BgBLAgAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAAALgAECgYJDAAAAA==.',
Ro='Roades:BAAALgADCgcJCAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgADCggJGgABLgAECgQJBAAGAAAAAA==.Rurry:BAACLgAFFH8SAAIaAAUJsRrQAQCZAQAaAAUJsRrQAQCZAQAuAAQKfyYABBoACQkeILMCAEEDABoACQkeILMCAEEDAA8ABQm6GRMWAI8BABsAAwnXFOZGAL8AAAAA.',
Ry='Ryumi:BAABLgAECn8bAAIHAAgJxxxWBABMAgAHAAgJxxxWBABMAgAAAA==.Ryur:BAAALgAECgQJBQAAAA==.',
Sa='Sabastion:BAAALgADCgIJAgABLgAECgQJBAAGAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECgYJDgAGAAAAAA==.Salocar:BAAALgAECgYJDAAAAA==.Sanafela:BAAALgADCggJFwAAAA==.Saphisha:BAAALgAECgYJCwAAAA==.Sasora:BAAALgAECgUJCgAAAA==.Saucemagic:BAAALgAECgYJBwAAAA==.Savonah:BAAALgADCggJFwAAAA==.',
Sc='Scalespawn:BAAALgADCgYJBgABLgAFFAUJCQARAJoPAA==.Scaryl:BAAALgADCgkJFQAAAA==.Scourgespawn:BAACLgAFFH8JAAMRAAUJmg8jIwAKAQARAAQJmg8jIwAKAQAfAAEJAACRDAAAAAAuAAQKfx0AAhEACQmPGzAkAK0CABEACQmPGzAkAK0CAAAA.',
Se='Sengoku:BAAALgADCggJCQAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shalis:BAAALgAECgYJEAAAAA==.Sharivee:BAAALgAECgUJCgAAAA==.Sharko:BAABLgAECn8WAAMDAAcJzBWODwDMAQADAAcJzBWODwDMAQAWAAIJwgN3iwBPAAAAAA==.Shibui:BAABLgAECn8cAAMTAAgJARIdGgDyAQATAAgJARIdGgDyAQAHAAYJUgUWowDNAAAAAA==.Shiggles:BAAALgADCgcJBwAAAA==.Shinhaein:BAAALgAECgYJBwABLgAECggJHQARAG8hAA==.Shockazilla:BAABLgAECn8bAAMWAAgJkBvHEACMAgAWAAgJkBvHEACMAgAFAAMJVw+d/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgADCgcJCAAAAA==.',
Si='Sigh:BAAALgAECgQJBwAAAA==.Silverhorn:BAAALgAECgQJCAAAAA==.',
Sk='Skoduh:BAAALgAECgQJCgAAAA==.Skyelene:BAABLgAECn8UAAMcAAYJCg+uQwA6AQAcAAYJCg+uQwA6AQAJAAIJ0gWcJwBSAAAAAA==.',
Sl='Slaanesh:BAAALgAECgMJBgAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgRbEwAHAQACAAQJhgRbEwAHAQAuAAQKfyIAAwIACAkLGS8cAEMCAAIACAnYGC8cAEMCAAQABAmEDTOaAJ8AAAAA.',
Sm='Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgIJAwAAAA==.Soraka:BAAALgAFFAIJAgAAAA==.',
Sp='Spiralist:BAAALgAECgYJEAAAAA==.',
St='Starge:BAAALgAECgQJBAAAAA==.Stonedalways:BAAALgAECgMJAwAAAA==.',
Su='Sunfuri:BAABLgAECn8dAAIeAAYJfQbRFAD2AAAeAAYJfQbRFAD2AAAAAA==.Sunjan:BAAALgADCgUJBwAAAA==.Sus:BAACLgAFFH8OAAITAAUJphuTAgBlAQATAAUJphuTAgBlAQAuAAQKfyAAAhMACQk2H5UDAEcDABMACQk2H5UDAEcDAAAA.Susanoo:BAAALgAECgYJDgAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAAALgAECgMJCQAAAA==.Takeko:BAAALgADCgcJDgABLgAECgIJAgAGAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJCgAAAA==.Taranad:BAAALgAECgQJBQAAAA==.Tarathor:BAAALgAECgIJAgAAAA==.Tauroctony:BAAALgAECgcJEAAAAA==.',
Te='Tea:BAAALgADCgkJCgABLgAECggJHAAIAOoJAA==.Teknofarious:BAAALgAECgEJAQAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgADCggJDgABLgAECggJHAABABIVAA==.Thesafe:BAAALgAECgIJAgAAAA==.Thialia:BAAALgAECgEJAQAAAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn8dAAIgAAYJISMrAgBMAgAgAAYJISMrAgBMAgAAAA==.',
To='Torrey:BAABLgAECn8XAAIWAAgJHiXeAADkAgAWAAgJHiXeAADkAgAAAA==.',
Tr='Trix:BAABLgAECn8dAAIJAAYJhA3HEwAVAQAJAAYJhA3HEwAVAQAAAA==.',
Tu='Tulsi:BAABLgAECn8WAAIhAAcJwSCBAABLAgAhAAcJwSCBAABLAgAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgADCgIJAgAAAA==.Tyronos:BAAALgAECgYJEAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Vaelara:BAABLgAECn8hAAIHAAgJ0xyGBQAqAgAHAAgJ0xyGBQAqAgAAAA==.Valdr:BAAALgAECgYJEAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIQAHANMcAA==.Vas:BAAALgADCgUJCwAAAA==.',
Ve='Velielina:BAAALgADCgQJBAAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vevicenth:BAAALgADCggJFgAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8PAAILAAUJch1RCgDMAQALAAUJch1RCgDMAQAuAAQKfxkAAwsACAkbJLghAOwCAAsACAkbJLghAOwCABgAAgl2FLUTAIoAAAAA.',
Wh='Whakan:BAAALgADCggJFwABLgAECgUJCgAGAAAAAA==.',
Wt='Wtfox:BAEALgAECgQJBwABLgAECgYJDwAGAAAAAA==.',
Wy='Wysteri:BAAALgAECgEJAQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgIJAgAAAA==.Xalatos:BAAALgADCgEJAQAAAA==.Xalfein:BAAALgADCggJEAAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECggJHAAEADsbAA==.',
Ya='Yanakana:BAAALgADCgkJHQAAAA==.',
Yd='Ydalise:BAAALgADCgEJAQAAAA==.Ydrassil:BAAALgADCgYJBwABLgAECgUJBwAGAAAAAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgMJBAAAAA==.Zatriani:BAAALgAECgQJBAAAAA==.',
Ze='Zenus:BAAALgAECgYJEgAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAAALgADCgQJBAAAAA==.Zeusinator:BAAALgAECgYJCgAAAA==.',
Zi='Zinu:BAABLgAECn8cAAIEAAgJOxspFwB/AgAEAAgJOxspFwB/AgAAAA==.Zivalisse:BAAALgAECgQJBAAAAA==.',
Zu='Zulfionn:BAAALgAECgUJCAAAAA==.',
['Áy']='Áyrá:BAAALgAECgYJEAAAAA==.',
['Åp']='Åpollyon:BAAALgAECgIJAgAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8XAAMPAAYJ5hpyFAChAQAPAAYJ5hpyFAChAQAbAAMJ4hd9RQDHAAAAAA==.',
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

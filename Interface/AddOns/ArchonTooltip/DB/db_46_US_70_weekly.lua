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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','DemonHunter-Havoc','Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Warlock-Demonology','Priest-Holy','Priest-Discipline','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Protection','Monk-Brewmaster','Paladin-Retribution','Druid-Restoration','Druid-Balance','Druid-Feral','Paladin-Holy','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Rogue-Assassination','Evoker-Devastation','Monk-Windwalker','Warlock-Affliction','Priest-Shadow','Hunter-Marksmanship','Mage-Arcane','Warlock-Destruction','Monk-Mistweaver','Shaman-Elemental','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.',
Ae='Aegon:BAABLgAECn8ZAAMBAAkJ2xLlNAClAQABAAkJ2xLlNAClAQACAAEJ8QCYUAASAAAAAA==.Aesthelian:BAAALgADCgkJDAAAAA==.Aesthelyan:BAABLgAECn8bAAIDAAcJvR9jHwAuAgADAAcJvR9jHwAuAgAAAA==.',
Ag='Agnia:BAAALgAECgYJDQAAAA==.',
Ah='Ahnerfays:BAAALgAFFAEJAQAAAA==.',
Ai='Aindriana:BAABLgAECn8gAAIEAAcJCgdnGwAAAQAEAAcJCgdnGwAAAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgIJAgABLgAECggJGwAFAD4PAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgYJBwABLgAECgkJMgAGAG0PAA==.Alestiana:BAABLgAECn8kAAIHAAgJvBKTHgC9AQAHAAgJvBKTHgC9AQAAAA==.Alkyria:BAABLgAECn8WAAIIAAYJKCCHCgDGAQAIAAYJKCCHCgDGAQAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBAAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBAAJAAAAAA==.',
Am='Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJBgABLgAECggJJAAKAH0eAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8OAAIHAAUJ8xmECgB6AQAHAAUJ8xmECgB6AQAuAAQKfyQAAgcACAnpH+EVAGYCAAcACAnpH+EVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgYJEAAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgcJEwAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECggJLgACACAhAA==.Apox:BAAALgADCgEJAQAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8hAAMLAAgJhiGTBADIAgALAAcJnCOTBADIAgAMAAQJ0BRTIwAPAQAAAA==.Arbrerahis:BAAALgADCgYJBQAAAA==.Arcaneisbad:BAAALgAECgQJDwABLgAFFAEJAQAJAAAAAA==.Areaman:BAAALgAECgIJAgABLgAECgYJFwADANIcAA==.Arkterris:BAAALgADCgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMNAAQJPw/CAgArAQANAAQJMw3CAgArAQABAAIJ1wm7RQCYAAAuAAQKfxYAAwEACQl0IEorAIwCAAEACAmnIEorAIwCAA0AAQkQH0ASAFsAAAAA.Artemisixion:BAAALgADCgYJBwAAAA==.Artemisomega:BAABLgAECn8XAAIOAAcJnBv5HwDIAQAOAAcJnBv5HwDIAQABLgADCgYJBwAJAAAAAA==.Arthillius:BAAALgAECgYJEAAAAA==.',
As='Asharà:BAAALgAECgQJBAAAAA==.Ashime:BAABLgAECn8ZAAIPAAcJXhzABwDXAQAPAAcJXhzABwDXAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECggJFwAHAAckAA==.',
Au='Augwater:BAAALgADCgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAAALgAECgYJDwAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECggJJQAQAJ8iAA==.Aviana:BAAALgADCgYJBgAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECggJJQAQAJ8iAA==.',
Ay='Ayothin:BAABLgAECn8rAAIRAAgJaBq0IAAGAgARAAgJaBq0IAAGAgAAAA==.',
Az='Azazall:BAAALgADCgIJAgAAAA==.Azerphale:BAAALgAECgMJBQAAAA==.Azura:BAAALgADCgIJAgAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8hAAQSAAkJXhi2LAD8AQASAAkJXhi2LAD8AQATAAEJBwr7WwAtAAAUAAEJAAbsNwAoAAABLgAECgYJFgAVADIJAA==.',
Be='Beefe:BAAALgAECgQJBwABLgAECgYJDgAJAAAAAA==.Beerntotems:BAAALgADCgQJBAAAAA==.Beldar:BAABLgAECn8aAAIWAAgJGw6FEgCLAQAWAAgJGw6FEgCLAQAAAA==.Benchpress:BAAALgAECgMJAwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bip:BAAALgAECgYJCAAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgADCggJEAABLgAECgcJGAASANkNAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzdk:BAAALgAECgYJBgABLgAECgcJEgAJAAAAAA==.Blitzlock:BAAALgADCgIJAgABLgAECgcJEgAJAAAAAA==.Blitzy:BAAALgAECgcJEgAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECgQJBQAAAA==.',
Br='Brearan:BAAALgADCgIJAgABLgAECgMJAwAJAAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn8lAAIXAAgJ3AWAJwA7AQAXAAgJ3AWAJwA7AQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAAALgAECgYJEAAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgMJAwAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8ZAAIXAAgJnQkEIABsAQAXAAgJnQkEIABsAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAABLgAECn8XAAIYAAYJChYkHwBGAQAYAAYJChYkHwBGAQAAAA==.Bursk:BAAALgADCgIJAgAAAA==.',
By='Byrum:BAABLgAECn8UAAIZAAcJSAS7EAACAQAZAAcJSAS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECgcJDQAJAAAAAA==.',
Ca='Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgADCgIJAgAAAA==.Canabull:BAAALgADCgUJCAAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAQAAAA==.Carion:BAABLgAECn8nAAIDAAkJhhmKKgDIAgADAAkJhhmKKgDIAgAAAA==.',
Ce='Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgADCgcJDQAAAA==.Cemeteri:BAAALgAECgIJAgAAAA==.',
Ch='Chaingun:BAAALgAECggJEgAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chilblain:BAABLgAECn8WAAIDAAcJTAuiYQBOAQADAAcJTAuiYQBOAQAAAA==.Chilchizedek:BAAALgAECgMJAwAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.',
Ci='Cibochevski:BAAALgAECgIJAgABLgAECgYJFwAIAGYeAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIaAAkJMQ5NBQCNAQAaAAkJMQ5NBQCNAQAAAA==.Citrus:BAABLgAECn8WAAIHAAcJCSNcGABTAgAHAAcJCSNcGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgQJBAABLgAECgYJDgAJAAAAAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgAAAA==.Closetfurry:BAAALgAECgUJEwAAAA==.',
Co='Codenheimer:BAABLgAECn8ZAAITAAcJugklLQDiAAATAAcJugklLQDiAAAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCAAAAA==.Corrinne:BAAALgAECgIJAgABLgAECgcJFgAIAOQOAA==.Corvast:BAAALgAECgEJAQABLgAECggJGwAFAD4PAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJAwABLgAECgYJDgAJAAAAAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgQJBQAAAA==.',
Da='Daeshan:BAABLgAECn8WAAIbAAcJDhxeDADzAQAbAAcJDhxeDADzAQAAAA==.Dahmage:BAAALgADCgUJCAAAAA==.Daldolarette:BAABLgAECn8jAAIVAAkJbRcqDwAoAgAVAAkJbRcqDwAoAgAAAA==.Daradevil:BAAALgAECgMJAwAAAA==.Daralune:BAAALgAECgcJEgAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAAALgAECgMJBQAAAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFgAAAA==.Darkkef:BAAALgAECgQJEAAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgADCgkJHAAAAA==.Dawg:BAAALgAECgYJCgAAAA==.Days:BAAALgAECgMJBgAAAA==.',
De='Deadtotem:BAAALgADCgIJAgABLgAFFAMJCAAVAJMOAA==.Deamonite:BAAALgAECgYJEwAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAOABAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonstein:BAEALgAECgMJAwABLgAFFAYJGgARADQhAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn8dAAISAAgJ4AXZQQAMAQASAAgJ4AXZQQAMAQAAAA==.Deystin:BAAALgADCggJCAAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAAJAAAAAA==.Drucy:BAABLgAECn8ZAAIHAAYJgBUvLABnAQAHAAYJgBUvLABnAQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgADCgYJBgAAAA==.Dryageribeye:BAABLgAECn8aAAIBAAkJRhp7OACXAQABAAkJRhp7OACXAQAAAA==.Drzip:BAAALgADCgkJGQAAAA==.Drzippy:BAAALgADCgkJGwAAAA==.',
Du='Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8cAAIBAAgJCQTSYgAeAQABAAgJCQTSYgAeAQAAAA==.Duyii:BAAALgAECgYJDQABLgAECgcJEQAJAAAAAQ==.',
Dy='Dyanthus:BAAALgAECgEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgIJAgAAAA==.',
Ec='Ech:BAAALgAECgcJDQAAAA==.Ecology:BAAALgADCgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJMwAAAA==.Elendirs:BAAALgADCgYJCQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn8oAAMNAAkJ+xS7BQDWAQANAAkJ+xS7BQDWAQABAAEJBQppKQEsAAAAAA==.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8VAAMcAAgJ8QZnCQD/AAAcAAcJQgdnCQD/AAAKAAMJ5gKZrwBjAAAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8aAAIWAAgJCRoeCAAmAgAWAAgJCRoeCAAmAgAAAA==.',
Fa='Fanceedas:BAAALgAECgYJEAAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAECgEJAQAAAA==.Fave:BAAALgAECgQJBAABLgAECgQJCQAJAAAAAA==.',
Fe='Feannesse:BAAALgAECgYJDgAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAAALgAECgQJCQAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAAJAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgcJHAASABEgAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8gAAIRAAcJWQoUWgA8AQARAAcJWQoUWgA8AQAAAA==.Frostbringer:BAAALgADCgEJAQAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgAECgEJAQABLgAECgIJAwAJAAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgIJAwAJAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNhXRZgAJAgADAAkJNhXRZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECgQJBAAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAAALgAECggJEwAAAA==.Garekk:BAAALgAECgcJEgAAAA==.',
Gh='Ghomy:BAAALgAECgMJBQAAAA==.Ghun:BAABLgAECn8QAAMcAAcJPgaDEgAEAQAcAAUJ3QeDEgAEAQAKAAMJAQPjwQBIAAAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8IAAIBAAQJSBHgKwDsAAABAAQJSBHgKwDsAAAuAAQKfykAAgEACAnWHQYwAHgCAAEACAnWHQYwAHgCAAAA.Gilmore:BAAALgADCgkJEQAAAA==.Giozzef:BAAALgADCgUJBQABLgAECgYJFwADANIcAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJAwAAAA==.Goneville:BAAALgAECgYJEQAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8hAAIRAAgJSyM6CgC2AgARAAgJSyM6CgC2AgAAAA==.',
Gu='Guias:BAAALgADCgkJHwAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAAALgAECgYJEAAAAA==.',
Ha='Hairykrishna:BAABLgAECn8hAAIKAAcJiBssIgDlAQAKAAcJiBssIgDlAQAAAA==.Haldevarik:BAAALgAECgQJDQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn8XAAIVAAYJRxspFwDUAQAVAAYJRxspFwDUAQAAAA==.Hamur:BAABLgAECn8eAAQdAAcJgAksJQAaAQAdAAcJgAksJQAaAQAMAAYJhgZJJAAIAQALAAUJrQk5VADmAAAAAA==.Happysummon:BAABLgAECn8ZAAIKAAgJZR+BGAAeAgAKAAgJZR+BGAAeAgAAAA==.Hargrave:BAAALgADCgMJBwAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAABLgAECn8XAAIbAAYJRA/lJAAEAQAbAAYJRA/lJAAEAQAAAA==.Hate:BAAALgADCgYJBgAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMBAAcJNBDQVgA6AQABAAcJJQnQVgA6AQANAAUJPRM+CgArAQAAAA==.Heavywinner:BAABLgAECn8cAAITAAkJvRsCDgC8AgATAAkJvRsCDgC8AgAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hu='Hughmann:BAABLgAECn8UAAMIAAYJmwhjHQDRAAAIAAYJmwhjHQDRAAAFAAEJ0QOOSAAkAAAAAA==.',
['Hâ']='Hârlot:BAAALgADCgcJCQAAAA==.',
Ia='Iambrewt:BAAALgADCggJCAABLgAECggJEAAJAAAAAA==.',
Id='Idamage:BAAALgAECgcJCQAAAA==.',
Ig='Igetmoney:BAAALgAECgUJCAAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAECgQJBwABLgAFFAEJAQAJAAAAAA==.Imdaboss:BAAALgADCgYJBgAAAA==.Imgnnatchyou:BAAALgAECgUJBgAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAAALgAECgQJBwAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBQAAAA==.',
Iv='Ivebadbreath:BAAALgADCgIJAgAAAA==.',
Ja='Jadeth:BAAALgAECgYJCgAAAA==.Jaestra:BAAALgADCgUJCwABLgAECgYJFwALAPkhAA==.Jaidah:BAAALgAECgMJBAAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQAAAA==.Jansôlo:BAABLgAECn8ZAAMWAAcJQh5LCwDwAQAeAAYJgB3JIgAQAgAWAAcJxxlLCwDwAQAAAA==.Jaratri:BAABLgAECn8mAAIWAAkJqh36BQCnAgAWAAkJqh36BQCnAgAAAA==.Jaug:BAAALgAECgMJCAAAAA==.',
Je='Jenton:BAABLgAECn8cAAIDAAgJsgfKYwBKAQADAAgJsgfKYwBKAQAAAA==.Jeric:BAABLgAECn8ZAAIDAAcJHxFuUwBxAQADAAcJHxFuUwBxAQAAAA==.',
Jo='Jobomage:BAAALgAECgUJCgAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8kAAIGAAkJ1hZ/GAANAgAGAAkJ1hZ/GAANAgAAAA==.',
Ju='Juicydrucy:BAAALgADCggJCAAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAAALgAECggJEwAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMfAAkJPx2sAQCuAgAfAAkJPx2sAQCuAgADAAMJRQ9MRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kaneki:BAABLgAECn8YAAIBAAcJjCA3GgAtAgABAAcJjCA3GgAtAgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8WAAIRAAkJWRGYkwBVAQARAAkJWRGYkwBVAQAAAA==.Karmai:BAAALgAECgIJBQABLgAECgMJCAAJAAAAAA==.Kastandmixer:BAAALgAECggJEQAAAA==.Kathine:BAAALgAECgMJAwAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgADCgcJFAAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kelandor:BAAALgAECgIJAgAAAA==.Kelwynd:BAABLgAECn8WAAIeAAYJJR9bBgCzAQAeAAYJJR9bBgCzAQAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAAALgAECgUJCwAAAA==.Kezak:BAAALgAECgIJBgABLgAECgYJDgAJAAAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAAALgAECgcJEAAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMYAAkJswRGMwAxAQAYAAkJswRGMwAxAQAaAAEJKgEjRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJCQAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAAALgAECgUJCQAAAA==.Kodera:BAABLgAECn8eAAMYAAkJuxBcGwDuAQAYAAkJuxBcGwDuAQAaAAEJ2wFpRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECgcJEQAJAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgMJAwABLgAECggJIQAHAOMOAA==.Kryssie:BAABLgAECn8kAAIGAAkJ8BaOEwA0AgAGAAkJ8BaOEwA0AgAAAA==.',
Ku='Kungfushammy:BAAALgAECgYJBwABLgAECgcJHQAgAJMPAA==.Kurkan:BAAALgAECgcJEQAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAABLgAECn8jAAIhAAgJZwmPIQA5AQAhAAgJZwmPIQA5AQAAAA==.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJFgARAFkRAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8gAAMQAAkJ1hlLEQCMAgAQAAkJTxhLEQCMAgAbAAMJeBVtMQC/AAAAAA==.Lanaya:BAAALgAECgYJBgAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJBwAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8QAAIdAAQJJBpMCABjAQAdAAQJJBpMCABjAQAuAAQKfx8AAh0ACAlPHeoMALUCAB0ACAlPHeoMALUCAAAA.Laulon:BAAALgADCgYJBgABLgAECgcJEQAJAAAAAQ==.Lawrensce:BAAALgADCgkJFQAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgcJFgAHAAkjAA==.Lencho:BAABLgAECn8eAAIXAAgJ4wyNGgCTAQAXAAgJ4wyNGgCTAQAAAA==.Lenian:BAABLgAECn8XAAIIAAYJZh5gCwCzAQAIAAYJZh5gCwCzAQAAAA==.Lexida:BAAALgAECgYJEAAAAA==.',
Li='Lightmonarch:BAAALgADCgcJDQAAAA==.Litesout:BAABLgAECn8YAAMFAAcJaxDtEgAoAQAXAAcJ8wtGJgBCAQAFAAYJUhHtEgAoAQAAAA==.',
Ll='Llanadia:BAAALgAECgEJAQAAAA==.',
Lo='Loreck:BAAALgAECgMJAwAAAA==.Loredaryn:BAABLgAECn8dAAIgAAcJthQeCQBGAQAgAAcJthQeCQBGAQAAAA==.Lorra:BAAALgADCgYJBgAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8bAAIFAAgJPg8FEgCBAQAFAAgJPg8FEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgMJAwAAAA==.',
Ma='Mack:BAAALgAECgcJBQAAAA==.Madliblol:BAAALgADCgUJCAAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgADCgkJDAAAAA==.Magebou:BAAALgAECggJDAAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAABLgAECn8uAAIGAAgJoR0fFQCOAgAGAAgJoR0fFQCOAgAAAA==.Maiganoss:BAAALgAECgYJEgAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgYJDgAJAAAAAA==.Maxpurpz:BAAALgADCgYJBgAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgEJAQAAAA==.Mestopheles:BAAALgAECggJEgAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAAALgAECgcJDwAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECggJEwAJAAAAAA==.Morcathord:BAAALgADCgkJCgABLgAECgcJEQAJAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgADCggJCQAAAA==.',
Mw='Mwane:BAAALgAECgIJBAAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgMJAwAAAA==.',
Na='Nainel:BAAALgADCgUJCwABLgAECgYJFwAIAGYeAA==.Nakros:BAABLgAECn8bAAIRAAcJ8xSFbwCdAQARAAcJ8xSFbwCdAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIVAAcJYRI/OACZAQAVAAcJYRI/OACZAQABLgADCgYJBgAJAAAAAA==.',
Ni='Nianna:BAAALgAECgUJCwAAAA==.Nickto:BAAALgAECgQJBAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Ny='Nymn:BAAALgAECgUJBwABLgAECggJGwAFAD4PAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Og='Ogbruced:BAABLgAECn8YAAISAAcJ2Q1dNwA5AQASAAcJ2Q1dNwA5AQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8WAAIHAAYJWyKTEQAtAgAHAAYJWyKTEQAtAgAAAA==.',
Or='Orcrest:BAAALgAECgYJDwAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn8bAAIiAAYJ+xYQHwBVAQAiAAYJ+xYQHwBVAQAAAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECgcJDwAAAA==.Paryah:BAABLgAECn8XAAMjAAYJRwRPIgDoAAAjAAYJQgRPIgDoAAAZAAQJugJqFQCkAAAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMOAAkJEB5iDgBVAgAOAAkJEB5iDgBVAgAkAAIJhRYrIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgQJBAAAAA==.Phréek:BAABLgAECn8ZAAQRAAYJtB2JOwCTAQARAAYJtB2JOwCTAQAVAAMJ2hOGawDMAAAPAAIJnxAiNwBmAAAAAA==.',
Pi='Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAABLgAECn8iAAICAAkJph1TCACfAgACAAkJph1TCACfAgABLgAFFAQJBgAPAEEXAA==.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgMJAwAAAA==.Praze:BAAALgAECgYJDwAAAA==.Priority:BAABLgAECn8gAAIDAAYJKx+6NQDLAQADAAYJKx+6NQDLAQAAAA==.Professorodd:BAABLgAECn8kAAIDAAgJrhkJRABsAgADAAgJrhkJRABsAgABLgAFFAUJDgASAAIPAA==.Prophet:BAAALgAECgMJCAAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECgMJAwAJAAAAAA==.',
Ra='Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgADCgYJCgAAAA==.Rahis:BAABLgAECn8sAAMGAAkJCRYWEwA4AgAGAAkJCRYWEwA4AgAeAAEJtgNllAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn8XAAMHAAYJmwtlQgD5AAAHAAYJmwtlQgD5AAAiAAEJigkwbAAqAAAAAA==.Ramsis:BAABLgAECn8eAAIHAAkJtQdZRgBoAQAHAAkJtQdZRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIdAAkJpwqdIwC7AQAdAAkJpwqdIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJBwAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgMJAwAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAAALgAECggJEAAAAA==.Red:BAABLgAECn8dAAIWAAYJPwvTHgAKAQAWAAYJPwvTHgAKAQAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgIJAgAAAA==.Redtwinkies:BAAALgAECgQJBwAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgADCggJEQABLgAECgcJEQAJAAAAAQ==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJCAAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAAALgAECgcJEwAAAA==.Robokage:BAAALgADCggJFwABLgAECgcJHgARAMsWAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgQJCQAAAA==.Romokhar:BAAALgAECgYJDwAAAA==.Ronyar:BAAALgAECggJEgABLgAFFAYJEwAVAP4ZAA==.',
Ru='Rudef:BAABLgAECn8aAAIHAAkJbRWKIgAPAgAHAAkJbRWKIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgUJBQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECgcJEQAJAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgADCgkJHAAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgMJAwAAAA==.Seret:BAABLgAECn8pAAIdAAkJBxgoCQAzAgAdAAkJBxgoCQAzAgAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn8XAAIKAAYJsBD/VwAlAQAKAAYJsBD/VwAlAQAAAA==.Shammbo:BAAALgAECgYJEQAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMLAAkJ7x3rFgAkAgALAAkJ7x3rFgAkAgAdAAgJtAglGwBiAQAAAA==.Shiyn:BAAALgADCgUJCAABLgAECgYJFwAjAEcEAA==.Shupala:BAAALgAECgQJBwAAAA==.',
Si='Sicnus:BAAALgAECgYJEgAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgYJFgAIACggAA==.Sinadin:BAAALgAECgQJBAAAAA==.Sindoreisins:BAAALgAECgUJBQAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn8lAAIQAAgJnyIBBACzAgAQAAgJnyIBBACzAgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgADCgcJDwAAAA==.Sourkeys:BAAALgAECgQJBQAAAA==.Southsound:BAAALgAECgEJAgABLgAECgYJDgAJAAAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Steakknife:BAABLgAECn8nAAIjAAkJshegBQBgAgAjAAkJshegBQBgAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Superrad:BAAALgADCgYJBgAAAA==.',
Sv='Svlla:BAAALgAECgQJBAAAAA==.',
Sy='Sybil:BAACLgAFFH8OAAITAAUJHBQdEQAtAQATAAUJHBQdEQAtAQAuAAQKfyMAAhMABwkMHhYZAD4CABMABwkMHhYZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgQJAwABLgAECgUJCAAJAAAAAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgMJBAAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgADCgMJAwAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECgcJEQAJAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Telysse:BAAALgAECgcJDQAAAA==.Tenma:BAAALgAECgMJAwABLgAECgcJEwAJAAAAAA==.Teo:BAAALgAECgQJCgAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECgcJDQAJAAAAAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgQJCQAJAAAAAA==.Thehunted:BAAALgAECgYJCwAAAA==.Thelock:BAABLgAECn8dAAIHAAkJ/xgUEgCFAgAHAAkJ/xgUEgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAABLgAFFH8OAAISAAUJAg9ZDgBmAQASAAUJAg9ZDgBmAQAAAA==.Thien:BAAALgAECgEJAQAAAA==.Thundertwig:BAABLgAECn8oAAIMAAgJ7wUmHABMAQAMAAgJ7wUmHABMAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAOABAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8WAAIIAAcJ5A4WEwA2AQAIAAcJ5A4WEwA2AQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgUJBwABLgAECggJJAAKAH0eAA==.Tofulhundun:BAABLgAECn8kAAIiAAgJ4AMRLgD9AAAiAAgJ4AMRLgD9AAAAAA==.Toothpick:BAAALgAECgQJDAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgMJAwAAAA==.Treehaus:BAABLgAECn8WAAISAAcJBQmkRAAAAQASAAcJBQmkRAAAAQAAAA==.Triannah:BAAALgAECgYJDAAAAA==.Trildjr:BAABLgAECn8cAAIGAAgJJhFYKQCsAQAGAAgJJhFYKQCsAQAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgADCgIJAgAAAA==.',
Tu='Tuldag:BAABLgAECn8ZAAIiAAcJTwdPLwD3AAAiAAcJTwdPLwD3AAAAAA==.',
Ty='Tyrse:BAAALgAECgMJBwAAAA==.',
Tz='Tzerina:BAABLgAECn8aAAIEAAcJtA8mFABMAQAEAAcJtA8mFABMAQAAAA==.',
Um='Umbrawing:BAAALgADCgkJCQABLgAECgkJIAAkAHgkAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECgcJEQAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn8aAAIVAAgJ0BG8HwCJAQAVAAgJ0BG8HwCJAQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8SAAQOAAYJrhYKQQA2AQAOAAYJuxQKQQA2AQAkAAQJThFhGQDOAAAEAAIJIRktNwBKAAAAAA==.Valkriss:BAAALgADCgUJCAAAAA==.Vallak:BAABLgAECn8cAAIUAAcJPhg5CACsAQAUAAcJPhg5CACsAQAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn8lAAIlAAgJLh5vAwBbAgAlAAgJLh5vAwBbAgAAAA==.Valth:BAAALgAECgYJCwAAAA==.Valtonka:BAAALgADCgUJCQAAAA==.Vanae:BAAALgAECgUJDAAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJBgAAAA==.Varaella:BAAALgADCgcJDAAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgADCgEJAQAAAA==.',
Ve='Vecna:BAAALgAECgMJBgAAAA==.Velendez:BAAALgAECgYJDwAAAA==.Veleria:BAABLgAECn8WAAMVAAYJMgm9MgAFAQAVAAYJMgm9MgAFAQARAAYJfgqKdAADAQAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8YAAIdAAcJlg3SHgBGAQAdAAcJlg3SHgBGAQAAAA==.Versatina:BAAALgAECgYJDwAAAA==.Vexizz:BAABLgAECn8UAAIjAAcJtw6cEwB3AQAjAAcJtw6cEwB3AQAAAA==.',
Vi='Victra:BAABLgAECn8cAAILAAgJhBQcGwByAQALAAgJhBQcGwByAQAAAA==.Viko:BAABLgAECn8WAAIiAAcJcQqIKwAKAQAiAAcJcQqIKwAKAQAAAA==.Vinaya:BAAALgAECgYJDwAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgEJAQAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAAALgAECgYJDwAAAA==.',
Vu='Vulpy:BAAALgADCgIJAgAAAA==.',
Wa='Wandersong:BAAALgAECgQJCgAAAA==.Wardudeman:BAAALgAECgUJEgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwAJAAAAAA==.Watsuki:BAAALgAECgIJAgABLgAECgYJFwAYAAoWAA==.',
We='Weoo:BAAALgAECgYJDQAAAA==.Werrick:BAABLgAECn8oAAIRAAgJ/QptUABVAQARAAgJ/QptUABVAQAAAA==.',
Wh='Whitespot:BAAALgAECgEJAQAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgYJFwADANIcAA==.',
Wo='Woblatus:BAAALgAECgcJEQABLgAECgcJEQAJAAAAAQ==.',
Wr='Wreckreation:BAAALgAECgYJDgAAAA==.',
Wy='Wylectra:BAABLgAECn8WAAMLAAcJhhEjGwByAQALAAcJIhEjGwByAQAMAAMJDQq8RACSAAAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8lAAIDAAcJoh5FKwD1AQADAAcJoh5FKwD1AQAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgADCgkJCQABLgAECgUJEgAJAAAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgEJAQAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAAALgAECgYJCAAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJCAAJAAAAAA==.',
Za='Zagasham:BAABLgAECn8ZAAIHAAgJGhiiHwAhAgAHAAgJGhiiHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAAALgAECgYJEgAAAA==.Zamari:BAAALgADCgUJCwABLgAECgYJEgAJAAAAAA==.Zaphiell:BAABLgAECn8VAAMMAAgJVxX+CwARAgAMAAgJVxX+CwARAgAdAAEJsAIoVwAsAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIXAAkJOArpIgBYAQAXAAkJOArpIgBYAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgADCgkJCQAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zev:BAAALgAECgYJDwAAAA==.',
Zi='Zilli:BAAALgAECgYJEAAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECgcJEQAJAAAAAQ==.',
Zo='Zoeystorm:BAAALgADCgkJFQAAAA==.Zoltraak:BAAALgAECgYJDgAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn8iAAIZAAgJkwurBgCAAQAZAAgJkwurBgCAAQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8dAAQgAAcJkw+ACQA/AQAgAAcJkw+ACQA/AQAKAAUJQgiF5gCOAAAcAAEJhgFmOAAXAAAAAA==.',
['Är']='Ärgo:BAABLgAECn8eAAIXAAgJ/Q98FwCrAQAXAAgJ/Q98FwCrAQAAAA==.',
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

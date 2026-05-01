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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Paladin-Protection','Monk-Brewmaster','Paladin-Retribution','Druid-Restoration','Druid-Balance','Druid-Feral','Hunter-Survival','Warrior-Fury','Mage-Frost','Evoker-Devastation','DemonHunter-Devourer','Warlock-Affliction','Warlock-Demonology','Priest-Shadow','Mage-Arcane','Evoker-Augmentation','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Shaman-Elemental','DemonHunter-Vengeance','Hunter-Marksmanship','Druid-Guardian','Rogue-Assassination',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.',
Ae='Aegon:BAABLgAECn8ZAAMBAAkJ2xKTIwC0AQABAAkJ2xKTIwC0AQACAAEJ8QCXUAASAAAAAA==.Aesthelian:BAAALgADCggJCQAAAA==.Aesthelyan:BAAALgAECgYJEwAAAA==.',
Ag='Agnia:BAAALgAECgYJDQAAAA==.',
Ah='Ahnerfays:BAAALgAECgYJCgABLgAECgkJKQADAIMdAA==.',
Ai='Aindriana:BAABLgAECn8YAAIEAAYJrAYlGADdAAAEAAYJrAYlGADdAAAAAA==.Airees:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgIJAgABLgAECgcJFgAFAO4PAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgYJBwABLgAECggJKQAGADIOAA==.Alestiana:BAABLgAECn8dAAIHAAcJKBOaGQCWAQAHAAcJKBOaGQCWAQAAAA==.Alkyria:BAAALgAECgYJEAAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJAwAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJAwAIAAAAAA==.',
Am='Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJBAABLgAECgUJBwAIAAAAAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8MAAIHAAQJsBo9BwBRAQAHAAQJsBo9BwBRAQAuAAQKfyQAAgcACAnpH+MVAGYCAAcACAnpH+MVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgYJEAAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgYJDQAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECggJJgACAB0hAA==.Apox:BAAALgADCgEJAQAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8dAAMJAAcJmiO6AgDPAgAJAAcJmiO6AgDPAgAKAAMJbhXtIADOAAAAAA==.Arbrerahis:BAAALgADCgYJBQAAAA==.Arcaneisbad:BAAALgAECgQJDgABLgAECgkJKQADAIMdAA==.Arkterris:BAAALgADCgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMLAAQJPw+CAQBFAQALAAQJMw2CAQBFAQABAAIJ1wm0RQCYAAAuAAQKfxUAAgEACAmnIFArAIwCAAEACAmnIFArAIwCAAAA.Artemisixion:BAAALgADCgMJAwAAAA==.Artemisomega:BAAALgAECgYJDwABLgADCgMJAwAIAAAAAA==.Arthillius:BAAALgAECgQJCgAAAA==.',
As='Ashime:BAABLgAECn8WAAIMAAYJjB4RBwCtAQAMAAYJjB4RBwCtAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECgcJEwAIAAAAAA==.',
Au='Augwater:BAAALgADCgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAAALgAECgYJCwAAAA==.',
Av='Aviana:BAAALgADCgYJBgAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECgcJHQANAIMjAA==.',
Ay='Ayothin:BAABLgAECn8kAAIOAAgJZxpDFQAQAgAOAAgJZxpDFQAQAgAAAA==.',
Az='Azerphale:BAAALgAECgMJBQAAAA==.Azura:BAAALgADCgIJAgAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8bAAQPAAgJGhe6LAD8AQAPAAgJGhe6LAD8AQAQAAEJBwrIRwAwAAARAAEJAAbrNwAoAAABLgAECgYJFgADADIJAA==.',
Be='Beefe:BAAALgAECgIJBAABLgAECgUJCwAIAAAAAA==.Beerntotems:BAAALgADCgQJBAAAAA==.Beldar:BAABLgAECn8YAAISAAcJcg/lDwDEAQASAAcJcg/lDwDEAQAAAA==.Benchpress:BAAALgAECgMJAwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgADCgUJBgABLgADCgYJDQAIAAAAAA==.Bip:BAAALgAECgYJCAAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgADCggJEAABLgAECgYJFQAPAPUOAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzlock:BAAALgADCgIJAgABLgAECgcJEgAIAAAAAA==.Blitzy:BAAALgAECgcJEgAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECgQJBQAAAA==.',
Br='Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn8dAAITAAcJLAVCJAAZAQATAAcJLAVCJAAZAQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAAALgAECgYJEAAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgMJAwAAAA==.Bullgrim:BAABLgAECn8WAAITAAgJnQnWFgB8AQATAAgJnQnWFgB8AQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAAALgAECgYJEQAAAA==.Bursk:BAAALgADCgIJAgAAAA==.',
By='Byrum:BAAALgAECgYJEgAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgAAAA==.',
Ca='Canabull:BAAALgADCgMJAwAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carion:BAABLgAECn8hAAIUAAkJhhmJFwAgAgAUAAkJhhmJFwAgAgAAAA==.',
Ce='Celeres:BAAALgADCgEJAQAAAA==.Celestiné:BAAALgADCgcJBwAAAA==.Cemeteri:BAAALgADCgkJFQAAAA==.',
Ch='Chaingun:BAAALgAECggJEgAAAA==.Chilblain:BAAALgAECgYJDwAAAA==.Chilchizedek:BAAALgAECgMJAwAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.',
Ci='Cibochevski:BAAALgADCgkJEAABLgAECgYJEQAIAAAAAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8ZAAIVAAkJMQ6uAwCnAQAVAAkJMQ6uAwCnAQAAAA==.Citrus:BAABLgAECn8WAAIHAAcJCSNeGABTAgAHAAcJCSNeGABTAgAAAA==.',
Cl='Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJCgAAAA==.Closetfurry:BAAALgAECgUJDQAAAA==.',
Co='Codenheimer:BAAALgAECgcJEwAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgMJAwAAAA==.Corrinne:BAAALgADCgcJDQABLgAECgcJEQAIAAAAAA==.Corvast:BAAALgAECgEJAQABLgAECgcJFgAFAO4PAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgEJAgAAAA==.',
Da='Daeshan:BAAALgAECgYJDwAAAA==.Dahmage:BAAALgADCgMJAwAAAA==.Daldolarette:BAABLgAECn8fAAIDAAkJ5RbWCQA5AgADAAkJ5RbWCQA5AgAAAA==.Daradevil:BAAALgAECgMJAwAAAA==.Daralune:BAAALgAECgcJCwAAAA==.Darcnight:BAAALgAECgMJBAAAAA==.Darkestdeath:BAAALgAECgYJCwAAAA==.Darkhate:BAAALgADCgkJEAAAAA==.Darkkef:BAAALgAECgMJCwAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgADCgkJEwAAAA==.Dawg:BAAALgAECgYJCAAAAA==.Days:BAAALgAECgIJBAAAAA==.',
De='Deamonite:BAAALgAECgUJDQAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJIAAWAIgdAA==.Deko:BAAALgADCgQJBAAAAA==.Demonstein:BAEALgAECgMJAwABLgAFFAUJFAAOAPkgAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgQJBAAAAA==.Destiney:BAAALgADCgcJBwAAAA==.Destros:BAABLgAECn8VAAIPAAcJkgV8OgDpAAAPAAcJkgV8OgDpAAAAAA==.Deystin:BAAALgADCggJCAAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQAAAA==.Drucy:BAAALgAECgYJEwAAAA==.Drusti:BAAALgADCgYJBgAAAA==.Dryageribeye:BAABLgAECn8aAAIBAAkJRho2JQCrAQABAAkJRho2JQCrAQAAAA==.Drzip:BAAALgADCgkJGQAAAA==.Drzippy:BAAALgADCgkJEgAAAA==.',
Du='Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8UAAIBAAcJjwN9WgD1AAABAAcJjwN9WgD1AAAAAA==.Duyii:BAAALgAECgYJDQAAAQ==.',
Dy='Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgIJAgAAAA==.',
Ec='Ech:BAAALgAECgYJBgAAAA==.Ecology:BAAALgADCgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgMJBgAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJKgAAAA==.Elendirs:BAAALgADCgYJCQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn8lAAMLAAgJuBW7BQDWAQALAAgJuBW7BQDWAQABAAEJBQpaKQEsAAAAAA==.',
Er='Eres:BAAALgAECgMJAwAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAAALgAECgcJDQAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAAALgAECgcJEwAAAA==.',
Fa='Fanceedas:BAAALgAECgQJCwAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAECgEJAQAAAA==.Fave:BAAALgADCgQJBgABLgAECgQJCAAIAAAAAA==.',
Fe='Feannesse:BAAALgAECgYJCAAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAAALgAECgQJCAAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAAIAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgIJAgAIAAAAAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8ZAAIOAAcJ6gi4RAA8AQAOAAcJ6gi4RAA8AQAAAA==.Frostbringer:BAAALgADCgEJAQAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgAECgEJAQABLgAECgIJAwAIAAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgIJAwAIAAAAAA==.',
Fv='Fvzz:BAABLgAECn8bAAIUAAgJGBfWZgAJAgAUAAgJGBfWZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECgQJBAAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAAALgAECggJEwAAAA==.Garekk:BAAALgAECgYJCwAAAA==.',
Gh='Ghomy:BAAALgAECgMJBAAAAA==.Ghun:BAABLgAECn8QAAMXAAcJPgaEEgAEAQAXAAUJ3QeEEgAEAQAYAAMJAQPxmgBMAAAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8HAAIBAAQJSBHZKwDsAAABAAQJSBHZKwDsAAAuAAQKfycAAgEACAmmHQ4wAHgCAAEACAmmHQ4wAHgCAAAA.Gilmore:BAAALgADCgkJEQAAAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJAgAAAA==.Goneville:BAAALgAECgYJDQAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8dAAIOAAcJCyK2DwBAAgAOAAcJCyK2DwBAAgAAAA==.',
Gu='Guias:BAAALgADCgkJHwAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAAALgAECgYJDgAAAA==.',
Ha='Hairykrishna:BAABLgAECn8bAAIYAAcJchoxGQDfAQAYAAcJchoxGQDfAQAAAA==.Haldevarik:BAAALgAECgQJCwAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAAALgAECgYJEQAAAA==.Hamur:BAABLgAECn8WAAQKAAcJqAq0GgAOAQAKAAYJfQa0GgAOAQAZAAcJ9wS2IAD1AAAJAAUJrQkxVADmAAAAAA==.Happysummon:BAABLgAECn8XAAIYAAgJZB+2DwAqAgAYAAgJZB+2DwAqAgAAAA==.Hargrave:BAAALgADCgMJBQAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAAALgAECgYJEQAAAA==.Hate:BAAALgADCgYJBgAAAA==.Hautos:BAAALgADCgEJAgAAAA==.',
He='Heavydisease:BAABLgAECn8XAAMBAAcJNBCtTgAUAQALAAUJPRM9CgArAQABAAcJXgitTgAUAQAAAA==.Heavywinner:BAABLgAECn8cAAIQAAkJvRsDDgC8AgAQAAkJvRsDDgC8AgAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hu='Hughmann:BAAALgAECgYJDgAAAA==.',
['Hâ']='Hârlot:BAAALgADCgcJCQAAAA==.',
Id='Idamage:BAAALgAECgcJBwABLgAECgUJFAABAGocAA==.',
Ig='Igetmoney:BAAALgAECgUJBgAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAECgQJBgABLgAECgkJKQADAIMdAA==.Imgnnatchyou:BAAALgAECgQJBQAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAAALgAECgQJBwAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBQAAAA==.',
Ja='Jadeth:BAAALgAECgYJCgAAAA==.Jaestra:BAAALgADCgMJBgABLgAECgYJEQAIAAAAAA==.Jaidah:BAAALgAECgEJAQAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQAAAA==.Jansôlo:BAAALgAECgYJEgAAAA==.Jaratri:BAABLgAECn8lAAISAAgJOB/7BQCnAgASAAgJOB/7BQCnAgAAAA==.Jaug:BAAALgAECgIJBAAAAA==.',
Je='Jenton:BAABLgAECn8YAAIUAAcJuAcuYQAZAQAUAAcJuAcuYQAZAQAAAA==.Jeric:BAAALgAECgcJEwAAAA==.',
Jo='Jobomage:BAAALgAECgUJCgAAAA==.Johnisme:BAAALgAECgMJBgAAAA==.Joryn:BAABLgAECn8eAAIGAAgJQRkWFgDhAQAGAAgJQRkWFgDhAQAAAA==.',
Ju='Juicydrucy:BAAALgADCggJCAAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJCwAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAAALgAECggJEwAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamdragosa:BAAALgADCgYJBgAAAA==.Kamlanthia:BAABLgAECn8ZAAMaAAkJPx2sAQCuAgAaAAkJPx2sAQCuAgAUAAMJRQ9MRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kaneki:BAAALgAECgcJEwAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAAALgAECggJEwAAAA==.Kastandmixer:BAAALgAECggJDgAAAA==.Kathine:BAAALgADCgkJMQAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgADCgcJDgAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kelandor:BAAALgADCgkJEwAAAA==.Kelwynd:BAAALgAECgYJEAAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAAALgAECgUJCAAAAA==.Kezak:BAAALgAECgEJBAABLgAECgUJCwAIAAAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAAALgAECgYJCAAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMbAAkJswRJMwAxAQAbAAkJswRJMwAxAQAVAAEJKgEkRgAcAAAAAA==.Knobbgoblin:BAAALgAECgcJBwAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAAALgAECgUJCQAAAA==.Kodera:BAABLgAECn8bAAMbAAgJpBFgGwDuAQAbAAgJpBFgGwDuAQAVAAEJ2wFqRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECgYJDQAIAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Kryssie:BAABLgAECn8bAAIGAAgJ8BU6GQDKAQAGAAgJ8BU6GQDKAQAAAA==.',
Ku='Kungfushammy:BAAALgAECgEJAQABLgAECgYJFgAcAGkOAA==.Kurkan:BAAALgAECgcJCwAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAABLgAECn8fAAIdAAcJeAcgJgDQAAAdAAcJeAcgJgDQAAAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECggJEwAIAAAAAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8gAAMNAAkJ1hlNEQCMAgANAAkJTxhNEQCMAgAeAAMJeBUGJgDBAAAAAA==.Lanaya:BAAALgAECgYJBgAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgMJAwAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8MAAIZAAQJ0BWyBQBbAQAZAAQJ0BWyBQBbAQAuAAQKfx8AAhkACAlPHekMALUCABkACAlPHekMALUCAAAA.Laulon:BAAALgADCgYJBgABLgAECgYJDQAIAAAAAQ==.Lawrensce:BAAALgADCgkJDAAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgcJFgAHAAkjAA==.Lencho:BAABLgAECn8XAAITAAcJlwslGQBnAQATAAcJlwslGQBnAQAAAA==.Lenian:BAAALgAECgYJEQAAAA==.Lexida:BAAALgAECgYJDAAAAA==.',
Li='Lightmonarch:BAAALgADCgUJBgAAAA==.Litesout:BAABLgAECn8YAAMFAAcJaxDnDAA1AQAFAAYJUhHnDAA1AQATAAcJ8wuHJAAYAQAAAA==.',
Ll='Llanadia:BAAALgAECgEJAQAAAA==.',
Lo='Loreck:BAAALgADCgkJIQAAAA==.Loredaryn:BAABLgAECn8dAAIcAAcJthSjBgBOAQAcAAcJthSjBgBOAQAAAA==.Lorra:BAAALgADCgYJBgAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8WAAIFAAcJ7g8IEgCBAQAFAAcJ7g8IEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
Ma='Mack:BAAALgAECgcJBQAAAA==.Madliblol:BAAALgADCgUJCAAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgADCgkJDAAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAABLgAECn8mAAIGAAgJ0hwfFQCOAgAGAAgJ0hwfFQCOAgAAAA==.Maiganoss:BAAALgAECgYJDAAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgYJDgAIAAAAAA==.',
Me='Megid:BAAALgAECgMJBgAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgEJAQAAAA==.Mestopheles:BAAALgAECgcJEAAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAAALgAECgYJCwAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECggJEQAIAAAAAA==.Morcathord:BAAALgADCgYJBwABLgAECgYJDQAIAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgADCggJCQAAAA==.',
Mw='Mwane:BAAALgAECgEJAgAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgMJAwAAAA==.',
Na='Nainel:BAAALgADCgMJBgABLgAECgYJEQAIAAAAAA==.Nakros:BAABLgAECn8aAAIOAAcJ8xSCbwCdAQAOAAcJ8xSCbwCdAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Neezytm:BAABLgAECn8hAAIfAAgJuxe9BwD1AQAfAAgJuxe9BwD1AQAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIDAAcJYRI9OACZAQADAAcJYRI9OACZAQABLgADCgYJBgAIAAAAAA==.',
Ni='Nianna:BAAALgAECgMJBgAAAA==.Nickto:BAAALgAECgQJBAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgADCgkJFQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Ny='Nymn:BAAALgAECgQJBAABLgAECgcJFgAFAO4PAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Og='Ogbruced:BAABLgAECn8VAAIPAAYJ9Q7MMQAUAQAPAAYJ9Q7MMQAUAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAAALgAECgYJEAAAAA==.',
Or='Orcrest:BAAALgAECgQJCQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn8VAAIgAAYJ9xb0FgBcAQAgAAYJ9xb0FgBcAQAAAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECgYJDQAAAA==.Paryah:BAAALgAECgYJEQAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8gAAMWAAkJiB17HACnAgAWAAkJiB17HACnAgAhAAIJhRYsIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgQJBAAAAA==.Phréek:BAABLgAECn8UAAQOAAYJXx2HKwCUAQAOAAYJXx2HKwCUAQADAAMJ2hOBawDMAAAMAAIJnBAmNwBmAAAAAA==.',
Pi='Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAABLgAECn8hAAICAAkJph3YBADvAQACAAkJph3YBADvAQABLgAFFAQJBQAMANkWAA==.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgMJAwAAAA==.Praze:BAAALgAECgQJCQAAAA==.Priority:BAABLgAECn8UAAIUAAYJbxpNPAB5AQAUAAYJbxpNPAB5AQAAAA==.Professorodd:BAABLgAECn8kAAIUAAgJrhkRRABsAgAUAAgJrhkRRABsAgABLgAFFAQJCQAPAHYMAA==.Prophet:BAAALgAECgIJBAAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgADCgkJIQAIAAAAAA==.',
Ra='Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgADCgYJCgAAAA==.Rahis:BAABLgAECn8jAAMGAAgJPRSoGQDHAQAGAAgJPRSoGQDHAQAiAAEJtgNSlAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAAALgAECgYJEQAAAA==.Ramsis:BAABLgAECn8bAAIHAAgJzQZbRgBoAQAHAAgJzQZbRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIZAAkJpwqfIwC7AQAZAAkJpwqfIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgMJAwAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgADCgcJDAAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAAALgAECgQJBQAAAA==.Red:BAABLgAECn8XAAISAAYJPwtPGgDhAAASAAYJPwtPGgDhAAAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgADCgkJEAAAAA==.Redtwinkies:BAAALgAECgQJBwAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBgAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgADCggJEQABLgAECgYJDQAIAAAAAQ==.Revy:BAAALgADCgYJDAAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJBQAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAAALgAECgYJDwAAAA==.Robokage:BAAALgADCggJEgABLgAECgYJEgAIAAAAAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgADCgcJCgAAAA==.Rolynas:BAAALgAECgIJBgAAAA==.Romokhar:BAAALgAECgQJCQAAAA==.Ronyar:BAAALgAECggJDAABLgAFFAUJDgADAJwVAA==.',
Ru='Rudef:BAABLgAECn8XAAIHAAkJRBOMIgAPAgAHAAkJRBOMIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECgYJDQAIAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgADCgkJHAAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgUJBQAAAA==.Seline:BAAALgADCgQJBAAAAA==.Seret:BAABLgAECn8gAAIZAAkJmReuGQATAgAZAAkJmReuGQATAgAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAAALgAECgYJEQAAAA==.Shammbo:BAAALgAECgYJDwAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8hAAMJAAgJ7xrtFgAkAgAJAAYJtyHtFgAkAgAZAAgJnAj7EgBtAQAAAA==.Shiyn:BAAALgADCgMJAwABLgAECgYJEQAIAAAAAA==.Shupala:BAAALgAECgQJBgAAAA==.',
Si='Sicnus:BAAALgAECgYJDAAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgYJEAAIAAAAAA==.Sinadin:BAAALgAECgEJAQAAAA==.Sindoreisins:BAAALgAECgUJBQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn8dAAINAAcJgyMgBQBbAgANAAcJgyMgBQBbAgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgADCgcJCQAAAA==.Sourkeys:BAAALgAECgQJBQAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Sy='Sybil:BAACLgAFFH8KAAIQAAQJ1RczDgD9AAAQAAQJ1RczDgD9AAAuAAQKfx4AAhAABwkMHhQZAD4CABAABwkMHhQZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgQJAwAAAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgMJBAAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgADCgMJAwAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECgYJDQAIAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCAAAAA==.Telysse:BAAALgAECgYJBgAAAA==.Tenma:BAAALgAECgIJAgABLgAECgYJDQAIAAAAAA==.Teo:BAAALgAECgMJBgAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECgYJBgAIAAAAAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgQJCAAIAAAAAA==.Thehunted:BAAALgAECgYJCwAAAA==.Thelock:BAABLgAECn8dAAIHAAkJ/xgXEgCFAgAHAAkJ/xgXEgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAABLgAFFH8JAAIPAAQJdgy2EgAIAQAPAAQJdgy2EgAIAQAAAA==.Thundertwig:BAABLgAECn8gAAIKAAgJPQVJFQBJAQAKAAgJPQVJFQBJAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJIAAWAIgdAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAAALgAECgcJEQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgUJBwAAAA==.Tofulhundun:BAABLgAECn8cAAIgAAcJAQTgJwDoAAAgAAcJAQTgJwDoAAAAAA==.Toothpick:BAAALgAECgQJCAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Treehaus:BAAALgAECgYJDwAAAA==.Triannah:BAAALgAECgYJDAAAAA==.Trildjr:BAABLgAECn8XAAIGAAcJWBCYJgB+AQAGAAcJWBCYJgB+AQAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgADCgIJAgAAAA==.',
Tu='Tuldag:BAABLgAECn8WAAIgAAYJEgjMKQDeAAAgAAYJEgjMKQDeAAAAAA==.',
Ty='Tyrse:BAAALgAECgMJBwAAAA==.',
Tz='Tzerina:BAABLgAECn8UAAIEAAcJXQ8dDwBJAQAEAAcJXQ8dDwBJAQAAAA==.',
Um='Umbrawing:BAAALgADCgkJCQAAAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECgYJCAABLgAECgYJDQAIAAAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAAALgAECggJEwAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAAALgAECgYJDwAAAA==.Valkriss:BAAALgADCgMJAwAAAA==.Vallak:BAABLgAECn8cAAIRAAcJPhjpBQCwAQARAAcJPhjpBQCwAQAAAA==.Vallyrie:BAAALgAECgkJDAAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn8dAAIjAAcJ+BxWBADhAQAjAAcJ+BxWBADhAQAAAA==.Valth:BAAALgAECgMJBQAAAA==.Valtonka:BAAALgADCgMJBAAAAA==.Vanae:BAAALgAECgMJBwAAAA==.Vaporgriffin:BAAALgAECgQJBAAAAA==.Varaella:BAAALgADCgcJDAAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgADCgEJAQAAAA==.',
Ve='Vecna:BAAALgAECgMJBgAAAA==.Velendez:BAAALgAECgQJCQAAAA==.Veleria:BAABLgAECn8WAAMDAAYJMgkNJwASAQADAAYJMgkNJwASAQAOAAYJfgobVgANAQAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAAALgAECgYJEQAAAA==.Versatina:BAAALgAECgQJCQAAAA==.Vexizz:BAAALgAECgUJDgAAAA==.',
Vi='Victra:BAABLgAECn8YAAIJAAcJphQILgCNAQAJAAcJphQILgCNAQAAAA==.Viko:BAABLgAECn8UAAIgAAYJwgkwKQDhAAAgAAYJwgkwKQDhAAAAAA==.Vinaya:BAAALgAECgQJCQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAAALgAECgQJCQAAAA==.',
Vu='Vulpy:BAAALgADCgIJAgAAAA==.',
Wa='Wandersong:BAAALgAECgQJCgAAAA==.Wardudeman:BAAALgAECgUJEgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwAIAAAAAA==.Watsuki:BAAALgADCgkJFQABLgAECgYJEQAIAAAAAA==.',
We='Weoo:BAAALgAECgYJDAAAAA==.Werrick:BAABLgAECn8gAAIOAAgJxgrTOgBaAQAOAAgJxgrTOgBaAQAAAA==.',
Wh='Whitespot:BAAALgADCggJDgAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgYJEQAIAAAAAA==.',
Wo='Woblatus:BAAALgAECgYJCgABLgAECgYJDQAIAAAAAQ==.',
Wr='Wreckreation:BAAALgAECgYJDgAAAA==.',
Wy='Wylectra:BAAALgAECgYJDwAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8jAAIUAAYJ0h9RKwC3AQAUAAYJ0h9RKwC3AQAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgEJAQAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAAALgAECgEJAgAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgEJAgAIAAAAAA==.',
Za='Zagasham:BAABLgAECn8XAAIHAAgJGhiiHwAhAgAHAAgJGhiiHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAAALgAECgYJDAAAAA==.Zamari:BAAALgADCgMJBgABLgAECgYJDAAIAAAAAA==.Zaphiell:BAAALgAECgYJDgAAAA==.',
Ze='Zeid:BAABLgAECn8cAAITAAkJOApXGABtAQATAAkJOApXGABtAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zev:BAAALgAECgQJCQAAAA==.',
Zi='Zilli:BAAALgAECgQJCgAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECgYJDQAIAAAAAQ==.',
Zo='Zoeystorm:BAAALgADCgkJDAAAAA==.Zoltraak:BAAALgAECgUJCwAAAA==.',
Zy='Zykie:BAABLgAECn8aAAIkAAcJkApdBgBNAQAkAAcJkApdBgBNAQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8WAAQcAAYJaQ72CwDhAAAcAAUJnhD2CwDhAAAYAAUJQQh25gCOAAAXAAEJhgFnOAAXAAAAAA==.',
['Är']='Ärgo:BAABLgAECn8WAAITAAcJuA5gFwB3AQATAAcJuA5gFwB3AQAAAA==.',
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

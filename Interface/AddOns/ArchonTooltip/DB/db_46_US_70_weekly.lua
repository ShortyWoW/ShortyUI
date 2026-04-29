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

local lookup = {'Paladin-Holy','Warrior-Arms','Hunter-Marksmanship','Unknown-Unknown','Warlock-Destruction','Shaman-Restoration','DeathKnight-Blood','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Monk-Brewmaster','Paladin-Retribution','Druid-Restoration','Druid-Feral','Hunter-Survival','Warrior-Fury','Mage-Frost','DemonHunter-Devourer','DeathKnight-Frost','Warlock-Demonology','Druid-Balance','Hunter-BeastMastery','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DemonHunter-Vengeance','Paladin-Protection','Shaman-Elemental','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.',
Ae='Aegon:BAAALgAECgkJEwAAAA==.Aesthelyan:BAAALgAECgQJCwAAAA==.',
Ag='Agnia:BAAALgAECgYJDQAAAA==.',
Ah='Ahnerfays:BAAALgAECgUJBQABLgAECggJIgABAC4bAA==.',
Ai='Aindriana:BAAALgAECgYJEQAAAA==.Airees:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgIJAgABLgAECgcJFAACAO4PAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgYJBwABLgAECggJIQADADIOAA==.Alestiana:BAAALgAECgcJEgAAAA==.Alkyria:BAAALgAECgYJCgAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJAwAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.',
Am='Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgADCgcJCgABLgAECgcJGgAFAOMaAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8KAAIGAAQJsBo+BwBRAQAGAAQJsBo+BwBRAQAuAAQKfyQAAgYACAnpH+YVAGYCAAYACAnpH+YVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgADCgQJBAAAAA==.Antarres:BAAALgAECgYJCgAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgUJBwAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECgcJHgAHAOkfAA==.',
Ar='Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8WAAMIAAcJsB5+GwAAAgAIAAcJsB5+GwAAAgAJAAMJbhUgDgDUAAAAAA==.Arcaneisbad:BAAALgAECgQJBwABLgAECggJIgABAC4bAA==.Arkterris:BAAALgADCgYJBgAAAA==.Arlyn:BAABLgAECn8VAAIKAAgJpyBKKwCMAgAKAAgJpyBKKwCMAgAAAA==.Artemisomega:BAAALgAECgQJBwAAAA==.Arthillius:BAAALgAECgMJBQAAAA==.',
As='Ashime:BAAALgAECgYJEAAAAA==.Ashkara:BAAALgAECgUJCQAAAA==.Ashèr:BAAALgADCgIJAgABLgAECgcJEgAEAAAAAA==.',
Au='Augwater:BAAALgADCgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAAALgAECgQJBwAAAA==.',
Av='Avålkrin:BAAALgADCgEJAQABLgAECgcJFgALAA0jAA==.',
Ay='Ayothin:BAABLgAECn8cAAIMAAcJNxyGDQDAAQAMAAcJNxyGDQDAAQAAAA==.',
Az='Azerphale:BAAALgAECgMJBQAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8YAAMNAAgJhBa5LAD8AQANAAgJhBa5LAD8AQAOAAEJAAbkNwAoAAABLgAECgYJEAAEAAAAAA==.',
Be='Beefe:BAAALgAECgIJAwABLgAECgUJCgAEAAAAAA==.Beldar:BAABLgAECn8YAAIPAAcJcg83BgBiAQAPAAcJcg83BgBiAQAAAA==.Benchpress:BAAALgAECgMJAwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgADCgUJBgABLgADCgYJDQAEAAAAAA==.Bip:BAAALgAECgIJAgAAAA==.Birgittë:BAAALgADCgUJBgAAAA==.Biscuitbob:BAAALgADCgcJDAABLgAECgYJDwAEAAAAAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzlock:BAAALgADCgIJAgABLgAECgcJEAAEAAAAAA==.Blitzy:BAAALgAECgcJEAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECgQJBQAAAA==.',
Br='Brenick:BAABLgAECn8WAAIQAAcJOQQdFgDmAAAQAAcJOQQdFgDmAAAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAAALgAECgYJCgAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgMJAwAAAA==.Bullgrim:BAAALgAECgcJEgAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAAALgAECgQJCQAAAA==.Bursk:BAAALgADCgIJAgAAAA==.',
By='Byrum:BAAALgAECgYJEgAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgAAAA==.',
Ca='Canabull:BAAALgADCgMJAwAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carion:BAABLgAECn8ZAAIRAAkJuxiKKgDIAgARAAkJuxiKKgDIAgAAAA==.',
Ce='Cemeteri:BAAALgADCgkJDAAAAA==.',
Ch='Chaingun:BAAALgAECggJDQAAAA==.Chilblain:BAAALgAECgUJCQAAAA==.Chilchizedek:BAAALgAECgMJAwAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.',
Ci='Cibochevski:BAAALgADCgkJBwABLgAECgQJCQAEAAAAAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAAALgAECgkJEQAAAA==.Citrus:BAABLgAECn8VAAIGAAYJ6CRkGABTAgAGAAYJ6CRkGABTAgAAAA==.',
Cl='Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJBgAAAA==.Closetfurry:BAAALgAECgMJBgAAAA==.',
Co='Codenheimer:BAAALgAECgYJDAAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgMJAwAAAA==.Corrinne:BAAALgADCgcJBwABLgAECgYJEAAEAAAAAA==.Corvast:BAAALgADCgQJBAABLgAECgcJFAACAO4PAA==.Corya:BAAALgADCgkJFQAAAA==.',
Cp='Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgEJAQAAAA==.',
Da='Daeshan:BAAALgAECgUJCQAAAA==.Dahmage:BAAALgADCgMJAwAAAA==.Daldolarette:BAABLgAECn8ZAAIBAAkJHxLdKwDXAQABAAkJHxLdKwDXAQAAAA==.Daradevil:BAAALgAECgMJAwAAAA==.Daralune:BAAALgAECgQJBAAAAA==.Darcnight:BAAALgAECgEJAQAAAA==.Darkestdeath:BAAALgAECgYJCwAAAA==.Darkhate:BAAALgADCggJDAAAAA==.Darkkef:BAAALgAECgMJCwAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgADCggJDwAAAA==.Dawg:BAAALgAECgUJBgAAAA==.Days:BAAALgAECgIJBAAAAA==.',
De='Deamonite:BAAALgAECgQJCAAAAA==.Decapa:BAAALgAECgQJBAABLgAECggJGwASAGEeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonstein:BAEALgAECgMJAwAAAA==.Derd:BAAALgAECgIJAwAAAA==.Destiney:BAAALgADCgcJBwAAAA==.Destros:BAAALgAECgcJDgAAAA==.Deystin:BAAALgADCgYJBgAAAA==.',
Dj='Djangoo:BAAALgAECgcJDgAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQAAAA==.Drucy:BAAALgAECgQJCwAAAA==.Drusti:BAAALgADCgYJBgAAAA==.Dryageribeye:BAABLgAECn8UAAIKAAgJfRazSAAZAgAKAAgJfRazSAAZAgAAAA==.Drzip:BAAALgADCgkJFgAAAA==.Drzippy:BAAALgADCgkJCQAAAA==.',
Du='Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAAALgAECgYJDQAAAA==.Duyii:BAAALgAECgQJCwABLgAECgYJDAAEAAAAAQ==.',
Dy='Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgEJAQAAAA==.',
Ec='Ech:BAAALgADCgcJCwAAAA==.Ecology:BAAALgADCgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgMJAwAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJHwAAAA==.Elendirs:BAAALgADCgYJCQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn8gAAMTAAgJRxO6BQDWAQATAAgJRxO6BQDWAQAKAAEJBQpKKQEsAAAAAA==.',
Er='Eres:BAAALgAECgMJAwAAAA==.Eringobragh:BAAALgADCgkJBwAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAAALgAECgYJBgAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAAALgAECgcJDAAAAA==.',
Fa='Fanceedas:BAAALgAECgQJBgAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAECgEJAQAAAA==.',
Fe='Feannesse:BAAALgAECgQJBgAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAAALgAECgQJBAAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAAEAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgYJFQANAD0iAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAAALgAECgcJEgAAAA==.Frostbringer:BAAALgADCgEJAQAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgADCgcJCAAAAA==.',
Fv='Fvzz:BAABLgAECn8YAAIRAAgJ8RPeZgAJAgARAAgJ8RPeZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECgMJAwAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAAALgAECgcJCwAAAA==.Garekk:BAAALgAECgUJBQAAAA==.',
Gh='Ghomy:BAAALgAECgEJAQAAAA==.Ghun:BAAALgAECgUJDgAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8GAAIKAAMJOA7RKwDsAAAKAAMJOA7RKwDsAAAuAAQKfyEAAgoACAmSGwgwAHgCAAoACAmSGwgwAHgCAAAA.Gilmore:BAAALgADCgkJCgAAAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJAgAAAA==.Goneville:BAAALgAECgYJDQAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCgUJBwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8WAAIMAAcJCyKFBQA/AgAMAAcJCyKFBQA/AgAAAA==.',
Gu='Guias:BAAALgADCgkJGAAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAAALgAECgYJDQAAAA==.',
Ha='Hairykrishna:BAABLgAECn8UAAIUAAcJfhS4DgCcAQAUAAcJfhS4DgCcAQAAAA==.Haldevarik:BAAALgAECgQJCQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAAALgAECgQJCQAAAA==.Hamur:BAAALgAECgYJDwAAAA==.Happysummon:BAABLgAECn8VAAIUAAcJ3CBOCADtAQAUAAcJ3CBOCADtAQAAAA==.Hargrave:BAAALgADCgIJAgAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAAALgAECgQJCQAAAA==.Hate:BAAALgADCgYJBgAAAA==.',
He='Heavydisease:BAAALgAECgcJEgAAAA==.Heavywinner:BAABLgAECn8cAAIVAAkJvRsEDgC8AgAVAAkJvRsEDgC8AgAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgQJBQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hu='Hughmann:BAAALgAECgQJBgAAAA==.',
['Hâ']='Hârlot:BAAALgADCgcJCQAAAA==.',
Ig='Igetmoney:BAAALgAECgIJAgAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAECgQJBgABLgAECggJIgABAC4bAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAAALgAECgQJBAAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBQAAAA==.',
Ja='Jadeth:BAAALgAECgYJCgAAAA==.Jaestra:BAAALgADCgMJBgABLgAECgQJCQAEAAAAAA==.Jaidah:BAAALgADCgkJFAAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQABLgAECgQJCwAEAAAAAA==.Jansôlo:BAAALgAECgYJDAAAAA==.Jaratri:BAABLgAECn8hAAIPAAgJdxz5BQCnAgAPAAgJdxz5BQCnAgAAAA==.Jaug:BAAALgAECgIJBAAAAA==.',
Je='Jenton:BAABLgAECn8VAAIRAAYJHwcaNgDtAAARAAYJHwcaNgDtAAAAAA==.Jeric:BAAALgAECgYJDAAAAA==.',
Jo='Jobomage:BAAALgAECgUJCAAAAA==.Johnisme:BAAALgAECgMJAwAAAA==.Joryn:BAABLgAECn8WAAIWAAgJnRffNgDTAQAWAAgJnRffNgDTAQAAAA==.',
Ju='Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgYJCQAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAAALgAECgcJCwAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamlanthia:BAABLgAECn8WAAMXAAgJ7B2sAQCuAgAXAAgJ7B2sAQCuAgARAAMJRQ9BRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAQAAAA==.Kaneki:BAAALgAECgcJDwAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAAALgAECgcJEQAAAA==.Kastandmixer:BAAALgAECgcJBwAAAA==.Kathine:BAAALgADCgkJMQAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgADCgUJBwAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kelandor:BAAALgADCgkJCgAAAA==.Kelwynd:BAAALgAECgYJCgAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAAALgAECgQJBAAAAA==.Kezak:BAAALgAECgEJAgABLgAECgUJCgAEAAAAAA==.',
Kh='Khaarna:BAAALgADCgkJGwAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kirean:BAAALgAECgQJBQAAAA==.',
Kn='Knives:BAABLgAECn8WAAMYAAgJzgRBMwAxAQAYAAgJzgRBMwAxAQAZAAEJKgEbRgAcAAAAAA==.Knobbgoblin:BAAALgAECgcJBwAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAAALgAECgUJCQAAAA==.Kodera:BAABLgAECn8YAAMYAAgJpBFYGwDuAQAYAAgJpBFYGwDuAQAZAAEJ2wFhRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAQ==.Korigan:BAAALgAECgEJAQAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgADCgkJFAAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Kryssie:BAABLgAECn8XAAIWAAgJWBRhCQDSAQAWAAgJWBRhCQDSAQAAAA==.',
Ku='Kungfushammy:BAAALgADCgcJFwABLgAECgYJEAAEAAAAAA==.Kurkan:BAAALgAECgcJCgAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAABLgAECn8ZAAIaAAcJeAYyDgAAAQAaAAcJeAYyDgAAAQAAAA==.',
['Kå']='Kårg:BAAALgADCgYJBgABLgAECgcJEQAEAAAAAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8dAAILAAkJTxhMEQCMAgALAAkJTxhMEQCMAgAAAA==.Lanaya:BAAALgAECgYJBgAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgADCgQJEAAAAA==.Lascîel:BAAALgADCgcJDAAAAA==.Laserheadten:BAACLgAFFH8IAAIbAAMJmhS6BAD+AAAbAAMJmhS6BAD+AAAuAAQKfx8AAhsACAlPHegMALUCABsACAlPHegMALUCAAAA.Laulon:BAAALgADCgYJBgABLgAECgYJDAAEAAAAAQ==.Lawrensce:BAAALgADCggJCAAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lencho:BAAALgAECgcJEAAAAA==.Lenian:BAAALgAECgQJCQAAAA==.Lexida:BAAALgAECgUJCAAAAA==.',
Li='Lightmonarch:BAAALgADCgUJBQAAAA==.Litesout:BAAALgAECgcJEgAAAA==.',
Ll='Llanadia:BAAALgADCggJDQAAAA==.',
Lo='Loreck:BAAALgADCgkJIQAAAA==.Loredaryn:BAABLgAECn8UAAIFAAcJDhE8FgCYAQAFAAcJDhE8FgCYAQAAAA==.Lorra:BAAALgADCgYJBgAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgADCgYJBgAAAA==.Lunariel:BAABLgAECn8UAAICAAcJ7g8BEgCBAQACAAcJ7g8BEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
Ma='Mack:BAAALgAECgcJBQAAAA==.Madliblol:BAAALgADCgMJAwAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgADCgMJAwAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAABLgAECn8eAAIWAAgJSBwhFQCOAgAWAAgJSBwhFQCOAgAAAA==.Maiganoss:BAAALgAECgYJBgAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgQJCQAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgUJCAAEAAAAAA==.',
Me='Megid:BAAALgAECgMJAwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgUJBQAAAA==.Mestopheles:BAAALgAECgUJDgAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAAALgAECgUJBQAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgUJBwAEAAAAAA==.Morcathord:BAAALgADCgEJAQABLgAECgYJDAAEAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mourtanious:BAAALgADCgQJBAAAAA==.',
Mu='Mulva:BAAALgAECgUJBQAAAA==.Muradil:BAAALgADCggJCQAAAA==.',
Mw='Mwane:BAAALgADCgYJCgAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgADCgcJDAAAAA==.',
Na='Nainel:BAAALgADCgMJBgABLgAECgQJCQAEAAAAAA==.Nakros:BAABLgAECn8YAAIMAAcJ8xSEbwCdAQAMAAcJ8xSEbwCdAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Neezytm:BAABLgAECn8ZAAIcAAgJVRSyHgAGAgAcAAgJVRSyHgAGAgAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIBAAcJYRI+OACZAQABAAcJYRI+OACZAQABLgADCgYJBgAEAAAAAA==.',
Ni='Nianna:BAAALgAECgMJAwAAAA==.Nickto:BAAALgAECgQJBAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgADCgkJDAAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Ny='Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Og='Ogbruced:BAAALgAECgYJDwAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.',
Ol='Olessa:BAAALgAECgYJCgAAAA==.',
Or='Orcrest:BAAALgAECgMJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAAALgAECgYJDwAAAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECgYJDQAAAA==.Paryah:BAAALgAECgQJCQAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8bAAMSAAgJYR50HACnAgASAAgJYR50HACnAgAdAAIJhRYuIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCQAAAA==.Phindra:BAAALgAECgQJBAAAAA==.Phréek:BAAALgAECgYJDwAAAA==.',
Pi='Pitythefü:BAAALgADCgcJDAAAAA==.',
Pl='Plethknight:BAABLgAECn8WAAIHAAgJhh5UCACfAgAHAAgJhh5UCACfAgABLgAECggJHwAeAE0eAA==.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgMJAwAAAA==.Praze:BAAALgAECgMJBQAAAA==.Priority:BAAALgAECgYJDwAAAA==.Professorodd:BAABLgAECn8gAAIRAAgJrhkQRABsAgARAAgJrhkQRABsAgABLgAFFAMJBQANAIcFAA==.Prophet:BAAALgAECgIJBAAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgADCgkJIQAEAAAAAA==.',
Ra='Raeztharion:BAAALgADCgYJCgAAAA==.Rahis:BAABLgAECn8fAAMWAAgJxRNKCQDUAQAWAAgJxRNKCQDUAQADAAEJtgNNlAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAAALgAECgQJCQAAAA==.Ramsis:BAABLgAECn8YAAIGAAgJyAZaRgBoAQAGAAgJyAZaRgBoAQAAAA==.Randir:BAABLgAECn8WAAIbAAgJRAuWIwC7AQAbAAgJRAuWIwC7AQAAAA==.Rauk:BAAALgAECgMJAwAAAA==.Rauldk:BAAALgAECgEJAQAAAA==.Raylee:BAAALgADCgYJBgAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAAALgAECgQJBQAAAA==.Red:BAAALgAECgUJEgAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgADCgkJBwAAAA==.Redtwinkies:BAAALgAECgQJBwAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBgAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgADCggJEQABLgAECgYJDAAEAAAAAQ==.Revy:BAAALgADCgYJDAAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgADCgcJCAABLgAECgIJAgAEAAAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAAALgAECgUJCQAAAA==.Robokage:BAAALgADCgcJDAABLgAECgYJDwAEAAAAAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgADCgUJCAAAAA==.Rolynas:BAAALgAECgEJBAAAAA==.Romokhar:BAAALgAECgMJBQAAAA==.Ronyar:BAAALgAECggJCAABLgAFFAUJCgABAHsQAA==.',
Ru='Rudef:BAABLgAECn8UAAIGAAgJJhWTIgAPAgAGAAgJJhWTIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECgYJDAAEAAAAAQ==.Sarris:BAAALgADCgkJBwAAAA==.Sarynah:BAAALgADCgkJHAAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgUJBQAAAA==.Seline:BAAALgADCgQJBAAAAA==.Seret:BAABLgAECn8dAAIbAAgJZheqGQATAgAbAAgJZheqGQATAgAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAAALgAECgQJCQAAAA==.Shammbo:BAAALgAECgYJCgAAAA==.Shazra:BAAALgAECgUJCwAAAA==.Sheboygz:BAABLgAECn8gAAMIAAgJjRrmFgAkAgAIAAYJtyHmFgAkAgAbAAgJCwcJCgBPAQAAAA==.Shiyn:BAAALgADCgMJAwABLgAECgQJCQAEAAAAAA==.Shupala:BAAALgAECgQJBgAAAA==.',
Si='Sicnus:BAAALgAECgUJBgAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgYJCgAEAAAAAA==.Sindoreisins:BAAALgAECgUJBQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn8WAAILAAcJDSMwAgA7AgALAAcJDSMwAgA7AgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgADCgQJAgAAAA==.Sourkeys:BAAALgAECgMJBAAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Sy='Sybil:BAACLgAFFH8GAAIVAAMJ3RQpDgD9AAAVAAMJ3RQpDgD9AAAuAAQKfx4AAhUABwkMHhYZAD4CABUABwkMHhYZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgIJAgAAAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgMJBAAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgADCgMJAwAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECgYJDAAEAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCAAAAA==.Telysse:BAAALgADCgkJEQAAAA==.Tenma:BAAALgAECgIJAgABLgAECgUJBwAEAAAAAA==.Teo:BAAALgAECgMJAwAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwAAAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJAwABLgAECgQJBAAEAAAAAA==.Thehunted:BAAALgAECgYJCwAAAA==.Thelock:BAABLgAECn8dAAIGAAkJ/xgYEgCFAgAGAAkJ/xgYEgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAABLgAFFH8FAAINAAMJhwWXFADCAAANAAMJhwWXFADCAAAAAA==.Thundertwig:BAABLgAECn8YAAIJAAcJPwVHCgAsAQAJAAcJPwVHCgAsAQAAAA==.',
Ti='Tilith:BAAALgADCgYJCgAAAA==.Timoris:BAAALgADCgYJBgABLgAECggJGwASAGEeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAAALgAECgYJEAAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgQJBAABLgAECgcJGgAFAOMaAA==.Tofulhundun:BAABLgAECn8VAAIfAAcJIwPBFQDKAAAfAAcJIwPBFQDKAAAAAA==.Toothpick:BAAALgAECgQJBgAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Treehaus:BAAALgAECgUJCQAAAA==.Triannah:BAAALgAECgUJBgAAAA==.Trildjr:BAAALgAECgcJEAAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgADCgIJAgAAAA==.',
Tu='Tuldag:BAAALgAECgYJEAAAAA==.',
Ty='Tyrse:BAAALgAECgMJBAAAAA==.',
Tz='Tzerina:BAAALgAECgYJDQAAAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAAALgAECgYJEQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAAALgAECgQJBwAAAA==.Valkriss:BAAALgADCgMJAwAAAA==.Vallak:BAABLgAECn8VAAIOAAYJhBXYBABGAQAOAAYJhBXYBABGAQAAAA==.Vallyrie:BAAALgAECgQJBAAAAA==.Valrah:BAAALgAECgYJCQAAAA==.Valssharess:BAABLgAECn8WAAIgAAcJIhvvAgCJAQAgAAcJIhvvAgCJAQAAAA==.Valth:BAAALgAECgMJBQAAAA==.Valtonka:BAAALgADCgMJAwAAAA==.Vanae:BAAALgAECgMJBAAAAA==.Vaporgriffin:BAAALgAECgQJBAAAAA==.Varaella:BAAALgADCgcJDAAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgADCgEJAQAAAA==.',
Ve='Vecna:BAAALgADCgcJDAAAAA==.Velenkes:BAAALgAECgMJBQAAAA==.Veleria:BAAALgAECgYJEAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAAALgAECgYJCwAAAA==.Versatina:BAAALgAECgMJBQAAAA==.Vexizz:BAAALgAECgQJCQAAAA==.',
Vi='Victra:BAAALgAECgYJEQAAAA==.Viko:BAAALgAECgYJDwAAAA==.Vinaya:BAAALgAECgMJBQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAAALgAECgMJBAAAAA==.',
Wa='Wandersong:BAAALgAECgQJCgAAAA==.Wardudeman:BAAALgAECgUJEgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwAEAAAAAA==.Watsuki:BAAALgADCgkJDAABLgAECgQJCQAEAAAAAA==.',
We='Weoo:BAAALgAECgMJBgAAAA==.Werrick:BAABLgAECn8YAAIMAAcJbAo5JQASAQAMAAcJbAo5JQASAQAAAA==.',
Wh='Whitespot:BAAALgADCgUJCAAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgQJCQAEAAAAAA==.',
Wo='Woblatus:BAAALgAECgQJBAABLgAECgYJDAAEAAAAAQ==.',
Wr='Wreckreation:BAAALgAECgUJCAAAAA==.',
Wy='Wylectra:BAAALgAECgUJCQAAAA==.',
Xe='Xerosaga:BAAALgAECgYJBwAAAA==.Xeròmercy:BAABLgAECn8dAAIRAAYJxh7JXQAhAgARAAYJxh7JXQAhAgAAAA==.Xerômercy:BAAALgAECgUJBQAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgEJAQAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgQJCgAAAA==.',
['Yè']='Yèti:BAAALgADCgYJCgAAAA==.Yètipally:BAAALgADCgIJAgABLgADCgYJCgAEAAAAAA==.',
Za='Zagasham:BAABLgAECn8VAAIGAAgJ8heoHwAhAgAGAAgJ8heoHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAAALgAECgQJBQAAAA==.Zamari:BAAALgADCgMJBgABLgAECgQJBQAEAAAAAA==.Zaphiell:BAAALgAECgUJCAAAAA==.',
Ze='Zeid:BAABLgAECn8WAAIQAAgJAAgVRQCPAQAQAAgJAAgVRQCPAQAAAA==.Zenoltt:BAAALgAECgYJCwAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zev:BAAALgAECgMJBQAAAA==.',
Zi='Zilli:BAAALgAECgQJBgAAAA==.Zinderalanot:BAAALgAECgYJDAAAAQ==.',
Zo='Zoeystorm:BAAALgADCggJCAAAAA==.Zoltraak:BAAALgAECgUJCgAAAA==.',
Zy='Zykie:BAAALgAECgcJEwAAAA==.',
['Äc']='Ächmed:BAAALgAECgYJEAAAAA==.',
['Är']='Ärgo:BAAALgAECgYJDwAAAA==.',
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

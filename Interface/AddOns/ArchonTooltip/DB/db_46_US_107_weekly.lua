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

local lookup = {'Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Blood','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Warrior-Protection','Evoker-Devastation','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Rogue-Subtlety','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Druid-Restoration',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abogato:BAAALgADCgYJCgAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECgMJBgAAAA==.',
Ah='Ahnir:BAAALgAECgYJCgAAAA==.Ahnkhano:BAABLgAECn8dAAIBAAgJ8RFeEgCjAQABAAgJ8RFeEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akbartheiiv:BAACLgAFFH8OAAICAAYJ1xO2AQACAgACAAYJ1xO2AQACAgAuAAQKfyMAAgIACAm+JIoEAE0DAAIACAm+JIoEAE0DAAAA.',
Al='Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8cAAIDAAgJ7RwxEwBGAgADAAgJ7RwxEwBGAgAAAA==.Aluvia:BAAALgAECgIJAwAAAA==.',
Am='Amairis:BAAALgAECgEJAQAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJHwAAAA==.Annestasia:BAAALgAECgcJAQAAAA==.Anrion:BAABLgAECn8ZAAMEAAgJFCBwBgABAwAEAAgJFCBwBgABAwAFAAcJSxtVAQDsAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAGAAAAAA==.',
Ap='Apolló:BAAALgAECgkJCAAAAA==.',
Ar='Araiana:BAAALgADCgEJAQAAAA==.Arayia:BAAALgAECgMJBQAAAA==.Arelian:BAAALgAECgUJCAAAAA==.Aristia:BAAALgAECgYJCgABLgADCgYJCgAGAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJBwAAAA==.',
Au='Auranar:BAAALgAECgQJBAAAAA==.Aurilia:BAAALgAECgEJAQAAAA==.',
Av='Avanicus:BAABLgAECn8dAAQHAAgJpAknIgBFAQAHAAcJfQgnIgBFAQAIAAIJqgy4HQCDAAAJAAIJ0QH3EwE6AAAAAA==.Aven:BAAALgAECgcJDgAAAA==.',
Ax='Axiomronin:BAABLgAECn8YAAMKAAcJfiOuDgCSAgAKAAcJoyKuDgCSAgALAAMJox5PHABjAAAAAA==.',
Ay='Ayroon:BAAALgADCgYJBgAAAA==.',
Az='Azulien:BAAALgAECgUJDgAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIMAAgJ0R3TJgCgAgAMAAgJ0R3TJgCgAgAAAA==.Banderblitz:BAABLgAECn8eAAINAAgJdxv8AgAlAgANAAgJdxv8AgAlAgAAAA==.Bar:BAACLgAFFH8FAAMCAAMJyQThEQCOAAACAAIJZwThEQCOAAADAAMJkhEvBgCJAAAuAAQKfxsAAgIACAlCGiAVAEMCAAIACAlCGiAVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgUJBQABLgAECggJEQAGAAAAAA==.Bellatrixie:BAAALgADCggJDgAAAA==.Benafflock:BAAALgAECgQJCQABLgAECgcJEgAGAAAAAA==.Beriadhwen:BAAALgAECgEJAQAAAA==.Bermy:BAAALgAECgYJEgAAAA==.Bewildert:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8VAAIMAAcJlRD0HAAzAQAMAAcJlRD0HAAzAQAAAA==.Blende:BAAALgAECgYJCwAAAA==.Bloodshadow:BAABLgAECn8UAAIOAAgJjgpnTwB7AQAOAAgJjgpnTwB7AQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Br='Braveharth:BAAALgAECgQJCwAAAA==.Braxus:BAAALgADCgYJCAAAAA==.Breakcooloz:BAACLgAFFH8KAAIPAAQJ/BlpAQB6AQAPAAQJ/BlpAQB6AQAuAAQKfyEAAg8ACAmnIyIBADQDAA8ACAmnIyIBADQDAAAA.Brooce:BAABLgAECn8VAAIQAAYJSSAtOwA3AgAQAAYJSSAtOwA3AgAAAA==.Broom:BAAALgADCgkJFAABLgAECgcJEwARAOMVAA==.',
Bu='Burstinurass:BAAALgAECgYJBgABLgAFFAQJCgAPAPwZAA==.',
Ca='Candyjar:BAAALgADCgcJBwAAAA==.Cantmissyou:BAAALgAECgEJAwAAAA==.Capidk:BAAALgAECgUJBgAAAA==.Carafe:BAAALgADCgEJAQABLgAECgYJCwAGAAAAAA==.Caspianne:BAAALgAECgQJBQAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAABLgAECn8WAAMDAAgJqQyFLQCPAQADAAgJqQyFLQCPAQASAAEJugFkXgAkAAAAAA==.Cellyne:BAAALgAECgUJCgAAAA==.Centy:BAAALgAECgUJCgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chaz:BAAALgAECgMJAwAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEALgAECgQJBwAAAA==.Chubrub:BAAALgAECgQJBQAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAQAAAA==.',
Cl='Claud:BAAALgADCgQJBAAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgEJBQAAAA==.Colanasou:BAAALgAECgEJAQAAAA==.Coldbattler:BAAALgAECgUJCQAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8hAAIQAAgJhyPADAAoAwAQAAgJhyPADAAoAwAAAA==.',
Da='Daarrkstar:BAAALgAECgQJBwABLgAECgYJCwAGAAAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darocate:BAAALgADCgYJBgAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAABLgAECn8nAAITAAkJShtsAQA+AgATAAkJShtsAQA+AgAAAA==.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAIRAAUJvBiHCACSAQARAAUJvBiHCACSAQAuAAQKfxQAAhEABwl0JOIUAIkCABEABwl0JOIUAIkCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgADCgkJDgAAAA==.Desniee:BAABLgAECn8gAAQUAAkJJB+IEQC2AQAUAAkJJB+IEQC2AQAVAAIJHA3hFAB4AAAWAAEJuxXADgA/AAAAAA==.Dethrone:BAAALgAECggJEgAAAA==.',
Di='Digitpro:BAABLgAECn8XAAIXAAYJfw5ZCAAqAQAXAAYJfw5ZCAAqAQAAAA==.Dirtydragon:BAAALgAECgYJDgAAAA==.Divinedecay:BAAALgAECgQJBwABLgAECggJHQAOAJERAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJDAAAAA==.Donos:BAAALgADCggJHgABLgADCgkJDAAGAAAAAA==.Dontkare:BAAALgADCgcJEQABLgAECggJHwAYAMwkAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgYJCgAGAAAAAA==.',
Dr='Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAAALgAECgUJCgAAAA==.Drark:BAAALgADCgQJBAAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Dreezee:BAAALgAECgIJBQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAAALgAECgUJDgAAAA==.Dràco:BAAALgADCgYJCAAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgYJBgAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
El='Elfadwagon:BAACLgAFFH8GAAIZAAQJ1RURBAAHAQAZAAQJ1RURBAAHAQAuAAQKfyMAAhkACAlcIa4CAAIDABkACAlcIa4CAAIDAAAA.Eliptical:BAAALgAECgYJEgABLgAECggJFwAQAIUeAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAAALgAECgEJAQAAAA==.Erdor:BAAALgADCgcJDgAAAA==.',
Es='Esmer:BAABLgAECn8WAAIQAAgJ+wQoHwA0AQAQAAgJ+wQoHwA0AQAAAA==.',
Et='Etheman:BAAALgAECgcJBgAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECgcJEgAGAAAAAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECgUJDQAGAAAAAA==.Evholker:BAAALgAECgYJDgAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAYJFQANAEoVAA==.Executey:BAAALgADCgQJBAAAAA==.',
Fa='Facestealerr:BAAALgAECgEJAQAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Felmufín:BAABLgAECn8UAAIJAAgJEgxIGABPAQAJAAgJEgxIGABPAQAAAA==.Felspury:BAAALgAECgEJAQABLgAECggJIgAVAAceAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAAALgAECgUJCgAAAA==.Flars:BAAALgAECgEJAQAAAA==.Flatliner:BAABLgAECn8pAAMaAAgJTg2RDAB2AQAaAAgJTg2RDAB2AQAQAAEJpQk3UwEqAAAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgcJEwARAOMVAA==.Fray:BAAALgAECgYJBgAAAA==.Freeguy:BAAALgAECgYJEAAAAA==.',
Fu='Fuddicus:BAABLgAECn8nAAMbAAcJ7yP8CgDNAgAbAAcJ7yP8CgDNAgAcAAEJGRIlgwA9AAAAAA==.Fuddmore:BAAALgAECgEJAQABLgAECgMJAwAGAAAAAA==.Fuddster:BAAALgAECgMJAwAAAA==.',
Ga='Gaddess:BAAALgAECgQJBwAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgQJAwAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAAALgAECggJCQAAAA==.',
Gi='Gimpy:BAAALgAECgQJBAAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgADCgkJEwAAAA==.',
Go='Gonefishing:BAABLgAECn8mAAIQAAgJpR9gFwDcAgAQAAgJpR9gFwDcAgAAAA==.Gorddownie:BAAALgAECgYJCgAAAA==.',
Gr='Grellior:BAAALgAECgEJAQAAAA==.Grippysocks:BAACLgAFFH8HAAIaAAMJHBUoBgD0AAAaAAMJHBUoBgD0AAAuAAQKfykAAhoACAlyGCoGAPUBABoACAlyGCoGAPUBAAAA.',
Gu='Gummibear:BAAALgAECgQJBwAAAA==.',
Ha='Hakar:BAAALgAECgEJAQAAAA==.Harthoon:BAACLgAFFH8HAAIUAAMJggdBFQDgAAAUAAMJggdBFQDgAAAuAAQKfykAAhQACAliGg8OANgBABQACAliGg8OANgBAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJCwAGAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgADCgEJAQAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCggJCAABLgAECggJHAAdAH0WAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAAALgAECgYJDAAAAA==.Hotdwarf:BAAALgAECgIJBAAAAA==.',
Hu='Hubbabubbles:BAAALgADCggJCAAAAA==.Hullkk:BAACLgAFFH8HAAINAAMJxhhUBAAfAQANAAMJxhhUBAAfAQAuAAQKfygAAw0ACAmiJZAFAE4DAA0ACAmcJZAFAE4DAB4AAQlDJPsOAGUAAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8aAAMJAAgJbRlILQBYAgAJAAgJbRlILQBYAgAIAAEJAACqCgAAAAAAAA==.Hutchknight:BAAALgAECgUJCgABLgAECggJGgAJAG0ZAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJGgAJAG0ZAA==.',
Hy='Hydro:BAABLgAECn8XAAIQAAcJIx2LPQAuAgAQAAcJIx2LPQAuAgAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgYJDgAGAAAAAA==.Inseng:BAAALgAECgIJAwAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAAALgAECgUJDgAAAA==.',
Ja='Jahde:BAAALgAECgYJDwAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgADCggJEAAAAA==.Jamer:BAAALgAECgMJCAAAAA==.Jassykins:BAAALgAECgUJCAAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgEJAQAAAA==.',
Ji='Jinjerr:BAAALgADCggJCAAAAA==.',
Jo='Joloc:BAABLgAECn8UAAIHAAYJwgiEBgDSAAAHAAYJwgiEBgDSAAAAAA==.Jozay:BAAALgAECgQJBAAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
['Jæ']='Jæ:BAAALgADCggJCAAAAA==.',
Ka='Kalasparkle:BAAALgAECgQJAwAAAA==.Kalrosa:BAAALgAECgQJCAABLgAECggJHgANAHcbAA==.Kare:BAABLgAECn8fAAIYAAgJzCRwAADCAgAYAAgJzCRwAADCAgAAAA==.Karee:BAAALgAECgYJEAABLgAECggJHwAYAMwkAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kermodrood:BAAALgAECgYJEwAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.',
Ki='Kiizo:BAAALgAECgQJCwAAAA==.Kilnot:BAAALgAECgcJEQAAAA==.Kinstine:BAAALgAECgYJDAAAAA==.',
Ko='Koltara:BAAALgAECgEJAQABLgAFFAMJBwALAIkfAA==.Koltaris:BAACLgAFFH8HAAILAAMJiR9OBgAQAQALAAMJiR9OBgAQAQAuAAQKfyEAAgsACAlyJJ8AAM4CAAsACAlyJJ8AAM4CAAAA.Konshis:BAABLgAECn8YAAIdAAcJGBROIgCiAQAdAAcJGBROIgCiAQAAAA==.Kookymonster:BAABLgAECn8hAAMJAAgJiyBaBAA+AgAHAAcJlh2ABwBPAgAJAAcJcBtaBAA+AgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAAALgAFFAMJAwAAAA==.',
Ku='Kuragaru:BAACLgAFFH8FAAMPAAIJgg5RBACsAAAPAAIJbwxRBACsAAAfAAIJigazFQCgAAAuAAQKfyIAAw8ACAmpHSUFAEICAA8ACAlqGiUFAEICAB8ACAnkGf4EAK4BAAAA.',
Ky='Kyoubouna:BAAALgAECgMJAwAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAAALgAECgQJCgAAAA==.Leretic:BAAALgADCgYJCgABLgAECggJFwAQAIUeAA==.Lerion:BAABLgAECn8XAAIQAAgJhR4dEgABAwAQAAgJhR4dEgABAwAAAA==.Lester:BAABLgAECn8WAAICAAYJvxcUCgBOAQACAAYJvxcUCgBOAQAAAA==.Lethana:BAAALgADCgcJDAAAAA==.',
Li='Liamsun:BAABLgAECn8nAAMdAAgJghThBADgAQAdAAgJghThBADgAQAKAAUJuhToPwAZAQAAAA==.Lidrael:BAABLgAECn8dAAQFAAgJGhsbBQBdAgAFAAgJGhsbBQBdAgAEAAYJNAX0QgDsAAAgAAYJewpAmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJAwAAAA==.Lightbloom:BAAALgAECgIJAgAAAA==.Liliria:BAABLgAECn8fAAIDAAgJPBb+GQAMAgADAAgJPBb+GQAMAgAAAA==.Lillidân:BAAALgAECgYJEQABLgAECggJHAAUALEbAA==.Litebite:BAAALgAECgUJBQAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAAALgAECgYJDwAAAA==.',
Ll='Lloreth:BAAALgAECgYJEQAAAA==.',
Ln='Lnpoop:BAAALgAECgQJBAAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAAALgAECgYJCAAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAAALgAECgQJBwAAAA==.Lorrellia:BAAALgAECgcJDgAAAA==.',
Lu='Lucariõ:BAACLgAFFH8RAAIDAAUJOxOHAgCDAQADAAUJOxOHAgCDAQAuAAQKfxYAAgMACAkXHpUNAH8CAAMACAkXHpUNAH8CAAAA.Lumina:BAAALgAECgUJCgAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAAALgAECgcJEgAAAA==.',
['Lì']='Lìght:BAABLgAECn8VAAIaAAYJ0xsoJgD2AQAaAAYJ0xsoJgD2AQAAAA==.',
Ma='Mahoney:BAAALgADCgIJBAAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAAALgAECgYJDAAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAAALgAECgUJCgAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marunji:BAAALgAECgYJCwAAAA==.Matcauthon:BAAALgAECgIJAwAAAA==.Matrim:BAAALgAECgQJBQAAAA==.Mattdæmon:BAAALgAECgYJEwAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn8bAAIbAAgJ6x3rEACQAgAbAAgJ6x3rEACQAgAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgADCgEJAgABLgAECgcJGgAOAPomAA==.Mimzy:BAAALgAECgEJAgAAAA==.Mingzi:BAAALgAECgUJCgAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAQABLgAECggJGAAZAJATAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAQJCgAQABoPAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAAALgAECgUJDQAAAA==.Moonsocks:BAAALgADCgEJAQABLgAFFAMJBwAaABwVAA==.Moxxie:BAAALgAECgQJBgAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAAALgAECgYJEgAAAA==.Murica:BAAALgADCgEJAQABLgAECgcJEwARAOMVAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8HAAIgAAMJchE3DQDzAAAgAAMJchE3DQDzAAAuAAQKfykAAyAACAkxHh0cAKoCACAACAkxHh0cAKoCAAQABgn7EBg2AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAMJBwAaABwVAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8VAAIbAAYJdQr7VwAoAQAbAAYJdQr7VwAoAQAAAA==.Nashness:BAABLgAECn8lAAIMAAgJziMEEAAdAwAMAAgJziMEEAAdAwAAAA==.Natharion:BAABLgAECn8nAAMIAAgJMRmVAgCTAgAIAAgJMRmVAgCTAgAJAAYJnQONtQDtAAAAAA==.Nazrogul:BAABLgAECn8VAAIMAAYJXwg/sgAeAQAMAAYJXwg/sgAeAQAAAA==.',
Ne='Nezar:BAAALgADCgcJEQAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8JAAIKAAQJihChAgAWAQAKAAQJihChAgAWAQAuAAQKfyIAAwoACAnLH9kJANoCAAoACAnLH9kJANoCAAsAAQkmCC+VACAAAAAA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgADCgcJBwABLgAECggJIwAbAEMZAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAAALgAECgUJCgAAAA==.',
No='Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nullthor:BAAALgAECgYJDgAAAA==.Nurfd:BAAALgAECgYJDgAAAA==.',
['Nè']='Nègan:BAABLgAECn8jAAIOAAcJFxT/NADbAQAOAAcJFxT/NADbAQAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgQJBAABLgAECggJHwAYAMwkAA==.',
Od='Odinrex:BAAALgAECgkJDgAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Op='Opuntia:BAAALgAECgEJAQAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn8TAAMRAAcJ4xW5LQDAAQARAAcJ4xW5LQDAAQAXAAEJXwmILgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Ownown:BAAALgAECgIJAgABLgAECgcJGgAOAPomAA==.',
Pa='Pallypaladin:BAACLgAFFH8KAAIQAAQJGg9mFgD4AAAQAAQJGg9mFgD4AAAuAAQKfxcAAhAACAm/IBkgAKsCABAACAm/IBkgAKsCAAAA.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8mAAIgAAcJ3xuyFQBQAQAgAAcJ3xuyFQBQAQAAAA==.',
Ph='Phatzero:BAABLgAECn8dAAIOAAgJkRHpDgCMAQAOAAgJkRHpDgCMAQAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJIAADAD4YAA==.Piety:BAAALgADCgMJAQAAAA==.Pinjo:BAAALgAECgEJAQAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECgYJFQAUADgVAA==.Polarr:BAABLgAECn8VAAIUAAYJOBVJzwBNAQAUAAYJOBVJzwBNAQAAAA==.Popsicles:BAAALgAECgUJBQAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Proofy:BAAALgAECgcJDgAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.',
Ps='Psyop:BAAALgADCgcJDwABLgAECgMJBAAGAAAAAA==.',
Pu='Punchkick:BAAALgADCgcJBwAAAA==.Punchup:BAAALgAECgcJDwAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgADCggJAwAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.',
Re='Rebrex:BAAALgADCgcJBwAAAA==.Redpyro:BAAALgADCgcJDgAAAA==.Retrïbutor:BAAALgADCgYJBgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAAALgAECgUJCQAAAA==.',
Ri='Rinela:BAABLgAECn8fAAIhAAgJDRz1GQA2AgAhAAgJDRz1GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAAALgAECgcJEwAAAA==.',
Ro='Robi:BAAALgADCgEJAQABLgAECgYJCwAGAAAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAAALgAECgYJDQAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCAAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAYJFAAUAIIdAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAAALgAECgYJBgABLgAFFAYJFAAUAIIdAA==.',
['Ró']='Rónin:BAAALgAECgMJCQAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Sanzen:BAABLgAECn8VAAMKAAYJsRu5IgDAAQAKAAYJsRu5IgDAAQAdAAMJsgfOWABsAAAAAA==.Sauce:BAABLgAECn8cAAIdAAgJfRZfAwAaAgAdAAgJfRZfAwAaAgAAAA==.',
Sc='Scrubz:BAABLgAECn8ZAAIiAAgJ8xzSBwA2AgAiAAgJ8xzSBwA2AgAAAA==.',
Se='Senile:BAAALgAECgUJCgAAAA==.Seydori:BAAALgADCgUJCwAAAA==.',
Sh='Shadylid:BAAALgAECggJEQAAAA==.Shadówglider:BAAALgAECgEJAQAAAA==.Shale:BAAALgAECgYJEgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgADCgYJDgAAAA==.Shreck:BAAALgAECgEJAQAAAA==.',
Sk='Skikette:BAAALgADCggJFAAAAA==.Skinrot:BAABLgAECn8dAAIjAAcJMQpwGQDvAAAjAAcJMQpwGQDvAAAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAAALgAECgUJCgAAAA==.Soullove:BAABLgAECn8jAAIHAAcJMxZxEADLAQAHAAcJMxZxEADLAQAAAA==.Soullovez:BAAALgAECgYJCgABLgAECgcJIwAHADMWAA==.Soulshocks:BAABLgAECn8aAAIcAAYJKgpnSQAiAQAcAAYJKgpnSQAiAQABLgAECgcJIwAHADMWAA==.Soulviver:BAAALgAECgYJEwAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAABLgAECn8iAAMVAAgJBx48AwBGAgAVAAgJNRo8AwBGAgAUAAgJuBV5KQAnAQAAAA==.Spurylock:BAAALgADCgMJAwABLgAECggJIgAVAAceAA==.',
St='Starstreak:BAAALgADCgUJBQABLgAECgYJGAAUABcSAA==.Stimer:BAABLgAECn8kAAMNAAkJchy0BgA8AwANAAkJchy0BgA8AwAeAAcJFRI2BABfAQAAAA==.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAAALgAECgUJDwAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.',
Sw='Swan:BAABLgAECn8UAAMUAAcJig+HoQCUAQAUAAcJig+HoQCUAQAWAAMJBwRLDABpAAABLgAECggJHgAXAFgeAA==.Swordboardal:BAAALgAFFAIJAgAAAA==.',
Sy='Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgUJBQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgEJAgAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takia:BAAALgAECgEJAQAAAA==.Talanzen:BAABLgAECn8aAAIUAAgJ7BswCgAIAgAUAAgJ7BswCgAIAgAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECggJEQAGAAAAAA==.',
Te='Teacup:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8HAAIdAAMJiBdjBgDZAAAdAAMJiBdjBgDZAAAuAAQKfykAAh0ACAlXHgwOAHYCAB0ACAlXHgwOAHYCAAAA.Thunderhorns:BAAALgAECgQJBgAAAA==.Thundrall:BAAALgADCgUJCgAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAMJBwAaABwVAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgIJAgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgEJAQAAAA==.Treeåj:BAAALgAECgYJCgAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8VAAMNAAYJShU6BACxAQANAAUJfxo6BACxAQAeAAEJcwBZBwA6AAAuAAQKfxwAAg0ACAneIokIACMDAA0ACAneIokIACMDAAAA.',
Ts='Tsuo:BAACLgAFFH8HAAIiAAMJNh1VAQAEAQAiAAMJNh1VAQAEAQAuAAQKfykAAiIACAmdJTAAAOsCACIACAmdJTAAAOsCAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgAMANEdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAAALgAECgEJAQAAAA==.Tyrick:BAAALgAECgcJDAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8GAAMJAAMJTAzVGQChAAAJAAIJgwjVGQChAAAHAAEJ3xMSBQBYAAAuAAQKfyIABAcACAksIfYIADECAAcABwnpHfYIADECAAkACAnPGx88ABwCAAgAAQmWHSooAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Va='Vache:BAAALgADCgQJBAAAAA==.Valartha:BAAALgAECgEJAQAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJDAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECgcJEgAGAAAAAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgEJAgAAAA==.Velstadt:BAABLgAECn8WAAIKAAYJxBtOCABSAQAKAAYJxBtOCABSAQAAAA==.Venhance:BAAALgAECgYJEAAAAA==.Venotu:BAABLgAECn8UAAIBAAcJXhjFDAD7AQABAAcJXhjFDAD7AQAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgUJEAAAAQ==.',
Vo='Voidherron:BAAALgAECgUJCQAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgIJAgAAAA==.Vonzilla:BAAALgAECgYJDQAAAA==.Vorthael:BAAALgAECgMJBgAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warmongral:BAAALgAECgYJDwAAAA==.Waterboot:BAAALgAECgQJBAAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAAALgAECgYJDgAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgcJEwARAOMVAA==.',
Wi='Wingsaber:BAABLgAECn8iAAIQAAgJFRBAFAB/AQAQAAgJFRBAFAB/AQAAAA==.Withher:BAAALgADCgcJBwAAAA==.',
Wo='Wombo:BAABLgAECn8UAAIPAAYJvR/lAQCgAQAPAAYJvR/lAQCgAQAAAA==.Woolala:BAAALgADCgcJBwABLgAECggJJgAQAKUfAA==.',
Wr='Wrathran:BAAALgAECgUJCQAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECggJHAAdAH0WAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAABLgAECn8XAAIaAAgJRRK9KgDdAQAaAAgJRRK9KgDdAQAAAA==.Yazmyn:BAAALgAECgYJDAAAAA==.',
Ye='Yerehmi:BAAALgAECgEJAQAAAA==.',
Yu='Yuny:BAAALgAECgcJEwAAAA==.',
Yv='Yvendria:BAAALgAECgYJDwAAAA==.',
Za='Zacnafeen:BAAALgADCgcJBwAAAA==.Zaelessa:BAAALgAECgMJAwABLgAECgUJEAAGAAAAAQ==.Zaier:BAABLgAECn8qAAIaAAgJtCQCAwBFAwAaAAgJtCQCAwBFAwAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.',
Ze='Zeltan:BAAALgAECgYJDwAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAAALgAECgEJAQAAAA==.',
Zi='Zinik:BAAALgADCgEJAQAAAA==.',
Zo='Zolt:BAAALgAECgcJDQAAAA==.Zoma:BAAALgADCgEJAQAAAA==.',
Zu='Zugzeal:BAAALgADCgYJBAAAAA==.',
['Zï']='Zïggy:BAAALgAECgYJBwAAAA==.',
['År']='Åres:BAAALgADCgEJAQAAAA==.',
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

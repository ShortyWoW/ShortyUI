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

local lookup = {'Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DemonHunter-Devourer','Druid-Restoration','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Priest-Discipline','Warrior-Fury','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Rogue-Subtlety','DeathKnight-Frost','Druid-Feral','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abogato:BAAALgAECgQJBAAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECgcJDQAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAAALgAECggJEgAAAA==.Ahnkhano:BAABLgAECn8dAAIBAAgJ8RFgEgCjAQABAAgJ8RFgEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akashaa:BAAALgADCgEJAQAAAA==.Akbartheiiv:BAACLgAFFH8UAAICAAcJcBW3AQACAgACAAcJcBW3AQACAgAuAAQKfy0AAgIACQlWI0sBAC0DAAIACQlWI0sBAC0DAAAA.',
Al='Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8iAAIDAAkJBRw0EwBGAgADAAkJBRw0EwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAAALgAECgQJCAAAAA==.Ambiorix:BAAALgADCgEJAQAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJAQAAAA==.Anrion:BAABLgAECn8cAAMEAAkJiSFxBgABAwAEAAkJiSFxBgABAwAFAAcJSxuwBADbAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAGAAAAAA==.',
Ap='Aph:BAAALgAECgcJDAAAAA==.Apolló:BAAALgAECgkJCwAAAA==.',
Ar='Araiana:BAAALgAECgEJAQAAAA==.Arayia:BAAALgAECgYJEAAAAA==.Arelian:BAABLgAECn8YAAMFAAgJqRP+CABNAQAFAAYJmhb+CABNAQAHAAgJMQvzZgDPAAAAAA==.Aristia:BAABLgAECn8UAAMIAAcJYiORFgAQAgAIAAcJYiORFgAQAgAJAAEJzwwrVwA0AAABLgADCgYJCgAGAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAAALgAECgYJDgAAAA==.Aurilia:BAAALgAECgQJCAAAAA==.',
Av='Avanicus:BAABLgAECn8kAAQKAAkJhgqmCwAaAQAKAAcJbwmmCwAaAQALAAUJKApkCgDnAAAMAAQJqAOWtgBYAAAAAA==.Aven:BAABLgAECn8WAAMNAAcJ2wrHXAAsAQANAAcJbgrHXAAsAQAOAAUJ7wQyKQCBAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8cAAMPAAgJgSSxDgCSAgAPAAcJoyKxDgCSAgAQAAUJWCJiFgCFAQAAAA==.',
Ay='Ayroon:BAAALgAECgQJBAAAAA==.',
Az='Azulien:BAABLgAECn8aAAIRAAYJFAPCKQDbAAARAAYJFAPCKQDbAAAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAINAAgJ0R3TJgCgAgANAAgJ0R3TJgCgAgAAAA==.Banderblitz:BAABLgAECn8sAAISAAgJWyBnBgCKAgASAAgJWyBnBgCKAgAAAA==.Baobei:BAAALgADCgcJBwAAAA==.Bar:BAACLgAFFH8GAAMCAAMJ+wXpEQCOAAACAAMJ+wXpEQCOAAADAAMJkhFsFwCEAAAuAAQKfxsAAgIACAlCGiIVAEMCAAIACAlCGiIVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJIgAHAGgSAA==.Bellatrixie:BAAALgADCggJFQAAAA==.Benafflock:BAAALgAECgQJDQABLgAECgcJEgAGAAAAAA==.Beriadhwen:BAAALgAECgQJBQAAAA==.Bermy:BAABLgAECn8VAAIKAAcJMA4YJQAzAQAKAAcJMA4YJQAzAQAAAA==.Bewildert:BAAALgADCgEJAQAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8fAAINAAgJ6RiAKgDSAQANAAgJ6RiAKgDSAQAAAA==.Blende:BAABLgAECn8XAAITAAYJ6yG9JQDrAQATAAYJ6yG9JQDrAQAAAA==.Bloodshadow:BAABLgAECn8fAAIUAAgJ4xGXMwB/AQAUAAgJ4xGXMwB/AQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Bo='Boidohanta:BAAALgADCgUJBQAAAA==.Bondarrex:BAAALgADCgYJBgAAAA==.',
Br='Braveharth:BAAALgAECgYJEAAAAA==.Braxus:BAAALgAECgMJBAAAAA==.Breakcooloz:BAACLgAFFH8QAAIVAAUJHSE1AQCQAQAVAAUJHSE1AQCQAQAuAAQKfyIAAhUACAmnIyEBADQDABUACAmnIyEBADQDAAAA.Brooce:BAABLgAECn8kAAITAAgJyx2AEwBeAgATAAgJyx2AEwBeAgAAAA==.Broom:BAAALgADCgkJHQABLgAECgkJJAAWACYdAA==.',
Bu='Burstinurass:BAACLgAFFH8MAAINAAUJsSMbDgCeAQANAAUJsSMbDgCeAQAuAAQKfxYAAg0ACAmnJSsHAOkCAA0ACAmnJSsHAOkCAAEuAAUUBQkQABUAHSEA.',
Ca='Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBQAAAA==.Capidk:BAAALgAECgUJBgAAAA==.Carafe:BAAALgADCgEJAQABLgAECgUJBgAGAAAAAA==.Carbonight:BAAALgADCgEJAQAAAA==.Carlos:BAAALgAECgUJCAAAAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAABLgAECn8fAAMDAAgJOBg9DAAiAgADAAgJOBg9DAAiAgARAAEJugFoXgAkAAAAAA==.Cellyne:BAABLgAECn8UAAMTAAYJfQWIjgDQAAATAAYJfQWIjgDQAAAXAAIJJALeWwBBAAAAAA==.Centy:BAAALgAECgYJEgAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chaz:BAAALgAECgQJCQAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEALgAECgYJEwAAAA==.Chubrub:BAAALgAECgUJCwAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgADCgcJCwAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgQJCAAAAA==.Colanasou:BAAALgAECgQJBgAAAA==.Coldbattler:BAAALgAECgYJDwAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8iAAITAAgJhyPCDAAoAwATAAgJhyPCDAAoAwAAAA==.',
Da='Daarrkstar:BAAALgAECgYJEwABLgAECgYJFwATAOshAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darkane:BAABLgAFFH8FAAMUAAUJGwIjMQDBAAAUAAQJrQIjMQDBAAAWAAEJZgAYHwAwAAAAAA==.Darocate:BAAALgADCgYJBgAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8JAAIOAAMJrBE4EwDEAAAOAAMJrBE4EwDEAAAuAAQKfzgAAg4ACQlOILQBAPUCAA4ACQlOILQBAPUCAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAIWAAUJvBiRCACSAQAWAAUJvBiRCACSAQAuAAQKfxQAAhYABwl0JBUVAIoCABYABwl0JBUVAIoCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgADCgkJEQAAAA==.Desniee:BAABLgAECn8gAAQYAAkJMh9vQwBuAgAYAAkJMh9vQwBuAgAZAAIJHA3iFAB3AAAaAAEJuxW/DgA/AAAAAA==.Dethrone:BAAALgAECggJEwAAAA==.',
Di='Digitpro:BAABLgAECn8mAAIbAAgJvg0aEACoAQAbAAgJvg0aEACoAQAAAA==.Dirtydragon:BAABLgAECn8dAAMcAAgJTRtHBAByAgAcAAgJTRtHBAByAgAdAAEJhwdZZQArAAAAAA==.Disturbo:BAAALgADCgYJBgAAAA==.Divinedecay:BAAALgAECgYJDQABLgAECgkJLQAUAFoUAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJGAABLgADCgkJJAAGAAAAAA==.Donos:BAAALgADCgkJJAAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJKAAeAEUlAA==.Doomjuele:BAAALgADCgYJBgAAAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECggJEgAGAAAAAA==.',
Dr='Draazzy:BAAALgADCgkJCQAAAA==.Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAABLgAECn8UAAIcAAYJ2RtHCADlAQAcAAYJ2RtHCADlAQAAAA==.Drark:BAAALgADCgQJBAAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Dreezee:BAAALgAECgIJBQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAABLgAECn8aAAIYAAYJshY3VABvAQAYAAYJshY3VABvAQAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
El='Elfadwagon:BAACLgAFFH8NAAIfAAQJ2BeXAQBZAQAfAAQJ2BeXAQBZAQAuAAQKfyQAAh8ACAlcIa8CAAIDAB8ACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJGwATAO4eAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCggJCQAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAAALgAECgQJCAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8oAAITAAkJJwrFMwCuAQATAAkJJwrFMwCuAQAAAA==.',
Et='Etheman:BAAALgAECgcJBgAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECggJFAAgANMhAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECgYJGQABAFYgAA==.Evholker:BAABLgAECn8VAAMfAAcJxBA4GQBsAQAfAAcJshA4GQBsAQAdAAUJlA6ZMQDeAAAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAYJIAASALUaAA==.Executey:BAAALgADCgQJBAAAAA==.Exhumina:BAAALgAECgUJBQAAAA==.',
Fa='Facestealerr:BAAALgAECgQJCAAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Feetsmell:BAAALgADCgkJCQABLgAECgkJJAAWACYdAA==.Felmufín:BAABLgAECn8cAAIMAAgJQQzKPQBxAQAMAAgJQQzKPQBxAQAAAA==.Felspury:BAAALgAECgEJAQABLgAECgkJLwAZAPoeAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAABLgAECn8UAAISAAYJiBquGQCZAQASAAYJiBquGQCZAQAAAA==.Flars:BAAALgAECgcJCgAAAA==.Flatliner:BAABLgAECn85AAMXAAgJNQ5bIACEAQAXAAgJNQ5bIACEAQATAAEJpQlXUwEqAAAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECgkJJAAWACYdAA==.Fray:BAABLgAECn8VAAIHAAgJNhbzGwDhAQAHAAgJNhbzGwDhAQAAAA==.Freeguy:BAABLgAECn8cAAIHAAgJphpJFQASAgAHAAgJphpJFQASAgAAAA==.',
Fu='Fuddicus:BAABLgAECn83AAMgAAgJ3CTXBwCwAgAgAAgJ3CTXBwCwAgAhAAEJGRI3gwA9AAAAAA==.Fuddmore:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Fuddster:BAAALgAECgQJBwAAAA==.',
Ga='Gaddess:BAAALgAECgYJEwAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJCAAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAABLgAECn8XAAIXAAgJyxwZCQCAAgAXAAgJyxwZCQCAAgAAAA==.',
Gi='Gimpy:BAAALgAECgQJBQAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgAECgIJAgAAAA==.',
Go='Gonefishing:BAABLgAECn8yAAITAAkJ5CAoCgC3AgATAAkJ5CAoCgC3AgAAAA==.Gorddownie:BAAALgAECgYJEAAAAA==.',
Gr='Grellior:BAAALgAECgEJAQAAAA==.Grippysocks:BAACLgAFFH8MAAIXAAUJcRkuCACZAQAXAAUJcRkuCACZAQAuAAQKfzMAAhcACAnKGBAcADQCABcACAnKGBAcADQCAAAA.',
Gu='Gummibear:BAAALgAECgYJDQAAAA==.',
Ha='Hakar:BAAALgAECgIJAgAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8PAAIYAAUJtAxzNAA+AQAYAAUJtAxzNAA+AQAuAAQKfzkAAhgACAnIHo0XAF8CABgACAnIHo0XAF8CAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAGAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgADCgEJAQAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJGgABLgAECgkJJQAiAHQXAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAABLgAECn8XAAIDAAYJ4gVlLgDaAAADAAYJ4gVlLgDaAAAAAA==.Honks:BAAALgAECgEJAQAAAA==.Hotdwarf:BAAALgAECgYJCgAAAA==.',
Hu='Hubbabubbles:BAAALgADCggJCAAAAA==.Hullkk:BAACLgAFFH8PAAMjAAUJxBlACAAjAQASAAQJ7xL2EAArAQAjAAQJ0h9ACAAjAQAuAAQKfzcAAyMACAmKJmcBAOMCABIACAnOJYoFAE4DACMABwkPJGcBAOMCAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8kAAMMAAgJ0xtHLQBYAgAMAAgJ0xtHLQBYAgALAAEJAAArHQAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJJAAMANMbAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJJAAMANMbAA==.',
Hy='Hydro:BAABLgAECn8gAAITAAcJgB6EPQAuAgATAAcJgB6EPQAuAgAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECggJHQAUACcWAA==.Inseng:BAAALgAECgYJDwAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAABLgAECn8WAAIHAAgJjxczGQDzAQAHAAgJjxczGQDzAQAAAA==.',
Ja='Jahde:BAABLgAECn8bAAIIAAYJRAs3RgD6AAAIAAYJRAs3RgD6AAAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgAECgQJBAAAAA==.Jamer:BAAALgAECgUJEQAAAA==.Jassykins:BAAALgAECgYJEAAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgQJBQAAAA==.',
Ji='Jinjerr:BAAALgAECgYJCgAAAA==.',
Jo='Joloc:BAABLgAECn8UAAIKAAYJwghEEgDDAAAKAAYJwghEEgDDAAAAAA==.Jozay:BAAALgAECgYJCwAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kaidaa:BAAALgAECgQJBAAAAA==.Kalasparkle:BAAALgAECgQJAwAAAA==.Kalrosa:BAABLgAECn8UAAISAAYJZCFJEwDTAQASAAYJZCFJEwDTAQABLgAECggJLAASAFsgAA==.Kare:BAABLgAECn8oAAIeAAkJRSWuAABDAwAeAAkJRSWuAABDAwAAAA==.Karee:BAAALgAECgYJEAABLgAECgkJKAAeAEUlAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAGAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kermodrood:BAABLgAECn8iAAIJAAgJkyIBBAC+AgAJAAgJkyIBBAC+AgAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.Kholdbrew:BAAALgAECgUJBQAAAA==.',
Ki='Kiizo:BAABLgAECn8XAAIkAAYJoxX8FQBaAQAkAAYJoxX8FQBaAQAAAA==.Kilnot:BAAALgAECgcJEgAAAA==.Kinstine:BAABLgAECn8VAAIOAAYJ/wFIMgCtAAAOAAYJ/wFIMgCtAAAAAA==.',
Ko='Koltara:BAAALgAFFAEJAQABLgAFFAQJCwAQAP8dAA==.Koltaris:BAACLgAFFH8LAAIQAAQJ/x2RCwBaAQAQAAQJ/x2RCwBaAQAuAAQKfyIAAhAACAlyJGYDAMYCABAACAlyJGYDAMYCAAAA.Konshis:BAABLgAECn8iAAIiAAgJ+xQnGACQAQAiAAgJ+xQnGACQAQAAAA==.Kookymonster:BAABLgAECn8xAAMMAAkJoyF0BAADAwAMAAgJ0iB0BAADAwAKAAcJlh2BBwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAACLgAFFH8LAAMNAAUJ/QyMMwA3AQANAAQJ/QyMMwA3AQAOAAEJAACCMAAAAAAuAAQKfxcAAw0ACAl6H9MRAG0CAA0ACAl6H9MRAG0CACUAAgmaGZEOAJcAAAAA.',
Ku='Kuragaru:BAACLgAFFH8NAAMkAAUJPBzRBgBzAQAkAAUJPBzRBgBzAQAVAAIJbwxUBACsAAAuAAQKfzEAAyQACAmzJNYBAPACACQACAmzJNYBAPACABUACAlqGiYFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgMJAwAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAABLgAECn8VAAIJAAYJvwUSMgDIAAAJAAYJvwUSMgDIAAAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJGwATAO4eAA==.Lerion:BAABLgAECn8bAAITAAgJ7h4dEgABAwATAAgJ7h4dEgABAwAAAA==.Lester:BAABLgAECn8iAAICAAgJxhlVCQAvAgACAAgJxhlVCQAvAgAAAA==.Lethana:BAAALgADCgcJDAAAAA==.',
Li='Liamsun:BAABLgAECn82AAQiAAkJpRNyDgAEAgAiAAkJpRNyDgAEAgAQAAgJShaRDQDtAQAPAAUJuhTsPwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn8qAAQFAAkJsBsYAwAuAgAFAAkJsBsYAwAuAgAEAAYJNAX7QgDsAAAHAAYJewpNmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJCAAAAA==.Lightbloom:BAAALgAECgIJBAAAAA==.Liliria:BAABLgAECn8xAAIDAAkJWhi3CgA7AgADAAkJWhi3CgA7AgAAAA==.Lillidân:BAAALgAECgYJEQABLgAFFAIJBQAYABkVAA==.Litebite:BAAALgAECgUJBQAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAABLgAECn8aAAICAAgJ5BfDDAD7AQACAAgJ5BfDDAD7AQAAAA==.',
Ll='Lloreth:BAABLgAECn8YAAIIAAcJRwo5PwAXAQAIAAcJRwo5PwAXAQAAAA==.',
Ln='Lnpoop:BAAALgAECgYJDAAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAABLgAECn8WAAIkAAgJnwfyFABnAQAkAAgJnwfyFABnAQAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAAALgAECgYJEwAAAA==.Lorrellia:BAAALgAECgcJDgAAAA==.',
Lu='Lucariõ:BAACLgAFFH8TAAIDAAYJXBUPAgDVAQADAAYJXBUPAgDVAQAuAAQKfxYAAgMACAkXHpINAH8CAAMACAkXHpINAH8CAAAA.Lumina:BAAALgAECgYJDwAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.Lustydragon:BAAALgADCgEJAQAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAABLgAECn8UAAIgAAgJ0yF1CACkAgAgAAgJ0yF1CACkAgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8KAAIXAAQJPRxuDwA7AQAXAAQJPRxuDwA7AQAuAAQKfyAAAhcABwnBH5IPACQCABcABwnBH5IPACQCAAAA.',
Ma='Madrona:BAAALgAECgEJAQAAAA==.Magnumrex:BAAALgADCgUJBQAAAA==.Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8bAAINAAgJfBd6JADxAQANAAgJfBd6JADxAQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAABLgAECn8UAAIhAAYJcARgOgDDAAAhAAYJcARgOgDDAAAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marrok:BAAALgAECgcJBwAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgQJCAAAAA==.Matrim:BAAALgAECgQJBQAAAA==.Mattdæmon:BAABLgAECn8bAAMEAAcJHwtdFgA0AQAEAAcJHwtdFgA0AQAHAAIJpwK72AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.Mazzak:BAAALgADCgMJAwAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn8rAAIgAAgJJCLmBgDCAgAgAAgJJCLmBgDCAgAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.Melestaris:BAAALgADCgYJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgAFFAIJAwABLgAFFAMJCgAUAP8mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Minarmo:BAAALgADCgEJAQAAAA==.Mingzi:BAAALgAECgYJDwAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAgABLgAECggJHQAfADYSAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAUJEwATAPcUAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUIAAYJcgvvQwADAQAIAAYJcgvvQwADAQAJAAUJpwLPZACOAAAmAAIJoxJeKgB1AAAnAAEJJxphLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAUJDAAXAHEZAA==.Moxxie:BAAALgAECgYJEAAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8VAAMCAAcJXRgvIwC+AQACAAcJXRgvIwC+AQADAAQJWgx/WQDOAAAAAA==.Murica:BAAALgADCgEJAQABLgAECgkJJAAWACYdAA==.',
My='Mythosrex:BAAALgAECgcJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8NAAIHAAUJEBSVHQA0AQAHAAUJEBSVHQA0AQAuAAQKfzIAAwcACAlcITAKAIYCAAcACAlcITAKAIYCAAQABgn7EBk2AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAUJDAAXAHEZAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8dAAIgAAgJSgncMwA9AQAgAAgJSgncMwA9AQAAAA==.Nashness:BAABLgAECn8yAAMNAAkJDiMEEAAdAwANAAkJDiMEEAAdAwAlAAEJ1CP7EABpAAAAAA==.Natharion:BAABLgAECn82AAMLAAkJghiVAgCTAgALAAkJdBiVAgCTAgAMAAgJWAjTSgBIAQAAAA==.Nazrogul:BAABLgAECn8VAAINAAYJXwg1sgAeAQANAAYJXwg1sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgYJBwAAAA==.Nezar:BAAALgADCgcJEQAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAIPAAQJihC+DAANAQAPAAQJihC+DAANAQAuAAQKfyIAAw8ACAnLH9kJANoCAA8ACAnLH9kJANoCABAAAQkmCD2VACAAAAEuAAUUBQkFABQAGwIA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAABLgAECgkJMQAgALcdAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAABLgAECn8UAAInAAYJqQ1kFQC+AAAnAAYJqQ1kFQC+AAAAAA==.',
No='Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nu:BAAALgADCgkJCQAAAA==.Nuckinphutz:BAAALgADCgUJBQAAAA==.Nullthor:BAABLgAECn8UAAIoAAYJ7xORDQAtAQAoAAYJ7xORDQAtAQAAAA==.Nurfd:BAABLgAECn8UAAIeAAYJbwEjJwCHAAAeAAYJbwEjJwCHAAAAAA==.',
['Nè']='Nègan:BAABLgAECn8rAAIUAAgJ0hSaLACcAQAUAAgJ0hSaLACcAQAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgYJDQABLgAECgkJKAAeAEUlAA==.',
Od='Odinrex:BAABLgAECn8VAAIUAAYJThT0QABLAQAUAAYJThT0QABLAQAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Op='Opuntia:BAAALgAECgQJBQAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn8kAAMWAAkJJh1kAQCyAgAWAAkJJh1kAQCyAgAbAAEJXwmPLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAMJCgAUAP8mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8TAAITAAUJ9xR+GQBGAQATAAUJ9xR+GQBGAQAuAAQKfxkAAhMACQmqHxAgAKwCABMACQmqHxAgAKwCAAAA.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAIHAAcJ8hvNRADgAQAHAAcJ8hvNRADgAQAAAA==.',
Ph='Phatzero:BAABLgAECn8tAAMUAAkJWhTfFwARAgAUAAkJWhTfFwARAgAWAAIJMgQ+IwBFAAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJLgADAD4YAA==.Pierogi:BAAALgADCgUJBQAAAA==.Piety:BAAALgAECgIJAgAAAA==.Pinjo:BAAALgAECgEJAwAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECgcJFgAYAB8VAA==.Polarr:BAABLgAECn8WAAIYAAcJHxVZzwBNAQAYAAcJHxVZzwBNAQAAAA==.Popsicles:BAAALgAECgUJBQAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgYJCQAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.',
Ps='Psyop:BAAALgADCgkJEQABLgAECgcJCwAGAAAAAA==.',
Pu='Punchkick:BAAALgADCgcJBwAAAA==.Punchup:BAABLgAECn8WAAIPAAcJ/gnFIAAgAQAPAAcJ/gnFIAAgAQAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgMJAwAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJBwAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Ren:BAAALgAECgEJAQAAAA==.Retrïbutor:BAAALgAECgYJCgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAAALgAECgYJEwAAAA==.',
Ri='Rinela:BAABLgAECn8fAAIJAAgJDRz1GQA2AgAJAAgJDRz1GQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8dAAIIAAcJoCGbCgCfAgAIAAcJoCGbCgCfAgAAAA==.',
Ro='Robi:BAAALgADCgEJAQABLgAECgYJFwATAOshAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8aAAIDAAcJeQhUJQAfAQADAAcJeQhUJQAfAQAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Rt='Rtfreshness:BAAALgAECgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCQAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAcJGwAYAGIdAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAAALgAECgYJBgABLgAFFAcJGwAYAGIdAA==.',
['Ró']='Rónin:BAAALgAFFAEJAQAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Sanzen:BAABLgAECn8ZAAMPAAYJsRu6IgDAAQAPAAYJsRu6IgDAAQAiAAMJsgcTWQBqAAAAAA==.Sauce:BAABLgAECn8lAAIiAAkJdBcoCQBfAgAiAAkJdBcoCQBfAgAAAA==.',
Sc='Scrubz:BAABLgAECn8ZAAInAAgJ8xzVBwA2AgAnAAgJ8xzVBwA2AgAAAA==.',
Se='Senile:BAABLgAECn8UAAIaAAYJExGwAwBEAQAaAAYJExGwAwBEAQAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadydice:BAAALgADCgYJBgABLgAECgkJIgAHAGgSAA==.Shadylid:BAABLgAECn8iAAMHAAkJaBLeGwDiAQAHAAkJaBLeGwDiAQAFAAMJVQniFQBzAAAAAA==.Shadówglider:BAAALgAECgQJCAAAAA==.Shale:BAABLgAECn8VAAIHAAcJRiHvOgAIAgAHAAcJRiHvOgAIAgAAAA==.Shamallaman:BAAALgAECgEJAQABLgAECgkJIgATANgjAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgMJAwAAAA==.Shreck:BAAALgAECgQJBgAAAA==.',
Sk='Skikette:BAAALgADCggJIQAAAA==.Skinrot:BAABLgAECn8nAAIIAAgJTQuLPwAVAQAIAAgJTQuLPwAVAQAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAABLgAECn8UAAIKAAYJpwuHDgDrAAAKAAYJpwuHDgDrAAAAAA==.Solux:BAAALgAFFAMJAwABLgAFFAUJCQAKABgLAA==.Soullove:BAABLgAECn81AAIKAAgJ0hSBBQClAQAKAAgJ0hSBBQClAQAAAA==.Soullovez:BAABLgAECn8UAAIJAAYJ6AliLwDWAAAJAAYJ6AliLwDWAAABLgAECggJNQAKANIUAA==.Soulshocks:BAABLgAECn8pAAIhAAgJ1QwOHgBdAQAhAAgJ1QwOHgBdAQABLgAECggJNQAKANIUAA==.Soulviver:BAABLgAECn8iAAIDAAgJ3ww3GwBxAQADAAgJ3ww3GwBxAQAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spicytuna:BAAALgADCgYJBgAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAABLgAECn8vAAMZAAkJ+h46AwBFAgAZAAgJNRo6AwBFAgAYAAkJxxlQMADfAQAAAA==.Spurylock:BAAALgADCgcJBwABLgAECgkJLwAZAPoeAA==.',
St='Starstreak:BAAALgADCgUJBQABLgAECggJJwAYAGMSAA==.Stimer:BAABLgAECn8lAAMSAAkJiByvBgA8AwASAAkJiByvBgA8AwAjAAcJFRLoDwBJAQAAAA==.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIeAAUJ8xRuJAAbAQAeAAUJ8xRuJAAbAQAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgUJBQAAAA==.',
Sw='Swan:BAACLgAFFH8IAAIYAAMJ9wckUgDZAAAYAAMJ9wckUgDZAAAuAAQKfxYAAxgABwk5EHuhAJQBABgABwk5EHuhAJQBABoAAwkHBE0MAGkAAAAA.Swordboardal:BAABLgAFFH8JAAIeAAMJ0g2PDwDBAAAeAAMJ0g2PDwDBAAAAAA==.',
Sy='Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDQAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgIJBAAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takia:BAAALgAECgQJCAAAAA==.Talanzen:BAABLgAECn8mAAIYAAkJ1RwnEACZAgAYAAkJ1RwnEACZAgAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJIgAHAGgSAA==.',
Te='Teacup:BAAALgAECgUJBgAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8PAAIiAAUJqRFXCwBlAQAiAAUJqRFXCwBlAQAuAAQKfzkAAiIACAmNH2ALADQCACIACAmNH2ALADQCAAAA.Thunderhorns:BAAALgAECgYJEAAAAA==.Thundrall:BAAALgAECgQJAwAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAUJDAAXAHEZAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAAALgAECgYJCgAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8gAAMSAAYJtRpaAQDIAQASAAYJtRpaAQDIAQAjAAEJcwBUHQA0AAAuAAQKfxwAAhIACAneIoUIACMDABIACAneIoUIACMDAAAA.Trystrom:BAAALgADCgcJBwAAAA==.',
Ts='Tsuo:BAACLgAFFH8PAAInAAUJyCCiAQCMAQAnAAUJyCCiAQCMAQAuAAQKfzgAAicACAkhJtkAAAQDACcACAkhJtkAAAQDAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgANANEdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAAALgAECgQJCAAAAA==.Tyrick:BAAALgAECgkJEAAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8JAAMKAAUJGAszCQCeAAAKAAIJwQ0zCQCeAAAMAAMJcAiXZACIAAAuAAQKfykABAoACAlnIfoIADECAAwACAn9HcARAFUCAAoABwnpHfoIADECAAsAAQmWHSkoAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Ur='Urethrafrkln:BAAALgADCgcJCQAAAA==.',
Va='Vache:BAAALgADCgQJBAAAAA==.Valartha:BAAALgAECgQJCAAAAA==.Variol:BAAALgADCgkJCgAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECggJFAAgANMhAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgIJBAAAAA==.Velstadt:BAABLgAECn8gAAIPAAgJthyQBwBOAgAPAAgJthyQBwBOAgAAAA==.Venhance:BAABLgAECn8YAAIhAAcJlRY3GgB9AQAhAAcJlRY3GgB9AQAAAA==.Venotu:BAABLgAECn8kAAIBAAgJFR54BABAAgABAAgJFR54BABAAgAAAA==.Vermilion:BAAALgAECgQJCgAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgcJHQAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCwAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAABLgAECn8YAAICAAYJ+RPdHABVAQACAAYJ+RPdHABVAQAAAA==.Vorthael:BAAALgAECgYJEgAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
Vy='Vynirel:BAAALgAECgEJAQAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAFFAEJAQAAAA==.Warmongral:BAABLgAECn8bAAITAAYJTBK3XQA0AQATAAYJTBK3XQA0AQAAAA==.Waterboot:BAAALgAECgYJDgAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8YAAIKAAYJwwqnDgDpAAAKAAYJwwqnDgDpAAAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECgkJJAAWACYdAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn80AAITAAkJcRNAIgD9AQATAAkJcRNAIgD9AQAAAA==.Wisename:BAAALgADCgMJAwAAAA==.Withher:BAAALgADCgcJBwAAAA==.',
Wo='Wombo:BAABLgAECn8bAAIVAAgJlhwgAgBTAgAVAAgJlhwgAgBTAgAAAA==.Woolala:BAAALgAECgEJAQABLgAECgkJMgATAOQgAA==.',
Wr='Wrathran:BAAALgAECgYJEAAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECgkJJQAiAHQXAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAACLgAFFH8FAAIXAAIJjw5VIwCHAAAXAAIJjw5VIwCHAAAuAAQKfyYAAhcACAk3HvQFAMICABcACAk3HvQFAMICAAAA.Yazmyn:BAAALgAECgcJDQAAAA==.',
Ye='Yerehmi:BAAALgAECgMJBAAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAAALgAECgcJEwAAAA==.',
Yv='Yvendria:BAABLgAECn8bAAQLAAgJWBh8AgABAgALAAgJWBh8AgABAgAMAAUJpA9aWQAhAQAKAAEJAAAeagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJBQABLgAECgcJHQAGAAAAAQ==.Zaier:BAABLgAECn88AAMXAAkJqCT/AgBFAwAXAAkJqCT/AgBFAwATAAMJuRHNmQC8AAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.',
Ze='Zeltan:BAABLgAECn8ZAAMXAAcJbBz1LwDCAQAXAAYJGxz1LwDCAQATAAUJIAORvwB2AAAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAAALgAECgQJCAAAAA==.',
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

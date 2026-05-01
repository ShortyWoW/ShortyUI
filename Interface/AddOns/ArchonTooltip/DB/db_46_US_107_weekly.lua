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

local lookup = {'Paladin-Protection','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Hunter-Marksmanship','Priest-Discipline','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Evoker-Devastation','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Druid-Restoration','Druid-Balance','Rogue-Subtlety','Druid-Feral','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abogato:BAAALgADCgYJCgAAAA==.',
Ae='Aedra:BAAALgADCgcJEgAAAA==.Aeowyyn:BAAALgAECgcJDQAAAA==.',
Af='Af:BAAALgADCgUJBQAAAA==.',
Ah='Ahnir:BAAALgAECgYJCgAAAA==.Ahnkhano:BAABLgAECn8dAAIBAAgJ8RFfEgCjAQABAAgJ8RFfEgCjAQAAAA==.',
Ai='Aidenarren:BAAALgADCgkJEAAAAA==.Ainge:BAAALgADCgUJBQAAAA==.Aiom:BAAALgADCgMJAwAAAA==.',
Ak='Akbartheiiv:BAACLgAFFH8PAAICAAcJcBS3AQACAgACAAcJcBS3AQACAgAuAAQKfyoAAgIACAnmJIsEAE0DAAIACAnmJIsEAE0DAAAA.',
Al='Allero:BAAALgAECgMJAwAAAA==.Allistrana:BAABLgAECn8hAAIDAAgJTR02EwBGAgADAAgJTR02EwBGAgAAAA==.Aluvia:BAAALgAECgIJBAAAAA==.',
Am='Amairis:BAAALgAECgMJBAAAAA==.',
An='Anari:BAAALgADCgUJBQAAAA==.Angelsin:BAAALgADCgkJGwAAAA==.Animorph:BAAALgADCgcJJQAAAA==.Annestasia:BAAALgAECgcJAQAAAA==.Anrion:BAABLgAECn8cAAMEAAkJiSFyBgABAwAEAAkJiSFyBgABAwAFAAcJSxtCAwDoAQAAAA==.Anteater:BAAALgADCgEJAQABLgAECgUJDgAGAAAAAA==.',
Ap='Aph:BAAALgAECgcJDAAAAA==.Apolló:BAAALgAECgkJCAAAAA==.',
Ar='Araiana:BAAALgADCgEJAQAAAA==.Arayia:BAAALgAECgQJCgAAAA==.Arelian:BAAALgAECgYJDwAAAA==.Aristia:BAAALgAECgcJCwABLgADCgYJCgAGAAAAAA==.Artaic:BAAALgAECgUJDgAAAA==.Artemysia:BAAALgADCgEJAQAAAA==.',
At='Ataboom:BAAALgADCgEJAQAAAA==.Ataliya:BAAALgAECgQJCgAAAA==.',
Au='Auranar:BAAALgAECgQJCAAAAA==.Aurilia:BAAALgAECgMJBAAAAA==.',
Av='Avanicus:BAABLgAECn8hAAQHAAgJlAreCAAeAQAHAAcJbgneCAAeAQAIAAIJqgy2HQCDAAAJAAQJpwOakwBYAAAAAA==.Aven:BAABLgAECn8UAAMKAAcJjwkPbwDCAAAKAAcJIgkPbwDCAAALAAUJ7gRCHgCFAAAAAA==.',
Ax='Axiomronin:BAABLgAECn8YAAMMAAcJfiOxDgCSAgAMAAcJoyKxDgCSAgANAAMJox6lPQBiAAAAAA==.',
Ay='Ayroon:BAAALgADCgkJDQAAAA==.',
Az='Azulien:BAAALgAECgUJEwAAAA==.Azuriel:BAAALgAECgIJAgAAAA==.',
Ba='Baltuk:BAABLgAECn8aAAIKAAgJ0R3YJgCgAgAKAAgJ0R3YJgCgAgAAAA==.Banderblitz:BAABLgAECn8mAAIOAAgJFBzfBQBZAgAOAAgJFBzfBQBZAgAAAA==.Bar:BAACLgAFFH8GAAMCAAMJ+wXmEQCOAAACAAMJ+wXmEQCOAAADAAMJkhEHEQCJAAAuAAQKfxsAAgIACAlCGiMVAEMCAAIACAlCGiMVAEMCAAAA.Barunnar:BAAALgADCgEJAQAAAA==.',
Be='Bearlyshady:BAAALgADCgcJCwABLgAECgkJGQAPAKAQAA==.Bellatrixie:BAAALgADCggJDgAAAA==.Benafflock:BAAALgAECgQJDQABLgAECgcJEgAGAAAAAA==.Beriadhwen:BAAALgAECgIJAwAAAA==.Bermy:BAABLgAECn8VAAIHAAgJDgwcJQAzAQAHAAgJDgwcJQAzAQAAAA==.Bewildert:BAAALgADCgEJAQAAAA==.',
Bh='Bhawkwco:BAAALgADCgEJAQAAAA==.',
Bl='Blackhawkdk:BAABLgAECn8bAAIKAAcJVhcAMAB6AQAKAAcJVhcAMAB6AQAAAA==.Blende:BAAALgAECgYJEQAAAA==.Bloodshadow:BAABLgAECn8ZAAIQAAgJGw++NAA+AQAQAAgJGw++NAA+AQAAAA==.Blueberrae:BAAALgADCgEJAQAAAA==.Bluemaster:BAAALgADCgYJBgAAAA==.',
Br='Braveharth:BAAALgAECgYJDwAAAA==.Braxus:BAAALgADCgcJDgAAAA==.Breakcooloz:BAACLgAFFH8QAAIRAAUJHSGoAACZAQARAAUJHSGoAACZAQAuAAQKfyIAAhEACAmnIyEBADQDABEACAmnIyEBADQDAAAA.Brooce:BAABLgAECn8cAAISAAcJNR/kGAD2AQASAAcJNR/kGAD2AQAAAA==.Broom:BAAALgADCgkJHQABLgAECggJGwATANgWAA==.',
Bu='Burstinurass:BAABLgAFFH8HAAIKAAQJUyPIBwCdAQAKAAQJUyPIBwCdAQABLgAFFAUJEAARAB0hAA==.',
Ca='Candyjar:BAAALgADCgcJDAAAAA==.Cantmissyou:BAAALgAECgEJBAAAAA==.Capidk:BAAALgAECgUJBgAAAA==.Carafe:BAAALgADCgEJAQABLgAECgUJBgAGAAAAAA==.Carlos:BAAALgAECgIJAwAAAA==.Caspianne:BAAALgAECgQJBgAAAA==.',
Cb='Cbrown:BAAALgAECgEJAQAAAA==.',
Ce='Celani:BAABLgAECn8XAAMDAAgJOA6DLQCPAQADAAgJOA6DLQCPAQAUAAEJugFlXgAkAAAAAA==.Cellyne:BAAALgAECgYJDQAAAA==.Centy:BAAALgAECgYJDQAAAA==.Ceredisam:BAAALgADCgcJBwAAAA==.',
Ch='Chaz:BAAALgAECgQJBgAAAA==.Chedrood:BAAALgADCgMJBwAAAA==.Chelives:BAEALgAECgYJDQAAAA==.Chubrub:BAAALgAECgUJCQAAAA==.Chìef:BAAALgADCgEJAQAAAA==.',
Ci='Cires:BAAALgAECgEJAgAAAA==.',
Cl='Claud:BAAALgADCgQJBAAAAA==.Cleric:BAAALgADCgMJAwAAAA==.',
Co='Cobaltwolf:BAAALgAECgEJBQAAAA==.Colanasou:BAAALgAECgMJBAAAAA==.Coldbattler:BAAALgAECgYJDwAAAA==.Copelongcut:BAAALgADCgMJAQAAAA==.Corrick:BAAALgADCgcJEAAAAA==.',
Cr='Crow:BAAALgAECgkJHQAAAQ==.',
Cu='Curavis:BAAALgADCgMJAwAAAA==.',
Cy='Cydric:BAABLgAECn8hAAISAAgJhyPEDAAoAwASAAgJhyPEDAAoAwAAAA==.',
Da='Daarrkstar:BAAALgAECgYJDQABLgAECgYJEQAGAAAAAA==.Daenyra:BAAALgADCgUJBQAAAA==.Dakarai:BAAALgADCggJDgAAAA==.Danek:BAAALgADCggJGQAAAA==.Darocate:BAAALgADCgYJBgAAAA==.',
De='Deadskvll:BAAALgADCgYJBgAAAA==.Deathbot:BAACLgAFFH8GAAILAAMJVwyHDgC5AAALAAMJVwyHDgC5AAAuAAQKfy8AAgsACQkVHGcCAEYCAAsACQkVHGcCAEYCAAAA.Demira:BAAALgADCgMJAwAAAA==.Demoray:BAACLgAFFH8KAAITAAUJvBiNCACSAQATAAUJvBiNCACSAQAuAAQKfxQAAhMABwl0JOUUAIkCABMABwl0JOUUAIkCAAAA.Dendrin:BAAALgADCgEJAQAAAA==.Deneese:BAAALgADCgkJDwAAAA==.Desniee:BAABLgAECn8gAAQVAAkJJB93QwBuAgAVAAkJJB93QwBuAgAWAAIJHA3kFAB3AAAXAAEJuxXADgA/AAAAAA==.Dethrone:BAAALgAECggJEwAAAA==.',
Di='Digitpro:BAABLgAECn8fAAIYAAgJSw2yCwClAQAYAAgJSw2yCwClAQAAAA==.Dirtydragon:BAABLgAECn8WAAMZAAgJSxvBAgCDAgAZAAgJSxvBAgCDAgAaAAEJhwdVZQArAAAAAA==.Divinedecay:BAAALgAECgYJDQABLgAECggJJAAQAJERAA==.',
Do='Dok:BAAALgADCgcJBwAAAA==.Donoraginn:BAAALgADCgkJEQABLgADCgkJIAAGAAAAAA==.Donos:BAAALgADCgkJIAAAAA==.Dontkare:BAAALgADCgcJEQABLgAECgkJJQAbAIwkAA==.Dorsai:BAAALgADCgUJBQAAAA==.Dott:BAAALgADCgIJAgABLgAECgYJCgAGAAAAAA==.',
Dr='Dracbanti:BAAALgADCgkJEQAAAA==.Dracobelle:BAAALgAECgYJDQAAAA==.Drark:BAAALgADCgQJBAAAAA==.Drathiel:BAAALgAECgMJAwAAAA==.Drazlowe:BAAALgADCgQJBwAAAA==.Dreezee:BAAALgAECgIJBQAAAA==.Drizztknight:BAAALgADCgEJAQAAAA==.Droobear:BAAALgAECgIJAgAAAA==.Drwho:BAAALgAECgUJEwAAAA==.Dràco:BAAALgADCggJDwAAAA==.Drääx:BAAALgADCggJCAAAAA==.Dräëxx:BAAALgADCgcJDQAAAA==.',
Du='Durimli:BAAALgADCgYJBwAAAA==.',
Dw='Dwayneb:BAAALgAECgkJBwAAAA==.',
['Dô']='Dôz:BAAALgADCgQJBAAAAA==.',
El='Elfadwagon:BAACLgAFFH8JAAIcAAQJORcQAgAMAQAcAAQJORcQAgAMAQAuAAQKfyQAAhwACAlcIa8CAAIDABwACAlcIa8CAAIDAAAA.Eliptical:BAAALgAECgYJEwABLgAECggJFwASAIUeAA==.Elkesey:BAAALgADCgEJAQAAAA==.Elonura:BAAALgADCgYJBgAAAA==.Elunea:BAAALgADCgQJBAAAAA==.',
Em='Emishanot:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.',
Ep='Epoch:BAAALgADCgEJAQAAAA==.',
Er='Erangar:BAAALgAECgMJBAAAAA==.Erdor:BAAALgADCgcJDgAAAA==.Erred:BAAALgADCgcJBwAAAA==.',
Es='Esmer:BAABLgAECn8fAAISAAkJeAfNKgCXAQASAAkJeAfNKgCXAQAAAA==.',
Et='Etheman:BAAALgAECgcJBgAAAA==.',
Eu='Euphrasie:BAAALgADCgUJBQABLgAECgcJEgAGAAAAAA==.',
Ev='Eversteal:BAAALgADCgQJBAABLgAECgYJEwAGAAAAAA==.Evholker:BAABLgAECn8VAAMcAAcJxBA7GQBsAQAcAAcJshA7GQBsAQAaAAUJlA4eJQDfAAAAAA==.',
Ex='Excuses:BAAALgAECgYJDAABLgAFFAYJGwAOAOAZAA==.Executey:BAAALgADCgQJBAAAAA==.',
Fa='Facestealerr:BAAALgAECgMJBAAAAA==.Fallenhullkk:BAAALgADCgYJBgAAAA==.Fangyi:BAAALgADCgYJBgAAAA==.',
Fe='Felmufín:BAABLgAECn8UAAIJAAgJEgzrOABJAQAJAAgJEgzrOABJAQAAAA==.Felspury:BAAALgAECgEJAQABLgAECgkJKgAWAC8eAA==.',
Fi='Fibula:BAAALgADCgcJBwAAAA==.',
Fl='Flairrick:BAAALgAECgYJDQAAAA==.Flars:BAAALgAECgQJBQAAAA==.Flatliner:BAABLgAECn8xAAMdAAgJTg0pGgB7AQAdAAgJTg0pGgB7AQASAAEJpQlfUwEqAAAAAA==.',
Fr='Fran:BAAALgADCgYJBgABLgAECggJGwATANgWAA==.Fray:BAAALgAECgcJDQAAAA==.Freeguy:BAABLgAECn8XAAIPAAcJfhcCHQCFAQAPAAcJfhcCHQCFAQAAAA==.',
Fu='Fuddicus:BAABLgAECn8vAAMeAAgJ3CTTBACuAgAeAAgJ3CTTBACuAgAfAAEJGRI6gwA9AAAAAA==.Fuddmore:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Fuddster:BAAALgAECgQJBwAAAA==.',
Ga='Gaddess:BAAALgAECgYJDQAAAA==.Ganath:BAAALgAECgMJAwAAAA==.Ganymede:BAAALgAECgYJBgAAAA==.Garan:BAAALgADCgQJBAAAAA==.Garnar:BAAALgADCgIJAgAAAA==.',
Ge='Geilamaine:BAAALgAECggJEAAAAA==.',
Gi='Gimpy:BAAALgAECgQJBAAAAA==.',
Gl='Glimagi:BAAALgADCgcJDwAAAA==.Glimdaemon:BAAALgADCgkJHAAAAA==.',
Go='Gonefishing:BAABLgAECn8sAAISAAkJth5BCwByAgASAAkJth5BCwByAgAAAA==.Gorddownie:BAAALgAECgYJEAAAAA==.',
Gr='Grellior:BAAALgAECgEJAQAAAA==.Grippysocks:BAACLgAFFH8HAAIdAAMJHBWDEQDqAAAdAAMJHBWDEQDqAAAuAAQKfysAAh0ACAlyGBIcADQCAB0ACAlyGBIcADQCAAAA.',
Gu='Gummibear:BAAALgAECgQJBwAAAA==.',
Ha='Hakar:BAAALgAECgIJAgAAAA==.Hanoa:BAAALgADCgIJAgAAAA==.Harthoon:BAACLgAFFH8KAAIVAAMJXg9oNAD+AAAVAAMJXg9oNAD+AAAuAAQKfzEAAhUACAloHgUQAF0CABUACAloHgUQAF0CAAAA.Haruharu:BAAALgAECgMJCwAAAA==.Hawkhogan:BAAALgADCgYJCQAAAA==.Hazdanzul:BAAALgADCgQJBQABLgAECgYJEQAGAAAAAA==.',
He='Hehexxd:BAAALgAECgIJAgAAAA==.Helias:BAAALgADCgkJBgAAAA==.Hemp:BAAALgADCgEJAQAAAA==.Herrondale:BAAALgADCgcJBwAAAA==.Hey:BAAALgADCgkJEQABLgAECggJHAAgAH0WAA==.',
Hj='Hjukonlikjuj:BAAALgAECgEJAQAAAA==.',
Ho='Hollanov:BAAALgADCgYJBgAAAA==.Honeynoats:BAAALgAECgYJEgAAAA==.Hotdwarf:BAAALgAECgYJCgAAAA==.',
Hu='Hubbabubbles:BAAALgADCggJCAAAAA==.Hullkk:BAACLgAFFH8KAAMhAAMJXCD9BgACAQAOAAMJxhjlDQAZAQAhAAMJzxX9BgACAQAuAAQKfzAAAw4ACAn0JY0FAE4DAA4ACAnOJY0FAE4DACEABgnnIkcCAGUCAAAA.Hundale:BAAALgAECgQJBAAAAA==.Hutchkins:BAABLgAECn8dAAMJAAgJ0htKLQBYAgAJAAgJ0htKLQBYAgAIAAEJAAClFAAAAAAAAA==.Hutchknight:BAAALgAECgUJDAABLgAECggJHQAJANIbAA==.Hutchyo:BAAALgADCgQJBAABLgAECggJHQAJANIbAA==.',
Hy='Hydro:BAABLgAECn8aAAISAAcJIx2GPQAuAgASAAcJIx2GPQAuAgAAAA==.',
['Hä']='Häwtz:BAAALgADCgIJAgAAAA==.',
Ia='Iamhealer:BAAALgADCgMJAgAAAA==.',
In='Inari:BAAALgAECgQJBwABLgAECgcJFQAQAEoYAA==.Inseng:BAAALgAECgYJCwAAAA==.Invasion:BAAALgAECgYJDAAAAA==.',
Ix='Ixy:BAAALgAECgUJDgAAAA==.',
Ja='Jahde:BAABLgAECn8VAAIiAAYJKQv0NAAEAQAiAAYJKQv0NAAEAQAAAA==.Jahoda:BAAALgADCgYJBgAAAA==.Jaina:BAAALgADCggJFwAAAA==.Jamer:BAAALgAECgQJDQAAAA==.Jassykins:BAAALgAECgUJCwAAAA==.',
Je='Jeewop:BAAALgADCgEJAQAAAA==.Jeongaegdeom:BAAALgADCgcJDgAAAA==.Jessecuster:BAAALgAECgIJAwAAAA==.',
Ji='Jinjerr:BAAALgAECgQJBAAAAA==.',
Jo='Joloc:BAABLgAECn8UAAIHAAYJwgj4DQDJAAAHAAYJwgj4DQDJAAAAAA==.Jozay:BAAALgAECgQJBQAAAA==.',
Ju='Juancarlos:BAAALgADCgEJAQAAAA==.',
Ka='Kalasparkle:BAAALgAECgQJAwAAAA==.Kalrosa:BAAALgAECgYJDgABLgAECggJJgAOABQcAA==.Kare:BAABLgAECn8lAAIbAAkJjCRwAAA2AwAbAAkJjCRwAAA2AwAAAA==.Karee:BAAALgAECgYJEAABLgAECgkJJQAbAIwkAA==.Kathilnas:BAAALgADCgUJBQABLgAECgYJEQAGAAAAAA==.',
Kc='Kcosfomas:BAAALgADCgIJAgAAAA==.',
Ke='Kermodrood:BAABLgAECn8aAAIjAAcJfCKVBQBRAgAjAAcJfCKVBQBRAgAAAA==.',
Kh='Khanthurs:BAAALgAECgQJBAAAAA==.',
Ki='Kiizo:BAAALgAECgQJDwAAAA==.Kilnot:BAAALgAECgcJEgAAAA==.Kinstine:BAAALgAECgYJEAAAAA==.',
Ko='Koltara:BAAALgAECgEJAgABLgAFFAMJBwANAIkfAA==.Koltaris:BAACLgAFFH8HAAINAAMJiR/7EAARAQANAAMJiR/7EAARAQAuAAQKfyEAAg0ACAlyJAQCAM0CAA0ACAlyJAQCAM0CAAAA.Konshis:BAABLgAECn8iAAIgAAgJ+xQhEQCYAQAgAAgJ+xQhEQCYAQAAAA==.Kookymonster:BAABLgAECn8oAAMJAAgJSiEkCACLAgAJAAcJhx8kCACLAgAHAAcJlh1/BwBPAgAAAA==.Korbyn:BAAALgADCgkJCQAAAA==.Kos:BAABLgAFFH8GAAIKAAMJUAiIOgDlAAAKAAMJUAiIOgDlAAAAAA==.',
Ku='Kuragaru:BAACLgAFFH8IAAMkAAMJrw3wDwDxAAAkAAMJYAjwDwDxAAARAAIJbwxSBACsAAAuAAQKfyoAAyQACAlRIx4CAKoCACQACAnNIh4CAKoCABEACAlqGiYFAEMCAAAA.',
Ky='Kyoubouna:BAAALgAECgMJAwAAAA==.Kyoxi:BAAALgADCgEJAQAAAA==.',
La='Larianne:BAAALgAECgcJEgAAAA==.',
Le='Leese:BAAALgAECgQJDgAAAA==.Leretic:BAAALgAECgYJBgABLgAECggJFwASAIUeAA==.Lerion:BAABLgAECn8XAAISAAgJhR4fEgABAwASAAgJhR4fEgABAwAAAA==.Lester:BAABLgAECn8cAAICAAcJQxjxCgDRAQACAAcJQxjxCgDRAQAAAA==.Lethana:BAAALgADCgcJDAAAAA==.',
Li='Liamsun:BAABLgAECn8tAAMgAAkJpBMcCgALAgAgAAkJpBMcCgALAgAMAAUJuhTuPwAZAQAAAA==.Lidd:BAAALgAECgQJAwAAAA==.Lidrael:BAABLgAECn8jAAQFAAkJ6hkZBQBdAgAFAAkJ6hkZBQBdAgAEAAYJNAX3QgDsAAAPAAYJewpHmwDiAAAAAA==.Lidrahl:BAAALgADCgcJDQAAAA==.Liekos:BAAALgAECgMJBgAAAA==.Lightbloom:BAAALgAECgIJAwAAAA==.Liliria:BAABLgAECn8oAAIDAAkJ5BT8CQAIAgADAAkJ5BT8CQAIAgAAAA==.Lillidân:BAAALgAECgYJEQAAAA==.Litebite:BAAALgAECgUJBQAAAA==.Littlefish:BAAALgADCgcJDwAAAA==.',
Lj='Ljaeì:BAAALgAECgYJEgAAAA==.',
Ll='Lloreth:BAAALgAECgYJEQAAAA==.',
Ln='Lnpoop:BAAALgAECgUJBgAAAA==.',
Lo='Locknload:BAAALgADCgMJAwAAAA==.Lockwood:BAAALgAECgcJDwAAAA==.Lominar:BAAALgADCgcJBwAAAA==.Lorelei:BAAALgAECgYJDQAAAA==.Lorrellia:BAAALgAECgcJDgAAAA==.',
Lu='Lucariõ:BAACLgAFFH8TAAIDAAYJXBXeAAD1AQADAAYJXBXeAAD1AQAuAAQKfxYAAgMACAkXHpYNAH8CAAMACAkXHpYNAH8CAAAA.Lumina:BAAALgAECgYJDQAAAA==.Lunaría:BAAALgADCgUJBgAAAA==.',
Ly='Lyllies:BAAALgAECgIJAgAAAA==.Lysergia:BAAALgAECgcJEgAAAA==.',
['Lì']='Lìght:BAACLgAFFH8GAAIdAAMJERlyEAD5AAAdAAMJERlyEAD5AAAuAAQKfxsAAh0ABwlkGiomAPYBAB0ABwlkGiomAPYBAAAA.',
Ma='Mahoney:BAAALgAECgUJBQAAAA==.Majestynihil:BAAALgADCggJCAAAAA==.Makkazul:BAABLgAECn8UAAIKAAgJghaRGQDvAQAKAAgJghaRGQDvAQAAAA==.Management:BAAALgADCgQJBAAAAA==.Mangler:BAAALgAECgYJDQAAAA==.Marrad:BAAALgAECgQJBAAAAA==.Marunji:BAAALgAECgYJEQAAAA==.Matcauthon:BAAALgAECgIJBAAAAA==.Matrim:BAAALgAECgQJBQAAAA==.Mattdæmon:BAABLgAECn8UAAMEAAYJjwhoFwDkAAAEAAYJjwhoFwDkAAAPAAIJpwKv2AA+AAAAAA==.Mattmattmatt:BAAALgADCgEJAQAAAA==.',
Me='Meanit:BAAALgAECgQJBgAAAA==.Meekogaia:BAABLgAECn8jAAIeAAgJgyDuCQBKAgAeAAgJgyDuCQBKAgAAAA==.Meekosan:BAAALgAECgQJBgAAAA==.',
Mi='Mihlenna:BAAALgADCgcJBwAAAA==.Millerowntoo:BAAALgADCgEJAgABLgAFFAIJBwAQAI0mAA==.Mimzy:BAAALgAECgEJAgAAAA==.Mingzi:BAAALgAECgUJCgAAAA==.Missanabie:BAAALgADCgcJBwAAAA==.Missymeow:BAAALgADCgYJDAAAAA==.Mital:BAAALgADCgEJAQAAAA==.Mizu:BAEALgAECgEJAQABLgAECggJGwAcAHwRAA==.',
Mm='Mmbear:BAAALgAECgEJAQABLgAFFAQJDgASAFQRAA==.',
Mo='Mojeen:BAAALgADCgIJAgAAAA==.Monkoko:BAAALgADCgEJAgAAAA==.Montkriege:BAABLgAECn8UAAUiAAYJcgu4MwAKAQAiAAYJcgu4MwAKAQAjAAUJpwLEZACOAAAlAAIJoxJeKgB1AAAmAAEJJxpeLABGAAAAAA==.Moonsocks:BAAALgAECgUJBQABLgAFFAMJBwAdABwVAA==.Moxxie:BAAALgAECgYJCQAAAA==.',
Mu='Mufín:BAAALgAECgYJCQAAAA==.Murfie:BAABLgAECn8VAAQCAAgJNxUxIwC+AQACAAcJdxcxIwC+AQADAAQJWgx6WQDOAAAUAAEJugOvOAAyAAAAAA==.Murica:BAAALgADCgEJAQABLgAECggJGwATANgWAA==.',
My='Mythosrex:BAAALgAECgYJBgAAAA==.',
['Mâ']='Mâjôr:BAAALgADCgUJBQAAAA==.',
['Mì']='Mìr:BAACLgAFFH8IAAIPAAMJlBKQHwDpAAAPAAMJlBKQHwDpAAAuAAQKfyoAAw8ACAlyIE8IAFQCAA8ACAlyIE8IAFQCAAQABgn7EBU2AC8BAAAA.',
['Mó']='Mónkass:BAAALgAECgEJAQAAAA==.',
Na='Naitho:BAAALgAECgYJBgAAAA==.Nakedfeet:BAAALgADCgEJAQABLgAFFAMJBwAdABwVAA==.Narena:BAAALgADCgYJBgAAAA==.Nashira:BAABLgAECn8VAAIeAAYJdQr/VwAoAQAeAAYJdQr/VwAoAQAAAA==.Nashness:BAABLgAECn8rAAIKAAkJCyMJEAAdAwAKAAkJCyMJEAAdAwAAAA==.Natharion:BAABLgAECn8vAAMIAAkJdBiVAgCTAgAIAAkJdBiVAgCTAgAJAAcJ0AX1XgDWAAAAAA==.Nazrogul:BAABLgAECn8VAAIKAAYJXwg8sgAeAQAKAAYJXwg8sgAeAQAAAA==.',
Ne='Nerfme:BAAALgAECgQJAwAAAA==.Nezar:BAAALgADCgcJEQAAAA==.',
Ni='Ninjaxe:BAACLgAFFH8MAAIMAAQJihCgCAAPAQAMAAQJihCgCAAPAQAuAAQKfyIAAwwACAnLH9oJANoCAAwACAnLH9oJANoCAA0AAQkmCDiVACAAAAAA.Ninkharak:BAAALgADCgEJAQAAAA==.Nishal:BAAALgAECgMJBAAAAA==.Niterage:BAAALgADCgYJDQAAAA==.',
Nn='Nn:BAAALgAECgYJDQAAAA==.',
No='Novachrono:BAAALgADCgEJAQAAAA==.',
Nu='Nullthor:BAABLgAECn8UAAInAAYJ7xP7CQBHAQAnAAYJ7xP7CQBHAQAAAA==.Nurfd:BAABLgAECn8UAAIbAAYJbwGSHgCKAAAbAAYJbwGSHgCKAAAAAA==.',
['Nè']='Nègan:BAABLgAECn8rAAIQAAgJ0hSbHAC0AQAQAAgJ0hSbHAC0AQAAAA==.',
['Nô']='Nôyar:BAAALgAECgQJBQAAAA==.',
Ob='Obamakare:BAAALgAECgUJBwABLgAECgkJJQAbAIwkAA==.',
Od='Odinrex:BAAALgAECgkJDwAAAA==.',
Og='Ogmattbone:BAAALgADCgMJAQAAAA==.',
Op='Opuntia:BAAALgAECgEJAQAAAA==.',
Ou='Ouch:BAAALgADCgMJAwAAAA==.Outofarrows:BAABLgAECn8bAAMTAAgJ2BYZBADTAQATAAgJ2BYZBADTAQAYAAEJXwmOLgA4AAAAAA==.',
Ow='Ow:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Ownown:BAAALgAECgIJAgABLgAFFAIJBwAQAI0mAA==.',
Pa='Palinuttz:BAAALgAECgMJAwAAAA==.Pallypaladin:BAACLgAFFH8OAAISAAQJVBGdEQA/AQASAAQJVBGdEQA/AQAuAAQKfxkAAhIACQmqHxQgAKwCABIACQmqHxQgAKwCAAAA.Pasteeater:BAAALgAECgQJBAAAAA==.',
Pe='Pernelope:BAABLgAECn8iAAIPAAcJ8hvPRADgAQAPAAcJ8hvPRADgAQAAAA==.',
Ph='Phatzero:BAABLgAECn8kAAMQAAgJkRG2JACIAQAQAAgJkRG2JACIAQATAAIJMwTMHABNAAAAAA==.Phöenix:BAAALgAECgEJAQAAAA==.',
Pi='Piedra:BAAALgADCgYJDAABLgAECgkJJgADAD4YAA==.Piety:BAAALgAECgIJAgAAAA==.Pinjo:BAAALgAECgEJAgAAAA==.',
Po='Polarnomad:BAAALgADCgYJCwABLgAECgYJFQAVADgVAA==.Polarr:BAABLgAECn8VAAIVAAYJOBVRzwBNAQAVAAYJOBVRzwBNAQAAAA==.Popsicles:BAAALgAECgUJBQAAAA==.',
Pr='Prismatic:BAAALgAECgMJBAAAAA==.Probablyblue:BAAALgAECgUJBgAAAA==.Proofy:BAAALgAECgcJDwAAAA==.Prowl:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.',
Ps='Psyop:BAAALgADCgkJEQABLgAECgMJBAAGAAAAAA==.',
Pu='Punchkick:BAAALgADCgcJBwAAAA==.Punchup:BAABLgAECn8WAAIMAAcJ/gkpGAAnAQAMAAcJ/gkpGAAnAQAAAA==.',
Py='Pythie:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgMJAwAAAA==.Ramsey:BAAALgADCgEJAQAAAA==.Rastputin:BAAALgAECgkJDgAAAA==.',
Re='Rebrex:BAAALgADCgcJBwAAAA==.Redpyro:BAAALgADCgcJDwAAAA==.Retrïbutor:BAAALgADCgYJBgAAAA==.',
Rf='Rf:BAAALgAECgEJAQAAAA==.',
Rh='Rhodraco:BAAALgAECgYJDAAAAA==.',
Ri='Rinela:BAABLgAECn8fAAIjAAgJDRzzGQA2AgAjAAgJDRzzGQA2AgAAAA==.Riotdrill:BAAALgADCgYJBwAAAA==.',
Rj='Rj:BAABLgAECn8aAAIiAAcJoSHNBgCoAgAiAAcJoSHNBgCoAgAAAA==.',
Ro='Robi:BAAALgADCgEJAQABLgAECgYJEQAGAAAAAA==.Romulusinc:BAAALgADCgMJBgAAAA==.Rosabee:BAABLgAECn8UAAIDAAcJfQYKIgDwAAADAAcJfQYKIgDwAAAAAA==.',
Rp='Rp:BAAALgAECgMJAwAAAA==.',
Rq='Rq:BAAALgADCgYJBgAAAA==.',
Ru='Runswithheal:BAAALgAECgQJBQAAAA==.',
Ry='Ryyukken:BAAALgAECgYJCAAAAA==.',
['Rà']='Ràndòm:BAAALgADCgIJAgABLgAFFAYJGQAVAFceAA==.Ràwrshåk:BAAALgADCgYJBgAAAA==.',
['Rá']='Rándom:BAAALgAECgYJBgABLgAFFAYJGQAVAFceAA==.',
['Ró']='Rónin:BAAALgAECgMJCQAAAA==.',
Sa='Sago:BAAALgAECgMJBAAAAA==.Sanzen:BAABLgAECn8ZAAMMAAYJsRu5IgDAAQAMAAYJsRu5IgDAAQAgAAMJsgcRWQBqAAAAAA==.Sauce:BAABLgAECn8cAAIgAAgJfRYdCgALAgAgAAgJfRYdCgALAgAAAA==.',
Sc='Scrubz:BAABLgAECn8ZAAImAAgJ8xzUBwA2AgAmAAgJ8xzUBwA2AgAAAA==.',
Se='Senile:BAAALgAECgYJDQAAAA==.Seydori:BAAALgADCgUJDAAAAA==.',
Sh='Shadylid:BAABLgAECn8ZAAMPAAkJoBBmHACJAQAPAAkJZRBmHACJAQAFAAMJUwn6EAB/AAAAAA==.Shadówglider:BAAALgAECgMJBAAAAA==.Shale:BAABLgAECn8VAAIPAAgJpyDzOgAIAgAPAAgJpyDzOgAIAgAAAA==.Shameless:BAAALgAFFAIJAgAAAA==.Sharkina:BAAALgADCgUJBQAAAA==.Sharkweek:BAAALgAECgQJBQAAAA==.Sheyoni:BAAALgAECgMJAwAAAA==.Shreck:BAAALgAECgQJBAAAAA==.',
Sk='Skikette:BAAALgADCggJGgAAAA==.Skinrot:BAABLgAECn8jAAIiAAcJ7wssNwD5AAAiAAcJ7wssNwD5AAAAAA==.',
Sm='Smig:BAAALgAECgEJBAAAAA==.',
So='Soeki:BAAALgAECgYJDQAAAA==.Solux:BAAALgAFFAMJAwABLgAFFAMJBgAHAEwMAA==.Soullove:BAABLgAECn8tAAIHAAgJexTrAwCmAQAHAAgJexTrAwCmAQAAAA==.Soullovez:BAAALgAECgYJEAABLgAECggJLQAHAHsUAA==.Soulshocks:BAABLgAECn8hAAIfAAcJ0AkCIAAaAQAfAAcJ0AkCIAAaAQABLgAECggJLQAHAHsUAA==.Soulviver:BAABLgAECn8aAAIDAAcJlg3bFwBMAQADAAcJlg3bFwBMAQAAAA==.',
Sp='Sparkelly:BAAALgADCgEJAQAAAA==.Spliffy:BAAALgADCgYJBgAAAA==.Spurey:BAABLgAECn8qAAMWAAkJLx47AwBFAgAWAAgJNRo7AwBFAgAVAAkJ/RgDIwDdAQAAAA==.Spurylock:BAAALgADCgcJBwABLgAECgkJKgAWAC8eAA==.',
St='Starstreak:BAAALgADCgUJBQABLgAECgcJIAAVADgTAA==.Stimer:BAABLgAECn8lAAMOAAkJiByzBgA8AwAOAAkJiByzBgA8AwAhAAcJFRLNCgBVAQAAAA==.Stuipd:BAAALgADCgYJCQAAAA==.',
Su='Sublimedeath:BAABLgAECn8UAAIbAAUJ8xSzFQDbAAAbAAUJ8xSzFQDbAAAAAA==.Sublimelife:BAAALgAECgEJAQAAAA==.Sukboytony:BAAALgADCgYJBgAAAA==.Sultanofswat:BAAALgADCgcJBwAAAA==.Sunnysideup:BAAALgAECgUJBQAAAA==.',
Sv='Svetlana:BAAALgAECgUJBQAAAA==.',
Sw='Swan:BAACLgAFFH8HAAIVAAMJ9wcFPADgAAAVAAMJ9wcFPADgAAAuAAQKfxYAAxUABwk5EHuhAJQBABUABwk5EHuhAJQBABcAAwkHBE0MAGkAAAAA.Swordboardal:BAABLgAFFH8FAAIbAAMJ1gkxEABxAAAbAAMJ1gkxEABxAAAAAA==.',
Sy='Symptom:BAAALgAECgEJAQAAAA==.Syncophat:BAAALgADCgcJDAAAAA==.',
['Sé']='Séphórâ:BAAALgADCgMJBAAAAA==.',
Ta='Tachia:BAAALgAECgYJBgAAAA==.Tad:BAAALgAECgIJBAAAAA==.Taint:BAAALgADCgQJBgAAAA==.Takia:BAAALgAECgMJBAAAAA==.Talanzen:BAABLgAECn8gAAIVAAgJ9ByWFQAvAgAVAAgJ9ByWFQAvAgAAAA==.Tarrzok:BAAALgADCgcJBwABLgAECgkJGQAPAKAQAA==.',
Te='Teacup:BAAALgAECgUJBgAAAA==.',
Th='Theowyn:BAAALgADCgEJAQAAAA==.Thormarian:BAAALgADCgUJBwAAAA==.Thrakara:BAACLgAFFH8KAAIgAAMJpBcZDwDnAAAgAAMJpBcZDwDnAAAuAAQKfzEAAiAACAlwH14IAC8CACAACAlwH14IAC8CAAAA.Thunderhorns:BAAALgAECgYJCQAAAA==.Thundrall:BAAALgADCgUJCgAAAA==.',
To='Toaster:BAAALgADCgQJBAABLgAFFAMJBwAdABwVAA==.Toothléss:BAAALgADCgIJAgAAAA==.Toria:BAAALgAECgUJBgAAAA==.Torlania:BAAALgADCgYJBgAAAA==.',
Tr='Trayleen:BAAALgAECgMJBAAAAA==.Treeåj:BAAALgAECgYJCgAAAA==.Trilina:BAAALgADCgkJCAAAAA==.Truths:BAACLgAFFH8bAAMOAAYJ4Bl8AADbAQAOAAYJ4Bl8AADbAQAhAAEJcwBjFAA1AAAuAAQKfxwAAg4ACAneIogIACMDAA4ACAneIogIACMDAAAA.',
Ts='Tsuo:BAACLgAFFH8KAAImAAMJtiC5AgAXAQAmAAMJtiC5AgAXAQAuAAQKfzEAAiYACAkiJiwAAP8CACYACAkiJiwAAP8CAAAA.',
Tu='Tuhãn:BAAALgAECgEJAQAAAA==.',
Tw='Twixxed:BAAALgADCgYJCAABLgAECggJGgAKANEdAA==.',
Tx='Txjustice:BAAALgADCgUJDwAAAA==.',
Ty='Tymptriss:BAAALgAECgMJBAAAAA==.Tyrick:BAAALgAECggJDgAAAA==.Tywen:BAAALgADCgEJAQAAAA==.',
Uh='Uhogpaladin:BAAALgADCgEJAQAAAA==.',
Um='Umbrage:BAACLgAFFH8GAAMHAAMJTAwHFABWAAAJAAIJgwgHTACSAAAHAAEJ3xMHFABWAAAuAAQKfykABAkACAlnIdMKAGICAAkACAn9HdMKAGICAAcABwnpHfkIADECAAgAAQmWHSwoAFEAAAAA.',
Un='Unholyblade:BAAALgADCgYJCgAAAA==.',
Va='Vache:BAAALgADCgQJBAAAAA==.Valartha:BAAALgAECgMJBAAAAA==.Vaztek:BAAALgADCgMJAwAAAA==.',
Ve='Vecna:BAAALgAECgYJEAAAAA==.Vellarya:BAAALgADCgYJBgABLgAECgcJEgAGAAAAAA==.Vellmora:BAAALgAECgEJAQAAAA==.Velsea:BAAALgAECgIJBAAAAA==.Velstadt:BAABLgAECn8aAAIMAAcJ6BxtCAD4AQAMAAcJ6BxtCAD4AQAAAA==.Venhance:BAABLgAECn8WAAIfAAYJIRkzFwBbAQAfAAYJIRkzFwBbAQAAAA==.Venotu:BAABLgAECn8cAAIBAAgJ7hy6BAD5AQABAAgJ7hy6BAD5AQAAAA==.Vermilion:BAAALgAECgEJAQAAAA==.Verso:BAAALgADCgcJEwAAAA==.',
Vi='Vinculum:BAAALgADCgIJAgAAAA==.Viviel:BAAALgAECgYJFgAAAQ==.',
Vo='Voidherron:BAAALgAECgYJCQAAAA==.Voidobscur:BAAALgADCgUJBQAAAA==.Voidwapa:BAAALgAECgQJCAAAAA==.Vonzilla:BAAALgAECgYJEgAAAA==.Vorthael:BAAALgAECgYJDAAAAA==.Voxen:BAAALgADCgQJBAAAAA==.',
['Vö']='Vöid:BAAALgADCgcJBwAAAA==.',
Wa='Waarlow:BAAALgADCgEJAQAAAA==.Warlockbot:BAAALgAECgMJAwAAAA==.Warmongral:BAABLgAECn8VAAISAAYJJhF/RgA2AQASAAYJJhF/RgA2AQAAAA==.Waterboot:BAAALgAECgUJCAAAAA==.Wattheyneed:BAAALgADCgUJBQAAAA==.',
We='Wendi:BAABLgAECn8UAAIHAAYJMwncCwDjAAAHAAYJMwncCwDjAAAAAA==.',
Wh='Wheelchair:BAAALgADCgUJBQABLgAECggJGwATANgWAA==.Whipx:BAAALgADCgIJAgAAAA==.',
Wi='Wingsaber:BAABLgAECn8rAAISAAkJbRESGQD0AQASAAkJbRESGQD0AQAAAA==.Wisename:BAAALgADCgMJAwAAAA==.Withher:BAAALgADCgcJBwAAAA==.',
Wo='Wombo:BAABLgAECn8VAAIRAAcJrR0SAwDRAQARAAcJrR0SAwDRAQAAAA==.Woolala:BAAALgADCgcJBwABLgAECgkJLAASALYeAA==.',
Wr='Wrathran:BAAALgAECgYJDwAAAA==.',
Wu='Wut:BAAALgADCgkJCQABLgAECggJHAAgAH0WAA==.',
Xa='Xahiri:BAAALgAECgEJAQAAAA==.',
Xl='Xlia:BAAALgAECgIJAgAAAA==.',
Ya='Yaeyo:BAAALgAECgcJDQAAAA==.Yazmat:BAABLgAECn8eAAIdAAgJcRIhFAC1AQAdAAgJcRIhFAC1AQAAAA==.Yazmyn:BAAALgAECgYJDAAAAA==.',
Ye='Yerehmi:BAAALgAECgMJAwAAAA==.',
Ym='Ymma:BAAALgADCgcJBwAAAA==.',
Yu='Yuny:BAAALgAECgcJEwAAAA==.',
Yv='Yvendria:BAABLgAECn8VAAQIAAcJAxJuAwCDAQAIAAcJOg9uAwCDAQAJAAUJpQ/IQwAmAQAHAAEJAAAdagA+AAAAAA==.',
Za='Zacnafeen:BAAALgAECgMJAwAAAA==.Zaelessa:BAAALgAECgMJBAABLgAECgYJFgAGAAAAAQ==.Zaier:BAABLgAECn8zAAMdAAkJjSGXAQAdAwAdAAkJjSGXAQAdAwASAAMJuxGvdADFAAAAAA==.Zaraelila:BAAALgADCgMJAwAAAA==.',
Ze='Zeltan:BAABLgAECn8VAAMdAAcJEhv0LwDCAQAdAAYJhxr0LwDCAQASAAUJHwM2lgB5AAAAAA==.Zeropriest:BAAALgADCgUJBQAAAA==.',
Zh='Zhundrenga:BAAALgAECgMJBAAAAA==.',
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

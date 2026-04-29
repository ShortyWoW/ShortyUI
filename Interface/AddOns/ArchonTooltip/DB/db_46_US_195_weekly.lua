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

local lookup = {'Druid-Balance','Druid-Restoration','Mage-Frost','Priest-Holy','Warrior-Fury','Warrior-Protection','Warrior-Arms','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Priest-Shadow','Monk-Windwalker','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','Monk-Brewmaster','Druid-Guardian','Monk-Mistweaver','Hunter-Survival','Evoker-Preservation','DeathKnight-Unholy','Evoker-Devastation',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Ackrenoth:BAAALgADCgkJIAAAAA==.',
Ad='Adynn:BAABLgAECn8UAAMBAAYJwCLPBADMAQABAAYJwCLPBADMAQACAAIJrBaEoQCGAAAAAA==.',
Ae='Aethreal:BAAALgADCgEJAgAAAA==.',
Af='Afridium:BAAALgAECgcJAQAAAA==.',
Ag='Agrathayn:BAAALgADCgkJCQAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECggJHAADAKwZAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAAALgAECgYJEwAAAA==.Alnharaelune:BAAALgADCgMJBgAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAAALgAECgQJBgAAAA==.',
An='Anali:BAABLgAECn8bAAIEAAgJciHBAADeAgAEAAgJciHBAADeAgAAAA==.Anani:BAAALgADCgkJIgAAAA==.Andavin:BAAALgAECgYJEAAAAA==.Angreifer:BAABLgAECn8eAAQFAAgJ+Q9bMgDiAQAFAAgJEA9bMgDiAQAGAAYJFBDsBwATAQAHAAIJ1A4LEwBAAAAAAA==.Anori:BAAALgAECgYJCwAAAA==.',
Ao='Aonar:BAAALgAECgEJAQAAAA==.',
Ar='Arc:BAAALgAECgYJEQAAAA==.Archenteron:BAAALgADCgYJCQAAAA==.Arctat:BAAALgADCgcJCwAAAA==.Ardorcinder:BAAALgADCgkJGAAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCgAAAA==.',
As='Asbjorne:BAAALgAECgUJDAAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Autumnmoon:BAAALgAECgUJCgAAAA==.',
Av='Avelos:BAABLgAECn8dAAMEAAkJSBK1IQDWAQAEAAgJEhS1IQDWAQAIAAQJhgbJRgCGAAAAAA==.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAAALgAECgUJCwAAAA==.Ayzmist:BAAALgAECgQJBAAAAA==.Ayzmyth:BAAALgAECgYJEQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIJAAcJ7yAbDwCgAgAJAAcJ7yAbDwCgAgAAAA==.Bashra:BAAALgAECgQJCwAAAA==.',
Be='Beasic:BAABLgAECn8UAAMKAAYJiAhqFQDNAAAKAAYJiAhqFQDNAAAJAAMJ3wDdkgBQAAAAAA==.Beletili:BAAALgAECgYJEwAAAA==.',
Bi='Birb:BAAALgAECgYJBgAAAA==.Birddh:BAABLgAECn8WAAMLAAgJ9w8nUwCrAQALAAgJmg8nUwCrAQAMAAYJjg5cBQDjAAAAAA==.Birdman:BAAALgAECgQJBAABLgAECggJFgALAPcPAA==.Bismuth:BAAALgADCgYJBgAAAA==.',
Bl='Blackraven:BAAALgAECgYJCgAAAA==.Blatendrg:BAABLgAECn8cAAINAAgJlg2mJQCPAQANAAgJlg2mJQCPAQAAAA==.Blindcloud:BAAALgAECgUJCQAAAA==.',
Bo='Boot:BAAALgAECgMJAwAAAA==.Bophedes:BAAALgAECgUJCQAAAA==.Borodemonin:BAEALgAECgUJBQABLgAECggJGAAOAGMkAA==.Bosstun:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn8UAAIEAAYJfRcpCACBAQAEAAYJfRcpCACBAQAAAA==.Bromith:BAAALgAECgEJAQAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calyma:BAAALgADCgkJEgAAAA==.Catsclaw:BAAALgAECgQJCAAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAAALgAECgYJDwAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgQJCAAAAA==.Charles:BAABLgAECn8eAAIPAAgJviO7AAClAgAPAAgJviO7AAClAgAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiot:BAAALgAECgYJEgAAAA==.Chonkr:BAAALgAECgcJDwAAAA==.Chubs:BAABLgAECn8VAAIFAAYJQBRZEQAcAQAFAAYJQBRZEQAcAQAAAA==.Chuga:BAAALgAECggJDwAAAA==.',
Ci='Cimerian:BAAALgAECgYJDwAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgUJDQAQAAAAAA==.',
Co='Cobalticus:BAAALgADCgYJBgAAAA==.Corange:BAAALgADCgkJEAAAAA==.Corlock:BAAALgADCgQJBQAAAA==.Cormech:BAAALgAECgYJDQAAAA==.Cornite:BAAALgAECgMJBgAAAA==.',
Cr='Crizzo:BAAALgAECgYJEgAAAA==.',
Cy='Cyndrial:BAAALgADCgIJAgAAAA==.',
Da='Daddyslilgrl:BAAALgADCgcJBwAAAA==.Dakra:BAEALgAECgYJDgAAAA==.Dalamar:BAABLgAECn8jAAMRAAgJYBp/OQAmAgARAAgJIxh/OQAmAgASAAQJ9x01IgBEAQAAAA==.Dalyeth:BAAALgAECgYJCgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAAALgAFFAIJAgAAAA==.',
De='Decypher:BAAALgAECgYJCwAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAAALgAECgQJCwABLgAECggJIwARAGAaAA==.Demonablaze:BAAALgADCgMJAwAAAA==.Dentik:BAAALgAECgQJBgAAAA==.Denuma:BAAALgADCgcJBwAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJBgAAAA==.',
Dh='Dheri:BAAALgAECgQJBwABLgAECgYJCwAQAAAAAA==.',
Di='Diamair:BAABLgAECn8aAAMTAAYJhhnPBQDHAQATAAYJhhnPBQDHAQADAAIJAAJEXwFBAAAAAA==.Diamones:BAAALgADCgkJCQAAAA==.Dixiee:BAAALgADCgYJFQAAAA==.',
Dn='Dnegelpal:BAABLgAECn8XAAIUAAgJnw10EgCPAQAUAAgJnw10EgCPAQAAAA==.',
Do='Dodgecharger:BAAALgADCgcJEgAAAA==.Dornix:BAABLgAECn8hAAIRAAgJlR4gBQApAgARAAgJlR4gBQApAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgUJBgAAAA==.Drakilu:BAABLgAECn8UAAIVAAYJkxgAEACBAQAVAAYJkxgAEACBAQAAAA==.Drasic:BAABLgAECn8hAAICAAgJPByABwDuAQACAAgJPByABwDuAQAAAA==.Dreddscott:BAAALgADCgYJBgABLgAECgYJEQAQAAAAAA==.Drophin:BAAALgADCgcJDQAAAA==.Drunken:BAAALgAECgYJEgAAAA==.Druphin:BAAALgADCgQJCAAAAA==.',
Du='Durward:BAAALgAECgYJEQAAAA==.Duvo:BAAALgAECgYJCgAAAA==.',
Dw='Dwarfo:BAAALgAECgEJAQAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAAALgAECgUJEAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIWAAgJah6FAABDAgAWAAgJah6FAABDAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAAALgAECgcJCwAAAA==.Elemental:BAABLgAECn8hAAMKAAkJ6RiiDgC6AgAKAAkJ6RiiDgC6AgAJAAIJnwwdjgBeAAABLgAFFAQJBgABAAAFAA==.Elloseth:BAAALgAECgYJCgAAAA==.Elmorin:BAAALgADCgkJEAAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAAALgADCgcJGAAAAA==.',
Ep='Epica:BAABLgAECn8UAAIDAAYJXRb5IQBLAQADAAYJXRb5IQBLAQAAAA==.',
Er='Eragonhawk:BAAALgAECgUJDQAAAA==.Eroldan:BAAALgAECgUJDAAAAA==.Erovianoria:BAABLgAECn8mAAIVAAkJuBYEFwCAAgAVAAkJuBYEFwCAAgAAAA==.Eruadan:BAAALgADCggJEQAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAAALgAECgYJDgAAAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8YAAIJAAcJzxHhDwBEAQAJAAcJzxHhDwBEAQAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAAALgAECgQJBQAAAA==.Fauxstorm:BAAALgAECgEJAQAAAA==.',
Fi='Finngan:BAAALgAECgcJEwAAAA==.Fireina:BAAALgADCgYJBwAAAA==.',
Fo='Forestkin:BAAALgADCgcJEgABLgAECgYJCgAQAAAAAA==.Fossilis:BAABLgAECn8WAAMXAAcJFQUyBAAWAQAXAAcJ+QQyBAAWAQAYAAUJ2wIRTwCzAAAAAA==.',
Fr='Frozenthunda:BAAALgAECgEJAgAAAA==.',
Fu='Furna:BAAALgAECgYJCQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAABLgAECn8dAAIFAAgJdxM8BgDCAQAFAAgJdxM8BgDCAQAAAA==.',
Gh='Ghorienge:BAAALgAECgMJBQAAAA==.Ghostcat:BAAALgADCgIJAgAAAA==.',
Gi='Gilox:BAAALgAECgYJEQAAAA==.',
Gn='Gndmexia:BAAALgADCgYJBwAAAA==.Gneiss:BAAALgADCgkJIAAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8cAAICAAgJSSHYAAAPAwACAAgJSSHYAAAPAwAAAA==.',
Gr='Graymon:BAAALgAECgEJAQAAAA==.Greebo:BAAALgAECgEJAQAAAA==.Griknor:BAABLgAECn8bAAMHAAYJRQXHCADfAAAHAAYJRQXHCADfAAAFAAEJ3QF3swAjAAAAAA==.Gryphonwrest:BAAALgADCgMJBAAAAA==.',
Gu='Guatalupe:BAAALgAECgIJAgAAAA==.Guilherme:BAAALgADCgUJBwAAAA==.',
Gw='Gwenyver:BAAALgAECgUJDAAAAA==.',
Ha='Hafaken:BAAALgADCgQJBAAAAA==.Hamord:BAAALgAECgUJDAAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgADCgQJBAAAAA==.Harliqynn:BAABLgAECn8VAAIVAAgJNBnuIABAAgAVAAgJNBnuIABAAgAAAA==.Harlock:BAAALgAECgYJEgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.',
Hi='Hiten:BAABLgAECn8UAAMYAAYJrRIVCwAiAQAXAAUJRBWFDQBEAQAYAAYJpAgVCwAiAQAAAA==.',
Ho='Hopedaimond:BAABLgAECn8UAAIKAAcJgA2ORQAyAQAKAAcJgA2ORQAyAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8UAAIVAAYJUw7cGwAfAQAVAAYJUw7cGwAfAQAAAA==.',
Hy='Hypro:BAABLgAECn8lAAIJAAkJfCU5AADXAwAJAAkJfCU5AADXAwAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIZAAcJByOXBAC6AgAZAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgUJBQAAAA==.',
Ie='Iepa:BAAALgADCgYJBgAAAA==.',
Il='Ilthad:BAAALgADCggJGgAAAA==.',
Im='Imshalar:BAAALgAECgQJBAAAAA==.',
In='Inconcvabull:BAAALgAECggJDwAAAA==.Inferious:BAAALgAECgUJDAAAAA==.Inistus:BAAALgADCgUJBQAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgQJBwAAAA==.Itsirk:BAABLgAECn8YAAIaAAYJNBrULgDIAQAaAAYJNBrULgDIAQAAAA==.',
Iz='Izyebelle:BAAALgAECgYJEQAAAA==.',
Ja='Jadevine:BAAALgADCgEJAQAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAAALgAECgUJDQAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jimmydin:BAABLgAECn8dAAMaAAgJ1Bi3HgAiAgAaAAgJ1Bi3HgAiAgAUAAQJaQ9YKAACAQAAAA==.Jix:BAABLgAECn8YAAMSAAgJkxi9DgDeAQASAAYJuRy9DgDeAQARAAQJSAwirQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8fAAQLAAgJuxC8GgAsAQALAAgJAxC8GgAsAQAMAAMJyxWmHgCSAAAbAAEJYw4MbwA2AAAAAA==.',
Ju='Julkan:BAAALgAECgQJBQAAAA==.Junhoong:BAABLgAECn8XAAIUAAYJTBXHGABcAQAUAAYJTBXHGABcAQAAAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAAALgAECgUJCAAAAA==.Kairoll:BAABLgAECn8ZAAIEAAgJDhKzBgCnAQAEAAgJDhKzBgCnAQAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Karaa:BAAALgAECgUJDQAAAA==.Kariena:BAAALgAECgUJCwAAAA==.Katesluage:BAABLgAECn8cAAIDAAgJrBkUDgDYAQADAAgJrBkUDgDYAQAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECggJHAADAKwZAA==.',
Ke='Keeya:BAAALgAECgQJCgAAAA==.Kelina:BAAALgADCgYJDAABLgADCgcJDgAQAAAAAA==.Kendari:BAAALgAECgQJBwAAAA==.Kernasas:BAAALgAECgQJDgAAAA==.Keslynn:BAAALgADCgUJBQABLgAECgUJCwAQAAAAAA==.Ketrani:BAAALgADCgYJDAABLgAECgUJCwAQAAAAAA==.',
Kh='Khiari:BAAALgADCgUJBQABLgAECgUJCgAQAAAAAA==.',
Ki='Kildarin:BAAALgAECgYJCgAAAA==.Kilrith:BAAALgADCgkJDwAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJIQARAJUeAA==.Kizaraan:BAAALgAECgUJDAAAAA==.',
Kl='Kleyntamar:BAAALgADCgkJJwAAAA==.',
Kr='Kritter:BAAALgADCgcJFgAAAA==.Krohm:BAABLgAECn8eAAIUAAgJryAmEwD6AgAUAAgJryAmEwD6AgAAAA==.Krshna:BAAALgAECgMJBAAAAA==.',
Ku='Kumachikara:BAAALgADCgkJEQAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgMJAwAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgQJDQAAAA==.Lanss:BAABLgAECn8gAAIGAAgJFSKnAQAsAgAGAAgJFSKnAQAsAgAAAA==.Larachel:BAAALgADCgkJGwAAAA==.Laur:BAABLgAECn8YAAIOAAgJExKoCQBVAQAOAAgJExKoCQBVAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCQAAAA==.Leipäjuusto:BAABLgAECn8UAAIUAAgJjxcRQAAmAgAUAAgJjxcRQAAmAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAAALgAECgEJAQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAgAAAA==.Lilipo:BAAALgAECgQJDAAAAA==.Liltara:BAAALgAECgQJCAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJDwAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAABLgAECn8dAAIRAAgJcw6GEACNAQARAAgJcw6GEACNAQAAAA==.Lokdan:BAAALgADCgkJCQAAAA==.Loula:BAAALgAECgQJCwAAAA==.Lowryder:BAABLgAECn8VAAMYAAgJRA91BQChAQAYAAgJRA91BQChAQAXAAEJmwZbIAAxAAAAAA==.Loxes:BAAALgAECgIJAgABLgAECgYJCwAQAAAAAA==.Loxy:BAAALgAECgQJBQAAAA==.',
Lu='Lukam:BAAALgADCgcJEgAAAA==.Lunaellana:BAAALgADCgcJCwAAAA==.Lus:BAABLgAECn8UAAMRAAYJsRfgegBmAQARAAYJsRfgegBmAQASAAIJugglUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAAALgAECgEJAQABLgAECgcJFgACAGEZAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
Ma='Magicfang:BAAALgAECgMJAwAAAA==.Maiku:BAAALgAECgYJEgAAAA==.Makado:BAAALgAECgYJEAAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAAALgAECgYJBgAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Maycee:BAAALgADCgkJGQAAAA==.',
Mc='Mcnaugh:BAAALgAECgUJDAAAAA==.Mcsaltface:BAAALgAECgUJDAAAAA==.',
Me='Meddic:BAAALgADCgYJBwAAAA==.Menaras:BAABLgAECn8mAAMKAAkJJB09EgCRAgAKAAkJJB09EgCRAgAJAAYJMhOUQQB7AQAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAECggJHgAFAPkPAA==.',
Mi='Mirosmundo:BAABLgAECn8lAAIcAAkJAB3aCAD5AgAcAAkJAB3aCAD5AgAAAA==.Mistfit:BAAALgAECgcJEAAAAA==.Miyagi:BAAALgAECgUJCwAAAA==.Miyu:BAAALgAECgYJEwAAAA==.',
Mo='Mod:BAABLgAECn8cAAMKAAgJKCCjAgArAgAKAAcJmyGjAgArAgAJAAUJgRSvUwA3AQAAAA==.Modaka:BAAALgADCgcJCgAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moggatorash:BAAALgAECgQJBAAAAA==.Mogtham:BAABLgAECn8UAAIdAAYJPwRmIwCBAAAdAAYJPwRmIwCBAAAAAA==.Moisticklez:BAAALgAECgIJBAAAAA==.Monkeyspaul:BAAALgAECgcJEwABLgAECggJHAAGAJ8bAA==.Moonfall:BAAALgAECgQJBAAAAA==.Moosader:BAABLgAECn8UAAMUAAcJwROdUwDnAQAUAAcJwROdUwDnAQAaAAYJZAiKVwAdAQAAAA==.Morellea:BAAALgAFFAEJAQAAAA==.Morighann:BAABLgAECn8bAAIVAAgJUyB5AgB9AgAVAAgJUyB5AgB9AgAAAA==.Morkith:BAAALgADCgUJBQAAAA==.Mosrael:BAAALgAECgEJAQAAAA==.Mousse:BAAALgADCgMJAwABLgAECgYJFQAeAGUkAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgADCgkJEQABLgAECgcJFAAKAMQLAA==.',
My='Mynkx:BAAALgAECgUJCgAAAA==.Mythyras:BAAALgAECgYJCgAAAA==.',
Na='Nahaman:BAAALgADCgkJGQAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8VAAIaAAYJEQ2IEQAmAQAaAAYJEQ2IEQAmAQAAAA==.',
Ne='Nechahira:BAABLgAFFH8GAAIBAAQJAAV8BAAbAQABAAQJAAV8BAAbAQAAAA==.Netherite:BAAALgAECgUJDAAAAA==.Nethim:BAAALgADCgcJBwABLgAECgUJDAAQAAAAAA==.Netre:BAAALgADCgcJBwAAAA==.Nezana:BAAALgAECgYJEwAAAA==.',
Ni='Nianah:BAAALgADCggJCgAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8cAAIdAAgJGR7eBACYAgAdAAgJGR7eBACYAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Noranna:BAAALgAECgEJAQAAAA==.',
['Nø']='Nøva:BAAALgADCgcJBwABLgAFFAMJAwAQAAAAAA==.',
Oh='Ohthesemyboo:BAAALgAECgQJBAAAAA==.Ohwellz:BAAALgAECgYJDQAAAA==.',
Op='Ophin:BAAALgAECgQJCgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.',
Ov='Overheal:BAAALgAECgUJCwAAAA==.',
Pa='Padhu:BAAALgAECgUJCwAAAA==.Panamared:BAAALgAECgYJEQAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn8VAAIEAAYJnxEpCwBEAQAEAAYJnxEpCwBEAQAAAA==.Pezza:BAAALgAECgUJCwAAAA==.',
Ph='Phaze:BAAALgAECggJDwAAAA==.Phia:BAABLgAECn8dAAMVAAgJzCGiAgB3AgAVAAgJzCGiAgB3AgAfAAEJEhV7LABCAAAAAA==.Pholcus:BAAALgAECgMJAwAAAA==.',
Pr='Prothagon:BAABLgAECn8cAAIgAAgJBBhPAQBZAgAgAAgJBBhPAQBZAgAAAA==.',
Ps='Psylix:BAAALgAECgYJEQAAAA==.',
Ra='Raeburne:BAAALgAECgEJAQAAAA==.Raevennlumis:BAAALgAECgYJCgAAAA==.Rahkhard:BAAALgADCgkJEAAAAA==.Ransha:BAAALgAECgEJAQABLgAECggJFgALAPcPAA==.Rascdit:BAAALgAECgUJCAAAAA==.',
Re='Redwood:BAAALgADCgkJHwAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Regorian:BAAALgADCgMJAwAAAA==.Renwic:BAAALgAECgEJAQAAAA==.',
Rh='Rheingard:BAAALgADCgUJCAAAAA==.Rhemiroll:BAAALgAECgUJCAAAAA==.',
Ri='Rickroll:BAAALgADCggJEAAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn8VAAIeAAYJZSQBAgByAgAeAAYJZSQBAgByAgAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgADCgEJAQAAAA==.',
Ru='Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgQJCAAAAA==.Sagehawk:BAAALgAECgUJCQAAAA==.Sali:BAAALgADCgYJBAAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAAALgAECggJEgAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAAALgAECgYJEgAAAA==.Sarova:BAAALgADCgcJEQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJAgAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAAALgAECgQJCgAAAA==.Sellidor:BAAALgAECgIJAgAAAA==.Seriniyaa:BAAALgADCgkJIgAAAA==.',
Sh='Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAAALgAECgYJEAAAAA==.Shirito:BAABLgAECn8fAAIhAAgJeiQaAgCjAgAhAAgJeiQaAgCjAgAAAA==.Shiritodh:BAABLgAECn8VAAILAAcJ3yQpEwDmAgALAAcJ3yQpEwDmAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAAALgAECgcJDQAAAA==.Shyle:BAAALgAECgIJAwAAAA==.',
Si='Sienje:BAAALgAECgUJBwAAAA==.Simpleson:BAAALgAECgYJDgAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAAALgAECgUJDAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skribble:BAAALgAECgQJBQAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slaete:BAAALgAECgQJBwAAAA==.',
So='Solemn:BAAALgADCgkJCgABLgAECgIJAgAQAAAAAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAAALgAECgUJCAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgADCgkJCQAAAA==.Sorren:BAAALgADCgkJJAAAAA==.Sorrows:BAAALgAECgQJCQAAAA==.Sosukesagara:BAAALgADCgkJCQAAAA==.Sotta:BAAALgAECgMJBAAAAA==.Soulbled:BAABLgAECn8bAAIMAAgJ5A02DQCEAQAMAAgJ5A02DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAAALgADCgYJDAAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAAALgADCgkJHgAAAA==.Superbautumn:BAAALgAECgcJDgAAAA==.',
Sy='Sylo:BAABLgAECn8VAAIhAAcJFRX1IAAbAQAhAAcJFRX1IAAbAQAAAA==.Synnyca:BAAALgADCgcJEQABLgAECgYJCgAQAAAAAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgYJBgAAAA==.',
['Só']='Sóta:BAAALgAECgUJBwAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIhAAkJtBu3CQDjAQAhAAkJtBu3CQDjAQAAAA==.Taeonaki:BAAALgADCgUJBgAAAA==.Tagnaras:BAAALgADCggJEQAAAA==.Tahlang:BAAALgAECgEJAQAAAA==.Tainhen:BAAALgAECgUJDQAAAA==.Tali:BAAALgAECgUJDAAAAA==.Tamune:BAAALgAECgYJBwAAAA==.Tangle:BAAALgAECgcJBgAAAA==.Tanka:BAABLgAECn8UAAMHAAYJZCEUCAA3AgAHAAYJZCEUCAA3AgAGAAIJfRI1OwByAAAAAA==.Tanuki:BAAALgADCgkJIQAAAA==.Tashlaraz:BAEALgAECgEJAQAAAA==.Taurannosaur:BAAALgADCgEJAgAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.',
Te='Temporantus:BAAALgAECgEJAQAAAA==.',
Th='Thaddeus:BAAALgAECgYJDQAAAA==.Thariane:BAAALgADCgcJDgAAAA==.Therm:BAABLgAECn8pAAIUAAgJkyVmBwBcAwAUAAgJkyVmBwBcAwAAAA==.Thoramier:BAAALgAECgEJAQAAAA==.Thorgrymm:BAAALgADCgUJBQAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timoonja:BAAALgAECgQJBQAAAA==.',
To='Tonatuih:BAAALgAECgYJEwAAAA==.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAECgYJDAABLgAFFAUJDwAGADUkAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAAALgAECgQJCgAAAA==.Trinkat:BAAALgAECgEJAQAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgIJAgAAAA==.Tynk:BAAALgADCgcJFAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgADCgUJCAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgADCgkJIgAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn8gAAIRAAgJFgQ8IgAUAQARAAgJFgQ8IgAUAQAAAA==.Valwar:BAABLgAECn8bAAIFAAgJ4RmuBgC5AQAFAAgJ4RmuBgC5AQAAAA==.Vareyn:BAAALgAECgQJCAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCAAAAA==.Velithice:BAAALgAECgEJAgAAAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAABLgAECn8YAAMZAAcJoRvdAwCDAQAUAAYJBR9gRwANAgAZAAUJyRjdAwCDAQAAAA==.Vorth:BAAALgAECgYJEwAAAA==.Vorükh:BAABLgAECn8VAAMXAAYJ7ApADQBKAQAXAAYJ7ApADQBKAQAYAAUJ0AMMEQC4AAABLgAECgYJBgAQAAAAAA==.',
Vy='Vyrlana:BAABLgAECn8UAAMgAAgJLgiUCADkAAAgAAgJLgiUCADkAAANAAYJ0QLUSAC0AAAAAA==.',
Wa='Waldir:BAABLgAECn8UAAIaAAYJXCRFAgB+AgAaAAYJXCRFAgB+AgAAAA==.Waldstein:BAAALgAECgEJAQAAAA==.Wanted:BAABLgAECn8YAAMUAAcJYw+GhwBrAQAUAAcJYw+GhwBrAQAZAAYJ8QM4DQCKAAAAAA==.Watz:BAAALgAECgYJEQAAAA==.',
Xe='Xessala:BAAALgADCgkJCQAAAA==.',
Xh='Xheero:BAABLgAECn8gAAIVAAgJPxmRBwDwAQAVAAgJPxmRBwDwAQAAAA==.Xheerom:BAAALgAECgUJBQAAAA==.',
Yu='Yulica:BAAALgAECgEJAQAAAA==.',
Za='Zaffy:BAABLgAECn8XAAISAAcJ1gmBBQDsAAASAAcJ1gmBBQDsAAAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgADCgcJGwAAAA==.Zaleron:BAAALgADCggJEwAAAA==.Zanazath:BAABLgAECn8VAAMiAAcJbhgvEADZAQAiAAYJBRsvEADZAQANAAUJfwy4GwBdAAAAAA==.Zaruba:BAABLgAECn8UAAMKAAcJxAs9OwBgAQAKAAcJxAs9OwBgAQAJAAIJ5wCfmgA4AAAAAA==.Zatheon:BAAALgAECgYJEgAAAA==.Zatkyng:BAAALgAECgYJEQAAAA==.',
Ze='Zekos:BAAALgAECgMJAwAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8cAAIGAAgJnxtYAgD7AQAGAAgJnxtYAgD7AQAAAA==.Zimdalar:BAAALgAECgQJBQAAAA==.',
Zo='Zolls:BAAALgADCgEJAQAAAA==.',
Zu='Zulre:BAABLgAECn8dAAIhAAgJoRBpDAC+AQAhAAgJoRBpDAC+AQAAAA==.',
['Ôv']='Ôverkill:BAAALgADCgYJEwABLgAECgUJCwAQAAAAAA==.',
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

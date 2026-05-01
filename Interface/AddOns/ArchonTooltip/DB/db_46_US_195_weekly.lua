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

local lookup = {'Druid-Balance','Druid-Restoration','Mage-Frost','Warrior-Fury','Warrior-Arms','Priest-Holy','Paladin-Retribution','Warrior-Protection','Warlock-Demonology','Priest-Discipline','Monk-Mistweaver','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Unknown-Unknown','Hunter-BeastMastery','Mage-Arcane','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Paladin-Holy','DemonHunter-Havoc','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Hunter-Survival',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Ackrenoth:BAAALgAECgIJAgAAAA==.Actaeon:BAAALgAECgEJAQAAAA==.',
Ad='Adynn:BAABLgAECn8dAAMBAAcJxSQBBACCAgABAAcJxSQBBACCAgACAAIJrBaOoQCGAAAAAA==.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJAQAAAA==.',
Ag='Agrathayn:BAAALgADCgkJCQAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJJQADAFgZAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn8aAAMEAAcJoyQQBACHAgAEAAcJoyQQBACHAgAFAAEJ+BTzKQBBAAAAAA==.Alnharaelune:BAAALgADCgMJBgAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAAALgAECgUJCwAAAA==.',
An='Anali:BAABLgAECn8bAAIGAAgJciGUAgDWAgAGAAgJciGUAgDWAgAAAA==.Anani:BAAALgAECgIJAgAAAA==.Andavin:BAABLgAECn8aAAIHAAYJ0AMgfAC1AAAHAAYJ0AMgfAC1AAAAAA==.Angreifer:BAABLgAECn8nAAQIAAgJexqUBAAjAgAIAAgJexqUBAAjAgAEAAgJEA9dMgDiAQAFAAIJ1A5aLAA3AAAAAA==.Anori:BAAALgAECgYJDQAAAA==.',
Ao='Aonar:BAAALgAECgMJBAAAAA==.',
Ar='Arc:BAABLgAECn8YAAIJAAcJPiEADQBHAgAJAAcJPiEADQBHAgAAAA==.Archenteron:BAAALgAECgEJAQAAAA==.Arctat:BAAALgADCgcJCwAAAA==.Ardorcinder:BAAALgAECgEJAQAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.',
As='Asbjorne:BAAALgAECgUJEQAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Autumnmoon:BAAALgAECgYJEAAAAA==.',
Av='Avelos:BAABLgAECn8lAAMGAAkJSRg7CQAVAgAGAAkJSRg7CQAVAgAKAAQJhgbJRgCGAAAAAA==.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAAALgAECgUJDAAAAA==.Ayzmist:BAAALgAECgQJBAAAAA==.Ayzmyth:BAABLgAECn8XAAILAAYJKA4+HgAOAQALAAYJKA4+HgAOAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIMAAcJ7yAZDwCgAgAMAAcJ7yAZDwCgAgAAAA==.Bashra:BAAALgAECgQJCwAAAA==.',
Be='Beasic:BAABLgAECn8aAAMNAAcJYwdHJgDzAAANAAcJYwdHJgDzAAAMAAMJ3wDbkgBQAAAAAA==.Beletili:BAABLgAECn8cAAIGAAcJGBSNDgC6AQAGAAcJGBSNDgC6AQAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8YAAMOAAkJ9w8oUwCrAQAOAAkJpg8oUwCrAQAPAAYJjg6bCwDcAAAAAA==.Birdman:BAAALgAECgQJBAABLgAECgkJGAAOAPcPAA==.Bismuth:BAAALgADCgYJBgAAAA==.',
Bl='Blackraven:BAAALgAECgYJEAAAAA==.Blatendrg:BAABLgAECn8kAAIQAAgJBQ/KEgBwAQAQAAgJBQ/KEgBwAQAAAA==.Blindcloud:BAAALgAECgYJDwAAAA==.',
Bo='Boot:BAAALgAECgMJAwAAAA==.Bophedes:BAAALgAECgUJCgAAAA==.Borodemonin:BAEALgAECgUJBQABLgAFFAMJBQARAOwjAA==.Bosstun:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn8aAAIGAAcJQBa0DQDHAQAGAAcJQBa0DQDHAQAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgQJCAAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8VAAMSAAYJLh7UWQDkAQASAAYJLh7UWQDkAQATAAEJ3wtGGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgQJDAAAAA==.Charles:BAABLgAECn8nAAIUAAkJHCRsAABQAwAUAAkJHCRsAABQAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiot:BAABLgAECn8WAAIIAAYJvhdMDABeAQAIAAYJvhdMDABeAQAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8YAAIEAAcJdxHGFgB8AQAEAAcJdxHGFgB8AQAAAA==.Chuga:BAABLgAECn8WAAMJAAgJwQlKQgArAQAJAAgJ5QdKQgArAQAVAAQJCA3sFgBoAAAAAA==.',
Ci='Cimerian:BAABLgAECn8VAAIWAAYJWw/YHwAJAQAWAAYJWw/YHwAJAQAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgYJEQAXAAAAAA==.',
Co='Cobalticus:BAAALgAECgYJBgAAAA==.Corange:BAAALgADCgkJEAAAAA==.Corlock:BAAALgADCgQJBgAAAA==.Cormech:BAAALgAECgYJEAAAAA==.Cornite:BAAALgAECgYJCQAAAA==.',
Cr='Crizzo:BAABLgAECn8YAAIYAAYJiBplLgBXAQAYAAYJiBplLgBXAQAAAA==.',
Cy='Cyndrial:BAAALgADCgIJAgAAAA==.',
Da='Daddyslilgrl:BAAALgADCgcJBwAAAA==.Dakra:BAEBLgAECn8UAAIFAAcJfhOzBwCTAQAFAAcJfhOzBwCTAQAAAA==.Dalyeth:BAAALgAECgYJEAAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAAALgAFFAMJBAAAAA==.',
De='Decypher:BAAALgAECgYJEQAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Demonablaze:BAAALgAECgEJAQAAAA==.Dentik:BAAALgAECgYJDAAAAA==.Denuma:BAAALgADCgcJBwAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAECgYJEQAXAAAAAA==.',
Di='Diamair:BAABLgAECn8gAAMZAAcJqRfRBQDHAQAZAAcJqRfRBQDHAQADAAIJAAJOXwFBAAAAAA==.Diamones:BAAALgADCgkJCQAAAA==.Dixiee:BAAALgADCgYJFQAAAA==.',
Dn='Dnegelpal:BAABLgAECn8gAAIHAAkJCBCrHADeAQAHAAkJCBCrHADeAQAAAA==.',
Do='Dodgecharger:BAAALgAECgEJAQAAAA==.Dornix:BAABLgAECn8hAAIJAAgJlR6IEAAiAgAJAAgJlR6IEAAiAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Drakilu:BAABLgAECn8aAAIYAAcJvxd4GADPAQAYAAcJvxd4GADPAQAAAA==.Drasic:BAABLgAECn8pAAICAAgJtCFNAwAIAwACAAgJtCFNAwAIAwAAAA==.Dreddscott:BAAALgADCgYJBgABLgAECgcJFwAaAGMWAA==.Drophin:BAAALgADCgkJEwAAAA==.Drunken:BAABLgAECn8ZAAIbAAcJMx2/CAADAgAbAAcJMx2/CAADAgAAAA==.Druphin:BAAALgADCgQJCAAAAA==.',
Du='Durward:BAABLgAECn8bAAMSAAcJkBtkGgDqAQASAAcJkBtkGgDqAQATAAEJ3REFEAA7AAAAAA==.Duvo:BAAALgAECgYJDwAAAA==.',
Dw='Dwarfo:BAAALgAECgIJAwAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAAALgAECgUJEQAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAITAAgJah46AQBJAgATAAgJah46AQBJAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAAALgAECgcJEQAAAA==.Elemental:BAABLgAECn8oAAMNAAkJIxmkDgC6AgANAAkJIxmkDgC6AgAMAAMJuAkbjgBeAAABLgAFFAQJBgABAAAFAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgADCgEJAQAAAA==.Elloseth:BAAALgAECgYJEAAAAA==.Elmorin:BAAALgADCgkJEAAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAAALgAECgEJAQAAAA==.',
Ep='Epica:BAABLgAECn8YAAIDAAYJXRblRwBXAQADAAYJXRblRwBXAQAAAA==.',
Er='Eragonhawk:BAAALgAECgYJEwAAAA==.Eroldan:BAAALgAECgUJEQAAAA==.Erovianoria:BAACLgAFFH8HAAIYAAMJgQTJHgDeAAAYAAMJgQTJHgDeAAAuAAQKfyYAAhgACQm4FgIXAIACABgACQm4FgIXAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAAALgAECgYJEwAAAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8aAAIMAAcJzxGrJgA4AQAMAAcJzxGrJgA4AQAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAAALgAECgcJDAAAAA==.Fauxstorm:BAAALgAECgMJBAAAAA==.',
Fi='Finngan:BAABLgAECn8bAAIVAAgJWQwXBgBeAQAVAAgJWQwXBgBeAQAAAA==.Fireina:BAAALgAECgUJBQAAAA==.',
Fo='Forestkin:BAAALgAECgEJAQABLgAECgYJEAAXAAAAAA==.Fossilis:BAABLgAECn8YAAMcAAcJFQWzCAAMAQAcAAcJ+QSzCAAMAQAaAAUJ2wIUTwCzAAAAAA==.',
Fr='Frozenthunda:BAAALgAECgEJAgAAAA==.',
Fu='Furna:BAAALgAECgYJEAAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAABLgAECn8kAAIEAAkJFBJ+CgACAgAEAAkJFBJ+CgACAgAAAA==.',
Gh='Ghorienge:BAAALgAECgQJCQAAAA==.Ghostcat:BAAALgADCgIJAgAAAA==.',
Gi='Gilox:BAAALgAECgYJEwAAAA==.',
Gn='Gndmexia:BAAALgADCgkJEAAAAA==.Gneiss:BAAALgAECgIJAgAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8cAAICAAgJSSF5AwABAwACAAgJSSF5AwABAwAAAA==.',
Gr='Graymon:BAAALgAECgMJBAAAAA==.Greebo:BAAALgAECgMJBAAAAA==.Griknor:BAABLgAECn8cAAMFAAYJRQVKFQDRAAAFAAYJRQVKFQDRAAAEAAEJ0wLqWgAoAAAAAA==.Gryphonwrest:BAAALgADCgMJBAAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAAALgAECgQJBAAAAA==.',
Gw='Gwenyver:BAAALgAECgUJEQAAAA==.',
Ha='Hadoukendk:BAAALgAECgcJDAAAAA==.Hafaken:BAAALgADCgQJBAAAAA==.Hamord:BAAALgAECgUJEQAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgADCgQJBAAAAA==.Harliqynn:BAABLgAECn8ZAAIYAAgJNBnuIABAAgAYAAgJNBnuIABAAgAAAA==.Harlock:BAABLgAECn8XAAIaAAYJgRwXJADYAQAaAAYJgRwXJADYAQAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.',
He='Heartkiller:BAAALgAECgIJAgABLgAECgcJGAADAF0WAA==.',
Hi='Hiten:BAABLgAECn8aAAMaAAcJVxG5EABlAQAaAAcJcAu5EABlAQAcAAUJRBWIDQBEAQAAAA==.',
Ho='Hopedaimond:BAABLgAECn8bAAINAAcJPA5KHQAsAQANAAcJPA5KHQAsAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8aAAIYAAcJug2/LABfAQAYAAcJug2/LABfAQAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIMAAkJfCU6AADXAwAMAAkJfCU6AADXAwAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIWAAcJByOYBAC6AgAWAAcJByOYBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJDgAAAA==.',
Ie='Iepa:BAAALgADCgYJBgAAAA==.',
Il='Ilthad:BAAALgAECgYJBgAAAA==.',
Im='Imshalar:BAAALgAECgQJBAAAAA==.',
In='Inconcvabull:BAAALgAECggJDwAAAA==.Inferious:BAAALgAECgUJDAAAAA==.Inistus:BAAALgADCgUJBQAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Ischadè:BAAALgADCgUJBQAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgQJBwAAAA==.Itsirk:BAABLgAECn8gAAIdAAYJpBwMEgDMAQAdAAYJpBwMEgDMAQAAAA==.',
Iz='Izyebelle:BAABLgAECn8VAAIRAAYJhAHINgBaAAARAAYJhAHINgBaAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAAALgAECgYJEwAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jimmydin:BAABLgAECn8kAAMdAAkJ8xi0HgAiAgAdAAkJ8xi0HgAiAgAHAAYJgw8YSAAxAQAAAA==.Jix:BAABLgAECn8YAAMVAAgJkxi8DgDeAQAVAAYJuRy8DgDeAQAJAAQJSAw2rQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8oAAQOAAgJ/RNQGwCQAQAOAAgJRRNQGwCQAQAPAAMJyxWlHgCSAAAeAAEJYw4MbwA2AAAAAA==.',
Ju='Julkan:BAAALgAECgQJBQAAAA==.Junhoong:BAABLgAECn8cAAIHAAYJiBVHbQCjAQAHAAYJiBVHbQCjAQAAAA==.',
Jy='Jynnysa:BAAALgADCgEJAQABLgAECgYJEAAXAAAAAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAAALgAECgUJDAAAAA==.Kairoll:BAABLgAECn8iAAIGAAkJChV9BwA5AgAGAAkJChV9BwA5AgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Karaa:BAABLgAECn8UAAILAAYJSwLpLgCVAAALAAYJSwLpLgCVAAAAAA==.Kariena:BAAALgAECgYJEQAAAA==.Katesluage:BAABLgAECn8lAAIDAAkJWBmCDgBqAgADAAkJWBmCDgBqAgAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJJQADAFgZAA==.',
Ke='Keeya:BAAALgAECgYJEAAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kendari:BAAALgAECgYJDQAAAA==.Kernasas:BAAALgAECgQJEgAAAA==.Keslynn:BAAALgADCgYJBwABLgAECgYJEQAXAAAAAA==.Ketrani:BAAALgADCgYJDAABLgAECgYJEQAXAAAAAA==.',
Kh='Khiari:BAAALgADCgkJDgABLgAECgYJEAAXAAAAAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgIJAgAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJIQAJAJUeAA==.Kizaraan:BAAALgAECgUJEAAAAA==.',
Kl='Kleyntamar:BAAALgADCgkJJwAAAA==.',
Kr='Kritter:BAAALgAECgEJAQAAAA==.Krohm:BAABLgAECn8gAAIHAAgJryAoEwD6AgAHAAgJryAoEwD6AgAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgADCgkJFwAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgMJAwAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn8nAAIIAAgJpiKLAQC4AgAIAAgJpiKLAQC4AgAAAA==.Larachel:BAAALgAECgIJAgAAAA==.Laur:BAABLgAECn8YAAIRAAgJ6BDMJQCpAQARAAgJ6BDMJQCpAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8dAAIHAAkJKBsJCgCAAgAHAAkJKBsJCgCAAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAAALgAECgMJBAAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAgAAAA==.Lilipo:BAAALgAECgYJEgAAAA==.Liltara:BAAALgAECgUJDQAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJGAAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAABLgAECn8lAAIJAAgJ3Q5oKACNAQAJAAgJ3Q5oKACNAQAAAA==.Lokdan:BAAALgADCgkJCQAAAA==.Loula:BAAALgAECgUJEAAAAA==.Lowryder:BAABLgAECn8WAAMaAAgJng9aDQCVAQAaAAgJng9aDQCVAQAcAAEJmwZfIAAxAAAAAA==.Loxes:BAAALgAECgUJBwABLgAECgYJCwAXAAAAAA==.Loxy:BAAALgAECgQJBwAAAA==.',
Lu='Lukam:BAAALgAECgMJAwAAAA==.Lunaellana:BAAALgADCgcJCwAAAA==.Lus:BAABLgAECn8UAAMJAAYJsRfoegBmAQAJAAYJsRfoegBmAQAVAAIJuggrUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAAALgAECgIJAwABLgAECgcJHQACAGYbAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
Ma='Magicfang:BAAALgAECgMJAwAAAA==.Maiku:BAABLgAECn8XAAIJAAcJDw8vNABaAQAJAAcJDw8vNABaAQAAAA==.Makado:BAABLgAECn8XAAQVAAcJywd4LwD9AAAVAAcJPgd4LwD9AAAfAAMJPQaqDABiAAAJAAEJngFDMgEdAAAAAA==.Makaris:BAAALgADCgMJAwAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAAALgAECgYJDAAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Maycee:BAAALgADCgkJGQAAAA==.',
Mc='Mcnaugh:BAAALgAECgUJEQAAAA==.Mcsaltface:BAAALgAECgUJEQAAAA==.',
Me='Meddic:BAAALgADCgYJBwAAAA==.Menaras:BAACLgAFFH8HAAMMAAMJfw5PHACxAAAMAAMJfw5PHACxAAANAAIJYgJzHQCEAAAuAAQKfyYAAw0ACQkkHToSAJECAA0ACQkkHToSAJECAAwABgkyE5FBAHoBAAAA.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAECggJJwAIAHsaAA==.',
Mi='Mirosmundo:BAABLgAECn8sAAIbAAkJHh/cCAD5AgAbAAkJHh/cCAD5AgAAAA==.Mistfit:BAAALgAECgcJEAAAAA==.Miyagi:BAAALgAECgYJDwAAAA==.Miyu:BAABLgAECn8UAAMGAAcJYw+XOgBQAQAGAAcJYw+XOgBQAQARAAQJEBJwQQDuAAAAAA==.',
Mo='Mod:BAABLgAECn8lAAMNAAkJmyTYBABvAgANAAcJByTYBABvAgAMAAYJihOsUwA3AQAAAA==.Modaka:BAAALgAECgIJAgAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moggatorash:BAAALgAECgQJCAAAAA==.Mogtham:BAABLgAECn8aAAIgAAcJfg+ACgAfAQAgAAcJfg+ACgAfAQAAAA==.Moirenna:BAAALgAECgEJAQAAAA==.Moisticklez:BAAALgAECgMJBgAAAA==.Monkeyspaul:BAABLgAECn8bAAIUAAgJOxtPCQDkAQAUAAgJOxtPCQDkAQABLgAECgkJJQAIAA4bAA==.Moonfall:BAAALgAECgQJCAAAAA==.Moosader:BAABLgAECn8bAAMHAAcJxBWWUwDnAQAHAAcJxBWWUwDnAQAdAAYJZAiJVwAdAQAAAA==.Morellea:BAAALgAFFAIJAwAAAA==.Morighann:BAABLgAECn8kAAIYAAkJGiLbAQAGAwAYAAkJGiLbAQAGAwAAAA==.Morkith:BAAALgADCggJCAAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mousse:BAAALgADCgMJAwABLgAECgcJGwALAEUjAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgADCgkJGgABLgAECggJGwANAO4KAA==.',
My='Mylea:BAAALgADCgEJAQABLgAECgQJCAAXAAAAAA==.Mynkx:BAAALgAECgYJEAAAAA==.Mythyras:BAAALgAECgYJEAAAAA==.',
Na='Nahaman:BAAALgADCgkJGQAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8VAAIdAAYJEQ0lJgAYAQAdAAYJEQ0lJgAYAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8GAAIBAAQJAAWPDgAQAQABAAQJAAWPDgAQAQAuAAQKfxYABAIACAl0GxElACUCAAIACAl0GxElACUCACEAAwklEQ8kALQAAAEAAgn7Fu47AFcAAAAA.Netherite:BAAALgAECgUJEAAAAA==.Nethim:BAAALgAECgEJAQABLgAECgUJEAAXAAAAAA==.Netre:BAAALgAECgUJBQAAAA==.Nezana:BAABLgAECn8aAAQiAAcJBRRPDABEAQAiAAYJGhFPDABEAQAQAAQJUQyaLAC2AAAjAAMJNggiNwBeAAAAAA==.',
Ni='Nianah:BAAALgADCggJCgAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8lAAIgAAkJ7hwQAwAeAgAgAAkJ7hwQAwAeAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Noranna:BAAALgAECgMJBAAAAA==.',
['Nø']='Nøva:BAAALgADCgcJBwABLgAFFAMJAwAXAAAAAA==.',
Oh='Ohthesemyboo:BAAALgAECgQJBAAAAA==.Ohwellz:BAAALgAECgcJEwAAAA==.',
Op='Ophin:BAAALgAECgQJDgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.',
Ov='Overheal:BAAALgAECgYJEAAAAA==.',
Pa='Padhu:BAAALgAECgYJEAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn8XAAIaAAcJYxbDCgC9AQAaAAcJYxbDCgC9AQAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn8bAAIGAAcJNhOREQCSAQAGAAcJNhOREQCSAQAAAA==.Pezza:BAAALgAECgYJEAAAAA==.',
Ph='Phaze:BAABLgAECn8XAAIkAAkJTBNRBQAmAgAkAAkJTBNRBQAmAgAAAA==.Phia:BAABLgAECn8eAAMYAAkJ+h6vBACyAgAYAAkJ+h6vBACyAgAkAAEJEhV/LABCAAAAAA==.Pholcus:BAAALgAECgUJCAAAAA==.',
Pr='Prothagon:BAABLgAECn8lAAIiAAkJbBdSAgCfAgAiAAkJbBdSAgCfAgAAAA==.',
Ps='Psylix:BAABLgAECn8XAAIeAAcJsRZZDgBVAQAeAAcJsRZZDgBVAQAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAAALgAECgMJBAAAAA==.Raevennlumis:BAAALgAECgcJEgAAAA==.Rahkhard:BAAALgADCgkJEAAAAA==.Ransha:BAAALgAECgEJAQABLgAECgkJGAAOAPcPAA==.Rascdit:BAAALgAECgYJDgAAAA==.',
Re='Redwood:BAAALgAECgIJAgAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Regorian:BAAALgADCgMJAwAAAA==.Renwic:BAAALgAECgMJBAAAAA==.',
Rh='Rheingard:BAAALgADCgUJCAAAAA==.Rhemiroll:BAAALgAECgYJDgAAAA==.',
Ri='Rickroll:BAAALgAECgIJAgAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn8bAAMLAAcJRSOCAwC5AgALAAcJRSOCAwC5AgAUAAEJlheyPwBGAAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgADCgYJBgAAAA==.',
Ru='Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgQJCAAAAA==.Sagehawk:BAAALgAECgUJDgAAAA==.Sali:BAAALgADCgYJBAAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIUAAgJJBSPCgDNAQAUAAgJJBSPCgDNAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn8ZAAIDAAcJIRaOMAChAQADAAcJIRaOMAChAQAAAA==.Sarova:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgMJBAAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJAgAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAAALgAECgQJCgAAAA==.Sellidor:BAAALgAECgcJCQAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAAALgAECgMJAwAAAA==.',
Sh='Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8VAAIHAAYJFgJ1mgBwAAAHAAYJFgJ1mgBwAAAAAA==.Shirito:BAABLgAECn8oAAISAAkJDCZlAACBAwASAAkJDCZlAACBAwAAAA==.Shiritodh:BAABLgAECn8dAAIOAAgJYyWcBQCHAgAOAAgJYyWcBQCHAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8aAAMWAAkJcSFRAAAbAwAWAAkJcSFRAAAbAwAHAAYJsBY1egCGAQAAAA==.Shyle:BAAALgAECgQJBwAAAA==.',
Si='Sienje:BAAALgAECgYJDQAAAA==.Simpleson:BAABLgAECn8VAAMJAAcJFBd0HgC+AQAJAAcJuhZ0HgC+AQAVAAUJxQ7QNADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAAALgAECgUJEQAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgYJAQABLgAECgcJBgAXAAAAAA==.Skribble:BAAALgAECgQJCQAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slaete:BAAALgAECgQJBwAAAA==.',
So='Sokey:BAAALgADCgYJCAAAAA==.Solemn:BAAALgADCgkJCgABLgAECgcJCQAXAAAAAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAAALgAECgUJDAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgADCgkJCQAAAA==.Sorren:BAAALgADCgkJJAAAAA==.Sorrows:BAAALgAECgQJDQAAAA==.Sosukesagara:BAAALgADCgkJCQAAAA==.Sotta:BAAALgAECgMJBAAAAA==.Soulbled:BAABLgAECn8gAAIPAAgJ5A00DQCEAQAPAAgJ5A00DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAAALgAECgUJBQAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAAALgAECgMJAwAAAA==.Superbautumn:BAAALgAECgcJDgAAAA==.',
Sy='Sylo:BAABLgAECn8cAAISAAcJ8hV2KwCOAQASAAcJ8hV2KwCOAQAAAA==.Synnyca:BAAALgAECgEJAQABLgAECgYJEAAXAAAAAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgYJBgAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAISAAkJtBuBKACYAgASAAkJtBuBKACYAgAAAA==.Taeonaki:BAAALgADCgcJDQAAAA==.Tagnaras:BAAALgADCggJEQAAAA==.Tahlang:BAAALgAECgEJAgAAAA==.Tainhen:BAAALgAECgYJEwAAAA==.Tali:BAAALgAECgUJEAAAAA==.Tamune:BAAALgAECgYJDgAAAA==.Tangle:BAAALgAECgcJBgAAAA==.Tanka:BAABLgAECn8aAAMFAAcJRB5lBAD6AQAFAAcJRB5lBAD6AQAIAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJIQAAAA==.Tashlaraz:BAEALgAECgMJBAAAAA==.Taurannosaur:BAAALgADCgEJAgAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.',
Te='Temporantus:BAAALgAECgMJAwAAAA==.',
Th='Thaddeus:BAAALgAECgYJEgAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAXAAAAAA==.Therm:BAABLgAECn8xAAIHAAkJLCZpBwBcAwAHAAkJLCZpBwBcAwAAAA==.Thoramier:BAAALgAECgcJDAAAAA==.Thorgrymm:BAAALgADCgUJBQAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timoonja:BAAALgAECgQJBQAAAA==.',
To='Tonatuih:BAABLgAECn8cAAQPAAcJIByhDQB8AQAPAAYJgBahDQB8AQAOAAUJ0RL6PgDqAAAeAAYJuhnVHACyAAAAAA==.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAUJFAAIAGUlAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAAALgAECgUJDwAAAA==.Trinkat:BAAALgAECgMJBAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgQJBQAAAA==.Tynk:BAAALgADCgcJFAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgADCgUJCAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgAECgMJAwAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn8oAAIJAAgJdgSaSgARAQAJAAgJdgSaSgARAQAAAA==.Valwar:BAABLgAECn8kAAIEAAkJ8hmoBAB2AgAEAAkJ8hmoBAB2AgAAAA==.Vareyn:BAAALgAECgUJDAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgQJBQAAAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAABLgAECn8cAAMWAAcJ4xu9CACDAQAHAAYJVB9aRwANAgAWAAUJyRi9CACDAQABLgAECgkJHwAbAMEUAA==.Vorth:BAABLgAECn8ZAAMTAAcJ6RaMBABfAQATAAYJWReMBABfAQASAAcJ6RCcpwAyAQAAAA==.Vorükh:BAABLgAECn8XAAMcAAcJAApBDQBKAQAcAAYJXgtBDQBKAQAaAAYJrgORHQDbAAABLgAECgYJDwAXAAAAAA==.',
Vy='Vyrlana:BAABLgAECn8bAAMiAAkJERIkBgDqAQAiAAkJERIkBgDqAQAQAAYJ0QLbSAC0AAAAAA==.',
Wa='Waldir:BAABLgAECn8aAAIdAAcJXCS/AgDnAgAdAAcJXCS/AgDnAgAAAA==.Waldstein:BAAALgAECgMJBQAAAA==.Wanted:BAABLgAECn8YAAMHAAcJYw+GhwBrAQAHAAcJYw+GhwBrAQAWAAYJ8QOKGwCDAAAAAA==.Watz:BAABLgAECn8YAAIYAAcJAxA5LQBcAQAYAAcJAxA5LQBcAQAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xessala:BAAALgADCgkJCQAAAA==.',
Xh='Xheero:BAABLgAECn8iAAIYAAgJsRlVFgDfAQAYAAgJsRlVFgDfAQAAAA==.Xheerom:BAAALgAECgYJCwAAAA==.',
Yu='Yulica:BAAALgAECgMJBAAAAA==.',
Za='Zaffy:BAABLgAECn8fAAIVAAgJgw6oBQBqAQAVAAgJgw6oBQBqAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgADCgcJGwAAAA==.Zaleron:BAAALgADCgkJHAAAAA==.Zanazath:BAABLgAECn8aAAMjAAcJeBkwEADZAQAjAAYJRBwwEADZAQAQAAUJNhJKKwC8AAAAAA==.Zaruba:BAABLgAECn8bAAMNAAgJ7grRIAAUAQANAAgJ7grRIAAUAQAMAAIJ5wCcmgA4AAAAAA==.Zatheon:BAABLgAECn8dAAIHAAcJ6hsQHADiAQAHAAcJ6hsQHADiAQAAAA==.Zatkyng:BAABLgAECn8VAAIUAAYJGRNzLwBrAQAUAAYJGRNzLwBrAQAAAA==.',
Ze='Zekos:BAAALgAECgMJBgAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8lAAIIAAkJDhubAgB5AgAIAAkJDhubAgB5AgAAAA==.Zimdalar:BAAALgAECgQJCQAAAA==.',
Zo='Zolls:BAAALgAECgEJAQAAAA==.',
Zu='Zulre:BAABLgAECn8lAAISAAgJ8xWeGgDoAQASAAgJ8xWeGgDoAQAAAA==.',
['Ôv']='Ôverkill:BAAALgADCgcJFQABLgAECgYJEAAXAAAAAA==.',
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

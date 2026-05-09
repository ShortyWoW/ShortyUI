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

local lookup = {'Druid-Balance','Druid-Restoration','Mage-Frost','Warrior-Fury','Warrior-Arms','Priest-Holy','Paladin-Retribution','Warrior-Protection','Warlock-Demonology','Paladin-Holy','Mage-Fire','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Evoker-Augmentation','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Monk-Brewmaster','DeathKnight-Blood','Druid-Guardian','DemonHunter-Havoc','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Ackrenoth:BAAALgAECgcJDAAAAA==.Actaeon:BAAALgAECgEJAgAAAA==.',
Ad='Adynn:BAABLgAECn8lAAMBAAgJUSQQAwDhAgABAAgJUSQQAwDhAgACAAIJsBaMoQCGAAAAAA==.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJBAAAAA==.',
Ag='Agrathayn:BAAALgADCgkJCQAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJLQADAEwaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn8iAAMEAAgJkyTQAgDrAgAEAAgJkyTQAgDrAgAFAAEJ6RRLOABAAAAAAA==.Alnharaelune:BAAALgADCgMJBgAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAAALgAECgUJDwAAAA==.',
An='Anali:BAABLgAECn8bAAIGAAgJbiGuBADEAgAGAAgJbiGuBADEAgAAAA==.Anani:BAAALgAECgcJDAAAAA==.Andavin:BAABLgAECn8eAAIHAAYJYASElADFAAAHAAYJYASElADFAAAAAA==.Angreifer:BAABLgAECn8nAAQIAAgJixonBwATAgAIAAgJixonBwATAgAEAAgJEA9eMgDiAQAFAAIJ3w5OOwA3AAAAAA==.Anori:BAAALgAECgYJEwAAAA==.',
Ao='Aonar:BAAALgAECgQJCAAAAA==.',
Ar='Arc:BAABLgAECn8iAAIJAAgJwx7ADQB+AgAJAAgJwx7ADQB+AgAAAA==.Archenteron:BAAALgAECgIJAgAAAA==.Arctat:BAAALgADCgcJCwAAAA==.Ardorcinder:BAAALgAECgIJAgAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.Artea:BAAALgAECgIJAgAAAA==.',
As='Asbjorne:BAABLgAECn8XAAIKAAYJLRhtHQCbAQAKAAYJLRhtHQCbAQAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Augamand:BAAALgAECgYJBgAAAA==.Autumnmoon:BAABLgAECn8WAAILAAYJYA4zBAAmAQALAAYJYA4zBAAmAQAAAA==.',
Av='Avelos:BAABLgAECn8tAAQGAAkJuBnwCwAoAgAGAAkJuBnwCwAoAgAMAAQJhwbIRgCGAAANAAIJrgzqQQBsAAAAAA==.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAAALgAECgcJEgAAAA==.Ayzmist:BAAALgAECgQJBAAAAA==.Ayzmyth:BAABLgAECn8dAAIOAAYJjg7tJwALAQAOAAYJjg7tJwALAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIPAAcJ7yAWDwCgAgAPAAcJ7yAWDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn8lAAMQAAgJ8QojMADzAAAQAAcJAwgjMADzAAAPAAUJHgHUkgBQAAAAAA==.Beletili:BAABLgAECn8iAAIGAAcJkBTdFACwAQAGAAcJkBTdFACwAQAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8iAAMRAAkJERAqUwCrAQARAAkJwA8qUwCrAQASAAYJqQ5KDgDcAAAAAA==.Birdman:BAAALgAECgQJBAABLgAECgkJIgARABEQAA==.Bismuth:BAAALgADCgYJBgAAAA==.',
Bl='Blackraven:BAABLgAECn8WAAITAAYJuxhvFAByAQATAAYJuxhvFAByAQAAAA==.Blatendrg:BAABLgAECn8sAAIUAAgJNQ/jGAB5AQAUAAgJNQ/jGAB5AQAAAA==.Blindcloud:BAAALgAECgYJEwAAAA==.',
Bo='Boot:BAAALgAECgQJCQAAAA==.Bophedes:BAAALgAECgYJEgAAAA==.Borodemonin:BAEALgAECgYJDgABLgAFFAMJCAANAAQlAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn8lAAIGAAgJ1BUgDwD3AQAGAAgJ1BUgDwD3AQAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgQJBQAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgQJCAAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8cAAMVAAcJcBuhJwDgAQAVAAcJcBuhJwDgAQAWAAEJ3wtGGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIXAAkJlCTHAABVAwAXAAkJlCTHAABVAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJCQABLgAECggJJwAIAIsaAA==.Chiot:BAABLgAECn8hAAIIAAgJtRyYBQBGAgAIAAgJtRyYBQBGAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8cAAMEAAcJqxI6IABqAQAEAAcJehE6IABqAQAIAAQJchgbHADaAAAAAA==.Chuga:BAABLgAECn8WAAMJAAgJzgn6WAAiAQAJAAgJ6gf6WAAiAQAYAAQJHQ1+HQBhAAAAAA==.',
Ci='Cimerian:BAABLgAECn8aAAMZAAcJoA02FgDsAAAZAAcJoA02FgDsAAAHAAMJrwMAAAAAAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgYJEQAaAAAAAA==.',
Co='Cobalticus:BAAALgAECgYJCgAAAA==.Corange:BAAALgADCgkJEwAAAA==.Corlock:BAAALgADCgQJBgAAAA==.Cormech:BAAALgAECgYJEAAAAA==.Cornite:BAAALgAECgcJDwAAAA==.',
Cr='Crizzo:BAABLgAECn8gAAIbAAgJCRjpIADXAQAbAAgJCRjpIADXAQAAAA==.',
Cy='Cyndrial:BAAALgADCgIJAgAAAA==.',
Da='Daddyslilgrl:BAAALgAECgYJBgAAAA==.Dakra:BAEBLgAECn8fAAIFAAgJshoTBQArAgAFAAgJshoTBQArAgAAAA==.Dalyeth:BAABLgAECn8WAAISAAYJUCV8AwAWAgASAAYJUCV8AwAWAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAABLgAFFH8FAAIbAAMJzw09GQCiAAAbAAMJzw09GQCiAAAAAA==.Daunt:BAAALgADCgkJCQABLgAECggJIgAQAJ8LAA==.',
De='Decypher:BAABLgAECn8XAAIcAAgJgg4kCQCWAQAcAAgJgg4kCQCWAQAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Demonablaze:BAAALgAECgEJAQAAAA==.Dentik:BAAALgAECgYJEwAAAA==.Denuma:BAAALgADCgcJBwAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAECggJFwAcAIIOAA==.',
Di='Diamair:BAABLgAECn8rAAMdAAgJExjdAQD5AQAdAAgJExjdAQD5AQADAAIJAAJWXwFBAAAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAAALgAECgMJAwAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIHAAkJUhANKQDbAQAHAAkJUhANKQDbAQAAAA==.',
Do='Dodgecharger:BAAALgAECgMJBAAAAA==.Dornix:BAABLgAECn8pAAIJAAgJZyCgDgB0AgAJAAgJZyCgDgB0AgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAAALgAECgYJBgAAAA==.Drakilu:BAABLgAECn8lAAIbAAgJPRsXEwA4AgAbAAgJPRsXEwA4AgAAAA==.Drasic:BAABLgAECn8xAAICAAgJtSF+BQD/AgACAAgJtSF+BQD/AgAAAA==.Dreddscott:BAAALgADCgYJBgABLgAECggJIgAeAIwdAA==.Drophin:BAAALgADCgkJEwAAAA==.Drunken:BAABLgAECn8hAAIfAAgJyxt3CABDAgAfAAgJyxt3CABDAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn8jAAQVAAgJMR5REwBhAgAVAAgJMR5REwBhAgAgAAQJ/w6eHwDGAAAWAAEJ6hG9FQA3AAAAAA==.Duvo:BAAALgAECgYJEQAAAA==.',
Dw='Dwarfo:BAAALgAECgIJAwAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8VAAMhAAUJgwZ8HwBgAAAhAAUJgwZ8HwBgAAABAAQJpQASVQA5AAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIWAAgJlR4uAgArAgAWAAgJlR4uAgArAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAAALgAECggJEwAAAA==.Elemental:BAACLgAFFH8FAAIQAAMJ9AaTHADKAAAQAAMJ9AaTHADKAAAuAAQKfykAAxAACQkiGaUOALoCABAACQkiGaUOALoCAA8AAwm4CROOAF4AAAEuAAUUBAkKAAEAoQoA.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgADCgEJAQAAAA==.Elloseth:BAABLgAECn8WAAINAAYJhRfmGgBkAQANAAYJhRfmGgBkAQAAAA==.Elmorin:BAAALgAECgUJBQAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAAALgAECgMJBAAAAA==.',
Ep='Epica:BAABLgAECn8dAAIDAAcJ0hQDSQCNAQADAAcJ0hQDSQCNAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8ZAAIHAAYJEhySOACdAQAHAAYJEhySOACdAQAAAA==.Eroldan:BAABLgAECn8XAAMPAAYJliFpEQAvAgAPAAYJliFpEQAvAgAQAAEJKRL9YQA1AAAAAA==.Erovianoria:BAACLgAFFH8IAAIbAAMJggRHLgDXAAAbAAMJggRHLgDXAAAuAAQKfygAAhsACQm8Fv8WAIACABsACQm8Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8aAAIiAAcJNR1PCQD4AQAiAAcJNR1PCQD4AQAAAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8gAAIPAAgJFBINKAB/AQAPAAgJFBINKAB/AQAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAABLgAECn8UAAIHAAgJwhaiLADLAQAHAAgJwhaiLADLAQAAAA==.Fauxstorm:BAAALgAECgQJCAAAAA==.',
Fi='Finngan:BAABLgAECn8iAAIYAAgJWQxOCABYAQAYAAgJWQxOCABYAQAAAA==.Fireina:BAAALgAECgYJCwAAAA==.',
Fo='Forestkin:BAAALgAECgIJAgABLgAECgYJFgASAFAlAA==.Fossilis:BAABLgAECn8YAAMjAAcJHgWNCwAIAQAjAAcJAQWNCwAIAQAeAAUJ2wIOTwCzAAAAAA==.',
Fr='Frozenthunda:BAAALgAECgMJBQAAAA==.',
Fu='Furna:BAABLgAECn8ZAAIMAAYJWxSjFQCQAQAMAAYJWxSjFQCQAQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAABLgAECn8tAAIEAAkJUhWsCQBOAgAEAAkJUhWsCQBOAgAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgADCgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8WAAIjAAcJShDFBwBhAQAjAAcJShDFBwBhAQAAAA==.',
Gn='Gndmexia:BAAALgAECgEJAgAAAA==.Gneiss:BAAALgAECgMJBQAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAICAAkJhyDXAgBOAwACAAkJhyDXAgBOAwAAAA==.',
Gr='Graymon:BAAALgAECgQJCAAAAA==.Greebo:BAAALgAECgQJCAAAAA==.Griknor:BAABLgAECn8fAAMFAAYJRgV8HgDGAAAFAAYJRgV8HgDGAAAEAAQJBgOfSwCJAAAAAA==.Gryphonwrest:BAAALgADCgMJBAAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAAALgAECgQJBAAAAA==.',
Gw='Gwenyver:BAABLgAECn8XAAIHAAYJpQIcqgCfAAAHAAYJpQIcqgCfAAAAAA==.',
Ha='Hadoukendk:BAAALgAECgcJDAAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8XAAIZAAYJ+BCRGADSAAAZAAYJ+BCRGADSAAAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAABLgAECn8aAAIbAAgJ3RrtIABAAgAbAAgJ3RrtIABAAgAAAA==.Harlock:BAABLgAECn8gAAIeAAgJRh5XBgBNAgAeAAgJRh5XBgBNAgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.',
He='Heartkiller:BAAALgAECgIJAgABLgAECgkJHQADANIUAA==.',
Hi='Hiten:BAABLgAECn8lAAQeAAgJ1BXZCwDjAQAeAAgJmRPZCwDjAQAjAAUJRBWIDQBEAQAkAAEJjwgPFAAvAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8dAAIQAAgJbw6kHgBYAQAQAAgJbw6kHgBYAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8lAAIbAAgJBg9oKwCiAQAbAAgJBg9oKwCiAQAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIPAAkJfCU7AADXAwAPAAkJfCU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIZAAcJByOWBAC6AgAZAAcJByOWBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEgAAAA==.',
Ie='Iepa:BAAALgADCgYJBgAAAA==.',
Il='Ilthad:BAAALgAECgYJCwAAAA==.',
Im='Imshalar:BAAALgAECggJDQAAAA==.',
In='Inconcvabull:BAAALgAECggJDwAAAA==.Inferious:BAAALgAECgUJDAABLgAECgYJEgAaAAAAAA==.Infurryating:BAAALgAECgcJBwAAAA==.Inistus:BAAALgADCgUJBQAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Ischadè:BAAALgADCgkJCgAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgQJBwAAAA==.Itsirk:BAABLgAECn8iAAIKAAYJpBxZGgC3AQAKAAYJpBxZGgC3AQAAAA==.',
Iz='Izyebelle:BAABLgAECn8bAAINAAcJhwGpPQCDAAANAAcJhwGpPQCDAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8ZAAIZAAYJdyKEBwDeAQAZAAYJdyKEBwDeAQAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jimmydin:BAABLgAECn8tAAMKAAkJ8hizHgAiAgAKAAkJ8hizHgAiAgAHAAcJghPTOwCSAQAAAA==.Jix:BAABLgAECn8YAAMYAAgJkhi9DgDeAQAYAAYJtxy9DgDeAQAJAAQJSAw4rQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8pAAQRAAkJQhIRJQCrAQARAAkJoRERJQCrAQASAAMJyxWkHgCSAAAiAAEJYw4MbwA2AAAAAA==.',
Ju='Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn8kAAIHAAgJDRLUMQC1AQAHAAgJDRLUMQC1AQAAAA==.',
Jy='Jynnysa:BAAALgAECgMJAwABLgAECgYJFgAZANgeAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAAALgAECgYJEgAAAA==.Kairoll:BAABLgAECn8mAAIGAAkJuBXyCQBKAgAGAAkJuBXyCQBKAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECgEJAQAAAA==.Karaa:BAABLgAECn8YAAIOAAYJVAKtPACTAAAOAAYJVAKtPACTAAAAAA==.Kariena:BAABLgAECn8XAAIbAAYJmB3wKgCkAQAbAAYJmB3wKgCkAQAAAA==.Katesluage:BAABLgAECn8tAAIDAAkJTBoFFAB6AgADAAkJTBoFFAB6AgAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJLQADAEwaAA==.',
Ke='Keeya:BAABLgAECn8WAAIVAAYJuhFncAABAQAVAAYJuhFncAABAQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAAALgAECgYJDQAAAA==.Kernasas:BAABLgAECn8cAAIYAAYJORTDCQA6AQAYAAYJORTDCQA6AQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECgYJFwAbAJgdAA==.Ketrani:BAAALgAECgEJAgABLgAECgYJFwAbAJgdAA==.',
Kh='Khiari:BAAALgADCgkJFwABLgAECgYJFgAHAGgRAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgMJBQAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQAJAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECgYJFwAbAJgdAA==.Kitalidie:BAAALgAECgIJAgABLgAECgYJFwAbAJgdAA==.Kizaraan:BAABLgAECn8WAAIlAAYJGARgGADDAAAlAAYJGARgGADDAAAAAA==.',
Kl='Kleyntamar:BAAALgADCgkJJwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.',
Kr='Kritter:BAAALgAECgMJBAAAAA==.Krohm:BAABLgAECn8jAAIHAAkJaSAlEwD6AgAHAAkJaSAlEwD6AgAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgMJAwAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn8wAAIIAAgJ7CM5AgDJAgAIAAgJ7CM5AgDJAgAAAA==.Larachel:BAAALgAECgUJBwAAAA==.Laur:BAABLgAECn8gAAINAAkJ7hDQEgCwAQANAAkJ7hDQEgCwAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIHAAkJUBySDACdAgAHAAkJUBySDACdAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAAALgAECgQJCAAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn8YAAIXAAYJlAbHLADVAAAXAAYJlAbHLADVAAAAAA==.Liltara:BAAALgAECgUJEQAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJIQAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAABLgAECn8tAAIJAAgJvRTVJQDSAQAJAAgJvRTVJQDSAQAAAA==.Lokdan:BAAALgAECgMJAwAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8XAAIDAAcJVgKtoADSAAADAAcJVgKtoADSAAAAAA==.Lowryder:BAABLgAECn8cAAMeAAgJ5RMxDgDAAQAeAAgJ5RMxDgDAAQAjAAEJmwZfIAAxAAAAAA==.Loxes:BAAALgAECgcJDQABLgAECgYJCwAaAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJCAAAAA==.Lunaellana:BAAALgADCgcJCwAAAA==.Lus:BAABLgAECn8UAAMJAAYJsRfnegBmAQAJAAYJsRfnegBmAQAYAAIJuggrUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAAALgAECgYJDQABLgAECgkJJgACADMYAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
Ma='Magicfang:BAAALgAECgQJBAAAAA==.Maiku:BAABLgAECn8iAAIJAAgJnBJ0KQDAAQAJAAgJnBJ0KQDAAQAAAA==.Makado:BAABLgAECn8aAAQYAAgJCAgQEgDFAAAYAAcJQAcQEgDFAAAJAAMJLwWQtQBaAAAmAAMJRQYvEwBYAAAAAA==.Makaris:BAAALgADCgMJAwAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAAALgAECgYJEgAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAQAAAA==.Maycee:BAAALgADCgkJGQAAAA==.',
Mc='Mcnaugh:BAABLgAECn8XAAMgAAYJhRFAGgD1AAAgAAYJWA5AGgD1AAAVAAQJKRQneADxAAAAAA==.Mcsaltface:BAABLgAECn8XAAIHAAYJzhqQOgCXAQAHAAYJzhqQOgCXAQAAAA==.',
Me='Meddic:BAAALgADCgYJBwAAAA==.Menaras:BAACLgAFFH8IAAMPAAMJfw6wKQCpAAAPAAMJfw6wKQCpAAAQAAIJZgKuJgB/AAAuAAQKfysAAxAACQkmHToSAJECABAACQkmHToSAJECAA8ABwk3F5YyAEMBAAAA.Menarot:BAAALgAECgEJAQABLgAFFAMJCAAPAH8OAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAECggJJwAIAIsaAA==.',
Mi='Mikeydluffy:BAAALgAECggJCAAAAA==.Mirosmundo:BAACLgAFFH8HAAIfAAMJ1BN0HwDiAAAfAAMJ1BN0HwDiAAAuAAQKfy0AAh8ACQkmH9sIAPkCAB8ACQkmH9sIAPkCAAAA.Mistfit:BAABLgAECn8WAAIOAAcJSBP4GQB9AQAOAAcJSBP4GQB9AQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn8cAAMGAAgJaxKeOgBQAQAGAAcJPRGeOgBQAQANAAUJPxFuQQDuAAAAAA==.',
Mo='Mod:BAABLgAECn8rAAMQAAkJlCQtAwDfAgAQAAgJRyQtAwDfAgAPAAYJihOlUwA3AQAAAA==.Modaka:BAAALgAECgIJAgAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moggatorash:BAAALgAECgQJCgAAAA==.Mogtham:BAABLgAECn8lAAIhAAgJ5RWSBwC7AQAhAAgJ5RWSBwC7AQAAAA==.Moirenna:BAAALgAECgEJAQAAAA==.Moisticklez:BAAALgAECgMJBgAAAA==.Monkeyspaul:BAABLgAECn8cAAIXAAgJQhuoDQDdAQAXAAgJQhuoDQDdAQABLgAECgkJKwAIAM0cAA==.Moonfall:BAAALgAECgQJDQAAAA==.Moonpig:BAAALgAECgMJAwAAAA==.Moosader:BAABLgAECn8gAAMHAAcJyRWXUwDnAQAHAAcJyRWXUwDnAQAKAAYJcQiNVwAdAQAAAA==.Morellea:BAAALgAFFAIJAwAAAA==.Morighann:BAABLgAECn8qAAIbAAkJvSNvAgAjAwAbAAkJvSNvAgAjAwAAAA==.Morkith:BAAALgADCggJDgAAAA==.Morphalot:BAAALgAECgIJAgAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECggJJgAOAO4jAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgADCgkJIgABLgAECggJIgAQAJ8LAA==.',
My='Mylea:BAAALgADCgEJAQABLgAECgQJDQAaAAAAAA==.Mynkx:BAABLgAECn8WAAIHAAYJaBFBXQA1AQAHAAYJaBFBXQA1AQAAAA==.Mythyras:BAABLgAECn8WAAIZAAYJ2B4gCgCgAQAZAAYJ2B4gCgCgAQABLgAECgYJFgAZANgeAA==.',
Na='Nahaman:BAAALgADCgkJGQAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8VAAIKAAYJEg3NMQALAQAKAAYJEg3NMQALAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8KAAIBAAQJoQotEwAdAQABAAQJoQotEwAdAQAuAAQKfxYABAIACAl0Gw4lACUCAAIACAl0Gw4lACUCABwAAwklERAkALQAAAEAAgkLFw5LAFYAAAAA.Netherite:BAABLgAECn8WAAIdAAYJVBHlBAA1AQAdAAYJVBHlBAA1AQAAAA==.Nethim:BAAALgAECgEJAQABLgAECgYJFgAdAFQRAA==.Netre:BAAALgAECgYJDAAAAA==.Nezana:BAABLgAECn8iAAQlAAgJuhjQBwDyAQAlAAcJ6BbQBwDyAQAUAAUJ4wsDLwDqAAAnAAMJNQghNwBeAAAAAA==.',
Ni='Nianah:BAAALgADCggJCwAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIhAAkJyB1SAgCVAgAhAAkJyB1SAgCVAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Noranna:BAAALgAECgQJCAAAAA==.',
['Nø']='Nøva:BAAALgADCgcJBwABLgAFFAQJCQAHAPkdAA==.',
Oh='Ohthesemyboo:BAAALgAECgQJBAAAAA==.Ohwellz:BAAALgAECgcJEwABLgAECggJEQAaAAAAAA==.',
Op='Ophin:BAAALgAECgQJEAAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAAALgAECgYJCQAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.',
Ov='Overheal:BAABLgAECn8WAAIlAAYJQQ0nEgAbAQAlAAYJQQ0nEgAbAQAAAA==.',
Pa='Padhu:BAABLgAECn8WAAIfAAYJpwjAMwDLAAAfAAYJpwjAMwDLAAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn8iAAIeAAgJjB39BQBXAgAeAAgJjB39BQBXAgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn8mAAIGAAgJXxWJEADkAQAGAAgJXxWJEADkAQAAAA==.Pezza:BAABLgAECn8WAAIPAAYJCRNWMwA/AQAPAAYJCRNWMwA/AQAAAA==.',
Ph='Phantomlord:BAAALgAECgUJBgABLgAECgkJHQADANIUAA==.Phaze:BAABLgAECn8aAAITAAkJ0BfvBgA/AgATAAkJ0BfvBgA/AgAAAA==.Phia:BAABLgAECn8eAAMbAAkJ/x7CCgCOAgAbAAkJ/x7CCgCOAgATAAEJEhV+LABCAAAAAA==.Pholcus:BAAALgAECgUJCAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMlAAkJshecAwCPAgAlAAkJshecAwCPAgAUAAIJQBZ5RACGAAAAAA==.',
Ps='Psylix:BAABLgAECn8iAAIiAAgJvRdbCQD3AQAiAAgJvRdbCQD3AQAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAAALgAECgQJCAAAAA==.Raevennlumis:BAABLgAECn8aAAIHAAgJLQYkZgAhAQAHAAgJLQYkZgAhAQAAAA==.Rahkhard:BAAALgAECgMJAwAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAAALgAECgEJAQABLgAECgkJIgARABEQAA==.Rascdit:BAAALgAECgYJDgAAAA==.',
Re='Redwood:BAAALgAECgUJBwAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBAAAAA==.',
Rh='Rheingard:BAAALgADCgUJCAAAAA==.Rhemiroll:BAAALgAECgYJDgAAAA==.Rhintalle:BAEALgADCgIJAgABLgAECgMJBwAaAAAAAA==.',
Ri='Rickroll:BAAALgAECgIJAgAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn8mAAMOAAgJ7iNLAgA2AwAOAAgJ7iNLAgA2AwAXAAEJkBdkUgBGAAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgADCgcJDAAAAA==.',
Ru='Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgQJCAAAAA==.Sagehawk:BAAALgAECgYJEwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIXAAgJJhRkDwDFAQAXAAgJJhRkDwDFAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn8hAAIDAAgJwBk8IAAqAgADAAgJwBk8IAAqAgAAAA==.Sarova:BAAALgAECgMJBAAAAA==.Satori:BAAALgAECgQJCAAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJAgAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8VAAIVAAgJtBiNHgARAgAVAAgJtBiNHgARAgAAAA==.Sellidor:BAAALgAECggJEQAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAAALgAECgUJCAAAAA==.',
Sh='Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8fAAIHAAgJ8QJdlQDEAAAHAAgJ8QJdlQDEAAAAAA==.Shirito:BAABLgAECn8uAAIVAAkJGibFAAB/AwAVAAkJGibFAAB/AwAAAA==.Shiritodh:BAABLgAECn8eAAIRAAgJeCWsBwCsAgARAAgJeCWsBwCsAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8jAAMZAAkJ7iKMAAAjAwAZAAkJ7iKMAAAjAwAHAAYJsBY4egCGAQAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn8VAAIHAAgJghmuIgD7AQAHAAgJghmuIgD7AQAAAA==.Simpleson:BAABLgAECn8dAAMJAAgJkBdqHAAGAgAJAAgJkBdqHAAGAgAYAAUJxQ7NNADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAAALgAECgUJEQAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgYJAgABLgAECgcJBgAaAAAAAA==.Skribble:BAAALgAECgQJDAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8ZAAIJAAYJyRBWUQA2AQAJAAYJyRBWUQA2AQAAAA==.Slaete:BAAALgAECgYJDQAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAAALgAECgEJAgAAAA==.Solemn:BAAALgAECgYJBgABLgAECggJEQAaAAAAAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAAALgAECgYJEgAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgMJAwAAAA==.Sorren:BAAALgADCgkJJAAAAA==.Sorrows:BAAALgAECgYJEwAAAA==.Sosukesagara:BAAALgAECgMJAwAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8kAAISAAkJmQ40DQCEAQASAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAAALgAECgYJCwAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAAALgAECgUJCAAAAA==.Superbautumn:BAABLgAECn8XAAIHAAkJox88CwCqAgAHAAkJox88CwCqAgAAAA==.',
Sy='Sylo:BAABLgAECn8cAAIVAAcJ9RU6PwCAAQAVAAcJ9RU6PwCAAQAAAA==.Synalaid:BAAALgAECgEJAQAAAA==.Synnyca:BAAALgAECgEJAQABLgAECgYJFgAZANgeAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgYJCgAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIVAAkJsht5KACYAgAVAAkJsht5KACYAgAAAA==.Taeonaki:BAAALgADCgcJDQAAAA==.Tagnaras:BAAALgADCggJEQAAAA==.Tahlang:BAAALgAECgEJBAAAAA==.Tali:BAABLgAECn8WAAMbAAYJzgsYTwAgAQAbAAYJzgsYTwAgAQAoAAEJYwbhKwAoAAAAAA==.Tamune:BAAALgAECgcJDwAAAA==.Tangle:BAAALgAECgcJBgAAAA==.Tanka:BAABLgAECn8lAAMFAAgJ9iN5AQDeAgAFAAgJ9iN5AQDeAgAIAAIJfRI1OwByAAAAAA==.Tanuki:BAAALgADCgkJKgAAAA==.Tashlaraz:BAEALgAECgMJBwAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAQAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgMJAwABLgAECggJHQAaAAAAAQ==.',
Te='Temporantus:BAAALgAECgQJBgAAAA==.',
Th='Thaddeus:BAAALgAECgcJEwAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAaAAAAAA==.Therm:BAACLgAFFH8FAAIHAAIJKCZ5NADlAAAHAAIJKCZ5NADlAAAuAAQKfzMAAgcACQlJJmgHAFwDAAcACQlJJmgHAFwDAAAA.Thoramier:BAAALgAECgcJEgAAAA==.Thorgrymm:BAAALgADCgUJBQAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timoonja:BAAALgAECgQJCQAAAA==.',
To='Tonatuih:BAABLgAECn8kAAQSAAgJHxyiDQB8AQASAAYJlxaiDQB8AQARAAYJPBMcRgAmAQAiAAgJnxkbHAD5AAAAAA==.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAYJFgAIAAMjAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8ZAAImAAgJCBYUAwDcAQAmAAgJCBYUAwDcAQAAAA==.Triipod:BAAALgADCgUJCQAAAA==.Trinkat:BAAALgAECgQJCAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgcJBwAAAA==.Tynk:BAAALgADCgcJFAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgADCgUJCAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgAECgUJCAAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn8xAAIJAAkJ9wTpTABCAQAJAAkJ9wTpTABCAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIEAAkJ8hn7CABZAgAEAAkJ8hn7CABZAgAAAA==.Vareyn:BAAALgAECgYJEAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJBwAAAA==.Velle:BAAALgAECgUJBQABLgAFFAMJCAAbAIIEAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAABLgAECn8cAAMZAAcJ5xsWDAB7AQAHAAYJVR9cRwANAgAZAAUJ1hgWDAB7AQABLgAECgkJKgAfAGoZAA==.Vorth:BAABLgAECn8hAAMWAAgJtRfFBACYAQAWAAcJNRjFBACYAQAVAAcJ+BJZcQD/AAAAAA==.Vorükh:BAABLgAECn8XAAMjAAcJCApBDQBKAQAjAAYJaAtBDQBKAQAeAAYJsAPHJADTAAABLgAECggJEgAaAAAAAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAIlAAMJgAR6FQCyAAAlAAMJgAR6FQCyAAAuAAQKfxwAAyUACQndEuwHAO8BACUACQndEuwHAO8BABQABgnRAt1IALQAAAAA.',
Wa='Waldir:BAABLgAECn8lAAIKAAgJ9SRsAQBZAwAKAAgJ9SRsAQBZAwAAAA==.Waldstein:BAAALgAECgQJDAAAAA==.Wanted:BAABLgAECn8iAAQHAAcJYw+IhwBrAQAHAAcJYw+IhwBrAQAKAAUJnBK8LAArAQAZAAYJegVhIQCKAAAAAA==.Watz:BAABLgAECn8gAAIbAAgJahMTIQDWAQAbAAgJahMTIQDWAQAAAA==.',
We='Wensa:BAAALgAECgUJBQAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xessala:BAAALgAECgMJAwAAAA==.',
Xh='Xheero:BAABLgAECn8qAAIbAAgJuBoyGgABAgAbAAgJuBoyGgABAgAAAA==.Xheerom:BAAALgAECgYJCwAAAA==.',
Yu='Yulica:BAAALgAECgQJCAAAAA==.',
Za='Zaffy:BAABLgAECn8mAAIYAAgJww+kBgCCAQAYAAgJww+kBgCCAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgEJAQAAAA==.Zaleron:BAAALgADCgkJHAAAAA==.Zanazath:BAABLgAECn8bAAMnAAcJeRkyEADZAQAnAAYJRhwyEADZAQAUAAYJIRKxLQDxAAAAAA==.Zaruba:BAABLgAECn8iAAMQAAgJnwvUJwAeAQAQAAgJnwvUJwAeAQAPAAIJ5wCVmgA4AAAAAA==.Zatheon:BAABLgAECn8iAAIHAAgJChl4HwAMAgAHAAgJChl4HwAMAgAAAA==.Zatkyng:BAABLgAECn8aAAIXAAcJghBvLwBrAQAXAAcJghBvLwBrAQAAAA==.',
Ze='Zekos:BAAALgAECgQJBwAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAIIAAkJzRxMAwCYAgAIAAkJzRxMAwCYAgAAAA==.Zimdalar:BAAALgAECgQJDQAAAA==.',
Zo='Zolls:BAAALgAECgMJBQAAAA==.',
Zu='Zulre:BAABLgAECn8vAAIVAAkJAhVzGQAzAgAVAAkJAhVzGQAzAgAAAA==.',
['Ôv']='Ôverkill:BAAALgADCgcJGwABLgAECgYJFgAlAEENAA==.',
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

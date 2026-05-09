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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Priest-Shadow','Warrior-Fury','Mage-Fire','Priest-Holy','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Mage-Frost','DeathKnight-Unholy','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','Monk-Brewmaster','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Paladin-Protection','Monk-Windwalker','Mage-Arcane','Monk-Mistweaver','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','DemonHunter-Vengeance','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarchon:BAABLgAECn8eAAIBAAcJ9CH+BwCVAgABAAcJ9CH+BwCVAgAAAA==.',
Ad='Aduin:BAAALgAECgMJAwAAAA==.',
Ae='Aedarelyn:BAAALgAECgQJCwAAAA==.Aellet:BAABLgAECn8VAAMCAAcJqB2gIQDoAQACAAcJyxygIQDoAQADAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgIJAgAAAA==.',
Ak='Akky:BAABLgAECn8fAAIEAAgJ2R5vBABtAgAEAAgJ2R5vBABtAgAAAA==.Aksafiya:BAABLgAECn82AAIFAAcJcBJaGgBpAQAFAAcJcBJaGgBpAQAAAA==.',
Al='Alal:BAAALgAECgYJCAAAAA==.Alandras:BAABLgAECn8XAAIGAAYJxAhRNAD4AAAGAAYJxAhRNAD4AAAAAA==.Alaras:BAACLgAFFH8PAAIFAAUJiBC+CwBGAQAFAAUJiBC+CwBGAQAuAAQKfxcAAgUACQnQFQoaAA8CAAUACQnQFQoaAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8hAAIDAAgJcBcsAwDYAQADAAgJcBcsAwDYAQAAAA==.Allrianne:BAAALgAECgMJBAAAAA==.Allyriae:BAABLgAECn8VAAIHAAcJjAlfBAAbAQAHAAcJjAlfBAAbAQAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8WAAIIAAgJKg/sMQB5AQAIAAgJKg/sMQB5AQAAAA==.',
Am='Ambilena:BAAALgAECgYJCgAAAA==.',
An='Andoros:BAABLgAECn8qAAIJAAgJVh26EgA2AgAJAAgJVh26EgA2AgAAAA==.Angiliana:BAAALgAECgUJCwAAAA==.Angvall:BAAALgAECgYJBgABLgAECgEJAQAKAAAAAA==.Anzurath:BAABLgAECn8dAAILAAYJKBXkWQA9AQALAAYJKBXkWQA9AQAAAA==.',
Ap='Applebow:BAABLgAECn8XAAIMAAYJ4BGKGAAHAQAMAAYJ4BGKGAAHAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgADCgMJCAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgMJAwAAAA==.Arylin:BAABLgAECn8cAAINAAcJXyIiGQBUAgANAAcJXyIiGQBUAgAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEALgAECgQJCwAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAKAAAAAA==.Asnabel:BAAALgAECgYJEgAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCQAOAEMlAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgADCgkJFAAAAA==.Ayden:BAAALgAECgQJBwAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAKAAAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgADCgIJAgAAAA==.',
Bl='Blee:BAABLgAECn8YAAMPAAYJ1xG4GQBkAQAPAAYJ1xG4GQBkAQAFAAQJagWMSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8WAAICAAYJbxv+OwB4AQACAAYJbxv+OwB4AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8YAAIQAAYJ1B4tJwC2AQAQAAYJ1B4tJwC2AQAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8WAAIOAAYJNRE2XgApAQAOAAYJNRE2XgApAQAAAA==.Brood:BAABLgAECn8lAAIOAAgJsBBYOQCUAQAOAAgJsBBYOQCUAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAAALgAECgYJCQAAAA==.',
Ca='Cailaranel:BAABLgAECn8gAAIRAAcJagkuCQA8AQARAAcJagkuCQA8AQAAAA==.Calaul:BAAALgAECgYJEQAAAA==.Calenbraga:BAAALgAECgQJDQAAAA==.Calisim:BAAALgAECgUJCwAAAA==.Callidae:BAABLgAECn8kAAIIAAkJBwo8IABGAQAIAAkJBwo8IABGAQAAAA==.Calmnbald:BAABLgAECn8ZAAISAAcJdBdYIwAhAQASAAcJdBdYIwAhAQAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8YAAITAAgJQgzjGwAlAQATAAgJQgzjGwAlAQAAAA==.Cataryn:BAABLgAECn8aAAIQAAcJPSQwEABUAgAQAAcJPSQwEABUAgAAAA==.Catt:BAABLgAECn8pAAIBAAcJBhYQFgDeAQABAAcJBhYQFgDeAQAAAA==.',
Ce='Cellebur:BAAALgAECgQJCwAAAA==.Ceta:BAABLgAECn8hAAIIAAcJ2xrrEwC7AQAIAAcJ2xrrEwC7AQAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAABLgAECn8lAAMUAAgJlxaGEwC7AQAUAAcJtBmGEwC7AQAVAAcJAxK4JgCHAQAAAA==.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn8XAAINAAYJnwMspwDFAAANAAYJnwMspwDFAAAAAA==.Cizean:BAAALgAECgUJDwAAAA==.',
Co='Cometopapa:BAABLgAECn8aAAMWAAgJ9g+6CABYAQAWAAcJ/BC6CABYAQAOAAcJpwgOZwAVAQAAAA==.',
Cr='Craivan:BAAALgADCgIJAgAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8iAAINAAgJ5hrvIAAmAgANAAgJ5hrvIAAmAgAAAA==.Crowe:BAAALgAECgMJBAABLgAECgUJBQAKAAAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAAALgAECgUJCQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgUJCQAAAA==.Damia:BAABLgAECn8XAAMXAAYJgRiDFABrAQAXAAYJgRiDFABrAQARAAIJ+guBFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8eAAIMAAcJIiWnBABrAgAMAAcJIiWnBABrAgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgcJHgAMACIlAA==.Delvarrieth:BAAALgAECgUJDwAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAAALgAECgcJEgAAAA==.Dercuur:BAAALgAECgUJDQAAAA==.Devoursol:BAABLgAECn8fAAMYAAgJmAvFOABTAQAYAAgJZAvFOABTAQAZAAIJrg42XABvAAAAAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgADCgkJFAAAAA==.Drainmee:BAAALgAECgUJCwAAAA==.Draknol:BAAALgADCgkJFAAAAA==.Dregoth:BAABLgAECn8fAAIOAAgJSwd/TgBQAQAOAAgJSwd/TgBQAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMJAAkJ3x5jEAC0AgAJAAkJ3x5jEAC0AgAaAAEJxQkXXgAqAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elynth:BAABLgAECn8dAAICAAcJ2Rw3HgD7AQACAAcJ2Rw3HgD7AQAAAA==.',
En='Endlessyueh:BAAALgADCgYJDQAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgcJFQACAKgdAA==.',
Ev='Evilis:BAAALgADCgMJBAAAAA==.Evolnasty:BAAALgAECgYJBwABLgAFFAQJCgALAHoOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8GAAIbAAMJ3xuhAwD5AAAbAAMJ3xuhAwD5AAAuAAQKfyYAAhsACAmhJCQBAOECABsACAmhJCQBAOECAAAA.Falunia:BAABLgAECn8bAAINAAYJDQdIigD+AAANAAYJDQdIigD+AAAAAA==.Fangren:BAAALgAECgUJCwAAAA==.Fariah:BAAALgAECgUJCQAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAAALgAECgYJEgAAAA==.',
Fe='Felscythe:BAAALgAECgUJDgAAAA==.Felynn:BAABLgAECn8cAAIBAAgJPRbXEwD0AQABAAgJPRbXEwD0AQAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgMJAwAAAA==.',
Fi='Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAAALgAECgUJDwAAAA==.',
Fl='Flaeli:BAABLgAECn8XAAINAAYJbhLnZQBFAQANAAYJbhLnZQBFAQAAAA==.Flemish:BAAALgADCgkJHwAAAA==.Flextame:BAAALgAECgQJCgAAAA==.Flipalicious:BAABLgAECn8tAAIVAAgJrx0hCACqAgAVAAgJrx0hCACqAgAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8VAAIFAAYJJxbwGgBkAQAFAAYJJxbwGgBkAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8VAAIQAAYJZgy2TwAfAQAQAAYJZgy2TwAfAQAAAA==.Gazo:BAAALgADCggJGQABLgAECgcJGwAcAH0gAA==.',
Ge='Gemboss:BAABLgAECn8qAAMLAAYJ+x9hLwC/AQALAAYJ+x9hLwC/AQABAAQJLRK6YwDtAAAAAA==.Gerbo:BAABLgAECn8mAAMNAAkJwxJ3LgDnAQANAAkJwxJ3LgDnAQAdAAMJrwW/FQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8ZAAIcAAgJxQYfLADYAAAcAAgJxQYfLADYAAAAAA==.Ginodh:BAAALgAECgcJEQABLgAECggJFwAMAAcPAA==.Ginomage:BAAALgAECgcJCgABLgAECggJFwAMAAcPAA==.Ginomonk:BAAALgAECgUJBQABLgAECggJFwAMAAcPAA==.Ginopally:BAAALgAECgQJCQABLgAECggJFwAMAAcPAA==.Girth:BAAALgADCgIJAgAAAA==.Gizelli:BAAALgADCgMJAwAAAA==.',
Go='Gordonn:BAAALgADCgcJCwAAAA==.',
Gr='Grubetsell:BAAALgADCgUJCgABLgAECgYJIQAeAJIjAA==.Grubetsella:BAABLgAECn8hAAIeAAYJkiMBDQAZAgAeAAYJkiMBDQAZAgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIYAAYJXBszPQBDAQAYAAYJXBszPQBDAQAAAA==.Gumpers:BAAALgAECggJEwAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAAALgADCgkJHAAAAA==.',
Ha='Hanoumatoi:BAAALgAECgUJBQAAAA==.Haralambos:BAAALgAECgQJCwAAAA==.Haralogain:BAAALgADCgMJAwABLgAECgQJCwAKAAAAAA==.Harithon:BAABLgAECn8aAAIfAAgJzxsoBAAtAgAfAAgJzxsoBAAtAgAAAA==.Havvöc:BAABLgAECn8hAAIBAAcJDR95CgBpAgABAAcJDR95CgBpAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAAALgAECgYJDAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAAALgAECgUJCwAAAA==.Heyokagi:BAABLgAECn8eAAMgAAgJ7BucAwBJAgAgAAgJ7BucAwBJAgAhAAIJ1BS6JgBnAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgcJFQACAKgdAA==.Hordkilla:BAABLgAECn8cAAILAAgJtgXnZAAkAQALAAgJtgXnZAAkAQAAAA==.Hownowbrncw:BAABLgAECn8YAAILAAYJFhywOACdAQALAAYJFhywOACdAQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn8fAAIYAAgJ5Bg8FwACAgAYAAgJ5Bg8FwACAgAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgQJBwAAAA==.',
Im='Imathdal:BAABLgAECn8fAAIiAAgJPwybCQBfAQAiAAgJPwybCQBfAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAKAAAAAA==.Insoniacyun:BAAALgAECgQJBAAAAA==.',
Is='Iselian:BAAALgAECggJGwAAAQ==.Ishanu:BAABLgAECn8UAAIFAAgJUBvjCAA4AgAFAAgJUBvjCAA4AgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAKAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJEQABLgADCggJDgAKAAAAAA==.Jax:BAACLgAFFH8JAAINAAQJ9CA2GAB/AQANAAQJ9CA2GAB/AQAuAAQKfyEAAg0ACAk+Iw8TADUDAA0ACAk+Iw8TADUDAAAA.',
Jb='Jblockiv:BAAALgADCgUJBQAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn8dAAMVAAYJKSEfEAA+AgAVAAYJKSEfEAA+AgAUAAMJWQafcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgQJBQAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn8jAAIdAAgJJAt2AwB7AQAdAAgJJAt2AwB7AQAAAA==.Jetfires:BAABLgAECn8nAAIQAAgJzRmJGAAMAgAQAAgJzRmJGAAMAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAAALgAECgMJBgAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jozhua:BAAALgADCgkJMAAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.',
Ka='Kaedren:BAAALgADCgkJDQAAAA==.Kaelaya:BAABLgAECn8UAAIiAAYJmgaLEgDMAAAiAAYJmgaLEgDMAAAAAA==.Kaelorien:BAABLgAECn8jAAIeAAgJIQ0dHgBXAQAeAAgJIQ0dHgBXAQAAAA==.Kaetta:BAABLgAECn8VAAINAAYJrwMZnwDVAAANAAYJrwMZnwDVAAAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgMJAwAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAAALgADCgUJCAAAAA==.Kaldevayn:BAAALgADCgkJHwAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgIJAgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAAALgAECgkJEQAAAA==.Kardanis:BAABLgAECn8eAAIVAAcJ9SU3BAAAAwAVAAcJ9SU3BAAAAwAAAA==.Kashe:BAAALgAECgQJCQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8eAAIVAAcJLRK+MQBIAQAVAAcJLRK+MQBIAQAAAA==.Kaydencia:BAAALgAECgYJEQAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgMJAwAAAA==.Kazureshal:BAAALgADCgkJBwAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgADCgEJAQAAAA==.',
Ki='Ki:BAAALgAECgMJAwAAAA==.Kiddow:BAAALgAECgMJBQAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgADCgQJBAAAAA==.Kiri:BAAALgADCgkJEAAAAA==.Kitamii:BAABLgAECn8UAAIgAAYJchbEEQCQAQAgAAYJchbEEQCQAQAAAA==.Kivrin:BAAALgAECgUJCgAAAA==.',
Kr='Kringlë:BAABLgAECn8eAAIQAAgJdSAHDAB/AgAQAAgJdSAHDAB/AgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.',
Ky='Kymma:BAABLgAECn8cAAILAAYJTwxkdQABAQALAAYJTwxkdQABAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAAALgAECgYJEwAAAA==.Laitue:BAAALgAECgQJCAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAgAAAA==.Lazengann:BAABLgAECn8YAAMYAAgJYhP2PQBAAQAYAAgJ+RL2PQBAAQAZAAEJvxblagA7AAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Legevia:BAAALgAECgUJDAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn8iAAILAAgJoBBDNwChAQALAAgJoBBDNwChAQAAAA==.Letifer:BAAALgADCgUJBQAAAA==.Leucetios:BAAALgADCgkJCwAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAAALgAECgcJEgAAAA==.Lightbeard:BAAALgAECgUJDwAAAA==.Lightdawns:BAAALgAECgQJBAAAAA==.Lightforge:BAAALgAECgYJEwAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgADCgkJDgAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgADCgkJDgAAAA==.Lothwen:BAAALgADCgkJHwAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8HAAIIAAMJnhi0DgDlAAAIAAMJnhi0DgDlAAAuAAQKfyQAAggACAmQFJAsAJQBAAgACAmQFJAsAJQBAAAA.Luxinine:BAAALgAECgYJEQAAAA==.',
Ly='Lyon:BAAALgADCgMJBAAAAA==.Lyshai:BAAALgADCgUJCAABLgAECgUJDwAKAAAAAA==.',
Ma='Madhawi:BAAALgAECgUJCwAAAA==.Magamon:BAABLgAECn8eAAINAAcJbhfnQgCeAQANAAcJbhfnQgCeAQAAAA==.Mahndarb:BAAALgAECgMJBgABLgAECggJFgAIACoPAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAAALgAECgUJDwAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Margerdria:BAAALgAECgQJCAAAAA==.Maskelle:BAABLgAECn8XAAIjAAYJ6g2bDgDXAAAjAAYJ6g2bDgDXAAAAAA==.Mauugrim:BAABLgAECn8WAAIOAAYJIgfDcwD6AAAOAAYJIgfDcwD6AAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAAALgAECgUJDwAAAA==.',
Me='Mearadan:BAAALgAECgYJCQAAAA==.Meatsweats:BAAALgAECgYJCAAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDgAAAA==.Mekh:BAAALgAECgUJDwAAAA==.Mel:BAAALgAECgMJBAAAAA==.Melanara:BAABLgAECn8oAAINAAgJcwwuSwCHAQANAAgJcwwuSwCHAQAAAA==.Melstrom:BAAALgADCgkJHwAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgQJBQAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAAALgAECgYJDAAAAA==.Miyävii:BAABLgAECn8WAAIbAAgJ/hPVDgBLAQAbAAgJ/hPVDgBLAQAAAA==.',
Mj='Mjsage:BAABLgAECn8dAAIQAAcJth78HADuAQAQAAcJth78HADuAQAAAA==.',
Mm='Mmeow:BAAALgAECgEJAQABLgAECgcJDAAKAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAAALgAECgUJDwAAAA==.Moonflowers:BAACLgAFFH8VAAIJAAUJuht7CwCIAQAJAAUJuht7CwCIAQAuAAQKfygAAgkACAmNJNYDAC0DAAkACAmNJNYDAC0DAAAA.Mordsevoker:BAAALgAFFAEJAQABLgAFFAQJDAAOAL4RAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8VAAIIAAYJCAyfJAAlAQAIAAYJCAyfJAAlAQAAAA==.',
Mu='Murdrmitts:BAAALgAECgYJDwAAAA==.Mustikka:BAAALgAECgQJCwAAAA==.',
My='Myuriyanka:BAABLgAECn8VAAMUAAYJxBAiPABcAQAUAAYJxBAiPABcAQAVAAEJDgEYrAAaAAAAAA==.',
Na='Naahommii:BAABLgAECn8VAAIQAAcJZBfRNQB2AQAQAAcJZBfRNQB2AQAAAA==.Nachtpranke:BAAALgAECgYJDgAAAA==.Nadron:BAAALgAECgIJAgAAAA==.Nagualli:BAAALgADCgkJDwAAAA==.',
Ne='Negargra:BAABLgAECn8VAAMCAAYJPw43gwC/AAACAAYJPw43gwC/AAAkAAEJcgMjfAAkAAAAAA==.Nephadin:BAAALgADCgkJFgAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgMJAwAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAAALgAECgUJCQAAAA==.Nikooli:BAAALgAECgUJCwAAAA==.',
No='Noodledragon:BAAALgAECgYJBgAAAA==.Noopsie:BAAALgAECgQJCQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAYJGQAlAL0QAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMPAAgJxhpMCQBDAgAPAAcJLxxMCQBDAgAFAAcJsBw9EwCsAQAAAA==.',
Ny='Nyteweaver:BAAALgAECgUJDwAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8WAAMNAAkJUQMKigD+AAANAAkJOwMKigD+AAAdAAcJogE+EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCgYJDAAAAA==.Olympia:BAABLgAECn8aAAIbAAgJ1AyOEwANAQAbAAgJ1AyOEwANAQAAAA==.',
On='Ontai:BAAALgADCgkJFAAAAA==.',
Or='Oraclemega:BAAALgAECgYJDAAAAA==.',
Os='Oscarmikey:BAACLgAFFH8NAAMJAAQJ1AfdHADvAAAJAAQJ1AfdHADvAAAaAAEJhAHlKwA1AAAuAAQKfyIABAkACAlEG7IYAP8BAAkACAlEG7IYAP8BABoABAmICvFCAHIAACAAAQlIAoAsACYAAAAA.',
Ot='Ottoshot:BAAALgAECgUJDwAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
['Oö']='Oöps:BAAALgADCgMJAwAAAA==.',
Pa='Panamone:BAAALgAECgUJDgAAAA==.Pandeism:BAABLgAECn8VAAIfAAYJ3RLIDAA8AQAfAAYJ3RLIDAA8AQAAAA==.Patrin:BAABLgAECn8VAAINAAYJ8giIhgAFAQANAAYJ8giIhgAFAQAAAA==.',
Pe='Peanutbritle:BAABLgAECn8eAAIMAAcJmAZ7IgCxAAAMAAcJmAZ7IgCxAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJEQAAAA==.',
Ph='Phantdoom:BAAALgAECgYJCAAAAA==.',
Pi='Picdruid:BAAALgAECgMJBQABLgAECggJJAALAJ4gAA==.',
Pl='Plsdiddyno:BAAALgAECgIJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJAwAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Punchabaal:BAAALgAECgYJCgAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJCwAAAA==.Raharmin:BAABLgAECn8XAAIJAAcJVhnrMwDZAQAJAAcJVhnrMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgIJAgAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAQJDAANAIkiAA==.Reyrocko:BAAALgAECgEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAMJCQAFAFsdAA==.Rezshift:BAABLgAECn8UAAMaAAYJ3BrKPgA3AQAaAAYJ3BrKPgA3AQAJAAQJBRbpbwAFAQABLgAFFAMJCQAFAFsdAA==.Rezvoid:BAACLgAFFH8JAAMFAAMJWx2NDwAWAQAFAAMJWx2NDwAWAQAIAAIJgyFpEgC7AAAuAAQKfygAAgUACAmLIxMEAK0CAAUACAmLIxMEAK0CAAAA.',
Rh='Rhage:BAAALgAECgMJBAAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAAALgAECgcJEgAAAA==.Roxane:BAABLgAECn8YAAIaAAgJbQiCJQAQAQAaAAgJbQiCJQAQAQAAAA==.',
Ru='Runningelk:BAABLgAECn8hAAIhAAgJ0xJ6CgBzAQAhAAgJ0xJ6CgBzAQAAAA==.Runscapemain:BAABLgAECn8dAAILAAcJxxZWQwB7AQALAAcJxxZWQwB7AQAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJCgAZAJ4iAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAACLgAFFH8GAAIiAAUJFAWyCwABAQAiAAUJFAWyCwABAQAuAAQKfyYAAiIACAnAG2gDACMCACIACAnAG2gDACMCAAAA.Sandía:BAAALgAECgcJDgAAAA==.Sanitas:BAAALgAECgYJEQAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAKAAAAAA==.',
Se='Seeyen:BAACLgAFFH8MAAIQAAQJ8BJMFABLAQAQAAQJ8BJMFABLAQAuAAQKfyYAAhAACQmPHgYHAB8DABAACQmPHgYHAB8DAAAA.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8aAAImAAgJxAdkBwBDAQAmAAgJxAdkBwBDAQAAAA==.Seren:BAAALgAECgYJBgAAAA==.Serenityhate:BAAALgAECgUJCwAAAA==.',
Sh='Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgEJAQAAAA==.Shandrilyn:BAAALgAECgYJCgAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJuRSKDgBZAQAlAAkJuRSKDgBZAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sk='Skala:BAAALgAECgcJEAAAAA==.Skibbie:BAACLgAFFH8QAAMmAAQJsQqVAgArAQAmAAQJfQiVAgArAQAnAAQJywepGgAUAQAuAAQKfxgAAycACQk8FloQAHMCACcACQk8FloQAHMCACYABQnOBocsALcAAAAA.Skibbward:BAABLgAECn8yAAQhAAgJTiS4AQAyAwAhAAgJTiS4AQAyAwAaAAUJxQ9aVADUAAAJAAYJ6QrmggDSAAABLgAFFAQJEAAmALEKAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgUJBgAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIaAAcJPR0RHQAYAgAaAAcJPR0RHQAYAgAAAA==.',
So='Solteria:BAAALgAECgYJEwAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgAECgUJCQAAAA==.Sorvina:BAABLgAECn8fAAICAAkJ/AqlKgC6AQACAAkJ/AqlKgC6AQAAAA==.Soulflame:BAABLgAECn8gAAINAAgJTglhWgBgAQANAAgJTglhWgBgAQAAAA==.Soulshifter:BAAALgAECgYJEQAAAA==.Soultrader:BAAALgADCgcJBgABLgAECgQJCwAKAAAAAA==.',
Sp='Spooñ:BAAALgADCgcJBwAAAA==.Spottedcoat:BAABLgAECn8eAAIJAAcJwgOoWwCuAAAJAAcJwgOoWwCuAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Stregnor:BAABLgAECn8iAAIQAAgJHBHMKQCqAQAQAAgJHBHMKQCqAQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJCgAZAJ4iAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn8jAAMcAAcJuhN5FwBrAQAcAAcJuhN5FwBrAQASAAQJ7QqGZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKkEwBHAgAnAAkJfhGkEwBHAgAmAAYJoRLxHwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECggJGAAnAFUVAA==.Tachie:BAABLgAECn8YAAMnAAgJVRX0GAB4AQAnAAgJihP0GAB4AQAmAAUJDBStJQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAUJDgACAHYlAA==.Taele:BAABLgAECn8bAAMNAAgJWBqKOADAAQANAAcJUBmKOADAAQAdAAUJlhq2CABnAQAAAA==.Taiche:BAABLgAECn8wAAIaAAgJHw6qGAB0AQAaAAgJHw6qGAB0AQAAAA==.Tamalpais:BAAALgAECgUJBwAAAA==.Tamarind:BAAALgADCgkJCQABLgAECggJGgAfAM8bAA==.Tanya:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAAALgAECgUJDwAAAA==.',
Th='Therin:BAABLgAECn8jAAITAAgJoRL7DADWAQATAAgJoRL7DADWAQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.',
To='Tongshi:BAAALgADCgYJDAAAAA==.Toofast:BAABLgAECn8UAAIVAAYJsyNkEgAlAgAVAAYJsyNkEgAlAgAAAA==.Toofurrious:BAAALgADCgkJHwAAAA==.Topswimmer:BAAALgAECgQJBQAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgQJBQAAAA==.',
Tr='Trifus:BAAALgAECgYJCgAAAA==.Trydora:BAAALgAECgUJCwAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQAAAA==.',
Tu='Tulao:BAABLgAECn8VAAINAAYJAwxhlgDmAAANAAYJAwxhlgDmAAAAAA==.',
Tw='Twan:BAAALgAECgYJBgAAAA==.',
Ty='Tyrionel:BAAALgAECgUJCQAAAA==.',
Tz='Tzitzimitl:BAAALgADCgkJCQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIeAAQJdhApEgAJAQAeAAQJdhApEgAJAQAAAA==.',
Ut='Utheli:BAABLgAECn8cAAILAAgJ/RrOHgAPAgALAAgJ/RrOHgAPAgAAAA==.',
Va='Vaevictis:BAAALgADCgMJAwABLgAECgYJFQAFACcWAA==.Vaildora:BAAALgAECgEJAQABLgAECggJGAAnAFUVAA==.Valdra:BAABLgAECn8jAAIEAAgJShDUDgB2AQAEAAgJShDUDgB2AQAAAA==.',
Vi='Viralprepped:BAAALgAECgMJBAAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8ZAAIYAAkJrg7HJACtAQAYAAkJrg7HJACtAQAAAA==.',
Vn='Vnasty:BAACLgAFFH8KAAILAAQJeg41HAA8AQALAAQJeg41HAA8AQAuAAQKfyUAAgsACQnPHyUKAEADAAsACQnPHyUKAEADAAAA.',
Vr='Vrale:BAAALgAECgEJAgAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wilken:BAAALgAECggJEwAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8eAAILAAcJUhqdMAC6AQALAAcJUhqdMAC6AQAAAA==.',
Ws='Wspr:BAAALgAECgIJBAAAAA==.',
Xa='Xaartahli:BAAALgAECgQJBwAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgIJAgAAAA==.',
Ya='Yanut:BAAALgAECgQJCQAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJCwAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAAALgAECgYJDAAAAA==.Zalanto:BAAALgADCgYJBgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn8fAAIQAAgJ+g5sMgCEAQAQAAgJ+g5sMgCEAQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8eAAMVAAcJ1BMMJQCRAQAVAAcJ1BMMJQCRAQAfAAEJtQEAMAAjAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAAALgAECgUJEQAAAA==.',
Zr='Zriana:BAAALgADCgkJFwAAAA==.',
Zs='Zsarilya:BAABLgAECn8XAAIIAAYJZgIXMwC5AAAIAAYJZgIXMwC5AAAAAA==.',
Zu='Zurgen:BAABLgAECn8jAAICAAgJhh7rDgBxAgACAAgJhh7rDgBxAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8jAAIJAAcJpAliQAASAQAJAAcJpAliQAASAQABLgAFFAMJBwAIAJ4YAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
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

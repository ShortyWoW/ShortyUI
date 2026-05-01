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

local lookup = {'Paladin-Holy','Warrior-Protection','Priest-Shadow','Warlock-Affliction','Mage-Fire','Priest-Holy','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Rogue-Assassination','Monk-Brewmaster','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Warlock-Demonology','Paladin-Protection','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarchon:BAABLgAECn8XAAIBAAYJVyMUCABZAgABAAYJVyMUCABZAgAAAA==.',
Ad='Aduin:BAAALgADCgkJGAAAAA==.',
Ae='Aedarelyn:BAAALgAECgQJBwAAAA==.Aellet:BAAALgAECgYJEQAAAA==.Aellita:BAAALgAECgEJAQAAAA==.',
Ak='Akky:BAABLgAECn8XAAICAAcJxR6eBQAAAgACAAcJxR6eBQAAAgAAAA==.Aksafiya:BAABLgAECn8pAAIDAAYJ6xHKGAA4AQADAAYJ6xHKGAA4AQAAAA==.',
Al='Alal:BAAALgADCgcJBwAAAA==.Alandras:BAAALgAECgYJEQAAAA==.Alaras:BAACLgAFFH8KAAIDAAQJUQ0wCAA+AQADAAQJUQ0wCAA+AQAuAAQKfxcAAgMACQnQFQ0aAA8CAAMACQnQFQ0aAA8CAAAA.Allistair:BAABLgAECn8aAAIEAAcJkha5AgClAQAEAAcJkha5AgClAQAAAA==.Allrianne:BAAALgAECgEJAQAAAA==.Allyriae:BAABLgAECn8UAAIFAAcJswhlAwAhAQAFAAcJswhlAwAhAQAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8UAAIGAAgJCA7kMQB5AQAGAAgJCA7kMQB5AQAAAA==.',
Am='Ambilena:BAAALgAECgYJCgAAAA==.',
An='Andoros:BAABLgAECn8iAAIHAAcJbx+sFQDWAQAHAAcJbx+sFQDWAQAAAA==.Angiliana:BAAALgAECgIJBAAAAA==.Angvall:BAAALgAECgYJBgABLgAECgEJAQAIAAAAAA==.Anzurath:BAABLgAECn8XAAIJAAYJfxOGhQBvAQAJAAYJfxOGhQBvAQAAAA==.',
Ap='Applebow:BAAALgAECgYJEQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgADCgMJBQAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgMJAwAAAA==.Arylin:BAABLgAECn8bAAIKAAcJNyJREABaAgAKAAcJNyJREABaAgAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEALgAECgQJBwAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAIAAAAAA==.Asnabel:BAAALgAECgUJCwAAAA==.Aspirate:BAAALgADCgcJCwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCQALAEMlAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgADCgcJEQAAAA==.Ayden:BAAALgAECgIJAwAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAIAAAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgADCgIJAgAAAA==.',
Bl='Blee:BAAALgAECgYJEgAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAAALgAECgYJEQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAAALgAECgYJEgAAAA==.Botsugo:BAAALgAECgIJAgAAAA==.',
Br='Braelia:BAAALgAECgYJEAAAAA==.Brood:BAABLgAECn8dAAILAAgJQRD4KgCPAQALAAgJQRD4KgCPAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAAALgAECgMJBgAAAA==.',
Ca='Cailaranel:BAABLgAECn8YAAIMAAYJmQmBCAARAQAMAAYJmQmBCAARAQAAAA==.Calaul:BAAALgAECgYJDwAAAA==.Calenbraga:BAAALgAECgQJCAAAAA==.Calisim:BAAALgAECgIJBAAAAA==.Callidae:BAABLgAECn8dAAIGAAkJaAiQGwAqAQAGAAkJaAiQGwAqAQAAAA==.Calmnbald:BAABLgAECn8WAAINAAcJwhQyKQDIAAANAAcJwhQyKQDIAAAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8WAAIOAAYJ5Q/mFQBqAQAOAAYJ5Q/mFQBqAQAAAA==.Cataryn:BAAALgAECgYJEgAAAA==.Catt:BAABLgAECn8iAAIBAAcJhxK3FQClAQABAAcJhxK3FQClAQAAAA==.',
Ce='Cellebur:BAAALgAECgQJBwAAAA==.Ceta:BAABLgAECn8bAAIGAAcJbhhVEwB8AQAGAAcJbhhVEwB8AQAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAABLgAECn8dAAMPAAcJqRmxDQDDAQAPAAcJqRmxDQDDAQAQAAIJLgSZlABKAAAAAA==.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAAALgAECgYJEgAAAA==.Cizean:BAAALgAECgQJBwAAAA==.',
Co='Cometopapa:BAABLgAECn8XAAMRAAcJWw64CABYAQARAAYJCQ+4CABYAQALAAcJpwhLSwAdAQAAAA==.',
Cr='Craivan:BAAALgADCgIJAgAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8aAAIKAAgJMxlzHQD7AQAKAAgJMxlzHQD7AQAAAA==.Crowe:BAAALgAECgMJBAABLgAECgUJBQAIAAAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAAALgAECgQJBQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgUJBQAAAA==.Damia:BAAALgAECgYJEQAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8XAAISAAYJTyQ5BQDjAQASAAYJTyQ5BQDjAQAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAQABLgAECgYJFwASAE8kAA==.Delvarrieth:BAAALgAECgQJBwAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAAALgAECgYJEQAAAA==.Dercuur:BAAALgAECgUJCgAAAA==.Devoursol:BAABLgAECn8XAAMTAAcJvwqyNwAEAQATAAcJmAmyNwAEAQAUAAIJrg4yXABvAAAAAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgADCgkJFAAAAA==.Drainmee:BAAALgAECgMJBgAAAA==.Draknol:BAAALgADCgkJDwAAAA==.Dregoth:BAABLgAECn8XAAILAAcJ9QerRAAwAQALAAcJ9QerRAAwAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMHAAkJ3x5nEAC0AgAHAAkJ3x5nEAC0AgAVAAEJxQk3SwAqAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elynth:BAABLgAECn8WAAIWAAYJERpXKQCIAQAWAAYJERpXKQCIAQAAAA==.',
En='Endlessyueh:BAAALgADCgYJDQAAAA==.',
Er='Eridormi:BAAALgAECgYJBgABLgAECgYJEQAIAAAAAA==.',
Ev='Evilis:BAAALgADCgMJBAAAAA==.Evolnasty:BAAALgADCgcJCQABLgAFFAMJBgAJAPoNAA==.',
Fa='Face:BAAALgAECgYJBgAAAA==.Faethian:BAACLgAFFH8GAAIXAAMJ3xt3AgD/AAAXAAMJ3xt3AgD/AAAuAAQKfyMAAhcACAmEJKcAAOUCABcACAmEJKcAAOUCAAAA.Falunia:BAABLgAECn8VAAIKAAYJ9AX0dADtAAAKAAYJ9AX0dADtAAAAAA==.Fangren:BAAALgAECgMJBgAAAA==.Fariah:BAAALgAECgIJBAAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAAALgAECgYJDAAAAA==.',
Fe='Felscythe:BAAALgAECgQJBgAAAA==.Felynn:BAABLgAECn8UAAIBAAcJ2hXdGQB+AQABAAcJ2hXdGQB+AQAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgMJAwAAAA==.',
Fi='Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAAALgAECgQJBwAAAA==.',
Fl='Flaeli:BAAALgAECgYJEQAAAA==.Flemish:BAAALgADCgkJHwAAAA==.Flextame:BAAALgAECgQJBQAAAA==.Flipalicious:BAABLgAECn8lAAIQAAgJehcNDgAOAgAQAAgJehcNDgAOAgAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAAALgAECgYJDwAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAAALgAECgYJDwAAAA==.Gazo:BAAALgADCggJGQAAAA==.',
Ge='Gemboss:BAABLgAECn8eAAMJAAYJzB3CMwBzAQAJAAYJzB3CMwBzAQABAAQJLRK6YwDtAAAAAA==.Gerbo:BAABLgAECn8fAAMKAAgJbxBTRQBfAQAKAAgJbxBTRQBfAQAYAAMJrwXBFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8WAAIZAAYJVwcURQACAQAZAAYJVwcURQACAQAAAA==.Ginodh:BAAALgAECgYJDwABLgAECgcJCgAIAAAAAA==.Ginomage:BAAALgAECgcJCgAAAA==.Ginomonk:BAAALgADCgcJBwABLgAECgcJCgAIAAAAAA==.Ginopally:BAAALgAECgQJCQABLgAECgcJCgAIAAAAAA==.Girth:BAAALgADCgEJAQAAAA==.Gizelli:BAAALgADCgMJAwAAAA==.',
Go='Gordonn:BAAALgADCgcJCwAAAA==.',
Gr='Grubetsell:BAAALgADCgUJCgABLgAECgYJGwAaAJIjAA==.Grubetsella:BAABLgAECn8bAAIaAAYJkiP2CQAOAgAaAAYJkiP2CQAOAgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAITAAYJXBt/KABFAQATAAYJXBt/KABFAQAAAA==.Gumpers:BAAALgAECgUJEAAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAAALgADCggJEwAAAA==.',
Ha='Hanoumatoi:BAAALgAECgMJAwAAAA==.Haralambos:BAAALgAECgQJBwAAAA==.Haralogain:BAAALgADCgMJAwABLgAECgQJBwAIAAAAAA==.Harithon:BAABLgAECn8UAAIbAAUJSh0qEQCkAQAbAAUJSh0qEQCkAQAAAA==.Havvöc:BAABLgAECn8YAAIBAAcJmh6tBgB3AgABAAcJmh6tBgB3AgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAAALgAECgYJCQAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAAALgAECgIJBAAAAA==.Heyokagi:BAABLgAECn8XAAMcAAcJGBxeBADpAQAcAAcJGBxeBADpAQAdAAIJ1BS2JgBnAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgYJEQAIAAAAAA==.Hordkilla:BAABLgAECn8VAAIJAAcJRQTqZADoAAAJAAcJRQTqZADoAAAAAA==.Hownowbrncw:BAAALgAECgYJEgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn8XAAITAAcJNBqGEwDOAQATAAcJNBqGEwDOAQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgQJBgAAAA==.',
Im='Imathdal:BAABLgAECn8XAAIeAAcJOQyZCQA7AQAeAAcJOQyZCQA7AQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAIAAAAAA==.Insoniacyun:BAAALgADCggJFwAAAA==.',
Is='Iselian:BAAALgAECgcJEwAAAQ==.Ishanu:BAAALgAECgcJDAAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJCQABLgADCggJDgAIAAAAAA==.Jax:BAABLgAECn8hAAIKAAgJPiMQEwA1AwAKAAgJPiMQEwA1AwAAAA==.',
Jb='Jblockiv:BAAALgADCgUJBQAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn8WAAMQAAYJthGSIwBMAQAQAAYJthGSIwBMAQAPAAMJWQaocgB3AAAAAA==.',
Je='Jeb:BAAALgAECgMJAwAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn8bAAIYAAcJVQslAwBkAQAYAAcJVQslAwBkAQAAAA==.Jetfires:BAABLgAECn8fAAIfAAgJkxbrFQDiAQAfAAgJkxbrFQDiAQAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAAALgAECgMJBgAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jozhua:BAAALgADCgkJIwAAAA==.',
Ka='Kaedren:BAAALgADCgcJCgAAAA==.Kaelaya:BAABLgAECn8UAAIeAAYJmgaLDgDgAAAeAAYJmgaLDgDgAAAAAA==.Kaelorien:BAABLgAECn8bAAIaAAcJ+wx5HwAEAQAaAAcJ+wx5HwAEAQAAAA==.Kaetta:BAAALgAECgYJDgAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgMJAwAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kaldevayn:BAAALgADCgkJHwAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgIJAgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAAALgAECgkJEQAAAA==.Kardanis:BAABLgAECn8XAAIQAAYJjyZ4BQCcAgAQAAYJjyZ4BQCcAgAAAA==.Kashe:BAAALgAECgQJBQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8XAAIQAAYJjxShLAATAQAQAAYJjxShLAATAQAAAA==.Kaydencia:BAAALgAECgYJEQAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgMJAwAAAA==.Kazureshal:BAAALgADCgkJBwAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.',
Ki='Ki:BAAALgAECgMJAwAAAA==.Kiddow:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kiri:BAAALgADCgkJEAAAAA==.Kitamii:BAABLgAECn8UAAIcAAYJchbFEQCQAQAcAAYJchbFEQCQAQAAAA==.Kivrin:BAAALgAECgUJCgAAAA==.',
Kr='Kringlë:BAABLgAECn8WAAIfAAgJnR4GCAB3AgAfAAgJnR4GCAB3AgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.',
Ky='Kymma:BAABLgAECn8UAAIJAAYJ4gs1WQAFAQAJAAYJ4gs1WQAFAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAAALgAECgYJDQAAAA==.Laitue:BAAALgAECgQJBwAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAgAAAA==.Lazengann:BAABLgAECn8VAAMTAAYJKhfjPQDuAAATAAYJmBbjPQDuAAAUAAEJvxbmagA7AAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Legevia:BAAALgAECgMJBAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn8aAAIJAAcJUg3yOwBWAQAJAAcJUg3yOwBWAQAAAA==.Letifer:BAAALgADCgIJAgAAAA==.Leucetios:BAAALgADCgcJCAAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAAALgAECgcJCwAAAA==.Lightbeard:BAAALgAECgQJCAAAAA==.Lightdawns:BAAALgAECgQJBAAAAA==.Lightforge:BAAALgAECgYJEwAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgADCgcJCwAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgADCgcJCwAAAA==.Lothwen:BAAALgADCgkJHwAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAEBLgAECn8gAAIGAAgJ+xONLACUAQAGAAgJ+xONLACUAQAAAA==.Luxinine:BAAALgAECgYJDwAAAA==.',
Ly='Lyon:BAAALgADCgIJBAAAAA==.Lyshai:BAAALgADCgUJCAABLgAECgQJBwAIAAAAAA==.',
Ma='Madhawi:BAAALgAECgQJBgAAAA==.Magamon:BAABLgAECn8XAAIKAAYJQhewVQA0AQAKAAYJQhewVQA0AQAAAA==.Mahndarb:BAAALgAECgMJAwABLgAECggJFAAGAAgOAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAAALgAECgQJBwAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Margerdria:BAAALgAECgMJBAAAAA==.Maskelle:BAAALgAECgYJEQAAAA==.Mauugrim:BAAALgAECgYJEAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAAALgAECgQJBwAAAA==.',
Me='Mearadan:BAAALgAECgYJCQAAAA==.Meatsweats:BAAALgAECgIJAgAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgUJCgAAAA==.Mekh:BAAALgAECgQJBwAAAA==.Mel:BAAALgAECgEJAQAAAA==.Melanara:BAABLgAECn8aAAIKAAcJNg2hSwBMAQAKAAcJNg2hSwBMAQAAAA==.Melstrom:BAAALgADCgkJHwAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgMJAwAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAAALgAECgUJBgAAAA==.Miyävii:BAABLgAECn8WAAIXAAgJ/hP3CgBTAQAXAAgJ/hP3CgBTAQAAAA==.',
Mj='Mjsage:BAABLgAECn8WAAIfAAYJDB4pLQD+AQAfAAYJDB4pLQD+AQAAAA==.',
Mm='Mmeow:BAAALgAECgEJAQABLgAECgcJCwAIAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAAALgAECgQJBwAAAA==.Moonflowers:BAACLgAFFH8QAAIHAAQJkCDGCwBJAQAHAAQJkCDGCwBJAQAuAAQKfygAAgcACAmNJDgCADcDAAcACAmNJDgCADcDAAAA.Mordsevoker:BAAALgAFFAEJAQABLgAFFAQJCgALAFgQAA==.Mousekee:BAAALgAECgYJDwAAAA==.',
Mu='Murdrmitts:BAAALgAECgYJDwAAAA==.Mustikka:BAAALgAECgQJBwAAAA==.',
My='Myuriyanka:BAABLgAECn8UAAMPAAYJxBAiPABcAQAPAAYJxBAiPABcAQAQAAEJDgEbrAAaAAAAAA==.',
Na='Naahommii:BAAALgAECgYJDgAAAA==.Nachtpranke:BAAALgAECgYJDgAAAA==.Nadron:BAAALgAECgEJAQAAAA==.Nagualli:BAAALgADCgkJDwAAAA==.Naturecalls:BAAALgAECgQJCQAAAA==.',
Ne='Negargra:BAABLgAECn8UAAMWAAYJPw7TaQC6AAAWAAYJPw7TaQC6AAAgAAEJcgMhfAAkAAAAAA==.Nephadin:BAAALgADCgkJFgAAAA==.Nephilum:BAAALgAECgQJBAAAAA==.',
Ni='Nidarian:BAAALgAECgMJAwAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAAALgAECgQJBQAAAA==.Nikooli:BAAALgAECgMJBgAAAA==.',
No='Noodledragon:BAAALgAECgYJBgAAAA==.Noopsie:BAAALgAECgMJBQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAECgMJBgAIAAAAAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8VAAMhAAcJ5BvRCAAIAgAhAAYJux3RCAAIAgADAAcJIRiyJACyAQAAAA==.',
Ny='Nyteweaver:BAAALgAECgQJBwAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8WAAMKAAkJUAN/bAABAQAKAAkJOwN/bAABAQAYAAcJogFBEgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgIJAgAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCgYJDAAAAA==.Olympia:BAAALgAECgUJEgAAAA==.',
On='Ontai:BAAALgADCgkJFAAAAA==.',
Or='Oraclemega:BAAALgAECgYJBgAAAA==.',
Os='Oscarmikey:BAACLgAFFH8JAAIHAAMJjgjqHAC4AAAHAAMJjgjqHAC4AAAuAAQKfx4ABAcACAn+Go41ANIBAAcACAn+Go41ANIBABUAAwmXCNBBAEAAABwAAQlIAoohACkAAAAA.',
Ot='Ottoshot:BAAALgAECgQJBwAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Pa='Panamone:BAAALgAECgQJBwAAAA==.Pandeism:BAAALgAECgYJCwAAAA==.Patrin:BAAALgAECgYJDwAAAA==.',
Pe='Peanutbritle:BAABLgAECn8XAAISAAYJsQZTLQDUAAASAAYJsQZTLQDUAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJDQAAAA==.',
Ph='Phantdoom:BAAALgAECgIJAgAAAA==.',
Pi='Picdruid:BAAALgAECgMJBAABLgAECggJJAAJAJ4gAA==.',
Pl='Plsdiddyno:BAAALgAECgIJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJAwAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Punchabaal:BAAALgAECgQJCAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgQJBQAAAA==.Raharmin:BAAALgAECgYJEAAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgADCgkJBwAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgIJAgAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAQJCAAKAH4hAA==.Reyrocko:BAAALgADCgYJDgAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAMJBgADABcQAA==.Rezshift:BAABLgAECn8UAAMVAAYJ3BrGPgA3AQAVAAYJ3BrGPgA3AQAHAAQJBRbwbwAFAQABLgAFFAMJBgADABcQAA==.Rezvoid:BAACLgAFFH8GAAMDAAMJFxA0DADuAAADAAMJFxA0DADuAAAGAAIJgyGmDADEAAAuAAQKfyYAAgMACAlBI38CAKkCAAMACAlBI38CAKkCAAAA.',
Rh='Rhage:BAAALgAECgEJAQAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAAALgAECgcJEAAAAA==.Roxane:BAABLgAECn8WAAIVAAYJhQkZKQDAAAAVAAYJhQkZKQDAAAAAAA==.',
Ru='Runningelk:BAABLgAECn8ZAAIdAAcJ7BIACQBHAQAdAAcJ7BIACQBHAQAAAA==.Runscapemain:BAABLgAECn8XAAIJAAYJyBdSQABJAQAJAAYJyBdSQABJAQAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJBgAUAC0iAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAACLgAFFH8FAAIeAAQJDAWDBwARAQAeAAQJDAWDBwARAQAuAAQKfxoAAh4ACAm1ERgsAMoBAB4ACAm1ERgsAMoBAAAA.Sandía:BAAALgAECgYJCgAAAA==.Sanitas:BAAALgAECgYJEAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAIAAAAAA==.',
Se='Seeyen:BAACLgAFFH8IAAIfAAQJGQsIEAA7AQAfAAQJGQsIEAA7AQAuAAQKfyQAAh8ACQmPHggHAB8DAB8ACQmPHggHAB8DAAAA.Selûne:BAAALgADCgcJDAAAAA==.Sentrath:BAAALgADCgkJHAAAAA==.Seraphi:BAAALgAECgYJEgAAAA==.Serenityhate:BAAALgAECgMJBgAAAA==.',
Sh='Shadowhunder:BAAALgADCgMJAwAAAA==.Shandrilyn:BAAALgAECgQJBAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8eAAIiAAkJuRTqCgBkAQAiAAkJuRTqCgBkAQAAAA==.',
Si='Sinthoras:BAAALgADCgUJBgAAAA==.',
Sk='Skala:BAAALgAECgYJCQAAAA==.Skibbie:BAACLgAFFH8MAAMjAAQJ1Qg7AwCyAAAkAAQJyAdWEgAbAQAjAAMJfgM7AwCyAAAuAAQKfxgAAyQACQk8Fl4QAHMCACQACQk8Fl4QAHMCACMABQnNBoosALcAAAAA.Skibbward:BAABLgAECn8nAAQdAAgJxCO5AQAyAwAdAAgJxCO5AQAyAwAVAAUJxQ9XVADUAAAHAAUJTgzkggDSAAABLgAFFAQJDAAjANUIAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgUJBQAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIVAAcJPR0MHQAYAgAVAAcJPR0MHQAYAgAAAA==.',
So='Solteria:BAAALgAECgYJDgAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgAECgQJBAAAAA==.Sorvina:BAABLgAECn8WAAIWAAgJaQm+NwBNAQAWAAgJaQm+NwBNAQAAAA==.Soulflame:BAABLgAECn8YAAIKAAcJRgkDVgAzAQAKAAcJRgkDVgAzAQAAAA==.Soulshifter:BAAALgAECgUJCwAAAA==.Soultrader:BAAALgADCgcJBgABLgAECgQJBwAIAAAAAA==.',
Sp='Spooñ:BAAALgADCgcJBwAAAA==.Spottedcoat:BAABLgAECn8XAAIHAAYJIARfTQCcAAAHAAYJIARfTQCcAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Stregnor:BAABLgAECn8bAAIfAAcJsg8pJwB7AQAfAAcJsg8pJwB7AQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJBgAUAC0iAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn8cAAMZAAcJfRNSEQBsAQAZAAcJfRNSEQBsAQANAAQJ7QqEZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMkAAkJDxKrEwBHAgAkAAkJfhGrEwBHAgAjAAYJoRL4HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgYJFQAkAOwYAA==.Tachie:BAABLgAECn8VAAMkAAYJ7Bg7JwCDAQAkAAYJahY7JwCDAQAjAAUJDBSyJQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAMJCQAWAMEkAA==.Taele:BAABLgAECn8VAAMYAAcJ3Bm1CABnAQAYAAUJlhq1CABnAQAKAAUJHhkZWQAsAQAAAA==.Taiche:BAABLgAECn8oAAIVAAgJPQw5FABiAQAVAAgJPQw5FABiAQAAAA==.Tamalpais:BAAALgAECgIJAgAAAA==.Tamarind:BAAALgADCgkJCQABLgAECgUJFAAbAEodAA==.Tanya:BAAALgADCgEJAQAAAA==.Tareyn:BAAALgADCgkJEwAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAAALgAECgQJBwAAAA==.',
Th='Therin:BAABLgAECn8bAAIOAAcJ7RAvDQCLAQAOAAcJ7RAvDQCLAQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.',
To='Tongshi:BAAALgADCgUJBQAAAA==.Toofast:BAAALgAECgYJDgAAAA==.Toofurrious:BAAALgADCgkJHwAAAA==.Topswimmer:BAAALgAECgEJAQAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgMJAwAAAA==.',
Tr='Trifus:BAAALgAECgQJBAAAAA==.Trydora:BAAALgAECgIJBAAAAA==.',
Ts='Tsugumi:BAAALgADCgkJGwAAAA==.',
Tu='Tulao:BAAALgAECgYJEQAAAA==.',
Tw='Twan:BAAALgAECgEJAQAAAA==.',
Ty='Tyrionel:BAAALgAECgUJCQAAAA==.',
Tz='Tzitzimitl:BAAALgADCgkJCQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIaAAQJdhA7DAAXAQAaAAQJdhA7DAAXAQAAAA==.',
Ut='Utheli:BAABLgAECn8aAAIJAAgJWRbPHQDWAQAJAAgJWRbPHQDWAQAAAA==.',
Va='Vaevictis:BAAALgADCgEJAQABLgAECgYJDwAIAAAAAA==.Vaildora:BAAALgAECgEJAQABLgAECgYJFQAkAOwYAA==.Valdra:BAABLgAECn8bAAICAAcJFhBLDQBLAQACAAcJFhBLDQBLAQAAAA==.',
Vi='Viralprepped:BAAALgAECgEJAQAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8TAAITAAgJTgzGJwBJAQATAAgJTgzGJwBJAQAAAA==.',
Vn='Vnasty:BAACLgAFFH8GAAIJAAMJ+g3SIADzAAAJAAMJ+g3SIADzAAAuAAQKfyQAAgkACQlLHycKAEADAAkACQlLHycKAEADAAAA.',
Vr='Vrale:BAAALgAECgEJAQAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgADCgEJAQAAAA==.',
Wi='Wilken:BAAALgAECgcJDQAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8XAAIJAAYJshmkPABUAQAJAAYJshmkPABUAQAAAA==.',
Ws='Wspr:BAAALgAECgIJAgAAAA==.',
Xa='Xaartahli:BAAALgAECgMJAwAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgEJAQAAAA==.',
Ya='Yanut:BAAALgAECgMJBQAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgUJBQAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAAALgAECgUJCwAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn8XAAIfAAYJrxCITQCAAQAfAAYJrxCITQCAAQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8XAAMQAAcJ/xG0GgCOAQAQAAcJ/xG0GgCOAQAbAAEJtQH+LwAjAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAAALgAECgUJDAAAAA==.',
Zr='Zriana:BAAALgADCgkJEwAAAA==.',
Zs='Zsarilya:BAAALgAECgYJEQAAAA==.',
Zu='Zurgen:BAABLgAECn8bAAIWAAcJzxyQFAABAgAWAAcJzxyQFAABAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8bAAIHAAcJYwl1OwDlAAAHAAcJYwl1OwDlAAABLgAECggJIAAGAPsTAA==.',
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

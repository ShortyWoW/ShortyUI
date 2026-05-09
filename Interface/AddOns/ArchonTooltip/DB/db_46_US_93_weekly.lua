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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Protection','Shaman-Elemental','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Warlock-Demonology','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Absolon:BAAALgAECgYJBwAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8dAAMBAAgJ/QnoIABBAQABAAgJ/QnoIABBAQACAAEJXgAmbAAXAAAAAA==.Aerir:BAACLgAFFH8IAAIDAAMJ6QzxTgDnAAADAAMJ6QzxTgDnAAAuAAQKfycAAgMACAn0G9pbACYCAAMACAn0G9pbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECgUJCgAAAA==.',
Al='Alandris:BAABLgAECn8UAAIEAAcJqgMsPQDNAAAEAAcJqgMsPQDNAAAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAABLgAECn8WAAIFAAgJCSVZBwD3AgAFAAgJCSVZBwD3AgAAAA==.Alleriya:BAABLgAECn8ZAAIGAAYJOwu3VQAOAQAGAAYJOwu3VQAOAQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJCQAHAPgdAA==.',
Am='Amarawyn:BAAALgAECgYJDQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8bAAMIAAgJdRkqCgCkAQAEAAcJqBfWOADDAQAIAAcJnRYqCgCkAQAAAA==.',
An='Andriela:BAAALgAECgYJDQAAAA==.',
Ap='Apexy:BAAALgAECgUJCgAAAA==.',
Ar='Arashikaze:BAAALgAECgYJDgAAAA==.',
Au='Augidget:BAABLgAECn8cAAICAAgJDBUuDwDaAQACAAgJDBUuDwDaAQAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAJAAAAAA==.Avilen:BAAALgAECgcJDgAAAA==.Aviris:BAAALgADCgYJCwABLgAECgcJCAAJAAAAAA==.',
Ay='Ayuzi:BAAALgADCgEJAQAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAAALgAECgYJBgAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8cAAIFAAgJBCSrAgAkAwAFAAgJBCSrAgAkAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Bendyy:BAABLgAECn8bAAIDAAgJdx2oHgAyAgADAAgJdx2oHgAyAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8XAAIKAAYJuxTiIAAwAQAKAAYJuxTiIAAwAQAAAA==.Bitxi:BAAALgAECgUJCgAAAA==.',
Bo='Boldbane:BAAALgAECgQJBQAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8XAAILAAYJjxBrDQAwAQALAAYJjxBrDQAwAQAAAA==.',
Bu='Bubbaman:BAAALgAECgUJCQAAAA==.Burda:BAABLgAECn8aAAIMAAkJcxUVBwA7AgAMAAkJcxUVBwA7AgAAAA==.',
Ca='Caenae:BAAALgAECgMJBAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJCQAHAPgdAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJCgAAAA==.',
Co='Coletrain:BAAALgAECgUJCgAAAA==.Corri:BAAALgAECgMJBwAAAA==.Corriandis:BAAALgAECgMJAwAAAA==.',
Cr='Credon:BAAALgAECgUJCgAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAAALgAECgYJDQAAAA==.Dirtytaters:BAAALgAECgUJCgAAAA==.Divastating:BAAALgAECgEJAQABLgAECgIJBQAJAAAAAA==.',
Do='Doró:BAAALgADCgQJBgAAAA==.',
Dt='Dtothed:BAAALgADCgQJCwAAAA==.',
Dw='Dwarfred:BAAALgAECgYJCgAAAA==.Dwimor:BAABLgAECn8ZAAIGAAYJBBDMTwAeAQAGAAYJBBDMTwAeAQAAAA==.',
['Dô']='Dôro:BAAALgADCggJDQABLgAECgkJGwANALwdAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgMJBQAAAA==.Elmö:BAAALgAECgUJBQAAAA==.Elrarebriel:BAAALgADCggJDAAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgMJAwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzlyn:BAACLgAFFH8IAAMOAAMJ5hnaSgD5AAAOAAMJnBnaSgD5AAAPAAEJXyPVGgBmAAAuAAQKfygAAg4ACAnsIrUlAOoBAA4ACAnsIrUlAOoBAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgADCgcJDgAAAA==.',
Fu='Furr:BAAALgAECgEJAQABLgAFFAUJFQADAIAZAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgMJBAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJGQABLgAECgQJEAAJAAAAAA==.Grewsöm:BAABLgAECn8XAAMOAAgJvyMuDwCHAgAOAAgJvyMuDwCHAgAPAAUJqB5AEQBdAQABLgAFFAQJCQAHAPgdAA==.Grotusque:BAABLgAECn8kAAIQAAgJrxPcCQCBAQAQAAgJrxPcCQCBAQAAAA==.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIRAAYJ8xCGTAATAQARAAYJ8xCGTAATAQAAAA==.Haiiro:BAABLgAECn8cAAISAAgJeRXwEAC/AQASAAgJeRXwEAC/AQAAAA==.Hardim:BAAALgAECgYJDAAAAA==.Hargen:BAAALgAECgIJAgAAAA==.Harknesse:BAAALgAECgUJCgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8ZAAITAAYJwCANBgCiAQATAAYJwCANBgCiAQAAAA==.Hewhospins:BAABLgAECn8hAAISAAcJVRSVGAByAQASAAcJVRSVGAByAQAAAA==.',
Hy='Hydraulicman:BAAALgADCggJGwAAAA==.Hyzer:BAAALgADCgcJBwABLgAECggJDAAJAAAAAA==.',
Ig='Igknight:BAAALgADCgUJBQAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgYJBgAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8VAAIUAAYJYwZcLQDSAAAUAAYJYwZcLQDSAAAAAA==.',
Jo='Jolage:BAABLgAECn8UAAIDAAYJOg+7awA5AQADAAYJOg+7awA5AQAAAA==.Jolreal:BAABLgAECn8yAAMMAAgJXCCVCAAdAgAVAAcJUCI9FACSAgAMAAgJUBiVCAAdAgAAAA==.',
Ju='Julez:BAAALgAECgYJDwAAAA==.Julezara:BAAALgAECgEJAQAAAA==.Julezdruid:BAAALgADCgIJAgAAAA==.Junkai:BAACLgAFFH8FAAIHAAIJgBZEIgCoAAAHAAIJgBZEIgCoAAAuAAQKfygAAgcACAn7IykbAMYCAAcACAn7IykbAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgYJFwALAI8QAA==.',
Ke='Keco:BAAALgAECgIJBQAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8aAAMNAAcJ/Ak3DQD+AAANAAcJ/Ak3DQD+AAAWAAMJIAa1HACNAAAAAA==.',
Kl='Kladivo:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgEJAQAAAA==.',
La='Lahlania:BAAALgAECgYJDQAAAA==.Laura:BAAALgADCgQJBQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgMJAwAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAAALgAECgUJDQAAAA==.Mailaria:BAABLgAECn8cAAITAAgJDQ6PCQA+AQATAAgJDQ6PCQA+AQAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAABLgAECn8jAAMXAAcJtBvTEQCNAQAXAAcJYxfTEQCNAQAYAAYJhxnQCwBqAQAAAA==.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgMJBAAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgUJBAAAAA==.',
Me='Meingsolin:BAAALgAECgYJDwAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Minizoomies:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgADCgkJFgAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIZAAYJ9gTjWgCwAAAZAAYJ9gTjWgCwAAAAAA==.Myuk:BAABLgAECn8YAAIMAAgJMB2tBwAwAgAMAAgJMB2tBwAwAgAAAA==.',
Na='Naminay:BAAALgAECgYJDgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDAAAAA==.Natalie:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8hAAIRAAcJBRgrLQCDAQARAAcJBRgrLQCDAQAAAA==.Nerppie:BAABLgAECn8hAAIFAAcJ+h+oDQA8AgAFAAcJ+h+oDQA8AgAAAA==.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8YAAIHAAcJcRpQTwD0AQAHAAcJcRpQTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8aAAMGAAcJehWCKQCrAQAGAAcJehWCKQCrAQAVAAYJpgiATwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAZAPYEAA==.',
On='Onari:BAABLgAECn8bAAIBAAgJ5xxsCQBUAgABAAgJ5xxsCQBUAgAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAAALgAECgUJBwAAAA==.Perce:BAABLgAECn8WAAIFAAcJchyOEAAXAgAFAAcJchyOEAAXAgAAAA==.Peyotte:BAABLgAECn8VAAIaAAgJex/0BABdAgAaAAgJex/0BABdAgABLgAECggJHgAbAJsiAA==.',
Pf='Pfemme:BAABLgAECn8dAAIGAAgJaBU1HwDhAQAGAAgJaBU1HwDhAQAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgMJAwAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgMJBQAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8sAAIcAAgJfg+aEAB7AQAcAAgJfg+aEAB7AQAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgADCgkJEQAAAA==.Rustymark:BAAALgAFFAEJAQAAAA==.',
Sc='Scaletal:BAAALgADCgYJBgAAAA==.Schmetzy:BAAALgAECgYJBwAAAA==.Schmezzy:BAABLgAECn8aAAIOAAgJsB0pGQA1AgAOAAgJsB0pGQA1AgAAAA==.',
Se='Sealalicious:BAABLgAECn8hAAIdAAcJzheqEgCfAQAdAAcJzheqEgCfAQAAAA==.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgIJAgAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAAALgAECgkJEAAAAA==.Shauray:BAAALgADCgMJAwAAAA==.Shine:BAAALgAECgQJEAAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAgJGQAeALIhAA==.',
Sm='Smoo:BAAALgADCgkJHQAAAA==.',
Sn='Snø:BAAALgAECgYJDQAAAA==.',
So='Sobol:BAAALgAFFAEJAQAAAA==.Soggyaugi:BAAALgAECgUJBQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgcJDQAJAAAAAA==.',
St='Starlethia:BAAALgAECgQJBQAAAA==.',
Su='Sunshine:BAAALgADCgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgMJBAAAAA==.Tankufrdying:BAAALgADCgQJBgAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.',
Te='Tenjo:BAAALgADCgMJAwAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8ZAAIPAAcJ3xWBEQBZAQAPAAcJ3xWBEQBZAQAAAA==.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonjuren:BAAALgAECgMJBAABLgAECgYJDwAJAAAAAA==.',
Tr='Trublood:BAAALgAECgUJCgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgADCgQJBgAAAA==.',
Us='Usorloups:BAABLgAECn8eAAIbAAgJmyI1BgCEAgAbAAgJmyI1BgCEAgAAAA==.',
Ve='Velonys:BAABLgAECn8oAAQNAAkJvB/WBACPAgANAAgJiCHWBACPAgAWAAQJLCCsBQBpAQAfAAYJSRVdRABcAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vy='Vyu:BAAALgAECgkJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8bAAINAAgJVhgYAwD/AQANAAgJVhgYAwD/AQAAAA==.Wanweasley:BAAALgAECgUJCQAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgADCgkJCQAAAA==.Weh:BAABLgAECn8YAAIDAAkJsSLPCgDNAgADAAkJsSLPCgDNAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAAALgAECgYJBwAAAA==.Wizagon:BAAALgAECggJEgAAAA==.',
Wo='Woodsy:BAABLgAECn8bAAIgAAgJHBk6BwAFAgAgAAgJHBk6BwAFAgAAAA==.Wounded:BAAALgADCgYJBgAAAA==.Woundliquor:BAAALgAECgYJBwAAAA==.',
Wu='Wuinn:BAACLgAFFH8KAAIZAAQJ5xHMCgAvAQAZAAQJ5xHMCgAvAQAuAAQKfzEAAxkACQkMIN0PALkCABkACQkMIN0PALkCABAABwlKGEcIAKcBAAAA.',
Xe='Xemnas:BAABLgAECn8jAAQOAAcJpgykTwBNAQAOAAcJpgykTwBNAQAhAAEJtAtIFgAzAAAPAAEJqgG3PgAcAAAAAA==.',
Ya='Yawnday:BAAALgADCgMJAwAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJBQAAAA==.',
Zy='Zynthia:BAABLgAECn8fAAIOAAcJBSUlFwBCAgAOAAcJBSUlFwBCAgAAAA==.',
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

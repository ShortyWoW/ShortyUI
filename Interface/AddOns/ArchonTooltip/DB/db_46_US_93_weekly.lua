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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Paladin-Holy','Shaman-Elemental','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Hunter-Survival','Warlock-Destruction','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Devourer','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Protection','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Warlock-Demonology','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Blood',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Absolon:BAAALgAECgEJAQAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8WAAMBAAcJJAmpRgAfAQABAAcJJAmpRgAfAQACAAEJXgAkbAAXAAAAAA==.Aerir:BAACLgAFFH8FAAIDAAIJZQ/iQQCrAAADAAIJZQ/iQQCrAAAuAAQKfyEAAgMACAkUG+JbACYCAAMACAkUG+JbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECgUJBQAAAA==.',
Al='Alandris:BAAALgAECgcJDQAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAABLgAECn8WAAIEAAgJCSVZBwD3AgAEAAgJCSVZBwD3AgABLgAECgkJGgAFAMkcAA==.Alleriya:BAAALgAECgYJEwAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECgQJBAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAMJAwAGAAAAAA==.',
Am='Amarawyn:BAAALgAECgQJBwAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8ZAAMHAAcJTxh9CwBKAQAIAAcJpRfYOADDAQAHAAYJwhN9CwBKAQAAAA==.',
An='Andriela:BAAALgAECgYJCwAAAA==.',
Ap='Apexy:BAAALgAECgUJBgAAAA==.',
Ar='Arashikaze:BAAALgAECgYJDgAAAA==.',
Au='Augidget:BAABLgAECn8aAAICAAcJ4hXPDQCoAQACAAcJ4hXPDQCoAQAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAGAAAAAA==.Avilen:BAAALgAECgcJBwAAAA==.Aviris:BAAALgADCgYJCwABLgAECgYJBwAGAAAAAA==.',
Ay='Ayuzi:BAAALgADCgEJAQAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8aAAIEAAcJ0yN5AwDOAgAEAAcJ0yN5AwDOAgAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Bendyy:BAABLgAECn8ZAAIDAAcJSB7ZHgDzAQADAAcJSB7ZHgDzAQAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAAALgAECgYJEgAAAA==.Bitxi:BAAALgAECgUJBgAAAA==.',
Bo='Boldbane:BAAALgAECgIJAgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAAALgAECgUJEQAAAA==.',
Bu='Bubbaman:BAAALgAECgUJBgAAAA==.Burda:BAABLgAECn8ZAAIJAAkJIRRnBAA/AgAJAAkJIRRnBAA/AgAAAA==.',
Ca='Caenae:BAAALgAECgEJAQAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAMJAwAGAAAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJBgAAAA==.',
Co='Coletrain:BAAALgAECgUJCQAAAA==.Corri:BAAALgAECgMJBAAAAA==.Corriandis:BAAALgAECgMJAwAAAA==.',
Cr='Credon:BAAALgAECgUJBgAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
De='Deathcross:BAAALgAECgEJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAAALgAECgQJBwAAAA==.Dirtytaters:BAAALgAECgUJBgAAAA==.Divastating:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Do='Doró:BAAALgADCgMJAwAAAA==.',
Dt='Dtothed:BAAALgADCgQJCwAAAA==.',
Dw='Dwarfred:BAAALgAECgQJBAAAAA==.Dwimor:BAAALgAECgYJDwAAAA==.',
['Dô']='Dôro:BAAALgADCggJDQABLgAECggJGAAKAKodAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgIJAgAAAA==.Elmö:BAAALgAECgQJBAAAAA==.Elrarebriel:BAAALgADCggJBgAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgMJAwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzlyn:BAACLgAFFH8FAAILAAIJCRs/NQCzAAALAAIJCRs/NQCzAAAuAAQKfyIAAgsACAmVIrAuAH0CAAsACAmVIrAuAH0CAAAA.',
Fl='Fluffsmcgee:BAAALgADCgQJCAAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgADCgcJDgAAAA==.',
Fu='Furr:BAAALgAECgEJAQABLgAFFAMJBgABAI0NAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgEJAQAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJDwABLgAECgQJDgAGAAAAAA==.Grewsöm:BAAALgAFFAMJAwAAAA==.Grotusque:BAABLgAECn8cAAIMAAYJPhO0FAAlAQAMAAYJPhO0FAAlAQAAAA==.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8UAAINAAYJnw6hPADzAAANAAYJnw6hPADzAAAAAA==.Haiiro:BAABLgAECn8aAAIOAAcJehX0EQB8AQAOAAcJehX0EQB8AQAAAA==.Hardim:BAAALgAECgQJBgAAAA==.Hargen:BAAALgAECgIJAgAAAA==.Harknesse:BAAALgAECgUJBgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAAALgAECgYJEwAAAA==.Hewhospins:BAABLgAECn8aAAIOAAcJFRNvFABhAQAOAAcJFRNvFABhAQAAAA==.',
Hy='Hydraulicman:BAAALgADCggJEwAAAA==.',
Ig='Igknight:BAAALgADCgUJBQAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgUJBQAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAAALgAECgYJDwAAAA==.',
Jo='Jolage:BAAALgAECgYJEQAAAA==.Jolreal:BAABLgAECn8qAAMPAAgJ8B0KFACRAgAPAAcJUCIKFACRAgAJAAgJHhHhCQDEAQAAAA==.',
Ju='Julez:BAAALgAECgQJCQAAAA==.Julezara:BAAALgAECgEJAQAAAA==.Julezdruid:BAAALgADCgIJAgAAAA==.Junkai:BAACLgAFFH8FAAIQAAIJgBZBIgCoAAAQAAIJgBZBIgCoAAAuAAQKfyIAAhAACAn7IywbAMYCABAACAn7IywbAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgUJEQAGAAAAAA==.',
Ke='Keco:BAAALgAECgEJAQAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8aAAMKAAcJ/AkACgAEAQAKAAcJ/AkACgAEAQARAAMJIAazHACNAAAAAA==.',
Kl='Kladivo:BAAALgADCgYJBgAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
La='Lahlania:BAAALgAECgQJBwAAAA==.Laura:BAAALgADCgQJBQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgMJAwAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAAALgAECgUJCQAAAA==.Mailaria:BAABLgAECn8aAAISAAcJGg9eCAAoAQASAAcJGg9eCAAoAQAAAA==.Majesti:BAAALgADCgIJAQAAAA==.Malakar:BAABLgAECn8jAAMTAAcJtBthDACjAQATAAcJYxdhDACjAQAUAAYJhxnQCwBqAQAAAA==.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgEJAQAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgQJBAAAAA==.',
Me='Meingsolin:BAAALgAECgQJCQAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Minizoomies:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgADCgkJDQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIVAAYJ9gTLRgC2AAAVAAYJ9gTLRgC2AAAAAA==.Myuk:BAABLgAECn8WAAIJAAcJzx1yBwDxAQAJAAcJzx1yBwDxAQAAAA==.',
Na='Naminay:BAAALgAECgYJCQAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgUJCAAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8aAAINAAcJTxU8KABGAQANAAcJTxU8KABGAQAAAA==.Nerppie:BAABLgAECn8aAAIEAAcJ8x82DQAFAgAEAAcJ8x82DQAFAgAAAA==.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8YAAIQAAcJcRpRTwD0AQAQAAcJcRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAAALgAECgYJEwAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAVAPYEAA==.',
On='Onari:BAABLgAECn8ZAAIBAAcJVB21CAAeAgABAAcJVB21CAAeAgAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgMJAwAAAA==.',
Pe='Peezee:BAAALgAECgUJBwAAAA==.Perce:BAAALgAECgYJDwAAAA==.Peyotte:BAABLgAECn8VAAIWAAgJex/qAgBrAgAWAAgJex/qAgBrAgABLgAECggJHAAFABchAA==.',
Pf='Pfemme:BAABLgAECn8bAAIXAAgJHhQKFADyAQAXAAgJHhQKFADyAQAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgMJAwAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgIJAgAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8kAAIYAAgJaA7gCwB/AQAYAAgJaA7gCwB/AQAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgADCgkJEQAAAA==.Rustymark:BAAALgAECgYJCwAAAA==.',
Sc='Scaletal:BAAALgADCgYJBgAAAA==.Schmetzy:BAAALgAECgYJBgAAAA==.Schmezzy:BAABLgAECn8ZAAILAAcJGx5gGAD4AQALAAcJGx5gGAD4AQAAAA==.',
Se='Sealalicious:BAABLgAECn8aAAIZAAcJphepEgCfAQAZAAcJphepEgCfAQAAAA==.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgIJAgAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAAALgAECgcJEAAAAA==.Shauray:BAAALgADCgMJAwAAAA==.Shine:BAAALgAECgQJDgAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAgJFgAaAGghAA==.',
Sm='Smoo:BAAALgADCggJGQAAAA==.',
Sn='Snø:BAAALgAECgQJBwAAAA==.',
So='Sobol:BAAALgAECgQJBwAAAA==.Soggyaugi:BAAALgAECgQJBQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgYJCAAGAAAAAA==.',
St='Starlethia:BAAALgAECgQJBQAAAA==.',
Su='Sunshine:BAAALgADCgcJDAAAAA==.Sunwälker:BAAALgADCgEJAQAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgEJAQAAAA==.Tankufrdying:BAAALgADCgIJAgAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.',
Te='Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAAALgAECgcJEgAAAA==.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonjuren:BAAALgAECgEJAQABLgAECgQJCQAGAAAAAA==.',
Tr='Trublood:BAAALgAECgUJBgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgADCgIJAgAAAA==.',
Us='Usorloups:BAABLgAECn8cAAIFAAgJFyEQBgBNAgAFAAgJFyEQBgBNAgAAAA==.',
Ve='Velonys:BAABLgAECn8fAAMKAAkJnh7YBACPAgAKAAgJFyHYBACPAgAbAAUJTBbuQQAsAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8ZAAIKAAcJ1xb6AwCkAQAKAAcJ1xb6AwCkAQAAAA==.Wanweasley:BAAALgAECgQJCQAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgADCgkJCQAAAA==.Weh:BAAALgAECgcJDwAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wizagon:BAAALgAECgcJEAAAAA==.',
Wo='Woodsy:BAABLgAECn8ZAAIcAAcJAxkjBwDJAQAcAAcJAxkjBwDJAQAAAA==.Woundliquor:BAAALgAECgYJBwAAAA==.',
Wu='Wuinn:BAACLgAFFH8JAAIVAAQJ5xHLCgAvAQAVAAQJ5xHLCgAvAQAuAAQKfy0AAxUACQnHH+IPALkCABUACQnHH+IPALkCAAwABwlKGF0IAFoBAAAA.',
Xe='Xemnas:BAABLgAECn8eAAQLAAcJaQypPQBGAQALAAcJMAypPQBGAQAdAAEJowsGEAA7AAAeAAEJqAE+LwAeAAAAAA==.',
Ya='Yawnday:BAAALgADCgMJAwAAAA==.',
Za='Zaryala:BAAALgADCgkJHwAAAA==.',
Ze='Zenshift:BAAALgAECgMJBAAAAA==.',
Zy='Zynthia:BAABLgAECn8YAAILAAcJACV1EwAeAgALAAcJACV1EwAeAgAAAA==.',
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

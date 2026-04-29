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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Elemental','Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Restoration','DeathKnight-Blood','Druid-Balance','Druid-Guardian','DemonHunter-Vengeance','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-04-24',data={Af='Afu:BAABLgAECn8cAAMBAAgJ4RcDGAAAAgABAAgJ4RcDGAAAAgACAAcJHA4lLQB4AQABLgAFFAYJCgADAHYNAA==.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAECgIJBAAAAA==.Amellwind:BAAALgADCgkJHgAAAA==.',
Ar='Arana:BAAALgAECgEJAQAAAA==.Argonaut:BAAALgADCgcJEAAAAA==.Ariosto:BAEBLgAECn8eAAIEAAgJ2AkRGgBAAQAEAAgJ2AkRGgBAAQAAAA==.Arkadias:BAAALgADCgEJAQAAAA==.Arthea:BAAALgAECgQJBgAAAA==.',
As='Asmmina:BAAALgAECgYJCgAAAA==.',
Ay='Ayrwen:BAAALgAECgMJAwAAAA==.',
Az='Azarit:BAAALgADCgMJAwAAAA==.',
Ba='Badgerbadger:BAAALgADCgUJBQAAAA==.Bagelqt:BAABLgAECn8bAAIFAAgJ3hBiCQBnAQAFAAgJ3hBiCQBnAQAAAA==.Bahlsytotems:BAAALgAECgEJAQAAAA==.Bajablaster:BAABLgAECn8eAAIGAAgJrh8OHwDHAgAGAAgJrh8OHwDHAgABLgAFFAQJCQAHAHUeAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgADCgQJBAABLgAECggJIAAIAJcdAA==.',
Be='Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAAALgAECgcJEgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8QAAMCAAYJ1hjqCQA1AQACAAYJ1hjqCQA1AQAJAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJBgAGAAEaAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.',
['Bû']='Bûg:BAABLgAECn8YAAMKAAcJ/xRzKgCpAQAKAAYJvxdzKgCpAQALAAIJdQujHQA/AAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAAALgAECgQJBAAAAA==.Cheesemix:BAAALgAECgQJBQABLgAECggJGQAMAIQgAA==.Chesleigh:BAAALgADCgYJDgAAAA==.',
Ci='Cinderlight:BAAALgAECgYJDwAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgMJBQAAAA==.Cozyfog:BAAALgAECgUJBQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECggJIAAHANoZAA==.Crilynn:BAABLgAECn8bAAIHAAgJHhLqbQD5AQAHAAgJHhLqbQD5AQAAAA==.Crispycrittr:BAABLgAECn8cAAMNAAgJfwdsCADpAAANAAgJfwdsCADpAAAOAAEJrgJBCgAsAAAAAA==.Cryhavoc:BAAALgAECgUJCQAAAA==.',
Cy='Cyssor:BAAALgADCgYJEAAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJAQAAAA==.Dancingfox:BAAALgADCgYJEQAAAA==.Dathdeath:BAAALgAECgUJCQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgADCgEJAgAAAA==.',
Dk='Dkpik:BAACLgAFFH8FAAIGAAMJtQtELADqAAAGAAMJtQtELADqAAAuAAQKfygAAgYACAmsIswDAF0CAAYACAmsIswDAF0CAAAA.',
Do='Donavis:BAAALgADCgYJBgAAAA==.Dotsomahan:BAAALgAECgYJCgAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8XAAIPAAYJsRCYBwDwAAAPAAYJsRCYBwDwAAAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAAALgAECgUJCQAAAA==.Druidfaime:BAAALgADCggJEgAAAA==.Druprincess:BAAALgADCgMJAwAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
El='Elise:BAAALgAECgQJBQAAAA==.Ellzik:BAAALgADCgIJAgAAAA==.',
Fa='Falorien:BAAALgAECgUJCQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8cAAIQAAYJihQOJQDrAAAQAAYJihQOJQDrAAAAAA==.',
Fl='Flamingpax:BAAALgADCgkJEwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgADCgkJCQAAAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8UAAIGAAcJfRoJSgAVAgAGAAcJfRoJSgAVAgAAAA==.Fluffinhigh:BAAALgAECgMJAwABLgAECgcJFAAGAH0aAA==.Fluffybúnny:BAAALgADCgYJEQAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJBgAAAA==.Ghpwarlock:BAAALgAECgYJEAAAAA==.',
Gi='Giorgina:BAABLgAECn8fAAIRAAgJOxIKCACAAQARAAgJOxIKCACAAQAAAA==.',
Gl='Glasc:BAAALgAECgEJAgABLgAECgQJBAASAAAAAA==.',
Go='Gobbynuke:BAAALgAECgYJCwAAAA==.',
Gr='Grapes:BAAALgADCgYJDgAAAA==.Grigorii:BAAALgADCgEJAQAAAA==.Grimstone:BAABLgAECn8ZAAMKAAcJ1x2YGQA3AgAKAAcJ3RyYGQA3AgALAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgADCgEJAQAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJBgAAAA==.',
Hu='Hurt:BAAALgADCgYJBgABLgAECggJHQATAIMcAA==.Huurs:BAAALgADCgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgASAAAAAA==.',
It='Itzli:BAABLgAECn8fAAIPAAgJIyDTAAA9AgAPAAgJIyDTAAA9AgABLgAECggJIAAIAJcdAA==.',
Iv='Ivee:BAAALgADCgMJAwABLgAECggJIAAIAJcdAA==.',
Ja='Jaser:BAAALgADCgkJGAAAAA==.',
Je='Jellybeane:BAAALgADCgYJCwAAAA==.Jesdei:BAAALgAECgEJAQAAAA==.',
Jo='Jojen:BAAALgAECgYJEwAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgADCgYJEQAAAA==.Kavix:BAAALgAECgYJEAAAAA==.Kayos:BAABLgAECn8bAAMUAAgJ9hBtHgDLAQAUAAcJUxNtHgDLAQAQAAgJiQMvIwD3AAAAAA==.',
Ke='Kelzexx:BAAALgAECgYJCgAAAA==.',
Kh='Khorne:BAAALgAECgYJEwAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAECgUJBQABLgAECggJIAAIAJcdAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krelerokos:BAAALgADCgMJBAAAAA==.',
Ku='Kula:BAAALgAECgUJBQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgADCgYJEQAAAA==.',
Ky='Kylewithac:BAAALgADCgkJJAAAAA==.Kytes:BAAALgADCgUJBQABLgAECggJIAAHANoZAA==.',
La='Latro:BAABLgAECn8dAAMTAAgJgxwVHgBRAgATAAgJgxwVHgBRAgAPAAEJCAW1kgAnAAAAAA==.',
Le='Leenex:BAAALgADCgkJCQAAAA==.Leginer:BAAALgAECgkJAQAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAAALgAECgYJEgAAAA==.',
Lf='Lforeman:BAABLgAECn8hAAIVAAcJbxnbNwDIAQAVAAcJbxnbNwDIAQAAAA==.',
Li='Liliith:BAAALgADCgYJDAAAAA==.',
Lo='Lochnessy:BAABLgAECn8gAAMOAAgJ2BMBDQAKAgAOAAgJmRIBDQAKAgADAAgJtQyhBwB1AQAAAA==.',
Lu='Lunden:BAAALgAECgYJDwAAAA==.Luvalee:BAAALgADCgEJAQAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgIJAwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAAALgAECgYJDwAAAA==.Maldus:BAABLgAECn8gAAIIAAgJlx0KAgBKAgAIAAgJlx0KAgBKAgAAAA==.Manapaw:BAAALgAECgMJAwAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAKANcdAA==.Marloak:BAAALgAECgEJAQAAAA==.',
Mc='Mcbain:BAAALgADCgYJBgAAAA==.',
Mi='Milough:BAAALgAECgYJBgAAAA==.Mistii:BAAALgAECgYJBgAAAA==.',
Mo='Moonchips:BAAALgADCgYJBgAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.',
Na='Nathali:BAAALgAECgEJAQAAAA==.Nattsu:BAAALgADCgEJAQAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAAALgAECgYJEAAAAA==.Nightshadye:BAABLgAECn8dAAIWAAgJbQ0aHQBhAQAWAAgJbQ0aHQBhAQAAAA==.Nirazen:BAAALgADCgcJBwABLgAECgYJHAAQAIoUAA==.',
No='Noches:BAAALgAECgEJAQAAAA==.Noi:BAABLgAECn8bAAIXAAYJIA4HDwAEAQAXAAYJIA4HDwAEAQAAAA==.',
Ny='Nymphoma:BAAALgAECgUJBQAAAA==.',
Oc='Octobotic:BAABLgAECn8eAAIHAAgJTCDVGwAHAwAHAAgJTCDVGwAHAwAAAA==.',
Om='Ombos:BAABLgAECn8kAAMNAAgJTB6rBwDCAgANAAgJTB6rBwDCAgADAAIJGh2QHABXAAAAAA==.',
Or='Orenthal:BAAALgAECgQJBwAAAA==.Ortinchi:BAAALgAECgMJBwAAAA==.',
Pa='Pandacakes:BAAALgAECgYJBwAAAA==.',
Ph='Phantom:BAAALgADCgkJFAAAAA==.Pheldor:BAAALgADCgcJCQABLgABCgMJAQASAAAAAA==.Pheldorai:BAAALgAECgEJAQABLgABCgMJAQASAAAAAA==.Pheldrid:BAAALgAECgcJCAABLgABCgMJAQASAAAAAA==.Phàntoms:BAAALgAECgUJDQAAAA==.',
Pr='Protector:BAAALgAECgYJCAABLgAECggJHQATAIMcAA==.',
Pu='Puma:BAAALgAECgUJCQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAAALgAECgUJBQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAAAAA==.',
Ra='Radiance:BAAALgAECgYJEwAAAA==.Raevynn:BAABLgAECn8YAAIFAAgJRg3MOABYAQAFAAgJRg3MOABYAQAAAA==.Ragepioneer:BAAALgADCgkJDgAAAA==.Raiinzen:BAAALgAECgYJDwAAAA==.Rascanthana:BAAALgADCgcJDQAAAA==.Rawrgrr:BAAALgAECgUJCAAAAA==.Razelda:BAAALgAECgIJAwAAAA==.Razelka:BAAALgAECgYJDgAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAAALgAECgYJEwAAAA==.Repunzel:BAAALgAECgMJBwAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAABLgAECn8bAAIHAAgJLxQpFQCZAQAHAAgJLxQpFQCZAQAAAA==.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAAALgAECgUJCQAAAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAAALgAECgYJDwAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgQJBgAAAA==.Shevah:BAAALgAECgYJEQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgUJCAAAAA==.',
Si='Sid:BAACLgAFFH8JAAIHAAQJdR4DEwCAAQAHAAQJdR4DEwCAAQAuAAQKfx0AAgcACAm0JFQVACgDAAcACAm0JFQVACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.Sinsation:BAAALgAECgMJBQAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn8gAAIHAAgJ2hl3DgDUAQAHAAgJ2hl3DgDUAQAAAA==.',
So='Sophié:BAAALgAECgEJAQABLgAECggJIAAIAJcdAA==.Souxie:BAAALgADCgYJEQAAAA==.',
St='Starlost:BAAALgADCgUJBQAAAA==.Starnova:BAAALgAECgEJAgAAAA==.Stãr:BAAALgADCgYJFAAAAA==.',
Su='Sud:BAAALgAFFAEJAQAAAA==.Suelock:BAAALgAECgUJCQAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAAALgAECgEJAQAAAA==.',
['Sô']='Sôulreaper:BAAALgAECgYJDAAAAA==.',
Ta='Taali:BAAALgAECgUJCQAAAA==.Tarrant:BAAALgADCgYJCwAAAA==.Tarv:BAAALgAECgYJDwAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8iAAIPAAgJPRk+AgC5AQAPAAgJPRk+AgC5AQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAAALgAECgYJEwAAAA==.Thomasten:BAABLgAFFH8IAAIUAAMJSR+zBAAfAQAUAAMJSR+zBAAfAQAAAA==.Thomasthree:BAAALgAECgMJAwABLgAFFAMJCAAUAEkfAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgQJBAAAAA==.',
Tr='Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAABLgAECn8bAAIYAAgJwCD7AABDAgAYAAgJwCD7AABDAgAAAA==.Tricksibobby:BAAALgAECgUJCQAAAA==.',
Tu='Tuckinfank:BAAALgAECgYJCgAAAA==.',
Ty='Tylèr:BAABLgAECn8hAAQUAAgJqRueCQDHAgAUAAgJqRueCQDHAgAZAAEJOA3VKQA8AAAQAAEJJw2b3AA1AAAAAA==.',
Uj='Ujak:BAAALgAECgUJCwAAAA==.',
Um='Umami:BAAALgAECgYJEQAAAA==.',
Ur='Urnothefathr:BAAALgADCgYJBgAAAA==.',
Va='Vanillacream:BAAALgAECgYJDwAAAA==.',
Vi='Viddar:BAABLgAECn8gAAIZAAgJRhykAABIAgAZAAgJRhykAABIAgAAAA==.Viroqua:BAACLgAFFH8HAAIIAAMJqwzdBQDjAAAIAAMJqwzdBQDjAAAuAAQKfygAAggACAmsGAwQAIUCAAgACAmsGAwQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vorren:BAAALgADCgMJAwAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Winkelsmom:BAAALgAECgYJCwAAAA==.',
Wo='Woru:BAAALgAECgQJCAAAAA==.',
Wr='Wrathofangus:BAAALgAECgEJAwAAAA==.',
Xa='Xarava:BAAALgAECgYJDwAAAA==.',
Yo='Yogisa:BAABLgAECn8eAAIBAAcJEBUKKwBgAQABAAcJEBUKKwBgAQAAAA==.',
Ys='Ysanova:BAAALgAECgUJCQAAAA==.',
Ze='Zenogias:BAAALgAECgQJCQAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn8cAAIaAAcJ5CJeEQCIAgAaAAcJ5CJeEQCIAgAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgADCgYJCwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwAAAA==.',
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

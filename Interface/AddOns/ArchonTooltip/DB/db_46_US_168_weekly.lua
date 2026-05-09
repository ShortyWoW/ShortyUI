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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warrior-Fury','DemonHunter-Devourer','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Priest-Shadow','Druid-Restoration','DemonHunter-Havoc','DeathKnight-Blood','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAABLgAECn8lAAMBAAkJ6Rb5FwD/AQABAAkJ6Rb5FwD/AQACAAcJHA4jLQB4AQABLgAFFAYJEgADAJgcAA==.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAECgQJBwAAAA==.Amellwind:BAAALgAECgEJAQAAAA==.',
An='Anga:BAAALgADCgcJCgAAAA==.',
Ar='Arana:BAAALgAECgIJAgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn8rAAIEAAkJWAnnEAAuAQAEAAkJWAnnEAAuAQAAAA==.Arkadias:BAAALgADCgEJAgAAAA==.Arthea:BAAALgAECgUJCwAAAA==.',
As='Asmmina:BAAALgAECgcJEgAAAA==.',
Ay='Ayrwen:BAAALgAECgYJDAAAAA==.',
Az='Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgADCgkJDgAAAA==.Bagelqt:BAABLgAECn8jAAIFAAkJ3BBREgDOAQAFAAkJ3BBREgDOAQAAAA==.Bahlsytotems:BAAALgAECgUJBgAAAA==.Bajablaster:BAABLgAECn8oAAIGAAkJXyG5CgC2AgAGAAkJXyG5CgC2AgABLgAFFAUJDAAHABsgAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJAQABLgAECgkJJQAIAPMhAA==.',
Be='Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAAALgAFFAIJAwAAAA==.Bllacktotem:BAAALgAECgEJAQAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAAALgAECgcJDQAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8bAAMCAAYJgR4BEAC8AQACAAYJgR4BEAC8AQAJAAMJuAzzbACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAGAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMKAAkJeRYlBwA5AgAKAAkJeRYlBwA5AgALAAIJdgumHQA/AAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAAALgAECgYJCAAAAA==.Cheese:BAAALgAECgQJBAAAAA==.Cheesemix:BAABLgAECn8UAAIMAAYJ+AvlPwADAQAMAAYJ+AvlPwADAQABLgAECgkJKgAMACAgAA==.Chesleigh:BAAALgAECgEJAQAAAA==.',
Ci='Cinderlight:BAABLgAECn8cAAINAAcJVhHzRgBxAQANAAcJVhHzRgBxAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgUJBwAAAA==.Cozyfog:BAAALgAECgcJBwAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECgkJJgAHAHIYAA==.Crilynn:BAACLgAFFH8JAAIHAAQJOw69NgA2AQAHAAQJOw69NgA2AQAuAAQKfxwAAgcACAkDE9ttAPkBAAcACAkDE9ttAPkBAAAA.Crispycrittr:BAABLgAECn8eAAMOAAgJiAePFQDqAAAOAAgJiAePFQDqAAAPAAEJwwJBGgAkAAAAAA==.Cryhavoc:BAABLgAECn8VAAIQAAYJHhX7CQA1AQAQAAYJHhX7CQA1AQAAAA==.',
Cy='Cyssor:BAAALgAECgEJAQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJAwAAAA==.Dancingfox:BAAALgAECgEJAQAAAA==.Dathdeath:BAABLgAECn8UAAIRAAYJeA/PCAATAQARAAYJeA/PCAATAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgADCgEJBAAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIGAAMJ7g1SLADqAAAGAAMJ7g1SLADqAAAuAAQKfygAAgYACAm2IuIYAOcCAAYACAm2IuIYAOcCAAAA.',
Do='Docken:BAAALgAECgYJBwABLgAECgkJJgAHAHIYAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgADCgEJAgAAAA==.Dotsomahan:BAAALgAECgYJDwAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8jAAIIAAcJaxTyBwCGAQAIAAcJaxTyBwCGAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8UAAISAAYJBQe9NAD2AAASAAYJBQe9NAD2AAAAAA==.Druidfaime:BAAALgADCgkJIgAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgADCgEJAQAAAA==.',
El='Elise:BAAALgAECgYJEAAAAA==.Ellzik:BAAALgAECgQJBAAAAA==.',
Fa='Falorien:BAABLgAECn8VAAIHAAYJIRH2aQA9AQAHAAYJIRH2aQA9AQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8lAAITAAgJWxQCLgB/AQATAAgJWxQCLgB/AQAAAA==.',
Fl='Flamingpax:BAAALgADCgkJEwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgQJBAABLgAECgkJKgAHAEAUAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8gAAIGAAcJHh+XJADwAQAGAAcJHh+XJADwAQAAAA==.Fluffinhigh:BAAALgAECgYJDAABLgAECgcJIAAGAB4fAA==.Fluffybúnny:BAAALgAECgEJAQAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJKwAEAFgJAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8aAAIUAAYJvgyqbADyAAAUAAYJvgyqbADyAAAAAA==.',
Gi='Giorgina:BAABLgAECn8kAAIVAAgJdxXVFQCkAQAVAAgJdxXVFQCkAQAAAA==.',
Gl='Glasc:BAAALgAECgYJDQAAAA==.',
Gn='Gnowances:BAAALgADCgIJAgAAAA==.',
Go='Goobynuk:BAABLgAECn8VAAIHAAYJHhgUWgBgAQAHAAYJHhgUWgBgAQAAAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAECgkJIwAKAHkWAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMKAAcJ1x2TGQA3AgAKAAcJ3RyTGQA3AgALAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.',
Hu='Hurt:BAAALgAECgIJAgABLgAFFAMJCgAWAHYNAA==.Huurs:BAAALgADCgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAXAAAAAA==.',
It='Itzli:BAABLgAECn8lAAIIAAkJ8yHvAADpAgAIAAkJ8yHvAADpAgAAAA==.',
Iv='Ivee:BAAALgAECgYJBgABLgAECgkJJQAIAPMhAA==.',
Ix='Ixtli:BAAALgAECgYJBgABLgAECgkJJQAIAPMhAA==.',
Ja='Jaser:BAAALgADCgkJHgAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgEJAQAAAA==.Jesdei:BAAALgAECgIJBAAAAA==.',
Jo='Jojen:BAABLgAECn8fAAMFAAcJDxqxIwDJAQAFAAcJDxqxIwDJAQAYAAQJ+AqfOACjAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgADCgEJAQAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgEJAQAAAA==.Kavix:BAABLgAECn8cAAIZAAcJMBgGIwCvAQAZAAcJMBgGIwCvAQAAAA==.Kayos:BAABLgAECn8jAAMTAAkJnBOiGgDpAQATAAkJzRKiGgDpAQAaAAcJUxNuHgDLAQAAAA==.',
Ke='Kelzexx:BAABLgAECn8XAAIYAAcJexKuGgBmAQAYAAcJexKuGgBmAQAAAA==.',
Kh='Khalas:BAAALgADCgEJAwAAAA==.Khorne:BAABLgAECn8fAAIbAAcJBAs9GwDsAAAbAAcJBAs9GwDsAAAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAECgUJCQABLgAECgkJJQAIAPMhAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krelerokos:BAAALgADCgMJBAAAAA==.',
Ku='Kula:BAAALgAECgYJEQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgEJAQAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAECgkJJgAHAHIYAA==.',
La='Latro:BAACLgAFFH8KAAIWAAMJdg1rKQD0AAAWAAMJdg1rKQD0AAAuAAQKfyMAAxYACQlFGg8eAFECABYACQlFGg8eAFECAAgAAQkIBcaSACcAAAAA.',
Le='Leenex:BAAALgADCgkJEAAAAA==.Leginer:BAAALgAECgkJDQAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAABLgAECn8XAAMKAAcJKgrWHQAOAQAKAAcJKgrWHQAOAQAcAAEJWwR9DwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8QAAIZAAQJBRJRFwAVAQAZAAQJBRJRFwAVAQAuAAQKfyYAAxkABwlwGd83AMgBABkABwlwGd83AMgBAB0AAQmNFcRRAEEAAAAA.',
Li='Liliith:BAAALgADCgYJDAAAAA==.Lilnative:BAAALgADCgYJBgAAAA==.',
Lo='Lochnessy:BAABLgAECn8uAAMDAAkJ4hxRBAC4AgADAAkJ3hxRBAC4AgAPAAgJmRIDDQAKAgAAAA==.',
Lu='Lunden:BAABLgAECn8cAAQdAAcJBRbTHABOAQAeAAYJZRXLEQBYAQAdAAcJNhDTHABOAQAfAAUJzw//EgDuAAAAAA==.Luvalee:BAAALgADCgcJCAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgMJBgAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8bAAIEAAcJ6Ap4FAABAQAEAAcJ6Ap4FAABAQAAAA==.Maldus:BAABLgAECn8kAAIYAAkJZh5wAwDDAgAYAAkJZh5wAwDDAgABLgAECgkJJQAIAPMhAA==.Mallacath:BAAALgAECggJCwAAAA==.Manapaw:BAAALgAECgMJAwAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAKANcdAA==.Marloak:BAAALgAECgMJBgAAAA==.Mazzkal:BAAALgAECgUJCAAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Methot:BAAALgADCgIJAgAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJCQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAXAAAAAA==.',
Na='Nassaug:BAAALgADCgEJAgAAAA==.Nathali:BAAALgAECgEJAQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8cAAIEAAcJjxICEAA6AQAEAAcJjxICEAA6AQAAAA==.Nightshadye:BAACLgAFFH8HAAIbAAIJFBB8FwCLAAAbAAIJFBB8FwCLAAAuAAQKfx4AAhsACAl0DRodAGEBABsACAl0DRodAGEBAAAA.Nirazen:BAAALgADCgcJBwABLgAECggJJQATAFsUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIdAAYJIA6SKwDrAAAdAAYJIA6SKwDrAAAAAA==.',
Ny='Nymphoma:BAAALgAECgcJBwAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8IAAIHAAMJRxdGRAABAQAHAAMJRxdGRAABAQAuAAQKfyAAAgcACAmxIdkbAAcDAAcACAmxIdkbAAcDAAAA.',
Om='Ombos:BAABLgAECn8xAAMOAAkJQiECAgDyAgAOAAkJQiECAgDyAgADAAQJOxhOMwDVAAAAAA==.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Ortinchi:BAABLgAECn8WAAICAAYJgwh7KgDhAAACAAYJgwh7KgDhAAAAAA==.',
Pa='Pandacakes:BAAALgAECgYJBwAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAAALgAECgQJBQAAAA==.Pheldor:BAAALgAECgMJAwABLgABCgMJAQAXAAAAAA==.Pheldorai:BAAALgAECgYJCQABLgABCgMJAQAXAAAAAA==.Pheldrid:BAABLgAECn8VAAIFAAgJ2x4MCABwAgAFAAgJ2x4MCABwAgABLgABCgMJAQAXAAAAAA==.Phàntoms:BAABLgAECn8ZAAIRAAYJoxcrBwA+AQARAAYJoxcrBwA+AQAAAA==.',
Pr='Protector:BAAALgAECgYJDgABLgAFFAMJCgAWAHYNAA==.',
Pu='Puma:BAABLgAECn8VAAIeAAYJow42FgC0AAAeAAYJow42FgC0AAAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAAALgAECgYJDwAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgYJDQAXAAAAAA==.',
Ra='Radiance:BAABLgAECn8fAAIDAAcJZiGKCABJAgADAAcJZiGKCABJAgAAAA==.Raevynn:BAABLgAECn8bAAIFAAkJLQzVOABYAQAFAAkJLQzVOABYAQAAAA==.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8bAAIBAAcJ0BzUDAAcAgABAAcJ0BzUDAAcAgAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECgQJBAAAAA==.Rawrgrr:BAAALgAECgcJEwAAAA==.Razelda:BAAALgAECgQJBwAAAA==.Razelka:BAABLgAECn8XAAISAAgJnRHVFADEAQASAAgJnRHVFADEAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8cAAIHAAcJkhBPVQBsAQAHAAcJkhBPVQBsAQAAAA==.Repunzel:BAABLgAECn8WAAINAAYJjQYKigDZAAANAAYJjQYKigDZAAAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAABLgAECn8qAAIHAAkJQBT2IwAWAgAHAAkJQBT2IwAWAgAAAA==.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAABLgAECn8VAAIWAAYJbBR2PwBQAQAWAAYJbBR2PwBQAQAAAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAAALgAECgcJEQAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgYJBgAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAAAAA==.Shamrok:BAEALgAECgEJAQABLgAECgkJKwAEAFgJAA==.Shevah:BAABLgAECn8UAAIfAAcJBBD+FQBYAQAfAAcJBBD+FQBYAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgYJDgAAAA==.',
Si='Sid:BAACLgAFFH8MAAIHAAUJGyAUEwCAAQAHAAUJGyAUEwCAAQAuAAQKfygAAgcACQm9I1wVACgDAAcACQm9I1wVACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.Sinsation:BAAALgAECgQJCQAAAA==.',
Sl='Slomo:BAAALgADCgEJAQAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn8mAAIHAAkJchj8HgAwAgAHAAkJchj8HgAwAgAAAA==.',
So='Sophié:BAAALgAECgYJCAABLgAECgkJJQAIAPMhAA==.Souxie:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgADCgcJDwAAAA==.Starnova:BAAALgAECgQJBgAAAA==.Stãr:BAAALgAECgIJAgAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8UAAIUAAYJGwR2ggDBAAAUAAYJGwR2ggDBAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAAALgAECgMJBwAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8ZAAIGAAgJDBLQLwC6AQAGAAgJDBLQLwC6AQAAAA==.',
Ta='Taali:BAABLgAECn8VAAINAAYJ4A2maAAcAQANAAYJ4A2maAAcAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn8bAAIcAAcJ6QiFBwAdAQAcAAcJ6QiFBwAdAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8sAAIIAAgJfhxFAwAqAgAIAAgJfhxFAwAqAgAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8dAAIVAAcJHhquEgDFAQAVAAcJHhquEgDFAQAAAA==.Thomasten:BAACLgAFFH8NAAIaAAQJ3yTvAAC6AQAaAAQJ3yTvAAC6AQAuAAQKfx8AAxoACAk9IzsTADwCABoACAmzIDsTADwCABAABQnrIQQHAIUBAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAQJDQAaAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgUJBgABLgAECgYJDAAXAAAAAA==.',
Tr='Tranquil:BAAALgAECgYJBgABLgAFFAMJCgAWAHYNAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAABLgAECn8qAAIeAAkJISB3AQDRAgAeAAkJISB3AQDRAgAAAA==.Tricksibobby:BAABLgAECn8VAAMdAAYJOBwhFAChAQAdAAYJOBwhFAChAQAZAAYJDBcNLwBmAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tylèr:BAACLgAFFH8GAAIaAAMJqBgdCQAFAQAaAAMJqBgdCQAFAQAuAAQKfzIABBoACQncHVIDAKoCABoACQncHVIDAKoCABAAAQk4DdMpADwAABMAAQk2DbDcADUAAAAA.',
Uj='Ujak:BAABLgAECn8XAAIgAAYJEQ73DgAUAQAgAAYJEQ73DgAUAQAAAA==.',
Um='Umami:BAABLgAECn8cAAIMAAYJahcFMwBBAQAMAAYJahcFMwBBAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgADCgYJBgAAAA==.',
Va='Vanillacream:BAABLgAECn8cAAIWAAcJ6xU+KwCjAQAWAAcJ6xU+KwCjAQAAAA==.',
Vi='Viddar:BAABLgAECn8jAAIQAAkJUx2YAQCaAgAQAAkJUx2YAQCaAgAAAA==.Viroqua:BAACLgAFFH8NAAIYAAQJswvQDQAvAQAYAAQJswvQDQAvAQAuAAQKfy8AAhgACAkEGQsQAIUCABgACAkEGQsQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vorren:BAAALgADCgMJAwAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgADCggJCAABLgAECggJJQATAFsUAA==.Winkelsmom:BAABLgAECn8VAAQdAAcJ+w9sHABRAQAdAAcJ+w9sHABRAQAZAAUJ4gliZQCOAAAfAAIJJQUILwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8UAAMgAAYJ7heiCgBqAQAgAAYJ7heiCgBqAQAMAAUJPgu2TQDIAAAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCQAAAA==.',
Xa='Xarava:BAABLgAECn8cAAIMAAcJ4xVXIgCiAQAMAAcJ4xVXIgCiAQAAAA==.',
Yo='Yogisa:BAABLgAECn8qAAMBAAgJEBbpGACIAQABAAgJEBbpGACIAQAJAAEJAADPewAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8VAAIGAAYJwRVVSwBZAQAGAAYJwRVVSwBZAQAAAA==.',
Za='Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zenogias:BAABLgAECn8VAAIHAAYJSRLDZABIAQAHAAYJSRLDZABIAQAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn8fAAIhAAgJ0SJdEQCIAgAhAAgJ0SJdEQCIAgAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAECgkJIwAKAHkWAA==.',
['ßú']='ßúg:BAAALgAECgkJAgABLgAECgkJIwAKAHkWAA==.',
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

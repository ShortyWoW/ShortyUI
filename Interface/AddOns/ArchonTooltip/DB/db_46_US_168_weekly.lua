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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship','DemonHunter-Devourer','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','DemonHunter-Havoc','DeathKnight-Blood','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Druid-Feral','DemonHunter-Vengeance','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-05-01',data={Af='Afu:BAABLgAECn8cAAMBAAgJ4Rf6FwD/AQABAAgJ4Rf6FwD/AQACAAcJHA4nLQB4AQABLgAFFAYJDwADADAYAA==.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAECgQJBwAAAA==.Amellwind:BAAALgAECgEJAQAAAA==.',
An='Anga:BAAALgADCgEJAQAAAA==.',
Ar='Arana:BAAALgAECgIJAgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn8mAAIEAAgJ5AkTGgBAAQAEAAgJ5AkTGgBAAQAAAA==.Arkadias:BAAALgADCgEJAQAAAA==.Arthea:BAAALgAECgUJCwAAAA==.',
As='Asmmina:BAAALgAECgYJEAAAAA==.',
Ay='Ayrwen:BAAALgAECgQJCgAAAA==.',
Az='Azarit:BAAALgAECgQJCAAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgADCgUJBQAAAA==.Bagelqt:BAABLgAECn8bAAIFAAgJ3hAxFgBcAQAFAAgJ3hAxFgBcAQAAAA==.Bahlsytotems:BAAALgAECgUJBgAAAA==.Bajablaster:BAABLgAECn8eAAIGAAgJrh8THwDHAgAGAAgJrh8THwDHAgABLgAFFAUJCwAHABwgAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgADCgQJBAABLgAECgkJIwAIAAkeAA==.',
Be='Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAAALgAFFAIJAgAAAA==.Bllacktotem:BAAALgAECgEJAQAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAAALgAECgYJBgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8WAAMCAAYJ9By3DACsAQACAAYJ9By3DACsAQAJAAMJuAzubACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQAAAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.',
['Bû']='Bûg:BAABLgAECn8aAAMKAAgJzxLxFAA0AQAKAAcJvBTxFAA0AQALAAIJdQumHQA/AAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAAALgAECgUJBQAAAA==.Cheese:BAAALgADCgYJBgAAAA==.Cheesemix:BAAALgAECgUJDgABLgAECggJIQAMACwhAA==.Chesleigh:BAAALgAECgEJAQAAAA==.',
Ci='Cinderlight:BAABLgAECn8VAAINAAYJlQ2HTQAjAQANAAYJlQ2HTQAjAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgUJBwAAAA==.Cozyfog:BAAALgAECgUJBQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECgkJJQAHAHEYAA==.Crilynn:BAACLgAFFH8FAAIHAAMJVQx5NwD1AAAHAAMJVQx5NwD1AAAuAAQKfxwAAgcACAkDE95tAPkBAAcACAkDE95tAPkBAAAA.Crispycrittr:BAABLgAECn8eAAMOAAgJiQeKEAD0AAAOAAgJiQeKEAD0AAAPAAEJrgLxFAAoAAAAAA==.Cryhavoc:BAAALgAECgYJDwAAAA==.',
Cy='Cyssor:BAAALgAECgEJAQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJAgAAAA==.Dancingfox:BAAALgAECgEJAQAAAA==.Dathdeath:BAAALgAECgUJDgAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgADCgEJAwAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIGAAMJ8g1LLADqAAAGAAMJ8g1LLADqAAAuAAQKfygAAgYACAmsIuIYAOcCAAYACAmsIuIYAOcCAAAA.',
Do='Donavis:BAAALgADCgYJBgAAAA==.Dotsomahan:BAAALgAECgYJCwAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8eAAIQAAcJORQCBgCUAQAQAAcJORQCBgCUAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAAALgAECgUJDgAAAA==.Druidfaime:BAAALgADCgkJGgAAAA==.Druprincess:BAAALgADCgMJAwAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgADCgEJAQAAAA==.',
El='Elise:BAAALgAECgUJCgAAAA==.Ellzik:BAAALgADCgQJBAAAAA==.',
Fa='Falorien:BAAALgAECgYJDwAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8dAAIRAAcJwxF2NAARAQARAAcJwxF2NAARAQAAAA==.',
Fl='Flamingpax:BAAALgADCgkJEwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgADCgkJCQABLgAECggJIwAHAJoVAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8aAAIGAAcJXRsKLwB+AQAGAAcJXRsKLwB+AQAAAA==.Fluffinhigh:BAAALgAECgMJBgABLgAECgcJGgAGAF0bAA==.Fluffybúnny:BAAALgAECgEJAQAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgIJAwABLgAECggJJgAEAOQJAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8VAAISAAYJXwrVWQDkAAASAAYJXwrVWQDkAAAAAA==.',
Gi='Giorgina:BAABLgAECn8hAAITAAgJcBVGDwCvAQATAAgJcBVGDwCvAQAAAA==.',
Gl='Glasc:BAAALgAECgUJBwAAAA==.',
Gn='Gnowances:BAAALgADCgIJAgAAAA==.',
Go='Gobbynuke:BAAALgAECgYJEQAAAA==.',
Gr='Grapes:BAAALgADCgYJDgAAAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMKAAcJ1x2VGQA3AgAKAAcJ3RyVGQA3AgALAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.',
Hu='Hurt:BAAALgADCgYJBgABLgAFFAMJBwAUAHcJAA==.Huurs:BAAALgADCgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAVAAAAAA==.',
It='Itzli:BAABLgAECn8iAAIQAAkJryDaAAC8AgAQAAkJryDaAAC8AgABLgAECgkJIwAIAAkeAA==.',
Iv='Ivee:BAAALgADCgMJAwABLgAECgkJIwAIAAkeAA==.',
Ix='Ixtli:BAAALgAECgEJAQABLgAECgkJIwAIAAkeAA==.',
Ja='Jaser:BAAALgADCgkJHgAAAA==.',
Je='Jellybeane:BAAALgAECgEJAQAAAA==.Jesdei:BAAALgAECgIJAwAAAA==.',
Jo='Jojen:BAABLgAECn8aAAIFAAcJDxquIwDJAQAFAAcJDxquIwDJAQAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgEJAQAAAA==.Kavix:BAABLgAECn8XAAIWAAcJKRicHgCMAQAWAAcJKRicHgCMAQAAAA==.Kayos:BAABLgAECn8cAAMRAAgJxxTcGwCNAQAXAAcJUxNtHgDLAQARAAgJ1xHcGwCNAQAAAA==.',
Ke='Kelzexx:BAAALgAECgYJEAAAAA==.',
Kh='Khalas:BAAALgADCgEJAQAAAA==.Khorne:BAABLgAECn8aAAIYAAcJwgoKEwDwAAAYAAcJwgoKEwDwAAAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAECgUJBwABLgAECgkJIwAIAAkeAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krelerokos:BAAALgADCgMJBAAAAA==.',
Ku='Kula:BAAALgAECgYJCwAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgEJAQAAAA==.',
Ky='Kylewithac:BAAALgADCgkJJAAAAA==.Kytes:BAAALgADCgUJBQABLgAECgkJJQAHAHEYAA==.',
La='Latro:BAACLgAFFH8HAAIUAAMJdwmhHQDoAAAUAAMJdwmhHQDoAAAuAAQKfyEAAxQACAmDHBEeAFECABQACAmDHBEeAFECABAAAQkIBbuSACcAAAAA.',
Le='Leenex:BAAALgADCgkJEAAAAA==.Leginer:BAAALgAECgkJAwAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAABLgAECn8XAAMKAAcJKQrJFwAWAQAKAAcJKQrJFwAWAQAZAAEJWwR/DwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8IAAIWAAMJyBUMFwDdAAAWAAMJyBUMFwDdAAAuAAQKfyYAAxYABwlvGeE3AMgBABYABwlvGeE3AMgBABoAAQmLFWhBAEEAAAAA.',
Li='Liliith:BAAALgADCgYJDAAAAA==.',
Lo='Lochnessy:BAABLgAECn8lAAMDAAkJExs7BQBaAgADAAkJdhc7BQBaAgAPAAgJmRICDQAKAgAAAA==.',
Lu='Lunden:BAABLgAECn8VAAMbAAYJAhfLEQBYAQAbAAYJZhXLEQBYAQAcAAUJzg9aDgD1AAAAAA==.Luvalee:BAAALgADCgEJAQAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgIJAwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8UAAIEAAYJjgpkIwDsAAAEAAYJjgpkIwDsAAAAAA==.Maldus:BAABLgAECn8jAAIIAAkJCR4FAgDDAgAIAAkJCR4FAgDDAgAAAA==.Mallacath:BAAALgAECgIJAgAAAA==.Manapaw:BAAALgAECgMJAwAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAKANcdAA==.Marloak:BAAALgAECgIJBAAAAA==.Mazzkal:BAAALgAECgUJBQAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Methot:BAAALgADCgIJAgAAAA==.',
Mi='Milough:BAAALgAECgYJCAAAAA==.Mistii:BAAALgAECgYJBgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAVAAAAAA==.',
Na='Nassaug:BAAALgADCgEJAQAAAA==.Nathali:BAAALgAECgEJAQAAAA==.Nattsu:BAAALgAECgEJAgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8XAAIEAAcJixL0CwBCAQAEAAcJixL0CwBCAQAAAA==.Nightshadye:BAACLgAFFH8FAAIYAAIJFxDGEACQAAAYAAIJFxDGEACQAAAuAAQKfx4AAhgACAltDRodAGEBABgACAltDRodAGEBAAAA.Nirazen:BAAALgADCgcJBwABLgAECgcJHQARAMMRAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIaAAYJIA5RIQDzAAAaAAYJIA5RIQDzAAAAAA==.',
Ny='Nymphoma:BAAALgAECgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8FAAIHAAIJ5hzvNgC8AAAHAAIJ5hzvNgC8AAAuAAQKfyAAAgcACAmxIdgbAAcDAAcACAmxIdgbAAcDAAAA.',
Om='Ombos:BAABLgAECn8pAAMOAAkJQiHPAgCAAgAOAAkJQiHPAgCAAgADAAMJ1hmgMQCYAAAAAA==.',
Or='Orenthal:BAAALgAECgQJCwAAAA==.Ortinchi:BAAALgAECgYJEAAAAA==.',
Pa='Pandacakes:BAAALgAECgYJBwAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAAALgADCgkJFAAAAA==.Pheldor:BAAALgAECgMJAwABLgABCgMJAQAVAAAAAA==.Pheldorai:BAAALgAECgMJAwABLgABCgMJAQAVAAAAAA==.Pheldrid:BAAALgAECgcJCwABLgABCgMJAQAVAAAAAA==.Phàntoms:BAAALgAECgYJEwAAAA==.',
Pr='Protector:BAAALgAECgYJCAABLgAFFAMJBwAUAHcJAA==.',
Pu='Puma:BAAALgAECgYJDwAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAAALgAECgUJCgAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgUJBwAVAAAAAA==.',
Ra='Radiance:BAABLgAECn8aAAIDAAcJriBIBgA6AgADAAcJriBIBgA6AgAAAA==.Raevynn:BAABLgAECn8bAAIFAAkJLgzOOABYAQAFAAkJLgzOOABYAQAAAA==.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8VAAIBAAYJDx1pDQDPAQABAAYJDx1pDQDPAQAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rascanthana:BAAALgADCgcJDQAAAA==.Rawrgrr:BAAALgAECgYJDQAAAA==.Razelda:BAAALgAECgMJBgAAAA==.Razelka:BAAALgAECgcJEgAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8aAAIHAAcJiRB+PwBwAQAHAAcJiRB+PwBwAQAAAA==.Repunzel:BAAALgAECgYJEAAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAABLgAECn8jAAIHAAgJmhW8KQC9AQAHAAgJmhW8KQC9AQAAAA==.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAAALgAECgYJDwAAAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAAALgAECgYJEAAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAAAAA==.Shevah:BAAALgAECgcJEgAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgUJCAAAAA==.',
Si='Sid:BAACLgAFFH8LAAIHAAUJHCAQEwCAAQAHAAUJHCAQEwCAAQAuAAQKfx8AAgcACAm0JFsVACgDAAcACAm0JFsVACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.Sinsation:BAAALgAECgQJCAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn8lAAIHAAkJcRhlFAA3AgAHAAkJcRhlFAA3AgAAAA==.',
So='Sophié:BAAALgAECgEJAgABLgAECgkJIwAIAAkeAA==.Souxie:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgADCgUJBQAAAA==.Starnova:BAAALgAECgMJBQAAAA==.Stãr:BAAALgADCgcJGwAAAA==.',
Su='Sud:BAAALgAFFAEJAQAAAA==.Suelock:BAAALgAECgUJDgAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAAALgAECgIJBQAAAA==.',
['Sô']='Sôulreaper:BAAALgAECgcJEwAAAA==.',
Ta='Taali:BAAALgAECgYJDwAAAA==.Tarrant:BAAALgADCgYJCwAAAA==.Tarv:BAABLgAECn8UAAIZAAYJuQV8BwDMAAAZAAYJuQV8BwDMAAAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8rAAIQAAgJgBzzAQBJAgAQAAgJgBzzAQBJAgAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8YAAITAAcJ0BhNDwCvAQATAAcJ0BhNDwCvAQAAAA==.Thomasten:BAACLgAFFH8JAAIXAAMJHSK7BAAfAQAXAAMJHSK7BAAfAQAuAAQKfxgAAxcACAmpITwTADwCABcACAl5IDwTADwCAB0AAQmKGM4VAEcAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAMJCQAXAB0iAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgUJBgAAAA==.',
Tr='Tranquil:BAAALgAECgYJBgABLgAFFAMJBwAUAHcJAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAABLgAECn8jAAIbAAgJUiF3AQCCAgAbAAgJUiF3AQCCAgAAAA==.Tricksibobby:BAAALgAECgYJDwAAAA==.',
Tu='Tuckinfank:BAAALgAECgcJDAAAAA==.',
Ty='Tylèr:BAABLgAECn8wAAQXAAkJOx26AgCDAgAXAAkJOx26AgCDAgAdAAEJOA3XKQA8AAARAAEJJw2m3AA1AAAAAA==.',
Uj='Ujak:BAAALgAECgYJEQAAAA==.',
Um='Umami:BAABLgAECn8XAAIMAAYJwBY9KAAtAQAMAAYJwBY9KAAtAQAAAA==.',
Ur='Urnothefathr:BAAALgADCgYJBgAAAA==.',
Va='Vanillacream:BAABLgAECn8VAAIUAAYJaRC6NAA+AQAUAAYJaRC6NAA+AQAAAA==.',
Vi='Viddar:BAABLgAECn8jAAIdAAkJMB3gAACqAgAdAAkJMB3gAACqAgAAAA==.Viroqua:BAACLgAFFH8LAAIIAAQJmwveCAAzAQAIAAQJmwveCAAzAQAuAAQKfy8AAggACAkFGQsQAIUCAAgACAkFGQsQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vorren:BAAALgADCgMJAwAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wileecyotie:BAAALgADCggJCAABLgAECgcJHQARAMMRAA==.Winkelsmom:BAAALgAECgYJDwAAAA==.',
Wo='Woru:BAAALgAECgYJDgAAAA==.',
Wr='Wrathofangus:BAAALgAECgUJCAAAAA==.',
Xa='Xarava:BAABLgAECn8VAAIMAAYJmhX1IQBWAQAMAAYJmhX1IQBWAQAAAA==.',
Yo='Yogisa:BAABLgAECn8lAAMBAAgJTBQkFwBRAQABAAgJTBQkFwBRAQAJAAEJAACwYQAAAAAAAA==.',
Ys='Ysanova:BAAALgAECgYJDwAAAA==.',
Za='Zarkanna:BAAALgAECgUJBQAAAA==.',
Ze='Zenogias:BAAALgAECgYJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn8dAAIeAAgJiSBbEQCIAgAeAAgJiSBbEQCIAgAAAA==.',
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

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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Druid-Balance','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Priest-Holy',}
local provider = {region='US',realm='Chromaggus',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAIJAgABLgAFFAUJFgABAIIYAQ==.',
An='Anasazi:BAAALgADCgkJMAAAAA==.',
Ar='Aranaya:BAAALgAECgUJCgAAAA==.',
As='Aspersio:BAAALgAECgUJCQAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgADCgcJBwABLgAECgQJCAACAAAAAA==.Barehunt:BAAALgADCgcJBwABLgAECgQJCAACAAAAAA==.',
Be='Bedorea:BAABLgAECn8cAAMDAAYJ5BJ6GwBUAQADAAYJ5BJ6GwBUAQAEAAEJ0Aa1RQAtAAAAAA==.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Blessurheart:BAAALgAECgMJAwABLgAFFAUJFgABAIIYAQ==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Boxab:BAAALgAECgEJAQABLgAFFAUJFgABAIIYAQ==.',
Bu='Buckchuck:BAAALgAECgYJDQAAAA==.Bumwitboba:BAAALgAECgYJDgAAAA==.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAAALgAECgUJCAAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAECgUJDgACAAAAAA==.',
Da='Daelnei:BAAALgAECgYJDgAAAA==.Damja:BAAALgAECgYJDgAAAA==.Darkloky:BAAALgAECgYJEAAAAA==.Darthburger:BAAALgADCgEJAQAAAA==.Dasa:BAAALgAECgYJDgAAAA==.',
De='Debby:BAAALgAECgUJBgAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECgQJBQAAAA==.',
Do='Donane:BAAALgAECgQJBAAAAA==.',
Dr='Drimbo:BAAALgAECgUJCQAAAA==.',
Du='Duareapa:BAAALgAECgUJBgAAAA==.',
Ec='Echoes:BAABLgAECn8VAAIFAAYJXBqaEQCBAQAFAAYJXBqaEQCBAQAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fi='Fizzl:BAABLgAECn8XAAIGAAYJwBQOFgBQAQAGAAYJwBQOFgBQAQAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAAALgAECgUJDgAAAA==.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAECgEJAQAAAA==.',
Ja='Jasa:BAAALgAECgYJDAAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAAALgAECgUJCQAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8WAAMHAAgJ/AEObwDTAAAHAAgJ/AEObwDTAAAIAAYJNQZhLgDFAAAAAA==.',
Kh='Khane:BAABLgAECn8VAAMJAAYJFBO9GgB2AQAJAAYJFBO9GgB2AQAKAAMJiRNH+ACiAAAAAA==.',
Ki='Kiernan:BAAALgAECgEJAQAAAA==.Kiril:BAAALgAECgIJAgAAAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAECgUJDgACAAAAAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Maelle:BAACLgAFFH8WAAMBAAUJghi7FQBHAQABAAUJghi7FQBHAQALAAIJ7gxSDQCiAAAuAAQKfygABAEACAmTJHYbALACAAEACAnrInYbALACAAsABQlaIlIMAP0BAAwAAgkxIxMYALoAAAAA.Magewings:BAAALgAECgUJCgAAAA==.Manglehaft:BAAALgAECgMJAwAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgADCggJCAAAAA==.',
Me='Mexcutioner:BAABLgAECn8oAAINAAkJHxnOEQAFAgANAAkJHxnOEQAFAgAAAA==.',
Mi='Miranda:BAAALgAFFAEJAQABLgAFFAUJFgABAIIYAQ==.Mixup:BAABLgAECn8wAAIBAAkJoh1NBQDAAgABAAkJoh1NBQDAAgAAAA==.',
Mo='Mollan:BAAALgAECgIJAgAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn8mAAIOAAgJCRkoBgDIAQAOAAgJCRkoBgDIAQAAAA==.Mythikal:BAAALgAECgQJCQAAAA==.',
Na='Nalgene:BAAALgADCgcJDQAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAACAAAAAA==.',
Ot='Otekah:BAAALgAECgUJCQAAAA==.',
Pe='Peppanutz:BAAALgADCgQJBgAAAA==.',
Pi='Pinuno:BAAALgAECgQJBQAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn8nAAIPAAgJGgzLLQCEAQAPAAgJGgzLLQCEAQAAAA==.',
Pu='Puncho:BAAALgAECgUJCQAAAA==.Putmypwninu:BAAALgAECgYJDAAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Ri='Riiven:BAAALgAECggJCQABLgAECgkJHwAQAFsPAA==.',
Ro='Ronald:BAAALgADCgEJAQAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQACAAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sh='Shikaka:BAAALgAECgQJBAABLgAECgQJCAACAAAAAA==.Shme:BAACLgAFFH8QAAIQAAQJ8gsIHgBSAQAQAAQJ8gsIHgBSAQAuAAQKfzQAAxAACAnVHUsrAMUCABAACAnVHUsrAMUCABEAAQmKFQQdADgAAAAA.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAQAPILAA==.Shruikan:BAAALgAECgQJBAAAAA==.',
Si='Sidaria:BAAALgAECgEJAQABLgAECggJJAAKAMsjAA==.Silex:BAAALgADCgIJAgAAAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgADCgEJAQAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQACAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAAALgAECgQJCQAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.',
Sw='Swayne:BAAALgAECgQJDwAAAA==.',
Sy='Syllogica:BAAALgAECgcJDgAAAA==.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn8wAAISAAkJuCIqAQAxAwASAAkJuCIqAQAxAwAAAA==.',
Te='Tenderloinz:BAAALgAECgQJBwAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIJAAIJdRdwGQCWAAAJAAIJdRdwGQCWAAAuAAQKfyoAAgkACAl/IrEFABADAAkACAl/IrEFABADAAAA.',
Ty='Tyrant:BAAALgAECgUJCAAAAA==.',
Va='Valanir:BAAALgADCgQJCAAAAA==.Vaughan:BAABLgAECn8kAAIKAAgJyyN6BQDCAgAKAAgJyyN6BQDCAgAAAA==.',
Vi='Violence:BAAALgAECgQJBwAAAA==.',
Wa='Waffle:BAABLgAECn8oAAIBAAgJSxSRHgC9AQABAAgJSxSRHgC9AQAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.Wasteysage:BAAALgAECgYJDQAAAA==.',
Wh='Whollycow:BAAALgAECgQJCAAAAA==.',
Wi='Wildheart:BAAALgADCgIJAgAAAA==.Wily:BAAALgAECgEJAQABLgAECgUJDgACAAAAAA==.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgQJBQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
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

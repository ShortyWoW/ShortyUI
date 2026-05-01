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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Mage-Frost','DeathKnight-Unholy','Unknown-Unknown','Mage-Arcane','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','DemonHunter-Vengeance','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','DeathKnight-Frost','Monk-Brewmaster','Evoker-Augmentation','Priest-Holy','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc','Paladin-Protection',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-05-01',data={Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECgQJBAABLgAFFAQJDgABAGAjAA==.Alex:BAAALgAECggJCwABLgAECggJIQACAHYfAA==.Alexw:BAABLgAECn8hAAQCAAcJdh8XJwCTAQACAAcJCBwXJwCTAQADAAQJIBm/JQAwAQAEAAQJXyFHEAApAQAAAA==.',
Au='Audrey:BAAALgAECggJEQAAAA==.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAAALgAECgQJDgABLgAECggJIQAFAFIVAA==.Bat:BAAALgAECgUJBQAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAIGAAgJKiIbEQAzAgAGAAgJKiIbEQAzAgABLgAFFAEJAQAHAAAAAA==.',
Br='Braggie:BAAALgADCgIJAgAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8UAAIIAAYJNAd2DQDxAAAIAAYJNAd2DQDxAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8HAAIJAAQJWQTlEADyAAAJAAQJWQTlEADyAAAuAAQKfyAAAgkACAkvGJ0bACUCAAkACAkvGJ0bACUCAAAA.',
Co='Codh:BAAALgADCgUJBQABLgAECgUJCQAHAAAAAA==.Codum:BAAALgAECgUJCQAAAA==.',
Da='Dackosaur:BAABLgAECn8UAAIKAAYJniPfAwD3AQAKAAYJniPfAwD3AQAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgADCgcJDAAAAA==.Danekriste:BAABLgAECn8RAAILAAYJ3gVDVgClAAALAAYJ3gVDVgClAAAAAA==.Darkenedone:BAACLgAFFH8PAAIMAAQJWxyVBQBEAQAMAAQJWxyVBQBEAQAuAAQKfxkAAwwACQm1GzcQAAgCAAwACQm1GzcQAAgCAAYAAgkPErkUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECgEJAQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAHAAAAAA==.Demono:BAABLgAECn8WAAILAAYJExdCXgCGAQALAAYJExdCXgCGAQABLgAFFAUJEwANAHckAA==.',
Do='Doggx:BAAALgADCgYJCAAAAA==.',
Dr='Drfrangelico:BAAALgAECggJEQAAAA==.Druido:BAACLgAFFH8TAAINAAUJdyRKAQARAgANAAUJdyRKAQARAgAuAAQKfysAAw0ACQnZJS8AAO8DAA0ACQnZJS8AAO8DAAkABAmTIVY5AFIBAAAA.Drunkmonk:BAAALgAECgUJCQAAAA==.',
Ds='Ds:BAACLgAFFH8HAAIOAAMJLyKiAQAVAQAOAAMJLyKiAQAVAQAuAAQKfyIAAg4ACAmdIygBACcDAA4ACAmdIygBACcDAAAA.',
Du='Dumdum:BAAALgADCgcJEAAAAA==.',
En='Enjoyby:BAABLgAECn8VAAIPAAYJZCLoBgBQAgAPAAYJZCLoBgBQAgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAYJGgACAO4jAA==.',
Fr='Frankßuck:BAABLgAECn8ZAAMQAAYJ5gJXWADBAAAQAAYJ1wJXWADBAAARAAYJDQKuFQCDAAAAAA==.Friarstrange:BAAALgAECgQJCAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAINAAYJHiEEKgAKAgANAAYJHiEEKgAKAgAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECggJHgASABgeAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDlUgDoAQATAAgJfhDlUgDoAQAAAA==.Harakki:BAABLgAECn8UAAIUAAYJHhX+BABMAQAUAAYJHhX+BABMAQAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
Ho='Holyroran:BAABLgAECn8aAAIBAAYJEyKnCABOAgABAAYJEyKnCABOAgAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
Ia='Iamundeadian:BAAALgADCgkJAgABLgAECgkJAgAHAAAAAA==.',
Ic='Icdeadpeeple:BAAALgAECgQJDAAAAA==.Icytouch:BAAALgAECgQJBwAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECgcJGQAVACIfAA==.',
Im='Immortal:BAAALgAECgkJCAAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgADCgYJBgAAAA==.Jellybeanrez:BAAALgAECgYJEwAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgcJDgAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8XAAIFAAgJqhtAHgD2AQAFAAgJqhtAHgD2AQAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgcJEAAHAAAAAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAUJCwAWALcWAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kreiger:BAAALgADCgUJCQAAAA==.Kritz:BAAALgAECgEJAgAAAA==.',
La='Laine:BAABLgAECn8WAAIXAAYJshuHHwDlAQAXAAYJshuHHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAAALgAFFAEJAQAAAA==.',
Lo='Lockstar:BAAALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8aAAQCAAYJ7iP9AAASAgACAAYJ7iP9AAASAgAEAAEJAABeBABbAAADAAEJnQ2RFQBTAAAuAAQKfyQAAwIACQm3Is8EAG4DAAIACQm3Is8EAG4DAAMAAQkAAMKAAA0AAAAA.Loricarvonri:BAAALgAECgUJBQAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAAALgAECgcJDwAAAA==.Lunarheals:BAABLgAECn8ZAAIXAAYJ5RlbDgC9AQAXAAYJ5RlbDgC9AQAAAA==.Lunasong:BAABLgAECn8UAAIQAAYJ/AXYRwD6AAAQAAYJ/AXYRwD6AAAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyulon:BAABLgAECn8UAAIPAAYJHRgQEgCNAQAPAAYJHRgQEgCNAQAAAA==.',
Me='Melikefire:BAABLgAECn8bAAIYAAgJaxm+AAAqAgAYAAgJaxm+AAAqAgAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEgAAAA==.Monkjimothy:BAABLgAECn8ZAAQVAAcJIh/NDgCiAQAVAAYJfxzNDgCiAQAZAAUJ3R7kNQBIAQAPAAIJdAomXgBVAAAAAA==.Monko:BAAALgAECgEJAQABLgAFFAUJEwANAHckAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECgUJCQAAAA==.Mortius:BAAALgADCgYJBwAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAUJCwAWALcWAA==.',
Od='Odinsknight:BAAALgAECgQJBwAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECgUJCQAAAA==.',
Ph='Phreek:BAAALgAECgcJEwAAAA==.',
Po='Pookie:BAAALgADCgYJBgAAAA==.Portius:BAAALgADCggJDAAAAA==.Pouyan:BAABLgAECn8eAAINAAgJzRVwGgCsAQANAAgJzRVwGgCsAQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn8oAAMOAAgJXQ54DQB/AQAOAAgJKA54DQB/AQAaAAQJYAyvHgChAAAAAA==.Racinette:BAACLgAFFH8OAAIBAAQJYCPbBAClAQABAAQJYCPbBAClAQAuAAQKfxoAAgEACQn7JL0FABADAAEACQn7JL0FABADAAAA.',
Re='Rebexha:BAAALgAECgQJBwAAAA==.Relvanas:BAAALgAECgUJDQAAAA==.',
Ri='Riverside:BAAALgAECgYJBQAAAA==.',
Sa='Saelesth:BAAALgAECgUJCQAAAA==.Sambie:BAABLgAECn8UAAIQAAYJogIkXgCvAAAQAAYJogIkXgCvAAAAAA==.',
Sc='Scantron:BAAALgAECgIJAgAAAA==.Scrappycocco:BAAALgAECgIJBAAAAA==.Scuffedbones:BAAALgAFFAEJAQAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAEJAQAHAAAAAA==.Scuffedfaith:BAAALgAECggJEgABLgAFFAEJAQAHAAAAAA==.',
Se='Sefyra:BAAALgAECgQJDAAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgUJBQAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgQJBAAAAA==.Snolo:BAAALgAECgUJDQAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAEJAQAHAAAAAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAECgQJBQABLgAFFAYJGgACAO4jAA==.Splux:BAAALgAECgMJAwAAAA==.',
St='Starsky:BAAALgADCgQJBAAAAA==.Strangewood:BAABLgAECn8tAAMNAAgJ6hVSRgCIAQANAAcJrBNSRgCIAQAJAAgJUAqmFABeAQAAAA==.',
Su='Sugarhzopurp:BAAALgAECgIJAwAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgADCgYJBgAAAA==.',
Th='Thala:BAAALgADCgUJBQAAAA==.Thunderfnk:BAAALgAECgcJEAAAAA==.',
Tr='Trickydice:BAAALgAECgQJBAAAAA==.',
Ty='Tysreaper:BAABLgAECn8XAAMCAAcJjhN8XACzAQACAAcJlRJ8XACzAQAEAAMJcQ/4GACzAAAAAA==.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8UAAITAAYJ5yEBGwDoAQATAAYJ5yEBGwDoAQAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQANACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn8lAAMTAAgJZSC6CQCDAgATAAgJZSC6CQCDAgAbAAIJOhkyGgCQAAAAAA==.',
Wu='Wu:BAABLgAECn8VAAIZAAgJ2Q8kEAB7AQAZAAgJ2Q8kEAB7AQABLgAECggJIQACAHYfAA==.',
Xe='Xelagos:BAAALgADCgEJAQABLgAECggJIQACAHYfAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAABLgAECn8jAAIWAAgJRRJeDADCAQAWAAgJRRJeDADCAQAAAA==.',
Zi='Zingispingus:BAABLgAECn8WAAIJAAcJ/wbwSwD6AAAJAAcJ/wbwSwD6AAAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCggJBgABLgAECgQJBwAHAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgUJBQAAAA==.',
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

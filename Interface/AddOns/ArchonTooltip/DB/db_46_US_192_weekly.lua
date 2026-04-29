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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Mage-Frost','DeathKnight-Unholy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','DemonHunter-Vengeance','Warrior-Arms','Paladin-Retribution','Priest-Holy','Mage-Fire','Evoker-Augmentation',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-04-24',data={Al='Alannaria:BAAALgADCgQJBgAAAA==.Alaris:BAAALgAECgQJBAABLgAFFAMJCgABAD0iAA==.Alex:BAAALgAECggJCgABLgAECggJIQACAHYfAA==.Alexw:BAABLgAECn8hAAQCAAcJdh+/DgCcAQACAAcJCBy/DgCcAQADAAQJIBm+JQAwAQAEAAQJXyFHEAApAQAAAA==.',
Au='Audrey:BAAALgAECggJEQAAAA==.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAAALgAECgQJCQABLgAECggJHQAFAMUTAA==.Bat:BAAALgAECgEJAQAAAA==.',
Be='Beautieful:BAAALgADCgYJCwAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Borgor:BAABLgAECn8lAAIGAAgJ2x8OGwDbAgAGAAgJ2x8OGwDbAgAAAA==.',
Br='Braggie:BAAALgADCgIJAgAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAAALgAECgYJDgAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Chaoticka:BAAALgADCgcJAwAAAA==.Cheri:BAABLgAECn8bAAIHAAgJbhefGwAlAgAHAAgJbhefGwAlAgAAAA==.',
Co='Codh:BAAALgADCgUJBQABLgAECgUJCAAIAAAAAA==.Codum:BAAALgAECgUJCAAAAA==.',
Da='Dackosaur:BAAALgAECgYJDgAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgADCgYJBgAAAA==.Danekriste:BAAALgAECgYJEQAAAA==.Darkenedone:BAACLgAFFH8LAAIJAAQJaxtOAgA8AQAJAAQJaxtOAgA8AQAuAAQKfxcAAwkACAmVGzYQAAgCAAkACAmVGzYQAAgCAAYAAgkPEqYUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECgEJAQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAIAAAAAA==.Demono:BAABLgAECn8WAAIKAAYJExc+XgCGAQAKAAYJExc+XgCGAQABLgAFFAUJDgALALsjAA==.',
Do='Doggx:BAAALgADCgIJAgAAAA==.',
Dr='Drfrangelico:BAAALgAECgYJCQAAAA==.Druido:BAACLgAFFH8OAAILAAUJuyNIAQARAgALAAUJuyNIAQARAgAuAAQKfykAAwsACQm8JS4AAO8DAAsACQm8JS4AAO8DAAcABAnKG1o5AFIBAAAA.Drunkmonk:BAAALgAECgQJBAAAAA==.',
Ds='Ds:BAABLgAECn8iAAIMAAgJnSMoAQAnAwAMAAgJnSMoAQAnAwAAAA==.',
Du='Dumdum:BAAALgADCgcJEAAAAA==.',
En='Enjoyby:BAAALgAECgYJDwAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAYJFAACACYiAA==.',
Fr='Frankßuck:BAAALgAECgYJEwAAAA==.Friarstrange:BAAALgAECgMJAwAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAILAAYJHiH+KQAKAgALAAYJHiH+KQAKAgAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgcJFgANAHIcAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8UAAIOAAgJfhDsUgDoAQAOAAgJfhDsUgDoAQAAAA==.Harakki:BAAALgAECgYJDgAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.',
Ho='Holyroran:BAAALgAECgYJEwAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
Ic='Icdeadpeeple:BAAALgAECgQJBwAAAA==.Icytouch:BAAALgAECgMJAwAAAA==.',
Il='Illijim:BAAALgAECgEJAQABLgAECgcJEwAIAAAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgADCgYJBgAAAA==.Jellybeanrez:BAAALgAECgYJDwAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgYJDQAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAAALgAECgcJEAAAAA==.',
Ke='Keysbricked:BAAALgAECgMJAwABLgAECgcJEAAIAAAAAA==.',
Ki='Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kreiger:BAAALgADCgUJCQAAAA==.Kritz:BAAALgAECgEJAgAAAA==.',
La='Laine:BAABLgAECn8VAAIPAAYJshuFHwDlAQAPAAYJshuFHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Lo='Lockstar:BAAALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8UAAQCAAYJJiI6AAAJAgACAAYJJiI6AAAJAgAEAAEJAABdBABbAAADAAEJnQ2RFQBTAAAuAAQKfyMAAwIACQm3Is0EAG4DAAIACQm3Is0EAG4DAAMAAQkAALyAAA0AAAAA.Loricarvonri:BAAALgAECgUJBQAAAA==.Love:BAAALgAECgMJAwAAAA==.',
Lu='Luciena:BAAALgAECgYJCAAAAA==.Lunarheals:BAAALgAECgYJEwAAAA==.Lunasong:BAAALgAECgYJDgAAAA==.Luxury:BAAALgAECgMJAwAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyulon:BAAALgAECgYJDgAAAA==.',
Me='Melikefire:BAABLgAECn8XAAIQAAgJEBeDAADZAQAQAAgJEBeDAADZAQAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgYJDAAAAA==.Monkjimothy:BAAALgAECgcJEwAAAA==.Monko:BAAALgAECgEJAQABLgAFFAUJDgALALsjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECgQJBAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAQJBwARAFINAA==.',
Od='Odinsknight:BAAALgAECgQJBwAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECgQJBAAAAA==.',
Ph='Phreek:BAAALgAECgcJEQAAAA==.',
Po='Pookie:BAAALgADCgYJBgAAAA==.Portius:BAAALgADCggJDAAAAA==.Pouyan:BAABLgAECn8YAAILAAgJsBV3DACMAQALAAgJsBV3DACMAQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn8hAAIMAAgJbwx3DQB/AQAMAAgJbwx3DQB/AQAAAA==.Racinette:BAACLgAFFH8KAAIBAAMJPSIgBAA3AQABAAMJPSIgBAA3AQAuAAQKfxgAAgEACAl7JMEFABADAAEACAl7JMEFABADAAAA.',
Re='Rebexha:BAAALgAECgQJBAAAAA==.Relvanas:BAAALgAECgMJBgAAAA==.',
Ri='Riverside:BAAALgAECgYJBAAAAA==.',
Sa='Saelesth:BAAALgAECgQJBAAAAA==.Sambie:BAAALgAECgYJDgAAAA==.',
Sc='Scantron:BAAALgADCgcJBwAAAA==.Scrappycocco:BAAALgAECgEJAQAAAA==.Scuffedbones:BAAALgAECgcJCAABLgAECggJEgAIAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAECggJEgAIAAAAAA==.Scuffedfaith:BAAALgAECggJEgAAAA==.',
Se='Sefyra:BAAALgAECgQJBwAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgUJBQAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgQJBAAAAA==.Snolo:BAAALgAECgMJBgAAAA==.Snowyrose:BAAALgAECgMJAwABLgAECggJJQAGANsfAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAECgMJBAABLgAFFAYJFAACACYiAA==.Splux:BAAALgAECgMJAwAAAA==.',
St='Starsky:BAAALgADCgMJAwAAAA==.Strangewood:BAABLgAECn8mAAMLAAgJ8xFKRgCIAQALAAcJZg9KRgCIAQAHAAcJ0AmUCwAzAQAAAA==.',
Su='Sugarhzopurp:BAAALgADCgUJBQAAAA==.Summerss:BAAALgADCgcJBwAAAA==.',
Th='Thala:BAAALgADCgUJBQAAAA==.Thunderfnk:BAAALgAECgcJEAAAAA==.',
Tr='Trickydice:BAAALgAECgQJBAAAAA==.',
Ty='Tysreaper:BAABLgAECn8XAAMCAAcJjhN9XACzAQACAAcJlRJ9XACzAQAEAAMJcQ/5GACzAAAAAA==.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAAALgAECgYJDgAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgADCgIJAgABLgAECgYJFQALACAjAA==.Vonbane:BAAALgADCgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJDAAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn8ZAAIOAAYJTB9FDgC3AQAOAAYJTB9FDgC3AQAAAA==.',
Wu='Wu:BAAALgAECgcJDQABLgAECggJIQACAHYfAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAABLgAECn8eAAIRAAgJmA+bBwB1AQARAAgJmA+bBwB1AQAAAA==.',
Zi='Zingispingus:BAABLgAECn8WAAIHAAcJ/wbsSwD6AAAHAAcJ/wbsSwD6AAAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCggJBgABLgAECgQJBAAIAAAAAA==.',
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

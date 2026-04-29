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

local lookup = {'Druid-Restoration','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Paladin-Protection','Evoker-Devastation','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Paladin-Holy','Warrior-Protection','Paladin-Retribution','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-04-24',data={Al='Allä:BAAALgAECgYJBgAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAAALgAECgEJAgAAAA==.',
As='Asecretbear:BAABLgAECn8lAAIBAAgJ4Ru8FwB5AgABAAgJ4Ru8FwB5AgAAAA==.Ashvana:BAABLgAECn8kAAICAAgJ7CFqCAD4AQACAAgJ7CFqCAD4AQAAAA==.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8XAAMDAAYJNxX4AgBGAQADAAQJoxb4AgBGAQAEAAIJbQjICgCZAAAuAAQKfx8AAwMACQl4IZgDAGkDAAMACQl4IZgDAGkDAAQAAQnyBnSoACYAAAAA.',
Ba='Balanced:BAACLgAFFH8VAAIFAAYJLxYvAQDRAQAFAAYJLxYvAQDRAQAuAAQKfx4AAwUACQmCIO8DADQDAAUACQmCIO8DADQDAAYABgn2G2QcAPgBAAEuAAQKCAkIAAcAAAAA.',
Be='Berserkr:BAAALgADCgcJEwAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradrian:BAAALgAFFAIJAwAAAA==.',
Ch='Chainéd:BAAALgAECgIJAgABLgAECggJHwAIAJwjAA==.Choco:BAAALgAECgkJDQAAAA==.Chodemage:BAAALgADCgcJCwAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAECggJHwAJAFsjAA==.Crazy:BAAALgAECgEJAQAAAA==.Creme:BAABLgAECn8bAAIDAAgJqRqWBQC9AQADAAgJqRqWBQC9AQAAAA==.',
Cy='Cynestrya:BAABLgAECn8eAAIKAAgJ1hcVAwDYAQAKAAgJ1hcVAwDYAQAAAA==.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAAALgAECgYJDwAAAA==.Depsesh:BAAALgADCgYJCgAAAA==.Deralan:BAAALgAECgcJEgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8XAAILAAkJUhx7DgDgAgALAAkJUhx7DgDgAgAAAA==.Dominatus:BAAALgAECgQJCwAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAAALgAECgcJEAAAAA==.Faenghorn:BAAALgAECgQJBQABLgAECgcJEAAHAAAAAA==.Fanah:BAAALgADCgYJBgABLgAECgUJDAAHAAAAAA==.',
Fe='Fearmonger:BAAALgADCgYJBgAAAA==.Felora:BAAALgADCgIJAgAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.',
Fu='Fujitroll:BAAALgADCgcJBQAAAA==.Furuion:BAAALgAECgYJEgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAECggJHgAMAOcVAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindëlwald:BAABLgAECn8eAAINAAgJURbECwANAgANAAgJURbECwANAgABLgAFFAIJAwAHAAAAAA==.',
Gu='Guac:BAAALgAECgQJBAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgUJDAAHAAAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8XAAMMAAYJRiKSAADyAQAMAAYJ3SGSAADyAQAOAAIJphn/BQCxAAAuAAQKfx4AAwwACQlhI4cBAK4DAAwACQk/I4cBAK4DAA4ABwmgJdkFAJsCAAAA.Ishmonk:BAABLgAECn8hAAMGAAgJ5CEICgDXAgAGAAcJeiQICgDXAgAPAAgJNxxODwCkAgABLgAFFAYJFwAMAEYiAA==.',
Jc='Jcole:BAAALgAECgYJCAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Jon:BAABLgAECn8cAAIQAAgJiRzYCwDzAQAQAAgJiRzYCwDzAQAAAA==.',
Ka='Kaivasyr:BAAALgAECgQJBgAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgQJBAAAAA==.',
Ke='Kealee:BAAALgAECgMJAwAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Kp='Kpop:BAAALgADCgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8FAAIQAAMJewR3FQDbAAAQAAMJewR3FQDbAAAuAAQKfxoAAxAABwnAE/KNALcBABAABwm2E/KNALcBABEABAnqDOsPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMJAAYJLwW7mgDkAAAJAAYJLwW7mgDkAAASAAEJSwGkfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8YAAIJAAcJGBeyEQB1AQAJAAcJGBeyEQB1AQAAAA==.',
Li='Lifemonk:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Lifepriest:BAAALgAECgEJAQAAAA==.Lifetide:BAAALgAECgYJDgAAAA==.Lifevoid:BAAALgADCgMJAwABLgAECgEJAQAHAAAAAA==.Littletop:BAABLgAECn8UAAITAAgJ0Ac6AwBAAQATAAgJ0Ac6AwBAAQAAAA==.',
Lo='Lostfaith:BAAALgAECgYJEAAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8eAAICAAgJuQiBHwAjAQACAAgJuQiBHwAjAQAAAA==.Malex:BAAALgAECggJCAAAAA==.Malrien:BAABLgAECn8bAAMDAAgJYxxoGABSAgADAAcJmx1oGABSAgAEAAcJ4RFkQgB3AQABLgAECggJCAAHAAAAAA==.Marselli:BAAALgAECgYJBwAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn8eAAIUAAgJZgljDAAnAQAUAAgJZgljDAAnAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAAALgAECgYJEwAAAA==.',
No='Norcaine:BAAALgADCgYJBgAAAA==.',
Ny='Nycteria:BAAALgAECgUJBgAAAA==.',
Om='Omgimaburger:BAAALgAECgQJCAAAAA==.',
Pa='Pachuuwas:BAAALgADCgIJAgAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8eAAIQAAgJGx09BQBiAgAQAAgJGx09BQBiAgAAAA==.',
Pe='Pepe:BAABLgAECn8fAAMIAAgJnCOaBgAkAwAIAAgJ5yKaBgAkAwAKAAYJthsxFACCAQAAAA==.',
Ph='Phatt:BAAALgAECgQJBgAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAABLgAECn8hAAIEAAgJvyGTCQDfAgAEAAgJvyGTCQDfAgAAAA==.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAAALgAECgQJDAAAAA==.Raghnoll:BAABLgAECn8VAAIVAAYJIw6zTgA+AQAVAAYJIw6zTgA+AQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAABLgAECn8eAAIWAAgJvwy2BwAZAQAWAAgJvwy2BwAZAQAAAA==.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgADCgUJCAABLgAECgcJFgAQAAckAA==.Sartorius:BAAALgAECgYJDQAAAA==.Satiate:BAAALgADCgUJDgAAAA==.',
Sc='Scarthan:BAAALgAECgYJEQAAAA==.Sciel:BAABLgAECn8VAAIDAAcJ9ByNFAB6AgADAAcJ9ByNFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgADCgcJEQAAAA==.Senpåi:BAAALgADCgEJAgABLgAECggJIQACAGAjAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8UAAIGAAgJTgf7NABNAQAGAAgJTgf7NABNAQAAAA==.',
Si='Sizzlesham:BAAALgAECgMJAwAAAA==.',
So='Sojaslim:BAAALgAECgcJDQAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJBgAAAA==.',
Su='Supanegroxy:BAAALgAECgEJAQAAAA==.',
Ta='Tankhugs:BAAALgAECgMJAwABLgAECggJHgAQABsdAA==.Tarias:BAAALgADCgMJBAAAAA==.Tasty:BAABLgAECn8kAAIEAAgJeiITAQDLAgAEAAgJeiITAQDLAgAAAA==.',
To='Topology:BAAALgAECgEJAQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Un='Unrealleet:BAABLgAECn8WAAIXAAgJ8QrwcACaAQAXAAgJ8QrwcACaAQAAAA==.',
Va='Vaipara:BAAALgADCgcJCgAAAA==.',
Vi='Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8aAAMYAAcJEx1IFQAzAgAYAAcJ0hxIFQAzAgAZAAYJ0RWOIACPAQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wr='Wrathchld:BAAALgADCgMJBAAAAA==.',
Xa='Xalatath:BAAALgAECgQJBAAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
['Àl']='Àlilith:BAAALgAECgcJEAAAAA==.',
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

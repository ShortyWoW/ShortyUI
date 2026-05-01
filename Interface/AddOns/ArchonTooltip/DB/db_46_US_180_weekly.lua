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

local lookup = {'Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Feral','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Shaman-Enhancement','Druid-Restoration','Shaman-Restoration','Monk-Windwalker','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-05-01',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAAALgAECggJDQAAAA==.Allinaa:BAAALgAECggJEwAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAABLgAECn8oAAICAAkJKgiuEAC1AQACAAkJKgiuEAC1AQAAAA==.',
Ar='Arlyx:BAACLgAFFH8HAAMDAAMJ3Q9wLgDqAAADAAMJ3Q9wLgDqAAAEAAEJmw5XFQBUAAAuAAQKfxUABAMACAkmGL5tAIUBAAMABQlSGr5tAIUBAAQAAwm3EoNHAJgAAAUAAgnoBzEfAHcAAAAA.Arnwaz:BAAALgAECgUJCAAAAA==.Arthuria:BAAALgAECgYJCAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAABLgAECn8aAAIGAAcJdx2GPgArAgAGAAcJdx2GPgArAgAAAA==.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Beefis:BAAALgAECgQJCAAAAA==.Beenjuicin:BAAALgAFFAEJAQAAAA==.Berfomat:BAABLgAECn8nAAIHAAkJ1CFfAAAHAwAHAAkJ1CFfAAAHAwAAAA==.',
Bi='Bingchilling:BAACLgAFFH8NAAIIAAUJbAzaCgBrAQAIAAUJbAzaCgBrAQAuAAQKfyAAAggACQnsGmUMAOMCAAgACQnsGmUMAOMCAAAA.',
Bj='Bjorn:BAAALgAECgYJCQAAAA==.',
Bl='Bloomyvfd:BAAALgAECgYJCwAAAA==.',
Bo='Bonniebadass:BAAALgAECgQJBwAAAA==.Bottle:BAAALgAECgEJAQAAAA==.Boxxylove:BAAALgAECgEJAQAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAAALgAECgYJDwAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8cAAIJAAcJiRnVZgAJAgAJAAcJiRnVZgAJAgAAAA==.Cavalis:BAABLgAECn8oAAQDAAkJ6hgjFgD0AQADAAgJQxcjFgD0AQAFAAQJTRizEgABAQAEAAIJsB/MGABfAAAAAA==.',
Ce='Ceedh:BAAALgAFFAEJAQAAAA==.Ceejr:BAACLgAFFH8WAAMCAAYJxyKhAQDoAQACAAUJ5iKhAQDoAQAKAAIJJSIHCwDLAAAuAAQKfyAAAgIACQlpJSIBAMUDAAIACQlpJSIBAMUDAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgABAAAAAA==.Chillum:BAAALgAECgIJAgABLgAECggJHAALACgeAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAABLgAFFH8FAAIMAAIJiRirGACoAAAMAAIJiRirGACoAAAAAA==.',
Da='Damnskippy:BAAALgAECgMJAwAAAA==.Dannÿ:BAAALgAECgYJDwAAAA==.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAABLgAECn8gAAINAAgJXxmvIgCTAQANAAgJXxmvIgCTAQAAAA==.Darkstar:BAAALgADCgUJBQAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8hAAIOAAkJGxVKCAAyAgAOAAkJGxVKCAAyAgAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJBgABLgAECgcJCAABAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwABAAAAAA==.Dontah:BAAALgADCgcJBwABLgAECgkJIAAPAIwgAA==.Doomward:BAAALgAECgYJDwAAAA==.Dorien:BAABLgAECn8gAAIPAAkJjCCiAAAQAwAPAAkJjCCiAAAQAwAAAA==.',
Dr='Drachilly:BAABLgAECn8cAAQLAAgJKB6RCwDPAQAQAAYJ9x02EADYAQALAAgJjR2RCwDPAQARAAEJCgJgJgAbAAAAAA==.Dragnar:BAABLgAECn8hAAINAAgJlA3nPQC3AQANAAgJlA3nPQC3AQAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Fa='Faewryn:BAAALgAECggJCQAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAABLgAECn8cAAIMAAgJySFlCgDlAQAMAAgJySFlCgDlAQAAAA==.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Fireserpent:BAAALgAECgYJDwAAAA==.Firstblood:BAAALgAECgUJBwAAAA==.Fishnchimps:BAAALgAFFAMJAwAAAA==.',
Ga='Gaiserik:BAABLgAECn8YAAISAAYJOx/CBQDJAQASAAYJOx/CBQDJAQAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgABAAAAAA==.Garlictoast:BAAALgAECgIJBAAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECgEJAQAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJAwABAAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAAALgAECgcJEgAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8XAAITAAYJGiLfAwD+AQATAAYJGiLfAwD+AQAAAA==.',
Ha='Havibonespur:BAAALgAECgYJEQAAAA==.',
He='Healir:BAAALgAECgYJDgAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJCwAUAGoPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMVAAkJ1hVxEADsAQAVAAkJ1hVxEADsAQAWAAUJ3RW5LgBXAQAAAA==.',
Ho='Holydeath:BAAALgAECgYJCwAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwACACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAECgMJAwAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8eAAIGAAgJ7iVfBQB3AwAGAAgJ7iVfBQB3AwAAAA==.Jarlan:BAACLgAFFH8HAAISAAMJ+CBPBQAxAQASAAMJ+CBPBQAxAQAuAAQKfyEAAhIACAkMIrsBACMDABIACAkMIrsBACMDAAAA.Jarlhun:BAAALgAECgYJEQABLgAFFAMJBwASAPggAA==.',
Je='Jellous:BAABLgAECn8mAAMWAAkJgheNEwA4AgAWAAgJeRiNEwA4AgAVAAkJaRTdMwAqAgAAAA==.Jethereal:BAAALgADCgcJBwABLgAECgkJJgAWAIIXAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8bAAIXAAgJPBbBCwAbAgAXAAgJPBbBCwAbAgAAAA==.Kevamin:BAAALgAECgUJCQAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECgYJCAAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAAALgAECggJDgAAAA==.',
Le='Learned:BAAALgAECgcJDAAAAA==.Leo:BAAALgAECgcJEgAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAAALgAECggJDgAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8nAAIYAAgJ4x8BAgBmAgAYAAgJ4x8BAgBmAgAAAA==.',
Lo='Logical:BAAALgADCgUJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgADCgEJAQABLgAFFAMJBwADAN0PAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAECggJHAAMAMkhAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIZAAcJpxSlHACbAQAZAAcJpxSlHACbAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAABLgAECn8aAAIaAAcJJhkPLQDWAQAaAAcJJhkPLQDWAQAAAA==.',
Mc='Mcchungus:BAAALgAECgQJBwAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAAALgAECgYJCgAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAABLgAECn8jAAIFAAkJ5xS/AABGAgAFAAkJ5xS/AABGAgAAAA==.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJKQAbAAIjAA==.',
Mo='Mooage:BAACLgAFFH8GAAIJAAIJYiC1MwDLAAAJAAIJYiC1MwDLAAAuAAQKfywAAgkACAnGJTEFAOkCAAkACAnGJTEFAOkCAAAA.Morewyn:BAABLgAECn8YAAINAAgJ1A+/MwDgAQANAAgJ1A+/MwDgAQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAAALgAECgQJCQABLgAFFAIJBQASANcQAA==.Nidhogg:BAAALgADCgcJBwABLgAECggJGAAaAB8dAA==.Nisara:BAAALgAECgYJCgAAAA==.',
No='Noellie:BAAALgAECgEJAQAAAA==.Noobdestroya:BAAALgAECgQJDQAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8YAAMaAAgJHx2HIgAQAgAaAAYJKR2HIgAQAgAUAAYJSxnJSAAkAQAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAMJCwAcAGoUAA==.',
Pa='Painfull:BAABLgAECn8cAAIVAAgJAh1FKwBTAgAVAAgJAh1FKwBTAgAAAA==.Pants:BAAALgADCggJAwAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgABAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAAALgAECgcJDwAAAA==.Phizz:BAAALgAFFAQJBAAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJCwAVAIkQAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgABAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8UAAIdAAgJRSHxAACfAgAdAAgJRSHxAACfAgAAAA==.Pumpkinspice:BAAALgADCgMJAgAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgYJEQABAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAECggJHAADAK0RAA==.',
Ro='Rotdaddy:BAABLgAECn8UAAIcAAcJPBSFLQCVAQAcAAcJPBSFLQCVAQAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAAALgAECggJDQAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shinra:BAAALgADCgEJAQAAAA==.Shore:BAAALgAECggJDAAAAA==.Shrekw:BAAALgAECgUJCwAAAA==.Shuralya:BAACLgAFFH8FAAMGAAMJ/AZIJQDYAAAGAAMJ/AZIJQDYAAAXAAIJhQhdFwCKAAAuAAQKfy0AAwYACQkiGxkHAKkCAAYACQkiGxkHAKkCABcACAkbFn4gABcCAAAA.',
Si='Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMeAAkJBA5qGgB+AQAeAAkJBA5qGgB+AQAfAAEJMgHlOwEbAAAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAAALgAECgUJDQAAAA==.Stradynia:BAAALgAECgYJCQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.Stócky:BAAALgAECgUJCwAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAABLgAECn8dAAIcAAgJqhn8DQCLAQAcAAgJqhn8DQCLAQAAAA==.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJCQAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgIJAwABLgAECgMJAwABAAAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAECgUJBgABLgAFFAMJAwABAAAAAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAAALgAECgcJEwAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgMJAwAAAA==.',
To='Toospooky:BAAALgAECgEJAQAAAA==.Toyboy:BAAALgADCgEJAQAAAA==.',
Tr='Triage:BAAALgAECgYJEwAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAABLgAECn8oAAMgAAkJUhb4AQACAgAgAAgJvxT4AQACAgAfAAgJ6BBnKgCSAQAAAA==.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAECggJIgAfALchAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8oAAIYAAkJByBsAAAGAwAYAAkJByBsAAAGAwAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJCQABAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.',
Vo='Voidomo:BAAALgAECggJEAAAAA==.',
Wa='Walden:BAAALgAECgYJDwAAAA==.Waterlance:BAAALgAECgEJAgAAAA==.',
Wi='Wisecraic:BAAALgADCgYJBgAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8LAAIcAAMJahTiDQAOAQAcAAMJahTiDQAOAQAuAAQKfyIAAhwACQlIHbQGACQDABwACQlIHbQGACQDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECgcJCwAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgEJAQAAAA==.',
Za='Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8UAAIhAAcJUxQEAwBsAQAhAAcJUxQEAwBsAQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.',
Ze='Zeale:BAABLgAECn8cAAIDAAgJrRFxhgBNAQADAAgJrRFxhgBNAQAAAA==.Zenedict:BAAALgAECgUJDQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
['Áç']='Áçe:BAAALgADCgMJAwAAAA==.',
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

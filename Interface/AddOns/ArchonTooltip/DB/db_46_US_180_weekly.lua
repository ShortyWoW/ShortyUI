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

local lookup = {'Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Hunter-BeastMastery','DeathKnight-Unholy','Monk-Mistweaver','Hunter-Survival','Evoker-Devastation','Monk-Brewmaster','Shaman-Elemental','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Druid-Restoration','Shaman-Restoration','Monk-Windwalker','Rogue-Subtlety','Paladin-Holy','DeathKnight-Blood',}
local provider = {region='US',realm='Rivendare',name='US',type='weekly',zone=46,date='2026-04-24',data={Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAAALgAECggJDQAAAA==.Allinaa:BAAALgAECggJEwAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAABLgAECn8fAAICAAgJ0gceCwBuAQACAAgJ0gceCwBuAQAAAA==.Antilight:BAAALgADCgQJBAAAAA==.',
Ar='Arlyx:BAABLgAECn8UAAQDAAgJyRe4bQCFAQADAAUJ0Bm4bQCFAQAEAAMJtxKARwCYAAAFAAIJ6AcyHwB3AAAAAA==.Arnwaz:BAAALgAECgUJCAAAAA==.Arthuria:BAAALgAECgYJCAAAAA==.',
As='Aslan:BAAALgADCgQJBQAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAABLgAECn8aAAIGAAcJdx2LPgArAgAGAAcJdx2LPgArAgAAAA==.Bayside:BAAALgAECgYJDQAAAA==.',
Be='Beefis:BAAALgAECgIJBAAAAA==.Beenjuicin:BAAALgAECgIJAgAAAA==.Berfomat:BAABLgAECn8eAAIHAAgJ8yD7AgD2AgAHAAgJ8yD7AgD2AgAAAA==.',
Bi='Bingchilling:BAACLgAFFH8NAAIIAAUJbAzQCgBrAQAIAAUJbAzQCgBrAQAuAAQKfyAAAggACQnsGmIMAOMCAAgACQnsGmIMAOMCAAAA.',
Bj='Bjorn:BAAALgAECgYJCQAAAA==.',
Bl='Bloomyvfd:BAAALgAECgMJBQAAAA==.',
Bo='Bonniebadass:BAAALgAECgMJAwAAAA==.Bottle:BAAALgAECgEJAQAAAA==.Boxxylove:BAAALgAECgEJAQAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAAALgAECgUJCQAAAA==.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8YAAIJAAcJQRjbZgAJAgAJAAcJQRjbZgAJAgAAAA==.Cavalis:BAABLgAECn8fAAQDAAgJfBaNEQCEAQADAAcJ/xONEQCEAQAFAAQJTRizEgABAQAEAAIJix+cDABeAAAAAA==.',
Ce='Ceejr:BAACLgAFFH8TAAMCAAYJ4CCsAACPAQACAAUJ5iKsAACPAQAKAAEJyRjEBgBaAAAuAAQKfyAAAgIACQlpJSIBAMUDAAIACQlpJSIBAMUDAAAA.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgABAAAAAA==.Chillum:BAAALgAECgIJAgABLgAECgcJGgALAC0dAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgMJCAAAAA==.',
Cr='Creativez:BAAALgAFFAIJBAAAAA==.',
Da='Damnskippy:BAAALgAECgMJAwAAAA==.Dannÿ:BAAALgAECgYJCgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAABLgAECn8eAAIMAAcJaRmBOADMAQAMAAcJaRmBOADMAQAAAA==.Darkstar:BAAALgADCgUJBQAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathrave:BAABLgAECn8fAAINAAgJtyFXEQAUAwANAAgJtyFXEQAUAwAAAA==.Deathroll:BAABLgAECn8ZAAIOAAgJmhCRCQBXAQAOAAgJmhCRCQBXAQAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJAwABLgAECgcJCAABAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwABAAAAAA==.Dontah:BAAALgADCgcJBwABLgAECggJFwAPAEAeAA==.Doomward:BAAALgAECgQJCgAAAA==.Dorien:BAABLgAECn8XAAIPAAgJQB7gAAB2AgAPAAgJQB7gAAB2AgAAAA==.',
Dr='Drachilly:BAABLgAECn8aAAMLAAcJLR32FQApAgALAAcJeRz2FQApAgAQAAYJ9x00EADYAQAAAA==.Dragnar:BAABLgAECn8fAAIMAAgJlA3wPQC3AQAMAAgJlA3wPQC3AQAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Fa='Faewryn:BAAALgAECggJCQAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAABLgAECn8aAAIRAAcJ5CHuEgB6AgARAAcJ5CHuEgB6AgAAAA==.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Fireserpent:BAAALgAECgYJDAAAAA==.Firstblood:BAAALgAECgUJBwAAAA==.Fishnchimps:BAAALgAECgcJDgAAAA==.',
Ga='Gaiserik:BAAALgAECgYJEgAAAA==.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgABAAAAAA==.Garlictoast:BAAALgAECgIJBAAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECgEJAQAAAA==.Gome:BAAALgADCgcJGwABLgAECgcJDgABAAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAAALgAECgYJCwAAAA==.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBgAAAA==.',
Gu='Gustabo:BAAALgAECgYJEQAAAA==.',
Ha='Havibonespur:BAAALgAECgYJCwAAAA==.',
He='Healir:BAAALgAECgYJDgAAAA==.Healmepls:BAAALgADCgYJBgABLgAFFAUJCgASAH8PAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAAALgAECgkJEwAAAA==.',
Ho='Holydeath:BAAALgAECgYJCwAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwACACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAECgMJAwAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8eAAIGAAgJ7iWJAQDDAgAGAAgJ7iWJAQDDAgAAAA==.Jarlan:BAABLgAECn8gAAITAAgJDCK6AQAjAwATAAgJDCK6AQAjAwAAAA==.Jarlhun:BAAALgAECgUJCwABLgAECggJIAATAAwiAA==.',
Je='Jellous:BAABLgAECn8oAAMUAAkJJhixCADoAQAVAAgJeRiOEwA4AgAUAAkJ8hOxCADoAQAAAA==.Jethereal:BAAALgADCgcJBwABLgAECgkJKAAUACYYAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.',
Ke='Ketharion:BAAALgAECgcJEwAAAA==.Kevamin:BAAALgAECgIJAwAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECgYJCAAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kurailos:BAAALgADCgIJAgAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAAALgAECggJDQAAAA==.',
Le='Learned:BAAALgAECgcJDAAAAA==.Leo:BAAALgAECgYJCwAAAA==.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAAALgAECgcJDAAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8gAAIWAAgJ4x8qBADfAgAWAAgJ4x8qBADfAgAAAA==.',
Lo='Logical:BAAALgADCgUJBgAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgADCgEJAQABLgAECggJFAADAMkXAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAECgcJGgARAOQhAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIXAAcJpxTCCgCsAQAXAAcJpxTCCgCsAQAAAA==.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAABLgAECn8aAAIYAAcJJhkPLQDWAQAYAAcJJhkPLQDWAQAAAA==.',
Mc='Mcchungus:BAAALgAECgEJAgAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAAALgAECgIJAwAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAABLgAECn8aAAIFAAgJjhS+AADdAQAFAAgJjhS+AADdAQAAAA==.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJJAAZAAIjAA==.',
Mo='Mooage:BAACLgAFFH8FAAIJAAIJYiCzMwDLAAAJAAIJYiCzMwDLAAAuAAQKfyQAAgkACAmNJRIMAGQDAAkACAmNJRIMAGQDAAAA.Morewyn:BAAALgAECggJEQAAAA==.Mozoh:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAAALgAECgQJBwABLgAECggJHgATAGUbAA==.Nidhogg:BAAALgADCgcJBwABLgAECggJFgAYAB8dAA==.Nisara:BAAALgAECgMJBAAAAA==.',
No='Noellie:BAAALgAECgEJAQAAAA==.Noobdestroya:BAAALgAECgQJCQAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8WAAMYAAgJHx2PIgAQAgAYAAYJKR2PIgAQAgASAAUJDRjASAAkAQAAAA==.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAMJCQAaAGoUAA==.',
Pa='Painfull:BAABLgAECn8gAAIUAAgJsRw9KwBTAgAUAAgJsRw9KwBTAgAAAA==.Pants:BAAALgADCggJAwAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgABAAAAAA==.',
Ph='Phakes:BAAALgAECgUJBwAAAA==.Phengzera:BAAALgAECgcJCwAAAA==.Phizz:BAAALgAECgUJCAAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAQJCQAUAIkQAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDQABAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAAALgAECggJDAAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDQAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgYJCwABAAAAAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwAAAA==.',
Ro='Rotdaddy:BAAALgAECgcJEgAAAA==.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAAALgAECggJDQAAAA==.',
Sa='Saintrandy:BAAALgADCgIJAgAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shinra:BAAALgADCgEJAQAAAA==.Shore:BAAALgAECggJCAAAAA==.Shrekw:BAAALgAECgQJBgAAAA==.Shuralya:BAABLgAECn8lAAMbAAkJ7Rd/IAAXAgAbAAgJGxZ/IAAXAgAGAAgJQxUYCAAJAgAAAA==.',
Si='Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8cAAMcAAgJog9tGgB+AQAcAAgJog9tGgB+AQANAAEJMgHUOwEbAAAAAA==.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAAALgAECgQJCAAAAA==.Stradynia:BAAALgAECgYJCQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.Stócky:BAAALgAECgQJBgAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAABLgAECn8aAAIaAAcJ+hn6HAAXAgAaAAcJ+hn6HAAXAgAAAA==.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgMJAwAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgIJAgAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgADCgMJAwABLgAECgcJDgABAAAAAA==.Tawna:BAAALgAECgEJAQAAAA==.',
Te='Tealan:BAAALgAECgcJEwAAAA==.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgADCggJDgABLgAECgIJAgABAAAAAA==.',
To='Toospooky:BAAALgAECgEJAQAAAA==.',
Tr='Triage:BAAALgAECgYJDwAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAABLgAECn8fAAINAAgJ6BBYDQCzAQANAAgJ6BBYDQCzAQAAAA==.',
Um='Umaydie:BAAALgAECgIJAgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAECggJHwANALchAA==.Unholylukers:BAAALgAECgEJAQAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8fAAIWAAgJhx+mAAB6AgAWAAgJhx+mAAB6AgAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgMJAwABAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.',
Vo='Voidomo:BAAALgAECggJDgAAAA==.',
Wa='Walden:BAAALgAECgQJCQAAAA==.Waterlance:BAAALgAECgEJAgAAAA==.',
Wi='Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8JAAIaAAMJahTjDQAOAQAaAAMJahTjDQAOAQAuAAQKfyIAAhoACQlIHbQGACUDABoACQlIHbQGACUDAAAA.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECgIJAgAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgADCgMJBAAAAA==.',
Za='Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAAALgAECgUJDQAAAA==.Zaida:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.',
Ze='Zeale:BAABLgAECn8bAAIDAAgJrRHgDwCSAQADAAgJrRHgDwCSAQAAAA==.Zenedict:BAAALgAECgQJCwAAAA==.',
['Áç']='Áçe:BAAALgADCgEJAQAAAA==.',
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

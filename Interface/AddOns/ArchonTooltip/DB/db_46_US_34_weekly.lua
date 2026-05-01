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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Priest-Discipline','Mage-Arcane','DemonHunter-Devourer','Evoker-Preservation','DemonHunter-Vengeance','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adamonious:BAAALgADCggJAwABLgAECggJEwABAAAAAA==.Adaware:BAAALgAECgMJAwAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgADCgcJDQAAAA==.',
Al='Alba:BAABLgAECn8WAAICAAgJ+Be7FQANAgACAAgJ+Be7FQANAgABLgAECgkJIQADAD4dAA==.Aletta:BAAALgADCgQJCwAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn8aAAIDAAcJ0g0JKQByAQADAAcJ0g0JKQByAQAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwAAAA==.',
Ar='Arianes:BAAALgAECgcJDgAAAA==.Arturias:BAAALgAECgcJEgAAAA==.',
At='Athenaowl:BAAALgAECgYJBwAAAA==.',
Au='Autofocus:BAAALgAECgYJEgAAAA==.',
Aw='Aweyna:BAAALgAECgYJCQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8FAAIEAAMJXg7UAgAGAQAEAAMJXg7UAgAGAQAuAAQKfykAAgQACAk0HzYBAGQCAAQACAk0HzYBAGQCAAAA.Ayasumi:BAAALgAECgEJAQAAAA==.',
Ba='Babaganoosh:BAAALgAECgQJBQAAAA==.Baoyue:BAAALgAECgUJBAABLgAECggJKQAFABQVAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Benmonk:BAAALgAECgIJAgAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAABLgAECn8iAAIGAAgJ6g5yEAC3AQAGAAgJ6g5yEAC3AQAAAA==.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn8fAAIHAAgJWhQCCgB0AQAHAAgJWhQCCgB0AQAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Boneski:BAAALgAECgQJCwAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAAALgAECgUJDgAAAA==.Brudiclad:BAABLgAECn8aAAQIAAcJihABEAAuAQAIAAcJVA0BEAAuAQAJAAIJzxHxUQB4AAAKAAQJRQew8QB2AAAAAA==.',
Bu='Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8WAAILAAgJ9gI/3AA6AQALAAgJ9gI/3AA6AQAAAA==.Calahan:BAABLgAECn8dAAICAAgJqRqeHQDYAQACAAgJqRqeHQDYAQAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chikostix:BAAALgAECgYJDgAAAA==.Christae:BAABLgAECn8XAAIMAAgJDxgUDQDSAQAMAAgJDxgUDQDSAQAAAA==.',
Cl='Clemêntine:BAAALgAECgYJBgAAAA==.Clydè:BAABLgAECn82AAMNAAgJbxczDACzAQANAAgJYxczDACzAQAOAAgJQBG9EgBzAQAAAA==.Cláncey:BAAALgAECgcJCwAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCAAAAA==.Cocytus:BAAALgADCgIJAgAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromised:BAABLgAECn8dAAIPAAcJNBtyBwDeAQAPAAcJNBtyBwDeAQAAAA==.Corelack:BAAALgAECggJDgAAAA==.',
Cr='Crwth:BAAALgADCgIJAgAAAA==.',
Cu='Curendae:BAABLgAECn8WAAIDAAcJrBR7JACJAQADAAcJrBR7JACJAQAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8NAAILAAUJPhnuHABZAQALAAUJPhnuHABZAQAuAAQKfxcAAgsACAmpGERMAFICAAsACAmpGERMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAAALgAECgUJEAAAAA==.',
De='Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Despair:BAAALgADCggJDgABLgAECgkJIQADAD4dAA==.',
Di='Dice:BAABLgAECn8cAAIQAAcJax6jAgBSAgAQAAcJax6jAgBSAgAAAA==.Disturbd:BAABLgAFFH8FAAMRAAQJ4QOgQQDDAAARAAMJ4QOgQQDDAAAHAAEJAACYJAAAAAAAAA==.Disturbian:BAAALgAFFAIJAwABLgAFFAQJBQARAOEDAA==.Dixierecht:BAABLgAECn8aAAISAAgJahl9CQA/AgASAAgJahl9CQA/AgAAAA==.',
Do='Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgQJBAAAAA==.Drvargas:BAAALgADCgcJAQAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
El='Elenestern:BAAALgAECggJDAAAAA==.Elmo:BAABLgAECn8VAAILAAYJxRPiWgAoAQALAAYJxRPiWgAoAQAAAA==.',
Em='Emryssa:BAAALgAECgMJBgAAAA==.',
Er='Erosis:BAACLgAFFH8FAAILAAMJcxyxLQATAQALAAMJcxyxLQATAQAuAAQKfyAAAgsACAmtIjoaAA4CAAsACAmtIjoaAA4CAAAA.',
Ez='Ezaratren:BAAALgAECgUJCQABLgAECggJDgABAAAAAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8FAAIKAAMJOBuzHQANAQAKAAMJOBuzHQANAQAuAAQKfyMAAwoACAlPIOQrAF8CAAoACAlPIOQrAF8CAAkABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8cAAMHAAgJcxYtDwAiAQARAAcJARYVYwDKAQAHAAgJWA0tDwAiAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAAALgAECgYJDgAAAA==.',
Fi='Fistofwayne:BAAALgAECgYJCgABLgAFFAMJBwARAF0fAA==.',
Ga='Gakopozy:BAAALgAECgYJCAAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIRAAMJuhEPJwD7AAARAAMJuhEPJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgADCgcJBwAAAA==.',
Gu='Guldán:BAAALgAECgYJCQAAAA==.',
Gw='Gwydre:BAACLgAFFH8IAAIHAAMJKhTYDQDFAAAHAAMJKhTYDQDFAAAuAAQKfxUAAgcACAnpHrkDABICAAcACAnpHrkDABICAAAA.',
Ha='Havran:BAAALgAECgMJAwABLgAECgkJNwATABIWAA==.Havrin:BAABLgAECn83AAMTAAkJEhaVDQCsAQATAAkJEhaVDQCsAQAUAAEJQhLcMQA7AAAAAA==.',
He='Headshots:BAABLgAECn8hAAIDAAkJPh1eFACTAgADAAkJPh1eFACTAgAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Ho='Holmie:BAAALgADCgkJCgAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8OAAIRAAUJkybkAwDNAQARAAUJkybkAwDNAQAuAAQKfy0AAxEACAkhJAEUAAMDABEACAmvIQEUAAMDAAcABwmjH4EGAMABAAAA.',
Hu='Huamulan:BAABLgAECn8hAAICAAgJsARnTwAeAQACAAgJsARnTwAeAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAECgcJHQALACEbAA==.Ibchilling:BAABLgAECn8dAAILAAcJIRsPIQDnAQALAAcJIRsPIQDnAQAAAA==.Ibcorrupted:BAAALgAECgUJCQABLgAECgcJHQALACEbAA==.',
Ic='Icarrus:BAABLgAECn8hAAIVAAgJaxn1FQAUAgAVAAgJaxn1FQAUAgABLgAECgYJFAARANIZAA==.Icarus:BAAALgADCgEJAQABLgAECgYJFAARANIZAA==.Icebone:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.',
Ig='Ignis:BAABLgAECn8UAAIRAAYJ0hmqMQBzAQARAAYJ0hmqMQBzAQAAAA==.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJCwAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwABAAAAAA==.',
Ja='Jackbfistn:BAAALgAECgYJDwAAAA==.Jaskim:BAAALgAECgIJAgAAAA==.',
Je='Jeses:BAAALgAECgEJAQAAAA==.',
Jo='Jolty:BAAALgADCggJCAABLgAFFAIJBwARAH8iAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAAALgAECgUJCQAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgABAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kahtonah:BAAALgADCgMJAwAAAA==.Kaltaan:BAABLgAECn8ZAAMWAAcJoSHwBABzAgAWAAcJoSHwBABzAgAMAAQJUh8ZPABKAQAAAA==.Karasan:BAAALgAECgcJDwAAAA==.Karenas:BAABLgAECn8VAAMLAAgJARmDVAA7AgALAAgJARmDVAA7AgAXAAIJ4QqYFgBmAAAAAA==.Karr:BAAALgAECgQJBQAAAA==.Kataraara:BAACLgAFFH8HAAIOAAQJRSDZAwCZAQAOAAQJRSDZAwCZAQAuAAQKfxcAAg4ACAntJOEEADwDAA4ACAntJOEEADwDAAAA.Katbeans:BAABLgAECn8ZAAMVAAcJUxyZDgC9AQAVAAcJUxyZDgC9AQAOAAQJpguLYgC4AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.',
Ke='Kelicemoon:BAABLgAECn8UAAMKAAYJwgd3bAC0AAAKAAYJfgV3bAC0AAAJAAUJSQeiSwCKAAAAAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn8xAAIYAAkJcwwnYACAAQAYAAkJcwwnYACAAQAAAA==.',
Ki='Kiara:BAACLgAFFH8GAAIZAAMJ7hdpDQD0AAAZAAMJ7hdpDQD0AAAuAAQKfyEAAhkACAnLH1QIALUCABkACAnLH1QIALUCAAAA.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgMJAwAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
La='Lahrnaon:BAAALgAECgcJDwAAAA==.Laxeron:BAAALgAECgYJEQAAAA==.',
Le='Leotherassy:BAAALgAECgEJAQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgQJBAAAAA==.',
Lo='Lotiel:BAAALgAECgMJBgAAAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMYAAYJPx0jUgCuAQAYAAUJoiEjUgCuAQAaAAEJswuhLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJDgAAAA==.',
Ma='Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAAALgAECgYJEQAAAA==.Mcfeast:BAAALgAECgYJEAAAAA==.',
Me='Medra:BAABLgAECn8XAAIGAAgJOROSFACQAQAGAAgJOROSFACQAQAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAAALgAECgYJEwAAAA==.',
Mo='Morar:BAAALgAECgIJAgAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Ni='Nightcat:BAAALgAECgEJAQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nixie:BAABLgAECn8cAAIbAAcJ2AZiNwD4AAAbAAcJ2AZiNwD4AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8JAAIPAAQJuwSIBQAbAQAPAAQJuwSIBQAbAQAuAAQKfxoAAg8ACAmQFi4eAM4BAA8ACAmQFi4eAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8FAAMKAAMJFBvXPQCuAAAKAAIJGxvXPQCuAAAJAAEJBhtXCwBdAAAuAAQKfyEAAwoACAmQIjoOADkCAAoABgkLIjoOADkCAAkABQm9HzsaAHsBAAAA.',
Ol='Oliiver:BAABLgAECn8YAAIDAAgJNx1mDAA9AgADAAgJNx1mDAA9AgAAAA==.',
Om='Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAABAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8YAAIYAAcJNyC/EwDMAQAYAAcJNyC/EwDMAQAAAA==.',
Pa='Panaceus:BAABLgAECn8mAAIZAAgJRyB+AQDiAgAZAAgJRyB+AQDiAgAAAA==.Paragon:BAAALgADCgkJCQABLgAFFAMJDAARAMMdAA==.Patron:BAAALgADCgEJAQAAAA==.',
Pe='Perennial:BAAALgAECgIJAgAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJCgAAAA==.Phrequency:BAEALgAECgQJCQABLgAECgYJCgABAAAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAUJDgARAJMmAA==.',
Pl='Playingwow:BAAALgAECgUJBQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8FAAIHAAMJ7AdaDwCsAAAHAAMJ7AdaDwCsAAAuAAQKfykAAgcACAlHG+YNAC8CAAcACAlHG+YNAC8CAAAA.',
Pr='Profang:BAAALgADCgUJAwAAAA==.',
Py='Pyrelic:BAABLgAFFH8GAAINAAUJNgq2CADqAAANAAUJNgq2CADqAAAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAMJCAAHACoUAA==.',
['Pö']='Pöncho:BAAALgADCgMJAwAAAA==.',
Qa='Qayllera:BAAALgADCgkJCQAAAA==.',
Qe='Qelcie:BAAALgADCgYJDAAAAA==.',
Qu='Quizet:BAAALgADCgYJCAAAAA==.',
Ra='Radkeem:BAAALgAECgYJBgABLgAECgYJDgABAAAAAA==.Raf:BAAALgAECgYJBwAAAA==.Rakeem:BAAALgAECgYJDgAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.',
Re='Redtoxin:BAAALgADCgYJAQAAAA==.Reilley:BAACLgAFFH8GAAIRAAMJYhrdNAD3AAARAAMJYhrdNAD3AAAuAAQKfx4AAhEACAlvIdUXAOwCABEACAlvIdUXAOwCAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAMJBgARAGIaAA==.Remorsa:BAAALgAECgUJDAAAAA==.Renni:BAABLgAECn8eAAIKAAYJRxdaQwAnAQAKAAYJRxdaQwAnAQAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8cAAISAAkJohTDJwDtAQASAAkJohTDJwDtAQAAAA==.',
Ro='Rosealia:BAAALgAECgUJCgAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAABLgAECn8pAAIFAAgJFBX9BgAEAgAFAAgJFBX9BgAEAgAAAA==.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgYJBgABLgAECgQJBAABAAAAAA==.Saintzan:BAAALgAECgUJBgAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECggJFwACAKEQAA==.Sathariel:BAAALgADCgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8aAAIZAAcJ6wuBDAA+AQAZAAcJ6wuBDAA+AQAAAA==.Schmoop:BAABLgAECn8dAAQcAAcJKSJ+DwCMAgAcAAcJKSJ+DwCMAgAMAAMJXBtTUwDpAAAWAAEJ8RBfVgA0AAABLgAFFAUJDgARAJMmAA==.',
Se='Seldaria:BAAALgAECgYJDwAAAA==.Senza:BAAALgAECgUJDQAAAA==.Senzyri:BAABLgAECn8UAAIDAAYJ+hQzOQAuAQADAAYJ+hQzOQAuAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECgYJDwABAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgABAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8WAAIHAAcJ6QxOFgDMAAAHAAcJ6QxOFgDMAAAAAA==.',
Sn='Snowthistle:BAAALgAECgYJCgAAAA==.',
So='Sorle:BAAALgADCgYJBgABLgAECggJFwAGADkTAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAAALgAECgEJAgAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgcJGQAWAKEhAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgEJAQAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Stonymahoney:BAABLgAECn8kAAICAAgJrBpCJACzAQACAAgJrBpCJACzAQAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAABLgAECn8gAAIGAAgJjyA+AwChAgAGAAgJjyA+AwChAgAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.',
Sv='Sveela:BAABLgAECn8cAAITAAgJdh/AAwDKAgATAAgJdh/AAwDKAgAAAA==.Sveelaa:BAAALgAECgYJEgABLgAECggJHAATAHYfAA==.Sveella:BAAALgADCgEJAQABLgAECggJHAATAHYfAA==.',
Sw='Swampjimmy:BAAALgAECgIJAgAAAA==.',
Sy='Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn8kAAIMAAgJ7hz+AwCaAgAMAAgJ7hz+AwCaAgAAAA==.Talras:BAAALgADCgkJDAAAAA==.',
Te='Temlock:BAABLgAECn8uAAIKAAcJthsoMQBIAgAKAAcJthsoMQBIAgABLgAECggJHAAHAEcbAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDAARAMMdAA==.Temtank:BAABLgAECn8cAAIHAAgJRxtIBQDhAQAHAAgJRxtIBQDhAQAAAA==.',
Tr='Trak:BAABLgAECn8UAAIdAAgJHwziMwAtAQAdAAgJHwziMwAtAQAAAA==.Trukarak:BAABLgAECn8XAAICAAgJoRDfPABTAQACAAgJoRDfPABTAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Valenti:BAAALgAECgUJDgAAAA==.Valor:BAABLgAECn8fAAICAAcJQyGyFAAVAgACAAcJQyGyFAAVAgAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAAALgAECgcJEwAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.',
Xi='Xiao:BAABLgAECn8YAAIVAAgJKxYWDADmAQAVAAgJKxYWDADmAQAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQABAAAAAA==.',
Ya='Yahargul:BAAALgAECgYJDQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Ze='Zeik:BAABLgAECn8cAAMeAAgJtBXABwCcAQAeAAgJtBXABwCcAQACAAMJngoInABuAAAAAA==.Zephyrgosa:BAAALgADCgUJCAAAAA==.',
Zu='Zucco:BAAALgAECgkJCQAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgcJGQAWAKEhAA==.',
['Zí']='Zíx:BAABLgAECn8UAAIfAAYJRBGvIAA6AQAfAAYJRBGvIAA6AQAAAA==.',
['Àl']='Àlcàrà:BAAALgAECgYJDAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgMJAwAAAA==.',
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

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

local lookup = {'Rogue-Subtlety','Druid-Balance','Druid-Restoration','DemonHunter-Devourer','Monk-Windwalker','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Paladin-Retribution','Warrior-Protection','Mage-Frost','Shaman-Elemental','Rogue-Assassination','Druid-Feral','DeathKnight-Blood','DeathKnight-Frost','Shaman-Enhancement','Shaman-Restoration','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCgAAAA==.',
Au='Augmentation:BAAALgAECgEJAQAAAA==.Aurumursi:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgADCgkJEgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgQJBAAAAA==.',
Be='Belthazaar:BAAALgADCgQJBAAAAA==.',
Bl='Blade:BAAALgAFFAIJAwAAAA==.Blarneystone:BAAALgAECgQJBAAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8JAAIBAAQJ1hNvAwBLAQABAAQJ1hNvAwBLAQAuAAQKfyYAAgEACAnLIkoGACwDAAEACAnLIkoGACwDAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAAALgAECgYJEwAAAA==.',
Bu='Bullievit:BAABLgAECn8bAAMCAAgJkRtYHQAVAgACAAgJkRtYHQAVAgADAAQJLQUvngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAAALgAECggJEgAAAA==.',
Ch='Chaozz:BAABLgAECn8YAAIEAAYJXyIQPwD4AQAEAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgADCggJEgAAAA==.Chunly:BAAALgAECgIJAgAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAAALgADCgcJBwAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgYJGwAFAKQkAA==.',
Cr='Crisgard:BAAALgAECgQJCQAAAA==.Cronos:BAAALgAECgcJDwAAAA==.Crysalus:BAAALgADCggJGwAAAA==.',
Da='Dacian:BAAALgADCgEJAQAAAA==.Darallyn:BAAALgADCgkJEQAAAA==.Davik:BAAALgAECgQJDQAAAA==.',
De='Deathcharger:BAAALgADCgYJDwAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Doser:BAAALgAECgYJCAAAAA==.',
Dr='Dracarsynimz:BAAALgAECggJIQAAAQ==.Dracene:BAAALgAECgQJBAAAAA==.',
Du='Duf:BAAALgAECgEJAQAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fl='Flixs:BAAALgADCggJEAABLgAECgIJBAAGAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8ZAAMHAAkJwB4MBQAVAwAHAAkJwB4MBQAVAwAIAAEJZQq3hQA7AAAAAA==.',
Fr='Friëren:BAAALgADCgcJCgAAAA==.',
Ga='Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAABLgAECn8bAAQJAAgJ5RyBBADVAQAJAAgJ5RyBBADVAQAKAAIJOQgkcQBiAAALAAEJgw3bVQA2AAAAAA==.',
Gi='Giffca:BAAALgAECgYJDQAAAA==.',
Gr='Groobel:BAAALgAECgEJAgAAAA==.Groobs:BAAALgAECgEJAwAAAA==.',
Ho='Holycow:BAAALgAECgUJBQAAAA==.',
Hu='Humanmatt:BAAALgAECgIJAwAAAA==.',
Ic='Icewolff:BAAALgAECgEJAQAAAA==.',
Ik='Ikinokoru:BAABLgAECn8dAAIMAAcJ3SSTDQDRAgAMAAcJ3SSTDQDRAgAAAA==.',
In='Inyànga:BAAALgAECgIJAgAAAA==.',
Je='Jeffren:BAAALgAECgIJBAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECggJFgAMAMgXAA==.',
Ka='Kalal:BAAALgADCgQJBAAAAA==.',
Ke='Keg:BAABLgAECn8bAAIFAAYJpCQUEAB/AgAFAAYJpCQUEAB/AgAAAA==.',
Ko='Kovowolf:BAABLgAECn8aAAIDAAgJRBjdJAAmAgADAAgJRBjdJAAmAgAAAA==.',
Kr='Krazedwolf:BAABLgAECn8WAAINAAcJQB4xOgA6AgANAAcJQB4xOgA6AgAAAA==.',
Kv='Kvn:BAAALgAECgIJAgAAAA==.',
Le='Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJBwAAAA==.',
Li='Linsay:BAACLgAFFH8PAAIJAAYJqBviAQD1AQAJAAYJqBviAQD1AQAuAAQKfyQAAgkACQlZJT0BAMADAAkACQlZJT0BAMADAAAA.',
Lo='Lokagdai:BAAALgADCgEJAQAAAA==.Lotieos:BAAALgAECgYJEQAAAA==.Lovelypwr:BAABLgAECn8lAAIJAAgJHg54BwCDAQAJAAgJHg54BwCDAQAAAA==.',
Ma='Manzio:BAAALgADCgQJBAAAAA==.Matheris:BAABLgAECn8VAAIOAAgJXiJSBgDMAgAOAAgJXiJSBgDMAgAAAA==.Mawiyah:BAAALgADCgcJCAAAAA==.',
Me='Melarac:BAAALgADCgcJGAAAAA==.',
Mi='Minimagic:BAABLgAECn8gAAIPAAgJsBynPQCBAgAPAAgJsBynPQCBAgAAAA==.',
Mo='Monker:BAAALgAECgcJDgAAAA==.',
Mu='Muth:BAAALgADCgUJBgAAAA==.',
Na='Nasara:BAABLgAECn8fAAIPAAgJZSD2IADwAgAPAAgJZSD2IADwAgAAAA==.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgUJDQAGAAAAAA==.Notloc:BAAALgAECgMJAwABLgAECgYJGwAFAKQkAA==.',
Ob='Oblivionpwr:BAAALgADCgQJBgABLgAECggJJQAJAB4OAA==.',
On='Onomisar:BAAALgAECgQJBwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAAALgAECgQJCQAAAA==.Pallyfever:BAAALgADCgcJBwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgYJGwAFAKQkAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgQJBAAAAA==.Repentia:BAAALgAECgQJCQAAAA==.Revaneth:BAAALgADCgMJAwAAAA==.',
Ro='Roidsnmolly:BAAALgAECgYJAQAAAA==.',
Ru='Runa:BAAALgAECgEJAQABLgAECggJGgADAEQYAA==.',
Sa='Sahlberg:BAAALgAECgMJBQAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJEwAGAAAAAA==.',
Se='Senkestsu:BAAALgAECgEJAQAAAA==.Seraphin:BAAALgADCgEJAQAAAA==.Sezen:BAAALgADCgYJBgAAAA==.',
Sh='Shammtastiç:BAABLgAECn8bAAIQAAcJ1xXiJwDUAQAQAAcJ1xXiJwDUAQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAYJDwAJAKgbAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAAALgAECgQJBAAAAA==.',
Sn='Sncak:BAACLgAFFH8OAAMBAAQJ6hZVAwBPAQABAAQJ6hZVAwBPAQARAAEJOQ03BgBcAAAuAAQKfx8AAwEACQneIiYCAJADAAEACQlmIiYCAJADABEAAwm/G6IPABYBAAAA.',
So='Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAABLgAECn8UAAISAAgJGCA5BADdAgASAAgJGCA5BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sy='Symphony:BAAALgADCgkJGwAAAA==.Syrax:BAAALgAECgYJCgABLgAECggJHQATAK0XAA==.Syrieal:BAABLgAECn8dAAMTAAgJrReeAwCvAQATAAgJrReeAwCvAQAUAAEJ3QNvGQApAAAAAA==.',
Ta='Taiyla:BAABLgAECn8bAAIPAAgJtQ9mGwBwAQAPAAgJtQ9mGwBwAQAAAA==.Talithiala:BAAALgADCgkJFgAAAA==.Tallai:BAAALgAECgEJAgAAAA==.Tash:BAABLgAECn8jAAMHAAgJGhcoEwA1AgAHAAgJGhcoEwA1AgAFAAQJnAxaTQDcAAAAAA==.',
Te='Tejano:BAAALgAECgYJBwAAAA==.',
Tr='Trip:BAABLgAECn8bAAMVAAgJ/Q6nBQA+AQAVAAYJNAunBQA+AQAWAAgJTgvyVgArAQAAAA==.',
Tu='Tubbybuddy:BAAALgAECgYJDQAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAQJDAAKAOEWAA==.Unilock:BAAALgAECgkJCQABLgAFFAQJDAAKAOEWAA==.Unipray:BAACLgAFFH8MAAIKAAQJ4RZJBABEAQAKAAQJ4RZJBABEAQAuAAQKfyEAAwoACQmwIlEBAG8DAAoACQmwIlEBAG8DAAkABwmLHMwUAEcCAAAA.',
Va='Vamperella:BAAALgAECgQJBwAAAA==.',
Ve='Velkor:BAAALgAECgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgADCggJEQAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgAAAA==.',
Ye='Yefercas:BAAALgAECgQJCAAAAA==.',
Yi='Yiumi:BAABLgAECn8YAAIXAAgJKhGjAAC/AQAXAAgJKhGjAAC/AQAAAA==.',
Yl='Ylvis:BAAALgAECgMJBQAAAA==.',
Yo='You:BAABLgAECn8bAAITAAgJGxU5BACTAQATAAgJGxU5BACTAQAAAA==.',
Yu='Yurdead:BAAALgADCgYJBgABLgAECgEJAQAGAAAAAA==.',
Ze='Zemzelett:BAAALgAECgQJBAAAAA==.',
Zu='Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
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

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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Warrior-Protection','Mage-Frost','Shaman-Elemental','DeathKnight-Blood','Shaman-Enhancement','Shaman-Restoration','Warlock-Demonology','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgMJAwAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJBwAAAA==.',
Be='Belthazaar:BAAALgADCgcJEgAAAA==.',
Bl='Blade:BAACLgAFFH8FAAIBAAMJRhV6FQC7AAABAAMJRhV6FQC7AAAuAAQKfxsAAgEACAnWIjAHAHsCAAEACAnWIjAHAHsCAAAA.Blarneystone:BAAALgAECgQJCwAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8RAAICAAUJOSAcCABpAQACAAUJOSAcCABpAQAuAAQKfy8AAwIACQm4IjQCAN0CAAIACQm4IjQCAN0CAAMAAQl8FhsYAEEAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIEAAYJ5AtyEQAFAQAEAAYJ5AtyEQAFAQAAAA==.',
Bu='Bullievit:BAABLgAECn8kAAMFAAkJVx3NCgAeAgAFAAkJVx3NCgAeAgAGAAQJLQU4ngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn8iAAIHAAgJHBFdBACpAQAHAAgJHBFdBACpAQAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAQABLgAFFAMJBQABAEYVAA==.Chaozz:BAABLgAECn8YAAIIAAYJXyIKPwD4AQAIAAYJXyIKPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgQJBAAAAA==.Chunly:BAAALgAECgQJBgAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAAALgAECgcJDQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAJAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8dAAMKAAgJvQ+LJAAkAQAKAAcJDwyLJAAkAQALAAMJ/g/VDQCwAAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECgcJDQAAAA==.Darallyn:BAAALgAECgQJBwAAAA==.Davik:BAAALgAECgQJEgAAAA==.',
De='Deathcharger:BAAALgADCgYJDwAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAAALgAECgYJEgAAAA==.',
Dr='Dracarsynimz:BAAALgAECgkJLAABLgAFFAQJCwAKAJ8KAQ==.Dracene:BAAALgAECgQJCwAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAAMAAAAAA==.',
Du='Duf:BAAALgAECgEJAgAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCAAMAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMNAAkJvB4MBQAUAwANAAkJvB4MBQAUAwAOAAEJZQq/hQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.',
Ga='Gamera:BAAALgAECgQJBwAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8KAAMPAAQJ8hrVDwASAQAPAAMJsBnVDwASAQAQAAIJmRDCHgCbAAAuAAQKfyEABA8ACAnlHAAOAKMCAA8ACAnlHAAOAKMCABAACAlkGbIHAGoCABEAAgk5CCtxAGIAAAAA.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBgAAAA==.',
Ho='Holycow:BAAALgAECgUJBQAAAA==.',
Hu='Humanmatt:BAAALgAECgQJBQAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgEJAgAAAA==.',
Ik='Ikinokoru:BAABLgAECn8sAAISAAgJZiTnCAClAgASAAgJZiTnCAClAgAAAA==.',
In='Inyànga:BAAALgAECgIJAgAAAA==.',
Je='Jeffren:BAAALgAECgQJCAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgASAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIJAAcJPiQXEAB+AgAJAAcJPiQXEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8GAAIGAAIJ5RJNLwCKAAAGAAIJ5RJNLwCKAAAuAAQKfygAAgYACQnXHjEHANsCAAYACQnXHjEHANsCAAAA.',
Kr='Krazedwolf:BAABLgAECn8jAAITAAkJrSC9CQC8AgATAAkJrSC9CQC8AgAAAA==.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJCgAAAA==.',
Li='Linsay:BAACLgAFFH8YAAIPAAYJESXRAAAtAgAPAAYJESXRAAAtAgAuAAQKfy8AAg8ACQkjJkABAMADAA8ACQkjJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAQAAAA==.Lotieos:BAABLgAECn8WAAIUAAYJLg0/YwAdAQAUAAYJLg0/YwAdAQAAAA==.Lovelypwr:BAABLgAECn8xAAIPAAkJrBCvDAD8AQAPAAkJrBCvDAD8AQAAAA==.',
Ma='Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8XAAIVAAgJqiLwAgCoAgAVAAgJqiLwAgCoAgAAAA==.Mawiyah:BAAALgAECgYJBgAAAA==.Max:BAAALgAECgYJBgAAAA==.',
Me='Melarac:BAAALgAECgQJBwAAAA==.',
Mi='Minimagic:BAACLgAFFH8IAAIWAAMJhxvxQAAKAQAWAAMJhxvxQAAKAQAuAAQKfzEAAhYACAk3JIoJANwCABYACAk3JIoJANwCAAAA.',
Mo='Monker:BAABLgAECn8VAAQNAAgJhxmjJQCGAQANAAYJaxajJQCGAQAJAAYJgBUBPgAjAQAOAAMJvBwgPQCjAAAAAA==.',
Mu='Muthra:BAAALgADCgcJBwAAAA==.Muthroc:BAAALgAECgEJAQAAAA==.',
Na='Nasara:BAABLgAECn8rAAIWAAgJ0SL1IADwAgAWAAgJ0SL1IADwAgAAAA==.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgADCgEJAQAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgYJBgAMAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAJAD4kAA==.',
Ob='Oblivionpwr:BAAALgADCgQJCAABLgAECgkJMQAPAKwQAA==.',
On='Onomisar:BAAALgAECgQJBwAAAA==.',
Or='Oriah:BAAALgADCgIJAgAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8UAAIUAAYJtxTJTwBNAQAUAAYJtxTJTwBNAQAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAJAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgQJCwAAAA==.Repentia:BAAALgAECgYJEAAAAA==.Revaneth:BAAALgADCgUJCgAAAA==.',
Ro='Roidsnmolly:BAAALgAECgYJAQAAAA==.',
Ru='Runa:BAAALgAECgYJEAABLgAFFAIJBgAGAOUSAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgMJCAAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAEAOQLAA==.',
Se='Senkestsu:BAAALgAECgEJAwAAAA==.Seraphin:BAAALgAFFAEJAQAAAA==.Sezen:BAAALgAECgcJBwAAAA==.',
Sh='Shammtastiç:BAABLgAECn8sAAIXAAgJsRbaFQCkAQAXAAgJsRbaFQCkAQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAYJGAAPABElAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAAALgAECgcJEQAAAA==.',
Sn='Sncak:BAACLgAFFH8TAAMCAAUJzR8gCABoAQACAAUJzR8gCABoAQADAAEJOQ05BgBcAAAuAAQKfyQAAwIACQkoIykCAJADAAIACQkoIykCAJADAAMABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAABLgAECn8ZAAIEAAkJ8yE7BADdAgAEAAkJ8yE7BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgIJAgAAAA==.Syrax:BAAALgAECgYJEwABLgAECgkJKAAYADIaAA==.Syrieal:BAABLgAECn8oAAMYAAkJMhqlBQBMAgAYAAkJMhqlBQBMAgAHAAEJ3QN0GQApAAAAAA==.',
Ta='Taiyla:BAABLgAECn8sAAIWAAkJ8g8VKQD+AQAWAAkJ8g8VKQD+AQAAAA==.Talithiala:BAAALgADCgkJFgAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMNAAgJFBkmEwAzAgANAAgJFBkmEwAzAgAJAAcJigoVMQDBAAAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAIJBgAGAOUSAA==.',
Tr='Trip:BAABLgAECn8iAAMZAAkJBw9aCwBYAQAZAAcJBw1aCwBYAQAaAAkJHQvqVgArAQAAAA==.',
Tu='Tubbybuddy:BAAALgAECgYJDQAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAUJFQARAEwdAA==.Unilock:BAABLgAECn8XAAIbAAkJVhVSHwD1AQAbAAkJVhVSHwD1AQABLgAFFAUJFQARAEwdAA==.Unipray:BAACLgAFFH8VAAMRAAUJTB3wBQBpAQARAAUJTB3wBQBpAQAPAAIJiBXlFwCmAAAuAAQKfyIAAxEACQmwIlABAG8DABEACQmwIlABAG8DAA8ABwmUHM0UAEcCAAAA.',
Va='Vamperella:BAAALgAECgQJEAAAAA==.',
Ve='Velkor:BAAALgAECgIJAgAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgAAAA==.',
Ye='Yefercas:BAAALgAECgUJCgAAAA==.',
Yi='Yiumi:BAABLgAECn8pAAIcAAkJcxQGAQA2AgAcAAkJcxQGAQA2AgAAAA==.',
Yl='Ylvis:BAABLgAECn8ZAAISAAgJawXJRQA8AQASAAgJawXJRQA8AQAAAA==.',
Yo='You:BAABLgAECn8iAAIYAAkJTxW7CQDiAQAYAAkJTxW7CQDiAQAAAA==.',
Yu='Yurdead:BAAALgADCgYJBgABLgAECgEJAQAMAAAAAA==.',
Ze='Zemzelett:BAAALgAECgQJCQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
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

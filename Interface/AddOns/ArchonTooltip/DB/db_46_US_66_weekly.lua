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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Protection','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Priest-Shadow','Monk-Windwalker','Warlock-Demonology','Paladin-Holy','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Warlock-Destruction','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Restoration','Rogue-Subtlety','Hunter-Survival','Shaman-Elemental','Mage-Fire','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abaddôn:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Abelard:BAAALgAECgUJCAAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAYJCgACAMQNAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgUJBAAAAA==.',
Ag='Agesilaus:BAAALgADCgcJCwAAAA==.Agesipolis:BAAALgADCgUJCwAAAA==.Aggathon:BAEALgAECgcJEwAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgYJFgADAKojAA==.',
Ak='Akusai:BAAALgADCgcJBwABLgAECgYJEgABAAAAAA==.',
Al='Aldebaran:BAAALgADCgkJGQAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgEJAQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Ashke:BAAALgAECgUJDAAAAA==.',
Av='Avarice:BAAALgADCgEJAgABLgAECggJIgAEAEUXAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.',
Az='Azraeon:BAAALgAECgUJBgAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgcJDAABAAAAAA==.',
Ba='Badlucklouie:BAAALgAECgQJBAAAAA==.Badpenny:BAAALgADCgQJBQAAAA==.Bajenkas:BAAALgAECgQJBgAAAA==.Balfas:BAAALgADCgYJBgAAAA==.',
Be='Beaupeep:BAAALgAECgYJEgAAAA==.Benedictine:BAAALgAECgYJEAAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bo='Boyacky:BAAALgADCgMJAwAAAA==.',
Br='Braiglock:BAAALgAECgQJCAAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAABLgAECn8iAAQFAAgJbhaSFAD+AQAFAAgJbhaSFAD+AQAGAAIJyA6MBgCFAAAHAAIJthOGGAB9AAAAAA==.Caicedo:BAAALgAECgMJAwAAAA==.Callmemeg:BAAALgAECgMJAwAAAA==.Catadelic:BAAALgAECgcJEwAAAA==.',
Ce='Celektra:BAAALgAECgQJBAAAAA==.Celestial:BAAALgAECgYJEwAAAA==.',
Ch='Chewmatter:BAAALgAECgcJDwAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chud:BAAALgADCggJCAAAAA==.',
Ci='Cindroz:BAAALgAECgMJAwAAAA==.',
Cl='Claus:BAAALgADCgEJAQAAAA==.Cleanname:BAAALgAECgYJEAAAAA==.Clurichaun:BAAALgAECgUJDwAAAA==.',
Cr='Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAAALgAECgYJEQAAAA==.',
Da='Daemonna:BAAALgAECgYJBgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAAALgAECgcJEwAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgQJBwABLgAECggJFwAIAF4gAA==.Desdemona:BAAALgAECgYJDwAAAA==.Deshler:BAAALgAECgcJCgAAAA==.',
Di='Dirtyblonde:BAAALgAECgQJBQAAAA==.Ditlutz:BAABLgAECn8WAAIDAAYJqiNOAgDWAQADAAYJqiNOAgDWAQAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIEAAcJoxzFdADpAQAEAAcJoxzFdADpAQAAAA==.',
Do='Dom:BAACLgAFFH8HAAMJAAQJfwzdBQAEAQAJAAQJfwzdBQAEAQAKAAEJnQb+DABMAAAuAAQKfyAAAgkACAnxH/gYAIQCAAkACAnxH/gYAIQCAAAA.Doraf:BAAALgADCgYJBgAAAA==.Dormammu:BAAALgADCgYJBgAAAA==.',
Dr='Druken:BAAALgAECgQJBwAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfussy:BAAALgAECgYJCgAAAA==.',
Dy='Dybby:BAAALgAECgYJCwAAAA==.',
El='Elderoth:BAAALgAECgQJBgAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAAALgAECgYJEwAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
['Eä']='Eärendil:BAAALgADCgUJBQAAAA==.',
Fa='Faearia:BAACLgAFFH8GAAILAAQJ2AwKAwA2AQALAAQJ2AwKAwA2AQAuAAQKfx8AAgsACQmnG+QMALUCAAsACQmnG+QMALUCAAAA.Faebryn:BAABLgAECn8WAAIJAAYJ4htvCgB4AQAJAAYJ4htvCgB4AQAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgMJAwAAAA==.Fettylock:BAAALgAECgEJAQAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgADCggJGgAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAAALgAECgYJEwAAAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgUJCgAAAA==.',
Ga='Gallifrey:BAABLgAECn8iAAIEAAgJRRdxCwD4AQAEAAgJRRdxCwD4AQAAAA==.Gamarrick:BAABLgAECn8UAAILAAYJIxBqLgBtAQALAAYJIxBqLgBtAQAAAA==.Ganyin:BAAALgADCgcJGAAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgADCgQJCAAAAA==.',
Gn='Gnometzu:BAABLgAECn8WAAIMAAYJ/hXKCwAUAQAMAAYJ/hXKCwAUAQAAAA==.',
Go='Golddicmove:BAAALgADCggJFwAAAA==.Goth:BAAALgAECgYJBgAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgADCgYJBwAAAA==.Griever:BAEALgAECgQJBQAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAINAAcJhhQBGQBKAQANAAcJhhQBGQBKAQAAAA==.Guillak:BAAALgAECgYJEwAAAA==.',
Ha='Harafar:BAAALgAECgcJEAAAAA==.Harmonic:BAAALgADCgkJCQABLgADCgkJEAABAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgMJAwAAAA==.',
He='Healtards:BAAALgAECgYJEAAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.',
Ho='Holyfyer:BAAALgADCgkJDgAAAA==.Holyshift:BAABLgAECn8ZAAIOAAgJ8Bp1GABPAgAOAAgJ8Bp1GABPAgAAAA==.Hoofingit:BAAALgADCgkJHgAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Ic='Icyifu:BAAALgAECgcJDgAAAA==.',
If='Iffy:BAAALgAECgYJDAAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAAALgAECgUJBgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn8VAAMPAAcJ8BTzIQDUAQAPAAcJ8BTzIQDUAQALAAUJwQ9MPAAQAQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAQAAAA==.Jackthebeast:BAAALgAFFAIJBAAAAA==.Jaida:BAABLgAECn8fAAICAAgJewplIgD8AAACAAgJewplIgD8AAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8WAAMQAAYJwSVvAQABAgAQAAYJwSVvAQABAgARAAEJ5yOLKQBUAAAAAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgYJFgAQAMElAA==.',
Je='Jeanne:BAABLgAECn8WAAMLAAYJqAmFDgANAQALAAYJqAmFDgANAQAPAAUJNAbiWQDMAAAAAA==.Jedoniah:BAABLgAECn8WAAIIAAYJySVlIwCbAgAIAAYJySVlIwCbAgAAAA==.Jeffrey:BAAALgAECgIJAwAAAA==.',
Jo='Jorhmont:BAAALgADCgkJHwAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAAALgAECgYJDQAAAA==.Jumbo:BAAALgAECgUJDwAAAA==.Jumpeor:BAACLgAFFH8OAAIIAAYJkhU8AQCSAQAIAAYJkhU8AQCSAQAuAAQKfxgAAggACQkQIuQDAJADAAgACQkQIuQDAJADAAAA.',
Ka='Kassey:BAAALgADCgQJBQAAAA==.Katacola:BAACLgAFFH8VAAISAAYJth8FAQAnAgASAAYJth8FAQAnAgAuAAQKfyEAAhIACAm5JssCAGoDABIACAm5JssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kevesebal:BAABLgAECn8VAAMNAAkJWyJbBQBmAwANAAkJWyJbBQBmAwATAAEJAAA4cAA2AAAAAA==.',
Kh='Khronic:BAAALgAECgQJBwAAAA==.',
Ki='Kikiliki:BAAALgAECgUJCgAAAA==.Kilthgar:BAABLgAECn8VAAIDAAYJSxSZBgAlAQADAAYJSxSZBgAlAQAAAA==.',
Ko='Koa:BAAALgAECgYJEQAAAA==.Kobeni:BAAALgAECgYJCgAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAAALgAECgYJCwAAAA==.Koravellia:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgAAAA==.',
Ku='Kurau:BAAALgAECgcJEgAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAAALgAECgMJAwAAAA==.',
Le='Leela:BAAALgADCgMJAwABLgAECgcJDgABAAAAAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAAALgAECgcJDgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgADCgYJBgAAAA==.',
Lu='Lunula:BAABLgAECn8dAAIRAAcJ6BmZCQAGAgARAAcJ6BmZCQAGAgAAAA==.Luxörd:BAABLgAECn8UAAIOAAYJ7yIfFgBgAgAOAAYJ7yIfFgBgAgAAAA==.',
Ly='Lyaenna:BAAALgAECgcJEgAAAA==.Lydius:BAAALgAECgcJEwAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgIJAgAAAA==.Madeng:BAAALgAECgUJCwAAAA==.Mageshir:BAAALgAECgcJDwAAAA==.Maletherion:BAABLgAECn8WAAIUAAYJTR+nAwBxAQAUAAYJTR+nAwBxAQAAAA==.Maltherion:BAABLgAECn8VAAIVAAcJox2JFAAsAgAVAAcJox2JFAAsAgAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgADCggJFgAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgQJBQAAAA==.Minireaper:BAAALgAECgUJDQAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8WAAIIAAYJCSLlPAAxAgAIAAYJCSLlPAAxAgAAAA==.',
Mo='Moggren:BAAALgAECgYJBgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgYJEQABAAAAAA==.Mongke:BAAALgADCgYJBwAAAA==.',
Na='Namôr:BAAALgADCgQJBQAAAA==.Narzel:BAAALgAECgEJAQAAAA==.Nazgul:BAAALgAECgkJCgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8UAAISAAYJdB6rKQAMAgASAAYJdB6rKQAMAgAAAA==.Nequinss:BAAALgAECgcJEwABLgAECgYJFAASAHQeAA==.Nevermore:BAAALgAECgIJAgAAAA==.',
Ni='Nicabar:BAABLgAECn8YAAINAAgJJQmIdgBwAQANAAgJJQmIdgBwAQAAAA==.Nitemare:BAAALgADCgEJAQAAAA==.',
No='Noaman:BAAALgAECgEJAgAAAA==.Noapandman:BAAALgADCgEJAQAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgADCgYJCQABLgAECgUJDQABAAAAAA==.Normareaper:BAAALgADCgQJBQAAAA==.Noztalgia:BAAALgAECgUJCgAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQAAAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAAALgAECgQJBQAAAA==.',
Oa='Oakily:BAABLgAECn8WAAISAAYJ9Ak5cgD/AAASAAYJ9Ak5cgD/AAAAAA==.',
Od='Oditte:BAAALgADCgEJAQAAAA==.',
Oi='Oilliphéist:BAAALgAECgQJBgAAAA==.',
Om='Omegatanker:BAABLgAECn8dAAIWAAgJsCTFAwBTAwAWAAgJsCTFAwBTAwAAAA==.',
Or='Ornot:BAABLgAECn8ZAAIXAAgJUA7ODQBiAQAXAAgJUA7ODQBiAQAAAA==.',
Os='Oshdruid:BAABLgAECn8XAAISAAgJqyAeBQAvAgASAAgJqyAeBQAvAgAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pandurbear:BAAALgADCgQJBQAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pergatory:BAAALgAECgUJDgAAAA==.',
Ph='Pho:BAAALgAECgIJAgAAAA==.Phuule:BAAALgADCgQJBQAAAA==.',
Pi='Piruletras:BAAALgAECgQJBAAAAA==.',
Pr='Priechwhirl:BAAALgAECgkJEwAAAA==.Provost:BAAALgAECgYJDwAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgEJAgAAAA==.',
Qu='Quanx:BAAALgAECgYJBgAAAA==.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Remulüs:BAAALgAECgcJEwAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn8XAAIYAAcJVxkgGgAxAgAYAAcJVxkgGgAxAgAAAA==.Riolu:BAAALgAECgEJAQAAAA==.',
Ru='Ruith:BAAALgAECgMJAwAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8VAAQFAAcJ7wluCADpAAAFAAcJ7wluCADpAAAGAAQJ4hYQJwDpAAAHAAEJ7Aw0YwAwAAAAAA==.Scecretzs:BAAALgAECgMJAwAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8UAAIZAAYJKB7yDAD7AQAZAAYJKB7yDAD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sesamo:BAACLgAFFH8NAAIIAAQJgRI4BABTAQAIAAQJgRI4BABTAQAuAAQKfycAAggACQl/IzYGAGoDAAgACQl/IzYGAGoDAAAA.',
Sh='Shocks:BAAALgAECgEJAgAAAA==.Shroomin:BAABLgAECn8XAAIaAAYJ7iDoHgAYAgAaAAYJ7iDoHgAYAgAAAA==.',
Si='Sixseven:BAAALgADCgkJEgAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAAALgAECgUJCgAAAA==.',
Sm='Smarthen:BAABLgAECn8WAAQEAAgJBQ8WFgCSAQAEAAgJBQ8WFgCSAQAbAAIJJwFZEAAzAAAcAAEJPgERIwANAAAAAA==.',
Sn='Sniffums:BAAALgAECgYJEAAAAA==.',
So='Solarian:BAAALgAECgYJEwAAAA==.Soule:BAAALgADCgkJJQAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECgYJFAAOAO8iAA==.',
St='Startle:BAAALgADCgcJEQAAAA==.Steelbreeze:BAAALgADCggJHgAAAA==.Stoutbringer:BAAALgADCggJFwAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaedir:BAAALgADCgcJBgAAAA==.Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAAALgADCgIJAgAAAA==.Talyn:BAAALgAECgcJDgAAAA==.Taomi:BAABLgAECn8WAAIXAAYJ5xQgEwAcAQAXAAYJ5xQgEwAcAQAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.',
Te='Tengri:BAAALgAECgEJAQAAAA==.Tenspeed:BAAALgAECgUJDwAAAA==.',
Th='Thire:BAAALgAECgQJBAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAECgQJBAABLgAFFAYJEAAdAAUaAA==.',
Ti='Tidereign:BAAALgAECgMJAwAAAA==.Timka:BAAALgAECgQJBwAAAA==.Tiriell:BAABLgAECn8XAAIIAAgJXiCFIgCfAgAIAAgJXiCFIgCfAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAABLgAECn8iAAILAAgJqhHMGwD+AQALAAgJqhHMGwD+AQAAAA==.',
['Tô']='Tôrunn:BAABLgAECn8UAAIDAAcJlA2lGQBEAQADAAcJlA2lGQBEAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgADCgIJAgABLgAECgYJFgADAKojAA==.',
Va='Vallock:BAAALgAECgUJCwAAAA==.Vanarn:BAAALgADCgQJBQAAAA==.',
Ve='Velrez:BAAALgAECgMJAwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAAALgAECgUJBgAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBAAAAA==.Voidbourne:BAAALgADCgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgQJBwAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Wayden:BAAALgAECgYJCwAAAA==.Waz:BAAALgADCgEJAQAAAA==.',
We='Wef:BAAALgAECgcJDwAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAAALgAECgcJEwAAAA==.Wings:BAAALgAECgcJDAAAAA==.Wintel:BAAALgADCgEJAQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgIJAgAAAA==.',
Yl='Ylva:BAAALgADCgcJCAAAAA==.',
Yo='Yo:BAAALgAECgQJBwAAAA==.Yozomiria:BAAALgADCgEJAwAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAAALgADCgkJEAABLgAFFAMJBgAHAB4HAA==.Zanju:BAAALgAECgQJBAAAAA==.Zanvoker:BAACLgAFFH8GAAIHAAMJHgfHCgDEAAAHAAMJHgfHCgDEAAAuAAQKfxsAAgcABwm5GKAWACICAAcABwm5GKAWACICAAAA.',
Ze='Zerc:BAABLgAECn8kAAIeAAkJPx10AABbAgAeAAkJPx10AABbAgAAAA==.',
Zi='Zinkie:BAABLgAECn8WAAITAAYJABY3AwBAAQATAAYJABY3AwBAAQAAAA==.',
Zo='Zorttok:BAAALgAECgMJAwAAAA==.',
Zy='Zyp:BAAALgADCgMJAwAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8KAAICAAYJxA2VCwB5AQACAAYJxA2VCwB5AQAuAAQKfxcAAgIACQmPIj0UAN4CAAIACQmPIj0UAN4CAAAA.',
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

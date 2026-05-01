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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Enhancement','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Monk-Windwalker','Mage-Frost','Warlock-Affliction','Evoker-Preservation','Paladin-Protection','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Evoker-Devastation','Warrior-Fury','Warrior-Arms','Hunter-Survival','Monk-Mistweaver','Warrior-Protection','Rogue-Subtlety','Priest-Discipline','Priest-Holy',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8UAAIBAAYJ8BDhCgAhAQABAAYJ8BDhCgAhAQAAAA==.Akumu:BAABLgAECn8cAAICAAkJYhpVBQC5AgACAAkJYhpVBQC5AgAAAA==.',
Al='Alangi:BAAALgAECgYJBgABLgAECggJLgADAEUeAA==.Albinah:BAAALgAECgYJEAAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzu:BAAALgADCgEJAQAAAA==.Aldien:BAAALgAECgQJCQAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.',
Ao='Aoe:BAACLgAFFH8FAAIEAAIJHBUgLgCcAAAEAAIJHBUgLgCcAAAuAAQKfxIAAgQACQmZEMMVALoBAAQACQmZEMMVALoBAAAA.',
Ar='Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8XAAIFAAcJ2wncCQBJAQAFAAcJ2wncCQBJAQAAAA==.',
Av='Averroes:BAABLgAECn8gAAIGAAgJVQ4aIgCWAQAGAAgJVQ4aIgCWAQAAAA==.',
Aw='Awa:BAAALgAECgQJDAABLgAFFAIJBQAEABwVAA==.Awee:BAABLgAECn81AAIHAAgJACF5AwBhAgAHAAgJACF5AwBhAgABLgAFFAIJBQAEABwVAA==.Awi:BAAALgADCgUJBQABLgAFFAIJBQAEABwVAA==.Awo:BAABLgAECn8vAAQIAAgJZSU7AQBqAwAIAAgJZSU7AQBqAwACAAYJiBZBFABuAQAJAAgJgh2+CABPAQAAAA==.Awoo:BAAALgAECgIJAgABLgAECggJLwAIAGUlAA==.',
Ay='Aylen:BAABLgAECn8bAAIKAAgJqA95LgCIAQAKAAgJqA95LgCIAQAAAA==.',
Ba='Bahldrahg:BAAALgAECgMJAwAAAA==.Bahnjek:BAAALgAECgUJBQAAAA==.Baki:BAAALgAECgQJBwABLgAFFAMJCAALAIAfAA==.Banegrim:BAABLgAECn8UAAIMAAYJ1ApsWQDlAAAMAAYJ1ApsWQDlAAAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAAALgAECgcJBwAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAECgkJHAACAGIaAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwANAAAAAA==.Blindwalker:BAABLgAECn8eAAIOAAgJhw51HgBUAQAOAAgJhw51HgBUAQAAAA==.Blissfuleigh:BAAALgAECgIJAgAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgMJAwANAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgADCgkJFgAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgMJAwANAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.Brielan:BAAALgAECgYJEQAAAA==.',
Ca='Cadillacbob:BAAALgAECgEJAQAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8PAAILAAUJlx9sAgCYAQALAAUJlx9sAgCYAQAuAAQKfysAAgsACAkqIVkDAIcCAAsACAkqIVkDAIcCAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgEJAQAAAA==.',
Ch='Cheesemonk:BAAALgADCgkJGAABLgAECggJJwAKAEcmAA==.Cheesepally:BAABLgAECn8nAAIKAAgJRyaYAgAGAwAKAAgJRyaYAgAGAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.',
Cl='Cloud:BAAALgAECgIJAgAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAAALgAECgUJEwAAAA==.Cylla:BAAALgAECgYJBgABLgAFFAMJBwAKAHwVAA==.',
Da='Daddywarbuks:BAAALgAECgUJBQAAAA==.Dagin:BAABLgAECn8bAAIKAAcJYxvLIADGAQAKAAcJYxvLIADGAQAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAAALgAECgYJEwAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAAALgAECgYJEAAAAA==.Dawnotheholy:BAABLgAECn8qAAMPAAgJXw1BFQCqAQAPAAgJXw1BFQCqAQAKAAcJDA/9WgABAQAAAA==.',
De='Deathstar:BAACLgAFFH8TAAMQAAUJFR+LEABsAQAQAAQJFR+LEABsAQAOAAEJAAAXHwAAAAAuAAQKfygAAxAACQkyI5UNAC4DABAACQkyI5UNAC4DABEAAwl+Df4RAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8UAAMMAAcJJRv8UQDSAQAMAAYJ6Rn8UQDSAQASAAIJ0RLuSACTAAAAAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgMJAwANAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgMJAwANAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8HAAMRAAMJoBOzAgACAQARAAMJoBOzAgACAQAQAAEJow5GVABPAAAuAAQKfx0AAxEABwlpIw0CAPkBABEABwlTIg0CAPkBABAABgl/IRBdANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJBQAAAA==.Dominhoes:BAAALgAECgMJBQAAAA==.Doontless:BAAALgAECgYJEQAAAA==.',
Dr='Draig:BAAALgAECgUJBgAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwATAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAAALgAECgIJAwAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
Eb='Ebonhèart:BAAALgAECgYJEQAAAA==.',
Ec='Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAAALgAECgYJDQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIUAAYJoRWrpwCKAQAUAAYJoRWrpwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Frombehind:BAAALgAECgMJAwABLgAFFAUJEgAQAFsaAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwANAAAAAA==.Gloomy:BAAALgAECgYJDgAAAA==.',
Gr='Grandizzle:BAAALgADCgcJCQAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAABLgAECn8qAAIVAAgJySUNAQD/AgAVAAgJySUNAQD/AgAAAA==.Guruprime:BAAALgADCgMJBAAAAA==.',
Gw='Gwalla:BAAALgADCgUJBQABLgAECgMJBQANAAAAAA==.',
Ha='Hagniy:BAABLgAECn8mAAIPAAgJGhvFGABMAgAPAAgJGhvFGABMAgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Happyboy:BAAALgAECgYJDgABLgAECggJLwAIAGUlAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECggJDgAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAABLgAECn8ZAAIWAAgJXiEnBQD6AgAWAAgJXiEnBQD6AgAAAA==.Heyzus:BAAALgAECgIJAgAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJCwAAAA==.',
Hr='Hrizul:BAABLgAECn8VAAMXAAgJURrADwDIAQAXAAgJURrADwDIAQAKAAIJNQvDlwB1AAAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJCwAAAA==.',
Il='Il:BAABLgAECn8fAAIMAAgJwB8qIACXAgAMAAgJwB8qIACXAgAAAA==.Illisharr:BAAALgADCggJCgAAAA==.Ilusive:BAABLgAECn8bAAIYAAgJsA7gFABwAQAYAAgJsA7gFABwAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJBgAAAA==.Irielyn:BAAALgADCgcJBwAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgUJDQAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn8rAAMZAAgJ8B3sFgBeAgAZAAcJZR7sFgBeAgAYAAYJvRZwIQAQAQAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwATAEgZAA==.',
Ju='Junö:BAAALgADCgcJEgAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgUJCQAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Katamine:BAABLgAECn8eAAIaAAYJRRvjEwBmAQAaAAYJRRvjEwBmAQAAAA==.Katoz:BAAALgAFFAEJAgAAAA==.',
Ke='Keydron:BAAALgADCgcJDQAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kilemall:BAAALgAECggJAgAAAA==.Killnall:BAAALgAECgUJDAAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8dAAIBAAgJwxe5BAC7AQABAAgJwxe5BAC7AQAAAA==.',
Ko='Konantheduck:BAAALgADCgIJAgAAAA==.',
Kr='Krystarin:BAABLgAECn8UAAIIAAYJExcLIACAAQAIAAYJExcLIACAAQAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgMJAwAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAITAAgJSBk+EQBvAgATAAgJSBk+EQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn8jAAIbAAgJCB/UAACMAgAbAAgJCB/UAACMAgAAAA==.Launcelot:BAABLgAECn8cAAMcAAYJLCOjCgAAAgAcAAYJ9SKjCgAAAgAdAAMJwx+3DgAcAQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgUJBgAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8IAAILAAMJgB8+CQAtAQALAAMJgB8+CQAtAQAuAAQKfy8AAgsACAkYJgABAAoDAAsACAkYJgABAAoDAAAA.Littlezo:BAABLgAFFH8FAAIeAAMJWxCACgD7AAAeAAMJWxCACgD7AAAAAA==.',
Lo='Lotus:BAABLgAECn8WAAMTAAgJrhMXDAC1AQATAAgJrhMXDAC1AQAfAAYJqwz1OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAECggJLwAIAGUlAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn8cAAIJAAcJ+hAiCgAqAQAJAAcJ+hAiCgAqAQAAAA==.Makpriest:BAAALgADCgQJBwAAAA==.Malakaii:BAABLgAECn8aAAMFAAgJexEWDAAEAgAFAAgJQREWDAAEAgAYAAYJrhLBQgA+AQAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAAALgAECgQJCAAAAA==.Maxdeath:BAAALgAECggJEwAAAA==.Maztajake:BAAALgAECgYJDwAAAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgADCggJCgAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECggJHgADAEUbAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEALgAECgYJEAAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necroknight:BAAALgAECgEJAQAAAA==.Necrotheholy:BAAALgAECgQJCwAAAA==.',
Ng='Nghtíy:BAABLgAECn8WAAIQAAYJPxNwQQA6AQAQAAYJPxNwQQA6AQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8YAAILAAgJzQzsIQDIAQALAAgJzQzsIQDIAQAAAA==.Noh:BAAALgAECgEJAQAAAA==.Nordikmage:BAAALgAECgYJDQAAAA==.Nort:BAAALgADCgEJAQAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
On='Ondereth:BAAALgAECgUJCgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJBgAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.',
Pi='Piercey:BAACLgAFFH8FAAIgAAIJORuDDACvAAAgAAIJORuDDACvAAAuAAQKfyIAAiAACAmGHroKAGUCACAACAmGHroKAGUCAAEuAAQKCAkvAAgAZSUA.Pinkylove:BAABLgAECn8eAAIIAAgJ8iBRDADcAgAIAAgJ8iBRDADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJBwAAAA==.Promathia:BAACLgAFFH8HAAIKAAMJfBUSHgD+AAAKAAMJfBUSHgD+AAAuAAQKfzIAAwoACAngJV4CAAwDAAoACAngJV4CAAwDAA8ABAkXCBduAMIAAAAA.Pross:BAAALgADCgMJBAABLgAECgcJGwAKAGMbAA==.',
Pu='Puff:BAAALgAECgcJDAAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8GAAIGAAQJ2QUtEgAqAQAGAAQJ2QUtEgAqAQAuAAQKfxQAAgYACAkxFgY1ANoBAAYACAkxFgY1ANoBAAAA.Rat:BAABLgAECn8jAAILAAkJSSB1BABOAwALAAkJSSB1BABOAwAAAA==.',
Re='Rectumus:BAAALgADCgMJBAAAAA==.Redrouges:BAAALgAECgYJEQAAAA==.Redwood:BAAALgAECgIJAgAAAA==.Renvskadoosh:BAAALgADCgkJGQAAAA==.Rexpanda:BAABLgAECn8YAAIfAAYJ1R1/GgDmAQAfAAYJ1R1/GgDmAQAAAA==.',
Ro='Ross:BAEALgADCgEJAQABLgAFFAQJCAAfADMjAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Sa='Sapoude:BAAALgADCgYJCwAAAA==.Sarang:BAAALgADCgYJBgAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwANAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJAwAAAA==.Shadowrunner:BAAALgADCgYJCAAAAA==.Shamwich:BAAALgAECgYJDQAAAA==.Shandroz:BAAALgAECgMJAwAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shrkbait:BAAALgAECgMJAwAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAgAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAAALgAFFAEJAQAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgQJBAAAAA==.',
Sq='Squigglybutt:BAAALgAECgYJDgAAAA==.',
St='Steelwing:BAAALgAECgcJBwABLgAECgkJHAACAGIaAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strrawberry:BAAALgADCgIJAgAAAA==.',
Su='Sungchaluka:BAAALgADCgkJDwAAAA==.',
['Sá']='Sásu:BAAALgADCgkJEAAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAAALgAFFAQJBAAAAA==.Tars:BAAALgADCgMJBAAAAA==.Tats:BAAALgAECgYJDwAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIMAAkJIgwCHQDGAQAMAAkJIgwCHQDGAQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgADCggJCAAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgUJBQAAAA==.Throdwran:BAAALgAECgEJAQABLgAECgcJGwAKAGMbAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAIhAAYJAxmSJQDMAQAhAAYJAxmSJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJAwAAAA==.Totem:BAAALgAECgUJCAAAAA==.',
Tr='Tranqx:BAACLgAFFH8IAAIQAAMJGCQVHQBEAQAQAAMJGCQVHQBEAQAuAAQKfyoAAhAACAmuJv0CAAgDABAACAmuJv0CAAgDAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8eAAQDAAgJRRujCwDOAQADAAgJRRujCwDOAQAbAAQJtAYkLgCoAAAWAAEJZQPXSgAsAAAAAA==.Trizz:BAAALgADCgYJCQAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.',
Ts='Tsuchiya:BAAALgAECgUJBQAAAA==.',
Up='Uproar:BAABLgAECn8YAAIRAAkJ/B8vAAAZAwARAAkJ/B8vAAAZAwAAAA==.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAAALgAFFAIJBAAAAA==.Valeskogr:BAABLgAECn8dAAQGAAkJ7Q0xGgDDAQAGAAgJTg4xGgDDAQAeAAcJjQgnFQB1AQABAAgJmAMhUQAIAQAAAA==.Valestraza:BAAALgAECgYJBgAAAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Vengefulmilk:BAAALgADCgUJBwAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8hAAMiAAgJCCEJAgAAAwAiAAgJCCEJAgAAAwAjAAEJrh+WdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAAALgAECgQJBQABLgAECgYJCwANAAAAAA==.',
Vo='Volkihar:BAAALgADCgMJAwAAAA==.Vordt:BAAALgAECgEJAgAAAA==.',
Wa='Wardaorm:BAAALgAECgYJCgABLgAECgcJGwAKAGMbAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Winden:BAAALgAECgYJEAAAAA==.Wingback:BAAALgADCgEJAQAAAA==.Wiz:BAAALgADCgYJBgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgQJBAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwATAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJBQAAAA==.',
Xh='Xhenshini:BAABLgAECn8uAAMDAAgJRR7mBQBFAgADAAgJHhzmBQBFAgAbAAgJnBqXAgDiAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDQAAAA==.',
Yu='Yums:BAAALgADCgcJBwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJAwAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAMACIMAA==.Zaran:BAAALgADCgYJBgAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMdAAkJtyD6AABaAwAdAAkJ2h36AABaAwAcAAcJISaNDgDgAgAAAA==.',
['Âu']='Âura:BAAALgADCgEJAQAAAA==.',
['Ës']='Ësme:BAAALgADCgcJAgAAAA==.',
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

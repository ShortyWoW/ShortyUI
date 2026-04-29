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

local lookup = {'Druid-Feral','Hunter-BeastMastery','DemonHunter-Havoc','Unknown-Unknown','Druid-Guardian','Druid-Restoration','Warlock-Demonology','DeathKnight-Blood','Priest-Shadow','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Monk-Windwalker','Mage-Frost','Warlock-Affliction','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Hunter-Marksmanship','Evoker-Devastation','Warrior-Fury','Shaman-Enhancement','Evoker-Augmentation','Warrior-Protection','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Hunter-Survival','Priest-Discipline','Priest-Holy','Warrior-Arms',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAAALgAECgYJDgAAAA==.Akumu:BAABLgAECn8bAAIBAAkJYhpSBQC5AgABAAkJYhpSBQC5AgAAAA==.',
Al='Albinah:BAAALgAECgYJCgAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Aldien:BAAALgAECgQJBQAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.',
Ao='Aoe:BAAALgAFFAEJAQAAAA==.',
Ar='Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAAALgAECgYJEAAAAA==.',
Av='Averroes:BAABLgAECn8YAAICAAYJIBKLGAA3AQACAAYJIBKLGAA3AQAAAA==.',
Aw='Awee:BAABLgAECn8wAAIDAAgJACHVCADVAgADAAgJACHVCADVAgABLgAFFAEJAQAEAAAAAA==.Awi:BAAALgADCgUJBQABLgAFFAEJAQAEAAAAAA==.Awo:BAABLgAECn8aAAQFAAcJ7x9NDgCcAQAFAAcJ2B5NDgCcAQABAAYJiBY+FABuAQAGAAQJ8Q0UlACnAAAAAA==.',
Ay='Aylen:BAAALgAECggJEwAAAA==.',
Ba='Bahldrahg:BAAALgAECgMJAwAAAA==.Bahnjek:BAAALgAECgUJBQAAAA==.Banegrim:BAABLgAECn8UAAIHAAYJ1Ar3JwDxAAAHAAYJ1Ar3JwDxAAAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAECgkJGwABAGIaAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAEAAAAAA==.Blindwalker:BAABLgAECn8dAAIIAAgJPA6vCAAAAQAIAAgJPA6vCAAAAQAAAA==.Blissfuleigh:BAAALgAECgIJAQAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgADCgUJBgAEAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgADCggJCgAAAA==.Braistlin:BAAALgADCgIJAgABLgADCgUJBgAEAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBAAAAA==.Brielan:BAAALgAECgYJEQAAAA==.',
Ca='Calon:BAAALgAECgEJAQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8KAAIJAAQJmhsvAQB1AQAJAAQJmhsvAQB1AQAuAAQKfygAAgkACAlOIH8BAG8CAAkACAlOIH8BAG8CAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgEJAQAAAA==.',
Ch='Cheesemonk:BAAALgADCgkJGAABLgAECggJHwAKAHwlAA==.Cheesepally:BAABLgAECn8fAAIKAAgJfCViBwBcAwAKAAgJfCViBwBcAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.',
Cl='Cloud:BAAALgAECgEJAQAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAAALgAECgQJDgAAAA==.',
Da='Dagin:BAABLgAECn8UAAIKAAcJqxbjIAAqAQAKAAcJqxbjIAAqAQAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAAALgAECgYJDQAAAA==.Daorcy:BAAALgADCggJCAAAAA==.Dartherd:BAAALgAECgYJCgAAAA==.Dawnotheholy:BAABLgAECn8jAAMLAAgJqAdLSQBSAQALAAgJqAdLSQBSAQAKAAcJDA8TJwAJAQAAAA==.',
De='Deathstar:BAACLgAFFH8OAAIMAAQJ2h6OAgCIAQAMAAQJ2h6OAgCIAQAuAAQKfycAAwwACQlrIZYNAC4DAAwACQlrIZYNAC4DAA0AAwl+DfsRAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8UAAMHAAcJJRv6UQDSAQAHAAYJ6Rn6UQDSAQAOAAIJ0RLsSACTAAAAAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgAAAA==.Dirtymon:BAAALgADCgMJAwABLgADCgUJBgAEAAAAAA==.',
Dk='Dkfatality:BAABLgAECn8XAAMNAAcJWSLaBAAAAgANAAYJxiDaBAAAAgAMAAYJfyETXQDbAQAAAA==.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgEJAQAAAA==.Dominhoes:BAAALgAECgIJAgAAAA==.Doontless:BAAALgAECgYJCgAAAA==.',
Dr='Draig:BAAALgAECgUJBgAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAPAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAAALgAECgIJAgAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
Eb='Ebonhèart:BAAALgAECgYJDAAAAA==.',
Ec='Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAAALgAECgYJDQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firerage:BAAALgADCgcJDwABLgAECgEJAgAEAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJCgAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Foorsaken:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIQAAYJoRWypwCKAQAQAAYJoRWypwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.',
Fu='Fubu:BAAALgAECgEJAQAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.Gloomy:BAAALgAECgYJCAAAAA==.',
Gr='Grandizzle:BAAALgADCgMJAwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAABLgAECn8kAAIRAAgJXSUNAQD/AgARAAgJXSUNAQD/AgAAAA==.Guruprime:BAAALgADCgMJBAAAAA==.',
Ha='Hagniy:BAABLgAECn8lAAILAAgJGhvTAgBjAgALAAgJGhvTAgBjAgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Happyboy:BAAALgAECgUJCwABLgAECgcJGgAFAO8fAA==.Hardrockcafe:BAAALgADCgMJAwAAAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECggJDgAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAABLgAECn8YAAISAAgJXiElBQD6AgASAAgJXiElBQD6AgAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJCwAAAA==.',
Hr='Hrizul:BAAALgAECgcJEgAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgADCggJCAAAAA==.',
Il='Il:BAABLgAECn8eAAIHAAgJah8sIACXAgAHAAgJah8sIACXAgAAAA==.Illisharr:BAAALgADCggJCgAAAA==.Ilusive:BAAALgAECgYJEQAAAA==.',
Ir='Irazlynaa:BAAALgADCgMJAwAAAA==.Irielyn:BAAALgADCgcJBwAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgQJCAAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn8jAAMTAAgJYh3wFgBeAgATAAcJwx3wFgBeAgAUAAYJvRYwFQDQAAAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAPAEgZAA==.',
Ju='Junö:BAAALgADCgcJEgAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgUJBQAAAA==.Katamine:BAABLgAECn8YAAIVAAYJRRsbCAB0AQAVAAYJRRsbCAB0AQAAAA==.Katoz:BAAALgAECgQJCwAAAA==.',
Ke='Keydron:BAAALgADCgcJDQAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kilemall:BAAALgAECggJAgAAAA==.Killnall:BAAALgAECgQJBwAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8bAAIWAAgJVRcAAgDGAQAWAAgJVRcAAgDGAQAAAA==.',
Kr='Krystarin:BAAALgAECgYJDgAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgMJAwAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgIJAgAAAA==.Lambic:BAAALgADCgMJAwAAAA==.Lanma:BAABLgAECn8XAAIPAAgJSBk8EQBvAgAPAAgJSBk8EQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn8bAAIXAAgJZhxgAABrAgAXAAgJZhxgAABrAgAAAA==.Launcelot:BAABLgAECn8WAAIYAAYJzCL7AwACAgAYAAYJzCL7AwACAgAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgUJBgAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8FAAIJAAIJrhzZBgC5AAAJAAIJrhzZBgC5AAAuAAQKfycAAgkACAm6JWkAAPkCAAkACAm6JWkAAPkCAAAA.Littlezo:BAAALgAFFAIJAwAAAA==.',
Lo='Lotus:BAAALgAECgcJDgAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAECgcJGgAFAO8fAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn8VAAIFAAYJNQo3HADEAAAFAAYJNQo3HADEAAAAAA==.Makpriest:BAAALgADCgQJBQAAAA==.Malakaii:BAABLgAECn8aAAMZAAgJexEXDAAEAgAZAAgJQREXDAAEAgAUAAYJrhK8QgA+AQAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAAALgADCgYJBgAAAA==.Maxdeath:BAAALgAECggJEgAAAA==.Maztajake:BAAALgAECgYJDgAAAA==.',
Me='Melchizedic:BAAALgADCgYJCAAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECggJHgAaAEUbAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAQAAAA==.Mordacity:BAEALgAECgYJCgAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necroknight:BAAALgAECgEJAQAAAA==.Necrotheholy:BAAALgAECgQJCwAAAA==.',
Ng='Nghtíy:BAAALgAECgYJEAAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAAALgAECggJEgAAAA==.Noh:BAAALgAECgEJAQAAAA==.Nordikmage:BAAALgAECgUJBwAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
On='Ondereth:BAAALgAECgUJBQAAAA==.Onthehouse:BAAALgAECgYJCgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJBQAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.',
Pi='Piercey:BAABLgAECn8eAAIbAAgJFR67CgBlAgAbAAgJFR67CgBlAgABLgAECgcJGgAFAO8fAA==.Pinkylove:BAABLgAECn8eAAIGAAgJ8iBRDADcAgAGAAgJ8iBRDADcAgAAAA==.',
Pr='Proera:BAAALgAECgYJBgAAAA==.Promathia:BAACLgAFFH8EAAIKAAIJ0RjfDwCmAAAKAAIJ0RjfDwCmAAAuAAQKfyoAAwoACAkSJOIAAOwCAAoACAkSJOIAAOwCAAsABAkXCBZuAMIAAAAA.',
Pu='Puff:BAAALgAECgMJBgAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAABLgAECn8UAAICAAgJMRYLNQDaAQACAAgJMRYLNQDaAQAAAA==.Rat:BAABLgAECn8jAAIJAAkJSSBzBABOAwAJAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCgMJBAAAAA==.Redrouges:BAAALgAECgYJEQAAAA==.Redwood:BAAALgAECgIJAgAAAA==.Renvskadoosh:BAAALgADCgkJFgABLgAECgYJCwAEAAAAAA==.Rexpanda:BAABLgAECn8YAAIcAAYJ1R1/GgDnAQAcAAYJ1R1/GgDnAQAAAA==.',
Ro='Ross:BAEALgADCgEJAQABLgAFFAMJAwAEAAAAAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
Sa='Sapoude:BAAALgADCgQJBQAAAA==.Sarang:BAAALgADCgUJBAAAAA==.',
Se='Seaursus:BAAALgAECgMJBQAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAEAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJAwAAAA==.Shadowrunner:BAAALgADCgYJBgAAAA==.Shamwich:BAAALgAECgQJCAAAAA==.Shandroz:BAAALgADCgUJBQABLgADCgUJBgAEAAAAAA==.Shaori:BAAALgADCgMJBAAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skullcleaver:BAAALgADCgcJDgAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAAALgAFFAEJAQAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgQJAwAAAA==.',
Sq='Squigglybutt:BAAALgAECgYJCgAAAA==.',
St='Stormbeards:BAAALgADCgYJBgAAAA==.',
Su='Sungchaluka:BAAALgADCgcJDQAAAA==.',
['Sá']='Sásu:BAAALgADCgkJEAAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAAALgADCgYJBgAAAA==.Tars:BAAALgADCgMJBAAAAA==.Tats:BAAALgAECgYJCwAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAAALgAECggJDwAAAA==.Tezguin:BAAALgADCgUJDAAAAA==.',
Th='Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgUJBQAAAA==.Throdwran:BAAALgADCgcJDgABLgAECgcJFAAKAKsWAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8XAAIdAAYJAxmSJQDMAQAdAAYJAxmSJQDMAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJAwAAAA==.Totem:BAAALgAECgUJCAAAAA==.',
Tr='Tranqx:BAABLgAECn8iAAIMAAgJTSalAAALAwAMAAgJTSalAAALAwAAAA==.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8eAAQaAAgJRRuWBADFAQAaAAgJRRuWBADFAQAXAAQJtAYfLgCoAAASAAEJZQPTSgAsAAAAAA==.Trizz:BAAALgADCgMJAwAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.',
Ts='Tsuchiya:BAAALgADCgcJDAAAAA==.',
Up='Uproar:BAAALgAFFAEJAQAAAA==.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAAALgAFFAEJAgABLgAFFAUJDAAeAO0jAA==.Valeskogr:BAABLgAECn8cAAQCAAkJ7Q1dCQDSAQACAAgJTg5dCQDSAQAfAAcJjQglFQB1AQAWAAgJmAMnUQAIAQAAAA==.Varoth:BAAALgADCgkJDwAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Vengefulmilk:BAAALgADCgUJBwAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8YAAMgAAgJlx3RAQBpAgAgAAgJlx3RAQBpAgAhAAEJrh+RdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAAALgAECgIJAgABLgAECggJFgACALYVAA==.',
Vo='Volkihar:BAAALgADCgIJAgAAAA==.Vordt:BAAALgAECgEJAgAAAA==.',
Wa='Wardaorm:BAAALgAECgYJBgABLgAECgcJFAAKAKsWAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Winden:BAAALgAECgUJCgAAAA==.Wingback:BAAALgADCgEJAQAAAA==.Wiz:BAAALgADCgYJBgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAPAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xh='Xhenshini:BAABLgAECn8mAAIXAAgJnBr5AADtAQAXAAgJnBr5AADtAQAAAA==.',
Ye='Yeonguo:BAAALgAECgMJAwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECggJDwAEAAAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8eAAMiAAkJtyD4AABaAwAiAAkJ2h34AABaAwAYAAcJISaNDgDgAgAAAA==.',
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

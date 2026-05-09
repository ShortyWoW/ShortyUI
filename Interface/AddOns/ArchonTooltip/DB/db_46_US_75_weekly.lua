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

local lookup = {'Hunter-Marksmanship','Druid-Feral','Druid-Balance','Evoker-Augmentation','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Monk-Windwalker','Mage-Frost','Priest-Holy','Warlock-Affliction','Evoker-Preservation','Paladin-Protection','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Warrior-Fury','Warrior-Arms','Hunter-Survival','DemonHunter-Vengeance','Priest-Discipline',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Ador:BAAALgADCgMJAwAAAA==.',
Ae='Aeladrel:BAAALgADCggJCAAAAA==.',
Ak='Akirie:BAABLgAECn8aAAIBAAYJDxc9CgBQAQABAAYJDxc9CgBQAQAAAA==.Akumu:BAABLgAECn8dAAMCAAkJYhpUBQC5AgACAAkJYhpUBQC5AgADAAEJAAAyaQAAAAAAAA==.',
Al='Alangi:BAAALgAECgYJDAABLgAECggJLgAEAEUeAA==.Albinah:BAABLgAECn8WAAIFAAYJoh7GDgD/AQAFAAYJoh7GDgD/AQAAAA==.Albsli:BAAALgADCgIJAgAAAA==.Albsygos:BAAALgADCgQJBAAAAA==.Albz:BAAALgADCgkJHAAAAA==.Albzap:BAAALgADCgMJAwAAAA==.Albzu:BAAALgADCgEJAQAAAA==.Aldien:BAAALgAECgYJDAAAAA==.Aliphar:BAAALgADCgEJAQAAAA==.',
Ao='Aoe:BAACLgAFFH8JAAIGAAMJfRDSNADeAAAGAAMJfRDSNADeAAAuAAQKfxMAAgYACQlgEQwgAMgBAAYACQlgEQwgAMgBAAEuAAUUBQkHAAcAQBEA.',
Ar='Arienna:BAAALgAECgMJAwAAAA==.Arteñ:BAAALgAECgUJCQAAAA==.',
As='Ashrak:BAABLgAECn8cAAIIAAcJkwxTDABEAQAIAAcJkwxTDABEAQAAAA==.',
Av='Averroes:BAABLgAECn8oAAIJAAgJzRAuKgCoAQAJAAgJzRAuKgCoAQAAAA==.',
Aw='Awa:BAAALgAECgYJEQABLgAFFAUJBwAHAEARAA==.Awee:BAACLgAFFH8HAAIHAAUJQBEECAAZAQAHAAUJQBEECAAZAQAuAAQKfzgAAgcACAlCIvEEAHACAAcACAlCIvEEAHACAAAA.Awi:BAAALgADCgUJBQABLgAFFAUJBwAHAEARAA==.Awo:BAACLgAFFH8GAAIKAAQJtBacDwBYAQAKAAQJtBacDwBYAQAuAAQKfy8ABAoACAllJUwCAGMDAAoACAllJUwCAGMDAAIABgmIFkAUAG4BAAsACAmCHSsMAE4BAAAA.Awoo:BAAALgAECgYJBwABLgAFFAQJBgAKALQWAA==.',
Ay='Aylen:BAABLgAECn8cAAIMAAgJqQ+TQQCBAQAMAAgJqQ+TQQCBAQAAAA==.',
Ba='Bahldrahg:BAAALgAECgMJAwAAAA==.Baki:BAAALgAFFAIJBAABLgAFFAMJCwANANQhAA==.Banegrim:BAABLgAECn8kAAIOAAgJsguJQQBlAQAOAAgJsguJQQBlAQAAAA==.Barnbirt:BAAALgAECgEJAQAAAA==.Barron:BAAALgAECgIJAgAAAA==.Barronthee:BAAALgAECgIJAgAAAA==.Battlecat:BAAALgAECgcJBwAAAA==.',
Be='Beelzebubx:BAAALgAECgQJBAABLgAECgkJHQACAGIaAA==.Belysiuh:BAAALgAECgMJAwAAAA==.',
Bl='Blackdaisydr:BAAALgADCgcJDQABLgAECgYJCwAPAAAAAA==.Blindwalker:BAABLgAECn8hAAIQAAkJeQ2SEwA9AQAQAAkJeQ2SEwA9AQAAAA==.Blissfuleigh:BAAALgAECgIJAwAAAA==.',
Bo='Boldius:BAAALgADCgQJBAABLgAECgMJAwAPAAAAAA==.Bookchin:BAAALgADCgEJAQAAAA==.',
Br='Bragdand:BAEALgADCgkJFgAAAA==.Braistlin:BAAALgADCgIJAgABLgAECgMJAwAPAAAAAA==.Bred:BAAALgADCgcJBwAAAA==.Brewfest:BAAALgADCgMJBgAAAA==.Briarthorn:BAAALgAECgYJBgAAAA==.Brielan:BAAALgAECgYJEQAAAA==.',
Ca='Cadillacbob:BAAALgAECgEJAQAAAA==.Calon:BAAALgAECgQJBQAAAA==.Cantseedizz:BAAALgADCgMJAwAAAA==.Castigate:BAACLgAFFH8TAAINAAUJdiCpBACWAQANAAUJdiCpBACWAQAuAAQKfysAAg0ACAkqIccFAH4CAA0ACAkqIccFAH4CAAAA.',
Ce='Cederek:BAAALgADCgIJAgAAAA==.Ceresarian:BAAALgADCgMJAwAAAA==.',
Ch='Chancho:BAAALgADCgcJBwABLgAECggJJQALAN4RAA==.Cheesemonk:BAAALgADCgkJIQABLgAECggJLwAMAJ8mAA==.Cheesepally:BAABLgAECn8vAAIMAAgJnyb3AwAUAwAMAAgJnyb3AwAUAwAAAA==.Cheesewhelp:BAAALgADCgcJBwAAAA==.Chikoung:BAAALgADCgUJBQAAAA==.',
Cl='Cloud:BAAALgAECgcJCQAAAA==.',
Co='Coderictond:BAAALgADCgQJBgAAAA==.Cogpally:BAAALgADCggJCAAAAA==.',
Cr='Crysa:BAAALgADCgYJBgAAAA==.',
Cy='Cygnus:BAABLgAECn8ZAAMRAAYJIAw3DAD5AAARAAUJfwY3DAD5AAASAAUJ0g2CIwDeAAAAAA==.Cylla:BAAALgAECgYJDAABLgAFFAMJCgAMAJMaAA==.',
Da='Daddywarbuks:BAAALgAECgUJBgAAAA==.Dagin:BAABLgAECn8fAAIMAAgJARuCGwAjAgAMAAgJARuCGwAjAgAAAA==.Dalarenaric:BAAALgADCgcJDAAAAA==.Dalt:BAAALgAFFAEJAQAAAA==.Daltonator:BAAALgADCgMJAwAAAA==.Dantemore:BAAALgAECgYJEwAAAA==.Daorcy:BAAALgADCggJDgAAAA==.Dartherd:BAABLgAECn8WAAITAAYJWBlTDwBuAQATAAYJWBlTDwBuAQAAAA==.Dawnotheholy:BAABLgAECn8wAAMUAAgJnA25HQCZAQAUAAgJnA25HQCZAQAMAAcJDA96egD3AAAAAA==.',
De='Deathstar:BAACLgAFFH8YAAMVAAUJGB/2FAB/AQAVAAQJGB/2FAB/AQAQAAEJAACZKQAAAAAuAAQKfygAAxUACQkyI5QNAC4DABUACQkyI5QNAC4DABYAAwl+Df8RAHEAAAAA.Demonbunz:BAAALgADCgUJBwAAAA==.Derregar:BAABLgAECn8UAAMOAAcJJRv3UQDSAQAOAAYJ6Rn3UQDSAQAXAAIJ0RLwSACTAAAAAA==.',
Di='Dibella:BAAALgADCgYJAwAAAA==.Dirtydrago:BAAALgADCgUJBgABLgAECgMJAwAPAAAAAA==.Dirtymon:BAAALgADCgMJAwABLgAECgMJAwAPAAAAAA==.',
Dk='Dkfatality:BAACLgAFFH8KAAMWAAMJcR1TAwAVAQAWAAMJcR1TAwAVAQAVAAEJow5MVABPAAAuAAQKfyMAAxYABwk0JGYCABwCABYABwkyJGYCABwCABUABgl/IQRdANsBAAAA.',
Dl='Dlord:BAAALgADCgYJCAAAAA==.',
Do='Dock:BAAALgAECgQJCQAAAA==.Dominhoes:BAAALgAECgQJCgAAAA==.Doontless:BAAALgAECgYJEQAAAA==.',
Dr='Draig:BAAALgAECgYJDgAAAA==.Dratini:BAAALgADCggJBwABLgAECggJFwAYAEgZAA==.Drozigg:BAAALgADCgYJCQAAAA==.',
Du='Duckfury:BAAALgAECgYJCgAAAA==.Dummy:BAAALgADCgYJBgAAAA==.Dunzoboom:BAAALgADCgcJCwAAAA==.Dunzö:BAAALgADCgYJBgAAAA==.',
Eb='Ebonhèart:BAAALgAECgYJEwAAAA==.',
Ec='Ecliptic:BAAALgAECgQJDQAAAA==.',
Eg='Eggle:BAAALgADCgIJAgAAAA==.',
Ei='Eisenheim:BAAALgADCgIJAgAAAA==.',
El='Electronvolt:BAAALgAECggJEQAAAA==.Eleidie:BAAALgADCgEJAQAAAA==.Elia:BAAALgAECgEJAQAAAA==.',
Ex='Exíled:BAAALgAECgEJAQAAAA==.',
Fa='Fallenlegion:BAAALgADCgcJBwAAAA==.Fartwizard:BAAALgAECgMJBQAAAA==.',
Fe='Felskerri:BAAALgADCgYJBgAAAA==.Fenus:BAAALgADCgIJAgAAAA==.',
Fi='Firebelly:BAAALgAECgMJAwAAAA==.Firerage:BAAALgADCgcJDwABLgAECgEJAgAPAAAAAA==.',
Fl='Flacidmonkey:BAAALgAECgcJDwAAAA==.Flufflenuzs:BAAALgAECgEJAQAAAA==.',
Fo='Fors:BAAALgAECgQJBAAAAA==.Forsäken:BAABLgAECn8VAAIZAAYJoRWspwCKAQAZAAYJoRWspwCKAQAAAA==.Forumangel:BAAALgADCgYJCQAAAA==.',
Fr='Freya:BAAALgADCgUJBQAAAA==.Frombehind:BAAALgAECgYJCgABLgAFFAUJFwAVAGcaAA==.',
Fu='Fubu:BAAALgAECgIJAgAAAA==.',
Ga='Gabenson:BAAALgADCgQJBAAAAA==.',
Gl='Glizzylatte:BAAALgADCgYJBgABLgAECgYJCwAPAAAAAA==.Gloomy:BAABLgAECn8UAAIaAAYJLiJBCgBEAgAaAAYJLiJBCgBEAgAAAA==.',
Gr='Grandizzle:BAAALgAECgYJBwAAAA==.',
Gu='Gumbi:BAAALgAECgIJAgAAAA==.Gumgum:BAACLgAFFH8GAAIbAAIJoyYkAgDpAAAbAAIJoyYkAgDpAAAuAAQKfysAAhsACAktJg0BAP8CABsACAktJg0BAP8CAAAA.Guruprime:BAAALgADCgMJBAAAAA==.',
Gw='Gwalla:BAAALgADCgkJEAABLgAECgMJBQAPAAAAAA==.',
Ha='Hagniy:BAABLgAECn85AAIUAAgJFx/rBQDEAgAUAAgJFx/rBQDEAgAAAA==.Hakunamatata:BAAALgADCgUJBQAAAA==.Halten:BAAALgAECgkJBwAAAA==.Happyboy:BAABLgAECn8UAAQKAAYJjR/aFAAhAgAKAAYJjR/aFAAhAgALAAYJdw8nEgDmAAACAAEJnRODJQA7AAABLgAFFAQJBgAKALQWAA==.Hardrockcafe:BAAALgADCgYJAwAAAA==.Harfu:BAAALgAECgIJAgAAAA==.Hartzdrell:BAAALgADCgUJCQAAAA==.',
He='Healmedaddy:BAAALgADCgEJAQAAAA==.Helbrandt:BAAALgAECgMJAwAAAA==.Heldarram:BAAALgAECggJEAAAAA==.Hemaroid:BAAALgADCgcJBwAAAA==.Heolt:BAEALgADCgUJBQABLgADCgkJFgAPAAAAAA==.Hestia:BAAALgAECgUJBgAAAA==.Hexra:BAACLgAFFH8GAAIcAAMJnBjNEQD1AAAcAAMJnBjNEQD1AAAuAAQKfxoAAhwACAkgIiUFAPoCABwACAkgIiUFAPoCAAAA.Heyzus:BAAALgAECgQJBgAAAA==.',
Ho='Honnok:BAAALgAECgQJBAAAAA==.Hoofweaver:BAAALgAECgUJBQAAAA==.Hornyhead:BAAALgAECgQJDQAAAA==.Howard:BAAALgADCgIJAgAAAA==.',
Hr='Hrizul:BAABLgAECn8aAAMdAAgJ8hpYCADIAQAdAAgJ8hpYCADIAQAMAAIJNQvLwQByAAAAAA==.',
Ib='Iblameheals:BAAALgADCgMJBAAAAA==.',
Ic='Icebarron:BAAALgAECgYJCwAAAA==.',
Il='Il:BAABLgAECn8iAAIOAAkJtx4rIACXAgAOAAkJtx4rIACXAgAAAA==.Illisharr:BAAALgADCggJEQAAAA==.Ilusive:BAABLgAECn8bAAIeAAgJsA4FHQBlAQAeAAgJsA4FHQBlAQAAAA==.',
Ir='Irazlynaa:BAAALgADCgUJDQAAAA==.Irielyn:BAAALgADCgcJBwAAAA==.Ironblight:BAAALgAECgEJAQAAAA==.Irrah:BAAALgAECgYJDwAAAA==.',
Is='Ishal:BAAALgADCgEJAQAAAA==.',
Ja='Jabar:BAAALgADCgEJAQAAAA==.Jagz:BAABLgAECn8xAAMfAAkJThzrFgBeAgAfAAgJgBzrFgBeAgAeAAcJVBoFIQBIAQAAAA==.',
Jh='Jharael:BAAALgADCgUJBwAAAA==.',
Jo='Jonsi:BAAALgADCgUJBQABLgAECggJFwAYAEgZAA==.',
Ju='Junö:BAAALgADCgcJEgAAAA==.Jursh:BAAALgADCgQJBAAAAA==.',
Ka='Kaelen:BAAALgAECgUJCQAAAA==.Kaley:BAAALgADCgIJAgAAAA==.Katamine:BAABLgAECn8mAAIDAAgJoRklDQD5AQADAAgJoRklDQD5AQAAAA==.Katoz:BAABLgAECn8TAAMVAAYJwh1rOgCQAQAVAAYJwh1rOgCQAQAWAAIJTRYsEgBuAAAAAA==.Kawas:BAAALgAECgYJBgAAAA==.',
Ke='Keydron:BAAALgADCggJDwAAAA==.',
Kh='Khài:BAAALgAECgQJBQAAAA==.',
Ki='Kilemall:BAAALgAECggJAgAAAA==.Killnall:BAAALgAECgYJEgAAAA==.Kiyohime:BAAALgAECgIJAgAAAA==.',
Kj='Kjadmina:BAAALgADCgUJBAAAAA==.',
Kl='Kladon:BAABLgAECn8gAAIBAAkJJRoYAwAzAgABAAkJJRoYAwAzAgAAAA==.',
Ko='Konantheduck:BAAALgADCgIJAgAAAA==.',
Kr='Krystarin:BAABLgAECn8aAAIKAAYJxRr/HgDMAQAKAAYJxRr/HgDMAQAAAA==.Kryx:BAAALgADCgkJEAAAAA==.Kráytos:BAAALgAECgQJBwAAAA==.',
Ky='Kynria:BAAALgAECgIJAwAAAA==.',
La='Lallaure:BAAALgADCgQJBAAAAA==.Lambic:BAAALgAECgQJBAAAAA==.Lanma:BAABLgAECn8XAAIYAAgJSBk8EQBvAgAYAAgJSBk8EQBvAgAAAA==.Larpgodx:BAAALgAECgIJAwAAAA==.Lastoran:BAAALgAECgMJBQAAAA==.Lateralus:BAABLgAECn8sAAIgAAkJex2lAADcAgAgAAkJex2lAADcAgAAAA==.Launcelot:BAABLgAECn8dAAMhAAcJRCLbEADsAQAhAAYJ9SLbEADsAQAiAAQJQR9rDQBrAQAAAA==.Laurasecord:BAAALgADCgQJBAAAAA==.Lazymage:BAAALgAECgUJBgAAAA==.',
Le='Leanbeef:BAAALgAECgYJBgAAAA==.Leshy:BAAALgADCgYJBgAAAA==.',
Li='Lights:BAACLgAFFH8LAAINAAMJ1CFfDgAoAQANAAMJ1CFfDgAoAQAuAAQKfzoAAg0ACQntJUoAAIQDAA0ACQntJUoAAIQDAAAA.Littlezo:BAACLgAFFH8FAAIjAAMJWxBsEADwAAAjAAMJWxBsEADwAAAuAAQKfxsAAiMACQn8JFUAAGcDACMACQn8JFUAAGcDAAAA.',
Lo='Lotus:BAABLgAECn8dAAMYAAgJKBZwDQDhAQAYAAgJKBZwDQDhAQAFAAYJ5gz1OAAFAQAAAA==.',
Lt='Ltrnck:BAAALgADCgIJAgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckbound:BAAALgAECgEJAQABLgAFFAQJBgAKALQWAA==.Luthonys:BAAALgADCgEJAQAAAA==.',
Ma='Magond:BAAALgAECgIJAgAAAA==.Makoha:BAABLgAECn8lAAILAAgJ3hHyCgBoAQALAAgJ3hHyCgBoAQAAAA==.Makpriest:BAAALgADCgQJBwAAAA==.Malakaii:BAABLgAECn8aAAMIAAgJexEXDAAEAgAIAAgJQREXDAAEAgAeAAYJrhLDQgA+AQAAAA==.Mariahh:BAAALgADCgEJAQAAAA==.Masherkillu:BAAALgAECgUJEgAAAA==.Masherpally:BAAALgAECgEJAQAAAA==.Maxdeath:BAABLgAECn8ZAAIZAAgJYBBKgADQAQAZAAgJYBBKgADQAQAAAA==.Maztajake:BAAALgAECgYJEAAAAA==.Mazzyjake:BAAALgAECgQJBAABLgAECgYJEAAPAAAAAA==.',
Me='Medorh:BAAALgADCgYJBgAAAA==.Melchizedic:BAAALgAECgEJAQAAAA==.Merily:BAAALgADCgQJBAAAAA==.',
Mi='Mikeytott:BAAALgADCgQJBQAAAA==.Minnie:BAAALgAECgEJAQABLgAECgkJIQAEAPIZAA==.',
Mo='Mohgmoment:BAAALgADCgYJBgAAAA==.Moonfare:BAAALgADCgEJAgAAAA==.Mordacity:BAEBLgAECn8WAAIkAAYJTgcEEQCyAAAkAAYJTgcEEQCyAAAAAA==.',
Mu='Muris:BAAALgAECgQJBAAAAA==.',
['Mä']='Määt:BAAALgADCgIJAgAAAA==.',
Na='Nardo:BAAALgAECgEJAQAAAA==.',
Ne='Necroknight:BAAALgAECgEJAQAAAA==.Necrotheholy:BAAALgAECgQJDQAAAA==.',
Ng='Nghtíy:BAABLgAECn8WAAIVAAYJPxMHWgAyAQAVAAYJPxMHWgAyAQAAAA==.',
Ni='Nixa:BAAALgADCgUJBQAAAA==.',
No='Nocturnüs:BAABLgAECn8eAAINAAkJlg7DEQC7AQANAAkJlg7DEQC7AQAAAA==.Noh:BAAALgAECgEJAQAAAA==.Nordikmage:BAAALgAECgYJEwAAAA==.Nort:BAAALgADCgEJAQAAAA==.Nov:BAAALgADCgMJAwAAAA==.',
On='Ondereth:BAAALgAECgUJCgAAAA==.Onthehouse:BAAALgAECgYJDgAAAA==.',
Or='Orid:BAAALgADCgcJBwAAAA==.Orvannan:BAAALgADCgQJBgAAAA==.',
Pa='Pacho:BAAALgADCgUJBQAAAA==.Palimorea:BAEALgADCgUJBgABLgADCgkJFgAPAAAAAA==.',
Pi='Piercey:BAACLgAFFH8FAAITAAIJORu6EQChAAATAAIJORu6EQChAAAuAAQKfyIAAhMACAmGHroKAGUCABMACAmGHroKAGUCAAEuAAUUBAkGAAoAtBYA.Pinkylove:BAABLgAECn8eAAIKAAgJ8iBNDADcAgAKAAgJ8iBNDADcAgAAAA==.',
Pr='Proera:BAAALgAECgcJBwAAAA==.Promathia:BAACLgAFFH8KAAIMAAMJkxpwKgAFAQAMAAMJkxpwKgAFAQAuAAQKfzsAAwwACQnwJA4BAGwDAAwACQnwJA4BAGwDABQABAkXCB5uAMIAAAAA.Pross:BAAALgADCgMJBAABLgAECggJHwAMAAEbAA==.',
Pu='Puff:BAAALgAECggJDQAAAA==.',
Ra='Raenori:BAAALgADCgYJBgAAAA==.Ragnarolk:BAAALgAECgIJAgAAAA==.Raiyuden:BAAALgAECgEJAQAAAA==.Randydaytona:BAAALgAECgYJCwAAAA==.Rangërdangër:BAACLgAFFH8KAAIJAAQJ2wVvHgAeAQAJAAQJ2wVvHgAeAQAuAAQKfxYAAgkACQkQFQg1ANoBAAkACQkQFQg1ANoBAAAA.Rat:BAABLgAECn8jAAINAAkJSSBzBABOAwANAAkJSSBzBABOAwAAAA==.',
Re='Rectumus:BAAALgADCgUJCQAAAA==.Redrouges:BAABLgAECn8ZAAISAAgJqh51BACCAgASAAgJqh51BACCAgAAAA==.Redwood:BAAALgAECgIJAgAAAA==.Renvskadoosh:BAAALgADCgkJGQAAAA==.Revhero:BAAALgADCgcJBwAAAA==.Rexpanda:BAABLgAECn8YAAIFAAYJ1R18GgDmAQAFAAYJ1R18GgDmAQAAAA==.',
Ro='Ross:BAEALgADCgEJAQABLgAFFAQJDAAhAOweAA==.Rotlord:BAAALgAECgYJCgAAAA==.',
Ru='Ruckus:BAAALgAECgUJBQABLgAECgYJEAAPAAAAAA==.Rumble:BAAALgAECgEJAQAAAA==.Rumrootbeer:BAAALgADCgIJAQAAAA==.',
['Rë']='Rëkz:BAAALgAECgMJAwAAAA==.',
Sa='Sapoude:BAAALgAECgEJAQAAAA==.Sarang:BAAALgADCgYJBgAAAA==.',
Se='Seaursus:BAAALgAECgMJCAAAAA==.Seerblade:BAAALgADCgcJCgABLgAECgYJCwAPAAAAAA==.Sekaiju:BAAALgAECgQJBgAAAA==.Selakin:BAAALgADCgIJAgAAAA==.',
Sh='Shadowbann:BAAALgAECgMJAwAAAA==.Shadowrunner:BAAALgADCgYJCAAAAA==.Shamwich:BAAALgAECggJEAAAAA==.Shandroz:BAAALgAECgMJAwAAAA==.Shaori:BAAALgADCgMJBAAAAA==.Shrkbait:BAAALgAECgMJBgAAAA==.',
Sk='Skeezicks:BAAALgADCgUJBQAAAA==.Skidoosh:BAAALgAECgEJAgAAAA==.Skullcleaver:BAAALgADCgcJFAAAAA==.',
Sl='Slycc:BAAALgAECgMJAwAAAA==.',
Sm='Smackerr:BAAALgADCgUJBgAAAA==.',
Sn='Sneakay:BAAALgAFFAIJAwAAAA==.Sneakybiter:BAAALgADCgcJDQAAAA==.',
So='Solei:BAAALgAECgUJBQAAAA==.Southernguy:BAAALgAECgMJBAAAAA==.',
Sp='Spazzies:BAAALgAECgUJBgAAAA==.',
Sq='Squigglybutt:BAABLgAECn8VAAMaAAcJixBCHABnAQAaAAcJixBCHABnAQAlAAEJGQTTTQAmAAAAAA==.',
St='Steelwing:BAAALgAECggJDQABLgAECgkJHQACAGIaAA==.Stormbeards:BAAALgADCgYJBgAAAA==.Stoutkeg:BAAALgADCgQJAwAAAA==.Strrawberry:BAAALgADCgIJAgAAAA==.',
Su='Sungchaluka:BAAALgAECgEJAQAAAA==.',
['Sá']='Sásu:BAAALgADCgkJEAAAAA==.',
Ta='Talsomething:BAAALgAFFAEJAgAAAA==.Talsumthing:BAAALgAFFAQJBAAAAA==.Tars:BAAALgAECgYJBgAAAA==.Tats:BAABLgAECn8WAAIMAAcJsxZ7NQCnAQAMAAcJsxZ7NQCnAQAAAA==.',
Te='Terraxic:BAAALgAECgYJDAAAAA==.Terthaith:BAABLgAECn8YAAIOAAkJIgziKgC5AQAOAAkJIgziKgC5AQAAAA==.Tezguin:BAAALgADCgYJDQAAAA==.',
Th='Theedemon:BAAALgAECgQJBAAAAA==.Theironie:BAAALgADCgYJBgAAAA==.Theparttimer:BAAALgADCgEJAQAAAA==.Thiccpie:BAAALgAECgUJBQAAAA==.Throdwran:BAAALgAECgMJAwABLgAECggJHwAMAAEbAA==.',
Ti='Timba:BAAALgAECgYJCAAAAA==.Tisaka:BAABLgAECn8aAAISAAYJAxmUJQDMAQASAAYJAxmUJQDMAQAAAA==.',
Tl='Tlovexx:BAAALgAFFAEJAQAAAA==.',
To='Tolya:BAAALgADCgEJAQAAAA==.Toohbooh:BAAALgAECgMJBgAAAA==.Totem:BAAALgAECgUJCAAAAA==.',
Tr='Tranqx:BAACLgAFFH8LAAMVAAMJuyTAMAA+AQAVAAMJGSTAMAA+AQAWAAIJpyEnBQDPAAAuAAQKfysAAxUACQm3JhAGAPsCABUACAmuJhAGAPsCABYAAQn3JiMQAHUAAAAA.Treevlo:BAAALgADCgEJAQAAAA==.Treva:BAABLgAECn8hAAQEAAkJ8hlzCwAUAgAEAAkJ8hlzCwAUAgAgAAQJtAYhLgCoAAAcAAEJZQPaSgAsAAAAAA==.Trizz:BAAALgAECgQJBAAAAA==.Troctzul:BAAALgADCgEJAwAAAA==.',
Ts='Tsuchiya:BAAALgAECgYJBgAAAA==.',
Tu='Tuts:BAAALgADCgYJDAAAAA==.',
Up='Uproar:BAABLgAECn8hAAIWAAkJBCUqAABfAwAWAAkJBCUqAABfAwAAAA==.',
Va='Vaelira:BAAALgADCgkJCQAAAA==.Vahlfi:BAABLgAFFH8EAAIGAAIJMBvAQQCkAAAGAAIJMBvAQQCkAAABLgAFFAUJFAARAO4lAA==.Valemon:BAAALgAFFAEJAQAAAA==.Valeskogr:BAABLgAECn8dAAQJAAkJ7Q1OKQCsAQAJAAgJTg5OKQCsAQAjAAcJjQglFQB1AQABAAgJmANtUAAMAQAAAA==.Valffi:BAAALgAECgYJBgABLgAFFAUJFAARAO4lAA==.Varoth:BAAALgAECgEJAQAAAA==.Varus:BAAALgAECgYJCQAAAA==.',
Ve='Vengefulmilk:BAAALgAECgMJAwAAAA==.Venture:BAAALgADCgkJIgAAAA==.Vergo:BAAALgADCgEJAQAAAA==.Vescovo:BAABLgAECn8iAAMlAAkJDiDpAQBHAwAlAAkJDiDpAQBHAwAaAAEJrh+cdABWAAAAAA==.',
Vi='Virde:BAAALgADCgMJAwAAAA==.',
Vl='Vll:BAAALgAECggJDgABLgAECgcJIAACAOsfAA==.',
Vo='Volkihar:BAAALgADCgMJAwAAAA==.Vordt:BAAALgAECgIJBQAAAA==.',
Wa='Wardaorm:BAAALgAECgYJEQABLgAECggJHwAMAAEbAA==.Warkinz:BAAALgADCgQJBQAAAA==.Warlin:BAAALgAECgEJAQAAAA==.',
Wi='Willohh:BAAALgAECgQJBAAAAA==.Winden:BAABLgAECn8WAAIIAAYJhhtICQCKAQAIAAYJhhtICQCKAQAAAA==.Wingback:BAAALgADCgEJAQAAAA==.Wiz:BAAALgADCgYJBgAAAA==.',
Wp='Wphoenix:BAAALgAECgQJBAAAAA==.',
Wr='Wrizz:BAAALgADCgQJBAAAAA==.',
Wt='Wtfsteve:BAAALgADCgUJBQABLgAECggJFwAYAEgZAA==.',
Xa='Xadrai:BAAALgAECgYJCwAAAA==.',
Xe='Xeplin:BAAALgAECgUJBQAAAA==.',
Xh='Xhenshini:BAABLgAECn8uAAMEAAgJRR65CABEAgAEAAgJHhy5CABEAgAgAAgJnBqoAwDXAQAAAA==.',
Ye='Yeonguo:BAAALgAECgYJDgAAAA==.',
Yu='Yums:BAAALgADCgcJBwAAAA==.',
Za='Zalethe:BAAALgAECgMJAwAAAA==.Zalliel:BAAALgADCggJCAAAAA==.Zalman:BAAALgAECgMJAwAAAA==.Zaphíel:BAAALgADCgcJBwABLgAECgkJGAAOACIMAA==.Zaran:BAAALgADCgYJBgAAAA==.',
Ze='Zeninnaoya:BAABLgAECn8fAAMiAAkJtyD6AABaAwAiAAkJ2h36AABaAwAhAAcJISaGDgDgAgAAAA==.',
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

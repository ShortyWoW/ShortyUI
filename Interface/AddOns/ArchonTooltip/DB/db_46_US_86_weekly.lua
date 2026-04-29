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

local lookup = {'Warrior-Fury','Unknown-Unknown','Priest-Discipline','Monk-Mistweaver','Paladin-Retribution','Hunter-BeastMastery','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Mage-Frost','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Rogue-Outlaw','Shaman-Restoration','Druid-Guardian','Warrior-Protection','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Priest-Holy','Warrior-Arms',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acharon:BAABLgAECn8UAAIBAAYJXAyZEAAlAQABAAYJXAyZEAAlAQAAAA==.',
Ad='Adrastus:BAAALgAECgUJCwAAAA==.',
Ae='Aeslin:BAAALgADCgcJEwABLgAECgYJDgACAAAAAA==.',
Ah='Ahsoka:BAAALgAECgUJCAAAAA==.',
Ai='Ain:BAAALgAFFAEJAQAAAA==.Ainslie:BAAALgAECgYJBgAAAA==.',
Al='Alarashinu:BAAALgAECgUJCgAAAA==.Alataris:BAAALgADCgQJBAAAAA==.Alawae:BAAALgAECgYJEQAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAAALgAECgcJEAAAAA==.',
An='Anahit:BAAALgADCgUJBQAAAA==.Angela:BAAALgADCgcJEAABLgAECggJHAADAHoQAA==.',
Ar='Araedia:BAAALgAECgYJCAABLgAECgcJEgACAAAAAA==.Arahant:BAACLgAFFH8FAAIEAAMJGxNwCACXAAAEAAMJGxNwCACXAAAuAAQKfyIAAgQACAmbHf8MAIQCAAQACAmbHf8MAIQCAAAA.Aretas:BAAALgAECgYJEAABLgAECggJCgACAAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.',
As='Asifa:BAAALgAECgMJBAAAAA==.Astinds:BAAALgADCgMJBQAAAA==.',
At='Atherion:BAAALgAECgYJEQAAAA==.',
Au='Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Avranarada:BAAALgAECgcJEgAAAA==.',
Az='Azung:BAABLgAECn8VAAIFAAgJzhwrIwCcAgAFAAgJzhwrIwCcAgAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8JAAIGAAMJBheTCgANAQAGAAMJBheTCgANAQAuAAQKfyQAAgYACAn0ItQIAAUDAAYACAn0ItQIAAUDAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAAALgAECgYJEwAAAA==.Baka:BAABLgAECn8fAAMHAAcJvCFXAwBQAgAHAAcJvCFXAwBQAgAFAAYJNBCikQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAAALgAECgYJDwAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8GAAIIAAMJlgpjEAD0AAAIAAMJlgpjEAD0AAAuAAQKfyAAAwgACAkeHwUuAIACAAgABwntIgUuAIACAAkAAQlICMQUADEAAAAA.Baragohn:BAAALgADCgYJBgAAAA==.Barb:BAAALgADCgMJBgAAAA==.Barrelrollin:BAAALgAECgUJBQAAAA==.Batrito:BAABLgAECn8cAAMDAAgJehAVHAC1AQADAAgJehAVHAC1AQAKAAcJkQydEQDeAAAAAA==.Bawchu:BAAALgADCgYJBgAAAA==.',
Be='Bealzebubbà:BAAALgAECgMJBQAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAAALgAECgYJDwAAAA==.Bethlahammer:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.',
Bi='Bigboom:BAAALgADCgQJBAAAAA==.Billcosbrew:BAABLgAECn8fAAILAAgJQyUWBABLAwALAAgJQyUWBABLAwAAAA==.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAQAAAA==.',
Bl='Blackleaf:BAAALgADCgkJHQAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blizzcon:BAABLgAECn8bAAIDAAcJYRI3HgCiAQADAAcJYRI3HgCiAQAAAA==.',
Bo='Borrgar:BAAALgAECgYJDwAAAA==.',
Br='Brackle:BAABLgAECn8XAAIGAAYJnCI3DgCTAQAGAAYJnCI3DgCTAQAAAA==.Bracori:BAACLgAFFH8FAAIEAAMJcQoLBwDHAAAEAAMJcQoLBwDHAAAuAAQKfyIAAwQACAkAEOUnAHcBAAQACAkAEOUnAHcBAAwABgn0DP03AD4BAAAA.Brandywynne:BAABLgAECn8cAAIGAAgJjA4jPAC+AQAGAAgJjA4jPAC+AQAAAA==.Brick:BAABLgAECn8YAAINAAgJLx1EAQBgAgANAAgJLx1EAQBgAgAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Brightfame:BAABLgAECn8fAAMOAAgJhBq0AAADAgAOAAgJLBi0AAADAgAPAAYJ8huaCAC/AQAAAA==.Bronny:BAAALgADCgMJAwAAAA==.Brownpepperz:BAAALgADCgEJAQAAAA==.',
Bu='Bubblebull:BAAALgADCgcJDAAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Butterbllz:BAAALgAECggJEwAAAA==.',
Ca='Caius:BAAALgADCgUJCAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAAALgAECgYJDwAAAA==.Camany:BAAALgAECgYJCAAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAMJBgAKAKUMAA==.Caretakerz:BAAALgAECgQJCgAAAA==.Cartus:BAAALgAECgYJEQAAAA==.',
Ce='Cedre:BAAALgADCgQJDAAAAA==.Celidoria:BAAALgAECggJEgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Cheesepuff:BAABLgAECn8UAAIQAAYJigkEJQACAQAQAAYJigkEJQACAQAAAA==.Chikara:BAAALgAECgQJBQAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgADCgYJBgABLgAFFAMJBwARAAgbAA==.Cinnibar:BAAALgADCgYJBgAAAA==.Cirï:BAAALgAECgYJDAAAAA==.Cisbick:BAAALgAECgYJDwAAAA==.',
Cl='Clamshell:BAABLgAECn8aAAIIAAcJfSHcCQDgAQAIAAcJfSHcCQDgAQAAAA==.Clayier:BAAALgAECgIJAwAAAA==.',
Cn='Cntendr:BAAALgAECgEJAgAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAAALgAECgUJCQAAAA==.Corbanite:BAAALgADCgkJEQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDgAAAA==.Covertyqt:BAABLgAECn8aAAIRAAcJ3x6JCAAfAgARAAcJ3x6JCAAfAgAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn8aAAIIAAcJ+xTDEQCGAQAIAAcJ+xTDEQCGAQAAAA==.',
Cr='Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgADCgEJAQAAAA==.',
Da='Daboof:BAAALgADCgcJFAAAAA==.Daemandred:BAAALgADCgUJBQAAAA==.Daggere:BAAALgAECgEJAgAAAA==.Damaged:BAAALgAECgMJAwAAAA==.Damian:BAAALgAECgIJAgABLgAECgYJCgACAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAAALgAECgYJBwAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darkenmicky:BAAALgAECgYJEQAAAA==.Darkmickyz:BAAALgAECgMJAwAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8GAAIFAAMJiAbNCwDYAAAFAAMJiAbNCwDYAAAuAAQKfyIAAgUACAmMIGcYANYCAAUACAmMIGcYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAECgYJBgABLgAECgkJBAACAAAAAA==.Dayloc:BAABLgAECn8aAAIQAAcJ5g2xGgBAAQAQAAcJ5g2xGgBAAQAAAA==.',
De='Deataria:BAAALgADCgUJBQAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Delryth:BAAALgAECgMJAgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8aAAISAAcJWx3iBgAfAgASAAcJWx3iBgAfAgAAAA==.Dirtyd:BAAALgAECgEJAgAAAA==.Dirtydeeds:BAABLgAECn8ZAAIIAAgJSwiDlABXAQAIAAgJSwiDlABXAQAAAA==.Divinetism:BAAALgAECgUJBwAAAA==.',
Dl='Dl:BAABLgAECn8hAAIKAAgJhBwAAwARAgAKAAgJhBwAAwARAgAAAA==.',
Dr='Draekbee:BAABLgAECn8kAAQTAAgJFxW0BwBzAQAUAAYJZBiPFACfAQATAAgJkBG0BwBzAQAVAAEJwwddSgAtAAAAAA==.Dragkohn:BAAALgAECgQJBAABLgAECgcJFgAHABMlAA==.Dragonaged:BAAALgADCgMJAwAAAA==.Drakkarr:BAAALgADCgUJCQAAAA==.Drimbirt:BAAALgADCgkJGgAAAA==.Drinkmormilk:BAAALgAECgMJBAAAAA==.Drogman:BAAALgADCgcJEAAAAA==.Droowin:BAAALgAECgEJAQABLgAECgUJBQACAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgEJAQAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAAALgAECgUJBQAAAA==.',
Ed='Edensfury:BAAALgADCggJCwABLgAECgEJAQACAAAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAAALgAECgcJDwAAAA==.',
Ek='Ekthelion:BAAALgAECgYJEQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8WAAIOAAYJnh8xCgAbAgAOAAYJnh8xCgAbAgAAAA==.Eleyert:BAABLgAECn8XAAIWAAcJxyOyAQBkAgAWAAcJxyOyAQBkAgAAAA==.Elwe:BAAALgAECgYJEAAAAA==.',
Em='Emmaga:BAAALgAECgUJBgAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAAALgAECgYJDwAAAA==.Enseth:BAAALgAECgYJDQAAAA==.',
Er='Erotikzombie:BAAALgAECgQJDwAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAAALgAECgMJBAABLgAECgcJGwADAGESAA==.',
Ex='Exene:BAAALgAECgUJCgAAAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAAALgAECgYJEgAAAA==.Fangrell:BAAALgADCgEJAgABLgAECgYJGAAGAB8RAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Felcon:BAAALgADCgMJBAAAAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fet:BAACLgAFFH8UAAINAAUJVxsKAgDlAQANAAUJVxsKAgDlAQAuAAQKfxwAAw0ACAlnItkIAAQDAA0ACAlnItkIAAQDABcAAgllFrsLAHwAAAAA.Feyu:BAEALgAECgYJBgABLgAECgcJFwAYANUbAA==.',
Fh='Fhatbashtud:BAAALgADCgkJHgAAAA==.',
Fi='Fireflies:BAAALgAECgcJCwAAAA==.Firelore:BAAALgAECgcJAwABLgAECgkJBAACAAAAAA==.',
Fl='Flatline:BAAALgAECgMJBgAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flöti:BAEBLgAECn8XAAIYAAcJ1RsmHQAxAgAYAAcJ1RsmHQAxAgAAAA==.',
Fo='Four:BAAALgAECgYJEQAAAA==.',
Fr='Frostnips:BAAALgAECgYJCQAAAA==.Frysky:BAABLgAECn8UAAIZAAYJ+Q2EGQDkAAAZAAYJ+Q2EGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwACAAAAAA==.Futz:BAAALgAECgUJDAAAAA==.Fuzzymage:BAAALgADCgYJBgAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAAALgAECggJEgAAAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.',
Go='Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgADCgUJBQAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8lAAIXAAkJ/BovAACGAgAXAAkJ/BovAACGAgAAAA==.Gravewin:BAAALgADCgIJAgABLgAECgUJBQACAAAAAA==.Grendelheim:BAAALgADCgcJFAAAAA==.Grogar:BAAALgADCgMJAwAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.',
Gw='Gwynath:BAAALgAECgYJCwAAAA==.',
Ha='Hagrok:BAAALgADCgEJAQAAAA==.Haldael:BAAALgADCgkJDwAAAA==.Hanbil:BAAALgAECgYJCwAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgIJAwABLgAECgcJEAACAAAAAA==.Hantak:BAAALgADCgkJDAAAAA==.Hathaendron:BAAALgADCgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.',
He='Hemorrhagic:BAAALgADCgIJAgAAAA==.',
Hi='Hiromi:BAABLgAECn8VAAIaAAcJxhG0BwAZAQAaAAcJxhG0BwAZAQAAAA==.',
Ho='Hoisin:BAAALgAECgcJEgAAAA==.Holyyballs:BAAALgAECgYJEAAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgMJAwABLgAECgYJGAAGAB8RAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn8kAAIMAAgJEyGuAQBLAgAMAAgJEyGuAQBLAgAAAA==.Hussion:BAAALgADCgMJAwAAAA==.',
['Hì']='Hìroko:BAAALgAECgIJAgAAAA==.',
Ia='Iaaryn:BAAALgADCggJFAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQACAAAAAA==.',
Im='Imananji:BAAALgAECgMJBAABLgAFFAMJBQAZAK0LAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAAALgAECgYJEgAAAA==.Imperius:BAAALgADCgMJAwABLgAECgYJDgACAAAAAA==.',
In='Infernodruid:BAAALgAECgIJAgABLgAECgUJBwACAAAAAA==.Infinitie:BAAALgADCgkJEQAAAA==.Insillico:BAAALgAECgQJBwAAAA==.',
Io='Iog:BAAALgAECgYJBgAAAA==.',
Ip='Iplaydead:BAAALgAECgYJDwAAAA==.',
Ir='Iroh:BAAALgAECgYJDwAAAA==.Irondali:BAAALgADCgUJBQAAAA==.',
Is='Ismokeprot:BAAALgADCggJFAAAAA==.',
Ja='Jakub:BAAALgAECgYJBwAAAA==.Jarinduva:BAAALgADCgcJEAAAAA==.Jawnson:BAABLgAECn8aAAMNAAcJThKcBQCcAQANAAcJFBKcBQCcAQAbAAIJ8RK0GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jenefer:BAACLgAFFH8HAAMJAAMJ6AtKBQDKAAAJAAMJ6AtKBQDKAAAIAAEJRgc7VgBNAAAuAAQKfyEAAgkACAl9IZ4GAMwCAAkACAl9IZ4GAMwCAAAA.Jerzak:BAAALgADCgYJCwAAAA==.',
Jo='Joemomo:BAAALgAECgUJCgAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAACAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgIJAgAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kailback:BAAALgAECgYJBgAAAA==.Kait:BAABLgAECn8dAAMYAAcJJh6QGgBEAgAYAAcJJh6QGgBEAgAcAAMJ3gdDJACVAAAAAA==.Kakarotto:BAAALgAECgMJAwAAAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalcifur:BAACLgAFFH8GAAIHAAMJkAkFBwDXAAAHAAMJkAkFBwDXAAAuAAQKfyMAAgcACAm0FD8qAOABAAcACAm0FD8qAOABAAAA.Kaseofbeer:BAAALgAECgEJAQAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgADCgIJAgABLgAFFAMJBwAJAOgLAA==.Kasstigate:BAAALgAECgYJEAABLgAFFAMJBwAJAOgLAA==.Kastiel:BAAALgAECgQJAwABLgAECgYJDwACAAAAAA==.Kathtel:BAAALgAECgYJEAAAAA==.Katstrider:BAAALgAECgYJDwAAAA==.Kattarea:BAAALgADCgkJGQABLgAECgYJDwACAAAAAA==.Kavica:BAAALgAECgQJBAABLgAECgcJJAAdAHIkAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgQJBwAAAA==.Keldean:BAABLgAECn8VAAIaAAYJcRsOFQC8AQAaAAYJcRsOFQC8AQAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAABLgAECn8fAAIIAAgJXyFdFgD2AgAIAAgJXyFdFgD2AgAAAA==.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgADCgYJBgAAAA==.',
Ki='Kirigiri:BAABLgAECn8UAAMdAAcJTwwoHgDGAAAdAAcJTwwoHgDGAAAZAAEJAAA6NAAlAAABLgAFFAMJBgAHAJAJAA==.Kirøs:BAAALgAECgUJBQAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgADCgIJAgAAAA==.',
Ko='Kohn:BAABLgAECn8WAAIHAAcJEyUPCQDfAgAHAAcJEyUPCQDfAgAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECggJGgAFAEEeAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8HAAIeAAQJqQ5GAQAMAQAeAAQJqQ5GAQAMAQAuAAQKfxwAAh4ACAn/IeoEAMYCAB4ACAn/IeoEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAAALgADCgkJFwAAAA==.Lateo:BAABLgAECn8dAAINAAcJkQ14BwBqAQANAAcJkQ14BwBqAQAAAA==.Lawz:BAAALgAECgYJDwAAAA==.',
Le='Leafz:BAAALgAECggJEgAAAA==.Leaonissa:BAAALgADCgMJAwAAAA==.Learn:BAAALgADCgYJBgAAAA==.Lelianna:BAAALgADCgcJFgAAAA==.Lemonruss:BAABLgAECn8hAAIFAAkJExhxLABxAgAFAAkJExhxLABxAgAAAA==.Leshafrierne:BAAALgAECgQJBAAAAA==.Leshen:BAAALgAECgQJBgAAAA==.Lexia:BAAALgAECgYJEAAAAA==.',
Li='Lilturtz:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.Linnea:BAAALgAECgMJAwAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Longhorn:BAAALgAECgQJCgAAAA==.Loni:BAAALgAECgUJCwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAACAAAAAA==.Lortpegsalot:BAABLgAECn8aAAIFAAgJQR5lIACqAgAFAAgJQR5lIACqAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.',
Lu='Lucena:BAAALgAECgYJEwAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Madamkluck:BAAALgAECgYJEQAAAA==.Maglubiyet:BAAALgAECgQJCgAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Markyb:BAABLgAECn8ZAAIFAAcJpw2EGwBJAQAFAAcJpw2EGwBJAQAAAA==.Masamura:BAACLgAFFH8IAAIRAAQJ8BF5CQBVAQARAAQJ8BF5CQBVAQAuAAQKfygAAhEACAnnHjwtAL0CABEACAnnHjwtAL0CAAAA.Mattor:BAAALgADCgYJBgABLgAECgcJEAACAAAAAA==.Maureanna:BAABLgAECn8gAAIdAAcJrxorBwD2AQAdAAcJrxorBwD2AQAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Medari:BAEALgAECgcJCwAAAA==.Melorm:BAAALgADCgMJAwAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgADCgcJDwAAAA==.Mireille:BAAALgADCgcJEQAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAAALgAECgQJBAAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgADCgYJBgABLgAECgcJDwACAAAAAA==.Monachier:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Moonkin:BAAALgAECgMJAwAAAA==.Moonlïght:BAAALgAECgcJDwAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgcJDwACAAAAAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8VAAIQAAYJZwHLQwBfAAAQAAYJZwHLQwBfAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAAALgAECgYJEAAAAA==.Mosho:BAAALgADCgcJDgABLgAFFAUJFAANAFcbAA==.Mousemist:BAAALgAECgYJEwAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEAAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAAALgAECgIJAwAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mó']='Móldy:BAAALgAECgEJAgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJEwAAAA==.Namesgambit:BAAALgAECgEJAQABLgAECggJHwALAEMlAA==.Namor:BAAALgADCgYJBgAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgADCggJCAAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAECgcJHgAKADMTAA==.Nedvox:BAEBLgAECn8eAAIKAAcJMxO1CgBEAQAKAAcJMxO1CgBEAQAAAA==.Nervous:BAAALgAECgQJCwABLgAECgkJBAACAAAAAA==.Neveenn:BAABLgAECn8eAAMdAAgJcBaiJwAXAgAdAAgJcBaiJwAXAgAfAAEJfAUeJAAtAAAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Nightpigas:BAAALgADCgIJAgABLgAECgUJCgACAAAAAA==.',
No='Nohatcat:BAAALgAECgYJDQAAAA==.Notoom:BAAALgAECgYJCgAAAA==.Noxle:BAAALgADCgIJAgAAAA==.',
Ny='Nyxara:BAAALgAECgYJEgAAAA==.',
['Nè']='Nèzukõ:BAAALgAECgUJDgAAAA==.',
['Nø']='Nøtfuriøus:BAAALgADCgYJBQABLgAECgYJCgACAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCgYJDwAAAA==.',
Oc='Octavius:BAAALgAECgEJAQAAAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEALgAECgUJCwAAAA==.Ojoverde:BAABLgAECn8iAAIQAAgJARx0JACBAgAQAAgJARx0JACBAgAAAA==.',
On='Ontahli:BAAALgADCgUJBQABLgAECggJHAADAHoQAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.',
Ov='Overflare:BAAALgADCgEJAQAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Pajamas:BAAALgAECgUJCwAAAA==.Pallanquin:BAAALgAECgEJAQAAAA==.Pallywacker:BAAALgAECgMJBAAAAA==.Pashnir:BAAALgADCggJCQAAAA==.',
Pe='Peachey:BAAALgAECgYJDwAAAA==.Percilus:BAABLgAECn8lAAMJAAgJ2CFEBgDTAgAJAAgJcyFEBgDTAgAIAAQJ+xkf1ADYAAAAAA==.',
Ph='Phrantic:BAAALgAECgEJAQAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAAALgAECgUJCgAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgMJAwAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAAALgAECgUJBQABLgAECgQJCAACAAAAAA==.',
Ps='Psychosix:BAABLgAECn8eAAIRAAgJTSHCBABtAgARAAgJTSHCBABtAgAAAA==.Psychros:BAAALgADCgcJCAAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgADCgYJDQAAAA==.',
Qu='Quinberos:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.',
Ra='Radchad:BAAALgAECgMJBAAAAA==.Raiola:BAAALgAECgQJBQAAAA==.Ramdel:BAAALgADCgkJHgABLgAECgcJEQACAAAAAA==.Ramstryder:BAAALgAECgcJEQAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8LAAIaAAQJUCFzAgCMAQAaAAQJUCFzAgCMAQAuAAQKfxwAAhoACAk6JdYCADYDABoACAk6JdYCADYDAAAA.',
Re='Rekmortal:BAAALgAFFAIJAgAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8YAAIGAAYJHxHiFwA8AQAGAAYJHxHiFwA8AQAAAA==.Resinya:BAAALgAECgYJBwAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rheagall:BAAALgAECgYJCgAAAA==.Rheagnar:BAAALgADCgIJAgAAAA==.',
Ri='Rinshino:BAAALgAECgUJDAAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Rowena:BAABLgAECn8oAAIfAAkJZBo7FQBnAgAfAAkJZBo7FQBnAgAAAA==.Rowynna:BAAALgAECgMJAwAAAA==.Roxydk:BAAALgAECgcJCQAAAA==.',
Ru='Ruxspin:BAAALgAECgMJBAAAAA==.',
Ry='Ryzedvoid:BAAALgAECgQJCgAAAA==.Ryzinneko:BAABLgAECn8gAAIdAAgJTCGmBAA+AgAdAAgJTCGmBAA+AgAAAA==.',
Sa='Sabend:BAACLgAFFH8QAAIQAAUJoRHCCACdAQAQAAUJoRHCCACdAQAuAAQKfx8AAxAACAmfHVkpAGsCABAACAmfHVkpAGsCAA4AAQkAAFRmAEMAAAAA.Sablewolfe:BAAALgAECgEJAgAAAA==.Safaria:BAAALgAECgUJDAAAAA==.Sarlyssa:BAAALgADCgkJEQAAAA==.Saucymac:BAACLgAFFH8GAAIKAAMJpQwCBgDfAAAKAAMJpQwCBgDfAAAuAAQKfyMAAgoACAkJIesKANQCAAoACAkJIesKANQCAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Senath:BAAALgAECgYJEQAAAA==.Sephrenia:BAAALgADCgUJCQAAAA==.Serandipity:BAAALgAECgEJAQABLgAFFAMJBwAJAOgLAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAAALgAECgYJCgAAAA==.Shamanagans:BAAALgADCgUJBQAAAA==.Shamanigans:BAAALgAECgUJCAAAAA==.Shammygoat:BAAALgAECgUJDwAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDgAAAA==.Shaqattack:BAABLgAECn8ZAAIMAAgJGCNMBgAcAwAMAAgJGCNMBgAcAwAAAA==.Shaqattaq:BAAALgAECgYJCgABLgAECggJGQAMABgjAA==.Sharkmeat:BAAALgAECgYJEwAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAAALgAECgYJBgAAAA==.Shawntelle:BAABLgAECn8UAAIgAAcJ7yOnBQCvAgAgAAcJ7yOnBQCvAgAAAA==.Sheutka:BAAALgAECgMJBAAAAA==.Shinaie:BAAALgAECgYJEQAAAA==.Shockanduwu:BAAALgAECgUJEAAAAA==.Shruikan:BAAALgADCgYJCwABLgAECgcJEAACAAAAAA==.Shtylez:BAAALgADCgYJBgAAAA==.',
Si='Sigzil:BAAALgADCgUJBQAAAA==.Silth:BAAALgADCgcJEwAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Sinariel:BAAALgAECgYJDwAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAAALgAECgUJCQAAAA==.',
Sm='Smmoke:BAABLgAECn8aAAIGAAcJUxygIwAwAgAGAAcJUxygIwAwAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAECgMJAwAAAA==.Sniperart:BAAALgAECgcJEwABLgAECggJCgACAAAAAA==.',
So='Soull:BAAALgAECgcJEQAAAA==.',
Sp='Spacemoo:BAAALgAECgYJEAAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.',
St='Starface:BAACLgAFFH8FAAIZAAMJrQsYAgCkAAAZAAMJrQsYAgCkAAAuAAQKfyIAAxkACAkYH7MEAKACABkACAkYH7MEAKACAB0AAQk9AenpABsAAAAA.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgADCgkJFQAAAA==.Stefane:BAAALgAECgYJCAAAAA==.Steverogers:BAAALgAECgEJBAABLgAECggJHwALAEMlAA==.Stocktonrush:BAAALgADCgUJBQABLgAECggJHwALAEMlAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAAALgAECgMJCAAAAA==.Sturmx:BAABLgAECn8aAAIhAAcJ3BgfBACeAQAhAAcJ3BgfBACeAQAAAA==.',
Su='Subaaâ:BAABLgAECn8aAAMSAAgJTiMGAQAzAwASAAgJTiMGAQAzAwAiAAUJIhQwhgAaAQABLgAECgYJGgABAPseAA==.Subby:BAAALgADCgUJDQAAAA==.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAAALgAECgMJBAAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8YAAIIAAcJ0xJbFQBnAQAIAAcJ0xJbFQBnAQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCgcJEwACAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAAALgAECgYJCgAAAA==.Syrony:BAAALgADCgMJAwAAAA==.',
['Sû']='Sûshealä:BAAALgAECgUJCQAAAA==.',
Ta='Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn8XAAIZAAYJ8h2dCgDtAQAZAAYJ8h2dCgDtAQAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAQAAAA==.Terrya:BAAALgADCgUJBQAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.',
Ti='Tickle:BAAALgAECgUJCwAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgQJBAACAAAAAA==.Tirithor:BAABLgAECn8ZAAIFAAcJuRaEVADkAQAFAAcJuRaEVADkAQAAAA==.',
To='Tockell:BAAALgADCggJDQAAAA==.Tonakai:BAAALgAFFAEJAQAAAA==.Tony:BAAALgAECgYJCgABLgAECgkJKAAMAP8aAA==.Torbin:BAAALgAECgUJCQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgACAAAAAA==.',
Tr='Tricks:BAAALgAECgcJDwAAAA==.Trilleon:BAAALgADCgkJDAABLgAECgMJAwACAAAAAA==.Trillis:BAAALgADCggJDgABLgAECgMJAwACAAAAAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgUJBQABLgAECgYJDAACAAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.',
Tu='Turgà:BAAALgADCgEJAgABLgADCgMJBQACAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgEJAQAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tý']='Týlïus:BAAALgAECgYJEQAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCgcJEwAAAA==.',
Ut='Uthilon:BAABLgAECn8ZAAIjAAcJ7SIsAQA6AgAjAAcJ7SIsAQA6AgAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAAALgAECgYJDwAAAA==.',
Ve='Vedillian:BAAALgAECgcJDwAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vennaya:BAAALgAECgcJDQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgYJBgAAAA==.Violentpanda:BAAALgAECgIJAgAAAA==.Vite:BAAALgADCgcJFAAAAA==.Vixious:BAAALgADCgQJBAAAAA==.Vizigoth:BAABLgAECn8UAAMQAAcJrwo3HAA3AQAQAAYJlQg3HAA3AQAOAAIJCxHlVwBnAAAAAA==.',
Vo='Voladon:BAAALgAECgYJEQAAAA==.Voyana:BAAALgAECgUJDAABLgAECgUJDAACAAAAAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAMJBwARAAgbAA==.Vymage:BAACLgAFFH8HAAIRAAMJCBsnDgAdAQARAAMJCBsnDgAdAQAuAAQKfyAAAhEACAkaJD8SADoDABEACAkaJD8SADoDAAAA.',
['Vá']='Válidüs:BAACLgAFFH8JAAIkAAQJdgruAgAOAQAkAAQJdgruAgAOAQAuAAQKfxsAAiQACQnfFcoLAJQCACQACQnfFcoLAJQCAAAA.',
['Vã']='Vãsh:BAAALgADCggJCAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAAALgAECgUJBwAAAA==.Waterloo:BAAALgADCgcJFgAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIRAAgJpAlyGQB9AQARAAgJpAlyGQB9AQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.',
Wr='Wrathidan:BAAALgAECgYJDAAAAA==.',
['Wì']='Wìccka:BAAALgAECgQJBwAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Ya='Yalper:BAAALgADCgUJBQAAAA==.',
Yo='Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAAALgAECgYJDQAAAA==.',
Yz='Yz:BAAALgAECgQJBAAAAA==.',
Za='Zalysi:BAABLgAECn8WAAMHAAgJHBLhJwDtAQAHAAgJHBLhJwDtAQAFAAIJkQc8HwFeAAAAAA==.Zam:BAABLgAECn8cAAMBAAcJ5B3XHwBSAgABAAcJsRrXHwBSAgAlAAMJwBhICwCsAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgADCgUJBgAAAA==.Zashen:BAAALgAECgYJDAAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAMJBQAZAK0LAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgMJAwABLgAFFAMJBQAQAKIXAA==.Zlufernal:BAACLgAFFH8FAAIQAAMJohf0FQC1AAAQAAMJohf0FQC1AAAuAAQKfyMAAhAACAkIJVANAA8DABAACAkIJVANAA8DAAAA.',
Zy='Zyn:BAABLgAECn8UAAIBAAUJJg5lZAAhAQABAAUJJg5lZAAhAQAAAA==.',
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

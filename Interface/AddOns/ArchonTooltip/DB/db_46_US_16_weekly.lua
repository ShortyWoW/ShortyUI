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

local lookup = {'Priest-Holy','Priest-Shadow','Druid-Restoration','Mage-Frost','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Warrior-Fury','Warrior-Arms','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warrior-Protection','Warlock-Affliction','Hunter-Survival','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','Mage-Fire','Druid-Guardian',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Absoul:BAABLgAECn8iAAMBAAgJwCFoAwD0AgABAAgJwCFoAwD0AgACAAEJcQPyaAAmAAAAAA==.',
Ac='Acedia:BAABLgAECn8qAAIBAAkJ+hT6CwAnAgABAAkJ+hT6CwAnAgAAAA==.',
Ad='Adellas:BAABLgAECn8fAAIDAAgJNh4FEgA+AgADAAgJNh4FEgA+AgAAAA==.Adern:BAABLgAECn8dAAICAAcJ2B6GEgBkAgACAAcJ2B6GEgBkAgAAAA==.Adon:BAABLgAECn8cAAIEAAgJuByCJAAUAgAEAAgJuByCJAAUAgAAAA==.Adondruel:BAAALgAECgEJAQAAAA==.',
Ae='Aelali:BAAALgAECgQJBQAAAA==.Aelith:BAAALgAECgcJEgAAAA==.',
Af='Afador:BAAALgAECgEJAgABLgAECggJJQAFALAQAA==.',
Ag='Ageling:BAAALgADCgQJAgAAAA==.',
Ak='Akeno:BAAALgAECgMJAwABLgAECgIJAwAGAAAAAA==.Akrom:BAAALgADCgEJAgAAAA==.',
Al='Aladestar:BAACLgAFFH8GAAMHAAMJqAr4GQDVAAAHAAMJqAr4GQDVAAADAAIJHxB1GgCTAAAuAAQKfyUAAwMACAnIGqsbAF4CAAMACAnIGqsbAF4CAAcACAlfIBAiAOwBAAAA.Albinodargon:BAAALgAECgQJCwAAAA==.Alderleise:BAABLgAECn8UAAIDAAcJrwqkRQD8AAADAAcJrwqkRQD8AAAAAA==.Alecc:BAAALgAECgYJCwAAAA==.Alecw:BAAALgAECgQJBAAAAA==.Alexein:BAACLgAFFH8FAAIIAAQJdQG/BADhAAAIAAQJdQG/BADhAAAuAAQKfyUAAggACAnvFA4FAPYBAAgACAnvFA4FAPYBAAAA.Alienspace:BAAALgADCgEJAQAAAA==.',
Am='Amets:BAABLgAECn8kAAIJAAgJrSUQAQBwAwAJAAgJrSUQAQBwAwAAAA==.Amydh:BAAALgAECgIJCAAAAA==.',
An='Anabel:BAAALgADCgkJFAAAAA==.Anamii:BAAALgADCgEJAQAAAA==.Andorsi:BAAALgAECgYJCAAAAA==.Anglechow:BAAALgADCgUJBQAAAA==.',
Ar='Arachne:BAABLgAECn8eAAICAAcJQwoiKwDyAAACAAcJQwoiKwDyAAAAAA==.Aranax:BAAALgADCgEJAgAAAA==.Arce:BAAALgAECgQJCgAAAA==.Architeleaf:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.Areafiftymoo:BAABLgAECn8qAAMKAAgJ5Qs9HwBxAQAKAAgJ/Qo9HwBxAQALAAEJ2wl3QAAuAAAAAA==.Arthurleywin:BAAALgADCgIJAgAAAA==.Arysia:BAAALgAECgUJDgAAAA==.Aryya:BAABLgAECn8+AAMMAAgJ2iM6AQDhAgAMAAgJ2iM6AQDhAgAHAAMJHAe7ZwCCAAAAAA==.',
As='Astralbreak:BAAALgADCgQJBQABLgAECgUJBwAGAAAAAA==.',
At='Athelia:BAAALgADCgEJAQAAAA==.',
Av='Avalan:BAABLgAECn8tAAIKAAgJfiBjBgCKAgAKAAgJfiBjBgCKAgAAAA==.Avashammy:BAABLgAECn8fAAMNAAgJ+ByeGwDUAQANAAgJ+ByeGwDUAQAOAAEJbwgFbQApAAAAAA==.Avesia:BAABLgAECn8aAAIPAAYJUBadIgB/AQAPAAYJUBadIgB/AQAAAA==.Aviendah:BAABLgAECn8WAAIQAAgJkROCJgC6AQAQAAgJkROCJgC6AQAAAA==.',
Aw='Awsomeonet:BAABLgAECn8WAAMRAAgJ/ha2EAAxAQARAAgJ/ha2EAAxAQASAAIJPwQWKAFQAAAAAA==.',
Ay='Ayot:BAAALgAECgcJEwAAAA==.',
Az='Azdfghop:BAACLgAFFH8WAAMQAAYJfyHtCAB4AQAQAAUJph7tCAB4AQATAAUJ4BhTDAD1AAAuAAQKfyAAAxMACQm2IigPAMcCABMACAnIHigPAMcCABAACAmZIY0/ALEBAAAA.Azzinotica:BAAALgAECgEJAQAAAA==.',
Ba='Babeshot:BAABLgAECn8cAAIQAAgJnhIuIwDKAQAQAAgJnhIuIwDKAQAAAA==.Babezila:BAAALgAECgYJDwAAAA==.Badshahprime:BAABLgAECn8eAAISAAgJPhphKgB7AgASAAgJPhphKgB7AgAAAA==.Barbiegrill:BAABLgAECn8dAAMUAAgJ7x79DwCmAgAUAAgJEB79DwCmAgAVAAUJVRxACQCuAQABLgAFFAMJBgAWAIoSAA==.Battlemaker:BAAALgADCgcJBwABLgAECgcJJwANAPUYAA==.Baykin:BAABLgAECn8nAAIXAAgJNh9bBgBzAgAXAAgJNh9bBgBzAgAAAA==.',
Bb='Bbeastt:BAAALgADCgEJAgAAAA==.',
Be='Beefyfivelyr:BAAALgADCgcJBwAAAA==.Berandas:BAABLgAECn8UAAMYAAcJ/hECJgCDAQAYAAcJ/hECJgCDAQAZAAUJhQ2JKgDhAAAAAA==.Bereessielin:BAAALgAECgQJBgAAAA==.Berkowitz:BAAALgAECgUJDQAAAA==.',
Bi='Bigbear:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.',
Bl='Blaaze:BAAALgAECgQJBgAAAA==.Blaiddyd:BAABLgAECn8eAAIQAAcJeyBeGAANAgAQAAcJeyBeGAANAgAAAA==.Blead:BAABLgAFFH8GAAMWAAMJihKlEQDZAAAWAAMJihKlEQDZAAAFAAEJtgUqmgBHAAAAAA==.Blinkerr:BAAALgADCgkJDAAAAA==.',
Br='Brahot:BAAALgAECgEJAQAAAA==.Brain:BAAALgAECgQJAwAAAA==.Brandawn:BAAALgADCgYJBgAAAA==.Branwarden:BAAALgAECgYJDwAAAA==.Brewsle:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebot:BAAALgAECgMJAwABLgAECggJIgAaANwfAA==.Bullchitz:BAABLgAECn8WAAIQAAYJ+RiXQwChAQAQAAYJ+RiXQwChAQAAAA==.Bullchitza:BAAALgADCgcJBwABLgAECgYJFgAQAPkYAA==.Burningooch:BAAALgADCgEJAQAAAA==.',
['Bã']='Bãyy:BAAALgAECgYJDAAAAA==.',
['Bæ']='Bæyy:BAAALgADCgUJCgABLgAECgYJDAAGAAAAAA==.',
Ca='Calador:BAAALgAECggJEgAAAA==.Capybara:BAAALgAECgcJDAAAAA==.Caster:BAAALgADCgQJBAAAAA==.Cathbad:BAAALgADCgEJAQAAAA==.Caylynn:BAAALgADCgkJFAAAAA==.',
Ce='Celyne:BAABLgAECn8iAAMaAAgJ3B+IFgAIAgAaAAgJ3B+IFgAIAgAbAAcJTheIBgCTAQAAAA==.Cereza:BAAALgAECgEJAQAAAA==.',
Ch='Chaoslock:BAAALgADCgMJAwAAAA==.Chicknfajita:BAAALgAECgYJCAAAAA==.Chrissi:BAABLgAECn8YAAIDAAgJgQt1OAA0AQADAAgJgQt1OAA0AQAAAA==.',
Ci='Cinco:BAAALgADCgUJBQAAAA==.',
Cl='Clearly:BAAALgADCgQJAwAAAA==.',
Co='Cocytus:BAAALgAECgIJAwAAAA==.Colbith:BAAALgADCgYJBgAAAA==.Conquest:BAAALgAFFAIJAgAAAA==.Cordaddy:BAABLgAECn8gAAIDAAgJnSXWBgDiAgADAAgJnSXWBgDiAgAAAA==.Cordragu:BAAALgAECgQJBQABLgAECggJIAADAJ0lAA==.Corinthe:BAABLgAECn8VAAMJAAgJESbzAAB4AwAJAAgJESbzAAB4AwASAAEJYQ/C+wA5AAABLgAECggJIAADAJ0lAA==.Corinthin:BAABLgAECn8nAAINAAcJ9RiOHQDFAQANAAcJ9RiOHQDFAQAAAA==.',
Cr='Crinn:BAAALgAECggJDgAAAA==.Crizmon:BAABLgAECn8yAAIIAAgJYCM/AQD5AgAIAAgJYCM/AQD5AgAAAA==.Cryomancer:BAAALgADCgQJBAAAAA==.Crõwley:BAAALgADCgYJBgABLgAECgcJGQAcAKUYAA==.',
Da='Damage:BAAALgAECgEJAQAAAA==.Damorax:BAAALgAECgcJDgAAAA==.Darazarke:BAACLgAFFH8cAAIcAAYJrRJOBQDWAQAcAAYJrRJOBQDWAQAuAAQKfyMABB0ACAlsHg8EANICAB0ACAlsHg8EANICABwABwmTHKgOAE4CAB4AAQlwGHZdAEQAAAAA.Darkcursed:BAABLgAECn8eAAIfAAgJgwmnPwBrAQAfAAgJgwmnPwBrAQAAAA==.Darksudge:BAAALgAECgEJAQAAAA==.Darps:BAABLgAECn8TAAIQAAcJgBcgJgC8AQAQAAcJgBcgJgC8AQAAAA==.Daybreak:BAAALgAECgcJEQAAAA==.Dayquil:BAEBLgAECn8hAAMSAAgJdB2zNgBIAgASAAgJdB2zNgBIAgAJAAEJwRkCWgBGAAAAAA==.',
De='Deadaddie:BAABLgAECn8gAAMFAAgJgh/BDwCBAgAFAAgJgh/BDwCBAgAIAAYJUxd9BgBTAQAAAA==.Deamoneyes:BAAALgAFFAMJAwAAAA==.Decastamon:BAAALgAECggJDgAAAA==.Delin:BAAALgAECgcJBwABLgAFFAYJHAAcAK0SAA==.Deluxdh:BAAALgAECgMJAwAAAA==.Demonslinger:BAAALgADCgUJBQAAAA==.Dendrel:BAAALgADCggJCAAAAA==.Derpspally:BAAALgAECgEJAQAAAA==.Derpspunch:BAABLgAECn8WAAIYAAgJTRsFCAB1AgAYAAgJTRsFCAB1AgAAAA==.Destrox:BAAALgADCgYJBgAAAA==.Dezatra:BAAALgAECgMJBgAAAA==.Deíty:BAAALgADCgUJBgAAAA==.',
Di='Diane:BAEALgAECgYJBgAAAA==.Dieselcon:BAABLgAECn84AAMRAAgJ9xXDDQDpAQARAAgJ9xXDDQDpAQASAAEJswyXRAEyAAAAAA==.Dieseletta:BAAALgAECgMJAwAAAA==.Dinodruid:BAAALgAECgcJAwAAAA==.',
Do='Domdog:BAABLgAECn8sAAIEAAkJOhO8IwAYAgAEAAkJOhO8IwAYAgAAAA==.Domína:BAAALgAECgEJAQAAAA==.Dontforget:BAABLgAECn8VAAIJAAYJJRSMIgBzAQAJAAYJJRSMIgBzAQAAAA==.Dookiesmash:BAABLgAECn8cAAIgAAgJfiPfAgCrAgAgAAgJfiPfAgCrAgAAAA==.Doomblast:BAAALgADCgIJAgAAAA==.Doomdealer:BAAALgAFFAEJAQAAAA==.Doomed:BAAALgADCgQJBAABLgAECgcJFgAXAGMgAA==.Doomrage:BAAALgADCgcJFAAAAA==.Doomsdead:BAAALgADCgcJBwAAAA==.Doomshock:BAAALgADCgYJBQAAAA==.',
Dr='Draftymonk:BAABLgAECn8dAAMXAAcJQSGPDQDtAQAXAAYJKCKPDQDtAQAZAAUJTRq8GwBFAQAAAA==.Drax:BAABLgAECn8aAAMhAAgJ8wm8DgBFAQAfAAgJGwnkQQBjAQAhAAYJpgi8DgBFAQAAAA==.Dreadgar:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.Dritzzfive:BAABLgAECn8XAAIFAAcJ6QhLWgAyAQAFAAcJ6QhLWgAyAQAAAA==.Dritzzwar:BAAALgAECgYJDAAAAA==.',
Ei='Eilica:BAAALgAECgUJBQAAAA==.',
Ek='Ekaine:BAAALgADCgQJBAABLgAECgYJGAAEAFgQAA==.',
El='Elandrus:BAAALgAECgQJBQABLgAECgcJGQAcAKUYAA==.Elishiveth:BAAALgAECgYJBgAAAA==.Elleynre:BAAALgADCgQJBAAAAA==.Elliewilliam:BAAALgADCgQJBAAAAA==.Elrëim:BAAALgAECggJDQAAAA==.Elwendigo:BAAALgADCgMJAwAAAA==.Elwyna:BAAALgADCgIJAgAAAA==.',
Em='Emmara:BAABLgAECn8YAAITAAgJyALeEQDUAAATAAgJyALeEQDUAAAAAA==.',
En='Enhancement:BAAALgADCgcJDQABLgAFFAUJEwAOAAIlAA==.Enitar:BAAALgAECgUJCQABLgAECggJIgAaANwfAA==.',
Er='Erata:BAAALgAECgUJDAAAAA==.Erlangshen:BAAALgADCgUJBQAAAA==.Erravis:BAAALgADCgcJDwAAAA==.',
Ev='Evarion:BAAALgADCgEJAQAAAA==.Eviaei:BAAALgAECgMJAwAAAA==.Evulise:BAAALgADCgYJBAAAAA==.Evullight:BAAALgAECgEJAQAAAA==.',
Ez='Ezalan:BAAALgADCgcJBwAAAA==.Ezlok:BAAALgAFFAEJAQAAAA==.Ezorreodd:BAAALgADCgQJBAAAAA==.Ezzorreodd:BAAALgAECgUJCQAAAA==.',
Fa='Fae:BAABLgAECn8YAAMNAAgJ2BX6SgBWAQANAAYJihH6SgBWAQAOAAYJ+BISJwAjAQABLgAECgYJFAASAGUVAA==.Falcyon:BAAALgAECgMJAwAAAA==.Falerin:BAABLgAECn8XAAIDAAgJCBGoNABHAQADAAgJCBGoNABHAQAAAA==.Farenheit:BAABLgAECn8pAAMHAAkJjBlEBgB7AgAHAAkJjBlEBgB7AgADAAQJlQ0XowCDAAAAAA==.Fatel:BAAALgAECgEJAQABLgAFFAMJBgAWAIoSAA==.Faydwer:BAAALgADCgMJBAAAAA==.Fayfox:BAAALgADCgkJFwAAAA==.',
Fe='Feenex:BAAALgAECgYJDAAAAA==.',
Fi='Finick:BAAALgAECgYJDgAAAA==.Firedealer:BAABLgAECn8bAAITAAgJ2xJkBgCzAQATAAgJ2xJkBgCzAQAAAA==.Firnen:BAABLgAECn8ZAAIcAAcJpRgVGgC7AQAcAAcJpRgVGgC7AQAAAA==.',
Fl='Flahash:BAAALgAECgMJAwAAAA==.Flappy:BAAALgAECgcJDwABLgAECgkJJQANAO0eAA==.Flapster:BAAALgADCgkJFQABLgAECgkJJQANAO0eAA==.Flashmaster:BAAALgAECgYJCgAAAA==.Flawlessheal:BAAALgAECgEJCAAAAA==.Flora:BAAALgAECgEJAwABLgAECgYJFAASAGUVAA==.Fluffybutt:BAAALgADCgkJDgAAAA==.',
Fo='Fossora:BAAALgAECgMJBgAAAA==.',
Fr='Frostmagi:BAAALgAECgYJDwABLgAFFAUJEwAOAAIlAA==.Frostybunny:BAAALgAECgIJAgAAAA==.Frozenharded:BAAALgAECgQJAwABLgAECgcJDwAGAAAAAA==.',
Fu='Furrbidden:BAAALgADCgQJBAAAAA==.Fusionve:BAAALgAECgUJBgAAAA==.',
Ga='Gaffershot:BAAALgADCgMJAwAAAA==.Gafferthicc:BAABLgAECn8cAAIaAAgJpxrLHgDPAQAaAAgJpxrLHgDPAQAAAA==.Gaffharir:BAAALgADCgUJBQAAAA==.Galvin:BAAALgADCgYJBgAAAA==.Garfeeld:BAAALgADCgcJCwABLgAECgcJJwANAPUYAA==.Garlicroast:BAAALgAECgMJBgAAAA==.Gayden:BAAALgAECgUJBgAAAA==.',
Ge='Gelatin:BAAALgADCgQJBQAAAA==.Gerry:BAABLgAECn8rAAIiAAgJOh9MBgBMAgAiAAgJOh9MBgBMAgAAAA==.Geyora:BAABLgAECn8cAAIiAAgJ9x6nAwDpAgAiAAgJ9x6nAwDpAgAAAA==.',
Gg='Ggkando:BAAALgAECgYJBgAAAA==.',
Gi='Gingerail:BAAALgAECgcJDwAAAA==.',
Gl='Glory:BAABLgAECn8XAAIWAAgJshpQCQDqAQAWAAgJshpQCQDqAQAAAA==.',
Go='Goochsquirts:BAABLgAECn8oAAMNAAcJ+RqGKADuAQANAAcJ+RqGKADuAQAOAAEJ1ASKbgAmAAAAAA==.Gorrick:BAAALgAECgQJBAAAAA==.Gorriff:BAAALgAECgMJBAAAAA==.',
Gr='Graestrae:BAABLgAECn8WAAIFAAYJkQSXhQDVAAAFAAYJkQSXhQDVAAAAAA==.Gravedygger:BAABLgAECn8sAAIQAAgJfRl5GgD/AQAQAAgJfRl5GgD/AQAAAA==.Greenonions:BAAALgADCgIJAgAAAA==.Grenswood:BAACLgAFFH8QAAIjAAQJiiM3AQCBAQAjAAQJiiM3AQCBAQAuAAQKfykAAiMACQnjJK0AAEwDACMACQnjJK0AAEwDAAAA.Grimmarius:BAAALgAFFAIJAgAAAA==.Grimmkin:BAAALgAECgUJCAAAAA==.Grimmyr:BAAALgADCgYJBgAAAA==.Grumbo:BAAALgAECgMJBgAAAA==.Gryff:BAAALgADCgcJBwAAAA==.',
Gu='Guuldurak:BAAALgAECgMJBgAAAA==.',
Ha='Harrod:BAABLgAECn8UAAIEAAcJCgbrewAZAQAEAAcJCgbrewAZAQAAAA==.Hasew:BAABLgAECn8cAAIQAAcJPhu9MgDkAQAQAAcJPhu9MgDkAQAAAA==.Haste:BAAALgAECgMJAwABLgAFFAMJBgAWAIoSAA==.',
He='He:BAAALgAECgEJAQAAAA==.Heimlich:BAAALgAECgEJAgABLgAECggJHgASAD4aAA==.Hellodoodle:BAAALgADCgcJGgAAAA==.Helpimßlind:BAABLgAECn8jAAIaAAcJqRYsQgAyAQAaAAcJqRYsQgAyAQAAAA==.Hera:BAACLgAFFH8KAAIQAAQJACIUBQCUAQAQAAQJACIUBQCUAQAuAAQKfy4AAhAACAn0JUUCAHYDABAACAn0JUUCAHYDAAAA.Herry:BAAALgAECgUJDgABLgAECggJKwAiADofAA==.Heyner:BAABLgAECn8pAAIkAAgJ0xQIAwDjAQAkAAgJ0xQIAwDjAQAAAA==.',
Hi='Hille:BAAALgADCgEJAQAAAA==.Hinral:BAACLgAFFH8HAAIYAAQJtR3TCwBdAQAYAAQJtR3TCwBdAQAuAAQKfyIAAhgACAnRJSgDAEsDABgACAnRJSgDAEsDAAAA.',
Ho='Holyangus:BAAALgAECgUJCQAAAA==.',
Hu='Hukkaru:BAAALgADCgYJDgAAAA==.',
['Hë']='Hëll:BAABLgAECn8dAAIfAAgJUhF5QgBhAQAfAAgJUhF5QgBhAQAAAA==.',
Ic='Iceblind:BAAALgAECgYJEAAAAA==.',
Il='Ilcanna:BAAALgADCgEJAQAAAA==.Illaynne:BAABLgAECn8mAAIBAAgJyRvYCgA5AgABAAgJyRvYCgA5AgAAAA==.',
Im='Imani:BAACLgAFFH8GAAIlAAQJlgS9BQDaAAAlAAQJlgS9BQDaAAAuAAQKfysAAiUACAmLFSMNAO4BACUACAmLFSMNAO4BAAAA.Immensepain:BAABLgAECn8mAAIEAAgJqRD7fADXAQAEAAgJqRD7fADXAQAAAA==.Imnotbalding:BAAALgAECgMJBgAAAA==.Imtrynacrack:BAAALgADCgQJBAAAAA==.Imurhucklbry:BAAALgADCgMJAwAAAA==.',
In='Inalee:BAAALgAECgcJEgAAAA==.Inoshikacho:BAABLgAECn8jAAIMAAgJZAgFDABYAQAMAAgJZAgFDABYAQAAAA==.Involio:BAAALgADCggJDAAAAA==.Invý:BAABLgAECn8nAAISAAgJgBlQIQACAgASAAgJgBlQIQACAgAAAA==.',
Ir='Irishdots:BAAALgADCgMJAwAAAA==.Irishkicks:BAAALgADCgQJBAAAAA==.Irishlife:BAAALgAECgQJBAAAAA==.Irishmecha:BAACLgAFFH8KAAIVAAQJ6QMoAwAqAQAVAAQJ6QMoAwAqAQAuAAQKfykAAhUACAntFx0FAEQCABUACAntFx0FAEQCAAAA.Irishtotems:BAAALgADCgQJBAAAAA==.Irishtraps:BAAALgADCgEJAQAAAA==.',
Is='Isandra:BAAALgADCgEJAQAAAA==.',
It='Itharillys:BAABLgAECn8cAAIQAAgJiguIQABMAQAQAAgJiguIQABMAQAAAA==.',
Ja='Jaadu:BAAALgADCgQJAwAAAA==.',
Je='Jeennkiins:BAAALgADCggJFwABLgAECgkJKgABAH4cAA==.Jessibella:BAAALgAECgcJDwAAAA==.Jezzako:BAABLgAECn8YAAMQAAYJjAtiaAAvAQAQAAUJsg1iaAAvAQAiAAYJHASdGwAaAQAAAA==.',
Ji='Jinx:BAAALgAECgMJBAABLgAECgYJFAASAGUVAA==.',
Jo='Johali:BAABLgAECn8dAAILAAcJTwdnGwDaAAALAAcJTwdnGwDaAAAAAA==.',
Ju='Justise:BAABLgAECn8WAAQgAAYJvxkCFADMAQAgAAYJ5BgCFADMAQAKAAUJFhj+KQAtAQALAAEJjQ4HRgAsAAAAAA==.Jutojerry:BAABLgAECn8WAAMXAAcJYyDwEQC0AQAXAAcJYyDwEQC0AQAYAAIJzhwOTQChAAAAAA==.',
['Jî']='Jîru:BAAALgADCgQJBAAAAA==.',
['Jö']='Jöhnblaze:BAABLgAECn8ZAAQgAAgJNg7xHwC+AAAKAAcJWwzfYQAqAQAgAAUJYw3xHwC+AAALAAEJPAu6PQAzAAAAAA==.Jöker:BAAALgAECgEJAQAAAA==.',
Ka='Kaalya:BAAALgADCgYJBgAAAA==.Kaelus:BAAALgADCgEJAQAAAA==.Kahoona:BAAALgAECgUJDAAAAA==.Kailys:BAABLgAECn8dAAIRAAgJ2Au9EgAWAQARAAgJ2Au9EgAWAQAAAA==.Kaishias:BAABLgAECn8eAAISAAgJfRirPwAnAgASAAgJfRirPwAnAgAAAA==.Kamyra:BAAALgAECgYJEQAAAA==.Kanimeh:BAAALgADCgIJAgAAAA==.Kankuró:BAABLgAECn8sAAMQAAkJqB/zBwCyAgAQAAkJqB/zBwCyAgATAAEJyAdljgAtAAAAAA==.',
Ke='Kedzen:BAAALgADCgcJGgABLgAECgcJJwANAPUYAA==.Kerfur:BAAALgAECgMJAwAAAA==.',
Ki='Killudead:BAAALgAECggJDgAAAA==.',
Ko='Kodetra:BAAALgAECgQJBAAAAA==.Kolgrim:BAABLgAECn8bAAMWAAgJQxrnFgAZAQAIAAUJbxPPCQA4AQAWAAcJVhrnFgAZAQAAAA==.Korimya:BAAALgAECgEJAgAAAA==.Korva:BAAALgAECgYJEwABLgAECgYJGAAEAFgQAA==.',
Kr='Krianthess:BAAALgAECgUJCQAAAA==.Krissypoo:BAAALgADCgcJCwAAAA==.Kristie:BAABLgAECn8YAAIEAAYJWBCGugBsAQAEAAYJWBCGugBsAQAAAA==.Krom:BAABLgAECn8hAAINAAgJ4w7vLgBXAQANAAgJ4w7vLgBXAQAAAA==.',
Ku='Kuadonaran:BAAALgADCgEJAQABLgAECggJKAAhAPYhAA==.Kulitcomandr:BAAALgADCgUJBQAAAA==.Kupquake:BAACLgAFFH8IAAIZAAMJfwgkEgDVAAAZAAMJfwgkEgDVAAAuAAQKfysAAhkACAlmHLAQAHYCABkACAlmHLAQAHYCAAAA.',
Ky='Kynris:BAAALgADCgMJAwABLgAECgcJGQAcAKUYAA==.',
La='Laancelot:BAAALgADCgkJDgAAAA==.Lacy:BAAALgADCgEJAQAAAA==.Laetus:BAAALgAECgUJDQAAAA==.Lamort:BAABLgAECn8oAAQhAAgJ9iFAAQBkAgAhAAcJ8yJAAQBkAgAfAAcJVx3xPAAZAgAjAAYJcxq5CABOAQAAAA==.Lanaal:BAAALgADCgIJAgAAAA==.Lancewh:BAAALgADCgkJFwAAAA==.Launzi:BAAALgADCgkJDgAAAA==.Lavirna:BAAALgADCgEJAQABLgAECgYJGAAEAFgQAA==.Lazulli:BAAALgADCgMJAwAAAA==.',
Le='Leaila:BAAALgAECgYJEAAAAA==.Leonora:BAABLgAECn8gAAITAAgJphAhCACCAQATAAgJphAhCACCAQAAAA==.',
Li='Lightbreakk:BAAALgADCgkJDwABLgAECgUJBwAGAAAAAA==.Lindesong:BAAALgAECgEJAQABLgAFFAYJEAAQAH4gAA==.Lisondrel:BAAALgAECgUJBwAAAA==.',
Lo='Lockbone:BAAALgAECgMJAwAAAA==.Loops:BAABLgAECn8dAAIiAAgJkR+lCgD4AQAiAAgJkR+lCgD4AQAAAA==.Lorette:BAABLgAECn8ZAAMBAAgJ3RTkLQCNAQABAAgJ3RTkLQCNAQACAAYJiRbBIgArAQAAAA==.Lovelychow:BAAALgADCgYJCQAAAA==.',
Lu='Luuma:BAAALgADCgkJEQABLgAECgYJFAASAGUVAA==.',
Lw='Lwinterheart:BAAALgADCgEJAQAAAA==.',
Ly='Ly:BAAALgADCgUJBQAAAA==.Lymriina:BAACLgAFFH8GAAIUAAMJaROfDQARAQAUAAMJaROfDQARAQAuAAQKfxwAAhQACAlsI5kHABYDABQACAlsI5kHABYDAAEuAAUUBgkQABAAfiAA.Lyr:BAAALgADCgcJBwAAAA==.',
Ma='Machotedan:BAABLgAECn8nAAISAAgJmR/7EgBiAgASAAgJmR/7EgBiAgAAAA==.Macmittens:BAAALgAECgMJAwAAAA==.Magedude:BAAALgAECgIJAgAAAA==.Maliken:BAABLgAECn8fAAIFAAgJ7B3zJQCkAgAFAAgJ7B3zJQCkAgAAAA==.Mamadrag:BAABLgAECn8fAAQcAAgJORmyCgCmAQAcAAcJhhiyCgCmAQAeAAMJXgbaWABbAAAdAAIJ7wZYEwBYAAAAAA==.Mambø:BAAALgADCgYJBgAAAA==.Managua:BAAALgADCgEJAQAAAA==.Mandwa:BAAALgAECgYJBgABLgAECggJIgAaANwfAA==.Mario:BAABLgAECn8ZAAIEAAcJJxjhVwBmAQAEAAcJJxjhVwBmAQAAAA==.Masivewin:BAAALgAECgEJAQAAAA==.Mastashifta:BAAALgAECgMJCAAAAA==.Matryoshka:BAAALgAECgUJCAAAAA==.Mattsadler:BAAALgAECgEJAgAAAA==.Maverex:BAAALgAFFAEJAQAAAA==.Mavok:BAAALgAECgEJAQAAAA==.Maxxim:BAAALgAECgMJAwAAAA==.',
Me='Mechamonk:BAAALgADCgIJAgAAAA==.Merczdk:BAAALgADCgYJDAAAAA==.Merczpal:BAAALgAECgYJBgAAAA==.Meta:BAAALgAECgYJEQAAAA==.',
Mi='Mindfreeze:BAAALgADCgUJBQAAAA==.Minthara:BAAALgADCgUJCgAAAA==.Missdemon:BAAALgADCgUJBgAAAA==.Missikrissi:BAAALgADCgYJBgAAAA==.Missmorrigan:BAAALgAECgQJCQAAAA==.Missî:BAAALgAECgcJDAAAAA==.Mists:BAACLgAFFH8KAAIfAAUJ1xzqDgBnAQAfAAUJ1xzqDgBnAQAuAAQKfyMAAx8ACAmCJOwLABsDAB8ACAmCJOwLABsDACMAAgmaHfFHAJcAAAAA.Miththrawndo:BAABLgAECn8aAAMWAAgJMBhFEgDnAQAWAAgJMBhFEgDnAQAIAAEJAAAvGwAIAAAAAA==.',
Ml='Ml:BAABLgAECn8UAAMjAAYJVh4GCwAPAgAjAAYJVh4GCwAPAgAfAAQJDA99agD3AAAAAA==.',
Mo='Moldevort:BAAALgAECgMJBwAAAA==.Momjeans:BAABLgAECn8gAAMmAAgJah6cAQCzAgAmAAcJjSGcAQCzAgAEAAYJEhXuYABQAQAAAA==.Monfanth:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.Morningumbra:BAAALgADCgIJAgAAAA==.',
Ms='Mstryoda:BAAALgADCgUJCAAAAA==.',
Mu='Muramasa:BAAALgAECgIJAwABLgAECgcJJQAZAM0fAA==.',
My='Myfriendtold:BAAALgADCgEJAgAAAA==.Mythunsarian:BAABLgAECn8nAAInAAgJoBCDDgCZAQAnAAgJoBCDDgCZAQAAAA==.',
['Mä']='Mäylä:BAABLgAECn8cAAIDAAgJFg+qLABzAQADAAgJFg+qLABzAQAAAA==.',
['Mí']='Míst:BAABLgAECn8rAAISAAgJnBcSNwCiAQASAAgJnBcSNwCiAQAAAA==.',
Na='Nazaline:BAAALgADCgIJAgAAAA==.',
Ne='Necrohealiac:BAAALgAECgEJBAAAAA==.Necromerc:BAAALgAECgQJBAAAAA==.Necrotizer:BAAALgADCgMJAwAAAA==.Nephie:BAABLgAECn8dAAInAAgJghyfCQDyAQAnAAgJghyfCQDyAQAAAA==.Netazia:BAAALgADCgcJGQAAAA==.Nethralfus:BAAALgAECgEJAQAAAA==.Nezqk:BAACLgAFFH8GAAIFAAQJZQQGQwAJAQAFAAQJZQQGQwAJAQAuAAQKfyIAAgUACAnXFQ9dANsBAAUACAnXFQ9dANsBAAAA.',
Ni='Niano:BAAALgAECgEJAQAAAA==.',
Nm='Nmnenthe:BAAALgAECgUJBgAAAA==.',
No='Noelytv:BAAALgADCgcJBwAAAA==.Norman:BAAALgADCgEJAgAAAA==.November:BAAALgADCgEJAQAAAA==.Noxren:BAAALgAFFAEJAgAAAA==.',
['Nî']='Nîstø:BAABLgAECn8hAAQRAAgJFRdsDgDeAQARAAcJzBhsDgDeAQAJAAYJIByiFwDQAQASAAQJAArF1QBaAAAAAA==.',
Ob='Obin:BAABLgAECn8gAAIKAAgJUxXrGgCQAQAKAAgJUxXrGgCQAQAAAA==.',
Oh='Oharachloe:BAAALgADCgYJBgAAAA==.',
Ol='Ollenbock:BAAALgADCgQJBAABLgAFFAYJEAAQAH4gAA==.',
Or='Orhanu:BAAALgAECgcJCAAAAA==.',
Ou='Outbbreakk:BAAALgAECgUJBwAAAA==.',
Ow='Owendriel:BAABLgAECn8XAAIaAAgJTBhkOwAGAgAaAAgJTBhkOwAGAgAAAA==.',
Pa='Padocus:BAAALgADCgIJAgAAAA==.Pajamas:BAABLgAECn8xAAIQAAgJaCDrCgDuAgAQAAgJaCDrCgDuAgAAAA==.Palyamorous:BAAALgADCgUJBQAAAA==.Pandress:BAABLgAECn8bAAIQAAYJPhfPOQBmAQAQAAYJPhfPOQBmAQAAAA==.Pankake:BAAALgAECgEJAQABLgAECggJJwAXADYfAA==.Paralysis:BAAALgAECgIJAwABLgAFFAMJCAAZAH8IAA==.',
Pe='Peryite:BAABLgAECn8fAAMPAAcJQRLWGABsAQAPAAcJyxHWGABsAQABAAYJrwohRwAdAQAAAA==.',
Ph='Phelris:BAAALgAECgYJBgAAAA==.',
Pi='Pillpusher:BAAALgAECgMJBAAAAA==.Pisscat:BAAALgAECgUJCgAAAA==.',
Po='Polymerase:BAAALgAECgEJAQABLgAECggJIgAFAKAfAA==.',
Pr='Prideindeath:BAAALgAECgUJBQAAAA==.Promiscuity:BAAALgAECgcJCQAAAA==.Protròast:BAAALgAECgIJAgAAAA==.Prængle:BAAALgAECgYJDwAAAA==.',
Ps='Psypriest:BAABLgAFFH8JAAIBAAQJKxm+CAA4AQABAAQJKxm+CAA4AQABLgAFFAYJGgABACsZAA==.',
Pu='Pulverine:BAAALgADCgcJDgAAAA==.',
Qu='Quarantinia:BAAALgADCgEJAQAAAA==.',
Ra='Rabbi:BAABLgAECn8WAAMCAAYJWxPPHgBGAQACAAYJWxPPHgBGAQABAAUJaA7MTgD9AAAAAA==.Ragerunnerx:BAAALgAECggJDwAAAA==.Rahfna:BAAALgAECgEJAQAAAA==.Rakan:BAAALgADCgIJAgAAAA==.Raynare:BAAALgAECgIJAwAAAA==.',
Re='Redall:BAABLgAECn8XAAITAAcJSAdeDgAGAQATAAcJSAdeDgAGAQAAAA==.Reesespbc:BAABLgAECn8iAAIEAAgJ3Q7FSgCIAQAEAAgJ3Q7FSgCIAQAAAA==.Reina:BAABLgAECn8UAAISAAYJZRXlWwA4AQASAAYJZRXlWwA4AQAAAA==.Reinir:BAABLgAECn8oAAIgAAgJaiNRAgDFAgAgAAgJaiNRAgDFAgAAAA==.Reinz:BAAALgAECgUJBQAAAA==.Rektagar:BAABLgAECn8mAAMOAAkJdCNaCQBEAgAOAAcJwyJaCQBEAgANAAQJSR3aLwBRAQABLgAFFAYJEAAQAH4gAA==.Ressandra:BAAALgADCgcJBwAAAA==.Reyvanna:BAAALgADCgEJAQAAAA==.',
Ro='Roar:BAAALgAECgEJAQABLgAECggJJQAFALAQAA==.Robert:BAAALgADCgEJAQAAAA==.Rosavyra:BAAALgAECggJCQAAAA==.Roshara:BAAALgAECgQJBgAAAA==.',
['Rö']='Rös:BAACLgAFFH8KAAIEAAQJBBzhHwBpAQAEAAQJBBzhHwBpAQAuAAQKfywAAwQACAmLHVw7AIkCAAQACAmLHVw7AIkCACgAAQlfINwMAF0AAAAA.',
['Rü']='Rübblë:BAAALgADCgcJCwAAAA==.',
Sa='Saberie:BAAALgAECgMJAwAAAA==.Salamun:BAAALgAECgQJBQAAAA==.Salaria:BAABLgAECn8bAAIaAAcJawl1VAD9AAAaAAcJawl1VAD9AAAAAA==.Salen:BAABLgAECn8pAAIlAAgJlRf7BAAIAgAlAAgJlRf7BAAIAgAAAA==.Salina:BAEBLgAECn8kAAIbAAcJyRjYCABRAQAbAAcJyRjYCABRAQAAAA==.Sandraia:BAABLgAECn8fAAIFAAgJrRs2MAC4AQAFAAgJrRs2MAC4AQAAAA==.Sandstique:BAABLgAECn8WAAINAAkJpyFqCADvAgANAAkJpyFqCADvAgAAAA==.Sandtwig:BAAALgADCgEJAQAAAA==.Sandweaver:BAAALgADCgEJAQAAAA==.Sanjira:BAABLgAECn8XAAIkAAgJBgYSCAALAQAkAAgJBgYSCAALAQAAAA==.Sarusuby:BAABLgAECn8dAAIpAAcJYRdxDQCvAQApAAcJYRdxDQCvAQAAAA==.',
Sc='Schuffles:BAAALgAECgEJAQAAAA==.Scottyfist:BAABLgAECn8YAAIXAAgJdh97FgBVAgAXAAgJdh97FgBVAgAAAA==.Scottymac:BAAALgADCgYJBgABLgAECgkJGAAXAHYfAA==.',
Se='Sealion:BAACLgAFFH8JAAMJAAMJVyCZEQDDAAAJAAIJQB2ZEQDDAAASAAIJkgsQRgChAAAuAAQKfxoAAwkACQmUF10WAF4CAAkACQmUF10WAF4CABIAAwlkI9GOAM8AAAAA.Seetah:BAABLgAECn8aAAIBAAgJgCGzBADEAgABAAgJgCGzBADEAgAAAA==.Seetur:BAAALgAECgQJBAAAAA==.Serratus:BAABLgAECn8sAAQeAAgJyh7OCQAvAgAeAAgJixrOCQAvAgAdAAgJmhcRAwD6AQAcAAEJTgSLKQAuAAAAAA==.Setcher:BAAALgADCgEJAQAAAA==.',
Sh='Shadaddy:BAAALgAECggJDAABLgAECggJIAAFAIIfAA==.Shadoweyes:BAAALgAECgcJCgAAAA==.Shadowsyther:BAAALgAECgYJBgAAAA==.Shamax:BAAALgADCgEJAgABLgADCgUJBQAGAAAAAA==.Shamommy:BAAALgAECgMJBgAAAA==.Shayes:BAABLgAECn8cAAIpAAgJzR0bBAA/AgApAAgJzR0bBAA/AgAAAA==.Shifue:BAAALgAECgMJBAAAAA==.Shimmerstar:BAABLgAECn8UAAISAAkJuxFpJwDjAQASAAkJuxFpJwDjAQAAAA==.',
Si='Sigg:BAAALgAECgUJBQAAAA==.Silexe:BAAALgAECgUJBwABLgAECggJKAAhAPYhAA==.',
Sk='Skathae:BAAALgAECgEJAQABLgAECgcJGQAcAKUYAA==.Skåld:BAABLgAECn8bAAIFAAgJDxg5NQCkAQAFAAgJDxg5NQCkAQAAAA==.',
Sl='Slipperyboi:BAAALgAECgYJBgAAAA==.',
Sn='Snuffles:BAABLgAECn8cAAIiAAgJ1xqTCwDrAQAiAAgJ1xqTCwDrAQAAAA==.Snugs:BAAALgADCgEJAQAAAA==.',
So='Soldraca:BAAALgAECgMJBgAAAA==.Soulence:BAAALgAECgMJBAAAAA==.Soymaster:BAAALgADCgYJBgABLgAFFAEJAQAGAAAAAA==.',
St='Stinkbug:BAAALgADCgEJAQAAAA==.Stutters:BAABLgAECn8iAAMFAAgJoB/QDgCLAgAFAAgJoB/QDgCLAgAWAAUJIBgkIABDAQAAAA==.',
Su='Sudachi:BAABLgAECn8VAAMLAAkJkhqMBACkAgALAAkJkhqMBACkAgAKAAIJAw1PlABuAAABLgAFFAQJBwAZAF0YAA==.Sunnyräy:BAAALgADCgcJDQAAAA==.',
Sw='Swineflu:BAAALgAECgMJAwAAAA==.Swizzjenks:BAAALgADCgMJAwAAAA==.',
Sy='Synonym:BAAALgADCgcJBwAAAA==.Syrprize:BAAALgADCgEJAQABLgAECgcJFgAXAGMgAA==.',
['Sý']='Sýndrá:BAABLgAECn8ZAAIjAAgJkCAbAQCOAgAjAAgJkCAbAQCOAgAAAA==.',
Ta='Tacobob:BAACLgAFFH8IAAIDAAQJBgaKHgDkAAADAAQJBgaKHgDkAAAuAAQKfysAAgMACAlvFm03AMkBAAMACAlvFm03AMkBAAAA.Taethron:BAAALgADCgUJBQAAAA==.Taffeta:BAAALgADCgEJAQAAAA==.Taffyboy:BAAALgADCggJCgAAAA==.Talysiah:BAAALgAECgcJEgAAAA==.Tannir:BAAALgAECgEJAQAAAA==.Tarogen:BAAALgADCgQJBgABLgAFFAQJBwAYALUdAA==.Tavok:BAABLgAECn8jAAMKAAgJzCJ5BAC4AgAKAAgJzCJ5BAC4AgAgAAEJ+BUFRAA9AAAAAA==.',
Te='Tenacious:BAAALgADCgcJDAAAAA==.Tene:BAAALgADCgMJAwAAAA==.Teratots:BAAALgADCgYJBgAAAA==.Testament:BAAALgADCgcJCAAAAA==.',
Th='Thenna:BAAALgAECgMJAwAAAA==.Theosclaws:BAAALgADCgcJDgAAAA==.Theramier:BAAALgADCgIJAgAAAA==.Thiux:BAABLgAECn8VAAMfAAgJVBxJFQA3AgAfAAcJVBxJFQA3AgAjAAEJAABnXQBWAAAAAA==.Thotsnprayrs:BAAALgADCgUJCAABLgAECgcJFgAXAGMgAA==.Thourin:BAAALgADCgEJAQAAAA==.Thrappy:BAABLgAECn8lAAINAAkJ7R5VBAD7AgANAAkJ7R5VBAD7AgAAAA==.Thráwñ:BAAALgAECgIJAwABLgAECgYJCgAGAAAAAA==.',
Ti='Tiddyhammer:BAABLgAECn8cAAMJAAcJMhRhRQBiAQAJAAcJMhRhRQBiAQASAAMJ8xotfwDuAAAAAA==.Tintaglia:BAAALgAECgUJBQABLgAECgcJGQAEACcYAA==.Tirtun:BAABLgAECn8fAAIEAAgJgR3dIQAhAgAEAAgJgR3dIQAhAgAAAA==.',
To='Tomek:BAABLgAECn8kAAMiAAkJrBpxBAB+AgAiAAkJKhdxBAB+AgATAAcJxB/FBQDEAQAAAA==.Totemetot:BAAALgAECgMJBgAAAA==.',
Tr='Treemourne:BAAALgADCgEJAQAAAA==.Triggeer:BAABLgAECn8tAAIgAAkJgxYuCQDjAQAgAAkJgxYuCQDjAQAAAA==.',
Tu='Tully:BAAALgADCgEJAQAAAA==.Turalus:BAAALgADCgYJBgAAAA==.Turina:BAAALgAECgYJEAAAAA==.',
Tw='Twelvekill:BAACLgAFFH8JAAIQAAQJigkDHAArAQAQAAQJigkDHAArAQAuAAQKfysAAhAACAlzGiYaAGsCABAACAlzGiYaAGsCAAAA.',
Ty='Tyliaa:BAAALgAECggJCwABLgAECggJHwAcADkZAA==.Tylidus:BAAALgAECgUJCQAAAA==.Tyranny:BAAALgAECgYJEQAAAA==.',
Ub='Ubisami:BAAALgAECggJEgAAAA==.',
Ud='Udderfailure:BAAALgADCgIJAgAAAA==.',
Ul='Ullur:BAAALgADCgEJAgAAAA==.Ultramon:BAABLgAECn8bAAISAAcJcA+kTgBaAQASAAcJcA+kTgBaAQAAAA==.Uly:BAAALgAECgUJCQAAAA==.',
Un='Unwell:BAAALgAECgUJCgABLgAFFAMJBgAUAEIeAA==.',
Ur='Urgoochness:BAABLgAECn8hAAIDAAgJshZDHQDZAQADAAgJshZDHQDZAQAAAA==.Urikhai:BAAALgAECgQJBQAAAA==.',
Va='Vaellvoid:BAAALgAECgMJAwAAAA==.Vainglorious:BAAALgAECgQJCgABLgAECggJFwAWALIaAA==.Valanora:BAABLgAECn8fAAIhAAgJ6hmjAwBbAgAhAAgJ6hmjAwBbAgAAAA==.Valdis:BAAALgADCgcJDgABLgAECgYJGAAEAFgQAA==.Valinaxius:BAAALgAECgQJDwAAAA==.Valphalk:BAAALgADCggJCQAAAA==.Vanastasia:BAAALgAECgQJBgAAAA==.Vapturov:BAAALgAECgQJCAAAAA==.',
Ve='Veeks:BAAALgAECgcJDwAAAA==.Velikirn:BAABLgAECn8tAAMZAAgJ5h90CAA6AgAZAAgJRx90CAA6AgAXAAcJZhhmEgCuAQAAAA==.Vellwinnalas:BAAALgADCgUJCAAAAA==.Verah:BAAALgADCgYJBgAAAA==.Versø:BAABLgAECn8mAAQkAAcJNxtGBACeAQAVAAYJSBvvBgD9AQAkAAcJmxZGBACeAQAUAAQJ1hmBPgAoAQAAAA==.',
Vi='Villageinn:BAAALgAECgMJAwAAAA==.Vine:BAAALgAECgYJDAAAAA==.Vixxon:BAABLgAECn8dAAIQAAgJ7BeGHADyAQAQAAgJ7BeGHADyAQAAAA==.',
Vl='Vly:BAAALgAECggJEAAAAA==.Vlyrae:BAAALgAECgEJAQAAAA==.Vlyzen:BAAALgAECgQJBQAAAA==.',
Vo='Voidhearted:BAABLgAECn8xAAICAAgJ2h7mBQB8AgACAAgJ2h7mBQB8AgAAAA==.',
['Vì']='Vìolet:BAAALgAECgUJDAABLgAECggJIAAHAKAgAA==.',
Wa='Waggleton:BAAALgAECgEJAgAAAA==.Warp:BAAALgADCgEJAQAAAA==.Wasted:BAAALgADCgEJAQABLgAECgkJJQANAO0eAA==.Wayshua:BAAALgAECgUJBwAAAA==.',
We='Wearyouout:BAAALgADCgUJBQAAAA==.Wemon:BAAALgAECgUJBQAAAA==.Werkajerk:BAABLgAECn8eAAMXAAgJPiFEDAD+AQAXAAgJPiFEDAD+AQAZAAEJwBc6dABEAAABLgAFFAUJEwAOAAIlAA==.Werkjathal:BAACLgAFFH8TAAQOAAUJAiVwAwC2AQAOAAQJAiVwAwC2AQAlAAUJfh0ZAQCSAQANAAIJhwenGwCKAAAuAAQKfyoABA4ACQlJIxYOAMICAA4ACAkhIxYOAMICAA0ABwnDI4sNAK8CACUABglpHpkHALYBAAAA.Wetribs:BAAALgADCgkJCQAAAA==.',
Wh='Whereareyou:BAAALgADCgkJCQABLgAECgYJFgAQAPkYAA==.Whitedog:BAAALgAECgEJAQAAAA==.Whitetank:BAABLgAECn8gAAIRAAgJ9hiiCADBAQARAAgJ9hiiCADBAQAAAA==.',
Wi='Willowbeard:BAAALgAECgQJBwAAAA==.Winnelepooh:BAAALgADCgQJBAAAAA==.',
Wo='Wobys:BAABLgAECn8dAAIYAAgJWBQQGACRAQAYAAgJWBQQGACRAQAAAA==.Wolfblitzer:BAABLgAECn8eAAISAAgJ6xixTAD8AQASAAgJ6xixTAD8AQAAAA==.Wolfmanbro:BAAALgADCggJCAAAAA==.Worldbane:BAABLgAECn8dAAIjAAcJ1BGZBwBpAQAjAAcJ1BGZBwBpAQAAAA==.',
['Wä']='Wärchild:BAAALgADCgcJJwAAAA==.',
Xa='Xalaa:BAAALgAECgYJCgAAAA==.Xalataxfraud:BAAALgAECgQJAwAAAA==.Xanthos:BAAALgAECgMJBAAAAA==.',
Xe='Xenthriel:BAAALgADCgcJBwAAAA==.',
Xi='Xianyu:BAAALgAECgUJDAAAAA==.Ximmer:BAAALgAECgEJAQAAAA==.',
Xr='Xrispy:BAAALgAECgMJAwABLgAECgkJJQANAO0eAA==.',
Ya='Yarian:BAAALgAECgMJAwAAAA==.',
Yo='Yormin:BAAALgAECgUJEAAAAA==.Yorra:BAAALgAECgIJAgAAAA==.',
Yu='Yuzuu:BAABLgAECn8WAAINAAYJGQ6lUABCAQANAAYJGQ6lUABCAQAAAA==.',
Za='Zachhunter:BAABLgAFFH8QAAMQAAYJfiDVBwB+AQAQAAQJkCLVBwB+AQATAAYJDhEjBgBlAQAAAA==.Zan:BAACLgAFFH8KAAMOAAQJ2wvIFAAMAQAOAAQJ2wvIFAAMAQANAAIJ4hArGQCXAAAuAAQKfysAAw4ACAmZH6kTAIICAA4ACAmZH6kTAIICAA0AAgmgC76JAG0AAAAA.',
Zo='Zohaan:BAAALgADCgEJAwAAAA==.Zoma:BAAALgADCggJDgAAAA==.',
Zu='Zuhura:BAAALgAECgUJCwAAAA==.Zultrix:BAAALgAECgMJBQAAAA==.',
Zy='Zylaeri:BAAALgAECggJDQAAAA==.',
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

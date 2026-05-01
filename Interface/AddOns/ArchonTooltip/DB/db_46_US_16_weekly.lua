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

local lookup = {'Priest-Holy','Priest-Shadow','Druid-Restoration','Mage-Frost','Unknown-Unknown','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Warrior-Fury','Warrior-Arms','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','DeathKnight-Unholy','Paladin-Protection','Warrior-Protection','Hunter-Survival','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','DeathKnight-Blood','Warlock-Affliction','Mage-Arcane','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Absoul:BAABLgAECn8iAAMBAAgJwCHiAQABAwABAAgJwCHiAQABAwACAAEJcQPzaAAmAAAAAA==.',
Ac='Acedia:BAABLgAECn8kAAIBAAgJURa2CQANAgABAAgJURa2CQANAgAAAA==.',
Ad='Adellas:BAABLgAECn8fAAIDAAgJNh7iCwBKAgADAAgJNh7iCwBKAgAAAA==.Adern:BAABLgAECn8dAAICAAcJ2B6IEgBkAgACAAcJ2B6IEgBkAgAAAA==.Adon:BAABLgAECn8cAAIEAAgJuByOFwAgAgAEAAgJuByOFwAgAgAAAA==.Adondruel:BAAALgAECgEJAQAAAA==.',
Ae='Aelali:BAAALgAECgQJBQAAAA==.Aelith:BAAALgAECgcJEgAAAA==.',
Af='Afador:BAAALgAECgEJAQAAAA==.',
Ag='Ageling:BAAALgADCgQJAgAAAA==.',
Ak='Akeno:BAAALgAECgMJAwABLgAECgEJAQAFAAAAAA==.Akrom:BAAALgADCgEJAgAAAA==.',
Al='Aladestar:BAACLgAFFH8GAAMGAAMJqAqmEgDgAAAGAAMJqAqmEgDgAAADAAIJHxBwGgCTAAAuAAQKfyUAAwMACAnIGqwbAF4CAAMACAnIGqwbAF4CAAYACAlfIAoiAOwBAAAA.Albinodargon:BAAALgAECgQJCwAAAA==.Alderleise:BAABLgAECn8UAAIDAAcJrwq+NAAFAQADAAcJrwq+NAAFAQAAAA==.Alecc:BAAALgAECgYJCwAAAA==.Alexein:BAABLgAECn8iAAIHAAgJ7RQOBQD2AQAHAAgJ7RQOBQD2AQAAAA==.Alienspace:BAAALgADCgEJAQAAAA==.',
Am='Amets:BAABLgAECn8cAAIIAAgJ5iM/AQAyAwAIAAgJ5iM/AQAyAwAAAA==.Amydh:BAAALgAECgIJBgAAAA==.',
An='Anabel:BAAALgADCgkJCwAAAA==.Anamii:BAAALgADCgEJAQAAAA==.Andorsi:BAAALgAECgYJCAAAAA==.Anglechow:BAAALgADCgUJBQAAAA==.',
Ar='Arachne:BAABLgAECn8cAAICAAYJ4gqrNQA+AQACAAYJ4gqrNQA+AQAAAA==.Aranax:BAAALgADCgEJAgAAAA==.Arce:BAAALgAECgQJCgAAAA==.Architeleaf:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Areafiftymoo:BAABLgAECn8iAAMJAAgJ6AclHABPAQAJAAgJtAclHABPAQAKAAEJ3gTuRwAmAAAAAA==.Arthurleywin:BAAALgADCgIJAgAAAA==.Arysia:BAAALgAECgQJCgAAAA==.Aryya:BAABLgAECn82AAMLAAgJZiGlAQB/AgALAAgJZiGlAQB/AgAGAAMJHAeyZwCCAAAAAA==.',
As='Astralbreak:BAAALgADCgEJAQABLgAECgUJBgAFAAAAAA==.',
At='Athelia:BAAALgADCgEJAQAAAA==.',
Av='Avalan:BAABLgAECn8lAAIJAAgJRh/ZBAByAgAJAAgJRh/ZBAByAgAAAA==.Avashammy:BAABLgAECn8fAAMMAAgJ+BzAEQDkAQAMAAgJ+BzAEQDkAQANAAEJbwh1VQAtAAAAAA==.Avesia:BAABLgAECn8aAAIOAAYJUBadIgB/AQAOAAYJUBadIgB/AQAAAA==.Aviendah:BAAALgAECgcJDgAAAA==.',
Aw='Awsomeonet:BAAALgAECgYJEQAAAA==.',
Ay='Ayot:BAAALgAECgcJEwAAAA==.',
Az='Azdfghop:BAACLgAFFH8SAAMPAAUJRR9xFAAaAQAPAAQJ5htxFAAaAQAQAAQJbRgIFQD0AAAuAAQKfyAAAxAACQm2Ih8PAMUCABAACAnIHh8PAMUCAA8ACAmZIYo/ALEBAAAA.Azzinotica:BAAALgAECgEJAQAAAA==.',
Ba='Babeshot:BAABLgAECn8VAAIPAAgJ2g/pHACyAQAPAAgJ2g/pHACyAQAAAA==.Babezila:BAAALgAECgYJDgAAAA==.Badshahprime:BAABLgAECn8eAAIRAAgJPhphKgB7AgARAAgJPhphKgB7AgAAAA==.Barbiegrill:BAABLgAECn8dAAMSAAgJ7x79DwCmAgASAAgJEB79DwCmAgATAAUJVRxACQCuAQABLgAFFAIJAwAFAAAAAA==.Baykin:BAABLgAECn8gAAIUAAgJJRuuCAAEAgAUAAgJJRuuCAAEAgAAAA==.',
Bb='Bbeastt:BAAALgADCgEJAgAAAA==.',
Be='Beefyfivelyr:BAAALgADCgcJBwAAAA==.Berandas:BAABLgAECn8UAAMVAAcJ/hEAJgCDAQAVAAcJ/hEAJgCDAQAWAAUJhA1+IADjAAAAAA==.Bereessielin:BAAALgAECgQJBgAAAA==.Berkowitz:BAAALgAECgUJDQAAAA==.',
Bi='Bigbear:BAAALgADCgEJAQABLgADCgMJAwAFAAAAAA==.',
Bl='Blaaze:BAAALgAECgQJBgAAAA==.Blaiddyd:BAABLgAECn8eAAIPAAcJeyAmDgAqAgAPAAcJeyAmDgAqAgAAAA==.Blead:BAAALgAFFAIJAwAAAA==.Blinkerr:BAAALgADCgkJDAAAAA==.',
Br='Brahot:BAAALgAECgEJAQAAAA==.Brain:BAAALgAECgQJAwAAAA==.Brandawn:BAAALgADCgYJBgAAAA==.Branwarden:BAAALgAECgYJCwAAAA==.Brewsle:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebot:BAAALgAECgMJAwABLgAECggJEwAXALIdAA==.Bullchitz:BAABLgAECn8WAAIPAAYJ+RjcLABeAQAPAAYJ+RjcLABeAQAAAA==.Bullchitza:BAAALgADCgcJBwABLgAECgYJFgAPAPkYAA==.Burningooch:BAAALgADCgEJAQAAAA==.',
['Bã']='Bãyy:BAAALgAECgYJBgAAAA==.',
['Bæ']='Bæyy:BAAALgADCgUJCgABLgAECgYJBgAFAAAAAA==.',
Ca='Calador:BAAALgAECggJCgAAAA==.Capybara:BAAALgAECgYJCwAAAA==.Caster:BAAALgADCgQJBAAAAA==.Cathbad:BAAALgADCgEJAQAAAA==.Caylynn:BAAALgADCgkJFAAAAA==.',
Ce='Celyne:BAABLgAECn8TAAIXAAgJsh3+KwBOAgAXAAgJsh3+KwBOAgAAAA==.Cereza:BAAALgAECgEJAQAAAA==.',
Ch='Chaoslock:BAAALgADCgMJAwAAAA==.Chicknfajita:BAAALgAECgYJCAAAAA==.Chrissi:BAABLgAECn8UAAIDAAgJeQomNwD5AAADAAgJeQomNwD5AAAAAA==.',
Ci='Cinco:BAAALgADCgUJBQAAAA==.',
Cl='Clearly:BAAALgADCgQJAwAAAA==.',
Co='Cocytus:BAAALgAECgIJAwAAAA==.Colbith:BAAALgADCgMJAwAAAA==.Conquest:BAAALgAECgYJEAAAAA==.Cordaddy:BAABLgAECn8gAAIDAAgJnSUrBADrAgADAAgJnSUrBADrAgAAAA==.Cordragu:BAAALgAECgMJAwABLgAECggJIAADAJ0lAA==.Corinthe:BAAALgAECgUJBwABLgAECggJIAADAJ0lAA==.Corinthin:BAABLgAECn8fAAIMAAcJ9Bg7FADKAQAMAAcJ9Bg7FADKAQAAAA==.',
Cr='Crinn:BAAALgAECggJDgAAAA==.Crizmon:BAABLgAECn8rAAIHAAgJGSE/AQD5AgAHAAgJGSE/AQD5AgAAAA==.Cryomancer:BAAALgADCgQJBAAAAA==.Crõwley:BAAALgADCgYJBgABLgAECgcJFgAYAE0XAA==.',
Da='Damage:BAAALgAECgEJAQAAAA==.Damorax:BAAALgAECgYJDAAAAA==.Darazarke:BAACLgAFFH8WAAIYAAUJKxTDBQCMAQAYAAUJKxTDBQCMAQAuAAQKfyMABBkACAlsHg8EANICABkACAlsHg8EANICABgABwmTHKkOAE4CABoAAQlwGHRdAEQAAAAA.Darkcursed:BAABLgAECn8WAAIbAAcJggggSwAPAQAbAAcJggggSwAPAQAAAA==.Darksudge:BAAALgAECgEJAQAAAA==.Darps:BAAALgAECgYJCAAAAA==.Daybreak:BAAALgAECgYJCgAAAA==.Dayquil:BAEBLgAECn8fAAMRAAgJuRy1NgBIAgARAAgJuRy1NgBIAgAIAAEJwRmVSABJAAAAAA==.',
De='Deadaddie:BAABLgAECn8ZAAMHAAcJ1xtHBABrAQAcAAcJKxdyVgDuAQAHAAYJOxdHBABrAQAAAA==.Deamoneyes:BAAALgAECgEJAgAAAA==.Decastamon:BAAALgAECgYJBgAAAA==.Delin:BAAALgADCgQJBwABLgAFFAUJFgAYACsUAA==.Deluxdh:BAAALgAECgMJAwAAAA==.Demonslinger:BAAALgADCgUJBQAAAA==.Dendrel:BAAALgADCggJCAAAAA==.Derpspally:BAAALgADCgcJEgAAAA==.Derpspunch:BAABLgAECn8WAAIVAAgJThsnBQCAAgAVAAgJThsnBQCAAgAAAA==.Destrox:BAAALgADCgYJBgAAAA==.Dezatra:BAAALgAECgMJAwAAAA==.Deíty:BAAALgADCgUJBQAAAA==.',
Di='Diane:BAEALgADCggJDgAAAA==.Dieselcon:BAABLgAECn8uAAMdAAgJnRXFDQDpAQAdAAgJnRXFDQDpAQARAAEJswydRAEyAAAAAA==.Dieseletta:BAAALgAECgMJAwAAAA==.',
Do='Domdog:BAABLgAECn8qAAIEAAgJXBSCJgDMAQAEAAgJXBSCJgDMAQAAAA==.Dontforget:BAABLgAECn8VAAIIAAYJLRRkGACLAQAIAAYJLRRkGACLAQAAAA==.Dookiesmash:BAABLgAECn8UAAIeAAgJJCLBCQB8AgAeAAgJJCLBCQB8AgAAAA==.Doomblast:BAAALgADCgIJAgAAAA==.Doomdealer:BAAALgAFFAEJAQAAAA==.Doomed:BAAALgADCgQJBAABLgAECgcJFgAUAGMgAA==.Doomrage:BAAALgADCgcJFAAAAA==.Doomsdead:BAAALgADCgcJBwAAAA==.Doomshock:BAAALgADCgYJBQAAAA==.',
Dr='Draftymonk:BAABLgAECn8XAAMUAAcJOh/aDwCVAQAUAAYJuR/aDwCVAQAWAAUJTRouFABMAQAAAA==.Drax:BAAALgAECgYJEgAAAA==.Dreadgar:BAAALgAECgQJBAABLgAFFAEJAQAFAAAAAA==.Dritzzfive:BAAALgAECgYJDgAAAA==.Dritzzwar:BAAALgAECgYJDAAAAA==.',
Ei='Eilica:BAAALgAECgUJBQAAAA==.',
Ek='Ekaine:BAAALgADCgQJBAABLgAECgYJGAAEAFgQAA==.',
El='Elandrus:BAAALgAECgQJBAABLgAECgcJFgAYAE0XAA==.Elleynre:BAAALgADCgMJAwAAAA==.Elrëim:BAAALgAECggJDQAAAA==.Elwendigo:BAAALgADCgMJAwAAAA==.Elwyna:BAAALgADCgIJAgAAAA==.',
Em='Emmara:BAAALgAECgYJEAAAAA==.',
En='Enhancement:BAAALgADCgcJDQABLgAFFAUJDwANAAIlAA==.Enitar:BAAALgAECgUJCQABLgAECggJEwAXALIdAA==.',
Er='Erata:BAAALgAECgQJBwAAAA==.Erlangshen:BAAALgADCgUJBQAAAA==.Erravis:BAAALgADCgcJDwAAAA==.',
Ev='Evarion:BAAALgADCgEJAQAAAA==.Eviaei:BAAALgAECgMJAwAAAA==.Evulise:BAAALgADCgYJBAAAAA==.',
Ez='Ezalan:BAAALgADCgcJBwAAAA==.Ezlok:BAAALgAFFAEJAQAAAA==.Ezorreodd:BAAALgADCgQJBAAAAA==.Ezzorreodd:BAAALgAECgUJCAAAAA==.',
Fa='Fae:BAAALgAECgcJEgAAAA==.Falcyon:BAAALgADCgkJEAAAAA==.Falerin:BAABLgAECn8UAAIDAAcJOxEgLwAhAQADAAcJOxEgLwAhAQAAAA==.Farenheit:BAABLgAECn8jAAMGAAgJgRbxCQDwAQAGAAgJgRbxCQDwAQADAAQJlA0bowCDAAAAAA==.Fatel:BAAALgADCgQJBAABLgAFFAIJAwAFAAAAAA==.Faydwer:BAAALgADCgMJBAAAAA==.Fayfox:BAAALgADCgkJFwAAAA==.',
Fe='Feenex:BAAALgAECgUJBgAAAA==.',
Fi='Finick:BAAALgAECgYJCwAAAA==.Firedealer:BAABLgAECn8bAAIQAAgJ2xJgBADKAQAQAAgJ2xJgBADKAQAAAA==.Firnen:BAABLgAECn8WAAIYAAcJTRcUGgC7AQAYAAcJTRcUGgC7AQAAAA==.',
Fl='Flahash:BAAALgAECgMJAwAAAA==.Flappy:BAAALgAECgcJDwABLgAECggJGwAMAIQgAA==.Flapster:BAAALgADCgkJFQABLgAECggJGwAMAIQgAA==.Flashmaster:BAAALgAECgYJCAAAAA==.Flawlessheal:BAAALgAECgEJBwAAAA==.Flora:BAAALgAECgEJAgAAAA==.Fluffybutt:BAAALgADCgcJBwAAAA==.',
Fo='Fossora:BAAALgAECgMJAwAAAA==.',
Fr='Frostmagi:BAAALgAECgYJCwABLgAFFAUJDwANAAIlAA==.Frostybunny:BAAALgAECgIJAgAAAA==.Frozenharded:BAAALgADCgQJBAABLgAECgYJDAAFAAAAAA==.',
Fu='Furrbidden:BAAALgADCgQJBAAAAA==.Fusionve:BAAALgAECgUJBgAAAA==.',
Ga='Gaffershot:BAAALgADCgMJAwAAAA==.Gafferthicc:BAABLgAECn8aAAIXAAgJpxoEEwDTAQAXAAgJpxoEEwDTAQAAAA==.Gaffharir:BAAALgADCgUJBQAAAA==.Galvin:BAAALgADCgYJBgAAAA==.Garfeeld:BAAALgADCgcJBwABLgAECgcJHwAMAPQYAA==.Garlicroast:BAAALgAECgMJAwAAAA==.Gayden:BAAALgAECgUJBgAAAA==.',
Ge='Gelatin:BAAALgADCgQJBQAAAA==.Gerry:BAABLgAECn8lAAIfAAgJOh+zAwBaAgAfAAgJOh+zAwBaAgAAAA==.Geyora:BAABLgAECn8cAAIfAAgJ9x6nAwDpAgAfAAgJ9x6nAwDpAgAAAA==.',
Gi='Gingerail:BAAALgAECgYJDAAAAA==.',
Gl='Glory:BAAALgAECggJEwAAAA==.',
Go='Goochsquirts:BAABLgAECn8mAAIMAAYJNh2HKADuAQAMAAYJNh2HKADuAQAAAA==.Gorrick:BAAALgAECgQJBAAAAA==.Gorriff:BAAALgAECgMJBAAAAA==.',
Gr='Graestrae:BAAALgAECgYJEQAAAA==.Gravedygger:BAABLgAECn8kAAIPAAgJchUwGADRAQAPAAgJchUwGADRAQAAAA==.Greenonions:BAAALgADCgIJAgAAAA==.Grenswood:BAACLgAFFH8OAAIgAAQJiSOuAACSAQAgAAQJiSOuAACSAQAuAAQKfygAAiAACQnjJK0AAEwDACAACQnjJK0AAEwDAAAA.Grimmarius:BAAALgAFFAIJAgAAAA==.Grimmkin:BAAALgAECgUJCAAAAA==.Grimmyr:BAAALgADCgYJBgAAAA==.Grumbo:BAAALgAECgMJAwAAAA==.',
Gu='Guuldurak:BAAALgAECgMJAwAAAA==.',
Ha='Harrod:BAAALgAECgcJDQAAAA==.Hasew:BAAALgAECgcJEwAAAA==.',
He='He:BAAALgAECgEJAQAAAA==.Heimlich:BAAALgAECgEJAgABLgAECggJHgARAD4aAA==.Hellodoodle:BAAALgADCgcJFQAAAA==.Helpimßlind:BAABLgAECn8eAAIXAAcJiBYiSwDIAQAXAAcJiBYiSwDIAQAAAA==.Hera:BAACLgAFFH8GAAIPAAMJoyA/EgApAQAPAAMJoyA/EgApAQAuAAQKfyoAAg8ACAnyJUUCAHYDAA8ACAnyJUUCAHYDAAAA.Herry:BAAALgAECgUJCgABLgAECggJJQAfADofAA==.Heyner:BAABLgAECn8iAAIhAAgJPRMZAgDbAQAhAAgJPRMZAgDbAQAAAA==.',
Hi='Hille:BAAALgADCgEJAQAAAA==.Hinral:BAABLgAECn8fAAIVAAgJ0SUpAwBLAwAVAAgJ0SUpAwBLAwAAAA==.',
Ho='Holyangus:BAAALgAECgUJCAAAAA==.',
Hu='Hukkaru:BAAALgADCgYJCwAAAA==.',
['Hë']='Hëll:BAABLgAECn8VAAIbAAgJeBBoRwAaAQAbAAgJeBBoRwAaAQAAAA==.',
Ic='Iceblind:BAAALgAECgYJCgAAAA==.',
Il='Ilcanna:BAAALgADCgEJAQAAAA==.Illaynne:BAABLgAECn8eAAIBAAcJohz0CQAJAgABAAcJohz0CQAJAgAAAA==.',
Im='Imani:BAABLgAECn8oAAIiAAgJmxIkDQDuAQAiAAgJmxIkDQDuAQAAAA==.Immensepain:BAABLgAECn8jAAIEAAgJjBD/fADXAQAEAAgJjBD/fADXAQAAAA==.Imnotbalding:BAAALgAECgMJAwAAAA==.Imtrynacrack:BAAALgADCgQJBAAAAA==.Imurhucklbry:BAAALgADCgMJAwAAAA==.',
In='Inalee:BAAALgAECgcJEgAAAA==.Inoshikacho:BAABLgAECn8bAAILAAgJ9QZcCQBTAQALAAgJ9QZcCQBTAQAAAA==.Involio:BAAALgADCgcJBwAAAA==.Invý:BAABLgAECn8gAAIRAAgJFBfYIwC1AQARAAgJFBfYIwC1AQAAAA==.',
Ir='Irishdots:BAAALgADCgMJAwAAAA==.Irishkicks:BAAALgADCgQJBAAAAA==.Irishlife:BAAALgAECgEJAQAAAA==.Irishmecha:BAACLgAFFH8GAAITAAMJKgNIAwDeAAATAAMJKgNIAwDeAAAuAAQKfyYAAhMACAnOFx0FAEQCABMACAnOFx0FAEQCAAAA.Irishtotems:BAAALgADCgQJBAAAAA==.Irishtraps:BAAALgADCgEJAQAAAA==.',
Is='Isandra:BAAALgADCgEJAQAAAA==.',
It='Itharillys:BAABLgAECn8aAAIPAAgJWAoKMABQAQAPAAgJWAoKMABQAQAAAA==.',
Ja='Jaadu:BAAALgADCgQJAwAAAA==.',
Je='Jeennkiins:BAAALgADCggJCAAAAA==.Jessibella:BAAALgAECgMJCQAAAA==.Jezzako:BAABLgAECn8YAAMPAAYJjAthaAAvAQAPAAUJsg1haAAvAQAfAAYJHASAGwDTAAAAAA==.',
Ji='Jinx:BAAALgAECgMJBAABLgAECgcJEgAFAAAAAA==.',
Jo='Johali:BAABLgAECn8XAAIKAAcJTgYbFgDJAAAKAAcJTgYbFgDJAAAAAA==.',
Ju='Justise:BAABLgAECn8WAAQeAAYJvxkEFADMAQAeAAYJ5BgEFADMAQAJAAUJFhhQHwA5AQAKAAEJjQ4HRgAsAAAAAA==.Jutojerry:BAABLgAECn8WAAMUAAcJYyD7DAC7AQAUAAcJYyD7DAC7AQAVAAIJzhwPTQChAAAAAA==.',
['Jî']='Jîru:BAAALgADCgQJBAAAAA==.',
['Jö']='Jöhnblaze:BAABLgAECn8ZAAQeAAgJNg6LGADBAAAJAAcJWwzeYQAqAQAeAAUJYw2LGADBAAAKAAEJPAsnLgAzAAAAAA==.',
Ka='Kaalya:BAAALgADCgYJBgAAAA==.Kaelus:BAAALgADCgEJAQAAAA==.Kahoona:BAAALgAECgQJBwAAAA==.Kailys:BAABLgAECn8cAAIdAAgJiQsvDgAcAQAdAAgJiQsvDgAcAQAAAA==.Kaishias:BAABLgAECn8YAAIRAAcJmBurPwAnAgARAAcJmBurPwAnAgAAAA==.Kamyra:BAAALgAECgYJEQAAAA==.Kankuró:BAABLgAECn8nAAMPAAgJzBtfDgAnAgAPAAgJzBtfDgAnAgAQAAEJyAdMjgAtAAAAAA==.',
Ke='Kedzen:BAAALgADCgYJDAABLgAECgcJHwAMAPQYAA==.Kerfur:BAAALgAECgMJAwAAAA==.',
Ki='Killudead:BAAALgAECgMJAwAAAA==.',
Ko='Kodetra:BAAALgADCgEJAQAAAA==.Kolgrim:BAABLgAECn8bAAMHAAgJQxrNCQA4AQAjAAcJVhrCHQBbAQAHAAUJbxPNCQA4AQAAAA==.Korimya:BAAALgAECgEJAQAAAA==.Korva:BAAALgAECgYJDQABLgAECgYJGAAEAFgQAA==.',
Kr='Krianthess:BAAALgAECgUJCQAAAA==.Krissypoo:BAAALgADCgcJCwAAAA==.Kristie:BAABLgAECn8YAAIEAAYJWBCCugBsAQAEAAYJWBCCugBsAQAAAA==.Krom:BAABLgAECn8cAAIMAAgJ6Q7TIABfAQAMAAgJ6Q7TIABfAQAAAA==.',
Ku='Kuadonaran:BAAALgADCgEJAQABLgAECgcJHgAbAKQgAA==.Kulitcomandr:BAAALgADCgUJBQAAAA==.Kupquake:BAACLgAFFH8GAAIWAAMJDwjADADWAAAWAAMJDwjADADWAAAuAAQKfygAAhYACAlcHK8QAHYCABYACAlcHK8QAHYCAAAA.',
Ky='Kynris:BAAALgADCgMJAwABLgAECgcJFgAYAE0XAA==.',
La='Laancelot:BAAALgADCgkJCQAAAA==.Lacy:BAAALgADCgEJAQAAAA==.Laetus:BAAALgAECgUJDQAAAA==.Lamort:BAABLgAECn8eAAQbAAcJpCD3PAAZAgAbAAYJaB/3PAAZAgAkAAQJ+R+/BQAiAQAgAAQJMxhpSgCOAAAAAA==.Lanaal:BAAALgADCgIJAgAAAA==.Lancewh:BAAALgADCgkJFwAAAA==.Launzi:BAAALgADCgcJDAAAAA==.Lavirna:BAAALgADCgEJAQABLgAECgYJGAAEAFgQAA==.Lazulli:BAAALgADCgMJAwAAAA==.',
Le='Leaila:BAAALgAECgYJEAAAAA==.Leonora:BAABLgAECn8YAAIQAAYJzBI5CgAuAQAQAAYJzBI5CgAuAQAAAA==.',
Li='Lightbreakk:BAAALgADCgkJDwABLgAECgUJBgAFAAAAAA==.Lindesong:BAAALgADCgkJCQABLgAFFAYJDwAPAGcbAA==.Lisondrel:BAAALgAECgUJBwAAAA==.',
Lo='Lockbone:BAAALgAECgMJAwAAAA==.Loops:BAABLgAECn8dAAIfAAgJkR9UBgAKAgAfAAgJkR9UBgAKAgAAAA==.Lorette:BAABLgAECn8ZAAMBAAgJ3RThLQCNAQABAAgJ3RThLQCNAQACAAYJiRbTGQAvAQAAAA==.Lovelychow:BAAALgADCgYJCQAAAA==.',
Lu='Luuma:BAAALgADCgcJBwABLgAECgcJEgAFAAAAAA==.',
Lw='Lwinterheart:BAAALgADCgEJAQAAAA==.',
Ly='Ly:BAAALgADCgUJBQAAAA==.Lymriina:BAACLgAFFH8GAAISAAMJaROcDQARAQASAAMJaROcDQARAQAuAAQKfxwAAhIACAlsI5kHABYDABIACAlsI5kHABYDAAEuAAUUBgkPAA8AZxsA.Lyr:BAAALgADCgcJBwAAAA==.',
Ma='Machotedan:BAABLgAECn8lAAIRAAgJTR/sCwBqAgARAAgJTR/sCwBqAgAAAA==.Macmittens:BAAALgAECgMJAwAAAA==.Magedude:BAAALgAECgIJAgAAAA==.Maliken:BAABLgAECn8fAAIcAAgJ7R35JQCkAgAcAAgJ7R35JQCkAgAAAA==.Mamadrag:BAABLgAECn8fAAQYAAgJRRnqBwCwAQAYAAcJkxjqBwCwAQAaAAMJXgbaWABbAAAZAAIJ7waFDwBaAAAAAA==.Mambø:BAAALgADCgYJBgAAAA==.Managua:BAAALgADCgEJAQAAAA==.Mandwa:BAAALgAECgYJBgABLgAECggJEwAXALIdAA==.Mario:BAABLgAECn8ZAAIEAAcJJxizQQBpAQAEAAcJJxizQQBpAQAAAA==.Masivewin:BAAALgAECgEJAQAAAA==.Mastashifta:BAAALgAECgMJBQAAAA==.Matryoshka:BAAALgAECgUJCAAAAA==.Mattsadler:BAAALgAECgEJAgAAAA==.Maverex:BAAALgAFFAEJAQAAAA==.Mavok:BAAALgAECgEJAQAAAA==.Maxxim:BAAALgAECgMJAwAAAA==.',
Me='Mechamonk:BAAALgADCgIJAgAAAA==.Merczdk:BAAALgADCgYJDAAAAA==.Meta:BAAALgAECgYJEQAAAA==.',
Mi='Minthara:BAAALgADCgUJCgAAAA==.Missdemon:BAAALgADCgUJBgAAAA==.Missikrissi:BAAALgADCgYJBgAAAA==.Missmorrigan:BAAALgAECgQJCQAAAA==.Missî:BAAALgAECgUJBQAAAA==.Mists:BAACLgAFFH8JAAIbAAQJ1xznDgBnAQAbAAQJ1xznDgBnAQAuAAQKfyMAAxsACAmCJO4LABsDABsACAmCJO4LABsDACAAAgmaHfFHAJcAAAAA.Miththrawndo:BAABLgAECn8WAAMjAAgJMBhFEgDnAQAjAAgJMBhFEgDnAQAHAAEJAAAvGwAIAAAAAA==.',
Ml='Ml:BAABLgAECn8UAAMgAAYJVh4FCwAPAgAgAAYJVh4FCwAPAgAbAAQJDA+BUQD8AAAAAA==.',
Mo='Moldevort:BAAALgAECgMJBAAAAA==.Momjeans:BAABLgAECn8aAAIlAAcJjSGcAQCzAgAlAAcJjSGcAQCzAgAAAA==.Morningumbra:BAAALgADCgIJAgAAAA==.',
Ms='Mstryoda:BAAALgADCgUJCAAAAA==.',
Mu='Muramasa:BAAALgADCggJCgAAAA==.',
My='Myfriendtold:BAAALgADCgEJAgAAAA==.Mythunsarian:BAABLgAECn8jAAImAAgJ6g5FCwCIAQAmAAgJ6g5FCwCIAQAAAA==.',
['Mä']='Mäylä:BAABLgAECn8VAAIDAAgJmg5nIgBuAQADAAgJmg5nIgBuAQAAAA==.',
['Mí']='Míst:BAABLgAECn8iAAIRAAgJLhURZwCyAQARAAgJLhURZwCyAQAAAA==.',
Na='Nazaline:BAAALgADCgIJAgAAAA==.',
Ne='Necrohealiac:BAAALgAECgEJAwAAAA==.Necromerc:BAAALgAECgQJBAAAAA==.Necrotizer:BAAALgADCgMJAwAAAA==.Nephie:BAABLgAECn8dAAImAAgJghwYBgADAgAmAAgJghwYBgADAgAAAA==.Netazia:BAAALgADCgcJGQAAAA==.Nethralfus:BAAALgAECgEJAQAAAA==.Nezqk:BAABLgAECn8fAAIcAAgJzREYXQDbAQAcAAgJzREYXQDbAQAAAA==.',
Ni='Niano:BAAALgADCgEJAgAAAA==.',
Nm='Nmnenthe:BAAALgAECgEJAQAAAA==.',
No='Noelytv:BAAALgADCgcJBwAAAA==.Norman:BAAALgADCgEJAgAAAA==.November:BAAALgADCgEJAQAAAA==.Noxren:BAAALgAECgQJBgAAAA==.',
['Nî']='Nîstø:BAABLgAECn8hAAQIAAgJZhqjDwDoAQAIAAYJIByjDwDoAQAdAAcJzBhtDgDeAQARAAQJAAqepwBdAAAAAA==.',
Ob='Obin:BAABLgAECn8dAAIJAAgJmhKsLgD2AQAJAAgJmhKsLgD2AQAAAA==.',
Oh='Oharachloe:BAAALgADCgYJBgAAAA==.',
Ol='Ollenbock:BAAALgADCgQJBAABLgAFFAYJDwAPAGcbAA==.',
Or='Orhanu:BAAALgAECgcJCAAAAA==.',
Ou='Outbbreakk:BAAALgAECgUJBgAAAA==.',
Ow='Owendriel:BAABLgAECn8XAAIXAAgJTBhoOwAGAgAXAAgJTBhoOwAGAgAAAA==.',
Pa='Pajamas:BAABLgAECn8oAAIPAAgJViDtCgDuAgAPAAgJViDtCgDuAgAAAA==.Palyamorous:BAAALgADCgUJBQAAAA==.Pandress:BAABLgAECn8VAAIPAAYJrxAqNgA5AQAPAAYJrxAqNgA5AQAAAA==.Paralysis:BAAALgAECgEJAQABLgAFFAMJBgAWAA8IAA==.',
Pe='Peryite:BAABLgAECn8fAAMOAAcJQRK0EQB1AQAOAAcJyxG0EQB1AQABAAYJrwoXRwAdAQAAAA==.',
Ph='Phelris:BAAALgAECgUJBQAAAA==.',
Pi='Pillpusher:BAAALgAECgMJBAAAAA==.Pisscat:BAAALgAECgQJBQAAAA==.',
Po='Polymerase:BAAALgAECgEJAQABLgAECgcJGgAcAN0YAA==.',
Pr='Prideindeath:BAAALgAECgUJBQAAAA==.Promiscuity:BAAALgAECgcJCAAAAA==.Protròast:BAAALgAECgIJAgAAAA==.Prængle:BAAALgAECgYJDgAAAA==.',
Ps='Psypriest:BAAALgAFFAMJAwABLgAFFAUJFAABAI8XAA==.',
Pu='Pulverine:BAAALgADCgcJDgAAAA==.',
Qu='Quarantinia:BAAALgADCgEJAQAAAA==.',
Ra='Rabbi:BAAALgAECgUJEgAAAA==.Ragerunnerx:BAAALgAECggJDwAAAA==.Rahfna:BAAALgAECgEJAQAAAA==.Rakan:BAAALgADCgIJAgAAAA==.Raynare:BAAALgAECgEJAQAAAA==.',
Re='Redall:BAAALgAECgYJEwAAAA==.Reesespbc:BAABLgAECn8bAAIEAAgJ3Q7IRgBaAQAEAAgJ3Q7IRgBaAQAAAA==.Reina:BAAALgAECgQJCgABLgAECgcJEgAFAAAAAA==.Reinir:BAABLgAECn8lAAIeAAgJKyLrAQCeAgAeAAgJKyLrAQCeAgAAAA==.Rektagar:BAABLgAECn8jAAMNAAgJ2CLBBgA9AgANAAcJbyLBBgA9AgAMAAMJXh/iLAARAQABLgAFFAYJDwAPAGcbAA==.Ressandra:BAAALgADCgcJBwAAAA==.Reyvanna:BAAALgADCgEJAQAAAA==.',
Ro='Roar:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Robert:BAAALgADCgEJAQAAAA==.Rosavyra:BAAALgAECggJCQAAAA==.Roshara:BAAALgAECgIJAgAAAA==.',
['Rö']='Rös:BAACLgAFFH8GAAIEAAMJkRqPLQATAQAEAAMJkRqPLQATAQAuAAQKfygAAwQACAnhHGI7AIkCAAQACAnhHGI7AIkCACcAAQlfIN0MAF0AAAAA.',
['Rü']='Rübblë:BAAALgADCgQJBAAAAA==.',
Sa='Saberie:BAAALgAECgMJAwAAAA==.Salamun:BAAALgAECgQJBAAAAA==.Salaria:BAABLgAECn8UAAIXAAYJ5gcKRwDQAAAXAAYJ5gcKRwDQAAAAAA==.Salen:BAABLgAECn8hAAIiAAgJPxQhBQDNAQAiAAgJPxQhBQDNAQAAAA==.Salina:BAEBLgAECn8iAAIoAAYJ3Rr2DACJAQAoAAYJ3Rr2DACJAQAAAA==.Sandraia:BAABLgAECn8fAAIcAAgJrRurHwDJAQAcAAgJrRurHwDJAQAAAA==.Sandstique:BAABLgAECn8VAAIMAAkJryFpCADvAgAMAAkJryFpCADvAgAAAA==.Sandtwig:BAAALgADCgEJAQAAAA==.Sandweaver:BAAALgADCgEJAQAAAA==.Sanjira:BAABLgAECn8XAAIhAAgJBgaYBQAUAQAhAAgJBgaYBQAUAQAAAA==.Sarusuby:BAABLgAECn8dAAIpAAcJYRdxDQCvAQApAAcJYRdxDQCvAQAAAA==.',
Sc='Scottyfist:BAABLgAECn8YAAIUAAgJdh96FgBVAgAUAAgJdh96FgBVAgAAAA==.Scottymac:BAAALgADCgYJBgABLgAECggJGAAUAHYfAA==.',
Se='Sealion:BAACLgAFFH8HAAMIAAMJVyCXEQDDAAAIAAIJQB2XEQDDAAARAAIJygutMACkAAAuAAQKfxkAAwgACQmVF1wWAF4CAAgACQmVF1wWAF4CABEAAwn0HaajAGIAAAAA.Seetah:BAABLgAECn8WAAIBAAgJgCHBCADAAgABAAgJgCHBCADAAgAAAA==.Serratus:BAABLgAECn8kAAMZAAgJ9x2FAgDnAQAZAAcJABuFAgDnAQAaAAgJ8RZsEQCAAQAAAA==.Setcher:BAAALgADCgEJAQAAAA==.',
Sh='Shadaddy:BAAALgAECggJCgABLgAECgcJGQAHANcbAA==.Shadoweyes:BAAALgAECgcJCAAAAA==.Shamax:BAAALgADCgEJAgABLgADCgUJBQAFAAAAAA==.Shamommy:BAAALgAECgMJAwAAAA==.Shayes:BAABLgAECn8bAAIpAAcJLh4ZBADsAQApAAcJLh4ZBADsAQAAAA==.Shifue:BAAALgAECgMJAwAAAA==.Shimmerstar:BAABLgAECn8UAAIRAAkJxxGfGQDxAQARAAkJxxGfGQDxAQAAAA==.',
Si='Sigg:BAAALgAECgUJBQAAAA==.Silexe:BAAALgAECgUJBgABLgAECgcJHgAbAKQgAA==.',
Sk='Skathae:BAAALgAECgEJAQABLgAECgcJFgAYAE0XAA==.Skåld:BAABLgAECn8VAAIcAAgJaRfQPQBFAQAcAAgJaRfQPQBFAQAAAA==.',
Sn='Snuffles:BAABLgAECn8aAAIfAAcJCxqaDACUAQAfAAcJCxqaDACUAQAAAA==.Snugs:BAAALgADCgEJAQAAAA==.',
So='Soldraca:BAAALgAECgMJAwAAAA==.Sorrytanks:BAAALgAECgcJEAAAAA==.Soulence:BAAALgAECgMJBAAAAA==.',
St='Stinkbug:BAAALgADCgEJAQAAAA==.Stutters:BAABLgAECn8aAAMcAAcJ3RjCSAAZAgAcAAcJqxjCSAAZAgAjAAUJIBgmIABDAQAAAA==.',
Su='Sudachi:BAABLgAECn8VAAMKAAkJkhqOBACjAgAKAAkJkhqOBACjAgAJAAIJAw1LlABuAAABLgAFFAQJBQAWABQYAA==.Sunnyräy:BAAALgADCgcJDQAAAA==.',
Sw='Swineflu:BAAALgAECgMJAwAAAA==.Swizzjenks:BAAALgADCgMJAwAAAA==.',
Sy='Synonym:BAAALgADCgcJBwAAAA==.Syrprize:BAAALgADCgEJAQABLgAECgcJFgAUAGMgAA==.',
['Sý']='Sýndrá:BAABLgAECn8ZAAIgAAgJkCCqAACVAgAgAAgJkCCqAACVAgAAAA==.',
Ta='Tacobob:BAABLgAECn8oAAIDAAgJdBZtNwDJAQADAAgJdBZtNwDJAQAAAA==.Taethron:BAAALgADCgUJBQAAAA==.Taffeta:BAAALgADCgEJAQAAAA==.Taffyboy:BAAALgADCggJCgAAAA==.Talysiah:BAAALgAECgYJEAAAAA==.Tannir:BAAALgAECgEJAQAAAA==.Tarogen:BAAALgADCgQJBgABLgAECggJHwAVANElAA==.Tavok:BAABLgAECn8bAAMJAAcJeyNPCQAVAgAJAAcJeyNPCQAVAgAeAAEJ+BUIRAA9AAAAAA==.',
Te='Tenacious:BAAALgADCgcJDAAAAA==.Tene:BAAALgADCgMJAwAAAA==.Teratots:BAAALgADCgYJBgAAAA==.Testament:BAAALgADCgcJCAAAAA==.',
Th='Thenna:BAAALgAECgMJAwAAAA==.Theosclaws:BAAALgADCgcJDgAAAA==.Theramier:BAAALgADCgIJAgAAAA==.Thiux:BAABLgAECn8VAAMbAAgJVBxjDQBDAgAbAAcJVBxjDQBDAgAgAAEJAABqXQBWAAAAAA==.Thotsnprayrs:BAAALgADCgUJCAABLgAECgcJFgAUAGMgAA==.Thourin:BAAALgADCgEJAQAAAA==.Thrappy:BAABLgAECn8bAAIMAAgJhCAdBgCNAgAMAAgJhCAdBgCNAgAAAA==.Thráwñ:BAAALgAECgIJAwABLgAECgYJCgAFAAAAAA==.',
Ti='Tiddyhammer:BAABLgAECn8YAAMIAAcJIhRhRQBiAQAIAAcJIhRhRQBiAQARAAMJTxpLYgDvAAAAAA==.Tirtun:BAABLgAECn8fAAIEAAgJgR3nFQAtAgAEAAgJgR3nFQAtAgAAAA==.',
To='Tomek:BAABLgAECn8eAAMQAAgJChzcAwDfAQAfAAgJxhNqBwDyAQAQAAcJsh/cAwDfAQAAAA==.Totemetot:BAAALgAECgIJBAAAAA==.',
Tr='Treemourne:BAAALgADCgEJAQAAAA==.Triggeer:BAABLgAECn8nAAIeAAgJWhdTCQCaAQAeAAgJWhdTCQCaAQAAAA==.',
Tu='Tully:BAAALgADCgEJAQAAAA==.Turalus:BAAALgADCgYJBgAAAA==.Turina:BAAALgAECgYJCgAAAA==.',
Tw='Twelvekill:BAACLgAFFH8GAAIPAAMJZQiGHQDpAAAPAAMJZQiGHQDpAAAuAAQKfygAAg8ACAlNGigaAGsCAA8ACAlNGigaAGsCAAAA.',
Ty='Tylidus:BAAALgAECgUJCAAAAA==.Tyranny:BAAALgAECgYJDwAAAA==.',
Ub='Ubisami:BAAALgAECgcJDAAAAA==.',
Ul='Ullur:BAAALgADCgEJAgAAAA==.Ultramon:BAABLgAECn8UAAIRAAYJUwxGWgADAQARAAYJUwxGWgADAQAAAA==.Uly:BAAALgAECgQJBQAAAA==.',
Un='Unwell:BAAALgAECgQJBAABLgAECggJHAASAK8aAA==.',
Ur='Urgoochness:BAABLgAECn8eAAIDAAcJfxgWGADAAQADAAcJfxgWGADAAQAAAA==.Urikhai:BAAALgAECgQJBQAAAA==.',
Va='Vaellvoid:BAAALgAECgMJAwAAAA==.Vainglorious:BAAALgAECgQJBgABLgAECggJEwAFAAAAAA==.Valanora:BAABLgAECn8YAAIkAAcJFBujAwBbAgAkAAcJFBujAwBbAgAAAA==.Valdis:BAAALgADCgcJDgABLgAECgYJGAAEAFgQAA==.Valinaxius:BAAALgAECgQJCwAAAA==.Valphalk:BAAALgADCggJCQAAAA==.Vanastasia:BAAALgAECgQJBgAAAA==.Vapturov:BAAALgAECgMJBAAAAA==.',
Ve='Veeks:BAAALgAECgcJDwAAAA==.Velikirn:BAABLgAECn8mAAMWAAgJZB+GBQBBAgAWAAgJRh+GBQBBAgAUAAYJQhjaFABdAQAAAA==.Vellwinnalas:BAAALgADCgUJCAAAAA==.Verah:BAAALgADCgYJBgAAAA==.Versø:BAABLgAECn8kAAQTAAYJPh3wBgD9AQATAAYJSBvwBgD9AQAhAAYJdBYgBABWAQASAAQJ1hmEPgAoAQAAAA==.',
Vi='Villageinn:BAAALgAECgMJAwAAAA==.Vine:BAAALgAECgYJCgAAAA==.Vixxon:BAABLgAECn8VAAIPAAcJshCXKQBvAQAPAAcJshCXKQBvAQAAAA==.',
Vl='Vly:BAAALgAECgYJCQAAAA==.Vlyzen:BAAALgAECgQJBQAAAA==.',
Vo='Voidhearted:BAABLgAECn8pAAICAAgJnBqdBgAkAgACAAgJnBqdBgAkAgAAAA==.',
['Vì']='Vìolet:BAAALgAECgQJBwABLgAECgcJGAAGAIEeAA==.',
Wa='Waggleton:BAAALgAECgEJAgAAAA==.Warp:BAAALgADCgEJAQAAAA==.Wasted:BAAALgADCgEJAQABLgAECggJGwAMAIQgAA==.Wayshua:BAAALgAECgUJBwAAAA==.',
We='Wearyouout:BAAALgADCgUJBQAAAA==.Wemon:BAAALgAECgUJBQAAAA==.Werkajerk:BAABLgAECn8YAAMUAAcJgx8wEQCFAQAUAAcJgx8wEQCFAQAWAAEJwBc6dABEAAABLgAFFAUJDwANAAIlAA==.Werkjathal:BAACLgAFFH8PAAQNAAUJAiVtAwC2AQANAAQJAiVtAwC2AQAMAAIJhwekGwCKAAAiAAMJzxBaBQBlAAAuAAQKfykABA0ACQmdIhYOAMICAA0ACAkXIxYOAMICAAwABwnDI40NAK8CACIABQlDH8oHAHwBAAAA.Wetribs:BAAALgADCgkJCQAAAA==.',
Wh='Whereareyou:BAAALgADCgkJCQABLgAECgYJFgAPAPkYAA==.Whitedog:BAAALgAECgEJAQAAAA==.Whitetank:BAABLgAECn8gAAIdAAgJ9hgCBgDNAQAdAAgJ9hgCBgDNAQAAAA==.',
Wi='Willowbeard:BAAALgAECgMJAwAAAA==.Winnelepooh:BAAALgADCgQJBAAAAA==.',
Wo='Wobys:BAABLgAECn8VAAIVAAcJExXQIgCdAQAVAAcJExXQIgCdAQAAAA==.Wolfblitzer:BAABLgAECn8YAAIRAAcJ0huxTAD8AQARAAcJ0huxTAD8AQAAAA==.Wolfmanbro:BAAALgADCggJCAAAAA==.Worldbane:BAABLgAECn8WAAIgAAYJFBTFBgBLAQAgAAYJFBTFBgBLAQAAAA==.',
['Wä']='Wärchild:BAAALgADCgcJJwAAAA==.',
Xa='Xalaa:BAAALgAECgYJCgAAAA==.Xalataxfraud:BAAALgAECgQJAwAAAA==.Xanthos:BAAALgAECgEJAQAAAA==.',
Xe='Xenthriel:BAAALgADCgcJBwAAAA==.',
Xi='Xianyu:BAAALgAECgQJBwAAAA==.Ximmer:BAAALgAECgEJAQAAAA==.',
Ya='Yarian:BAAALgAECgMJAwAAAA==.',
Yo='Yormin:BAAALgAECgUJEAAAAA==.Yorra:BAAALgAECgIJAgAAAA==.',
Yu='Yuzuu:BAAALgAECgYJEQAAAA==.',
Za='Zachhunter:BAABLgAFFH8PAAMPAAYJZxsiBACDAQAPAAQJBBwiBACDAQAQAAYJMRE3AwB5AQAAAA==.Zan:BAACLgAFFH8GAAMNAAMJcQuSEwDgAAANAAMJcQuSEwDgAAAMAAIJ4hAoGQCXAAAuAAQKfygAAw0ACAmNH6kTAIICAA0ACAmNH6kTAIICAAwAAgmgC8qJAG0AAAAA.',
Zo='Zohaan:BAAALgADCgEJAwAAAA==.Zoma:BAAALgADCggJDgAAAA==.',
Zu='Zuhura:BAAALgAECgQJBAAAAA==.Zultrix:BAAALgAECgIJAgAAAA==.',
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

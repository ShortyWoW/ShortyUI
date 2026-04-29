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

local lookup = {'Priest-Holy','Priest-Shadow','Druid-Restoration','Mage-Frost','DeathKnight-Unholy','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Druid-Feral','Shaman-Restoration','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Paladin-Protection','Shaman-Elemental','Hunter-Survival','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','Warrior-Protection','DeathKnight-Blood','Warlock-Affliction','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Absoul:BAABLgAECn8aAAMBAAgJRR9hAgBMAgABAAgJRR9hAgBMAgACAAEJcQPlaAAmAAAAAA==.',
Ac='Acedia:BAABLgAECn8bAAIBAAcJlRTsBQC+AQABAAcJlRTsBQC+AQAAAA==.',
Ad='Adellas:BAABLgAECn8aAAIDAAgJqx0MIQA7AgADAAgJqx0MIQA7AgAAAA==.Adern:BAABLgAECn8YAAICAAcJ2B6HEgBkAgACAAcJ2B6HEgBkAgAAAA==.Adon:BAABLgAECn8XAAIEAAcJiR75ewDZAQAEAAcJiR75ewDZAQAAAA==.Adondruel:BAAALgAECgEJAQAAAA==.',
Ae='Aelali:BAAALgADCgcJCAAAAA==.Aelith:BAAALgAECgcJEgAAAA==.',
Af='Afador:BAAALgADCgcJFAABLgAECggJFwAFADkPAA==.',
Ag='Ageling:BAAALgADCgQJAgAAAA==.',
Ak='Akrom:BAAALgADCgEJAgAAAA==.',
Al='Aladestar:BAABLgAECn8hAAMDAAgJyBqtGwBeAgADAAgJyBqtGwBeAgAGAAcJrSAOIgDsAQAAAA==.Albinodargon:BAAALgAECgQJBwAAAA==.Alderleise:BAAALgAECgYJDQAAAA==.Alecc:BAAALgAECgYJCwAAAA==.Alexein:BAABLgAECn8eAAIHAAgJnhIMBQD2AQAHAAgJnhIMBQD2AQAAAA==.Alienspace:BAAALgADCgEJAQAAAA==.',
Am='Amets:BAABLgAECn8UAAIIAAcJwyHQAQCWAgAIAAcJwyHQAQCWAgAAAA==.Amydh:BAAALgAECgEJAwAAAA==.',
An='Anabel:BAAALgADCgUJBQAAAA==.Anamii:BAAALgADCgEJAQAAAA==.Andorsi:BAAALgAECgYJCAAAAA==.Anglechow:BAAALgADCgUJBQAAAA==.',
Ar='Arachne:BAAALgAECgYJEAAAAA==.Aranax:BAAALgADCgEJAgAAAA==.Arce:BAAALgAECgQJCgAAAA==.Architeleaf:BAAALgADCgMJAwABLgAECgMJAwAJAAAAAA==.Areafiftymoo:BAABLgAECn8aAAMKAAcJTAaEFAD6AAAKAAcJLwaEFAD6AAALAAEJIQTqRwAmAAAAAA==.Arthurleywin:BAAALgADCgIJAgAAAA==.Arysia:BAAALgAECgQJBAAAAA==.Aryya:BAABLgAECn8uAAMMAAgJZiHLAABPAgAMAAgJZiHLAABPAgAGAAMJHAesZwCCAAAAAA==.',
As='Astralbreak:BAAALgADCgEJAQABLgAECgMJBAAJAAAAAA==.',
At='Athelia:BAAALgADCgEJAQAAAA==.',
Av='Avalan:BAABLgAECn8dAAIKAAcJHh3fBgC1AQAKAAcJHh3fBgC1AQAAAA==.Avashammy:BAABLgAECn8aAAINAAgJ+ByaIgAPAgANAAgJ+ByaIgAPAgAAAA==.Avesia:BAABLgAECn8aAAIOAAYJUBaeIgB/AQAOAAYJUBaeIgB/AQAAAA==.Aviendah:BAAALgAECgcJDgAAAA==.',
Aw='Awsomeonet:BAAALgAECgYJEAAAAA==.',
Ay='Ayot:BAAALgAECgcJEwAAAA==.',
Az='Azdfghop:BAACLgAFFH8PAAMPAAUJFR1eBQAmAQAPAAQJyhpeBQAmAQAQAAMJbRj4FAD0AAAuAAQKfyAAAxAACQm2Ih4PAMUCABAACAnIHh4PAMUCAA8ACAmZIZM/ALEBAAAA.Azzinotica:BAAALgAECgEJAQAAAA==.',
Ba='Babeshot:BAAALgAECgcJDQAAAA==.Babezila:BAAALgAECgYJDgAAAA==.Badshahprime:BAABLgAECn8eAAIRAAgJPhpmKgB7AgARAAgJPhpmKgB7AgAAAA==.Barbiegrill:BAABLgAECn8dAAMSAAgJ7x7+DwCmAgASAAgJEB7+DwCmAgATAAUJVRxACQCuAQAAAA==.Baykin:BAABLgAECn8YAAIUAAcJvRzIBQCuAQAUAAcJvRzIBQCuAQAAAA==.',
Bb='Bbeastt:BAAALgADCgEJAgAAAA==.',
Be='Beefyfivelyr:BAAALgADCgcJBwAAAA==.Berandas:BAABLgAECn8UAAMVAAcJ/hHQJQCGAQAVAAcJ/hHQJQCGAQAWAAUJhA04DgDtAAAAAA==.Bereessielin:BAAALgAECgQJBgAAAA==.Berkowitz:BAAALgAECgUJCQAAAA==.',
Bi='Bigbear:BAAALgADCgEJAQABLgADCgMJAwAJAAAAAA==.',
Bl='Blaaze:BAAALgAECgQJBgAAAA==.Blaiddyd:BAABLgAECn8XAAIPAAcJmx1dBwD0AQAPAAcJmx1dBwD0AQAAAA==.Blead:BAAALgAECggJCQABLgAECggJHQASAO8eAA==.Blinkerr:BAAALgADCgYJBgAAAA==.',
Br='Brahot:BAAALgAECgEJAQAAAA==.Brain:BAAALgADCgYJBgAAAA==.Brandawn:BAAALgADCgYJBgAAAA==.Branwarden:BAAALgAECgQJBAAAAA==.Brewsle:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebot:BAAALgAECgMJAwABLgAECggJGgAXAL8eAA==.Bullchitz:BAAALgAECgYJEAAAAA==.Bullchitza:BAAALgADCgcJBwABLgAECgYJEAAJAAAAAA==.Burningooch:BAAALgADCgEJAQAAAA==.',
['Bã']='Bãyy:BAAALgADCgkJCwAAAA==.',
['Bæ']='Bæyy:BAAALgADCgUJCgABLgADCgkJCwAJAAAAAA==.',
Ca='Calador:BAAALgAECgIJAgAAAA==.Capybara:BAAALgAECgYJCwAAAA==.Caster:BAAALgADCgQJBAAAAA==.Cathbad:BAAALgADCgEJAQAAAA==.Caylynn:BAAALgADCgkJCwAAAA==.',
Ce='Celyne:BAABLgAECn8aAAIXAAgJvx5FBwD/AQAXAAgJvx5FBwD/AQAAAA==.Cereza:BAAALgAECgEJAQAAAA==.',
Ch='Chaoslock:BAAALgADCgMJAwAAAA==.Chicknfajita:BAAALgAECgYJCAAAAA==.Chrissi:BAAALgAECgYJEgAAAA==.',
Ci='Cinco:BAAALgADCgUJBQAAAA==.',
Cl='Clearly:BAAALgADCgQJAwAAAA==.',
Co='Cocytus:BAAALgAECgIJAwAAAA==.Conquest:BAAALgAECgYJCgAAAA==.Cordaddy:BAABLgAECn8bAAIDAAcJZCUzCwDoAgADAAcJZCUzCwDoAgAAAA==.Corinthe:BAAALgAECgQJBAABLgAECgcJGwADAGQlAA==.Corinthin:BAABLgAECn8XAAINAAYJdheeQQB6AQANAAYJdheeQQB6AQAAAA==.',
Cr='Crinn:BAAALgAECggJDgAAAA==.Crizmon:BAABLgAECn8nAAIHAAgJlB8/AQD5AgAHAAgJlB8/AQD5AgAAAA==.Cryomancer:BAAALgADCgQJBAAAAA==.Crõwley:BAAALgADCgYJBgABLgAECgYJEgAJAAAAAA==.',
Da='Damage:BAAALgAECgEJAQAAAA==.Damorax:BAAALgAECgUJDAAAAA==.Darazarke:BAACLgAFFH8RAAIYAAUJURJtAgB8AQAYAAUJURJtAgB8AQAuAAQKfyMABBkACAlsHg0EANICABkACAlsHg0EANICABgABwmTHKUOAE4CABoAAQlwGHJdAEQAAAAA.Darkcursed:BAABLgAECn8WAAIbAAcJggh4IAAeAQAbAAcJggh4IAAeAQAAAA==.Darksudge:BAAALgAECgEJAQAAAA==.Darps:BAAALgAECgEJAgAAAA==.Daybreak:BAAALgAECgQJBAAAAA==.Dayquil:BAEBLgAECn8aAAMRAAgJQxu9NgBIAgARAAgJQxu9NgBIAgAIAAEJwRkmIwBMAAAAAA==.',
De='Deadaddie:BAABLgAECn8XAAMHAAcJtxoaAgBsAQAFAAcJZBR1VgDuAQAHAAYJOxcaAgBsAQAAAA==.Deamoneyes:BAAALgAECgEJAQAAAA==.Delin:BAAALgADCgQJBwABLgAFFAUJEQAYAFESAA==.Deluxdh:BAAALgADCgYJBgAAAA==.Demonslinger:BAAALgADCgUJBQAAAA==.Dendrel:BAAALgADCggJCAAAAA==.Derpspally:BAAALgADCgcJEgAAAA==.Derpspunch:BAAALgAECgcJDgAAAA==.Destrox:BAAALgADCgYJBgAAAA==.Deíty:BAAALgADCgUJBQAAAA==.',
Di='Diane:BAEALgADCggJDgAAAA==.Dieselcon:BAABLgAECn8kAAMcAAgJnRXCDQDpAQAcAAgJnRXCDQDpAQARAAEJswx4RAEyAAAAAA==.',
Do='Domdog:BAABLgAECn8iAAIEAAgJgBEfFACgAQAEAAgJgBEfFACgAQAAAA==.Dontforget:BAAALgAECgYJDwAAAA==.Dookiesmash:BAAALgAECgYJEgAAAA==.Doomblast:BAAALgADCgIJAgAAAA==.Doomdealer:BAAALgAECgQJCwAAAA==.Doomrage:BAAALgADCgcJFAAAAA==.Doomsdead:BAAALgADCgcJBwAAAA==.Doomshock:BAAALgADCgYJBQAAAA==.',
Dr='Draftymonk:BAAALgAECgYJEAAAAA==.Drax:BAAALgAECgYJEgAAAA==.Dritzzfive:BAAALgAECgUJCAAAAA==.Dritzzwar:BAAALgAECgYJCwAAAA==.',
Ei='Eilica:BAAALgAECgUJBQAAAA==.',
Ek='Ekaine:BAAALgADCgQJBAABLgAECgYJGAAEAFgQAA==.',
El='Elandrus:BAAALgAECgEJAQABLgAECgYJEgAJAAAAAA==.Elleynre:BAAALgADCgMJAwAAAA==.Elrëim:BAAALgAECgcJCwAAAA==.Elwendigo:BAAALgADCgMJAwAAAA==.Elwyna:BAAALgADCgIJAgAAAA==.',
Em='Emmara:BAAALgAECgYJCgAAAA==.',
En='Enhancement:BAAALgADCgcJDQABLgAFFAQJDAAdAAIlAA==.Enitar:BAAALgAECgUJCQABLgAECggJGgAXAL8eAA==.',
Er='Erata:BAAALgAECgIJAwAAAA==.Erlangshen:BAAALgADCgUJBQAAAA==.Erravis:BAAALgADCgcJDwAAAA==.',
Ev='Evarion:BAAALgADCgEJAQAAAA==.Eviaei:BAAALgAECgMJAwAAAA==.Evulise:BAAALgADCgYJBAAAAA==.',
Ez='Ezalan:BAAALgADCgcJBwAAAA==.Ezlok:BAAALgAECgYJEwAAAA==.Ezorreodd:BAAALgADCgQJBAAAAA==.Ezzorreodd:BAAALgAECgUJCAAAAA==.',
Fa='Fae:BAAALgAECgcJDQAAAA==.Faeleste:BAAALgAECgEJAQABLgAECgcJDQAJAAAAAA==.Falcyon:BAAALgADCggJDgAAAA==.Falerin:BAAALgAECgcJEwAAAA==.Farenheit:BAABLgAECn8aAAMGAAcJdhUtBgCiAQAGAAcJdhUtBgCiAQADAAMJcQkSowCDAAAAAA==.Faydwer:BAAALgADCgMJBAAAAA==.Fayfox:BAAALgADCgkJFwAAAA==.',
Fe='Feenex:BAAALgAECgQJBQAAAA==.',
Fi='Finick:BAAALgAECgQJBgAAAA==.Firedealer:BAABLgAECn8WAAIQAAgJRg1zQwBIAQAQAAgJRg1zQwBIAQAAAA==.Firnen:BAAALgAECgYJEgAAAA==.',
Fl='Flahash:BAAALgAECgMJAwAAAA==.Flappy:BAAALgAECgMJBgABLgAECgcJGQANAOwcAA==.Flapster:BAAALgADCgcJDAABLgAECgcJGQANAOwcAA==.Flashmaster:BAAALgAECgIJAgAAAA==.Flawlessheal:BAAALgAECgEJBQAAAA==.',
Fr='Frostmagi:BAAALgAECgYJBgABLgAFFAQJDAAdAAIlAA==.Frostybunny:BAAALgAECgIJAgAAAA==.',
Fu='Furrbidden:BAAALgADCgQJBAAAAA==.Fusionve:BAAALgADCgUJBQAAAA==.',
Ga='Gaffershot:BAAALgADCgMJAwAAAA==.Gafferthicc:BAAALgAECggJEgAAAA==.Gaffharir:BAAALgADCgUJBQAAAA==.Garlicroast:BAAALgADCgcJDAAAAA==.Gayden:BAAALgAECgUJBQAAAA==.',
Ge='Gelatin:BAAALgADCgQJBQAAAA==.Gerry:BAABLgAECn8ZAAIeAAgJjh7YBQCqAgAeAAgJjh7YBQCqAgAAAA==.Geyora:BAABLgAECn8bAAIeAAgJ9x6lAwDpAgAeAAgJ9x6lAwDpAgAAAA==.',
Gi='Gingerail:BAAALgAECgUJBwAAAA==.',
Gl='Glory:BAAALgAECgYJCwAAAA==.',
Go='Goochsquirts:BAABLgAECn8aAAINAAYJNh2JKADuAQANAAYJNh2JKADuAQAAAA==.Gorrick:BAAALgAECgIJAgAAAA==.Gorriff:BAAALgAECgMJBAAAAA==.',
Gr='Graestrae:BAAALgAECgYJCwAAAA==.Gravedygger:BAABLgAECn8cAAIPAAcJdBeKNgDUAQAPAAcJdBeKNgDUAQAAAA==.Greenonions:BAAALgADCgIJAgAAAA==.Grenswood:BAACLgAFFH8KAAIfAAQJJCOBAAAxAQAfAAQJJCOBAAAxAQAuAAQKfyUAAh8ACAk5Ja0AAEwDAB8ACAk5Ja0AAEwDAAAA.Grimmkin:BAAALgAECgUJBQAAAA==.Grimmyr:BAAALgADCgYJBgAAAA==.',
Ha='Harrod:BAAALgAECgcJDQAAAA==.Hasew:BAAALgAECgcJDQAAAA==.',
He='He:BAAALgADCgEJAQAAAA==.Heimlich:BAAALgAECgEJAgABLgAECggJHgARAD4aAA==.Hellodoodle:BAAALgADCgcJFAAAAA==.Helpimßlind:BAABLgAECn8eAAIXAAcJiBYmSwDIAQAXAAcJiBYmSwDIAQAAAA==.Hera:BAABLgAECn8mAAIPAAgJ3yVFAgB2AwAPAAgJ3yVFAgB2AwAAAA==.Herry:BAAALgAECgUJBgABLgAECggJGQAeAI4eAA==.Heyner:BAABLgAECn8aAAIgAAcJkBO+AQBOAQAgAAcJkBO+AQBOAQAAAA==.',
Hi='Hille:BAAALgADCgEJAQAAAA==.Hinral:BAABLgAECn8bAAIVAAgJxCUlAwBNAwAVAAgJxCUlAwBNAwAAAA==.',
Ho='Holyangus:BAAALgAECgUJCAAAAA==.',
Hu='Hukkaru:BAAALgADCgYJCwAAAA==.',
['Hë']='Hëll:BAAALgAECgcJEwAAAA==.',
Ic='Iceblind:BAAALgAECgQJBAAAAA==.',
Il='Ilcanna:BAAALgADCgEJAQAAAA==.Illaynne:BAABLgAECn8XAAIBAAcJmhtkBADzAQABAAcJmhtkBADzAQAAAA==.',
Im='Imani:BAABLgAECn8kAAIhAAgJjRAjDQDuAQAhAAgJjRAjDQDuAQAAAA==.Immensepain:BAABLgAECn8fAAIEAAgJ/Q4LfQDXAQAEAAgJ/Q4LfQDXAQAAAA==.Imtrynacrack:BAAALgADCgQJBAAAAA==.Imurhucklbry:BAAALgADCgMJAwAAAA==.',
In='Inalee:BAAALgAECgcJEgAAAA==.Inoshikacho:BAAALgAECgYJEwAAAA==.Involio:BAAALgADCgUJBQAAAA==.Invý:BAABLgAECn8YAAIRAAYJyxuzVwDbAQARAAYJyxuzVwDbAQAAAA==.',
Ir='Irishdots:BAAALgADCgMJAwAAAA==.Irishkicks:BAAALgADCgQJBAAAAA==.Irishmecha:BAABLgAECn8iAAITAAgJwxUcBQBEAgATAAgJwxUcBQBEAgAAAA==.Irishtotems:BAAALgADCgQJBAAAAA==.Irishtraps:BAAALgADCgEJAQAAAA==.',
Is='Isandra:BAAALgADCgEJAQAAAA==.',
It='Itharillys:BAABLgAECn8ZAAIPAAcJBQvwGgAmAQAPAAcJBQvwGgAmAQAAAA==.',
Ja='Jaadu:BAAALgADCgQJAwAAAA==.',
Je='Jessibella:BAAALgAECgIJBgAAAA==.Jezzako:BAAALgAECgYJEgAAAA==.',
Ji='Jinx:BAAALgAECgEJAQABLgAECgcJDQAJAAAAAA==.',
Jo='Johali:BAAALgAECgkJEgAAAA==.',
Ju='Justise:BAAALgAECgYJDwAAAA==.Jutojerry:BAAALgAECgYJEAAAAA==.',
['Jî']='Jîru:BAAALgADCgQJBAAAAA==.',
['Jö']='Jöhnblaze:BAABLgAECn8VAAQKAAgJRg3WYQAqAQAKAAcJWwzWYQAqAQAiAAMJIQsLNwCPAAALAAEJPAvHEwA7AAAAAA==.',
Ka='Kaelus:BAAALgADCgEJAQAAAA==.Kahoona:BAAALgAECgIJAwAAAA==.Kailys:BAABLgAECn8UAAIcAAcJKwuNHQAdAQAcAAcJKwuNHQAdAQAAAA==.Kaishias:BAAALgAECgcJEwAAAA==.Kamyra:BAAALgAECgYJDAAAAA==.Kankuró:BAABLgAECn8fAAMPAAgJaBh2CADiAQAPAAgJaBh2CADiAQAQAAEJyAdFjgAtAAAAAA==.',
Ke='Kedzen:BAAALgADCgYJBgABLgAECgYJFwANAHYXAA==.Kerfur:BAAALgAECgMJAwAAAA==.',
Ki='Killudead:BAAALgAECgIJAgAAAA==.',
Ko='Kodetra:BAAALgADCgEJAQAAAA==.Kolgrim:BAABLgAECn8XAAMHAAgJdxjNCQA4AQAjAAYJzxrBHQBcAQAHAAUJbxPNCQA4AQAAAA==.Korimya:BAAALgADCgEJAQAAAA==.Korva:BAAALgAECgQJBwABLgAECgYJGAAEAFgQAA==.',
Kr='Krianthess:BAAALgAECgQJBgAAAA==.Krissypoo:BAAALgADCgcJCwAAAA==.Kristie:BAABLgAECn8YAAIEAAYJWBCBugBsAQAEAAYJWBCBugBsAQAAAA==.Krom:BAABLgAECn8VAAINAAcJ5g9bDwBLAQANAAcJ5g9bDwBLAQAAAA==.',
Ku='Kuadonaran:BAAALgADCgEJAQABLgAECgcJGAAbAGgfAA==.Kulitcomandr:BAAALgADCgUJBQAAAA==.Kupquake:BAABLgAECn8kAAIWAAgJPBusEAB2AgAWAAgJPBusEAB2AgAAAA==.',
Ky='Kynris:BAAALgADCgMJAwABLgAECgYJEgAJAAAAAA==.',
La='Laetus:BAAALgAECgUJCAAAAA==.Lamort:BAABLgAECn8YAAQbAAcJaB/7PAAZAgAbAAYJaB/7PAAZAgAfAAMJFRZjSgCOAAAkAAEJAAB2MAA9AAAAAA==.Lanaal:BAAALgADCgIJAgAAAA==.Lancewh:BAAALgADCgkJDwAAAA==.Lavirna:BAAALgADCgEJAQABLgAECgYJGAAEAFgQAA==.Lazulli:BAAALgADCgMJAwAAAA==.',
Le='Leaila:BAAALgAECgYJEAAAAA==.Leonora:BAAALgAECgYJEgAAAA==.',
Li='Lightbreakk:BAAALgADCgkJDwABLgAECgMJBAAJAAAAAA==.Lindesong:BAAALgADCgkJCQABLgAFFAUJCQAQAEEPAA==.Lisondrel:BAAALgAECgUJBwAAAA==.',
Lo='Lockbone:BAAALgAECgMJAwAAAA==.Loops:BAABLgAECn8YAAIeAAgJdR0ACgA8AgAeAAgJdR0ACgA8AgAAAA==.Lorette:BAABLgAECn8UAAMBAAgJaxXfLQCNAQABAAcJvBbfLQCNAQACAAUJLBU/MgBTAQAAAA==.Lovelychow:BAAALgADCgYJCQAAAA==.',
Ly='Ly:BAAALgADCgUJBQAAAA==.Lymriina:BAACLgAFFH8GAAISAAMJaROdDQARAQASAAMJaROdDQARAQAuAAQKfxwAAhIACAlsI5kHABYDABIACAlsI5kHABYDAAEuAAUUBQkJABAAQQ8A.Lyr:BAAALgADCgcJBwAAAA==.',
Ma='Machotedan:BAABLgAECn8dAAIRAAcJ6R4UCAAJAgARAAcJ6R4UCAAJAgAAAA==.Macmittens:BAAALgADCgkJHQAAAA==.Magedude:BAAALgAECgIJAgAAAA==.Maliken:BAABLgAECn8bAAIFAAgJzB30JQCkAgAFAAgJzB30JQCkAgAAAA==.Mamadrag:BAABLgAECn8ZAAMYAAgJFhgnBACLAQAYAAcJOhcnBACLAQAaAAIJOwXUWABbAAAAAA==.Mambø:BAAALgADCgYJBgAAAA==.Managua:BAAALgADCgEJAQAAAA==.Mario:BAABLgAECn8UAAIEAAYJcBkhlgCoAQAEAAYJcBkhlgCoAQAAAA==.Mastashifta:BAAALgAECgMJAwAAAA==.Matryoshka:BAAALgAECgUJCAAAAA==.Mattsadler:BAAALgAECgEJAgAAAA==.Maverex:BAAALgAECgEJAQAAAA==.Maxxim:BAAALgAECgMJAwAAAA==.',
Me='Mechamonk:BAAALgADCgIJAgAAAA==.Merczdk:BAAALgADCgYJDAAAAA==.Meta:BAAALgAECgYJEQAAAA==.',
Mi='Minthara:BAAALgADCgIJAgAAAA==.Missdemon:BAAALgADCgUJBgAAAA==.Missikrissi:BAAALgADCgYJBgAAAA==.Missmorrigan:BAAALgAECgQJCQAAAA==.Missî:BAAALgADCgkJDgAAAA==.Mists:BAACLgAFFH8IAAIbAAQJ6RneDgBnAQAbAAQJ6RneDgBnAQAuAAQKfx8AAxsACAn+I+kLABsDABsACAn+I+kLABsDAB8AAgmaHe5HAJcAAAAA.Miththrawndo:BAABLgAECn8WAAMjAAgJMBhGEgDnAQAjAAgJMBhGEgDnAQAHAAEJAAAsGwAIAAAAAA==.',
Ml='Ml:BAABLgAECn8UAAMfAAYJVh4DCwAPAgAfAAYJVh4DCwAPAgAbAAQJDA8TJAAJAQAAAA==.',
Mo='Moldevort:BAAALgAECgMJAwAAAA==.Momjeans:BAAALgAECgkJEwAAAA==.Morningumbra:BAAALgADCgIJAgAAAA==.',
Ms='Mstryoda:BAAALgADCgUJCAAAAA==.',
Mu='Muramasa:BAAALgADCggJCAABLgAECgcJGAAWAEIeAA==.',
My='Myfriendtold:BAAALgADCgEJAgAAAA==.Mythunsarian:BAABLgAECn8bAAIlAAcJrw4wBgBYAQAlAAcJrw4wBgBYAQAAAA==.',
['Mä']='Mäylä:BAAALgAECggJDgAAAA==.',
['Mí']='Míst:BAABLgAECn8iAAIRAAgJLhUTZwCyAQARAAgJLhUTZwCyAQAAAA==.',
Na='Nazaline:BAAALgADCgIJAgAAAA==.',
Ne='Necrohealiac:BAAALgAECgEJAgAAAA==.Necromerc:BAAALgAECgQJBAAAAA==.Necrotizer:BAAALgADCgMJAwAAAA==.Nephie:BAABLgAECn8YAAIlAAgJhBxzEgBHAgAlAAgJhBxzEgBHAgAAAA==.Netazia:BAAALgADCgcJGQAAAA==.Nethralfus:BAAALgAECgEJAQAAAA==.Nezqk:BAABLgAECn8fAAIFAAgJzREaXQDbAQAFAAgJzREaXQDbAQAAAA==.',
Ni='Niano:BAAALgADCgEJAgAAAA==.',
Nm='Nmnenthe:BAAALgAECgEJAQAAAA==.',
No='Noelytv:BAAALgADCgcJBwAAAA==.Norman:BAAALgADCgEJAgAAAA==.November:BAAALgADCgEJAQAAAA==.Noxren:BAAALgAECgQJBgAAAA==.',
['Nî']='Nîstø:BAABLgAECn8hAAQIAAgJZhoyBgD0AQAIAAYJIBwyBgD0AQAcAAcJzBhqDgDeAQARAAQJAAr5SwBdAAAAAA==.',
Ob='Obin:BAABLgAECn8bAAIKAAgJVRKrLgD2AQAKAAgJVRKrLgD2AQAAAA==.',
Oh='Oharachloe:BAAALgADCgYJBgAAAA==.',
Ol='Ollenbock:BAAALgADCgQJBAABLgAFFAUJCQAQAEEPAA==.',
Or='Orhanu:BAAALgAECgUJBQAAAA==.',
Ou='Outbbreakk:BAAALgAECgMJBAAAAA==.',
Ow='Owendriel:BAAALgAFFAIJAgAAAA==.',
Pa='Pajamas:BAABLgAECn8gAAIPAAgJMR/uCgDuAgAPAAgJMR/uCgDuAgAAAA==.Palyamorous:BAAALgADCgUJBQAAAA==.Pandress:BAAALgAECgUJDgAAAA==.',
Pe='Peryite:BAABLgAECn8bAAMOAAcJjRD5CQA0AQAOAAcJ7A75CQA0AQABAAYJrwoSRwAdAQAAAA==.',
Pi='Pillpusher:BAAALgAECgMJBAAAAA==.Pisscat:BAAALgAECgEJAQAAAA==.',
Po='Polymerase:BAAALgAECgEJAQABLgAECgcJGgAFAN0YAA==.',
Pr='Prideindeath:BAAALgAECgMJAwAAAA==.Promiscuity:BAAALgAECgYJBwAAAA==.Protròast:BAAALgAECgIJAgAAAA==.Prængle:BAAALgAECgUJCAAAAA==.',
Ps='Psypriest:BAAALgAECgYJDAABLgAFFAUJDwABAL4VAA==.',
Pu='Pulverine:BAAALgADCgcJDgAAAA==.',
Qu='Quarantinia:BAAALgADCgEJAQAAAA==.',
Ra='Rabbi:BAAALgAECgUJCAAAAA==.Ragerunnerx:BAAALgAECggJDwAAAA==.Rahfna:BAAALgAECgEJAQAAAA==.Rakan:BAAALgADCgIJAgAAAA==.Raynare:BAAALgAECgEJAQAAAA==.',
Re='Redall:BAAALgAECgYJDQAAAA==.Reesespbc:BAABLgAECn8WAAIEAAcJhw8kLwANAQAEAAcJhw8kLwANAQAAAA==.Reina:BAAALgAECgQJCQABLgAECgcJDQAJAAAAAA==.Reinir:BAABLgAECn8dAAIiAAcJ1iLMAQAhAgAiAAcJ1iLMAQAhAgAAAA==.Rektagar:BAABLgAECn8WAAMdAAgJnCLdFgBiAgAdAAYJCyPdFgBiAgANAAIJigq9iABxAAABLgAFFAUJCQAQAEEPAA==.Ressandra:BAAALgADCgcJBwAAAA==.Reyvanna:BAAALgADCgEJAQAAAA==.',
Ro='Roar:BAAALgAECgEJAQABLgAECggJFwAFADkPAA==.Robert:BAAALgADCgEJAQAAAA==.Rosavyra:BAAALgAECggJCQAAAA==.Roshara:BAAALgAECgIJAgAAAA==.',
['Rö']='Rös:BAABLgAECn8kAAMEAAgJzBtdOwCJAgAEAAgJzBtdOwCJAgAmAAEJXyDbDABdAAAAAA==.',
Sa='Salamun:BAAALgADCggJCAAAAA==.Salaria:BAAALgAECgYJDgAAAA==.Salen:BAABLgAECn8ZAAIhAAcJqhUADgDdAQAhAAcJqhUADgDdAQAAAA==.Salina:BAEBLgAECn8WAAInAAYJfxb3DACJAQAnAAYJfxb3DACJAQAAAA==.Sandraia:BAABLgAECn8aAAIFAAgJ2Rh7RAAoAgAFAAgJ2Rh7RAAoAgAAAA==.Sandstique:BAABLgAECn8UAAINAAgJaiJoCADvAgANAAgJaiJoCADvAgAAAA==.Sandtwig:BAAALgADCgEJAQAAAA==.Sandweaver:BAAALgADCgEJAQAAAA==.Sanjira:BAAALgAECggJEwAAAA==.Sarusuby:BAABLgAECn8YAAIoAAcJYRdvDQCvAQAoAAcJYRdvDQCvAQAAAA==.',
Sc='Scottyfist:BAABLgAECn8XAAIUAAcJWSB3FgBVAgAUAAcJWSB3FgBVAgAAAA==.Scottymac:BAAALgADCgYJBgABLgAECgcJFwAUAFkgAA==.',
Se='Sealion:BAACLgAFFH8FAAIIAAIJQB2PEQDDAAAIAAIJQB2PEQDDAAAuAAQKfxkAAwgACQmVF14WAF4CAAgACQmVF14WAF4CABEAAwn0HTFKAGIAAAAA.Seetah:BAABLgAECn8UAAIBAAgJgCG/CADAAgABAAgJgCG/CADAAgAAAA==.Serratus:BAABLgAECn8cAAMZAAcJPBoZAgCDAQAZAAcJPBoZAgCDAQAaAAYJDxA0MgA3AQAAAA==.Setcher:BAAALgADCgEJAQAAAA==.',
Sh='Shadaddy:BAAALgAECgQJBAABLgAECgcJFwAHALcaAA==.Shadoweyes:BAAALgAECgEJAQAAAA==.Shamax:BAAALgADCgEJAgABLgADCgUJBQAJAAAAAA==.Shayes:BAABLgAECn8UAAIoAAYJOB3KCwDQAQAoAAYJOB3KCwDQAQAAAA==.Shifue:BAAALgAECgIJAgAAAA==.Shimmerstar:BAAALgAECggJDQAAAA==.',
Si='Sigg:BAAALgAECgUJBQAAAA==.Silexe:BAAALgAECgUJBgABLgAECgcJGAAbAGgfAA==.',
Sk='Skathae:BAAALgAECgEJAQABLgAECgYJEgAJAAAAAA==.Skåld:BAAALgAECgcJEwAAAA==.',
Sn='Snuffles:BAABLgAECn8VAAIeAAYJYBwjDgDlAQAeAAYJYBwjDgDlAQAAAA==.Snugs:BAAALgADCgEJAQAAAA==.',
So='Soldraca:BAAALgAECgIJAgAAAA==.Sorrytanks:BAAALgAECgcJDwAAAA==.Soulence:BAAALgAECgMJBAAAAA==.',
St='Stutters:BAABLgAECn8aAAMFAAcJ3RiCDQCwAQAFAAcJqxiCDQCwAQAjAAUJIBgmIABDAQAAAA==.',
Su='Sudachi:BAABLgAECn8VAAMLAAkJkhqPBACkAgALAAkJkhqPBACkAgAKAAIJAw06lABuAAABLgAFFAEJAQAJAAAAAA==.Sunnyräy:BAAALgADCgcJDQAAAA==.',
Sw='Swineflu:BAAALgAECgMJAwAAAA==.Swizzjenks:BAAALgADCgMJAwAAAA==.',
Sy='Synonym:BAAALgADCgcJBwAAAA==.Syrprize:BAAALgADCgEJAQABLgAECgYJEAAJAAAAAA==.',
['Sý']='Sýndrá:BAAALgAECgcJEQAAAA==.',
Ta='Tacobob:BAABLgAECn8jAAIDAAgJqxVnNwDJAQADAAgJqxVnNwDJAQAAAA==.Taethron:BAAALgADCgUJBQAAAA==.Taffeta:BAAALgADCgEJAQAAAA==.Taffyboy:BAAALgADCggJCgAAAA==.Talysiah:BAAALgAECgUJDgAAAA==.Tannir:BAAALgAECgEJAQAAAA==.Tarogen:BAAALgADCgQJBgABLgAECggJGwAVAMQlAA==.Tavok:BAABLgAECn8WAAMKAAYJHyQgBwCxAQAKAAYJHyQgBwCxAQAiAAEJ+BUCRAA9AAAAAA==.',
Te='Tenacious:BAAALgADCgcJDAAAAA==.Tene:BAAALgADCgMJAwAAAA==.Teratots:BAAALgADCgYJBgAAAA==.Testament:BAAALgADCgcJCAAAAA==.',
Th='Thenna:BAAALgAECgIJAgAAAA==.Theosclaws:BAAALgADCgcJDgAAAA==.Theramier:BAAALgADCgIJAgAAAA==.Thiux:BAABLgAECn8VAAMbAAgJVBw4BABCAgAbAAcJVBw4BABCAgAfAAEJAABiXQBWAAAAAA==.Thotsnprayrs:BAAALgADCgUJCAABLgAECgYJEAAJAAAAAA==.Thourin:BAAALgADCgEJAQAAAA==.Thrappy:BAABLgAECn8ZAAINAAcJ7BxxBgDxAQANAAcJ7BxxBgDxAQAAAA==.Thráwñ:BAAALgAECgIJAwABLgAECgYJCgAJAAAAAA==.',
Ti='Tiddyhammer:BAAALgAECgYJEQAAAA==.Tirtun:BAABLgAECn8aAAIEAAgJchrmTgBKAgAEAAgJchrmTgBKAgAAAA==.',
To='Tomek:BAABLgAECn8WAAMQAAcJsh+GAQDuAQAQAAcJsh+GAQDuAQAeAAUJAhUZGQA9AQAAAA==.Totemetot:BAAALgAECgIJAgAAAA==.',
Tr='Treemourne:BAAALgADCgEJAQAAAA==.Triggeer:BAABLgAECn8eAAIiAAcJWhgeBgBCAQAiAAcJWhgeBgBCAQAAAA==.',
Tu='Turalus:BAAALgADCgYJBgAAAA==.Turina:BAAALgAECgQJBAAAAA==.',
Tw='Twelvekill:BAABLgAECn8kAAIPAAgJuBkoGgBrAgAPAAgJuBkoGgBrAgAAAA==.',
Ty='Tylidus:BAAALgAECgMJAwAAAA==.Tyranny:BAAALgAECgUJCQAAAA==.',
Ub='Ubisami:BAAALgAECgYJBwAAAA==.',
Ul='Ullur:BAAALgADCgEJAgAAAA==.Ultramon:BAAALgAECgYJDgAAAA==.',
Un='Unwell:BAAALgAECgQJBAABLgAECggJGQASABoZAA==.',
Ur='Urgoochness:BAABLgAECn8YAAIDAAcJ6RF1RgCIAQADAAcJ6RF1RgCIAQAAAA==.Urikhai:BAAALgAECgEJAgAAAA==.',
Va='Vaellvoid:BAAALgAECgMJAwAAAA==.Vainglorious:BAAALgAECgIJAgABLgAECgYJCwAJAAAAAA==.Valanora:BAAALgAECgcJEwAAAA==.Valdis:BAAALgADCgcJDAABLgAECgYJGAAEAFgQAA==.Valinaxius:BAAALgAECgQJBgAAAA==.Valphalk:BAAALgADCggJCQAAAA==.Vanastasia:BAAALgAECgQJBgAAAA==.Vapturov:BAAALgAECgMJAwAAAA==.',
Ve='Veeks:BAAALgAECgcJDwAAAA==.Velikirn:BAABLgAECn8gAAMWAAgJRh/CAQBFAgAWAAgJRh/CAQBFAgAUAAUJHRV8QgA5AQAAAA==.Vellwinnalas:BAAALgADCgUJCAAAAA==.Versø:BAABLgAECn8YAAMTAAYJ/hvyBgD9AQATAAYJSBvyBgD9AQASAAQJ1hmDPgAoAQAAAA==.',
Vi='Villageinn:BAAALgAECgMJAwAAAA==.Vine:BAAALgADCgcJDQAAAA==.Vixxon:BAAALgAECgcJDgAAAA==.',
Vl='Vly:BAAALgAECgUJBQAAAA==.Vlyzen:BAAALgAECgQJBQAAAA==.',
Vo='Voidhearted:BAABLgAECn8hAAICAAgJXRohAwALAgACAAgJXRohAwALAgAAAA==.',
['Vì']='Vìolet:BAAALgAECgIJAwABLgAECgYJEQAJAAAAAA==.',
Wa='Waggleton:BAAALgAECgEJAgAAAA==.Warp:BAAALgADCgEJAQAAAA==.Wasted:BAAALgADCgEJAQABLgAECgcJGQANAOwcAA==.Wayshua:BAAALgAECgUJBgAAAA==.',
We='Wearyouout:BAAALgADCgUJBQAAAA==.Wemon:BAAALgAECgMJAwAAAA==.Werkajerk:BAAALgAECgcJEwABLgAFFAQJDAAdAAIlAA==.Werkjathal:BAACLgAFFH8MAAQdAAQJAiVmAwC2AQAdAAQJAiVmAwC2AQAhAAIJzxA/AgCwAAANAAIJhwejGwCKAAAuAAQKfyYABB0ACAmrIhIOAMICAB0ACAmrIhIOAMICAA0ABwnDI40NAK8CACEABAlAH6oGABsBAAAA.Wetribs:BAAALgADCgkJCQAAAA==.',
Wh='Whitedog:BAAALgADCgIJAgAAAA==.Whitetank:BAABLgAECn8eAAIcAAcJwxmpAwCNAQAcAAcJwxmpAwCNAQAAAA==.',
Wi='Willowbeard:BAAALgAECgMJAwAAAA==.Winnelepooh:BAAALgADCgQJBAAAAA==.',
Wo='Wobys:BAABLgAECn8UAAIVAAYJxBfZIgCeAQAVAAYJxBfZIgCeAQAAAA==.Wolfblitzer:BAAALgAECgcJEwAAAA==.Wolfmanbro:BAAALgADCggJCAAAAA==.Worldbane:BAAALgAECgUJEAAAAA==.',
['Wä']='Wärchild:BAAALgADCgcJIAAAAA==.',
Xa='Xalaa:BAAALgAECgYJCgAAAA==.Xalataxfraud:BAAALgAECgQJAwAAAA==.Xanthos:BAAALgADCgcJCAAAAA==.',
Xi='Xianyu:BAAALgAECgIJAwAAAA==.Ximmer:BAAALgAECgEJAQAAAA==.',
Ya='Yarian:BAAALgAECgMJAwAAAA==.',
Yo='Yormin:BAAALgAECgIJAgAAAA==.Yorra:BAAALgAECgIJAgAAAA==.',
Yu='Yuzuu:BAAALgAECgYJCwAAAA==.',
Za='Zachhunter:BAABLgAFFH8JAAIQAAUJQQ83AgAuAQAQAAUJQQ83AgAuAQAAAA==.Zan:BAABLgAECn8kAAMdAAgJVRyqEwCCAgAdAAgJVRyqEwCCAgANAAIJoAvJiQBtAAAAAA==.',
Zo='Zohaan:BAAALgADCgEJAwAAAA==.Zoma:BAAALgADCggJDgAAAA==.',
Zu='Zuhura:BAAALgADCgYJDQAAAA==.Zultrix:BAAALgAECgIJAgAAAA==.',
Zy='Zylaeri:BAAALgAECggJCgAAAA==.',
['Ùl']='Ùly:BAAALgAECgEJAQAAAA==.',
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

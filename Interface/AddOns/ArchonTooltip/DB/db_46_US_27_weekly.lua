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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Protection','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Monk-Windwalker','Shaman-Restoration','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline','Monk-Brewmaster','Druid-Balance','Warlock-Demonology','Druid-Feral','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Priest-Holy',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaravos:BAAALgAECgUJBgAAAA==.',
Ab='Abysseon:BAAALgAECgQJBAAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIBAAcJWgXpIQDzAAABAAcJWgXpIQDzAAAAAA==.Adura:BAAALgADCgcJDwAAAA==.',
Ae='Aeirith:BAABLgAECn8bAAICAAgJ5xwbAwBLAgACAAgJ5xwbAwBLAgAAAA==.',
Ah='Ahheevoker:BAAALgADCgUJBQAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgQJBwAAAA==.Alvist:BAAALgAECgQJBAAAAA==.',
Am='Amarasu:BAAALgAECgcJEgAAAA==.Amarlly:BAAALgAECgUJCwAAAA==.Amenedil:BAAALgAECgEJAQAAAA==.',
An='Anbrew:BAAALgAECgQJBAABLgAFFAMJBgADAGsdAA==.Ancelina:BAAALgAECgUJCgAAAA==.Anderton:BAAALgAECgYJEAAAAA==.Andilocks:BAAALgADCgEJAQAAAA==.Aneira:BAAALgAECgEJAQAAAA==.',
Ap='Apagon:BAAALgAECgEJAQAAAA==.',
Ar='Archérhiro:BAACLgAFFH8IAAMBAAQJMxDlBwAHAQABAAMJMxXlBwAHAQAEAAIJ6QPDIQCHAAAuAAQKfx4AAwEACAniHw8GAA8CAAQACAkrGZEbAEgCAAEABwleHg8GAA8CAAAA.Arilias:BAAALgAECgEJAQABLgAECgYJGAABAPgOAA==.Arillann:BAABLgAECn8fAAIFAAgJQx4+AQAyAgAFAAgJQx4+AQAyAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn8fAAIBAAgJfhKBCQDQAQABAAgJfhKBCQDQAQAAAA==.Arthundermis:BAAALgAECgcJCwAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgcJCwAGAAAAAA==.',
As='Ashymage:BAABLgAECn8dAAIHAAgJyRyyKQDMAgAHAAgJyRyyKQDMAgAAAA==.Askevar:BAAALgAECgYJCwAAAA==.Aspect:BAAALgADCgEJAQABLgADCgkJDgAGAAAAAA==.Astrona:BAAALgADCgUJDgAAAA==.',
At='Atreus:BAAALgAECgYJCgAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Az='Azaleah:BAABLgAECn8aAAIIAAgJ8RE+WwDRAQAIAAgJ8RE+WwDRAQAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAAALgAECgYJCwAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgADCgEJAQABLgAECgQJBAAGAAAAAA==.Banjoman:BAAALgAECgUJDwAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAAALgAECgYJCwAAAA==.',
Be='Beary:BAAALgAECgEJAwAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgEJAQAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigjuicy:BAAALgAECgUJBQAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Blackadder:BAAALgAECgEJAQAAAA==.Blessthefall:BAAALgAECgYJCAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn8fAAIJAAgJqhynAwDaAQAJAAgJqhynAwDaAQAAAA==.',
Bo='Bode:BAAALgAECgMJBQAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgEJAgAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.Borledish:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.Bottosai:BAAALgAECgEJAQAAAA==.',
Br='Breezysha:BAAALgADCgYJBwAAAA==.Brenz:BAAALgAECgQJBgAAAA==.Brokenblade:BAAALgADCgYJBQAAAA==.Brotherblood:BAAALgADCgcJCAAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBAAAAA==.Butterknifeo:BAAALgAFFAEJAQABLgAECgcJHQAHAEwbAA==.',
By='Byryja:BAAALgAECgEJAQAAAA==.',
Ca='Cahrazie:BAAALgADCgUJBQAAAA==.Caidinn:BAAALgAECggJCgAAAA==.Calissancia:BAAALgAECgYJEQAAAA==.Calkey:BAAALgAECgQJCwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8IAAIKAAMJHxsVDQAJAQAKAAMJHxsVDQAJAQAuAAQKfyUAAgoACAlpII0BAKYCAAoACAlpII0BAKYCAAAA.Charlemoo:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.Cheekymonkey:BAAALgAECgUJDAAAAA==.Chueyé:BAAALgADCgYJBwABLgAECggJIwALANUgAA==.Churros:BAAALgAECgYJEAAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQAGAAAAAA==.',
Co='Cordialkylie:BAAALgADCgMJBAAAAA==.',
Cr='Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgADCggJGwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgEJAQAAAA==.',
Da='Dalaris:BAAALgAECgYJDAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darlenedark:BAAALgADCgcJCAAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darrosh:BAABLgAECn8UAAQMAAcJpw4bCQDlAAAMAAYJqw0bCQDlAAALAAYJTwsWEQC3AAANAAMJWgt7FAC1AAAAAA==.Dazdot:BAAALgADCgQJBAAAAA==.',
De='Deathdevil:BAAALgAECgMJAwAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgADCgMJAwAAAA==.Deathmommy:BAAALgADCgkJEAAAAA==.Deathty:BAAALgAECgIJAwABLgAECgQJCAAGAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Derpsforsnac:BAAALgADCgkJAgAAAA==.Design:BAAALgAECgYJEAAAAA==.Desmeridian:BAAALgAECgMJAwAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgADCggJFwAAAA==.',
Di='Disconcern:BAAALgADCgcJBwAAAA==.Discontent:BAAALgAECgUJCAAAAA==.Discordiä:BAABLgAECn8WAAIOAAcJxRjNAwD0AQAOAAcJxRjNAwD0AQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgADCggJHAAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8GAAIKAAQJPhbQAwA5AQAKAAQJPhbQAwA5AQAAAA==.',
Dr='Dracones:BAAALgAECgQJBQAAAA==.Dragondz:BAAALgADCgUJCAAAAA==.Dragonflai:BAABLgAECn8VAAIHAAYJ4xlVIgBJAQAHAAYJ4xlVIgBJAQAAAA==.Dragonkin:BAAALgAECgQJBAAAAA==.Drakkei:BAAALgAECgYJDwAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgADCgUJCwAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn8fAAIPAAgJryJyAQBzAgAPAAgJryJyAQBzAgAAAA==.Drylo:BAEALgAECgkJEwAAAA==.',
Du='Dunstir:BAAALgAECgYJDAAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAAALgAECgYJDwAAAA==.',
Ed='Edelweíss:BAAALgADCgcJDAAAAA==.',
El='Elarol:BAAALgADCgEJAQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAAALgAECgUJCgAAAA==.Emeralde:BAAALgAECgIJAgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyheals:BAABLgAECn8aAAIOAAgJohYhBQC+AQAOAAgJohYhBQC+AQAAAA==.',
Er='Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8UAAIQAAcJTw6zQwAgAQAQAAcJTw6zQwAgAQAAAA==.',
Et='Ethellin:BAAALgAECgYJCwAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.',
Fe='Feildmedic:BAAALgADCgUJBQAAAA==.Felmage:BAAALgADCgEJAQAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgAGAAAAAA==.Felwinter:BAABLgAECn8fAAIRAAgJzReADgCeAQARAAgJzReADgCeAQAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgADCgUJBwAAAA==.',
Fl='Fluxarata:BAAALgAECgUJDAAAAA==.',
Fr='Fred:BAAALgAECgUJCgAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgQJBQAAAA==.Frëya:BAAALgADCgUJBwAAAA==.Frøstitute:BAAALgAECgQJBAAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8VAAISAAYJAyDRAgCcAQASAAYJAyDRAgCcAQAAAA==.Gailardia:BAAALgAECgEJAQAAAA==.Galand:BAAALgAECgYJEgAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAECgEJAQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8WAAIEAAYJow4lBgAZAQAEAAYJow4lBgAZAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Gruggrug:BAAALgADCgIJAQAAAA==.',
Ha='Halleyscomet:BAAALgAECgcJDwAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgADCgcJDQAAAA==.Hawkwave:BAAALgAECgcJBwABLgAECggJCgAGAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAAALgAFFAIJAgAAAA==.Hellbine:BAAALgADCgMJAgAAAA==.',
Ho='Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAABLgAECn8jAAMLAAgJ1SBrAgAUAgALAAgJ1SBrAgAUAgANAAEJ8RDiHABDAAAAAA==.Homealone:BAAALgAECgQJBAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgADCgEJAQAAAA==.Huntinfuzzy:BAAALgAECgMJAwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgIJAgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8VAAITAAcJSiIJEAC4AgATAAcJSiIJEAC4AgAAAA==.',
Il='Illariana:BAAALgAECgUJBwAAAA==.',
In='Insanitty:BAAALgAECgcJCAAAAA==.Invincible:BAAALgAECgEJAQAAAA==.',
Ir='Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAAALgAECgQJBAAAAA==.',
It='Itherious:BAAALgADCgcJEwAAAA==.',
Ja='Jacham:BAAALgAECgIJAgAAAA==.Jackyll:BAAALgADCgIJAgAAAA==.Jatix:BAABLgAECn8fAAIIAAgJIiBhAgCbAgAIAAgJIiBhAgCbAgAAAA==.',
Je='Jeetkundo:BAAALgADCgEJAQAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyspinoff:BAAALgAECgMJBQAAAA==.Jellytown:BAABLgAECn8fAAIHAAgJAw4UFACgAQAHAAgJAw4UFACgAQAAAA==.Jessiana:BAAALgADCgYJCQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgEJAQAAAA==.',
Ju='Juicifer:BAAALgAECgEJAQAAAA==.Jumano:BAAALgADCggJCQAAAA==.Jundra:BAAALgAECgEJAgAAAA==.',
Ka='Kaineh:BAAALgAECgYJDAAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kamis:BAAALgADCgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMUAAgJzxv8LwA8AgAUAAgJzxv8LwA8AgAVAAEJAQdMeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJCwAAAA==.Kasmius:BAAALgADCgUJBQAAAA==.Kasmus:BAAALgAECgMJAwAAAA==.Kawdor:BAAALgAECgYJEQAAAA==.',
Ke='Keetsz:BAAALgAECgIJAwAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAABLgAECn8WAAMVAAgJ6BrUAQAYAgAVAAcJexbUAQAYAgAUAAgJNRdaPgD7AQAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgADCgYJCAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgADCgMJAwAAAA==.Kirtthehurt:BAAALgAECgYJEgAAAA==.',
Ko='Koldfront:BAAALgADCgMJBQAAAA==.Kollinator:BAAALgADCgUJBgAAAA==.Korso:BAAALgADCgUJCwABLgADCggJDgAGAAAAAA==.',
Ky='Kylair:BAABLgAECn8WAAIWAAgJzhmSAwD4AQAWAAgJzhmSAwD4AQAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgIJAgAAAA==.',
La='Labeya:BAAALgADCgEJAQAAAA==.Lafty:BAAALgAECgQJBAABLgAECgQJCAAGAAAAAA==.Laftydh:BAAALgAECgQJCAAAAA==.Lailah:BAAALgADCgIJAgABLgAECggJGgAIAPERAA==.Landrra:BAAALgAECgQJBAAAAA==.Lathsong:BAAALgADCgYJDAAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAAALgAECgUJCAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgADCgEJAQABLgAECgYJEAAGAAAAAA==.Lieree:BAAALgAECgQJCQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAAALgAECgIJAwAAAA==.Linsatha:BAAALgADCgIJAgAAAA==.',
Lo='Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgADCgYJCwAAAA==.Lulubean:BAAALgADCgEJAQAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgUJCAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAAALgAECgYJEQAAAA==.',
Ma='Madison:BAAALgADCgYJCQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Magickul:BAAALgAECgQJCAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgADCgkJEwABLgAECgEJAQAGAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Manavoid:BAAALgAECgYJDAAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAAALgAECgUJDAAAAA==.',
Me='Meri:BAAALgAECgYJEgAAAA==.',
Mi='Microburst:BAAALgADCgUJBQAAAA==.Minilock:BAAALgAECgUJDAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missleading:BAAALgADCgQJBAAAAA==.Missused:BAAALgAECgEJAQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.',
Mo='Mongermook:BAAALgAECgYJEAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQAGAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgMJAwAAAA==.Moonbloom:BAAALgAECgUJEgAAAA==.Morlosh:BAAALgADCgEJAQAAAA==.Moryna:BAAALgAECgYJDAAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Mull:BAAALgADCgkJGAAAAA==.',
My='Myaka:BAAALgADCgMJBwAAAA==.',
Na='Naatixa:BAAALgADCgYJCAAAAA==.Nacronor:BAAALgADCggJGwAAAA==.Naiika:BAAALgAECgIJAgAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgMJBAABLgAECgQJBwAGAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgADCgEJAQAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgIJAgAGAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nickatnite:BAAALgAECgEJAgAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAAALgAECgYJDgAAAA==.Nightgear:BAACLgAFFH8QAAIBAAQJfBQhBABeAQABAAQJfBQhBABeAQAuAAQKf0gAAwEACAkVIQUIABADAAEACAkVIQUIABADAAQAAQm7Ci0SADwAAAAA.Nilux:BAAALgAECgQJCAAAAA==.Ninetails:BAAALgAECgUJBQAAAA==.Niteshadeth:BAAALgADCgUJCwAAAA==.Nixeava:BAAALgADCggJKAAAAA==.',
No='Nopetsneeded:BAABLgAECn8YAAIEAAcJxgdWCADeAAAEAAcJxgdWCADeAAAAAA==.Nostariel:BAAALgADCgEJAQAAAA==.Noteworthy:BAAALgAECgYJDQABLgAFFAMJBgADAGsdAA==.',
Ny='Nysong:BAAALgAECgYJEAAAAA==.',
Od='Oddangel:BAAALgAECgQJBwAAAA==.Odex:BAAALgAECgYJDAAAAA==.',
Oh='Ohblergen:BAAALgAECgEJAQAAAA==.',
Ok='Okragren:BAABLgAECn8YAAIXAAcJhggnRAA4AQAXAAcJhggnRAA4AQAAAA==.',
On='Onos:BAAALgAECgYJEgAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAgAAAA==.Pathogen:BAABLgAECn8ZAAIDAAgJ2BwlBwAPAgADAAgJ2BwlBwAPAgAAAA==.',
Pe='Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgEJAQAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgQJBAAAAA==.Pormas:BAAALgAECgQJCAAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQAGAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Pryto:BAAALgADCgkJDgAAAA==.',
Qu='Queedle:BAAALgAECgQJBAAAAA==.',
Ra='Raennis:BAAALgADCgEJAQAAAA==.Rahanumn:BAAALgAECgQJBQAAAA==.Rainsvoker:BAACLgAFFH8RAAIYAAQJsQs4BAAsAQAYAAQJsQs4BAAsAQAuAAQKfzoAAhgACQnzG/kBABECABgACQnzG/kBABECAAAA.Ramike:BAAALgAECgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Raveena:BAAALgAECgkJEQAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8UAAIIAAYJDQnLKQD7AAAIAAYJDQnLKQD7AAAAAA==.Retman:BAAALgADCgIJAgAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAAALgAECgQJBwAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn8fAAMZAAgJiiB2AgA7AgAZAAcJBCJ2AgA7AgAaAAEJrRe1EQBJAAAAAA==.',
Ro='Roxydan:BAABLgAECn8cAAMbAAgJ6ws5KQAdAQARAAgJ6ws7ZwCWAQAbAAYJ8Ag5KQAdAQAAAA==.',
Ry='Ryko:BAAALgAECgcJDQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgADCggJCgAAAA==.Santadeath:BAAALgADCgIJAQAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Senseijundra:BAAALgAECgIJAgAAAA==.',
Sh='Shadyandi:BAAALgADCgIJAgAAAA==.Shamanhack:BAAALgAECgQJBAAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgEJAwAAAA==.Shmooves:BAEALgADCgYJCgAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgADCgUJBQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgIJAgAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJBAAAAA==.Skullace:BAAALgAECgYJCAAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwAGAAAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Sotzi:BAAALgADCggJEQAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgADCggJGgAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIXAAYJCAxPTAAWAQAXAAYJCAxPTAAWAQAAAA==.Stormßringer:BAABLgAECn8UAAIXAAgJERDTMwCJAQAXAAgJERDTMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJBwAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAAALgAECgMJAwAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECggJCgAGAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgIJAgAAAA==.Sune:BAAALgAECgQJDAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.',
Sy='Syldi:BAAALgADCgMJAwABLgAECgMJBQAGAAAAAA==.Sythis:BAAALgADCgUJCQAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgEJAQAAAA==.',
Ta='Tacosdeasada:BAAALgADCgIJAgAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgADCgcJCAAAAA==.Tanlon:BAAALgADCgYJCgAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8ZAAITAAgJBxDtDQB2AQATAAgJBxDtDQB2AQAAAA==.Tempestira:BAAALgADCgIJBAAAAA==.Tensuken:BAAALgAECgQJDwAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJBgAAAA==.Themedic:BAAALgADCgkJDgAAAA==.Thergothon:BAAALgAECgEJAQAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thrazoro:BAAALgADCgcJCwAAAA==.Thrazzoro:BAAALgAECgQJBAAAAA==.',
Ti='Tiarl:BAABLgAECn8WAAIcAAYJyBGUDwD3AAAcAAYJyBGUDwD3AAAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Titañick:BAAALgADCgEJAQAAAA==.',
To='Tom:BAAALgAECgQJCAAAAA==.Toosxyfohair:BAAALgAECgEJAQAAAA==.',
Tr='Tresg:BAAALgAECgYJCQAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Ty='Tyregar:BAAALgADCgYJCgAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAAALgAECgYJDwAAAA==.',
Un='Unholy:BAAALgAECgQJCgAAAA==.',
Ur='Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgUJBQAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAECgkJJQAIAMMjAA==.',
Va='Valakk:BAAALgADCgkJDgAAAA==.Vallak:BAAALgADCgIJAwAAAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Varadun:BAAALgADCgEJAwABLgADCgkJDgAGAAAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBAAAAA==.',
Ve='Velmora:BAAALgAECgkJCAAAAA==.Velsetin:BAABLgAECn8dAAIHAAcJTBtATABSAgAHAAcJTBtATABSAgAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAAGAAAAAA==.Veryspooky:BAAALgAECggJEwAAAA==.Vexian:BAAALgADCgcJFgAAAA==.',
Vi='Vicas:BAAALgADCggJEwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgUJBQAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
Wh='Whitetoothe:BAAALgAECgMJCAAAAA==.',
Wi='Winterbane:BAAALgAECgMJBgAAAA==.',
['Wå']='Wånheda:BAAALgAECgcJBwAAAA==.',
Xa='Xaniana:BAAALgAECgYJBgAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xo='Xotiko:BAAALgADCgcJBwAAAA==.',
Xu='Xubris:BAAALgADCgUJBQAAAA==.',
Ya='Yaerin:BAABLgAECn8cAAIOAAgJIyJxAAAlAwAOAAgJIyJxAAAlAwAAAA==.',
Yu='Yunarä:BAAALgAECgEJAQAAAA==.Yuukon:BAAALgAECgQJCwAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAAALgAECgYJEQAAAA==.',
Ze='Zenwu:BAAALgADCgkJCQAAAA==.Zephrylia:BAAALgADCggJFgAAAA==.',
Zh='Zheratul:BAAALgADCgkJIwAAAA==.',
Zi='Zilphia:BAAALgAECgUJBgAAAA==.',
['Àm']='Àmagezing:BAAALgAECgIJAgAAAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgADCgMJBAAAAA==.',
['Ór']='Órión:BAAALgAECgUJDAAAAA==.',
['Ös']='Östara:BAAALgAECgQJCAAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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

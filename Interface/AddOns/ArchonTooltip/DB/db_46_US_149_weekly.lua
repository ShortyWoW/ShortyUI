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

local lookup = {'Druid-Balance','Hunter-BeastMastery','Druid-Restoration','Unknown-Unknown','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Priest-Holy','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Priest-Shadow','Paladin-Retribution','DemonHunter-Devourer','Shaman-Elemental','Warrior-Protection','Warlock-Affliction','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Evoker-Devastation','Druid-Guardian','Paladin-Protection','Priest-Discipline','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAUJDwABAE0jAA==.',
Ab='Abadizzo:BAAALgAECgcJBAAAAA==.Abadizzoo:BAABLgAECn8YAAICAAkJDRtWBwCCAgACAAkJDRtWBwCCAgAAAA==.Abilities:BAAALgAECgEJAgAAAA==.',
Ac='Ace:BAAALgAECgQJBgAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgQJCAAAAA==.Agilio:BAABLgAECn8iAAIDAAkJCCTXBABAAwADAAkJCCTXBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgEJAQAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airwrecka:BAABLgAECn8rAAIBAAkJqh6QAgC/AgABAAkJqh6QAgC/AgAAAA==.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAEAAAAAA==.',
Al='Alexian:BAAALgAECgYJDgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgYJDgAAAA==.',
Am='Amebeliever:BAABLgAECn8ZAAMFAAgJKx4WFQBEAgAFAAcJIB0WFQBEAgAGAAcJAgi9NwAMAQAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.',
Ar='Arahgon:BAAALgAECgcJEQABLgAECgQJAgAEAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAEAAAAAA==.',
As='Asher:BAAALgAECgMJAgAAAA==.Asukà:BAABLgAECn8YAAMHAAcJ6QkfFwBPAQAHAAYJ7AofFwBPAQAIAAUJqggwPAC/AAAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJFgAJAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCQAAAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAAALgAECgcJDQABLgAECgcJGAAKALgYAA==.Bellarg:BAABLgAECn8lAAMLAAYJTxvLKACLAQALAAYJTxvLKACLAQAMAAMJ3weoSACUAAAAAA==.Belyn:BAAALgAECgUJCgAAAA==.Benmage:BAAALgADCgIJAgAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bigfaust:BAABLgAECn8YAAQKAAcJox90EgB3AQAKAAUJph90EgB3AQAGAAUJABu7LgBDAQAFAAIJQR/+UgDFAAAAAA==.',
Bl='Blackbudro:BAABLgAECn8bAAINAAgJjhMVCADlAQANAAgJjhMVCADlAQAAAA==.Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAAALgAECgQJCwAAAA==.Bluespider:BAAALgAECgEJAgAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAAALgAECgcJEQABLgAFFAUJEAAOAIIjAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBAAAAA==.Brolich:BAAALgAECgYJCQABLgAECgQJBAAEAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJDAAAAA==.Calculusx:BAABLgAECn8dAAIPAAgJ2hpfBABoAgAPAAgJ2hpfBABoAgAAAA==.',
Ce='Cellice:BAACLgAFFH8XAAMQAAYJVRo9BAAtAgAQAAYJBxo9BAAtAgARAAIJnxuyAAC/AAAuAAQKfzAABBAACQklJgoFALEDABAACQnAJQoFALEDABIACAmUIeICAAUCABEAAwm/IhYGAM0AAAAA.',
Ch='Charlotte:BAAALgAECgcJDQAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn8YAAIKAAcJuBixDgCkAQAKAAcJuBixDgCkAQAAAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAEAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgUJCgAAAA==.',
Co='Coleco:BAABLgAECn8XAAITAAgJ1BjDLgB/AQATAAgJ1BjDLgB/AQABLgAECgkJCQAEAAAAAA==.Combatboots:BAABLgAECn8XAAIUAAcJJwj3EwAMAQAUAAcJJwj3EwAMAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8XAAMKAAYJFho0LwCaAQAKAAUJGhw0LwCaAQAFAAYJ7hKcNwBAAQAAAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8bAAIVAAcJRiJeBQDeAQAVAAcJRiJeBQDeAQAAAA==.Debra:BAABLgAECn8qAAIUAAkJvxvdAgB9AgAUAAkJvxvdAgB9AgAAAA==.Debz:BAAALgAECgQJAQAAAA==.Deegee:BAABLgAECn8WAAMOAAYJfiG+BwAzAgAOAAYJfiG+BwAzAgAWAAYJvBjRJgChAQAAAA==.Deliveryboy:BAAALgADCgMJAwAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgADCgIJAgAAAA==.Demize:BAAALgADCgIJBAAAAA==.Demonflame:BAAALgAECgkJDgAAAA==.Deshield:BAAALgADCgQJBAABLgAFFAQJCgAIALccAA==.Deus:BAABLgAECn8VAAIQAAcJnRN8SABVAQAQAAcJnRN8SABVAQAAAA==.Dewry:BAAALgAECgYJDQAAAA==.',
Dh='Dhudamuthi:BAABLgAECn8jAAIKAAgJiyT6AwBPAwAKAAgJiyT6AwBPAwAAAA==.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgUJBQAAAA==.',
Do='Donnajuan:BAABLgAECn8fAAIJAAgJxRbCDgDyAQAJAAgJxRbCDgDyAQAAAA==.Dornath:BAABLgAECn8ZAAIXAAcJrwXvYwDrAAAXAAcJrwXvYwDrAAAAAA==.',
Dr='Draaxelro:BAABLgAECn8VAAICAAgJCxF2JQCEAQACAAgJCxF2JQCEAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJCgAIALccAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAEAAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8hAAIWAAgJbgkJGgAuAQAWAAgJbgkJGgAuAQAAAA==.Elinalise:BAAALgAECgQJCgABLgAFFAUJDgAYANoLAA==.Elminstér:BAAALgAECgIJAgAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAABLgAECn8iAAICAAgJuR7HDgDFAgACAAgJuR7HDgDFAgAAAA==.',
Em='Embertal:BAAALgAECgYJCgAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgEJAwAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMZAAYJNxY/OQBrAQAZAAYJNxY/OQBrAQAIAAUJpxH7MwDqAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.',
Fe='Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8aAAIXAAYJUwfeXwD1AAAXAAYJUwfeXwD1AAAAAA==.',
Fi='Fiammetta:BAECLgAFFH8FAAIaAAMJBB3VBgD4AAAaAAMJBB3VBgD4AAAuAAQKfxcAAhoACQkuIzsDAF0CABoACQkuIzsDAF0CAAEuAAUUBQkKAAoA6xoA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJDAAEAAAAAA==.Finke:BAABLgAECn8YAAIQAAcJZBzKLgCoAQAQAAcJZBzKLgCoAQAAAA==.Fishmärket:BAABLgAECn8aAAIHAAcJJwyACABpAQAHAAcJJwyACABpAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAAALgAFFAIJAgABLgAFFAQJBQAJAI0QAA==.Frís:BAAALgAECggJEwAAAA==.',
Ga='Galarine:BAABLgAECn8gAAILAAgJUxbJHwC2AQALAAgJUxbJHwC2AQAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAECgcJGAAKALgYAA==.Gilrathor:BAAALgAECgUJCAAAAA==.Gizzlit:BAAALgAECgYJEAAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgEJAQAAAA==.Gofetch:BAABLgAECn8eAAICAAgJohfBEAAQAgACAAgJohfBEAAQAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAEAAAAAA==.',
Gr='Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8WAAMCAAYJCRsUIQCbAQACAAYJBBsUIQCbAQANAAUJ+hL4GAA/AQAAAA==.',
Ha='Hac:BAAALgAECgcJDAAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJDAAEAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAEAAAAAA==.Harpö:BAAALgAECgEJAQABLgAECgYJBgAEAAAAAA==.',
He='Healingkiss:BAAALgAECgQJCQAAAA==.Heatup:BAABLgAECn8aAAIQAAgJfiOrCQCjAgAQAAgJfiOrCQCjAgAAAA==.Helper:BAAALgAECgYJEQAAAA==.',
Ho='Holymages:BAABLgAECn8VAAIQAAYJnBvyiwC6AQAQAAYJnBvyiwC6AQAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.',
Il='Ilyanna:BAABLgAECn8WAAMbAAgJ7RZXCQCvAQAbAAcJBRhXCQCvAQALAAEJXBDJCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8WAAQNAAYJ6xfbAACvAQAcAAUJRhx+BgC3AQANAAYJqQ7bAACvAQACAAEJPRPPIgBaAAAuAAQKfyUAAhwACAmyJCgGADgDABwACAmyJCgGADgDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgMJAwAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgYJBwAEAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgcJFwAUACcIAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhoppss:BAAALgAECgYJEAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAECgUJBwAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgEJAQAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDQAAAA==.',
Ke='Keez:BAAALgAECgEJAQAAAA==.Keezey:BAAALgAECggJEAAAAA==.Kerafyrm:BAABLgAECn8cAAMdAAcJUxujBAAlAgAdAAcJUxujBAAlAgAeAAIJch9yQABQAAAAAA==.Kerrigan:BAACLgAFFH8OAAIYAAUJ2gtgFwAWAQAYAAUJ2gtgFwAWAQAuAAQKfyUAAhgACQnuGrclAHACABgACQnuGrclAHACAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJFgAJAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMDAAkJYxd3JAAoAgADAAkJYxd3JAAoAgAfAAEJPRBSMQA+AAAAAA==.Kozand:BAAALgADCgIJAgABLgABCgYJAwAEAAAAAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCgcJDAAAAA==.',
Ky='Kyirr:BAABLgAECn8dAAMgAAgJcRlJDAAWAgAgAAcJPxpJDAAWAgAeAAQJnRe8JQDbAAAAAA==.Kyralen:BAABLgAECn8WAAMJAAYJHSPEGABMAgAJAAYJHSPEGABMAgAXAAIJVxNikQCEAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8UAAIHAAkJHRRQCgAtAgAHAAkJHRRQCgAtAgAAAA==.',
Li='Lilchithead:BAAALgAECgYJCgAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8KAAIKAAUJ6xorCABQAQAKAAUJ6xorCABQAQAuAAQKfyQAAgoACQl1JSYBAK0DAAoACQl1JSYBAK0DAAAA.',
Ll='Llela:BAAALgAECgQJBQAAAA==.Llynryn:BAABLgAECn8QAAIWAAcJMA5/MwBLAQAWAAcJMA5/MwBLAQAAAA==.',
Ly='Lympha:BAAALgAFFAIJAwAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAUJBwAYAFgaAA==.Magicmanzz:BAAALgAECgYJDAAAAA==.Magnifuso:BAAALgAECgYJCgAAAA==.Malgata:BAAALgADCgkJDwAAAA==.Margarita:BAAALgAECgMJBAAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAABLgAECn8gAAMXAAkJLBqPIQDBAQAXAAcJgRiPIQDBAQAJAAcJ9xDANQClAQAAAA==.',
Mc='Mcplucky:BAAALgAECgQJBAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Mikio:BAAALgAECgYJEgAAAA==.Milinka:BAABLgAECn8iAAIOAAgJJxR0EwB6AQAOAAgJJxR0EwB6AQAAAA==.',
Mo='Moardottz:BAABLgAECn8WAAILAAYJOBVrRQAgAQALAAYJOBVrRQAgAQABLgAECgUJBQAEAAAAAA==.Moiryn:BAABLgAECn8bAAMIAAgJrhqfGQBKAgAIAAgJrhqfGQBKAgAZAAEJZA8oTQA5AAAAAA==.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJBQAAAA==.',
Na='Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8UAAIdAAUJdBJBBgCCAQAdAAUJdBJBBgCCAQAuAAQKfz4AAx0ACQnvFL8MAGoCAB0ACQnvFL8MAGoCACAABgknI9oIAFUCAAAA.',
No='Norasoul:BAABLgAECn8gAAIYAAgJVhqrDgAAAgAYAAgJVhqrDgAAAgAAAA==.',
Og='Ogron:BAACLgAFFH8KAAMIAAQJtxyIDgAcAQAIAAQJtxyIDgAcAQAZAAEJ4x8eHwBgAAAuAAQKfzAAAxkACAkqJhEEAF4DABkACAkqJhEEAF4DAAgAAwkoIHM+ALQAAAAA.',
Oh='Ohmna:BAAALgAECgMJBgAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgYJCwAAAA==.',
Or='Orwenya:BAAALgADCgEJAQABLgABCgYJAwAEAAAAAA==.',
Os='Osten:BAAALgAECgYJDAAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAEAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAAALgAECgQJDQAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgYJBwAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8XAAIBAAcJcxm8AQAAAgABAAcJcxm8AQAAAgAuAAQKfzAAAgEACQmwJbYBALYDAAEACQmwJbYBALYDAAAA.Rexam:BAAALgAECgEJAQABLgAECgYJDwAYABYdAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAAALgAECgUJCgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAAALgAECgYJDAAAAA==.',
Ru='Rucket:BAAALgAECgYJCwAAAA==.Rutroraggy:BAABLgAECn8VAAMRAAYJ5Q8xCQBZAQARAAYJ5Q8xCQBZAQAQAAYJ+whqZwAMAQAAAA==.',
['Rè']='Rènza:BAAALgAECgkJAwAAAA==.',
Sa='Saelybrosa:BAAALgAECgUJCAAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAECgUJBwAEAAAAAA==.Shadda:BAAALgAECgYJDgAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAAALgAFFAIJAwAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgUJCgAEAAAAAA==.Shinru:BAAALgAECgkJEQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAAALgAECggJDAABLgAECggJEwAEAAAAAA==.',
Si='Sickdayze:BAABLgAECn8XAAIJAAgJgB+wBACqAgAJAAgJgB+wBACqAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAEAAAAAA==.Skyrain:BAAALgADCgcJEgAAAA==.',
Sl='Slyxxar:BAABLgAECn8UAAQHAAYJkBcgEQCkAQAHAAYJsRYgEQCkAQAZAAUJtRHfUQD/AAAIAAEJeAFQqwAfAAAAAA==.',
Sm='Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8JAAIDAAUJDRnxBQCjAQADAAUJDRnxBQCjAQAuAAQKfxQAAwMABwlrIlknABkCAAMABwlrIlknABkCAAEAAgmjFuVAAEMAAAEuAAUUBQkQAA4AgiMA.Sophie:BAACLgAFFH8JAAIXAAQJ7Rv2CQBmAQAXAAQJ7Rv2CQBmAQAuAAQKfxUAAxcACAmAF+w7ADQCABcACAmAF+w7ADQCAAkABgkuDk5KAE8BAAEuAAUUBQkQAA4AgiMA.Sophievokie:BAAALgAECgQJCwABLgAFFAUJEAAOAIIjAA==.Sophisticate:BAAALgAECgcJDAABLgAFFAUJEAAOAIIjAA==.Sophiz:BAAALgAECgYJDwABLgAFFAUJEAAOAIIjAA==.Sophlax:BAACLgAFFH8QAAIOAAUJgiOiAQCpAQAOAAUJgiOiAQCpAQAuAAQKfxUAAg4ACQmFHw0EABQDAA4ACQmFHw0EABQDAAAA.Sophs:BAAALgAECgUJDQABLgAFFAUJEAAOAIIjAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAABLgAECn8qAAIhAAkJEyHEAAC9AgAhAAkJEyHEAAC9AgAAAA==.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAECgcJEwAEAAAAAA==.',
Sp='Spicynoodle:BAAALgAECgYJBgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAAALgAFFAEJBAAAAA==.',
Sq='Squattinchop:BAABLgAECn8VAAIFAAYJKyDwFQA6AgAFAAYJKyDwFQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJFQAFACsgAA==.',
St='Stiffcrit:BAAALgAECgMJAwAAAA==.Stinkydh:BAAALgAECgYJEQAAAA==.Stryx:BAAALgADCgYJBgABLgAECgYJDwAEAAAAAA==.',
Su='Suji:BAAALgAECgcJEwAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAEAAAAAA==.Supergogeta:BAABLgAECn8iAAMDAAcJfCJ1DgDGAgADAAcJfCJ1DgDGAgAhAAEJiQQ4NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgcJDAAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
Ta='Takoda:BAAALgADCgYJBgAAAA==.Talauyia:BAAALgAECgYJCQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.',
Th='Thorish:BAABLgAECn8iAAIiAAkJtiGrAwDbAgAiAAkJtiGrAwDbAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgIJAwAAAA==.Timbit:BAABLgAECn8iAAIFAAgJfQkrGgAUAQAFAAgJfQkrGgAUAQAAAA==.Tinybubbles:BAABLgAECn8XAAMIAAYJZRn3MwC0AQAIAAYJZRn3MwC0AQAZAAQJKw2NXwDFAAAAAA==.Tinyfeet:BAAALgADCgUJCwAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgYJCwAEAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8XAAMjAAgJUxcSCwDcAQAjAAgJUxcSCwDcAQAWAAEJtQeGQwAxAAAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAAEAAAAAA==.Tròybòy:BAABLgAECn8XAAITAAcJNyF/FQAOAgATAAcJNyF/FQAOAgAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgIJAgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgEJAQAAAA==.',
Ty='Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAAALgAECgYJBgAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAAALgAECgYJDgAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8YAAMTAAYJ5xU/UgAKAQATAAYJ5xU/UgAKAQAVAAUJZAmxFQDSAAAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMkAAgJ8iOoAQDjAgAkAAgJ8iOoAQDjAgAlAAEJnBXhOwBCAAAAAA==.Veyla:BAEALgADCgcJDgAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAABLgAECn8dAAITAAgJQxVYaQC6AQATAAgJQxVYaQC6AQAAAA==.',
Wa='Warkdom:BAAALgADCgIJAgAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAABLgAECn8WAAIaAAYJiyKWBgDjAQAaAAYJiyKWBgDjAQAAAA==.',
Wh='Wheelchair:BAEALgADCgYJBgABLgADCgcJDgAEAAAAAA==.',
Wi='Wickeddemon:BAAALgAECgQJCQAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8fAAIJAAgJcBJiFwCVAQAJAAgJcBJiFwCVAQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgADAGMXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAABLgAECn8bAAIYAAgJ9h+7BQCEAgAYAAgJ9h+7BQCEAgAAAA==.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8OAAIfAAUJcha4AACxAQAfAAUJcha4AACxAQAuAAQKfxYAAh8ACAnDInIEANUCAB8ACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zaftenpuff:BAAALgAECgQJBAAAAA==.Zarya:BAAALgAECgUJCgAAAA==.',
Ze='Zelgie:BAABLgAECn8aAAMiAAYJvBHIHQAbAQAiAAYJvBHIHQAbAQAJAAUJ4RBEJgAXAQAAAA==.',
Zo='Zorsse:BAAALgAECgMJAwAAAA==.',
Zu='Zulu:BAAALgAECgYJDAAAAA==.',
['Zâ']='Zâkârum:BAAALgADCgcJBwAAAA==.',
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

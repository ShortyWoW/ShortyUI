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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Paladin-Retribution','Evoker-Preservation','DemonHunter-Devourer','Shaman-Elemental','Warrior-Protection','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Priest-Discipline','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJBAAAAA==.Abadizzoo:BAABLgAECn8hAAICAAkJVCHqAwD5AgACAAkJVCHqAwD5AgAAAA==.Abilities:BAAALgAECgEJAgAAAA==.',
Ac='Ace:BAAALgAECgQJBgAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgQJCQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8iAAIEAAkJBiTVBABAAwAEAAkJBiTVBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAgAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airwrecka:BAABLgAECn8rAAIBAAkJqh5IBAC0AgABAAkJqh5IBAC0AgAAAA==.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
Al='Alexian:BAAALgAECgYJEwAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgYJDgAAAA==.',
Am='Amebeliever:BAABLgAECn8dAAQGAAgJLB4SFQBEAgAGAAcJIh0SFQBEAgAHAAcJAgi+NwAMAQAIAAQJ/gl7QgCNAAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgQJBAAAAA==.',
Ar='Arahgon:BAAALgAECgcJEwABLgAECgUJAwAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asukà:BAABLgAECn8gAAMJAAgJvxF9GQDmAQAJAAgJvxF9GQDmAQAKAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAQAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJFgALAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAAALgAECgcJEwABLgAECgkJIwAMAO4iAA==.Bellarg:BAABLgAECn8sAAMNAAcJfRpnJADZAQANAAcJfRpnJADZAQAOAAMJ3wepSACUAAAAAA==.Belobog:BAAALgAECgMJAwABLgAECggJHAADALsPAA==.Belyn:BAAALgAECgUJCwAAAA==.Benmage:BAAALgAECgEJAQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bigfaust:BAABLgAECn8YAAQIAAcJph+MGAByAQAIAAUJpx+MGAByAQAHAAUJARu7LgBDAQAGAAIJRR//UgDFAAAAAA==.',
Bl='Blackbudro:BAABLgAECn8hAAIPAAgJ1BRwCwDtAQAPAAgJ1BRwCwDtAQAAAA==.Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAAALgAECgcJEQAAAA==.Bluespider:BAAALgAECgIJAwAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAAALgAECgcJEQABLgAFFAYJDQAEADIWAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECgcJDgABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJDAAAAA==.Calculusx:BAABLgAECn8hAAIQAAgJ7xpfBABoAgAQAAgJ7xpfBABoAgAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8cAAMRAAYJURo/BAAtAgARAAYJBRo/BAAtAgASAAIJmRsXAQC3AAAuAAQKfzYABBEACQkrJgoFALEDABEACQn7JQoFALEDABMACAkSIuECAAUCABIAAwm/IoUHAMgAAAAA.',
Ch='Charlotte:BAAALgAECgcJDgAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn8cAAIIAAgJsxrACwAFAgAIAAgJsxrACwAFAgABLgAECgkJIwAMAO4iAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgUJCgAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgMSQAYAgADAAgJ1BgMSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn8eAAIUAAgJbwkvFQBAAQAUAAgJbwkvFQBAAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMIAAYJ2RswLwCaAQAIAAUJGhwwLwCaAQAGAAYJsRSgKwDbAAAAAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8cAAIVAAcJRSJjBgA0AgAVAAcJRSJjBgA0AgAAAA==.Debra:BAABLgAECn8qAAIUAAkJwhtLBQBkAgAUAAkJwhtLBQBkAgAAAA==.Debz:BAAALgAECgQJAQAAAA==.Deegee:BAABLgAECn8WAAMWAAYJgSEaDAAlAgAWAAYJgSEaDAAlAgAXAAYJvBjPJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAQAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJAQAAAA==.Demize:BAAALgADCgIJBAAAAA==.Demonflame:BAABLgAECn8aAAIOAAkJHxWAAgAhAgAOAAkJHxWAAgAhAgAAAA==.Deshield:BAAALgADCgQJBAABLgAFFAQJDgAJAGslAA==.Deus:BAABLgAECn8XAAIRAAgJKRKXRgCTAQARAAgJKRKXRgCTAQAAAA==.Dewry:BAAALgAECgYJDQAAAA==.',
Dh='Dhudamuthi:BAABLgAECn8jAAIIAAgJiyT5AwBPAwAIAAgJiyT5AwBPAwAAAA==.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgUJBQAAAA==.',
Do='Donnajuan:BAABLgAECn8nAAILAAgJthlECwBeAgALAAgJthlECwBeAgAAAA==.Dornath:BAABLgAECn8fAAIYAAcJPgbyewD0AAAYAAcJPgbyewD0AAAAAA==.',
Dr='Draaxelro:BAABLgAECn8XAAICAAgJsRHcNQB1AQACAAgJsRHcNQB1AQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJDgAJAGslAA==.Dragontiddys:BAABLgAECn8XAAIZAAgJRRqiBABiAgAZAAgJRRqiBABiAgAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8mAAIXAAkJzQnbFwB/AQAXAAkJzQnbFwB/AQAAAA==.Elinalise:BAAALgAECgQJCgABLgAFFAUJEgAaAEYOAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAABLgAECn8qAAICAAgJLB/FDgDFAgACAAgJLB/FDgDFAgAAAA==.',
Em='Embertal:BAAALgAECgYJCgAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgYJCAAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMbAAYJNxZAOQBrAQAbAAYJNxZAOQBrAQAJAAUJthF9RwDiAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAQABLgAECggJFgAUACchAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.',
Fe='Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8gAAIYAAYJiAelfgDvAAAYAAYJiAelfgDvAAAAAA==.',
Fi='Fiammetta:BAECLgAFFH8HAAIcAAQJpR3XBgD5AAAcAAQJpR3XBgD5AAAuAAQKfxgAAhwACQlnIxwFAFgCABwACQlnIxwFAFgCAAEuAAUUBgkOAAgADRsA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJDAAFAAAAAA==.Finke:BAABLgAECn8aAAIRAAcJZhw/QgCgAQARAAcJZhw/QgCgAQAAAA==.Fishmärket:BAABLgAECn8eAAIKAAkJeQvSBgDLAQAKAAkJeQvSBgDLAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAAALgAFFAIJAgABLgAFFAQJBQALAJYQAA==.Frís:BAAALgAECggJEwAAAA==.',
Ga='Galarine:BAABLgAECn8lAAINAAkJcBe6EgBNAgANAAkJcBe6EgBNAgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAECgkJIwAMAO4iAA==.Gilrathor:BAAALgAECgcJCgAAAA==.Gizzlit:BAABLgAECn8WAAIKAAYJnxWoDQArAQAKAAYJnxWoDQArAQAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgEJAQAAAA==.Gofetch:BAABLgAECn8fAAICAAgJ4RnmFgAYAgACAAgJ4RnmFgAYAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8dAAMCAAcJdhywHADwAQACAAcJdhywHADwAQAPAAUJ+hL4GAA/AQAAAA==.',
Ha='Hac:BAAALgAECgcJDQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJDQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.Harpö:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAAALgAECgYJEQAAAA==.Heatup:BAABLgAECn8aAAIRAAgJfiMxFQApAwARAAgJfiMxFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Holymages:BAABLgAECn8cAAIRAAcJ/RpCOwC2AQARAAcJ/RpCOwC2AQAAAA==.Homtardy:BAAALgAECgEJAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.',
Il='Ilyanna:BAABLgAECn8bAAMdAAkJoRxhAQBWAgAdAAkJoRxhAQBWAgANAAEJXxDUCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8YAAQPAAcJvRbpAQCiAQAeAAYJARqCBgC3AQAPAAYJng7pAQCiAQACAAEJPRPWIgBaAAAuAAQKfyUAAh4ACAmyJDMGADkDAB4ACAmyJDMGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgMJAwAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgYJBwAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECggJHgAUAG8JAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhalse:BAAALgADCgMJAwAAAA==.Jhoppss:BAABLgAECn8WAAMfAAYJlx1nDwDkAQAfAAYJlx1nDwDkAQAgAAQJjQ+jPgCgAAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAFFAEJAQAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDQAAAA==.',
Ke='Keez:BAAALgAECgYJDAAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kerafyrm:BAABLgAECn8jAAMZAAcJ+B6uBABgAgAZAAcJ+B6uBABgAgAgAAIJch9gUgBPAAAAAA==.Kerrigan:BAACLgAFFH8SAAIaAAUJRg75IwAgAQAaAAUJRg75IwAgAQAuAAQKfykAAhoACQkgHbIlAHACABoACQkgHbIlAHACAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJFgALAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd2JAAoAgAEAAkJaBd2JAAoAgAhAAEJPRBTMQA+AAAAAA==.Kozand:BAAALgADCgIJAgABLgADCgEJAQAFAAAAAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCgcJEQAAAA==.',
Ky='Kyirr:BAABLgAECn8eAAMfAAgJchlKDAAWAgAfAAcJQRpKDAAWAgAgAAQJnheHMgDZAAAAAA==.Kyralen:BAABLgAECn8WAAMLAAYJHSPDGABMAgALAAYJHSPDGABMAgAYAAIJVxMZvAB8AAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIKAAkJiRVQCgAsAgAKAAkJiRVQCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgYJCgAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8OAAIIAAYJDRufDABRAQAIAAYJDRufDABRAQAuAAQKfyUAAggACQl1JSYBAK0DAAgACQl1JSYBAK0DAAAA.Lividea:BAAALgADCgEJAQAAAA==.Livinglover:BAAALgADCgMJAwAAAA==.',
Ll='Llela:BAAALgAECgUJBgAAAA==.Llynryn:BAABLgAECn8SAAIXAAcJMA6AMwBLAQAXAAcJMA6AMwBLAQAAAA==.',
Ly='Lympha:BAABLgAFFH8FAAIJAAIJriQiIQDVAAAJAAIJriQiIQDVAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAYJDgAaAEwcAA==.Magicmanzz:BAAALgAECgYJDQAAAA==.Magnifuso:BAAALgAECgYJCwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgMJBQAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8GAAILAAMJIRc/FwDsAAALAAMJIRc/FwDsAAAuAAQKfycAAwsACQnbHywLAF8CAAsABwkNHywLAF8CABgABwl9GbMtAMYBAAAA.',
Mc='Mcplucky:BAAALgAECgQJBAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Mikio:BAABLgAECn8ZAAIBAAcJgg1+IAAzAQABAAcJgg1+IAAzAQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8nAAIWAAkJcxctDAAjAgAWAAkJcxctDAAjAgAAAA==.',
Mo='Moardottz:BAABLgAECn8XAAINAAYJPxW0cgB5AQANAAYJPxW0cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8FAAIJAAMJYw7SIwDGAAAJAAMJYw7SIwDGAAAuAAQKfyEAAwkACAnKGp8ZAEoCAAkACAnKGp8ZAEoCABsAAQlxD1BgADkAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8ZAAIZAAYJxBDfBQDIAQAZAAYJxBDfBQDIAQAuAAQKfz8AAxkACQnvFL4MAGoCABkACQnvFL4MAGoCAB8ABwmbIdwIAFUCAAAA.',
No='Norasoul:BAABLgAECn8lAAIaAAkJVRuICACdAgAaAAkJVRuICACdAgAAAA==.',
Og='Ogron:BAACLgAFFH8OAAMJAAQJayWyBQC6AQAJAAQJayWyBQC6AQAbAAEJcx/JGwBTAAAuAAQKfzgAAxsACQl8JdsCAOsCABsACQl8JdsCAOsCAAkAAwkoIGFTALAAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgYJCwAAAA==.',
Or='Orwenya:BAAALgADCgYJCQABLgADCgEJAQAFAAAAAA==.',
Os='Osten:BAAALgAECgYJDQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAAALgAECgQJDQAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgYJBwAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8bAAIBAAcJDhq+AQAAAgABAAcJDhq+AQAAAgAuAAQKfzAAAgEACQnFJbYBALYDAAEACQnFJbYBALYDAAAA.Rexam:BAAALgAECgIJAgABLgAECgYJEQAaAPsfAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAAALgAECgYJEgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAAALgAECgYJEgAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8VAAMSAAYJ5A8yCQBZAQASAAYJ5A8yCQBZAQARAAYJ/QiKhAAJAQAAAA==.',
['Rè']='Rènza:BAAALgAECgkJAwAAAA==.',
Sa='Saelybrosa:BAAALgAECgYJCQAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAEJAQAFAAAAAA==.Shadda:BAAALgAECgYJDgAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8FAAIbAAIJgAlFJACNAAAbAAIJgAlFJACNAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgUJCgAFAAAAAA==.Shinru:BAABLgAECn8WAAMLAAkJbhhyFgDbAQALAAgJCxdyFgDbAQAYAAYJlR4xSgBnAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAAALgAECggJDQABLgAECggJEwAFAAAAAA==.',
Si='Sickdayze:BAABLgAECn8ZAAILAAgJ9SAlBgC+AgALAAgJ9SAlBgC+AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgADCgcJEgAAAA==.',
Sl='Slyxxar:BAACLgAFFH8FAAIJAAMJIwWBKQCqAAAJAAMJIwWBKQCqAAAuAAQKfxYABAoABwkiF2EKAG8BAAoABwn2FmEKAG8BABsABQm1EeZRAP8AAAkAAQl4AU2rAB8AAAAA.',
Sm='Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8NAAIEAAYJMhaaBQDkAQAEAAYJMhaaBQDkAQAuAAQKfxUAAwQABwlrIlUnABkCAAQABwlrIlUnABkCAAEAAgmjFiZRAEIAAAAA.Sophie:BAACLgAFFH8KAAMYAAQJ9RvIEQBgAQAYAAQJ9RvIEQBgAQALAAEJ2w1OLQBAAAAuAAQKfxUAAxgACAmBF+o7ADQCABgACAmBF+o7ADQCAAsABgkuDlBKAE8BAAEuAAUUBgkNAAQAMhYA.Sophievokie:BAAALgAECgQJCwABLgAFFAYJDQAEADIWAA==.Sophisticate:BAAALgAFFAQJBAABLgAFFAYJDQAEADIWAA==.Sophiz:BAAALgAECgYJDwABLgAFFAYJDQAEADIWAA==.Sophlax:BAACLgAFFH8SAAIWAAUJeyO7AQDlAQAWAAUJeyO7AQDlAQAuAAQKfxUAAhYACQmFHw4EABQDABYACQmFHw4EABQDAAEuAAUUBgkNAAQAMhYA.Sophs:BAAALgAFFAIJAgABLgAFFAYJDQAEADIWAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAABLgAECn8qAAIiAAkJHiHYAAAEAwAiAAkJHiHYAAAEAwAAAA==.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAEJAQAFAAAAAA==.',
Sp='Spicynoodle:BAAALgAECgkJCwAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8ZAAIXAAUJUSVkEgC1AQAXAAUJUSVkEgC1AQAAAA==.',
Sq='Squattinchop:BAABLgAECn8XAAIGAAYJaiDvFQA6AgAGAAYJaiDvFQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJFwAGAGogAA==.',
St='Stiffcrit:BAAALgAECgMJAwAAAA==.Stinkydh:BAABLgAECn8SAAIaAAYJMhEKXgDkAAAaAAYJMhEKXgDkAAAAAA==.Stryx:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.',
Su='Suji:BAABLgAECn8UAAIDAAgJQBWLPQCFAQADAAgJQBWLPQCFAQAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supergogeta:BAABLgAECn8nAAQEAAgJUiFxDgDGAgAEAAcJfCJxDgDGAgABAAIJ+A5XQwBwAAAiAAEJiQQ8NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgcJDAAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
Ta='Takoda:BAAALgADCgYJBgAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAAALgAECgYJDQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBAAAAA==.',
Th='Thorish:BAABLgAECn8kAAIMAAkJ5CGqAwDbAgAMAAkJ5CGqAwDbAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgUJDgABLgAECgkJFwAZAEUaAA==.Timbit:BAABLgAECn8jAAIGAAgJfQlQIwAOAQAGAAgJfQlQIwAOAQAAAA==.Tinfoiltotem:BAAALgADCgYJAQAAAA==.Tinybubbles:BAABLgAECn8eAAMJAAcJbRj1MwC0AQAJAAcJbRj1MwC0AQAbAAQJKw2QXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJCgAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgYJCwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8ZAAMjAAgJDhn+DQDxAQAjAAgJDhn+DQDxAQAXAAEJvwfmVgAtAAAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Tròybòy:BAABLgAECn8eAAIDAAgJlSGlDgCMAgADAAgJlSGlDgCMAgAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgMJAwAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgEJAQABLgAECgkJNQAfAIQlAA==.',
Ty='Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAAALgAECgcJDQAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAAALgAECgYJDgAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8fAAMVAAcJaBVdFgAeAQAVAAcJZQ9dFgAeAQADAAYJ5xV9bgAFAQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMkAAgJ+CO+AwDMAgAkAAgJ+CO+AwDMAgAlAAEJnBXjOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAABLgAECn8hAAIDAAkJwxXJRwBkAQADAAkJwxXJRwBkAQAAAA==.',
Wa='Warkdom:BAAALgAECgMJAwAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAABLgAECn8dAAIcAAcJhiORBABpAgAcAAcJhiORBABpAgAAAA==.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAAALgAECgYJEQAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAILAAkJxhTjFADqAQALAAkJxhTjFADqAQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAABLgAECn8eAAIaAAgJ6R/oCgB9AgAaAAgJ6R/oCgB9AgAAAA==.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8SAAIhAAUJdx24AACxAQAhAAUJdx24AACxAQAuAAQKfxYAAiEACAnDInIEANUCACEACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zaftenpuff:BAAALgAECgQJBAAAAA==.Zarya:BAAALgAECgUJDQAAAA==.',
Ze='Zelgie:BAABLgAECn8hAAMMAAcJnhC0EgAWAQAMAAcJnhC0EgAWAQALAAUJ6BCPMgAGAQAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAkAN0XAA==.',
Zu='Zulu:BAAALgAECgYJDQAAAA==.',
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

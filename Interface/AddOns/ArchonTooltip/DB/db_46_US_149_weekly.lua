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

local lookup = {'Druid-Balance','Druid-Restoration','Unknown-Unknown','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Rogue-Assassination','Mage-Frost','Mage-Fire','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Restoration','Monk-Brewmaster','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Shaman-Enhancement','Hunter-Survival','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Evoker-Devastation','Druid-Guardian','Paladin-Protection','Priest-Discipline','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAUJCgABAKwdAA==.',
Ab='Abadizzo:BAAALgAECgYJAwAAAA==.Abadizzoo:BAAALgAECgcJDwAAAA==.',
Ac='Ace:BAAALgAECgQJBAAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agilio:BAABLgAECn8iAAICAAkJCCTYBABAAwACAAkJCCTYBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgEJAQAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airwrecka:BAABLgAECn8iAAIBAAgJwh/zAgASAgABAAgJwh/zAgASAgAAAA==.Airyxana:BAAALgADCgEJAQABLgAECgUJBQADAAAAAA==.',
Al='Alexian:BAAALgAECgUJDQAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgQJCQAAAA==.',
Am='Amebeliever:BAABLgAECn8YAAMEAAgJKx4TFQBEAgAEAAcJIB0TFQBEAgAFAAcJAghhNwARAQAAAA==.',
An='Andari:BAAALgAECgYJCwAAAA==.',
Ar='Arahgon:BAAALgAECgYJCwABLgADCgkJHgADAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQADAAAAAA==.',
As='Asukà:BAAALgAECgYJEwAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJEAADAAAAAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCQAAAA==.',
Be='Beans:BAAALgADCggJDgAAAA==.Bearhugzz:BAAALgAECgcJDQAAAA==.Bellarg:BAABLgAECn8fAAMGAAYJSBW4hABQAQAGAAYJxxS4hABQAQAHAAMJ3welSACUAAAAAA==.Belyn:BAAALgAECgUJBgAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bigfaust:BAAALgAECgYJEQAAAA==.',
Bl='Blackbudro:BAAALgAECgYJEwAAAA==.Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAAALgAECgMJBwAAAA==.Bluespider:BAAALgADCgkJGwAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAAALgAECgcJEQABLgAFFAUJEAAIAIIjAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBAAAAA==.Brolich:BAAALgAECgUJCAABLgAECgQJBAADAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJDAAAAA==.Calculusx:BAABLgAECn8XAAIJAAgJhBpfBABoAgAJAAgJhBpfBABoAgAAAA==.',
Ce='Cellice:BAACLgAFFH8QAAIKAAYJ2Bc5BAAtAgAKAAYJ2Bc5BAAtAgAuAAQKfyoAAwoACQklJggFALEDAAoACQnAJQgFALEDAAsACAmUIeACAAUCAAAA.',
Ch='Charlotte:BAAALgAECgUJBgAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAAALgAECgYJEQABLgAECgcJDQADAAAAAA==.Chuttbeeks:BAAALgAECgIJAwABLgAECgUJBQADAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgMJBQAAAA==.',
Co='Coleco:BAABLgAECn8XAAIMAAgJ1Bj7DQCrAQAMAAgJ1Bj7DQCrAQAAAA==.Combatboots:BAAALgAECgYJEAAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAAALgAECgYJEQAAAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAAALgAECgYJEwAAAA==.Debra:BAABLgAECn8hAAINAAgJsRoWDwByAgANAAgJsRoWDwByAgAAAA==.Debz:BAAALgAECgQJAQAAAA==.Deegee:BAAALgAECgYJEAAAAA==.Deliveryboy:BAAALgADCgMJAwAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgADCgIJAgAAAA==.Demize:BAAALgADCgIJBAAAAA==.Demonflame:BAAALgAECggJDAAAAA==.Deshield:BAAALgADCgQJBAABLgAFFAMJBgAOAC4VAA==.Deus:BAABLgAECn8VAAIKAAcJnRPsHABmAQAKAAcJnRPsHABmAQAAAA==.Dewry:BAAALgAECgQJCAAAAA==.',
Dh='Dhudamuthi:BAABLgAECn8dAAIPAAgJiyT3AwBPAwAPAAgJiyT3AwBPAwAAAA==.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgUJBQAAAA==.',
Do='Donnajuan:BAABLgAECn8XAAIQAAcJyRmdCQCoAQAQAAcJyRmdCQCoAQAAAA==.Dornath:BAAALgAECgYJEgAAAA==.',
Dr='Draaxelro:BAAALgAECgcJEwAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAMJBgAOAC4VAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgADAAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8bAAIRAAcJ4AhDLQB0AQARAAcJ4AhDLQB0AQAAAA==.Elinalise:BAAALgAECgQJCQABLgAFFAQJCQASAIYKAA==.Elminstér:BAAALgADCgYJBgAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAABLgAECn8bAAITAAgJAB7HDgDFAgATAAgJAB7HDgDFAgAAAA==.',
Em='Embertal:BAAALgAECgQJBAAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgEJAQAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMUAAYJNxY/OQBrAQAUAAYJNxY/OQBrAQAOAAUJpxGOFgD1AAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.',
Fe='Feyre:BAABLgAECn8UAAIVAAYJEAcLMwDOAAAVAAYJEAcLMwDOAAAAAA==.',
Fi='Fiammetta:BAEALgAFFAMJAwABLgAFFAQJBwAPAOsaAA==.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJDAADAAAAAA==.Finke:BAAALgAECgcJEgAAAA==.Fishmärket:BAABLgAECn8UAAIWAAYJggzMBQA5AQAWAAYJggzMBQA5AQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Frostie:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Frís:BAAALgAECggJEwAAAA==.',
Ga='Galarine:BAABLgAECn8ZAAIGAAcJZhbhTgDbAQAGAAcJZhbhTgDbAQAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgEJAQABLgAECgcJDQADAAAAAA==.Gilrathor:BAAALgAECgMJAwAAAA==.Gizzlit:BAAALgAECgYJDQAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgADCgYJCwAAAA==.Gofetch:BAABLgAECn8WAAITAAcJoxl5CQDQAQATAAcJoxl5CQDQAQAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAADAAAAAA==.',
Gr='Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAAALgAECgYJEAAAAA==.',
Ha='Hackacracka:BAAALgAECgYJDgAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgADCgYJAQABLgAECgEJAQADAAAAAA==.Harpull:BAAALgADCgYJEAABLgAECgEJAQADAAAAAA==.Harpö:BAAALgAECgEJAQAAAA==.',
He='Healingkiss:BAAALgAECgQJBAAAAA==.Heatup:BAAALgAECggJEQAAAA==.Helper:BAAALgAECgYJEAAAAA==.',
Ho='Holymages:BAAALgAECgYJEAAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.',
Il='Ilyanna:BAAALgAECgcJDwAAAA==.',
Im='Im:BAACLgAFFH8SAAQXAAYJDxcyAACtAQAYAAUJRhx7BgC3AQAXAAYJoQoyAACtAQATAAEJPRPKIgBaAAAuAAQKfyUAAhgACAmyJCUGADgDABgACAmyJCUGADgDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgIJAgAAAA==.',
In='Incandescent:BAAALgADCgcJCwAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgYJEAADAAAAAA==.',
Ja='Ja:BAAALgADCgMJAwAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhoppss:BAAALgAECgYJEAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAECgUJBwAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgEJAQAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgIJBQAAAA==.',
Ke='Keezey:BAAALgAECggJEAAAAA==.Kerafyrm:BAABLgAECn8VAAMZAAYJRR2hAgDjAQAZAAYJRR2hAgDjAQAaAAEJPCMjXQBFAAAAAA==.Kerrigan:BAACLgAFFH8JAAISAAQJhgqHCAArAQASAAQJhgqHCAArAQAuAAQKfykAAhIACAl4H48DAGYCABIACAl4H48DAGYCAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJEAADAAAAAA==.',
Ko='Kookler:BAABLgAECn8hAAMCAAgJUhl2JAAoAgACAAgJUhl2JAAoAgAbAAEJPRBJMQA+AAAAAA==.Kozand:BAAALgADCgEJAQABLgABCgYJAwADAAAAAA==.Kozari:BAAALgAECgYJEAAAAA==.',
Ku='Kushmon:BAAALgADCgcJDAAAAA==.',
Ky='Kyirr:BAABLgAECn8dAAMcAAgJcRlHDAAWAgAcAAcJPxpHDAAWAgAaAAQJnRcsEQDdAAAAAA==.Kyralen:BAAALgAECgYJEAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAAALgAECggJEwAAAA==.',
Li='Lilchithead:BAAALgAECgYJCgAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8HAAIPAAQJ6xoqCABQAQAPAAQJ6xoqCABQAQAuAAQKfyQAAg8ACQl1JSYBAK0DAA8ACQl1JSYBAK0DAAAA.',
Ll='Llela:BAAALgAECgMJAwAAAA==.Llynryn:BAABLgAECn8VAAIRAAcJ8REKCAB4AQARAAcJ8REKCAB4AQAAAA==.',
Ly='Lympha:BAAALgAFFAEJAQAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAUJCAASAN8UAA==.Magicmanzz:BAAALgAECgUJBgAAAA==.Magnifuso:BAAALgAECgQJBAAAAA==.Malgata:BAAALgADCgYJBgAAAA==.Margarita:BAAALgAECgEJAQAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAABLgAECn8gAAMVAAkJLBrsDADHAQAVAAcJgRjsDADHAQAQAAcJ9xDCNQClAQAAAA==.',
Mc='Mcplucky:BAAALgAECgQJBAAAAA==.Mcziggles:BAAALgAECgQJBAAAAA==.',
Mi='Mikio:BAAALgAECgUJDQAAAA==.Milinka:BAABLgAECn8bAAIIAAcJzRJWKwCbAQAIAAcJzRJWKwCbAQAAAA==.',
Mo='Moardottz:BAAALgAECgYJEAABLgAECgUJBQADAAAAAA==.Moiryn:BAABLgAECn8bAAMOAAgJrhqnGQBKAgAOAAgJrhqnGQBKAgAUAAEJZA9PJgA5AAAAAA==.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJBQAAAA==.',
Na='Naturals:BAAALgAECgEJAQAAAA==.Navillus:BAACLgAFFH8QAAIZAAUJEg4xAgCIAQAZAAUJEg4xAgCIAQAuAAQKfz0AAxkACQnvFLwMAGoCABkACQnvFLwMAGoCABwABgknI9oIAFUCAAAA.',
No='Norasoul:BAABLgAECn8ZAAISAAcJVhqbNwAXAgASAAcJVhqbNwAXAgAAAA==.',
Og='Ogron:BAACLgAFFH8GAAMOAAMJLhX+CQCnAAAOAAMJLhX+CQCnAAAUAAEJVhq/GwBTAAAuAAQKfygAAxQACAkZJg4EAF4DABQACAkZJg4EAF4DAA4AAwmtHZIdAKQAAAAA.',
Oh='Ohmna:BAAALgAECgMJBgAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgMJBQAAAA==.',
Os='Osten:BAAALgAECgYJBgAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgYJEQADAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAAALgAECgQJCAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgMJAwAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8SAAIBAAYJjhW9AQAAAgABAAYJjhW9AQAAAgAuAAQKfyoAAgEACQmrJbQBALYDAAEACQmrJbQBALYDAAAA.Rexam:BAAALgADCgEJAQABLgAFFAEJAQADAAAAAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAAALgAECgQJBAAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAAALgAECgQJBgAAAA==.',
Ru='Rucket:BAAALgAECgUJCgAAAA==.Rutroraggy:BAAALgAECgYJDwAAAA==.',
['Rè']='Rènza:BAAALgAECgkJAwAAAA==.',
Sa='Saelybrosa:BAAALgAECgMJAwAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAECgUJBwADAAAAAA==.Shadda:BAAALgAECgQJCAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAAALgAECgYJDAAAAA==.Shinru:BAAALgAECggJCQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.',
Si='Sickdayze:BAABLgAECn8VAAIQAAcJyR/2AgBfAgAQAAcJyR/2AgBfAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAADAAAAAA==.Skyrain:BAAALgADCgcJEgAAAA==.',
Sl='Slyxxar:BAAALgAECgYJEAAAAA==.',
Sm='Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJBwAAAA==.Soph:BAAALgAFFAIJBAABLgAFFAUJEAAIAIIjAA==.Sophie:BAACLgAFFH8FAAIVAAQJ9guHEAAiAQAVAAQJ9guHEAAiAQAuAAQKfxUAAxUACAmAF/E7ADQCABUACAmAF/E7ADQCABAABgkuDk9KAE8BAAEuAAUUBQkQAAgAgiMA.Sophievokie:BAAALgAECgQJCwABLgAFFAUJEAAIAIIjAA==.Sophisticate:BAAALgAECgcJDAABLgAFFAUJEAAIAIIjAA==.Sophiz:BAAALgAECgYJCwABLgAFFAUJEAAIAIIjAA==.Sophlax:BAACLgAFFH8QAAIIAAUJgiMzAADzAQAIAAUJgiMzAADzAQAuAAQKfxUAAggACQmFHwwEABQDAAgACQmFHwwEABQDAAAA.Sophs:BAAALgAECgUJDQABLgAFFAUJEAAIAIIjAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAABLgAECn8hAAIdAAgJESKSAACAAgAdAAgJESKSAACAAgAAAA==.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAECgcJEwADAAAAAA==.',
Sp='Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAAALgAFFAEJBAAAAA==.',
Sq='Squattinchop:BAAALgAECgYJDwAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJDwADAAAAAA==.',
St='Stinkydh:BAAALgAECgYJEQAAAA==.',
Su='Suji:BAAALgAECgUJCwAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgADAAAAAA==.Supergogeta:BAABLgAECn8cAAMCAAcJfCJ1DgDGAgACAAcJfCJ1DgDGAgAdAAEJiQQ0NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgMJBQAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
Ta='Talauyia:BAAALgAECgMJAwAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgADCgMJAwAAAA==.',
Th='Thorish:BAABLgAECn8iAAIeAAkJtiGqAwDbAgAeAAkJtiGqAwDbAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgIJAwAAAA==.Timbit:BAABLgAECn8bAAIEAAcJdgrUDQDyAAAEAAcJdgrUDQDyAAAAAA==.Tinybubbles:BAABLgAECn8XAAMOAAYJZRn0MwC0AQAOAAYJZRn0MwC0AQAUAAQJKw2EXwDFAAAAAA==.Tinyfeet:BAAALgADCgUJBgAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgMJBQADAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8VAAIfAAcJPxlFBQC5AQAfAAcJPxlFBQC5AQAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAADAAAAAA==.Tròybòy:BAAALgAECgYJEAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgADCggJDAAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.',
Ty='Tyranis:BAAALgADCgkJHgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAAALgAECgQJBgAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAAALgAECgYJEgAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8XAAMgAAcJPyMPAgBOAgAgAAcJPyMPAgBOAgAhAAEJnBXiOwBBAAAAAA==.Veyla:BAEALgADCgcJDgAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgYJEQAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAABLgAECn8aAAIMAAgJxQ5eaQC6AQAMAAgJxQ5eaQC6AQAAAA==.',
Wa='Warkdom:BAAALgADCgIJAgAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAAALgAECgYJEAAAAA==.',
Wh='Wheelchair:BAEALgADCgYJBgABLgADCgcJDgADAAAAAA==.',
Wi='Wickeddemon:BAAALgAECgQJBAAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8YAAIQAAcJFxOxDAB0AQAQAAcJFxOxDAB0AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECggJIQACAFIZAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAABLgAECn8ZAAISAAgJxhTiDACsAQASAAgJxhTiDACsAQAAAA==.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8KAAIbAAUJHRK4AACxAQAbAAUJHRK4AACxAQAuAAQKfxYAAhsACAnDInEEANUCABsACAnDInEEANUCAAAA.',
Yr='Yralka:BAAALgAECgIJAgAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zaftenpuff:BAAALgAECgQJBAAAAA==.Zarya:BAAALgAECgMJBQAAAA==.',
Ze='Zelgie:BAABLgAECn8UAAMeAAYJvBHHHQAbAQAeAAYJvBHHHQAbAQAQAAQJgg/9FQDmAAAAAA==.',
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

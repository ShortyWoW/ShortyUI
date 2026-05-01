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

local lookup = {'Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Arcane','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Evoker-Preservation','Monk-Mistweaver','DemonHunter-Devourer','Paladin-Holy','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','DemonHunter-Havoc','Paladin-Protection','Warrior-Fury','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Hunter-Survival','Mage-Fire','Rogue-Assassination','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAAALgAECgcJDQAAAA==.',
Ac='Activision:BAAALgAECgMJAwAAAA==.',
Ad='Ademisk:BAAALgADCgYJDAAAAA==.Adventureux:BAABLgAECn8fAAIBAAgJ7xvrDwAYAgABAAgJ7xvrDwAYAgAAAA==.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8UAAICAAYJgBmqNQCtAQACAAYJgBmqNQCtAQAAAA==.',
Ai='Aiblul:BAAALgAECgQJBwAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgcJEQABLgAECggJGQADANgiAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgAEAAAAAA==.Aliroarx:BAAALgADCggJDgAAAA==.Almosteasy:BAABLgAECn8XAAIFAAgJLCO4BwAfAwAFAAgJLCO4BwAfAwAAAA==.Alunadoom:BAAALgADCgcJBwAAAA==.Alunagryn:BAACLgAFFH8GAAIGAAQJTQY7EQD2AAAGAAQJTQY7EQD2AAAuAAQKfyMABAYACAllGZkTABICAAYACAnHFZkTABICAAcABwkyF1ofAN0BAAgABQnpGGY1AGgBAAAA.Alvera:BAABLgAECn8hAAIJAAgJuh3NOABTAgAJAAgJuh3NOABTAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgAAAA==.',
An='Angerforge:BAAALgAECgcJBwAAAA==.',
Ar='Arielordril:BAAALgAECgQJCQAAAA==.Arm:BAABLgAECn8hAAMKAAgJKBc8NQDTAQAKAAcJWxY8NQDTAQALAAgJ0xIIEgB8AQAAAA==.Armee:BAABLgAECn8bAAIIAAgJqRrnDwBnAgAIAAgJqRrnDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgEJAgAAAA==.',
As='Asmilwelme:BAAALgAECgQJBAAAAA==.Astrael:BAABLgAECn8dAAMMAAgJBRHMKwC1AQAMAAgJSBDMKwC1AQANAAUJ2hCnDgDZAAAAAA==.Aszayla:BAAALgAECgUJCQAAAA==.Aszea:BAAALgAECgQJBAAAAA==.',
Av='Avoidme:BAAALgAECgMJBgAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwAEAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8kAAIOAAgJfxB8KgDCAQAOAAgJfxB8KgDCAQAAAA==.Azóg:BAABLgAECn8iAAIJAAgJhhhGJgCmAQAJAAgJhhhGJgCmAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAECgUJBwAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8UAAMPAAcJTB/HBACvAQAPAAYJEiPHBACvAQAQAAUJTxoUAgBwAQAuAAQKfx4AAw8ACQk8JvsBAJkDAA8ACQk8JvsBAJkDABAACAkaJCIEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAAALgADCgcJBwABLgAECggJIgAHAIwRAA==.',
Be='Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgUJCQABLgAECgYJEwAEAAAAAA==.Beastiegrljd:BAAALgADCgYJBgAAAA==.Beastoker:BAAALgAECgMJAwAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAcJEwAMAJIfAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgAECgEJAQAAAA==.Beeto:BAACLgAFFH8HAAIRAAMJGA4AIgCpAAARAAMJGA4AIgCpAAAuAAQKfxoAAhEACAlaHTokAJcCABEACAlaHTokAJcCAAAA.Bekdrop:BAAALgAFFAEJAQABLgAFFAcJEwAMAJIfAA==.Benlian:BAAALgAECgUJBwAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8TAAIMAAUJKBQtHgBWAQAMAAUJKBQtHgBWAQAuAAQKfyMAAwwACAkgIbMgAPECAAwACAkgIbMgAPECAA0AAQmmFUoeADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8LAAIMAAQJRxF5LwD4AAAMAAQJRxF5LwD4AAAuAAQKfyoAAgwACQljHjIbAAoDAAwACQljHjIbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAABLgAFFH8JAAIKAAcJARyLAACAAgAKAAcJARyLAACAAgABLgAFFAYJFwASABkaAA==.Boof:BAABLgAECn8aAAIHAAgJGxpsGwACAgAHAAgJGxpsGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgADCgUJBQAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAAALgAECgQJBwAAAA==.Bruski:BAAALgAECgMJAwAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAECggJLgAMABIiAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8UAAIRAAgJ2R6RQwAZAgARAAgJ2R6RQwAZAgAAAA==.Buzzbuzz:BAAALgAECggJDwAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAISAAYJGRoaAgAKAgASAAYJGRoaAgAKAgAuAAQKfx8AAxIACQllHzYEABMDABIACQllHzYEABMDABAAAwn5Iu4iABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAITAAMJaiBdCwAjAQATAAMJaiBdCwAjAQABLgAFFAYJFwASABkaAA==.',
Ca='Caelin:BAABLgAECn8dAAIUAAcJcw0tNQAOAQAUAAcJcw0tNQAOAQAAAA==.Caishana:BAABLgAECn8iAAICAAkJxh0RCgDYAgACAAkJxh0RCgDYAgAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAAALgAECgYJCgAAAA==.',
Ce='Cecil:BAABLgAECn8ZAAIVAAgJGwP2KAACAQAVAAgJGwP2KAACAQAAAA==.Celeb:BAABLgAECn8jAAIWAAgJzCMJAQAyAwAWAAgJzCMJAQAyAwAAAA==.Celebrity:BAAALgAECgQJBQABLgAECggJIwAWAMwjAA==.Celebtard:BAAALgAECgEJAQABLgAECggJIwAWAMwjAA==.Cervrakabra:BAAALgAECgEJAQAAAA==.',
Ch='Chaddingus:BAAALgAECgcJCgAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgIJBAAAAA==.Chilltea:BAABLgAECn8eAAIMAAgJ+CPkBwC7AgAMAAgJ+CPkBwC7AgAAAA==.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8UAAMXAAYJuQiVXADcAAAXAAUJuQiVXADcAAAYAAIJuwELKQBNAAAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAABLgAECn8WAAIVAAYJEiGWCgAtAgAVAAYJEiGWCgAtAgAAAA==.',
Co='Coheedkil:BAAALgADCgEJAQABLgADCgIJAgAEAAAAAA==.Coldbreeze:BAAALgAECgMJAwABLgAECgYJEQAEAAAAAA==.Collateral:BAAALgADCgUJCQAAAA==.Compaktdisc:BAAALgAECggJEAAAAA==.Conartist:BAAALgAECgEJAQABLgAECggJJQAZALskAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwAEAAAAAA==.Cowpox:BAABLgAECn8YAAIKAAcJbA4UKABHAQAKAAcJbA4UKABHAQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAAALgAECgYJBwAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn8kAAIVAAcJ8x+9EgB8AgAVAAcJ8x+9EgB8AgAAAA==.Cry:BAAALgAECgEJAgAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8IAAIaAAMJTSJTDgAhAQAaAAMJTSJTDgAhAQAuAAQKfx0AAhoACAmoHjALANkCABoACAmoHjALANkCAAAA.',
Cy='Cybuster:BAAALgAECgcJCQABLgAECgkJGwAMABkfAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8aAAIMAAgJ9RF/ewDaAQAMAAgJ9RF/ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8ZAAIWAAgJDhbWCQDOAQAWAAgJDhbWCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECgQJBgAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAAALgAECgYJEAABLgAECgUJDgAEAAAAAA==.Dargong:BAAALgADCgIJAgAAAA==.Darkrunes:BAABLgAECn8dAAIUAAcJLho1PgD7AQAUAAcJLho1PgD7AQAAAA==.Darrkness:BAAALgAFFAEJAQAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJBwAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgEJAQABLgAECggJHQAbAGETAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAAALgAECgcJEwAAAA==.Deristus:BAABLgAECn8cAAIXAAgJnBSCVQDHAQAXAAgJnBSCVQDHAQAAAA==.Deroth:BAAALgADCgUJBQAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAAEAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgAEAAAAAA==.Devi:BAAALgAECgIJAwAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dirtmonkgirt:BAAALgAECgcJEwAAAA==.Dirtysham:BAABLgAECn8cAAIOAAgJcBjGIQABAgAOAAgJcBjGIQABAgAAAA==.Discipline:BAAALgAFFAEJAQAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8VAAMJAAYJwBBRkQBdAQAJAAYJwBBRkQBdAQAbAAYJ8gYIGQC0AAAAAA==.Dotdotgoose:BAAALgAECgQJAwABLgAECggJEAAEAAAAAA==.Dotgunner:BAABLgAECn8XAAIXAAcJXRtBQAANAgAXAAcJXRtBQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECggJFwAUAD8aAA==.Downbad:BAACLgAFFH8FAAIXAAMJdQcaJwDhAAAXAAMJdQcaJwDhAAAuAAQKfx8AAxcACAl+H10XAMgCABcACAl+H10XAMgCABwABAm8Cwo1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJGgAdALoPAA==.Drahseer:BAAALgAECgIJAgAAAA==.Drakulya:BAAALgAECgYJDgAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAABLgAECn8QAAMUAAYJMQvrRQDUAAAUAAYJrwjrRQDUAAAdAAMJMghkWgB5AAAAAA==.Driftèr:BAAALgAECgcJDAAAAA==.Drizzle:BAABLgAECn8bAAIUAAgJTiVkIQCJAgAUAAgJTiVkIQCJAgAAAA==.Drkdestro:BAABLgAECn8iAAQXAAkJ+SC/DwD8AgAXAAkJ+SC/DwD8AgAYAAEJAADBHwBzAAAcAAEJyxzAXwBPAAAAAA==.Druidic:BAACLgAFFH8IAAIKAAQJdCM/BgCeAQAKAAQJdCM/BgCeAQAuAAQKfygAAgoACAlMJbsDAFYDAAoACAlMJbsDAFYDAAAA.Druvinci:BAAALgADCgQJBAAAAA==.Drü:BAAALgAECggJEgAAAA==.',
Du='Dunk:BAAALgADCgIJAgAAAA==.Dusan:BAABLgAECn8lAAMIAAgJ6B3FAwCiAgAIAAgJ6B3FAwCiAgAGAAYJmgv3FwAsAQAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ear:BAAALgADCgcJBwABLgAECgkJIwAeAIEiAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8hAAMCAAcJGRc+GACjAQACAAcJGRc+GACjAQADAAQJ/wK6IgCqAAAAAA==.',
Ed='Edonsian:BAABLgAECn8kAAMfAAgJKxs8HgBdAgAfAAgJxRk8HgBdAgAgAAIJXRkrOgB6AAAAAA==.',
Ee='Eepy:BAABLgAECn8aAAMTAAkJpxHrHQDGAQATAAkJpxHrHQDGAQAZAAUJrBEYHQD8AAAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgADCgEJAQABLgAECgcJEwAEAAAAAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAAALgAECgcJEgAAAA==.Emorlyn:BAABLgAECn8XAAMBAAkJwg+oNADcAQABAAkJwg+oNADcAQAFAAYJpgILZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Endrai:BAAALgAECgEJAQAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAABLgAECn8dAAIMAAgJOxwXTQBPAgAMAAgJOxwXTQBPAgAAAA==.',
Er='Eriksangus:BAABLgAECn8XAAIfAAgJAAiyHQBEAQAfAAgJAAiyHQBEAQAAAA==.',
Es='Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAAALgAECgYJDgAAAA==.',
Ev='Evilguard:BAABLgAECn8dAAIbAAgJYRMPFwCmAQAbAAgJYRMPFwCmAQAAAA==.Evilpatty:BAAALgADCggJCAAAAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECgUJCAAAAA==.',
Fa='Falador:BAAALgADCgcJBwAAAA==.Fariebubbles:BAAALgAECgQJCQAAAA==.Fastandis:BAAALgADCgYJDAAAAA==.Fatale:BAAALgAECgIJAgAAAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMXAAcJgRm1aQCQAQAXAAYJghq1aQCQAQAcAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAAALgAECggJDwAAAA==.Fenixstraza:BAACLgAFFH8KAAQPAAQJxBTVFQD5AAAPAAMJ0xnVFQD5AAASAAIJ4hYHFQBpAAAQAAEJlQXWBgBBAAAuAAQKfyMAAxIACAlLGyYNAGQCABIABwkVHCYNAGQCAA8ACAmzEmUfAMcBAAAA.Fervis:BAAALgAECgQJCAABLgAECgYJDAAEAAAAAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJDAAAAA==.Firitako:BAAALgAECgQJCgAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECggJJQAfAJEhAA==.Flipper:BAABLgAECn8XAAMVAAgJPBatIgAJAgAVAAgJPBatIgAJAgARAAIJawFwRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8VAAMYAAgJxh+RAwBfAgAYAAgJxh+RAwBfAgAXAAIJBBTSEwE6AAAAAA==.Frankiejr:BAAALgAECgIJAgABLgAECgcJEwAEAAAAAA==.Frapsity:BAAALgAECgYJDwAAAA==.Frostamper:BAAALgAECgQJCQAAAA==.Frostpoptart:BAABLgAECn8bAAICAAcJHBwBIgATAgACAAcJHBwBIgATAgAAAA==.Frozenblade:BAAALgADCgkJCQAAAA==.',
Fu='Fupah:BAAALgADCgEJAQAAAA==.Furball:BAAALgAECgMJAwABLgAFFAQJDQAXAGgSAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAABLgAECn8VAAIaAAcJux/+FgBQAgAaAAcJux/+FgBQAgAAAA==.Galadrielle:BAAALgAECgMJAwAAAA==.Gandelf:BAAALgADCgEJAQABLgAECggJFwABAFkWAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8lAAIhAAgJWwrODQDbAAAhAAgJWwrODQDbAAAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAABLgAECn8aAAIUAAgJJhjPTQC+AQAUAAgJJhjPTQC+AQAAAA==.',
Gh='Ghostfate:BAAALgAECgEJAQAAAA==.',
Gi='Gigbutt:BAABLgAECn8jAAIiAAkJDxlNEwB+AgAiAAkJDxlNEwB+AgAAAA==.Giggléz:BAAALgAECgYJCQAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAIMAAgJIBs9RABrAgAMAAgJIBs9RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgADCgkJFQAAAA==.Goatedfury:BAAALgAFFAMJAwAAAA==.Gorgrot:BAAALgAECgEJAQABLgAFFAMJBwALANoTAA==.Gorshot:BAAALgAECggJDwAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgADCgcJBwABLgAECggJLQAcAIkhAA==.Griitz:BAAALgAECgEJAQAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAABLgAECn8hAAMjAAgJMSAyAQCnAgAjAAgJMSAyAQCnAgAhAAYJkQ8JFwAFAQAAAA==.Griswold:BAAALgAECgQJCwAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8aAAMMAAgJqBvmQAB2AgAMAAgJqBvmQAB2AgANAAEJ0ibRFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJGgAMAKgbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8FAAIJAAIJgx1STQCqAAAJAAIJgx1STQCqAAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJBAAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8XAAIHAAkJwQhwFgBMAQAHAAkJwQhwFgBMAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8jAAMXAAgJ8iF4DQBCAgAXAAgJ8iF4DQBCAgAcAAMJeh4OMQD1AAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAgAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAAALgAECggJDgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECggJDwAEAAAAAA==.Hoofrat:BAAALgAECgcJBQAAAA==.',
Hp='Hpal:BAAALgADCgEJAQAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgYJCgAEAAAAAA==.Huxley:BAAALgADCgEJAQAAAA==.Huñted:BAABLgAECn8aAAMkAAgJAhMwCQDPAQAkAAgJmQ8wCQDPAQABAAYJIw7PYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgADCgMJAwAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgYJCgAEAAAAAA==.',
Ic='Icuris:BAAALgAECgMJAwAAAA==.',
Id='Idistroya:BAAALgAECgQJBAAAAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMYAAgJVxWPCADBAQAYAAYJ1BiPCADBAQAXAAgJ+xAwIQCuAQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8WAAIIAAgJkxVTGwACAgAIAAgJkxVTGwACAgAAAA==.Ilithiya:BAAALgAECgYJBwAAAA==.Illidrac:BAABLgAECn8aAAIdAAkJug9pDAB2AQAdAAkJug9pDAB2AQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJEwAEAAAAAA==.',
Im='Imangry:BAAALgAECgQJCQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inpherno:BAAALgADCgEJAQAAAA==.',
Is='Isaidnoice:BAABLgAECn8YAAMcAAcJiRShFgCVAQAcAAYJ6RShFgCVAQAXAAcJRQ5rMgBiAQAAAA==.Ishton:BAAALgAECggJCgAAAA==.Istompgnomes:BAAALgADCggJEwAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgYJEQAAAA==.',
Ja='Jacked:BAABLgAECn8WAAMXAAgJQxw2TwDaAQAXAAYJQBs2TwDaAQAYAAMJMR/CEAAhAQAAAA==.Jasøn:BAAALgAECgQJBAABLgAECgYJCwAEAAAAAA==.',
Je='Jecka:BAABLgAECn8iAAMHAAgJ6RIeEQCAAQAHAAcJAhEeEQCAAQAIAAcJEA2wQgAuAQAAAA==.Jeckah:BAAALgADCgcJBwABLgAECggJIgAHAOkSAA==.Jecthyr:BAAALgAECgEJAQABLgAECggJIgAHAOkSAA==.Jefryepsteen:BAAALgADCgUJBQAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAAALgAECgYJEwAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8WAAMeAAYJAh5WCQB1AQAeAAYJAh5WCQB1AQARAAEJrwLyWQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jo='Jordana:BAAALgAECgcJEgAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJAQAAAA==.',
Js='Jsdruid:BAAALgAECgYJCwAAAA==.',
Ju='Jug:BAABLgAECn8cAAIkAAgJqBurBADJAgAkAAgJqBurBADJAgAAAA==.',
Ka='Kainöa:BAAALgAECgYJDAABLgAECgYJEwAEAAAAAA==.Kakum:BAAALgADCgkJFgAAAA==.Kaldrogo:BAAALgAECgQJCQAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAUJEwATAFYfAA==.Kalnuggets:BAAALgADCgcJBgAAAA==.Kalrathen:BAABLgAECn8eAAIIAAcJ8hPoEwB0AQAIAAcJ8hPoEwB0AQAAAA==.Kaniku:BAAALgAECgEJAgABLgAFFAQJBwAMAOgMAA==.Karsh:BAABLgAECn8XAAIfAAgJrwaIIgAkAQAfAAgJrwaIIgAkAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAAALgAECgYJDQAAAA==.',
Ke='Kered:BAAALgAECgQJBAAAAA==.Keuaakepo:BAABLgAECn8rAAMBAAgJzCBuCAByAgABAAgJzCBuCAByAgAkAAEJUQM6MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8fAAIBAAYJVBs1NgA5AQABAAYJVBs1NgA5AQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECgQJAwABLgAECggJEAAEAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgMJAwAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAAALgAECgYJCwAAAA==.',
Ko='Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8kAAMjAAkJxxb0AQBoAgAjAAkJxxb0AQBoAgAhAAIJ0AweKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJBgAAAA==.',
Kr='Krethar:BAAALgAECgIJAgAAAA==.Krypt:BAABLgAECn8ZAAIgAAgJShE/GwByAQAgAAgJShE/GwByAQAAAA==.Krìzl:BAABLgAECn8fAAIMAAgJBCLjFAA0AgAMAAgJBCLjFAA0AgAAAA==.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgMJAwAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAABLgAECn8tAAQcAAgJiSHUAAB8AgAcAAgJiSHUAAB8AgAXAAUJ1hYZNABbAQAYAAEJGh6UDQBWAAAAAA==.Lanzen:BAAALgADCgUJBQAAAA==.Lanzier:BAAALgADCgIJAgABLgADCgUJBQAEAAAAAA==.Larrfena:BAAALgAECgYJDgAAAA==.',
Le='Legit:BAAALgAECgYJCgABLgAECggJHQAUAC4aAA==.Lementz:BAACLgAFFH8OAAIDAAUJxB2tAADIAQADAAUJxB2tAADIAQAuAAQKfzAAAgMACQl3JmEAAMQDAAMACQl3JmEAAMQDAAAA.Lexiiees:BAAALgAECgYJEwAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAAALgAECgQJCQAAAA==.Lillia:BAABLgAECn8lAAIXAAgJ5RE8IQCuAQAXAAgJ5RE8IQCuAQAAAA==.',
Lo='Lovetobussy:BAAALgAECgYJEwAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn8vAAMXAAkJAByRCgBlAgAXAAkJfBuRCgBlAgAcAAUJtBuBGwBxAQAAAA==.Lumpia:BAABLgAECn8aAAIJAAgJKR+WEQAuAgAJAAgJKR+WEQAuAgAAAA==.',
['Lè']='Lèah:BAAALgAECgUJBQAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAEJAQABLgAFFAMJCQAMADojAA==.Magenta:BAAALgAECgQJBAAAAA==.Magicchoc:BAAALgAECgYJCAABLgAECggJHQAbAGETAA==.Maktah:BAAALgAFFAMJAwAAAA==.Mandrakor:BAAALgADCgEJAQAAAA==.Marshboa:BAAALgAECgUJCgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mclovinit:BAACLgAFFH8TAAIMAAcJkh+ZAgBeAgAMAAcJkh+ZAgBeAgAuAAQKf0sAAgwACQmkJnsAAAIEAAwACQmkJnsAAAIEAAAA.Mcmagic:BAABLgAECn8gAAIMAAYJUCPiSQBZAgAMAAYJUCPiSQBZAgAAAA==.Mcpally:BAABLgAECn8nAAIRAAgJdyG5DwBAAgARAAgJdyG5DwBAAgAAAA==.',
Me='Mecca:BAACLgAFFH8GAAIJAAIJlRkXbQBTAAAJAAIJlRkXbQBTAAAuAAQKfxUAAwkABwlVISNAADgCAAkABwlVISNAADgCABsABQl7Fh0kACABAAAA.Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8bAAIKAAgJsyS7CAADAwAKAAgJsyS7CAADAwAAAA==.Mensu:BAAALgAECgYJBgAAAA==.Mentos:BAABLgAECn8hAAMSAAcJoR5hBQAFAgASAAYJJx5hBQAFAgAQAAUJwBm7BAB0AQAAAA==.Mercilezz:BAAALgADCgUJCAAAAA==.',
Mi='Midwestfel:BAABLgAECn8OAAIUAAYJQwjtWwCUAAAUAAYJQwjtWwCUAAAAAA==.Mikeoxhard:BAAALgAECgQJBAAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAABLgAECn8ZAAIHAAgJEBGLDwCSAQAHAAgJEBGLDwCSAQAAAA==.Mionn:BAAALgAECgUJDgAAAA==.',
Ml='Mlleena:BAABLgAECn8jAAMXAAcJUgzBOgBDAQAXAAcJIAzBOgBDAQAYAAMJxAr8GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8hAAMcAAgJyBqYBgBkAgAcAAcJqR2YBgBkAgAXAAUJeha8MgBhAQAAAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBgAAAA==.Mooncake:BAAALgAECgYJCwAAAA==.Moosiah:BAABLgAECn8iAAILAAgJ1B8IBwApAgALAAgJ1B8IBwApAgAAAA==.Mortenerra:BAAALgAECgQJBwAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfiré:BAAALgAECgYJEAAAAA==.Motoko:BAABLgAECn8fAAQZAAgJqA5PNABQAQAZAAcJUQ1PNABQAQATAAYJMBIBNgAXAQAaAAYJJAc6JADlAAAAAA==.',
Mu='Muatamuata:BAAALgAECgEJAQAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECggJEAAEAAAAAA==.',
My='Myhealmissed:BAAALgADCggJCAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECgYJCwAEAAAAAA==.Møøfi:BAAALgAECgEJAQAAAA==.',
Na='Nachoshamy:BAAALgADCgEJAQAAAA==.Nameless:BAABLgAECn8hAAMNAAcJNxiIBQDUAQANAAYJzhqIBQDUAQAMAAcJ5RAeOQCEAQAAAA==.Narc:BAAALgAECgUJEQAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAABLgAECn8dAAMFAAkJdBe+EACzAgAFAAkJPhe+EACzAgABAAMJzRcOhADcAAAAAA==.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn8ZAAIBAAcJ2xDbWwBUAQABAAcJ2xDbWwBUAQAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgADCgcJDQAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECggJEAAEAAAAAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8FAAMYAAIJxgySAgBiAAAXAAIJEAIiQACDAAAYAAEJFxmSAgBiAAAuAAQKfyMABBwACQltHAcPANoBABwABwmuFgcPANoBABcABwmvF+RjAJ8BABgABQmEFY4FACoBAAAA.',
No='Noova:BAABLgAECn8kAAIMAAcJrB+RUABGAgAMAAcJrB+RUABGAgAAAA==.Norooux:BAAALgADCggJCwAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJBgAGAE0GAA==.',
Ob='Obliverat:BAAALgAECgcJDAAAAA==.',
Ol='Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgQJBwAAAA==.',
Or='Orcaneblast:BAACLgAFFH8HAAIMAAQJ6AxWIgBKAQAMAAQJ6AxWIgBKAQAuAAQKfx0AAgwACAlEGQweAPcBAAwACAlEGQweAPcBAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDQAAAA==.Ornn:BAABLgAECn8aAAIgAAcJbCK+CwBRAgAgAAcJbCK+CwBRAgAAAA==.',
Pa='Palmtalon:BAAALgAECgMJBAAAAA==.Pandaminium:BAAALgADCgYJBgAAAA==.Pandarias:BAAALgAECgMJAwAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Partypizza:BAABLgAECn8oAAIOAAgJNR8JBwA3AgAOAAgJNR8JBwA3AgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAQJCAAKAHQjAA==.Penne:BAAALgAECgYJBwABLgAFFAMJCQAMADojAA==.Permanence:BAABLgAECn8UAAIUAAYJARZ1bQBbAQAUAAYJARZ1bQBbAQAAAA==.',
Pi='Picobuffu:BAAALgAECgYJBgABLgAECggJIAAUAMobAA==.Picodedge:BAABLgAECn8gAAIUAAgJyhvuDwDyAQAUAAgJyhvuDwDyAQAAAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn8eAAMMAAgJLBRLMQCfAQAMAAgJLBRLMQCfAQAlAAIJQQxTBgBwAAAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgMJAwAAAA==.Porthos:BAAALgADCgYJCgAAAA==.Poõpsikens:BAAALgADCgEJAQAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAIXAAcJtRmZOABKAQAXAAcJtRmZOABKAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAgAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8JAAIJAAQJHB6iCwCCAQAJAAQJHB6iCwCCAQAuAAQKfyUAAgkABwntI20eANEBAAkABwntI20eANEBAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qt='Qtpi:BAABLgAECn8XAAIUAAgJPxo7HQCEAQAUAAgJPxo7HQCEAQAAAA==.',
Qu='Quica:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAIMAAgJURmEQwBuAgAMAAgJURmEQwBuAgABLgAFFAYJFQAMAAIbAA==.Raketh:BAAALgAECgYJDAAAAA==.Rallek:BAABLgAECn8oAAIVAAgJ1hccDwDuAQAVAAgJ1hccDwDuAQAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECgcJGgAgAGwiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAAALgAECggJEgAAAA==.Rehabherox:BAAALgADCgcJBwAAAA==.Rektek:BAABLgAECn8YAAIfAAgJ4RRRNADZAQAfAAgJ4RRRNADZAQAAAA==.Rektnasty:BAAALgAECgEJAQAAAA==.Remeras:BAABLgAECn8YAAIRAAgJvw8AXgDJAQARAAgJvw8AXgDJAQAAAA==.Resilientaid:BAAALgAECgYJDAAAAA==.Restolyfe:BAAALgAECgUJCgAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8jAAQTAAgJ3g4DGgA0AQATAAgJ3g4DGgA0AQAaAAIJygshdwBlAAAZAAEJsAR2hQArAAAAAA==.Rilzi:BAAALgAECgYJBgAAAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAAALgAECgUJDAABLgAECgkJIwAiAA8ZAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Roley:BAAALgADCgcJCgAAAA==.Roots:BAAALgAECgUJDwAAAA==.Rosalie:BAAALgADCgUJBQAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgADCgYJBgAAAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAgAAAA==.Ruuf:BAABLgAECn8iAAIOAAgJ+gpYHgAlAQAOAAgJ+gpYHgAlAQAAAA==.',
Ry='Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgAECgEJAQAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgMJAwAAAA==.',
Sc='Scalylusion:BAAALgAECgcJEwAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.',
Se='Seanconery:BAAALgAECgYJCgAAAA==.Senica:BAABLgAECn8iAAIIAAgJvR08EgBPAgAIAAgJvR08EgBPAgAAAA==.Seriphina:BAAALgADCgkJFQAAAA==.',
Sh='Shabbarankz:BAABLgAECn8dAAIjAAgJ9hUOCwASAgAjAAgJ9hUOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAAALgAECggJEwAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgQJBAABLgAECggJEAAEAAAAAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAAALgAECgcJDwAAAA==.Sheepwreck:BAAALgADCgQJBQAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgADCgQJBAAAAA==.Shotbot:BAAALgADCgYJBgABLgAECgkJIQARAModAA==.Shra:BAABLgAECn8gAAIhAAkJnBCACABVAQAhAAkJnBCACABVAQAAAA==.Shrafu:BAAALgAECgYJCAAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECgYJDAAEAAAAAA==.Sindracosa:BAABLgAECn8XAAMQAAYJsgqLIAApAQAQAAYJsgqLIAApAQASAAYJiQUULwD5AAABLgAECgkJGgAdALoPAA==.Sindradori:BAAALgADCgMJAwABLgAECggJGgAHABsaAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinsidious:BAAALgADCgcJFAAAAA==.Sizzle:BAAALgADCgcJCAABLgAECggJDwAEAAAAAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAAALgAFFAEJAQAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAAALgAECgYJDgAAAA==.Smokindots:BAABLgAECn8bAAIXAAcJqhiWbgCDAQAXAAcJqhiWbgCDAQABLgAECggJLAACADghAA==.Smokinmyrrh:BAAALgAECgMJAwABLgAECggJLAACADghAA==.Smokinpsalm:BAAALgAECgcJEwABLgAECggJLAACADghAA==.Smokintotem:BAABLgAECn8sAAICAAgJOCEgCQBYAgACAAgJOCEgCQBYAgAAAA==.',
Sn='Sneakingbush:BAABLgAECn8XAAMiAAcJfg2gLACaAQAiAAcJvgygLACaAQAmAAQJ8grcEwDCAAAAAA==.Snowberry:BAAALgAECgEJAQAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8FAAIOAAMJogeEEQDfAAAOAAMJogeEEQDfAAAuAAQKfxgAAw4ACAlLEUcmAN8BAA4ACAlLEUcmAN8BAAMAAwmxBWckAJIAAAEuAAUUBQkTAAwAKBQA.Spaghett:BAABLgAFFH8JAAIMAAMJOiOzKQAnAQAMAAMJOiOzKQAnAQAAAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAABLgAECn8lAAMZAAgJuyQDAgDQAgAZAAgJjCQDAgDQAgAaAAUJjyBzEQCDAQAAAA==.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAAALgAECgYJBgAAAA==.',
Su='Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgMJBQABLgAECgcJIQANADcYAA==.Sundowning:BAAALgAECggJEQAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sw='Swiftdragon:BAAALgAECggJEAAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECggJFQAYAMYfAA==.',
Sy='Sylerwinassa:BAAALgAECgQJCAAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Synjo:BAABLgAECn8hAAInAAgJ7RnkAQAIAgAnAAgJ7RnkAQAIAgAAAA==.',
Ta='Taapfer:BAABLgAECn8bAAIWAAgJqR4nAwCtAgAWAAgJqR4nAwCtAgAAAA==.Tackyh:BAAALgAECgUJCQAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwAAAA==.Tassidar:BAAALgAECgUJCgAAAA==.Taxii:BAABLgAECn8lAAMfAAgJkSE/BQBoAgAfAAgJ9iA/BQBoAgAoAAUJwBpkCwBLAQAAAA==.',
Te='Teapots:BAABLgAECn8ZAAIDAAgJ2CKNBADkAQADAAgJ2CKNBADkAQAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAABLgAECn8bAAMHAAkJ3hOvGwAAAgAHAAkJ3hOvGwAAAgAIAAEJlAkufgA1AAAAAA==.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgYJFgAVABIhAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAABLgAECn8hAAIRAAkJyh0aEQAHAwARAAkJyh0aEQAHAwAAAA==.Thefifth:BAACLgAFFH8UAAISAAYJyg/tAgDiAQASAAYJyg/tAgDiAQAuAAQKfyAABBIACQkGGncOAFACABIACQkGGncOAFACABAAAgmzEtgyAH8AAA8AAQm7DvtFADoAAAAA.Theralendris:BAABLgAECn8XAAIWAAgJhBGDEQA5AQAWAAgJhBGDEQA5AQAAAA==.Thickarm:BAAALgAECgYJDAABLgAECgYJEwAEAAAAAA==.Thyrn:BAAALgADCgYJBgABLgAECgcJGgAgAGwiAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8gAAIJAAgJdxt7FAAWAgAJAAgJdxt7FAAWAgAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAQJBwAMAOgMAA==.Treebeard:BAAALgADCgYJCwAAAA==.Treshan:BAAALgADCgkJCQAAAA==.Tri:BAAALgAECgcJEwAAAA==.',
Ts='Tsavo:BAABLgAECn8gAAMOAAgJexBCFgBjAQAOAAgJexBCFgBjAQACAAEJBAWloAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgQJBAAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgADCgcJBwAAAA==.Turgrok:BAAALgAECgYJCgAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQAEAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAABLgAECn8bAAMMAAkJGR+7DgBRAwAMAAkJGR+7DgBRAwANAAEJdCLqFgBjAAAAAA==.',
Un='Uniförm:BAABLgAECn8bAAMiAAgJzhCPDwB1AQAiAAgJzhCPDwB1AQAmAAEJUQS9FgAqAAAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAABLgAECn8jAAIgAAgJjCRABQDrAgAgAAgJjCRABQDrAgAAAA==.Vainhellsing:BAAALgAECgYJBgABLgAECggJJAAOAH8QAA==.Vampage:BAAALgAECggJCgAAAA==.Vandeadly:BAAALgAECgYJDwAAAA==.Vannethir:BAAALgAECgQJBAABLgAFFAQJBwAMAOgMAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8VAAMBAAgJExzgEQAFAgABAAcJtBzgEQAFAgAFAAcJfxVCMQCqAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8VAAIBAAgJaQ9pMgDmAQABAAgJaQ9pMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAECggJIwAgAIwkAA==.Verycurious:BAAALgAECgQJBwABLgAECgYJEwAEAAAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgMJAwABLgAECgkJIwAiAA8ZAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgMJAwABLgAECgUJCwAEAAAAAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
['Vá']='Váder:BAAALgAECgYJAgAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAECggJLQAcAIkhAA==.Wernov:BAAALgAECgYJEgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8JAAIhAAQJlR9bAQB4AQAhAAQJlR9bAQB4AQAuAAQKfyIAAiEACAmnHUMEALMCACEACAmnHUMEALMCAAAA.',
Wi='Wichan:BAABLgAECn8oAAIhAAgJSx9EAwAUAgAhAAgJSx9EAwAUAgAAAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Windrúnner:BAAALgAECgQJBAAAAA==.Wiziviji:BAAALgAECggJEQAAAA==.',
Wo='Woodrow:BAABLgAECn8XAAIVAAgJjR5vDgD2AQAVAAgJjR5vDgD2AQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8aAAMGAAcJ8hnJCAAJAgAGAAcJ8hnJCAAJAgAHAAMJvxHWSgCvAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
Xa='Xanddlock:BAAALgADCgQJBAAAAA==.',
Xc='Xclusive:BAAALgADCggJDwAAAA==.',
Xf='Xfire:BAABLgAECn8WAAQSAAcJEhPdIAB2AQASAAYJSBTdIAB2AQAPAAQJOw/dRQDFAAAQAAEJcAv/EgA8AAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECgYJCwAEAAAAAA==.',
Xr='Xray:BAAALgADCgYJBgAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAAALgAECgYJCQAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.',
Yi='Yisoonshin:BAAALgAECgYJEwAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJGgAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAAALgADCggJCAAAAA==.',
Za='Zaka:BAAALgADCgMJBAAAAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECggJCgAAAA==.Zanosuke:BAAALgAECgcJCgAAAA==.Zanzer:BAAALgADCgQJBAABLgADCgUJBQAEAAAAAA==.Zaria:BAABLgAECn8YAAIXAAcJZRP8QgAoAQAXAAcJZRP8QgAoAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zerica:BAAALgADCgEJAQAAAA==.Zerika:BAABLgAECn8eAAIIAAgJrCKyAQAMAwAIAAgJrCKyAQAMAwAAAA==.',
Zi='Zigzwag:BAAALgADCgkJDAAAAA==.Zionna:BAAALgADCgYJAQABLgAECggJEAAEAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8WAAIDAAgJEhU+BwCLAQADAAgJEhU+BwCLAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8VAAIfAAcJnxlhEgClAQAfAAcJnxlhEgClAQABLgAECgcJFwAiAH4NAA==.',
Zy='Zydis:BAAALgAECgMJAwAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAECgQJEwAEAAAAAA==.',
['És']='Éstéla:BAABLgAECn8gAAIBAAkJdRU6HwClAQABAAkJdRU6HwClAQAAAA==.',
['ßr']='ßrïñcey:BAAALgAECgEJAgAAAA==.',
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

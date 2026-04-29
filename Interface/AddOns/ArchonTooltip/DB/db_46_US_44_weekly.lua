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

local lookup = {'Hunter-BeastMastery','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Arcane','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Evoker-Preservation','DemonHunter-Devourer','Shaman-Restoration','DemonHunter-Vengeance','Paladin-Holy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Hunter-Survival','Mage-Fire','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAAALgAECgMJAwAAAA==.',
Ac='Activision:BAAALgAECgMJAwAAAA==.',
Ad='Ademisk:BAAALgADCgYJDAAAAA==.Adventureux:BAABLgAECn8XAAIBAAgJMBZHMwDiAQABAAgJMBZHMwDiAQAAAA==.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAAALgAECgYJDgAAAA==.',
Ai='Aiblul:BAAALgAECgQJBwAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgYJCQABLgAECggJFwACAMchAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgADAAAAAA==.Alestrike:BAAALgAECgUJCQAAAA==.Aliroarx:BAAALgADCggJDgAAAA==.Almosteasy:BAABLgAECn8XAAIEAAgJLCO1BwAfAwAEAAgJLCO1BwAfAwAAAA==.Alunadoom:BAAALgADCgcJBwAAAA==.Alunagryn:BAABLgAECn8iAAQFAAgJZRmYEwASAgAFAAgJxxWYEwASAgAGAAcJMhdVHwDdAQAHAAUJ6RhkNQBoAQAAAA==.Alvera:BAABLgAECn8gAAIIAAgJhhrGOABTAgAIAAgJhhrGOABTAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgAAAA==.',
An='Angerforge:BAAALgAECgcJBwAAAA==.',
Ar='Arielordril:BAAALgAECgQJBAAAAA==.Arm:BAABLgAECn8aAAMJAAgJKBc3NQDTAQAJAAcJWxY3NQDTAQAKAAgJ1A8zKwCoAQAAAA==.Armee:BAABLgAECn8aAAIHAAgJtBnhDwBnAgAHAAgJtBnhDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgEJAgAAAA==.',
As='Asmilwelme:BAAALgAECgQJBAAAAA==.Astrael:BAABLgAECn8VAAMLAAgJlQ2BKAAsAQALAAgJMAyBKAAsAQAMAAUJ2hClDgDZAAAAAA==.Aszayla:BAAALgAECgUJBQAAAA==.',
Av='Avoidme:BAAALgAECgMJBAAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwADAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8kAAINAAgJfxB5KgDCAQANAAgJfxB5KgDCAQAAAA==.Azóg:BAABLgAECn8cAAIIAAcJlxcAFAByAQAIAAcJlxcAFAByAQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAECgIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8TAAMOAAYJEiMWAQC9AQAOAAYJEiMWAQC9AQAPAAQJ7x4SAgBwAQAuAAQKfx4AAw4ACQk3Jv0BAJkDAA4ACQk3Jv0BAJkDAA8ACAkaJCIEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAAALgADCgcJBwABLgAECggJIgAGAIwRAA==.',
Be='Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgUJCAABLgAECgYJDwADAAAAAA==.Beastoker:BAAALgADCgYJCAAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAYJEAALAFYhAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgADCgcJIgAAAA==.Beeto:BAACLgAFFH8FAAIQAAIJzhH7IQCpAAAQAAIJzhH7IQCpAAAuAAQKfxkAAhAACAlaHT4kAJcCABAACAlaHT4kAJcCAAAA.Bekdrop:BAAALgAECgYJDgABLgAFFAYJEAALAFYhAA==.Benlian:BAAALgAECgEJAgAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8NAAILAAUJ2ArbIABBAQALAAUJ2ArbIABBAQAuAAQKfyEAAwsACAkgIbMgAPECAAsACAkgIbMgAPECAAwAAQmmFUseADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.',
Bl='Blackadam:BAAALgAECgQJBAAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8JAAILAAQJIQ17LwD4AAALAAQJIQ17LwD4AAAuAAQKfyoAAgsACQm/Hi0bAAoDAAsACQm/Hi0bAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobá:BAAALgAFFAIJAgABLgAFFAYJFwARABkaAA==.Boof:BAABLgAECn8aAAIGAAgJGxpoGwACAgAGAAgJGxpoGwACAgAAAA==.Boogieboppin:BAAALgAFFAEJAQAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgADCgUJBQAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bronxor:BAAALgAECgEJAQAAAA==.Bruski:BAAALgAECgMJAwAAAA==.',
Bu='Buhtol:BAAALgADCgQJBAABLgAECggJJgALAB0hAA==.Bure:BAAALgAECgYJEQAAAA==.Buzzbuzz:BAAALgAECgYJDAAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAIRAAYJGRoYAgAKAgARAAYJGRoYAgAKAgAuAAQKfx8AAxEACQllHzMEABMDABEACQllHzMEABMDAA8AAwn5IuYiABMBAAAA.',
['Bõ']='Bõba:BAAALgAFFAIJAwABLgAFFAYJFwARABkaAA==.',
Ca='Caelin:BAABLgAECn8WAAISAAYJwAxiewA1AQASAAYJwAxiewA1AQAAAA==.Caishana:BAABLgAECn8iAAITAAkJxh0RCgDYAgATAAkJxh0RCgDYAgAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAAALgAECgQJBAAAAA==.',
Ce='Cecil:BAAALgAECgcJEgAAAA==.Celeb:BAABLgAECn8bAAIUAAgJViMJAQAyAwAUAAgJViMJAQAyAwAAAA==.Celebtard:BAAALgAECgEJAQABLgAECggJGwAUAFYjAA==.Cervrakabra:BAAALgADCgQJBQAAAA==.',
Ch='Chaddingus:BAAALgAECgcJCQAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgEJAgAAAA==.Chilltea:BAABLgAECn8YAAILAAcJUiHFCwD0AQALAAcJUiHFCwD0AQAAAA==.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAAALgAECgYJDgAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAAALgAECgYJEQAAAA==.',
Co='Coheedkil:BAAALgADCgEJAQABLgADCgIJAgADAAAAAA==.Coldbreeze:BAAALgAECgMJAwABLgAECgYJCwADAAAAAA==.Collateral:BAAALgADCgUJBQAAAA==.Compaktdisc:BAAALgAECggJDwAAAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgYJDAADAAAAAA==.Cowpox:BAAALgAECgYJEQAAAA==.',
Cp='Cpr:BAAALgAECgQJBQAAAA==.',
Cr='Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECgUJCgAAAA==.Critzilla:BAAALgAECgIJAgAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn8bAAIVAAcJ4h/BEgB8AgAVAAcJ4h/BEgB8AgAAAA==.Cry:BAAALgAECgEJAQAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8FAAIWAAIJAiVPCQDMAAAWAAIJAiVPCQDMAAAuAAQKfx0AAhYACAmoHjELANkCABYACAmoHjELANkCAAAA.',
Cy='Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8ZAAILAAgJyBGJewDaAQALAAgJyBGJewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8YAAIUAAgJDhbXCQDOAQAUAAgJDhbXCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECgQJBAAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAAALgAECgYJCgABLgAECgUJDAADAAAAAA==.Dargong:BAAALgADCgIJAgAAAA==.Darkrunes:BAABLgAECn8eAAISAAgJvhY1PgD7AQASAAgJvhY1PgD7AQAAAA==.Darrkness:BAAALgAECgQJBgAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgQJBAAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgEJAQABLgAECggJHQAXAGETAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAAALgAECgcJEwAAAA==.Deristus:BAABLgAECn8aAAIYAAgJnBR/VQDHAQAYAAgJnBR/VQDHAQAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAADAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgADAAAAAA==.Devi:BAAALgAECgIJAwAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dirtmonkgirt:BAAALgAECgYJEgAAAA==.Dirtysham:BAABLgAECn8cAAINAAgJcBjFIQABAgANAAgJcBjFIQABAgAAAA==.Discipline:BAAALgAECgYJBgAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAAALgAECgYJDwAAAA==.Dotgunner:BAABLgAECn8XAAIYAAcJXRtGQAANAgAYAAcJXRtGQAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgcJDwADAAAAAA==.Downbad:BAACLgAFFH8FAAIYAAMJdQcXJwDhAAAYAAMJdQcXJwDhAAAuAAQKfx8AAxgACAl+H14XAMgCABgACAl+H14XAMgCABkABAm8Cwo1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgcJDQADAAAAAA==.Drahseer:BAAALgADCgcJCwAAAA==.Drakulya:BAAALgAECgYJCgAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAAALgAECgYJDwAAAA==.Driftèr:BAAALgAECgYJBgAAAA==.Drizzle:BAABLgAECn8dAAISAAgJkyTCAgCDAgASAAgJkyTCAgCDAgAAAA==.Drkdestro:BAABLgAECn8iAAQYAAkJ+SC8DwD8AgAYAAkJ+SC8DwD8AgAaAAEJAADCHwBzAAAZAAEJyxy6XwBPAAAAAA==.Druidic:BAACLgAFFH8FAAIJAAMJqSPjBAA1AQAJAAMJqSPjBAA1AQAuAAQKfyQAAgkACAlMJbwDAFYDAAkACAlMJbwDAFYDAAAA.Druvinci:BAAALgADCgQJBAAAAA==.Drü:BAAALgAECggJEQAAAA==.',
Du='Dunk:BAAALgADCgIJAgAAAA==.Dusan:BAABLgAECn8cAAMHAAgJnxR5IADeAQAHAAgJyhN5IADeAQAFAAYJmgu7CQA6AQAAAA==.Duskthesixth:BAAALgAECgQJBAAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ear:BAAALgADCgcJBwABLgAFFAMJAwADAAAAAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8aAAMTAAYJyxnXCgCQAQATAAYJyxnXCgCQAQACAAQJ/wK9IgCqAAAAAA==.',
Ed='Edonsian:BAABLgAECn8eAAMbAAgJohhAHgBdAgAbAAgJPBdAHgBdAgAcAAIJXRknOgB6AAAAAA==.',
Ee='Eepy:BAABLgAECn8aAAMdAAkJpxGqHQDKAQAdAAkJpxGqHQDKAQAeAAUJrBHXDAACAQAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgADCgEJAQABLgAECgcJEgADAAAAAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAAALgAECgcJEgAAAA==.Emorlyn:BAABLgAECn8WAAMBAAgJSBCvNADcAQABAAgJSBCvNADcAQAEAAYJpgIUZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAABLgAECn8cAAILAAgJWBwaTQBPAgALAAgJWBwaTQBPAgAAAA==.',
Er='Eriksangus:BAAALgAECgYJDwAAAA==.',
Es='Estelá:BAAALgADCgkJCQAAAA==.',
Et='Etikwa:BAAALgAECgYJDgAAAA==.',
Ev='Evilguard:BAABLgAECn8dAAIXAAgJYRMRFwCmAQAXAAgJYRMRFwCmAQAAAA==.Evilpatty:BAAALgADCgYJBgAAAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECgMJAwAAAA==.',
Fa='Fariebubbles:BAAALgAECgQJBAAAAA==.Fastandis:BAAALgADCgYJDAAAAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMYAAcJgRmuaQCQAQAYAAYJghquaQCQAQAZAAMJXhfxOQDMAAAAAA==.Fearóshima:BAAALgAECgcJDwAAAA==.Felene:BAAALgAECggJDgAAAA==.Fenixstraza:BAACLgAFFH8GAAMOAAMJqxteFwCnAAAOAAIJkBleFwCnAAARAAIJ4hYHFQBpAAAuAAQKfyMAAxEACAlLGyMNAGQCABEABwkVHCMNAGQCAA4ACAmwElwfAMcBAAAA.Fervis:BAAALgAECgQJCAABLgAECgYJBgADAAAAAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJDAAAAA==.Firitako:BAAALgAECgQJCAAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECggJHgAbAI8gAA==.Flipper:BAABLgAECn8XAAMVAAgJPBasIgAJAgAVAAgJPBasIgAJAgAQAAIJawFIRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAAALgAECggJDwAAAA==.Frankiejr:BAAALgADCgkJGgABLgAECgYJDAADAAAAAA==.Frapsity:BAAALgAECgYJCwAAAA==.Frostpoptart:BAABLgAECn8UAAITAAYJHR8JIgATAgATAAYJHR8JIgATAgAAAA==.Frozenblade:BAAALgADCgkJCQAAAA==.',
Fu='Fupah:BAAALgADCgEJAQAAAA==.Furball:BAAALgADCgUJBAABLgAFFAQJCQAYAO4PAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAAALgAFFAEJAQAAAA==.Galadrielle:BAAALgADCgYJCwAAAA==.Gandelf:BAAALgADCgEJAQABLgAECgYJEQADAAAAAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8cAAIfAAgJfgmQFwD+AAAfAAgJfgmQFwD+AAAAAA==.',
Ge='Genngar:BAABLgAECn8cAAISAAgJJhifDgCVAQASAAgJJhifDgCVAQAAAA==.',
Gi='Gigbutt:BAABLgAECn8jAAIgAAkJDxnfAwDVAQAgAAkJDxnfAwDVAQAAAA==.Giggléz:BAAALgAECgYJCAAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAILAAgJIBs7RABrAgALAAgJIBs7RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgADCgkJFQAAAA==.Goatedfury:BAAALgAECgcJEgAAAA==.Gorgrot:BAAALgADCgEJAQABLgAECggJJAAKAIgjAA==.Gorshot:BAAALgAECgcJBwAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgADCgcJBwABLgAECggJIQAZAPMeAA==.Griitz:BAAALgAECgEJAQAAAA==.Grimfate:BAAALgAECgYJDAAAAA==.Grimmjob:BAABLgAECn8aAAMhAAcJuyGjAQDxAQAhAAcJuyGjAQDxAQAfAAYJkQ8JFwAFAQAAAA==.Griswold:BAAALgAECgQJBwAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8VAAMLAAgJmBvfQAB2AgALAAgJmBvfQAB2AgAMAAEJ0ibRFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJFQALAJgbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAAALgAFFAIJAwAAAA==.Guzmo:BAAALgADCgYJBAAAAA==.',
Gy='Gyat:BAAALgAECgMJAwAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8XAAIGAAkJwQhuCgBJAQAGAAkJwQhuCgBJAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8cAAMYAAgJ2h43CwDDAQAYAAgJ2h43CwDDAQAZAAMJeh4QMQD1AAAAAA==.',
Hi='Hitechtotem:BAAALgAECgEJAQAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAAALgAECggJDgAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgQJBAABLgAECgYJDAADAAAAAA==.Hoofrat:BAAALgAECgcJBQAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgQJBwADAAAAAA==.Huxley:BAAALgADCgEJAQAAAA==.Huñted:BAAALgAECggJEwAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgQJBwADAAAAAA==.',
Ic='Icuris:BAAALgAECgMJAwAAAA==.',
Id='Idomagic:BAAALgADCgYJBgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8YAAMaAAcJxRWRCADAAQAaAAYJ1BiRCADAAQAYAAEJeQZLFAE6AAAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAAALgAECgcJEQAAAA==.Ilithiya:BAAALgAECgEJAQAAAA==.Illidrac:BAAALgAECgcJDQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJEgADAAAAAA==.',
Im='Imangry:BAAALgAECgQJBAAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inpherno:BAAALgADCgEJAQAAAA==.',
Is='Isaidnoice:BAAALgAECgcJEAAAAA==.Ishton:BAAALgAECgYJBwAAAA==.Istompgnomes:BAAALgADCggJEwAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgYJEAAAAA==.',
Ja='Jacked:BAABLgAECn8VAAMYAAgJQxwzTwDaAQAYAAYJQBszTwDaAQAaAAMJMR/DEAAhAQAAAA==.',
Je='Jecka:BAABLgAECn8bAAMHAAgJTA2rQgAuAQAHAAYJxAurQgAuAQAGAAcJfw17DQAcAQAAAA==.Jecthyr:BAAALgAECgEJAQABLgAECggJGwAHAEwNAA==.Jefryepsteen:BAAALgADCgUJBQAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAAALgAECgYJEAAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAAALgAECgYJEAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jo='Jordana:BAAALgAECgYJEQAAAA==.Jove:BAAALgAECgYJBwAAAA==.',
Js='Jsdruid:BAAALgAECgQJCAAAAA==.',
Ju='Jug:BAABLgAECn8cAAIiAAgJqBuqBADJAgAiAAgJqBuqBADJAgAAAA==.',
Ka='Kainöa:BAAALgAECgQJBgABLgAECgYJDwADAAAAAA==.Kakum:BAAALgADCgkJEwAAAA==.Kaldrogo:BAAALgAECgQJBQAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAQJDgAdAA8fAA==.Kalnuggets:BAAALgADCgcJBgAAAA==.Kalrathen:BAABLgAECn8XAAIHAAcJaRG2LgCJAQAHAAcJaRG2LgCJAQAAAA==.Kaniku:BAAALgAECgEJAQABLgAECggJGgALAGEZAA==.Karsh:BAABLgAECn8VAAIbAAcJfQdREwAHAQAbAAcJfQdREwAHAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAAALgAECgYJCgAAAA==.',
Ke='Kered:BAAALgADCgUJBQAAAA==.Keuaakepo:BAABLgAECn8hAAMBAAcJ1SF6EgCjAgABAAcJ1SF6EgCjAgAiAAEJUQM1MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8ZAAIBAAYJUhmuTQCAAQABAAYJUhmuTQCAAQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgADCgkJFwAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAAALgAECgYJCQAAAA==.',
Ko='Koreanbrewbq:BAAALgAECgEJAQAAAA==.Kothbaark:BAABLgAECn8bAAMhAAgJLhUUAgDPAQAhAAgJ1hQUAgDPAQAfAAIJ0AwbKwBMAAAAAA==.',
Kp='Kpa:BAAALgADCgEJAQAAAA==.',
Kr='Krethar:BAAALgAECgEJAQABLgAECggJEgADAAAAAA==.Krypt:BAABLgAECn8YAAIcAAcJvw84GwByAQAcAAcJvw84GwByAQAAAA==.Krìzl:BAAALgAECgcJEwABLgAFFAQJDQAIAN8XAA==.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgMJAwAAAA==.',
Ky='Kymira:BAAALgAECgMJAwAAAA==.',
['Kâ']='Kârnage:BAAALgAECgEJAQAAAA==.',
La='Lace:BAABLgAECn8hAAIZAAgJ8x5eAwC9AgAZAAgJ8x5eAwC9AgAAAA==.Lanzen:BAAALgADCgUJBQAAAA==.Lanzier:BAAALgADCgIJAgABLgADCgUJBQADAAAAAA==.Larrfena:BAAALgAECgYJCwAAAA==.',
Le='Legit:BAAALgAECgEJAQAAAA==.Lementz:BAACLgAFFH8KAAICAAUJVBqrAADIAQACAAUJVBqrAADIAQAuAAQKfyoAAgIACQnuJWEAAMQDAAIACQnuJWEAAMQDAAAA.Lexiiees:BAAALgAECgYJDgAAAA==.',
Li='Liadres:BAAALgAECgQJBQAAAA==.Lilboat:BAAALgAECgQJCQAAAA==.Lillia:BAABLgAECn8cAAIYAAgJTRF9FABsAQAYAAgJTRF9FABsAQAAAA==.',
Lo='Lovetobussy:BAAALgAECgUJCAAAAA==.',
Lu='Lucarrio:BAAALgAECgEJAQAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn8nAAMYAAkJWhpsDAC0AQAYAAkJDxpsDAC0AQAZAAUJHhmFGwBxAQAAAA==.Lumpia:BAAALgAECggJEgAAAA==.',
['Lè']='Lèah:BAAALgADCggJCAAAAA==.',
Ma='Macaroní:BAAALgAECgYJBgABLgAFFAMJBgALAHAZAA==.Magicchoc:BAAALgAECgYJBwABLgAECggJHQAXAGETAA==.Maktah:BAAALgAECgcJEgAAAA==.Mandrakor:BAAALgADCgEJAQAAAA==.Marshboa:BAAALgAECgUJCgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mclovinit:BAACLgAFFH8QAAILAAYJViGXAgBeAgALAAYJViGXAgBeAgAuAAQKfzcAAgsACQmIJnoAAAIEAAsACQmIJnoAAAIEAAAA.Mcmagic:BAABLgAECn8gAAILAAYJSCPiSQBZAgALAAYJSCPiSQBZAgAAAA==.Mcpally:BAABLgAECn8gAAIQAAgJkh96GQDQAgAQAAgJkh96GQDQAgAAAA==.',
Me='Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8aAAIJAAgJsyS7CAADAwAJAAgJsyS7CAADAwAAAA==.Mensu:BAAALgAECgYJBgAAAA==.Mentos:BAABLgAECn8aAAMRAAYJgR2AFQDzAQARAAYJgR2AFQDzAQAPAAQJ/Bk2AwA0AQAAAA==.Mercilezz:BAAALgADCgUJBQAAAA==.',
Mi='Midwestfel:BAAALgAECgYJDwAAAA==.Mikeoxhard:BAAALgADCggJCAAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAAALgAECggJEQAAAA==.Mionn:BAAALgAECgUJDgAAAA==.',
Ml='Mlleena:BAABLgAECn8cAAMYAAcJFgtJGQBJAQAYAAcJ5ApJGQBJAQAaAAMJxAr+GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8cAAMZAAgJyBqWBgBkAgAZAAcJqR2WBgBkAgAYAAUJahIeuADoAAAAAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBgAAAA==.Mooncake:BAAALgAECgUJBQAAAA==.Moosiah:BAABLgAECn8cAAIKAAcJfBw9GABHAgAKAAcJfBw9GABHAgAAAA==.Mortenerra:BAAALgAECgMJBgAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfiré:BAAALgAECgYJEAAAAA==.Motoko:BAABLgAECn8dAAQeAAgJlwtONABQAQAeAAcJvQlONABQAQAdAAYJMBJLNgAYAQAWAAYJJAdqEADtAAAAAA==.',
Mu='Murdrmittens:BAAALgADCgYJAQABLgAECggJDwADAAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECgYJCwADAAAAAA==.Møøfi:BAAALgAECgEJAQAAAA==.',
Na='Nachoshamy:BAAALgADCgEJAQAAAA==.Nameless:BAABLgAECn8YAAMMAAcJNxiGBQDUAQAMAAYJzhqGBQDUAQALAAYJ9QeBTwBxAAAAAA==.Narc:BAAALgAECgQJCAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAABLgAECn8dAAMEAAkJdBe9EACzAgAEAAkJPhe9EACzAgABAAMJzRcJhADcAAAAAA==.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAAALgAECgYJEgAAAA==.Newnu:BAAALgADCgcJBwABLgAECggJGwAUAFYjAA==.',
Ni='Nibbah:BAAALgAECgUJCAAAAA==.Nicadema:BAAALgADCgcJDQAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECggJDwADAAAAAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAABLgAECn8hAAQZAAgJ8BwLDwDaAQAZAAcJrhYLDwDaAQAYAAYJfRbkYwCfAQAaAAUJhBWiAgArAQAAAA==.',
No='Noova:BAABLgAECn8gAAILAAcJrB+XUABGAgALAAcJrB+XUABGAgAAAA==.Norooux:BAAALgADCggJCgAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgEJBQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAECggJIgAFAGUZAA==.',
Ob='Obliverat:BAAALgAECgcJDAAAAA==.',
Ol='Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgQJBAAAAA==.',
Or='Orcaneblast:BAABLgAECn8aAAILAAgJYRnpCQALAgALAAgJYRnpCQALAgAAAA==.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDQAAAA==.Ornn:BAABLgAECn8aAAIcAAcJbCJCAwDCAQAcAAcJbCJCAwDCAQAAAA==.',
Pa='Pandaminium:BAAALgADCgYJBgAAAA==.Pandarias:BAAALgAECgMJAwAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Partypizza:BAABLgAECn8hAAINAAgJNRxgEQCaAgANAAgJNRxgEQCaAgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAMJBQAJAKkjAA==.Penne:BAAALgAECgYJBwABLgAFFAMJBgALAHAZAA==.Permanence:BAABLgAECn8UAAISAAYJARZtbQBbAQASAAYJARZtbQBbAQAAAA==.',
Pi='Picodedge:BAABLgAECn8bAAISAAYJZx7pFABWAQASAAYJZx7pFABWAQAAAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn8aAAMLAAgJthKfHQBiAQALAAgJthKfHQBiAQAjAAEJOwdUBAA4AAAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Porthos:BAAALgADCgQJCAAAAA==.Poõpsikens:BAAALgADCgEJAQAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8XAAIYAAYJyhyXYwCfAQAYAAYJyhyXYwCfAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgEJAQAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8FAAIIAAIJTx4oEwDDAAAIAAIJTx4oEwDDAAAuAAQKfx8AAggABwnkIPkyAGsCAAgABwnkIPkyAGsCAAAA.',
Qe='Qelsie:BAAALgAECgYJCgAAAA==.',
Qt='Qtpi:BAAALgAECgcJDwAAAA==.',
Qu='Quica:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAILAAgJURmEQwBuAgALAAgJURmEQwBuAgABLgAFFAUJDwALAOgaAA==.Raketh:BAAALgAECgYJBgAAAA==.Rallek:BAABLgAECn8hAAIVAAgJnBNfJwDvAQAVAAgJnBNfJwDvAQAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECgcJGgAcAGwiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAAALgAECggJEQAAAA==.Rektek:BAABLgAECn8XAAIbAAgJ4RRTNADZAQAbAAgJ4RRTNADZAQAAAA==.Remeras:BAABLgAECn8WAAIQAAgJvw8FXgDJAQAQAAgJvw8FXgDJAQAAAA==.Resilientaid:BAAALgAECgQJBgAAAA==.Restolyfe:BAAALgAECgUJCQAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8cAAQdAAgJlQ6OLABVAQAdAAcJAg+OLABVAQAWAAIJygsqdwBlAAAeAAEJsARxhQArAAAAAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAAALgAECgUJDAABLgAECgkJIwAgAA8ZAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Roley:BAAALgADCgcJCgAAAA==.Roots:BAAALgAECgUJCwAAAA==.Rosalie:BAAALgADCgUJBQAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgADCgYJBgAAAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAgAAAA==.Ruuf:BAABLgAECn8bAAINAAcJGgxPOQBqAQANAAcJGgxPOQBqAQAAAA==.',
Ry='Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgADCgEJAQAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgADCgkJEAAAAA==.',
Sc='Scalylusion:BAAALgAECgcJEgAAAA==.Scrubbers:BAAALgADCgUJBQAAAA==.',
Se='Seanconery:BAAALgAECgQJBwAAAA==.Senica:BAABLgAECn8XAAIHAAcJWB02EgBPAgAHAAcJWB02EgBPAgAAAA==.Seriphina:BAAALgADCgkJFQAAAA==.',
Sh='Shabbarankz:BAABLgAECn8bAAIhAAcJQhkOCwASAgAhAAcJQhkOCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAAALgAECgYJCwAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgADCgIJAgABLgAECggJDwADAAAAAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAAALgAECgcJDwAAAA==.Sheepwreck:BAAALgADCgQJBQAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgADCgMJAwAAAA==.Shotbot:BAAALgADCgYJBgABLgAECgkJIQAQAModAA==.Shra:BAABLgAECn8gAAIfAAkJnBDjAgCLAQAfAAkJnBDjAgCLAQAAAA==.Shrafu:BAAALgAECgYJCAAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECgYJBgADAAAAAA==.Sindracosa:BAABLgAECn8XAAMPAAYJsgqDIAApAQAPAAYJsgqDIAApAQARAAYJiQUULwD5AAABLgAECgcJDQADAAAAAA==.Sindradori:BAAALgADCgMJAwABLgAECggJGgAGABsaAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinsidious:BAAALgADCgUJCAAAAA==.Sizzle:BAAALgADCgMJAgABLgAECgYJDAADAAAAAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAAALgAFFAEJAQAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAAALgAECgYJBwAAAA==.Smokindots:BAABLgAECn8aAAIYAAYJIhyNbgCDAQAYAAYJIhyNbgCDAQABLgAECggJHwATAH4gAA==.Smokinmyrrh:BAAALgAECgEJAQABLgAECggJHwATAH4gAA==.Smokinpsalm:BAAALgAECgcJEwABLgAECggJHwATAH4gAA==.Smokintotem:BAABLgAECn8fAAITAAgJfiCsDwCbAgATAAgJfiCsDwCbAgAAAA==.',
Sn='Sneakingbush:BAABLgAECn8XAAMgAAcJfg2hLACaAQAgAAcJvgyhLACaAQAkAAQJ8grcEwDCAAAAAA==.Snowberry:BAAALgAECgEJAQAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAEBLgAECn8YAAMNAAgJSxFEJgDfAQANAAgJSxFEJgDfAQACAAMJsQVqJACSAAABLgAFFAUJDQALANgKAA==.Spaghett:BAABLgAFFH8GAAILAAMJcBkREAAPAQALAAMJcBkREAAPAQAAAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAABLgAECn8bAAIeAAYJjSWbAgAKAgAeAAYJjSWbAgAKAgAAAA==.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgQJBAAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAAALgAECgYJBgAAAA==.',
Su='Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgMJAwABLgAECgcJGAAMADcYAA==.Sundowning:BAAALgAECggJDgAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sw='Swiftdragon:BAAALgAECggJDwAAAA==.Swizzle:BAAALgADCgEJAQAAAA==.',
Sy='Sylerwinassa:BAAALgAECgQJCAAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Synjo:BAABLgAECn8bAAIlAAYJrx6eBAAPAgAlAAYJrx6eBAAPAgAAAA==.',
Ta='Taapfer:BAABLgAECn8aAAIUAAgJqR4nAwCtAgAUAAgJqR4nAwCtAgAAAA==.Tackyh:BAAALgAECgMJBAAAAA==.Taku:BAAALgADCgQJBAAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwAAAA==.Taxii:BAABLgAECn8eAAIbAAgJjyDaAQBYAgAbAAgJjyDaAQBYAgAAAA==.',
Te='Teapots:BAABLgAECn8XAAICAAgJxyEzAgDcAQACAAgJxyEzAgDcAQAAAA==.Teggatz:BAAALgAECgEJAgAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAABLgAECn8YAAMGAAgJfRSqGwAAAgAGAAgJfRSqGwAAAgAHAAEJlAkhfgA1AAAAAA==.Telor:BAAALgAECgEJAQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECgYJEQADAAAAAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAABLgAECn8hAAIQAAkJyh0TEQAHAwAQAAkJyh0TEQAHAwAAAA==.Thefifth:BAACLgAFFH8TAAIRAAYJyg/pAgDiAQARAAYJyg/pAgDiAQAuAAQKfx8AAxEACQkGGnMOAFACABEACQkGGnMOAFACAA8AAgmzEtEyAH8AAAAA.Theralendris:BAABLgAECn8VAAIUAAcJixGBEQA5AQAUAAcJixGBEQA5AQAAAA==.Thickarm:BAAALgAECgYJDAABLgAECgYJDwADAAAAAA==.Thyrn:BAAALgADCgYJBgABLgAECgcJGgAcAGwiAA==.',
Ti='Timmythicc:BAAALgAECgEJAgAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8YAAIIAAcJbRkkEQCLAQAIAAcJbRkkEQCLAQAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgYJDAAAAA==.Trazenoth:BAAALgADCgYJBgABLgAECggJGgALAGEZAA==.Tri:BAAALgAECgYJDAAAAA==.',
Ts='Tsavo:BAABLgAECn8dAAMNAAcJdA+VNgB5AQANAAcJdA+VNgB5AQATAAEJBAWjoAAwAAAAAA==.',
Tu='Tuggle:BAAALgADCgcJFAAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turgrok:BAAALgAECgQJBQAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQADAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAABLgAECn8bAAMLAAkJGR+1DgBRAwALAAkJGR+1DgBRAwAMAAEJdCLqFgBjAAAAAA==.',
Un='Uniförm:BAABLgAECn8VAAIgAAgJzhB2JQDNAQAgAAgJzhB2JQDNAQAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAABLgAECn8YAAIcAAcJPyU9BQDrAgAcAAcJPyU9BQDrAgAAAA==.Vainhellsing:BAAALgADCggJCAABLgAECggJJAANAH8QAA==.Vampage:BAAALgAECggJCQAAAA==.Vandeadly:BAAALgAECgYJDwABLgAECggJFQAIAKMfAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAAALgAECggJDgAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8UAAIBAAgJrQ5xMgDmAQABAAgJrQ5xMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAECgcJGAAcAD8lAA==.Verycurious:BAAALgAECgQJBAABLgAECgYJDwADAAAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgADCgEJAQABLgAECgkJIwAgAA8ZAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnfang:BAAALgAECgUJBQAAAA==.Vinnidari:BAAALgAECgMJAwABLgAECgUJBQADAAAAAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAECggJIQAZAPMeAA==.Wernov:BAAALgAECgYJDAAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8FAAIfAAIJhhzfAQC8AAAfAAIJhhzfAQC8AAAuAAQKfyIAAh8ACAmnHUUEALMCAB8ACAmnHUUEALMCAAAA.',
Wi='Wichan:BAABLgAECn8hAAIfAAgJyh1qBQCGAgAfAAgJyh1qBQCGAgAAAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Wiziviji:BAAALgAECggJDAAAAA==.',
Wo='Woodrow:BAAALgAECgYJEwAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAAALgAECgcJEwAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
Xa='Xanddlock:BAAALgADCgQJBAAAAA==.',
Xc='Xclusive:BAAALgADCggJDwAAAA==.',
Xf='Xfire:BAABLgAECn8WAAQRAAcJEhPXIAB2AQARAAYJSBTXIAB2AQAOAAQJOw/YRQDFAAAPAAEJcAs+CQBCAAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECgYJCwADAAAAAA==.',
Xr='Xray:BAAALgADCgYJBgAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAAALgAECgMJAwAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.',
Yi='Yisoonshin:BAAALgAECgYJDwAAAA==.',
Yo='Yo:BAAALgAECgUJDAAAAA==.Yolotli:BAAALgADCggJFAAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAAALgADCggJCAAAAA==.',
Za='Zaka:BAAALgADCgMJBAAAAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECggJCgAAAA==.Zanosuke:BAAALgAECgcJCgAAAA==.Zanzer:BAAALgADCgQJBAABLgADCgUJBQADAAAAAA==.Zaria:BAABLgAECn8YAAIYAAcJZROjHAA0AQAYAAcJZROjHAA0AQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zerica:BAAALgADCgEJAQAAAA==.Zerika:BAABLgAECn8WAAIHAAcJfRs/BwCYAQAHAAcJfRs/BwCYAQAAAA==.',
Zi='Zigzwag:BAAALgADCgkJDAAAAA==.Zionna:BAAALgADCgYJAQABLgAECggJDwADAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8VAAICAAgJEhUrDgDaAQACAAgJEhUrDgDaAQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8VAAIbAAcJnxnDLAABAgAbAAcJnxnDLAABAgABLgAECgcJFwAgAH4NAA==.',
Zy='Zydis:BAAALgAECgMJAwAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQADAAAAAA==.',
['És']='Éstéla:BAABLgAECn8YAAIBAAgJJReTKwAGAgABAAgJJReTKwAGAgAAAA==.',
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

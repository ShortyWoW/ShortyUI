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

local lookup = {'DemonHunter-Vengeance','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Unknown-Unknown','Hunter-Marksmanship','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Arcane','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Evoker-Preservation','Monk-Mistweaver','DemonHunter-Devourer','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','DemonHunter-Havoc','Warrior-Fury','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Hunter-Survival','Paladin-Protection','Mage-Fire','Rogue-Assassination','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abbaton:BAAALgAECgYJBgAAAA==.Abishai:BAAALgAECgcJEAAAAA==.Abrakadaver:BAAALgAECgEJAQABLgAECggJHAABAKkeAA==.',
Ac='Activision:BAAALgAECgUJCAAAAA==.',
Ad='Ademisk:BAAALgADCgYJDAAAAA==.Adventureux:BAABLgAECn8gAAICAAgJ7xviGAAKAgACAAgJ7xviGAAKAgAAAA==.',
Ag='Agax:BAAALgADCgEJAQAAAA==.',
Ah='Ahriana:BAABLgAECn8bAAIDAAcJNhfBJgCHAQADAAcJNhfBJgCHAQAAAA==.',
Ai='Aiblul:BAAALgAECgQJCAAAAA==.',
Al='Alandin:BAAALgADCgUJBQAAAA==.Alaris:BAAALgAECgMJBAAAAA==.Alastar:BAAALgAECgcJEgABLgAECggJGQAEANgiAA==.Albinee:BAAALgADCgYJBgABLgAECgUJDgAFAAAAAA==.Aliroarx:BAAALgADCggJFAAAAA==.Almosteasy:BAABLgAECn8XAAIGAAgJLCPBBwAhAwAGAAgJLCPBBwAhAwAAAA==.Alunadoom:BAAALgADCgcJCQAAAA==.Alunagryn:BAACLgAFFH8GAAIHAAQJTQZ1FwDsAAAHAAQJTQZ1FwDsAAAuAAQKfyQABAcACAllGZgTABICAAcACAnHFZgTABICAAgABwkyF1gfAN0BAAkABQnpGG01AGgBAAAA.Alvera:BAABLgAECn8hAAIKAAgJuh3KOABTAgAKAAgJuh3KOABTAgAAAA==.',
Am='Ambellìna:BAAALgADCgIJAgABLgAECgUJBQAFAAAAAA==.',
An='Anduin:BAAALgAECgYJCQAAAA==.Angerforge:BAAALgAECgcJBwAAAA==.Angrydk:BAAALgAECgQJBAAAAA==.',
Ar='Arielordril:BAAALgAECgYJDQAAAA==.Arm:BAABLgAECn8pAAMLAAgJKBc4NQDTAQALAAcJWxY4NQDTAQAMAAgJpBQNEQDEAQAAAA==.Armee:BAABLgAECn8bAAIJAAgJqRrkDwBnAgAJAAgJqRrkDwBnAgAAAA==.Arthasreborn:BAAALgADCgUJBQAAAA==.Artèmís:BAAALgAECgYJCgAAAA==.',
As='Asmilwelme:BAAALgAECgQJCAAAAA==.Astrael:BAABLgAECn8eAAMNAAgJBRH/PACxAQANAAgJSBD/PACxAQAOAAUJ2hClDgDZAAAAAA==.Aszayla:BAAALgAECgYJDAAAAA==.Aszea:BAAALgAECgYJCgAAAA==.',
Av='Avoidme:BAAALgAECgMJBgAAAA==.',
Az='Azendeth:BAAALgADCgUJBQABLgADCgYJBwAFAAAAAA==.Azrâel:BAAALgAECgQJBAAAAA==.Azrælz:BAABLgAECn8oAAIPAAgJ6xF7KgDCAQAPAAgJ6xF7KgDCAQAAAA==.Azóg:BAABLgAECn8rAAIKAAgJ3RnLIgD6AQAKAAgJ3RnLIgD6AQAAAA==.',
Ba='Bailmorek:BAAALgAECgYJCQAAAA==.Balsin:BAAALgAFFAIJAgAAAA==.Balthromaw:BAAALgADCgEJAQAAAA==.Bangvoker:BAACLgAFFH8ZAAMQAAgJEB/FAwAOAgAQAAcJLCLFAwAOAgARAAUJTxoVAgBwAQAuAAQKfx4AAxAACQk8JvsBAJkDABAACQk8JvsBAJkDABEACAkaJCUEAM4CAAAA.Bannags:BAAALgADCgMJAwAAAA==.Bannix:BAAALgADCgYJBgAAAA==.Barlaf:BAAALgADCgcJBwABLgAECggJIgAIAIwRAA==.',
Be='Beardsells:BAAALgADCgcJEwAAAA==.Bearhug:BAAALgADCgEJAQAAAA==.Bearier:BAAALgAECgEJAQAAAA==.Beastallday:BAAALgAECgcJDgAAAA==.Beastiegrljd:BAAALgADCgYJBgAAAA==.Beastoker:BAAALgAECgUJBgAAAA==.Beckonez:BAAALgADCgMJAwABLgAFFAcJEwANAJIfAA==.Beeps:BAAALgAFFAEJAgAAAA==.Beeski:BAAALgAECgQJBQAAAA==.Beeto:BAACLgAFFH8LAAISAAQJsxFWGQBGAQASAAQJsxFWGQBGAQAuAAQKfxsAAhIACAlaHTckAJcCABIACAlaHTckAJcCAAAA.Bekdrop:BAAALgAFFAEJAQABLgAFFAcJEwANAJIfAA==.Benlian:BAEALgAECgUJDAAAAA==.',
Bi='Bigbush:BAAALgAECgMJAwAAAA==.Bigolbkt:BAECLgAFFH8UAAINAAYJJxGOEQChAQANAAYJJxGOEQChAQAuAAQKfyMAAw0ACAkgIbMgAPECAA0ACAkgIbMgAPECAA4AAQmmFUseADUAAAAA.Bisect:BAAALgADCgQJBwAAAA==.Bishtease:BAAALgADCgQJBAAAAA==.',
Bl='Blackadam:BAAALgAECgQJBQAAAA==.Blunsty:BAAALgAECgEJAQAAAA==.Blâze:BAACLgAFFH8PAAINAAQJfxSIKgBUAQANAAQJfxSIKgBUAQAuAAQKfyoAAg0ACQljHjEbAAoDAA0ACQljHjEbAAoDAAAA.',
Bm='Bm:BAAALgAECgQJBgAAAA==.',
Bo='Bobtheknight:BAAALgAECgMJAwAAAA==.Bobá:BAABLgAFFH8QAAILAAgJ8xuFAADMAgALAAgJ8xuFAADMAgABLgAFFAYJFwATABkaAA==.Boof:BAABLgAECn8cAAIIAAkJpxloGwACAgAIAAkJpxloGwACAgAAAA==.Boogieboppin:BAAALgAFFAIJAgAAAA==.Boregut:BAAALgAECgYJBgAAAA==.Bozo:BAAALgAECgYJBgAAAA==.',
Br='Brewdock:BAAALgAECgEJAgAAAA==.Brickncheese:BAAALgAECgEJAQAAAA==.Bricknibba:BAAALgAECgEJAgAAAA==.Bronxor:BAAALgAECgYJDwAAAA==.Bruski:BAAALgAECgMJAwAAAA==.',
Bu='Buhtol:BAAALgADCgQJBQABLgAFFAMJBQANAG4ZAA==.Bullma:BAAALgAECgcJBQAAAA==.Bure:BAABLgAECn8YAAISAAgJUSKSQwAZAgASAAgJUSKSQwAZAgAAAA==.Buzzbuzz:BAAALgAECggJDwAAAA==.',
['Bó']='Bóba:BAACLgAFFH8XAAITAAYJGRobAgAKAgATAAYJGRobAgAKAgAuAAQKfx8AAxMACQllHzUEABMDABMACQllHzUEABMDABEAAwn5IugiABMBAAAA.',
['Bõ']='Bõba:BAABLgAFFH8FAAIUAAMJaiCLEAAaAQAUAAMJaiCLEAAaAQABLgAFFAYJFwATABkaAA==.',
['Bö']='Böba:BAAALgAECgYJBgABLgAFFAYJFwATABkaAA==.',
Ca='Caelin:BAABLgAECn8gAAIVAAcJhA86RgAmAQAVAAcJhA86RgAmAQAAAA==.Caishana:BAABLgAECn8rAAIDAAkJaiJEAgBAAwADAAkJaiJEAgBAAwAAAA==.Carnitine:BAAALgAECgYJBgAAAA==.Cassandra:BAAALgAECgcJEQAAAA==.',
Ce='Cecil:BAABLgAECn8iAAIWAAkJjwOGKABIAQAWAAkJjwOGKABIAQAAAA==.Celeb:BAABLgAECn8jAAIBAAgJzCMJAQAyAwABAAgJzCMJAQAyAwAAAA==.Celebrity:BAAALgAECgUJCgABLgAECggJIwABAMwjAA==.Celebtard:BAAALgAECgIJAgABLgAECggJIwABAMwjAA==.Cervrakabra:BAAALgAECgEJAQAAAA==.',
Ch='Chaddingus:BAAALgAECgkJDQAAAA==.Chaosdottz:BAAALgADCgIJAgAAAA==.Chikaboom:BAAALgAECgIJBAAAAA==.Chilltea:BAABLgAECn8hAAINAAgJ+CPdDQCuAgANAAgJ+CPdDQCuAgAAAA==.Chumley:BAAALgADCgEJAQAAAA==.Chumlëy:BAABLgAECn8aAAMXAAYJ3gh7cQDnAAAXAAYJ3gh7cQDnAAAYAAIJuwEJKQBNAAAAAA==.',
Ci='Cigarette:BAAALgADCgYJCAAAAA==.',
Cl='Clique:BAABLgAECn8eAAIWAAgJVB9BBQDWAgAWAAgJVB9BBQDWAgAAAA==.',
Co='Coheedkil:BAAALgAECgUJBQAAAA==.Coldbreeze:BAAALgAECgMJAwABLgAECgYJEgAFAAAAAA==.Collateral:BAAALgAECgcJBwAAAA==.Compaktdisc:BAAALgAECggJEQAAAA==.Conartist:BAAALgAECgYJBwABLgAECggJKQAZALskAA==.Contrition:BAAALgAECgYJDQAAAA==.Converge:BAAALgAECgEJAQAAAA==.Costaz:BAAALgADCgMJAwABLgAECgcJEwAFAAAAAA==.Cowpox:BAABLgAECn8ZAAILAAgJmg41LgBqAQALAAgJmg41LgBqAQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Creatrix:BAAALgAECgEJAQABLgAECggJKQAZALskAA==.Crikey:BAAALgADCgMJAwAAAA==.Crimmi:BAAALgAECggJEwAAAA==.Critzilla:BAAALgAECgYJCAAAAA==.Cromak:BAAALgAECgMJAwAAAA==.Crungle:BAABLgAECn8tAAIWAAgJ7CDGBgCuAgAWAAgJ7CDGBgCuAgAAAA==.Cry:BAAALgAECgMJBAAAAA==.',
Cu='Cuddy:BAAALgADCgkJCgAAAA==.Cumamonk:BAACLgAFFH8KAAIaAAQJiB3aCgBgAQAaAAQJiB3aCgBgAQAuAAQKfx8AAhoACQnJHzALANkCABoACQnJHzALANkCAAAA.',
Cy='Cybuster:BAAALgAECgcJCQABLgAFFAQJBwANAFAOAA==.Cyndle:BAAALgADCgkJCQABLgAECgkJDQAFAAAAAA==.Cyre:BAAALgADCgEJAQAAAA==.',
Da='Daddythicc:BAABLgAECn8aAAINAAgJ9RF7ewDaAQANAAgJ9RF7ewDaAQAAAA==.Daeladila:BAAALgADCgYJCQAAAA==.Daemond:BAABLgAECn8bAAIBAAkJDBXVCQDOAQABAAkJDBXVCQDOAQAAAA==.Dair:BAAALgADCgMJAwAAAA==.Dairy:BAAALgAECgYJCQAAAA==.Danalei:BAAALgAECgIJAgAAAA==.Dankdatank:BAAALgAECgEJAQAAAA==.Dankpal:BAABLgAECn8XAAISAAcJfgcBZwAfAQASAAcJfgcBZwAfAQABLgAECgUJEwAFAAAAAA==.Dargong:BAAALgAECgEJAQAAAA==.Darkrunes:BAABLgAECn8dAAIVAAcJLhouPgD7AQAVAAcJLhouPgD7AQAAAA==.Darrkness:BAAALgAFFAEJAgAAAA==.Darthvikingw:BAAALgADCgcJDAAAAA==.Dasboots:BAAALgADCgEJAQAAAA==.Davidwallace:BAAALgADCgMJAwAAAA==.',
De='Deadgirljd:BAAALgAECgYJCAAAAA==.Demensemen:BAAALgAECgQJBwAAAA==.Deminnissa:BAAALgADCgMJAwAAAA==.Demonchocc:BAAALgAECgUJBgABLgAECggJHQAbAGQTAA==.Deputy:BAAALgAECgEJAQAAAA==.Deran:BAABLgAECn8ZAAISAAcJBCIJFwBDAgASAAcJBCIJFwBDAgAAAA==.Deristus:BAABLgAECn8jAAIXAAkJRBVjHwD0AQAXAAkJRBVjHwD0AQAAAA==.Deroth:BAAALgAECgEJAQAAAA==.Desolt:BAAALgADCgUJCAAAAA==.Desoltes:BAAALgADCgIJAQABLgADCgUJCAAFAAAAAA==.Detritus:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Devi:BAAALgAECgIJAwAAAA==.',
Di='Digamma:BAAALgADCgUJBQAAAA==.Dirtmonkgirt:BAABLgAECn8YAAIZAAgJqRKVFACKAQAZAAgJqRKVFACKAQAAAA==.Dirtysham:BAABLgAECn8cAAIPAAgJcBjFIQABAgAPAAgJcBjFIQABAgAAAA==.Discipline:BAABLgAECn8VAAIIAAgJDROFEQC/AQAIAAgJDROFEQC/AQAAAA==.Divinia:BAAALgADCgYJBgAAAA==.',
Do='Doob:BAABLgAECn8WAAMKAAYJnxJTkQBdAQAKAAYJnxJTkQBdAQAbAAYJ8gazIgCwAAAAAA==.Dotdotgoose:BAAALgAECgQJAwABLgAECggJEQAFAAAAAA==.Dotgunner:BAABLgAECn8XAAIXAAcJXRs5QAANAgAXAAcJXRs5QAANAgAAAA==.Dotvader:BAAALgADCgIJAQABLgAECgkJHgAVAPgcAA==.Downbad:BAACLgAFFH8FAAIXAAMJdQchJwDhAAAXAAMJdQchJwDhAAAuAAQKfx8AAxcACAl+H1sXAMgCABcACAl+H1sXAMgCABwABAm8Cwc1AOIAAAAA.',
Dr='Dracara:BAAALgAECgEJAQABLgAECgkJGgAdALsPAA==.Drahseer:BAAALgAECgIJAgAAAA==.Drakulya:BAAALgAECggJEAAAAA==.Dranzier:BAAALgAECgEJAQAAAA==.Dreadz:BAABLgAECn8WAAMVAAYJIQuPXgDjAAAVAAYJTQqPXgDjAAAdAAMJMghoWgB5AAAAAA==.Drewish:BAAALgADCgQJBAAAAA==.Driftèr:BAAALgAECgcJEgAAAA==.Drizzle:BAABLgAECn8fAAIVAAgJTiVjFQARAgAVAAgJTiVjFQARAgAAAA==.Drkdestro:BAABLgAECn8pAAQXAAkJBSK9DwD8AgAXAAkJAyG9DwD8AgAYAAUJVSGRBACUAQAcAAEJyxy/XwBPAAAAAA==.Druidic:BAACLgAFFH8MAAILAAQJ+CM+CQCmAQALAAQJ+CM+CQCmAQAuAAQKfy4AAgsACQnZJLoDAFYDAAsACQnZJLoDAFYDAAAA.Drunkhorn:BAAALgADCgMJAwAAAA==.Druvinci:BAAALgADCgQJBAAAAA==.Drü:BAABLgAECn8UAAIMAAkJDxLcLQCVAQAMAAkJDxLcLQCVAQAAAA==.',
Du='Duneshade:BAAALgADCgUJBQAAAA==.Dunk:BAAALgADCgIJAgAAAA==.Dusan:BAABLgAECn8mAAMJAAgJCh55BgCSAgAJAAgJCh55BgCSAgAHAAYJmwvKIAAlAQAAAA==.Duskthesixth:BAAALgAECgQJBgAAAA==.',
['Dï']='Dïvinity:BAAALgAECgQJBgAAAA==.',
Ea='Ear:BAAALgADCgcJBwABLgAFFAMJCQAaAGkRAA==.Eatmybrain:BAAALgADCgEJAQAAAA==.',
Ec='Echeyaket:BAABLgAECn8iAAMDAAgJ+xT/HQDCAQADAAgJ+xT/HQDCAQAEAAQJ/wK7IgCqAAAAAA==.',
Ed='Edonsian:BAABLgAECn8tAAMeAAkJxxo9CQBUAgAeAAkJYho9CQBUAgAfAAIJXRkmOgB6AAAAAA==.',
Ee='Eepy:BAABLgAECn8aAAMUAAkJpxHoHQDGAQAUAAkJpxHoHQDGAQAZAAUJrBEAJwD2AAAAAA==.',
El='Elaitharia:BAAALgAECgYJDQAAAA==.Elelusion:BAAALgADCgEJAQABLgAECgcJFgAQAFsaAA==.Elpapii:BAAALgADCgEJAQAAAA==.Elçhapo:BAAALgAFFAEJAgAAAA==.',
Em='Emmasculate:BAABLgAECn8UAAIfAAgJjxTRCwCpAQAfAAgJjxTRCwCpAQAAAA==.Emorlyn:BAABLgAECn8XAAMCAAkJwg+qNADcAQACAAkJwg+qNADcAQAGAAYJpgIYZQCrAAAAAA==.Emorí:BAAALgADCgMJAwAAAA==.',
En='Endrai:BAAALgAECgEJAQAAAA==.Enmerkar:BAAALgADCgYJBgAAAA==.Enoka:BAABLgAECn8eAAINAAgJOxwNTQBPAgANAAgJOxwNTQBPAgAAAA==.',
Er='Eriksangus:BAABLgAECn8XAAIeAAgJAAhaKAA2AQAeAAgJAAhaKAA2AQAAAA==.',
Es='Estelá:BAAALgAECgUJBQAAAA==.',
Et='Etikwa:BAABLgAECn8WAAILAAgJBw5/QQANAQALAAgJBw5/QQANAQAAAA==.',
Ev='Evilguard:BAABLgAECn8dAAIbAAgJZBMQFwCmAQAbAAgJZBMQFwCmAQAAAA==.Evilpatty:BAAALgADCggJDQAAAA==.',
Ex='Excessive:BAAALgAECgEJAQAAAA==.',
Ey='Eyecandy:BAAALgADCgIJAgAAAA==.Eyvania:BAAALgAECgYJCQAAAA==.',
Fa='Falador:BAAALgAECgIJAgAAAA==.Fariebubbles:BAAALgAECgYJCwAAAA==.Fastandis:BAAALgAECgEJAQAAAA==.Fatale:BAAALgAFFAMJBAAAAA==.',
Fe='Fearspamyou:BAABLgAECn8UAAMXAAcJgRm1aQCQAQAXAAYJghq1aQCQAQAcAAMJXhfvOQDMAAAAAA==.Fearóshima:BAAALgAECgcJEQAAAA==.Feign:BAAALgAECgEJAQAAAA==.Felene:BAAALgAECggJEAAAAA==.Fenixstraza:BAACLgAFFH8OAAQQAAQJNxbKHgD0AAAQAAMJ1hnKHgD0AAATAAMJThd7EwDVAAARAAEJVwsnCABMAAAuAAQKfyUAAxMACQnVGSUNAGQCABMABwkVHCUNAGQCABAACQnyFWIfAMcBAAAA.Fervis:BAAALgAECgQJCAABLgAECgcJEwAFAAAAAA==.',
Fi='Fiddler:BAAALgAECgUJBQAAAA==.Fiftypiece:BAAALgAECgYJDAAAAA==.Firitako:BAAALgAECgYJDwAAAA==.',
Fl='Flattax:BAAALgAECgQJBwABLgAECgkJLQAeADYlAA==.Flipper:BAABLgAECn8ZAAMWAAkJLBSqIgAJAgAWAAkJLBSqIgAJAgASAAIJawFqRgExAAAAAA==.',
Fo='Footlocker:BAAALgAECgMJBAAAAA==.',
Fr='Frailey:BAABLgAECn8WAAMYAAgJxh+RAwBfAgAYAAgJxh+RAwBfAgAXAAIJBBTfEwE6AAAAAA==.Frankiejr:BAAALgAECgQJBgABLgAECgcJGQASAKglAA==.Frapsity:BAABLgAECn8VAAIDAAYJyRiPHwC2AQADAAYJyRiPHwC2AQAAAA==.Frostamper:BAAALgAECgQJCQAAAA==.Frostpoptart:BAABLgAECn8jAAIDAAgJbxoAIgATAgADAAgJbxoAIgATAgAAAA==.Frozenblade:BAAALgAECgYJBgAAAA==.',
Fu='Fupah:BAAALgAECgEJAQAAAA==.Furball:BAAALgAECgMJAwABLgAFFAQJDQAXAGgSAA==.Fuzzysforms:BAAALgADCgEJAQAAAA==.',
['Fá']='Fárháná:BAAALgADCgIJAgAAAA==.',
Ga='Gagabooney:BAACLgAFFH8HAAIaAAMJISC6FAAeAQAaAAMJISC6FAAeAQAuAAQKfxgAAhoACQl1HaYJACsCABoACQl1HaYJACsCAAAA.Galadrielle:BAAALgAECgUJBwAAAA==.Gandelf:BAAALgADCgEJAQABLgAECggJGQACANIXAA==.Gankulots:BAAALgADCgUJBQAAAA==.Garabashi:BAAALgADCgcJBwAAAA==.Garret:BAAALgADCgQJBAABLgAECgcJIAAVAIQPAA==.Gavacho:BAAALgAECgIJAwAAAA==.Gazze:BAABLgAECn8mAAIgAAgJ1gsbEQD2AAAgAAgJ1gsbEQD2AAAAAA==.',
Ge='Gearatron:BAAALgAECgIJAwAAAA==.Genngar:BAABLgAECn8hAAIVAAgJjBhyHADeAQAVAAgJjBhyHADeAQAAAA==.',
Gh='Ghostfate:BAAALgAECgEJAQAAAA==.',
Gi='Gigbutt:BAABLgAECn8xAAIhAAkJ5xvPBQBbAgAhAAkJ5xvPBQBbAgAAAA==.Giggléz:BAAALgAECgYJCQAAAA==.Gillis:BAAALgADCgIJAgAAAA==.',
Gl='Glow:BAABLgAECn8cAAINAAgJIBs1RABrAgANAAgJIBs1RABrAgAAAA==.',
Gn='Gnrx:BAAALgAECggJDwAAAA==.',
Go='Goam:BAAALgADCgkJFQAAAA==.Goatedfury:BAACLgAFFH8HAAISAAQJEwJ0MgDtAAASAAQJEwJ0MgDtAAAuAAQKfxQAAhIACAnUFQExALgBABIACAnUFQExALgBAAAA.Goblegoble:BAAALgADCgcJCAAAAA==.Gorgrot:BAAALgAECgMJAwABLgAFFAMJCgAMAI8ZAA==.Gorshot:BAABLgAECn8YAAICAAkJwgzBHwDdAQACAAkJwgzBHwDdAQAAAA==.',
Gr='Grandrios:BAAALgAECgEJAQAAAA==.Greatvibes:BAAALgAECgQJBAABLgAECgcJDgAFAAAAAA==.Gretzzky:BAAALgAFFAEJAQAAAA==.Grid:BAAALgADCgcJBwABLgAECggJLgAcAIkhAA==.Griitz:BAAALgAECgEJAQAAAA==.Grimfate:BAAALgAECgYJDQAAAA==.Grimmjob:BAABLgAECn8nAAMiAAgJhyDhAQCtAgAiAAgJhyDhAQCtAgAgAAYJkQ8FFwAFAQAAAA==.Griswold:BAAALgAECgYJDgAAAA==.',
Gu='Guap:BAAALgADCgEJAQAAAA==.Guess:BAABLgAECn8dAAMNAAgJqRvbQAB2AgANAAgJqRvbQAB2AgAOAAEJ0ibRFwBaAAAAAA==.Guestophson:BAAALgAECgEJAQABLgAECggJHQANAKkbAA==.Gulag:BAAALgADCgEJAQAAAA==.Gurkzy:BAAALgAECgIJAgAAAA==.Gurtdk:BAABLgAFFH8JAAMbAAQJHBSgEgDNAAAbAAMJLg+gEgDNAAAKAAIJmh4FaQCoAAAAAA==.Guzmo:BAAALgADCgYJBgAAAA==.',
Gy='Gyat:BAAALgAECgQJBQAAAA==.',
Ha='Hambones:BAAALgAECgMJAwAAAA==.Hammerguard:BAAALgAECgMJAwAAAA==.Handofjuice:BAAALgAECgkJCQAAAA==.Hanyuu:BAABLgAECn8dAAIIAAkJLQqsFgCKAQAIAAkJLQqsFgCKAQAAAA==.Hatefulßîtsh:BAAALgADCgUJBQAAAA==.Hauntter:BAAALgADCgQJBAAAAA==.',
He='Heisca:BAAALgADCgcJBwAAAA==.Hellbound:BAABLgAECn8mAAMXAAkJ3yH1CQCqAgAXAAkJ3yH1CQCqAgAcAAMJeh4NMQD1AAAAAA==.',
Hi='Hitechtotem:BAAALgAECgIJAgAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holyfeetpics:BAAALgAECgQJBAAAAA==.Holyshirts:BAABLgAECn8XAAISAAkJvRdgJADyAQASAAkJvRdgJADyAQAAAA==.Holywhooper:BAAALgADCgcJBwAAAA==.Honk:BAAALgAECgYJCQABLgAECggJDwAFAAAAAA==.Hoofrat:BAAALgAECgcJBQAAAA==.',
Hp='Hpal:BAAALgAECgQJBAAAAA==.',
Hu='Hughmungus:BAAALgAECgEJAQABLgAECgYJCgAFAAAAAA==.Huxley:BAAALgADCgEJAQAAAA==.Huñted:BAABLgAECn8aAAMjAAgJAhM7DgDEAQAjAAgJmQ87DgDEAQACAAYJIw7SYQBCAQAAAA==.',
['Hí']='Hítman:BAAALgADCgMJAwAAAA==.',
Ia='Iannà:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.',
Ic='Icuris:BAAALgAECgMJAwAAAA==.',
Id='Idistroya:BAAALgAECgcJDQABLgAECgkJPQACADAjAA==.Idomagic:BAAALgADCgYJBgAAAA==.',
Ih='Ihaveproblem:BAABLgAECn8gAAMYAAgJVxWPCADAAQAYAAYJ1BiPCADAAQAXAAgJ+xAEMACjAQAAAA==.Ihaverogue:BAAALgADCgcJDgAAAA==.',
Il='Iliketmoist:BAABLgAECn8XAAIJAAgJkxVTGwACAgAJAAgJkxVTGwACAgAAAA==.Ilithiya:BAAALgAECggJEAAAAA==.Illidrac:BAABLgAECn8aAAIdAAkJuw9WEgBlAQAdAAkJuw9WEgBlAQAAAA==.Illoosion:BAAALgADCgYJBgABLgAECgcJFgAQAFsaAA==.',
Im='Imangry:BAAALgAECgYJEQAAAA==.Imyals:BAAALgADCgUJBQAAAA==.',
In='Inconsolable:BAAALgADCgMJAwAAAA==.Inpherno:BAAALgADCgEJAQAAAA==.',
Is='Isaidnoice:BAABLgAECn8bAAMcAAgJ7ROfFgCVAQAcAAcJGROfFgCVAQAXAAcJXw9GQQBlAQAAAA==.Ishton:BAAALgAECggJCgAAAA==.Istompgnomes:BAAALgAECggJCAAAAA==.',
It='Itstoomuch:BAAALgAECgUJCQAAAA==.',
Iz='Izzaltank:BAAALgAECgcJEwAAAA==.',
Ja='Jacked:BAABLgAECn8WAAMXAAgJQxwvTwDaAQAXAAYJQBsvTwDaAQAYAAMJMR/CEAAhAQAAAA==.Jasøn:BAAALgAECggJDAAAAA==.',
Je='Jecka:BAABLgAECn8lAAMIAAkJXRV+FwCDAQAIAAcJ/BF+FwCDAQAJAAgJWAy2QgAuAQAAAA==.Jeckah:BAAALgAECgUJBQABLgAECgkJJQAIAF0VAA==.Jecthyr:BAAALgAECgEJAQABLgAECgkJJQAIAF0VAA==.Jefryepsteen:BAAALgADCgUJBQAAAA==.Jennîfer:BAAALgADCgUJBQAAAA==.Jerryberry:BAAALgADCgQJBgAAAA==.',
Ji='Jimboner:BAAALgADCgUJBgAAAA==.Jimmybeanz:BAABLgAECn8dAAIJAAcJuRb3FACvAQAJAAcJuRb3FACvAQAAAA==.Jimothy:BAAALgADCgEJAQAAAA==.Jinnasaiquoi:BAABLgAECn8YAAMkAAYJAh5oDAB1AQAkAAYJAh5oDAB1AQASAAEJrwLrWQElAAAAAA==.Jinncubus:BAAALgADCgYJBwAAAA==.',
Jo='Jordana:BAABLgAECn8UAAILAAgJ3hLoSQB7AQALAAgJ3hLoSQB7AQAAAA==.Jove:BAAALgAECgYJCQAAAA==.',
Jr='Jrack:BAAALgAECgEJAgAAAA==.',
Js='Jsdruid:BAAALgAECgYJDAAAAA==.',
Ju='Jug:BAABLgAECn8cAAIjAAgJqBuqBADJAgAjAAgJqBuqBADJAgAAAA==.Julaudette:BAAALgADCgcJDAAAAA==.',
Ka='Kainöa:BAAALgAECgYJDAABLgAECgcJDgAFAAAAAA==.Kakum:BAAALgAECgQJBwAAAA==.Kaldrogo:BAAALgAECgQJCgAAAA==.Kalius:BAAALgADCgMJAwABLgAFFAUJGAAUADUfAA==.Kalnuggets:BAAALgAECgQJBAAAAA==.Kalrathen:BAABLgAECn8eAAIJAAcJ8hMkHABpAQAJAAcJ8hMkHABpAQAAAA==.Kaniku:BAAALgAECgEJAwABLgAFFAQJCwANALwNAA==.Karsh:BAABLgAECn8gAAIeAAkJBwcaHQCAAQAeAAkJBwcaHQCAAQAAAA==.Kassaii:BAAALgAECgUJCgAAAA==.Kazadax:BAABLgAECn8UAAMXAAcJaQ+9QQBkAQAXAAcJOw69QQBkAQAcAAYJoQw0JAA4AQAAAA==.',
Ke='Kered:BAAALgAECgYJCQAAAA==.Keuaakepo:BAABLgAECn89AAMCAAkJMCMCAgAyAwACAAkJMCMCAgAyAwAjAAEJUQM6MgAqAAAAAA==.',
Ki='Kienne:BAABLgAECn8lAAICAAYJ9R56KACwAQACAAYJ9R56KACwAQAAAA==.Kinnison:BAAALgAECgQJCAAAAA==.Kinomi:BAAALgAECgQJAwABLgAECggJEQAFAAAAAA==.Kiresana:BAAALgAECgcJDAAAAA==.',
Kl='Kleenex:BAAALgAECgMJAwAAAA==.Klitkahmandr:BAAALgADCgEJAQAAAA==.Klonkie:BAAALgADCgQJBgAAAA==.Klutzyhunts:BAAALgAECgUJCwAAAA==.Klutçh:BAAALgAECgYJDwAAAA==.',
Ko='Koreanbrewbq:BAAALgAFFAEJAQAAAA==.Kothbaark:BAABLgAECn8mAAMiAAkJExf1AgBpAgAiAAkJExf1AgBpAgAgAAIJ0AwgKwBMAAAAAA==.',
Kp='Kpa:BAAALgAECgQJBwAAAA==.',
Kr='Krethar:BAAALgAECgIJAgABLgAFFAEJAQAFAAAAAA==.Krypt:BAABLgAECn8eAAIfAAkJ4xOjEgA8AQAfAAkJ4xOjEgA8AQAAAA==.Krìzl:BAABLgAECn8iAAINAAgJ/CIWEwCAAgANAAgJ/CIWEwCAAgAAAA==.',
Ku='Kullervo:BAAALgADCggJDQAAAA==.Kumookumts:BAAALgAECgQJBAAAAA==.',
Ky='Kymira:BAAALgAECgYJCQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgMJAwAAAA==.',
La='Lace:BAABLgAECn8uAAQcAAgJiSFsAQB0AgAcAAgJiSFsAQB0AgAXAAUJFhmAPAB2AQAYAAEJHh6QFABLAAAAAA==.Lanzen:BAAALgADCgUJBQABLgAECgUJBQAFAAAAAA==.Lanzier:BAAALgAECgUJBQAAAA==.Larrfena:BAABLgAECn8UAAICAAYJjBONSQCNAQACAAYJjBONSQCNAQAAAA==.',
Le='Legit:BAAALgAECgcJDAABLgAECggJHQAVAC4aAA==.Lementz:BAACLgAFFH8SAAIEAAUJnR+tAADIAQAEAAUJnR+tAADIAQAuAAQKfzYAAgQACQmQJmEAAMQDAAQACQmQJmEAAMQDAAAA.Lexiiees:BAABLgAECn8aAAIhAAcJugQCHgAMAQAhAAcJugQCHgAMAQAAAA==.',
Li='Liadres:BAAALgAECgQJBwAAAA==.Lialius:BAAALgAECgYJBgAAAA==.Lilboat:BAAALgAECgQJCQAAAA==.Lillia:BAABLgAECn8mAAIXAAgJ5RG1LgCoAQAXAAgJ5RG1LgCoAQAAAA==.',
Lo='Lockyshocky:BAAALgADCgEJAwAAAA==.Lovetobussy:BAABLgAECn8XAAIJAAYJ8BqGEgDLAQAJAAYJ8BqGEgDLAQAAAA==.',
Lu='Lucarrio:BAAALgAECgIJAgAAAA==.Luckylagers:BAAALgAECgEJAwAAAA==.Lumaomao:BAABLgAECn84AAQXAAkJZiBZDACOAgAXAAkJzh1ZDACOAgAcAAUJhR1+GwBxAQAYAAEJ6RpPFABOAAAAAA==.Lumpia:BAABLgAECn8bAAIKAAgJVR+cGQAyAgAKAAgJVR+cGQAyAgAAAA==.',
['Lè']='Lèah:BAAALgAECgUJCgAAAA==.',
['Lú']='Lúcifër:BAAALgADCgEJAQAAAA==.',
Ma='Macaroní:BAAALgAFFAEJAQABLgAFFAMJCQANADojAA==.Madgeyoulook:BAAALgAECgEJAQAAAA==.Magenta:BAAALgAECgUJBQAAAA==.Magicchoc:BAAALgAECgYJCAABLgAECggJHQAbAGQTAA==.Maktah:BAABLgAFFH8HAAIEAAQJBAYEBAAhAQAEAAQJBAYEBAAhAQAAAA==.Mandrakor:BAAALgADCgEJAQAAAA==.Marshboa:BAAALgAECgUJCgAAAA==.Mathematix:BAAALgAECgMJAwAAAA==.Maybesinged:BAAALgADCgYJBgAAAA==.',
Mc='Mcballinger:BAAALgAECgMJAwAAAA==.Mclovinit:BAACLgAFFH8TAAINAAcJkh+bAgBeAgANAAcJkh+bAgBeAgAuAAQKf0sAAg0ACQmpJnsAAAIEAA0ACQmpJnsAAAIEAAAA.Mcmagic:BAABLgAECn8nAAINAAcJLCNjFgBnAgANAAcJLCNjFgBnAgAAAA==.Mcpally:BAABLgAECn8vAAISAAkJ0CG1CgCwAgASAAkJ0CG1CgCwAgAAAA==.',
Me='Mecca:BAACLgAFFH8GAAIKAAIJlRmidgCcAAAKAAIJlRmidgCcAAAuAAQKfxUAAwoABwlVIR9AADgCAAoABwlVIR9AADgCABsABQl7FhskACABAAAA.Meggatron:BAAALgAECgEJAQAAAA==.Melendria:BAABLgAECn8dAAILAAkJeSO3CAADAwALAAkJeSO3CAADAwAAAA==.Mensu:BAAALgAECgYJCwAAAA==.Mentos:BAABLgAECn8mAAMRAAkJfxfwAQBQAgARAAgJfxfwAQBQAgATAAYJKh5wBwD9AQAAAA==.Mercilezz:BAAALgAECgEJAQAAAA==.',
Mi='Midwestfel:BAABLgAECn8VAAIVAAgJwgbcZQDRAAAVAAgJwgbcZQDRAAAAAA==.Mikeoxhard:BAAALgAECggJCgAAAA==.Minaa:BAAALgAECgIJAwAAAA==.Minaqt:BAABLgAECn8aAAIIAAgJNREnFgCPAQAIAAgJNREnFgCPAQAAAA==.Minihulk:BAAALgAECgMJAwAAAA==.Mionn:BAAALgAECgUJDgAAAA==.Misshell:BAAALgAECgEJAQAAAA==.',
Ml='Mlleena:BAABLgAECn8oAAMXAAcJAg9/QgBhAQAXAAcJAg9/QgBhAQAYAAMJxAr9GgCdAAAAAA==.',
Mo='Modotz:BAABLgAECn8jAAMcAAkJ9BiYBgBkAgAcAAcJqR2YBgBkAgAXAAYJwhSiMQCdAQAAAA==.Moofist:BAAALgAECgkJCAAAAA==.Mookungfoo:BAAALgADCgYJBgAAAA==.Moomagic:BAAALgAECgQJBgAAAA==.Mooncake:BAAALgAECggJEgAAAA==.Moosiah:BAABLgAECn8kAAIMAAgJ1iAdCQA9AgAMAAgJ1iAdCQA9AgAAAA==.Mortenerra:BAAALgAECgUJDAAAAA==.Morvash:BAAALgAECgEJBAAAAA==.Mossfiré:BAAALgAECgYJEAAAAA==.Motoko:BAABLgAECn8pAAQZAAkJ6hPuEgCdAQAZAAgJRRXuEgCdAQAUAAYJMBIDNgAWAQAaAAYJ6Qh3LgDiAAAAAA==.',
Mu='Muatamuata:BAAALgAECgEJAQAAAA==.Murdrmittens:BAAALgADCgYJAQABLgAECggJEQAFAAAAAA==.',
My='Myhealmissed:BAAALgADCggJCAAAAA==.',
['Mø']='Møø:BAAALgAECgQJBwABLgAECggJDAAFAAAAAA==.Møøfi:BAAALgAECgIJAgAAAA==.',
Na='Nachoshamy:BAAALgAECgUJBQAAAA==.Nameless:BAABLgAECn8iAAMOAAcJNxiHBQDUAQAOAAYJzhqHBQDUAQANAAcJfBLmSQCKAQAAAA==.Narc:BAABLgAECn8YAAILAAYJXwgFVADHAAALAAYJXwgFVADHAAAAAA==.Narcosis:BAAALgAECgYJDQAAAA==.Narissa:BAAALgADCgQJBAAAAA==.Nasfurratu:BAAALgAECgIJAgAAAA==.Nashkawaka:BAAALgADCgQJBgAAAA==.Nazrel:BAACLgAFFH8GAAMCAAQJLhEXFgBFAQACAAQJLhEXFgBFAQAGAAEJnQFkLQA8AAAuAAQKfyYAAwIACQkwHz0JAKECAAYACQk+F20QALkCAAIACQk5HT0JAKECAAAA.',
Ne='Necrojinn:BAAALgADCgMJAgAAAA==.Neeraj:BAABLgAECn8hAAICAAgJXBNVKACxAQACAAgJXBNVKACxAQAAAA==.',
Ni='Nibbah:BAAALgAECgYJDQAAAA==.Nicadema:BAAALgADCggJEgAAAA==.Nidmonk:BAAALgADCgUJBAAAAA==.Nightcap:BAAALgADCgEJAQAAAA==.Nightreaver:BAAALgADCgcJBAABLgAECggJEQAFAAAAAA==.Nikoro:BAAALgADCgEJAQAAAA==.Nitrofuse:BAACLgAFFH8IAAMYAAMJPQnDBwBVAAAXAAMJDwMuXQCTAAAYAAEJExnDBwBVAAAuAAQKfyMABBwACQltHAgPANoBABwABwmuFggPANoBABcABwmvF+NjAJ8BABgABQmEFRgJAAYBAAAA.',
No='Noova:BAABLgAECn8oAAINAAcJrB+IUABGAgANAAcJrB+IUABGAgAAAA==.Norooux:BAAALgADCggJCwAAAA==.Nostradotmus:BAAALgADCgYJBgAAAA==.Notcurty:BAAALgAECgUJCQAAAA==.',
Ny='Nyang:BAAALgADCgkJEAABLgAFFAQJBgAHAE0GAA==.',
Ob='Obliverat:BAAALgAECgcJDQAAAA==.',
Ol='Oldzygs:BAAALgAECgIJAQAAAA==.',
Om='Omgkings:BAAALgAECgQJBwAAAA==.',
Or='Orcaneblast:BAACLgAFFH8LAAINAAQJvA1gMgBDAQANAAQJvA1gMgBDAQAuAAQKfyMAAg0ACQlwHsAOAKYCAA0ACQlwHsAOAKYCAAAA.Orenj:BAAALgADCgIJAgAAAA==.Orindis:BAAALgAECgcJDgAAAA==.Ornn:BAABLgAECn8gAAIfAAcJnCILBgA3AgAfAAcJnCILBgA3AgAAAA==.',
Pa='Palmtalon:BAAALgAECgMJBAAAAA==.Pandaminium:BAAALgADCgYJBgAAAA==.Pandarias:BAAALgAECgMJAwAAAA==.Papsergargan:BAAALgAECgIJAgAAAA==.Partypizza:BAABLgAECn8wAAIPAAkJxx1+BgB9AgAPAAkJxx1+BgB9AgAAAA==.Parzul:BAAALgADCgcJCgAAAA==.',
Pe='Penance:BAAALgAECgIJBAABLgAFFAQJDAALAPgjAA==.Penne:BAAALgAECgYJBwABLgAFFAMJCQANADojAA==.Permanence:BAABLgAECn8UAAIVAAYJARZ3bQBbAQAVAAYJARZ3bQBbAQAAAA==.',
Pi='Picobuffu:BAAALgAECgYJBgABLgAECggJJgAVAEMdAA==.Picodedge:BAABLgAECn8mAAIVAAgJQx1vEwAhAgAVAAgJQx1vEwAhAgAAAA==.Picoroo:BAAALgAECgQJBAABLgAECggJJgAVAEMdAA==.Piekel:BAAALgADCgYJBwAAAA==.Pinkbagger:BAAALgADCgYJCQAAAA==.Pippìn:BAAALgAECgEJAQAAAA==.Pivnert:BAABLgAECn8kAAMNAAkJ1RZ7GwBFAgANAAkJ1RZ7GwBFAgAlAAIJJwwhCABsAAAAAA==.Pixxysticks:BAAALgAECgEJAQAAAA==.',
Po='Pollygix:BAAALgADCgIJAgAAAA==.Popdkook:BAAALgAECgMJAwAAAA==.Porthos:BAAALgADCgYJCwAAAA==.Poõpsikens:BAAALgADCgEJAQAAAA==.',
Pr='Praxispravus:BAAALgAECgYJDgAAAA==.Proko:BAABLgAECn8YAAIXAAcJtRmjTQBBAQAXAAcJtRmjTQBBAQAAAA==.Prophetplus:BAAALgADCgEJAQAAAA==.',
Ps='Psychopump:BAAALgAECgIJAgAAAA==.',
Py='Pyrai:BAAALgAECgEJAQAAAA==.',
['Pü']='Pünish:BAACLgAFFH8NAAIKAAQJHR4xGAB1AQAKAAQJHR4xGAB1AQAuAAQKfyUAAgoABwntI/cyAGsCAAoABwntI/cyAGsCAAAA.',
Qe='Qelsie:BAAALgAECgYJDQAAAA==.',
Qq='Qqpewpew:BAAALgAECgYJCQAAAA==.',
Qt='Qtpi:BAABLgAECn8eAAIVAAkJ+BwgDQBjAgAVAAkJ+BwgDQBjAgAAAA==.',
Qu='Quica:BAAALgAECgEJAQAAAA==.',
Ra='Rabit:BAAALgAECgQJDQAAAA==.Raelina:BAABLgAECn8dAAINAAgJURl8QwBuAgANAAgJURl8QwBuAgABLgAFFAYJFQANAAIbAA==.Raketh:BAAALgAECgcJEwAAAA==.Rallek:BAABLgAECn8wAAIWAAkJsRlwCgBqAgAWAAkJsRlwCgBqAgAAAA==.Ralos:BAAALgADCgQJBQAAAA==.Rarn:BAAALgADCggJCAABLgAECgcJIAAfAJwiAA==.',
Re='Read:BAAALgADCgcJBwAAAA==.Readysetvöke:BAABLgAECn8UAAITAAkJYR7CCwB6AgATAAkJYR7CCwB6AgAAAA==.Rehabherox:BAAALgADCgcJDgAAAA==.Rektek:BAABLgAECn8aAAIeAAkJWBRSNADZAQAeAAkJWBRSNADZAQAAAA==.Rektnasty:BAAALgAECgIJAwAAAA==.Remeras:BAABLgAECn8ZAAISAAgJ5hABXgDJAQASAAgJ5hABXgDJAQAAAA==.Resilientaid:BAAALgAECgYJEgAAAA==.Restolyfe:BAAALgAECgUJCwAAAA==.Retack:BAAALgAECgEJAgAAAA==.Reynara:BAAALgADCgUJBgAAAA==.',
Ri='Riken:BAABLgAECn8mAAQUAAkJ/A3kHABiAQAUAAkJ/A3kHABiAQAaAAIJygskdwBlAAAZAAEJsAR7hQArAAAAAA==.Rilzi:BAAALgAECgYJBgAAAA==.',
Ro='Roac:BAAALgADCgYJBgAAAA==.Roadi:BAAALgAECgcJDgABLgAECgkJMQAhAOcbAA==.Robomonkey:BAAALgADCgkJEAAAAA==.Rogueghost:BAAALgAECgUJDAAAAA==.Rohar:BAAALgAECgcJDgAAAA==.Roley:BAAALgADCgcJCgAAAA==.Roots:BAAALgAECgUJDwAAAA==.Rosalie:BAAALgADCgUJBQAAAA==.Roshii:BAAALgADCgYJBgAAAA==.Roshkar:BAAALgADCgYJBgAAAA==.',
Ru='Rukaa:BAAALgADCgEJAQAAAA==.Ruskiputanka:BAAALgAECgcJAgAAAA==.Ruuf:BAABLgAECn8mAAIPAAkJEQqTHABpAQAPAAkJEQqTHABpAQAAAA==.',
Ry='Ryvv:BAAALgAECgUJDQAAAA==.',
Sa='Sabre:BAAALgAECgcJEQAAAA==.Sadio:BAAALgADCgUJBQAAAA==.Sadistiik:BAAALgAECgMJAwAAAA==.Sailo:BAAALgADCgMJAwAAAA==.Saosis:BAAALgADCgEJAQAAAA==.Sappygurl:BAAALgAECgEJAQAAAA==.Sarvakana:BAAALgADCgUJBQAAAA==.Satanlovesu:BAAALgADCgYJBgAAAA==.Satori:BAAALgAECgQJBwAAAA==.',
Sc='Scalylusion:BAABLgAECn8WAAMQAAcJWxreLQBTAQAQAAYJAhfeLQBTAQARAAYJ0xisDQCzAAAAAA==.Scrubbers:BAAALgAECgEJAQAAAA==.',
Se='Seanconery:BAAALgAECgYJCgAAAA==.Senica:BAABLgAECn8nAAIJAAgJVx46EgBPAgAJAAgJVx46EgBPAgAAAA==.Sensedeous:BAAALgADCgQJBgAAAA==.Seriphina:BAAALgADCgkJFQAAAA==.',
Sh='Shabbarankz:BAABLgAECn8dAAIiAAgJ9hUPCwASAgAiAAgJ9hUPCwASAgAAAA==.Shader:BAAALgADCgcJDwAAAA==.Shadethemage:BAAALgADCgEJAQAAAA==.Shadetotem:BAABLgAECn8bAAIEAAgJSw6BCACeAQAEAAgJSw6BCACeAQAAAA==.Shadowblazer:BAAALgADCgYJBgAAAA==.Shadowcrash:BAAALgAECgQJBAABLgAECggJEQAFAAAAAA==.Shalanath:BAAALgADCgcJBwAAAA==.Sharded:BAAALgAECgcJDwAAAA==.Sheepwreck:BAAALgAECgQJBAAAAA==.Shenon:BAAALgADCgIJAgAAAA==.Shirairyu:BAAALgAECgUJCAAAAA==.Shmoopy:BAAALgADCgQJBAAAAA==.Shotbot:BAAALgADCgYJBgABLgAFFAMJBQASAFQRAA==.Shra:BAABLgAECn8hAAIgAAkJLhF9CQCLAQAgAAkJLhF9CQCLAQAAAA==.Shrafu:BAAALgAECgYJDAAAAA==.Shunye:BAAALgAECgQJBQAAAA==.Shyphter:BAAALgAECgEJAgAAAA==.',
Si='Silanah:BAAALgAECgMJAwAAAA==.Sillidan:BAAALgADCgEJAQABLgAECgcJEwAFAAAAAA==.Sindracosa:BAABLgAECn8XAAMRAAYJsgqGIAApAQARAAYJsgqGIAApAQATAAYJiQUULwD5AAABLgAECgkJGgAdALsPAA==.Sindradori:BAAALgADCgMJAwABLgAECgkJHAAIAKcZAA==.Sinnerman:BAAALgAECgQJBQAAAA==.Sinsidious:BAAALgADCgcJFAAAAA==.Sizzle:BAAALgAECggJCAABLgAECggJDwAFAAAAAA==.',
Sk='Skipthedishz:BAAALgAECgYJDQAAAA==.',
Sl='Slamburger:BAAALgAFFAEJAQAAAA==.Slimyghoul:BAAALgAECgYJBwAAAA==.Slingpingtin:BAAALgADCgEJAQAAAA==.',
Sm='Smokeahontas:BAABLgAECn8YAAIPAAgJMRPyFACtAQAPAAgJMRPyFACtAQAAAA==.Smokindots:BAABLgAECn8dAAIXAAgJvRfXVgAoAQAXAAgJvRfXVgAoAQABLgAECgkJNQADAGceAA==.Smokinmyrrh:BAAALgAECgMJAwABLgAECgkJNQADAGceAA==.Smokinpsalm:BAABLgAECn8ZAAMJAAcJ6xs0HAD7AQAJAAcJ6xs0HAD7AQAIAAQJAAfaNAC6AAABLgAECgkJNQADAGceAA==.Smokintotem:BAABLgAECn81AAIDAAkJZx5qCAClAgADAAkJZx5qCAClAgAAAA==.',
Sn='Sneakingbush:BAABLgAECn8bAAMhAAcJfQ2eLACaAQAhAAcJUg2eLACaAQAmAAQJ8grdEwDCAAAAAA==.Snowberry:BAAALgAECgEJAQAAAA==.Snufflüpagus:BAAALgAECgYJEQAAAA==.Snusnus:BAAALgAECgEJAQAAAA==.',
So='Sodiasm:BAAALgADCgEJAQAAAA==.Soulspartan:BAAALgAECggJEAAAAA==.',
Sp='Spaghet:BAECLgAFFH8IAAIPAAMJjQ+IEQDfAAAPAAMJjQ+IEQDfAAAuAAQKfxkAAw8ACAlLEUcmAN8BAA8ACAlLEUcmAN8BAAQAAwmxBWkkAJIAAAEuAAUUBgkUAA0AJxEA.Spaghett:BAABLgAFFH8JAAINAAMJOiPrOwAfAQANAAMJOiPrOwAfAQAAAA==.Spirytus:BAAALgAECgUJDgAAAA==.Spoonski:BAABLgAECn8pAAMZAAgJuyRnAwDHAgAZAAgJjCRnAwDHAgAaAAUJjiBwFwB8AQAAAA==.Spritecran:BAAALgAECgQJBgAAAA==.',
Sq='Square:BAAALgAECgUJCQAAAA==.Squigboogalo:BAAALgAECgUJBQAAAA==.',
St='Stealthycat:BAAALgADCgMJAwAAAA==.Stormz:BAAALgAECgcJBwAAAA==.',
Su='Sukuna:BAAALgAECgYJCgAAAA==.Sunblade:BAAALgAECgQJBgABLgAECgcJIgAOADcYAA==.Sundowning:BAABLgAECn8bAAIIAAkJsRV5CABBAgAIAAkJsRV5CABBAgAAAA==.Supercappy:BAAALgADCgUJBQAAAA==.Supervillain:BAAALgADCgEJAQAAAA==.',
Sw='Swiftdragon:BAAALgAECggJEQAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.Swuurv:BAAALgAECgMJAgABLgAECggJFgAYAMYfAA==.',
Sy='Sylerwinassa:BAAALgAECgQJCAAAAA==.Sylvette:BAAALgADCgcJBwAAAA==.Sylvy:BAEALgAECgUJBQABLgAECgUJDAAFAAAAAA==.Symbolofhope:BAAALgAECgUJBgAAAA==.Synjo:BAABLgAECn8qAAInAAgJJBxLAgAkAgAnAAgJJBxLAgAkAgAAAA==.',
Ta='Taapfer:BAABLgAECn8cAAMBAAgJqR4lAwCtAgABAAgJqR4lAwCtAgAVAAEJAAAq2gAAAAAAAA==.Tackyh:BAAALgAECgYJCgAAAA==.Taku:BAAALgADCgQJBgAAAA==.Tamada:BAAALgADCgcJBwAAAA==.Tankedabbot:BAAALgAECgMJAwAAAA==.Tankxiety:BAAALgADCgUJBQAAAA==.Tar:BAAALgAECgYJCwABLgAECggJDAAFAAAAAA==.Tassidar:BAAALgAECgUJCgAAAA==.Taxii:BAABLgAECn8tAAMeAAkJNiWsAABNAwAeAAkJ/iSsAABNAwAoAAUJwRp2EABDAQAAAA==.',
Te='Teapots:BAABLgAECn8ZAAIEAAgJ2CJVCQBDAgAEAAgJ2CJVCQBDAgAAAA==.Teegria:BAAALgADCgYJBgAAAA==.Teggatz:BAAALgAECgEJAwAAAA==.Tehana:BAAALgADCgUJCQAAAA==.Teldaris:BAABLgAECn8eAAMIAAkJFxapGwAAAgAIAAkJFxapGwAAAgAJAAEJlAkwfgA1AAAAAA==.Telor:BAAALgAECgEJAQAAAA==.Tezcacoatl:BAAALgAECgUJBQAAAA==.',
Th='Thatwarlock:BAAALgADCgYJBgABLgAECggJHgAWAFQfAA==.Thayelith:BAAALgADCgcJBwAAAA==.Thedeus:BAACLgAFFH8FAAISAAMJVBE3LgD7AAASAAMJVBE3LgD7AAAuAAQKfykAAhIACQn2HjIIAM8CABIACQn2HjIIAM8CAAAA.Thefifth:BAACLgAFFH8YAAITAAcJGA7tAgDiAQATAAcJGA7tAgDiAQAuAAQKfyAABBMACQkGGngOAFACABMACQkGGngOAFACABEAAgmzEtUyAH8AABAAAQm7DtpYADoAAAAA.Theralendris:BAABLgAECn8YAAIBAAgJhxGBEQA5AQABAAgJhxGBEQA5AQAAAA==.Thickarm:BAAALgAECgYJDAABLgAECgcJDgAFAAAAAA==.Thyrn:BAAALgADCgYJBgABLgAECgcJIAAfAJwiAA==.',
Ti='Timmythicc:BAAALgAECgQJBQAAAA==.Tinytots:BAAALgADCgYJCgAAAA==.Tirare:BAABLgAECn8gAAIKAAgJdxviIQD+AQAKAAgJdxviIQD+AQAAAA==.Titanfang:BAAALgAECgMJAwAAAA==.',
To='Tokebee:BAAALgADCgcJDQAAAA==.',
Tr='Tracts:BAAALgADCgMJAwAAAA==.Traumatize:BAAALgAECgcJEwAAAA==.Trazenoth:BAAALgADCgYJBgABLgAFFAQJCwANALwNAA==.Treebeard:BAAALgADCgYJCwAAAA==.Treshan:BAAALgADCgkJCQAAAA==.Tri:BAABLgAECn8ZAAISAAcJqCXYDQCQAgASAAcJqCXYDQCQAgAAAA==.Tristam:BAAALgAECgUJBQAAAA==.',
Ts='Tsavo:BAABLgAECn8nAAMPAAgJIBF7GgB7AQAPAAgJIBF7GgB7AQADAAEJBAWdoAAwAAAAAA==.',
Tu='Tuggle:BAAALgAECgQJCAAAAA==.Tuneleitor:BAAALgADCgIJAgAAAA==.Turdle:BAAALgADCgcJBwAAAA==.Turgrok:BAAALgAECgYJCgAAAA==.',
Tw='Twistedmagic:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.',
Ty='Tyler:BAAALgADCgEJAQAAAA==.Tyllan:BAACLgAFFH8HAAINAAQJUA69NQA6AQANAAQJUA69NQA6AQAuAAQKfx0AAw0ACQkZH7sOAFEDAA0ACQkZH7sOAFEDAA4AAQl0IuoWAGMAAAAA.',
Un='Uniförm:BAABLgAECn8dAAMhAAkJxg9oDwCuAQAhAAkJxg9oDwCuAQAmAAEJTgSsHAAqAAAAAA==.',
Va='Vaalsyra:BAAALgAECgMJAwAAAA==.Vaeld:BAABLgAECn8oAAIfAAgJzyRABQDrAgAfAAgJzyRABQDrAgAAAA==.Vainhellsing:BAAALgAECgYJCgABLgAECggJKAAPAOsRAA==.Vampage:BAAALgAECggJCgAAAA==.Vandeadly:BAAALgAECgYJDwAAAA==.Vannethir:BAAALgAECgQJBAABLgAFFAQJCwANALwNAA==.Vanzer:BAAALgAECgYJDQAAAA==.Vanzier:BAABLgAECn8YAAMCAAkJIRvYEABNAgACAAgJiRvYEABNAgAGAAcJfxVyMQCrAQAAAA==.Varixnt:BAAALgADCgMJAQAAAA==.Vaxis:BAABLgAECn8WAAICAAgJaBBrMgDmAQACAAgJaBBrMgDmAQAAAA==.',
Ve='Ved:BAAALgAECgcJEgAAAA==.Vedishh:BAAALgADCgkJCgAAAA==.Venatohr:BAAALgAECggJDgABLgAECggJKAAfAM8kAA==.Verycurious:BAAALgAECgUJCwABLgAECgcJDgAFAAAAAA==.',
Vi='Vid:BAAALgADCgIJAgAAAA==.Video:BAAALgAECgUJCQABLgAECgkJMQAhAOcbAA==.Vilemaw:BAAALgAECgUJCwAAAA==.Vinnidari:BAAALgAECgMJAwABLgAECgcJEgAFAAAAAA==.',
Vo='Voidbuz:BAAALgAECgQJBwAAAA==.Voidmaw:BAAALgADCgcJBwAAAA==.',
Vy='Vyral:BAAALgAECgYJBgAAAA==.',
['Vá']='Váder:BAAALgAECgcJCAAAAA==.',
We='Weave:BAAALgAECgMJAwABLgAECggJLgAcAIkhAA==.Wernov:BAABLgAECn8ZAAIDAAgJTiC3CgCCAgADAAgJTiC3CgCCAgAAAA==.',
Wh='Whathappened:BAAALgAECgQJBAAAAA==.Whitemonster:BAAALgADCgUJBQAAAA==.Whodoitaunt:BAACLgAFFH8NAAIgAAQJlR/3AQB3AQAgAAQJlR/3AQB3AQAuAAQKfyQAAiAACQnXHkMEALMCACAACQnXHkMEALMCAAAA.',
Wi='Wichan:BAABLgAECn8wAAIgAAkJRx7JAgB8AgAgAAkJRx7JAgB8AgAAAA==.Wilfèral:BAAALgADCgcJBwAAAA==.Windrúnner:BAAALgAECgQJBwAAAA==.Wiziviji:BAABLgAECn8VAAINAAgJtQ2uaABAAQANAAgJtQ2uaABAAQAAAA==.',
Wo='Woodrow:BAABLgAECn8YAAIWAAgJjR6TFQDjAQAWAAgJjR6TFQDjAQAAAA==.Worldstar:BAAALgAECgYJBgAAAA==.',
Ws='Ws:BAABLgAECn8bAAMHAAcJ8hk+DQD9AQAHAAcJ8hk+DQD9AQAIAAMJvxHXSgCvAAAAAA==.',
Wu='Wulfen:BAAALgAECgEJAQAAAA==.',
Xa='Xanddlock:BAAALgADCgQJBAAAAA==.Xanorea:BAAALgADCgcJBwABLgAECgcJDAAFAAAAAA==.',
Xc='Xclusive:BAAALgADCggJDwAAAA==.',
Xf='Xfire:BAABLgAECn8WAAQTAAcJDxPgIAB2AQATAAYJSBTgIAB2AQAQAAQJOw/fRQDFAAARAAEJcAt4FwA3AAAAAA==.',
Xi='Xi:BAAALgADCgQJBAABLgAECggJDAAFAAAAAA==.',
Xr='Xray:BAAALgADCgYJDAAAAA==.',
Ya='Yaphetkotto:BAAALgADCgMJAwAAAA==.Yashooba:BAAALgAECgYJCwAAAA==.',
Ye='Yeasted:BAAALgAECgYJCgAAAA==.Yetunde:BAAALgADCgEJAQAAAA==.',
Yi='Yisoonshin:BAABLgAECn8UAAIaAAYJPyUnEgCDAgAaAAYJPyUnEgCDAgABLgAECgcJDgAFAAAAAA==.',
Yo='Yo:BAAALgAECggJEAAAAA==.Yolotli:BAAALgADCggJGgAAAA==.',
Yu='Yugito:BAAALgADCgcJCQAAAA==.Yun:BAAALgAECgYJBgAAAA==.Yunsky:BAAALgAECgUJBQAAAA==.',
Za='Zaka:BAAALgADCgMJBgAAAA==.Zali:BAAALgADCgYJCgAAAA==.Zanber:BAAALgAECgkJDAAAAA==.Zanosuke:BAAALgAECgcJDwAAAA==.Zanzer:BAAALgADCgQJBAABLgAECgUJBQAFAAAAAA==.Zaria:BAABLgAECn8YAAIXAAcJZRN3WAAkAQAXAAcJZRN3WAAkAQAAAA==.Zaryor:BAAALgAECgEJAQAAAA==.',
Ze='Zerica:BAAALgADCgMJAwAAAA==.Zerika:BAABLgAECn8fAAIJAAgJrCI8AwD6AgAJAAgJrCI8AwD6AgAAAA==.',
Zi='Zigzwag:BAAALgAECgQJBQAAAA==.Zionna:BAAALgADCgYJAQABLgAECggJEQAFAAAAAA==.',
Zo='Zomgqq:BAABLgAECn8XAAIEAAgJEhUqDgDaAQAEAAgJEhUqDgDaAQAAAA==.Zorr:BAAALgADCgUJBQAAAA==.',
Zu='Zunson:BAAALgADCgcJBgAAAA==.Zurtrax:BAABLgAECn8VAAIeAAcJohnnGgCQAQAeAAcJohnnGgCQAQABLgAECgcJGwAhAH0NAA==.',
Zy='Zydis:BAAALgAECgYJCQAAAA==.',
['Èe']='Èepy:BAAALgADCgMJBAABLgAFFAEJAQAFAAAAAA==.',
['És']='Éstéla:BAABLgAECn8pAAICAAkJQxbCFgAZAgACAAkJQxbCFgAZAgAAAA==.',
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

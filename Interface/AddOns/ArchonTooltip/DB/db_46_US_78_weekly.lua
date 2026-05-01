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

local lookup = {'Priest-Discipline','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Blood','Mage-Fire','Druid-Guardian','Warrior-Fury','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost','Paladin-Protection',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abbathdoom:BAAALgAECgYJBwAAAA==.',
Ae='Aedaris:BAABLgAECn9FAAMBAAgJ/BsWEgBwAQABAAYJyhYWEgBwAQACAAMJmiGFIwDiAAAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Altaria:BAABLgAFFH8JAAMDAAQJDxf7BABKAQADAAQJ4xX7BABKAQAEAAMJURLREwDaAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAAALgAECgYJDwAAAA==.',
Ar='Arcfuldodger:BAAALgADCgQJBAAAAA==.Artais:BAABLgAECn8gAAIFAAgJ1Rx/FgCCAgAFAAgJ1Rx/FgCCAgAAAA==.Artzlayer:BAABLgAECn8mAAIGAAkJcCIqBADqAgAGAAkJcCIqBADqAgAAAA==.Aríes:BAABLgAECn9FAAIHAAgJlBywAwBYAgAHAAgJlBywAwBYAgAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAUJCgAIAOIOAA==.Awry:BAABLgAECn8eAAIGAAgJpxvoEwAaAgAGAAgJpxvoEwAaAgAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAJAAAAAA==.Aww:BAACLgAFFH8KAAIIAAUJ4g7JIABPAQAIAAUJ4g7JIABPAQAuAAQKfxwAAggACAkkFwR/ANMBAAgACAkkFwR/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8bAAIKAAcJHCDlBAC1AQAKAAcJHCDlBAC1AQAAAA==.Azmo:BAABLgAECn8lAAMLAAgJMCHBAgDWAgALAAgJiR3BAgDWAgAMAAUJPhyzYACnAQAAAA==.Azulon:BAAALgADCgUJBQABLgAECgcJGQABAPcbAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAFANUcAA==.',
Be='Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQAAAA==.Belerick:BAABLgAFFH8JAAINAAMJnQqYDwDoAAANAAMJnQqYDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAAALgAFFAIJAwAAAA==.Bigdaddylock:BAACLgAFFH8LAAIMAAUJ8RmrDwBgAQAMAAUJ8RmrDwBgAQAuAAQKfyQAAwsACQnfJEwIAD4CAAsABgm1IkwIAD4CAAwACAkqI1IRABsCAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8ZAAIBAAcJ9xuABQBgAgABAAcJ9xuABQBgAgAAAA==.',
Bl='Bluecar:BAAALgAECgYJBwAAAA==.',
Bo='Bohica:BAAALgAECgEJAwAAAA==.Bombdiggity:BAABLgAECn8WAAIBAAYJ3R5PCAATAgABAAYJ3R5PCAATAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn80AAIEAAgJEReaCgDhAQAEAAgJEReaCgDhAQAAAA==.Brick:BAABLgAECn8fAAIEAAcJch6YDADAAQAEAAcJch6YDADAAQABLgAFFAUJEAAMANkdAA==.Brongakill:BAAALgADCgYJBgAAAA==.',
Bu='Bumble:BAAALgADCgYJBgABLgAFFAYJGAACAIgdAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAABLgAECn8UAAIIAAgJLQeVWAAtAQAIAAgJLQeVWAAtAQAAAA==.',
Ce='Cell:BAAALgAECgUJCAABLgAECgYJBwAJAAAAAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJBQAAAA==.',
Ci='Cig:BAAALgAECgYJEQAAAA==.',
Cl='Clankychan:BAACLgAFFH8GAAIEAAMJWAV7JwBvAAAEAAMJWAV7JwBvAAAuAAQKfxQAAgQABgn/E2s8AFUBAAQABgn/E2s8AFUBAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgIJBAAAAA==.Comillmouth:BAABLgAECn8ZAAIBAAgJahGBDADCAQABAAgJahGBDADCAQAAAA==.Comillthroat:BAAALgAECggJCAAAAA==.Cos:BAABLgAECn8kAAMOAAgJqgvECwCsAQAOAAgJqgvECwCsAQAPAAMJOAXBFgCKAAAAAA==.',
Cr='Cryptum:BAAALgAECggJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Daerus:BAAALgAECgYJBQAAAA==.Damge:BAAALgAECgUJCQAAAA==.Danky:BAAALgAECgMJAwAAAA==.Darahug:BAAALgADCgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAJAAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8YAAMQAAcJdR/BFQDjAQAQAAYJ1SDBFQDjAQAKAAYJ+hnMOQB5AQAAAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8XAAIRAAcJgQq6EAAWAQARAAcJgQq6EAAWAQAAAA==.Deeper:BAAALgAECgUJBQAAAA==.Deepest:BAAALgAFFAEJAQAAAA==.Deloraine:BAACLgAFFH8VAAISAAUJgxu2AgDMAQASAAUJgxu2AgDMAQAuAAQKfxcAAhIABwk5ImkSAGUCABIABwk5ImkSAGUCAAAA.Demonicfaith:BAABLgAECn82AAMHAAcJbxp+FwAMAgAHAAYJTx5+FwAMAgATAAcJwAtwRgDSAAAAAA==.Denman:BAAALgAECgcJEQAAAA==.',
Di='Dirtyfux:BAABLgAECn8VAAMBAAYJaxyFHwCYAQABAAYJaxyFHwCYAQACAAEJGQ8AgwAuAAAAAA==.Dirtysham:BAABLgAECn8nAAIUAAgJcSH+DAC1AgAUAAgJcSH+DAC1AgAAAA==.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgADCgUJBgAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAUJCgAIAOIOAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8hAAQVAAgJvhgdAwDCAQAWAAgJkBT+GwDoAQAVAAcJRxYdAwDCAQAXAAUJQwivMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgEJAQABLgAECgIJAgAJAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJEwAJAAAAAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elibaba:BAAALgAECggJDAAAAA==.Elideady:BAAALgAECggJAgABLgAECggJDAAJAAAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgADCggJFwAAAA==.',
En='Endlessdh:BAACLgAFFH8FAAIHAAMJ7SEJBwDIAAAHAAMJ7SEJBwDIAAAuAAQKfxgAAgcABwkbJJYJAMgCAAcABwkbJJYJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAECggJFgASAIQdAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Es='Estreuth:BAAALgADCgIJAgAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAAALgAECgUJBwAAAA==.',
Ez='Ezelia:BAAALgAECgcJEgABLgAFFAcJIwACAHQXAA==.',
Fa='Faelune:BAAALgAECgYJDwAAAA==.Faldir:BAAALgADCgYJBAABLgAECgcJFAATACAaAA==.',
Fe='Ferndru:BAAALgAECgUJBwAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAECggJGAAWADQhAA==.Fisticuffs:BAACLgAFFH8LAAIYAAQJfA/XDAAPAQAYAAQJfA/XDAAPAQAuAAQKfxsAAhgABwngFfskAIsBABgABwngFfskAIsBAAAA.',
Fl='Flameshock:BAAALgAECgQJCQAAAA==.Flowki:BAAALgADCgYJBQAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgEJAQAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAAALgAECgYJDwAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIZAAYJSxV7GwBwAQAZAAYJSxV7GwBwAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAABLgAECn8iAAIaAAgJ0BicGgDrAQAaAAgJ0BicGgDrAQAAAA==.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECgcJBgAJAAAAAA==.',
Gh='Ghalorin:BAAALgAECgMJCQAAAA==.Ghiroza:BAABLgAECn9GAAQLAAgJoBzdCAAzAgALAAgJjBbdCAAzAgAMAAgJChx+EQAZAgAbAAIJcBdnHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIXAAgJahZiBAAxAgAXAAgJahZiBAAxAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8hAAIGAAgJLx66EgAkAgAGAAgJLx66EgAkAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgIJAgAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9DAAIcAAgJHQ8uGABRAQAcAAgJHQ8uGABRAQAAAA==.Griinn:BAAALgAECgcJEQAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.',
Gu='Guldannyboy:BAABLgAECn8dAAILAAgJkAlLHgBeAQALAAgJkAlLHgBeAQAAAA==.Gumbö:BAAALgAECgYJBgABLgAECggJIAAFANUcAA==.',
Ha='Hammer:BAAALgAECgIJAgAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harry:BAABLgAECn8lAAMdAAkJRCPlAQA/AwAdAAkJRCPlAQA/AwAUAAcJxBrkIAAaAgAAAA==.',
He='Heartdh:BAAALgAECgcJEgAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgADCgIJAwABLgAECgYJFQAeAA4VAA==.Herpyprotect:BAAALgAFFAEJAQAAAA==.Herrion:BAACLgAFFH8QAAIMAAUJ2R28DQBuAQAMAAUJ2R28DQBuAQAuAAQKfyoAAwwACAkZJfgcAKgCAAwABwkZJfgcAKgCAAsABAmcJNQUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Hotspur:BAABLgAECn80AAIFAAgJaxDROADDAQAFAAgJaxDROADDAQAAAA==.',
Hu='Huskar:BAAALgAECgYJBwAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8TAAIfAAgJbhyUAABRAgAfAAgJbhyUAABRAgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9FAAILAAgJwRpfBQCBAgALAAgJwRpfBQCBAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECggJCQAAAA==.',
In='Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgADCgMJAwAAAA==.Infernyoz:BAAALgADCggJCAAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
It='Itchygrowth:BAAALgAECgEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.',
Ja='Jasha:BAAALgADCgYJBQAAAA==.Jayy:BAABLgAECn8bAAIGAAkJBRCDTAANAgAGAAkJBRCDTAANAgAAAA==.',
Je='Jennatalia:BAAALgAECgcJBgAAAA==.',
Jo='Joelsdruid:BAAALgAFFAMJAwAAAA==.Joelvoker:BAAALgAECgEJAQABLgAFFAMJAwAJAAAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAABLgAECn8VAAMBAAcJgxMVEACMAQABAAcJ1BEVEACMAQACAAUJExJ3SAAXAQAAAA==.Kairon:BAABLgAECn8nAAIaAAgJtRUJGwDoAQAaAAgJtRUJGwDoAQAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAAALgAFFAMJAwAAAA==.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8HAAIHAAMJeAnwBwDZAAAHAAMJeAnwBwDZAAAuAAQKfyQAAgcACAkcHn8DAGACAAcACAkcHn8DAGACAAAA.',
Kl='Klckyourass:BAAALgADCgUJBQAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAABLgAECn8WAAMDAAgJAhC7DQCeAQADAAgJAhC7DQCeAQAYAAYJtRBAMQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAAALgAECgUJDQAAAA==.',
Ky='Kynnareth:BAAALgAECgIJBAABLgAECgYJCgAJAAAAAA==.Kynralol:BAABLgAECn8aAAIIAAcJoB4OJgDOAQAIAAcJoB4OJgDOAQAAAA==.',
['Ká']='Káiser:BAAALgAECgcJEAAAAA==.',
La='Laenosh:BAAALgAECgQJCAAAAA==.Laomoo:BAAALgAECgcJDAAAAA==.',
Le='Learning:BAABLgAECn8XAAIcAAcJDB9HGwA4AgAcAAcJDB9HGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8iAAMQAAgJBh5vCABxAgAQAAgJBh5vCABxAgAKAAEJyAgCjgAtAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8PAAMOAAUJhhwKAwDMAQAOAAUJhhwKAwDMAQAPAAEJQRHGBQBgAAAuAAQKfyIAAw4ACAmUJEAKAO4CAA4ACAnbI0AKAO4CAA8ABwk/ItwDAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAABLgAECn8kAAIaAAgJxhchJAC0AQAaAAgJxhchJAC0AQAAAA==.Littleriver:BAAALgAECgcJEQAAAA==.',
Ll='Llewser:BAAALgAECgUJDQAAAA==.',
Lo='Loistiah:BAAALgAECgQJCgAAAA==.Lothaof:BAABLgAECn8gAAIaAAkJzAyzSAAwAQAaAAkJzAyzSAAwAQAAAA==.Louisvuitton:BAAALgAECgUJCgAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAECgEJAgABLgAFFAUJEAAMANkdAA==.Lunana:BAAALgAECgYJDwAAAA==.',
Ly='Lychiee:BAAALgAECgYJDwAAAA==.',
Ma='Magesorry:BAAALgADCgUJBQAAAA==.Maize:BAABLgAECn8eAAMBAAgJLBt8BQBhAgABAAgJLBt8BQBhAgACAAMJhgvAZwCOAAAAAA==.Makima:BAAALgAECgMJAwABLgAFFAQJDgANAGMWAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcyon:BAAALgAECgYJEAAAAA==.',
Mc='Mchèalz:BAABLgAECn8UAAQBAAgJuAfQFQBEAQABAAgJuAfQFQBEAQACAAQJxAEzaQCIAAASAAIJOwFuZgAsAAAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAAALgAECggJEAAAAA==.',
Mi='Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgADCgYJBgAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAAALgAECggJEwAAAA==.Monscustodes:BAABLgAECn8ZAAIIAAYJrxDVVAA2AQAIAAYJrxDVVAA2AQAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAAALgAECgYJDAAAAA==.Moounka:BAABLgAECn8bAAIEAAYJOgtbIQD4AAAEAAYJOgtbIQD4AAAAAA==.Morphio:BAABLgAECn8tAAMQAAgJjiK9BQCcAgAQAAgJjiK9BQCcAgAKAAUJCxNzTAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn8wAAIEAAgJhRPxDwCUAQAEAAgJhRPxDwCUAQAAAA==.Murius:BAABLgAECn8kAAIGAAgJ2RXsIwCyAQAGAAgJ2RXsIwCyAQAAAA==.',
My='Mysterio:BAAALgAECgYJCAAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJDAAAAA==.Nigella:BAAALgAECggJDgAAAA==.Nikola:BAABLgAECn8iAAQFAAgJAxdmNwDKAQAFAAgJAxdmNwDKAQAgAAUJNxbjFQAUAQANAAQJfQ90VADUAAAAAA==.Nimro:BAACLgAFFH8PAAIRAAQJNxZ6BAA1AQARAAQJNxZ6BAA1AQAuAAQKfycAAhEACQmPH5sDABsDABEACQmPH5sDABsDAAAA.Niub:BAABLgAECn8YAAIhAAcJFArYJAAVAQAhAAcJFArYJAAVAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgYJGQAIAK8QAA==.',
Nu='Nuferax:BAAALgAECgYJDwAAAA==.Numbrethree:BAACLgAFFH8HAAIYAAMJMgnqFgCBAAAYAAMJMgnqFgCBAAAuAAQKfzMAAhgACAlTF3UWAA8CABgACAlTF3UWAA8CAAAA.',
Ob='Obbi:BAAALgAECgYJDQAAAA==.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Or='Orinocco:BAAALgAECgEJAQAAAA==.Orobas:BAAALgADCgYJBwAAAA==.',
Pa='Pakaww:BAAALgAECgIJAgAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn8bAAIZAAYJHSTlEwBzAgAZAAYJHSTlEwBzAgAAAA==.Pallidnim:BAAALgAFFAEJAgAAAA==.',
Pe='Pea:BAAALgAECgcJDAAAAA==.',
Ph='Phatmonk:BAACLgAFFH8FAAIDAAMJ+h7JBgArAQADAAMJ+h7JBgArAQAuAAQKfxwAAgMACAk+JSABAAEDAAMACAk+JSABAAEDAAAA.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8TAAMSAAYJfRnVAgDHAQASAAUJYh3VAgDHAQABAAUJwgwXCACNAQAuAAQKfy0AAhIACQlSIkAEAFIDABIACQlSIkAEAFIDAAAA.',
Pl='Pleasuremax:BAAALgAECgYJDgAAAA==.Plex:BAABLgAECn8xAAIiAAgJKBeBAwAOAgAiAAgJKBeBAwAOAgAAAA==.',
Po='Poogie:BAAALgADCgYJBgABLgAECgMJBQAJAAAAAA==.Popshot:BAABLgAECn8eAAIKAAYJ5xL0RABBAQAKAAYJ5xL0RABBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAABLgAECn8WAAIRAAgJ8Ah1HQBaAQARAAgJ8Ah1HQBaAQAAAA==.Preast:BAAALgADCgMJAwABLgAECggJEwAJAAAAAA==.Procist:BAAALgADCggJCAABLgAECggJKAAUAFsiAA==.',
Py='Pyrusdk:BAABLgAECn8XAAIGAAgJRA6YKACaAQAGAAgJRA6YKACaAQAAAA==.',
Qo='Qop:BAAALgAECggJBgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAJAAAAAA==.',
Qw='Qweffor:BAAALgAECgMJAwABLgAECgcJFQAGAMMWAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAAALgAECgUJBAAAAA==.',
Re='Reapy:BAAALgAFFAEJAQAAAA==.Recruitqt:BAAALgAECgUJDgAAAA==.Reiayanami:BAABLgAECn8eAAIIAAgJmgxSNwCJAQAIAAgJmgxSNwCJAQAAAA==.',
Ri='Ripandtear:BAAALgAECgcJEwAAAA==.',
Ro='Roguewan:BAAALgAECgYJCgAAAA==.Roninn:BAAALgAECgcJDwAAAA==.Ronlock:BAABLgAECn8VAAMMAAYJ6xDvnQAdAQAMAAUJ6xDvnQAdAQALAAEJAAD3aQA+AAABLgAECgcJNgAHAG8aAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAAALgAECgYJBgAAAA==.',
Sa='Salvare:BAABLgAECn8lAAMPAAkJeRhvAwCVAgAPAAkJbxhvAwCVAgAjAAIJWBDnCQB/AAAAAA==.Sappy:BAAALgADCgMJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAECgUJDgAJAAAAAA==.',
Sb='Sbf:BAABLgAFFH8SAAIWAAYJxRG4BQCbAQAWAAYJxRG4BQCbAQABLgAFFAcJJgAIAHIbAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAAALgAECgYJBgAAAA==.Scioscioz:BAABLgAECn8aAAMFAAcJxRPgOwC1AQAFAAcJxRPgOwC1AQANAAIJZBDxawBwAAAAAA==.Scwisgar:BAAALgAECggJDAAAAA==.',
Se='Sedge:BAAALgAFFAIJAgAAAA==.Sephire:BAABLgAECn8WAAIaAAcJ3gPrewC1AAAaAAcJ3gPrewC1AAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMeAAYJDhX8DwAYAQAeAAYJDhX8DwAYAQAGAAMJLASQAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAABLgAECn8pAAMKAAgJXx3QAwDhAQAKAAgJLRnQAwDhAQAQAAQJMhsUMgBJAQAAAA==.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMbAAgJcRDnCwB7AQAbAAcJABLnCwB7AQAMAAcJmwgYPQA7AQAAAA==.Shammalxs:BAABLgAFFH8GAAIcAAUJRwR5CQBCAQAcAAUJRwR5CQBCAQAAAA==.Shamoc:BAABLgAECn8oAAMUAAgJWyJgBAC5AgAUAAgJWyJgBAC5AgAcAAYJoREGSQAkAQAAAA==.Shampooing:BAABLgAECn8UAAIcAAgJHAttGABPAQAcAAgJHAttGABPAQAAAA==.Sharpknife:BAAALgAFFAMJBAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shorpus:BAABLgAECn8XAAQdAAcJGyAgCgAwAgAdAAYJNx8gCgAwAgAUAAcJCwj5XQATAQAcAAUJ8xhfJAD/AAAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIDAAkJRyH5CQDYAgADAAkJRyH5CQDYAgAAAA==.',
Sk='Skizzyy:BAAALgAECgIJAgABLgAECgcJEAAJAAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgEJAQAAAA==.Slowpoke:BAABLgAFFH8OAAINAAQJYxbACABXAQANAAQJYxbACABXAQAAAA==.',
Sm='Smacedh:BAAALgAECgcJEgAAAA==.',
Sn='Sneakyfella:BAAALgAECggJCgAAAA==.',
So='Solidus:BAAALgAFFAEJAQAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8PAAMNAAUJrxjfCQBFAQANAAUJrxjfCQBFAQAFAAMJ3gNRHwCnAAAuAAQKfxoAAg0ABwmoJewLANkCAA0ABwmoJewLANkCAAAA.',
Ss='Ss:BAAALgAECgEJAgAAAA==.',
St='Stickydruid:BAAALgAECgIJAgABLgAECggJQAASAIohAA==.Stickyholes:BAAALgAECgEJAgABLgAECggJQAASAIohAA==.Stickypriest:BAABLgAECn9AAAMSAAgJiiGCAgCoAgASAAgJiiGCAgCoAgACAAEJExiJeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH8mAAIIAAcJchseAwBMAgAIAAcJchseAwBMAgAuAAQKfzwAAggACQkyJWkCANgDAAgACQkyJWkCANgDAAAA.Streamliner:BAABLgAECn8oAAMOAAgJKRiUCADlAQAOAAgJKRiUCADlAQAjAAMJ1gdLCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Sustangelia:BAABLgAECn8WAAIGAAgJHxl4UAAAAgAGAAgJHxl4UAAAAgAAAA==.',
Sw='Swisadecay:BAACLgAFFH8GAAIeAAMJshnECwDmAAAeAAMJshnECwDmAAAuAAQKfx0AAh4ACQn9IV0FAOsCAB4ACQn9IV0FAOsCAAAA.Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgADCgcJBwAAAA==.',
Sy='Sy:BAAALgAECgYJBwAAAA==.Synthesis:BAAALgAECgcJEwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Talas:BAAALgADCgIJAgAAAA==.Talletalanot:BAABLgAECn8sAAIXAAkJwx72AQC4AgAXAAkJwx72AQC4AgAAAA==.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8iAAICAAgJ7hvMBQBjAgACAAgJ7hvMBQBjAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8VAAIGAAcJzRVeSAAlAQAGAAcJzRVeSAAlAQAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Tesarion:BAABLgAECn8VAAIGAAcJwxbRJgCjAQAGAAcJwxbRJgCjAQAAAA==.Testalatesta:BAABLgAECn8dAAIZAAcJnx6KBwBlAgAZAAcJnx6KBwBlAgAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgYJBgAAAA==.',
Tm='Tmonk:BAAALgAECgcJBwAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Totemea:BAAALgADCgcJDAAAAA==.Totems:BAABLgAFFH8LAAIUAAUJoRsBBACuAQAUAAUJoRsBBACuAQAAAA==.Totemîxx:BAABLgAECn8XAAMcAAcJ0xRkLgCqAQAcAAcJ0xRkLgCqAQAUAAMJjg65fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAABLgAECn8wAAMMAAgJQSBzCwBbAgAMAAgJQSBzCwBbAgALAAMJKREVRAClAAAAAA==.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAAALgAECgYJCgAAAA==.',
Tu='Tuzz:BAABLgAECn8lAAIkAAgJHSFiAQDuAgAkAAgJHSFiAQDuAgAAAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgQJBAAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAJAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Verdict:BAACLgAFFH8JAAIaAAQJxhsIBwB8AQAaAAQJxhsIBwB8AQAuAAQKfxgAAhoACAloHl0gAKoCABoACAloHl0gAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8MAAIaAAQJkxUeDgBOAQAaAAQJkxUeDgBOAQAuAAQKfxoAAhoACAmCH/JEABUCABoACAmCH/JEABUCAAAA.',
Vi='Viegas:BAACLgAFFH8FAAIQAAIJmhLmKgClAAAQAAIJmhLmKgClAAAuAAQKfxsAAhAABwkhHK8gAEECABAABwkhHK8gAEECAAAA.Vincent:BAABLgAECn8hAAIIAAYJsB6XfgDUAQAIAAYJsB6XfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.',
Vo='Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAAALgAECgcJEgAAAA==.',
Vr='Vrag:BAABLgAECn8ZAAIGAAcJrAeIWAD6AAAGAAcJrAeIWAD6AAAAAA==.',
['Vè']='Vè:BAAALgAECgUJBQAAAA==.',
Wa='Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8FAAIIAAMJVhKkKgAKAQAIAAMJVhKkKgAKAQAuAAQKfzEAAggACAnVHOM0AJ8CAAgACAnVHOM0AJ8CAAAA.',
Wc='Wchin:BAAALgAECgcJDQAAAA==.Wchinz:BAAALgAECggJEgAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAAALgAECgcJEwAAAA==.',
Wi='Windsabre:BAAALgADCgIJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8eAAIMAAcJUxFbOgBEAQAMAAcJUxFbOgBEAQAAAA==.Woshiren:BAAALgAECgUJBQAAAA==.',
Wy='Wyvern:BAAALgAECgQJBgAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAAALgAECgYJDwAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHgAMAFMRAA==.Yazdorzarn:BAAALgAECgYJBwAAAA==.',
Za='Zaaniz:BAABLgAECn8aAAMaAAgJzh5wHwCvAgAaAAgJzh5wHwCvAgAlAAIJ5A2lHwBhAAAAAA==.',
Ze='Zenestra:BAAALgAECggJAQAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgADCgYJBgAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAAALgADCgMJAwAAAA==.',
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

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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Priest-Holy','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Paladin-Holy','Warlock-Destruction','Paladin-Protection','Warrior-Fury','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-05-01',data={Ae='Aegisthal:BAABLgAECn8WAAIBAAgJCBsiBAA1AgABAAgJCBsiBAA1AgAAAA==.Aequitasx:BAAALgAECgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJHgACAFUKAA==.',
Al='Alanerazza:BAAALgADCgUJBQAAAA==.Althenzdormu:BAAALgAECgYJDQAAAA==.Altruist:BAAALgAECgYJDQABLgAECgcJGAABAH0YAA==.',
Am='Amaethon:BAAALgAECgYJCAAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8gAAIDAAgJcB4QBgCOAgADAAgJcB4QBgCOAgAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8YAAIEAAcJch0fBgBNAgAEAAcJch0fBgBNAgAAAA==.',
Ar='Arathor:BAAALgAECgQJBQAAAA==.Ari:BAABLgAECn8UAAIFAAgJtQUXOwD6AAAFAAgJtQUXOwD6AAAAAA==.Ariyia:BAAALgAECgYJEQAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8YAAQHAAcJJBKQBQBSAQAHAAYJCBWQBQBSAQAIAAEJhwm3IgAsAAAJAAEJsANATAApAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8YAAIKAAcJFgmJBgBIAQAKAAcJFgmJBgBIAQAAAA==.',
Az='Azbogah:BAAALgADCgYJBgAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMgIgCoAAAMAAIJqxMgIgCoAAAuAAQKfx4AAgwACAn+IZERAAQDAAwACAn+IZERAAQDAAAA.',
Be='Beej:BAAALgAECggJDwAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgYJDQAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgIJBwAAAA==.',
Bl='Blightbeard:BAAALgAECgUJDQAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgIJAgABLgAFFAUJDwANAGMRAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgEJAQAAAA==.',
Br='Brut:BAABLgAECn8XAAIOAAgJJx0COQAQAgAOAAgJJx0COQAQAgAAAA==.',
Bu='Bustus:BAABLgAECn8VAAIPAAcJSg5sKABFAQAPAAcJSg5sKABFAQAAAA==.',
Ca='Caroll:BAAALgAECgEJAQAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgQJBgAAAA==.',
Ch='Chilly:BAAALgAECgYJDgAAAA==.Chunt:BAAALgADCgcJCQAAAA==.',
Co='Compliance:BAABLgAECn8YAAIBAAcJfRhvCACvAQABAAcJfRhvCACvAQAAAA==.Corannis:BAAALgAECgcJEwAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECggJHgAQAFgQAA==.',
Cr='Cranberries:BAAALgAECgkJBwAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJEwAGAAAAAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgIJAgAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8QAAIOAAcJkxfXHQCAAQAOAAcJkxfXHQCAAQAAAA==.',
De='Delderach:BAAALgAECgQJBgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8XAAINAAcJbBXSLQCEAQANAAcJbBXSLQCEAQAAAA==.',
Di='Dirkette:BAABLgAECn8gAAIEAAgJ9gMuGAAqAQAEAAgJ9gMuGAAqAQAAAA==.Dirksavoid:BAAALgADCgUJBQABLgAECggJIAAEAPYDAA==.Dixonmayas:BAAALgAECgYJCQAAAA==.',
Do='Dokai:BAABLgAECn8WAAIRAAcJCBUEEAB9AQARAAcJCBUEEAB9AQAAAA==.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgADCgcJCwAAAA==.Dragmartigan:BAAALgAECgQJBgAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCgYJBgAAAA==.Eliance:BAAALgAECgQJBgAAAA==.Elsewhere:BAABLgAECn8WAAIJAAcJaQ3mGQAuAQAJAAcJaQ3mGQAuAQAAAA==.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8UAAISAAYJshPIEwDoAAASAAYJshPIEwDoAAAAAA==.',
Fu='Fusaa:BAABLgAECn8XAAITAAYJsRChPgA2AQATAAYJsRChPgA2AQAAAA==.',
Ga='Gangry:BAAALgAECgQJBgAAAA==.',
Ge='Gerbzarrion:BAAALgAECgQJBgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8fAAIUAAgJVhEMDAB8AQAUAAgJVhEMDAB8AQAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Hawknnin:BAAALgAECgQJBgAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBAAAAA==.Huroona:BAAALgADCgcJDAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJBwAGAAAAAA==.',
Ip='Ipwnallnoobs:BAAALgAECgYJDQAAAA==.',
Ir='Irisila:BAAALgADCgcJAQABLgAECgQJBAAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJBgAAAA==.Jaxsi:BAAALgAECgQJBwAAAA==.Jaypharyn:BAAALgAECgYJDQAAAA==.',
['Jå']='Jåsper:BAAALgAECgYJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8UAAIVAAYJSRavDACPAQAVAAYJSRavDACPAQAAAA==.Kandistars:BAABLgAECn8UAAIWAAYJ7wxLIwDmAAAWAAYJ7wxLIwDmAAAAAA==.Kasia:BAAALgAECgYJDQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8VAAINAAcJlBeEIwC0AQANAAcJlBeEIwC0AQAAAA==.Kirarah:BAAALgAECgcJEwAAAA==.Kirarose:BAACLgAFFH8JAAIXAAQJWQ8ZCAA/AQAXAAQJWQ8ZCAA/AQAuAAQKfxUAAxcABwneHV4WADUCABcABwneHV4WADUCABgAAwmECVpoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8aAAIFAAgJhQiDGQA5AQAFAAgJhQiDGQA5AQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCggJCgAAAA==.',
Ky='Kylia:BAAALgAECgQJBwAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8aAAICAAgJORxKCwBLAgACAAgJORxKCwBLAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8eAAMQAAgJWBC1CABPAQAWAAcJ1A/oLwCHAQAQAAgJVw61CABPAQAAAA==.',
Li='Lizardath:BAABLgAECn8eAAICAAcJTQqQNQA7AQACAAcJTQqQNQA7AQAAAA==.',
Lj='Ljósálfr:BAABLgAECn8gAAIBAAgJ6iDxAgBrAgABAAgJ6iDxAgBrAgAAAA==.',
Lo='Lochramae:BAABLgAECn8aAAISAAcJeRWRDQA3AQASAAcJeRWRDQA3AQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.',
Lu='Lumanoughty:BAAALgADCgcJBwAAAA==.Lunargaze:BAABLgAECn8VAAIOAAcJ7R9oCwAnAgAOAAcJ7R9oCwAnAgAAAA==.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgQJBgAGAAAAAA==.Mamimisan:BAABLgAECn8XAAIDAAYJXB96DwD9AQADAAYJXB96DwD9AQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgUJBgAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgEJAgAAAA==.Mizkat:BAABLgAECn8dAAQQAAgJRxmaBADXAQAQAAgJRxmaBADXAQAZAAEJNQ4SHQA6AAAPAAIJHA2UzwAvAAAAAA==.',
Mo='Mormra:BAABLgAECn8eAAMCAAgJVQroJQCCAQACAAgJVQroJQCCAQAaAAEJ1QHwJQAiAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8dAAQbAAcJsSRiAgCNAgAbAAcJsSRiAgCNAgACAAEJKh7EtwBTAAAaAAEJgwGrmgAXAAAAAA==.',
Na='Naklus:BAAALgADCgMJAwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECgcJCQABLgAECggJHwAUAFYRAA==.',
Nl='Nlani:BAAALgAECgQJBAAAAA==.',
Nu='Nuvi:BAAALgADCgcJDQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pl='Platura:BAABLgAECn8UAAIcAAcJhRf/DgDvAQAcAAcJhRf/DgDvAQAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8YAAIdAAcJ3Q8VBgBeAQAdAAcJ3Q8VBgBeAQAAAA==.Rassaphore:BAAALgAECgIJAgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgYJDQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJFwAOACcdAA==.Rionach:BAABLgAECn8YAAIQAAcJdAeYEACxAAAQAAcJdAeYEACxAAAAAA==.Ritsara:BAAALgAECgQJBwAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAAALgAECgYJEwAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgUJBQAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgYJBwAAAA==.',
Sc='Scoop:BAAALgAECgMJAwAAAA==.',
Se='Seanx:BAABLgAECn8YAAMMAAYJrBwFPwBNAQAMAAYJrBwFPwBNAQAeAAYJghKlDgAWAQAAAA==.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJtBk0SQCvAAANAAIJtBk0SQCvAAAAAA==.Shigurexx:BAABLgAECn8aAAMCAAcJVhpJFgDgAQACAAcJVhpJFgDgAQAaAAYJchK8DgDdAAAAAA==.Shoe:BAABLgAECn8hAAMHAAgJTxmoCgAxAgAHAAcJPhyoCgAxAgAJAAYJihCLQgBHAAAAAA==.',
Si='Sigmandis:BAAALgAECgQJBwAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgYJBwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgMJBgAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAQAAAA==.',
Ta='Taliadrin:BAAALgADCgYJBgAAAA==.Tamarins:BAAALgAECgYJDQAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIQAAgJqCJFAQCQAgAQAAgJqCJFAQCQAgAAAA==.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgADCgcJBwAAAA==.',
To='Toom:BAAALgAECgQJBgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJDgABLgAECggJHwAUAFYRAA==.Trophyhubby:BAABLgAECn8UAAMYAAYJEA0PIAABAQAYAAYJEA0PIAABAQAXAAMJxQGoXABBAAAAAA==.',
Tu='Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDQAAAA==.Tyeriel:BAACLgAFFH8PAAMNAAUJYxHjIwAtAQANAAQJYxHjIwAtAQASAAEJAAD9HwAAAAAuAAQKfxwAAg0ACAn/HtgiALQCAA0ACAn/HtgiALQCAAAA.',
Va='Valat:BAAALgADCgUJBQAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valvet:BAAALgADCgkJIAAAAA==.Vardanis:BAAALgADCgYJBgAAAA==.',
Vi='Vikril:BAAALgADCgkJFQAAAA==.Vincenzo:BAAALgAECgEJAQAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJ2SPkJQBvAgAOAAcJ2SPkJQBvAgAAAA==.Volora:BAAALgAECgEJAQAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
We='Weeblewobble:BAAALgADCgYJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgMJAwAAAA==.William:BAAALgAECgYJDQAAAA==.Windee:BAAALgAECgUJCQAAAA==.',
Wr='Wrast:BAAALgAECgcJEQAAAA==.',
Xy='Xyara:BAABLgAECn8ZAAQdAAgJUhllOwDGAAAdAAMJoBNlOwDGAAALAAQJMx3ZCQCjAAATAAQJSxRheQCRAAAAAA==.Xylaara:BAAALgADCgMJAgAAAA==.',
Ya='Yarine:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.',
Yo='Yoghurt:BAABLgAECn8eAAIfAAgJxh1gBQBlAgAfAAgJxh1gBQBlAgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAAALgAECgQJDAAAAA==.Zatika:BAABLgAECn8aAAIgAAcJjxjlBgCgAQAgAAcJjxjlBgCgAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAAALgAECgQJBgAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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

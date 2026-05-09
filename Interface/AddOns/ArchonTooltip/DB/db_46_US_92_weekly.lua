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

local lookup = {'Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Druid-Balance','DemonHunter-Havoc','Evoker-Preservation','Rogue-Subtlety','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Rogue-Assassination','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Warlock-Destruction','Hunter-Survival','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Hunter-Marksmanship','Priest-Discipline','Unknown-Unknown','Mage-Arcane','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Druid-Feral','Warlock-Affliction','Rogue-Outlaw','Mage-Fire','Warrior-Protection','DeathKnight-Blood','Druid-Restoration','Monk-Brewmaster','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE4OgAjAgABAAkJuxE4OgAjAgAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAAALgAECgUJBgABLgAECgkJKgACAAATAA==.',
Ae='Aestris:BAAALgADCgkJLQAAAA==.Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8sAAIDAAgJWSBBDwCDAgADAAgJWSBBDwCDAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgADCgEJAQABLgAECgkJMgAEAKIdAA==.Amarndeus:BAAALgADCgMJAwAAAA==.',
An='Anmodru:BAAALgAECgYJBgAAAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aotc:BAABLgAECn8WAAIFAAcJxg1nKwBsAQAFAAcJxg1nKwBsAQAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAAALgAFFAEJAQAAAA==.Aquílés:BAAALgAECgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn8qAAIGAAgJyhv1AwCAAgAGAAgJyhv1AwCAAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAUJCAAHABcOAA==.Ariandrel:BAAALgAECgcJEgAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Asellus:BAAALgADCgEJAQAAAA==.Ashraun:BAAALgAECgMJAwAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8pAAIFAAgJAhvjBgAyAgAFAAgJAhvjBgAyAgAAAA==.',
Au='Aubrii:BAAALgADCgYJCAAAAA==.Aukatsang:BAACLgAFFH8HAAIIAAQJqRnADgD6AAAIAAQJqRnADgD6AAAuAAQKfyMAAggACQnBIl0BAKMDAAgACQnBIl0BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.',
Az='Azymor:BAAALgADCggJDgAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIJAAgJ9xz+FAClAgAJAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIIAAQJvRwFBgBfAQAIAAQJvRwFBgBfAQAuAAQKfyQAAggACAndHowJAN8CAAgACAndHowJAN8CAAAA.Baladeva:BAABLgAECn8pAAIKAAgJRB36BQALAgAKAAgJRB36BQALAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECggJLAADAFkgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beersnob:BAABLgAECn8cAAILAAgJMhJpGwBvAQALAAgJMhJpGwBvAQAAAA==.Benjam:BAACLgAFFH8KAAIMAAUJdhgpFgBSAQAMAAUJdhgpFgBSAQAuAAQKfyIAAgwABwk2I0gZAL0CAAwABwk2I0gZAL0CAAAA.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn8rAAIDAAgJRgwfRgBzAQADAAgJRgwfRgBzAQAAAA==.Bigsteve:BAABLgAECn8gAAMNAAgJOBj6CAC9AQAJAAYJERvkMwDaAQANAAgJ1RL6CAC9AQAAAA==.',
Bl='Blanket:BAABLgAFFH8JAAMHAAMJNwiSDwD0AAAHAAMJqQWSDwD0AAAOAAEJ0QliCgBTAAAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJBwAJAD4ZAA==.',
Br='Brewtel:BAAALgADCgcJBwAAAA==.',
Bu='Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8fAAIPAAkJkRl+CQCVAgAPAAkJkRl+CQCVAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgEJAQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8bAAQGAAkJTQb4IgBhAQAGAAgJawX4IgBhAQAQAAMJGgi+MgCAAAARAAEJEwYFXAAyAAAAAA==.Calizon:BAAALgAECggJDgAAAA==.Calogero:BAAALgADCgEJAQAAAA==.Camc:BAAALgAECgQJCQAAAA==.Canowhoopass:BAABLgAECn8bAAICAAYJvgr7MADvAAACAAYJvgr7MADvAAAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8PAAIMAAQJGhPiHAA3AQAMAAQJGhPiHAA3AQAuAAQKfy0AAgwACQk+H/IPAP8CAAwACQk+H/IPAP8CAAAA.Cereas:BAABLgAECn8pAAIFAAcJ0RiPDwCJAQAFAAcJ0RiPDwCJAQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgMJBQAAAA==.Chuckrutis:BAABLgAECn8aAAIQAAYJUh5tDAAUAgAQAAYJUh5tDAAUAgAAAA==.',
Cl='Cliché:BAAALgAECgQJBAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8PAAISAAUJthq7DwBbAQASAAUJthq7DwBbAQAuAAQKfyIAAhIACQnhIHUCAHEDABIACQnhIHUCAHEDAAAA.',
Co='Coldandwet:BAAALgAFFAIJAwAAAA==.Combination:BAABLgAECn8rAAITAAgJvx2SAQBiAgATAAgJvx2SAQBiAgABLgAFFAYJFgADAIgZAA==.Constrace:BAAALgAECgMJAwAAAA==.Corvenall:BAABLgAECn8zAAIQAAgJmAwuBgBtAQAQAAgJmAwuBgBtAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECgQJBwAAAA==.Crossbow:BAABLgAECn8tAAISAAkJmB9JCwCHAgASAAkJmB9JCwCHAgAAAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECggJFQAUADsTAA==.Darkluster:BAAALgADCgEJAQAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAAALgAECgYJEgAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demorian:BAAALgAECgEJAQABLgAECggJHwAVABgMAA==.Deondre:BAAALgAECgMJBQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.',
Di='Diehappy:BAAALgAECgUJBgAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgQJBgAAAA==.',
Do='Dompal:BAAALgAECgMJBgABLgAFFAUJDwAWAHofAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAgJIgAXAEQmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drybonez:BAABLgAECn8UAAIXAAYJzwiAoADSAAAXAAYJzwiAoADSAAAAAA==.Drylie:BAACLgAFFH8NAAMSAAUJeyJ1CAB7AQASAAUJeyJ1CAB7AQAYAAEJwBmXJQBSAAAuAAQKfyMAAxgACQmGJMoJAAYDABgACAmdIsoJAAYDABIAAwnsIn1KAC0BAAAA.Dràgonkíng:BAAALgAECgUJCwAAAA==.',
Dt='Dtinnel:BAABLgAECn8aAAIJAAgJrhl+DAAjAgAJAAgJrhl+DAAjAgABLgAECgcJHgAZAOoaAA==.',
Du='Dumbledussy:BAABLgAECn8fAAIVAAgJGAyeGAB4AQAVAAgJGAyeGAB4AQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.',
Ed='Edanor:BAAALgADCgEJAQABLgAECgkJEgAaAAAAAA==.',
Eg='Ego:BAABLgAECn8uAAIJAAkJMiSwAABMAwAJAAkJMiSwAABMAwAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgADCgQJBAAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAXAHciAA==.Emmone:BAAALgAECgUJCAAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgEJAgAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAABLgAECn8yAAIEAAkJoh2MBACsAgAEAAkJoh2MBACsAgAAAA==.',
Fe='Feebeeboofae:BAAALgADCgYJBgAAAA==.Felaz:BAABLgAECn8pAAIbAAgJQR/4AABjAgAbAAgJQR/4AABjAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.',
Fi='Fingerguns:BAABLgAECn8bAAQZAAgJYBeuCQA8AgAZAAgJYBeuCQA8AgAcAAMJdwjnZgCRAAAVAAMJIAgnQgBqAAAAAA==.Fionaa:BAABLgAECn8dAAMBAAkJMAV0QQBlAQABAAkJBQV0QQBlAQATAAEJsAfmeAAqAAAAAA==.Fiyona:BAAALgAECgIJAwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAABLgAECn8WAAMdAAcJgwV1dgD0AAAdAAcJLQR1dgD0AAAeAAMJ6gfzEACIAAAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAABLgAFFH8IAAIfAAMJsBa5EgCzAAAfAAMJsBa5EgCzAAAAAA==.Frikilatar:BAAALgAECgEJAgAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAaAAAAAA==.Frrank:BAACLgAFFH8PAAINAAUJESTHAgCVAQANAAUJESTHAgCVAQAuAAQKfysAAg0ACQmNJGEAALQDAA0ACQmNJGEAALQDAAAA.',
Fu='Fullerene:BAAALgADCgYJEQAAAA==.',
Ga='Galcain:BAABLgAECn8gAAQSAAgJAiL3BwARAwASAAgJvSH3BwARAwAUAAQJxxNPHAAiAQAYAAMJVBrFYAC9AAAAAA==.',
Gh='Ghostmain:BAAALgAECgIJAwABLgAECgYJDQAaAAAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8lAAIXAAgJhxN3NwDEAQAXAAgJhxN3NwDEAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.',
Go='Gorizarev:BAAALgAECgQJCAAAAA==.',
Gr='Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn8qAAIgAAgJSRCwCACiAQAgAAgJSRCwCACiAQAAAA==.',
Gu='Gudetama:BAAALgAECggJEwAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgQJBAAAAA==.Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn8qAAIDAAgJ6h1DGgArAgADAAgJ6h1DGgArAgAAAA==.Hamahara:BAAALgADCgMJAwAAAA==.Hanma:BAACLgAFFH8OAAIdAAYJaBcuCQC/AQAdAAYJaBcuCQC/AQAuAAQKfygAAh0ACQn7HgssAIgCAB0ACQn7HgssAIgCAAAA.Harribel:BAABLgAECn8lAAIXAAgJcA5RTQCBAQAXAAgJcA5RTQCBAQAAAA==.',
He='Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAAALgAECgcJEQAAAA==.Hitachitotem:BAACLgAFFH8MAAICAAMJxgqaEQDeAAACAAMJxgqaEQDeAAAuAAQKfxkAAgIACAmZGlkaAEACAAIACAmZGlkaAEACAAAA.Hizzon:BAAALgADCgcJCgAAAA==.',
Ho='Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAAALgAECggJDgAAAA==.Holymaet:BAAALgADCgEJAQABLgAECggJKgAJAKMjAA==.Holyphatso:BAAALgADCgMJAwABLgAECggJIAAcAHMgAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8WAAIXAAcJfRUUQwCeAQAXAAcJfRUUQwCeAQAAAA==.',
In='Inflikted:BAABLgAECn8cAAIdAAgJeQjXRwBkAQAdAAgJeQjXRwBkAQAAAA==.Interwebz:BAAALgAECggJDwAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgADCgcJBwAaAAAAAA==.',
Je='Jehannum:BAABLgAECn8cAAICAAgJlA2aIQBEAQACAAgJlA2aIQBEAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJDgAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAAALgAFFAEJAQABLgAFFAQJDwAPAIIcAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIVAAgJ0RfxDgDeAQAVAAgJ0RfxDgDeAQAAAA==.',
Ka='Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgADCgYJBgAAAA==.Katarena:BAABLgAECn8mAAIfAAgJog4VHgCWAQAfAAgJog4VHgCWAQAAAA==.Kathyra:BAABLgAECn8aAAMBAAgJdQqRPwBrAQABAAgJdQqRPwBrAQAhAAEJ7wEiNwAnAAAAAA==.Kavax:BAABLgAECn8YAAIfAAgJ+BKkFADsAQAfAAgJ+BKkFADsAQAAAA==.',
Ke='Keel:BAAALgAECgEJAQAAAA==.Keeller:BAACLgAFFH8RAAIDAAUJaA96GwA/AQADAAUJaA96GwA/AQAuAAQKfzMAAgMACAmTH2EdABcCAAMACAmTH2EdABcCAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kentyr:BAABLgAECn8jAAMHAAgJ+wzjFABnAQAHAAgJ+wzjFABnAQAiAAIJZwGADgA0AAAAAA==.',
Kh='Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgADCgIJAgABLgAECggJKgAJAKMjAA==.Kinký:BAABLgAECn8gAAMJAAgJSBGnHgB1AQAJAAgJtRCnHgB1AQANAAEJ2xQeOABBAAABLgAECgUJCwAaAAAAAA==.Kiraelis:BAABLgAECn8bAAIYAAgJ0A3NCABxAQAYAAgJ0A3NCABxAQAAAA==.Kiss:BAAALgADCgEJAQABLgAECgQJBAAaAAAAAA==.Kivea:BAABLgAECn8YAAMXAAgJ6A+7QgCfAQAXAAgJ6A+7QgCfAQAjAAEJ8gZICwAzAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECgcJBwAAAA==.Konagda:BAAALgADCgcJDQAAAA==.Korvoh:BAABLgAECn8rAAMZAAgJ/xyKBQCoAgAZAAgJ9RyKBQCoAgAcAAMJUxeIXQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8ZAAICAAYJNyTRFAB3AgACAAYJNyTRFAB3AgAAAA==.',
Ku='Kumonk:BAABLgAECn8UAAIIAAYJBgYELgDPAAAIAAYJBgYELgDPAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn8rAAISAAgJOSDWDAB2AgASAAgJOSDWDAB2AgAAAA==.',
['Kì']='Kìn:BAAALgAECgYJDQAAAA==.',
La='Lampion:BAABLgAECn8WAAIFAAgJUwghOgAZAQAFAAgJUwghOgAZAQAAAA==.Lasstchance:BAAALgAECgUJBgAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8XAAIBAAcJ0xvSKQC+AQABAAcJ0xvSKQC+AQAAAA==.',
Le='Leijona:BAAALgAECgEJAQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8ZAAIkAAYJkA1fGgDqAAAkAAYJkA1fGgDqAAAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMfAAgJJROAKADqAQAfAAgJJROAKADqAQADAAUJDwgBlQDEAAAAAA==.Lilwagyu:BAAALgAECgEJAQAAAA==.Linds:BAABLgAECn8nAAMfAAgJTB2OHgAjAgAfAAgJTB2OHgAjAgADAAYJ4gsEfAD0AAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgYJDwAAAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8VAAMHAAYJExdWFQBiAQAHAAYJExdWFQBiAQAOAAEJhxDzHwAzAAAAAA==.Lorralen:BAAALgAECgcJCAAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8pAAIIAAgJPhykCAA2AgAIAAgJPhykCAA2AgAAAA==.',
Lu='Luber:BAAALgAECggJDwAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn8uAAIlAAkJ+ySvAABDAwAlAAkJ+ySvAABDAwAAAA==.Luxzy:BAAALgADCggJEgAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8YAAImAAgJ5SGDBwDVAgAmAAgJ5SGDBwDVAgAAAA==.Marbleous:BAABLgAFFH8HAAIJAAMJPhn/FQD/AAAJAAMJPhn/FQD/AAAAAA==.Marina:BAAALgADCgcJDQAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECggJFAAhAOQfAA==.Melhina:BAAALgAECgUJBQABLgAECgcJIgAhAFAXAA==.Memisstotem:BAABLgAECn8XAAIPAAcJ6xk5GQDoAQAPAAcJ6xk5GQDoAQAAAA==.Merle:BAABLgAECn8qAAMJAAgJoyMrCABoAgAJAAgJTiErCABoAgANAAMJLx7zFAASAQAAAA==.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAAALgAFFAEJAQAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAAALgAECgUJCwAAAA==.Mistborn:BAABLgAECn8mAAQcAAgJ+SIiCQC5AgAcAAgJ+SIiCQC5AgAZAAQJ1RyFKQBMAQAVAAIJsBXDUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn8jAAIgAAgJGBNHBwDEAQAgAAgJGBNHBwDEAQAAAA==.Monkjamin:BAAALgAFFAEJAQAAAA==.Moolimbo:BAABLgAECn8gAAICAAgJthVnEQDUAQACAAgJthVnEQDUAQAAAA==.Mooseboy:BAABLgAECn8kAAIgAAgJTx68AgB0AgAgAAgJTx68AgB0AgAAAA==.Mooserton:BAABLgAECn8hAAMDAAYJrA+qcAALAQADAAYJrA+qcAALAQAfAAUJcguaNwDnAAAAAA==.Mootalstrike:BAABLgAECn8hAAIJAAgJZxNIFwCtAQAJAAgJZxNIFwCtAQAAAA==.Moshworm:BAABLgAECn8gAAIEAAcJDwt3KAD+AAAEAAcJDwt3KAD+AAAAAA==.',
Mu='Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJDwASALYaAA==.',
Na='Nalaxx:BAAALgADCgkJDAAAAA==.Natsumi:BAAALgAECgQJBAAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIRAAYJVQPKQwDRAAARAAYJVQPKQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn8tAAIXAAgJ8BkCKQD+AQAXAAgJ8BkCKQD+AQAAAA==.Neuroticaine:BAABLgAECn8rAAMVAAgJIxYrHQBSAQAVAAYJoBgrHQBSAQAZAAQJGwY1OQBqAAAAAA==.Nev:BAACLgAFFH8MAAMSAAQJZiGyBACXAQASAAQJZiGyBACXAQAYAAMJ6AU0GQDAAAAuAAQKfyEAAxIACAnbIsYjAC8CABIABwkjIsYjAC8CABgABwmhHKokAAICAAAA.Nexassin:BAAALgAFFAIJAgAAAA==.',
Ni='Nico:BAABLgAECn8VAAIUAAgJOxMQEQCxAQAUAAgJOxMQEQCxAQAAAA==.Nimz:BAABLgAECn8UAAQhAAgJ5B/KAACcAgAhAAgJ3R/KAACcAgATAAcJIRowBADMAQABAAIJrRPG7ACBAAAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAABLgAECn8YAAIHAAcJwhwCJQDRAQAHAAcJwhwCJQDRAQAAAA==.Noradia:BAAALgAECgMJBAAAAA==.Noxxidari:BAABLgAECn8fAAMMAAgJyhDUOgBLAQAMAAgJyhDUOgBLAQAWAAIJuRT4HAA+AAAAAA==.Noxxus:BAABLgAECn8eAAIKAAkJvBrSBwDVAQAKAAkJvBrSBwDVAQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymphis:BAAALgADCgYJCQAAAA==.Nymz:BAAALgAECgMJAwABLgAECggJFAAhAOQfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBQAAAA==.',
Of='Offended:BAAALgADCgcJBgAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgQJBAABLgAECggJIAACALYVAA==.',
On='Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCAAfALAWAA==.Oratherah:BAABLgAFFH8IAAIlAAMJliN+EgDOAAAlAAMJliN+EgDOAAAAAA==.Orbs:BAAALgADCgYJBgAAAA==.Orchist:BAABLgAECn8YAAIJAAgJMR7KBwBvAgAJAAgJMR7KBwBvAgAAAA==.',
Oz='Ozôls:BAAALgAECgEJAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn8rAAIeAAgJKAfVCAASAQAeAAgJKAfVCAASAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECggJIAACALYVAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECggJDwAaAAAAAA==.Pitchblende:BAABLgAECn8nAAIfAAgJ7hI/GADKAQAfAAgJ7hI/GADKAQAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAQJBwAdAKUiAA==.Porthub:BAABLgAECn8gAAIXAAgJZQm6ZQBGAQAXAAgJZQm6ZQBGAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBgAAAA==.',
Pu='Purejoy:BAAALgAECgYJCwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAAALgAECgIJAgAAAA==.Rajak:BAAALgAECgEJAQAAAA==.Raph:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8PAAInAAUJRyMbBgCXAQAnAAUJRyMbBgCXAQAuAAQKfzAAAicACQkyI7wBAIwDACcACQkyI7wBAIwDAAAA.',
Re='Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCAAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAInAAYJihvBJwDIAQAnAAYJihvBJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAAALgAECgYJBgAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBAAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgADCgYJBwAAAA==.',
Ro='Rockyx:BAAALgAECgQJBAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAMJBwAlAPQlAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAABLgAECn8iAAIdAAgJTBmDawC0AQAdAAgJTBmDawC0AQABLgAECgcJHgAZAOoaAA==.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAAALgAECgYJDAAAAA==.Salezar:BAAALgAECgkJEgAAAA==.Sandoud:BAAALgAECgkJEgAAAA==.Sapientia:BAABLgAECn8eAAIDAAgJOwWebAAUAQADAAgJOwWebAAUAQAAAA==.Saragon:BAAALgAECgUJBQABLgAECgcJKQAFANEYAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAABLgAECn8hAAMfAAgJWhjFGQBFAgAfAAgJWhjFGQBFAgADAAEJ8g8hMgE/AAAAAA==.',
Se='Sebaux:BAAALgAECgQJBQAAAA==.Segur:BAAALgAECgYJDwAAAA==.Selenesul:BAABLgAECn8eAAMDAAgJLBeDIgD7AQADAAgJLBeDIgD7AQAKAAMJTAyjNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8HAAIIAAMJDhS3DgD6AAAIAAMJDhS3DgD6AAAuAAQKfyMAAggACAl4H14GAGsCAAgACAl4H14GAGsCAAEuAAUUBAkJAAgA+hEA.',
Sh='Shadowdrake:BAAALgAECgYJBwAAAA==.Shadowheàrt:BAAALgAECgUJCgAAAA==.Shadowshifty:BAAALgAECgQJDQAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAECgUJBQAAAA==.Shagi:BAAALgAECgYJEgAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharroz:BAABLgAECn8dAAMeAAcJiB1nAwBWAgAeAAcJiB1nAwBWAgAlAAQJRw7lJACgAAAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8eAAMZAAcJ6hq4DgDmAQAZAAcJ6hq4DgDmAQAVAAEJJQKVaQAlAAAAAA==.Shockybalboa:BAAALgAECgYJBgAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8sAAICAAkJ9g2hEwC6AQACAAkJ9g2hEwC6AQAAAA==.Skyded:BAABLgAECn8nAAIdAAgJJxppHQAYAgAdAAgJJxppHQAYAgAAAA==.Skyknight:BAABLgAECn8fAAIJAAkJiBNcDgAIAgAJAAkJiBNcDgAIAgAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8HAAMUAAMJiRTaDQAIAQAUAAMJiRTaDQAIAQAYAAIJBwtbEwCPAAAuAAQKfzIAAxQACQmyIOgBAOUCABQACQkpHugBAOUCABgACAnXHk4DACgCAAAA.',
Sn='Snapahead:BAAALgADCgIJAgAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8dAAIMAAgJSBz9EgAlAgAMAAgJSBz9EgAlAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECgEJAQAAAA==.Soralas:BAAALgAECgMJBAAAAA==.',
Sp='Spaazz:BAABLgAECn8YAAIDAAgJlx8aEQByAgADAAgJlx8aEQByAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.',
St='Starweaver:BAAALgAECgcJEwAAAA==.Stellmarine:BAABLgAECn8dAAIEAAkJyxofCgAqAgAEAAkJyxofCgAqAgAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgQJBgAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8nAAMoAAgJUhpcBgDkAQAoAAgJChhcBgDkAQAEAAYJBBrhKgCqAQAAAA==.',
Su='Sunamé:BAAALgAECgMJAwAAAA==.',
Sw='Swaazil:BAABLgAECn8gAAIXAAgJlA9BWQBiAQAXAAgJlA9BWQBiAQAAAA==.Swan:BAAALgAFFAIJBAAAAA==.Swiftsama:BAAALgAECgEJAQAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8UAAIMAAYJDgpTXwDhAAAMAAYJDgpTXwDhAAAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAABLgAECn8YAAMcAAgJFRkJDQAVAgAcAAgJFRkJDQAVAgAVAAEJPhXkYAA2AAAAAA==.Tanazir:BAEALgAECgYJDQAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAAALgAECgQJBwAAAA==.',
Te='Techytechy:BAABLgAECn8WAAITAAcJOx7UAgAOAgATAAcJOx7UAgAOAgAAAA==.Tennmage:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIDAAkJKBlXRQATAgADAAkJKBlXRQATAgAAAA==.',
Ti='Tigermaster:BAAALgAECgYJDQAAAA==.Tilamano:BAABLgAECn8sAAQTAAgJLiU9AQCBAgATAAcJaSU9AQCBAgAhAAcJqCLGAQAzAgABAAcJ1SP2HAACAgAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8JAAMLAAQJngnHEwD2AAALAAQJngnHEwD2AAAnAAMJbQFyKQCjAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMSAAcJOCMYHwBLAgASAAcJciIYHwBLAgAYAAYJMSMOIgAVAgABLgAECggJDgAaAAAAAA==.Tonycheeks:BAAALgAECgIJAgAAAA==.Toogie:BAAALgAECgIJAwABLgAECggJGQAnANAgAA==.Tookie:BAAALgADCgYJBgABLgAECggJGQAnANAgAA==.Toophie:BAAALgADCgIJAgABLgAECggJGQAnANAgAA==.Toopie:BAABLgAECn8ZAAMnAAgJ0CBlCwDXAgAnAAgJySBlCwDXAgAIAAUJbxkYOAA9AQAAAA==.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8YAAImAAcJ1Bu1GgDuAQAmAAcJ1Bu1GgDuAQAAAA==.Tryath:BAAALgAECgcJEAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8JAAITAAMJxxNEBADtAAATAAMJxxNEBADtAAAuAAQKfyQAAhMACQl+G2oCAOUCABMACQl+G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIUAAkJCh81AwD6AgAUAAkJCh81AwD6AgAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJCgAAAA==.',
Um='Umbrute:BAABLgAECn8kAAIMAAkJsh1dEwDlAgAMAAkJsh1dEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgYJFAAXAJ0TAA==.',
Va='Valcristo:BAABLgAECn8tAAIKAAgJMySLAQDDAgAKAAgJMySLAQDDAgAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgIJAgABLgAECgYJEgAaAAAAAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8dAAMHAAgJ2xNsFABtAQAHAAcJxhFsFABtAQAOAAUJ1BF/EwDJAAAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8kAAISAAgJ7xnoIQDRAQASAAgJ7xnoIQDRAQAAAA==.',
Vi='Vicariana:BAACLgAFFH8PAAIZAAUJaCQXBQAIAgAZAAUJaCQXBQAIAgAuAAQKfyQAAhkACQneJhEAAPkDABkACQneJhEAAPkDAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAECgYJCwAAAA==.Vidette:BAAALgADCgYJCwAAAA==.Viduus:BAAALgAECgMJAwABLgAECggJFAAhAOQfAA==.Viv:BAABLgAECn8jAAMKAAgJ5SJeAwBsAgAKAAcJLiReAwBsAgADAAYJEiNSOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8UAAIDAAYJCwUuigDYAAADAAYJCwUuigDYAAAAAA==.Voldermort:BAAALgAECgEJAQAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAMJAwAaAAAAAA==.Warrendemon:BAACLgAFFH8NAAIMAAUJpiTTCgCcAQAMAAUJpiTTCgCcAQAuAAQKfy0AAwwACQkDJroBAMADAAwACQkDJroBAMADAAUAAwn9InZDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIXAAkJUBOqUgA/AgAXAAkJUBOqUgA/AgAAAA==.Wildheart:BAABLgAECn8UAAMgAAcJsh4IBgDsAQAgAAcJTh4IBgDsAQAoAAMJ+xTrFQC4AAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.',
Wo='Wowbelly:BAABLgAECn8VAAILAAcJghs9FgARAgALAAcJghs9FgARAgAAAA==.Wowbellyjr:BAAALgAECgYJCwABLgAECgcJFQALAIIbAA==.',
Xa='Xaanii:BAAALgADCgcJBwAAAA==.Xandon:BAAALgAECgQJBQAAAA==.',
Xo='Xonk:BAACLgAFFH8LAAIhAAUJ2A8LAQA7AQAhAAUJ2A8LAQA7AQAuAAQKfxoAAiEACAnPICwBAPECACEACAnPICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgYJEgAaAAAAAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgQJCQAAAA==.',
Yu='Yuuna:BAAALgAECgMJBQAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAAALgAECgYJDQAAAA==.Zaps:BAABLgAECn8eAAIpAAgJIyMzAQDbAgApAAgJIyMzAQDbAgAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCggJCQAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8UAAIXAAYJSBKsYgBMAQAXAAYJSBKsYgBMAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn8pAAMPAAgJvQfuOwAVAQAPAAgJvQfuOwAVAQACAAYJywhyMwDjAAAAAA==.Zenreto:BAABLgAECn8rAAIOAAgJpRyMAgAyAgAOAAgJpRyMAgAyAgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8NAAIXAAQJjiFgFwCCAQAXAAQJjiFgFwCCAQAuAAQKfysAAhcACAnAJGwSADkDABcACAnAJGwSADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8OAAIpAAUJ3RonAgBlAQApAAUJ3RonAgBlAQAuAAQKfxwAAikACQl3IcMAAI8DACkACQl3IcMAAI8DAAAA.',
['Îl']='Îllîdan:BAAALgAFFAEJAQAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8oAAMBAAgJrx5+DQCAAgABAAgJrx5+DQCAAgATAAQJGwjAQQCuAAAAAA==.',
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

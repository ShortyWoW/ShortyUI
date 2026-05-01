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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Arcane','Monk-Mistweaver','Paladin-Retribution','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Hunter-Marksmanship','Hunter-Survival','Druid-Feral','Druid-Restoration','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Monk-Windwalker','Rogue-Assassination','Warrior-Protection','Paladin-Holy','Druid-Guardian','Shaman-Elemental','Druid-Balance','Rogue-Subtlety','Paladin-Protection','Evoker-Preservation','DeathKnight-Frost','Shaman-Enhancement','Priest-Discipline','Warrior-Arms',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Aborc:BAAALgAECgQJCAAAAA==.Abraxøs:BAACLgAFFH8HAAIBAAQJxBFmIQCZAAABAAQJxBFmIQCZAAAuAAQKfxUAAwIACAnpHRYKAD0CAAIABwl5HhYKAD0CAAEAAQmHGsdaAFEAAAAA.',
Ad='Adiris:BAAALgAECgcJBwAAAA==.Aduranu:BAAALgAECgcJCAAAAA==.',
Ae='Aegeax:BAAALgAECgMJBwAAAA==.Aethers:BAAALgADCgYJBwAAAA==.Aethrion:BAAALgADCgQJBAAAAA==.',
Ai='Aiou:BAAALgAECgYJDgABLgAFFAEJAQADAAAAAA==.Airtrun:BAAALgADCgEJAQAAAA==.',
Al='Alaalla:BAAALgAECgUJDwAAAA==.Alasttra:BAAALgAECgUJCAAAAA==.Alesallie:BAAALgAECgQJBgAAAA==.Alexie:BAAALgAECgQJCQAAAA==.Alleriand:BAAALgADCgcJBwAAAA==.Alleryn:BAAALgADCgkJDQAAAA==.Alpine:BAAALgAECggJCwAAAA==.Alunaarn:BAAALgADCgMJCQAAAA==.',
Am='Amandagarcia:BAAALgAECgQJCAABLgAFFAEJAQADAAAAAA==.Ambermage:BAAALgADCgUJDQAAAA==.Amerese:BAAALgADCgEJAQAAAA==.Amourantha:BAAALgADCggJCwAAAA==.',
An='Andersdame:BAABLgAECn8VAAIEAAcJARWdOgAoAQAEAAcJARWdOgAoAQAAAA==.Anish:BAAALgAECgEJAQAAAA==.Anrot:BAAALgADCgUJBgAAAA==.Anthonyisme:BAABLgAECn8UAAIFAAYJIAeBbAABAQAFAAYJIAeBbAABAQAAAA==.',
Ao='Aon:BAAALgAECgQJBwAAAA==.',
Ar='Araels:BAABLgAECn8XAAMGAAYJiAxOCwDiAAAGAAYJiAxOCwDiAAAHAAMJ6gSexQBvAAAAAA==.Arindoril:BAAALgADCgYJDAAAAA==.Arktyh:BAABLgAECn8iAAIIAAcJ5B2RAwAwAgAIAAcJ5B2RAwAwAgAAAA==.Aryndinnin:BAACLgAFFH8OAAIJAAQJ5w9YCQAhAQAJAAQJ5w9YCQAhAQAuAAQKfx8AAgkACAkWHakLAJcCAAkACAkWHakLAJcCAAAA.',
As='Asdar:BAAALgAECgYJCAAAAA==.Asherah:BAACLgAFFH8FAAIBAAMJOAmmGQDcAAABAAMJOAmmGQDcAAAuAAQKfxgAAwIACQn7CgoaAGQBAAIABwkeDAoaAGQBAAEABgkpCVs1AIMAAAAA.Ashketchums:BAAALgADCgcJBwAAAA==.Astralrepaul:BAAALgAECgYJDwAAAA==.',
At='Attincy:BAAALgADCggJDwAAAA==.',
Au='Augtistic:BAACLgAFFH8GAAIBAAMJBxmtEAD8AAABAAMJBxmtEAD8AAAuAAQKfxYAAgEACAlJIjkKANMCAAEACAlJIjkKANMCAAAA.',
Ax='Axelofóðinn:BAABLgAECn8lAAIKAAgJJA/SLACOAQAKAAgJJA/SLACOAQAAAA==.',
Ay='Ayah:BAABLgAECn8eAAMLAAgJ7BqjBgBNAgALAAgJ7BqjBgBNAgAMAAMJ6AriKQCxAAAAAA==.Ayayrahn:BAAALgAECgMJAgAAAA==.',
Az='Azerfrost:BAAALgAECgIJAgAAAA==.Azogothar:BAAALgADCggJGQAAAA==.Aztinuz:BAAALgADCgUJBQAAAA==.',
Ba='Babygerl:BAAALgADCgIJAgAAAA==.Badbuny:BAAALgAECgYJCwAAAA==.Badger:BAAALgAECgMJAwAAAA==.Bahlz:BAAALgADCggJDQAAAA==.Bareca:BAAALgAECgUJBAAAAA==.Barnbek:BAAALgADCgQJCAAAAA==.Barode:BAAALgADCgEJAQAAAA==.',
Be='Bearenstein:BAAALgAECgQJBgAAAA==.Beccaw:BAAALgADCgUJCAAAAA==.Beccky:BAAALgADCgEJAQAAAA==.Beginners:BAAALgADCgEJAQAAAA==.Benthelius:BAAALgADCgkJGQAAAA==.Bestial:BAAALgADCgkJDwAAAA==.Bevicia:BAAALgAECgYJEgAAAA==.',
Bi='Biggrim:BAAALgAECgIJAgAAAA==.Bigtotemz:BAAALgADCgIJAgAAAA==.Biiwaabik:BAAALgADCgcJDAAAAA==.Binkey:BAAALgADCgQJBAAAAA==.Bitsotig:BAAALgAECgIJAgAAAA==.',
Bj='Bjarkes:BAAALgADCgIJAgAAAA==.',
Bl='Blap:BAAALgADCgEJAQAAAA==.Blemish:BAAALgAECgYJDAAAAA==.Bloodfm:BAAALgAECgMJAwAAAA==.Bloodlordz:BAAALgADCgYJDQAAAA==.Bloodology:BAAALgAECgEJAgABLgAECgYJDQADAAAAAA==.Bloodscum:BAAALgADCgcJCAAAAA==.Bloodsham:BAAALgAECgYJDQAAAA==.Blordz:BAAALgADCgYJCwAAAA==.Bluelicht:BAABLgAECn8cAAINAAcJ7BuZTgAHAgANAAcJ7BuZTgAHAgABLgAECggJDQADAAAAAA==.Bluphantom:BAAALgAECgIJBAAAAA==.Blym:BAAALgAECgQJBAAAAA==.',
Bo='Boodiica:BAABLgAECn8bAAIOAAYJJhe4DgAoAQAOAAYJJhe4DgAoAQAAAA==.Boom:BAAALgADCgEJAQAAAA==.Bootyism:BAAALgAECgYJDAAAAA==.',
Br='Brandofig:BAAALgAECgUJCQAAAA==.Brauman:BAAALgAECgIJAgAAAA==.Braynia:BAAALgAECggJDAAAAA==.Brazo:BAABLgAECn8kAAIPAAgJriHMAgCpAgAPAAgJriHMAgCpAgAAAA==.Brazzinoth:BAAALgADCgEJAQABLgAECggJJAAPAK4hAA==.Broxxigarr:BAAALgAECgQJBQAAAA==.',
Bu='Bucky:BAAALgADCgcJBwAAAA==.Buhlz:BAAALgAECgQJCQAAAA==.Bullybane:BAABLgAECn8VAAIKAAcJrwxbTwAeAQAKAAcJrwxbTwAeAQAAAA==.Buri:BAABLgAECn8VAAMOAAYJVxRIEAATAQAOAAYJVxRIEAATAQANAAMJlwi39QCRAAAAAA==.Buzzslc:BAAALgAECgQJBAAAAA==.',
By='Bytebait:BAAALgADCgUJCgAAAA==.',
Ca='Caelista:BAAALgADCgUJBQAAAA==.Caktan:BAAALgADCgYJCgAAAA==.Calahunts:BAACLgAFFH8KAAIEAAQJ5RAfDwBBAQAEAAQJ5RAfDwBBAQAuAAQKfyoABAQACAlRJEwMAN8CAAQACAlRJEwMAN8CABAAAglwIqlmAKQAABEAAQnCD6ksAEQAAAAA.Calatath:BAAALgAECgMJBgABLgAFFAQJCgAEAOUQAA==.Castiana:BAAALgADCgQJBAAAAA==.Catmint:BAAALgADCgQJBAAAAA==.',
Ce='Celandria:BAAALgADCgkJFQAAAA==.Celical:BAAALgADCgMJAwAAAA==.Celize:BAABLgAECn8WAAMSAAcJ9R27CQA1AgASAAcJ9R27CQA1AgATAAYJgxUwIgBwAQAAAA==.Cerollan:BAAALgADCgUJBQAAAA==.',
Ch='Cheekfreak:BAAALgADCgUJBgABLgAECgYJDAADAAAAAA==.Cheeto:BAAALgADCgkJCwAAAA==.Chenna:BAAALgAECgEJAwAAAA==.Chewwybot:BAAALgADCgMJAwAAAA==.Chifoxx:BAAALgAECgYJCwABLgAECggJDgADAAAAAA==.Chokeahoa:BAAALgADCgEJAQAAAA==.Chorgin:BAAALgADCgEJAQAAAA==.Chromaxion:BAAALgAFFAMJBAAAAA==.Chronic:BAABLgAECn8cAAIUAAkJFR+aDQDpAgAUAAkJFR+aDQDpAgAAAA==.Chrysostom:BAABLgAECn8bAAIKAAgJIhgYFgAKAgAKAAgJIhgYFgAKAgAAAA==.Chwamz:BAABLgAECn8cAAMVAAgJZhsPKABxAgAVAAgJZhsPKABxAgAWAAEJAADXfAAiAAABLgAFFAEJAQADAAAAAA==.',
Ci='Ciphirion:BAAALgADCgYJBwAAAA==.',
Cl='Clivennik:BAAALgADCgEJAQAAAA==.Cloggy:BAACLgAFFH8SAAQVAAUJXSA7CQCIAQAVAAUJXSA7CQCIAQAXAAEJURt2AgBkAAAWAAEJWx0VEgBbAAAuAAQKfyUABBUACAnDJdgFAGADABUACAmCJdgFAGADABcABwn+IvIBALUCABYABQmdHlQQAMwBAAAA.Cloudshield:BAAALgAECgYJCgAAAA==.Clydell:BAAALgADCgIJAgAAAA==.',
Co='Coeus:BAAALgADCgMJAwAAAA==.Cokolo:BAAALgADCggJCAAAAA==.Coldflame:BAABLgAECn8oAAIFAAgJDCFzIwDlAgAFAAgJDCFzIwDlAgAAAA==.Corruption:BAAALgAECgYJCAAAAA==.Corruptmonk:BAAALgAECgEJAQAAAA==.Cowchucker:BAAALgAECgQJBAAAAA==.',
Cp='Cptboomerang:BAABLgAECn8WAAIEAAgJZRdIEwD4AQAEAAgJZRdIEwD4AQAAAA==.',
Cr='Crabrangoons:BAAALgAECgUJBQAAAA==.Crath:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Crathdk:BAAALgAECggJEwAAAA==.Crathmonk:BAAALgAECgQJCgABLgAECggJEwADAAAAAA==.Creamfilling:BAAALgADCgYJBgAAAA==.Crispynugget:BAAALgADCggJDQAAAA==.Crixo:BAAALgADCgUJBQAAAA==.Crownroyale:BAABLgAECn8lAAIPAAgJWhl0CQD1AQAPAAgJWhl0CQD1AQAAAA==.Cryovex:BAAALgADCgEJAQAAAA==.',
Cy='Cyrissa:BAABLgAECn8aAAIFAAcJYxSZQgBmAQAFAAcJYxSZQgBmAQAAAA==.',
['Câ']='Cârnägê:BAAALgAECgEJAQAAAA==.',
Da='Dadlover:BAAALgAECgYJDAAAAA==.Daegu:BAABLgAECn8cAAIYAAgJLQ6sMADEAQAYAAgJLQ6sMADEAQAAAA==.Daenlan:BAAALgADCgQJBwAAAA==.Daeynora:BAAALgADCgEJAQAAAA==.Daityasfist:BAABLgAFFH8FAAIZAAMJJyFABQA2AQAZAAMJJyFABQA2AQAAAA==.Dalien:BAAALgAECgUJCAAAAA==.Dalinius:BAAALgAECgYJDgAAAA==.Dalonar:BAAALgADCgMJAwAAAA==.Dance:BAAALgADCgYJCwAAAA==.Darcine:BAAALgAECgQJCAAAAA==.Darkbojangle:BAAALgAECgEJAQAAAA==.Darkless:BAAALgAECgEJAQAAAA==.Dashmodius:BAABLgAECn8dAAMHAAgJXh+hCABQAgAHAAgJIx+hCABQAgAGAAEJkhwSJgBUAAAAAA==.Datfourloko:BAAALgAECgEJAgAAAA==.Dazing:BAAALgAECgUJBgAAAA==.',
De='Deamontsuki:BAAALgAECgYJDwAAAA==.Deceasedpi:BAAALgAECgUJCgAAAA==.Delaci:BAAALgAECgYJCAAAAA==.Delsid:BAAALgADCgUJBQAAAA==.Demonicbeilf:BAAALgADCgEJAQAAAA==.Demonster:BAABLgAECn8ZAAIaAAkJXhPUAQAmAgAaAAkJXhPUAQAmAgAAAA==.Denaian:BAAALgADCgYJBwAAAA==.Deohgee:BAAALgAECgQJCQAAAA==.Deranker:BAAALgAECgcJEgAAAA==.Desmus:BAAALgADCgUJBgAAAA==.Devourdeez:BAAALgAECggJCwABLgAFFAYJGwAVABEgAA==.Dezarath:BAAALgAECgUJBgAAAA==.',
Dh='Dhuumstar:BAAALgADCgkJDQAAAA==.',
Dk='Dkbuhlz:BAAALgAECgIJAgAAAA==.',
Do='Dotdude:BAAALgAECgYJCQAAAA==.',
Dr='Draganhammer:BAAALgAECggJEgAAAA==.Drakeath:BAAALgADCgcJBwAAAA==.Drakkarn:BAABLgAECn8ZAAIbAAYJ0hTMDQBBAQAbAAYJ0hTMDQBBAQAAAA==.Draxina:BAAALgADCgYJBgAAAA==.Draxxton:BAAALgADCgcJCgAAAA==.Drdurty:BAABLgAECn8dAAIMAAgJshdYFABNAgAMAAgJshdYFABNAgAAAA==.Dreadhoof:BAAALgADCgkJDQAAAA==.Drewcifur:BAAALgAECgUJDgAAAA==.Droodar:BAAALgADCgUJBQAAAA==.Droopey:BAAALgADCgYJCQAAAA==.Dropxlife:BAAALgAECgQJBAAAAA==.Druttut:BAAALgADCgEJAQAAAA==.',
Du='Duckywg:BAAALgAECgYJCQAAAA==.Duskvoke:BAAALgAECgMJAwABLgAECgUJCwADAAAAAA==.Duskzen:BAAALgAECgUJCwAAAA==.Dusq:BAAALgAECgEJAQAAAA==.',
Ei='Eilistraaee:BAABLgAECn8jAAIcAAgJDyK1CADjAgAcAAgJDyK1CADjAgAAAA==.',
Ek='Eki:BAAALgAECgIJAgAAAA==.Ekicarys:BAAALgADCgQJBAAAAA==.',
El='Eleratzis:BAAALgAECgYJBgAAAA==.Elfayomega:BAAALgADCgEJAQABLgADCgQJBQADAAAAAA==.Elmencho:BAABLgAECn8WAAINAAYJgRAWnABIAQANAAYJgRAWnABIAQAAAA==.Eltiera:BAAALgAECgQJBQAAAA==.Elvenshot:BAAALgADCgMJAwAAAA==.Elyssa:BAAALgAECgYJEAAAAA==.',
Em='Emberfist:BAAALgADCgYJCQAAAA==.',
En='Endswell:BAAALgAECgEJAQAAAA==.Endszene:BAAALgADCgMJAwAAAA==.',
Er='Errorin:BAAALgAECgMJAwAAAA==.',
Es='Eskimo:BAAALgAECgQJBgAAAA==.Esquimaux:BAABLgAECn8YAAIKAAgJehE0JwCmAQAKAAgJehE0JwCmAQAAAA==.Essex:BAAALgAECgEJAQAAAA==.',
Et='Etchlock:BAAALgADCgkJDwAAAA==.Etheriademon:BAAALgADCgQJBAAAAA==.',
Eu='Euclyn:BAAALgADCgMJAwAAAA==.',
Ev='Evasive:BAAALgADCgUJBQAAAA==.Eviannis:BAAALgAECgYJBwAAAA==.Evîe:BAAALgADCgQJBAAAAA==.',
Ew='Ewanae:BAAALgAECgQJBAABLgAFFAMJBQABADgJAA==.',
Ex='Extacee:BAAALgAECgEJAQAAAA==.Extrafancy:BAAALgADCggJCAAAAA==.',
Fa='Faerina:BAAALgADCgIJAgAAAA==.Faesonia:BAAALgAECgQJDAAAAA==.Fangthir:BAAALgADCgYJCAABLgAECgUJCQADAAAAAA==.Faoop:BAAALgADCgIJAgAAAA==.Fasylan:BAAALgADCgEJAQAAAA==.',
Fe='Feastling:BAAALgAECgYJEQAAAA==.Feefree:BAAALgAECgEJAQAAAA==.Felthirra:BAAALgADCgEJAQAAAA==.Femboyswag:BAAALgAECgUJBgAAAA==.Ferrak:BAAALgADCgcJBwAAAA==.',
Fi='Finnabust:BAAALgAECgEJAQAAAA==.Fizzlefarts:BAAALgADCgYJDwAAAA==.Fizzylemon:BAAALgADCgcJCQAAAA==.',
Fl='Flipnslam:BAABLgAECn8YAAIbAAgJIgpPEQAPAQAbAAgJIgpPEQAPAQAAAA==.Floofball:BAACLgAFFH8FAAITAAIJNgv0JgCCAAATAAIJNgv0JgCCAAAuAAQKfxQAAhMABgnlIRkWANIBABMABgnlIRkWANIBAAEuAAUUBAkKAAQA5RAA.Floralia:BAAALgAECgEJAQAAAA==.',
Fo='Forget:BAAALgAECgEJAQAAAA==.Foxyshadow:BAAALgADCgkJCgAAAA==.',
Fr='Fragwork:BAAALgAECgQJBAAAAA==.Freadyfire:BAAALgAECgYJCgAAAA==.Frostfiretip:BAAALgAECgYJEQAAAA==.Frozanath:BAAALgAFFAEJAQAAAA==.Frózen:BAAALgAECgQJBgAAAA==.',
Fu='Fucctaard:BAAALgADCgIJAgAAAA==.Furious:BAAALgADCgYJBgAAAA==.',
Ga='Gaerestord:BAAALgADCgUJBgAAAA==.Gakusei:BAAALgAECgEJAQAAAA==.Gatortail:BAAALgADCgUJBQAAAA==.Gatzart:BAAALgADCgUJCQAAAA==.',
Gi='Gimchick:BAAALgAECgcJEAAAAA==.',
Gn='Gnomebody:BAAALgADCgcJBwABLgAECgQJBgADAAAAAA==.',
Go='Goofydude:BAAALgAECgYJCQAAAA==.Goofysensei:BAAALgAECgUJCAABLgAECgYJCQADAAAAAA==.Goyimblade:BAAALgAECgcJBwAAAA==.',
Gr='Grandejugoso:BAAALgAECgEJAQAAAA==.Grapejuicy:BAAALgADCgIJAgAAAA==.Grea:BAAALgAECgYJEgAAAA==.Grumpyguts:BAAALgADCgQJBAAAAA==.',
Gu='Guatemoc:BAAALgADCgUJBQAAAA==.Guldandan:BAAALgAECgIJBAAAAA==.Gurthang:BAAALgAECgMJBgAAAA==.',
Ha='Hadrianus:BAAALgADCgcJBwAAAA==.Haginger:BAAALgAECggJEgABLgAECggJHQAdACEUAA==.Hangwenaz:BAAALgAECgMJAwAAAA==.Harlyq:BAABLgAECn8kAAQPAAcJDx7HOgBdAQAPAAUJ/RrHOgBdAQAJAAcJEBFmGQA6AQAZAAIJFAs+aABsAAAAAA==.Havocpeener:BAAALgADCgIJAgABLgADCgcJFQADAAAAAA==.Hazy:BAAALgADCgEJAQAAAA==.',
He='Hearah:BAABLgAECn8dAAMYAAkJug+RHAB+AQAYAAkJug+RHAB+AQAeAAEJ6wEylAAiAAAAAA==.Hellyes:BAAALgADCgYJBgAAAA==.Hexdabear:BAAALgADCgcJDgABLgAECgUJCQADAAAAAA==.Hexkwondo:BAAALgAECgUJCQAAAA==.',
Ho='Holybone:BAAALgADCgEJAQAAAA==.Hondô:BAECLgAFFH8SAAINAAUJDyMfCQCIAQANAAUJDyMfCQCIAQAuAAQKfyYAAg0ACQk+Jc8GAGwDAA0ACQk+Jc8GAGwDAAAA.Hosinator:BAABLgAECn8kAAIFAAcJQgW7YgAWAQAFAAcJQgW7YgAWAQAAAA==.Hotzs:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.',
Hu='Huckleberry:BAAALgADCgcJBwAAAA==.Hukmo:BAAALgAECgMJBQAAAA==.Huntermanjoe:BAAALgAECgUJCAAAAA==.Hunterzalt:BAABLgAECn8mAAMOAAgJDhY6DABNAQAOAAgJDhY6DABNAQANAAEJxgGWMQEmAAAAAA==.',
Hy='Hydroplex:BAAALgADCgQJBgAAAA==.',
['Hò']='Hòndo:BAEALgAECgQJBAABLgAFFAUJEgANAA8jAA==.',
['Hô']='Hôndo:BAEALgAECgQJCAABLgAFFAUJEgANAA8jAA==.',
Ic='Icepanda:BAAALgADCgMJAwAAAA==.Ichantspell:BAAALgAECgQJBwAAAA==.',
Id='Idra:BAACLgAFFH8FAAIQAAIJTx74CwCvAAAQAAIJTx74CwCvAAAuAAQKfycAAhAACAkIJYsGADEDABAACAkIJYsGADEDAAAA.Idrea:BAAALgADCgYJBgAAAA==.',
Il='Ildjarnn:BAAALgAECgUJCAAAAA==.Illaoii:BAAALgAECgEJAQAAAA==.Illussions:BAABLgAECn8XAAMTAAcJ6BOGUgBcAQATAAYJjxSGUgBcAQAfAAIJfBZMQQBCAAAAAA==.',
Im='Imdyland:BAAALgADCgIJAgAAAA==.',
In='Inashen:BAAALgADCgEJAQABLgAECgMJBwADAAAAAA==.Informal:BAAALgADCgIJAgAAAA==.Invelmoon:BAAALgAECgQJDAAAAA==.',
Ir='Iriane:BAAALgAECgkJEgAAAA==.',
It='Ithrail:BAACLgAFFH8FAAIHAAMJjgigIwDWAAAHAAMJjgigIwDWAAAuAAQKfxkAAgcACQnrGy40ACgCAAcACQnrGy40ACgCAAAA.',
Ja='Jakilk:BAAALgAECgQJBAAAAA==.Janistrapin:BAAALgADCgcJDQAAAA==.Jatza:BAAALgAECgcJDQAAAA==.Javontavius:BAAALgAECgQJBwAAAA==.Jazzmisa:BAABLgAECn8oAAIKAAgJXAuoRgA2AQAKAAgJXAuoRgA2AQAAAA==.',
Jd='Jdoobie:BAAALgADCgYJBgAAAA==.',
Je='Jehon:BAAALgAECgEJAgAAAA==.Jellydead:BAABLgAECn8aAAINAAcJTg7pOgBPAQANAAcJTg7pOgBPAQAAAA==.Jerico:BAAALgADCgIJAgAAAA==.Jesselroes:BAAALgADCgMJAwAAAA==.',
Ji='Jinja:BAAALgADCgcJDwAAAA==.',
Jo='Jockster:BAAALgAECgYJEgAAAA==.Jonawayne:BAAALgAECgQJBAAAAA==.Joseycoyote:BAAALgADCgcJBwAAAA==.',
Ju='Judgeandrson:BAAALgAECgUJBQABLgAECgYJEQADAAAAAA==.Judinous:BAABLgAECn8gAAIFAAgJSyNSJwDVAgAFAAgJSyNSJwDVAgAAAA==.Juggernåut:BAAALgADCgkJCwAAAA==.',
Ka='Kabooms:BAABLgAECn8cAAIFAAYJ/wYPcwDyAAAFAAYJ/wYPcwDyAAAAAA==.Kaelditeta:BAAALgAECgYJEAAAAA==.Kaelsdruid:BAAALgAECgQJBAAAAA==.Kaelsevoker:BAAALgAFFAEJAQAAAA==.Kaelthuss:BAAALgADCgMJAwABLgAECgIJBAADAAAAAA==.Kaiarbarcy:BAAALgAECgQJCAAAAA==.Kaisen:BAAALgADCgUJBQAAAA==.Kalamord:BAAALgADCgYJBgAAAA==.Kalross:BAAALgAECgEJAQAAAA==.Kanao:BAABLgAECn8UAAIHAAgJ0g61TQC+AQAHAAgJ0g61TQC+AQAAAA==.Karethi:BAAALgADCgEJAQAAAA==.Katimeen:BAABLgAECn8UAAIMAAYJJwvAHAAWAQAMAAYJJwvAHAAWAQAAAA==.Katla:BAAALgADCgUJBQAAAA==.Kawaiiuwu:BAAALgADCgYJCwAAAA==.',
Ke='Keesah:BAAALgAECgEJAQAAAA==.Keinddora:BAAALgADCgEJAQAAAA==.Kelann:BAABLgAECn8YAAIHAAcJ2ARVWgCZAAAHAAcJ2ARVWgCZAAAAAA==.Kensei:BAAALgAFFAEJAgAAAA==.Kentohya:BAAALgADCgYJDwAAAA==.Kenöbi:BAAALgAECgEJAQAAAA==.',
Kh='Khaoticbrews:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Kharnoth:BAAALgAECgQJBAAAAA==.Khayla:BAAALgADCgEJAQAAAA==.Khody:BAAALgAECgQJBAAAAA==.',
Ki='Kicknbird:BAAALgADCgEJAQAAAA==.Kilain:BAACLgAFFH8JAAMNAAMJqhlaMwD6AAANAAMJYhZaMwD6AAAOAAIJARuvEACSAAAuAAQKfxQAAw4ACAlqFEMgAEIBAA4ABAmyIkMgAEIBAA0ABwkeAjz8AIMAAAAA.Kimbo:BAAALgAECgEJAQAAAA==.Kippo:BAEALgAECgIJAgABLgAFFAQJBwAFAIYFAA==.',
Kn='Knewbee:BAAALgADCgEJAQABLgADCgQJBQADAAAAAA==.',
Ko='Kokushîbo:BAAALgAECgUJCAAAAA==.Konkon:BAAALgAECgYJBwAAAA==.Konoa:BAAALgAECgEJAQABLgAECgQJBwADAAAAAA==.Konton:BAAALgAECgQJBAABLgAECgYJIQAgAJ8ZAA==.',
Kr='Kradoro:BAAALgADCgYJDAAAAA==.Kratorick:BAAALgADCgEJAQAAAA==.Krelash:BAAALgAECgYJEgAAAA==.',
Ku='Kukipoo:BAAALgADCgMJAwAAAA==.Kurdzy:BAAALgADCgQJBAAAAA==.',
Kv='Kvarda:BAAALgADCgMJBAAAAA==.',
Ky='Kynetic:BAAALgAECgQJBwAAAA==.',
La='Labatblue:BAAALgAECgMJAwAAAA==.',
Le='Learning:BAAALgAECgMJAwAAAA==.Leenie:BAAALgAECggJEAAAAA==.Leftleg:BAAALgAECgEJBAAAAA==.Legendrìser:BAACLgAFFH8FAAIKAAMJmwl6IgDsAAAKAAMJmwl6IgDsAAAuAAQKfxYAAgoACQleGKFNAPkBAAoACQleGKFNAPkBAAAA.Leggomyeggos:BAAALgADCgMJAwAAAA==.Leginge:BAABLgAECn8dAAMdAAgJIRSADwCCAQAdAAgJIRSADwCCAQATAAEJdgHn6AAcAAAAAA==.Leigong:BAAALgAECgYJBwAAAA==.Leiyang:BAABLgAECn8ZAAIGAAcJdwy6CgDuAAAGAAcJdwy6CgDuAAAAAA==.Lemmykillmr:BAAALgAECgMJBAAAAA==.',
Li='Liaree:BAAALgADCgIJAgAAAA==.Lie:BAABLgAECn8hAAIgAAYJnxmpIQDsAQAgAAYJnxmpIQDsAQAAAA==.Lifey:BAABLgAECn8WAAINAAcJtRtKRwAeAgANAAcJtRtKRwAeAgABLgAECgMJBQADAAAAAA==.Lightfemboy:BAAALgAECgYJDwABLgAFFAYJFAAPAKclAA==.Limonespe:BAABLgAECn8YAAMVAAgJvSSTCwAeAwAVAAgJvSSTCwAeAwAWAAEJAAAUXABaAAAAAA==.Lisal:BAAALgAECgkJAwAAAA==.Lizerd:BAAALgAECgUJCAABLgAFFAQJCQALAOgXAA==.',
Lo='Locktendo:BAAALgADCgUJCAAAAA==.Looksmaxxing:BAAALgADCgIJAgAAAA==.Lothon:BAAALgADCgMJAwAAAA==.',
Lu='Luciferal:BAAALgADCgYJBgAAAA==.Lunaluv:BAAALgAECgYJCwAAAA==.Lussions:BAAALgAECgUJCwAAAA==.',
Ly='Lytefoot:BAAALgADCgQJBAAAAA==.Lytheris:BAAALgADCgQJBAAAAA==.',
['Lë']='Lëägolas:BAAALgADCgcJBgABLgAECgcJBwADAAAAAA==.',
Ma='Machoshaman:BAABLgAECn8bAAMYAAgJuBTnKQDmAQAYAAgJuBTnKQDmAQAeAAIJrRH4dABuAAAAAA==.Maeveran:BAABLgAECn8XAAMKAAYJohctdQCQAQAKAAYJohctdQCQAQAhAAUJPBFbEwDUAAAAAA==.Mafuyu:BAAALgAECgMJBAAAAA==.Maghalfastir:BAABLgAECn8bAAINAAcJzhd+jwBhAQANAAcJzhd+jwBhAQAAAA==.Magnusvll:BAAALgAECgkJEQAAAA==.Magraah:BAAALgAECgkJEQAAAA==.Mahesvara:BAAALgAECgYJCwAAAA==.Malomea:BAAALgADCgcJBwAAAA==.Malvoryx:BAAALgAECgIJAwAAAA==.Mandrei:BAAALgAECgEJAQAAAA==.Mantisa:BAAALgAECgMJAwAAAA==.Manøn:BAAALgAECgQJBQAAAA==.Maraul:BAAALgAECgEJAQAAAA==.Marlynn:BAAALgAECgcJDAAAAA==.Masinverter:BAAALgAECgYJCgAAAA==.Mastalys:BAEALgAECgQJCAAAAQ==.Mattamuss:BAAALgAECgIJAgAAAA==.Mattdamon:BAAALgADCgEJAQAAAA==.Mattzappara:BAAALgADCgMJAwAAAA==.Mavet:BAABLgAECn8oAAMMAAgJOBZMCQDvAQAMAAgJOBZMCQDvAQALAAQJNANuYwChAAAAAA==.Mavina:BAAALgAECgYJCwABLgAECggJJQABAEQbAA==.Mavinaqt:BAABLgAECn8lAAMBAAgJRBvCDQCuAQABAAgJRBvCDQCuAQAiAAIJ7QJSRABMAAAAAA==.Mazez:BAAALgADCgkJCQAAAA==.',
Mc='Mcpeek:BAAALgAECgQJBQAAAA==.',
Me='Meanswell:BAAALgAECgQJBQAAAA==.Meatshieldz:BAAALgAECgUJBQAAAA==.Mechachi:BAAALgAECgYJEQAAAA==.Megabonk:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Meglatwo:BAAALgADCgYJBgABLgADCgkJEgADAAAAAA==.Meibardo:BAAALgAECgQJAQAAAA==.Meketek:BAABLgAECn8ZAAIjAAYJDhhcBQA+AQAjAAYJDhhcBQA+AQAAAA==.Meliretiera:BAAALgAECgQJBAABLgAECgMJBQADAAAAAA==.Mellivia:BAAALgAECgUJBQAAAA==.Melodica:BAAALgAECgQJBgAAAA==.Menaly:BAAALgAECgMJBQAAAA==.Mendel:BAAALgADCgQJBQAAAA==.Metaphysical:BAABLgAECn82AAMJAAgJrRbxCgD6AQAJAAgJrRbxCgD6AQAPAAQJkRl1VwDmAAAAAA==.Methenistul:BAAALgAECgEJAQAAAA==.',
Mi='Miennie:BAAALgAECgYJDAAAAA==.Mildo:BAABLgAECn8WAAMWAAcJdw+VBgBQAQAWAAcJdw+VBgBQAQAVAAEJAAAMNQEOAAAAAA==.Millerlight:BAAALgAECgQJBAAAAA==.Mingemeister:BAAALgAECgIJAgAAAA==.Minotàurus:BAABLgAECn8fAAMEAAgJvAreJgB9AQAEAAgJvAreJgB9AQARAAMJNANzJwB9AAAAAA==.Mintonka:BAAALgAECgYJEAAAAA==.Mirakodus:BAAALgADCgcJDQAAAA==.Misfired:BAAALgAECgYJDgAAAA==.Mistbehave:BAABLgAECn8YAAQJAAgJaAwhOAAKAQAJAAYJOQ0hOAAKAQAPAAYJkwhgLAC3AAAZAAMJawX1cABOAAAAAA==.Miztaqe:BAAALgADCgMJAwAAAA==.',
Mo='Mogthalen:BAAALgADCgMJAwAAAA==.Moneyheavy:BAAALgAECgUJBwAAAA==.Mongkorn:BAAALgAECgEJAQAAAA==.Monstershi:BAAALgAECgEJAQAAAA==.Mooarcane:BAAALgAECgEJAQABLgAECgYJBgADAAAAAA==.Moomoopie:BAAALgAECgEJAgAAAA==.Moonologist:BAAALgAECgYJBgAAAA==.Moonpig:BAAALgADCgcJFwAAAA==.Moopiehead:BAAALgAECgIJBAAAAA==.Mordayna:BAAALgADCgkJFwAAAA==.Morganà:BAAALgAECgQJBwAAAA==.Morgy:BAABLgAECn8hAAIFAAgJRwddTwBDAQAFAAgJRwddTwBDAQAAAA==.Mortimr:BAAALgAECgUJBAAAAA==.Mortinir:BAAALgAECgEJAQAAAA==.',
Mu='Muneco:BAAALgADCgYJBgAAAA==.',
My='Mylina:BAAALgAECgIJAgAAAA==.Myor:BAAALgADCgUJBQAAAA==.Mystsouls:BAABLgAECn8gAAINAAgJlA8dXgDYAQANAAgJlA8dXgDYAQAAAA==.',
['Må']='Måâgic:BAAALgAECgUJBgAAAA==.',
Na='Nagasaywhat:BAAALgAECgYJDwAAAA==.Nahari:BAAALgADCgIJAgAAAA==.Narcissist:BAAALgAECgMJAgABLgAECggJNgAJAK0WAA==.Natalietes:BAAALgADCgcJCgAAAA==.Nattylight:BAAALgADCggJCAAAAA==.',
Ne='Necronomicon:BAABLgAECn8cAAMWAAYJhhcqCwDwAAAVAAUJGBXbmwAhAQAWAAUJphIqCwDwAAAAAA==.Neetneetneet:BAAALgADCgMJAgAAAA==.Nemoglobine:BAAALgADCgIJAwAAAA==.Nethwarlock:BAAALgAFFAEJAQAAAA==.',
Ni='Nightshroud:BAABLgAECn8ZAAINAAkJ1SHtAgAJAwANAAkJ1SHtAgAJAwAAAA==.Niipz:BAAALgAECgcJDgAAAA==.Nilie:BAAALgAECgEJAQAAAA==.Ninelinez:BAABLgAECn8YAAQPAAYJ/xt8EgB2AQAPAAYJ/xt8EgB2AQAZAAQJ5wYmWACvAAAJAAEJ+h0AAAAAAAAAAA==.Ninjakiwiz:BAAALgADCgEJAQAAAA==.Ninjaknife:BAAALgADCgEJAQAAAA==.',
No='Noctaholic:BAAALgADCgMJBQAAAA==.Noctria:BAAALgAECgQJBAAAAA==.Nocturnalis:BAAALgADCgYJBgAAAA==.Nords:BAAALgAECgMJBgAAAA==.Nordswizard:BAAALgAECgEJAQAAAA==.Novavanna:BAAALgADCgcJDAAAAA==.Noxistra:BAABLgAECn8ZAAQXAAcJ/RESBQA7AQAXAAYJ6Q4SBQA7AQAVAAYJahE0PgA3AQAWAAMJBgRkXQBWAAAAAA==.Noyan:BAAALgAECgMJAwAAAQ==.',
Nu='Nukedawg:BAAALgAECgMJAwAAAA==.Nunchaku:BAAALgAECggJCwAAAA==.',
['Nä']='Nägasäh:BAABLgAECn8WAAINAAYJIxiSVgD/AAANAAYJIxiSVgD/AAAAAA==.',
['Nî']='Nîneline:BAAALgAECgQJBAABLgAECgYJGAAPAP8bAA==.',
['Nø']='Nørb:BAAALgAECgYJDQAAAA==.',
Ob='Obsessions:BAAALgADCgEJAQAAAA==.',
Og='Ogdirtymac:BAAALgADCgMJAwAAAA==.',
Oi='Oilless:BAAALgAECgIJAgAAAA==.',
Ol='Olayro:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Olgalina:BAAALgADCgYJBgAAAA==.Ollietrollie:BAAALgAECgYJDAAAAA==.',
Om='Ommateal:BAAALgAECgEJAgAAAA==.',
Op='Opirix:BAACLgAFFH8JAAILAAQJ6BcFBgA+AQALAAQJ6BcFBgA+AQAuAAQKfygAAwsACAmXIjYIAMgCAAsACAmXIjYIAMgCAAwAAwlxGCdCAOkAAAAA.',
Or='Orcgirl:BAAALgAECgQJBgAAAA==.',
Ou='Ouidufromage:BAAALgAECgEJAQAAAA==.',
Ov='Overlandx:BAAALgAECgMJBQAAAA==.Overloaded:BAABLgAECn8UAAIeAAgJigg/GwA6AQAeAAgJigg/GwA6AQAAAA==.',
Ow='Owlzkaban:BAAALgAECgcJDwAAAA==.',
Ox='Oxelox:BAAALgADCgUJBgAAAA==.',
Oz='Ozzytbone:BAAALgAECgUJCAAAAA==.',
Pa='Paddfoot:BAAALgADCgQJBQAAAA==.Painkillerx:BAAALgADCgcJFAAAAA==.Palisa:BAAALgAECgQJBQAAAA==.Pancakeus:BAAALgAECgkJDQAAAA==.Panini:BAAALgADCgkJEAABLgAECgcJGgAFAGMUAA==.Panzurdin:BAAALgADCgUJBQAAAA==.Panzurlock:BAABLgAECn8aAAIVAAgJFh3JLgBSAgAVAAgJFh3JLgBSAgAAAA==.Panzurrkin:BAAALgADCgEJAQAAAA==.Papabelliswa:BAAALgADCgIJAgAAAA==.Papasquat:BAAALgAECgIJAwAAAA==.Parkane:BAAALgADCgQJBAAAAA==.Patreszas:BAABLgAECn8hAAMBAAgJeQw7FQBVAQABAAgJJgw7FQBVAQACAAYJ7gvkIwAIAQAAAA==.',
Pe='Peener:BAAALgADCgcJFQAAAA==.Pellere:BAAALgADCgMJAwAAAA==.Pemberton:BAAALgAECgcJEwAAAA==.Pepperboy:BAAALgADCgQJBAAAAA==.',
Ph='Pheauxbe:BAAALgADCgYJCAAAAA==.Pheauxly:BAAALgADCgYJDAAAAA==.Phlehm:BAABLgAECn8dAAMTAAcJ3hppDwAaAgATAAcJ3hppDwAaAgAfAAIJAQ27awBxAAAAAA==.',
Pi='Pidpv:BAAALgADCgIJAgAAAA==.',
Pl='Plaguesire:BAAALgADCgYJDgAAAA==.Plutonyx:BAAALgAECgYJCgAAAA==.',
Po='Popedk:BAAALgAECggJEAAAAA==.',
Pr='Prannanm:BAAALgAECgEJAQAAAA==.Priestduude:BAAALgAECgcJEAAAAA==.Priestpheus:BAAALgAECgEJAQAAAA==.Prismaticp:BAAALgADCgYJDAAAAA==.',
Ps='Psyger:BAAALgAECgUJCQAAAA==.',
Pu='Pullacrapton:BAAALgAECgYJCgAAAA==.Purecorrupt:BAAALgAECgIJAgAAAA==.Putridmeat:BAAALgAECgcJDgAAAA==.',
Pw='Pwrsmoke:BAAALgADCgcJCQAAAA==.',
Qu='Quackery:BAAALgADCgIJAgAAAA==.Quiggins:BAAALgAECgUJEgAAAA==.Quikbrownfox:BAAALgAFFAEJAQAAAA==.Quirkster:BAAALgADCgMJAwAAAA==.',
Ra='Rakoon:BAAALgADCgMJAwAAAA==.Rathindor:BAAALgADCgEJAQAAAA==.',
Rc='Rchris:BAAALgADCgEJAQAAAA==.',
Re='Rectivius:BAAALgADCgMJAwAAAA==.Reddknight:BAAALgAECgcJEwAAAA==.Reiker:BAAALgAECgIJAwAAAA==.Retzu:BAAALgAECgEJAQAAAA==.Rezme:BAAALgADCgMJAwAAAA==.',
Ri='Riccardo:BAAALgAECgEJAwAAAA==.Rickiebear:BAAALgADCgQJBwAAAA==.Rimeborn:BAAALgAECgEJAQAAAA==.Rivenn:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.Rizzlesschud:BAAALgADCgMJAwAAAA==.Rizzlér:BAAALgADCgUJAwAAAA==.',
Ru='Rubonyx:BAAALgAECgEJAQAAAA==.Ruikai:BAAALgAECgEJAQAAAA==.Rune:BAAALgADCgcJBgAAAA==.',
Ry='Ryoko:BAABLgAECn8XAAMVAAYJKx0IKgCFAQAVAAUJlhsIKgCFAQAWAAMJzBgjMwDrAAAAAA==.',
['Rä']='Rävaged:BAAALgADCgcJDQABLgAECgYJEQADAAAAAA==.',
Sa='Sagerin:BAAALgAECgQJDAAAAA==.Sageslife:BAAALgAECgQJCQAAAA==.Sailwe:BAAALgAECgIJAwAAAA==.Saintofthetp:BAAALgADCgUJCAAAAA==.Saison:BAAALgADCgYJBgAAAA==.Salém:BAAALgADCgUJBQAAAA==.Sambooka:BAAALgADCgQJBAAAAA==.Saraaj:BAAALgAECgYJDwAAAA==.Sarallina:BAAALgADCgUJCQAAAA==.Sarifa:BAAALgADCgcJBwAAAA==.',
Sc='Scaleygirl:BAAALgADCgYJBgAAAA==.Scallion:BAAALgADCgIJAwAAAQ==.Scalythott:BAAALgAECgQJBAAAAA==.Scarr:BAAALgAECgIJAgAAAA==.Scorbunny:BAAALgAECgEJAgABLgAECgcJGAAFAAcfAA==.Scruffmcgruf:BAABLgAECn8YAAILAAYJcA6uHAAfAQALAAYJcA6uHAAfAQAAAA==.Scubany:BAAALgADCgQJBAAAAA==.',
Se='Selem:BAAALgADCgUJBQABLgAECgcJFwAJAFoXAA==.Seth:BAABLgAFFH8GAAIHAAUJCgWUHQD0AAAHAAUJCgWUHQD0AAAAAA==.Sezeth:BAAALgAECgQJBAAAAA==.',
Sh='Shaboomboom:BAACLgAFFH8HAAIkAAMJugptBACkAAAkAAMJugptBACkAAAuAAQKfxsAAiQACAnCH9oFAKECACQACAnCH9oFAKECAAEuAAMKBgkGAAMAAAAA.Shadowglaive:BAABLgAECn8YAAIHAAYJHBYBYQB+AQAHAAYJHBYBYQB+AQAAAA==.Shalthorn:BAAALgADCgMJAwAAAA==.Shamful:BAAALgAECgMJAwAAAA==.Sharsu:BAACLgAFFH8FAAIVAAMJ5hrvJQAGAQAVAAMJ5hrvJQAGAQAuAAQKfysAAhUACAlGJY4GAFYDABUACAlGJY4GAFYDAAAA.Shew:BAAALgAECgYJDAAAAA==.Shewadin:BAAALgAECgQJBAAAAA==.Shewcifer:BAAALgAECgMJBwAAAA==.Shortcake:BAAALgAECgMJAwAAAA==.',
Sk='Skaborn:BAABLgAECn8UAAIFAAcJxRQwMgCbAQAFAAcJxRQwMgCbAQAAAA==.Skillitor:BAAALgADCgcJBwAAAA==.Skillman:BAAALgADCgUJCQAAAA==.Skrizik:BAAALgAECgIJAgAAAA==.Skullshine:BAACLgAFFH8QAAMNAAUJWR60EwBTAQANAAQJWR60EwBTAQAOAAEJAAD4HwAAAAAuAAQKfxgAAg0ACQk9I78WAPMCAA0ACQk9I78WAPMCAAAA.Skunkie:BAAALgAECgYJEQAAAA==.Skybreaker:BAAALgAFFAEJAQAAAA==.Skåbørn:BAAALgADCgcJDQABLgAECgcJFAAFAMUUAA==.',
Sl='Sluewt:BAABLgAECn8ZAAIKAAgJ3xDaWQDVAQAKAAgJ3xDaWQDVAQAAAA==.Slushadin:BAAALgAECgUJBQABLgAECgYJDQADAAAAAA==.Slushpuppy:BAAALgADCgEJAQAAAA==.Slìquid:BAAALgADCgUJBQAAAA==.',
Sm='Smileysabear:BAAALgAECggJDgAAAA==.Smileysalock:BAAALgADCgcJBwABLgAECggJDgADAAAAAA==.Smolderr:BAAALgAECgYJDAAAAA==.',
Sn='Sneasel:BAAALgADCgEJAQABLgAECgcJGAAFAAcfAA==.',
So='Soapydish:BAAALgADCgIJAgAAAA==.Solcow:BAAALgAECgEJAQABLgADCgEJAwADAAAAAA==.Soulshart:BAAALgAECgcJBQAAAA==.',
Sp='Spacerift:BAABLgAFFH8VAAIbAAYJ5iDSAADvAQAbAAYJ5iDSAADvAQAAAA==.Spaciousyeti:BAAALgAECgYJCwAAAA==.Sparhawke:BAAALgADCgkJEAAAAA==.Spawne:BAAALgAECgcJDgAAAA==.Spearowmage:BAAALgADCgYJBgAAAA==.Spearowpally:BAAALgAECgQJBwAAAA==.Spellomode:BAAALgAECgYJDAAAAA==.Spilt:BAAALgAECgEJAQAAAA==.Splits:BAAALgAECgEJAgABLgAECgIJAgADAAAAAA==.',
St='Stanhorn:BAAALgADCgIJAQAAAA==.Starrscream:BAAALgAECgkJBAAAAA==.Stazxd:BAAALgAECgEJAQAAAA==.Steezyah:BAAALgAECgUJCQAAAA==.Stevebrule:BAAALgAECgEJAQAAAA==.Stiffbacon:BAABLgAECn8hAAIUAAYJxQ+8HQBDAQAUAAYJxQ+8HQBDAQAAAA==.Stinkler:BAAALgAECgUJBQAAAA==.Stomach:BAAALgAECgQJBwAAAA==.Stornhas:BAAALgADCgQJBwAAAA==.Strikerj:BAAALgAECgQJBAAAAA==.Strànge:BAAALgADCgUJBQAAAA==.Stun:BAAALgAECgMJBAAAAA==.Stunllub:BAAALgAECgYJEQAAAA==.',
Su='Suggs:BAACLgAFFH8JAAIVAAUJuRn2LwCzAAAVAAUJuRn2LwCzAAAuAAQKfyAABBUACQkuJNkOAAMDABUACAmYJNkOAAMDABYAAgl4GgtMAIkAABcAAQkAAKMoAE8AAAAA.Sunwelldone:BAAALgADCgYJDAAAAA==.Superali:BAAALgADCgMJAwAAAA==.Surnaturelle:BAAALgADCgcJBwAAAA==.',
Sy='Sylariel:BAAALgADCgMJAwAAAA==.Sylbane:BAAALgADCgQJBAAAAA==.Sylviex:BAAALgADCgIJAgAAAA==.Syphyr:BAAALgADCgQJBwAAAA==.Syradael:BAAALgADCgUJBQAAAA==.Sythyn:BAAALgADCgUJBQAAAA==.',
['Sâ']='Sâmurai:BAAALgADCgcJBwAAAA==.',
['Sæ']='Sæd:BAAALgADCgYJCwAAAA==.',
Ta='Taelinn:BAAALgADCgcJBwABLgAECggJIQABAHkMAA==.Talet:BAAALgAECgMJAwAAAA==.Tallyjaber:BAAALgAECgEJAQAAAA==.Tastymelo:BAAALgAECgEJAQAAAA==.Taterthott:BAABLgAECn8WAAQLAAcJ5wqhSAAXAQALAAcJSQihSAAXAQAlAAYJ6wXOPgC3AAAMAAMJEQMUOgBJAAAAAA==.Tauriko:BAAALgAECgcJEQAAAA==.',
Te='Telma:BAAALgAECgMJAwABLgAECgQJCQADAAAAAA==.Teradin:BAAALgAECgEJAQAAAA==.Teratori:BAAALgADCgIJAwAAAA==.Terrorknight:BAABLgAECn8YAAINAAgJ3BQ0JACxAQANAAgJ3BQ0JACxAQAAAA==.',
Th='Thebestlorax:BAAALgADCgMJAwAAAA==.Theldrus:BAAALgAECgYJCgAAAA==.Theradestria:BAAALgAECgMJAwAAAA==.Thereeree:BAAALgADCggJDAAAAA==.Thestigg:BAAALgAECgIJAgAAAA==.Threaten:BAAALgADCgUJCQAAAA==.Thunderfall:BAAALgAECgYJEgAAAA==.Thyrä:BAAALgADCgkJFwAAAA==.Thëspiän:BAAALgAECgEJAgAAAA==.',
Ti='Tihro:BAAALgAECgUJCgAAAA==.Timmyjam:BAABLgAECn8dAAMWAAgJag4kBQB6AQAWAAgJag4kBQB6AQAVAAEJAAACNgEHAAAAAA==.Tiradia:BAABLgAECn8hAAIQAAcJECYKCgAAAwAQAAcJECYKCgAAAwAAAA==.',
To='Toffersox:BAAALgAECgYJDgABLgAECgMJBQADAAAAAA==.',
Tr='Traianus:BAAALgAECgMJAwAAAA==.Traynnissa:BAAALgADCgcJDAAAAA==.Treexa:BAAALgADCgQJBAAAAA==.',
Tu='Tutankhamun:BAAALgAECgMJBAAAAA==.',
Tv='Tvenom:BAABLgAECn8UAAIKAAYJgRRPgwBzAQAKAAYJgRRPgwBzAQAAAA==.',
Tw='Twistybanana:BAAALgAECgYJDAAAAA==.Twofourfive:BAAALgADCgEJAQAAAA==.',
Ty='Tyinastor:BAAALgADCggJBwAAAA==.',
['Tö']='Töme:BAAALgADCgUJBwAAAA==.',
['Tø']='Tømb:BAAALgAECgQJBQABLgAFFAQJBwABAMQRAA==.',
Ud='Udderless:BAAALgAECgUJCgAAAA==.',
Uh='Uhhtari:BAAALgAECgEJAQAAAA==.',
Un='Unbëärable:BAAALgADCggJEAAAAA==.',
Ut='Uthers:BAAALgADCgYJBgAAAA==.',
Va='Vaalhazak:BAAALgAECgIJBAAAAA==.Valdril:BAAALgADCgcJBwAAAA==.Valky:BAAALgAECgYJCgAAAA==.Vanhealín:BAAALgAECgYJBwAAAA==.',
Ve='Vecx:BAAALgAECgMJAwABLgAECgYJDQADAAAAAA==.Veiyn:BAAALgADCgYJBgAAAA==.Veldispel:BAAALgADCgYJBgAAAA==.Velgy:BAAALgAECgQJBAAAAA==.Velro:BAAALgAECggJEgAAAA==.Versë:BAAALgAECgEJAQAAAA==.Vextrex:BAAALgAECgEJAQAAAA==.',
Vh='Vhalaan:BAAALgADCgMJAwAAAA==.',
Vi='Vianir:BAAALgAECgYJEgAAAA==.Viann:BAAALgADCgYJCgAAAA==.Vitamin:BAAALgAECggJCwAAAA==.',
Vo='Voidness:BAAALgAECgUJBwAAAA==.Voldanis:BAAALgAECgkJAQAAAA==.Volpris:BAAALgADCgYJBgAAAA==.Volzuka:BAAALgAECgEJAQAAAA==.',
Vu='Vulsutyr:BAAALgADCgMJAwAAAA==.',
Vy='Vyndeyice:BAAALgADCgIJAgAAAA==.',
['Vá']='Vál:BAAALgADCgQJBAAAAA==.',
['Vé']='Véxør:BAABLgAECn8lAAQTAAgJPwwMIgBxAQATAAgJPwwMIgBxAQAdAAYJUhKNDADxAAAfAAIJugLFeQA/AAAAAA==.',
['Vê']='Vêxor:BAAALgADCgcJBwAAAA==.',
['Vë']='Vësper:BAAALgADCgkJCwAAAA==.',
Wa='Waffel:BAAALgAECgEJAQAAAA==.Wafulol:BAACLgAFFH8FAAIKAAMJTAPAJgDKAAAKAAMJTAPAJgDKAAAuAAQKfzMAAgoACAnsFx06ADsCAAoACAnsFx06ADsCAAAA.Warhawkyo:BAAALgAECgYJBwAAAA==.Warlockios:BAAALgADCgcJBwAAAA==.Warmsoup:BAAALgADCgMJAwAAAA==.Warscared:BAAALgAECgUJCgAAAA==.Waxxpoet:BAAALgADCgYJDQAAAA==.',
We='Wels:BAAALgAECgYJCQAAAA==.',
Wh='Whichwitch:BAAALgADCgUJBQAAAA==.Whist:BAAALgADCgEJAgAAAA==.',
Wi='Wigglypuffsr:BAAALgAECggJDQAAAA==.Wiikkid:BAAALgAECgQJBAAAAA==.Winddrake:BAAALgAECgYJCAAAAA==.',
Wr='Wrathborne:BAAALgADCgMJAwAAAA==.',
Xa='Xaanu:BAAALgADCgUJBQAAAA==.Xaclov:BAAALgAECgYJEQAAAA==.Xalcor:BAEALgAECgQJBQAAAA==.Xanelivan:BAAALgADCgUJCgAAAA==.Xanneste:BAAALgADCgMJAwAAAA==.Xano:BAAALgAECgYJDwAAAA==.Xarius:BAAALgAECgUJBgAAAA==.',
Xi='Xiz:BAAALgAECgEJAQAAAA==.',
Xo='Xorlandu:BAAALgAECggJCQAAAA==.',
Xx='Xxchan:BAAALgAECgUJBQAAAA==.',
Xy='Xylotus:BAAALgAECgUJEAABLgAFFAEJAQADAAAAAA==.',
Ya='Yahtzeé:BAABLgAECn8dAAIcAAgJOA29LwDDAQAcAAgJOA29LwDDAQAAAA==.',
Yo='Yokaihp:BAAALgADCgMJAwAAAA==.Yoshii:BAAALgAECgUJBQAAAA==.',
Yu='Yujirø:BAABLgAECn8TAAIHAAYJSB5XIgBlAQAHAAYJSB5XIgBlAQAAAA==.Yuubel:BAAALgADCgcJDwAAAA==.',
Za='Zale:BAAALgAECgIJAgAAAA==.Zanpakuto:BAAALgAECgkJCgAAAA==.Zayday:BAAALgADCgEJAQAAAA==.',
Ze='Zedawg:BAAALgAECgQJBAAAAA==.Zenfemboy:BAACLgAFFH8UAAIPAAYJpyV6AAAjAgAPAAYJpyV6AAAjAgAuAAQKfyUAAg8ACQkQJuQBAIYDAA8ACQkQJuQBAIYDAAAA.Zerofoxx:BAAALgADCgMJAwAAAA==.',
Zh='Zhdun:BAAALgAECgYJBgAAAA==.',
Zi='Zidalix:BAAALgADCgkJCQAAAA==.Ziweix:BAAALgADCgYJCAAAAA==.',
Zo='Zolmijin:BAABLgAECn8WAAMmAAYJbhDtFwA6AQAmAAYJVQztFwA6AQAbAAUJ3A9AFgDVAAAAAA==.Zombiekush:BAAALgADCgMJBAAAAA==.',
Zu='Zugomik:BAAALgAECggJEgAAAA==.Zurydh:BAAALgAECgkJBwAAAA==.Zuulax:BAAALgAECgMJAwAAAA==.',
['Zæ']='Zæn:BAAALgAECgUJBQAAAA==.',
['Zé']='Zéddicus:BAAALgADCgEJAQAAAA==.',
['Ça']='Çasey:BAAALgAECgYJDQAAAA==.',
['Çé']='Çélädor:BAACLgAFFH8IAAIKAAQJXxowGwDGAAAKAAQJXxowGwDGAAAuAAQKfyQAAgoACAm1JHQNACIDAAoACAm1JHQNACIDAAAA.',
['Çü']='Çürzê:BAAALgADCgMJAwAAAA==.',
['Èm']='Èmrys:BAAALgAECgcJBQAAAA==.',
['Öb']='Öbi:BAAALgAECgYJDAAAAA==.',
['Ör']='Örin:BAABLgAECn8bAAIaAAgJtRm4BABWAgAaAAgJtRm4BABWAgAAAA==.',
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

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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Warrior-Fury','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Warlock-Destruction','Mage-Arcane','Monk-Windwalker','DemonHunter-Havoc','Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Monk-Brewmaster','Warrior-Protection','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Shaman-Enhancement','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aassvik:BAABLgAECn8XAAIBAAYJsCF+BADuAQABAAYJsCF+BADuAQAAAA==.',
Ac='Achievless:BAAALgAECgYJBgAAAA==.Achievsome:BAACLgAFFH8LAAQCAAQJVh8oAQB2AQACAAQJVh8oAQB2AQADAAQJFgnQCwAdAQABAAEJgAiRFgA7AAAuAAQKfyUABAIACQn2ICECAEICAAIACAn7ICECAEICAAEAAwnjGYBTAOkAAAMAAQm8HhtOAFkAAAAA.',
Ad='Adava:BAAALgADCggJCAABLgAFFAQJCgAEAGggAA==.Adennoko:BAAALgADCgkJCQAAAA==.',
Ae='Aery:BAAALgADCgcJBwAAAA==.Aesomx:BAAALgAECgEJBQABLgAECgIJAwAFAAAAAA==.',
Ag='Agrajag:BAAALgADCgkJCQABLgAECggJHwAGABITAA==.',
Ai='Aiona:BAAALgAECgUJBQAAAA==.Aithea:BAAALgAECgQJBAAAAA==.',
Ak='Akagrats:BAAALgAECgYJDAAAAA==.Aknutiak:BAAALgAECgIJAgAAAA==.',
Al='Aldenwarlock:BAAALgAECgQJBgAAAA==.Alekhine:BAAALgADCgIJAgAAAA==.Aliengrey:BAAALgAECgQJCQAAAA==.Allimore:BAAALgAECgQJBQAAAA==.Alonsusfaol:BAAALgADCgUJBgAAAA==.',
Am='Amane:BAAALgAECgUJDAAAAA==.American:BAAALgAECgUJCQAAAA==.Amulisha:BAAALgADCgcJFQAAAA==.',
An='Annya:BAABLgAECn8UAAIBAAcJrRFJLACWAQABAAcJrRFJLACWAQAAAA==.Anowon:BAAALgADCgcJBwABLgAECgkJCwAFAAAAAA==.',
Ar='Arassaka:BAAALgAECgYJCQAAAA==.Archdragon:BAAALgAECgUJCAAAAA==.Arcius:BAAALgAECgYJDQAAAA==.Aristae:BAAALgAECgEJAQABLgAECgYJDQAFAAAAAA==.Arkanis:BAABLgAECn8gAAIHAAgJIBtzAgA8AgAHAAgJIBtzAgA8AgAAAA==.Arlestia:BAAALgADCgEJAQAAAA==.Armament:BAAALgAECggJEAAAAA==.Arrolexancas:BAAALgAECgQJCwAAAA==.Arrows:BAAALgADCgQJBAAAAA==.Arturiouss:BAABLgAECn8VAAIIAAYJnRNIBwAmAQAIAAYJnRNIBwAmAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.Arzuul:BAAALgAECgUJDQAAAA==.',
At='Athira:BAAALgADCgUJBQAAAA==.',
Au='Audi:BAAALgAECgEJAQAAAA==.Auid:BAAALgADCgUJBQAAAA==.Aurafiora:BAABLgAECn8qAAMJAAgJIB77EgCfAgAJAAgJfRz7EgCfAgAKAAIJjQxVdgBlAAAAAA==.Aurelio:BAAALgAECgYJDgAAAA==.Auther:BAAALgAECgEJAQAAAA==.',
Av='Avalancha:BAABLgAECn8WAAILAAcJmxA6BQAQAQALAAcJmxA6BQAQAQAAAA==.Avangela:BAAALgAECgYJBQAAAA==.Avanish:BAAALgADCgEJAQABLgAECgQJBAAFAAAAAA==.Avinoch:BAAALgAECgQJCgAAAA==.',
Aw='Awenyedd:BAAALgAECgMJAwAAAA==.',
Ax='Axon:BAAALgADCgcJBwAAAA==.',
Az='Azaliene:BAAALgAECgQJBAAAAA==.Azambregon:BAAALgADCgcJBwAAAA==.Azenroth:BAAALgAECgEJAQAAAA==.Azulhail:BAAALgAECgQJCAAAAA==.Azurhan:BAAALgADCgMJAwAAAA==.',
Ba='Bahadir:BAAALgADCgEJAQAAAA==.Bakimono:BAAALgAECgMJBQAAAA==.Banehellborn:BAAALgAECgIJAgAAAA==.Barloran:BAAALgADCgEJAQAAAA==.Bastoosebata:BAAALgAECgUJBAAAAA==.Bazzi:BAAALgAECgEJAQAAAA==.',
Be='Bearbud:BAAALgADCggJCAABLgAFFAQJCgAMAI0YAA==.Beardicuss:BAAALgAECgQJCgAAAA==.Beastdrank:BAAALgAECgMJAwAAAA==.Beauxjingles:BAAALgAECgQJBAAAAA==.Beezlebumon:BAAALgAECggJDwAAAA==.Beld:BAAALgADCgYJBgAAAA==.Bellcross:BAAALgAECgYJCwAAAA==.Bewater:BAAALgAECgQJBAAAAA==.',
Bh='Bhutcheeks:BAAALgAECgEJAQAAAA==.',
Bi='Birr:BAAALgADCgUJCAAAAA==.',
Bl='Bloomflow:BAAALgAECgYJDwAAAA==.',
Bo='Bobabear:BAAALgADCgMJAwAAAA==.Bonersimpsun:BAAALgAECgYJCAAAAA==.Boomclap:BAAALgAECgcJDgAAAA==.',
Bp='Bpbreezy:BAABLgAECn8pAAIBAAkJpSF+AgBCAwABAAkJpSF+AgBCAwAAAA==.',
Br='Bracknor:BAABLgAECn8gAAIJAAgJ1BXqDwCCAQAJAAgJ1BXqDwCCAQAAAA==.Brandonb:BAABLgAECn8jAAMEAAgJjhyYDwDHAQAEAAgJjhyYDwDHAQANAAEJNhbjHAA5AAAAAA==.Brandondh:BAAALgAECgYJEgAAAA==.Bredock:BAAALgAECgUJCQABLgAFFAMJCAAJAKARAA==.Brickmitts:BAAALgADCgYJBwAAAA==.Brotem:BAAALgAECgUJEQAAAA==.Broth:BAAALgAECgQJCgAAAA==.',
Bu='Bullshamy:BAAALgADCgIJAgAAAA==.Bumblbeetuna:BAAALgADCgcJEAAAAA==.Bumperdemon:BAAALgAECgQJBgAAAA==.Burkisure:BAAALgADCgYJBgAAAA==.',
By='Bysokar:BAABLgAECn8cAAIOAAgJMxdkFABKAgAOAAgJMxdkFABKAgAAAA==.',
Ca='Cainfortea:BAAALgADCgkJFQAAAA==.Cakecity:BAABLgAECn8bAAIPAAcJ9R4GAwDPAQAPAAcJ9R4GAwDPAQAAAA==.Calikillaoi:BAAALgADCgcJCAAAAA==.Calimage:BAAALgADCgUJBQAAAA==.Calipal:BAAALgAECgYJBwAAAA==.Catalïna:BAAALgADCgUJBQABLgAFFAUJCQAQAN8bAA==.Catälina:BAACLgAFFH8JAAIQAAUJ3xtvBQB1AQAQAAUJ3xtvBQB1AQAuAAQKfy8AAhAACAnOIm0KANQCABAACAnOIm0KANQCAAAA.',
Ce='Celebrimbjor:BAAALgADCggJCQAAAA==.Cerberusbone:BAAALgAECgEJAgAAAA==.',
Ch='Cheddthyr:BAAALgADCgEJAQAAAA==.Cherubim:BAAALgAECgEJAQAAAA==.Chrnobog:BAABLgAECn8iAAQMAAgJyhqaEQC/AQARAAcJbBytOAApAgAMAAYJqBaaEQC/AQASAAQJNR1SDgBNAQABLgAFFAQJCgAMAI0YAA==.',
Ci='Cinderlily:BAAALgADCggJCAAAAA==.',
Cl='Classicoil:BAAALgADCgEJAQAAAA==.Clayprincess:BAAALgAECgEJAQABLgAECgcJEgAFAAAAAA==.',
Co='Cocoyibobo:BAAALgAECgQJBQAAAA==.Colty:BAAALgADCgYJDAAAAA==.Conflagrate:BAABLgAECn8TAAIRAAcJWR0eJwB1AgARAAcJWR0eJwB1AgAAAA==.Coolbeamz:BAAALgAECgEJAQAAAA==.Corvik:BAAALgADCgEJAQAAAA==.',
Cp='Cptcrushingb:BAAALgAECgEJAgAAAA==.',
Cr='Crazyhamster:BAAALgAECgQJBAAAAA==.Crithappens:BAABLgAECn8oAAIEAAgJtxswPACGAgAEAAgJtxswPACGAgAAAA==.Criturrpants:BAAALgAECgYJBgAAAA==.',
Cu='Cute:BAAALgADCgYJBwAAAA==.',
Cy='Cyb:BAAALgADCgEJAQAAAA==.Cynnå:BAAALgAECgcJEAAAAA==.',
['Cü']='Cüpcake:BAAALgAECggJDQAAAA==.',
Da='Daikirí:BAAALgAECgYJDgAAAA==.Damienator:BAAALgAECgIJAwAAAA==.Dankiferus:BAAALgADCgcJBwAAAA==.Dannyy:BAAALgADCggJDAAAAA==.Dawrk:BAAALgAECgQJBgAAAA==.',
De='Deadincide:BAAALgAECgYJEwAAAA==.Dearia:BAAALgADCgIJAQAAAA==.Decree:BAAALgAECgYJDAAAAA==.Delcid:BAAALgAECgQJBQABLgAECgcJDQAFAAAAAA==.Delik:BAABLgAECn8WAAIEAAcJIAjYMQABAQAEAAcJIAjYMQABAQAAAA==.Demonarch:BAAALgADCgUJCAAAAA==.Deneol:BAAALgAECgcJCAAAAA==.Desola:BAAALgADCgEJAQAAAA==.Destrogen:BAAALgAECgcJEwAAAA==.Destïny:BAACLgAFFH8KAAITAAQJNBVVFwBHAQATAAQJNBVVFwBHAQAuAAQKfxcAAhMACAluIKgwAHUCABMACAluIKgwAHUCAAAA.Desìre:BAABLgAECn8WAAIDAAcJIRbpBgCGAQADAAcJIRbpBgCGAQAAAA==.Devastator:BAAALgADCgcJDQAAAA==.Deàthgirls:BAAALgADCgUJBQABLgAECgkJLgAUAOgjAA==.',
Di='Dinonuggies:BAAALgADCgkJFAAAAA==.Dirty:BAABLgAECn8bAAIEAAgJ2RymCwD1AQAEAAgJ2RymCwD1AQAAAA==.Disk:BAAALgAECgQJBgAAAA==.',
Dn='Dnice:BAAALgAECgEJAQAAAA==.',
Do='Doompalm:BAAALgADCgUJBQAAAA==.Doomshield:BAAALgAECgYJEAAAAA==.Doomtrain:BAAALgADCgEJAQAAAA==.Dorati:BAAALgAECgQJBgAAAA==.',
Dr='Drackiechan:BAAALgAECgMJAwABLgAECgkJKQABAKUhAA==.Dracodeez:BAABLgAECn8bAAIVAAcJECKXAAA6AgAVAAcJECKXAAA6AgAAAA==.Droobid:BAABLgAECn8eAAIWAAkJ6h08BQA6AwAWAAkJ6h08BQA6AwAAAA==.',
Dy='Dykenasty:BAABLgAECn8YAAIGAAcJ1B6qOAASAgAGAAcJ1B6qOAASAgAAAA==.',
Dz='Dzlightning:BAAALgAECgEJAQAAAA==.',
['Dò']='Dòóm:BAAALgADCgMJAwAAAA==.',
Ea='Earendur:BAAALgAECgQJCAAAAA==.',
Ec='Eciruma:BAAALgAECgEJAgAAAA==.',
Ei='Eiseth:BAAALgADCgUJBQAAAA==.',
El='Elemeesel:BAAALgADCggJCQAAAA==.Eltael:BAAALgAECgUJCwAAAA==.Elæna:BAAALgADCgkJCQAAAA==.',
Em='Emilianaluz:BAAALgADCgcJBwAAAA==.',
En='Endeavor:BAAALgAECgQJBAAAAA==.Enky:BAAALgADCgYJBgABLgAECgYJEQAFAAAAAA==.Enyxia:BAAALgADCggJEAAAAA==.',
Ep='Epikhotti:BAAALgAECgMJBQAAAA==.',
Er='Eradion:BAAALgAECgEJAgAAAA==.Erisson:BAAALgAECgcJAgAAAA==.',
Es='Eszran:BAAALgAECgYJDAAAAA==.',
Eu='Euthanized:BAAALgADCgIJAgAAAA==.',
Ev='Evelleda:BAAALgADCgIJAgAAAA==.Evendell:BAAALgADCgcJBwAAAA==.',
Fa='Falys:BAAALgADCgYJCQAAAA==.Fasani:BAAALgAECgEJAQAAAA==.',
Fe='Feels:BAAALgAECgEJAwAAAA==.Felbro:BAAALgAECgMJAwAAAA==.Felraiser:BAAALgADCgkJHgAAAA==.Fendalein:BAAALgADCgQJBAAAAA==.Fennar:BAAALgAECgYJCgAAAA==.Ferosha:BAAALgAECgYJEAABLgAECggJHwAXABQVAA==.Fexxyr:BAAALgADCgIJAgABLgAFFAQJCAACAD0WAA==.',
Fi='Fidobedo:BAAALgADCgMJAwAAAA==.Firefly:BAAALgADCgEJAQAAAA==.Firstfear:BAAALgAECgMJBAAAAA==.Fisch:BAABLgAECn8bAAIYAAcJ4SXOAACCAgAYAAcJ4SXOAACCAgAAAA==.Fizzlepow:BAAALgADCgYJBgAAAA==.',
Fl='Flagrent:BAAALgAECgQJDQAAAA==.Flashico:BAAALgAECgYJDgAAAA==.Flemingo:BAAALgAECgIJAwAAAA==.Flemtaur:BAAALgAECgkJAgAAAA==.Flidd:BAABLgAECn8VAAIEAAcJXwjTIgBGAQAEAAcJXwjTIgBGAQAAAA==.Flipingtiska:BAAALgAECgIJAgAAAA==.Floret:BAAALgADCgMJAwAAAA==.Flowforth:BAAALgAECgUJBQAAAA==.Fluht:BAAALgADCgYJBgAAAA==.Flynae:BAABLgAECn8WAAIBAAcJchN/CAB5AQABAAcJchN/CAB5AQAAAA==.',
Fr='Frearyne:BAABLgAECn8WAAMWAAgJkiOxBgAhAwAWAAgJkiOxBgAhAwAZAAMJBg1cCADHAAAAAA==.Friergren:BAABLgAECn8ZAAIEAAkJ7RszGwAKAwAEAAkJ7RszGwAKAwAAAA==.Frostfight:BAAALgADCgYJBgAAAA==.Frylôck:BAAALgADCgIJAgABLgAECgYJEQAFAAAAAA==.',
Fs='Fstingnemo:BAAALgADCgUJCAAAAA==.',
Fy='Fyster:BAAALgAECgQJBAAAAA==.Fyxxer:BAAALgAECgYJCAABLgAFFAQJCAACAD0WAA==.Fyxxie:BAACLgAFFH8IAAICAAQJPRbyCQAVAQACAAQJPRbyCQAVAQAuAAQKfx8AAgIACQnqHGcHABIDAAIACQnqHGcHABIDAAAA.',
Ga='Galex:BAAALgADCgEJAQAAAA==.Garah:BAAALgADCgUJBQAAAA==.',
Ge='Geewonii:BAAALgADCgYJBgAAAA==.Geroesan:BAAALgADCggJCAAAAA==.Geron:BAAALgADCgMJAwAAAA==.',
Gh='Ghostchedd:BAAALgADCggJCwAAAA==.',
Gi='Gialiana:BAABLgAECn8gAAIKAAkJgxa6FwBsAgAKAAkJgxa6FwBsAgAAAA==.Giblar:BAAALgADCgUJBQAAAA==.Gikyounoshi:BAAALgADCgUJBQAAAA==.Girthen:BAABLgAECn8jAAMBAAgJfiLHBQDzAgABAAgJfiLHBQDzAgACAAMJKhd3QwDfAAAAAA==.',
Gn='Gnx:BAAALgAECgQJBQAAAA==.',
Go='Goobby:BAABLgAECn8XAAITAAgJXSKRFQD6AgATAAgJXSKRFQD6AgAAAA==.Goonfred:BAAALgAECgQJBAAAAA==.',
Gr='Greenymeany:BAABLgAECn8eAAIHAAYJyiO4GwBvAgAHAAYJyiO4GwBvAgAAAA==.Grrimm:BAAALgADCgMJAwAAAA==.Grukk:BAAALgADCgYJCwABLgAECgMJBgAFAAAAAA==.Grully:BAABLgAECn8aAAIQAAgJHBN/KQDpAQAQAAgJHBN/KQDpAQAAAA==.Gruumsh:BAAALgAECgUJCQAAAA==.',
Ha='Haggard:BAABLgAECn8WAAIGAAcJlxIaGwApAQAGAAcJlxIaGwApAQAAAA==.Hailsbelle:BAABLgAECn8VAAIPAAYJYwpWOQAdAQAPAAYJYwpWOQAdAQAAAA==.',
Hb='Hbic:BAAALgAECgQJBQAAAA==.',
He='Healingpanda:BAAALgAECgQJBQAAAA==.Healyboar:BAAALgAECgcJDQAAAA==.Heartstabber:BAAALgADCggJCwAAAA==.Heascha:BAAALgADCgEJAQAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAQJBgAEAEwFAA==.Helado:BAAALgADCgUJCAAAAA==.Hellbane:BAAALgADCgkJHQAAAA==.Heri:BAAALgADCgEJAQAAAA==.',
Hi='Highwayman:BAAALgAECgUJCgABLgAECggJIwAJAHQiAA==.Himwhome:BAAALgADCgYJCAAAAA==.',
Ho='Holyteamdiff:BAABLgAECn8ZAAIDAAgJmhWvFAAEAgADAAgJmhWvFAAEAgAAAA==.Hondurasman:BAAALgADCgUJDQAAAA==.Honkhonk:BAABLgAECn8fAAIUAAYJ+BkOaQCtAQAUAAYJ+BkOaQCtAQAAAA==.',
Hu='Huahhuahhuah:BAAALgADCgcJFwABLgAECgYJCgAFAAAAAA==.Hulas:BAAALgAECgEJAQAAAA==.Hungidan:BAAALgADCgYJBgABLgAECggJHAAaAIIPAA==.Huntdemonz:BAAALgAECgUJBwABLgAECgYJFQAHAGIWAA==.',
Ic='Icelynsnow:BAAALgADCgkJDAAAAA==.Icrono:BAAALgADCgIJAgAAAA==.Icwiener:BAAALgAECgYJCgAAAA==.',
Il='Illaria:BAAALgADCgIJAgAAAA==.',
Im='Imjustpika:BAAALgADCgcJBwABLgAFFAMJBwAbALAEAA==.',
In='Indeathinite:BAAALgADCgIJAgAAAA==.Inferniö:BAACLgAFFH8KAAIEAAQJaCBJDQAmAQAEAAQJaCBJDQAmAQAuAAQKfy0AAgQACQnnJGQEALoDAAQACQnnJGQEALoDAAAA.Inkurushio:BAAALgAECgUJCwAAAA==.Insector:BAAALgADCgIJAgAAAA==.Inshallah:BAAALgAECgEJBAABLgAECgIJAwAFAAAAAA==.',
Io='Iolanie:BAAALgAECgMJAwAAAA==.',
Ip='Ipewdmyself:BAAALgADCgYJCAAAAA==.',
Is='Ismat:BAABLgAECn8jAAIQAAgJ5h2gDgClAgAQAAgJ5h2gDgClAgAAAA==.',
Iv='Ivorybones:BAAALgAECgUJDAAAAA==.',
Ix='Ixxia:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Ixxy:BAAALgADCgYJBgAAAA==.',
Iz='Izbiar:BAAALgADCgcJDAAAAA==.',
Ja='Jabahnzulash:BAAALgADCgcJEwABLgAFFAIJBQATAFIiAA==.Jabzularu:BAAALgAECgYJDwAAAA==.Jaeko:BAABLgAECn8WAAIOAAYJXw85NwBCAQAOAAYJXw85NwBCAQAAAA==.Jaekyrn:BAAALgADCgIJAgABLgAECgYJFgAOAF8PAA==.Jaeza:BAAALgADCggJEQAAAA==.Jamrock:BAABLgAECn8ZAAITAAgJchJtWADoAQATAAgJchJtWADoAQAAAA==.Jarshh:BAABLgAECn8bAAIHAAcJ2xzdAwAFAgAHAAcJ2xzdAwAFAgAAAA==.',
Je='Jethic:BAAALgADCgUJCwAAAA==.Jezabell:BAAALgAECgYJBgAAAA==.',
Ji='Jibberwhocky:BAAALgADCgYJCgABLgAECgcJEwAFAAAAAA==.',
Jo='Jonald:BAAALgAECgYJCwAAAA==.Jonwic:BAAALgADCgIJAgAAAA==.',
Ju='Judge:BAAALgAECgYJBgABLgAECggJHwAXABQVAA==.',
Ka='Kaelostrasza:BAAALgAECgYJDAABLgAFFAQJBgACANgMAA==.Kallindrya:BAAALgADCgkJDQAAAA==.Kass:BAAALgADCgcJEgAAAA==.Kasselliea:BAAALgADCgEJAQAAAA==.Kaveros:BAAALgAECgUJDQAAAA==.',
Ke='Kelaan:BAAALgAECgYJEAAAAA==.Kelimao:BAABLgAECn8bAAMcAAcJVAvTCgBAAQAcAAcJVAvTCgBAAQAWAAMJKwy2ogCEAAAAAA==.Kellin:BAAALgADCgMJAwAAAA==.Kelthannaras:BAAALgAECgYJEQAAAA==.Kendrà:BAAALgADCgMJAwAAAA==.Kerunirus:BAAALgADCgYJBgAAAA==.Kevinns:BAAALgAECgMJBAAAAA==.Kevwave:BAAALgAECgMJBQAAAA==.',
Ki='Kilian:BAAALgAECgYJDwAAAA==.Killoroc:BAAALgADCgYJDQAAAA==.Kiritos:BAAALgAECgMJBwAAAA==.Kiserys:BAAALgAECgUJBgAAAA==.',
Ko='Kohor:BAAALgADCgUJBQAAAA==.Koko:BAAALgADCgMJAwAAAA==.Komekaka:BAAALgADCgQJCAAAAA==.Korpse:BAAALgAECgIJAgAAAA==.Kostard:BAAALgADCgEJAQAAAA==.',
Kr='Kryemhild:BAAALgADCggJEAAAAA==.Krysto:BAABLgAECn8WAAIJAAcJyxKUDwCFAQAJAAcJyxKUDwCFAQAAAA==.',
Kw='Kwatli:BAAALgADCgYJCgAAAA==.',
Ky='Kyferon:BAAALgADCgIJAgAAAA==.Kyral:BAAALgADCgIJAgAAAA==.',
La='Ladiegp:BAAALgADCgEJAQAAAA==.Lanria:BAAALgAECgMJBQAAAA==.Laquisha:BAABLgAECn8VAAIHAAYJYhbWPwClAQAHAAYJYhbWPwClAQAAAA==.Lays:BAAALgADCgQJBAAAAA==.Lazarusgrimm:BAAALgADCgIJAgAAAA==.',
Le='Lelét:BAAALgADCgYJDwAAAA==.Lenin:BAAALgAECgEJAQAAAA==.Lexicology:BAAALgAECgQJBgABLgAECgQJCAAFAAAAAA==.',
Li='Lickithom:BAAALgAECgQJBQAAAA==.Lilgup:BAAALgADCgUJBgAAAA==.Lilydari:BAAALgAECgQJCgAAAA==.Limerick:BAAALgAECgEJAQAAAA==.Limitless:BAAALgADCgcJBwAAAA==.Linaa:BAAALgADCgEJAQAAAA==.Lissathshonk:BAAALgAECgEJAQAAAA==.',
Lo='Lookforlight:BAABLgAECn8uAAIUAAkJ6CMaCABTAwAUAAkJ6CMaCABTAwAAAA==.Lorenth:BAABLgAECn8bAAIBAAcJAQYKDgAPAQABAAcJAQYKDgAPAQAAAA==.',
Lu='Lucid:BAAALgADCgEJAQAAAA==.Luckyjade:BAAALgAECgUJDAAAAA==.Luunya:BAABLgAECn8UAAQDAAgJ/QyVBwB1AQADAAgJ/QyVBwB1AQABAAUJvwjqVwDVAAACAAEJDALwaQAjAAAAAA==.',
Ly='Lyralia:BAAALgADCgkJEQAAAA==.',
Ma='Mabi:BAAALgAECgEJAQAAAA==.Madcowburger:BAAALgAECgMJBQAAAA==.Madelyine:BAAALgADCgIJAgAAAA==.Mageyoulookk:BAAALgAECgYJDQAAAA==.Mahziir:BAAALgAECgYJBwAAAA==.Maithieran:BAAALgADCgYJDAAAAA==.Maizen:BAAALgAECgQJBQABLgAECgQJCAAFAAAAAA==.Majax:BAAALgAECgYJEAAAAA==.Malidros:BAAALgAECgYJCwAAAA==.Manogawd:BAAALgAECgUJCgAAAA==.Manwathiel:BAAALgADCgMJAwAAAA==.Marhault:BAABLgAECn8jAAMJAAgJdCLHBAAxAgAJAAgJdCLHBAAxAgAKAAUJCxLaVQDyAAAAAA==.Marriage:BAAALgAECgQJBQAAAA==.Masitaka:BAAALgAECgQJCAAAAA==.Mathollas:BAAALgADCgUJBQAAAA==.Matt:BAAALgAECgEJAQAAAA==.Maxicat:BAAALgAECgQJBQAAAA==.Maximus:BAAALgAECgYJEQAAAA==.Mayaplc:BAAALgADCgEJAQAAAA==.Mazah:BAABLgAECn8hAAMdAAcJDRKsEACrAQAdAAcJDRKsEACrAQAQAAEJMiBdJQBeAAABLgAECggJFAADAP0MAA==.Mazlo:BAAALgAECgQJBwAAAA==.',
Mc='Mckrakin:BAAALgADCgEJAQAAAA==.Mclovìns:BAAALgADCgEJAQAAAA==.',
Me='Mechanix:BAAALgAECgMJAwAAAA==.Meibao:BAABLgAECn8fAAIXAAgJFBXNIwDkAQAXAAgJFBXNIwDkAQAAAA==.Meleebrain:BAABLgAECn8fAAIGAAgJEhNERADiAQAGAAgJEhNERADiAQAAAA==.Messalina:BAAALgADCgUJCAABLgAECgYJCwAFAAAAAA==.Mex:BAAALgADCgMJBAAAAA==.',
Mi='Miaoyi:BAAALgADCgEJAQAAAA==.Millîe:BAAALgAECgQJBgAAAA==.Missclick:BAAALgAECgQJBQAAAA==.Mistbringer:BAAALgAECgQJCAAAAA==.Mistmaker:BAAALgADCgcJDAABLgAECgcJEwAFAAAAAA==.Miwi:BAAALgAECgUJBgAAAA==.',
Mo='Moiest:BAAALgADCgcJBwABLgAECgUJEAAFAAAAAA==.Moiesttuna:BAAALgAECgUJEAAAAA==.Monfalauda:BAAALgADCgEJAgAAAA==.Monkazz:BAAALgADCgYJEAAAAA==.Monkorith:BAACLgAFFH8LAAIXAAQJngcRBgAVAQAXAAQJngcRBgAVAQAuAAQKfyAAAhcACQlaEJ4kAN0BABcACQlaEJ4kAN0BAAAA.Moongyal:BAABLgAECn8UAAIWAAgJKxa0CQC/AQAWAAgJKxa0CQC/AQAAAA==.Mordoboinik:BAAALgAECgEJAQAAAA==.Mortis:BAAALgADCgQJCgAAAA==.Mosaden:BAAALgAECgYJDgAAAA==.',
Mu='Mudahnk:BAAALgADCgUJBQAAAA==.Mullett:BAAALgAECgYJEgAAAA==.',
My='Mymeii:BAAALgAECgEJAgAAAA==.Mysticheart:BAAALgADCgEJAQAAAA==.Mystogaan:BAAALgAECgUJBQAAAA==.',
['Mï']='Mïra:BAAALgAECgYJCgABLgAECgYJEAAFAAAAAA==.',
Na='Nakiki:BAAALgAECgQJBgAAAA==.Nastyiam:BAABLgAECn8aAAIdAAcJ3RCJEACuAQAdAAcJ3RCJEACuAQAAAA==.',
Ne='Necromeany:BAAALgADCgQJBwABLgAECgYJHgAHAMojAA==.Nennya:BAAALgAECgYJCwAAAA==.Nerfornothin:BAAALgAECgQJCwAAAA==.Nethflap:BAABLgAECn8cAAMeAAgJdRDnHwDCAQAeAAgJdRDnHwDCAQAaAAUJZQVoMQDlAAAAAA==.Netsmear:BAAALgAECgYJCwAAAA==.Newdawn:BAAALgAECgIJAgAAAA==.',
Ni='Niftypackage:BAAALgADCgcJDwAAAA==.Nik:BAABLgAECn8hAAMBAAgJrBuVEABfAgABAAgJVRqVEABfAgADAAcJchIIKwBCAQAAAA==.',
No='Nosferato:BAAALgADCgUJBgAAAA==.',
Nu='Nutmilker:BAABLgAECn8nAAIdAAgJuiR7AACSAgAdAAgJuiR7AACSAgAAAA==.',
Ny='Nycterine:BAAALgAECgEJAQAAAA==.Nyxnight:BAAALgADCgYJBgAAAA==.',
Oa='Oakenhart:BAAALgAECgIJAgAAAA==.Oathtaker:BAAALgADCgQJBAAAAA==.',
Ob='Obi:BAAALgAECgQJBQAAAA==.',
Ok='Okoye:BAAALgADCgcJBwAAAA==.',
Ol='Olahla:BAAALgADCgYJCwAAAA==.',
Om='Omacron:BAAALgADCgIJAgAAAA==.',
Op='Ophriala:BAAALgADCgMJAwAAAA==.Optimistic:BAAALgAECgEJAQAAAA==.',
Or='Oriion:BAAALgAECgEJAQAAAA==.Orthae:BAAALgADCgUJBQABLgADCggJEQAFAAAAAA==.',
Pa='Paladio:BAAALgADCgUJCgAAAA==.Pandoosevelt:BAAALgADCgkJDgAAAA==.',
Pe='Pelotuda:BAAALgAECgQJBAAAAA==.Penix:BAAALgADCgEJAQAAAA==.Petrovna:BAAALgAECgIJAgAAAA==.',
Pi='Picklerickz:BAAALgADCgYJBgAAAA==.Pikagosa:BAACLgAFFH8HAAMbAAMJsARNBwCVAAAbAAIJ8wNNBwCVAAAeAAMJ/gM6DgCSAAAuAAQKfykAAx4ACQkhFmQSAFcCAB4ACQn+EmQSAFcCABsABwkKGk0NAAQCAAAA.Pilgor:BAAALgAECgcJDQAAAA==.Pils:BAAALgADCgYJBgAAAA==.Pitchief:BAAALgAECgEJAQAAAA==.',
Pl='Plopping:BAAALgADCgMJAwAAAA==.',
Po='Pocky:BAAALgADCgMJAwAAAA==.',
Pr='Priestkidx:BAAALgADCggJCgAAAA==.Primax:BAAALgAECgIJAgAAAA==.',
Pu='Punchballz:BAAALgADCgIJAgAAAA==.Punchkín:BAAALgAECgYJEAAAAA==.',
['Pæ']='Pæsta:BAABLgAECn8bAAIMAAgJhRWDCQAoAgAMAAgJhRWDCQAoAgAAAA==.',
Ra='Ragepounce:BAAALgAECgYJCAAAAA==.Ragingblownr:BAAALgAECgQJBAABLgAECgYJDwAFAAAAAA==.Rangikü:BAAALgADCgkJDAAAAA==.Rast:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Rastabout:BAAALgAECgYJEgAAAA==.Rathannar:BAAALgAECgYJEAAAAA==.Ravel:BAABLgAECn8bAAIfAAcJ6h7EAgA7AgAfAAcJ6h7EAgA7AgAAAA==.Razah:BAAALgAECgYJDQAAAA==.',
Re='Reahla:BAAALgADCgcJBwAAAA==.Realchad:BAAALgAECgUJBQAAAA==.Redeem:BAAALgADCgEJAQAAAA==.Reios:BAABLgAECn8TAAIRAAcJExofEgCAAQARAAcJExofEgCAAQAAAA==.Remedis:BAAALgADCgYJBgAAAA==.Renara:BAAALgAECgMJAwAAAA==.Resora:BAAALgADCgMJAwAAAA==.',
Rh='Rhaz:BAAALgAECgQJCwAAAA==.Rhoup:BAAALgAECgUJDAABLgAECgYJCwAFAAAAAA==.',
Ri='Richter:BAAALgAECggJCAAAAA==.Rickyspanish:BAAALgAECgYJEgAAAA==.Rictor:BAAALgADCgEJAQAAAA==.Rifter:BAAALgAECgMJBgAAAA==.',
Ro='Roarke:BAAALgADCgMJAwAAAA==.',
Ru='Rubyouraw:BAAALgAECgUJDQAAAA==.Rubyus:BAAALgADCgcJBwAAAA==.Ruematoid:BAAALgAECgUJCgAAAA==.Ruffneck:BAABLgAECn8UAAIJAAYJpw56UgBxAQAJAAYJpw56UgBxAQAAAA==.Rumina:BAAALgAECgIJAwAAAA==.Russk:BAAALgADCgUJBQAAAA==.',
Sa='Saelirria:BAAALgADCggJCAABLgAECgkJIAAKAIMWAA==.Sailboat:BAAALgAECgEJAQAAAA==.Sakau:BAAALgAECgYJDQAAAA==.Sakurá:BAAALgAECgUJDAAAAA==.Samo:BAAALgAECgYJEQAAAA==.Sandarr:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgQJCgAAAA==.Saphran:BAAALgAECgEJAQAAAA==.Sargemarge:BAAALgAECgIJAgAAAA==.Sauccy:BAAALgAECgEJAQAAAA==.',
Sc='Scaly:BAABLgAECn8cAAMaAAgJgg/KHQCUAQAaAAgJgg/KHQCUAQAeAAMJOA2OFAC1AAAAAA==.Scrotosaggin:BAAALgAECgUJBQAAAA==.',
Se='Seafoame:BAAALgADCgcJCAABLgAFFAEJAQAFAAAAAA==.See:BAABLgAFFH8GAAIgAAMJlw81BAD2AAAgAAMJlw81BAD2AAAAAA==.Selener:BAAALgAECgYJDgAAAA==.Sendisth:BAAALgADCgYJDQABLgAFFAIJBQAdAKIPAA==.Serrata:BAAALgAECgEJAgAAAA==.Severus:BAAALgAECgUJBQAAAA==.',
Sh='Shadoryan:BAAALgADCgYJBgABLgAECgcJEwARAFkdAA==.Shaggiê:BAAALgAECgYJBgAAAA==.Shamydavisjr:BAAALgADCgEJAQAAAA==.Shellenne:BAAALgADCgIJAQAAAA==.Shikamáru:BAAALgAECgcJCAAAAA==.',
Si='Silther:BAABLgAECn8VAAIUAAcJdRscDgC5AQAUAAcJdRscDgC5AQAAAA==.Sinnabun:BAAALgAECgIJAgAAAA==.',
Sl='Slapslap:BAAALgAECgIJAgAAAA==.Slavka:BAAALgADCggJCgAAAA==.Sleepyjoee:BAAALgAECgMJBQABLgAECgYJDQAFAAAAAA==.Sleepypriest:BAAALgADCgIJAgABLgAECgYJDQAFAAAAAA==.Sleepyyjoe:BAAALgAECgQJBAABLgAECgYJDQAFAAAAAA==.Slock:BAAALgAECgEJAQAAAA==.Slothymoon:BAAALgADCgcJBwAAAA==.',
Sm='Smalliam:BAAALgADCgYJDgABLgAECggJGgAdAN0QAA==.Smoted:BAAALgADCgUJBQAAAA==.',
Sn='Snaerbear:BAAALgADCgUJCgABLgAECgkJLgAUAOgjAA==.Snâppy:BAAALgAECgYJEQAAAA==.',
So='Soloron:BAAALgAECgQJCwAAAA==.Sorceremy:BAAALgAECgYJEAAAAA==.Southvik:BAAALgADCgUJCAABLgAECgYJFwABALAhAA==.',
Sp='Sparke:BAAALgAECgIJBQAAAA==.Sparrhawk:BAAALgAECgMJAwAAAA==.Spiced:BAABLgAECn8hAAIcAAgJ2yQbBQBOAwAcAAgJ2yQbBQBOAwAAAA==.Spiceweasel:BAAALgAECgEJAQAAAA==.Spiritbound:BAAALgAECgIJAgAAAA==.',
St='Starskream:BAAALgADCgkJDAAAAA==.Steliokontos:BAAALgAECgUJBgAAAA==.Stickes:BAAALgADCgUJBwAAAA==.Stormclaw:BAAALgAECgQJBQAAAA==.Streea:BAAALgADCgcJBwABLgADCggJEQAFAAAAAA==.Sttriker:BAABLgAECn8fAAIPAAgJZQRkMABNAQAPAAgJZQRkMABNAQAAAA==.',
Su='Survival:BAAALgAECgMJBgABLgAFFAQJCAATAKIbAA==.Suzierulz:BAAALgAECgQJBAAAAA==.',
Sw='Sweetcheese:BAAALgAECgEJAQAAAA==.',
Sy='Syn:BAAALgADCgkJCgAAAA==.Synsairis:BAABLgAECn8aAAIOAAYJ4B/aBgBxAQAOAAYJ4B/aBgBxAQAAAA==.',
Ta='Talietha:BAAALgADCgUJBQAAAA==.Tallonk:BAAALgADCgEJAQAAAA==.Talonknight:BAAALgAECgYJEQAAAA==.Talset:BAABLgAECn8WAAIXAAcJ1ArPDAAjAQAXAAcJ1ArPDAAjAQAAAA==.Taurrows:BAAALgADCgMJAwAAAA==.',
Tb='Tbill:BAAALgAECgUJCAAAAA==.',
Te='Teaux:BAAALgADCgQJBQAAAA==.Tenson:BAAALgAECgQJBgAAAA==.',
Th='Thad:BAAALgADCgYJBgAAAA==.Thaendofyou:BAAALgAECggJCwAAAA==.Thagda:BAAALgAECgcJDAAAAA==.Theevoker:BAAALgAECgcJEQAAAA==.Theproject:BAAALgAECgcJBgAAAA==.Thestarman:BAAALgADCgUJBQAAAA==.Tholnar:BAAALgAECgUJDAAAAA==.Thoroughbred:BAAALgADCgIJAgAAAA==.Throwdini:BAABLgAECn8hAAIJAAgJhh/bBAAuAgAJAAgJhh/bBAAuAgAAAA==.',
Ti='Tigerboy:BAAALgAECgUJBQAAAA==.Timotthy:BAAALgAECgYJBwAAAA==.Titant:BAAALgADCgEJAQAAAA==.Titanta:BAAALgAECgQJCQAAAA==.',
Tm='Tmate:BAAALgAECgYJCQAAAA==.',
To='Totempics:BAAALgADCgUJBQABLgAECggJIQAWAAAgAA==.Touchmé:BAAALgAECgMJAwAAAA==.',
Ts='Tsunaris:BAABLgAECn8VAAIKAAcJSBY1KgDXAQAKAAcJSBY1KgDXAQAAAA==.',
Tu='Tulanis:BAABLgAECn8jAAIKAAgJgRrXAQDUAQAKAAgJgRrXAQDUAQAAAA==.Turbotax:BAAALgAECgQJBAAAAA==.',
Ty='Tyriem:BAABLgAECn8cAAIJAAgJiBilBwDvAQAJAAgJiBilBwDvAQAAAA==.Tyssanton:BAABLgAECn8WAAQaAAcJJgKnMgDZAAAaAAYJTAKnMgDZAAAbAAUJZQJuBgCKAAAeAAEJgQEUJAAkAAAAAA==.',
Tz='Tziganin:BAABLgAECn8bAAIdAAcJ4RdRAwCcAQAdAAcJ4RdRAwCcAQAAAA==.',
Ug='Uggork:BAAALgAECgYJCAAAAA==.',
Un='Unholybussy:BAABLgAECn8bAAITAAcJjRdGEACUAQATAAcJjRdGEACUAQAAAA==.Unicorns:BAAALgAECgEJAQAAAA==.',
Ur='Urvazlite:BAAALgAECgYJEQAAAA==.',
Ut='Utaadh:BAAALgAECgYJDgAAAA==.',
Va='Vallerin:BAAALgAECgYJEgAAAA==.Vanestor:BAAALgADCgkJCQABLgAFFAMJCAAJAKARAA==.Varahk:BAAALgADCgMJAwAAAA==.Varus:BAAALgADCggJFAAAAA==.',
Ve='Velaar:BAABLgAECn8gAAITAAgJ3SP4DQArAwATAAgJ3SP4DQArAwABLgAECgYJEAAFAAAAAA==.Velamuna:BAAALgADCgQJBAAAAA==.Velindraela:BAAALgADCgMJAgABLgAECggJIQAWAAAgAA==.',
Vi='Vikthyr:BAAALgADCgYJBgABLgAECgYJFwABALAhAA==.Villain:BAAALgADCgYJBgABLgAECggJIwAJAHQiAA==.',
Vo='Vodnar:BAACLgAFFH8IAAMJAAMJoBEmDQD3AAAJAAMJoBEmDQD3AAAKAAEJegD9LQA1AAAuAAQKfyIAAwkACQlrG1kZAHACAAkACAnwHlkZAHACAAoABglhCFBHADYBAAAA.Vohnkhar:BAAALgADCgEJAQAAAA==.Voidatfear:BAAALgAECgMJBQAAAA==.Voidhunter:BAAALgADCgYJBgAAAA==.Voodoodoo:BAAALgAECgYJDwAAAA==.Voxramus:BAAALgADCgQJBAABLgAECgMJBgAFAAAAAA==.',
Vu='Vulcos:BAAALgAECgQJBQAAAA==.',
Vy='Vyreth:BAAALgAECgIJAwAAAA==.',
Wa='Walls:BAAALgAECgYJDQAAAA==.Waste:BAAALgAECgcJCAAAAA==.',
We='Werragan:BAAALgADCgcJBwAAAA==.',
Wh='Whipps:BAAALgAECgYJBgAAAA==.',
Wi='Wilt:BAAALgADCggJFAAAAA==.',
Wo='Wompazuzu:BAAALgAECgYJDgAAAA==.',
Wr='Wraithewyn:BAAALgADCgUJBwAAAA==.Wrékt:BAAALgADCgMJAwAAAA==.',
Xa='Xanosina:BAAALgAECgQJBAAAAA==.',
Yi='Yilongma:BAAALgAECgIJAwAAAA==.',
Yl='Ylaran:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAECgYJEAAAAA==.',
Yo='Yogí:BAABLgAECn8dAAIdAAgJEBfVAQD0AQAdAAgJEBfVAQD0AQAAAA==.Yokos:BAAALgAECgQJBQAAAA==.Yonokojo:BAAALgADCgYJBgAAAA==.',
Za='Zacksquach:BAAALgADCgMJAwAAAA==.Zahneel:BAABLgAECn8bAAIWAAcJ9BjyCQC6AQAWAAcJ9BjyCQC6AQAAAA==.Zalanar:BAAALgADCgkJDAAAAA==.Zaney:BAAALgAECgYJEQAAAA==.Zaps:BAAALgAECgEJAQAAAA==.Zaratul:BAACLgAFFH8GAAIUAAMJQxZMHgC0AAAUAAMJQxZMHgC0AAAuAAQKfyMAAhQACQmBIAgIAFQDABQACQmBIAgIAFQDAAAA.Zaroth:BAABLgAECn8cAAIBAAgJuhTQJwCxAQABAAgJuhTQJwCxAQAAAA==.',
Ze='Zeleste:BAAALgAECgUJCQAAAA==.Zelnorac:BAAALgAECgQJBgAAAA==.Zenma:BAAALgAECgMJAwAAAA==.Zerovii:BAACLgAFFH8FAAIdAAIJog99AgClAAAdAAIJog99AgClAAAuAAQKfx0AAh0ACAndHSYEAOACAB0ACAndHSYEAOACAAAA.Zetsubou:BAAALgAECgMJAwAAAA==.',
Zh='Zharrak:BAAALgAECgUJCAAAAA==.',
Zi='Zilyana:BAAALgAECgQJBAAAAA==.',
Zu='Zubuûuûuûuûu:BAAALgADCgUJBQAAAA==.',
Zy='Zyrian:BAAALgADCgkJHgAAAA==.',
['Zä']='Zärthan:BAAALgADCgIJAgAAAA==.',
['Éd']='Édz:BAAALgAECgQJBgAAAA==.',
['Ía']='Íamjakehill:BAAALgAECgMJBgAAAA==.',
['Îr']='Îris:BAAALgADCgcJEAAAAA==.',
['Ör']='Örnak:BAAALgADCgUJBQAAAA==.',
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

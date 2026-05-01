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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Shaman-Restoration','Mage-Arcane','Monk-Windwalker','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Druid-Balance','DeathKnight-Unholy','Rogue-Assassination','Druid-Restoration','Druid-Feral','Monk-Brewmaster','Warrior-Protection','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Monk-Mistweaver',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aassvik:BAABLgAECn8eAAIBAAcJQyGeBQBnAgABAAcJQyGeBQBnAgAAAA==.',
Ac='Achievless:BAAALgAECgYJCAAAAA==.Achievsome:BAACLgAFFH8QAAQCAAUJVh8rAwCEAQACAAUJVh8rAwCEAQADAAQJFgnOCwAdAQABAAEJgAiUFgA7AAAuAAQKfyUABAIACQn2IDgFAEgCAAIACAn7IDgFAEgCAAEAAwnjGYdTAOkAAAMAAQm8HhxOAFkAAAAA.',
Ad='Adava:BAAALgAECgYJDAABLgAFFAUJDwAEAAchAA==.Adennoko:BAAALgADCgkJCQAAAA==.',
Ae='Aery:BAAALgADCgcJBwAAAA==.Aesomx:BAAALgAECgEJBQABLgAECgIJAwAFAAAAAA==.',
Ag='Agrajag:BAAALgADCgkJCQABLgAECggJIAAGAIIXAA==.',
Ai='Aiona:BAAALgAECgUJBQAAAA==.Aithea:BAAALgAECgQJBAAAAA==.',
Ak='Akagrats:BAAALgAECgYJDAAAAA==.Aknutiak:BAAALgAECgIJAgAAAA==.',
Al='Aldenwarlock:BAAALgAECgQJCgAAAA==.Alekhine:BAAALgADCgIJAgAAAA==.Alestar:BAAALgADCgYJBgABLgAECgYJEAAFAAAAAA==.Aliengrey:BAAALgAECgUJDQAAAA==.Allimore:BAAALgAECgQJBQAAAA==.Alonsusfaol:BAAALgADCgUJBgAAAA==.Alyx:BAAALgADCgEJAQAAAA==.',
Am='Amane:BAAALgAECgcJEwAAAA==.American:BAAALgAECgUJCQAAAA==.Amulisha:BAAALgADCgkJHgAAAA==.Amytenchi:BAAALgADCgYJBgAAAA==.',
An='Angrystake:BAAALgADCgMJAwAAAA==.Annya:BAABLgAECn8XAAIBAAgJFRJLLACWAQABAAgJFRJLLACWAQAAAA==.Anowon:BAAALgADCgcJBwABLgAECgkJCwAFAAAAAA==.',
Ar='Arassaka:BAAALgAECgYJCQAAAA==.Archdragon:BAAALgAECgUJCAAAAA==.Arcius:BAAALgAECgYJDQAAAA==.Aristae:BAAALgAECgEJAQABLgAECgYJGQAHAAsWAA==.Arkanis:BAABLgAECn8oAAIIAAgJNRxHBgBPAgAIAAgJNRxHBgBPAgAAAA==.Arlestia:BAAALgADCgEJAQAAAA==.Armament:BAABLgAECn8YAAMJAAgJQRJoDQAtAQAIAAcJdQpgRACSAQAJAAYJhxFoDQAtAQAAAA==.Arrolexancas:BAAALgAECgYJEQAAAA==.Arrows:BAAALgADCgQJBAAAAA==.Arturiouss:BAABLgAECn8aAAIKAAgJxxEjDABPAQAKAAgJxxEjDABPAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.Arzuul:BAAALgAECgUJDQAAAA==.',
As='Ashlenna:BAAALgAECgMJAwAAAA==.',
At='Athira:BAAALgADCgUJBQAAAA==.',
Au='Audi:BAAALgAECgEJAQAAAA==.Auid:BAAALgADCgUJBQAAAA==.Aurafiora:BAABLgAECn8wAAMLAAgJqyD6EgCfAgALAAgJqyD6EgCfAgAMAAIJjQxadgBlAAAAAA==.Aurelio:BAABLgAECn8aAAINAAYJZhy3LgDIAQANAAYJZhy3LgDIAQAAAA==.Auther:BAAALgAECgEJAQAAAA==.',
Av='Avalancha:BAABLgAECn8cAAIOAAcJXxIGCQBHAQAOAAcJXxIGCQBHAQAAAA==.Avangela:BAAALgAECgYJBQAAAA==.Avanish:BAAALgADCgEJAQABLgAECgQJBAAFAAAAAA==.Avinoch:BAAALgAECgYJEAAAAA==.',
Aw='Awenyedd:BAAALgAECgMJAwAAAA==.',
Ax='Axon:BAAALgADCgcJBwAAAA==.',
Az='Azaliene:BAAALgAECgQJBAAAAA==.Azambregon:BAAALgADCgcJCwAAAA==.Azenroth:BAAALgAECgEJAQAAAA==.Azulhail:BAAALgAECgQJCAAAAA==.Azurhan:BAAALgADCgMJAwAAAA==.',
Ba='Bahadir:BAAALgADCgEJAQAAAA==.Bakimono:BAAALgAECgMJBQAAAA==.Banehellborn:BAAALgAECgIJAgAAAA==.Barloran:BAAALgADCgEJAQAAAA==.Bastoosebata:BAAALgAECgYJCAAAAA==.Bazzi:BAAALgAECgMJBAAAAA==.',
Be='Bearbud:BAAALgADCggJCAABLgAFFAQJDgAPAJ0dAA==.Beardicuss:BAAALgAECgQJCgAAAA==.Beastdrank:BAAALgAECgMJAwAAAA==.Beauxjingles:BAAALgAECgQJBAAAAA==.Beezlebumon:BAAALgAECggJEQAAAA==.Belakor:BAAALgADCgMJAwAAAA==.Beld:BAAALgADCgYJBgAAAA==.Bellcross:BAAALgAECgYJDAAAAA==.Bewater:BAAALgAECgQJBAAAAA==.',
Bh='Bhutcheeks:BAAALgAECgEJAQAAAA==.',
Bi='Birr:BAAALgADCgUJCAAAAA==.',
Bl='Bloomflow:BAAALgAECgYJDwAAAA==.',
Bo='Bobabear:BAAALgADCgMJAwAAAA==.Bonersimpsun:BAAALgAECgYJCAAAAA==.Boomclap:BAABLgAECn8fAAIQAAgJTBrlDQAQAgAQAAgJTBrlDQAQAgAAAA==.',
Bp='Bpbreezy:BAACLgAFFH8HAAIBAAMJ1x3mCAAKAQABAAMJ1x3mCAAKAQAuAAQKfysAAwEACQmlIX4CAEIDAAEACQmlIX4CAEIDAAIAAQmRDy88AEEAAAAA.',
Br='Bracknor:BAABLgAECn8iAAILAAgJ1BU+MgDnAQALAAgJ1BU+MgDnAQAAAA==.Brandonb:BAABLgAECn8rAAMEAAgJ+R4nDACEAgAEAAgJ+R4nDACEAgARAAEJNhbiHAA5AAAAAA==.Brandondh:BAABLgAECn8YAAIGAAYJRxsKIgBmAQAGAAYJRxsKIgBmAQAAAA==.Bredock:BAABLgAECn8VAAIHAAYJYhg2NwBnAQAHAAYJYhg2NwBnAQABLgAFFAMJCwALAJUVAA==.Brickmitts:BAAALgADCgYJBwAAAA==.Brittlehorn:BAAALgADCgEJAQAAAA==.Brotem:BAAALgAECgcJEwAAAA==.Broth:BAAALgAECgQJCgAAAA==.',
Bu='Bullshamy:BAAALgADCgIJAgAAAA==.Bulwarkk:BAAALgADCgkJCwAAAA==.Bumblbeetuna:BAAALgADCgcJEQAAAA==.Bumperdemon:BAAALgAECgQJBgAAAA==.Burkisure:BAAALgADCgYJBgAAAA==.',
By='Bysokar:BAABLgAECn8cAAISAAgJMxdoFABKAgASAAgJMxdoFABKAgAAAA==.',
['Bü']='Büllshift:BAAALgADCgQJBAAAAA==.',
Ca='Cainfortea:BAAALgADCgkJFQAAAA==.Cakecity:BAABLgAECn8jAAITAAgJBh/wAwBLAgATAAgJBh/wAwBLAgAAAA==.Calikillaoi:BAAALgADCgcJCAAAAA==.Calimage:BAAALgADCgYJCwAAAA==.Calipal:BAAALgAECgYJDQAAAA==.Caskashah:BAAALgAECgEJAgAAAA==.Catalïna:BAAALgADCgUJBQABLgAFFAUJCgAQAN8bAA==.Catälina:BAACLgAFFH8KAAIQAAUJ3xtzBQB1AQAQAAUJ3xtzBQB1AQAuAAQKfy8AAhAACAnOIm0KANQCABAACAnOIm0KANQCAAAA.',
Ce='Celebrimbjor:BAAALgADCggJCQAAAA==.Cerberusbone:BAAALgAECgEJAgAAAA==.',
Ch='Cheddthyr:BAAALgAECgQJBAAAAA==.Cherubim:BAAALgAECgEJAQAAAA==.Chrnobog:BAABLgAECn8iAAQUAAgJyhqZEQC/AQAPAAcJbBytOAApAgAUAAYJqBaZEQC/AQAVAAQJNR1TDgBNAQABLgAFFAQJDgAPAJ0dAA==.',
Ci='Cinderlily:BAAALgAECgEJAQAAAA==.Cinderz:BAAALgADCgIJAgAAAA==.',
Cl='Classicoil:BAAALgADCgEJAQAAAA==.Clayprincess:BAAALgAECgMJAwABLgAECgcJEgAFAAAAAA==.',
Co='Cocoyibobo:BAAALgAECgQJBQAAAA==.Colty:BAAALgADCgcJDQAAAA==.Conflagrate:BAABLgAECn8bAAIPAAgJQiJPBgCqAgAPAAgJQiJPBgCqAgAAAA==.Coolbeamz:BAAALgAECgQJBgAAAA==.Corvik:BAAALgADCgEJAQAAAA==.',
Cp='Cptcrushingb:BAAALgAECgEJAgAAAA==.',
Cr='Crazyhamster:BAAALgAECgQJBAAAAA==.Crithappens:BAABLgAECn8oAAIEAAgJtxs4PACGAgAEAAgJtxs4PACGAgAAAA==.Criturrpants:BAAALgAECgYJCQAAAA==.',
Cu='Cute:BAAALgADCgYJBwAAAA==.',
Cy='Cyb:BAAALgADCgEJAQAAAA==.Cynnå:BAAALgAECggJEgAAAA==.Cyp:BAAALgAECgEJAQAAAA==.',
['Cü']='Cüpcake:BAAALgAECggJDgAAAA==.',
Da='Daikirí:BAABLgAECn8aAAIWAAYJhAXhJwDIAAAWAAYJhAXhJwDIAAAAAA==.Damienator:BAAALgAECgMJBwAAAA==.Dankiferus:BAAALgADCgcJBwAAAA==.Dannyy:BAAALgAECgMJAwAAAA==.Darren:BAAALgADCgYJBgAAAA==.Dawrk:BAAALgAECgQJBgAAAA==.',
De='Deadincide:BAABLgAECn8aAAIXAAgJuBYIFwACAgAXAAgJuBYIFwACAgAAAA==.Dearia:BAAALgADCgIJAQAAAA==.Decree:BAAALgAECgYJEgAAAA==.Delcid:BAAALgAECgQJBQABLgAECgcJDQAFAAAAAA==.Delik:BAABLgAECn8cAAIEAAcJqQglWgApAQAEAAcJqQglWgApAQAAAA==.Demonarch:BAAALgADCgUJCAAAAA==.Deneol:BAAALgAFFAEJAQAAAA==.Desola:BAAALgADCgEJAQAAAA==.Destrogen:BAABLgAECn8ZAAQVAAcJExowDgBPAQAVAAQJOR4wDgBPAQAPAAYJFRSGOABLAQAUAAIJgg2ITQCFAAAAAA==.Destïny:BAACLgAFFH8NAAIXAAQJ4xldFwBHAQAXAAQJ4xldFwBHAQAuAAQKfxcAAhcACAluIK4wAHUCABcACAluIK4wAHUCAAAA.Desìre:BAABLgAECn8cAAIDAAcJIRbGDwCSAQADAAcJIRbGDwCSAQAAAA==.Devastator:BAAALgAECgIJAwAAAA==.Deàthgirls:BAAALgADCgUJBQABLgAECgkJLgAHAOgjAA==.',
Di='Dinonuggies:BAAALgAECgEJAgAAAA==.Dirty:BAABLgAECn8jAAIEAAgJICDTDQBxAgAEAAgJICDTDQBxAgAAAA==.Discotheque:BAAALgAECgQJCAAAAA==.Disk:BAAALgAECgQJBgAAAA==.',
Dn='Dnice:BAAALgAECgEJAQAAAA==.',
Do='Doompalm:BAAALgADCgUJBQAAAA==.Doompulse:BAAALgADCgMJAwAAAA==.Doomshield:BAAALgAECgYJEAAAAA==.Doomshroud:BAAALgADCgMJAwABLgAECgcJEgAFAAAAAA==.Dorati:BAAALgAECgQJBwAAAA==.',
Dr='Drackiechan:BAAALgAECgMJAwABLgAFFAMJBwABANcdAA==.Dracodeez:BAABLgAECn8jAAIYAAgJxCKVAAC8AgAYAAgJxCKVAAC8AgAAAA==.Droobid:BAABLgAECn8fAAIZAAkJGB47BQA6AwAZAAkJGB47BQA6AwAAAA==.Drovosh:BAEALgAECgIJAgAAAA==.',
Dy='Dykenasty:BAABLgAECn8YAAIGAAcJ1B6tOAASAgAGAAcJ1B6tOAASAgAAAA==.Dyxx:BAAALgAECgEJAQAAAA==.',
Dz='Dzlightning:BAAALgAECgEJAQAAAA==.',
['Dò']='Dòóm:BAAALgADCgMJAwAAAA==.',
Ea='Earendur:BAAALgAECgUJDQAAAA==.',
Ec='Eciruma:BAAALgAECgEJAgAAAA==.',
Ei='Eiseth:BAAALgADCgUJBQAAAA==.',
El='Electronvolt:BAAALgADCgMJBAABLgAECggJGgAXALgWAA==.Elemeesel:BAAALgADCggJCQAAAA==.Eltael:BAAALgAECgUJEAAAAA==.Elæna:BAAALgADCgkJCQAAAA==.',
Em='Emilianaluz:BAAALgAECgEJAQAAAA==.',
En='Endeavor:BAAALgAECgQJBgAAAA==.Enkie:BAAALgADCgEJAQABLgAECgYJFQAEAM8YAA==.Enky:BAAALgAECgEJAQABLgAECgYJFQAEAM8YAA==.Enyxia:BAAALgADCggJEAAAAA==.',
Ep='Epikhotti:BAAALgAECgMJBQAAAA==.',
Er='Eradion:BAAALgAECgEJAwAAAA==.Erisson:BAAALgAECgkJAgAAAA==.Erlaandã:BAAALgADCgYJBgAAAA==.',
Es='Eszran:BAABLgAECn8UAAIaAAYJjQ6uCwAkAQAaAAYJjQ6uCwAkAQAAAA==.',
Eu='Euthanized:BAAALgADCgIJAgAAAA==.',
Ev='Evelleda:BAAALgADCgIJAgAAAA==.Evendell:BAAALgADCgcJBwAAAA==.',
Fa='Falys:BAAALgADCgYJCQAAAA==.Fasani:BAAALgAECgEJAQAAAA==.',
Fe='Feels:BAAALgAECgEJBgAAAA==.Feixiao:BAAALgADCgIJAwAAAA==.Felbro:BAAALgAECgMJAwAAAA==.Felraiser:BAAALgADCgkJHgAAAA==.Fendalein:BAAALgADCgUJBQAAAA==.Fennar:BAAALgAECgYJDQAAAA==.Ferosha:BAABLgAECn8WAAMKAAcJYBi3CgBmAQAKAAYJYxi3CgBmAQAXAAUJqRNHmABPAQABLgAECggJJAAbAEQVAA==.Fexxyr:BAAALgAECgQJBAABLgAFFAQJDQACAPEXAA==.',
Fi='Fidobedo:BAAALgADCgMJAwAAAA==.Firefly:BAAALgADCgEJAQAAAA==.Firstfear:BAAALgAECgMJBAAAAA==.Fisch:BAABLgAECn8jAAIcAAgJfSXoAADuAgAcAAgJfSXoAADuAgAAAA==.Fizzlepow:BAAALgADCgYJBgAAAA==.',
Fl='Flagrent:BAAALgAECgQJDQAAAA==.Flashico:BAAALgAECgYJDgAAAA==.Flemingo:BAAALgAECgIJAwAAAA==.Flemruk:BAAALgAECgcJDAAAAA==.Flemtaur:BAAALgAECgkJAgAAAA==.Flidd:BAABLgAECn8dAAIEAAgJtAhoPgBzAQAEAAgJtAhoPgBzAQAAAA==.Flipingtiska:BAAALgAECgIJAgAAAA==.Floret:BAAALgADCgMJAwAAAA==.Flowforth:BAAALgAECgUJBQAAAA==.Fluht:BAAALgADCgYJBgAAAA==.Flynae:BAABLgAECn8cAAIBAAcJchOcFABtAQABAAcJchOcFABtAQAAAA==.',
Fr='Frearyne:BAABLgAECn8YAAMZAAgJ+SOwBgAhAwAZAAgJ+SOwBgAhAwAaAAMJBg1+EQDBAAAAAA==.Friergren:BAACLgAFFH8HAAIEAAMJwxQzMQAHAQAEAAMJwxQzMQAHAQAuAAQKfyAAAgQACQkMHjQbAAoDAAQACQkMHjQbAAoDAAAA.Frostfight:BAAALgADCgYJBgAAAA==.Frylôck:BAAALgADCgIJAgABLgAECgYJFQAEAM8YAA==.',
Fs='Fstingnemo:BAAALgADCgUJCAAAAA==.',
Fy='Fyster:BAAALgAECgQJBAAAAA==.Fyxxer:BAABLgAECn8bAAIKAAkJkBXGBADwAQAKAAkJkBXGBADwAQABLgAFFAQJDQACAPEXAA==.Fyxxie:BAACLgAFFH8NAAICAAQJ8RfABgBQAQACAAQJ8RfABgBQAQAuAAQKfyIAAgIACQnqHGsHABIDAAIACQnqHGsHABIDAAAA.',
Ga='Galex:BAAALgADCgEJAQAAAA==.Garah:BAAALgADCgYJBwAAAA==.',
Ge='Geewonii:BAAALgADCgYJBgAAAA==.Geroesan:BAAALgADCggJCAAAAA==.Geron:BAAALgADCgMJAwAAAA==.',
Gh='Ghostchedd:BAAALgADCggJCwAAAA==.',
Gi='Gialiana:BAACLgAFFH8HAAIMAAQJ1wxlDQCdAAAMAAQJ1wxlDQCdAAAuAAQKfyAAAgwACQmDFr4XAGwCAAwACQmDFr4XAGwCAAAA.Giblar:BAAALgADCgUJBQAAAA==.Gikyounoshi:BAAALgADCgUJBQAAAA==.Girthen:BAABLgAECn8kAAMBAAgJyiLIBQDzAgABAAgJyiLIBQDzAgACAAMJKheCQwDfAAAAAA==.',
Gn='Gnx:BAAALgAECgQJCAAAAA==.',
Go='Goobby:BAABLgAECn8fAAIXAAgJviNeCQCKAgAXAAgJviNeCQCKAgAAAA==.Goonfred:BAAALgAECgQJBAAAAA==.',
Gr='Greenymeany:BAABLgAECn8eAAIIAAYJyiO4GwBvAgAIAAYJyiO4GwBvAgAAAA==.Grrimm:BAAALgADCgMJAwAAAA==.Grukk:BAAALgADCgYJCwABLgAECgMJBwAFAAAAAA==.Grully:BAABLgAECn8bAAIQAAkJsxF/KQDpAQAQAAkJsxF/KQDpAQAAAA==.Gruumsh:BAAALgAECgYJDQAAAA==.',
Ha='Haggard:BAABLgAECn8WAAIGAAcJ5RVdHgB8AQAGAAcJ5RVdHgB8AQAAAA==.Hailsbelle:BAABLgAECn8bAAITAAYJqg9iEgAeAQATAAYJqg9iEgAeAQAAAA==.',
Hb='Hbic:BAAALgAECgYJCwAAAA==.',
He='Healingpanda:BAAALgAECgQJBQAAAA==.Healyboar:BAABLgAECn8VAAINAAgJbxDPEQDPAQANAAgJbxDPEQDPAQAAAA==.Heartstabber:BAAALgADCggJCwAAAA==.Heascha:BAAALgADCgEJAQAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAQJBgAEAEwFAA==.Helado:BAAALgAECgEJAQAAAA==.Hellbane:BAAALgAECgYJBgAAAA==.Heri:BAAALgADCgEJAQAAAA==.',
Hi='Highwayman:BAAALgAECgUJDAABLgAECggJKQALAFwjAA==.Himwhome:BAAALgAECgMJBQAAAA==.',
Ho='Holyteamdiff:BAABLgAECn8ZAAIDAAgJmhWxFAAEAgADAAgJmhWxFAAEAgAAAA==.Holÿshut:BAAALgADCgEJAQABLgAECggJIAAQAHcXAA==.Hondurasman:BAAALgADCgYJDgAAAA==.Honkay:BAAALgAECgQJBgAAAA==.Honkhonk:BAABLgAECn8nAAIHAAgJMBUoKACiAQAHAAgJMBUoKACiAQAAAA==.',
Hu='Huahhuahhuah:BAAALgADCgcJFgABLgAECgYJEAAFAAAAAA==.Hulas:BAAALgAECgEJAQAAAA==.Hungidan:BAAALgADCgYJBgABLgAECgkJIAAdAPoPAA==.Huntdemonz:BAAALgAECgUJCAABLgAECgcJGwAIAMUYAA==.',
Ic='Icelynsnow:BAAALgADCgkJDAAAAA==.Icrono:BAAALgADCgIJAgAAAA==.Icwiener:BAAALgAECgYJEAAAAA==.',
Il='Illaria:BAAALgADCgIJAgAAAA==.Illumis:BAAALgAECgYJBgAAAA==.',
Im='Imjustpika:BAAALgADCgcJBwABLgAFFAUJCwAeAJYFAA==.',
In='Indeathinite:BAAALgADCgIJAgAAAA==.Inferniö:BAACLgAFFH8PAAIEAAUJByGKEAB9AQAEAAUJByGKEAB9AQAuAAQKfy0AAgQACQnnJGcEALoDAAQACQnnJGcEALoDAAAA.Inkurushio:BAABLgAECn8XAAMIAAYJ4g1cKQD7AAAIAAYJMgxcKQD7AAAJAAQJhAoSKgBAAAAAAA==.Insector:BAAALgADCgIJAgAAAA==.Inshallah:BAAALgAECgEJBAABLgAECgIJAwAFAAAAAA==.Inyoguts:BAAALgAECgcJBwAAAA==.',
Io='Iolanie:BAAALgAECgMJAwAAAA==.',
Ip='Ipewdmyself:BAAALgADCgYJCAAAAA==.',
Is='Ismat:BAABLgAECn8rAAIQAAgJ5h2aDgClAgAQAAgJ5h2aDgClAgAAAA==.',
Iv='Ivorybones:BAAALgAECgYJEQAAAA==.',
Ix='Ixxi:BAAALgADCgUJBQAAAA==.Ixxia:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Ixxy:BAAALgADCgYJBgAAAA==.',
Iz='Izbiar:BAAALgADCgcJDAAAAA==.',
Ja='Jabahnzulash:BAAALgADCgcJEwABLgAFFAMJCwAXAPgaAA==.Jabzularu:BAAALgAECgcJEAAAAA==.Jaeko:BAABLgAECn8WAAISAAYJXw86NwBCAQASAAYJXw86NwBCAQAAAA==.Jaekyrn:BAAALgADCgIJAgABLgAECgYJFgASAF8PAA==.Jaeza:BAAALgADCggJEQAAAA==.Jarshh:BAABLgAECn8jAAIIAAgJKyA9BACBAgAIAAgJKyA9BACBAgAAAA==.',
Je='Jethic:BAAALgADCgUJCwAAAA==.Jezabell:BAAALgAECgYJBgAAAA==.',
Ji='Jibberwhocky:BAAALgADCgYJCgABLgAECgcJGQAVABMaAA==.',
Jo='Jonald:BAAALgAECggJEwAAAA==.Jonwic:BAAALgADCgIJAgAAAA==.',
Ju='Judge:BAAALgAECgYJCQABLgAECggJJAAbAEQVAA==.',
Ka='Kaelostrasza:BAABLgAFFH8GAAIeAAQJ3hChDgA7AQAeAAQJ3hChDgA7AQABLgAFFAUJBwACANkMAA==.Kallaiopi:BAAALgAECgMJAwAAAA==.Kallindrya:BAAALgADCgkJDQAAAA==.Kaly:BAAALgADCgEJAQAAAA==.Kass:BAAALgAECgEJAQAAAA==.Kasselliea:BAAALgADCgEJAQAAAA==.Kaveros:BAAALgAECgYJDQAAAA==.',
Ke='Kefurion:BAAALgAECgQJBAABLgAECgUJBwAFAAAAAA==.Kelaan:BAABLgAECn8WAAMfAAcJLxwvEAD+AAAfAAcJLxwvEAD+AAAHAAQJdhU6zwDrAAAAAA==.Kelimao:BAABLgAECn8jAAMWAAgJ7gvwEgByAQAWAAgJ7gvwEgByAQAZAAYJngjnSgClAAAAAA==.Kellin:BAAALgADCgMJAwAAAA==.Kelthannaras:BAABLgAECn8ZAAIMAAgJRBn0AwDaAQAMAAgJRBn0AwDaAQAAAA==.Kendrà:BAAALgADCgMJAwAAAA==.Kerunirus:BAAALgADCgYJBgAAAA==.Kevinns:BAAALgAECgQJCQAAAA==.Kevwave:BAAALgAECgMJBQAAAA==.Keyadon:BAAALgAECgMJAgAAAA==.',
Ki='Kilian:BAAALgAECgYJDwAAAA==.Killoroc:BAAALgADCgYJDQAAAA==.Kiritos:BAAALgAECgMJBwAAAA==.Kiserys:BAAALgAECgUJBwAAAA==.',
Ko='Kohor:BAAALgADCgUJBQAAAA==.Koko:BAAALgADCgYJCQAAAA==.Komekaka:BAAALgADCgQJCAAAAA==.Korpse:BAAALgAECgQJBQAAAA==.Kostard:BAAALgAECgEJAQAAAA==.',
Kr='Kryemhild:BAAALgADCggJEQAAAA==.Krysto:BAABLgAECn8cAAILAAcJOhP9JACGAQALAAcJOhP9JACGAQAAAA==.',
Kw='Kwatli:BAAALgADCgYJCgAAAA==.',
Ky='Kyferon:BAAALgADCgIJAgAAAA==.Kyral:BAAALgADCgIJAgAAAA==.',
La='Ladiegp:BAAALgADCgEJAQAAAA==.Lanria:BAAALgAECgMJBQAAAA==.Laquisha:BAABLgAECn8bAAIIAAcJxRiqGABrAQAIAAcJxRiqGABrAQAAAA==.Lays:BAAALgADCgQJBAAAAA==.Lazarusgrimm:BAAALgADCgIJAgAAAA==.',
Le='Lelét:BAAALgADCgYJDwAAAA==.Lenin:BAAALgAECgEJAQAAAA==.Lexicology:BAAALgAECgQJBgABLgAECgQJCAAFAAAAAA==.',
Li='Lickithom:BAAALgAECgQJBQAAAA==.Lilgup:BAAALgADCgUJBgAAAA==.Lilydari:BAAALgAECgUJDwAAAA==.Limerick:BAAALgAECgEJAQAAAA==.Limitless:BAAALgADCgcJBwAAAA==.Linaa:BAAALgADCgEJAQAAAA==.Lishna:BAAALgADCgYJBgAAAA==.Lissathshonk:BAAALgAECgEJAQAAAA==.',
Lo='Lookforlight:BAABLgAECn8uAAIHAAkJ6CMdCABTAwAHAAkJ6CMdCABTAwAAAA==.Lorenth:BAABLgAECn8jAAIBAAgJkgfaGABDAQABAAgJkgfaGABDAQAAAA==.',
Lu='Lucid:BAAALgADCgEJAQAAAA==.Luckyjade:BAAALgAECgYJEQAAAA==.Luunya:BAABLgAECn8cAAQDAAgJ/QyaEgBpAQADAAgJ/QyaEgBpAQACAAgJBQgAFQBYAQABAAUJvwjuVwDVAAAAAA==.',
Ly='Lyralia:BAAALgADCgkJEQAAAA==.',
Ma='Mabi:BAAALgAECgEJAQAAAA==.Madcowburger:BAAALgAECgQJBgAAAA==.Madelyine:BAAALgADCgIJAgAAAA==.Mageyoulookk:BAAALgAECgYJDwAAAA==.Mahziir:BAAALgAECgYJBwAAAA==.Maithieran:BAAALgADCgYJDAAAAA==.Maizen:BAAALgAECgQJBQABLgAECgQJCAAFAAAAAA==.Majax:BAAALgAFFAEJAgAAAA==.Malidros:BAAALgAECgYJEgAAAA==.Manogawd:BAAALgAECgUJCgAAAA==.Manwathiel:BAAALgADCgMJAwAAAA==.Marhault:BAABLgAECn8pAAQLAAgJXCN2EAC2AgALAAgJdCJ2EAC2AgAgAAYJhR8kCADkAQAMAAUJCxLUVQDyAAAAAA==.Marriage:BAAALgAECgQJBQAAAA==.Masitaka:BAAALgAECgQJCAAAAA==.Mathollas:BAAALgAECgUJBQAAAA==.Matt:BAAALgAECgEJAQAAAA==.Maxicat:BAAALgAECgQJBgAAAA==.Maximus:BAABLgAECn8VAAIHAAcJ9xRkKgCYAQAHAAcJ9xRkKgCYAQAAAA==.Mayaplc:BAAALgADCgEJAQAAAA==.Mazah:BAABLgAECn8nAAMQAAcJVB02CwA3AgAQAAYJ2SA2CwA3AgAhAAcJDRKvEACrAQABLgAECggJHAADAP0MAA==.Mazlo:BAAALgAECgYJEAAAAA==.',
Mc='Mckrakin:BAAALgADCgEJAQAAAA==.Mclovìns:BAAALgAECgMJAwAAAA==.',
Me='Mechanix:BAAALgAECgMJAwAAAA==.Megafrost:BAAALgAECgEJAQAAAA==.Meibao:BAABLgAECn8kAAIbAAgJRBXIIwDkAQAbAAgJRBXIIwDkAQAAAA==.Meleebrain:BAABLgAECn8gAAIGAAgJghfHEwDMAQAGAAgJghfHEwDMAQAAAA==.Messalina:BAAALgAECgUJBQABLgAECgYJEgAFAAAAAA==.Mex:BAAALgADCgYJCgAAAA==.',
Mi='Miaoyi:BAAALgADCgEJAgAAAA==.Millîe:BAAALgAECgQJBwAAAA==.Mimikay:BAAALgADCgIJAgAAAA==.Missclick:BAAALgAECgQJCAAAAA==.Missoxx:BAAALgAECgMJAwAAAA==.Mistbringer:BAAALgAECgUJDQAAAA==.Mistmaker:BAAALgADCgcJDwABLgAECgcJGQAVABMaAA==.Miwi:BAAALgAECgYJCwAAAA==.',
Mo='Moiest:BAAALgADCgcJBwABLgAECgUJEAAFAAAAAA==.Moiesttuna:BAAALgAECgUJEAAAAA==.Monfalauda:BAAALgADCgEJAgAAAA==.Monkazz:BAAALgADCgYJEAAAAA==.Monkorith:BAACLgAFFH8QAAIbAAUJfhquBwBcAQAbAAUJfhquBwBcAQAuAAQKfyAAAhsACQlaEJckAN0BABsACQlaEJckAN0BAAAA.Moongyal:BAABLgAECn8WAAIZAAgJJhhoEAANAgAZAAgJJhhoEAANAgAAAA==.Mordoboinik:BAAALgAECgEJAQAAAA==.Mortis:BAAALgADCgQJCgAAAA==.Mosaden:BAABLgAECn8UAAISAAYJiB8wDACzAQASAAYJiB8wDACzAQAAAA==.',
Mu='Mudahnk:BAAALgAECgEJAQAAAA==.Mullett:BAAALgAECgcJEwAAAA==.',
My='Mymeii:BAAALgAECgEJAgAAAA==.Mysticheart:BAAALgADCgEJAQAAAA==.Mystogaan:BAAALgAECgUJBQAAAA==.',
['Mï']='Mïra:BAAALgAECgYJDAABLgAECgcJFgAfAC8cAA==.',
Na='Nakiki:BAAALgAECgUJCwAAAA==.Nastyiam:BAABLgAECn8iAAIhAAcJ8BJ3BwCFAQAhAAcJ8BJ3BwCFAQAAAA==.',
Ne='Necromeany:BAAALgADCgQJBwABLgAECgYJHgAIAMojAA==.Nennya:BAAALgAECgYJCwAAAA==.Nerfornothin:BAAALgAECgYJEwAAAA==.Nethflap:BAABLgAECn8eAAMeAAgJdRDwHwDCAQAeAAgJdRDwHwDCAQAdAAcJ7AdmMQDlAAAAAA==.Netsmear:BAAALgAECgYJEQAAAA==.Newdawn:BAAALgAECgIJAgAAAA==.',
Ni='Niftypackage:BAAALgADCgcJDwAAAA==.Nik:BAABLgAECn8mAAMBAAgJrBuaEABfAgABAAgJVRqaEABfAgADAAcJIxSqEACEAQAAAA==.',
No='Noctiss:BAAALgAECgIJAgAAAA==.Nosferato:BAAALgADCgUJBgAAAA==.',
Nu='Nutmilker:BAABLgAECn8rAAIhAAgJvyT/AAC3AgAhAAgJvyT/AAC3AgAAAA==.',
Ny='Nycterine:BAAALgAECgEJAQAAAA==.Nyxnight:BAAALgADCgYJBgAAAA==.',
Oa='Oakenhart:BAAALgAECgIJAgAAAA==.Oathtaker:BAAALgADCgQJBAAAAA==.',
Ob='Obi:BAAALgAECgUJBwAAAA==.',
Ok='Okoye:BAAALgADCgcJBwAAAA==.',
Ol='Olahla:BAAALgADCgYJCwAAAA==.',
Om='Omacron:BAAALgADCggJCAAAAA==.Omroko:BAAALgADCgQJAwAAAA==.',
Op='Ophriala:BAAALgADCgMJAwAAAA==.Optimistic:BAAALgAECgEJAQAAAA==.',
Or='Oriion:BAAALgAECgEJAQAAAA==.Orthae:BAAALgADCgcJEQABLgADCggJEQAFAAAAAA==.',
Pa='Paladio:BAAALgAECgMJAwAAAA==.Pandoosevelt:BAAALgADCgkJDgAAAA==.Panodoc:BAAALgADCgMJAwAAAA==.Parmenion:BAAALgADCgYJBgABLgAECgcJDAAFAAAAAA==.',
Pe='Pelotuda:BAAALgAECgQJBwAAAA==.Penix:BAAALgADCgEJAQAAAA==.Petrovna:BAAALgAECgIJAwAAAA==.',
Pi='Picklerickz:BAAALgADCgYJBgAAAA==.Pikagosa:BAACLgAFFH8LAAMeAAUJlgVEGwDMAAAeAAUJlgVEGwDMAAAiAAIJ8wNMBwCVAAAuAAQKfyoAAx4ACQmOFmgSAFcCAB4ACQlsE2gSAFcCACIABwkKGk0NAAQCAAAA.Pilgor:BAABLgAECn8VAAIeAAgJghFREACMAQAeAAgJghFREACMAQAAAA==.Pils:BAAALgADCgYJBgAAAA==.Pitchief:BAAALgAECgEJAgAAAA==.',
Pl='Plopping:BAAALgADCgMJAwAAAA==.',
Po='Pocky:BAAALgADCgMJAwAAAA==.',
Pr='Priestkidx:BAAALgADCggJCgAAAA==.Primax:BAAALgAECgIJAgAAAA==.',
Pu='Punchballz:BAAALgADCgIJAgAAAA==.Punchkín:BAABLgAECn8UAAQbAAYJCiATHgASAgAbAAYJyR4THgASAgASAAQJShsXPAAsAQAjAAQJFBJWKQC5AAAAAA==.',
['Pæ']='Pæsta:BAABLgAECn8iAAIUAAkJgBfPAgDVAQAUAAkJgBfPAgDVAQAAAA==.',
['Pó']='Póókie:BAAALgAECgEJAQAAAA==.',
Ra='Ragdenar:BAAALgAECgEJAQAAAA==.Ragepounce:BAAALgAECgYJCAAAAA==.Ragingblownr:BAAALgAECgQJBAABLgAECgYJDwAFAAAAAA==.Rangikü:BAAALgAECgQJBAAAAA==.Rast:BAAALgADCgYJBgABLgAECgYJEQAFAAAAAA==.Rastabout:BAAALgAECgcJEwAAAA==.Rathannar:BAABLgAECn8WAAMTAAYJLBQjEwAWAQATAAYJLBQjEwAWAQAGAAMJIQcrwACAAAAAAA==.Ravel:BAABLgAECn8jAAIjAAgJ8R67BACNAgAjAAgJ8R67BACNAgAAAA==.Raxxar:BAEALgADCgcJBwAAAA==.Razah:BAAALgAECgYJEQAAAA==.',
Re='Reahla:BAAALgADCgcJBwAAAA==.Realchad:BAAALgAECgUJBgAAAA==.Redeem:BAAALgAECgEJAQAAAA==.Reios:BAABLgAECn8ZAAIPAAcJdhxEFQD7AQAPAAcJdhxEFQD7AQAAAA==.Remedis:BAAALgADCgYJBgAAAA==.Renara:BAAALgAECgMJAwAAAA==.Resora:BAAALgADCgMJAwAAAA==.',
Rh='Rhaz:BAAALgAECgYJEwAAAA==.Rhoup:BAAALgAECgUJDwABLgAECgYJCwAFAAAAAA==.',
Ri='Richter:BAAALgAECggJCAAAAA==.Rickyspanish:BAAALgAECgcJEwAAAA==.Rifter:BAAALgAECgUJCwAAAA==.',
Ro='Roarke:BAAALgADCgMJAwAAAA==.',
Ru='Rubyouraw:BAAALgAECgYJEQAAAA==.Rubyus:BAAALgADCgcJBwAAAA==.Ruematoid:BAAALgAECgUJCgAAAA==.Ruffneck:BAABLgAECn8bAAILAAcJVBGGJgB/AQALAAcJVBGGJgB/AQAAAA==.Ruine:BAAALgADCgMJAwAAAA==.Rumina:BAAALgAECgIJAwAAAA==.Runiic:BAAALgAECgYJAgAAAA==.Russk:BAAALgADCgUJBQAAAA==.',
Sa='Saelirria:BAAALgADCggJCAABLgAFFAQJBwAMANcMAA==.Sailboat:BAAALgAECgEJAQAAAA==.Sakau:BAAALgAECgYJDQAAAA==.Sakurá:BAAALgAECgYJEgAAAA==.Samo:BAABLgAECn8YAAICAAcJpxwVCAAFAgACAAcJpxwVCAAFAgAAAA==.Sandarr:BAABLgAECn8YAAIfAAYJQBnDFwBZAQAfAAYJQBnDFwBZAQAAAA==.Sanguinne:BAAALgAECgYJEAAAAA==.Saphran:BAAALgAECgEJAQAAAA==.Sargemarge:BAAALgAECgIJAgAAAA==.Sauccy:BAAALgAECgEJAQAAAA==.',
Sc='Scaly:BAABLgAECn8gAAMdAAkJ+g9uDABBAQAdAAkJ+g9uDABBAQAeAAMJOA3mLgCoAAAAAA==.Scrotosaggin:BAAALgAECgUJBQAAAA==.',
Se='Seafoame:BAAALgADCgcJCAABLgAFFAEJAQAFAAAAAA==.See:BAABLgAFFH8JAAIJAAMJYBY4BAD2AAAJAAMJYBY4BAD2AAAAAA==.Selener:BAAALgAECgYJDwAAAA==.Sendisth:BAAALgADCgYJDQABLgAFFAIJBQAhAKIPAA==.Sennia:BAAALgAECgYJBgAAAA==.Serrata:BAAALgAECgEJAwAAAA==.Severus:BAAALgAECgYJBgAAAA==.',
Sh='Shadoryan:BAAALgADCgYJBgABLgAECggJGwAPAEIiAA==.Shaggiê:BAAALgAECgYJBgAAAA==.Shamydavisjr:BAAALgADCgEJAQAAAA==.Shellenne:BAAALgADCgIJAQAAAA==.Shikamáru:BAAALgAECgcJCAAAAA==.',
Si='Silentsnipe:BAAALgADCgQJAwAAAA==.Silther:BAABLgAECn8dAAIHAAgJjB2SDQBXAgAHAAgJjB2SDQBXAgAAAA==.Sinnabun:BAAALgAECgIJAgAAAA==.',
Sl='Slapslap:BAAALgAECgIJAgAAAA==.Slavka:BAAALgADCggJCgAAAA==.Sleepyjoee:BAAALgAECgQJBwABLgAECgYJDwAFAAAAAA==.Sleepypriest:BAAALgADCgIJAgABLgAECgYJDwAFAAAAAA==.Sleepyyjoe:BAAALgAECgQJBQABLgAECgYJDwAFAAAAAA==.Slock:BAAALgAECgEJAQAAAA==.Slothymoon:BAAALgADCgcJBwAAAA==.',
Sm='Smalliam:BAAALgADCgYJDgABLgAECggJIgAhAPASAA==.Smoted:BAAALgADCgUJBQAAAA==.',
Sn='Snaerbear:BAAALgADCgUJCgABLgAECgkJLgAHAOgjAA==.Snikrot:BAAALgADCgMJAwAAAA==.Snâppy:BAABLgAECn8YAAIZAAcJOA1hLAAvAQAZAAcJOA1hLAAvAQAAAA==.',
So='Soloron:BAAALgAECgYJEwAAAA==.Sorceremy:BAAALgAECgcJEwAAAA==.Southvik:BAAALgAECgYJBgABLgAECgcJHgABAEMhAA==.',
Sp='Sparke:BAAALgAECgIJBQAAAA==.Sparrhawk:BAAALgAECgMJAwAAAA==.Spiced:BAABLgAECn8hAAIWAAgJ2yQbBQBOAwAWAAgJ2yQbBQBOAwAAAA==.Spiceweasel:BAAALgAECgEJAQAAAA==.Spiritbound:BAAALgAECgIJAgAAAA==.',
St='Starquake:BAAALgADCgMJAwABLgAECgQJCAAFAAAAAA==.Starskream:BAAALgAECgMJAwAAAA==.Steliokontos:BAAALgAECgcJCAAAAA==.Stickes:BAAALgADCgcJCQAAAA==.Stormclaw:BAAALgAECgUJCQAAAA==.Streea:BAAALgADCgcJCwABLgADCggJEQAFAAAAAA==.Sttriker:BAABLgAECn8gAAITAAgJfwRiMABNAQATAAgJfwRiMABNAQAAAA==.',
Su='Survival:BAAALgAECgMJBgABLgAFFAUJDgAXAKgkAA==.Suzierulz:BAAALgAECgQJBAAAAA==.',
Sw='Sweetcheese:BAAALgAECgEJAQAAAA==.',
Sy='Syn:BAAALgADCgkJCgAAAA==.Synsairis:BAABLgAECn8iAAISAAgJtx0NBwAYAgASAAgJtx0NBwAYAgAAAA==.',
Ta='Talietha:BAAALgADCgUJBQAAAA==.Tallonk:BAAALgADCgEJAQAAAA==.Talonknight:BAABLgAECn8YAAIeAAcJTg8gGAA8AQAeAAcJTg8gGAA8AQAAAA==.Talset:BAABLgAECn8cAAIbAAcJpQw/GQA1AQAbAAcJpQw/GQA1AQAAAA==.Tatarin:BAAALgAECgEJAQAAAA==.Taurrows:BAAALgADCgMJAwAAAA==.',
Tb='Tbill:BAAALgAECgUJCAAAAA==.',
Te='Teaux:BAAALgADCgQJBQAAAA==.Tenson:BAAALgAECgQJBwAAAA==.',
Th='Thad:BAAALgADCgYJBgAAAA==.Thaendofyou:BAAALgAECggJEgAAAA==.Thagda:BAAALgAECgcJDAAAAA==.Theevoker:BAABLgAECn8eAAMdAAgJOg/zBwCvAQAdAAgJOg/zBwCvAQAiAAEJ1AHLRQAeAAAAAA==.Theproject:BAAALgAECgcJBgAAAA==.Thestarman:BAAALgADCgUJBQAAAA==.Thizzordie:BAAALgAECgEJAQAAAA==.Tholnar:BAAALgAECgUJDgAAAA==.Thoroughbred:BAAALgAECgUJBQAAAA==.Throwdini:BAABLgAECn8iAAILAAgJqx+FEAC2AgALAAgJqx+FEAC2AgAAAA==.',
Ti='Tigerboy:BAAALgAECgYJCAAAAA==.Tikva:BAAALgAECgEJAQABLgAECggJHAADAP0MAA==.Timotthy:BAAALgAECgYJCgAAAA==.Titant:BAAALgADCgEJAQAAAA==.Titanta:BAAALgAECgQJCQAAAA==.',
Tm='Tmate:BAAALgAECgYJCgAAAA==.',
To='Totempics:BAAALgADCgUJBQABLgAECggJIQAZAAAgAA==.Touchmé:BAAALgAECgMJAwAAAA==.',
Ts='Tsunaris:BAABLgAECn8dAAIMAAgJDhttAgArAgAMAAgJDhttAgArAgAAAA==.',
Tu='Tulanis:BAABLgAECn8rAAIMAAgJ2R5PAQCBAgAMAAgJ2R5PAQCBAgAAAA==.Turbotax:BAAALgAECgQJBAAAAA==.',
Ty='Tyriem:BAABLgAECn8dAAILAAgJiBh9FgDeAQALAAgJiBh9FgDeAQAAAA==.Tyssanton:BAABLgAECn8cAAQdAAcJuQIyFAC5AAAdAAYJ+AIyFAC5AAAiAAUJZQI6DQCAAAAeAAEJgQEDTwAiAAAAAA==.',
Tz='Tziganin:BAABLgAECn8bAAIhAAcJ4RcQBwCQAQAhAAcJ4RcQBwCQAQAAAA==.',
Ug='Uggork:BAAALgAECgYJCAAAAA==.',
Um='Umi:BAAALgAECgEJAQAAAA==.',
Un='Unholybussy:BAABLgAECn8jAAIXAAgJvhpHFwAAAgAXAAgJvhpHFwAAAgAAAA==.Unicorns:BAAALgAECgEJAQAAAA==.',
Ur='Urvazlite:BAABLgAECn8YAAIIAAcJcgo8HABPAQAIAAcJcgo8HABPAQAAAA==.',
Ut='Utaadh:BAABLgAECn8UAAITAAYJ2BpTHADeAQATAAYJ2BpTHADeAQAAAA==.',
Va='Vallerin:BAABLgAECn8YAAIhAAYJChTPCQBKAQAhAAYJChTPCQBKAQAAAA==.Vanestor:BAAALgADCgkJCQABLgAFFAMJCwALAJUVAA==.Varahk:BAAALgADCgMJAwAAAA==.Varus:BAAALgADCggJFAAAAA==.',
Ve='Velaar:BAABLgAECn8pAAIXAAgJBiW2AwD1AgAXAAgJBiW2AwD1AgABLgAECgYJEgAFAAAAAA==.Velamuna:BAAALgADCgQJBAAAAA==.Velindraela:BAAALgADCgMJAgABLgAECggJIQAZAAAgAA==.Verras:BAAALgADCgIJAgAAAA==.',
Vi='Vikthyr:BAAALgADCgYJBgABLgAECgcJHgABAEMhAA==.Villain:BAAALgADCgYJBgABLgAECggJKQALAFwjAA==.',
Vo='Vodnar:BAACLgAFFH8LAAMLAAMJlRUrDQD3AAALAAMJlRUrDQD3AAAMAAEJegAALgA1AAAuAAQKfyIAAwsACQlrG1gZAHACAAsACAnwHlgZAHACAAwABglhCE1HADYBAAAA.Vohnkhar:BAAALgADCgEJAQAAAA==.Voidatfear:BAAALgAECgUJCgAAAA==.Voidhunter:BAAALgADCgcJBwAAAA==.Voodoodoo:BAAALgAECgYJDwAAAA==.Voxramus:BAAALgADCgQJBAABLgAECgMJBwAFAAAAAA==.',
Vu='Vulcos:BAAALgAECgYJBwAAAA==.',
Vy='Vyreth:BAAALgAECgIJBAAAAA==.',
Wa='Walls:BAABLgAECn8ZAAIHAAYJCxZ2OwBYAQAHAAYJCxZ2OwBYAQAAAA==.Wasil:BAAALgADCgYJBgAAAA==.Waste:BAAALgAECggJEAAAAA==.Waylander:BAAALgADCgMJAwABLgAECgcJDAAFAAAAAA==.',
We='Werragan:BAAALgADCgcJBwAAAA==.',
Wh='Whipps:BAAALgAECgYJBgAAAA==.',
Wi='Wilt:BAAALgADCggJFAAAAA==.',
Wo='Wompazuzu:BAAALgAECgYJEAAAAA==.',
Wr='Wraithewyn:BAAALgADCgUJBwAAAA==.Wrékt:BAAALgADCgMJAwAAAA==.',
Xa='Xanosina:BAAALgAECgQJBAAAAA==.',
Yi='Yilongma:BAAALgAECgIJAwAAAA==.',
Yl='Ylaran:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAECgYJEAAAAA==.',
Yo='Yogí:BAABLgAECn8fAAIhAAgJEBdhBADqAQAhAAgJEBdhBADqAQAAAA==.Yokos:BAAALgAECgUJBwAAAA==.Yonokojo:BAAALgAECgQJBAAAAA==.Yornic:BAAALgAECgEJAwABLgAECgYJDgAFAAAAAA==.',
Za='Zacksquach:BAAALgADCgMJAwAAAA==.Zahneel:BAABLgAECn8dAAIZAAgJURl/EgD2AQAZAAgJURl/EgD2AQAAAA==.Zalanar:BAAALgADCgkJDAAAAA==.Zaney:BAAALgAECgYJEQAAAA==.Zaps:BAAALgAECgEJAQAAAA==.Zaratul:BAACLgAFFH8IAAIHAAQJYRdUHgC0AAAHAAQJYRdUHgC0AAAuAAQKfy0AAgcACQlDIQwIAFQDAAcACQlDIQwIAFQDAAAA.Zaroth:BAACLgAFFH8JAAIBAAMJ7SG2BgAxAQABAAMJ7SG2BgAxAQAuAAQKfxwAAgEACAm6FNEnALEBAAEACAm6FNEnALEBAAAA.',
Ze='Zeleste:BAAALgAECgYJCwAAAA==.Zelnorac:BAAALgAECgQJCwAAAA==.Zenma:BAAALgAECgMJAwAAAA==.Zerovii:BAACLgAFFH8FAAIhAAIJog9aBAClAAAhAAIJog9aBAClAAAuAAQKfx0AAiEACAndHSYEAOACACEACAndHSYEAOACAAAA.Zetsubou:BAAALgAECgMJAwAAAA==.',
Zh='Zharrak:BAAALgAECgUJCAAAAA==.',
Zi='Zilyana:BAAALgAECgQJBAAAAA==.',
Zu='Zubuûuûuûuûu:BAAALgADCgYJCgAAAA==.',
Zy='Zyrian:BAAALgAECgIJAgAAAA==.',
['Zä']='Zärthan:BAAALgADCgIJAgAAAA==.',
['Éd']='Édz:BAAALgAECgQJCgAAAA==.',
['Ía']='Íamjakehill:BAAALgAECgMJBgAAAA==.',
['Îr']='Îris:BAAALgADCgcJEAAAAA==.',
['Ño']='Ñovember:BAAALgAFFAEJAQAAAA==.',
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

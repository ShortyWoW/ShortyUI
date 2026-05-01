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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Paladin-Retribution','Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Warlock-Destruction','Paladin-Protection','Priest-Holy','Priest-Discipline','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Mage-Fire','Monk-Windwalker','Evoker-Devastation','Hunter-BeastMastery','Priest-Shadow','Druid-Balance','Druid-Feral','Paladin-Holy','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Druid-Guardian','DeathKnight-Frost','Monk-Mistweaver','Rogue-Assassination','Shaman-Enhancement',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abor:BAAALgAECgYJEgAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAAALgAFFAIJAgAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDAAAAA==.Aethelbane:BAAALgADCgUJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Aginah:BAAALgADCgYJBgABLgAECgUJBgABAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAAALgAECgMJBwAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAAALgAECgUJDQAAAA==.',
Al='Alariel:BAABLgAECn8WAAICAAcJwxqeIgBkAQACAAcJwxqeIgBkAQABLgAFFAMJBQADALEWAA==.Albesuri:BAAALgAECgUJBQABLgAFFAYJDAACAMYZAA==.Alcazar:BAAALgAECgUJDAAAAA==.Alcmeneinen:BAABLgAECn8YAAIEAAgJGwj2HwB+AQAEAAgJGwj2HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwAAAA==.Alliar:BAABLgAECn8aAAIFAAgJ7Rt5EQDnAQAFAAgJ7Rt5EQDnAQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwABAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJBwAAAA==.',
Am='Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAABLgAECn8ZAAIGAAcJNB4gLACRAQAGAAcJNB4gLACRAQAAAA==.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAAALgAECgQJCgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAAALgAECgQJCQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJCwAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8LAAIHAAMJHyCmKgAhAQAHAAMJHyCmKgAhAQAuAAQKfyQAAgcACAkUIuwlANsCAAcACAkUIuwlANsCAAAA.',
At='Atlasdark:BAAALgAECgYJBwABLgABCgEJAQABAAAAAA==.Atlasstout:BAAALgAECggJEgABLgABCgEJAQABAAAAAA==.Atrell:BAAALgAECggJEwAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgADCgcJCAABLgAFFAMJBwAIAEEcAA==.',
Ba='Balrock:BAAALgADCgQJBAAAAA==.Balthromaw:BAABLgAECn8lAAIJAAYJnRunKgCDAQAJAAYJnRunKgCDAQAAAA==.Bangar:BAAALgAECgYJCgAAAA==.Barron:BAABLgAECn8aAAIKAAYJGCLyDQAtAgAKAAYJGCLyDQAtAgAAAA==.Bartahh:BAAALgAECgYJDQAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgMJAwABLgAECggJHwALAHgbAA==.Beardwaffle:BAABLgAECn8fAAILAAgJeBsjHwBXAgALAAgJeBsjHwBXAgAAAA==.Bearlysota:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.Beatstick:BAAALgADCgkJFAAAAA==.Belfdelphine:BAAALgAECgQJDgAAAA==.',
Bi='Bifurthegrey:BAAALgAECgQJBwAAAA==.Bigbubba:BAABLgAFFH8GAAIHAAMJVwSGQAC/AAAHAAMJVwSGQAC/AAAAAA==.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8FAAMLAAIJ7Rw+FgC+AAALAAIJ7Rw+FgC+AAAMAAEJcwObEwBEAAAuAAQKfyYABAsACAnxIzIUAKwCAAsACAk5ITIUAKwCAA0AAwmPJPoNAD8BAAwABAk0Fj4bABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgEJAQABLgAECgYJFwAEABgRAA==.Blaxdevoured:BAAALgAECgcJEwAAAA==.Blinkss:BAAALgADCggJCAAAAA==.Bloodhoundss:BAABLgAECn8dAAILAAcJqxSWFgB+AQALAAcJqxSWFgB+AQAAAA==.Blössöm:BAABLgAECn8YAAIOAAgJ8RJzBACsAQAOAAgJ8RJzBACsAQAAAA==.',
Bo='Bob:BAACLgAFFH8OAAICAAYJcxByCQCTAQACAAYJcxByCQCTAQAuAAQKfyAAAgIACQkfId8IAEIDAAIACQkfId8IAEIDAAAA.Bofft:BAABLgAECn8aAAIFAAgJ8RUuEgDfAQAFAAgJ8RUuEgDfAQAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAECgcJDwAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAECgIJAgAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAAALgAECgcJEAAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAAALgAFFAIJBAAAAA==.',
Bu='Buldur:BAAALgADCgIJAwAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgADCgEJAgAAAA==.Caliginosity:BAABLgAECn8YAAIPAAcJeRc1DAD/AQAPAAcJeRc1DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.Cesard:BAAALgAECgYJEAAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgEJAgAAAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8eAAILAAgJ8RwLCAArAgALAAgJ8RwLCAArAgAAAA==.Chrondeezee:BAAALgAECgEJBQAAAA==.',
Ci='Ciradyl:BAAALgADCgkJCgAAAA==.Circledebull:BAAALgADCgIJAgAAAA==.',
Cl='Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgEJAwABLgAECgEJAwABAAAAAA==.Coeurdeleon:BAABLgAECn8ZAAIQAAgJ8RtNCABVAgAQAAgJ8RtNCABVAgAAAA==.Condemnation:BAABLgAECn8oAAMRAAkJXhfADADXAQARAAgJ4BbADADXAQASAAcJbg1BDgCmAQAAAA==.Congressmen:BAAALgAECgQJBAAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJBQABLgAECgMJAwABAAAAAA==.Corebin:BAAALgADCgcJEgABLgAECgMJAwABAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAAALgAECgcJDwAAAA==.',
Cr='Crayak:BAABLgAECn8iAAMTAAgJkiHOAQC0AgATAAgJkiHOAQC0AgACAAYJbxNjfgAuAQAAAA==.Crossbones:BAAALgAECgcJDwAAAA==.',
Cu='Cudà:BAACLgAFFH8DAAICAAMJQBAnKQCfAAACAAMJQBAnKQCfAAAuAAQKfxMAAgIACAltGqIyAC8CAAIACAltGqIyAC8CAAAA.Curbside:BAABLgAECn8XAAIUAAYJfxIxJAAAAQAUAAYJfxIxJAAAAQAAAA==.Curbstomped:BAAALgADCgYJCgAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAABLgAECn8cAAMVAAgJ3yDVIAC+AgAVAAgJPiDVIAC+AgAWAAcJFhpzEwDWAQAAAA==.Davinator:BAABLgAECn8hAAQNAAgJfh+vBgDfAQALAAcJSB2WHQBhAgANAAUJFiGvBgDfAQAMAAIJ7hafKwCXAAAAAA==.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDQAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJAwAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAJAO0TAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8IAAIHAAMJcA1dOgDqAAAHAAMJcA1dOgDqAAAuAAQKfyMAAgcACAn9GKIkANUBAAcACAn9GKIkANUBAAAA.Deselle:BAAALgAECgYJDQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJAgAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8XAAIKAAYJiRICKABIAQAKAAYJiRICKABIAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn8kAAIQAAgJgBsRAwA/AgAQAAgJgBsRAwA/AgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgADCgUJBQAAAA==.Donatelloh:BAAALgAECgYJDgAAAA==.Dortbraz:BAAALgAECgYJCAAAAA==.Dotmeharder:BAABLgAECn8bAAMJAAcJ7ROaegBnAQAJAAcJ7ROaegBnAQAXAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Drakelayer:BAAALgAFFAIJAgAAAA==.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAAALgAECgcJDwAAAA==.Draxyl:BAABLgAECn8kAAIVAAcJrRZ1VgDuAQAVAAcJrRZ1VgDuAQAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8gAAMCAAgJkREwIwBhAQACAAgJkREwIwBhAQAOAAUJpAtgDQC8AAAAAA==.Drogbar:BAAALgAECgcJEAAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8jAAMJAAgJNQrpLgBwAQAJAAgJMwrpLgBwAQAPAAMJNAYkUQB7AAAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn8VAAIVAAYJbiMjJQCsAQAVAAYJbiMjJQCsAQAAAA==.Duo:BAABLgAECn8ZAAMYAAgJKAw6BwASAQAYAAUJIBE6BwASAQAHAAcJewUlpgB3AAABLgAECgYJEgABAAAAAA==.',
Eb='Ebontoes:BAABLgAECn8hAAMIAAgJYCFqBABuAgAIAAgJYCFqBABuAgAZAAIJ0gV7bgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAAALgAECgYJEQAAAA==.',
Ei='Einjhell:BAAALgAECgYJDAAAAA==.',
El='Eladra:BAAALgAECgUJBgAAAA==.Eleidon:BAAALgAECgYJCQAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elody:BAAALgAECgYJCAAAAA==.Elowynn:BAABLgAECn8nAAMRAAkJaAw8GQA/AQARAAkJqQs8GQA/AQASAAUJvgi4IQDGAAAAAA==.Elèctra:BAAALgAECgcJEwAAAA==.',
En='Enyô:BAAALgAECgYJEwAAAA==.',
Eo='Eorae:BAAALgAECgEJAgAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAAALgAECgEJAgAAAA==.',
Es='Esoss:BAAALgAECgMJAwAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAYJDAACAMYZAA==.',
Ex='Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCAAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgMJBgABLgAECgYJEgABAAAAAA==.',
Fa='Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAAALgAECgcJEwABLgAECgcJHAAaAP8kAA==.',
Fh='Fhalanx:BAAALgAECgQJBwAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECgYJEAABAAAAAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgYJEgABAAAAAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECgYJCwABAAAAAA==.Flapp:BAAALgAECgYJCwAAAA==.Flarios:BAAALgAECgEJAQAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQAAAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8iAAIbAAgJ/hF3GQDIAQAbAAgJ/hF3GQDIAQAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJDQAAAA==.Frozenwings:BAAALgAECgUJBQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgMJBgABLgAECgIJEQABAAAAAA==.',
Ga='Garrosh:BAAALgADCgcJBQAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAAALgAECgYJDgAAAA==.Geraldene:BAABLgAECn8UAAIRAAgJNgpQFQBlAQARAAgJNgpQFQBlAQAAAA==.Geraniho:BAAALgADCgUJBQAAAA==.',
Gh='Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Gishwrath:BAAALgAECgEJAQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgEJAQAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn8hAAICAAkJrxVxDwD3AQACAAkJrxVxDwD3AQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgIJAgABLgAECgYJEgABAAAAAA==.Grimthruul:BAAALgAECgEJAQAAAA==.Grommkar:BAAALgAECgYJDAAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gunnulf:BAAALgAECgYJDgAAAA==.',
Ha='Halucination:BAABLgAECn8ZAAMRAAcJlBPvKQCjAQARAAYJTxbvKQCjAQAcAAYJmw0ZIAD6AAAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwABAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJAwAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgADCgUJBgAAAA==.',
He='Hetzák:BAABLgAECn8jAAIdAAgJyRDSEgBzAQAdAAgJyRDSEgBzAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAABLgAECn8jAAIeAAgJaByzAgA6AgAeAAgJaByzAgA6AgAAAA==.Hiphopuler:BAABLgAECn8nAAIRAAcJrxycGwAAAgARAAcJrxycGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8XAAMGAAgJuxygHwCuAgAGAAgJuxygHwCuAgAQAAQJUxilIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgADCgcJBwAAAA==.Holyschmit:BAABLgAECn8XAAIfAAcJrRpPDwDsAQAfAAcJrRpPDwDsAQAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8jAAINAAgJNRESCgCKAQANAAgJNRESCgCKAQAAAA==.Hucklebarry:BAABLgAECn8WAAIgAAgJNRjnAgANAgAgAAgJNRjnAgANAgAAAA==.Huntris:BAAALgAECgYJEQAAAA==.Hurdur:BAAALgAECgcJDAAAAA==.',
Hy='Hyala:BAAALgADCgUJBQAAAA==.Hypnotykk:BAAALgAECgUJDwAAAA==.',
Ia='Iadygaga:BAAALgAECgEJAQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgEJAQAAAA==.Imrah:BAABLgAECn8VAAMZAAYJog/wNwA+AQAZAAYJog/wNwA+AQAIAAMJ0gZmNgCCAAAAAA==.',
In='Innuendowo:BAAALgAECgcJBwAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgADCgcJDgAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAABLgAECn8iAAIRAAgJ8RfoBgBGAgARAAgJ8RfoBgBGAgAAAA==.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAABLgAECn8ZAAIhAAcJWRN0LACbAQAhAAcJWRN0LACbAQAAAA==.Jocon:BAABLgAECn8aAAIJAAgJRgSvRgAcAQAJAAgJRgSvRgAcAQAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJBQABLgAFFAMJBgAiACIMAA==.Kanami:BAABLgAECn8XAAILAAYJkRnCFgB9AQALAAYJkRnCFgB9AQAAAA==.Kaori:BAAALgAECgYJEQAAAA==.Karamazov:BAABLgAECn8aAAIjAAgJuxo+BADnAQAjAAgJuxo+BADnAQAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJDQAAAA==.Kaynyx:BAABLgAECn8jAAIhAAgJ1BrdBAA6AgAhAAgJ1BrdBAA6AgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAABLgAECn8jAAMGAAgJLhf3SgACAgAGAAgJLhf3SgACAgAQAAEJuwuPRgAnAAAAAA==.Keedron:BAACLgAFFH8MAAICAAYJxhkwEwA4AQACAAYJxhkwEwA4AQAuAAQKfxoAAgIACAlJJI4LACUDAAIACAlJJI4LACUDAAAA.Keiden:BAABLgAECn8fAAIVAAgJlRNxIgC5AQAVAAgJlRNxIgC5AQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8XAAMVAAYJyR5pJQCqAQAVAAYJyR5pJQCqAQAkAAEJPAVgGQApAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kilfogg:BAABLgAECn8UAAIUAAcJqBbmKwC5AQAUAAcJqBbmKwC5AQAAAA==.Killinflak:BAAALgAECgUJBgAAAA==.Kimosabi:BAAALgAECgcJCAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECggJDwAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAABLgAECn8kAAQEAAgJlxrhBQD0AQAEAAgJlxrhBQD0AQADAAUJIA0OLQCzAAAaAAEJkQW6QAAvAAABLgAECgcJGQAGADQeAA==.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Konjur:BAACLgAFFH8SAAIHAAUJLST0BgDwAQAHAAUJLST0BgDwAQAuAAQKfxcAAgcACAm6IwcVACoDAAcACAm6IwcVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwABAAAAAA==.Kotonano:BAABLgAECn8UAAIdAAgJHx5dJgDKAQAdAAgJHx5dJgDKAQABLgAECggJGwAGAI0hAA==.',
Kr='Krelock:BAABLgAECn8WAAIJAAcJYBRRUgDQAQAJAAcJYBRRUgDQAQAAAA==.Krymzendeath:BAAALgADCgkJHAABLgAECggJJQANAIUaAA==.Krísztina:BAAALgAECgYJEgAAAA==.',
Ku='Kuenybby:BAAALgADCgEJAQABLgAFFAYJDAACAMYZAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwABAAAAAA==.Kuya:BAAALgAECgUJDQAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8GAAIiAAMJIgxYCgD9AAAiAAMJIgxYCgD9AAAuAAQKfyEAAiIACAnuGv0HAG0CACIACAnuGv0HAG0CAAAA.',
La='Lakey:BAAALgAECgUJDAABLgAFFAMJCAAKADwYAA==.Lakeyy:BAACLgAFFH8IAAIKAAMJPBizFgDgAAAKAAMJPBizFgDgAAAuAAQKfyEAAwoACAmlIhMLAOkCAAoACAmlIhMLAOkCAB0ABQnwGGQ9AD0BAAAA.Lanayrd:BAAALgAECgEJAQAAAA==.Lawrence:BAACLgAFFH8HAAMFAAMJkgn0GgC7AAAFAAMJkgn0GgC7AAAUAAIJQwygGgCYAAAuAAQKfx0AAxQACAkKIb0KAOoCABQACAkKIb0KAOoCAAUAAgndBOSaADcAAAAA.',
Le='Lebonk:BAAALgAECgEJAQAAAA==.Lexía:BAAALgAECgQJBAAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8TAAQVAAUJJxluGABDAQAVAAQJXhhuGABDAQAkAAQJqgZgAgAPAQAWAAEJAAAOGgA0AAAuAAQKfysAAyQACQnFIcUAAH8CABUACQkAIfMWAPICACQABwmWHMUAAH8CAAAA.',
Lo='Locklear:BAABLgAECn8ZAAIGAAgJLxUeKQCeAQAGAAgJLxUeKQCeAQAAAA==.Logic:BAACLgAFFH8VAAIHAAYJ8haGBgDMAQAHAAYJ8haGBgDMAQAuAAQKfyEAAgcACQmmIQ4WACUDAAcACQmmIQ4WACUDAAAA.Lolshield:BAAALgAECgYJBgAAAA==.Lorecan:BAABLgAECn8VAAIQAAYJhwosJADnAAAQAAYJhwosJADnAAAAAA==.Lotei:BAAALgADCgUJBQAAAA==.',
Lu='Luchenta:BAAALgAECgYJCwAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJBgABLgAFFAMJCAAKADwYAA==.Luubitotems:BAAALgAECgcJCQAAAA==.',
Ly='Lyterbox:BAABLgAECn8XAAQdAAgJ2Qh5OABWAQAdAAgJ2Qh5OABWAQAeAAYJJAW3HwDjAAAjAAMJ6ARHKgBRAAABLgAFFAIJBgAVAHcPAA==.',
Ma='Maani:BAAALgADCgMJBQAAAA==.Macediin:BAABLgAECn8iAAIVAAkJEBuNEQAuAgAVAAkJEBuNEQAuAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8PAAICAAYJJRF8BADpAQACAAYJJRF8BADpAQAuAAQKfycAAgIACQnaIeQDALMCAAIACQnaIeQDALMCAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJDwACACURAA==.Magegummy:BAAALgAECgcJCAAAAA==.Magesterique:BAABLgAECn8hAAIHAAgJhxWrNQCPAQAHAAgJhxWrNQCPAQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAABLgAECn8hAAIGAAgJtB07DgBQAgAGAAgJtB07DgBQAgAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn8eAAIVAAkJSRsyCQCMAgAVAAkJSRsyCQCMAgAAAA==.Mamageek:BAABLgAECn8VAAIFAAgJnhPmKADsAQAFAAgJnhPmKADsAQAAAA==.Mami:BAAALgAECgUJCwABLgAECggJCAABAAAAAA==.Marksterique:BAAALgADCggJEgABLgAECggJIQAHAIcVAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAABLgAECn8YAAIlAAcJVxdKIACxAQAlAAcJVxdKIACxAQAAAA==.Maxson:BAAALgAECgYJEgAAAA==.',
Mc='Mcversatile:BAABLgAECn8VAAIjAAYJuxc2DwCIAQAjAAYJuxc2DwCIAQAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIRAAkJrBksEABkAgARAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8NAAIEAAYJBRkxBAC8AQAEAAYJBRkxBAC8AQAuAAQKfx4AAgQACAk1JKkAAE0DAAQACAk1JKkAAE0DAAAA.Mereoleona:BAAALgAECgIJAgAAAA==.Metalmagus:BAABLgAECn8YAAIHAAgJCRikGAAYAgAHAAgJCRikGAAYAgAAAA==.Metori:BAAALgADCgEJAQAAAA==.',
Mi='Millican:BAAALgAECggJEgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAYJDAACAMYZAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8eAAIIAAgJoROrEACLAQAIAAgJoROrEACLAQAAAA==.Misslobster:BAAALgAECgQJBwAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECgcJEwABAAAAAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8FAAMDAAMJsRZZEAD/AAADAAMJsRZZEAD/AAAaAAEJVQsUCgBTAAAuAAQKfygAAwMACQkCHtAFACcDAAMACQnoHdAFACcDABoABwlFHWELACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAMJBQADALEWAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8hAAMdAAgJrBtIBwAkAgAdAAgJrBtIBwAkAgAKAAQJDxFaggDUAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8lAAIZAAgJCSP0AwB2AgAZAAgJCSP0AwB2AgAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
['Mò']='Mòrtale:BAAALgADCgMJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAMJBwAIAEEcAA==.Nahmo:BAAALgAECgUJEAAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgEJAQABAAAAAA==.Nametaken:BAAALgAECgEJAQAAAA==.',
Ne='Necro:BAABLgAECn8ZAAIVAAcJWBoLRwAfAgAVAAcJWBoLRwAfAgAAAA==.Necrota:BAAALgAFFAIJAwABLgAFFAUJEgAHAC0kAA==.Neuron:BAACLgAFFH8SAAIKAAUJ6CKsAQD6AQAKAAUJ6CKsAQD6AQAuAAQKfxoAAwoACAmAI/0OAMECAAoABwnlJP0OAMECAB0AAQkAG31zAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJBAAAAA==.Nigdruu:BAABLgAECn8cAAIKAAgJexskHABbAgAKAAgJexskHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8VAAImAAcJFAkfBwA3AQAmAAcJFAkfBwA3AQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.',
Or='Oralys:BAABLgAECn8YAAIfAAgJwCEjAwDZAgAfAAgJwCEjAwDZAgAAAA==.Oromis:BAAALgAECgcJDwAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDAAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladian:BAAALgAECgEJAQABLgAECgcJEwABAAAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAAALgAECgYJEgAAAA==.Palugly:BAAALgADCgIJAgABLgAECgkJLQAOAB0cAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Patoko:BAABLgAECn8iAAInAAgJpBrECgAhAgAnAAgJpBrECgAhAgAAAA==.Paxwet:BAAALgADCgcJFQAAAA==.Payn:BAABLgAECn8cAAMaAAcJ/yTcAQAcAgAaAAYJbyXcAQAcAgADAAIJDR4ESgCsAAAAAA==.Paypay:BAABLgAECn8jAAIKAAkJXCACAgBAAwAKAAkJXCACAgBAAwAAAA==.',
Ph='Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgIJAgAAAA==.',
Pi='Piglittle:BAABLgAECn8ZAAMRAAYJTBmbGQA8AQARAAYJTBmbGQA8AQAcAAQJ9xnUOAAoAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgADCgQJBAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJBAAAAA==.Porthub:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAABLgAECn8YAAISAAYJlB+/EwAQAgASAAYJlB+/EwAQAgAAAA==.Prrowl:BAAALgAECgMJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rakashi:BAAALgADCgcJBwAAAA==.Ralon:BAAALgADCgUJBQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAECggJIQAGALQdAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAAALgAECgYJDwAAAA==.Rollos:BAAALgAECgcJEgAAAA==.Ronara:BAAALgAECgcJDwAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8WAAIDAAYJjyQbAwD9AQADAAYJjyQbAwD9AQAuAAQKfyAAAgMACQm3JfIAAMwDAAMACQm3JfIAAMwDAAAA.',
['Rä']='Rävylock:BAAALgAECgkJDwAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgYJEgABAAAAAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgUJDQABAAAAAA==.Saintnick:BAAALgADCgUJBQAAAA==.Samtarkras:BAABLgAECn8gAAIEAAgJFRV/BwC8AQAEAAgJFRV/BwC8AQAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgADCgcJBwAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgEJAQAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAABLgAECn8dAAMXAAcJGRcRCwCKAQAXAAYJGRIRCwCKAQAJAAYJihaLNwBOAQABLgAECggJDgABAAAAAA==.Selket:BAAALgAECgUJBwAAAA==.',
Sh='Shadowfawn:BAABLgAECn8UAAMcAAYJ0BCCGAA6AQAcAAYJ0BCCGAA6AQARAAEJsALiiQAjAAAAAA==.Shadowzugger:BAAALgAECgUJBQABLgAFFAQJDwAUAFQXAA==.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamxie:BAAALgAECgEJAQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Sharklord:BAABLgAECn8cAAIhAAgJwBfREgBKAQAhAAgJwBfREgBKAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAAALgAFFAMJAwAAAA==.Shinryujin:BAAALgADCgcJCwABLgAFFAYJFgADAI8kAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAQAAAA==.',
Sl='Slyde:BAABLgAECn8VAAIVAAgJ9x5zHwDKAQAVAAgJ9x5zHwDKAQAAAA==.',
Sm='Smalldk:BAACLgAFFH8RAAIVAAUJLRcwFwBIAQAVAAUJLRcwFwBIAQAuAAQKfyUAAhUACAnOIq0VAPoCABUACAnOIq0VAPoCAAAA.Smick:BAABLgAECn8VAAIfAAYJyRCpSABVAQAfAAYJyRCpSABVAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgQJCAAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgEJAgAAAA==.Sota:BAAALgAECgMJAwAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn8kAAILAAgJ/hlKCAAmAgALAAgJ/hlKCAAmAgAAAA==.Soulfox:BAAALgAECgEJAgABLgAECgcJEwABAAAAAA==.',
Sp='Spacing:BAAALgAECgYJBgAAAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAAALgAECggJDgAAAA==.Starfu:BAAALgADCggJGAAAAA==.Stealthops:BAAALgAECgQJBgAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8QAAIZAAUJCR0ZAgCeAQAZAAUJCR0ZAgCeAQAuAAQKfxUAAhkACAlEH5MMALECABkACAlEH5MMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCAAAAA==.Straydog:BAAALgAECgkJDwAAAA==.Strongsad:BAAALgAECgYJDQAAAA==.Stumptavion:BAABLgAECn8nAAIVAAYJoxyWYwDJAQAVAAYJoxyWYwDJAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgABAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgABAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Superpowers:BAAALgAECgUJDgAAAA==.Supersaiyan:BAAALgAECgUJBgAAAA==.Surtur:BAABLgAECn8rAAIMAAgJKR57BACmAgAMAAgJKR57BACmAgAAAA==.Sus:BAAALgAECgcJCgAAAA==.Suzel:BAAALgAECgQJCwAAAA==.',
Sw='Swoof:BAAALgAECggJEAABLgAFFAIJBgAVAHcPAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn8UAAITAAcJOg0tDwBIAQATAAcJOg0tDwBIAQAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAMJCAASAMgRAA==.Synwise:BAABLgAECn8hAAIKAAgJLCBbBADlAgAKAAgJLCBbBADlAgAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ta='Tagbone:BAABLgAECn8jAAMbAAgJLRxxDwAcAgAbAAgJLRxxDwAcAgAgAAEJIgJLmgAZAAAAAA==.Taotien:BAABLgAECn8bAAIZAAgJCRkMDAC2AQAZAAgJCRkMDAC2AQAAAA==.Taowg:BAAALgADCgYJCQAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8XAAQRAAgJUBoECgAIAgARAAgJUBoECgAIAgASAAIJvwW0TQBbAAAcAAEJ/g2+PgA7AAAAAA==.',
Th='Thanah:BAAALgADCggJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAABLgAECn8lAAIVAAgJ8hVISwARAgAVAAgJ8hVISwARAgAAAA==.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwABAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJAwAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAABLgAECn8tAAIOAAkJHRw3AQB5AgAOAAkJHRw3AQB5AgAAAA==.Tinytea:BAABLgAECn8tAAIIAAkJJSEMAQAJAwAIAAkJJSEMAQAJAwAAAA==.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJCQAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8FAAMfAAMJcx5dDQAkAQAfAAMJcx5dDQAkAQAGAAEJVA2PRQBMAAAuAAQKfyQAAx8ACAknH4sHAGUCAB8ACAknH4sHAGUCAAYAAgn2GOWKAJUAAAAA.Tototree:BAAALgAECgMJAwAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMLAAYJ0SGHLQD9AQALAAUJvSOHLQD9AQAMAAEJIxoDPgA8AAABLgAFFAMJBwAVAIYTAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsunt:BAAALgAECgYJDQAAAA==.Tsusha:BAAALgADCgkJEAABLgAECgYJDQABAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQAAAA==.Turkeyleg:BAAALgADCgYJBwAAAA==.',
Tw='Twiisty:BAAALgAECgYJCwAAAA==.Twippy:BAAALgADCgYJBgABLgAECgYJCwABAAAAAA==.',
Ty='Tyanis:BAAALgAECgQJBQABLgAECgQJBwABAAAAAA==.Tyriam:BAABLgAECn8jAAMfAAgJ8xa1EwC5AQAfAAgJ8xa1EwC5AQAGAAYJNRwjJwCnAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8YAAIHAAcJQRSqogCSAQAHAAcJQRSqogCSAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Vandy:BAABLgAECn8gAAMCAAgJjAoKQQDjAAATAAYJtwvSNwAmAQACAAgJowkKQQDjAAAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8FAAIaAAIJhBP/AwCTAAAaAAIJhBP/AwCTAAAuAAQKfx4AAhoACAlhIEYEAMkCABoACAlhIEYEAMkCAAAA.',
Vi='Vikdruid:BAAALgAECgUJAwABLgAECggJEgABAAAAAA==.Vikindia:BAAALgAECgUJBQABLgAECggJEgABAAAAAA==.Vinushka:BAAALgAECgIJAgAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgYJFAADAKYbAA==.Vitalithry:BAABLgAECn8UAAMDAAYJphuIEwBnAQADAAYJmRuIEwBnAQAaAAEJSh+xOABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.',
Vy='Vyndication:BAAALgAECgMJAwAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAQABLgAECggJIQAGALQdAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Wetpax:BAABLgAECn8aAAIVAAcJFhKzOgBQAQAVAAcJFhKzOgBQAQAAAA==.',
Wh='Whiskeybeer:BAABLgAECn8VAAMFAAcJAhioEQDlAQAFAAcJAhioEQDlAQAUAAYJGh7VEQCRAQAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8FAAIcAAQJCA+8BwBEAQAcAAQJCA+8BwBEAQAuAAQKfyYAAxwACAntHCwOAKACABwACAntHCwOAKACABEAAQkmJaUyAGoAAAAA.Windoelicker:BAAALgAECgUJDAAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAAALgAECggJDgAAAA==.',
Wu='Wuggles:BAABLgAECn8nAAMKAAkJVhvCCAB/AgAKAAkJVhvCCAB/AgAdAAQJHA3GVQDNAAAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xb='Xbalanque:BAABLgAECn8bAAIgAAgJcBZCCQBBAQAgAAgJcBZCCQBBAQAAAA==.',
Xu='Xu:BAACLgAFFH8HAAIVAAMJhhPDNQD0AAAVAAMJhhPDNQD0AAAuAAQKfx4AAxUACAnvHp0LAG0CABUACAnvHp0LAG0CACQAAQkuECMQADoAAAAA.',
Ya='Yad:BAAALgADCgIJAgABLgADCgcJDgABAAAAAA==.Yakiki:BAABLgAECn8UAAIlAAcJAhrqHgC9AQAlAAcJAhrqHgC9AQABLgAFFAYJHgAlAHUiAA==.',
Ye='Yetil:BAABLgAECn8UAAIfAAcJNgjYIgAwAQAfAAcJNgjYIgAwAQAAAA==.Yey:BAABLgAECn8bAAMfAAgJ/hQxFgCgAQAfAAgJ/hQxFgCgAQAQAAMJJAE2JABFAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAAALgAECgUJBgAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECgcJEQAAAA==.Zaycursed:BAAALgAECgYJCwABLgAECggJFgACAOIdAA==.Zaydream:BAAALgAECggJDgABLgAECggJFgACAOIdAA==.Zaydämon:BAABLgAECn8WAAICAAgJ4h1HHwCWAgACAAgJ4h1HHwCWAgAAAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgYJEwABAAAAAA==.Ziggybeast:BAABLgAECn8iAAIdAAgJoCICDwCvAgAdAAgJoCICDwCvAgAAAA==.Ziggybrute:BAAALgADCgEJAQABLgAECggJIgAdAKAiAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAABLgAECn8wAAIVAAgJUR0pHQDYAQAVAAgJUR0pHQDYAQAAAA==.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAQAAAA==.',
Zu='Zugmebalz:BAAALgAECgIJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAECggJFgACAOIdAA==.',
['Zø']='Zøphar:BAAALgADCgEJAQAAAA==.',
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

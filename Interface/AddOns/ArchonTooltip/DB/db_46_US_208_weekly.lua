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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Paladin-Retribution','Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Priest-Discipline','Priest-Holy','Paladin-Holy','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Evoker-Devastation','Mage-Fire','Monk-Windwalker','Druid-Balance','Priest-Shadow','Druid-Feral','Rogue-Subtlety','Druid-Guardian','DeathKnight-Frost','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAAALgAECgYJEgAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAAALgAFFAMJBAAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Aginah:BAAALgADCgYJBgABLgAECgUJBgABAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAAALgAECgUJCwAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAAALgAECgUJEAAAAA==.Akshun:BAAALgADCgEJAQABLgAECgUJEAABAAAAAA==.',
Al='Alariel:BAABLgAECn8dAAICAAgJWBovGwDlAQACAAgJWBovGwDlAQABLgAFFAMJBQADALEWAA==.Albesuri:BAAALgAECgUJBQABLgAFFAYJEgACAM4ZAA==.Alcazar:BAAALgAECgUJEgAAAA==.Alcmeneinen:BAABLgAECn8YAAIEAAgJGwj5HwB+AQAEAAgJGwj5HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAcJFgAEAFUZAA==.Alliar:BAABLgAECn8hAAIFAAkJxBwVEAA+AgAFAAkJxBwVEAA+AgAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwABAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCAABLgAFFAcJFgAEAFUZAA==.',
Am='Amalek:BAAALgADCgIJAgAAAA==.Amerha:BAAALgAECgYJBgAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAABLgAECn8bAAIGAAgJbCDDHgAPAgAGAAgJbCDDHgAPAgABLgAECggJJgAEAJoaAA==.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAAALgAECgQJDQAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAAALgAECgQJCQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8PAAIHAAQJ5B3CHABxAQAHAAQJ5B3CHABxAQAuAAQKfyQAAgcACAkUIuwlANsCAAcACAkUIuwlANsCAAAA.',
At='Atlasdark:BAAALgAECgYJDQABLgAECgEJAQABAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQABAAAAAA==.Atrell:BAABLgAECn8eAAIGAAkJrRgAGQAzAgAGAAkJrRgAGQAzAgAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgADCgcJCAABLgAFFAQJCwAIACceAA==.',
Ba='Balrock:BAAALgADCgUJCAAAAA==.Balthromaw:BAABLgAECn8pAAIJAAgJqhdTGwAMAgAJAAgJqhdTGwAMAgAAAA==.Bangar:BAAALgAECgcJDgAAAA==.Bansol:BAAALgADCgEJAQAAAA==.Barron:BAABLgAECn8aAAIKAAYJGSKWFAAkAgAKAAYJGSKWFAAkAgAAAA==.Bartahh:BAAALgAECgcJEAAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCAABLgAECgkJIQALABAcAA==.Beardwaffle:BAABLgAECn8hAAILAAkJEBwMEQDqAQALAAkJEBwMEQDqAQAAAA==.Bearlysota:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.Beatstick:BAAALgADCgkJFAAAAA==.Belfdelphine:BAAALgAFFAEJAQAAAA==.',
Bi='Bifurthegrey:BAAALgAECgYJDQAAAA==.Bigbubba:BAABLgAFFH8HAAIHAAMJ1wSsVgC+AAAHAAMJ1wSsVgC+AAAAAA==.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8JAAMLAAQJThznCgBMAQALAAQJRRnnCgBMAQAMAAEJ/iNCFQBnAAAuAAQKfycABAsACAn4IyoUAKwCAAsACAlAISoUAKwCAA0AAwmPJOgSADkBAAwABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECgYJGQAEACcRAA==.Blaxdevoured:BAABLgAECn8VAAICAAgJbBpIGAD6AQACAAgJbBpIGAD6AQAAAA==.Blinkss:BAAALgADCggJCAAAAA==.Bloodhoundss:BAABLgAECn8eAAILAAgJSxWUFgCzAQALAAgJSxWUFgCzAQAAAA==.Blössöm:BAABLgAECn8eAAIOAAgJCBQHBgCjAQAOAAgJCBQHBgCjAQAAAA==.',
Bo='Bob:BAACLgAFFH8PAAICAAYJjxF1CQCTAQACAAYJjxF1CQCTAQAuAAQKfyAAAgIACQkfIdoIAEIDAAIACQkfIdoIAEIDAAAA.Bofft:BAABLgAECn8hAAIFAAgJdRiVEwAZAgAFAAgJdRiVEwAZAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAECggJEAAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAECgIJAgAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8UAAILAAgJ4gqNHgB1AQALAAgJ4gqNHgB1AQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8FAAIPAAIJehYBEgCdAAAPAAIJehYBEgCdAAAAAA==.',
Bu='Buldur:BAAALgADCgIJAwAAAA==.Buu:BAAALgAECgEJAgAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Caliginosity:BAABLgAECn8YAAIQAAcJeRc2DAD/AQAQAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.Cesard:BAAALgAECgYJEAAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgEJAwAAAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8lAAILAAkJkhzLBgCBAgALAAkJkhzLBgCBAgAAAA==.Chrondeezee:BAAALgAECgEJBgAAAA==.',
Ci='Ciradyl:BAAALgAECgEJAgAAAA==.Circledebull:BAAALgADCgIJAgAAAA==.',
Cl='Clamchowdér:BAAALgAECggJCAAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgEJBAABLgAECgIJAgABAAAAAA==.Coeurdeleon:BAACLgAFFH8FAAIRAAIJRhTkBwCCAAARAAIJRhTkBwCCAAAuAAQKfxsAAhEACAl5HEsIAFUCABEACAl5HEsIAFUCAAAA.Condemnation:BAABLgAECn8qAAMSAAkJqRkACgA2AgASAAkJRRAACgA2AgATAAgJ4hb2GQAMAgAAAA==.Congressmen:BAAALgAECgQJBAAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJBQABLgAECgMJAwABAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwABAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8WAAIUAAgJBQlHJQBfAQAUAAgJBQlHJQBfAQAAAA==.',
Cr='Crayak:BAACLgAFFH8FAAIVAAIJ6hVYDQCqAAAVAAIJ6hVYDQCqAAAuAAQKfyoAAxUACAluIuoCALoCABUACAluIuoCALoCAAIABglvE2V+AC4BAAAA.Crossbones:BAABLgAECn8VAAMWAAcJmhKaOABqAQAWAAcJvA+aOABqAQAXAAQJWA9SIAD7AAAAAA==.',
Cu='Cudà:BAACLgAFFH8IAAICAAUJEg62KgAHAQACAAUJEg62KgAHAQAuAAQKfxMAAgIACAltGpwyAC8CAAIACAltGpwyAC8CAAAA.Curbside:BAABLgAECn8gAAIYAAgJQxXJEgDDAQAYAAgJQxXJEgDDAQAAAA==.Curbstomped:BAAALgAECgEJAQAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAABLgAECn8dAAMZAAgJ3yDSIAC+AgAZAAgJPiDSIAC+AgAaAAcJFhpyEwDWAQAAAA==.Davinator:BAACLgAFFH8GAAINAAMJgSBNCQAYAQANAAMJgSBNCQAYAQAuAAQKfygABA0ACAnVJKsCALMCAA0ACAl/IqsCALMCAAsABwlIHZUdAGICAAwAAgnuFqErAJcAAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDQAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJBAAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAJAPATAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8MAAIHAAQJERLOLABQAQAHAAQJERLOLABQAQAuAAQKfyQAAgcACAnzGb4vAOEBAAcACAnzGb4vAOEBAAAA.Deselle:BAAALgAECggJEQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJAwAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8dAAIKAAYJLhTRMQBWAQAKAAYJLhTRMQBWAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn8sAAIRAAgJvhuiBAA3AgARAAgJvhuiBAA3AgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgADCgUJBQAAAA==.Donatelloh:BAAALgAECgYJEAAAAA==.Dortbraz:BAAALgAECgYJCAAAAA==.Dotmeharder:BAABLgAECn8bAAMJAAcJ8BOZegBnAQAJAAcJ8BOZegBnAQAbAAEJAABBJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Drakelayer:BAACLgAFFH8GAAIDAAMJNQ6GIQDlAAADAAMJNQ6GIQDlAAAuAAQKfxcAAwMABgnpHxMQANMBAAMABgnBHxMQANMBABwABgnlHDoHAEcBAAAA.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAAALgAECggJEwAAAA==.Draxyl:BAABLgAECn8mAAIZAAgJ5BRuVgDuAQAZAAgJ5BRuVgDuAQAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMCAAkJpRCqJwCdAQACAAkJpRCqJwCdAQAOAAUJwwuwEQCpAAAAAA==.Drogbar:BAABLgAECn8WAAIPAAgJXwiNCwA1AQAPAAgJXwiNCwA1AQAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8pAAMJAAgJ/Q4BMwCYAQAJAAgJ/Q4BMwCYAQAQAAMJNAYjUQB7AAAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn8cAAIZAAcJKSFlGgAsAgAZAAcJKSFlGgAsAgAAAA==.Duo:BAABLgAECn8hAAMdAAgJxhEcAwBtAQAdAAcJexEcAwBtAQAHAAcJqQfZwgCIAAABLgAECgYJEgABAAAAAA==.',
Eb='Ebontoes:BAABLgAECn8oAAMIAAkJ1iCoAwC/AgAIAAkJ1iCoAwC/AgAeAAIJ0gV8bgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8XAAIJAAYJbwNnhAC9AAAJAAYJbwNnhAC9AAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDAAAAA==.',
El='Eladra:BAAALgAECgUJBgAAAA==.Eleidon:BAAALgAECgYJCQAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elody:BAAALgAECgcJCgAAAA==.Elowynn:BAABLgAECn8wAAMSAAkJ7A8eEgC5AQASAAgJ8g0eEgC5AQATAAkJqQtLMgB3AQAAAA==.Elèctra:BAABLgAECn8ZAAMFAAcJUxkUNQA2AQAFAAcJUxkUNQA2AQAYAAQJCw/pNQDXAAAAAA==.',
En='Enyô:BAABLgAECn8ZAAIHAAcJzRYuQgChAQAHAAcJzRYuQgChAQAAAA==.',
Eo='Eorae:BAAALgAECgEJAgAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAAALgAECgUJBgAAAA==.',
Es='Esoss:BAAALgAECgMJAwAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAYJEgACAM4ZAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCAAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgMJBgABLgAECgYJEgABAAAAAA==.',
Fa='Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8bAAIeAAgJEyamAQATAwAeAAgJEyamAQATAwABLgAECggJIwAcALclAA==.',
Fh='Fhalanx:BAAALgAECgQJBwAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECgYJFgAfAFwTAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgYJEwABAAAAAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECggJGAAJAP4UAA==.Flapp:BAABLgAECn8YAAMJAAgJ/hSnJQDTAQAJAAgJ/hSnJQDTAQAQAAIJsQh5XABZAAAAAA==.Flarios:BAAALgAECgEJAQAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQAAAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8oAAIWAAgJRBeKGwD4AQAWAAgJRBeKGwD4AQAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJDwAAAA==.Frozenwings:BAAALgAECgUJBQAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgMJBgABLgAFFAQJBQAEANUPAA==.',
Ga='Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAAALgAECgYJDgAAAA==.Geraldene:BAABLgAECn8UAAITAAgJMQpaHQBeAQATAAgJMQpaHQBeAQAAAA==.Geraniho:BAAALgAECgEJAQAAAA==.',
Gh='Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn8qAAICAAkJ7RVXGAD6AQACAAkJ7RVXGAD6AQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgIJAgABLgAECgcJGQARAMkWAA==.Grimthruul:BAAALgAECgcJBwAAAA==.Grommkar:BAAALgAECgcJDQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gunnulf:BAAALgAECgYJDgAAAA==.',
Ha='Halucination:BAABLgAECn8iAAMTAAkJ0xHxKQCjAQATAAcJDRXxKQCjAQAgAAcJAhJHHwBCAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwABAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBQABLgAECgIJAgABAAAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgADCgUJBgAAAA==.',
He='Hetzák:BAABLgAECn8pAAIfAAgJQBKcFgCHAQAfAAgJQBKcFgCHAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8FAAIhAAIJ1AjtBwCfAAAhAAIJ1AjtBwCfAAAuAAQKfysAAiEACAlpHI8DAE0CACEACAlpHI8DAE0CAAAA.Hiphopuler:BAABLgAECn8rAAITAAcJrByeGwAAAgATAAcJrByeGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMGAAkJUB6dHwCuAgAGAAkJUB6dHwCuAgARAAQJUxijIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgADCgkJCQAAAA==.Holyschmit:BAABLgAECn8dAAIUAAgJbRlmEAAZAgAUAAgJbRlmEAAZAgAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8pAAINAAgJ0hKEDACdAQANAAgJ0hKEDACdAQAAAA==.Hucklebarry:BAABLgAECn8cAAIPAAgJ1BmNAwAcAgAPAAgJ1BmNAwAcAgAAAA==.Huntris:BAABLgAECn8ZAAIXAAgJOBzaCQAFAgAXAAgJOBzaCQAFAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAAALgAECgEJAQAAAA==.Hypnotykk:BAAALgAECgYJEgAAAA==.',
Ia='Iadygaga:BAAALgAECgEJAQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgEJAQAAAA==.Imrah:BAABLgAECn8cAAMeAAcJsBH3FwBmAQAeAAcJsBH3FwBmAQAIAAMJ2Qa1RgB7AAAAAA==.',
In='Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgADCgcJDgAAAA==.',
It='Ittáchi:BAAALgAECgUJBQAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAABLgAECn8qAAITAAgJJBoWCQBbAgATAAgJJBoWCQBbAgAAAA==.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAABLgAECn8dAAIiAAcJCBRyLACbAQAiAAcJCBRyLACbAQAAAA==.Jocon:BAABLgAECn8aAAIJAAgJSATVXQAWAQAJAAgJSATVXQAWAQAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJBQABLgAFFAMJCQAXAB0MAA==.Kanami:BAABLgAECn8dAAILAAYJ6BslGgCWAQALAAYJ6BslGgCWAQAAAA==.Kaori:BAAALgAECgcJEwAAAA==.Karamazov:BAABLgAECn8bAAIjAAgJwxo9BgDoAQAjAAgJwxo9BgDoAQAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJDQAAAA==.Kaynyx:BAABLgAECn8pAAIiAAgJ6hy/BQBcAgAiAAgJ6hy/BQBcAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8FAAIGAAMJQQYpNwDWAAAGAAMJQQYpNwDWAAAuAAQKfygAAwYACAk7F8krAM8BAAYACAk7F8krAM8BABEABQnRCtUfAJUAAAAA.Keedron:BAACLgAFFH8SAAICAAYJzhmuCQCnAQACAAYJzhmuCQCnAQAuAAQKfxsAAgIACAlJJIkLACUDAAIACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8fAAIZAAgJpRMXMwCtAQAZAAgJpRMXMwCtAQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8dAAMZAAcJXx1+JgDmAQAZAAcJXx1+JgDmAQAkAAEJPAVgGQApAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kilfogg:BAABLgAECn8XAAIYAAcJoxflKwC5AQAYAAcJoxflKwC5AQAAAA==.Killinflak:BAAALgAECgUJBgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAABLgAECn8mAAQEAAgJmho3CADmAQAEAAgJmho3CADmAQADAAYJNxBrJQAfAQAcAAEJkQW5QAAvAAAAAA==.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8UAAIHAAYJ2CL2BgD9AQAHAAYJ2CL2BgD9AQAuAAQKfxcAAgcACAm6IwcVACoDAAcACAm6IwcVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwABAAAAAA==.Kotonano:BAABLgAECn8UAAIfAAgJKR5iJgDKAQAfAAgJKR5iJgDKAQABLgAECggJHAAGAJAhAA==.',
Kr='Krangler:BAAALgAECgEJAQAAAA==.Krelock:BAABLgAECn8WAAIJAAcJYBRLUgDQAQAJAAcJYBRLUgDQAQAAAA==.Krymzendeath:BAAALgADCgkJHAABLgAFFAIJBgANAL4aAA==.Krísztina:BAAALgAECgYJEgAAAA==.',
Ku='Kuenybby:BAAALgADCgEJAQABLgAFFAYJEgACAM4ZAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwABAAAAAA==.Kuya:BAAALgAECgYJDwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8JAAIXAAMJHQwpEADzAAAXAAMJHQwpEADzAAAuAAQKfyMAAhcACQkmGP0HAG0CABcACQkmGP0HAG0CAAAA.',
La='Lakey:BAAALgAECgUJDgABLgAFFAQJDAAKAM0UAA==.Lakeyy:BAACLgAFFH8MAAIKAAQJzRSEFgAaAQAKAAQJzRSEFgAaAQAuAAQKfyEAAwoACAmlIg8LAOkCAAoACAmlIg8LAOkCAB8ABQn4GGU9AD0BAAAA.Lanayrd:BAAALgAECgEJAQAAAA==.Lawrence:BAACLgAFFH8HAAMFAAMJkwnWJwCzAAAFAAMJkwnWJwCzAAAYAAIJNww6IwCSAAAuAAQKfx0AAxgACAkKIb8KAOoCABgACAkKIb8KAOoCAAUAAgncBNyaADcAAAAA.',
Le='Lebonk:BAAALgAECgEJAQAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgQJBAAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8XAAQZAAYJGxmpGwBrAQAZAAUJiBipGwBrAQAkAAQJmwb7AwD6AAAaAAEJAAAUGgA0AAAuAAQKfy4AAyQACQkYIooBAGACABkACQk7IfIWAPICACQABwkiHYoBAGACAAAA.Lithe:BAAALgAECgMJBAABLgAFFAMJBgAYAEUOAA==.',
Lo='Locklear:BAABLgAECn8aAAIGAAgJrRXMOwCSAQAGAAgJrRXMOwCSAQAAAA==.Logic:BAACLgAFFH8XAAIHAAcJmRPeBQAMAgAHAAcJmRPeBQAMAgAuAAQKfyMAAgcACQmmIQ8WACQDAAcACQmmIQ8WACQDAAAA.Lolshield:BAAALgAECgYJBgABLgAFFAQJCwAIACceAA==.Lonelyphatty:BAAALgAECgcJBwAAAA==.Lorecan:BAABLgAECn8bAAIRAAgJWgk/FQD3AAARAAgJWgk/FQD3AAAAAA==.Lotei:BAAALgADCgUJBQAAAA==.',
Lu='Luchenta:BAAALgAECgYJEQAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDAABLgAFFAQJDAAKAM0UAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQfAAgJ2QiBOABWAQAfAAgJ2QiBOABWAQAhAAYJJAW2HwDjAAAjAAMJ6ARJKgBRAAAAAA==.',
Ma='Maani:BAAALgADCgMJBQAAAA==.Macediin:BAABLgAECn8iAAIZAAkJEhuQHQAXAgAZAAkJEhuQHQAXAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8TAAICAAYJBhd+BADpAQACAAYJBhd+BADpAQAuAAQKfycAAgIACQkYIkEIAEgDAAIACQkYIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJEwACAAYXAA==.Magegummy:BAAALgAFFAEJAQAAAA==.Magesterique:BAABLgAECn8oAAIHAAkJGhWmKwDzAQAHAAkJGhWmKwDzAQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAABLgAECn8rAAIGAAgJ5B/LEAB1AgAGAAgJ5B/LEAB1AgAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn8nAAIZAAkJCBwqDgCSAgAZAAkJCBwqDgCSAgAAAA==.Mamageek:BAABLgAECn8XAAIFAAkJ9hHlKADsAQAFAAkJ9hHlKADsAQAAAA==.Mami:BAAALgAECgUJDAABLgAECggJCAABAAAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJKAAHABoVAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAABLgAECn8YAAIlAAcJWxdKIACxAQAlAAcJWxdKIACxAQAAAA==.Maxson:BAABLgAECn8UAAIGAAcJphvFKQDYAQAGAAcJphvFKQDYAQAAAA==.',
Mc='Mcdeath:BAAALgAECgcJBwAAAA==.Mcversatile:BAABLgAECn8VAAIjAAYJuxc1DwCIAQAjAAYJuxc1DwCIAQABLgAECgcJBwABAAAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAITAAkJrBkrEABkAgATAAkJrBkrEABkAgAAAA==.Meeko:BAACLgAFFH8OAAIEAAYJTxkyBAC8AQAEAAYJTxkyBAC8AQAuAAQKfyAAAgQACQk0JCEBAEMDAAQACQk0JCEBAEMDAAAA.Mereoleona:BAAALgAECgMJAwAAAA==.Metalmagus:BAABLgAECn8fAAIHAAgJZxh0JAAUAgAHAAgJZxh0JAAUAgAAAA==.Metori:BAAALgAECgMJAwAAAA==.',
Mi='Millican:BAABLgAECn8VAAImAAkJTCLaAAD9AgAmAAkJTCLaAAD9AgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAYJEgACAM4ZAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8hAAIIAAkJ/hJBDwDVAQAIAAkJ/hJBDwDVAQAAAA==.Misslobster:BAAALgAECgUJCwAAAA==.Mistweaver:BAAALgAECgYJBwAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECgcJGQAFAFMZAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8FAAMDAAMJsRZcEAD/AAADAAMJsRZcEAD/AAAcAAEJVQsXCgBTAAAuAAQKfykAAwMACQkCHtEFACcDAAMACQnoHdEFACcDABwABwlFHWMLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAMJBQADALEWAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8oAAMfAAkJFh0VBQCcAgAfAAkJFh0VBQCcAgAKAAQJDxFbggDUAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8sAAIeAAkJbCN1AgDuAgAeAAkJbCN1AgDuAgAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
['Mò']='Mòrtale:BAAALgADCgMJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAQJCwAIACceAA==.Nahmo:BAAALgAECgUJEgAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEgABAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ne='Necro:BAABLgAECn8gAAIZAAkJvxrAKADaAQAZAAkJvxrAKADaAQAAAA==.Necrota:BAAALgAFFAIJBAABLgAFFAYJFAAHANgiAA==.Neuron:BAACLgAFFH8UAAIKAAYJKh2rAQD6AQAKAAYJKh2rAQD6AQAuAAQKfxoAAwoACAmAI/kOAMECAAoABwnlJPkOAMECAB8AAQkAG4JzAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJBAAAAA==.Nigdruu:BAABLgAECn8fAAIKAAgJehsjHABbAgAKAAgJehsjHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8cAAInAAgJVAwSBgCQAQAnAAgJVAwSBgCQAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.',
Or='Oralys:BAABLgAECn8fAAIUAAgJEiKoBQDKAgAUAAgJEiKoBQDKAgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladian:BAAALgAECgEJAQABLgAECgcJGQAFAFMZAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn8ZAAIRAAcJyRYADgBXAQARAAcJyRYADgBXAQAAAA==.Palugly:BAAALgADCgIJAgABLgAECgkJNgAOANMeAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAAALgAECgUJBgAAAA==.Patoko:BAABLgAECn8pAAImAAkJXxmDBQD3AQAmAAkJXxmDBQD3AQAAAA==.Paxwet:BAAALgADCgcJFQAAAA==.Payn:BAABLgAECn8jAAMcAAgJtyUrAQCUAgAcAAcJriUrAQCUAgADAAIJmx8ISgCsAAAAAA==.Paypay:BAABLgAECn8sAAMKAAkJ/SEXAgBsAwAKAAkJ/SEXAgBsAwAfAAYJIBClIwAcAQAAAA==.',
Ph='Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgIJAgAAAA==.',
Pi='Piglittle:BAABLgAECn8dAAMTAAcJMhnHEwC8AQATAAcJMhnHEwC8AQAgAAQJ9xnVOAAoAQAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJBgAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAABLgAECn8ZAAISAAYJlR++EwAQAgASAAYJlR++EwAQAgAAAA==.Prrowl:BAAALgAECgMJBQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rakashi:BAAALgADCgcJBwAAAA==.Ralon:BAAALgADCgUJBQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAECggJKwAGAOQfAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8VAAIYAAYJbBSzIwA3AQAYAAYJbBSzIwA3AQAAAA==.Rollos:BAABLgAECn8YAAIJAAcJ8BXQMwCVAQAJAAcJ8BXQMwCVAQAAAA==.Ronara:BAABLgAECn8UAAIlAAcJBRK0JwANAQAlAAcJBRK0JwANAQAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8YAAIDAAcJFSHmAwALAgADAAcJFSHmAwALAgAuAAQKfyAAAgMACQm3JfIAAMwDAAMACQm3JfIAAMwDAAAA.',
['Rä']='Rävylock:BAAALgAECgkJDwAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECgcJGQARAMkWAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgUJEAABAAAAAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgADCgUJBQAAAA==.Samtarkras:BAABLgAECn8nAAIEAAkJDhl7BABpAgAEAAkJDhl7BABpAgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgADCgcJBwAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEgABAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAABLgAECn8zAAMJAAcJCSGQKADEAQAJAAYJUBmQKADEAQAbAAcJjh8QCwCKAQABLgAECggJFAAOAP8JAA==.Selket:BAAALgAECgUJBwAAAA==.',
Sh='Shadowfawn:BAABLgAECn8bAAMgAAcJ4xCdGQBvAQAgAAcJ4xCdGQBvAQATAAEJsALkiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8FAAIgAAMJAAmfFADVAAAgAAMJAAmfFADVAAAuAAQKfz8AAiAACAloJG4CAPACACAACAloJG4CAPACAAEuAAUUBgkVABgAGBgA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamxie:BAAALgAECgEJAQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Sharklord:BAABLgAECn8cAAIiAAgJwherGAA+AQAiAAgJwherGAA+AQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIWAAQJSQu0HwAYAQAWAAQJSQu0HwAYAQAuAAQKfxUAAhYABgk3IN4rAKABABYABgk3IN4rAKABAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAcJGAADABUhAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.',
Sl='Slyde:BAABLgAECn8XAAIZAAgJhh//KADZAQAZAAgJhh//KADZAQAAAA==.',
Sm='Smalldk:BAACLgAFFH8VAAIZAAUJCBo2FwBIAQAZAAUJCBo2FwBIAQAuAAQKfyUAAhkACAnPIqwVAPoCABkACAnPIqwVAPoCAAAA.Smick:BAABLgAECn8ZAAIUAAYJ6hUnKgA9AQAUAAYJ6hUnKgA9AQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgQJCAAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn8sAAILAAgJTiErBQCmAgALAAgJTiErBQCmAgAAAA==.Soulfox:BAAALgAECgEJAgABLgAECgcJGQAFAFMZAA==.',
Sp='Spacing:BAAALgAECgYJBwAAAA==.Speknawz:BAAALgAECgMJAwABLgAECggJGwAiALkVAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.',
Sq='Squidmonk:BAAALgAECgYJBgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8UAAIOAAgJ/wnOCgAhAQAOAAgJ/wnOCgAhAQAAAA==.Starfail:BAAALgADCgIJAgABLgAECgYJEwABAAAAAA==.Starfu:BAAALgADCggJGAAAAA==.Stealthops:BAAALgAECggJEQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8RAAIeAAYJ6xx7AQC9AQAeAAYJ6xx7AQC9AQAuAAQKfxUAAh4ACAlEH5IMALECAB4ACAlEH5IMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCQAAAA==.Straydog:BAABLgAECn8WAAIFAAkJjxodCQCbAgAFAAkJjxodCQCbAgAAAA==.Strongsad:BAAALgAECgYJDgAAAA==.Stumptavion:BAABLgAECn8pAAIZAAcJqBmQYwDJAQAZAAcJqBmQYwDJAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgABAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgABAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Superpowers:BAABLgAECn8VAAIIAAgJZB5pBgByAgAIAAgJZB5pBgByAgAAAA==.Supersaiyan:BAAALgAECgYJCwAAAA==.Surtur:BAABLgAECn8yAAIMAAkJFB0AAgC4AgAMAAkJFB0AAgC4AgAAAA==.Sus:BAAALgAECgcJCwAAAA==.Suzel:BAAALgAECgUJDwAAAA==.',
Sw='Swoof:BAAALgAECggJEQABLgAECggJFwAfANkIAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn8bAAIVAAcJ6A9CEwBXAQAVAAcJ6A9CEwBXAQAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDAASAD8OAA==.Synwise:BAABLgAECn8jAAIKAAgJLiAeBwDcAgAKAAgJLiAeBwDcAgAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8FAAIWAAIJpw/BOgClAAAWAAIJpw/BOgClAAAuAAQKfysAAxYACAmKHMAVACECABYACAmKHMAVACECAA8AAQkiAlmaABkAAAAA.Taotien:BAABLgAECn8bAAIeAAgJCRksEQCvAQAeAAgJCRksEQCvAQAAAA==.Taowg:BAAALgADCgYJCQAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8dAAQTAAgJ8xyJCABmAgATAAgJ8xyJCABmAgASAAIJvwW0TQBbAAAgAAEJCg4/UQA2AAAAAA==.',
Th='Thanah:BAAALgADCggJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8FAAIZAAMJxgU5WQDTAAAZAAMJxgU5WQDTAAAuAAQKfyUAAhkACAnyFT05AJUBABkACAnyFT05AJUBAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwABAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJAwAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAABLgAECn82AAIOAAkJ0x43AQC5AgAOAAkJ0x43AQC5AgAAAA==.Tinytea:BAABLgAECn82AAIIAAkJeSNQAQAlAwAIAAkJeSNQAQAlAwAAAA==.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJCgAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8JAAMUAAQJcx8gCgB8AQAUAAQJcx8gCgB8AQAGAAEJUQ31XABMAAAuAAQKfygAAxQACQkYHcoMAEgCABQACAkqH8oMAEgCAAYABQneEIFeADIBAAAA.Totosapling:BAAALgADCgcJBwAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAQAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMLAAYJ0SGCLQD9AQALAAUJvSOCLQD9AQAMAAEJIxoFPgA8AAABLgAFFAQJCwAZAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsunt:BAAALgAECgYJDgAAAA==.Tsusha:BAAALgADCgkJEAABLgAECgYJDgABAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJBwABAAAAAA==.Turkeyleg:BAAALgADCgYJBwAAAA==.',
Tw='Twiisty:BAABLgAECn8WAAINAAgJXg5bEABcAQANAAgJXg5bEABcAQAAAA==.Twippy:BAAALgADCgYJBgABLgAECggJFgANAF4OAA==.',
Ty='Tyanis:BAAALgAECgQJCQABLgAECgYJDQABAAAAAA==.Tyriam:BAABLgAECn8pAAMGAAgJLRwwFQBQAgAGAAcJLRwwFQBQAgAUAAgJ9BasHACjAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8fAAIHAAcJNxUGSwCHAQAHAAcJNxUGSwCHAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwABAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Vandy:BAABLgAECn8nAAMCAAkJLAqbSQAcAQAVAAYJtwvVNwAmAQACAAkJXAmbSQAcAQAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8JAAIcAAQJlg1KAgA5AQAcAAQJlg1KAgA5AQAuAAQKfx4AAhwACAlhIEgEAMkCABwACAlhIEgEAMkCAAAA.Verso:BAABLgAECn8dAAIoAAgJCBhuAwDMAQAoAAgJCBhuAwDMAQAAAA==.',
Vi='Vikdruid:BAAALgAECgUJAwABLgAECgkJFQAmAEwiAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAmAEwiAA==.Vinushka:BAAALgAECgUJCgAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgcJGwADAE8eAA==.Vitalithry:BAABLgAECn8bAAMDAAcJTx62DQDxAQADAAcJRB62DQDxAQAcAAEJSh+vOABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgIJAgAAAA==.',
Vy='Vyndication:BAAALgAECgMJAwAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAECggJKwAGAOQfAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Wetpax:BAABLgAECn8eAAIZAAgJ5BLSNQCiAQAZAAgJ5BLSNQCiAQAAAA==.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn8dAAMFAAgJdhmdDwBDAgAFAAgJdhmdDwBDAgAYAAYJKR69GACJAQAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8JAAIgAAQJIxbqCABdAQAgAAQJIxbqCABdAQAuAAQKfywAAyAACAntHEsLAA8CACAACAntHEsLAA8CABMAAQklJVI/AGkAAAAA.Windoelicker:BAAALgAECgUJDAAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAAALgAECggJDgAAAA==.',
Wu='Wuggles:BAACLgAFFH8HAAIKAAMJSA0wEwDQAAAKAAMJSA0wEwDQAAAuAAQKfycAAwoACQlWGwgOAHACAAoACQlWGwgOAHACAB8ABAkcDclVAM0AAAAA.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xb='Xbalanque:BAABLgAECn8hAAMPAAkJ9xfpJgDyAQAPAAgJbxbpJgDyAQAWAAUJXxdsNgBzAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIZAAQJRBTZIwBYAQAZAAQJRBTZIwBYAQAuAAQKfx4AAxkACAnwHjMUAFkCABkACAnwHjMUAFkCACQAAQlgEAsWADUAAAAA.',
Ya='Yad:BAAALgADCgIJAgABLgADCgcJDgABAAAAAA==.Yakiki:BAABLgAECn8UAAIlAAcJAhrpHgC9AQAlAAcJAhrpHgC9AQABLgAFFAgJJgAlAHobAA==.',
Ye='Yetil:BAABLgAECn8YAAIUAAgJUAjaJABiAQAUAAgJUAjaJABiAQAAAA==.Yey:BAABLgAECn8fAAQUAAgJJRoIEAAeAgAUAAgJJRoIEAAeAgARAAMJJgHRLQBDAAAGAAEJDQS2FwEqAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAAALgAECgcJDAAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAAALgAECgkJDwAAAA==.Zaydream:BAABLgAECn8VAAQjAAgJChvDBAAiAgAjAAgJChvDBAAiAgAfAAQJmgvtMADOAAAhAAIJpAfKKQAwAAABLgAECgkJDwABAAAAAA==.Zaydämon:BAABLgAECn8WAAICAAgJ4B1DHwCWAgACAAgJ4B1DHwCWAgABLgAECgkJDwABAAAAAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgcJGgAhANYTAA==.Ziggybeast:BAABLgAECn8oAAIfAAkJViHUCQAvAgAfAAkJViHUCQAvAgAAAA==.Ziggybrute:BAAALgADCgEJAQABLgAECgkJKAAfAFYhAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAABLgAECn8zAAIZAAgJbB25JgDkAQAZAAgJbB25JgDkAQAAAA==.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgIJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAECgkJDwABAAAAAA==.',
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

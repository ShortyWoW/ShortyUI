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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','DemonHunter-Devourer','Evoker-Preservation','Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Warrior-Arms','Warrior-Protection','Warlock-Destruction','Paladin-Protection','Priest-Holy','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','DemonHunter-Vengeance','Monk-Windwalker','Priest-Discipline','Evoker-Devastation','Hunter-BeastMastery','Priest-Shadow','Druid-Balance','Druid-Feral','Paladin-Retribution','Rogue-Subtlety','Hunter-Survival','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Holy','Monk-Mistweaver',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abor:BAAALgAECgYJCwAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAAALgAECgcJDgAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aerosualt:BAAALgAECgYJDAAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Aginah:BAAALgADCgYJBgABLgAECgUJBgABAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAAALgAECgMJBAAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAAALgAECgUJDQAAAA==.',
Al='Alariel:BAAALgAFFAEJAQABLgAFFAMJBQACALEWAA==.Albesuri:BAAALgAECgUJBQABLgAFFAUJCgADAFEXAA==.Alcazar:BAAALgAECgUJBwAAAA==.Alcmeneinen:BAABLgAECn8YAAIEAAgJGwj3HwB+AQAEAAgJGwj3HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwAAAA==.Alliar:BAAALgAECgcJEwAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwABAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.',
Am='Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAAALgAECgYJEwABLgAECgcJHQAEAKITAA==.Ancalagðn:BAAALgAECgYJBwAAAA==.Angelshare:BAAALgAECgQJBwAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAAALgAECgQJCQAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJCwAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8HAAIFAAMJ1RN2KgALAQAFAAMJ1RN2KgALAQAuAAQKfyMAAgUACAnXIe8lANsCAAUACAnXIe8lANsCAAAA.',
At='Atlasdark:BAAALgAECgYJBwABLgAECgcJCgABAAAAAA==.Atlasstout:BAAALgAECgcJCgAAAA==.Atrell:BAAALgAECggJEQAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgADCgcJCAABLgAECggJIwAGAI8gAA==.',
Ba='Balthromaw:BAABLgAECn8eAAIHAAYJJRONHQAvAQAHAAYJJRONHQAvAQAAAA==.Bangar:BAAALgAECgYJCgAAAA==.Barron:BAABLgAECn8VAAIIAAYJlyDICADTAQAIAAYJlyDICADTAQAAAA==.Bartahh:BAAALgAECgYJDQAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardwaffle:BAABLgAECn8cAAIJAAgJtRokHwBXAgAJAAgJtRokHwBXAgAAAA==.Bearlysota:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.Beatstick:BAAALgADCgkJFAAAAA==.Belfdelphine:BAAALgAECgQJDQAAAA==.',
Bi='Bifurthegrey:BAAALgAECgMJAwAAAA==.Bigbubba:BAAALgAFFAEJAQAAAA==.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAABLgAECn8iAAQJAAgJOSE1FACsAgAJAAgJOSE1FACsAgAKAAQJNBY5GwAXAQALAAEJuA8kTAAlAAAAAA==.',
Bl='Bladesplicer:BAAALgADCgkJFwABLgAECgYJEgABAAAAAA==.Blaxdevoured:BAAALgAECgYJDAAAAA==.Blinkss:BAAALgADCggJCAAAAA==.Bloodhoundss:BAABLgAECn8XAAIJAAcJcBM4DABcAQAJAAcJcBM4DABcAQAAAA==.Blössöm:BAAALgAECgYJEAAAAA==.',
Bo='Bob:BAACLgAFFH8RAAIDAAYJ5Q/sAgB/AQADAAYJ5Q/sAgB/AQAuAAQKfyAAAgMACQkfIdsIAEIDAAMACQkfIdsIAEIDAAAA.Bofft:BAAALgAECgcJEgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgADCgMJAwAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAECgcJCAAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Broko:BAAALgADCgcJCwAAAA==.Brttneyfears:BAAALgAECgEJAQAAAA==.Brunko:BAAALgAECgQJBwAAAA==.Bryan:BAAALgAECgUJCQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAAALgAFFAIJAwAAAA==.',
Bu='Buldur:BAAALgADCgIJAwAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgADCgEJAgAAAA==.Caliginosity:BAABLgAECn8YAAIMAAcJeRcxDAD/AQAMAAcJeRcxDAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.Cesard:BAAALgAECgUJCgAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgEJAQAAAA==.Chrisbrewn:BAABLgAECn8XAAIJAAcJ8BunIABNAgAJAAcJ8BunIABNAgAAAA==.Chrondeezee:BAAALgAECgEJAwAAAA==.',
Ci='Ciradyl:BAAALgADCgkJCgAAAA==.Circledebull:BAAALgADCgIJAgAAAA==.',
Cl='Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Coeurdeleon:BAABLgAECn8YAAINAAgJcxtNCABVAgANAAgJcxtNCABVAgAAAA==.Condemnation:BAABLgAECn8fAAIOAAgJ4BajBADoAQAOAAgJ4BajBADoAQAAAA==.Congressmen:BAAALgAECgQJBAAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJBQABLgAECgMJAwABAAAAAA==.Corebin:BAAALgADCgcJDQABLgAECgMJAwABAAAAAA==.Coriantumr:BAAALgAECgEJAQAAAA==.Corriius:BAAALgAECgYJCAAAAA==.',
Cr='Crayak:BAABLgAECn8aAAMPAAcJzR/sAQARAgAPAAcJzR/sAQARAgADAAYJbxNlfgAuAQAAAA==.Crossbones:BAAALgAECgUJCAAAAA==.',
Cu='Cudà:BAACLgAFFH8FAAIDAAMJrRYgCgAWAQADAAMJrRYgCgAWAQAuAAQKfxYAAgMACQnrGZ8yAC8CAAMACQnrGZ8yAC8CAAAA.Curbside:BAAALgAECgYJEgAAAA==.Curbstomped:BAAALgADCgYJCgAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAABLgAECn8cAAMQAAgJ3yDQIAC+AgAQAAgJPiDQIAC+AgARAAcJFhpzEwDXAQAAAA==.Davinator:BAABLgAECn8bAAMJAAcJmh2YHQBhAgAJAAcJSB2YHQBhAgAKAAIJ7hacKwCXAAAAAA==.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJBgAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJAwAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Denarian:BAAALgADCgYJCQABLgAECgYJGgAHANkTAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8FAAIFAAMJOgthFQDeAAAFAAMJOgthFQDeAAAuAAQKfyMAAgUACAkBGX0MAOoBAAUACAkBGX0MAOoBAAAA.Deselle:BAAALgAECgYJDQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgADCgMJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAAALgAECgUJDwAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn8cAAINAAgJtRrhAQD3AQANAAgJtRrhAQD3AQAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgADCgUJBQAAAA==.Donatelloh:BAAALgAECgUJCgAAAA==.Dortbraz:BAAALgAECgIJAgAAAA==.Dotmeharder:BAABLgAECn8aAAMHAAYJ2RORegBnAQAHAAYJ2RORegBnAQASAAEJAABAJgBZAAAAAA==.Dotpocketz:BAAALgAECgMJBgAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Drakelayer:BAAALgAECgYJCgAAAA==.Drapo:BAAALgADCgkJCQAAAA==.Dratr:BAAALgAECgYJDAAAAA==.Draxyl:BAABLgAECn8iAAIQAAcJhBZ2VgDuAQAQAAcJhBZ2VgDuAQAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8ZAAMDAAcJkw+7ZgBuAQADAAcJpw67ZgBuAQATAAUJpAslBgDGAAAAAA==.Drogbar:BAAALgAECgcJEAAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8bAAMHAAgJPQkeFABvAQAHAAgJLwkeFABvAQAMAAMJNAYeUQB7AAAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAAALgAECgYJDwAAAA==.Duo:BAAALgAECgYJDQABLgAECgYJCwABAAAAAA==.',
Eb='Ebontoes:BAABLgAECn8aAAMGAAcJeR1rCABwAQAGAAcJeR1rCABwAQAUAAIJ0gVxbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAAALgAECgUJCwAAAA==.',
Ei='Einjhell:BAAALgAECgYJDAAAAA==.',
El='Eladra:BAAALgAECgUJBgAAAA==.Eleidon:BAAALgAECgYJCQAAAA==.Eletricbollo:BAAALgAECgUJDwAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elody:BAAALgAECgYJCAAAAA==.Elowynn:BAABLgAECn8eAAMOAAkJ/wo/MgB3AQAOAAkJtgg/MgB3AQAVAAQJJwoKFABhAAAAAA==.Elèctra:BAAALgAECgcJEgAAAA==.',
En='Enyô:BAAALgAECgYJDQAAAA==.',
Eo='Eorae:BAAALgAECgEJAgAAAA==.',
Er='Erada:BAAALgAECgEJAQAAAA==.',
Es='Esoss:BAAALgAECgMJAwAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAUJCgADAFEXAA==.',
Ex='Expectpriest:BAAALgADCgcJCAAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgMJAwABLgAECgYJCwABAAAAAA==.',
Fa='Fabian:BAABLgAECn8gAAIDAAgJ6BJZDgCYAQADAAgJ6BJZDgCYAQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAAALgAECgYJDAABLgAECgYJFQAWADglAA==.',
Fh='Fhalanx:BAAALgADCgYJBwAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECgYJDAABAAAAAA==.Firzen:BAAALgAECgUJDAAAAA==.',
Fl='Flaid:BAAALgAECgQJBgAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgYJEgABAAAAAA==.Flapfinnigan:BAAALgADCgMJAwAAAA==.Flapp:BAAALgAECgMJBgAAAA==.Flarios:BAAALgAECgEJAQAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQAAAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8aAAIXAAgJBAuDDgCQAQAXAAgJBAuDDgCQAQAAAA==.Freehandes:BAAALgAECgEJAQAAAA==.Fridolf:BAAALgAECgQJCgAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJCQAAAA==.Frozenwings:BAAALgAECgQJBAAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgMJBgABLgAECgIJBwABAAAAAA==.',
Ga='Garrosh:BAAALgADCgcJBQAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAAALgAECgYJCwAAAA==.Geraldene:BAAALgAECggJDgAAAA==.Geraniho:BAAALgADCgUJBQAAAA==.',
Gh='Ghydra:BAAALgAECgcJBwAAAA==.',
Gi='Gishwrath:BAAALgADCgUJBgAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Gremlinn:BAAALgADCgkJCQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgIJAgABLgAECgYJDwABAAAAAA==.Grimthruul:BAAALgADCgIJAgAAAA==.Grommkar:BAAALgAECgQJBQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gunnulf:BAAALgAECgYJDAAAAA==.',
Ha='Halucination:BAABLgAECn8ZAAMOAAcJlBPuKQCjAQAOAAYJTxbuKQCjAQAYAAYJmw3zDwD4AAAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCgABAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJAgAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgADCgUJBgAAAA==.',
He='Hetzák:BAABLgAECn8bAAIZAAgJyRD6BwB2AQAZAAgJyRD6BwB2AQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAABLgAECn8bAAIaAAcJVRwmCgAqAgAaAAcJVRwmCgAqAgAAAA==.Hiphopuler:BAABLgAECn8kAAIOAAcJrxyaGwAAAgAOAAcJrxyaGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8WAAMbAAgJuxyjHwCuAgAbAAgJuxyjHwCuAgANAAQJUxijIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holyschmit:BAAALgAECgYJEAAAAA==.',
Hu='Huatarm:BAABLgAECn8bAAILAAgJiA/gBAB0AQALAAgJiA/gBAB0AQAAAA==.Hucklebarry:BAAALgAECgYJDgAAAA==.Huntris:BAAALgAECgYJEQAAAA==.Hurdur:BAAALgAECgcJDAAAAA==.',
Hy='Hypnotykk:BAAALgAECgUJDAAAAA==.',
Ia='Iadygaga:BAAALgAECgEJAQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgEJAQAAAA==.Imrah:BAAALgAECgYJDwAAAA==.',
In='Innuendowo:BAAALgADCgcJCQAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgADCgcJDgAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAABLgAECn8aAAIOAAcJKBqFAwAXAgAOAAcJKBqFAwAXAgAAAA==.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAABLgAECn8WAAIcAAYJchR0LACbAQAcAAYJchR0LACbAQAAAA==.Jocon:BAAALgAECgYJEgAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.',
Ka='Kamo:BAAALgADCgcJBwABLgAECggJIAAdAO4aAA==.Kanami:BAAALgAECgUJDwAAAA==.Kaori:BAAALgAECgYJEQAAAA==.Karamazov:BAABLgAECn8YAAIeAAcJLRzmCAAZAgAeAAcJLRzmCAAZAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJDQAAAA==.Kaynyx:BAABLgAECn8bAAIcAAgJiRqeAQBFAgAcAAgJiRqeAQBFAgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAABLgAECn8jAAMbAAgJLhctCwDeAQAbAAgJLhctCwDeAQANAAEJuwuNRgAnAAAAAA==.Keedron:BAACLgAFFH8KAAIDAAUJURcwEwA4AQADAAUJURcwEwA4AQAuAAQKfx4AAgMACAkmJYoLACUDAAMACAkmJYoLACUDAAAA.Keiden:BAABLgAECn8aAAIQAAgJ2xLACQDiAQAQAAgJ2xLACQDiAQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAAALgAECgYJEQAAAA==.',
Ki='Kickstuff:BAAALgAECgEJAQAAAA==.Kilfogg:BAAALgAECgcJEQAAAA==.Kimosabi:BAAALgAECgYJBwAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECggJDgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAABLgAECn8dAAQEAAcJohPcGwCpAQAEAAcJohPcGwCpAQACAAQJ1wyCEgDLAAAWAAEJkQWxQAAvAAAAAA==.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Konjur:BAACLgAFFH8OAAIFAAUJSyPtBgDwAQAFAAUJSyPtBgDwAQAuAAQKfxcAAgUACAm6IwEVACoDAAUACAm6IwEVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwABAAAAAA==.Kotonano:BAABLgAECn8UAAIZAAgJHx5gJgDKAQAZAAgJHx5gJgDKAQABLgAECggJFwAbAP8fAA==.',
Kr='Krelock:BAABLgAECn8WAAIHAAcJYBRPUgDQAQAHAAcJYBRPUgDQAQAAAA==.Krymzendeath:BAAALgADCgkJHAABLgAECgcJFQAGAH0MAA==.Krísztina:BAAALgAECgYJDAAAAA==.',
Ku='Kulikov:BAAALgADCgYJCgABLgAECgQJCgABAAAAAA==.Kuya:BAAALgAECgUJDAAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAABLgAECn8gAAIdAAgJ7hr6BwBtAgAdAAgJ7hr6BwBtAgAAAA==.',
La='Lakey:BAAALgAECgUJDAABLgAFFAIJBQAIAFkYAA==.Lakeyy:BAACLgAFFH8FAAIIAAIJWRivCwCYAAAIAAIJWRivCwCYAAAuAAQKfx8AAwgACAmlIhQLAOkCAAgACAmlIhQLAOkCABkABQnwGGQ9AD0BAAAA.Lanayrd:BAAALgAECgEJAQAAAA==.Lawrence:BAABLgAECn8cAAMfAAgJCiG5CgDqAgAfAAgJCiG5CgDqAgAgAAEJ6wXlmgA3AAAAAA==.',
Le='Lebonk:BAAALgAECgEJAQAAAA==.Lexía:BAAALgAECgQJBAAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8PAAQhAAUJfRVAAQAcAQAQAAQJsxRnGABDAQAhAAQJqgZAAQAcAQARAAEJAAAGGgA0AAAuAAQKfygAAyEACQnlH0QAAIICABAACQkaHu8WAPICACEABwmWHEQAAIICAAAA.',
Lo='Locklear:BAABLgAECn8ZAAIbAAgJLxVlDwCrAQAbAAgJLxVlDwCrAQAAAA==.Logic:BAACLgAFFH8PAAIFAAYJwA+FCABcAQAFAAYJwA+FCABcAQAuAAQKfyEAAgUACQmmIQoWACUDAAUACQmmIQoWACUDAAAA.Lolshield:BAAALgAECgYJBgAAAA==.Lorecan:BAABLgAECn8UAAINAAYJhworJADnAAANAAYJhworJADnAAAAAA==.Lotei:BAAALgADCgUJBQAAAA==.',
Lu='Luchenta:BAAALgAECgUJBQAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgADCgEJAQABLgAFFAIJBQAIAFkYAA==.Luubitotems:BAAALgAECgYJBgAAAA==.',
Ly='Lyterbox:BAABLgAECn8XAAQZAAgJ2Qh9OABWAQAZAAgJ2Qh9OABWAQAaAAYJJAWzHwDjAAAeAAMJ6AREKgBRAAABLgAECggJHQAQAKMZAA==.',
Ma='Maani:BAAALgADCgMJBQAAAA==.Macediin:BAABLgAECn8aAAIQAAkJFBTvJwCbAgAQAAkJFBTvJwCbAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8PAAIDAAYJJRF9BADpAQADAAYJJRF9BADpAQAuAAQKfx4AAgMACQnZIEcIAEgDAAMACQnZIEcIAEgDAAAA.Maddice:BAAALgAECgUJBwABLgAFFAYJDwADACURAA==.Magegummy:BAAALgADCggJDgAAAA==.Magesterique:BAABLgAECn8aAAIFAAcJyBfXcgDtAQAFAAcJyBfXcgDtAQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAABLgAECn8YAAIbAAgJBB9sBQBBAgAbAAgJBB9sBQBBAgAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn8VAAIQAAgJtBboSwAPAgAQAAgJtBboSwAPAgAAAA==.Mamageek:BAABLgAECn8VAAIgAAgJnhPtKADsAQAgAAgJnhPtKADsAQAAAA==.Mami:BAAALgAECgUJCgAAAA==.Marksterique:BAAALgADCggJEgABLgAECgcJGgAFAMgXAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAAALgAECgcJEwAAAA==.Maxson:BAAALgAECgYJEgAAAA==.',
Mc='Mcversatile:BAAALgAECgYJDwAAAA==.',
Me='Meatloaf:BAABLgAECn8jAAIOAAkJ+RgoEABkAgAOAAkJ+RgoEABkAgAAAA==.Meeko:BAACLgAFFH8LAAIEAAUJdRkqBAC8AQAEAAUJdRkqBAC8AQAuAAQKfx4AAgQACAk1JCwAAF0DAAQACAk1JCwAAF0DAAAA.Mereoleona:BAAALgAECgIJAgAAAA==.Metalmagus:BAAALgAECgYJEAAAAA==.Metori:BAAALgADCgEJAQAAAA==.',
Mi='Millican:BAAALgAECggJDwAAAA==.Minata:BAAALgAECgEJAQABLgAFFAUJCgADAFEXAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJBgAAAA==.Mishi:BAABLgAECn8aAAIGAAgJ4xGJBwCCAQAGAAgJ4xGJBwCCAQAAAA==.Misslobster:BAAALgAECgQJBwAAAA==.Mistygoblin:BAAALgAECgYJCwABLgAECgcJEgABAAAAAA==.Mithos:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8FAAMCAAMJsRZXEAD/AAACAAMJsRZXEAD/AAAWAAEJVQsTCgBTAAAuAAQKfycAAwIACQkCHs8FACcDAAIACQnoHc8FACcDABYABwlFHWILACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAMJBQACALEWAA==.Mommythang:BAAALgADCggJDgAAAA==.Moomoo:BAABLgAECn8aAAMZAAcJFxyfHAAcAgAZAAcJFxyfHAAcAgAIAAQJDxFVggDUAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8eAAIUAAcJdyNpCgDSAgAUAAcJdyNpCgDSAgAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
['Mò']='Mòrtale:BAAALgADCgMJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAECggJIwAGAI8gAA==.Nahmo:BAAALgAECgUJCQAAAA==.Nahwa:BAAALgADCgcJDAAAAA==.Nametaken:BAAALgAECgEJAQAAAA==.',
Ne='Necro:BAABLgAECn8ZAAIQAAcJWBoLRwAfAgAQAAcJWBoLRwAfAgAAAA==.Necrota:BAAALgAECgcJDgABLgAFFAUJDgAFAEsjAA==.Neuron:BAACLgAFFH8OAAIIAAUJuiGoAQD6AQAIAAUJuiGoAQD6AQAuAAQKfxoAAwgACAmAIwAPAMECAAgABwnlJAAPAMECABkAAQkAG3JzAFQAAAAA.',
Ni='Nigdruu:BAABLgAECn8aAAIIAAgJexsjHABbAgAIAAgJexsjHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAAALgAECgYJDgAAAA==.',
No='Nokona:BAAALgAECgMJBwAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.',
Or='Oralys:BAAALgAECgYJEAAAAA==.Oromis:BAAALgAECgcJDwAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Pa='Padanfain:BAAALgAECgYJDwAAAA==.Padle:BAAALgAECgYJDAAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAAALgAECgYJDwAAAA==.Palugly:BAAALgADCgIJAgABLgAECgkJJQATADUaAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pappamidnite:BAAALgADCgYJBgAAAA==.Patoko:BAABLgAECn8cAAIiAAgJLRnCCgAhAgAiAAgJLRnCCgAhAgAAAA==.Paxwet:BAAALgADCgcJFQAAAA==.Payn:BAABLgAECn8VAAMWAAYJOCUECwArAgAWAAUJ1yUECwArAgACAAIJAR79SQCsAAAAAA==.Paypay:BAABLgAECn8bAAIIAAkJBB4EAQD+AgAIAAkJBB4EAQD+AgAAAA==.',
Ph='Pharoahlyfe:BAAALgAECgEJAQAAAA==.',
Pi='Piglittle:BAAALgAECgYJEwAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgADCgQJBAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJAwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAABLgAECn8XAAIVAAYJlB++EwAQAgAVAAYJlB++EwAQAgAAAA==.Prrowl:BAAALgAECgIJAgAAAA==.',
Ra='Ragnur:BAAALgAECgQJCAAAAA==.Rakashi:BAAALgADCgcJBwAAAA==.Ralon:BAAALgADCgUJBQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgADCgUJBQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAECggJGAAbAAQfAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAAALgAECgQJCAAAAA==.Rollos:BAAALgAECgcJEgAAAA==.Ronara:BAAALgAECgYJCQAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8RAAICAAYJfCEWAwD9AQACAAYJfCEWAwD9AQAuAAQKfyAAAgIACQm3JfEAAMwDAAIACQm3JfEAAMwDAAAA.',
['Rä']='Rävylock:BAAALgAECgkJDAAAAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgUJDQABAAAAAA==.Saintnick:BAAALgADCgUJBQAAAA==.Samtarkras:BAABLgAECn8ZAAIEAAcJfxK0HACgAQAEAAcJfxK0HACgAQAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgADCgcJBwAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgADCgEJAQAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAABLgAECn8dAAMHAAcJGRfqDACuAQAHAAYJihbqDACuAQASAAYJGRIQCwCKAQAAAA==.Selket:BAAALgAECgUJBwAAAA==.',
Sh='Shadowfawn:BAAALgAECgYJDgAAAA==.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamxie:BAAALgAECgEJAQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Sharklord:BAABLgAECn8cAAIcAAgJwBeBCABRAQAcAAgJwBeBCABRAQAAAA==.Shimada:BAAALgAFFAMJAwAAAA==.Shinryujin:BAAALgADCgcJCwABLgAFFAYJEQACAHwhAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJDwAAAA==.',
Sl='Slyde:BAAALgAECgYJEgAAAA==.',
Sm='Smalldk:BAACLgAFFH8QAAIQAAUJLRerCAA6AQAQAAUJLRerCAA6AQAuAAQKfyUAAhAACAnOIqUVAPoCABAACAnOIqUVAPoCAAAA.Smick:BAAALgAECgYJEQAAAA==.Smokermcpot:BAAALgADCgcJIQAAAA==.Smurs:BAAALgAECgQJBAAAAA==.',
Sn='Snackstand:BAAALgAECgQJCAAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgEJAgAAAA==.Sota:BAAALgAECgMJAwAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn8cAAIJAAcJ/hxhBgC/AQAJAAcJ/hxhBgC/AQAAAA==.Soulfox:BAAALgADCggJCAABLgAECgcJEgABAAAAAA==.',
Sp='Spacing:BAAALgAECgQJBAAAAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgYJCQAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAAALgAECgYJBgABLgAECgcJHQAHABkXAA==.Starfu:BAAALgADCggJEAAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8MAAIUAAUJTxwXAgCeAQAUAAUJTxwXAgCeAQAuAAQKfxUAAhQACAlEH5EMALECABQACAlEH5EMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormstyle:BAAALgAECgQJBwAAAA==.Straydog:BAAALgAECgkJCQAAAA==.Strongsad:BAAALgAECgYJDQAAAA==.Stumptavion:BAABLgAECn8nAAIQAAYJoxyaYwDJAQAQAAYJoxyaYwDJAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgABAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgABAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Superpowers:BAAALgAECgUJDgAAAA==.Supersaiyan:BAAALgAECgUJBgAAAA==.Surtur:BAABLgAECn8jAAIKAAgJsB17BACmAgAKAAgJsB17BACmAgAAAA==.Sus:BAAALgAECgQJBAAAAA==.Suzel:BAAALgAECgQJCAAAAA==.',
Sw='Swoof:BAAALgAECggJDwABLgAECggJHQAQAKMZAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgADCgMJBAAAAA==.Sygismund:BAAALgAECgYJDQAAAA==.Synndershock:BAAALgAECgUJCAABLgAFFAIJBQAVAB8RAA==.Synwise:BAABLgAECn8ZAAIIAAgJpR6qAQDGAgAIAAgJpR6qAQDGAgAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.',
Ta='Tagbone:BAABLgAECn8bAAMXAAcJwBzoCgC7AQAXAAcJwBzoCgC7AQAjAAEJIgJHmgAZAAAAAA==.Taotien:BAAALgAECgcJEgAAAA==.Taowg:BAAALgADCgYJCQAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8XAAQOAAgJUBqaAwAUAgAOAAgJUBqaAwAUAgAVAAIJvwW0TQBbAAAYAAEJ/g0TIAA6AAAAAA==.',
Th='Thanah:BAAALgADCggJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAABLgAECn8lAAIQAAgJ8hXQCQDhAQAQAAgJ8hXQCQDhAQAAAA==.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECgcJBwABAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgEJAQAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAABLgAECn8lAAITAAkJNRqyAAA8AgATAAkJNRqyAAA8AgAAAA==.Tinytea:BAABLgAECn8lAAIGAAkJ/R+/AAC+AgAGAAkJ/R+/AAC+AgAAAA==.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJBwAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAABLgAECn8iAAIkAAgJJx+HAgBwAgAkAAgJJx+HAgBwAgAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMJAAYJ0SGFLQD9AQAJAAUJvSOFLQD9AQAKAAEJIxr9PQA8AAAAAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsunt:BAAALgAECgUJDAAAAA==.Tsusha:BAAALgADCgkJEAABLgAECgUJDAABAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQAAAA==.Turkeyleg:BAAALgADCgYJBwAAAA==.',
Tw='Twippy:BAAALgADCgYJBgAAAA==.',
Ty='Tyanis:BAAALgAECgQJBQAAAA==.Tyriam:BAABLgAECn8bAAMkAAgJGhatLQDNAQAkAAgJGhatLQDNAQAbAAYJqBspEACkAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8UAAIFAAYJixW7ogCSAQAFAAYJixW7ogCSAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Vandy:BAABLgAECn8cAAMPAAgJrQrTNwAmAQADAAgJuwlXdgBDAQAPAAYJtwvTNwAmAQAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8FAAIWAAIJhBO/AQCZAAAWAAIJhBO/AQCZAAAuAAQKfx4AAhYACAlhIEYEAMkCABYACAlhIEYEAMkCAAAA.',
Vi='Vikdruid:BAAALgADCgMJAwABLgAECggJDwABAAAAAA==.Vikindia:BAAALgAECgUJBQABLgAECggJDwABAAAAAA==.Vinushka:BAAALgADCgcJBgAAAA==.Virdanfrost:BAAALgADCgkJDgAAAA==.Vitalic:BAAALgADCgEJAQABLgAECgQJDgABAAAAAA==.Vitalithry:BAAALgAECgQJDgAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCgAAAA==.',
We='Wetpax:BAAALgAECgYJEwAAAA==.',
Wh='Whiskeybeer:BAAALgAECgYJDgAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAABLgAECn8kAAIYAAgJ7RwqDgCgAgAYAAgJ7RwqDgCgAgAAAA==.Windoelicker:BAAALgAECgUJDAAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAAALgAECggJDgAAAA==.',
Wu='Wuggles:BAABLgAECn8eAAMIAAgJkhvMFwB4AgAIAAgJkhvMFwB4AgAZAAQJHA3CVQDNAAAAAA==.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgADCggJDQAAAA==.',
Xb='Xbalanque:BAABLgAECn8bAAIjAAgJcBZuBABOAQAjAAgJcBZuBABOAQAAAA==.',
Xu='Xu:BAABLgAECn8aAAMQAAgJOR4bAwB3AgAQAAgJOR4bAwB3AgAhAAEJLhABCQA6AAABLgAECgYJFAAJANEhAA==.',
Ya='Yakiki:BAABLgAECn8UAAIlAAcJAhr4HgC+AQAlAAcJAhr4HgC+AQABLgAFFAYJGAAlAPsgAA==.',
Ye='Yetil:BAAALgAECgcJDQAAAA==.Yey:BAABLgAECn8XAAIkAAcJFBchLgDLAQAkAAcJFBchLgDLAQAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAAALgAECgIJAwAAAA==.',
Za='Zak:BAAALgAECgIJAgAAAA==.Zarana:BAAALgAECgYJDAAAAA==.Zaycursed:BAAALgAECgUJCgABLgAECggJFgADAHMcAA==.Zaydream:BAAALgAECgYJBgABLgAECggJFgADAHMcAA==.Zaydämon:BAABLgAECn8WAAIDAAgJcxxEHwCWAgADAAgJcxxEHwCWAgAAAA==.Zayzen:BAAALgAECgEJAQABLgAECggJFgADAHMcAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECgYJDQABAAAAAA==.Ziggybeast:BAABLgAECn8cAAIZAAgJ1iECDwCvAgAZAAgJ1iECDwCvAgAAAA==.Ziggybrute:BAAALgADCgEJAQABLgAECggJHAAZANYhAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAABLgAECn8uAAIQAAgJ2xugCAD0AQAQAAgJ2xugCAD0AQAAAA==.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgADCgEJAwAAAA==.',
Zu='Zugmebalz:BAAALgAECgIJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAECggJFgADAHMcAA==.',
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

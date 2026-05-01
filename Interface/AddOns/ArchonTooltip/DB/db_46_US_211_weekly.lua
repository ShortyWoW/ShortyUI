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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Shaman-Restoration','Druid-Feral','Priest-Shadow','Druid-Restoration','Druid-Balance','Shaman-Elemental','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Mage-Arcane','Priest-Discipline','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Frost','Evoker-Preservation','Priest-Holy','Monk-Windwalker','Druid-Guardian','Warrior-Protection','DemonHunter-Vengeance',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Achooe:BAABLgAECn8WAAMBAAYJ0AYLGwCIAAABAAUJDwgLGwCIAAACAAEJ0wEP5QAeAAAAAA==.',
Ad='Adrel:BAAALgAECgMJAwAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQ5CAAnAwADAAgJNiQ5CAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw4DQCPAgAEAAgJ3Bo4DQCPAgAFAAYJGhHJiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn8fAAQGAAgJTA2DDgB2AQAGAAcJAA2DDgB2AQAHAAUJtQaqWwDUAAAIAAUJAgbWlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8XAAIJAAcJig1LVAA3AQAJAAcJig1LVAA3AQAAAA==.Agathorz:BAAALgAECgEJAQAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgYJBwAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECggJFQAKAOQcAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAABLgAECn8hAAMDAAcJxB1rCgADAgADAAcJxB1rCgADAgALAAYJ0hBSCwBMAQAAAA==.Allei:BAAALgAECgMJAwABLgAECggJIwAMABUWAA==.Alyndrya:BAAALgAECgYJEAAAAA==.Alyndrys:BAABLgAECn8XAAINAAcJlw4BEgCNAQANAAcJlw4BEgCNAQAAAA==.',
Am='Amelialynne:BAABLgAECn8hAAIFAAgJiBOtGgCVAQAFAAgJiBOtGgCVAQAAAA==.Amithralia:BAAALgAECgYJEgAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAAALgAECgUJDgAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anissel:BAABLgAECn8ZAAIOAAgJmhBqEgByAQAOAAgJmhBqEgByAQAAAA==.Anzarna:BAAALgAECgUJCwAAAA==.',
Ao='Aohikari:BAAALgADCgUJBgABLgAFFAYJEgAPAH4eAA==.Aokuma:BAACLgAFFH8SAAIPAAYJfh6CAQAGAgAPAAYJfh6CAQAGAgAuAAQKfx4AAw8ACAmsJJIGACIDAA8ACAmsJJIGACIDABAAAwlSIQJIAAwBAAAA.',
Ap='Aprigity:BAAALgAECgYJDQAAAA==.',
Aq='Aquaten:BAAALgAECgUJDgAAAA==.',
Ar='Arashinigon:BAAALgAECggJEAAAAA==.Arceus:BAAALgAECgIJAgAAAA==.Archaon:BAAALgAECgYJEgAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnicACaAQACAAYJeRnicACaAQAAAA==.Ariandise:BAAALgAECgMJAwAAAA==.Arick:BAAALgAECggJEwAAAA==.Ark:BAABLgAECn8rAAMMAAgJlSb+AQBrAwAMAAgJlSb+AQBrAwARAAYJ6iSmCAAVAgAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmódeus:BAABLgAECn8UAAQSAAYJuRD3DQBTAQASAAYJXQ73DQBTAQATAAQJYQ1QPgC7AAAUAAEJxggQKAEqAAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAAALgAECgYJEAAAAA==.',
['Aì']='Aìo:BAAALgAECgUJCwABLgAECgYJBwAVAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJAQAAAA==.Baelhay:BAAALgAECgUJDgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJCwAAAA==.Belitha:BAABLgAECn8gAAIFAAkJoR8NEwDoAgAFAAkJoR8NEwDoAgAAAA==.Belmaris:BAABLgAECn8WAAIWAAYJxBXCBQBhAQAWAAYJxBXCBQBhAQAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAAALgAECgQJCgAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAAALgAECggJDgAAAA==.Bimbosuzi:BAAALgAECgUJDQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.',
Bl='Blasteyes:BAAALgAECgYJEAAAAA==.Blegh:BAABLgAECn8hAAMXAAgJLB6gCgAxAgAXAAcJMh2gCgAxAgAYAAYJIBsjHwDKAQAAAA==.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn8pAAINAAgJoh+jAQCAAgANAAgJoh+jAQCAAgAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMZAAgJxQmSIgAyAQAZAAgJxQmSIgAyAQACAAYJpQq3sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8VAAIKAAgJ5BzzHQASAgAKAAgJ5BzzHQASAgAAAA==.Bosco:BAAALgAECgMJBAAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAVAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAAALgAECgEJAQAAAA==.Buggers:BAAALgAECgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAAALgAECgUJBQAAAA==.',
Ca='Caiphage:BAABLgAECn8VAAIFAAgJ0heQTADCAQAFAAgJ0heQTADCAQAAAA==.Caladelm:BAAALgAECgUJBwAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAAALgAECgYJEAAAAA==.Carlarae:BAAALgAECgYJDgAAAA==.Castelo:BAAALgAECgUJDgAAAA==.',
Ce='Cedra:BAAALgAECgYJCwAAAA==.Cegeo:BAABLgAECn8lAAITAAgJKRNoAwC6AQATAAgJKRNoAwC6AQAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Cheepdeeps:BAABLgAECn8pAAIDAAgJiBikCQAQAgADAAgJiBikCQAQAgAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAQAAAA==.Chupathingyy:BAABLgAECn8WAAMUAAYJ5x9oWQC7AQAUAAUJyiBoWQC7AQASAAQJSBj0EgD9AAAAAA==.',
Ci='Ciennajewel:BAAALgADCgYJBwAAAA==.Cirdle:BAAALgAECgYJDQAAAA==.Cirona:BAAALgAECgYJEgAAAA==.',
Cl='Clausewitz:BAAALgAECggJEwAAAA==.Cloroxx:BAAALgAECgUJBgAAAA==.',
Co='Cobalt:BAAALgAECgcJEQAAAA==.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAVAAAAAA==.Colphere:BAAALgADCgUJBQAAAA==.Coolkid:BAAALgAECgIJBQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8gAAIRAAgJ2AJcJQD5AAARAAgJ2AJcJQD5AAAAAA==.Creamyweamy:BAAALgAECgUJEAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8UAAMJAAYJZQjTaQAGAQAJAAYJZQjTaQAGAQAaAAEJ6wGtIQAmAAAAAA==.Crucifixea:BAAALgADCgUJCgAAAA==.Cruzmaster:BAAALgAECggJEgAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAAALgAECgYJEAAAAA==.',
Cu='Cupp:BAAALgAECgQJBwAAAA==.Cute:BAAALgAECgYJCAABLgAFFAUJCgAbAO8PAA==.',
Da='Daamass:BAAALgADCgMJAwAAAA==.Daddy:BAACLgAFFH8RAAIcAAYJKyHQAABdAgAcAAYJKyHQAABdAgAuAAQKf2sAAhwACQmzJgwAAAkEABwACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAVAAAAAA==.Daggonet:BAAALgAECgIJAwAAAA==.Dalrin:BAABLgAECn8XAAMdAAYJ7A+vFQBiAQAdAAYJ7A+vFQBiAQARAAQJzAfjZwCjAAAAAA==.Darkcarnival:BAABLgAECn8WAAIUAAYJ2xouLQB3AQAUAAYJ2xouLQB3AQAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAABLgAECn8cAAIDAAgJmBVNLAADAgADAAgJmBVNLAADAgAAAA==.Darkphoenixx:BAAALgAECgYJBwAAAA==.Darthraider:BAAALgAECgQJCwAAAA==.Dasnotgood:BAAALgAECgUJCAAAAA==.Datoneshammy:BAAALgAECgUJCQAAAA==.Davrøs:BAAALgAECgIJBQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAAALgAECggJEgAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAAALgAECgYJEAAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAAALgAECgYJDwAAAA==.Denidan:BAAALgADCgcJDAAAAA==.Dertus:BAABLgAECn8VAAIQAAYJ0RQ9GQAzAQAQAAYJ0RQ9GQAzAQAAAA==.Desdemona:BAAALgAECgYJEAAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAAALgAECgQJBAABLgAECgYJEAAVAAAAAA==.',
Di='Dianimal:BAAALgAECgYJBwAAAA==.Dings:BAAALgADCgcJCAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAAALgAECgcJEQAAAA==.',
Dk='Dklel:BAACLgAFFH8LAAIeAAQJjR+UCQCPAQAeAAQJjR+UCQCPAQAuAAQKfz4AAh4ACQlyJloAAIUDAB4ACQlyJloAAIUDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8aAAMCAAcJcRlwPwAoAgACAAcJcRlwPwAoAgABAAQJfAEQIwBMAAAAAA==.Doomfeather:BAAALgAECgEJAgAAAA==.Dorigog:BAABLgAECn8hAAICAAgJERDhNQBsAQACAAgJERDhNQBsAQAAAA==.',
Dr='Dragon:BAAALgAECgYJCwAAAA==.Dragonpunch:BAABLgAECn8WAAIcAAgJnBsMGQD0AQAcAAgJnBsMGQD0AQAAAA==.Driftyshaman:BAAALgAECgUJCwAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAAALgAECgQJBQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Dw='Dworflundgrn:BAAALgAECgYJEgAAAA==.',
Dy='Dyamï:BAABLgAECn8WAAIcAAYJRRciEgCMAQAcAAYJRRciEgCMAQAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAAALgAECgUJCQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAAALgAECgYJEgAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Ellä:BAAALgADCgkJCQAAAA==.Elrythe:BAABLgAECn8mAAIIAAgJDx/cDAA3AgAIAAgJDx/cDAA3AgAAAA==.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Erzulie:BAAALgADCgIJAgAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.',
Ev='Evilmorana:BAAALgADCgQJBAAAAA==.',
Fa='Fallyynn:BAAALgAECgYJCgAAAA==.Fatalii:BAAALgADCgEJAQABLgAECgcJAQAVAAAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAAALgAECgYJCAAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgADCgYJBgAAAA==.',
Fl='Floofies:BAACLgAFFH8PAAIdAAUJqBaHAQAPAQAdAAUJqBaHAQAPAQAuAAQKfx0AAh0ACQk9JLUDAO8CAB0ACQk9JLUDAO8CAAAA.Floofyfu:BAAALgAECgYJCgABLgAFFAUJDwAdAKgWAA==.',
Fr='Fredrickk:BAAALgAECgEJAgABLgAECgMJAwAVAAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgADCgUJBQAAAA==.Furrylight:BAAALgAECgIJAgAAAA==.Furryphase:BAACLgAFFH8KAAIMAAUJ6hOXBgB+AQAMAAUJ6hOXBgB+AQAuAAQKfx4AAgwACQnwGw4NALUCAAwACQnwGw4NALUCAAAA.Fuzzington:BAAALgAECgQJBAABLgAFFAUJDwAdAKgWAA==.Fuzzydunlop:BAAALgAECgMJAwAAAA==.',
['Fï']='Fïddlestïcks:BAAALgADCgMJAgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgEJAQAAAA==.Gallin:BAAALgAECgEJAQAAAA==.Gauldangit:BAAALgAECgMJAwAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJDAAAAA==.',
Gl='Glaur:BAABLgAECn8gAAIMAAgJ/xp4DAAjAgAMAAgJ/xp4DAAjAgAAAA==.',
Go='Goatjira:BAAALgADCgEJAQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECggJFAAeAFUaAA==.Gripisrdy:BAABLgAECn8WAAMeAAYJkx4UNwBdAQAeAAUJDx8UNwBdAQAfAAEJnxz6JABUAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8YAAMgAAgJ5iFiAAC7AgAgAAgJ5iFiAAC7AgAhAAEJugwHXgA7AAAAAA==.Guìdo:BAAALgAECgMJAwAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAAALgAECgEJAQAAAA==.Hairyjolene:BAAALgAECgUJDgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAECggJIgAVAAAAAA==.Handsome:BAAALgADCgcJCAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIUAAcJGh+nJQB8AgAUAAcJGh+nJQB8AgAAAA==.Harthvader:BAAALgADCgcJCAAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJCgAAAA==.Heycarlos:BAAALgAECgYJEQAAAA==.',
Hi='Hikaridh:BAAALgAFFAMJBAABLgAFFAYJEgAPAH4eAA==.Hikarimonk:BAAALgAECgEJAQABLgAFFAYJEgAPAH4eAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAYJEgAPAH4eAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgIJAgAVAAAAAA==.Holyblimblam:BAAALgAECgUJCAAAAA==.Hosemachine:BAABLgAECn8lAAMeAAgJsxyuGAD2AQAeAAgJgxmuGAD2AQAfAAcJ1xWkHQBcAQAAAA==.Hotpants:BAABLgAECn8WAAIOAAYJggoOHAAdAQAOAAYJggoOHAAdAQAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJCgAAAA==.Icyjackets:BAAALgAECgUJDgAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgEJAQAAAA==.',
Il='Ilamuna:BAAALgAECgEJAQAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgADCgEJAQAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAAALgAECgYJDAAAAA==.Jameson:BAAALgAECgcJEQAAAA==.Jamiel:BAAALgADCgEJAQAAAA==.Jasmind:BAABLgAECn8fAAMPAAYJcQk8PwDUAAAPAAYJcQk8PwDUAAAQAAEJLApPiAAnAAAAAA==.',
Je='Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAVAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAAALgAECgYJCgAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgADCgUJBQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8UAAMMAAYJIhYNNgCrAQAMAAYJIhYNNgCrAQARAAUJXA42KQDhAAAAAA==.Jiwâ:BAACLgAFFH8MAAIOAAQJ7wnxCAAyAQAOAAQJ7wnxCAAyAQAuAAQKfzIAAg4ACQn2HaACAKMCAA4ACQn2HaACAKMCAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECgUJDQAAAA==.Joss:BAAALgAECgEJAQAAAA==.',
Ka='Kadan:BAAALgAECgYJBgABLgAECgkJIAAFAKEfAA==.Kahless:BAAALgADCgIJAwAAAA==.Kakwaa:BAAALgAECgYJEAAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJAwAAAA==.Keyadistor:BAABLgAECn8UAAMeAAgJVRpAXQDbAQAeAAYJ7BpAXQDbAQAiAAUJmBi0CwAAAQAAAA==.',
Kh='Khazabrew:BAABLgAECn8hAAIKAAgJBx5bBQBUAgAKAAgJBx5bBQBUAgAAAA==.',
Ki='Kiamara:BAAALgAECgYJEAAAAA==.Kinderlin:BAAALgAECgYJEgAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJCAAAAA==.',
Kr='Krelix:BAAALgAECgYJEAAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
La='Lancaban:BAAALgAECgUJCAAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQXAAgJfRaLDwDiAQAXAAYJNhmLDwDiAQAYAAMJfRR7QgDYAAAjAAQJlQqIMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.Lithena:BAAALgADCgQJBwAAAA==.',
Lo='Loadedtater:BAABLgAECn8kAAMIAAgJ+ST/AQABAwAIAAgJ8ST/AQABAwAHAAUJ3CWMJgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAAALgAECgMJAwABLgAECggJIwAMABUWAA==.Lorianne:BAABLgAECn8jAAMMAAgJFRZkKQDpAQAMAAgJFRZkKQDpAQARAAUJsAutVgDqAAAAAA==.Lorri:BAAALgADCgQJBQABLgAECggJIwAMABUWAA==.',
Lu='Lucianas:BAAALgAECgYJCwAAAA==.Lunchböx:BAAALgAECgMJAwAAAA==.Lunico:BAAALgADCgEJAgAAAA==.',
Ly='Lysi:BAAALgAECgUJDgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Madaea:BAABLgAECn8hAAIcAAgJtx65CwCWAgAcAAgJtx65CwCWAgAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn8hAAIJAAgJ5BrlGgAKAgAJAAgJ5BrlGgAKAgABLgAFFAIJBQAGAM8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAAALgAECgYJCwAAAA==.Makavali:BAAALgADCgYJDAABLgAECgYJCwAVAAAAAA==.Makdaddy:BAAALgAECgUJBQABLgAECgYJCwAVAAAAAA==.Malzeth:BAAALgADCgUJEgAAAA==.Marrina:BAAALgADCgMJAwAAAA==.Matagi:BAAALgAECggJEQAAAA==.Mate:BAAALgADCgcJDQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgADCgYJBgAAAA==.Meeseks:BAAALgADCgcJBwAAAA==.Melbeast:BAAALgAECgYJEAAAAA==.Melorea:BAAALgADCgUJBQAAAA==.Merdin:BAAALgAECggJEQAAAA==.Methmartion:BAAALgAECgUJDgAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mikewai:BAABLgAECn8XAAIFAAgJgQ9oUgCtAQAFAAgJgQ9oUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgADCgEJAQAAAA==.Missiah:BAAALgAECgYJEgAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgIJAgAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECggJGAAQAAwVAA==.Molfise:BAAALgAECgYJEQAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8eAAIkAAgJMRRFIgDSAQAkAAgJMRRFIgDSAQAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAAALgAECgYJEAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgMJAgAAAA==.',
Mu='Mugatoo:BAAALgADCgMJAwAAAA==.Musubi:BAAALgADCgEJAQABLgAECgYJCwAVAAAAAA==.',
Mx='Mxtemlen:BAAALgADCgkJCgABLgAECgYJEAAVAAAAAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCgYJDQAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgYJBgABLgAECggJFgAcAJwbAA==.Myttus:BAEALgADCgMJAwABLgAECgQJDgAVAAAAAA==.',
['Mê']='Mêrlin:BAABLgAECn8YAAIJAAgJSwWfYwAUAQAJAAgJSwWfYwAUAQAAAA==.',
Na='Nachtelf:BAABLgAECn8pAAIIAAgJvhzFCgBRAgAIAAgJvhzFCgBRAgAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nannysham:BAAALgAECgcJDQAAAA==.Naomí:BAABLgAECn8cAAIUAAYJ0wx8UQD8AAAUAAYJ0wx8UQD8AAAAAA==.Natadawn:BAAALgAECgEJAQAAAA==.Natalone:BAABLgAECn8iAAIJAAgJ8SHZDgBnAgAJAAgJ8SHZDgBnAgAAAA==.Natherel:BAAALgAECgUJDgAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAAALgAECgMJAwABLgAFFAUJCgAbAO8PAA==.',
Ne='Newander:BAABLgAECn8YAAIPAAcJWBDPNgD7AAAPAAcJWBDPNgD7AAAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgQJBAAAAA==.Nirra:BAAALgADCggJDQAAAA==.',
No='Nonphatmilk:BAAALgAECgMJBQAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8kAAMeAAgJIxI4LACKAQAeAAgJIxI4LACKAQAfAAEJGxJzRQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8cAAIJAAgJAx+QEgBGAgAJAAgJAx+QEgBGAgAAAA==.',
Og='Ograskygazer:BAAALgAECgUJDgAAAA==.',
Om='Omee:BAAALgAECgYJEAAAAA==.Omy:BAABLgAECn8VAAIJAAYJXQRa9AARAQAJAAYJXQRa9AARAQAAAA==.',
Or='Oralena:BAAALgAECgUJDgAAAA==.Orioncheats:BAABLgAECn8hAAIeAAgJyBnNGwDhAQAeAAgJyBnNGwDhAQAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAVAAAAAA==.',
Pa='Paladingbat:BAAALgAECgEJAQAAAA==.Pallygoboom:BAAALgADCgUJBQABLgAECgYJCgAVAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paull:BAAALgAECgYJCgAAAA==.',
Pe='Ped:BAABLgAECn8eAAMlAAgJBRylCQDdAQAlAAgJBRylCQDdAQAcAAEJ2AHZdgAXAAAAAA==.Peon:BAAALgADCgkJCQAAAA==.',
Ph='Pharune:BAABLgAECn8WAAImAAYJsAyfDwC/AAAmAAYJsAyfDwC/AAAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAAALgAECgUJDAAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAECgcJBAAVAAAAAA==.Picklebob:BAAALgAECgcJBAAAAA==.Pickleboe:BAAALgAECgUJBQABLgAECgcJBAAVAAAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.',
Pl='Plandemic:BAAALgAECgQJBQAAAA==.',
Po='Pockithealz:BAAALgAECgEJAQABLgAECgcJAQAVAAAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.',
Pr='Precious:BAACLgAFFH8KAAIbAAUJ7w9mBQCRAQAbAAUJ7w9mBQCRAQAuAAQKfzMABBsACQnwH6YDAC4DABsACQnwH6YDAC4DACQABglwDxE2AGQBAA4AAQkAALxlAC0AAAAA.',
['Pä']='Pängari:BAAALgADCgYJBgAAAA==.',
Qu='Quattro:BAAALgAECgYJBwAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn8qAAMDAAcJSBnLDQDWAQADAAcJJhnLDQDWAQALAAEJhBWMKQBCAAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAAALgAECgYJEAABLgAECgcJGAAPAFgQAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAAALgAECgUJCwAAAA==.',
Re='Rehum:BAEALgAECgQJDgAAAA==.Remagtrepxe:BAAALgADCgMJBQAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgADCgMJBgAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAAALgAECgYJEwAAAA==.Revèndreth:BAAALgADCgMJAwAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGRd8PQD+AQAFAAcJGRd8PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgIJAgAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn8fAAIOAAgJ5QheFwBDAQAOAAgJ5QheFwBDAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAAALgAECgYJDQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8bAAMeAAgJzBsXFQARAgAeAAgJmRsXFQARAgAiAAYJrhWuCABaAQAAAA==.Rolemartyr:BAAALgAECgYJCgAAAA==.Rooth:BAAALgAECgYJDwAAAA==.Roryn:BAABLgAECn8sAAICAAgJ4yHiCACPAgACAAgJ4yHiCACPAgAAAA==.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAECgkJCwAAAA==.Rugiia:BAACLgAFFH8YAAIPAAYJYCR6AACJAgAPAAYJYCR6AACJAgAuAAQKfzgAAw8ACQmWJkMAAOMDAA8ACQmWJkMAAOMDAA0ABAlfJc8JAEkBAAAA.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAAALgAECgUJCgAAAA==.Ryuka:BAAALgAECgYJCgAAAA==.',
Sa='Samyria:BAAALgAECgIJAwAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8VAAQlAAgJAA9zGwAKAQAlAAcJKAxzGwAKAQAcAAQJEAb6WABqAAAKAAEJgAHymQAYAAAAAA==.Saucy:BAAALgAECgUJBQAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAVAAAAAA==.Scrubsauce:BAAALgAECgEJAgAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8VAAIkAAcJZA8pGABJAQAkAAcJZA8pGABJAQAAAA==.Seric:BAABLgAECn8dAAInAAcJuQuzEAAXAQAnAAcJuQuzEAAXAQAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgYJDQAVAAAAAA==.',
Sh='Shadowdancèr:BAAALgAECgYJCAAAAA==.Shadowlocke:BAAALgADCgYJDQAAAA==.Shanair:BAACLgAFFH8FAAIGAAIJzxumAwC7AAAGAAIJzxumAwC7AAAuAAQKfyoAAwYACQkvISgBANgCAAYACQkrICgBANgCAAcABwnWHfIaAE4CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAMJBgABALgHAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJAgAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAECgkJRgAnAJoeAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAAALgAECgYJEwAAAA==.',
Sl='Slambamwhoo:BAAALgADCgEJAgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8bAAIJAAgJgg11RwBYAQAJAAgJgg11RwBYAQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Solnar:BAAALgAECgYJEAAAAA==.',
Sp='Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAVAAAAAA==.Splashdaddy:BAABLgAECn8hAAIMAAgJUiSpAgD0AgAMAAgJUiSpAgD0AgABLgADCgYJBgAVAAAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgQJCQAAAA==.',
St='Staks:BAAALgADCgQJBAAAAA==.Starii:BAAALgAECgYJEAAAAA==.Stas:BAAALgADCgYJBgAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgADCgQJBAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAAALgAECgYJEgAAAA==.',
Ta='Taea:BAAALgADCgIJAgABLgAECgYJEgAVAAAAAA==.Taeus:BAABLgAECn8XAAIJAAgJFhjjXgAeAgAJAAgJFhjjXgAeAgAAAA==.Taladiir:BAAALgADCgMJAwAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8gAAInAAgJ2B4ICAClAgAnAAgJ2B4ICAClAgAAAA==.Tayblr:BAAALgAECgMJCgAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Temajin:BAAALgADCgcJFwAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJBwAAAA==.Teratrendera:BAAALgAECgUJDgAAAA==.Teron:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAAALgAECgcJDwAAAA==.Themyscira:BAAALgAECgEJAQAAAA==.Theonorf:BAABLgAECn8iAAIIAAgJpx78CQBdAgAIAAgJpx78CQBdAgAAAA==.Thetimelord:BAAALgAECgEJAQAAAA==.Thewarrior:BAAALgAECgUJBQAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8jAAICAAgJUhWtHwDLAQACAAgJUhWtHwDLAQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Torrey:BAABLgAECn8hAAIoAAgJLQ7nBwA1AQAoAAgJLQ7nBwA1AQAAAA==.',
Tr='Tradd:BAABLgAECn8YAAIbAAcJvCA2BQBqAgAbAAcJvCA2BQBqAgAAAA==.Tristyana:BAABLgAECn8lAAIIAAgJeBX4FQDiAQAIAAgJeBX4FQDiAQAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn8pAAMlAAgJZCNLAgC/AgAlAAgJZCNLAgC/AgAcAAcJgxY8IwCZAQAAAA==.',
Tw='Twinkletoe:BAAALgADCgYJBgABLgAECggJKQAlAGQjAA==.',
Ty='Tylurien:BAABLgAECn8WAAIZAAYJGiXDCABMAgAZAAYJGiXDCABMAgAAAA==.',
['Të']='Tëmpest:BAAALgADCgMJAgAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAAALgAECgYJEAAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valkoinen:BAABLgAECn8jAAIjAAUJlw82EAD5AAAjAAUJlw82EAD5AAAAAA==.Valora:BAABLgAECn8pAAMbAAgJixqmCAALAgAbAAgJpRimCAALAgAkAAYJ9xdVKwCbAQAAAA==.Valoria:BAAALgAECgQJCQAAAA==.Vanille:BAAALgAECgUJDgAAAA==.Vargen:BAAALgAECgYJEAAAAA==.Varonika:BAAALgAECgUJCgAAAA==.Vayla:BAABLgAECn8YAAInAAcJVRZSEgDjAQAnAAcJVRZSEgDjAQAAAA==.',
Ve='Vee:BAAALgAECgEJAQABLgAECggJEgAVAAAAAA==.Veld:BAAALgAECgcJBAAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJQAeALMcAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBAAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAAALgAECgUJEgAAAA==.',
Vo='Voidofdeath:BAAALgAECgQJCAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn8hAAIPAAgJDAPQOgDoAAAPAAgJDAPQOgDoAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAABLgAECn8hAAIJAAcJih4XIQDnAQAJAAcJih4XIQDnAQAAAA==.Wargrimm:BAABLgAECn8VAAIRAAYJTxvWEQCRAQARAAYJTxvWEQCRAQAAAA==.Warriovix:BAAALgAECgQJCwAAAA==.Warwizard:BAACLgAFFH8NAAIZAAMJ4yUHCwA/AQAZAAMJ4yUHCwA/AQAuAAQKfzwAAxkACQmeJhIAAPgDABkACQmeJhIAAPgDAAIABAm1DAJmAOUAAAAA.',
We='Webin:BAAALgAECgEJAwAAAA==.',
Wh='Whatshisface:BAABLgAECn8ZAAIlAAcJGB6AEQBtAgAlAAcJGB6AEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECggJGAAQAAwVAA==.Whiisper:BAAALgAECgYJBgABLgAECggJGAAQAAwVAA==.Whispaknight:BAAALgAECgUJBgABLgAECggJGAAQAAwVAA==.Whisperwiind:BAAALgAECgMJAwABLgAECggJGAAQAAwVAA==.Whisperz:BAAALgAECgIJAgABLgAECggJGAAQAAwVAA==.Whizpa:BAABLgAECn8YAAIQAAgJDBWBCwDXAQAQAAgJDBWBCwDXAQAAAA==.Whizper:BAAALgAECgEJAQABLgAECggJGAAQAAwVAA==.',
Wi='Wickerchickn:BAAALgAECgYJDwAAAA==.Wiisper:BAAALgADCgYJBgABLgAECggJGAAQAAwVAA==.Wizzy:BAAALgAECgQJCQAAAA==.',
Wr='Wrathbarrage:BAAALgAECgMJAwABLgAECgcJCAAVAAAAAA==.Wrathbourne:BAAALgAECgYJDQABLgAECgcJCAAVAAAAAA==.Wrathstorm:BAAALgAECgEJAgABLgAECgcJCAAVAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAAALgAECgYJEQAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgMJBAAVAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEAAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAAALgAECggJDgAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAVAAAAAA==.Zirfireballs:BAAALgADCgUJBQAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJDAAAAA==.',
Zu='Zurazaee:BAAALgAECgUJDgAAAA==.',
['År']='Årtêmis:BAAALgADCgEJAQAAAA==.',
['Él']='Élle:BAAALgAECgMJBQAAAA==.',
['Ér']='Éric:BAABLgAECn8oAAImAAgJ6RbHBADOAQAmAAgJ6RbHBADOAQAAAA==.',
['Ïr']='Ïridescent:BAAALgAECgIJAgAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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

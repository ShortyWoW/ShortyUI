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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Warrior-Arms','Shaman-Restoration','Druid-Restoration','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Paladin-Holy','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Priest-Shadow','Monk-Brewmaster','Evoker-Preservation','Mage-Frost','Priest-Holy','Monk-Windwalker','DeathKnight-Frost','Warrior-Protection','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Achooe:BAAALgAECgYJEAAAAA==.',
Ad='Adrel:BAAALgADCgEJAQAAAA==.Adversity:BAABLgAECn8jAAIBAAgJNiQ8CAAnAwABAAgJNiQ8CAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMCAAgJCxw3DQCPAgACAAgJ3Bo3DQCPAgADAAYJGhHIiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn8WAAQEAAYJ2wsSCQAWAQAEAAYJ9gkSCQAWAQAFAAUJtQazWwDUAAAGAAQJQgTUlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAAALgAECgYJEAAAAA==.',
Ai='Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECgYJEgAHAAAAAA==.Alexeika:BAAALgADCgkJCQAAAA==.Alistarz:BAABLgAECn8aAAMIAAcJbxuHBABVAQABAAYJbxtbMADtAQAIAAYJ0hCHBABVAQAAAA==.Allei:BAAALgADCgcJCgABLgAECggJHQAJAKQXAA==.Alyndrya:BAAALgAECgUJCgAAAA==.Alyndrys:BAAALgAECgcJEwAAAA==.',
Am='Amelialynne:BAABLgAECn8YAAIDAAYJRBKNHwANAQADAAYJRBKNHwANAQAAAA==.Amithralia:BAAALgAECgUJDAAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAAALgAECgUJDgAAAA==.Anhinga:BAAALgADCggJEwAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anissel:BAAALgAECggJEgAAAA==.Anzarna:BAAALgAECgQJBgAAAA==.',
Ao='Aohikari:BAAALgADCgUJBgABLgAFFAYJDgAKAGsXAA==.Aokuma:BAACLgAFFH8OAAIKAAYJaxeAAQAGAgAKAAYJaxeAAQAGAgAuAAQKfx0AAwoACAnjI5QGACIDAAoACAnjI5QGACIDAAsAAwlSIf9HAAwBAAAA.',
Ap='Aprigity:BAAALgAECgQJBwAAAA==.',
Aq='Aquaten:BAAALgAECgQJCQAAAA==.',
Ar='Arashinigon:BAAALgAECgYJDQAAAA==.Arceus:BAAALgAECgIJAgAAAA==.Archaon:BAAALgAECgUJDAAAAA==.Argoroth:BAABLgAECn8VAAIMAAYJeRnicACaAQAMAAYJeRnicACaAQAAAA==.Ariandise:BAAALgAECgMJAwAAAA==.Arick:BAAALgAECgYJEAAAAA==.Ark:BAABLgAECn8jAAMJAAgJlSb/AQBrAwAJAAgJlSb/AQBrAwANAAQJYyTIBgCcAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmódeus:BAAALgAECgYJDwAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJDgAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAAALgAECgUJBQAAAA==.',
['Aì']='Aìo:BAAALgAECgQJBQAAAA==.',
Ba='Baaku:BAAALgADCgMJAwAAAA==.Babyfists:BAAALgADCgMJAwABLgAECgQJCgAHAAAAAA==.Baelhay:BAAALgAECgQJCQAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJCwAAAA==.Belitha:BAABLgAECn8hAAIDAAgJjiAHEwDoAgADAAgJjiAHEwDoAgAAAA==.Belmaris:BAAALgAECgYJEAAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Berketta:BAAALgAECgYJDAAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJAgAAAA==.Bigcupcakes:BAAALgAECgQJBgAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAAALgAECgcJDAAAAA==.Bimbosuzi:BAAALgAECgQJCAAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.',
Bl='Blasteyes:BAAALgAECgUJCgAAAA==.Blegh:BAABLgAECn8bAAMOAAgJzxyfCgAxAgAOAAcJLxqfCgAxAgAPAAYJbBoaHwDKAQAAAA==.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn8hAAIQAAgJ1R0IAQAsAgAQAAgJ1R0IAQAsAgAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMRAAgJxQnVDwBAAQARAAgJxQnVDwBAAQAMAAYJpQqusAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAAALgAECgYJEgAAAA==.Bosco:BAAALgAECgMJBAAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAHAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buggers:BAAALgADCgYJBgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAAALgAECgEJAQAAAA==.',
Ca='Caiphage:BAABLgAECn8XAAIDAAcJAhdjFQBSAQADAAcJAhdjFQBSAQAAAA==.Caladelm:BAAALgAECgIJAgAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAAALgAECgUJCgAAAA==.Carlarae:BAAALgAECgQJCAAAAA==.Castelo:BAAALgAECgUJDgAAAA==.',
Ce='Cedra:BAAALgAECgUJBQAAAA==.Cegeo:BAABLgAECn8eAAISAAgJ4g7+AQCJAQASAAgJ4g7+AQCJAQAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Cheepdeeps:BAABLgAECn8hAAIBAAgJYhTRBwCkAQABAAgJYhTRBwCkAQAAAA==.Chocoworm:BAAALgADCgMJBAAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chupathingyy:BAABLgAECn8WAAMTAAYJ5x9qWQC7AQATAAUJyiBqWQC7AQAUAAQJSBj1EgD9AAAAAA==.',
Ci='Ciennajewel:BAAALgADCgYJBwAAAA==.Cirdle:BAAALgAECgYJDQAAAA==.Cirona:BAAALgAECgUJDAAAAA==.',
Cl='Clausewitz:BAAALgAECgYJDgAAAA==.Cloroxx:BAAALgAECgUJBQAAAA==.',
Co='Cobalt:BAAALgAECgYJCgAAAA==.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAHAAAAAA==.Coolkid:BAAALgAECgIJBQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8ZAAINAAgJVQKLFwC4AAANAAgJVQKLFwC4AAAAAA==.Creamyweamy:BAAALgAECgUJDwAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAAALgAECgYJDgAAAA==.Crucifixea:BAAALgADCgUJCgAAAA==.Cruzmaster:BAAALgAECgcJEAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAAALgAECgUJCgAAAA==.',
Cu='Cupp:BAAALgAECgQJBwAAAA==.Cute:BAAALgAECgYJCAABLgAFFAUJCgAVAO8PAA==.',
Da='Daddy:BAACLgAFFH8JAAIWAAMJaiVABwBMAQAWAAMJaiVABwBMAQAuAAQKf1oAAhYACQmcJgsAAAsEABYACQmcJgsAAAsEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Daggonet:BAAALgAECgEJAgAAAA==.Dalrin:BAABLgAECn8XAAMXAAYJ7A+iBgAcAQAXAAYJ7A+iBgAcAQANAAQJzAfXZwCjAAAAAA==.Darkcarnival:BAAALgAECgYJEAAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAABLgAECn8aAAIBAAcJhRdMLAADAgABAAcJhRdMLAADAgAAAA==.Darkphoenixx:BAAALgAECgEJAQAAAA==.Darthraider:BAAALgAECgQJCgAAAA==.Dasnotgood:BAAALgAECgUJCAAAAA==.Datoneshammy:BAAALgAECgMJBAAAAA==.Davrøs:BAAALgAECgIJBQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deeman:BAAALgAECgcJDAAAAA==.Deemon:BAAALgAECgcJEAAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAAALgAECgUJCgAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAAALgAECgYJCgAAAA==.Denidan:BAAALgADCgcJDAAAAA==.Dertus:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgUJCgAAAA==.Dethon:BAAALgADCgcJBwAAAA==.',
Di='Dianimal:BAAALgAECgEJAQAAAA==.Dings:BAAALgADCgcJCAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAAALgAECgYJCwAAAA==.',
Dk='Dklel:BAACLgAFFH8GAAIYAAMJuxr/IAAUAQAYAAMJuxr/IAAUAQAuAAQKfy4AAhgACAkFJc4CAIMCABgACAkFJc4CAIMCAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8WAAIMAAcJcRl2PwAoAgAMAAcJcRl2PwAoAgAAAA==.Doomfeather:BAAALgAECgEJAQAAAA==.Dorigog:BAABLgAECn8WAAIMAAgJERBQfACBAQAMAAgJERBQfACBAQAAAA==.',
Dr='Dragon:BAAALgAECgYJCwAAAA==.Dragonpunch:BAABLgAECn8WAAIWAAgJnBsRGQD2AQAWAAgJnBsRGQD2AQAAAA==.Driftyshaman:BAAALgAECgQJBgAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAAALgAECgQJBQAAAA==.',
Dw='Dworflundgrn:BAAALgAECgUJDAAAAA==.',
Dy='Dyamï:BAAALgAECgYJEAAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAAALgAECgQJBQAAAA==.',
El='Elbuhero:BAAALgAECgUJDAAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Ellä:BAAALgADCgkJCQAAAA==.Elrythe:BAABLgAECn8eAAIGAAgJFRs5GgBqAgAGAAgJFRs5GgBqAgAAAA==.Elviric:BAAALgADCgMJAwAAAA==.',
Et='Ethepally:BAAALgADCgEJAQAAAA==.',
Fa='Fallyynn:BAAALgAECgYJCgAAAA==.Fatalii:BAAALgADCgEJAQABLgAECgQJCgAHAAAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Felebash:BAAALgAECgQJCwAAAA==.',
Fi='Fistdaddy:BAAALgADCgYJBgAAAA==.',
Fl='Floofies:BAACLgAFFH8KAAIXAAQJ+g+pAABbAQAXAAQJ+g+pAABbAQAuAAQKfxsAAhcACAnTIbUDAO8CABcACAnTIbUDAO8CAAAA.Floofyfu:BAAALgAECgYJCgABLgAFFAQJCgAXAPoPAA==.',
Fr='Fredrickk:BAAALgAECgEJAQABLgAECgMJAwAHAAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgADCgQJBAAAAA==.Furryphase:BAACLgAFFH8HAAIJAAQJNg0PBQAcAQAJAAQJNg0PBQAcAQAuAAQKfxsAAgkACQnwGxANALUCAAkACQnwGxANALUCAAAA.Fuzzington:BAAALgADCgUJBQABLgAFFAQJCgAXAPoPAA==.Fuzzydunlop:BAAALgADCgkJJQAAAA==.',
Ga='Gaawdshammit:BAAALgAECgEJAQAAAA==.Gallin:BAAALgAECgEJAQAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJDAAAAA==.',
Gl='Glaur:BAABLgAECn8XAAIJAAYJFiBmIgARAgAJAAYJFiBmIgARAgAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgYJEQAHAAAAAA==.Gripisrdy:BAAALgAECgYJEAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAAALgAECgYJDwAAAA==.Guìdo:BAAALgADCgcJFwAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAAALgADCgcJBgAAAA==.Hairyjolene:BAAALgAECgQJCQAAAA==.Hammetrick:BAAALgADCgYJCQABLgAECggJGwAHAAAAAA==.Handsome:BAAALgADCgcJBwAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAITAAcJGh+lJQB8AgATAAcJGh+lJQB8AgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJCQAAAA==.Heycarlos:BAAALgAECgYJEAAAAA==.',
Hi='Hikaridh:BAAALgAFFAIJAgABLgAFFAYJDgAKAGsXAA==.Hikarimonk:BAAALgAECgEJAQABLgAFFAYJDgAKAGsXAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAYJDgAKAGsXAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgIJAgAHAAAAAA==.Holyblimblam:BAAALgADCgkJDQAAAA==.Hosemachine:BAABLgAECn8XAAMZAAcJhhWiHQBcAQAZAAYJxReiHQBcAQAYAAYJ2wYgvQAIAQAAAA==.Hotpants:BAAALgAECgYJEAAAAA==.',
Hu='Huckleberrie:BAAALgAECgUJDAAAAA==.Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBAAAAA==.',
Ic='Icyjackets:BAAALgAECgQJCQAAAA==.',
Id='Idouna:BAAALgADCgEJAQAAAA==.',
Il='Ilamuna:BAAALgADCgcJBwAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAAALgAECgYJDAAAAA==.Jameson:BAAALgAECgUJCgAAAA==.Jasmind:BAABLgAECn8aAAMKAAYJ8AgFdAD7AAAKAAYJ8AgFdAD7AAALAAEJLApBiAAnAAAAAA==.',
Je='Jellydonut:BAAALgADCgUJCQABLgAECgEJAQAHAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAAALgAECgQJBAAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgADCgUJBQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAAALgAECgYJDQAAAA==.Jiwâ:BAACLgAFFH8IAAIaAAMJgQZqBgDOAAAaAAMJgQZqBgDOAAAuAAQKfycAAhoABwkaIDwFAL8BABoABwkaIDwFAL8BAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECgUJDAAAAA==.Joss:BAAALgADCgcJAQAAAA==.',
Ka='Kadan:BAAALgADCgMJAwABLgAECggJIQADAI4gAA==.Kahless:BAAALgADCgIJAwAAAA==.Kakwaa:BAAALgAECgUJCgAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJAwAAAA==.Keyadistor:BAAALgAECgYJEQAAAA==.',
Kh='Khazabrew:BAABLgAECn8YAAIbAAYJEB01CAB0AQAbAAYJEB01CAB0AQAAAA==.',
Ki='Kiamara:BAAALgAECgUJCgAAAA==.Kinderlin:BAAALgAECgQJDAAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJCAAAAA==.',
Kr='Krelix:BAAALgAECgUJCgAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
La='Lancaban:BAAALgAECgMJAwAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQOAAgJfRaLDwDiAQAOAAYJNhmLDwDiAQAPAAMJfRRzQgDYAAAcAAQJlQqMMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.Lithena:BAAALgADCgQJBwAAAA==.',
Lo='Loadedtater:BAABLgAECn8cAAMGAAYJOiYgBQAmAgAGAAYJFSYgBQAmAgAFAAUJ3CWKJgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgADCgIJAgAAAA==.Lorianne:BAABLgAECn8dAAMJAAgJpBdjKQDpAQAJAAcJ3xZjKQDpAQANAAUJpguoVgDqAAAAAA==.Lorri:BAAALgADCgQJBAABLgAECggJHQAJAKQXAA==.',
Lu='Lucianas:BAAALgAECgYJBgAAAA==.Lunchböx:BAAALgAECgMJAwAAAA==.Lunico:BAAALgADCgEJAgAAAA==.',
Ly='Lysi:BAAALgAECgQJCQAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Madaea:BAABLgAECn8fAAIWAAgJuR24CwCYAgAWAAgJuR24CwCYAgAAAA==.Madrashai:BAAALgAECgUJCAAAAA==.Magepuppy:BAABLgAECn8YAAIdAAYJKhrEGQB6AQAdAAYJKhrEGQB6AQABLgAECgkJIgAEAMMfAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAAALgAECgYJCwAAAA==.Makavali:BAAALgADCgYJDAAAAA==.Malzeth:BAAALgADCgUJEgAAAA==.Marrina:BAAALgADCgMJAwAAAA==.Matagi:BAAALgAECgYJCAAAAA==.Mate:BAAALgADCgcJCQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgADCgYJBgAAAA==.Melbeast:BAAALgAECgUJCgAAAA==.Melorea:BAAALgADCgUJBQAAAA==.Merdin:BAAALgAECgYJDwAAAA==.Methmartion:BAAALgAECgQJCQAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mikewai:BAABLgAECn8XAAIDAAgJgQ9oUgCtAQADAAgJgQ9oUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgADCgEJAQAAAA==.Missiah:BAAALgAECgUJDAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moistwhispa:BAAALgAECgIJAgABLgAECgYJDAAHAAAAAA==.Molfise:BAAALgAECgUJDAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8eAAIeAAgJMRRDIgDSAQAeAAgJMRRDIgDSAQAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAAALgAECgUJCgAAAA==.Mopp:BAAALgADCgkJFAAAAA==.Morganthe:BAAALgAECgMJAgAAAA==.',
Mu='Mugatoo:BAAALgADCgMJAwAAAA==.Musubi:BAAALgADCgEJAQABLgAECgYJCwAHAAAAAA==.',
Mx='Mxtemlen:BAAALgADCgkJCQABLgAECgUJCgAHAAAAAA==.',
My='Mylilhunter:BAAALgAECgYJCQAAAA==.Mysticalmoo:BAAALgADCgUJDAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgYJBgABLgAECggJFgAWAJwbAA==.Myttus:BAEALgADCgMJAwABLgAECgQJCgAHAAAAAA==.',
['Mê']='Mêrlin:BAAALgAECgcJEQAAAA==.',
Na='Nachtelf:BAABLgAECn8hAAIGAAgJQxhuCQDRAQAGAAgJQxhuCQDRAQAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nannysham:BAAALgAECgYJDAAAAA==.Naomí:BAABLgAECn8cAAITAAYJ0wzXIwAKAQATAAYJ0wzXIwAKAQAAAA==.Natadawn:BAAALgAECgEJAQAAAA==.Natalone:BAABLgAECn8aAAIdAAgJvB5EDQDhAQAdAAgJvB5EDQDhAQAAAA==.Natherel:BAAALgAECgQJCQAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAAALgAECgMJAwAAAA==.',
Ne='Newander:BAAALgAECgcJEwAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgQJBAAAAA==.Nirra:BAAALgADCgcJDAAAAA==.',
No='Nonphatmilk:BAAALgAECgIJAgAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8cAAMYAAgJTRCNYwDJAQAYAAgJQBCNYwDJAQAZAAEJGxJ3RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8aAAIdAAYJ/h4vEwCoAQAdAAYJ/h4vEwCoAQAAAA==.',
Og='Ograskygazer:BAAALgAECgQJCQAAAA==.',
Om='Omee:BAAALgAECgUJCgAAAA==.Omy:BAAALgAECgYJEQAAAA==.',
Or='Oralena:BAAALgAECgQJCQAAAA==.Orioncheats:BAABLgAECn8YAAIYAAYJxxqoGQBIAQAYAAYJxxqoGQBIAQAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAHAAAAAA==.',
Pa='Pallygoboom:BAAALgADCgUJBQABLgAECgYJCgAHAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paull:BAAALgAECgMJBAAAAA==.',
Pe='Ped:BAABLgAECn8VAAMfAAYJSR0/GgAOAgAfAAYJSR0/GgAOAgAWAAEJ2AHodgAXAAAAAA==.',
Ph='Pharune:BAAALgAECgYJEAAAAA==.Philosofist:BAAALgAECgQJBwAAAA==.Phredrick:BAAALgAECgUJBwAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDQABLgAECgcJAgAHAAAAAA==.Picklebob:BAAALgAECgcJAgAAAA==.Pickleboe:BAAALgAECgUJBQABLgAECgcJAgAHAAAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.',
Pl='Plandemic:BAAALgAECgQJBQAAAA==.',
Po='Pockithealz:BAAALgAECgEJAQABLgAECgQJCgAHAAAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Pounce:BAAALgAECgcJCwAAAA==.',
Pr='Procalypse:BAABLgAECn8bAAMTAAgJERqnMwA+AgATAAgJWxinMwA+AgASAAMJ0xcXNgDeAAAAAA==.',
Pu='Puginator:BAAALgAECgMJAwABLgAECggJGwATABEaAA==.',
['Pä']='Pängari:BAAALgADCgYJBgAAAA==.',
Qu='Quattro:BAAALgAECgYJBgAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn8jAAMBAAYJrhluDwAzAQABAAYJIxluDwAzAQAIAAEJhBUBEgBHAAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAAALgAECgUJCgABLgAECgcJEwAHAAAAAA==.Rajantu:BAAALgADCgUJCQAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAAALgAECgQJBgAAAA==.',
Re='Rehum:BAEALgAECgQJCgAAAA==.Remagtrepxe:BAAALgADCgMJAwAAAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgADCgMJBgAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAAALgAECgYJDQAAAA==.Revèndreth:BAAALgADCgMJAwAAAA==.Rexbi:BAABLgAECn8bAAIDAAcJGRd+PQD+AQADAAcJGRd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgIJAgAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn8XAAIaAAYJ6wocEAD1AAAaAAYJ6wocEAD1AAAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAAALgAECgYJDAAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8VAAMYAAYJKBqwEwB1AQAYAAYJ8xawEwB1AQAgAAYJrhWuCABaAQAAAA==.Rolemartyr:BAAALgAECgQJBQAAAA==.Rooth:BAAALgAECgUJCQAAAA==.Roryn:BAABLgAECn8kAAIMAAgJmiEkBQBIAgAMAAgJmiEkBQBIAgAAAA==.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAECgkJCgAAAA==.Rugiia:BAACLgAFFH8SAAIKAAUJ4iRlAAAmAgAKAAUJ4iRlAAAmAgAuAAQKfy8AAwoACQmCJkIAAOMDAAoACQmCJkIAAOMDABAABAlSJb8RAJEBAAAA.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAAALgAECgUJCgAAAA==.Ryuka:BAAALgAECgUJBQAAAA==.',
Sa='Samyria:BAAALgAECgEJAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8UAAQfAAgJAA/uCwARAQAfAAcJKAzuCwARAQAWAAQJoARUWABuAAAbAAEJgAHpmQAYAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAHAAAAAA==.Scrubsauce:BAAALgAECgEJAgAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8UAAIeAAcJFg2VCwA7AQAeAAcJFg2VCwA7AQAAAA==.Seric:BAABLgAECn8WAAIhAAYJEQYfCwDMAAAhAAYJEQYfCwDMAAAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgYJCwAHAAAAAA==.',
Sh='Shadowdancèr:BAAALgAECgMJBAAAAA==.Shadowlocke:BAAALgADCgUJDAAAAA==.Shanair:BAABLgAECn8iAAMEAAkJwx/uAABvAgAEAAkJqh7uAABvAgAFAAcJ1h3vGgBOAgAAAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgADCgEJAQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAECgkJMgAhADcaAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAAALgAECgYJEAAAAA==.',
Sl='Slambamwhoo:BAAALgADCgEJAgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8UAAIdAAcJSAzTpgCLAQAdAAcJSAzTpgCLAQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Solnar:BAAALgAECgUJCgAAAA==.',
Sp='Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgADCggJEgAHAAAAAA==.Splashdaddy:BAABLgAECn8ZAAIJAAgJliF/BwD8AgAJAAgJliF/BwD8AgABLgADCgYJBgAHAAAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgQJCQAAAA==.',
St='Staks:BAAALgADCgQJBAAAAA==.Starii:BAAALgAECgUJCgAAAA==.Stas:BAAALgADCgYJBgAAAA==.Stevelock:BAAALgADCgcJDQAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgADCgQJBAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAAALgAECgUJDAAAAA==.',
Ta='Taea:BAAALgADCgIJAgABLgAECgUJDAAHAAAAAA==.Taeus:BAABLgAECn8XAAIdAAgJFhjsXgAeAgAdAAgJFhjsXgAeAgAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Taurenator:BAABLgAECn8fAAIhAAgJ2B4iAgAJAgAhAAgJ2B4iAgAJAgAAAA==.Tayblr:BAAALgAECgMJBgAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Temajin:BAAALgADCgcJEgAAAA==.Temple:BAAALgADCgIJAgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJBwAAAA==.Teratrendera:BAAALgAECgQJCQAAAA==.Teron:BAAALgAECgEJAQAAAA==.',
Th='Thavis:BAAALgAECgYJCwAAAA==.Themyscira:BAAALgAECgEJAQAAAA==.Theonorf:BAABLgAECn8dAAIGAAcJISBLCADkAQAGAAcJISBLCADkAQAAAA==.Thetimelord:BAAALgADCgYJCwAAAA==.Thypriest:BAAALgAECgYJDwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8cAAIMAAgJfRTADQC9AQAMAAgJfRTADQC9AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Torrey:BAABLgAECn8YAAIiAAYJ+BGPDwBYAQAiAAYJ+BGPDwBYAQAAAA==.',
Tr='Tradd:BAAALgAECgYJEQAAAA==.Tristyana:BAABLgAECn8dAAIGAAgJihOsCgC/AQAGAAgJihOsCgC/AQAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn8hAAMfAAgJtyIeAQB5AgAfAAgJtyIeAQB5AgAWAAcJgxYiIwCcAQAAAA==.',
Tw='Twinkletoe:BAAALgADCgYJBgABLgAECggJIQAfALciAA==.',
Ty='Tylurien:BAAALgAECgYJEAAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAAALgAECgUJCgAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valkoinen:BAABLgAECn8UAAIcAAQJSQqUNQDAAAAcAAQJSQqUNQDAAAAAAA==.Valora:BAABLgAECn8hAAMVAAgJSBrVFQD2AQAVAAgJ2hfVFQD2AQAeAAYJ9xdUKwCbAQAAAA==.Valoria:BAAALgAECgQJCQAAAA==.Vanille:BAAALgAECgQJCQAAAA==.Vargen:BAAALgAECgUJCgAAAA==.Varonika:BAAALgAECgQJBQAAAA==.Vayla:BAAALgAECgcJEwAAAA==.',
Ve='Veld:BAAALgAECgYJAgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECgcJFwAZAIYVAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBAAAAA==.',
Vi='Violet:BAAALgAECgUJDQAAAA==.',
Vo='Voidofdeath:BAAALgAECgIJAgAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn8YAAIKAAYJ6gKlIACwAAAKAAYJ6gKlIACwAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAABLgAECn8hAAIdAAcJih48CwD6AQAdAAcJih48CwD6AQAAAA==.Wargrimm:BAAALgAECgYJDwAAAA==.Warriovix:BAAALgAECgQJCAAAAA==.Warwizard:BAACLgAFFH8KAAIRAAMJFiMJCwAtAQARAAMJFiMJCwAtAQAuAAQKfzMAAxEACQmeJhIAAPgDABEACQmeJhIAAPgDAAwABAnJCQ4vAOAAAAAA.',
We='Webin:BAAALgAECgEJAwAAAA==.',
Wh='Whatshisface:BAABLgAECn8ZAAIfAAcJGB5+EQBtAgAfAAcJGB5+EQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgYJDAAHAAAAAA==.Whiisper:BAAALgAECgYJBgABLgAECgYJDAAHAAAAAA==.Whispaknight:BAAALgAECgUJBgABLgAECgYJDAAHAAAAAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgYJDAAHAAAAAA==.Whizpa:BAAALgAECgYJDAAAAA==.Whizper:BAAALgADCgMJAwABLgAECgYJDAAHAAAAAA==.',
Wi='Wickerchickn:BAAALgAECgUJCQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgYJDAAHAAAAAA==.Wizzy:BAAALgAECgQJCQAAAA==.',
Wr='Wrathbarrage:BAAALgAECgMJAwABLgAECgYJDQAHAAAAAA==.Wrathbourne:BAAALgAECgYJDQAAAA==.Wrathstorm:BAAALgAECgEJAQABLgAECgYJDQAHAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJBwAAAA==.',
Xi='Xiangfei:BAAALgAECgUJDAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.',
Yo='Youmightlive:BAAALgAECgQJCAAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgUJCAAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAAALgAECgcJDAAAAA==.',
Zi='Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAHAAAAAA==.Zirfireballs:BAAALgADCgUJBQAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJDAAAAA==.',
Zu='Zurazaee:BAAALgAECgQJCQAAAA==.',
['Él']='Élle:BAAALgAECgMJAwAAAA==.',
['Ér']='Éric:BAABLgAECn8gAAIjAAgJUhMvAwB8AQAjAAgJUhMvAwB8AQAAAA==.',
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

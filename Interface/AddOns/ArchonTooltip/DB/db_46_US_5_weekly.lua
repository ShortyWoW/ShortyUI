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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Paladin-Retribution','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Druid-Restoration','Mage-Frost','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Priest-Discipline','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Monk-Windwalker','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Warrior-Fury','Evoker-Preservation','Priest-Shadow','Druid-Feral','Shaman-Elemental','Rogue-Outlaw','Druid-Balance','Hunter-Survival','Warrior-Arms','DemonHunter-Havoc','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Accost:BAAALgAECgQJBAAAAA==.',
Ad='Adagar:BAAALgAECgYJCwAAAA==.Adesha:BAAALgADCgYJBgAAAA==.',
Ae='Aeloria:BAAALgAECgcJBgAAAA==.Aeratedlol:BAAALgAFFAIJAwABLgAFFAQJBwABAIAXAA==.Aethandor:BAAALgAECgQJCAAAAA==.',
Ak='Akassa:BAAALgAECgYJEwAAAA==.Aknologia:BAAALgADCgYJBgABLgAECgMJAwACAAAAAA==.',
Al='Alaric:BAAALgADCgUJBQAAAA==.Alecto:BAABLgAECn8XAAIDAAgJlAvJTwBXAQADAAgJlAvJTwBXAQAAAA==.Alune:BAAALgADCgYJDAAAAA==.',
Am='Amarah:BAACLgAFFH8HAAIEAAMJsRBwEADPAAAEAAMJsRBwEADPAAAuAAQKfzgAAgQACQm5GpwIAGQCAAQACQm5GpwIAGQCAAAA.',
An='Andron:BAAALgADCgIJAgAAAA==.Andy:BAAALgADCgcJBwAAAA==.Angryjames:BAAALgADCgYJCgAAAA==.Animehero:BAAALgAECgIJAwABLgAECgkJFQAFAJEcAA==.',
Ap='Applemonster:BAAALgAECgcJBwAAAA==.',
Ar='Arboghast:BAAALgAECgUJCAAAAA==.Argdru:BAAALgAECgYJDQAAAA==.Arglock:BAAALgADCgIJAgABLgAECgYJDQACAAAAAA==.Argrekd:BAAALgADCgMJAwABLgAECgYJDQACAAAAAA==.Aridol:BAAALgADCgUJBAAAAA==.Arigön:BAAALgADCgMJAwAAAA==.Arima:BAAALgAECgEJAQAAAA==.Arknox:BAABLgAECn8ZAAIGAAgJSQ72HACgAQAGAAgJSQ72HACgAQAAAA==.Arthaslk:BAAALgAECgcJCAABLgAECgYJDAACAAAAAA==.',
As='Aserus:BAAALgAECgcJCwABLgAFFAUJEwAHAGUeAA==.Ashallel:BAAALgAECgQJBAABLgAFFAUJEwAHAGUeAA==.Ashx:BAAALgADCgIJBAABLgAECgkJIAAIAKUXAA==.Astralock:BAAALgAECgEJAQAAAA==.',
At='Atlette:BAACLgAFFH8NAAIEAAQJNBxzBwBMAQAEAAQJNBxzBwBMAQAuAAQKfygAAgQACQluH2MCAEUDAAQACQluH2MCAEUDAAAA.Atrocitusz:BAAALgAECgIJAgAAAA==.Atroxx:BAACLgAFFH8MAAIBAAQJ0w24HgAjAQABAAQJ0w24HgAjAQAuAAQKf0UAAgEACAnZI8kQABcDAAEACAnZI8kQABcDAAEuAAUUBQkdAAkA+xcA.Attman:BAABLgAFFH8GAAIKAAQJ6RQDEgAyAQAKAAQJ6RQDEgAyAQAAAA==.',
Au='Auradawn:BAAALgAECgQJEgAAAA==.',
Ay='Ayaya:BAAALgADCgQJBAABLgAECgYJEAACAAAAAA==.',
Ba='Baetrayer:BAAALgAECgcJCAAAAA==.Bailz:BAAALgADCgMJAwAAAA==.Balimund:BAAALgAECgEJAQAAAA==.Ballerstatus:BAAALgAECgMJAwAAAA==.Ballsofaith:BAAALgADCgkJFAAAAA==.Ballsofire:BAABLgAECn8hAAILAAcJchuUCQDaAQALAAcJchuUCQDaAQAAAA==.Basherz:BAAALgAECgQJBQAAAA==.',
Be='Bearmane:BAAALgAECgYJBgAAAA==.Beedoc:BAAALgADCgEJAQAAAA==.Behindithu:BAABLgAECn8XAAMMAAYJJAp+DgDMAAAMAAQJiQt+DgDMAAANAAYJ5wXMJgDCAAAAAA==.Belithel:BAABLgAECn8gAAIIAAkJpRdUQACmAQAIAAkJpRdUQACmAQAAAA==.Bencreepin:BAAALgAECgYJDwAAAA==.Beniz:BAABLgAECn8VAAMOAAcJ9AjyXQAWAQAOAAcJQwjyXQAWAQAPAAIJBQm9WgBeAAAAAA==.Bernoulli:BAABLgAECn8aAAIQAAcJ/huEEwDDAQAQAAcJ/huEEwDDAQAAAA==.',
Bi='Bigblunts:BAAALgADCgEJAgAAAA==.Bigcrunch:BAAALgAECggJCQAAAA==.Bignative:BAAALgAECgYJCAAAAA==.',
Bl='Bloodboo:BAAALgAECgQJBAAAAA==.Bloodyhpally:BAAALgAFFAIJAgABLgAFFAgJIgAQAKwcAA==.Bloodymyst:BAABLgAFFH8iAAIQAAgJrBx1AADhAgAQAAgJrBx1AADhAgAAAA==.Blumpy:BAAALgADCggJCAAAAA==.',
Bo='Boethius:BAAALgADCgYJBgABLgAECgYJCwACAAAAAA==.Boopsnoopems:BAAALgAECgYJEwAAAA==.Borderline:BAAALgADCgYJBgABLgAFFAMJCAARACgPAA==.',
Br='Briannajade:BAABLgAECn8dAAIIAAgJrQirZQBGAQAIAAgJrQirZQBGAQAAAA==.Brisha:BAACLgAFFH8YAAIGAAUJ4yGdBgC0AQAGAAUJ4yGdBgC0AQAuAAQKfzMAAwYACQk9JHQAALUDAAYACQk9JHQAALUDABIAAQkaEo8vADsAAAAA.Brodan:BAAALgAECgQJBAAAAA==.Brokenhealz:BAAALgAECgIJAgAAAA==.',
Bs='Bs:BAAALgAECgYJBgABLgAFFAMJBgABAL8RAA==.',
Bu='Bubble:BAAALgADCgEJAgAAAA==.Bubblehash:BAAALgADCgEJAQAAAA==.Bubbletarded:BAAALgAECgUJBgAAAA==.Bustah:BAABLgAECn8eAAMTAAgJex24DgDFAgATAAgJex24DgDFAgAUAAYJag3nTwAPAQABLgAFFAMJBgABAL8RAA==.',
Ca='Cacaco:BAAALgADCgIJAgAAAA==.Cactuscooler:BAAALgADCgcJBwAAAA==.Caffrey:BAABLgAECn8ZAAIHAAkJ1yKzAQCJAwAHAAkJ1yKzAQCJAwAAAA==.Cammi:BAAALgAECgYJDwAAAA==.Cammywammy:BAAALgADCgcJBwAAAA==.Casare:BAABLgAECn8bAAIUAAYJJglAFAC4AAAUAAYJJglAFAC4AAAAAA==.Catjam:BAAALgAECgMJAwABLgAFFAgJIwAVAG0iAA==.',
Ce='Celarc:BAAALgAECgYJDwAAAA==.Celithe:BAAALgAECgcJCQABLgAECggJJgAIAPIVAA==.Celyda:BAAALgADCgcJBwAAAA==.',
Ch='Chapito:BAAALgAECgcJCAAAAA==.Chipmonked:BAABLgAECn8oAAQFAAgJLwvaIAAxAQAFAAgJygjaIAAxAQAWAAYJOwqsJwDyAAAQAAUJIwPGUACQAAAAAA==.Chlop:BAABLgAECn8ZAAIBAAgJahxrHADUAgABAAgJahxrHADUAgAAAA==.Chunkers:BAAALgAECgQJBAAAAA==.Chuubar:BAAALgADCgYJCwAAAA==.',
Ci='Cinderzin:BAABLgAECn8pAAIXAAgJFAm8BgBWAQAXAAgJFAm8BgBWAQAAAA==.',
Cl='Clawhalla:BAAALgAECgQJBAAAAA==.',
Cn='Cnorthover:BAAALgAECgQJBAAAAA==.',
Co='Cobrallig:BAAALgAECgYJCAAAAA==.Colexn:BAAALgAECgQJBAAAAA==.Comfyboi:BAAALgAECgYJCwAAAA==.Congdh:BAACLgAFFH8TAAIYAAUJPSNKCAChAQAYAAUJPSNKCAChAQAuAAQKfx4AAhgACAm8JJ8MABsDABgACAm8JJ8MABsDAAAA.Conmann:BAAALgAECgYJEAAAAA==.Corg:BAAALgADCgUJBQAAAA==.Cornchipz:BAAALgAECgMJAwAAAA==.Cowmage:BAAALgAECgEJAQAAAA==.',
Cr='Crit:BAAALgADCgcJCAAAAA==.Crossy:BAAALgAECgQJBQAAAA==.Cryogenic:BAAALgAECgYJCQAAAA==.Cryptex:BAAALgADCgEJAQAAAA==.',
Cy='Cyrus:BAAALgADCgQJBAAAAA==.',
Cz='Czznkj:BAAALgADCgkJDgAAAA==.',
['Cá']='Cálívént:BAAALgAECgQJAwAAAA==.',
Da='Daak:BAAALgADCgcJEAABLgAECgcJGwAFAAUIAA==.Dabberoni:BAAALgAECgcJAQAAAA==.Daelin:BAAALgAECgEJAQAAAA==.Dankkush:BAABLgAECn8YAAIBAAkJqB7eGQAwAgABAAkJqB7eGQAwAgAAAA==.Darkacedia:BAABLgAECn8jAAMOAAgJIB+qFgAtAgAOAAgJIB+qFgAtAgAPAAMJyQ9YQwCoAAAAAA==.Darkrubie:BAAALgADCgMJAwAAAA==.Datbish:BAAALgADCgkJBgAAAA==.Dawgis:BAAALgAECgEJAQAAAA==.',
Db='Dbznz:BAAALgADCgYJBwAAAA==.',
De='Deadcell:BAABLgAECn8UAAIBAAcJNCFZFwBBAgABAAcJNCFZFwBBAgAAAA==.Deadcells:BAAALgAECgQJBgABLgAECgcJFAABADQhAA==.Deadharvest:BAAALgAECgYJBwAAAA==.Deadlift:BAAALgAECgQJCQAAAA==.Dealosed:BAACLgAFFH8HAAMMAAQJ4Q0CBAAKAQAMAAMJZxICBAAKAQANAAQJ0wcTDwD/AAAuAAQKfyUAAwwACQlBIQkCAFgCAA0ABwnOIMgRAJECAAwABglDIgkCAFgCAAAA.Decrepit:BAABLgAECn8cAAIBAAgJqhqqGAA4AgABAAgJqhqqGAA4AgAAAA==.Defect:BAAALgAECgQJBAAAAA==.Demonclawz:BAAALgAECgcJDAAAAA==.Demonscar:BAAALgAECgUJCwAAAA==.Dex:BAAALgAECgEJAQAAAA==.',
Dh='Dhaeverdh:BAAALgADCgIJAgAAAA==.',
Di='Diddious:BAAALgADCgMJAgAAAA==.Diremane:BAAALgAECgIJAgAAAA==.Disastacast:BAAALgAECgMJAwABLgAECgcJFAAZAKoVAA==.Disastasmite:BAAALgADCgEJAQABLgAECgcJFAAZAKoVAA==.Dive:BAABLgAECn8jAAMIAAkJDSLnJgDXAgAIAAgJjCHnJgDXAgAaAAUJbRx6CwAfAQAAAA==.',
Dk='Dkeruu:BAAALgAECgUJCAAAAA==.',
Do='Doinks:BAABLgAECn8VAAIFAAkJkRwyDgCxAgAFAAkJkRwyDgCxAgAAAA==.Dondozo:BAAALgAECgUJCwAAAA==.Doogru:BAABLgAECn8lAAIbAAkJrBPYDAAeAgAbAAkJrBPYDAAeAgAAAA==.Doufu:BAAALgAECgQJBAABLgAECgYJDAACAAAAAA==.',
Dr='Dracomaibois:BAAALgAECgYJCgAAAA==.Dragoneggs:BAACLgAFFH8JAAMVAAMJcxl/HQD9AAAVAAMJcxl/HQD9AAAcAAMJqQklFADKAAAuAAQKfyEAAxUACQnYHuoIAOoCABUACQnYHuoIAOoCABwABwkZDmMfAIQBAAAA.Dragonforce:BAAALgAECgYJDAABLgAECggJDwACAAAAAA==.Draxan:BAAALgADCgcJCAAAAA==.Draxx:BAAALgAECgcJDgAAAA==.Dreammachine:BAABLgAECn8vAAIdAAkJzCPyAABFAwAdAAkJzCPyAABFAwAAAA==.Driipp:BAAALgAECgkJEAAAAA==.Drizs:BAAALgADCgEJAQAAAA==.Drjoel:BAAALgADCgYJCAAAAA==.Drunkenutz:BAABLgAECn8UAAMQAAYJYxWVNQAZAQAQAAUJxxKVNQAZAQAFAAYJpw3FKQD8AAAAAA==.',
Du='Duane:BAAALgADCgEJAQABLgAFFAMJCAARACgPAA==.',
Dy='Dyab:BAAALgAECgEJAQAAAA==.',
['Dä']='Dälf:BAABLgAECn8cAAMeAAcJnCFkCwAKAgAeAAYJbiNkCwAKAgAHAAYJKxDZWABIAQABLgAFFAgJHAAVAMAYAA==.',
Ec='Echidona:BAABLgAECn8bAAINAAgJERn7EwB2AgANAAgJERn7EwB2AgAAAA==.',
Ed='Edirii:BAAALgADCgEJAQAAAA==.',
Ee='Eelsky:BAAALgAECgcJEgAAAA==.',
Ef='Efvoidhunter:BAAALgAECgUJBQAAAA==.',
Ek='Eksi:BAEALgAECgQJBAABLgAFFAUJEwAOAIMjAA==.',
El='Elenix:BAABLgAECn8aAAMfAAkJyRyyCAAGAwAfAAkJyRyyCAAGAwAKAAMJhA3tgACQAAABLgAECggJFgAGAAklAA==.Elinras:BAACLgAFFH8FAAIDAAIJYAUbTgCPAAADAAIJYAUbTgCPAAAuAAQKfxQAAgMACAnfDttrAKYBAAMACAnfDttrAKYBAAAA.Elliott:BAAALgADCgMJBQABLgADCggJDQACAAAAAA==.Elrizon:BAAALgAECgIJAQAAAA==.Elvar:BAAALgAECgcJDAABLgAECgQJBQACAAAAAA==.Elynith:BAAALgAECgIJBAAAAA==.Elynni:BAABLgAECn8dAAIEAAcJ2RUFIADhAQAEAAcJ2RUFIADhAQAAAA==.',
Em='Emmylou:BAAALgAECgEJAwAAAA==.Emotett:BAAALgADCgQJBAAAAA==.Emz:BAABLgAECn8jAAIgAAgJqyHlAAAMAwAgAAgJqyHlAAAMAwAAAA==.',
En='Endboss:BAAALgAECgUJBQAAAA==.Endorsi:BAABLgAFFH8GAAIMAAQJpQ98AgBbAQAMAAQJpQ98AgBbAQAAAA==.Enfuega:BAAALgAECgQJCwAAAA==.Eniar:BAACLgAFFH8LAAIGAAUJUAaVDgBFAQAGAAUJUAaVDgBFAQAuAAQKfxQAAwYACAlSErcuAMgBAAYACAlSErcuAMgBAAMABAl0CSvvALIAAAAA.',
Er='Eroninja:BAAALgAECgQJCAABLgAECgkJIAAIAKUXAA==.',
Eu='Eurong:BAACLgAFFH8NAAIhAAQJxhgyDgBAAQAhAAQJxhgyDgBAAQAuAAQKfxsAAiEACAlvH0caADMCACEACAlvH0caADMCAAAA.',
Ev='Evangelune:BAAALgAECgYJDAAAAA==.',
Ew='Ewright:BAAALgAECgEJAQABLgAECgYJCgACAAAAAA==.',
Ez='Ezynuff:BAAALgAECgYJCwAAAA==.',
['Eï']='Eïr:BAAALgADCgcJCAAAAA==.',
Fa='Fakie:BAAALgAECgQJBAABLgAECgYJFAAOAB8fAA==.Fapple:BAAALgAECgQJBwABLgAECggJHwAcAGUgAA==.Fatesprocket:BAAALgAECgMJBQAAAA==.Faïry:BAACLgAFFH8IAAMTAAQJdxXZKQDyAAATAAMJrBPZKQDyAAAiAAMJTwvkEQDUAAAuAAQKfy0AAxMACQnhG8oRAKoCABMACAkpHsoRAKoCACIABgkUCjQjALYAAAAA.',
Fe='Feardih:BAAALgADCgIJAgAAAA==.Felheart:BAAALgAECgYJBwAAAA==.Feltnutz:BAAALgADCgQJBQABLgAECgYJFAAQAGMVAA==.Felwyrm:BAAALgAECgYJCAABLgAFFAMJCAARACgPAA==.Femboi:BAAALgADCgUJBQAAAA==.Fengshui:BAAALgAECgMJCAAAAA==.Feralle:BAAALgADCgQJBAAAAA==.',
Fl='Flacidmon:BAAALgAECgMJAwAAAA==.Flutterina:BAAALgAECgIJAgAAAA==.Flyjin:BAABLgAECn8dAAMcAAgJCg5nJABVAQAcAAcJJQxnJABVAQAVAAgJIQ4cHgBOAQAAAA==.Flylo:BAAALgADCgMJAwAAAA==.',
Fo='Folandras:BAAALgADCgcJDAABLgAECgcJIQALAHIbAA==.',
Fr='Fries:BAECLgAFFH8GAAIOAAQJog+ILwAOAQAOAAQJog+ILwAOAQAuAAQKfx4AAw4ACAkCJBYGAOICAA4ACAkCJBYGAOICAA8AAQmHGhRgAE8AAAAA.Frozenpyre:BAAALgAECgYJEQAAAA==.',
Fu='Funch:BAACLgAFFH8GAAIPAAMJdgU5BgC7AAAPAAMJdgU5BgC7AAAuAAQKfysAAg8ACAmDGMQCABICAA8ACAmDGMQCABICAAAA.',
['Fè']='Fènrir:BAAALgAECgEJAQABLgAECgYJCgACAAAAAA==.',
Ga='Gabbathegoo:BAAALgAECgkJDgAAAA==.Gainzbrew:BAAALgAECgEJAgAAAA==.Gainzz:BAAALgAECgQJBgAAAA==.Galesdeyn:BAAALgAECgUJCgAAAA==.Garl:BAAALgAECgUJBQABLgAECgcJFAAIAD4dAA==.Garonnaa:BAAALgAFFAIJBAAAAA==.',
Gh='Ghari:BAABLgAECn8eAAIBAAgJ5hIYOwCOAQABAAgJ5hIYOwCOAQAAAA==.',
Gi='Gilrog:BAABLgAECn8VAAIBAAUJLxAZeQDvAAABAAUJLxAZeQDvAAAAAA==.Gingerlock:BAAALgAECgUJBgAAAA==.',
Gl='Gladiusmax:BAAALgADCgQJBAAAAA==.',
Gn='Gnoblin:BAAALgAECgQJCAAAAA==.Gnz:BAAALgAECgIJAQAAAA==.Gnzz:BAAALgAECgcJDAAAAA==.',
Go='Gonz:BAAALgADCgcJBwAAAA==.',
Gr='Gravys:BAAALgAECgcJAwAAAA==.Greka:BAAALgAECgYJEgAAAA==.Greylooms:BAABLgAECn8jAAMjAAkJKB6CAQDcAgAjAAkJVB2CAQDcAgAbAAYJhB3mMgDgAQAAAA==.Gruuith:BAAALgADCgEJAQAAAA==.',
Gw='Gwath:BAAALgAECgEJAQAAAA==.',
Gy='Gynaris:BAAALgAECgMJBQAAAA==.',
['Gâ']='Gâinzz:BAAALgADCgQJBAAAAA==.',
Ha='Hakun:BAAALgAECgMJAwAAAA==.Happyfriend:BAACLgAFFH8IAAMRAAMJKA/lGADdAAARAAMJKA/lGADdAAAdAAEJZAAmIwA4AAAuAAQKfyUAAxEACAnMFZgQAMsBABEACAnMFZgQAMsBAB0ABwmiEXskALQBAAAA.Haruko:BAAALgADCgQJBAAAAA==.',
He='Heemski:BAAALgAECgMJAwAAAA==.Hellbourne:BAAALgADCggJDQAAAA==.Hellbrick:BAAALgADCgMJAwAAAA==.Hermitpurple:BAAALgADCgcJEwAAAA==.Heàl:BAAALgAECgYJCgAAAA==.',
Hi='Hidejames:BAAALgAECgMJBAAAAA==.Hims:BAAALgAECgYJEwABLgAFFAgJIwAVAG0iAA==.',
Ho='Hoguy:BAAALgAECgYJEAAAAA==.Holofox:BAACLgAFFH8XAAIHAAUJOR41BwDFAQAHAAUJOR41BwDFAQAuAAQKfzUAAwcACAkwJvkBAHIDAAcACAkwJvkBAHIDAB4AAQkmBrgrACoAAAAA.Holycrow:BAAALgAECgMJAwAAAA==.Holytotem:BAAALgADCgEJAQAAAA==.Horman:BAAALgAECgYJEwAAAA==.',
Hu='Hunterishard:BAAALgAECggJEAABLgAECgkJCgACAAAAAA==.',
Hy='Hylda:BAAALgAECgMJBgAAAA==.',
['Hï']='Hïru:BAAALgAECgYJCAAAAA==.',
['Hô']='Hôlÿ:BAAALgAECgQJCQABLgAECgYJDQACAAAAAA==.',
Ic='Iclapu:BAAALgAECgEJAQAAAA==.',
Ig='Igosduikanna:BAAALgADCgQJBQAAAA==.',
Ik='Ikerous:BAABLgAECn8bAAMZAAgJrBkwBwAWAgAZAAgJrBkwBwAWAgAkAAMJ1AmPVgCNAAAAAA==.',
Il='Ilililililli:BAABLgAECn8aAAMQAAgJ9BYuJgCBAQAQAAgJ9BYuJgCBAQAWAAIJdgifRwBhAAAAAA==.',
Im='Imadwagon:BAAALgADCgkJCAAAAA==.Imapandairl:BAABLgAECn8VAAIfAAcJrR6AEgCOAgAfAAcJrR6AEgCOAgAAAA==.Imhammered:BAABLgAECn8UAAIGAAYJcg+SLwAZAQAGAAYJcg+SLwAZAQAAAA==.Impullse:BAAALgAECgQJBwAAAA==.',
Ir='Ironpally:BAAALgAECgYJBwAAAA==.Irsty:BAAALgAECgEJAQABLgAECgYJCwACAAAAAA==.',
It='Ithilwen:BAABLgAECn8iAAIRAAgJux4cDQBnAgARAAgJux4cDQBnAgAAAA==.Itiswhatitiz:BAAALgAECgYJEQAAAA==.Itsybityshiv:BAABLgAECn8qAAMNAAkJkBfDBQBcAgANAAkJkBfDBQBcAgAMAAEJoBjxHwAzAAAAAA==.',
Iw='Iwillpull:BAAALgADCgcJDgAAAA==.',
Iz='Izzlirkkgazp:BAAALgAECgcJDgAAAA==.',
Ja='Jackiefox:BAAALgAECgIJAwAAAA==.Jahq:BAABLgAECn8VAAIYAAYJAyFzNAAnAgAYAAYJAyFzNAAnAgAAAA==.Jambs:BAAALgADCgEJAQAAAA==.Jaysontatum:BAAALgADCgEJAQAAAA==.',
Jh='Jhani:BAABLgAECn8XAAIIAAcJqgQagwALAQAIAAcJqgQagwALAQAAAA==.',
Ji='Jinu:BAAALgAECgYJDQAAAA==.Jixn:BAAALgAECgMJBQAAAA==.',
Jo='Joethemage:BAABLgAECn8tAAIIAAkJAxyXCwDFAgAIAAkJAxyXCwDFAgAAAA==.Jormojo:BAAALgAECgQJBQAAAA==.Jotwnky:BAABLgAECn8eAAQlAAcJAyC3BQAMAgAlAAUJSSO3BQAMAgAPAAQJsxo3IwA+AQAOAAMJFR9JuADoAAAAAA==.Jotwnkyy:BAABLgAECn8bAAINAAcJ6hLtFQBbAQANAAcJ6hLtFQBbAQABLgAECgcJHgAlAAMgAA==.',
Ju='Jungol:BAAALgADCgkJDgAAAA==.',
Ka='Kaela:BAAALgAECgEJAQAAAA==.Kaikova:BAAALgADCgcJCgAAAA==.Kaltank:BAAALgAECgMJAwAAAA==.Kamin:BAABLgAECn8jAAILAAgJwiHhAwARAwALAAgJwiHhAwARAwAAAA==.Karoka:BAAALgADCgEJAQAAAA==.Kasitos:BAAALgAFFAMJAwAAAA==.Katamaran:BAAALgAECgUJBQABLgAFFAQJDQAdAPwMAA==.Kaykaypally:BAABLgAECn8cAAIDAAgJcBOBLwC+AQADAAgJcBOBLwC+AQAAAA==.',
Ke='Keis:BAEALgAECgYJBgABLgAFFAUJEwAOAIMjAA==.Keledron:BAAALgADCgcJCgAAAA==.Kellan:BAABLgAECn8kAAIDAAcJkxhtPQCOAQADAAcJkxhtPQCOAQAAAA==.Kelos:BAAALgAECgYJCAABLgAFFAEJAgACAAAAAA==.Kenwith:BAAALgADCgYJBgAAAA==.Keylethel:BAAALgADCgEJAQAAAA==.',
Ki='Kideki:BAABLgAECn8kAAIGAAkJ5yFHAwAOAwAGAAkJ5yFHAwAOAwAAAA==.Kidori:BAAALgAECgEJAQABLgAECgkJJAAGAOchAA==.Kilgharra:BAAALgADCgcJDgAAAA==.Kinji:BAAALgADCgYJCAABLgAECgkJIAAIAKUXAA==.Kirisute:BAAALgAECgEJAQAAAA==.',
Ko='Kolsch:BAAALgADCgQJBAAAAA==.Koriandar:BAAALgAECgcJEQAAAA==.Koyama:BAAALgADCgcJBwAAAA==.',
Kr='Kristysavage:BAABLgAECn8lAAIiAAYJlSG5DADZAQAiAAYJlSG5DADZAQAAAA==.Krul:BAAALgADCgkJCgAAAA==.Kruya:BAAALgAECgMJBAABLgAECgYJEQACAAAAAA==.',
Ku='Kulaesca:BAAALgADCgkJDgAAAA==.',
Ky='Kynar:BAACLgAFFH8WAAMBAAcJqhu1AwARAgABAAYJqhu1AwARAgAmAAEJAABlEQBnAAAuAAQKfxcAAgEACAkuH6Y/ADoCAAEACAkuH6Y/ADoCAAAA.Kyperion:BAAALgAECgYJDQAAAA==.Kyua:BAAALgAECgYJEgAAAA==.',
La='Lambshot:BAAALgAECgYJEgAAAA==.Lambsy:BAACLgAFFH8kAAQbAAgJhBZsAAAaAgAbAAcJ/xdsAAAaAgAjAAEJXgWsGQBMAAALAAEJpAhgGABHAAAuAAQKfxsAAxsACAmnIA0RAMgCABsACAl1Hg0RAMgCACMAAQnuIz45AEsAAAAA.Landwhalexxl:BAABLgAECn8WAAIIAAcJ9BGGpACPAQAIAAcJ9BGGpACPAQAAAA==.Laneera:BAAALgAECgQJDAAAAA==.',
Le='Ledronys:BAAALgADCgEJAQAAAA==.Ledsole:BAAALgADCgEJAQAAAA==.Lerat:BAABLgAECn8qAAIXAAgJdiIMAQChAgAXAAgJdiIMAQChAgAAAA==.',
Li='Lichkali:BAAALgADCgMJAwAAAA==.Lightofhope:BAAALgAECggJEgAAAA==.Lihandra:BAAALgAECgMJAwAAAA==.Lillipup:BAAALgAECgQJBAAAAA==.Lillyy:BAAALgAECgIJAgABLgAECgcJFQAIAKUaAA==.Lilyy:BAABLgAECn8VAAIIAAcJpRo/kgCuAQAIAAcJpRo/kgCuAQAAAA==.Liria:BAAALgAECgYJDQAAAA==.Lisanalgaib:BAABLgAECn8XAAIDAAYJKBxVOgCXAQADAAYJKBxVOgCXAQAAAA==.Liulei:BAAALgAECgQJAwAAAA==.Lizzimcguire:BAAALgAECgQJBAAAAA==.',
Lo='Loharfal:BAAALgADCgEJAQAAAA==.Lokî:BAAALgAECgQJBAAAAA==.Loraen:BAAALgAECgYJCwAAAA==.Lorelei:BAAALgAECgEJAQABLgAECgkJJAAjAA4bAA==.Lostep:BAAALgAECgEJAQABLgAFFAcJGAAKAHYKAA==.Lowkeyjz:BAAALgADCgIJAgAAAA==.',
Lu='Luasa:BAAALgADCgIJAgAAAA==.Lukadoncic:BAAALgAECgYJBwABLgADCgEJAQACAAAAAA==.Lunarmon:BAAALgAECgQJCgAAAA==.Lunchable:BAABLgAECn8eAAIfAAgJnBmFFgBlAgAfAAgJnBmFFgBlAgAAAA==.Luxmalleo:BAAALgADCgkJDwABLgAECgYJEQACAAAAAA==.',
Ly='Lykho:BAAALgAECgEJAQAAAA==.',
['Lé']='Léblanc:BAABLgAECn8kAAIIAAgJEx0jMADgAQAIAAgJEx0jMADgAQAAAA==.',
Ma='Madam:BAAALgADCgMJBwAAAA==.Madday:BAAALgADCgcJDAAAAA==.Maelorus:BAAALgADCgkJEQAAAA==.Mahli:BAAALgAECgEJAQAAAA==.Makah:BAAALgAECgMJAwAAAA==.Makaroni:BAAALgADCgcJBwAAAA==.Makizenin:BAAALgADCgYJCAAAAA==.Malenia:BAAALgADCgUJBwAAAA==.Malthezar:BAAALgADCgEJAQAAAA==.Manticus:BAAALgADCgYJEAAAAA==.Mari:BAAALgAECgMJBQABLgAFFAMJBwAEALEQAA==.Matroxx:BAAALgAECgcJEgABLgAFFAUJHQAJAPsXAA==.',
Me='Meat:BAAALgAECgUJBQAAAA==.Meatballz:BAAALgADCgEJAQAAAA==.Meatbeef:BAAALgADCgEJAQAAAA==.Meenoi:BAACLgAFFH8GAAIBAAMJvxEDTwDxAAABAAMJvxEDTwDxAAAuAAQKfysAAgEACAnPIfUSAGQCAAEACAnPIfUSAGQCAAAA.Melysia:BAACLgAFFH8TAAIHAAUJZR4HBwDIAQAHAAUJZR4HBwDIAQAuAAQKfzEAAwcACQnOH/0MANQCAAcACQnOH/0MANQCAB4AAgmmCRAhAFUAAAAA.Metalgear:BAAALgADCgYJDAAAAA==.',
Mi='Midgeyfam:BAAALgAECgIJAgAAAA==.Midgeyzen:BAAALgAECgQJBAAAAA==.Mindi:BAAALgAECgMJAwAAAA==.Mizakina:BAAALgADCgYJCwAAAA==.Mizby:BAAALgADCgIJAwABLgADCgMJAwACAAAAAA==.Mizry:BAAALgADCgMJAwAAAA==.',
Mo='Moardotsnow:BAABLgAECn8oAAMOAAkJ4SSJGQAXAgAOAAUJ9iSJGQAXAgAPAAQJvSRuCQBAAQAAAA==.Moby:BAAALgAECgUJCwAAAA==.Moistmender:BAAALgAECgYJCwAAAA==.Monktyson:BAABLgAFFH8IAAIQAAQJSA8SEgAKAQAQAAQJSA8SEgAKAQAAAA==.Mortui:BAAALgADCgQJBgABLgAFFAUJHQAJAPsXAA==.Mous:BAAALgADCgMJAwAAAA==.',
Mu='Muffasah:BAAALgAECgEJAQAAAA==.Munchkinn:BAAALgADCgYJBgAAAA==.Murbella:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.Murridan:BAABLgAECn8gAAIYAAkJxSGVCQA7AwAYAAkJxSGVCQA7AwAAAA==.',
My='Mykaela:BAAALgAECgIJAgAAAA==.Myraela:BAAALgAECgQJBAABLgAECgcJFwAmACwgAA==.',
['Më']='Mëow:BAAALgAECgUJCwAAAA==.',
Na='Narrath:BAAALgAECgMJBQAAAA==.Nayalaah:BAAALgAECgIJAgAAAA==.',
Ne='Nellybearwl:BAAALgADCgYJBgAAAA==.Nerfherder:BAAALgAECgEJAQAAAA==.Nexes:BAAALgADCgcJEgAAAA==.',
Ni='Nicotinee:BAAALgAECgMJAwAAAA==.Nightbané:BAAALgAECgIJAwAAAA==.Nirina:BAAALgAECgYJEwAAAA==.Nixie:BAAALgAECgYJBQAAAA==.',
No='Nojaw:BAAALgADCgcJBwAAAA==.Noraeri:BAAALgAECgYJBgABLgAECgkJIAAIAKUXAA==.Notdicey:BAAALgADCggJCQABLgAFFAQJCAAVAEkXAA==.Novo:BAAALgAECgYJCwAAAA==.',
Nu='Nukefury:BAABLgAECn8aAAIfAAYJZyRvGgBAAgAfAAYJZyRvGgBAAgABLgAECgcJFAAZAKoVAA==.',
Nw='Nwalliance:BAAALgADCgIJAgAAAA==.',
Od='Oddstriker:BAAALgADCgYJAwAAAA==.',
Ol='Oliveoil:BAAALgADCgEJAQAAAA==.',
Om='Omnidh:BAACLgAFFH8PAAIYAAQJehZ1GwA8AQAYAAQJehZ1GwA8AQAuAAQKfx4AAhgACQmzH60PAAEDABgACQmzH60PAAEDAAAA.Omnihead:BAAALgADCgYJBgAAAA==.',
On='Onepavo:BAAALgAECgEJAQAAAA==.',
Op='Oppose:BAAALgAECgYJDAAAAA==.',
Or='Orestes:BAAALgAFFAEJAQAAAA==.Orexion:BAAALgADCgcJBgAAAA==.Ormagöden:BAABLgAECn8oAAInAAkJJxSLAwBPAgAnAAkJJxSLAwBPAgAAAA==.',
Oz='Ozzpoxzo:BAAALgADCgcJCwAAAA==.',
Pa='Palladean:BAABLgAECn8eAAIDAAcJnBFiRwBvAQADAAcJnBFiRwBvAQAAAA==.Pandemic:BAAALgAECgMJAwAAAA==.Parabow:BAAALgAECgMJAwAAAA==.Parador:BAAALgAECgIJAQABLgAECgMJAwACAAAAAA==.Pastasauce:BAABLgAECn8VAAIDAAcJEAuchwBrAQADAAcJEAuchwBrAQAAAA==.',
Pc='Pcpmlsd:BAAALgADCgkJDAAAAA==.',
Pe='Penelohpe:BAAALgAECgcJCgABLgAECggJIwALAMIhAA==.Penwork:BAAALgAECgcJBgAAAA==.Penz:BAAALgADCgkJBgAAAA==.Perrian:BAAALgADCgMJBAAAAA==.',
Ph='Phamine:BAAALgAECgMJAwAAAA==.Philex:BAEALgAECgIJAgABLgAFFAUJEwAOAIMjAA==.Phoon:BAECLgAFFH8TAAIOAAUJgyP6CQCiAQAOAAUJgyP6CQCiAQAuAAQKfxsABA4ACAl7HUEdAKYCAA4ACAl7HUEdAKYCAA8AAglGGVFJAJIAACUAAQkAAJ8qAEoAAAAA.Phøenixbane:BAAALgAECgYJEgAAAA==.',
Pi='Pita:BAAALgAECgcJCwAAAA==.Pitaya:BAAALgAECgYJCQAAAA==.',
Pl='Plaguefist:BAAALgAECggJDwAAAA==.Plata:BAAALgAECgQJBQAAAA==.Plikxy:BAAALgADCgkJCQAAAA==.',
Po='Pocketmage:BAAALgAECgQJBQAAAA==.',
Pr='Premonitions:BAABLgAECn8fAAIKAAgJUBSNHADNAQAKAAgJUBSNHADNAQAAAA==.Premune:BAABLgAECn84AAQGAAkJ6h+aBQDLAgAGAAkJ6h+aBQDLAgASAAgJ8xDeDABsAQADAAIJOgioGwFjAAAAAA==.Prion:BAACLgAFFH8IAAIYAAMJNwvINwDUAAAYAAMJNwvINwDUAAAuAAQKfxQAAhgACAnnEuwlAKcBABgACAnnEuwlAKcBAAAA.',
Ps='Psycs:BAAALgAECgYJCwAAAA==.',
Pu='Pulga:BAAALgADCgIJAgAAAA==.Pull:BAAALgADCgcJCQABLgAECgkJIwAIAA0iAA==.Purplemage:BAAALgAECgkJCgAAAA==.',
Pw='Pwincess:BAAALgADCgMJAwAAAA==.',
Qu='Quigly:BAAALgAECgYJCgAAAA==.Quìts:BAABLgAECn8mAAMOAAgJPx3tHAADAgAOAAgJoxvtHAADAgAPAAMJzxc8FgCcAAAAAA==.Quíts:BAAALgADCgEJAQABLgAECggJJgAOAD8dAA==.',
Ra='Rainbowdots:BAAALgAECgcJDgAAAA==.Raine:BAACLgAFFH8YAAIKAAcJdgrgAwDgAQAKAAcJdgrgAwDgAQAuAAQKfxYAAwoACAkLHy0fACQCAAoACAkLHy0fACQCAB8ABAkKGWJVAPAAAAAA.Raistlin:BAABLgAECn8eAAMkAAgJ3xaxCwDHAQAkAAgJ3xaxCwDHAQAYAAEJywOc8AAiAAAAAA==.Ralfio:BAABLgAECn8fAAIcAAgJZSDjAwCCAgAcAAgJZSDjAwCCAgAAAA==.Ralfiosky:BAAALgAECgcJBwABLgAECggJHwAcAGUgAA==.Ramennoodlez:BAAALgADCggJDgAAAA==.Rat:BAAALgAFFAIJAgAAAA==.Ratren:BAAALgADCgQJAwAAAA==.Ravalyn:BAAALgADCgkJCgAAAA==.Raynith:BAABLgAECn8dAAQeAAcJ7B+5CgAaAgAeAAcJ1x+5CgAaAgAoAAcJxxKDDABIAQAhAAEJAADIgQAvAAAAAA==.',
Re='Readycheck:BAAALgAECgcJDAAAAA==.Reckalossi:BAAALgAECgkJAQABLgAFFAIJBQADAGAFAA==.Redcows:BAAALgADCggJFAAAAA==.Redeemed:BAAALgADCgEJAQAAAA==.Reikon:BAABLgAECn8iAAIDAAgJzB2mHAAcAgADAAgJzB2mHAAcAgAAAA==.Remulous:BAAALgAECgYJEwAAAA==.Revelaen:BAACLgAFFH8IAAIVAAQJCA7VFgAsAQAVAAQJCA7VFgAsAQAuAAQKfyMAAxUACQluHQwJAOcCABUACQluHQwJAOcCABcABQlYBoMoANwAAAAA.',
Ri='Rick:BAACLgAFFH8PAAMTAAQJSSJSBQCSAQATAAQJSSJSBQCSAQAUAAEJXBr/JABUAAAuAAQKfykAAxMACAnPI+kJAJgCABQACAlpI9sJAAUDABMACAm2H+kJAJgCAAAA.Rickers:BAAALgAECgMJAwABLgAFFAQJDwATAEkiAA==.',
Ro='Roarz:BAAALgADCgkJCQAAAA==.Rollthebones:BAAALgADCgMJAwAAAA==.Roman:BAABLgAECn8XAAMGAAYJZyWcCgBnAgAGAAYJZyWcCgBnAgADAAQJnRkyrQAoAQABLgAFFAQJCQAcAKAlAA==.Roust:BAAALgAECgUJBQABLgAECgkJIwAIAA0iAA==.',
Ru='Runinfear:BAAALgADCgYJBgAAAA==.',
Sa='Saephora:BAABLgAECn8WAAIIAAYJSASjqgC/AAAIAAYJSASjqgC/AAAAAA==.Saerea:BAABLgAECn8gAAIBAAgJKx8LGgAuAgABAAgJKx8LGgAuAgAAAA==.Sahhm:BAAALgAECgQJDAAAAA==.Salali:BAAALgAECgQJBwAAAA==.Samael:BAAALgAECgMJBgABLgAFFAQJBgAMAKUPAA==.Sammel:BAABLgAECn8ZAAMdAAgJ9BhSFABOAgAdAAgJ9BhSFABOAgARAAEJCxGaRgAyAAAAAA==.Sandmanslim:BAAALgAECgUJBQAAAA==.Sathreina:BAABLgAECn8mAAIDAAgJ1RdEJQDtAQADAAgJ1RdEJQDtAQAAAA==.Sawbones:BAAALgADCggJCQAAAA==.',
Sc='Scaries:BAABLgAECn8XAAIFAAkJKhtpEgCAAgAFAAkJKhtpEgCAAgAAAA==.Scootzmcgee:BAAALgAECgUJCQAAAA==.',
Se='Sekii:BAEALgAECgQJBAABLgAFFAUJEwAOAIMjAA==.Sekimaru:BAACLgAFFH8IAAINAAQJ+QcRDwAzAQANAAQJ+QcRDwAzAQAuAAQKfyoAAw0ACQllFGMKAPkBAA0ACQllFGMKAPkBAAwAAQmmB5AbADIAAAAA.Selok:BAAALgAFFAEJAgAAAA==.',
Sh='Shaddik:BAAALgAECgQJBgABLgAECggJEAACAAAAAA==.Shadowisbad:BAAALgAECgkJEwAAAA==.Shadpriest:BAAALgAECggJEAAAAA==.Shaeledoran:BAACLgAFFH8FAAIBAAMJYA18WgDNAAABAAMJYA18WgDNAAAuAAQKfzgAAgEACQnWHwkUAFoCAAEACQnWHwkUAFoCAAAA.Shamaneggs:BAAALgAECgMJAwAAAA==.Shamatroxx:BAACLgAFFH8dAAIJAAUJ+xeVAgBYAQAJAAUJ+xeVAgBYAQAuAAQKfycAAgkACQk/GYEFAPgBAAkACQk/GYEFAPgBAAAA.Shampomaster:BAAALgADCgMJAwAAAA==.Shieetz:BAAALgAECgYJEAAAAA==.Shlomie:BAAALgADCggJFQAAAA==.Shlomiel:BAAALgADCgEJAQAAAA==.Shlomieo:BAAALgADCgkJFwAAAA==.Shocknasty:BAAALgADCgMJAwAAAA==.Shorttemper:BAAALgADCgkJDQAAAA==.Shänk:BAAALgAECgYJEQAAAA==.',
Si='Sibirica:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgYJDAAAAA==.Silith:BAAALgAECgQJBQAAAA==.Silre:BAAALgAECgYJCgAAAA==.Silverfangg:BAAALgADCgkJEQAAAA==.Sinergy:BAABLgAECn8UAAIOAAYJHx8sRAD/AQAOAAYJHx8sRAD/AQAAAA==.Siz:BAAALgAECgYJCAAAAA==.',
Sk='Skiddlebutt:BAAALgADCgMJAgAAAA==.Skirmish:BAAALgAECgIJAQAAAA==.Skyray:BAAALgADCgUJBQAAAA==.',
Sl='Slappeepries:BAAALgADCgEJAQABLgAECgkJCgACAAAAAA==.Slappeey:BAAALgAECggJCgABLgAECgkJCgACAAAAAA==.',
Sn='Snapbean:BAAALgADCgEJAQAAAA==.Snarls:BAAALgAECgIJAgABLgAECggJHwAcAGUgAA==.Snaxx:BAAALgAECgEJAwABLgAECgYJCwACAAAAAA==.Snorunt:BAAALgAECgYJEAAAAA==.Snuudle:BAACLgAFFH8OAAMBAAMJVSCxPAAbAQABAAMJVSCxPAAbAQAnAAEJsBXaCABSAAAuAAQKf0AAAwEACQmdJIkDADEDAAEACQlLJIkDADEDACcABQmUJDMEALEBAAAA.',
So='Solokills:BAAALgAECgcJDwAAAA==.Soulreaperqt:BAAALgAECgMJAwABLgAECgUJCwACAAAAAA==.Soundtrack:BAAALgADCgEJAQAAAA==.',
Sp='Spaceman:BAAALgAECgQJBwABLgAFFAMJCAARACgPAA==.',
Sq='Sqlpal:BAABLgAECn8cAAMYAAcJpx6vLwA9AgAYAAcJpx6vLwA9AgAkAAQJOB75PgAAAQAAAA==.Squirrels:BAABLgAECn8bAAMFAAcJBQgiJgARAQAFAAcJBQgiJgARAQAQAAQJuwXnUgCGAAAAAA==.Squirtstorm:BAABLgAECn8jAAIKAAgJTiHIBADxAgAKAAgJTiHIBADxAgAAAA==.Squirtz:BAAALgADCgUJBAAAAA==.',
Sr='Srgntsnoop:BAAALgADCgUJBQAAAA==.',
St='Stabmywood:BAABLgAECn8sAAMNAAkJvSGFAQAEAwANAAkJvSGFAQAEAwAgAAEJNxZbEQBEAAAAAA==.Sthella:BAAALgADCgMJAwABLgAECgUJDQACAAAAAA==.Stompy:BAAALgADCgkJEAABLgAFFAQJDQAdAPwMAA==.Storienn:BAAALgAECgYJCwAAAA==.Stormßlessed:BAAALgADCgUJBQAAAA==.Strokemyhorn:BAAALgAECgQJBQAAAA==.',
Su='Suküna:BAACLgAFFH8HAAIYAAMJTRMlMgDoAAAYAAMJTRMlMgDoAAAuAAQKfygAAhgACAlWICYZAL0CABgACAlWICYZAL0CAAAA.Sunglo:BAAALgADCgYJBgAAAA==.Surefire:BAAALgAECgEJAQAAAA==.',
Sw='Swaption:BAABLgAECn8kAAIKAAgJ4SQgDAC/AgAKAAgJ4SQgDAC/AgAAAA==.Swolebane:BAAALgADCgUJBQAAAA==.',
Sy='Sybaü:BAAALgAECgYJDAAAAA==.Synchronize:BAABLgAECn8YAAIBAAcJOBSnUQBHAQABAAcJOBSnUQBHAQAAAA==.Syrelia:BAABLgAECn8mAAIIAAgJ8hVtMgDXAQAIAAgJ8hVtMgDXAQAAAA==.',
Ta='Takèda:BAABLgAECn8TAAIiAAYJdhz1FABsAQAiAAYJdhz1FABsAQAAAA==.Taldain:BAAALgAECgMJBQAAAA==.Talonstrykz:BAAALgAECggJEQAAAA==.Tankdeesnuts:BAABLgAECn8fAAILAAYJWgcfIgCtAAALAAYJWgcfIgCtAAAAAA==.Tashalle:BAAALgAECgEJAQABLgAECggJIgARALseAA==.Tauloe:BAAALgAECgYJEAAAAA==.Tayna:BAAALgADCgkJBgAAAA==.',
Te='Teejaydh:BAAALgADCgEJAQAAAA==.Tellamon:BAABLgAECn8aAAIDAAgJqBPANgCjAQADAAgJqBPANgCjAQAAAA==.Tetanus:BAAALgAECgQJBwABLgAECgYJEAACAAAAAA==.Teyassha:BAAALgAECgEJAgAAAA==.',
Th='Thomo:BAABLgAECn8YAAMTAAcJSwfjTAAnAQATAAcJ3AbjTAAnAQAiAAYJ2gSgHAAMAQAAAA==.Throatfist:BAAALgAFFAIJBAABLgAFFAUJEwAYAD0jAA==.Throme:BAAALgADCgEJAQAAAA==.Thunk:BAACLgAFFH8JAAIfAAMJPRfQDQAQAQAfAAMJPRfQDQAQAQAuAAQKfyEAAh8ACQl6JfUDAGADAB8ACQl6JfUDAGADAAAA.',
Ti='Timdawg:BAAALgAECgMJAwABLgAECgUJEwACAAAAAA==.',
Tj='Tjkrollsaway:BAAALgAECgIJAgAAAA==.',
To='Tomotostein:BAABLgAECn8mAAIDAAkJ8RqcGAA2AgADAAkJ8RqcGAA2AgAAAA==.Tonobaggins:BAAALgADCggJCAAAAA==.Toothluss:BAAALgADCgMJAgAAAA==.Totemnutz:BAAALgAECgEJAQABLgAECgYJFAAQAGMVAA==.',
Tr='Tradrael:BAAALgADCgcJBwAAAA==.Tristîtia:BAAALgAFFAEJAQAAAA==.',
Ts='Tsume:BAAALgAECgYJEgAAAA==.',
Tu='Tumlek:BAAALgAECgIJAgAAAA==.Tunobuffpapi:BAAALgAFFAIJAgAAAA==.',
Ty='Tyrinn:BAAALgAECggJDAAAAA==.Tyv:BAABLgAECn8rAAMaAAkJshS5AQAHAgAaAAgJVBa5AQAHAgAIAAUJiQaNqQDBAAAAAA==.',
Ur='Urä:BAAALgAECgIJAgAAAA==.',
Va='Vainatetosix:BAAALgAECgQJCAAAAA==.Valindra:BAAALgAECgUJCQAAAA==.Vallodon:BAABLgAECn8hAAIIAAkJ6CCrFAB0AgAIAAkJ6CCrFAB0AgAAAA==.Valyndra:BAAALgAECgYJCAAAAA==.Vampÿ:BAAALgAECgYJCQABLgAFFAQJCAATAHcVAA==.Vanquizsher:BAAALgAECgIJAgAAAA==.Vanwolfy:BAABLgAECn8UAAILAAYJTwg0HgDLAAALAAYJTwg0HgDLAAAAAA==.',
Ve='Velanthris:BAAALgAECgMJBQABLgAECgYJCAACAAAAAA==.Velectran:BAABLgAECn8aAAIDAAcJhRKYYAAtAQADAAcJhRKYYAAtAQABLgAECggJJgAIAPIVAA==.',
Vi='Vilgehkfrúna:BAAALgAECgEJAQAAAA==.Virdreth:BAAALgAECgEJAQAAAA==.Vish:BAAALgAECgUJBgAAAA==.',
Vo='Vortash:BAAALgADCgcJCAAAAA==.',
Vy='Vynle:BAAALgAECgQJBgAAAA==.Vyrthos:BAAALgADCgkJCQABLgAFFAMJCAAIABMDAA==.',
Wa='Warheimer:BAAALgAECgEJAQAAAA==.Warrgodx:BAAALgAECgYJDAAAAA==.Wartroxx:BAAALgADCgkJCAABLgAFFAUJHQAJAPsXAA==.',
We='Wengja:BAABLgAECn8gAAQQAAcJryUJBwDqAgAQAAcJryUJBwDqAgAFAAEJ9QSUjgAnAAAWAAEJAACeiQAlAAAAAA==.',
Wh='Wheri:BAAALgADCggJCAABLgAECgkJJAAjAA4bAA==.Whoknows:BAAALgAECgYJCQAAAA==.',
Wo='Wolfchef:BAAALgAECgYJDAAAAA==.Woodkin:BAAALgAECgUJEQAAAA==.',
Wr='Wrongwookie:BAABLgAECn8iAAIfAAkJwx2lCAAHAwAfAAkJwx2lCAAHAwAAAA==.',
Wy='Wyrmbreaker:BAAALgAECgMJBgAAAA==.',
Xi='Xiak:BAAALgADCgYJBgABLgAECgcJHQAeAOwfAA==.',
Ya='Yako:BAAALgAECgIJAgAAAA==.',
Ye='Yereka:BAAALgADCgQJBAAAAA==.',
Yi='Yinshai:BAABLgAECn8WAAMKAAgJnhdaFwD3AQAKAAgJnhdaFwD3AQAfAAEJxwIecAAkAAAAAA==.',
Yo='Yoomesbonds:BAAALgAFFAEJAQAAAA==.Youtube:BAACLgAFFH8jAAMVAAgJbSJSAADyAgAVAAgJbSJSAADyAgAXAAMJayGJAwAlAQAuAAQKfx8AAxcACQknJVQDAOoCABcABwmsJVQDAOoCABUABAlsH0MoAHsBAAAA.Yoyohunty:BAAALgAECgEJAgAAAA==.Yozki:BAABLgAECn8cAAIIAAcJ3yDwKQD6AQAIAAcJ3yDwKQD6AQAAAA==.',
Yu='Yuuki:BAAALgAECgEJAQABLgAFFAQJBgAMAKUPAA==.Yuulia:BAABLgAECn8kAAMjAAkJDhujAgCUAgAjAAkJnxqjAgCUAgALAAYJeRhrGQCGAQAAAA==.',
Za='Zabada:BAAALgADCgkJHwAAAA==.Zaee:BAAALgAECgIJAwABLgAECgkJFAAKADQTAA==.Zariee:BAAALgAECgMJBQAAAA==.',
Ze='Zemsen:BAACLgAFFH8IAAIIAAMJEwP9MQDgAAAIAAMJEwP9MQDgAAAuAAQKfzAAAwgACQmdGOI8AIQCAAgACQmdGOI8AIQCABoAAgneBb4ZAEoAAAAA.Zenyea:BAAALgAECgQJBAABLgAFFAQJDQAdAPwMAA==.Zetta:BAACLgAFFH8NAAIdAAQJ/AwWDQA5AQAdAAQJ/AwWDQA5AQAuAAQKfycAAh0ACQlYH+gMALUCAB0ACQlYH+gMALUCAAAA.',
Zo='Zoktavir:BAAALgADCgEJAQAAAA==.Zoltan:BAABLgAECn8VAAIIAAYJnQvT2QA9AQAIAAYJnQvT2QA9AQAAAA==.Zorin:BAAALgADCgcJDgAAAA==.',
Zy='Zyndrael:BAABLgAECn8cAAIDAAgJuhpEGwAlAgADAAgJuhpEGwAlAgAAAA==.',
['Zâ']='Zâgs:BAAALgADCgYJCAAAAA==.',
['Êl']='Êlytz:BAAALgAECggJEAAAAA==.',
['ßl']='ßlue:BAABLgAECn9CAAMFAAgJSR9qCABFAgAFAAgJSR9qCABFAgAQAAMJnBt1LADuAAAAAA==.',
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

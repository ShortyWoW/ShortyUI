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

local lookup = {'Warrior-Fury','Warrior-Arms','Paladin-Retribution','Druid-Restoration','Unknown-Unknown','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DemonHunter-Devourer','Druid-Guardian','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Unholy','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Evoker-Augmentation','Priest-Shadow','Warrior-Protection','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Actionfigure:BAABLgAECn8jAAMBAAgJcSHTBQCWAgABAAgJcSHTBQCWAgACAAEJ7AYwRwAoAAAAAA==.',
Ad='Adessa:BAAALgAECgQJBgAAAA==.Adgavery:BAABLgAECn8ZAAIDAAgJmg6BPwCHAQADAAgJmg6BPwCHAQAAAA==.Adielia:BAABLgAECn8VAAIEAAYJDx1tLwDuAQAEAAYJDx1tLwDuAQAAAA==.',
Ae='Aeskir:BAAALgAECgcJAQAAAA==.',
Ak='Akaim:BAAALgADCgIJAgAAAA==.Aksa:BAAALgAFFAEJAQAAAA==.',
Al='Alantharia:BAAALgADCgMJAwABLgAECgUJCQAFAAAAAA==.Alexious:BAACLgAFFH8LAAIGAAQJqR+KAQBaAQAGAAQJqR+KAQBaAQAuAAQKfyQAAgYACAlWIkEDAOwCAAYACAlWIkEDAOwCAAAA.Alkapwnn:BAAALgAECgUJDAAAAA==.Aloefox:BAAALgADCgkJKQAAAA==.Alofyxe:BAABLgAECn8bAAIHAAgJfhkvIADbAQAHAAgJfhkvIADbAQAAAA==.Altagravee:BAAALgADCgQJBAAAAA==.Altffour:BAABLgAFFH8NAAIIAAMJwAOyGACnAAAIAAMJwAOyGACnAAAAAA==.Alulla:BAACLgAFFH8QAAIBAAQJgho1CABfAQABAAQJgho1CABfAQAuAAQKfxsAAgEACAnHIMwWAJYCAAEACAnHIMwWAJYCAAAA.Alunira:BAABLgAECn8xAAMJAAkJmRxoEwB3AgAJAAkJmRxoEwB3AgADAAcJ+BQ8QACFAQAAAA==.',
Am='Amberrfrost:BAAALgAECgYJDwAAAA==.Amberveil:BAAALgADCgYJBgAAAA==.Amex:BAAALgAECgEJAQAAAA==.',
An='Andark:BAAALgAECgMJAwAAAA==.Angryhtr:BAAALgAECgQJBQAAAA==.',
Ap='Aphox:BAABLgAECn8lAAQKAAgJwBlyIgDkAQAKAAgJAhVyIgDkAQALAAQJsxnJCgDgAAAMAAMJLBNCGgBwAAAAAA==.Apokalypto:BAAALgAECgYJCAAAAA==.',
Ar='Arachnida:BAAALgADCgYJBgAAAA==.Arairi:BAAALgAECgQJBAABLgAECgYJEQAFAAAAAA==.Aravera:BAAALgAECgMJAwAAAA==.Araxes:BAAALgAECgMJBwAAAA==.Arcanefox:BAAALgAECgYJDwAAAA==.Arcåedeå:BAAALgADCgYJBgAAAA==.Ardelan:BAAALgADCgMJAwAAAA==.Ardå:BAAALgAECgYJAQAAAA==.Arîse:BAAALgADCgUJCAAAAA==.',
As='Ashgold:BAAALgAECgEJAQAAAA==.Ashoggal:BAAALgADCgQJBgAAAA==.Ashyl:BAAALgAECgEJAQAAAA==.Aslunay:BAABLgAECn8dAAIDAAYJLQufcAAMAQADAAYJLQufcAAMAQAAAA==.Assine:BAAALgADCgIJAgABLgAECgcJBgAFAAAAAA==.Astanis:BAAALgAECgYJEAAAAA==.Asteriia:BAABLgAECn8eAAINAAgJHQ8nMgBtAQANAAgJHQ8nMgBtAQAAAA==.',
At='Athhena:BAAALgADCgQJBgAAAA==.Atomskdmn:BAAALgADCgEJAQAAAA==.',
Au='Augustino:BAAALgAECgIJAgAAAA==.',
Av='Avraelia:BAAALgAECgYJCwAAAA==.',
Aw='Awakemoon:BAABLgAECn8VAAIOAAcJFyRcAwBfAgAOAAcJFyRcAwBfAgAAAA==.',
Az='Azarazan:BAAALgADCgIJAgAAAA==.Azaria:BAAALgADCgkJDQAAAA==.Azenderv:BAABLgAECn8UAAIPAAcJbwMcnQDYAAAPAAcJbwMcnQDYAAAAAA==.Azka:BAABLgAECn8hAAIDAAgJVx9mGADWAgADAAgJVx9mGADWAgAAAA==.Azkadk:BAAALgAECgcJDAAAAA==.Azkamage:BAAALgAECgYJCQAAAA==.Azshaloria:BAAALgAECgYJDgAAAA==.Azter:BAAALgADCgMJAwAAAA==.',
Ba='Babybilly:BAAALgAECgYJDwAAAA==.Baddieelf:BAAALgAECgYJEAAAAA==.Bakkasura:BAAALgAFFAEJAQABLgAFFAEJAQAFAAAAAA==.Balduran:BAAALgADCgMJAwAAAA==.Baludis:BAAALgAECgYJCgAAAA==.Bamff:BAABLgAECn8ZAAIPAAgJQxlTLQDsAQAPAAgJQxlTLQDsAQAAAA==.Bast:BAABLgAECn8gAAIQAAgJiiCKAgDMAgAQAAgJiiCKAgDMAgABLgAFFAMJBgAIAKEHAA==.Bastbrew:BAABLgAFFH8GAAIIAAMJoQeiJQC+AAAIAAMJoQeiJQC+AAAAAA==.Basthara:BAAALgAECgYJDQABLgAFFAMJBgAIAKEHAA==.Batracio:BAABLgAECn8jAAMNAAcJxRXCMQBvAQANAAcJWxTCMQBvAQARAAYJsRX+EwBOAQAAAA==.Batshiz:BAAALgADCgUJBQAAAA==.',
Be='Bearlylivin:BAAALgAECgEJAgABLgAECgcJCQAFAAAAAA==.Beerox:BAAALgADCgIJAgAAAA==.Belindah:BAAALgADCgcJDAABLgAECggJGwAEAO0SAA==.Bellemore:BAAALgADCgkJCQAAAA==.Benif:BAACLgAFFH8OAAIBAAUJox73BgBqAQABAAUJox73BgBqAQAuAAQKfzUAAwEACQnUIwIBADUDAAEACQnUIwIBADUDAAIABAkKGoYRADcBAAAA.Bertodruid:BAAALgADCgYJBgAAAA==.Bertorod:BAABLgAECn8TAAISAAgJXR09EgDKAQASAAgJXR09EgDKAQAAAA==.',
Bh='Bhaall:BAABLgAECn8WAAITAAYJ1QenigDLAAATAAYJ1QenigDLAAAAAA==.',
Bi='Bigbitehotdo:BAAALgAFFAIJAwABLgAFFAMJCgATADYlAA==.Bigboppa:BAAALgADCgEJAQAAAA==.Bigknife:BAAALgAECgQJEwAAAA==.Bigtommybuns:BAAALgAECgEJAQAAAA==.Binkyfiasco:BAABLgAECn8lAAMIAAgJtiGqBwBVAgAIAAgJtiGqBwBVAgAUAAEJphiFeQA3AAAAAA==.',
Bl='Blaqlight:BAAALgADCgEJAQAAAA==.Bloblop:BAAALgAECgkJBgAAAA==.Blockybird:BAAALgAECgIJAgAAAA==.Bloodstoned:BAAALgADCgcJDwAAAA==.Bloodtank:BAAALgAECgYJEgAAAA==.',
Bm='Bmanblastmas:BAAALgAECgEJAQAAAA==.',
Bo='Bobquat:BAAALgADCgIJAgAAAA==.Bolcy:BAACLgAFFH8KAAQHAAQJ7AxTGgA0AQAHAAQJ0AxTGgA0AQAVAAMJDwl8EADwAAAWAAEJyAFQLQA9AAAuAAQKfxkABAcACAnRG6EXABICAAcABwmVH6EXABICABYABAm1EgdRAAkBABUAAQkrENI3AEkAAAAA.Boogat:BAAALgAECgcJDwAAAA==.Boonkgang:BAAALgADCgEJAQAAAA==.Bowjangles:BAAALgADCgUJBQAAAA==.',
Br='Brahd:BAAALgAECggJCAAAAA==.Brauck:BAACLgAFFH8KAAIKAAQJ3B5uGQBOAQAKAAQJ3B5uGQBOAQAuAAQKfyUAAwwACAmvIEQYAIgBAAoABQnSIcdSAM8BAAwABQk3H0QYAIgBAAEuAAUUBgkPABcAcxYA.Brittarcher:BAAALgAECgcJDAAAAA==.Brixlo:BAAALgAECgUJCAABLgAECgcJGwAYAMQIAA==.',
Bu='Bubblegum:BAAALgADCgMJAQAAAA==.Buffmuffin:BAAALgAECgEJAgAAAA==.Bugslyfe:BAAALgADCggJCAAAAA==.Bullcat:BAAALgADCgEJAQAAAA==.Bunbohue:BAABLgAECn8XAAINAAcJtROOWQCVAQANAAcJtROOWQCVAQAAAA==.Burp:BAACLgAFFH8VAAQKAAYJ6RiiGgBJAQAKAAUJLhaiGgBJAQAMAAIJDxjtCgCyAAALAAEJAAAbBQBYAAAuAAQKfyUABAwACAlPJOMUAKMBAAoABglZJJc0ADkCAAwABAmCJOMUAKMBAAsAAwnqJI4OAEgBAAAA.Burped:BAAALgAECgQJCAAAAA==.',
['Bü']='Büllseye:BAAALgAECgEJAQAAAA==.',
Ca='Cambrier:BAABLgAECn8vAAIBAAgJwiAhBgCPAgABAAgJwiAhBgCPAgAAAA==.Cardinal:BAAALgAECgcJBQAAAA==.Carynden:BAAALgAECgYJBgAAAA==.Cazbirkzul:BAAALgADCgEJAQAAAA==.',
Ce='Celeniel:BAAALgAFFAQJBAAAAA==.Celorne:BAAALgADCgEJAQAAAA==.Cerostus:BAAALgAECgUJBQAAAA==.',
Ch='Chaladaug:BAAALgAECgIJAQAAAA==.Chaladk:BAAALgAECgcJBgAAAA==.Charcharwar:BAABLgAECn8vAAICAAcJYhINEACcAQACAAcJYhINEACcAQAAAA==.Charknight:BAAALgAECgMJAwAAAA==.Charmaldin:BAAALgADCgMJAwAAAA==.Chatdodu:BAAALgAECgUJEAAAAA==.Chatnoir:BAAALgAECgUJBQAAAA==.Chivap:BAAALgAECgkJCQAAAA==.Chulu:BAAALgADCgcJCwAAAA==.Chunklleria:BAAALgAECgMJBAABLgAECgkJLAABAPAhAA==.Chunks:BAABLgAECn8sAAQBAAkJ8CFrAQAhAwABAAkJ8CFrAQAhAwAZAAcJ3RigEQDtAQACAAcJNxDnDgBXAQAAAA==.Chunkvourer:BAAALgADCgUJAwABLgAECgkJLAABAPAhAA==.',
Ci='Cinci:BAAALgADCgkJCgAAAA==.Cinderazer:BAAALgAECgMJAQAAAA==.Cipherdam:BAAALgAECgIJAgAAAA==.',
Co='Colesiaw:BAAALgADCgUJBQAAAA==.Colress:BAAALgAECgQJBwAAAA==.Conduit:BAAALgAECgYJDAAAAA==.Cormier:BAAALgAECgQJCgABLgAECgYJEQAFAAAAAA==.Covidvax:BAAALgADCgEJAQAAAA==.',
Cr='Cronnie:BAAALgAECgMJBgAAAA==.Cryodormu:BAAALgAECgYJCgAAAA==.',
Ct='Ctrlaltd:BAAALgAECgEJAQAAAA==.',
Cu='Cubo:BAAALgADCgEJAQAAAA==.',
Cw='Cwarr:BAAALgAFFAIJAwABLgAFFAQJDQAZAAMVAA==.',
Cy='Cyrcee:BAAALgADCggJCAABLgAECggJGwAEAO0SAA==.',
Da='Dabast:BAAALgAECgMJBAABLgAFFAMJBgAIAKEHAA==.Daddyluis:BAAALgAECgQJBwAAAA==.Daddywarbuck:BAAALgAECgEJAQAAAA==.Danat:BAAALgAECgEJAQAAAA==.Dandanh:BAAALgADCgcJCAAAAA==.Dankbo:BAABLgAECn8wAAIaAAkJYCOgAAC0AwAaAAkJYCOgAAC0AwAAAA==.Dankbro:BAAALgADCgUJBQAAAA==.Darkivie:BAAALgAECgYJBwABLgAECggJKwAXAOAEAA==.Darthmama:BAAALgADCgIJAgAAAA==.',
Dc='Dcbuster:BAABLgAECn8nAAIBAAgJaRdMFgC1AQABAAgJaRdMFgC1AQAAAA==.',
De='Deathshrimp:BAAALgADCgcJCwAAAA==.Delaylea:BAAALgAECgQJBQAAAA==.Demonhusk:BAAALgAECgYJDAAAAA==.Demoni:BAAALgADCgcJBwAAAA==.Demonicsword:BAAALgAECgIJBwAAAA==.Demonz:BAAALgADCgcJCgAAAA==.Denaheal:BAAALgADCgUJBQABLgAECgYJDwAFAAAAAA==.Devildj:BAAALgAECgcJCAAAAA==.',
Dh='Dhampyra:BAABLgAECn8gAAIYAAkJhx6QAwDAAgAYAAkJhx6QAwDAAgAAAA==.',
Di='Dianasia:BAAALgAECgMJAwAAAA==.Dietdrkelps:BAAALgAECgQJBAABLgAECgcJEwAFAAAAAA==.Dietmountdew:BAAALgAECgUJCQAAAA==.Dimitrios:BAAALgAECgEJAgAAAA==.Dingadinga:BAAALgAECgYJEQAAAA==.Dirtlicker:BAAALgADCgIJAgAAAA==.Disconnect:BAAALgAECgYJDQAAAA==.Dixxonciderr:BAACLgAFFH8LAAIbAAMJ0Rn3EAAHAQAbAAMJ0Rn3EAAHAQAuAAQKfzMABBsACQmGEesMAHgBABsACQmGEesMAHgBABwABAl3E2MNALkAABcABQmOBUJEAIcAAAAA.',
Dk='Dkjaypim:BAAALgAECgIJAgAAAA==.',
Dm='Dmoe:BAAALgAECgUJEwAAAA==.',
Do='Dorkdark:BAAALgAECgMJAwAAAA==.',
Dr='Dragonflyer:BAAALgAFFAEJAQAAAA==.Drioksis:BAAALgAECgQJDgAAAA==.Drshaboinkyy:BAACLgAFFH8LAAINAAUJYhJkCQCUAQANAAUJYhJkCQCUAQAuAAQKfxQAAw0ACAmYIv0tAEUCAA0ACAmYIv0tAEUCABAABwlEA8QqADYAAAAA.Drshbuinky:BAAALgAECgYJBwAAAA==.Druyalulz:BAAALgAECgYJCgAAAA==.',
Du='Duckboy:BAAALgADCgUJBwAAAA==.Dumag:BAABLgAECn8hAAIIAAgJbyFiBgByAgAIAAgJbyFiBgByAgAAAA==.Duplicate:BAACLgAFFH8NAAIPAAMJ/A7QMADvAAAPAAMJ/A7QMADvAAAuAAQKfzoAAg8ACQmDHPwTAHoCAA8ACQmDHPwTAHoCAAAA.Dustdruid:BAABLgAFFH8FAAIdAAMJAwyFDwDqAAAdAAMJAwyFDwDqAAAAAA==.Dustlock:BAAALgAECgQJBAAAAA==.',
Dw='Dwighthowelf:BAAALgADCgEJAQAAAA==.',
Dy='Dyorah:BAAALgADCgYJBgAAAA==.',
Eb='Ebonsnoot:BAAALgADCgEJAQAAAA==.',
Ee='Eender:BAAALgADCgYJCAAAAA==.',
Eg='Eggrolls:BAAALgAECgQJBAAAAA==.',
El='Elif:BAAALgADCgEJAQAAAA==.Eliotyy:BAAALgADCgYJCgAAAA==.Ellcrys:BAABLgAECn8nAAIEAAkJ2A4QLgBrAQAEAAkJ2A4QLgBrAQAAAA==.Elletta:BAAALgAECgEJAgAAAA==.Ellssa:BAAALgAECgYJDwAAAA==.Elmamonster:BAAALgAECgQJBwAAAA==.',
Em='Emerick:BAAALgADCgYJBQAAAA==.Emillie:BAAALgAECgYJEQAAAA==.',
Ep='Epora:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.',
Er='Ersande:BAAALgADCggJCwAAAA==.',
Es='Estellia:BAAALgADCgUJBQAAAA==.Estheban:BAABLgAECn8nAAMbAAgJ7CMeAQBEAwAbAAgJ7CMeAQBEAwAXAAEJAwfPaAAkAAAAAA==.',
Ex='Exodia:BAAALgAECgYJCQAAAA==.',
Fa='Face:BAABLgAECn8VAAINAAYJGAwKWgDvAAANAAYJGAwKWgDvAAAAAA==.Faelila:BAAALgADCgYJBgAAAA==.Fairgrim:BAAALgAECgMJAwAAAA==.Falin:BAABLgAECn9fAAIDAAkJtRyfDQCTAgADAAkJtRyfDQCTAgAAAA==.Falthras:BAAALgAECgYJDAAAAA==.Fanethben:BAAALgAECgYJCgAAAA==.Faqueuedark:BAACLgAFFH8IAAMLAAMJUA/jBgBZAAAKAAMJUA8nSADJAAALAAEJVBfjBgBZAAAuAAQKfx4ABAoACAmVH1IrAGICAAoACAkJH1IrAGICAAsAAgkXIQMYALsAAAwAAQkAADxuADkAAAAA.Faqueueeight:BAAALgAFFAEJAQABLgAFFAMJCAALAFAPAA==.Faqueuetoo:BAAALgAECgUJBAABLgAFFAMJCAALAFAPAA==.Fatsloth:BAAALgADCgcJEAAAAA==.',
Fe='Feironos:BAAALgAECgMJDgAAAA==.Felray:BAAALgADCgUJCAAAAA==.Ferairi:BAAALgAECgQJCgABLgAECgYJEQAFAAAAAA==.Fereir:BAAALgADCgQJBAAAAA==.Ferndavia:BAAALgAECgYJDwAAAA==.',
Fi='Fiist:BAAALgADCgYJDgAAAA==.Filigree:BAAALgADCgYJBgAAAA==.Fimtastic:BAABLgAECn8XAAIeAAcJ2AfLRQDqAAAeAAcJ2AfLRQDqAAAAAA==.Finasy:BAABLgAECn8pAAQfAAgJ+CDqAwCJAgAfAAgJ+CDqAwCJAgATAAQJxhLNcwD6AAAgAAEJ4g9FFwAzAAAAAA==.Finnicka:BAAALgADCgcJDQAAAA==.Fireouch:BAAALgAECgEJAQAAAA==.Fistymisty:BAAALgAECggJDAAAAA==.',
Fl='Flaynpray:BAAALgAECgcJAgAAAA==.Flopsie:BAAALgAECggJDAAAAA==.',
Fo='Fonzsupreme:BAABLgAECn8YAAIPAAYJnCKfVwAyAgAPAAYJnCKfVwAyAgABLgAFFAQJDQAZABIhAA==.Foxkit:BAAALgAECgEJAgAAAA==.',
Fr='Fredox:BAAALgADCgcJBwAAAA==.Freemilk:BAAALgAECgEJAQAAAA==.Frostbight:BAAALgADCgUJCwAAAA==.Frostyflake:BAAALgADCgUJBQAAAA==.',
Fu='Furearia:BAAALgAECgMJAwAAAA==.Furrybowner:BAAALgAECgcJDgAAAA==.',
['Fó']='Fóx:BAAALgAECgYJCAAAAA==.',
Ga='Gaelai:BAAALgAECgUJBwAAAA==.Galeriel:BAACLgAFFH8MAAIhAAMJJhnWDQD0AAAhAAMJJhnWDQD0AAAuAAQKfy4AAiEACQlyG7sGAIsCACEACQlyG7sGAIsCAAAA.Gallethline:BAAALgADCgcJIAAAAA==.Garault:BAAALgAECgYJBgAAAA==.',
Ge='Gekoni:BAABLgAECn8XAAIGAAgJwApgJQDdAAAGAAgJwApgJQDdAAAAAA==.Geonon:BAABLgAECn8fAAIPAAgJeAw2SgCJAQAPAAgJeAw2SgCJAQAAAA==.Georgemoyd:BAAALgADCgkJCwAAAA==.',
Gi='Girthybeam:BAAALgAECgMJAwAAAA==.',
Gl='Glandrien:BAAALgAECgMJAwAAAA==.Gloomshak:BAAALgAECgMJAgAAAA==.Glowclaws:BAAALgADCgQJAwAAAA==.Glowpwr:BAAALgADCgMJAwAAAA==.',
Go='Gobblerella:BAAALgADCgMJAwAAAA==.Gobeullin:BAAALgAFFAEJAQAAAA==.Goonthergg:BAAALgADCgkJCgAAAA==.Gothmog:BAAALgADCgMJAwAAAA==.',
Gr='Graytonson:BAAALgAECgEJAQAAAA==.Greenhills:BAAALgADCgIJAgAAAA==.Greenlocks:BAAALgADCgIJAgABLgAFFAEJAQAFAAAAAA==.Greenrånger:BAAALgAECgQJCwAAAA==.Greybush:BAAALgAECgQJBwAAAA==.Griffithw:BAAALgADCgYJCwAAAA==.Grombrindil:BAAALgAECgEJAQABLgAECgcJHAAUAG8NAA==.Grullander:BAABLgAECn8iAAIeAAgJtxdMEwAcAgAeAAgJtxdMEwAcAgAAAA==.Grullandur:BAAALgAECgEJAQABLgAECggJIgAeALcXAA==.',
Gu='Guiguiie:BAAALgADCgcJBwAAAA==.',
['Gó']='Gólden:BAAALgADCgYJBgAAAA==.',
Ha='Hahacx:BAACLgAFFH8CAAINAAIJShOBVwBRAAANAAIJShOBVwBRAAAuAAQKfxkAAg0ACAmdIVkSAO0CAA0ACAmdIVkSAO0CAAAA.Halama:BAAALgADCgcJBwAAAA==.Halazzì:BAAALgAECgMJAwAAAA==.Haleon:BAAALgAECgIJAgAAAA==.Haraharotou:BAAALgAECgMJBgAAAA==.Hardyhar:BAAALgADCgMJBAAAAA==.',
He='Hebrews:BAAALgADCgYJBgAAAA==.Herkharu:BAABLgAECn8XAAISAAgJhQy2JAAxAQASAAgJhQy2JAAxAQAAAA==.Hermionee:BAAALgAECgQJBwAAAA==.',
Hi='Himjongun:BAABLgAECn8bAAMRAAYJzQ+tLABkAQARAAYJPQ+tLABkAQANAAYJdQiVXQDlAAAAAA==.',
Ho='Hobbitdemon:BAAALgAECgQJBAAAAA==.Hobbitdruid:BAABLgAECn8cAAMEAAcJ5AVLUADUAAAEAAcJ5AVLUADUAAAOAAUJwwl8GgCIAAAAAA==.Hobbitpriest:BAAALgADCgUJBQAAAA==.Hobbitvoid:BAAALgAECgEJAQAAAA==.Holydagoon:BAAALgADCgYJBgABLgAFFAYJDwAXAHMWAA==.Hoother:BAAALgAECgYJCAAAAA==.Hoppingmuff:BAAALgADCgcJDQAAAA==.',
Hu='Hunia:BAAALgAECgUJDQAAAA==.Huntieluis:BAAALgAECgQJBAAAAA==.Hurndredd:BAAALgAECgIJAwAAAA==.Huuh:BAAALgADCgMJBgAAAA==.',
Hy='Hystericc:BAAALgAECgEJAgAAAA==.',
['Hé']='Héboric:BAAALgAECgcJDQAAAA==.',
['Hõ']='Hõlycow:BAAALgAECgEJAQAAAA==.',
Id='Idolon:BAAALgADCggJGAAAAA==.',
Ik='Ikashi:BAAALgADCgEJAQAAAA==.Ikodiwa:BAAALgAECgYJEQAAAA==.',
Il='Ilrion:BAAALgAECgcJEQAAAA==.',
In='Indravax:BAAALgAECgMJBQAAAA==.Inferno:BAAALgAECgEJAwAAAA==.',
Is='Iseehot:BAABLgAECn8hAAIPAAYJah60RQCWAQAPAAYJah60RQCWAQAAAA==.',
Iv='Ivantis:BAAALgAECgQJCAAAAA==.Ivie:BAABLgAECn8bAAIEAAgJ7RJTKACNAQAEAAgJ7RJTKACNAQAAAA==.Ivieenfuego:BAABLgAECn8rAAIXAAgJ4ATQLgDrAAAXAAgJ4ATQLgDrAAAAAA==.',
Ja='Jadednurse:BAAALgAECgYJEQAAAA==.Jakisormjr:BAAALgADCgIJAgAAAA==.Jalanii:BAAALgAECggJEQAAAA==.Janjor:BAACLgAFFH8KAAISAAMJlAxcGgDcAAASAAMJlAxcGgDcAAAuAAQKfycAAhIACQkeHk4aAEECABIACQkeHk4aAEECAAAA.Janjorski:BAAALgADCgQJBAAAAA==.Jayrior:BAAALgADCgcJCwAAAA==.',
Je='Jehlock:BAAALgAECgUJCgAAAA==.Jehvoker:BAAALgAECgYJCgABLgAECgUJCgAFAAAAAA==.Jerghal:BAAALgAECgYJEAAAAA==.Jesthos:BAAALgAECgcJAgABLgAECgcJCQAFAAAAAA==.Jettian:BAAALgAECgYJEgAAAA==.',
Ji='Jinu:BAAALgADCgIJAgAAAA==.',
Jj='Jjdruid:BAAALgAECgEJAQAAAA==.',
Jo='Jockwork:BAAALgAECgQJDAAAAA==.Jokeer:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Jolene:BAABLgAECn8aAAIdAAcJbApoKgDxAAAdAAcJbApoKgDxAAAAAA==.Jollygreene:BAAALgAECgYJDwAAAA==.Joyina:BAAALgADCgkJIgAAAA==.',
Ju='Justicee:BAAALgAECgQJCAABLgAECggJDAAFAAAAAA==.',
Jx='Jxy:BAAALgAECgUJCQABLgAFFAYJFwANAKMcAA==.',
Ka='Kachess:BAAALgADCgIJAgAAAA==.Kahri:BAABLgAECn8VAAQOAAYJVB11CACjAQAOAAYJVB11CACjAQAiAAUJxBOOEQADAQAEAAEJiAVCqgAhAAAAAA==.Kakali:BAAALgADCgQJBQAAAA==.Kalend:BAAALgAECgMJAwAAAA==.Karlager:BAABLgAECn8cAAIUAAcJbw0THQA7AQAUAAcJbw0THQA7AQAAAA==.Karlain:BAAALgAECgYJDQAAAA==.Karldun:BAAALgADCggJCAABLgAECgcJHAAUAG8NAA==.Kasaide:BAAALgADCgcJDQABLgAECggJKQAKAIwPAA==.Kasmir:BAABLgAECn8pAAIKAAgJjA80NACTAQAKAAgJjA80NACTAQAAAA==.Katia:BAAALgADCgUJBwAAAA==.Kazoo:BAAALgAECgQJBAABLgAFFAUJEgAaADEVAA==.',
Ke='Keeflo:BAAALgADCgkJDwAAAA==.Kelisii:BAAALgAFFAMJBAAAAA==.Keloenivas:BAAALgADCggJEQAAAA==.Kelomage:BAAALgAECgEJAQAAAA==.Ketaza:BAAALgAECgEJAQAAAA==.Keyash:BAAALgADCgIJAgAAAA==.',
Kh='Khyle:BAAALgADCgEJAQABLgADCgcJEAAFAAAAAA==.',
Ki='Kibblebits:BAABLgAECn8aAAIdAAcJcAPrOQChAAAdAAcJcAPrOQChAAAAAA==.Kijanajr:BAAALgAECgIJAgAAAA==.Kitheros:BAAALgADCgcJBwAAAA==.Kittun:BAAALgADCgEJAQAAAA==.',
Kl='Klay:BAABLgAECn8jAAQZAAgJ7SOHBQBIAgAZAAgJ7SOHBQBIAgACAAMJug1nNABgAAABAAIJtQKGngBGAAAAAA==.Klutch:BAAALgADCgIJAgAAAA==.',
Km='Kmarti:BAECLgAFFH8FAAINAAMJpBB9MQDqAAANAAMJpBB9MQDqAAAuAAQKfx4AAw0ACAlEIGAhAIkCAA0ACAlEIGAhAIkCABEAAgn/C/9fAGIAAAAA.',
Ko='Koivath:BAAALgADCgkJEQAAAA==.Konradevoker:BAAALgAFFAEJAgABLgAECgkJKwAKAFQeAA==.Konradlock:BAABLgAECn8rAAMKAAkJVB6YBgBVAwAKAAkJVB6YBgBVAwAMAAIJVxkyTQCGAAAAAA==.Konradrogue:BAABLgAECn8xAAMjAAkJuh6sAABiAwAjAAkJox6sAABiAwAkAAcJYxrXHQAPAgABLgAECgkJKwAKAFQeAA==.Konradwar:BAABLgAECn8XAAMCAAYJNx79EgB0AQACAAYJZhj9EgB0AQABAAQJpRa5bgD8AAABLgAECgkJKwAKAFQeAA==.Kosmicknight:BAABLgAECn8WAAITAAcJeBE5YgAgAQATAAcJeBE5YgAgAQAAAA==.',
Kr='Krathös:BAAALgAECgQJBAAAAA==.Krimzin:BAAALgAECgEJAQABLgAFFAQJCQAHAD0bAA==.Kromak:BAAALgAECgQJBAAAAA==.',
Ku='Kunfoopizza:BAAALgAECgQJCQAAAA==.Kuulibah:BAAALgADCgEJAQABLgADCgMJAwAFAAAAAA==.Kuulibarr:BAAALgADCgMJAwAAAA==.',
Kw='Kwarr:BAACLgAFFH8KAAIeAAMJWBOUDwDrAAAeAAMJWBOUDwDrAAAuAAQKfxYAAh4ABwnOFxYxAMIBAB4ABwnOFxYxAMIBAAEuAAUUBAkNABkAAxUA.',
Ky='Kynaragon:BAABLgAECn8lAAMdAAcJfSaPGABEAgAdAAYJZSaPGABEAgAEAAQJ0CSlYwAmAQABLgAECgkJLQAEALYmAA==.Kyrimmon:BAAALgAECgEJAQAAAA==.',
La='Lallypop:BAAALgAECgQJCAAAAA==.Lammoth:BAAALgAECgEJAgAAAA==.Lanthein:BAAALgAECgEJAQABLgAFFAYJDwAXAHMWAA==.Laraela:BAAALgADCgEJAQAAAA==.Largehusband:BAAALgAECgEJAQAAAA==.Larkindas:BAAALgAECgEJAQAAAA==.Layil:BAAALgADCgYJBwAAAA==.',
Le='Leafu:BAAALgAECgQJDAABLgAECgcJHQAYAI0dAA==.Leasin:BAABLgAECn8dAAIYAAcJjR2OEADJAQAYAAcJjR2OEADJAQAAAA==.Leathle:BAAALgADCgkJEAAAAA==.Leepa:BAAALgAECgcJDQAAAA==.Leesta:BAAALgAECgEJAQAAAA==.Lepp:BAAALgAECgEJAQAAAA==.Lexslaner:BAAALgADCgYJCQAAAA==.',
Li='Lighthusk:BAABLgAECn8WAAMhAAgJlR/IBADCAgAhAAgJlR/IBADCAgAYAAEJxAOvaAAnAAABLgAECggJFgAhAJUfAA==.Likeans:BAAALgAECgEJAQAAAA==.Liliauna:BAABLgAECn8aAAIKAAgJCRWjJADYAQAKAAgJCRWjJADYAQAAAA==.Lilibejeane:BAAALgAECgEJAQABLgAECgcJFAARADUOAA==.Lilithalen:BAABLgAECn8oAAIhAAgJfBnmFQAtAgAhAAgJfBnmFQAtAgAAAA==.Lilmymy:BAAALgAECgIJAgAAAA==.Lilshimer:BAABLgAECn8XAAMKAAYJ3BmTVgDEAQAKAAYJ3BmTVgDEAQALAAIJdQMnIQBtAAAAAA==.Lilsquirtboy:BAACLgAFFH8KAAITAAMJNiVIKgBMAQATAAMJNiVIKgBMAQAuAAQKfzAAAxMACQnCI/4DACYDABMACQnCI/4DACYDAB8AAQmZCcNNABsAAAAA.Linithara:BAAALgAECgUJBQABLgAECggJKAAhAHwZAA==.Lizardbird:BAAALgAECgQJBwAAAA==.Lizzi:BAAALgADCgcJBgAAAA==.',
Lo='Lockersz:BAAALgAECgQJBAABLgAFFAUJCQAWAAENAA==.Lockitt:BAABLgAECn8WAAIKAAkJBg0dXQCxAQAKAAkJBg0dXQCxAQAAAA==.Lostgrip:BAAALgAECgMJAwAAAA==.',
Lu='Lucthedk:BAABLgAECn8ZAAITAAYJCxCsWgAxAQATAAYJCxCsWgAxAQAAAA==.Luk:BAAALgADCgYJBgAAAA==.Lukis:BAAALgADCgYJDAAAAA==.Lumario:BAAALgADCgEJAQAAAA==.Lunarpriest:BAAALgAECgEJAQAAAA==.Lunkbeck:BAAALgAECgQJBAAAAA==.Luva:BAAALgADCgcJEQAAAA==.Luxriel:BAAALgAECgQJBAAAAA==.',
Ly='Lyio:BAAALgAECgUJCgAAAA==.',
Ma='Madmandeath:BAAALgADCgQJAwAAAA==.Magicmegan:BAAALgAECgEJAQAAAA==.Mahlanas:BAAALgAECgYJDgAAAA==.Maki:BAABLgAFFH8FAAITAAIJ8heUaACpAAATAAIJ8heUaACpAAAAAA==.Maladin:BAAALgAECgMJAwAAAA==.Malvean:BAAALgADCgcJCgAAAA==.Mamajoy:BAAALgADCgMJBgAAAA==.Maravilla:BAABLgAECn8VAAIOAAgJhQ1lDwASAQAOAAgJhQ1lDwASAQAAAA==.Marceline:BAAALgAECgcJCwAAAA==.Markuspapa:BAAALgAECgQJBAABLgAFFAUJEgAaADEVAA==.Marlowe:BAAALgAECgYJCAAAAA==.Marremer:BAABLgAECn8YAAMfAAcJJA8aJAAgAQAfAAUJnBMaJAAgAQAgAAcJKwRQDADEAAAAAA==.',
Mc='Mckicky:BAAALgAECgYJDwAAAA==.',
Me='Mechafire:BAAALgADCgYJBgAAAA==.Melanius:BAABLgAECn8iAAMbAAgJ4CT2AABUAwAbAAgJ4CT2AABUAwAcAAEJYg0KQQAuAAAAAA==.Melliex:BAAALgADCgMJAwAAAA==.Melodras:BAABLgAECn8eAAMhAAgJrxKdFQCoAQAhAAgJrxKdFQCoAQAaAAIJkgZnTgBXAAAAAA==.Memelord:BAAALgAECgQJCgAAAA==.Merce:BAAALgADCgEJAQAAAA==.Metalock:BAAALgADCgcJCwAAAA==.Mewalina:BAAALgADCgQJBAAAAA==.',
Mi='Mirajen:BAAALgADCgMJAwAAAA==.Mirukoo:BAAALgAECgQJBAAAAA==.Misconduct:BAAALgAFFAEJAQAAAA==.Mistywaters:BAAALgAECgEJAgAAAA==.Mittyy:BAAALgADCgYJBwAAAA==.',
Mo='Moomist:BAAALgAECgIJAgAAAA==.Mornintreant:BAAALgADCgMJAwAAAA==.Mousekewitzk:BAAALgAECgQJAwAAAA==.Movarth:BAAALgADCgkJCQAAAA==.',
Mu='Mujer:BAAALgAECgEJAQAAAA==.Mungas:BAAALgADCgUJBgAAAA==.Murlloc:BAAALgADCgcJBgAAAA==.',
My='Myrathia:BAABLgAFFH8GAAIEAAIJmASAOQBoAAAEAAIJmASAOQBoAAAAAA==.Myrcella:BAAALgAECgQJBQAAAA==.',
['Má']='Máximodécimo:BAAALgAECgMJCAAAAA==.',
Na='Nahemah:BAAALgAECgIJAwABLgAFFAEJAQAFAAAAAA==.Nahtan:BAABLgAECn8dAAIHAAcJ5w/hMwB+AQAHAAcJ5w/hMwB+AQAAAA==.Nahwe:BAAALgADCgUJBQAAAA==.Narrsul:BAABLgAECn8XAAIKAAYJ5xJnVgApAQAKAAYJ5xJnVgApAQAAAA==.Nattyg:BAAALgAECgYJEAAAAA==.Naves:BAAALgADCgIJAgAAAA==.',
Ne='Nereza:BAAALgADCgUJBgAAAA==.Nevermorte:BAAALgAECgYJBgAAAA==.',
Nf='Nfggolden:BAAALgAECgcJAwAAAA==.',
Ni='Nightforday:BAABLgAECn80AAITAAgJwBl2HgASAgATAAgJwBl2HgASAgAAAA==.Niko:BAAALgAECgQJDAAAAA==.',
No='Noknani:BAAALgADCgUJBgAAAA==.Nokx:BAAALgAECgEJAQAAAA==.Nool:BAAALgADCgcJCQAAAA==.Norch:BAAALgADCgMJAwAAAA==.Nostranova:BAAALgAECgEJAQAAAA==.Novà:BAAALgADCgMJAwAAAA==.',
Ny='Nyriand:BAAALgADCgQJBAAAAA==.',
Oh='Ohkayboomer:BAAALgAFFAEJAQAAAA==.',
Ok='Oktraal:BAAALgAECgEJAQAAAA==.',
Oo='Oontanx:BAAALgADCgcJCQAAAA==.Ooups:BAABLgAECn8fAAIIAAgJcRQ4EQC8AQAIAAgJcRQ4EQC8AQAAAA==.',
Op='Ophysia:BAABLgAECn8ZAAIDAAgJZhkeHQAZAgADAAgJZhkeHQAZAgAAAA==.',
Or='Orangecage:BAABLgAECn/RAAMdAAkJdCYpAACPAwAdAAkJdCYpAACPAwAEAAIJfwYgswBeAAAAAA==.Orkcansas:BAAALgAFFAEJAQAAAA==.',
Os='Osrsfemale:BAAALgAECgIJAgAAAA==.',
Ov='Overlooker:BAAALgADCgMJAwAAAA==.',
Ox='Oxazine:BAABLgAECn8XAAMSAAkJ6BL9NgDSAAASAAcJHxD9NgDSAAAeAAUJjQMIXgCFAAAAAA==.',
Pa='Paapineau:BAABLgAECn8VAAIjAAYJHQvjCgAWAQAjAAYJHQvjCgAWAQAAAA==.Packel:BAAALgADCgEJAQABLgAECggJIQAOAC8SAA==.Packs:BAAALgADCgIJAgABLgAECggJIQAOAC8SAA==.Palladias:BAAALgAECgQJBgAAAA==.Pally:BAAALgADCgIJAgAAAA==.',
Pc='Pcm:BAAALgAECgYJCQAAAA==.',
Pe='Peefmajeef:BAAALgADCgIJAgAAAA==.Peony:BAAALgADCgQJBAAAAA==.Pepperjack:BAAALgAECgQJBQAAAA==.Petshellkek:BAACLgAFFH8WAAITAAcJwyK1AQBRAgATAAcJwyK1AQBRAgAuAAQKfxcAAhMACAktI3oUAAADABMACAktI3oUAAADAAAA.Pewpeew:BAAALgAECgUJDQAAAA==.',
Ph='Phantomclone:BAABLgAECn8UAAIUAAYJYR68FwBoAQAUAAYJYR68FwBoAQAAAA==.Phantomghoul:BAAALgADCgEJAQAAAA==.Phantomwar:BAAALgAECgIJAgAAAA==.Phantomzz:BAAALgAECgEJAQAAAA==.Phaté:BAAALgADCgEJAQAAAA==.Pheonixxwolf:BAAALgAECgYJDgAAAA==.Pherc:BAAALgADCgcJBwAAAA==.Phillyblunt:BAABLgAECn8aAAMeAAcJURNEMQDBAQAeAAcJURNEMQDBAQASAAEJDQcciwAtAAAAAA==.Phløw:BAAALgADCgUJDAAAAA==.',
Pl='Plaguekitten:BAAALgAECgEJAQAAAA==.Plowpatine:BAACLgAFFH8FAAIPAAMJ2gvqTgDnAAAPAAMJ2gvqTgDnAAAuAAQKfxcAAg8ABwmlHuAhACECAA8ABwmlHuAhACECAAAA.',
Po='Poisonblade:BAAALgAECgEJAQAAAA==.Poolius:BAAALgAECgQJDQAAAA==.Porfinne:BAAALgAECgEJAQAAAA==.',
Pr='Praedor:BAAALgADCgUJBQAAAA==.Preza:BAAALgADCgIJAgAAAA==.Priestymon:BAABLgAECn8eAAMaAAgJjxt/CgCRAgAaAAgJjxt/CgCRAgAYAAMJHxPiNAC6AAABLgAFFAUJDgABAKMeAA==.Prober:BAAALgADCgUJBQAAAA==.Producer:BAAALgAECgEJAQAAAA==.Protato:BAAALgAECgUJBQAAAA==.Prowaifu:BAAALgAECgUJBgAAAA==.Prowess:BAAALgADCggJFAAAAA==.Prîestitute:BAAALgADCgYJCQAAAA==.',
Pu='Purger:BAAALgADCgYJCgAAAA==.Puyo:BAABLgAECn8hAAIOAAgJLxKACwBbAQAOAAgJLxKACwBbAQAAAA==.Puyyoo:BAAALgADCgcJDwABLgAECggJIQAOAC8SAA==.',
Pw='Pwarr:BAACLgAFFH8NAAIZAAQJAxWMCAAkAQAZAAQJAxWMCAAkAQAuAAQKfxoAAhkABwlSH7kKAGUCABkABwlSH7kKAGUCAAAA.',
Py='Pyrofox:BAAALgADCgEJAQAAAA==.',
Qw='Qwarr:BAACLgAFFH8JAAMcAAMJVgrcBgChAAAXAAMJVgphIwDbAAAcAAIJWQncBgChAAAuAAQKfzMAAxcACQnlHwQDAO4CABcACQnlHwQDAO4CABwABglCHuoPANwBAAEuAAUUBAkNABkAAxUA.',
Ra='Rafoen:BAABLgAFFH8FAAIkAAIJ1hO5GgCjAAAkAAIJ1hO5GgCjAAAAAA==.Rakrur:BAAALgADCgEJAQAAAA==.Ramsay:BAAALgADCgkJEQAAAA==.Ranee:BAAALgAECgEJAQAAAA==.Rathorn:BAAALgADCgYJDAAAAA==.Raxsan:BAAALgAFFAMJBAAAAA==.Raydanbalor:BAAALgAECgUJBQABLgAECgcJGAAfACQPAA==.Rayennagrom:BAAALgAECgYJCwAAAA==.Razkko:BAAALgADCgUJBQAAAA==.',
Rd='Rdru:BAAALgADCgcJBwABLgAECgYJCgAFAAAAAA==.',
Re='Redpumpkin:BAAALgADCgMJAwAAAA==.Redsonja:BAAALgADCgcJDQAAAA==.Rel:BAAALgADCgYJBgAAAA==.Reneana:BAAALgAECgQJAgAAAA==.Respectisluv:BAABLgAECn8aAAIVAAcJRA7vEwB5AQAVAAcJRA7vEwB5AQAAAA==.Rexcor:BAAALgAECgQJBwAAAA==.',
Rh='Rhulad:BAAALgADCggJCAAAAA==.',
Ri='Riaeline:BAAALgAECgQJBgAAAA==.Richardluis:BAAALgAECgEJAQAAAA==.Rinehardtt:BAAALgAFFAEJAQAAAA==.Ripheals:BAACLgAFFH8TAAIeAAUJkBAyDgBTAQAeAAUJkBAyDgBTAQAuAAQKfysAAx4ACAnVGssdAC0CAB4ACAnVGssdAC0CABIABAkoHhNBAEUBAAAA.Riplee:BAAALgADCgYJCwABLgAFFAUJEwAeAJAQAA==.Rit:BAAALgAECgIJAgAAAA==.Rivër:BAABLgAECn8YAAIDAAkJpBv4PwAmAgADAAkJpBv4PwAmAgAAAA==.',
Ro='Robbell:BAABLgAECn8bAAIHAAgJahkKIABFAgAHAAgJahkKIABFAgAAAA==.Rockd:BAAALgAECgcJCQAAAA==.Rogueflame:BAAALgAECgcJDQAAAA==.Rootsie:BAAALgAECgQJDQAAAA==.Roselynn:BAABLgAECn8lAAIEAAgJJx3cDwC5AgAEAAgJJx3cDwC5AgAAAA==.',
Rs='Rsolbes:BAAALgADCgUJBQAAAA==.',
Ru='Ruerl:BAABLgAECn8UAAMGAAgJIwsQIwDvAAADAAgJ6AaBqgAtAQAGAAYJGwoQIwDvAAAAAA==.Rumblies:BAAALgAECgQJDgAAAA==.Runetusk:BAAALgADCgEJAQABLgAECgYJDQAFAAAAAA==.Rungin:BAAALgADCgEJAQAAAA==.Russopp:BAAALgADCgEJAQAAAA==.',
Sa='Saars:BAAALgADCgYJBgAAAA==.Samchan:BAAALgAECgEJBAAAAA==.Sanatharia:BAAALgAECgYJDAAAAA==.Saneatey:BAAALgAECgUJCwAAAA==.Sassibelle:BAAALgAECgUJBQAAAA==.Satanskidney:BAAALgADCgcJCAAAAA==.Sathenset:BAACLgAFFH8PAAIXAAYJcxYECACsAQAXAAYJcxYECACsAQAuAAQKfxUAAxwACAnLGEkRAMoBABwABwmsFkkRAMoBABcABAmrEjJDANQAAAAA.',
Sc='Scandium:BAABLgAECn8iAAILAAgJXR8TAQB2AgALAAgJXR8TAQB2AgAAAA==.Scrembiblion:BAABLgAECn8eAAIPAAgJMSEiEACZAgAPAAgJMSEiEACZAgAAAA==.',
Sd='Sdhoscillate:BAAALgAECgQJBQAAAA==.',
Se='Seagulpunchr:BAAALgADCgYJCgAAAA==.Seesh:BAACLgAFFH8KAAIBAAQJLiDyBgB+AQABAAQJLiDyBgB+AQAuAAQKfxgAAgEACQnSJBEDAIADAAEACQnSJBEDAIADAAAA.Sentarr:BAABLgAFFH8NAAIZAAQJEiHsAwB+AQAZAAQJEiHsAwB+AQAAAA==.Septhera:BAAALgAFFAEJAgAAAA==.',
Sh='Shadewither:BAAALgADCgQJBAAAAA==.Shadeyheals:BAAALgAECgYJCAAAAA==.Shadowxcraft:BAAALgAECgcJDAAAAA==.Shadrelin:BAAALgADCgEJAgAAAA==.Shaqler:BAAALgAECgMJBAAAAA==.Shecks:BAAALgADCgcJCAAAAA==.Shelandria:BAAALgAECgIJAgAAAA==.Sherwild:BAABLgAECn8YAAIEAAgJxiHvCgDqAgAEAAgJxiHvCgDqAgAAAA==.Shinara:BAABLgAECn8UAAIkAAYJQQ8AHAAfAQAkAAYJQQ8AHAAfAQAAAA==.Shiverchill:BAAALgAECgcJCQAAAA==.Shizznoint:BAAALgADCgMJAwAAAA==.Shnipishnap:BAABLgAECn9ZAAMeAAkJHiPWAACgAwAeAAkJHiPWAACgAwASAAkJniVnAAB5AwAAAA==.Shroomjuicee:BAABLgAECn8bAAIaAAcJdhWmGgDCAQAaAAcJdhWmGgDCAQAAAA==.Shyi:BAAALgADCgYJBgAAAA==.Shìlo:BAAALgAECgEJAQAAAA==.',
Si='Sindaemon:BAACLgAFFH8HAAINAAMJCBuCIwCzAAANAAMJCBuCIwCzAAAuAAQKfyMAAg0ACAntIWIUAN0CAA0ACAntIWIUAN0CAAAA.Sindrina:BAAALgAECgIJAgAAAA==.',
Sk='Skedaddle:BAAALgAECgQJBgAAAA==.Skelstone:BAAALgADCgYJBgAAAA==.Skädoosh:BAAALgAECgQJCAAAAA==.',
Sl='Slapshappy:BAABLgAECn8XAAIDAAcJcxmeRQB1AQADAAcJcxmeRQB1AQAAAA==.Sloptop:BAAALgAECgMJAwAAAA==.Slowfall:BAAALgADCgcJCwAAAA==.',
Sm='Smokin:BAAALgAECgYJDwAAAA==.Smoothg:BAAALgAECgMJAwAAAA==.',
Sn='Snowjor:BAAALgADCgEJAQAAAA==.Snyx:BAAALgADCgUJBQAAAA==.',
So='Solaríus:BAAALgADCgMJAwAAAA==.Soldanas:BAAALgADCgEJAQAAAA==.Solomus:BAAALgAECgIJAgAAAA==.',
Sp='Spheaddin:BAAALgAECgEJAQAAAA==.Spiritbomb:BAABLgAECn8bAAINAAgJpRlTFAAaAgANAAgJpRlTFAAaAgAAAA==.Spytime:BAAALgAECgYJDAAAAA==.',
Ss='Ssjchezzy:BAAALgAECgcJDgAAAA==.Ssmeltn:BAAALgAECgYJDQAAAA==.',
St='Steinberg:BAAALgADCgEJAQAAAA==.Stnaprednu:BAABLgAFFH8FAAIDAAMJ1wsGMgDvAAADAAMJ1wsGMgDvAAAAAA==.Stormiee:BAAALgAECgYJBgABLgAECggJGwAEAO0SAA==.Stormroid:BAAALgAECgQJBQAAAA==.Stormxwolf:BAAALgAECgYJDQAAAA==.Strangulate:BAAALgAECgQJBQAAAA==.Stripez:BAAALgADCgUJBwAAAA==.Stumpvee:BAAALgADCgMJAwAAAA==.',
Su='Sunmx:BAAALgAFFAIJAgAAAA==.Superdark:BAAALgAECgMJAwAAAA==.',
Sw='Swurves:BAAALgAECgIJAgABLgAECgcJGAAeAO8dAA==.',
Sy='Sybrooker:BAAALgADCgMJBAAAAA==.',
Ta='Taedrum:BAAALgAECgQJBAAAAA==.Taerror:BAACLgAFFH8RAAIhAAUJ1B9MAQD/AQAhAAUJ1B9MAQD/AQAuAAQKfywABCEACQmyI34AAK8DACEACQmyI34AAK8DABoAAgl5GE5FAI8AABgAAQktB8dVAC8AAAAA.Tahkon:BAAALgAECgYJCwAAAA==.Tahmtan:BAAALgADCgcJEAAAAA==.Talegos:BAAALgAECgQJBAAAAA==.Talonfel:BAAALgADCgcJCwABLgAECggJMQAlAOojAA==.Talonflight:BAAALgAECgQJBAABLgAECggJMQAlAOojAA==.Talonstryke:BAABLgAECn8xAAIlAAgJ6iNkAgAwAwAlAAgJ6iNkAgAwAwAAAA==.Tanarious:BAAALgADCgQJBAAAAA==.Taytonar:BAABLgAECn8fAAIGAAcJTAc0GADVAAAGAAcJTAc0GADVAAAAAA==.',
Te='Teamocil:BAAALgAECgEJAwAAAA==.Teefa:BAAALgAECgYJCwAAAA==.Tehrror:BAAALgADCgMJAwAAAA==.Tenths:BAAALgADCgEJAQAAAA==.Terak:BAAALgAECgEJAQAAAA==.Tevers:BAAALgADCgcJDAAAAA==.',
Th='Thane:BAAALgADCgMJAwAAAA==.Thaumium:BAAALgADCgEJAQAAAA==.Theenforcer:BAABLgAECn8eAAIDAAgJow3PQACDAQADAAgJow3PQACDAQAAAA==.Theguyfurry:BAAALgADCgcJCwAAAA==.Thidwick:BAAALgAECgQJCAABLgAECggJJQAKAMAZAA==.Thingtwø:BAAALgAECgIJAgAAAA==.Thirdryker:BAAALgADCgIJAgAAAA==.Thistle:BAAALgAECgEJAQAAAA==.Thorissa:BAABLgAECn8YAAIMAAgJzA0OEwCzAQAMAAgJzA0OEwCzAQAAAA==.Thäne:BAABLgAECn8XAAITAAcJ6hC6QQB3AQATAAcJ6hC6QQB3AQAAAA==.',
Ti='Tickletorque:BAAALgAECgUJBgABLgAFFAMJCgATADYlAA==.Tikimon:BAAALgADCgIJAgAAAA==.Tiles:BAAALgAECgEJAQAAAA==.Timojj:BAAALgAECgEJAwAAAA==.Tinglu:BAAALgADCgcJCQAAAA==.Tinkk:BAAALgAECgYJDAAAAA==.Titø:BAAALgAECgYJCwAAAA==.',
To='Tomorrow:BAACLgAFFH8HAAIPAAQJKxcIJABgAQAPAAQJKxcIJABgAQAuAAQKfxgAAg8ACAllHfROAEoCAA8ACAllHfROAEoCAAAA.Topdog:BAAALgAECgQJBAAAAA==.Topzee:BAAALgAECgQJBwAAAA==.Torquin:BAAALgADCgMJAwAAAA==.Tottytotems:BAAALgADCgcJDAAAAA==.Touchmablade:BAAALgADCgQJBAAAAA==.',
Tr='Traylo:BAAALgAECgYJEgAAAA==.Treysong:BAAALgADCgMJAwAAAA==.',
Tu='Turkeymm:BAAALgADCgMJAwAAAA==.',
Tv='Tvak:BAABLgAECn8fAAIDAAkJHCAnDQCXAgADAAkJHCAnDQCXAgAAAA==.',
Tw='Twopump:BAABLgAECn8cAAIDAAcJuQbUgQDoAAADAAcJuQbUgQDoAAAAAA==.',
Ty='Tygrarelea:BAAALgAECgEJAQAAAA==.Tynan:BAAALgADCgMJBQAAAA==.Tyrah:BAAALgADCgQJBQAAAA==.',
Ul='Ulinova:BAAALgAECgYJEwAAAA==.',
Ur='Uroro:BAAALgAECggJBwAAAA==.',
Uu='Uu:BAABLgAFFH8HAAMUAAMJBAFtHABdAAAIAAIJ1wAuNQBnAAAUAAIJ6wBtHABdAAAAAA==.',
Va='Vaiden:BAAALgADCgEJAQAAAA==.Vainqueur:BAAALgAECgYJCgAAAA==.Valoroso:BAAALgAECgQJBAAAAA==.Vanarios:BAAALgAECgEJAgAAAA==.Vanderius:BAAALgAECgEJAQAAAA==.Vanderpal:BAAALgADCggJBgAAAA==.Vanec:BAAALgADCgMJAwAAAA==.Varm:BAAALgAECgEJAQAAAA==.Vasarian:BAAALgAECgEJAQAAAA==.',
Ve='Veidima:BAAALgAECgQJBgAAAA==.Veigar:BAAALgADCgYJBgAAAA==.Velathrus:BAAALgADCgEJAQAAAA==.Velion:BAAALgAECgIJAwAAAA==.Verzweifeln:BAAALgAECgQJBQAAAA==.Vesenya:BAAALgAECgEJAQAAAA==.Veyez:BAAALgADCgkJDAAAAA==.',
Vh='Vhyrix:BAAALgAECgQJBQAAAA==.',
Vi='Viantel:BAAALgAECgYJEAAAAA==.Viklicious:BAAALgADCgkJCQAAAA==.Vinarn:BAABLgAECn8oAAMTAAgJQw1LPwB/AQATAAgJtQtLPwB/AQAgAAYJAg0ACgAzAQAAAA==.Vinyls:BAAALgAECgIJAgAAAA==.Viridias:BAAALgADCgEJAQAAAA==.Viridius:BAAALgAECgIJBAAAAA==.Virindi:BAAALgAECgEJAQAAAA==.Vishouspayne:BAAALgAECgMJBQAAAA==.',
Vr='Vrogar:BAAALgAECgcJCQAAAA==.',
Vy='Vyntage:BAAALgAECgcJCQAAAA==.',
['Vä']='Väelün:BAABLgAECn8iAAINAAcJMhIzSAAgAQANAAcJMhIzSAAgAQABLgAECggJHgAOACcKAA==.',
Wa='Wachoosh:BAAALgAECgQJBgAAAA==.Wackamoose:BAABLgAECn8hAAQCAAcJQh3aBQAPAgACAAcJQh3aBQAPAgAZAAQJ7g5zMADAAAABAAIJmgdYlgBnAAAAAA==.Wagoogusmay:BAAALgAECgEJAQAAAA==.Waidmanns:BAABLgAECn8lAAMHAAgJmRrsHQBSAgAHAAgJmRrsHQBSAgAVAAUJZBIZHQAaAQAAAA==.Walkinredflg:BAAALgADCgYJBgAAAA==.Walvet:BAAALgAECgYJEgAAAA==.Warc:BAAALgADCgUJBQAAAA==.Wargramps:BAAALgADCgQJBAAAAA==.Warrioo:BAAALgADCgMJAwABLgAECgcJBgAFAAAAAA==.',
We='Weather:BAAALgADCgUJBQAAAA==.Weelad:BAAALgADCgkJFAAAAA==.Weldord:BAABLgAECn8rAAIHAAYJWw22WwBVAQAHAAYJWw22WwBVAQAAAA==.',
Wh='Whatorne:BAAALgAECgUJBgAAAA==.Whatyamean:BAAALgADCgEJAQAAAA==.Whiskeytaur:BAAALgADCgYJBgAAAA==.',
Wi='Wickedchick:BAAALgAECgYJDQAAAA==.Willowknight:BAAALgADCgcJEAAAAA==.',
Wo='Wolvareene:BAAALgADCgcJBwAAAA==.',
Wr='Wrenn:BAAALgAECgEJAQAAAA==.Wrongknight:BAAALgAECgQJCgAAAA==.Wrongname:BAAALgAECgUJEAAAAA==.',
Xa='Xalthérion:BAAALgAECgMJAwAAAA==.',
Xe='Xeruu:BAAALgADCgUJBQAAAA==.',
Xo='Xolan:BAACLgAFFH8FAAIEAAIJKQ2yGwCOAAAEAAIJKQ2yGwCOAAAuAAQKfx0AAgQACAkQGtUkACYCAAQACAkQGtUkACYCAAAA.',
Xp='Xprophet:BAAALgAECgQJCgAAAA==.',
Xu='Xunghuai:BAAALgADCgcJBwAAAA==.',
Xw='Xw:BAAALgADCgYJCwAAAA==.',
Ye='Yemonyunter:BAAALgADCgUJBQAAAA==.Yesyesyes:BAAALgADCgIJAgAAAA==.',
Yo='Yogsothoth:BAEBLgAECn8hAAMHAAgJehRjJADEAQAHAAgJfRNjJADEAQAVAAYJjBBdFgBjAQAAAA==.Yooloakala:BAAALgADCggJCAAAAA==.Yormaum:BAAALgADCgYJBgAAAA==.Yosha:BAAALgADCgcJCQAAAA==.',
Za='Zaartyn:BAAALgAECgcJEQAAAA==.Zalupalkys:BAAALgAECgQJAwAAAA==.Zarexion:BAAALgADCggJDAAAAA==.',
Ze='Zeebeth:BAAALgAECggJEQAAAA==.Zefi:BAAALgAECgQJDAAAAA==.Zerokai:BAAALgAECgQJBAAAAA==.',
Zh='Zhahira:BAAALgAECgUJCgAAAA==.',
Zi='Zipsy:BAABLgAECn8nAAIPAAgJ0A0VRQCYAQAPAAgJ0A0VRQCYAQAAAA==.',
Zo='Zomlo:BAAALgAECgEJAQAAAA==.Zonka:BAAALgAECgEJAQABLgAECgcJGwAYAMQIAA==.',
Zu='Zumtobel:BAAALgAECgMJBgAAAA==.Zuuko:BAACLgAFFH8XAAIUAAQJgyKhAgCYAQAUAAQJgyKhAgCYAQAuAAQKfxwAAhQACQlKJKAGABUDABQACQlKJKAGABUDAAAA.',
Zy='Zyreth:BAAALgAECgEJAQAAAA==.',
['Ár']='Árthur:BAAALgAECgUJBwAAAA==.',
['År']='Åres:BAAALgAECgMJBgAAAA==.',
['Îs']='Îsadora:BAAALgADCgYJCQAAAA==.',
['Ýe']='Ýe:BAAALgADCgYJBgAAAA==.',
['ßu']='ßuzzibee:BAAALgAECgUJCQABLgAFFAEJAQAFAAAAAA==.',
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

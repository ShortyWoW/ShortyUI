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

local lookup = {'Mage-Frost','Warlock-Demonology','DemonHunter-Devourer','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','Evoker-Preservation','Warlock-Destruction','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Hunter-Survival','Warrior-Arms','Warlock-Affliction','Paladin-Protection','DeathKnight-Frost','Paladin-Retribution','Druid-Restoration','Priest-Shadow','Evoker-Devastation','Hunter-Marksmanship','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Fury','Druid-Guardian','Paladin-Holy','Shaman-Enhancement','Warrior-Protection','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','Mage-Arcane','Mage-Fire','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abacinate:BAAALgADCggJCAAAAA==.Abadawn:BAAALgAECgEJAQAAAA==.Abrigo:BAAALgAECgYJDgAAAA==.',
Ac='Actafool:BAAALgADCgEJAQAAAA==.',
Ae='Aelas:BAAALgAECgMJAwAAAA==.',
Ak='Akanerogue:BAAALgADCgYJBgAAAA==.',
Al='Alaanz:BAAALgAECgIJAgAAAA==.Aladriian:BAAALgAECgIJAgAAAA==.Alestranza:BAAALgAECgUJDAAAAA==.Aletamale:BAAALgADCgEJAQAAAA==.Alpharatz:BAABLgAECn8bAAIBAAgJhhx/BgBGAgABAAgJhhx/BgBGAgAAAA==.Altfacts:BAEALgAECgEJAQABLgAFFAUJDQACACYNAA==.Alumat:BAAALgAECgYJCQAAAA==.Aluminore:BAAALgAECgYJBwAAAA==.',
Am='Amunwrath:BAAALgAECgYJDgAAAA==.',
An='Anatharion:BAAALgAECgUJCQAAAA==.Angel:BAAALgADCggJDQAAAA==.Annari:BAABLgAECn8aAAIDAAcJmRROFgBLAQADAAcJmRROFgBLAQAAAA==.Anunaki:BAAALgAECgMJAwABLgAECgYJGAAEADEhAA==.Anùbìs:BAAALgADCgYJCAAAAA==.',
Ao='Aozera:BAAALgAECgYJDAABLgABCgQJAQAFAAAAAA==.',
Ar='Arakh:BAAALgADCgUJBQAAAA==.Araleana:BAAALgAECgEJAQAAAA==.Arazarke:BAAALgAECgYJDQAAAA==.Archidan:BAAALgAECgMJAwAAAA==.Argias:BAAALgAECgQJBgAAAA==.Arkoric:BAAALgAECgYJAQAAAA==.Armian:BAAALgADCgYJEgAAAA==.Artemais:BAAALgADCgYJBgABLgAFFAQJCwAGANkUAA==.Aru:BAABLgAFFH8HAAIHAAMJJxY9DgD0AAAHAAMJJxY9DgD0AAAAAA==.Arzed:BAAALgAECgQJCAAAAA==.',
As='Asaki:BAAALgAFFAEJAQAAAA==.Asarmaul:BAAALgAECgUJDQAAAA==.Ashbringa:BAAALgADCgkJJAAAAA==.Ashtongue:BAECLgAFFH8NAAMCAAUJJg34BwBCAQACAAUJFw34BwBCAQAIAAIJpwYqDgCbAAAuAAQKfyYAAwIACQnHICkfAJwCAAIACQnpHCkfAJwCAAgABQkwIhwNAPIBAAAA.Ashtonguetwo:BAEBLgAECn8XAAMCAAgJyBEPiABJAQACAAYJQw4PiABJAQAIAAMJWxgxOgDLAAABLgAFFAUJDQACACYNAA==.Associate:BAAALgADCgcJCAAAAA==.Asteran:BAAALgAECgYJCgAAAA==.',
At='Atalantia:BAAALgAECgMJBAABLgAECggJHgAGAC0VAA==.Atheîst:BAAALgAECgEJAQAAAA==.Athrú:BAAALgADCgYJBgAAAA==.Athèná:BAAALgADCgYJBwABLgADCgYJCAAFAAAAAA==.Atiesh:BAAALgADCgEJAQAAAA==.Atza:BAABLgAECn8eAAIGAAgJLRUPXwDWAQAGAAgJLRUPXwDWAQAAAA==.',
Au='Aurorawrynn:BAAALgAECgMJAwAAAA==.',
Av='Avanoria:BAAALgAECgIJAgAAAA==.',
Aw='Awa:BAAALgADCgMJAwAAAA==.Awakarih:BAAALgADCgEJAQAAAA==.Aweyna:BAAALgAECgEJAQAAAA==.',
Ax='Axetogrind:BAAALgADCgcJBwAAAA==.',
Ay='Ayvero:BAABLgAECn8ZAAIJAAYJEBVtRwCUAQAJAAYJEBVtRwCUAQAAAA==.',
Az='Azelia:BAAALgAECgYJDAAAAA==.Azgrumaul:BAAALgADCgcJDAAAAA==.Azhagthefang:BAAALgADCgMJAwAAAA==.Azin:BAAALgAFFAEJAQAAAA==.Azureky:BAAALgAECgYJDwAAAA==.Azurepriest:BAABLgAECn8XAAMKAAcJnw7EIgB+AQAKAAcJnw7EIgB+AQALAAQJtwPZYwCfAAAAAA==.Azuric:BAABLgAECn8WAAIMAAYJjBoZJgDMAQAMAAYJjBoZJgDMAQAAAA==.',
Ba='Babzz:BAAALgAECgYJCAAAAA==.Badfelix:BAABLgAECn8uAAMNAAgJKhoKBAA3AgANAAgJKhoKBAA3AgAOAAEJ3QGblgAcAAAAAA==.Ballfro:BAAALgADCgcJBwABLgADCggJCAAFAAAAAA==.Bammboo:BAAALgAECgUJBgAAAA==.Bandage:BAAALgAECgEJAQAAAA==.Bania:BAAALgADCgEJAQABLgAECgQJBgAFAAAAAA==.Bapster:BAAALgAFFAIJAgAAAA==.Barbatoz:BAAALgADCgcJBwAAAA==.Barbs:BAABLgAECn8dAAMPAAcJsx4qBQDWAQAPAAcJsx4qBQDWAQAQAAEJPwptfwAxAAAAAA==.',
Bb='Bbr:BAAALgADCgYJBgAAAA==.',
Be='Bearbeár:BAAALgADCgIJAgAAAA==.Beauxyy:BAAALgAECgYJEAAAAA==.Bedrock:BAAALgAECgYJDwAAAA==.Beebzy:BAAALgADCgQJBAAAAA==.Beezycakez:BAAALgAECgYJDAAAAA==.',
Bg='Bgneedwork:BAABLgAECn8eAAMCAAgJ0hi/CQDVAQACAAgJ0hi/CQDVAQAIAAEJDxdzagA9AAAAAA==.',
Bi='Billidari:BAAALgAECgQJBwABLgAECggJIwACAI4eAA==.Binkies:BAABLgAECn8UAAIEAAcJoxiaBwCCAQAEAAcJoxiaBwCCAQAAAA==.Bittermonk:BAAALgADCgQJBAAAAQ==.Bixby:BAAALgADCgIJAgAAAA==.',
Bj='Bjartskular:BAAALgAECgcJBwAAAA==.',
Bl='Blachdeath:BAAALgAECgMJAgABLgAECgYJBgAFAAAAAA==.Blachloch:BAAALgAECgYJBgAAAA==.Blasco:BAAALgAECgYJCAAAAA==.Blazedin:BAAALgAECgMJBQAAAA==.Blaçkheart:BAAALgAECgEJAgAAAA==.Bleumachine:BAAALgADCgEJAQAAAA==.Blingtron:BAAALgADCgEJAQAAAA==.Blodhwar:BAAALgAECgEJAwABLgAECgcJBwAFAAAAAA==.Bloodeagle:BAAALgADCgYJBgAAAA==.Bluecashew:BAAALgADCgMJAwAAAA==.',
Bo='Boeds:BAAALgAECgYJDgAAAA==.Bombae:BAAALgADCgYJBgAAAA==.Bombgoesboom:BAAALgAECgYJDQABLgAECgcJCAAFAAAAAA==.Bonanorn:BAABLgAECn8WAAMJAAYJYw+MXwBJAQAJAAYJKA+MXwBJAQARAAYJ2Qo+CgD3AAAAAA==.',
Br='Braeni:BAAALgADCgEJAQAAAA==.Brakii:BAAALgADCgYJCAAAAA==.Brandra:BAAALgAECgcJCAAAAA==.Brawns:BAABLgAECn8ZAAISAAcJmRxiBwBJAgASAAcJmRxiBwBJAgABLgAECggJHwATANAaAA==.Braér:BAAALgADCgcJCgAAAA==.Breakout:BAAALgADCgQJBAAAAA==.Brena:BAAALgADCgMJAwAAAA==.Brendasonng:BAAALgADCgYJCQAAAA==.Brewsleeroy:BAAALgADCgcJBwAAAA==.Brine:BAAALgADCgUJBQAAAA==.Brisktwo:BAAALgADCgMJAwAAAA==.Bromall:BAAALgAECgUJEgAAAA==.Brotar:BAAALgAECgUJBgAAAA==.Brucewee:BAAALgADCgcJDQAAAA==.Bruceweë:BAAALgADCgkJDwAAAA==.Brusly:BAAALgADCgcJEgAAAA==.Bryxie:BAAALgADCgQJBAABLgABCgIJAgAFAAAAAA==.',
Bu='Bubax:BAAALgADCgUJBQABLgAECggJHgAGAKkjAA==.Bubbes:BAABLgAECn8WAAIUAAYJfR+kDQDsAQAUAAYJfR+kDQDsAQAAAA==.Bubbleosevén:BAAALgAECgQJBQAAAA==.Bubpix:BAAALgADCgYJBgAAAA==.Buggasm:BAAALgADCgkJFQAAAA==.Bunghoolio:BAAALgADCgYJBgAAAA==.Bunnyjuice:BAAALgADCgYJCQAAAA==.Burtgummer:BAAALgAECgEJAQAAAA==.Buscemimi:BAAALgADCgMJAwAAAA==.',
Ca='Calcub:BAAALgAECgUJCAAAAA==.Calystalyn:BAECLgAFFH8LAAIKAAQJZBsfCABaAQAKAAQJZBsfCABaAQAuAAQKfxwAAwoACAmoGjkQADwCAAoACAmoGjkQADwCAAsAAwkZDhliAKgAAAAA.Cancercowboy:BAAALgADCgUJBQAAAA==.Carcass:BAABLgAECn8cAAMGAAgJTAm2kABfAQAGAAgJNQm2kABfAQAVAAMJsQOLEQB5AAAAAA==.Carelyda:BAAALgADCgYJCQABLgAECgIJAgAFAAAAAA==.Carramrod:BAAALgAECgUJBwAAAA==.Catheria:BAAALgADCgQJBAABLgAECgYJGAAEADEhAA==.Catheriana:BAABLgAECn8WAAIWAAYJfxh1YwC7AQAWAAYJfxh1YwC7AQAAAA==.',
Ce='Cemus:BAAALgAECgYJBgAAAA==.',
Ch='Chaar:BAAALgADCgkJCQAAAA==.Chach:BAAALgAECgYJBgAAAA==.Chadgpt:BAAALgAECgYJEgAAAA==.Chalupurss:BAAALgAECgYJBgAAAA==.Chanthony:BAAALgADCgYJBgAAAA==.Chantzie:BAAALgAECggJDgAAAA==.Charming:BAAALgAECgQJBAAAAA==.Chawkdruid:BAABLgAECn8WAAIXAAgJAxvuJwAVAgAXAAgJAxvuJwAVAgAAAA==.Chrav:BAAALgADCgQJBAAAAA==.Chris:BAAALgAECgQJBAAAAA==.Christmass:BAAALgAECgMJAwAAAA==.Chronpurp:BAAALgAFFAEJAQAAAA==.Chuglover:BAAALgAECgYJDwAAAA==.Chupmode:BAACLgAFFH8JAAIYAAQJ5RChBQDpAAAYAAQJ5RChBQDpAAAuAAQKfx4AAhgACAmaH1EMAL4CABgACAmaH1EMAL4CAAAA.',
Ci='Cincy:BAAALgADCgUJBQAAAA==.Cindragosa:BAABLgAECn8aAAIZAAgJxB1YBQCpAgAZAAgJxB1YBQCpAgABLgAFFAUJFQAaAN8ZAA==.',
Cl='Clawmaine:BAAALgAECgQJBAAAAA==.Clem:BAAALgADCgkJCQAAAA==.Cleophatra:BAAALgADCggJDgAAAA==.Clunts:BAAALgADCgUJBQABLgAECgIJAgAFAAAAAA==.',
Co='Cobarr:BAABLgAECn8UAAMCAAgJWRBSHAA2AQACAAYJVA9SHAA2AQAIAAIJeRZ0SwCLAAAAAA==.Colauris:BAABLgAECn8XAAIbAAYJkwoZCwAhAQAbAAYJkwoZCwAhAQAAAA==.Combustion:BAAALgAECgYJDAAAAA==.Courserlul:BAABLgAECn8UAAIDAAcJuR3hRgDYAQADAAcJuR3hRgDYAQABLgAFFAgJIQACAPkjAA==.Cowtoes:BAAALgADCgUJBQABLgAECgcJGwARAGsVAA==.',
Cr='Craodin:BAAALgAECgYJCgAAAA==.Craydaughter:BAABLgAECn8aAAMcAAcJ6SB8AQAxAgAcAAcJciB8AQAxAgAdAAYJ1xylCQDTAQAAAA==.Crinkleberry:BAAALgADCgMJAwAAAA==.',
['Cá']='Cály:BAEALgADCgUJBQABLgAFFAQJCwAKAGQbAQ==.',
Da='Daddy:BAAALgAECgQJBAABLgAFFAYJFQAOALkVAA==.Daddyops:BAAALgAECgYJDwAAAA==.Dahl:BAAALgADCgEJAgAAAA==.Daliserna:BAAALgAECgYJEgAAAA==.Dangohealing:BAAALgAECgQJBwAAAA==.Dante:BAAALgADCgMJAwAAAA==.Darklabel:BAAALgADCgYJBwAAAA==.Darkmayhm:BAAALgADCgUJCQAAAA==.Dathrustae:BAABLgAECn8UAAMJAAYJOBIBTACFAQAJAAYJOBIBTACFAQAaAAEJSQK5lgAhAAAAAA==.Dathumpy:BAABLgAECn8VAAIeAAcJEwRQFgDkAAAeAAcJEwRQFgDkAAAAAA==.Davriel:BAABLgAECn8ZAAIIAAcJCRqzCAA2AgAIAAcJCRqzCAA2AgAAAA==.',
De='Deafheaven:BAAALgAECgUJBQAAAA==.Deatherselfs:BAAALgAECgYJEwAAAA==.Deathex:BAAALgAECgEJAQAAAA==.Deatheyes:BAAALgADCgEJAQAAAA==.Deathkorg:BAAALgAECgQJCAAAAA==.Deathkuma:BAAALgAECgMJBAABLgAECgYJCwAFAAAAAA==.Deex:BAAALgADCgcJBwAAAA==.Deggs:BAAALgADCgIJAgAAAA==.Demonbarbie:BAAALgAECgYJEQAAAA==.Demoniyt:BAAALgADCgQJBAABLgAECgIJAwAFAAAAAA==.Demonloch:BAAALgADCgcJBwABLgAECgYJBgAFAAAAAA==.Derekthegood:BAAALgADCgIJAgAAAA==.Dereliction:BAAALgAECgYJEwAAAA==.Derood:BAAALgAECgEJAQAAAA==.Desertfox:BAAALgAECgcJBwAAAA==.Dethsong:BAABLgAECn8WAAIDAAYJzRvIHQAZAQADAAYJzRvIHQAZAQAAAA==.Dezalan:BAAALgADCgMJBgAAAA==.',
Dh='Dheid:BAAALgAECgMJAwAAAA==.',
Di='Diadem:BAAALgAECgYJCAAAAA==.Diesels:BAAALgADCggJCAAAAA==.Dihruid:BAAALgAECgYJCwAAAA==.Dihscipline:BAAALgADCgUJBQAAAA==.Dillusion:BAAALgAECgQJDAAAAA==.Dinkdonk:BAAALgAECgYJBwAAAA==.Dinkdonkin:BAAALgAECgEJAQAAAA==.Diodoesdmg:BAABLgAECn8eAAIJAAcJfRgZLgD6AQAJAAcJfRgZLgD6AQAAAA==.Dipsnchip:BAAALgAECgUJBQABLgAECggJGAAfAAAcAA==.Discodizz:BAAALgAECgYJDgAAAA==.Discold:BAABLgAECn8hAAIKAAgJCyRAAwA5AwAKAAgJCyRAAwA5AwAAAA==.Dizzynight:BAAALgAECgYJBgAAAA==.',
Dj='Djent:BAAALgAECgYJDgAAAA==.',
Dk='Dklulz:BAACLgAFFH8FAAIGAAMJ8wySGgCcAAAGAAMJ8wySGgCcAAAuAAQKfyMAAgYACQn6HvQKAEMDAAYACQn6HvQKAEMDAAAA.Dkp:BAAALgAECgYJCAAAAA==.',
Do='Dobetter:BAAALgADCgYJBgABLgAECgcJCAAFAAAAAA==.Docked:BAAALgAECgkJCQAAAA==.Domochevsky:BAAALgAECgYJCQAAAA==.Domonkasshu:BAAALgADCgUJCQAAAA==.Domowarsky:BAAALgADCgUJBQAAAA==.Dorland:BAAALgAECgEJAQAAAA==.Doxa:BAABLgAECn8ZAAMgAAcJrQbSWwANAQAgAAYJvwbSWwANAQAWAAcJUAM0KQD+AAAAAA==.',
Dr='Draac:BAAALgAECgcJDwAAAA==.Dragonaire:BAAALgADCgEJAQAAAA==.Dragondk:BAAALgAECgMJBQAAAA==.Dragondots:BAAALgADCgcJCAABLgAECgMJBQAFAAAAAA==.Dranek:BAAALgAECgQJCAAAAA==.Dranzamewmew:BAAALgAECgYJCgAAAA==.Dratnuh:BAABLgAECn8UAAMJAAcJUh/fHQBTAgAJAAcJKR7fHQBTAgAaAAYJ5RubMgCiAQAAAA==.Dreadnaught:BAAALgAECgMJAwABLgAECgkJIAASAA8VAA==.Droes:BAAALgAECgQJCAAAAA==.Dropaganda:BAABLgAECn8cAAIhAAgJYw7JDQDgAQAhAAgJYw7JDQDgAQAAAA==.Drorian:BAAALgAECgQJBgAAAA==.Drosselmeyer:BAAALgADCgcJBwAAAA==.Drtotem:BAAALgAECgQJBwAAAA==.Drwigglesz:BAAALgAECgUJBQABLgAECgQJBQAFAAAAAA==.Dryeth:BAAALgADCgcJCQAAAA==.Drîfter:BAAALgADCgIJAgAAAA==.',
Du='Duckpond:BAABLgAECn8ZAAIEAAcJORt+HgAOAgAEAAcJORt+HgAOAgAAAA==.Dulgan:BAAALgADCgUJBQAAAA==.Durandal:BAAALgAECgUJCAABLgAECgYJEAAFAAAAAA==.Durrtybao:BAAALgAECgYJBgAAAA==.',
Ec='Ecksman:BAABLgAECn8YAAIPAAcJvSE6AwAhAgAPAAcJvSE6AwAhAgAAAA==.Ectheliön:BAAALgAECgQJBAABLgAECggJHwARAHASAA==.Ecthyma:BAAALgAECgEJAgABLgAECgUJBgAFAAAAAA==.',
Eg='Egars:BAAALgAECgQJBgAAAA==.',
Ei='Eillonwy:BAABLgAECn8eAAIUAAcJiSTyAABcAgAUAAcJiSTyAABcAgAAAA==.',
Ek='Ekho:BAAALgAECgQJDwAAAA==.',
El='Elice:BAABLgAECn8dAAMaAAgJrhikHAA/AgAaAAgJrhikHAA/AgARAAYJdgqFBwA/AQAAAA==.Elitextony:BAAALgAECgEJAQAAAA==.',
Em='Ember:BAACLgAFFH8KAAIJAAUJrRKFBAA3AQAJAAUJrRKFBAA3AQAuAAQKfxwAAgkACAkLIxUFADwDAAkACAkLIxUFADwDAAAA.Emobuzz:BAABLgAECn8YAAMCAAgJyCE0AgCLAgACAAgJyCE0AgCLAgATAAEJAACgCQAAAAAAAA==.',
En='Enzymes:BAAALgAECgMJBAAAAA==.',
Er='Eremes:BAABLgAECn8VAAMDAAcJexzQOAARAgADAAcJexzQOAARAgAcAAIJFw0vYQBdAAAAAA==.Ereshkigal:BAABLgAECn8XAAIIAAYJUxoHAgCHAQAIAAYJUxoHAgCHAQAAAA==.',
Es='Escaflowne:BAAALgAECgQJBQAAAA==.Eskenny:BAAALgAECgIJAgAAAA==.Esperranza:BAABLgAECn8WAAMTAAYJugzCDABrAQATAAYJywvCDABrAQACAAQJowfD1QCuAAAAAA==.Espurr:BAABLgAECn8ZAAIXAAgJhCKmAQDIAgAXAAgJhCKmAQDIAgAAAA==.',
Et='Eturnal:BAAALgAECgUJCgAAAA==.',
Ev='Evadriel:BAABLgAECn8aAAILAAgJrSRLAAA0AwALAAgJrSRLAAA0AwAAAA==.Evylet:BAAALgAECgQJBAABLgAECggJGgALAK0kAA==.',
Fa='Fact:BAAALgAECggJDgAAAA==.Faeris:BAABLgAECn8hAAIXAAgJ5AujTQBtAQAXAAgJ5AujTQBtAQAAAA==.Faexi:BAAALgADCgMJAwAAAA==.Fallstone:BAAALgAECgYJEgAAAA==.Faroreswind:BAABLgAECn8UAAIfAAYJgAfyHwCfAAAfAAYJgAfyHwCfAAAAAA==.Fatchance:BAAALgAECgQJBAAAAA==.Fayline:BAAALgAFFAEJAgAAAA==.',
Fe='Feacialiale:BAAALgAECgQJCAAAAA==.Felbladekid:BAAALgAECgYJEQAAAA==.Felcollins:BAAALgADCgIJAgAAAA==.Fellspawn:BAAALgADCgQJBQABLgAECggJHwARAHASAA==.Felmartyr:BAAALgADCgMJAwAAAA==.Felslinger:BAAALgAECgEJAgAAAA==.Feralblood:BAAALgADCgEJAQAAAA==.',
Fi='Fikkle:BAAALgADCgYJBgAAAA==.Fishmoony:BAAALgAECgEJAQAAAA==.Fisttoface:BAAALgAECgQJBwAAAA==.Fitchner:BAAALgAECgUJBQAAAA==.Fiyt:BAAALgAECgIJAwAAAA==.',
Fl='Flappyz:BAAALgAECgEJAQABLgAECgcJGQAEADkbAA==.Flashoflulz:BAAALgAECgEJAQAAAA==.',
Fo='Fortysouls:BAAALgADCgMJAwAAAA==.',
Fr='Freadrick:BAAALgADCgMJAwAAAA==.Freddyp:BAABLgAECn8bAAMWAAcJCyPSHQC4AgAWAAcJCyPSHQC4AgAUAAEJ2xBIRgAoAAAAAA==.Freddyy:BAAALgAECgQJBAAAAA==.Freyahweaver:BAAALgAECgEJAQAAAA==.Friarpuck:BAABLgAECn8aAAIXAAYJkhZJFAAlAQAXAAYJkhZJFAAlAQAAAA==.Frostchi:BAABLgAECn8fAAMPAAgJFRhfBADxAQAPAAgJFRhfBADxAQAQAAIJiAH+dgA8AAAAAA==.Frosteye:BAAALgAECgIJAgAAAA==.Frostfu:BAAALgADCgUJCQAAAA==.Frozensalt:BAABLgAECn8jAAIBAAgJnyNYAgC7AgABAAgJnyNYAgC7AgAAAA==.Fryssa:BAAALgAECgEJAQAAAA==.Fríend:BAAALgADCgEJAQAAAA==.',
Fu='Fu:BAAALgADCggJCAAAAA==.Fullbritney:BAAALgAECgEJAQAAAA==.Furiá:BAAALgAECgIJAgAAAA==.Furrbaby:BAAALgAECgYJCgAAAA==.Furyness:BAAALgADCgUJAgAAAA==.Futter:BAAALgAECgYJEwAAAA==.Fuzhun:BAAALgAECgEJAQAAAA==.',
Fy='Fyrn:BAAALgAECgQJBgAAAA==.',
Ga='Gabbroh:BAAALgAECgIJAgAAAA==.Galiphe:BAABLgAECn8bAAIiAAgJ+A9JBQBjAQAiAAgJ+A9JBQBjAQAAAA==.Ganna:BAAALgAECgMJAwAAAA==.Garidan:BAABLgAECn8YAAQdAAcJ2ROkEwAYAQAdAAUJURSkEwAYAQAcAAYJCwsDDADOAAADAAUJrwJDtwCYAAAAAA==.Gaymenology:BAAALgADCgMJAwAAAA==.',
Ge='Geeyyanni:BAABLgAECn8VAAIjAAgJJgr8BwBsAQAjAAgJJgr8BwBsAQAAAA==.Geldanger:BAAALgAECgIJAgAAAA==.Geno:BAAALgAECgQJBAAAAA==.Genodruid:BAAALgAECgkJCAAAAA==.Genopaladin:BAAALgAFFAQJBAAAAA==.Geopetal:BAABLgAECn8ZAAMkAAcJFBM9DwC6AQAkAAcJFBM9DwC6AQAXAAEJxwHF5QAgAAAAAA==.Gex:BAAALgAECgQJBQAAAA==.',
Gi='Gilia:BAAALgAECgEJAQAAAA==.Gingy:BAABLgAECn8YAAIlAAgJCCIWAQBqAgAlAAgJCCIWAQBqAgAAAA==.',
Gl='Gladefresh:BAAALgAECgYJDwAAAA==.Glae:BAAALgADCgEJAQABLgAECgQJBwAFAAAAAA==.Glok:BAAALgAECgYJCwAAAA==.',
Gn='Gnomealone:BAABLgAECn8XAAIeAAcJUhw4LwDzAQAeAAcJUhw4LwDzAQAAAA==.',
Go='Goldenice:BAAALgAECgYJCwAAAA==.Goliad:BAAALgADCgYJCwABLgADCgkJEwAFAAAAAA==.Gorannak:BAAALgADCgYJCQAAAA==.Gornur:BAAALgADCgMJBwAAAA==.',
Gr='Grandcruu:BAABLgAECn8VAAIgAAUJmRs/PwB7AQAgAAUJmRs/PwB7AQAAAA==.Grinzler:BAABLgAECn8lAAQRAAgJZRkWBgBmAQARAAgJzxAWBgBmAQAaAAUJ9RNJRwA2AQAJAAQJKyD9bAAhAQAAAA==.Gross:BAAALgADCgkJCQAAAA==.',
Gu='Guappo:BAAALgAECgUJBgAAAA==.Guldanshower:BAAALgADCgEJAQAAAA==.Gulrok:BAAALgADCgEJAQAAAA==.Gundric:BAAALgAECgYJCgAAAA==.Gundrul:BAAALgADCgcJCgAAAA==.Gunt:BAAALgAECgYJCgAAAA==.Gustavericus:BAAALgADCgQJBAAAAA==.',
Gw='Gwynlok:BAAALgADCgkJEAAAAA==.',
['Gä']='Gähl:BAAALgADCgUJBQAAAA==.',
Ha='Hafwyn:BAABLgAECn8dAAMLAAgJ6hMlBAD9AQALAAgJ6hMlBAD9AQAYAAEJcQndYQA0AAAAAA==.Hammerhai:BAAALgADCgQJBAABLgAECgIJAgAFAAAAAA==.Hammy:BAAALgADCgkJEwABLgAECgQJCAAFAAAAAA==.Handjabz:BAAALgAECgQJBAAAAA==.Hannage:BAAALgAECgQJBAAAAA==.Harlot:BAAALgAECgcJEQAAAA==.Harribel:BAAALgADCgYJBgAAAA==.Harrizune:BAAALgADCggJCwAAAA==.Harthus:BAAALgAECgcJBwABLgAFFAMJCAAPAGkKAA==.Hathawtelyot:BAAALgADCgIJAgAAAA==.Haunteddrank:BAAALgAECgYJCgAAAA==.Haveashot:BAAALgADCgMJAwAAAA==.Hayley:BAAALgAECgMJAwAAAA==.',
He='Healabull:BAAALgAECgEJAQAAAA==.Healarious:BAAALgADCgYJCgAAAA==.Healshim:BAAALgADCggJBwAAAA==.Healstrong:BAAALgADCgYJBgAAAA==.Healìn:BAAALgADCgYJBgABLgAECggJHwAgALshAA==.Hellballz:BAAALgAFFAMJAwAAAA==.Hellsprince:BAAALgAECgQJBAAAAA==.Hemphog:BAAALgADCgQJBQAAAA==.Hephaistion:BAAALgADCgEJAQAAAA==.Hexxer:BAAALgADCgkJCQAAAA==.',
Hi='Hilamâry:BAAALgAECgUJBQAAAA==.',
Ho='Holker:BAAALgADCgYJBgABLgAFFAUJDgAjAEEMAA==.Holyhavok:BAAALgADCgUJCAAAAA==.Holymacaroli:BAAALgAECgIJAgAAAA==.Holymeow:BAAALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Holysmiter:BAAALgAECgUJBgAAAA==.Holywood:BAAALgADCgUJBgAAAA==.Hornsstar:BAAALgAECgEJAQABLgAECgcJGwARAGsVAA==.Hots:BAAALgADCgYJBwABLgAECgYJCAAFAAAAAA==.Hoverboots:BAAALgAECgIJAgAAAA==.',
Hu='Huberto:BAAALgAECgQJDAAAAA==.Huntiing:BAAALgADCggJEwABLgAECggJIAAWAPYcAA==.Hupyaptelyot:BAAALgAECgEJAQAAAA==.Hurtsdonut:BAAALgAECgEJAgAAAA==.',
Hy='Hyruledrood:BAAALgAECgEJAQAAAA==.Hytierea:BAABLgAECn8gAAIWAAgJag3oFAB6AQAWAAgJag3oFAB6AQAAAA==.',
Ic='Icedøut:BAAALgADCgMJAwAAAA==.Icemaneli:BAAALgADCgMJAwAAAA==.',
Il='Ilbs:BAAALgADCgkJJAAAAA==.Ilgal:BAAALgAECgIJAgAAAA==.Illidurrty:BAAALgAECgQJBAABLgAECgYJBgAFAAAAAA==.Ilocku:BAAALgAFFAMJBwAAAQ==.',
Im='Impulsé:BAAALgADCgYJCwAAAA==.Imsosmol:BAABLgAECn8WAAIOAAgJUwUgDwAVAQAOAAgJUwUgDwAVAQAAAA==.Imunderaged:BAABLgAECn8cAAIiAAgJlxgRDABKAgAiAAgJlxgRDABKAgAAAA==.',
In='Incubus:BAABLgAECn8ZAAIdAAgJNiNGAACzAgAdAAgJNiNGAACzAgAAAA==.Infectum:BAABLgAECn8fAAIGAAgJEx46JgCjAgAGAAgJEx46JgCjAgAAAA==.Innout:BAAALgAECgYJBgAAAA==.',
Ir='Iriemon:BAAALgAECgYJDgAAAA==.',
Is='Isabeau:BAAALgAECgQJBAAAAA==.Issowimonk:BAAALgADCgkJJQABLgAECgYJFwAhAFAVAA==.Issowipriest:BAAALgADCggJDgABLgAECgYJFwAhAFAVAA==.Issowishaman:BAABLgAECn8XAAIhAAYJUBUfBQBQAQAhAAYJUBUfBQBQAQAAAA==.',
It='Italiaa:BAAALgAECgUJCAAAAA==.Itzzack:BAAALgAECgUJBQAAAA==.',
Ix='Ixtel:BAAALgAECgUJCAAAAA==.',
Ja='Jabundi:BAAALgAECgEJAQAAAA==.Jacalo:BAAALgADCgYJDAAAAA==.Jaidy:BAAALgAECgcJEwAAAA==.Janapoundmor:BAAALgAECgYJEQAAAA==.Jaslynn:BAAALgADCgUJEAAAAA==.',
Je='Jedakye:BAABLgAECn8YAAIJAAcJ+BXlFwA8AQAJAAcJ+BXlFwA8AQAAAA==.Jenzypoo:BAAALgADCgcJDAAAAA==.Jerzzarn:BAAALgADCgMJAwAAAA==.',
Ji='Jintae:BAABLgAECn8aAAIPAAgJwBsIAgBwAgAPAAgJwBsIAgBwAgAAAA==.',
Jm='Jmama:BAAALgAECgQJBgAAAA==.',
Jo='Jojo:BAABLgAECn8eAAMCAAgJLRz9CQDTAQACAAYJ2xv9CQDTAQAIAAMJpxj8MQDwAAAAAA==.Jolder:BAAALgAECgYJCQAAAA==.Jordanary:BAAALgADCgkJHQAAAA==.Jorkin:BAAALgAECgYJEAAAAA==.Joseyindiana:BAAALgADCgkJFAABLgAECgYJEwAFAAAAAA==.',
Jp='Jpow:BAAALgAECgcJDQAAAA==.',
Ju='Jumae:BAAALgADCgMJAwAAAA==.Junnarma:BAAALgAECgYJDQAAAA==.Justbetta:BAAALgADCgMJBQABLgAECgcJCAAFAAAAAA==.',
['Já']='Járnviðr:BAABLgAECn8fAAMRAAgJcBIdBACtAQAJAAcJnw7nNwDOAQARAAcJLBMdBACtAQAAAA==.',
['Jé']='Jérrex:BAAALgAECgIJAgAAAA==.',
Ka='Kaalias:BAAALgAECgUJBQAAAA==.Kabaneri:BAAALgAECgcJDgAAAA==.Kabrax:BAAALgAECgEJAQAAAA==.Kadreu:BAAALgADCgEJAQAAAA==.Kaedara:BAAALgAECggJDwABLgABCgQJAQAFAAAAAA==.Kaeyda:BAABLgAECn8YAAIQAAgJBBh+FgA0AgAQAAgJBBh+FgA0AgAAAA==.Kai:BAAALgAECgIJAgABLgAFFAQJCAAXAJwXAA==.Kaiula:BAABLgAECn8UAAIgAAcJJRRKNQCnAQAgAAcJJRRKNQCnAQAAAA==.Kakegurui:BAAALgAECgMJAwAAAA==.Kalimbrimor:BAAALgADCgQJBAAAAA==.Kalnath:BAABLgAECn8hAAIdAAkJcB34AgC6AgAdAAkJcB34AgC6AgAAAA==.Kalynnah:BAABLgAECn8XAAIWAAYJph77SQAFAgAWAAYJph77SQAFAgAAAA==.Kanatoo:BAAALgAFFAIJAwAAAA==.Kanekisenpai:BAACLgAFFH8LAAICAAQJMBGsCAA6AQACAAQJMBGsCAA6AQAuAAQKfygAAwIACAlLIZ8QAPUCAAIACAlLIZ8QAPUCAAgAAQkAAG1rADwAAAAA.Kanjam:BAABLgAECn8hAAMmAAgJIyKNAAAqAwAmAAgJIyKNAAAqAwAnAAIJ/xarCwB3AAAAAA==.Kassandra:BAAALgADCgUJBQAAAA==.Kazimist:BAAALgAECgEJAgABLgAECgIJAgAFAAAAAA==.Kazit:BAABLgAECn8YAAMOAAcJsxBnDgAdAQAOAAYJtBBnDgAdAQANAAcJTggGXAAaAQAAAA==.Kazrar:BAAALgAECgMJAwAAAA==.',
Ke='Keakdasneak:BAAALgAECgQJBwABLgAECggJIQABAJEaAA==.Kelai:BAACLgAFFH8MAAIlAAQJ9BsmBQBRAQAlAAQJ9BsmBQBRAQAuAAQKfxwAAiUACQlJGaUJAIMCACUACQlJGaUJAIMCAAAA.Kelitha:BAAALgADCgEJAgAAAA==.Kellion:BAAALgAECgUJCAAAAA==.Keystoned:BAAALgAECgIJAgAAAA==.Keèy:BAAALgADCgYJCwAAAA==.',
Kh='Khonsu:BAAALgADCggJCAAAAA==.',
Ki='Kittypride:BAAALgAECgYJEAAAAA==.Kiwi:BAAALgAECgQJBAAAAA==.',
Kn='Kneenja:BAAALgAECgYJDgAAAA==.Knottinburst:BAAALgADCgcJDgAAAA==.',
Ko='Koda:BAAALgAECgUJCgAAAA==.Kolaghan:BAAALgADCgEJAQAAAA==.Koltiera:BAABLgAECn8XAAIGAAYJWxx3FwBWAQAGAAYJWxx3FwBWAQAAAA==.Konfucius:BAABLgAECn8bAAIDAAgJRh+VAwBlAgADAAgJRh+VAwBlAgAAAA==.',
Kr='Krump:BAABLgAECn8gAAIWAAgJ9hz+BQA0AgAWAAgJ9hz+BQA0AgAAAA==.Krìtta:BAAALgAECgEJAQAAAA==.',
Ku='Kuldruid:BAAALgADCgkJCQAAAA==.Kulpriest:BAACLgAFFH8FAAIKAAMJ9AgSBwDYAAAKAAMJ9AgSBwDYAAAuAAQKfyEAAgoACAkUHkwJAKYCAAoACAkUHkwJAKYCAAAA.Kuramá:BAAALgAECgYJCgAAAA==.Kuyà:BAAALgAECgYJEAAAAA==.Kuzé:BAABLgAECn8VAAMRAAYJ6Bq6DgDZAQARAAYJ6Bq6DgDZAQAJAAEJuxJ+1QAvAAAAAA==.',
Kw='Kwok:BAAALgADCgMJAwAAAA==.Kwyjibo:BAACLgAFFH8LAAMGAAUJvQXrEQDbAAAGAAQJvQXrEQDbAAAlAAEJAADcDwAAAAAuAAQKfxoAAgYABwn7Gd0PAJgBAAYABwn7Gd0PAJgBAAAA.',
Ky='Kyyguy:BAAALgAECgMJAwAAAA==.',
['Ké']='Kénpachi:BAAALgAECgcJCQAAAA==.',
['Kí']='Kítkatz:BAAALgADCgEJAQAAAA==.',
['Kï']='Kïllerfrost:BAAALgAECggJCgAAAA==.',
La='Lanana:BAABLgAECn8bAAICAAcJSxAtbgCEAQACAAcJSxAtbgCEAQAAAA==.Lanmythe:BAABLgAECn8XAAIGAAcJgBYGFAByAQAGAAcJgBYGFAByAQAAAA==.Larien:BAAALgAECgYJBwAAAA==.Lastrite:BAAALgADCgEJAQAAAA==.',
Le='Lectracutie:BAAALgADCgQJBAAAAA==.Ledin:BAAALgADCgYJBgAAAA==.Leonidas:BAAALgAECgQJBgAAAA==.Letmitt:BAAALgAECgIJAgAAAA==.',
Lh='Lhatso:BAAALgADCggJEAABLgAECgIJAgAFAAAAAA==.',
Li='Liannia:BAAALgADCgYJBgAAAA==.Lightningki:BAAALgAECgUJCAAAAA==.Lightofdawn:BAAALgAECgYJDAAAAA==.Liianâ:BAAALgADCgkJCgAAAA==.Liigghtt:BAAALgADCgIJAgAAAA==.Lilshoobs:BAAALgAECgYJEgAAAA==.Lindir:BAAALgADCgkJIwAAAA==.Lipapriesty:BAAALgAECgIJAgABLgAECggJHAAWABYRAA==.Liparoonie:BAABLgAECn8cAAIWAAgJFhFSVwDcAQAWAAgJFhFSVwDcAQAAAA==.Lirina:BAAALgADCgEJAQAAAA==.Lithice:BAAALgADCgkJJAABLgAECgYJFwAUAHETAA==.Lizardalgaib:BAAALgADCgMJAwABLgAECgYJCQAFAAAAAA==.',
Ll='Llordros:BAAALgADCgEJAQAAAA==.',
Lo='Lockedupfoo:BAACLgAFFH8MAAICAAQJcxv8AwBzAQACAAQJcxv8AwBzAQAuAAQKfyQAAwIACAmCJHMDAF0CAAIACAnoI3MDAF0CAAgAAglpI5E5AM4AAAAA.Lockfour:BAAALgAECgYJBgAAAA==.Lodi:BAAALgADCgYJCQABLgAECggJGQAdADYjAA==.Loggerhead:BAAALgADCgMJBgAAAA==.Lolmindflay:BAAALgADCgkJJAAAAA==.Lomund:BAAALgAECgIJAgAAAA==.Lorchah:BAAALgAECgYJDQAAAA==.Lorgash:BAAALgAECgIJAwAAAA==.Lostara:BAAALgADCgMJAwAAAA==.Lostindeath:BAAALgAECgIJAgAAAA==.Lothrik:BAAALgADCgEJAQAAAA==.Loti:BAAALgAECgEJAQAAAA==.Loubie:BAAALgADCgQJCAAAAA==.',
Lu='Lunah:BAABLgAECn8YAAILAAgJhhpoAwAcAgALAAgJhhpoAwAcAgAAAA==.Lunamos:BAAALgAECgQJBwAAAA==.Lussty:BAAALgAECgIJAgAAAA==.Luuppo:BAABLgAECn8XAAIPAAgJJAvtCABmAQAPAAgJJAvtCABmAQAAAA==.Luzhun:BAAALgADCgcJDwAAAA==.',
Ma='Machahunt:BAAALgADCgUJCAAAAA==.Machico:BAABLgAECn8bAAMkAAgJdxphDAD0AQAkAAYJcR1hDAD0AQAMAAUJUg7TRQAWAQAAAA==.Macks:BAAALgAECgYJCAAAAA==.Madsin:BAAALgADCgcJDAAAAA==.Maetha:BAAALgAECgQJBgAAAA==.Mages:BAAALgADCgIJAgAAAA==.Magetinyt:BAABLgAECn8ZAAIBAAgJSBTJFACbAQABAAgJSBTJFACbAQAAAA==.Maggo:BAAALgADCgUJBQAAAA==.Magicalpssy:BAABLgAECn8XAAIBAAcJghQiegDeAQABAAcJghQiegDeAQAAAA==.Magicbebo:BAAALgADCgcJBwAAAA==.Magicdeadly:BAAALgAECgYJCgAAAA==.Magicianing:BAAALgADCgQJBAAAAA==.Magina:BAAALgAECgYJDwAAAA==.Magosika:BAABLgAECn8XAAILAAgJeAYlRQAkAQALAAgJeAYlRQAkAQAAAA==.Magyarkrisp:BAAALgADCgIJAgAAAA==.Maiev:BAAALgAECgEJAQAAAA==.Maldeamon:BAAALgAECgQJBwAAAA==.Maledizione:BAAALgAECgcJEQAAAA==.Mannfred:BAAALgADCgcJDgAAAA==.Maomi:BAAALgADCgkJFAAAAA==.Massaspligga:BAAALgADCgMJAwAAAA==.Mastafister:BAAALgAECgQJBgAAAA==.Matora:BAAALgAECgQJBAAAAA==.Maxbadly:BAABLgAECn8hAAIPAAgJvR84CADTAgAPAAgJvR84CADTAgAAAA==.Mazrim:BAAALgADCgIJAgAAAA==.',
Mc='Mcfly:BAAALgAECgQJCAAAAA==.Mcspanky:BAAALgAECgIJAgAAAA==.Mctàvish:BAAALgAECgQJBAAAAA==.',
Me='Medeus:BAAALgADCgcJDwAAAA==.Medívh:BAAALgADCgUJBQAAAA==.Megahorn:BAABLgAECn8cAAMcAAcJzBVFLQBgAQADAAcJIRCWXACLAQAcAAYJvxhFLQBgAQAAAA==.Meid:BAAALgAECgQJCQAAAA==.Meloras:BAAALgAECgEJAQAAAA==.Menily:BAAALgADCgYJBgABLgAECggJIgAHAGwXAA==.Merpp:BAAALgAECgcJEwAAAA==.',
Mf='Mfhambone:BAAALgAECgQJBAAAAA==.',
Mi='Mikki:BAAALgAECgQJBgAAAA==.Mikkilina:BAAALgAECgcJDAAAAA==.Milesdavis:BAABLgAECn8eAAIOAAgJ8h+qCwDfAgAOAAgJ8h+qCwDfAgAAAA==.Minarax:BAABLgAECn8UAAIiAAcJtAwiCAAOAQAiAAcJtAwiCAAOAQAAAA==.Minishadow:BAAALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Mitric:BAAALgAECgYJCQAAAA==.',
Mm='Mmeow:BAAALgAECgYJCgAAAA==.Mmeows:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.',
Mo='Momasan:BAAALgAECgQJBgAAAA==.Moograine:BAAALgADCgYJBgAAAA==.Moowarrior:BAAALgAECgYJDgAAAA==.Moozhu:BAAALgADCgkJFgAAAA==.Mordion:BAAALgADCgIJAgAAAA==.Mordred:BAAALgAECgQJBAAAAA==.',
Mu='Murman:BAAALgAECgQJCAAAAA==.Muse:BAAALgAECggJEAAAAA==.',
My='Mynx:BAAALgAECgEJAwAAAA==.',
['Mâ']='Mârk:BAAALgADCgYJBwAAAA==.',
['Mé']='Ménéthil:BAAALgAECgEJAQAAAA==.',
['Mö']='Möthug:BAAALgAECgYJCQAAAA==.',
Na='Nalla:BAAALgAECgYJBwAAAA==.Naoz:BAAALgAECgMJBQAAAA==.Naroon:BAAALgADCgYJBgAAAA==.Nater:BAAALgAECgYJDwAAAA==.Nateshot:BAABLgAECn8ZAAMaAAgJ0BuyFACKAgAaAAgJ0BuyFACKAgAJAAUJKBTgGwAfAQAAAA==.Naturaleza:BAAALgADCgkJDgAAAA==.',
Ne='Nekkrosys:BAABLgAECn8bAAIGAAgJSQuTDgClAQAGAAgJSQuTDgClAQAAAA==.Nekrron:BAABLgAECn8XAAIlAAYJgBICHgBZAQAlAAYJgBICHgBZAQAAAA==.Nemosis:BAAALgAECgEJAQAAAA==.',
Ni='Niceandslow:BAAALgAECgQJCQAAAA==.Nightshaed:BAAALgAECgEJAQAAAA==.Nitroxic:BAAALgADCgMJBQAAAA==.',
No='Noggenus:BAAALgADCgYJBgAAAA==.Nohozkohkoh:BAAALgAECgQJCAAAAA==.Nork:BAAALgAECgUJCAAAAA==.Normalname:BAAALgAECgIJAwAAAA==.Novembër:BAABLgAECn8bAAQTAAgJNg17DgBKAQACAAgJYgt9hgBNAQATAAYJFA17DgBKAQAIAAQJfQgUQAC0AAAAAA==.',
Nu='Nullarion:BAAALgAECgQJBwAAAA==.',
Ny='Nylons:BAAALgADCgYJBwAAAA==.',
Nz='Nzô:BAAALgAECgEJAQAAAA==.',
['Në']='Nëøs:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøbødy:BAAALgADCgIJAwAAAA==.',
Ok='Okishama:BAACLgAFFH8LAAMOAAQJ4BJsAwA8AQAOAAQJ4BJsAwA8AQANAAIJ0RHGGQCUAAAuAAQKfycAAw4ACAmWITQMANgCAA4ACAmWITQMANgCAA0ABgm+GMM8AI4BAAAA.',
On='Onkrack:BAAALgADCgYJCwAAAA==.',
Oo='Ooga:BAAALgAECgEJAQAAAA==.',
Or='Orchiecktomi:BAAALgAECgUJBgAAAA==.Oreofresh:BAAALgADCgEJAQAAAA==.',
Ot='Otrhunter:BAAALgADCgUJBQAAAA==.',
Ow='Owlfliction:BAAALgAECggJDwAAAA==.',
Oz='Ozwiz:BAAALgADCgMJAwABLgAECgYJGAAEADEhAA==.',
Pa='Papaosote:BAAALgAECgIJAgAAAA==.Paradoxlost:BAAALgADCgMJAwAAAA==.Parox:BAAALgADCggJDQABLgAECgUJBQAFAAAAAA==.Patbee:BAAALgAECgIJAgAAAA==.Paykun:BAAALgAECgUJCgAAAA==.',
Pb='Pbexpress:BAAALgAECgQJDAAAAA==.',
Pe='Persëphone:BAAALgADCgIJAgABLgADCgYJCAAFAAAAAA==.',
Ph='Phatê:BAAALgAECgIJAgAAAA==.Phoenix:BAAALgADCgEJAQAAAA==.',
Pi='Picesty:BAABLgAECn8YAAIBAAcJXRf9bAD7AQABAAcJXRf9bAD7AQAAAA==.Pilikiä:BAAALgAECgQJBAAAAA==.Piteä:BAAALgADCgIJAgAAAA==.',
Pk='Pkflash:BAABLgAECn8WAAIgAAYJCwYdWwAQAQAgAAYJCwYdWwAQAQAAAA==.',
Pl='Pleabsham:BAABLgAECn8aAAIhAAcJASPkAABSAgAhAAcJASPkAABSAgAAAA==.',
Po='Pocketank:BAAALgAECgkJBwABLgAFFAQJBAAFAAAAAA==.Poggy:BAAALgAECgQJBAAAAA==.Posenpo:BAAALgADCgUJBQAAAA==.Potlogic:BAAALgAECgYJDwABLgAECggJIQABAJEaAA==.Powderberryz:BAAALgAECgYJBgAAAA==.',
Pr='Praesolus:BAABLgAECn8YAAILAAcJ8RzMAgA0AgALAAcJ8RzMAgA0AgAAAA==.Prep:BAAALgAECgIJAwAAAA==.Priesttinyt:BAAALgAECgQJBAAAAA==.Probstoned:BAAALgAECgcJBwABLgAECggJFAALABciAA==.',
Ps='Pssygrip:BAAALgAECgcJBwAAAA==.',
Pu='Puddl:BAAALgAECgUJCQAAAA==.Pugs:BAAALgAECgIJAgAAAA==.Punchdrunk:BAAALgADCgIJAgAAAA==.Punkii:BAABLgAECn8fAAIJAAcJyCTVDwC8AgAJAAcJyCTVDwC8AgAAAA==.Punnisher:BAAALgADCgkJIwAAAA==.Puntard:BAAALgADCgIJAgAAAA==.Purdee:BAAALgAECgQJBwAAAA==.',
Py='Pyró:BAAALgAECgUJCAAAAA==.',
Qp='Qpawnz:BAAALgAECgEJAQABLgAFFAUJDAACAKISAA==.',
Qt='Qtshift:BAABLgAECn8eAAIkAAcJPiB2CQA8AgAkAAcJPiB2CQA8AgAAAA==.',
Qu='Quanonshaman:BAAALgAECgEJAQAAAA==.Quatermain:BAAALgAFFAIJAgAAAA==.Quidamtyra:BAABLgAECn8WAAIoAAYJ4BihBAC8AQAoAAYJ4BihBAC8AQAAAA==.Quigonjin:BAABLgAECn8dAAIWAAgJzRtmIACqAgAWAAgJzRtmIACqAgAAAA==.Quivton:BAAALgADCgcJBQAAAA==.',
Ra='Raahm:BAAALgADCgUJBQAAAA==.Raazaa:BAABLgAECn8UAAMeAAYJnB0rJwAiAgAeAAYJnB0rJwAiAgASAAEJcgFRSwAJAAAAAA==.Rabbifrost:BAABLgAECn8nAAIYAAcJWyKOAgApAgAYAAcJWyKOAgApAgAAAA==.Rackham:BAACLgAFFH8IAAIPAAMJaQrUDADYAAAPAAMJaQrUDADYAAAuAAQKfx8AAg8ACAl9GakSADsCAA8ACAl9GakSADsCAAAA.Radiana:BAABLgAECn8YAAIXAAcJcBl8CgCwAQAXAAcJcBl8CgCwAQAAAA==.Raeknor:BAAALgAECgYJDwAAAA==.Ragequit:BAAALgADCgQJBAABLgAECgQJBwAFAAAAAA==.Raldoron:BAAALgAECgEJAQAAAA==.Ramone:BAAALgAECgUJBgAAAA==.Randymarsh:BAAALgADCgcJBwAAAA==.Rankoneahri:BAAALgAECgYJCwAAAA==.Rathvyr:BAACLgAFFH8LAAIeAAQJbh8aAQB/AQAeAAQJbh8aAQB/AQAuAAQKfycAAh4ACAlhJeQEAFoDAB4ACAlhJeQEAFoDAAAA.Razuriell:BAABLgAECn8WAAIDAAYJbB9eNgAdAgADAAYJbB9eNgAdAgABLgAECgcJEQAFAAAAAA==.',
Re='Rebeakah:BAABLgAECn8hAAQSAAgJHRYBDQDPAQASAAgJ8w0BDQDPAQAiAAYJdhmZBACAAQAeAAYJExIiTAB1AQAAAA==.Redbash:BAAALgAECgQJBAAAAA==.Redcast:BAAALgADCgUJBQAAAA==.Redcrusader:BAAALgADCgEJAQAAAA==.Redjudgment:BAAALgADCgUJBQAAAA==.Redlightning:BAAALgAECgQJBgAAAA==.Redpriest:BAAALgADCgYJCQAAAA==.Reggs:BAAALgAECgcJFgAAAQ==.Relick:BAABLgAECn8YAAIOAAgJ7Q+XCAB1AQAOAAgJ7Q+XCAB1AQAAAA==.Reminara:BAABLgAECn8gAAMDAAgJbhu6DwCIAQADAAgJiRm6DwCIAQAcAAYJ0RMUKwBuAQAAAA==.Renia:BAAALgAECgEJAgAAAA==.Renko:BAABLgAECn8cAAIQAAgJex9nAQBiAgAQAAgJex9nAQBiAgAAAA==.Restartpal:BAAALgAECgcJCAAAAA==.Restocol:BAAALgAECgMJAwAAAA==.Retnoob:BAAALgADCgYJBgAAAA==.',
Rh='Rhylea:BAAALgADCgEJAQAAAA==.',
Ri='Ribitey:BAACLgAFFH8OAAILAAUJsyIjAAALAgALAAUJsyIjAAALAgAuAAQKfykAAgsACAmdJuEAAIgDAAsACAmdJuEAAIgDAAAA.Riggins:BAAALgADCgUJBQAAAA==.Rigginss:BAAALgAECgUJCQAAAA==.Rilakuma:BAAALgAECgMJBAABLgAECgYJCwAFAAAAAA==.Ripfappening:BAAALgAECgIJAgAAAA==.Riptubes:BAEALgAECgYJEQAAAA==.',
Ro='Robuchiha:BAAALgADCgEJAQAAAA==.Roguspanish:BAAALgADCgQJBwAAAA==.Rolando:BAAALgAECgMJAwAAAA==.Rollcall:BAAALgADCgEJAwABLgAECgEJAQAFAAAAAA==.Rosemika:BAAALgADCgcJDQAAAA==.Roserage:BAAALgAECgMJAwAAAA==.Roycold:BAAALgAECgEJAQAAAA==.Rozewyn:BAABLgAECn8XAAILAAgJbwPWDwDzAAALAAgJbwPWDwDzAAAAAA==.',
Ru='Rukator:BAAALgAECgUJBQAAAA==.Rumstein:BAAALgADCgYJBgAAAA==.',
Ry='Ryawhitefang:BAABLgAECn8aAAIJAAYJ6h5LJgAhAgAJAAYJ6h5LJgAhAgAAAA==.Ryli:BAAALgAECgMJBgAAAA==.Ryvoon:BAAALgAECgYJDwAAAA==.',
Sa='Sackandballs:BAAALgAECgUJBwABLgAECgcJCAAFAAAAAA==.Saeris:BAABLgAECn8fAAIYAAgJehe7BQCwAQAYAAgJehe7BQCwAQAAAA==.Sagesop:BAAALgAECgYJCgAAAA==.Salael:BAABLgAECn8WAAIkAAcJ1Bb5DADpAQAkAAcJ1Bb5DADpAQAAAA==.Salyndra:BAAALgADCgcJBwAAAA==.Samaythe:BAAALgADCgIJAgAAAA==.Sandswift:BAAALgADCgUJBQAAAA==.Sanguinerex:BAAALgAECgEJAgAAAA==.Sanpei:BAAALgAECgYJDwAAAA==.Saphi:BAAALgAECgEJAQAAAA==.Saphielle:BAAALgAECgQJBAAAAA==.Saphirei:BAAALgADCgMJAwAAAA==.Saphirin:BAACLgAFFH8LAAIlAAQJ5heGAgAxAQAlAAQJ5heGAgAxAQAuAAQKfyMAAiUACAlDHn8KAHECACUACAlDHn8KAHECAAAA.Sardon:BAAALgADCgEJAQAAAA==.Sav:BAAALgADCgEJAQAAAA==.Savagebrain:BAAALgADCgIJAgABLgAECgcJFgABAAggAA==.Savagelung:BAABLgAECn8WAAIBAAcJCCBiOgCNAgABAAcJCCBiOgCNAgAAAA==.Sawako:BAACLgAFFH8HAAILAAIJyBfXDACXAAALAAIJyBfXDACXAAAuAAQKfygAAwsACQnmFWYQAGECAAsACQnmFWYQAGECAAoABQk/BBg+ALwAAAAA.',
Sc='Schutzengel:BAABLgAECn8bAAINAAgJrh8tDQC0AgANAAgJrh8tDQC0AgAAAA==.Scorcht:BAEALgAECgkJDQAAAA==.Scribbl:BAABLgAECn8pAAMIAAgJ5iRSBwBTAgAIAAYJPSNSBwBTAgACAAUJqiPQCQDVAQAAAA==.Scyllia:BAAALgAECgcJCAAAAA==.Scylon:BAABLgAECn8ZAAIUAAgJVB6oBAC3AgAUAAgJVB6oBAC3AgAAAA==.',
Se='Seiric:BAABLgAECn8aAAIDAAgJNw+qUgCsAQADAAgJNw+qUgCsAQAAAA==.Selinda:BAAALgAECgcJDgAAAA==.Senzamira:BAAALgAECgQJBwAAAA==.Seraka:BAAALgAECgQJBwAAAA==.Sevenfold:BAAALgADCgkJFAAAAA==.',
Sh='Shacobar:BAAALgADCgcJEAABLgAECggJFAACAFkQAA==.Shadowbanned:BAAALgAECgYJCgAAAA==.Shadowscream:BAABLgAECn8gAAQCAAcJdiXMDgCbAQACAAUJaCXMDgCbAQATAAMJyyQABADYAAAIAAEJAABYWABlAAAAAA==.Shallowgrave:BAABLgAECn8ZAAMVAAgJYhSTAQCeAQAVAAgJYhSTAQCeAQAGAAYJugaOtAAZAQAAAA==.Shampoo:BAAALgAECgUJBgAAAA==.Shamram:BAAALgAECgYJCgAAAA==.Shamywamy:BAAALgAECgYJEQAAAA==.Shaodk:BAAALgAECgUJDwAAAA==.Shathar:BAAALgADCgEJAQAAAA==.Shayamalan:BAAALgAECgYJBgAAAA==.Shenron:BAAALgAECgMJCQAAAA==.Shidazz:BAAALgADCgMJAwAAAA==.Shidoshi:BAAALgADCgEJAQAAAA==.Shiffty:BAAALgADCgEJAQABLgAECgUJBgAFAAAAAA==.Shiftedvolts:BAAALgADCggJCAAAAA==.Shikanshi:BAAALgADCgQJBAAAAA==.Shindra:BAAALgADCgcJBwABLgAECgcJGwAiABYOAA==.Shocknlawl:BAAALgADCgkJGAAAAA==.Shwingg:BAAALgAECgYJDwAAAA==.Shäde:BAACLgAFFH8MAAIbAAQJIBlNAgBrAQAbAAQJIBlNAgBrAQAuAAQKfx4AAhsACAlqGzIOALwCABsACAlqGzIOALwCAAAA.Shöckadin:BAAALgAECgIJAgAAAA==.',
Si='Siastra:BAAALgAECgIJAgAAAA==.Siek:BAAALgADCgIJAgAAAA==.Sintura:BAABLgAECn8fAAIGAAkJ6RYiMwBqAgAGAAkJ6RYiMwBqAgAAAA==.',
Sk='Skiethx:BAACLgAFFH8NAAIbAAUJSCGwBQCFAQAbAAUJSCGwBQCFAQAuAAQKfx4AAhsACAmKI4gDAGQDABsACAmKI4gDAGQDAAAA.Skipii:BAAALgAECgYJCwAAAA==.Skor:BAAALgADCgcJCQAAAA==.Skullderz:BAAALgAECgEJAQABLgAECggJFwARABcjAA==.Skullderzii:BAAALgADCgMJAwABLgAECggJFwARABcjAA==.Skullderziix:BAAALgAECgYJDgABLgAECggJFwARABcjAA==.Skullderzvi:BAAALgADCgIJAgABLgAECggJFwARABcjAA==.Skullderzxx:BAABLgAECn8XAAIRAAgJFyNJAwD2AgARAAgJFyNJAwD2AgAAAA==.Skullderzz:BAAALgAECgIJAgABLgAECggJFwARABcjAA==.Skullzfist:BAAALgADCgEJAQAAAA==.',
Sl='Sleighty:BAAALgAECgEJAQAAAA==.Slopersafari:BAABLgAECn8fAAIBAAgJxRjiFwCGAQABAAgJxRjiFwCGAQAAAA==.',
Sm='Smashbro:BAAALgAECgQJBAABLgAECgcJGQAEADkbAA==.Smashyz:BAAALgAECgYJCgABLgAECgcJGQAEADkbAA==.Smc:BAAALgAECgUJBwAAAA==.Smitherz:BAAALgAECgQJBgAAAA==.Smokinfist:BAAALgADCgcJCQABLgAECggJGQAaANAbAA==.Smoothbrain:BAAALgAECgYJBgAAAA==.',
Sn='Sniffle:BAAALgADCgcJAQAAAA==.',
So='Solitudes:BAAALgADCgEJAQAAAA==.Somaria:BAAALgAECgYJBwAAAA==.Souldarkelf:BAAALgADCgMJAwAAAA==.Soulie:BAAALgAECgEJAgAAAA==.Soundz:BAAALgAECgcJCgAAAA==.',
Sp='Spadersage:BAAALgADCgkJEwAAAA==.Spankydrood:BAAALgAECgEJAQAAAA==.Spankyrogue:BAACLgAFFH8HAAIbAAMJYghSBwDGAAAbAAMJYghSBwDGAAAuAAQKfxUAAhsACAngG08TAH4CABsACAngG08TAH4CAAAA.Sparkie:BAAALgAECgYJDwAAAA==.Spartus:BAAALgAECgMJAwABLgAECgYJDwAFAAAAAA==.Spazie:BAAALgAECgYJDwAAAA==.Spellbonk:BAAALgAECgYJDgAAAA==.Spikethenoob:BAAALgADCgYJDgAAAA==.Spikè:BAAALgAECgEJAQAAAA==.Spookypedo:BAAALgADCgcJBwABLgAECgYJCwAFAAAAAA==.',
Sq='Squee:BAABLgAECn8aAAIeAAgJmhhsGQCAAgAeAAgJmhhsGQCAAgAAAA==.Squirts:BAAALgADCgMJAwAAAA==.',
Sr='Srmonkey:BAAALgAECgMJAwAAAA==.',
St='Stabachacha:BAACLgAFFH8HAAIbAAQJ5AilCgBFAQAbAAQJ5AilCgBFAQAuAAQKfyAAAxsACAkFIeYJAPQCABsACAkFIeYJAPQCACkAAQkEHX4aAFQAAAAA.Star:BAAALgAECgYJCAAAAA==.Steamknight:BAAALgAECgYJCAAAAA==.Sth:BAABLgAECn8XAAIOAAkJoBaoEwCCAgAOAAkJoBaoEwCCAgAAAA==.Stille:BAAALgAECgIJAgAAAA==.Stinkie:BAAALgAECgUJBQABLgABCgUJDwAFAAAAAA==.Stonebeard:BAAALgAECgIJBAABLgAECgQJBgAFAAAAAA==.Stonedpriest:BAABLgAECn8UAAILAAgJFyJwAAAOAwALAAgJFyJwAAAOAwAAAA==.Stongman:BAAALgADCgYJCwAAAA==.Stormblessed:BAAALgAECgYJDwAAAA==.Stormy:BAAALgADCgEJAgAAAA==.Strepitant:BAAALgADCgEJAQAAAA==.Strixie:BAAALgAECgcJCwAAAA==.Styion:BAAALgAECgYJCwAAAA==.Stymonic:BAAALgAECgIJAgAAAA==.',
Su='Sunwind:BAAALgADCgUJBQAAAA==.Supernóva:BAAALgADCgIJAgABLgAECgQJBgAFAAAAAA==.Superr:BAAALgADCgUJBQAAAA==.Superspiffy:BAAALgADCgEJAQAAAA==.Surgate:BAAALgAECgYJDwAAAA==.Suriell:BAAALgAECgcJEQAAAA==.',
Sw='Swampybutt:BAAALgAECgYJCgAAAA==.Sweepingfear:BAAALgADCgcJCAAAAA==.Swiftxo:BAAALgAECgQJBQAAAA==.',
Sy='Sylveon:BAAALgAECgQJDwAAAA==.Sylverarrow:BAAALgAECgUJBwAAAA==.Synga:BAAALgAECgQJBAAAAA==.Syradea:BAAALgAECgIJAgAAAA==.',
['Sä']='Säcktapper:BAAALgADCgMJAwAAAA==.Sämael:BAAALgADCgIJAQAAAA==.',
Ta='Tadorcha:BAAALgAECgQJEAAAAA==.Taijing:BAAALgADCgIJAgAAAA==.Taikwon:BAAALgAECgMJAwAAAA==.Taliesin:BAAALgADCgEJAQAAAA==.Tallow:BAABLgAECn8gAAIeAAgJDxKsCgB0AQAeAAgJDxKsCgB0AQAAAA==.Tanksahoy:BAAALgADCgEJAQAAAA==.Tarkarram:BAAALgAECgYJDgAAAA==.Tarnfair:BAAALgAECgIJAgAAAA==.Taurìel:BAAALgADCgIJAgAAAA==.Taven:BAAALgAECgUJCAAAAA==.',
Te='Technique:BAAALgAECgYJDwAAAA==.Teedd:BAAALgADCgQJBAAAAA==.Tekka:BAAALgAECgYJDwAAAA==.Telvor:BAAALgAECgUJBQAAAA==.Teminar:BAAALgAECgQJBgAAAA==.Terrukk:BAAALgAECgQJCAAAAA==.Teufelsnudel:BAABLgAECn8bAAIeAAgJwwuYCQCFAQAeAAgJwwuYCQCFAQAAAA==.',
Th='Thealdrin:BAAALgADCgEJAQABLgAECggJFgAbAFgRAA==.Thefreák:BAAALgADCgkJFQAAAA==.Thelysong:BAAALgAECgIJAgAAAA==.Themdraz:BAAALgAECgEJAQAAAA==.Therran:BAABLgAECn8XAAIUAAYJcRPhGQBCAQAUAAYJcRPhGQBCAQAAAA==.Theterror:BAAALgADCgYJBgAAAA==.Theuss:BAAALgAECgcJCgAAAA==.Thexador:BAAALgAECgMJAwAAAA==.Thiccjimmy:BAABLgAECn8aAAIWAAcJzQ2mGQBWAQAWAAcJzQ2mGQBWAQAAAA==.Thorkell:BAAALgAECgQJBwAAAA==.Thorraden:BAAALgADCgYJCAABLgAECgUJBgAFAAAAAA==.Thranduill:BAABLgAECn8cAAIWAAgJ5g4zEQCaAQAWAAgJ5g4zEQCaAQAAAA==.Thras:BAAALgAECgMJBwAAAA==.Thunderhoof:BAAALgADCgQJBwAAAA==.',
Ti='Tidepod:BAABLgAECn8mAAMNAAkJwh1AEwB7AgANAAgJlR1AEwB7AgAOAAIJ4h0fZACzAAABLgAFFAUJBQAcAAQcAA==.Tigerclaw:BAAALgADCgcJBgAAAA==.Tilley:BAABLgAECn8eAAIaAAcJSyHAAABGAgAaAAcJSyHAAABGAgAAAA==.Tingaling:BAABLgAECn8YAAIEAAYJMSFxBADZAQAEAAYJMSFxBADZAQAAAA==.Tinymonk:BAAALgADCgUJBQAAAA==.Tirion:BAABLgAECn8bAAIUAAgJ6xVfDQDxAQAUAAgJ6xVfDQDxAQAAAA==.',
Tl='Tlock:BAAALgAECgUJCAAAAA==.',
To='Toguro:BAAALgADCgQJBQAAAA==.Tolfir:BAABLgAECn8UAAITAAgJzg+xBQANAgATAAgJzg+xBQANAgAAAA==.Tonecaponed:BAAALgADCggJFQAAAA==.Tonkotsu:BAAALgAECgEJAQAAAA==.Toothlss:BAAALgADCgEJAQABLgAECgQJDQAFAAAAAA==.Toyletpaypah:BAAALgAECgMJAwAAAA==.Toyletwahtah:BAAALgAECgQJBAAAAA==.',
Tr='Trapdoor:BAAALgAECgEJAgAAAA==.Treefitty:BAAALgAECgQJBAAAAA==.Treelilly:BAAALgADCgMJAwAAAA==.Tribalz:BAABLgAECn8WAAMkAAgJUxGcDwC0AQAkAAgJUxGcDwC0AQAfAAIJ+wUfMgAtAAAAAA==.Tripsitter:BAAALgADCgEJAQAAAA==.Trunddle:BAAALgADCgcJCgAAAA==.Trïstan:BAAALgAECgEJAQAAAA==.',
Tu='Tuchmydemons:BAABLgAECn8dAAICAAcJRBdhDwCXAQACAAcJRBdhDwCXAQAAAA==.Tugmahog:BAAALgAECgMJAwAAAA==.',
Ty='Tygrelilly:BAABLgAECn8cAAINAAcJnRh6JAAEAgANAAcJnRh6JAAEAgAAAA==.Typeshi:BAAALgAECgUJCAAAAA==.Tyrieal:BAAALgAECgYJDgAAAA==.',
['Tö']='Tööl:BAAALgAECgYJBgAAAA==.',
['Tø']='Tøøthlss:BAAALgAECgQJDQAAAA==.',
Un='Unami:BAAALgADCgEJAQAAAA==.',
Up='Upnah:BAAALgAECgYJCAAAAA==.',
Ut='Uthler:BAABLgAECn8fAAMgAAgJuyE4DQCvAgAgAAgJuyE4DQCvAgAWAAgJMA4yWQDXAQAAAA==.',
Va='Valnyr:BAAALgADCgUJBQAAAA==.Vanita:BAAALgAECgIJAgAAAA==.Vanêssa:BAAALgAECgcJEwAAAA==.Varner:BAABLgAECn8WAAIMAAgJoiJYAQB4AgAMAAgJoiJYAQB4AgAAAA==.Varsca:BAAALgADCgIJAgAAAA==.',
Ve='Velantria:BAAALgAECgIJAwAAAA==.Venger:BAAALgADCgcJCAAAAA==.Vervlock:BAAALgAECgMJAwAAAA==.Vesadir:BAAALgADCgYJDgAAAA==.Vexander:BAAALgAECgYJDAAAAA==.',
Vi='Vicktus:BAAALgAECgUJBgAAAA==.Vindict:BAABLgAECn8UAAIlAAcJThpgBACOAQAlAAcJThpgBACOAQAAAA==.Violent:BAAALgAECgEJAQAAAA==.Virtutis:BAAALgADCgkJDgAAAA==.Vishor:BAAALgADCgYJBgABLgAECgYJEQAFAAAAAA==.',
Vo='Voidcore:BAAALgAECgYJCgAAAA==.Voiyd:BAAALgADCgQJBAAAAA==.Voltedrage:BAAALgADCgMJAwAAAA==.Vonalass:BAAALgAECgQJCgAAAA==.Vongala:BAAALgADCgcJBwAAAA==.Vongalas:BAABLgAECn8aAAILAAYJcRm+BgCmAQALAAYJcRm+BgCmAQAAAA==.Vongalase:BAAALgADCgYJBgAAAA==.Vongalass:BAAALgADCgkJEQAAAA==.Vongimi:BAAALgAECgYJCgABLgAECgYJCgAFAAAAAA==.Vongimiv:BAAALgAECgYJCgAAAA==.Voninfinite:BAAALgADCgMJAwAAAA==.Vork:BAAALgADCgYJDQAAAA==.Voucher:BAACLgAFFH8MAAMCAAUJohIuIgD7AAACAAQJihIuIgD7AAAIAAIJ+Q9iDACpAAAuAAQKfyIAAwgACAlZHmUbAHIBAAIABglWHTdLAOgBAAgABQm1HGUbAHIBAAAA.',
Vv='Vvarriorr:BAAALgAECgcJCgAAAA==.',
Vy='Vysérå:BAABLgAECn8XAAMHAAYJ9wp6KAAwAQAHAAYJ9wp6KAAwAQAZAAYJyAWPBADlAAAAAA==.',
['Vé']='Vénkman:BAAALgAECgYJCAAAAA==.',
Wa='Wai:BAAALgADCgYJBwAAAA==.Waifo:BAAALgAECgMJAwAAAA==.Warjuice:BAAALgAECgYJBgAAAA==.Warrikk:BAAALgAECgYJDwAAAA==.Wasted:BAAALgAECgcJBwAAAA==.',
We='Welanin:BAAALgADCgQJBAAAAA==.',
Wh='Wheel:BAAALgADCgcJDQAAAA==.Whosadoris:BAAALgAECgYJBwAAAA==.',
Wi='Wildbillee:BAABLgAECn8XAAMEAAYJhw+fDgAHAQAEAAYJjw2fDgAHAQAQAAQJsgrRTQDaAAABLgAECggJIwACAI4eAA==.Wildbilly:BAAALgAECgYJCwABLgAECggJIwACAI4eAA==.Wildbily:BAAALgAECgIJAwABLgAECggJIwACAI4eAA==.Wind:BAAALgAECgUJCwABLgAFFAUJDgAjAEEMAA==.Windfury:BAAALgAECgIJCQAAAA==.Winniferd:BAAALgADCgYJCAAAAA==.Wizzlewozzle:BAABLgAECn8WAAIBAAYJZiAZVQA5AgABAAYJZiAZVQA5AgAAAA==.',
Wo='Woes:BAAALgAECgQJBgAAAA==.Wolvslayer:BAAALgADCgUJBQABLgAFFAQJDAAbACAZAA==.Wompwomp:BAAALgAECgUJEAAAAA==.Worldwaker:BAACLgAFFH8FAAIQAAMJFxUuAwACAQAQAAMJFxUuAwACAQAuAAQKfyUAAhAACAlYJKkAALMCABAACAlYJKkAALMCAAAA.',
Wr='Wretched:BAABLgAECn8fAAQTAAgJ0BreBAAmAgATAAcJyhzeBAAmAgACAAYJgBeHUADWAQAIAAQJxBrwIgBAAQAAAA==.',
Wy='Wylblly:BAAALgAECgUJBgABLgAECggJIwACAI4eAA==.Wyldbill:BAABLgAECn8jAAMCAAgJjh4WNQA4AgACAAcJjh4WNQA4AgAIAAMJyxQjNADmAAAAAA==.',
Xa='Xanityy:BAAALgAECgcJDQAAAA==.Xarxzez:BAABLgAECn8dAAIBAAcJUiKrCAAdAgABAAcJUiKrCAAdAgAAAA==.',
Xe='Xera:BAAALgAECgIJAgAAAA==.Xernau:BAAALgADCgIJAgAAAA==.',
Xg='Xgambit:BAAALgAECgQJBgAAAA==.',
Xm='Xmoon:BAAALgAECgcJCQAAAA==.',
Xp='Xprt:BAABLgAECn8aAAIiAAcJ/CP1AABxAgAiAAcJ/CP1AABxAgAAAA==.Xprtdemon:BAAALgAECgUJBQAAAA==.Xprtdrood:BAAALgADCgMJAwABLgAECgUJBQAFAAAAAA==.',
Xy='Xyno:BAAALgAECgcJEwAAAA==.',
Ya='Yandora:BAAALgAECgIJAgAAAA==.Yaong:BAAALgAECgUJCgABLgAECgYJBwAFAAAAAA==.Yarbs:BAAALgAFFAMJAwAAAA==.Yarrôw:BAAALgAECgYJCgAAAA==.',
Yi='Yishi:BAAALgAECgMJAwAAAA==.',
Yo='Yokoyama:BAAALgAECgYJDAAAAA==.',
Yu='Yuckmouth:BAABLgAECn8hAAIBAAgJkRoBRwBjAgABAAgJkRoBRwBjAgAAAA==.Yungdh:BAAALgADCgMJAwAAAA==.',
Za='Zadaen:BAABLgAECn8aAAINAAcJGxnjJgD3AQANAAcJGxnjJgD3AQAAAA==.Zag:BAAALgADCgcJCQAAAA==.Zaku:BAAALgADCgYJBgAAAA==.Zalysa:BAABLgAFFH8FAAICAAQJgQPwGwAWAQACAAQJgQPwGwAWAQAAAA==.Zankeh:BAAALgAECgEJAwAAAA==.Zardax:BAAALgADCgIJAgAAAA==.Zarroth:BAAALgAECgEJAQAAAA==.Zaurion:BAAALgAECgYJBwAAAA==.Zayandrysal:BAAALgADCgcJEQAAAA==.',
Ze='Zeera:BAAALgADCgEJAQAAAA==.Zelthar:BAAALgAECgUJBQAAAA==.Zendeth:BAAALgADCgEJAQAAAA==.Zev:BAACLgAFFH8JAAIRAAQJSBzxAAB8AQARAAQJSBzxAAB8AQAuAAQKfyAABBEACAkrID4FALoCABEACAkHID4FALoCAAkABAlFG95cAFEBABoAAwkUD/FmAKMAAAAA.',
Zi='Zingo:BAAALgADCgQJBAAAAA==.Zivie:BAAALgAECgYJCwAAAA==.',
Zo='Zofu:BAAALgAECgcJDwAAAA==.Zoia:BAABLgAECn8UAAMHAAcJvxKiHwCCAQAHAAcJvxKiHwCCAQAjAAEJRw45YwAwAAAAAA==.Zorkky:BAABLgAECn8cAAMTAAYJnRGEEAAlAQACAAYJIRBmggBVAQATAAUJZw2EEAAlAQAAAA==.Zosoó:BAAALgAECgUJCAAAAA==.',
['Ác']='Áchu:BAABLgAECn8aAAMhAAgJvBwEAQA/AgAhAAgJvBwEAQA/AgANAAQJ4xsvWQAjAQAAAA==.',
['Än']='Änh:BAAALgAECgYJDAAAAA==.',
['Äv']='Ävailable:BAAALgADCgUJBQAAAA==.',
['Çh']='Çhef:BAAALgAECgkJBwAAAA==.',
['Êk']='Êkkô:BAAALgAECgUJCAABLgAECgcJDAAFAAAAAA==.',
['Ðe']='Ðestroyer:BAABLgAECn8bAAIGAAcJqhGmawC0AQAGAAcJqhGmawC0AQAAAA==.',
['Ñå']='Ñårãzú:BAAALgADCgkJEgAAAA==.',
['Øs']='Øsiris:BAAALgAECgQJBQAAAA==.',
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

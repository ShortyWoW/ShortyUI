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

local lookup = {'Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Druid-Balance','Druid-Feral','Hunter-Survival','Hunter-BeastMastery','Paladin-Protection','Unknown-Unknown','Druid-Guardian','Evoker-Augmentation','Evoker-Preservation','Priest-Discipline','Warrior-Protection','Monk-Mistweaver','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Frost','Priest-Shadow','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Evoker-Devastation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aahrya:BAAALgAFFAEJAQAAAA==.',
Ac='Ackreser:BAAALgAECgQJBAAAAA==.',
Ae='Aellana:BAAALgAECgEJAQAAAA==.Aevisea:BAABLgAECn8VAAIBAAYJTxVrKgAjAQABAAYJTxVrKgAjAQAAAA==.',
Ai='Aidan:BAACLgAFFH8SAAICAAUJyCUfAADFAQACAAUJyCUfAADFAQAuAAQKfx4AAgIACQkHJfsAAL8DAAIACQkHJfsAAL8DAAEuAAUUCAkiAAMAxyEA.Aidhan:BAACLgAFFH8iAAIDAAgJxyEMAABwAwADAAgJxyEMAABwAwAuAAQKfy4AAwMACQnZJhMAAA4EAAMACQnZJhMAAA4EAAQABgmAEdw2ACsBAAAA.',
Aj='Ajanni:BAABLgAECn8ZAAIFAAgJsh6iEgC6AgAFAAgJsh6iEgC6AgAAAA==.',
Ak='Akamaki:BAAALgADCgMJBAAAAA==.',
Al='Aldrigor:BAAALgAECgcJDAAAAA==.Alett:BAAALgAECgYJCgAAAA==.Alinni:BAAALgADCgkJDwAAAA==.Alivathus:BAABLgAECn8iAAIGAAgJMCVIAgBJAwAGAAgJMCVIAgBJAwAAAA==.Aloka:BAAALgAECgMJAwABLgAECggJKgAHAE4dAA==.Alvart:BAAALgADCgcJCQAAAA==.',
Am='Amaru:BAAALgAECgEJAQAAAA==.Amateur:BAAALgADCgEJAQAAAA==.Amiko:BAAALgAECgMJBQAAAA==.',
An='Anaryll:BAAALgAECgEJAQAAAA==.Angriff:BAAALgAECgIJAgAAAA==.Anhedonia:BAAALgADCgMJAwAAAA==.Ansigar:BAAALgAECgQJBgAAAA==.',
Ap='Apep:BAAALgAECgYJDwAAAA==.',
Ar='Aramar:BAAALgADCgYJBwAAAA==.Arbark:BAACLgAFFH8GAAIHAAQJdBqyBABqAQAHAAQJdBqyBABqAQAuAAQKfx4ABAcACAnWJG8rAGECAAcABwlkJW8rAGECAAgABQkCINoSALUBAAkAAQkAANUlAFoAAAAA.Arbarkm:BAAALgADCgIJAgAAAA==.Arcelf:BAAALgAECgQJBgAAAA==.Arcnfrost:BAAALgAECgYJBwAAAA==.Ardone:BAAALgADCgQJBAAAAA==.Arenar:BAACLgAFFH8JAAMKAAMJFSI7BAA8AQAKAAMJFSI7BAA8AQACAAMJ6Bk0BwAEAQAuAAQKfyEAAwIACAmtIt8LAL0CAAIABwm2I98LAL0CAAoAAwn4HNEUALYAAAAA.Ariandralina:BAAALgAECgEJAQAAAA==.Arkham:BAAALgADCggJDgAAAA==.',
As='Ashaya:BAAALgAECgYJDgAAAA==.Ashenclaw:BAAALgAECgYJCgAAAA==.Asmohdian:BAAALgAECgcJEAAAAA==.Asra:BAABLgAECn8qAAQHAAgJTh19BQAfAgAHAAgJShl9BQAfAgAJAAYJmiDfBgDqAQAIAAMJlROHNQDgAAAAAA==.',
Au='Auder:BAAALgADCgIJAgAAAA==.Aug:BAAALgADCgcJEwAAAA==.Auxevo:BAAALgAECgMJAwAAAA==.',
Av='Availl:BAAALgAECgQJBQAAAA==.Avinôx:BAACLgAFFH8LAAILAAQJwRMSAgA3AQALAAQJwRMSAgA3AQAuAAQKfx0AAgsACAmUI2gJAAkDAAsACAmUI2gJAAkDAAAA.',
Ay='Aydan:BAACLgAFFH8KAAIMAAMJXB8DIgAPAQAMAAMJXB8DIgAPAQAuAAQKfx4AAwwACQn5I1AJAFIDAAwACQn5I1AJAFIDAA0AAQkyHso+AFUAAAEuAAUUCAkiAAMAxyEA.Aylan:BAAALgAECgEJAQAAAA==.',
Az='Aziera:BAAALgADCgYJBgABLgAECgYJFQABAE8VAA==.Azumaa:BAAALgAECgQJBAAAAA==.',
['Aù']='Aùra:BAAALgADCgQJBAAAAA==.',
Ba='Bacnmac:BAABLgAECn8pAAIHAAgJtx9LFwDJAgAHAAgJtx9LFwDJAgAAAA==.Bainironwind:BAAALgAECgYJCwAAAA==.Baiwushi:BAAALgAECgYJDAAAAA==.Bajablessed:BAAALgADCgEJAQAAAA==.Baldyr:BAAALgADCgUJBwAAAA==.Balior:BAAALgAECgIJAgAAAA==.',
Be='Bemba:BAAALgAECgEJAQAAAA==.Bench:BAAALgAECgEJAQABLgAFFAUJDAAOAG0SAA==.Bestricer:BAACLgAFFH8NAAIPAAUJdxS0BACmAQAPAAUJdxS0BACmAQAuAAQKfxkAAg8ACQlWI10GAGgDAA8ACQlWI10GAGgDAAAA.',
Bi='Biggles:BAECLgAFFH8RAAIQAAUJLxxrAQDAAQAQAAUJLxxrAQDAAQAuAAQKfxwABBAACAnjHLUlACICABAACAnjHLUlACICABEABglNFQ5AADEBABIAAQnyAQs2AC0AAAAA.Bigred:BAAALgAECgYJDAAAAA==.Bigshow:BAAALgAECgIJAgAAAA==.',
Bl='Blobney:BAACLgAFFH8WAAMHAAYJ8SJMAAD/AQAHAAYJNyFMAAD/AQAIAAMJ2SBXBQAgAQAuAAQKfy0ABAcACQnVJIEBALwDAAcACQmOJIEBALwDAAkABAlSJi8IAMkBAAgABAk4JVEVAJ8BAAAA.Bloodobot:BAAALgAECgIJBQAAAA==.Bloodymouth:BAABLgAECn8YAAMDAAgJXyMzGADEAgADAAgJISMzGADEAgAEAAYJwx/LIAC3AQAAAA==.Bluechip:BAAALgAECgYJEwAAAA==.Blueeagle:BAACLgAFFH8IAAMLAAIJliLIGADGAAALAAIJliLIGADGAAATAAIJTgd2BQCmAAAuAAQKfysAAwsACAk/I14AAI0CAAsACAk/I14AAI0CABQAAQkAAMDKADsAAAAA.',
Br='Brandwon:BAABLgAECn8YAAIDAAYJWSLIPQD9AQADAAYJWSLIPQD9AQAAAA==.Braum:BAAALgAECgQJBAAAAA==.Brazlor:BAAALgAECgUJDAAAAA==.Brikz:BAAALgAECggJDgAAAA==.Broboom:BAAALgADCgkJFQAAAA==.',
Bu='Butler:BAAALgAECgEJAQABLgAFFAQJBwADAF0NAA==.Butterflyy:BAAALgAECgYJCgAAAA==.Butternutt:BAAALgADCgYJBwAAAA==.',
Ca='Caelena:BAAALgAECgYJEAAAAA==.Callistra:BAAALgADCgMJAwAAAA==.',
Ce='Celestial:BAABLgAECn8hAAQIAAgJtBRHDAD+AQAIAAgJtBRHDAD+AQAJAAIJSg97BQCJAAAHAAEJYwBgMwEYAAAAAA==.',
Ch='Charlíxcx:BAAALgAECgQJCAAAAA==.Chillice:BAABLgAECn8jAAIBAAgJjCC2IgDoAgABAAgJjCC2IgDoAgAAAA==.Chupacabra:BAAALgAECgQJBAAAAA==.Chuppa:BAAALgADCgEJAQAAAA==.Chuyz:BAAALgAECgcJEgAAAA==.Chuyzz:BAAALgAECgMJBAAAAA==.',
Ci='Cilelienea:BAAALgAECgUJBwAAAA==.Cinderion:BAAALgAECgYJCQAAAA==.',
Cl='Claymation:BAEALgAECgQJCQAAAA==.Clickchi:BAAALgAECgEJAQAAAA==.Clikclikboom:BAAALgAECgcJBQAAAA==.',
Co='Coin:BAAALgADCgcJCgAAAA==.Cordeliaa:BAABLgAECn8aAAIPAAYJnhBhkABbAQAPAAYJnhBhkABbAQAAAA==.Corkster:BAAALgADCgYJCAAAAA==.Coven:BAAALgAECgQJBQAAAA==.',
Cr='Crazyoldmage:BAAALgADCgUJBwAAAA==.Crendybby:BAAALgADCgYJBwAAAA==.Critfast:BAAALgAECgYJEwAAAA==.Crunch:BAABLgAECn8jAAIFAAgJTSEBAQCVAgAFAAgJTSEBAQCVAgAAAA==.',
Cs='Cshaugh:BAAALgAECggJDgAAAA==.',
Cu='Cueballh:BAAALgADCgMJAwAAAA==.Curly:BAAALgAECgQJBwABLgAECggJGgAVAAAWAA==.Curlybonker:BAABLgAECn8aAAIVAAgJABaVDAD+AQAVAAgJABaVDAD+AQAAAA==.',
Cy='Cynikka:BAAALgADCgcJCwAAAA==.Cynthor:BAAALgAECgcJEwAAAA==.',
Da='Dabz:BAAALgAECgYJDQAAAA==.Daghahi:BAABLgAECn8VAAIKAAYJehmkCQBWAQAKAAYJehmkCQBWAQAAAA==.Dahyun:BAAALgADCgYJBgAAAA==.Daisharagos:BAAALgAECgcJEgAAAA==.Dalelor:BAABLgAECn8bAAQSAAgJhiJtBQC2AgASAAgJzSFtBQC2AgAQAAMJziL0YQAsAQARAAIJFhetFwCMAAAAAA==.Dalethyr:BAAALgAECgQJBAAAAA==.Darthflamed:BAABLgAECn8oAAMQAAgJUBFIQQCcAQAQAAgJUBFIQQCcAQARAAcJgworOwBIAQAAAA==.Darthman:BAAALgADCgUJBQAAAA==.Davinah:BAABLgAECn8bAAIGAAYJ6Q6mDAAmAQAGAAYJ6Q6mDAAmAQAAAA==.Dawnara:BAAALgAECgMJAwAAAA==.',
De='Deathkick:BAAALgAECgYJDgAAAA==.Deathkwondo:BAAALgADCgMJAwAAAA==.Deleos:BAAALgAECgUJCAAAAA==.Delmus:BAAALgADCgkJEAABLgAECgMJBAAWAAAAAA==.Delphinae:BAAALgAECgQJCAAAAA==.Demitia:BAAALgADCgkJDwAAAA==.Demonsponge:BAAALgADCggJCAABLgAECgcJFgATAKklAA==.Derpalaherp:BAAALgADCgMJAwAAAA==.Devera:BAABLgAECn8cAAIRAAkJyg+bIgDoAQARAAkJyg+bIgDoAQABLgAECgkJHQAJALoSAA==.Devious:BAAALgADCgUJBAAAAA==.',
Dh='Dhae:BAAALgADCgMJAwAAAA==.Dhanydevito:BAAALgADCgQJBAAAAA==.',
Di='Dirtykahuna:BAAALgADCgMJAwABLgAECgQJCgAWAAAAAA==.Dirtypali:BAAALgAECgQJCgAAAA==.Dirtypoacher:BAAALgADCgEJAQABLgAECgQJCgAWAAAAAA==.Discodiyu:BAAALgAECgQJBgAAAA==.Disconnected:BAAALgAECgEJAQAAAA==.Disemboweler:BAAALgADCgUJBQABLgADCgcJCwAWAAAAAA==.Distress:BAAALgAECgQJBgAAAA==.',
Dm='Dmorte:BAAALgADCgkJCQAAAA==.',
Do='Dojohunter:BAAALgADCgkJCQAAAA==.Doodmang:BAEALgAECgcJEAAAAA==.Doozerdae:BAAALgADCgYJBwAAAA==.',
Dr='Dracrspurb:BAAALgADCgcJBQAAAA==.Dragondeez:BAAALgADCgUJBQABLgAECggJHAAXAO4hAA==.Dragonized:BAAALgADCgYJBgAAAA==.Drakthirr:BAAALgAECgMJBAAAAA==.Droxigar:BAAALgAECgQJBgAAAA==.Drslay:BAAALgAECgQJBAAAAA==.Druidplowz:BAAALgADCgMJAgAAAA==.',
Du='Dumbclass:BAAALgADCgIJAgABLgAFFAUJDQAPAHcUAA==.Duty:BAAALgAECgQJBgAAAA==.',
Dw='Dwelknarr:BAAALgAECgQJCgAAAA==.',
['Dö']='Döminaria:BAAALgAECgIJAgAAAA==.',
Ea='Eadric:BAABLgAECn8eAAIPAAgJSxxLCAAGAgAPAAgJSxxLCAAGAgAAAA==.Earendur:BAAALgAECgEJAQAAAA==.',
Ed='Edallen:BAAALgAECgYJCQAAAA==.',
Ei='Eightchaos:BAAALgAECgYJDwAAAA==.',
El='Elbrujo:BAAALgADCgUJBQAAAA==.Eleaanor:BAABLgAECn8aAAMYAAgJCBUEIQC3AQAYAAgJCBUEIQC3AQAZAAgJ/QMrJQBOAQAAAA==.Eleana:BAAALgADCgcJBwABLgAECggJIwAaADMdAA==.Elendra:BAAALgADCgIJAgAAAA==.Elontesla:BAAALgADCgMJAwAAAA==.',
Em='Emaytete:BAAALgAECgEJAQAAAA==.Empress:BAAALgAECgYJCwABLgAFFAUJDgANAPQjAA==.',
En='Entropius:BAAALgAECgQJCgAAAA==.',
Er='Eratìc:BAAALgADCgkJCwAAAA==.',
Es='Esha:BAAALgADCgEJAQAAAA==.',
Et='Ethaerielle:BAAALgADCgIJAgAAAA==.',
Ev='Evillive:BAAALgAECgEJAQABLgAECgcJIAAbAFsPAA==.',
Ex='Exavin:BAAALgADCgYJBgAAAA==.',
Fa='Faezress:BAAALgAECgQJBQAAAA==.Faliss:BAAALgAECgUJBgAAAA==.Falwyn:BAAALgAECgMJBAAAAA==.Fancypantss:BAAALgADCgMJAwAAAA==.',
Fe='Felflamel:BAAALgAECgIJAgABLgAECggJKAAQAFARAA==.Felfook:BAAALgAECgYJCgAAAA==.Fellien:BAAALgAECgYJCgAAAA==.Feltest:BAAALgAECgUJBQAAAA==.Felystmagi:BAAALgADCgkJCgABLgAECgkJPQAPACUkAA==.Fengrey:BAABLgAECn8qAAMUAAgJSCJWAgCDAgAUAAgJVCFWAgCDAgALAAcJ4QshQQBTAQAAAA==.Feralized:BAAALgAECgQJBwAAAA==.Ferrenz:BAAALgAECgQJBAAAAA==.',
Fi='Fightmeqt:BAAALgADCgUJBQAAAA==.Fistenjoyer:BAABLgAECn8fAAIKAAgJwx1DAgA4AgAKAAgJwx1DAgA4AgAAAA==.',
Fl='Flax:BAAALgADCgkJEgAAAA==.Flippincoco:BAABLgAECn8hAAMcAAgJphezFAAjAgAcAAgJphezFAAjAgAKAAgJWwqhCgBEAQAAAA==.',
Fo='Foremancurly:BAAALgAECgQJBgABLgAECggJGgAVAAAWAA==.',
Fr='Franks:BAAALgAECggJEAAAAA==.Frayon:BAAALgADCgYJCQAAAA==.Frozenhawk:BAAALgADCgMJAwAAAA==.',
Fy='Fynsty:BAAALgAECgYJEwAAAA==.',
Ga='Gaiah:BAAALgADCgEJAQAAAA==.Gaias:BAAALgAECgQJCgAAAA==.Galaesa:BAAALgADCgYJBgAAAA==.Galalea:BAAALgADCgYJCAAAAA==.Galdrial:BAAALgADCgEJAQAAAA==.Galeas:BAABLgAECn8ZAAIdAAgJsCAtDAC6AgAdAAgJsCAtDAC6AgAAAA==.Galiniis:BAAALgADCgcJBwABLgAECgMJBAAWAAAAAA==.Gallarlyn:BAAALgADCgQJBAABLgAECgUJCAAWAAAAAA==.Gary:BAAALgAECgYJDwAAAA==.',
Ge='Geewilkr:BAAALgAECgUJDQAAAA==.Gerhart:BAAALgAECgQJBgAAAA==.',
Gh='Ghostlegend:BAAALgADCgYJBgAAAA==.Ghostsham:BAACLgAFFH8YAAIeAAgJHxwiAAACAwAeAAgJHxwiAAACAwAuAAQKfykAAh4ACQnPJjEAAPoDAB4ACQnPJjEAAPoDAAAA.',
Gl='Glamizon:BAAALgAECgEJAQAAAA==.Glörfindel:BAAALgAECgcJBwAAAA==.',
Go='Goldoran:BAAALgAECgQJCAAAAA==.Goniff:BAABLgAECn8gAAIVAAgJkCKGAACcAgAVAAgJkCKGAACcAgAAAA==.Goransk:BAAALgAECgQJBgAAAA==.Gormash:BAAALgADCgcJBwAAAA==.Gorsk:BAAALgADCgkJEAABLgAECgQJBgAWAAAAAA==.',
Gr='Gracelious:BAAALgAECgQJCgAAAA==.Graebrand:BAAALgADCgYJCwAAAA==.Graemyste:BAAALgADCggJCAAAAA==.Graewynde:BAAALgADCgMJAwAAAA==.Grakkora:BAABLgAECn8pAAIUAAgJoiVoAgBzAwAUAAgJoiVoAgBzAwAAAA==.Grakkus:BAAALgADCgYJBgABLgAECggJKQAUAKIlAA==.Greyshadow:BAAALgAECgYJEgAAAA==.Grimreåper:BAAALgADCgcJCAAAAA==.Grotkal:BAAALgADCgcJBwAAAA==.Grubber:BAAALgAECgQJBAAAAA==.Grüb:BAAALgADCgQJCQABLgAECgQJBAAWAAAAAA==.',
Gu='Guitarbeef:BAAALgAECgYJEAAAAA==.Guncarick:BAAALgADCgMJAwAAAA==.Guntran:BAAALgAECgYJCgAAAA==.Gurthock:BAABLgAECn8VAAMHAAgJhAo6ggBWAQAHAAcJvgg6ggBWAQAIAAQJcQnmPQC9AAAAAA==.',
Gw='Gwenixx:BAAALgAECgEJAQAAAA==.',
Gy='Gymadin:BAAALgADCgEJAQAAAA==.',
['Gà']='Gàuron:BAAALgAECgYJDwAAAA==.',
['Gô']='Gôût:BAAALgADCgcJEwAAAA==.',
['Gû']='Gûnn:BAAALgADCgEJAgAAAA==.',
Ha='Hakke:BAAALgADCgMJAwAAAA==.',
He='Headhuntin:BAABLgAECn8XAAIUAAgJpRbDJQAkAgAUAAgJpRbDJQAkAgAAAA==.Hellione:BAAALgADCgMJAwAAAA==.Helltest:BAABLgAECn8gAAIDAAgJviW/BgBbAwADAAgJviW/BgBbAwAAAA==.Herraboosted:BAAALgAECgQJBQAAAA==.',
Hi='Hinari:BAAALgAECgQJBwABLgAECgUJCAAWAAAAAA==.Hiruzèn:BAAALgAECgQJBAAAAA==.',
Ho='Hoamanager:BAAALgAECgcJBwAAAA==.Holypwr:BAABLgAECn8ZAAIPAAgJ2h97EwD3AgAPAAgJ2h97EwD3AgAAAA==.Hotdumpling:BAAALgAECgYJDgAAAA==.',
Hu='Huegarak:BAAALgAECgYJCgAAAA==.Huggybuns:BAAALgAECgEJAQAAAA==.',
Hy='Hyle:BAAALgAECgYJDwAAAA==.',
Ic='Ichio:BAAALgADCgIJAwAAAA==.',
Il='Ilidor:BAAALgAECgUJBQABLgAECgcJEQAWAAAAAA==.Illidanina:BAAALgAECgUJBQABLgAECggJFQABAAUPAA==.Illuminator:BAAALgAECgEJAQAAAA==.',
In='Infntyonhigh:BAAALgADCgIJAgAAAA==.Inspectadeck:BAACLgAFFH8LAAIHAAQJFwZSCgAkAQAHAAQJFwZSCgAkAQAuAAQKfywAAwcACAmQGqYFABwCAAcACAmQGqYFABwCAAgABAltEjItAAkBAAAA.',
Ir='Ironson:BAAALgADCgYJBgAAAA==.Irsh:BAAALgADCggJCAAAAA==.',
Is='Istariel:BAAALgAECgYJDAABLgAFFAgJGAAeAB8cAA==.',
Iv='Ivoryson:BAAALgAECgIJAgAAAA==.',
Ja='Jacksparrowl:BAAALgAECgQJCAAAAA==.Jakarra:BAAALgADCgkJDwAAAA==.Jalkymoose:BAAALgADCgQJBAAAAA==.Jaytov:BAAALgAECgIJAwAAAA==.Jazu:BAAALgAECgYJDwAAAA==.',
Je='Jemba:BAABLgAECn8dAAIBAAgJYRfsTgBKAgABAAgJYRfsTgBKAgAAAA==.Jeras:BAAALgADCgIJAgAAAA==.Jerks:BAABLgAECn8XAAMfAAcJxBT9EQCXAQAfAAYJJBX9EQCXAQAOAAMJqgzJeQCrAAAAAA==.Jetblue:BAAALgADCgYJBgABLgAECgYJEwAWAAAAAA==.',
Ji='Jinhala:BAAALgAECgUJBQABLgAFFAIJCAALAJYiAA==.',
Jo='Joenips:BAAALgAECgcJEQAAAA==.Jokhan:BAAALgAECgQJBgAAAA==.Jorrell:BAABLgAECn8VAAIPAAYJARCYLADtAAAPAAYJARCYLADtAAAAAA==.Josh:BAABLgAECn8jAAIDAAgJgR1kCADtAQADAAgJgR1kCADtAQAAAA==.Jotun:BAAALgAECgEJAgABLgAECgIJBQAWAAAAAA==.Joval:BAAALgAECgEJAQAAAA==.Jozeph:BAABLgAECn8XAAIgAAgJRR91AQDoAgAgAAgJRR91AQDoAgAAAA==.',
Ju='Juno:BAAALgADCgYJDAAAAA==.',
['Jà']='Jàmie:BAAALgAECgMJAgAAAA==.',
Ka='Kaalar:BAABLgAECn8YAAIUAAcJ4h75FQCIAgAUAAcJ4h75FQCIAgAAAA==.Kaestirael:BAAALgAECgMJBQAAAA==.Kalmia:BAAALgAECgUJDgAAAA==.Kamoura:BAABLgAECn8VAAIBAAYJFxjcHABmAQABAAYJFxjcHABmAQAAAA==.Kapeta:BAAALgAECgUJBgAAAA==.Karmen:BAACLgAFFH8RAAIZAAUJ0yOwAAD3AQAZAAUJ0yOwAAD3AQAuAAQKfxwAAhkACAlhJoMBAG8DABkACAlhJoMBAG8DAAAA.Karnara:BAAALgADCgcJCQABLgAECgEJAQAWAAAAAA==.Karnatron:BAAALgAECgEJAQAAAA==.Kayha:BAAALgADCgEJAQAAAA==.Kayleave:BAACLgAFFH8LAAIhAAUJVQujCAA6AQAhAAUJVQujCAA6AQAuAAQKfxoAAiEACQmaHf8MALMCACEACQmaHf8MALMCAAAA.Kazuha:BAAALgADCgkJGAABLgAECgUJCQAWAAAAAA==.Kazz:BAABLgAECn8eAAIQAAgJXxK7DgBrAQAQAAgJXxK7DgBrAQAAAA==.',
Ke='Kealohalani:BAAALgAECgEJAQAAAA==.Keattz:BAABLgAFFH8FAAMFAAMJDBa+FQC3AAAFAAIJNh2+FQC3AAAiAAEJuAf7CwBSAAABLgAFFAUJDQAjAC8dAA==.Keattzdh:BAAALgAFFAEJAQABLgAFFAUJDQAjAC8dAA==.Keattzdx:BAABLgAECn8VAAIjAAcJyCJiHQAUAgAjAAcJyCJiHQAUAgABLgAFFAUJDQAjAC8dAA==.Keattzxd:BAACLgAFFH8NAAMjAAUJLx0KAQCMAQAjAAUJLx0KAQCMAQAkAAIJ4xdTAwDFAAAuAAQKfyYAAyMACAk0I8AEAEoDACMACAk0I8AEAEoDACQAAQmfIR4ZAGUAAAAA.Keatzz:BAABLgAFFH8JAAMMAAUJmhUBCABGAQAMAAQJmhUBCABGAQANAAEJAABQDwAAAAABLgAFFAUJDQAjAC8dAA==.Keedill:BAAALgAECgcJDQAAAA==.Keelinnea:BAAALgADCgcJDgAAAA==.Keggerz:BAAALgAECgQJBgAAAA==.Kelii:BAAALgAFFAMJAwABLgAFFAUJDAAOAG0SAA==.Kennagi:BAAALgAECgIJAgAAAA==.Kenshunterl:BAAALgAECgQJCQAAAA==.',
Kh='Kharka:BAABLgAECn8WAAMHAAgJMSNGGQC9AgAHAAgJMSNGGQC9AgAJAAEJAAC3KwBHAAAAAA==.Khathgar:BAAALgADCggJEgABLgAECgYJGgASAKYYAA==.Khomorphisis:BAAALgAFFAEJAQABLgAFFAUJEQASAKMbAA==.Khovastis:BAACLgAFFH8RAAISAAUJoxuMAADOAQASAAUJoxuMAADOAQAuAAQKfxwAAxIACAl/JEoDAAUDABIACAnpIkoDAAUDABEAAwnsFMtSANsAAAAA.',
Ki='Kianll:BAAALgAECgIJAgAAAA==.Kiljorith:BAAALgAECgYJDAAAAA==.Kiralnikika:BAAALgADCgkJDgAAAA==.Kiron:BAAALgADCgMJAwAAAA==.Kiros:BAAALgAECgYJDwAAAA==.Kitchntabls:BAACLgAFFH8PAAMDAAUJsg2SDABuAQADAAUJsg2SDABuAQAEAAEJ9AgADgBOAAAuAAQKfxwAAwMACAn+H3QqAFcCAAMACAkKHnQqAFcCAAQABwnXGZEaAO4BAAAA.',
Kj='Kjinthal:BAAALgAECgYJDwAAAA==.',
Kl='Kleno:BAAALgAECgcJBwAAAA==.',
Ko='Koenji:BAACLgAFFH8OAAIfAAUJKRQ0AQCZAQAfAAUJKRQ0AQCZAQAuAAQKfxwAAh8ACAkFIYoEANECAB8ACAkFIYoEANECAAAA.Korastos:BAAALgAECgIJAgABLgAECggJIwAaADMdAA==.Korastus:BAABLgAECn8jAAMaAAgJMx0vAgBLAgAaAAgJkRkvAgBLAgAGAAcJ0Rk6HQD0AQAAAA==.Korvaany:BAAALgAECgYJCwAAAA==.',
Kp='Kpc:BAAALgAECgIJAwABLgAECggJJAABACsaAA==.Kpcmini:BAABLgAECn8kAAIBAAgJKxrlCgD/AQABAAgJKxrlCgD/AQAAAA==.Kpcmoose:BAAALgADCgEJAQABLgAECggJJAABACsaAA==.',
Kr='Krinne:BAABLgAECn8iAAIQAAgJdyQ2BwAZAwAQAAgJdyQ2BwAZAwAAAA==.Krizez:BAAALgAECgQJBgAAAA==.',
Ky='Kyndas:BAAALgADCgQJBAAAAA==.Kyndel:BAABLgAECn8gAAIfAAcJtxndCgAgAgAfAAcJtxndCgAgAgAAAA==.',
['Kä']='Käne:BAAALgAECgYJDwAAAA==.',
['Kí']='Kín:BAAALgAECgQJBAABLgAECgYJDwAWAAAAAA==.',
La='Lableue:BAAALgADCgYJBgAAAA==.Lalada:BAEALgAECgUJBQAAAA==.',
Le='Legateflame:BAAALgADCgYJBgAAAA==.Legendáry:BAABLgAECn8VAAIBAAcJBQ/nsAB7AQABAAcJBQ/nsAB7AQAAAA==.Legimp:BAABLgAECn8XAAIYAAgJHxEuHADmAQAYAAgJHxEuHADmAQAAAA==.Lehvy:BAABLgAECn8VAAIGAAYJcxNtCQBmAQAGAAYJcxNtCQBmAQAAAA==.Lerann:BAAALgAECgYJCgAAAA==.Levey:BAAALgADCggJCAAAAA==.',
Li='Libi:BAAALgADCgUJBQAAAA==.Lict:BAABLgAECn8jAAIdAAgJ5BsdFAByAgAdAAgJ5BsdFAByAgABLgABCgUJBQAWAAAAAA==.Lightbearer:BAAALgADCgIJAgAAAA==.Lightninghan:BAAALgADCgYJCQAAAA==.Lilithene:BAAALgAECgMJBQABLgAECggJKgAHAE4dAA==.Lillea:BAAALgAECgYJDwAAAA==.Litebringer:BAAALgAECgYJEAAAAA==.Lizardwizard:BAAALgAECgQJCQAAAA==.',
Lo='Loktalaan:BAACLgAFFH8LAAIfAAQJiQ3jAAA+AQAfAAQJiQ3jAAA+AQAuAAQKfyoAAh8ACAlFH9oAAFcCAB8ACAlFH9oAAFcCAAAA.Lonjurace:BAAALgAECgIJAgAAAA==.',
Lu='Luan:BAABLgAECn8gAAMFAAkJbBWjAgAzAgAFAAkJuhSjAgAzAgAbAAMJ2RrcLgDMAAAAAA==.Lucien:BAABLgAECn8tAAIQAAgJhhliIQA6AgAQAAgJhhliIQA6AgAAAA==.Luni:BAAALgAECgYJDwAAAA==.Lute:BAABLgAECn8aAAIOAAgJjxlIBQAQAgAOAAgJjxlIBQAQAgAAAA==.',
Ly='Lycha:BAAALgAECgQJCAAAAA==.Lyfeguard:BAAALgAECgYJCwAAAA==.Lyridrael:BAAALgAECgEJAQAAAA==.',
Ma='Mahito:BAAALgAECgUJCQAAAA==.Maleus:BAAALgADCgEJAQAAAA==.Malianas:BAAALgADCgUJCgAAAA==.Malitax:BAAALgAECgUJEQAAAA==.Malzah:BAAALgADCgQJBAAAAA==.Manaless:BAACLgAFFH8IAAIBAAMJkBqLDwASAQABAAMJkBqLDwASAQAuAAQKfyUAAwEACAlkIssYABYDAAEACAlkIssYABYDACUAAQmJCwIfADIAAAAA.Manawarrx:BAABLgAECn8YAAIhAAgJWyU3BABTAwAhAAgJWyU3BABTAwAAAA==.Marderer:BAABLgAECn8VAAIkAAYJZxBFAwBEAQAkAAYJZxBFAwBEAQAAAA==.Mariene:BAAALgADCgMJAwABLgAECgYJFQABAE8VAA==.Mariuss:BAAALgAECgUJBQABLgAFFAUJEAABAGwYAA==.Marizio:BAAALgADCggJFAAAAA==.Masakari:BAABLgAECn8VAAIUAAYJvhKnGwAgAQAUAAYJvhKnGwAgAQAAAA==.Mattðaemon:BAAALgADCgMJAwAAAA==.Mazzlock:BAAALgAECgQJEAAAAA==.',
Mc='Mcgyvr:BAAALgAECgYJBgAAAA==.',
Me='Mealo:BAAALgADCgQJBAAAAA==.Megameow:BAABLgAECn8aAAISAAYJphirAwB3AQASAAYJphirAwB3AQAAAA==.Mercuria:BAAALgADCgkJEAAAAA==.Meriel:BAAALgADCgYJCgAAAA==.',
Mh='Mherlen:BAABLgAECn8aAAMBAAgJjx+QJQDcAgABAAgJjx+QJQDcAgAlAAEJuxubGwA9AAAAAA==.',
Mi='Miriane:BAAALgAECgEJAQAAAA==.Misile:BAAALgADCgEJAQAAAA==.Missmonk:BAAALgADCgcJDQABLgAECgMJBAAWAAAAAA==.Mitsuri:BAAALgADCgcJBwABLgAECgMJBAAWAAAAAA==.',
Mo='Mobius:BAAALgADCgkJFgAAAA==.Mobro:BAAALgADCgUJBQAAAA==.Mokuo:BAABLgAFFH8JAAIFAAQJmBrCCABjAQAFAAQJmBrCCABjAQAAAA==.Mongöose:BAAALgADCgQJBAAAAA==.Moni:BAAALgAECgEJAQAAAA==.Monkmommy:BAAALgADCgkJEQAAAA==.Moomedic:BAAALgAECgQJBgAAAA==.Moondrius:BAABLgAECn8eAAMRAAgJXhofBADmAQARAAcJJx0fBADmAQAQAAcJuxbDPwCjAQAAAA==.Moonthorn:BAAALgAECgUJCgAAAA==.Mort:BAAALgAECgQJCgAAAA==.Moxxou:BAACLgAFFH8HAAIOAAMJPA19EQDcAAAOAAMJPA19EQDcAAAuAAQKfykAAg4ACQl6H9gCAGECAA4ACQl6H9gCAGECAAAA.',
Mu='Mulch:BAABLgAECn8gAAIQAAgJtQ2DEABSAQAQAAgJtQ2DEABSAQAAAA==.Murciélago:BAAALgADCgEJAQAAAA==.Murray:BAAALgAECgIJAgAAAA==.',
My='Mybelle:BAAALgAECgUJDQAAAA==.Mysticle:BAAALgADCgkJHQAAAA==.Mythaltis:BAABLgAECn8VAAIEAAYJfSQgAgAGAgAEAAYJfSQgAgAGAgAAAA==.',
Na='Naul:BAAALgAECgYJBgABLgAECgkJIAAFAGwVAA==.Naur:BAAALgADCgMJAwABLgAECgkJIAAFAGwVAA==.',
Ne='Necrokai:BAABLgAECn8WAAMQAAcJvCAoEwCcAgAQAAcJvCAoEwCcAgARAAIJVhLtawBwAAAAAA==.Nerevar:BAAALgAECgEJAQAAAA==.Netal:BAAALgAECgUJBgAAAA==.Netherbear:BAEALgAECgUJBwAAAA==.Netherrage:BAAALgADCgIJAgAAAA==.Nezhul:BAAALgAECggJEQAAAA==.',
Ni='Nikehalo:BAAALgAECgkJBwAAAA==.Ninejuanjuan:BAAALgAECgkJDgAAAA==.',
No='No:BAACLgAFFH8PAAIPAAUJsiC7AgDUAQAPAAUJsiC7AgDUAQAuAAQKfxwAAg8ACAnCI4YRAAUDAA8ACAnCI4YRAAUDAAAA.Nochit:BAAALgADCggJCAABLgAECggJGAAhAFslAA==.Noctula:BAAALgAECgYJCQABLgAECgcJFgAQALwgAA==.Norne:BAABLgAECn8WAAIEAAYJNx7wBACAAQAEAAYJNx7wBACAAQAAAA==.Nozok:BAAALgAECgEJAQAAAA==.',
Ny='Nytkiller:BAAALgAECgIJAgAAAA==.Nyxy:BAAALgAECgEJAQAAAA==.Nyzul:BAAALgAECgMJBAAAAA==.',
Oa='Oakherst:BAAALgADCgMJAwAAAA==.',
Oo='Ooljee:BAAALgADCgMJAwABLgAECgYJFQAKAHoZAA==.',
Op='Opallea:BAAALgAECgMJBAAAAA==.',
Or='Oriazure:BAAALgADCgcJBwAAAA==.',
Ov='Overclocked:BAAALgAECggJEwAAAA==.Ovid:BAAALgAECgUJCwAAAA==.',
Pa='Paddington:BAAALgAECgYJDwAAAA==.Pahbi:BAAALgAECgEJAQAAAA==.Palempi:BAAALgADCgIJAgAAAA==.Pastorjohn:BAAALgAECgUJBQAAAA==.',
Pe='Pendojight:BAAALgAECgcJCQAAAA==.Pendojo:BAABLgAECn8VAAIPAAgJpyP/DgAWAwAPAAgJpyP/DgAWAwAAAA==.Pendomage:BAAALgADCgUJBQAAAA==.Pendovoker:BAAALgADCgQJBAAAAA==.',
Ph='Phorne:BAAALgADCgEJAQAAAA==.',
Pi='Pifril:BAAALgADCgMJAwAAAA==.Pinay:BAAALgADCgQJBAAAAA==.Pip:BAABLgAECn8lAAMeAAkJ2BnBIAAJAgAeAAgJxhjBIAAJAgAOAAMJygRfgQCOAAABLgAECgkJHQAJALoSAA==.Pipium:BAABLgAECn8dAAIJAAkJuhLEBAApAgAJAAkJuhLEBAApAgAAAA==.',
Pl='Plagued:BAAALgAECgEJAQAAAA==.',
Po='Pocketpotion:BAAALgAECgcJCwAAAA==.Poisun:BAAALgADCggJFwAAAA==.Pookiehandz:BAAALgADCgUJBQAAAA==.Pookiemonstr:BAAALgAECgYJEgAAAA==.Powery:BAAALgAECgEJAQAAAA==.',
Pr='Prizrak:BAAALgAECgYJBgABLgAFFAgJGAAeAB8cAA==.Project:BAAALgAECgIJAgAAAA==.',
Ps='Psychoticvet:BAAALgADCggJDAAAAA==.',
Pu='Punchyheal:BAAALgAECgIJAwAAAA==.Punkinpie:BAAALgADCgkJFAAAAA==.Purple:BAAALgADCgYJBgABLgAECggJFgAUAHIeAA==.Purples:BAABLgAECn8WAAMUAAgJch7ADgDFAgAUAAgJch7ADgDFAgALAAEJRQx0jQAtAAAAAA==.Purppally:BAAALgADCgUJCAAAAA==.Purrplerain:BAABLgAECn8cAAMXAAgJ7iHqAABOAgARAAgJPB0UEgCIAgAXAAgJUB7qAABOAgAAAA==.',
['Pà']='Pàarthurnax:BAAALgAECgQJBAAAAA==.',
['Pá']='Páïnful:BAAALgADCggJEQAAAA==.',
Ra='Rahios:BAAALgAECgEJAQAAAA==.Raikeji:BAAALgAECgIJAgABLgAECgYJCgAWAAAAAA==.Rainan:BAAALgAECgEJAQAAAA==.Raisins:BAACLgAFFH8RAAIdAAUJnyGPAQD5AQAdAAUJnyGPAQD5AQAuAAQKfyAAAx0ACAllI7MDADYDAB0ACAllI7MDADYDAA8ABAk3FKi5ABIBAAAA.Raisyns:BAAALgAECgkJBwABLgAFFAUJEQAdAJ8hAA==.Raizins:BAAALgADCgEJAQABLgAFFAUJEQAdAJ8hAA==.Ramune:BAAALgADCgEJAQAAAA==.Ranal:BAAALgADCgUJBQABLgAECgIJBQAWAAAAAA==.Raptorguin:BAAALgAECgYJEQAAAA==.Raulothim:BAAALgAECgYJEQAAAA==.',
Re='Retribussy:BAAALgAECgMJCAAAAA==.Rezmir:BAAALgADCgQJBAAAAA==.',
Ri='Ricemachinex:BAAALgAECgYJDQABLgAFFAUJDQAPAHcUAA==.Ricemachnedk:BAACLgAFFH8LAAIMAAMJtyVJFgBLAQAMAAMJtyVJFgBLAQAuAAQKfxoAAgwABwl3JjMfAMYCAAwABwl3JjMfAMYCAAEuAAUUBQkNAA8AdxQA.Ricos:BAAALgAECgEJAQAAAA==.',
Ro='Roan:BAAALgAECgIJBQAAAA==.Rockky:BAAALgADCgYJBgAAAA==.Rocthar:BAABLgAECn8UAAIPAAgJnRUnQAAlAgAPAAgJnRUnQAAlAgAAAA==.Romeoposter:BAAALgAECgQJBQAAAA==.Rotandroll:BAAALgAECgQJBwABLgAECggJIwAfAGMmAA==.Roundhouse:BAAALgAECgIJBQAAAA==.Rovak:BAAALgADCgYJCQAAAA==.',
Ru='Rukarazyll:BAAALgADCgcJCwAAAA==.Ruush:BAAALgAFFAEJAQAAAA==.',
['Rë']='Rëquiëm:BAAALgADCgIJAgAAAA==.',
Sa='Saelbrine:BAAALgADCgEJAQAAAA==.Saeletar:BAAALgADCgcJBwAAAA==.Saihua:BAAALgAECgYJDwAAAA==.Saintjohn:BAAALgAECgkJCwAAAA==.Saintrob:BAAALgAECgEJAgAAAA==.Salamando:BAACLgAFFH8PAAMmAAUJTxidAgBaAQAmAAUJpRSdAgBaAQAYAAMJpxg+EAAAAQAuAAQKfyEAAxgACQkOIAALAMYCABgACAnhHwALAMYCACYABQnJIMYUAJ0BAAAA.',
Sc='Scaryspices:BAAALgADCgIJAgAAAA==.Schlacht:BAAALgAFFAEJAQAAAA==.Scholoman:BAAALgAECgcJDQAAAA==.',
Se='Senpai:BAACLgAFFH8QAAIBAAUJbBg6CwDDAQABAAUJbBg6CwDDAQAuAAQKfxwAAgEACAnjI5QhAO0CAAEACAnjI5QhAO0CAAAA.',
Sh='Shadowborn:BAABLgAECn8WAAIMAAkJURgxBQA4AgAMAAkJURgxBQA4AgABLgAFFAMJCAABAJAaAA==.Shalanthra:BAAALgAECgIJAgAAAA==.Shamallow:BAAALgADCgMJAQAAAA==.Shammunition:BAABLgAECn8jAAIfAAgJYyYmAADwAgAfAAgJYyYmAADwAgAAAA==.Shanks:BAAALgADCgEJAQABLgAFFAQJBwADAF0NAA==.Shaqueefa:BAAALgAECgIJAgAAAA==.Shartner:BAAALgADCgEJAQAAAA==.Shartz:BAAALgAECgYJDwAAAA==.Shaysa:BAAALgAECgYJCgAAAA==.Sheraa:BAAALgAECgUJCQAAAA==.Shinigamisan:BAABLgAECn8ZAAIBAAgJ9g/FhQDGAQABAAgJ9g/FhQDGAQAAAA==.Shinycoco:BAAALgADCgcJBwAAAA==.Shynox:BAAALgAECgYJEAAAAA==.',
Si='Sisirinah:BAAALgAECgQJBAAAAA==.Sitharco:BAAALgAECgYJDwAAAA==.',
Sk='Skag:BAACLgAFFH8QAAMMAAQJRx+xEABeAQAMAAQJRx+xEABeAQAgAAEJ3wOvBABFAAAuAAQKfyYAAwwACAnRInsWAPUCAAwACAnRInsWAPUCACAAAQlMImQVAD8AAAAA.Skarlotta:BAAALgADCgcJBwAAAA==.',
Sm='Smedley:BAAALgADCgcJBwAAAA==.Smorc:BAAALgAECgcJDAAAAA==.',
Sn='Snackwitch:BAAALgAECgQJCQAAAA==.Snapgabagura:BAAALgAECgMJBAAAAA==.Sncbmspd:BAAALgADCgUJBQAAAA==.Sneaki:BAAALgAECggJEAABLgAECggJGAADAF8jAA==.Snixa:BAAALgADCgEJAQAAAA==.Snowproblem:BAAALgAECgQJBgAAAA==.',
So='Sommin:BAAALgAECgQJBgAAAA==.Sophelna:BAAALgADCgkJCQAAAA==.Sorno:BAAALgAECgIJAgAAAA==.Sorscha:BAAALgAECgUJBwAAAA==.Souljin:BAAALgAECgYJDwAAAA==.Soulviper:BAABLgAECn8gAAMOAAkJsiEMAwBMAwAOAAkJsiEMAwBMAwAeAAEJ2QXgjgApAAAAAA==.',
Sp='Spamming:BAAALgADCgEJAQAAAA==.Spankmaster:BAAALgAECgMJAwAAAA==.Spankmyflank:BAAALgAECgEJAQABLgAECgMJBAAWAAAAAA==.Spankshubby:BAAALgADCgcJBwAAAA==.Spiritbear:BAAALgAECgQJBQAAAA==.Spurb:BAAALgAECggJBgAAAA==.',
Sq='Squaleon:BAAALgAECgQJBgAAAA==.',
St='Stabbyfinch:BAAALgAECgQJCgAAAA==.Starthirteen:BAAALgAECgYJDwAAAA==.Steatfox:BAAALgADCgMJAwAAAA==.Stelf:BAAALgADCgQJBAABLgAECgYJEQAWAAAAAA==.Steplok:BAAALgAECgcJDgAAAA==.Steroidz:BAAALgADCgEJAQAAAA==.Stonestriker:BAAALgAECgQJCAAAAA==.Stranglehold:BAAALgAECgIJAgAAAA==.Strixz:BAAALgADCgMJAwAAAA==.Sturge:BAAALgAECgYJDAAAAA==.',
Su='Supahsayajin:BAEALgAECgMJBAABLgAECgUJBQAWAAAAAA==.Survival:BAAALgADCgcJBwABLgABCgUJBQAWAAAAAA==.',
Sw='Sweetapple:BAAALgAECgMJBgAAAA==.Sweetbee:BAAALgAECgYJCgAAAA==.Sweetivy:BAAALgADCgMJAwAAAA==.Swole:BAABLgAECn8dAAIPAAgJ1BgcBwAbAgAPAAgJ1BgcBwAbAgAAAA==.Swoleefist:BAEALgAECgYJDQAAAA==.',
Sy='Syanalody:BAAALgAECgEJAQAAAA==.Syanaria:BAAALgADCgcJDwABLgAECgEJAQAWAAAAAA==.Sylarz:BAAALgAECgIJAwABLgAECggJKQAHALcfAA==.Synackle:BAABLgAECn8gAAQHAAgJQR2gDwCVAQAHAAgJQR2gDwCVAQAIAAMJWRpROwDHAAAJAAIJiiB0BgBkAAAAAA==.Synthica:BAAALgADCgUJBgABLgAECggJGQAbAB0kAA==.',
Sz='Szayelaporro:BAAALgADCgcJBwAAAA==.',
['Sð']='Sðrrøw:BAAALgADCgcJBwAAAA==.',
Ta='Talyeria:BAAALgADCgUJBwAAAA==.Tanstaafl:BAABLgAECn8YAAIUAAgJBhOlNQDYAQAUAAgJBhOlNQDYAQAAAA==.Taralom:BAAALgAECgQJCgAAAA==.Tasselhoff:BAAALgADCgQJBAAAAA==.Taz:BAEBLgAECn8XAAInAAYJtSNEBQBWAgAnAAYJtSNEBQBWAgAAAA==.Tazroc:BAAALgADCgMJAwABLgADCgQJBAAWAAAAAA==.',
Te='Tehrocklee:BAAALgADCgcJDgAAAA==.Telmo:BAABLgAECn8kAAIGAAgJ4htYDgB3AgAGAAgJ4htYDgB3AgAAAA==.Tenebrix:BAAALgAECgMJAwAAAA==.Teracgosa:BAAALgAECgYJDgAAAA==.Teuton:BAAALgAECgYJBwAAAA==.',
Th='Thadex:BAAALgAECgYJCwAAAA==.Thassa:BAAALgAECgEJAgAAAA==.Thecolonel:BAAALgADCgUJBQAAAA==.Theholytank:BAAALgAECgEJAQAAAA==.Thepallyguy:BAAALgADCgkJDQABLgAECgYJDwAWAAAAAA==.Thepriestguy:BAAALgAECgYJDwAAAA==.Therat:BAAALgADCgIJAgAAAA==.Thorseas:BAABLgAECn8VAAITAAYJESNBAwDQAQATAAYJESNBAwDQAQAAAA==.Thundastruck:BAAALgADCgEJAQAAAA==.',
Ti='Tiertrah:BAAALgADCgUJBQAAAA==.Tiger:BAAALgAECgYJBgAAAA==.Titùs:BAABLgAECn8fAAIBAAgJNRFbEwCmAQABAAgJNRFbEwCmAQAAAA==.',
To='Tooyoo:BAACLgAFFH8RAAMFAAUJaiFoAQDyAQAFAAUJaiFoAQDyAQAiAAMJIR26AgDLAAAuAAQKfxwAAwUACAlhJBkIACkDAAUACAlhJBkIACkDACIAAwk5IiolAMQAAAAA.Torpedotaka:BAAALgAECgYJCQAAAA==.',
Tp='Tpala:BAAALgAECgcJEAAAAA==.',
Ts='Tsukirius:BAAALgAECgEJAQABLgAECggJHgARAF4aAA==.',
Tu='Tulkas:BAAALgAECgEJAgAAAA==.Turthunt:BAACLgAFFH8SAAQLAAYJAxx7AgA6AgALAAYJAxx7AgA6AgAUAAIJjxIzFwCqAAATAAEJag85BwBYAAAuAAQKfycAAwsACQk7JrECAIQDAAsACAlWJrECAIQDABQAAQl5JaWrAG0AAAAA.Turtlock:BAABLgAECn8XAAIHAAkJ7R/fBABtAwAHAAkJ7R/fBABtAwABLgAFFAYJEgALAAMcAA==.',
Tw='Twinkdaddy:BAAALgAECgYJDQAAAA==.Twoyoo:BAAALgAECgEJAgABLgAFFAUJEQAFAGohAA==.',
Ty='Tygr:BAAALgAECgUJCgAAAA==.Tyndriel:BAAALgAECgUJBwAAAA==.Tyremon:BAAALgADCgYJBgAAAA==.Tyrraell:BAAALgADCgMJAwAAAA==.',
Un='Uninclined:BAAALgADCgUJBQAAAA==.Unsurpassed:BAAALgAECgIJBAAAAA==.',
Va='Valaid:BAABLgAECn8WAAIEAAYJOh/6BAB+AQAEAAYJOh/6BAB+AQAAAA==.Valakar:BAAALgAECgUJBgAAAA==.Valoth:BAAALgAECgQJBAAAAA==.Vanelura:BAAALgAECgQJBgAAAA==.',
Ve='Veyle:BAAALgAECgUJBQAAAA==.',
Vi='Villager:BAAALgADCgcJBwAAAA==.Vistray:BAAALgAECgEJAQAAAA==.',
Vo='Voidsorrow:BAAALgADCgQJBAAAAA==.Volassian:BAAALgADCgIJAgAAAA==.',
Vr='Vrahalla:BAAALgAECgUJCQAAAA==.',
Vy='Vyrana:BAAALgAECgMJBgAAAA==.',
Wa='Wahstella:BAACLgAFFH8PAAIBAAYJUBbDCgDIAQABAAYJUBbDCgDIAQAuAAQKfysAAgEACQm1JBMEAL8DAAEACQm1JBMEAL8DAAAA.Waraight:BAACLgAFFH8KAAINAAUJLRbkBABXAQANAAUJLRbkBABXAQAuAAQKfxUAAg0ACAkdHm0MAEoCAA0ACAkdHm0MAEoCAAAA.Wararrior:BAABLgAFFH8IAAIbAAQJHB0FAwBrAQAbAAQJHB0FAwBrAQABLgAFFAUJCgANAC0WAA==.Wasabi:BAACLgAFFH8HAAIDAAQJXQ3+EwAyAQADAAQJXQ3+EwAyAQAuAAQKfxoAAgMACAkoIoATAOQCAAMACAkoIoATAOQCAAAA.Waterdroplet:BAAALgAECggJDgAAAA==.',
We='Weedcookies:BAAALgADCgMJAwABLgADCgYJDAAWAAAAAA==.',
Wh='Whitelady:BAABLgAECn8gAAIhAAgJoBTKBADNAQAhAAgJoBTKBADNAQAAAA==.Whodofthunk:BAAALgAECgYJCgAAAA==.',
Wi='Wilferth:BAABLgAECn8ZAAIbAAcJaRd6EwDTAQAbAAcJaRd6EwDTAQAAAA==.Winterhogman:BAAALgADCgYJBgABLgAECgUJDAAWAAAAAA==.Wirl:BAAALgADCgEJAQAAAA==.',
Wo='Woozi:BAACLgAFFH8MAAIOAAUJbRI6AwCmAQAOAAUJbRI6AwCmAQAuAAQKfxkAAw4ABwkUJB8TAH0CAA4ABwkUJB8TAH0CAB4ABQmTEPZKABsBAAAA.',
Wr='Wreckedon:BAAALgAECgMJAwAAAA==.Wrekker:BAAALgADCgMJAwAAAA==.Wrinklz:BAABLgAECn8UAAIBAAYJ0AjDMgD9AAABAAYJ0AjDMgD9AAAAAA==.',
Wu='Wulgarr:BAABLgAECn8ZAAIbAAgJHSSlAgA9AwAbAAgJHSSlAgA9AwAAAA==.',
Xa='Xavierson:BAAALgAECgQJCgAAAA==.',
Xe='Xen:BAAALgAECgQJBQABLgABCgUJBQAWAAAAAA==.',
Xi='Xiaoxiao:BAAALgAECgEJAQAAAA==.Xilone:BAAALgAECgYJDgAAAA==.',
Ya='Yangchengfu:BAABLgAECn8gAAIbAAcJWw8jHgBUAQAbAAcJWw8jHgBUAQAAAA==.',
Ye='Yelpies:BAAALgADCgUJBwABLgABCgUJBQAWAAAAAA==.',
Yo='Yoinksower:BAAALgAECgYJDgAAAA==.Yootoo:BAAALgAECgUJBQABLgAFFAUJEQAFAGohAA==.Youkai:BAABLgAECn8WAAIMAAYJPSBdDQCyAQAMAAYJPSBdDQCyAQAAAA==.',
Za='Zaaga:BAAALgAECgcJEgAAAA==.Zalarok:BAAALgAECgUJCAABLgAECggJKQAHALcfAA==.Zalianna:BAAALgADCgQJBAAAAA==.Zamyk:BAAALgAECgMJAwAAAA==.Zarf:BAABLgAECn8dAAITAAcJJxKWBgBYAQATAAcJJxKWBgBYAQAAAA==.Zaviar:BAAALgADCggJDAAAAA==.Zayra:BAAALgADCgUJCgAAAA==.',
Ze='Zelgius:BAABLgAECn8mAAIMAAgJUyTVAQCuAgAMAAgJUyTVAQCuAgAAAA==.Zenasdara:BAAALgAECgMJAgAAAA==.Zenerap:BAAALgAECgEJAQAAAA==.Zenhunter:BAAALgAECgYJDwAAAA==.Zevilna:BAAALgAECgYJEgAAAA==.',
Zh='Zhongfu:BAABLgAECn8ZAAICAAgJHhJHHAD5AQACAAgJHhJHHAD5AQAAAA==.Zhulee:BAABLgAECn8ZAAICAAgJWiLPBgASAwACAAgJWiLPBgASAwAAAA==.',
Zi='Zikaja:BAACLgAFFH8UAAIKAAUJeRQmBgBxAQAKAAUJeRQmBgBxAQAuAAQKfykAAgoACQkUGQQPAKcCAAoACQkUGQQPAKcCAAAA.Zins:BAAALgADCgQJBAAAAA==.Zinu:BAAALgAECgEJAQAAAA==.Zir:BAAALgAECgEJAwAAAA==.Ziviana:BAACLgAFFH8VAAIQAAUJVxxvAQC/AQAQAAUJVxxvAQC/AQAuAAQKfyoAAhAACQlUI3cEAEcDABAACQlUI3cEAEcDAAAA.',
Zo='Zoark:BAAALgADCgEJAQAAAA==.Zorgap:BAAALgAECgEJAQAAAA==.Zoryp:BAAALgADCgIJAgAAAA==.',
Zu='Zuldope:BAAALgAECgQJBAAAAA==.',
Zv='Zv:BAAALgAFFAIJAwAAAA==.',
Zy='Zyprexal:BAABLgAECn8bAAMQAAcJcSA0FgCFAgAQAAcJcSA0FgCFAgARAAYJ4BUaNgBjAQAAAA==.',
['Zï']='Zïlla:BAAALgADCgYJBgAAAA==.Zïn:BAAALgAECgMJBAAAAA==.',
['Ðr']='Ðraven:BAAALgAECgkJBAAAAA==.',
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

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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Paladin-Holy','Paladin-Retribution','Priest-Holy','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Paladin-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Hunter-Marksmanship','Rogue-Subtlety','DeathKnight-Frost','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aairidari:BAABLgAECn8ZAAIBAAYJ2g5aGQAVAQABAAYJ2g5aGQAVAQAAAA==.',
Ab='Abruna:BAAALgAECgcJEgABLgAFFAUJFQACAK4cAA==.Abruno:BAACLgAFFH8VAAICAAUJrhw0IABoAQACAAUJrhw0IABoAQAuAAQKfyYAAgIACQn+IAgQAEgDAAIACQn+IAgQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAUJFQACAK4cAA==.',
Ad='Adrians:BAABLgAECn8lAAICAAgJERWYLQDrAQACAAgJERWYLQDrAQAAAA==.',
Ae='Aeown:BAABLgAECn8bAAMDAAcJpQkJLAAwAQADAAcJpQkJLAAwAQAEAAEJagKMGwEmAAABLgAECgkJKgAFAFIUAA==.Aerdis:BAAALgAECgMJBAABLgAECgYJDAAGAAAAAA==.',
Ag='Aggerwator:BAAALgAECgEJAgABLgAECgcJFgAHAMohAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAECgQJCgABLgAFFAQJDAAIAIkYAA==.',
Al='Alahrî:BAABLgAECn8sAAQJAAkJdBDlFgDiAQAJAAkJdBDlFgDiAQAKAAYJrQw7BwBHAQALAAYJXQuLKwD8AAAAAA==.Alandrìas:BAABLgAECn8jAAIMAAgJsg93CABbAQAMAAgJsg93CABbAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3VBQA9AwANAAkJsB3VBQA9AwAAAA==.Altera:BAABLgAECn8mAAIJAAgJXxdMBgAiAgAJAAgJXxdMBgAiAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAICAAcJ2grrcwApAQACAAcJ2grrcwApAQAAAA==.Amuri:BAAALgAECgYJCQAAAA==.',
An='Andere:BAAALgAECggJCQAAAA==.Androonatorz:BAACLgAFFH8WAAIDAAUJrB0aCACaAQADAAUJrB0aCACaAQAuAAQKfyQAAwMACQlDH1YHAPcCAAMACQlDH1YHAPcCAAQABAn+ETm+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAAALgAECgEJAwAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgAAAA==.Ardemus:BAABLgAECn8XAAMOAAYJIBKWDQD5AAAOAAYJIBKWDQD5AAAPAAEJYAAUNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgMJBwAAAA==.',
As='Ashborrn:BAAALgAECgUJBwAAAA==.Ashtar:BAABLgAECn8RAAIHAAgJmhOdHgB1AQAHAAgJmhOdHgB1AQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgUJBQABLgAECgkJHgAQANoVAA==.',
Aw='Awaken:BAAALgAECgcJEgAAAA==.Awoomonk:BAAALgAECgIJAgAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8UAAMRAAUJIBYXGABFAQARAAQJIBYXGABFAQASAAEJAABPMQAAAAAuAAQKfyEAAhEACAlFIVwVAPsCABEACAlFIVwVAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8jAAMPAAkJYRgiGAAhAgAPAAkJYRgiGAAhAgAOAAIJ7RjHIgBLAAAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgIJAgABLgAECggJIAATAJgNAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECgMJBAAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn8mAAICAAgJDiCSFwBfAgACAAgJDiCSFwBfAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn8pAAINAAkJtxmZCQAzAgANAAkJtxmZCQAzAgAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgADCgkJDwAAAA==.Bluewaffles:BAAALgAECgEJAgAAAA==.',
Bo='Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8XAAIUAAUJKCQ3BACgAQAUAAUJKCQ3BACgAQAuAAQKfyYAAhQACQnDI4MEAE0DABQACQnDI4MEAE0DAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHAAVADoZAA==.Brimara:BAAALgAFFAEJAQAAAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECgcJCQAGAAAAAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJHgABAHYNAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8aAAQWAAgJfR/rBwD/AQAWAAcJTx3rBwD/AQAXAAgJ7B3KDQBmAQAHAAYJGw+YUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMEAAYJehnNaAAcAQAEAAYJTRnNaAAcAQAYAAEJpgQ+SQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAQAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd4KwCmAQANAAcJBBV4KwCmAQAZAAcJkxcRLgBrAQAaAAIJ+gALOwAYAAAAAA==.Capz:BAACLgAFFH8eAAMXAAcJZCApAABHAgAXAAcJqB4pAABHAgAHAAUJiiJSBwB3AQAuAAQKfyEAAxcACQnPIzsDANsCABcACAkCJTsDANsCAAcACQlnFpkPANYCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgMJBAAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECgEJAQAAAA==.',
Cd='Cdlam:BAAALgADCgcJBwAAAA==.',
Ce='Ceez:BAAALgAECgYJDQAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAECgkJIQACAKMVAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chongy:BAAALgAECgIJAwABLgAECgcJDQAGAAAAAA==.Chopperr:BAAALgAECgQJBAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAABLgAECn8hAAICAAkJoxXIcADyAQACAAkJoxXIcADyAQAAAA==.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8NAAIOAAQJMBTlAQBSAQAOAAQJMBTlAQBSAQAuAAQKfzcAAg4ACQntIy8AAEUDAA4ACQntIy8AAEUDAAAA.Clow:BAABLgAECn8WAAMHAAcJyiHLGgB1AgAHAAYJhyPLGgB1AgAXAAMJcRr0KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8dAAMbAAcJqSP8CAAuAgAbAAcJyB/8CAAuAgAcAAYJnyGVDgDeAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8SAAIPAAUJbhkMGgBLAQAPAAUJbhkMGgBLAQAuAAQKfzQAAw8ACQklHZARAFcCAA8ACQklHZARAFcCABUAAQkAALg0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgcJBwAAAA==.Cryovox:BAAALgADCgIJAgAAAA==.',
Cu='Cumazzing:BAACLgAFFH8NAAIEAAUJ+CQjBgCNAQAEAAUJ+CQjBgCNAQAuAAQKfx0AAgQACQk4JbUCAK4DAAQACQk4JbUCAK4DAAAA.',
Da='Dadrin:BAAALgADCggJDgAAAA==.Daedyxes:BAAALgAECgYJEAAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Darfretail:BAABLgAECn8WAAIHAAgJAhF+HACEAQAHAAgJAhF+HACEAQAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgADCggJDQAAAA==.Daygath:BAABLgAECn8hAAIdAAgJ7BIzFgCgAQAdAAgJ7BIzFgCgAQAAAA==.',
De='Deadlyiris:BAABLgAECn8fAAMXAAkJlR1GAgCmAgAXAAkJlR1GAgCmAgAHAAYJHxCVSgB7AQABLgAECgYJFQAeAF8jAA==.Deatharin:BAAALgAECgYJDQAAAA==.Demonbulio:BAABLgAECn8fAAIBAAgJOhFbDgCcAQABAAgJOhFbDgCcAQAAAA==.Demonisthicc:BAAALgAECgIJAwABLgAECgkJHAAVADoZAA==.Demonskitten:BAABLgAECn8cAAIVAAkJOhk2AgARAgAVAAkJOhk2AgARAgAAAA==.Demonslayeer:BAAALgADCgMJBQAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn8sAAIEAAgJgRWWNgCjAQAEAAgJgRWWNgCjAQAAAA==.Dithehealer:BAABLgAECn8ZAAMYAAgJbh5xBQAcAgAYAAgJbh5xBQAcAgAEAAEJmQdpTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAICAAYJQR60RgCTAQACAAYJQR60RgCTAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECggJGQAfAMwSAA==.Doogie:BAAALgADCgEJAQAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAGAAAAAA==.Dragømir:BAAALgAECgEJAQAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8WAAMKAAUJDCLnAQB9AQAKAAUJBCHnAQB9AQALAAMJESLKFgAsAQAuAAQKfyQAAwoACQnrJAgBAF0DAAoACAmKJQgBAF0DAAsABgnOIowVAJgBAAAA.Drenamai:BAAALgAECgYJEQAAAA==.Drewetta:BAABLgAECn8bAAINAAgJpwxPGgBlAQANAAgJpwxPGgBlAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.Durbana:BAAALgAECgMJAwAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgUJBQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8JAAIEAAMJPSSLDgA2AQAEAAMJPSSLDgA2AQAuAAQKfzAAAgQACQlZJa4BAMgDAAQACQlZJa4BAMgDAAEuAAUUBQkNAAQA+CQA.',
El='Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8NAAIgAAUJcwetCwApAQAgAAUJcwetCwApAQAuAAQKfxQAAiAACAkUDRwmAMgBACAACAkUDRwmAMgBAAAA.Elvwyr:BAAALgADCgQJBQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8KAAIdAAUJihW9DwAwAQAdAAUJihW9DwAwAQAuAAQKfyAAAx0ACAkkHtQTAIACAB0ACAkkHtQTAIACAB4ABAk3CaN1ALoAAAAA.Emmy:BAAALgAECgYJDwAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAAALgAFFAEJAQABLgAFFAUJFQABAFsfAA==.Endorush:BAACLgAFFH8VAAQBAAUJWx/0AQB7AQABAAQJqB30AQB7AQAIAAUJOxTEHgAxAQAMAAEJECe3AwB2AAAuAAQKfy0AAwEACQl8JXMAAOgDAAEACQl8JXMAAOgDAAgABQkPG8c7AEgBAAAA.Eneldenes:BAAALgAECgEJAQAAAA==.Enjoyer:BAAALgAECgYJEAAAAA==.',
Er='Ereitherla:BAABLgAECn8gAAITAAcJcAs6PwBRAQATAAcJcAs6PwBRAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgIJAgAAAA==.',
Ex='Excalibear:BAABLgAECn8jAAIDAAgJ8BRvHAClAQADAAgJ8BRvHAClAQABLgAFFAUJDwACAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJEQAAAA==.',
Fa='Fatherjeff:BAAALgADCgkJDQAAAA==.',
Fe='Feironor:BAAALgAECgEJAQAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fistbroz:BAAALgAECggJDgABLgAFFAUJFwAbABYSAA==.',
Fl='Flawpeacok:BAABLgAECn8aAAIRAAkJBRcqHAAgAgARAAkJBRcqHAAgAgAAAA==.Fleredil:BAABLgAECn8vAAMFAAcJlRU1IQDZAQAFAAcJlRU1IQDZAQAUAAYJsB/dDwDRAQAAAA==.Flingernle:BAAALgAECgEJAQAAAA==.Floista:BAAALgAECgYJBgAAAA==.Floistas:BAAALgAECgQJBAAAAA==.',
Fo='Forepray:BAAALgAECgQJBgABLgAFFAUJFAAHAMgcAA==.Forger:BAABLgAECn8jAAIWAAgJohKwDACZAQAWAAgJohKwDACZAQAAAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8RAAQRAAUJaiSjDgCbAQARAAQJaiSjDgCbAQAhAAMJ7xKGAQC4AAASAAEJAABgLgAAAAAuAAQKfzEABBEACQkFJG0MADcDABEACQkDJG0MADcDACEABgltIuoEAJABABIAAQljDnFBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJIwAPAFseAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAACLgAFFH8GAAIRAAMJRBJ3TQD0AAARAAMJRBJ3TQD0AAAuAAQKfy4AAhEACAllItsLAKkCABEACAllItsLAKkCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQIAAgJziImCgCGAgAIAAgJliImCgCGAgAMAAIJqiMcFwBnAAABAAIJTxiTNwBIAAAAAA==.Future:BAAALgAECgYJDQABLgAECggJKwAiAJMlAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaerlan:BAAALgADCgYJBgAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgADCgEJAQAAAA==.',
Gh='Ghostblades:BAACLgAFFH8TAAMRAAUJZRdjFQBOAQARAAUJZRdjFQBOAQAhAAEJAACJCwAAAAAuAAQKfyMAAxEACQlbID8bANoCABEACQlbID8bANoCACEAAQnbHDQWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBAABLgAFFAcJFQAUAAAZAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAAALgAECgUJBgABLgAFFAUJDwACAEQaAA==.',
Gr='Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAAALgADCgIJAgABLgAECgkJNwAEAA4dAA==.Grinny:BAABLgAECn83AAMEAAkJDh2aCgCxAgAEAAkJDh2aCgCxAgADAAIJowMrjQBKAAAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8aAAIEAAgJdQpRUABVAQAEAAgJdQpRUABVAQABLgAECgYJFQAeAF8jAA==.Havochunter:BAAALgAECgcJCQAAAA==.',
He='Heidegger:BAAALgAECgIJAgAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8ZAAIfAAgJzBISBwCdAQAfAAgJzBISBwCdAQAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgMJBgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECgMJBAAAAA==.Hunterdh:BAABLgAECn8ZAAITAAYJTgmrWwD9AAATAAYJTgmrWwD9AAAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8UAAIHAAUJyBwGCQBZAQAHAAUJyBwGCQBZAQAuAAQKfygAAgcACAlcILcOAN4CAAcACAlcILcOAN4CAAAA.',
Ic='Icecandie:BAAALgAECgYJDQAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAUJFgAKAAwiAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJKgAFAFIUAA==.',
Im='Imistmypants:BAAALgAECgcJDQAAAA==.',
In='Infinitevoid:BAAALgADCgQJBAAAAA==.Innervatez:BAABLgAFFH8MAAIZAAcJ9BdhAgBAAgAZAAcJ9BdhAgBAAgAAAA==.Inspectda:BAABLgAECn8VAAIPAAgJgwcPdgBxAQAPAAgJgwcPdgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8bAAIJAAgJJBvHBQA0AgAJAAgJJBvHBQA0AgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn8kAAICAAgJ0hVRMQDbAQACAAgJ0hVRMQDbAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn8uAAICAAkJBSRzAwBHAwACAAkJBSRzAwBHAwAAAA==.Jarten:BAABLgAECn8XAAIhAAcJ5SIcAgAyAgAhAAcJ5SIcAgAyAgAAAA==.Jaylebate:BAABLgAECn8oAAMRAAgJnhxMHQAYAgARAAgJmRtMHQAYAgASAAIJIxE3LABsAAAAAA==.',
Je='Jerrenn:BAAALgAECggJEgAAAA==.Jesseatamer:BAABLgAECn8YAAITAAcJ0SQUDgBpAgATAAcJ0SQUDgBpAgAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jouska:BAAALgAECgYJCgABLgAECgcJBwAGAAAAAA==.',
Ju='Judge:BAAALgADCgEJAQAAAA==.Justar:BAAALgADCgIJAgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAAALgAFFAEJAQAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAAALgAECgkJEgAAAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Kastia:BAAALgAECgMJBQAAAA==.Katrynwel:BAAALgAECgcJCwAAAA==.Katsumi:BAAALgADCgkJKAAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgMJAwAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.',
Ki='Killalltoday:BAABLgAECn8lAAMeAAgJGxEGKAB/AQAeAAgJGxEGKAB/AQAjAAYJbwrCDwAHAQAAAA==.Kilon:BAAALgAECgEJAgAAAA==.Kirkk:BAAALgADCgkJFAAAAA==.Kixarea:BAAALgADCgkJDQABLgAECgkJHAAZAGQfAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAAALgAECgYJDQAAAA==.Knixx:BAACLgAFFH8SAAMUAAQJYQkoDgArAQAUAAQJYQkoDgArAQAkAAQJXwjmHQChAAAuAAQKfzEABBQACQlqFfULAAYCABQACQlqFfULAAYCAAUABwk6GGIbAAECACQABgldEMItADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIcAAkJUxHSEwCfAQAcAAkJUxHSEwCfAQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIQAAkJmhgIBwCMAgAQAAkJmhgIBwCMAgAAAA==.Koyya:BAAALgAECgkJEwAAAA==.',
Ku='Kufoo:BAABLgAECn8lAAIHAAgJSCU4AgD/AgAHAAgJSCU4AgD/AgAAAA==.Kuma:BAAALgAECgUJCQABLgAECggJKwAiAJMlAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAAALgAECgcJEAAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
La='Layez:BAAALgADCgUJBQABLgAECggJJAAVABogAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Lethe:BAAALgAECgUJBQABLgAFFAUJDQAgAHMHAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJKwATAPsaAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannrose:BAAALgAECgEJAQAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8kAAIPAAkJURc0JwDLAQAPAAkJURc0JwDLAQAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAABLgAECn8gAAINAAkJRgb+GwBVAQANAAkJRgb+GwBVAQAAAA==.',
Lu='Luania:BAAALgAECgMJBQAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgEJAQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAUJCgAdAIoVAA==.',
Ma='Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn8oAAMCAAgJwRUKMgDYAQACAAgJwRUKMgDYAQAlAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgMJBAAAAA==.Mamadeezy:BAAALgADCgcJDgAAAA==.Manical:BAAALgAECgIJAgAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAMJBwARAIYNAA==.Maxgoon:BAABLgAECn8WAAIPAAcJwgzNcwB2AQAPAAcJwgzNcwB2AQAAAA==.',
Me='Megumin:BAAALgAECgYJEgABLgAECgkJJAAEAA0gAA==.Mellisandria:BAAALgAECgUJBQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn8lAAIcAAgJGR9zBgBxAgAcAAgJGR9zBgBxAgAAAA==.Merriska:BAACLgAFFH8FAAMDAAIJxyDJHQCwAAADAAIJxyDJHQCwAAAEAAEJHRFCWwBOAAAuAAQKfxkAAwQACQlAIZ0lAJACAAQABwnzIZ0lAJACAAMACAm7IJoTAHUCAAEuAAUUAwkFABsAdBsA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJDQAAAA==.Misseslovett:BAAALgADCgQJBAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8VAAImAAUJVBCEBAD4AAAmAAUJVBCEBAD4AAAuAAQKfzMAAiYACQnwGbQDAFACACYACQnwGbQDAFACAAAA.Mithras:BAAALgAECgEJAQAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAABLgAECn8oAAIDAAkJGyaxAQBoAwADAAkJGyaxAQBoAwAAAA==.Morgause:BAAALgAECgYJDQABLgAECggJHAANALoLAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAABLgAECn8aAAITAAgJ+BCKKQCrAQATAAgJ+BCKKQCrAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMXAAkJYCJ2AgCdAgAXAAkJbCF2AgCdAgAHAAUJNRtlTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJIwAPAFseAA==.',
Na='Naanomage:BAAALgAECgQJBwAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn8jAAMPAAkJWx50CwCXAgAPAAgJWx50CwCXAgAOAAEJAADsXABYAAAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMIAAkJrxzfIQCGAgAIAAkJOhrfIQCGAgABAAUJBCGuJgCLAQAAAA==.Nirath:BAABLgAECn8kAAIKAAgJrgo2BgBsAQAKAAgJrgo2BgBsAQAAAA==.',
No='Noiire:BAAALgAECgIJAgABLgAFFAUJDQAgAHMHAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8NAAIUAAQJoyXOAgDFAQAUAAQJoyXOAgDFAQAuAAQKfywAAhQACAkIJtEBAAoDABQACAkIJtEBAAoDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn8eAAIBAAkJdg3aDACzAQABAAkJdg3aDACzAQAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAAALgAECgUJBQAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJFAAgAKkaAA==.',
Oa='Oakly:BAABLgAECn8kAAIZAAcJjRsWFwAMAgAZAAcJjRsWFwAMAgAAAA==.',
Ob='Obsidian:BAAALgADCgIJAgABLgAECgkJKAADABsmAA==.',
On='Onaroll:BAAALgAFFAIJBAABLgAFFAUJEwAZABEYAA==.',
Oo='Ooyagoddess:BAAALgAECgQJCgAAAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8XAAIbAAYJGSK0EwCUAQAbAAYJGSK0EwCUAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pann:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8gAAIdAAcJHxlWFQCpAQAdAAcJHxlWFQCpAQAAAA==.Pawsa:BAABLgAECn8eAAMbAAYJyBi4FgByAQAbAAYJyBi4FgByAQAcAAMJWQ+eagCYAAAAAA==.Pawthetic:BAACLgAFFH8TAAIZAAUJERgXCwCNAQAZAAUJERgXCwCNAQAuAAQKfyYAAhkACQkDIT0DAGEDABkACQkDIT0DAGEDAAAA.',
Pe='Peelforheals:BAABLgAECn8hAAMkAAcJuxUXHAC1AQAkAAcJuxUXHAC1AQAUAAYJoRT3IQAwAQAAAA==.Penguindemic:BAABLgAECn8YAAIPAAcJHyYMHACtAgAPAAcJHyYMHACtAgAAAA==.Pentimus:BAAALgADCgYJBgABLgAECgcJDQAGAAAAAA==.Pep:BAABLgAECn8dAAMbAAkJnBveBACVAgAbAAkJnBveBACVAgAQAAEJUwMPcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAAALgAECgUJCgAAAA==.Pewpewlepew:BAAALgAECgYJCAAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgcJBwAGAAAAAA==.Phaeku:BAAALgAECgcJBwAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgUJCgABLgAECgcJHQAbAKkjAA==.',
Pr='Prey:BAAALgADCgEJAQAAAA==.Prospa:BAAALgAECgQJBQAAAA==.Prumper:BAACLgAFFH8FAAICAAQJ6QaxUwDPAAACAAQJ6QaxUwDPAAAuAAQKfzcAAgIACAnAHpMbAEQCAAIACAnAHpMbAEQCAAAA.',
Py='Pyric:BAAALgAECgEJAwAAAA==.',
Qu='Quesoblanco:BAAALgADCgcJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgQJBQAAAA==.',
Ra='Rabid:BAAALgADCgEJAQAAAA==.Raghallov:BAAALgADCggJCgAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8jAAIRAAkJthuhOQBQAgARAAkJthuhOQBQAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgEJAQAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn8qAAMFAAkJUhSFDwDyAQAFAAkJUhSFDwDyAQAkAAUJ2wk2OgDWAAAAAA==.Remorse:BAACLgAFFH8SAAIWAAUJqxG2CgAGAQAWAAUJqxG2CgAGAQAuAAQKfzEAAhYACQn/G2QEAG4CABYACQn/G2QEAG4CAAAA.Required:BAAALgAECgUJBwABLgAFFAcJGQAIANgbAA==.Retro:BAABLgAECn8XAAIdAAYJJAZYNwDQAAAdAAYJJAZYNwDQAAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8cAAMZAAkJZB84CQC1AgAZAAgJGSA4CQC1AgANAAEJxQimTwBHAAAAAA==.Rim:BAABLgAECn8qAAIeAAkJ5h37AwAHAwAeAAkJ5h37AwAHAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8GAAICAAMJ5hHpSQD1AAACAAMJ5hHpSQD1AAAuAAQKfyAAAgIACQleHGk0AKECAAIACQleHGk0AKECAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIRAAIJthvSZACuAAARAAIJthvSZACuAAAuAAQKfzcAAhEACQm6I4QGAG8DABEACQm6I4QGAG8DAAAA.Ronfar:BAACLgAFFH8NAAIjAAQJbhQyAwBGAQAjAAQJbhQyAwBGAQAuAAQKfzkAAiMACAnxIooBAL8CACMACAnxIooBAL8CAAAA.',
Ru='Rukidingme:BAAALgADCgcJDgAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8kAAIEAAcJ5AkfWwA6AQAEAAcJ5AkfWwA6AQAAAA==.Ryno:BAAALgAECgMJAwAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAAALgAECggJEQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgMJBAAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECgcJFwAhAOUiAA==.',
Sc='Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8WAAIbAAcJGBM6LAB+AQAbAAcJGBM6LAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQZAAgJdhy1JQAiAgAZAAcJ1By1JQAiAgANAAYJ+R5/HwADAgAmAAEJGQaXNQAfAAAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgcJCQAAAA==.Selen:BAABLgAECn8oAAIDAAgJwB+3BwCaAgADAAgJwB+3BwCaAgAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Seråphiel:BAAALgAECgQJEgAAAA==.Seswatha:BAACLgAFFH8PAAICAAUJRBp1GwBdAQACAAUJRBp1GwBdAQAuAAQKfyoAAgIACQncIacEAC0DAAIACQncIacEAC0DAAAA.',
Sh='Shadowbaron:BAAALgADCgkJGQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAAALgAECgkJEwABLgAFFAUJFgADAKwdAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgADCgYJBgABLgAECgYJEAAGAAAAAA==.Shocktop:BAAALgAECgYJDgAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAGAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Shådowfire:BAAALgADCgkJHwAAAA==.Shìft:BAABLgAECn8kAAIZAAgJRRkPEABVAgAZAAgJRRkPEABVAgAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgADCgYJBwAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAAALgAECgMJDAABLgAECgYJDwAGAAAAAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8XAAImAAYJHSRaBgDkAQAmAAYJHSRaBgDkAQAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQiAAgJkyWfAgBmAgACAAgJjyB6LQC8AgAiAAYJsiKfAgBmAgAlAAQJcx8HAwByAQAAAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAAALgAECgkJEQAAAA==.',
So='Sonicberger:BAAALgADCgQJBAABLgAECggJHgARADIYAA==.Sonicbergger:BAAALgAECgQJBAABLgAECggJHgARADIYAA==.Sonicpoe:BAAALgADCgkJDAABLgAECggJHgARADIYAA==.Sonícberger:BAABLgAECn8eAAMRAAgJMhjEKgDQAQARAAgJMhjEKgDQAQASAAEJkwlUPgAdAAAAAA==.Soulcaliber:BAAALgADCgEJAQAAAA==.',
St='Stain:BAAALgAECgQJBQAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stith:BAAALgADCgIJAgAAAA==.Stkinbck:BAABLgAECn8gAAIgAAcJjRDqEgCAAQAgAAcJjRDqEgCAAQAAAA==.Stonehenge:BAABLgAECn8VAAIeAAYJXyMrFwBcAgAeAAYJXyMrFwBcAgAAAA==.Stonepalm:BAAALgADCgcJCgAAAA==.Stratan:BAAALgAECgQJCAAAAA==.',
Su='Suffer:BAAALgAFFAEJAQABLgAECggJKwAiAJMlAA==.Sundermere:BAAALgAECgEJAQAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8XAAIEAAcJiSDPIwCZAgAEAAcJiSDPIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8XAAQbAAUJFhK1CgAmAQAbAAQJuAy1CgAmAQAcAAUJJwxHEAD+AAAQAAEJLgBkGgATAAAuAAQKfy8AAxwACQmHGk8SAIECABwACQnAFk8SAIECABsACAlmG3ITAFUCAAAA.',
Sy='Sylvia:BAAALgAECgMJBAAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgEJAQAAAA==.',
Ta='Tabbz:BAABLgAECn8oAAMdAAgJZhp4DAAUAgAdAAgJZhp4DAAUAgAeAAEJBQekpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgADCgcJBwAAAA==.Tallyhochick:BAABLgAECn8fAAITAAgJygmXNAB7AQATAAgJygmXNAB7AQAAAA==.Taman:BAABLgAECn8YAAMdAAcJOBalKADPAQAdAAcJOBalKADPAQAeAAYJaxWkQgD4AAAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telkon:BAAALgADCgYJBgAAAA==.Tellesto:BAABLgAECn8wAAMnAAkJnRw8BQBnAgAnAAkJqxo8BQBnAgATAAMJIhcKewCnAAAAAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgADCgcJBwAAAA==.Thebigonion:BAAALgAECgEJAQAAAA==.',
Ti='Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8jAAMcAAgJJxv1DgDZAQAcAAgJJxv1DgDZAQAbAAEJhhl+UABKAAAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJIgATALsfAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8iAAMTAAkJux8GDwDDAgATAAkJmB4GDwDDAgAnAAQJtxCxJQDLAAAAAA==.',
To='Toko:BAACLgAFFH8WAAITAAUJ2yEtAgB9AQATAAUJ2yEtAgB9AQAuAAQKfyMAAxMACQkjIuQIAAUDABMACQkjIuQIAAUDAB8AAQmjCg2MAC8AAAAA.Tomblord:BAABLgAECn8mAAMhAAkJ9hliAQBwAgAhAAkJ9hliAQBwAgASAAMJGAqMQABLAAAAAA==.Toogga:BAAALgAECgQJBAAAAA==.',
Tr='Trapattack:BAAALgADCgEJAQAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECgMJBAAGAAAAAA==.Truepatriot:BAACLgAFFH8IAAIDAAMJbxkgFwDuAAADAAMJbxkgFwDuAAAuAAQKfyYAAwMACAmpExQyALcBAAMACAmpExQyALcBABgABQnpEgoXAOIAAAAA.Truexlord:BAABLgAECn8WAAIRAAcJegxoTwBOAQARAAcJegxoTwBOAQAAAA==.Truthes:BAAALgAECgcJCQABLgAECggJJAAVABogAA==.Truthez:BAAALgADCgMJBgABLgAECggJJAAVABogAA==.Truths:BAAALgAECgIJAgABLgAECggJJAAVABogAA==.Truthsx:BAABLgAECn8kAAMVAAgJGiAEAQB7AgAVAAgJph8EAQB7AgAPAAUJchp+QwBeAQAAAA==.Truthz:BAAALgADCgYJBgABLgAECggJJAAVABogAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgMJAwAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAECgYJCAAAAA==.Tyraell:BAABLgAECn8sAAMDAAkJkR1ABADyAgADAAkJkR1ABADyAgAEAAQJnwdH7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAABLgAECn8aAAISAAgJEyFdBQDrAgASAAgJEyFdBQDrAgABLgAFFAUJFgATANshAA==.',
Ud='Udor:BAAALgAECgYJEAAAAA==.',
Um='Umbrae:BAABLgAECn8pAAIFAAgJzBoJCwA2AgAFAAgJzBoJCwA2AgAAAA==.',
Up='Upies:BAAALgAECgcJDAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAAALgAECgQJCQAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBgAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAABLgAECn8XAAIPAAgJExgMNwCJAQAPAAgJExgMNwCJAQAAAA==.',
Ve='Veera:BAABLgAECn8lAAIdAAkJSBBQEwC9AQAdAAkJSBBQEwC9AQAAAA==.Vendyr:BAABLgAECn8ZAAQVAAgJoyHxBwDOAQAPAAcJQx4uLQBZAgAVAAYJYhjxBwDOAQAOAAIJ8AsTYABPAAAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voodruid:BAAALgADCggJCQAAAA==.Vorgol:BAABLgAECn8hAAIXAAkJChhJBABGAgAXAAkJChhJBABGAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAIEAAcJ0hVKUQBTAQAEAAcJ0hVKUQBTAQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8MAAIEAAQJlA3mHAA6AQAEAAQJlA3mHAA6AQAuAAQKfxwAAgQACAmzHacjAJoCAAQACAmzHacjAJoCAAAA.',
We='Westerin:BAABLgAECn8eAAIOAAgJfRncAwDcAQAOAAgJfRncAwDcAQAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgcJBwAAAA==.Wimateeka:BAABLgAECn8dAAQYAAcJzh27CQCpAQAYAAcJzh27CQCpAQADAAUJxRIIYQD4AAAEAAQJlw2T3QDRAAAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgcJHQAYAM4dAA==.Windfury:BAAALgAECgYJDgABLgAECggJKwAiAJMlAA==.Windigo:BAAALgAECgYJDwAAAA==.Winginit:BAAALgAECgcJDQABLgAFFAUJEwAZABEYAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECggJLAAEAIEVAA==.',
Ye='Yespaladin:BAAALgAECgYJBwABLgAFFAQJDQAUAKMlAA==.',
Yi='Yiddosh:BAAALgAECgMJCQAAAA==.',
Yo='Yogí:BAACLgAFFH8PAAIeAAUJKR1QBQDBAQAeAAUJKR1QBQDBAQAuAAQKfxcAAx4ACAk6I94FABQDAB4ACAk6I94FABQDACMAAQk+A98uACoAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgQJBAAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8FAAMbAAMJdBscDQAJAQAbAAMJdBscDQAJAQAQAAIJGQf7HwB3AAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAAALgAECgYJEwAAAA==.Zanalia:BAAALgAECgMJBAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeffie:BAAALgAECgQJBgAAAA==.Zelxari:BAABLgAECn8WAAIPAAcJNwq8TgA+AQAPAAcJNwq8TgA+AQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8cAAITAAgJXiByEwA1AgATAAgJXiByEwA1AgAAAA==.Zithen:BAABLgAECn8XAAILAAkJnxfNHwBCAQALAAkJnxfNHwBCAQAAAA==.Zivver:BAABLgAECn8oAAIWAAgJnyKZAgC3AgAWAAgJnyKZAgC3AgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECgMJBAAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIDAAgJUR+qCQB3AgADAAgJUR+qCQB3AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAAALgAECgUJBwAAAA==.',
['Üt']='Üther:BAABLgAECn8kAAMEAAkJDSCjDgCJAgAEAAkJDSCjDgCJAgAYAAEJsRb9LQBCAAAAAA==.',
['ßu']='ßubbleøseven:BAAALgAFFAEJAQAAAA==.',
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

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

local lookup = {'Warrior-Fury','Warrior-Arms','Unknown-Unknown','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Windwalker','Evoker-Augmentation','Warrior-Protection','Evoker-Devastation','Priest-Discipline','Evoker-Preservation','Mage-Frost','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','Shaman-Elemental','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Priest-Shadow','Monk-Mistweaver','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Actionfigure:BAABLgAECn8XAAMBAAYJjh73LgD1AQABAAYJjh73LgD1AQACAAEJ7AYqRwAoAAAAAA==.',
Ad='Adgavery:BAAALgAECgYJCgAAAA==.Adielia:BAAALgAECgYJCgAAAA==.',
Ae='Aeskir:BAAALgAECgcJAQAAAA==.',
Ak='Aksa:BAAALgAECgkJAgAAAA==.',
Al='Alantharia:BAAALgADCgMJAwABLgAECgUJCQADAAAAAA==.Alarii:BAAALgADCgcJBwAAAA==.Alexious:BAABLgAECn8kAAIEAAgJViJBAwDsAgAEAAgJViJBAwDsAgAAAA==.Alkapwnn:BAAALgAECgUJDAAAAA==.Aloefox:BAAALgADCgkJIAAAAA==.Alofyxe:BAABLgAECn8UAAIFAAcJ1Bd9DgCQAQAFAAcJ1Bd9DgCQAQAAAA==.Altagravee:BAAALgADCgQJBAAAAA==.Altffour:BAABLgAFFH8LAAIGAAMJRwP3CQC8AAAGAAMJRwP3CQC8AAAAAA==.Alulla:BAACLgAFFH8HAAIBAAMJQBZNBQAMAQABAAMJQBZNBQAMAQAuAAQKfxkAAgEABwlKIdQWAJYCAAEABwlKIdQWAJYCAAAA.Alunira:BAABLgAECn8fAAMHAAgJdRxtEwB3AgAHAAgJdRxtEwB3AgAIAAIJVBMQQACPAAAAAA==.',
Am='Amberrfrost:BAAALgAECgQJBAAAAA==.Amex:BAAALgAECgEJAQAAAA==.',
An='Andark:BAAALgAECgMJAwAAAA==.Angryhtr:BAAALgADCgYJCgAAAA==.',
Ap='Aphox:BAABLgAECn8WAAQJAAYJWRInCgB4AAAKAAQJEBA9wQDWAAAJAAMJLBMnCgB4AAALAAIJAxLsIABuAAAAAA==.Apokalypto:BAAALgAECgEJAQAAAA==.',
Ar='Arachnida:BAAALgADCgYJBgAAAA==.Arairi:BAAALgAECgQJBAABLgAECgYJEQADAAAAAA==.Aravera:BAAALgAECgMJAwAAAA==.Araxes:BAAALgAECgMJBwAAAA==.Arcanefox:BAAALgAECgQJCAAAAA==.Arcåedeå:BAAALgADCgEJAQAAAA==.Ardå:BAAALgAECgYJBgAAAA==.Arîse:BAAALgADCgUJCAAAAA==.',
As='Ashgold:BAAALgAECgEJAQAAAA==.Ashoggal:BAAALgADCgQJBgAAAA==.Ashyl:BAAALgAECgEJAQAAAA==.Aslunay:BAAALgAECgUJEQAAAA==.Assine:BAAALgADCgIJAgABLgAECgcJBgADAAAAAA==.Astanis:BAAALgAECgUJBQAAAA==.Asteriia:BAAALgAECgYJDgAAAA==.',
At='Athhena:BAAALgADCgQJBgAAAA==.Atomskdmn:BAAALgADCgEJAQAAAA==.',
Au='Augustino:BAAALgAECgIJAgAAAA==.',
Av='Avraelia:BAAALgAECgYJCwAAAA==.',
Aw='Awakemoon:BAAALgAECgYJEgAAAA==.',
Az='Azaria:BAAALgADCgkJDQAAAA==.Azenderv:BAAALgAECgYJDwAAAA==.Azka:BAABLgAECn8fAAIIAAgJFx9lGADWAgAIAAgJFx9lGADWAgAAAA==.Azkadk:BAAALgAECgMJAwAAAA==.Azkamage:BAAALgAECgYJCQAAAA==.Azshaloria:BAAALgAECgYJDgAAAA==.Azter:BAAALgADCgMJAwAAAA==.',
Ba='Babybilly:BAAALgAECgYJCQAAAA==.Baddieelf:BAAALgAECgMJBwAAAA==.Bakkasura:BAAALgAECgYJCQAAAA==.Balduran:BAAALgADCgMJAwAAAA==.Baludis:BAAALgAECgUJBQAAAA==.Bamff:BAAALgAECgYJEQAAAA==.Bast:BAABLgAECn8gAAIMAAgJiiCLAgDMAgAMAAgJiiCLAgDMAgAAAA==.Basthara:BAAALgAECgUJCAABLgAECggJIAAMAIogAA==.Batracio:BAABLgAECn8WAAINAAYJPhAoIAAKAQANAAYJPhAoIAAKAQAAAA==.Batshiz:BAAALgADCgUJBQAAAA==.',
Be='Belindah:BAAALgADCgcJDAABLgAECgcJDgADAAAAAA==.Benif:BAACLgAFFH8FAAIBAAIJ5xfVCAC2AAABAAIJ5xfVCAC2AAAuAAQKfyQAAgEACAkNJMEBAF8CAAEACAkNJMEBAF8CAAAA.Bertodruid:BAAALgADCgYJBgAAAA==.Bertorod:BAAALgAECgQJDAAAAA==.',
Bh='Bhaall:BAAALgAECgYJEgAAAA==.',
Bi='Bigbitehotdo:BAAALgAECgEJAQAAAA==.Bigboppa:BAAALgADCgEJAQAAAA==.Bigknife:BAAALgAECgQJCwAAAA==.Bigtommybuns:BAAALgAECgEJAQAAAA==.Binkyfiasco:BAABLgAECn8dAAMGAAcJOCKgAwD5AQAGAAcJOCKgAwD5AQAOAAEJphh5eQA3AAAAAA==.',
Bl='Blaqlight:BAAALgADCgEJAQAAAA==.Blockybird:BAAALgAECgIJAgAAAA==.Bloodstoned:BAAALgADCgcJDwAAAA==.Bloodtank:BAAALgAECgYJEgAAAA==.',
Bm='Bmanblastmas:BAAALgAECgEJAQAAAA==.',
Bo='Bobquat:BAAALgADCgIJAgAAAA==.Bolcy:BAAALgAFFAIJAwAAAA==.Boogat:BAAALgAECgYJBgAAAA==.Boonkgang:BAAALgADCgEJAQAAAA==.Bowjangles:BAAALgADCgUJBQAAAA==.',
Br='Brahd:BAAALgADCgcJBwAAAA==.Brauck:BAABLgAECn8lAAMJAAgJryBIGACIAQAKAAUJ0iHKUgDPAQAJAAUJNx9IGACIAQABLgAFFAUJCgAPAMUUAA==.Brittarcher:BAAALgAECgYJBgAAAA==.Brixlo:BAAALgAECgMJAwAAAA==.',
Bu='Bubblegum:BAAALgADCgMJAQAAAA==.Bugslyfe:BAAALgADCggJCAAAAA==.Bullcat:BAAALgADCgEJAQAAAA==.Bunbohue:BAABLgAECn8YAAINAAcJUxWKWQCVAQANAAcJUxWKWQCVAQAAAA==.Burp:BAACLgAFFH8PAAQKAAUJAx08GwAaAQAKAAMJvRo8GwAaAQAJAAIJDxjqCgCyAAALAAEJAAAZBQBYAAAuAAQKfyQABAkACAlPJOcUAKMBAAoABglZJJQ0ADoCAAkABAmCJOcUAKMBAAsAAwnqJI0OAEgBAAAA.Burped:BAAALgAECgQJCAAAAA==.',
['Bü']='Büllseye:BAAALgAECgEJAQAAAA==.',
Ca='Cambrier:BAABLgAECn8fAAIBAAgJEBvBFACnAgABAAgJEBvBFACnAgAAAA==.Cardinal:BAAALgAECgcJAQAAAA==.Carynden:BAAALgAECgYJBgAAAA==.Cazbirkzul:BAAALgADCgEJAQAAAA==.',
Ce='Celeniel:BAAALgAECgYJBgAAAA==.Celorne:BAAALgADCgEJAQAAAA==.Cerostus:BAAALgAECgUJBQAAAA==.',
Ch='Chaladaug:BAAALgAECgIJAQAAAA==.Chaladk:BAAALgAECgcJBgAAAA==.Charcharwar:BAABLgAECn8eAAICAAcJthEKEACcAQACAAcJthEKEACcAQAAAA==.Charknight:BAAALgADCgEJAQAAAA==.Charmaldin:BAAALgADCgMJAwAAAA==.Chatdodu:BAAALgAECgUJDwAAAA==.Chatnoir:BAAALgADCgUJBQAAAA==.Chulu:BAAALgADCgcJCwAAAA==.Chunklleria:BAAALgAECgEJAQABLgAECgcJHAABALsdAA==.Chunks:BAABLgAECn8cAAQBAAcJux0gJQAvAgABAAcJih0gJQAvAgAQAAcJ3RigEQDtAQACAAYJYw9VBQA5AQAAAA==.Chunkvourer:BAAALgADCgUJAwABLgAECgcJHAABALsdAA==.',
Ci='Cinci:BAAALgADCgkJCgAAAA==.Cinderazer:BAAALgAECgEJAQAAAA==.Cipherdam:BAAALgAECgIJAgAAAA==.',
Co='Colesiaw:BAAALgADCgUJBQAAAA==.Cormier:BAAALgAECgQJCgAAAA==.Covidvax:BAAALgADCgEJAQAAAA==.',
Cr='Cronnie:BAAALgADCgkJFAAAAA==.Cryodormu:BAAALgAECgYJCgAAAA==.',
Ct='Ctrlaltd:BAAALgAECgEJAQAAAA==.',
Cu='Cubo:BAAALgADCgEJAQAAAA==.',
Cw='Cwarr:BAAALgAECgYJCgABLgAFFAMJBQARAKIHAA==.',
Da='Dabast:BAAALgADCgUJBgABLgAECggJIAAMAIogAA==.Daddyluis:BAAALgAECgQJBwAAAA==.Daddywarbuck:BAAALgADCgYJBwAAAA==.Danat:BAAALgAECgEJAQAAAA==.Dandanh:BAAALgADCgcJCAAAAA==.Dankbo:BAABLgAECn8eAAISAAgJliJ5BQD4AgASAAgJliJ5BQD4AgAAAA==.Dankbro:BAAALgADCgUJBQAAAA==.Darkivie:BAAALgAECgYJBwABLgAECggJGwAPAFMEAA==.Darthmama:BAAALgADCgIJAgAAAA==.',
Dc='Dcbuster:BAABLgAECn8eAAIBAAcJhhZCMQDoAQABAAcJhhZCMQDoAQAAAA==.',
De='Deathshrimp:BAAALgADCgcJCwAAAA==.Demonhusk:BAAALgAECgYJDAAAAA==.Demoni:BAAALgADCgcJBwAAAA==.Demonicsword:BAAALgAECgEJAwAAAA==.Demonz:BAAALgADCgcJCgAAAA==.Devildj:BAAALgADCgEJAQAAAA==.',
Dh='Dhampyra:BAAALgAFFAEJAQAAAA==.',
Di='Dianasia:BAAALgADCgYJCwAAAA==.Dietdrkelps:BAAALgAECgQJBAAAAA==.Dietmountdew:BAAALgAECgUJCQAAAA==.Dimitrios:BAAALgADCgkJCQAAAA==.Dingadinga:BAAALgAECgYJDQAAAA==.Dirtlicker:BAAALgADCgIJAgAAAA==.Disconnect:BAAALgAECgQJBQAAAA==.Dixxonciderr:BAACLgAFFH8FAAITAAIJchRXBwCgAAATAAIJchRXBwCgAAAuAAQKfygABBMACQlIDtsFAEEBABMACQlIDtsFAEEBABEABAlXC1ksALkAAA8ABAmOBS8XAJIAAAAA.',
Dk='Dkjaypim:BAAALgADCgkJCwAAAA==.',
Dm='Dmoe:BAAALgAECgQJCgAAAA==.',
Do='Dorkdark:BAAALgAECgMJAwAAAA==.',
Dr='Dragonflyer:BAAALgAECgQJBQAAAA==.Drioksis:BAAALgAECgMJBQAAAA==.Drshaboinkyy:BAACLgAFFH8LAAINAAUJYhJhCQCUAQANAAUJYhJhCQCUAQAuAAQKfxgAAw0ACAmYIv8tAEUCAA0ACAmYIv8tAEUCAAwABwlEA8YqADYAAAAA.Drshbuinky:BAAALgAECgYJBwAAAA==.Druyalulz:BAAALgAECgUJBwAAAA==.',
Du='Duckboy:BAAALgADCgUJBwAAAA==.Dumag:BAABLgAECn8bAAIGAAcJYCLAAgAhAgAGAAcJYCLAAgAhAgAAAA==.Duplicate:BAACLgAFFH8IAAIUAAMJSAbMMADvAAAUAAMJSAbMMADvAAAuAAQKfy4AAhQACQmxGoQlANwCABQACQmxGoQlANwCAAAA.Dustdruid:BAAALgAFFAMJBAAAAA==.Dustlock:BAAALgAECgQJBAAAAA==.',
Dy='Dyorah:BAAALgADCgYJBgAAAA==.',
Ee='Eender:BAAALgADCgUJBQAAAA==.',
El='Elif:BAAALgADCgEJAQAAAA==.Eliotyy:BAAALgADCgYJCgAAAA==.Ellcrys:BAABLgAECn8eAAIVAAgJWQ+HRQCLAQAVAAgJWQ+HRQCLAQAAAA==.Elletta:BAAALgADCgIJAgAAAA==.Ellssa:BAAALgAECgQJCAAAAA==.Elmamonster:BAAALgAECgQJBwAAAA==.',
Em='Emerick:BAAALgADCgYJBQAAAA==.Emillie:BAAALgAECgYJEQAAAA==.',
Ep='Epora:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Er='Ersande:BAAALgADCggJCwAAAA==.',
Es='Estellia:BAAALgADCgUJBQAAAA==.Estheban:BAABLgAECn8eAAMTAAcJaSFmAQBPAgATAAcJaSFmAQBPAgAPAAEJAwfBaAAkAAAAAA==.',
Ex='Exodia:BAAALgADCgYJBgAAAA==.',
Fa='Face:BAAALgAECgUJCQAAAA==.Faelila:BAAALgADCgYJBgAAAA==.Fairgrim:BAAALgAECgMJAwAAAA==.Falin:BAABLgAECn8+AAIIAAgJDRm7KgB5AgAIAAgJDRm7KgB5AgAAAA==.Falthras:BAAALgAECgEJAgAAAA==.Fanethben:BAAALgAECgQJCAAAAA==.Faqueuedark:BAACLgAFFH8FAAIKAAMJUA/BMgCtAAAKAAMJUA/BMgCtAAAuAAQKfx0ABAoABwnDIVIrAGICAAoABwkgIVIrAGICAAsAAgkXIQMYALsAAAkAAQkAADVuADkAAAAA.Faqueueeight:BAAALgAECgUJCQABLgAFFAMJBQAKAFAPAA==.Faqueuetoo:BAAALgAECgEJAQABLgAFFAMJBQAKAFAPAA==.Fatsloth:BAAALgADCgcJEAAAAA==.',
Fe='Feironos:BAAALgAECgMJCQAAAA==.Felray:BAAALgADCgMJBgAAAA==.Ferairi:BAAALgAECgQJCgABLgAECgYJEQADAAAAAA==.Fereir:BAAALgADCgQJBAAAAA==.Ferndavia:BAAALgAECgQJBAAAAA==.',
Fi='Fiist:BAAALgADCgYJDgAAAA==.Filigree:BAAALgADCgYJBgAAAA==.Fimtastic:BAAALgAECgYJDwAAAA==.Finasy:BAABLgAECn8aAAMWAAgJsBsMAwDLAQAWAAgJsBsMAwDLAQAXAAEJ4g9AFwAzAAAAAA==.Finnicka:BAAALgADCgcJDQAAAA==.Fireouch:BAAALgADCgQJBgAAAA==.Fistymisty:BAAALgAECggJDAAAAA==.',
Fl='Flaynpray:BAAALgAECgcJAgAAAA==.Flopsie:BAAALgAECggJCAAAAA==.',
Fo='Fonzsupreme:BAABLgAECn8WAAIUAAYJnCKwVwAyAgAUAAYJnCKwVwAyAgABLgAFFAMJBgAQAOMaAA==.Foxkit:BAAALgAECgEJAQAAAA==.',
Fr='Fredox:BAAALgADCgcJBwAAAA==.Freemilk:BAAALgADCgEJAQAAAA==.Frostbight:BAAALgADCgUJBQAAAA==.Frostyflake:BAAALgADCgUJBQAAAA==.',
Fu='Furearia:BAAALgAECgMJAwAAAA==.Furrybowner:BAAALgAECgUJDQAAAA==.',
['Fó']='Fóx:BAAALgAECgYJBwAAAA==.',
Ga='Gaelai:BAAALgAECgIJAwAAAA==.Galeriel:BAABLgAECn8eAAIYAAgJdxicEgBLAgAYAAgJdxicEgBLAgAAAA==.Gallethline:BAAALgADCgYJEgAAAA==.Garault:BAAALgAECgMJAwAAAA==.',
Ge='Gekoni:BAAALgAECggJEgAAAA==.Geonon:BAAALgAECgYJEAAAAA==.Georgemoyd:BAAALgADCgkJCwAAAA==.',
Gi='Girthybeam:BAAALgADCgcJDQAAAA==.',
Gl='Glandrien:BAAALgAECgMJAwAAAA==.Glowpwr:BAAALgADCgMJAwAAAA==.',
Go='Gobblerella:BAAALgADCgMJAwAAAA==.Gothmog:BAAALgADCgMJAwAAAA==.',
Gr='Graytonson:BAAALgAECgEJAQAAAA==.Greenhills:BAAALgADCgIJAgAAAA==.Greenlocks:BAAALgADCgIJAgABLgAFFAEJAQADAAAAAA==.Greenrånger:BAAALgAECgQJCwAAAA==.Greybush:BAAALgAECgMJBgAAAA==.Griffithw:BAAALgADCgYJCwAAAA==.Grombrindil:BAAALgAECgEJAQABLgAECgYJEAADAAAAAA==.Grullander:BAABLgAECn8UAAIZAAYJUxFnEgAkAQAZAAYJUxFnEgAkAQAAAA==.Grullandur:BAAALgADCgMJAwABLgAECgYJFAAZAFMRAA==.',
Gu='Guiguiie:BAAALgADCgcJBwAAAA==.',
['Gó']='Gólden:BAAALgADCgYJBgAAAA==.',
Ha='Hahacx:BAACLgAFFH8FAAINAAUJXAtxCAAsAQANAAUJXAtxCAAsAQAuAAQKfxkAAg0ACAmdIVUSAO0CAA0ACAmdIVUSAO0CAAAA.Halazzì:BAAALgAECgMJAwAAAA==.Haleon:BAAALgAECgIJAgAAAA==.Haraharotou:BAAALgAECgMJBgAAAA==.Hardyhar:BAAALgADCgMJBAAAAA==.',
He='Hebrews:BAAALgADCgYJBgAAAA==.Herkharu:BAAALgAECgYJDQAAAA==.Hermionee:BAAALgAECgQJBwAAAA==.',
Hi='Himjongun:BAABLgAECn8bAAMaAAYJzQ+uLABkAQAaAAYJPQ+uLABkAQANAAYJdQjUJADtAAAAAA==.',
Ho='Hobbitdemon:BAAALgAECgQJBAAAAA==.Hobbitdruid:BAAALgAECgcJEgAAAA==.Hobbitvoid:BAAALgADCgcJCwAAAA==.Holydagoon:BAAALgADCgYJBgABLgAFFAUJCgAPAMUUAA==.Hoppingmuff:BAAALgADCgcJBwAAAA==.',
Hu='Hunia:BAAALgAECgQJCAAAAA==.Huntieluis:BAAALgAECgQJBAAAAA==.Hurndredd:BAAALgAECgIJAwAAAA==.Huuh:BAAALgADCgMJBgAAAA==.',
Hy='Hystericc:BAAALgADCgIJAgAAAA==.',
['Hé']='Héboric:BAAALgAECgIJAgAAAA==.',
Id='Idolon:BAAALgADCgcJDgAAAA==.',
Ik='Ikashi:BAAALgADCgEJAQAAAA==.Ikodiwa:BAAALgAECgYJBgAAAA==.',
Il='Ilrion:BAAALgAECgYJDAAAAA==.',
In='Inferno:BAAALgAECgEJAwAAAA==.',
Is='Iseehot:BAABLgAECn8VAAIUAAYJ0BtQHABqAQAUAAYJ0BtQHABqAQAAAA==.',
Iv='Ivantis:BAAALgADCgkJHwAAAA==.Ivie:BAAALgAECgcJDgAAAA==.Ivieenfuego:BAABLgAECn8bAAIPAAgJUwTROQALAQAPAAgJUwTROQALAQAAAA==.',
Ja='Jackjackk:BAAALgADCgQJBAAAAA==.Jadednurse:BAAALgAECgYJCwAAAA==.Jakisormjr:BAAALgADCgIJAgAAAA==.Jalanii:BAAALgAECgQJCQAAAA==.Janjor:BAABLgAECn8fAAIbAAgJ+xxOGgBBAgAbAAgJ+xxOGgBBAgAAAA==.Janjorski:BAAALgADCgQJBAAAAA==.Jant:BAAALgAECgcJBwAAAA==.Jayrior:BAAALgADCgcJCwAAAA==.',
Je='Jehlock:BAAALgAECgUJCgAAAA==.Jehvoker:BAAALgAECgMJAwABLgAECgUJCgADAAAAAA==.Jerghal:BAAALgAECgYJBgAAAA==.Jettian:BAAALgAECgQJBQAAAA==.',
Ji='Jinu:BAAALgADCgIJAgAAAA==.',
Jj='Jjdruid:BAAALgAECgEJAQAAAA==.',
Jo='Jockwork:BAAALgAECgQJCwAAAA==.Jolene:BAABLgAECn8ZAAIcAAcJbAogDwACAQAcAAcJbAogDwACAQAAAA==.Jollygreene:BAAALgAECgQJCAAAAA==.Joyina:BAAALgADCgkJIgAAAA==.',
Ju='Justicee:BAAALgAECgQJCAABLgAECggJDAADAAAAAA==.',
Jx='Jxy:BAAALgAECgUJCQABLgAFFAUJDgANADwhAA==.',
Ka='Kahri:BAAALgAECgUJCQAAAA==.Kakali:BAAALgADCgEJAQAAAA==.Kalend:BAAALgAECgMJAwAAAA==.Karlager:BAAALgAECgYJEAAAAA==.Karlain:BAAALgAECgUJBgAAAA==.Kasaide:BAAALgADCgcJBwABLgAECgcJGQAKANINAA==.Kasmir:BAABLgAECn8ZAAIKAAcJ0g2EGgBBAQAKAAcJ0g2EGgBBAQAAAA==.Katia:BAAALgADCgUJBwAAAA==.',
Ke='Kelisii:BAAALgAECgcJCgAAAA==.Keloenivas:BAAALgADCggJEQAAAA==.Kelomage:BAAALgAECgEJAQAAAA==.Ketaza:BAAALgAECgEJAQAAAA==.Keyash:BAAALgADCgIJAgAAAA==.',
Kh='Khyle:BAAALgADCgEJAQABLgADCgcJEAADAAAAAA==.',
Ki='Kibblebits:BAABLgAECn8UAAIcAAYJSgPXVwDEAAAcAAYJSgPXVwDEAAAAAA==.Kijanajr:BAAALgADCggJDAAAAA==.Kitheros:BAAALgADCgcJBwAAAA==.Kittun:BAAALgADCgEJAQAAAA==.',
Kl='Klay:BAABLgAECn8VAAQQAAYJbCPpCgBiAgAQAAYJbCPpCgBiAgACAAIJpQpbNABgAAABAAIJtQJwngBGAAAAAA==.Klutch:BAAALgADCgIJAgAAAA==.',
Km='Kmarti:BAEBLgAECn8dAAMNAAgJfx9dIQCJAgANAAgJfx9dIQCJAgAaAAIJ/wv7XwBiAAAAAA==.',
Ko='Koivath:BAAALgADCgkJEQAAAA==.Konradevoker:BAAALgAFFAEJAgABLgAECgkJKwAKAFQeAA==.Konradlock:BAABLgAECn8rAAMKAAkJVB6WBgBVAwAKAAkJVB6WBgBVAwAJAAIJVxkrTQCGAAAAAA==.Konradrogue:BAABLgAECn8xAAMdAAkJuh6sAABiAwAdAAkJox6sAABiAwAeAAcJYxrZHQAPAgABLgAECgkJKwAKAFQeAA==.Konradwar:BAABLgAECn8XAAMCAAYJNx76EgB0AQACAAYJZhj6EgB0AQABAAQJpRaxbgD8AAABLgAECgkJKwAKAFQeAA==.Kosmicknight:BAAALgAECgcJEwAAAA==.',
Kr='Krathös:BAAALgADCgcJCQAAAA==.Krethrah:BAACLgAFFH8QAAIfAAYJBRo2BQCuAQAfAAYJBRo2BQCuAQAuAAQKfxcAAh8ACAktI3cUAAADAB8ACAktI3cUAAADAAAA.',
Ku='Kunfoopizza:BAAALgAECgQJCQAAAA==.Kuulibah:BAAALgADCgEJAQABLgADCgMJAwADAAAAAA==.Kuulibarr:BAAALgADCgMJAwAAAA==.',
Kw='Kwarr:BAAALgAFFAMJBAABLgAFFAMJBQARAKIHAA==.',
Ky='Kynaragon:BAABLgAECn8lAAMcAAcJfSaOGABEAgAcAAYJZSaOGABEAgAVAAQJ0CQdSQB+AQABLgAECgkJLQAVALYmAA==.Kyrimmon:BAAALgAECgEJAQAAAA==.',
La='Lallypop:BAAALgAECgQJBgAAAA==.Lammoth:BAAALgADCgcJCgAAAA==.Lanthein:BAAALgAECgEJAQABLgAFFAUJCgAPAMUUAA==.Laraela:BAAALgADCgEJAQAAAA==.Layil:BAAALgADCgYJBwAAAA==.',
Le='Leafu:BAAALgAECgQJBAABLgAECgcJFAAgADgbAA==.Leasin:BAABLgAECn8UAAIgAAcJOBusFQA8AgAgAAcJOBusFQA8AgAAAA==.Leathle:BAAALgADCgkJCQAAAA==.Leepa:BAAALgAECgcJDAAAAA==.Lepp:BAAALgAECgEJAQAAAA==.Lexslaner:BAAALgADCgYJCQAAAA==.',
Li='Lighthusk:BAAALgAECggJDQAAAA==.Liliauna:BAAALgAECgcJEAAAAA==.Lilibejeane:BAAALgAECgEJAQABLgAECgUJBwADAAAAAA==.Lilithalen:BAABLgAECn8jAAIYAAgJLRfkFQAtAgAYAAgJLRfkFQAtAgAAAA==.Lilmymy:BAAALgADCgcJBwAAAA==.Lilshimer:BAABLgAECn8WAAMKAAYJURWXVgDEAQAKAAYJURWXVgDEAQALAAIJdQMnIQBtAAAAAA==.Lilsquirtboy:BAACLgAFFH8FAAIfAAIJmB/5MgC9AAAfAAIJmB/5MgC9AAAuAAQKfyMAAx8ACAmGIcQBALICAB8ACAmGIcQBALICABYAAQmZCcBNABsAAAAA.',
Lo='Lockitt:BAABLgAECn8WAAIKAAkJBg0bXQCxAQAKAAkJBg0bXQCxAQAAAA==.Lostgrip:BAAALgADCgIJAgAAAA==.',
Lu='Lucthedk:BAAALgAECgQJCwAAAA==.Luk:BAAALgADCgYJBgAAAA==.Lukis:BAAALgADCgYJDAAAAA==.Lumario:BAAALgADCgEJAQAAAA==.Lunarpriest:BAAALgAECgEJAQAAAA==.Lunkbeck:BAAALgADCgUJBgAAAA==.',
Ly='Lyio:BAAALgAECgUJCgAAAA==.',
Ma='Madmandeath:BAAALgADCgQJAwAAAA==.Mahlanas:BAAALgAECgYJDgAAAA==.Maki:BAAALgAECgcJCQAAAA==.Malvean:BAAALgADCgcJCgAAAA==.Maravilla:BAAALgAECgYJDAAAAA==.Markuspapa:BAAALgAECgQJBAABLgAFFAMJCQASAFMaAA==.Marremer:BAAALgAECgUJDQAAAA==.',
Mc='Mckicky:BAAALgAECgYJDwAAAA==.',
Me='Mechafire:BAAALgADCgYJBgAAAA==.Melanius:BAAALgAECgYJEwAAAA==.Melodras:BAAALgAECgYJDgAAAA==.Memelord:BAAALgAECgQJCgAAAA==.Metalock:BAAALgADCgcJCwAAAA==.Mewalina:BAAALgADCgQJBAAAAA==.',
Mi='Mirajen:BAAALgADCgMJAwAAAA==.Mirukoo:BAAALgAECgQJBAAAAA==.Misconduct:BAAALgAECgQJCgAAAA==.Mistywaters:BAAALgAECgEJAgAAAA==.Mittyy:BAAALgADCgYJBwAAAA==.',
Mo='Mornintreant:BAAALgADCgMJAwAAAA==.Mousekewitzk:BAAALgADCgEJAQAAAA==.Movarth:BAAALgADCgkJCQAAAA==.',
Mu='Mungas:BAAALgADCgUJBgAAAA==.Murlloc:BAAALgADCgcJBgAAAA==.',
My='Myrathia:BAAALgAFFAEJAgAAAA==.Myrcella:BAAALgAECgQJBQAAAA==.',
Na='Nahemah:BAAALgAECgIJAwAAAA==.Nahtan:BAAALgAECgYJEgAAAA==.Nahwe:BAAALgADCgUJBQAAAA==.Narrsul:BAAALgAECgYJEgAAAA==.Nattyg:BAAALgAECgYJCgAAAA==.',
Ne='Nevermorte:BAAALgAECgYJBgAAAA==.',
Nf='Nfggolden:BAAALgAECgcJAgAAAA==.',
Ni='Nightforday:BAABLgAECn8WAAIfAAcJRhAAHwAmAQAfAAcJRhAAHwAmAQAAAA==.Niko:BAAALgAECgQJBQAAAA==.',
No='Noknani:BAAALgADCgUJBgAAAA==.Nokx:BAAALgAECgEJAQAAAA==.Nool:BAAALgADCgcJCQAAAA==.Norch:BAAALgADCgMJAwAAAA==.Nostranova:BAAALgAECgEJAQAAAA==.Novà:BAAALgADCgMJAwAAAA==.',
Oh='Ohkayboomer:BAAALgAECgYJCQAAAA==.',
Oo='Oontanx:BAAALgADCgcJCQAAAA==.Ooups:BAAALgAECgYJDgAAAA==.',
Op='Ophysia:BAAALgAECgYJCAAAAA==.',
Or='Orangecage:BAABLgAECn9jAAMcAAkJKCU/AAA+AwAcAAkJKCU/AAA+AwAVAAIJfwYcswBeAAAAAA==.Orkcansas:BAAALgAFFAEJAQAAAA==.',
Os='Osrsfemale:BAAALgAECgIJAgAAAA==.',
Ox='Oxazine:BAAALgAECgYJDQAAAA==.',
Pa='Paapineau:BAAALgAECgUJCQAAAA==.Palladias:BAAALgAECgQJBgAAAA==.Pally:BAAALgADCgIJAgAAAA==.',
Pc='Pcm:BAAALgAECgYJCQAAAA==.',
Pe='Peefmajeef:BAAALgADCgIJAgAAAA==.Peony:BAAALgADCgQJBAAAAA==.Pepperjack:BAAALgADCgYJDQAAAA==.Pewpeew:BAAALgAECgUJCgAAAA==.',
Ph='Phantomclone:BAAALgAECgUJDgAAAA==.Phantomwar:BAAALgAECgIJAgAAAA==.Phantomzz:BAAALgAECgEJAQAAAA==.Pheonixxwolf:BAAALgAECgYJDgAAAA==.Pherc:BAAALgADCgcJBwAAAA==.Phillyblunt:BAABLgAECn8aAAMZAAcJURNAMQDBAQAZAAcJURNAMQDBAQAbAAEJDQcPiwAtAAAAAA==.Phløw:BAAALgADCgMJBgAAAA==.',
Pl='Plaguekitten:BAAALgAECgEJAQAAAA==.Plowpatine:BAAALgAFFAEJAQAAAA==.',
Po='Poolius:BAAALgAECgQJDQAAAA==.Porfinne:BAAALgADCgQJBAAAAA==.',
Pr='Praedor:BAAALgADCgUJBQAAAA==.Preza:BAAALgADCgIJAgAAAA==.Priestymon:BAABLgAECn8bAAMSAAgJjxt9CgCRAgASAAgJjxt9CgCRAgAgAAIJtRCuGQBpAAABLgAFFAIJBQABAOcXAA==.Prober:BAAALgADCgUJBQAAAA==.Producer:BAAALgAECgEJAQAAAA==.Protato:BAAALgADCgYJBQAAAA==.Prowaifu:BAAALgAECgEJAQAAAA==.Prowess:BAAALgADCggJFAAAAA==.Prîestitute:BAAALgADCgYJCQAAAA==.',
Pu='Purger:BAAALgADCgYJCgAAAA==.Puyo:BAAALgAECgcJDgAAAA==.Puyyoo:BAAALgADCgMJAwABLgAECgcJDgADAAAAAA==.',
Pw='Pwarr:BAABLgAECn8aAAIQAAcJUh+6CgBlAgAQAAcJUh+6CgBlAgABLgAFFAMJBQARAKIHAA==.',
Py='Pyrofox:BAAALgADCgEJAQAAAA==.',
Qw='Qwarr:BAACLgAFFH8FAAMRAAMJogfaBgChAAARAAIJWQnaBgChAAAPAAIJ/QMtHQCHAAAuAAQKfyoAAw8ACQkJHyYBAIkCAA8ACQkJHyYBAIkCABEABglCHucPANwBAAAA.',
Ra='Rafoen:BAAALgAFFAIJAwAAAA==.Rakrur:BAAALgADCgEJAQAAAA==.Ramsay:BAAALgADCgYJDQAAAA==.Rathorn:BAAALgADCgYJDAAAAA==.Raxsan:BAAALgAFFAEJAQAAAA==.Raydanbalor:BAAALgAECgUJBQABLgAECgUJDQADAAAAAA==.Rayennagrom:BAAALgAECgUJBgAAAA==.Razkko:BAAALgADCgUJBQAAAA==.',
Rd='Rdru:BAAALgADCgcJBwABLgAECgYJCgADAAAAAA==.',
Re='Redpumpkin:BAAALgADCgMJAwAAAA==.Redsonja:BAAALgADCgcJDQAAAA==.Reneana:BAAALgADCggJDAAAAA==.Respectisluv:BAAALgAECgYJDQAAAA==.Rexcor:BAAALgAECgIJAwAAAA==.',
Rh='Rhulad:BAAALgADCggJCAAAAA==.',
Ri='Riaeline:BAAALgADCgcJCgAAAA==.Rinehardtt:BAAALgAECgUJCQABLgAECgYJCQADAAAAAA==.Ripheals:BAACLgAFFH8KAAIZAAQJhxHpBAAgAQAZAAQJhxHpBAAgAQAuAAQKfyIAAxkACAk8GtIdAC0CABkACAk8GtIdAC0CABsABAkoHgtBAEUBAAAA.Riplee:BAAALgADCgYJCwABLgAFFAQJCgAZAIcRAA==.Rivër:BAABLgAECn8VAAIIAAgJwRr+PwAmAgAIAAgJwRr+PwAmAgAAAA==.',
Ro='Robbell:BAAALgAECgcJEwAAAA==.Rogueflame:BAAALgAECgcJDQAAAA==.Rootsie:BAAALgAECgQJCAAAAA==.Roselynn:BAABLgAECn8iAAIVAAgJJx3iDwC5AgAVAAgJJx3iDwC5AgAAAA==.',
Rs='Rsolbes:BAAALgADCgUJBQAAAA==.',
Ru='Ruerl:BAAALgAECgcJEQAAAA==.Rumblies:BAAALgAECgQJDAAAAA==.Runetusk:BAAALgADCgEJAQABLgAECgUJBgADAAAAAA==.Rungin:BAAALgADCgEJAQAAAA==.Russopp:BAAALgADCgEJAQAAAA==.',
Sa='Saars:BAAALgADCgYJBgAAAA==.Samchan:BAAALgAECgEJBAAAAA==.Sanatharia:BAAALgAECgQJBgAAAA==.Saneatey:BAAALgAECgUJCwAAAA==.Sassibelle:BAAALgADCgkJCQAAAA==.Satanskidney:BAAALgADCgcJCAAAAA==.Sathenset:BAACLgAFFH8KAAIPAAUJxRQuAgB+AQAPAAUJxRQuAgB+AQAuAAQKfxQAAxEACAnLGEYRAMoBABEABwmsFkYRAMoBAA8AAwmrEitDANQAAAAA.',
Sc='Scandium:BAAALgAECgcJEgAAAA==.Scrembiblion:BAAALgAECgYJDgAAAA==.',
Sd='Sdhoscillate:BAAALgAECgQJBAAAAA==.',
Se='Seagulpunchr:BAAALgADCgYJCgAAAA==.Seesh:BAACLgAFFH8KAAIBAAQJLiDpBgB+AQABAAQJLiDpBgB+AQAuAAQKfxgAAgEACQnSJBYDAIADAAEACQnSJBYDAIADAAAA.Sentarr:BAABLgAFFH8GAAIQAAMJ4xonAwD+AAAQAAMJ4xonAwD+AAAAAA==.Septhera:BAAALgAFFAEJAgAAAA==.',
Sh='Shadeyheals:BAAALgAECgEJAQAAAA==.Shadowxcraft:BAAALgAECgUJBQAAAA==.Shadrelin:BAAALgADCgEJAgAAAA==.Shaqler:BAAALgAECgMJBAAAAA==.Shecks:BAAALgADCgcJCAAAAA==.Shelandria:BAAALgAECgEJAQAAAA==.Sherwild:BAABLgAECn8YAAIVAAgJxiH1CgDqAgAVAAgJxiH1CgDqAgAAAA==.Shinara:BAAALgAECgYJDgAAAA==.Shiverchill:BAAALgAECgcJAQAAAA==.Shnipishnap:BAABLgAECn8yAAMZAAkJHCPUAACgAwAZAAkJHCPUAACgAwAbAAQJvBqJQgA+AQAAAA==.Shnupel:BAAALgAECgkJBgAAAA==.Shroomjuicee:BAABLgAECn8VAAISAAcJdhWmGgDCAQASAAcJdhWmGgDCAQAAAA==.Shyi:BAAALgADCgYJBgAAAA==.',
Si='Sindaemon:BAABLgAECn8iAAINAAgJJiJdFADeAgANAAgJJiJdFADeAgAAAA==.Sindrina:BAAALgAECgIJAgAAAA==.',
Sk='Skelstone:BAAALgADCgYJBgAAAA==.Skädoosh:BAAALgAECgQJBwAAAA==.',
Sl='Slapshappy:BAAALgAECgcJDgAAAA==.Sloptop:BAAALgADCgcJBwAAAA==.Slowfall:BAAALgADCgcJCwAAAA==.',
Sm='Smokin:BAAALgAECgYJDwAAAA==.',
Sn='Snowjor:BAAALgADCgEJAQAAAA==.Snyx:BAAALgADCgUJBQAAAA==.',
So='Solaríus:BAAALgADCgMJAwAAAA==.Soldanas:BAAALgADCgEJAQAAAA==.Solomus:BAAALgADCgkJDAAAAA==.',
Sp='Spheaddin:BAAALgAECgEJAQAAAA==.Spiritbomb:BAAALgAECgYJCwAAAA==.Spytime:BAAALgAECgEJAQAAAA==.',
Ss='Ssjchezzy:BAAALgAECgcJDgAAAA==.Ssmeltn:BAAALgAECgYJDQAAAA==.',
St='Steinberg:BAAALgADCgEJAQAAAA==.Stnaprednu:BAAALgAFFAEJAQAAAA==.Stormroid:BAAALgAECgEJAgAAAA==.Stormxwolf:BAAALgAECgYJDQAAAA==.Strangulate:BAAALgAECgQJBQAAAA==.Stripez:BAAALgADCgUJBwAAAA==.Stumpvee:BAAALgADCgMJAwAAAA==.',
Su='Sunmx:BAAALgAECgcJBgAAAA==.Superdark:BAAALgADCgYJBwAAAA==.',
Sw='Swurves:BAAALgADCggJDwABLgAECgYJEQADAAAAAA==.',
Ta='Taedrum:BAAALgAECgEJAQAAAA==.Taerror:BAACLgAFFH8LAAIYAAMJ2yTSAQBIAQAYAAMJ2yTSAQBIAQAuAAQKfysAAxgACQmyI34AAK8DABgACQmyI34AAK8DABIAAgl5GEtFAI8AAAAA.Tahkon:BAAALgADCgEJAQAAAA==.Tahmtan:BAAALgADCgcJEAAAAA==.Talegos:BAAALgAECgQJBAAAAA==.Talonfel:BAAALgADCgcJCwABLgAECggJIQAhAAkiAA==.Talonflight:BAAALgAECgQJBAABLgAECggJIQAhAAkiAA==.Talonstryke:BAABLgAECn8hAAIhAAgJCSLnAADUAgAhAAgJCSLnAADUAgAAAA==.Tanarious:BAAALgADCgQJBAAAAA==.Taytonar:BAAALgAECgYJEwAAAA==.',
Te='Teamocil:BAAALgAECgEJAQAAAA==.Teefa:BAAALgAECgYJCwAAAA==.Tevers:BAAALgADCgcJDAAAAA==.',
Th='Thane:BAAALgADCgMJAwAAAA==.Thaumium:BAAALgADCgEJAQAAAA==.Theenforcer:BAAALgAECgQJBwAAAA==.Theguyfurry:BAAALgADCgcJCwAAAA==.Thidwick:BAAALgAECgIJAgAAAA==.Thingtwø:BAAALgAECgIJAgAAAA==.Thirdryker:BAAALgADCgIJAgAAAA==.Thorissa:BAABLgAECn8UAAIJAAgJsQ0QEwCzAQAJAAgJsQ0QEwCzAQAAAA==.Thäne:BAAALgAECgUJBgAAAA==.',
Ti='Tiles:BAAALgAECgEJAQAAAA==.Timojj:BAAALgAECgEJAgAAAA==.Tinglu:BAAALgADCgcJCQAAAA==.Tinkk:BAAALgAECgEJAQAAAA==.Titø:BAAALgAECgYJCwAAAA==.',
To='Tomorrow:BAABLgAECn8WAAIUAAcJCR//TgBKAgAUAAcJCR//TgBKAgAAAA==.Topdog:BAAALgADCgYJDgAAAA==.Topzee:BAAALgAECgQJBwAAAA==.Torquin:BAAALgADCgMJAwAAAA==.Tottytotems:BAAALgADCgcJDAAAAA==.Touchmablade:BAAALgADCgQJBAAAAA==.',
Tr='Traylo:BAAALgAECgYJDAAAAA==.',
Tu='Turkeymm:BAAALgADCgMJAwAAAA==.',
Tv='Tvak:BAABLgAECn8UAAIIAAYJgCHGQwAZAgAIAAYJgCHGQwAZAgAAAA==.',
Tw='Twopump:BAABLgAECn8UAAIIAAYJBAabLADtAAAIAAYJBAabLADtAAAAAA==.',
Ty='Tygrarelea:BAAALgAECgEJAQAAAA==.Tynan:BAAALgADCgMJBQAAAA==.',
Ul='Ulinova:BAAALgAECgQJBwAAAA==.',
Uu='Uu:BAAALgAFFAMJAwAAAA==.',
Va='Vainqueur:BAAALgAECgYJBwAAAA==.Valoroso:BAAALgAECgQJBAAAAA==.Vanarios:BAAALgAECgEJAQAAAA==.Vanderpal:BAAALgADCggJAQAAAA==.Vanec:BAAALgADCgMJAwAAAA==.Varm:BAAALgAECgEJAQAAAA==.Vasarian:BAAALgAECgEJAQAAAA==.',
Ve='Veidima:BAAALgAECgQJBgAAAA==.Veigar:BAAALgADCgYJBgAAAA==.Velion:BAAALgAECgIJAwAAAA==.Verzweifeln:BAAALgAECgEJAQAAAA==.Vesenya:BAAALgAECgEJAQAAAA==.Veyez:BAAALgADCgkJDAAAAA==.',
Vh='Vhyrix:BAAALgAECgQJBQAAAA==.',
Vi='Viantel:BAAALgAECgYJCgAAAA==.Viklicious:BAAALgADCgkJCQAAAA==.Vinarn:BAABLgAECn8ZAAMXAAYJEw7/CQAzAQAXAAYJAg3/CQAzAQAfAAYJXwa7KADtAAAAAA==.Vinyls:BAAALgADCgQJBAAAAA==.Viridius:BAAALgAECgEJAQAAAA==.Virindi:BAAALgAECgEJAQAAAA==.',
Vr='Vrogar:BAAALgAECgcJCQAAAA==.',
['Vä']='Väelün:BAABLgAECn8UAAINAAYJ6w8GdQBGAQANAAYJ6w8GdQBGAQABLgAECggJHgAiACcKAA==.',
Wa='Wachoosh:BAAALgADCggJGQAAAA==.Wackamoose:BAABLgAECn8UAAQCAAYJdBReBwACAQACAAYJQhNeBwACAQAQAAQJ7g5xMADBAAABAAIJmgdBlgBnAAAAAA==.Wagoogusmay:BAAALgAECgEJAQAAAA==.Waidmanns:BAABLgAECn8eAAIFAAgJOhryHQBSAgAFAAgJOhryHQBSAgAAAA==.Walvet:BAAALgAECgMJCAAAAA==.Warc:BAAALgADCgUJBQAAAA==.Wargramps:BAAALgADCgQJBAAAAA==.Warrioo:BAAALgADCgMJAwABLgAECgcJBgADAAAAAA==.',
We='Weelad:BAAALgADCgkJFAAAAA==.Weldord:BAABLgAECn8fAAIFAAYJWw25WwBVAQAFAAYJWw25WwBVAQAAAA==.',
Wh='Whatorne:BAAALgAECgQJBQAAAA==.Whiskeytaur:BAAALgADCgYJBgAAAA==.',
Wi='Wickedchick:BAAALgAECgMJBAAAAA==.Willowknight:BAAALgADCgMJAwAAAA==.',
Wo='Wolvareene:BAAALgADCgcJBwAAAA==.',
Wr='Wrongknight:BAAALgAECgQJBgAAAA==.Wrongname:BAAALgAECgUJDAAAAA==.',
Xe='Xeruu:BAAALgADCgUJBQAAAA==.',
Xo='Xolan:BAACLgAFFH8FAAIVAAIJKQ2lGwCOAAAVAAIJKQ2lGwCOAAAuAAQKfx0AAhUACAkQGs8kACYCABUACAkQGs8kACYCAAAA.',
Xp='Xprophet:BAAALgAECgQJCAAAAA==.',
Xw='Xw:BAAALgADCgYJCwAAAA==.',
Ye='Yesyesyes:BAAALgADCgIJAgAAAA==.',
Yo='Yogsothoth:BAEBLgAECn8cAAMFAAcJERDDEgBlAQAFAAcJ7w3DEgBlAQAjAAYJjBBdFgBjAQAAAA==.Yooloakala:BAAALgADCgUJBQAAAA==.Yormaum:BAAALgADCgYJBgAAAA==.Yosha:BAAALgADCgYJBgAAAA==.',
Za='Zaartyn:BAAALgAECgcJEQAAAA==.Zalupalkys:BAAALgAECgQJAwAAAA==.Zarexion:BAAALgADCggJDAAAAA==.',
Ze='Zeebeth:BAAALgAECgQJCQAAAA==.Zefi:BAAALgAECgIJAwAAAA==.Zerokai:BAAALgAECgEJAQAAAA==.',
Zh='Zhahira:BAAALgAECgEJAQAAAA==.',
Zi='Zipsy:BAABLgAECn8aAAIUAAcJEgsEIABVAQAUAAcJEgsEIABVAQAAAA==.',
Zo='Zomlo:BAAALgAECgEJAQAAAA==.',
Zu='Zumtobel:BAAALgADCgYJDgAAAA==.Zuuko:BAACLgAFFH8QAAIOAAMJNx9BAgAmAQAOAAMJNx9BAgAmAQAuAAQKfxYAAg4ACAkWIKEGABUDAA4ACAkWIKEGABUDAAAA.',
Zy='Zyreth:BAAALgADCgYJCAAAAA==.',
['Ár']='Árthur:BAAALgAECgIJAgAAAA==.',
['År']='Åres:BAAALgAECgIJAgAAAA==.',
['Îs']='Îsadora:BAAALgADCgYJCQAAAA==.',
['Ýe']='Ýe:BAAALgADCgYJBgAAAA==.',
['ßu']='ßuzzibee:BAAALgADCgkJGgABLgAECgQJCgADAAAAAA==.',
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

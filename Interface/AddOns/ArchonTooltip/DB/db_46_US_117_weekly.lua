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

local lookup = {'Warrior-Fury','Warrior-Arms','Unknown-Unknown','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Mage-Frost','DemonHunter-Vengeance','Druid-Restoration','DeathKnight-Unholy','Monk-Windwalker','Hunter-Marksmanship','Evoker-Augmentation','Warrior-Protection','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Monk-Mistweaver',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Actionfigure:BAABLgAECn8aAAMBAAYJjh75LgD1AQABAAYJjh75LgD1AQACAAEJ7AYvRwAoAAAAAA==.',
Ad='Adessa:BAAALgAECgQJBgAAAA==.Adgavery:BAAALgAECgcJEQAAAA==.Adielia:BAAALgAECgYJCwAAAA==.',
Ae='Aeskir:BAAALgAECgcJAQAAAA==.',
Ak='Aksa:BAAALgAECgkJBAAAAA==.',
Al='Alantharia:BAAALgADCgMJAwABLgAECgUJCQADAAAAAA==.Alexious:BAACLgAFFH8HAAIEAAMJYCGQAgD6AAAEAAMJYCGQAgD6AAAuAAQKfyQAAgQACAlWIkIDAOwCAAQACAlWIkIDAOwCAAAA.Alkapwnn:BAAALgAECgUJDAAAAA==.Aloefox:BAAALgADCgkJKQAAAA==.Alofyxe:BAABLgAECn8ZAAIFAAgJcBglKQBxAQAFAAgJcBglKQBxAQAAAA==.Altagravee:BAAALgADCgQJBAAAAA==.Altffour:BAABLgAFFH8NAAIGAAMJwAMKHQCzAAAGAAMJwAMKHQCzAAAAAA==.Alulla:BAACLgAFFH8MAAIBAAQJxRnyBQBkAQABAAQJxRnyBQBkAQAuAAQKfxsAAgEACAnHIM8WAJYCAAEACAnHIM8WAJYCAAAA.Alunira:BAABLgAECn8nAAMHAAgJYB1qEwB3AgAHAAgJYB1qEwB3AgAIAAQJcxs5QABJAQAAAA==.',
Am='Amberrfrost:BAAALgAECgUJCQAAAA==.Amberveil:BAAALgADCgUJBQAAAA==.Amex:BAAALgAECgEJAQAAAA==.',
An='Andark:BAAALgAECgMJAwAAAA==.Angryhtr:BAAALgAECgEJAQAAAA==.',
Ap='Aphox:BAABLgAECn8dAAQJAAcJkhJoLQB2AQAJAAcJkBFoLQB2AQAKAAMJLBOfFAB2AAALAAIJAxLrIABuAAAAAA==.Apokalypto:BAAALgAECgYJBwAAAA==.',
Ar='Arachnida:BAAALgADCgYJBgAAAA==.Arairi:BAAALgAECgQJBAABLgAECgYJEQADAAAAAA==.Aravera:BAAALgAECgMJAwAAAA==.Araxes:BAAALgAECgMJBwAAAA==.Arcanefox:BAAALgAECgUJCQAAAA==.Arcåedeå:BAAALgADCgYJBgAAAA==.Ardå:BAAALgAECgYJBwAAAA==.Arîse:BAAALgADCgUJCAAAAA==.',
As='Ashgold:BAAALgAECgEJAQAAAA==.Ashoggal:BAAALgADCgQJBgAAAA==.Ashyl:BAAALgAECgEJAQAAAA==.Aslunay:BAABLgAECn8dAAIIAAYJLQuqUgAWAQAIAAYJLQuqUgAWAQAAAA==.Assine:BAAALgADCgIJAgABLgAECgcJBgADAAAAAA==.Astanis:BAAALgAECgUJCgAAAA==.Asteriia:BAABLgAECn8WAAIMAAgJXwpTJwBLAQAMAAgJXwpTJwBLAQAAAA==.',
At='Athhena:BAAALgADCgQJBgAAAA==.Atomskdmn:BAAALgADCgEJAQAAAA==.',
Au='Augustino:BAAALgAECgIJAgAAAA==.',
Av='Avraelia:BAAALgAECgYJCwAAAA==.',
Aw='Awakemoon:BAAALgAECgYJEwAAAA==.',
Az='Azarazan:BAAALgADCgIJAgAAAA==.Azaria:BAAALgADCgkJDQAAAA==.Azenderv:BAAALgAECgcJEAAAAA==.Azka:BAABLgAECn8gAAIIAAgJFx9qGADWAgAIAAgJFx9qGADWAgAAAA==.Azkadk:BAAALgAECgMJAwAAAA==.Azkamage:BAAALgAECgYJCQAAAA==.Azshaloria:BAAALgAECgYJDgAAAA==.Azter:BAAALgADCgMJAwAAAA==.',
Ba='Babybilly:BAAALgAECgYJDwAAAA==.Baddieelf:BAAALgAECgYJDAAAAA==.Bakkasura:BAAALgAECgYJCQAAAA==.Balduran:BAAALgADCgMJAwAAAA==.Baludis:BAAALgAECgYJCgAAAA==.Bamff:BAABLgAECn8ZAAINAAgJQxm0HgD0AQANAAgJQxm0HgD0AQAAAA==.Bast:BAABLgAECn8gAAIOAAgJiiCLAgDMAgAOAAgJiiCLAgDMAgAAAA==.Bastbrew:BAAALgAECgUJBQABLgAECggJIAAOAIogAA==.Basthara:BAAALgAECgYJDQABLgAECggJIAAOAIogAA==.Batracio:BAABLgAECn8dAAIMAAcJbxRSIABxAQAMAAcJbxRSIABxAQAAAA==.Batshiz:BAAALgADCgUJBQAAAA==.',
Be='Beerox:BAAALgADCgIJAgAAAA==.Belindah:BAAALgADCgcJDAABLgAECggJGgAPAO0SAA==.Benif:BAACLgAFFH8JAAIBAAQJ0BWYBwBXAQABAAQJ0BWYBwBXAQAuAAQKfy8AAwEACQlyIyMCAMsCAAEACQlyIyMCAMsCAAIABAnlGYAMADsBAAAA.Bertodruid:BAAALgADCgYJBgAAAA==.Bertorod:BAAALgAECgYJDgAAAA==.',
Bh='Bhaall:BAABLgAECn8WAAIQAAYJ1QdnagDNAAAQAAYJ1QdnagDNAAAAAA==.',
Bi='Bigbitehotdo:BAAALgAECgUJBwAAAA==.Bigboppa:BAAALgADCgEJAQAAAA==.Bigknife:BAAALgAECgQJDwAAAA==.Bigtommybuns:BAAALgAECgEJAQAAAA==.Binkyfiasco:BAABLgAECn8jAAMGAAcJOCK9CAADAgAGAAcJOCK9CAADAgARAAEJphiCeQA3AAAAAA==.',
Bl='Blaqlight:BAAALgADCgEJAQAAAA==.Bloblop:BAAALgAECgkJBgAAAA==.Blockybird:BAAALgAECgIJAgAAAA==.Bloodstoned:BAAALgADCgcJDwAAAA==.Bloodtank:BAAALgAECgYJEgAAAA==.',
Bm='Bmanblastmas:BAAALgAECgEJAQAAAA==.',
Bo='Bobquat:BAAALgADCgIJAgAAAA==.Bolcy:BAACLgAFFH8GAAMFAAMJ6wwpHADzAAAFAAMJ6wwpHADzAAASAAEJyAFGLQA9AAAuAAQKfxgAAwUACAnRG7wNAC8CAAUABwmVH7wNAC8CABIABAm1EhdSAAQBAAAA.Boogat:BAAALgAECgcJCgAAAA==.Boonkgang:BAAALgADCgEJAQAAAA==.Bowjangles:BAAALgADCgUJBQAAAA==.',
Br='Brahd:BAAALgAECggJCAAAAA==.Brauck:BAACLgAFFH8GAAIJAAMJniBNIwATAQAJAAMJniBNIwATAQAuAAQKfyUAAwoACAmvIEYYAIgBAAkABQnSIc1SAM8BAAoABQk3H0YYAIgBAAEuAAUUBQkKABMAxRQA.Brittarcher:BAAALgAECgcJDAAAAA==.Brixlo:BAAALgAECgUJBwAAAA==.',
Bu='Bubblegum:BAAALgADCgMJAQAAAA==.Bugslyfe:BAAALgADCggJCAAAAA==.Bullcat:BAAALgADCgEJAQAAAA==.Bunbohue:BAABLgAECn8XAAIMAAcJtRONWQCVAQAMAAcJtRONWQCVAQAAAA==.Burp:BAACLgAFFH8VAAQJAAYJ6RjwEABZAQAJAAUJLhbwEABZAQAKAAIJDxjrCgCyAAALAAEJAAAYBQBYAAAuAAQKfyUABAoACAlPJOUUAKMBAAkABglZJJY0ADoCAAoABAmCJOUUAKMBAAsAAwnqJI4OAEgBAAAA.Burped:BAAALgAECgQJCAAAAA==.',
['Bü']='Büllseye:BAAALgAECgEJAQAAAA==.',
Ca='Cambrier:BAABLgAECn8nAAIBAAgJZR4aBQBsAgABAAgJZR4aBQBsAgAAAA==.Cardinal:BAAALgAECgcJBQAAAA==.Carynden:BAAALgAECgYJBgAAAA==.Cazbirkzul:BAAALgADCgEJAQAAAA==.',
Ce='Celeniel:BAAALgAECgYJBwAAAA==.Celorne:BAAALgADCgEJAQAAAA==.Cerostus:BAAALgAECgUJBQAAAA==.',
Ch='Chaladaug:BAAALgAECgIJAQAAAA==.Chaladk:BAAALgAECgcJBgAAAA==.Charcharwar:BAABLgAECn8jAAICAAcJthEQEACcAQACAAcJthEQEACcAQAAAA==.Charknight:BAAALgADCgcJCAAAAA==.Charmaldin:BAAALgADCgMJAwAAAA==.Chatdodu:BAAALgAECgUJEAAAAA==.Chatnoir:BAAALgAECgUJBQAAAA==.Chivap:BAAALgAECgkJBQAAAA==.Chulu:BAAALgADCgcJCwAAAA==.Chunklleria:BAAALgAECgMJAwABLgAECggJIwABAOobAA==.Chunks:BAABLgAECn8jAAQBAAgJ6hsKEAC7AQAUAAcJ3RigEQDtAQABAAcJhx4KEAC7AQACAAcJKhADCgBjAQAAAA==.Chunkvourer:BAAALgADCgUJAwABLgAECggJIwABAOobAA==.',
Ci='Cinci:BAAALgADCgkJCgAAAA==.Cinderazer:BAAALgAECgMJAQAAAA==.Cipherdam:BAAALgAECgIJAgAAAA==.',
Co='Colesiaw:BAAALgADCgUJBQAAAA==.Conduit:BAAALgAECgYJBgAAAA==.Cormier:BAAALgAECgQJCgAAAA==.Covidvax:BAAALgADCgEJAQAAAA==.',
Cr='Cronnie:BAAALgAECgMJAwAAAA==.Cryodormu:BAAALgAECgYJCgAAAA==.',
Ct='Ctrlaltd:BAAALgAECgEJAQAAAA==.',
Cu='Cubo:BAAALgADCgEJAQAAAA==.',
Cw='Cwarr:BAAALgAECgYJCgABLgAFFAQJBwAUAI4SAA==.',
Cy='Cyrcee:BAAALgADCggJCAABLgAECggJGgAPAO0SAA==.',
Da='Dabast:BAAALgAECgMJBAABLgAECggJIAAOAIogAA==.Daddyluis:BAAALgAECgQJBwAAAA==.Daddywarbuck:BAAALgAECgEJAQAAAA==.Danat:BAAALgAECgEJAQAAAA==.Dandanh:BAAALgADCgcJCAAAAA==.Dankbo:BAABLgAECn8uAAIVAAgJBiXeAABmAwAVAAgJBiXeAABmAwAAAA==.Dankbro:BAAALgADCgUJBQAAAA==.Darkivie:BAAALgAECgYJBwABLgAECggJIwATAMEEAA==.Darthmama:BAAALgADCgIJAgAAAA==.',
Dc='Dcbuster:BAABLgAECn8nAAIBAAgJaRfzDgDIAQABAAgJaRfzDgDIAQAAAA==.',
De='Deathshrimp:BAAALgADCgcJCwAAAA==.Delaylea:BAAALgAECgEJAQAAAA==.Demonhusk:BAAALgAECgYJDAAAAA==.Demoni:BAAALgADCgcJBwAAAA==.Demonicsword:BAAALgAECgEJBgAAAA==.Demonz:BAAALgADCgcJCgAAAA==.Denaheal:BAAALgADCgUJBQABLgAECgUJCQADAAAAAA==.Devildj:BAAALgADCgEJAQAAAA==.',
Dh='Dhampyra:BAABLgAECn8XAAIWAAgJJRyQBgAmAgAWAAgJJRyQBgAmAgAAAA==.',
Di='Dianasia:BAAALgADCgYJCwAAAA==.Dietdrkelps:BAAALgAECgQJBAAAAA==.Dietmountdew:BAAALgAECgUJCQAAAA==.Dimitrios:BAAALgAECgEJAgAAAA==.Dingadinga:BAAALgAECgYJEQAAAA==.Dirtlicker:BAAALgADCgIJAgAAAA==.Disconnect:BAAALgAECgUJCgAAAA==.Dixxonciderr:BAACLgAFFH8JAAIXAAMJ0RmTDAAJAQAXAAMJ0RmTDAAJAQAuAAQKfy4ABBcACQmCEXkJAIcBABcACQmCEXkJAIcBABgABAlXC10sALkAABMABAmOBao0AIgAAAAA.',
Dk='Dkjaypim:BAAALgAECgIJAgAAAA==.',
Dm='Dmoe:BAAALgAECgQJDgAAAA==.',
Do='Dorkdark:BAAALgAECgMJAwAAAA==.',
Dr='Dragonflyer:BAAALgAFFAEJAQAAAA==.Drioksis:BAAALgAECgQJCgAAAA==.Drshaboinkyy:BAACLgAFFH8LAAIMAAUJYhJiCQCUAQAMAAUJYhJiCQCUAQAuAAQKfxQAAwwACAmYIgIuAEUCAAwACAmYIgIuAEUCAA4ABwlEA8gqADYAAAAA.Drshbuinky:BAAALgAECgYJBwAAAA==.Druyalulz:BAAALgAECgUJCAAAAA==.',
Du='Duckboy:BAAALgADCgUJBwAAAA==.Dumag:BAABLgAECn8dAAIGAAcJYCIYBwAnAgAGAAcJYCIYBwAnAgAAAA==.Duplicate:BAACLgAFFH8KAAINAAMJSAbNMADvAAANAAMJSAbNMADvAAAuAAQKfzUAAg0ACQm9GnwVADACAA0ACQm9GnwVADACAAAA.Dustdruid:BAABLgAFFH8FAAIZAAMJAwyDDwDqAAAZAAMJAwyDDwDqAAAAAA==.Dustlock:BAAALgAECgQJBAAAAA==.',
Dy='Dyorah:BAAALgADCgYJBgAAAA==.',
Eb='Ebonsnoot:BAAALgADCgEJAQAAAA==.',
Ee='Eender:BAAALgADCgYJCAAAAA==.',
El='Elif:BAAALgADCgEJAQAAAA==.Eliotyy:BAAALgADCgYJCgAAAA==.Ellcrys:BAABLgAECn8eAAIPAAgJWQ+TRQCLAQAPAAgJWQ+TRQCLAQAAAA==.Elletta:BAAALgAECgEJAQAAAA==.Ellssa:BAAALgAECgUJCQAAAA==.Elmamonster:BAAALgAECgQJBwAAAA==.',
Em='Emerick:BAAALgADCgYJBQAAAA==.Emillie:BAAALgAECgYJEQAAAA==.',
Ep='Epora:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Er='Ersande:BAAALgADCggJCwAAAA==.',
Es='Estellia:BAAALgADCgUJBQAAAA==.Estheban:BAABLgAECn8fAAMXAAgJASDVAgB+AgAXAAgJASDVAgB+AgATAAEJAwfLaAAkAAAAAA==.',
Ex='Exodia:BAAALgAECgIJAgAAAA==.',
Fa='Face:BAAALgAECgYJDwAAAA==.Faelila:BAAALgADCgYJBgAAAA==.Fairgrim:BAAALgAECgMJAwAAAA==.Falin:BAABLgAECn9SAAIIAAgJphwGFQATAgAIAAgJphwGFQATAgAAAA==.Falthras:BAAALgAECgQJCAAAAA==.Fanethben:BAAALgAECgYJCgAAAA==.Faqueuedark:BAACLgAFFH8GAAIJAAMJUA8AMgDeAAAJAAMJUA8AMgDeAAAuAAQKfx4ABAkACAmVH1IrAGICAAkACAkJH1IrAGICAAsAAgkXIQIYALsAAAoAAQkAADxuADkAAAAA.Faqueueeight:BAAALgAFFAEJAQABLgAFFAMJBgAJAFAPAA==.Faqueuetoo:BAAALgAECgMJAgABLgAFFAMJBgAJAFAPAA==.Fatsloth:BAAALgADCgcJEAAAAA==.',
Fe='Feironos:BAAALgAECgMJDAAAAA==.Felray:BAAALgADCgUJCAAAAA==.Ferairi:BAAALgAECgQJCgABLgAECgYJEQADAAAAAA==.Fereir:BAAALgADCgQJBAAAAA==.Ferndavia:BAAALgAECgUJCQAAAA==.',
Fi='Fiist:BAAALgADCgYJDgAAAA==.Filigree:BAAALgADCgYJBgAAAA==.Fimtastic:BAAALgAECgcJEQAAAA==.Finasy:BAABLgAECn8hAAQaAAgJCB3+BgCyAQAaAAgJCB3+BgCyAQAQAAQJxhIOVwD+AAAbAAEJ4g9FFwAzAAAAAA==.Finnicka:BAAALgADCgcJDQAAAA==.Fireouch:BAAALgAECgEJAQAAAA==.Fistymisty:BAAALgAECggJDAAAAA==.',
Fl='Flaynpray:BAAALgAECgcJAgAAAA==.Flopsie:BAAALgAECggJDAAAAA==.',
Fo='Fonzsupreme:BAABLgAECn8YAAINAAYJnCKmVwAyAgANAAYJnCKmVwAyAgABLgAFFAQJCgAUAG0dAA==.Foxkit:BAAALgAECgEJAgAAAA==.',
Fr='Fredox:BAAALgADCgcJBwAAAA==.Freemilk:BAAALgADCgEJAQAAAA==.Frostbight:BAAALgADCgUJCAAAAA==.Frostyflake:BAAALgADCgUJBQAAAA==.',
Fu='Furearia:BAAALgAECgMJAwAAAA==.Furrybowner:BAAALgAECgYJDQAAAA==.',
['Fó']='Fóx:BAAALgAECgYJBwAAAA==.',
Ga='Gaelai:BAAALgAECgUJBgAAAA==.Galeriel:BAACLgAFFH8JAAIcAAMJexaQCgDkAAAcAAMJexaQCgDkAAAuAAQKfygAAhwACQnIGKISAEsCABwACQnIGKISAEsCAAAA.Gallethline:BAAALgADCgcJHAAAAA==.Garault:BAAALgAECgUJBQAAAA==.',
Ge='Gekoni:BAABLgAECn8VAAIEAAgJGwpgJQDdAAAEAAgJGwpgJQDdAAAAAA==.Geonon:BAABLgAECn8YAAINAAgJ3AnATgBEAQANAAgJ3AnATgBEAQAAAA==.Georgemoyd:BAAALgADCgkJCwAAAA==.',
Gi='Girthybeam:BAAALgADCgcJDQAAAA==.',
Gl='Glandrien:BAAALgAECgMJAwAAAA==.Gloomshak:BAAALgAECgMJAgAAAA==.Glowclaws:BAAALgADCgQJAwAAAA==.Glowpwr:BAAALgADCgMJAwAAAA==.',
Go='Gobblerella:BAAALgADCgMJAwAAAA==.Gobeullin:BAAALgAFFAEJAQAAAA==.Goonthergg:BAAALgADCgIJAwAAAA==.Gothmog:BAAALgADCgMJAwAAAA==.',
Gr='Graytonson:BAAALgAECgEJAQAAAA==.Greenhills:BAAALgADCgIJAgAAAA==.Greenlocks:BAAALgADCgIJAgABLgAFFAEJAQADAAAAAA==.Greenrånger:BAAALgAECgQJCwAAAA==.Greybush:BAAALgAECgQJBwAAAA==.Griffithw:BAAALgADCgYJCwAAAA==.Grombrindil:BAAALgAECgEJAQABLgAECgcJFQARAPwMAA==.Grullander:BAABLgAECn8bAAIdAAcJaBZ2FADIAQAdAAcJaBZ2FADIAQAAAA==.Grullandur:BAAALgAECgEJAQABLgAECgcJGwAdAGgWAA==.',
Gu='Guiguiie:BAAALgADCgcJBwAAAA==.',
['Gó']='Gólden:BAAALgADCgYJBgAAAA==.',
Ha='Hahacx:BAACLgAFFH8CAAIMAAIJShM8PgBUAAAMAAIJShM8PgBUAAAuAAQKfxkAAgwACAmdIV0SAOwCAAwACAmdIV0SAOwCAAAA.Halazzì:BAAALgAECgMJAwAAAA==.Haleon:BAAALgAECgIJAgAAAA==.Haraharotou:BAAALgAECgMJBgAAAA==.Hardyhar:BAAALgADCgMJBAAAAA==.',
He='Hebrews:BAAALgADCgYJBgAAAA==.Herkharu:BAAALgAECgcJEQAAAA==.Hermionee:BAAALgAECgQJBwAAAA==.',
Hi='Himjongun:BAABLgAECn8bAAMeAAYJzQ+rLABkAQAeAAYJPQ+rLABkAQAMAAYJdQg0QADmAAAAAA==.',
Ho='Hobbitdemon:BAAALgAECgQJBAAAAA==.Hobbitdruid:BAAALgAECgcJEgAAAA==.Hobbitvoid:BAAALgAECgEJAQAAAA==.Holydagoon:BAAALgADCgYJBgABLgAFFAUJCgATAMUUAA==.Hoother:BAAALgAECgYJBgAAAA==.Hoppingmuff:BAAALgADCgcJDQAAAA==.',
Hu='Hunia:BAAALgAECgUJDQAAAA==.Huntieluis:BAAALgAECgQJBAAAAA==.Hurndredd:BAAALgAECgIJAwAAAA==.Huuh:BAAALgADCgMJBgAAAA==.',
Hy='Hystericc:BAAALgAECgEJAQAAAA==.',
['Hé']='Héboric:BAAALgAECgQJBgAAAA==.',
Id='Idolon:BAAALgADCggJGAAAAA==.',
Ik='Ikashi:BAAALgADCgEJAQAAAA==.Ikodiwa:BAAALgAECgYJCwAAAA==.',
Il='Ilrion:BAAALgAECgYJDQAAAA==.',
In='Indravax:BAAALgAECgIJAgAAAA==.Inferno:BAAALgAECgEJAwAAAA==.',
Is='Iseehot:BAABLgAECn8bAAINAAYJXR5JNQCQAQANAAYJXR5JNQCQAQAAAA==.',
Iv='Ivantis:BAAALgAECgQJBAAAAA==.Ivie:BAABLgAECn8aAAIPAAgJ7RJxHACdAQAPAAgJ7RJxHACdAQAAAA==.Ivieenfuego:BAABLgAECn8jAAITAAgJwQSLJQDcAAATAAgJwQSLJQDcAAAAAA==.',
Ja='Jackjackk:BAAALgADCgQJBAAAAA==.Jadednurse:BAAALgAECgYJEQAAAA==.Jakisormjr:BAAALgADCgIJAgAAAA==.Jalanii:BAAALgAECgYJCwAAAA==.Janjor:BAABLgAECn8kAAIfAAgJjh9PGgBBAgAfAAgJjh9PGgBBAgAAAA==.Janjorski:BAAALgADCgQJBAAAAA==.Jayrior:BAAALgADCgcJCwAAAA==.',
Je='Jehlock:BAAALgAECgUJCgAAAA==.Jehvoker:BAAALgAECgUJBgABLgAECgUJCgADAAAAAA==.Jerghal:BAAALgAECgYJDAAAAA==.Jettian:BAAALgAECgQJCgAAAA==.',
Ji='Jinu:BAAALgADCgIJAgAAAA==.',
Jj='Jjdruid:BAAALgAECgEJAQAAAA==.',
Jo='Jockwork:BAAALgAECgQJCwAAAA==.Jolene:BAABLgAECn8aAAIZAAcJbApPIAD7AAAZAAcJbApPIAD7AAAAAA==.Jollygreene:BAAALgAECgUJCQAAAA==.Joyina:BAAALgADCgkJIgAAAA==.',
Ju='Justicee:BAAALgAECgQJCAABLgAECggJDAADAAAAAA==.',
Jx='Jxy:BAAALgAECgUJCQABLgAFFAUJEgAMAHwhAA==.',
Ka='Kachess:BAAALgADCgIJAgAAAA==.Kahri:BAAALgAECgYJDwAAAA==.Kakali:BAAALgADCgEJAQAAAA==.Kalend:BAAALgAECgMJAwAAAA==.Karlager:BAABLgAECn8VAAIRAAcJ/AylFgA0AQARAAcJ/AylFgA0AQAAAA==.Karlain:BAAALgAECgUJBwAAAA==.Kasaide:BAAALgADCgcJBwABLgAECggJIQAJAJoOAA==.Kasmir:BAABLgAECn8hAAIJAAgJmg69KQCGAQAJAAgJmg69KQCGAQAAAA==.Katia:BAAALgADCgUJBwAAAA==.Kazoo:BAAALgADCgUJBQABLgAFFAQJDQAVAKUZAA==.',
Ke='Kelbek:BAAALgAECgQJBAAAAA==.Kelisii:BAAALgAECgcJCgAAAA==.Keloenivas:BAAALgADCggJEQAAAA==.Kelomage:BAAALgAECgEJAQAAAA==.Ketaza:BAAALgAECgEJAQAAAA==.Keyash:BAAALgADCgIJAgAAAA==.',
Kh='Khyle:BAAALgADCgEJAQABLgADCgcJEAADAAAAAA==.',
Ki='Kibblebits:BAABLgAECn8aAAIZAAcJcAM4LQCnAAAZAAcJcAM4LQCnAAAAAA==.Kijanajr:BAAALgAECgIJAgAAAA==.Kitheros:BAAALgADCgcJBwAAAA==.Kittun:BAAALgADCgEJAQAAAA==.',
Kl='Klay:BAABLgAECn8YAAQUAAcJWyPoCgBiAgAUAAcJWyPoCgBiAgACAAIJpQpiNABgAAABAAIJtQKDngBGAAAAAA==.Klutch:BAAALgADCgIJAgAAAA==.',
Km='Kmarti:BAEBLgAECn8dAAMMAAgJRCBlIQCJAgAMAAgJRCBlIQCJAgAeAAIJ/wv6XwBiAAAAAA==.',
Ko='Koivath:BAAALgADCgkJEQAAAA==.Konradevoker:BAAALgAFFAEJAgABLgAECgkJKwAJAFQeAA==.Konradlock:BAABLgAECn8rAAMJAAkJVB6aBgBVAwAJAAkJVB6aBgBVAwAKAAIJVxkxTQCGAAAAAA==.Konradrogue:BAABLgAECn8xAAMgAAkJuh6sAABiAwAgAAkJox6sAABiAwAhAAcJYxrXHQAPAgABLgAECgkJKwAJAFQeAA==.Konradwar:BAABLgAECn8XAAMCAAYJNx7/EgB0AQACAAYJZhj/EgB0AQABAAQJpRa4bgD8AAABLgAECgkJKwAJAFQeAA==.Kosmicknight:BAABLgAECn8VAAIQAAcJgA7RhwBxAQAQAAcJgA7RhwBxAQAAAA==.',
Kr='Krathös:BAAALgAECgQJBAAAAA==.Krethrah:BAACLgAFFH8VAAIQAAYJPiP+AQABAgAQAAYJPiP+AQABAgAuAAQKfxcAAhAACAktI3wUAAADABAACAktI3wUAAADAAAA.Kromak:BAAALgAECgQJBAAAAA==.',
Ku='Kunfoopizza:BAAALgAECgQJCQAAAA==.Kuulibah:BAAALgADCgEJAQABLgADCgMJAwADAAAAAA==.Kuulibarr:BAAALgADCgMJAwAAAA==.',
Kw='Kwarr:BAACLgAFFH8JAAIdAAMJrBGRDwDrAAAdAAMJrBGRDwDrAAAuAAQKfxYAAh0ABwnOFxUxAMIBAB0ABwnOFxUxAMIBAAEuAAUUBAkHABQAjhIA.',
Ky='Kynaragon:BAABLgAECn8lAAMZAAcJfSaOGABEAgAZAAYJZSaOGABEAgAPAAQJ0CQjSQB+AQABLgAECgkJLQAPALYmAA==.Kyrimmon:BAAALgAECgEJAQAAAA==.',
La='Lallypop:BAAALgAECgQJCAAAAA==.Lammoth:BAAALgAECgEJAQAAAA==.Lanthein:BAAALgAECgEJAQABLgAFFAUJCgATAMUUAA==.Laraela:BAAALgADCgEJAQAAAA==.Largehusband:BAAALgADCgUJBgAAAA==.Larkindas:BAAALgAECgEJAQAAAA==.Layil:BAAALgADCgYJBwAAAA==.',
Le='Leafu:BAAALgAECgQJCAABLgAECgcJGgAWAIYbAA==.Leasin:BAABLgAECn8aAAIWAAcJhhvNDgCbAQAWAAcJhhvNDgCbAQAAAA==.Leathle:BAAALgADCgkJEAAAAA==.Leepa:BAAALgAECgcJDAAAAA==.Lepp:BAAALgAECgEJAQAAAA==.Lexslaner:BAAALgADCgYJCQAAAA==.',
Li='Lighthusk:BAABLgAECn8UAAMcAAgJBx5dAwCwAgAcAAgJBx5dAwCwAgAWAAEJxAOwaAAnAAABLgAECggJFAAcAAceAA==.Liliauna:BAAALgAECggJEgAAAA==.Lilibejeane:BAAALgAECgEJAQABLgAECgYJDQADAAAAAA==.Lilithalen:BAABLgAECn8nAAIcAAgJfBnpFQAtAgAcAAgJfBnpFQAtAgAAAA==.Lilmymy:BAAALgAECgEJAQAAAA==.Lilshimer:BAABLgAECn8WAAMJAAYJURWaVgDEAQAJAAYJURWaVgDEAQALAAIJdQMmIQBtAAAAAA==.Lilsquirtboy:BAACLgAFFH8HAAIQAAIJ5SAuQgDBAAAQAAIJ5SAuQgDBAAAuAAQKfysAAxAACAltJDQFANICABAACAltJDQFANICABoAAQmZCcJNABsAAAAA.Lizardbird:BAAALgAECgQJBwAAAA==.',
Lo='Lockitt:BAABLgAECn8WAAIJAAkJBg0aXQCxAQAJAAkJBg0aXQCxAQAAAA==.Lostgrip:BAAALgAECgEJAQAAAA==.',
Lu='Lucthedk:BAAALgAECgYJEwAAAA==.Luk:BAAALgADCgYJBgAAAA==.Lukis:BAAALgADCgYJDAAAAA==.Lumario:BAAALgADCgEJAQAAAA==.Lunarpriest:BAAALgAECgEJAQAAAA==.Lunkbeck:BAAALgADCgUJBgAAAA==.Luva:BAAALgADCgUJBgAAAA==.',
Ly='Lyio:BAAALgAECgUJCgAAAA==.',
Ma='Madmandeath:BAAALgADCgQJAwAAAA==.Mahlanas:BAAALgAECgYJDgAAAA==.Maki:BAAALgAFFAEJAQAAAA==.Maladin:BAAALgAECgMJAwAAAA==.Malvean:BAAALgADCgcJCgAAAA==.Mamajoy:BAAALgADCgMJBgAAAA==.Maravilla:BAAALgAECgYJDQAAAA==.Marceline:BAAALgAECgYJBgAAAA==.Markuspapa:BAAALgAECgQJBAABLgAFFAQJDQAVAKUZAA==.Marlowe:BAAALgAECgUJBQAAAA==.Marremer:BAAALgAECgUJEQAAAA==.',
Mc='Mckicky:BAAALgAECgYJDwAAAA==.',
Me='Mechafire:BAAALgADCgYJBgAAAA==.Melanius:BAABLgAECn8aAAMXAAcJKiR8AQDiAgAXAAcJKiR8AQDiAgAYAAEJYg0LQQAuAAAAAA==.Melodras:BAABLgAECn8WAAMcAAgJ6A8iEwB+AQAcAAgJ6A8iEwB+AQAVAAIJkgZnTgBXAAAAAA==.Memelord:BAAALgAECgQJCgAAAA==.Merce:BAAALgADCgEJAQAAAA==.Metalock:BAAALgADCgcJCwAAAA==.Mewalina:BAAALgADCgQJBAAAAA==.',
Mi='Mirajen:BAAALgADCgMJAwAAAA==.Mirukoo:BAAALgAECgQJBAAAAA==.Misconduct:BAAALgAECgQJCgAAAA==.Mistywaters:BAAALgAECgEJAgAAAA==.Mittyy:BAAALgADCgYJBwAAAA==.',
Mo='Mornintreant:BAAALgADCgMJAwAAAA==.Mousekewitzk:BAAALgADCgEJAQAAAA==.Movarth:BAAALgADCgkJCQAAAA==.',
Mu='Mujer:BAAALgAECgEJAQAAAA==.Mungas:BAAALgADCgUJBgAAAA==.Murlloc:BAAALgADCgcJBgAAAA==.',
My='Myrathia:BAABLgAFFH8FAAIPAAIJmARMKwBtAAAPAAIJmARMKwBtAAAAAA==.Myrcella:BAAALgAECgQJBQAAAA==.',
['Má']='Máximodécimo:BAAALgAECgIJAwAAAA==.',
Na='Nahemah:BAAALgAECgIJAwAAAA==.Nahtan:BAABLgAECn8YAAIFAAYJGAquPAAhAQAFAAYJGAquPAAhAQAAAA==.Nahwe:BAAALgADCgUJBQAAAA==.Narrsul:BAABLgAECn8XAAIJAAYJ5xJLQQAuAQAJAAYJ5xJLQQAuAQAAAA==.Nattyg:BAAALgAECgYJCgAAAA==.Naves:BAAALgADCgIJAgAAAA==.',
Ne='Nereza:BAAALgADCgUJBgAAAA==.Nevermorte:BAAALgAECgYJBgAAAA==.',
Nf='Nfggolden:BAAALgAECgcJAwAAAA==.',
Ni='Nightforday:BAABLgAECn8wAAIQAAgJwBkLEwAhAgAQAAgJwBkLEwAhAgAAAA==.Niko:BAAALgAECgQJBQAAAA==.',
No='Noknani:BAAALgADCgUJBgAAAA==.Nokx:BAAALgAECgEJAQAAAA==.Nool:BAAALgADCgcJCQAAAA==.Norch:BAAALgADCgMJAwAAAA==.Nostranova:BAAALgAECgEJAQAAAA==.Novà:BAAALgADCgMJAwAAAA==.',
Ny='Nyriand:BAAALgADCgQJBAAAAA==.',
Oh='Ohkayboomer:BAAALgAFFAEJAQAAAA==.',
Ok='Oktraal:BAAALgAECgEJAQAAAA==.',
Oo='Oontanx:BAAALgADCgcJCQAAAA==.Ooups:BAABLgAECn8YAAIGAAgJzBOuDAC/AQAGAAgJzBOuDAC/AQAAAA==.',
Op='Ophysia:BAAALgAECgcJEwAAAA==.',
Or='Orangecage:BAABLgAECn+kAAMZAAkJliVHAABxAwAZAAkJliVHAABxAwAPAAIJfwYhswBeAAAAAA==.Orkcansas:BAAALgAFFAEJAQAAAA==.',
Os='Osrsfemale:BAAALgAECgIJAgAAAA==.',
Ov='Overlooker:BAAALgADCgMJAwAAAA==.',
Ox='Oxazine:BAABLgAECn8VAAMfAAgJBBNfKgDbAAAfAAYJyA9fKgDbAAAdAAUJjQNvRwCFAAAAAA==.',
Pa='Paapineau:BAAALgAECgYJDwAAAA==.Packel:BAAALgADCgEJAQABLgAECggJGgAiAPARAA==.Palladias:BAAALgAECgQJBgAAAA==.Pally:BAAALgADCgIJAgAAAA==.',
Pc='Pcm:BAAALgAECgYJCQAAAA==.',
Pe='Peefmajeef:BAAALgADCgIJAgAAAA==.Peony:BAAALgADCgQJBAAAAA==.Pepperjack:BAAALgADCgYJDQAAAA==.Pewpeew:BAAALgAECgUJDAAAAA==.',
Ph='Phantomclone:BAAALgAECgYJEAAAAA==.Phantomghoul:BAAALgADCgEJAQAAAA==.Phantomwar:BAAALgAECgIJAgAAAA==.Phantomzz:BAAALgAECgEJAQAAAA==.Pheonixxwolf:BAAALgAECgYJDgAAAA==.Pherc:BAAALgADCgcJBwAAAA==.Phillyblunt:BAABLgAECn8aAAMdAAcJURNEMQDBAQAdAAcJURNEMQDBAQAfAAEJDQcfiwAtAAAAAA==.Phløw:BAAALgADCgMJBwAAAA==.',
Pl='Plaguekitten:BAAALgAECgEJAQAAAA==.Plowpatine:BAAALgAFFAIJAgAAAA==.',
Po='Poolius:BAAALgAECgQJDQAAAA==.Porfinne:BAAALgADCgQJBAAAAA==.',
Pr='Praedor:BAAALgADCgUJBQAAAA==.Preza:BAAALgADCgIJAgAAAA==.Priestymon:BAABLgAECn8dAAMVAAgJjxuACgCRAgAVAAgJjxuACgCRAgAWAAMJHxOIKAC7AAABLgAFFAQJCQABANAVAA==.Prober:BAAALgADCgUJBQAAAA==.Producer:BAAALgAECgEJAQAAAA==.Protato:BAAALgADCgYJBQAAAA==.Prowaifu:BAAALgAECgEJAQAAAA==.Prowess:BAAALgADCggJFAAAAA==.Prîestitute:BAAALgADCgYJCQAAAA==.',
Pu='Purger:BAAALgADCgYJCgAAAA==.Puyo:BAABLgAECn8aAAIiAAgJ8BF5CABWAQAiAAgJ8BF5CABWAQAAAA==.Puyyoo:BAAALgADCgcJDwABLgAECggJGgAiAPARAA==.',
Pw='Pwarr:BAACLgAFFH8HAAIUAAQJjhKfBwAMAQAUAAQJjhKfBwAMAQAuAAQKfxoAAhQABwlSH7kKAGUCABQABwlSH7kKAGUCAAAA.',
Py='Pyrofox:BAAALgADCgEJAQAAAA==.',
Qw='Qwarr:BAACLgAFFH8JAAMTAAMJVgpUGQDfAAATAAMJVgpUGQDfAAAYAAIJWQnZBgChAAAuAAQKfzMAAxMACQnlH8gBAPMCABMACQnlH8gBAPMCABgABglCHugPANwBAAEuAAUUBAkHABQAjhIA.',
Ra='Rafoen:BAABLgAFFH8FAAIhAAIJ1hNzEwCwAAAhAAIJ1hNzEwCwAAAAAA==.Rakrur:BAAALgADCgEJAQAAAA==.Ramsay:BAAALgADCgkJEQAAAA==.Rathorn:BAAALgADCgYJDAAAAA==.Raxsan:BAAALgAFFAMJBAAAAA==.Raydanbalor:BAAALgAECgUJBQABLgAECgUJEQADAAAAAA==.Rayennagrom:BAAALgAECgYJCwAAAA==.Razkko:BAAALgADCgUJBQAAAA==.',
Rd='Rdru:BAAALgADCgcJBwABLgAECgYJCgADAAAAAA==.',
Re='Redpumpkin:BAAALgADCgMJAwAAAA==.Redsonja:BAAALgADCgcJDQAAAA==.Reneana:BAAALgAECgMJAgAAAA==.Respectisluv:BAABLgAECn8UAAIjAAcJKAueEABWAQAjAAcJKAueEABWAQAAAA==.Rexcor:BAAALgAECgQJBwAAAA==.',
Rh='Rhulad:BAAALgADCggJCAAAAA==.',
Ri='Riaeline:BAAALgAECgQJBgAAAA==.Richardluis:BAAALgADCgkJCQAAAA==.Rinehardtt:BAAALgAECgUJCQABLgAECgYJCQADAAAAAA==.Ripheals:BAACLgAFFH8OAAIdAAQJjBFqEAAOAQAdAAQJjBFqEAAOAQAuAAQKfysAAx0ACAnVGssdAC0CAB0ACAnVGssdAC0CAB8ABAkoHhBBAEUBAAAA.Riplee:BAAALgADCgYJCwABLgAFFAQJDgAdAIwRAA==.Rivër:BAABLgAECn8XAAIIAAgJgBv5PwAmAgAIAAgJgBv5PwAmAgAAAA==.',
Ro='Robbell:BAABLgAECn8bAAIFAAgJahkLIABFAgAFAAgJahkLIABFAgAAAA==.Rogueflame:BAAALgAECgcJDQAAAA==.Rootsie:BAAALgAECgQJDAAAAA==.Roselynn:BAABLgAECn8iAAIPAAgJJx3hDwC5AgAPAAgJJx3hDwC5AgAAAA==.',
Rs='Rsolbes:BAAALgADCgUJBQAAAA==.',
Ru='Ruerl:BAAALgAECgcJEQAAAA==.Rumblies:BAAALgAECgQJDAAAAA==.Runetusk:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Rungin:BAAALgADCgEJAQAAAA==.Russopp:BAAALgADCgEJAQAAAA==.',
Sa='Saars:BAAALgADCgYJBgAAAA==.Samchan:BAAALgAECgEJBAAAAA==.Sanatharia:BAAALgAECgQJBgAAAA==.Saneatey:BAAALgAECgUJCwAAAA==.Sassibelle:BAAALgAECgUJBQAAAA==.Satanskidney:BAAALgADCgcJCAAAAA==.Sathenset:BAACLgAFFH8KAAITAAUJxRQHCQBoAQATAAUJxRQHCQBoAQAuAAQKfxUAAxgACAnLGEgRAMoBABgABwmsFkgRAMoBABMABAmrEjFDANQAAAAA.',
Sc='Scandium:BAABLgAECn8aAAILAAgJKRZzAQABAgALAAgJKRZzAQABAgAAAA==.Scrembiblion:BAABLgAECn8WAAINAAgJuht2GQATAgANAAgJuht2GQATAgAAAA==.',
Sd='Sdhoscillate:BAAALgAECgQJBQAAAA==.',
Se='Seagulpunchr:BAAALgADCgYJCgAAAA==.Seesh:BAACLgAFFH8KAAIBAAQJLiDxBgB+AQABAAQJLiDxBgB+AQAuAAQKfxgAAgEACQnSJBIDAIADAAEACQnSJBIDAIADAAAA.Sentarr:BAABLgAFFH8KAAIUAAQJbR0BAwB2AQAUAAQJbR0BAwB2AQAAAA==.Septhera:BAAALgAFFAEJAgAAAA==.',
Sh='Shadeyheals:BAAALgAECgYJCAAAAA==.Shadowxcraft:BAAALgAECgUJCQAAAA==.Shadrelin:BAAALgADCgEJAgAAAA==.Shaqler:BAAALgAECgMJBAAAAA==.Shecks:BAAALgADCgcJCAAAAA==.Shelandria:BAAALgAECgIJAgAAAA==.Sherwild:BAABLgAECn8YAAIPAAgJxiHzCgDqAgAPAAgJxiHzCgDqAgAAAA==.Shinara:BAAALgAECgYJDgAAAA==.Shiverchill:BAAALgAECgcJBQAAAA==.Shizznoint:BAAALgADCgMJAwAAAA==.Shnipishnap:BAABLgAECn9AAAMdAAkJHCPVAACgAwAdAAkJHCPVAACgAwAfAAgJMSMtAgDQAgAAAA==.Shnupel:BAAALgAECgkJBgAAAA==.Shroomjuicee:BAABLgAECn8VAAIVAAcJdhWmGgDCAQAVAAcJdhWmGgDCAQAAAA==.Shyi:BAAALgADCgYJBgAAAA==.',
Si='Sindaemon:BAACLgAFFH8FAAIMAAMJnxbxKgCpAAAMAAMJnxbxKgCpAAAuAAQKfyMAAgwACAntIWUUAN0CAAwACAntIWUUAN0CAAAA.Sindrina:BAAALgAECgIJAgAAAA==.',
Sk='Skelstone:BAAALgADCgYJBgAAAA==.Skädoosh:BAAALgAECgQJCAAAAA==.',
Sl='Slapshappy:BAABLgAECn8XAAIIAAcJbxksMQB9AQAIAAcJbxksMQB9AQAAAA==.Sloptop:BAAALgAECgMJAwAAAA==.Slowfall:BAAALgADCgcJCwAAAA==.',
Sm='Smokin:BAAALgAECgYJDwAAAA==.Smoothg:BAAALgAECgMJAwAAAA==.',
Sn='Snowjor:BAAALgADCgEJAQAAAA==.Snyx:BAAALgADCgUJBQAAAA==.',
So='Solaríus:BAAALgADCgMJAwAAAA==.Soldanas:BAAALgADCgEJAQAAAA==.Solomus:BAAALgAECgEJAQAAAA==.',
Sp='Spheaddin:BAAALgAECgEJAQAAAA==.Spiritbomb:BAAALgAECggJEwAAAA==.Spytime:BAAALgAECgYJBwAAAA==.',
Ss='Ssjchezzy:BAAALgAECgcJDgAAAA==.Ssmeltn:BAAALgAECgYJDQAAAA==.',
St='Steinberg:BAAALgADCgEJAQAAAA==.Stnaprednu:BAAALgAFFAIJAgAAAA==.Stormroid:BAAALgAECgMJBQAAAA==.Stormxwolf:BAAALgAECgYJDQAAAA==.Strangulate:BAAALgAECgQJBQAAAA==.Stripez:BAAALgADCgUJBwAAAA==.Stumpvee:BAAALgADCgMJAwAAAA==.',
Su='Sunmx:BAAALgAECgcJCgAAAA==.Superdark:BAAALgAECgMJAwAAAA==.',
Sw='Swurves:BAAALgADCggJDwABLgAECgYJEQADAAAAAA==.',
Ta='Taedrum:BAAALgAECgQJBAAAAA==.Taerror:BAACLgAFFH8PAAIcAAQJNiXZAQC6AQAcAAQJNiXZAQC6AQAuAAQKfywABBwACQmyI34AAK8DABwACQmyI34AAK8DABUAAgl5GEtFAI8AABYAAQktB9lDADAAAAAA.Tahkon:BAAALgAECgUJBQAAAA==.Tahmtan:BAAALgADCgcJEAAAAA==.Talegos:BAAALgAECgQJBAAAAA==.Talonfel:BAAALgADCgcJCwABLgAECggJKQAkAOkjAA==.Talonflight:BAAALgAECgQJBAABLgAECggJKQAkAOkjAA==.Talonstryke:BAABLgAECn8pAAIkAAgJ6SNeAQA4AwAkAAgJ6SNeAQA4AwAAAA==.Tanarious:BAAALgADCgQJBAAAAA==.Taytonar:BAABLgAECn8aAAIEAAcJAgYFFADNAAAEAAcJAgYFFADNAAAAAA==.',
Te='Teamocil:BAAALgAECgEJAwAAAA==.Teefa:BAAALgAECgYJCwAAAA==.Terak:BAAALgAECgEJAQAAAA==.Tevers:BAAALgADCgcJDAAAAA==.',
Th='Thane:BAAALgADCgMJAwAAAA==.Thaumium:BAAALgADCgEJAQAAAA==.Theenforcer:BAAALgAFFAEJAgAAAA==.Theguyfurry:BAAALgADCgcJCwAAAA==.Thidwick:BAAALgAECgQJBgAAAA==.Thingtwø:BAAALgAECgIJAgAAAA==.Thirdryker:BAAALgADCgIJAgAAAA==.Thorissa:BAABLgAECn8YAAIKAAgJzA0NEwCzAQAKAAgJzA0NEwCzAQAAAA==.Thäne:BAAALgAECgYJDQAAAA==.',
Ti='Tickletorque:BAAALgAECgQJBAAAAA==.Tiles:BAAALgAECgEJAQAAAA==.Timojj:BAAALgAECgEJAwAAAA==.Tinglu:BAAALgADCgcJCQAAAA==.Tinkk:BAAALgAECgYJBwAAAA==.Titø:BAAALgAECgYJCwAAAA==.',
To='Tomorrow:BAABLgAECn8WAAINAAcJCR/9TgBKAgANAAcJCR/9TgBKAgAAAA==.Topdog:BAAALgADCgYJDgAAAA==.Topzee:BAAALgAECgQJBwAAAA==.Torquin:BAAALgADCgMJAwAAAA==.Tottytotems:BAAALgADCgcJDAAAAA==.Touchmablade:BAAALgADCgQJBAAAAA==.',
Tr='Traylo:BAAALgAECgYJEgAAAA==.Treysong:BAAALgADCgMJAwAAAA==.',
Tu='Turkeymm:BAAALgADCgMJAwAAAA==.',
Tv='Tvak:BAABLgAECn8ZAAIIAAkJHCD/KQCaAQAIAAkJHCD/KQCaAQAAAA==.',
Tw='Twopump:BAABLgAECn8cAAIIAAcJuQbATAAlAQAIAAcJuQbATAAlAQAAAA==.',
Ty='Tygrarelea:BAAALgAECgEJAQAAAA==.Tynan:BAAALgADCgMJBQAAAA==.',
Ul='Ulinova:BAAALgAECgUJDAAAAA==.',
Uu='Uu:BAAALgAFFAMJAwAAAA==.',
Va='Vaiden:BAAALgADCgEJAQAAAA==.Vainqueur:BAAALgAECgYJCgAAAA==.Valoroso:BAAALgAECgQJBAAAAA==.Vanarios:BAAALgAECgEJAgAAAA==.Vanderius:BAAALgADCgkJCAAAAA==.Vanderpal:BAAALgADCggJBgAAAA==.Vanec:BAAALgADCgMJAwAAAA==.Varm:BAAALgAECgEJAQAAAA==.Vasarian:BAAALgAECgEJAQAAAA==.',
Ve='Veidima:BAAALgAECgQJBgAAAA==.Veigar:BAAALgADCgYJBgAAAA==.Velathrus:BAAALgADCgEJAQAAAA==.Velion:BAAALgAECgIJAwAAAA==.Verzweifeln:BAAALgAECgEJAQAAAA==.Vesenya:BAAALgAECgEJAQAAAA==.Veyez:BAAALgADCgkJDAAAAA==.',
Vh='Vhyrix:BAAALgAECgQJBQAAAA==.',
Vi='Viantel:BAAALgAECgYJEAAAAA==.Viklicious:BAAALgADCgkJCQAAAA==.Vinarn:BAABLgAECn8hAAMQAAcJxQ4dPABLAQAQAAcJMwwdPABLAQAbAAYJAg3/CQAzAQAAAA==.Vinyls:BAAALgAECgIJAgAAAA==.Viridias:BAAALgADCgEJAQAAAA==.Viridius:BAAALgAECgIJAgAAAA==.Virindi:BAAALgAECgEJAQAAAA==.',
Vr='Vrogar:BAAALgAECgcJCQAAAA==.',
Vy='Vyntage:BAAALgAECgYJBgAAAA==.',
['Vä']='Väelün:BAABLgAECn8ZAAIMAAYJYhBQRwDPAAAMAAYJYhBQRwDPAAABLgAECggJHgAiACcKAA==.',
Wa='Wachoosh:BAAALgAECgQJBAAAAA==.Wackamoose:BAABLgAECn8bAAQCAAcJ9BdNBQDYAQACAAcJ9BdNBQDYAQAUAAQJ7g53MADBAAABAAIJmgdUlgBnAAAAAA==.Wagoogusmay:BAAALgAECgEJAQAAAA==.Waidmanns:BAABLgAECn8gAAIFAAgJmRruHQBSAgAFAAgJmRruHQBSAgAAAA==.Walvet:BAAALgAECgYJEgAAAA==.Warc:BAAALgADCgUJBQAAAA==.Wargramps:BAAALgADCgQJBAAAAA==.Warrioo:BAAALgADCgMJAwABLgAECgcJBgADAAAAAA==.',
We='Weelad:BAAALgADCgkJFAAAAA==.Weldord:BAABLgAECn8qAAIFAAYJWw1iPwAYAQAFAAYJWw1iPwAYAQAAAA==.',
Wh='Whatorne:BAAALgAECgUJBgAAAA==.Whatyamean:BAAALgADCgEJAQAAAA==.Whiskeytaur:BAAALgADCgYJBgAAAA==.',
Wi='Wickedchick:BAAALgAECgQJCAAAAA==.Willowknight:BAAALgADCgYJCgAAAA==.',
Wo='Wolvareene:BAAALgADCgcJBwAAAA==.',
Wr='Wrongknight:BAAALgAECgQJCAAAAA==.Wrongname:BAAALgAECgUJDgAAAA==.',
Xa='Xalthérion:BAAALgAECgMJAwAAAA==.',
Xe='Xeruu:BAAALgADCgUJBQAAAA==.',
Xo='Xolan:BAACLgAFFH8FAAIPAAIJKQ2tGwCOAAAPAAIJKQ2tGwCOAAAuAAQKfx0AAg8ACAkQGtckACYCAA8ACAkQGtckACYCAAAA.',
Xp='Xprophet:BAAALgAECgQJCAAAAA==.',
Xu='Xunghuai:BAAALgADCgcJBwAAAA==.',
Xw='Xw:BAAALgADCgYJCwAAAA==.',
Ye='Yemonyunter:BAAALgADCgUJBQAAAA==.Yesyesyes:BAAALgADCgIJAgAAAA==.',
Yo='Yogsothoth:BAEBLgAECn8hAAMFAAgJehSmFgDdAQAFAAgJfROmFgDdAQAjAAYJjBBfFgBjAQAAAA==.Yooloakala:BAAALgADCgUJBQAAAA==.Yormaum:BAAALgADCgYJBgAAAA==.Yosha:BAAALgADCgcJCQAAAA==.',
Za='Zaartyn:BAAALgAECgcJEQAAAA==.Zalupalkys:BAAALgAECgQJAwAAAA==.Zarexion:BAAALgADCggJDAAAAA==.',
Ze='Zeebeth:BAAALgAECgYJCwAAAA==.Zefi:BAAALgAECgQJCAAAAA==.Zerokai:BAAALgAECgMJAwAAAA==.',
Zh='Zhahira:BAAALgAECgUJCgAAAA==.',
Zi='Zipsy:BAABLgAECn8gAAINAAcJ+w7WQwBjAQANAAcJ+w7WQwBjAQAAAA==.',
Zo='Zomlo:BAAALgAECgEJAQAAAA==.Zonka:BAAALgAECgEJAQABLgAECgUJBwADAAAAAA==.',
Zu='Zumtobel:BAAALgAECgMJAwAAAA==.Zuuko:BAACLgAFFH8TAAIRAAMJUh9VBwAiAQARAAMJUh9VBwAiAQAuAAQKfxoAAhEACQkHJKEGABUDABEACQkHJKEGABUDAAAA.',
Zy='Zyreth:BAAALgADCgYJCAAAAA==.',
['Ár']='Árthur:BAAALgAECgUJBwAAAA==.',
['År']='Åres:BAAALgAECgMJBgAAAA==.',
['Îs']='Îsadora:BAAALgADCgYJCQAAAA==.',
['Ýe']='Ýe:BAAALgADCgYJBgAAAA==.',
['ßu']='ßuzzibee:BAAALgAECgQJBAABLgAECgQJCgADAAAAAA==.',
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

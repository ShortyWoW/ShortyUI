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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Druid-Balance','Druid-Restoration','Druid-Guardian','Monk-Brewmaster','Hunter-BeastMastery','Paladin-Retribution','DemonHunter-Devourer','Paladin-Protection','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warrior-Fury','Mage-Arcane','Warrior-Arms','Hunter-Survival','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Warlock-Affliction','Evoker-Preservation','Mage-Frost','Priest-Discipline','DeathKnight-Blood','DemonHunter-Havoc','Warlock-Demonology','Hunter-Marksmanship','Monk-Mistweaver','Druid-Feral','Paladin-Holy','Warlock-Destruction','Warrior-Protection','Mage-Fire','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abattoir:BAAALgADCgIJAgAAAA==.',
Ad='Adyr:BAAALgAECgUJBQAAAA==.',
Ae='Aeleya:BAAALgAECgEJAQAAAA==.Aerouant:BAABLgAECn8dAAMBAAgJABI6BgCXAQABAAgJPRE6BgCXAQACAAYJAg60HQBAAQAAAA==.',
Af='Afganheals:BAAALgADCgYJBgAAAA==.Afhgankush:BAAALgAECgYJDAAAAA==.Afus:BAAALgADCgMJAwAAAA==.',
Ag='Aggelos:BAAALgAECgYJBgABLgAECgYJDgADAAAAAA==.',
Ah='Ahnkhan:BAABLgAECn8dAAQEAAgJEBfvBADIAQAEAAgJEBfvBADIAQAFAAUJFApyhQDMAAAGAAIJbg1JLABGAAAAAA==.',
Ai='Aidix:BAAALgADCgMJAwAAAA==.',
Ak='Akascia:BAAALgADCgYJBgAAAA==.Akfortyseven:BAAALgAECgMJAwAAAA==.',
Al='Alakablamm:BAAALgADCgMJBwAAAA==.Alandréa:BAAALgADCgcJEAAAAA==.Alariks:BAAALgADCgMJAwAAAA==.Alcyone:BAABLgAECn8jAAIFAAkJPBjBAgCKAgAFAAkJPBjBAgCKAgAAAA==.Alexstanna:BAAALgADCgcJCwAAAA==.Alicewism:BAAALgADCgYJBgAAAA==.Alicewismera:BAAALgAECgEJAQAAAA==.Alleksev:BAAALgAECgUJCwAAAA==.Almanor:BAAALgAECgQJBAAAAA==.Almendra:BAAALgAECgMJAwAAAA==.Alorades:BAAALgADCgEJAQABLgAECgQJBAADAAAAAA==.Alperen:BAABLgAECn8jAAMBAAkJ+h2AAQBqAgABAAgJDB2AAQBqAgACAAgJ0xgGCgA+AgAAAA==.Alphawarlock:BAAALgAECgUJBQAAAA==.',
An='Anagami:BAAALgAECgQJCAAAAA==.Andrena:BAAALgAECgIJAgAAAA==.Androwo:BAAALgADCgEJAQABLgADCgYJDQADAAAAAA==.Andyxd:BAAALgADCgYJAwAAAA==.Angelis:BAAALgAECgEJAQAAAA==.Anhsang:BAAALgAECgUJBgAAAA==.Antakata:BAABLgAECn8nAAIHAAkJURWrAwD3AQAHAAkJURWrAwD3AQAAAA==.Anthross:BAABLgAECn8VAAIIAAcJZQcGGwAlAQAIAAcJZQcGGwAlAQAAAA==.',
Ap='Apollovon:BAAALgAECgMJCgAAAA==.',
Ar='Argelmach:BAAALgAECgQJCQAAAA==.Aristodemuz:BAAALgADCgYJBgAAAA==.Armiggy:BAABLgAECn8ZAAIHAAgJbRcFGQA8AgAHAAgJbRcFGQA8AgAAAA==.Arthadrow:BAAALgAECggJEwAAAA==.',
As='Asavera:BAAALgAECgMJAwAAAA==.Ashenhowl:BAAALgAECgcJEwAAAA==.Ashenrune:BAAALgADCgMJAwAAAA==.Ashlit:BAAALgADCgMJBAAAAA==.Asmodeusz:BAAALgAECgMJBAAAAA==.Aspêct:BAAALgADCgEJAQAAAA==.Astheron:BAAALgAECgQJBAAAAA==.Astrâeâ:BAAALgADCgUJBQAAAA==.Asurmon:BAAALgADCgMJAwABLgAECgYJHwAJAFobAA==.',
Au='Aucoinflip:BAAALgAECgEJAQAAAA==.',
Av='Avraellia:BAABLgAECn8lAAIKAAkJ+B1QBABNAgAKAAkJ+B1QBABNAgAAAA==.',
Az='Azerlon:BAAALgAECgYJBwAAAA==.Azkaellon:BAABLgAECn8cAAMLAAgJSBoZCABZAgALAAgJxBkZCABZAgAJAAMJqhIp6QC9AAAAAA==.Azra:BAAALgADCgMJAwAAAA==.',
['Aù']='Aùrä:BAAALgAECgUJBwABLgAECgcJFAAFAO4ZAA==.',
Ba='Babydaddi:BAAALgADCggJGAAAAA==.Baddraggon:BAAALgADCgMJAwABLgAECgcJEwADAAAAAA==.Bairdy:BAAALgAECgYJEAAAAA==.Balnarg:BAAALgAECgQJBAABLgAECgQJBAADAAAAAA==.Balreth:BAAALgADCgYJCQAAAA==.Bashnsmash:BAABLgAECn8aAAIHAAkJbxzXDgCpAgAHAAkJbxzXDgCpAgAAAA==.Battlebeasty:BAAALgADCgYJBQAAAA==.',
Be='Bearbacon:BAAALgAECgEJAQAAAA==.Beastybro:BAAALgAECgUJCgAAAA==.Beefrow:BAAALgADCgcJDQAAAA==.Beleroth:BAABLgAECn8dAAIMAAYJIRWCHgApAQAMAAYJIRWCHgApAQAAAA==.Bellion:BAAALgADCgMJAwAAAA==.Beolwolf:BAAALgADCgUJBAAAAA==.Beriechdh:BAAALgADCgYJBgAAAA==.Berijar:BAAALgADCgMJBAABLgAFFAEJAQADAAAAAA==.Bernadette:BAAALgADCgYJCwAAAA==.Bestorestos:BAAALgAECgQJBAAAAA==.Betrayu:BAAALgADCgkJCwAAAA==.',
Bh='Bheisle:BAAALgAECgIJAgAAAA==.Bhmth:BAAALgADCgIJAgAAAA==.',
Bi='Biblehumping:BAABLgAECn8YAAMNAAgJCSA3EABkAgANAAgJCSA3EABkAgAOAAEJDgvfIAA3AAAAAA==.Bidness:BAAALgAECgMJAwAAAA==.Biean:BAAALgADCggJCAAAAA==.Bigchugga:BAAALgADCgYJBgAAAA==.Bigeazy:BAAALgADCgEJAQAAAA==.Bigmageman:BAAALgAECgcJBwAAAA==.Bilbotbagin:BAAALgAECgIJAwAAAA==.Bimbley:BAAALgADCgIJAgAAAA==.',
Bj='Bjobeagann:BAAALgADCgcJBwAAAA==.',
Bl='Blackplague:BAAALgADCgMJAwAAAA==.Bland:BAAALgADCgMJAgAAAA==.Bloodhunterx:BAAALgADCgYJBgAAAA==.Bloodreign:BAAALgAECgcJEQAAAA==.Bloodyvjj:BAAALgAECgQJBAAAAA==.',
Bo='Boldhar:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.Bonghunter:BAAALgADCgYJBgAAAA==.Bongwater:BAAALgAECgEJAQAAAA==.Bonobimbo:BAAALgADCgQJBAAAAA==.Booÿa:BAAALgAECgEJAQAAAA==.Bopdatazzqt:BAAALgAECgEJAQAAAA==.',
Br='Braazzy:BAAALgADCgQJBAAAAA==.Bridges:BAAALgAECgYJDAAAAA==.Brightpower:BAAALgADCgMJAwAAAA==.Broodwich:BAAALgADCgMJAwAAAA==.Bruhalo:BAAALgAECgMJAwAAAA==.',
Bu='Bubblezorz:BAAALgADCgYJCwAAAA==.Buckoh:BAAALgAECgQJBAAAAA==.Buttkick:BAAALgADCgcJEgAAAA==.',
Ca='Cadences:BAAALgAECgYJDAAAAA==.Carlosmario:BAAALgADCgEJAQAAAA==.Caustictouch:BAAALgAECgYJCQAAAA==.Caylor:BAAALgAECgMJAwAAAA==.',
Ce='Celirra:BAABLgAECn8pAAIMAAkJxyN3AAAjAwAMAAkJxyN3AAAjAwAAAA==.Cellsius:BAAALgADCgEJAQAAAA==.Cenzo:BAAALgADCgcJBwAAAA==.',
Ch='Chadingo:BAAALgADCgcJFgAAAA==.Charraf:BAAALgADCgYJBwAAAA==.Cheekybaby:BAABLgAECn8VAAIPAAcJHRRJCgB7AQAPAAcJHRRJCgB7AQAAAA==.Chewthefat:BAAALgADCgcJBwAAAA==.Chiflows:BAAALgADCgEJAQABLgADCgYJDQADAAAAAA==.Chiweaver:BAAALgAECgcJAgAAAA==.Choco:BAAALgADCgcJCgAAAA==.Chokeh:BAAALgAECgYJCgAAAA==.Choseph:BAAALgAECgQJBwAAAA==.Chunkyfists:BAAALgADCgEJAQAAAA==.Chupapii:BAAALgADCgYJCAAAAA==.Chëeks:BAAALgADCgEJAQAAAA==.',
Ci='Cinnaa:BAAALgAECgUJBQABLgAECgUJCQADAAAAAA==.Civilized:BAAALgAECgUJCQAAAA==.',
Cl='Clange:BAAALgAECgMJAwAAAA==.Clapton:BAAALgADCgMJAwAAAA==.Clawset:BAAALgADCgEJAQAAAA==.Clawwz:BAAALgAECgMJBQAAAA==.',
Co='Compressed:BAAALgAECgEJAgABLgAECgYJDwADAAAAAA==.Concealment:BAAALgADCgYJCgAAAA==.Conflux:BAAALgADCgQJBAAAAA==.Contrivex:BAAALgAECgYJEAAAAA==.Coolslight:BAAALgAECgQJBQAAAA==.Cootiegiver:BAAALgADCgMJAwAAAA==.Cornpops:BAAALgADCgEJAQAAAA==.Cozyhorse:BAAALgAECgEJAgAAAA==.Coñsfearacy:BAAALgADCgcJDAABLgAECgYJGAAQAMciAA==.',
Cr='Criticx:BAAALgAECgIJBAAAAA==.Crownkiller:BAAALgAECgMJAwAAAA==.Crventvs:BAAALgAECgUJCwAAAA==.',
Cu='Curlyp:BAAALgADCgcJBwAAAA==.Curzondax:BAABLgAECn8VAAIPAAkJrASQFQDuAAAPAAkJrASQFQDuAAAAAA==.',
Cy='Cyberfairy:BAAALgAECgUJDAAAAA==.Cyphinx:BAAALgAECggJDwAAAA==.',
['Cä']='Cät:BAAALgAECgMJBAABLgAECgQJBgADAAAAAA==.',
['Cò']='Còld:BAAALgAECgYJBgAAAA==.',
Da='Daduke:BAAALgAECgUJDQAAAA==.Dallroti:BAAALgAECgIJAgAAAA==.Dalìnar:BAAALgAECgcJEAAAAA==.Damadafacker:BAABLgAECn8VAAIRAAYJHBNkFABiAQARAAYJHBNkFABiAQAAAA==.Dankudai:BAAALgADCgcJCwAAAA==.Darkclôud:BAAALgAECgEJAwAAAA==.Darkeyès:BAAALgAECgIJAgAAAA==.Darklia:BAAALgAECgYJEQAAAA==.Darkrammz:BAABLgAECn8gAAIMAAkJ3h+AHADTAgAMAAkJ3h+AHADTAgAAAA==.Darksidedes:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Darktolight:BAAALgAECgUJDAAAAA==.Darkøs:BAAALgAECgcJEgAAAA==.Dashaman:BAAALgADCgQJBAAAAA==.Daulivandon:BAAALgAECgQJBAAAAA==.Davepriest:BAAALgAECgEJAQAAAA==.Davina:BAABLgAECn8aAAISAAgJWhzfBgCMAgASAAgJWhzfBgCMAgAAAA==.Daxxy:BAAALgAECgEJAQAAAA==.',
De='Deadestmoona:BAAALgADCgkJCQAAAA==.Deadzones:BAAALgADCgEJAgAAAA==.Dealsfirm:BAAALgADCgYJAgAAAA==.Deathalimon:BAAALgAECgEJAQABLgAECggJHQAEABAXAA==.Deathdots:BAAALgAECggJEQAAAA==.Deathlyguy:BAAALgAECgIJAgAAAA==.Deepfvalue:BAAALgAECgQJBQAAAA==.Demonarian:BAAALgAECgYJEQABLgAECggJHQAEABAXAA==.Demonpenguin:BAAALgADCgMJAwAAAA==.Deméter:BAAALgAECgMJBQAAAA==.Demönïcs:BAAALgAECgYJCgAAAA==.Denian:BAAALgADCgUJBQAAAA==.Deroc:BAABLgAECn8UAAIJAAcJxQ57JAAWAQAJAAcJxQ57JAAWAQAAAA==.Desporator:BAAALgAECgIJAgABLgAECgQJBAADAAAAAA==.Deswillhuntu:BAAALgADCgIJAgABLgAECgQJBAADAAAAAA==.Desyo:BAAALgADCgEJAQAAAA==.Devimon:BAAALgADCgEJAQAAAA==.',
Di='Diamondd:BAAALgADCgEJAQAAAA==.Diceyslicey:BAACLgAFFH8FAAITAAIJmRJDBACtAAATAAIJmRJDBACtAAAuAAQKfxcAAhMACQktGqUCAMMCABMACQktGqUCAMMCAAAA.Dietzel:BAAALgADCgQJAQAAAA==.Dillan:BAAALgADCgIJAgAAAA==.Dirtaycheese:BAAALgADCgcJCAAAAA==.Dirtycheese:BAAALgAECgYJDwAAAA==.',
Dj='Djuuras:BAAALgADCgcJDAAAAA==.',
Do='Doesntcare:BAAALgAFFAEJAQABLgAFFAEJAQADAAAAAA==.Doglock:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.Donquavius:BAAALgADCgUJBQAAAA==.Dorunter:BAAALgAECgcJEwAAAA==.Dotcleave:BAAALgAECgcJEQAAAA==.Dottíe:BAAALgADCgkJCgAAAA==.Doubledosage:BAAALgAECgYJDQAAAA==.',
Dr='Drachyn:BAAALgAECgcJCAAAAA==.Dragonxlayer:BAAALgADCgEJAQAAAA==.Drakismon:BAAALgADCgEJAQABLgAECggJHQAEABAXAA==.Drdoitall:BAAALgAECgUJBQAAAA==.Drsprinkles:BAAALgAECgUJBgAAAA==.Drwatzin:BAAALgADCgEJAQAAAA==.Drædgbw:BAAALgADCgUJBwAAAA==.',
Du='Dubhlinn:BAAALgAECgQJAwAAAA==.Durts:BAAALgADCgEJAQAAAA==.',
['Dö']='Döthrakí:BAAALgAECgIJAgAAAA==.',
Eb='Ebbis:BAAALgAECgUJBQAAAA==.',
Ed='Edaladalrian:BAAALgAECgMJBAAAAA==.',
Ef='Efickaçi:BAAALgADCgQJBAAAAA==.',
Ek='Ekogo:BAAALgADCggJDwAAAA==.',
El='Elazr:BAABLgAECn8ZAAILAAgJwBcADAAJAgALAAgJwBcADAAJAgAAAA==.Elontronic:BAAALgAECgEJAQAAAA==.Elosse:BAAALgADCgQJBAAAAA==.',
Em='Emmushka:BAABLgAECn8rAAIKAAkJ3yIwAQDXAgAKAAkJ3yIwAQDXAgAAAA==.',
En='Encephalo:BAAALgAECgEJAgAAAA==.Enhydra:BAAALgADCgcJEwAAAA==.Enosis:BAAALgAECgQJBAAAAA==.Ensee:BAAALgADCgcJDQAAAA==.Entaro:BAAALgADCgYJBgABLgAFFAQJBwAUAEcSAA==.Enthaimonk:BAABLgAECn8UAAMHAAcJqAy3SQAcAQAHAAcJsgu3SQAcAQAVAAUJ0wqwRQD/AAAAAA==.Entlordtb:BAAALgADCgMJAwAAAA==.Env:BAAALgAECgEJAQAAAA==.',
Eq='Eqv:BAABLgAECn8UAAIWAAgJqiHaAQC6AgAWAAgJqiHaAQC6AgAAAA==.',
Er='Ericolson:BAAALgAECgUJEwAAAA==.',
Es='Esteri:BAAALgAECggJDAAAAA==.',
Et='Etherios:BAAALgAECgYJDQAAAA==.',
Ev='Eversannik:BAAALgAECgYJBgAAAA==.Evé:BAAALgAECgUJBQABLgAECgkJIAAVAHIWAA==.',
Ex='Excuses:BAAALgAECgEJAQAAAA==.',
Ey='Eyllis:BAAALgADCgMJAwAAAA==.Eyoniss:BAAALgADCgQJAwAAAA==.',
Ez='Ezbakee:BAAALgAECgEJAwAAAA==.',
Fa='Faelyria:BAAALgADCgYJDQAAAA==.Fangluin:BAAALgADCgEJAQAAAA==.Fanndango:BAAALgAECgEJAQAAAA==.Farmerdragon:BAAALgADCgQJBQAAAA==.Fartbox:BAAALgAECgYJDAAAAA==.Favabean:BAAALgAECgEJAQAAAA==.',
Fe='Fearx:BAAALgAECgUJBQAAAA==.Febrezes:BAAALgAECgMJAwAAAA==.Fellboy:BAAALgADCgQJBAAAAA==.Fengshui:BAAALgADCgYJBgAAAA==.Feralco:BAAALgAECgQJBAAAAA==.',
Fi='Fifteenlegs:BAAALgADCgMJAwABLgAECgcJEwADAAAAAA==.Filoo:BAAALgADCgQJBAAAAA==.Fistma:BAAALgADCgYJBgAAAA==.',
Fl='Flapma:BAABLgAECn8VAAIBAAcJfAzCDQAOAQABAAcJfAzCDQAOAQAAAA==.Fleurdeheals:BAAALgADCgEJAQAAAA==.Flourae:BAAALgADCgEJAQAAAA==.Flourie:BAABLgAECn8nAAIXAAkJfQ50AwCxAQAXAAkJfQ50AwCxAQAAAA==.Flyhawk:BAAALgAECgMJBAAAAA==.Fläshlycan:BAAALgAECgEJAQAAAA==.Flåshlycan:BAAALgAECgEJAQAAAA==.Flöör:BAAALgADCgYJCAAAAA==.',
Fo='Folureen:BAAALgAECgQJBAAAAA==.Foorsaken:BAAALgAECgMJBQAAAA==.',
Fr='Freshapplez:BAABLgAECn8nAAIYAAgJix/8CgD9AQAYAAgJix/8CgD9AQAAAA==.Frezeypop:BAAALgAECgIJAgAAAA==.Frostbane:BAAALgAECgQJBwAAAA==.Frostbang:BAAALgADCgEJAQAAAA==.Frostdx:BAAALgAECgMJAwAAAA==.Frozenstiff:BAAALgAECgQJBwAAAA==.',
Fu='Fullchubb:BAAALgAECgYJEAAAAA==.Fullmetal:BAAALgADCgYJBgAAAA==.Fulmia:BAAALgAECgEJAQAAAA==.Fungsiyuk:BAAALgAECgEJAQAAAA==.Funkadelfic:BAAALgAECgQJBQAAAA==.',
Fy='Fyre:BAAALgADCgMJAwAAAA==.',
Ga='Gaarm:BAAALgADCgMJBAAAAA==.Gala:BAAALgADCgcJCwAAAA==.Galairan:BAAALgAECgUJCgAAAA==.Gallanos:BAAALgAECgIJAgABLgAECgUJCQADAAAAAA==.Garet:BAAALgAECgMJAwAAAA==.Garroshpally:BAAALgAECgcJDQAAAA==.Gatherer:BAAALgADCgcJCAAAAA==.Gaxxz:BAAALgAECgQJBAABLgAECgYJCAADAAAAAQ==.',
Gb='Gbhunter:BAAALgADCgcJCwAAAA==.',
Ge='Geartryx:BAAALgAECgQJCAAAAA==.Genjimainx:BAAALgADCgQJBAABLgAECgcJJwAPAIMjAA==.Geroth:BAAALgADCgYJBgAAAA==.Gett:BAAALgADCgcJBwAAAA==.',
Gh='Ghanz:BAAALgAECgEJAQAAAA==.Ghoshshadow:BAAALgADCgYJDgAAAA==.',
Gi='Giggie:BAAALgAECgUJBQAAAA==.Gilgalassian:BAAALgADCgEJAQAAAA==.Girlpissbrew:BAAALgADCgIJAgAAAA==.Gizzstrasza:BAABLgAECn8fAAMBAAkJpBWuEQBfAgABAAkJpBWuEQBfAgACAAQJngedLQCtAAAAAA==.',
Gl='Globb:BAAALgADCgcJDAAAAA==.Globius:BAABLgAECn8hAAIJAAkJFRxLBgAtAgAJAAkJFRxLBgAtAgAAAA==.Gloopp:BAAALgAECgQJBgAAAA==.Gloriouscole:BAAALgAECgEJAQAAAA==.Glâdiüs:BAAALgAECgIJAgAAAA==.',
Gn='Gnomepises:BAAALgAECgEJAQAAAA==.',
Go='Gotafuzybutt:BAAALgADCgcJEgAAAA==.',
Gr='Greekorc:BAAALgAECgEJAQAAAA==.Grillogoon:BAABLgAECn8XAAIPAAcJcBzeBwCjAQAPAAcJcBzeBwCjAQAAAA==.Grimby:BAAALgAECgkJEQAAAA==.Gromark:BAAALgAECgIJAwAAAA==.Grumby:BAABLgAECn8VAAIPAAgJUBR+IgBBAgAPAAgJUBR+IgBBAgAAAA==.',
Gu='Guccikage:BAAALgADCgMJAwAAAA==.Guldir:BAAALgADCgcJDQAAAA==.',
Gw='Gwendolÿn:BAAALgADCgcJCwAAAA==.',
Ha='Hams:BAAALgAECgYJCQAAAA==.Handsoap:BAAALgAECgYJCwAAAA==.Haye:BAAALgADCgEJAQAAAA==.',
He='Healman:BAAALgADCgcJCgAAAA==.Heihvorerdu:BAAALgAFFAEJAQAAAA==.Helganord:BAAALgADCgYJBgAAAA==.Heliosaegis:BAABLgAECn8VAAIKAAcJIg7IXACLAQAKAAcJIg7IXACLAQAAAA==.Hercueles:BAAALgAECgEJAQABLgAECgUJCQADAAAAAA==.Herenorthere:BAABLgAECn8qAAQOAAgJtAlgDQAeAQAOAAcJtAlgDQAeAQANAAQJRQ00aQCIAAAZAAEJkwINXAAqAAABLgAECgkJLgABANkZAA==.Hexngone:BAAALgADCgMJAwAAAA==.Hexstraits:BAABLgAECn8bAAIaAAgJ6BkPCwBlAgAaAAgJ6BkPCwBlAgAAAA==.',
Hi='Hia:BAAALgAECgEJAQAAAA==.Hitlist:BAAALgAECgUJBQAAAA==.',
Ho='Hodokken:BAAALgAECgcJBwAAAA==.Holyrockets:BAAALgADCgEJAQAAAA==.Holyzaimon:BAAALgADCgUJBQAAAA==.Hondaimpala:BAAALgADCgQJBAAAAA==.Hoodedrat:BAAALgAECgIJAgAAAA==.Hoolyavenger:BAAALgAECgMJAwAAAA==.Hootsy:BAAALgAECgUJBQAAAA==.Hotxy:BAAALgADCgMJBgAAAA==.',
Hu='Huhdean:BAABLgAECn8nAAMMAAkJDCWXAAASAwAMAAkJDCWXAAASAwAaAAcJ6BvkEAD8AQAAAA==.Hunterryan:BAAALgAECgcJAwAAAA==.Huntnwabits:BAAALgADCggJDQAAAA==.',
['Hê']='Hêlleon:BAAALgADCgIJAgAAAA==.',
Ic='Icedfuri:BAAALgAECgYJBgAAAA==.Icedpro:BAABLgAECn8eAAIKAAgJZheoCgDJAQAKAAgJZheoCgDJAQAAAA==.Icemike:BAAALgAECgQJCgAAAA==.Icyblaze:BAABLgAECn8oAAMQAAkJCyCaAwAuAgAQAAYJIyKaAwAuAgAYAAcJDRteFwCJAQAAAA==.',
Ih='Ihop:BAAALgAECgcJAQAAAA==.',
Ik='Ikillualot:BAAALgADCgMJAwAAAA==.',
Il='Illirobert:BAAALgADCgQJBQAAAA==.Illumi:BAAALgAECgUJCQAAAA==.Illénium:BAAALgADCgIJAgABLgAECggJJwAQAKMiAA==.Ilovecandy:BAAALgAECgEJAQAAAA==.',
Im='Impullsive:BAAALgADCgUJBQAAAA==.',
In='Innate:BAAALgADCgYJBQABLgADCgkJFAADAAAAAA==.Invalidnamed:BAAALgADCgQJBAAAAA==.',
Ir='Ires:BAAALgADCgYJBgAAAA==.Irimi:BAAALgADCgMJAwAAAA==.',
It='Itsjerry:BAAALgAECgYJCQAAAA==.',
Iw='Iwannacast:BAAALgADCgQJBQAAAA==.Iwillcrushyo:BAAALgAECgYJCgAAAA==.',
Iz='Izonie:BAABLgAECn8lAAMKAAgJ9RbJEQB1AQAKAAgJ9RbJEQB1AQAbAAEJ9xAAbAA6AAAAAA==.',
Ja='Jaaric:BAAALgADCgcJBwAAAA==.Jackinjones:BAAALgAECgQJCwAAAA==.Jaepriest:BAAALgADCgIJAgAAAA==.Jainalynn:BAAALgAECgEJAQAAAA==.Jalenbrunson:BAAALgADCgEJAQAAAA==.Jaquuib:BAAALgADCgIJAgABLgAECgUJBQADAAAAAA==.Jazira:BAAALgAECgYJDQAAAA==.',
Jd='Jdarkside:BAAALgADCggJDgAAAA==.',
Je='Jeremmiah:BAAALgADCgQJBAAAAA==.Jermus:BAAALgAECgEJAQABLgAECgYJGAAQAMciAA==.Jerrydh:BAAALgAECgIJAgAAAA==.Jesttrr:BAAALgAECgYJBgAAAA==.',
Jh='Jhacobo:BAABLgAECn8cAAIEAAkJJxUEFAByAgAEAAkJJxUEFAByAgAAAA==.',
Jo='Johnpaladin:BAAALgAECgMJAwAAAA==.',
Jr='Jragon:BAABLgAECn8XAAIcAAgJkhK5QQAIAgAcAAgJkhK5QQAIAgAAAA==.',
Ju='Juicedh:BAABLgAECn8bAAIKAAgJKiPSAgCBAgAKAAgJKiPSAgCBAgAAAA==.Juiceloc:BAAALgADCgMJAwABLgAECggJGwAKACojAA==.Juicy:BAABLgAECn8dAAIYAAgJPiXqDABeAwAYAAgJPiXqDABeAwAAAA==.Jumentous:BAAALgAECgcJDQAAAA==.Jungmin:BAAALgAECgcJEAAAAA==.',
Jx='Jxxy:BAABLgAECn8cAAIdAAgJJR8QDQDcAgAdAAgJJR8QDQDcAgAAAA==.',
['Já']='Jáinà:BAABLgAECn8nAAIYAAkJKRnhCAAaAgAYAAkJKRnhCAAaAgAAAA==.',
['Jú']='Júnjúnwälä:BAAALgAECgYJBgAAAA==.',
Ka='Kaikos:BAAALgADCgEJAQAAAA==.Kairue:BAAALgADCgEJAQABLgAECgkJKAAJAJIlAA==.Kalories:BAABLgAECn8ZAAIYAAgJHAlCtgBzAQAYAAgJHAlCtgBzAQAAAA==.Kappan:BAAALgADCgEJAQAAAA==.Karanakin:BAAALgAECgIJAgABLgAECgYJHwAJAFobAA==.Kareena:BAAALgADCgIJAgABLgADCgcJCwADAAAAAA==.Kaynz:BAAALgADCgYJBgAAAA==.',
Ke='Kellana:BAAALgADCgcJBwAAAA==.Kelsang:BAAALgADCgYJEAABLgADCggJDwADAAAAAA==.Kelvintwo:BAAALgADCggJCwAAAA==.Kennykeester:BAAALgADCgQJBAAAAA==.Kenrock:BAAALgAECgIJAgAAAA==.',
Ki='Kickington:BAAALgAECgEJAQAAAA==.Kidneysweeny:BAAALgAECgUJEwAAAA==.Kikkou:BAAALgAECgQJBAAAAA==.Kimbopable:BAABLgAECn8XAAILAAgJXBEPEQC2AQALAAgJXBEPEQC2AQAAAA==.Kinx:BAAALgAECgYJCAAAAA==.Kiraji:BAAALgAECgEJAQAAAA==.Kirsto:BAAALgAECgMJAwAAAA==.Kisagi:BAAALgAECgMJAwABLgAECgQJBgADAAAAAA==.Kittyassist:BAAALgADCgMJAwAAAA==.',
Ko='Kobin:BAAALgADCgIJAgAAAA==.Korgh:BAAALgAECgQJBgAAAA==.Koriayze:BAAALgAFFAEJAQAAAA==.Kotonano:BAABLgAECn8XAAIJAAgJ/x+7JACUAgAJAAgJ/x+7JACUAgAAAA==.Kozan:BAAALgAECgIJAgAAAA==.',
Kr='Krayelopay:BAABLgAECn8oAAIJAAkJkiVoAAAxAwAJAAkJkiVoAAAxAwAAAA==.Kraypapi:BAAALgADCgQJBAABLgAECgkJKAAJAJIlAA==.Krisjun:BAAALgAECgQJCQAAAA==.Krommcrocket:BAAALgAECgYJEQABLgAFFAEJAQADAAAAAA==.',
Ku='Kuarahy:BAAALgAECgEJAwAAAA==.Kunfugrip:BAABLgAECn8gAAMVAAkJchYHGAAjAgAVAAgJuxQHGAAjAgAeAAgJWhHoKgBhAQAAAA==.',
['Ká']='Kál:BAAALgAECgQJBAABLgAECggJGQAYABwJAA==.',
['Kä']='Kärtänus:BAAALgAECgQJBwAAAA==.',
La='Lanloris:BAAALgADCgcJDQAAAA==.Lanthos:BAABLgAECn8iAAIKAAkJTBPiLgBBAgAKAAkJTBPiLgBBAgAAAA==.Laojin:BAAALgAECgQJBwAAAA==.Lasrimas:BAAALgADCgMJAwAAAA==.Latavious:BAAALgADCgUJBwAAAA==.Laundrysoap:BAAALgAECgQJBQAAAA==.',
Le='Leboomjames:BAAALgADCgQJBQAAAA==.Ledanis:BAAALgADCgEJAQAAAA==.Lemonteatree:BAAALgAECgMJAwAAAA==.',
Li='Libidawalkin:BAAALgADCgEJAQAAAA==.Lielys:BAAALgADCgEJAQAAAA==.Lightmoo:BAAALgADCgMJAwABLgAECggJGAANAAkgAA==.Lightsavior:BAAALgADCgYJCAAAAA==.Lilina:BAAALgAECgMJBAAAAA==.Lillim:BAAALgADCgIJAgAAAA==.Lilsashi:BAAALgADCgUJBQAAAA==.Limeseltzer:BAAALgAECgYJCwAAAA==.Linarinia:BAAALgADCgcJDgAAAA==.Liqudcourage:BAAALgADCgMJAwAAAA==.Litesprey:BAAALgAECgUJBQAAAA==.Littleleg:BAAALgADCgYJDgAAAA==.',
Lm='Lmn:BAAALgAECgYJBgAAAA==.',
Lo='Loading:BAAALgAECgUJBQAAAA==.Loadingerror:BAAALgADCgEJAQAAAA==.Loadpumper:BAAALgADCgUJBQAAAA==.Lockasm:BAAALgAECgkJCwAAAA==.Loneorc:BAAALgAECgIJAgAAAA==.Lostkate:BAAALgAECgUJDQAAAA==.Lotheri:BAAALgAECgQJBwAAAA==.',
Lu='Luceri:BAAALgADCgMJAwAAAA==.Lulafairy:BAAALgAECgUJCwAAAA==.Lulo:BAAALgAECgYJCQAAAA==.Lumador:BAAALgADCgEJAQAAAA==.Lunatick:BAABLgAECn8fAAIaAAgJECAAAQByAgAaAAgJECAAAQByAgAAAA==.Lunawa:BAABLgAECn8fAAIYAAgJzx3NEwCjAQAYAAgJzx3NEwCjAQAAAA==.Lunätic:BAAALgADCgMJAwAAAA==.Lustbót:BAAALgAECgkJCQAAAA==.Luvnrdjr:BAAALgADCgcJCwAAAA==.',
Ly='Lyca:BAAALgAECgIJAgAAAA==.Lykann:BAAALgADCgMJBQAAAA==.Lykanthropy:BAAALgADCgQJBwAAAA==.',
Ma='Maahn:BAAALgADCgYJDAAAAA==.Macalob:BAAALgAECgQJBgAAAA==.Maddiebear:BAAALgADCggJEAAAAA==.Maflinggo:BAAALgAECgYJBgAAAA==.Magdagni:BAAALgAECgUJBwAAAA==.Magepies:BAAALgADCgEJAQABLgAECgcJDwADAAAAAA==.Malarkus:BAAALgAECgcJBQABLgAECgkJJQAIAO0mAA==.Malarkx:BAAALgAECgcJBgAAAA==.Mallgoth:BAAALgAECgQJBAAAAA==.Malphias:BAAALgADCgMJBAAAAA==.Malthaelyn:BAAALgAECgQJCAAAAA==.Mandarrtwo:BAAALgADCgEJAQAAAA==.Manosteel:BAAALgADCggJDAAAAA==.Marderdh:BAAALgAECgYJDwAAAA==.Marlonwayans:BAABLgAECn8nAAIFAAkJvwmgEABQAQAFAAkJvwmgEABQAQAAAA==.Maryola:BAAALgAECgYJDgAAAA==.Matdaemon:BAABLgAECn8aAAIKAAgJ0iS0CQA6AwAKAAgJ0iS0CQA6AwAAAA==.Mavraylvane:BAAALgADCgMJAwAAAA==.Mazìkeen:BAAALgADCgQJAwAAAA==.',
Mb='Mbarrigag:BAAALgADCgQJBAAAAA==.',
Mc='Mcprotein:BAAALgADCgYJCgAAAA==.',
Me='Medizyn:BAAALgADCgcJBwAAAA==.Medlock:BAAALgAECgIJAQAAAA==.Meewcow:BAAALgAECgMJBAAAAA==.Mehiel:BAAALgAFFAIJAwAAAA==.Melfice:BAAALgADCgYJBgAAAA==.Menachi:BAAALgADCgcJBwAAAA==.Merkén:BAAALgAECgMJBQAAAA==.Meroko:BAAALgADCgcJBwABLgAECgcJCwADAAAAAA==.Merxenary:BAAALgADCgkJCwAAAA==.Metaloclypse:BAAALgADCgEJAQAAAA==.Mezaryn:BAAALgAECgcJAgABLgAECgkJBwADAAAAAA==.Mezzara:BAAALgAECgcJDgABLgAECgkJBwADAAAAAA==.Mezzoo:BAAALgAECgkJBwAAAA==.',
Mi='Milannie:BAAALgADCgUJBQAAAA==.Millic:BAAALgAECgYJEQAAAA==.Millish:BAAALgADCgQJBAAAAA==.Minax:BAABLgAECn8dAAMXAAgJehr4CQCWAgAXAAgJehr4CQCWAgABAAYJDwh7DwD2AAAAAA==.Minimejr:BAAALgADCgcJCwAAAA==.Minionlife:BAAALgADCgUJBgAAAA==.Missluna:BAAALgAECgQJBgAAAA==.',
Mo='Mongobrain:BAAALgAECgMJAwAAAA==.Monkjam:BAAALgAECgEJAQAAAA==.Mootios:BAAALgAECgEJAwAAAA==.Mors:BAAALgADCgYJCAAAAA==.',
Mt='Mtxboy:BAAALgAECgIJAgABLgAFFAMJBQAfAHEHAA==.',
Mu='Muckdile:BAACLgAFFH8NAAISAAUJfB/hAACBAQASAAUJfB/hAACBAQAuAAQKfxUAAxIACAkRI3wEANACABIACAkRI3wEANACAB0AAglmFIdrAJAAAAAA.Muckstab:BAAALgADCgcJBwAAAA==.Murlldrood:BAAALgADCgYJCQAAAA==.',
My='Mykols:BAAALgADCgMJAwAAAA==.Mystwolf:BAABLgAECn8XAAIeAAgJQgy4CABqAQAeAAgJQgy4CABqAQAAAA==.Mytheas:BAAALgADCgkJFAAAAA==.',
['Mâ']='Mâxxémûss:BAAALgAECgEJAQAAAA==.',
['Mï']='Mïndthegåp:BAAALgADCgQJBAAAAA==.',
Na='Naann:BAAALgAECgEJAQAAAA==.Nagarickk:BAAALgAECgMJCwAAAA==.Narayeda:BAAALgADCgEJAQAAAA==.Naudamarth:BAAALgAECgYJBwAAAA==.',
Ne='Nerphette:BAAALgADCgEJAQAAAA==.Nerpho:BAAALgAECgQJCgAAAA==.Nerpthyr:BAAALgADCgEJAgAAAA==.Newwt:BAAALgAECgUJDwAAAA==.Neytiri:BAAALgADCgcJBwAAAA==.Nezzliok:BAAALgADCgEJAQAAAA==.',
Ni='Nightblazt:BAAALgADCgMJAwAAAA==.Ninjasaur:BAAALgADCgIJAgAAAA==.Nitalouise:BAAALgADCgYJBgAAAA==.',
No='Nokkohtak:BAAALgADCgEJAQAAAA==.Norros:BAAALgAECgYJCAAAAA==.Notåredneck:BAAALgAECgEJAQAAAA==.Novikane:BAAALgAECgMJBgAAAA==.',
Nt='Ntflxnchlidn:BAAALgADCgYJBgAAAA==.',
Nu='Nutswang:BAAALgAECgkJBQAAAA==.Nuvi:BAAALgAECgQJBQAAAA==.Nuvostaph:BAAALgAECgcJCQAAAA==.',
['Nö']='Nötgood:BAAALgAECgIJAwAAAA==.',
Oa='Oakshror:BAAALgAECgQJBgAAAA==.',
Oc='Ocyyn:BAAALgADCgMJAgAAAA==.',
Od='Odecias:BAAALgADCgcJDQAAAA==.',
Oj='Ojdajuiceman:BAAALgAECgcJAgAAAA==.',
Ol='Ollomer:BAAALgADCgQJBAABLgAECggJJwAQAKMiAA==.',
Om='Omegaheals:BAAALgAECgQJBwAAAA==.',
On='Onepoint:BAAALgAECgYJCgAAAA==.',
Or='Orcboken:BAAALgAECgUJDAAAAA==.Orionember:BAAALgADCgkJFAAAAA==.Orolen:BAAALgADCgEJAQAAAA==.Orothrim:BAAALgAECgMJAwAAAA==.',
Pa='Palpatîne:BAAALgAECgYJEAAAAA==.Palymaster:BAAALgAECgMJAwAAAA==.Pandaop:BAAALgADCgIJAwAAAA==.Pandapumper:BAAALgADCgcJCQAAAA==.Pandra:BAAALgADCgkJCQAAAA==.Papadots:BAAALgAECgQJBQAAAA==.Pato:BAAALgADCgUJBQAAAA==.Pavlowick:BAAALgADCgQJBQAAAA==.',
Pc='Pchien:BAAALgADCgMJAwAAAA==.',
Pe='Pemala:BAABLgAECn8fAAIgAAgJfSK/AADvAgAgAAgJfSK/AADvAgAAAA==.Perceus:BAAALgAECgYJDQAAAA==.Perky:BAAALgADCggJCAAAAA==.',
Ph='Phaith:BAEALgAECgQJBQAAAA==.Phatnips:BAABLgAECn8nAAMcAAkJSxARCADwAQAcAAkJSxARCADwAQAhAAEJAACUgAAOAAAAAA==.Phiisa:BAAALgAECgMJBgAAAA==.',
Pi='Pif:BAAALgAECgEJAQAAAA==.Pigeon:BAABLgAECn8eAAIgAAcJCxgcDAB9AQAgAAcJCxgcDAB9AQAAAA==.Pigeons:BAAALgADCgIJAwAAAA==.Pingu:BAAALgADCgEJAQABLgADCgMJAwADAAAAAA==.Pinknipplez:BAAALgAECgcJAgAAAA==.',
Pn='Pnuts:BAACLgAFFH8KAAMZAAQJag4mDwDdAAAZAAQJqAomDwDdAAANAAIJlRH1DQCOAAAuAAQKfyYABA0ACAllG9oXAB0CABkABwllGmgSACECAA0ACAkuGNoXAB0CAA4ABgnNBf0PAPcAAAAA.',
Po='Pokazul:BAABLgAECn8gAAIiAAkJYhQFCwBgAgAiAAkJYhQFCwBgAgAAAA==.Popedragon:BAAALgAECgIJAwAAAA==.Poshh:BAAALgAECgEJAQAAAA==.',
Pr='Prometheüs:BAAALgADCgEJAQAAAA==.Promodas:BAAALgAECgQJCAAAAA==.Proven:BAAALgAECgkJBwAAAA==.Prídé:BAAALgAECgYJCgABLgAFFAUJCgAYADsYAA==.',
Pu='Puffindaboof:BAAALgADCgIJAgAAAA==.Pumapuma:BAAALgAECgEJAgAAAA==.Punkz:BAABLgAECn8nAAQQAAgJoyJ9AAAzAwAQAAgJoyJ9AAAzAwAYAAIJPg9VSwCHAAAjAAMJ7wb8AgB0AAAAAA==.Purdyflap:BAAALgAECgQJCQABLgAFFAEJAQADAAAAAA==.Purplesocks:BAAALgAECgYJBgAAAA==.',
Qi='Qir:BAAALgADCgQJBAAAAA==.',
Qu='Quigzz:BAAALgAECgQJCwAAAA==.',
Ra='Rack:BAAALgAECgIJAgAAAA==.Raeincarnate:BAAALgADCgUJBQAAAA==.Raenarya:BAAALgAECgUJBwAAAA==.Raganarok:BAAALgADCgkJEgAAAA==.Rahja:BAAALgAECgUJDQAAAA==.Ramss:BAAALgAECgEJAQAAAA==.Ranch:BAAALgAECgMJBwAAAA==.',
Re='Reachy:BAABLgAECn8mAAMQAAgJSiUFAAAHAwAQAAgJSiUFAAAHAwAYAAYJZiJdSgBYAgAAAA==.Realtrendy:BAABLgAECn8UAAMPAAYJJxeQPwCmAQAPAAYJJxeQPwCmAQARAAMJaw4UKQCnAAAAAA==.Reaping:BAAALgADCgEJAQAAAA==.Reebs:BAAALgAECgcJAwAAAA==.Rellans:BAAALgADCgEJAQAAAA==.Resa:BAAALgAECgIJAgAAAA==.',
Rh='Rhomdogo:BAAALgAECgEJAgAAAA==.Rhomdos:BAAALgAECgEJAQAAAA==.',
Ri='Rieve:BAAALgAECgYJEgAAAA==.Ripdembunzqt:BAAALgADCgIJAgAAAA==.',
Ro='Rodanel:BAAALgAECgQJBQAAAA==.Rokenn:BAAALgADCgcJCAAAAA==.Ronoa:BAAALgADCgIJAgAAAA==.Rosaliie:BAAALgADCgUJBQAAAA==.',
['Rà']='Ràyliotta:BAAALgAECgIJAQAAAA==.',
['Rá']='Rácnorr:BAAALgADCgIJAgAAAA==.',
['Rô']='Rôbert:BAAALgADCgQJBQAAAA==.',
Sa='Saberyn:BAAALgAECgQJBAAAAA==.Saenya:BAABLgAECn8kAAMOAAgJqRtWDgCeAgAOAAgJqRtWDgCeAgANAAgJ/RPaAwAIAgAAAA==.Saeras:BAAALgADCgIJAgAAAA==.Saf:BAAALgADCgcJDAABLgAECgQJDAADAAAAAA==.Safyr:BAAALgAECgQJDAAAAA==.Saiama:BAAALgADCgYJBgAAAA==.Sanctis:BAAALgAECgYJCwAAAA==.Sants:BAAALgADCgIJAgAAAA==.Santuskie:BAAALgADCgcJBwAAAA==.Sappedflesh:BAAALgAECggJDgABLgAFFAUJEwATALMYAA==.Sapph:BAAALgAECgYJBgAAAA==.Saturos:BAAALgADCgIJAgAAAA==.Satìvex:BAABLgAECn8eAAIIAAkJ0RNuIABDAgAIAAkJ0RNuIABDAgAAAA==.',
Sc='Schaughn:BAABLgAECn8hAAISAAgJ9CCXAgAUAwASAAgJ9CCXAgAUAwAAAA==.Schvitz:BAAALgAECgYJCwAAAA==.',
Se='Searchman:BAAALgADCgQJBAAAAA==.Segagamecube:BAAALgAECgQJBAAAAA==.Selias:BAAALgADCgcJBwAAAA==.Selosona:BAAALgADCgEJAQAAAA==.Semaine:BAAALgADCgEJAQAAAA==.Semiricary:BAAALgADCgcJCgAAAA==.Senestia:BAAALgAECgEJAQAAAA==.Sephereth:BAAALgADCgQJBAABLgAECgcJEwADAAAAAA==.Sephyrøs:BAAALgADCgYJBgAAAA==.Seral:BAABLgAECn8lAAIBAAkJyRzZAACzAgABAAkJyRzZAACzAgAAAA==.Seraphies:BAAALgAECgYJDgAAAA==.Serena:BAAALgAECgYJEAAAAA==.Serengeti:BAAALgAECgMJBgAAAA==.Sevilon:BAAALgAECgYJEAAAAA==.',
Sh='Shabiyouxi:BAACLgAFFH8UAAMIAAYJdBzRAQCGAQAIAAUJfSLRAQCGAQAdAAQJYgiIGADKAAAuAAQKfycAAwgACQl8Iu4GACADAAgACAn2JO4GACADAB0ABQnyC7lXAOgAAAAA.Shaco:BAAALgADCgYJBgAAAA==.Shadowtrail:BAAALgAECgcJEAAAAA==.Shamanate:BAAALgADCgYJBgAAAA==.Sharrowkynn:BAAALgADCgEJAQAAAA==.Shawshanks:BAAALgADCgMJAwAAAA==.Sheeply:BAAALgAECgQJCAAAAA==.Sheezy:BAAALgADCgMJAwAAAA==.Shenzzo:BAAALgAECgYJEwAAAA==.Shiesti:BAAALgAECgEJAQAAAA==.Shiftry:BAAALgADCgEJAQAAAA==.Shifu:BAAALgAECggJCAAAAA==.Shivàh:BAAALgAECgYJBgABLgAFFAMJCAAHANkmAA==.Shoeknee:BAAALgAECgUJDQAAAA==.Shozus:BAABLgAECn8oAAIUAAkJvRgFAQB4AgAUAAkJvRgFAQB4AgAAAA==.',
Si='Sieuhunter:BAAALgADCgUJBQAAAA==.Sifalous:BAAALgAECgEJAQAAAA==.Sinruki:BAABLgAECn8dAAQOAAcJphrdGAAbAgAOAAcJphrdGAAbAgANAAYJgh2YJADDAQAZAAEJ9AtuWQAvAAAAAA==.Sizzlinghots:BAAALgAECgMJBQAAAA==.',
Sk='Skrat:BAAALgAECgYJBwAAAA==.',
Sl='Slackin:BAAALgADCgQJBAAAAA==.Slankie:BAABLgAECn8YAAIYAAcJhAyAKAAsAQAYAAcJhAyAKAAsAQAAAA==.Sleepymoon:BAAALgADCgUJBgAAAA==.Sluc:BAAALgAECgYJCgAAAA==.',
Sm='Smashcrack:BAAALgADCgQJBAAAAA==.Smittae:BAAALgADCgkJDgAAAA==.Smolgrog:BAAALgAECgQJBwAAAA==.Smolwang:BAAALgADCgUJBQAAAA==.Smutysluty:BAAALgADCgEJAQAAAA==.',
Sn='Snoogles:BAAALgADCgUJBQAAAA==.Snugglebutts:BAAALgAECgUJBQAAAA==.',
So='Soar:BAAALgAECgMJAwABLgAFFAYJEwAYACgeAA==.Sogak:BAAALgAECgMJAgAAAA==.Solitude:BAAALgADCgYJBgAAAA==.Solo:BAAALgAECgcJCAAAAA==.Somedamnmage:BAAALgAECgEJBAAAAA==.Soulleo:BAAALgAECgEJAQAAAA==.Soundar:BAAALgADCgQJBAAAAA==.',
Sp='Spikekings:BAAALgADCgMJAwAAAA==.Spinifex:BAAALgADCgYJBgAAAA==.Spâdez:BAAALgADCgYJCAAAAA==.',
St='Staggerdaddy:BAAALgAECgYJCAAAAA==.Staleria:BAAALgADCggJDAAAAA==.Stankytotems:BAAALgAECgYJBgAAAA==.Steelscrotum:BAAALgADCgUJCgAAAA==.Stensoul:BAAALgADCgEJAQAAAA==.Stinkcheese:BAAALgAECgQJBAAAAA==.Stinkytickle:BAAALgADCgcJBwAAAA==.Stkk:BAAALgAECgIJAgABLgAECgkJCQADAAAAAA==.Stolz:BAAALgAECgIJAwAAAA==.Stompez:BAAALgADCgYJDAAAAA==.Straightrash:BAAALgAECgMJAwAAAA==.Stumpedtotem:BAAALgADCgYJBgAAAA==.Stärrdust:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Stårrfall:BAAALgAECgEJAQAAAA==.Stèllå:BAAALgADCggJDAAAAA==.',
Su='Succyoubus:BAAALgAECgEJAQAAAA==.Suggon:BAAALgAECgYJEgAAAA==.Sukkahpunch:BAAALgADCgcJEgAAAA==.Supersk:BAAALgAECgMJAwAAAA==.Survivaldes:BAAALgADCgUJBwABLgAECgQJBAADAAAAAA==.',
Sw='Sweepingwind:BAAALgAECgEJAQAAAA==.',
['Sà']='Sàviorself:BAAALgADCgcJEAAAAA==.',
['Sâ']='Sâphirra:BAAALgAECgEJAQAAAA==.Sââraus:BAAALgAECgcJEQAAAA==.',
['Sè']='Sènsational:BAAALgAECgEJAQABLgAECgYJJwAZAM0lAA==.',
['Sî']='Sîeg:BAAALgAECgQJBwAAAA==.',
Ta='Taeladoric:BAAALgAECgQJCQAAAA==.Talanath:BAAALgAECgUJDwAAAA==.Taslin:BAAALgAECgQJBQAAAA==.Tazoo:BAAALgAECgYJDwAAAA==.',
Te='Technine:BAAALgADCgYJBwAAAA==.Tehhahn:BAAALgADCgMJAwAAAA==.Tehzoo:BAAALgAECgEJAQAAAA==.Teliandra:BAAALgAECgQJBAAAAA==.Telps:BAAALgAECgQJBQAAAA==.Tenkry:BAAALgAECggJEwAAAA==.Terintio:BAAALgAECgYJEAAAAA==.Teronas:BAAALgADCgQJBAAAAA==.',
Th='Thadeouss:BAABLgAECn8fAAINAAkJhh9sBwDVAgANAAkJhh9sBwDVAgAAAA==.Thanarl:BAAALgAECgQJBQAAAA==.Thebes:BAAALgAECgUJCQAAAA==.Thebigboom:BAAALgAECgQJBwABLgAECgcJFwAHALEfAA==.Thedemon:BAAALgAECgEJAQAAAA==.Thegarantine:BAAALgADCgUJBQAAAA==.Thelordmunzo:BAAALgAECgYJDQAAAA==.Theotokos:BAAALgADCgQJBwAAAA==.Therocker:BAABLgAECn8UAAIgAAYJmBcUQQB0AQAgAAYJmBcUQQB0AQAAAA==.Thetrooper:BAAALgAECgEJAQABLgAECgQJBAADAAAAAA==.Thorion:BAAALgAECgMJAwAAAA==.Threeonefour:BAAALgAECgQJBAAAAA==.Threnni:BAAALgAECgMJAwAAAA==.Thrumgar:BAAALgADCgkJEQAAAA==.Thunderson:BAAALgAECgUJCQAAAA==.Thynner:BAAALgAECgEJAQAAAA==.',
Ti='Tichalock:BAAALgAECgEJAQAAAA==.Tichee:BAAALgADCgMJAwABLgAECgEJAQADAAAAAA==.Tigerchimon:BAABLgAECn8aAAMHAAcJmgpPRQAtAQAHAAcJmgpPRQAtAQAVAAEJyQO/hwAoAAAAAA==.Tilbery:BAABLgAECn8jAAIYAAkJzCBGIADzAgAYAAkJzCBGIADzAgAAAA==.Timmothy:BAAALgADCgUJBQABLgAECgcJEwADAAAAAA==.Timmywumpus:BAAALgADCgcJDgAAAA==.Tinnus:BAAALgADCggJDQAAAA==.Tinyburn:BAAALgADCgUJBgAAAA==.Tinywand:BAAALgAECgQJBAAAAA==.',
Tj='Tjorn:BAAALgAECgYJBgAAAA==.',
To='Todas:BAAALgADCgQJBAABLgADCgUJBgADAAAAAA==.Topenga:BAAALgAFFAEJAQAAAA==.Torathar:BAAALgADCgUJBQAAAA==.',
Tr='Treelimbs:BAABLgAECn8nAAIfAAkJriE0AADpAgAfAAkJriE0AADpAgAAAA==.Triggerhappi:BAAALgADCgEJAQAAAA==.Trizzoy:BAAALgADCgIJAgAAAA==.',
Tu='Tusutu:BAAALgADCgUJBQAAAA==.',
Ty='Tylanar:BAAALgADCgQJBAABLgAECgYJCAADAAAAAA==.Typroxnix:BAAALgAECgQJCAAAAA==.',
['Tô']='Tôrô:BAAALgAECgYJEgAAAA==.',
Ul='Ulitima:BAAALgADCgYJBgAAAA==.',
Un='Unconvicted:BAAALgADCgYJCgAAAA==.Untouchablè:BAAALgAECgQJCQABLgAECgcJGQAJAL8fAA==.Untöuchable:BAABLgAECn8ZAAMJAAcJvx/zTAD8AQAJAAYJeh/zTAD8AQAgAAcJthIPCADGAQAAAA==.',
Up='Upham:BAAALgAECgMJAwAAAA==.',
Ur='Uraldum:BAAALgAECgEJAQAAAA==.',
Va='Vaelraven:BAAALgADCgYJBwAAAA==.Valoel:BAAALgADCgMJCAAAAA==.Valvier:BAAALgAECgMJBQAAAA==.Vapélord:BAAALgAECgQJBwAAAA==.Variline:BAAALgADCgUJBQAAAA==.Varnolan:BAAALgADCgEJAQAAAA==.',
Ve='Velkaris:BAAALgADCgMJAwAAAA==.Venator:BAAALgADCgQJBAAAAA==.Vendatha:BAABLgAECn8fAAIJAAYJWhupYgC9AQAJAAYJWhupYgC9AQAAAA==.Verdtual:BAAALgAECgEJAQAAAA==.Verxl:BAAALgAECgMJBwAAAA==.Veyvid:BAAALgADCgcJCAAAAA==.',
Vi='Visarch:BAAALgADCgYJEAABLgAECgYJHwAJAFobAA==.',
Vo='Voidpunch:BAABLgAECn8gAAIHAAgJvhNoIgDvAQAHAAgJvhNoIgDvAQAAAA==.Voltlustamp:BAAALgAECgYJBgAAAA==.Volumes:BAAALgAECgQJCAABLgADCgcJDwADAAAAAA==.Volumez:BAAALgAECgYJDAABLgADCgcJDwADAAAAAA==.Volund:BAABLgAECn8aAAIkAAcJ7wUeFwBQAQAkAAcJ7wUeFwBQAQAAAA==.',
Vy='Vyndron:BAAALgADCgcJCwAAAA==.Vyorinye:BAAALgAECgIJAwAAAA==.Vyz:BAAALgAFFAIJAgABLgAFFAUJDQAgACoTAA==.',
['Vè']='Vèrtèn:BAABLgAECn8bAAIPAAYJOA8UEwAJAQAPAAYJOA8UEwAJAQAAAA==.',
['Ví']='Víðarr:BAAALgADCgcJBwAAAA==.',
Wa='Wachulu:BAAALgAECgcJDQAAAA==.Waitingforu:BAAALgAECgcJEAABLgAECgYJCAADAAAAAA==.Warming:BAAALgAECgEJAQAAAA==.Warrlord:BAAALgAECgIJAgAAAA==.Warwalkerz:BAAALgAECgQJBAAAAA==.Waterfilter:BAABLgAECn8XAAMcAAgJTRUADAC6AQAcAAgJlRQADAC6AQAhAAYJohAsIwA+AQAAAA==.Watermalorne:BAAALgAECgMJBAAAAA==.',
Wi='Wigglës:BAAALgADCgYJBgAAAA==.Wiggumz:BAAALgADCgYJBgAAAA==.Winnototem:BAABLgAECn8nAAMlAAkJ6hUIGQBOAgAlAAkJ6hUIGQBOAgAmAAMJJRdOFADZAAAAAA==.Wisakedjak:BAAALgAECgUJBwAAAA==.',
Wu='Wutpuddle:BAAALgAECgYJCwAAAA==.',
['Wì']='Wìld:BAAALgADCgYJBgAAAA==.',
Xa='Xamnd:BAAALgAECgUJCQABLgAECggJGgAKANIkAA==.',
Xe='Xereph:BAAALgADCgEJAQAAAA==.',
Xg='Xguard:BAAALgAECgIJAgAAAA==.',
Xi='Xiaoshui:BAAALgADCgEJAQAAAA==.',
Xj='Xjangor:BAAALgADCgEJAQAAAA==.',
Xu='Xugos:BAABLgAECn8TAAIcAAYJMSB4DQCpAQAcAAYJMSB4DQCpAQAAAA==.',
Xy='Xyno:BAABLgAECn8cAAQWAAkJahMzBgD6AQAWAAcJGRczBgD6AQAcAAgJLQt2DgCfAQAhAAEJTgnDdAAwAAAAAA==.',
Ya='Yatun:BAAALgADCgEJAQAAAA==.',
Ye='Yeeargh:BAAALgADCgUJBQABLgAFFAMJBgAOAMoTAA==.',
Yi='Yiggdigg:BAAALgADCgIJAgAAAA==.Yinea:BAAALgADCgUJBQAAAA==.',
Yo='Yooper:BAAALgAECgQJDQAAAA==.',
Yu='Yummymango:BAAALgAECgMJAwABLgAECgcJIgAYAFYjAA==.Yunaga:BAAALgADCgYJBgABLgAECgYJDwADAAAAAA==.',
Yy='Yynertia:BAAALgADCgEJAgAAAA==.',
Za='Zadanthra:BAAALgADCgYJEQAAAA==.',
Zd='Zdod:BAAALgAECgEJAQAAAA==.',
Ze='Zeenie:BAAALgAFFAEJAQAAAA==.Zeigheim:BAAALgAECggJDQAAAA==.Zektra:BAAALgAECgEJAQAAAA==.Zendrost:BAABLgAECn8nAAMYAAkJ7hLgCwDyAQAYAAkJ7hLgCwDyAQAjAAIJTgyvDABhAAAAAA==.Zenjamin:BAAALgAECgYJCwAAAA==.Zeonic:BAAALgAECgQJBQAAAA==.',
Zi='Zigurous:BAABLgAECn8WAAIIAAcJ5SWqBQAYAgAIAAcJ5SWqBQAYAgAAAA==.Zimmyy:BAAALgAECgQJBwAAAA==.',
Zl='Zloma:BAAALgAECgUJBgAAAA==.',
Zm='Zmax:BAABLgAECn8tAAIKAAgJXiMBDAAhAwAKAAgJXiMBDAAhAwAAAA==.',
Zo='Zoerik:BAABLgAECn8nAAIZAAkJRBh+AgA6AgAZAAkJRBh+AgA6AgAAAA==.Zoogawaka:BAAALgADCgcJBwAAAA==.Zotoperen:BAAALgAECgIJAwABLgAECgkJIwABAPodAA==.',
Zu='Zukbang:BAAALgAECgQJAwAAAA==.Zulazlok:BAAALgADCgcJBwAAAA==.Zuperuber:BAAALgADCgYJBgAAAA==.Zuzo:BAAALgAECgEJAQAAAA==.',
Zy='Zylergy:BAAALgAECgEJAQAAAA==.',
['Zù']='Zùl:BAAALgADCgIJAgAAAA==.',
['Àm']='Àmunra:BAAALgAECgYJDgAAAA==.',
['Àn']='Àncksunamun:BAAALgAECgYJDQAAAA==.Àndrew:BAAALgADCgMJAwABLgADCgYJDQADAAAAAA==.',
['Ãn']='Ãngrymeatbal:BAAALgAECgcJDgAAAA==.',
['Ðe']='Ðeath:BAAALgADCgcJCQAAAA==.',
['ße']='ßeel:BAABLgAECn8ZAAMKAAgJxg8UFABdAQAKAAgJxg8UFABdAQAbAAEJAAAmfwASAAAAAA==.',
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

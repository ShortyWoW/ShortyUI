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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','DeathKnight-Unholy','Shaman-Elemental','Evoker-Preservation','Evoker-Devastation','Warrior-Arms','Shaman-Enhancement','Druid-Guardian','Druid-Feral','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Rogue-Subtlety','DemonHunter-Vengeance','Warrior-Fury','Priest-Shadow','Priest-Discipline','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Evoker-Augmentation','Warlock-Affliction','Mage-Arcane','Mage-Frost','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaluah:BAAALgAECgQJBAAAAA==.',
Ab='Abc:BAAALgADCgcJIAABLgAECggJIAABAFcTAA==.',
Ac='Accessdeez:BAAALgAECgUJBQAAAA==.Acmis:BAAALgAECgYJEwAAAA==.Acp:BAABLgAECn8YAAMCAAcJiRvtKQAOAgACAAcJsxrtKQAOAgADAAMJPQshbgCGAAAAAA==.',
Ad='Adomangma:BAAALgADCgkJCgAAAA==.',
Ae='Aedryth:BAAALgAECgEJAgABLgAECgQJBwAEAAAAAA==.Aeelan:BAAALgADCgMJAgAAAA==.Aeshael:BAAALgAECgMJBQAAAA==.Aethrys:BAAALgAECgIJAQABLgAECgQJBwAEAAAAAA==.',
Ai='Ailardrion:BAAALgADCgUJBQAAAA==.Airrose:BAAALgADCgcJBwAAAA==.',
Ak='Akilah:BAAALgADCgEJAQABLgAECgYJDAAEAAAAAA==.Akumaho:BAABLgAECn8YAAMFAAgJMiBxDgAGAwAFAAgJMiBxDgAGAwAGAAEJXxLPcQA0AAAAAA==.Akurantirea:BAAALgAECgMJAwAAAA==.Akusephine:BAABLgAECn8VAAIHAAYJPRvEFABXAQAHAAYJPRvEFABXAQAAAA==.',
Al='Alayndia:BAAALgAECgQJBwAAAA==.Aldonya:BAAALgAECgQJBwAAAA==.Alexxia:BAAALgADCggJCgAAAA==.Allise:BAAALgAECgYJDgAAAA==.Alougim:BAAALgADCgYJBwAAAA==.Aluia:BAAALgADCgUJBQAAAA==.Alva:BAAALgAECgMJBQAAAA==.Alystraza:BAAALgADCgIJBAAAAA==.Aléthia:BAAALgAECgYJEAAAAA==.',
Am='Amkhara:BAAALgADCgYJCQAAAA==.',
An='Anathemá:BAAALgAECgYJCQAAAA==.Anduriel:BAAALgADCgEJAQAAAA==.Ange:BAAALgAECgYJCQAAAA==.Anjo:BAAALgADCgEJAQAAAA==.Ankleblaster:BAAALgAECgEJAQABLgAECgcJHgAIAOwjAA==.Antigen:BAAALgAECgIJAgAAAA==.',
Ap='Apawcalypse:BAAALgAECgEJAQAAAA==.',
Ar='Arak:BAAALgAECgEJAgAAAA==.Araoppai:BAAALgAECgcJEQAAAA==.Arfur:BAAALgADCgUJBQAAAA==.Arianndda:BAABLgAECn8WAAIJAAgJpQfyNgBhAQAJAAgJpQfyNgBhAQAAAA==.Arin:BAABLgAECn8mAAIKAAgJXyMWAgCkAgAKAAgJXyMWAgCkAgAAAA==.Artleandra:BAAALgAECgYJDQAAAA==.',
As='Asha:BAABLgAECn8UAAILAAYJTSNRJADuAQALAAYJTSNRJADuAQAAAA==.Ashwood:BAAALgAECgMJAwAAAA==.Asili:BAAALgADCgcJDAAAAA==.Askor:BAAALgAECgEJAQAAAA==.Assurance:BAAALgADCgYJBgAAAA==.Astela:BAABLgAECn8VAAIGAAYJFBZOBAAVAQAGAAYJFBZOBAAVAQAAAA==.',
At='Atraxa:BAAALgADCgEJAQAAAA==.Atulkaji:BAAALgADCgcJBwAAAA==.',
Au='Auraia:BAAALgAECgQJBQAAAA==.Autumn:BAAALgAECgMJBQAAAA==.',
Av='Avan:BAAALgADCgcJBwAAAA==.Avatan:BAAALgAECgcJEgAAAA==.Avecrusade:BAAALgAECgcJBwAAAA==.Avedeath:BAAALgAECgQJBgAAAA==.Averlis:BAAALgAECgYJEwAAAA==.',
Aw='Aweburn:BAAALgAFFAEJAQAAAA==.',
Az='Azenezin:BAAALgAECgEJAQAAAA==.Azulena:BAAALgADCgcJBwAAAA==.',
Ba='Backpack:BAAALgAECgcJEAAAAA==.Badderdragon:BAABLgAECn8pAAMMAAgJ6CGGAADZAgAMAAgJ6CGGAADZAgANAAEJ5ALJRAAjAAAAAA==.Badmrmittens:BAAALgAECgcJCgAAAA==.Badmuffin:BAAALgAECgYJEwAAAA==.Balamuth:BAAALgAECgEJAQAAAA==.Balzarion:BAAALgAECgQJBgAAAA==.Bandemicc:BAABLgAECn8gAAIKAAgJEx7JHQDOAgAKAAgJEx7JHQDOAgAAAA==.Bandrui:BAAALgADCgEJAgAAAA==.Banru:BAABLgAECn8gAAIOAAgJjhTiAgCcAQAOAAgJjhTiAgCcAQAAAA==.Barnaclepan:BAAALgADCgYJCQAAAA==.',
Be='Bearlygrillz:BAAALgAECgYJEAAAAA==.Bearontoe:BAAALgADCggJCAAAAA==.Bedtimez:BAAALgADCgMJAwAAAA==.Beelzabub:BAAALgADCggJDgAAAA==.Berkstein:BAAALgAECgYJEwAAAA==.',
Bi='Biggisnicker:BAABLgAECn8gAAIFAAgJiBtKJgB5AgAFAAgJiBtKJgB5AgAAAA==.Bigin:BAAALgAECggJEwAAAA==.Bigspriesty:BAAALgAECgQJBAAAAA==.Billhilly:BAAALgADCgIJAgAAAA==.Billyblanks:BAAALgAECgYJEwAAAA==.Bimbom:BAABLgAECn8WAAIPAAYJ6R91CQA/AgAPAAYJ6R91CQA/AgAAAA==.Biophysics:BAABLgAECn8ZAAQQAAcJGRs7CQAQAgAQAAcJGRs7CQAQAgARAAMJ6A4qJgCgAAASAAIJMhElagB4AAAAAA==.',
Bl='Blackdoom:BAAALgAECgQJBAAAAA==.Bladestein:BAAALgAECgMJAwAAAA==.Blightstone:BAAALgADCgcJBwAAAA==.Bloodemperor:BAAALgAECgMJAwAAAA==.Bluemountain:BAAALgADCgYJBgAAAA==.',
Bo='Boodylicious:BAAALgADCgcJBwAAAA==.Booshh:BAAALgAECgIJAgAAAA==.Boshi:BAAALgADCgYJCQAAAA==.',
Br='Brahmin:BAAALgADCgcJDQAAAA==.Brassticus:BAABLgAECn8dAAITAAgJ+h+ACwDHAgATAAgJ+h+ACwDHAgAAAA==.Breanan:BAAALgAECgMJBAABLgAECgQJBwAEAAAAAA==.Brew:BAAALgADCgcJCgAAAA==.Brewsader:BAAALgADCgMJAwABLgAECgcJHgAIAOwjAA==.Brise:BAAALgAECgYJDwAAAA==.Brucewee:BAAALgADCgIJAgABLgAECgUJBQAEAAAAAA==.',
Bu='Bubblemelons:BAAALgAECgcJEQAAAA==.Buddhamonk:BAAALgADCgcJCgAAAA==.Buddhi:BAABLgAECn8UAAQBAAgJDSBrDAC3AgABAAgJDSBrDAC3AgAUAAIJ+B5+OwCnAAAVAAEJ1AbMEwAqAAAAAA==.Buddhïst:BAAALgAECgMJAwAAAA==.Burlan:BAAALgADCgIJAgAAAA==.Burrhas:BAAALgADCgQJBAAAAA==.Buzzbolt:BAAALgADCgEJAQAAAA==.',
Bw='Bwonsally:BAAALgADCgcJCgAAAA==.',
Ca='Cacashosho:BAAALgAECgcJDwAAAA==.Cahlamity:BAAALgADCgkJHwABLgADCgcJBwAEAAAAAA==.Cahlcifer:BAABLgAECn8eAAIMAAgJDxeMEAAyAgAMAAgJDxeMEAAyAgABLgADCgcJBwAEAAAAAA==.Cahlm:BAAALgADCgcJBwAAAA==.Caity:BAAALgADCgEJAQAAAA==.Cakke:BAAALgADCgEJAQAAAA==.Calamy:BAAALgADCgcJDQAAAA==.Candre:BAABLgAECn8eAAIVAAcJNx4MCQBFAgAVAAcJNx4MCQBFAgAAAA==.Candyears:BAAALgADCgYJBgAAAA==.Capii:BAAALgAECgYJBgAAAA==.Capristal:BAAALgADCgMJAwABLgAECgYJBgAEAAAAAA==.Caraxxes:BAAALgADCgUJBQAAAA==.Cardiac:BAAALgADCggJDAAAAA==.Cardora:BAAALgAECgEJAQAAAA==.Carrian:BAAALgADCgYJBgAAAA==.Cassielia:BAABLgAECn8ZAAIIAAcJ2RStOgC6AQAIAAcJ2RStOgC6AQAAAA==.Catmint:BAAALgAECgcJDgAAAA==.',
Ce='Ceb:BAAALgAECgMJAwAAAA==.',
Ch='Chariot:BAAALgAECgQJBAAAAA==.Charkycc:BAAALgAECgQJBAAAAA==.Chay:BAABLgAECn8fAAMFAAgJixZ3DQCpAQAFAAcJlxh3DQCpAQAGAAIJQwpiUgB3AAAAAA==.Chaylin:BAAALgADCgMJBAAAAA==.Chel:BAAALgAFFAIJAgAAAA==.Chiharu:BAAALgADCgUJBAAAAA==.Chiji:BAAALgAECgUJBQAAAA==.Chillen:BAAALgAECgYJDwAAAA==.Chivo:BAAALgAECgYJCQAAAA==.Chopu:BAAALgAECgYJDQAAAA==.Chrystabella:BAAALgADCgQJBAAAAA==.Chyna:BAAALgAECgYJBgAAAA==.',
Ci='Ciaani:BAABLgAECn8VAAMVAAgJch2xAQAFAgAVAAgJch2xAQAFAgABAAMJHghyfQCEAAAAAA==.Cibø:BAAALgAECgQJCgAAAA==.Cinnacism:BAAALgADCggJCAAAAA==.',
Cl='Claymonic:BAAALgAECgcJCgAAAA==.Cleric:BAAALgADCgkJDwABLgAECgYJBgAEAAAAAA==.Clip:BAAALgADCgcJBwABLgAECggJFAAWAOwfAA==.Clõud:BAAALgADCgYJDwAAAA==.',
Co='Cococolalaw:BAAALgADCgEJAQAAAA==.Comah:BAAALgADCgcJBwABLgAECgYJEQAEAAAAAA==.Conc:BAAALgADCgEJAQAAAA==.Coresh:BAAALgADCgYJCQAAAA==.Corppor:BAAALgADCgIJAgAAAA==.',
Cp='Cptkush:BAABLgAECn8nAAIUAAgJ/B2HMwBUAgAUAAgJ/B2HMwBUAgAAAA==.',
Cr='Crankash:BAAALgADCgEJAQAAAA==.Crazylikafox:BAAALgAECgkJCwAAAA==.Crazynip:BAABLgAECn8WAAIBAAcJVB8ZBgD3AQABAAcJVB8ZBgD3AQAAAA==.Crickit:BAAALgAECgYJEQAAAA==.Crickét:BAAALgAECgEJAQABLgAECgYJEQAEAAAAAA==.Crickêt:BAAALgADCgEJAQABLgAECgYJEQAEAAAAAA==.Crickët:BAAALgAECgEJAwABLgAECgYJEQAEAAAAAA==.Crikit:BAAALgAECgEJAwABLgAECgYJEQAEAAAAAA==.Crrioth:BAABLgAECn8fAAIXAAgJJhfoBgAfAgAXAAgJJhfoBgAfAgAAAA==.Crypticál:BAAALgADCgcJCgAAAA==.',
Cu='Cubanito:BAAALgADCgIJAgAAAA==.Cubmyrotch:BAABLgAECn8XAAIQAAgJDiCrAwDOAgAQAAgJDiCrAwDOAgAAAA==.Cuiscuis:BAAALgAECgYJBgAAAA==.Cujo:BAABLgAECn8cAAILAAgJ7RbxBgCZAQALAAgJ7RbxBgCZAQAAAA==.Curiousgeorg:BAAALgAECgIJAgAAAA==.',
Cy='Cyanidesun:BAABLgAECn8VAAMBAAcJKwTdGQCrAAABAAcJKwTdGQCrAAAUAAEJXQd+YQAxAAAAAA==.Cybre:BAAALgAECgQJCAAAAA==.Cyndil:BAAALgAECgYJDwAAAA==.Cyswarf:BAAALgADCgIJAgAAAA==.',
['Cä']='Cästiel:BAAALgAECgUJCAAAAA==.',
['Cø']='Cørgi:BAABLgAECn8UAAIKAAYJJR4VFABxAQAKAAYJJR4VFABxAQAAAA==.',
Da='Daddey:BAAALgADCgEJAQABLgADCgcJBwAEAAAAAA==.Daesyn:BAAALgADCgMJAwAAAA==.Daleus:BAABLgAECn8eAAIYAAcJLRQrCwBuAQAYAAcJLRQrCwBuAQAAAA==.Dalgn:BAAALgAECgYJBgAAAA==.Dallei:BAAALgAECgYJCwAAAA==.Darcane:BAABLgAECn8pAAMGAAgJwRPvCwADAgAGAAgJwRPvCwADAgAFAAQJogTsMwCxAAAAAA==.Darctanian:BAAALgAECgQJBQAAAA==.Darkchaos:BAAALgADCgcJBwAAAA==.Darktitomonk:BAAALgAECgEJAQAAAA==.Darkvayne:BAAALgAECgcJDQAAAA==.Darkzulu:BAAALgADCgYJBAAAAA==.Dathrel:BAAALgADCggJIAAAAA==.Dawnfather:BAAALgADCgkJFAAAAA==.',
De='Deceiver:BAABLgAECn8UAAIUAAcJMRH6awCmAQAUAAcJMRH6awCmAQAAAA==.Deeanna:BAAALgAECgUJDwAAAA==.Deemanhunter:BAAALgADCgEJAQAAAA==.Def:BAAALgAECgYJDAAAAA==.Dek:BAABLgAECn8pAAMZAAgJRyKrBwAMAwAZAAgJRyKrBwAMAwAaAAgJ7hqtDQBfAgAAAA==.Deleitlama:BAAALgADCgkJCgAAAA==.Delisius:BAAALgAECgEJAQAAAA==.Demonhellish:BAAALgAECgUJCwAAAA==.Demonnova:BAABLgAFFH8HAAIHAAUJ/wynDwDbAAAHAAUJ/wynDwDbAAAAAA==.Denary:BAAALgAECgYJDAAAAA==.Dessertname:BAAALgAECggJCQABLgAECggJHwAHAIIfAA==.Devinity:BAAALgAECgMJAwAAAA==.Dezsp:BAACLgAFFH8LAAIZAAQJSx46AQBzAQAZAAQJSx46AQBzAQAuAAQKfyUAAhkACAkcJacEAEkDABkACAkcJacEAEkDAAAA.',
Dg='Dghunter:BAABLgAECn8fAAMCAAgJbgQRJQDbAAACAAgJbgQRJQDbAAADAAUJ+QBKfABTAAAAAA==.',
Dh='Dhrat:BAABLgAECn8ZAAIbAAcJzRBeBgBTAQAbAAcJzRBeBgBTAQAAAA==.',
Di='Diarana:BAAALgAECgUJCgAAAA==.Diggus:BAAALgADCgIJAgAAAA==.Dimsum:BAAALgAECgcJDgABLgAECgcJFAAcAPkQAA==.Dippÿ:BAAALgADCgMJAwAAAA==.',
Do='Docsored:BAAALgAECgUJCAAAAA==.Dovul:BAAALgADCgcJDAAAAA==.',
Dr='Dragn:BAAALgAECgYJEAAAAA==.Dragnalus:BAAALgAECgYJCQAAAA==.Dragnas:BAABLgAECn8dAAIdAAgJoxzzCACPAgAdAAgJoxzzCACPAgAAAA==.Dragniperake:BAABLgAECn8cAAIBAAcJXRvOHQAoAgABAAcJXRvOHQAoAgAAAA==.Dragnspawn:BAAALgADCgQJBAAAAA==.Dragondees:BAAALgADCgEJAQABLgAECggJKQAZAEciAA==.Dragonflare:BAAALgADCgMJAwAAAA==.Draxonic:BAAALgADCgEJAQAAAA==.Drdots:BAABLgAECn8fAAIFAAgJDhpfCQDbAQAFAAgJDhpfCQDbAQAAAA==.Dreadnaunt:BAAALgAECgYJEgAAAA==.Drewed:BAABLgAECn8XAAIIAAYJJhS6TABxAQAIAAYJJhS6TABxAQAAAA==.Drugral:BAACLgAFFH8FAAIKAAIJ/RmYFwCqAAAKAAIJ/RmYFwCqAAAuAAQKfykAAgoACAnaIqsCAIgCAAoACAnaIqsCAIgCAAAA.Druidspider:BAAALgAECgIJAgAAAA==.Drundar:BAAALgAECgQJBwAAAA==.Druíd:BAAALgAECgYJEwAAAA==.Dryad:BAABLgAECn8ZAAIIAAcJWQbmbgAIAQAIAAcJWQbmbgAIAQAAAA==.',
Du='Dugronn:BAABLgAECn8fAAIdAAgJXxwbAgALAgAdAAgJXxwbAgALAgAAAA==.',
Dw='Dwarfvadar:BAAALgAECgcJDwAAAA==.',
['Dî']='Dîabló:BAAALgAECgMJAwAAAA==.',
Ea='Eadric:BAABLgAECn8aAAIUAAcJ0xo+FQB3AQAUAAcJ0xo+FQB3AQAAAA==.',
Eg='Eggfupunch:BAAALgAECgQJCQAAAA==.Eggrow:BAAALgADCggJEwAAAA==.',
El='Elanthemage:BAAALgAECgYJEwAAAA==.Eleison:BAACLgAFFH8PAAIZAAUJqx2cAgDQAQAZAAUJqx2cAgDQAQAuAAQKfxwAAhkACAnKJHoFADgDABkACAnKJHoFADgDAAAA.Ellesperis:BAAALgAECgYJEAAAAA==.Ellron:BAAALgADCgcJDAAAAA==.Ellumon:BAABLgAECn8gAAIeAAgJCyXfAgBVAwAeAAgJCyXfAgBVAwAAAA==.',
En='Enazicus:BAAALgAECgEJAQABLgAFFAUJBwAHAP8MAA==.Enkï:BAAALgAECgUJBQAAAA==.',
Eo='Eotteoke:BAABLgAECn8eAAMIAAcJ7COCEwCZAgAIAAcJ7COCEwCZAgASAAIJJxZKaACAAAAAAA==.',
Ep='Epicwar:BAAALgADCgQJBAAAAA==.',
Er='Eragôn:BAAALgAECgYJEQAAAA==.Erinyes:BAABLgAECn8WAAIfAAYJ1wSmGwAZAQAfAAYJ1wSmGwAZAQAAAA==.',
Es='Estee:BAAALgAECgcJDwAAAA==.',
Ev='Evoked:BAABLgAECn8WAAMMAAgJIwGJCQDHAAAMAAgJIwGJCQDHAAAgAAYJ6QC+UwB3AAAAAA==.',
Ex='Exarkune:BAAALgADCgMJAwAAAA==.Executioner:BAAALgAECgQJBAAAAA==.',
Ez='Ezreth:BAAALgAECgEJAQAAAA==.Ezuri:BAAALgADCgQJBAAAAA==.',
Fa='Faoladhconri:BAAALgAECgMJAwAAAA==.Fatfish:BAAALgAECgYJCgAAAA==.Fatty:BAABLgAECn8eAAIeAAcJeh01BAD3AQAeAAcJeh01BAD3AQABLgAECggJIAABAFcTAA==.',
Fe='Felpine:BAAALgAECgcJAQAAAA==.Feul:BAABLgAECn8ZAAMTAAgJFR/uCADnAgATAAgJFR/uCADnAgALAAMJQxTBYQC8AAAAAA==.Feuldrasil:BAAALgADCgYJBgAAAA==.Feyded:BAAALgAECgYJEwAAAA==.Feylis:BAAALgADCgUJBgABLgAECgYJFQAGABQWAA==.',
Fi='Fiasko:BAABLgAECn8eAAIYAAgJRxuMAgA3AgAYAAgJRxuMAgA3AgAAAA==.Fiir:BAAALgADCgkJFAAAAA==.Finebaum:BAAALgAECgQJBAAAAA==.Firedup:BAAALgADCgcJDgAAAA==.Firehawk:BAAALgADCgUJBQAAAA==.',
Fl='Flarefstrot:BAAALgAECgQJCQAAAA==.Flippÿ:BAAALgAECgEJAQAAAA==.Flotila:BAAALgADCgQJBAAAAA==.Fluffythecup:BAAALgAECgYJEwAAAA==.',
Fo='Forgedflame:BAAALgAECggJCgAAAA==.Formidonis:BAABLgAECn8gAAMFAAgJSyGVEAD2AgAFAAgJSyGVEAD2AgAhAAMJgSIDFgDTAAAAAA==.',
Fr='Fraudcheese:BAAALgAECgEJAQABLgAECgUJCgAEAAAAAA==.Frostyna:BAAALgAECgYJBgAAAA==.',
Fu='Fulgur:BAAALgAECgYJEAAAAA==.Funshine:BAAALgADCgcJBwAAAA==.Funsizegurly:BAABLgAECn8eAAMiAAcJNxdkBAAHAgAiAAcJNxdkBAAHAgAjAAYJRgdsNAD2AAAAAA==.Furyfighter:BAAALgADCgMJAwAAAA==.',
['Fì']='Fìzban:BAABLgAECn8cAAMMAAgJzhNkAwC0AQAMAAgJzhNkAwC0AQANAAYJqA7NHQA/AQAAAA==.',
Ga='Galihath:BAAALgAECgMJAwAAAA==.Gallasdk:BAAALgADCgMJAwAAAA==.Gallypotter:BAACLgAFFH8FAAICAAIJrw+aGQCgAAACAAIJrw+aGQCgAAAuAAQKfx8AAgIABwmJGzoiADgCAAIABwmJGzoiADgCAAAA.Gander:BAAALgADCggJEQAAAA==.Garopp:BAAALgADCgEJAQAAAA==.Garygabagool:BAABLgAECn8pAAIPAAgJyyNrAACiAgAPAAgJyyNrAACiAgAAAA==.Gawdspet:BAAALgAECgcJDQAAAA==.',
Ge='Geobeanz:BAAALgAECgYJDgAAAA==.Geoffreey:BAAALgAECgYJEQAAAA==.',
Gl='Glyn:BAAALgAECgMJAwAAAA==.',
Gn='Gnatytoop:BAABLgAECn8eAAIYAAcJexXDCACUAQAYAAcJexXDCACUAQAAAA==.Gnawrly:BAAALgAECgcJCwAAAA==.Gneve:BAAALgAECgYJBgAAAA==.',
Go='Gogurt:BAAALgAECgYJDwAAAA==.Gotowork:BAABLgAECn8XAAMdAAgJgRpWDABHAgAdAAcJzB1WDABHAgAYAAEJuwaVsAAqAAAAAA==.Govrek:BAAALgAECgYJCwAAAA==.',
Gr='Greenguyman:BAABLgAECn8bAAIKAAgJfRvsMgBrAgAKAAgJfRvsMgBrAgAAAA==.Greenstone:BAAALgADCggJDQAAAA==.Grobyc:BAAALgADCgkJFwAAAA==.Groøt:BAABLgAECn8UAAMIAAYJtxp9QACgAQAIAAYJtxp9QACgAQARAAQJfBqpBABNAQAAAA==.Grïm:BAABLgAECn8gAAIjAAgJkBk+QQB1AgAjAAgJkBk+QQB1AgAAAA==.',
Gu='Guldanramsay:BAAALgAECgcJAQAAAA==.Guldont:BAAALgADCgYJCQAAAA==.Gunmetalgibz:BAAALgAECgcJAQAAAA==.Gunne:BAAALgADCgIJAwAAAA==.Gunsa:BAAALgADCgEJAQAAAA==.',
Ha='Hags:BAAALgAECgMJAwAAAA==.Halfblast:BAAALgADCgMJAwAAAA==.Halmi:BAAALgADCgMJAwABLgAFFAIJBQACAK8PAA==.Hankerchief:BAAALgADCgcJBwABLgAECggJIAAHACwYAA==.Hankering:BAABLgAECn8gAAQHAAgJLBioDQChAQAHAAgJ4BeoDQChAQAXAAMJkxYfHgCXAAAbAAEJmx0cbAA5AAAAAA==.Hankopher:BAAALgADCgMJAwABLgAECggJIAAHACwYAA==.Hankytanky:BAAALgADCgIJAgAAAA==.Hapi:BAAALgAECgUJCwAAAA==.Haptics:BAABLgAECn8UAAMWAAgJ7B/hFQBgAgAWAAgJLh/hFQBgAgAkAAQJCB4eEAAOAQAAAA==.Harmonix:BAAALgADCgUJBQABLgAECgYJEQAEAAAAAA==.Haruot:BAAALgADCgEJAQAAAA==.Hasbin:BAAALgAECgEJAQAAAA==.Hatsunari:BAAALgAECgIJAgAAAA==.Hawkelf:BAAALgADCgUJBQAAAA==.Hawkshot:BAAALgADCgYJBgAAAA==.',
He='Hecateis:BAAALgAECgQJBAAAAA==.Heenan:BAABLgAECn8bAAIYAAYJ5AYgFQDzAAAYAAYJ5AYgFQDzAAAAAA==.Hellere:BAAALgAECgIJAgABLgAECggJIAAHACwYAA==.Hempknight:BAAALgAECgcJCQAAAA==.Herukas:BAAALgAECgQJBwAAAA==.Heímdall:BAAALgADCgUJBQAAAA==.',
Hi='Hikons:BAAALgADCgEJAQABLgAECggJIAABAFcTAA==.Hironan:BAABLgAECn8gAAIlAAgJORjDGwAlAgAlAAgJORjDGwAlAgAAAA==.',
Hn='Hnymanbadger:BAAALgAECgEJAQABLgAECgYJFgAlAL0NAA==.',
Ho='Holdmybear:BAAALgAECgEJAQAAAA==.Holyfudge:BAAALgAECgQJCAABLgAFFAEJAQAEAAAAAA==.Holyhyper:BAABLgAECn8hAAMUAAgJlB8bGQDTAgAUAAgJlB8bGQDTAgABAAQJxAFDdwCcAAAAAA==.Holyslanger:BAAALgADCgYJBgABLgAECggJHgAIAKwhAA==.Holywaddles:BAAALgAECgYJEAAAAA==.Hookshot:BAAALgADCgEJAQAAAA==.Hotfix:BAAALgADCgIJBAAAAA==.Hozax:BAAALgADCgYJBgAAAA==.Hozo:BAACLgAFFH8FAAMBAAIJ1BTZCgBlAAABAAIJ1BTZCgBlAAAUAAIJKgc3GQBPAAAuAAQKfyMAAwEACAn+GeYXAFMCAAEACAn+GeYXAFMCABQACAlbFaNEABYCAAAA.Hozoyummy:BAAALgAECgMJAwAAAA==.',
Ht='Htownshawdo:BAAALgAECgYJEAAAAA==.',
Hu='Hubertus:BAAALgADCgYJCQAAAA==.Huntressa:BAAALgAECgEJAQAAAA==.',
Ic='Icesus:BAAALgADCgYJBgAAAA==.',
Ih='Ihatepriests:BAAALgADCgYJDAAAAA==.',
Il='Iloveluci:BAAALgADCgkJDgAAAA==.',
Io='Ioraa:BAAALgAECgYJEwAAAA==.',
Ip='Ip:BAAALgAECgEJAQABLgAECggJHgAIAKwhAA==.',
Ir='Ireumi:BAAALgADCgIJAgABLgAECgcJHgAIAOwjAA==.Irishhammer:BAAALgAECgYJEwAAAA==.',
Ix='Ixalas:BAAALgAECgMJBgAAAA==.Ixias:BAAALgADCgkJDwAAAA==.Ixionath:BAAALgAECgUJCQAAAA==.',
Iz='Izaelith:BAAALgADCgEJAQAAAA==.',
['Iá']='Ián:BAABLgAECn8hAAMFAAgJYx9nAwBeAgAFAAgJYx9nAwBeAgAGAAUJlx3mFQCbAQAAAA==.',
Ja='Janaloaf:BAAALgADCgQJBAAAAA==.Janq:BAABLgAECn8eAAILAAgJLRmkFgBlAgALAAgJLRmkFgBlAgAAAA==.',
Je='Jedwalethan:BAAALgADCgEJAQAAAA==.Jeniko:BAAALgAECgYJDgAAAA==.Jext:BAAALgAFFAIJAgAAAA==.',
Ji='Jintulu:BAAALgADCgQJBAAAAA==.',
Jm='Jmc:BAAALgAECgUJBwAAAA==.',
Jo='Joedk:BAAALgAECggJCAAAAA==.Joeruid:BAAALgADCgYJBgAAAA==.Jollyjohn:BAAALgAECgcJEgAAAA==.Jonah:BAAALgADCgcJBgAAAA==.Jonesy:BAAALgAECgEJAQAAAA==.Jono:BAAALgADCgEJAQAAAA==.Jork:BAAALgADCgEJAQAAAA==.',
Jp='Jpglaive:BAABLgAECn8VAAIHAAgJkh+GDgALAwAHAAgJkh+GDgALAwAAAA==.',
Ju='Juisi:BAABLgAECn8ZAAMkAAgJXBnYAwCAAgAkAAgJXBnYAwCAAgAWAAYJAxOPKgCoAQAAAA==.Juiski:BAAALgAECgMJAwAAAA==.Justania:BAABLgAECn8dAAMJAAgJ5AbINgBhAQAJAAgJ5AbINgBhAQAZAAYJJQWwQwDeAAAAAA==.',
['Já']='Jáque:BAAALgAECgYJDwAAAA==.',
Ka='Kaayle:BAAALgAECgMJBAAAAA==.Kadike:BAAALgAECgQJBwAAAA==.Kaela:BAAALgADCgIJAgAAAA==.Kaeloth:BAABLgAECn8fAAIUAAgJ7B+FBABYAgAUAAgJ7B+FBABYAgAAAA==.Kafaya:BAAALgAECgcJDQAAAA==.Kagome:BAAALgADCgYJCAAAAA==.Kalanar:BAAALgADCgEJAQAAAA==.Kaldh:BAAALgAECgYJBgABLgAECggJIAAUAEUUAA==.Kalebmonk:BAAALgAECgYJCQABLgAECggJIAAUAEUUAA==.Kalebpal:BAABLgAECn8gAAIUAAgJRRSCRgAQAgAUAAgJRRSCRgAQAgAAAA==.Kalen:BAAALgADCgYJBgAAAA==.Kamtano:BAAALgAECgYJEwAAAA==.Kardia:BAAALgADCgQJBAAAAA==.Karic:BAAALgAECgQJBAAAAA==.Karper:BAAALgAECgYJEAABLgAFFAIJBQAUAD0ZAA==.Kayaanu:BAABLgAECn8gAAIjAAgJlSVeAQDxAgAjAAgJlSVeAQDxAgAAAA==.Kazuld:BAAALgADCgEJAQAAAA==.',
Ke='Kegsmasher:BAAALgADCgkJCQAAAA==.Kelork:BAAALgADCgIJAgAAAA==.Kerethor:BAAALgADCgUJBQAAAA==.Kermora:BAAALgADCgUJCQAAAA==.',
Kh='Khalanos:BAABLgAECn8WAAMfAAcJvRP7BACOAQAfAAcJvRP7BACOAQADAAEJvwW4kgAnAAAAAA==.Khazryl:BAAALgAECgYJEAAAAA==.Khyzer:BAABLgAECn8eAAIlAAcJZBGSCgBFAQAlAAcJZBGSCgBFAQAAAA==.',
Ki='Killershot:BAABLgAECn8ZAAICAAcJFCFWBQAhAgACAAcJFCFWBQAhAgAAAA==.Killián:BAAALgAECgYJCQAAAA==.Kirke:BAAALgADCgMJAwAAAA==.Kirriana:BAABLgAECn8fAAIJAAgJHyLYBAADAwAJAAgJHyLYBAADAwAAAA==.Kirrie:BAAALgAECgEJAQAAAA==.',
Kk='Kkitty:BAAALgAECgQJBgAAAA==.',
Kl='Kletus:BAAALgAECgkJCQAAAA==.',
Ko='Kobs:BAAALgADCgUJBgAAAA==.Kongming:BAAALgAECgEJAQAAAA==.Korvash:BAAALgAECgYJCwAAAA==.Kosmos:BAAALgADCgYJBgAAAA==.Kostik:BAAALgADCgcJDQAAAA==.',
Kr='Kromgi:BAAALgADCgMJAwAAAA==.Kromgol:BAACLgAFFH8JAAILAAQJ0BG8AwA2AQALAAQJ0BG8AwA2AQAuAAQKfxkAAgsACAlEHXUQAKQCAAsACAlEHXUQAKQCAAAA.Krulos:BAAALgAECgYJBgAAAA==.',
Ku='Kua:BAAALgADCgkJHgAAAA==.Kushov:BAAALgADCgQJBAAAAA==.',
Kw='Kwende:BAABLgAECn8dAAIUAAgJqReMSgADAgAUAAgJqReMSgADAgAAAA==.',
Ky='Kyela:BAAALgAECgYJEQAAAA==.Kyndill:BAAALgADCgYJEAAAAA==.Kyriè:BAAALgAECgUJBQAAAA==.Kyrrith:BAAALgAECgUJDAAAAA==.Kyrtion:BAAALgAECgUJCQAAAA==.',
['Kø']='Kørupted:BAABLgAECn8WAAIFAAYJIBibXACyAQAFAAYJIBibXACyAQAAAA==.',
La='Lailis:BAAALgADCgEJAQABLgAECggJGgAaAOEeAA==.Lamiisa:BAAALgAECgYJDAAAAA==.Lanaya:BAABLgAECn8ZAAIjAAcJcSGXDADpAQAjAAcJcSGXDADpAQAAAA==.Lankanau:BAAALgAECgIJAgAAAA==.Lapyy:BAAALgADCgEJAQAAAA==.Laurala:BAAALgADCggJFAAAAA==.Laurandrel:BAABLgAECn8YAAIfAAcJkggwBwBIAQAfAAcJkggwBwBIAQAAAA==.Laved:BAABLgAECn8fAAMSAAgJRyL1BwAXAwASAAgJRyL1BwAXAwAIAAYJwiTfBQAYAgAAAA==.',
Ld='Ldkillsemm:BAAALgADCgYJCAAAAA==.',
Le='Leegandhi:BAAALgAECgUJBQAAAA==.Lewinn:BAAALgAECgYJDQAAAA==.',
Li='Lightrose:BAAALgAECgIJAwAAAA==.Likäbäws:BAAALgAECgIJAgAAAA==.Lilitü:BAAALgADCgcJCQAAAA==.Lilstaby:BAABLgAECn8XAAIWAAcJ4hdFHgAKAgAWAAcJ4hdFHgAKAgAAAA==.Lilya:BAABLgAECn8ZAAIeAAgJhBMHCgBNAQAeAAgJhBMHCgBNAQAAAA==.Linossa:BAAALgAFFAEJAQAAAA==.Liola:BAAALgAECgEJAQAAAA==.Lizardwizàrd:BAAALgAECgIJAgAAAA==.',
Lo='Lockycharms:BAAALgADCgcJCgAAAA==.Logikul:BAABLgAECn8cAAIlAAgJdRcSIAABAgAlAAgJdRcSIAABAgAAAA==.Lookbak:BAAALgAECgYJEQAAAA==.Lookiezi:BAABLgAECn8bAAIBAAkJpRyzBwDyAgABAAkJpRyzBwDyAgAAAA==.Lostriis:BAAALgADCgEJAQAAAA==.',
Lu='Lucidonis:BAAALgAECgYJEQAAAA==.Lucili:BAABLgAECn8WAAMFAAYJ9AnCKQDnAAAFAAUJuwrCKQDnAAAGAAQJsgR1RQCgAAAAAA==.Luh:BAAALgAECgcJEgAAAA==.Lumira:BAAALgAECgUJCgAAAA==.Lunandriel:BAABLgAECn8lAAIWAAkJzhe5DgC1AgAWAAkJzhe5DgC1AgAAAA==.',
Ly='Lystia:BAAALgAECgUJDQAAAA==.',
['Lâ']='Lâdypantz:BAAALgADCgEJAQAAAA==.',
['Læ']='Læncelot:BAAALgAECgUJEQAAAA==.',
['Lú']='Lúná:BAAALgADCgMJAwAAAA==.',
Ma='Maalik:BAAALgADCgQJBAAAAA==.Madgoat:BAAALgAECgYJEwAAAA==.Madriel:BAAALgAECgcJDQAAAA==.Maelune:BAAALgAECgYJCAAAAA==.Mafanya:BAAALgADCgkJDwAAAA==.Magento:BAABLgAECn8hAAIjAAgJ7SIYFAAwAwAjAAgJ7SIYFAAwAwAAAA==.Maintankpov:BAAALgADCgQJBAAAAA==.Maladie:BAABLgAECn8XAAIKAAYJYg1ulwBRAQAKAAYJYg1ulwBRAQAAAA==.Malira:BAAALgAECgYJBwAAAA==.Malvaron:BAAALgADCgUJBQAAAA==.Mamoullian:BAAALgADCgQJBAAAAA==.Manmonk:BAABLgAECn8WAAIlAAYJvQ3mRwAiAQAlAAYJvQ3mRwAiAQAAAA==.Manthellea:BAAALgADCgEJAQAAAA==.Marakanis:BAAALgADCgIJAgAAAA==.Marsmerlot:BAAALgAECgQJBwAAAA==.Mastaquick:BAAALgAECgUJBQAAAA==.Mattank:BAABLgAECn8jAAMUAAkJMBGeYwC7AQAUAAkJNxCeYwC7AQAVAAEJnxhDEQBHAAAAAA==.Mavzy:BAABLgAECn8UAAMhAAgJ0AdaAgBDAQAhAAgJlAdaAgBDAQAGAAMJOQNFWwBdAAAAAA==.Mawey:BAAALgADCgEJAQAAAA==.Mayor:BAAALgADCgMJAwAAAA==.',
Mc='Mcbubbies:BAAALgAECgQJCgAAAA==.Mcfknkfc:BAAALgADCgkJEwAAAA==.',
Me='Meatydk:BAAALgAECgYJDwAAAA==.Mechabuzz:BAAALgAECgYJCwAAAA==.Meeyoh:BAAALgADCgcJBwAAAA==.Mehrunedagon:BAAALgAECgYJCgAAAA==.Melchizedekk:BAAALgADCgMJAwAAAA==.Melnibonai:BAAALgADCgUJBQAAAA==.',
Mi='Michelena:BAAALgAECgQJBAAAAA==.Micti:BAABLgAECn8hAAIGAAgJsA/EAQCXAQAGAAgJsA/EAQCXAQAAAA==.Micycle:BAAALgAECgUJCgAAAA==.Miirra:BAAALgAECgMJAwAAAA==.Milamber:BAAALgAECgcJDAAAAA==.Miniion:BAAALgAECgYJBgAAAA==.Minjiu:BAAALgAECgEJAQAAAA==.Minyon:BAABLgAECn8gAAIZAAgJ6yObAQBmAgAZAAgJ6yObAQBmAgAAAA==.Mir:BAAALgADCgkJEQAAAA==.Miruna:BAAALgAECgMJAwAAAA==.Misdirected:BAAALgADCgYJBgAAAA==.',
Mo='Mommadragon:BAAALgAECgYJEwAAAA==.Momohirai:BAABLgAECn8eAAImAAcJWCCfAwDbAQAmAAcJWCCfAwDbAQAAAA==.Monkhoe:BAAALgAECgYJCgABLgAECgkJJQAWAM4XAA==.Monkinasuey:BAAALgAECgYJCgAAAA==.Monkspider:BAAALgAECgcJEgAAAA==.Monsterdk:BAAALgAECgYJCQAAAA==.Moonerknight:BAEBLgAECn8WAAIKAAgJHRPfXQDZAQAKAAgJHRPfXQDZAQAAAA==.Mordekaiser:BAAALgADCgMJAwAAAA==.Moshi:BAAALgAECgUJBQAAAA==.',
Ms='Msmoistmufin:BAAALgADCgUJBQAAAA==.',
Mu='Mugoogaipan:BAAALgAECgQJBAAAAA==.Mugron:BAABLgAECn8UAAMdAAcJ5CLjBgC/AgAdAAcJ5CLjBgC/AgAYAAEJ8wdnogA+AAABLgAFFAYJEwAcAGMfAA==.',
My='Mynions:BAAALgADCgUJBQAAAA==.Myrarawr:BAAALgAECgQJBAAAAA==.Mystoril:BAAALgADCgkJDwAAAA==.Mythrandia:BAABLgAECn8aAAIJAAgJoR5rDQCBAgAJAAgJoR5rDQCBAgAAAA==.',
Na='Nappychan:BAAALgAECgQJCQAAAA==.Narsissa:BAAALgADCgQJBAAAAA==.Nazerem:BAAALgAECgYJCAAAAA==.Nazgothoth:BAAALgADCgMJAwAAAA==.',
Ne='Neebstrasza:BAAALgADCgkJFQAAAA==.Nexmagus:BAAALgADCgMJAwAAAA==.',
Ni='Nichts:BAAALgADCgkJCQAAAA==.Nicklâus:BAAALgAECgEJAQAAAA==.Nicko:BAAALgADCgQJBAAAAA==.Nicodkemus:BAAALgAECgYJBgABLgAECggJIAAlACAcAA==.Nicolius:BAAALgADCgcJCAABLgAECggJIAAlACAcAA==.Nikfu:BAABLgAECn8gAAIlAAgJIBwOBgCnAQAlAAgJIBwOBgCnAQAAAA==.Ningenalah:BAABLgAECn8eAAIKAAgJfyKJCAD1AQAKAAgJfyKJCAD1AQAAAA==.Ningendormu:BAAALgADCgUJBgAAAA==.Ningenurion:BAAALgAECgUJBgAAAA==.Nippÿ:BAABLgAECn8eAAIjAAgJUhSiZAAPAgAjAAgJUhSiZAAPAgAAAA==.Nirazend:BAAALgADCgkJEgAAAA==.Nixis:BAAALgAECgYJEQAAAA==.',
No='Noobyasha:BAAALgAECgMJAwAAAA==.Norav:BAAALgADCgQJBAAAAA==.Nordryde:BAAALgAECgUJBQABLgAFFAMJBgAeABAXAA==.Nordrydm:BAACLgAFFH8GAAIeAAMJEBdjCgAGAQAeAAMJEBdjCgAGAQAuAAQKfxkAAh4ACAmOHbUNAHsCAB4ACAmOHbUNAHsCAAAA.Nordrydpr:BAAALgADCggJAgABLgAFFAMJBgAeABAXAA==.Notoes:BAAALgADCgYJBgAAAA==.Noxeis:BAAALgADCgcJDAAAAA==.Noxes:BAAALgAECgYJDwAAAA==.Noxii:BAAALgADCgEJAgAAAA==.',
Nu='Numericz:BAAALgAECgQJBQAAAA==.',
Nx='Nxs:BAAALgAECgYJBgAAAA==.',
Ny='Nylèi:BAAALgADCgEJAQAAAA==.',
['Nå']='Nå:BAABLgAECn8bAAIHAAcJchopOgAMAgAHAAcJchopOgAMAgABLgAECggJFQAVAHIdAA==.',
['Ní']='Níghtmäre:BAAALgAECgMJAwAAAA==.',
Oa='Oakshaler:BAAALgAECgYJEQAAAA==.',
Ob='Obsidium:BAAALgAECgIJAgABLgAECgcJGQABAGIRAA==.',
Oc='Ocris:BAAALgADCgMJAwAAAA==.',
Of='Offënsive:BAABLgAECn8YAAIYAAgJPBvvIABLAgAYAAgJPBvvIABLAgAAAA==.',
Ol='Olayhahla:BAAALgAECgYJEwAAAA==.Olivens:BAAALgADCgcJBwAAAQ==.',
Om='Ommie:BAAALgAECgUJBgAAAA==.Omun:BAAALgADCgEJAQAAAA==.',
On='Onè:BAAALgADCgMJAwABLgAECggJKAAKAOggAA==.',
Or='Ordek:BAAALgAECgQJBAAAAA==.',
Os='Osyrus:BAAALgADCgYJCQAAAA==.',
Pa='Paegusus:BAAALgADCgEJAQAAAA==.Pandybearz:BAABLgAECn8UAAICAAYJlxcqEgBrAQACAAYJlxcqEgBrAQAAAA==.Pantyfa:BAAALgADCgYJBgAAAA==.Paraclete:BAAALgAECgcJCgAAAA==.Paraimee:BAAALgAECgEJAQAAAA==.Parkiepark:BAAALgADCgQJBAAAAA==.Pawtism:BAAALgADCgQJBAABLgAECggJKQAMAOghAA==.',
Pe='Pekkie:BAAALgADCggJDwAAAA==.Percpapi:BAAALgADCgMJAwAAAA==.Pestis:BAAALgAECgYJDQAAAA==.',
Ph='Phallon:BAAALgAECgYJEQAAAA==.Phantomlord:BAAALgAECgkJBgAAAA==.',
Pi='Pi:BAABLgAECn8YAAIZAAcJ4hAyCAB0AQAZAAcJ4hAyCAB0AQAAAA==.Pidi:BAAALgADCgEJAQABLgAECgcJHgAiADcXAA==.Pindolino:BAAALgADCgMJAwAAAA==.Pingu:BAABLgAECn8cAAMKAAcJDBwiRgAiAgAKAAcJ5RsiRgAiAgAcAAEJWho/RAA4AAAAAA==.Pioree:BAACLgAFFH8FAAQgAAMJLQ/fDACiAAAgAAIJ4hHfDACiAAANAAEJwgm/AgBRAAAMAAEJAwFlGQA0AAAuAAQKfyYABCAACAnEH5wLAL0CACAACAk2HZwLAL0CAA0ACAnyGRUPAOkBAAwAAQmnCPNJAC4AAAAA.Piott:BAAALgADCgEJAQAAAA==.Pixieberry:BAAALgAECgYJDQAAAA==.',
Pl='Plimp:BAAALgADCgYJBgAAAA==.',
Po='Pokédex:BAAALgADCgYJAQAAAA==.Pookiebear:BAAALgAECgEJAwAAAA==.Porthub:BAAALgAECgMJAwAAAA==.',
Pp='Ppriest:BAAALgADCgIJAgAAAA==.',
Pr='Prandal:BAAALgADCgcJCwAAAA==.Preserves:BAAALgAECgEJAQABLgAFFAUJEgAlAJsTAA==.Primechi:BAAALgADCgMJAwAAAA==.Priëst:BAAALgADCgEJAQAAAA==.',
Ps='Pseudocheese:BAAALgADCgcJDQABLgAECgUJCgAEAAAAAA==.',
['Pä']='Päladont:BAAALgAECgEJAgAAAA==.',
['Pø']='Pø:BAAALgADCgYJBgABLgAECgUJBQAEAAAAAA==.',
Qe='Qe:BAAALgADCgMJAwAAAA==.',
Qu='Quanzanon:BAABLgAECn8aAAIIAAgJIQd0GQDvAAAIAAgJIQd0GQDvAAAAAA==.',
Ra='Rabiddad:BAAALgAECgUJCgAAAA==.Rachelrae:BAABLgAECn8bAAIJAAgJ0A2zKgCfAQAJAAgJ0A2zKgCfAQAAAA==.Raistlèe:BAAALgADCgIJAgAAAA==.Ramenwrapz:BAABLgAECn8XAAMJAAcJ/CANGQAUAgAJAAcJ/CANGQAUAgAZAAEJ1wKNIwAoAAAAAA==.Rattybones:BAAALgADCgEJAQAAAA==.Rauiri:BAAALgAECgYJEAAAAA==.',
Re='Recessive:BAAALgAECgQJEQAAAA==.Reddìngton:BAAALgADCgUJBQAAAA==.Refeik:BAAALgAECgUJCAAAAA==.Reginald:BAABLgAECn8YAAIUAAgJHRmQMgBYAgAUAAgJHRmQMgBYAgABLgAECgYJFQAHAD0bAA==.Regrowth:BAAALgAECgMJAwAAAA==.Reikoku:BAAALgAECgIJAgAAAA==.Rejuva:BAAALgAECgMJBAAAAA==.Relinquo:BAABLgAECn8bAAMfAAgJ1yRAAQBXAwAfAAgJ1yRAAQBXAwADAAEJDguNjwArAAAAAA==.Relse:BAAALgAECgQJBwAAAA==.Renika:BAABLgAECn8XAAMnAAYJswl2BgA3AQAnAAYJIwl2BgA3AQAjAAQJNgXILgGjAAAAAA==.Resperea:BAAALgADCgkJGQAAAA==.',
Ri='Ricassou:BAABLgAECn8YAAIlAAcJGBlmBgCeAQAlAAcJGBlmBgCeAQAAAA==.Ricochet:BAAALgAECgYJDwAAAA==.Rinn:BAAALgADCgIJAgAAAA==.Riottmoon:BAAALgAECgcJEgAAAA==.Riptipped:BAAALgADCgYJBgAAAA==.Rivendell:BAAALgAFFAEJAQAAAA==.',
Ro='Robloxrocks:BAAALgAECgUJBQAAAA==.Romi:BAAALgAECgYJBgABLgAECggJIAAHACwYAA==.Rook:BAAALgAECgcJDQAAAA==.Rorynne:BAAALgAECgYJDAAAAA==.Rotheion:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Rougenova:BAAALgADCgYJBgABLgAFFAUJBwAHAP8MAA==.',
Rr='Rrubio:BAAALgADCgkJCQAAAA==.',
Ru='Rucksack:BAABLgAECn8ZAAIOAAgJCRRRCgACAgAOAAgJCRRRCgACAgAAAA==.Rucy:BAEBLgAECn8eAAISAAgJAhOyIwDfAQASAAgJAhOyIwDfAQAAAA==.Rucybow:BAEALgADCgUJBQABLgAECggJHgASAAITAA==.',
Ry='Ryndkmc:BAAALgAECgMJAwABLgAECgQJBwAEAAAAAA==.',
['Ré']='Réfléx:BAAALgAECgIJAwAAAA==.',
Sa='Sacredmilk:BAAALgADCgEJAgAAAA==.Saeya:BAAALgAECgMJAwAAAA==.Sakurai:BAABLgAECn8VAAIkAAYJByFRAQDPAQAkAAYJByFRAQDPAQAAAA==.Salamander:BAABLgAECn8aAAMgAAgJSwqhKgBqAQAgAAgJSwqhKgBqAQANAAQJOQLINQBnAAAAAA==.Samirah:BAAALgADCgcJDgAAAA==.Sanotor:BAAALgADCgYJCQAAAA==.Santhras:BAAALgADCgQJBAAAAA==.Saristia:BAAALgAECgMJAwABLgAECgYJEwAEAAAAAA==.Sattha:BAABLgAECn8UAAMcAAcJ+RBdHgBVAQAcAAYJhxNdHgBVAQAKAAIJkQpSBwFnAAAAAA==.Saurmont:BAAALgAECgUJDwAAAA==.Savage:BAAALgADCgQJBAAAAA==.Saveu:BAAALgAECgQJCQAAAA==.',
Sc='Scalesofuwu:BAAALgAECgQJBQAAAA==.Scorpïon:BAAALgAECgYJEgAAAA==.Screampies:BAABLgAECn8ZAAIBAAcJYhHXDQBjAQABAAcJYhHXDQBjAQAAAA==.',
Se='Seagulls:BAEALgAECgYJEwAAAA==.Seayaa:BAAALgAECgYJEwAAAA==.Sejanuss:BAAALgAECgMJAwABLgAECgYJBgAEAAAAAA==.Selindia:BAAALgAECgIJAgAAAA==.Sellsword:BAAALgAECgIJAgAAAA==.Senadoria:BAAALgAECgQJBAAAAA==.Sewersliding:BAABLgAECn8UAAIgAAkJRxP3EABqAgAgAAkJRxP3EABqAgAAAA==.',
Sh='Shadowzangel:BAAALgAECgMJAwAAAA==.Shaedee:BAAALgADCggJCAAAAA==.Shammyshaga:BAAALgAECgYJEwAAAA==.Shampayne:BAAALgAECgMJAwAAAA==.Shattered:BAAALgAECgEJAQAAAA==.Shelina:BAAALgADCgIJAgAAAA==.Shen:BAAALgAECgYJEQAAAA==.Sheriff:BAACLgAFFH8NAAIHAAUJgx3+BgC0AQAHAAUJgx3+BgC0AQAuAAQKfxkAAgcACQn0HlELACcDAAcACQn0HlELACcDAAEuAAQKBgkGAAQAAAAA.Shibito:BAABLgAECn8dAAIZAAgJgRKRGgAKAgAZAAgJgRKRGgAKAgAAAA==.Shilan:BAAALgADCgkJDwAAAA==.Shilihu:BAAALgADCggJCAAAAA==.Shinukishin:BAABLgAECn8dAAIKAAgJ+SGiAQC3AgAKAAgJ+SGiAQC3AgAAAA==.Shiraga:BAAALgADCgcJEAAAAA==.Shivx:BAAALgADCgcJDgAAAA==.Shockaflokka:BAAALgADCgEJAQAAAA==.Shodomy:BAAALgAECgQJBwAAAA==.Shoebolt:BAAALgAECgEJAQAAAA==.Shorzy:BAABLgAECn8aAAIHAAcJGhquCwC6AQAHAAcJGhquCwC6AQAAAA==.Shreddeez:BAABLgAECn8UAAIRAAcJsx5JAQAQAgARAAcJsx5JAQAQAgAAAA==.Shygon:BAABLgAECn8hAAILAAgJkiRKBQBDAwALAAgJkiRKBQBDAwAAAA==.',
Si='Siek:BAAALgADCgMJAwABLgAECgYJDQAEAAAAAA==.Sienar:BAAALgADCgcJDAAAAA==.Sigmasmite:BAAALgADCgIJAgAAAA==.Simulacra:BAAALgAECgQJBgAAAA==.Sivienne:BAAALgADCgYJBgAAAA==.',
Sk='Skallock:BAABLgAECn8bAAIFAAcJIw5zGQBIAQAFAAcJIw5zGQBIAQAAAA==.',
Sl='Sleepfrostvv:BAAALgAECgYJDAAAAA==.Slimpikkinz:BAAALgAECgMJAwAAAA==.Slipnslide:BAAALgAECgQJCQAAAA==.Slu:BAABLgAECn8iAAIjAAgJ9yLzFQAlAwAjAAgJ9yLzFQAlAwABLgAECgYJBgAEAAAAAA==.',
Sm='Smashinsmith:BAABLgAECn8gAAMOAAgJPBoxAQAcAgAOAAgJ1xkxAQAcAgAYAAcJtxHcRwCFAQAAAA==.Smokey:BAAALgAECgYJBgAAAA==.',
Sn='Snackpack:BAAALgAECgMJAwAAAA==.Snekprotek:BAAALgAECgUJCgAAAA==.Snockerz:BAAALgADCgYJBgAAAA==.Snoop:BAAALgADCgQJBAAAAA==.Snoopzxd:BAACLgAFFH8KAAILAAQJYw/6CwAsAQALAAQJYw/6CwAsAQAuAAQKfyUAAgsACAltIGMTAIUCAAsACAltIGMTAIUCAAAA.Snowdancer:BAAALgAECgQJBQAAAA==.',
So='Socialist:BAAALgADCgIJAgAAAA==.Sollina:BAAALgADCgcJBwAAAA==.Somno:BAABLgAECn8eAAMHAAcJ3STeAwBaAgAHAAcJ3STeAwBaAgAbAAYJRRTLKQB2AQAAAA==.Songito:BAAALgADCgQJBQAAAA==.Sophea:BAAALgADCgkJEAAAAA==.Soulfly:BAAALgAECgQJCwAAAA==.Soulsabi:BAABLgAECn8mAAMFAAgJCyXSCQAvAwAFAAgJCyXSCQAvAwAGAAIJmiOhOwDGAAAAAA==.Soulshaper:BAAALgAECgUJCAAAAA==.',
Sp='Spectral:BAABLgAECn8bAAIJAAgJdx28EwBBAgAJAAgJdx28EwBBAgAAAA==.Sperkk:BAAALgAECgYJBgAAAA==.Spiritwalk:BAAALgADCgUJBQAAAA==.Spookyshark:BAAALgADCgUJBQAAAA==.Spookywacky:BAAALgADCgMJAwAAAA==.Spoonman:BAABLgAECn8fAAIIAAgJ4yBJAQDoAgAIAAgJ4yBJAQDoAgAAAA==.Spurk:BAABLgAECn8dAAMLAAgJOx3JFQBtAgALAAYJJCXJFQBtAgATAAYJ3hsxNQCvAQAAAA==.Spåwnkîll:BAAALgAECgYJEAAAAA==.',
St='Staceysmom:BAAALgAECgYJEgAAAA==.Stardrift:BAAALgADCgcJCwAAAA==.Static:BAAALgAECgYJCAAAAA==.Stephen:BAAALgADCgUJBQAAAA==.Stere:BAAALgAECgQJCAAAAA==.Steve:BAAALgADCgcJFQAAAA==.Stinggrayjr:BAAALgAECgIJAgAAAA==.Stinkyfeets:BAAALgAECgEJAQABLgAECgYJEAAEAAAAAA==.Stonedborn:BAAALgAECgcJBwAAAA==.Storihbeg:BAAALgADCgcJCAABLgAECgYJCgAEAAAAAA==.Stox:BAAALgAECgYJDAAAAA==.Stärkiller:BAAALgADCgMJBAAAAA==.Stòrm:BAAALgADCgcJDQAAAA==.',
Su='Suenami:BAAALgAECgYJDAAAAA==.Sunon:BAAALgADCgMJAwAAAA==.Sunøn:BAAALgADCgUJCgAAAA==.Superhilock:BAACLgAFFH8FAAIFAAIJqBjGFwCrAAAFAAIJqBjGFwCrAAAuAAQKfykAAwUACAk6JIEBALMCAAUACAk5JIEBALMCAAYAAwlPH0UsAA0BAAAA.Supershenron:BAAALgAECgcJCQAAAA==.Surlyroach:BAAALgADCgYJBQAAAA==.',
Sv='Svelesstiá:BAAALgADCgcJGwAAAA==.',
Sw='Swan:BAABLgAECn8eAAIfAAgJWB54BQC0AgAfAAgJWB54BQC0AgAAAA==.Swordmaster:BAABLgAECn8iAAMOAAgJkyN0AQA2AwAOAAgJKSJ0AQA2AwAYAAcJLB0NKwALAgABLgAECggJIgAOAJMjAA==.',
Sy='Sydneezy:BAABLgAECn8ZAAIFAAYJ5xSvIQAXAQAFAAYJ5xSvIQAXAQAAAA==.Syrelliia:BAABLgAECn8dAAIkAAgJlA/TBgACAgAkAAgJlA/TBgACAgAAAA==.',
['Sæ']='Sævage:BAABLgAECn8qAAICAAcJfh8HLQD/AQACAAcJfh8HLQD/AQAAAA==.',
Ta='Taii:BAAALgADCgQJBAABLgAECgkJFAAgAEcTAA==.Taiigah:BAAALgAECgYJDAABLgAECgkJFAAgAEcTAA==.Taladage:BAAALgADCgMJAwAAAA==.Talendar:BAAALgADCgYJCwAAAA==.Talfrah:BAAALgADCgcJDwAAAA==.Tanrok:BAABLgAECn8bAAMjAAgJCg8zggDNAQAjAAgJQQ4zggDNAQAnAAcJ5gZzBwAKAQAAAA==.Tarnac:BAAALgAECgEJAQAAAA==.Tatertots:BAAALgAECgYJDwAAAA==.Tazorface:BAABLgAECn8iAAQKAAgJUBwwCQDrAQAKAAgJKBswCQDrAQAcAAYJHh7qEwDRAQAoAAEJVQnECAA+AAAAAA==.',
Te='Techissue:BAAALgAECgEJAQAAAA==.Techtonich:BAAALgAECgYJDAAAAA==.',
Th='Tharkash:BAAALgAECgYJEAAAAA==.Thedockwho:BAAALgAECgYJDQAAAA==.Thedoctorwho:BAAALgADCgkJEAAAAA==.Thellarius:BAAALgADCgcJCQAAAA==.Thirdeye:BAAALgAECgEJAQAAAA==.Thoxic:BAAALgADCgYJCgABLgAECgcJHgAlAGQRAA==.Thundermaw:BAAALgAECgEJAQAAAA==.',
Ti='Tibetan:BAAALgADCgcJCgABLgAECggJHwAUAOwfAA==.Tigs:BAAALgADCgcJEQAAAA==.Tildra:BAAALgAECgMJBwAAAA==.Timidity:BAABLgAECn8gAAMWAAgJiB65AgADAgAWAAgJFR25AgADAgAkAAQJvRdNDwAdAQAAAA==.',
To='Tomey:BAAALgADCgMJAwAAAA==.Tonyrona:BAAALgAECgYJCgAAAA==.Toolip:BAABLgAECn8YAAIBAAcJEh73BwDIAQABAAcJEh73BwDIAQAAAA==.Toothesayer:BAAALgADCgYJBgAAAA==.Tornwraith:BAABLgAECn8XAAMhAAYJ4RIeDgBRAQAhAAYJYg8eDgBRAQAGAAYJZQsQKgAZAQAAAA==.Tovash:BAAALgADCgkJFwAAAA==.',
Tr='Trapsy:BAEALgAECgQJCAABLgAECggJFgAKAB0TAA==.Trauma:BAAALgAECgUJDQAAAA==.Traumaspally:BAAALgADCgYJBgABLgAECgUJDQAEAAAAAA==.Trehuga:BAAALgAECgUJDAAAAA==.Triso:BAAALgAECgYJBgAAAA==.Trochanter:BAAALgADCgIJAgAAAA==.Tronus:BAAALgAECgEJAQAAAA==.Troodonus:BAABLgAECn8fAAIUAAgJOCGrEgD9AgAUAAgJOCGrEgD9AgAAAA==.',
Ts='Tsukaar:BAABLgAECn8YAAMdAAcJIRbVEgDcAQAdAAcJIRbVEgDcAQAYAAEJ/whWqQA0AAAAAA==.Tsunade:BAAALgAECgIJAgAAAA==.Tswift:BAAALgAECgYJEAAAAA==.',
Tu='Tutorialboss:BAABLgAECn8cAAMDAAgJ+x+IEwCWAgADAAgJ/R6IEwCWAgACAAIJOSNRJwDLAAAAAA==.',
Tw='Twotoes:BAAALgAECgEJAQAAAA==.',
Ty='Tydiss:BAAALgAECgYJDAAAAA==.Tygranther:BAAALgADCgcJEQAAAA==.',
Ug='Ugway:BAAALgADCgEJAQABLgAECgYJEQAEAAAAAA==.',
Ul='Ulfheðnar:BAAALgADCgEJAQAAAA==.Ulrika:BAABLgAECn8fAAIKAAgJBCIyAwB1AgAKAAgJBCIyAwB1AgAAAA==.',
Um='Umbralmoon:BAAALgADCgEJAQAAAA==.',
Un='Unforgyven:BAAALgAECgYJEQAAAA==.Uniscorn:BAAALgADCgEJAQAAAA==.',
Va='Vaepor:BAABLgAECn8eAAMXAAgJ1ROWCQDUAQAXAAgJ1ROWCQDUAQAHAAYJFQzYJgDhAAAAAA==.Vague:BAABLgAECn8XAAMDAAYJFSSWGgBSAgADAAYJhyOWGgBSAgAfAAQJ0R4QFgBnAQAAAA==.Vaguelz:BAAALgADCgYJBgAAAA==.Valeureux:BAAALgADCgMJAwAAAA==.Valgaar:BAAALgADCgEJAQAAAA==.Valorin:BAAALgAECgYJCwAAAA==.Valvify:BAAALgAECgEJAQAAAA==.Vandimion:BAAALgADCgYJBgAAAA==.Vaneste:BAACLgAFFH8QAAMFAAUJdxMmCAClAQAFAAUJdxMmCAClAQAGAAEJJAUcGQBLAAAuAAQKfyYAAgUACQl8IXcLAB8DAAUACQl8IXcLAB8DAAAA.Vartrino:BAABLgAECn8eAAILAAcJgR22BADXAQALAAcJgR22BADXAQAAAA==.',
Ve='Velandela:BAAALgADCgYJBgAAAA==.Vendoralia:BAAALgAECgYJDgAAAA==.Venuspriest:BAAALgADCgYJBgAAAA==.Verdius:BAAALgAECgYJEQAAAA==.Verifiedbot:BAAALgAECgYJBgAAAA==.Verlant:BAAALgAECgYJDwAAAA==.Vermwing:BAAALgAECgYJBgAAAA==.Vernichtet:BAAALgAECgEJAQAAAA==.',
Vi='Virikae:BAAALgAECgQJBgAAAA==.',
Vo='Voodooshot:BAAALgADCgcJBwAAAA==.Vortan:BAAALgAECggJEwAAAA==.',
Vu='Vush:BAAALgAECgYJDQAAAA==.',
Vy='Vyniran:BAAALgADCgQJCAAAAA==.',
Wa='Wagwan:BAAALgADCgEJAQABLgAECgkJFAAgAEcTAA==.Wankfumuch:BAAALgADCgkJHwAAAA==.War:BAABLgAECn8hAAIVAAgJNiRRAQBKAwAVAAgJNiRRAQBKAwAAAA==.Warfury:BAAALgAECgQJCQAAAA==.Warrcriminal:BAAALgADCgcJDQABLgAECgYJDgAEAAAAAA==.Warros:BAAALgADCgIJAgAAAA==.Watchnu:BAAALgAECgIJBAAAAA==.',
Wh='Whät:BAAALgADCgYJBgABLgAECgYJEAAEAAAAAA==.',
Wi='Willhelmina:BAAALgADCgcJCwABLgAECgcJGAABABIeAA==.Willowhite:BAAALgAECgMJBAAAAA==.',
Wo='Wockyslush:BAABLgAECn8XAAIUAAcJ2BIpIQApAQAUAAcJ2BIpIQApAQAAAA==.Wolfrin:BAAALgAECgMJAwAAAA==.Worgonfreman:BAAALgADCgcJEAAAAA==.Workplox:BAAALgAECgYJEAAAAA==.',
Wu='Wubers:BAABLgAECn8cAAMBAAgJZSA7CwDFAgABAAgJZSA7CwDFAgAUAAEJghRLLwFDAAAAAA==.Wubrs:BAAALgAECgYJDAABLgAECggJHAABAGUgAA==.Wulfjin:BAAALgAECgYJEAAAAA==.Wunderboi:BAAALgAECgcJCQAAAA==.',
Xe='Xellie:BAAALgAECgIJAwAAAA==.',
Xu='Xumexania:BAAALgADCgcJCAAAAA==.',
Ya='Yakisoba:BAAALgADCgUJBQAAAA==.Yanagi:BAAALgAECgYJBgABLgAECggJGAAFADIgAA==.',
['Yå']='Yåmatohime:BAAALgAECgQJBwABLgAECgYJEAAEAAAAAA==.',
Za='Zandrood:BAAALgADCggJDQABLgAECgQJBwAEAAAAAA==.Zaremis:BAABLgAECn8hAAMTAAgJzCGBCwDHAgATAAgJzCGBCwDHAgALAAIJIRlIbQCOAAAAAA==.Zathore:BAAALgADCgkJFAAAAA==.Zayehuo:BAAALgAECgEJAQAAAA==.',
Ze='Zeeni:BAAALgADCgYJBgAAAA==.Zelio:BAAALgADCgMJAwAAAA==.Zelphie:BAAALgAECgUJCgAAAA==.Zemtor:BAAALgAECgUJDwAAAA==.Zengadormu:BAAALgAECgMJBAAAAA==.Zerase:BAABLgAECn8aAAMaAAgJ4R7/AAC7AgAaAAcJqCL/AAC7AgAZAAEJ1gNKZQAuAAAAAA==.Zerttrak:BAAALgAECgYJDQAAAA==.Zeryon:BAAALgADCgYJBgAAAA==.',
Zh='Zhay:BAAALgAECgQJBAAAAA==.Zhonglö:BAAALgADCgIJAgAAAA==.',
Zi='Zippityzap:BAAALgADCgMJAwAAAA==.Zitawitch:BAAALgAECgYJCgAAAA==.Zivot:BAAALgAECgEJAQAAAA==.',
Zo='Zodiak:BAAALgAECgQJCwAAAA==.Zomal:BAAALgAECgQJBAAAAA==.',
Zu='Zugzug:BAAALgAECgkJCAAAAA==.Zuladan:BAAALgADCgYJCwAAAA==.',
['Æl']='Ælin:BAAALgAECgUJDgAAAA==.',
['Ër']='Ërâgnõr:BAABLgAECn8YAAIKAAgJMx2SJgCiAgAKAAgJMx2SJgCiAgAAAA==.',
['Ðe']='Ðemonyx:BAAALgAECgUJBQAAAA==.',
['Øk']='Økrit:BAAALgAECgYJEwAAAA==.',
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

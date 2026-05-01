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

local lookup = {'Paladin-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','DeathKnight-Unholy','Shaman-Elemental','Rogue-Assassination','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','Warrior-Arms','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Druid-Feral','Druid-Balance','Rogue-Subtlety','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Priest-Shadow','Priest-Discipline','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Protection','Hunter-Survival','Warlock-Affliction','Monk-Brewmaster','Rogue-Outlaw','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaluah:BAAALgAECgQJBwAAAA==.',
Ab='Abc:BAAALgAECgEJAQABLgAECgkJIgABAEwTAA==.',
Ac='Accessdeez:BAAALgAECgUJBQAAAA==.Acmis:BAABLgAECn8bAAICAAgJPB9RAQBwAgACAAgJPB9RAQBwAgAAAA==.Acp:BAABLgAECn8YAAMDAAcJiRvrKQAOAgADAAcJsxrrKQAOAgAEAAMJPQsdbgCGAAAAAA==.',
Ad='Adomangma:BAAALgADCgkJCwAAAA==.',
Ae='Aedryth:BAAALgAECgEJAgABLgAECgQJBwAFAAAAAA==.Aeelan:BAAALgADCgMJAgAAAA==.Aeshael:BAAALgAECgMJBQAAAA==.Aetherconri:BAAALgADCgIJAgABLgAECgMJBAAFAAAAAA==.Aethrys:BAAALgAECgIJAQABLgAECgQJBwAFAAAAAA==.',
Ag='Aggro:BAAALgADCggJCAABLgAECgkJIgABAEwTAA==.',
Ai='Ailardrion:BAAALgADCgUJBQAAAA==.Airrose:BAAALgADCgcJBwAAAA==.',
Ak='Akilah:BAAALgADCgEJAQABLgAECgYJEgAFAAAAAA==.Akumaho:BAABLgAECn8aAAMGAAgJMiB0DgAGAwAGAAgJMiB0DgAGAwAHAAEJXxLUcQA0AAAAAA==.Akurantirea:BAAALgAECgMJAwAAAA==.Akusephine:BAABLgAECn8XAAIIAAYJSB1oGACmAQAIAAYJSB1oGACmAQAAAA==.',
Al='Alayndia:BAAALgAECgQJBwAAAA==.Aldenteween:BAAALgAECgEJAQAAAA==.Aldonya:BAAALgAECgQJCAAAAA==.Alexxia:BAAALgADCggJCgAAAA==.Allise:BAAALgAECgcJDwAAAA==.Alougim:BAAALgADCgYJBwAAAA==.Aluia:BAAALgADCgkJDgAAAA==.Alva:BAAALgAECgYJDQAAAA==.Alystraza:BAAALgADCgIJBAAAAA==.Aléthia:BAAALgAECggJEwAAAA==.',
Am='Amkhara:BAAALgADCgYJCQAAAA==.',
An='Anathemá:BAAALgAECgYJDwAAAA==.Anduriel:BAAALgADCgEJAQAAAA==.Ange:BAAALgAECggJDwAAAA==.Angrøn:BAAALgAECgIJAgAAAA==.Anjo:BAAALgADCgcJBwAAAA==.Ankleblaster:BAAALgAECgEJAQABLgAECggJJgAJAOEhAA==.Antigen:BAAALgAECgIJAgAAAA==.',
Ap='Apawcalypse:BAAALgAECgEJAgAAAA==.',
Ar='Arak:BAAALgAECgEJAgAAAA==.Araoppai:BAAALgAECgcJEQAAAA==.Arfur:BAAALgADCgUJBQAAAA==.Arianndda:BAABLgAECn8WAAIKAAgJpQf1NgBhAQAKAAgJpQf1NgBhAQAAAA==.Arin:BAABLgAECn8rAAILAAgJvCTrBQDBAgALAAgJvCTrBQDBAgAAAA==.Artleandra:BAAALgAECgYJDwAAAA==.',
As='Asha:BAABLgAECn8UAAIMAAYJTSNUJADuAQAMAAYJTSNUJADuAQAAAA==.Ashwood:BAAALgAECgMJAwAAAA==.Asili:BAAALgADCgcJDAAAAA==.Askor:BAAALgAECgEJAQAAAA==.Asmodaes:BAAALgAECgkJAQABLgAFFAIJBQAJAM4TAA==.Assurance:BAAALgADCgYJBgAAAA==.Astela:BAABLgAECn8bAAIHAAYJvRlBBQB3AQAHAAYJvRlBBQB3AQAAAA==.',
At='Atraxa:BAAALgADCgEJAQAAAA==.Atulkaji:BAAALgADCgcJBwAAAA==.',
Au='Augmi:BAAALgAECgEJAQAAAA==.Auraia:BAAALgAECgQJBQAAAA==.Aurá:BAAALgAECgYJBwABLgAECggJHAANABghAA==.Autumn:BAAALgAECgYJCwAAAA==.',
Av='Avan:BAAALgAECgEJAQAAAA==.Avatan:BAABLgAECn8dAAIOAAcJrQb9KAD9AAAOAAcJrQb9KAD9AAAAAA==.Avecrusade:BAAALgAECgcJCgAAAA==.Avedeath:BAAALgAECgQJBwAAAA==.Averlis:BAABLgAECn8ZAAIJAAcJeArmMgAOAQAJAAcJeArmMgAOAQAAAA==.',
Aw='Aweburn:BAAALgAFFAEJAQAAAA==.',
Az='Azenezin:BAAALgAECgEJAQAAAA==.Azulena:BAAALgAECgEJAQAAAA==.',
Ba='Backpack:BAAALgAECgcJEAAAAA==.Badderdragon:BAACLgAFFH8HAAIPAAMJ0hSBDgDcAAAPAAMJ0hSBDgDcAAAuAAQKfy0AAw8ACAnoIY0BAN0CAA8ACAnoIY0BAN0CABAAAQnkAtJEACMAAAAA.Badmrmittens:BAAALgAECggJEAAAAA==.Badmuffin:BAABLgAECn8bAAIDAAgJ3BKVGQDHAQADAAgJ3BKVGQDHAQAAAA==.Balamuth:BAAALgAECgQJBAAAAA==.Balzarion:BAAALgAECgQJBgAAAA==.Bandemicc:BAABLgAECn8jAAILAAkJHyLQHQDOAgALAAkJHyLQHQDOAgAAAA==.Bandrui:BAAALgADCgEJAgAAAA==.Banru:BAABLgAECn8pAAIRAAgJCBeyBADuAQARAAgJCBeyBADuAQAAAA==.Barnaclepan:BAAALgADCgYJCQAAAA==.',
Be='Bearlygrillz:BAABLgAECn8VAAISAAYJRRkGCwASAQASAAYJRRkGCwASAQAAAA==.Bearontoe:BAAALgADCggJCAAAAA==.Bedtimez:BAAALgADCgMJAwAAAA==.Beelzabub:BAAALgADCggJDgAAAA==.Beerrun:BAAALgAECgEJAQAAAA==.Berkstein:BAABLgAECn8bAAMTAAgJUhQ1CwDCAQATAAgJUhQ1CwDCAQAUAAMJmQj2WABrAAAAAA==.',
Bi='Biggisnicker:BAABLgAECn8oAAIGAAgJvhxkEwAJAgAGAAgJvhxkEwAJAgAAAA==.Bigin:BAABLgAECn8bAAIDAAgJRxZfGwC7AQADAAgJRxZfGwC7AQAAAA==.Bigspriesty:BAAALgAECgQJBAAAAA==.Billhilly:BAAALgADCgIJAgAAAA==.Billyblanks:BAABLgAECn8ZAAMVAAYJbQzDXQAhAQAVAAYJbQzDXQAhAQAWAAUJmwMFEQCxAAAAAA==.Bimbom:BAABLgAECn8WAAIXAAYJ6R92CQA/AgAXAAYJ6R92CQA/AgAAAA==.Bimbomz:BAAALgAECgYJBgAAAA==.Biophysics:BAABLgAECn8iAAQSAAcJXh0/CQAQAgASAAcJXh0/CQAQAgAYAAMJ6A4tJgCgAAAZAAIJMhEpagB4AAAAAA==.',
Bl='Blackdoom:BAAALgAECgQJBAAAAA==.Bladestein:BAAALgAECgYJCQAAAA==.Bleebloop:BAAALgAECgQJBAABLgAECggJIwAaADAiAA==.Blightstone:BAAALgADCgcJBwAAAA==.Bloodemperor:BAAALgAECgMJAwAAAA==.Bluemountain:BAAALgADCgYJBgAAAA==.',
Bo='Boodylicious:BAAALgAECgEJAQAAAA==.Booshh:BAAALgAECgIJAgAAAA==.Boshi:BAAALgADCgYJCQAAAA==.',
Br='Brahmin:BAAALgADCgcJDQAAAA==.Brassticus:BAABLgAECn8lAAIbAAgJBiB+CwDHAgAbAAgJBiB+CwDHAgAAAA==.Breanan:BAAALgAECgMJBAABLgAECgQJBwAFAAAAAA==.Brew:BAAALgADCgcJCgAAAA==.Brewsader:BAAALgADCgMJAwABLgAECggJJgAJAOEhAA==.Brise:BAAALgAECgYJDwAAAA==.Brucewee:BAAALgADCgIJAgABLgAECgUJBQAFAAAAAA==.',
Bu='Bubblemelons:BAAALgAECgcJEQAAAA==.Buddhamonk:BAAALgADCgcJDQAAAA==.Buddhi:BAABLgAECn8UAAQBAAgJDSBoDAC3AgABAAgJDSBoDAC3AgAcAAIJ+B6zrABVAAAdAAEJ1AYZKgAmAAAAAA==.Buddhïst:BAAALgAECgMJAwAAAA==.Burlan:BAAALgAECgEJAQAAAA==.Burrhas:BAAALgADCgQJBAAAAA==.Buzzbolt:BAAALgADCgEJAQAAAA==.',
Bw='Bwonsally:BAAALgADCgcJCgAAAA==.',
['Bí']='Bítten:BAAALgADCgIJAgAAAA==.',
Ca='Cacashosho:BAAALgAECgcJDwAAAA==.Cahlamity:BAAALgAECgUJCgABLgADCgcJBwAFAAAAAA==.Cahlcifer:BAABLgAECn8oAAIPAAgJvhqUAwBYAgAPAAgJvhqUAwBYAgABLgADCgcJBwAFAAAAAA==.Cahlm:BAAALgADCgcJBwAAAA==.Caity:BAAALgAECgMJAwAAAA==.Cakke:BAAALgADCgIJAwAAAA==.Calamy:BAAALgADCgcJDQAAAA==.Calkestis:BAAALgADCggJCAAAAA==.Candre:BAABLgAECn8mAAIdAAgJGx4NCQBEAgAdAAgJGx4NCQBEAgAAAA==.Candyears:BAAALgADCgYJBgAAAA==.Capii:BAAALgAECgYJBwAAAA==.Capristal:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.Caraxxes:BAAALgADCgkJDgAAAA==.Cardiac:BAAALgADCggJDAAAAA==.Cardora:BAAALgAECgEJAQAAAA==.Carrian:BAAALgAECgEJAQABLgAECgcJGwAaAHMiAA==.Cassielia:BAABLgAECn8hAAIJAAgJYxW0FQDWAQAJAAgJYxW0FQDWAQAAAA==.Catmint:BAAALgAECgcJDgAAAA==.',
Ce='Ceb:BAAALgAECgMJBAAAAA==.',
Ch='Chariot:BAAALgAECgQJBAAAAA==.Charkycc:BAAALgAECgQJBAAAAA==.Chay:BAABLgAECn8fAAMGAAgJixYqJACgAQAGAAcJlxgqJACgAQAHAAIJQwppUgB3AAAAAA==.Chaylin:BAAALgADCgMJBAAAAA==.Chel:BAABLgAECn8hAAIeAAcJxRqDCgDiAQAeAAcJxRqDCgDiAQAAAA==.Chickenuggie:BAAALgAECgEJAQAAAA==.Chiharu:BAAALgADCgUJBAAAAA==.Chiji:BAAALgAECgYJCwAAAA==.Chillen:BAABLgAECn8ZAAIaAAYJuBvNDwByAQAaAAYJuBvNDwByAQAAAA==.Chivo:BAAALgAECgYJCgAAAA==.Chopu:BAABLgAECn8UAAIOAAcJ/RN5EwCaAQAOAAcJ/RN5EwCaAQAAAA==.Chrystabella:BAAALgADCgQJBAAAAA==.Chyna:BAAALgAECgYJDwAAAA==.',
Ci='Ciaani:BAACLgAFFH8HAAIdAAQJmhhIAQBKAQAdAAQJmhhIAQBKAQAuAAQKfxcAAx0ACQmpG8YBAI0CAB0ACQmpG8YBAI0CAAEAAwkeCHh9AIQAAAAA.Cibø:BAAALgAECgYJEAAAAA==.Cinnacism:BAAALgAECgUJBwAAAA==.',
Cl='Claymonic:BAAALgAECgcJEAAAAA==.Cleric:BAAALgADCgkJDwABLgAECgYJCgAFAAAAAA==.Clip:BAAALgADCgcJBwABLgAECgkJFwAaAE8fAA==.Clóud:BAAALgAECgMJAwAAAA==.Clõud:BAAALgAECgcJBwAAAA==.',
Co='Cococolalaw:BAAALgAECgEJAQAAAA==.Comah:BAAALgAECgYJBgABLgAECgYJEQAFAAAAAA==.Conc:BAAALgAECgcJBwAAAA==.Coresh:BAAALgAECgEJAQAAAA==.Corppor:BAAALgADCgIJAgAAAA==.',
Cp='Cptkush:BAABLgAECn8uAAIcAAgJXSBjEAA6AgAcAAgJXSBjEAA6AgAAAA==.',
Cr='Crankash:BAAALgADCgEJAQAAAA==.Crazylikafox:BAAALgAECgkJCwAAAA==.Crazynip:BAABLgAECn8fAAIBAAgJ9R34AgDfAgABAAgJ9R34AgDfAgAAAA==.Crickit:BAABLgAECn8UAAIJAAgJ6BZQHACdAQAJAAgJ6BZQHACdAQAAAA==.Crickét:BAAALgAECgEJAwABLgAECggJFAAJAOgWAA==.Crickêt:BAAALgAECgEJAQABLgAECggJFAAJAOgWAA==.Crickët:BAAALgAECgEJBAABLgAECggJFAAJAOgWAA==.Crikit:BAAALgAECgEJBAABLgAECggJFAAJAOgWAA==.Crrioth:BAABLgAECn8mAAICAAgJVBknAwDuAQACAAgJVBknAwDuAQAAAA==.Crypticál:BAAALgADCgcJCgABLgAECgQJBAAFAAAAAA==.',
Cu='Cubanito:BAAALgADCgIJAgAAAA==.Cubmyrotch:BAABLgAECn8gAAISAAkJPB6qAwDOAgASAAkJPB6qAwDOAgAAAA==.Cuiscuis:BAAALgAECgYJBgAAAA==.Cujo:BAABLgAECn8mAAIMAAgJpRmcCAAWAgAMAAgJpRmcCAAWAgAAAA==.Curiousgeorg:BAAALgAECgIJAwAAAA==.',
Cy='Cyanidesun:BAABLgAECn8ZAAMBAAgJygSVIQA6AQABAAgJygSVIQA6AQAcAAEJXQcAAAAAAAAAAA==.Cybre:BAAALgAECgYJDgAAAA==.Cyndil:BAABLgAECn8WAAIHAAcJGQ1hCAAoAQAHAAcJGQ1hCAAoAQAAAA==.Cyswarf:BAAALgADCgIJAgAAAA==.',
['Cä']='Cästiel:BAAALgAECgUJCAAAAA==.',
['Cø']='Cørgi:BAABLgAECn8cAAILAAgJ4R1wDQBZAgALAAgJ4R1wDQBZAgAAAA==.',
Da='Daddey:BAAALgADCgEJAQABLgAECgcJCQAFAAAAAA==.Daesyn:BAAALgAECgEJAQAAAA==.Daleus:BAABLgAECn8mAAIOAAgJKhUgEAC6AQAOAAgJKhUgEAC6AQAAAA==.Dalgn:BAAALgAECgYJBgAAAA==.Dallei:BAAALgAECgcJEQAAAA==.Darcane:BAABLgAECn8tAAMHAAgJwRPzCwADAgAHAAgJwRPzCwADAgAGAAQJFQY3awC3AAAAAA==.Darctanian:BAAALgAECgQJBgAAAA==.Darkchaos:BAAALgADCgcJBwAAAA==.Darktitomonk:BAAALgAECgIJAwAAAA==.Darkvayne:BAABLgAECn8TAAIDAAcJyx4KEgADAgADAAcJyx4KEgADAgAAAA==.Darkzulu:BAAALgADCgYJBAAAAA==.Dathrel:BAAALgADCggJIAAAAA==.Dawnfather:BAAALgADCgkJFAAAAA==.',
De='Deceiver:BAABLgAECn8cAAIcAAcJsBMMLwCFAQAcAAcJsBMMLwCFAQAAAA==.Deeanna:BAABLgAECn8UAAIbAAUJoAmTPwCuAAAbAAUJoAmTPwCuAAAAAA==.Deemanhunter:BAAALgADCgEJAQAAAA==.Def:BAAALgAECgYJDgAAAA==.Dek:BAACLgAFFH8HAAMfAAMJ5x9FCQAsAQAfAAMJ5x9FCQAsAQAgAAEJZRPVGABNAAAuAAQKfywAAyAACAnuGq0NAF8CACAACAnuGq0NAF8CAB8ACAk7Ih4FAEsCAAAA.Deleitlama:BAAALgAECgMJAwAAAA==.Delisius:BAAALgAECgEJAQAAAA==.Demonhellish:BAAALgAECgUJCwAAAA==.Demonnova:BAABLgAFFH8KAAIIAAYJSBXqBgCFAQAIAAYJSBXqBgCFAQAAAA==.Denary:BAAALgAECgcJEwAAAA==.Denleader:BAAALgAECgQJBAAAAA==.Dessertname:BAAALgAFFAIJAgABLgAFFAMJBQAIADIRAA==.Devinity:BAAALgAECgMJAwAAAA==.Dezsp:BAACLgAFFH8PAAIfAAUJgiC4AgCPAQAfAAUJgiC4AgCPAQAuAAQKfyYAAh8ACAkkJakEAEkDAB8ACAkkJakEAEkDAAAA.',
Dg='Dghunter:BAABLgAECn8oAAMDAAgJFAdLKgBsAQADAAgJFAdLKgBsAQAEAAUJ+QBOfABTAAAAAA==.',
Dh='Dhrat:BAABLgAECn8dAAIhAAgJgRAzCwCKAQAhAAgJgRAzCwCKAQABLgAECgcJBwAFAAAAAA==.',
Di='Diarana:BAAALgAECgUJCgAAAA==.Diggus:BAAALgADCgIJAgAAAA==.Dimsum:BAAALgAECgcJDgABLgAECgcJFAAiAPkQAA==.Dino:BAAALgADCgEJAQAAAA==.Dippÿ:BAAALgADCgMJAwAAAA==.',
Do='Docsored:BAAALgAECgUJCAAAAA==.Doomcoom:BAAALgAECgcJCQABLgAECgcJGQABAGIRAA==.Dovul:BAAALgADCgcJDAAAAA==.',
Dr='Dragn:BAABLgAECn8WAAIeAAYJBRUGHQAXAQAeAAYJBRUGHQAXAQAAAA==.Dragnalus:BAAALgAFFAIJAgAAAA==.Dragnas:BAABLgAECn8lAAIjAAgJKR5eAwBXAgAjAAgJKR5eAwBXAgAAAA==.Dragniperake:BAABLgAECn8cAAIBAAcJXRvMHQAoAgABAAcJXRvMHQAoAgAAAA==.Dragnspawn:BAAALgADCgQJBAAAAA==.Dragondees:BAAALgADCgEJAQABLgAFFAMJBwAfAOcfAA==.Dragonflare:BAAALgADCgMJAwAAAA==.Drakespawn:BAABLgAECn8fAAMPAAgJlRVuBAAvAgAPAAgJlRVuBAAvAgAQAAYJqA7UHQA/AQAAAA==.Draxonic:BAAALgADCgEJAQAAAA==.Drdots:BAABLgAECn8qAAIGAAgJDhrgGgDUAQAGAAgJDhrgGgDUAQAAAA==.Dreadnaunt:BAABLgAECn8ZAAIjAAcJthbXCQCPAQAjAAcJthbXCQCPAQAAAA==.Drewed:BAABLgAECn8fAAIJAAcJ1RJuJwBMAQAJAAcJ1RJuJwBMAQAAAA==.Drugral:BAACLgAFFH8IAAILAAMJsRaOMgD8AAALAAMJsRaOMgD8AAAuAAQKfy0AAgsACAkLIxgLAHMCAAsACAkLIxgLAHMCAAAA.Druidspider:BAAALgAECgIJAgAAAA==.Drundar:BAAALgAECgQJBwAAAA==.Druíd:BAAALgAECgYJEwAAAA==.Dryad:BAABLgAECn8hAAIJAAgJ0AcCLQAsAQAJAAgJ0AcCLQAsAQAAAA==.',
Du='Dugronn:BAABLgAECn8nAAIjAAgJTiCeAgB5AgAjAAgJTiCeAgB5AgAAAA==.',
Dw='Dwarfvadar:BAABLgAECn8VAAIiAAgJYhJPHQBgAQAiAAgJYhJPHQBgAQAAAA==.',
['Dî']='Dîabló:BAAALgAECgMJAwAAAA==.',
Ea='Eadric:BAABLgAECn8iAAIcAAgJXxr7GwDiAQAcAAgJXxr7GwDiAQAAAA==.',
Eg='Eggfupunch:BAAALgAECgQJCAAAAA==.Eggrow:BAAALgADCggJEwAAAA==.',
El='Elanthemage:BAABLgAECn8bAAIbAAgJGxwXBgCOAgAbAAgJGxwXBgCOAgAAAA==.Eleison:BAACLgAFFH8UAAIfAAUJ+h+hAgDQAQAfAAUJ+h+hAgDQAQAuAAQKfx0AAh8ACQlYI34FADgDAB8ACQlYI34FADgDAAAA.Ellesperis:BAABLgAECn8XAAIkAAcJqgqJEQBLAQAkAAcJqgqJEQBLAQAAAA==.Ellramy:BAAALgAECgEJAQAAAA==.Ellumon:BAACLgAFFH8FAAIUAAMJTR2rDQABAQAUAAMJTR2rDQABAQAuAAQKfyIAAhQACAksJeMCAFMDABQACAksJeMCAFMDAAAA.',
En='Enazicus:BAAALgAECgEJAQABLgAFFAYJCgAIAEgVAA==.Enkï:BAAALgAECgUJBQAAAA==.',
Eo='Eotteoke:BAABLgAECn8mAAMJAAgJ4SEcCgBoAgAJAAgJ4SEcCgBoAgAZAAIJJxZOaACAAAAAAA==.',
Ep='Epicwar:BAAALgADCgQJBAAAAA==.',
Er='Eragôn:BAABLgAECn8YAAMeAAcJ7xqTCwDPAQAeAAcJ7xqTCwDPAQAQAAEJAAA6OQBPAAAAAA==.Erinyes:BAABLgAECn8eAAIkAAgJRQVeDwBpAQAkAAgJRQVeDwBpAQAAAA==.',
Es='Estee:BAABLgAECn8VAAMKAAgJyxkxGQATAgAKAAgJyxkxGQATAgAgAAMJGwhHKACNAAAAAA==.',
Ev='Evoked:BAABLgAECn8YAAMPAAgJPwHUEwC+AAAPAAgJPwHUEwC+AAAeAAYJ6QDFUwB3AAAAAA==.',
Ex='Exarkune:BAAALgADCgMJAwAAAA==.Executioner:BAAALgAECgQJBAAAAA==.',
Ez='Ezreth:BAAALgAECgEJAQAAAA==.Ezuri:BAAALgADCgQJBAAAAA==.',
Fa='Faoladhconri:BAAALgAECgMJBAAAAA==.Fatfish:BAAALgAECgYJCgAAAA==.Fatty:BAABLgAECn8iAAIUAAgJeByYBwBBAgAUAAgJeByYBwBBAgABLgAECgkJIgABAEwTAA==.',
Fe='Felpine:BAAALgAECgcJAQAAAA==.Feul:BAABLgAECn8ZAAMbAAgJFR/rCADnAgAbAAgJFR/rCADnAgAMAAMJQxTKYQC8AAAAAA==.Feuldrasil:BAAALgADCgYJBgAAAA==.Feyded:BAAALgAECgYJEwAAAA==.Feylis:BAAALgAECgEJAQABLgAECgYJGwAHAL0ZAA==.',
Fi='Fiasko:BAABLgAECn8nAAIOAAgJ9CDvAgCqAgAOAAgJ9CDvAgCqAgAAAA==.Fiir:BAAALgADCgkJFgAAAA==.Finebaum:BAAALgAECgQJBAAAAA==.Firedup:BAAALgADCgcJDgAAAA==.Firehawk:BAAALgADCgUJBQAAAA==.Firêfly:BAAALgAECgEJAQABLgAECggJFAAJAOgWAA==.',
Fl='Flarefstrot:BAAALgAECgQJCQAAAA==.Flippÿ:BAAALgAECgYJBwAAAA==.Florax:BAAALgADCgUJBQAAAA==.Flotila:BAAALgADCgQJBAAAAA==.Fluffythecup:BAABLgAECn8VAAMeAAgJahBxEACLAQAeAAgJahBxEACLAQAQAAIJlgpKOQBPAAAAAA==.',
Fo='Forgedflame:BAAALgAECggJCgAAAA==.Formidonis:BAABLgAECn8iAAMGAAgJSyGXEAD2AgAGAAgJSyGXEAD2AgAlAAMJgSICFgDTAAAAAA==.',
Fr='Fraudcheese:BAAALgAECgQJBQABLgAECgYJDAAFAAAAAA==.Frostfyre:BAAALgADCgcJBwAAAA==.Frostjax:BAAALgADCgYJBgAAAA==.Frostyna:BAAALgAECgYJDAAAAA==.',
Fu='Fulgur:BAAALgAECggJEwAAAA==.Funshine:BAAALgADCgcJBwAAAA==.Funsizegurly:BAABLgAECn8iAAMWAAgJYxhkBAAHAgAWAAcJNxdkBAAHAgAVAAcJ2wuiUwA5AQAAAA==.Furyfighter:BAAALgADCgMJAwAAAA==.',
Ga='Galihath:BAAALgAECgMJAwAAAA==.Gallasdk:BAAALgADCgMJAwAAAA==.Gallypotter:BAACLgAFFH8FAAIDAAIJrw+jGQCgAAADAAIJrw+jGQCgAAAuAAQKfx8AAgMABwmJGzsiADgCAAMABwmJGzsiADgCAAAA.Gander:BAAALgADCggJEQAAAA==.Garopp:BAAALgADCgEJAQAAAA==.Garygabagool:BAABLgAECn8pAAIXAAgJyyNaAQCbAgAXAAgJyyNaAQCbAgAAAA==.Gawdspet:BAAALgAECgcJEwAAAA==.',
Ge='Geobeanz:BAABLgAECn8WAAIGAAgJJQThWwDeAAAGAAgJJQThWwDeAAAAAA==.Geoffreey:BAAALgAECgYJEQAAAA==.',
Gl='Glyn:BAAALgAECgQJBgAAAA==.',
Gn='Gnatytoop:BAABLgAECn8mAAMOAAgJOhSGDwDBAQAOAAgJIxOGDwDBAQAjAAYJbBJ6EAAaAQAAAA==.Gnawrly:BAABLgAECn8WAAIYAAcJmBHJCQBKAQAYAAcJmBHJCQBKAQAAAA==.Gneve:BAAALgAECgYJBgAAAA==.',
Go='Gogurt:BAAALgAECggJEQAAAA==.Gotowork:BAABLgAECn8XAAMjAAgJgRpSDABHAgAjAAcJzB1SDABHAgAOAAEJuwassAAqAAAAAA==.Govrek:BAAALgAECgYJEQAAAA==.',
Gr='Greenguyman:BAABLgAECn8jAAILAAgJmB/eDABfAgALAAgJmB/eDABfAgAAAA==.Greenstone:BAAALgADCggJFAAAAA==.Grobyc:BAAALgADCgkJHwAAAA==.Groøt:BAABLgAECn8cAAMJAAgJlhmEQACgAQAJAAgJlhmEQACgAQAYAAUJZyCaBwCAAQAAAA==.Grïm:BAABLgAECn8mAAIVAAgJ0hotIwDcAQAVAAgJ0hotIwDcAQAAAA==.',
Gu='Guldanramsay:BAAALgAECgcJBgAAAA==.Guldont:BAAALgAECgQJBAAAAA==.Gunmetalgibz:BAAALgAECgcJAQAAAA==.Gunne:BAAALgADCgIJAwAAAA==.Gunsa:BAAALgADCgEJAQAAAA==.',
Ha='Hags:BAAALgAECgMJAwAAAA==.Halfblast:BAAALgADCgMJAwAAAA==.Halmi:BAAALgADCgMJAwABLgAFFAIJBQADAK8PAA==.Hankerchief:BAAALgADCgcJBwABLgAECggJIQAIABYdAA==.Hankering:BAABLgAECn8hAAQIAAgJFh3lCQA8AgAIAAgJFh3lCQA8AgACAAMJkxYhHgCXAAAhAAEJmx0abAA6AAAAAA==.Hankopher:BAAALgADCgMJAwABLgAECggJIQAIABYdAA==.Hankytanky:BAAALgADCgIJAgAAAA==.Hanziè:BAAALgADCgIJAgAAAA==.Hapi:BAAALgAECgYJEQAAAA==.Haptics:BAABLgAECn8XAAMaAAkJTx/fFQBgAgAaAAgJpR/fFQBgAgANAAUJyBwhEAAOAQAAAA==.Harmonix:BAAALgAECgYJBgABLgAECggJEwAFAAAAAA==.Haruot:BAAALgADCgEJAQAAAA==.Hasbin:BAAALgAECgEJAQAAAA==.Hatsunari:BAAALgAECgIJAgAAAA==.Hawkelf:BAAALgADCgUJBQAAAA==.Hawkshot:BAAALgADCgYJBgAAAA==.',
He='Hecateis:BAAALgAECgUJCAAAAA==.Heenan:BAABLgAECn8iAAMOAAcJvwsvIwAfAQAOAAcJ8gYvIwAfAQAjAAUJEw4PFwDPAAAAAA==.Hellere:BAAALgAECgIJAgABLgAECggJIQAIABYdAA==.Hempknight:BAAALgAECgcJCQAAAA==.Herukas:BAAALgAECgQJBwAAAA==.Heímdall:BAAALgADCgUJBQAAAA==.',
Hi='Hikons:BAAALgADCgEJAQABLgAECgkJIgABAEwTAA==.Hironan:BAABLgAECn8nAAImAAgJihhcDQC2AQAmAAgJihhcDQC2AQAAAA==.',
Hn='Hnymanbadger:BAAALgAECgEJAQABLgAECggJHgAmANQNAA==.',
Ho='Holdmybear:BAAALgAECgMJBAAAAA==.Holyfudge:BAAALgAECgQJCwABLgAFFAEJAQAFAAAAAA==.Holyhyper:BAABLgAECn8jAAMcAAgJlB8fGQDTAgAcAAgJlB8fGQDTAgABAAQJxAFJdwCcAAAAAA==.Holyslanger:BAAALgADCgYJBgABLgAFFAIJBQAJAM4TAA==.Holywaddles:BAABLgAECn8WAAIBAAYJ/RHRIwAoAQABAAYJ/RHRIwAoAQAAAA==.Hookshot:BAAALgADCgIJAgAAAA==.Hope:BAEALgAECgUJBQABLgAFFAYJCAAgAAMPAA==.Hotfix:BAAALgADCgIJBAAAAA==.Hozax:BAAALgADCgYJBgAAAA==.Hozo:BAACLgAFFH8FAAMBAAIJ1BTVHQBlAAABAAIJ1BTVHQBlAAAcAAIJKgecQwBPAAAuAAQKfyMAAwEACAn+GeQXAFMCAAEACAn+GeQXAFMCABwACAlbFZtEABYCAAAA.Hozoyummy:BAAALgAECgUJBQAAAA==.',
Ht='Htownshawdo:BAAALgAECggJEwAAAA==.Htownworgen:BAAALgADCgkJCQAAAA==.',
Hu='Hubertus:BAAALgADCgcJCgAAAA==.Huntressa:BAAALgAECgEJAQAAAA==.',
Ic='Icesus:BAAALgADCgYJBgAAAA==.',
Ih='Ihatepriests:BAAALgADCgYJEQAAAA==.',
Il='Iloveluci:BAAALgADCgkJDgAAAA==.',
Io='Ioraa:BAABLgAECn8bAAIMAAgJvBfcDADOAQAMAAgJvBfcDADOAQAAAA==.',
Ip='Ip:BAAALgAECgEJAQABLgAFFAIJBQAJAM4TAA==.',
Ir='Ireumi:BAAALgADCgIJAgABLgAECggJJgAJAOEhAA==.Irishhammer:BAABLgAECn8bAAIjAAgJfxgKBgDzAQAjAAgJfxgKBgDzAQAAAA==.',
Ix='Ixalas:BAAALgAECgMJBgAAAA==.Ixias:BAAALgADCgkJDwAAAA==.Ixionath:BAAALgAECgUJCQAAAA==.',
Iz='Izaelith:BAAALgADCgEJAQAAAA==.',
['Iá']='Ián:BAACLgAFFH8FAAIGAAIJBhX2QAClAAAGAAIJBhX2QAClAAAuAAQKfyIAAwYACAljH3QLAFsCAAYACAljH3QLAFsCAAcABQmXHeUVAJsBAAAA.',
Ja='James:BAAALgAECgIJAgAAAA==.Janaloaf:BAAALgADCgQJBgAAAA==.Janq:BAABLgAECn8gAAIMAAgJLRmiFgBlAgAMAAgJLRmiFgBlAgAAAA==.Javok:BAAALgAECgEJAQAAAA==.',
Je='Jedwalethan:BAAALgADCgMJAwAAAA==.Jeniko:BAABLgAECn8UAAIjAAYJNhFNEgACAQAjAAYJNhFNEgACAQAAAA==.Jerrodsmage:BAAALgADCgcJBwAAAA==.Jext:BAAALgAFFAIJBAAAAA==.',
Ji='Jintulu:BAAALgADCgQJBAAAAA==.',
Jm='Jmc:BAAALgAECgUJBwAAAA==.',
Jo='Joedk:BAAALgAECggJCQAAAA==.Joeruid:BAAALgADCgYJBgAAAA==.Jollyjohn:BAAALgAECgcJEgAAAA==.Jonah:BAAALgADCgcJBgAAAA==.Jonesy:BAAALgAECgMJBgAAAA==.Jono:BAAALgADCgEJAQAAAA==.Jork:BAAALgADCgEJAQAAAA==.',
Jp='Jpglaive:BAABLgAECn8VAAIIAAgJkh+KDgAKAwAIAAgJkh+KDgAKAwAAAA==.',
Ju='Juisi:BAABLgAECn8ZAAMNAAgJXBnZAwCAAgANAAgJXBnZAwCAAgAaAAYJAxOPKgCoAQAAAA==.Juiski:BAAALgAECgMJAwAAAA==.Justania:BAABLgAECn8lAAMKAAgJDgjMNgBhAQAKAAgJDgjMNgBhAQAfAAcJHAdiIAD4AAAAAA==.',
['Já']='Jáque:BAABLgAECn8VAAIcAAYJ2QdGXAD9AAAcAAYJ2QdGXAD9AAAAAA==.',
Ka='Kaayle:BAAALgAECgQJCAAAAA==.Kadike:BAAALgAECgUJCAAAAA==.Kaela:BAAALgADCgUJBwAAAA==.Kaeloth:BAABLgAECn8pAAIcAAgJGSFQBwClAgAcAAgJGSFQBwClAgAAAA==.Kafaya:BAAALgAECgcJDwAAAA==.Kagome:BAAALgADCgYJCAAAAA==.Kalanar:BAAALgADCgEJAQAAAA==.Kaldh:BAAALgAECgYJDAABLgAECggJKQAcAHsdAA==.Kalebmonk:BAAALgAECgYJCQABLgAECggJKQAcAHsdAA==.Kalebpal:BAABLgAECn8pAAIcAAgJex39DQBTAgAcAAgJex39DQBTAgAAAA==.Kalen:BAAALgADCgYJBgAAAA==.Kamtano:BAABLgAECn8bAAILAAgJFhX/GwDgAQALAAgJFhX/GwDgAQAAAA==.Kardia:BAAALgADCgQJBAAAAA==.Karic:BAAALgAECgQJBAAAAA==.Karper:BAAALgAECgYJEAABLgAFFAIJBwAcAO8ZAA==.Kayaanu:BAABLgAECn8oAAIVAAgJlSXqBADuAgAVAAgJlSXqBADuAgAAAA==.Kazuld:BAAALgADCgEJAQAAAA==.',
Ke='Kegsmasher:BAAALgADCgkJCQAAAA==.Kellaine:BAAALgAECgIJAgAAAA==.Kellmonk:BAAALgAFFAIJAgAAAA==.Kelork:BAAALgADCgIJAgAAAA==.Kerethor:BAAALgADCgUJBQAAAA==.Kermora:BAAALgADCgYJDwAAAA==.',
Kh='Khalanos:BAABLgAECn8WAAMkAAcJvRM/EgBDAQAkAAcJvRM/EgBDAQAEAAEJvwW+kgAnAAAAAA==.Khazryl:BAAALgAECggJEwAAAA==.Khyzer:BAABLgAECn8gAAImAAgJ6A8cEwBvAQAmAAgJ6A8cEwBvAQAAAA==.',
Ki='Killershot:BAABLgAECn8fAAIDAAcJFCEiEAAWAgADAAcJFCEiEAAWAgAAAA==.Killián:BAAALgAECgYJDAAAAA==.Kirke:BAAALgADCgMJAwABLgAECggJHQAUAH0UAA==.Kirriana:BAABLgAECn8oAAIKAAgJ8CLlAQAAAwAKAAgJ8CLlAQAAAwAAAA==.Kirrie:BAAALgAECgEJAQAAAA==.',
Kk='Kkitty:BAAALgAECgQJBgAAAA==.',
Kl='Kletus:BAAALgAECgkJCwAAAA==.',
Ko='Kobs:BAAALgADCgUJBgAAAA==.Kombat:BAAALgAFFAMJAwAAAA==.Kongming:BAAALgAECgEJAQAAAA==.Korvash:BAAALgAECgYJDQAAAA==.Kosmos:BAAALgADCgYJBgAAAA==.Kostik:BAAALgAECgcJDAAAAA==.',
Kr='Kromgi:BAAALgADCgMJAwAAAA==.Kromgol:BAACLgAFFH8LAAIMAAQJ+BISCwA2AQAMAAQJ+BISCwA2AQAuAAQKfxsAAgwACQmWG3QQAKQCAAwACQmWG3QQAKQCAAAA.Krulos:BAAALgAECgcJDQAAAA==.',
Ku='Kua:BAAALgAECgMJAwAAAA==.Kushov:BAAALgADCgQJBAAAAA==.',
Kw='Kwende:BAABLgAECn8lAAIcAAgJYhj8HQDVAQAcAAgJYhj8HQDVAQAAAA==.',
Ky='Kyela:BAABLgAECn8ZAAIBAAgJOAozFwCWAQABAAgJOAozFwCWAQAAAA==.Kyndill:BAAALgADCgYJEAAAAA==.Kyriè:BAAALgAECgUJBQAAAA==.Kyrrith:BAAALgAECgUJDAAAAA==.Kyrtion:BAAALgAECgYJCgAAAA==.',
['Kø']='Kørupted:BAABLgAECn8YAAIGAAgJ1RO1MABoAQAGAAgJ1RO1MABoAQAAAA==.',
La='Lailis:BAAALgADCgEJAQABLgAECggJIgAgAJEiAA==.Lamiisa:BAAALgAECgYJEwAAAA==.Lanaya:BAABLgAECn8gAAIVAAcJmSIpFAA5AgAVAAcJmSIpFAA5AgAAAA==.Lankanau:BAAALgAECgIJAgAAAA==.Lapyy:BAAALgADCgEJAQAAAA==.Laurala:BAAALgADCgkJGgAAAA==.Laurandrel:BAABLgAECn8aAAIkAAcJXQkPEQBRAQAkAAcJXQkPEQBRAQAAAA==.Laved:BAABLgAECn8nAAMZAAkJTiUJAgDbAgAZAAkJTiUJAgDbAgAJAAYJwiQtEAARAgAAAA==.',
Ld='Ldkillsemm:BAAALgADCgYJCAAAAA==.',
Le='Leegandhi:BAAALgAECgUJBQAAAA==.Lewinn:BAAALgAECgYJEgAAAA==.',
Li='Lightrose:BAAALgAECgMJBQAAAA==.Likäbäws:BAAALgAECgIJAgAAAA==.Lilitü:BAAALgADCgcJCQAAAA==.Lilstaby:BAABLgAECn8XAAIaAAcJ4hdDHgAKAgAaAAcJ4hdDHgAKAgAAAA==.Lilya:BAABLgAECn8dAAIUAAgJfRR1EwB8AQAUAAgJfRR1EwB8AQAAAA==.Linossa:BAABLgAECn8cAAIVAAgJXRbPHgD0AQAVAAgJXRbPHgD0AQAAAA==.Liola:BAAALgAECgEJAgAAAA==.Lizardwizàrd:BAAALgAECgIJAgAAAA==.',
Lo='Lockycharms:BAAALgADCgcJCgAAAA==.Logikul:BAABLgAECn8kAAImAAgJfxeCDgCmAQAmAAgJfxeCDgCmAQAAAA==.Lookbak:BAABLgAECn8XAAMNAAYJCwPICwC+AAANAAYJCwPICwC+AAAnAAUJQQLJCgCiAAAAAA==.Lookiezi:BAABLgAECn8bAAIBAAkJpRywBwDyAgABAAkJpRywBwDyAgAAAA==.Lostriis:BAAALgADCgEJAQAAAA==.',
Lu='Lucidonis:BAABLgAECn8YAAIJAAcJUxn2EwDnAQAJAAcJUxn2EwDnAQAAAA==.Lucili:BAABLgAECn8dAAMGAAcJCg8nMABrAQAGAAcJCg8nMABrAQAHAAQJsgR3RQCgAAAAAA==.Luh:BAABLgAECn8bAAMDAAgJ0g1RIQCaAQADAAgJ0g1RIQCaAQAEAAEJ9QYGJAAuAAAAAA==.Lumira:BAAALgAECgUJCgAAAA==.Lunandriel:BAABLgAECn8uAAIaAAkJNRxvAgCaAgAaAAkJNRxvAgCaAgAAAA==.',
Ly='Lystia:BAABLgAECn8UAAIcAAcJzBc0IQDDAQAcAAcJzBc0IQDDAQAAAA==.',
['Lâ']='Lâdypantz:BAAALgADCgEJAQAAAA==.',
['Læ']='Læncelot:BAABLgAECn8XAAMUAAYJnQuvJADaAAAUAAYJnQuvJADaAAATAAIJFwq+agBjAAAAAA==.',
['Lú']='Lúná:BAAALgADCgMJAwAAAA==.',
Ma='Maalik:BAAALgADCgQJBAAAAA==.Madgoat:BAAALgAECgYJEwAAAA==.Madriel:BAAALgAECggJEwAAAA==.Maelune:BAAALgAECgYJCAABLgAECggJBQAFAAAAAA==.Mafanya:BAAALgAECgEJAQAAAA==.Magento:BAACLgAFFH8FAAIVAAMJfhs3LgAQAQAVAAMJfhs3LgAQAQAuAAQKfyMAAhUACAntIh0UADADABUACAntIh0UADADAAAA.Mailla:BAAALgADCgkJCQAAAA==.Maintankpov:BAAALgADCgQJBAAAAA==.Maladie:BAABLgAECn8fAAILAAgJaBDzJgCiAQALAAgJaBDzJgCiAQAAAA==.Malira:BAAALgAECgYJBwAAAA==.Malvaron:BAAALgADCgUJBQAAAA==.Mamoullian:BAAALgADCgQJBAAAAA==.Manmonk:BAABLgAECn8eAAImAAgJ1A3VEQB+AQAmAAgJ1A3VEQB+AQAAAA==.Manthellea:BAAALgADCgEJAQAAAA==.Marakanis:BAAALgADCggJCAAAAA==.Marsmerlot:BAAALgAECgQJBwAAAA==.Mastaquick:BAAALgAECgUJBQAAAA==.Mattank:BAABLgAECn8mAAMdAAkJ9BXuCQBmAQAcAAkJNxCbYwC7AQAdAAQJzB7uCQBmAQAAAA==.Mavzy:BAABLgAECn8cAAMlAAgJQAqTAwB8AQAlAAgJPQqTAwB8AQAHAAMJOQNQWwBdAAAAAA==.Mawey:BAAALgADCgYJBgAAAA==.Mayor:BAAALgADCgMJAwAAAA==.',
Mc='Mcbubbies:BAAALgAECgQJCgAAAA==.Mcfknkfc:BAAALgADCgkJEwAAAA==.',
Me='Meatydk:BAABLgAECn8ZAAILAAYJoCR2FQAOAgALAAYJoCR2FQAOAgAAAA==.Mechabuzz:BAAALgAECgYJCwAAAA==.Meech:BAACLgAFFH8GAAIRAAMJjBOJBwD3AAARAAMJjBOJBwD3AAAuAAQKfyUAAxEACAmTI3YBADYDABEACAkpInYBADYDAA4ABwnWHRArAAsCAAAA.Meeyoh:BAAALgADCgcJBwAAAA==.Mehrunedagon:BAAALgAECgYJCgAAAA==.Melchizedekk:BAAALgADCgMJAwAAAA==.Melnibonai:BAAALgADCgUJBQAAAA==.',
Mi='Michelena:BAAALgAECgUJBQAAAA==.Micti:BAABLgAECn8pAAIHAAgJSxS/AgDYAQAHAAgJSxS/AgDYAQAAAA==.Micycle:BAAALgAECgYJEgAAAA==.Miirra:BAAALgAECgMJAwAAAA==.Milamber:BAABLgAECn8UAAIVAAgJegeaUQA9AQAVAAgJegeaUQA9AQAAAA==.Milk:BAAALgAECggJCAABLgAECggJGgAGADIgAA==.Miniion:BAAALgAECgYJDAAAAA==.Minjiu:BAAALgAECgEJAQAAAA==.Minyon:BAABLgAECn8oAAIfAAgJ6yX9AAAMAwAfAAgJ6yX9AAAMAwAAAA==.Mir:BAAALgAECgMJAwAAAA==.Miruna:BAAALgAECgMJAwAAAA==.Misdirected:BAAALgADCgYJBgAAAA==.',
Mo='Modangles:BAAALgADCgMJAwAAAA==.Mommadragon:BAABLgAECn8ZAAIDAAYJAxNlOQAtAQADAAYJAxNlOQAtAQAAAA==.Momohirai:BAABLgAECn8mAAITAAgJ9hwGBgAxAgATAAgJ9hwGBgAxAgAAAA==.Monkhoe:BAAALgAECgYJCwABLgAECgkJLgAaADUcAA==.Monkinasuey:BAAALgAECgYJCgAAAA==.Monkspider:BAAALgAFFAIJAwAAAA==.Monsterdk:BAAALgAECgYJCQAAAA==.Moonerknight:BAABLgAECn8WAAILAAgJHRPeXQDZAQALAAgJHRPeXQDZAQAAAA==.Mordekaiser:BAAALgADCgMJAwAAAA==.Moshi:BAAALgAECgUJBQAAAA==.',
Ms='Msmoistmufin:BAAALgADCgUJBQAAAA==.',
Mu='Muggle:BAAALgADCgUJBQAAAA==.Mugoogaipan:BAAALgAECgcJDAAAAA==.Mugron:BAACLgAFFH8FAAMjAAMJ0xb8CADyAAAjAAMJ0xb8CADyAAAOAAEJSwFzJgA9AAAuAAQKfxsAAyMACAlFIgMEADsCACMACAlFIgMEADsCAA4AAQnzB3yiAD4AAAEuAAUUBgkZACIAECAA.',
My='Mynions:BAAALgADCgUJBQAAAA==.Myrarawr:BAAALgAECgUJBQAAAA==.Mystoril:BAAALgADCgkJDwAAAA==.Mythrandia:BAABLgAECn8iAAIKAAgJFB9uDQCBAgAKAAgJFB9uDQCBAgAAAA==.',
Na='Nadrael:BAAALgAECgEJAQAAAA==.Nappychan:BAAALgAECgQJCQAAAA==.Narae:BAAALgAECgYJBwABLgAFFAYJFgAGAIQaAA==.Narsissa:BAAALgADCgQJBAAAAA==.Narìko:BAAALgADCgYJBgABLgAECgYJEgAFAAAAAA==.Nazerem:BAAALgAECgYJDgAAAA==.Nazgothoth:BAAALgADCgMJAwAAAA==.',
Ne='Neebstrasza:BAAALgADCgkJFQAAAA==.Neeko:BAAALgAECgUJBQAAAA==.Nexmagus:BAAALgADCgMJAwAAAA==.',
Ni='Nichts:BAAALgADCgkJCQAAAA==.Nicklâus:BAAALgAECgEJAQAAAA==.Nicko:BAAALgADCgQJBAAAAA==.Nicodkemus:BAAALgAECgYJBgABLgAECggJKQAmAJgcAA==.Nicolius:BAAALgAECgYJBgABLgAECggJKQAmAJgcAA==.Nikfu:BAABLgAECn8pAAImAAgJmBy0BwAaAgAmAAgJmBy0BwAaAgAAAA==.Ningenalah:BAABLgAECn8gAAILAAgJECPqIAC9AgALAAgJECPqIAC9AgAAAA==.Ningendormu:BAAALgADCgUJBgAAAA==.Ningenurion:BAAALgAECgcJDQAAAA==.Nippÿ:BAABLgAECn8nAAIVAAgJhBsSFAA6AgAVAAgJhBsSFAA6AgAAAA==.Nixis:BAAALgAECggJEwAAAA==.',
No='Noobyasha:BAAALgAECgMJAwAAAA==.Norav:BAAALgADCgQJBAAAAA==.Nordryde:BAAALgAECgUJBQABLgAFFAQJCgAUAJ4WAA==.Nordrydm:BAACLgAFFH8KAAIUAAQJnhZMCwAkAQAUAAQJnhZMCwAkAQAuAAQKfxkAAhQACAmOHbcNAHkCABQACAmOHbcNAHkCAAAA.Nordrydpr:BAAALgADCggJAgABLgAFFAQJCgAUAJ4WAA==.Notoes:BAAALgADCgYJBgAAAA==.Noxeis:BAAALgADCgcJDAAAAA==.Noxes:BAABLgAECn8XAAINAAcJWQ2rBQBjAQANAAcJWQ2rBQBjAQAAAA==.Noxii:BAAALgADCgEJAgAAAA==.',
Nu='Nucess:BAAALgADCgIJAgABLgADCgkJDgAFAAAAAA==.Numericz:BAAALgAECgYJCgAAAA==.',
Nx='Nxs:BAAALgAECgcJDwAAAA==.',
Ny='Nylèi:BAAALgAECgEJAQAAAA==.',
['Nå']='Nå:BAABLgAECn8oAAIIAAgJJRucEQDhAQAIAAgJJRucEQDhAQABLgAFFAQJBwAdAJoYAA==.',
['Ní']='Níghtmäre:BAAALgAECgMJAwAAAA==.',
Oa='Oakshaler:BAAALgAECgYJEQAAAA==.',
Ob='Obsidium:BAAALgAECgIJAwABLgAECgcJGQABAGIRAA==.',
Oc='Ocris:BAAALgADCgMJAwAAAA==.',
Of='Offënsive:BAABLgAECn8gAAMjAAgJYBxWBwDMAQAOAAgJPBvwIABLAgAjAAgJ8BVWBwDMAQAAAA==.',
Ol='Olayhahla:BAABLgAECn8XAAIfAAgJTAquEgBwAQAfAAgJTAquEgBwAQAAAA==.Olila:BAAALgADCgYJBgAAAA==.Olivens:BAAALgADCgcJBwAAAQ==.',
Om='Ommie:BAAALgAECgUJBgAAAA==.Omun:BAAALgADCgEJAQAAAA==.',
On='Onè:BAAALgAECgEJAQABLgAFFAUJBgALAK8VAA==.',
Or='Ordek:BAAALgAECgQJBwAAAA==.',
Os='Osyrus:BAAALgADCgYJDQAAAA==.',
Pa='Paegusus:BAAALgADCgEJAQAAAA==.Pandybearz:BAABLgAECn8VAAIDAAcJHhh8HgCpAQADAAcJHhh8HgCpAQAAAA==.Pantyfa:BAAALgADCgYJBgAAAA==.Paraclete:BAAALgAECgcJDwAAAA==.Paraimee:BAAALgAECgEJAQAAAA==.Parkiepark:BAAALgADCgQJBAAAAA==.Pawtism:BAAALgADCgQJBAABLgAFFAMJBwAPANIUAA==.',
Pe='Pekkie:BAAALgADCgkJFQAAAA==.Percpapi:BAAALgADCgMJAwAAAA==.Pestis:BAAALgAECgcJDgAAAA==.',
Ph='Phallon:BAABLgAECn8YAAIYAAcJCwzfCQBHAQAYAAcJCwzfCQBHAQAAAA==.Phearia:BAAALgADCgQJBAAAAA==.',
Pi='Pi:BAABLgAECn8YAAIfAAcJ4hAtEQCAAQAfAAcJ4hAtEQCAAQAAAA==.Pidi:BAAALgAECgQJBAABLgAECggJIgAWAGMYAA==.Pindolino:BAAALgADCgMJAwAAAA==.Pingu:BAABLgAECn8lAAMLAAgJ3h6QDwBCAgALAAgJ3h6QDwBCAgAiAAEJWho8RAA4AAAAAA==.Pioree:BAACLgAFFH8LAAQeAAUJ0BJXDgA9AQAeAAUJ0BJXDgA9AQAQAAIJqgYRBACKAAAPAAEJAwFnGQA0AAAuAAQKfyoABBAACAmkICIBAGYCAB4ACAk2HZ4LAL0CABAACAkaHyIBAGYCAA8AAQmnCPdJAC4AAAAA.Piott:BAAALgADCgEJAQAAAA==.Pixieberry:BAAALgAECgYJEwAAAA==.',
Pl='Plimp:BAAALgADCgYJBgAAAA==.',
Po='Pokédex:BAAALgADCgYJAQAAAA==.Pookiebear:BAAALgAECgEJAwAAAA==.Porthub:BAAALgAECgMJAwAAAA==.',
Pp='Ppriest:BAAALgADCgIJAgAAAA==.',
Pr='Prandal:BAAALgADCgcJCwAAAA==.Praxithea:BAAALgADCgEJAQAAAA==.Preserves:BAAALgAECgEJAgAAAA==.Primechi:BAAALgADCgMJAwAAAA==.Priëst:BAAALgADCgEJAQAAAA==.Projecthorde:BAAALgADCgYJBgAAAA==.Pronouns:BAAALgAECgYJCgABLgAECggJIwALAB8dAA==.',
Ps='Pseudocheese:BAAALgADCgcJDQABLgAECgYJDAAFAAAAAA==.',
['Pä']='Päladont:BAAALgAECgEJAgAAAA==.',
['Pø']='Pø:BAAALgADCgYJBgABLgAECgUJBQAFAAAAAA==.',
Qe='Qe:BAAALgADCgMJAwAAAA==.',
Qu='Quadmonk:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Quanzanon:BAABLgAECn8aAAIJAAgJIQfxOwDiAAAJAAgJIQfxOwDiAAAAAA==.',
Ra='Rabiddad:BAAALgAECgYJEAAAAA==.Rachelrae:BAABLgAECn8jAAIKAAgJsA/SFABqAQAKAAgJsA/SFABqAQAAAA==.Raistlèe:BAAALgADCgIJAgAAAA==.Ramenwrapz:BAABLgAECn8YAAMKAAgJcSAUGQATAgAKAAgJcSAUGQATAgAfAAEJ1wIgRgApAAAAAA==.Rattybones:BAAALgADCgEJAQAAAA==.Rauiri:BAABLgAECn8WAAIcAAYJsgj7XQD5AAAcAAYJsgj7XQD5AAAAAA==.',
Re='Recessive:BAAALgAECgQJEQAAAA==.Reddynon:BAAALgAECgUJBQAAAA==.Reddìngton:BAAALgADCgUJBQAAAA==.Refeik:BAAALgAECgYJDgAAAA==.Reginald:BAABLgAECn8fAAIcAAgJ0xmzHwDLAQAcAAgJ0xmzHwDLAQABLgAECgYJFwAIAEgdAA==.Regrowth:BAAALgAECgMJAwAAAA==.Reikoku:BAAALgAECgYJCAAAAA==.Rejuva:BAAALgAECgMJBAAAAA==.Relinquo:BAABLgAECn8cAAMkAAgJ1yQ/AQBXAwAkAAgJ1yQ/AQBXAwAEAAEJDguUjwArAAAAAA==.Relse:BAAALgAECgQJCQAAAA==.Renika:BAABLgAECn8eAAMoAAcJBgrIAgBNAQAoAAcJ5wnIAgBNAQAVAAQJNgXXLgGjAAAAAA==.Resperea:BAAALgAECgQJBAAAAA==.Revwraith:BAAALgAECgcJCwAAAA==.',
Ri='Ricassou:BAABLgAECn8gAAImAAgJ9RipCAAEAgAmAAgJ9RipCAAEAgAAAA==.Ricochet:BAABLgAECn8UAAIDAAYJPBazTACDAQADAAYJPBazTACDAQAAAA==.Rinn:BAAALgADCgIJAgAAAA==.Riottmoon:BAAALgAECgcJEwAAAA==.Riptipped:BAAALgADCgYJBgAAAA==.Rivendell:BAAALgAFFAEJAQAAAA==.',
Ro='Roarr:BAAALgADCgMJAwABLgAECgEJAQAFAAAAAA==.Robloxrocks:BAAALgAECgUJBQAAAA==.Rogarn:BAAALgADCgUJBQAAAA==.Romi:BAAALgAECgYJDAABLgAECggJIQAIABYdAA==.Rook:BAAALgAECgcJDQAAAA==.Rorynne:BAAALgAECgYJEgAAAA==.Rotheion:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Rougenova:BAAALgADCgYJBgABLgAFFAYJCgAIAEgVAA==.',
Rr='Rrubio:BAAALgADCgkJCQAAAA==.',
Ru='Rucksack:BAABLgAECn8fAAIRAAgJchoeBgC/AQARAAgJchoeBgC/AQAAAA==.Rucy:BAEBLgAECn8nAAIZAAkJ6BENDQC8AQAZAAkJ6BENDQC8AQAAAA==.Rucybow:BAEALgADCgUJBQABLgAECgkJJwAZAOgRAA==.Ruend:BAAALgADCgIJAgAAAA==.',
Ry='Ryndkmc:BAAALgAECgMJBgABLgAECgQJCQAFAAAAAA==.',
['Ré']='Réfléx:BAAALgAECgYJCQAAAA==.',
Sa='Sacredmilk:BAAALgADCgEJAgAAAA==.Saeya:BAAALgAECgYJCQAAAA==.Sakurai:BAABLgAECn8cAAINAAgJGCGzAACsAgANAAgJGCGzAACsAgAAAA==.Salamander:BAABLgAECn8aAAMeAAgJSwqmKgBqAQAeAAgJSwqmKgBqAQAQAAQJOQLQNQBnAAAAAA==.Samirah:BAAALgADCgcJDgAAAA==.Sanotor:BAAALgADCgYJCQAAAA==.Santhras:BAAALgADCgQJBAAAAA==.Saristia:BAAALgAECgYJCQABLgAECggJGwACADwfAA==.Sattha:BAABLgAECn8UAAMiAAcJ+RBcHgBVAQAiAAYJhxNcHgBVAQALAAIJkQpnBwFnAAAAAA==.Saurmont:BAAALgAECgUJDwAAAA==.Savage:BAAALgADCgQJBAAAAA==.Savein:BAAALgAECgYJBwAAAA==.Saveu:BAAALgAECgQJCgAAAA==.',
Sc='Scalesofuwu:BAAALgAECgYJCwAAAA==.Scorpïon:BAABLgAECn8UAAINAAYJ2iB0BwDrAQANAAYJ2iB0BwDrAQAAAA==.Screampies:BAABLgAECn8ZAAIBAAcJYhHTHgBRAQABAAcJYhHTHgBRAQAAAA==.',
Se='Seagulls:BAEBLgAECn8TAAIIAAYJch3nJQBSAQAIAAYJch3nJQBSAQAAAA==.Seayaa:BAABLgAECn8bAAIDAAgJiAzdJACHAQADAAgJiAzdJACHAQAAAA==.Sejanuss:BAAALgAECgMJAwABLgAECgcJDQAFAAAAAA==.Selindia:BAAALgAECgIJAgAAAA==.Sellsword:BAAALgAECgIJAwAAAA==.Senadoria:BAAALgAECgQJBwAAAA==.Sewersliding:BAABLgAECn8UAAIeAAkJRxP8EABqAgAeAAkJRxP8EABqAgAAAA==.',
Sh='Shadowzangel:BAAALgAECgMJAwAAAA==.Shaedee:BAAALgADCggJCAAAAA==.Shammyshaga:BAABLgAECn8bAAIbAAcJYQ+tMAD8AAAbAAcJYQ+tMAD8AAAAAA==.Shampayne:BAAALgAECgQJBAAAAA==.Shattered:BAAALgAECgEJAQAAAA==.Sheeple:BAAALgAECgEJAgAAAA==.Shelina:BAAALgAECgEJAQAAAA==.Shen:BAAALgAECgYJEQAAAA==.Sheriff:BAACLgAFFH8SAAIIAAUJ3B78BgC0AQAIAAUJ3B78BgC0AQAuAAQKfxkAAggACQn0HlULACcDAAgACQn0HlULACcDAAEuAAQKBgkKAAUAAAAA.Shibito:BAABLgAECn8lAAIfAAgJ8BNPDwCVAQAfAAgJ8BNPDwCVAQAAAA==.Shilan:BAAALgADCgkJDwAAAA==.Shilihu:BAAALgADCgkJDgAAAA==.Shinukishin:BAABLgAECn8lAAILAAgJqSTqAwDwAgALAAgJqSTqAwDwAgAAAA==.Shiraga:BAAALgADCgcJEAAAAA==.Shivx:BAAALgAECgMJAwAAAA==.Shockaflokka:BAAALgADCgEJAQAAAA==.Shodomy:BAAALgAECgQJBwAAAA==.Shoebolt:BAAALgAECgEJAQAAAA==.Shorzy:BAABLgAECn8cAAIIAAgJ1x1qGACmAQAIAAgJ1x1qGACmAQAAAA==.Shreddeez:BAABLgAECn8cAAIYAAgJ3BsKAgBgAgAYAAgJ3BsKAgBgAgAAAA==.Shredzmage:BAAALgAECgIJAgAAAA==.Shygon:BAABLgAECn8pAAIMAAgJ7yRPBQBDAwAMAAgJ7yRPBQBDAwAAAA==.',
Si='Siek:BAAALgADCgMJAwABLgAECgcJDgAFAAAAAA==.Sienar:BAAALgAECgcJBwAAAA==.Sigmasmite:BAAALgADCgIJAgAAAA==.Simulacra:BAAALgAECgYJDAAAAA==.Sineya:BAAALgAECggJAgAAAA==.Sivienne:BAAALgADCgYJBgAAAA==.',
Sk='Skallock:BAABLgAECn8jAAIGAAcJHRJjKwB/AQAGAAcJHRJjKwB/AQAAAA==.',
Sl='Sleepfrostvv:BAAALgAECgYJDAAAAA==.Slimpikkinz:BAAALgAECgMJAwAAAA==.Slipnslide:BAAALgAECgQJCQAAAA==.Slogto:BAAALgADCgEJAQAAAA==.Slu:BAABLgAECn8jAAIVAAgJ9yL3FQAlAwAVAAgJ9yL3FQAlAwABLgAECgYJCgAFAAAAAA==.',
Sm='Smashinsmith:BAABLgAECn8pAAMRAAgJpBzKAgBDAgARAAgJQBzKAgBDAgAOAAcJtxHiRwCFAQAAAA==.Smokey:BAAALgAECgYJBgAAAA==.',
Sn='Snackpack:BAAALgAECgMJAwAAAA==.Snekprotek:BAAALgAECgUJCgAAAA==.Snockerz:BAAALgADCgYJBgAAAA==.Snoop:BAAALgADCgQJBAAAAA==.Snoopzxd:BAACLgAFFH8OAAIMAAQJYw+RDQAgAQAMAAQJYw+RDQAgAQAuAAQKfycAAgwACAltIGQTAIUCAAwACAltIGQTAIUCAAAA.Snowdancer:BAAALgAECgQJBQAAAA==.',
So='Socialist:BAAALgADCgIJAgABLgAECggJIAAmAOgPAA==.Sollina:BAAALgADCgcJBwAAAA==.Somno:BAABLgAECn8eAAMIAAgJzyGGDQAMAgAIAAgJzyGGDQAMAgAhAAYJRRTKKQB2AQAAAA==.Songito:BAAALgADCgQJBQAAAA==.Sophea:BAAALgADCgkJGQAAAA==.Soulfly:BAAALgAECgYJEQAAAA==.Soulsabi:BAABLgAECn8pAAMGAAkJdyPVCQAvAwAGAAkJdyPVCQAvAwAHAAIJmiOkOwDGAAAAAA==.Soulshaper:BAAALgAECgUJCAAAAA==.',
Sp='Spectral:BAABLgAECn8hAAIKAAgJOB73BwAuAgAKAAgJOB73BwAuAgAAAA==.Sperkk:BAAALgAECgcJEgAAAA==.Spiritwalk:BAAALgADCgUJBQAAAA==.Spoken:BAAALgADCgMJAwAAAA==.Spookyshark:BAAALgADCgUJBQAAAA==.Spookywacky:BAAALgADCgMJAwAAAA==.Spoonman:BAACLgAFFH8HAAIJAAMJ9AuDGgDHAAAJAAMJ9AuDGgDHAAAuAAQKfyMAAgkACAkpIYwEAOECAAkACAkpIYwEAOECAAAA.Spurk:BAABLgAECn8gAAMMAAgJVSDiCgDsAQAMAAcJPyTiCgDsAQAbAAYJ3hs0NQCvAQAAAA==.Spåwnkîll:BAAALgAECgYJEAAAAA==.',
St='Staceysmom:BAABLgAECn8ZAAIVAAgJyQG9oACFAAAVAAgJyQG9oACFAAAAAA==.Stardrift:BAAALgADCgcJCwAAAA==.Static:BAAALgAECgYJCgAAAA==.Stephen:BAAALgADCgUJBQAAAA==.Stere:BAAALgAECgYJDQAAAA==.Steve:BAAALgAECgcJBwAAAA==.Stinggrayjr:BAAALgAECgMJAwAAAA==.Stinkyfeets:BAAALgAECgEJAQABLgAECgYJEgAFAAAAAA==.Stonedborn:BAAALgAECgcJCAAAAA==.Storihbeg:BAAALgADCgcJCAABLgAECgYJCgAFAAAAAA==.Stox:BAAALgAECgYJDAAAAA==.Stärkiller:BAAALgADCgQJBQAAAA==.Stòrm:BAAALgADCgcJDQAAAA==.',
Su='Suenami:BAAALgAECgYJDAAAAA==.Sunon:BAAALgADCgMJAwAAAA==.Sunøn:BAAALgADCgUJCgAAAA==.Superhilock:BAACLgAFFH8IAAIGAAMJLBaAKgD2AAAGAAMJLBaAKgD2AAAuAAQKfysAAwYACAljJHcEANUCAAYACAljJHcEANUCAAcAAwlPH0IsAA0BAAAA.Supershenron:BAAALgAECgcJCQAAAA==.Surlyroach:BAAALgAECgEJAQAAAA==.',
Sv='Svelesstiá:BAAALgADCgcJGwAAAA==.',
Sw='Swan:BAABLgAECn8fAAIkAAgJWB56BQC0AgAkAAgJWB56BQC0AgABLgAFFAMJBwAVAPcHAA==.',
Sy='Sydneezy:BAABLgAECn8bAAIGAAcJPBO4OwBAAQAGAAcJPBO4OwBAAQAAAA==.Syrelliia:BAABLgAECn8hAAINAAgJ5hPSBgACAgANAAgJ5hPSBgACAgAAAA==.',
['Sæ']='Sævage:BAABLgAECn82AAIDAAgJ6x4sEgABAgADAAgJ6x4sEgABAgAAAA==.',
Ta='Taii:BAAALgADCgQJBAABLgAECgkJFAAeAEcTAA==.Taiigah:BAAALgAECgYJDAABLgAECgkJFAAeAEcTAA==.Taladage:BAAALgADCgMJAwAAAA==.Talendar:BAAALgADCgYJCwAAAA==.Talfrah:BAAALgADCgcJDwAAAA==.Tanrok:BAABLgAECn8bAAMVAAgJCg8lggDNAQAVAAgJQQ4lggDNAQAoAAcJ5gZzBwAKAQAAAA==.Tarnac:BAAALgAECgEJAQAAAA==.Tatertots:BAAALgAECggJEgAAAA==.Tazorface:BAABLgAECn8jAAQLAAgJHx3KGwDhAQALAAgJYxzKGwDhAQAiAAYJHh7pEwDRAQApAAEJVwnFDwA+AAAAAA==.',
Te='Techissue:BAAALgAECgEJAQAAAA==.Techtonich:BAAALgAECgYJEgAAAA==.',
Th='Tharkash:BAABLgAECn8YAAIMAAcJixvdCwDcAQAMAAcJixvdCwDcAQAAAA==.Thedockwho:BAABLgAECn8UAAIXAAcJVRSjBgCbAQAXAAcJVRSjBgCbAQAAAA==.Thedoctorwho:BAAALgAECgEJAQAAAA==.Thellarius:BAAALgADCgcJCQAAAA==.Thirdeye:BAAALgAECgEJAQAAAA==.Thoxic:BAAALgADCgYJCgABLgAECggJIAAmAOgPAA==.Thundermaw:BAAALgAECgEJAQAAAA==.',
Ti='Tibetan:BAAALgAECgUJBwABLgAECggJKQAcABkhAA==.Tigs:BAAALgADCggJEQAAAA==.Tildra:BAAALgAECgMJBwAAAA==.Timidity:BAABLgAECn8hAAMaAAgJqx52BwD7AQAaAAgJNx12BwD7AQANAAQJvRdODwAdAQAAAA==.',
To='Tomey:BAAALgADCgMJAwAAAA==.Tonyrona:BAAALgAECgYJCgAAAA==.Toolip:BAABLgAECn8gAAIBAAgJfh2HBQCRAgABAAgJfh2HBQCRAgAAAA==.Toothesayer:BAAALgADCgYJBgAAAA==.Tornwraith:BAABLgAECn8dAAMlAAYJ4RIfDgBRAQAlAAYJqA8fDgBRAQAHAAYJCQ0RKgAZAQAAAA==.Tovash:BAAALgAECgMJAwAAAA==.',
Tr='Trapsy:BAAALgAECgQJCAABLgAECggJFgALAB0TAA==.Trauma:BAAALgAECgcJEwAAAA==.Traumaspally:BAAALgADCgYJBgABLgAECgcJEwAFAAAAAA==.Trehuga:BAAALgAECgcJEgAAAA==.Triso:BAAALgAECgYJCgAAAA==.Trochanter:BAAALgADCgIJAgAAAA==.Tronus:BAAALgAECgEJAQAAAA==.Troodonus:BAABLgAECn8nAAIcAAkJAiK4BwCfAgAcAAkJAiK4BwCfAgAAAA==.',
Ts='Tsukaar:BAABLgAECn8YAAMjAAcJIRbXEgDcAQAjAAcJIRbXEgDcAQAOAAEJ/whvqQA0AAAAAA==.Tsunade:BAAALgAECgIJBAAAAA==.Tswift:BAABLgAECn8WAAMhAAcJZSLHAwBVAgAhAAcJZSLHAwBVAgAIAAEJNw/P4AAxAAAAAA==.',
Tu='Tutorialboss:BAABLgAECn8eAAQEAAgJUyCKEwCWAgAEAAgJ/R6KEwCWAgADAAIJbSQTUgDVAAAkAAEJ2hpIKQBOAAAAAA==.',
Tw='Twotoes:BAAALgAECgEJAQAAAA==.',
Ty='Tydiss:BAAALgAECgYJDAAAAA==.Tygranther:BAAALgADCggJFAAAAA==.',
Ug='Ugway:BAAALgAECgIJAgABLgAECgYJEQAFAAAAAA==.',
Ul='Ulfheðnar:BAAALgADCgEJAQAAAA==.Ulrika:BAABLgAECn8nAAILAAgJsyWwAwD2AgALAAgJsyWwAwD2AgAAAA==.Ultimatenerd:BAAALgAECgUJBgAAAA==.Ultyma:BAAALgADCgMJAwAAAA==.',
Um='Umbralmoon:BAAALgADCgEJAQAAAA==.',
Un='Unforgyven:BAABLgAECn8UAAIiAAgJRBd0CQB/AQAiAAgJRBd0CQB/AQAAAA==.Uniscorn:BAAALgAECgkJAQAAAA==.',
Va='Vaepor:BAABLgAECn8mAAMCAAgJxhSXCQDUAQACAAgJ1ROXCQDUAQAIAAgJDQ7gIQBnAQAAAA==.Vague:BAABLgAECn8ZAAQEAAgJLyKXGgBRAgAEAAYJhyOXGgBRAgAkAAUJ0h0TFgBnAQADAAEJCiCEegBdAAAAAA==.Vaguelz:BAAALgADCgYJBgAAAA==.Valeureux:BAAALgADCgMJAwAAAA==.Valgaar:BAAALgADCgEJAQAAAA==.Valkiria:BAAALgAECgEJAgAAAA==.Valorin:BAAALgAECgYJCwAAAA==.Valvify:BAAALgAECgEJAgAAAA==.Vandimion:BAAALgADCgYJBgAAAA==.Vaneste:BAACLgAFFH8WAAMGAAYJhBosCAClAQAGAAYJhBosCAClAQAHAAEJJAUdGQBLAAAuAAQKfyoAAgYACQmhIXsLAB8DAAYACQmhIXsLAB8DAAAA.Vartrino:BAABLgAECn8fAAIMAAgJ4RvvCAAPAgAMAAgJ4RvvCAAPAgAAAA==.',
Ve='Velandela:BAAALgAECgYJBgAAAA==.Vendoralia:BAABLgAECn8UAAIlAAYJZwb7BgD1AAAlAAYJZwb7BgD1AAAAAA==.Venuspriest:BAAALgADCgYJBgAAAA==.Verdius:BAABLgAECn8ZAAIVAAgJqAbKYwAUAQAVAAgJqAbKYwAUAQAAAA==.Verifiedbot:BAAALgAECgYJDAAAAA==.Verlant:BAABLgAECn8VAAIBAAYJDgYhKQABAQABAAYJDgYhKQABAQAAAA==.Vermwing:BAAALgAECgYJBgAAAA==.Vernichtet:BAAALgAFFAEJAQAAAA==.',
Vi='Virikae:BAAALgAECgQJBgAAAA==.',
Vo='Voidy:BAAALgAECgQJBAABLgAECgkJIgABAEwTAA==.Voodooshot:BAAALgADCgcJBwAAAA==.Vortan:BAABLgAECn8dAAIaAAgJ9xjeCwCrAQAaAAgJ9xjeCwCrAQAAAA==.',
Vu='Vush:BAAALgAECgYJEgAAAA==.',
Vy='Vyniran:BAAALgADCgQJCAAAAA==.',
Wa='Wagwan:BAAALgADCgEJAQABLgAECgkJFAAeAEcTAA==.Wallock:BAAALgADCgcJBwAAAA==.Wankfumuch:BAAALgAECgMJAwAAAA==.War:BAABLgAECn8hAAIdAAgJNiRTAQBKAwAdAAgJNiRTAQBKAwAAAA==.Warfury:BAAALgAECgUJDgAAAA==.Warrbeast:BAAALgADCgEJAQAAAA==.Warrcriminal:BAAALgADCgcJDQABLgAECgYJFAAjADYRAA==.Warros:BAAALgADCgIJAgAAAA==.Watchnu:BAAALgAECgYJDgAAAA==.',
We='Wendell:BAAALgAECgMJAgAAAA==.',
Wh='Whammo:BAAALgAECggJBQAAAA==.Whät:BAAALgADCgYJBgABLgAECgYJEgAFAAAAAA==.',
Wi='Willhelmina:BAAALgADCgkJEgABLgAECggJIAABAH4dAA==.Willowhite:BAAALgAECgQJCQAAAA==.',
Wl='Wlockholmes:BAAALgADCgQJBAABLgAFFAEJAQAFAAAAAA==.',
Wo='Wockyslush:BAABLgAECn8gAAIcAAgJ3xO5IgC7AQAcAAgJ3xO5IgC7AQAAAA==.Wolfrin:BAAALgAECgQJBAAAAA==.Worgonfreman:BAAALgAECgEJAQAAAA==.Workplox:BAAALgAECgYJEgAAAA==.',
Wu='Wubers:BAABLgAECn8gAAMBAAgJZSA2CwDFAgABAAgJZSA2CwDFAgAcAAUJhxU6TgAhAQAAAA==.Wubrs:BAAALgAECgYJDgABLgAECggJIAABAGUgAA==.Wulfjin:BAABLgAECn8YAAIkAAgJ3BlkBwDzAQAkAAgJ3BlkBwDzAQAAAA==.Wunderboi:BAAALgAECgcJCQAAAA==.Wundle:BAAALgADCgUJBQAAAA==.',
Xe='Xellie:BAAALgAECgIJBQAAAA==.',
Xu='Xumexania:BAAALgADCgcJCAAAAA==.',
Ya='Yakisoba:BAAALgAECgEJAQAAAA==.Yanagi:BAAALgAECgYJBgABLgAECggJGgAGADIgAA==.',
['Yå']='Yåmatohime:BAAALgAECgQJBwABLgAECgYJEgAFAAAAAA==.',
Za='Zandrood:BAAALgADCggJDQABLgAECgQJBwAFAAAAAA==.Zaremis:BAACLgAFFH8FAAIbAAMJiRFQGADLAAAbAAMJiRFQGADLAAAuAAQKfyMAAxsACAnMIYALAMcCABsACAnMIYALAMcCAAwAAgkhGVBtAI4AAAAA.Zathore:BAAALgADCgkJFAAAAA==.Zayehuo:BAAALgAECgMJBgAAAA==.',
Ze='Zeeni:BAAALgADCgYJBgAAAA==.Zelio:BAAALgADCgMJAwAAAA==.Zelphie:BAAALgAECgYJDAAAAA==.Zemtor:BAABLgAECn8VAAIkAAYJ2gjiFQAWAQAkAAYJ2gjiFQAWAQAAAA==.Zengadormu:BAAALgAECgMJBgAAAA==.Zerase:BAABLgAECn8iAAMgAAgJkSJrAQAqAwAgAAgJkSJrAQAqAwAfAAEJ1gNVZQAuAAAAAA==.Zerttrak:BAABLgAECn8VAAMDAAgJjBWFFQDmAQADAAgJjBWFFQDmAQAEAAIJngNNgQBBAAAAAA==.Zeryon:BAAALgADCgYJBgAAAA==.',
Zh='Zhay:BAAALgAECgUJCQAAAA==.Zhonglö:BAAALgAECgEJAQAAAA==.',
Zi='Zippityzap:BAAALgADCgMJAwAAAA==.Zitawitch:BAAALgAECgYJEAAAAA==.Zivot:BAAALgAECgEJAQAAAA==.',
Zo='Zodiak:BAAALgAECgQJDQAAAA==.Zomal:BAAALgAECgQJBAAAAA==.',
Zu='Zugzug:BAAALgAECgkJCAAAAA==.Zuladan:BAAALgADCgYJCwAAAA==.',
['Æl']='Ælin:BAABLgAECn8UAAIVAAYJQw03WQArAQAVAAYJQw03WQArAQAAAA==.',
['Ër']='Ërâgnõr:BAABLgAECn8YAAILAAgJMx2XJgChAgALAAgJMx2XJgChAgAAAA==.',
['Ðe']='Ðemonyx:BAAALgAECgUJBQAAAA==.',
['Øk']='Økrit:BAABLgAECn8bAAIkAAgJtRtSBABCAgAkAAgJtRtSBABCAgAAAA==.',
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

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

local lookup = {'Paladin-Holy','Druid-Feral','Druid-Guardian','DeathKnight-Blood','Mage-Frost','Warlock-Destruction','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Mage-Arcane','Unknown-Unknown','DemonHunter-Havoc','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Warlock-Affliction','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Restoration','Warrior-Protection','Warrior-Arms','Warrior-Fury','Hunter-Survival','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aadolin:BAABLgAECn8eAAIBAAgJRh72DgDvAQABAAgJRh72DgDvAQAAAA==.Aaromourne:BAAALgADCgMJAwAAAA==.',
Ab='Abmtt:BAABLgAECn8WAAMCAAgJfBH5DQDTAQACAAgJfBH5DQDTAQADAAMJSglQKgBQAAAAAA==.Abraxxy:BAAALgADCgkJDQAAAA==.',
Ac='Acalirra:BAAALgAECgEJAQAAAA==.Acorazado:BAAALgADCgEJAQAAAA==.',
Ad='Adeillia:BAABLgAECn8UAAIEAAcJ/RGxGgB6AQAEAAcJ/RGxGgB6AQAAAA==.Adeleska:BAABLgAECn8cAAIFAAgJoQLNcQD1AAAFAAgJoQLNcQD1AAAAAA==.Aderina:BAAALgADCggJCAAAAA==.Aderon:BAAALgAECgcJEQAAAA==.',
Ae='Aelkete:BAAALgAECgMJBQAAAA==.Aelorion:BAAALgAECgYJCAAAAA==.Aeovina:BAABLgAECn8WAAIGAAgJaRDMBACFAQAGAAgJaRDMBACFAQAAAA==.Aertenn:BAAALgAECgEJAQAAAA==.',
Ag='Agrash:BAAALgADCgEJAgAAAA==.',
Ai='Aiin:BAAALgAECgkJDgAAAA==.Aikar:BAABLgAECn8aAAIHAAgJExm7AgDoAQAHAAgJExm7AgDoAQAAAA==.Airasalt:BAAALgAECgcJBwAAAA==.Airassault:BAAALgAECgcJBAAAAA==.Airazzault:BAAALgADCgYJBgAAAA==.',
Ak='Akameuchiha:BAAALgAECgUJDgAAAA==.Akfirefly:BAAALgADCgIJAgAAAA==.Akrog:BAAALgAECgMJAwAAAA==.Akícita:BAAALgADCgMJAwAAAA==.',
Al='Albu:BAABLgAECn8VAAMIAAcJZwmGKABSAQAIAAcJZwmGKABSAQAJAAYJIRJnHQARAQAAAA==.Alianz:BAAALgADCgYJCwAAAA==.Aloradannan:BAAALgADCgcJBwAAAA==.Althiel:BAAALgADCgUJCAAAAA==.',
Am='Amaellara:BAABLgAECn8YAAMKAAYJexN2BwCMAQAKAAYJexN2BwCMAQAFAAMJ1wsUkQCuAAAAAA==.Amoralanth:BAAALgAECgcJCAAAAA==.Ams:BAAALgADCgkJDwAAAA==.',
An='Annabel:BAAALgAECgUJBgAAAA==.Anthatheus:BAAALgAECgYJDwAAAA==.',
Ao='Aoda:BAAALgAECgYJCwABLgAECgcJCQALAAAAAA==.Aotrom:BAAALgADCgYJBgAAAA==.',
Aq='Aqualina:BAAALgAECgIJAgAAAA==.',
Ar='Arashu:BAAALgADCgEJAQAAAA==.Arba:BAAALgAECgIJAgAAAA==.Arcanefire:BAAALgAECgYJCwAAAA==.Arckaius:BAAALgADCgcJDgAAAA==.Arcusu:BAAALgAECgQJBAAAAA==.',
As='Ashlevelle:BAAALgAECgUJCAAAAA==.Asterixx:BAAALgAECgUJCQAAAA==.Astralock:BAAALgADCgMJAwAAAA==.Astrea:BAAALgAECgEJAwAAAA==.Astreria:BAAALgADCgkJBAAAAA==.',
Au='Audare:BAABLgAECn8cAAIMAAYJdh0YGwDoAQAMAAYJdh0YGwDoAQAAAA==.Augmentism:BAAALgAECgIJAwAAAA==.Auzkaa:BAAALgADCgQJBAAAAA==.',
Av='Avarya:BAABLgAECn8hAAINAAgJZCX5AQBUAwANAAgJZCX5AQBUAwAAAA==.Averagelock:BAAALgAECgcJCQABLgAFFAMJCwAOAHYeAA==.Averagevoker:BAACLgAFFH8LAAQOAAMJdh54EwAQAQAOAAMJdh54EwAQAQAPAAIJ9wtyBwCOAAAQAAIJ0wRGFACFAAAuAAQKfxcABA8ACAmRHFwPAOUBAA8ABwl3G1wPAOUBAA4ABQm6H7ghALEBABAAAgmdCvc+AHMAAAAA.Averwine:BAAALgADCggJCQAAAA==.Avvala:BAAALgAECgEJBQAAAA==.',
Aw='Awangboboi:BAAALgADCgYJCAAAAA==.',
Az='Azhara:BAABLgAECn8VAAIRAAYJXg53dwBAAQARAAYJXg53dwBAAQAAAA==.Azuryal:BAAALgAECgEJAgAAAA==.',
Ba='Babychow:BAAALgADCgEJAQAAAA==.Baconlocks:BAAALgAECgQJCQAAAA==.Badgermilk:BAAALgADCgIJAgAAAA==.Badragon:BAABLgAECn8VAAQOAAcJSxf6KgBoAQAOAAUJdRn6KgBoAQAPAAQJeA/HKADaAAAQAAMJegtHOwCQAAABLgAFFAUJFAAOAM0cAA==.Baeleshea:BAAALgADCgcJCgAAAA==.Bagchi:BAABLgAECn8bAAMSAAgJpiEkDgCbAgASAAcJLh8kDgCbAgATAAQJ5h1dSAAgAQABLgAFFAEJAQALAAAAAA==.Bairian:BAAALgADCgcJCwAAAA==.Balsagnafays:BAAALgADCgYJBgAAAA==.Bamboozle:BAEALgAECgcJDQAAAA==.Baned:BAAALgADCgUJBQAAAA==.Barema:BAAALgAECgYJDwAAAA==.Bartokk:BAAALgAECgEJAQAAAA==.Bashtaz:BAAALgADCgYJBgAAAA==.Bawitab:BAABLgAECn8aAAIUAAYJ7R6NDQAVAgAUAAYJ7R6NDQAVAgAAAA==.Bawler:BAAALgAECgYJEwAAAA==.Bayleaf:BAAALgADCgIJAgABLgAFFAMJCwAOAHYeAA==.',
Be='Beanbagbear:BAAALgADCgUJBQABLgAECgYJFQAVAMobAA==.Bearforceone:BAAALgADCgEJAQAAAA==.Bearykyns:BAABLgAECn8bAAMDAAgJ3RGqCgAaAQADAAgJ3RGqCgAaAQAWAAIJcAcHPQBSAAAAAA==.Beastwarden:BAAALgAECgUJCwAAAA==.Bejay:BAAALgAFFAIJAgAAAA==.Belenath:BAAALgAECgYJBgAAAA==.Belgo:BAAALgAECgMJAwAAAA==.Belladar:BAAALgADCgIJAwAAAA==.Belphania:BAAALgADCgEJAQAAAA==.Bemused:BAAALgAECgYJEwAAAA==.Benefitmonk:BAACLgAFFH8GAAIXAAMJrwoHEgDAAAAXAAMJrwoHEgDAAAAuAAQKfy4AAhcACAmKIHIKAKoCABcACAmKIHIKAKoCAAAA.Benefitwar:BAAALgADCgIJAgAAAA==.Berrishorti:BAAALgAECgcJCgAAAA==.',
Bi='Biga:BAAALgADCgEJAQAAAA==.Bigsock:BAAALgADCgQJBAAAAA==.Bigsocs:BAAALgADCgYJBwAAAA==.',
Bl='Blackbow:BAAALgAECgcJEAAAAA==.Blackleaf:BAAALgAECgEJAQABLgAECgcJEAALAAAAAA==.Blazeweaver:BAAALgADCgIJAgAAAA==.Blep:BAABLgAECn8VAAINAAcJKhVvEQCUAQANAAcJKhVvEQCUAQAAAA==.Blesseditbe:BAAALgADCgQJBgAAAA==.Blindluck:BAAALgADCgUJBQAAAA==.Blites:BAAALgAECgYJDQAAAA==.Blitzø:BAABLgAECn8bAAIGAAgJXgcxCAAsAQAGAAgJXgcxCAAsAQAAAA==.Blueheal:BAAALgAECgIJAgAAAA==.Bluemilk:BAABLgAECn8ZAAIBAAYJ9xlnOwCMAQABAAYJ9xlnOwCMAQAAAA==.',
Bo='Bobafet:BAAALgADCgIJAgAAAA==.Bobwayjr:BAACLgAFFH8RAAIFAAUJJyMKCwCaAQAFAAUJJyMKCwCaAQAuAAQKfygAAgUACQlgI/YHAIoDAAUACQlgI/YHAIoDAAAA.Bojo:BAAALgADCgcJCgAAAA==.Bonboof:BAAALgAECgQJBAAAAA==.Boneshadow:BAAALgADCgYJBgAAAA==.Bonnieve:BAAALgAECgEJAQAAAA==.Boombada:BAAALgADCgYJCAAAAA==.Bootysweat:BAAALgAECgcJAQAAAA==.Borderline:BAAALgADCgMJAwAAAA==.Bournefang:BAAALgAECgMJAwAAAA==.Bowlinder:BAACLgAFFH8FAAIVAAQJTBq+DgABAQAVAAQJTBq+DgABAQAuAAQKfxkAAhUABwm9IawRAJcCABUABwm9IawRAJcCAAAA.',
Br='Braestirina:BAAALgADCgMJAgAAAA==.Braldar:BAAALgAECgYJBwAAAA==.Braxiss:BAABLgAECn8jAAIYAAkJjxvmEQCpAgAYAAkJjxvmEQCpAgAAAA==.Breakalegg:BAAALgAECgMJAwAAAA==.Brilin:BAAALgAECgYJDQAAAA==.Brimridge:BAAALgADCgYJBgAAAA==.Broguë:BAAALgAECgYJDgAAAA==.Brokton:BAAALgADCgIJAgAAAA==.Brucarus:BAAALgAECgcJCQAAAA==.Bruceleex:BAAALgAECgEJAQAAAA==.Brueld:BAAALgAECgIJAwAAAA==.',
Bu='Bumond:BAAALgADCgYJCQAAAA==.Burrito:BAAALgADCgEJAQAAAA==.Busin:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäwitaba:BAAALgAECgEJAQAAAA==.',
Ca='Calabag:BAAALgAFFAEJAQAAAA==.Calabloom:BAAALgADCgcJBwABLgAFFAEJAQALAAAAAA==.Calahunt:BAAALgADCgUJBQABLgAFFAEJAQALAAAAAA==.Calapriest:BAAALgADCgkJEgABLgAFFAEJAQALAAAAAA==.Calasmash:BAAALgADCgQJBAABLgAFFAEJAQALAAAAAA==.Calendre:BAAALgADCggJDQAAAA==.Capheira:BAAALgADCgcJBwAAAA==.Carlidruid:BAAALgAECgMJAwAAAA==.Carlinofuoco:BAAALgAECgYJEgAAAA==.Castle:BAAALgADCgQJBAAAAA==.Caswynde:BAAALgADCgQJBQAAAA==.Cavalina:BAAALgAECgUJBQAAAA==.Cavick:BAABLgAECn8cAAMKAAYJ+RSnDAADAQAFAAYJIg7EWQAqAQAKAAQJwRSnDAADAQAAAA==.Cayleth:BAAALgADCgYJCQAAAA==.',
Ce='Celyanar:BAAALgADCgYJCgAAAA==.Cereas:BAAALgAECgYJDwAAAA==.Cerlin:BAAALgADCggJCAABLgAFFAIJAgALAAAAAA==.',
Ch='Chainsoul:BAAALgAECgMJAwAAAA==.Chancec:BAAALgADCgcJCQAAAA==.Chanpaanda:BAAALgADCgMJAwAAAA==.Chantalle:BAAALgADCgMJBgAAAA==.Charliedruid:BAAALgAECgYJCwAAAA==.Charsham:BAAALgAECgUJCQAAAA==.Charön:BAABLgAECn8oAAIFAAgJhSAsCQCqAgAFAAgJhSAsCQCqAgAAAA==.Chentrocka:BAABLgAECn8rAAIFAAkJTyCyDAB9AgAFAAkJTyCyDAB9AgAAAA==.Cherine:BAABLgAECn8dAAMDAAgJ4xUoCwDfAQADAAgJ4xUoCwDfAQACAAQJyQ3mJACrAAAAAA==.Cherrytomato:BAAALgAECgYJCQAAAA==.Chervil:BAAALgAFFAEJAQABLgAFFAMJCwAOAHYeAA==.Chhr:BAAALgAECgMJBAAAAA==.Chicakes:BAAALgADCgcJDgABLgAECgQJBAALAAAAAA==.Chiillyy:BAAALgAECgYJDgAAAA==.Chikaahh:BAAALgAECgIJAgAAAA==.Chillbruh:BAAALgAECgYJAwAAAA==.Chillydroo:BAAALgADCgYJCgABLgAECgYJDgALAAAAAA==.Chiselin:BAAALgAECgYJCwAAAA==.Chktmilk:BAAALgADCgUJBQAAAA==.Chohh:BAAALgADCgEJAQAAAA==.Chronoflames:BAAALgAECgUJBQAAAA==.Chuckversus:BAAALgADCgYJBgAAAA==.Chugchug:BAAALgAECgYJCAAAAA==.Chunkernot:BAAALgAECgQJBAAAAA==.Chàrron:BAAALgADCgMJBgAAAA==.',
Ci='Cicee:BAAALgADCgkJGwAAAA==.Cigsinside:BAAALgAECgQJBAAAAA==.',
Ck='Ckdruid:BAAALgAECgUJCwAAAA==.',
Cl='Clerikyns:BAAALgADCgMJBQABLgAECggJGwADAN0RAA==.Clicks:BAAALgAECgUJBwAAAA==.Clics:BAAALgAECgQJCAAAAA==.',
Co='Coalgrim:BAAALgAECgYJEQAAAA==.Cohiba:BAAALgAECgEJAQAAAA==.Coldflames:BAABLgAECn8bAAISAAkJSyIKBgAhAwASAAkJSyIKBgAhAwAAAA==.Coldmountain:BAAALgADCgQJBAAAAA==.Coldonn:BAAALgAECgQJBwAAAA==.Confuzed:BAAALgADCgEJAQAAAA==.Continental:BAAALgADCgIJAgAAAA==.Coolbeans:BAAALgADCgMJAwAAAA==.Coprozonodo:BAAALgAECgYJDgAAAA==.Cowsoup:BAAALgAECgIJAQAAAA==.Cozmos:BAAALgAECgMJBAAAAA==.',
Cp='Cploc:BAAALgADCgEJAQAAAA==.',
Cr='Cravenn:BAAALgADCgEJAQAAAA==.Cravins:BAAALgAECgYJBgAAAA==.Craziness:BAAALgAECgYJDQAAAA==.Creambeam:BAAALgAECgUJBAAAAA==.Cremedently:BAABLgAECn8VAAIYAAgJUhDENADbAQAYAAgJUhDENADbAQAAAA==.Crewsader:BAAALgADCgQJBAAAAA==.Critnyspears:BAAALgAECgMJAwAAAA==.Crowdie:BAAALgADCgcJCwAAAA==.Crowlett:BAABLgAECn8qAAMZAAgJ+xu4CABLAgAZAAgJ+xu4CABLAgAaAAYJJQXZaADfAAAAAA==.',
Cu='Curoconcum:BAAALgAECgIJAgAAAA==.',
Cy='Cyllene:BAAALgADCgMJAwAAAA==.Cypher:BAAALgADCgIJAgAAAA==.Cyrub:BAAALgAECgMJBQAAAA==.',
Da='Daboneman:BAAALgADCgYJBgAAAA==.Dabrinto:BAAALgAECgQJCAAAAA==.Daelith:BAAALgADCgIJAgAAAA==.Daemonmortis:BAABLgAECn8VAAQbAAUJ1wVHHACQAAAcAAQJJgSG3QCfAAAbAAMJlQVHHACQAAAGAAQJXQWDWgBfAAAAAA==.Dainsleif:BAAALgAECgEJAQAAAA==.Daiya:BAAALgADCgUJBgAAAA==.Damndelion:BAABLgAECn8WAAMIAAYJyApoGQAcAQAIAAYJyApoGQAcAQAJAAEJEgejZAAvAAAAAA==.Dankweaver:BAABLgAECn8aAAMXAAcJqh8pFQAdAgAXAAcJqh8pFQAdAgASAAEJ5wpzgQAvAAAAAA==.Daoloth:BAAALgADCgcJBwAAAA==.Darazen:BAAALgADCgYJDAAAAA==.Darkviper:BAAALgAECgIJAwAAAA==.Darkzonex:BAAALgAECgEJAgAAAA==.Darthxander:BAAALgAECgcJDgAAAA==.Dasir:BAAALgAECgcJDQAAAA==.Daskinny:BAAALgAECgEJAQAAAA==.Dattoo:BAAALgADCgMJAwAAAA==.Dazuk:BAAALgAECgIJAgAAAA==.',
Dc='Dctrstrange:BAAALgAECgUJBQAAAA==.',
De='Deadbølt:BAABLgAECn8WAAIdAAYJJQlZDAAUAQAdAAYJJQlZDAAUAQAAAA==.Deberry:BAAALgADCgUJCAAAAA==.Deevine:BAAALgADCgEJAQAAAA==.Deform:BAAALgAECgQJBAAAAA==.Deformjr:BAAALgADCgUJCQAAAA==.Dehll:BAAALgADCgYJBgAAAA==.Demonarmy:BAAALgADCgUJBQAAAA==.Demonics:BAAALgAECgQJBAAAAA==.Demonos:BAAALgADCggJDQAAAA==.Demonstix:BAAALgADCgMJAwABLgAECgYJDwALAAAAAA==.Demontoki:BAAALgADCgcJDQAAAA==.Depressa:BAACLgAFFH8HAAIFAAQJoxBVHgBWAQAFAAQJoxBVHgBWAQAuAAQKfxgAAgUACAmAHEY3AJcCAAUACAmAHEY3AJcCAAAA.Devilslip:BAAALgAECgEJAQAAAA==.Dewfall:BAAALgAECgYJCwAAAA==.Deydrayn:BAAALgADCgYJCAAAAA==.',
Dh='Dhuoth:BAAALgAECgYJEAAAAA==.',
Di='Dialtone:BAAALgAECgUJCQAAAA==.Diamondeyes:BAAALgAECgUJDAAAAA==.Dibbington:BAABLgAECn8UAAMeAAgJPAOiCQC8AAAeAAgJDwOiCQC8AAAfAAQJUwJm/wB7AAAAAA==.Diggen:BAAALgADCgUJBgAAAA==.Diio:BAAALgAECgMJAwAAAA==.Dilfydee:BAAALgAECgQJBQAAAA==.Dinakeri:BAAALgAECgMJAwAAAA==.Dinda:BAABLgAECn8iAAIYAAcJgCE9EQCvAgAYAAcJgCE9EQCvAgAAAA==.Disdrag:BAACLgAFFH8TAAMOAAYJ7yKPBAC0AQAOAAYJ7yKPBAC0AQAPAAEJmg3ZCQBUAAAuAAQKfx0AAw4ACAlqJRwFADkDAA4ACAkdJRwFADkDAA8ABwlNJEMJAE0CAAAA.',
Dk='Dkkiller:BAAALgAECgQJCAAAAA==.Dkmetcàlf:BAABLgAECn8cAAIfAAkJdhFvJwCgAQAfAAkJdhFvJwCgAQAAAA==.',
Do='Dohane:BAAALgADCgYJCQAAAA==.Domatize:BAAALgAECgYJCgAAAA==.Domineera:BAAALgADCgYJBgAAAA==.Donkeymonk:BAAALgAECgEJAQAAAA==.Donkeytank:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Donutchan:BAAALgAECgcJDwAAAA==.Doof:BAAALgAECgQJBwAAAA==.Doopity:BAAALgAECgMJAwAAAA==.',
Dr='Dracosoup:BAAALgADCgcJBwAAAA==.Dragondruid:BAAALgAECgYJAQAAAA==.Dragonstix:BAAALgAECgYJDwAAAA==.Drahkula:BAAALgAECgEJAQAAAA==.Dreamerzz:BAAALgAECgQJBQAAAA==.Dredblade:BAAALgADCgkJIQAAAA==.Dredstar:BAAALgAECgYJBgAAAA==.Drockan:BAAALgADCgcJBgAAAA==.Drovac:BAAALgAECgYJDQAAAA==.Drudyy:BAAALgAECgUJCQAAAA==.Drugar:BAAALgADCgEJAQAAAA==.Druidxd:BAAALgAECgIJAwAAAA==.',
Du='Dubbies:BAAALgAECgQJBAAAAA==.Dumplins:BAAALgAECgUJBgABLgAECgcJDwALAAAAAA==.Durtluz:BAAALgAECgUJCQAAAA==.',
Dy='Dyrim:BAAALgAECgMJBQAAAA==.',
['Dê']='Dêformjr:BAAALgAECgYJCwAAAA==.',
['Dë']='Dëformjr:BAAALgAECgQJBAAAAA==.',
['Dú']='Dúbletap:BAABLgAECn8nAAIgAAgJQSL7AACoAgAgAAgJQSL7AACoAgAAAA==.',
Ea='Eajae:BAAALgADCgcJEAAAAA==.',
Eb='Ebidxd:BAAALgADCgMJAwAAAA==.',
Ed='Edavina:BAAALgADCgMJAwAAAA==.',
Eh='Ehra:BAAALgADCgEJAQAAAA==.Ehvie:BAAALgADCgkJBAABLgAECggJJwAWAIEaAA==.',
Ei='Eilaenil:BAAALgAECgEJAQAAAA==.',
Ek='Ekanta:BAAALgADCgEJAQAAAA==.',
El='Elani:BAAALgAECgcJDwAAAA==.Electricia:BAAALgAECgQJBgAAAA==.Elenii:BAABLgAECn8tAAINAAgJkR2iBACEAgANAAgJkR2iBACEAgAAAA==.Elinyra:BAAALgADCgkJFgAAAA==.Elisagrey:BAAALgAECgQJCgAAAA==.Elishia:BAAALgADCgMJAQAAAA==.Ellbosyou:BAABLgAECn8UAAIRAAYJZgjdSADLAAARAAYJZgjdSADLAAAAAA==.Elmadget:BAAALgADCgYJBgAAAA==.Elybere:BAAALgAECgIJAgAAAA==.Elÿ:BAAALgAFFAIJAgAAAA==.',
Em='Emdash:BAAALgADCgMJBAAAAA==.Emmaava:BAABLgAECn8eAAIZAAgJawuVGABQAQAZAAgJawuVGABQAQAAAA==.Emptyside:BAAALgADCgkJJwAAAA==.',
En='Enchorxxi:BAABLgAECn8YAAMEAAcJZyBlBQDdAQAEAAcJZyBlBQDdAQAfAAEJvQweuQA1AAAAAA==.Enetrenazara:BAAALgADCgUJBQAAAA==.Engage:BAAALgADCgMJAwABLgAECgcJFQANACoVAA==.Enkidudu:BAAALgAECgcJCwAAAA==.',
Ep='Epicgooner:BAAALgAECgIJBQAAAA==.',
Er='Eraeliice:BAAALgADCgYJBgAAAA==.Erahm:BAAALgAECgEJAQAAAA==.Erahmm:BAABLgAECn8aAAIfAAgJhgfROwBMAQAfAAgJhgfROwBMAQAAAA==.',
Es='Eskanore:BAAALgADCgcJDwAAAA==.',
Eu='Eule:BAEALgAECgQJCQAAAA==.',
Ev='Evilicecream:BAAALgAECgUJCwABLgAECgcJFwAOAF4RAA==.Evokil:BAAALgAECgEJAQABLgAECggJJQAHAHMUAA==.Evoktune:BAAALgAECgEJAQABLgAFFAIJAgALAAAAAA==.',
Ex='Exactlee:BAABLgAFFH8IAAIXAAQJcQjuDQD9AAAXAAQJcQjuDQD9AAAAAA==.Exlee:BAAALgADCgkJHAAAAA==.Exurio:BAAALgAECgEJAQAAAA==.',
Ey='Eyls:BAAALgAECgYJDQAAAA==.',
Fa='Faithwarrior:BAAALgAECgYJDgAAAA==.Falopero:BAAALgADCgYJAQAAAA==.Falron:BAAALgAECgEJAQAAAA==.Fartlosh:BAAALgADCgMJAwAAAA==.Fathercheak:BAABLgAECn8UAAMNAAcJGQyOOgBRAQANAAcJGQyOOgBRAQAIAAQJuQNhQgCgAAAAAA==.Fathlia:BAABLgAECn8kAAIUAAgJWRc6FgC2AQAUAAgJWRc6FgC2AQAAAA==.',
Fe='Felgood:BAAALgAECgEJAQAAAA==.Felinlove:BAAALgAECgEJAQAAAA==.Felixito:BAAALgADCgcJEgAAAA==.Femroster:BAAALgADCgUJBQAAAA==.Femrostt:BAAALgADCggJDgAAAA==.Fezzjin:BAABLgAECn8cAAIBAAYJKhhhEwC8AQABAAYJKhhhEwC8AQAAAA==.',
Fi='Fidgetspin:BAAALgAECgYJDwAAAA==.Findlehurst:BAAALgADCggJBwAAAA==.Finleyy:BAAALgAECgYJDwAAAA==.Fireaveus:BAAALgAECgIJAwAAAA==.Firemender:BAAALgAECgIJAwAAAA==.',
Fl='Flashlights:BAAALgAECgUJCQAAAA==.Fleshbiter:BAAALgAECgMJAwAAAA==.Flites:BAAALgADCgMJAwAAAA==.Floofypoof:BAAALgADCgEJAQAAAA==.Flowriduh:BAAALgAECgQJBwAAAA==.Fluffyfister:BAAALgAECgQJBQAAAA==.',
Fm='Fmjserval:BAAALgAECgUJDAAAAA==.',
Fo='Fookiebookie:BAAALgADCgEJAQAAAA==.Foot:BAAALgAECgYJDQAAAA==.Forcefaith:BAABLgAECn8dAAQaAAgJwx8RFADzAgAaAAgJwx8RFADzAgABAAMJ0ASefwB6AAAZAAIJtxluNAB2AAAAAA==.Foxmulder:BAAALgAECgIJAgAAAA==.',
Fr='Freduardo:BAAALgADCgEJAQAAAA==.Freva:BAABLgAECn8kAAIJAAgJCw/SDgCbAQAJAAgJCw/SDgCbAQAAAA==.Friarfox:BAAALgADCggJCAABLgAECggJGwAVAO4KAA==.Frodobaggins:BAAALgAECgYJDAAAAA==.Fronkyfronk:BAAALgAECgMJAwAAAA==.Fruitpuddle:BAAALgAFFAEJAQAAAA==.',
Fu='Funkmemonk:BAAALgADCgEJAQAAAA==.Furabier:BAAALgAECgYJDgAAAA==.Furlock:BAAALgADCgYJCQAAAA==.Furryhugger:BAABLgAECn8VAAIVAAYJyhvLKADOAQAVAAYJyhvLKADOAQAAAA==.Furyos:BAAALgADCgIJAgAAAA==.',
Ga='Galepalm:BAABLgAECn8bAAISAAkJtA9wDQChAQASAAkJtA9wDQChAQAAAA==.Gambriniss:BAAALgAECgYJDgAAAA==.Gamea:BAAALgAECgYJDgAAAA==.Gangshin:BAAALgADCgMJAwAAAA==.Gatepally:BAAALgAECgcJBwAAAA==.Gattler:BAAALgADCgcJCgAAAA==.Gazrosh:BAABLgAECn8UAAMSAAYJHx94DQChAQASAAYJHx94DQChAQAXAAIJJg8FWwBiAAAAAA==.',
Gh='Gharvar:BAAALgADCgIJAgAAAA==.',
Gi='Gingipie:BAAALgADCgIJAgAAAA==.Gizzinuz:BAAALgADCgkJCQABLgAECgYJEwALAAAAAA==.',
Gj='Gjimli:BAAALgAFFAMJAwAAAA==.',
Gl='Glowshroom:BAAALgADCgcJBwABLgAECgUJBQALAAAAAA==.',
Go='Goldenheals:BAAALgAECgcJCgAAAA==.Goosemon:BAAALgADCgcJDwAAAA==.Gordoc:BAAALgADCggJIQAAAA==.Gorehowlin:BAAALgAECgcJAgAAAA==.',
Gr='Graff:BAABLgAECn8jAAMEAAcJpRkRCQCHAQAEAAYJtR4RCQCHAQAfAAcJjQHz5AC2AAAAAA==.Gravie:BAAALgADCgEJAQAAAA==.Graystaf:BAAALgAECgYJCwAAAA==.Grennan:BAAALgAECgUJCAAAAA==.Greymists:BAAALgAECgYJCgABLgAECggJHQAIAF4UAA==.Greyp:BAAALgADCgUJBQAAAA==.Greysn:BAAALgAECggJBwAAAA==.Greíf:BAAALgADCgQJBAAAAA==.Griffidan:BAAALgADCggJCAAAAA==.Grifflez:BAABLgAECn8bAAIGAAYJ6Q95CQAQAQAGAAYJ6Q95CQAQAQAAAA==.Grimfifteen:BAAALgADCgMJAwAAAA==.Grizwintrgrn:BAAALgAECgcJDwAAAA==.Grundleswath:BAAALgADCgcJEAAAAA==.',
Gu='Gufo:BAAALgAECgcJCAAAAA==.Guljinn:BAAALgADCgcJCQAAAA==.Guyledouche:BAAALgAECgYJBgAAAA==.',
Ha='Hagann:BAAALgAECgYJCQABLgAECggJGgATAOIFAA==.Hakkazul:BAAALgAECgIJAgAAAA==.Halvanhelev:BAAALgADCgUJBQAAAA==.Hammeredd:BAABLgAECn8WAAIBAAcJeA1BHQBfAQABAAcJeA1BHQBfAQAAAA==.Handofblood:BAABLgAECn8bAAIaAAYJgwkeXgD5AAAaAAYJgwkeXgD5AAAAAA==.Hardrockgirl:BAACLgAFFH8MAAICAAQJHggQAgBHAQACAAQJHggQAgBHAQAuAAQKfy8AAwIACAkRHRcIAGECAAIACAkGGhcIAGECAAMACAkMHAYKAC0BAAAA.Harenima:BAAALgAECgUJBQAAAA==.Harmonechi:BAABLgAECn8YAAIGAAcJvhAlBwBDAQAGAAcJvhAlBwBDAQAAAA==.Havadatwo:BAAALgAECgUJEQAAAA==.',
He='Healinghammz:BAAALgAECgIJAgAAAA==.Healmonbello:BAAALgADCgcJCAAAAA==.Healsgobrr:BAAALgAECgMJBQAAAA==.Healystix:BAAALgADCgcJCgABLgAECgYJDwALAAAAAA==.Helldoll:BAAALgAECgQJBAAAAA==.Hellzcrusade:BAABLgAECn8ZAAIaAAcJwxX3KwCSAQAaAAcJwxX3KwCSAQAAAA==.Herboos:BAAALgAECgYJCgAAAA==.Herbus:BAAALgADCgYJBgAAAA==.Hexcaster:BAAALgADCgcJDAAAAA==.Hexwing:BAAALgAECgMJBAABLgAECgkJHAAaACQSAA==.',
Hi='Higowrath:BAAALgAECgEJAQAAAA==.',
Ho='Hodesh:BAAALgADCggJCgAAAA==.Holypuuss:BAACLgAFFH8HAAIaAAQJgRKmEQA/AQAaAAQJgRKmEQA/AQAuAAQKfyIAAxoACQkSH8MTAPUCABoACQkSH8MTAPUCAAEAAQl2DE9PADUAAAAA.Holystar:BAAALgAFFAEJAQAAAA==.Hopeslayer:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Hoplitedh:BAAALgADCgQJBAABLgAECgcJEAALAAAAAA==.Hoplitesaint:BAAALgAECgcJEAAAAA==.Hoplitescout:BAAALgADCgMJBgABLgAECgcJEAALAAAAAA==.',
Hp='Hps:BAABLgAECn8VAAIhAAgJLh2cDQAxAgAhAAgJLh2cDQAxAgAAAA==.',
Hr='Hrakos:BAAALgAECgcJBwAAAA==.Hrímgerðr:BAAALgAECgYJBwAAAA==.',
Ht='Htiál:BAAALgAECgcJDgAAAA==.Htïål:BAAALgADCgYJBgABLgAECgcJDgALAAAAAA==.',
Hu='Hutõ:BAAALgAECgcJEwAAAA==.',
Hy='Hyndra:BAAALgAECgQJCAAAAA==.Hyrakka:BAAALgADCgYJCQABLgAECgYJDgALAAAAAA==.Hyunkel:BAAALgADCgMJAwAAAA==.Hyunkvoker:BAAALgAECgUJCAAAAA==.Hyx:BAAALgADCgYJBgAAAA==.',
Ic='Icemommy:BAABLgAECn8gAAIFAAgJ5hbOLQCsAQAFAAgJ5hbOLQCsAQAAAA==.Icystyx:BAAALgAECgUJBgAAAA==.',
Id='Ideot:BAAALgADCgYJCAAAAA==.',
Ig='Igottinylegs:BAAALgADCgQJBQAAAA==.',
Il='Iloveturtle:BAAALgAECgUJBQAAAA==.Ilvann:BAAALgADCggJFQAAAA==.Ilyamurometz:BAABLgAECn8VAAMiAAgJ/xMvFgCsAQAiAAgJ/xMvFgCsAQAjAAEJ+QcBRQAuAAAAAA==.',
Im='Immorta:BAABLgAECn8rAAIkAAgJRxkVCgAJAgAkAAgJRxkVCgAJAgAAAA==.Imyourdaddy:BAAALgAECgIJAwAAAA==.',
Ir='Iriclaw:BAACLgAFFH8JAAIlAAUJlRfUAwBlAQAlAAUJlRfUAwBlAQAuAAQKfxQAAiUACQnCE7YDAFkCACUACQnCE7YDAFkCAAAA.Ironwood:BAAALgAECgcJCgAAAA==.',
Is='Ismellblood:BAAALgADCgUJCAAAAA==.',
It='Itisfinished:BAAALgAECgEJAQAAAA==.',
Ja='Jackeyguan:BAACLgAFFH8KAAIZAAMJjhDdAwC+AAAZAAMJjhDdAwC+AAAuAAQKfzEAAxkACAlIGUMEAAoCABkACAlIGUMEAAoCABoABgluCaupAC4BAAAA.Jackiepàn:BAAALgADCgUJBQAAAA==.Jadedapple:BAABLgAECn8cAAIFAAgJmRUnNQCQAQAFAAgJmRUnNQCQAQAAAA==.Jadefires:BAAALgAECgUJDAAAAA==.Jadejutsu:BAAALgAECgIJAwABLgAECgUJDAALAAAAAA==.Jandda:BAABLgAECn8hAAIhAAgJtiXyAwBSAwAhAAgJtiXyAwBSAwAAAA==.',
Je='Jefezadan:BAAALgADCgcJBwAAAA==.',
Jh='Jheniffer:BAAALgADCgEJAQAAAA==.Jherri:BAAALgAECgMJAwAAAA==.',
Ji='Jigslorei:BAAALgADCgEJAQAAAA==.Jimbeamer:BAAALgADCgkJCQABLgAECgQJCgALAAAAAA==.',
Jk='Jkm:BAAALgAECgYJEwAAAA==.',
Jo='Joanexotic:BAAALgAECgUJCAAAAA==.Joltx:BAAALgADCgYJBgAAAA==.',
Jr='Jrocmfka:BAAALgAECgUJBwAAAA==.',
Ju='Judeau:BAAALgADCgYJBgAAAA==.Judgemortis:BAAALgADCgUJBQAAAA==.Julihanna:BAAALgADCgIJAgAAAA==.Juntor:BAAALgADCggJEAAAAA==.Justa:BAAALgAECgEJAQAAAA==.Justinmatto:BAAALgADCgUJBQAAAA==.',
Ka='Kaawaki:BAAALgADCgYJCAABLgAECgkJMQAkANkdAA==.Kaeliin:BAAALgADCggJCAABLgADCggJDQALAAAAAA==.Kage:BAAALgAECgIJBAAAAA==.Kaiaicewing:BAAALgADCgMJAwAAAA==.Kaishowspeed:BAAALgADCgcJDQAAAA==.Kal:BAAALgAECgMJBQAAAA==.Kalorondir:BAAALgADCgUJBgAAAA==.Kandvoker:BAAALgAECgEJAgAAAA==.Karatekyns:BAAALgAECgIJAgABLgAECggJGwADAN0RAA==.Katatonia:BAAALgAECgMJBQAAAA==.Katherwind:BAAALgADCgEJAQAAAA==.Kattara:BAABLgAECn8eAAIDAAgJphy9AwD8AQADAAgJphy9AwD8AQAAAA==.Kattarwal:BAABLgAECn8XAAIeAAgJqQrSBQAvAQAeAAgJqQrSBQAvAQAAAA==.Kawakki:BAABLgAECn8xAAIkAAkJ2R3wAwCLAgAkAAkJ2R3wAwCLAgAAAA==.Kayjay:BAAALgADCgMJAwAAAA==.Kayoti:BAAALgADCgkJCQABLgAECggJFwAfAIQPAA==.',
Ke='Keely:BAAALgADCgEJAQAAAA==.Kennily:BAAALgADCgUJBQAAAA==.Kenté:BAAALgAECgYJDgAAAA==.Keyndian:BAAALgAECgQJBwAAAA==.',
Kh='Khaiza:BAAALgADCgQJBAAAAA==.Khaotikdraco:BAACLgAFFH8UAAMOAAUJzRzpCABpAQAOAAUJzRzpCABpAQAPAAEJAADSBwAAAAAuAAQKfyMAAw4ACQmmH4QEAEgDAA4ACQmmH4QEAEgDAA8ABQl0Dh8kAAYBAAAA.Khaototem:BAABLgAECn8dAAIVAAkJjxVfDADVAQAVAAkJjxVfDADVAQABLgAFFAUJFAAOAM0cAA==.Khazgul:BAAALgAECgEJAQAAAA==.Khrosrin:BAAALgADCgQJBAAAAA==.',
Ki='Kiljaiden:BAAALgAECgYJDQAAAA==.Killalily:BAAALgAECgUJCwAAAA==.Kimagure:BAABLgAECn8XAAMOAAcJXhE5KQB0AQAOAAcJeQ85KQB0AQAPAAUJkBPSJAD/AAAAAA==.Kimjonggoon:BAAALgAECgQJDQAAAA==.Kissbuttchin:BAAALgAECgUJCAAAAA==.Kiyoshie:BAABLgAECn8nAAIYAAgJ4xbHHwBHAgAYAAgJ4xbHHwBHAgAAAA==.',
Km='Kmaruko:BAAALgAECgIJAgAAAA==.',
Ko='Koblelock:BAABLgAECn8ZAAIbAAgJyRTEAQDjAQAbAAgJyRTEAQDjAQAAAA==.Kodiakjak:BAAALgADCgUJBwAAAA==.Kodiakpax:BAAALgADCggJCwAAAA==.Kodiakwak:BAAALgADCgcJBwAAAA==.Kodiakzug:BAAALgADCgEJAQAAAA==.Koftimu:BAAALgAECgYJDQAAAA==.Kolax:BAAALgAECgMJBgAAAA==.Komoonyoung:BAAALgADCgYJBgAAAA==.Kontroll:BAEALgAECgYJAwABLgAECgcJDQALAAAAAA==.Kookee:BAABLgAECn8dAAIcAAgJWxamFgDxAQAcAAgJWxamFgDxAQAAAA==.',
Kr='Kraazh:BAABLgAECn8aAAISAAgJ8h4fDQCpAgASAAgJ8h4fDQCpAgAAAA==.Krieghelm:BAAALgAECgQJBAAAAA==.Krizzlix:BAAALgAECggJCQAAAA==.Krypticgrip:BAAALgAECgMJBAABLgAFFAUJFAAOAM0cAA==.',
Ku='Kunglou:BAAALgAECgcJDQAAAA==.Kurayamiryu:BAAALgAECgQJBAAAAA==.Kuyntaitain:BAAALgAECgMJBQAAAA==.',
Ky='Kyle:BAAALgADCgcJDAAAAA==.',
La='Lacina:BAAALgADCgEJAgAAAA==.Lanfeár:BAAALgADCgYJBgAAAA==.Larissa:BAABLgAECn8aAAMWAAcJgQyCGQAxAQAWAAcJgQyCGQAxAQAhAAEJ8QDW7QAKAAABLgAECggJGwAVAO4KAA==.Laserdisc:BAAALgAECgEJAgAAAA==.Lathillea:BAAALgAECgYJEAAAAA==.Lavendertown:BAAALgAECgQJBgAAAA==.Lazzirus:BAABLgAECn8kAAMVAAgJdhoXCgD5AQAVAAgJdhoXCgD5AQAUAAIJ1AlwjABjAAAAAA==.',
Le='Leelominai:BAAALgADCgMJAwAAAA==.Legendairÿ:BAAALgADCgcJBwAAAA==.Legogatz:BAAALgADCgYJBgAAAA==.Leinalei:BAAALgAECggJCAABLgAECgkJTAAhAMMmAA==.Lessii:BAECLgAFFH8NAAIfAAQJ1h2UEABsAQAfAAQJ1h2UEABsAQAuAAQKfyQAAh8ACAm/IY8bANgCAB8ACAm/IY8bANgCAAAA.',
Li='Lidarcis:BAABLgAECn8oAAMfAAgJJx+tFQAMAgAfAAgJJx+tFQAMAgAEAAcJmRYvDwAiAQAAAA==.Life:BAAALgADCggJBgAAAA==.Lifebinder:BAAALgADCgkJCQAAAA==.Liftz:BAAALgAECgMJBgAAAA==.Lilbingbong:BAAALgAECgEJAQAAAA==.Lilithstyx:BAAALgAECgIJBAAAAA==.Lilykilikili:BAAALgAECgMJBgABLgAECggJDQALAAAAAA==.Linkin:BAAALgADCgUJAwAAAA==.Lissandra:BAAALgAECgQJBQAAAA==.Litcore:BAAALgADCgYJCgABLgAECgcJFAABAB0bAA==.',
Lo='Lobó:BAAALgADCgQJBQAAAA==.Lockybuns:BAAALgADCgQJBAAAAA==.Lokdis:BAAALgADCgIJAQAAAA==.Loosekitty:BAAALgADCgYJCQAAAA==.Lorily:BAAALgADCgcJBwABLgAECgYJEwALAAAAAA==.Lorthñemar:BAAALgAECgQJBwAAAA==.Lostdogg:BAAALgAECgcJDQAAAA==.Lostdrt:BAAALgADCgEJAQAAAA==.Lostpreist:BAAALgAECgYJBwABLgAECgcJDQALAAAAAA==.',
Lu='Luckybet:BAABLgAECn8YAAIYAAcJSB28FQDkAQAYAAcJSB28FQDkAQAAAA==.Lukashenko:BAAALgADCgYJBAAAAA==.Lunamorr:BAAALgADCgkJDAAAAA==.Luxian:BAAALgAECgQJCgAAAA==.',
Ly='Lyger:BAAALgADCgYJBwABLgAECgQJBAALAAAAAA==.Lymka:BAAALgAECgQJBQAAAA==.',
Ma='Mackori:BAAALgAECgUJCgAAAA==.Madamepali:BAAALgADCgYJBgAAAA==.Madduxx:BAAALgAECgYJEQAAAA==.Maeg:BAAALgADCgYJBgAAAA==.Maesera:BAAALgADCgUJCgAAAA==.Magenos:BAABLgAECn8eAAIFAAgJwQrmPQB0AQAFAAgJwQrmPQB0AQAAAA==.Magic:BAAALgAECgMJBQAAAA==.Magickwarior:BAAALgAECgMJAwAAAA==.Magicnieech:BAAALgADCgQJBAAAAA==.Magicpants:BAAALgAECgYJDwAAAA==.Magobiga:BAAALgAECgQJCwAAAA==.Maguito:BAAALgAECgIJAgAAAA==.Mahohyuga:BAAALgADCgYJFQAAAA==.Mahrx:BAACLgAFFH8QAAISAAUJdBw5AwBpAQASAAUJdBw5AwBpAQAuAAQKfyUAAhIACAm+JFcEAEYDABIACAm+JFcEAEYDAAAA.Mahvel:BAAALgAECgYJCQAAAA==.Majinvegeta:BAAALgAECgQJBQAAAA==.Manrrome:BAAALgADCgEJAgAAAA==.Masamoon:BAABLgAECn8lAAIXAAgJRxxABgBjAgAXAAgJRxxABgBjAgAAAA==.Masonshyphy:BAAALgAECgcJDwAAAA==.Mather:BAAALgADCgYJBgAAAA==.Maxmiup:BAAALgADCgUJBgAAAA==.Maxomi:BAAALgADCgYJBwAAAA==.',
Mc='Mcswissleguy:BAAALgADCgYJCAAAAA==.',
Me='Medarela:BAAALgADCgcJFAAAAA==.Meeke:BAACLgAFFH8LAAIJAAQJ+RsdBQBjAQAJAAQJ+RsdBQBjAQAuAAQKfygAAgkACAngIW8GACUDAAkACAngIW8GACUDAAAA.Meekrob:BAAALgAECgIJAgAAAA==.Melmin:BAAALgAECgQJDAAAAA==.Mercyful:BAAALgAECgkJBgAAAA==.Meroman:BAAALgAECgMJBQAAAA==.Merrllyn:BAAALgAECgMJBAAAAA==.Merynn:BAAALgADCgYJBgAAAA==.Metamora:BAABLgAECn8VAAIWAAcJgQYpIgDuAAAWAAcJgQYpIgDuAAAAAA==.Meuria:BAABLgAECn8WAAIYAAcJ/glBPAAiAQAYAAcJ/glBPAAiAQAAAA==.',
Mi='Milliarde:BAAALgADCgUJCAAAAA==.Ministry:BAAALgAECgEJAwAAAA==.Misstearly:BAAALgAECgYJEAAAAA==.Missyann:BAAALgADCgYJCgAAAA==.Mistamec:BAAALgAECgUJCQAAAA==.',
Mo='Mohjoejoejoe:BAAALgADCgkJCQAAAA==.Moida:BAAALgADCgUJBQABLgAECggJKAAfACcfAA==.Mojok:BAAALgAECgYJCAAAAA==.Moltonmonk:BAABLgAECn8VAAMkAAYJ2gx6NAC6AAAkAAYJ2gx6NAC6AAAiAAQJQgPNNgCRAAAAAA==.Momô:BAAALgAECgEJAQAAAA==.Moneebagz:BAABLgAECn8XAAIeAAcJzQ35CABSAQAeAAcJzQ35CABSAQAAAA==.Monkbezz:BAAALgADCgUJBAAAAA==.Monktune:BAAALgAECgIJAgAAAA==.Montblanc:BAAALgADCgYJBgAAAA==.Mooingtun:BAABLgAECn8bAAIWAAgJMA+bEgB1AQAWAAgJMA+bEgB1AQAAAA==.Moonem:BAABLgAECn8YAAMWAAgJKB7tGABAAgAWAAgJKB7tGABAAgAhAAMJ+hdHQQDLAAAAAA==.Mossburg:BAABLgAECn8YAAIlAAkJAxpYCgAzAgAlAAkJAxpYCgAzAgAAAA==.',
Mu='Mulgogi:BAAALgAECgUJBgAAAA==.Munziees:BAAALgADCgcJBwAAAA==.Mustachio:BAAALgADCgcJCAAAAA==.',
My='Mysticwarior:BAAALgAECgIJAgAAAA==.',
['Mé']='Méta:BAAALgAECgcJCwABLgAECgcJFQAWAIEGAA==.',
Na='Nachopapa:BAAALgADCgkJGgAAAA==.Nagare:BAAALgADCgIJAgAAAA==.Nani:BAAALgADCgEJAQAAAA==.Naniwa:BAABLgAECn8XAAIUAAgJ3xT7IwAHAgAUAAgJ3xT7IwAHAgAAAA==.Nasturtium:BAAALgADCgQJBAABLgAFFAMJCwAOAHYeAA==.Natsuko:BAAALgAECgIJAgAAAA==.Natura:BAAALgAECgEJAQAAAA==.Nayllia:BAAALgAECgQJBAAAAA==.Nazacis:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.Nazarickdk:BAAALgADCgkJCQABLgAECgUJBQALAAAAAA==.Nazarickhh:BAAALgADCgYJBgABLgAECgUJBQALAAAAAA==.Nazarickm:BAAALgAECgQJBAABLgAECgUJBQALAAAAAA==.',
Ne='Necrodik:BAAALgADCgEJAQAAAA==.Necroo:BAAALgAECgEJAQAAAA==.Nelenloth:BAAALgAECgEJAQAAAA==.Nelronde:BAAALgAECgEJAQAAAA==.Neoptolemus:BAAALgAECgMJBQAAAA==.Nerclopse:BAABLgAECn8UAAIVAAgJVA9vGQBHAQAVAAgJVA9vGQBHAQAAAA==.Neverender:BAAALgAECgYJEgAAAA==.',
Ni='Nightveil:BAAALgADCgQJBwAAAA==.Nikephorous:BAAALgAECgQJBwAAAA==.Niomee:BAAALgADCgcJBwAAAA==.Nitesbane:BAAALgADCgQJBAABLgAECgcJFAAaAIwhAA==.Nitroxs:BAAALgADCgcJCAAAAA==.',
No='Nokachí:BAAALgAECgEJAQAAAA==.Nola:BAAALgAECgEJAgAAAA==.Noritotem:BAABLgAECn8eAAIdAAgJJSPtAAC+AgAdAAgJJSPtAAC+AgAAAA==.Notec:BAAALgAECgcJBAAAAA==.Notics:BAABLgAECn8dAAQIAAgJXhT1EQByAQAIAAgJXhT1EQByAQAJAAUJYxKaQADzAAANAAIJUAuyPgAyAAAAAA==.Notpog:BAAALgAECggJEgAAAA==.Novacainê:BAAALgADCggJCAAAAA==.Noworry:BAACLgAFFH8IAAIFAAMJWQqUOQDuAAAFAAMJWQqUOQDuAAAuAAQKfyAAAgUACAl+GcRCAHACAAUACAl+GcRCAHACAAAA.',
Nu='Numb:BAACLgAFFH8IAAIXAAMJrg8cEADWAAAXAAMJrg8cEADWAAAuAAQKfykAAxcACAmdHHMRAEcCABcACAmdHHMRAEcCABIAAQn4A2uHACgAAAAA.Numuhotep:BAAALgADCgUJBQAAAA==.Nutnbolt:BAAALgADCgYJBgABLgAFFAMJCAAcAAUbAA==.Nuzoc:BAAALgADCgUJBQAAAA==.',
Ny='Nylistraz:BAAALgADCgkJEwAAAA==.',
['Ní']='Níghtwolf:BAAALgAECgUJBQAAAA==.',
Oa='Oakfel:BAAALgADCgEJAQAAAA==.Oakwar:BAAALgADCgMJAwAAAA==.',
Ob='Obsidiandusk:BAAALgAECgcJAQAAAA==.',
Oc='Occulore:BAAALgADCgIJAgAAAA==.',
Od='Odr:BAAALgADCgEJAQAAAA==.',
Oh='Ohdinn:BAAALgAECgIJAgABLgAECggJGgATAOIFAA==.',
Ok='Okiji:BAAALgADCgcJDAAAAA==.',
Ol='Olbonivia:BAAALgAECgEJAQAAAA==.Oldgreg:BAAALgADCgYJCQAAAA==.Oleander:BAAALgADCgcJDQAAAA==.Oliveros:BAAALgAECgEJAgAAAA==.Oliviadrago:BAAALgAECgcJCQAAAA==.',
On='Onebutton:BAABLgAECn8fAAQYAAgJ8iOlBwB9AgAYAAcJziOlBwB9AgAgAAYJmSPIGQBZAgAlAAIJtx0nHgC2AAAAAA==.Oniraine:BAAALgAECgQJCgAAAA==.Onlymilfs:BAAALgADCgMJAwAAAA==.',
Op='Opalescence:BAAALgAECgYJDQAAAA==.Optional:BAABLgAECn8iAAIlAAgJmyL5AgADAwAlAAgJmyL5AgADAwAAAA==.',
Or='Orgargo:BAABLgAECn8bAAIfAAYJLw2KSAAlAQAfAAYJLw2KSAAlAQAAAA==.Ornormas:BAAALgADCgYJBgAAAA==.',
Os='Oshagosa:BAAALgADCgcJBwABLgAECgYJDQALAAAAAA==.',
Ot='Othar:BAAALgADCgUJBQAAAA==.Otyphoon:BAAALgAECgUJBQAAAA==.',
Ow='Owl:BAAALgAECgYJCgAAAA==.Owtter:BAAALgADCgUJBQAAAA==.',
Pa='Pallorx:BAAALgAECgUJCQAAAA==.Pandasennin:BAAALgAECgMJBQAAAA==.Pankis:BAAALgADCgQJBAAAAA==.Papahammer:BAAALgAECgIJAgABLgADCgIJAgALAAAAAA==.Papashootin:BAAALgADCgIJAgAAAA==.Paperplate:BAABLgAECn8uAAIhAAkJ/yEmAQBxAwAhAAkJ/yEmAQBxAwAAAA==.Paradox:BAACLgAFFH8FAAICAAIJ/ByEBAC8AAACAAIJ/ByEBAC8AAAuAAQKfx0AAgIABwk8Ip4FAK8CAAIABwk8Ip4FAK8CAAAA.Patrien:BAAALgAECgEJAQAAAA==.Pattyhealsu:BAAALgAFFAIJAwAAAA==.',
Pe='Peachizz:BAAALgAECgcJCQAAAA==.Peligrynn:BAAALgAECgEJAQABLgAECgkJFwAfAIccAA==.Pelitina:BAAALgAECggJEwABLgAECgkJFwAfAIccAA==.Pelivarondo:BAAALgAECgIJBAABLgAECgkJFwAfAIccAA==.Peliweiza:BAABLgAECn8XAAIfAAkJhxwxLQCEAgAfAAkJhxwxLQCEAgAAAA==.Pelizandeth:BAAALgAECgYJEQABLgAECgkJFwAfAIccAA==.Pestillia:BAAALgAECgUJCAAAAA==.Pezzerino:BAEALgADCgQJBAABLgAECgcJBwALAAAAAA==.',
Ph='Phoffïn:BAAALgAECgQJCgAAAA==.',
Pi='Pistolbeat:BAAALgADCgYJBQAAAA==.Pitterpatter:BAAALgADCgcJDQAAAA==.',
Pl='Plapadin:BAAALgADCgUJBQAAAA==.',
Po='Poeup:BAAALgADCgYJCAAAAA==.',
Pr='Prayformojo:BAAALgAECgMJBQAAAA==.Pridehorn:BAAALgADCgQJBwAAAA==.Prizmatic:BAAALgADCgkJEwAAAA==.',
Ps='Psyko:BAAALgADCgkJCwAAAA==.',
Pu='Puiness:BAAALgADCgYJDAAAAA==.',
Py='Pyraskia:BAAALgADCgYJCQABLgAECgUJDAALAAAAAA==.',
Qu='Quickbrown:BAAALgAECgYJEwAAAA==.',
Ra='Rabiddog:BAAALgAECgMJBAAAAA==.Raced:BAAALgAECgEJAQAAAA==.Raebspace:BAAALgAECgIJAwAAAA==.Ragenarok:BAAALgAECgUJCwAAAA==.Ragenel:BAAALgADCgQJBAAAAA==.Rahxe:BAAALgAECgIJAwAAAA==.Raifyre:BAAALgADCgkJEQAAAA==.Raikz:BAAALgAECgEJAQAAAA==.Raiyne:BAAALgAECgYJDQAAAA==.Rak:BAAALgADCgYJCwAAAA==.Rakaa:BAAALgADCgEJAQAAAA==.Ramello:BAAALgAECgQJCQAAAA==.Randinator:BAAALgADCgEJAQAAAA==.Randomin:BAAALgAECgYJBgAAAA==.Rayyford:BAAALgADCgIJAgAAAA==.',
Re='Redneckrouge:BAAALgADCgYJBgAAAA==.Reielis:BAAALgADCgEJAQAAAA==.Relexi:BAAALgADCgYJBgAAAA==.Renarinn:BAAALgADCgcJBwAAAA==.Renloth:BAAALgADCggJDgAAAA==.Reno:BAABLgAECn8VAAIYAAYJFB2vHgCoAQAYAAYJFB2vHgCoAQAAAA==.Renthyr:BAABLgAECn8fAAMOAAgJZxY6HwDJAQAOAAcJphM6HwDJAQAQAAgJuxISCQCRAQAAAA==.Rentiana:BAAALgADCggJDgAAAA==.Reportcard:BAAALgAECgYJCgABLgAECgYJCwALAAAAAA==.Reuhots:BAAALgADCgUJBQABLgAECgcJDwALAAAAAA==.Reurog:BAAALgAECgcJDwAAAA==.',
Rh='Rhakudu:BAAALgAECgcJEwAAAA==.Rhipp:BAAALgAECgMJBgAAAA==.',
Ri='Rian:BAACLgAFFH8OAAMgAAUJVx0DCwBoAQAgAAUJVx0DCwBoAQAYAAEJthndNABbAAAuAAQKfxsAAiAACAlSI5YKAPkCACAACAlSI5YKAPkCAAEuAAUUBwkPAAUAahwA.Rigbee:BAAALgADCgYJBgAAAA==.Riikku:BAAALgADCgEJAQAAAA==.Ringram:BAAALgADCgEJAQAAAA==.Riploc:BAAALgAECgMJAwAAAA==.',
Ro='Roadiee:BAAALgAECgMJAwAAAA==.Roadkyll:BAAALgAECgYJDgAAAA==.Rolisea:BAAALgAECgYJEwAAAA==.Rosamoon:BAAALgADCgkJIAAAAA==.Rosettia:BAAALgAECgYJEAAAAA==.',
Ru='Rueofdarkest:BAAALgADCgYJBgAAAA==.Rum:BAAALgAECgEJAQABLgAFFAMJDgAiANofAA==.Rune:BAAALgAECgcJCAABLgAFFAcJDwAFAGocAA==.',
Ry='Rykaughn:BAAALgADCgkJHAAAAA==.',
['Râ']='Rânge:BAAALgAECggJAwAAAA==.',
Sa='Sadfingchud:BAAALgADCgMJBAAAAA==.Sadlerz:BAAALgAECgQJBAAAAA==.Salara:BAABLgAECn8VAAIFAAcJ0w9RnQCbAQAFAAcJ0w9RnQCbAQAAAA==.Salasong:BAAALgADCggJCwAAAA==.Saldri:BAAALgADCgYJDgAAAA==.Samb:BAAALgADCgMJAwAAAA==.Sambwave:BAAALgAECgUJCQAAAA==.Sample:BAAALgADCgMJAwABLgAECgYJEwALAAAAAA==.Sandrinea:BAABLgAECn8ZAAIcAAYJaAXgWgDhAAAcAAYJaAXgWgDhAAAAAA==.Sanguinore:BAAALgADCgMJAwAAAA==.Santá:BAAALgAECgUJEgAAAA==.Sarahmar:BAAALgADCgkJEgAAAA==.Saratogany:BAAALgADCgcJDAAAAA==.Sardenaris:BAACLgAFFH8IAAIYAAMJCxs2GQABAQAYAAMJCxs2GQABAQAuAAQKfycAAhgACAnvHwENADYCABgACAnvHwENADYCAAAA.Saripal:BAAALgADCgkJEwAAAA==.Sasquatchpal:BAAALgAECgYJDwAAAA==.',
Sc='Scrubpala:BAAALgADCgIJAgAAAA==.',
Se='Sebanis:BAAALgADCggJCAAAAA==.Sedale:BAAALgADCgkJCQAAAA==.Seesdeline:BAAALgAECgQJBAABLgAECgcJHAAWAHMeAA==.Seilene:BAAALgAECgUJCQAAAA==.Sekaii:BAAALgADCgEJAQAAAA==.Senis:BAAALgAECgIJAgAAAA==.Seo:BAABLgAECn8XAAIRAAcJmxFrJABaAQARAAcJmxFrJABaAQAAAA==.Seshomaruu:BAAALgAECgIJAgAAAA==.Sethanndis:BAABLgAECn8VAAIXAAgJ9gHQKwCqAAAXAAgJ9gHQKwCqAAAAAA==.Sevarog:BAAALgAECgIJAgAAAA==.Severan:BAAALgADCgYJDAAAAA==.',
Sh='Shadowhart:BAABLgAECn8iAAIcAAgJAhsUDwAxAgAcAAgJAhsUDwAxAgAAAA==.Shadowmagic:BAAALgADCgEJAQAAAA==.Shadowreap:BAAALgADCgIJAgAAAA==.Shaforgold:BAABLgAECn8aAAIVAAYJKhULGwA7AQAVAAYJKhULGwA7AQAAAA==.Shaidie:BAAALgAECgYJDQAAAA==.Shaiyuri:BAAALgADCgIJAgAAAA==.Shakuma:BAAALgAECgUJCAAAAA==.Shamblam:BAAALgAECgYJCQAAAA==.Sharmin:BAAALgADCgQJBgAAAA==.Shawtyschit:BAAALgAFFAEJAQABLgAECgYJCwALAAAAAA==.Shennidan:BAAALgAECgQJBAABLgAECgcJHAAWAHMeAA==.Shibal:BAABLgAECn8hAAIBAAgJTyHrAgDgAgABAAgJTyHrAgDgAgAAAA==.Shotorock:BAABLgAECn8VAAIFAAgJUQQDWQAsAQAFAAgJUQQDWQAsAQAAAA==.Shrekismydad:BAAALgADCgYJDgAAAA==.Shroompie:BAAALgADCgYJBgABLgAECgUJBQALAAAAAA==.Shroomsy:BAAALgAECgUJBQAAAA==.Shushumen:BAABLgAECn8fAAIfAAgJzBm7HQDVAQAfAAgJzBm7HQDVAQAAAA==.Shäken:BAABLgAECn8VAAIcAAYJ8wyKVgDtAAAcAAYJ8wyKVgDtAAAAAA==.Shîmmy:BAAALgADCgMJAQAAAA==.',
Si='Sicknezz:BAAALgAECgQJBwABLgAECgcJDgALAAAAAA==.Sickntwizted:BAAALgAECgcJDgAAAA==.Sickside:BAAALgADCgEJAQAAAA==.Sifzerg:BAAALgAECgMJBAAAAA==.Silvercore:BAABLgAECn8UAAMBAAcJHRs4HQAsAgABAAcJHRs4HQAsAgAaAAQJUB/AtQAZAQAAAA==.Silverstarz:BAAALgAECgYJDwABLgAFFAUJEgAWAMkfAA==.Simpmyimp:BAAALgADCgcJBwABLgAECggJKQAFAGIYAA==.Sindari:BAABLgAECn8cAAImAAgJ8wN6MQB8AQAmAAgJ8wN6MQB8AQAAAA==.Sinturio:BAAALgAECgYJDgAAAA==.Sipsy:BAAALgAECgYJEwAAAA==.Sisurae:BAAALgADCgcJEQAAAA==.',
Sk='Skarg:BAAALgADCgYJCQAAAA==.Skinnylock:BAAALgAECgQJBQAAAA==.Skycynder:BAAALgADCgkJBQAAAA==.Skyeashe:BAAALgAECgYJDAAAAA==.Skyerend:BAAALgADCgIJAwAAAA==.Skyeshadow:BAAALgADCgEJAQAAAA==.',
Sl='Slayersmma:BAAALgADCggJDgAAAA==.Slimeyy:BAAALgADCgcJBwAAAA==.Slip:BAAALgAFFAEJAQAAAA==.Slipknight:BAAALgADCgYJBgAAAA==.Slobbrknckr:BAAALgAECgYJBgABLgAFFAQJBwAaAIESAA==.Sloppydemon:BAAALgAECgYJDwAAAA==.Slowmo:BAAALgADCgEJAQAAAA==.Slyrak:BAAALgADCggJDgAAAA==.',
Sm='Smittles:BAABLgAECn8XAAQfAAgJhA/ROABXAQAfAAcJoBDROABXAQAeAAMJbQdCEwBeAAAEAAEJ3wgAAAAAAAAAAA==.Smolschmeaty:BAAALgADCgEJAQAAAA==.Smple:BAAALgAECgYJEwAAAA==.',
Sn='Snartfiffer:BAAALgAECgEJAQAAAA==.Snippbear:BAAALgAECgYJBQAAAA==.Snëk:BAABLgAECn8WAAImAAYJGwt4HADnAAAmAAYJGwt4HADnAAAAAA==.',
So='Sokhin:BAAALgAECgYJDQABLgAECgcJHAAWAHMeAA==.Soline:BAAALgADCgkJJQAAAA==.Somadru:BAAALgAECgYJDQAAAA==.Somamonk:BAAALgAECggJCAAAAA==.Somapal:BAAALgAECgUJBQAAAA==.Somasham:BAAALgAECgIJAgAAAA==.Sonshine:BAAALgADCggJDgAAAA==.Sophus:BAAALgAECgMJBAAAAA==.Soren:BAABLgAECn8cAAIWAAcJcx4KCAATAgAWAAcJcx4KCAATAgAAAA==.Sorete:BAAALgADCgMJAwABLgAECgcJHAAWAHMeAA==.Sortia:BAAALgADCgUJCAAAAA==.Sothotha:BAAALgADCgIJAgAAAA==.',
Sp='Spagooter:BAACLgAFFH8IAAIcAAMJBRurJAANAQAcAAMJBRurJAANAQAuAAQKfyMAAxwACAm9IKspAGoCABwABwm9IKspAGoCABsAAQkAAAwmAFkAAAAA.Sparklepants:BAACLgAFFH8IAAIFAAMJghjXLwALAQAFAAMJghjXLwALAQAuAAQKfxwAAgUACAkjIaYeAPoCAAUACAkjIaYeAPoCAAAA.Spicyadams:BAAALgADCgQJAgAAAA==.Spinachdip:BAAALgAECgQJBAAAAA==.Spunnilingus:BAAALgAECgYJDwAAAA==.Spyfamily:BAAALgADCgcJBwAAAA==.',
Sq='Squidsten:BAAALgAECgcJEgAAAA==.',
Sr='Sren:BAAALgAECgUJBQABLgAECgcJHAAWAHMeAA==.',
St='Stabzya:BAAALgADCgQJBAAAAA==.Starslayer:BAABLgAECn8bAAMDAAgJRxiTCAAiAgADAAgJRxiTCAAiAgACAAIJfxADKwBuAAAAAA==.Stevemo:BAAALgAECgUJCQAAAA==.Stillness:BAAALgADCgYJBgAAAA==.Stonemason:BAAALgAECgYJDgAAAA==.Stopover:BAAALgADCgYJBgAAAA==.Strechy:BAAALgAECgEJAQAAAA==.Stril:BAAALgAECgEJAQAAAA==.Strongcarote:BAAALgAECgUJCgAAAA==.Stórr:BAAALgAECgEJAQAAAA==.',
Su='Subakiie:BAAALgAECgYJCQAAAA==.Submisive:BAAALgAECgQJCQAAAA==.Suitcase:BAAALgADCgMJAwAAAA==.Sumting:BAAALgADCgcJBwAAAA==.Supaxhot:BAAALgAECggJDgAAAA==.',
Sv='Svish:BAABLgAECn8TAAIRAAgJRxTmFgCxAQARAAgJRxTmFgCxAQAAAA==.',
Sw='Swaellen:BAAALgADCgMJAwAAAA==.Swagruid:BAABLgAECn8UAAIhAAcJVwwyMQAXAQAhAAcJVwwyMQAXAQAAAA==.Swampcaller:BAAALgAECgMJAwABLgAECggJLAAFAPYdAA==.Swampdonkey:BAAALgADCggJFQABLgAECggJLAAFAPYdAA==.Swampslinger:BAABLgAECn8sAAIFAAgJ9h0EEgBLAgAFAAgJ9h0EEgBLAgAAAA==.Swordlady:BAAALgAECgEJAQABLgAECggJLQANAJEdAA==.',
Sy='Sylpha:BAAALgAECgcJEQAAAA==.Symorenner:BAAALgADCgUJBQABLgAECgYJDQALAAAAAA==.Syndragos:BAAALgAECgYJCQAAAA==.Synoria:BAAALgADCgkJEQAAAA==.Synroshi:BAAALgAECgEJAQAAAA==.Syntala:BAAALgAECgQJCgAAAA==.Syntari:BAAALgADCgEJAQAAAA==.',
['Sä']='Sänll:BAAALgAECgEJAQAAAA==.',
Ta='Talenalat:BAAALgAECgYJCwAAAA==.Talfa:BAAALgADCgYJBwAAAA==.Tankaa:BAAALgADCgUJCwAAAA==.Tarnuz:BAAALgADCgEJAQAAAA==.Tatsuni:BAAALgAECggJCgAAAA==.Taymatt:BAAALgAECgYJEwAAAA==.Tazina:BAAALgADCgEJAQAAAA==.Tazstinko:BAABLgAECn84AAIkAAkJ+iPrAQCoAwAkAAkJ+iPrAQCoAwAAAA==.',
Te='Teepot:BAAALgADCgIJAwAAAA==.Tejasgeek:BAAALgAECgYJDAAAAA==.Templordan:BAAALgAECgYJCwAAAA==.Tenntoes:BAABLgAECn8dAAMGAAgJniC0BwBLAgAGAAcJ4x20BwBLAgAcAAcJpRsrDgA5AgAAAA==.Termuda:BAAALgAECgkJBwAAAA==.',
Th='Thalanil:BAAALgAECgQJCQAAAA==.Thalema:BAAALgAECgcJEgAAAA==.Tharaven:BAAALgAECgcJBgAAAA==.Thegoob:BAAALgAECgEJAgAAAA==.Themuffinman:BAAALgAECgYJCwAAAA==.Thenazera:BAAALgAECgUJBwAAAA==.Theworrirawr:BAAALgAFFAEJAQAAAA==.Thiccfilaa:BAAALgAECggJEQAAAA==.Thornan:BAAALgADCgQJBAAAAA==.Threeskin:BAAALgAECgQJBAAAAA==.Thunderess:BAAALgADCgYJBgAAAA==.Thur:BAABLgAECn8ZAAIaAAYJVxePPgBOAQAaAAYJVxePPgBOAQAAAA==.Thymera:BAAALgADCgYJBwAAAA==.',
Ti='Tiandor:BAAALgADCgMJBAAAAA==.Tinyclash:BAAALgAECgYJBwAAAA==.Tinyfel:BAAALgAECgYJEAAAAA==.Tizef:BAAALgAECgMJBgAAAA==.',
To='Toddhoward:BAAALgAECgEJAQAAAA==.Toestalker:BAAALgAECgYJDwAAAA==.Tokaiteio:BAAALgADCgUJBwAAAA==.Tokilock:BAAALgADCgQJBAAAAA==.Toldyousoul:BAAALgAECgQJCwAAAA==.Tonarui:BAAALgADCgYJBgAAAA==.Tonytots:BAAALgADCgcJDQAAAA==.Toon:BAAALgAECgQJDQAAAA==.Tormentaa:BAAALgAECgIJAgAAAA==.Torruid:BAAALgAECgYJDAAAAA==.Torsha:BAAALgADCgUJBQAAAA==.Toscha:BAAALgADCgEJAQAAAA==.Toxikil:BAABLgAECn8lAAMHAAgJcxSmAwCvAQAHAAgJUBOmAwCvAQAmAAcJnRE2LgCQAQAAAA==.',
Tr='Traelirra:BAAALgADCgYJCAAAAA==.Travian:BAAALgAECgYJAQAAAA==.Treebeard:BAAALgADCgIJAgAAAA==.Treebirth:BAACLgAFFH8KAAIhAAMJWReeFQDqAAAhAAMJWReeFQDqAAAuAAQKfyIAAiEACAlqGh8lACUCACEACAlqGh8lACUCAAAA.Treestezza:BAAALgADCggJDQAAAA==.Troyano:BAAALgAECgEJAQAAAA==.Trunder:BAABLgAECn8cAAIDAAYJhRlECABdAQADAAYJhRlECABdAQAAAA==.',
Tw='Tweaks:BAAALgAECgkJDQAAAA==.Twinkies:BAAALgADCgcJBwAAAA==.',
Tz='Tzugo:BAAALgADCgMJAwAAAA==.',
['Tâ']='Tâmaÿa:BAAALgADCgYJBgAAAA==.',
['Té']='Téderiata:BAAALgAECgQJDAAAAA==.',
Ud='Udekar:BAAALgADCgMJBQAAAA==.Uders:BAABLgAECn8WAAIUAAYJYhwsLgDRAQAUAAYJYhwsLgDRAQAAAA==.',
Ul='Ultradrac:BAAALgAECgQJBwABLgAECgYJDgALAAAAAA==.Ultramad:BAAALgAECgEJAQABLgAECggJHwATAIAhAA==.Ultramellow:BAAALgADCgUJBwABLgAECggJHwATAIAhAA==.Ulubai:BAAALgAECgEJAQAAAA==.',
Um='Umaulk:BAAALgAECgEJAQAAAA==.',
Un='Unclebunzo:BAAALgAECgMJAwAAAA==.Unclejames:BAAALgADCgcJDAAAAA==.Unmarked:BAABLgAECn8cAAIfAAkJYh4hBwCsAgAfAAkJYh4hBwCsAgAAAA==.',
Up='Upngo:BAACLgAFFH8FAAMkAAQJ+BGKIwBOAAAkAAIJawmKIwBOAAAjAAIJEiNADgAoAAAuAAQKfzUAAyMACAntHh0IADYCACQACAnwGEQWAJsCACMACAlKGh0IADYCAAAA.',
Ur='Urotherdaddy:BAAALgADCgcJDAABLgAECgYJEQALAAAAAA==.',
Va='Vaelys:BAAALgADCgEJAQAAAA==.Vaerel:BAAALgADCgYJBgAAAA==.Valandine:BAAALgADCgcJDgAAAA==.Vandarras:BAAALgAECgEJAQAAAA==.Vandredor:BAACLgAFFH8NAAMRAAUJrw07DQBnAQARAAUJrw07DQBnAQAnAAEJYwBiBgAvAAAuAAQKfxUAAxEABgkQH5JfAIIBABEABgkQH5JfAIIBACcABgnmEfkWAO0AAAAA.Varate:BAAALgAECgYJDgAAAA==.Vasträ:BAAALgAECgMJBQAAAA==.Vatal:BAABLgAECn8XAAMjAAcJ/RjZDQDAAQAjAAYJshrZDQDAAQAkAAQJPA41NAC7AAAAAA==.',
Ve='Veladorastia:BAAALgADCgYJCwAAAA==.Velasha:BAAALgADCgMJAwAAAA==.Velcryn:BAAALgADCgQJBAAAAA==.Velicelia:BAAALgAECgYJDgAAAA==.Vellindrys:BAAALgAECgYJDQAAAA==.Veloriel:BAAALgADCgEJAQAAAA==.Venusaur:BAAALgAECgYJDgAAAA==.Veronika:BAAALgADCgcJBwAAAA==.',
Vi='Vince:BAAALgAECgQJCAAAAA==.Vizak:BAAALgADCgUJCAAAAA==.Vizzak:BAABLgAECn8UAAIiAAcJpwnnFADkAAAiAAcJpwnnFADkAAAAAA==.',
Vl='Vladis:BAABLgAECn8ZAAIaAAYJiwu+agDaAAAaAAYJiwu+agDaAAAAAA==.Vlasic:BAAALgAECgUJCAAAAA==.',
Vo='Voidraybih:BAAALgADCgMJAwAAAA==.Voljinx:BAAALgAECgQJBwAAAA==.',
Vu='Vup:BAAALgADCgEJAQAAAA==.',
Vy='Vynestia:BAAALgADCggJCwAAAA==.',
['Vä']='Vääko:BAAALgAECgYJDgAAAA==.',
Wa='Wagyyu:BAAALgAECgYJBgAAAA==.Walldo:BAAALgADCgEJAQAAAA==.Waluigi:BAAALgAECgQJBAABLgAECgYJFgASAGsRAA==.Warriornos:BAAALgADCgYJBwAAAA==.Wayvrn:BAABLgAECn8pAAIFAAgJeBeFNQCPAQAFAAgJeBeFNQCPAQAAAA==.',
We='Weki:BAAALgAECgUJCgAAAA==.Welimarx:BAAALgAECgMJBQAAAA==.Westbrooke:BAAALgADCggJCAAAAA==.Westinghouse:BAAALgADCgYJBgAAAA==.Wetshrimp:BAABLgAECn8pAAIaAAgJACTAAwDmAgAaAAgJACTAAwDmAgABLgAFFAMJBQAcAJoJAA==.',
Wh='Whippoorwill:BAABLgAECn8nAAIWAAgJgRowGABIAgAWAAgJgRowGABIAgAAAA==.Whisky:BAAALgADCgcJDAAAAA==.Whosman:BAAALgADCgIJAgAAAA==.',
Wi='Wikkid:BAAALgAECgEJAQAAAA==.Wisdomcheck:BAAALgAECgMJAwAAAA==.',
Wo='Woe:BAAALgAECgIJAwABLgAECgQJDQALAAAAAA==.Wolfnacht:BAAALgAECgYJBgAAAA==.',
Wr='Wrathfil:BAAALgAECgYJDQAAAA==.Wrene:BAAALgAFFAMJAwAAAA==.',
Xe='Xehanerd:BAAALgADCgMJAwAAAA==.Xendar:BAAALgADCgcJBwAAAA==.Xene:BAABLgAECn8YAAIVAAcJ7RrhHwARAgAVAAcJ7RrhHwARAgAAAA==.',
Xi='Xino:BAAALgAECgMJBgAAAA==.',
Xo='Xorthos:BAAALgAECgEJAQAAAA==.',
Ya='Yagirlmolli:BAAALgADCgEJAQAAAA==.Yahla:BAAALgAECgYJCgAAAA==.Yakiki:BAAALgAECgcJCgABLgAFFAYJHgAXAHUiAA==.Yallah:BAAALgADCgMJAwAAAA==.Yanedin:BAABLgAECn8kAAITAAkJZQiPGgArAQATAAkJZQiPGgArAQAAAA==.Yathr:BAAALgADCgUJBgAAAA==.',
Ye='Yearp:BAAALgADCgMJAwAAAA==.Yethril:BAAALgAECgUJBQAAAA==.',
Yi='Yippeezippee:BAAALgADCgEJAQAAAA==.',
Yn='Ynrghost:BAAALgAECgUJDAAAAA==.',
Yo='Yorastai:BAAALgADCgkJCQAAAA==.Yorforger:BAAALgAECgIJAgABLgAECggJEAALAAAAAA==.Youngbj:BAAALgAECgIJAgABLgAFFAIJAgALAAAAAA==.Yousaidit:BAAALgADCgUJBgABLgAECggJHAAFAJkVAA==.',
Ys='Yserene:BAAALgADCggJHAAAAA==.',
Yu='Yukonilock:BAAALgADCgcJDwABLgAECgcJEwALAAAAAA==.Yukonícus:BAAALgAECgYJCAABLgAECgcJEwALAAAAAA==.Yukonïcus:BAAALgAECgcJEwAAAA==.Yumm:BAAALgADCgMJAwAAAA==.',
['Yè']='Yènnefer:BAAALgAECgEJAQAAAA==.',
Za='Zabyr:BAAALgADCgcJBwAAAA==.Zaffeine:BAAALgADCgYJBgAAAA==.Zaladorine:BAAALgADCgMJBgAAAA==.Zaldrena:BAAALgADCgQJBgAAAA==.Zanotgaming:BAAALgAECgcJEwAAAA==.Zaíde:BAAALgADCgcJBwAAAA==.',
Zb='Zbrickashaw:BAAALgAECgUJBQAAAA==.',
Ze='Zelrin:BAACLgAFFH8SAAIFAAYJnhaECwDBAQAFAAYJnhaECwDBAQAuAAQKfx8AAwUACAlZIRUeAP0CAAUACAlZIRUeAP0CAAoAAQk/ByIfADIAAAAA.Zendara:BAAALgAECgMJBAAAAA==.Zenthalion:BAAALgAECgYJDwAAAA==.Zephïre:BAAALgAECgEJAQAAAA==.Zeridar:BAAALgAECgQJBQAAAA==.Zesyus:BAAALgAECgEJAQAAAA==.',
Zi='Zippee:BAAALgAECgUJBQAAAA==.Zippies:BAAALgAECgQJBAAAAA==.',
Zo='Zobz:BAAALgADCgUJBQAAAA==.Zoomhunt:BAACLgAFFH8WAAMlAAUJSCHrAQCIAQAlAAUJAiDrAQCIAQAgAAQJMxxJCwBkAQAuAAQKfzIAAyAACQk5JfYCAHwDACAACAkXJvYCAHwDACUAAwk6ItYTAC8BAAAA.Zorgborg:BAAALgADCgEJAgAAAA==.',
Zr='Zral:BAAALgADCgMJBAAAAA==.',
Zu='Zutter:BAAALgAECgYJEwAAAA==.',
Zx='Zxy:BAAALgAECgQJBQAAAA==.',
['Íf']='Ífrosty:BAAALgADCgYJBgAAAA==.',
['Ör']='Ördög:BAAALgADCgUJBQAAAA==.',
['ße']='ßearheals:BAAALgADCgcJDAAAAA==.',
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

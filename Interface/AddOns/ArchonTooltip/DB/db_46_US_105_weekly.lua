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

local lookup = {'Paladin-Holy','DeathKnight-Blood','Mage-Frost','Warlock-Destruction','Unknown-Unknown','DemonHunter-Havoc','Priest-Holy','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Shaman-Elemental','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Retribution','Druid-Guardian','Druid-Feral','Paladin-Protection','Warlock-Affliction','Warlock-Demonology','DeathKnight-Unholy','Hunter-Marksmanship','Rogue-Assassination','Priest-Discipline','Shaman-Restoration','Priest-Shadow','Druid-Restoration','Warrior-Fury','Druid-Balance','Hunter-Survival','Shaman-Enhancement','Warrior-Protection','Rogue-Subtlety','Warrior-Arms','DemonHunter-Vengeance','Mage-Arcane',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aadolin:BAABLgAECn8XAAIBAAYJMCCxHAAwAgABAAYJMCCxHAAwAgAAAA==.',
Ab='Abmtt:BAAALgAFFAIJAwAAAA==.Abraxxy:BAAALgADCgkJDQAAAA==.',
Ac='Acalirra:BAAALgAECgEJAQAAAA==.Acorazado:BAAALgADCgEJAQAAAA==.',
Ad='Adeillia:BAABLgAECn8UAAICAAcJ/RGxGgB7AQACAAcJ/RGxGgB7AQAAAA==.Adeleska:BAABLgAECn8UAAIDAAcJ5gF+QAC+AAADAAcJ5gF+QAC+AAAAAA==.Aderina:BAAALgADCggJCAAAAA==.Aderon:BAAALgAECgYJCgAAAA==.',
Ae='Aelkete:BAAALgAECgIJAgAAAA==.Aelorion:BAAALgAECgEJAgAAAA==.Aeovina:BAABLgAECn8WAAIEAAgJaRDbAQCSAQAEAAgJaRDbAQCSAQAAAA==.Aertenn:BAAALgADCggJHAAAAA==.',
Ag='Agrash:BAAALgADCgEJAgAAAA==.',
Ai='Aiin:BAAALgAECgkJBwAAAA==.Aikar:BAAALgAECggJDgAAAA==.Airasalt:BAAALgAECgcJBwAAAA==.Airassault:BAAALgAECgcJBAAAAA==.Airazzault:BAAALgADCgYJBgAAAA==.',
Ak='Akameuchiha:BAAALgAECgUJDgAAAA==.Akfirefly:BAAALgADCgIJAgAAAA==.Akrog:BAAALgAECgMJAwAAAA==.Akícita:BAAALgADCgMJAwAAAA==.',
Al='Albu:BAAALgAECgcJEgAAAA==.Alianz:BAAALgADCgYJCwAAAA==.Althiel:BAAALgADCgUJCAAAAA==.',
Am='Amaellara:BAAALgAECgYJEgAAAA==.Amoralanth:BAAALgAECgcJBwAAAA==.Ams:BAAALgADCgkJDwAAAA==.',
An='Annabel:BAAALgAECgIJAgAAAA==.Anthatheus:BAAALgAECgUJCQAAAA==.',
Ao='Aoda:BAAALgAECgUJBQABLgAECgcJCQAFAAAAAA==.Aotrom:BAAALgADCgYJBgAAAA==.',
Aq='Aqualina:BAAALgAECgIJAgAAAA==.',
Ar='Arashu:BAAALgADCgEJAQAAAA==.Arba:BAAALgADCggJEAAAAA==.Arcanefire:BAAALgAECgYJCwAAAA==.Arckaius:BAAALgADCgcJDgAAAA==.Arcusu:BAAALgAECgQJBAAAAA==.',
As='Ashlevelle:BAAALgAECgMJAwAAAA==.Asterixx:BAAALgAECgUJBgAAAA==.Astralock:BAAALgADCgMJAwAAAA==.Astrea:BAAALgAECgEJAwAAAA==.',
Au='Audare:BAABLgAECn8ZAAIGAAYJdh1aBQBzAQAGAAYJdh1aBQBzAQAAAA==.Augmentism:BAAALgAECgIJAwAAAA==.Auzkaa:BAAALgADCgQJBAAAAA==.',
Av='Avarya:BAABLgAECn8ZAAIHAAgJOyX7AQBUAwAHAAgJOyX7AQBUAwAAAA==.Averagelock:BAAALgAECgcJCQABLgAFFAMJBwAIAG8RAA==.Averagevoker:BAACLgAFFH8HAAQIAAMJbxFzBwCOAAAIAAIJ9wtzBwCOAAAJAAIJ0wRGFACFAAAKAAEJXhyQHwBVAAAuAAQKfxcABAgACAmRHFsPAOUBAAgABwl3G1sPAOUBAAoABQm6H64hALEBAAkAAgmdCv4+AHMAAAAA.Averwine:BAAALgADCggJCQAAAA==.Avvala:BAAALgAECgEJAwAAAA==.',
Aw='Awangboboi:BAAALgADCgYJCAAAAA==.',
Az='Azhara:BAABLgAECn8XAAILAAYJXg57dwBAAQALAAYJXg57dwBAAQAAAA==.',
Ba='Babychow:BAAALgADCgEJAQAAAA==.Baconlocks:BAAALgAECgQJCQAAAA==.Badgermilk:BAAALgADCgIJAgAAAA==.Badragon:BAABLgAECn8VAAQKAAcJSxfzKgBoAQAKAAUJdRnzKgBoAQAIAAQJeA/AKADaAAAJAAMJegtMOwCQAAABLgAFFAUJDwAKAPwaAA==.Baeleshea:BAAALgADCgcJBwAAAA==.Bagchi:BAABLgAECn8bAAMMAAgJpiEgDgCbAgAMAAcJLh8gDgCbAgANAAQJ5h1gSAAgAQAAAA==.Bairian:BAAALgADCgcJCwAAAA==.Balsagnafays:BAAALgADCgYJBgAAAA==.Bamboozle:BAEALgAECgcJCQAAAA==.Baned:BAAALgADCgUJBQAAAA==.Barema:BAAALgAECgYJDwAAAA==.Bartokk:BAAALgAECgEJAQAAAA==.Bashtaz:BAAALgADCgYJBgABLgAFFAUJFAAOAPAhAA==.Bawitab:BAAALgAECgYJEQAAAA==.Bawler:BAAALgAECgUJDAAAAA==.',
Be='Beanbagbear:BAAALgADCgUJBQABLgAECgYJFAAPAPkaAA==.Bearforceone:BAAALgADCgEJAQAAAA==.Bearykyns:BAAALgAECgYJEQAAAA==.Beastwarden:BAAALgAECgQJCgAAAA==.Belenath:BAAALgAECgYJBgAAAA==.Belgo:BAAALgADCgcJDQAAAA==.Belladar:BAAALgADCgIJAwAAAA==.Belphania:BAAALgADCgEJAQAAAA==.Bemused:BAAALgAECgUJDAAAAA==.Benefitmonk:BAABLgAECn8rAAIQAAgJUx8XAgBqAgAQAAgJUx8XAgBqAgAAAA==.Benefitwar:BAAALgADCgIJAgAAAA==.Berrishorti:BAAALgAECgcJCQAAAA==.',
Bi='Bigsock:BAAALgADCgMJAwAAAA==.Bigsocs:BAAALgADCgYJBwAAAA==.',
Bl='Blackbow:BAAALgAECgYJDAAAAA==.Blackleaf:BAAALgAECgEJAQABLgAECgYJDAAFAAAAAA==.Blazeweaver:BAAALgADCgIJAgAAAA==.Blep:BAAALgAECgcJDwAAAA==.Blindluck:BAAALgADCgUJBQAAAA==.Blites:BAAALgAECgUJDAAAAA==.Blitzø:BAAALgAECgcJEwAAAA==.Blueheal:BAAALgAECgIJAgAAAA==.Bluemilk:BAABLgAECn8VAAIBAAYJ9xlqOwCMAQABAAYJ9xlqOwCMAQAAAA==.',
Bo='Bobafet:BAAALgADCgIJAgAAAA==.Bobwayjr:BAACLgAFFH8MAAIDAAQJyB+gEQCJAQADAAQJyB+gEQCJAQAuAAQKfx8AAgMACAmDJu0HAIoDAAMACAmDJu0HAIoDAAAA.Bojo:BAAALgADCgcJCgAAAA==.Bonboof:BAAALgADCgEJAQAAAA==.Boneshadow:BAAALgADCgYJBgAAAA==.Bonnieve:BAAALgADCgYJBgAAAA==.Boombada:BAAALgADCgYJCAAAAA==.Borderline:BAAALgADCgMJAwAAAA==.Bournefang:BAAALgAECgMJAwAAAA==.Bowlinder:BAACLgAFFH8FAAIPAAQJTBq9DgABAQAPAAQJTBq9DgABAQAuAAQKfxkAAg8ABwm9Ia0RAJcCAA8ABwm9Ia0RAJcCAAAA.',
Br='Braestirina:BAAALgADCgMJAgAAAA==.Braldar:BAAALgAECgUJBgAAAA==.Braxiss:BAABLgAECn8gAAIRAAgJ1B3lEQCpAgARAAgJ1B3lEQCpAgAAAA==.Breakadinn:BAACLgAFFH8HAAISAAQJDCNlBQA7AQASAAQJDCNlBQA7AQAuAAQKfxkAAhIACQlJJYoBAMwDABIACQlJJYoBAMwDAAEuAAUUBAkHABIADCMA.Breakalegg:BAAALgAECgMJAwAAAA==.Brilin:BAAALgAECgYJDQAAAA==.Broguë:BAAALgAECgQJCAAAAA==.Brucarus:BAAALgAECgcJCQAAAA==.Bruceleex:BAAALgAECgEJAQAAAA==.Brueld:BAAALgAECgIJAwAAAA==.',
Bu='Bumond:BAAALgADCgYJCQAAAA==.Burrito:BAAALgADCgEJAQAAAA==.Busin:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäwitaba:BAAALgAECgEJAQAAAA==.',
Ca='Calabag:BAAALgAECgMJAwABLgAECggJGwAMAKYhAA==.Calabloom:BAAALgADCgcJBwABLgAECggJGwAMAKYhAA==.Calahunt:BAAALgADCgUJBQABLgAECggJGwAMAKYhAA==.Calapriest:BAAALgADCggJDgABLgAECggJGwAMAKYhAA==.Calasmash:BAAALgADCgQJBAABLgAECggJGwAMAKYhAA==.Calendre:BAAALgADCggJDQAAAA==.Capheira:BAAALgADCgcJBwAAAA==.Carlidruid:BAAALgAECgMJAwAAAA==.Carlinofuoco:BAAALgAECgUJCwAAAA==.Caswynde:BAAALgADCgQJBQAAAA==.Cavalina:BAAALgAECgMJAwAAAA==.Cavick:BAAALgAECgYJEwAAAA==.Cayleth:BAAALgADCgYJCQAAAA==.',
Ce='Celyanar:BAAALgADCgYJCgAAAA==.Cereas:BAAALgAECgYJDwAAAA==.',
Ch='Chainsoul:BAAALgAECgMJAwAAAA==.Chancec:BAAALgADCgcJCQAAAA==.Chanpaanda:BAAALgADCgMJAwAAAA==.Chantalle:BAAALgADCgMJBgAAAA==.Charliedruid:BAAALgAECgQJBwAAAA==.Charsham:BAAALgAECgUJBQAAAA==.Charön:BAABLgAECn8gAAIDAAgJTxbbEgCrAQADAAgJTxbbEgCrAQAAAA==.Chentrocka:BAABLgAECn8jAAIDAAgJKiDuIQDrAgADAAgJKiDuIQDrAgAAAA==.Cherine:BAABLgAECn8bAAMTAAgJEBQlCwDfAQATAAgJEBQlCwDfAQAUAAQJyQ3jJACrAAAAAA==.Cherrytomato:BAAALgAECgIJAgAAAA==.Chervil:BAAALgAFFAEJAQABLgAFFAMJBwAIAG8RAA==.Chhr:BAAALgAECgMJBAAAAA==.Chicakes:BAAALgADCgcJDgAAAA==.Chiillyy:BAAALgAECgYJDgAAAA==.Chikaahh:BAAALgAECgIJAgAAAA==.Chillbruh:BAAALgAECgYJAwAAAA==.Chillydroo:BAAALgADCgYJCgABLgAECggJDAAFAAAAAA==.Chiselin:BAAALgAECgUJBgAAAA==.Chktmilk:BAAALgADCgUJBQAAAA==.Chohh:BAAALgADCgEJAQAAAA==.Chronoflames:BAAALgAECgUJBQAAAA==.Chuckversus:BAAALgADCgYJBgAAAA==.Chugchug:BAAALgAECgYJCAAAAA==.Chunkernot:BAAALgAECgQJBAAAAA==.Chàrron:BAAALgADCgMJBgAAAA==.',
Ci='Cicee:BAAALgADCgkJGwAAAA==.Cigsinside:BAAALgAECgQJBAAAAA==.',
Ck='Ckdruid:BAAALgAECgUJBwAAAA==.',
Cl='Clerikyns:BAAALgADCgMJBQABLgAECgYJEQAFAAAAAA==.Clicks:BAAALgAECgUJBwAAAA==.Clics:BAAALgAECgQJCAAAAA==.',
Co='Coalgrim:BAAALgAECgYJDgAAAA==.Cohiba:BAAALgAECgEJAQAAAA==.Coldflames:BAABLgAECn8YAAIMAAgJICQKBgAhAwAMAAgJICQKBgAhAwAAAA==.Coldmountain:BAAALgADCgQJBAAAAA==.Coldonn:BAAALgAECgQJBwAAAA==.Confuzed:BAAALgADCgEJAQAAAA==.Continental:BAAALgADCgIJAgAAAA==.Coolbeans:BAAALgADCgMJAwAAAA==.Coprozonodo:BAAALgAECgQJCAAAAA==.Cowsoup:BAAALgAECgIJAQAAAA==.Cozmos:BAAALgAECgEJAgAAAA==.',
Cr='Cravenn:BAAALgADCgEJAQAAAA==.Cravins:BAAALgAECgYJBgAAAA==.Craziness:BAAALgAECgUJBwAAAA==.Creambeam:BAAALgAECgUJBAAAAA==.Cremedently:BAAALgAECggJEwAAAA==.Crewsader:BAAALgADCgQJBAAAAA==.Critnyspears:BAAALgAECgMJAwAAAA==.Crowdie:BAAALgADCgcJCwAAAA==.Crowlett:BAABLgAECn8kAAIVAAgJ+xu4CABMAgAVAAgJ+xu4CABMAgAAAA==.',
Cu='Curoconcum:BAAALgAECgIJAgAAAA==.',
Cy='Cyllene:BAAALgADCgMJAwAAAA==.Cypher:BAAALgADCgIJAgAAAA==.Cyrub:BAAALgAECgIJAgAAAA==.',
Da='Daboneman:BAAALgADCgYJBgAAAA==.Dabrinto:BAAALgAECgQJBwAAAA==.Daelith:BAAALgADCgIJAgAAAA==.Daemonmortis:BAABLgAECn8VAAQWAAUJ1wVJHACQAAAXAAQJJgRz3QCfAAAWAAMJlQVJHACQAAAEAAQJXQV5WgBfAAAAAA==.Daidomrag:BAEALgADCgQJBAABLgADCgcJDAAFAAAAAA==.Dainsleif:BAAALgAECgEJAQAAAA==.Daiya:BAAALgADCgUJBgAAAA==.Damndelion:BAAALgAECgYJEAAAAA==.Dankweaver:BAAALgAECgYJEwAAAA==.Daoloth:BAAALgADCgcJBwAAAA==.Darazen:BAAALgADCgUJBgAAAA==.Darkviper:BAAALgAECgEJAQAAAA==.Darkzonex:BAAALgAECgEJAgAAAA==.Darthxander:BAAALgAECgcJDgAAAA==.Dasir:BAAALgAECgYJBgAAAA==.Daskinny:BAAALgAECgEJAQAAAA==.Dattoo:BAAALgADCgMJAwAAAA==.Dazuk:BAAALgAECgIJAgAAAA==.',
De='Deadbølt:BAAALgAECgYJEAAAAA==.Deberry:BAAALgADCgUJCAAAAA==.Deevine:BAAALgADCgEJAQAAAA==.Deformjr:BAAALgADCgUJCQAAAA==.Dehll:BAAALgADCgYJBgAAAA==.Demonarmy:BAAALgADCgUJBQAAAA==.Demonics:BAAALgAECgQJBAAAAA==.Demonos:BAAALgADCggJDQAAAA==.Demonstix:BAAALgADCgMJAwABLgAECgUJDAAFAAAAAA==.Demontoki:BAAALgADCgcJDQAAAA==.Depressa:BAABLgAECn8YAAIDAAgJgBxBNwCXAgADAAgJgBxBNwCXAgAAAA==.Devilslip:BAAALgAECgEJAQAAAA==.Dewfall:BAAALgAECgYJCgAAAA==.Deydrayn:BAAALgADCgYJCAAAAA==.',
Di='Dialtone:BAAALgAECgEJAQAAAA==.Diamondeyes:BAAALgAECgUJDAAAAA==.Dibbington:BAABLgAECn8UAAMOAAgJPAMrBQDAAAAOAAgJDwMrBQDAAAAYAAQJUwJO/wB7AAAAAA==.Diggen:BAAALgADCgUJBgAAAA==.Diio:BAAALgAECgMJAwAAAA==.Dilfydee:BAAALgAECgIJAgAAAA==.Dinakeri:BAAALgAECgMJAwAAAA==.Dinda:BAABLgAECn8bAAIRAAcJQCE8EQCvAgARAAcJQCE8EQCvAgAAAA==.Disdrag:BAACLgAFFH8PAAMKAAUJBCIvBADQAQAKAAUJBCIvBADQAQAIAAEJmg3YCQBUAAAuAAQKfx0AAwoACAlqJRkFADkDAAoACAkdJRkFADkDAAgABwlNJEMJAE0CAAAA.Dixierekt:BAAALgADCggJDgAAAA==.',
Dk='Dkkiller:BAAALgAECgQJCAAAAA==.Dkmetcàlf:BAABLgAECn8cAAIYAAkJdhEeCgDdAQAYAAkJdhEeCgDdAQAAAA==.',
Do='Dohane:BAAALgADCgYJCQAAAA==.Domatize:BAAALgAECgYJCgAAAA==.Domineera:BAAALgADCgYJBgAAAA==.Donutchan:BAAALgAECgcJDwAAAA==.Doof:BAAALgAECgQJBwAAAA==.Doopity:BAAALgADCgkJGgAAAA==.',
Dr='Dracosoup:BAAALgADCgcJBwAAAA==.Dragonstix:BAAALgAECgUJDAAAAA==.Drahkula:BAAALgAECgEJAQAAAA==.Dreamerzz:BAAALgAECgQJBQAAAA==.Dredblade:BAAALgADCgkJGgAAAA==.Drockan:BAAALgADCgcJBgAAAA==.Drovac:BAAALgAECgUJCAAAAA==.Drudyy:BAAALgAECgUJCQAAAA==.Drugar:BAAALgADCgEJAQAAAA==.Druidxd:BAAALgAECgIJAwAAAA==.',
Du='Dubbies:BAAALgAECgQJBAAAAA==.Dumplins:BAAALgAECgQJBAABLgAECgcJDQAFAAAAAA==.Durtluz:BAAALgAECgUJBwAAAA==.',
Dy='Dyrim:BAAALgAECgIJAgAAAA==.',
['Dê']='Dêformjr:BAAALgAECgYJBwAAAA==.',
['Dú']='Dúbletap:BAABLgAECn8fAAIZAAgJrR4tDgDPAgAZAAgJrR4tDgDPAgAAAA==.',
Ea='Eajae:BAAALgADCgcJDgAAAA==.',
Eb='Ebidxd:BAAALgADCgMJAwAAAA==.',
Ed='Edavina:BAAALgADCgIJAgAAAA==.',
Ei='Eilaenil:BAAALgAECgEJAQAAAA==.',
Ek='Ekanta:BAAALgADCgEJAQAAAA==.',
El='Elani:BAAALgAECgcJDQAAAA==.Electricia:BAAALgAECgQJBAAAAA==.Elenii:BAABLgAECn8lAAIHAAgJgx1WAQCTAgAHAAgJgx1WAQCTAgAAAA==.Elinyra:BAAALgADCgkJFgAAAA==.Elisagrey:BAAALgAECgQJBgAAAA==.Elishia:BAAALgADCgMJAQAAAA==.Ellbosyou:BAAALgAECgYJEgAAAA==.Elmadget:BAAALgADCgYJBgAAAA==.Elybere:BAAALgADCgEJAQAAAA==.',
Em='Emdash:BAAALgADCgEJAQAAAA==.Emmaava:BAABLgAECn8eAAIVAAgJawuTGABQAQAVAAgJawuTGABQAQAAAA==.Emptyside:BAAALgADCgkJHgAAAA==.',
En='Enchorxxi:BAAALgAECgYJEAAAAA==.Enetrenazara:BAAALgADCgUJBQAAAA==.Engage:BAAALgADCgMJAwABLgAECgcJDwAFAAAAAA==.Enkidudu:BAAALgAECgcJBwAAAA==.',
Ep='Epicgooner:BAAALgAECgIJBQAAAA==.',
Er='Eraeliice:BAAALgADCgYJBgAAAA==.Erahm:BAAALgAECgEJAQAAAA==.Erahmm:BAABLgAECn8VAAIYAAcJHQdCHQAxAQAYAAcJHQdCHQAxAQAAAA==.',
Es='Eskanore:BAAALgADCgcJCgAAAA==.',
Eu='Eule:BAEALgAECgQJCQAAAA==.',
Ev='Evilicecream:BAAALgAECgUJCwABLgAECgcJFwAKAF4RAA==.Evokil:BAAALgAECgEJAQABLgAECgcJIQAaALQVAA==.Evoktune:BAAALgAECgEJAQABLgAECgcJDAAFAAAAAA==.',
Ex='Exactlee:BAAALgAFFAMJBAAAAA==.Exlee:BAAALgADCgkJHAAAAA==.Exurio:BAAALgAECgEJAQAAAA==.',
Ey='Eyls:BAAALgAECgMJBAAAAA==.',
Fa='Faithwarrior:BAAALgAECgYJCAAAAA==.Falopero:BAAALgADCgYJAQAAAA==.Falron:BAAALgAECgEJAQAAAA==.Fartlosh:BAAALgADCgMJAwAAAA==.Fathercheak:BAABLgAECn8UAAMHAAcJGQyMOgBRAQAHAAcJGQyMOgBRAQAbAAQJuQNgQgCgAAAAAA==.Fathlia:BAABLgAECn8cAAIcAAgJwhSQNwCkAQAcAAgJwhSQNwCkAQAAAA==.',
Fe='Felinlove:BAAALgAECgEJAQAAAA==.Felixito:BAAALgADCgcJEgAAAA==.Femroster:BAAALgADCgUJBQAAAA==.Femrostt:BAAALgADCgYJBgAAAA==.Fezzjin:BAAALgAECgYJEwAAAA==.',
Fi='Fidgetspin:BAAALgAECgYJDwAAAA==.Findlehurst:BAAALgADCggJBwAAAA==.Finleyy:BAAALgAECgYJDAAAAA==.Fireaveus:BAAALgAECgIJAgAAAA==.Firemender:BAAALgADCgcJBwAAAA==.',
Fl='Flashlights:BAAALgAECgUJCAAAAA==.Fleshbiter:BAAALgADCgUJDAAAAA==.Flites:BAAALgADCgMJAwAAAA==.Flowriduh:BAAALgAECgQJBwAAAA==.Fluffyfister:BAAALgAECgQJBAAAAA==.',
Fm='Fmjserval:BAAALgAECgEJAQAAAA==.',
Fo='Fookiebookie:BAAALgADCgEJAQAAAA==.Foot:BAAALgAECgYJDAAAAA==.Forcefaith:BAABLgAECn8bAAQSAAgJwx8LFADzAgASAAgJwx8LFADzAgABAAMJ0ASafwB6AAAVAAIJtxluNAB2AAAAAA==.Foxmulder:BAAALgAECgIJAgAAAA==.',
Fr='Freva:BAABLgAECn8cAAIdAAgJbg29CQBUAQAdAAgJbg29CQBUAQAAAA==.Friarfox:BAAALgADCggJCAABLgAECgcJEwAFAAAAAA==.Frodobaggins:BAAALgAECgUJBQAAAA==.Fronkyfronk:BAAALgAECgMJAwAAAA==.Fruitpuddle:BAAALgAECgcJDgAAAA==.',
Fu='Funkmemonk:BAAALgADCgEJAQAAAA==.Furabier:BAAALgAECgQJCAAAAA==.Furlock:BAAALgADCgYJCQAAAA==.Furryhugger:BAABLgAECn8UAAIPAAYJ+RrKKADOAQAPAAYJ+RrKKADOAQAAAA==.Furyos:BAAALgADCgIJAgAAAA==.',
Ga='Galepalm:BAAALgAECggJEgAAAA==.Gambriniss:BAAALgAECgQJCAAAAA==.Gamea:BAAALgAECgYJCQAAAA==.Gangshin:BAAALgADCgMJAwAAAA==.Gatepally:BAAALgADCgQJBAAAAA==.Gattler:BAAALgADCgcJCgAAAA==.Gazrosh:BAAALgAECgYJDgAAAA==.',
Gh='Gharvar:BAAALgADCgIJAgAAAA==.',
Gi='Gingipie:BAAALgADCgEJAQAAAA==.Gizzinuz:BAAALgADCgkJCQABLgAECgYJEwAFAAAAAA==.',
Gj='Gjimli:BAAALgADCggJDgAAAA==.',
Go='Goldenheals:BAAALgAECgMJBAAAAA==.Goosemon:BAAALgADCgcJDwAAAA==.Gordoc:BAAALgADCggJGAAAAA==.Gorehowlin:BAAALgAECgYJAQAAAA==.',
Gr='Graff:BAABLgAECn8aAAMCAAcJbhnSBAB6AQACAAYJcx7SBAB6AQAYAAcJjQHi5AC2AAAAAA==.Gravie:BAAALgADCgEJAQAAAA==.Graystaf:BAAALgAECgUJBQAAAA==.Grennan:BAAALgAECgQJBwAAAA==.Greymists:BAAALgAECgYJCgABLgAECgYJFAAbAPUPAA==.Greyp:BAAALgADCgUJBQAAAA==.Greysn:BAAALgAECggJBwAAAA==.Griffidan:BAAALgADCggJCAAAAA==.Grifflez:BAAALgAECgYJEgAAAA==.Grimfifteen:BAAALgADCgMJAwAAAA==.Grizwintrgrn:BAAALgAECgcJDQAAAA==.Grundleswath:BAAALgADCgcJDgAAAA==.',
Gu='Gufo:BAAALgAECgcJCAAAAA==.Guljinn:BAAALgADCgcJCQAAAA==.',
Ha='Hagann:BAAALgAECgYJCQABLgAECgcJFAANACIGAA==.Hakkazul:BAAALgAECgIJAgAAAA==.Halvanhelev:BAAALgADCgUJBQAAAA==.Hammeredd:BAAALgAECgYJDwAAAA==.Handofblood:BAABLgAECn8YAAISAAYJgwlfKAACAQASAAYJgwlfKAACAQAAAA==.Hardrockgirl:BAACLgAFFH8JAAIUAAQJVgewAABHAQAUAAQJVgewAABHAQAuAAQKfy0AAxQACAkiHBYIAGECABQACAkGGhYIAGECABMACAnNGGwTADkBAAAA.Harenima:BAAALgAECgUJBQAAAA==.Harmonechi:BAAALgAECgYJEQAAAA==.Havadatwo:BAAALgAECgUJDQAAAA==.',
He='Healinghammz:BAAALgAECgIJAgAAAA==.Healsgobrr:BAAALgAECgIJAgAAAA==.Healystix:BAAALgADCgcJCgABLgAECgUJDAAFAAAAAA==.Hellzcrusade:BAAALgAECgYJEgAAAA==.Herboos:BAAALgAECgQJBAAAAA==.Herbus:BAAALgADCgYJBgAAAA==.Hexcaster:BAAALgADCgcJDAAAAA==.Hexwing:BAAALgAECgMJBAABLgAECggJFwASAPQSAA==.',
Hi='Higowrath:BAAALgAECgEJAQAAAA==.',
Ho='Hodesh:BAAALgADCggJCgAAAA==.Holypuuss:BAABLgAECn8cAAISAAgJFCDAEwD1AgASAAgJFCDAEwD1AgAAAA==.Holystar:BAAALgAFFAEJAQAAAA==.Hopeslayer:BAAALgAECgEJAQABLgAECggJGwAMAKYhAA==.Hoplitedh:BAAALgADCgEJAQAAAA==.Hoplitesaint:BAAALgAECgcJEAAAAA==.Hoplitescout:BAAALgADCgMJBgAAAA==.',
Hp='Hps:BAABLgAECn8VAAIeAAgJLh1/BABEAgAeAAgJLh1/BABEAgAAAA==.',
Hr='Hrakos:BAAALgAECgYJBgAAAA==.',
Ht='Htiál:BAAALgAECgYJBwAAAA==.Htïål:BAAALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Hu='Hutõ:BAAALgAECgUJDQAAAA==.',
Hy='Hyndra:BAAALgAECgQJCAAAAA==.Hyrakka:BAAALgADCgYJCQABLgAECgYJCAAFAAAAAA==.Hyunkel:BAAALgADCgMJAwAAAA==.Hyunkvoker:BAAALgAECgQJBwAAAA==.Hyx:BAAALgADCgYJBgAAAA==.',
Ic='Icemommy:BAABLgAECn8WAAIDAAcJGxcWdwDkAQADAAcJGxcWdwDkAQAAAA==.Icystyx:BAAALgAECgQJBAAAAA==.',
Id='Ideot:BAAALgADCgQJBAAAAA==.',
Ig='Igottinylegs:BAAALgADCgQJBQAAAA==.',
Il='Ilvann:BAAALgADCggJDgAAAA==.Ilyamurometz:BAAALgAFFAEJAQAAAA==.',
Im='Immorta:BAABLgAECn8jAAIfAAgJPxk/BQDdAQAfAAgJPxk/BQDdAQAAAA==.Imyourdaddy:BAAALgAECgIJAwAAAA==.',
Ir='Iriclaw:BAAALgAFFAQJBAAAAA==.Ironwood:BAAALgAECgcJCgAAAA==.',
Is='Ismellblood:BAAALgADCgUJCAAAAA==.',
Ja='Jackeyguan:BAACLgAFFH8GAAIVAAMJCQriAwChAAAVAAMJCQriAwChAAAuAAQKfywAAxUACAnPE9kNAOgBABUACAnPE9kNAOgBABIABgluCaGpAC4BAAAA.Jackiepàn:BAAALgADCgUJBQAAAA==.Jadedapple:BAABLgAECn8UAAIDAAYJbxusjgC1AQADAAYJbxusjgC1AQAAAA==.Jadefires:BAAALgAECgUJCQAAAA==.Jadejutsu:BAAALgADCgkJEwABLgAECgUJCQAFAAAAAA==.Jandda:BAABLgAECn8ZAAIeAAgJVCTzAwBSAwAeAAgJVCTzAwBSAwAAAA==.',
Jh='Jheniffer:BAAALgADCgEJAQAAAA==.Jherri:BAAALgAECgMJAwAAAA==.',
Jk='Jkm:BAAALgAECgUJDAAAAA==.',
Jo='Joanexotic:BAAALgAECgMJAwAAAA==.Joltx:BAAALgADCgYJBgAAAA==.',
Jr='Jrocmfka:BAAALgAECgEJAQAAAA==.',
Ju='Judgemortis:BAAALgADCgUJBQAAAA==.Julihanna:BAAALgADCgIJAgAAAA==.Juntor:BAAALgADCggJEAAAAA==.Justa:BAAALgADCgcJDAAAAA==.Justinmatto:BAAALgADCgUJBQAAAA==.',
Ka='Kaawaki:BAAALgADCgYJCAABLgAECggJKAAfADwbAA==.Kaeliin:BAAALgADCggJCAABLgADCggJDQAFAAAAAA==.Kage:BAAALgAECgIJAgAAAA==.Kaiaicewing:BAAALgADCgMJAwAAAA==.Kaishowspeed:BAAALgADCgYJBgAAAA==.Kal:BAAALgAECgIJAgAAAA==.Kalorondir:BAAALgADCgUJBgAAAA==.Kandvoker:BAAALgAECgEJAgAAAA==.Karatekyns:BAAALgAECgEJAQABLgAECgYJEQAFAAAAAA==.Katatonia:BAAALgAECgIJAgAAAA==.Katherwind:BAAALgADCgEJAQAAAA==.Kattara:BAABLgAECn8WAAITAAcJURpGAwB4AQATAAcJURpGAwB4AQAAAA==.Kattarwal:BAAALgAECgYJEAAAAA==.Kawakki:BAABLgAECn8oAAIfAAgJPBtxGgB4AgAfAAgJPBtxGgB4AgAAAA==.Kayjay:BAAALgADCgMJAwAAAA==.Kayoti:BAAALgADCgkJCQAAAA==.',
Ke='Keely:BAAALgADCgEJAQAAAA==.Kennily:BAAALgADCgUJBQAAAA==.Kenté:BAAALgAECgYJCAAAAA==.Keyndian:BAAALgAECgQJBwAAAA==.',
Kh='Khaiza:BAAALgADCgQJBAAAAA==.Khaotikdraco:BAACLgAFFH8PAAIKAAUJ/BrwAgBoAQAKAAUJ/BrwAgBoAQAuAAQKfyMAAwoACQmmH4EEAEgDAAoACQmmH4EEAEgDAAgABQl0DhgkAAYBAAAA.Khaototem:BAABLgAECn8WAAIPAAgJlhQYIQAGAgAPAAgJlhQYIQAGAgABLgAFFAUJDwAKAPwaAA==.Khazgul:BAAALgAECgEJAQAAAA==.Khrosrin:BAAALgADCgQJBAAAAA==.',
Ki='Kiljaiden:BAAALgAECgYJDQAAAA==.Killalily:BAAALgAECgUJCgAAAA==.Kimagure:BAABLgAECn8XAAMKAAcJXhE2KQB0AQAKAAcJeQ82KQB0AQAIAAUJkBPOJAD/AAAAAA==.Kimjonggoon:BAAALgAECgQJDAAAAA==.Kissbuttchin:BAAALgAECgQJBgAAAA==.Kiyoshie:BAABLgAECn8fAAIRAAgJ4xbLHwBHAgARAAgJ4xbLHwBHAgAAAA==.',
Km='Kmaruko:BAAALgAECgIJAgAAAA==.',
Ko='Koblelock:BAAALgAECgYJEQAAAA==.Kodiakjak:BAAALgADCgIJAwAAAA==.Kodiakpax:BAAALgADCggJCAAAAA==.Kodiakwak:BAAALgADCgcJBwAAAA==.Kodiakzug:BAAALgADCgEJAQAAAA==.Koftimu:BAAALgAECgYJDQAAAA==.Kolax:BAAALgAECgMJBgAAAA==.Kontroll:BAEALgAECgYJAwABLgAECgcJCQAFAAAAAA==.Kookee:BAABLgAECn8aAAIXAAgJQBaABwD6AQAXAAgJQBaABwD6AQAAAA==.',
Kr='Kraazh:BAABLgAECn8UAAIMAAgJ8h4cDQCpAgAMAAgJ8h4cDQCpAgAAAA==.Krieghelm:BAAALgAECgQJBAAAAA==.Krizzlix:BAAALgAECggJCQAAAA==.Krypticgrip:BAAALgADCgEJAQAAAA==.',
Ku='Kunglou:BAAALgAECgcJDQAAAA==.Kurayamiryu:BAAALgAECgQJBAAAAA==.Kuyntaitain:BAAALgAECgMJBQAAAA==.',
Ky='Kyle:BAAALgADCgcJDAAAAA==.',
La='Lanfeár:BAAALgADCgYJBgAAAA==.Larissa:BAAALgAECgcJEwAAAA==.Laserdisc:BAAALgAECgEJAQAAAA==.Lathillea:BAAALgAECgYJCgAAAA==.Lavendertown:BAAALgAECgQJBgAAAA==.Lazzirus:BAABLgAECn8cAAMPAAgJXhjPGABOAgAPAAgJXhjPGABOAgAcAAIJ1AlwjABjAAAAAA==.',
Le='Leelominai:BAAALgADCgMJAwAAAA==.Legendairÿ:BAAALgADCgcJBwAAAA==.Legogatz:BAAALgADCgYJBgAAAA==.Lessii:BAECLgAFFH8JAAIYAAQJZBmRBABsAQAYAAQJZBmRBABsAQAuAAQKfyMAAhgACAmfIYgbANgCABgACAmfIYgbANgCAAAA.',
Li='Lidarcis:BAABLgAECn8gAAMYAAgJFR++AwBfAgAYAAgJFR++AwBfAgACAAYJChliGwBzAQAAAA==.Life:BAAALgADCggJBgAAAA==.Lifebinder:BAAALgADCgkJCQAAAA==.Liftz:BAAALgAECgMJBgAAAA==.Lilbingbong:BAAALgAECgEJAQAAAA==.Lilithstyx:BAAALgAECgIJBAAAAA==.Lilykilikili:BAAALgAECgIJAwABLgAECggJDQAFAAAAAA==.Linkin:BAAALgADCgUJAwAAAA==.Lissandra:BAAALgADCgYJBgAAAA==.Litcore:BAAALgADCgYJCgABLgAECgcJFAABAB0bAA==.',
Lo='Lobó:BAAALgADCgQJBQAAAA==.Lockybuns:BAAALgADCgQJBAAAAA==.Lokdis:BAAALgADCgIJAQAAAA==.Loosekitty:BAAALgADCgYJCQAAAA==.Lorily:BAAALgADCgcJBwABLgAECgYJEwAFAAAAAA==.Lorthñemar:BAAALgAECgQJBwAAAA==.Lostdogg:BAAALgAECgYJBwABLgAECgYJBwAFAAAAAA==.Lostpreist:BAAALgAECgYJBwAAAA==.',
Lu='Luckybet:BAAALgAECgYJEgAAAA==.Lukashenko:BAAALgADCgYJBAAAAA==.Lunamorr:BAAALgADCgkJDAAAAA==.Luxian:BAAALgAECgQJBQAAAA==.',
Ly='Lyger:BAAALgADCgYJBwABLgADCgcJDgAFAAAAAA==.Lymka:BAAALgAECgIJAgAAAA==.',
Ma='Mackori:BAAALgAECgUJBQAAAA==.Madamepali:BAAALgADCgYJBgAAAA==.Madduxx:BAAALgAECgQJDAAAAA==.Maeg:BAAALgADCgYJBgAAAA==.Maesera:BAAALgADCgUJCgAAAA==.Magenos:BAABLgAECn8YAAIDAAgJDQgTHQBlAQADAAgJDQgTHQBlAQAAAA==.Magic:BAAALgAECgIJAgAAAA==.Magickwarior:BAAALgAECgMJAwAAAA==.Magicnieech:BAAALgADCgQJBAAAAA==.Magicpants:BAAALgAECgUJCQAAAA==.Magobiga:BAAALgAECgQJCQAAAA==.Maguito:BAAALgADCgUJBgAAAA==.Mahohyuga:BAAALgADCgYJDAAAAA==.Mahrx:BAACLgAFFH8PAAIMAAUJdBzNAABxAQAMAAUJdBzNAABxAQAuAAQKfyUAAgwACAm+JFYEAEYDAAwACAm+JFYEAEYDAAAA.Majinvegeta:BAAALgAECgQJBAAAAA==.Manrrome:BAAALgADCgEJAgAAAA==.Masamoon:BAABLgAECn8dAAIQAAgJBRjsEwAsAgAQAAgJBRjsEwAsAgAAAA==.Masonshyphy:BAAALgAECgcJDwAAAA==.Mather:BAAALgADCgYJBgAAAA==.Maxmiup:BAAALgADCgUJBgAAAA==.Maxomi:BAAALgADCgMJAwAAAA==.',
Mc='Mcswissleguy:BAAALgADCgUJBgAAAA==.',
Me='Medarela:BAAALgADCgcJFAAAAA==.Meeke:BAACLgAFFH8IAAIdAAMJ5B9NCQAoAQAdAAMJ5B9NCQAoAQAuAAQKfyUAAh0ACAnjIWoGACUDAB0ACAnjIWoGACUDAAAA.Meekrob:BAAALgAECgIJAgAAAA==.Melmin:BAAALgAECgQJBwAAAA==.Mercyful:BAAALgAECgkJBgAAAA==.Meroman:BAAALgAECgIJAgAAAA==.Merrllyn:BAAALgAECgMJBAAAAA==.Merynn:BAAALgADCgYJBgAAAA==.Metamora:BAABLgAECn8UAAIgAAYJQgf5EQDYAAAgAAYJQgf5EQDYAAAAAA==.Meuria:BAAALgAECgYJDwAAAA==.',
Mi='Milliarde:BAAALgADCgUJCAAAAA==.Ministry:BAAALgAECgEJAgAAAA==.Misstearly:BAAALgAECgYJBwAAAA==.Missyann:BAAALgADCgYJCgAAAA==.Mistamec:BAAALgAECgUJCQAAAA==.',
Mo='Mohjoejoejoe:BAAALgADCgkJCQAAAA==.Moida:BAAALgADCgUJBQABLgAECggJIAAYABUfAA==.Moltonmonk:BAAALgAECgYJEAAAAA==.Momô:BAAALgAECgEJAQAAAA==.Moneebagz:BAABLgAECn8VAAIOAAYJtA/5CABSAQAOAAYJtA/5CABSAQAAAA==.Monkbezz:BAAALgADCgUJBAAAAA==.Monktune:BAAALgAECgIJAgAAAA==.Montblanc:BAAALgADCgYJBgAAAA==.Mooingtun:BAAALgAECggJEwAAAA==.Moonem:BAABLgAECn8YAAMgAAgJKB7wGABAAgAgAAgJKB7wGABAAgAeAAMJ+hdfHADTAAAAAA==.Mossburg:BAABLgAECn8VAAIhAAgJuBxVCgAzAgAhAAgJuBxVCgAzAgAAAA==.',
Mu='Mulgogi:BAAALgAECgEJAQAAAA==.Munziees:BAAALgADCgcJBwAAAA==.Mustachio:BAAALgADCgcJCAAAAA==.',
My='Mysticwarior:BAAALgAECgIJAgAAAA==.',
['Mé']='Méta:BAAALgADCggJGQABLgAECgYJFAAgAEIHAA==.',
Na='Nachopapa:BAAALgADCgkJGgAAAA==.Nagare:BAAALgADCgIJAgAAAA==.Nani:BAAALgADCgEJAQAAAA==.Naniwa:BAABLgAECn8XAAIcAAgJ3xT9IwAHAgAcAAgJ3xT9IwAHAgAAAA==.Nasturtium:BAAALgADCgQJBAABLgAFFAMJBwAIAG8RAA==.Natsuko:BAAALgAECgIJAgAAAA==.Natura:BAAALgAECgEJAQAAAA==.Nazacis:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Nazarickhh:BAAALgADCgYJBgABLgAECgQJBAAFAAAAAA==.Nazarickm:BAAALgADCgkJFAABLgAECgQJBAAFAAAAAA==.',
Ne='Necrodik:BAAALgADCgEJAQAAAA==.Necroo:BAAALgAECgEJAQAAAA==.Nelenloth:BAAALgAECgEJAQAAAA==.Neoptolemus:BAAALgAECgIJAgAAAA==.Nerclopse:BAAALgAECgYJEAAAAA==.Neverender:BAAALgAECgUJDAAAAA==.',
Ni='Nightveil:BAAALgADCgQJBwAAAA==.Nikephorous:BAAALgAECgMJBAAAAA==.Niomee:BAAALgADCgcJBwAAAA==.Nitesbane:BAAALgADCgQJBAABLgAECgYJDQAFAAAAAA==.Nitroxs:BAAALgADCgcJCAAAAA==.',
No='Nokachí:BAAALgADCggJDAAAAA==.Nola:BAAALgAECgEJAgAAAA==.Noritotem:BAABLgAECn8YAAIiAAcJhSB5BQCuAgAiAAcJhSB5BQCuAgAAAA==.Notics:BAABLgAECn8UAAQbAAYJ9Q8sLgAtAQAbAAUJVxEsLgAtAQAdAAQJGxOOQADzAAAHAAIJUAttHgA0AAAAAA==.Notpog:BAAALgAECgcJDAAAAA==.Novacainê:BAAALgADCgYJBgAAAA==.Noworry:BAABLgAECn8fAAIDAAgJfhnFQgBwAgADAAgJfhnFQgBwAgAAAA==.',
Nu='Numb:BAACLgAFFH8FAAIQAAIJZw8NEQCTAAAQAAIJZw8NEQCTAAAuAAQKfyIAAxAACAnSG3gRAEgCABAACAnSG3gRAEgCAAwAAQn4A2SHACgAAAAA.Numuhotep:BAAALgADCgUJBQAAAA==.Nutnbolt:BAAALgADCgYJBgABLgAECggJHgAXAKwcAA==.Nuzoc:BAAALgADCgUJBQAAAA==.',
Ny='Nylistraz:BAAALgADCgkJEwAAAA==.',
['Ní']='Níghtwolf:BAAALgADCgkJCwAAAA==.',
Oa='Oakfel:BAAALgADCgEJAQAAAA==.Oakwar:BAAALgADCgMJAwAAAA==.',
Oc='Occulore:BAAALgADCgIJAgAAAA==.',
Od='Odr:BAAALgADCgEJAQAAAA==.',
Oh='Ohdinn:BAAALgAECgIJAgABLgAECgcJFAANACIGAA==.',
Ol='Olbonivia:BAAALgAECgEJAQAAAA==.Oldgreg:BAAALgADCgYJCQAAAA==.Oleander:BAAALgADCgcJBwAAAA==.Oliveros:BAAALgADCgEJAQAAAA==.Oliviadrago:BAAALgAECgQJBgAAAA==.',
On='Onebutton:BAABLgAECn8XAAMZAAcJySPHGQBZAgAZAAYJmSPHGQBZAgAhAAEJtSSvDwBuAAAAAA==.Oniraine:BAAALgAECgQJCgAAAA==.Onlymilfs:BAAALgADCgMJAwAAAA==.',
Op='Opalescence:BAAALgAECgYJCQAAAA==.Optional:BAABLgAECn8gAAIhAAgJQyH4AgADAwAhAAgJQyH4AgADAwAAAA==.',
Or='Orgargo:BAAALgAECgYJEgAAAA==.Ornormas:BAAALgADCgYJBgAAAA==.',
Os='Oshagosa:BAAALgADCgcJBwABLgAECgYJDQAFAAAAAA==.',
Ot='Othar:BAAALgADCgUJBQAAAA==.Otyphoon:BAAALgAECgUJBQAAAA==.',
Ow='Owtter:BAAALgADCgUJBQAAAA==.',
Pa='Pallorx:BAAALgAECgQJBAAAAA==.Pandasennin:BAAALgAECgIJAgAAAA==.Pankis:BAAALgADCgQJBAAAAA==.Papahammer:BAAALgAECgIJAgABLgADCgIJAgAFAAAAAA==.Papashootin:BAAALgADCgIJAgAAAA==.Paperplate:BAABLgAECn8iAAIeAAgJrR8jDADeAgAeAAgJrR8jDADeAgAAAA==.Paradox:BAABLgAECn8cAAIUAAcJPCKdBQCvAgAUAAcJPCKdBQCvAgAAAA==.Patrien:BAAALgAECgEJAQAAAA==.Pattyhealsu:BAAALgAECggJDQAAAA==.',
Pe='Peachizz:BAAALgAECgUJBwAAAA==.Peligrynn:BAAALgAECgEJAQABLgAFFAEJAgAFAAAAAA==.Pelitina:BAAALgAECgYJCwABLgAFFAEJAgAFAAAAAA==.Pelivarondo:BAAALgAECgIJBAABLgAFFAEJAgAFAAAAAA==.Peliweiza:BAAALgAFFAEJAgAAAA==.Pelizandeth:BAAALgAECgYJEQABLgAFFAEJAgAFAAAAAA==.Pestillia:BAAALgAECgMJAwAAAA==.',
Ph='Phoffïn:BAAALgAECgQJBQAAAA==.',
Pi='Pistolbeat:BAAALgADCgYJBQAAAA==.Pitterpatter:BAAALgADCgYJCwAAAA==.',
Pl='Plapadin:BAAALgADCgUJBQAAAA==.',
Po='Poeup:BAAALgADCgYJCAAAAA==.',
Pr='Prayformojo:BAAALgAECgIJAgAAAA==.Pridehorn:BAAALgADCgQJBwAAAA==.Prizmatic:BAAALgADCgkJEwAAAA==.',
Ps='Psyko:BAAALgADCgkJCwABLgAECgYJBgAFAAAAAA==.',
Pu='Puiness:BAAALgADCgUJBgAAAA==.',
Py='Pyraskia:BAAALgADCgYJCQABLgAECgUJCQAFAAAAAA==.',
Qu='Quickbrown:BAAALgAECgUJDAAAAA==.',
Ra='Rabiddog:BAAALgAECgMJBAAAAA==.Raced:BAAALgADCgkJDQAAAA==.Raebspace:BAAALgAECgIJAgAAAA==.Ragenarok:BAAALgAECgUJCgAAAA==.Rahxe:BAAALgAECgEJAQAAAA==.Raifyre:BAAALgADCgkJEQAAAA==.Raiyne:BAAALgAECgUJBwAAAA==.Rak:BAAALgADCgUJBQAAAA==.Rakaa:BAAALgADCgEJAQAAAA==.Ramello:BAAALgAECgQJCQAAAA==.Randinator:BAAALgADCgEJAQAAAA==.Randomin:BAAALgAECgYJBgAAAA==.Rayyford:BAAALgADCgIJAgAAAA==.',
Re='Redneckrouge:BAAALgADCgYJBgAAAA==.Reielis:BAAALgADCgEJAQAAAA==.Relexi:BAAALgADCgYJBgAAAA==.Renloth:BAAALgADCggJCQAAAA==.Reno:BAAALgAECgUJEwAAAA==.Renthyr:BAABLgAECn8XAAMKAAgJZxYwHwDJAQAKAAcJphMwHwDJAQAJAAcJihOIGgC2AQAAAA==.Rentiana:BAAALgADCggJDgAAAA==.Reportcard:BAAALgAECgYJCgABLgAECgYJCwAFAAAAAA==.Reuhots:BAAALgADCgUJBQABLgAECgUJCwAFAAAAAA==.Reurog:BAAALgAECgUJCwAAAA==.',
Rh='Rhakudu:BAAALgAECgcJEwAAAA==.Rhipp:BAAALgAECgMJBgAAAA==.',
Ri='Rian:BAACLgAFFH8KAAIZAAQJGx35CgBoAQAZAAQJGx35CgBoAQAuAAQKfxsAAhkACAlSI5MKAPkCABkACAlSI5MKAPkCAAEuAAUUBgkNAAMA9BwA.Riikku:BAAALgADCgEJAQAAAA==.Ringram:BAAALgADCgEJAQAAAA==.Riploc:BAAALgAECgMJAwAAAA==.',
Ro='Roadiee:BAAALgAECgMJAwAAAA==.Roadkyll:BAAALgAECgQJCAAAAA==.Rolisea:BAAALgAECgYJEwAAAA==.Rosamoon:BAAALgADCgkJIAAAAA==.Rosettia:BAAALgAECgYJEAAAAA==.',
Ru='Rueofdarkest:BAAALgADCgYJBgAAAA==.Rum:BAAALgAECgEJAQABLgAFFAMJDgAjANofAA==.Rune:BAAALgAECgcJCAABLgAFFAYJDQADAPQcAA==.',
Ry='Rykaughn:BAAALgADCgkJGQAAAA==.',
['Râ']='Rânge:BAAALgAECgcJAQAAAA==.',
Sa='Sadfingchud:BAAALgADCgMJBAAAAA==.Sadlerz:BAAALgAECgQJAgAAAA==.Salara:BAAALgAECgcJEQAAAA==.Salasong:BAAALgADCgcJBwAAAA==.Saldri:BAAALgADCgYJCwAAAA==.Samb:BAAALgADCgMJAwAAAA==.Sambwave:BAAALgAECgQJBAAAAA==.Sample:BAAALgADCgMJAwABLgAECgYJEwAFAAAAAA==.Sandrinea:BAAALgAECgYJEAAAAA==.Sanguinore:BAAALgADCgMJAwAAAA==.Santá:BAAALgAECgUJCAAAAA==.Sarahmar:BAAALgADCgkJEgAAAA==.Saratogany:BAAALgADCgcJDAAAAA==.Sardenaris:BAABLgAECn8iAAIRAAgJ4x6VEQCsAgARAAgJ4x6VEQCsAgAAAA==.Saripal:BAAALgADCgkJEwAAAA==.Sasquatchpal:BAAALgAECgQJCQAAAA==.',
Se='Sebanis:BAAALgADCggJCAAAAA==.Sedale:BAAALgADCgkJCQAAAA==.Seilene:BAAALgAECgQJBAABLgAECgYJDgAFAAAAAA==.Sekaii:BAAALgADCgEJAQAAAA==.Senis:BAAALgAECgIJAgAAAA==.Seo:BAAALgAECgYJEAAAAA==.Seshomaruu:BAAALgADCgYJDQAAAA==.Sethanndis:BAAALgAECgYJDAAAAA==.Severan:BAAALgADCgYJDAAAAA==.',
Sh='Shadowhart:BAABLgAECn8gAAIXAAgJrBm9BQAaAgAXAAgJrBm9BQAaAgAAAA==.Shadowreap:BAAALgADCgIJAgAAAA==.Shaforgold:BAAALgAECgYJEwAAAA==.Shaidie:BAAALgAECgUJBwAAAA==.Shaiyuri:BAAALgADCgIJAgAAAA==.Shakuma:BAAALgAECgMJAwAAAA==.Shamblam:BAAALgAECgUJBQAAAA==.Sharmin:BAAALgADCgQJBgAAAA==.Shawtyschit:BAAALgAFFAEJAQABLgAECgYJCwAFAAAAAA==.Shennidan:BAAALgAECgQJBAABLgAECgcJHAAgAHMeAA==.Shibal:BAABLgAECn8aAAIBAAgJmx0wEQCJAgABAAgJmx0wEQCJAgAAAA==.Shrekismydad:BAAALgADCgYJDgAAAA==.Shroompie:BAAALgADCgYJBgABLgADCgkJFgAFAAAAAA==.Shroomsy:BAAALgADCgkJFgAAAA==.Shushumen:BAABLgAECn8dAAIYAAgJyhgKCAD/AQAYAAgJyhgKCAD/AQAAAA==.Shäken:BAAALgAECgYJDAAAAA==.Shîmmy:BAAALgADCgMJAQAAAA==.',
Si='Sicknezz:BAAALgAECgQJBwABLgAECgYJBwAFAAAAAA==.Sickntwizted:BAAALgAECgYJBwAAAA==.Sickside:BAAALgADCgEJAQAAAA==.Sifzerg:BAAALgAECgMJBAAAAA==.Silvercore:BAABLgAECn8UAAMBAAcJHRs5HQAsAgABAAcJHRs5HQAsAgASAAQJUB+2tQAZAQAAAA==.Silverstarz:BAAALgAECgYJDQABLgAFFAUJDQAgAEYZAA==.Simpmyimp:BAAALgADCgcJBwABLgAECggJHAADAJ0XAA==.Sindari:BAABLgAECn8WAAIkAAgJewN7MQB8AQAkAAgJewN7MQB8AQAAAA==.Sinturio:BAAALgAECgYJCwAAAA==.Sipsy:BAAALgAECgUJDAAAAA==.Sisurae:BAAALgADCgcJEQAAAA==.',
Sk='Skarg:BAAALgADCgYJCQAAAA==.Skinnylock:BAAALgAECgQJBQAAAA==.Skycynder:BAAALgADCgkJBQAAAA==.Skyeashe:BAAALgAECgYJBgAAAA==.Skyerend:BAAALgADCgIJAwAAAA==.Skyeshadow:BAAALgADCgEJAQAAAA==.',
Sl='Slayersmma:BAAALgADCggJDgAAAA==.Slip:BAAALgADCgcJCQAAAA==.Slipknight:BAAALgADCgYJBgAAAA==.Sloppydemon:BAAALgAECgYJDwAAAA==.Slowmo:BAAALgADCgEJAQAAAA==.Slyrak:BAAALgADCggJDgAAAA==.',
Sm='Smittles:BAABLgAECn8UAAMYAAYJ6BE7JAAIAQAYAAYJ6BE7JAAIAQAOAAMJbQdAEwBeAAAAAA==.Smolschmeaty:BAAALgADCgEJAQAAAA==.Smple:BAAALgAECgYJEwAAAA==.',
Sn='Snartfiffer:BAAALgAECgEJAQAAAA==.Snippbear:BAAALgAECgYJBQAAAA==.Snëk:BAAALgAECgQJEAAAAA==.',
So='Sokhin:BAAALgAECgYJCgABLgAECgcJHAAgAHMeAA==.Soline:BAAALgADCgkJIgAAAA==.Somadru:BAAALgAECgYJDQAAAA==.Somapal:BAAALgAECgUJBQAAAA==.Somasham:BAAALgAECgEJAQAAAA==.Sonshine:BAAALgADCggJDgAAAA==.Sophus:BAAALgAECgMJBAAAAA==.Soren:BAABLgAECn8cAAIgAAcJcx7JAgAZAgAgAAcJcx7JAgAZAgAAAA==.Sorete:BAAALgADCgMJAwABLgAECgcJHAAgAHMeAA==.Sortia:BAAALgADCgUJCAAAAA==.',
Sp='Spagooter:BAABLgAECn8eAAMXAAgJrBypKQBqAgAXAAcJrBypKQBqAgAWAAEJAAAKJgBZAAAAAA==.Sparklepants:BAABLgAECn8bAAIDAAgJIyGlHgD6AgADAAgJIyGlHgD6AgAAAA==.Spicyadams:BAAALgADCgQJAgAAAA==.Spinachdip:BAAALgAECgQJBAAAAA==.Spunnilingus:BAAALgAECgYJDwAAAA==.Spyfamily:BAAALgADCgcJBwAAAA==.',
Sq='Squidsten:BAAALgAECgYJEQAAAA==.Squidstens:BAAALgADCgYJBgAAAA==.',
Sr='Sren:BAAALgAECgQJBAABLgAECgcJHAAgAHMeAA==.',
St='Stabzya:BAAALgADCgQJBAAAAA==.Starslayer:BAABLgAECn8bAAMTAAgJRxiRCAAiAgATAAgJRxiRCAAiAgAUAAIJfxD+KgBuAAAAAA==.Stevemo:BAAALgAECgQJBgAAAA==.Stillness:BAAALgADCgYJBgAAAA==.Stonemason:BAAALgAECgUJCAAAAA==.Stopover:BAAALgADCgYJBgAAAA==.Strechy:BAAALgADCgEJAQAAAA==.Stril:BAAALgADCgUJCAAAAA==.Strongcarote:BAAALgAECgUJCgAAAA==.Stórr:BAAALgADCgMJAwAAAA==.',
Su='Subakiie:BAAALgAECgYJCQAAAA==.Submisive:BAAALgAECgQJCAAAAA==.Suitcase:BAAALgADCgMJAwAAAA==.Sumting:BAAALgADCgcJBwAAAA==.Supaxhot:BAAALgAECggJDgAAAA==.',
Sv='Svish:BAAALgAECgYJBgAAAA==.',
Sw='Swaellen:BAAALgADCgMJAwAAAA==.Swagruid:BAAALgAECgYJEQAAAA==.Swampdonkey:BAAALgADCggJFQABLgAECgYJHgADAEwjAA==.Swampslinger:BAABLgAECn8eAAIDAAYJTCOwDwDGAQADAAYJTCOwDwDGAQAAAA==.Swordlady:BAAALgAECgEJAQABLgAECggJJQAHAIMdAA==.',
Sy='Sylpha:BAAALgAECgcJEQAAAA==.Symorenner:BAAALgADCgUJBQABLgAECgYJDQAFAAAAAA==.Syndragos:BAAALgAECgYJCQAAAA==.Synoria:BAAALgADCgkJEQAAAA==.Synroshi:BAAALgAECgEJAQAAAA==.Syntala:BAAALgAECgQJCgAAAA==.',
['Sä']='Sänll:BAAALgADCgcJBAAAAA==.',
Ta='Talenalat:BAAALgAECgYJCQAAAA==.Talfa:BAAALgADCgEJAQAAAA==.Tankaa:BAAALgADCgUJCwAAAA==.Tarnuz:BAAALgADCgEJAQAAAA==.Tatsuni:BAAALgAECgcJCQAAAA==.Taymatt:BAAALgAECgUJDAAAAA==.Tazina:BAAALgADCgEJAQAAAA==.Tazstinko:BAABLgAECn8xAAIfAAkJoyPqAQCoAwAfAAkJoyPqAQCoAwAAAA==.',
Te='Teepot:BAAALgADCgEJAgAAAA==.Tejasgeek:BAAALgAECgUJBQAAAA==.Templordan:BAAALgAECgUJBQAAAA==.Tenntoes:BAABLgAECn8cAAMXAAgJgB//BAAsAgAEAAcJ4x2yBwBLAgAXAAcJhxr/BAAsAgAAAA==.Termuda:BAAALgAECgkJBwAAAA==.',
Th='Thalanil:BAAALgAECgQJCgAAAA==.Thalema:BAAALgAECgcJEgAAAA==.Tharaven:BAAALgAECgYJBgAAAA==.Thegoob:BAAALgAECgEJAgAAAA==.Themuffinman:BAAALgAECgQJBQAAAA==.Thenazera:BAAALgAECgUJBwAAAA==.Theworrirawr:BAAALgAFFAEJAQAAAA==.Thiccfilaa:BAAALgAECggJEQAAAA==.Thornan:BAAALgADCgQJBAAAAA==.Threeskin:BAAALgAECgQJBAAAAA==.Thunderess:BAAALgADCgYJBgAAAA==.Thur:BAAALgAECgYJEwAAAA==.Thymera:BAAALgADCgYJBwAAAA==.',
Ti='Tiandor:BAAALgADCgMJBAAAAA==.Tinyclash:BAAALgAECgUJBQAAAA==.Tinyfel:BAAALgAECgYJEAAAAA==.Tizef:BAAALgADCgYJDwAAAA==.',
To='Toddhoward:BAAALgAECgEJAQAAAA==.Toestalker:BAAALgAECgYJDwAAAA==.Tokaiteio:BAAALgADCgUJBwAAAA==.Tokilock:BAAALgADCgQJBAAAAA==.Toldyousoul:BAAALgAECgMJCQAAAA==.Tonytots:BAAALgADCgcJDQAAAA==.Toon:BAAALgAECgQJCwAAAA==.Tormentaa:BAAALgAECgIJAgAAAA==.Torruid:BAAALgAECgEJAQAAAA==.Torsha:BAAALgADCgUJBQAAAA==.Toscha:BAAALgADCgEJAQAAAA==.Toxikil:BAABLgAECn8hAAMaAAcJtBWHAgBzAQAkAAcJnRE1LgCQAQAaAAcJYBSHAgBzAQAAAA==.',
Tr='Traelirra:BAAALgADCgYJCAAAAA==.Treebeard:BAAALgADCgIJAgAAAA==.Treebirth:BAACLgAFFH8HAAIeAAMJ4wyMCQDIAAAeAAMJ4wyMCQDIAAAuAAQKfyAAAh4ACAnvGR0lACUCAB4ACAnvGR0lACUCAAAA.Treestezza:BAAALgADCggJDQAAAA==.Troyano:BAAALgAECgEJAQAAAA==.Trunder:BAAALgAECgYJEwAAAA==.',
Tw='Tweaks:BAAALgAECgkJDQAAAA==.Twinkies:BAAALgADCgcJBwAAAA==.',
Tz='Tzugo:BAAALgADCgMJAwAAAA==.',
['Tâ']='Tâmaÿa:BAAALgADCgYJBgAAAA==.',
['Té']='Téderiata:BAAALgAECgQJCwAAAA==.',
Ud='Udekar:BAAALgADCgMJBQAAAA==.Uders:BAAALgAECgYJDQAAAA==.',
Ul='Ultradrac:BAAALgAECgQJBwABLgAECgYJCAAFAAAAAA==.Ultramad:BAAALgADCgMJAwABLgAECggJHgANAIAhAA==.Ultramellow:BAAALgADCgUJBwABLgAECggJHgANAIAhAA==.Ulubai:BAAALgAECgEJAQAAAA==.',
Um='Umaulk:BAAALgAECgEJAQAAAA==.',
Un='Unclebunzo:BAAALgAECgMJAwAAAA==.Unclejames:BAAALgADCgcJBwAAAA==.Unmarked:BAAALgAECggJEwAAAA==.',
Up='Upngo:BAABLgAECn80AAMlAAgJ7R4cCAA2AgAfAAgJ8BhKFgCbAgAlAAgJShocCAA2AgAAAA==.',
Ur='Urotherdaddy:BAAALgADCgcJDAABLgAECgYJEQAFAAAAAA==.',
Va='Vaelys:BAAALgADCgEJAQAAAA==.Vaerel:BAAALgADCgYJBgAAAA==.Valandine:BAAALgADCgYJCAAAAA==.Vandarras:BAAALgAECgEJAQAAAA==.Vandredor:BAACLgAFFH8QAAMLAAUJMg46DQBnAQALAAUJMg46DQBnAQAmAAEJYwBhBgAvAAAuAAQKfxUAAwsABgkQH5FfAIIBAAsABgkQH5FfAIIBACYABgnmEfcWAO0AAAAA.Varate:BAAALgAECgQJCAAAAA==.Vasträ:BAAALgAECgIJAgAAAA==.Vatal:BAABLgAECn8XAAMlAAcJtRzXDQDAAQAlAAYJshrXDQDAAQAfAAQJrhV3FAD7AAAAAA==.',
Ve='Veladorastia:BAAALgADCgUJBQAAAA==.Velasha:BAAALgADCgMJAwAAAA==.Velcryn:BAAALgADCgQJBAAAAA==.Velicelia:BAAALgAECgQJCQAAAA==.Vellindrys:BAAALgAECgUJCAAAAA==.Veloriel:BAAALgADCgEJAQAAAA==.Venusaur:BAAALgAECgYJDgAAAA==.Veronika:BAAALgADCgcJBwAAAA==.',
Vi='Vince:BAAALgAECgMJAwAAAA==.Vizak:BAAALgADCgUJCAAAAA==.Vizzak:BAAALgAECgYJDgAAAA==.',
Vl='Vladis:BAABLgAECn8VAAISAAYJIAojMwDOAAASAAYJIAojMwDOAAAAAA==.Vlasic:BAAALgAECgUJCAAAAA==.',
Vo='Voidraybih:BAAALgADCgMJAwAAAA==.Voljinx:BAAALgAECgQJBwAAAA==.',
Vu='Vup:BAAALgADCgEJAQAAAA==.',
Vy='Vynestia:BAAALgADCggJCwAAAA==.',
['Vä']='Vääko:BAAALgAECgQJCAAAAA==.',
Wa='Wagyyu:BAAALgADCgkJDwAAAA==.Walldo:BAAALgADCgEJAQAAAA==.Waluigi:BAAALgADCgkJEgABLgAECgYJFAAMAN8QAA==.Wayvrn:BAABLgAECn8iAAIDAAgJDxbMWAAvAgADAAgJDxbMWAAvAgAAAA==.',
We='Weki:BAAALgAECgUJCgAAAA==.Welimarx:BAAALgAECgMJBQAAAA==.Westbrooke:BAAALgADCggJCAAAAA==.Westinghouse:BAAALgADCgYJBgAAAA==.Wetshrimp:BAABLgAECn8hAAISAAgJZx7fBQA4AgASAAgJZx7fBQA4AgAAAA==.',
Wh='Whippoorwill:BAABLgAECn8fAAIgAAgJLhkxGABIAgAgAAgJLhkxGABIAgAAAA==.Whisky:BAAALgADCgcJDAABLgAECggJHgAMABoZAA==.Whosman:BAAALgADCgIJAgAAAA==.',
Wi='Wikkid:BAAALgADCgMJAwAAAA==.Wisdomcheck:BAAALgAECgMJAwAAAA==.',
Wo='Woe:BAAALgAECgIJAwABLgAECgQJCwAFAAAAAA==.Wolfnacht:BAAALgADCgkJIQAAAA==.',
Wr='Wrathfil:BAAALgAECgYJCwAAAA==.Wrene:BAAALgAECgcJCgAAAA==.',
Xe='Xehanerd:BAAALgADCgMJAwAAAA==.Xendar:BAAALgADCgcJBwAAAA==.Xene:BAABLgAECn8YAAIPAAcJ7RrdHwARAgAPAAcJ7RrdHwARAgAAAA==.',
Xi='Xino:BAAALgAECgMJBgAAAA==.',
Xo='Xorthos:BAAALgAECgEJAQAAAA==.',
Ya='Yagirlmolli:BAAALgADCgEJAQAAAA==.Yahla:BAAALgAECgQJBAAAAA==.Yakiki:BAAALgAECgUJBQABLgAFFAYJGAAQAPsgAA==.Yallah:BAAALgADCgIJAgAAAA==.Yanedin:BAABLgAECn8bAAINAAgJQAiRQwA1AQANAAgJQAiRQwA1AQAAAA==.Yathr:BAAALgADCgUJBgAAAA==.',
Ye='Yearp:BAAALgADCgMJAwAAAA==.',
Yi='Yippeezippee:BAAALgADCgEJAQAAAA==.',
Yn='Ynrghost:BAAALgAECgUJCwAAAA==.',
Yo='Yorastai:BAAALgADCgkJCQAAAA==.Yousaidit:BAAALgADCgUJBgABLgAECgYJFAADAG8bAA==.',
Ys='Yserene:BAAALgADCggJHAAAAA==.',
Yu='Yukonilock:BAAALgADCgcJDwABLgAECgYJEgAFAAAAAA==.Yukonícus:BAAALgAECgIJAgABLgAECgYJEgAFAAAAAA==.Yukonïcus:BAAALgAECgYJEgAAAA==.Yumm:BAAALgADCgMJAwAAAA==.',
['Yè']='Yènnefer:BAAALgAECgEJAQAAAA==.',
Za='Zabyr:BAAALgADCgcJBwAAAA==.Zaffeine:BAAALgADCgYJBgAAAA==.Zaladorine:BAAALgADCgMJBgAAAA==.Zaldrena:BAAALgADCgQJBgAAAA==.Zanotgaming:BAAALgAECgYJEQAAAA==.Zaíde:BAAALgADCgcJBwAAAA==.',
Zb='Zbrickashaw:BAAALgAECgQJBAAAAA==.',
Ze='Zelrin:BAACLgAFFH8RAAIDAAYJnhZdBQB2AQADAAYJnhZdBQB2AQAuAAQKfx8AAwMACAlZIRMeAP0CAAMACAlZIRMeAP0CACcAAQk/ByMfADIAAAAA.Zendara:BAAALgAECgMJAwAAAA==.Zenthalion:BAAALgAECgYJCgAAAA==.Zephïre:BAAALgAECgEJAQAAAA==.Zeridar:BAAALgAECgEJAQAAAA==.Zesyus:BAAALgAECgEJAQAAAA==.',
Zi='Zippies:BAAALgAECgQJBAAAAA==.',
Zo='Zobz:BAAALgADCgUJBQAAAA==.Zoomhunt:BAACLgAFFH8RAAMZAAUJVx8/CwBkAQAZAAQJMxw/CwBkAQAhAAIJNR6UBgBfAAAuAAQKfyoAAxkACQnuI/oCAHwDABkACAkXJvoCAHwDACEAAwm4GY8JAAkBAAAA.Zorgborg:BAAALgADCgEJAgAAAA==.',
Zr='Zral:BAAALgADCgMJBAAAAA==.',
Zu='Zutter:BAAALgAECgUJDAAAAA==.',
Zx='Zxy:BAAALgAECgQJBAAAAA==.',
['Íf']='Ífrosty:BAAALgADCgYJBgAAAA==.',
['Ör']='Ördög:BAAALgADCgUJBQAAAA==.',
['ße']='ßearheals:BAAALgADCgUJBQAAAA==.',
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

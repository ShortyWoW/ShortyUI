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

local lookup = {'Priest-Shadow','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Priest-Holy','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Mage-Frost','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Druid-Restoration','Druid-Feral','Warrior-Arms','Evoker-Augmentation','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Warlock-Demonology','Monk-Mistweaver','Rogue-Assassination','Warlock-Affliction','Druid-Guardian','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','DemonHunter-Vengeance','Paladin-Holy','Monk-Windwalker','Rogue-Subtlety',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abukuma:BAAALgAECgIJAgAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYjOQCfAAABAAgJAQYjOQCfAAAAAA==.Aenstalash:BAABLgAECn8YAAICAAcJzCObFQBNAgACAAcJzCObFQBNAgAAAA==.Aephium:BAAALgAECgYJCQAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8hAAIDAAgJ+BZaKQDXAQADAAgJ+BZaKQDXAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAAALgAECgYJEQAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAECggJGAAEAPYhAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8hAAIFAAgJHx5WBwBbAgAFAAgJHx5WBwBbAgAAAA==.',
As='Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8ZAAIGAAYJZw5HEAA6AQAGAAYJZw5HEAA6AQAAAA==.',
Au='Aureliá:BAABLgAECn8VAAIHAAYJcwq3UwATAQAHAAYJcwq3UwATAQAAAA==.',
['Aü']='Aütobot:BAAALgAECgYJEQAAAA==.',
Ba='Badgirl:BAABLgAFFH8HAAIIAAMJowutEQDDAAAIAAMJowutEQDDAAAAAA==.Balnar:BAAALgAECgUJDgABLgAECgYJEwAJAAAAAA==.Balraga:BAAALgAECgcJEQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8WAAMDAAYJcB3fCQC5AQADAAUJcB3fCQC5AQAKAAEJAABJKwAAAAAuAAQKfzcAAwMACQktJVUCAFEDAAMACQktJVUCAFEDAAoABgkrFzolABUBAAAA.Benton:BAAALgAECgQJBwAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8hAAMLAAkJXhbXFwCoAQALAAcJahzXFwCoAQAMAAYJYgpUGQD0AAAAAA==.',
Bo='Bobster:BAABLgAECn8hAAINAAgJ5RH8QwCbAQANAAgJ5RH8QwCbAQAAAA==.Booyea:BAABLgAECn8mAAIKAAgJDhhBCQDrAQAKAAgJDhhBCQDrAQAAAA==.',
Br='Brewwnor:BAAALgAECgMJAwAAAA==.Brickdemkeys:BAABLgAECn8fAAINAAgJPBoOLADxAQANAAgJPBoOLADxAQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAYJEQAOAGQhAA==.Calamuelis:BAACLgAFFH8RAAQOAAYJZCHKBwCeAQAOAAYJjSDKBwCeAQAPAAMJOiHfCgAtAQAHAAEJYx+cSABaAAAuAAQKfxkAAw4ACAmWJLQNANcCAA4ACAmWJLQNANcCAA8AAQloJR4xAG8AAAAA.Caliope:BAAALgAECgEJAQAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBwAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECggJIQAFAB8eAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIQAAUJARC/SQAEAQAQAAUJARC/SQAEAQAAAA==.Cerelus:BAABLgAECn8WAAINAAgJtQpRUwBxAQANAAgJtQpRUwBxAQAAAA==.',
Ch='Chaac:BAAALgAECgYJBgAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAAALgAECggJEwAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgQJCAAAAA==.Cowpernicus:BAABLgAECn8eAAIRAAgJ5SDxBQD1AgARAAgJ5SDxBQD1AgAAAA==.',
Cr='Crungleman:BAABLgAECn8UAAIHAAYJcxu0MQCHAQAHAAYJcxu0MQCHAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECgYJBgAJAAAAAA==.',
Cu='Curoi:BAABLgAECn8dAAMSAAcJlgqBDQA+AQASAAcJlgqBDQA+AQARAAcJUwgteQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8KAAILAAMJCRhrFwD0AAALAAMJCRhrFwD0AAAuAAQKf0AAAwsACQmkHuoDAMcCAAsACQmkHuoDAMcCABMAAgmJH2YsAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8YAAIEAAgJ9iEfDABuAgAEAAgJ9iEfDABuAgAAAA==.',
Da='Daedalas:BAAALgAECgYJDgAAAA==.Damonk:BAAALgADCgYJBgABLgAECgcJIAAIAPciAA==.Danevolent:BAABLgAECn8gAAMIAAcJ9yJ8DQCAAgAIAAcJ9yJ8DQCAAgABAAQJEA3yNgCtAAAAAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAAALgAECgYJEwAAAA==.Darthknull:BAACLgAFFH8GAAICAAMJLgoMMwDrAAACAAMJLgoMMwDrAAAuAAQKfyAAAgIACQkvGAJNAPsBAAIACQkvGAJNAPsBAAAA.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBQABLgAECgEJAQAJAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8gAAIOAAgJMBgfBQDbAQAOAAgJMBgfBQDbAQAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAAALgAECgUJCAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgEJAwAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAYJFwAUACMjAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Donkform:BAAALgAECgUJBQAAAA==.Donniyii:BAAALgADCgcJBwABLgAECgkJJgAVAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8VAAIWAAYJ/hy7FQCcAQAWAAYJ/hy7FQCcAQAAAA==.',
Dr='Draconith:BAABLgAECn8jAAIGAAkJqhSNBQA9AgAGAAkJqhSNBQA9AgAAAA==.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAAALgAECgUJCAAAAA==.Dreddwing:BAAALgAECgUJBQABLgAECgYJBgAJAAAAAA==.',
Du='Dunsparrow:BAABLgAECn80AAIXAAkJsCI6AQB1AwAXAAkJsCI6AQB1AwAAAA==.Durzul:BAAALgADCggJCAAAAA==.',
Ei='Eightyone:BAAALgAECgEJAQAAAA==.Eindraken:BAABLgAECn8hAAIGAAgJABLsCwCMAQAGAAgJABLsCwCMAQAAAA==.Eisis:BAABLgAECn8nAAISAAgJBA9uCwBiAQASAAgJBA9uCwBiAQAAAA==.',
El='Elanalué:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8UAAIYAAYJdQ/EWQAgAQAYAAYJdQ/EWQAgAQAAAA==.Espriesso:BAAALgAECgUJBwABLgAECggJGQAZAGcNAA==.',
Ev='Evodragker:BAABLgAECn8hAAMUAAgJfBXaEQC/AQAUAAgJfBXaEQC/AQAGAAEJcwnnJwA3AAAAAA==.',
Fe='Feldron:BAAALgAECgYJEgAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJBgAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAAALgAECgYJDQAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMHAAkJYh9TDQBxAgAHAAkJYh9TDQBxAgAOAAUJAxLQTgAUAQAAAA==.Frofrolock:BAAALgAECgcJCwAAAA==.Froggie:BAAALgAECgcJEwAAAA==.Froshaman:BAAALgADCgkJCQAAAA==.',
Fu='Fuzywuuzy:BAABLgAECn8aAAIRAAgJ1COeBAAWAwARAAgJ1COeBAAWAwAAAA==.',
Ga='Gazdorn:BAABLgAECn8ZAAIMAAgJjRGjDQCIAQAMAAgJjRGjDQCIAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8aAAIaAAgJExcMAwASAgAaAAgJExcMAwASAgAAAA==.',
Gi='Gigof:BAABLgAECn8jAAMQAAkJ/xDfFACZAQAQAAgJZBHfFACZAQARAAYJQwlLigDAAAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQbAAcJdCWRAQDTAgAbAAcJEiWRAQDTAgAYAAMJhSJLogAUAQAWAAIJjxpYRACkAAAAAA==.',
Go='Gobah:BAAALgAECgYJEwAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAAALgAECgYJEQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Hadory:BAAALgAECgQJBAABLgAECgYJEQAJAAAAAA==.Harrowhark:BAABLgAECn8WAAMbAAYJoggGCgDvAAAbAAYJxwcGCgDvAAAWAAQJyQWsGwBpAAAAAA==.',
He='Hellzzdemon:BAAALgAECgIJBAAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJBQAAAA==.Hezekiiah:BAAALgADCgcJCQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAECgkJNAAXALAiAA==.Holycannoli:BAAALgAECgcJCQAAAA==.Horiffic:BAAALgAECgQJCAAAAA==.Horok:BAAALgAECgIJBgAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAAALgAECgYJEAAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAYJEgAEAAoVAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgYJDgAJAAAAAA==.',
Ii='Iilli:BAABLgAECn8mAAMVAAkJlB8lAgA4AwAVAAkJlB8lAgA4AwABAAcJphHVGQBtAQAAAA==.',
In='Inari:BAAALgAECgYJEgAAAA==.Inkkubus:BAABLgAFFH8KAAMWAAQJQBEPCgCLAAAYAAMJ5xWdQQDYAAAWAAIJYwUPCgCLAAAAAA==.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAISAAQJihYeAgBsAQASAAQJihYeAgBsAQAuAAQKfyMAAhIACAliIzMCADEDABIACAliIzMCADEDAAAA.',
Ja='Jade:BAABLgAECn8YAAIFAAYJYiQ8CwAOAgAFAAYJYiQ8CwAOAgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAJAAAAAA==.Jeronor:BAAALgAECgEJAQAAAA==.',
Ji='Jimmick:BAAALgAECgYJEQAAAA==.Jisung:BAAALgAECgUJBQAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgEJAQAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCQAAAA==.Kalena:BAABLgAECn8mAAINAAgJcg0CSgCKAQANAAgJcg0CSgCKAQAAAA==.Kaos:BAABLgAECn8gAAINAAgJCBL4QQChAQANAAgJCBL4QQChAQAAAA==.Kariatyda:BAABLgAECn8uAAIHAAkJMBgrDQBzAgAHAAkJMBgrDQBzAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgYJDwAJAAAAAA==.Kassandra:BAABLgAECn8mAAINAAgJtxlwIAAoAgANAAgJtxlwIAAoAgAAAA==.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIZAAYJhBhwJACQAQAZAAYJhBhwJACQAQAAAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8XAAIcAAgJkwyhEAD9AAAcAAgJkwyhEAD9AAAAAA==.Kitzy:BAAALgAECgYJEQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn8aAAIDAAgJ6RQJMgCxAQADAAgJ6RQJMgCxAQAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8ZAAIRAAgJPQreNQBAAQARAAgJPQreNQBAAQAAAA==.',
Ko='Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAABLgAECn8rAAMLAAkJGB/xAgDnAgALAAkJGB/xAgDnAgAMAAUJrRLsIAC2AAAAAA==.',
Ky='Kylarian:BAAALgAECgYJEQAAAA==.Kyntara:BAAALgAECgYJBwAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAAALgAECgYJDwAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECgcJEAAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn8nAAICAAgJChNgNQCoAQACAAgJChNgNQCoAQAAAA==.',
Li='Lightbehunt:BAAALgAECgMJBAAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJHgAYACoiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAAAAA==.',
Ly='Lyllith:BAABLgAECn8VAAIaAAYJjRHCCABHAQAaAAYJjRHCCABHAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgcJIAAIAPciAA==.Magnius:BAAALgADCgEJAQAAAA==.Mastablasta:BAAALgAECgIJBQAAAA==.Maursaline:BAABLgAECn8fAAIRAAgJMwh5PAAiAQARAAgJMwh5PAAiAQAAAA==.Mawks:BAABLgAECn8XAAIPAAcJTRkzCgA3AgAPAAcJTRkzCgA3AgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCQAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgADCgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Mixxon:BAAALgAECgYJDQAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8YAAIdAAgJfBeCFACxAQAdAAgJfBeCFACxAQAAAA==.Morhgana:BAAALgAECgUJCAAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMIAAgJygGFLgDYAAAIAAgJygGFLgDYAAABAAIJXwHRZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAYJEgAEAAoVAA==.Nilius:BAAALgADCgcJBwABLgAECgYJDgAJAAAAAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgYJBgAJAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8VAAIeAAYJCxOCEwANAQAeAAYJCxOCEwANAQAAAA==.',
['Ní']='Níce:BAAALgAECgEJAgAAAA==.',
['Nü']='Nügs:BAAALgAECgcJEgAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgQJBAABLgAECggJHQALAOYPAA==.Painnkiller:BAABLgAECn8iAAIHAAgJgx36EwAwAgAHAAgJgx36EwAwAgAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAAALgAECgUJCwABLgAECggJIQAFAB8eAA==.Paxis:BAAALgAECggJCwAAAA==.',
Pe='Perriwinkle:BAABLgAECn8jAAQSAAgJdBcqCwAQAgASAAgJ3hUqCwAQAgAcAAYJ+BINEAAHAQARAAIJ0AuDzAAyAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAAALgAECgcJEwAAAA==.Phylloxeras:BAABLgAECn8mAAIDAAgJzSL7CgCzAgADAAgJzSL7CgCzAgAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn8qAAINAAgJTBhDKAABAgANAAgJTBhDKAABAgAAAA==.',
Pr='Proshot:BAABLgAECn8fAAIPAAgJrhn2BgA/AgAPAAgJrhn2BgA/AgAAAA==.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECggJHgAfAIkWAA==.',
Ra='Raccoon:BAABLgAECn8mAAIYAAgJHg7yMgCYAQAYAAgJHg7yMgCYAQAAAA==.Ravenhawk:BAAALgAECgQJCAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAAALgAECgYJDgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8SAAIEAAYJChX1DwB3AQAEAAYJChX1DwB3AQAuAAQKfyAAAwQACQlIH2YjAH0CAAQACQlIH2YjAH0CACAAAglxEwQmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8fAAMLAAgJOxFWHACFAQALAAgJOxFWHACFAQATAAEJBwgqQgArAAAAAA==.',
Sa='Samidrac:BAAALgAECgUJDAAAAA==.Sammidormu:BAABLgAECn8cAAQfAAcJyhHzBQB2AQAfAAcJyhHzBQB2AQAUAAYJDgtVNgAgAQAGAAEJ2QEITgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8VAAMWAAYJ/A8UNADnAAAYAAYJ2gy2mwAiAQAWAAUJThEUNADnAAAAAA==.Satoshie:BAAALgADCgMJAwAAAA==.',
Sc='Scerevisiae:BAAALgAECgUJDgAAAA==.',
Se='Sedelis:BAABLgAECn8UAAIhAAgJbQvDIQB5AQAhAAgJbQvDIQB5AQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8WAAIRAAYJ1Rp2IgCzAQARAAYJ1Rp2IgCzAQAAAA==.Serafín:BAABLgAECn8mAAIFAAgJCAoqIAA1AQAFAAgJCAoqIAA1AQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgUJDAAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECgQJBAAAAA==.Shieldwall:BAABLgAECn8iAAIMAAgJugiMFAAlAQAMAAgJugiMFAAlAQAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8XAAICAAcJsBAETQBeAQACAAcJsBAETQBeAQAAAA==.',
So='Solone:BAAALgAECgEJAQAAAA==.Sopidia:BAABLgAECn8dAAMXAAcJtBb2HADJAQAXAAcJtBb2HADJAQAdAAQJUwUISgB8AAAAAA==.Sorvato:BAABLgAECn8WAAIEAAYJ+BNzSgAZAQAEAAYJ+BNzSgAZAQAAAA==.',
Sp='Spoonzz:BAABLgAECn8qAAMiAAkJMCCWAwDBAgAiAAkJMCCWAwDBAgAFAAIJKx+NOAC2AAAAAA==.',
St='Stamavan:BAABLgAECn8hAAIcAAgJoCPlAQCwAgAcAAgJoCPlAQCwAgAAAA==.Starflayer:BAABLgAECn8nAAMEAAkJXhzoDQBaAgAEAAkJbRvoDQBaAgAgAAIJYxr2IAB8AAAAAA==.Sterjariger:BAAALgAECgYJBgABLgAECgkJGgAKAIIeAA==.',
Su='Sunari:BAAALgAECgMJBAAAAA==.Supermelon:BAAALgAECgYJEgAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvanaria:BAABLgAECn8mAAIXAAgJWSZoAQBrAwAXAAgJWSZoAQBrAwAAAA==.Sylvanaris:BAAALgAECgYJCwAAAA==.Systyx:BAABLgAECn8bAAIYAAcJbB+9HwDyAQAYAAcJbB+9HwDyAQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwAJAAAAAA==.Talenel:BAAALgAECgMJAwAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAABLgAECn8lAAMUAAgJkRPZEQC/AQAUAAgJkRPZEQC/AQAGAAcJSRLkHACeAQAAAA==.Tealyn:BAAALgADCgYJCgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8iAAIDAAgJCyWCFAAAAwADAAgJCyWCFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6JpAA3AQACAAYJ7Q6JpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAABLgAECn8rAAIKAAkJnhuKBABuAgAKAAkJnhuKBABuAgAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJEgAJAAAAAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trout:BAAALgADCgYJDAABLgAECgYJCgAJAAAAAA==.Trovikk:BAAALgADCgUJBQAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAJAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8eAAIdAAgJ/x2NCQBBAgAdAAgJ/x2NCQBBAgAAAA==.',
Va='Valarios:BAAALgAECgYJBgAAAA==.Vannhellsing:BAABLgAECn8aAAIDAAcJjgj5YAAjAQADAAcJjgj5YAAjAQAAAA==.Vanyel:BAABLgAECn8vAAINAAgJYg8XQgChAQANAAgJYg8XQgChAQAAAA==.Vaudorka:BAABLgAECn8ZAAIfAAgJ2R7ZAQBWAgAfAAgJ2R7ZAQBWAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJEAAJAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn8gAAMVAAgJKhCFFgCHAQAVAAcJ7A6FFgCHAQAIAAcJzgiWKAAFAQAAAA==.Vemal:BAABLgAECn8eAAIHAAkJuQ6YIQDTAQAHAAkJuQ6YIQDTAQAAAA==.',
Vo='Vociferoy:BAABLgAECn8sAAIHAAgJ3h/RCgCNAgAHAAgJ3h/RCgCNAgAAAA==.Voidsteffan:BAAALgAECgYJEwAAAA==.',
Vr='Vryadox:BAAALgAECgcJDQABLgAECggJLwANAL8lAA==.',
Vv='Vv:BAACLgAFFH8gAAIEAAcJ8CSqAACTAgAEAAcJ8CSqAACTAgAuAAQKfy4AAgQACQm1JucAANoDAAQACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJEwAJAAAAAA==.',
Xi='Xingwong:BAABLgAECn8mAAIjAAYJ+SWZBwAvAgAjAAYJ+SWZBwAvAgAAAA==.',
Za='Zannytoes:BAABLgAECn8gAAIZAAgJBQ3yHgBPAQAZAAgJBQ3yHgBPAQAAAA==.',
Ze='Zead:BAAALgAECgEJAwAAAA==.Zerana:BAAALgAECgYJCQAAAA==.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn8uAAIBAAgJ4RL6EQC5AQABAAgJ4RL6EQC5AQAAAA==.Zikren:BAAALgAECggJCAAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIEAAgJlxy+DwBGAgAEAAgJlxy+DwBGAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAABLgAFFH8GAAILAAMJiRsRFgD/AAALAAMJiRsRFgD/AAAAAA==.',
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

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

local lookup = {'Priest-Discipline','Paladin-Protection','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Warrior-Protection','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Fury','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination','Priest-Shadow','Rogue-Subtlety','Mage-Fire','Evoker-Preservation','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane','DeathKnight-Frost','Shaman-Elemental','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aalst:BAAALgAECgYJDgAAAA==.',
Ac='Achillesheal:BAABLgAECn8VAAIBAAYJoR8OFAAMAgABAAYJoR8OFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acshec:BAAALgADCgUJDQABLgAECgcJFAACAIsaAA==.Acuna:BAAALgADCgkJEgAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn8YAAIDAAcJNAxdGgAsAQADAAcJNAxdGgAsAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.',
Ag='Aggrenox:BAAALgAECgYJEAAAAA==.',
Ai='Aisathya:BAAALgAECgcJEgAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJBgAAAA==.Albina:BAAALgAECgEJAgAAAA==.Aldelvir:BAAALgAECgIJAgABLgAECgcJHgAEANMQAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAAALgAECggJEAAAAA==.Alzhimers:BAAALgAECgIJAwAAAA==.',
Am='Amberscale:BAABLgAECn8jAAIFAAgJWhx3BQBUAgAFAAgJWhx3BQBUAgAAAA==.Amyrrin:BAAALgAECgcJEgAAAA==.',
An='Ancientiur:BAAALgAFFAIJAgAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAAALgAECgYJEQAAAA==.Angrulus:BAABLgAECn8fAAIGAAgJBhe/EQAGAgAGAAgJBhe/EQAGAgAAAA==.Animal:BAAALgADCgUJBQAAAA==.Animlshiftr:BAABLgAECn8VAAIEAAcJ3QeqDQABAQAEAAcJ3QeqDQABAQAAAA==.',
Ap='Apollo:BAAALgAECgYJDQAAAA==.',
Ar='Aradunn:BAACLgAFFH8HAAIHAAMJzB8DEQAJAQAHAAMJzB8DEQAJAQAuAAQKfxwAAwcACAkZI/kGAAQDAAcACAkZI/kGAAQDAAgAAgncBxctADIAAAAA.Araedis:BAAALgAECgcJEwAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwAJAPwJAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDAAAAA==.',
As='Assaelysia:BAAALgADCgYJBgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgADCgMJAwAAAA==.Astralon:BAAALgAECgEJAQAAAA==.',
At='Atharion:BAABLgAECn8ZAAMKAAcJ7RzqBwBcAgAKAAcJ7RzqBwBcAgALAAMJZAwdDAF/AAAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJAwAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAAALgAECgcJEQAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAAALgAECgUJCAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAAALgAECgYJEwAAAA==.Balinor:BAAALgAECgYJDgABLgAECgcJGAAJAIIdAA==.',
Be='Bearett:BAABLgAECn8VAAIMAAgJbhpBBADmAQAMAAgJbhpBBADmAQAAAA==.Beefynacho:BAAALgADCgMJAwAAAA==.Belyhell:BAAALgADCgUJBQAAAA==.Belymoon:BAAALgAECgkJBgAAAA==.Bernd:BAABLgAECn8WAAIMAAcJUg60DADtAAAMAAcJUg60DADtAAAAAA==.Beörn:BAAALgAECgcJEwAAAA==.',
Bl='Blackgrinn:BAAALgAECgcJEgAAAA==.Blackkgrin:BAAALgADCgQJBAAAAA==.Blasphemous:BAAALgAECgYJEAAAAA==.Blasé:BAABLgAECn8pAAMNAAYJ2CQDFAAFAgANAAYJ2CQDFAAFAgAOAAEJAACcXABZAAAAAA==.Blazéoné:BAAALgAECgEJAQAAAA==.Blessin:BAAALgAECgcJBwAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMPAAIJ7xJyHQCgAAAPAAIJ7xJyHQCgAAAGAAIJMAiPLgCaAAAuAAQKfyYABA8ACAmoH+UNANICAA8ACAkUHuUNANICABAABgnpHWoKALsBAAYAAglkHsJcALMAAAAA.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAIRAAcJdR3PSAAZAgARAAcJdR3PSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwARAHUdAA==.Bootypls:BAACLgAFFH8KAAMSAAMJvBWVDgCAAAARAAIJ5htnSgCuAAASAAIJBwyVDgCAAAAuAAQKfx4AAxIACAlZG2YVALwBABIACAlzF2YVALwBABEABAnxHQ98AKQAAAAA.',
Br='Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8cAAIRAAgJMxrcFQALAgARAAgJMxrcFQALAgAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Butschi:BAAALgAECgkJBgAAAA==.',
Bw='Bwca:BAAALgAFFAEJAQABLgAFFAIJBQAHAF0FAA==.',
Ca='Caine:BAABLgAECn8YAAIJAAcJgh07DABIAgAJAAcJgh07DABIAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgQJBAABLgAECgcJEAATAAAAAA==.Casey:BAAALgAECgQJBwAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAAALgAECgcJEAAAAA==.',
Ce='Cellina:BAAALgAECgcJCwAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgADCgcJCAABLgAECggJGQAUAPkPAA==.',
Ch='Chiman:BAAALgAECgUJBwAAAA==.Chronophage:BAAALgAECgQJBAAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Cl='Classá:BAACLgAFFH8FAAIVAAMJyRXyDwD9AAAVAAMJyRXyDwD9AAAuAAQKfygAAxUACAlwIDoOALkCABUABwkhJDoOALkCABYABQk8HslGAIcBAAAA.Clawz:BAAALgADCgYJBgABLgAFFAEJAQATAAAAAA==.',
Co='Codedd:BAAALgAECgcJDwAAAA==.Commit:BAAALgAECgYJCQAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAABLgAECn8WAAILAAcJIx/0EwAbAgALAAcJIx/0EwAbAgAAAA==.',
Cr='Crispìn:BAAALgAECgQJBQAAAA==.Crossbones:BAAALgAECgEJAQAAAA==.Crue:BAAALgAECgMJAwAAAA==.',
Cu='Curthar:BAAALgAFFAEJAQAAAA==.',
Cy='Cyndee:BAABLgAECn8hAAIXAAgJxhDiEACzAQAXAAgJxhDiEACzAQAAAA==.Cynnafrost:BAAALgADCgUJBQAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn8bAAIPAAcJ8B4EBQCyAQAPAAcJ8B4EBQCyAQAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgADCgYJBgABLgAECgYJEwATAAAAAA==.Dankmonk:BAAALgAECgUJEgAAAA==.Darcnis:BAAALgADCgkJCQAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn8XAAIYAAcJGgXNRQDUAAAYAAcJGgXNRQDUAAAAAA==.Darklasminth:BAAALgAECgQJBQAAAA==.Darthwang:BAABLgAECn8eAAINAAYJ3RjgWgC3AQANAAYJ3RjgWgC3AQAAAA==.Dartos:BAABLgAECn8oAAIRAAgJ9CKkFAAAAwARAAgJ9CKkFAAAAwAAAA==.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAUJCwAUABgVAA==.Deep:BAAALgAECgEJAQABLgAECggJIQAZAOYgAA==.Deepfister:BAABLgAECn8hAAIZAAgJ5iDEAwCvAgAZAAgJ5iDEAwCvAgAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECggJIQAZAOYgAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgYJBQAAAA==.Diluvium:BAABLgAECn8YAAILAAcJrgtIQABJAQALAAcJrgtIQABJAQAAAA==.Discodank:BAAALgADCgQJBAAAAA==.',
Dj='Djpleasant:BAABLgAECn8jAAIUAAgJqR3fEQBNAgAUAAgJqR3fEQBNAgAAAA==.',
Dk='Dktelmtwo:BAAALgADCgYJCAAAAA==.',
Do='Doneisha:BAAALgAECgQJCAAAAA==.Dontcare:BAAALgADCgYJBgAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAAALgAECgYJEgAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAABLgAECn8WAAIVAAgJjx3eBABmAgAVAAgJjx3eBABmAgAAAA==.',
Du='Dunzledorf:BAAALgADCgYJBgAAAA==.',
Dy='Dynammes:BAAALgAECgYJEAABLgAECggJHwAFAF0TAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgADCgkJKwAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8HAAIDAAQJzxT9DAAqAQADAAQJzxT9DAAqAQAuAAQKfxQAAwMACAkVG2YPAJoBABoABwkpF94jALcBAAMABQmDG2YPAJoBAAAA.',
El='Elementals:BAAALgAECgcJDgAAAA==.Elixera:BAAALgADCgUJBQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.',
Em='Emilwhaury:BAAALgADCgIJAgAAAA==.',
Ep='Epia:BAABLgAECn8XAAIaAAcJgwpqGAAlAQAaAAcJgwpqGAAlAQAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Essaila:BAAALgAECgYJEAAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8VAAMXAAYJSx6qEwCYAQAXAAYJSx6qEwCYAQAbAAEJ3BbeOABMAAAAAA==.',
Ev='Evocati:BAAALgAECgYJDgAAAA==.Evoka:BAABLgAECn8fAAMcAAcJaR4mBACSAQAcAAcJaR4mBACSAQAFAAUJIRdEHAAdAQAAAA==.',
Ex='Excision:BAABLgAECn8UAAMcAAcJZQ2yHgA5AQAcAAcJZQ2yHgA5AQAFAAMJggdCPgBYAAAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Ez='Ezindrozath:BAABLgAECn8XAAQNAAcJdRKUKgCDAQANAAcJVRGUKgCDAQAdAAQJAhQmEQAbAQAOAAEJ7wVCeQAqAAAAAA==.',
Fa='Fahbio:BAAALgAECgYJEAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAAALgAECgUJEgAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgADCgQJBAABLgAECgUJEgATAAAAAA==.Fivevolts:BAABLgAECn8WAAIeAAcJ4iCOAQA8AgAeAAcJ4iCOAQA8AgAAAA==.',
Fl='Flailuid:BAAALgAECgQJCAAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgEJAwAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgQJBAAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAABLgAECn8sAAIaAAgJLiJUAgC/AgAaAAgJLiJUAgC/AgAAAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8YAAIFAAgJdgz0MgAzAQAFAAgJdgz0MgAzAQAAAA==.',
Fu='Fudd:BAAALgAECgYJEAAAAA==.Fupa:BAAALgAECgUJCQAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAAALgAECgcJEgAAAA==.',
Ge='Genius:BAABLgAECn8VAAIbAAYJsRr4CAB1AQAbAAYJsRr4CAB1AQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAILAAgJyhjnfgB8AQALAAgJyhjnfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgADCgIJAgAAAA==.Gnomad:BAAALgAECgUJEgAAAA==.',
Go='Gouge:BAAALgAECggJKQAAAQ==.',
Gr='Griffynshu:BAAALgAECgYJCwAAAA==.Griz:BAAALgADCgkJDwAAAA==.Grunewald:BAABLgAECn8pAAIGAAcJ0gaIPAAhAQAGAAcJ0gaIPAAhAQAAAA==.',
Gu='Gula:BAABLgAECn8gAAMdAAgJExc+CQCxAQAdAAYJHRc+CQCxAQANAAgJ0xU9IwClAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAABLgAECn8WAAMfAAcJrROTIADUAQAfAAcJrROTIADUAQABAAQJ3iEUMAAfAQAAAA==.Hando:BAAALgADCgYJBgAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAABLgAECn8aAAIDAAkJsg+fCQDyAQADAAkJsg+fCQDyAQAAAA==.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIgAAgJ/xqyCQDPAQAgAAgJ/xqyCQDPAQAAAA==.Heimdall:BAAALgAECgYJCwAAAA==.Hellavva:BAAALgAECgMJAwAAAA==.Hench:BAAALgADCgIJAgAAAA==.Henchling:BAABLgAECn8rAAIHAAkJGyDNBACuAgAHAAkJGyDNBACuAgAAAA==.Henchragon:BAAALgADCgEJAQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIUAAcJzxvEIgDeAQAUAAcJzxvEIgDeAQABLgAFFAMJBwAFAG4TAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAgAP8aAA==.Holexios:BAAALgAECgQJBgABLgAECgUJBwATAAAAAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAQAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAAALgAECgUJCQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgcJDgAAAA==.Icyscorcher:BAABLgAECn8ZAAMUAAgJ+Q9qLQCuAQAUAAgJ+Q9qLQCuAQAhAAMJpwOyCwB3AAAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.',
Im='Immeira:BAAALgAECgYJEAAAAA==.',
In='Intense:BAAALgAECgIJAgAAAA==.',
Ja='Jackheals:BAABLgAECn8hAAMWAAYJAiBqJwAYAgAWAAYJAiBqJwAYAgAVAAEJ2QHMjwAbAAAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinphoenix:BAABLgAECn8TAAMGAAcJPBh3FQDmAQAGAAcJPBh3FQDmAQAPAAQJkAdtXwDDAAAAAA==.',
Jo='Jobin:BAACLgAFFH8FAAIRAAMJ+g4yOQDqAAARAAMJ+g4yOQDqAAAuAAQKfxgAAhEACAm2G3tAAD0BABEACAm2G3tAAD0BAAAA.Journei:BAAALgAECgQJBwAAAA==.',
Ju='Judging:BAABLgAECn8WAAMKAAcJ2hD0HwBHAQAKAAcJ2hD0HwBHAQALAAIJTiSDbADWAAAAAA==.',
Ka='Kaiduo:BAAALgADCgEJAQAAAA==.Kalmas:BAAALgAFFAIJBAAAAA==.',
Ke='Kegz:BAAALgADCgcJBwAAAA==.Kelendrian:BAAALgADCgkJCgAAAA==.Kellayna:BAAALgAECgQJBAAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgADCgQJBAAAAA==.Kezix:BAABLgAECn8bAAINAAgJOQ8VIQCvAQANAAgJOQ8VIQCvAQAAAA==.',
Kh='Kharigosa:BAAALgADCgcJBwABLgAECgYJCQATAAAAAA==.',
Ki='Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8gAAQFAAgJ7xCkIwChAQAFAAgJLA+kIwChAQAcAAIJ1AslEwA7AAAiAAEJwQFrTgAiAAAAAA==.',
Kl='Klerik:BAACLgAFFH8KAAINAAUJJAeVJQAIAQANAAUJJAeVJQAIAQAuAAQKfyEABA0ACQkIH7YJAHICAA0ACAlDHrYJAHICAA4AAgkpEmdMAIgAAB0AAQluJMALAG0AAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8MAAISAAQJ3x5+BQBGAQASAAQJ3x5+BQBGAQAuAAQKfysAAhIACAmJImwCAEUCABIACAmJImwCAEUCAAAA.Kore:BAAALgAECgYJEAAAAA==.Kozarke:BAABLgAECn8WAAIcAAcJdxFDBACKAQAcAAcJdxFDBACKAQAAAA==.',
Kp='Kpop:BAABLgAECn8VAAIjAAcJZR4vBwAWAgAjAAcJZR4vBwAWAgABLgAECgkJGgADALIPAA==.',
Kr='Krissia:BAABLgAECn8eAAIRAAgJjhmbHgDQAQARAAgJjhmbHgDQAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgADCgYJBgAAAA==.',
['Kí']='Kítsuñe:BAAALgADCgcJBwAAAA==.',
['Kî']='Kîn:BAAALgAECgYJEAAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8fAAIkAAYJkhRgLwCFAQAkAAYJkhRgLwCFAQAAAA==.Lalipop:BAAALgAECgYJEAAAAA==.Landroval:BAABLgAECn8WAAIFAAcJRRqfCgDfAQAFAAcJRRqfCgDfAQAAAA==.Lauma:BAABLgAFFH8FAAIHAAIJXQWoJgB1AAAHAAIJXQWoJgB1AAAAAA==.Lawson:BAAALgAECgcJEwAAAA==.',
Le='Lelora:BAAALgAECgQJCAAAAA==.Lenthaden:BAABLgAECn8YAAMOAAcJuRViJQAyAQANAAcJjBA8OwBBAQAOAAYJ+BJiJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgADCgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lilflame:BAAALgADCgUJCAAAAA==.Lilgonzo:BAAALgAECgYJBgABLgAFFAMJBwAFACASAA==.Lio:BAAALgAECgYJCgAAAA==.Lissetteliz:BAAALgADCgcJCwAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJCAAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.',
Ly='Lyreth:BAABLgAECn8gAAIVAAgJNREkEACSAQAVAAgJNREkEACSAQAAAA==.',
Ma='Madax:BAABLgAECn8YAAIXAAcJjhy2DADkAQAXAAcJjhy2DADkAQABLgAECggJHwAFAF0TAA==.Mageymutt:BAACLgAFFH8LAAIUAAUJGBVUDAC7AQAUAAUJGBVUDAC7AQAuAAQKfyUAAxQACAmMIJwlANwCABQACAmMIJwlANwCACUAAwkmCyAUAIQAAAAA.Maggidabeast:BAAALgAECgcJEwAAAA==.Maison:BAAALgAECgQJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAABLgAECn8iAAImAAgJzheJAwBPAgAmAAgJzheJAwBPAgAAAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAABLgAECn8gAAIUAAgJdhgfTwBKAgAUAAgJdhgfTwBKAgAAAA==.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAMJBQAVAMkVAA==.Missbehaving:BAABLgAECn8UAAIkAAcJlRTBEgCEAQAkAAcJlRTBEgCEAQAAAA==.',
Mo='Morefire:BAAALgAECgIJAgABLgAECgcJDgATAAAAAA==.Mosmos:BAAALgADCgUJDAAAAA==.',
Mu='Muddslinger:BAAALgAECgYJDAAAAA==.Mumra:BAABLgAECn8UAAQkAAcJKQIPKwCmAAABAAYJdgFXPwC0AAAkAAYJGQIPKwCmAAAfAAEJAACvSgAAAAAAAA==.',
My='Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgADCgkJFQAAAA==.Nanaki:BAABLgAECn8dAAIiAAgJsx70BgDQAgAiAAgJsx70BgDQAgAAAA==.Nannette:BAAALgAECgYJDgAAAA==.Nappe:BAAALgADCgcJBwABLgAECgcJEwATAAAAAA==.Narag:BAABLgAECn8XAAIGAAcJ/BKvJQCDAQAGAAcJ/BKvJQCDAQAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJAgAAAA==.Netanyahoo:BAAALgAECgUJBwAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8UAAMHAAcJrhkcMQDCAQAHAAcJrhkcMQDCAQAnAAIJqwgOQgBfAAAAAA==.',
Ni='Ninex:BAABLgAECn8ZAAIKAAcJbiDSGABMAgAKAAcJbiDSGABMAgAAAA==.Ninisina:BAABLgAECn8aAAMHAAYJzRyCIQBZAQAHAAYJzRyCIQBZAQAIAAEJ7wOCLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgADCgEJAgAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Nowon:BAAALgAECgYJDwAAAA==.',
Nu='Nudream:BAAALgAECgcJDgAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAAALgAECgYJEwAAAA==.',
Ol='Oldjerry:BAAALgAECgUJEgAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Op='Opalyte:BAAALgAECgYJDwAAAA==.',
Or='Orichalcum:BAABLgAECn8YAAIZAAcJ5RxcFAAmAgAZAAcJ5RxcFAAmAgAAAA==.Orphiee:BAAALgADCgkJEgAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAIJAgAAAQ==.',
Pa='Pakoros:BAABLgAECn8fAAMHAAgJ3RG1EwDPAQAHAAgJ3RG1EwDPAQAnAAQJBwp0agCZAAAAAA==.Pallyfreak:BAAALgADCgcJDgAAAA==.',
Pe='Peachy:BAAALgADCgEJAgABLgAECgcJFgAHAP8VAA==.Penderin:BAAALgADCgYJBgABLgAECgcJHgAEANMQAA==.Pensham:BAAALgAECgEJAQABLgAECgcJHgAEANMQAA==.Perlindree:BAABLgAECn8XAAIGAAYJnAjTSgDwAAAGAAYJnAjTSgDwAAAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8eAAIGAAcJphJ1JgB/AQAGAAcJphJ1JgB/AQAAAA==.',
Ph='Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8TAAILAAcJVRCkNgBpAQALAAcJVRCkNgBpAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgATAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAAALgAECgYJDQAAAA==.Poppers:BAAALgADCgUJBQAAAA==.',
Pr='Preacharond:BAABLgAECn8mAAIfAAgJnhhDFQBCAgAfAAgJnhhDFQBCAgAAAA==.Promir:BAAALgAECgQJCAAAAA==.',
Pu='Purdie:BAAALgAECgQJBAABLgAECgcJEAATAAAAAA==.',
Qe='Qeesa:BAAALgADCgYJBgAAAA==.',
Ra='Raeliene:BAAALgAECgYJEQAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8YAAIBAAcJqxs0CgDsAQABAAcJqxs0CgDsAQAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Relaxnerdlol:BAAALgAECgEJAQAAAA==.Renew:BAAALgAECggJCQAAAA==.Renix:BAABLgAECn8jAAMnAAgJnB0mBwAzAgAnAAgJnB0mBwAzAgAIAAEJdQsQLQAyAAAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgEJAQAAAA==.',
Ri='Riverah:BAAALgAECgQJBAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAAALgAECgQJCwAAAA==.',
Ry='Ryyah:BAABLgAECn8ZAAMKAAcJcArRHgBRAQAKAAcJcArRHgBRAQALAAQJOQMIlgB5AAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAEJAQAAAA==.',
Sa='Saetyl:BAAALgAECgYJEQAAAA==.Saga:BAAALgADCgEJAQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQATAAAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQATAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semii:BAAALgAECgIJAgAAAA==.Serkesul:BAABLgAECn8YAAIfAAcJLySYAwB+AgAfAAcJLySYAwB+AgAAAA==.Sevinas:BAAALgAECgUJCQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shamallamá:BAAALgADCgkJCgAAAA==.Shamwoww:BAAALgAECgYJBgABLgAECggJJgAfAJ4YAA==.Shamyou:BAAALgAECgcJDAAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAAALgAECgYJCwABLgAECgkJGgADALIPAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8KAAIHAAQJ3yVDAwDBAQAHAAQJ3yVDAwDBAQAuAAQKfycAAgcACQnrJTMDAEcDAAcACQnrJTMDAEcDAAAA.',
Si='Silvey:BAABLgAECn8WAAIYAAcJJCDYCwAhAgAYAAcJJCDYCwAhAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAAALgAECgcJDgAAAA==.Skully:BAAALgADCgEJAQAAAA==.Skyylorne:BAAALgAECgIJAgAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgAAAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snowfawn:BAAALgAECgUJDgABLgAECgYJCgATAAAAAA==.Snusnurae:BAAALgAECgMJAwAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Somay:BAAALgADCgYJBgAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECggJHQAiALMeAA==.',
Sp='Spanana:BAABLgAFFH8MAAIRAAQJThKqFQBNAQARAAQJThKqFQBNAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8QAAIUAAcJyyJdBgD6AQAUAAcJyyJdBgD6AQAuAAQKfxcAAhQACAnbIRAdAAEDABQACAnbIRAdAAEDAAAA.Splishsplásh:BAAALgAECgUJCQAAAA==.Sprattyboii:BAAALgAECgQJBAAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAAALgAECgcJDQAAAA==.',
St='Starzia:BAABLgAECn8YAAIBAAcJ4wf9FgA2AQABAAcJ4wf9FgA2AQAAAA==.Stupidtree:BAABLgAECn8WAAIWAAcJkiN+GQBsAgAWAAcJkiN+GQBsAgAAAA==.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8WAAINAAcJGxmNIgCoAQANAAcJGxmNIgCoAQAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJAwABLgAECgMJBAATAAAAAA==.Swiftblossom:BAAALgADCgkJFgAAAA==.',
Sy='Sylvanex:BAAALgAECgIJAgAAAA==.',
Ta='Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgQJBQABLgAECgUJBwATAAAAAA==.Talarus:BAAALgAECggJCQAAAA==.Tanadria:BAAALgAECgUJCgAAAA==.Tangerene:BAABLgAECn8ZAAMBAAgJTgUFLgAuAQABAAcJ3wUFLgAuAQAkAAYJFAIKXgC6AAAAAA==.Tapioca:BAABLgAECn8dAAIGAAgJgiDIBgCLAgAGAAgJgiDIBgCLAgAAAA==.Tashyr:BAAALgADCgUJCAAAAA==.',
Te='Telm:BAABLgAECn8UAAMCAAcJixqZDgAXAQACAAcJUxqZDgAXAQALAAQJCRZT0wDjAAAAAA==.Tentilious:BAAALgADCggJCAAAAA==.',
Th='Thadeusputz:BAAALgADCgcJCAAAAA==.Thaÿne:BAAALgAECgcJDgAAAA==.Thebestpally:BAABLgAECn8lAAMCAAgJdxgZBQDrAQACAAgJ7hcZBQDrAQALAAUJiw305ADEAAAAAA==.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAAALgAECgYJDwAAAA==.Tidds:BAAALgAECgYJEgAAAA==.',
To='Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8NAAIHAAcJFBOKAQDmAQAHAAcJFBOKAQDmAQAuAAQKfxkAAgcACAl8I2IHAP4CAAcACAl8I2IHAP4CAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAABLgAECn8qAAMFAAgJAxfbFgAfAgAFAAgJAxfbFgAfAgAcAAMJJgShMwB3AAAAAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJBQABLgAECggJHQAGAIIgAA==.',
Uj='Ujio:BAAALgAECgYJEAAAAA==.',
Un='Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgEJAgAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAECgYJGQABLgAFFAIJAgATAAAAAQ==.',
Va='Vaden:BAAALgAECgEJAQABLgAECgYJCgATAAAAAA==.Vaelthys:BAAALgADCgYJCQAAAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAABLgAECn8fAAMFAAgJXRNgDwCYAQAFAAgJCxNgDwCYAQAcAAIJ2gqtOQBMAAAAAA==.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAECggJHQALANYdAA==.Vanaheim:BAAALgADCgkJFgAAAA==.Vance:BAAALgAECgYJBgAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Varala:BAAALgADCgkJHAAAAA==.',
Ve='Vel:BAACLgAFFH8NAAIRAAUJvR7tKwAOAQARAAUJvR7tKwAOAQAuAAQKfzAAAhEACAmFJZ4KAEcDABEACAmFJZ4KAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Vellea:BAAALgAECgQJBQABLgAECgUJBwATAAAAAA==.Velýth:BAAALgAECgUJDAABLgAFFAUJDQARAL0eAA==.Veritas:BAAALgAECgEJBAAAAA==.Vexxius:BAABLgAECn8VAAMQAAkJJRi4AwBYAgAQAAkJ3RO4AwBYAgAPAAcJJxSSCABQAQAAAA==.',
Vo='Vorathis:BAAALgADCgEJAQABLgAFFAMJBwAHAMwfAA==.',
Vy='Vylana:BAAALgADCggJHgABLgAECgcJEAATAAAAAA==.',
['Và']='Vàlkyrie:BAABLgAECn8dAAILAAgJ1h1yIgCgAgALAAgJ1h1yIgCgAgAAAA==.',
Wa='Wack:BAAALgAECggJCwAAAA==.Wanderfoot:BAAALgAECgYJCgAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8cAAINAAgJXhFYJACfAQANAAgJXhFYJACfAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIJAAgJ/AkrIwAlAQAJAAgJ/AkrIwAlAQAAAA==.Wavestabe:BAABLgAECn8eAAIEAAcJ0xCdCABlAQAEAAcJ0xCdCABlAQAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgcJHgAEANMQAA==.',
Wr='Wreck:BAABLgAECn8YAAINAAcJIQsqSAAYAQANAAcJIQsqSAAYAQAAAA==.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.',
Ya='Yayrri:BAABLgAECn8WAAInAAcJBg+uGABNAQAnAAcJBg+uGABNAQAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zathamax:BAAALgAECgUJDQAAAA==.Zavya:BAAALgADCgEJAQABLgAECgYJEAATAAAAAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8bAAIoAAYJDRFJEwATAQAoAAYJDRFJEwATAQAAAA==.',
Zi='Ziaya:BAAALgAECgYJEAAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgEJAgABLgAECgUJBwATAAAAAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8YAAIoAAcJmQWjFgDsAAAoAAcJmQWjFgDsAAAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Él']='Élwë:BAAALgADCgUJBQAAAA==.',
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

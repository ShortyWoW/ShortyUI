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

local lookup = {'Priest-Discipline','Unknown-Unknown','Druid-Feral','Evoker-Augmentation','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warrior-Fury','Mage-Frost','Monk-Mistweaver','Paladin-Retribution','Evoker-Devastation','Monk-Windwalker','Warlock-Affliction','Priest-Shadow','Monk-Brewmaster','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane','DeathKnight-Frost','Paladin-Holy','Shaman-Elemental','Paladin-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aalst:BAAALgAECgQJBwAAAA==.',
Ac='Achillesheal:BAABLgAECn8UAAIBAAYJoR8NFAAMAgABAAYJoR8NFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acshec:BAAALgADCgUJDQABLgAECgYJEgACAAAAAA==.Acuna:BAAALgADCgkJEgAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEALgAECgcJEQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.',
Ag='Aggrenox:BAAALgAECgYJCgAAAA==.',
Ai='Aisathya:BAAALgAECgYJCwAAAA==.',
Ak='Akiza:BAAALgAECgEJAQAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgADCgUJBQAAAA==.Albina:BAAALgAECgEJAQAAAA==.Aldelvir:BAAALgAECgIJAgABLgAECgYJFQADAEoSAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAAALgAECgcJDgAAAA==.Alzhimers:BAAALgAECgIJAwAAAA==.',
Am='Amberscale:BAABLgAECn8dAAIEAAgJBxztAQBIAgAEAAgJBxztAQBIAgAAAA==.Amyrrin:BAAALgAECgYJCwAAAA==.',
An='Ancientiur:BAAALgAECggJDQAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAAALgAECgYJDAAAAA==.Angrulus:BAABLgAECn8YAAIFAAcJSRUpCwC4AQAFAAcJSRUpCwC4AQAAAA==.Animal:BAAALgADCgUJBQAAAA==.Animlshiftr:BAAALgAECgcJDgAAAA==.',
Ap='Apollo:BAAALgAECgYJCQAAAA==.',
Ar='Aradunn:BAACLgAFFH8FAAIGAAIJ0iDFCQCsAAAGAAIJ0iDFCQCsAAAuAAQKfxkAAwYACAlWIvgGAAQDAAYACAlWIvgGAAQDAAcAAQncBxktADIAAAAA.Araedis:BAAALgAECgcJDAAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGQAIAOMIAA==.Artheren:BAAALgAECgIJAgAAAA==.Aryllyn:BAAALgADCgYJDAAAAA==.',
As='Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgADCgMJAwAAAA==.',
At='Atharion:BAAALgAECgYJEQAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJAwAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAAALgAECgUJCAAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAAALgAECgMJAwAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAAALgAECgYJDQAAAA==.Balinor:BAAALgAECgQJCAABLgAECgcJEQACAAAAAA==.',
Be='Bearett:BAAALgAECgYJDgAAAA==.Beefynacho:BAAALgADCgMJAwAAAA==.Belyhell:BAAALgADCgUJBQAAAA==.Belymoon:BAAALgAECgkJBgAAAA==.Bernd:BAAALgAECgYJDwAAAA==.Beörn:BAAALgAECgYJEQAAAA==.',
Bl='Blackgrinn:BAAALgAECgYJEAAAAA==.Blackkgrin:BAAALgADCgEJAQAAAA==.Blasphemous:BAAALgAECgUJCgAAAA==.Blasé:BAABLgAECn8nAAMJAAYJ2CR7BgALAgAJAAYJ2CR7BgALAgAKAAEJAACSXABZAAAAAA==.Blazéoné:BAAALgAECgEJAQAAAA==.',
Bo='Bobo:BAAALgAECgUJDwAAAA==.Bobrossx:BAACLgAFFH8FAAMFAAIJ7xKxDwCfAAALAAIJ7xJlHQCgAAAFAAIJMAixDwCfAAAuAAQKfyYABAsACAmoH+MNANICAAsACAkUHuMNANICAAwABgnpHW4DAMkBAAUAAglkHn4qALcAAAAA.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAINAAcJdR3QSAAZAgANAAcJdR3QSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwANAHUdAA==.Bootypls:BAACLgAFFH8IAAMOAAMJSg2SDgCAAAAOAAIJBwySDgCAAAANAAEJzw/HUgBQAAAuAAQKfxwAAw4ACAnHGWgVALwBAA4ACAlzF2gVALwBAA0AAwm3IXm/AAQBAAAA.',
Br='Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8UAAINAAcJbRh9FwBWAQANAAcJbRh9FwBWAQAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Butschi:BAAALgAECgkJBgAAAA==.',
Bw='Bwca:BAAALgAECggJDQABLgAFFAEJAQACAAAAAA==.',
Ca='Caine:BAAALgAECgcJEQAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgQJBAABLgAECgYJDgACAAAAAA==.Casey:BAAALgAECgMJAwAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAAALgAECgYJDgAAAA==.',
Ce='Cellina:BAAALgAECgYJBgAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.',
Ch='Chiman:BAAALgAECgUJBwAAAA==.Chronophage:BAAALgAECgQJBAAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Cl='Classá:BAABLgAECn8iAAMPAAgJPyA6DgC5AgAPAAcJ5yM6DgC5AgAQAAUJPB7BRgCHAQAAAA==.Clawz:BAAALgADCgYJBgABLgAECgMJBAACAAAAAA==.',
Co='Codedd:BAAALgAECgUJCgAAAA==.Commit:BAAALgAECgYJCQAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAAALgAECgYJDwABLgAECggJEwACAAAAAA==.',
Cr='Crispìn:BAAALgAECgEJAQAAAA==.Crossbones:BAAALgADCgUJCgAAAA==.Crue:BAAALgAECgMJAwAAAA==.',
Cu='Curthar:BAAALgAECgMJBAAAAA==.',
Cy='Cyndee:BAABLgAECn8aAAIRAAcJlg4ZCwBvAQARAAcJlg4ZCwBvAQAAAA==.Cynnafrost:BAAALgADCgIJAgAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn8WAAILAAcJxx0tAgC7AQALAAcJxx0tAgC7AQAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgADCgYJBgABLgAECgYJDQACAAAAAA==.Dankmonk:BAAALgAECgUJCAAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAAALgAECgcJEAAAAA==.Darklasminth:BAAALgAECgIJAgAAAA==.Darthwang:BAABLgAECn8bAAIJAAYJ3RjkWgC3AQAJAAYJ3RjkWgC3AQAAAA==.Dartos:BAABLgAECn8iAAINAAgJmyKeFAAAAwANAAgJmyKeFAAAAwAAAA==.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAUJBwASAGMRAA==.Deepfister:BAABLgAECn8bAAITAAgJbB+UAQCSAgATAAgJbB+UAQCSAgAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECggJGwATAGwfAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgADCggJCQAAAA==.Diluvium:BAAALgAECgYJEQAAAA==.',
Dj='Djpleasant:BAABLgAECn8gAAISAAgJrx1MBQBgAgASAAgJrx1MBQBgAgAAAA==.',
Dk='Dktelmtwo:BAAALgADCgMJAwAAAA==.',
Do='Doneisha:BAAALgAECgIJBQAAAA==.Dontcare:BAAALgADCgYJBgAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAAALgAECgUJDQAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAAALgAECggJEAAAAA==.',
Du='Dunzledorf:BAAALgADCgYJBgAAAA==.',
Dy='Dynammes:BAAALgAECgYJCgABLgAECgcJGwAEAPEVAA==.',
Ea='Eatmorpizza:BAAALgADCgkJIwAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAAALgAFFAEJAQAAAA==.',
El='Elementals:BAAALgAECgYJDAAAAA==.Elixera:BAAALgADCgUJBQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.',
Ep='Epia:BAAALgAECggJEAAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Essaila:BAAALgAECgYJCgAAAA==.',
Et='Etheo:BAAALgADCgYJCAAAAA==.Etherwalker:BAAALgAECgYJDwAAAA==.',
Ev='Evocati:BAAALgAECgQJCwABLgAFFAMJBgAUAFsYAA==.Evoka:BAABLgAECn8XAAMVAAYJEyDqDAAMAgAVAAYJEyDqDAAMAgAEAAMJcRZ/HABXAAAAAA==.',
Ex='Excision:BAAALgAECgYJDgAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Ez='Ezindrozath:BAAALgAECgYJDgAAAA==.',
Fa='Fahbio:BAAALgAECgYJCgAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAAALgAECgUJDgAAAA==.',
Fi='Fishdish:BAAALgADCgkJCgAAAA==.Fistsmither:BAAALgADCgQJBAABLgAECgQJDAACAAAAAA==.Fivevolts:BAAALgAECgYJDwAAAA==.',
Fl='Flailuid:BAAALgAECgQJBgAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgEJAgAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgADCgkJEQAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAABLgAECn8fAAIWAAgJMxpsAwDlAQAWAAgJMxpsAwDlAQAAAA==.Frostdeeps:BAAALgAECgYJEgAAAA==.Frozarke:BAABLgAECn8VAAIEAAYJ9Q7sMgAzAQAEAAYJ9Q7sMgAzAQAAAA==.',
Fu='Fudd:BAAALgAECgYJCgAAAA==.Fupa:BAAALgAECgMJBAAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAAALgAECgcJEgAAAA==.',
Ge='Genius:BAAALgAECgYJDwAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAAALgAECgYJEgAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnomad:BAAALgAECgUJCAAAAA==.',
Go='Gouge:BAAALgAECggJIgAAAQ==.',
Gr='Griffynshu:BAAALgAECgYJCwAAAA==.Griz:BAAALgADCgYJBgAAAA==.Grunewald:BAABLgAECn8aAAIFAAYJygZ7cAAWAQAFAAYJygZ7cAAWAQAAAA==.',
Gu='Gula:BAABLgAECn8bAAMXAAYJ0ho+CQCxAQAXAAYJHRc+CQCxAQAJAAYJExnMGQBFAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAABLgAECn8VAAMYAAcJrROKIADUAQAYAAcJrROKIADUAQABAAQJ3iESMAAfAQAAAA==.Hando:BAAALgADCgYJBgAAAA==.Hattock:BAAALgADCgcJFQAAAA==.',
He='Heavyshlump:BAABLgAECn8XAAIZAAgJyw/8BQCpAQAZAAgJyw/8BQCpAQAAAA==.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIaAAgJ/xp+AwDjAQAaAAgJ/xp+AwDjAQAAAA==.Heimdall:BAAALgAECgUJBgAAAA==.Hellavva:BAAALgAECgMJAwAAAA==.Hench:BAAALgADCgIJAgAAAA==.Henchling:BAABLgAECn8kAAIGAAkJGyAnCQDkAgAGAAkJGyAnCQDkAgAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAAALgAECgYJEgAAAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAaAP8aAA==.Holexios:BAAALgAECgQJBgABLgAECgUJBwACAAAAAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAQAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAAALgAECgQJBAAAAA==.Hotsteve:BAAALgAECgQJBAAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgcJDgAAAA==.Icyscorcher:BAAALgAECggJEQAAAA==.',
Im='Immeira:BAAALgAECgUJCgAAAA==.',
Ja='Jackheals:BAABLgAECn8dAAMQAAYJ8h9lJwAYAgAQAAYJ8h9lJwAYAgAPAAEJ2QG+jwAbAAAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinphoenix:BAAALgAECgYJEAAAAA==.',
Jo='Jobin:BAAALgAECgcJEgAAAA==.Journei:BAAALgAECgQJBwAAAA==.',
Ju='Judging:BAAALgAECgYJDwAAAA==.',
Ka='Kaiduo:BAAALgADCgEJAQAAAA==.Kalmas:BAAALgAFFAEJAgAAAA==.',
Ke='Kegz:BAAALgADCgcJBwAAAA==.Kelendrian:BAAALgADCgEJAQAAAA==.Kellayna:BAAALgAECgIJAgAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Kezix:BAABLgAECn8aAAIJAAgJqQ0REgCAAQAJAAgJqQ0REgCAAQAAAA==.',
Kh='Kharigosa:BAAALgADCgcJBwABLgAECgMJAwACAAAAAA==.',
Ki='Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8gAAQEAAgJRhGYIwChAQAEAAgJhA+YIwChAQAVAAIJ1AtvCQA/AAAbAAEJwQFmTgAiAAAAAA==.',
Kl='Klerik:BAABLgAECn8dAAQJAAgJ2B9HBgAPAgAJAAcJFR9HBgAPAgAKAAIJKRJfTACIAAAXAAEJbiQOBgBuAAAAAA==.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgQJBgAAAA==.Koragg:BAACLgAFFH8IAAIOAAQJDhuoBQBDAQAOAAQJDhuoBQBDAQAuAAQKfyQAAg4ACAkfIisEAA0DAA4ACAkfIisEAA0DAAAA.Kore:BAAALgAECgYJCgAAAA==.Kozarke:BAAALgAECgYJDwAAAA==.',
Kp='Kpop:BAABLgAECn8VAAIcAAcJZR4vBwAWAgAcAAcJZR4vBwAWAgABLgAECggJFwAZAMsPAA==.',
Kr='Krissia:BAABLgAECn8WAAINAAgJIhZYQwAsAgANAAgJIhZYQwAsAgAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
['Kí']='Kítsuñe:BAAALgADCgcJBwAAAA==.',
['Kî']='Kîn:BAAALgAECgYJCgAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8ZAAIdAAYJ4hNfLwCFAQAdAAYJ4hNfLwCFAQAAAA==.Lalipop:BAAALgAECgYJCgAAAA==.Landroval:BAAALgAECgYJDwAAAA==.Lauma:BAAALgAFFAEJAQAAAA==.Lawson:BAAALgAECgcJDAAAAA==.',
Le='Lelora:BAAALgAECgQJBAAAAA==.Lenthaden:BAAALgAECgcJEQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgADCgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lilflame:BAAALgADCgUJCAAAAA==.Lio:BAAALgADCggJGQAAAA==.Lissetteliz:BAAALgADCgYJCQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgMJAwAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.',
Ly='Lyreth:BAABLgAECn8YAAIPAAYJ8BGhDgAIAQAPAAYJ8BGhDgAIAQAAAA==.',
Ma='Madax:BAAALgAECgcJEQABLgAECgcJGwAEAPEVAA==.Mageymutt:BAACLgAFFH8HAAISAAUJYxFHDAC7AQASAAUJYxFHDAC7AQAuAAQKfyQAAxIACAlgIJ0lANwCABIACAlgIJ0lANwCAB4AAwkmCyAUAIQAAAAA.Maggidabeast:BAAALgAECgYJCgAAAA==.Maison:BAAALgAECgQJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAABLgAECn8iAAIfAAgJzheIAwBPAgAfAAgJzheIAwBPAgAAAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAABLgAECn8cAAISAAcJ9BsiTwBKAgASAAcJ9BsiTwBKAgAAAA==.',
Mi='Micalknight:BAAALgADCgQJBQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAECggJIgAPAD8gAA==.Missbehaving:BAAALgAECgYJDQAAAA==.',
Mo='Morefire:BAAALgAECgIJAgABLgAECgYJDAACAAAAAA==.Mosmos:BAAALgADCgUJDAAAAA==.',
Mu='Muddslinger:BAAALgAECgUJBwAAAA==.Mumra:BAAALgAECgYJDgAAAA==.',
My='Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nalesean:BAAALgADCgkJEwAAAA==.Nanaki:BAABLgAECn8VAAIbAAgJxB3wBgDQAgAbAAgJxB3wBgDQAgAAAA==.Nannette:BAAALgAECgQJCAAAAA==.Nappe:BAAALgADCgcJBwABLgAECgYJDAACAAAAAA==.Narag:BAAALgAECgcJEAAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJAgAAAA==.Netanyahoo:BAAALgAECgQJBAAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAAALgAECgYJDgAAAA==.',
Ni='Ninex:BAABLgAECn8VAAIgAAYJNCPSGABMAgAgAAYJNCPSGABMAgAAAA==.Ninisina:BAABLgAECn8UAAMGAAUJBx3iNgCnAQAGAAUJBx3iNgCnAQAHAAEJ7wOCLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgADCgEJAgAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Nowon:BAAALgAECgYJCwAAAA==.',
Nu='Nudream:BAAALgAECgYJBwAAAA==.',
Ny='Nybors:BAAALgADCgUJBQAAAA==.',
['Nö']='Nörse:BAAALgAECgUJDQAAAA==.',
Ol='Oldjerry:BAAALgAECgQJDAAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Op='Opalyte:BAAALgAECgYJCQAAAA==.',
Or='Orichalcum:BAAALgAECgcJEQAAAA==.Orphiee:BAAALgADCgkJEgAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAECggJIAAAAQ==.',
Pa='Pakoros:BAABLgAECn8bAAMGAAgJ3wyaCwCEAQAGAAgJ3wyaCwCEAQAhAAQJBwppagCZAAAAAA==.Pallyfreak:BAAALgADCgcJDgAAAA==.',
Pe='Peachy:BAAALgADCgEJAgABLgAECgYJDwACAAAAAA==.Penderin:BAAALgADCgYJBgABLgAECgYJFQADAEoSAA==.Pensham:BAAALgADCgIJAgABLgAECgYJFQADAEoSAA==.Perlindree:BAAALgAECgYJEwAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8XAAIFAAYJeBCvHwADAQAFAAYJeBCvHwADAQAAAA==.',
Ph='Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAAALgAECgYJDQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgACAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAAALgAECgYJCAAAAA==.Poppers:BAAALgADCgMJAwAAAA==.',
Pr='Preacharond:BAABLgAECn8pAAIYAAgJnhhBFQBCAgAYAAgJnhhBFQBCAgAAAA==.Promir:BAAALgAECgQJBwAAAA==.',
Pu='Purdie:BAAALgAECgQJBAABLgAECgYJDgACAAAAAA==.',
Qe='Qeesa:BAAALgADCgYJBgAAAA==.',
Ra='Raeliene:BAAALgAECgYJCgAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAAALgAECgcJEQAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Relaxnerdlol:BAAALgAECgEJAQAAAA==.Renew:BAAALgAECgIJAgAAAA==.Renix:BAABLgAECn8bAAMhAAgJxBuNFQBvAgAhAAgJxBuNFQBvAgAHAAEJdQsSLQAyAAAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Ri='Riverah:BAAALgADCgcJDgAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAAALgAECgQJBwABLgAECggJHgASALQVAA==.',
Ry='Ryyah:BAAALgAECgYJEAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAECgMJBwAAAA==.',
Sa='Saetyl:BAAALgAECgYJDQAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgADCgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQACAAAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semii:BAAALgAECgIJAgAAAA==.Serkesul:BAAALgAECgYJEwAAAA==.Sevinas:BAAALgAECgMJBAAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shamallamá:BAAALgADCgkJCgAAAA==.Shamyou:BAAALgAECgcJDAAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAAALgAECgYJCwABLgAECggJFwAZAMsPAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8GAAIGAAMJ4CRAAwBLAQAGAAMJ4CRAAwBLAQAuAAQKfyQAAgYACAkGJjQDAEcDAAYACAkGJjQDAEcDAAAA.',
Si='Silvey:BAAALgAECgYJDwAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skeletorque:BAAALgAECgQJBwAAAA==.Skully:BAAALgADCgEJAQAAAA==.Skyylorne:BAAALgAECgIJAgAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgAAAA==.',
Sm='Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snowfawn:BAAALgAECgUJCQAAAA==.Snusnurae:BAAALgAECgMJAwAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECggJFQAbAMQdAA==.',
Sp='Spanana:BAABLgAFFH8KAAINAAQJThKjFQBNAQANAAQJThKjFQBNAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8OAAISAAYJsyRWBgD6AQASAAYJsyRWBgD6AQAuAAQKfxcAAhIACAnbIQ8dAAEDABIACAnbIQ8dAAEDAAAA.Splishsplásh:BAAALgAECgMJBAAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAAALgAECgYJCAAAAA==.',
St='Starzia:BAAALgAECgcJEQAAAA==.Stupidtree:BAABLgAECn8WAAIQAAcJkiOBGQBsAgAQAAcJkiOBGQBsAgAAAA==.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAAALgAECgYJDwAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJAwABLgAECgMJBAACAAAAAA==.Swiftblossom:BAAALgADCgcJFAAAAA==.',
Sy='Sylvanex:BAAALgADCgcJBwAAAA==.',
Ta='Taffbones:BAAALgAECgUJBwAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgQJBQABLgAECgUJBwACAAAAAA==.Talarus:BAAALgAECggJCQAAAA==.Tanadria:BAAALgAECgUJCgAAAA==.Tangerene:BAABLgAECn8YAAMBAAgJTgUHLgAuAQABAAcJ3wUHLgAuAQAdAAYJFAIFXgC6AAAAAA==.Tapioca:BAABLgAECn8VAAIFAAgJQh6yDADaAgAFAAgJQh6yDADaAgAAAA==.Tashyr:BAAALgADCgUJCAAAAA==.',
Te='Telm:BAAALgAECgYJEgAAAA==.Tentilious:BAAALgADCgUJBQAAAA==.',
Th='Thadeusputz:BAAALgADCgYJBgAAAA==.Thaÿne:BAAALgAECgYJBwAAAA==.Thebestpally:BAABLgAECn8cAAMiAAcJixesAwCNAQAiAAcJixesAwCNAQAUAAQJqAn15ADEAAAAAA==.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAAALgAECgYJCgAAAA==.Tidds:BAAALgAECgYJEgAAAA==.',
To='Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8KAAIGAAYJkhOKAQDmAQAGAAYJkhOKAQDmAQAuAAQKfxkAAgYACAl8I2EHAP4CAAYACAl8I2EHAP4CAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAABLgAECn8qAAMEAAgJFRfXFgAfAgAEAAgJFRfXFgAfAgAVAAMJJgSaMwB3AAAAAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
['Tã']='Tãpioca:BAAALgAECgEJAgABLgAECggJFQAFAEIeAA==.',
Uj='Ujio:BAAALgAECgYJCgAAAA==.',
Un='Unify:BAAALgADCgMJBAAAAA==.',
Us='Usdaprime:BAAALgAECgEJAgAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAECgYJEwABLgAECggJIAACAAAAAQ==.',
Va='Vaden:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAABLgAECn8bAAMEAAcJ8RVKBwB8AQAEAAcJ5RRKBwB8AQAVAAIJ2gqkOQBMAAAAAA==.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAECggJGwAUANYdAA==.Vanaheim:BAAALgADCgkJFgAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Varala:BAAALgADCgkJFgAAAA==.',
Ve='Vel:BAACLgAFFH8KAAINAAQJQRrVCwAUAQANAAQJQRrVCwAUAQAuAAQKfyYAAg0ACAnZJJoKAEcDAA0ACAnZJJoKAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Veldh:BAAALgADCgQJBwABLgAFFAQJCgANAEEaAA==.Velýth:BAAALgAECgUJDAABLgAFFAQJCgANAEEaAA==.Veritas:BAAALgAECgEJAwAAAA==.Vexxius:BAAALgAFFAEJAQAAAA==.',
Vo='Vorathis:BAAALgADCgEJAQABLgAFFAIJBQAGANIgAA==.',
Vy='Vylana:BAAALgADCggJHgABLgAECggJHAAUACoaAA==.',
['Và']='Vàlkyrie:BAABLgAECn8bAAIUAAgJ1h13IgCgAgAUAAgJ1h13IgCgAgAAAA==.',
Wa='Wack:BAAALgAECgYJBgAAAA==.Wanderfoot:BAAALgAECgMJAwAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8UAAIJAAcJbxDzZwCUAQAJAAcJbxDzZwCUAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8ZAAIIAAgJ4wgrIwAlAQAIAAgJ4wgrIwAlAQAAAA==.Wavestabe:BAABLgAECn8VAAIDAAYJShLFFQBbAQADAAYJShLFFQBbAQAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgYJFQADAEoSAA==.',
Wr='Wreck:BAAALgAECgYJEQAAAA==.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.',
Ya='Yayrri:BAAALgAECgYJDwAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zathamax:BAAALgAECgQJCAAAAA==.Zavya:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zephyrmars:BAAALgADCgIJAgAAAA==.Zextron:BAABLgAECn8VAAIjAAYJjxCeCAAaAQAjAAYJjxCeCAAaAQAAAA==.',
Zi='Ziaya:BAAALgAECgYJCgAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgEJAgABLgAECgUJBwACAAAAAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAAALgAECgcJEQAAAA==.',
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

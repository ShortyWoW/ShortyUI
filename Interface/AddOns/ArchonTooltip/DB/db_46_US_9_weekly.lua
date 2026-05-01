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

local lookup = {'Warlock-Destruction','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Priest-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Shaman-Enhancement','Paladin-Retribution','Monk-Mistweaver','Paladin-Holy','Evoker-Augmentation','DemonHunter-Havoc','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Feral','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abyssia:BAAALgAFFAEJAQAAAA==.',
Ac='Acupuncher:BAAALgADCgEJAgAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAAALgAECgYJDAAAAA==.',
Ai='Airius:BAAALgAECgcJBwAAAA==.Airmed:BAAALgAECgQJBQAAAA==.',
Al='Alcha:BAABLgAECn8ZAAIBAAcJmxrMAgDWAQABAAcJmxrMAgDWAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgcJGQABAJsaAA==.Alenndar:BAAALgAECgYJBgAAAA==.Alexdaddario:BAABLgAECn8cAAMCAAYJIyHvHgAIAgACAAYJIyHvHgAIAgADAAIJ2giBGwBFAAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECgcJGQABAJsaAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8aAAMEAAcJ4hH+OgB9AQAEAAcJ4hH+OgB9AQAFAAEJsgUOIAAvAAAAAA==.Amaridia:BAAALgAECgYJBgAAAA==.Amos:BAAALgAECgcJCwABLgAECgcJGgAGABgUAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8UAAIHAAYJRCWQAgAQAgAHAAYJRCWQAgAQAgAAAA==.Annalease:BAAALgAECgIJAgAAAA==.Anticlimax:BAABLgAECn8aAAIIAAcJbxNWIQBrAQAIAAcJbxNWIQBrAQAAAA==.Antipathy:BAAALgADCgIJAgAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ap='Apparition:BAABLgAECn8VAAMJAAgJWRL3DAC6AQAJAAgJWRL3DAC6AQAKAAQJ4glzUgB/AAAAAA==.Apprentice:BAABLgAECn8jAAIEAAgJoCNVFQAoAwAEAAgJoCNVFQAoAwAAAA==.',
Ar='Argonar:BAAALgAECgcJEQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAABLgAECn8aAAILAAgJ6BxtFgBiAgALAAgJ6BxtFgBiAgAAAA==.',
At='Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAABLgAECn8gAAILAAkJIw+yFQC7AQALAAkJIw+yFQC7AQAAAA==.',
Av='Avdol:BAAALgAECgcJDwABLgAFFAUJCwAMAIsXAA==.Avienndha:BAABLgAECn8UAAIHAAYJFRVYBwBGAQAHAAYJFRVYBwBGAQAAAA==.',
Aw='Awake:BAAALgAECgYJDAAAAA==.',
Az='Azgrunga:BAABLgAECn8nAAINAAgJdBxsBwA4AgANAAgJdBxsBwA4AgAAAA==.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgADCgcJFwAAAA==.Benderbrod:BAAALgADCgkJCQAAAA==.Beornwildlaw:BAAALgADCgcJAgAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQAAAA==.',
Bo='Bobbytofva:BAABLgAECn8YAAINAAcJahl1OQDBAQANAAcJahl1OQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8bAAILAAgJKBkrDAAoAgALAAgJKBkrDAAoAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBAAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8cAAIOAAgJNSAtBQDtAgAOAAgJNSAtBQDtAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJBgAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgADCggJCgAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAAMAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8FAAILAAMJlhIWFwDSAAALAAMJlhIWFwDSAAAuAAQKfyMAAwsACAkAGuMRAOIBAAsACAkAGuMRAOIBAA8ABQkoFAoiAA0BAAAA.Cheesefries:BAAALgAECgYJEgAAAA==.Chereth:BAABLgAECn8WAAIQAAcJhBJpSACBAQAQAAcJhBJpSACBAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8WAAMRAAgJzwyqQAAWAQARAAcJjAmqQAAWAQASAAIJPxIJOAB5AAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAAALgAECgcJEgAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgYJBgATAAAAAA==.Cokegirll:BAAALgAECgQJBgAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJGgAUAI8VAA==.Creamie:BAABLgAECn8VAAISAAcJ/xl5EACOAQASAAcJ/xl5EACOAQABLgAECggJGgAUAI8VAA==.Creamish:BAABLgAECn8aAAIUAAgJjxV2BADnAQAUAAgJjxV2BADnAQAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAAALgAECgcJEgAAAA==.Cryptos:BAAALgAECgQJBgAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAAALgAECgQJBgAAAA==.',
Da='Dacrus:BAAALgAECgEJBAAAAA==.Dalsen:BAABLgAECn8ZAAIDAAgJygsPDgDXAAADAAgJygsPDgDXAAAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECggJGQADAMoLAA==.Damnadin:BAAALgAECgcJCwAAAA==.Dankchop:BAAALgAECgcJEgAAAA==.Daredevil:BAAALgADCgEJAQABLgADCgYJBgATAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAQABLgAECgYJDAATAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAAALgAECgYJEgAAAA==.Deskpop:BAAALgADCgYJBwAAAA==.Dewberry:BAAALgAECgEJAQAAAA==.Deáth:BAAALgAECgMJBgAAAA==.',
Di='Diabolikal:BAAALgAECgQJBwAAAA==.Dill:BAABLgAECn8wAAINAAkJyCHXAAAcAwANAAkJyCHXAAAcAwAAAA==.Diomedus:BAAALgADCggJDgAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgADCgUJCQABLgAECgMJAwATAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgEJAQAAAA==.Drùna:BAABLgAECn8YAAICAAcJLgynIgDqAAACAAcJLgynIgDqAAAAAA==.',
Du='Duifean:BAAALgADCgMJAwAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolykal:BAAALgAECgQJBAABLgAECgQJBwATAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIVAAkJJBJVGgDsAQAVAAkJJBJVGgDsAQAAAA==.Elly:BAAALgADCgYJBgAAAA==.Elsharion:BAAALgAECgYJDQABLgAFFAUJEwAWADIeAA==.Elsharius:BAAALgAECgQJBAABLgAFFAUJEwAWADIeAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAUJEwAWADIeAA==.Elshie:BAACLgAFFH8TAAIWAAUJMh7PBACyAQAWAAUJMh7PBACyAQAuAAQKfxUAAhYACQkJHl0NAH4CABYACQkJHl0NAH4CAAAA.',
Em='Emachine:BAAALgAFFAMJBAABLgAFFAUJCwAMAIsXAA==.',
Es='Eskyxy:BAAALgAECgYJCQAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn8mAAIQAAgJmResHwBEAgAQAAgJmResHwBEAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8TAAIRAAUJayI2AQDRAQARAAUJayI2AQDRAQAuAAQKfzEAAhEACQkAJWgAAFIDABEACQkAJWgAAFIDAAAA.',
Fe='Felcollins:BAAALgAECgYJDQAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fill:BAABLgAECn8ZAAIUAAYJFSQ2CABfAgAUAAYJFSQ2CABfAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAAALgAECgYJDwAAAA==.',
Fr='Frags:BAABLgAECn8iAAIXAAgJphbtEwC3AQAXAAgJphbtEwC3AQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECggJCwATAAAAAA==.',
Ga='Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgADCgkJEAAAAA==.',
Ge='Genjyosanzo:BAAALgAECgYJEQAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8jAAISAAgJXiIbCAAEAwASAAgJXiIbCAAEAwAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAQJCgAYAAsPAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDAAAAA==.Grokdepaly:BAAALgAECgMJAwAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJAwAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBAAAAA==.',
Hi='Highfeather:BAABLgAECn8ZAAINAAYJJw8jIAA0AQANAAYJJw8jIAA0AQAAAA==.Hilazy:BAAALgAECgYJDQAAAA==.Hiping:BAAALgAECgYJCAAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAECgYJDAAAAA==.Holyphok:BAABLgAECn8WAAIJAAcJIhGlEACEAQAJAAcJIhGlEACEAQAAAA==.Holysheet:BAAALgAFFAEJAQAAAA==.Hort:BAAALgAECgYJDQAAAA==.Hotdog:BAAALgAECgYJBgAAAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQAAAA==.',
Hy='Hyla:BAAALgAECggJEgAAAA==.',
Ib='Ibackstab:BAAALgADCgcJEAAAAA==.',
Ic='Icestormy:BAABLgAECn8VAAIEAAYJVgSAhwDEAAAEAAYJVgSAhwDEAAAAAA==.',
Ih='Ihasaface:BAAALgAECgUJCQAAAA==.Ihavenofutur:BAAALgAECgQJBQAAAA==.',
Il='Illari:BAAALgAECgMJCAAAAA==.Illidantwo:BAACLgAFFH8QAAIZAAUJXxtkAQCYAQAZAAUJXxtkAQCYAQAuAAQKfyMAAhkACQn2IhAEADoDABkACQn2IhAEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAAALgAECgcJEQAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgADCgQJBAAAAA==.',
It='Italianapee:BAAALgAECgcJDgAAAA==.',
Ja='Jaboo:BAAALgAECgYJCwABLgAECggJHgAIABMcAA==.Jabu:BAAALgAECgEJAQABLgAECggJHgAIABMcAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAAALgAECgYJDgAAAA==.',
Je='Jenasys:BAAALgADCgkJCQAAAA==.Jenstonedart:BAAALgAECggJEgAAAA==.Jeryeth:BAABLgAECn8YAAIOAAgJMByNCACXAgAOAAgJMByNCACXAgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8SAAIaAAQJ+CFxAACaAQAaAAQJ+CFxAACaAQAuAAQKfykAAhoACAk9Jt0AAGgDABoACAk9Jt0AAGgDAAAA.Karenuwu:BAAALgAECggJDQAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJKwAVAH4hAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kenslee:BAAALgADCgEJAQAAAA==.',
Kh='Khanzu:BAAALgAECgYJEwAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJDAATAAAAAA==.Kiwí:BAABLgAECn8aAAMFAAcJSBuVCABqAQAFAAUJAh2VCABqAQAEAAUJxQ7+PgGDAAAAAA==.',
Kr='Krasavice:BAABLgAECn8bAAIbAAcJuiP/DgAgAgAbAAcJuiP/DgAgAgAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAAALgAECgYJEwAAAA==.Lavish:BAACLgAFFH8KAAIIAAQJKQtyIwDXAAAIAAQJKQtyIwDXAAAuAAQKfxkAAggACAmfGfEqAFQCAAgACAmfGfEqAFQCAAAA.',
Le='Leathal:BAAALgAECgcJEgAAAA==.Lemurshoes:BAAALgAECgYJBgAAAA==.Lena:BAABLgAECn8iAAIbAAgJvyOLAwDQAgAbAAgJvyOLAwDQAgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgADCgcJCQAAAA==.Leøn:BAABLgAECn8YAAIcAAgJFx1pJACsAgAcAAgJFx1pJACsAgAAAA==.',
Li='Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8UAAILAAYJqx+uEADwAQALAAYJqx+uEADwAQAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJDQATAAAAAA==.',
Lu='Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECgUJCwAAAA==.Lusat:BAAALgAECgEJAQAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAABLgAECn8qAAIdAAgJSB0sBQC+AgAdAAgJSB0sBQC+AgAAAA==.',
['Lü']='Lüna:BAABLgAECn8WAAIeAAYJYgTeEADAAAAeAAYJYgTeEADAAAAAAA==.',
Ma='Macewindu:BAAALgAECgEJAgAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAUJCwAMAIsXAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn8rAAIVAAkJfiGaAwDpAgAVAAkJfiGaAwDpAgAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAAALgAECgQJBgAAAA==.Maximus:BAABLgAECn8UAAIVAAgJxQmiPQBRAQAVAAgJxQmiPQBRAQAAAA==.',
Me='Mellowlizard:BAABLgAFFH8LAAIMAAUJixeMCACfAQAMAAUJixeMCACfAQAAAA==.Metamarie:BAAALgADCgEJAQAAAA==.Metuss:BAAALgAECgcJDQAAAA==.',
Mi='Mira:BAABLgAECn8aAAIbAAcJ3BKwMgBGAQAbAAcJ3BKwMgBGAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgAAAA==.Mkicon:BAAALgAECgYJEwAAAA==.Mkultra:BAABLgAECn8YAAMfAAcJbB7kDABCAQAcAAcJZRltbgCtAQAfAAYJ6h3kDABCAQAAAA==.',
Mo='Mogmoog:BAAALgAECgYJBwAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8UAAIgAAYJ2hXOBQBfAQAgAAYJ2hXOBQBfAQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8dAAMQAAgJbwgYMQAXAQAQAAgJbwgYMQAXAQACAAIJDwJeegA9AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn8aAAMMAAgJrxSFVADKAQAMAAcJzRWFVADKAQABAAIJ/w20VABwAAAAAA==.',
Mu='Mudget:BAACLgAFFH8fAAMBAAgJuRqPAAA9AgABAAYJDBiPAAA9AgAMAAcJPxkxBADcAQAuAAQKfzQAAwwACQkuJocNAA4DAAwABwkTJocNAA4DAAEABQl1JpcIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECggJJAALAOMVAA==.Multanni:BAABLgAECn8ZAAIPAAcJvhQ0FgBjAQAPAAcJvhQ0FgBjAQAAAA==.',
My='Myonecrosis:BAAALgAECgYJDgAAAA==.',
Na='Nakrog:BAAALgADCgIJAgAAAA==.Napster:BAABLgAECn8ZAAIXAAcJoSAbGABRAgAXAAcJoSAbGABRAgAAAA==.Nasa:BAACLgAFFH8QAAIRAAUJ+xQNBgAfAQARAAUJ+xQNBgAfAQAuAAQKfxsAAhEACQmZHu8LALwCABEACQmZHu8LALwCAAAA.Nazarov:BAAALgADCgQJBwAAAA==.',
Ne='Nellarixi:BAABLgAECn8fAAIKAAgJzhQXGgAPAgAKAAgJzhQXGgAPAgAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8RAAMYAAYJoRftBQCgAQAYAAYJoRftBQCgAQAhAAIJpgnoBgCgAAAuAAQKfz8AAyEACAkXIr0DAN4CACEACAklIL0DAN4CABgACAnoH00KANECAAAA.',
No='Nomaa:BAAALgAECgYJEwAAAA==.Nomäd:BAAALgAECgYJDQAAAA==.Nosneb:BAAALgAECgEJAgAAAA==.',
Nr='Nramar:BAAALgADCgYJBwAAAA==.',
Nu='Nurgle:BAAALgADCgYJDAAAAA==.',
Ny='Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAAALgAECgYJEQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgEJAgAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJCwAAAA==.',
Oi='Oisin:BAABLgAECn8cAAQDAAcJQQTaFgBlAAADAAcJGgTaFgBlAAACAAEJ4gN0iQAmAAAdAAEJkQM2OQAkAAAAAA==.',
Ok='Okko:BAAALgADCgEJAQAAAA==.Oktoberfest:BAAALgAECggJCwAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAAALgAECgcJEgAAAA==.',
Ph='Phrash:BAAALgAECgIJBAABLgAECgYJGQAUABUkAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAECgcJBwAAAA==.',
Po='Pocahontas:BAABLgAECn8aAAIGAAcJGBTrFABpAQAGAAcJGBTrFABpAQAAAA==.Poky:BAAALgADCgUJBgABLgADCgYJBgATAAAAAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAAALgAECgUJCQAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.',
Qu='Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8GAAIbAAMJaxmpFAAYAQAbAAMJaxmpFAAYAQAuAAQKfyIAAhsABwk8I1YRAK4CABsABwk8I1YRAK4CAAAA.Racker:BAAALgAECgUJBQAAAA==.Rainfallen:BAAALgAECgYJBgAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBAAAAA==.',
Re='Rellein:BAAALgAECgYJDQAAAA==.Rengar:BAABLgAECn8UAAMNAAUJ7xnCSgB6AQANAAUJ7xnCSgB6AQAOAAQJUxA8MADCAAAAAA==.Rengots:BAAALgAECgUJCQAAAA==.Renne:BAABLgAECn8jAAIZAAcJxRWgCwCCAQAZAAcJxRWgCwCCAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgUJCwAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgQJBQAAAA==.Rokkoz:BAABLgAECn8aAAMCAAcJshRXGQAyAQACAAcJshRXGQAyAQADAAQJhQhBKgBRAAAAAA==.Rookiestar:BAAALgAECgEJAgAAAA==.',
Ru='Rumí:BAAALgAECgcJEwAAAA==.',
['Rí']='Ríta:BAAALgAECgYJEQAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Sarnt:BAAALgAECgIJAgAAAA==.Sass:BAABLgAECn8gAAICAAgJ9R69BABqAgACAAgJ9R69BABqAgAAAA==.Satella:BAAALgAECgcJBwABLgAFFAUJCwAMAIsXAA==.',
Sc='Schattën:BAAALgAECgcJEQAAAA==.',
Se='Senseideath:BAAALgAECgMJAwABLgADCgYJBgATAAAAAA==.Serrana:BAAALgAECgQJDAAAAA==.',
Sf='Sfinktor:BAAALgADCgQJBAAAAA==.',
Sh='Shakz:BAAALgAECgYJBwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shirokhan:BAABLgAECn8XAAIEAAcJcx6SKQC+AQAEAAcJcx6SKQC+AQAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgADCgUJBQAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAABLgAECn8mAAMMAAgJ6iB9EAAjAgAMAAgJ6iB9EAAjAgABAAIJ+xwWRwCaAAAAAA==.',
Sn='Snagglespark:BAABLgAECn8hAAIPAAgJrhsgFgBpAgAPAAgJrhsgFgBpAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCgcJCQAAAA==.',
So='Soladrian:BAABLgAECn8SAAIIAAYJ+hj4IQBnAQAIAAYJ+hj4IQBnAQAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwATAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgMJAwAAAA==.',
St='Starlisia:BAAALgAECgUJCwAAAA==.Starz:BAAALgAECgUJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAECggJHAAbABcZAA==.',
Su='Suhdrake:BAABLgAECn8bAAIiAAcJXxiECwBVAQAiAAcJXxiECwBVAQAAAA==.Sunwing:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAAALgAECgIJAgAAAA==.',
['Só']='Sóozabimaru:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8UAAMJAAYJRw6TFQBGAQAJAAYJRw6TFQBGAQAKAAEJ+QIZaQAmAAAAAA==.',
Ta='Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8UAAIOAAYJmRXGDQBCAQAOAAYJmRXGDQBCAQAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAAMAAEZAA==.',
Tc='Tcharta:BAAALgAECgYJDwABLgAECgYJDwATAAAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgADCgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgIJAgABLgAECggJHwALAC8dAA==.Thoror:BAAALgAECgUJBwAAAA==.Thunderblap:BAAALgADCgEJAQAAAA==.Thunderbolt:BAAALgADCgIJAgABLgADCgYJBgATAAAAAA==.',
Ti='Tiamat:BAAALgADCgYJBgAAAA==.Tiffina:BAAALgAECgYJCQAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.',
Tr='Treeberk:BAAALgADCgkJCQAAAA==.Trissara:BAAALgAECgMJAwAAAA==.Trolli:BAABLgAECn8bAAIVAAgJjR9RDwBEAgAVAAgJjR9RDwBEAgAAAA==.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.',
Tw='Twixx:BAAALgAFFAIJAgAAAA==.',
Ty='Tyinar:BAAALgAECgEJAgAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgADCgUJBQAAAA==.Tîtån:BAAALgAECgYJDgAAAA==.',
Ud='Uddercover:BAAALgAECgQJBQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJBwABLgAECgYJGQAUABUkAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQATAAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIcAAMJjCHZMwD5AAAcAAMJjCHZMwD5AAAuAAQKfxYAAxwABgkdJuM9AEACABwABgkdJuM9AEACAB8AAQnNITc8AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vathen:BAABLgAECn8UAAIMAAcJARmOOQAlAgAMAAcJARmOOQAlAgAAAA==.',
Ve='Velmalthea:BAAALgAECgYJEwAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAABLgAECn8dAAIfAAcJBBtwBwCoAQAfAAcJBBtwBwCoAQAAAA==.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECgYJBgABLgAECgkJHAAVACQSAA==.',
Vo='Voidfed:BAAALgAECgEJAQABLgAECgYJDAATAAAAAA==.Vokzhen:BAAALgAECgYJDwAAAA==.Volescu:BAAALgAECgEJAgAAAA==.',
Wa='Walkerboah:BAABLgAECn8aAAMMAAcJGRH0NQBTAQAMAAcJGRH0NQBTAQABAAUJwAopMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAAALgAFFAEJAQAAAA==.',
Wo='Wolf:BAAALgAECgYJDAAAAA==.',
Wy='Wyland:BAAALgAECgYJEAAAAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAUJEQARAAImAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAUJEQARAAImAA==.Xeromus:BAABLgAECn8UAAICAAYJhRcJFwBHAQACAAYJhRcJFwBHAQAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Za='Zabawaba:BAAALgAECgYJEgAAAA==.Zaboomaprune:BAAALgAECgcJCgAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zarika:BAAALgAECggJCwABLgAFFAUJEQARAAImAA==.Zarì:BAACLgAFFH8RAAIRAAUJAiadAADHAQARAAUJAiadAADHAQAuAAQKfxwAAhEACQm8JQ4DAGUDABEACQm8JQ4DAGUDAAAA.Zaö:BAAALgADCgEJAQABLgAECgkJHgARALwcAA==.',
Ze='Zeblaw:BAABLgAECn8aAAIEAAcJjRb0PQB0AQAEAAcJjRb0PQB0AQAAAA==.Zenazure:BAAALgAECgUJCgAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgADCgEJAgAAAA==.',
['Zà']='Zàomega:BAABLgAECn8eAAMRAAkJvBxjAwCLAgARAAkJvBxjAwCLAgAWAAEJuA/sawAqAAAAAA==.',
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

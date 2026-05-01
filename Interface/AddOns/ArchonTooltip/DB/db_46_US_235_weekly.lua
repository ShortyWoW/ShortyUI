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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','DeathKnight-Unholy','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Unknown-Unknown','Mage-Frost','Warlock-Affliction','DemonHunter-Devourer','Shaman-Enhancement','Druid-Guardian','Shaman-Elemental','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Rogue-Subtlety','DemonHunter-Havoc','Monk-Brewmaster','Rogue-Assassination','Priest-Discipline','Druid-Feral','Monk-Windwalker','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Frost','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Addisyn:BAAALgADCgYJBwAAAA==.',
Ae='Aemetris:BAAALgAECgQJAwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgEJAgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgADCggJCAAAAA==.',
Aj='Ajheria:BAAALgADCgMJBAAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgADCgMJAwAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAABLgAECn8qAAMBAAkJnyAjAQCUAgABAAgJLSAjAQCUAgACAAEJuiNDcwBsAAAAAA==.',
Ap='Aponi:BAAALgADCggJGAAAAA==.',
Ar='Ardour:BAAALgAECgMJBgAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8dAAIDAAgJQRb7FgDKAQADAAgJQRb7FgDKAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAAALgAECgcJEQAAAA==.Asparagus:BAAALgAECgYJCgAAAA==.',
At='Atlass:BAABLgAECn8XAAIEAAcJ8RmlPABJAQAEAAcJ8RmlPABJAQAAAA==.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBAABLgAFFAYJEwAFABgYAQ==.Aust:BAAALgAECggJDwAAAA==.',
Av='Averlis:BAAALgAECgYJDwAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgYJDQAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAAALgAECgYJEQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8qAAIGAAgJoB9wFQDVAgAGAAgJoB9wFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgUJBwAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgIJAgAAAA==.Beastly:BAAALgAECgQJBQAAAA==.Beeble:BAAALgADCgQJBQAAAA==.Belii:BAAALgAECgMJAQAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJBgAAAA==.',
Bi='Bigbooty:BAAALgAECgMJCQAAAA==.',
Bl='Blikey:BAAALgAFFAIJBAAAAA==.Bloodyrott:BAAALgAECgQJBgAAAA==.Bluedrake:BAABLgAECn8cAAMHAAgJ7R27BAC6AgAHAAgJgx27BAC6AgAIAAgJiRVOGQADAgABLgAFFAIJBwAJADoTAA==.Blueparrot:BAABLgAECn8bAAIKAAcJxhAXFABzAQAKAAcJxhAXFABzAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8WAAILAAcJqBueDwDAAQALAAcJqBueDwDAAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8MAAMEAAUJ9B+cDwBwAQAEAAQJ9B+cDwBwAQAMAAEJAABzJQAAAAAuAAQKfyAAAwQACQmpIaAXAO4CAAQACQmpIaAXAO4CAAwABAmqE9sYALUAAAAA.Bowkatan:BAAALgAECgEJAQAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8VAAINAAYJ9B00JQD8AQANAAYJ9B00JQD8AQAAAA==.Bringinlight:BAAALgADCgkJEAAAAA==.',
Bu='Bubbleicious:BAAALgAECgEJAQAAAA==.Bubbletea:BAAALgAECgMJBAABLgAECgkJKAACAFsiAA==.Bulletz:BAAALgAECgYJEQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgEJAQABLgAECgIJAwAOAAAAAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8eAAMJAAcJVQmPPwAzAQAJAAcJVQmPPwAzAQADAAUJXg6POgDpAAAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.',
Ce='Cedrick:BAAALgADCgcJCQAAAA==.Celody:BAAALgAECgMJAwAAAA==.Celticsinsix:BAAALgADCgUJBQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn8VAAIPAAYJaQvwfwDUAAAPAAYJaQvwfwDUAAAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAAALgAECgIJAwAAAA==.Chogric:BAABLgAECn8nAAINAAkJvB6LBQATAwANAAkJvB6LBQATAwABLgABCgQJBQAOAAAAAA==.',
Ci='Civetta:BAAALgAECgYJBwAAAA==.',
Cl='Clannininick:BAAALgADCgUJBQAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgADCgEJAgAAAA==.Convalesor:BAAALgAECgYJCgAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8FAAIEAAIJMh80OwCmAAAEAAIJMh80OwCmAAAAAA==.Crona:BAABLgAECn8YAAINAAgJZg8HPACJAQANAAgJZg8HPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8MAAIPAAUJ+xL8IwBEAQAPAAUJ+xL8IwBEAQAuAAQKfxcAAg8ACAnmH2g5AJACAA8ACAnmH2g5AJACAAAA.Crzzy:BAAALgAECgQJBwAAAA==.',
Cu='Cuddlez:BAAALgAECgcJEwAAAA==.Cultera:BAAALgAECggJDgAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8bAAIQAAgJBh9wAACHAgAQAAgJBh9wAACHAgABLgAECggJLwARAHUaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Danda:BAAALgAECgUJBQAAAA==.Daricepicker:BAABLgAECn8oAAICAAkJWyJQBQA3AwACAAkJWyJQBQA3AwAAAA==.Darkyn:BAAALgAECgYJDgAAAA==.Davedadude:BAAALgAECggJDQAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAAALgAECgUJBwAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIEAAgJ8wvhbACwAQAEAAgJ8wvhbACwAQAAAA==.Deadscar:BAABLgAECn8hAAISAAgJxyRdAgAoAwASAAgJxyRdAgAoAwAAAA==.Deathmasterj:BAAALgADCggJCAAAAA==.Deaths:BAAALgAECgUJDgAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAOAAAAAA==.Deviously:BAAALgADCgEJAQABLgAECgYJEQAOAAAAAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dithariaa:BAAALgAECgIJAgAAAA==.',
Do='Docryktor:BAABLgAECn8ZAAISAAcJ7xSABgCfAQASAAcJ7xSABgCfAQAAAA==.Doomgears:BAAALgAECgIJAgAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Dragonair:BAAALgAECgQJBwAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAAALgAECgQJBgAAAA==.Dro:BAAALgAECgQJBwAAAA==.Dropbear:BAAALgAECggJDAAAAA==.Drtybear:BAAALgAECgUJBwAAAA==.Drulissa:BAABLgAECn8WAAINAAgJtBiXLQDNAQANAAgJtBiXLQDNAQABLgAFFAEJAQAOAAAAAA==.Druu:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.',
Du='Duogear:BAAALgADCgIJAgAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgQJCAAAAA==.',
Ed='Ediana:BAABLgAECn8jAAIPAAcJMgm9VAA2AQAPAAcJMgm9VAA2AQAAAA==.',
El='Elmyouu:BAAALgADCgYJBwABLgAECgcJCwAOAAAAAA==.Elmô:BAABLgAECn8YAAINAAcJCR+XBgB4AgANAAcJCR+XBgB4AgAAAA==.Elvara:BAAALgAECgQJBgAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8hAAITAAcJZBemCwDUAQATAAcJZBemCwDUAQAAAA==.',
Ex='Exash:BAABLgAECn8YAAIUAAgJICIyCQD/AgAUAAgJICIyCQD/AgAAAA==.Excizion:BAAALgADCgcJBwAAAA==.',
Fa='Fathertim:BAAALgAECgIJAgAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAAALgAECgYJEAAAAA==.',
Fu='Fudestamp:BAAALgADCgMJBAAAAA==.Fugryktor:BAAALgAECgQJBwAAAA==.',
Fy='Fyrebug:BAAALgAECgMJAwAAAA==.',
Ga='Galandor:BAAALgAECgMJAwAAAA==.Gandaalf:BAAALgAECgcJEgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8UAAIVAAYJ8gpQKgAYAQAVAAYJ8gpQKgAYAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAWAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIDAAgJQSD6BADVAgADAAgJQSD6BADVAgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn8gAAIXAAgJBx0/DgBPAgAXAAgJBx0/DgBPAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAYJDgAYAMgjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgAECgMJAwAAAA==.Graysurv:BAACLgAFFH8OAAIYAAYJyCMEAACBAgAYAAYJyCMEAACBAgAuAAQKfx8AAhgACQnyJgUAABIEABgACQnyJgUAABIEAAAA.Gromlin:BAAALgADCggJDgAAAA==.',
['Gä']='Gäreth:BAAALgADCgUJBQAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hasalia:BAAALgAECggJCAABLgAFFAEJAQAOAAAAAA==.',
He='Healsforu:BAAALgAECgMJBQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAAALgAECgcJEAAAAA==.Heunno:BAAALgADCgYJBgAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAAALgAECggJEQAAAA==.Highbrittz:BAAALgAECgYJDQAAAA==.',
Ho='Hoakaren:BAAALgAECgYJEgAAAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgADCgIJAgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAAALgAECgYJDQAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwAOAAAAAA==.',
Il='Illyy:BAABLgAECn8cAAIKAAcJcwz2GQA4AQAKAAcJcwz2GQA4AQAAAA==.',
In='Indawhole:BAABLgAFFH8NAAIRAAYJ5hULCQCYAQARAAYJ5hULCQCYAQAAAA==.',
Ir='Iridori:BAABLgAECn8hAAIKAAcJzyBGBACQAgAKAAcJzyBGBACQAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgAECgMJAwAAAA==.',
Ja='Jamerius:BAAALgADCgIJAgAAAA==.Jasmean:BAAALgADCgMJAwAAAA==.Javaluminous:BAABLgAECn8eAAIXAAcJJSBOEQAxAgAXAAcJJSBOEQAxAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJDwAZAEAbAA==.Jaytsukitori:BAACLgAFFH8GAAIDAAMJcBz8DwAfAQADAAMJcBz8DwAfAQAuAAQKfx0AAwMACAmHIbwMANcCAAMACAmHIbwMANcCAAkAAQlGEDZGADQAAAAA.',
Jh='Jhaeriao:BAAALgAECgQJBwAAAA==.Jhantherox:BAAALgADCgEJAQAAAA==.',
Jo='Joesepi:BAABLgAFFH8NAAIEAAUJ5BaUNgDyAAAEAAUJ5BaUNgDyAAAAAA==.Jonah:BAAALgAECgUJCAABLgAECggJFwAEAGUjAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIPAAYJUQ5c0ABMAQAPAAYJUQ5c0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Ki='Kilrah:BAABLgAECn8mAAIaAAgJhRQqCQC0AQAaAAgJhRQqCQC0AQAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAAALgAECgQJCQAAAA==.Kissmycrits:BAAALgAECgQJDQAAAA==.Kiyana:BAABLgAECn8cAAIaAAYJrQ3RFQD2AAAaAAYJrQ3RFQD2AAAAAA==.Kiyoine:BAAALgAECgcJEwAAAA==.',
Kn='Knocksteady:BAACLgAFFH8NAAIXAAQJVhieCgBXAQAXAAQJVhieCgBXAQAuAAQKfxcAAhcABwlzIIokAJUCABcABwlzIIokAJUCAAAA.Knoxform:BAAALgAECgIJAgAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgIJAgAOAAAAAA==.Knoxstaggers:BAABLgAECn8cAAIbAAcJhiH4EgB6AgAbAAcJhiH4EgB6AgABLgAECgIJAgAOAAAAAA==.',
Ku='Kuray:BAAALgAECgEJAQAAAA==.',
Ky='Kynbrookera:BAAALgAECgUJCwAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgMJBgAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJBwAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8WAAIPAAYJThXFSABUAQAPAAYJThXFSABUAQAAAA==.',
Li='Licht:BAAALgAECgYJCAAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8UAAIcAAYJMQjMDQA+AQAcAAYJMQjMDQA+AQAAAA==.Lit:BAAALgAECgEJAQAAAA==.Littledog:BAABLgAECn8nAAMFAAcJghbfDwCOAQAFAAcJghbfDwCOAQAdAAMJHRSsPQC/AAAAAA==.',
Lo='Loky:BAABLgAECn8cAAMGAAkJvR5PPwAQAgAGAAcJvB5PPwAQAgAVAAQJfhjLJAA1AQAAAA==.Longshanks:BAAALgADCgUJCgAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgQJBgAAAA==.',
Lu='Luckevin:BAAALgAECgQJCAAAAA==.Lunitari:BAAALgADCggJCAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCAABLgAECgcJFQAeAJ0MAA==.',
Ly='Lynnali:BAAALgADCggJEAAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAAALgAECgcJEgAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Malafang:BAAALgAECgEJAQAAAA==.Malanah:BAAALgADCgkJGwAAAA==.Marandra:BAAALgADCgcJDAAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgADCggJCQAAAA==.Maverick:BAACLgAFFH8PAAIZAAUJQBv8BgBfAQAZAAUJQBv8BgBfAQAuAAQKfxsAAxkABwlUIsMVAGECABkABwlNIsMVAGECABwABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAAALgAECgQJBgAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgMJAwABLgAECggJKQAfAAIjAA==.',
Mo='Mogina:BAAALgADCggJCAAAAA==.Monster:BAAALgAECgMJAwAAAA==.Moonzhine:BAABLgAECn8WAAIMAAYJNBeuDQA2AQAMAAYJNBeuDQA2AQAAAA==.Moosejaw:BAAALgADCgcJCAAAAA==.Mordread:BAAALgADCgcJEwAAAA==.Morgalruk:BAAALgAECgUJCQAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8QAAQCAAUJgRwDAgCBAQACAAUJdBwDAgCBAQAYAAMJjQ3ECgD4AAABAAEJ3wK+LAA/AAAuAAQKfygABAIACAl+In8IAAoDAAIACAl+In8IAAoDABgABQlPGD4TADYBAAEABQkFEcJMAB4BAAAA.',
Na='Narukin:BAAALgAECgcJEgAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAYJEwAFABgYAA==.',
Ni='Nivmizzet:BAABLgAECn8hAAMGAAcJaRczIAC0AQAGAAcJChczIAC0AQAVAAQJERcsLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJCgAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAABLgAECn8mAAMgAAkJECJsBQCeAgAgAAkJECJsBQCeAgAUAAQJHB1vJAD+AAAAAA==.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMWAAgJzxxYCwBYAgAWAAcJgB1YCwBYAgALAAgJhRoTIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.',
Ox='Oxxo:BAAALgAECgIJAgAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAAALgAECgQJBwAAAA==.',
Pe='Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJAgAAAA==.Phuriosa:BAAALgAECgQJBAABLgAECggJIQADABoZAA==.Phury:BAABLgAECn8hAAIDAAgJGhlRDgAoAgADAAgJGhlRDgAoAgAAAA==.',
Pi='Pizza:BAAALgAECgIJAgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJAgAAAA==.Porkmancer:BAAALgAECgUJBQAAAA==.Porkslope:BAABLgAECn8cAAIEAAcJuh24HgDPAQAEAAcJuh24HgDPAQAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgMJAwAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Ra='Raenyx:BAABLgAECn8XAAMGAAYJohvdJQCYAQAGAAYJohvdJQCYAQAQAAEJAABSLABGAAAAAA==.Raiflock:BAAALgADCgcJEAAAAA==.Ranalastus:BAAALgAECgEJAQAAAA==.Ravenblack:BAAALgAECgEJAQAAAA==.Raveneyes:BAEBLgAECn8WAAIGAAYJgg1ZRwAaAQAGAAYJgg1ZRwAaAQAAAA==.',
Re='Reiena:BAAALgAECgYJCQAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8YAAIhAAgJHxHRGABAAQAhAAgJHxHRGABAAQAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8WAAIRAAYJvBF/SQDJAAARAAYJvBF/SQDJAAAAAA==.',
Ri='Ricola:BAAALgAFFAEJAgAAAA==.Rivenel:BAABLgAECn8WAAIVAAYJpSI2AgD6AQAVAAYJpSI2AgD6AQAAAA==.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMRAAkJYSAOFQDZAgARAAkJYSAOFQDZAgAaAAEJ+RRhaQBAAAAAAA==.Rocksann:BAAALgADCggJDQAAAA==.Rodel:BAAALgADCgUJBQAAAA==.Roquan:BAABLgAECn8hAAIiAAcJvRpLAgDlAQAiAAcJvRpLAgDlAQAAAA==.Roulette:BAAALgAECgMJAwAAAA==.',
Ru='Rubmyrott:BAAALgADCgYJBwAAAA==.Runalot:BAAALgADCgUJBQAAAA==.',
['Rê']='Rêdd:BAAALgAECgIJAwAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Salswarriah:BAAALgAECgMJAwAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottlee:BAAALgADCgIJBAABLgAECgQJDwAOAAAAAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAOAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.',
Sg='Sgtpunchy:BAAALgADCgMJBQABLgAECgMJBQAOAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shamanizim:BAABLgAECn8iAAQSAAcJ9Bl1CABqAQAUAAcJvBWAMwCLAQASAAYJWhZ1CABqAQAgAAIJIAYiXABAAAAAAA==.Sheeanna:BAAALgAFFAEJAQAAAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAAALgAECggJEQAAAA==.Shinotenshi:BAAALgAECgYJCQABLgAECggJEQAOAAAAAA==.Shirase:BAAALgADCgkJIwABLgAECgkJJgAgABAiAA==.Shugarae:BAABLgAECn8VAAMJAAcJdQSoWADBAAAJAAcJdQSoWADBAAADAAUJbwTMUwCBAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skreezy:BAAALgAECgYJCgAAAA==.Skuls:BAAALgADCgcJBwAAAA==.',
Sl='Slashemup:BAABLgAECn8WAAIaAAYJihSTEAA0AQAaAAYJihSTEAA0AQAAAA==.Slayter:BAABLgAECn8bAAIDAAgJziEXHwBHAgADAAgJziEXHwBHAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAQAAAA==.',
Sn='Snakelazers:BAAALgAECggJEQAAAA==.Snufulafagus:BAAALgADCggJGQAAAA==.',
So='Soju:BAAALgAECgUJEgABLgAECgkJKAACAFsiAA==.Songwind:BAABLgAECn8UAAIfAAYJ0ANwLgCNAAAfAAYJ0ANwLgCNAAAAAA==.Soonie:BAAALgADCgEJAQAAAA==.',
Sq='Squishypal:BAAALgAECgUJCgAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAAALgAECgMJAwAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgADCgcJBwAAAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8UAAMCAAYJmh/sFwDTAQACAAYJmh/sFwDTAQABAAQJ2BPYVgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgADCggJCAAAAA==.Tentreeadvos:BAAALgADCggJGQABLgAECgQJCAAOAAAAAA==.Tetris:BAABLgAECn8pAAIPAAkJ1CGSBQDhAgAPAAkJ1CGSBQDhAgAAAA==.',
Th='Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECggJCgAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJDAAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgADCgcJCQABLgAFFAMJBgADAHAcAA==.',
Tr='Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAAALgAECggJDQAAAA==.Truthfully:BAAALgAECgUJCAAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgADCgcJEAAAAA==.',
Ug='Ugrup:BAAALgAECgMJAQAAAA==.',
Uj='Ujabula:BAAALgAECgUJCgAAAA==.',
Ul='Ulurak:BAABLgAECn8VAAMeAAcJnQwXGwAaAQAeAAYJkwkXGwAaAQADAAMJbgjtqgBxAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIjAAcJ0wd3FgBJAQAjAAcJ0wd3FgBJAQAAAA==.Unhappytoast:BAAALgAECgYJBwAAAA==.Unstobubble:BAAALgAECgEJAQAAAA==.',
Va='Valeriya:BAAALgADCgMJAwABLgADCgUJBQAOAAAAAA==.Valisanna:BAAALgADCgMJAwAAAA==.Vallorien:BAAALgAECgMJAwAAAA==.Valsharess:BAAALgADCgcJBwABLgAECggJLwARAHUaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velnia:BAAALgAECgYJCgAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgQJAwAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgADCgQJCQAAAA==.',
Wa='Wasenshi:BAAALgADCgIJAgAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgADCgUJBQAAAA==.',
Wi='Wickedromeo:BAAALgADCgIJBAAAAA==.',
Wo='Wolfmother:BAAALgAECgQJDwAAAA==.',
Xa='Xaanii:BAAALgAECgMJAwAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAAALgAECgIJAgAAAA==.',
Xe='Xeeria:BAACLgAFFH8FAAIgAAIJaRgYGgCSAAAgAAIJaRgYGgCSAAAuAAQKfyIAAiAACAlgIgwNALUCACAACAlgIgwNALUCAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIDAAgJ2RYRLgD1AQADAAgJ2RYRLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgEJAQAAAA==.',
Za='Zamzak:BAAALgADCgQJBAAAAA==.Zanthor:BAAALgAECgUJDwAAAA==.Zaralina:BAABLgAECn8VAAIFAAgJ+QlNJwCeAQAFAAgJ+QlNJwCeAQAAAA==.Zartox:BAABLgAECn8UAAIkAAYJAxfAAgB+AQAkAAYJAxfAAgB+AQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zaryssa:BAAALgAECgcJDQAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDQAAAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgADCgkJCwAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAAALgAECgYJDQAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAAALgAECgYJBwAAAA==.',
['Ût']='Ûthèr:BAAALgADCgEJAQAAAA==.',
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

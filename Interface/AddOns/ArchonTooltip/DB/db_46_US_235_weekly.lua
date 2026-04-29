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

local lookup = {'Hunter-Marksmanship','Druid-Restoration','Priest-Shadow','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Unknown-Unknown','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Druid-Guardian','Shaman-Elemental','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Priest-Holy','Rogue-Subtlety','DemonHunter-Havoc','Monk-Brewmaster','Priest-Discipline','Warlock-Destruction','Druid-Feral','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Monk-Mistweaver','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Addisyn:BAAALgADCgQJBAAAAA==.',
Ae='Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgEJAQAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Aj='Ajheria:BAAALgADCgEJAQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAABLgAECn8gAAIBAAgJGx+1AABMAgABAAgJGx+1AABMAgAAAA==.',
Ap='Aponi:BAAALgADCggJGAAAAA==.',
Ar='Ardour:BAAALgAECgMJAwAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8bAAICAAcJEhhJCgCzAQACAAcJEhhJCgCzAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAAALgAECgcJEQAAAA==.Asparagus:BAAALgAECgYJCgAAAA==.',
At='Atlass:BAAALgAECgcJEgAAAA==.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBAABLgAFFAYJDgADAHgVAQ==.Aust:BAAALgAECggJDwAAAA==.',
Av='Averlis:BAAALgAECgYJDwAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgQJBwAAAA==.',
Ba='Bacon:BAAALgAECgYJCwAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8kAAIEAAgJiR52FQDVAgAEAAgJiR52FQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgQJBgAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgEJAQAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgIJAgAAAA==.Beastly:BAAALgAECgQJBAAAAA==.Beeble:BAAALgADCgQJBQAAAA==.Belii:BAAALgAECgEJAQAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgIJAgAAAA==.',
Bi='Bigbooty:BAAALgAECgMJBgAAAA==.',
Bl='Blikey:BAAALgAECgQJBwAAAA==.Bloodyrott:BAAALgAECgQJBgAAAA==.Bluedrake:BAABLgAECn8cAAMFAAgJ7R26BAC6AgAFAAgJgx26BAC6AgAGAAgJiRVIGQADAgABLgAFFAIJBQAHADoTAA==.Blueparrot:BAAALgAECgYJEgAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAAALgAECgcJDwAAAA==.',
Bo='Bonesnap:BAACLgAFFH8HAAIIAAQJKxKBCAA9AQAIAAQJKxKBCAA9AQAuAAQKfxoAAggACAlLIJ0XAO4CAAgACAlLIJ0XAO4CAAAA.Bowkatan:BAAALgADCgEJAQAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAAALgAECgYJEAAAAA==.Bringinlight:BAAALgADCgkJDwAAAA==.',
Bu='Bubbletea:BAAALgAECgIJAgABLgAECgkJJAAJACUhAA==.Bulletz:BAAALgAECgYJDgAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgEJAQAAAA==.',
Ca='Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8VAAMHAAcJEAmQPwAzAQAHAAcJEAmQPwAzAQACAAEJaA6fOAAwAAAAAA==.',
Ce='Cedrick:BAAALgADCgYJCQAAAA==.Celody:BAAALgADCgEJAQAAAA==.Celticsinsix:BAAALgADCgUJBQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAAALgAECgUJDwAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAAALgAECgIJAgAAAA==.Chogric:BAABLgAECn8hAAIKAAkJeB2QBQATAwAKAAkJeB2QBQATAwABLgABCgQJBQALAAAAAA==.',
Ci='Civetta:BAAALgAECgEJAQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBQAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Convalesor:BAAALgAECgMJBAAAAA==.',
Cr='Crazzywazzy:BAAALgAFFAIJAwAAAA==.Crona:BAABLgAECn8YAAIKAAgJZg8JPACJAQAKAAgJZg8JPACJAQAAAA==.Crzyblnkrton:BAACLgAFFH8KAAIMAAQJ+xLQCQBRAQAMAAQJ+xLQCQBRAQAuAAQKfxcAAgwACAnmH2M5AJACAAwACAnmH2M5AJACAAAA.Crzzy:BAAALgAECgQJBwAAAA==.',
Cu='Cultera:BAAALgAECgcJCAAAAA==.',
Cy='Cyhyraethia:BAAALgAECgcJEwABLgAECggJJgANACcYAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Danda:BAAALgAECgUJBQAAAA==.Daricepicker:BAABLgAECn8kAAIJAAkJJSFQBQA3AwAJAAkJJSFQBQA3AwAAAA==.Darkyn:BAAALgAECgYJCAAAAA==.Davedadude:BAAALgAECgIJAgAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAAALgAECgQJBQAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIIAAgJ8wvnbACwAQAIAAgJ8wvnbACwAQAAAA==.Deadscar:BAABLgAECn8dAAIOAAgJWSNeAgAoAwAOAAgJWSNeAgAoAwAAAA==.Deathmasterj:BAAALgADCggJCAAAAA==.Deaths:BAAALgAECgMJCAAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwALAAAAAA==.Deviously:BAAALgADCgEJAQABLgAECgYJDgALAAAAAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Do='Docryktor:BAAALgAECgcJEgAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Dragonair:BAAALgAECgMJAwAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAAALgAECgEJAwAAAA==.Dro:BAAALgAECgQJBwAAAA==.Dropbear:BAAALgADCgYJCQAAAA==.Drtybear:BAAALgAECgEJAQAAAA==.Drulissa:BAAALgAECgcJEwABLgAECggJCAALAAAAAA==.Druu:BAAALgADCgMJAwABLgAECgcJGwAMACkfAA==.',
Du='Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgQJBwAAAA==.',
Ed='Ediana:BAABLgAECn8cAAIMAAcJ7AYvMQAEAQAMAAcJ7AYvMQAEAQAAAA==.',
El='Elmyouu:BAAALgADCgMJAwABLgAECgcJCwALAAAAAA==.Elmô:BAAALgAECgYJEQAAAA==.Elvara:BAAALgAECgIJBAAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8YAAIPAAcJURekCwDUAQAPAAcJURekCwDUAQAAAA==.',
Ex='Exash:BAABLgAECn8XAAIQAAgJNCAuCQD/AgAQAAgJNCAuCQD/AgAAAA==.',
Fe='Feannara:BAAALgAECgYJCAAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.',
Fr='Frostii:BAAALgAECgYJCwAAAA==.',
Fu='Fudestamp:BAAALgADCgMJBAAAAA==.Fugryktor:BAAALgAECgIJAwAAAA==.',
Fy='Fyrebug:BAAALgADCgkJGgAAAA==.',
Ga='Galandor:BAAALgADCgkJGgAAAA==.Gandaalf:BAAALgAECgcJEAAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAAALgAECgYJDwAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghostsaber:BAAALgADCgEJAQABLgAECggJGQARAM8cAA==.',
Gi='Gigglyguff:BAAALgAECggJEgAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn8YAAISAAcJ8hlxSQAGAgASAAcJ8hlxSQAGAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAYJDQATAJwjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgADCgYJDQAAAA==.Graysurv:BAACLgAFFH8NAAITAAYJnCMEAACBAgATAAYJnCMEAACBAgAuAAQKfx8AAhMACQnyJgUAABIEABMACQnyJgUAABIEAAAA.Gromlin:BAAALgADCgcJCwAAAA==.',
['Gä']='Gäreth:BAAALgADCgUJBQAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hasalia:BAAALgAECggJCAAAAA==.',
He='Healsforu:BAAALgAECgIJAwAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAAALgAECgMJBgAAAA==.Heunno:BAAALgADCgYJBgAAAA==.',
Hi='Hiemy:BAAALgADCgcJBwAAAA==.Hif:BAAALgAECggJEQAAAA==.Highbrittz:BAAALgAECgYJDQAAAA==.',
Ho='Hoakaren:BAAALgAECgQJCAAAAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgADCgIJAgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAAALgAECgYJCwAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwALAAAAAA==.',
Il='Illyy:BAAALgAECgcJEwAAAA==.',
In='Indawhole:BAABLgAFFH8NAAINAAUJsxoLCQCYAQANAAUJsxoLCQCYAQAAAA==.',
Ir='Iridori:BAABLgAECn8YAAIUAAcJDR19BQDLAQAUAAcJDR19BQDLAQAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgADCgkJEAAAAA==.',
Ja='Jamerius:BAAALgADCgIJAgAAAA==.Javaluminous:BAABLgAECn8VAAISAAcJeRsqQAAlAgASAAcJeRsqQAAlAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJDAAVAOkRAA==.Jaytsukitori:BAABLgAECn8dAAMCAAgJhyG+DADXAgACAAgJhyG+DADXAgAHAAEJRhDGIQA2AAAAAA==.',
Jh='Jhaeriao:BAAALgAECgMJAwAAAA==.Jhantherox:BAAALgADCgEJAQAAAA==.',
Jo='Joesepi:BAABLgAFFH8IAAIIAAQJoBOhCgAgAQAIAAQJoBOhCgAgAQAAAA==.Jonah:BAAALgAECgQJBQABLgAECggJFQAIAKsiAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAQAAAA==.',
Ka='Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIMAAYJUQ5V0ABMAQAMAAYJUQ5V0ABMAQAAAA==.',
Ki='Kilrah:BAABLgAECn8eAAIWAAgJhRRTAwDCAQAWAAgJhRRTAwDCAQAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAAALgAECgQJBQAAAA==.Kissmycrits:BAAALgAECgQJDAAAAA==.Kiyana:BAAALgAECgYJEQAAAA==.Kiyoine:BAAALgAECgcJEQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8JAAISAAQJKBaZCgBXAQASAAQJKBaZCgBXAQAuAAQKfxcAAhIABwlzII8kAJUCABIABwlzII8kAJUCAAAA.Knoxform:BAAALgAECgIJAgAAAA==.Knoxstaggers:BAABLgAECn8WAAIXAAcJQSD4EgB6AgAXAAcJQSD4EgB6AgABLgAECgIJAgALAAAAAA==.',
Ku='Kuray:BAAALgADCgEJAQAAAA==.',
Ky='Kynbrookera:BAAALgAECgMJBgAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgIJAwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgMJAwAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAAALgAECgYJEAAAAA==.',
Li='Licht:BAAALgAECgEJAwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAAALgAECgYJDwAAAA==.Lit:BAAALgAECgEJAQAAAA==.Littledog:BAABLgAECn8gAAMDAAYJNBlWIwC9AQADAAYJNBlWIwC9AQAYAAMJHRSoPQC/AAAAAA==.',
Lo='Loky:BAABLgAECn8ZAAMEAAgJmh5PPwAQAgAEAAYJlB5PPwAQAgAZAAQJfhjKJAA1AQAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgMJAwAAAA==.',
Lu='Luckevin:BAAALgAECgMJBAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCAABLgAECgcJFQAaAJ0MAA==.',
Ly='Lynnali:BAAALgADCggJDgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAAALgAECgYJCwAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Malanah:BAAALgADCgkJGgAAAA==.Marandra:BAAALgADCgcJDAAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgADCgEJAQAAAA==.Maverick:BAACLgAFFH8MAAIVAAUJ6RGfCABiAQAVAAUJ6RGfCABiAQAuAAQKfxsAAxUABwlUIsUVAGECABUABwlNIsUVAGECABsABAmBIpYMAFgBAAAA.Maxbaba:BAAALgADCgYJBQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAAALgAECgMJBAAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgADCgUJCAABLgAECggJJAAcAAIjAA==.',
Mo='Mogina:BAAALgADCggJCAAAAA==.Monster:BAAALgADCgkJFAAAAA==.Moonzhine:BAAALgAECgYJEAAAAA==.Moosejaw:BAAALgADCgcJBwAAAA==.Mordread:BAAALgADCgcJDwAAAA==.Morgalruk:BAAALgAECgUJBQAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8LAAMJAAQJdBwDAgCBAQAJAAQJdBwDAgCBAQABAAEJ3wK7LAA/AAAuAAQKfyIAAwkACAl+In4IAAoDAAkACAl+In4IAAoDAAEABQkFEcxMAB4BAAAA.',
Na='Narukin:BAAALgAECgUJCQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAYJDgADAHgVAA==.',
Ni='Nivmizzet:BAABLgAECn8YAAMEAAcJPRXjWAC9AQAEAAcJTxTjWAC9AQAZAAQJERctLQAJAQAAAA==.',
No='Nolakai:BAAALgADCgcJFgAAAA==.Nomiro:BAAALgAECgYJCAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAABLgAECn8eAAMdAAgJMyJsAwBKAgAdAAgJMyJsAwBKAgAQAAQJ8RJpXADRAAAAAA==.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMRAAgJzxxZCwBYAgARAAcJgB1ZCwBYAgAeAAgJhRoSIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgADCgYJCQAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAAALgAECgIJAwAAAA==.',
Pe='Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJDgAAAA==.',
Ph='Phuriosa:BAAALgAECgQJBAABLgAECggJHAACAO4XAA==.Phury:BAABLgAECn8cAAICAAgJ7hcJCADiAQACAAgJ7hcJCADiAQAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAECgIJAwAAAA==.Porkslope:BAABLgAECn8YAAIIAAcJiBzzEACNAQAIAAcJiBzzEACNAQAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgADCggJCQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Ra='Raenyx:BAAALgAECgYJEQAAAA==.Raiflock:BAAALgADCgcJEAAAAA==.Ranalastus:BAAALgADCgIJAQAAAA==.Ravenblack:BAAALgAECgEJAQAAAA==.Raveneyes:BAEALgAECgYJEAAAAA==.',
Re='Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8XAAIfAAgJXhC4CQBUAQAfAAgJXhC4CQBUAQAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8WAAINAAYJvBFIKwDJAAANAAYJvBFIKwDJAAAAAA==.',
Ri='Rivenel:BAAALgAECgYJDwAAAA==.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8ZAAMNAAgJyCAHFQDZAgANAAgJyCAHFQDZAgAWAAEJ+RRkaQBAAAAAAA==.Rocksann:BAAALgADCggJDAAAAA==.Rodel:BAAALgADCgUJBQAAAA==.Roquan:BAABLgAECn8YAAIgAAcJTBgVBQD1AQAgAAcJTBgVBQD1AQAAAA==.Roulette:BAAALgADCgYJBgAAAA==.',
Ru='Rubmyrott:BAAALgADCgIJAgAAAA==.Runalot:BAAALgADCgUJBQAAAA==.',
['Rê']='Rêdd:BAAALgAECgEJAQAAAA==.',
Sa='Sabeion:BAAALgAECgUJCwAAAA==.Salswarriah:BAAALgADCgkJGAAAAA==.Sanaku:BAAALgAECgIJAgAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottlee:BAAALgADCgIJBAAAAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwALAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.',
Sg='Sgtpunchy:BAAALgADCgMJBQABLgAECgIJAwALAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shamanizim:BAABLgAECn8aAAQQAAcJfxJ+MwCLAQAQAAcJfBF+MwCLAQAOAAQJDhC0HQDxAAAdAAIJIAaJKQBHAAAAAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAAALgAECggJDAAAAA==.Shinotenshi:BAAALgAECgYJCQABLgAECggJDAALAAAAAA==.Shirase:BAAALgADCgkJIwABLgAECggJHgAdADMiAA==.Shugarae:BAAALgAECgYJDAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skreezy:BAAALgAECgYJCgAAAA==.Skuls:BAAALgADCgUJBQAAAA==.',
Sl='Slashemup:BAAALgAECgYJEAAAAA==.Slayter:BAABLgAECn8ZAAICAAgJeiEUHwBHAgACAAgJeiEUHwBHAgAAAA==.',
Sn='Snakelazers:BAAALgAECggJEQAAAA==.Snufulafagus:BAAALgADCggJGAAAAA==.',
So='Soju:BAAALgAECgQJCwABLgAECgkJJAAJACUhAA==.Songwind:BAAALgAECgYJDgAAAA==.Soonie:BAAALgADCgEJAQAAAA==.',
Sq='Squishypal:BAAALgAECgUJBwAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAAALgADCgcJEQAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgADCgcJBwAAAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAAALgAECgYJDgAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Tentreeadvos:BAAALgADCggJGQABLgAECgQJBwALAAAAAA==.Tetris:BAABLgAECn8gAAIMAAgJZCHUCAAbAgAMAAgJZCHUCAAbAgAAAA==.',
Th='Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgYJBgAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJCgAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgADCgMJAwABLgAECggJHQACAIchAA==.',
Tr='Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAAALgAECggJDQAAAA==.Truthfully:BAAALgAECgMJAwAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgADCgcJDwAAAA==.',
Ug='Ugrup:BAAALgAECgEJAQAAAA==.',
Uj='Ujabula:BAAALgAECgUJCAAAAA==.',
Ul='Ulurak:BAABLgAECn8VAAMaAAcJnQwVGwAaAQAaAAYJkwkVGwAaAQACAAMJbgjkqgBxAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIhAAcJ0wd0FgBJAQAhAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAAALgAECgEJAQAAAA==.',
Va='Vallorien:BAAALgADCgkJGgAAAA==.Valsharess:BAAALgADCgcJBwABLgAECggJJgANACcYAA==.Vandix:BAAALgAECgUJBwAAAA==.',
Ve='Vegtam:BAAALgADCgcJDQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgQJAwAAAA==.',
['Và']='Vàli:BAAALgADCgMJBQAAAA==.',
Wa='Wasenshi:BAAALgADCgIJAgAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCAAAAA==.',
Wi='Wickedromeo:BAAALgADCgEJAgAAAA==.',
Xa='Xaanii:BAAALgADCgkJGgAAAA==.Xandius:BAAALgADCgcJDAAAAA==.',
Xe='Xeeria:BAABLgAECn8cAAIdAAcJVSMODQC1AgAdAAcJVSMODQC1AgAAAA==.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAICAAgJ2RbXCgCqAQACAAgJ2RbXCgCqAQAAAA==.',
Za='Zamzak:BAAALgADCgQJBAAAAA==.Zanthor:BAAALgAECgQJCgAAAA==.Zaralina:BAAALgAECggJEgAAAA==.Zartox:BAAALgAECgYJDgAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zaryssa:BAAALgAECgYJDAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDAAAAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgADCgIJAgAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAAALgAECgUJBwAAAA==.',
['Âr']='Ârc:BAAALgADCgQJBQAAAA==.',
['Èd']='Èddy:BAAALgAECgEJAQAAAA==.',
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

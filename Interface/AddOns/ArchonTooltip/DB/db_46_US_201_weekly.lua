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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Paladin-Protection','Druid-Guardian','Druid-Feral','Druid-Restoration','Unknown-Unknown','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Devourer','Warlock-Demonology','Mage-Frost','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Warrior-Fury','Druid-Balance','Hunter-Survival','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Vengeance','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Monk-Brewmaster',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8jAAIBAAgJeRh1IwD3AQABAAgJeRh1IwD3AQAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn8xAAICAAkJKxQMCgDbAQACAAkJKxQMCgDbAQAAAA==.',
Ag='Agu:BAAALgADCgcJCwAAAA==.',
Ak='Akinna:BAAALgADCgEJAQAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAABLgAECn8UAAMDAAcJBwogUQB1AQADAAcJBwogUQB1AQAEAAEJqQHdmQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJCwAAAA==.Artshell:BAABLgAECn8aAAIFAAgJjwhzLgArAQAFAAgJjwhzLgArAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8jAAIGAAgJCxeUDwDqAQAGAAgJCxeUDwDqAQAAAA==.',
Az='Azaelara:BAABLgAECn8jAAIHAAgJVgbhFQDwAAAHAAgJVgbhFQDwAAAAAA==.Azanie:BAAALgAECgIJAgAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgADCgYJCQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECgQJBAAAAA==.Bannon:BAAALgAECgMJAgAAAA==.Bartab:BAABLgAECn8iAAQIAAgJaxwoBAA9AgAIAAgJaxwoBAA9AgAJAAUJ5BLDGQArAQAKAAEJzwJM4QAjAAAAAA==.',
Be='Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgMJBQAAAA==.',
Bh='Bhoomi:BAAALgAECgEJAgAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgALAAAAAA==.Blenny:BAABLgAECn8jAAIKAAgJBwXzRwDzAAAKAAgJBwXzRwDzAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgQJBAAAAA==.',
Bo='Boyscourge:BAAALgAECgEJAwAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIMAAkJzQ6gJwB3AQAMAAkJzQ6gJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQANAG8lAA==.Brightblade:BAABLgAECn8VAAMOAAgJtBB4MAC/AQAOAAgJtBB4MAC/AQABAAUJ/CJShgBuAQABLgAFFAQJAwAPAOQOAA==.Brucetea:BAAALgAECggJEgAAAA==.Brux:BAABLgAECn8kAAIQAAkJghMgKQDBAQAQAAkJghMgKQDBAQAAAA==.',
Bu='Bubonic:BAAALgAECggJDgAAAA==.Burntt:BAAALgAECgcJDAAAAA==.Buttjeans:BAABLgAECn8VAAIQAAkJ6hWsPwAPAgAQAAkJ6hWsPwAPAgAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8WAAIKAAgJwA4AVADHAAAKAAgJwA4AVADHAAAAAA==.Chillypickle:BAABLgAECn8XAAIRAAgJZB0LaAAGAgARAAgJZB0LaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECgQJBAAAAA==.Chronichit:BAAALgAECgcJEAAAAA==.',
Cl='Cloudcaller:BAAALgAECgQJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8iAAISAAgJjRa6AgD1AQASAAgJjRa6AgD1AQAAAA==.Cochuata:BAAALgAECgYJCgAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8cAAMTAAcJwBvVNgCeAQATAAcJZxrVNgCeAQACAAQJShJdIQC5AAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAUJDQATAGkbAA==.Cripstaet:BAAALgAECgIJAgAAAA==.Crisp:BAABLgAECn8WAAMRAAYJ1xhhjwC0AQARAAYJ1xhhjwC0AQAUAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.',
Cu='Curse:BAAALgAECggJEgABLgAFFAUJDQATAGkbAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAECgcJBAAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8LAAIVAAMJ1RuCEQARAQAVAAMJ1RuCEQARAQAuAAQKfycAAxUACAlhHtgSAIQCABUACAlhHtgSAIQCABYABAnaDM8TAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgALAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAAALgAECgYJDAAAAA==.Dairydefendr:BAAALgAECgUJCgAAAA==.Damyn:BAABLgAECn8iAAIXAAgJaRu2AwBBAgAXAAgJaRu2AwBBAgAAAA==.Daniella:BAAALgAECgcJBgAAAA==.Dart:BAABLgAECn8YAAINAAgJGAg2FQAdAQANAAgJGAg2FQAdAQAAAA==.Daspanktank:BAABLgAECn8WAAICAAYJehcqEwBCAQACAAYJehcqEwBCAQAAAA==.',
De='Deathsgrace:BAABLgAECn8jAAIRAAgJdB/6FAByAgARAAgJdB/6FAByAgAAAA==.Demark:BAABLgAECn8dAAMNAAYJmxy7EABXAQANAAYJ9he7EABXAQAYAAQJ8By8JABMAQAAAA==.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgQJBAAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8YAAIBAAgJnhaZdACSAQABAAgJnhaZdACSAQAAAA==.Dezzolation:BAAALgADCggJCQAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgEJAQAAAA==.',
Dk='Dk:BAABLgAFFH8NAAMTAAUJaRt9MAA/AQATAAQJaRt9MAA/AQACAAEJAAAUKwAAAAAAAA==.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn8iAAIKAAkJiRApRwCFAQAKAAkJiRApRwCFAQAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgIJAgAAAA==.Drennifer:BAAALgAECggJEgAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECggJGAABAJ4WAA==.',
Du='Duskcandin:BAAALgADCgIJAgAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMTAAkJTxwOIQC8AgATAAkJTxwOIQC8AgACAAEJRhG/OAAxAAAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgQJBAAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.',
Fo='Fooksdk:BAAALgAECgcJBwAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgADCgQJBAAAAA==.',
Fu='Fullometal:BAABLgAECn8iAAIJAAgJjBk+BAAtAgAJAAgJjBk+BAAtAgAAAA==.Furojin:BAABLgAECn8YAAIZAAkJogUYLwDYAAAZAAkJogUYLwDYAAAAAA==.',
Ga='Galstad:BAABLgAECn8mAAQEAAgJ4CVWBAD5AQAaAAcJkRpsCQAPAgAEAAYJkSVWBAD5AQADAAIJXhdx1AAxAAAAAA==.Gazznoogg:BAAALgAECgkJBQAAAA==.',
Ge='Geff:BAAALgAECgYJCwAAAA==.',
Gh='Ghostpickle:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8VAAMXAAYJCQzzDwADAQAXAAYJCQzzDwADAQAGAAEJgQFlcgAfAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgUJDQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgUJCAAAAA==.',
Gr='Grrshhnak:BAAALgADCgQJBAAAAA==.Grumz:BAABLgAECn8WAAMbAAcJHxTcPwCBAQAbAAcJHxTcPwCBAQAGAAQJVAzJawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwARAFoSAA==.',
Ha='Habib:BAAALgAECgYJCQAAAA==.Happyflappy:BAEBLgAECn8nAAMcAAkJNhqBBwBfAgAcAAkJexmBBwBfAgAdAAMJSxpyKADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAcADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJIgAKAIkQAA==.',
He='Healforfun:BAABLgAECn8sAAIKAAkJOxmUEgA4AgAKAAkJOxmUEgA4AgAAAA==.Heilung:BAABLgAECn80AAIeAAkJ1hP4BgAMAgAeAAkJ1hP4BgAMAgAAAA==.Hellstar:BAAALgADCgcJBwAAAA==.',
Hi='Hirradee:BAACLgAFFH8IAAIPAAQJXAhsPQC5AAAPAAQJXAhsPQC5AAAuAAQKfyUAAw8ACQkaG1osAE0CAA8ACQkaG1osAE0CAB8AAgkoDBkaAFEAAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgADCgcJBwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.',
Hy='Hyacine:BAAALgAECgIJAgAAAA==.',
Ic='Icecweam:BAAALgAECgIJAgAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.',
In='Incarnate:BAAALgAECgUJBQABLgAFFAQJCAAPAFwIAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAITAAcJWBb6cQCjAQATAAcJWBb6cQCjAQAAAA==.',
Ja='Jakiichan:BAAALgAECgcJDgAAAA==.',
Ji='Jipper:BAAALgAECgUJBgAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAUJDQATAGkbAA==.',
Jy='Jym:BAEALgAECggJEAAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIgAAkJgxq1BwBKAgAgAAkJgxq1BwBKAgAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgQJBAAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAgALAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8UAAIDAAYJvAUShgCHAAADAAYJvAUShgCHAAAAAA==.Kiryanna:BAAALgAECgcJEgAAAA==.Kitiara:BAAALgADCgkJCQAAAA==.',
Kl='Klayana:BAAALgAECgYJDAAAAA==.',
Kr='Krombopulös:BAAALgAECgYJCwAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIhAAQJtxXgAwBPAQAhAAQJtxXgAwBPAQAuAAQKfx0AAiEACAn0ITUIAMgCACEACAn0ITUIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8dAAMEAAkJbxh/BgCwAQAEAAgJVhl/BgCwAQADAAEJHRJQogBPAAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAECgcJCAAAAA==.Littledirk:BAABLgAECn8hAAIVAAgJYA0TEAClAQAVAAgJYA0TEAClAQAAAA==.',
Ll='Llillies:BAAALgAECgUJDQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgIJBAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8dAAMYAAgJuyC1BQCYAgAYAAgJuyC1BQCYAgAiAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAABLgAECn8eAAIRAAkJnxwyDAC+AgARAAkJnxwyDAC+AgAAAA==.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8UAAIhAAkJnQupKwCZAQAhAAkJnQupKwCZAQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAQJCAAPAFwIAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgYJFAAXAIMTAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAEJAQAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Morkra:BAABLgAECn8UAAIYAAYJUBmSQQCeAQAYAAYJUBmSQQCeAQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAAALgAECggJDQABLgAECgkJGgAgAAYWAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn8jAAIbAAgJOhaFHgC+AQAbAAgJOhaFHgC+AQAAAA==.',
Na='Narcyon:BAABLgAECn8jAAMhAAgJ6xoNCwA2AgAhAAcJcBwNCwA2AgAjAAEJLhJATgA9AAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgcJCgAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAQAAAA==.',
Oe='Oexx:BAABLgAECn8WAAIkAAYJFR3pDwDRAQAkAAYJFR3pDwDRAQAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8VAAIMAAcJExd5GACNAQAMAAcJExd5GACNAQAAAA==.Palaadin:BAAALgAECgYJCgAAAA==.Pandicated:BAEBLgAECn8XAAMlAAgJdRMUEQC+AQAlAAgJdRMUEQC+AQAgAAMJYQ86QgBwAAABLgAECgkJGQAaAPoUAA==.',
Pe='Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8QAAIKAAQJ3BceFQAmAQAKAAQJ3BceFQAmAQAuAAQKfyAAAgoACAlOIvUMANUCAAoACAlOIvUMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIKAAcJKxfDMQDjAQAKAAcJKxfDMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8XAAMDAAYJDx2/LACcAQADAAYJDx2/LACcAQAEAAUJPQY8XQDNAAAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwALAAAAAA==.Prídè:BAAALgAECggJDAAAAA==.',
Qu='Quj:BAAALgAECgIJAgAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8UAAIKAAYJsg1pQQANAQAKAAYJsg1pQQANAQAAAA==.Raveñna:BAAALgAECgUJCAAAAA==.Rawrina:BAABLgAECn8UAAIZAAkJSQ1QLQCZAQAZAAkJSQ1QLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8qAAIRAAkJOxV6IQAjAgARAAkJOxV6IQAjAgABLgAECgMJAwALAAAAAA==.Risto:BAABLgAECn8jAAIQAAgJhiJ7CgCiAgAQAAgJhiJ7CgCiAgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8jAAIkAAgJDhQ+BQCrAQAkAAgJDhQ+BQCrAQAAAA==.Roody:BAAALgAECggJDQABLgAECgkJIgAKAIkQAA==.Rouein:BAAALgAECgEJAQAAAA==.',
Ry='Ryaala:BAAALgADCgQJBAAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgIJAgAAAA==.Sandroin:BAAALgAECgYJDQAAAA==.Sarah:BAAALgADCgIJAgABLgAECgkJLgAFAMsbAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8bAAIDAAgJXQ+nLQCXAQADAAgJXQ+nLQCXAQAAAA==.Shock:BAAALgAECgcJEwAAAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgEJAQAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAgAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAECgQJBAAAAA==.Soul:BAABLgAECn8xAAIZAAkJ8R7uAgDmAgAZAAkJ8R7uAgDmAgAAAA==.Sovietpanda:BAAALgAECgcJDAAAAA==.',
Sp='Spanky:BAAALgAECggJDwAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAUJDQATAGkbAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAIQAAkJvBj2MgBAAgAQAAkJvBj2MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAIHAAkJ7Q5AFQD3AAAHAAkJ7Q5AFQD3AAAAAA==.',
Ta='Taek:BAABLgAFFH8IAAITAAQJrw6rMAA+AQATAAQJrw6rMAA+AQAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAAALgAECgcJCwAAAA==.',
Te='Tehblink:BAAALgAECgQJBAAAAA==.Terah:BAAALgADCgEJAgAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAAALgAECgQJCwAAAA==.Trea:BAAALgADCgQJBAAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8nAAIjAAgJ+yBMBACmAgAjAAgJ+yBMBACmAgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMdAAgJHRxDAgAzAgAdAAgJExxDAgAzAgAcAAcJ1hYLMABFAQAAAA==.Warpfiend:BAABLgAECn8fAAIGAAgJOx+3CQA+AgAGAAgJOx+3CQA+AgAAAA==.',
We='Weid:BAAALgAECggJDAAAAA==.',
Wh='Whammy:BAAALgAECgUJEwAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgADCgcJBwAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIKAAcJ0A4vNQBEAQAKAAcJ0A4vNQBEAQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8TAAIPAAUJCRgfGQBFAQAPAAUJCRgfGQBFAQAuAAQKfyIAAg8ACAlWHe8kAHUCAA8ACAlWHe8kAHUCAAAA.',
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

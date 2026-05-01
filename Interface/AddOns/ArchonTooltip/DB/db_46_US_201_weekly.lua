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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Paladin-Protection','Druid-Feral','Druid-Guardian','Druid-Restoration','Unknown-Unknown','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Devourer','Warlock-Demonology','Mage-Frost','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Warrior-Fury','Druid-Balance','Hunter-Survival','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warlock-Destruction','Monk-Brewmaster','Priest-Shadow',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8bAAIBAAcJYBmUMACAAQABAAcJYBmUMACAAQAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn8oAAICAAkJcBNaBwCqAQACAAkJcBNaBwCqAQAAAA==.',
Ag='Agu:BAAALgADCgYJCgAAAA==.',
Ak='Akinna:BAAALgADCgEJAQAAAA==.',
Al='Alaran:BAAALgADCgMJAwAAAA==.Alaysia:BAAALgADCgkJCgAAAA==.Alestair:BAABLgAECn8UAAMDAAcJBwohUQB1AQADAAcJBwohUQB1AQAEAAEJqQHRmQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJCwAAAA==.Artshell:BAABLgAECn8aAAIFAAgJjQh3LgArAQAFAAgJjQh3LgArAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8VAAIGAAgJEBQmDgC9AQAGAAgJEBQmDgC9AQAAAA==.',
Az='Azaelara:BAABLgAECn8bAAIHAAcJowWpFQC8AAAHAAcJowWpFQC8AAAAAA==.Azanie:BAAALgADCgkJGQAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgADCgYJCQAAAA==.Bakasura:BAAALgADCgkJEgAAAA==.Bankhand:BAAALgAECgQJBAAAAA==.Bannon:BAAALgAECgMJAgAAAA==.Bartab:BAABLgAECn8aAAQIAAgJRQ3CGQArAQAIAAUJ5BLCGQArAQAJAAgJcQkQEQCoAAAKAAEJzwJF4QAjAAAAAA==.',
Be='Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgEJAQAAAA==.',
Bh='Bhoomi:BAAALgAECgEJAQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJCAALAAAAAA==.Blenny:BAABLgAECn8bAAIKAAcJSwVdQADPAAAKAAcJSwVdQADPAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgQJBAAAAA==.',
Bo='Boyscourge:BAAALgAECgEJAgAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8aAAIMAAgJqg+fJwB3AQAMAAgJqg+fJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECggJKAANAEIlAA==.Brightblade:BAABLgAECn8VAAMOAAgJtBB2MAC/AQAOAAgJtBB2MAC/AQABAAUJ/CJQhgBuAQABLgAFFAQJAwAPACcOAA==.Brucetea:BAAALgAECgYJCgAAAA==.Brux:BAABLgAECn8eAAIQAAgJoBRtLAB7AQAQAAgJoBRtLAB7AQAAAA==.',
Bu='Bubonic:BAAALgAECgYJBgAAAA==.Burntt:BAAALgAECgcJCQAAAA==.Buttjeans:BAABLgAECn8VAAIQAAkJ6xWxPwAPAgAQAAkJ6xWxPwAPAgAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgMJCQAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8UAAIKAAgJsw5DQgDIAAAKAAgJsw5DQgDIAAAAAA==.Chillypickle:BAABLgAECn8VAAIRAAgJYR0QaAAGAgARAAgJYR0QaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECgQJBAAAAA==.Chronichit:BAAALgAECgMJAwAAAA==.',
Cl='Cloudcaller:BAAALgAECgQJDQAAAA==.',
Co='Cobrakai:BAABLgAECn8bAAISAAgJwBJvAgDAAQASAAgJwBJvAgDAAQAAAA==.Cochuata:BAAALgAECgEJAQAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8XAAMCAAcJwRuLFwDBAAATAAcJIBrlYgDfAAACAAQJQhKLFwDBAAAAAA==.Cripstaet:BAAALgADCgkJGQAAAA==.Crisp:BAABLgAECn8WAAMRAAYJ1xhljwC0AQARAAYJ1xhljwC0AQAUAAEJZgvoHwAwAAAAAA==.Crow:BAAALgAECgIJAgAAAA==.',
Cu='Curse:BAAALgAECgYJDwABLgAFFAUJDAATAGUbAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAECgcJBAAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8FAAIVAAMJhgoOEADvAAAVAAMJhgoOEADvAAAuAAQKfyYAAxUACAn2HTYGABYCABUACAn2HTYGABYCABYABAnaDM4TAMMAAAAA.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAAALgAECgUJCwAAAA==.Dairydefendr:BAAALgAECgUJCQAAAA==.Damyn:BAABLgAECn8aAAIXAAgJYhiyBADeAQAXAAgJYhiyBADeAQAAAA==.Dart:BAABLgAECn8VAAINAAgJFwh5EAAaAQANAAgJFwh5EAAaAQAAAA==.Daspanktank:BAABLgAECn8VAAICAAYJ/RSiDgApAQACAAYJ/RSiDgApAQAAAA==.',
De='Deathsgrace:BAABLgAECn8bAAIRAAcJRR4NHQD9AQARAAcJRR4NHQD9AQAAAA==.Demark:BAABLgAECn8WAAMYAAYJlhznGgBZAQAYAAQJ7BznGgBZAQANAAYJ8BeQEQAMAQAAAA==.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgMJAwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8WAAIBAAcJehSXdACSAQABAAcJehSXdACSAQAAAA==.Dezzolation:BAAALgADCggJCQAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgADCgMJBAAAAA==.',
Dk='Dk:BAABLgAFFH8MAAMTAAUJZRslGwBKAQATAAQJZRslGwBKAQACAAEJAABFIAAAAAAAAA==.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn8gAAIKAAkJZw8uRwCFAQAKAAkJZw8uRwCFAQAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgIJAgAAAA==.Drennifer:BAAALgAECgYJCgAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgcJFgABAHoUAA==.',
Du='Duskcandin:BAAALgADCgIJAgAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMTAAkJSxwRIQC8AgATAAkJSxwRIQC8AgACAAEJQBFZKwAyAAAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgEJAQAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.',
Fo='Fooksdk:BAAALgAECgcJBwAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJAQAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgADCgQJBAAAAA==.',
Fu='Fullometal:BAABLgAECn8aAAIIAAcJURgxBgCoAQAIAAcJURgxBgCoAQAAAA==.Furojin:BAABLgAECn8XAAIZAAgJ8wWtKgC3AAAZAAgJ8wWtKgC3AAAAAA==.',
Ga='Galstad:BAABLgAECn8kAAQEAAgJuiXqAgAMAgAEAAYJkCXqAgAMAgAaAAcJBhprBgAIAgADAAIJXhdv1AAxAAAAAA==.',
Ge='Geff:BAAALgAECgYJCgAAAA==.',
Gh='Ghostpickle:BAAALgADCgIJAgABLgAECgYJCAALAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8UAAMXAAYJCAxbDAAUAQAXAAYJCAxbDAAUAQAGAAEJgQEUWwAgAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgQJCAAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgMJAwAAAA==.',
Gr='Grumz:BAABLgAECn8WAAMbAAcJHxTePwCBAQAbAAcJHxTePwCBAQAGAAQJUwzKawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwAAAA==.',
Ha='Habib:BAAALgAECgYJCAAAAA==.Happyflappy:BAEBLgAECn8gAAMcAAgJwhuDBwAaAgAcAAgJ6xqDBwAaAgAdAAMJSxp3KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECggJIAAcAMIbAA==.Harambe:BAAALgADCgUJBQABLgAECgkJIAAKAGcPAA==.',
He='Healforfun:BAABLgAECn8mAAIKAAkJYhU/FwDIAQAKAAkJYhU/FwDIAQAAAA==.Heilung:BAABLgAECn8uAAIeAAkJkhF/BgDgAQAeAAkJkhF/BgDgAQAAAA==.Hellstar:BAAALgADCgcJBwAAAA==.',
Hi='Hirradee:BAACLgAFFH8FAAIPAAMJuAlkNACLAAAPAAMJuAlkNACLAAAuAAQKfyMAAg8ACQkaG2EsAE0CAA8ACQkaG2EsAE0CAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hugebubbles:BAAALgADCgcJCQAAAA==.',
Hy='Hyacine:BAAALgADCgkJCQAAAA==.',
Ic='Icecweam:BAAALgADCgkJGQAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.',
In='Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAITAAcJWBb7cQCjAQATAAcJWBb7cQCjAQAAAA==.',
Ji='Jipper:BAAALgADCgYJBgAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAUJDAATAGUbAA==.',
Jy='Jym:BAEALgAECggJEAAAAA==.',
Ka='Kaijin:BAABLgAECn8nAAIfAAgJ0xnaCADuAQAfAAgJ0xnaCADuAQAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgQJBAAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Kelaya:BAAALgAECgMJBQAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAECggJDQALAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAAALgAECgkJEwAAAA==.Kiryanna:BAAALgAECgYJCwAAAA==.Kitiara:BAAALgADCgkJCQAAAA==.',
Kl='Klayana:BAAALgAECgYJDAAAAA==.',
Kr='Krombopulös:BAAALgAECgYJCwAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIgAAQJtxXfAwBPAQAgAAQJtxXfAwBPAQAuAAQKfx0AAiAACAn0ITgIAMgCACAACAn0ITgIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8aAAIEAAcJDxzoBQCXAQAEAAcJDxzoBQCXAQAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAECgcJCAAAAA==.Littledirk:BAABLgAECn8aAAIVAAgJ8wnBMACBAQAVAAgJ8wnBMACBAQAAAA==.',
Ll='Llillies:BAAALgAECgQJBAAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgADCgUJCQAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAAALgAFFAEJAgAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAAALgAECgkJEgAAAA==.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8UAAIgAAkJmwulKwCZAQAgAAkJmwulKwCZAQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgYJDgALAAAAAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAEJAQAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Morkra:BAAALgAECgYJEwAAAA==.Morte:BAAALgAECgYJCAAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAAALgAECggJDQABLgAECgcJEAALAAAAAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn8jAAIbAAgJOBZpFADJAQAbAAgJOBZpFADJAQAAAA==.',
Na='Narcyon:BAABLgAECn8hAAIgAAcJbhzhBgBGAgAgAAcJbhzhBgBGAgAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Noahdh:BAACLgAFFH8SAAIPAAUJYCOfAwC3AQAPAAUJYCOfAwC3AQAuAAQKfyIAAg8ACAk/IjUOAA0DAA8ACAk/IjUOAA0DAAAA.Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgYJCAAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAQAAAA==.',
Oe='Oexx:BAABLgAECn8WAAIhAAYJFh3wBACBAQAhAAYJFh3wBACBAQAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAAALgAECgYJEwAAAA==.Palaadin:BAAALgAECgYJCgAAAA==.Pandicated:BAEBLgAECn8VAAMiAAgJuxI/DADFAQAiAAgJuxI/DADFAQAfAAMJVA9eMgBzAAAAAA==.',
Pe='Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8LAAIKAAQJ+BSSDwAjAQAKAAQJ+BSSDwAjAQAuAAQKfyAAAgoACAlMIvkMANUCAAoACAlMIvkMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIKAAcJKxfIMQDjAQAKAAcJKxfIMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8XAAMDAAYJDh01HQCwAQADAAYJDh01HQCwAQAEAAUJPQYqXQDNAAAAAA==.',
Pr='Prettypatty:BAAALgADCgcJEwAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwALAAAAAA==.Prídè:BAAALgAECgYJCgAAAA==.',
Qu='Quj:BAAALgADCgkJEAAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCQAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAAALgAECgYJDgAAAA==.Raveñna:BAAALgAECgUJCAAAAA==.Rawrina:BAABLgAECn8UAAIZAAkJRw1LLQCZAQAZAAkJRw1LLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8hAAIRAAgJXhbaJQDPAQARAAgJXhbaJQDPAQABLgAECgMJAwALAAAAAA==.Risto:BAABLgAECn8bAAIQAAcJaCE9EAAlAgAQAAcJaCE9EAAlAgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8bAAIhAAcJOhQxBQB5AQAhAAcJOhQxBQB5AQAAAA==.Roody:BAAALgAECgYJBgABLgAECgkJIAAKAGcPAA==.',
Ry='Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgADCgkJDwAAAA==.Sandroin:BAAALgAECgYJDQAAAA==.',
Sc='Scarf:BAAALgAECgEJAQAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgADCgMJBAABLgAECgYJCAALAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8WAAIDAAcJuw7cKwBkAQADAAcJuw7cKwBkAQAAAA==.Shock:BAAALgAECgcJEgAAAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgADCgEJAQAAAA==.',
Sk='Skipuscales:BAAALgAECgkJCwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.',
So='Soul:BAABLgAECn8oAAIZAAkJLhyNAgC/AgAZAAkJLhyNAgC/AgAAAA==.Sovietpanda:BAAALgAECgYJCwAAAA==.',
Sp='Spanky:BAAALgAECggJDwAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAUJDAATAGUbAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8fAAIQAAgJKRr3MgBAAgAQAAgJKRr3MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8eAAIHAAkJPg4WEQDyAAAHAAkJPg4WEQDyAAAAAA==.',
Ta='Taek:BAAALgAFFAQJBAAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAAALgAECgcJCwAAAA==.',
Te='Tehblink:BAAALgAECgQJBAAAAA==.Terah:BAAALgADCgEJAgAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAAALgAECgQJCAAAAA==.Trea:BAAALgADCgQJBAAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8kAAIjAAgJhR9lAwCFAgAjAAgJhR9lAwCFAgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJCwAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCQAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMdAAgJDRxnAQBBAgAdAAgJAxxnAQBBAgAcAAcJ2RYOMABFAQAAAA==.Warpfiend:BAABLgAECn8cAAIGAAYJvx9qEQCWAQAGAAYJvx9qEQCWAQAAAA==.',
We='Weid:BAAALgAECgMJAwAAAA==.',
Wh='Whammy:BAAALgAECgQJDwAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzturtlezz:BAABLgAECn8UAAIKAAYJFQ8rMAAcAQAKAAYJFQ8rMAAcAQAAAA==.',
['Än']='Änorack:BAAALgADCggJCAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8SAAIPAAUJmhezDQBIAQAPAAUJmhezDQBIAQAuAAQKfyIAAg8ACAkaHfQkAHUCAA8ACAkaHfQkAHUCAAAA.',
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

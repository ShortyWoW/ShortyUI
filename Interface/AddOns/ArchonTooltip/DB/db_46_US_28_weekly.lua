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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','Paladin-Protection','Druid-Balance','Priest-Discipline','Warrior-Protection','Warrior-Fury','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Monk-Mistweaver','Paladin-Holy','Druid-Guardian','Shaman-Restoration','DeathKnight-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Rogue-Assassination','Druid-Feral','Warlock-Demonology','Hunter-Survival','Shaman-Enhancement',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abfuscatedd:BAAALgAECgcJEwAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJEAABAAAAAA==.Acidrain:BAABLgAECn8YAAICAAcJlhsABwCYAQACAAcJlhsABwCYAQAAAA==.Acmiax:BAAALgAECgUJDAAAAA==.',
Ad='Adar:BAAALgADCgcJBwAAAA==.',
Ah='Ahrmanhamma:BAABLgAECn8WAAIDAAgJNyDpAgCFAgADAAgJNyDpAgCFAgAAAA==.Ahu:BAABLgAECn8iAAMEAAcJNxkvMADwAQAEAAcJNxkvMADwAQAFAAMJZAQIcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgIJAgAAAA==.',
Al='Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgIJAgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn8hAAMFAAgJMg5JNQCSAQAFAAgJnwxJNQCSAQAEAAQJVwZEJQDZAAAAAA==.Alexander:BAABLgAECn8eAAIGAAkJhhryJgDXAgAGAAkJhhryJgDXAgAAAA==.Alexijones:BAAALgAECgcJEgAAAA==.',
Am='Ambassador:BAAALgAECgcJEwAAAA==.Amoondai:BAACLgAFFH8HAAIHAAMJWw5fCADiAAAHAAMJWw5fCADiAAAuAAQKfywAAgcACQn/IfEAAMgCAAcACQn/IfEAAMgCAAAA.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8eAAMIAAcJ6R/bAQAYAgAIAAcJ6R/bAQAYAgAJAAYJ7wNS0gDcAAAAAA==.Apolyon:BAABLgAECn8eAAIKAAgJSR4mBABQAgAKAAgJSR4mBABQAgAAAA==.',
Ar='Araon:BAAALgADCgEJAgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
At='Atroxz:BAAALgADCgIJAgAAAA==.',
Ba='Bacstabath:BAABLgAECn8jAAILAAkJoBwVBgAwAwALAAkJoBwVBgAwAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAECggJFgADADcgAA==.Banshee:BAAALgAECgcJEwAAAA==.',
Be='Becca:BAABLgAECn8bAAIMAAcJghbEEAC6AQAMAAcJghbEEAC6AQAAAA==.',
Bi='Bigdamaj:BAABLgAECn8ZAAIJAAgJUxS/XQDZAQAJAAgJUxS/XQDZAQAAAA==.Birbdormu:BAAALgAECgQJBAABLgAECggJGAANAAAdAA==.',
Bl='Bloodios:BAABLgAECn8cAAIIAAgJrBBoBgA9AQAIAAgJrBBoBgA9AQAAAA==.',
Bo='Bobin:BAAALgADCgcJBwABLgAECgcJEgABAAAAAA==.Bobinforapl:BAAALgAECgcJEgAAAA==.Bombadil:BAABLgAECn8YAAIOAAcJ/wKODAD3AAAOAAcJ/wKODAD3AAAAAA==.',
Br='Bribage:BAABLgAECn8YAAINAAgJAB2QAwD4AQANAAgJAB2QAwD4AQAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgQJBAABLgAECgcJCQABAAAAAA==.Budderwar:BAABLgAECn8hAAMPAAgJyiKRAACsAgAPAAgJyiKRAACsAgAQAAMJvw7xhgCjAAAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgEJAQAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.',
Cb='Cbreezy:BAAALgAECgEJAQAAAA==.',
Ce='Celjska:BAAALgADCgIJAgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAAALgAECgYJDQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.',
Ci='Cinderspella:BAAALgADCgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8VAAIRAAcJpiRDAQBuAgARAAcJpiRDAQBuAgAAAA==.',
Co='Cocoredbull:BAAALgAECgcJEgAAAA==.Correin:BAABLgAECn8XAAMSAAcJVQxjKgByAQASAAcJVQxjKgByAQATAAIJ7QRZVQArAAAAAA==.',
Cr='Craszhin:BAAALgAECgIJAwAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn8cAAIGAAgJ6gtMIABUAQAGAAgJ6gtMIABUAQAAAA==.',
Da='Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.',
De='Deets:BAABLgAECn8VAAIEAAcJAB/LBwDsAQAEAAcJAB/LBwDsAQAAAA==.Defoy:BAAALgAFFAEJAQAAAA==.Demona:BAABLgAECn8YAAIUAAcJegk1BAAaAQAUAAcJegk1BAAaAQAAAA==.Demonicfates:BAAALgAECgYJEAAAAA==.Derffy:BAAALgAECgUJCwAAAA==.Descalabrada:BAAALgAECgQJCAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Dm='Dmt:BAABLgAECn8XAAIVAAgJDxeNGQDwAQAVAAgJDxeNGQDwAQAAAA==.',
Do='Dotemdown:BAAALgADCgQJCgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadx:BAAALgAECgYJCwAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJGwAWALYiAA==.Drpeppers:BAABLgAECn8XAAMKAAcJ1AWLGgDkAAAKAAcJ1AWLGgDkAAAXAAEJAAAOPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgEJAwAAAA==.',
Ec='Eclair:BAABLgAECn8YAAMYAAcJ9RDlEAA3AQAYAAcJ9RDlEAA3AQACAAEJdBe4JABCAAAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgADCgcJBwABLgAECgkJIwALAKAcAA==.',
El='Eleysia:BAAALgADCgUJBgAAAA==.Elmos:BAABLgAECn8eAAIRAAkJDB0JCAD5AgARAAkJDB0JCAD5AgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgYJDgABAAAAAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECggJFgACAGsbAA==.Evilmonkeysh:BAEBLgAECn8WAAMCAAgJaxtaHAAvAgACAAgJaxtaHAAvAgAYAAcJQQviTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECggJFgACAGsbAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8WAAISAAcJZxDbBgBGAQASAAcJZxDbBgBGAQAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgEJAQAAAA==.Fergis:BAABLgAECn8YAAIGAAcJ+SLSBgA/AgAGAAcJ+SLSBgA/AgAAAA==.Fetchme:BAAALgAECgMJAwAAAA==.Fetchyou:BAAALgADCgcJCgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8UAAMIAAgJPBU6EgDoAQAIAAgJLBU6EgDoAQAZAAYJsxRBCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECgcJDwAAAA==.',
Fr='Freecaster:BAAALgADCgYJBgAAAA==.Frostybeary:BAAALgADCgcJFwAAAA==.Frostymonk:BAAALgAECgYJEAAAAA==.Frozenwaffle:BAAALgADCgEJAQABLgAECggJGwAaAKgcAA==.',
Fu='Furryben:BAAALgADCgYJEwAAAA==.',
Ga='Galeste:BAAALgAECgQJBAAAAA==.',
Gi='Gigem:BAAALgAECgMJAwAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQbAAkJkASPIwBcAQAbAAkJkASPIwBcAQAcAAUJ9gPvSgCoAAAdAAEJlQGECgAfAAAAAA==.',
Go='Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8bAAMaAAgJqBwNDQCyAgAaAAgJqBwNDQCyAgAHAAYJUxO1NQBmAQAAAA==.Grôg:BAAALgAECgQJAwAAAA==.',
Gu='Guldaniel:BAAALgADCgkJHgAAAA==.Guthx:BAAALgAECgcJEwAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgABAAAAAA==.',
Ho='Holymolii:BAAALgAECgYJEAAAAA==.Hotcoffee:BAAALgAECgUJCAAAAA==.',
Hu='Huntermaster:BAAALgAECgUJDAABLgAECggJIQAPAMoiAA==.',
In='Incredabull:BAAALgAECgQJBwAAAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAAALgAECgcJEwAAAA==.Istayblunted:BAABLgAECn8YAAIMAAYJkx4PEADEAQAMAAYJkx4PEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDAAAAA==.',
Ji='Jiayerah:BAAALgADCgkJDAABLgAECgQJCQABAAAAAA==.Jinkuzo:BAABLgAECn8YAAIeAAcJTSGUAgAoAgAeAAcJTSGUAgAoAgAAAA==.Jinmu:BAABLgAECn8VAAILAAcJNBN6CQA/AQALAAcJNBN6CQA/AQAAAA==.',
Ju='Juggie:BAAALgAECgYJEAAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8aAAIfAAgJLAr7AgBYAQAfAAgJLAr7AgBYAQAAAA==.',
Ka='Kagami:BAAALgADCgMJAwAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAAALgAECgQJCwAAAA==.',
Ki='Kickerr:BAAALgADCgcJBwABLgAECgkJHQAeAE8YAA==.',
Kl='Klum:BAAALgADCgcJEwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJCwAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgADCggJBQAAAA==.Lendela:BAAALgAECgMJAwAAAA==.',
Li='Liljugg:BAAALgAECgMJBgAAAA==.',
Lo='Lor:BAAALgAECgQJBQAAAA==.Lostmana:BAAALgADCgUJBQAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Ly='Lygor:BAAALgAECgcJEAAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJGwAWALYiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Majellan:BAAALgAECgMJAwAAAA==.Makrub:BAAALgAECggJDQAAAA==.Mandigosa:BAAALgADCgcJDAAAAA==.Marist:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8UAAIaAAgJLxdEBADcAQAaAAgJLxdEBADcAQAAAA==.',
Mc='Mcpeepants:BAAALgADCgcJCQABLgAECggJFgADADcgAA==.',
Me='Meqi:BAAALgAECgQJCQAAAA==.',
Mi='Mikàsa:BAAALgAECgYJDgAAAA==.Minand:BAAALgAECgYJEAAAAA==.Mindlessness:BAABLgAECn8cAAIQAAgJWh8OAwAjAgAQAAgJWh8OAwAjAgAAAA==.Mineralelf:BAABLgAECn8aAAIEAAgJJApWVABrAQAEAAgJJApWVABrAQAAAA==.Minichaos:BAAALgAECgYJDAAAAA==.Miriam:BAAALgAECgQJCgAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8bAAIWAAgJtiIuBwD5AgAWAAgJtiIuBwD5AgAAAA==.',
Mo='Mojosavage:BAAALgAECgMJBQAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAQAAAA==.Mortshan:BAAALgAECgYJEAAAAA==.',
My='Mysticalfox:BAAALgAECgMJAgAAAA==.',
Na='Nalfilas:BAAALgAECgQJBgAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgADCgMJAwAAAA==.',
No='Nornee:BAAALgAECgYJCwAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8XAAIgAAcJuhwpAgDIAQAgAAcJuhwpAgDIAQAAAA==.',
['Nà']='Nàtureswrath:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAAALgAECgYJEAAAAA==.',
Ol='Ollïee:BAAALgAECgUJBQAAAA==.',
Or='Orceo:BAABLgAECn8XAAIEAAgJ8SHIBQAxAwAEAAgJ8SHIBQAxAwAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwAAAA==.',
Ox='Oxcanor:BAAALgADCgkJDwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJGwAWALYiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAIhAAYJkh+5TgDcAQAhAAYJkh+5TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECggJIQAPAMoiAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8bAAICAAkJrQa3MwCKAQACAAkJrQa3MwCKAQAAAA==.Popple:BAABLgAECn8XAAIQAAcJ6AdjDwA0AQAQAAcJ6AdjDwA0AQAAAA==.Potential:BAAALgAECggJEQAAAA==.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgEJAgAAAA==.',
Qa='Qaccy:BAAALgAECgYJDwAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAAALgAECgYJEAAAAA==.',
Ra='Radaghast:BAAALgADCgUJCQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Reishirome:BAAALgADCgkJJQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8WAAIXAAgJmiAaAwDlAgAXAAgJmiAaAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8VAAINAAYJHgWrEwDDAAANAAYJHgWrEwDDAAAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgADCgEJAQAAAA==.',
Ru='Rumincoke:BAAALgADCgQJBAAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAAALgAECgQJCQAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwABAAAAAA==.Savrille:BAABLgAECn8YAAIJAAYJ6B6wEgB9AQAJAAYJ6B6wEgB9AQAAAA==.',
Sc='Scalygrob:BAAALgAECgYJCAAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8aAAIOAAgJ8BPjBQCnAQAOAAgJ8BPjBQCnAQAAAA==.',
Sh='Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgIJAgAAAA==.',
Sm='Smogcheck:BAABLgAECn8aAAMbAAgJFRFgGwCtAQAbAAcJlRFgGwCtAQAdAAEJewjHPgA0AAAAAA==.',
Sn='Snackcake:BAAALgAECgYJEAAAAA==.Snakeoil:BAAALgAECgcJEgAAAA==.Snowws:BAABLgAECn8bAAITAAgJyBn7CQDTAQATAAgJyBn7CQDTAQAAAA==.',
So='Sortis:BAABLgAECn8bAAIGAAkJmRbaMwCjAgAGAAkJmRbaMwCjAgAAAA==.',
Sp='Spongerunner:BAAALgAECgQJCAAAAA==.Sprucetea:BAAALgADCgIJAgAAAA==.',
St='Steck:BAAALgAECgUJDwAAAA==.Strigo:BAABLgAFFH8FAAQEAAIJ/RStIABfAAAEAAEJIxmtIABfAAAiAAEJ2BCxBgBeAAAFAAEJnwydKABKAAAAAA==.',
Su='Subway:BAAALgAECgQJBAAAAA==.Sunbaby:BAAALgAECgYJEAAAAA==.',
['Sà']='Sàlís:BAAALgADCgUJBQAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8aAAIOAAgJByJFBQD9AgAOAAgJByJFBQD9AgAAAA==.Talas:BAABLgAECn8dAAMEAAkJshlJDwDBAgAEAAkJshlJDwDBAgAFAAUJswrgVwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thieridan:BAAALgADCgIJAwAAAA==.Thrann:BAABLgAECn8YAAIJAAcJqCK2CADyAQAJAAcJqCK2CADyAQAAAA==.Thunderdex:BAABLgAECn8ZAAITAAkJjhloHACoAgATAAkJjhloHACoAgAAAA==.',
Ti='Tirium:BAAALgADCgYJCgAAAA==.',
To='Togglesmith:BAAALgADCgEJAQAAAA==.Togglestein:BAAALgADCgUJCAAAAA==.Togglethorp:BAAALgADCgYJBgAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgMJAwAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJBwAAAA==.',
Va='Vaadboolin:BAAALgAECgcJDgAAAA==.Vallius:BAAALgAECgcJEgAAAA==.',
Ve='Verðandi:BAAALgADCgcJCwAAAA==.',
Vo='Volcano:BAAALgAECgcJEAAAAA==.Volvox:BAAALgADCgEJAQAAAA==.',
Vy='Vyxenn:BAABLgAECn8aAAMYAAcJIQ3zQwByAQAYAAcJIQ3zQwByAQACAAEJTQObkAAnAAAAAA==.',
Wa='Waffletoast:BAAALgADCgcJBwABLgAECggJGwAaAKgcAA==.Wanders:BAAALgAECgYJDAAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAABLgAECn8UAAIDAAkJmSFpAAAxAwADAAkJmSFpAAAxAwAAAA==.Yesenìa:BAAALgADCgEJAQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zazreal:BAABLgAECn8YAAMdAAcJ1h3GAAAKAgAdAAcJ1h3GAAAKAgAcAAMJ4Q9ZSwCmAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn8YAAIjAAcJtwRZBwACAQAjAAcJtwRZBwACAQAAAA==.Zillyanna:BAAALgAECgYJBwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zywol:BAABLgAECn8ZAAMNAAcJkheZCQBUAQANAAcJkheZCQBUAQAKAAMJlga9pgB6AAAAAA==.',
['Ër']='Ëresta:BAAALgAECgYJDgAAAA==.',
['Ðe']='Ðespair:BAABLgAECn8mAAQOAAgJgSAhCgCWAgAOAAcJPSEhCgCWAgAaAAcJzhl8IADUAQAHAAUJlhg8DgAMAQAAAA==.',
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

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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Warrior-Protection','Evoker-Devastation','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','Hunter-Marksmanship','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8bAAIBAAYJPiCrVQDhAQABAAYJPiCrVQDhAQAAAA==.',
Ad='Adaila:BAABLgAECn8jAAICAAgJNQklJwCfAQACAAgJNQklJwCfAQAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJBQADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgMJBAAAAA==.Aiir:BAABLgAECn8XAAIBAAgJSQrzVgBEAQABAAgJSQrzVgBEAQAAAA==.',
Aj='Ajaki:BAAALgAECgYJEQAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgADCgQJBAAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgEJAQAAAA==.Ambridgerose:BAAALgAECgQJCgAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgEJAQAAAA==.Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECggJDgAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgMJAwAAAA==.Arlan:BAAALgAECggJDwAAAA==.Arlequin:BAABLgAECn8XAAMEAAcJrQjqZADUAAAEAAcJrQjqZADUAAAFAAEJAAAdfwAUAAAAAA==.Arnagan:BAAALgAECgIJAgAAAA==.',
As='Asharothh:BAABLgAECn8eAAIGAAkJ6ho4FgASAgAGAAkJ6ho4FgASAgAAAA==.Ashdem:BAAALgAECgYJCwAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAAALgAECgYJCAAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABoMAA==.',
Az='Azariel:BAABLgAECn8lAAQHAAkJyg40KgChAQAHAAkJyg40KgChAQACAAEJ8gdSVQAwAAAIAAEJZwHJXgAjAAAAAA==.Azorahai:BAABLgAECn8fAAIJAAYJRAjhdwDyAAAJAAYJRAjhdwDyAAAAAA==.Azshalia:BAAALgAECgUJCwAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8VAAQKAAYJCg/8CgC8AAALAAYJpA3pNQBgAQAKAAQJiQf8CgC8AAAMAAIJRg0fEwByAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8YAAMFAAcJKxf2DgCSAQAFAAYJNRr2DgCSAQAEAAYJkgg4kQD9AAAAAA==.Banilibug:BAABLgAECn8bAAINAAgJ3xArKACxAQANAAgJ3xArKACxAQAAAA==.',
Be='Benimaru:BAAALgAECgEJAgAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8kAAMOAAkJdCXnAAAOAwAOAAcJviXnAAAOAwAPAAgJ5h2RDACLAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJJQAQADgmAA==.',
Bo='Bobbybrady:BAABLgAECn8WAAIRAAgJ9RpxCgAyAgARAAgJ9RpxCgAyAgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAAALgAECgcJEAAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAAALgADCgkJEgAAAA==.Bosshog:BAABLgAECn8rAAIBAAkJViKkAwAcAwABAAkJViKkAwAcAwAAAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8GAAISAAUJdh8ZBgAIAQASAAUJdh8ZBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJJQAQADgmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bupropion:BAAALgAECgYJEQABLgAECgkJKQATABAdAA==.Bushwhacker:BAAALgAECgYJEQAAAA==.Butterbean:BAABLgAECn8kAAINAAkJ0x93CwDnAgANAAkJ0x93CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECgYJDAAAAA==.Catameringue:BAAALgAECgMJBgAAAA==.',
Ch='Chicxulub:BAAALgADCgcJBwAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABoMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8oAAMUAAkJAR9BCQDjAgAUAAkJAR9BCQDjAgARAAYJBhFsJwAhAQAAAA==.',
Co='Coaca:BAABLgAECn8bAAMBAAgJihq8GwAiAgABAAgJihq8GwAiAgAVAAEJEQfmaQAoAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAECggJGQAPAKsZAA==.Confluent:BAABLgAECn8sAAIWAAkJQyWBAADPAwAWAAkJQyWBAADPAwAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn8qAAIXAAgJORLuGwBUAQAXAAgJORLuGwBUAQAAAA==.',
Cy='Cythrandir:BAAALgAECgYJCwABLgAFFAMJCAAYADoUAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davdk:BAAALgAECgQJBAABLgAECgYJBwADAAAAAA==.',
Dd='Ddccssff:BAAALgAECgQJBwAAAA==.',
De='Deathcoiled:BAAALgAECgYJCgAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn8UAAMTAAYJSgKoEAB3AAATAAYJSgKoEAB3AAAZAAEJWgFbZwAPAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8eAAIaAAcJHxqqEwDPAQAaAAcJHxqqEwDPAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgADCgYJCAAAAA==.',
Do='Dorelios:BAAALgADCgMJAwAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJFwAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgUJCQAAAA==.',
Du='Dubstep:BAAALgAECgIJAwAAAA==.Dugatotems:BAABLgAECn8dAAIUAAkJPRjkGwA5AgAUAAkJPRjkGwA5AgAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dunkle:BAABLgAECn8kAAMaAAkJixz4EwCuAgAaAAkJixz4EwCuAgAbAAYJdxEJEQA8AQAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8VAAINAAgJmgZ8PwBQAQANAAgJmgZ8PwBQAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgYJDQAAAA==.',
Eb='Ebonise:BAAALgAECgMJBAAAAA==.',
Ed='Edrelang:BAAALgAECgYJBwAAAA==.',
Ee='Eerikki:BAAALgAECgMJBAAAAA==.',
Ei='Ein:BAABLgAECn8kAAITAAgJOBjBAgARAgATAAgJOBjBAgARAgAAAA==.',
El='Ellechero:BAAALgAECgQJCAAAAA==.Ellonia:BAAALgADCgYJCwABLgAECgcJFwAcALwdAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAAALgAECgUJBQAAAA==.Erinna:BAAALgAECgEJAwAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgQJCAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECggJGQASAMsIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABoMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAABLgAECn8WAAIJAAUJhxnzVQA8AQAJAAUJhxnzVQA8AQAAAA==.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.',
Fy='Fyrestar:BAAALgADCgEJAQAAAA==.',
Ga='Galatrix:BAABLgAECn8kAAIYAAkJkg0NLwDlAQAYAAkJkg0NLwDlAQAAAA==.',
Gh='Ghast:BAABLgAECn81AAMPAAgJ+xN7JwDJAQAPAAgJeRJ7JwDJAQAOAAEJqx1/FABMAAAAAA==.Ghats:BAAALgAECgcJDQAAAA==.',
Gi='Gigaflare:BAABLgAECn8lAAIYAAkJpgyGRwCQAQAYAAkJpgyGRwCQAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatknight:BAABLgAECn8mAAIJAAkJayCWBAAZAwAJAAkJayCWBAAZAwAAAA==.Gobblynn:BAAALgADCggJCwAAAA==.Golokan:BAABLgAECn8UAAIBAAcJGgyHbwAOAQABAAcJGgyHbwAOAQAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn8YAAIPAAcJZgrHVQArAQAPAAcJZgrHVQArAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJBAAAAA==.Greywings:BAABLgAECn8aAAITAAYJmA/oCAAaAQATAAYJmA/oCAAaAQAAAA==.Grimroxs:BAABLgAECn8aAAIMAAgJzwslBgCPAQAMAAgJzwslBgCPAQAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Grizzlemaw:BAAALgAECgQJBQAAAA==.',
Ha='Hacheros:BAAALgAECgEJAQAAAA==.Hairypits:BAAALgAECgQJCAABLgAECgkJJgAJAGsgAA==.Handerbug:BAABLgAECn8lAAMQAAkJOCb0AgCFAwAQAAkJOCb0AgCFAwAdAAYJpRyKCAChAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJJQAQADgmAA==.Hankit:BAAALgAECgMJAgAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJBwAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAAALgAECggJEwAAAA==.Heinrich:BAABLgAECn8jAAMBAAgJlCGtDQCSAgABAAgJlCGtDQCSAgAVAAQJPRHFSACEAAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.',
Ho='Hogglethorp:BAAALgAECgYJCgAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJEQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgkJAgAAAA==.',
Il='Illadron:BAAALgAECgEJAgAAAA==.Illecebra:BAAALgAECgYJDAAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAAALgAECgQJBAAAAA==.',
Ja='Jagerblunt:BAABLgAECn8eAAINAAgJqhe/KgClAQANAAgJqhe/KgClAQAAAA==.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgEJAgAAAA==.',
Je='Jenaaidy:BAAALgAECgUJDAAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJKAAGAPAhAA==.Joshery:BAABLgAECn8oAAMGAAkJ8CGHBQAJAwAGAAkJ8CGHBQAJAwAeAAYJQiYwDwCLAgAAAA==.Joshieboba:BAAALgAECgIJAgABLgAECgkJKAAGAPAhAA==.',
Ju='Judge:BAABLgAECn8aAAIBAAYJgAqAcgAIAQABAAYJgAqAcgAIAQAAAA==.Juhara:BAAALgADCgUJBQAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8cAAIfAAgJGh0qBgA8AgAfAAgJGh0qBgA8AgAAAA==.',
Ka='Katasaria:BAACLgAFFH8IAAMaAAMJrRxmHQDHAAAaAAIJoCBmHQDHAAAbAAEJxxSwFwBVAAAuAAQKfyUAAxoACAlOIG4UAKoCABoACAnWH24UAKoCABsABQkyGv0QAD0BAAAA.Kaycee:BAAALgADCgMJBAABLgAECgYJFQAKAAoPAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgYJFQAKAAoPAA==.Kaycer:BAAALgADCggJDwABLgAECgYJFQAKAAoPAA==.',
Ke='Keeps:BAAALgADCgEJAQAAAA==.Kerl:BAAALgAECgIJAgAAAA==.',
Ki='Kiboridi:BAAALgADCgMJAwAAAA==.Kimetshu:BAABLgAECn8ZAAIFAAYJbBj5FABDAQAFAAYJbBj5FABDAQAAAA==.Kirana:BAABLgAECn8bAAIQAAgJEgWJJwAEAQAQAAgJEgWJJwAEAQAAAA==.',
Kn='Knserbrave:BAAALgAECgYJEgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8iAAIgAAkJqhdvBwB0AgAgAAkJqhdvBwB0AgAAAA==.Kravin:BAAALgADCgMJBAAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABoMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Larlifax:BAAALgAECgIJAgAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8lAAIaAAkJECNgBQChAgAaAAkJECNgBQChAgAAAA==.Levìstus:BAABLgAECn8bAAIJAAgJbxPuKwDLAQAJAAgJbxPuKwDLAQAAAA==.Leylaní:BAAALgAECggJEwAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgEJAgAAAA==.Loroessan:BAAALgAECgUJCAAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgUJCQAAAA==.Lunet:BAAALgADCgcJCAAAAA==.Lustie:BAAALgAECgYJCwABLgAECgkJKQATABAdAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJKQATABAdAA==.Lytheum:BAABLgAECn8pAAITAAkJEB0vBADMAgATAAkJEB0vBADMAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
Ma='Machetesquad:BAAALgADCgMJAgABLgAECgkJKAAUAAEfAA==.Magerrac:BAAALgADCgQJBQABLgAECggJGQASAMsIAA==.Malachar:BAABLgAECn8aAAISAAcJfQxUFQAcAQASAAcJfQxUFQAcAQAAAA==.Malboro:BAABLgAECn8VAAIPAAcJvA8WQQBmAQAPAAcJvA8WQQBmAQAAAA==.Maled:BAAALgAECgUJDAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Meldin:BAAALgAECggJEwAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgMJAwAAAA==.Method:BAABLgAECn8iAAMhAAkJYxFEEQC0AQAhAAkJ5BBEEQC0AQABAAIJFhPXugB/AAAAAA==.Mew:BAABLgAECn8XAAIVAAYJkxxOHgCUAQAVAAYJkxxOHgCUAQAAAA==.',
Mi='Miannya:BAABLgAECn8bAAIeAAkJ4xboGAAbAgAeAAkJ4xboGAAbAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8gAAMEAAgJDhbdIgC3AQAEAAgJxRXdIgC3AQAiAAEJeRglKQBAAAAAAA==.Mineos:BAAALgAECgQJBAAAAA==.Mizoh:BAAALgAECgUJCwAAAA==.',
Mo='Moahuntress:BAAALgAECgQJBAAAAA==.Moonlyt:BAAALgADCgkJIAAAAA==.Morgaine:BAAALgADCgMJAwABLgAECggJGQASAMsIAA==.Morn:BAABLgAECn8YAAMTAAgJaBp9BwBzAgATAAgJaBp9BwBzAgAZAAQJVBWQPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECggJNQAPAPsTAA==.',
Mt='Mtrain:BAAALgAECgMJBQABLgAECgcJDQADAAAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgADCgYJBgAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAAALgAECggJEwAAAA==.Nestiae:BAAALgAECgMJAwAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAECgkJAgADAAAAAA==.Nightsfuri:BAABLgAECn8XAAIQAAgJHhPQEgCvAQAQAAgJHhPQEgCvAQAAAA==.Nik:BAAALgAECgEJAQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8UAAINAAgJyQxlLgCUAQANAAgJyQxlLgCUAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABoMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJBgAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJFwADAAAAAA==.Orlandbro:BAABLgAECn8eAAQNAAkJORxiGAB3AgAjAAgJmB3PBQCrAgANAAkJ4BdiGAB3AgAkAAEJMBA1igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECgcJEQAAAA==.Patchy:BAAALgADCgMJAwAAAA==.Pawradox:BAABLgAECn8aAAICAAgJ0AsrGwBiAQACAAgJ0AsrGwBiAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAgAAAA==.',
Ph='Phenomenon:BAAALgAECgYJCQAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn8sAAIfAAkJ6B3FAwCOAgAfAAkJ6B3FAwCOAgAAAA==.Pitviper:BAAALgAECgQJCwAAAA==.',
Pl='Plina:BAAALgAECggJEQAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgQJCQAAAA==.',
Pr='Prettycolorz:BAAALgAFFAIJAgAAAA==.',
Pu='Pulli:BAAALgAECggJCwAAAA==.',
Pv='Pve:BAABLgAECn8kAAIjAAgJ7x/ABAB0AgAjAAgJ7x/ABAB0AgAAAA==.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8aAAIUAAkJOBLSFwDzAQAUAAkJOBLSFwDzAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgUJBQAAAA==.Rains:BAAALgAECgcJEwAAAA==.Rathane:BAABLgAECn8bAAINAAgJsBkgIwAzAgANAAgJsBkgIwAzAgAAAA==.Ray:BAAALgAECgYJBgABLgAECggJGAATAGgaAA==.',
Re='Realmclovin:BAAALgADCgQJBAAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8cAAIVAAgJqyaoAACRAwAVAAgJqyaoAACRAwAAAA==.',
Ri='Rizzwan:BAABLgAECn8WAAIjAAcJ+hxMCQARAgAjAAcJ+hxMCQARAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMeAAMJYQkLEgDWAAAeAAMJYQkLEgDWAAAGAAIJ0AzTHwB4AAAuAAQKfxoABAYACQn7FcMfAEgBAAYACAkUFMMfAEgBAB4ABwmQEO4/ABkBABcAAQmJDrthADoAAAAA.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAMJCAAaAK0cAA==.Romy:BAAALgAECgUJDAAAAA==.',
Ru='Runecleaver:BAABLgAECn8sAAMUAAkJBCLQBQDaAgAUAAkJBCLQBQDaAgARAAQJ/RJpNgDUAAAAAA==.Ruw:BAAALgAECgYJDgAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8ZAAIJAAkJvRpLQAA3AgAJAAkJvRpLQAA3AgAAAA==.Satania:BAABLgAECn8fAAIFAAkJGSTxBAAlAwAFAAkJGSTxBAAlAwAAAA==.Satavara:BAABLgAECn8UAAMCAAcJdQ5lIgAtAQACAAYJ9A9lIgAtAQAHAAIJ9QrOTQAxAAAAAA==.',
Se='Segora:BAABLgAECn8aAAIPAAYJQwf7ngAbAQAPAAYJQwf7ngAbAQABLgAECgcJGAAPAGYKAA==.Seimus:BAAALgAECgQJBQAAAA==.Seniortotem:BAAALgAECgUJCwAAAA==.',
Sh='Shaanael:BAAALgAECgMJBAAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAAALgAECgUJDAAAAA==.Sharius:BAABLgAECn8iAAIYAAgJUQZWagA8AQAYAAgJUQZWagA8AQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIYAAkJ6RIUOgC7AQAYAAkJ6RIUOgC7AQAAAA==.Shihajimari:BAAALgAECgQJBwAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.',
Si='Sightlightx:BAAALgAECgYJDAAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8eAAIaAAgJXwlVIABpAQAaAAgJXwlVIABpAQAAAA==.Siryn:BAAALgAECgUJDAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smashn:BAAALgADCgYJBgAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAECgYJDAADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8cAAIlAAkJlRL1BADtAQAlAAkJlRL1BADtAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgADCgUJBwAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8jAAMWAAkJ5hvTEACxAgAWAAkJ5hvTEACxAgAQAAcJjBUpFQCWAQAAAA==.Syrden:BAAALgADCgkJCgAAAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCgYJCwAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJBwAAAA==.',
Th='Thandas:BAABLgAECn8dAAIBAAYJjggTeQD6AAABAAYJjggTeQD6AAAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Thniper:BAABLgAECn8oAAMkAAkJRxgkBQDaAQAkAAgJNhskBQDaAQAjAAUJ9gwMGQBAAQAAAA==.Thouvan:BAAALgADCgEJAQAAAA==.Thugnastyy:BAAALgAECgIJBAABLgAECgkJAgADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8eAAIVAAkJ2xjRDQA6AgAVAAkJ2xjRDQA6AgAAAA==.',
To='Tost:BAAALgADCgcJBwAAAA==.',
Ty='Tyinviril:BAABLgAECn8zAAICAAkJXSO+AABaAwACAAkJXSO+AABaAwAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8KAAIBAAUJmAyLHQA4AQABAAUJmAyLHQA4AQAuAAQKfzAAAwEACAlHHkIZADICAAEACAlHHkIZADICABUABQk8CfJgAPgAAAAA.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAAALgAECgUJCgAAAA==.Vonawesome:BAAALgAECgEJAgAAAA==.Vorpalblade:BAABLgAECn8lAAISAAkJCRZ/CQDcAQASAAkJCRZ/CQDcAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAAALgAFFAEJAQAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8lAAMmAAgJXx8GAQDOAgAmAAgJXx8GAQDOAgAYAAEJPRlK5QBLAAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8VAAIhAAgJ5RO3CwCBAQAhAAgJ5RO3CwCBAQAAAA==.Willowfox:BAAALgAECgMJBQAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCQAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJBQAAAA==.Wram:BAABLgAECn8ZAAISAAgJywhyFgAQAQASAAgJywhyFgAQAQAAAA==.Wreckuiem:BAAALgAECgYJDAAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8XAAMcAAcJvB20AwDjAQAcAAcJvB20AwDjAQAPAAEJQBVywgBIAAAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAABLgAECn8ZAAIEAAkJdhKFHQDYAQAEAAkJdhKFHQDYAQAAAA==.',
Zi='Zillara:BAAALgAECgcJEAAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQABLgAECgkJKwAaAGYZAA==.',
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

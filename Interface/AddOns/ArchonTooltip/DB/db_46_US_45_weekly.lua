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

local lookup = {'Paladin-Retribution','Priest-Shadow','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Unknown-Unknown','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Warrior-Protection','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Warrior-Fury','Warrior-Arms','Evoker-Devastation','Warlock-Destruction','Druid-Guardian','Monk-Windwalker','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Evoker-Augmentation','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Mage-Arcane','Paladin-Holy','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acast:BAAALgADCgYJBgAAAA==.Acurd:BAABLgAECn8bAAIBAAYJPiCvVQDhAQABAAYJPiCvVQDhAQAAAA==.',
Ad='Adaila:BAABLgAECn8iAAICAAgJNQkbDAAxAQACAAgJNQkbDAAxAQAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgADCggJDQAAAA==.',
Ai='Aicianklip:BAAALgAECgEJAQAAAA==.Aiir:BAAALgAECgQJCQAAAA==.',
Aj='Ajaki:BAAALgAECgQJBwAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgADCgQJBAAAAA==.Alwayspala:BAAALgAECggJEAAAAA==.',
Am='Ambridgerose:BAAALgAECgQJCgAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECgIJAgAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlan:BAAALgAECgQJBgAAAA==.Arlequin:BAABLgAECn8XAAMDAAcJrQiFKADYAAADAAcJrQiFKADYAAAEAAEJAAAUfwAUAAAAAA==.Arnagan:BAAALgAECgEJAQAAAA==.',
As='Asharothh:BAABLgAECn8ZAAIFAAgJ4Rg8FgATAgAFAAgJ4Rg8FgATAgAAAA==.Ashdem:BAAALgAECgYJCwAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAAALgAECgEJAQAAAA==.',
Av='Avari:BAAALgADCgkJEgABLgAECgYJDwAGAAAAAA==.',
Az='Azariel:BAABLgAECn8jAAQHAAgJZRAwKgChAQAHAAgJZRAwKgChAQACAAEJ8gfVIQAzAAAIAAEJZwHFXgAjAAAAAA==.Azorahai:BAABLgAECn8UAAIJAAYJageazQDmAAAJAAYJageazQDmAAAAAA==.Azshalia:BAAALgAECgIJAgAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAAALgAECgYJDwAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAAALgAECgYJDAAAAA==.Banilibug:BAAALgAECgYJDQAAAA==.',
Be='Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8iAAMKAAgJ8yTnAAAOAwAKAAcJviXnAAAOAwALAAcJURxoBQAiAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECggJIwAMADQmAA==.',
Bo='Bobbybrady:BAAALgAECgYJDgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAAALgAECgQJCAAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Bosshog:BAABLgAECn8hAAIBAAgJAyDTAwBpAgABAAgJAyDTAwBpAgAAAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8FAAINAAUJ4hsVBgAJAQANAAUJ4hsVBgAJAQAAAA==.Buglerion:BAAALgADCgYJBgABLgAECggJIwAMADQmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bushwhacker:BAAALgAECgQJBwAAAA==.Butterbean:BAABLgAECn8iAAIOAAgJVSHAAwBNAgAOAAgJVSHAAwBNAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgADCgUJBgAAAA==.Cassardis:BAAALgAECgQJBQAAAA==.Catameringue:BAAALgAECgMJBgAAAA==.',
Ch='Chido:BAAALgADCgYJCgABLgAECgYJDwAGAAAAAA==.',
Cl='Classfantasy:BAABLgAECn8jAAMPAAgJSCJBCQDjAgAPAAgJSCJBCQDjAgAQAAYJ7hCNDQAnAQAAAA==.',
Co='Coaca:BAAALgAECgUJDAAAAA==.Cobalt:BAAALgAECgMJBAABLgAECgYJCgAGAAAAAA==.Confluent:BAABLgAECn8fAAIRAAgJPyRiAABSAwARAAgJPyRiAABSAwAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn8bAAISAAcJDhPNDAAkAQASAAcJDhPNDAAkAQAAAA==.',
Cy='Cythrandir:BAAALgAECgQJBAABLgAECggJGQATAKIYAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.',
Dd='Ddccssff:BAAALgADCggJCAAAAA==.',
De='Deathcoiled:BAAALgAECgEJAQAAAA==.Defnotademon:BAAALgAECgQJBAAAAA==.Dethrahzen:BAAALgAECgQJCgAAAA==.',
Di='Dirtydan:BAAALgADCgMJAQAAAA==.Disektor:BAAALgAECgYJEAAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgADCgYJCAAAAA==.',
Do='Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJEgAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgUJCQAAAA==.',
Du='Dubstep:BAAALgAECgEJAQAAAA==.Dugatotems:BAABLgAECn8aAAIPAAgJvRjsGwA5AgAPAAgJvRjsGwA5AgAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dunkle:BAABLgAECn8iAAMUAAgJeBwBFACuAgAUAAgJeBwBFACuAgAVAAYJdxE4BABfAQAAAA==.Duskhawk:BAAALgAECgQJBwAAAA==.',
['Dâ']='Dârkness:BAAALgADCgcJBwAAAA==.',
Eb='Ebonise:BAAALgAECgEJAQAAAA==.',
Ed='Edrelang:BAAALgADCgkJDQAAAA==.',
Ee='Eerikki:BAAALgAECgEJAQAAAA==.',
Ei='Ein:BAABLgAECn8WAAIWAAcJ7hbIAQCaAQAWAAcJ7hbIAQCaAQAAAA==.',
El='Ellechero:BAAALgAECgMJAwAAAA==.Ellonia:BAAALgADCgUJBQABLgAECgYJFQAXAEggAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Erinna:BAAALgADCgYJBgAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgEJAQAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgYJEAAGAAAAAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgYJDwAGAAAAAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAAALgAECgUJBwAAAA==.Frthckr:BAAALgAECgIJAgAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.',
Fy='Fyrestar:BAAALgADCgEJAQAAAA==.',
Ga='Galatrix:BAABLgAECn8XAAITAAgJTwjKIQBMAQATAAgJTwjKIQBMAQAAAA==.',
Gh='Ghast:BAABLgAECn8bAAMLAAcJUw64GABMAQALAAcJiQu4GABMAQAKAAEJfx31BgBZAAAAAA==.',
Gi='Gigaflare:BAABLgAECn8jAAITAAgJyw3XHQBhAQATAAgJyw3XHQBhAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Go='Goatknight:BAABLgAECn8ZAAIJAAgJnxmECgDWAQAJAAgJnxmECgDWAQAAAA==.Gobblynn:BAAALgADCggJCwAAAA==.Golokan:BAAALgAECgYJDwAAAA==.Goodspeed:BAAALgAECgEJAgAAAA==.Gora:BAAALgAECgYJCQABLgAECgYJGgALAEMHAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greywings:BAAALgAECgYJDgAAAA==.Grimroxs:BAAALgAECgYJDAAAAA==.Grizzlemaw:BAAALgADCgEJAgAAAA==.',
Ha='Handerbug:BAABLgAECn8jAAMMAAgJNCbzAgCFAwAMAAgJNCbzAgCFAwAYAAYJpRyRAgCiAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECggJIwAMADQmAA==.Harandayum:BAAALgADCgQJBwAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJBwAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAAALgAECgUJBwAAAA==.Heinrich:BAAALgAECgYJEQAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.',
Ho='Hogglethorp:BAAALgAECgQJBAAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCggJCAAAAA==.',
Hr='Hrima:BAAALgAECgYJCQAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgEJAQAAAA==.',
Il='Illadron:BAAALgAECgEJAgAAAA==.Illecebra:BAAALgAECgYJBwAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
Ja='Jagerblunt:BAABLgAECn8XAAIOAAYJRh6FMQDqAQAOAAYJRh6FMQDqAQAAAA==.',
Jd='Jdbud:BAAALgADCgMJAwAAAA==.Jdpot:BAAALgAECgEJAQAAAA==.',
Je='Jenaaidy:BAAALgAECgIJAgAAAA==.',
Ji='Jiks:BAAALgADCggJCAAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECggJJgAFAOMiAA==.Joshery:BAABLgAECn8mAAMFAAgJ4yKGBQALAwAFAAgJ4yKGBQALAwAZAAYJQiYsDwCLAgAAAA==.',
Ju='Judge:BAAALgAECgYJDgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAAALgAECgYJDgAAAA==.',
Ka='Katasaria:BAABLgAECn8dAAMUAAgJ1h93FACqAgAUAAgJ1h93FACqAgAVAAQJBxpoGAA1AQAAAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgYJDwAGAAAAAA==.Kaycer:BAAALgADCggJDwABLgAECgYJDwAGAAAAAA==.',
Ke='Keeps:BAAALgADCgEJAQAAAA==.Kerl:BAAALgAECgIJAgAAAA==.',
Ki='Kiboridi:BAAALgADCgMJAwAAAA==.Kimetshu:BAAALgAECgYJEwAAAA==.Kirana:BAAALgAECgYJDQAAAA==.',
Kn='Knserbrave:BAAALgAECgYJEgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8gAAIaAAgJ5xlvBwB0AgAaAAgJ5xlvBwB0AgAAAA==.Kravin:BAAALgADCgMJBAAAAA==.Krunzar:BAAALgAECgIJAgAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgYJDwAGAAAAAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Larlifax:BAAALgAECgIJAgAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8jAAIUAAgJsiLxAQBUAgAUAAgJsiLxAQBUAgAAAA==.Levìstus:BAAALgAECgYJDgAAAA==.Leylaní:BAAALgAECgUJBwAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Loroessan:BAAALgAECgMJAwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgEJAQAAAA==.Lunet:BAAALgADCgcJCAAAAA==.Lustie:BAAALgAECgYJCQABLgAECggJIwAWAOQcAA==.',
Ly='Lynnadin:BAAALgAECgQJCQAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECggJIwAWAOQcAA==.Lytheum:BAABLgAECn8jAAIWAAgJ5BwuBADMAgAWAAgJ5BwuBADMAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
Ma='Magerrac:BAAALgADCgEJAQABLgAECgYJEAAGAAAAAA==.Malachar:BAAALgAECgYJDQAAAA==.Malboro:BAAALgAECgQJCAAAAA==.Maled:BAAALgAECgIJAgAAAA==.Maleficent:BAAALgAECgcJBAAAAA==.Mandrews:BAAALgAECgkJCAAAAA==.',
Me='Meldin:BAAALgAECgUJBwAAAA==.Method:BAABLgAECn8dAAIbAAgJ0BJCEQC0AQAbAAgJ0BJCEQC0AQAAAA==.Mew:BAAALgAECgUJCwAAAA==.',
Mi='Miannya:BAABLgAECn8ZAAIZAAcJmhnjGAAbAgAZAAcJmhnjGAAbAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8WAAMDAAYJQhUTGAA/AQADAAYJ3BQTGAA/AQAcAAEJeRgoKQBAAAAAAA==.Mineos:BAAALgADCgkJGAAAAA==.Mizoh:BAAALgAECgMJBAAAAA==.',
Mo='Moahuntress:BAAALgAECgIJAgAAAA==.Moonlyt:BAAALgADCgkJHwAAAA==.Morn:BAABLgAECn8YAAMWAAgJaBp7BwBzAgAWAAgJaBp7BwBzAgAdAAQJVBWMPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgcJGwALAFMOAA==.',
Mt='Mtrain:BAAALgAECgIJAgAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJCwAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgEJAQAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAAALgAECgUJBwAAAA==.Nestiae:BAAALgAECgMJAwAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Nightsfuri:BAAALgAECgYJDAAAAA==.Niqi:BAAALgADCgEJAQAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAAALgAECgYJDAAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDAABLgAECgYJDwAGAAAAAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJBgAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJEgAGAAAAAA==.Orlandbro:BAABLgAECn8cAAQOAAgJLB9lGAB3AgAeAAgJmB3OBQCrAgAOAAgJNBplGAB3AgAfAAEJMBD+iQAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgADCggJCAAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECgYJDwAAAA==.Patchy:BAAALgADCgMJAwAAAA==.Pawradox:BAAALgAECgYJEAAAAA==.',
Pe='Peadar:BAAALgADCgUJBQAAAA==.',
Ph='Phenomenon:BAAALgADCgcJDwAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn8fAAIgAAgJDx7kBwCpAgAgAAgJDx7kBwCpAgAAAA==.Pitviper:BAAALgAECgQJBgAAAA==.',
Pl='Plina:BAAALgAECgUJBQAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgQJBQAAAA==.',
Pr='Prettycolorz:BAAALgAFFAIJAgAAAA==.',
Pu='Pulli:BAAALgAECgYJBwAAAA==.',
Pv='Pve:BAABLgAECn8WAAIeAAcJmx+0AwC9AQAeAAcJmx+0AwC9AQAAAA==.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8VAAIPAAYJuBPmDgBSAQAPAAYJuBPmDgBSAQAAAA==.Rainn:BAAALgAECgIJAgAAAA==.Rains:BAAALgAECgYJDAAAAA==.Rathane:BAABLgAECn8bAAIOAAgJsBkjIwAzAgAOAAgJsBkjIwAzAgAAAA==.',
Re='Reaperzz:BAAALgADCgcJCAAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.',
Rh='Rhapsody:BAAALgAECgYJDgAAAA==.',
Ri='Rizzwan:BAAALgAECgUJCwAAAA==.',
Rj='Rjay:BAAALgAFFAEJAQAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAECggJHQAUANYfAA==.Romy:BAAALgAECgIJAgAAAA==.',
Ru='Runecleaver:BAABLgAECn8fAAMPAAgJICHuAgBdAgAPAAgJICHuAgBdAgAQAAMJBxByHAB9AAAAAA==.Ruw:BAAALgAECgQJCAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8XAAIJAAgJaRlGQAA3AgAJAAgJaRlGQAA3AgAAAA==.Satania:BAABLgAECn8dAAIEAAgJJCTxBAAlAwAEAAgJJCTxBAAlAwAAAA==.Satavara:BAAALgAECgYJBwAAAA==.',
Se='Segora:BAABLgAECn8aAAILAAYJQwfnngAbAQALAAYJQwfnngAbAQAAAA==.Seimus:BAAALgADCgMJAwAAAA==.Seniortotem:BAAALgAECgUJCwAAAA==.',
Sh='Shaanael:BAAALgAECgEJAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAAALgAECgMJAwAAAA==.Sharius:BAABLgAECn8cAAITAAgJXwVxJgA1AQATAAgJXwVxJgA1AQAAAA==.Shawesome:BAAALgADCgYJCAAAAA==.Shiera:BAABLgAECn8ZAAITAAgJaRR5ZAAPAgATAAgJaRR5ZAAPAgAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.',
Si='Sightlightx:BAAALgAECgQJBQAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAAALgAECgUJEAAAAA==.Siryn:BAAALgAECgIJAgAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgAAAA==.',
Sp='Spelledwong:BAABLgAECn8aAAIhAAgJ1hD1BADtAQAhAAgJ1hD1BADtAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgADCgUJBwAAAA==.Stormkight:BAAALgAECgEJAQAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8hAAMRAAgJXh3WEACxAgARAAgJXh3WEACxAgAMAAcJjBXyBQCoAQAAAA==.Syrden:BAAALgADCgkJCgAAAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCgYJBgAAAA==.Tapyourtoes:BAAALgADCgMJAwAAAA==.Tayloria:BAAALgADCgkJCgAAAA==.',
Te='Tenrizzy:BAAALgAECgEJAQAAAA==.',
Th='Thandas:BAAALgAECgYJDAAAAA==.Thisarsar:BAAALgAECgEJAQAAAA==.Thniper:BAABLgAECn8gAAMfAAkJDBhqGABlAgAfAAgJ8hpqGABlAgAeAAEJxAOHEgBJAAAAAA==.Thouvan:BAAALgADCgEJAQAAAA==.',
Ti='Tiamaria:BAABLgAECn8cAAIiAAgJjRo+BAAuAgAiAAgJjRo+BAAuAgAAAA==.',
To='Tost:BAAALgADCgcJBwABLgADCggJCAAGAAAAAA==.',
Ty='Tyinviril:BAABLgAECn8kAAICAAgJ6yLSAACwAgACAAgJ6yLSAACwAgAAAA==.',
Va='Valynx:BAAALgAECgUJBQAAAA==.',
Ve='Veraz:BAABLgAECn8iAAMBAAgJUhvlKwB0AgABAAgJUhvlKwB0AgAiAAUJPAnyYAD4AAAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAAALgAECgQJBgAAAA==.Vonawesome:BAAALgADCggJEgAAAA==.Vorpalblade:BAABLgAECn8jAAINAAgJSBi0AwCqAQANAAgJSBi0AwCqAQAAAA==.',
Vy='Vylas:BAAALgAECgQJBwAAAA==.Vynicon:BAAALgAECgQJBAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8jAAIjAAgJXx8HAQDOAgAjAAgJXx8HAQDOAgAAAA==.',
Wi='Wildpaleon:BAAALgAECggJEQAAAA==.Willowfox:BAAALgADCgYJDQAAAA==.',
Wo='Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgADCgcJGQABLgADCggJDQAGAAAAAA==.Wram:BAAALgAECgYJEAAAAA==.Wreckuiem:BAAALgAECgQJBQAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8VAAIXAAYJSCBGAQC8AQAXAAYJSCBGAQC8AQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAABLgAECn8XAAIDAAgJtguZFwBCAQADAAgJtguZFwBCAQAAAA==.',
Ya='Yaboislyy:BAAALgAECgUJBwAAAA==.',
Zi='Zillara:BAAALgAECgUJCQAAAA==.',
['Zù']='Zùlfang:BAAALgADCgYJBgABLgAECggJHwAUAJsYAA==.',
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

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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Warrior-Protection','Evoker-Devastation','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Druid-Guardian','Paladin-Holy','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Evoker-Augmentation','Hunter-Survival','Hunter-Marksmanship','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acast:BAAALgAECgEJAQAAAA==.Acurd:BAABLgAECn8bAAIBAAYJPiCqVQDhAQABAAYJPiCqVQDhAQAAAA==.',
Ad='Adaila:BAABLgAECn8jAAICAAgJNQnJGAA4AQACAAgJNQnJGAA4AQAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgADCggJDQABLgAECgEJAQADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgIJAwAAAA==.Aiir:BAAALgAECgYJDwAAAA==.',
Aj='Ajaki:BAAALgAECgYJCQAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgADCgQJBAAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Ambridgerose:BAAALgAECgQJCgAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgEJAQAAAA==.Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECgYJCAAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlan:BAAALgAECgYJDAAAAA==.Arlequin:BAABLgAECn8XAAMEAAcJrQjzRQDUAAAEAAcJrQjzRQDUAAAFAAEJAAAcfwAUAAAAAA==.Arnagan:BAAALgAECgIJAgAAAA==.',
As='Asharothh:BAABLgAECn8bAAIGAAgJPRs3FgASAgAGAAgJPRs3FgASAgAAAA==.Ashdem:BAAALgAECgYJCwAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAAALgAECgUJBgAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABoMAA==.',
Az='Azariel:BAABLgAECn8lAAQHAAkJyg4xKgChAQAHAAkJyg4xKgChAQACAAEJ8gcQQgA0AAAIAAEJZwHGXgAjAAAAAA==.Azorahai:BAABLgAECn8ZAAIJAAYJawd9XQDuAAAJAAYJawd9XQDuAAAAAA==.Azshalia:BAAALgAECgMJBQAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAAALgAECgYJEQAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8UAAMFAAcJwRABFAALAQAFAAUJYBQBFAALAQAEAAYJkggykQD9AAAAAA==.Banilibug:BAAALgAECgYJEwAAAA==.',
Be='Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8kAAMKAAkJdCXnAAAOAwAKAAcJviXnAAAOAwALAAgJ5h2UBwCTAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJJQAMADgmAA==.',
Bo='Bobbybrady:BAAALgAECgYJDgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAAALgAECgcJDwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAAALgADCgcJCQAAAA==.Bosshog:BAABLgAECn8iAAIBAAgJWiCaCwBtAgABAAgJWiCaCwBtAgAAAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8FAAINAAUJ4hsWBgAJAQANAAUJ4hsWBgAJAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJJQAMADgmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bupropion:BAAALgAECgQJCQABLgAECgkJJgAOABAdAA==.Bushwhacker:BAAALgAECgYJCQAAAA==.Butterbean:BAABLgAECn8kAAIPAAkJ0x89BgCTAgAPAAkJ0x89BgCTAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgADCgUJBwAAAA==.Cassardis:BAAALgAECgUJCgAAAA==.Catameringue:BAAALgAECgMJBgAAAA==.',
Ch='Chido:BAAALgADCgYJCgABLgAECgcJFAABABoMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8lAAMQAAkJAR9ACQDjAgAQAAkJAR9ACQDjAgARAAYJ7hAIHgAnAQAAAA==.',
Co='Coaca:BAAALgAECgYJEwAAAA==.Cobalt:BAAALgAECgMJBAABLgAECgcJEQADAAAAAA==.Confluent:BAABLgAECn8jAAISAAgJ7CSSAQBXAwASAAgJ7CSSAQBXAwAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn8jAAITAAgJOBLJEwBoAQATAAgJOBLJEwBoAQAAAA==.',
Cy='Cythrandir:BAAALgAECgUJCQABLgAFFAIJBQAUAF0UAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.',
Dd='Ddccssff:BAAALgAECgMJAwAAAA==.',
De='Deathcoiled:BAAALgAECgQJBAAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAAALgAECgQJDgAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8XAAIVAAcJahm7DgDLAQAVAAcJahm7DgDLAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgADCgYJCAAAAA==.',
Do='Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJEgAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgUJCQAAAA==.',
Du='Dubstep:BAAALgAECgEJAQAAAA==.Dugatotems:BAABLgAECn8cAAIQAAgJvRjlGwA5AgAQAAgJvRjlGwA5AgAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dunkle:BAABLgAECn8kAAMVAAkJixwAFACuAgAVAAkJixwAFACuAgAWAAYJdxEeCwBQAQAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAAALgAECgYJDQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgEJAQAAAA==.',
Eb='Ebonise:BAAALgAECgIJAwAAAA==.',
Ed='Edrelang:BAAALgADCgkJDQAAAA==.',
Ee='Eerikki:BAAALgAECgIJAwAAAA==.',
Ei='Ein:BAABLgAECn8eAAIOAAgJ+BfTAQAeAgAOAAgJ+BfTAQAeAgAAAA==.',
El='Ellechero:BAAALgAECgQJBwAAAA==.Ellonia:BAAALgADCgYJCwABLgAECgcJFgAXALcdAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Erinna:BAAALgAECgEJAgAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgMJBAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgYJFQANAIMJAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABoMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAAALgAECgUJEAAAAA==.Frthckr:BAAALgAECgQJBgAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.',
Fy='Fyrestar:BAAALgADCgEJAQAAAA==.',
Ga='Galatrix:BAABLgAECn8bAAIUAAgJZAtORABiAQAUAAgJZAtORABiAQAAAA==.',
Gh='Ghast:BAABLgAECn8nAAMLAAcJFBTLKgCCAQALAAcJShHLKgCCAQAKAAEJfx1/DQBYAAAAAA==.Ghats:BAAALgAECgcJDQAAAA==.',
Gi='Gigaflare:BAABLgAECn8lAAIUAAkJpgxhNACUAQAUAAkJpgxhNACUAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJBwAAAA==.',
Go='Goatknight:BAABLgAECn8dAAIJAAgJnxnMIQC9AQAJAAgJnxnMIQC9AQAAAA==.Gobblynn:BAAALgADCggJCwAAAA==.Golokan:BAABLgAECn8UAAIBAAcJGgzjUQAYAQABAAcJGgzjUQAYAQAAAA==.Goodspeed:BAAALgAECgEJAgAAAA==.Gora:BAAALgAECgYJDwABLgAECgYJGgALAEMHAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greywings:BAABLgAECn8UAAIOAAYJaA7TBgApAQAOAAYJaA7TBgApAQAAAA==.Grimroxs:BAAALgAECgYJEgAAAA==.Grizzlemaw:BAAALgAECgEJAQAAAA==.',
Ha='Hairypits:BAAALgAECgQJBAABLgAECggJHQAJAJ8ZAA==.Handerbug:BAABLgAECn8lAAMMAAkJOCb2AgCFAwAMAAkJOCb2AgCFAwAYAAYJpRwCBgCgAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJJQAMADgmAA==.Harandayum:BAAALgADCgQJBwAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJBwAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAAALgAECgYJDQAAAA==.Heinrich:BAABLgAECn8bAAMBAAgJzR5pKAChAQABAAgJzR5pKAChAQAZAAQJPRHgOQCKAAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.',
Ho='Hogglethorp:BAAALgAECgYJCgAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCggJCAAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgkJAgAAAA==.',
Il='Illadron:BAAALgAECgEJAgAAAA==.Illecebra:BAAALgAECgYJBwAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
Ja='Jagerblunt:BAABLgAECn8cAAIPAAgJaBcGIgCWAQAPAAgJaBcGIgCWAQAAAA==.',
Jd='Jdbud:BAAALgAECgEJAQAAAA==.Jdpot:BAAALgAECgEJAgAAAA==.',
Je='Jenaaidy:BAAALgAECgMJBgAAAA==.',
Ji='Jiks:BAAALgADCggJCAAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJKAAGAPAhAA==.Joshery:BAABLgAECn8oAAMGAAkJ8CGIBQAJAwAGAAkJ8CGIBQAJAwAaAAYJQiYwDwCLAgAAAA==.',
Ju='Judge:BAABLgAECn8UAAIBAAYJgQqZVAAQAQABAAYJgQqZVAAQAQAAAA==.Juhara:BAAALgADCgUJBQAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8UAAIbAAYJzx71BgCzAQAbAAYJzx71BgCzAQAAAA==.',
Ka='Katasaria:BAACLgAFFH8FAAMWAAIJVhUMEABWAAAVAAEJ7RkiHwBYAAAWAAEJvhAMEABWAAAuAAQKfyUAAxUACAlOIHIUAKoCABUACAnWH3IUAKoCABYABQkyGrcLAEcBAAAA.Kayceedeeuh:BAAALgADCgUJBQABLgAECgYJEQADAAAAAA==.Kaycer:BAAALgADCggJDwABLgAECgYJEQADAAAAAA==.',
Ke='Keeps:BAAALgADCgEJAQAAAA==.Kerl:BAAALgAECgIJAgAAAA==.',
Ki='Kiboridi:BAAALgADCgMJAwAAAA==.Kimetshu:BAABLgAECn8ZAAIFAAYJbBgxDwBIAQAFAAYJbBgxDwBIAQAAAA==.Kirana:BAAALgAECgYJEwAAAA==.',
Kn='Knserbrave:BAAALgAECgYJEgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8iAAIcAAkJqhdvBwB0AgAcAAkJqhdvBwB0AgAAAA==.Kravin:BAAALgADCgMJBAAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABoMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Larlifax:BAAALgAECgIJAgAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8lAAIVAAkJECNnAgDAAgAVAAkJECNnAgDAAgAAAA==.Levìstus:BAABLgAECn8TAAIJAAYJBhO9PwA/AQAJAAYJBhO9PwA/AQAAAA==.Leylaní:BAAALgAECgYJDQAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgEJAQAAAA==.Loroessan:BAAALgAECgMJAwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgIJBAAAAA==.Lunet:BAAALgADCgcJCAAAAA==.Lustie:BAAALgAECgYJCgABLgAECgkJJgAOABAdAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJJgAOABAdAA==.Lytheum:BAABLgAECn8mAAIOAAkJEB0tBADMAgAOAAkJEB0tBADMAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
Ma='Magerrac:BAAALgADCgQJBAABLgAECgYJFQANAIMJAA==.Malachar:BAAALgAECgYJEwAAAA==.Malboro:BAAALgAECgYJDgAAAA==.Maled:BAAALgAECgMJBgAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Meldin:BAAALgAECgYJDQAAAA==.Merve:BAAALgAECgIJAgAAAA==.Method:BAABLgAECn8gAAMdAAkJYxFEEQC0AQAdAAkJ5BBEEQC0AQABAAEJBxscsQBPAAAAAA==.Mew:BAAALgAECgUJEAAAAA==.',
Mi='Miannya:BAABLgAECn8bAAIaAAkJ4xbpGAAbAgAaAAkJ4xbpGAAbAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8YAAMEAAYJOhfuKQA+AQAEAAYJ1BbuKQA+AQAeAAEJeRgrKQBAAAAAAA==.Mineos:BAAALgAECgEJAQAAAA==.Mizoh:BAAALgAECgQJBgAAAA==.',
Mo='Moahuntress:BAAALgAECgMJAwAAAA==.Moonlyt:BAAALgADCgkJIAAAAA==.Morgaine:BAAALgADCgMJAwABLgAECgYJFQANAIMJAA==.Morn:BAABLgAECn8YAAMOAAgJaBp7BwBzAgAOAAgJaBp7BwBzAgAfAAQJVBWTPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgcJJwALABQUAA==.',
Mt='Mtrain:BAAALgAECgMJBQABLgAECgcJDQADAAAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgADCgYJBgAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgEJAQAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAAALgAECgYJDQAAAA==.Nestiae:BAAALgAECgMJAwAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAECgkJAgADAAAAAA==.Nightsfuri:BAAALgAECgcJEwAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAAALgAECgYJDAAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABoMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJBgAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJEgADAAAAAA==.Orlandbro:BAABLgAECn8eAAQPAAkJORxlGAB3AgAgAAgJmB3RBQCrAgAPAAkJ4BdlGAB3AgAhAAEJMBAFigAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgADCggJCwAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECgcJEAAAAA==.Patchy:BAAALgADCgMJAwAAAA==.Pawradox:BAABLgAECn8XAAICAAcJ9guSGAA6AQACAAcJ9guSGAA6AQAAAA==.',
Pe='Peadar:BAAALgADCgUJBQAAAA==.',
Ph='Phenomenon:BAAALgAECgIJAgAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn8jAAIbAAgJfx7jBwCpAgAbAAgJfx7jBwCpAgAAAA==.Pitviper:BAAALgAECgQJCgAAAA==.',
Pl='Plina:BAAALgAECgYJCwAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgQJCAAAAA==.',
Pr='Prettycolorz:BAAALgAFFAIJAgAAAA==.',
Pu='Pulli:BAAALgAECggJCwAAAA==.',
Pv='Pve:BAABLgAECn8dAAIgAAgJOhy/BQAZAgAgAAgJOhy/BQAZAgAAAA==.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8XAAIQAAcJhxH1HQB0AQAQAAcJhxH1HQB0AQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgUJBQAAAA==.Rains:BAAALgAECgcJEwAAAA==.Rathane:BAABLgAECn8bAAIPAAgJsBkfIwAzAgAPAAgJsBkfIwAzAgAAAA==.',
Re='Realmclovin:BAAALgADCgQJBAAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8UAAIZAAYJ/CZZBACzAgAZAAYJ/CZZBACzAgAAAA==.',
Ri='Rizzwan:BAAALgAECgYJEQAAAA==.',
Rj='Rjay:BAABLgAECn8YAAQGAAkJqhMDHAAiAQAGAAgJmxIDHAAiAQAaAAcJsA7wPwAZAQATAAEJZA4kTAA8AAAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAIJBQAWAFYVAA==.Romy:BAAALgAECgMJBgAAAA==.',
Ru='Runecleaver:BAABLgAECn8jAAMQAAgJICGfDQCuAgAQAAgJICGfDQCuAgARAAQJbw+QMgCvAAAAAA==.Ruw:BAAALgAECgQJCAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8ZAAIJAAkJvRpLQAA3AgAJAAkJvRpLQAA3AgAAAA==.Satania:BAABLgAECn8fAAIFAAkJGSTyBAAlAwAFAAkJGSTyBAAlAwAAAA==.Satavara:BAAALgAECgYJDQAAAA==.',
Se='Segora:BAABLgAECn8aAAILAAYJQwf2ngAbAQALAAYJQwf2ngAbAQAAAA==.Seimus:BAAALgADCgQJBAAAAA==.Seniortotem:BAAALgAECgUJCwAAAA==.',
Sh='Shaanael:BAAALgAECgIJAwAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAAALgAECgQJBgAAAA==.Sharius:BAABLgAECn8fAAIUAAgJGga3VgAxAQAUAAgJGga3VgAxAQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8ZAAIUAAgJbBRzZAAQAgAUAAgJbBRzZAAQAgAAAA==.Shihajimari:BAAALgAECgMJAwAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.',
Si='Sightlightx:BAAALgAECgUJCgAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8XAAIVAAcJigj2HQBCAQAVAAcJigj2HQBCAQAAAA==.Siryn:BAAALgAECgMJBgAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgAAAA==.',
Sp='Spelledwong:BAABLgAECn8cAAIiAAkJlRL3BADtAQAiAAkJlRL3BADtAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgADCgUJBwAAAA==.Stormkight:BAAALgAECgEJAQAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8jAAMSAAkJ5hvXEACxAgASAAkJ5hvXEACxAgAMAAcJjBUODwCgAQAAAA==.Syrden:BAAALgADCgkJCgAAAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCgYJBgAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgADCgkJDgAAAA==.',
Te='Tenrizzy:BAAALgAECgEJAwAAAA==.',
Th='Thandas:BAABLgAECn8YAAIBAAYJLQgSXAD+AAABAAYJLQgSXAD+AAAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Thniper:BAABLgAECn8kAAMhAAkJDBhtGABlAgAhAAgJ8hptGABlAgAgAAUJ9gxKEgBCAQAAAA==.Thouvan:BAAALgADCgEJAQAAAA==.Thugnastyy:BAAALgAECgEJAgABLgAECgkJAgADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8eAAIZAAkJ2xjbBwBdAgAZAAkJ2xjbBwBdAgAAAA==.',
To='Tost:BAAALgADCgcJBwABLgADCggJCAADAAAAAA==.',
Ty='Tyinviril:BAABLgAECn8oAAICAAgJFiMTAgDAAgACAAgJFiMTAgDAAgAAAA==.',
Va='Valynx:BAAALgAECgUJBgAAAA==.',
Ve='Veraz:BAABLgAECn8qAAMBAAgJRx5kEgAnAgABAAgJRx5kEgAnAgAZAAUJPAnyYAD4AAAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAAALgAECgUJCgAAAA==.Vonawesome:BAAALgADCggJEwAAAA==.Vorpalblade:BAABLgAECn8lAAINAAkJCRaFBgDlAQANAAkJCRaFBgDlAQAAAA==.',
Vy='Vylas:BAAALgAECgQJBwAAAA==.Vynicon:BAAALgAECgcJCQAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8jAAIjAAgJXx8GAQDOAgAjAAgJXx8GAQDOAgAAAA==.',
Wi='Wildpaleon:BAABLgAECn8VAAIdAAgJ5RNdCACMAQAdAAgJ5RNdCACMAQAAAA==.Willowfox:BAAALgAECgMJBQAAAA==.',
Wo='Wobblersmonk:BAAALgAECgIJAgAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgEJAQAAAA==.Wram:BAABLgAECn8VAAINAAYJgwmWGADBAAANAAYJgwmWGADBAAAAAA==.Wreckuiem:BAAALgAECgUJCgAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8WAAIXAAcJtx2JAgDpAQAXAAcJtx2JAgDpAQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAABLgAECn8VAAIEAAgJIBFCHQCEAQAEAAgJIBFCHQCEAQAAAA==.',
Zi='Zillara:BAAALgAECgcJEAAAAA==.',
['Zù']='Zùlfang:BAAALgADCgYJBgABLgAECgkJKAAVAO8XAA==.',
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

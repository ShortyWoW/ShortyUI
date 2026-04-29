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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','Mage-Fire','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Warrior-Fury','Druid-Restoration','Druid-Balance','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','Priest-Holy','Paladin-Retribution','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warrior-Arms','Hunter-Survival','Warlock-Demonology','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Hunter-Marksmanship','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.',
Ab='Abeblinkin:BAAALgADCgQJBwAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.',
Ae='Aeless:BAAALgADCgEJAQAAAA==.Aelless:BAAALgAECgMJAwAAAA==.',
Ai='Aithinne:BAAALgADCgcJFgAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alfira:BAAALgAECgQJBAAAAA==.Alghul:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgQJCgAAAA==.',
Ar='Arese:BAABLgAECn8bAAQCAAYJUyaSAAD6AQACAAUJUyaSAAD6AQADAAMJlyTGEgHYAAAEAAEJAABRDABpAAAAAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAAALgAECgUJBQAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBAAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAAALgAECgYJDAAAAA==.',
Ba='Babasha:BAAALgAECgYJCQAAAA==.Babybluz:BAAALgADCggJEgAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8aAAIFAAgJLw3RBQBOAQAFAAgJLw3RBQBOAQAAAA==.Behomethan:BAABLgAECn8VAAMGAAgJTxZLKgDlAQAGAAcJ5xVLKgDlAQAHAAUJSRFcSAAmAQAAAA==.Beyonsláy:BAAALgADCgIJAgAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJAgAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.',
Bo='Bobbyb:BAAALgAECgYJCwAAAA==.Bombchele:BAAALgADCggJJwABLgAECggJFwAIAIcaAA==.Boneulngtime:BAAALgADCgUJBQAAAA==.Boon:BAAALgADCggJEQAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAAALgAECgkJDAAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8WAAIGAAgJqCO6AADvAgAGAAgJqCO6AADvAgAAAA==.Bunnymedic:BAAALgADCggJDwABLgAECggJFgAGAKgjAA==.',
Ca='Caebrylla:BAAALgAECgYJEAAAAA==.Camil:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Capulin:BAABLgAECn8UAAIJAAYJrBfPCwBjAQAJAAYJrBfPCwBjAQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecimorte:BAAALgAECgYJEAAAAA==.Cephalopod:BAAALgAECgcJDQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgMJAwAAAA==.Chonker:BAABLgAECn8dAAMKAAgJLxw8BwD0AQAKAAcJjRs8BwD0AQALAAIJyAukbwBgAAAAAA==.Chorelock:BAAALgADCgEJAQAAAA==.Chronormu:BAAALgADCgEJAQAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8VAAQMAAYJMBX4FQBYAQAMAAYJMBX4FQBYAQALAAEJ2wHdjgAeAAAKAAEJAgK+6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn8cAAINAAgJbhb/AgCFAQANAAgJbhb/AgCFAQAAAA==.',
Cl='Claxious:BAAALgAECgYJDQAAAA==.Claye:BAABLgAECn8eAAIGAAkJ7xFUJgD6AQAGAAkJ7xFUJgD6AQAAAA==.',
Co='Coldshoulder:BAAALgAECgYJEAAAAA==.Corelas:BAAALgAECgUJBwAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgEJAgAAAA==.',
Cr='Crazymadman:BAAALgADCgcJDQAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Dawnson:BAAALgAECgYJEQAAAA==.',
De='Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAAALgADCgQJBAAAAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgADCgQJCAAAAA==.',
Di='Didimissfire:BAEBLgAECn8dAAIOAAgJaw2BNgDUAQAOAAgJaw2BNgDUAQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBgAAAA==.',
Dp='Dpsmaster:BAAALgAECgMJCAAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgADCggJDAAAAA==.',
Du='Dumonster:BAAALgADCgcJFgAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgADCgIJAgAAAA==.Eirenne:BAAALgAECgEJAQAAAA==.',
El='Elindril:BAAALgAECgQJBQAAAA==.',
En='Enoth:BAAALgADCgkJFgAAAA==.',
Eo='Eowynn:BAAALgAECgcJDQAAAA==.',
Es='Estella:BAABLgAECn8VAAIDAAYJ/QekNgDqAAADAAYJ/QekNgDqAAAAAA==.',
Ev='Eventhorizon:BAAALgAECgYJBQAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAAALgAECgYJEwAAAA==.Faythh:BAABLgAECn8bAAIPAAgJ9h2QAgBFAgAPAAgJ9h2QAgBFAgAAAA==.',
Fe='Fedoran:BAABLgAECn8VAAMMAAcJHCGkCABTAgAMAAYJqiKkCABTAgALAAUJ7R1ETgDwAAAAAA==.Fenastic:BAAALgAECgYJEwAAAA==.Fenrisúlfur:BAAALgAECgUJCAAAAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAAALgAECgUJBQAAAA==.Fixeruper:BAAALgAECgYJDwAAAA==.',
Fl='Flubberduck:BAAALgADCgUJBgAAAA==.Fluffybeer:BAAALgAECgcJDwAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgUJDgABAAAAAA==.Footdig:BAAALgAECgUJCAAAAA==.',
Fu='Fuquan:BAAALgADCgEJAQAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgQJBAAAAA==.Gless:BAAALgADCggJJgAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgADCgcJBwAAAA==.',
Gu='Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Haenus:BAAALgADCgQJAgAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8XAAIQAAgJUBJlFAB+AQAQAAgJUBJlFAB+AQAAAA==.Honourz:BAAALgAECgYJBgABLgAECggJHgARALcXAA==.',
Ih='Ihatepallys:BAAALgADCgcJEAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgQJBAAAAA==.Ilidank:BAAALgAECgMJAwAAAA==.Ilya:BAAALgADCgcJBwABLgAECgQJCwABAAAAAA==.',
In='Indigo:BAABLgAECn8cAAIGAAgJXRppAwBKAgAGAAgJXRppAwBKAgAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8WAAISAAYJwA7kCAATAQASAAYJwA7kCAATAQAAAA==.',
Ir='Irisblue:BAAALgADCgQJCgAAAA==.',
Iy='Iyahli:BAAALgAECgMJBgAAAA==.',
Ja='Jarclian:BAABLgAECn8mAAIDAAkJiBx/GQASAwADAAkJiBx/GQASAwAAAA==.Jaymonk:BAAALgADCgkJCgAAAA==.',
Je='Jezzea:BAAALgADCgQJBwAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.',
['Jâ']='Jâtens:BAABLgAECn8YAAITAAcJxhsABwAFAgATAAcJxhsABwAFAgAAAA==.',
Ka='Kaelía:BAAALgADCggJDQAAAA==.Kair:BAABLgAECn8dAAIRAAgJjgY2CgAvAQARAAgJjgY2CgAvAQAAAA==.Kairring:BAAALgAECgQJBAAAAA==.Kamehameha:BAAALgAECgMJBAAAAA==.Kami:BAABLgAECn8cAAIRAAgJ7w+jBQCWAQARAAgJ7w+jBQCWAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAAALgADCgQJBAAAAA==.Katteya:BAAALgADCggJJwAAAA==.Kattia:BAABLgAECn8cAAIOAAgJ+Qy6CwCwAQAOAAgJ+Qy6CwCwAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBAAAAA==.',
Ki='Kinomihime:BAABLgAECn8cAAIDAAgJWA6XFwCIAQADAAgJWA6XFwCIAQAAAA==.Kirajoy:BAABLgAECn8bAAIUAAgJ5ANQBQDzAAAUAAgJ5ANQBQDzAAAAAA==.Kirel:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAAALgAECgYJEQAAAA==.',
Ko='Kogwyn:BAAALgAECggJBwAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJBwABAAAAAA==.',
Kr='Kraviz:BAAALgADCgUJBQAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECgYJFAAOAFoKAA==.Krystle:BAAALgAECgYJCgAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAAALgAECgUJDgAAAA==.Livik:BAAALgAECgYJDwAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgQJBAAAAA==.Lorcan:BAABLgAECn8bAAIVAAgJehYzAgDGAQAVAAgJehYzAgDGAQAAAA==.',
Lr='Lroye:BAAALgAFFAEJAQAAAA==.',
Ls='Lsdarko:BAAALgADCggJCQAAAA==.',
Lu='Luckyleet:BAAALgADCgQJBwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECggJFQAOALoKAA==.Ludicrispeed:BAAALgADCgQJCgAAAA==.Luliak:BAABLgAFFH8GAAIWAAMJ/BlnAgAgAQAWAAMJ/BlnAgAgAQAAAA==.Lunabren:BAAALgAECgYJCwAAAA==.Lunamina:BAAALgADCggJHQAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAAALgAECgcJCwAAAA==.',
['Lì']='Lìllith:BAAALgAECgYJCgABLgAECggJIAAQANQZAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAAALgAECgYJEAAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Misstorgo:BAAALgADCgkJIgAAAA==.',
Mo='Monfro:BAAALgAECgUJCgAAAA==.Moonbane:BAABLgAECn8cAAIUAAgJORx3AABCAgAUAAgJORx3AABCAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgQJCgAAAA==.Mystogan:BAAALgADCgUJCQAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAAALgAECgYJDAAAAA==.Natsuu:BAABLgAECn8XAAIOAAgJFhl3BwDyAQAOAAgJFhl3BwDyAQAAAA==.Naturewolf:BAABLgAECn8WAAIMAAcJqBbYDQDWAQAMAAcJqBbYDQDWAQAAAA==.',
Ne='Nekona:BAAALgAECgYJEAAAAA==.Neron:BAABLgAECn8gAAIQAAgJ1BkTCgDrAQAQAAgJ1BkTCgDrAQAAAA==.Nethertusk:BAABLgAECn8fAAMXAAgJxBQTEACRAQAXAAgJxBQTEACRAQAUAAIJYQPlWQBhAAAAAA==.',
Nh='Nhancecntrl:BAAALgAECgcJDgABLgAECggJGwAYAOMUAA==.',
Ni='Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAAALgAECgUJBwABLgAFFAMJBwAZAKcMAA==.Nimposter:BAAALgAECgYJEwAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgUJBgAAAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ob='Obizi:BAAALgADCgcJBwAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAAALgAECggJDQAAAA==.',
Ou='Outerlimits:BAABLgAECn8YAAIaAAcJgxqlBAANAgAaAAcJgxqlBAANAgAAAA==.',
Pa='Paindore:BAAALgADCgUJCgAAAA==.Pamboo:BAABLgAECn8cAAIbAAcJ8Q1rEQAoAQAbAAcJ8Q1rEQAoAQAAAA==.',
Pe='Pearle:BAABLgAECn8cAAIZAAgJcRy4AgDeAQAZAAgJcRy4AgDeAQAAAA==.',
Ph='Phyg:BAAALgAECgQJBQAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECggJHwAPALwYAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgADCgMJAwAAAA==.Ramindizzle:BAABLgAECn8cAAIcAAcJ0g9PBgAUAQAcAAcJ0g9PBgAUAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAAALgAECgYJDgAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgQJCgAAAA==.',
Ro='Rook:BAABLgAECn8bAAIcAAcJ6AbgBQAhAQAcAAcJ6AbgBQAhAQAAAA==.Roye:BAACLgAFFH8GAAIQAAMJFAY8GQDfAAAQAAMJFAY8GQDfAAAuAAQKfx4AAhAACQlvHYYGACcCABAACQlvHYYGACcCAAAA.',
Ru='Ruffiyo:BAABLgAECn8bAAMTAAgJXRKkDQCiAQATAAgJ/Q+kDQCiAQASAAYJYhKGLQBfAQAAAA==.Rugrahh:BAABLgAECn8gAAIcAAkJdB4rDwDFAgAcAAkJdB4rDwDFAgAAAA==.Ruthen:BAAALgADCgkJEgAAAA==.Ruìn:BAAALgAECgMJAwAAAA==.',
Sa='Sabermore:BAAALgAECgQJCAAAAA==.Sabina:BAABLgAECn8cAAIHAAgJcAZ3EQD6AAAHAAgJcAZ3EQD6AAAAAA==.Sadako:BAAALgADCgMJAwABLgAECggJFQAOALoKAA==.Sadness:BAAALgADCggJJQAAAA==.Sadorick:BAAALgADCggJJgAAAA==.Safira:BAAALgAECgQJBgABLgAECggJIAAQANQZAA==.Sageguy:BAAALgADCggJGgAAAA==.Sango:BAABLgAECn8gAAMSAAgJYwx1BACSAQASAAgJYwx1BACSAQATAAQJ2gJ1wQB8AAAAAA==.Savagelykill:BAAALgAECgIJAgAAAA==.',
Sc='Scotch:BAABLgAECn8bAAMQAAgJwxr6BwAKAgAQAAgJwxr6BwAKAgAdAAIJcRHGMQCHAAAAAA==.Scotchnwater:BAAALgADCgYJBgAAAA==.Scrubyheals:BAAALgADCgQJBwAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgEJAQAAAA==.Shadowlock:BAAALgAECggJEQAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shamangroo:BAAALgADCgYJBgABLgADCgcJDQABAAAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Shivalry:BAAALgADCgMJAwAAAA==.Shmiggy:BAAALgADCgYJDAAAAA==.',
Si='Silverywolfe:BAAALgADCggJJgAAAA==.Simony:BAAALgAECgUJEQABLgAECggJFQAOALoKAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgYJDgAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8fAAIPAAgJvBjvEwA/AgAPAAgJvBjvEwA/AgAAAA==.',
Sp='Specialk:BAAALgADCggJHwAAAA==.',
St='Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAAALgADCgcJDwAAAA==.',
Su='Sunil:BAABLgAECn8cAAIPAAgJWBMMBAABAgAPAAgJWBMMBAABAgAAAA==.Suviqhabo:BAAALgAECgcJDQAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8aAAIFAAgJJCGUAACrAgAFAAgJJCGUAACrAgAAAA==.Syladen:BAAALgAECgYJEgAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgADCgcJDQAAAA==.Tavendar:BAAALgADCgQJBAABLgAECgkJHgAGAO8RAA==.Taírn:BAAALgADCgQJBAAAAA==.',
Te='Techie:BAAALgAECgUJBQAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAAALgADCgUJCAAAAA==.Thôrin:BAAALgADCggJDAAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn8bAAMQAAgJuhIrFACAAQAQAAgJ4hErFACAAQAdAAIJlhSrNgBoAAAAAA==.Timotheus:BAAALgADCgcJEAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8XAAIeAAcJywuBEgCPAQAeAAcJywuBEgCPAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn8dAAIXAAgJKRzGIgCKAgAXAAgJKRzGIgCKAgAAAA==.',
Ul='Ulyaoth:BAAALgAECgUJEAAAAA==.',
Un='Unnerfable:BAAALgAECgQJBgAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJCQAAAA==.Valkyrie:BAAALgAECgEJAQAAAA==.',
Ve='Vedros:BAAALgADCgQJBwAAAA==.Velowin:BAAALgADCgcJBwAAAA==.',
Vi='Viktoros:BAAALgADCgQJBAAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorukh:BAAALgAECgYJBgAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgADCggJJgABLgAECggJHAAGAF0aAA==.',
Wa='Warriorgroo:BAAALgADCgcJDQAAAA==.',
We='Wendish:BAAALgAECgEJBQAAAA==.Wertyda:BAAALgAECgYJDwAAAA==.',
Wh='Whácker:BAAALgAECggJEgABLgADCgQJBAABAAAAAA==.',
Wi='Wickedslicks:BAABLgAECn8VAAILAAYJ/BzSJADXAQALAAYJ/BzSJADXAQAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8XAAIIAAgJhxpgBwAKAgAIAAgJhxpgBwAKAgAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xa='Xalafeet:BAAALgADCgUJBQAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAAALgAECgYJCwAAAA==.Xxpallyz:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8cAAIIAAgJKRXURwAcAgAIAAgJKRXURwAcAgAAAA==.',
Yo='Yohh:BAAALgAECgMJBAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn8cAAIfAAgJlhC7BwCEAQAfAAgJlhC7BwCEAQAAAA==.',
Za='Zaidan:BAAALgADCgcJDQAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBQAAAA==.',
Ze='Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn8dAAINAAgJcBivCAAfAgANAAgJcBivCAAfAgAAAA==.Zornhealer:BAAALgADCggJEAABLgAECgEJAgABAAAAAA==.',
['Zö']='Zölä:BAAALgADCgMJAwAAAA==.',
['Ât']='Âtomic:BAAALgADCgYJAgABLgADCgQJBAABAAAAAA==.',
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

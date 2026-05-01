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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Druid-Guardian','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Frost','Warrior-Arms','Druid-Restoration','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Warrior-Protection','Hunter-BeastMastery','Mage-Arcane','Shaman-Elemental','Monk-Mistweaver','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aahzbear:BAAALgAECgUJDAAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhe/HwCWAQABAAYJNhe/HwCWAQAAAA==.Aerendyl:BAAALgAECgcJBwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRDYFwDbAAACAAMJbRDYFwDbAAAuAAQKfxQAAgIABgkfHGAqALcBAAIABgkfHGAqALcBAAAA.',
Am='Amathal:BAAALgAECgcJEgAAAA==.Amilea:BAAALgAECgQJBAABLgABCgkJCQADAAAAAA==.',
An='Anastasia:BAAALgADCgcJBwAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAECgYJBgAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAAALgAECgYJDwAAAA==.Arinth:BAAALgADCggJEQAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ashiiro:BAAALgAECgcJEAAAAA==.Asia:BAABLgAECn8tAAIEAAkJsiBrAgAMAwAEAAkJsiBrAgAMAwAAAA==.Asmodeius:BAAALgAFFAEJAQAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJEAADAAAAAA==.',
At='Athrea:BAAALgAECggJEwAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.',
Ba='Babilouchoux:BAAALgADCgUJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJBgABLgAECgYJCwADAAAAAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bd='Bdssm:BAAALgAECgYJDAAAAA==.',
Be='Beefstick:BAAALgAECgQJBAAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAAALgAECgYJEwAAAA==.',
Bh='Bhemtu:BAAALgADCgMJBAAAAA==.',
Bi='Biercan:BAAALgAECggJDQAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgcJDAAAAA==.Bittywhite:BAAALgADCgkJFwAAAA==.Bittywyvern:BAAALgADCgUJBQABLgADCgkJFwADAAAAAA==.',
Bl='Blayze:BAAALgAECgcJDgAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCAAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECggJEAAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAAALgAECgQJEAAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECgYJCwAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn8tAAIFAAkJOx/KAQBmAgAFAAkJOx/KAQBmAgAAAA==.Brayker:BAABLgAECn8tAAIGAAkJ4iT4AQAfAwAGAAkJ4iT4AQAfAwAAAA==.Breadoneal:BAABLgAECn8cAAIHAAcJzxmNDAAOAgAHAAcJzxmNDAAOAgAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8VAAIIAAcJgBOrFwAsAQAIAAcJgBOrFwAsAQAAAA==.Brisketbane:BAAALgAECgcJDwAAAA==.Brokenmask:BAAALgAFFAIJAgAAAA==.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.',
Bu='Burntroot:BAAALgAECgYJEQAAAA==.',
Ca='Caedwyn:BAABLgAECn8ZAAIJAAgJLB2bAgA3AgAJAAgJLB2bAgA3AgAAAA==.Caitrakk:BAAALgAECgYJEAAAAA==.Calignus:BAABLgAECn8cAAMGAAgJ9xAHOQBgAQAGAAgJ9xAHOQBgAQAKAAUJVQ8fJwDQAAAAAA==.Captjack:BAABLgAECn8ZAAILAAgJQAu+LgApAQALAAgJQAu+LgApAQAAAA==.Cartilage:BAAALgAECgcJDwAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgEJAQAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgADAAAAAA==.Choconilla:BAAALgADCggJCAAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgMJAwABLgAECggJIAALABwTAA==.Consuming:BAAALgAECgUJEwAAAA==.Coorsbanquet:BAAALgAECgYJDAAAAA==.Corgh:BAABLgAECn8eAAIMAAYJtA4XBgBIAQAMAAYJtA4XBgBIAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgADCgMJAwAAAA==.Crash:BAECLgAFFH8FAAILAAMJ8xa+IgC5AAALAAMJ8xa+IgC5AAAuAAQKfyUAAwsACAm8I9cVANMCAAsACAm8I9cVANMCAA0AAQkfGVwVAEsAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn8sAAIHAAkJpxfQCgApAgAHAAkJpxfQCgApAgAAAA==.',
Cy='Cybear:BAAALgAECgQJBAAAAA==.Cykun:BAABLgAECn8oAAIOAAgJlR+9AgCLAgAOAAgJlR+9AgCLAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgAAAA==.',
Da='Darch:BAABLgAECn8tAAMPAAkJtSNlAAA1AwAPAAkJtSNlAAA1AwAQAAEJPwmekAAqAAAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCgAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAABLgAECn8VAAIRAAcJNw9hNgBgAQARAAcJNw9hNgBgAQAAAA==.Demine:BAABLgAECn8ZAAISAAcJpB3mYAAZAgASAAcJpB3mYAAZAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgAAAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAAALgAECggJEgAAAA==.',
Do='Donbarriga:BAAALgAECgMJAwAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgADAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAABLgAECn8aAAITAAgJSxWWBwBEAgATAAgJSxWWBwBEAgAAAA==.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8VAAIUAAYJiwbFPgDWAAAUAAYJiwbFPgDWAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAABLgAECn8pAAIVAAgJhxiWAwALAgAVAAgJhxiWAwALAgAAAA==.',
Ej='Ejavuday:BAABLgAECn8fAAISAAgJgSHXEABWAgASAAgJgSHXEABWAgAAAA==.',
El='Elvudu:BAAALgAECgIJBAAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAECgIJAgABLgAECgQJBgADAAAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgADCgYJDAAAAA==.Ericdruid:BAABLgAECn8ZAAMWAAcJSiDxEgB+AgAWAAcJSiDxEgB+AgAUAAEJ6QqU1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8kAAIRAAcJoAX/TwAQAQARAAcJoAX/TwAQAQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAAALgAECgYJBwAAAA==.Explicatory:BAAALgAECgYJBgABLgAECgYJBwADAAAAAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAAALgAECgcJCQAAAA==.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJEgAAAA==.Feile:BAABLgAECn8tAAQEAAkJ7xR+EAAjAgAEAAkJ7xR+EAAjAgAXAAIJfgu6VwBnAAAYAAEJAAD1LwA+AAAAAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgEJAQAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQAAAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fo='Foolezz:BAAALgADCgMJAwAAAA==.',
Fr='Fredthedh:BAABLgAECn8aAAILAAgJFCNVFADeAgALAAgJFCNVFADeAgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgEJBAAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8aAAIRAAgJdyGoEgAkAgARAAgJdyGoEgAkAgAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgADCgcJBwAAAA==.Gethalyn:BAAALgAECgYJCQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAQAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCQABLgAECgQJCQADAAAAAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgYJBwADAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAECgQJBAAAAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn8eAAIUAAgJFB15BgCvAgAUAAgJFB15BgCvAgAAAA==.Grreenry:BAAALgAECgEJAQABLgAECgQJBAADAAAAAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgYJBwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hanswoloqued:BAABLgAECn8ZAAMEAAgJRwutNwBNAQAEAAgJRwutNwBNAQAYAAIJpgEPKgBLAAAAAA==.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8fAAIZAAgJzBnlCQAKAgAZAAgJzBnlCQAKAgAAAA==.Hellsong:BAAALgAECgMJAwAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Heysisters:BAAALgADCgEJAQAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAgAAAA==.',
Ho='Holysabeline:BAABLgAECn8tAAIHAAkJYRVADQAFAgAHAAkJYRVADQAFAgAAAA==.Honestleon:BAAALgADCgMJAwABLgAFFAEJAQADAAAAAA==.Hordechief:BAAALgAECgEJAgABLgAECgEJAgADAAAAAA==.',
Hu='Huchar:BAABLgAECn8kAAIaAAgJdhsVBgDyAQAaAAgJdhsVBgDyAQAAAA==.Huevos:BAAALgAECgEJAQAAAA==.Huntersteve:BAABLgAECn8hAAMbAAgJPyNHBAC8AgAbAAgJPyNHBAC8AgAQAAYJ7CCuIgAOAgAAAA==.',
Hy='Hydraxix:BAAALgAECgUJBQAAAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8aAAIHAAkJmxP2HwAaAgAHAAkJmxP2HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAAALgAECgQJCAAAAA==.Illsmurfuup:BAABLgAECn8XAAIPAAgJ9CZoAAClAwAPAAgJ9CZoAAClAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAAALgADCgcJBwAAAA==.Irôh:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgEJAQAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAAALgAECgYJEgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn8gAAIVAAkJvCDIAADPAgAVAAkJvCDIAADPAgAAAA==.',
Je='Jessaiyan:BAABLgAECn8aAAILAAkJBB0qGgC3AgALAAkJBB0qGgC3AgAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgADCgMJAwAAAA==.',
Ju='Julaudette:BAAALgAECgEJAgAAAA==.Julzaria:BAAALgAECgYJCwAAAA==.Julzoblin:BAAALgAECgEJAQAAAA==.Jurny:BAAALgAECgYJDAAAAA==.Jusdeen:BAABLgAECn8VAAMJAAgJGCIgAQCbAgAJAAgJGCIgAQCbAgAUAAEJXhkMwABHAAAAAA==.',
Ka='Kadookieii:BAAALgAECgQJBQAAAA==.Kahlandra:BAABLgAECn8lAAMcAAkJkhZZAQD7AQAcAAkJkhZZAQD7AQASAAIJggGFhAEjAAAAAA==.Kaizer:BAABLgAECn8jAAIdAAgJrxrbGABOAgAdAAgJrxrbGABOAgAAAA==.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgADCgQJBwABLgAECgYJGAAFAAMTAA==.Karina:BAABLgAECn8sAAMLAAkJWB7jBwBcAgALAAkJIx7jBwBcAgANAAgJFxJTBACxAQAAAA==.Kastravia:BAAALgAECgMJAwABLgAFFAQJCgAeAE0DAA==.Kawolski:BAAALgAECgIJAwABLgAFFAQJCgAeAE0DAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kevin:BAAALgAECgcJCgAAAA==.',
Kh='Khanjuror:BAABLgAECn8fAAIXAAcJGBH0BgBGAQAXAAcJGBH0BgBGAQAAAA==.Kholonoe:BAABLgAECn8bAAIfAAgJcBVQDAC8AQAfAAgJcBVQDAC8AQAAAA==.Khornedog:BAABLgAECn8XAAIEAAYJWhTINABYAQAEAAYJWhTINABYAQAAAA==.Khrama:BAAALgAECggJCQAAAA==.',
Ki='Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgADCgQJBQAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgADAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJDQADAAAAAA==.Kleenonean:BAACLgAFFH8FAAIfAAMJ6iCPCQAlAQAfAAMJ6iCPCQAlAQAuAAQKfzgAAx8ACAkRJtsAABkDAB8ACAkRJtsAABkDABkAAgnGBkd0AFcAAAAA.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8fAAIPAAkJLBDRCABXAgAPAAkJLBDRCABXAgAAAA==.',
Ku='Kungcarefu:BAABLgAECn8VAAICAAYJPhJhIQD4AAACAAYJPhJhIQD4AAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgIJAgAAAA==.Kurzak:BAAALgAECgMJAwAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECggJEwADAAAAAA==.Lacio:BAABLgAECn8sAAIfAAkJ7Qf8DwCNAQAfAAkJ7Qf8DwCNAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAABLgAECn8YAAIHAAgJKhvnDgDwAQAHAAgJKhvnDgDwAQAAAA==.',
Le='Lemonite:BAABLgAECn8UAAIUAAgJyhzmFACOAgAUAAgJyhzmFACOAgAAAA==.Lennykoggins:BAAALgAECgUJDgAAAA==.Leyru:BAAALgAECggJEwAAAA==.',
Li='Liberos:BAAALgAECgcJDQAAAA==.Lifenight:BAABLgAECn8YAAMgAAgJaBI9AwCgAQAgAAgJaBI9AwCgAQARAAEJvgD6PgEJAAAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8bAAMFAAcJ/BGdFQDSAAARAAcJ/BF0igBsAQAFAAcJeAadFQDSAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn8YAAMHAAkJRQlOEgDJAQAHAAkJRQlOEgDJAQAGAAEJ7gFf4QAmAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJCwAAAA==.Luticris:BAAALgADCggJEgAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgMJAwAAAA==.Maiden:BAAALgADCgUJCAABLgAECgYJGAAFAAMTAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Maxdeath:BAABLgAECn8lAAIRAAgJ9iO/DQAtAwARAAgJ9iO/DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgMJBAAAAA==.Mensrea:BAAALgAECgYJDQAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8cAAMRAAgJeyBeJQCqAQARAAcJpCFeJQCqAQAFAAMJtRLqJgBJAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECggJHAARAHsgAA==.Merrygored:BAAALgAECgIJAgABLgAECggJHAARAHsgAA==.Mess:BAAALgAECgYJEQABLgAECgYJGAAFAAMTAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8kAAMPAAYJdyZVBQAlAgAPAAYJdyZVBQAlAgAQAAEJlCXAFwBuAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAAALgAECgYJCgAAAA==.Mizirath:BAAALgAECgMJAwABLgAECggJGQAJACwdAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8YAAIhAAgJ6hXyEAAsAgAhAAgJ6hXyEAAsAgAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAAALgAECgYJCgAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgUJBQABLgAECggJJgAZAIUlAA==.Moopsta:BAAALgADCggJDgABLgAECggJJgAZAIUlAA==.Moopster:BAABLgAECn8mAAIZAAgJhSXTAABRAwAZAAgJhSXTAABRAwAAAA==.Mordekaiserz:BAAALgAECgUJCgAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAABLgAECn8XAAIiAAgJ3RETDQC4AQAiAAgJ3RETDQC4AQAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAAALgAECgQJBAAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgEJAgAAAA==.',
Ni='Nicktee:BAAALgAECgUJBwAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAAALgAECgYJCwAAAA==.Niquid:BAABLgAECn8YAAIUAAcJkxNCTABzAQAUAAcJkxNCTABzAQAAAA==.',
No='Nolmac:BAAALgAECgQJBAAAAA==.Notahealer:BAAALgAECgYJBwAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAAALgAFFAEJAQAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn8ZAAIIAAgJ2xoUCgDVAQAIAAgJ2xoUCgDVAQAAAA==.',
Ol='Olivertwist:BAAALgAECgQJBgAAAA==.',
On='Ontwou:BAAALgAECgYJCgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJCAAAAQ==.',
Ou='Ouchpotato:BAAALgAECgIJAgABLgAECggJHwAOAG0eAA==.',
Pa='Paarthurnax:BAAALgAECgUJBQAAAA==.Palathal:BAAALgAECgUJBQABLgAECgcJEgADAAAAAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAABLgAECn8WAAIIAAgJPCKWBwACAwAIAAgJPCKWBwACAwAAAA==.Pancakezebra:BAABLgAECn8uAAIPAAkJUhkaAwBuAgAPAAkJUhkaAwBuAgAAAA==.Pantsftw:BAABLgAECn8XAAIZAAcJCwsIHQAcAQAZAAcJCwsIHQAcAQAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAAALgAECgYJEgAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Peltier:BAABLgAECn8oAAISAAkJdCCNBQDiAgASAAkJdCCNBQDiAgAAAA==.Pendle:BAAALgAECgcJEgAAAA==.',
Ph='Phoenix:BAABLgAECn8VAAIGAAYJeyG+PgAqAgAGAAYJeyG+PgAqAgAAAA==.',
Pl='Plox:BAAALgAECgYJDwAAAA==.Plurnizz:BAABLgAECn8UAAMEAAgJwwN2qAAIAQAEAAgJwwN2qAAIAQAXAAQJEwHFXwBPAAAAAA==.',
Po='Pocketchange:BAAALgAFFAEJAQAAAA==.',
Pu='Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8WAAICAAcJ4yOYEACVAgACAAcJ4yOYEACVAgABLgAECggJCQADAAAAAA==.Raiker:BAAALgAECgMJAwAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgYJCgAAAA==.Relovan:BAABLgAECn8cAAMTAAgJFQ3uBwCOAQATAAgJFQ3uBwCOAQAjAAUJSwOKhgClAAAAAA==.Renothidan:BAABLgAECn8fAAIGAAgJcxxTFwABAgAGAAgJcxxTFwABAgAAAA==.Reuben:BAAALgADCgYJCAAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECgMJAwABLgAECggJHwAaAGQiAA==.',
Ri='Rickyboby:BAAALgAECgEJAQAAAA==.Righteøus:BAAALgAECgQJCgAAAA==.Rillan:BAAALgAECgUJDwAAAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn8mAAIjAAkJ6CRKAABeAwAjAAkJ6CRKAABeAwAAAA==.Rizzdolphler:BAAALgAFFAIJAgAAAA==.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECgYJGAAFAAMTAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAABLgAECn8pAAIEAAkJlhx7BQC7AgAEAAkJlhx7BQC7AgAAAA==.',
Sa='Sanako:BAABLgAECn8fAAIWAAkJCQs+EgB5AQAWAAkJCQs+EgB5AQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECgEJAQABLgAECggJIAALABwTAA==.Santoniche:BAAALgAECgMJAwAAAA==.Sap:BAAALgAECgYJEQABLgAECgYJGAAFAAMTAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8gAAILAAgJHBOTRgDZAQALAAgJHBOTRgDZAQAAAA==.Scyther:BAABLgAECn8VAAMLAAgJOg3GcQBPAQALAAgJPgzGcQBPAQAkAAUJUA6XSgDGAAAAAA==.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAAALgAECgQJCQAAAA==.Serenade:BAACLgAFFH8GAAISAAIJWxl2RAC0AAASAAIJWxl2RAC0AAAuAAQKfyAAAhIACAmrHxQzAKYCABIACAmrHxQzAKYCAAAA.Setheron:BAAALgAECgQJCQAAAA==.Sethron:BAAALgAECgEJAQAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamtul:BAAALgAECgEJAQAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAABLgAECn8aAAIiAAgJJA/CEwBlAQAiAAgJJA/CEwBlAQAAAA==.Shyva:BAABLgAECn8fAAMaAAgJZCI4AgCLAgAaAAgJZCI4AgCLAgAjAAEJLg05UgA8AAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDQABLgAECggJKQAEAP8gAA==.',
Sl='Slayla:BAAALgAECgMJAwAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Sneak:BAAALgADCgMJAwABLgAECgYJCwADAAAAAA==.',
So='Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgEJAQAAAA==.',
Sp='Spacehog:BAAALgAECgYJCgAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgADCgUJBQAAAA==.',
St='Standarshh:BAABLgAECn8hAAIbAAgJnRowFADxAQAbAAgJnRowFADxAQAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAABLgAECn8fAAMOAAgJbR4qDQDHAgAOAAgJbR4qDQDHAgAlAAUJowYTCQCZAAAAAA==.Sugarbabi:BAABLgAECn8bAAMUAAgJyB0vIQA7AgAUAAcJ3x4vIQA7AgAWAAUJmhRKFgBNAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn8tAAMZAAkJTh15BQBrAgAZAAkJTh15BQBrAgABAAQJrghkIgDAAAAAAA==.Sylveste:BAABLgAECn8eAAIHAAcJFBoEEgDNAQAHAAcJFBoEEgDNAQAAAA==.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAAALgAECgYJCQAAAA==.Tankhiskhan:BAAALgAECgcJEwAAAA==.Tarlis:BAABLgAECn8VAAIYAAgJoRq8BAAqAgAYAAgJoRq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBQAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAAALgAECgcJEQAAAA==.',
Ti='Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8aAAIhAAcJGgkeKgAhAQAhAAcJGgkeKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJCAAAAA==.Tom:BAAALgAECgEJAgAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgMJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8bAAMOAAYJ1yRKAQD/AQAOAAUJYiRKAQD/AQAmAAIJoR4TBQB2AAAuAAQKfyAAAg4ACQmtJQABAMMDAA4ACQmtJQABAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn8kAAIaAAkJ2RaCBQAEAgAaAAkJ2RaCBQAEAgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgIJAgAAAA==.',
Ty='Tym:BAAALgAECgkJCwAAAA==.',
Ug='Ugargro:BAAALgAECgEJAQAAAA==.',
Un='Unapologetic:BAAALgAECgQJBAAAAA==.Unbreakabull:BAAALgADCgYJBgAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8YAAMFAAYJAxMbIwApAQAFAAYJAxMbIwApAQARAAMJKgpA/wB8AAAAAA==.',
Va='Valcuna:BAAALgAECgEJAgAAAA==.Valka:BAAALgAECgcJDQAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwADAAAAAA==.Vanaan:BAAALgADCgYJBgAAAA==.Varidrus:BAAALgADCgYJBwAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAISAAkJ6hVQHQD8AQASAAkJ6hVQHQD8AQAAAA==.Veyle:BAABLgAECn8tAAMOAAkJvyPEAAAYAwAOAAkJvyPEAAAYAwAmAAEJKh67GwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8bAAIkAAYJDhrxDABtAQAkAAYJDhrxDABtAQAAAA==.',
Vo='Voidsurge:BAAALgAECgUJEQABLgAECgYJGAAFAAMTAA==.',
Vy='Vyndria:BAAALgADCgcJBwAAAA==.',
We='Weaspore:BAABLgAECn8gAAIRAAgJhx6oDABiAgARAAgJhx6oDABiAgAAAA==.Weasy:BAAALgAECgQJBAAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJAgAAAA==.Woogieboogie:BAAALgADCgEJAQABLgAECgIJAgADAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9OAAMkAAgJ+RxVCwCrAgAkAAgJhxxVCwCrAgALAAYJZA3HRADXAAAAAA==.',
Yh='Yharnem:BAAALgAECgcJDAAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAAALgAECgYJDwAAAA==.Zakaraki:BAABLgAECn8sAAQnAAkJ/SRHAAAFAwAnAAkJ/SRHAAAFAwAiAAcJKiGdBQBOAgAhAAcJTQd1JgBBAQAAAA==.Zaki:BAABLgAECn8WAAILAAYJvSGnFADEAQALAAYJvSGnFADEAQAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgADCgIJAgAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAECgEJAwAAAA==.Zerathis:BAABLgAECn8pAAIEAAgJ/yAtEwDjAgAEAAgJ/yAtEwDjAgAAAA==.Zerathül:BAAALgAECgIJBQAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgEJAQAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
['Zõ']='Zõshow:BAAALgAECgYJEAAAAA==.',
['Ða']='Ðaredevil:BAAALgAECgYJDwAAAA==.',
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

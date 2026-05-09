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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Mage-Frost','Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Monk-Mistweaver','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Hunter-Survival','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','Evoker-Devastation','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','DemonHunter-Havoc','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aahzbear:BAAALgAECgUJDAAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhe/HwCWAQABAAYJNhe/HwCWAQAAAA==.Aerendyl:BAAALgAECgcJBwAAAA==.',
Ai='Aiden:BAACLgAFFH8HAAICAAMJbRCxIQDWAAACAAMJbRCxIQDWAAAuAAQKfxQAAgIABgkfHF0qALcBAAIABgkfHF0qALcBAAAA.',
Am='Amathal:BAABLgAECn8WAAIDAAgJ9RNLTACEAQADAAgJ9RNLTACEAQAAAA==.Amilea:BAAALgAECgUJBQABLgABCgkJCQAEAAAAAA==.',
An='Anastasia:BAAALgADCggJCAAAAA==.Angelsevoker:BAAALgAECggJCAAAAA==.Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAFFAEJAQAAAA==.Anubbus:BAAALgAECggJCAAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Arbalest:BAAALgADCgcJBgAAAA==.Aredhela:BAAALgAECggJEQAAAA==.Arinth:BAAALgADCggJEQAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ashiiro:BAAALgAECgcJEAAAAA==.Ashveil:BAAALgAECgQJBAAAAA==.Asia:BAABLgAECn82AAIFAAkJFiR2AgA6AwAFAAkJFiR2AgA6AwAAAA==.Asmodeius:BAAALgAFFAEJAQAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJFAAGAFsaAA==.',
At='Athrea:BAABLgAECn8UAAMHAAkJkRsqEgBQAQAIAAgJcBiVcgCiAQAHAAUJUBsqEgBQAQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAgAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.',
Ba='Babilouchoux:BAAALgADCgUJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Barnre:BAAALgAECgYJBgABLgAECgYJCwAEAAAAAA==.Baythos:BAAALgAFFAEJAgAAAA==.',
Bd='Bdssm:BAAALgAECgYJDgAAAA==.',
Be='Beefstick:BAAALgAECgQJBQAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAABLgAECn8bAAIJAAgJTQ29CAByAQAJAAgJTQ29CAByAQAAAA==.',
Bh='Bhemtu:BAAALgADCgMJBAAAAA==.',
Bi='Biercan:BAAALgAECggJDQAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgcJDAAAAA==.Bittywhite:BAAALgADCgkJFwAAAA==.Bittywyvern:BAAALgADCgUJBQABLgADCgkJFwAEAAAAAA==.',
Bl='Blayze:BAAALgAECgcJDgAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJCAAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECggJEgAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAAALgAECgQJEQAAAA==.Boibye:BAAALgAECgYJDgAAAA==.Bolblock:BAAALgAECggJDQAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn82AAIHAAkJpiDhAQDtAgAHAAkJpiDhAQDtAgAAAA==.Brayker:BAABLgAECn82AAIKAAkJ7CQXAgBGAwAKAAkJ7CQXAgBGAwAAAA==.Breadoneal:BAABLgAECn8cAAILAAcJzxmcEwD3AQALAAcJzxmcEwD3AQAAAA==.Breeze:BAAALgAECgYJBgAAAA==.Brewed:BAABLgAECn8dAAMMAAgJeBJpFACMAQAMAAgJeBJpFACMAQANAAEJLwHsZwAMAAAAAA==.Brisketbane:BAAALgAECgcJDwAAAA==.Brokenmask:BAABLgAFFH8GAAIOAAMJ4xDTIgDKAAAOAAMJ4xDTIgDKAAAAAA==.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.Brüenor:BAAALgAECgIJAgAAAA==.',
Bu='Burntroot:BAABLgAECn8WAAIPAAcJiAMfOwC/AAAPAAcJiAMfOwC/AAAAAA==.',
Ca='Caedwyn:BAABLgAECn8hAAIQAAgJzR4nAwBpAgAQAAgJzR4nAwBpAgAAAA==.Caitrakk:BAABLgAECn8UAAMGAAYJWxqdMgC7AQAGAAYJWxqdMgC7AQAPAAUJYhC4TAAVAQAAAA==.Calignus:BAABLgAECn8cAAMKAAgJ9xDxUABUAQAKAAgJ9xDxUABUAQARAAUJVQ8dJwDQAAAAAA==.Captjack:BAABLgAECn8cAAISAAgJDQz3QQAzAQASAAgJDQz3QQAzAQAAAA==.Cartilage:BAABLgAECn8WAAIIAAcJSRU9PwB/AQAIAAcJSRU9PwB/AQAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.Celys:BAAALgAECgEJAQAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Choconilla:BAAALgAECgQJBAAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.',
Ci='Cinnomun:BAAALgADCgEJAQAAAA==.',
Co='Combustinme:BAAALgAECgQJBAABLgAECggJKAASAHkVAA==.Consuming:BAABLgAECn8aAAIOAAYJyBWOUABjAQAOAAYJyBWOUABjAQAAAA==.Coorsbanquet:BAAALgAECggJDgAAAA==.Coorsbite:BAAALgADCgEJAQAAAA==.Corgh:BAABLgAECn8kAAITAAYJtw4XBgBIAQATAAYJtw4XBgBIAQAAAA==.Corrahthecow:BAAALgADCgEJAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Craccjar:BAAALgADCgMJAwAAAA==.Crash:BAECLgAFFH8IAAISAAQJmxnJGABGAQASAAQJmxnJGABGAQAuAAQKfysAAxIACAnxI24GAMMCABIACAnxI24GAMMCABQAAQkfGVYbAEkAAAAA.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn81AAILAAkJKhiNEAAXAgALAAkJKhiNEAAXAgAAAA==.',
Cy='Cybear:BAAALgAECgQJBQAAAA==.Cykun:BAABLgAECn8oAAIVAAgJlR9MBQBpAgAVAAgJlR9MBQBpAgAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECggJFAAOAMQOAA==.',
Da='Darch:BAABLgAECn82AAMWAAkJ+CPbAAAtAwAWAAkJ+CPbAAAtAwAJAAEJPwmykAAqAAAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deathscreams:BAAALgAECgQJBgAAAA==.Deathxreaper:BAAALgAECgQJCgAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAABLgAECn8bAAIIAAcJLxKeQgB1AQAIAAcJLxKeQgB1AQAAAA==.Demine:BAABLgAECn8hAAIDAAgJNB2kGgBKAgADAAgJNB2kGgBKAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgABLgAFFAYJGgAXAA0dAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAAALgAECgkJEwAAAA==.',
Do='Donbarriga:BAAALgAECgYJCAAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCwAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Draagone:BAAALgADCgUJBQABLgAECgcJCgAEAAAAAA==.Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAABLgAECn8jAAIYAAkJSRZ9BAA7AgAYAAkJSRZ9BAA7AgAAAA==.Dußad:BAAALgAECgMJBwAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAABLgAECn8bAAIOAAYJjAbrUQDOAAAOAAYJjAbrUQDOAAAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAABLgAECn8xAAIZAAgJOx4PAwBiAgAZAAgJOx4PAwBiAgAAAA==.',
Ej='Ejavuday:BAABLgAECn8gAAIDAAkJ4SDdDgCmAgADAAkJ4SDdDgCmAgAAAA==.',
El='Elvudu:BAAALgAECgIJBAAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
En='Enerchi:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgADCgYJDAAAAA==.Ericdruid:BAABLgAECn8aAAMaAAcJSiDxEgB+AgAaAAcJSiDxEgB+AgAOAAEJ6QqY1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8sAAIIAAkJ0gQbVwA5AQAIAAkJ0gQbVwA5AQAAAA==.Evokinpants:BAAALgAECgcJDwAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Excels:BAAALgAFFAIJAwAAAA==.Explicatory:BAAALgAECgYJBgABLgAFFAIJAwAEAAAAAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAACLgAFFH8IAAIIAAUJOw1MVgDfAAAIAAUJOw1MVgDfAAAuAAQKfxgAAggACAkWHA0UAFoCAAgACAkWHA0UAFoCAAAA.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJFQAAAA==.Feile:BAABLgAECn82AAQFAAkJxRcCEgBTAgAFAAkJxRcCEgBTAgAbAAIJfgu4VwBnAAAcAAEJAAD0LwA+AAAAAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgAECgEJAQAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQABLgAFFAQJBQADADYLAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fl='Flinzza:BAAALgADCgkJCQAAAA==.',
Fo='Foolezz:BAAALgADCgMJAwAAAA==.',
Fr='Fredthedh:BAABLgAECn8cAAISAAkJZSFSFADeAgASAAkJZSFSFADeAgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgIJBgAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8jAAIIAAkJciJgBwDmAgAIAAkJciJgBwDmAgAAAA==.Gashdk:BAAALgAECgEJAQABLgAECgIJBgAEAAAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Geraldo:BAAALgADCgcJBwAAAA==.Gethalyn:BAAALgAECgYJDwAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gh='Ghee:BAAALgAECgEJAgAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCQABLgAECgYJEQAEAAAAAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greennrry:BAAALgAECgQJBgABLgAFFAIJAgAEAAAAAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn8nAAIOAAkJHBshBwDcAgAOAAkJHBshBwDcAgAAAA==.Grreenry:BAAALgAFFAIJAgAAAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgYJBwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCggJDwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hanswoloqued:BAABLgAECn8aAAMFAAgJUQsvTABEAQAFAAgJUQsvTABEAQAcAAIJpgENKgBLAAAAAA==.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8fAAIdAAgJzBlNDwD0AQAdAAgJzBlNDwD0AQAAAA==.Hellsong:BAAALgAECgMJAwAAAA==.Hendo:BAAALgADCgYJBgAAAA==.Heysisters:BAAALgADCgYJBwAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAwAAAA==.',
Ho='Holysabeline:BAABLgAECn82AAILAAkJ2xVKEwD6AQALAAkJ2xVKEwD6AQAAAA==.Honestleon:BAAALgADCgMJAwABLgAFFAEJAQAEAAAAAA==.Hordechief:BAAALgAECgEJAgABLgAECgEJAgAEAAAAAA==.',
Hu='Huchar:BAABLgAECn8tAAIXAAkJ3B0sAwCcAgAXAAkJ3B0sAwCcAgAAAA==.Huevos:BAAALgAECgEJAQAAAA==.Huntersteve:BAABLgAECn8hAAMeAAgJPyOpCAAIAwAeAAgJPyOpCAAIAwAJAAYJ7CAUIwAOAgAAAA==.',
Hy='Hydraxix:BAAALgAECgUJBQAAAA==.',
['Hô']='Hônk:BAAALgADCgEJAQABLgAECgYJEQAEAAAAAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8fAAILAAkJKBb1HwAaAgALAAkJKBb1HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAAALgAECgUJDQAAAA==.Illsmurfuup:BAABLgAECn8ZAAIWAAkJ9SZnAAClAwAWAAkJ9SZnAAClAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Ironßest:BAAALgAECgEJAQAAAA==.Irôh:BAAALgAECgEJAQABLgAECgQJBwAEAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgAECgEJAQAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAABLgAECn8YAAIKAAYJfCQUHwAOAgAKAAYJfCQUHwAOAgAAAA==.Jaxxion:BAAALgADCgMJBQAAAA==.',
Jd='Jdawg:BAABLgAECn8tAAIZAAkJmCNbAABMAwAZAAkJmCNbAABMAwAAAA==.',
Je='Jessaiyan:BAABLgAECn8jAAISAAkJYx9RBgDFAgASAAkJYx9RBgDFAgAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Jj='Jjcjr:BAAALgADCgMJAwABLgAFFAUJEwAfAMAgAA==.',
Ju='Julaudette:BAAALgAECgQJBgAAAA==.Julzaria:BAAALgAECgYJDAAAAA==.Julzoblin:BAAALgAECgEJAQAAAA==.Jurny:BAAALgAECgYJDgAAAA==.Jusdeen:BAABLgAECn8XAAMQAAgJGCIvAgCeAgAQAAgJGCIvAgCeAgAOAAIJpxKNggBNAAAAAA==.',
Ka='Kadookieii:BAAALgAECgQJCQAAAA==.Kahlandra:BAABLgAECn8uAAMgAAkJNRcABAAXAgAgAAkJ+RYABAAXAgADAAgJ9gzeTQCAAQAAAA==.Kaizer:BAABLgAECn8jAAIPAAgJsBraGABOAgAPAAgJsBraGABOAgAAAA==.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgADCgQJCQABLgAECgYJHQAHAOQUAA==.Karina:BAABLgAECn81AAMSAAkJ3x5fCQCQAgASAAkJqx5fCQCQAgAUAAgJFRJVBgCaAQAAAA==.Kastravia:BAAALgAECgUJCAABLgAFFAQJDQANAEEEAA==.Kawolski:BAAALgAECgIJAwABLgAFFAQJDQANAEEEAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kevin:BAAALgAECgcJCgAAAA==.',
Kh='Khanjuror:BAABLgAECn8lAAIbAAcJHhPXBwBjAQAbAAcJHhPXBwBjAQAAAA==.Kholonoe:BAABLgAECn8bAAIhAAgJcBWPEgCzAQAhAAgJcBWPEgCzAQAAAA==.Khornedog:BAABLgAECn8eAAIFAAcJ5xUMMwCYAQAFAAcJ5xUMMwCYAQAAAA==.Khrama:BAAALgAECggJDwABLgAECggJGQACANIiAA==.',
Ki='Kiimachamara:BAAALgADCgIJAwAAAA==.Killik:BAAALgAECgQJBAAAAA==.Kippili:BAAALgADCgQJBAABLgAECgYJCgAEAAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECggJDQAEAAAAAA==.Kleenonean:BAACLgAFFH8HAAIhAAMJviFSDQA2AQAhAAMJviFSDQA2AQAuAAQKf0IAAyEACQlrJV4AAHoDACEACQlrJV4AAHoDAB0AAgnGBk10AFcAAAAA.',
Kp='Kpyassan:BAAALgAECgYJBQAAAA==.',
Kr='Kravenn:BAAALgAECgMJAwAAAA==.Kreuzritter:BAABLgAECn8oAAIWAAkJORAxCwDxAQAWAAkJORAxCwDxAQAAAA==.',
Ku='Kungcarefu:BAABLgAECn8VAAICAAYJPhJJKwDzAAACAAYJPhJJKwDzAAAAAA==.Kungfushnaz:BAAALgAECgEJAQAAAA==.Kurzaan:BAAALgAECgIJAgAAAA==.Kurzak:BAAALgAECgQJBwAAAA==.',
Ky='Kyle:BAAALgAECgEJAQAAAA==.',
La='Laciel:BAAALgAECgMJBAABLgAECgkJFAAHAJEbAA==.Lacio:BAABLgAECn81AAIhAAkJ0QjRFgCIAQAhAAkJ0QjRFgCIAQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAABLgAECn8ZAAILAAgJKhsxFQDmAQALAAgJKhsxFQDmAQAAAA==.',
Le='Lemonite:BAABLgAECn8WAAIOAAkJbhvkFACOAgAOAAkJbhvkFACOAgAAAA==.Lennykoggins:BAAALgAECgYJEAAAAA==.Leyru:BAABLgAECn8cAAILAAgJHSOEAgArAwALAAgJHSOEAgArAwAAAA==.',
Li='Liberos:BAAALgAECggJEAAAAA==.Lifenight:BAABLgAECn8YAAMiAAgJaBIHBQCMAQAiAAgJaBIHBQCMAQAIAAEJvgABPwEJAAAAAA==.Lithvia:BAAALgAECgYJDQAAAA==.',
Ln='Lninedkhack:BAABLgAECn8cAAMHAAgJUhA9GgD1AAAIAAcJ/BF3igBsAQAHAAgJcwY9GgD1AAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAABLgAECn8hAAMLAAkJYw9LEgAFAgALAAkJYw9LEgAFAgAKAAEJ7gEDHQEkAAAAAA==.Loretharan:BAAALgAECgEJAQAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJCwAAAA==.Luticris:BAAALgADCggJFwAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Magicpants:BAAALgAECgMJAwAAAA==.Magnetto:BAAALgADCgQJBAAAAA==.Maiden:BAAALgADCgUJCAABLgAECgYJHQAHAOQUAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Mateus:BAAALgAECgEJAQAAAA==.Maxdeath:BAABLgAECn8lAAIIAAgJ9iO7DQAtAwAIAAgJ9iO7DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgMJBAAAAA==.Mensrea:BAAALgAECgYJEwAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8eAAMIAAgJfCBBPABGAgAIAAcJpSFBPABGAgAHAAMJtRJxMwBJAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECggJHgAIAHwgAA==.Merrygored:BAAALgAECgIJAgABLgAECggJHgAIAHwgAA==.Mess:BAABLgAECn8YAAQXAAYJXhiUFwCbAQAXAAYJXhiUFwCbAQAjAAIJ3gfJlABsAAAYAAMJPQgTRwApAAABLgAECgYJHQAHAOQUAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8uAAMWAAgJFiWOAQD6AgAWAAgJFiWOAQD6AgAJAAEJlSXoGwBsAAAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Mistweaver:BAAALgAECgYJDgAAAA==.Mizirath:BAAALgAECgQJBAABLgAECggJIQAQAM0eAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAABLgAECn8aAAIkAAkJHxVPCADkAQAkAAkJHxVPCADkAQAAAA==.Mojoe:BAAALgAECgQJDAAAAA==.Mommyswaggin:BAAALgAECggJEQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgUJBQABLgAECgkJLgAdAOkkAA==.Moopsta:BAAALgADCggJDgABLgAECgkJLgAdAOkkAA==.Moopster:BAABLgAECn8uAAMdAAkJ6SRdAAC5AwAdAAkJ6SRdAAC5AwABAAIJnh4VLwCzAAAAAA==.Mordekaiserz:BAAALgAECgUJCgAAAA==.Morrgoth:BAAALgADCgEJAQAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAABLgAECn8fAAIlAAgJnRihCwARAgAlAAgJnRihCwARAgAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAAALgAECgQJBQAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Neriah:BAAALgADCgMJAwAAAA==.Newcarsmell:BAAALgAECgEJAwAAAA==.',
Ni='Nicktee:BAAALgAECgUJBwAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nightrvn:BAAALgAECgQJBAAAAA==.Nimrose:BAAALgAECgYJDAAAAA==.Niquid:BAABLgAECn8cAAIOAAgJGRSmMABdAQAOAAgJGRSmMABdAQAAAA==.',
No='Nolmac:BAAALgAECgYJDAAAAA==.Notahealer:BAAALgAECgYJBwAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAAALgAFFAEJAgAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAABLgAECn8iAAIMAAkJeR8fBACsAgAMAAkJeR8fBACsAgAAAA==.',
Ol='Olivertwist:BAAALgAECgQJCwAAAA==.',
On='Ontwarr:BAAALgADCgIJAgAAAA==.Ontwou:BAAALgAECgcJCwAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJCQAAAQ==.',
Ou='Ouchpotato:BAAALgAECgIJAgABLgAECggJJgAVAIsfAA==.',
Pa='Paarthurnax:BAAALgAECgUJBQAAAA==.Palathal:BAAALgAECgUJBQABLgAECggJFgADAPUTAA==.Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAABLgAECn8YAAIMAAkJQCKVBwACAwAMAAkJQCKVBwACAwAAAA==.Pancakezebra:BAABLgAECn8yAAIWAAkJ6BqiBAB3AgAWAAkJ6BqiBAB3AgAAAA==.Pantsftw:BAABLgAECn8eAAIdAAgJ1Qt7HABmAQAdAAgJ1Qt7HABmAQAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAAALgAECgYJEwAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Pebbles:BAAALgADCgkJCQAAAA==.Peltier:BAABLgAECn8sAAIDAAkJdCBMCgDTAgADAAkJdCBMCgDTAgAAAA==.Pendle:BAABLgAECn8YAAMbAAcJzwzDKQAbAQAFAAcJUwr3VAAtAQAbAAYJHQvDKQAbAQAAAA==.',
Ph='Phoenix:BAABLgAECn8cAAIKAAcJ4CCPKgDUAQAKAAcJ4CCPKgDUAQAAAA==.',
Pl='Plox:BAAALgAECgYJEwAAAA==.Plurnizz:BAABLgAECn8VAAMFAAkJkQN8qAAIAQAFAAkJkQN8qAAIAQAbAAQJEwHDXwBPAAAAAA==.',
Po='Pocketchange:BAAALgAFFAMJBAAAAA==.',
Pu='Puffadin:BAAALgADCgEJAQAAAA==.Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8ZAAICAAgJ0iKVEACVAgACAAgJ0iKVEACVAgAAAA==.Raiker:BAAALgAECgMJBAAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgcJDQAAAA==.Relovan:BAABLgAECn8kAAMYAAgJuhEoCgCkAQAYAAgJuhEoCgCkAQAjAAUJSwOQhgClAAAAAA==.Renothidan:BAABLgAECn8gAAIKAAgJxxxQIAAIAgAKAAgJxxxQIAAIAgAAAA==.Reuben:BAAALgADCggJDQAAAA==.Revin:BAAALgADCgYJBgAAAA==.Revrynth:BAAALgAECgMJAwABLgAECggJIwAXAPQiAA==.Rexorcist:BAAALgADCgYJCwAAAA==.',
Ri='Rickyboby:BAAALgAECgYJBgAAAA==.Righteøus:BAAALgAECgQJCgAAAA==.Rillan:BAAALgAECgUJEgAAAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn8mAAIjAAkJ6CTRAABDAwAjAAkJ6CTRAABDAwAAAA==.Rizzdolphler:BAACLgAFFH8HAAIKAAMJsQeINQDgAAAKAAMJsQeINQDgAAAuAAQKfx8AAwoACAltHOoUAFICAAoACAltHOoUAFICAAsABgktERAmAFkBAAAA.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECgYJHQAHAOQUAA==.',
Ru='Ruins:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAABLgAECn8sAAIFAAkJpB0HCQC3AgAFAAkJpB0HCQC3AgAAAA==.',
Sa='Sanako:BAABLgAECn8fAAIaAAkJCQsvGQBwAQAaAAkJCQsvGQBwAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECgEJAQABLgAECggJKAASAHkVAA==.Santoniche:BAAALgAECgUJBQAAAA==.Sap:BAABLgAECn8UAAMVAAYJGw1lGgAtAQAVAAYJDA1lGgAtAQAmAAQJQQskDQDoAAABLgAECgYJHQAHAOQUAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8oAAISAAgJeRXDLACEAQASAAgJeRXDLACEAQAAAA==.Scyther:BAABLgAECn8WAAMSAAgJOA3HcQBPAQASAAgJPgzHcQBPAQAnAAUJTQ6YSgDGAAAAAA==.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAAALgAECgYJEQAAAA==.Serenade:BAACLgAFFH8KAAIDAAQJ5BEeMgBEAQADAAQJ5BEeMgBEAQAuAAQKfyQAAgMACAmpHxIzAKYCAAMACAmpHxIzAKYCAAAA.Setheron:BAAALgAECgYJEQAAAA==.Sethron:BAAALgAECgIJAgAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamminit:BAAALgAECgIJAgAAAA==.Shamtul:BAAALgAECgEJAgAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAABLgAECn8bAAIlAAgJJA86GwBkAQAlAAgJJA86GwBkAQAAAA==.Shyva:BAABLgAECn8jAAMXAAgJ9CKnAwCKAgAXAAgJ9CKnAwCKAgAjAAMJchOwTACDAAAAAA==.',
Si='Siinestro:BAAALgAECgQJBAAAAA==.Sinlee:BAAALgAECgcJDQABLgAECggJKQAFAP8gAA==.',
Sl='Slayla:BAAALgAECgMJAwAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Sneak:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Sneakcookies:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
So='Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgMJAwAAAA==.',
Sp='Spacehog:BAAALgAECgYJDAAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgADCgUJBQABLgAECggJHQAnAHoWAA==.Splouge:BAAALgAECgYJBgAAAA==.',
St='Standarshh:BAABLgAECn8qAAIeAAkJOB38BgDBAgAeAAkJOB38BgDBAgAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAABLgAECn8mAAMVAAgJix8oDQDHAgAVAAgJix8oDQDHAgAoAAUJqQa2DACUAAAAAA==.Sugarbabi:BAABLgAECn8dAAMOAAgJ+B4tIQA7AgAOAAcJ3x4tIQA7AgAaAAUJBxclGwBdAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sugarthorn:BAAALgADCgkJCQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn82AAMdAAkJsx23BgCMAgAdAAkJsx23BgCMAgABAAQJrgjsLQC8AAAAAA==.Sylveste:BAABLgAECn8eAAILAAcJFBpiGgC3AQALAAcJFBpiGgC3AQAAAA==.Sylvfelster:BAAALgAECgYJBwAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAAALgAECgcJEAAAAA==.Tankhiskhan:BAABLgAECn8UAAIHAAcJFQ7cHADcAAAHAAcJFQ7cHADcAAAAAA==.Tarlis:BAABLgAECn8WAAIcAAgJoRq8BAAqAgAcAAgJoRq8BAAqAgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBgAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAABLgAECn8YAAIKAAcJUxXSPwCGAQAKAAcJUxXSPwCGAQAAAA==.',
Ti='Tikamancer:BAAALgADCgEJAQAAAA==.Tilvalhalla:BAABLgAECn8aAAIkAAcJGgkcKgAhAQAkAAcJGgkcKgAhAQAAAA==.',
To='Todorokii:BAAALgAECgUJCgAAAA==.Tom:BAAALgAECgEJAgAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgMJBgAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Trauck:BAAALgADCgEJAQAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8dAAMVAAcJkSOSAQDpAQAVAAYJ8yKSAQDpAQAmAAIJoR7mBgB0AAAuAAQKfyAAAhUACQmtJQEBAMMDABUACQmtJQEBAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn8tAAIXAAkJRhxnAwCUAgAXAAkJRhxnAwCUAgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgQJBgAAAA==.',
Ty='Tym:BAAALgAECgkJDgAAAA==.',
Ug='Ugargro:BAAALgAECgEJAQAAAA==.',
Un='Unapologetic:BAAALgAECgQJBAAAAA==.Unbreakabull:BAAALgADCgYJBgAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAABLgAECn8dAAMHAAYJ5BQZIwApAQAHAAYJBRMZIwApAQAIAAUJBhAddwDzAAAAAA==.',
Va='Valcuna:BAAALgAECgEJAgAAAA==.Valka:BAAALgAECggJEAAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCwAEAAAAAA==.Vanaan:BAAALgADCgYJBgAAAA==.Varidrus:BAAALgAECgIJAgAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8jAAIDAAkJ6hXTKgD2AQADAAkJ6hXTKgD2AQAAAA==.Veyle:BAABLgAECn82AAMVAAkJ0SSOAABaAwAVAAkJ0SSOAABaAwAmAAEJKh69GwBJAAAAAA==.',
Vi='Vivian:BAABLgAECn8dAAInAAgJehZ5CwDMAQAnAAgJehZ5CwDMAQAAAA==.',
Vo='Voidsurge:BAAALgAECgUJEgABLgAECgYJHQAHAOQUAA==.',
Vy='Vyndria:BAAALgADCgkJCQAAAA==.',
We='Weaspore:BAABLgAECn8gAAIIAAgJhx4fFgBKAgAIAAgJhx4fFgBKAgAAAA==.Weasy:BAAALgAECgQJBAAAAA==.',
Wo='Woogidaboogi:BAAALgAECgIJAwAAAA==.Woogieboogie:BAAALgADCgEJAQABLgAECgIJAwAEAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9OAAMnAAgJ+RxUCwCrAgAnAAgJhxxUCwCrAgASAAYJZA0LZQDUAAAAAA==.',
Yh='Yharnem:BAAALgAECgcJDAAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAAALgAECggJEQAAAA==.Zakaraki:BAABLgAECn81AAQfAAkJhCVDAABDAwAfAAkJhCVDAABDAwAlAAcJNyFpCABMAgAkAAcJTQd1JgBBAQAAAA==.Zaki:BAABLgAECn8YAAISAAgJyRzrEQAvAgASAAgJyRzrEQAvAgAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zealot:BAAALgADCgYJDQAAAA==.Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAFFAEJAQAAAA==.Zerathis:BAABLgAECn8pAAIFAAgJ/yArEwDjAgAFAAgJ/yArEwDjAgAAAA==.Zerathül:BAAALgAECgIJBQAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFgAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgIJAgAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
['Zõ']='Zõshow:BAAALgAECgYJEQAAAA==.',
['Ða']='Ðaredevil:BAABLgAECn8VAAIMAAYJHhuMFACKAQAMAAYJHhuMFACKAQABLgAECggJHQAnAHoWAA==.',
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

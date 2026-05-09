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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Priest-Discipline','Mage-Arcane','DemonHunter-Devourer','Evoker-Preservation','DemonHunter-Vengeance','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adamonious:BAAALgAECgYJBgABLgAECggJEwABAAAAAA==.Adaware:BAAALgAECgMJAwAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAQAAAA==.',
Al='Alba:BAABLgAECn8dAAICAAgJHhqoGgApAgACAAgJHhqoGgApAgABLgAFFAIJBQADAIAeAA==.Aletta:BAAALgADCgQJCwABLgAECgMJBQABAAAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn8hAAMDAAcJFBG5NQB2AQADAAcJFBG5NQB2AQAEAAIJTAlYHwBZAAAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwAAAA==.',
Ar='Arianes:BAAALgAECgcJDgAAAA==.Arturias:BAAALgAECgcJEgAAAA==.',
At='Athenaowl:BAAALgAECgYJDQAAAA==.',
Au='Autofocus:BAABLgAECn8ZAAIDAAgJNhoyFgAeAgADAAgJNhoyFgAeAgAAAA==.',
Aw='Aweyna:BAAALgAECggJDAAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8IAAIFAAMJ4RH4AwALAQAFAAMJ4RH4AwALAQAuAAQKfykAAgUACAk0HwwCAFcCAAUACAk0HwwCAFcCAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgQJBQAAAA==.Baoyue:BAAALgAECgYJCQABLgAFFAMJBwAGAE0JAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Benmonk:BAAALgAECgIJAgAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAACLgAFFH8FAAIHAAMJRQSeHQDEAAAHAAMJRQSeHQDEAAAuAAQKfyIAAgcACAnqDqYYAKIBAAcACAnqDqYYAKIBAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn8nAAIIAAgJBBVdDACuAQAIAAgJBBVdDACuAQAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAAALgAECgYJEwAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8gAAQJAAgJnBCZBwAtAQAJAAcJwxCZBwAtAQAKAAYJQAq9YgAKAQALAAIJzxHwUQB4AAAAAA==.',
Bu='Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8bAAIMAAgJQQNE3AA6AQAMAAgJQQNE3AA6AQAAAA==.Calahan:BAABLgAECn8dAAICAAgJqRpqNABQAgACAAgJqRpqNABQAgAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chikostix:BAAALgAECgYJEwAAAA==.Christae:BAABLgAECn8bAAINAAgJ1hsGCgBIAgANAAgJ1hsGCgBIAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJBgAAAA==.Clydè:BAABLgAECn9AAAMOAAgJKhiAFABJAgAOAAgJbheAFABJAgAPAAgJHhLYEwCfAQAAAA==.Cláncey:BAAALgAECgcJCwAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAECggJLwAKAO8jAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromised:BAABLgAECn8lAAIQAAgJ1RpBBwAoAgAQAAgJ1RpBBwAoAgAAAA==.Conquests:BAAALgAECgEJAQAAAA==.Corelack:BAAALgAFFAMJAwAAAA==.',
Cr='Crwth:BAAALgAECgEJAQAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8dAAIDAAcJdhekLACcAQADAAcJdhekLACcAQAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8RAAIMAAUJoxorKgBVAQAMAAUJoxorKgBVAQAuAAQKfxgAAgwACQktGDlMAFICAAwACQktGDlMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAAALgAECgYJEQAAAA==.',
De='Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEALgAFFAIJAgABLgAFFAYJFAAMACcRAA==.Despair:BAAALgADCggJDgABLgAFFAIJBQADAIAeAA==.',
Di='Dice:BAABLgAECn8eAAIRAAgJ/x+jAgBSAgARAAgJ/x+jAgBSAgAAAA==.Disturbd:BAACLgAFFH8KAAMSAAUJRQg3OgAjAQASAAQJRQg3OgAjAQAIAAEJAACcLgAAAAAuAAQKfxUAAxIACQkVCzcuAMEBABIACQkVCzcuAMEBAAgABAmJAMM9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJCgASAEUIAA==.Dixierecht:BAABLgAECn8gAAITAAgJbhuaCACJAgATAAgJbhuaCACJAgAAAA==.',
Do='Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgQJBQAAAA==.Drvargas:BAAALgAECgIJAgAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAAALgAECggJEgAAAA==.Elmo:BAABLgAECn8YAAIMAAcJhhJ+WgBfAQAMAAcJhhJ+WgBfAQAAAA==.',
Em='Emryssa:BAAALgAECgMJCQAAAA==.',
Er='Erosis:BAACLgAFFH8IAAIMAAMJwhz6PwANAQAMAAMJwhz6PwANAQAuAAQKfyAAAgwACAmtIv0uALYCAAwACAmtIv0uALYCAAAA.',
Ez='Ezaratren:BAAALgAECgUJCQABLgAFFAMJAwABAAAAAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8FAAIKAAMJOBu5HQANAQAKAAMJOBu5HQANAQAuAAQKfyYAAwoACAlyIOMrAF8CAAoACAlyIOMrAF8CAAsABQkbFk0bAHIBAAAA.Felcatalyist:BAABLgAECn8dAAMIAAgJWhgSEwBDAQASAAgJuRUSYwDKAQAIAAgJWA0SEwBDAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAAALgAECgYJDwAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBAABLgAECgcJEAABAAAAAA==.Fistofwayne:BAAALgAECgYJDgABLgAFFAQJCwAUALQeAA==.',
Ga='Gakopozy:BAAALgAECgYJCAAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAISAAMJuhEXJwD7AAASAAMJuhEXJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgADCggJDwAAAA==.',
Gr='Grïmyst:BAAALgAECgEJAQABLgAFFAMJAwABAAAAAA==.',
Gu='Guldán:BAAALgAECgYJDAAAAA==.',
Gw='Gwydre:BAACLgAFFH8NAAIIAAQJ0RNXDAARAQAIAAQJ0RNXDAARAQAuAAQKfxUAAggACAnpHvIHAAsCAAgACAnpHvIHAAsCAAAA.',
Ha='Havran:BAAALgAECgMJAwABLgAECgkJNwAVABIWAA==.Havrin:BAABLgAECn83AAMVAAkJEhaVDQCsAQAVAAkJEhaVDQCsAQAWAAEJQhLeMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8FAAIDAAIJgB6OMQC/AAADAAIJgB6OMQC/AAAuAAQKfyYAAgMACQnIHV0UAJMCAAMACQnIHV0UAJMCAAAA.Hexatar:BAAALgAECgQJBAAAAA==.',
Ho='Holmie:BAAALgADCgkJCgAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8SAAISAAUJkyZtCADGAQASAAUJkyZtCADGAQAuAAQKfy4AAxIACQl6I/4TAAMDABIACQlWIf4TAAMDAAgABwmjH1cHABoCAAAA.',
Hu='Huamulan:BAABLgAECn8rAAICAAgJ0QTQagAYAQACAAgJ0QTQagAYAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAECggJJQAMAHEaAA==.Ibchilling:BAABLgAECn8lAAIMAAgJcRpQIAApAgAMAAgJcRpQIAApAgAAAA==.Ibcorrupted:BAAALgAECgUJCQABLgAECggJJQAMAHEaAA==.',
Ic='Icarrus:BAACLgAFFH8HAAIXAAMJdgzNGAC5AAAXAAMJdgzNGAC5AAAuAAQKfyQAAhcACAlhG6AQAOYBABcACAlhG6AQAOYBAAEuAAQKBgkUABIA0hkA.Icarus:BAAALgADCgEJAQABLgAECgYJFAASANIZAA==.Iccarus:BAAALgAECgUJBQABLgAECgYJFAASANIZAA==.Icebone:BAAALgAECgMJBAABLgAECgYJDwABAAAAAA==.',
Ig='Ignis:BAABLgAECn8UAAISAAYJ0hldRwBlAQASAAYJ0hldRwBlAQAAAA==.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJCwAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwABAAAAAA==.',
Ja='Jackbfistn:BAAALgAECgYJDwAAAA==.Jaskim:BAAALgAECgcJCAAAAA==.',
Je='Jeses:BAAALgAECgEJAQABLgAECggJJAACACYUAA==.',
Jo='Jolty:BAAALgADCggJCAABLgAECgEJAQABAAAAAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAAALgAECgYJCwAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgABAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kaltaan:BAABLgAECn8fAAMYAAgJAyHxBAC7AgAYAAgJAyHxBAC7AgANAAQJUh8ePABKAQAAAA==.Karasan:BAABLgAECn8VAAIDAAcJKBkHQwCjAQADAAcJKBkHQwCjAQAAAA==.Karenas:BAABLgAECn8XAAMMAAgJmRl8VAA7AgAMAAgJmRl8VAA7AgAZAAIJ4QqYFgBmAAAAAA==.Karr:BAAALgAECgQJBgAAAA==.Kataraara:BAACLgAFFH8HAAIPAAQJRSC2BgCOAQAPAAQJRSC2BgCOAQAuAAQKfxcAAg8ACAntJOAEADwDAA8ACAntJOAEADwDAAAA.Katbeans:BAABLgAECn8gAAQXAAcJrB1CCgBJAgAXAAcJrB1CCgBJAgAPAAQJpguMYgC4AAAOAAEJJhbDUwBDAAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.',
Ke='Kelicemoon:BAABLgAECn8VAAMKAAYJrwhxhgC4AAAKAAYJawZxhgC4AAALAAUJSQejSwCKAAABLgAECggJIgASAJgPAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn8xAAIaAAkJcwwpYACAAQAaAAkJcwwpYACAAQAAAA==.',
Ki='Kiara:BAACLgAFFH8KAAIbAAQJVxpmCwBeAQAbAAQJVxpmCwBeAQAuAAQKfyEAAhsACAnLH1IIALUCABsACAnLH1IIALUCAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgMJAwAAAA==.',
Kr='Krogers:BAAALgAECgMJBQAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgADCgEJAQABLgAECgcJCwABAAAAAA==.',
La='Lahrnaon:BAAALgAECgcJDwAAAA==.Laxeron:BAABLgAECn8XAAIHAAgJoCL1AwDGAgAHAAgJoCL1AwDGAgAAAA==.',
Le='Leotherassy:BAAALgAECgEJAQAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgUJBQAAAA==.',
Lo='Lotiel:BAAALgAECgMJBgABLgAFFAEJAQABAAAAAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMaAAYJPx0mUgCuAQAaAAUJoiEmUgCuAQAcAAEJswucLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEAAAAA==.',
Ma='Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8XAAICAAgJGgsXXwAwAQACAAgJGgsXXwAwAQAAAA==.Mcfeast:BAABLgAECn8WAAIdAAcJNA+fGgBnAQAdAAcJNA+fGgBnAQAAAA==.',
Me='Medra:BAABLgAECn8bAAIHAAgJrxPbFgCxAQAHAAgJrxPbFgCxAQAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn8ZAAIMAAcJeAPSnQDXAAAMAAcJeAPSnQDXAAAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECgYJDwABAAAAAA==.',
Mo='Morar:BAAALgAECgIJBAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Ni='Nightcat:BAAALgAECgEJAQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgAAAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nixie:BAABLgAECn8iAAIeAAgJYQbxQgAHAQAeAAgJYQbxQgAHAQAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIQAAUJlQZ2CAARAQAQAAUJlQZ2CAARAQAuAAQKfxsAAhAACQlMFi8eAM4BABAACQlMFi8eAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8IAAMKAAMJ+hzkUQCrAAAKAAIJ8x3kUQCrAAALAAEJChuQDwBZAAAuAAQKfyEAAwoACAmQIn4WAC4CAAoABgkLIn4WAC4CAAsABQm9HzgaAHsBAAAA.',
Ol='Oliiver:BAABLgAECn8cAAIDAAkJWx5OCQChAgADAAkJWx5OCQChAgAAAA==.',
Om='Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAABAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8fAAIaAAcJACGaFAAXAgAaAAcJACGaFAAXAgAAAA==.',
Pa='Panaceus:BAABLgAECn8uAAIbAAgJ4SHCAQAHAwAbAAgJ4SHCAQAHAwAAAA==.Paragon:BAAALgADCgkJDQABLgAECgUJBQABAAAAAA==.Patron:BAAALgADCgEJAQAAAA==.',
Pe='Perennial:BAAALgAECgYJCAAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJCgABLgAECgYJFAATAKYPAA==.Phrequency:BAEBLgAECn8UAAMTAAYJpg9UKABJAQATAAYJpg9UKABJAQACAAQJtxO8mgC6AAAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAUJEgASAJMmAA==.',
Pl='Playingwow:BAAALgAECgYJBgAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8IAAIIAAMJbBSZEQDaAAAIAAMJbBSZEQDaAAAuAAQKfykAAggACAlHG+YNAC8CAAgACAlHG+YNAC8CAAAA.',
Pr='Profang:BAAALgADCgUJAwAAAA==.',
Py='Pyrelic:BAABLgAFFH8KAAIOAAUJIRPqCQAwAQAOAAUJIRPqCQAwAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJDQAIANETAA==.',
['Pö']='Pöncho:BAAALgADCgMJAwAAAA==.',
Qa='Qayllera:BAAALgADCgkJEQAAAA==.',
Qe='Qelcie:BAAALgAECgMJAwAAAA==.',
Qu='Quizet:BAAALgADCgYJCAAAAA==.',
Ra='Radkeem:BAAALgAECgYJBgABLgAECgYJDwABAAAAAA==.Raf:BAAALgAECgYJBwAAAA==.Rakeem:BAAALgAECgYJDwAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.',
Re='Redtoxin:BAAALgADCggJAQAAAA==.Reilley:BAACLgAFFH8KAAISAAQJoReTKABPAQASAAQJoReTKABPAQAuAAQKfyEAAhIACAlvIdQXAOwCABIACAlvIdQXAOwCAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAQJCgASAKEXAA==.Reko:BAAALgAECgMJAwAAAA==.Remorsa:BAAALgAECgUJDQAAAA==.Renni:BAABLgAECn8eAAIKAAYJRxe6agCNAQAKAAYJRxe6agCNAQAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8eAAITAAkJ1BXDJwDtAQATAAkJ1BXDJwDtAQAAAA==.',
Ro='Rosealia:BAAALgAECgYJDgAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8HAAIGAAMJTQmsFgDaAAAGAAMJTQmsFgDaAAAuAAQKfzkAAgYACQmDGsoCAL4CAAYACQmDGsoCAL4CAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgcJBwABLgAECgYJCgABAAAAAA==.Saintzan:BAAALgAECgUJBgAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECggJGwACABQSAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8eAAIbAAgJZAueDgBYAQAbAAgJZAueDgBYAQAAAA==.Schmoop:BAABLgAECn8dAAQdAAcJKSJ9DwCMAgAdAAcJKSJ9DwCMAgANAAMJXBtaUwDpAAAYAAEJ8RBgVgA0AAABLgAFFAUJEgASAJMmAA==.',
Se='Seldaria:BAAALgAECgYJDwAAAA==.Senza:BAAALgAECgYJEQAAAA==.Senzyri:BAABLgAECn8VAAIDAAYJ+hQgUgByAQADAAYJ+hQgUgByAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECgYJDwABAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgABAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shambhala:BAAALgADCgcJBwAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8dAAIIAAcJhA7iGQD5AAAIAAcJhA7iGQD5AAAAAA==.',
Sn='Snowthistle:BAAALgAECgYJDgAAAA==.',
So='Sorle:BAAALgADCgYJBgABLgAECggJGwAHAK8TAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAAALgAECgIJBAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECggJHwAYAAMhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgEJAQAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Stonymahoney:BAABLgAECn8sAAICAAgJzBvrHgAPAgACAAgJzBvrHgAPAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAABLgAECn8jAAIHAAgJlSKfBACzAgAHAAgJlSKfBACzAgAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.',
Sv='Sveela:BAACLgAFFH8HAAIVAAMJzhdoBQDdAAAVAAMJzhdoBQDdAAAuAAQKfx0AAhUACAl2H8EDAMoCABUACAl2H8EDAMoCAAAA.Sveelaa:BAABLgAECn8ZAAIDAAcJeRgNJgC8AQADAAcJeRgNJgC8AQABLgAFFAMJBwAVAM4XAA==.Sveella:BAAALgADCgEJAQABLgAFFAMJBwAVAM4XAA==.',
Sw='Swampjimmy:BAAALgAECgYJCAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn8tAAINAAkJWhzjAwDiAgANAAkJWhzjAwDiAgAAAA==.Talras:BAAALgADCgkJDAAAAA==.',
Te='Temlock:BAABLgAECn8uAAIKAAcJthsmMQBIAgAKAAcJthsmMQBIAgABLgAECggJJAAIAP4bAA==.Tempest:BAAALgAECgUJBQAAAA==.Temtank:BAABLgAECn8kAAIIAAgJ/hsJBwAjAgAIAAgJ/hsJBwAjAgAAAA==.',
Tr='Trak:BAABLgAECn8UAAIfAAgJHwzgMwAuAQAfAAgJHwzgMwAuAQAAAA==.Trukarak:BAABLgAECn8bAAICAAgJFBJAPQCOAQACAAgJFBJAPQCOAQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Valenti:BAABLgAECn8VAAMgAAYJkA3SFwDZAAAgAAYJkA3SFwDZAAACAAEJ0AarFAEtAAAAAA==.Valor:BAABLgAECn8fAAICAAcJQyFRIAAIAgACAAcJQyFRIAAIAgAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAAALgAECgcJEwAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAFFAIJAgABAAAAAA==.',
Xi='Xiao:BAABLgAECn8cAAIXAAkJJBZpDAAiAgAXAAkJJBZpDAAiAgAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQABAAAAAA==.',
Ya='Yahargul:BAAALgAECgYJEwAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Za='Zaterok:BAAALgAECgMJAwABLgAECggJGwACABQSAA==.',
Ze='Zeik:BAABLgAECn8gAAMgAAkJjhcKBgAJAgAgAAkJjhcKBgAJAgACAAMJngoLyABrAAAAAA==.Zephyrgosa:BAAALgADCgcJCgAAAA==.',
Zu='Zucco:BAAALgAECgkJCQAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECggJHwAYAAMhAA==.',
['Zí']='Zíx:BAABLgAECn8VAAIhAAYJRBGwIAA6AQAhAAYJRBGwIAA6AQAAAA==.',
['Àl']='Àlcàrà:BAAALgAECgYJEQAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgMJAwAAAA==.',
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

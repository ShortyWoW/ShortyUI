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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Devourer','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Mage-Frost','Priest-Shadow','Paladin-Retribution','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Shaman-Restoration','Druid-Guardian','Paladin-Protection','Druid-Restoration','Rogue-Assassination','Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Blood','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarhus:BAAALgADCgcJBwAAAA==.Aaronyates:BAAALgADCgcJBwABLgAECgYJDAABAAAAAA==.',
Ac='Actualegirl:BAAALgAECgMJAwABLgAECggJHAACANokAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn8UAAIDAAcJ7A0OLQAwAQADAAcJ7A0OLQAwAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQABAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8bAAIEAAgJlhwIEQAzAgAEAAgJlhwIEQAzAgAAAA==.',
Ar='Arator:BAAALgADCgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQAAAA==.Ardzak:BAAALgAECgQJBgABLgAECgYJDQABAAAAAA==.Arragorn:BAABLgAECn8cAAIFAAgJGxzwCQA3AgAFAAgJGxzwCQA3AgAAAA==.',
As='Asendra:BAABLgAECn8UAAIGAAYJ4hdpGgApAQAGAAYJ4hdpGgApAQAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAAALgAECgYJDQAAAA==.',
At='Athenea:BAAALgAECgQJBwAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAAALgAECgYJEwAAAA==.',
Ba='Baal:BAAALgADCgkJCQAAAA==.Bacon:BAABLgAECn8hAAIHAAgJJCR+AQDNAgAHAAgJJCR+AQDNAgAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAECgIJAgAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beyla:BAAALgAECgYJEgAAAA==.',
Bi='Bishamon:BAABLgAECn8lAAQIAAkJbSDzBQBeAwAIAAkJbSDzBQBeAwAJAAEJAAC2aQA+AAAKAAEJAADkMQA6AAAAAA==.Bizotch:BAAALgAECgEJAQAAAA==.',
Bl='Bleau:BAABLgAECn8YAAILAAYJTQ4CDAAeAQALAAYJTQ4CDAAeAQAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodhornbob:BAAALgADCgIJAQAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAAALgAECgcJEQAAAA==.Bluebarrie:BAAALgADCgkJEQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8hAAIMAAgJcRhpHAABAgAMAAgJcRhpHAABAgAAAA==.Branchling:BAAALgAECgYJCwABLgAFFAMJCwAMADwYAA==.Brewswane:BAAALgAFFAEJAQAAAA==.Bridh:BAABLgAECn8ZAAIDAAgJkiBQEQD0AgADAAgJkiBQEQD0AgABLgAFFAUJEAAIAHkcAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJDQAAAA==.',
Bu='Bulkamania:BAAALgADCgMJAwAAAA==.Butterkip:BAACLgAFFH8KAAINAAUJ7gnnCAAzAQANAAUJ7gnnCAAzAQAuAAQKfyIAAg0ACQkNHiYKAOACAA0ACQkNHiYKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cantkillme:BAAALgAECgIJAwAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAAALgAECgYJDAAAAA==.',
Ch='Chicharrones:BAAALgADCgkJCQABLgAECggJIQAHACQkAA==.Chickenshift:BAAALgAECgQJBwAAAA==.Chipahoy:BAABLgAECn8XAAIOAAcJ/R6MEwAeAgAOAAcJ/R6MEwAeAgABLgAECggJKQAMAOkcAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8VAAIPAAYJRRDpGAAgAQAPAAYJRRDpGAAgAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAUJEgAMABwkAA==.Clamius:BAACLgAFFH8SAAIMAAUJHCSqCQCnAQAMAAUJHCSqCQCnAQAuAAQKfyIAAgwACAkCJVYRAEADAAwACAkCJVYRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Coldass:BAAALgAECgUJBQAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgADCgQJBAAAAA==.Coombrain:BAAALgAECgQJBAAAAA==.Cotopla:BAAALgAECgQJBgAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAICAAgJ4hb4FwAcAgACAAgJ4hb4FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAAAAA==.',
Da='Dachyy:BAAALgAECgUJCQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deathlentlez:BAABLgAECn8XAAIQAAgJUR1XBAAsAgAQAAgJUR1XBAAsAgAAAA==.Decaylentlez:BAAALgADCgIJAgABLgAECggJFwAQAFEdAA==.Deepwinter:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.Delphyne:BAAALgAECgUJCQAAAA==.Demonhunter:BAAALgAECgYJDwAAAA==.Demonià:BAAALgADCgMJAwAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgADCgYJBgAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8iAAMFAAgJOh9+CgAuAgAFAAgJOh9+CgAuAgAOAAIJ2BCImwBvAAAAAA==.Dogdimmadome:BAAALgAECgYJCwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgADCgkJEQABLgAECgcJEQABAAAAAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAAALgAECgUJCgAAAA==.',
['Dà']='Dàrkscythe:BAAALgAECgMJAwAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8UAAIRAAgJlhwRAgA1AgARAAgJlhwRAgA1AgAAAA==.Ehress:BAAALgAECgYJDAABLgAECgYJDAABAAAAAA==.',
Ei='Eirinny:BAABLgAECn8fAAISAAgJJgqxBwB/AQASAAgJJgqxBwB/AQAAAA==.',
El='Elindez:BAAALgAECgYJEQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAAALgADCgkJEAAAAA==.',
Em='Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgEJAgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgEJAQAAAA==.',
Fa='Facingworlds:BAAALgAECgYJBgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAMJCAAPAKcfAA==.Fazed:BAAALgAECgEJAgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Fl='Flavio:BAAALgAECgIJAgAAAA==.',
Fo='Fortuna:BAAALgAECgYJEgAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn8iAAITAAkJrQ92GwCIAQATAAkJrQ92GwCIAQAAAA==.',
Ga='Galil:BAAALgADCgQJBQAAAA==.Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8bAAIUAAgJ7xjgAwD3AQAUAAgJ7xjgAwD3AQAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Gethealed:BAAALgAECgcJCgAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAAALgAECggJEAAAAA==.Ghoztface:BAABLgAECn8kAAMVAAcJcRzHDgDYAQAVAAYJXCDHDgDYAQAOAAcJghHdNQBsAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAFFAMJBgAWAEEIAA==.',
Gi='Giblock:BAABLgAECn8UAAIKAAYJhxXxAwBsAQAKAAYJhxXxAwBsAQAAAA==.',
Gl='Glamour:BAAALgAECgQJBgAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAUJEwAPALAcAA==.',
Go='Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8HAAIDAAMJjhuhHAD6AAADAAMJjhuhHAD6AAAuAAQKfygAAwMACQnDJY8IAEUDAAMACQnDJY8IAEUDAAcAAQlSEjZsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAECggJDQAAAA==.',
Gr='Gralmerte:BAABLgAECn8dAAMLAAgJ+RwqAgBXAgALAAgJ+RwqAgBXAgAWAAEJ9xSBxgA8AAAAAA==.Graygoyle:BAABLgAECn8eAAIXAAgJ/QQRBwA4AQAXAAgJ/QQRBwA4AQAAAA==.Groggaris:BAAALgADCgIJAgAAAA==.Groosalugg:BAABLgAECn8aAAIYAAgJTR12DAA8AgAYAAgJTR12DAA8AgAAAA==.',
Gu='Guillotine:BAAALgADCgEJAQAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgQJDAAAAA==.',
Gw='Gwyndolïn:BAAALgAECgYJDwAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8VAAITAAgJrwgAKgAiAQATAAgJrwgAKgAiAQAAAA==.Haiku:BAAALgADCgUJBQAAAA==.Haliax:BAAALgAECgEJAQABLgAECggJFwAOAIchAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAAALgAECggJDQAAAA==.Hawktuahh:BAAALgADCgUJCAAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAAALgAFFAIJAwAAAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECggJFwAQAFEdAA==.Holymun:BAAALgAECgYJCAAAAA==.Holyox:BAABLgAECn8nAAIOAAgJmww3MgB5AQAOAAgJmww3MgB5AQAAAA==.Hotcheeto:BAAALgAECgIJAgAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAAALgAECgQJDAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAECgUJBQAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAABLgAECn8qAAQLAAkJRSI3AgAxAwALAAkJRSI3AgAxAwAWAAYJFBnqKgA3AQAGAAEJAQRSSwAqAAAAAA==.Imgibby:BAAALgADCgYJBgABLgAECgYJFAAKAIcVAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAAALgAECggJDwAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIOAAMJjxQlHgD+AAAOAAMJjxQlHgD+AAAAAA==.',
Ir='Irakwa:BAAALgAECgQJCwAAAA==.',
It='Itches:BAACLgAFFH8TAAIPAAUJsBxgAQDGAQAPAAUJsBxgAQDGAQAuAAQKfyAAAg8ACAkHJOYDAE8DAA8ACAkHJOYDAE8DAAAA.',
Iz='Izánámi:BAAALgAECggJEQAAAA==.',
Ja='Jagon:BAAALgAECgcJEgAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jasint:BAAALgAECgUJBQABLgAECgcJEgABAAAAAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8dAAIZAAgJ0hnACAADAgAZAAgJ0hnACAADAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgYJBgAAAA==.',
Jk='Jkbalo:BAAALgAECgUJBQAAAA==.Jkrlos:BAAALgAECgIJAwAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAABLgAECn8fAAQDAAkJqyBtGADDAgADAAkJ8h5tGADDAgARAAYJnCNQBQBUAgAHAAQJMheKRADkAAAAAA==.Jphunt:BAAALgADCgUJBQABLgAECgkJHwADAKsgAA==.',
Ju='Juddory:BAAALgAECgYJDAAAAA==.Junksvil:BAAALgAECgUJBgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDQAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Kismët:BAAALgADCgYJDAAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAECggJEQABAAAAAA==.',
Ko='Korinth:BAECLgAFFH8HAAIVAAIJdQ4BBgB3AAAVAAIJdQ4BBgB3AAAuAAQKfyoAAhUACQlPGZQLABECABUACQlPGZQLABECAAAA.',
Kr='Kriaalis:BAAALgAECgUJCQAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECggJGgAYAE0dAA==.',
Ky='Kyra:BAAALgADCgYJBgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.',
Le='Legault:BAAALgAECgYJCwAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAABLgAECn8TAAMIAAcJ6xy0JgCUAQAIAAUJtR20JgCUAQAJAAYJlhbmIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8YAAIMAAYJUyGiLACxAQAMAAYJUyGiLACxAQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAAALgAECgYJEgAAAA==.',
Lo='Loneshark:BAAALgADCgYJBgAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgADCgEJAgAAAA==.Loraddesmos:BAABLgAECn8eAAIJAAgJ8gzBBQBnAQAJAAgJ8gzBBQBnAQAAAA==.Loriah:BAABLgAECn8eAAIOAAgJ+QtMOQBgAQAOAAgJ+QtMOQBgAQAAAA==.',
Lu='Lullaby:BAABLgAECn8fAAICAAgJoxdZCQATAgACAAgJoxdZCQATAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAECgkJKgALAEUiAA==.Marcdofu:BAAALgADCgUJBQAAAA==.Maryjanè:BAAALgADCgIJAgAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8JAAIGAAQJ9iC6AwCMAQAGAAQJ9iC6AwCMAQAuAAQKfzMAAwYACQlkJWkBAMEDAAYACQlkJWkBAMEDABQABQl6FLATADQBAAAA.Mayli:BAAALgAECgYJCQAAAA==.',
Mc='Mctanker:BAAALgAECgEJAQAAAA==.',
Me='Meascii:BAAALgAECgYJDwAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Merc:BAACLgAFFH8NAAIPAAQJWByZAwBiAQAPAAQJWByZAwBiAQAuAAQKfzMAAg8ACAnKIrcGABQDAA8ACAnKIrcGABQDAAAA.',
Mi='Millee:BAABLgAECn8UAAMCAAYJxRcuLQCRAQACAAYJxRcuLQCRAQANAAEJKgYeRAAwAAAAAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAMJCAALANIWAA==.Mirespike:BAACLgAFFH8IAAILAAMJ0hbkAgAWAQALAAMJ0hbkAgAWAQAuAAQKfy4AAgsACQmsIZkDAPgCAAsACQmsIZkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgADCgcJDAAAAA==.Morlock:BAABLgAECn8dAAMIAAgJNQgENwBQAQAIAAgJ9AcENwBQAQAKAAEJWwgeNQAxAAAAAA==.Morningstahr:BAAALgAECgQJBAAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAABLgAECn8UAAIOAAgJlAiASgArAQAOAAgJlAiASgArAQAAAA==.Nadia:BAAALgAECgIJAgAAAA==.Nanako:BAAALgAECgQJCgAAAA==.Naravanta:BAAALgADCgEJAQAAAA==.Naughtyvoked:BAAALgAECgUJCQAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQABAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.',
Ni='Nisdenar:BAAALgADCgUJBQAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8iAAIOAAgJ+RZNGwDmAQAOAAgJ+RZNGwDmAQAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8cAAIMAAgJgxh0HAABAgAMAAgJgxh0HAABAgAAAA==.',
Ny='Nyghtrider:BAAALgAECgUJCgAAAA==.Nymëra:BAABLgAECn8VAAITAAYJ6Q4sSgBZAQATAAYJ6Q4sSgBZAQAAAA==.Nyneeve:BAABLgAECn8WAAINAAYJIgkWJgDNAAANAAYJIgkWJgDNAAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECgcJGAAEADIPAA==.Oddiee:BAABLgAECn8YAAMEAAcJMg9CPQBHAQAEAAcJMg9CPQBHAQAaAAQJzgPvOQB0AAAAAA==.Odinshunter:BAAALgADCgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECgYJDAABAAAAAA==.',
Oh='Ohdatroll:BAAALgAECgUJDAABLgAECgkJKgALAEUiAA==.',
Ol='Olgrin:BAAALgADCgkJCQABLgAECgEJAQABAAAAAA==.',
On='Oneslice:BAAALgAECgUJBQAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgMJAwAAAA==.',
Or='Orikkosh:BAAALgAECgYJCQAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn8eAAIFAAcJsRNMHQBfAQAFAAcJsRNMHQBfAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECggJIQAHACQkAA==.Parabelum:BAAALgADCgQJBwAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMIAAYJhh/kKgCBAQAIAAUJhh/kKgCBAQAJAAEJAADlXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAABLgAECn8cAAICAAgJ2iQjAgBPAwACAAgJ2iQjAgBPAwAAAA==.Peregrine:BAAALgADCgIJAgAAAA==.',
Ph='Phaet:BAACLgAFFH8IAAMIAAMJNh8jJAAPAQAIAAMJNh8jJAAPAQAJAAEJiw5dFQBUAAAuAAQKfzAAAggACQnyJGIEANcCAAgACQnyJGIEANcCAAAA.Philipp:BAABLgAECn8VAAIGAAYJ0whdIgDsAAAGAAYJ0whdIgDsAAAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQABAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAIEAAkJ4hpIEQAxAgAEAAkJ4hpIEQAxAgAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgQJBQAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAECggJEgABAAAAAA==.',
Ra='Raezorian:BAAALgADCgcJBwAAAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAAALgAECgUJCgAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn8eAAIOAAgJWgaQQgBCAQAOAAgJWgaQQgBCAQAAAA==.Rampant:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.Randwulf:BAAALgAECgYJEAAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8LAAIMAAMJPBhMLwANAQAMAAMJPBhMLwANAQAuAAQKfyMAAwwACAnCIOcwAK8CAAwACAnCIOcwAK8CABsAAwnRHNANAOkAAAAA.Rathtard:BAAALgAECgQJCQABLgAFFAMJCwAMADwYAA==.Rauloso:BAAALgAECgMJBAAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQABAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECggJFwAQAFEdAA==.Resoluteone:BAABLgAECn8kAAIaAAgJxRCjCwBWAQAaAAgJxRCjCwBWAQAAAA==.Retnu:BAAALgADCggJDgAAAA==.Revytwohand:BAACLgAFFH8IAAIPAAMJpx/MCAAMAQAPAAMJpx/MCAAMAQAuAAQKfygAAg8ACQkZJb8DAFMDAA8ACQkZJb8DAFMDAAAA.',
Rh='Rhagul:BAAALgAECgEJAQAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQABAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8iAAIOAAgJGiG5BwCeAgAOAAgJGiG5BwCeAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8YAAITAAcJRQteMQD4AAATAAcJRQteMQD4AAAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAIAIEUAA==.Sarduccini:BAABLgAECn8iAAIIAAgJgRTWTADiAQAIAAgJgRTWTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sekio:BAAALgADCgEJAQAAAA==.',
Sh='Shamburgyr:BAAALgAECgMJAwABLgAECgQJCQABAAAAAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8JAAIcAAQJ8gwWEAAwAQAcAAQJ8gwWEAAwAQAuAAQKfxkAAxwACAk7H9YRAF0CABwACAk7H9YRAF0CAB0ABAm2EWkpANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgADCgUJDgAAAA==.',
Sk='Skaara:BAAALgADCgYJBgAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgADCgcJBwAAAA==.Skyeforce:BAAALgADCgIJAgAAAA==.',
Sl='Slipknoth:BAAALgAECgYJEwAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Snowbiter:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAAALgADCgUJCQAAAA==.Soi:BAAALgAECgYJCgABLgAECggJFwAOAIchAA==.Solarion:BAAALgADCggJCAAAAA==.',
Sp='Sped:BAABLgAECn8WAAQQAAcJOx5PBQAKAgAQAAcJOx5PBQAKAgAeAAQJQwdqLwB6AAAfAAEJ9wPvrgAtAAAAAA==.',
St='Stormeyes:BAAALgAECgEJAQABLgAECgYJDwABAAAAAA==.Stormslight:BAAALgAECgYJDwAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgQJCAAAAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgIJAgABAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAAALgAECgQJBAAAAA==.',
['Sô']='Sôlrïx:BAAALgADCgQJBAAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgADCgkJCAAAAA==.Talas:BAABLgAECn8iAAIVAAgJPxUdBwCsAQAVAAgJPxUdBwCsAQAAAA==.Tamarack:BAABLgAECn8XAAIYAAYJsxsYLQBdAQAYAAYJsxsYLQBdAQAAAA==.',
Te='Tehmber:BAAALgAECgMJCAAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAFAIghAA==.Theboart:BAAALgAECgQJBgAAAA==.Thredron:BAAALgAFFAIJAwAAAA==.',
To='Tooru:BAACLgAFFH8IAAIYAAMJwheqFwAHAQAYAAMJwReqFwAHAQAuAAQKfyoAAxgACQnBIY0GACUDABgACQnBIY0GACUDACAABgkWGRRLACUBAAAA.',
Tr='Traeflor:BAAALgAECgEJAQAAAA==.Trailertrash:BAABLgAECn8pAAIMAAgJ6RwsIADsAQAMAAgJ6RwsIADsAQAAAA==.Treebeef:BAACLgAFFH8GAAIWAAMJQQilHQCzAAAWAAMJQQilHQCzAAAuAAQKfysAAxYACQkBG+8YAHACABYACQkBG+8YAHACAAYAAQnWA+SMACIAAAAA.Triena:BAAALgAECgMJBQAAAA==.Trumpeter:BAAALgAECgQJCQAAAA==.',
Ty='Tyberos:BAABLgAECn8hAAQCAAgJqxzJDQB9AgACAAgJ2RvJDQB9AgAhAAUJDBd7LwAkAQANAAEJcQ3aXABAAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAAALgAECgYJEwAAAA==.Ulysius:BAABLgAECn8bAAIOAAgJ1hW5JQCtAQAOAAgJ1hW5JQCtAQAAAA==.',
Un='Unicornslayr:BAABLgAECn8cAAIFAAgJ9hYnEwC/AQAFAAgJ9hYnEwC/AQAAAA==.',
Ur='Urund:BAAALgAECgYJCgAAAA==.',
Uw='Uwantsmoke:BAAALgAECgIJAgAAAA==.',
Va='Valgroth:BAAALgAECgEJAQAAAA==.Valkisek:BAABLgAECn8VAAIMAAYJqxcCmwCfAQAMAAYJqxcCmwCfAQAAAA==.Vallarfax:BAABLgAECn8dAAIYAAgJ/BvfCwBDAgAYAAgJ/BvfCwBDAgAAAA==.Vandro:BAAALgAECgcJEgAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAABLgAECn8VAAIaAAgJxBZ+EAADAgAaAAgJxBZ+EAADAgAAAA==.Vashmonk:BAABLgAFFH8IAAIZAAMJKiPeCgA7AQAZAAMJKiPeCgA7AQAAAA==.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECgUJBwAAAA==.Velaric:BAABLgAECn8hAAIWAAgJpRl3DQA0AgAWAAgJpRl3DQA0AgAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgABAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAAALgAECgQJBgABLgAECgQJCQABAAAAAA==.Vewdoo:BAABLgAECn8dAAIiAAcJoCLVBQBTAgAiAAcJoCLVBQBTAgAAAA==.',
Vi='Viejoverde:BAAALgAECgEJAQAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgADCgcJDAAAAA==.',
Vo='Voldune:BAAALgADCgcJCgAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQABAAAAAA==.',
Wa='Waiwai:BAAALgADCgUJBQAAAA==.Wascii:BAAALgAECgYJDAAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJIQACAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAAALgAECgkJBwAAAA==.',
Wy='Wyrmblood:BAAALgADCgkJCQABLgAECggJIwANAIMiAA==.Wyrmheal:BAABLgAECn8jAAINAAgJgyIZAgC+AgANAAgJgyIZAgC+AgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Ya='Yakoff:BAAALgADCgIJAgAAAA==.Yamihime:BAABLgAECn8aAAMHAAkJKxQhDAB6AQAHAAgJPxUhDAB6AQADAAMJkAjKWwCVAAAAAA==.Yatiri:BAAALgAECgYJCAAAAA==.',
Yo='Yoowuzsup:BAAALgAFFAEJAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIMAAYJLwv5YgAVAQAMAAYJLwv5YgAVAQAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8VAAIjAAYJWRWsAAC7AQAjAAYJWRWsAAC7AQAuAAQKfygAAiMACQmSIhcBAGADACMACQmSIhcBAGADAAAA.Zedsdeadd:BAAALgADCgkJFQAAAA==.Zephyr:BAAALgAECgQJCQAAAA==.Zeçhs:BAABLgAECn8XAAIOAAgJhyEKCgCAAgAOAAgJhyEKCgCAAgAAAA==.',
Zi='Zinek:BAAALgADCggJIQAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAAALgAECgYJDgAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAQAAAA==.Zulfilith:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDAAAAA==.',
['Zð']='Zðltrain:BAAALgADCgcJCQAAAA==.',
['Ál']='Álfruen:BAAALgAECgUJBgAAAA==.',
['Ãi']='Ãinz:BAAALgAECgMJAwAAAA==.',
['Ða']='Ðachee:BAAALgAECgQJCAAAAA==.',
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

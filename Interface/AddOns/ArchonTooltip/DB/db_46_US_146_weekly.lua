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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Devourer','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Mage-Frost','Rogue-Assassination','Priest-Shadow','Paladin-Retribution','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','DeathKnight-Blood','Mage-Arcane','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarhus:BAAALgADCgcJDgAAAA==.Aaronyates:BAAALgADCgcJBwABLgAECgYJEgABAAAAAA==.',
Ac='Actualegirl:BAAALgAECgMJBAABLgAFFAUJCAACABsLAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAAALgAECgUJAwAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn8cAAIDAAgJaQ0HNQBhAQADAAgJaQ0HNQBhAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQABAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8fAAIEAAgJdx0CGAA8AgAEAAgJdx0CGAA8AgAAAA==.',
Ar='Arator:BAAALgADCgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQAAAA==.Ardzak:BAAALgAECgQJBgABLgAECgYJDQABAAAAAA==.Arragorn:BAABLgAECn8eAAIFAAkJshrRCwBWAgAFAAkJshrRCwBWAgAAAA==.',
As='Asendra:BAABLgAECn8aAAIGAAgJ2xU4FACgAQAGAAgJ2xU4FACgAQAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAABLgAECn8cAAIHAAgJIR3GAQBQAgAHAAgJIR3GAQBQAgAAAA==.',
At='Athenea:BAAALgAECgQJBwAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAABLgAECn8ZAAMIAAYJTwmFFAD4AAAIAAYJTwmFFAD4AAAJAAUJHQv4DgCZAAAAAA==.',
Ba='Baal:BAAALgAECgYJBwAAAA==.Bacon:BAABLgAECn8mAAIKAAgJaCSBAgDOAgAKAAgJaCSBAgDOAgAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAECgIJAgAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beyla:BAAALgAECgYJEwAAAA==.',
Bi='Bishamon:BAABLgAECn8tAAQLAAkJ+CDyBQBeAwALAAkJ+CDyBQBeAwAMAAEJAAC3aQA+AAANAAEJAADkMQA6AAAAAA==.Bizotch:BAAALgAECgEJAQAAAA==.',
Bl='Bleau:BAABLgAECn8aAAIOAAcJEQ2GDQA+AQAOAAcJEQ2GDQA+AQAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAAALgAECggJEgAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIPAAgJEBkxKQD+AQAPAAgJEBkxKQD+AQAAAA==.Branchling:BAAALgAECgYJEQABLgAFFAQJDwAPAMQTAA==.Brewswane:BAAALgAFFAEJAgABLgAFFAUJGQAQAOAWAA==.Bridh:BAABLgAECn8ZAAIDAAgJkyBKEQD0AgADAAgJkyBKEQD0AgABLgAFFAUJFQALAC8dAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJDQAAAA==.',
Bu='Bulkamania:BAAALgADCgMJAwAAAA==.Butterkip:BAACLgAFFH8KAAIRAAUJAQriDQAvAQARAAUJAQriDQAvAQAuAAQKfyMAAhEACQk6HicKAOACABEACQk6HicKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cantkillme:BAAALgAECgIJAwAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAAALgAECgYJDQAAAA==.',
Ch='Chicharrones:BAAALgADCgkJCQABLgAECggJJgAKAGgkAA==.Chickenshift:BAAALgAECgUJCwAAAA==.Chipahoy:BAABLgAECn8dAAISAAgJQBwaFwBCAgASAAgJQBwaFwBCAgABLgAECggJMQAPAFwdAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8dAAITAAgJmQ9EFQCCAQATAAgJmQ9EFQCCAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAUJFwAPADwkAA==.Clamius:BAACLgAFFH8XAAIPAAUJPCQnEQCjAQAPAAUJPCQnEQCjAQAuAAQKfyIAAg8ACAkHJVYRAEADAA8ACAkHJVYRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgUJAwAAAA==.Coldass:BAAALgAECgcJCwAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgADCgQJBAAAAA==.Coombrain:BAAALgAECgUJBgAAAA==.Cotopla:BAAALgAECgQJBwAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAICAAgJ4hb4FwAcAgACAAgJ4hb4FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAAAAA==.',
Da='Dachyy:BAAALgAECgUJDAAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deathlentlez:BAABLgAECn8fAAIUAAgJWx20BgAiAgAUAAgJWx20BgAiAgAAAA==.Decaylentlez:BAAALgADCgIJAgABLgAECggJHwAUAFsdAA==.Deepwinter:BAAALgADCgQJBAABLgAECgYJEgABAAAAAA==.Delphyne:BAAALgAECgUJCQAAAA==.Demonhunter:BAAALgAECgcJEAAAAA==.Demonià:BAAALgAECgMJAwAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgADCgYJBgAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8mAAMFAAgJPB8FEQASAgAFAAgJPB8FEQASAgASAAIJ2BBYxwBrAAAAAA==.Dogdimmadome:BAAALgAECgYJDgAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgADCgkJGgABLgAECggJEgABAAAAAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECgYJDwABAAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAAALgAECgYJEAAAAA==.',
['Dà']='Dàrkscythe:BAAALgAECgUJCAAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8cAAIVAAgJ7R40AgBkAgAVAAgJ7R40AgBkAgAAAA==.Ehress:BAAALgAECgYJEgAAAA==.',
Ei='Eirinny:BAABLgAECn8jAAIWAAgJuQqHCgBtAQAWAAgJuQqHCgBtAQAAAA==.',
El='Elindez:BAABLgAECn8ZAAIXAAgJOQlxEgCGAQAXAAgJOQlxEgCGAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAAALgAECgQJBwAAAA==.',
Em='Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgEJAgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgEJAgAAAA==.',
Fa='Facingworlds:BAAALgAECgYJBgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAQJDAATAHMeAA==.Fazed:BAAALgAECgEJAwAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Fl='Flavio:BAAALgAECgIJBAAAAA==.',
Fo='Fortuna:BAABLgAECn8ZAAIWAAYJTwTmEgDUAAAWAAYJTwTmEgDUAAAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn8tAAMYAAkJrg9OJQCQAQAYAAkJrg9OJQCQAQAZAAMJaQtWRQCTAAAAAA==.',
Ga='Galil:BAAALgADCgQJBQAAAA==.Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8eAAIaAAkJcBbEBAAiAgAaAAkJcBbEBAAiAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJDgAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAAALgAECggJEAAAAA==.Ghoztface:BAABLgAECn8oAAMbAAcJcxzGDgDYAQAbAAYJXCDGDgDYAQASAAcJJxLZSQBoAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAFFAQJCgAcAMMIAA==.',
Gi='Giblock:BAABLgAECn8XAAINAAgJBxTUAwC1AQANAAgJBxTUAwC1AQAAAA==.',
Gl='Glamour:BAAALgAECgQJBwAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAYJFwATAKYdAA==.',
Go='Golomojek:BAAALgAECgMJAwAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8LAAIDAAQJEBucGgA/AQADAAQJEBucGgA/AQAuAAQKfygAAwMACQm/JYsIAEUDAAMACQm/JYsIAEUDAAoAAQlSEjZsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAFFAIJAgAAAA==.',
Gr='Gralmerte:BAABLgAECn8kAAMOAAgJdB0xAwBdAgAOAAgJdB0xAwBdAgAcAAEJ9xSLxgA8AAAAAA==.Graygoyle:BAABLgAECn8eAAIQAAgJAAWkCQAzAQAQAAgJAAWkCQAzAQAAAA==.Groggaris:BAAALgADCgcJCQAAAA==.Groosalugg:BAABLgAECn8aAAIdAAgJVB2sFgAZAgAdAAgJVB2sFgAZAgAAAA==.',
Gu='Guillotine:BAAALgADCgQJBAAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgYJDwAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8VAAMeAAYJ7Q3WLQDlAAAeAAYJ7Q3WLQDlAAATAAQJnATFOgCTAAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8dAAIYAAgJ4wp9MQBJAQAYAAgJ4wp9MQBJAQAAAA==.Haiku:BAAALgADCgUJBQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAASAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAAALgAECggJDwAAAA==.Hawktuahh:BAAALgADCgUJCAAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAAALgAFFAIJAwABLgAFFAUJFgAXAOUhAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECggJHwAUAFsdAA==.Holymun:BAAALgAECgYJDwAAAA==.Holyox:BAABLgAECn8wAAISAAkJAAwBMwCxAQASAAkJAAwBMwCxAQAAAA==.Hotcheeto:BAAALgAECgIJAgAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAAALgAECgUJEQAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAECgYJBwAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8FAAMOAAIJrxMqBwCtAAAOAAIJrxMqBwCtAAAcAAIJzRlpKwCeAAAuAAQKfy0ABA4ACQndIzUCADEDAA4ACQndIzUCADEDABwABgkUGYQ5AC8BAAYAAQkMBHNfACgAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwANAAcUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8WAAMLAAkJnRG+LQCsAQALAAkJnRG+LQCsAQAMAAEJAAAHdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAISAAMJjxRILgD7AAASAAMJjxRILgD7AAAAAA==.',
Ir='Irakwa:BAAALgAECgQJDAAAAA==.',
It='Itches:BAACLgAFFH8XAAITAAYJph3gAADtAQATAAYJph3gAADtAQAuAAQKfyAAAhMACAkHJOUDAE8DABMACAkHJOUDAE8DAAAA.',
Iz='Izánámi:BAABLgAECn8YAAQfAAcJtBGXEACjAQAfAAcJtBGXEACjAQAdAAEJ8A18ywA6AAAgAAEJlwGKmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8ZAAMhAAgJWhVgDwDcAQAhAAgJWhVgDwDcAQAJAAIJHwyoFgA7AAAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jasint:BAAALgAECgUJBQABLgAECggJGQAhAFoVAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8fAAIiAAgJiBu7CgAXAgAiAAgJiBu7CgAXAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAECgUJBgAAAA==.Jkrlos:BAAALgAECgMJBQAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAABLgAECn8gAAQDAAkJ1SBpGADDAgADAAkJUh9pGADDAgAVAAYJnCNRBQBUAgAKAAQJMheNRADkAAAAAA==.Jphunt:BAAALgADCgUJBQABLgAECgkJIAADANUgAA==.',
Ju='Juddory:BAAALgAECgcJEwAAAA==.Junksvil:BAAALgAECgUJBgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDQAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Kismët:BAAALgADCgYJDAAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAEJAQABAAAAAA==.',
Ko='Korinth:BAECLgAFFH8LAAIbAAQJfQ/XAwDyAAAbAAQJfQ/XAwDyAAAuAAQKfy4AAhsACQkUG5MLABECABsACQkUG5MLABECAAAA.',
Kr='Kriaalis:BAAALgAECggJEQAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECggJGgAdAFQdAA==.',
Ky='Kyra:BAAALgADCgYJBgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.',
Le='Legault:BAAALgAECgcJEgAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAABLgAECn8VAAMLAAgJ4xtCJgDQAQALAAYJYBxCJgDQAQAMAAYJlhbgIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8YAAIPAAYJWCEWQACnAQAPAAYJWCEWQACnAQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8ZAAISAAYJVxhVRgByAQASAAYJVxhVRgByAQAAAA==.',
Lo='Loneshark:BAAALgAECgYJBwAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgADCgEJAgAAAA==.Loraddesmos:BAABLgAECn8hAAIMAAkJCw2XBQChAQAMAAkJCw2XBQChAQAAAA==.Loriah:BAABLgAECn8nAAISAAkJFwxZNgCkAQASAAkJFwxZNgCkAQAAAA==.',
Lu='Lucance:BAAALgADCgkJCQAAAA==.Lullaby:BAABLgAECn8gAAICAAkJhRYvCwA0AgACAAkJhRYvCwA0AgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAIJBQAOAK8TAA==.Marcdofu:BAAALgADCgkJDgAAAA==.Maryjanè:BAAALgADCgIJAgAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8RAAIGAAQJuCJoBACmAQAGAAQJuCJoBACmAQAuAAQKfzMAAwYACQlkJWgBAMEDAAYACQlkJWgBAMEDABoABQl6FLETADQBAAAA.Mayli:BAAALgAECgYJCQAAAA==.',
Mc='Mctanker:BAAALgAECgEJAQAAAA==.',
Me='Meascii:BAABLgAECn8VAAIjAAcJFRfXDQDzAQAjAAcJFRfXDQDzAQAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8SAAITAAUJ/h4tBAB5AQATAAUJ/h4tBAB5AQAuAAQKfzUAAhMACQn7IukBAAYDABMACQn7IukBAAYDAAAA.',
Mi='Millee:BAABLgAECn8UAAMCAAYJxRc1LQCRAQACAAYJxRc1LQCRAQARAAEJ7AUWVwAtAAAAAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAQJDAAOAGAbAA==.Miremana:BAAALgADCgcJBwABLgAFFAQJDAAOAGAbAA==.Mirespike:BAACLgAFFH8MAAIOAAQJYBt1AQCCAQAOAAQJYBt1AQCCAQAuAAQKfzIAAg4ACQlRIpkDAPgCAA4ACQlRIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgADCgkJFQAAAA==.Morlock:BAABLgAECn8hAAMLAAgJcAnXRQBXAQALAAgJLwnXRQBXAQANAAEJWwgeNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAABLgAECn8UAAISAAgJlQjDZQAiAQASAAgJlQjDZQAiAQAAAA==.Nadia:BAAALgAECgMJAwAAAA==.Nanako:BAAALgAECgQJCgAAAA==.Naughtyvoked:BAAALgAECgYJCgAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQABAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgEJAgAAAA==.',
Ni='Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8mAAISAAgJpRouHgATAgASAAgJpRouHgATAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8fAAIPAAgJsRkTJwAHAgAPAAgJsRkTJwAHAgAAAA==.',
Ny='Nyghtrider:BAAALgAECgYJEAAAAA==.Nymëra:BAABLgAECn8WAAIYAAYJ6w4nSgBZAQAYAAYJ6w4nSgBZAQAAAA==.Nyneeve:BAABLgAECn8cAAIRAAYJ9gvZJQAWAQARAAYJ9gvZJQAWAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJFAAdACwWAA==.Oddiee:BAABLgAECn8YAAMEAAcJNw9IVABAAQAEAAcJNw9IVABAAQAkAAQJzgPxOQB0AAABLgAECggJFAAdACwWAA==.Odinshunter:BAAALgAECgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECgYJEgABAAAAAA==.',
Oh='Ohdatroll:BAAALgAECgUJDQABLgAFFAIJBQAOAK8TAA==.',
Ol='Olgrin:BAAALgADCgkJCQABLgAECgEJAQABAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBQAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAAALgAECgcJEgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn8jAAIFAAgJeBF3IgBzAQAFAAgJeBF3IgBzAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECggJJgAKAGgkAA==.Parabelum:BAAALgADCgQJBwAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMLAAYJhh+ZOgB8AQALAAUJhh+ZOgB8AQAMAAEJAADjXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8IAAICAAUJGwvVCQAnAQACAAUJGwvVCQAnAQAuAAQKfx4AAwIACAnaJCMCAE8DAAIACAnaJCMCAE8DABEAAgkmDiBIAFIAAAAA.Peregrine:BAAALgADCgIJAgAAAA==.',
Ph='Phaet:BAACLgAFFH8MAAMLAAQJSB9MFQBgAQALAAQJSB9MFQBgAQAMAAEJiw5hFQBUAAAuAAQKfzQAAgsACQnxJHQGAN0CAAsACQnxJHQGAN0CAAAA.Philipp:BAABLgAECn8dAAIGAAgJswgWHwA+AQAGAAgJswgWHwA+AQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQABAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAIEAAkJ4xo/HAAfAgAEAAkJ4xo/HAAfAgAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgQJBwAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJAgABAAAAAA==.',
Ra='Raezorian:BAAALgADCgcJBwAAAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAAALgAECgYJEAAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn8lAAISAAgJawZiWwA5AQASAAgJawZiWwA5AQAAAA==.Rampant:BAAALgAECgQJCAABLgAECgYJEgABAAAAAA==.Randalore:BAAALgAECgEJAQABLgAFFAIJBQAOAK8TAA==.Randwulf:BAAALgAECgYJEAAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8PAAIPAAQJxBMJLQBPAQAPAAQJxBMJLQBPAQAuAAQKfycAAw8ACAlgIecwAK8CAA8ACAlgIecwAK8CACUAAwnRHM4NAOkAAAAA.Rathtard:BAAALgAECgQJCQABLgAFFAQJDwAPAMQTAA==.Rauloso:BAAALgAECgQJCQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQABAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECggJHwAUAFsdAA==.Resoluteone:BAABLgAECn8sAAIkAAgJyhCUDwB5AQAkAAgJyhCUDwB5AQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8MAAITAAQJcx7gBABvAQATAAQJcx7gBABvAQAuAAQKfywAAhMACQmXJb4DAFMDABMACQmXJb4DAFMDAAAA.',
Rh='Rhagul:BAAALgAECgYJBgAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQABAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8mAAISAAgJryEJCwCtAgASAAgJryEJCwCtAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8gAAIYAAgJ3xFlIQCoAQAYAAgJ3xFlIQCoAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgALAIEUAA==.Sarduccini:BAABLgAECn8iAAILAAgJgRTQTADiAQALAAgJgRTQTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sekio:BAAALgAECgIJAgAAAA==.',
Sh='Shamburgyr:BAAALgAECgMJAwABLgAECgYJDwABAAAAAA==.Shanàs:BAAALgAECgEJAQABLgAECgYJFQASALwfAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8MAAIhAAQJcQ63FgAsAQAhAAQJcQ63FgAsAQAuAAQKfxkAAyEACAlGH9ARAF0CACEACAlGH9ARAF0CAAkABAm2EWUpANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgAECgMJAwAAAA==.',
Sk='Skaara:BAAALgAECgEJAgAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgADCgUJBQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMFAAYJkRl+UwAsAQAFAAUJFhd+UwAsAQASAAYJoRIRuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Snowbiter:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAAALgAECgUJBQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAASAE0hAA==.Solarion:BAAALgADCggJCAAAAA==.Sonoforak:BAAALgAECgIJAgAAAA==.',
Sp='Sped:BAABLgAECn8dAAQUAAgJaBxJBQBPAgAUAAgJaBxJBQBPAgAmAAUJ0QZsLwB6AAAnAAEJ9wPyrgAtAAAAAA==.',
St='Stormeyes:BAAALgAECgEJAQABLgAECgYJFQAbALkZAA==.Stormslight:BAABLgAECn8VAAIbAAYJuRkoDgBVAQAbAAYJuRkoDgBVAQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgUJDQABLgAECgkJIQAKADUbAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgIJAgABAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAAALgAECgQJBQAAAA==.',
['Sô']='Sôlrïx:BAAALgADCgQJBAAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgADCgkJCAAAAA==.Talas:BAABLgAECn8mAAIbAAgJURbwCAC6AQAbAAgJURbwCAC6AQAAAA==.Tamarack:BAABLgAECn8XAAIdAAYJshtIQABNAQAdAAYJshtIQABNAQAAAA==.',
Te='Teetsie:BAAALgAECgEJAQAAAA==.Tehmber:BAAALgAECgQJCAAAAA==.Tehmplar:BAAALgAECgIJAgABLgAECgQJCAABAAAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAFAIghAA==.Theboart:BAAALgAECgQJBgAAAA==.Thredron:BAAALgAFFAIJAwAAAA==.',
To='Tooru:BAACLgAFFH8MAAMdAAQJgRUaJgD/AAAdAAMJxRcaJgD/AAAfAAEJsg49HABRAAAuAAQKfy4ABB0ACQm+IYsGACUDAB0ACQm+IYsGACUDACAABgkWGTVLACUBAB8AAwmRGPchAO0AAAAA.Tortiana:BAAALgADCgMJAwAAAA==.',
Tr='Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAQAAAA==.Trailertrash:BAABLgAECn8xAAIPAAgJXB2yJgAJAgAPAAgJXB2yJgAJAgAAAA==.Treebeef:BAACLgAFFH8KAAIcAAQJwwiGHADzAAAcAAQJwwiGHADzAAAuAAQKfy8AAxwACQkBG+0YAHACABwACQkBG+0YAHACAAYAAQnWA+mMACIAAAAA.Triena:BAAALgAECgMJBQAAAA==.Trumpeter:BAAALgAECgQJCgAAAA==.',
Ts='Tsukuyómi:BAAALgADCgIJAgAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQCAAgJrBzFDQB+AgACAAgJ2RvFDQB+AgAjAAUJDBd4LwAkAQARAAMJpRd4NwCqAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIdAAcJVgu8QgBFAQAdAAcJVgu8QgBFAQAAAA==.Ulysius:BAABLgAECn8kAAISAAkJ2xY3GQAyAgASAAkJ2xY3GQAyAgAAAA==.',
Un='Unicornslayr:BAABLgAECn8gAAIFAAgJ9RZuHAClAQAFAAgJ9RZuHAClAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAAALgAECgYJCAAAAA==.',
Va='Valgroth:BAAALgAECgEJAQAAAA==.Valkisek:BAABLgAECn8VAAIPAAYJqxcCmwCfAQAPAAYJqxcCmwCfAQAAAA==.Vallarfax:BAABLgAECn8hAAIdAAgJth2aEQBFAgAdAAgJth2aEQBFAgAAAA==.Vandro:BAAALgAECggJEwAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAABLgAECn8VAAIkAAgJxBZ8EAADAgAkAAgJxBZ8EAADAgAAAA==.Vashmonk:BAACLgAFFH8MAAIiAAQJzyPyBACoAQAiAAQJzyPyBACoAQAuAAQKfxUAAiIACQmcIYoFAIgCACIACQmcIYoFAIgCAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECgUJBwAAAA==.Velaric:BAABLgAECn8lAAIcAAgJQhrVEgA0AgAcAAgJQhrVEgA0AgAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgABAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAAALgAECgYJCwABLgAECgYJDwABAAAAAA==.Vewdoo:BAABLgAECn8jAAIZAAcJpyLoCABNAgAZAAcJpyLoCABNAgAAAA==.',
Vi='Viejoverde:BAAALgAECgEJAQAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgEJAQAAAA==.',
Vo='Voldune:BAAALgAECgIJAgAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQABAAAAAA==.',
Wa='Waiwai:BAAALgADCgUJBQAAAA==.Warfarin:BAAALgAECgEJAgAAAA==.Wascii:BAAALgAECgYJEQABLgAECgYJEgABAAAAAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAACAKwcAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAAALgAECgkJBwAAAA==.',
Wy='Wyrmblood:BAAALgADCgkJCQABLgAECggJKQARAEMjAA==.Wyrmheal:BAABLgAECn8pAAIRAAgJQyM9AwDKAgARAAgJQyM9AwDKAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Ya='Yakoff:BAAALgADCgIJAgAAAA==.Yamihime:BAABLgAECn8lAAMDAAkJfBQ4LACHAQADAAkJaws4LACHAQAKAAgJPxUlEgBoAQAAAA==.Yatiri:BAAALgAECgYJDwAAAA==.',
Yo='Yoowuzsup:BAAALgAFFAEJAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIPAAYJMAuLfwASAQAPAAYJMAuLfwASAQAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8bAAIfAAYJ/Rn4AADMAQAfAAYJ/Rn4AADMAQAuAAQKfygAAh8ACQmSIhcBAGADAB8ACQmSIhcBAGADAAAA.Zedsdeadd:BAAALgAECgQJBAAAAA==.Zephyr:BAAALgAECgYJDwAAAA==.Zeçhs:BAABLgAECn8YAAISAAkJTSEYCADQAgASAAkJTSEYCADQAgAAAA==.',
Zi='Zinek:BAAALgADCggJKAAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8VAAINAAYJNxoSBQCAAQANAAYJNxoSBQCAAQAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAQAAAA==.Zulfilith:BAAALgADCgkJDgAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Mage-Frost','DemonHunter-Devourer','Priest-Shadow','Paladin-Holy','Shaman-Enhancement','Monk-Windwalker','Shaman-Restoration','Paladin-Protection','Druid-Restoration','Druid-Feral','Rogue-Assassination','Hunter-BeastMastery','Rogue-Subtlety','Paladin-Retribution','Monk-Brewmaster','DemonHunter-Vengeance','Druid-Balance','Druid-Guardian','Mage-Arcane','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaronyates:BAAALgADCgcJBwABLgAECgYJDAABAAAAAA==.',
Ac='Actualegirl:BAAALgAECgMJAwABLgAECggJHAACANokAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAAALgAECgYJEQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQABAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAAALgAECggJEwAAAA==.',
Ar='Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJCQAAAA==.Ardzak:BAAALgAECgQJBQABLgAECgYJCQABAAAAAA==.Arragorn:BAAALgAECgcJEwAAAA==.',
As='Asendra:BAAALgAECgYJDgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAAALgAECgUJBwAAAA==.',
At='Athenea:BAAALgAECgQJBwAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAAALgAECgUJDAAAAA==.',
Ba='Bacon:BAABLgAECn8YAAIDAAYJ8yRjDwBuAgADAAYJ8yRjDwBuAgAAAA==.Bandìt:BAAALgAECggJCwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beyla:BAAALgAECgYJDAAAAA==.',
Bi='Bishamon:BAABLgAECn8gAAQEAAkJbSDuBQBeAwAEAAkJbSDuBQBeAwAFAAEJAACvaQA+AAAGAAEJAADjMQA6AAAAAA==.Bizotch:BAAALgAECgEJAQAAAA==.',
Bl='Bleau:BAAALgAECgYJEgAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAAALgAECgYJCwAAAA==.Bluebarrie:BAAALgADCgcJCgAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8bAAIHAAgJhhWmDQDcAQAHAAgJhhWmDQDcAQAAAA==.Branchling:BAAALgAECgYJBwABLgAFFAMJCAAHANIRAA==.Bridh:BAABLgAECn8XAAIIAAgJkiBFEQD0AgAIAAgJkiBFEQD0AgABLgAFFAUJDQAEAL0YAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJCwAAAA==.',
Bu='Butterkip:BAACLgAFFH8IAAIJAAUJZQacAwAhAQAJAAUJZQacAwAhAQAuAAQKfyAAAgkACQl4HSQKAOACAAkACQl4HSQKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cantkillme:BAAALgAECgIJAwAAAA==.Cazzc:BAAALgAECgQJBwAAAA==.',
Ce='Cellan:BAAALgAECgYJCgAAAA==.',
Ch='Chicharrones:BAAALgADCgkJCQABLgAECgYJGAADAPMkAA==.Chickenshift:BAAALgAECgMJAwAAAA==.Chipahoy:BAAALgAECgUJBwABLgAECgcJJAAHAJccAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAAALgAECgYJDwAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAQJDQAHAK0fAA==.Clamius:BAACLgAFFH8NAAIHAAQJrR/wBQBxAQAHAAQJrR/wBQBxAQAuAAQKfyIAAgcACAkCJU4RAEADAAcACAkCJU4RAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgADCgQJBAAAAA==.Coombrain:BAAALgAECgQJBAAAAA==.Cotopla:BAAALgAECgQJBgAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAICAAgJ4hbxFwAcAgACAAgJ4hbxFwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAAAAA==.',
Da='Dachyy:BAAALgAECgQJBAAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deathlentlez:BAAALgAECgYJDwAAAA==.Decaylentlez:BAAALgADCgIJAgABLgAECgYJDwABAAAAAA==.Deepwinter:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.Delphyne:BAAALgAECgQJBAAAAA==.Demonhunter:BAAALgAECgYJCQAAAA==.Demonios:BAAALgAECgEJAgAAAA==.Desong:BAAALgADCgYJBwAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECgcJDQAAAA==.',
Do='Dochaze:BAABLgAECn8aAAIKAAgJOh9ZBAAqAgAKAAgJOh9ZBAAqAgAAAA==.Dogdimmadome:BAAALgAECgQJCQAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgADCgkJEQABLgAECgYJCwABAAAAAA==.',
Dr='Dragone:BAAALgAECgQJBAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBAAAAA==.',
Dy='Dyanuh:BAAALgAECgQJCAAAAA==.',
['Dà']='Dàrkscythe:BAAALgADCgcJDgAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAAALgAECgYJDAAAAA==.Ehress:BAAALgAECgYJDAAAAA==.',
Ei='Eirinny:BAABLgAECn8XAAILAAgJ0wlEBABxAQALAAgJ0wlEBABxAQAAAA==.',
El='Elindez:BAAALgAECgYJCwAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.',
Em='Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgEJAgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgADCgkJHwAAAA==.',
Fa='Fathercaleb:BAAALgAECgIJAwABLgAFFAIJBQAMAAMeAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgIJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Fl='Flavio:BAAALgAECgIJAgAAAA==.',
Fo='Fortuna:BAAALgAECgUJCwAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn8fAAINAAgJYQ8TDwBPAQANAAgJYQ8TDwBPAQAAAA==.',
Ga='Galil:BAAALgADCgQJBQAAAA==.Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAAALgAECggJEwAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Gethealed:BAAALgAECgcJBwAAAA==.',
Gh='Ghostlock:BAAALgAECggJEAAAAA==.Ghoztface:BAABLgAECn8YAAIOAAYJXCDEDgDYAQAOAAYJXCDEDgDYAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECggJIQAPAJAbAA==.',
Gi='Giblock:BAAALgAECgYJDgAAAA==.',
Gl='Glamour:BAAALgAECgQJBQAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAUJDgAMALkaAA==.',
Go='Gorkun:BAAALgADCggJCwAAAA==.Gov:BAABLgAECn8iAAMIAAgJXyaLCABFAwAIAAgJXyaLCABFAwADAAEJUhI4bAA5AAAAAA==.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAECgEJAQAAAA==.',
Gr='Gralmerte:BAABLgAECn8VAAMQAAYJZB6zAgCjAQAQAAYJZB6zAgCjAQAPAAEJ9xSGxgA8AAAAAA==.Graygoyle:BAABLgAECn8WAAIRAAcJqgRtBAAKAQARAAcJqgRtBAAKAQAAAA==.Groggaris:BAAALgADCgIJAgAAAA==.Groosalugg:BAABLgAECn8aAAISAAgJTR3oAwBIAgASAAgJTR3oAwBIAgAAAA==.',
Gu='Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgQJCAAAAA==.',
Gw='Gwyndolïn:BAAALgAECgUJCQAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAAALgAECgYJDQAAAA==.Haiku:BAAALgADCgUJBQAAAA==.Haliax:BAAALgAECgEJAQABLgAECggJEwABAAAAAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAAALgAECgYJBgAAAA==.Hawktuahh:BAAALgADCgUJCAAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAAALgAFFAIJAgABLgAFFAUJDQATAEkeAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Holymun:BAAALgAECgUJBgAAAA==.Holyox:BAABLgAECn8fAAIUAAgJSAnZGQBVAQAUAAgJSAnZGQBVAQAAAA==.Hotcheeto:BAAALgAECgIJAgAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAAALgAECgQJBgAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgADCgQJBQAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAABLgAECn8iAAMQAAgJ+SM4AgAxAwAQAAgJ+SM4AgAxAwAPAAQJqhdTaQAXAQAAAA==.Imgibby:BAAALgADCgYJBgABLgAECgYJDgABAAAAAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAAALgAECggJDAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIUAAMJjxQQCQAEAQAUAAMJjxQQCQAEAQAAAA==.',
Ir='Irakwa:BAAALgAECgQJCAAAAA==.',
It='Itches:BAACLgAFFH8OAAIMAAUJuRpfAQDGAQAMAAUJuRpfAQDGAQAuAAQKfyAAAgwACAkHJOUDAE8DAAwACAkHJOUDAE8DAAAA.',
Iz='Izánámi:BAAALgAECggJCwAAAA==.',
Ja='Jagon:BAAALgAECgYJCgAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jasint:BAAALgAECgUJBQABLgAECgYJCgABAAAAAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8aAAIVAAgJ6BaGBADXAQAVAAgJ6BaGBADXAQAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.',
Jk='Jkbalo:BAAALgAECgIJAgAAAA==.Jkrlos:BAAALgAECgEJAQAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgEJAQAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAABLgAECn8aAAQIAAgJFCNoGADDAgAIAAgJHCFoGADDAgAWAAYJnCNTBQBUAgADAAQJMheHRADkAAAAAA==.Jphunt:BAAALgADCgUJBQABLgAECggJGgAIABQjAA==.',
Ju='Juddory:BAAALgAECgYJBgAAAA==.Junksvil:BAAALgAECgQJBAAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJCgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgADCgMJAwAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Kismët:BAAALgADCgYJDAAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAECgYJDgABAAAAAA==.',
Ko='Korinth:BAECLgAFFH8FAAIOAAIJEAhzBQBtAAAOAAIJEAhzBQBtAAAuAAQKfyMAAg4ACAmDGJILABECAA4ACAmDGJILABECAAAA.',
Kr='Kriaalis:BAAALgAECgUJBwAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECggJGgASAE0dAA==.',
Ky='Kyra:BAAALgADCgYJBgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECggJCgAAAA==.',
Le='Legault:BAAALgAECgUJBQAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAAALgAECgYJDAAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAAALgAECgYJEgAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAAALgAECgUJCwAAAA==.',
Lo='Loneshark:BAAALgADCgYJBgAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgADCgEJAgAAAA==.Loraddesmos:BAABLgAECn8aAAIFAAYJNwqhBQDoAAAFAAYJNwqhBQDoAAAAAA==.Loriah:BAABLgAECn8cAAIUAAcJLw1LHgA5AQAUAAcJLw1LHgA5AQAAAA==.',
Lu='Lullaby:BAABLgAECn8XAAICAAcJ9hcYHQD1AQACAAcJ9hcYHQD1AQAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgEJAQABLgAECggJIgAQAPkjAA==.Maryjanè:BAAALgADCgIJAgAAAA==.Mawzshallah:BAACLgAFFH8HAAIXAAIJ5SI8BwDLAAAXAAIJ5SI8BwDLAAAuAAQKfy4AAxcACQlUJGcBAMEDABcACQlUJGcBAMEDABgABQl6FLATADQBAAAA.Mayli:BAAALgAECgYJCQAAAA==.',
Mc='Mctanker:BAAALgAECgEJAQAAAA==.',
Me='Meascii:BAAALgAECgYJCgAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Merc:BAACLgAFFH8JAAIMAAMJ9BqgBwD8AAAMAAMJ9BqgBwD8AAAuAAQKfy8AAgwACAmuIqIBAE8CAAwACAmuIqIBAE8CAAAA.',
Mi='Millee:BAABLgAECn8UAAMCAAYJxRcwLQCRAQACAAYJxRcwLQCRAQAJAAEJKgbEIgAuAAAAAA==.Mindpuck:BAAALgAECgMJAwAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAIJBQAQAIcWAA==.Mirespike:BAACLgAFFH8FAAIQAAIJhxavAwC5AAAQAAIJhxavAwC5AAAuAAQKfyQAAhAACAkqIZkDAPgCABAACAkqIZkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgADCgQJBwAAAA==.Morlock:BAABLgAECn8VAAMEAAYJFQjWJQD+AAAEAAYJugfWJQD+AAAGAAEJWwgeNQAxAAAAAA==.',
Mu='Murlen:BAAALgAECgMJAwAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAAALgAECggJEQAAAA==.Nadia:BAAALgAECgIJAgAAAA==.Nanako:BAAALgAECgIJBAAAAA==.Naughtyvoked:BAAALgAECgQJBAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQABAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8aAAIUAAgJDxYyDADQAQAUAAgJDxYyDADQAQAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8UAAIHAAgJURZHDADtAQAHAAgJURZHDADtAQAAAA==.',
Ny='Nyghtrider:BAAALgAECgQJCAAAAA==.Nymëra:BAAALgAECgYJDwAAAA==.Nyneeve:BAAALgAECgYJEAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECgYJEQABAAAAAA==.Oddiee:BAAALgAECgYJEQAAAA==.Odst:BAAALgADCgUJBwABLgAECgYJDAABAAAAAA==.',
Oh='Ohdatroll:BAAALgAECgQJCwABLgAECggJIgAQAPkjAA==.',
On='Oneslice:BAAALgAECgUJBQAAAA==.Onyxstar:BAAALgADCgYJBgAAAA==.',
Op='Opera:BAAALgAECgMJAwAAAA==.',
Or='Orikkosh:BAAALgAECgUJBgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAAALgAECgcJEwAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECgYJGAADAPMkAA==.Parabelum:BAAALgADCgQJBwAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMEAAYJhh/OEACKAQAEAAUJhh/OEACKAQAFAAEJAADeXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAABLgAECn8cAAICAAgJ2iQkAgBPAwACAAgJ2iQkAgBPAwAAAA==.Peregrine:BAAALgADCgIJAgAAAA==.',
Ph='Phaet:BAACLgAFFH8FAAMEAAIJQRoYHACOAAAEAAIJuxcYHACOAAAFAAEJiw5dFQBUAAAuAAQKfyMAAgQACAmjJHEJADMDAAQACAmjJHEJADMDAAAA.Philipp:BAAALgAECgYJDwAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgQJBAABAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAAALgAECgcJEwAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgADCgkJCQAAAA==.',
Pu='Punslug:BAAALgAECgYJBgABLgAECggJEQABAAAAAA==.',
Ra='Raezorian:BAAALgADCgcJBwABLgAECggJGAAMAKEgAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAAALgAECgQJCAAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn8VAAIUAAYJ9QM9MgDRAAAUAAYJ9QM9MgDRAAAAAA==.Rampant:BAAALgADCgYJBgABLgAECgYJDAABAAAAAA==.Randwulf:BAAALgAECgYJCgAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8IAAIHAAMJ0hEZEwD8AAAHAAMJ0hEZEwD8AAAuAAQKfyEAAwcACAnCIOUwAK8CAAcACAnCIOUwAK8CABkAAwnRHMwNAOkAAAAA.Rathtard:BAAALgAECgQJCQABLgAFFAMJCAAHANIRAA==.Rauloso:BAAALgAECgMJBAAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQABAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgYJDwABAAAAAA==.Resoluteone:BAABLgAECn8ZAAIaAAgJBQ1lBgA+AQAaAAgJBQ1lBgA+AQAAAA==.Retnu:BAAALgADCggJDgAAAA==.Revytwohand:BAACLgAFFH8FAAIMAAIJAx5bCgC4AAAMAAIJAx5bCgC4AAAuAAQKfyEAAgwACAnpJL0DAFMDAAwACAnpJL0DAFMDAAAA.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQABAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8aAAIUAAgJoxttCgDnAQAUAAgJoxttCgDnAQAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAAALgAECgYJEQAAAA==.Sardmongo:BAAALgADCgYJBQAAAA==.Sardogobo:BAAALgADCgkJHwABLgAECggJHQAEABQUAA==.Sarduccini:BAABLgAECn8dAAIEAAgJFBTWTADiAQAEAAgJFBTWTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sekio:BAAALgADCgEJAQAAAA==.',
Sh='Shamburgyr:BAAALgAECgMJAwABLgAECgQJBgABAAAAAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8FAAIbAAMJOgunCQDoAAAbAAMJOgunCQDoAAAuAAQKfxkAAxsACAk7H88RAF0CABsACAk7H88RAF0CABwABAm2EWMpANQAAAAA.Silvalus:BAAALgADCgkJFQAAAA==.Sin:BAAALgADCgMJCQAAAA==.',
Sk='Skaara:BAAALgADCgYJBgAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.',
Sl='Slipknoth:BAAALgAECgYJEAAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJBwAAAA==.',
Sn='Snowbiter:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAAALgADCgUJBwAAAA==.Soi:BAAALgAECgYJCgABLgAECggJEwABAAAAAA==.Solarion:BAAALgADCggJCAAAAA==.',
Sp='Sped:BAAALgAECgYJEwAAAA==.',
St='Stormeyes:BAAALgAECgEJAQABLgAECgUJCQABAAAAAA==.Stormslight:BAAALgAECgUJCQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgQJBQABLgAECggJGQADADIcAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgIJAgABAAAAAA==.',
['Så']='Såran:BAAALgAECgQJBwAAAA==.',
['Sí']='Sílence:BAAALgADCgcJDgAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgADCgkJCAAAAA==.Talas:BAABLgAECn8aAAIOAAgJFxKHBABoAQAOAAgJFxKHBABoAQAAAA==.Tamarack:BAABLgAECn8XAAISAAYJsxtREgBqAQASAAYJsxtREgBqAQAAAA==.',
Te='Tehmber:BAAALgAECgMJBQAAAA==.',
Th='Theboart:BAAALgAECgQJBgAAAA==.Thredron:BAAALgAECgIJAgAAAA==.',
To='Tooru:BAACLgAFFH8FAAISAAIJghR0DQCwAAASAAIJghR0DQCwAAAuAAQKfyMAAxIACAnQI40GACUDABIACAnQI40GACUDAB0ABgkWGRxLACUBAAAA.',
Tr='Trailertrash:BAABLgAECn8kAAIHAAcJlxyVTABRAgAHAAcJlxyVTABRAgAAAA==.Treebeef:BAABLgAECn8hAAMPAAgJkBvwGABwAgAPAAgJkBvwGABwAgAXAAEJ1gPWjAAiAAAAAA==.Triena:BAAALgAECgMJBQAAAA==.Trumpeter:BAAALgAECgMJBgAAAA==.',
Ty='Tyberos:BAABLgAECn8gAAQCAAgJPBzGDQB+AgACAAgJaRvGDQB+AgAeAAUJDBd6LwAkAQAJAAEJcQ3PXABAAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgEJAQAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAAALgAECgUJDAAAAA==.Ulysius:BAABLgAECn8YAAIUAAcJLRZ1FQB1AQAUAAcJLRZ1FQB1AQAAAA==.',
Un='Unicornslayr:BAABLgAECn8UAAIKAAgJ4BSFCAC+AQAKAAgJ4BSFCAC+AQAAAA==.',
Ur='Urund:BAAALgAECgYJCgAAAA==.',
Va='Valgroth:BAAALgAECgEJAQAAAA==.Valkisek:BAABLgAECn8VAAIHAAYJqxcSmwCfAQAHAAYJqxcSmwCfAQAAAA==.Vallarfax:BAABLgAECn8VAAISAAgJtRqpBAAzAgASAAgJtRqpBAAzAgAAAA==.Vandro:BAAALgAECgYJDwAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAAALgAECggJEAAAAA==.Vashmonk:BAABLgAFFH8FAAIVAAIJrx9qCQDKAAAVAAIJrx9qCQDKAAAAAA==.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECgUJBwAAAA==.Velaric:BAABLgAECn8ZAAIPAAgJgxUxCwCkAQAPAAgJgxUxCwCkAQAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgABAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAAALgAECgQJBgAAAA==.Vewdoo:BAABLgAECn8VAAIfAAYJpCAjHQAoAgAfAAYJpCAjHQAoAgAAAA==.',
Vi='Viejoverde:BAAALgAECgEJAQAAAA==.Vipul:BAAALgAECgUJCAAAAA==.Vizimir:BAAALgADCgcJDAAAAA==.',
Vo='Voldune:BAAALgADCgcJCgAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQABAAAAAA==.',
Wa='Waiwai:BAAALgADCgUJBQAAAA==.Wascii:BAAALgAECgYJCAABLgAECgYJDAABAAAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJIAACADwcAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAAALgAECgkJBwAAAA==.',
Wy='Wyrmblood:BAAALgADCgkJCQABLgAECgcJGwAJAGYiAA==.Wyrmheal:BAABLgAECn8bAAIJAAcJZiLAAwDxAQAJAAcJZiLAAwDxAQAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Ya='Yakoff:BAAALgADCgIJAgAAAA==.Yamihime:BAABLgAECn8XAAIDAAgJPxUxBQB3AQADAAgJPxUxBQB3AQAAAA==.Yatiri:BAAALgAECgUJBgAAAA==.',
Yo='Yoowuzsup:BAAALgAFFAEJAQAAAA==.',
Yu='Yureimage:BAAALgAECgYJEQAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8QAAIgAAUJkQyCAACuAQAgAAUJkQyCAACuAQAuAAQKfyUAAiAACQmSIhgBAGADACAACQmSIhgBAGADAAAA.Zedsdeadd:BAAALgADCgkJFQAAAA==.Zephyr:BAAALgADCgcJCAABLgAECgQJBgABAAAAAA==.Zeçhs:BAAALgAECggJEwAAAA==.',
Zi='Zinek:BAAALgADCggJGgAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAAALgAECgQJBwAAAA==.',
['Zð']='Zðltrain:BAAALgADCgYJCAAAAA==.',
['Ál']='Álfruen:BAAALgAECgIJAgAAAA==.',
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

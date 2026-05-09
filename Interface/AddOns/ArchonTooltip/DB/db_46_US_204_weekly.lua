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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Warrior-Fury','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Paladin-Holy','Hunter-Survival','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Monk-Windwalker','Rogue-Outlaw','Druid-Guardian','Druid-Feral','Priest-Discipline','Priest-Holy','Monk-Brewmaster','Priest-Shadow','DemonHunter-Havoc','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aalwein:BAABLgAECn8mAAIBAAgJEB6yEABPAgABAAgJEB6yEABPAgAAAA==.',
Ae='Aesculapius:BAABLgAECn8ZAAICAAcJ3hgBGQD9AQACAAcJ3hgBGQD9AQAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.Aloisious:BAAALgAECgEJAQAAAA==.',
Am='Amarii:BAAALgAECgYJDQAAAA==.Amorash:BAAALgADCgEJAQAAAA==.',
An='Anonymus:BAAALgAFFAEJAgAAAA==.',
Ar='Ardwin:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.',
As='Ashgrove:BAAALgAECgUJCAAAAA==.',
Av='Avigar:BAAALgADCgEJAwAAAA==.',
Ba='Bambarrok:BAABLgAECn8UAAIEAAgJegVaWAAkAQAEAAgJegVaWAAkAQAAAA==.Bangan:BAAALgAECgEJAQAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgYJBwABLgAECgkJGgAFADEVAA==.Bepragosa:BAABLgAECn8aAAIFAAkJMRWjCAA3AgAFAAkJMRWjCAA3AgAAAA==.',
Bi='Binpharteen:BAAALgADCgcJEwAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECgcJDwADAAAAAA==.',
Bo='Bowguytome:BAAALgAECgcJDAABLgAECgkJIQAGAOkmAA==.',
Br='Brimscythe:BAAALgAECgEJAgAAAA==.Brownbelt:BAABLgAECn8gAAIHAAYJNxhnHwBwAQAHAAYJNxhnHwBwAQAAAA==.Brîn:BAAALgADCgcJDQAAAA==.',
Bu='Buteihunter:BAABLgAECn8bAAMBAAgJhh1aEQCuAgABAAgJhh1aEQCuAgAGAAEJ7wtCiAA0AAAAAA==.',
Ca='Cadranak:BAABLgAECn8eAAIIAAgJCg6dPQBBAQAIAAgJCg6dPQBBAQAAAA==.Caiyenthi:BAABLgAECn8gAAIBAAgJhg+kKwChAQABAAgJhg+kKwChAQAAAA==.Calliesue:BAAALgAECgIJAgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAABLgAECn8XAAQHAAkJ8RVqJQAtAgAHAAgJ/BZqJQAtAgAJAAUJ5BBTEABEAQAKAAEJNAg9MwBAAAAAAA==.Chelly:BAAALgAECgEJAQABLgAECgkJFwAHAPEVAA==.Chicharrone:BAAALgAECgYJEgAAAA==.Chizaru:BAAALgAECggJEQAAAA==.Chlorophyll:BAAALgADCgEJAQAAAA==.Chyntobelt:BAABLgAECn8XAAILAAYJDAOvlAC3AAALAAYJDAOvlAC3AAABLgAECgYJIAAHADcYAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAAALgAECggJEAAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAAALgAECgQJBwAAAA==.Dalhma:BAAALgAECgUJBgAAAA==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgAECgUJBQAAAA==.',
De='Deadbeat:BAAALgAECgEJAQAAAA==.Deafenned:BAABLgAECn8aAAIMAAkJdx6aPQCBAgAMAAkJdx6aPQCBAgABLgAFFAMJBwAIANEOAA==.Deaflynn:BAAALgAECgEJAgABLgAFFAMJBwAIANEOAA==.Deafnight:BAAALgAECgIJAwABLgAFFAMJBwAIANEOAA==.Demonbep:BAAALgADCgQJBAABLgAECgkJGgAFADEVAA==.Derrington:BAABLgAECn8XAAIFAAYJmCDNAwDfAQAFAAYJmCDNAwDfAQAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.Dett:BAAALgAECgQJBAAAAA==.',
Di='Diamante:BAACLgAFFH8IAAINAAQJLhdVFAAjAQANAAQJLhdVFAAjAQAuAAQKfykAAg0ACAmHFxwdAMgBAA0ACAmHFxwdAMgBAAAA.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8jAAMOAAgJKg7/GAB4AQAOAAgJKg7/GAB4AQAPAAQJBQJBMgCEAAAAAA==.Drellin:BAAALgAECgEJAwAAAA==.Dremu:BAABLgAECn8dAAMQAAgJ2RqxCwAOAgAQAAgJ2RqxCwAOAgACAAMJEw9XoACJAAAAAA==.',
Du='Duraz:BAABLgAECn8dAAICAAgJ0g6gNwA4AQACAAgJ0g6gNwA4AQAAAA==.',
Dy='Dysraxis:BAAALgADCgEJAQAAAA==.',
Ee='Eerie:BAAALgAECgIJAwAAAA==.',
Eg='Eggar:BAAALgADCgYJEgABLgAECggJHwALAOsSAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAAALgAECgYJEgAAAA==.Elamaun:BAABLgAECn8gAAIRAAYJARaNIgBzAQARAAYJARaNIgBzAQAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgUJBwAAAA==.',
En='English:BAAALgAECgcJDwAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgAECgEJAQAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn8gAAISAAYJxw2bGgAwAQASAAYJxw2bGgAwAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAABLgAECn8kAAITAAgJ3B8LKQCBAgATAAgJ3B8LKQCBAgAAAA==.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgkJCQAAAA==.',
Gl='Glabberghoul:BAABLgAECn8nAAIOAAkJQRSJDwDaAQAOAAkJQRSJDwDaAQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgQJBQAAAA==.Griogair:BAAALgADCgYJEQABLgAECgYJEgADAAAAAA==.',
Ha='Hacelian:BAAALgADCgMJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
He='Heetseeker:BAAALgAECgIJAgABLgAECgkJGwANAMQgAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCgcJBwADAAAAAA==.Holyverdict:BAABLgAECn8XAAIRAAkJUSWcBQASAwARAAkJUSWcBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8kAAINAAkJoB8HFAB1AgANAAkJoB8HFAB1AgAAAA==.',
In='Incinderella:BAAALgADCgEJAQABLgAECgYJDQADAAAAAA==.Interval:BAAALgADCgcJDgABLgAECggJKAATACQfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAAALgAECgUJCwAAAA==.',
Je='Jeisa:BAABLgAECn8UAAMUAAYJ7wwGGwC8AAATAAUJog2IigDYAAAUAAYJIAoGGwC8AAAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAAALgAECgYJEgAAAA==.Kastoria:BAAALgADCgkJDwAAAA==.Katnipp:BAABLgAECn8bAAIBAAgJbBSPIADZAQABAAgJbBSPIADZAQAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAAALgAECgYJDgAAAA==.',
Ke='Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8fAAILAAgJ6xLMLwC6AQALAAgJ6xLMLwC6AQAAAA==.',
Ki='Kiye:BAACLgAFFH8OAAIBAAQJkBNWFABLAQABAAQJkBNWFABLAQAuAAQKfykAAgEACQnaG3kPAL8CAAEACQnaG3kPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAABLgAECn8VAAILAAkJfwr9LQDCAQALAAkJfwr9LQDCAQAAAA==.',
Ku='Kuuro:BAABLgAECn8VAAINAAYJQhXYLQBdAQANAAYJQhXYLQBdAQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgADCgUJBQAAAA==.',
Le='Leibniz:BAAALgAECgYJEQAAAA==.Leisa:BAABLgAECn8VAAIBAAYJPA7iSwAqAQABAAYJPA7iSwAqAQAAAA==.Lelwindae:BAAALgAECgUJBgAAAA==.',
Li='Lightgiver:BAAALgAECgUJBQAAAA==.Lighthoof:BAABLgAECn8gAAMTAAkJNx81FQDrAgATAAkJNx81FQDrAgAUAAQJVBsVGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMCAAYJBhbmRQCKAQACAAYJBhbmRQCKAQAQAAQJZQGUcgBXAAAAAA==.Liminara:BAEALgAFFAMJAwABLgAFFAYJDAABAL4ZAA==.Linaste:BAAALgAECgQJBAAAAA==.Lividzdk:BAABLgAECn8vAAMLAAgJVyA8EQBzAgALAAgJVyA8EQBzAgAVAAEJxQXsPwAZAAAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJFgAWAJwPAA==.',
Lu='Lulu:BAABLgAFFH8EAAIWAAQJ2xSTDgD7AAAWAAQJ2xSTDgD7AAAAAA==.',
Ly='Lynoia:BAAALgAECgYJBgAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBwAAAA==.Manknus:BAABLgAECn8dAAIHAAgJ3gqsHwBuAQAHAAgJ3gqsHwBuAQAAAA==.Mantequilla:BAABLgAECn8YAAILAAcJTxy7SQAWAgALAAcJTxy7SQAWAgAAAA==.Manthrax:BAABLgAECn8YAAINAAgJQAb5TQBLAQANAAgJQAb5TQBLAQAAAA==.Marix:BAAALgADCgEJAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAABLgAECn8WAAIXAAYJESONAgABAgAXAAYJESONAgABAgAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCggJCQAAAA==.Mykie:BAAALgADCgUJBQAAAA==.Mylor:BAABLgAECn8fAAMRAAgJhRFdGADJAQARAAgJhRFdGADJAQATAAEJvw/tSAEwAAAAAA==.Myrddral:BAABLgAECn8VAAIVAAYJBx8uDACyAQAVAAYJBx8uDACyAQAAAA==.Mystifeyed:BAABLgAECn8hAAMYAAkJGwrPEgDdAAAZAAcJYgmNFgBQAQAYAAgJMAfPEgDdAAAAAA==.',
['Mü']='Mürsaat:BAABLgAECn8ZAAITAAYJPRW7VABJAQATAAYJPRW7VABJAQAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAcJIgAVAFgeAA==.Narra:BAAALgAECgIJAgABLgADCgcJBwADAAAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQADAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn8yAAMaAAkJ0COsAACuAwAaAAkJ0COsAACuAwAbAAEJFCL4cgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAABLgAECn8WAAIBAAYJDwYBYADwAAABAAYJDwYBYADwAAAAAA==.',
Ol='Olizia:BAABLgAECn8WAAILAAcJiBKNdQCaAQALAAcJiBKNdQCaAQAAAA==.',
On='Onaga:BAAALgAECgUJCgAAAA==.',
Op='Opex:BAABLgAECn8aAAMBAAkJyAygSACQAQABAAkJyAygSACQAQAGAAEJUQB4mwATAAAAAA==.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECgkJEQAAAA==.',
Pa='Paw:BAAALgADCgEJAgAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.',
Ph='Philomel:BAACLgAFFH8HAAIIAAMJ0Q42NgDZAAAIAAMJ0Q42NgDZAAAuAAQKfxwAAggACAk/G8krAE8CAAgACAk/G8krAE8CAAAA.',
Pi='Pixamoo:BAAALgADCgUJCAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Priesthealz:BAAALgAECgEJAQABLgAECgkJLQAcAGYcAA==.Pritt:BAAALgADCgcJDQABLgAECgYJDAADAAAAAA==.',
Qu='Quazu:BAAALgADCgEJAQAAAA==.',
Ra='Radagahst:BAAALgAECgYJCwAAAA==.Rarngorm:BAAALgAECggJEgAAAA==.Ravinar:BAAALgAECgYJEgAAAA==.',
Re='Reardain:BAAALgAECgYJDgAAAA==.Received:BAAALgAECgIJAgAAAA==.Relia:BAABLgAECn8XAAMdAAkJyQ/EIQDJAQAdAAgJNhDEIQDJAQAaAAEJKAZ2QwA9AAAAAA==.Remedy:BAAALgADCgcJBwAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Riverwind:BAAALgAECgUJCgABLgAECgkJGwANAMQgAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAAALgAECgYJDwAAAA==.',
Ry='Ryo:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Sakuf:BAAALgADCgcJBwAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAAALgAECgYJDgAAAA==.Save:BAAALgAECgIJBAABLgAECggJIAAbAIgfAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8WAAIbAAkJ9hqYCwCXAgAbAAkJ9hqYCwCXAgAAAA==.Shallbedo:BAAALgAECgYJCwABLgAECggJHwAPAAsaAA==.Shallvoker:BAABLgAECn8fAAMPAAgJCxrqCgAtAgAPAAgJPxbqCgAtAgAOAAQJLxatKQAHAQAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.Shmalexia:BAAALgAECgIJAgAAAA==.',
Si='Siatraler:BAAALgAECggJDgAAAA==.Sigarette:BAACLgAFFH8iAAIVAAcJWB7eAAAvAgAVAAcJWB7eAAAvAgAuAAQKfzQAAhUACAnXJJkCAEIDABUACAnXJJkCAEIDAAAA.Silverspoon:BAAALgAECgIJAgAAAA==.Sinardi:BAABLgAECn8UAAIeAAYJuwo4IADYAAAeAAYJuwo4IADYAAAAAA==.',
Sk='Skoobz:BAAALgADCgEJAQAAAA==.Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgAECgYJBgAAAA==.Skylock:BAAALgAECgkJDwAAAA==.Skymane:BAAALgAECgYJEQAAAA==.',
Sn='Snaggletooth:BAAALgADCgEJAQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovix:BAAALgADCgIJAgAAAA==.Sovo:BAACLgAFFH8PAAIMAAUJ8xlGJQBeAQAMAAUJ8xlGJQBeAQAuAAQKfygAAgwACQlEIpMdAP8CAAwACQlEIpMdAP8CAAAA.',
Sq='Squshmepure:BAAALgAECgYJAgAAAA==.',
St='Starrin:BAAALgAECgYJDgAAAA==.Steaknquake:BAABLgAECn8gAAINAAYJGCBwEgAlAgANAAYJGCBwEgAlAgAAAA==.',
Su='Sumdumfun:BAAALgAECgMJAwAAAA==.Sunflower:BAAALgAECgYJDQAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ5RgeOQDKAQABAAcJNRoeOQDKAQAGAAUJ6wsiWQDhAAAAAA==.Sylvandel:BAABLgAECn8WAAIGAAYJkBQ2CwA7AQAGAAYJkBQ2CwA7AQAAAA==.',
Ta='Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn8rAAICAAkJNgZZOgAsAQACAAkJNgZZOgAsAQAAAA==.',
Th='Thalius:BAABLgAECn8VAAILAAYJzw0SYQAiAQALAAYJzw0SYQAiAQAAAA==.Thorandaal:BAAALgAECgUJBQAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tome:BAABLgAECn8hAAQGAAkJ6SYDAAAbBAAGAAkJ3CYDAAAbBAASAAkJwyYPAACcAwABAAEJEyaKjwBvAAAAAA==.Tometv:BAAALgAECgcJBgABLgAECgkJIQAGAOkmAA==.Toomanydeths:BAABLgAECn8rAAMVAAkJJg4qDwB/AQAVAAkJJg4qDwB/AQALAAEJqAiNIgExAAAAAA==.',
Tr='Trunx:BAAALgAECgEJAQABLgAECgkJHwAfAN4jAA==.',
Ty='Tye:BAAALgAECgUJCgAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJBAAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Ur='Ursusmanny:BAAALgAECgMJAwAAAA==.',
Va='Vaelthyeth:BAAALgADCgUJBQAAAA==.Vandarin:BAAALgADCgcJGgABLgAECgYJEgADAAAAAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8rAAMgAAkJ5iHlAQBkAgAgAAgJLyLlAQBkAgAhAAcJRyL7GAA9AgAAAA==.',
Ve='Velysa:BAABLgAECn8XAAMUAAYJzRYpDwBGAQAUAAYJzRYpDwBGAQATAAIJOgkyHgFgAAAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8bAAMNAAkJxCAlCADyAgANAAkJxCAlCADyAgAiAAMJkg45RACYAAAAAA==.Watlmonk:BAAALgADCgIJAgAAAA==.',
We='Weatherworn:BAABLgAECn8bAAINAAYJ6RidIwCaAQANAAYJ6RidIwCaAQAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECgYJGQAFADAZAA==.Xerber:BAAALgADCgYJCgABLgAECgYJEgADAAAAAA==.',
Xi='Xiro:BAAALgAECgUJEQAAAA==.',
Yo='Yoril:BAAALgAECgIJAgAAAA==.',
Za='Zagiroth:BAABLgAECn8lAAMIAAkJ9CC5AwD/AgAIAAkJ9CC5AwD/AgAjAAEJFhtgJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgYJEgADAAAAAA==.',
Ze='Zebraman:BAABLgAECn8VAAICAAgJCxJqKQCHAQACAAgJCxJqKQCHAQAAAA==.Zeraida:BAAALgADCgcJDAAAAA==.',
['Zê']='Zêth:BAAALgADCgEJAQAAAA==.',
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

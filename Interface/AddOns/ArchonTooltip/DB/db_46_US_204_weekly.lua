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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Warlock-Destruction','Warrior-Fury','DemonHunter-Devourer','Mage-Frost','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','DeathKnight-Unholy','Paladin-Holy','Hunter-Survival','Paladin-Retribution','Paladin-Protection','Druid-Balance','Druid-Feral','Druid-Guardian','DeathKnight-Blood','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Priest-Shadow','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','DemonHunter-Vengeance',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aalwein:BAABLgAECn8XAAIBAAcJxxodCwC4AQABAAcJxxodCwC4AQAAAA==.',
Ae='Aesculapius:BAAALgAECgQJBAAAAA==.',
Al='Aladia:BAAALgADCgMJAgAAAA==.',
Am='Amarii:BAAALgAECgIJAgAAAA==.',
An='Anonymus:BAAALgAECgIJAwAAAA==.',
Ar='Ardwin:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
As='Ashgrove:BAAALgAECgQJBAAAAA==.',
Av='Avigar:BAAALgADCgEJAQAAAA==.',
Ba='Bambarrok:BAAALgAECgcJEgAAAA==.Bangan:BAAALgAECgEJAQAAAA==.',
Be='Belakor:BAAALgAECgYJBgAAAA==.Bep:BAAALgAECgEJAQABLgAECggJGAADAB0VAA==.Bepragosa:BAABLgAECn8YAAIDAAgJHRWgCAA3AgADAAgJHRWgCAA3AgAAAA==.',
Bl='Blaque:BAAALgADCgcJBwABLgAECgYJCQACAAAAAA==.',
Bo='Bowguytome:BAAALgAECgcJDAAAAA==.',
Br='Brimscythe:BAAALgAECgEJAgAAAA==.Brownbelt:BAABLgAECn8UAAIEAAYJUBM+DABcAQAEAAYJUBM+DABcAQAAAA==.Brîn:BAAALgADCgYJCgAAAA==.',
Bu='Buteihunter:BAAALgAECggJEwAAAA==.',
Ca='Cadranak:BAABLgAECn8WAAIFAAgJcQzCVQCiAQAFAAgJcQzCVQCiAQAAAA==.Caiyenthi:BAAALgAECgcJEgAAAA==.Camgor:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Carfalis:BAAALgADCggJCQAAAA==.',
Ch='Chelali:BAAALgAECgkJEQAAAA==.Chicharrone:BAAALgAECgUJCAAAAA==.Chizaru:BAAALgAECggJCAAAAA==.Chlorophyll:BAAALgADCgEJAQAAAA==.Chyntobelt:BAAALgAECgYJDQABLgAECgYJFAAEAFATAA==.',
Cr='Creep:BAAALgAECgYJEAAAAA==.Cryption:BAAALgAECggJCQAAAA==.',
['Cú']='Cúchulainn:BAAALgAECgYJDQAAAA==.',
Da='Daelyn:BAAALgAECgMJAwAAAA==.Dane:BAAALgAECgIJAgAAAA==.Dayaris:BAAALgADCgcJBwAAAA==.',
De='Deafenned:BAABLgAECn8XAAIGAAkJcR6bPQCBAgAGAAkJcR6bPQCBAgAAAA==.Deafnight:BAAALgAECgIJAgABLgAECgkJFwAGAHEeAA==.Demonbep:BAAALgADCgQJBAABLgAECggJGAADAB0VAA==.Derrington:BAAALgAECgUJCgAAAA==.Destinyetwo:BAAALgAECgEJAQAAAA==.',
Di='Diamante:BAABLgAECn8dAAIHAAcJNRXkNQCsAQAHAAcJNRXkNQCsAQAAAA==.',
Dk='Dkvayce:BAAALgADCgYJBgAAAA==.',
Dr='Drakluz:BAAALgADCgEJAQAAAA==.Drakner:BAABLgAECn8VAAMIAAYJlgs5OAAVAQAIAAYJlgs5OAAVAQAJAAQJBQI+MgCEAAAAAA==.Drellin:BAAALgAECgEJAgAAAA==.Dremu:BAAALgAECgYJEgAAAA==.',
Du='Duraz:BAABLgAECn8VAAIKAAcJ7w8UTQBwAQAKAAcJ7w8UTQBwAQAAAA==.',
Ee='Eerie:BAAALgAECgEJAQAAAA==.',
Eg='Eggar:BAAALgADCgYJBgABLgAECgYJFQALABAQAA==.',
El='Elahna:BAAALgADCgcJDQAAAA==.Elalia:BAAALgAECgEJAQAAAA==.Elamaun:BAABLgAECn8UAAIMAAYJwRBuEwAKAQAMAAYJwRBuEwAKAQAAAA==.Elereia:BAAALgAECgEJAQAAAA==.Eltiana:BAAALgAECgMJAwAAAA==.',
En='English:BAAALgAECgYJCQAAAA==.',
Ep='Ephex:BAAALgADCgcJGQAAAA==.Ephyiana:BAAALgADCgcJCAAAAA==.',
Er='Errimys:BAAALgADCgUJBQAAAA==.Ertraz:BAAALgADCgYJBgAAAA==.',
Es='Essense:BAAALgADCgcJBwAAAA==.Esçanor:BAAALgADCgUJBQAAAA==.',
Et='Etania:BAAALgAECgYJCQAAAA==.',
Fa='Faelyna:BAABLgAECn8UAAINAAYJAQ3RCQADAQANAAYJAQ3RCQADAQAAAA==.',
Fe='Felnut:BAAALgADCgEJAQAAAA==.',
Fo='Foix:BAAALgADCgcJDwAAAA==.Forged:BAABLgAECn8bAAIOAAcJBB4NKQCBAgAOAAcJBB4NKQCBAgAAAA==.',
Ga='Gaerne:BAAALgADCgEJAQAAAA==.',
Gi='Githyanki:BAAALgADCgYJBgAAAA==.',
Gl='Glabberghoul:BAABLgAECn8cAAIIAAkJPw/ZIwCfAQAIAAkJPw/ZIwCfAQAAAA==.',
Go='Goodhead:BAAALgADCgMJBAAAAA==.',
Gr='Grangmage:BAAALgAECgEJAQAAAA==.Griogair:BAAALgADCgYJCwABLgAECgEJAQACAAAAAA==.',
Ha='Hacelian:BAAALgADCgMJAwAAAA==.Harper:BAAALgADCgcJBwAAAA==.',
Ho='Hoggins:BAAALgADCgUJBQABLgADCggJAwACAAAAAA==.Holyverdict:BAABLgAECn8XAAIMAAkJUSWfBQASAwAMAAkJUSWfBQASAwAAAA==.',
Ic='Icaina:BAABLgAECn8bAAIHAAgJgx8PFAB1AgAHAAgJgx8PFAB1AgAAAA==.',
Ii='Iiliilliilil:BAAALgADCgYJEAAAAA==.',
In='Interval:BAAALgADCgcJBwABLgAECgcJGAAOABkfAA==.',
Is='Islands:BAAALgADCgIJAgAAAA==.',
Ja='Jadani:BAAALgAECgUJBQAAAA==.',
Je='Jeisa:BAAALgAECgMJBwAAAA==.',
Ji='Jimbonereus:BAAALgADCgIJAgAAAA==.',
Jo='Jordyevoker:BAAALgAECggJDQAAAA==.',
Ka='Kalchee:BAAALgADCgIJAgAAAA==.Kallotera:BAAALgAECgUJCQAAAA==.Kastoria:BAAALgADCgUJBQAAAA==.Katnipp:BAAALgAECggJEwAAAA==.Katnyss:BAAALgAECgYJDQAAAA==.Kaylazune:BAAALgAECgEJAQAAAA==.',
Ke='Keramoon:BAAALgADCgUJBQAAAA==.Keyleth:BAAALgAECgEJAQAAAA==.',
Kh='Khrala:BAABLgAECn8VAAILAAYJEBCHHQAvAQALAAYJEBCHHQAvAQAAAA==.',
Ki='Kiye:BAACLgAFFH8GAAIBAAMJSQxQGgCdAAABAAMJSQxQGgCdAAAuAAQKfygAAgEACQm8G3sPAL8CAAEACQm8G3sPAL8CAAAA.',
Ko='Koren:BAAALgADCgMJAgAAAA==.',
Kr='Krenko:BAAALgAECgcJBwAAAA==.',
Ku='Kuuro:BAAALgAECgUJCQAAAA==.',
La='Lanister:BAAALgADCgQJBAAAAA==.Lattymag:BAAALgAECgUJBwAAAA==.Laughystabby:BAAALgADCgMJAwAAAA==.',
Le='Leibniz:BAAALgAECgUJCAAAAA==.Leisa:BAAALgAECgUJCQAAAA==.Lelwindae:BAAALgAECgMJBAAAAA==.',
Li='Lightgiver:BAAALgAECgUJBAAAAA==.Lighthoof:BAABLgAECn8eAAMOAAgJZyAyFQDrAgAOAAgJZyAyFQDrAgAPAAQJVBsVGwA1AQAAAA==.Lightiuz:BAABLgAECn8eAAMKAAYJBhbiRQCKAQAKAAYJBhbiRQCKAQAQAAQJZQGEcgBXAAAAAA==.Liminara:BAEALgAFFAMJAwAAAA==.Linaste:BAAALgADCgQJBAAAAA==.Lividzdk:BAABLgAECn8gAAILAAYJASI5DQC0AQALAAYJASI5DQC0AQAAAA==.',
Lo='Lonaldo:BAAALgAECgEJAQAAAA==.Lowpop:BAAALgADCgQJBAABLgAECgcJEwACAAAAAA==.',
Ly='Lynoia:BAAALgADCgkJEgAAAA==.',
Ma='Malarus:BAAALgADCgEJAQAAAA==.Mandevu:BAAALgAECgUJBgAAAA==.Manknus:BAAALgAECgYJEgAAAA==.Mantequilla:BAABLgAECn8YAAILAAcJTxy8SQAWAgALAAcJTxy8SQAWAgAAAA==.Manthrax:BAABLgAECn8WAAIHAAgJEAQCTgBLAQAHAAgJEAQCTgBLAQAAAA==.',
Me='Megami:BAAALgADCgEJAgAAAA==.',
Mi='Missmolt:BAAALgAECgUJCQAAAA==.',
Mo='Molting:BAAALgAECgMJBAAAAA==.',
My='Mykara:BAAALgADCgEJAQAAAA==.Mylor:BAABLgAECn8XAAMMAAgJBAzaNgCgAQAMAAgJBAzaNgCgAQAOAAEJvw/KSAEwAAAAAA==.Myrddral:BAAALgAECgUJCQAAAA==.Mystifeyed:BAABLgAECn8WAAMRAAgJcAqLFgBQAQARAAcJYgmLFgBQAQASAAIJcAs/DABTAAAAAA==.',
['Mü']='Mürsaat:BAAALgAECgUJCQAAAA==.',
Na='Namrekcah:BAAALgADCgcJDgABLgAFFAYJFQATAPYdAA==.Narra:BAAALgADCggJAwAAAA==.',
Ne='Nebalicious:BAAALgADCgcJDAABLgAECgYJDQACAAAAAA==.Nekonomiya:BAAALgADCgMJAwAAAA==.',
Ni='Nightlevels:BAABLgAECn8cAAMUAAcJPCMlAgBNAgAUAAcJnSIlAgBNAgAVAAEJFCLucgBcAAAAAA==.Nimbledragon:BAAALgADCggJCgAAAA==.',
Nt='Ntayu:BAAALgAECgUJCQAAAA==.',
Ol='Olizia:BAABLgAECn8VAAILAAcJgxKXdQCaAQALAAcJgxKXdQCaAQAAAA==.',
On='Onaga:BAAALgAECgEJAQAAAA==.',
Op='Opex:BAABLgAECn8WAAMBAAcJdQ6lSACQAQABAAcJdQ6lSACQAQAWAAEJUQBomwATAAAAAA==.Opheliabutts:BAAALgAECgQJBgAAAA==.',
Or='Oril:BAAALgAECggJDgAAAA==.',
Pa='Paw:BAAALgADCgEJAQAAAA==.',
Pe='Penjei:BAAALgADCgYJBgAAAA==.',
Ph='Philomel:BAABLgAECn8bAAIFAAgJLBvMKwBPAgAFAAgJLBvMKwBPAgABLgAECgkJFwAGAHEeAA==.',
Pi='Pixamoo:BAAALgADCgQJBAAAAA==.',
Pl='Planeswalker:BAAALgADCgYJBgAAAA==.',
Po='Podnuh:BAAALgADCgIJAgAAAA==.Poxic:BAAALgADCgQJBAAAAA==.',
Pr='Pritt:BAAALgADCgcJDQABLgAECgYJDAACAAAAAA==.',
Qu='Quazu:BAAALgADCgEJAQAAAA==.',
Ra='Radagahst:BAAALgAECgMJBQAAAA==.Rarngorm:BAAALgAECgQJBwAAAA==.Ravinar:BAAALgAECgUJDAAAAA==.',
Re='Reardain:BAAALgAECgMJCAAAAA==.Received:BAAALgADCggJCAAAAA==.Relia:BAABLgAECn8UAAIXAAgJLw/AIQDJAQAXAAgJLw/AIQDJAQAAAA==.',
Ri='Richardparkr:BAAALgAECgEJAQAAAA==.Riverwind:BAAALgAECgQJBQAAAA==.',
Rj='Rj:BAAALgADCgMJAwAAAA==.',
Ro='Romulus:BAAALgAECgIJAgAAAA==.',
Sa='Safyra:BAAALgADCgYJCAAAAA==.Salana:BAAALgADCgQJBwAAAA==.Santofrancis:BAAALgAECgYJDgAAAA==.Save:BAAALgADCgYJBgABLgAECggJGgAVAIgfAA==.',
Se='Seraie:BAAALgAECgcJCQAAAA==.',
Sh='Shadethrower:BAABLgAECn8VAAIVAAgJFR2bCwCXAgAVAAgJFR2bCwCXAgAAAA==.Shallbedo:BAAALgAECgQJCAAAAA==.Shallvoker:BAABLgAECn8ZAAMJAAgJiRXpCgAtAgAJAAgJiRXpCgAtAgAIAAEJoRQXXwA+AAAAAA==.Shazammy:BAAALgADCgMJBAAAAA==.',
Si='Siatraler:BAAALgAECgYJDAAAAA==.Sigarette:BAACLgAFFH8VAAITAAYJ9h3uAACVAQATAAYJ9h3uAACVAQAuAAQKfy4AAhMACAm5JIcAAL8CABMACAm5JIcAAL8CAAAA.Silverspoon:BAAALgAECgIJAgAAAA==.Sinardi:BAAALgAECgYJDgAAAA==.',
Sk='Skubasteve:BAAALgAECgYJDwAAAA==.Skydragon:BAAALgADCgcJBwAAAA==.Skylock:BAAALgAECgYJBgAAAA==.Skymane:BAAALgAECgYJEQAAAA==.',
So='Solar:BAAALgAFFAMJAwAAAA==.Sovo:BAACLgAFFH8LAAIGAAQJ6BlUBQB2AQAGAAQJ6BlUBQB2AQAuAAQKfyMAAgYACAk6I5IdAP8CAAYACAk6I5IdAP8CAAAA.',
Sq='Squshmepure:BAAALgAECgEJAQAAAA==.',
St='Starrin:BAAALgAECgMJCAAAAA==.Steaknquake:BAABLgAECn8UAAIHAAYJ6xv9CAC1AQAHAAYJ6xv9CAC1AQAAAA==.',
Su='Sunflower:BAAALgAECgQJBwAAAA==.',
Sv='Svaha:BAAALgAECgIJAgAAAA==.',
Sy='Sybri:BAABLgAECn8WAAMBAAgJ2xgeOQDKAQABAAcJKhoeOQDKAQAWAAUJ6wsRWQDhAAAAAA==.Sylvandel:BAAALgAECgUJCQAAAA==.',
Ta='Talthis:BAAALgAECgIJAgAAAA==.',
Te='Teagen:BAABLgAECn8cAAIKAAcJcAaFHADSAAAKAAcJcAaFHADSAAAAAA==.',
Th='Thalius:BAAALgAECgUJCQAAAA==.Thorandaal:BAAALgADCgcJBwAAAA==.',
Ti='Tisbish:BAAALgADCgIJAgAAAA==.',
To='Tometv:BAAALgAECgcJBgABLgAECgcJDAACAAAAAA==.Toomanydeths:BAABLgAECn8cAAMTAAcJLg5PCgDcAAATAAcJLg5PCgDcAAALAAEJqAhpIgExAAAAAA==.',
Tr='Trunx:BAAALgAECgEJAQABLgAECggJFwAYAO8kAA==.',
Ty='Tye:BAAALgAECgMJBgAAAA==.Tyyle:BAAALgADCgYJBgAAAA==.',
['Tá']='Tálos:BAAALgAECgEJAgAAAA==.',
Ul='Uldear:BAAALgADCgYJCwAAAA==.',
Ur='Ursusmanny:BAAALgAECgMJAwAAAA==.',
Va='Vandarin:BAAALgADCgYJDAABLgAECgEJAQACAAAAAA==.Vanthrall:BAAALgAECgQJCgAAAA==.Vayce:BAABLgAECn8cAAMZAAcJJSNbAQDNAQAaAAYJXSMBGQA9AgAZAAcJiR5bAQDNAQAAAA==.',
Ve='Velysa:BAAALgAECgYJCwAAAA==.',
Vi='Vizago:BAAALgADCgEJAQAAAA==.',
Vo='Vogekth:BAAALgAECgUJCwAAAA==.',
['Vÿ']='Vÿktor:BAAALgADCgYJBgAAAA==.',
Wa='Warseeker:BAABLgAECn8VAAMHAAkJKyAkCADzAgAHAAkJKyAkCADzAgAbAAEJnhKLJgA4AAAAAA==.',
We='Weatherworn:BAAALgAECgUJCwAAAA==.',
Xe='Xemu:BAAALgAECgQJBAAAAA==.Xenferos:BAAALgADCgcJDAABLgAECgYJDQACAAAAAA==.',
Xi='Xiro:BAAALgAECgUJCgAAAA==.',
Yo='Yoril:BAAALgADCgQJBAAAAA==.',
Za='Zagiroth:BAABLgAECn8cAAMFAAcJDx+BDACwAQAFAAcJDx+BDACwAQAcAAEJFhtjJwBLAAAAAA==.Zalthanos:BAAALgADCgEJAQAAAA==.Zarack:BAAALgADCgYJBAABLgAECgEJAQACAAAAAA==.',
Ze='Zebraman:BAAALgAECgYJCAAAAA==.Zeraida:BAAALgADCgYJBgAAAA==.',
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

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

local lookup = {'Druid-Restoration','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Frost','Priest-Shadow','Priest-Discipline','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','Warrior-Protection','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aanx:BAAALgAECgYJEgAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAECgkJGQABAMQaAA==.Abdorei:BAAALgAECgYJEQAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8UAAICAAcJIh0oHgBRAgACAAcJIh0oHgBRAgABLgAECggJCQADAAAAAA==.Accilatim:BAAALgAECggJCQAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwADAAAAAA==.',
Ag='Agrromagnet:BAABLgAECn8fAAIEAAgJfBlTNgBJAgAEAAgJfBlTNgBJAgAAAA==.',
Ai='Aiba:BAAALgAECggJEQAAAA==.',
Ak='Akcloud:BAAALgAFFAEJAgAAAA==.',
Al='Alaeris:BAABLgAECn8YAAIFAAgJTx5VCgAHAgAFAAgJTx5VCgAHAgAAAA==.Albetabeef:BAAALgAFFAMJBAAAAA==.Aleyeah:BAAALgAECgIJBAABLgAECggJIAAGAEwbAA==.Allhopeisded:BAAALgAECgYJEgAAAA==.',
Am='Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn8hAAIHAAgJ7As7IgBVAQAHAAgJ7As7IgBVAQAAAA==.',
An='Andii:BAABLgAECn8UAAQIAAgJcRJ+PwB6AQAIAAcJthB+PwB6AQAEAAIJtAeW0gAzAAAJAAEJAACdLwAAAAAAAA==.Andy:BAAALgAECggJDQAAAA==.Angusbeef:BAAALgADCgQJBAAAAA==.',
Ao='Aoibhoker:BAAALgADCgcJDQABLgAECggJIQAKAE8fAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFgALANQVAA==.Ardeno:BAABLgAECn8WAAMLAAYJ1BWuIwA7AQALAAYJbwyuIwA7AQAMAAUJvxWtQQAsAQAAAA==.Ardon:BAABLgAECn8WAAMHAAgJdg9kFwCrAQAHAAgJdg9kFwCrAQAGAAUJvRsaMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.Artémîs:BAAALgAECgEJAQAAAA==.',
As='Asteruis:BAABLgAECn8dAAICAAcJeh3pFgDaAQACAAcJeh3pFgDaAQAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH8aAAIIAAYJ0RHoAwC+AQAIAAYJ0RHoAwC+AQAuAAQKfy8AAwgACQl1H7QIAOMCAAgACQl1H7QIAOMCAAQAAQm4AeZYASYAAAAA.Barkendremix:BAABLgAECn8dAAINAAgJuxC0DgCkAQANAAgJuxC0DgCkAQAAAA==.Bathsheber:BAAALgAECgIJAgAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8UAAIOAAYJMw0pGQDvAAAOAAYJMw0pGQDvAAAAAA==.',
Bj='Bjorum:BAABLgAECn8cAAMKAAgJJSJgAgBLAgAKAAgJJSJgAgBLAgAGAAEJ4QiykAAnAAAAAA==.',
Bo='Bodytwodafa:BAABLgAECn8aAAMPAAgJ7CAXBgCVAgAPAAgJIB4XBgCVAgAQAAcJZBjbDAC7AQAAAA==.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAAALgAECgUJCwAAAA==.',
Ca='Cantarella:BAAALgAECgYJCgAAAA==.Carlyle:BAABLgAECn8VAAMEAAcJnhPdbwCdAQAEAAcJnhPdbwCdAQAIAAEJPx04RgBRAAAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEgAAAA==.Convik:BAAALgAECgcJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIRAAcJ+hN6EgCkAQARAAcJ+hN6EgCkAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8bAAIEAAcJGRbacgCWAQAEAAcJGRbacgCWAQAAAA==.',
De='Dekaar:BAAALgAECgYJDgAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgMJAwAAAA==.Desdemonica:BAAALgAECgUJDgAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCgYJBgAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8pAAISAAkJ/BNmCAAkAgASAAkJ/BNmCAAkAgAAAA==.Domain:BAAALgAECgcJEQAAAA==.Donfalprun:BAABLgAECn8XAAIEAAcJaSN1DgBNAgAEAAcJaSN1DgBNAgAAAA==.Doomstout:BAAALgAECgcJDwAAAA==.',
Dr='Draconus:BAABLgAECn8bAAMTAAcJjBJyIQA3AQATAAcJPBByIQA3AQAUAAMJdxwxewCmAAAAAA==.Dralas:BAAALgAECgEJAgAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAADAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJBQADAAAAAA==.Duskshade:BAAALgADCggJDwAAAA==.',
['Dü']='Düsk:BAAALgADCgkJEgAAAA==.',
El='Elij:BAABLgAECn8XAAIMAAgJPhR7PQAWAgAMAAgJPhR7PQAWAgAAAA==.Elunaire:BAABLgAECn8ZAAIBAAkJxBqTHQBRAgABAAkJxBqTHQBRAgAAAA==.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAABLgAECn8aAAIBAAgJpSNuBgAlAwABAAgJpSNuBgAlAwAAAA==.',
Er='Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAAALgAECgYJEQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8PAAMVAAQJPw++BABCAQAVAAQJ4A2+BABCAQARAAMJIAzKEgDvAAAuAAQKfyAAAxUACQnAG3kGAGQCABUACQmMGnkGAGQCABEABglLHFk1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.',
Fe='Fey:BAABLgAECn8iAAIMAAkJ3hOkFAAAAgAMAAkJ3hOkFAAAAgAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECgUJBQADAAAAAA==.Fistvendor:BAAALgAECgMJBAAAAA==.',
Fl='Flasheals:BAABLgAECn8hAAIIAAcJoBPKFwCRAQAIAAcJoBPKFwCRAQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fr='Frostine:BAAALgAECgcJEgAAAA==.Frostwave:BAABLgAECn8gAAMWAAgJ+BxhBAAcAgAWAAYJUSBhBAAcAgATAAgJYBCiDQA2AQAAAA==.',
Fu='Fujiyama:BAABLgAECn8gAAIGAAgJTBtlCQAGAgAGAAgJTBtlCQAGAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQACAL8WAA==.Garréosh:BAAALgAECgQJCAAAAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJBgAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgYJDQADAAAAAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8cAAMQAAgJnQhvGAA6AQAQAAgJbAhvGAA6AQAPAAUJxAMsKwDDAAAAAA==.',
Ha='Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJBgAAAA==.Heatindabs:BAABLgAECn8bAAIBAAcJzA9+MAAaAQABAAcJzA9+MAAaAQAAAA==.Hexed:BAAALgAECgIJAwAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgQJAwAAAA==.Holymama:BAABLgAECn8fAAMXAAgJJx1fBQBDAgAXAAcJFCBfBQBDAgAYAAIJIxPsKQB7AAAAAA==.',
Hu='Hunkwai:BAAALgAECgQJCAAAAA==.',
Ib='Ibok:BAAALgAECgQJBAAAAA==.',
Ic='Ickma:BAABLgAECn8hAAIUAAgJcx5QEAA7AgAUAAgJcx5QEAA7AgAAAA==.',
Id='Iddou:BAAALgAECgMJAwAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCggJCgAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgADCgYJCgAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCAAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgUJCgAAAA==.',
Je='Jerazia:BAAALgAECgQJBAAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgADCgEJAQAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAgAAAA==.',
Ka='Kaalli:BAAALgADCgMJBgAAAA==.Kaollanna:BAABLgAECn8jAAIZAAkJDRbXHgDzAQAZAAkJDRbXHgDzAQAAAA==.Karik:BAAALgADCgkJFgAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAABLgAECn8WAAIEAAcJZhq/JgCoAQAEAAcJZhq/JgCoAQAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJAwAAAA==.Kinkster:BAAALgAECgUJBQABLgAECgYJDQADAAAAAA==.Kiwidin:BAABLgAECn8WAAIIAAgJARbkJgDzAQAIAAgJARbkJgDzAQAAAA==.',
Kr='Krinxy:BAAALgAECgUJEgAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJBQAAAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgIJAgABLgAECgUJBQADAAAAAA==.',
Le='Ledgerfeign:BAAALgAECggJEAAAAA==.',
Li='Liadan:BAAALgAECgYJCgAAAA==.Lighteye:BAABLgAECn8hAAIBAAgJzRJnFwDGAQABAAgJzRJnFwDGAQAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCAAAAA==.',
Ly='Lyllow:BAAALgAECgYJEgAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAABLgAECn8mAAIZAAgJ4CAYCgCdAgAZAAgJ4CAYCgCdAgAAAA==.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.',
Mc='Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAABLgAECn8ZAAMaAAgJTBE2HACKAQAbAAgJyAtmHgDMAQAaAAgJVhA2HACKAQAAAA==.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAAALgAECgUJEgAAAA==.',
My='Mylianne:BAAALgAECgYJEgAAAA==.Mynameiscole:BAACLgAFFH8IAAIbAAQJgx97AQCSAQAbAAQJgx97AQCSAQAuAAQKfyIAAhsACAmYJq0BAIkDABsACAmYJq0BAIkDAAAA.Myrolan:BAABLgAECn8jAAIbAAgJUyOXAQDDAgAbAAgJUyOXAQDDAgAAAA==.Myrtru:BAAALgADCgkJFwAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAECgkJFAAEAE4fAA==.Nevyn:BAAALgAECgYJEwAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgQJBAAAAA==.Niji:BAAALgAECgEJAgABLgAECggJEQADAAAAAA==.Nininhp:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.Nithari:BAABLgAECn8fAAIZAAcJiCAmGAAcAgAZAAcJiCAmGAAcAgAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8aAAIYAAcJoBRJDwCYAQAYAAcJoBRJDwCYAQAAAA==.Now:BAABLgAECn8ZAAMEAAgJjR/hLQBrAgAEAAgJzB3hLQBrAgAJAAYJfRexCgBXAQAAAA==.',
Nu='Nukum:BAAALgAECgQJCgAAAA==.',
Oh='Ohpa:BAAALgAECgcJDgAAAA==.Ohrly:BAAALgADCgYJBgAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIcAAgJvSKkAwD2AgAcAAgJvSKkAwD2AgAAAA==.',
Pa='Papamush:BAAALgAECgMJBAAAAA==.Pathogenn:BAAALgAECgYJCgAAAA==.',
Pe='Pepecry:BAAALgAECgQJBgABLgAECgUJBQADAAAAAA==.',
Ph='Phoblade:BAAALgAECggJCwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Ponylion:BAAALgAECgYJCwAAAA==.Pooshka:BAABLgAECn8dAAIGAAkJRiJfCgDvAgAGAAkJRiJfCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8PAAIOAAQJvyZ5AADQAQAOAAQJvyZ5AADQAQAuAAQKfyQAAw4ACAlpJpYAAIoDAA4ACAlpJpYAAIoDAB0AAQm/JGB7AFUAAAAA.Presibro:BAAALgAECgYJBwAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgUJDgAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAAALgAFFAEJAQAAAA==.',
Ra='Ranouu:BAAALgAECgYJEwAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECggJIQAKAE8fAA==.Recision:BAABLgAECn8hAAIeAAgJmiCJAQBeAgAeAAgJmiCJAQBeAgAAAA==.Reeash:BAAALgAECgcJEAAAAA==.Reeatar:BAAALgAECgYJEwABLgAECgcJEAADAAAAAA==.Relindor:BAAALgADCgYJBgABLgAECgkJLQAUAOIfAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8ZAAIfAAYJgg0lFADsAAAfAAYJgg0lFADsAAAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAAALgAFFAEJAQAAAA==.',
Ru='Rumnstuff:BAAALgADCgIJAgAAAA==.Runcat:BAAALgAECggJEQAAAA==.',
['Rö']='Röyksopp:BAAALgAECgcJCQAAAA==.',
Sa='Sabo:BAAALgADCgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Samarah:BAAALgAECgEJAQAAAA==.Sandewor:BAAALgAECgYJBgABLgAECgYJDAADAAAAAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgADAAAAAA==.Sarafyn:BAABLgAECn8fAAISAAcJKRfyEgCBAQASAAcJKRfyEgCBAQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAQJCAAbAIMfAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8VAAIYAAcJXxudCQD2AQAYAAcJXxudCQD2AQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegrorc:BAABLgAECn8ZAAIfAAcJhwuGEgAAAQAfAAcJhwuGEgAAAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAAALgAECgYJDAAAAA==.Slayertin:BAAALgAECgYJAgABLgAECgYJDAADAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAAALgAECgYJEgAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgQJBAAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgADCggJDgAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
St='Steady:BAAALgAFFAEJAQAAAA==.Stonehand:BAAALgAECgkJEgAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgADCggJDgAAAA==.',
Su='Subudai:BAAALgAECggJDgAAAA==.Sugarboi:BAABLgAECn8cAAIgAAgJFwhTEAC0AAAgAAgJFwhTEAC0AAAAAA==.Sugasuga:BAAALgAECgEJAwAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgMJAwAAAA==.Tacoy:BAABLgAECn8UAAIRAAgJ+BR3NwDKAQARAAgJ+BR3NwDKAQAAAA==.Tagsy:BAABLgAECn8VAAICAAgJvxb+HQCsAQACAAgJvxb+HQCsAQAAAA==.Tay:BAAALgAECgUJBQAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn8hAAILAAgJpg17BQBvAQALAAgJpg17BQBvAQAAAA==.',
Th='Then:BAABLgAECn8dAAIZAAYJnBqaQwBkAQAZAAYJnBqaQwBkAQAAAA==.Threetimez:BAAALgAECgIJAgAAAA==.Thumbmage:BAAALgADCgcJBgAAAA==.',
Ti='Timemaster:BAABLgAECn8TAAMbAAYJ5g+5EgAaAQAbAAYJ5g+5EgAaAQAaAAIJnQP91gBCAAAAAA==.Timepacifist:BAAALgAECgQJBAAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAAALgAECgMJEQAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8YAAMEAAcJtxeYUQDsAQAEAAcJtxeYUQDsAQAIAAEJ0AqZngAqAAAAAA==.Troiikâ:BAABLgAECn8nAAMJAAkJnRQEEADFAQAJAAkJnRQEEADFAQAEAAYJ1wOCywDyAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8UAAIfAAgJtQw5EwD4AAAfAAgJtQw5EwD4AAAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgQJBAADAAAAAA==.Ttevoker:BAAALgAECgQJBAAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAAALgAECgYJDgAAAA==.',
Ur='Urukdrak:BAABLgAECn8jAAMOAAgJKA7vCwCfAQAOAAgJDwrvCwCfAQAdAAgJhA3gCwAQAQAAAA==.',
Uw='Uwantwar:BAAALgAECgUJBwAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAECgMJAwAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAAALgAECgcJDgAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAQAAAA==.',
Wu='Wunderbar:BAABLgAECn8aAAIHAAYJvBPqQwByAQAHAAYJvBPqQwByAQAAAA==.Wunderburger:BAAALgAECgYJEAAAAA==.Wunderground:BAAALgAECgEJAQAAAA==.',
Xa='Xannada:BAABLgAECn8dAAIEAAgJGAngPgBNAQAEAAgJGAngPgBNAQAAAA==.',
Ya='Yaoli:BAAALgAECgEJAgAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8KAAIXAAYJkQp4IgDnAAAXAAYJkQp4IgDnAAAAAA==.Yoh:BAABLgAECn8aAAIUAAgJxhrHFAAUAgAUAAgJxhrHFAAUAgAAAA==.Yourenotron:BAAALgADCgYJBgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJDgABLgAECggJEQADAAAAAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8cAAINAAgJaBByEACOAQANAAgJaBByEACOAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
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

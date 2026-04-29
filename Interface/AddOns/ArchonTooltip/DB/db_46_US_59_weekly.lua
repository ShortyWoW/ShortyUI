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

local lookup = {'Druid-Restoration','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Monk-Brewmaster','Warrior-Fury','Priest-Holy','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','DeathKnight-Unholy','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Warrior-Protection','Druid-Guardian','Paladin-Protection',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aanx:BAAALgAECgYJEgAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAECggJGAABANoZAA==.Abdorei:BAAALgAECgYJCwAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8UAAICAAcJIh0sHgBRAgACAAcJIh0sHgBRAgAAAA==.Accilatim:BAAALgAECgYJBgABLgAECgcJFAACACIdAA==.',
Ad='Adonsina:BAAALgAECgEJAQAAAA==.',
Ag='Agrromagnet:BAABLgAECn8fAAIDAAgJfBlcNgBJAgADAAgJfBlcNgBJAgAAAA==.',
Ai='Aiba:BAAALgAECgYJCAABLgAECgYJCwAEAAAAAA==.',
Ak='Akcloud:BAAALgAFFAEJAgAAAA==.',
Al='Alaeris:BAABLgAECn8YAAIFAAgJTx6OAwASAgAFAAgJTx6OAwASAgAAAA==.Albetabeef:BAAALgAFFAIJAgAAAA==.Aleyeah:BAAALgAECgIJBAABLgAECgcJHAAGADMeAA==.Allhopeisded:BAAALgAECgYJDwAAAA==.',
Am='Amarah:BAAALgADCgMJAwAAAA==.Amelaista:BAABLgAECn8ZAAIHAAcJ9QxUDwBMAQAHAAcJ9QxUDwBMAQAAAA==.',
An='Andii:BAAALgAFFAEJAgAAAA==.Angusbeef:BAAALgADCgQJBAAAAA==.',
Ao='Aoibhoker:BAAALgADCgcJCwABLgAECgcJGQAIAOAeAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFgAJANQVAA==.Ardeno:BAABLgAECn8WAAMJAAYJ1BWtIwA7AQAJAAYJbwytIwA7AQAKAAUJvxW3GwA6AQAAAA==.Ardon:BAAALgAECggJDgAAAA==.Armis:BAAALgADCgUJBQAAAA==.Artémîs:BAAALgAECgEJAQAAAA==.',
As='Asteruis:BAABLgAECn8aAAICAAcJ2BxyDACoAQACAAcJ2BxyDACoAQAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH8UAAILAAUJOBJbBQCHAQALAAUJOBJbBQCHAQAuAAQKfyoAAwsACQl1H7gIAOMCAAsACQl1H7gIAOMCAAMAAQm4AcRYASYAAAAA.Barkendremix:BAABLgAECn8aAAIMAAcJAxG6DAAlAQAMAAcJAxG6DAAlAQAAAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAAALgAECgUJDwAAAA==.',
Bj='Bjorum:BAABLgAECn8cAAMIAAgJJSLnAABQAgAIAAgJJSLnAABQAgAGAAEJ4QiikAAnAAAAAA==.',
Bo='Bodytwodafa:BAAALgAFFAEJAgAAAA==.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJBgAAAA==.',
Bu='Bubbleyou:BAAALgAECgQJBgAAAA==.',
Ca='Cantarella:BAAALgAECgMJBAAAAA==.Carlyle:BAAALgAECgcJEwAAAA==.Cascade:BAAALgADCgEJAQAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJAQAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJDQAAAA==.Convik:BAAALgAECgcJBgAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAINAAcJ+hOUBwCoAQANAAcJ+hOUBwCoAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8aAAIDAAYJLBodHgA6AQADAAYJLBodHgA6AQAAAA==.',
De='Dekaar:BAAALgAECgUJCAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgADCgkJGQAAAA==.Desdemonica:BAAALgAECgUJCwAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8gAAIOAAgJjRTkBADgAQAOAAgJjRTkBADgAQAAAA==.Domain:BAAALgAECgYJDgAAAA==.Donfalprun:BAABLgAECn8WAAIDAAcJaSOYBABVAgADAAcJaSOYBABVAgAAAA==.Doomstout:BAAALgAECgcJDwAAAA==.',
Dr='Draconus:BAABLgAECn8UAAIPAAYJghHoLQDQAAAPAAYJghHoLQDQAAAAAA==.Dralas:BAAALgAECgEJAQAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAEAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJBQAEAAAAAA==.Duskshade:BAAALgADCgcJCgAAAA==.',
['Dü']='Düsk:BAAALgADCgkJEAAAAA==.',
El='Elij:BAABLgAECn8XAAIKAAgJPhR+PQAWAgAKAAgJPhR+PQAWAgAAAA==.Elunaire:BAABLgAECn8YAAIBAAgJ2hmSHQBRAgABAAgJ2hmSHQBRAgAAAA==.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAAALgAFFAEJAgAAAA==.',
Er='Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAAALgAECgYJEQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8LAAMNAAQJcgzEEgDvAAANAAMJIAzEEgDvAAAQAAIJNAwmBACMAAAuAAQKfxwAAxAACAlGHngGAGQCABAABwnnHHgGAGQCAA0ABglLHFk1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.',
Fe='Fey:BAABLgAECn8aAAIKAAgJPxMHQgAHAgAKAAgJPxMHQgAHAgAAAA==.',
Fi='Fieryember:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Fistvendor:BAAALgAECgEJAQAAAA==.',
Fl='Flasheals:BAABLgAECn8bAAILAAcJrxEGDAB/AQALAAcJrxEGDAB/AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fr='Frostine:BAAALgAECgcJDgAAAA==.Frostwave:BAABLgAECn8YAAIRAAYJUSCiAQCXAQARAAYJUSCiAQCXAQAAAA==.',
Fu='Fujiyama:BAABLgAECn8cAAIGAAcJMx6bBQC8AQAGAAcJMx6bBQC8AQAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQACAL8WAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJAwAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.',
Gu='Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8aAAMSAAgJWwfMCgA5AQASAAgJIwfMCgA5AQATAAUJxAMnKwDDAAAAAA==.',
Ha='Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJBgAAAA==.Heatindabs:BAABLgAECn8YAAIBAAcJnQ+HFQAZAQABAAcJnQ+HFQAZAQAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgQJAwAAAA==.Holymama:BAABLgAECn8XAAIUAAcJTx9jAwAAAgAUAAcJTx9jAwAAAgAAAA==.',
Hu='Hunkwai:BAAALgAECgQJBwAAAA==.',
Ib='Ibok:BAAALgAECgQJBAAAAA==.',
Ic='Ickma:BAABLgAECn8ZAAIVAAcJAx9fCgDYAQAVAAcJAx9fCgDYAQAAAA==.',
Ik='Ikona:BAAALgADCgcJDQAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCgMJBQAAAA==.',
In='Incubus:BAAALgADCgEJAQAAAA==.Infari:BAAALgADCgYJBgAAAA==.',
Ja='Jabjek:BAAALgADCgYJCAAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgUJCgAAAA==.',
Je='Jerazia:BAAALgAECgQJBAAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgADCgEJAQAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAQAAAA==.',
Ka='Kaalli:BAAALgADCgMJBAAAAA==.Kaollanna:BAABLgAECn8bAAIWAAgJmRYlWQAuAgAWAAgJmRYlWQAuAgAAAA==.Karik:BAAALgADCgkJFgAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAAALgAECgYJDwAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJAwAAAA==.Kiwidin:BAABLgAECn8VAAILAAgJARbjJgDzAQALAAgJARbjJgDzAQAAAA==.',
Kr='Krinxy:BAAALgAECgUJEAAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJBQAAAA==.',
Ky='Kyý:BAAALgAECgYJDwAAAA==.',
Le='Ledgerfeign:BAAALgAECgcJDgAAAA==.',
Li='Liadan:BAAALgAECgQJBAAAAA==.Lighteye:BAABLgAECn8ZAAIBAAcJsw9EEgA7AQABAAcJsw9EEgA7AQAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJDwAEAAAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJBwAAAA==.',
Ly='Lyllow:BAAALgAECgYJDAAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAABLgAECn8dAAIWAAgJFh8oDgDXAQAWAAgJFh8oDgDXAQAAAA==.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.',
Mc='Mcsleuth:BAAALgAECgQJBQAAAA==.',
Me='Megarayquaza:BAAALgAECggJDAAAAA==.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAAALgAECgUJDgAAAA==.',
My='Mylianne:BAAALgAECgYJDAAAAA==.Mynameiscole:BAACLgAFFH8IAAIXAAQJgx90AQCSAQAXAAQJgx90AQCSAQAuAAQKfyAAAhcACAk7JqsBAIoDABcACAk7JqsBAIoDAAAA.Myrolan:BAABLgAECn8gAAIXAAgJ1iIrAQBSAgAXAAgJ1iIrAQBSAgAAAA==.Myrtru:BAAALgADCgkJEwAAAA==.',
['Mí']='Míyagi:BAAALgAECgUJBQAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAECgkJFAADAE4fAA==.Nevyn:BAAALgAECgUJDgAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgQJBAAAAA==.Niji:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Nininhp:BAAALgAECgIJAgABLgAECgQJBwAEAAAAAA==.Nithari:BAABLgAECn8ZAAIWAAcJ6R/cDQDbAQAWAAcJ6R/cDQDbAQAAAA==.',
No='Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgADCgkJEAAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8XAAIYAAcJoBQEBgCjAQAYAAcJoBQEBgCjAQAAAA==.Now:BAAALgAFFAEJAgAAAA==.',
Nu='Nukum:BAAALgAECgMJBgAAAA==.',
Oh='Ohpa:BAAALgAECgQJBAAAAA==.Ohrly:BAAALgADCgYJBgAAAA==.',
Oj='Ojikan:BAAALgAFFAEJAQAAAA==.',
Pa='Papamush:BAAALgAECgMJBAAAAA==.Pathogenn:BAAALgAECgYJCgAAAA==.',
Pe='Pepecry:BAAALgAECgQJBgABLgAECgUJBQAEAAAAAA==.',
Ph='Phoblade:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Ponylion:BAAALgAECgYJCwABLgAECgcJDQAEAAAAAA==.Pooshka:BAABLgAECn8cAAIGAAgJWiJbCgDvAgAGAAgJWiJbCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8LAAIZAAQJiiYjAADBAQAZAAQJiiYjAADBAQAuAAQKfx8AAxkACAleJpcAAIoDABkACAleJpcAAIoDABoAAQm/JFx7AFUAAAAA.Presibro:BAAALgAECgYJBgAAAA==.Presiric:BAAALgADCgYJBgAAAA==.Presisarian:BAAALgAECgUJDQAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAAALgAFFAEJAQAAAA==.',
Ra='Ranouu:BAAALgAECgYJDQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgcJGQAIAOAeAA==.Recision:BAABLgAECn8ZAAIbAAcJXR73AQCsAQAbAAcJXR73AQCsAQAAAA==.Reeash:BAAALgAECgcJDgAAAA==.Reeatar:BAAALgAECgYJEgABLgAECgcJDgAEAAAAAA==.Relindor:BAAALgADCgYJBgABLgAECgkJKgAVAI8fAA==.Revelle:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Rh='Rheizen:BAAALgAECgYJEgAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAAALgAFFAEJAQAAAA==.',
Ru='Runcat:BAAALgAECgMJBAAAAA==.',
['Rö']='Röyksopp:BAAALgAECgIJAgAAAA==.',
Sa='Sabo:BAAALgADCgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Samarah:BAAALgAECgEJAQAAAA==.Sandewor:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAEAAAAAA==.Sarafyn:BAABLgAECn8ZAAIOAAcJPhZzCAB5AQAOAAcJPhZzCAB5AQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgADCgcJDAABLgAFFAQJCAAXAIMfAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAAALgAECgcJEQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Sh='Shäpeshíft:BAAALgADCgQJBgAAAA==.',
Si='Siegrorc:BAABLgAECn8ZAAIcAAcJhwtsCAAHAQAcAAcJhwtsCAAHAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sl='Slayerhunt:BAAALgAECgYJDAAAAA==.Slayertin:BAAALgAECgYJAgABLgAECgYJDAAEAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAAALgAECgYJDQAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgQJBAAAAA==.Soulkings:BAAALgADCgcJBwAAAA==.Soupies:BAAALgADCggJCAAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
St='Steady:BAAALgAECgUJDgAAAA==.Stonehand:BAAALgAECgkJCQAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgADCggJDgAAAA==.',
Su='Subudai:BAAALgAECgcJDAAAAA==.Sugarboi:BAABLgAECn8UAAIdAAcJ1QjKHAC+AAAdAAcJ1QjKHAC+AAAAAA==.Sugasuga:BAAALgAECgEJAwAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tacoy:BAAALgAECgYJEgAAAA==.Tagsy:BAABLgAECn8VAAICAAgJvxa7CgC+AQACAAgJvxa7CgC+AQAAAA==.Tay:BAAALgAECgUJBQAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn8ZAAIJAAcJ0wvyAwAjAQAJAAcJ0wvyAwAjAQAAAA==.',
Th='Then:BAABLgAECn8aAAIWAAYJCxhrLQAVAQAWAAYJCxhrLQAVAQAAAA==.Threetimez:BAAALgADCgYJEAAAAA==.Thumbmage:BAAALgADCgcJBgABLgAECggJIAAGAOAgAA==.',
Ti='Timemaster:BAAALgAECgYJDwAAAA==.Timepacifist:BAAALgAECgQJBAAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAAALgAECgMJCQAAAA==.Topflight:BAAALgAECgcJDwAAAA==.',
Tr='Triggered:BAABLgAECn8YAAMDAAcJtxegUQDsAQADAAcJtxegUQDsAQALAAEJ0AqGngAqAAAAAA==.Troiikâ:BAABLgAECn8kAAMeAAgJpxYAEADFAQAeAAgJpxYAEADFAQADAAYJ1wOAywDyAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAAALgAECgcJDgAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgQJBAAEAAAAAA==.Ttevoker:BAAALgAECgQJBAAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAAALgAECgYJDgAAAA==.',
Ur='Urukdrak:BAABLgAECn8bAAIaAAgJhA1CBgAVAQAaAAgJhA1CBgAVAQAAAA==.',
Uw='Uwantwar:BAAALgAECgQJBAAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAECgIJAgAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Voiddastard:BAAALgADCgkJFwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAAALgAECgcJBAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAQAAAA==.',
Wu='Wunderbar:BAABLgAECn8UAAIHAAYJ2RLtQwByAQAHAAYJ2RLtQwByAQAAAA==.Wunderburger:BAAALgAECgYJDQAAAA==.',
Xa='Xannada:BAABLgAECn8VAAIDAAcJtAfJtAAbAQADAAcJtAfJtAAbAQAAAA==.',
Ya='Yaoli:BAAALgAECgEJAgAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAAALgAECgYJDwAAAA==.Yoh:BAAALgAFFAEJAgAAAA==.Yourenotron:BAAALgADCgYJBgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJCwAAAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAAALgAECggJEwAAAA==.',
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

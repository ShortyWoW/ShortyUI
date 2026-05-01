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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Blood','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Hunter-Survival','DemonHunter-Vengeance','Shaman-Enhancement','Monk-Brewmaster','Druid-Guardian','Warlock-Affliction','Mage-Frost','Evoker-Preservation',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarmorr:BAABLgAECn8dAAIBAAgJshC9GgCNAQABAAgJshC9GgCNAQAAAA==.',
Ab='Absoul:BAAALgADCgEJAQAAAA==.',
Ac='Acinthos:BAAALgADCgkJCQAAAA==.',
Ae='Aeloriá:BAABLgAECn8gAAMCAAgJVhz4MgDdAQACAAgJVhz4MgDdAQADAAEJFQGdOwAPAAAAAA==.Aelyra:BAAALgAECgUJBQAAAA==.',
Ai='Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8UAAIEAAgJCBiwIABBAgAEAAgJCBiwIABBAgAAAA==.Aldera:BAABLgAECn8UAAIBAAgJ7wKTMwDsAAABAAgJ7wKTMwDsAAAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8cAAMFAAgJORvbHwDIAQAFAAgJORvbHwDIAQAGAAEJyhBdFgA3AAAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn8jAAMCAAcJmBANLgAnAQACAAcJmBANLgAnAQAHAAEJgwYFSgAsAAAAAA==.Alorris:BAAALgAECgQJBAABLgAECgYJEQAIAAAAAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgYJCQAAAA==.',
Am='Amata:BAAALgAECgEJAQAAAA==.Ammastary:BAAALgAECgQJBQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgYJEAAIAAAAAA==.Andragos:BAAALgAECgIJAgAAAA==.Andrea:BAABLgAECn8cAAIDAAgJ+BLSBwB6AQADAAgJ+BLSBwB6AQAAAA==.Anthria:BAAALgAECgUJCQAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arilyn:BAAALgADCgUJCgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECggJCAAAAA==.Asyllaa:BAAALgAECgYJDgAAAA==.',
At='Atonement:BAAALgAECgIJBAABLgAECgcJEgAIAAAAAA==.',
Au='Auralynn:BAAALgAECgYJEgAAAA==.',
Av='Averus:BAABLgAECn8dAAIHAAgJKwqaFgBKAQAHAAgJKwqaFgBKAQAAAA==.',
Az='Azariel:BAABLgAECn8eAAIJAAgJPBTuRQASAgAJAAgJPBTuRQASAgAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8YAAIKAAgJNhUSDwDTAQAKAAgJNhUSDwDTAQAAAA==.',
Ba='Baane:BAAALgAECgEJAQABLgAECgIJAgAIAAAAAA==.Babnik:BAEALgAECgYJDQAAAA==.Bagel:BAACLgAFFH8GAAILAAMJ9R1XDgAZAQALAAMJ9R1XDgAZAQAuAAQKfxYAAgsABgnIIU8mAPYBAAsABgnIIU8mAPYBAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgEJAQAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn8dAAMMAAgJYBYGCQADAgAMAAgJjxUGCQADAgANAAMJFBxtVQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAACLgAFFH8GAAIJAAQJ3Q/3GQAQAQAJAAQJ3Q/3GQAQAQAuAAQKfyMAAgkACAniIkMIAJcCAAkACAniIkMIAJcCAAAA.Berathor:BAAALgAECgIJAgAAAA==.Betsea:BAAALgAECgUJBQABLgAECggJIwALAEEOAA==.',
Bi='Bidoof:BAABLgAECn8VAAIOAAYJNAUdGgDLAAAOAAYJNAUdGgDLAAAAAA==.Bigblunt:BAAALgADCgQJBgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgIJBAAAAA==.',
Bo='Boggrog:BAAALgADCggJCAABLgAECgEJAQAIAAAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8VAAIPAAYJ4QXgMAC4AAAPAAYJ4QXgMAC4AAAAAA==.Bowgobrr:BAABLgAECn8mAAMQAAgJJBUfBQCuAQAQAAgJJBUfBQCuAQAEAAYJ2goeYgCiAAAAAA==.',
Br='Braelyne:BAAALgAECgYJDwAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgADCgYJBgAAAA==.',
Bu='Buffsalot:BAAALgAECgQJCQAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn8vAAIJAAkJVh+jBADSAgAJAAkJVh+jBADSAgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgIJAgAAAA==.Castle:BAAALgAECgIJAwAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAECggJKQAFADkUAA==.Catzinhatz:BAAALgAECgcJEAABLgAECggJKQAFADkUAA==.',
Ce='Cecelya:BAABLgAECn8oAAINAAgJ4hkuCQAVAgANAAgJ4hkuCQAVAgAAAA==.Celibate:BAAALgAECgQJBAAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIPAAYJNBCsRQAyAQAPAAYJNBCsRQAyAQABLgAECggJDwAIAAAAAA==.Chivactdl:BAAALgADCgEJAQABLgAECgUJCwAIAAAAAA==.Chozen:BAAALgAECgYJBgAAAA==.Chunknoriss:BAAALgAECgQJBgABLgAECgUJCwAIAAAAAA==.',
Cl='Claudiuss:BAAALgAECgUJBQABLgAECggJJAABAPUYAA==.Clurefu:BAABLgAECn8bAAMRAAgJtB1WCwCcAgARAAgJtB1WCwCcAgASAAMJ5BZMWACuAAAAAA==.Clurelock:BAAALgAECgQJBgABLgAECggJGwARALQdAA==.Cluremage:BAAALgAECgYJBgAAAA==.',
Co='Codenameknd:BAAALgADCgYJCQAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECgYJDQAAAA==.Constella:BAAALgADCgUJBQAAAA==.Coppertan:BAAALgADCggJCwAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAAALgAECgYJEgAAAA==.',
Cr='Crazyshammy:BAAALgAECgYJCgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJBgAAAA==.Crunchynuget:BAAALgAECgIJAwABLgAECgYJCwAIAAAAAA==.',
Ct='Cthuwu:BAAALgADCgcJDgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAQAAAA==.',
Cy='Cybeast:BAABLgAECn8cAAIDAAgJOBsaBgCdAgADAAgJOBsaBgCdAgAAAA==.',
Da='Daciana:BAAALgAECgMJBAAAAA==.Dados:BAABLgAECn8kAAINAAgJ8x6xBwA0AgANAAgJ8x6xBwA0AgAAAA==.Dahleigh:BAAALgADCgQJBQAAAA==.Dakanar:BAAALgADCgkJGAAAAA==.Dambrien:BAAALgAECgEJAQAAAA==.Daravus:BAAALgAECgEJAgAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8cAAIJAAgJxR+vDABgAgAJAAgJxR+vDABgAgAAAA==.Darloct:BAAALgAECgQJBAAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8WAAMTAAcJKBmxMAAgAQAOAAYJexvpJwCDAQATAAcJoQ6xMAAgAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJFgATACgZAA==.Deadslinger:BAAALgADCgEJAQAAAA==.Deathcat:BAABLgAECn8pAAIFAAgJORQYUwD4AQAFAAgJORQYUwD4AQAAAA==.Deathkiss:BAAALgAECgQJBgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8GAAIFAAMJghhuMAABAQAFAAMJghhuMAABAQAAAA==.Deathshadowx:BAAALgAECgEJAQAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgQJBgAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgADCgIJAgABLgAECgcJFwASAJ0ZAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8VAAIUAAYJ4QoRHQAUAQAUAAYJ4QoRHQAUAQAAAA==.',
Do='Dolemite:BAABLgAECn8VAAMRAAUJewy3QgDUAAARAAUJewy3QgDUAAASAAQJJAbtLwCDAAAAAA==.Donalbain:BAABLgAECn8kAAIBAAgJ9RiqCwAwAgABAAgJ9RiqCwAwAgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgADCgUJBQAAAA==.',
Du='Durock:BAAALgAECgEJAQAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
El='Eldinn:BAAALgADCgcJBgAAAA==.Elidor:BAAALgAECgEJAgAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8gAAIVAAgJnxX+FgCnAQAVAAgJnxX+FgCnAQAAAA==.Elzulkin:BAAALgADCgUJBQAAAA==.',
Em='Emmils:BAABLgAECn8lAAIHAAgJowduGQAxAQAHAAgJowduGQAxAQAAAA==.Emìly:BAABLgAECn8cAAMSAAgJ6h5nCQDiAQASAAcJdx9nCQDiAQARAAQJqAvrLwCPAAAAAA==.',
En='Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn8fAAQKAAcJsyFFBQDjAQAJAAcJxB2PNABQAgAKAAYJuiFFBQDjAQALAAMJ0QrMhgBeAAAAAA==.',
Ep='Episkey:BAAALgAECgYJEgAAAA==.',
Er='Ereviss:BAAALgADCgcJBwAAAA==.Erindaglaze:BAAALgADCgQJBQAAAA==.Eropor:BAAALgAECgMJBgABLgAECggJPgACAHIdAA==.Eroversion:BAABLgAECn8+AAQCAAgJch07DQA3AgACAAgJch07DQA3AgAHAAQJNRQyVADVAAADAAMJKAZ5KQB+AAAAAA==.',
Es='Esmay:BAABLgAECn8YAAIPAAcJoA9oIQARAQAPAAcJoA9oIQARAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn8cAAIWAAgJ9gsZBgBVAQAWAAgJ9gsZBgBVAQAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgADCgUJBwAAAA==.',
Fi='Filgulfin:BAABLgAECn8eAAMQAAgJzBRBCwAbAQAQAAgJehBBCwAbAQAEAAQJ7hK+QwAJAQAAAA==.Finkate:BAAALgADCgkJCQAAAA==.Firebad:BAABLgAECn8eAAMXAAgJ3xmmAwCxAQAXAAgJ3xmmAwCxAQAYAAYJHQoqcgClAAAAAA==.Firebringer:BAABLgAECn8fAAITAAgJlgWVQADlAAATAAgJlgWVQADlAAAAAA==.',
Fl='Flamehunter:BAABLgAECn8eAAMTAAkJGxqDHACnAgATAAkJ4RiDHACnAgAOAAcJLRdXJACaAQAAAA==.Flo:BAABLgAECn8hAAIUAAgJoBPyFgBHAQAUAAgJoBPyFgBHAQAAAA==.Floki:BAAALgAECgYJDAAAAA==.',
Fo='Foods:BAABLgAECn8sAAQZAAgJTxNgDABdAQAaAAgJmg8lMQDpAQAZAAcJYxFgDABdAQAbAAIJwwxIMAB1AAAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
Ga='Gaboo:BAAALgAECgYJCgAAAA==.',
Gh='Ghostinhale:BAAALgAECgIJAwAAAA==.',
Gi='Gilorion:BAAALgAECgQJCQAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECggJJAABAPUYAA==.',
Gn='Gnibat:BAAALgADCgkJFQAAAA==.',
Go='Goburina:BAABLgAECn8VAAIBAAkJVwtRPQCMAQABAAkJVwtRPQCMAQAAAA==.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
['Gí']='Gímlí:BAABLgAECn8ZAAIEAAYJrxt5NwDQAQAEAAYJrxt5NwDQAQAAAA==.',
Ha='Halcyndraag:BAABLgAECn8dAAMcAAgJyhHpIQD0AAAcAAYJ2xDpIQD0AAAdAAMJpRWNKADcAAAAAA==.Handbannana:BAAALgADCgYJBgAAAA==.Handsome:BAAALgADCgEJAQABLgAECggJDgAIAAAAAA==.Happydk:BAABLgAECn8hAAMFAAkJxx55BADkAgAFAAkJxx55BADkAgAVAAMJDhVvNgCOAAAAAA==.Hartu:BAABLgAECn8bAAIZAAgJkw+8DQBDAQAZAAgJkw+8DQBDAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBgAAAA==.Hemic:BAABLgAECn8aAAIeAAgJCB6RBABEAgAeAAgJCB6RBABEAgAAAA==.Hemmorage:BAAALgAECgQJBAABLgAECggJHgAFAFMdAA==.Herbalmist:BAAALgAECgEJAQAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Horatio:BAAALgADCgcJBwABLgAECggJJAABAPUYAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECggJJwADAJwYAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Id='Idiocracy:BAAALgADCggJEQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgEJAQAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgEJAQAAAA==.Irys:BAAALgADCgcJDgAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAABLgAECn8SAAIEAAkJSiLnBAA/AwAEAAkJSiLnBAA/AwAAAA==.Ismokeu:BAABLgAECn8iAAINAAgJvRg6BwA9AgANAAgJvRg6BwA9AgAAAA==.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jalidelo:BAABLgAECn8hAAMMAAgJChavEwARAgAMAAgJChavEwARAgANAAEJ5gZahgAqAAAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8VAAIYAAgJQBisLQB1AQAYAAgJQBisLQB1AQAAAA==.Jokers:BAAALgAECgQJBAAAAA==.Joranbragi:BAAALgAECgQJBAAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAAALgAECgYJEAAAAA==.Jotoonice:BAAALgAECgYJEAAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8HAAQfAAQJpg/pBQBEAQAfAAQJGw3pBQBEAQAEAAEJeg6ROQBTAAAQAAEJrQFdLQA8AAAuAAQKfyEABBAACAnFGgYhABsCABAACAnwFQYhABsCAB8AAgkkHgkeALcAAAQAAQlUJcVyAG0AAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.',
['Jú']='Júgg:BAAALgADCgkJCQAAAA==.',
Ka='Kaachow:BAABLgAECn8eAAICAAcJ+CAMCACMAgACAAcJ+CAMCACMAgAAAA==.Kaana:BAABLgAECn8dAAIEAAgJ7A+gKwBlAQAEAAgJ7A+gKwBlAQAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAAALgAECgUJBgAAAA==.Karungash:BAACLgAFFH8IAAMYAAQJkweUIAAfAQAYAAQJkweUIAAfAQAXAAEJVQEyGwA+AAAuAAQKfx0AAxgACAm1IeEQAPMCABgACAm1IeEQAPMCABcAAgkTEkZSAHcAAAAA.Karva:BAABLgAECn8cAAIgAAgJVxnPBQBAAgAgAAgJVxnPBQBAAgAAAA==.Kash:BAAALgADCgUJBQABLgAECggJMgADAHQlAA==.Kayzer:BAAALgADCgYJCAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8GAAIPAAMJtBoFDwAOAQAPAAMJtBoFDwAOAQAuAAQKfx0AAw8ACAlCHuQYAE0CAA8ACAlCHuQYAE0CACEAAQlyEvAXAEAAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAMJBgAPALQaAA==.',
Kh='Khthonious:BAABLgAECn8SAAITAAcJbR14DQAMAgATAAcJbR14DQAMAgAAAA==.',
Ki='Kickingdonut:BAABLgAECn8qAAMSAAgJOSOoAgCuAgASAAgJOSOoAgCuAgAiAAYJFxlFNwBuAQAAAA==.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgAECgEJAQAAAA==.Kittykarma:BAAALgAECgEJAQAAAA==.',
Kl='Kloverr:BAAALgADCgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.',
Kr='Kromir:BAAALgADCgkJHQAAAA==.Kronixrage:BAAALgADCgcJDAAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krum:BAACLgAFFH8GAAIJAAMJgRJsHwD5AAAJAAMJgRJsHwD5AAAuAAQKfxsAAgkABgn+IPAqAJYBAAkABgn+IPAqAJYBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn8hAAIJAAgJIBcBKwCWAQAJAAgJIBcBKwCWAQAAAA==.Laurian:BAAALgADCgcJDgAAAA==.',
Le='Leaky:BAAALgAECgEJAgAAAA==.Leetah:BAABLgAECn8kAAIjAAgJthxZAwAQAgAjAAgJthxZAwAQAgAAAA==.Leftblank:BAAALgAECgEJAQAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgEJAgABLgAECgEJAgAIAAAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgADCgYJCwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgADCgkJDgAAAA==.Lowki:BAAALgADCgQJBAAAAA==.',
Ly='Lychi:BAAALgAECgEJAQAAAA==.Lylora:BAABLgAECn8jAAICAAgJ6CE5BgC1AgACAAgJ6CE5BgC1AgAAAA==.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAAALgAECgcJEgAAAA==.',
Ma='Madesh:BAABLgAECn8fAAITAAgJuRu1EQDgAQATAAgJuRu1EQDgAQAAAA==.Madman:BAAALgAECgYJDAAAAA==.Maelle:BAABLgAECn8dAAIJAAgJSiHRDQBUAgAJAAgJSiHRDQBUAgAAAA==.Magekaestey:BAAALgAECgcJDwAAAA==.Majandra:BAAALgAECgMJAwAAAA==.Malyndra:BAABLgAECn8UAAIOAAYJVhnzDwA+AQAOAAYJVhnzDwA+AQAAAA==.Marle:BAAALgAECgEJAwAAAA==.Marvolt:BAAALgADCgkJCQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgcJEAAIAAAAAA==.Merlot:BAAALgADCgEJAgABLgAECgEJAwAIAAAAAA==.Mesmash:BAAALgAECgYJEQAAAA==.Metahunt:BAAALgAECgEJAQABLgAECgcJFwASAJ0ZAA==.Metamasters:BAAALgAECgQJBAABLgAECgcJFwASAJ0ZAA==.',
Mi='Mialtaa:BAAALgAECgYJEAAAAA==.Milkurs:BAAALgAECgEJAQAAAA==.Miniborg:BAAALgAECgYJCwAAAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgADCgcJCgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAAALgAECgYJDAAAAA==.Monkter:BAABLgAECn8XAAQSAAcJnRkRCgDVAQASAAcJnRkRCgDVAQAiAAEJagjjVwAmAAARAAEJ/gbbbgAmAAAAAA==.Moofasaha:BAAALgAECgYJCgAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgADCgYJBgABLgAECggJEgATAG0dAA==.Morog:BAABLgAECn8lAAQQAAgJdx2mKwDNAQAQAAYJjh2mKwDNAQAEAAYJFxqmPwCwAQAfAAUJ4BJcFgAQAQAAAA==.Morragan:BAAALgADCgcJDgAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECgYJDAAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECgcJFwASAJ0ZAA==.Myrddinwyllt:BAAALgAECgIJAgAAAA==.',
Na='Nabû:BAAALgADCggJCgAAAA==.Naema:BAAALgAECgcJDQAAAA==.Nalid:BAABLgAECn8yAAIDAAgJdCWPAQBTAwADAAgJdCWPAQBTAwAAAA==.Nanarus:BAABLgAECn8iAAINAAgJvRsYBgBZAgANAAgJvRsYBgBZAgAAAA==.Nashalie:BAABLgAECn8cAAIYAAgJrhryEAAeAgAYAAgJrhryEAAeAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Nefele:BAAALgAECgYJEgAAAA==.Nepheli:BAABLgAECn8fAAITAAgJrx5WHgB9AQATAAgJrx5WHgB9AQAAAA==.Newrhu:BAAALgADCgIJAgAAAA==.Nexbasia:BAABLgAECn8cAAMDAAgJ4giBCABoAQADAAgJ4giBCABoAQACAAEJbwPQ5QAgAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8cAAQXAAcJuSC8CAA1AgAXAAcJuSC8CAA1AgAYAAIJuA6igQB4AAAkAAEJqheKDgBLAAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgEJAQAAAA==.Nikash:BAAALgAECgYJEQAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgEJAgAAAA==.Nommei:BAAALgAECgYJEgAAAA==.',
Ny='Nyriah:BAAALgAECgQJBAAAAA==.',
Ob='Obm:BAAALgAECgEJAQAAAA==.',
Oc='Octt:BAABLgAECn8XAAIYAAgJVBpJFwDsAQAYAAgJVBpJFwDsAQAAAA==.',
Of='Offal:BAAALgAECgYJEwAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgADCgkJEQAAAA==.',
Om='Ominis:BAAALgADCgcJGQAAAA==.',
Or='Orcal:BAACLgAFFH8OAAIcAAQJ0gvUDwAyAQAcAAQJ0gvUDwAyAQAuAAQKfx0AAhwACAn7GnUQAHICABwACAn7GnUQAHICAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgIJBAAAAA==.',
Oz='Ozo:BAAALgAECgQJCAAAAA==.',
Pa='Paiva:BAAALgAECgEJAQAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn8hAAIKAAgJmiC2AwDZAgAKAAgJmiC2AwDZAgAAAA==.Pampas:BAAALgAECgYJCgAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBQAAAA==.',
Ph='Phenixy:BAAALgAECgEJAQAAAA==.Phoebell:BAAALgAECgEJAgAAAA==.',
Pi='Pinkducky:BAAALgAECgQJEwAAAA==.',
Pl='Platinumsoul:BAAALgADCgMJAwAAAA==.Plen:BAABLgAECn8eAAIFAAgJUx1aNQBhAgAFAAgJUx1aNQBhAgAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgADCgYJAgAAAA==.Poquads:BAAALgADCgkJGAAAAA==.',
Pr='Primaris:BAAALgAECgEJAQAAAA==.Príestatute:BAAALgADCggJCAABLgAECgYJGQAEAK8bAA==.',
Pu='Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECggJIwALAEEOAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qu='Quasar:BAABLgAECn8dAAIlAAgJQRhEIgDhAQAlAAgJQRhEIgDhAQAAAA==.',
Ra='Radra:BAAALgADCgIJAwAAAA==.Raeku:BAABLgAECn8hAAIfAAgJLyH2AgADAwAfAAgJLyH2AgADAwAAAA==.Raja:BAAALgAECgIJBQAAAA==.Rathalo:BAAALgAECgEJAQAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.',
Re='Reducto:BAAALgAECgUJEAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAAALgAECgYJEwAAAA==.Retribution:BAABLgAECn8dAAIJAAYJKA1lUQAZAQAJAAYJKA1lUQAZAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Ro='Robomurph:BAAALgADCggJCgAAAA==.Ronfax:BAACLgAFFH8QAAMBAAUJdiMXAQAUAgABAAUJdiMXAQAUAgAPAAEJ6QOEIABAAAAuAAQKfxUAAwEACQkXIg0GABEDAAEACQkXIg0GABEDAA8AAQl1F6uGADMAAAAA.Rooss:BAAALgAECgQJBwAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgYJDAAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECgcJFwASAJ0ZAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.',
Ry='Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Saint:BAAALgAECgUJBQAAAA==.Samson:BAAALgAECgIJAwABLgAECgEJAQAIAAAAAA==.Sanivan:BAABLgAECn8VAAIOAAcJ+hdrGgDvAQAOAAcJ+hdrGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAAALgAECgcJEwABLgAECgkJIQAFAMceAA==.Sarinae:BAAALgAECgYJDQAAAA==.Sarmuc:BAAALgAECgcJCwAAAA==.Saryda:BAAALgAECgEJAwAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECgIJAgABLgAECggJHgAFAFMdAA==.Scubagal:BAAALgAECgEJAgAAAA==.Scy:BAAALgADCgcJCgAAAA==.',
Se='Sedaleice:BAAALgAECgEJAQAAAA==.Seedsprayer:BAAALgAECgQJBQAAAA==.Sellenah:BAAALgAECgUJDwAAAA==.Sensu:BAAALgAECgIJAgAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJBwAAAA==.Seä:BAABLgAECn8jAAILAAgJQQ7VFQCjAQALAAgJQQ7VFQCjAQAAAA==.',
Sh='Shadoweave:BAAALgAECggJCAAAAA==.Shamtea:BAAALgAECgUJDQAAAA==.Shapzan:BAAALgAECgIJAwAAAA==.Sharks:BAAALgAECgQJBwAAAA==.Shivant:BAAALgAECgUJCwAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAAALgAECgcJEgAAAA==.',
Si='Sindice:BAAALgAECgYJBwABLgAFFAUJEAABAHYjAA==.',
Sk='Skaa:BAAALgAECgEJAQAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slimpooshady:BAAALgAECgMJAwAAAA==.',
So='Solaspirus:BAABLgAECn8TAAMTAAYJmRfLKABDAQATAAYJmRfLKABDAQAgAAEJOAzwFwA3AAAAAA==.Solinius:BAAALgAECgEJAQAAAA==.Sope:BAAALgAECgYJBwAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.',
Sp='Spectors:BAAALgAECgcJCgAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAAALgAECggJDwAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwAIAAAAAA==.',
St='Stabon:BAAALgAECgYJEQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgMJAgAAAA==.',
Sw='Sweetstorm:BAAALgAECgYJEwAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn8XAAILAAcJnRBeIQA7AQALAAcJnRBeIQA7AQAAAA==.',
Ta='Tania:BAAALgADCgIJAwAAAA==.Tarixx:BAABLgAFFH8GAAMJAAMJBA9ZJACjAAAJAAIJQg5ZJACjAAAKAAEJhxDbCAA6AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBJ1HQDqAAAEAAMJ0A91HQDqAAAfAAIJJw4VDwCqAAAQAAEJTAqrJgBPAAAuAAQKfxoAAx8ACAmvGfkEAC8CAB8ACAmAGPkEAC8CABAABglBGncwALABAAAA.',
Te='Teasa:BAABLgAECn8WAAIEAAYJFBTeOwAjAQAEAAYJFBTeOwAjAQAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdEAgB7AQAEAAUJwwdEAgB7AQAfAAEJgwFQFgA8AAAQAAEJVgAKLgA1AAAuAAQKfycABB8ACAlgIooEADsCAAQACAmZH6UVAIoCAB8ACAlwGYoEADsCABAABwm3EZI5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAAALgAECgMJAwAAAA==.Thianna:BAAALgAECgYJEgAAAA==.Thiculuskage:BAAALgAECgYJCAAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgQJBgAAAA==.Thornscale:BAABLgAECn8hAAQcAAgJzhuVCgDgAQAcAAgJyhqVCgDgAQAmAAYJogvoKAAsAQAdAAEJHxjfEABKAAAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBgABLgAECgYJGQAEAK8bAA==.Timeforloads:BAAALgAECgYJEgAAAA==.',
To='Tolk:BAAALgAECgYJDQAAAA==.Tomzombe:BAAALgADCgkJCwAAAA==.Totem:BAAALgAECgUJDQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Troloq:BAABLgAECn8dAAMYAAgJSRxtHgC+AQAYAAcJ6BltHgC+AQAXAAIJXhgyRQChAAAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgADCgcJEQAAAA==.',
Ul='Uller:BAABLgAECn8UAAIlAAYJYxvqVgAxAQAlAAYJYxvqVgAxAQAAAA==.',
Um='Umbrafang:BAAALgAECgEJAwAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgAECgQJBAAAAA==.Vaimei:BAABLgAECn8kAAMXAAgJJiJ0AAC+AgAXAAgJJiJ0AAC+AgAYAAQJDR3FngAbAQAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Vapor:BAAALgAECgYJDwAAAA==.Varanius:BAAALgAECgEJAQAAAA==.',
Ve='Veebs:BAAALgAECgUJBQAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8UAAIlAAgJMwWkXwAdAQAlAAgJMwWkXwAdAQAAAA==.Vento:BAAALgAECgYJCQAAAA==.Verité:BAAALgAECgYJCwAAAA==.Veterpeinss:BAAALgADCggJCgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgADCgcJBwABLgAECgcJHwAKALMhAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn8bAAITAAgJwRCBMQAdAQATAAgJwRCBMQAdAQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgADCgkJCQAAAA==.Voidstar:BAAALgAECgQJBAAAAA==.',
Vv='Vvicked:BAAALgAECgYJDQAAAA==.',
Vy='Vynesta:BAAALgAECggJDwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wankz:BAAALgAECgYJCwAAAA==.Warriorguyes:BAAALgAECgYJDwAAAA==.',
We='Weyna:BAABLgAECn8YAAMRAAYJIA1VHwAFAQARAAYJIA1VHwAFAQAiAAUJsQrVKgDAAAABLgAFFAMJBgAmAN8QAA==.',
Wh='Whisperingei:BAAALgAECgQJBgAAAA==.',
Wi='Widowx:BAABLgAECn8eAAIPAAcJwBf6EQCPAQAPAAcJwBf6EQCPAQAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAAALgAECgQJBAAAAA==.',
Wr='Wrandohunt:BAAALgAECgEJAgAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wryn:BAAALgAECgYJDgABLgAECggJHgAFAFMdAA==.',
Wu='Wulyn:BAAALgAECgIJAgAAAA==.',
Wy='Wylla:BAAALgAECgEJAwAAAA==.',
Xa='Xalethra:BAABLgAECn8gAAITAAcJbyNUCgA2AgATAAcJbyNUCgA2AgAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgQJBwAAAA==.',
Xh='Xhosen:BAAALgAECgQJCwAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn8dAAICAAgJJhiIEgD2AQACAAgJJhiIEgD2AQAAAA==.',
Yv='Yve:BAAALgAECgQJBwAAAA==.',
Za='Zalajin:BAAALgADCggJCAAAAA==.Zalila:BAAALgADCgQJBAAAAA==.Zarayndia:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicus:BAABLgAECn8VAAMkAAYJ7gUEBwD0AAAkAAYJrwQEBwD0AAAYAAQJXwTKiABqAAAAAA==.Zendragan:BAABLgAECn8WAAIRAAYJ5hsWEQCZAQARAAYJ5hsWEQCZAQAAAA==.Zerhas:BAAALgAECgEJAgAAAA==.',
Zo='Zoidz:BAAALgAECgMJBAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgMJBgAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.',
Zz='Zzilladinzz:BAACLgAFFH8KAAIJAAMJGx2NGQASAQAJAAMJGx2NGQASAQAuAAQKfxsAAgkACAlWIwsSAAIDAAkACAlWIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgADCgMJAwABLgAECgcJEgAIAAAAAA==.',
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

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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Druid-Balance','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Shaman-Elemental','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Warrior-Fury','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Monk-Brewmaster','Druid-Guardian','Hunter-Survival','Mage-Frost','Evoker-Preservation',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarmorr:BAABLgAECn8VAAIBAAcJfQ4bDwBPAQABAAcJfQ4bDwBPAQAAAA==.',
Ae='Aeloriá:BAABLgAECn8cAAMCAAgJVhznAwBYAgACAAgJVhznAwBYAgADAAEJFQGVOwAPAAAAAA==.Aelyra:BAAALgAECgUJBQAAAA==.',
Ai='Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8UAAIEAAgJCBixIABBAgAEAAgJCBixIABBAgAAAA==.Aldera:BAAALgAECgYJDAAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8UAAMFAAgJSBS6TwADAgAFAAgJSBS6TwADAgAGAAEJyhBYFgA3AAAAAA==.Allykat:BAABLgAECn8WAAICAAcJYAr1awAQAQACAAcJYAr1awAQAQAAAA==.Alorris:BAAALgADCgcJBwABLgAECgYJDwAHAAAAAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgYJCAAAAA==.',
Am='Amata:BAAALgADCggJEwAAAA==.Ammastary:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgYJEAAHAAAAAA==.Andragos:BAAALgADCggJCAAAAA==.Andrea:BAABLgAECn8UAAIDAAcJwxKaBABPAQADAAcJwxKaBABPAQAAAA==.Anthria:BAAALgAECgUJCQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arilyn:BAAALgADCgUJCgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asyllaa:BAAALgAECgUJBwAAAA==.',
At='Atonement:BAAALgAECgIJBAABLgAECgYJEAAHAAAAAA==.',
Au='Auralynn:BAAALgAECgYJEgAAAA==.',
Av='Averus:BAABLgAECn8VAAIIAAcJYQp7DQAZAQAIAAcJYQp7DQAZAQAAAA==.',
Az='Azariel:BAABLgAECn8YAAIJAAgJbxP2RQASAgAJAAgJbxP2RQASAgAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8VAAIKAAcJ/xYQDwDTAQAKAAcJ/xYQDwDTAQAAAA==.',
Ba='Baane:BAAALgADCggJEgAAAA==.Babnik:BAEALgAECgUJDQAAAA==.Bagel:BAABLgAECn8WAAILAAYJyCFNJgD2AQALAAYJyCFNJgD2AQAAAA==.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn8VAAMMAAcJXxXrBQCmAQAMAAcJcBTrBQCmAQANAAMJFBxnVQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAABLgAECn8eAAIJAAgJ4iJbAwB4AgAJAAgJ4iJbAwB4AgAAAA==.Berathor:BAAALgAECgIJAgAAAA==.Betsea:BAAALgAECgUJBQABLgAECggJHAALACYLAA==.',
Bi='Bidoof:BAAALgAECgQJCgAAAA==.Bigblunt:BAAALgADCgIJAgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgEJAQAAAA==.',
Bo='Boggrog:BAAALgADCggJCAABLgADCggJEwAHAAAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAAALgAECgYJDwAAAA==.Bowgobrr:BAABLgAECn8iAAMOAAgJJBU1AgC6AQAOAAgJJBU1AgC6AQAEAAIJqwx8uABSAAABLgAFFAYJDgAOABQIAA==.',
Br='Braelyne:BAAALgAECgYJDwAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Broseidon:BAAALgADCgYJBgAAAA==.',
Bu='Buffsalot:BAAALgAECgQJBQAAAA==.Burlycheeks:BAABLgAECn8mAAIJAAkJuh6/AwBsAgAJAAkJuh6/AwBsAgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgADCgEJAQAAAA==.Castle:BAAALgAECgEJAQAAAA==.Catsneverdie:BAAALgAECgMJCAABLgAECggJJgAFADkUAA==.Catzinhatz:BAAALgAECgcJCwABLgAECggJJgAFADkUAA==.',
Ce='Celibate:BAAALgAECgQJBAAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIPAAYJNBCoRQAyAQAPAAYJNBCoRQAyAQABLgAECggJCAAHAAAAAA==.Chivactdl:BAAALgADCgEJAQABLgAECgUJBwAHAAAAAA==.Chozen:BAAALgAECgYJBgAAAA==.Chunknoriss:BAAALgAECgIJAgABLgAECgUJBwAHAAAAAA==.',
Cl='Claudiuss:BAAALgAECgQJBAABLgAECggJIwABAGYXAA==.Clurefu:BAAALgAECggJEwAAAA==.Clurelock:BAAALgADCgkJEAABLgAECggJEwAHAAAAAA==.Cluremage:BAAALgAECgYJBgAAAA==.',
Co='Codenameknd:BAAALgADCgEJAwAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECgYJDAAAAA==.Constella:BAAALgADCgQJBAAAAA==.Coppertan:BAAALgADCgYJCQAAAA==.Corrosion:BAAALgAECgYJEQAAAA==.',
Cr='Crazyshammy:BAAALgAECgYJCgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJBgAAAA==.Crunchynuget:BAAALgAECgIJAwABLgAECggJFQAJAH4dAA==.',
Ct='Cthuwu:BAAALgADCgcJBwABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAQAAAA==.',
Cy='Cybeast:BAABLgAECn8VAAIDAAgJlBoYBgCdAgADAAgJlBoYBgCdAgAAAA==.',
Da='Daciana:BAAALgAECgEJAQAAAA==.Dados:BAABLgAECn8cAAINAAgJMB2NEgBMAgANAAgJMB2NEgBMAgAAAA==.Dahleigh:BAAALgADCgQJBQAAAA==.Dakanar:BAAALgADCgkJGAAAAA==.Dambrien:BAAALgADCggJEgAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8VAAIJAAcJsh76SwD/AQAJAAcJsh76SwD/AQAAAA==.Darloct:BAAALgADCgkJHwAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAAALgAECgcJEQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECgcJEQAHAAAAAA==.Deadslinger:BAAALgADCgEJAQAAAA==.Deathcat:BAABLgAECn8mAAIFAAgJORQcUwD4AQAFAAgJORQcUwD4AQAAAA==.Deathkiss:BAAALgAECgMJAwAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAAALgAFFAIJAgAAAA==.Deathshadowx:BAAALgADCggJFAAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgQJBgAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAAALgAECgYJCQAAAA==.',
Do='Dolemite:BAAALgAECgUJEQAAAA==.Donalbain:BAABLgAECn8jAAIBAAgJZheCBAAnAgABAAgJZheCBAAnAgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgADCgUJBQAAAA==.',
Du='Durock:BAAALgAECgEJAQAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
El='Eldinn:BAAALgADCgcJBgAAAA==.Elidor:BAAALgAECgEJAQAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8cAAIQAAgJnxVvBQBhAQAQAAgJnxVvBQBhAQAAAA==.Elzulkin:BAAALgADCgUJBQAAAA==.',
Em='Emmils:BAABLgAECn8eAAIIAAgJhQW7DgAHAQAIAAgJhQW7DgAHAQAAAA==.Emìly:BAABLgAECn8UAAMRAAcJHB6PBQCYAQARAAUJ1ByPBQCYAQASAAMJ8QsNGQBmAAAAAA==.',
En='Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn8VAAQJAAcJ2R+XNABQAgAJAAcJiByXNABQAgAKAAIJoCLFKgC2AAALAAIJuQrJhgBeAAAAAA==.',
Ep='Episkey:BAAALgAECgYJEgAAAA==.',
Er='Ereviss:BAAALgADCgcJBwAAAA==.Erindaglaze:BAAALgADCgQJBQAAAA==.Eropor:BAAALgAECgMJBgABLgAECgcJNgACAA4dAA==.Eroversion:BAABLgAECn82AAQCAAcJDh1tJgAeAgACAAcJDh1tJgAeAgAIAAQJNRQuVADVAAADAAMJKAZ1KQB+AAAAAA==.',
Es='Esmay:BAABLgAECn8UAAIPAAcJXw+KCwBDAQAPAAcJXw+KCwBDAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn8UAAITAAcJiAgqAwBLAQATAAcJiAgqAwBLAQAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgADCgUJBwAAAA==.',
Fi='Filgulfin:BAABLgAECn8aAAIOAAgJehApAwCIAQAOAAgJehApAwCIAQAAAA==.Finkate:BAAALgADCgkJCQAAAA==.Firebad:BAABLgAECn8WAAMUAAcJrxdQEQDCAQAUAAYJVxtQEQDCAQAVAAUJKwYN1gCuAAAAAA==.Firebringer:BAABLgAECn8bAAIWAAgJhASfIgD7AAAWAAgJhASfIgD7AAAAAA==.',
Fl='Flamehunter:BAABLgAECn8aAAMWAAkJGxqBHACnAgAWAAkJ4RiBHACnAgAXAAcJLRdWJACaAQAAAA==.Flo:BAABLgAECn8dAAIYAAgJoBPhBQCsAQAYAAgJoBPhBQCsAQAAAA==.Floki:BAAALgAECgYJCgAAAA==.',
Fo='Foods:BAABLgAECn8kAAQZAAgJsg4kMQDpAQAZAAgJ3Q0kMQDpAQAaAAUJgArbMwCnAAAbAAIJwwxDMAB1AAAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
Ga='Gaboo:BAAALgAECgYJCgAAAA==.',
Gh='Ghostinhale:BAAALgAECgEJAQAAAA==.',
Gi='Gilorion:BAAALgAECgQJCAAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECggJIwABAGYXAA==.',
Gn='Gnibat:BAAALgADCgkJFQAAAA==.',
Go='Goburina:BAABLgAECn8UAAIBAAgJFwxTPQCMAQABAAgJFwxTPQCMAQAAAA==.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
['Gí']='Gímlí:BAABLgAECn8XAAIEAAYJrxt9NwDQAQAEAAYJrxt9NwDQAQAAAA==.',
Ha='Halcyndraag:BAABLgAECn8VAAMcAAcJQhFsEADoAAAcAAUJExBsEADoAAAdAAMJixWFKADcAAAAAA==.Handbannana:BAAALgADCgYJBgAAAA==.Handsome:BAAALgADCgEJAQABLgAECggJDQAHAAAAAA==.Happydk:BAABLgAECn8ZAAMFAAkJfxUvUgD7AQAFAAkJfxUvUgD7AQAQAAMJDhVwNgCOAAAAAA==.Hartu:BAABLgAECn8XAAIaAAgJPQzmBQBLAQAaAAgJPQzmBQBLAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBAAAAA==.Hemic:BAAALgAECggJEgAAAA==.Herbalmist:BAAALgADCggJEwAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Horatio:BAAALgADCgcJBwABLgAECggJIwABAGYXAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECggJIAADABEYAA==.',
Ib='Ibhuntin:BAAALgAECggJDQAAAA==.',
Id='Idiocracy:BAAALgADCggJEQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
In='Indoti:BAAALgADCgQJBgAAAA==.',
Ir='Ironmark:BAAALgADCgcJDgAAAA==.Irys:BAAALgADCgYJDQAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAABLgAECn8RAAIEAAkJSiLpBAA/AwAEAAkJSiLpBAA/AwAAAA==.Ismokeu:BAABLgAECn8aAAINAAcJRhTHCQBgAQANAAcJRhTHCQBgAQAAAA==.Ismyn:BAAALgADCgEJAgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jalidelo:BAABLgAECn8ZAAMMAAgJhRWuEwARAgAMAAgJhRWuEwARAgANAAEJ5gZOhgAqAAAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8VAAIVAAgJQBhgCADrAQAVAAgJQBhgCADrAQAAAA==.Jokers:BAAALgAECgQJBAAAAA==.Joranbragi:BAAALgADCgkJIwAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAAALgAECgYJCgAAAA==.Jotoonice:BAAALgAECgUJDQAAAA==.',
Jt='Jtoothaordan:BAABLgAECn8dAAIOAAgJ8BUFIQAbAgAOAAgJ8BUFIQAbAgAAAA==.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.',
Ka='Kaachow:BAABLgAECn8YAAICAAcJHyCKAwBlAgACAAcJHyCKAwBlAgAAAA==.Kaana:BAABLgAECn8VAAIEAAcJLRB+EQBxAQAEAAcJLRB+EQBxAQAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAAALgAECgIJAgAAAA==.Karungash:BAABLgAECn8bAAMVAAgJtSHgEADzAgAVAAgJtSHgEADzAgAUAAIJExJAUgB3AAAAAA==.Karva:BAABLgAECn8UAAIeAAgJNxjPBQBAAgAeAAgJNxjPBQBAAgAAAA==.Kash:BAAALgADCgUJBQABLgAECggJMgADAHQlAA==.Kayzer:BAAALgADCgYJBwAAAA==.',
Ke='Kelonaar:BAABLgAECn8aAAIPAAYJYSPjGABNAgAPAAYJYSPjGABNAgAAAA==.Kelya:BAAALgADCgMJAwABLgAECgYJGgAPAGEjAA==.',
Kh='Khthonious:BAAALgAECgcJDwAAAA==.',
Ki='Kickingdonut:BAABLgAECn8iAAMRAAcJwyMWCQDnAgARAAcJwyMWCQDnAgAfAAYJFxlQNwBuAQAAAA==.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgADCggJEwAAAA==.Kittykarma:BAAALgADCgcJDQAAAA==.',
Kl='Kloverr:BAAALgADCgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgADCgMJAwAAAA==.',
Kr='Kromir:BAAALgADCgkJFwAAAA==.Kronixrage:BAAALgADCgUJBQAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krum:BAABLgAECn8WAAIJAAYJ/iARSgAEAgAJAAYJ/iARSgAEAgAAAA==.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn8dAAIJAAgJcxUEDQDGAQAJAAgJcxUEDQDGAQAAAA==.Laurian:BAAALgADCgcJDgAAAA==.',
Le='Leaky:BAAALgADCgMJBQAAAA==.Leetah:BAABLgAECn8cAAIgAAgJhRswAgC5AQAgAAgJhRswAgC5AQAAAA==.Leftblank:BAAALgADCggJEwAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Livingdemon:BAAALgAECgUJCwAAAA==.',
Lm='Lminus:BAAALgAECgYJDAAAAA==.',
Lo='Lockolus:BAAALgADCgYJCwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Lowki:BAAALgADCgQJBAAAAA==.',
Ly='Lychi:BAAALgADCggJEwAAAA==.Lylora:BAABLgAECn8bAAICAAgJ6R+HAwBlAgACAAgJ6R+HAwBlAgAAAA==.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAAALgAECgcJEgAAAA==.',
Ma='Madesh:BAABLgAECn8cAAIWAAgJPRmACQDbAQAWAAgJPRmACQDbAQAAAA==.Madman:BAAALgAECgYJBgAAAA==.Maelle:BAABLgAECn8VAAIJAAcJBRvNDADIAQAJAAcJBRvNDADIAQAAAA==.Magekaestey:BAAALgAECgYJDQAAAA==.Majandra:BAAALgADCgkJFQAAAA==.Malyndra:BAAALgAECgYJEwAAAA==.Marle:BAAALgAECgEJAgAAAA==.Marvolt:BAAALgADCgkJCQAAAA==.',
Mc='Mcrae:BAAALgAECgEJAQAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Melon:BAAALgADCgEJAQABLgAECgcJBwAHAAAAAA==.Merlot:BAAALgADCgEJAgABLgAECgEJAgAHAAAAAA==.Mesmash:BAAALgAECgYJCwAAAA==.Metahunt:BAAALgAECgEJAQABLgADCgMJAwAHAAAAAA==.',
Mi='Mialtaa:BAAALgAECgYJEAAAAA==.Milkurs:BAAALgAECgEJAQAAAA==.Miniborg:BAAALgAECgUJBQABLgAECggJFQAJAH4dAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgADCgEJAwAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAAALgAECgYJCgAAAA==.Monkter:BAAALgAECgYJDwABLgADCgMJAwAHAAAAAA==.Moofasaha:BAAALgAECgYJCgAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morog:BAABLgAECn8gAAQOAAgJSxyiKwDNAQAOAAYJjh2iKwDNAQAEAAYJFxqwPwCwAQAhAAEJ6QYVFQA1AAAAAA==.Morragan:BAAALgADCgYJDQAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECgYJCgAAAA==.',
My='Myinja:BAAALgAECgMJAwABLgADCgMJAwAHAAAAAA==.Myrddinwyllt:BAAALgADCgkJDgAAAA==.',
Na='Nabû:BAAALgADCggJCgAAAA==.Naema:BAAALgAECgcJDQAAAA==.Nalid:BAABLgAECn8yAAIDAAgJdCUoAAD7AgADAAgJdCUoAAD7AgAAAA==.Nanarus:BAABLgAECn8aAAINAAgJ2xZdBQDQAQANAAgJ2xZdBQDQAQAAAA==.Nashalie:BAABLgAECn8UAAIVAAcJThqEDACzAQAVAAcJThqEDACzAQAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Nefele:BAAALgAECgYJEgAAAA==.Nepheli:BAABLgAECn8bAAIWAAgJxx2pBgANAgAWAAgJxx2pBgANAgAAAA==.Nexbasia:BAABLgAECn8UAAMDAAgJWAcIBABmAQADAAgJWAcIBABmAQACAAEJbwPN5QAgAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8WAAIUAAYJviK6CAA1AgAUAAYJviK6CAA1AgAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgADCgYJBwAAAA==.Nikash:BAAALgAECgYJEQAAAA==.',
No='Nommei:BAAALgAECgYJDAAAAA==.',
Ny='Nyriah:BAAALgAECgQJBAAAAA==.',
Ob='Obm:BAAALgADCggJEwAAAA==.',
Oc='Octt:BAAALgAECgcJDwAAAA==.',
Of='Offal:BAAALgAECgYJDwAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgADCgcJCAAAAA==.',
Om='Ominis:BAAALgADCgcJEwAAAA==.',
Or='Orcal:BAACLgAFFH8KAAIcAAQJQAn8BQAqAQAcAAQJQAn8BQAqAQAuAAQKfx0AAhwACAn7GnAQAHICABwACAn7GnAQAHICAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgEJAQAAAA==.',
Oz='Ozo:BAAALgAECgQJBgAAAA==.',
Pa='Paiva:BAAALgADCgcJCgAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn8ZAAIKAAgJbyC1AwDZAgAKAAgJbyC1AwDZAgAAAA==.Pampas:BAAALgAECgYJCgAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBAAAAA==.',
Ph='Phenixy:BAAALgADCgcJEAAAAA==.Phoebell:BAAALgAECgEJAQAAAA==.',
Pi='Pinkducky:BAAALgAECgMJDAAAAA==.',
Pl='Plen:BAABLgAECn8cAAIFAAgJ8hxYNQBhAgAFAAgJ8hxYNQBhAgAAAA==.',
Po='Ponder:BAAALgAECgQJCAAAAA==.Poquads:BAAALgADCgkJGAAAAA==.',
Pr='Primaris:BAAALgAECgEJAQAAAA==.',
Pu='Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECggJHAALACYLAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qu='Quasar:BAABLgAECn8VAAIiAAgJTRViUwA+AgAiAAgJTRViUwA+AgAAAA==.',
Ra='Radra:BAAALgADCgEJAQAAAA==.Raeku:BAABLgAECn8ZAAIhAAgJ4yD1AgADAwAhAAgJ4yD1AgADAwAAAA==.Raja:BAAALgAECgIJAwAAAA==.Rathalo:BAAALgADCgQJBAAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.',
Re='Reducto:BAAALgAECgUJBgAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAAALgAECgYJDgAAAA==.Retribution:BAABLgAECn8XAAIJAAYJKA32IgAfAQAJAAYJKA32IgAfAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Ro='Robomurph:BAAALgADCggJCgAAAA==.Ronfax:BAACLgAFFH8LAAMBAAQJiRf3BAAfAQABAAQJiRf3BAAfAQAPAAEJ6QN7IABAAAAuAAQKfxQAAwEACQkoIA4GABEDAAEACQkoIA4GABEDAA8AAQl1F5eGADMAAAAA.Rooss:BAAALgAECgQJBgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgUJCgAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwAAAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.',
Ry='Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saint:BAAALgADCgYJBgAAAA==.Samson:BAAALgAECgEJAQABLgADCggJEwAHAAAAAA==.Sanivan:BAABLgAECn8VAAIXAAcJ+hdoGgDvAQAXAAcJ+hdoGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAAALgAECgcJEwABLgAECgkJGQAFAH8VAA==.Sarinae:BAAALgAECgQJBwAAAA==.Sarmuc:BAAALgAECgUJBwAAAA==.Saryda:BAAALgAECgEJAgAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECgEJAQABLgAECggJHAAFAPIcAA==.Scubagal:BAAALgAECgEJAQAAAA==.Scy:BAAALgADCgcJCAAAAA==.',
Se='Sedaleice:BAAALgADCgcJFgAAAA==.Seedsprayer:BAAALgADCgQJBAAAAA==.Sellenah:BAAALgAECgUJCgAAAA==.Sensu:BAAALgADCggJCgAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgMJAwABLgAECggJIwAJAIgdAA==.Seä:BAABLgAECn8cAAILAAgJJgv4VAAnAQALAAgJJgv4VAAnAQAAAA==.',
Sh='Shamtea:BAAALgAECgUJCQAAAA==.Shapzan:BAAALgAECgEJAQAAAA==.Sharks:BAAALgAECgQJBgAAAA==.Shivant:BAAALgAECgUJBwAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAAALgAECgYJEAAAAA==.',
Si='Sindice:BAAALgAECgYJBwABLgAFFAQJCwABAIkXAA==.',
Sk='Skaa:BAAALgAECgEJAQAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slimpooshady:BAAALgADCgcJDQAAAA==.',
So='Solaspirus:BAAALgAECgYJDwAAAA==.Solinius:BAAALgAECgEJAQAAAA==.Sope:BAAALgAECgUJBQAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.',
Sp='Spectors:BAAALgAECgMJAwAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAAALgAECgYJCQAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJBwABLgAECgQJDwAHAAAAAA==.',
St='Stabon:BAAALgAECgYJCwAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgADCgMJBAAAAA==.',
Sw='Sweetstorm:BAAALgAECgYJDQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn8UAAILAAcJDhBjRgBeAQALAAcJDhBjRgBeAQAAAA==.',
Ta='Tania:BAAALgADCgEJAgAAAA==.Tarixx:BAAALgAFFAIJBAAAAA==.Tazanoth:BAACLgAFFH8GAAMEAAMJBBI9CQDzAAAEAAMJ0A89CQDzAAAOAAEJTAqnJgBPAAAuAAQKfxQAAyEACAncFNACAOQBACEACAlDD9ACAOQBAA4ABglBGnIwALABAAAA.',
Te='Teasa:BAAALgAECgYJEAAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdEAgB7AQAEAAUJwwdEAgB7AQAhAAEJgwE1CAA/AAAOAAEJVgAHLgA1AAAuAAQKfx8ABAQACAmZH6UVAIoCAAQACAmZH6UVAIoCAA4ABwm3EY85AHoBACEAAQlMBOsUADgAAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAAALgAECgMJAwAAAA==.Thianna:BAAALgAECgYJEgAAAA==.Thiculuskage:BAAALgAECgUJBQAAAA==.Thinkso:BAAALgADCgcJEgAAAA==.Thobu:BAAALgAECgQJBgAAAA==.Thornscale:BAABLgAECn8ZAAMcAAgJKBRmFwAZAgAcAAgJKBRmFwAZAgAjAAYJogvqKAAsAQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBQABLgAECgYJFwAEAK8bAA==.Timeforloads:BAAALgAECgYJEQAAAA==.',
To='Tolk:BAAALgAECgYJDAAAAA==.Tomzombe:BAAALgADCgEJAgAAAA==.Totem:BAAALgAECgUJDQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Troloq:BAABLgAECn8VAAMVAAgJoxunOwAeAgAVAAcJmhmnOwAeAgAUAAIJ/RUwRQChAAAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgADCgYJEAAAAA==.',
Ul='Uller:BAAALgAECgYJDgAAAA==.',
Um='Umbrafang:BAAALgAECgEJAwAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgADCggJIgAAAA==.Vaimei:BAABLgAECn8cAAMUAAgJZR9EAAB5AgAUAAgJYh9EAAB5AgAVAAQJDR23ngAbAQAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Vapor:BAAALgAECgUJCgAAAA==.',
Ve='Veebs:BAAALgAECgUJBQAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAAALgAECgkJEQAAAA==.Vento:BAAALgAECgYJCQAAAA==.Verité:BAAALgAECgQJBgAAAA==.Veterpeinss:BAAALgADCggJCgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgADCgcJBwABLgAECgcJFQAJANkfAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn8XAAIWAAgJtxDfEQB0AQAWAAgJtxDfEQB0AQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Voidstar:BAAALgADCgkJIwAAAA==.',
Vv='Vvicked:BAAALgAECgQJBwAAAA==.',
Vy='Vynesta:BAAALgAECggJCAAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wankz:BAAALgAECgYJCgAAAA==.Warriorguyes:BAAALgAECgUJCQAAAA==.',
We='Weyna:BAAALgAECgYJEwABLgAECggJHgAjAGcWAA==.',
Wh='Whisperingei:BAAALgAECgQJBAAAAA==.',
Wi='Widowx:BAABLgAECn8YAAIPAAcJvRflCQBdAQAPAAcJvRflCQBdAQAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAAALgADCgUJBQABLgAECggJHQANAF0eAA==.',
Wr='Wrandohunt:BAAALgAECgEJAQAAAA==.Wrandowdemon:BAAALgADCgEJAQAAAA==.Wryn:BAAALgAECgYJDgABLgAECggJHAAFAPIcAA==.',
Wu='Wulyn:BAAALgADCggJCgAAAA==.',
Wy='Wylla:BAAALgAECgEJAgAAAA==.',
Xa='Xalethra:BAABLgAECn8eAAIWAAYJESTbDwCHAQAWAAYJESTbDwCHAQAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xh='Xhosen:BAAALgAECgQJCwAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn8VAAICAAcJuheJDQB8AQACAAcJuheJDQB8AQAAAA==.',
Yv='Yve:BAAALgAECgQJBgAAAA==.',
Za='Zalajin:BAAALgADCggJCAAAAA==.Zalila:BAAALgADCgQJBAAAAA==.Zarayndia:BAAALgAECgEJAQAAAA==.',
Ze='Zeddicus:BAAALgAECgYJDwAAAA==.Zendragan:BAAALgAECgYJEQAAAA==.Zerhas:BAAALgAECgEJAgAAAA==.',
Zo='Zoidz:BAAALgAECgMJAwAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgEJBAAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.',
Zz='Zzilladinzz:BAACLgAFFH8GAAIJAAIJVB5MGgDPAAAJAAIJVB5MGgDPAAAuAAQKfxoAAgkACAm0IQYSAAIDAAkACAm0IQYSAAIDAAAA.',
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

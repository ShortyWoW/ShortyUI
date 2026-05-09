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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Unknown-Unknown','Monk-Brewmaster','DemonHunter-Vengeance','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Druid-Guardian','Mage-Frost','Rogue-Outlaw','Evoker-Preservation',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarmorr:BAABLgAECn8lAAIBAAgJsxIcIACyAQABAAgJsxIcIACyAQAAAA==.',
Ab='Absoul:BAAALgADCgEJAQAAAA==.',
Ac='Acinthos:BAAALgAECgIJAgAAAA==.',
Ad='Adiros:BAAALgADCgQJBAAAAA==.',
Ae='Aeloriá:BAABLgAECn8pAAMCAAgJEB1fDACFAgACAAgJEB1fDACFAgADAAEJFQGeOwAPAAAAAA==.Aelyra:BAAALgAECgUJBQAAAA==.',
Ai='Aimeeiove:BAAALgAECgMJAwAAAA==.Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8aAAIEAAkJYBivIABBAgAEAAkJYBivIABBAgAAAA==.Aldera:BAABLgAECn8WAAIBAAgJ/QJSRADxAAABAAgJ/QJSRADxAAAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8hAAMFAAkJvRxkGQAzAgAFAAkJvRxkGQAzAgAGAAEJyhBdFgA3AAAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn8oAAMCAAcJ6BN1JwCTAQACAAcJ6BN1JwCTAQAHAAEJgwZOXQArAAAAAA==.Alorris:BAAALgAECgQJBAABLgAECgYJEwAIAAAAAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgYJCQAAAA==.',
Am='Amata:BAAALgAECgQJBAAAAA==.Ammastary:BAAALgAECgQJBQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgYJFQAJAOkRAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn8kAAIDAAgJWxMYBwDKAQADAAgJWxMYBwDKAQAAAA==.Anthria:BAAALgAECgUJCQAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Archonsfury:BAAALgADCgEJAQAAAA==.Arilyn:BAAALgADCgcJEQAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJDAAAAA==.Asyllaa:BAAALgAECgcJEQAAAA==.',
At='Atnawuerus:BAAALgADCgMJAwAAAA==.Atonement:BAAALgAECgIJBAABLgAECggJGQAKAN8dAA==.',
Au='Auralynn:BAABLgAECn8aAAILAAgJ5QexXAA2AQALAAgJ5QexXAA2AQAAAA==.',
Av='Averus:BAABLgAECn8lAAIHAAgJTQowHgBEAQAHAAgJTQowHgBEAQAAAA==.',
Az='Azariel:BAABLgAECn8kAAILAAkJiRMoJQDuAQALAAkJiRMoJQDuAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8fAAIMAAgJVBZ3CADFAQAMAAgJVBZ3CADFAQAAAA==.',
Ba='Baane:BAAALgAECgQJBAABLgAECgQJBgAIAAAAAA==.Babnik:BAEALgAECgYJEwAAAA==.Bagel:BAACLgAFFH8JAAINAAMJyCDoEgAcAQANAAMJyCDoEgAcAQAuAAQKfxkAAw0ACAmCH04mAPYBAA0ACAmCH04mAPYBAAsAAQnkCtgFATUAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgEJAQAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn8lAAMOAAgJRBjqCwASAgAOAAgJdBfqCwASAgAPAAMJFBx0VQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAACLgAFFH8KAAILAAQJvxsiDwBrAQALAAQJvxsiDwBrAQAuAAQKfyUAAgsACAkUJOQMACYDAAsACAkUJOQMACYDAAAA.Berathor:BAAALgAECggJCgAAAA==.Betsea:BAAALgAECgUJBQABLgAECggJKwANAGAQAA==.',
Bi='Bidoof:BAABLgAECn8YAAIQAAcJNQV8HQDtAAAQAAcJNQV8HQDtAAAAAA==.Bigblunt:BAAALgADCgQJBgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgQJCQAAAA==.',
Bo='Boggrog:BAAALgADCggJCAABLgAECgQJBAAIAAAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8dAAIRAAgJ6wToMgDlAAARAAgJ6wToMgDlAAAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ2xVFBgC2AQASAAgJ2xVFBgC2AQAEAAYJ2gr7fgCcAAAAAA==.',
Br='Braelyne:BAABLgAECn8VAAILAAYJdR1kOACeAQALAAYJdR1kOACeAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgQJBAAAAA==.',
Bu='Buffsalot:BAAALgAECgUJCwAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn80AAILAAkJOiCpBwDWAgALAAkJOiCpBwDWAgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJBgAAAA==.Cassidyn:BAAALgADCgEJAgAAAA==.Castle:BAAALgAECgQJBwAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJBgAFAGQFAA==.Catzinhatz:BAAALgAECgcJEAABLgAFFAMJBgAFAGQFAA==.',
Ce='Cecelya:BAABLgAECn8wAAMPAAgJoRoeDQAUAgAPAAgJoRoeDQAUAgAOAAMJUw2sMACoAAAAAA==.Celibate:BAAALgAECgQJBAAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIRAAYJNBCwRQAyAQARAAYJNBCwRQAyAQABLgAECggJFQAQAKUaAA==.Chivactdl:BAAALgADCgEJAQABLgAECgUJEAAIAAAAAA==.Chozen:BAAALgAECgcJCgAAAA==.Chunknoriss:BAAALgAECgQJCgABLgAECgUJEAAIAAAAAA==.',
Cl='Claudiuss:BAAALgAECgUJBQABLgAECgkJJQABAP4XAA==.Clurefu:BAABLgAECn8hAAMTAAkJEB/xAwDsAgATAAkJEB/xAwDsAgAUAAMJ5BZNWACuAAAAAA==.Clurelock:BAAALgAECgUJCgABLgAECgkJIQATABAfAA==.Cluremage:BAAALgAECgYJBgAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECgYJDgAAAA==.Constella:BAAALgADCgUJBQAAAA==.Coppertan:BAAALgADCggJCwAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8ZAAIVAAgJ7BeTBQD1AQAVAAgJ7BeTBQD1AQAAAA==.',
Cr='Crazyshammy:BAAALgAECgYJDAAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCAAAAA==.Crunchynuget:BAAALgAECgMJBAABLgAECgYJEQAIAAAAAA==.',
Ct='Cthuwu:BAAALgADCgcJDgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAQAAAA==.',
Cy='Cybeast:BAABLgAECn8eAAIDAAgJ7xsZBgCdAgADAAgJ7xsZBgCdAgAAAA==.Cynortas:BAAALgAECgEJAQAAAA==.',
Da='Daciana:BAAALgAECgQJCAAAAA==.Dados:BAABLgAECn8qAAIPAAkJ0BuCCgA/AgAPAAkJ0BuCCgA/AgAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgADCgkJGAAAAA==.Dambrien:BAAALgAECgEJAQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8eAAILAAgJxh8EFQBRAgALAAgJxh8EFQBRAgAAAA==.Darloct:BAAALgAECgQJCAAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8WAAMQAAcJKBntJwCDAQAQAAYJexvtJwCDAQAWAAcJoQ5SSQAcAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJFgAQACgZAA==.Deadslinger:BAAALgADCgUJBgAAAA==.Deathcat:BAACLgAFFH8GAAIFAAMJZAXKSwBvAAAFAAMJZAXKSwBvAAAuAAQKfysAAgUACQm0Exs8AIoBAAUACQm0Exs8AIoBAAAA.Deathkiss:BAAALgAECgQJCAAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8KAAIFAAQJQxgkKABPAQAFAAQJQxgkKABPAQAAAA==.Deathshadowx:BAAALgAECgQJBAAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgUJBwAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgADCgIJAgABLgAECggJGQAUAGEXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8dAAIXAAgJBAuUGQBvAQAXAAgJBAuUGQBvAQAAAA==.',
Do='Dolemite:BAABLgAECn8bAAMTAAUJEg0LMQDSAAATAAUJEg0LMQDSAAAUAAQJIwZ2PgCBAAAAAA==.Donalbain:BAABLgAECn8lAAIBAAkJ/hehDQBbAgABAAkJ/hehDQBbAgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgMJAwAIAAAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgAECgQJBAAAAA==.',
Du='Durock:BAAALgAECgEJAQAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
El='Eldinn:BAAALgADCgcJBgAAAA==.Elidor:BAAALgAECgMJBQABLgAECgMJBQAIAAAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8oAAIYAAgJXxf9DgCCAQAYAAgJXxf9DgCCAQAAAA==.Elzulkin:BAAALgADCgYJCQAAAA==.',
Em='Emmils:BAABLgAECn8qAAIHAAgJ0wozHQBLAQAHAAgJ0wozHQBLAQAAAA==.Emìly:BAABLgAECn8pAAQUAAgJHiANBQCRAgAUAAgJHiANBQCRAgAJAAUJRRVRKQD+AAATAAQJpwuaPgCJAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIZAAUJbw8lAgBCAQAZAAUJbw8lAgBCAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn8lAAQMAAgJgx/HBQARAgALAAcJ0B2ONABQAgAMAAcJLB/HBQARAgANAAMJ0QrWhgBeAAAAAA==.',
Ep='Episkey:BAABLgAECn8VAAIHAAgJiQ8dGgBmAQAHAAgJiQ8dGgBmAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Eropor:BAAALgAECgMJBgABLgAECggJQgACABoeAA==.Eroversion:BAABLgAECn9CAAQCAAgJGh4uEgA8AgACAAgJGh4uEgA8AgAHAAQJNRQ1VADVAAADAAMJKAZ5KQB+AAAAAA==.',
Es='Esmay:BAABLgAECn8YAAIRAAcJoA9eJAAzAQARAAcJoA9eJAAzAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn8kAAIaAAgJ9wswBgCNAQAaAAgJ9wswBgCNAQAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgADCgUJBwAAAA==.',
Fi='Filgulfin:BAABLgAECn8qAAMEAAgJehjrGwD1AQAEAAgJeRjrGwD1AQASAAgJgBDACQBbAQAAAA==.Finkate:BAAALgADCgkJEgAAAA==.Firebad:BAABLgAECn8nAAMbAAkJeRmPAQBjAgAbAAkJeRmPAQBjAgAcAAYJHwqBkQCgAAAAAA==.Firebringer:BAABLgAECn8rAAIWAAgJlQh2RAArAQAWAAgJlQh2RAArAQAAAA==.Fistokaestey:BAAALgADCgkJCQABLgAECgcJEQAIAAAAAA==.',
Fl='Flamehunter:BAABLgAECn8iAAMWAAkJMBqAHACnAgAWAAkJbxmAHACnAgAQAAcJLRdcJACaAQAAAA==.Flo:BAABLgAECn8tAAMXAAgJKhQKEQDDAQAXAAgJKhQKEQDDAQAPAAIJKQdLQgBcAAAAAA==.Floki:BAAALgAECgYJDgAAAA==.',
Fo='Foods:BAABLgAECn80AAQdAAgJ8RbREADtAQAdAAgJmRXREADtAQAeAAcJchG9EABXAQAfAAIJwwxKMAB1AAAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
Ga='Gaboo:BAAALgAECgYJCwAAAA==.',
Gh='Ghostinhale:BAAALgAECgQJBwAAAA==.',
Gi='Gilorion:BAAALgAECgQJDQAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECgkJJQABAP4XAA==.',
Gn='Gnibat:BAAALgAECgMJAwAAAA==.',
Go='Goburina:BAABLgAECn8VAAIBAAkJVwtPPQCMAQABAAkJVwtPPQCMAQAAAA==.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgADCgcJBwAAAA==.',
['Gí']='Gímlí:BAABLgAECn8bAAIEAAgJ4Bk1JQDAAQAEAAgJ4Bk1JQDAAQAAAA==.',
Ha='Halcyndraag:BAABLgAECn8lAAMgAAgJ0hFCIwAsAQAgAAYJ4BBCIwAsAQAZAAMJthWIEAB6AAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgADCgEJAQABLgAECggJDgAIAAAAAA==.Happydk:BAABLgAECn8hAAMFAAkJxx4vCQDMAgAFAAkJxx4vCQDMAgAYAAMJDhVvNgCOAAAAAA==.Hartu:BAABLgAECn8nAAIeAAgJxA93DwBrAQAeAAgJxA93DwBrAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAABLgAECn8hAAIhAAgJFyFeBQBmAgAhAAgJFyFeBQBmAgAAAA==.Hemmorage:BAAALgAECgQJBAABLgAECggJHwAFAFQdAA==.Herbalmist:BAAALgAECgQJBAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Horatio:BAAALgADCgcJBwABLgAECgkJJQABAP4XAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECggJDgAIAAAAAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Id='Idiocracy:BAAALgADCggJEQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgIJAwAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgQJBAAAAA==.Irys:BAAALgADCgcJDgAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8HAAIEAAUJIx7JCwBrAQAEAAUJIx7JCwBrAQAuAAQKfxQAAgQACQlKIuUEAD8DAAQACQlKIuUEAD8DAAAA.Ismokeu:BAABLgAECn8oAAIPAAgJvhjmCwAoAgAPAAgJvhjmCwAoAgAAAA==.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAAALgAECgYJBgAAAA==.Jalidelo:BAABLgAECn8nAAMOAAkJqBWiCABSAgAOAAkJqBWiCABSAgAPAAEJ5gZdhgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8dAAIcAAgJtxqiFwAlAgAcAAgJtxqiFwAlAgAAAA==.Jokers:BAAALgAECgYJCwAAAA==.Joranbragi:BAAALgAECgQJCAAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8YAAIiAAYJsRCBDgBJAQAiAAYJsRCBDgBJAQAAAA==.Jotoonice:BAAALgAECgYJEAAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8HAAQjAAQJpg8kCgA6AQAjAAQJGw0kCgA6AQAEAAEJeg5ETQBRAAASAAEJrQFnLQA8AAAuAAQKfyEABBIACAnFGqUgACACABIACAnwFaUgACACACMAAgkkHrkoALIAAAQAAQlUJUuTAGkAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.',
['Jú']='Júgg:BAAALgAECgIJAgAAAA==.',
Ka='Kaachow:BAABLgAECn8hAAICAAgJkiDhBwDNAgACAAgJkiDhBwDNAgAAAA==.Kaana:BAABLgAECn8kAAIEAAgJ6BAtKACxAQAEAAgJ6BAtKACxAQAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAAALgAECgUJCQAAAA==.Karungash:BAACLgAFFH8IAAMcAAQJkweUMwACAQAcAAQJkweUMwACAQAbAAEJVQE3GwA+AAAuAAQKfx0AAxwACAm1Id8QAPMCABwACAm1Id8QAPMCABsAAgkTEkZSAHcAAAAA.Karva:BAABLgAECn8iAAIKAAkJBBn+AgA0AgAKAAkJBBn+AgA0AgAAAA==.Karvy:BAAALgADCggJCAABLgAECgkJIgAKAAQZAA==.Kash:BAAALgADCgUJBQABLgAFFAMJBgADAL0gAA==.Kayzer:BAAALgADCgYJDwAAAA==.',
Ke='Kelonaar:BAACLgAFFH8JAAIRAAMJ2BumFQACAQARAAMJ2BumFQACAQAuAAQKfyAAAxEACQkWHuIYAE0CABEACQkWHuIYAE0CABUAAQlyEkkdAEAAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAMJCQARANgbAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8SAAIWAAcJrR3GFgAGAgAWAAcJrR3GFgAGAgAAAA==.',
Ki='Kickingdonut:BAACLgAFFH8FAAIUAAMJNx+qCwAaAQAUAAMJNx+qCwAaAQAuAAQKfyoAAxQACAk5I04EAKYCABQACAk5I04EAKYCAAkABgkXGUA3AG4BAAAA.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgAECgQJBAAAAA==.Kittykarma:BAAALgAECgEJAQAAAA==.',
Kl='Kloverr:BAAALgADCgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.',
Kr='Kromir:BAAALgADCgkJHQAAAA==.Kronixrage:BAAALgAECgIJAgAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krum:BAACLgAFFH8JAAILAAMJ0hOiLgD5AAALAAMJ0hOiLgD5AAAuAAQKfx4AAgsACAmsHUgbACUCAAsACAmsHUgbACUCAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn8tAAILAAgJPRf4KADcAQALAAgJPRf4KADcAQAAAA==.Laurian:BAAALgADCgcJDgAAAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAABLgAECn8uAAMkAAgJvxxvBAAwAgAkAAgJvxxvBAAwAgADAAIJxQzLHAB2AAAAAA==.Leftblank:BAAALgAECgQJBAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgMJBQAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBgAAAA==.Lowki:BAAALgAECgEJAQAAAA==.',
Ly='Lychi:BAAALgAECgQJBAAAAA==.Lylora:BAABLgAECn8sAAICAAkJeB+pBAAVAwACAAkJeB+pBAAVAwAAAA==.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8aAAMPAAgJ/w0vHQBgAQAPAAgJ/w0vHQBgAQAXAAEJ6gInaQAmAAAAAA==.',
Ma='Madesh:BAABLgAECn8rAAMWAAgJ6xvGFAAWAgAWAAgJ6xvGFAAWAgAKAAQJjRJ6EQCsAAAAAA==.Madman:BAAALgAECgcJEwAAAA==.Maelle:BAABLgAECn8lAAILAAgJYiGiDACcAgALAAgJYiGiDACcAgAAAA==.Magekaestey:BAAALgAECgcJEQAAAA==.Majandra:BAAALgAECgQJBwAAAA==.Malyndra:BAABLgAECn8cAAIQAAgJABYvDQCuAQAQAAgJABYvDQCuAQAAAA==.Marle:BAAALgAECgEJAwAAAA==.Marvolt:BAAALgADCgkJEgAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgcJCQAIAAAAAA==.Merlot:BAAALgADCgEJAgABLgAECgQJBgAIAAAAAA==.Mesmash:BAABLgAECn8ZAAIeAAgJGhrdBgAeAgAeAAgJGhrdBgAeAgAAAA==.Metahunt:BAAALgAECgEJAQABLgAECggJGQAUAGEXAA==.Metamasters:BAAALgAECgQJBAABLgAECggJGQAUAGEXAA==.',
Mi='Mialtaa:BAABLgAECn8VAAIJAAYJ6RF4MADZAAAJAAYJ6RF4MADZAAAAAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgEJAQAAAA==.Miniborg:BAAALgAECgYJEQAAAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgIJAgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAAALgAECgYJDgAAAA==.Monkter:BAABLgAECn8ZAAQUAAgJYRc7CwAGAgAUAAgJYRc7CwAGAgAJAAEJfgiDbgAmAAATAAEJ/gbdbgAmAAAAAA==.Moofasaha:BAAALgAECgYJDAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgADCgYJBgABLgAECggJEgAWAK0dAA==.Morog:BAACLgAFFH8HAAMjAAMJfxtYDAAWAQAjAAMJfxtYDAAWAQAEAAEJ0w2JTQBRAAAuAAQKfygABBIACQmoGxssAM0BABIABgmOHRssAM0BAAQABgkXGqg/ALABACMABgnoEwMUAHgBAAAA.Morragan:BAAALgADCgcJDgAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECgYJDgAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAUAGEXAA==.Myrddinwyllt:BAAALgAECgUJBwAAAA==.',
Na='Nabû:BAAALgADCggJDgAAAA==.Naema:BAAALgAECgcJDQAAAA==.Nalid:BAACLgAFFH8GAAIDAAMJvSDJAwAlAQADAAMJvSDJAwAlAQAuAAQKfzIAAgMACAl0JQkBAPACAAMACAl0JQkBAPACAAAA.Nanarus:BAABLgAECn8qAAIPAAgJBh1aBwB+AgAPAAgJBh1aBwB+AgAAAA==.Nanosec:BAAALgADCgEJAQAAAA==.Nashalie:BAABLgAECn8fAAIcAAkJghoXDwBvAgAcAAkJghoXDwBvAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Nefele:BAABLgAECn8aAAIBAAgJ7xWuFgD9AQABAAgJ7xWuFgD9AQAAAA==.Nepheli:BAABLgAECn8mAAIWAAgJUh/ZDQBbAgAWAAgJUh/ZDQBbAgAAAA==.Newrhu:BAAALgADCgIJAgAAAA==.Nexbasia:BAABLgAECn8kAAMDAAgJjAs7CgB+AQADAAgJjAs7CgB+AQACAAEJbwPX5QAgAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8iAAQbAAcJyiEMAgA+AgAbAAcJyiEMAgA+AgAcAAIJvg4cowB1AAAiAAEJrBf9FQBBAAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgEJAQAAAA==.Nikash:BAABLgAECn8XAAMHAAYJ8gddLgDbAAAHAAYJ8gddLgDbAAACAAYJ+QiNUQDPAAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJCwAAAA==.Nommei:BAAALgAECgYJEgAAAA==.',
Ny='Nyriah:BAAALgAECgUJCgAAAA==.',
Ob='Obm:BAAALgAECgQJBAAAAA==.',
Oc='Octt:BAABLgAECn8ZAAIcAAgJMBzjHgD3AQAcAAgJMBzjHgD3AQAAAA==.',
Of='Offal:BAABLgAECn8YAAQfAAYJTQ0JGAA5AQAfAAYJCAsJGAA5AQAeAAQJoQ8NJACeAAAdAAEJJQVCbgAsAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgIJAgAAAA==.',
Om='Ominis:BAAALgADCgkJIQAAAA==.',
Or='Orcal:BAACLgAFFH8TAAIgAAUJqg4cFgAvAQAgAAUJqg4cFgAvAQAuAAQKfx0AAiAACAn7Gm8QAHICACAACAn7Gm8QAHICAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgQJCgAAAA==.',
Oz='Ozo:BAAALgAECgYJEAAAAA==.',
Pa='Paiva:BAAALgAECgQJBAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn8nAAIMAAkJViADAgCoAgAMAAkJViADAgCoAgAAAA==.Pampas:BAAALgAECgYJDgAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgQJBAAAAA==.Phoebell:BAAALgAECgMJBQAAAA==.',
Pi='Pinkducky:BAABLgAECn8ZAAIFAAQJTQeTqACPAAAFAAQJTQeTqACPAAAAAA==.',
Pl='Platinumsoul:BAAALgADCgIJAgAAAA==.Plen:BAABLgAECn8fAAIFAAgJVB1WNQBhAgAFAAgJVB1WNQBhAgAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgADCgYJAgAAAA==.Poquads:BAAALgADCgkJGAAAAA==.',
Pr='Primaris:BAAALgAECgEJAQAAAA==.Príestatute:BAAALgADCggJCAABLgAECggJGwAEAOAZAA==.',
Pu='Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECggJKwANAGAQAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qu='Quasar:BAABLgAECn8jAAIlAAkJlhinGABXAgAlAAkJlhinGABXAgAAAA==.',
Ra='Radra:BAAALgADCgQJBQAAAA==.Raeku:BAABLgAECn8hAAIjAAgJLyH2AgADAwAjAAgJLyH2AgADAwAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDQAAAA==.Rathalo:BAAALgAECgEJAQAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgQJBAAAAA==.',
Re='Reducto:BAAALgAECgYJEgAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8aAAMBAAYJ4QPgTQDHAAABAAYJ4QPgTQDHAAARAAUJRANYRwCKAAAAAA==.Retribution:BAABLgAECn8fAAILAAcJeAxVVgBGAQALAAcJeAxVVgBGAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Ro='Robomurph:BAAALgADCggJDgAAAA==.Ronfax:BAACLgAFFH8VAAMBAAUJsiVhAQAtAgABAAUJsiVhAQAtAgARAAEJ6QOIIABAAAAuAAQKfxUAAwEACQkXIg4GABEDAAEACQkXIg4GABEDABEAAQl1F6eGADMAAAAA.Rooss:BAAALgAECgUJCwAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgYJDQAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAUAGEXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.',
Ry='Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Saint:BAAALgAECgUJBQAAAA==.Samson:BAAALgAECgQJBwABLgAECgQJBAAIAAAAAA==.Sanivan:BAABLgAECn8VAAIQAAcJ+hduGgDvAQAQAAcJ+hduGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAABLgAECn8XAAQaAAcJdR9BCQCuAQAaAAYJAx5BCQCuAQAhAAQJrxwtOwA/AQAmAAQJ8BLbCQDFAAABLgAECgkJIQAFAMceAA==.Sarinae:BAABLgAECn8UAAMgAAcJfANCNQDNAAAgAAcJfANCNQDNAAAZAAEJwAEQGwAXAAAAAA==.Sarmuc:BAABLgAECn8UAAMVAAgJiA6ODQAtAQAVAAgJiA6ODQAtAQARAAEJXwsuZwAvAAAAAA==.Saryda:BAAALgAECgQJBgAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJCgABLgAECggJHwAFAFQdAA==.Scubagal:BAAALgAECgMJBQAAAA==.Scy:BAAALgADCgcJCgAAAA==.Scythraza:BAAALgAECgQJBgAAAA==.',
Se='Sedaleice:BAAALgAECgEJAQAAAA==.Seedsprayer:BAAALgAECgUJBgAAAA==.Sellenah:BAAALgAECgYJEwAAAA==.Sensu:BAAALgAECgQJBgAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJCAABLgAFFAMJCAALAEUiAA==.Seä:BAABLgAECn8rAAINAAgJYBAsGwCwAQANAAgJYBAsGwCwAQAAAA==.',
Sh='Shadoweave:BAAALgAECggJDgAAAA==.Shamtea:BAAALgAECgUJEgAAAA==.Shapzan:BAAALgAECgQJBwAAAA==.Sharks:BAAALgAECgQJCwAAAA==.Shivant:BAAALgAECgUJEAAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8ZAAIKAAgJ3x1pAwAZAgAKAAgJ3x1pAwAZAgAAAA==.',
Si='Sindice:BAAALgAECgYJBwABLgAFFAUJFQABALIlAA==.',
Sk='Skaa:BAAALgAECgEJAQAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slimpooshady:BAAALgAECgYJCQAAAA==.',
So='Solaspirus:BAABLgAECn8aAAMWAAgJwhZjHQDZAQAWAAgJwhZjHQDZAQAKAAEJaww9HwAwAAAAAA==.Solinius:BAAALgAECgEJAQAAAA==.Sope:BAAALgAECgYJBwAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.',
Sp='Spectors:BAAALgAECgcJCgAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAAALgAECggJEQAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwAIAAAAAA==.',
St='Stabon:BAABLgAECn8ZAAIhAAgJugiXEwB3AQAhAAgJugiXEwB3AQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgQJBgAAAA==.',
Sw='Sweetstorm:BAABLgAECn8ZAAIQAAYJNgY7IQDRAAAQAAYJNgY7IQDRAAAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn8iAAINAAcJ0BahFwDQAQANAAcJ0BahFwDQAQAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAAALgADCgIJBAAAAA==.Tarixx:BAABLgAFFH8GAAMLAAMJBA9bJACjAAALAAIJQg5bJACjAAAMAAEJhxAiDAA6AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBK9LADiAAAEAAMJ0A+9LADiAAAjAAIJJw4XFgClAAASAAEJTAq3JgBPAAAuAAQKfxoAAyMACAmvGV8IACECACMACAmAGF8IACECABIABglBGs0wALABAAAA.',
Te='Teasa:BAABLgAECn8cAAIEAAYJUBQITQAmAQAEAAYJUBQITQAmAQAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdEAgB7AQAEAAUJwwdEAgB7AQAjAAEJgwHeHgA5AAASAAEJVgAULgA1AAAuAAQKfycABAQACAlgIqMVAIoCAAQACAmZH6MVAIoCACMACAlwGfkHACkCABIABwm3Eds5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAAALgAECgMJAwAAAA==.Thianna:BAABLgAECn8aAAMNAAgJwhXHGADFAQANAAgJwhXHGADFAQALAAYJ8QqXdQABAQAAAA==.Thiculuskage:BAAALgAECgYJCAAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgUJBwAAAA==.Thornscale:BAABLgAECn8oAAQgAAkJ8hmnBgByAgAgAAkJ8hmnBgByAgAnAAYJogvnKAAsAQAZAAEJHxgaFQBHAAAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBgABLgAECggJGwAEAOAZAA==.Timeforloads:BAAALgAECgYJEwAAAA==.',
To='Tolk:BAAALgAECgYJDQAAAA==.Tomzombe:BAAALgAECgIJAgAAAA==.Totem:BAAALgAECggJEAAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Troloq:BAABLgAECn8jAAMcAAkJTBs5FwAoAgAcAAgJOBk5FwAoAgAbAAIJXhgzRQChAAAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgADCgcJEQAAAA==.',
Ul='Uller:BAABLgAECn8WAAIlAAcJIBrHVwBmAQAlAAcJIBrHVwBmAQAAAA==.',
Um='Umbrafang:BAAALgAECgEJAwAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgAECgQJCAAAAA==.Vaimei:BAABLgAECn8mAAMbAAgJySKpAADGAgAbAAgJySKpAADGAgAcAAQJDR3JngAbAQAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Vapor:BAABLgAECn8VAAIaAAYJbBNXCABRAQAaAAYJbBNXCABRAQAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAAALgAECgYJCwAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8UAAIlAAgJMwXjegAbAQAlAAgJMwXjegAbAQAAAA==.Vento:BAAALgAECggJDgAAAA==.Verité:BAAALgAECgYJCwAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgADCgcJBwABLgAECggJJQAMAIMfAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn8fAAIWAAgJ6RBlLwB5AQAWAAgJ6RBlLwB5AQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgQJCAAAAA==.',
Vv='Vvicked:BAAALgAECgYJEwAAAA==.',
Vy='Vynesta:BAABLgAECn8VAAIQAAgJpRpdBwAmAgAQAAgJpRpdBwAmAgAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wankz:BAAALgAECgYJDQAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8VAAIdAAYJuh4CGACmAQAdAAYJuh4CGACmAQAAAA==.',
We='Weyna:BAABLgAECn8gAAMTAAgJwQwpHgBWAQATAAgJwQwpHgBWAQAJAAUJtAqxOAC1AAABLgAFFAQJCgAnAD0SAA==.',
Wh='Whisperingei:BAAALgAECgQJBgAAAA==.',
Wi='Widowx:BAABLgAECn8kAAIRAAcJeBnuEwC3AQARAAcJeBnuEwC3AQAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAAALgAECgQJBAABLgAECggJHwAPAF0eAA==.',
Wr='Wrandohunt:BAAALgAECgEJAgAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wryn:BAAALgAECgYJDgABLgAECggJHwAFAFQdAA==.',
Wu='Wulyn:BAAALgAECgQJBgAAAA==.',
Wy='Wylla:BAAALgAECgQJBgAAAA==.',
Xa='Xalethra:BAABLgAECn8kAAIWAAcJbyM9EQA2AgAWAAcJbyM9EQA2AgAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgQJDQAAAA==.',
Xh='Xhosen:BAAALgAECgQJCwAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn8lAAICAAgJKhjYGwDlAQACAAgJKhjYGwDlAQAAAA==.',
Yv='Yve:BAAALgAECgQJCQAAAA==.',
Za='Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgQJBQAAAA==.',
Ze='Zeddicus:BAABLgAECn8dAAMiAAgJBQVXCQABAQAiAAcJAQVXCQABAQAcAAUJ0AMYlwCSAAAAAA==.Zendragan:BAABLgAECn8WAAITAAYJ5hvmFwCTAQATAAYJ5hvmFwCTAQAAAA==.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoidz:BAAALgAECgMJBAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.',
Zz='Zzilladinzz:BAACLgAFFH8OAAILAAQJvx6jDAB3AQALAAQJvx6jDAB3AQAuAAQKfxsAAgsACAlWIwkSAAIDAAsACAlWIwkSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgEJAQABLgAECggJGQAKAN8dAA==.',
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
